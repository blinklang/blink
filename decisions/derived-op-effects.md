[< All Decisions](../DECISIONS.md)

# Effects of a Derived Operation Body — Design Rationale

**Gap:** "Spec: may a derived op body in an effect declaration perform effects outside its own effect tree? Every spec derived-op example (Net verbs, IO.Read read_line/read_all) stays inside its own effect tree. The compiler typechecks a derived body under the declaring effect's row only; a body that performs another effect is refused until this is decided."

**Result:**

- **Q1 (6-0, A):** a derived operation body, written in the effect declaration, may perform only the leaf sub-effect it is declared in. An operation declaration has no `!` row. A body that performs any other effect is an error. This covers a built-in effect (`IO.Log`), another user effect, and a sibling sub-effect under the same root (`Greet.Loud` from a `Greet.Say` body). Reason: the body runs at the call site, and a caller that holds `! Greet.Say` holds only that child (§4.3: "Children are independent capabilities").
- **Q2 (5-1, B; Systems dissent):** the help offers two fixes, in this order: move the logic to a plain function with its own `!` row; make the operation primitive and implement it in each handler, where the clause row covers the other effect. No third line that says to pass the value as a parameter.

**Points all six seats agreed (not balloted):**

- The rule goes in §4.7.1 *Completeness and auto-delegation* as its own paragraph. It says "leaf sub-effect" and "the effect it is declared in".
- A built-in effect and a user effect are refused the same way. The compiler charges nothing to the handler or to the `with`. The clause row (§4.7) does not change: a handler that implements the operation itself may use other effects through its clause row.
- A new diagnostic code, not E0500 `UndeclaredEffect`. The writer chose `DerivedOpForeignEffect`, E0557.
- The help does not mention a `!` list, because an operation declaration has none. There is no `fix:` line; the help is prose only.
- The sibling case gets one extra help line: the sibling is a different effect and may have no handler where the declaring effect is handled.
- The open gap that builtin `io.*` calls are not checked for a row is not a precedent for the rule.

**Phase B shifts.** In Phase A, AI/ML and Minimalism read "own effect" as the whole root effect; the other four seats read it as the leaf sub-effect. After the facts in Phase B, AI/ML and Minimalism moved to the leaf (V1). PLT withdrew its "E0500 with new help" proposal and joined the new code (V2). DevOps wanted a third help line in Phase B, and changed its Q2 vote to B in Phase C. Systems kept the third help line and is the one dissent on Q2.

**Facts given to the panel** (summary): §4.7.1 says that an omitted derived operation runs its body at the call site, with the same handlers in force. §4.3 says that a parent effect grants all of its children and that children are independent capabilities. A derived body that called another user effect, or a sibling sub-effect, got `UndeclaredEffect` with the help "add the effect to the `!` list of the operation". The parser rejects a `!` row on an operation, so the user could not follow the help. A program whose function declared only `! Greet.Say` and called a derived operation that reached `Greet.Loud` installed no `Greet.Loud` handler, and the signature of the function named `Greet.Say` only.

**AI-first review:** 5/5 pass. Learnability, generability and debuggability pass: the rule is one sentence ("a derived body may use only the effect it is declared in"), the new code lets `blink explain` teach the real fix, and the help names exactly two repairs. Token efficiency passes: the rule adds no syntax. Consistency passes: the diagnostic follows the shape of the nearby `DefaultOutsideHandlerOp` entry.

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in independent-proposal → debate → vote rounds. The texts below are the panelists' own, verbatim.

#### Phase A — Independent proposals

##### Systems

> ## sys-1 (preferred): a derived body stays inside its own sub-effect. Keep the compiler rule; fix the diagnostic.
>
> **Rule.** A derived operation body may call only (a) operations of its own sub-effect (primitive or derived), (b) pure code, (c) `panic`. A call to any other effect is an error. This holds for a sibling sub-effect under the same root, a builtin effect such as `IO.Log`, and a user effect. No case is special.
>
> **Why (what the hardware sees).** The body runs at the call site, so it is inlined into the caller and monomorphized there. The caller's row for `net.get(...)` is `Net.Connect`, read from the op's effect. If the body could perform `IO.Log` as well, the true cost of `net.get` would not appear in its signature. The caller would need an effect it never wrote, and a function with no `!` could still reach I/O through a derived op. That breaks §4.1 ("the compiler proves it"). With sys-1 the cost of an op call is exactly: one dispatch to the innermost handler, or the inlined body, which calls that same handler. No hidden effect, no extra handler lookup, no extra row to check at the call site.
>
> **It also keeps the clause row sound.** §4.7 says an omitted derived op adds nothing to `R`, because its body runs at the call site. That holds only if the body adds nothing to the call site's row beyond `E`. If bodies could do `IO.Log`, `Handler[Net.Connect]` (empty `R`) would still force `IO.Log` onto the caller when the handler omits `get`. The type `Handler[E]` would lie.
>
> ```blink
> effect Greet {
>     effect Say {
>         fn word() -> Str
>         fn hello() -> Str { "hello {greet.word()}" }   // own sub-effect: ok
>     }
>     effect Loud {
>         fn shout(s: Str) -> Str
>     }
> }
> // error: hello() calling greet.shout(...) -> refused
> ```
>
> **Diagnostic.** New code text, not `UndeclaredEffect` (its help names a `!` list that cannot be written):
>
> ```
> error[E05xx]: derived operation `Greet.Say.hello` performs `Greet.Loud`
>   --> greet.bl:6:24
>    |  fn hello() -> Str { greet.shout("hi") }
>    |                      ^^^^^^^^^^^^^^^^^ outside effect `Greet.Say`
>    = note: a derived body runs at the call site; it may use only `Greet.Say`
>    = help: make `hello` a primitive operation and implement it in a handler,
>            or write a helper `fn` with `! Greet.Say, Greet.Loud`
> ```
>
> For a user or builtin effect, the same shape, with the effect name swapped. Add a test for each of the three cases.
>
> **Cross-language.** Rust trait default methods may use only the trait's own methods unless a `where` clause is added, and the clause is part of the signature. Haskell `mtl` default methods take extra constraints, which is sys-2 below. Koka operation defaults are not a feature; handlers carry the row.
>
> **Tradeoff.** A user cannot write a derived op that logs. They write a helper fn instead. That costs one fn and no runtime cost.
>
> ## sys-2 (fallback): allow an op-level row
>
> Allow `fn hello() -> Str ! IO.Log { ... }` in an effect. The row is part of the op's signature. The caller of the op pays it at every call site, whether or not the handler overrides the op. The handler's clause row counts the row when the handler implements the op itself with the same row. Zero runtime cost, because the row is erased. Cost: a parser change, a new rule for `Handler[E ! R]` fitting, and handler authors must now match rows. I oppose this for now: YAGNI, and no spec example needs it. If the panel wants it, it must be explicit in the signature; never infer the row from the body.
>
> ## Do not do
>
> Do not let the body perform other effects with the charge on the `with` site or the handler. A derived body is not a handler operation, so `R` does not apply to it, and the `with` site cannot know which ops are omitted.

##### Web/Scripting

> # web-1: a derived body stays inside its own sub-effect; fix the diagnostic, not the rule
>
> **Rule.** A derived operation body may call only (a) operations of its own sub-effect (primitives and other derived ops), and (b) pure code. Any call through another effect is an error: a sibling sub-effect, a user effect, or a builtin such as `IO.Log`. The same holds for all three cases. One rule has no per-case exceptions to teach.
>
> **Why, from the web seat.** A derived body is a default method. A JS or Kotlin dev reads `Net.get` as "sugar over `request`". Nobody expects `get` to also log, read a counter, or touch the clock. The caller of `net.get(url)` has `Net.Connect` in its `!` list and nothing else. The body runs at the call site, so a hidden `Counter.Get` would reach a caller whose signature does not show it. That breaks §4.1: "a function with no `!` cannot perform side effects." The signature is the only place a reader looks.
>
> **Allowing it fails.** The caller would pay, but the op declaration has no `!` row and the parser rejects one (probe b.bl). Adding one is new syntax with new questions for handler rows and `Handler[...]` types.
>
> **Diagnostic today is wrong.** c.bl and i.bl say `add Counter.Get to the ! list of Greet.hello`. The user cannot write that. Replace it:
>
> ```
> error[E0xxx]: derived operation `Greet.Say.hello` performs `Counter.Get`
>   --> greet.bl:9:24
>    |
>  9 |         "hello {greet.name()} {counter.get()}"
>    |                               ^^^^^^^^^^^^^ outside effect `Greet.Say`
>    = note: a derived body runs at the caller and may use only its own effect
>    = help: make `hello` a free function with `! Greet.Say, Counter.Get`
>    = help: or take the value as a parameter of `hello`
> ```
>
> For a sibling (j.bl) the help also says: `Greet.Loud` may have no handler where `Greet.Say` is handled.
>
> **Example (accepted).**
>
> ```blink
> effect Greet {
>   effect Say {
>     fn name() -> Str
>     fn hello() -> Str { "hello {greet.name()}" }
>   }
> }
>
> fn welcome() -> Str ! Greet.Say, Counter.Get {
>     "{greet.hello()} {counter.get()}"
> }
> ```
>
> The escape is a plain function. It states its row, works with `with`, and needs no new syntax. A handler that implements `hello` itself may use any effect in its clause row (§4.7); this is already specified and stays. Only the effect-declaration body is restricted.
>
> **Builtin effects.** `IO.Log` is refused too. Today a.bl and f.bl compile only because builtin `io.*` has no row check (open P1 bug). Do not take them as precedent. The spec should say so, so the P1 fix does not reopen this question.
>
> **Tradeoffs.** Pro: no syntax; one sentence in §4.7.1; matches every spec example. Con: a derived `get` cannot log; the author writes a free function. The same body in a handler clause may log, so the note must say the declaration body runs in the caller's row.
>
> **Cross-language.** Rust default methods may call only trait bounds that the trait itself declares (`where Self: Other`). A default cannot add a free dependency. Koka default op bodies have no hidden effects: the effect row is part of the op type. Haskell mtl default methods need the constraint in the class head. Each language makes the cost part of the declaration or forbids it. Blink has no op row, so it forbids.
>
> **Alternative I reject: web-2, allow `! E` on op declarations.** More power, more syntax, new handler-type questions. Revisit when a real stdlib derived op needs it.

##### PLT

> Typing question: a derived body runs at the call site. So its effects reach the caller. Under §4.1 the caller's row must show them. A derived op has no row of its own today, so the caller sees only the op's own effect (`E.Sub`). A body that performs `X` outside `E.Sub` would make `greet.hello()` perform `X` with no `X` in any signature. That is unsound against §4.1. Every rule below must close that gap.
>
> ## plt-1 (recommended): a derived body performs only its own sub-effect. Refuse the rest.
>
> Rule: the body of a derived op is checked under the row `{E.Sub}` (the op's leaf sub-effect), as the compiler does today. A call through any other effect is `UndeclaredEffect` (E0500). This holds for a sibling sub-effect, a user effect, and a builtin effect such as `IO.Log`. No exception for builtins: when the open P1 (row enforcement for `io.*`) lands, `io.log` in a derived body gets the same error. A sibling under the same root is not special: a caller that holds `! Greet.Say` does not hold `Greet.Loud`.
>
> ```blink
> effect Greet {
>     effect Say {
>         fn say(msg: Str) -> Str
>         fn hello() -> Str { say("hello") }   // ok: own effect only
>     }
>     effect Loud {
>         fn shout(msg: Str) -> Str
>     }
> }
> ```
>
> A body that needs more than its own effect is not a derived op. Write a plain fn with an honest row:
>
> ```blink
> fn hello_loud() -> Str ! Greet.Say, Greet.Loud { greet.shout(greet.hello()) }
> ```
>
> Diagnostic fix (the real defect). The help must not tell the user to edit a `!` list that cannot be written:
>
> ```
> error[E0500]: derived operation `Greet.Say.hello` performs `Counter.Get`
>   = note: a derived operation may use only its own effect `Greet.Say`
>   = help: move the body to a function with `! Greet.Say, Counter.Get`, and leave `hello` primitive
> ```
>
> Tradeoffs: sound; no new syntax; no new case in the clause row (an omitted derived op adds nothing, as §4.7 says now). Cost: a derived op cannot log or read config. Only a plain fn can. That matches the Net and IO.Read examples, which need nothing else.
>
> ## plt-2 (alternative): allow a `!` row on a derived op; the caller pays.
>
> Syntax: `fn hello() -> Str ! IO.Log { io.log("hi"); say("hello") }`. A call `greet.hello()` has row `{Greet.Say} ∪ IO.Log`. The charge is on the signature, so §4.1 holds. A handler that overrides `hello` keeps the declared row at call sites (the row is a bound, not an exact set). The override's own extra effects go in the clause row (§4.7), charged at the `with`. This is the Haskell mtl shape (default method with constraints) and the Rust shape (default method with `where`).
>
> Tradeoffs: sound, but it adds a grammar form, an op-row in the effect-handle type, a subsumption rule between the op row and the clause row, and projection/`Handler[_]` rules. Primitive ops would need the same row or the form is uneven. This is a large change for no current use. I do not recommend it now. If a real case appears, plt-2 is a conservative extension of plt-1: every plt-1 program stays valid.
>
> ## Cross-language
> Koka: operation types carry no row; the handler's clause pays, and a default body does not exist. Rust: a default method may use only what its `where` clause grants; plt-1 is the empty clause. OCaml 5 and Eff: no default bodies; the handler pays. mtl: constraints on the default method show in its type, which is plt-2.
>
> ## Position
> Vote plt-1, then fix the diagnostic. Reject any rule that runs an undeclared effect in a derived body without a row in the signature.

##### DevOps

> ## devops-1: No. A derived body performs only its own sub-effect. Make the error say so and name real fixes.
>
> **Rule.** A derived operation body runs under the row of the sub-effect that declares it (today's behavior, e.g. `Greet.Say`), plus pure code. Any call through another effect is an error. This holds for all three cases in the brief: a sibling sub-effect under the same root (`Greet.Loud`), a user effect (`Counter.Get`), and a builtin effect (`IO.Log`). One rule, no per-kind exceptions.
>
> **Why this rule.** The caller of `greet.hello()` already declares `! Greet.Say`. A derived body that also needs `Counter.Get` would charge the caller for an effect that appears in no signature the caller can read. That breaks §4.1: the signature must show the capabilities. Hover, LSP signature help, and the `with` site would all hide a real requirement. A handler clause body differs. Its extra effects go in the clause row `Handler[E ! E, R]`, which the `with` site sees and pays for. A derived body has no handler type and no `!` list, so it has no place to put a row. The brief confirms the parser rejects one (b.bl).
>
> **If a handler implements the op itself.** Nothing changes. The handler's clause row covers what its clause does. The derived body is not involved.
>
> **Diagnostic today is wrong, not the rule.** The help says "add `Counter.Get` to the `!` list of `Greet.hello`". A user cannot write that list. The message must change. Proposed:
>
> ```
> error[E0xxx]: derived operation `hello` of `Greet.Say` performs `Counter.Get`
>   --> app.bl:9:30
>    |
>  9 |     fn hello() -> Str { "hello {greet.name()} {counter.get()}" }
>    |                                                ^^^^^^^^^^^^^ effect `Counter.Get`
>    = note: a derived body runs at the call site and may perform only `Greet.Say`
>    = help: make `hello` a free function that declares the extra effect:
>            fn hello() -> Str ! Greet.Say, Counter.Get
>    = help: or make `hello` a primitive operation and implement it in each handler
> ```
>
> No `fix:` line. A machine fix that cannot compile is worse than none. A sibling case (`greet.shout` from `Greet.Loud`) gets the same text with the note "`Greet.Loud` is a different sub-effect; only the declaring sub-effect is allowed".
>
> **The free-function escape works today:**
>
> ```blink
> effect Greet {
>     effect Say {
>         fn name() -> Str
>     }
> }
>
> fn hello() -> Str ! Greet.Say, Counter.Get {
>     "hello {greet.name()} {counter.get()}"
> }
> ```
>
> The stdlib and convention carry the 'helper over several effects' case. Callers see the full row in the signature. `blink fmt`, LSP completion, and hover need no change.
>
> **Tradeoffs.**
> - Cost: a derived op cannot be a convenience method on the effect handle for cross-effect logic. Users write a free function and lose the `greet.hello()` spelling.
> - Gain: no new syntax, no new row position, no new parser or formatter path, and no hidden requirement at call sites. The diagnostic can be exact.
> - Dependency: the P1 gap (builtin `io.*` unchecked) means `io.log` in a derived body passes today. When that P1 lands, this rule makes it an error as well. The spec should state the rule now so the P1 fix has a ruling to follow. Until then the compiler accepts what the spec forbids, which I flag as a known gap, not a ruling.
>
> **Rejected alternative: allow `! R` on an op declaration.** The parser, formatter, LSP, and effect-row inference all gain a new position. Every handler and every caller of that op inherits `R`. It adds a second way to say what the clause row already says. Not worth it for zero spec examples that need it.
>
> **Cross-language.** Rust trait default methods may use only the trait's bounds and `where` clauses, and the caller sees the bounds on the trait: same shape as this rule. Haskell mtl default methods with extra constraints push those constraints into every instance and caller, which produces the long-constraint errors this rule avoids. Koka has no default operation bodies. Koka effect rows on functions are always written, so a helper function is the Koka idiom.

##### AI/ML

> ## aiml-1: A derived body may use only its own root effect. Any other effect is an error.
>
> Rule:
> 1. A derived operation body may call any operation of its **root** effect, including sibling sub-effects. It may also call pure code, `panic`, and other derived operations.
> 2. It may not perform an effect outside that root tree. This holds for user effects and for builtin effects (`IO.Log`, `IO.Read`). There is no `!` list on an operation, so there is no way to declare more.
> 3. Cost: the caller of the operation already has the root effect in its row. The body adds nothing to that row. No handler and no `with` site pays for a hidden effect.
> 4. If a handler implements the operation itself, the body never runs. Its clause body uses the clause row (`R` in `Handler[E, R]`), as today. So the "other effects" feature is already available, in the right place: the handler.
>
> ```blink
> effect Greet {
>     effect Say {
>         fn hello(name: Str) -> Str {
>             "hi {name}"
>         }
>         fn emphatic(name: Str) -> Str {
>             greet.shout(hello(name))   // OK: sibling Greet.Loud, same root
>         }
>     }
>     effect Loud {
>         fn shout(s: Str) -> Str
>     }
> }
> ```
>
> ```blink
> effect Greet {
>     effect Say {
>         fn hello(name: Str) -> Str {
>             io.log("hello {name}")   // error
>             "hi {name}"
>         }
>     }
> }
> ```
>
> Diagnostic (replace the unfollowable help):
>
> ```
> error[E0xxx]: derived operation `Greet.Say.hello` performs `IO.Log`, outside effect `Greet`
>   help: a derived body may use only effects of `Greet`.
>         Make `hello` a primitive operation and do the logging in a handler clause,
>         or call `io.log` from the caller.
> ```
>
> Never emit "add X to the `!` list", because the parser rejects `!` on an operation.
>
> Fix to the compiler: check the body under the **root** row (`Greet`), not `Greet.Say`. Today a call to `Greet.Loud` from `Greet.Say` fails; under this rule it passes.
>
> ### Domain argument (AI/ML)
> - One rule fits in one sentence: "a derived body stays inside its root effect." An LLM can learn it from §4.7.1 with no examples. The spec examples (Net verbs, IO.Read) already follow it, so the rule matches what models will copy.
> - Zero new syntax and zero new decision points. The alternative (a `!` row on operations, "aiml-2") adds a syntax form, a rule for who pays, and a rule for handler override. Each one is a place for a model to guess wrong.
> - Token cost: nothing added. The error text tells the model the one fix it can apply.
> - §4.1 stays true. A caller that reads `! Net.Connect` knows everything `net.get` can do. A hidden `IO.Log` would break this and also the auto-delegation text: the body runs at the call site, whose row has no `IO.Log`.
>
> ### Tradeoffs
> - Loses: a library author cannot write a derived `get_logged` that logs. They write a primitive op and a handler, or a stdlib helper function with `! IO.Log`. This is more code, but the cost shows in the signature.
> - Revisit later if a real case needs it. Adding `!` rows to operations later is backward compatible. Allowing hidden effects now cannot be undone.
>
> ### Cross-language
> - Rust: a default trait method sees only its trait bounds and `where` clauses. Same shape: body limited to what the signature gives.
> - Haskell mtl: a default method may need extra constraints, and these appear in the class context. The cost is explicit. aiml-2 would copy this.
> - Koka / Eff: handler clauses carry extra effects in the clause type. Blink's clause row already does this.
>
> ## aiml-2 (not preferred): allow `! R` on operations
> Syntax `fn hello() -> Str ! IO.Log { ... }` in an effect. The caller then needs `IO.Log`. I oppose it for the decision points above.

##### Minimalism

> ## min-1: No. A derived body stays inside its own root effect tree. No new syntax.
>
> **Rule.** A derived body may call operations of the root effect that declares it, and pure code. Siblings under the same root are allowed. Any other effect (user effect or builtin such as `IO.Log`) is a compile error. One check for all, no builtin special case.
>
> Root, not leaf: the ticket and spec say "own effect tree". The compiler today checks under the leaf and refuses a sibling call (i.bl, j.bl). That is a small bug against this intent: check under the root row.
>
> ```blink
> effect Greet {
>     effect Say {
>         fn name() -> Str
>         fn hello() -> Str { "hello {greet.name()} {greet.shout("x")}" }   // ok: same root
>     }
>     effect Loud {
>         fn shout(s: Str) -> Str
>     }
> }
> ```
>
> Refused case, and the fix:
>
> ```blink
> effect Greet {
>     effect Say {
>         fn name() -> Str
>         fn hello() -> Str { "hello {counter.get()}" }   // error
>     }
> }
>
> // instead: a free function, whose signature shows the capability
> fn hello() -> Str ! Greet.Say, Counter.Get {
>     "hello {greet.name()} {counter.get()}"
> }
> ```
>
> **Diagnostic.** Replace UndeclaredEffect at this site, because its help names a `!` list nobody can write (b.bl):
> `error: derived operation `Greet.hello` calls `Counter.Get`, outside effect `Greet``
> `help: a derived operation can call only operations of `Greet`. Move this code to a function with `! Greet.Say, Counter.Get`, or make `hello` primitive and implement it in each handler.`
> No fix-it edit: the right edit is a design choice.
>
> **Who pays.** Nobody, because no other effect occurs. §4.1 stays true without exception: the caller sees `! Greet.Say` and the body can do nothing more. No row on the op, none on the `with` site, no change to the clause row. A handler that implements the op is unaffected. Omitted derived ops keep their DECISIONS.md:441 behavior.
>
> **Why not allow it.**
> - Op-level `!` row: new syntax, parser, fmt, LSP, docs. Every caller pays `Counter.Get` even when a handler overrides the op and never uses it. It is a second signature to keep in step with the clause row. All spec examples (Net verbs, IO.Read) already stay in the tree, so there is no use case.
> - Handler or `with` site pays: the body runs at the call site, so the call site's row must cover it. "Handler pays" contradicts "runs at the call site".
> - Allow because builtins are unchecked today: that is the open P1 bug. Do not legislate from it. When fixed, `io.log` in a derived body fails with the same help.
>
> **Tradeoff.** An author cannot write "log, then request" in a default body. They write a free function. One extra function, and the signature shows the capability. We can lift the rule later with an op-level row without breaking any program. We cannot remove a row after it ships.
>
> **Cross-language.** Go: interfaces have no default bodies. Haskell: a default method needing extra constraints puts them on the class or moves to a function. Rust: default methods with `where` clauses push the bound to the caller, a known source of hard errors. Koka: handlers hold all bodies; no declared defaults.
>
> Sub-questions: sibling yes, builtin no, user effect no.

#### Phase B — Debate highlights

One round. Each panelist read all six Phase A texts and answered a list of options and variations. The moderator listed two options: Option 1, a derived body may not perform an effect outside its own effect, with no `!` row on an operation; Option 2, allow a `!` row on a derived operation, and the caller of the operation pays it. The variations were V1 (the leaf sub-effect or the root tree), V2 (which code), V3 (what the help offers) and V4 (a `fix:` line). The probe in the facts is `only_say`, described above. The texts name probe files such as `j.bl`; these were small scratch programs that the panel ran against the compiler. AI/ML and Minimalism changed V1 to the leaf. PLT changed V2. All six ended "STATUS: ready to vote".

##### Systems

> **Options.** I support Option 1. I keep sys-2 only as a fallback, and the other seats' rejections of it give me no reason to want it. No spec example needs an op-level row. It would add a parser rule and a new fit rule for `Handler[E ! R]`.
>
> **V1 (leaf, not root): I hold leaf.** Probe j.bl is the evidence. `only_say` has `! Greet.Say`. Its derived `hello` calls `greet.shout` of `Greet.Loud`. The program installs no `Greet.Loud` handler. If siblings were allowed, the caller would reach an effect that its signature does not name, with no handler for it. Spec :123 says children are independent capabilities that a caller can hold one at a time. The root rule (aiml-1, min-1) assumes the caller holds the root `Greet`. A caller that holds only `Greet.Say` does not. For the cost view: a root rule means the body can call into a sub-effect whose handler is absent or different, so the call site does not know which handler it reaches. Leaf keeps one effect and one handler lookup per body. I concede one point to min-1: §4.7.1 does not say "leaf". The spec text must say it, in §4.7.1, as a new sentence. "Effect tree" in the ticket is not a spec rule.
>
> **V2 (code): new code.** `UndeclaredEffect` (E0500) means "add to your `!` list". That help cannot be followed here, so a new code is correct. plt-1 wants E0500 with new help. I oppose that. A user who searches E0500 finds the advice that does not apply, and a test that matches the code cannot tell the two cases apart.
>
> **V3 (help): list all of these that apply.** Plain fn with the extra row; make the op primitive and implement it in the handlers. I support web-1's "take the value as a parameter" as a third line when the effect result is only data. I do not support aiml-1's "call the effect from the caller" as a help line. It moves the fix into the caller's code and the compiler cannot know what that code is. The sibling note (devops-1, web-1) is good: one sentence, "`Greet.Loud` is a different sub-effect".
>
> **V4 (fix line): no `fix:` line.** I agree with devops-1 and min-1. A fix that does not compile costs more than none. I changed nothing in my own Phase A text here: I had no fix line.
>
> **Change from Phase A.** One. I withdraw the claim that Rust and Koka mark the boundary the same way. I did not check Koka, so I drop that sentence. The rule stands on §4.1 and the clause-row argument.
>
> STATUS: ready to vote

##### Web/Scripting

> **Options.** Option 1. Six of six agree; I add nothing against Option 2. It is new syntax for a case no spec example needs.
>
> **V1: leaf sub-effect, not root tree.** I hold my position. The brief's own fact settles it: spec :123 says a parent grants all children, but a caller that holds `! Greet.Say` holds only that child. The body runs at the caller. Under root-tree checking, `only_say() ! Greet.Say` would call `greet.shout` with no `Greet.Loud` in its row, and no handler may exist (probe j.bl). That breaks §4.1 in the same way a foreign effect does. The aiml and min argument ("the caller has the root in its row") is true only when the caller wrote `! Greet`. Many callers will write the child. A rule that depends on how the caller wrote the row is the rule a JS or Python dev cannot predict. The words "effect tree" in the ticket are loose wording, not spec text; §4.7.1 is silent. If the panel prefers root, the compromise is: allowed only when the effect declares no sibling needing a separate handler. I do not support that; it adds a condition.
>
> **V2: new code.** E0500 means "declare this effect". Here the user cannot declare it. A different cause needs a different code, so search results and `blink explain` tell them apart. I oppose reusing E0500 (plt-1).
>
> **V3: help.** I accept the strongest merge: offer (a) a plain function with the extra row, and (b) make the op primitive and implement it in each handler. I drop my "take the value as a parameter" help; it only works for pure values. For siblings, add the note that `Greet.Loud` may have no handler where `Greet.Say` is handled.
>
> **V4: no `fix:` line.** I agree with devops and min. A fix that cannot compile is worse than none. This is a change from Phase A; I wrote no position there.
>
> STATUS: ready to vote

##### PLT

> **Options.** Option 1. Option 2 stays a conservative extension, not needed now. No change from Phase A.
>
> **V1: leaf, not root. This is the point that matters.** The root-tree reading is unsound under §4.1 and §4.1's own grant rule. Spec :123 says children are independent capabilities; `! Greet.Say` does not grant `Greet.Loud`. Probe j.bl is the counterexample: `only_say() ! Greet.Say` calls `greet.hello()`, whose body calls `greet.shout`. If the body is checked under root `Greet`, `only_say` performs `Greet.Loud` with no `Greet.Loud` in its row and with no handler installed. That is a missing handler at run time and a capability that was never granted. The aiml-1 argument ("the caller already has the root effect in its row") is false: the caller has only what it declares. Min's "effect tree" wording comes from the ticket note, not from §4.7.1; :123 and §4.12 govern. Root-tree is sound only if calling a derived op requires the root row. That is a new rule on every call site, and it is Option 2 with a hidden row. I oppose it. A body under root also lets two sub-effects of one root share state through the body. That breaks the independence that sub-effects exist to give.
>
> **V2: concede, new code.** E0500 says that the caller of a function lacks an effect. Here no caller is at fault. The effect declaration is ill-formed. The error belongs at the body, with its own code. Reusing E0500 would keep the wrong help text. I withdraw plt-1's "E0500 with new help".
>
> **V3: agree.** Offer the plain function with the full row first. Offer "make the op primitive and implement it in each handler" second. For a sibling, add devops-1's note that the sibling is a different capability. Reject web-1's parameter option as a listed fix: it changes the op signature, which is a design choice. Reject aiml-1's "call the effect from the caller" only in the case where the effect call is the point of the op.
>
> **V4: agree with devops-1 and min-1.** No `fix:` line. The help is prose only.
>
> Run note: I did not run j.bl; I rely on the brief. The compiler today already refuses the sibling case, so leaf matches current behaviour. Root-tree would loosen it.
>
> STATUS: ready to vote

##### DevOps

> **Option 1 vs 2.** I support Option 1. All six seats agree, so I add only one diagnostic point. Option 2 adds a `!` position that the parser, formatter, LSP hover and row inference must all handle, for zero spec examples that need it.
>
> **V1: leaf sub-effect, not root tree. I hold my Phase A position.** Spec :123 says children are independent capabilities. Probe j.bl is the evidence: `only_say` declares `! Greet.Say`, its derived body reaches `Greet.Loud`, and the program installs no `Greet.Loud` handler. Under the root-tree reading that program compiles with a requirement that the signature of `only_say` does not show. That is the exact hiding that §4.1 forbids. aiml-1 and min-1 argue "the caller already has the root". That is true for a caller that wrote `! Greet`. It is false for a caller that wrote `! Greet.Say`, and the compiler cannot know which caller it has when it checks the declaration. The check must therefore use the weakest caller, the leaf. Leaf-only also lets the diagnostic stay exact: one allowed effect, named in the message. The root-tree reading needs a second sentence: "or any sibling, if you hold the root".
> I do not see how the root-tree reading survives j.bl. If min or aiml see a way, I will listen. The phrase "effect tree" in the ticket title is not a spec rule; §4.7.1 is silent.
>
> **V2: a new code.** I disagree with plt-1. E0500 `UndeclaredEffect` means "add it to this function's `!` list". That is the false help we are removing. Keeping the code and changing the text leaves tools and docs that match on E0500 with the old meaning. A new code gets its own `--explain` entry and ERROR_CATALOG row. This is a diagnostics decision and does not touch language semantics.
>
> **V3: the help offers three fixes, in this order.** (1) a free function with the extra row; (2) make the op primitive and implement it in each handler; (3) pass the value as a parameter of the op (web-1). I take web-1's parameter option into my text. I take the note on the sibling case from web-1 as well: "`Greet.Loud` may have no handler where `Greet.Say` is handled". aiml-1's "call the effect from the caller" is the same as (1) with the call moved; I leave it out to keep the help to three lines.
>
> **V4: no `fix:` line.** I hold it. min-1 agrees. The right edit is a design choice, and an auto-fix that does not compile misleads LSP code actions.
>
> **Change from Phase A:** add fix (3) and the web-1 sibling note. Nothing else.
>
> STATUS: ready to vote

##### AI/ML

> **Option 1 over Option 2.** Unchanged. One rule, no new syntax, no new decision point for a model. Option 2 adds a syntax form, a rule for who pays, and a rule for handler override. Adding a row later is backward compatible, so waiting costs nothing.
>
> **V1: I change my position to the leaf sub-effect.** My Phase A claim was wrong. I wrote that the caller already holds the root effect. A caller holds only what its signature names. sections/04_effects.md:123 says children are independent capabilities. Probe j.bl shows the case: `only_say` is `! Greet.Say`, installs no `Greet.Loud` handler, and a sibling call from the body would perform an effect the signature never grants. That breaks §4.1. The compiler's current check under the leaf (`Greet.Say`) is correct. Drop my "check under the root row" compiler change. For a model, the rule is still one sentence: "a derived body may use only the effect it is declared in."
>
> Edge case to state in the spec: a derived op declared directly in a parent effect (not in a leaf) is checked under that parent row, which grants all its children (:123). Do not treat that as a sibling exception. It follows from the same rule.
>
> **V2: new code.** Reusing E0500 gives the same code to a case where the standard fix (add to the `!` list) cannot apply. A model that sees E0500 will apply that fix. A separate code lets `--explain` teach the real fix. I support a new code.
>
> **V3: help text.** Offer two fixes only, in this order:
> 1. Move the logic to a plain function with its own `!` row, and call it from the caller.
> 2. Make the op primitive and implement it in each handler (the clause row covers other effects).
> Drop the parameter option (web-1): it changes the op signature, which is a design choice. Drop "call from the caller" as a separate item: it is fix 1. Fewer options means fewer guesses. For the sibling case, add one line: "`Greet.Loud` is a different effect and may have no handler here."
>
> **V4: no `fix:` line.** I agree with devops and min. A machine fix that cannot compile teaches the model a wrong edit. A model applies `fix:` lines without thought.
>
> STATUS: ready to vote

##### Minimalism

> **Options.** Option 1. I oppose Option 2 for the Phase A reasons. It adds a second signature on the operation, and no spec example needs it. The missing example is the evidence: six seats found no use. The door stays open, because an op-level row can be added later without breaking a program.
>
> **V1: I change my position to the leaf sub-effect.** My Phase A said "root". The j.bl fact defeats it. A caller with `! Greet.Say` calls `greet.hello()`. The body would call `greet.shout` of `Greet.Loud`. The caller never held `Greet.Loud`, and no handler for it need exist. That breaks §4.1 (the signature shows the capabilities) and sections/04_effects.md:123, where children are independent capabilities. aiml-1's reason ("the caller already has the root in its row") is false: the caller holds the leaf, and a parent grants children only in the other direction. Leaf also removes work. It is what the compiler does today, so Option 1 with leaf needs no check change, only the diagnostic. The ticket wording "own effect tree" is not a rule; §4.7.1 does not define it. Read it as "own effect."
>
> **V2: new code.** A new code, since the problem differs from "add it to your `!` list". Reuse of E0500 with different help makes one code carry two opposite fixes. Do not name the number here; the writer assigns it.
>
> **V3: help text.** Offer the plain function first (all six agree). Offer "make the op primitive" second. Web's "take the value as a parameter" and aiml's "call the effect from the caller" are good for the simple cases, but each is one more alternative on a diagnostic that should be short. I accept at most two options in the help. For the sibling case, add devops's note that `Greet.Loud` is a different effect.
>
> **V4: no `fix:` line.** I agree with devops. A fix that cannot compile is worse than none.
>
> **Unchanged:** builtin and user effects refused the same way; nothing charged to the handler or the `with` site; the clause row (§4.7) unchanged; the P1 bug is not a precedent.
>
> STATUS: ready to vote

#### Phase C — Final vote

- **Q1: the rule** (6-0)
  - A: a derived body may not perform an effect outside its own effect; no `!` row on an operation.
  - B: allow a `!` row on a derived operation; the caller of the operation pays it.

  Winner: **A**.

##### Q1 — Systems

> **Q1. The rule.**
> **Vote:** A
> **Reasoning:** A derived body runs at the call site, inlined into the caller. The caller's row for the op comes from the op's effect, so the body must add nothing to it. This keeps §4.1 true and keeps `Handler[E]` honest when a handler omits a derived op. An op-level row would add a parser rule and a new fit rule for `Handler[E ! R]` for no spec example. The spec must say "leaf sub-effect" in §4.7.1, with a new diagnostic code (not E0500) and no `fix:` line.
> **Concern:** A user cannot write a derived op that logs, and the help must lead them to a helper `fn` or a primitive op, or the refusal will look arbitrary.

##### Q1 — Web/Scripting

> **Q1. The rule.**
> **Vote:** A
> **Reasoning:** A derived body is a default method. A JS or Kotlin dev reads `net.get` as sugar over `request` and does not expect hidden effects. The caller's `!` list is the only place a reader looks, so the body may use only its own leaf effect. A plain function with its own `!` row is a familiar escape, and it needs no new syntax.
> **Concern:** A library author who wants a default op that logs must write a free function and lose the `greet.hello()` spelling.

##### Q1 — PLT

> **Q1. The rule.**
> **Vote:** A
>
> **Reasoning:** A derived body runs at the call site, so its effects reach the caller. Under §4.1 those effects must show in the caller's row. An op has no row of its own, and a caller that holds `! Greet.Say` does not hold `Greet.Loud` (spec :123). So the body may perform only its declaring leaf sub-effect. This closes the unsoundness with no new syntax, and every program valid under A stays valid if B is added later.
>
> **Concern:** If a real case needs an extra effect in a derived body, users must move the logic to a plain function and lose the default-body convenience until the language adds B.

##### Q1 — DevOps

> ## Q1. The rule
> **Vote:** A
>
> **Reasoning:** A derived body runs at the call site under the caller's row, and the caller can read that row in the signature (§4.1). An op-level `!` row adds a new position that the parser, formatter, LSP hover and row inference must all handle. It has no spec example that needs it. With Option 1 the diagnostic is exact: one allowed effect, named in the message. It also gets a new code, a sibling-case note, no `fix:` line, and no help that points at an unwritable `!` list.
>
> **Concern:** The compiler accepts `io.log` in a derived body today because of the open P1 bug, so the spec forbids what the compiler allows until that bug is fixed.

##### Q1 — AI/ML

> **Q1. The rule.**
> **Vote:** A
> **Reasoning:** One rule with no exception is the cheapest for a model to learn from the spec: a derived body stays in its own leaf effect, and an op has no `!` row. Option B adds new syntax and a new cost rule for the caller, and a model must then guess which handlers pay. It also leaves no example in the spec to copy. A sibling, builtin and user effect all get the same refusal, so there is no case to memorize.
> **Concern:** A model may still write `io.log` in a derived body, because the builtin check is missing today (the open P1 bug), and the new refusal will not fire until that bug is fixed.

##### Q1 — Minimalism

> **Q1. Vote: A**
> **Reasoning:** No spec example needs an op-level `!` row. Option 1 adds no syntax, and it keeps §4.1 true with no exception. We can add a row later without breaking any program, but we cannot remove one after it ships.
> **Concern:** Authors who want "log, then request" in a default body must write a plain function. Pressure for Option 2 may return when real use cases appear.

- **Q2: a third help line, "take the value as a parameter of the op"** (5-1, Systems dissent)
  - A: in, as a third line.
  - B: out; the help has two fixes.

  Winner: **B**. The Systems vote is the dissent; DevOps voted A in Phase B and changed to B.

##### Q2 — Systems *(dissent)*

> **Q2. Third help line (value as op parameter).**
> **Vote:** A
> **Reasoning:** It costs nothing at run time, and it is the only fix that keeps the op derived when the effect result is only data. This matches my B1 position. The help stays prose, so it makes no promise the compiler cannot check.
> **Concern:** The compiler cannot tell when the result is only data, so the line may point at a change that does not fit, and a third line adds noise to the help.

##### Q2 — Web/Scripting

> **Q2. Third help line (take the value as a parameter).**
> **Vote:** B
> **Reasoning:** I dropped this line in B1. It works only when the effect result is pure data, and it changes the op signature. A short diagnostic with two fixes is easier to read and to apply.
> **Concern:** A user whose case is "only needs a value" gets no hint toward the simplest fix.

##### Q2 — PLT

> **Q2. A third help line (take the value as a parameter).**
> **Vote:** B
>
> **Reasoning:** The line works only for pure values, and it changes the op signature, which is a design choice the compiler must not suggest. Two help lines, both of which keep the program sound, are enough.
>
> **Concern:** Users who need an effect result as data get no hint, so they may pick the wrong fix of the two.

##### Q2 — DevOps

> ## Q2. Third help line (take the value as a parameter)
> **Vote:** B
>
> **Reasoning:** I put this line in at B1, and I now change my vote. It only works when the effect result is pure data, and it changes the signature of the op, which is a design choice and not a mechanical edit. A diagnostic that offers a fix which fits only some cases adds noise and trains users to skip the help. Two exact fixes (a plain function with its own `!` row; make the op primitive and implement it in each handler) cover every case.
>
> **Concern:** A user whose body needs only a value, such as a config string, gets no hint of the cheapest fix and may reach for the heavier primitive-op route.

##### Q2 — AI/ML

> **Q2. A third help line (pass the value as a parameter).**
> **Vote:** B
> **Reasoning:** Two fixes in the help give the model a clear choice: a plain function with its own `!` row, or make the op primitive and implement it in each handler. A third line changes the op signature, which is a design decision and not a repair, and it works only for pure values. Every added line is a decision point for a model that follows the help text literally.
> **Concern:** A user whose effect result is only data gets no direct hint to pass it as a parameter, and must find it from the first fix.

##### Q2 — Minimalism

> **Q2. Vote: B**
> **Reasoning:** The help keeps two fixes, which is the most a short diagnostic should carry. Taking the value as a parameter changes the op signature, which is a design choice. It works only for pure values, so it does not belong in a compiler hint.
> **Concern:** If the third line is added, the help grows with each new idea, and the diagnostic becomes a tutorial.

### Final Spec

```blink
effect Counter {
    effect Get {
        fn get() -> Int
    }
}

effect Greet {
    effect Say {
        fn name() -> Str
        fn hello() -> Str {
            "hello {greet.name()} {counter.get()}"   // error: `Counter.Get` is not `Greet.Say`
        }
    }
}

fn hello_logged() -> Str ! Greet.Say, IO.Log {   // fix 1: a plain function with its own row
    io.log("greeting")
    greet.hello()
}
```

- A derived operation body may perform only the leaf sub-effect it is declared in. An operation declaration has no `!` row.
- A built-in effect, another user effect and a sibling sub-effect are refused the same way.
- The diagnostic is `DerivedOpForeignEffect` (E0557), in §4.7.1 and the error catalog. It is not E0500.
- The help has two fixes, in this order: a plain function with its own `!` row; a primitive operation implemented in each handler. A sibling gets one more line. There is no `fix:` line and no mention of a `!` list.
- The clause row (§4.7) does not change. The compiler charges nothing to the handler or to the `with`.
- An op-level `!` row (Option 2) can be added later without breaking a program that follows this rule.
