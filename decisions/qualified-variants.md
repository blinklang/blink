[< All Decisions](../DECISIONS.md)

# Qualified Variants in Expressions — Design Rationale

A pending amendment made a bare variant `X` an error in an expression when a type `X` was in scope. So with `type Color { Red, Green }` and `type Red { A, B }`, `let a = Red` was an error but `let d = Green` was legal. The owner found one enum that needs the qualifier for some variants and not others inconsistent, and proposed that every variant is always qualified in expressions. The owner asked for this panel before ruling. This ruling decides the expression spelling of a variant, the prelude exception, the forms the rule covers, the diagnostic, and which older rules change.

The owner, verbatim: "line 16 doesn't seem like it should be allowed if line 15 requires the fully qualified" (line 16 is `let d = Green`, line 15 is `let c = Color.Red`). Then: "everywhere. Every variant is always qualified in expressions." Then: "run one more panel on it though before abusing my bdfl powers too quickly".

This ruling supersedes in part [A Type Named Like a Variant](type-variant-shadow.md): E0554 now means `UnqualifiedVariant`. It amends [Bare Variant and Value Names](bare-variant-value-names.md), the *Variant spelling and the uppercase pattern rule* ruling and the *Variant hint positions and global-unique reach* ruling.

## Summary

| Q | Question | Result | Vote |
|---|---|---|---|
| Q1 | The expression spelling of a variant | A user variant is qualified in an expression; `Some`, `None`, `Ok`, `Err` stay bare; patterns do not change | 6-0 |
| Q2 | The bare prelude list (if Q1 = A) | Exactly `Some`, `None`, `Ok`, `Err`; the list is closed | 6-0 |
| Q3 | A user type named like a bare prelude variant (`type None {}`) | A type named one of the four is E1016, also at an import entry | 6-0 |
| Q4 | Forms the rule covers | `X`, `X(...)` and `X { ... }` | 6-0 |
| Q5 | A dotted head that is a bare prelude variant (`None.is_none()`, `Some(x).map(f)`) | Dotted-head step 3 stays for the four names only | 6-0 |
| Q6 | Error code for the new error (name `UnqualifiedVariant`) | Reuse E0554 as `UnqualifiedVariant` | 6-0 |
| Q7 | Narrowing of other rules | Narrow E1016 and W1011, retire E0519; E0518 goes to a follow-up | 6-0 |
| Q8 | Migration order (implementation note for the impl ticket, not spec text) | Warning with a machine fix, migrate, then error (implementation note, not spec text) | 5-1, Minimalism dissent |

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated
in independent-proposal → debate → vote rounds.

#### Phase A — Independent proposals

- **Systems:**

  > Runtime cost is zero for each option: resolution is static, and the C output is the same tag value. So my vote rests on compile cost, locality and what a reader can see at a site.
  >
  > ## Proposal S1 (my pick): qualify user variants in expressions, prelude variants stay bare
  >
  > ```blink
  > type Color { Red, Green }
  > type Shape { Circle { r: Float }, Dot }
  >
  > fn paint(c: Color) -> Str {
  >     match c {
  >         Red => "red"
  >         Green => "green"
  >     }
  > }
  >
  > fn main() ! IO {
  >     let a = Color.Red
  >     let s = Shape.Circle { r: 1.0 }
  >     let o: Option[Int] = Some(3)
  >     let r: Result[Int, Str] = Err("bad")
  >     let d = Green           // error[UnqualifiedVariant]: variant `Green` needs its enum
  >                             // help: write `Color.Green`
  > }
  > ```
  >
  > - Expressions: `X`, `X(...)` and `X { ... }` for a user variant must be `Enum.X`. Patterns stay bare (they find the type from the matched value).
  > - Prelude: `Some`, `None`, `Ok`, `Err` stay bare. They are a closed set of four names. They are reserved: E1016 already bans a value with those names; extend it to a type with those names. Then a bare `Some` always means one thing, in each module, with no search.
  > - `Option.Some` stays legal. 1462 bare prelude uses do not change.
  >
  > What changes:
  > - DECISIONS "Variant spelling" Q1: write-bare is reversed for user variants in expressions. Patterns keep it.
  > - Hint positions: no longer pick a user variant. They stay as type-check targets only.
  > - Global-unique step: deleted for expressions. E0519 goes away in expressions.
  > - E0554: subsumed. A type named `Red` no longer conflicts with anything, because bare `Red` in an expression is never a variant. W1011 for a type that hides a variant goes away.
  > - W1011 / E1016 for values: needed only for the four prelude names.
  > - Dotted-head step 3: only for prelude variants (`None.is_none()`).
  > - `JsonValue.Bool(true)`: already qualified. No special case.
  >
  > Compile cost: the global-unique step searches every `pub` enum of the package for each bare uppercase name. Worse, it makes each bare name depend on enums in other modules: a new `pub` enum in module B can change a site in module A. For incremental builds that is a dependency edge from each module to each enum of the package. S1 deletes that edge. Resolution of `Color.Red` is one lookup in the type namespace.
  >
  > Migration: unknown count of bare user-variant uses in src/ and lib/. The compiler knows each resolution today, so the help is machine-applicable and a one-time `blink fix` (or a script on the E-code output) rewrites the tree. Needs the 3-step bootstrap dance: add the error as a warning, migrate src, make it an error.
  >
  > Tradeoffs: more text in enum-heavy code (`TokenKind.LParen` in a lexer). A short alias (`type TK = TokenKind`, then `TK.LParen`) reduces it. A Swift-style `.LParen` with a hint could come later; YAGNI now.
  >
  > Cross-language: this is Rust's default (`Color::Red`, prelude `Some/None/Ok/Err` bare) without `use Color::*`. TS/Python/Kotlin always qualify. Go has no enums, but constants carry a package prefix.
  >
  > ## Proposal S2 (fallback): every variant qualified, prelude included
  >
  > Same as S1 but `Option.Some(3)`, `Result.Err(e)`. Fully uniform, and no reserved names. Cost: about 1460 edits and much noise on the most common code in the language. I vote against: the four prelude names are a closed set, so the special case is small and does not grow.
  >
  > ## Not recommended: keep the current rule
  >
  > It keeps the global-unique search, the cross-module dependency, and the owner's inconsistency (`Green` legal, `Red` not) that depends on a far-away type declaration.

- **Web/Scripting:**

  > ## Proposal W1 (recommended): qualify user variants in expressions; prelude variants stay bare; patterns stay bare
  >
  > ```blink
  > type Color { Red, Green }
  > type Shape { Circle(Float), Square(Float) }
  >
  > fn paint(c: Color) -> Str {
  >     match c {
  >         Red => "red"
  >         Green => "green"
  >     }
  > }
  >
  > fn main() ! IO {
  >     let a = Color.Red
  >     let s = Shape.Circle(2.0)
  >     let o: Option[Int] = Some(3)
  >     let r: Result[Int, Str] = Err("bad")
  >     let n: Option[Int] = None
  > }
  > ```
  >
  > The rule in one line: "In an expression, write `Type.Variant`. `Some`, `None`, `Ok` and `Err` are the only bare variants." A JS, TS, Python or Kotlin developer learns this in one minute, because it is what they already write (`Color.Red`, `Color.RED`). There is no hint list, no search order, and no "it depends what else is in scope".
  >
  > **Prelude variants.** `Some/None/Ok/Err` stay bare, and `Option.Some` etc. stay legal. They are four fixed names, a closed set that a user learns once. Rust users write them bare. Counts: ~1460 bare uses vs 10 qualified in the tree. Forcing `Option.Some(x)` would make the most common code in the language loud, for no gain in clarity. `JsonValue.Bool(true)` is a stdlib enum, not prelude, so it is qualified.
  >
  > **Patterns.** Bare stays, as today: the scrutinee type names the enum. `Color.Red =>` stays legal. This matches the owner proposal and Swift/Rust `use Enum::*` habits; the match arm is where bare reads best.
  >
  > **Rules that change or go away**
  > - DECISIONS "Variant spelling" Q1: "write bare" flips to "qualify" for expressions. The patterns half stays.
  > - Hint positions and global-unique reach: go away for expressions (keep for prelude only; trivial, they are unique). Patterns do not need them.
  > - E0519: no longer reachable in expressions; in patterns the scrutinee decides. Likely retire or keep only for a pattern with no known type.
  > - E0554 amendment: absorbed. A type named like a variant no longer matters in expressions.
  > - Dotted-head step 3 (`Green.label()`): goes away. `Name.x` is a value or a type path, never a bare variant. Simpler.
  > - E1016: narrows to prelude variants (`let Some = ...`). User variants are not bare names any more, so a `let Red` cannot hide one.
  > - W1011: narrows to prelude variants and patterns (a local named like a variant in a pattern position, if that can happen). The `type Red` hides `Color.Red` case goes away.
  >
  > **Diagnostic** (new, or reuse E0554 under a new name `UnqualifiedVariant`):
  > ```
  > error[E0554]: a variant needs its type name here
  >   --> main.bl:3:13
  >    |
  >  3 |     let a = Red
  >    |             ^^^ `Red` is a variant of `Color`
  >    = help: write `Color.Red`
  > ```
  > If two enums have `Red`, list both in `help:`. If no enum has it, the normal "unknown name" error. `blink fmt --fix` (or the LSP quick fix) can apply the rewrite, because the type is known.
  >
  > **Migration.** Mechanical: the compiler already resolves each bare site, so a one-shot rewrite tool can emit `Type.` in front. Prelude variants (the bulk) do not move. Cost is moderate and scriptable; needs the 3-step bootstrap dance.
  >
  > **Tradeoffs.** Pro: one rule, no scope surprises, readable without an IDE, matches TS/Python/Kotlin, LLMs write it right first time. Con: longer code at construction sites with long enum names (`HttpMethod.Get`); the prelude exception is one special case a user must learn (but it is the same exception Rust has).
  >
  > ## Proposal W2 (rejected by me): qualify everything, prelude too
  >
  > Consistent, but `Option.Some(x)` 468 times is noise. No mainstream language does this for Option. It would generate "why is Blink so verbose" complaints. No.
  >
  > ## Proposal W3 (rejected by me): keep current rule
  >
  > The owner example proves the problem: `let d = Green` legal, `let a = Red` an error, same enum. That is a Stack Overflow question every week. The current rule needs a resolution order of 4+ steps to explain; a 5-minute learner cannot hold it.

- **PLT:**

  > ## The fault in the current rule
  > The legality of bare `Green` depends on facts that are not at the site: no type `Green`, no second enum with `Green`. A new declaration somewhere else (a type, an import entry, a new prelude type) changes a legal site into E0554 or E0519. So bare variants in expressions are not stable when the program grows. The qualified form depends only on `Color` in scope: it is stable. Patterns do not have this fault: the scrutinee type always names one enum (checking position), so a bare pattern name is decided locally.
  >
  > ## P1 (I support): qualify every user variant in expressions; four prelude variants stay bare
  > ```blink
  > type Color { Red, Green }
  > type Red { A, B }                       // legal, no W1011: nothing is hidden
  >
  > fn paint(c: Color) -> Str {
  >     match c {
  >         Red => "red"                    // pattern: bare, decided by c's type
  >         Color.Green => "green"          // qualified pattern stays legal
  >     }
  > }
  >
  > fn main() ! IO {
  >     let a = Color.Red
  >     let d = Green                       // error[UnqualifiedVariant]
  >     let o: Option[Int] = Some(1)        // prelude: bare
  >     let r: Result[Int, Str] = Err("x")
  > }
  > ```
  > Rule: in an expression, a bare variant name is legal only for `Some`, `None`, `Ok`, `Err` (closed list). These four are reserved: E1016 and E0518 already stop a package value or struct with these names; add that a type named like one of them is an error, so they never meet E0554. `Option.Some` stays legal (10 sites). Other prelude enums (Ordering, JsonValue) get no exception.
  >
  > Diagnostic: `error[UnqualifiedVariant]: variant `Green` needs its enum` / `help: write `Color.Green``. Machine-applicable when the old resolution (hint, then global-unique) finds one candidate; else the help lists each. The old resolution steps live on only to make this help. I prefer to give E0554 this wider meaning and new name; a fresh code is also acceptable.
  >
  > What changes:
  > - Q1 "write bare" goes for user enums; the pattern rule (Q2, Q3) stays.
  > - Hint-directed and global-unique steps leave expression resolution. E0519 goes (no ambiguity can occur). The hint-position list stays for literals and for the help.
  > - E0554 as "named like a type" goes (subsumed).
  > - Dotted heads: step 3 goes. A head is a value or a type, two namespaces only. `Green.label()` becomes `Color.Green.label()`.
  > - W1011: a type, struct or module value can no longer hide a user variant in an expression, so those cases go. W1011 stays for a local named like a prelude variant.
  > - E1016 and E0518 for user variants have no reason left; I propose to narrow them to the prelude four in a follow-up, not in this ruling.
  >
  > Migration: `Some/None/Ok/Err` (about 1460 sites) do not change. User-variant bare uses need a count; the machine fix rewrites them. Order: migrate src/lib first (gen0 already accepts the qualified form), then add the error.
  >
  > Tradeoff: longer expressions for user enums; one fixed exception list. Gain: one spelling per enum, a site that a distant declaration cannot break, and smaller resolution and diagnostic rules.
  >
  > ## P2 (alternative): bare only at a checking position
  > A bare variant is legal only where the expected type names its enum (the hint list), exactly as in a pattern; `let d = Green` is an error, `let b: Color = Red` is legal even with `type Red` in scope. This is the bidirectional-typing reading and is uniform with patterns, but it reverses the owner choice that a hint does not help, and it keeps the hint list as a load-bearing part of the language.
  >
  > ## Rejected: P3, Haskell-style uniqueness
  > Forbid two reachable enums with a shared variant and any type named like a variant. Bare is then always safe, but a dependency can break a program by adding a variant.
  >
  > ## Cross-language
  > Rust is P1: `Color::Red` unless glob-imported, prelude re-exports `Some/None/Ok/Err` bare. Swift `.red` is P2. OCaml type-directed disambiguation needs warnings 41/42 for the fragility above. I do not propose an enum glob import (`use Color.*`): it brings back the global-unique fault.

- **DevOps:**

  > My test: one resolution path, one error code, one exact fix. Today a bare variant in an expression has six outcomes (local, module value, hint, global-unique, E0519, E0554), and W1011 explains the hidden ones.
  >
  > ## P1 (my vote): user variants qualified in expressions; prelude variants bare
  >
  > ```
  > type Color { Red, Green }
  > type Red { A, B }                  // legal, no warning: nothing is hidden
  > fn paint(c: Color) -> Str {
  >     match c {
  >         Red => "red"               // patterns unchanged
  >         Green => "green"
  >     }
  > }
  > fn main() ! IO {
  >     let c = Color.Red              // ok
  >     let d = Green                  // error[E0554]
  >     let o: Option[Int] = Some(3)   // ok: prelude
  > }
  > ```
  >
  > Diagnostic (reuse E0554, rename to `UnqualifiedVariant`):
  > ```
  > error[E0554]: variant `Green` needs its enum in an expression
  >   --> main.bl:11:13
  >    |
  > 11 |     let d = Green
  >    |             ^^^^^ help: write `Color.Green`
  > ```
  > The old global-unique search now only finds candidates for the help. One candidate: machine-applicable. Two or more: list each, not machine-applicable.
  >
  > Prelude: `Some`, `None`, `Ok`, `Err`, `Less`, `Equal`, `Greater` stay bare and always mean the prelude variant. A user variant with one of these names must be qualified, so it never competes. A user type named like a prelude variant (`type None {}`) becomes a declaration error (extend E1016's prelude clause to the type namespace), so bare `None` has one meaning in every module.
  >
  > Rules that change:
  > - Q1 "write bare": reversed for user variants in expressions. Patterns keep both forms.
  > - Hint positions and global-unique reach: retired for resolution. Hints still give a type to `None` and `Ok(x)`.
  > - E0519: goes away. A qualified name is never ambiguous, and prelude names cannot collide.
  > - E1016 variant clause: shrinks to prelude variants.
  > - W1011: goes away for expressions. It stays only for an irrefutable-pattern binder named like a variant, if the panel wants it.
  > - E0554 amendment: absorbed into the general rule.
  > - Dotted-head step 3: removed. `Red.x` is always the type or value `Red`.
  >
  > LSP: completion after `Color.` lists the variants; go-to-definition has one path.
  >
  > Migration: typecheck already knows the enum at each bare site, so the rewrite is exact. Plan: (1) add the check as a warning with a machine-applicable fix, `task ci`; (2) apply the fix across src/, lib/, tests/, sections/ examples; (3) make it an error. That is the 3-step bootstrap dance. Before the vote, count the user-variant bare sites; the brief does not have that number.
  >
  > Tradeoff: long names cost text (`HttpStatus.NotFound`); TS, Python, Kotlin and Rust (without `use Color::*`) accept that. A variant import form waits for a user request (YAGNI).
  >
  > ## P2: every variant qualified, prelude too
  >
  > `Option.Some(3)`, `Result.Ok(x)`. About 1,460 lines in src/ + lib/, about 6,900 in tests/ + sections/. No mainstream language does this for Option/Result, and LLMs write `Some(x)`. Reject.
  >
  > ## P3: keep the current rule plus the E0554 amendment
  >
  > Zero migration, but the owner's complaint stands: one enum needs the qualifier for some variants only, and the reason is a W1011 at a different place. Reject.
  >
  > Swift `.green` (with an expected type) is a possible later short form; not proposed.

- **AI/ML:**

  > ## Main problem (my domain)
  > Today a model must know the full type scope (imports, prelude, builtin types) to know if `Green` is legal. That fact is not local to the line. A model that writes `let d = Green` cannot see that a later import adds `type Green`. The same text then breaks. A rule that depends on far-away scope is the worst kind for generation: the model cannot check it while it writes.
  >
  > ## Proposal A (recommended): user variants always qualified in expressions; prelude four stay bare
  >
  > ```blink
  > type Color { Red, Green }
  >
  > fn paint(c: Color) -> Str {
  >     match c {
  >         Red => "red"
  >         Green => "green"
  >     }
  > }
  >
  > fn main() ! IO {
  >     let a = Color.Red
  >     let b: Option[Color] = Some(Color.Green)
  >     let e: Result[Int, Str] = Err("bad")
  >     let f = Green          // error[BareVariant]: a variant in an expression needs its enum
  >                            // help: write `Color.Green`
  > }
  > ```
  >
  > - Prelude: `Some`, `None`, `Ok`, `Err` stay bare in expressions (closed list of four, like Rust's prelude). `Option.Some` etc. stay legal, but bare is the one written form. These four are about 1460 sites in src+lib; models write them bare from Rust and Swift data.
  > - Patterns: no change. Bare finds the variant from the scrutinee type. `Color.Red =>` stays legal, because a model from Rust writes `Color::Red =>` and an error there helps no one.
  > - Diagnostic: one code (widen E0554 or a new code). Help is machine-applicable when one enum has the variant; it lists each `Enum.X` when more than one has it.
  >
  > Rules that change:
  > - DECISIONS "Variant spelling" Q1: "write bare" becomes "write qualified" for user variants in expressions.
  > - Hint positions: no longer give a user variant its type in expressions. They stay for patterns only, if at all.
  > - Global-unique reach: goes for expressions.
  > - E0519: goes for expressions (a qualified name is never ambiguous).
  > - E0554 amendment: subsumed by the new rule.
  > - W1011 (type hides variant) and dotted-head step 3: go. `Green.label()` becomes `Color.Green.label()`.
  > - E1016: keep for the prelude four only; a `let Red` no longer collides with a user variant in an expression.
  > - Invariant "a bare name denotes one entity": now true by the token alone.
  >
  > Migration: user-variant bare sites in src/lib (not counted yet; I expect hundreds). The compiler already knows which variant each site picks, so `blink fix` can rewrite all of them. The prelude sites do not change.
  >
  > Tradeoffs: +2 tokens a site (`Color.`); more for long enum names (`JsonValue.Bool(true)`). In exchange: no scope lookup, no hint list to learn, grep finds every use, and a reader (human or model) knows the meaning from the line alone. TS, Python, Kotlin and Rust (no glob import) all write the qualifier, so model priors support it.
  >
  > ## Proposal B (reject): every variant qualified, prelude included
  > `Option.Some(x)` at 1460 sites. Strong conflict with training data; models will write `Some(x)` and get an error on almost every file. Large token cost on the most common values in the language.
  >
  > ## Proposal C (reject): Swift `.Green` with an expected type
  > New syntax, small training data, and it brings back the hint list as a decision point.
  >
  > ## Proposal D (reject): keep the current rule
  > The legal set depends on non-local scope. This is the inconsistency the owner saw, and it is the hardest kind of error for a model to avoid.

- **Minimalism:**

  > Test: does the rule remove more rules than it adds? Today a hint-position list (9+ items), a global-unique search, values-first order, E0519, E1016, W1011 at dotted heads, dotted-head step 3 and E0554 all exist so a user can omit `Color.`. That is much spec for one saved word.
  >
  > ## Proposal M1 (my vote): user variants always qualified in expressions; the four prelude variants stay bare; patterns stay bare
  >
  > ```
  > type Color { Red, Green }
  > type Red { A, B }                      // legal, no warning: no bare variant to hide
  > fn paint(c: Color) -> Str {
  >     match c {
  >         Red => "red"                   // pattern: found from c's type
  >         Green => "green"
  >     }
  > }
  > fn main() ! IO {
  >     let a = Color.Red
  >     let b: Color = Color.Green
  >     let o = Some(1)                    // prelude: bare
  >     let r: Result[Int, Str] = Err("x")
  > }
  > ```
  >
  > Prelude: `Some`, `None`, `Ok`, `Err` stay bare. They are a fixed set of four, every reader knows them, and they have 1462 uses in src/ + lib/ against 10 qualified. `Option.Some` is still legal. This is one exception with a name list, not a resolution algorithm. Rust does the same: prelude variants bare, others `Enum::X`.
  >
  > Rules that go away for user variants:
  > - hint positions and the global-unique step (patterns use the scrutinee type, a separate mechanism);
  > - E0519 in expressions (a qualified name is never ambiguous);
  > - E0554 and dotted-head step 3 (`Red.x` is always the type `Red`);
  > - W1011 for a type that hides a variant; values-first order between a value and a user variant;
  > - E1016 shrinks to the four prelude names.
  > - Follow-up, not this ticket: E0518 (struct named like a variant) loses its reason, since `Name { }` can no longer be a variant. Panel can remove it later.
  >
  > Rules added: one. A bare user variant in an expression is an error.
  >
  > Diagnostic (one code; it replaces E0519 and E0554 in expressions):
  > ```
  > error[UnqualifiedVariant]: variant `Green` needs its enum
  >   --> main.bl:13:13
  >    |
  > 13 |     let d = Green
  >    |             ^^^^^ write `Color.Green`
  > ```
  > Machine-applicable when one enum declares `Green`; with two, the help lists each form.
  >
  > Migration: prelude uses need no change. User bare variants in expressions get the fix from `blink fix` (the compiler knows the resolution today). The 6-0 "write bare" style rule in DECISIONS "Variant spelling" Q1 flips for expressions; its pattern half stays.
  >
  > Tradeoffs: more characters at construction (`Color.Red` vs `Red`). In exchange: one spelling, no lookup order, and no guess if the bare form "reaches". TS, Python and Kotlin users always qualify.
  >
  > ## Proposal M2 (fallback): keep today's rule, drop the E0554 amendment
  >
  > A type is not a value, so a bare `Red` in an expression can only be the variant. Only `Red.x` collides; make that one case the error. This removes the owner's inconsistency (`Red` and `Green` both legal), adds no rule, and has zero migration. It keeps all the hint machinery listed above, so it is less subtraction than M1.
  >
  > ## Rejected
  > - Qualify prelude variants too: 1462 edits and noise in every program, to remove one four-name list. Bad trade.
  > - Swift-style `.Red` with an expected type: new syntax, and it keeps the hint list. Adds, does not subtract.

#### Phase B — Debate highlights

One round. Each seat read all six Phase A texts and answered the deduplicated options. All six seats backed the qualified-variant rule. Devops withdrew `Less`/`Equal`/`Greater` from the bare list, min withdrew M2, and plt withdrew P2.

- **Systems:**

  > Sys, B1: I still back Q-main (my S1).
  >
  > 1. Prelude list: only `Some, None, Ok, Err`. Ordering has about 14 bare uses in src/ + lib/. Code seldom builds an Ordering by hand, so `Ordering.Less` costs little. Keep the closed list as short as possible.
  > 2. A type named like a prelude variant: make it a declaration error in this ruling (extend E1016 to the type namespace). Without it, we keep E0554 alive for the prelude four, and bare `None` can mean two things.
  > 3. A user variant named like a prelude variant (`MyOpt.None`): it must be qualified in expressions, as devops says. Patterns use the scrutinee type, so there is no conflict there.
  > 4. Error code: a new code `UnqualifiedVariant`, and retire E0554. A released code number that changes its meaning confuses old docs, search results and model priors. This is a mild preference, and I accept the reuse.
  > 5. Narrow E1016 and W1011 in this ruling, because they follow directly from the rule. E0518 can go to a follow-up (min, plt).
  > 6. Migration: warning, then migrate, then error. The warning's machine-applicable fix is what drives the rewrite of about 2,000 sites. plt's order is safe too (gen0 already accepts the qualified form), but then we need a separate rewrite tool.
  >
  > Objection, devops: "Dotted-head step 3: removed. `Red.x` is always the type or value `Red`." For user variants, yes. But `None.is_none()` and `Some(x).map(...)` still have a bare prelude variant as the head. Keep step 3 for the four prelude names only, or state that those heads read as their variant. Item 2 makes that unambiguous.
  >
  > Note on plt: "The old resolution steps live on only to make this help." I accept this. The search runs only on the error path, so legal code keeps no cross-module dependency, and the compile-cost gain holds.
  >
  > stable, ready to vote

- **Web/Scripting:**

  > Web seat B1: I still back Q-main (my W1).
  >
  > 1. Prelude list: only the four, `Some, None, Ok, Err`. A closed list of four is easy to teach in one line. `Less/Equal/Greater` have about 14 uses. A JS/Python developer does not expect a bare `Less`, and `Ordering.Less` is easy to read. A list of seven gets the question "why these and not JsonValue?".
  > 2. A user type named like a prelude variant (`type None {}`): make it a declaration error (sys, plt, devops). Then a bare `None` has one meaning in every file.
  > 3. A user variant named like a prelude one (`MyOpt.None`): it is legal, but you must qualify it in an expression, as the rule already says. A pattern with a `MyOpt` match value still finds it bare. No extra rule.
  > 4. Code: I have no strong view. Reuse E0554 with the new name `UnqualifiedVariant`, because the E0554 amendment is not on main yet, so this code number has no users. The name is what the user reads.
  > 5. Narrow W1011 and E1016 in this ruling. If we do not, users get errors with no purpose (an E1016 for `let Red = 1`). E0518 can wait for a follow-up.
  > 6. Use warning, then migrate, then error. tests/ has about 1,800 sites, and the warning plus a machine fix makes the change safe for users. It is also the bootstrap dance.
  >
  > Objections:
  > - plt P2: "`let b: Color = Red` is legal even with `type Red` in scope". This keeps the owner's inconsistency in a new form: whether `Red` is legal then depends on an annotation. A user still asks "why does this line work and that one not?". Reject.
  > - Scope gap: some seats write "`X` / `X(...)`", but sys writes "`X`, `X(...)` and `X { ... }`". The ruling must name all three forms. If it does not, `Circle { r: 1.0 }` stays a bare variant.
  >
  > stable, ready to vote

- **PLT:**

  > PLT B1: I still back Q-main (my P1). I drop P2.
  >
  > 1. Prelude list: the four only (`Some, None, Ok, Err`). Reserving `Less/Equal/Greater` stops users from naming their own variants `Equal` and so on, and it saves only 14 sites. Ordering is qualified like any other stdlib enum.
  > 2. A type named like one of the four must be a declaration error (E1016 widened to the type namespace). This is required, not optional. Without it, bare `None` can meet a type `None`, and the E0554 case comes back for the prelude.
  > 3. A user variant `MyOpt.None`: that follows from the rule. It is qualified in expressions. In a pattern the type of the matched value decides, so `match m { None => }` on a MyOpt is MyOpt.None. Agree with devops.
  > 4. Code: either is acceptable. Weak preference for renaming E0554, because its old meaning is a sub-case of the new one.
  > 5. I change my position. Narrow E1016 and W1011 in this ruling, because they follow directly from the rule. E0518 goes to a follow-up, because it has other clauses (a variant named like its own enum).
  > 6. Order: this is implementation, not spec. Warning, then migrate, then error is practical, because the machine fix comes from the diagnostic. No user-facing warning release (pre-1.0).
  >
  > Objections:
  > - web: "E0519 ... keep only for a pattern with no known type". A refutable pattern always has a scrutinee type (Q2 pattern rule), so that case does not occur. Retire E0519.
  > - web: "keep for prelude only" (hints), and aiml: "They stay for patterns only, if at all". Patterns never use the hint list; they use the type of the matched value. For the prelude four, an expected type only infers `T` in `None`/`Ok(x)`. It does no name resolution. Write it that way.
  > - min M2: "a bare `Red` in an expression can only be the variant". That holds for a type, but M2 keeps the global-unique step. A far-away new enum or import still changes or breaks a site (E0519). That is the fault the owner saw.
  >
  > stable, ready to vote

- **DevOps:**

  > devops B1. I still back Q-main (my P1).
  >
  > 1. Prelude list: I drop Less/Equal/Greater and accept the four. There are only 14 bare Ordering uses in src+lib, and a list of four is easier to teach and to put in a diagnostic. Ordering becomes `Ordering.Less`.
  > 2. `type None {}` must be a declaration error. Extend the prelude clause of E1016 to the type namespace. Without this, bare `None` needs a scope search again.
  > 3. A user variant named like a prelude variant (`MyOpt.None`) stays legal where it is declared. In an expression, bare `None` is always `Option.None`. In a pattern, the scrutinee type decides. The spec must say this in one sentence, or users will expect E0519.
  > 4. Error code: E0554 has never been on main (rg finds it in no src/ or sections/ file on main), so renaming it costs nothing. Give the new rule the name `UnqualifiedVariant` and either E0554 or a fresh number. I do not mind which.
  > 5. W1011 must narrow in this ruling. If it does not, it warns "hides variant" on `type Red` and `let Red = 5`, where nothing is hidden: a false warning on day one. E1016 narrowing: I also want it in this ruling, because otherwise `fn Red()` gives a false error. E0518 can go to a follow-up.
  > 6. Migration order: plt's order (migrate first, then the error) is acceptable, on one condition. The rewrite must use the compiler's resolution, not a text pattern, because the moderator's 235/1,800 estimate has false hits. The warning step is the simplest way to get that rewrite, so I still prefer warning, then fix, then error.
  >
  > Objections:
  > - web: "`blink fmt --fix` (or the LSP quick fix) can apply the rewrite". fmt does not resolve types, so it cannot know `Color`. The fix belongs to the compiler's machine-applicable help and to the LSP code action, not to fmt.
  > - web: E0519 "keep only for a pattern with no known type". A refutable pattern always has a scrutinee type. Retire E0519.
  > - plt P2: it keeps the hint list as a part of the language that changes what code means, and it reverses the owner's choice. No.
  >
  > stable, ready to vote

- **AI/ML:**

  > aiml B1: I still back Q-main (my Phase A first choice).
  >
  > 1. Prelude list: only `Some, None, Ok, Err`. Models learn a list of four quickly, and four covers about 1,460 sites. `Less/Equal/Greater` add only about 14 bare sites. Rust models write `Ordering::Less` qualified anyway, so `Ordering.Less` matches their priors. Objection to devops: "`Some`, `None`, `Ok`, `Err`, `Less`, `Equal`, `Greater` stay bare". Each name you add to the list is one more fact a model must remember, for almost no saved text.
  > 2. A type named like a prelude variant: make it a declaration error (sys, plt, devops). Without this, E0554 stays alive for the four names, and a bare `None` again depends on scope that the model cannot see.
  > 3. A user variant named like a prelude variant: state it outright. It must be qualified in expressions (`MyOpt.None`), and bare `None` always means `Option.None`. Patterns still find it from the scrutinee type.
  > 4. Error code: use a new code `UnqualifiedVariant` and retire E0554. Old docs, issues and training data that show E0554 with its old meaning would mislead models. If E0554 never shipped on main, reuse is fine. Low stakes.
  > 5. Narrowing: narrow E1016 and remove the W1011 type-hides-variant case in this ruling, because the new rule makes them dead text. E0518 can go to a follow-up. Objection to min: "E0518 (struct named like a variant) loses its reason, since `Name { }` can no longer be a variant". That is true in expressions only. Patterns stay bare, so `Red { .. }` in a pattern can still read as a struct pattern or a variant pattern. E0518 keeps that reason. Check this in the follow-up; do not assume it.
  > 6. Migration order: warning with a machine-applicable fix first, then migrate, then error (sys, devops). That warning is the tool that does the migration, and it gives the same rewrite in src, lib, tests and sections examples. plt's order is also acceptable.
  >
  > stable, ready to vote

- **Minimalism:**

  > min Phase B round 1. I still back Q-main (my M1). I drop M2.
  >
  > 1. Prelude list: four only (`Some, None, Ok, Err`). Objection to devops: "`Some`, `None`, `Ok`, `Err`, `Less`, `Equal`, `Greater` stay bare". Ordering has 14 bare uses in src+lib. A fifth to seventh exception for 14 sites is the wrong trade. Also, `Less`/`Equal`/`Greater` are common names for user enums, and reserving them costs users. Write `Ordering.Less`.
  > 2. Type named like a prelude variant: make it a declaration error (one clause added to E1016). This removes the last collision for the four names, so bare `None` has one meaning everywhere and dotted-head step 3 has no conflict left.
  > 3. User variant named like a prelude variant (`MyOpt.None`): no new rule. It follows from Q-main: you must qualify it, and bare `None` is always the prelude variant. Say so in one sentence of the spec, not as a separate rule.
  > 4. Error code: reuse E0554 and rename it `UnqualifiedVariant`. Its old meaning disappears, so a reused code adds no new code. This changes my Phase A text, and I accept the change.
  > 5. Narrowing: put E1016 and W1011 narrowing and the removal of dotted-head step 3 for user variants in this ruling. They follow directly from it, and leaving them in place keeps dead rules in the spec. Objection to plt: "narrow them to the prelude four in a follow-up, not in this ruling". Leave only E0518 to a follow-up, because it has its own reason (the brace literal) to check.
  > 6. Migration order: migrate src/lib/tests first, then add the error (plt). gen0 already accepts `Color.Red`, so a warning stage only adds a temporary rule and a third step. The fix tool can use the current resolution to write each rewrite.
  >
  > stable, ready to vote

#### Phase C — Final vote

Each seat voted alone on a silent ballot.

- **Q1: The expression spelling of a variant** (6-0, for A)

  > - A: Q-main. In an expression, a user variant must be qualified (`Color.Green`). A closed list of prelude variants stays bare, and their qualified form stays legal. Patterns do not change.
  > - B: Qualify every variant, prelude variants too (`Option.Some(3)`).
  > - C: Keep the current rule plus the pending E0554 amendment.
  > - D: Keep the current rule and drop the E0554 amendment; only the dotted-head collision `Red.x` is an error (min M2, withdrawn in B1).
  > - E: Bare is legal only at a checking position (hint list) (plt P2, withdrawn in B1).

  - **Systems:** A
    - Reasoning: Resolution of `Color.Green` is one lookup in the type namespace. Code that compiles does not depend on enums in other modules, so the global-unique search and its incremental-build dependency go away. The four prelude names cost nothing, because they are fixed and need no search.
    - Concern: Code with many enum values (lexers, state machines) gets long lines, and users may ask for a glob import that brings the search back.
  - **Web/Scripting:** A
    - Reasoning: It is what TS, Python and Kotlin developers already write (`Color.Red`), and the rule fits in one line with one four-name exception. It removes the owner's inconsistency: whether a line is legal no longer depends on a type declared somewhere else.
    - Concern: code with many enum values (lexers, state machines) gets longer, and users will ask for a short form, such as an enum import.
  - **PLT:** A
    - Reasoning: The qualified form depends only on the enum name in scope, so a declaration somewhere else cannot change or break the site. Patterns stay bare because the type of the matched value always names one enum, so the decision stays at the site. C and D keep the global-unique search, and that search is the source of the fault.
    - Concern: The spec text may leave the hint machinery partly in place for user variants, which gives two paths to the same result.
  - **DevOps:** A
    - Reasoning: One resolution path for user variants. The error has one exact fix (`Color.Green`) that the compiler can apply. Completion after `Color.` lists the variants. The prelude four stay bare, so the most common code does not change.
    - Concern: A user who writes a long enum name in many places can find the qualifier too long, and asks for a glob import that brings back the scope search.
  - **AI/ML:** A
    - Reasoning: Under this option, the code on one line tells whether a bare variant is legal. A model does not need the full type scope, which it cannot see while it writes. It matches TS, Python, Kotlin and Rust (with no glob import) for user enums, and Rust for `Some/None/Ok/Err`, so model priors give the correct form first time.
    - Concern: Models trained on the old "write bare" examples in sections/ and tests/ will make the error until those examples are rewritten.
  - **Minimalism:** A
    - Reasoning: A removes the hint-directed and global-unique steps from expression resolution, removes E0519 and E0554-as-type-collision, and removes dotted-head step 3 for user variants. It adds only one rule and one list of four names. B adds noise at about 1460 sites to remove a four-name list. C and D keep all the existing resolution steps.
    - Concern: users will ask for an import form such as `use Color.*`. That form brings back the global-unique search, so the panel must refuse it until users show a real need for it.

- **Q2: The bare prelude list (if Q1 = A)** (6-0, for A)

  > - A: `Some, None, Ok, Err`.
  > - B: Those four plus `Less, Equal, Greater` (devops Phase A, withdrawn in B1).

  - **Systems:** A
    - Reasoning: Keep the closed list as short as possible. Ordering has about 14 bare uses, and code seldom builds one by hand, so `Ordering.Less` costs little.
    - Concern: Pressure to add more names later, one at a time, until the list is not small.
  - **Web/Scripting:** A
    - Reasoning: A list of four that every Rust or Swift user already knows is easy to teach. If `Less/Equal/Greater` are also on the list, users ask "why these and not JsonValue?". They have only about 14 uses, and `Ordering.Less` is easy to read.
    - Concern: users from Rust who write a bare `Less` get an error, but the help line gives the fix.
  - **PLT:** A
    - Reasoning: Four names that the language fixes and that every reader knows, as in Rust's prelude. Reserving `Less/Equal/Greater` stops users from naming their own variants with common words, and it saves about 14 sites.
    - Concern: Users will ask for more names on the list. The list must stay closed, and only a panel vote can change it.
  - **DevOps:** A
    - Reasoning: Four names fit in one line of the diagnostic and of the docs. Ordering has only 14 bare uses in src/ + lib/, so `Ordering.Less` costs little.
    - Concern: Users from Rust write `Less` bare and get the error, but the machine-applicable fix covers it.
  - **AI/ML:** A
    - Reasoning: Four names cover about 1,460 sites. `Less/Equal/Greater` save about 14 sites and add three facts to remember, and Rust models already write `Ordering::Less` qualified.
    - Concern: A user can ask why `Ordering` is not on the list. The spec must give a short reason (the list is the Option and Result variants only).
  - **Minimalism:** A
    - Reasoning: Ordering has 14 bare uses, and that number does not justify three more exceptions. Also, `Less`, `Equal` and `Greater` are common names for user enums, so reserving them costs users. A closed list of four is easy to learn, and it stays four.
    - Concern: code that sorts gets slightly longer (`Ordering.Less`).

- **Q3: A user type named like a bare prelude variant (`type None {}`)** (6-0, for A)

  > - A: A declaration error (E1016's prelude clause extended to the type namespace).
  > - B: Legal.

  - **Systems:** A
    - Reasoning: If a type can be named `None`, then bare `None` needs a check against the type namespace again, and E0554 stays for the prelude. Reserving the names keeps one meaning in every module, with no lookup.
    - Concern: An existing user type named `Ok` or `None` breaks; the error must give a clear rename help.
  - **Web/Scripting:** A
    - Reasoning: Then a bare `None` has one meaning in every file, with no lookup. A user who declares `type None` makes code that confuses every reader, so an error at the declaration is the most useful place to stop it.
    - Concern: a dependency that already declares such a type breaks, but none is likely.
  - **PLT:** A
    - Reasoning: The rule needs this so that bare `None` names exactly one entity in every module. If `type None` is legal, the E0554 conflict comes back for the prelude.
    - Concern: An imported type with one of these names from a dependency needs the same check at the import entry. Write this down so that it does not stay a gap.
  - **DevOps:** A
    - Reasoning: Then a bare `None` has one meaning in every module, and the LSP, hover and the diagnostic need no scope search. Without it, the E0554 collision comes back for the four names.
    - Concern: A dependency that already declares `type None` breaks when this lands; the error must say "rename the type".
  - **AI/ML:** A
    - Reasoning: If the type is legal, a bare `None` again depends on scope that is not at the site, and the E0554 case comes back for four names. Then a bare `None` means one thing in every module.
    - Concern: A dependency that declares `type None` causes an error at import, and the help must give the alias fix.
  - **Minimalism:** A
    - Reasoning: One clause removes the last collision for the four names. With it, a bare `None` has one meaning in every module, and Q5 needs no rule to break ties.
    - Concern: a user who ports a type called `None` or `Ok` must rename it. This is rare.

- **Q4: Forms the rule covers** (6-0, for A)

  > - A: `X`, `X(...)` and `X { ... }`.
  > - B: `X` and `X(...)` only.

  - **Systems:** A
    - Reasoning: The brace form `X { ... }` is a construction site like the other two. If it stays bare, the hint search stays alive for one form only, and the rule is not uniform.
    - Concern: None from my domain.
  - **Web/Scripting:** A
    - Reasoning: A rule that covers `Circle(1.0)` but not `Circle { r: 1.0 }` is the same kind of inconsistency the owner objected to. A user should not need to know which form of construction is exempt.
    - Concern: none in my domain. The brace form already has the struct-in-scope step, which the implementation must delete cleanly.
  - **PLT:** A
    - Reasoning: The rule is about which entity a bare variant name denotes. The payload form does not change that. If `Circle { r: 1.0 }` stays bare while `Circle(1.0)` must be qualified, one enum again has two spellings, which is the fault the owner saw.
    - Concern: The struct-in-scope step in the brace-form resolution order must be rewritten, not only extended.
  - **DevOps:** A
    - Reasoning: If the rule leaves out `X { ... }`, the brace form still needs a scope search and a second diagnostic path. One rule for all three forms gives one code and one fix.
    - Concern: The brace form interacts with E0518, which goes to a follow-up; the spec text must not let them contradict each other before that.
  - **AI/ML:** A
    - Reasoning: Three forms in one rule mean the model has no exception to learn. If `X { ... }` stays bare when `X(...)` cannot, a model gets it wrong because one form is not like the others.
    - Concern: The brace form with a carrier hint (bare struct-style payload) must have its own spec example, or models will keep the old bare form there.
  - **Minimalism:** A
    - Reasoning: One rule for all three spellings. If the rule leaves out `X { ... }`, a bare brace variant still needs the old resolution steps, and E0518 keeps its reason. Covering all three forms also lets the E0518 follow-up remove that error cleanly.
    - Concern: brace-variant construction in tests needs the most rewriting.

- **Q5: A dotted head that is a bare prelude variant (`None.is_none()`, `Some(x).map(f)`)** (6-0, for A)

  > - A: The four prelude names at a dotted head read as their variant (step 3 kept for the four only); step 3 goes for user variants.
  > - B: Step 3 goes entirely; `None.x` is never a variant head.

  - **Systems:** A
    - Reasoning: `Some(x).map(f)` and `None.is_none()` are common, and the head can only be the prelude variant once Q3 reserves the names. It is a fixed check against four names, not a search.
    - Concern: A spec writer may forget to state the four-name limit, and step 3 grows back for user variants.
  - **Web/Scripting:** A
    - Reasoning: If a bare `None` is legal in an expression, `None.is_none()` must also be legal, or users get a surprise error on a form that looks correct. Keeping step 3 for only the four names is consistent with Q1.
    - Concern: the spec text must state clearly that step 3 applies only to the four names, so that readers do not take it to apply to user variants.
  - **PLT:** A
    - Reasoning: Compositionality. If `None` is a legal expression, then `None.is_none()` must mean a method call on that expression. Any other rule makes a dotted head different from a parenthesized `(None).is_none()`. `Some(x).map(f)` is a postfix on a call, not a bare dotted head, so the step does not apply to it.
    - Concern: The step 3 text must name the four exactly, so that it does not seem to allow user variants at a head.
  - **DevOps:** A
    - Reasoning: If `None` is legal but `None.is_none()` is an error, the owner's inconsistency comes back inside the prelude. Q3-A makes the head unambiguous, so keeping step 3 for the four costs no search.
    - Concern: The spec must say that step 3 covers only the four names, or an implementer keeps it for user variants.
  - **AI/ML:** A
    - Reasoning: A bare `None` is a legal expression. So `None.is_none()` must also be legal, as postfix on any other expression is. If `None` is legal by itself but not as a receiver, that is one more decision point and makes for an error message that is hard to understand.
    - Concern: The spec must say that the four names are the only bare dotted heads that are variants, or step 3 can grow again later.
  - **Minimalism:** A
    - Reasoning: Bare `None` is a legal expression. `.x` on a legal expression has to work without a special case. Q3 A removes the conflict, so step 3 for the four names costs nothing. B adds an exception: `None` is legal, but `None.x` is not.
    - Concern: none of substance. The spec text must make clear that step 3 covers the four names only.

- **Q6: Error code for the new error (name `UnqualifiedVariant`)** (6-0, for A)

  > - A: Reuse E0554 (never on main) with the new name and meaning.
  > - B: A fresh code; E0554 is retired.

  - **Systems:** A
    - Reasoning: E0554 never reached main, so no released doc, user or model knows the old meaning. My B1 concern was about a released code, and it does not apply. Reuse saves a number.
    - Concern: Pending branch text that uses E0554 with the old meaning must be rewritten before it lands.
  - **Web/Scripting:** A
    - Reasoning: E0554 never shipped on main, so this code number has no users and reusing it costs nothing. The name `UnqualifiedVariant` is what users read and search.
    - Concern: notes in the worktree branch that use the old meaning of E0554 must be updated, or the history becomes confusing.
  - **PLT:** A
    - Reasoning: E0554 is not on main, and its pending meaning is a sub-case of the new one. One code for one rule.
    - Concern: Readers of the pending branch may see the old meaning; the branch text must be updated in the same change.
  - **DevOps:** A
    - Reasoning: E0554 has never been on main, so no user, `@allow` or doc depends on its old meaning. Reusing it saves a code number and changes nothing for a user.
    - Concern: The pending branch text that uses the old meaning of E0554 must be rewritten in the same change, or two meanings of one code are on record.
  - **AI/ML:** A
    - Reasoning: E0554 never shipped on main, so no old docs or training data show its old meaning. If we reuse it, the code list stays shorter.
    - Concern: Branch text and panel notes that use the old meaning of E0554 must be rewritten before the ruling lands.
  - **Minimalism:** A
    - Reasoning: E0554 never reached main, so reusing it retires nothing and adds no code. A fresh code would leave a gap in the code numbers for no gain.
    - Concern: the branch text and its tests must change E0554's old meaning in one commit, so that no doc shows both meanings.

- **Q7: Narrowing of other rules** (6-0, for A)

  > - A: In this ruling, narrow E1016 and W1011 to what the new rule still needs; retire E0519; E0518 goes to a follow-up ticket.
  > - B: All narrowing (E1016, W1011, E0518) in a follow-up ticket; this ruling retires only E0519.

  - **Systems:** A
    - Reasoning: The narrowing of E1016 and W1011 follows directly from the rule. If we leave them as they are, the spec has rules that protect a case that cannot happen. E0518 touches structs, so a separate ticket is correct.
    - Concern: The follow-up ticket for E0518 stays open for a long time.
  - **Web/Scripting:** A
    - Reasoning: If E1016 and W1011 stay wide, users get errors and warnings with no purpose (E1016 on `let Red = 1`) the day the new rule lands. Narrow them in the same change, so that the diagnostics a user sees always agree with the rules.
    - Concern: the ruling becomes larger, and a narrowing step could be missed. The impl ticket needs one test for each narrowed case.
  - **PLT:** A
    - Reasoning: The E1016 and W1011 cases for user variants have no reason left once a bare user variant never resolves in an expression. If we keep them, the rules forbid things that can no longer be ambiguous. E0518 has other clauses, so it is a separate question.
    - Concern: W1011 may not be reduced far enough: it must stay for a local or a pattern binder named like one of the four.
  - **DevOps:** A
    - Reasoning: If W1011 stays as it is, it warns "hides variant" on `type Red` and `let Red = 5` where nothing is hidden. E1016 then rejects `fn Red()`, which is harmless. A false warning and a false error on day one are worse than a larger ruling.
    - Concern: E0518 is left in the follow-up with no reason to exist, and the follow-up ticket can wait a long time.
  - **AI/ML:** A
    - Reasoning: Rules that the new rule makes dead still look valid to a model that reads the spec, and they show rules that do not apply. Narrow E1016 and W1011 and retire E0519 now. E0518 still has a reason in patterns (`Red { .. }` reads as both a struct and a variant), so it needs its own check.
    - Concern: The narrowed E1016 and W1011 text can leave old examples in sections/ that still show the user-variant case.
  - **Minimalism:** A
    - Reasoning: The narrowing of E1016 and W1011, and the retirement of E0519, follow directly from Q1. If these narrowings wait, the spec keeps rules that nothing can trigger. E0518 has its own reason (the brace literal), so it goes to a follow-up, where the panel can check that reason separately.
    - Concern: the ruling's text must list exactly which W1011 cases stay, or the narrowed rules will drift.

- **Q8: Migration order (implementation note for the impl ticket, not spec text)** (5-1, Minimalism dissent, for A)

  > - A: Warning with a machine-applicable fix, migrate src/lib/tests/sections, then error.
  > - B: Migrate first (rewrite from compiler resolution), then add the error.

  - **Systems:** A
    - Reasoning: The warning's machine-applicable fix is the rewrite tool, so we do not build a second one. It also follows the bootstrap protocol: add, migrate, remove.
    - Concern: About 2,000 warnings in tests/ can hide other warnings until the migration is done.
  - **Web/Scripting:** A
    - Reasoning: A warning that comes with a machine fix gives anyone who has code outside the tree a safe path. It is also the bootstrap dance. About 1,800 test sites are easier to move with a fix tool than by hand.
    - Concern: the warning stage must not last for many releases, or "bare is fine" becomes the habit in new code.
  - **PLT:** A
    - Reasoning: The machine fix comes from the diagnostic, so emitting a warning first gives the rewrite for free and keeps each bootstrap step safe. This is an implementation note, not spec text.
    - Concern: The warning stage must not reach a release; pre-1.0, the user sees only the error.
  - **DevOps:** A
    - Reasoning: The warning step makes the compiler produce the exact rewrite, so the migration does not use a text pattern with false hits. The same fix then serves users outside the tree.
    - Concern: The warning stage must be short. If it stays long, new code keeps bare variants and the error step breaks more code.
  - **AI/ML:** A
    - Reasoning: The warning with a machine-applicable fix is the tool that does the migration. It gives one exact rewrite in src, lib, tests and spec examples, and users get the same tool.
    - Concern: The warning can stay in place too long and the error never lands. The impl ticket must make "change to error" its own step.
  - **Minimalism:** *(dissent)* B
    - Reasoning: gen0 already accepts the qualified form, so migrating first needs no temporary warning and no third step. The current resolution writes each rewrite exactly. The error is added last, against a tree that is already clean.
    - Concern: if a site is missed, it fails only when the error lands. Run the full corpus before the error commit.

### Final Spec

```blink
type Color { Red, Green }
type Red { A, B }                 // legal: no bare variant to collide with
type QueryError { NotFound { msg: Str }, Timeout { ms: Int } }

fn paint(c: Color) -> Str {
    match c {
        Red => "red"              // a pattern: the variant `Color.Red`, from the type of `c`
        Green => "green"
    }
}

fn main() {
    let a = Color.Red                         // a user variant: qualified
    let e = QueryError.NotFound { msg: "x" }  // the brace form: qualified
    let o = Some(1)                           // a prelude variant: bare
    let p = Option.Some(1)                    // legal: the qualified form of a prelude variant
    let n = None.is_none()                    // dotted-head step 3: the four names only
    let k = Ordering.Less                     // Ordering is qualified like any enum
    let r = Red.A                             // a type path: variant `A` of the type `Red`
    let g = Green                             // error[E0554]: variant `Green` needs its enum in an expression
                                              // help: write `Color.Green`
}

type None { Empty, Full }                     // error[E1016]: a type named like a prelude variant
```

- In an expression, a user variant carries its enum: `Enum.Variant`, `Enum.Variant(...)` and `Enum.Variant { ... }`. A bare user variant is `UnqualifiedVariant` (E0554). An expected type never makes the bare form legal.
- The bare list is exactly `Some`, `None`, `Ok` and `Err`, the variants of `Option` and `Result`. The list is closed; only a panel vote changes it. `Ordering`, `JsonValue` and every other enum are qualified. The qualified form of the four stays legal.
- Patterns do not change: a bare uppercase name in a pattern names a variant of the type of the matched value, and the qualified pattern stays legal.
- A value or a type named `Some`, `None`, `Ok` or `Err` is E1016, also at an import entry. The help says to rename, or to alias at the import entry.
- Dotted-head step 3 covers only the four prelude names. `Red.x` is always the type or the value `Red`.
- E0554 help: machine-applicable when one candidate enum has the variant; when several have it, the help lists each qualified form.
- An expected type types a literal and infers `T` for the four names. It does no name resolution. The global-unique search survives only to find candidates for the help.
- W1011 covers only a local or pattern binder named like one of the four. E1016 narrows to the four names. E0519 is retired. E0518 is not changed here; a follow-up checks it.
- Implementation order (Q8, not spec text): a warning with a machine-applicable fix, then migrate the tree, then the error.
