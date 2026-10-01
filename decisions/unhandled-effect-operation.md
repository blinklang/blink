[< All Decisions](../DECISIONS.md)

# Unhandled Effect Operation — Design Rationale

**Gap:** when a program performs an operation of a user-declared effect and no handler is installed, the operation answers a default value: `Err` for a `Result`, an empty list, `None`, or zero. For `Map`, `Set` and `Bytes` the default is a null handle that crashes on first use, and an operation that returns `Never` returns normally. The spec said that user-defined effects have no default handler (§4.12) and that unhandled operations "bubble up to the nearest enclosing handler" (§4.7.1). It did not say what happens when there is no such handler.

The MVCE in the gap report:

```blink
effect Zzstore {
    effect Fetch { fn zzget() -> Int }
}
fn main() {
    // no handler installed
    assert(zzstore.fetch.zzget() == 0)
}
```

Under §4.4 a sub-effect creates no handle of its own, so the call is spelled `zzstore.zzget()`. The panel's Phase D quotes keep the report's spelling; see *Phase D* for the correction.

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in independent-proposal → debate → vote rounds. Phase B ran one round. Q6 tied 3-3 in Phase C, so Phase D ran one focused round on Q6. The Systems seat's session ended twice on a tool error; its Phase A text is the part that was saved, and a replacement Systems seat cast the Phase D vote from the earlier seat's record.

#### Phase A — Independent proposals

**Systems:**

> # Sys Phase A — ee5e9m
>
> ## Proposal S1: compile error at `main`, panic stub at the root vtable
>
> **Position:** an unhandled user-effect op is an error, never a default value. Two layers:
>
> 1. **Static (zero cost).** Every non-`main` fn declares its row, so the only place a user effect can go unhandled is `main`'s transitive row. A user-declared effect that reaches `main` outside any `with` that discharges it is a new compile error, E05xx `UnhandledEffectInMain` (same shape as `UnhandledEffectInTest`). This makes §4.12's existing promise ("the compiler forces you to explicitly wire up your domain effects") true; today nothing enforces it. "main implicitly holds all effects" stays true for built-ins, whose stdlib default handlers discharge them.
>
> 2. **Dynamic (backstop).** Partial handlers auto-delegate omitted ops via `default.op(args)`, and handlers are first-class values. `Handler[E]` does not tell partial from total, so the static check cannot prove every op reaches a real body. For each user effect, the root evidence vtable (the outermost "enclosing handler") gets one generated stub per op. The stub has the op's exact C signature and calls a `
>
> *(The saved file ends here. The rest of the proposal, as relayed to the moderator:)* "… calls a `noreturn` panic … Null fn pointer plus a check at each perform site: … I reject it. One shared stub cast to every signature: calling through a mismatched fn-pointer type is undefined behavior in C … A `_Noreturn` stub fixes 7q2a63 for free." Example stub: `static int64_t __blink_unhandled_Zzstore_Fetch_zzget(void* st) { __blink_effect_unhandled("Zzstore.Fetch", "zzget"); }`

> S2 is S1 without the static check: keep only S1's runtime layer (the root vtable for a user effect panics and names the effect and operation, instead of answering a default value), and add no compile error at `main`. I rank it below S1 because it finds at runtime a mistake the compiler can find at compile time.

**Web/Scripting:**

> ## Web/Scripting panelist: Phase A submission (ee5e9m)
>
> **Position:** A zero default is JavaScript's `undefined` dressed up as a feature. Code keeps running on a value nobody produced, and the failure shows up three calls later somewhere unrelated. That is the kind of bug that fills Stack Overflow. The spec already says, in §4.12, "user-defined effects have no default handler — you must provide one." The compiler should make that sentence true.
>
> ### Proposal W1 (primary): compile error at `main`, panic for whatever the compiler cannot see
>
> **Part 1, static check (catches about 90% of cases).** `main` implicitly holds every effect, but holding an effect does not give you a handler for it. Only built-in effects ship stdlib handlers. So if `main`'s transitive effect row contains a user-declared effect that no enclosing `with` discharges, report a compile error at the call site in `main`. Tests already do this (UnhandledEffectInTest, 5-0). `main` would get the same check, limited to user effects.
>
> ```blink
> effect Metrics {
>     effect Emit { fn counter(name: Str, value: Int) }
> }
>
> fn record() ! Metrics.Emit {
>     metrics.counter("hits", 1)
> }
>
> fn main() {
>     record()              // error[E05xx]: UnhandledUserEffect
> }
> ```
>
> ```
> error[E05xx]: no handler installed for user effect `Metrics.Emit`
>  --> app.bl:9:5
>   |
> 9 |     record()
>   |     ^^^^^^^^ performs `Metrics.Emit`; nothing installs a handler for it
>   |
>   = help: user effects have no default handler. Wrap the call:
>   =       with my_metrics() { record() }
> ```
>
> The fix:
>
> ```blink
> fn stdout_metrics() -> Handler[Metrics] {
>     handler Metrics {
>         fn counter(name: Str, value: Int) {
>             io.println("{name} += {value}")
>         }
>     }
> }
>
> fn main() {
>     with stdout_metrics() {
>         record()
>     }
> }
> ```
>
> **Part 2, runtime panic for the rest.** Partial handlers auto-delegate (§4.7.1), and the type system does not tell partial handlers from total ones. A handler that leaves out an op can therefore still reach "no enclosing handler implements it" at runtime. In that case the operation panics with a fixed message:
>
> ```
> panic: no handler for effect operation `zzstore.fetch.zzget` (effect Zzstore.Fetch)
>   the installed handler omits `zzget` and no outer handler implements it
> ```
>
> ```blink
> fn half() -> Handler[Zzstore] {
>     handler Zzstore {
>         // zzget omitted: auto-delegates outward
>     }
> }
>
> fn main() {
>     with half() {
>         zzstore.fetch.zzget()   // compiles (E is discharged); panics at runtime
>     }
> }
> ```
>
> **Codegen consequence (answers the brief's vtable question):** the vtable needs no per-type default bodies. Every unfilled slot points to one shared stub that calls `__blink_panic_dispatch` with the effect and op name. It never returns, so a `-> Never` op is correct for free and 7q2a63 goes away. Map, Set and Bytes no longer get null handles that segfault. `assert_panics` in tests catches the panic like any other.
>
> **Tradeoffs (DX lens):**
> - Plus: the error arrives at compile time, at the line the developer wrote, with a copy-paste fix. Five-minute rule: met. "I declared an effect and forgot to wire it up" is the most common newcomer mistake, and this catches it before the program runs.
> - Plus: one behaviour for every return type. No "why is my count zero?" questions, and no segfaults.
> - Plus: the §4.12 sentence ("the compiler forces you") becomes true instead of aspirational.
> - Minus: a new diagnostic and a reachability check over `main`'s row. That check should be the same machinery the test-block check already uses, so the cost is small.
> - Minus: there are two failure modes (compile error vs panic). I accept that. The panic only happens with partial handlers, which are an advanced feature.
>
> ### Proposal W2 (fallback, if the panel wants minimal): runtime panic only
>
> This is Part 2 without Part 1. It is uniform and honest, and it fixes both bugs. But the developer learns about the missing wiring only when that code path runs, which may be in production. I would vote for W2 over the status quo without hesitation, but W1 is better DX.
>
> ### Rejected: keep the zero/empty default
>
> It is not uniform (null handles), it breaks Never, and it contradicts §4.12. Its only selling point is "doesn't crash", which is the same trap as JS's silent `undefined` and Python's `dict.get` returning None into an arithmetic expression.
>
> ### Cross-language notes
>
> - **Python:** an abstract method left unimplemented raises `NotImplementedError` loudly. It never returns 0.
> - **Kotlin:** `TODO()` returns `Nothing` and throws. This is exactly the Never-typed stub Part 2 proposes.
> - **TypeScript:** `strictNullChecks` exists because silent `undefined` was the top source of bugs. A zero default brings that bug class back.
> - **Koka / OCaml 5:** performing an unhandled effect is a type error in Koka and a runtime `Unhandled` exception in OCaml 5. W1 combines the two: static where possible, a loud runtime error where not.

**PLT:**

> # PLT panelist — Phase A submission (ee5e9m)
>
> ## Diagnosis
>
> An effect type system exists to prove one thing: **no well-typed program performs an operation that has no handler.** In Koka and Frank, a top-level computation with an empty effect row is safe by construction. Blink's main holds every effect implicitly, and the root installs handlers only for built-in effects. So for user effects, main's implicit row claims a capability that nothing provides. The "zero value" fills that gap with a value nobody produced:
>
> - For `T = Never` it makes up a value of the empty type (bug 7q2a63). That breaks progress and preservation directly.
> - For Map, Set and Bytes it makes up a null handle, which gives undefined behaviour.
>
> No default value is correct for every type. Only a term of type `Never` fits every answer type. So the default must diverge, and the static rules should make that default unreachable wherever they can.
>
> ## Proposal P1 (preferred): check statically at the root, trap on the dynamic leftover
>
> **Rule 1 (static).** Compute main's *residual row*: the effects main's body performs that no enclosing `with` discharges. Any **user-declared** effect left in that row is a compile error, `UnhandledEffectInMain` (next free E05xx). This is the same rule as `UnhandledEffectInTest`, restricted to effects that have no root handler. Built-in effects are not affected.
>
> ```blink
> effect Zzstore {
>     effect Fetch { fn zzget() -> Int }
> }
>
> fn load() -> Int ! Zzstore.Fetch {
>     zzstore.fetch.zzget()
> }
>
> fn main() {
>     let n = load()   // error[UnhandledEffectInMain]: effect `Zzstore.Fetch`
>                      // has no handler; wrap the call in `with h { ... }`
> }
>
> fn mem_store() -> Handler[Zzstore] {
>     handler Zzstore {
>         fn zzget() -> Int { 42 }
>     }
> }
>
> fn main() {
>     with mem_store() {
>         io.println("{load()}")   // OK: `with` discharges Zzstore
>     }
> }
> ```
>
> This does not reopen the 5-0 vote on main. It reads "implicitly holds all effects" as "holds every capability the root can provide". §4.6 says main is "the only place where capabilities are created from nothing". For a user effect, nothing exists to create. §4.12 already promises that "the compiler forces you" to wire user effects. Rule 1 makes the compiler keep that promise.
>
> **Why Rule 1 is sound with first-class handlers.** `with h` where `h: Handler[E]` discharges `E` statically, whatever value `h` holds. A closure that performs `E` carries `E` in its row, and a call to it adds `E` back. No effect variables exist in v1, so the residual row is a finite, concrete set. The check is decidable and has no false negatives within the static fragment.
>
> **Rule 2 (dynamic leftover).** Partial handlers (§4.7.1, 5-0) have the same type as total ones. So a root-most partial handler can still auto-delegate an omitted op to nowhere. Explicit `default.op()` with no outer handler has the same problem. Types cannot see this case, so it needs a runtime answer. The root evidence slot for each user effect holds a **trap vtable**. Each of its operations has the type `Never`, and by ex falso a `Never` term fits every answer type:
>
> ```
> panic: no handler for operation `Zzstore.Fetch.zzget`
> ```
>
> - The trap is an ordinary `panic`. `assert_panics` catches it in tests, and in production it ends the process. BlockHandler `exit` follows the existing catchable-unwind rules.
> - The trap has the same shape for every return type, so Map, Set and Bytes no longer get null handles.
> - 7q2a63 closes with no separate fix, because a `-> Never` op's default now diverges.
> - For codegen, the vtable keeps one slot per operation. The slot holds a shared trap stub instead of a body that makes up a zero value.
>
> Rule 1 also cuts the trap down to the partial-handler case, so a program almost never hits it.
>
> ## Proposal P2 (fallback): Rule 2 alone
>
> If the panel will not add a compile error, adopt the runtime trap alone. It is still sound in the progress-and-preservation sense: a stuck state becomes divergence, which the type `Never` allows. But it leaves §4.12's "the compiler forces you" untrue, and it moves a fault the compiler could prove into run time.
>
> ## Rejected: keep defaults and make them uniform
>
> Any "default value" design needs a `Default`-style witness for every answer type. No such witness exists for `Never`, function types or opaque handles. It would also need a new trait bound on every effect operation. That is unsound for `Never`, and for every other type it makes the silent failure permanent.
>
> ## Tradeoffs
>
> - (+) The effect-safety theorem holds again for user effects, and main stays consistent with test blocks.
> - (+) Codegen no longer needs a default-body generator; one trap stub covers every operation.
> - (−) A program that today runs on zero values stops compiling. That is the intended result, but the change needs a migration note.
> - (−) Open question for the systems seat: do spawned tasks inherit the evidence vector? If a spawn entry point is a second root, Rule 1 must also apply there.
>
> ## Other languages
>
> - Koka: a top-level row must be empty or `<io,...>`, so an unhandled user effect is a type error. This matches Rule 1.
> - OCaml 5: an unhandled `perform` raises `Effect.Unhandled` at run time. This matches Rule 2, with no static check.
> - Eff and Frank: rejected statically.
>
> No language I know of answers an unhandled op with a zero value. Go's zero values are the closest thing, and Go has no effect system.
>
> **Vote intent:** P1 > P2. I strongly reject any zero-value default.

**DevOps:**

> # DevOps/tooling — Phase A proposals for ee5e9m
>
> **Position.** The current behaviour is wrong in two ways. A zero value hides the bug, and it shows up later as wrong data or a segfault far from the call that caused it. The compiler can find most of these cases before the program runs, so it should report them there. A runtime panic should catch only the cases that static analysis cannot see.
>
> ## P1 (preferred): compile-time error at `main`, with a uniform runtime panic as backstop
>
> **Rule A (static).** `main`'s implicit row (§4.6) gives only the effects that have a root handler, which means the built-in effects. A user-declared effect operation that reaches `main` with no discharge is an error. "Reaches" means a direct call, or a call through any function or closure whose row carries the effect.
>
> This is the same rule that tests already use (UnhandledEffectInTest, 5-0), applied to the second root. It also makes §4.12 true: "the compiler forces you to explicitly wire up your domain effects" is false today.
>
> ```blink
> effect Zzstore {
>     effect Fetch { fn zzget() -> Int }
> }
>
> fn load() -> Int ! Zzstore.Fetch {
>     zzstore.zzget()
> }
>
> fn main() {
>     let n = load()          // error E0539
>     io.println("{n}")
> }
> ```
>
> ```
> error[UnhandledEffect]: unhandled effect `Zzstore.Fetch` in `main`
>   --> src/app.bl:9:13
>    |
>  9 |     let n = load()
>    |             ^^^^^^ `load` requires `! Zzstore.Fetch`
>    |
>    = note: `Zzstore` is user-defined and has no default handler (§4.12)
>    = help: wrap in `with <handler> { ... }`; in scope: `store_handler(cfg) -> Handler[Zzstore]`
> ```
>
> I propose one code, `UnhandledEffect` (E0539, the next free code in the effects range), with the root named in the header ("in `main`" or "in test \"...\""). This would also give the unnumbered UnhandledEffectInTest a number. One code means one LSP quick-fix provider and one entry in the docs. If the panel wants the test name kept, give it its own number next to this one. Either choice works for tooling. Two unnumbered names do not.
>
> **Tooling surface:**
> - The LSP quick fix "Wrap in `with ...`" lists the in-scope functions that return `Handler[Zzstore]`, in the same way rust-analyzer offers fill-ins for missing match arms. This works because handlers are typed values (`Handler[E]`).
> - The inlay hint on `main` (§4.6) stays "documentation, not enforcement" for built-in effects. A user effect in it that has no discharge gets the error squiggle, so the hint and the error agree.
> - `blink fmt`: no syntax change, so no impact.
>
> **Rule B (runtime backstop).** Static analysis cannot see every case. The type does not tell a partial handler from a total one (§4.7.1: auto-delegated omitted ops, and an explicit `default.op()` with no outer handler). For those cases, every root vtable slot of a user effect points to one shared stub per operation. The stub calls `__blink_panic_dispatch` with this message:
>
> ```
> panic: no handler for effect operation `zzstore.zzget` (Zzstore.Fetch)
>   --> src/app.bl:5:5
>   = note: the handler installed at src/app.bl:12:5 omits `zzget`, and no enclosing handler implements it
> ```
>
> Uniform: one panic for every return type. That removes the Map/Set/Bytes null-handle segfault, and it fixes 7q2a63 for free, because the stub for a `-> Never` op never returns. The vtable needs no type-specific default bodies at all, which answers the brief's codegen question. `assert_panics` can catch it, and the test runner reports `status:"panicked"` under the existing record shape. The span is optional, as in panicked-status-reporting. The perform site should pass it when it can.
>
> **Tradeoffs.**
> - Plus: the error appears at edit time, with a fix-it. Rule B's panic text names the effect and the op, so nobody has to grep a stack trace.
> - Plus: one rule for both roots, so there is less for users and LLMs to learn.
> - Minus: dynamic delegation through partial handlers stays a runtime failure. That is acceptable, because it is the same gap Koka and OCaml 5 have.
> - Minus: the rule touches the transitive-row computation at `main`, which the LSP already does for the inlay hint, so the cost is low.
>
> **Cross-language.** OCaml 5 raises `Effect.Unhandled` at runtime: correct, but late. Koka rejects an unhandled effect at the top level at compile time, except for its built-in default handlers. That is the same split this proposal makes between built-in and user effects. No mainstream effect system answers a zero value.
>
> ## P2 (fallback, if Rule A loses): runtime panic only
>
> Adopt Rule B on its own. It is still uniform and it still fixes 7q2a63. It is strictly worse for tooling, because the error appears in production and not in the editor. Choose it only if the panel judges Rule A too costly to build before the perform stage lands.
>
> ## Rejected: keep zero defaults, or let a handler declare a default value
>
> Both are silent. A defined default produces no diagnostic, so no tool can surface it. A program that runs with a value nobody produced is the worst possible error message.
>
> **Vote intent:** P1 > P2 >> status quo.

**AI/ML:**

> # Phase A — AI/ML panelist (ee5e9m: unhandled user-effect operation)
>
> ## Proposal 1 (preferred): compile-time error in `main` + runtime panic backstop
>
> **Rule 1 — static.** `main` implicitly holds all *built-in* effects. A *user-declared* effect that reaches `main`'s body without being discharged by a `with` is a compile error, `UnhandledUserEffect` (new E05xx), the twin of `UnhandledEffectInTest`.
>
> ```blink
> effect Zzstore {
>     effect Fetch { fn zzget() -> Int }
> }
>
> fn load() -> Int ! Zzstore.Fetch {
>     zzstore.fetch.zzget()
> }
>
> fn main() {
>     let n = load()   // error[UnhandledUserEffect]: `load` requires `! Zzstore.Fetch`;
>                      // no handler installed. help: wrap the call in `with <handler> { ... }`
> }
>
> fn main() {
>     let h = handler Zzstore.Fetch {
>         fn zzget() -> Int { 42 }
>     }
>     with h {
>         io.println(load())   // OK
>     }
> }
> ```
>
> **Rule 2 — runtime backstop.** Partial handlers (§4.7.1) delegate omitted ops to `default.op(...)`, and the type system does not tell partial from total handlers, so the compiler cannot always prove an enclosing handler exists. When dispatch finds no handler for an op, it panics:
>
> ```
> panic: no handler for effect operation `zzstore.fetch.zzget` (Zzstore.Fetch)
> ```
>
> Uniform for every return type (Int, Map, Bytes, Never alike). It is an ordinary panic: `assert_panics` catches it, production terminates. The vtable needs no per-type default bodies — one shared "no handler" stub per op that calls `__blink_panic_dispatch`. This closes 7q2a63 (Never op returning normally) for free.
>
> **Why (AI/ML domain):**
> - **Silent defaults are the worst failure mode for LLM-written code.** The most common effect mistake a model makes is to declare an effect, write the logic, and forget the `with`. Today that program compiles, runs, and returns 0/None/[]. A model reads "it ran" as "it worked"; no output contradicts it. A compile error with a fix-it line is the highest-value signal in an agent's repair loop.
> - **One rule replaces a hidden table.** The current behaviour asks a model to learn a per-type default table (Err, empty list, None, zero, null handle) that no spec text states. The new rule is one sentence — "user effects need a `with`; built-ins have stdlib defaults" — and matches the test-block rule the model already learns from §2.20. It makes §4.12's promise ("the compiler forces you to explicitly wire up your domain effects") literally true.
> - **Zero added decision points, zero token cost** for correct programs. The only forced code is the `with` the spec already says you must write.
> - **Learnable from the spec alone.** Today §4.6 ("main holds all effects") and §4.12 ("user effects have no default handler") contradict each other; a spec-trained model cannot predict the MVCE. This proposal makes them agree.
>
> **On relitigation:** this narrows §4.6's sentence from "all effects" to "all built-in effects". I frame it as reconciling two decided texts that conflict, not overturning the 5-0 vote: that vote's rationale was ceremony — built-ins have real default handlers, so naming them in main adds nothing. User effects have no default handler, so the rationale does not reach them. If the panel rules this out of scope, Proposal 2 is the fallback.
>
> **Cross-language:** Koka — main may only have built-in effects (`io` etc.); an unhandled user effect at main is a type error (closest model). Unison — `main` runs with `{IO, Exception}`; any other ability unhandled is a type error. OCaml 5 — no static check; raises `Effect.Unhandled` at runtime (= Rule 2 alone). No mainstream effect system answers an unhandled op with a zero value.
>
> ## Proposal 2 (fallback): runtime panic only
>
> Rule 2 without Rule 1: uniform panic, no default bodies in the vtable.
>
> Tradeoff: strictly better than today (loud, uniform across types, no segfault, correct for Never). But the error surfaces at runtime and only on the executed path. An agent that generated the code learns of the bug only if its test run reaches the op; untested branches still ship it. That weakens the feedback loop that matters most for AI-generated code.
>
> ## What I oppose
>
> Keeping zero-value defaults in any form, including opt-in. It adds a hidden per-type rule and a decision point ("is this default safe?"), produces plausible-but-wrong programs (the hardest failure for a model to detect), and is already non-uniform (Map/Set/Bytes segfault).
>
> **Vote intent:** Proposal 1 > Proposal 2 >> status quo.

**Minimalism:**

> **Min (Minimalism), Phase A submission: spec gap ee5e9m (unhandled user-effect operation)**
>
> **Framing.** The current behaviour is a hidden feature: every operation of every user effect has an implicit default body that returns a zero value. Nobody voted for it, the spec does not describe it, it is not uniform (Map, Set and Bytes give a null handle that segfaults), and it breaks `Never` (7q2a63). My lens is subtraction, so the question I ask is which rule lets us delete the most and still be correct.
>
> ---
>
> **Proposal M1 (my recommendation): an unhandled operation panics, and default bodies are removed.**
>
> If an operation is performed and no enclosing handler implements it, the program calls `panic` with a fixed message naming the effect path and the operation. This is an ordinary panic, not a new mechanism:
> - `assert_panics` catches it in tests.
> - In production it ends the process through `__blink_panic_dispatch`.
> - BlockHandler exit/close behave as they do for any panic, per the existing 6-0 vote.
>
> ```blink
> effect Zzstore {
>     effect Fetch { fn zzget() -> Int }
> }
>
> fn main() {
>     let n = zzstore.fetch.zzget()
>     // panic: no handler for Zzstore.Fetch.zzget
>     io.println("{n}")   // never reached
> }
>
> test "unhandled op panics" {
>     let h = handler Zzstore.Fetch {
>         fn zzget() -> Int { 1 }
>     }
>     with h {
>         assert(zzstore.fetch.zzget() == 1)
>     }
> }
> ```
>
> Spec changes:
> 1. §4.7.1: add one sentence. "If no enclosing handler implements the operation, the program panics with `no handler for <Effect>.<op>`." This closes the open end of "bubble up to the nearest enclosing handler", including partial handlers whose auto-delegated `default.op` has nothing above it.
> 2. §4.12: change "the compiler forces you to explicitly wire up your domain effects" to say what is true. Tests reject it at compile time (UnhandledEffectInTest). Elsewhere, an unwired operation panics at the perform site.
>
> What this removes: per-type zero-value tables, the null-handle Map/Set/Bytes segfaults, and the `Never` special case. 7q2a63 closes without further work, because a panic already has type `Never`. Codegen no longer needs a default body for each operation. Whether the root slot holds a panic stub or a null that is checked at the perform site is an implementation choice, not spec.
>
> Tradeoffs:
> - (+) One rule. It reuses `panic` and adds no syntax, no new diagnostic and no keyword.
> - (+) It is uniform across all return types, so there are no per-type exceptions to document.
> - (−) A wiring mistake shows up at runtime, not compile time. It does show up loudly, on the first perform, with the effect and operation named, so it is not a silent wrong value.
> - (−) It costs one runtime check or stub per perform root. That cost is negligible next to the call through the vtable.
>
> ---
>
> **Proposal M2 (I accept it, but do not prefer it): M1 plus a compile-time check at `main`.**
>
> If `main`'s inferred transitive row contains a user-declared effect that no `with` in `main` discharges, report a new E05xx (`UnhandledUserEffectInMain`). This makes the existing §4.12 sentence true. It does not relitigate "main implicitly holds all effects", because built-in effects keep their stdlib defaults.
>
> ```blink
> fn main() {
>     zzstore.fetch.zzget()   // error[E05xx]: user effect Zzstore.Fetch has no handler in main
> }
> ```
>
> Why I rank it below M1:
> - M2 is a second mechanism for the same failure, and it cannot replace M1:
>   - A partial handler (auto-delegation, 5-0) discharges the whole row statically but leaves operations with no implementation.
>   - First-class handlers pulled from a list or map discharge the row while their contents are unknown statically.
> - So the runtime panic must exist anyway. M2 adds a diagnostic, a rule that makes `main` special a second time, and a test matrix, all to catch the subset of cases that M1 already reports clearly on the first run.
> - If the panel wants it, it costs little and does not conflict with M1. It must not be presented as a replacement for M1.
>
> ---
>
> **Options I reject:**
> - **Keep a defined default (zero, None, Err).** It is quiet and wrong, and it is not uniform. Fixing it means more per-type rules plus a `Never` exception, which is the opposite of subtraction.
> - **New syntax for an author-declared default handler inside the `effect` block** (e.g. `default fn zzget() -> Int { 0 }`). YAGNI. A user who wants a default can already write a handler value and install it with `with` at the top of `main`. That is one line, and it keeps the wiring visible, which is the stated purpose of §4.12.
> - **Make main's implicit row exclude user effects.** That changes a 5-0 decision to fix a runtime hole.
>
> **Cross-language note.**
> - OCaml 5 raises `Effect.Unhandled` at runtime. It is the closest prior art for "panic, uniform, named".
> - Koka and Eff reject it statically, but only because they have no first-class partial handlers that escape the type. Blink chose first-class handlers with auto-delegation, so a runtime backstop is required whatever else we choose.
> - Go's lesson applies: one rule that fails loudly beats a set of quiet defaults.
>
> **Vote intent:** yes on M1. Yes on M2 only as an addition to M1. No on any defined-default option.

#### Phase A.5 — Dedupe

- **Option 1** — a compile error when a user-declared effect reaches `main` with no discharging `with`, plus a runtime panic for an operation that finds no handler (Sys, Web, PLT, DevOps, AI/ML; Min accepted it as an addition).
- **Option 2** — runtime panic only (Min's first proposal; every other seat's fallback).
- A default value was proposed by no seat.

Variations flagged for debate: one code or two, the §4.6 wording, how much lowering the spec states, spawned tasks, and the panic message.

#### Phase B — Debate (round 1)

All six seats marked themselves stable after one round. Min moved to Option 1. On the diagnostic code, positions crossed: DevOps dropped the single code while the other five adopted it.

**Systems:**

> # Sys, Phase B round 1
>
> S2 in one sentence: S1's runtime panic only, with no compile-time check at `main` (the same as Option 2).
>
> **Option 1 vs 2:** I hold Option 1. Min is right that the runtime half must exist anyway. But the static half costs nothing at runtime and catches the common case (no `with` at all) at build time, so it pays for itself.
>
> **V1:** I accept DevOps's single code that names the root. One code for "no handler at a root" is simpler than two.
>
> **V2:** I accept the AI/ML wording ("all built-in effects"), or PLT's reading. Either one only states what §4.12 already says.
>
> **V3:** The spec states the behaviour only: a panic that names the effect and the operation. The lowering is not spec. I agree with Min here and withdraw my stub detail from the spec text.
>
> **V4:** A spawned closure's effect row is part of its caller's row, so the `main` check already covers it. I see no second root.
>
> **V5:** The spec fixes the content (effect and operation named), not the exact wording.
>
> stable, ready to vote

**Web/Scripting:**

> ## Web, Phase B round 1 (ee5e9m)
>
> ### Option 1 vs Option 2: Option 1
>
> Min is right that the runtime panic must exist in all cases. I agree, and Option 1 keeps it. The question is whether the static half earns its cost. From the DX seat, it does:
>
> - **The case it catches is the common one.** "I declared an effect and forgot the `with`" is the mistake a newcomer makes on day one. Partial handlers that auto-delegate to nothing, and handlers pulled out of a map, are the 10% case. Option 2 tells the 90% case about the mistake only when that code path runs. For a rarely used path (an error branch, a cron job, a webhook), that means production.
> - **It is not a new mechanism.** Tests already reject this at compile time (UnhandledEffectInTest, 5-0). Option 1 applies the same rule to `main`, limited to the effects that have no root handler. For a user, "same error in tests and in main" is less to learn than "compile error in tests, runtime panic in main". Option 2 is the asymmetry that generates the Stack Overflow question: "why did my test fail to compile but my program compiled and crashed?"
> - **§4.12 already promises it.** Option 2 has to reword the spec to promise less. Option 1 makes the existing text true.
>
> Min's cost list (a diagnostic, a rule, a test matrix) is real but small. The row computation already exists for tests and for the LSP inlay hint on `main`.
>
> ### V1, diagnostic identity: one code (DevOps's form)
>
> I drop my `UnhandledUserEffect` name. One number, `UnhandledEffect` (E0539, or the next free code), with the root named in the header: "in `main`" or "in test \"...\"". One code is one thing to search for and one `blink explain` page. It also gives the unnumbered test diagnostic a number, which tooling needs. For `main`, the help line must say *why*: "user effects have no default handler; install one with `with`". Without that line, a dev who knows "main holds all effects" will think the compiler is wrong.
>
> ### V2, framing of §4.6: add a sentence, do not change the existing one
>
> "main holds all effects" is the simple mental model, and devs keep it. Keep the sentence as it is and add one: "The root provides handlers only for built-in effects. A user effect that reaches `main` without a `with` is a compile error (E0539)." This is the PLT/Sys reading written down. AI/ML's edit ("all built-in effects") is acceptable as a second choice. Min's concern (reopening the 5-0 vote) is met because the capability rule does not change. Only the handler rule is stated.
>
> ### V3, lowering: keep it out of the spec
>
> I agree with Min here. The spec states the behaviour: the operation does not return, and it panics naming the effect and the operation. Sys's point about UB is correct, and I withdraw "one shared stub". A shared stub cast to every signature is a C undefined-behaviour bug. Put Sys's per-operation stub in the implementation ticket (and in the 7q2a63 fix), not in sections/.
>
> ### V4, other roots (spawn)
>
> The answer a JS/Python dev expects is that a spawned task sees the handlers that were in scope where `async.spawn` was called. This is how AsyncLocalStorage and contextvars behave. With that rule, the spawn closure's row flows into the enclosing row, Rule 1 covers it, and there is no second root. I ask the spec to state the inheritance in one sentence in §4.13 if it does not already. Sys should confirm the runtime does this. It does not block my vote on Option 1.
>
> ### V5, panic message: fix the content, not the wording
>
> The spec should require the effect path and the operation name, plus the perform-site span where available, in the same form as panicked-status-reporting. The exact wording stays out of the spec, so tooling and translations can change it. My example text was only an example.
>
> **stable, ready to vote**: Option 1 first, Option 2 second, no on any defined default. V1 one code; V2 add a sentence; V3 not in spec; V5 content, not wording.

**PLT:**

> # PLT, Phase B round 1 (ee5e9m)
>
> ## Option 1 vs Option 2
>
> I keep Option 1. Min is right on one point: the runtime panic must exist in any case, so Option 2 is the floor, not an alternative. The question is whether the static half earns its cost. I say yes, for three reasons.
>
> **1. Min overstates the size of the static hole.** M2 lists two cases that defeat the static check:
> - (a) partial handlers;
> - (b) "first-class handlers pulled from a list or map ... while their contents are unknown statically."
>
> (b) is not a hole. A value of type `Handler[E]` is a full vtable for `E`, whatever its origin (§4.7: struct of fn pointers, one per operation). `with h` discharges `E` because of the *type* of `h`, not its value. A handler read from a `List[Handler[Zzstore]]` covers every operation exactly as a literal does. The static check is sound for every handler value. The one exception is auto-delegated slots, i.e. case (a). So the runtime trap covers exactly one construct, partial handlers, and the static check covers everything else. Those are not "two mechanisms for the same failure". They are a theorem plus a precisely bounded residue.
>
> **2. A compiler-provable fault should be a compile error.** The MVCE case (perform a user effect with no `with` anywhere) is the common wiring mistake. The compiler already computes main's transitive row (the §4.6 LSP hint). Under Option 2 the compiler knows the program will panic and says nothing. That violates §4.12's stated design intent and treats `main` differently from `test` for no principled reason.
>
> **3. Rewording §4.12 is a spec regression.** Option 2 must delete "the compiler forces you". That sentence is the reason user effects have no default handler. Removing a stated guarantee to avoid a diagnostic is the wrong trade.
>
> ## V1 Diagnostic identity
>
> I accept DevOps's form: one code, `UnhandledEffect` (E0539), with the root named in the header (`in `main`` / `in test "..."`). The typing rule is the same at both roots: residual row ∩ (effects with no root handler) = ∅. For a test the set is all effects; for main it is user effects. One rule should have one code. I withdraw the separate `UnhandledEffectInMain` name.
>
> ## V2 Framing of §4.6
>
> I support AI/ML's and DevOps's text, and the moderator may merge it with mine: "`main` implicitly holds every effect that has a root handler: all built-in effects." This is a clarification, not a reversal. The 5-0 vote was about ceremony (no annotation on main), and that stays. Main never could perform a user effect without a handler. Today it only *appears* to, by producing invented values, which no panelist defends. Min's objection that this "changes a 5-0 decision" applies equally to Option 2. Option 2 also changes what main may do with a user effect: today it gets a zero, afterwards a panic. Both options change behaviour. Option 1 also makes the type say so.
>
> ## V3 Lowering
>
> The spec states the observable behaviour only: a perform that reaches no implementing handler panics, and it never returns a value. Stub vs null-check is implementation, as Min says. Sys's point about C fn-pointer type mismatch is correct, but it belongs in the codegen notes, not in sections/. The spec should state one constraint: the trap has type `Never`, so a `-> Never` operation stays non-returning (7q2a63).
>
> ## V4 Other roots (my question, now answered)
>
> §4.13 gives structured concurrency: tasks cannot outlive their scope. §4.13 wildcard forwarding threads the caller's evidence vector into callbacks. So a spawned closure runs under the evidence of its spawn site, and `async.spawn` inside `with h { ... }` is discharged by that `with`. Spawn is not a second root. The spec should say this in one sentence in §4.13 ("a spawned task runs with the handlers in force at `async.spawn`"), so the codegen cannot pick up the root vector by mistake. With that sentence in place, there are only two roots: `main` and `test`.
>
> ## V5 Panic message
>
> Spec fixes the content, not the wording: the message names the full effect path and the operation. Spans are optional, as in panicked-status-reporting. No preference on wording.
>
> ## Status
>
> Stable, ready to vote. Order: Option 1 (with V1 = one code E0539, V2 = clarifying text, V4 = §4.13 sentence) > Option 2. No on any defined default.

**DevOps:**

> # DevOps/tooling: Phase B round 1
>
> ## Option 1 vs Option 2
>
> I keep Option 1. Min's argument is right that the runtime panic must exist in every case, because partial handlers make the gap impossible to close by types alone. That makes the runtime panic necessary. It does not make it enough.
>
> The tooling question is when the user learns about the mistake. The most common case is "I declared an effect and forgot the `with` in `main`". Under Option 2 the user learns this from a crash in production, on the first request that takes that path. A path that runs once a week fails once a week. Under Option 1 it is a red squiggle while the user types, with a quick fix. Partial-handler delegation to nothing is the rare case. The runtime panic covers that case.
>
> Min says Option 1 makes `main` special a second time. It does not: it applies the same root rule tests already have (5-0) to the other root. Users already have to learn "a root with no handler for a domain effect is an error" for tests. Option 2 leaves them two answers to one question: compile error in a test, crash in `main`.
>
> On cost: the LSP already computes `main`'s transitive row for the §4.6 inlay hint. The check is a filter on that set ("user-declared and not discharged"). It does no new analysis.
>
> ## V1: diagnostic identity
>
> I drop my single-code proposal. The majority named a separate code, and one code covering two roots is not worth a fight. My conditions:
>
> - **Name:** `UnhandledEffectInMain`, not `UnhandledUserEffect`. The rule is about the root, and its name should match the sibling `UnhandledEffectInTest`, so users and the LSP can treat them as one family. "User" belongs in the note, not the name. The header already says which effect.
> - **Number:** E0539. That number is free in sections/ and src/.
> - **Message:** the same shape as the test diagnostic, plus a `note:` that the effect is user-declared and has no default handler, and a `help:` that suggests `with`.
> - **Follow-up, not this vote:** `UnhandledEffectInTest` has no number. Give it one (E0540) in a separate chore. An unnumbered diagnostic cannot be filtered in CI output or linked from the docs index.
>
> ## V2: framing of §4.6
>
> I agree with AI/ML's edit: "implicitly holds all built-in effects". Keep the "why implicit" paragraph. PLT's and Sys's readings have the same meaning, but a reader (or an LLM) who reads only "all effects" will write the MVCE and expect it to compile. The spec text must say what the compiler does. This does not reopen the 5-0 vote. That vote was about ceremony on `main`, and built-in effects stay implicit. §4.13's `Async` is built in, so it is not affected.
>
> ## V3: how much lowering the spec states
>
> I agree with Min. The spec states the observable behaviour: the operation panics, it never returns (this covers `-> Never`), and no default value is produced. Stubs and nulls are an implementation choice. Sys's point is correct and important (casting one stub to every signature is undefined behaviour in C), but it belongs in the implementation ticket for the perform stage, not in sections/. I withdraw "one shared stub per operation" from my spec text.
>
> ## V4: other roots (spawn)
>
> The static rule is a check on the row, not on an entry point. `async.spawn(fn() { ... })` takes a closure whose row flows to the spawn site (§4.15.1), so an undischarged user effect inside a spawned closure reaches `main`'s residual row and E0539 reports it at the spawn call. A spawned task is not a third root for the static rule.
>
> The static rule is sound only if a task inherits the evidence installed at its spawn site. If it does not, `with h { async.spawn(...) }` passes the check and then panics at run time. I ask Sys to confirm inheritance, and I ask the spec to state it in §4.13 as part of this decision. If Sys says no, the static rule must also reject a user effect that crosses a spawn boundary.
>
> ## V5: panic message content
>
> The spec must fix part of the text, not only its content. `assert_panics(matching: "...")` (§2.20, §6) matches on the message, so the text is observable API. Tests written today against the wording must still pass after a compiler upgrade. I propose that the spec fix this much:
>
> - A fixed prefix: `no handler for effect operation `.
> - Then the qualified operation, in the form the user writes at the call: `` `zzstore.fetch.zzget` ``. Optionally, the declared path follows in parentheses: `(Zzstore.Fetch)`.
> - Optional extra content, with no fixed wording: the perform-site span (optional, as in panicked-status-reporting), and a note naming the installed handler that omitted the operation.
>
> Web's wording already fits this. Min's and PLT's wordings would need only the prefix changed.
>
> ## Status
>
> Stable, ready to vote. Option 1 > Option 2. On V1, I accept `UnhandledEffectInMain` E0539. One condition is still open: Sys's answer on V4. If tasks do not inherit evidence, the static rule needs the spawn clause I describe above before I vote for it unchanged.

**AI/ML:**

> # Phase B r1 — AI/ML
>
> ## Option 1 vs Option 2: Option 1
>
> Min's case against the static check is that it covers only part of what the runtime panic already covers. That is true, but it is the wrong part to give up. The two halves catch different mistakes:
>
> - **The static half catches "forgot `with` entirely".** By far the most common way code generators get effects wrong is to declare an effect, write the calls, and never install a handler. Option 1 rejects that on every path, including branches no test reaches. Option 2 reports it only when a run happens to perform the op. An agent's repair loop gets the error at `check` time, with a fix-it line, before any test exists.
> - **The runtime half catches handler bugs.** Partial handlers that auto-delegate to nothing, and first-class handlers taken from a list or map, are rarer and sit in deliberate handler code. A runtime panic is enough there.
>
> Option 1 also makes §4.12's sentence ("the compiler forces you to explicitly wire up your domain effects") true. Option 2 rewrites the sentence to fit the hole. A spec-trained model learns the first rule from one sentence. Under Option 2 it has to learn "tests are checked, `main` is not", which is the kind of asymmetry models get wrong.
>
> Cost: zero tokens for correct programs, and no new decision point. The check forces only the `with` the spec already requires.
>
> ## V1, diagnostic identity: DevOps' single code
>
> I support one code, `UnhandledEffect` (E0539), with the root named in the header ("in `main`" / "in test \"...\""). It gives the same mistake one name and one fix in both places, which makes it easier for a model to learn and to grep for. I withdraw `UnhandledUserEffect`. `UnhandledEffectInTest` has no number today, so folding it in breaks nothing numbered. If the panel wants to keep the test name, two adjacent numbers is my second choice.
>
> ## V2, framing of §4.6: flexible on the wording, firm that it be explicit
>
> I accept the Sys/PLT reading ("holds every capability the root can provide"), and I drop my "change 'all effects' to 'all built-in effects'" wording if that reading wins votes. My one condition: §4.6 must carry an explicit sentence, not leave the reader to infer it. Proposed text:
>
> "User-declared effects have no root handler, so `main` must discharge them with `with` (§4.12)."
>
> Without that sentence, §4.6 still says "all effects" with nothing qualifying it, and a model trained on the spec will predict the wrong behaviour.
>
> ## V3, lowering detail: Min on the spec text, Sys on the implementation
>
> The spec should state only the behaviour: an op that reaches no implementing handler panics. Sys is right that one stub cast to every signature is undefined behaviour in C. Record that in the decision file as an implementation constraint (one stub per operation, with that op's exact signature). Do not put it in the language spec.
>
> ## V4, spawned tasks: state that tasks inherit evidence
>
> A closure passed to `async.spawn` is written inside the scope of the spawn site, and its effect row is checked there. If the spec states that **a spawned task inherits the handlers active at its spawn site**, then spawn is not a second root and Rule 1 needs only `main` and tests. If tasks do not inherit, every user effect performed in a task panics at runtime, which is a trap for anyone writing concurrent code. Recommendation: add the inheritance sentence to §4.13 as part of this decision. It is one sentence, and it removes a question a model would otherwise have to guess at.
>
> ## V5, panic message: fix the content and the stable prefix, not the full wording
>
> The spec should require:
>
> - the effect path and the operation name;
> - the perform-site span when one is available (optional, as in panicked-status-reporting).
>
> It should also fix the fixed first-line prefix, `no handler for effect operation`, so tools and agents can match on it. Everything after that prefix, such as notes naming the handler that omitted the op, stays free.
>
> ## Status
>
> Stable, ready to vote. My order: Option 1 (with V1 single code, the explicit V2 sentence and the V4 inheritance sentence), then Option 2, then any default value.

**Minimalism:**

> **Min, Phase B round 1**
>
> **Option 1 vs Option 2: I move to Option 1.**
>
> The argument that moved me is DevOps's and PLT's: the static check is not a new rule. It is the UnhandledEffectInTest rule (5-0), applied to the other implicit root. One rule for two roots costs less to teach than one rule for tests plus a "but main panics" exception. It also makes §4.12 true without rewording it. With Option 2, the spec would keep a promise in one root and break it in the other, and I would have to write that exception into the spec. That is more surface, not less. My M2 objection still holds in one way: the runtime backstop is required, because partial handlers and an explicit `default.op()` can reach no handler. The panel agrees on that, so Option 1 is the M1 runtime rule plus a reuse of an existing static rule. I vote yes.
>
> **V1, diagnostic identity: one code (DevOps).**
> Use `UnhandledEffect` (E0539) for both roots, with the root named in the header. This replaces an unnumbered name instead of adding a second one, so it is net subtraction: one code, one doc entry, one quick-fix. I am against separate `...InMain` and `...InTest` codes. If tests must keep a distinct name, I prefer a header variant over a second number.
>
> **V2, framing of §4.6: do not edit the vote text.**
> I keep my position. Adopt the reading that PLT and Sys give: "holds every capability the root can provide", where built-ins have root handlers and user effects do not. Put that clarification in §4.6 as one added sentence that points to §4.12. Keep the "all effects" sentence as it is. AI/ML's "all built-in effects" edit gives the same result, but it rewrites the text of a 5-0 vote, and the next reader will see that as a reversal. Same result, smaller change: add, do not rewrite.
>
> **V3, lowering in the spec: keep it out of the spec.**
> Sys is correct that one stub cast to every signature is undefined behavior in C, so per-operation stubs (or an equivalent) is the correct implementation. That belongs in the decision record and in codegen, not in sections/. The spec states the behaviour: the operation does not return, and the program panics. If the backend changes (for example a perform-site check, or a non-C target), the spec must not change with it.
>
> **V4, other roots (spawn).**
> I accept no new root. `async.spawn` takes a closure. The closure's row is checked like any closure, and it must be a subset of the row of the enclosing function, which in main is covered by main's `with` blocks. "No spawn without a scope" means the task runs inside the lexical `with` that encloses the spawn. So the static rule applies only to roots with an implicit row: `main` and test blocks. If the evidence vector is not passed into the task at run time, that is a codegen bug, and the runtime backstop reports it as a panic, not as a wrong value. The spec needs one sentence: "A spawned task performs with the handlers in scope at the spawn site." Sys should confirm that this is already the design, not a new rule.
>
> **V5, panic message.**
> The spec fixes the content: the message names the effect path and the operation. It does not fix the wording or the span. This follows panicked-status-reporting, where the span is optional. Naming the omitting handler is a quality-of-implementation item, not spec.
>
> **stable, ready to vote.** My votes: yes on Option 1 with a single E0539. V2 as an added sentence, not a rewrite. V3 out of the spec. V4 needs no new root. V5 fixes content, not wording.

#### Phase C — Final vote

Ballot (verbatim):


> # Final positions notice and Phase C ballot (ee5e9m)
>
> Round 1 replies from all six seats are in this folder: phaseB-r1-{sys,web,plt,devops,aiml,min}.md. Read the ones from the other five before you vote. All six marked "stable, ready to vote". DevOps's condition on V4 asked Sys about evidence inheritance; Sys's reply (phaseB-r1-sys.md) says: "A spawned closure's effect row is part of its caller's row, so the `main` check already covers it. I see no second root."
>
> Note on V1: positions crossed in round 1. DevOps withdrew the single code and now accepts `UnhandledEffectInMain` E0539; Web, PLT, AI/ML, Min and Sys now accept the single `UnhandledEffect` code.
>
> This is a silent vote: write only to your own file, phaseC-vote-<seat>.md, and do not read other seats' vote files. Then send "voted".
>
> For EACH question give:
> 1. Vote: the option label
> 2. Reasoning: 2-4 sentences from your domain
> 3. Concern: one sentence on what could go wrong with the option you expect to win
>
> ## Q1. Core rule
> - 1A: Option 1. A user-declared effect that reaches `main` with no discharging `with` is a compile error. At run time, an operation that reaches no implementing handler (a partial handler auto-delegating to nothing, or an explicit `default.op()` with no outer handler) panics and names the effect and the operation. No default values.
> - 1B: Option 2. Runtime panic only; reword §4.12.
>
> ## Q2. Diagnostic identity (applies if 1A wins)
> - 2A: One code, `UnhandledEffect` (E0539), for both roots; the header names the root ("in `main`" / "in test \"...\""). `UnhandledEffectInTest` folds into it.
> - 2B: A separate `UnhandledEffectInMain` (E0539), sibling of `UnhandledEffectInTest`; numbering the test diagnostic is a separate chore.
>
> ## Q3. §4.6 text
> - 3A: Change "implicitly holds all effects" to "implicitly holds all built-in effects" (keep the "why implicit" paragraph).
> - 3B: Keep the voted sentence as written; add one sentence: `main` holds every capability the root can provide; built-in effects have root handlers, user-declared effects do not and must be discharged with `with` (§4.12).
>
> ## Q4. Lowering in the spec
> - 4A: The spec states behaviour only: the operation panics, never returns (covers `-> Never`), and no default value is produced. Stub vs check, and "one stub per operation with the op's exact signature, never one stub cast to every signature (C UB)", go to the decision record and the implementation ticket.
> - 4B: The spec also states the per-operation stub lowering.
>
> ## Q5. Spawned tasks
> - 5A: Add one sentence to §4.13: a spawned task performs with the handlers in force at its `async.spawn` site. Spawn is not a root; the static rule applies to `main` and test blocks only.
> - 5B: No §4.13 sentence.
>
> ## Q6. Panic message
> - 6A: The spec fixes the content (effect path and operation name), not the wording; the perform-site span is optional, as in panicked-status-reporting.
> - 6B: The spec fixes a stable prefix `no handler for effect operation ` followed by the qualified operation as written at the call (e.g. `zzstore.fetch.zzget`), optionally `(Zzstore.Fetch)`; anything after that (span, note naming the omitting handler) is free.

- **Q1: core rule** — 1A, 6-0
- **Q2: diagnostic identity** — 2A, 6-0
- **Q3: §4.6 text** — 3B, 5-1, PLT dissent (3A)
- **Q4: lowering in the spec** — 4A, 6-0
- **Q5: spawned tasks** — 5A, 6-0
- **Q6: panic message** — 3-3 (6A: Sys, PLT, Min; 6B: Web, DevOps, AI/ML) → Phase D

Votes (verbatim):

**Systems:**

> # Sys vote (ee5e9m)
>
> Q1: 1A. The static check costs nothing at runtime and moves the common mistake to build time; the runtime panic covers what the static check cannot prove. Concern: the transitive row computation for `main` must be complete, or the check gives false confidence.
>
> Q2: 2A. One code for one failure is simpler for tools and users. Concern: tools that match the old unnumbered test name need an update.
>
> Q3: 3B. It keeps the voted sentence and states the root-handler rule plainly. Concern: readers may skim past the added sentence.
>
> Q4: 4A. Lowering belongs in the decision record, not the spec. Concern: the C UB note must reach the implementation ticket.
>
> Q5: 5A. One sentence removes the doubt about spawn at no cost. Concern: none from my domain.
>
> Q6: 6A. Fix the content, not the wording. Concern: tests that match exact text may break when the wording changes.

**Web/Scripting:**

> # Web, Phase C vote (ee5e9m)
>
> ## Q1. Core rule: 1A
> Reasoning: The common mistake is "declared the effect, forgot the `with`", and 1A reports it at `check` time, at the line the dev wrote, with a fix. 1B reports the same mistake only when that path runs, which for an error branch or a weekly job means production. 1A also gives tests and `main` the same rule, so there is no "why did my test fail to compile but my program crashed?" question.
> Concern: Devs who learned "main holds all effects" may read E0539 as a compiler bug, unless the help line says plainly that user effects have no default handler.
>
> ## Q2. Diagnostic identity: 2A
> Reasoning: One mistake should have one code: one search term, one `blink explain` page, one quick fix. The header already says which root, so a second code adds nothing for the user. It also gives the unnumbered test diagnostic a number, which CI filters and docs links need.
> Concern: Folding `UnhandledEffectInTest` into the new code may leave old docs, examples and LLM training text showing the old name, so the migration must update every place that shows it.
>
> ## Q3. §4.6 text: 3B
> Reasoning: "main holds all effects" is the simple model devs already have. Adding one sentence that says user effects need a `with` keeps that model and corrects it where it matters. Rewriting the voted sentence reads like a reversal to anyone comparing spec versions.
> Concern: If the added sentence sits far from the "all effects" sentence, a skimming reader (or a model) will still take "all effects" literally, so it must come directly after it.
>
> ## Q4. Lowering in the spec: 4A
> Reasoning: Users care that the operation panics and never returns. They do not care whether a stub or a check does it. Sys's C undefined-behaviour constraint is real, and it belongs in the decision record and the implementation ticket, where the codegen author will read it.
> Concern: The implementation constraint (one stub per operation, exact signature) could be lost if it is only in the decision record, so the perform-stage ticket must quote it.
>
> ## Q5. Spawned tasks: 5A
> Reasoning: A JS/Python dev expects a task to see the context in force where it was started, as with AsyncLocalStorage or contextvars. One sentence states that, and confirms that spawn is not a third root. Without it, "does my handler reach into `async.spawn`?" becomes a common question.
> Concern: If the runtime does not pass the evidence into the task, the static check passes and the program panics at run time, so the corpus needs a test of `with h { async.spawn(...) }`.
>
> ## Q6. Panic message: 6B
> Reasoning: DevOps changed my mind: `assert_panics(matching: "...")` matches on the text, so the message is observable API, just like `pytest.raises(match=...)`. A stable prefix lets tests and agents match it across compiler upgrades, and leaves everything after it free to improve. The form `zzstore.fetch.zzget` is what the user wrote at the call site, so they recognise it at once.
> Concern: Once the prefix is fixed it can never be improved without breaking user tests, so it must be right the first time.

**PLT:**

> # PLT, Phase C vote (ee5e9m)
>
> ## Q1. Core rule — 1A
> Reasoning: An effect system has value only if it proves that a well-typed program never performs an operation with no handler. 1A gives that proof for every handler value. The only gap left is auto-delegated slots of partial handlers, and those trap with a `Never`-typed panic, which is sound for every answer type. 1B leaves a fault the compiler can prove to run time and deletes a stated guarantee in §4.12.
> Concern: the residual-row computation in `main` must use the same effect-row inference as the rest of typecheck (closures, `! _` forwarding, `async.scope`), or it will produce false positives or misses at the edges.
>
> ## Q2. Diagnostic identity — 2A
> Reasoning: Both roots use one typing rule: residual row ∩ effects with no root handler = ∅. Only the second set changes (all effects for a test, user effects for `main`). One rule should have one code, and the root belongs in the header.
> Concern: the existing `UnhandledEffectInTest` name in §2.20 must be migrated in the same change, or the spec will name two codes for one rule.
>
> ## Q3. §4.6 text — 3A
> Reasoning: "All built-in effects" is the precise statement of main's implicit row. "All effects" was never true for user effects. The change keeps the 5-0 decision's substance (no annotation on `main`) and makes the text match the typing rule. 3B keeps a sentence that the next sentence must then take back.
> Concern: the LSP inlay hint text in §4.6 should still show user effects that `main` discharges with `with`, so that readers do not confuse "held" with "performed".
>
> ## Q4. Lowering in the spec — 4A
> Reasoning: The spec fixes semantics: the operation diverges with type `Never` and produces no value. Stub layout is a representation choice and belongs in the decision record. The C fn-pointer UB point is correct and must go into the implementation ticket.
> Concern: if the decision record loses the "exact signature per stub" constraint, an implementer may cast one shared stub to every signature, which is UB in C.
>
> ## Q5. Spawned tasks — 5A
> Reasoning: Structured concurrency plus evidence passing means a task runs under the evidence of its spawn site. Stating this in one sentence fixes the semantics, so that codegen cannot pick up the root vector by mistake. It also confirms that `main` and test blocks are the only roots.
> Concern: if a future non-structured spawn (detached tasks) is added, it would be a new root and would need this rule again.
>
> ## Q6. Panic message — 6A
> Reasoning: The observable contract is the content: the effect path and the operation. The exact wording is UI, and panicked-status-reporting already treats it that way. Fixing a prefix is only useful to tools that grep stderr, and that is a weak reason to freeze text in the spec.
> Concern: without a fixed prefix, test authors who use `assert_panics(matching: ...)` may match on wording that later changes.

**DevOps:**

> # Phase C vote: DevOps/tooling (ee5e9m)
>
> ## Q1. Core rule
> 1. Vote: **1A**
> 2. Reasoning: The common mistake is declaring an effect and forgetting the `with`. 1A shows it in the editor, with a quick fix, on every path. 1B shows it as a crash on the first run of that path, which for a rare branch means production. The LSP already computes `main`'s transitive row for the §4.6 inlay hint, so the check only filters a set the toolchain already has. Tests and `main` then give one answer to one mistake.
> 3. Concern: If the static check and the runtime trap disagree about what counts as "discharged" (for example, a handler installed by a BlockHandler `Context`), users get a compile error for a program that would run, or no error for one that panics. Both halves must share one definition of discharge.
>
> ## Q2. Diagnostic identity
> 1. Vote: **2A**
> 2. Reasoning: This was my Phase A proposal. I withdrew it in round 1 only to avoid a fight, and the other five have since moved to it. One code gives one `blink explain` page, one LSP quick-fix provider and one CI filter. It also gives the unnumbered test diagnostic a number as part of this decision instead of a later chore. The header still names the root, so no information is lost.
> 3. Concern: Folding in `UnhandledEffectInTest` changes the name in existing golden diagnostic output and in the 02_syntax.md example. The implementation must update both in the same change, or `task ci` goldens drift.
>
> ## Q3. §4.6 text
> 1. Vote: **3B**
> 2. Reasoning: My concern was a reader who stops at "all effects" and expects the MVCE to compile. 3B puts the qualifier in the next sentence, by name, with a pointer to §4.12. That answers the concern without rewriting the text of a 5-0 vote. Docs tooling and LLM retrieval pick up the section as a whole, so an adjacent explicit sentence is enough.
> 3. Concern: Search results and inlay-hint tooltips that quote only the first sentence of §4.6 will still say "all effects". The E0539 help line must say "user-declared effects have no root handler" so the user sees the reason where the error appears.
>
> ## Q4. Lowering in the spec
> 1. Vote: **4A**
> 2. Reasoning: The user sees the panic, the fact that the call never returns, and the absence of a value. Stubs versus checks is not visible and must be free to change, for example for a non-C target. Sys's warning about undefined behaviour is real and must go in the implementation ticket for the perform stage, so the vtable codegen does not reintroduce a single shared stub.
> 3. Concern: If the UB constraint goes only into the decision record and not into the perform-stage ticket, an implementer can miss it. The moderator should copy it into the br ticket.
>
> ## Q5. Spawned tasks
> 1. Vote: **5A**
> 2. Reasoning: The static rule is sound only if a task inherits the handlers at its spawn site. Without that sentence, codegen could pick up the root evidence vector, and then the check would pass for programs that panic. One sentence in §4.13 makes the assumption explicit and testable. It also matches what JS and Python developers expect from AsyncLocalStorage and contextvars.
> 3. Concern: Tasks spawned through a handler value stored past its `with` scope (handlers are first-class values) may test the edge of "in force at the spawn site". A corpus test should cover spawn inside `with` with the perform inside the task.
>
> ## Q6. Panic message
> 1. Vote: **6B**
> 2. Reasoning: `assert_panics(matching: "...")` (§2.20, §6.x) matches on the message text, so the text is part of the API that tests depend on. If the spec fixes only the content, a compiler upgrade that rewords the message breaks user tests that match on it. Log alerting and agent repair loops also match on a fixed prefix. Fixing the prefix and the operation spelling costs nothing and leaves the rest free.
> 3. Concern: If 6A wins, nothing stops the wording from changing between releases. Then `assert_panics(matching:)` tests and log alerts that match on it break with no diagnostic. 6A should at least require that the wording not change within a major version.

**AI/ML:**

> # Phase C vote — AI/ML (ee5e9m)
>
> ## Q1. Core rule: 1A
> Reasoning: The most common way generated code gets effects wrong is to declare the effect and forget the `with`. 1A rejects that at `check` time on every path, including untested branches, and the error gives the agent's repair loop a fix-it line. 1A also keeps one rule a model can learn from the spec: tests and `main` behave the same, and §4.12's promise stays true. Correct programs pay no tokens and gain no new decision point.
> Concern: Users may read the static check as a guarantee and be surprised when a partial handler that auto-delegates to nothing still panics at run time. The spec must say plainly that the panic covers that one leftover case.
>
> ## Q2. Diagnostic identity: 2A
> Reasoning: One mistake should have one name, one `blink explain` page and one fix-it. A model learns and greps one code more reliably than a pair of near-identical siblings. Folding the unnumbered `UnhandledEffectInTest` into it removes a name instead of adding one.
> Concern: Existing docs, examples and any training text that say `UnhandledEffectInTest` go stale. The spec should point the old name to the new code once.
>
> ## Q3. §4.6 text: 3B
> Reasoning: My condition was an explicit sentence in §4.6, so a reader of §4.6 alone predicts the error, and 3B gives that. It does so without rewording a 5-0 vote, so a future reader will not take it for a reversal. The capability model ("main holds everything") and the handler rule ("user effects have no root handler") are both stated outright.
> Concern: If the added sentence sits far below "implicitly holds all effects", a model reading only the code example and the first sentence still writes the MVCE. Put it right after the voted sentence.
>
> ## Q4. Lowering in the spec: 4A
> Reasoning: The language spec is what models learn from. Implementation detail in it adds tokens and suggests rules users must follow when they need not. The observable contract (panics, never returns, no default value) is what users and models must know. Sys's C undefined-behaviour constraint belongs in the decision record.
> Concern: The UB constraint could get lost between the decision record and the perform-stage ticket. The ticket must copy it word for word.
>
> ## Q5. Spawned tasks: 5A
> Reasoning: One sentence answers a question a model would otherwise guess at, and it matches the AsyncLocalStorage/contextvars intuition most training data carries. It also pins the static rule's soundness to a stated runtime contract, so codegen cannot pick up the root handlers by mistake.
> Concern: If the runtime does not pass the spawn site's handlers to the task today, the sentence describes intent rather than behaviour until a codegen ticket fixes it.
>
> ## Q6. Panic message: 6B
> Reasoning: DevOps is right that `assert_panics(matching: ...)` makes the message observable API. Agents write tests that match on panic text, so a fixed prefix makes them work across compiler versions. A fixed prefix is also one exact string a model can learn and a tool can match on. Everything after the prefix stays free, so tooling can still improve the rest.
> Concern: If 6A wins, tests that match on today's wording break when it changes, and generated tests will do exactly that.

**Minimalism:**

> **Min, Phase C vote (ee5e9m)**
>
> ## Q1. Vote: 1A
> Reasoning: The static half reuses the UnhandledEffectInTest rule at the other root that holds effects without declaring them, so it adds no new concept. It also makes §4.12's existing promise true, so we do not need to reword it. The runtime panic removes the zero-value tables, the null-handle segfaults and the `Never` special case. 1B would need a documented exception for `main`, which adds more to the spec than 1A does.
> Concern: Users may read the static check as complete. The spec text must say that partial handlers and `default.op()` can still reach the runtime panic.
>
> ## Q2. Vote: 2A
> Reasoning: One code, one doc entry and one quick-fix for one rule. Folding the unnumbered test name into it removes a diagnostic instead of adding one. The header that names the root keeps all the information that two codes would carry.
> Concern: Tools that already match the string `UnhandledEffectInTest` will break. Keep it as a documented alias for one release, or grep for users of it before the fold.
>
> ## Q3. Vote: 3B
> Reasoning: The result is the same as 3A, but 3B adds to the voted text and does not rewrite it. A later reader then does not see the 5-0 decision as reversed. It is the smaller change.
> Concern: "Every capability the root can provide" is vaguer than 3A's "built-in". The added sentence must name built-in versus user-declared explicitly, or readers will argue about what "can provide" means.
>
> ## Q4. Vote: 4A
> Reasoning: The spec states behaviour that holds for any backend. Per-operation stubs are the correct C lowering, and they belong in the decision record and in codegen. If the spec named the lowering, any backend change would force a spec change.
> Concern: The rule against one stub cast to every signature (C undefined behaviour) could get lost if it lives only in a decision record. The implementation ticket must carry it as an explicit acceptance criterion.
>
> ## Q5. Vote: 5A
> Reasoning: Sys confirmed that spawn is not a second root, so the sentence states existing design and adds no rule. One sentence is cheaper than the future friction ticket that asks "do spawned tasks see my handlers?"
> Concern: The sentence could be read as dynamic capture at run time. It must say "in force at the `async.spawn` site", lexically, which matches the scope rule.
>
> ## Q6. Vote: 6A
> Reasoning: The spec fixes what the message must tell the reader (the effect and the operation) and leaves the wording free, as panicked-status-reporting does. A fixed prefix is a string contract that nobody asked for. Tests should match on the effect and operation names, not on the wording.
> Concern: Without a stable prefix, tooling and `assert_panics` message matches may anchor on wording that changes later. If that becomes friction, a stable prefix is easy to add later; taking one away is not.

#### Phase D — Round 2 (Q6 only)

The moderator gave the panel two facts: no sentence in sections/ makes a runtime panic's text normative, and §2.20 makes `assert_panics(matching:)` a substring test. Debate replies (verbatim):

**Systems:**

> # Sys, Phase D debate (Q6)
>
> **DevOps's point holds.** `assert_panics(matching:)` matches on substrings, and §2.20 already counts on a stable part of a panic message ("index out of bounds"). So in practice the text is API. I move toward 6B.
>
> **One problem with 6B as written.** "The qualified operation *as written at the call*" puts call-site data into the panic. The trap belongs to the operation, not to the call site, so it knows only the declared operation. Two calls that spell the same operation in different ways (an alias import, for example) would need either a stub per call site or a name passed on every perform. That is a real cost on the hot path, paid to support a rare failure.
>
> **My fix.** Fix the prefix, but derive the name from the declaration, not from the call: `no handler for effect operation zzstore.fetch.zzget`. Here the name is the operation's canonical lowercase path from its declaration. With no alias it reads the same as the call. It is one constant string per operation, and it costs nothing at runtime.
>
> With that change I vote 6B. Without it, I stay on 6A and support DevOps's fallback: keep the wording stable within a major version.

**Web/Scripting:**

> # Web, Phase D debate on Q6 (ee5e9m)
>
> I voted 6B. After the codebase facts in the digest and one more read of the decisions folder, I now lean to **6A, with one amendment**. Here is why, and what I still want from the 6B side.
>
> ## What changed my mind
>
> 1. **No panic text in Blink is normative today.** The moderator found no normative panic string in sections/. `decisions/unwrap-panic-message-format.md` says it directly: "The language spec does **not** pin the text of an unwrap panic message. The only normative contract over panic message contents is `assert_panics matching:` ... which matches a caller-supplied **substring** and explicitly treats the rest of the message as volatile." Under 6B, this one panic would be the only one in the language with a spec-fixed text. "Index out of bounds" and "unwrap called on Err" would not be. A dev would not guess that, and an inconsistent rule produces more questions than no rule.
>
> 2. **Substring matching already solves the test-stability problem, if the spec fixes the right content.** The 6B case (mine included) was "`assert_panics(matching:)` is observable API, like `pytest.raises(match=...)`". That holds, but what a test author matches on is the *operation*, not the sentence around it. A dev writes `assert_panics(matching: "zzget")`. 6A already guarantees the operation name is in the message, so that test stays green whatever the wording. This is how §2.20 says matching is meant to work: match "the stable part" and ignore the rest.
>
> 3. **Min's asymmetry argument holds.** If friction shows up, adding a stable prefix later is a non-breaking change. Removing one breaks every test that matched on it. My own Phase C concern ("it must be right the first time") argues for waiting.
>
> ## The amendment I want on 6A (this is my condition)
>
> 6A as written says "effect path and operation name" but not how they are spelled. A test that matches on `Zzstore.Fetch.zzget` must not break because the message changes to `zzstore.fetch.zzget`. So:
>
> > The message contains the operation name exactly as declared (e.g. `zzget`) and the effect path exactly as declared (e.g. `Zzstore.Fetch`). The surrounding wording and the span are not specified.
>
> This gives tests and agents the stable substrings they need (DevOps's and AI/ML's real concern) without freezing the sentence. The current wording then goes in the decision record as an implementation choice, the way unwrap's format is recorded.
>
> ## To DevOps and AI/ML
>
> Your concern is real: tests and log alerts match on text. But tests should match on what this decision guarantees: the op name and the effect path. Log alerting on panic text is a cross-cutting need. If the panel wants stable panic prefixes, give *every* built-in panic one in a separate spec ticket, not just this one. I would support that ticket, and I would file it as friction.
>
> **Not voting yet.** Unless a 6B seat shows a test or tool that cannot match on a declared name, I will vote 6A with the amendment above.

**PLT:**

> # PLT, Phase D debate on Q6 (ee5e9m)
>
> ## What the 6B side gets right
>
> `assert_panics(matching:)` makes panic text something users can observe. I named this same risk as my own concern in Phase C. I agree that a test must have a stable substring to match on.
>
> ## Why I still hold 6A
>
> **1. No runtime panic in the spec has a normative text today.** The moderator found no such sentence in sections/. The nearest precedent, decisions/unwrap-panic-message-format.md, goes further. It pins a user-observable panic string *as a decision record*, and it says why: "The language spec does not pin the text of an unwrap panic message. The only normative contract over panic message contents is `assert_panics matching:` ... which ... explicitly treats the rest of the message as volatile." §2.20:1491 says the same: a substring "matches the stable part ... while ignoring the location".
>
> If 6B wins, this one panic gets a spec-frozen prefix, while `index out of bounds` and `unwrap called on Err` do not. That is an inconsistency in the language contract. The principled route is a general rule for all runtime panic texts, not a one-off rule for one panic. That general rule is a separate spec question, and it should not ride on ee5e9m.
>
> **2. 6B's real need is covered by 6A's content, if we make one point precise.** A test needs one stable *substring*, not a stable prefix. 6A already fixes the content: the message names the operation. I propose the 6A text also fix *how the operation is spelled*: the qualified path as written at the call, e.g. `zzstore.fetch.zzget`. Then:
>
> ```blink
> test "unwired store panics" {
>     assert_panics(matching: "zzstore.fetch.zzget") {
>         load()
>     }
> }
> ```
>
> That test is stable across every compiler version under 6A as amended. It is also *more* precise than matching the prefix `no handler for effect operation `, which cannot tell which operation was unhandled. The prefix adds no test capability that the operation path does not already give.
>
> **3. Freezing English prose in the spec is the costly direction.** Web conceded it: "Once the prefix is fixed it can never be improved without breaking user tests." Min's asymmetry is the decisive point. We can add a stable prefix later if real friction appears. We can never remove one. With an unproven need, the reversible choice wins.
>
> ## Proposed synthesis (for the moderator to offer, if the panel wants it)
>
> - §4.7.1 (spec): the panic message names the operation by its qualified path as written at the call (`zzstore.fetch.zzget`) and the effect path (`Zzstore.Fetch`). Wording is otherwise free. The span is optional.
> - Decision record for ee5e9m (not spec): records the current text `no handler for effect operation <path> (<Effect>)`, with the same status as the unwrap format. Tools and agents can then rely on it in practice, and the spec still makes one uniform claim about panic text.
> - DevOps's "no change within a major version" request would be a policy for all panic texts. I would support that as a separate friction/spec ticket covering every runtime panic, not this one alone.
>
> If the synthesis is offered, I vote for it. Otherwise 6A.

**DevOps:**

> # DevOps: Phase D debate on Q6
>
> ## The spec already promises a stable part
>
> The moderator's fact settles most of this. §2.20 (02_syntax.md:1491) says substring matching is deliberate because a panic message has "the stable part (`"index out of bounds"`)" plus a volatile location suffix. So the spec already tells users that a panic message has a stable part and that their tests should match on it. 6A leaves that part unnamed for this panic. A user who follows §2.20 then has nothing stable to match on. 6B names the stable part. It does not add a new kind of contract. It fills in one that §2.20 already assumes.
>
> ## Answers to the 6A side
>
> **PLT: "a prefix is only useful to tools that grep stderr".** That is not the main user. The main user is `assert_panics(matching: ...)`, a language feature with a spec section. Its matching unit is the message text.
>
> **Min: "tests should match on the effect and operation names, not the wording".** I agree with the goal. But 6A does not fix how the names are spelled either. Each of these is valid under 6A:
> - `zzstore.fetch.zzget`
> - `Zzstore.Fetch.zzget`
> - `Zzstore.Fetch::zzget`
> - `zzget (Zzstore.Fetch)`
>
> A test that matches `"zzstore.fetch.zzget"` breaks when an implementer picks a different form. Matching only `"zzget"` is too weak: it also matches an unrelated panic whose message mentions that name. So even Min's proposed rule for tests needs the spelling of the operation fixed.
>
> **Min: "easy to add later, hard to take away".** That is true in general, but not here. Tests written before the prefix is fixed match whatever text the first implementation prints, and that is the text that ships in the perform stage. The real choice is whether we choose that text now, in the spec, or let the first implementer choose it by accident. LLM-generated tests (AI/ML's point) will copy the first wording they see either way.
>
> **Sys and PLT both name the 6B risk as their own concern.** Their stated concern with 6A is that `assert_panics` tests break when the wording changes. That concern is the case for 6B.
>
> ## A compromise that may break the tie
>
> If the 6A seats object to freezing prose ("no handler for effect operation"), I accept a narrower form:
>
> **6A+**: the spec fixes the content *and the spelling of the operation*. The message contains the qualified operation exactly as the user writes it at the call (`zzstore.fetch.zzget`). The wording around it, the declared path, and the span are free.
>
> This freezes no prose, only an identifier the user already wrote. It gives `assert_panics(matching: "zzstore.fetch.zzget")` a stable target, which is Min's own rule for tests. I rank 6B > 6A+ > 6A. If the moderator puts 6A+ on the ballot, I would vote for it over 6A without hesitation.
>
> ## Web's concern (the prefix must be right the first time)
>
> That is correct, and it is why the prefix is short and literal: `no handler for effect operation`. It says what happened in the words a user would search for. There is nothing in it that a later improvement would need to change. Improvements go after the operation name, where 6B leaves the text free.

**AI/ML:**

> # Phase D debate — AI/ML (Q6 only)
>
> ## What the 6A side gets right
>
> The moderator's facts and decisions/unwrap-panic-message-format.md show that no runtime panic text in Blink is normative today. The only contract is `assert_panics(matching:)`, and it is a **substring** match designed so tests anchor on the stable part of the message. 6B would make this panic the first one with fixed spec text. For learnability that matters: one rule ("panic text is not spec; match on the names") is easier to learn than "panic text is not spec, except this one". Min's point about one-way doors is also sound: a prefix is easy to add later and impossible to take back.
>
> ## What 6A still leaves open
>
> What a test or an agent actually matches on is the **operation name**. Min says as much: "Tests should match on the effect and operation names." 6A fixes that the name appears but not how it is spelled. All of these meet 6A:
>
> - `zzstore.fetch.zzget`
> - `Zzstore.Fetch.zzget`
> - `Zzstore.Fetch::zzget`
>
> The Phase A drafts already differed this way (Web/DevOps used the call-site spelling, PLT and Min the declared path). A model writing `assert_panics(matching: "zzstore.fetch.zzget")` copies the spelling from its own call site. Under 6A as written, that test can break on a compiler upgrade with no wording change at all, only a change of spelling. This failure is the one I flagged in Phase C, and the prefix was never the part that mattered for it.
>
> ## Bridge proposal
>
> Take 6A, plus one clause: **the message contains the operation spelled as written at the perform site (e.g. `zzstore.fetch.zzget`)**. Drop the fixed prefix.
>
> - It keeps the 6A principle and the unwrap precedent: no fixed wording, no prefix contract.
> - It gives `matching:` one stable anchor, and it is the name the user and the model already typed. No new string to learn.
> - It answers DevOps's and Web's concern (tests stay valid across upgrades) without freezing any prose.
> - PLT's concern (freezing UI text) does not apply: an identifier spelling is not wording.
>
> ## My position
>
> If the moderator can put this clause on the ballot as part of 6A, I move to 6A. If the ballot stays the strict 6A/6B text, I hold 6B, because 6A as written leaves the spelling open, and that is the thing generated tests depend on.

**Minimalism:**

> **Min, Phase D debate (Q6 only)**
>
> I accept the 6B side's premise. `assert_panics(matching:)` makes panic text observable, so some part of it is API. I do not accept their conclusion that the right fix is a prose prefix. Three points.
>
> **1. Substring matching already gives a stable anchor under 6A, if we fix one spelling.**
> §2.20 (02_syntax.md:1491) says matching is by substring "deliberate[ly]", so that tests match "the stable part". The stable part of this panic is the operation, not the English around it. A test written as `assert_panics(matching: "zzstore.fetch.zzget")` survives any rewording of the prose. 6A as written has one real gap: it fixes the operation *name* but not its *spelling* (`zzstore.fetch.zzget` or `Zzstore.Fetch.zzget`). Web's point is good: the call-site form is what the user wrote and will search for.
>
> So I propose an amendment (6A'), which I will vote for: the spec fixes the content, and fixes that the operation appears exactly as qualified at the call site (`zzstore.fetch.zzget`). The prose around it is not normative. This gives tests, log alerts and agents one exact token to match. It freezes no English.
>
> **2. 6B would make this the only runtime panic in the spec with normative text.**
> The moderator found no sentence in sections/ that makes any runtime panic's text normative. Index out of bounds, unwrap on None and arithmetic overflow are all de facto stable at best. Fixing a prefix for this one panic is an ad hoc exception, and the next ticket will ask why `index out of bounds` is not fixed too. If the panel wants stable panic prefixes, that is a single policy for every built-in panic. Decide it once, in its own ticket, under panicked-status-reporting, not as a side effect of ee5e9m. I would support logging that ticket.
>
> **3. Reversibility favours the smaller contract.**
> Web's own concern makes my case: "it can never be improved without breaking user tests, so it must be right the first time." We are choosing English wording in a design panel about an operation that does not run yet (the perform half has not landed). Under 6A', adding a fixed prefix later is backward-compatible. Removing 6B's prefix later is a breaking change. When we are unsure, freeze the smaller thing.
>
> **On DevOps's fallback** ("6A should at least require that the wording not change within a major version"): I accept that as a general rule for panic text. It costs nothing in the spec and gives log alerts what they need. It also belongs in the cross-panic policy from point 2, not only in this one message.
>
> **Summary for the moderator:** I offer 6A' = 6A + "the operation appears as qualified at the call site, e.g. `zzstore.fetch.zzget`". If the moderator puts 6A' on the ballot, I think it meets the stated concerns of Web, DevOps and AI/ML (a stable token that agents and tests can match) without fixing prose. If the ballot stays 6A versus 6B, I stay on 6A, and I ask that a follow-up ticket be logged for a stable-prefix policy across all panics.

Before the vote the moderator gave the panel two more facts: the handle is always the lowercase form of the top-level effect name and sub-effects create no handle (§4.4), and module aliases and renamed imports exist (§10.5). The ballot listed the five options the panel had proposed:

- **6A** — the spec fixes the content (effect path + operation name), not the wording.
- **6B** — fixed prefix `no handler for effect operation ` + the qualified operation as written at the call.
- **6B-decl** (Sys) — the 6B prefix + the operation's canonical lowercase path from its declaration.
- **6A-call** (Min, DevOps, AI/ML, PLT) — no fixed wording; the message contains the operation spelled as qualified at the call.
- **6A-decl** (Web) — no fixed wording; the message contains the operation name and effect path as declared.

**Result: 6A-call, 4-2** (Web, DevOps, AI/ML, Min; PLT for 6A-decl, Sys for 6B-decl). Phase D is capped at one round, so the majority result ships with the dissent recorded.

Votes (verbatim):

**Systems:** *(dissent)*

> # Sys vote (Q6, Phase D)
>
> 1. **First choice** — 6B-decl
>
> 2. **Full ranking** — 6B-decl, 6A-decl, 6A-call, 6B, 6A
>
> 3. **Reasoning** — `assert_panics(matching:)` makes panic text observable, and a fixed prefix plus one exact operation token gives tests and tools a stable anchor. The trap belongs to the operation, not to the call, so the name comes from the declaration: one constant string per operation, no cost on the perform path, and no stub per call site for aliased imports. Handles are always the lowercase form of the effect name (04_effects.md:252), so the declared path reads the same as the call in the common case. If the prefix does not win, I prefer 6A-decl over 6A-call because it avoids call-site data in the panic.
>
> 4. **Concern** — A fixed prefix freezes English wording in the spec for one panic only, which is inconsistent with the unwrap precedent, and it can never be improved without breaking tests that match on it.

**Web/Scripting:**

> # Web, Phase D vote on Q6 (ee5e9m)
>
> 1. **First choice:** 6A-call
>
> 2. **Full ranking:** 6A-call > 6A-decl > 6A > 6B-decl > 6B
>
> 3. **Reasoning:** DevOps and AI/ML were right that my 6A-decl leaves a gap. A dev copies `zzstore.fetch.zzget` from their own call site into `assert_panics(matching: ...)`, so that spelling is the stable substring the message must contain. It freezes an identifier the user already typed, not English prose, so it keeps the unwrap precedent (no normative panic wording) and stays reversible. Five of six seats proposed it in some form, so it ends the tie on common ground.
>
>    One clarification to record in the decision, from Sys's cost point: read "as qualified at the call" as the operation's canonical lowercase path from its declaration (handle = lowercase effect name, §4.12 / 04_effects.md:252). That is one constant string per operation, with no call-site data on the hot path. In every case except a renamed import, it is the same text the user typed.
>
> 4. **Concern:** If a renamed import ever changes the handle spelling at the call site, "as written at the call" and the declared path disagree. The decision record must say which one wins (the declared path), or the implementer pays a per-call cost or a test silently fails to match.

**PLT:** *(dissent)*

> # PLT, Phase D vote on Q6 (ee5e9m)
>
> 1. **First choice:** 6A-decl
>
> 2. **Full ranking:** 6A-decl > 6A > 6A-call > 6B-decl > 6B
>
> 3. **Reasoning:** I move from my own synthesis (6A-call) because of the moderator's §4.4 fact and Sys's point. The call-site spelling is not a property of the operation. Sub-effects create no handle (04_effects.md:252), so the call reads `zzstore.zzget()` while the operation's identity is `Zzstore.Fetch.zzget`. Renamed imports can also change what the user writes. A name that depends on the call site is not canonical, and it forces either a stub per call site or a name passed on every perform. The declared effect path and the declared operation name are canonical, unique and known statically. A per-operation trap can carry them at zero cost. A test can match on `Zzstore.Fetch` or `zzget`, and no English prose is frozen, which is consistent with the unwrap decision record.
>
> 4. **Concern:** the declared form (`Zzstore.Fetch`, `zzget`) differs from what the user typed at the call (`zzstore.zzget`). So a user or model that copies the call-site spelling into `matching:` gets a mismatch, though E0832 shows the full actual message, and the fix is then obvious.

**DevOps:**

> # DevOps: Phase D vote on Q6
>
> 1. **First choice:** 6A-call
>
> 2. **Full ranking:** 6A-call > 6B > 6B-decl > 6A-decl > 6A
>
> 3. **Reasoning:** What I care about is that a test or a log alert has one exact token that does not change between compiler versions. 6A-call gives that token without freezing English. The unwrap precedent (decisions/unwrap-panic-message-format.md) persuades me that a prose prefix for this one panic is an inconsistency, and it is better solved as a policy for all panics in its own ticket. 6A-decl is weaker for tooling because it gives two separate tokens (`zzget`, `Zzstore.Fetch`), and the bare op name alone can match unrelated panics.
>
>    **A correction every 6A-call/6B example needs.** The moderator's fact at 04_effects.md:252 says the handle is always the lowercase top-level effect name and that sub-effects do not create handles. So the call is written `zzstore.zzget()`, not `zzstore.fetch.zzget()`. The MVCE in the ticket uses the sub-effect form, which §4.4 does not allow. The spec text and the decision record must use `zzstore.zzget` as the example token. This also answers Sys's cost concern for 6B: the handle cannot be aliased (it is not an import name), so "as written at the call" and "derived from the declaration" are the same constant string per operation. No per-call-site data reaches the trap.
>
> 4. **Concern:** If the spec example keeps `zzstore.fetch.zzget`, the implementer will print a form no user ever writes, and `assert_panics(matching:)` tests copied from real call sites will not match. Fix the example to `zzstore.zzget` before recording.

**AI/ML:**

> # Phase D vote — AI/ML (Q6)
>
> 1. **First choice:** 6A-call
>
> 2. **Full ranking:** 6A-call > 6B-decl > 6B > 6A-decl > 6A
>
> 3. **Reasoning:** 6A-call gives tests and agents the one stable token they need, the operation exactly as written in code (`zzstore.fetch.zzget`). A model writing `assert_panics(matching: ...)` copies that from its own call site. It freezes no English prose and keeps the language-wide rule a model can learn ("panic text is not spec; match on the names"). On Sys's cost concern: §4.4/§4.12 say the handle is always the lowercase form of the top-level effect name, so call-site spelling and the canonical declared lowercase path should be the same string. The trap can then be one constant per operation, with no per-call-site data. 6A-decl ranks low because a split `zzget` + `Zzstore.Fetch` is not the string anyone writes, so a model's natural `matching:` text would not hit it.
>
> 4. **Concern:** If the panel later allows a handle to be renamed at an import, "as written at the call" and the canonical declared path would diverge. The decision record should then pin the canonical lowercase path, not per-call-site spelling, so the trap stays one constant per operation.

**Minimalism:**

> **Min, Phase D vote (Q6)**
>
> 1. **First choice:** 6A-call
>
> 2. **Full ranking:** 6A-call > 6A-decl > 6A > 6B-decl > 6B
>
> 3. **Reasoning:** 6A-call gives tests, log alerts and agents one exact token to match. That token is the identifier the user already typed. No English text becomes a contract, and Blink's single rule stays intact: panic text is not spec, and tests match on names. Sys's hot-path point is real, so I read "as qualified at the call" as the canonical lowercase handle path. By §4.4:252 and :1912, the handle is always the lowercase effect name, so in the normal case the call form and the declared form are the same string. One constant per operation, no data from the call site, no cost at run time. A stable prefix can still be added later in a separate ticket that covers every panic; under this option nothing has to be taken back.
>
> 4. **Concern:** If an alias (a module alias or a renamed import) can ever change how the call is spelled, "as written at the call" would require call-site data in the trap. The spec text must pin the canonical lowercase handle path, `zzstore.fetch.zzget`, not the literal text at each call site.

**Reading of the Q6 result (confirmed by the user at sign-off).** DevOps pointed out that the example spelling `zzstore.fetch.zzget` is not a form a program can write: under §4.4 the call is `zzstore.zzget()`. Web, AI/ML and Min each said in their vote that "as qualified at the call" means the operation's canonical lowercase handle path, one constant per operation. Under §4.4 that path is `<handle>.<op>`, the same string a program writes. The spec therefore states the token as `<handle>.<op>` (e.g. `cache.put`). The panic carries no data from the call site.

### Final Spec

```blink
effect Cache {
    fn get(key: Str) -> Option[Int]
    fn put(key: Str, value: Int)
}

fn load() -> Option[Int] ! Cache {
    cache.get("hits")
}

// error[UnhandledEffect] (E0539): unhandled effect `Cache` in `main`
fn main() {
    io.println("{load()}")
}

fn read_only_cache() -> Handler[Cache] {
    handler Cache {
        fn get(key: Str) -> Option[Int] { None }
    }
}

test "an omitted operation panics" {
    with read_only_cache() {
        assert_panics(matching: "cache.put") {
            cache.put("hits", 1)
        }
    }
}
```

- **Roots (Q1, Q2).** A user-declared effect that reaches `main` with no `with` that discharges it is `UnhandledEffect` (E0539). Test blocks are the other root; the same code reports any undischarged effect there, and `UnhandledEffectInTest` folds into it. The header names the root (in `main`, or in test "…"). In `main` the help line says user-declared effects have no root handler.
- **§4.6 (Q3).** "`main` implicitly holds all effects" stays. The added text says the root has handlers for built-in effects only, and that a user-declared effect needs a `with`.
- **Run time (Q1, Q4).** An operation that finds no handler (a partial handler's omitted operation with no outer handler, or `default.op()` with no outer handler) panics. It never returns and never produces a default value, for any return type, `-> Never` included. The spec states only this behaviour.
- **Lowering (Q4, decision record only).** One generated stub per operation, with the operation's exact C signature, that calls a `noreturn` panic. Never one shared stub cast to every signature: calling through a mismatched function-pointer type is undefined behaviour in C.
- **Spawn (Q5).** A spawned task performs with the handlers in force at its `async.spawn` site. Spawn is not a root.
- **Panic message (Q6).** The message contains the operation as a program calls it, `<handle>.<op>`. The rest of the wording and the source location are not specified. A test matches on the operation.

### Concerns carried to the implementation

- The static check and the runtime panic share one definition of "discharged", a `BlockHandler` whose `Context` is `Handler[E]` included (Sys, PLT).
- The check uses the same row inference as the type checker (closures, `! _`, `async.scope`); a missed effect gives false confidence (PLT, AI/ML).
- The spec and docs say plainly that a partial handler or `default.op()` can still panic after the compile-time check passes (AI/ML, Min).
- Rename `UnhandledEffectInTest` and update the §2.20 example and any golden output in the same change (DevOps). No source or test in the repo used the old name when this was decided.
- The E0539 help line says user-declared effects have no root handler (Web).
- The LSP inlay hint on `main` still lists user effects that `main` discharges (DevOps).
- A corpus test for `with h { async.spawn(...) }` with the operation performed inside the task (Sys, AI/ML).
- Copy the C stub rule into the perform-stage ticket, not only this record (DevOps).

### Follow-ups

- If an aliased import can ever change how a handle is spelled at the call, the panic still uses the declared `<handle>.<op>`; the spec should then say so (Web, AI/ML, Min).
- A separate spec question: should every built-in panic get a stable message prefix, and should panic wording stay fixed within a major version? (Min, PLT, Web, DevOps.)
