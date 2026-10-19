[< All Decisions](../DECISIONS.md)

# Module-Level Initializers — Design Rationale

The spec said a module-level `let` is "runtime-initialized" and that its initializer may be "any expression". It said nothing about which effects an initializer may perform, the order initializers run in, a panic in one, a read before init, cycles, or `return` and `?` inside one.

Measured with the compiler before the decision (gen1):

- An initializer that calls a `! IO` function printed before `main`, with no diagnostic.
- A user effect operation in an initializer, with no handler, returned 0.
- A panic in an initializer exited 1 before `main`.
- Literals were C statics. Other initializers ran in source order in a per-module init function; the order across modules was not specified.
- `fn fa() -> Int { b + 1 }`, `let a = fa()`, `let b = a + 1` printed `1 2`: `b` was read as a zeroed global.
- A forward reference to a call-initialized global, and a cycle across modules, were internal compiler errors.
- An initializer could write a module `let mut`.

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in independent-proposal → debate → vote rounds. Quoted text is each panelist's own, verbatim; only local ticket IDs are replaced with a short name.

#### Phase A — Independent proposals

The panel split 3-3. Systems, PLT and Web/Scripting proposed a closed syntactic set of static initializers (Option S). DevOps, AI/ML and Minimalism proposed any initializer whose effect row is empty, run in dependency order with a compile-time cycle check (Option P). All six rejected the ticket's own suggestion (const initializers only) and "do nothing". Excerpts:

- **Systems:**

> ## Position
>
> No user code runs before `main`. A module `let` initializer holds data, not work. Every initializer must compile to C static data, or to a fixed list of allocations that the compiler writes and that cannot fail except on out-of-memory. This closes this gap and the `return`/`?` gap together, and it keeps "reads of a module `let` are free" true at the machine level, with no guard branch on each read.

- **Web/Scripting:**

> ## Proposal A (my pick) — "init expressions"
>
> A module-level `let` / `let mut` initializer must be an **init expression**:
>
> - any const expression (§2.21), with refs to `const` and type-scoped constants only;
> - list literals `[]`, `[a, b]`, tuple literals, struct literals, enum variants — each part an init expression;
> - the empty-collection constructors by name: `Map()`, `Set()`, `Map.new[K, V]()`, `Set.new[T]()`, `List.new()`, `List.new[T]()` (with no arguments; `List.with_capacity(n)` is out). These are calls in syntax, and §2.21 excludes them ("these allocate"). I carve them out on purpose: they are total, pure, cannot panic, and do not depend on order. A JS dev reads `Map()` as `new Map()`;
> - closure literals `fn(n: Int) -> Int { n * 2 }`. The body runs only when called, never at startup. (A JS dev writes `const add = (n) => n + 1` all day.)
>
> **Not** init expressions: any other call or method call, `if`, `match`, a block, `with`, `?`, `return`, and any read of a module `let` or `let mut`.
>
> That last rule does the real work. Note the trap: the State ruling keeps reads of a module `let` free of effects. So "pure calls only" (empty effect row) does **not** catch case #5 — `fn fa() -> Int { b + 1 }` has an empty row and still reads `b` before it is set. With no calls and no `let` reads, no initializer can see another one. Order stops being something a user can observe.

- **PLT:**

> ## Proposal P1 (my pick): static initializers
>
> Add a second judgment beside const: **static expression**. A module `let` / `let mut` initializer must be static.
>
> ```
> s ::= c                      -- any const expression (§2.21), incl. const refs
>     | (s, ..., s)            -- tuple
>     | [s, ...]               -- list literal, incl. []
>     | Map() | Set() | List() -- zero-arg built-in empty constructors
>     | T { f: s, ... }        -- struct literal
>     | V(s, ...)              -- variant
>     | fn(params) -> R ! E { body }   -- function literal; the body is not run at init
> ```
>
> Not static: calls (other than the three empty constructors), method calls, reads of a module `let` or `let mut`, `if` / `match` / blocks, string interpolation, `return`, `?`.

- **DevOps:**

> ## Position
>
> Do not go "const only". Go "pure only": **a module `let` initializer must have an empty effective row** — the same test `@pure` already uses (§3b.2, §4.16.3). Then specify order by dependency, reject cycles at compile time, and reject `return` / `?` in typecheck.
>
> My lens is the diagnostic surface. Today four of the brief's seven cases give either no diagnostic (IO at startup, user effect returns 0, cycle reads a zeroed global) or an ICE (forward ref to a call global, cross-module cycle, `return`, `?`). An ICE and a silent zero are the two worst outputs a toolchain can give. Each rule below exists to turn one of those into a named error with a span and a fix.
>
> ## Proposal 1 (main): pure initializers, dependency order
>
> ### Rules
>
> 1. **Effects.** The initializer's effective row must be empty. This one rule rejects IO, user effects (so no question of which handler is in force: none is), and `State` (no read or write of a module `let mut`, so `let first = bump()` is out). Reads of module `let` and `const` stay free, as §4.16 already says. Panics are not effects, so `unwrap`, index out of range and overflow can still fire.
> 2. **Order.** An initializer runs after every initializer it depends on. "Depends on" = names a module `let` directly, or calls a function whose body (transitively) reads one. This holds within a module and across modules. Intra-package import cycles are legal (§7, Cycle Detection), so "imports first" cannot be the rule; per-binding dependency order can. Independent initializers run in module order then source order; since they are pure, only which panic fires first can tell the difference.
> 3. **Cycles.** A dependency cycle is a compile error. This replaces the silent zero (brief item 5) and the cross-module ICE (item 6). Forward references with no cycle are fine (item 6, `let y = x + 1` above `let x = id(5)`, becomes legal and correct instead of an ICE).
> 4. **`return` and `?`.** Rejected in typecheck when they would leave the initializer. There is no function to return from and no `Result` to propagate into. A `return` inside a closure literal in the initializer is fine. Covers ticket the `return`/`?` gap.
> 5. **Panic.** Allowed. The program prints the panic, names the binding, and exits 1 before `main` runs. `blink test` reports it once as a setup failure for the binary, not N test failures.

- **AI/ML:**

> ## Summary
>
> Proposal 1 (my pick): **pure initializers**. A module `let` initializer may be any expression whose effect row is empty: no built-in effect, no user effect, no `State`. Order follows dependencies, and a cycle is a compile error. `return` and `?` are errors in an initializer. A panic during initialization is a defined startup failure.
>
> Proposal 2 (fallback): **data-only initializers**. Const expressions plus list literals, empty-collection constructors, and function literals. No calls to user functions.
>
> I rank 1 above 2 because 2 has no good fix for a common, harmless pattern (a lookup table built by a pure function), and an LLM that hits a rule with no clear fix makes the most retry loops.

- **Minimalism:**

> ## Position in one line
>
> Do not add a new mechanism. Use the effect system we already have: **a module-level `let` initializer must have an empty effect row.** Panics stay allowed. Everything else (order, cycles, `return`/`?`, handlers) then gets a short answer that follows from rules we already have.
>
> I reject the ticket's own fix (const-only) and I reject "do nothing".

#### Phase B — Debate highlights

One round. All six replied `STABLE: yes`. Four panelists changed their pick: AI/ML, Minimalism and DevOps moved from P to S, and Web/Scripting moved from S to P. Systems kept S as a narrow first choice. The opening of each reply:

- **Systems:**

> ## The strongest argument against S (aiml, also min)
>
> aiml's point is the one that hurts S. A pure lookup table (`make_lookup()`) has no one-line form under S, because Blink has no map literal. My Phase A fix was "`let mut t = []`, fill it in `main`". I now count the cost of that fix more honestly. The table becomes `let mut`, so **every reader gets `State` in its row**. Each `pub fn` that reads it must declare `! State` (E0552). A function value that reads it can no longer go to `async.spawn` (E0651). A read-only value then looks, to the type system, like shared mutable state. That is worse for local reasoning and for codegen (no `const`-like aliasing, no free sharing across tasks) than one pure call before `main`. So S moves the cost out of startup and into every signature. I concede this.
>
> What I still hold against P: user code runs before `main`, and the compiler needs a cycle walk through function bodies. Both costs are bounded. The row is empty, so the code is pure work. Blink already compiles the whole program (mono), so the walk is not a new kind of pass.

- **Web/Scripting:**

> ## I move from S to P
>
> aiml has the strongest argument, and it beats my Phase A. Under S, the only fix for a pure lookup table (`let lookup = make_lookup()`) is my own memo recipe: `let mut x: Option[T] = None` and a fn to fill it. But a read of a module `let mut` puts `State` in the row, and every `pub` fn that reaches it must declare `! State` (E0552). So one table that never changes spreads `State` through every signature that touches it, all to describe a value that is fixed. That is the ceremony I said we must not copy from Rust. It is worse than Rust here, because `LazyLock` at least keeps the signature clean. Blink has no map literal, so the user has no one-line form. A JS or Python dev hits this in week one.
>
> S also fails my "5 minutes" test in a quieter way. Its rule is a list of exceptions: `Map()` yes, `List()` does not exist, `List.new()` yes, `List.with_capacity(n)` no, your own `cols_empty()` no. Each line of that list is a future Stack Overflow question ("why can't I call my pure helper at top level?"). P's rule fits in one line a dev already knows from the signature: **an initializer cannot do I/O or touch mutable globals.** Go devs live with "dependency order + initialization cycle error" without complaint.
>
> To sys and plt: your soundness case is correct. Under P, init can still panic or loop before `main`. I accept that. A panic in a pure initializer happens on every run, at once, with the binding named. A dev finds it in the first second, not in production. This is not the hidden-effect bug the ticket is about. Your whole-program cost point (sys) is real, but it is the compiler's cost, not the user's. devops and min say the effect walk already exists.

- **PLT:**

> ## Answer to the strongest P argument (aiml, with min and devops)
>
> aiml's best point is that a pure lookup table (`let lookup = make_lookup()`) has no one-line form under S. The memo fix puts `State` in every reader's row. I grant both facts. Three replies:
>
> 1. **Need.** The measured need is one test fixture. src/lib/examples have zero such tables. We should not buy a whole-program analysis for a case the corpus does not have.
> 2. **Direction of change.** Every S program is a P program. If we pick S now and a real need shows up, we can widen to P later and break nothing. If we pick P now and find a hole in the cycle analysis, narrowing to S breaks code. S is the choice we can undo; P is not.
> 3. **Where the soundness lives.** Under S, "a read of a module `let` is free" holds by a local, syntactic rule. Under P, it holds only if the dependency analysis is exact or over-approximates. devops is honest that indirect calls (function values, trait dispatch, closures passed to `.map`) need the crude rule "depends on every module `let` that any address-taken function or lambda reads". Without that rule, a missed edge is a zeroed `Str`, which is a null deref. That is a memory-safety hole, not a wrong number. min and aiml do not state an indirect-call rule at all. As written, M1 and aiml-P1 are unsound.

- **DevOps:**

> ## I move from P to S, and here is why
>
> web made the strongest point against my group. Reads of a module `let` are free, so an empty row does not catch case #5 (`fn fa() -> Int { b + 1 }`). To catch it, P needs a cycle walk through function bodies. plt added that the walk is only conservative through function values, trait methods and `! _` rows. sys added that it is a whole-program pass.
>
> I wrote that conservative rule myself (P-V3). Judged by my own test (what does the error look like?), it fails. A false cycle error that names "any address-taken function" is a message the user cannot act on. They never called that function and cannot see the path. The runtime-guard fallback is worse: the editor stays green and the binary crashes on startup. A P cycle error is also non-local. Editing a fn body in file A can raise an error on a `let` in file B. LSP then has to re-check the whole package on each keystroke to keep that error honest.
>
> S gives the best diagnostic surface on the table:
> - one code, one span, on the line the user is typing;
> - decidable from syntax, so LSP can flag it with no call graph and no other files;
> - no false positives, no panics before `main`, and no order to explain.
>
> The help text carries the cost. It must show the one fix: compute the value in `main`, or memoize it in a `let mut` and let the reader get `State`. aiml's `make_lookup()` case is real. But it is one memo function plus an honest `State` in the signature, and the error can print that exact pattern.
>
> I accept that my own Phase A example `let width = names.len() * LIMIT` becomes an error under S.

- **AI/ML:**

> ## The strongest argument from Option S: I accept it
>
> The strongest argument comes from **plt** (with **web**'s case #5 point behind it). Under P, module `let` reads are free, so an empty row does not stop a read before init. Catching that needs read sets through function bodies, and through function values, trait methods and `! _` rows those sets can only be conservative. devops says this openly (P-V3): "an indirect call depends on every module `let` read by any address-taken function".
>
> That is bad on my axis. A conservative false cycle gives an error whose cause sits in an unrelated function the model never touched. That is the worst repair-loop shape for an LLM: the span does not explain the error, so the model guesses. A missed cycle (devops's run-time guard fallback) is worse, because it ships.
>
> My Phase A case for P was "the habit `let table = build()` compiles when pure, and S has no clear fix for it". I measured that habit: it shows up **once**, in a test (`make_lookup()`), and never in src/lib/examples. The fix S gives (a `let mut x: Option[T] = None` memo behind `State`) is plain Blink. It works when the help text shows it as one fixed recipe. And narrow-then-widen is the right order for learnability too: we can later add pure calls or a map literal, but taking a rule back breaks code that models have already learned.
>
> So I **move to Option S**. Its rule is a closed list, the error lands on the bad subterm, and it needs no order, cycle or panic-before-main rules. That means three fewer spec paragraphs a model must learn.

- **Minimalism:**

> ## I change my pick: from P to S, in its narrow form (plt / web)
>
> I said I would apply a subtraction lens. On that lens I chose wrong in Phase A, and I say so here.
>
> **plt and sys gave the strongest argument against P.** Here is my short form of it. P keeps a run-time init phase. The spec must then still say four things:
> - the dependency order;
> - a cycle analysis that goes through function bodies (devops admits it needs a conservative rule for function values: P-V3);
> - what a panic before `main` does (and devops's P-V4 for `blink test`);
> - the order tie-break (P-V1, already in dispute).
>
> I counted the rules M1 needs: an order rule, a cycle analysis, a panic rule and three new codes. Narrow S needs **one** new code, and the order, cycle, panic-before-`main` and handler questions do not exist for it. The spec says *less*. That is the result I want.
>
> My Phase A objection to S was "it widens what `const` means". It does not. S adds one short list next to const. With that list, every other init rule leaves the spec. A small addition that removes four rules is a net subtraction.
>
> sys also makes the YAGNI argument, and I accept it: **start narrow and widen later.** Widening S later (const fns, pure calls) breaks no one. Narrowing P later breaks users. lib/ and examples/ have zero initializers that need a computed value. Under S, src/ changes about 11 lines, each a mechanical inline. The memo pattern (`let mut x: Option[T] = None` plus a `! State` accessor) is plain Blink today, so we add no lazy type.

#### Phase C — Final vote

- **Q1: rule for module-level initializers** — S (static initializers) 6-0. Web/Scripting returned from P to S.
- **Q2: may an initializer read another module `let`?** — Deny 6-0. Systems and Web/Scripting moved from Allow, on DevOps's point that `let mut seen = names` would share one list with an immutable `let`.
- **Q3: empty-collection constructors** — Named (`[]`, `Map()`, `Set()`, `Map.new[K, V]()`, `Set.new[T]()`, `List.new()`, `List.new[T]()`) 5-1. **Minimalism** *(dissent)*: Small (`[]`, `Map()`, `Set()`).
- **Q4: is string interpolation static?** — No 6-0.
- **Q5: function literals** — NoRule (no capture rule) 6-0.
- **Q6: diagnostic** — OneNew (`NonInitExpr`, E1129) 6-0.
- **Q7: rollout** — WarnThenError 5-1. **Minimalism** *(dissent)*: ErrorNow.

Phase D did not run: no question was closer than 5-1. The user signed off on the tally.

Each ballot, verbatim:

<details><summary><b>Systems</b></summary>

> ## Q1. Rule for module-level initializers
> **Vote:** S
> **Reasoning:** Under S no user code runs before `main`. Every initializer lowers to C static data or a short list of runtime constructor calls. Global reads stay a plain load, with no guard and no hidden startup cost. P's soundness depends on a whole-program read-set analysis that can only over-approximate through function values and trait methods. A miss there reads a zeroed `Str`, which is a null dereference, not a wrong number. S is the choice we can widen later at no cost; P cannot be narrowed without breaking code.
> **Concern:** A pure computed table becomes a `let mut` memo behind `State`, so `State` spreads into readers' signatures and blocks `async.spawn` (E0651) for a value that never changes. If real code hits this often, we must widen soon (const fns or a map literal).
>
> ## Q2 (S-V1). Reads of another module `let`
> **Vote:** Deny
> **Reasoning:** I change my B1 position. With reads denied, init order is not observable and a cycle cannot exist, so we need no topological sort and no second code. devops's aliasing point is a real hardware-level hazard: `let mut seen = names` would share one `List` buffer, and a push through the `mut` binding would change an immutable `let`. `const` refs cover the sharing need, and we can widen later.
> **Concern:** Users will write `let b = a` and get an error that looks arbitrary, so the help text must say "make `a` a `const`".
>
> ## Q3 (S-V2). Empty-collection constructors
> **Vote:** Named
> **Reasoning:** All seven spellings lower to the same zero-argument runtime constructor, so each extra spelling costs nothing in codegen. Rejecting a spelling that users and models already write only causes retries. `List.with_capacity(n)` stays out, because a bad `n` can panic and S promises a total initializer.
> **Concern:** The list must track the real stdlib names, or the spec will again name a constructor that does not exist (as `List()` did).
>
> ## Q4 (S-V3). String interpolation
> **Vote:** No
> **Reasoning:** Interpolation dispatches to `Display` / `to_str`, which is user code that can panic or allocate without bound. That is the run-time work S exists to keep out of init.
> **Concern:** None worth noting. A plain string literal stays const.
>
> ## Q5 (S-V4). Function literals
> **Vote:** NoRule
> **Reasoning:** At module scope the only names in reach are module names, and they bind as global references at call time, not as captured values. A module-level literal therefore lowers to a static function pointer with no environment to allocate. My Phase A capture rule said nothing extra, so I drop it.
> **Concern:** None, as long as typecheck still gives the literal's own row `State` when its body reads a `let mut`.
>
> ## Q6. Diagnostic
> **Vote:** OneNew
> **Reasoning:** Use one code (E1129) with a label that names the kind of the first bad subterm. The fix belongs in help text, not in the code number. E1101 says "const", which is the wrong set. E0508/E0509 talk about an enclosing function's return type, and an initializer has none.
> **Concern:** The help text must show the memo recipe and state its `State` cost plainly, or users will believe they hit a missing feature.
>
> ## Q7 (S-V5). Rollout
> **Vote:** WarnThenError
> **Reasoning:** The self-host protocol needs this anyway. The rule lands, then src migrates (about 11 lines, one of them `node_columns_empty()`, which needs a memo or a move into `main`), then the warning becomes an error. The warning must carry the final code and message.
> **Concern:** The warning stage must not last past one release, or new code will grow more dynamic initializers to migrate.

</details>

<details><summary><b>Web/Scripting</b></summary>

> ## Q1. Rule for module-level `let` / `let mut` initializers
> **Vote:** S
>
> **Reasoning:** In B1 I moved to P to spare the pure-table case a `State` memo. devops's B1 has the stronger DX point, and I missed it. Under P, a cycle error can come from a function the user never touched, through a function value, and can show up in file B after an edit in file A. That error is the worst kind for a JS or Python dev: it looks like a compiler bug, and it will keep coming back as a question. S puts one error on the line being typed, and the help gives one fix. The pure-table case occurs once in the corpus (a test fixture). plt is right that S can widen to P later with no breakage, but P cannot narrow back to S without breakage.
>
> **Concern:** The memo recipe puts `State` in the row of every reader of a computed table. If that pattern spreads in user code, we must widen soon (a map literal or pure calls), not leave it as a papercut.
>
> ## Q2 (S-V1). Reads of another module `let`
> **Vote:** Deny
>
> **Reasoning:** I said Allow in B1. devops's aliasing point changes my vote. With `let mut seen = names`, a `push` on `seen` could change an immutable `let`, and that gotcha is worse than the rule. Deny also keeps "order does not exist" true, so the spec needs no order section to teach. The help can say "make it a `const`, or repeat the literal".
>
> **Concern:** Users will try `let b = a` with a list and hit an error they did not expect, so the message must name the read ("read of module `let` `a`") and give the fix.
>
> ## Q3 (S-V2). Empty-collection constructors
> **Vote:** Named
>
> **Reasoning:** People write `List.new()` and `Map.new[K, V]()` because the docs and the `List()` help text tell them to. If the static list rejects a spelling the compiler itself suggests, that is a trap. Only zero-argument forms count, and `List.with_capacity(n)` is out.
>
> **Concern:** The list must stay in sync with the stdlib. If a new empty constructor ships and nobody adds it, that is a fresh "why is this not allowed" question.
>
> ## Q4 (S-V3). String interpolation
> **Vote:** No
>
> **Reasoning:** Interpolation runs `Display`, which is user code. A plain string literal is still allowed, which covers what people write at module level.
>
> **Concern:** `let greeting = "v{VERSION}"` with a `const` will surprise people, so the label must say "string interpolation runs `Display`".
>
> ## Q5 (S-V4). Function literals at module level
> **Vote:** NoRule
>
> **Reasoning:** At module scope there are no locals to capture. The body runs at call time and is checked like any fn body, `State` included. A rule here would only add a line to learn.
>
> **Concern:** None worth a rule. Calling a module-level closure is an ICE today (`CodegenStageNotBuilt`), so that must work before S makes closures the endorsed form.
>
> ## Q6. Diagnostic
> **Vote:** OneNew
>
> **Reasoning:** One code (E1129) whose label names the bad part: "function call", "`if` expression", "block", "string interpolation", "read of module `let` `x`", "`return`/`?` has no enclosing function". The help shows the fix (compute in `main`, or the memo with its `State` cost). E0508/E0509 would tell the user about a function that does not exist.
>
> **Concern:** If the help text omits the `State` cost of the memo, users will find out from a later E0552 and feel tricked.
>
> ## Q7 (S-V5). Rollout
> **Vote:** WarnThenError
>
> **Reasoning:** The bootstrap needs it anyway. A warning with the final code and text lets users fix before the build breaks, and the docs and `--explain` do not change when it turns into an error.
>
> **Concern:** A warning phase that never ends. Tie the switch to a named release.

</details>

<details><summary><b>PLT</b></summary>

> ## Q1. Rule for module-level initializers
> **Vote:** S
> **Reasoning:** Under S, "a read of a module `let` is free" holds by a local, syntactic judgment. Each static term refers only to consts, always finishes, and has an empty row, so init order cannot be seen and cycles cannot exist. Under P the same property rests on a whole-program dependency analysis that is only conservative through function values, trait methods and `! _` rows, and a missed edge is a null read. S is also the choice we can undo: every S program is a P program, so we can widen later and break no one.
> **Concern:** A pure, fixed table (`make_lookup()`, `node_columns_empty()`) must become a `let mut` memo, so its readers carry `State` for a value that never changes. That may push us toward ad hoc exceptions later instead of a principled widening such as pure calls or const fns.
>
> ## Q2 (S-V1). Reads of another module `let`
> **Vote:** Deny
> **Reasoning:** Denying reads keeps each initializer closed over consts only. That is what makes order unobservable and removes the cycle rule and the order rule from the spec. It also avoids the aliasing hazard devops named (`let mut seen = names` sharing one list). `const` refs cover the real need, and we can add `let` reads later as a compatible widening.
> **Concern:** Users who write `let b = a` will hit an error they do not expect, so the help line must say "make `a` a `const`".
>
> ## Q3 (S-V2). Empty-collection constructors
> **Vote:** Named
> **Reasoning:** Each listed form is a zero-argument, total, effect-free allocation, so each one is static by the same argument as `Map()`. Adding a spelling does not weaken soundness. Leaving one out only makes the rule look arbitrary. `List.with_capacity(n)` stays out because it takes an argument and can panic.
> **Concern:** The list is a closed set of names. A new zero-arg constructor in std later needs a spec edit, or the rule will drift from the library.
>
> ## Q4 (S-V3). String interpolation
> **Vote:** No
> **Reasoning:** Interpolation dispatches to a user `Display` impl, which is arbitrary code that can panic or loop. That breaks the totality S relies on. A plain string literal is already const.
> **Concern:** Users may expect `"{CONST}"` with const parts to work. That is a later widening, not a soundness issue.
>
> ## Q5 (S-V4). Function literals at module level
> **Vote:** NoRule
> **Reasoning:** Building a closure does not run its body. The literal's type carries its own effective row (`! State` if the body reads a `let mut`), and the initializer's row stays empty. At module scope there are no locals to capture, so a capture rule would add text that says nothing.
> **Concern:** A `let mut` holding a closure that reads module state carries `State` in its type, and users may find that surprising at the call site.
>
> ## Q6. Diagnostic
> **Vote:** OneNew
> **Reasoning:** "Static" is a different judgment from "const", and from "`?` in a function whose return type is not Result". Reusing E1101 or E0508/E0509 would report the wrong judgment and give a false message. One code labelled by the first bad subterm keeps the error local and true.
> **Concern:** If the label names only the first bad subterm, a user may fix one and hit the next. The note list should cover every bad subterm in that initializer.
>
> ## Q7 (S-V5). Rollout
> **Vote:** WarnThenError
> **Reasoning:** The self-hosting protocol needs it: add the check, migrate src, then make it an error, with one regen per step. The warning should carry the final code and message so docs and `--explain` do not change.
> **Concern:** If the warning stays too long, new code will lean on non-static initializers. Make it an error in the next release.

</details>

<details><summary><b>DevOps</b></summary>

> ## Q1. Rule for module-level initializers
> **Vote:** S
> **Reasoning:** S gives one diagnostic with one span, found from syntax alone. The LSP can report it on each keystroke with no call graph and no other files, and it never reports a false positive. P's cycle check is not local: an edit in file A raises an error on a `let` in file B. Through indirect calls, P has to over-report and name functions the user never called, and that is a message nobody can act on. sys and web are right that S's memo recipe spreads `State` through signatures. But the corpus has one such table, and widening S to P later breaks nothing.
> **Concern:** users will hit E1129 on a pure helper call such as `let t = build()` and think the rule is arbitrary. The help text must explain why and show the memo recipe word for word.
>
> ## Q2 (S-V1). Reads of another module `let`
> **Vote:** Deny
> **Reasoning:** Allowing reads brings back a dependency sort, a second code for cycles and an order rule. It also adds an aliasing hazard (`let mut seen = names` would share an immutable `List`). With reads denied, a cycle cannot exist, so no cycle diagnostic is needed. The fix stays local: make the source a `const`.
> **Concern:** "`let b = a` is an error" will surprise people. The E1129 label must say "read of module `let` `a`" and the help must suggest `const`.
>
> ## Q3 (S-V2). Empty-collection constructors
> **Vote:** Named
> **Reasoning:** An error on a spelling the user knows to be total and pure is a bad diagnostic: the message reads as a compiler bug. `Map.new[K, V]()` and `List.new[T]()` are the forms the existing `List()` help already suggests, so the static set must accept them. Each spelling costs one table row in the checker.
> **Concern:** the list can grow by request, one constructor at a time. The rule must stay "zero-argument, total" so the list has a clear test.
>
> ## Q4 (S-V3). String interpolation
> **Vote:** No
> **Reasoning:** Interpolation runs `Display.fmt`, which is user code that can panic, so it is a call in disguise. The label "string interpolation runs `Display`" says exactly what is wrong. A plain string literal stays const.
> **Concern:** `let greeting = "v{VERSION}"` with a `const` will feel like it should work. The help should point to the fix: write a `const` with a literal, or build the string in `main`.
>
> ## Q5 (S-V4). Function literals
> **Vote:** NoRule
> **Reasoning:** At module scope the only names in reach are module names, so a capture rule would say nothing. The body is checked like any fn body, and its row (with `State` if it reads a `let mut`) shows on the closure's type. A rule with no effect is spec text that tooling must still explain.
> **Concern:** someone may read "function literal is static" as "its body follows the static rules". The spec should say the body is not checked against the static list.
>
> ## Q6. Diagnostic
> **Vote:** OneNew
> **Reasoning:** E1101 means "not a const expression", but the static set is wider than const, so reusing it lies about which rule failed. E0508/E0509 say "the function returns …", and here there is no function, so reusing them gives a false message. One code (E1129) with a label for the kind of bad part (call, method call, `if`, block, interpolation, read of `let`, `return`/`?`) gives one `--explain` page and one LSP code action. The help text should be fixed and identical every time.
> **Concern:** if the label points at the whole initializer and not at the first bad part, users will not see which part to change.
>
> ## Q7 (S-V5). Rollout
> **Vote:** WarnThenError
> **Reasoning:** The self-host bootstrap needs this anyway, because src must be migrated between steps. The warning must already carry the final code and message, so `--explain`, the docs, LSP code actions and editor filters do not change when it becomes an error.
> **Concern:** a warning phase that ships to users without a fixed end release turns into a permanent warning. Tie the switch to error to the next release after src is migrated.

</details>

<details><summary><b>AI/ML</b></summary>

> ## Q1. Rule for module-level initializers
> **Vote:** S
> **Reasoning:** sys and web now cite my Phase A point: the memo fix makes a fixed table `let mut`, so `State` spreads to every reader (E0552, E0651). I weigh that again. The need is still rare: one test fixture, plus `node_columns_empty()` in src/, which is already `let mut` and pays no new `State` cost. For a model, S is one closed list checked on the line being written. P's cycle errors may name a function the model never touched, and that error shape gives the worst repair loops. Every S program is a P program, so S is the choice we can widen later without breaking code.
> **Concern:** models will often write `let table = build()` out of habit. If the help text does not show the memo recipe and its `State` cost the same way every time, they will guess at fixes. We should also open a follow-up to widen S (pure calls or a map literal) when real code needs it.
>
> ## Q2. Reads of another module `let`
> **Vote:** Deny
> **Reasoning:** with no reads, order and cycles cannot exist, so the spec has no order section for a model to learn. devops's aliasing point (`let mut seen = names` shares the list) is a second trap that Deny removes. The fix, "make it a `const`", is one fixed rewrite.
> **Concern:** `let b = a` failing surprises people, so the label must say "read of module `let` `a`; use a `const`".
>
> ## Q3. Empty-collection constructors
> **Vote:** Named
> **Reasoning:** models emit all of these spellings, and the compiler's own `List()` help already suggests `List.new()`. A static rule that rejects a spelling our own diagnostic recommends causes a pointless retry. Each form is total and pure.
> **Concern:** the list must stay in sync with the stdlib. If a new zero-argument constructor is added and not listed, models will hit a confusing error.
>
> ## Q4. String interpolation
> **Vote:** No
> **Reasoning:** it runs `Display`, which is user code. "Static = const plus a short list" stays one rule, and a plain string literal is still allowed.
> **Concern:** "{NAME}-v{MAJOR}" with only const parts is a natural thing to write, and the error must name the interpolation clearly.
>
> ## Q5. Function literals
> **Vote:** NoRule
> **Reasoning:** at module level a literal has no locals to capture. Its body is checked like any fn body and carries its own row. An extra rule would add a spec line that changes nothing.
> **Concern:** none of note.
>
> ## Q6. Diagnostic
> **Vote:** OneNew
> **Reasoning:** one code with a kind label ("function call", "block", "string interpolation", "read of module `let` `x`", "`return`/`?` has no enclosing function") is one pattern for a model to map to one fix. Reusing E0508/E0509 gives a false message ("in a function that returns..."), and a false message misleads repair.
> **Concern:** the help text must be the same each time and show the memo recipe with its `State` cost, or the code teaches nothing.
>
> ## Q7. Rollout
> **Vote:** WarnThenError
> **Reasoning:** the bootstrap protocol needs it. If the warning carries the final code and message, docs, `--explain` and training data stay the same when it becomes an error.
> **Concern:** a long warning phase lets new code that depends on the old behaviour appear, so the error step needs a fixed release.

</details>

<details><summary><b>Minimalism</b></summary>

> ## Q1: S
> **Reasoning.** S adds one short list next to `const`. With that list, four rules leave the spec: order, cycles through fn bodies, panic before `main`, and the handlers in force at init. P keeps all four and adds an analysis that has to be conservative for function values. Starting narrow is cheap, because widening later (pure calls, const fns) breaks no one.
> **Concern.** Users will want a computed table at module level and will keep asking to widen the list. We must answer with the memo recipe, not a quick carve-out.
>
> ## Q2: Deny
> **Reasoning.** If an initializer may read a module `let`, we need an order rule and a cycle code again. That brings back most of P's spec cost under S's name. A `const` ref covers the real case, and repeating a literal covers the rest.
> **Concern.** A user with a `let` list that cannot be a `const` (a list literal) cannot derive a second binding from it. That will look arbitrary until const covers list literals.
>
> ## Q3: Small
> **Reasoning.** `[]`, `Map()` and `Set()` already spell every empty collection. Each extra spelling is one more list item to learn, document and test, and it gives no new power.
> **Concern.** A user who writes `Map.new[Str, Int]()` gets an error for a form that means the same thing. The help text must name the accepted spelling.
>
> ## Q4: No
> **Reasoning.** Interpolation calls `Display`, which is user code. A static form must run no user code. Plain string literals stay const.
> **Concern.** None of note. Multi-line string literals with no `{}` parts must stay static, and the implementation must not treat every string as interpolation.
>
> ## Q5: NoRule
> **Reasoning.** A module-level function literal has no locals to capture, so a capture rule would forbid nothing. Its body is a fn body and is checked as one. The spec should state no rule that has no effect.
> **Concern.** None for the rule itself. The codegen must still not run the body at init.
>
> ## Q6: OneNew
> **Reasoning.** E1101 names the const judgment, and E0508/E0509 say "enclosing function", which is false here. A wrong message costs more than one new code. One code with a label per kind keeps the surface to a single entry.
> **Concern.** The label set (call, method call, block, `if`, `match`, interpolation, `let` read, `return`, `?`) can grow. Keep it to one code with labels, never a code per kind.
>
> ## Q7: ErrorNow
> **Reasoning.** The warning step belongs to the self-host bootstrap, between regens, not to a release. lib/ and examples/ need zero changes, and src/ migrates before release. A warning phase in a release only adds a temporary rule that the spec and users must then forget.
> **Concern.** An outside user with a computed initializer breaks on upgrade with no notice. The release notes must show the memo recipe.

</details>

#### AI-First review

Learnability, Consistency, Generability and Debuggability pass: the rule is one closed list beside `const`, and the error has one code and one span on the line being written. Token Efficiency fails: a computed lookup table needs the fill-on-first-use recipe in place of one line. 4/5 pass.

### Final Spec

```blink
const MAX_RETRIES = 5

let retries = MAX_RETRIES * 2                  // const expression
let names = ["ada", "bob"]                     // list literal
let mut seen: Map[Str, Int] = Map()            // empty-collection constructor
let double = fn(n: Int) -> Int { n * 2 }       // function literal; body not run at init

let table = build_table()                      // error[NonInitExpr]: function call
let copy = names                               // error[NonInitExpr]: read of module `let` `names`
let label = "v{MAX_RETRIES}"                   // error[NonInitExpr]: string interpolation
```

- The initializer of a module-level `let` or `let mut` is a static expression: a const expression, a list or tuple literal, a struct literal, an enum variant (each part static), a zero-argument empty-collection constructor, or a function literal (§2.12.1).
- No call, no read of a module `let` or `let mut`, no `if`/`match`/block/`with`, no string interpolation, no `return` or `?`.
- No user code runs before `main`. The order of initialization is not defined and cannot change a value; no cycle can occur.
- One diagnostic, `NonInitExpr` (E1129), per initializer: primary label on the first part that is not static, secondary labels on the rest; help gives the fix for the kind.
- Rollout: a warning that already carries the final code and message, then an error at a fixed release. This is a release plan, not spec text.
- A computed value is computed in `main`, or filled into a `let mut` on first use, which puts `State` in each reader's row (§4.16).

### Follow-ups the panel asked for

- Widen the static set later (pure calls, a map literal, or const functions) when real code needs it. Every S program stays valid under a wider rule.
- Keep the constructor list in step with the stdlib.
- Calling a module-level function literal must work before the spec points users at it.
