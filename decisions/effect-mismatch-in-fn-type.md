[< All Decisions](../DECISIONS.md)

# A Function Type's Row Does Not Fit: EffectMismatchInFnType (E0574) — Design Rationale

**Gap:** §4.15.1 printed `error[EffectMismatchInFnType]` for an effectful callback given where a pure fn type is expected, and §4.15.4 named it for a pure slot. ERROR_CATALOG.md had no row and no code for it, and the compiler emitted nothing: an effectful closure passed into a pure parameter passed `blink check`. The closure-effects decision (a closure is charged at its call) is sound only if this check runs at every site where a value meets a declared type.

```blink
fn apply(f: fn(Int) -> Int, x: Int) -> Int {
    f(x)
}

fn main() ! IO.Log {
    let logger = fn(n: Int) -> Int ! IO.Log {
        io.log("got {n}")
        n
    }
    apply(logger, 42)     // was: no error; now E0574
}
```

**Already decided (not on the ballot):** the rule that a pure slot rejects an effectful closure and that pure fits effectful (§4.15.1); closures charged at the call (6-0); row slots and E0571-E0573; pre-1.0 new errors ship as errors; published names are frozen.

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in independent-proposal → debate → vote rounds. Phase B ran one round; all six said they were stable. Phase D did not run (every question 6-0).

#### Phase A — Independent proposals

All six proposed an own catalog row, `EffectMismatchInFnType`, E0574, category Effects. All six rejected folding it into E0300 and reusing E0500.

- **Systems:**

> sys Phase A: give EffectMismatchInFnType its own row, E0574, category Effects, section §4.15.1 (plus §4.15.4, §4.15.5).
>
> **Q0: own row, yes.** The spec already prints `error[EffectMismatchInFnType]`, and names freeze once published. Folding it into TypeMismatch (E03xx) would make the spec example false and hide the one fact that matters: the shapes match and only the row is wider. E0563 is the precedent: a coercion that fails only on effect width gets its own Effects code. E0500 is wrong because no call happens at the site. The row is charged later, where the closure runs, so this is the only check that keeps that row sound.
>
> **Q1: E0574, Effects, §4.15.1.** It is the next free number and sits beside E0571-E0573, the codes of the feature that needs it.
>
> **Behavior**
> - Fires at every coercion site with a declared target type: call/method argument, annotated `let`, return value, struct-literal field (pure field or `Cleanup[! IO]` into a rowless slot), assignment to a typed place, list/map element against a declared element type. That is the same site list as E0563, so both share one coercion walk.
> - Fires only when the fn shapes unify and the source row holds an effect the target row lacks. If params or return types also differ, the error is TypeMismatch. One diagnostic per site, never both.
> - Nested positions follow variance. `[fn() ! IO]` into `[fn()]` fires. In a param position the rule reverses: passing `fn(cb: fn() -> Int)` where `fn(fn() -> Int ! IO) -> Int` is expected is fine.
> - The label names the effects the target lacks. A `note:` names the slot that requires pure. No machine-applicable fix: two fixes are possible, and the compiler cannot pick one.
> - JSON `"code": "E0574"`. `blink explain E0574` and `blink explain EffectMismatchInFnType` resolve to the same entry. Not suppressible by `@allow`: it is a soundness error, the same as E0500.
>
> ```blink
> fn apply(f: fn(Int) -> Int, x: Int) -> Int {
>     f(x)
> }
>
> fn main() ! IO.Log {
>     let logger = fn(n: Int) -> Int ! IO.Log {
>         log.info("got {n}")
>         n
>     }
>     apply(logger, 42)
> }
> ```
> ```
> error[EffectMismatchInFnType]: effect mismatch in function type
>  --> app.bl:10:11
>    |
> 10 |     apply(logger, 42)
>    |           ^^^^^^ expected pure `fn(Int) -> Int`, found `fn(Int) -> Int ! IO.Log`
>    |
>    = note: `apply` requires a pure callback
>    = help: change `apply` to take `fn(Int) -> Int ! _`, or remove `IO.Log` from the callback
> ```
>
> **Tradeoffs (systems)**
> - Zero runtime cost. This is a type-level check. Pure-into-effectful must also stay free: no thunk or wrapper at the coercion. If effects ever use evidence passing, pure and effectful fn pointers must keep one ABI, or "pure is a subtype" quietly costs an allocation. A writer should keep that invariant out of the spec, but the implementer must hold it.
> - A dedicated code tells optimizer authors and readers that a pure slot is a guarantee they can build on: no I/O, so calls can be reordered, memoized, or hoisted. Under a generic TypeMismatch, that guarantee is just a side effect of type equality.
> - Cost: one more code, but no new machinery. It reuses E0563's site walk.
>
> **Cross-language:** Koka and Eff reject this as an effect-row unification failure, with no dedicated name, and users find those messages hard to read. Rust has no effects, so the closest case is `Fn` vs `FnMut` bound errors (E0525), which get their own code for the same reason: the shape matches and only the capability differs.

- **Web/Scripting:**

> web Phase A proposal: EffectMismatchInFnType = own row, E0574, category Effects, sections §4.15.1, §4.15.4.
>
> ## Proposal W1 (preferred): own row E0574, Effects
>
> Q0: own row, own code. Do not fold it into E0500 or TypeMismatch.
> - E0500 means "your body does an effect you did not declare". The fix is to add `! IO` to your fn. The fix for this error is the opposite: change the callback, or widen the callee's param. If both share a code, users and LLMs apply the E0500 fix ("add `! IO.Log` to main") and the error stays. One code, one fix.
> - TypeMismatch (E03xx) hides the cause. The user sees two types that differ only after `!`. A dedicated code lets the message point at the row, the same reason TemplateMismatch got E0310.
> - E0563 InsufficientHandlerCoverage is the nearest model: a coercion-site rule for effect-carrying values, own code, category Effects. Copy its shape.
>
> Q1: E0574 (next free; keeps the row-slot family E0571-E0574 together, since §4.15.4 slots depend on it). Category "Effects". Section "§4.15.1, §4.15.4".
>
> Behavior:
> - Fires at every coercion site, the same list as E0563 plus the containers from the closure-effects decision: call/method arg, annotated `let`, return value, struct-literal field, assignment to a typed place, list/map element, Option/Result payload. Nested fn types (a `List[fn(Int) -> Int]` slot) check too; soundness needs all of them.
> - Rule: found row not contained in expected row. Pure slot vs effectful value is the common case; `! IO.Log` slot vs `! IO` value is the same error. A `_` in the slot accepts any row (no error).
> - One error per site; span on the value; label names both rows; `note:` names the slot owner; `help:` gives both fixes, with the param written as `fn(Int) -> Int ! _` when the callee is user code.
> - JSON `"code": "E0574"`, `blink explain E0574` and `blink explain EffectMismatchInFnType` both work. `@allow(EffectMismatchInFnType)` is refused: it is a soundness error, like E0500.
>
> ```blink
> fn apply(f: fn(Int) -> Int, x: Int) -> Int {
>     f(x)
> }
>
> fn main() ! IO.Log {
>     let logger = fn(n: Int) -> Int ! IO.Log {
>         log.info("got {n}")
>         n
>     }
>     let r = apply(logger, 42)
> }
> ```
>
> ```
> error[E0574]: effect mismatch in function type (EffectMismatchInFnType)
>  --> app.bl:10:19
>    |
> 10 |     let r = apply(logger, 42)
>    |                   ^^^^^^ expected pure `fn(Int) -> Int`, found `fn(Int) -> Int ! IO.Log`
>    |
>    = note: parameter `f` of `apply` takes a pure callback
>    = help: remove `IO.Log` from the callback, or widen the parameter: `f: fn(Int) -> Int ! _`
> ```
>
> (The spec example says `= fix:`; whatever form the catalog uses for help lines elsewhere should win. Not my vote to fight.)
>
> Tradeoffs (DX):
> - + Searchable, unique name; the explain page can teach "pure is a subtype of effectful" in one place.
> - + LLM-friendly: code maps to one fix.
> - - One more code to learn. Small cost; it reads plainly.
> - - Must keep messages for E0500 vs E0574 clearly apart; the `note:` naming the slot does that.
>
> Cross-language: Swift has a dedicated error, "invalid conversion from throwing function of type '() throws -> Int' to non-throwing function type '() -> Int'". Kotlin reports `suspend () -> Unit` vs `() -> Unit` as plain type mismatch, and users find it confusing; that is the outcome to avoid. TypeScript has no effects, but its best errors (e.g. "Type 'Promise<X>' is not assignable to 'X'... Did you forget to use 'await'?") succeed by naming the one difference.
>
> ## Proposal W2 (fallback, not preferred): E03xx TypeMismatch-family code
>
> Same behavior, code in E03xx, category Type checking. Only argument: it is a type-identity rule. I reject it: users search effect errors under E05xx, and the row-slot rules that cite it all live in Effects.
>
> Vote intent: W1.

- **PLT:**

> PLT Phase A proposal: EffectMismatchInFnType gets its own row, E0574, in the Effects category.
>
> **Proposal P1 (main).** Q0: give it its own row and keep the name. Q1: `EffectMismatchInFnType | E0574 | Effects | §4.15.1, §4.15.4, §4.15.5`.
>
> **What the rule is.** Function subtyping with rows: `fn(A) -> B ! R1 <: fn(A') -> B' ! R2` holds when `A' <: A`, `B <: B'` and `R1 ⊆ R2`. In row containment, a sub-effect is inside its parent (`IO.Log ⊆ IO`), and an expected `_` holds any row. E0574 fires when only the row check fails: `R1 ⊄ R2`. Pure into effectful is one case of `R1 ⊆ R2`, not a special rule. So E0574 covers `fn() ! FS.Read` given where `fn() ! IO.Log` is expected, as well as effectful given where pure is expected.
>
> **Sites.** The same set as E0563, so that the two effect-coercion codes match: a call or method argument, an annotated `let`, a return value, a struct literal field, a list element, an assignment to a typed place, and a row-slot field (§4.15.5). It also fires at a nested position. Rows are covariant in a return type and contravariant in a parameter type. The label names the path to the mismatch: "in the return type of the expected `fn`".
>
> **Lambda literal.** When the value is a `fn` literal whose row was inferred, the primary span is the literal. A `note:` points to the first operation that adds the extra effect. The user must see why the lambda is effectful.
>
> **Precedence.** When the fn types differ only in their rows, E0574 replaces E0300. When the parameter or return types also differ, E0300 fires alone, because that is the deeper error. E0574 is not E0500: E0500 means a caller's declared row is too narrow, and E0574 means a value does not fit a type.
>
> **Output.** JSON `"code": "E0574"`. `blink explain E0574` gives the subtyping rule and both fixes. `@allow` does not apply, because it is an error.
>
> ```
> fn apply(f: fn(Int) -> Int, x: Int) -> Int {
>     f(x)
> }
>
> fn main() ! IO {
>     let r = apply(fn(n: Int) -> Int { io.println("n={n}")
>         n }, 42)
> }
> ```
> ```
> error[EffectMismatchInFnType] E0574: effect mismatch in function type
>  --> app.bl:6:19
>   |
> 6 |     let r = apply(fn(n: Int) -> Int { io.println("n={n}")
>   |                   ^^ expected pure `fn(Int) -> Int`, found `fn(Int) -> Int ! IO.Print`
>   = note: `io.println` at 6:39 adds `IO.Print`
>   = help: give `apply` a row slot (`f: fn(Int) -> Int ! _`), or remove the effect from the callback
> ```
>
> **Tradeoffs (PLT).**
> - Soundness: the 6-0 rule that closures are charged at the call holds only if every coercion site checks rows. A dedicated code makes the site list a testable contract. A corpus row per site proves coverage, and today's probe shows zero coverage.
> - If we fold it into E0300, the row failure is hidden inside a general unification error. The fix is different (add a row slot or `_` to the HOF, versus remove the effect), so a dedicated code earns its place, as E0310 and E0563 do.
> - Risk: variance of generic containers. `[fn() -> Int]` where `[fn() -> Int ! IO]` is expected is sound only if `List` is covariant, which needs immutable lists. A mutable place, such as a `let mut` element or a field, must be invariant in its row, or a write makes it unsound. This panel does not settle variance. I ask for a friction ticket: "is the row of a fn type invariant under a mutable container or place?"
>
> **Cross-language.** Koka reports this as a unification failure on the effect row, with no separate code. Its users see poor messages for exactly this case. Scala 3 capture checking and Effekt give a dedicated message for a capability or effect that escapes into a pure position. Haskell gives `IO a` versus `a`, the classic confusing mismatch. A dedicated code is the better UX and is still principled, because it is one clause of the subtyping judgment.
>
> **Proposal P2 (fallback, not preferred).** Make the name an alias and route the case to E0300 TypeError with a sub-label. I reject it on the grounds above. Also, names in published spec text are frozen in practice, and the spec already shows `error[EffectMismatchInFnType]`.

- **DevOps:**

> devops Phase A: give it its own row, EffectMismatchInFnType, E0574, category Effects, section §4.15.1 (with §4.15.4 also listed).
>
> **Proposal A (recommended): its own row, E0574, Effects, §4.15.1 and §4.15.4**
> - Q0: own row. Users will hit this error often, because callbacks are everywhere. It deserves its own `blink explain`, its own LSP filter, and its own JSON `"code"`. E0563 InsufficientHandlerCoverage is the precedent: a subtype check at a coercion site, in the Effects category, with its own code.
> - Q1: E0574, the next free number. Use the spec name as written; names freeze once published.
> - Sites: the same coercion sites as E0563, plus list elements. That is a call or method argument, an annotated `let`, a return value, a struct literal field (a rowless field, per type-row-slot), an assignment to a typed place, and a list or map literal element. The decision on closure-effects-charged-at-call says these sites are what make the rule sound, so the catalog row must list them all.
> - Variance: one code for both directions. An effectful row in a covariant position (result, field) and a pure parameter in a contravariant position (`fn(fn() -> Int ! IO)` slot given `fn(fn() -> Int)`) both get E0574. The label shows the nested path.
> - Precedence: when the shapes differ (arity, param or result type), only TypeError E0300 fires. E0574 fires only when the shapes match and only the row is wider. This gives one error per site and no cascade.
> - `@allow(EffectMismatchInFnType)` is refused, because only warnings can be suppressed. Pre-1.0, it ships as an error at once.
> - No machine-applicable fix, because a tool cannot know which side to change. The spec example's `= fix:` line has to become `help:`. In our catalog, `fix:` means machine-applicable, and an LSP code action would advertise this one wrongly.
>
> ```
> fn apply(f: fn(Int) -> Int, x: Int) -> Int { f(x) }
>
> fn main() ! IO.Log {
>     let logger = fn(n: Int) -> Int ! IO.Log { log.info("{n}"); n }
>     apply(logger, 42)
> }
> ```
> ```
> error[EffectMismatchInFnType]: effect mismatch in function type
>  --> app.bl:5:11
>   |
> 5 |     apply(logger, 42)
>   |           ^^^^^^ expected pure `fn(Int) -> Int`, found `fn(Int) -> Int ! IO.Log`
>   |
>   = note: parameter `f` of `apply` has a pure fn type; `IO.Log` is not in its row
>   = help: give the parameter the row `! _`, or remove `IO.Log` from the closure
> ```
> JSON: `{"code":"E0574","name":"EffectMismatchInFnType",...,"fixes":[]}`. `blink explain E0574` gives a short page with this example and the variance note.
>
> Tradeoffs:
> - A dedicated code lets tooling filter "effect errors" by category. Folded into E0300, it reads as "types look identical, why the error?" The two types print the same except for the row, and the user is confused.
> - Cost: one more row, and the catalog test needs an emit site. The row cannot land without the checker. The probe shows nothing fires today, so the row and the impl ship together.
>
> **Proposal B (I reject it): fold into TypeError E0300**
> No new code. The `note:` says the row differs. This is cheaper, but you cannot grep, filter or `explain` it apart from other type errors, and it breaks the E0563 precedent. I vote against.
>
> Cross-language: Kotlin reports `suspend () -> Unit` vs `() -> Unit` as a generic "Type mismatch", which is a known source of confusion. Swift gives "invalid conversion from throwing function of type X to non-throwing function type Y", a separate diagnostic, and users find it at once. Follow Swift.
>
> Side finding (not for this vote): the spec says `error[TraitContract]` (§3.6, §4.5) but catalog row E0904 is `TraitContractEffectMismatch`. That is the same kind of drift this ticket fixes, so someone should file it.

- **AI/ML:**

> aiml Phase A: own row, EffectMismatchInFnType = E0574, category Effects, §4.15.1, one code at every coercion site, fix says add `! _`.
>
> PROPOSAL A (recommended)
> Q0: own row. Q1: E0574, "Effects", sections §4.15.1 and §4.15.5 (the rowless-field case).
>
> Behavior:
> - JSON `"code": "E0574"`, name `EffectMismatchInFnType`. `blink explain E0574` shows the §4.15.1 example. It is an error, so `@allow` does not apply. That matches the other E05xx soundness errors.
> - Scope: a fn value whose row is WIDER than the row of the target fn type. Pure-into-effectful is the main case, but one code also covers `! IO.Log` into `! FS.Read`. Pure into effectful and narrow into wide stay legal.
> - Sites: a call or method arg, an annotated `let`, a return value, a struct-literal field (a rowless field is pure), a list or map element of an annotated container, and an assignment to a typed place. This is the same site list as E0563, so one checker walk serves both.
> - Label: "expected `fn(Int) -> Int`, found `fn(Int) -> Int ! IO.Log`". Add one label per added effect, as E0904 does.
> - help/fix, ranked: (1) when the target is a param of a user fn, give the machine-applicable fix "add `! _` to the parameter type" (the closure decision named this as the 90% wall). (2) When the slot is a field: "add a row slot `[! _]` to the type and `! _` to the field". (3) Else: remove the effects from the callback.
> - Nested fn types such as `fn(fn() -> Int) -> Int`: report one error at the outer value, plus a `note:` that names the inner position.
>
> ```blink
> fn apply(f: fn(Int) -> Int, x: Int) -> Int {
>     f(x)
> }
>
> fn main() ! IO.Log {
>     let logger = fn(n: Int) -> Int ! IO.Log {
>         io.log("got {n}")
>         n
>     }
>     apply(logger, 42)
> }
> ```
> ```
> error[EffectMismatchInFnType]: effect mismatch in function type
>  --> app.bl:9:11
>   |
> 9 |     apply(logger, 42)
>   |           ^^^^^^ expected pure `fn(Int) -> Int`, found `fn(Int) -> Int ! IO.Log`
>   = note: `apply` requires a pure callback
>   = fix: change the parameter to `f: fn(Int) -> Int ! _`
> ```
>
> Tradeoffs (my domain):
> - LLM accuracy: a separate code makes the repair clear. A model that sees TypeMismatch edits the arg or param TYPE and often removes the effect call in the closure body. E0574 plus "add `! _`" points to the one correct change, and the spec example already prints this name. Without a code, the spec teaches a name that the tool never prints, and a model trained on it will invent codes.
> - One code for pure and for wider rows means one thing to learn, not two.
> - Debuggability: the same site list as E0563 is easy to learn ("handlers and closures narrow at the same places").
> - Cost: one more catalog row. That is low; the E05xx range has room.
>
> PROPOSAL B (rejected): fold it into TypeMismatch E03xx with a note. It needs no new code, but it hides the effect cause in a general bucket, `explain` cannot give the `! _` fix, and it breaks the published name in §4.15.1 (names are frozen). It also splits effect errors between two ranges.
>
> Cross-language: Swift has a dedicated diagnostic for "invalid conversion from throwing function to non-throwing function type", and Kotlin has one for suspend vs non-suspend. Both are separate from the general type mismatch, and models fix those errors well. Koka reports this as a general type error, and the messages are hard to act on.
>
> Open item for the panel: a `let` with no annotation infers the closure's full row, so it never fires there. State that, or models will expect the error at that site.

- **Minimalism:**

> min (Minimalism) Phase A proposal: give EffectMismatchInFnType its own row, E0574, category Effects, §4.15.1 (plus §4.15.4 and §4.15.5).
>
> Q0, the subtraction case first. I looked for an existing code to reuse, and none fits.
> - E0500 UndeclaredEffect is about the caller's row, and its fix is "add the effect to your `!`". Here the caller's row is not the problem. The slot's type is too narrow. If we reuse E0500, users get the wrong fix.
> - A generic TypeMismatch/E0300 hides the one fact the user needs: the shapes match and only the row differs. The help ("give the slot `! _`" or "remove the effect") then has no home.
> - The name is already in two spec sections and two 6-0 decisions. Names are frozen once published, so folding it into another code means re-editing settled text. Today the cheapest step is one catalog row.
> So my answer to Q0 is its own row. It adds no new concept, only a number for a rule that already exists.
>
> Q1: E0574, Effects. E0563 InsufficientHandlerCoverage is the twin: the same "value's effect set is wider than the slot allows" check, also in Effects. Copy its site list word for word, so we have one mental model and one checker path: call or method argument, annotated `let`, return value, struct-literal field, assignment to a typed place, plus list/collection element. The closure-effects panel said soundness needs every coercion site, and E0563's list already names them. A nested fn type (`List[fn(Int) -> Int]`, a fn that returns a fn) gets the same code at the outer value, and the label names the full types.
>
> Behavior:
> - `blink explain E0574` and `blink explain EffectMismatchInFnType` print the same entry.
> - JSON `"code": "E0574"`, `"name": "EffectMismatchInFnType"`.
> - It is an error, so `@allow` does not apply (pre-1.0: ships as an error).
> - The fix is help text, not machine-applicable. Which side to change (widen the slot or purify the closure) is a design choice, and a tool must not make it.
>
> ```
> fn apply(f: fn(Int) -> Int, x: Int) -> Int {
>     f(x)
> }
>
> fn main() ! IO.Log {
>     let logger = fn(n: Int) -> Int ! IO.Log { io.log("{n}"); n }
>     io.log("{apply(logger, 42)}")
> }
> ```
> ```
> error[EffectMismatchInFnType]: effect mismatch in function type
>  --> app.bl:7:20
>   |
> 7 |     io.log("{apply(logger, 42)}")
>   |                    ^^^^^^ expected pure `fn(Int) -> Int`, found `fn(Int) -> Int ! IO.Log`
>   |
>   = note: `apply` requires a pure callback
>   = help: give the parameter the row `! _` (`f: fn(Int) -> Int ! _`), or remove the effects from the callback
> ```
> The same code fires for `struct Hook { cb: fn() -> Int }` built with an effectful closure, and for `let g: fn(Int) -> Int = logger`.
>
> Not this error: pure into effectful (legal), and a handler-type gap (E0563).
>
> Tradeoffs: one row and one number, and no new syntax or flags. The risk is drift between E0563 and E0574 site lists. To avoid it, the catalog text says "the sites of E0563", so a writer cannot let them diverge. I reject a per-site split (E0574 param, E0575 field...): that is the C++ path of codes multiplying for one rule.
>
> Cross-language: Koka and Effekt report this as a plain type mismatch with the row diff in the message. Kotlin gives `suspend` vs non-suspend fn types its own diagnostic. That supports a dedicated name, because users read effect-row errors differently from shape errors.

#### Phase B — Round 1 (variations V1-V5)

The digest listed five variations: V1 whether the `! _` repair is machine-applicable; V2 a fn whose parameter is a pure fn type, given where the slot's parameter is effectful; V3 a `note:` on an inline fn literal naming the operation that adds the effect; V4 Option/Result payloads as sites; V5 the row of a fn type inside a mutable container or place. Systems retracted its Phase A position on V2 ("In a param position the rule reverses ... is fine"). AI/ML withdrew its machine-applicable fix on V1.

- **Systems:**

> sys Phase B1: I take back my V2 position. devops and plt are right, and E0574 fires in that case.
>
> **V2 (retraction).** I had the direction backwards. The slot `fn(fn() -> Int ! IO) -> Int` promises its callers that they can pass an effectful callback. A value of type `fn(fn() -> Int) -> Int` was checked on the assumption that `cb` is pure, so its own row has no `IO`. Through the slot, that callback runs with `IO` that no row accounts for, which is unsound. Parameter types are contravariant, so a pure fn-type parameter cannot fill an effectful one:
> ```blink
> fn run_pure(cb: fn() -> Int) -> Int {
>     cb()
> }
> let s: fn(fn() -> Int ! IO) -> Int = run_pure   // E0574
> ```
> The reverse is fine: an `fn(fn() -> Int ! IO) -> Int` value fits an `fn(fn() -> Int) -> Int` slot. The label should point at the inner fn type that fails.
>
> **V1: no machine-applicable fix.** Adding `! _` to a parameter changes the callee's signature for every caller, and it moves the row charge onto every call site. That is an API decision, not a mechanical edit. Use `help:` lines that name both repairs, with the concrete `fn(Int) -> Int ! _` text, and JSON `"fixes":[]`.
>
> **V3: support.** When the value is an inline fn literal with an inferred row, a `note:` names the first operation that adds the effect. The typechecker already has this when it computes the row, so it costs nothing at run time, and it saves the user a search.
>
> **V4: support, but as one rule, not a list.** The check walks every fn type inside the target type, so it covers `Option[fn()]`, `Result[fn(), E]`, tuple, list and map payloads, and fields. If we list sites by type constructor, the list will drift.
>
> **V5: support plt's friction ticket, and keep it out of this vote.** A mutable place must be invariant in its row, which is the same reason Rust makes `&mut T` invariant. Whatever variance rule we settle on, E0574 is the code for a failure that is only about the row. This panel does not need to decide it.
>
> stable, ready to vote.

- **Web/Scripting:**

> web Phase B1: V1 help text only; V2 E0574 fires (sys has the direction wrong); V3 yes; V4 covered by nested positions; V5 friction ticket. Stable, ready to vote.
>
> V1: Not machine-applicable. Help text with both fixes. I join sys/min/devops. An IDE quick-fix list can offer both as choices, but `"fixes":[]` in JSON is right: an auto-fix that widens a library's param is a bad surprise.
>
> V2: Check the direction. Slot `fn(fn() -> Int ! IO) -> Int` means the caller WILL hand an effectful callback to the value. Value `fn(cb: fn() -> Int) -> Int` promised its body only pure callbacks. That is unsound, so E0574 fires. PLT's rule says the same: `A' <: A` needs `fn() -> Int ! IO <: fn() -> Int`, which is false. devops is right; sys's statement is backwards. The reverse (value takes `fn() -> Int ! IO`, slot param is pure) is fine.
>
> ```blink
> fn run(h: fn(fn() -> Int ! IO) -> Int) -> Int ! IO { ... }
> fn pure_h(cb: fn() -> Int) -> Int { cb() }
> run(pure_h)   // E0574: `pure_h` takes a pure callback; `run` gives it one with `IO`
> ```
>
> The label should name the inner position, since "found X expected Y" on two nested fn types is hard to read. Same as TypeScript under strictFunctionTypes: it says "Types of parameters 'cb' and 'cb' are incompatible" and then drills in.
>
> V3: Yes. Highest DX value on the ballot. The user wrote no `!` anywhere; the row came from inference. Pointing at `io.println` at 6:39 answers "where did IO come from?" at once. Keep it a `note:`, first operation only.
>
> V4: I fold my Option/Result item into "nested fn-type positions": any fn type inside a type argument (`Option[fn() -> Int]`, `Result[fn() -> Int, E]`, `Map[Str, fn() -> Int]`) checks. No separate site list needed. Writer wording.
>
> V5: Agree with PLT: friction ticket, not this panel. Note for that ticket: mutable list invariance surprises JS/Python users less than it surprises Java users. Keep the error message plain if it comes.
>
> Stable, ready to vote.

- **PLT:**

> PLT Phase B1: my positions on V1-V5. V2 is a soundness issue: sys's reading is wrong, devops's is right.
>
> **V1: no machine-applicable fix.** I agree with sys, min and devops. Widening the slot changes the HOF's contract for every caller, and a tool must not choose that. Both fixes go in `help:`, and JSON gives `"fixes":[]`.
>
> **V2: devops is right, sys is wrong. This is a soundness issue, not taste.** The parameter rule is `A' <: A`: the slot's parameter type must fit the value's parameter type, not the reverse.
> ```
> fn run(h: fn(fn() -> Int ! IO) -> Int ! IO) ! IO { ... }
> fn pure_h(g: fn() -> Int) -> Int { g() }   // body checked with g pure
> run(pure_h)   // E0574: run passes an effectful g, and pure_h would perform IO under a pure row
> ```
> The 6-0 decision charges `g()` to `pure_h`'s row, and that row is pure. Accepting this hides an effect. The safe direction is the reverse: a value whose parameter is `fn() -> Int ! IO`, given where the slot's parameter is pure, is accepted. Label: "in parameter 1 of the expected `fn`: expected `fn() -> Int ! IO`, found pure `fn() -> Int`".
>
> **V3: keep the note.** An inferred lambda row is invisible in the source. Without the note pointing to the operation that adds the effect, the user cannot see why the lambda is effectful. It costs nothing when the value is a named fn, because then there is no note.
>
> **V4: Option/Result payloads are covered.** They fit under "nested positions": a fn type inside any type argument is checked. Name the rule, not a list of types, or the list will drift.
>
> **V5: keep the friction ticket, but adopt a sound default now.** Until variance is decided, the row of a fn type inside a type argument of a container value is checked for equality (`_` still takes any row). Element positions of a literal still coerce one element at a time:
> ```
> let fs: [fn() -> Int ! IO] = [pure_f, eff_f]   // ok: each element is coerced
> let ps: [fn() -> Int] = [pure_f]
> let es: [fn() -> Int ! IO] = ps                 // E0574 for now (invariant), label names the type argument
> ```
> Relaxing this later is not a breaking change. Tightening it would be one.
>
> stable, ready to vote (Option 1 + V1 none, V2 contravariant as above, V3 note, V4 rule-based, V5 invariant default + friction).

- **DevOps:**

> devops Phase B1 on V1–V5. I am stable and ready to vote.
>
> V1 (no machine-applicable fix). I hold my position. Adding `! _` to a param changes the callee's signature: the fn gets a row source, so its row becomes polymorphic for every caller. On a `pub` fn that breaks the API, and no tool should make that change on its own. Give both repairs as `help:` lines that are suggestions only. The LSP may still list them as code actions, as long as they are not marked preferred or auto-fix. JSON: `"fixes":[]`, with both helps carried as suggestions. For a field, the help names the `[! _]` slot repair, as aiml asked.
>
> V2 (contravariant position). This is an error, and sys has the direction backwards. A slot of type `fn(fn() -> Int ! IO) -> Int` will be called with effectful callbacks. A value of type `fn(fn() -> Int) -> Int` calls its callback as pure, and because a closure is charged where it is called, its body is charged nothing. IO then runs with no row that names it. plt's rule `A' <: A` gives the same answer.
> ```
> fn run(cb: fn() -> Int) -> Int { cb() }
> let h: fn(fn() -> Int ! IO) -> Int = run   // E0574
> ```
> ```
> error[EffectMismatchInFnType]: effect mismatch in function type
>   |   ^^^ parameter 1: expected `fn() -> Int ! IO`, found pure `fn() -> Int`
>   = note: `run` calls its callback as pure; the slot passes callbacks that perform `IO`
> ```
> The other direction (`run2(cb: fn() -> Int ! IO)` into a slot that takes a pure callback) is fine.
>
> V3 (a `note:` that names the operation that adds the effect). I support it. This note is what lets a user act on the error. For a named binding, the note points at the binding's declaration, where the row comes from. It costs nothing at the other sites.
>
> V4 (Option/Result payloads). Do not list them one by one. Define the trigger as "any comparison of a value's type with an expected type, at any depth". `Some(logger)` into `Option[fn() -> Int]` is a nested position inside a type argument, so V5 settles it.
>
> V5 (variance). I agree: file a friction ticket for spec variance. Until it is settled, the compiler should treat a row inside a type argument as invariant. Then `[fn() -> Int]` into `[fn() -> Int ! IO]` is E0574 too, with the label "rows inside a type argument must match". This rejects more programs, but it is sound, and relaxing the rule later breaks no one. If we start loose instead, tightening later breaks users.

- **AI/ML:**

> aiml Phase B1, V1-V5:
>
> V1: I concede. The fix is not machine-applicable (`"fixes":[]`), but the `help:` names the exact edit. For a param of a user fn, the help prints the whole new param, `f: fn(Int) -> Int ! _`, so a model can copy it. A second help says "or remove the effect from the callback". Models act on help text well. The gain I wanted is in the text; the auto-apply flag adds nothing.
>
> V2: sys has the direction wrong. devops and plt are right: this case is E0574.
> ```blink
> fn run(g: fn(fn() -> Int ! IO) -> Int) -> Int ! IO { ... }
> fn pure_user(cb: fn() -> Int) -> Int { cb() }
> run(pure_user)   // E0574
> ```
> `run` gives `g` an effectful callback, and `pure_user` calls that callback while it charges nothing. That is an unsound hole. The reverse is fine: a value with an effectful param in a slot that has a pure param. The label must name the inner position: "parameter 1 of `g`: expected `fn(fn() -> Int ! IO) -> Int`, found `fn(fn() -> Int) -> Int`". Plus a note: "`pure_user` calls its callback as pure". Without that note, an LLM will widen the wrong side.
>
> V3: I support plt's note. It is the most useful line for a model: it names the operation to remove or the row to add. Keep it to the first operation only, so the output stays short.
>
> V4: yes, Option/Result payloads, and any immutable type-argument position. Ground it as "the value's type contains a fn type at a position where the slot's fn type has a narrower row", not as a list of sites that can drift. min's "sites of E0563" covers the outer sites; nesting covers the rest.
>
> V5: I support plt. Ask for a friction ticket, and do not settle variance here. Until it is settled, a mutable place (a `mut` list, field assignment) must be invariant in its row. Any mismatch there, either way, is E0574. That is the sound default, and it gives one message to learn.
>
> Stable, ready to vote.

- **Minimalism:**

> min Phase B1.
>
> V1: no machine-applicable fix, in every case. aiml's param fix changes the callee's public signature, and every other caller of `apply` sees it. A tool must never make an API change without being asked. Keep both repairs as `help:` text. JSON `"fixes": []`. The §4.15.1 example's `= fix:` line becomes `= help:` (writer).
>
> V2: I side with plt and devops, and sys has the direction backwards. Use the single subtyping rule: params contravariant, return and row covariant. The value `fn(fn() -> Int) -> Int` takes only pure callbacks, but the slot promises its callers they may pass `fn() -> Int ! IO`. So this case is unsound and gets E0574:
> ```
> fn run(g: fn(fn() -> Int ! IO) -> Int) -> Int ! IO { g(fn() -> Int ! IO { io.println("x"); 1 }) }
> fn pure_only(cb: fn() -> Int) -> Int { cb() }
> run(pure_only)   // E0574: expected `fn(fn() -> Int ! IO) -> Int`, found `fn(fn() -> Int) -> Int`
> ```
> Minimalism argument: one rule, applied the same way at any depth, with no special case per position. The catalog row states the rule once, and that rule is plt's.
>
> V3: accept as a `note:`, not a new code. E0500 already names where an effect comes from, so it costs no new idea. If the checker does not record the source op, leave the note out rather than invent new machinery for it.
>
> V4: do not list Option/Result separately. "Any position inside the slot type, under the V2 rule" covers payloads, map values, tuple fields and nested fns. A list of sites gets out of date. A rule does not.
>
> V5: agree with plt. A friction ticket, out of scope here. The catalog row must not promise covariance for mutable places until that ticket settles it.
>
> Stable, ready to vote.

#### Phase C — Final vote

Ballot (options as given):

- **Q1 Catalog identity.** A: own row `EffectMismatchInFnType | E0574 | Effects`, error, not `@allow`-able; fires only when the fn shapes match and only the row check fails; E0300 alone otherwise. B: route to E0300 with a row note.
- **Q2 Machine-applicable fix.** A: none; JSON `"fixes":[]`; both repairs are `help:` suggestions, the first printing the widened param in full (or the `[! _]` slot repair for a field). B: machine-applicable "add `! _` to the parameter type" for a param of a user fn.
- **Q3** `let s: fn(fn() -> Int ! IO) -> Int = run_pure` where `run_pure(cb: fn() -> Int)`. A: E0574 (parameters contravariant; the label names the inner position). B: accepted.
- **Q4 Inline fn literal with an inferred row.** A: a `note:` names the first operation that adds the extra effect. B: no note.
- **Q5 A fn-type row inside a type argument** (`let es: [fn() -> Int ! IO] = ps`). A: rows must match for now (E0574); literal elements coerce one by one. B: state no rule; leave it to a later ticket.

Result: **A on all five, 6-0 each.**

- **Systems:** A, A, A, A, A

> sys Phase C votes: A, A, A, A, A.
>
> **Q1: A.** Reasoning: the shapes match and only the row is wider, so that is the fact the code must report. E0563 already gives a width-only coercion failure its own Effects code. A dedicated code also tells readers and optimizer authors that a pure slot is a guarantee (no I/O, safe to reorder or cache calls), not just a side effect of type equality. Concern: the shape-match test and the E0300 path may disagree on edge cases, so one site emits both codes, or neither.
>
> **Q2: A.** Reasoning: adding `! _` to a parameter changes the signature for every caller and moves the row charge onto every call site. That is an API decision, and a tool must not apply it silently. The `help:` text with the full widened type is enough for a human or an agent to apply by hand. Concern: agents that only act on machine-applicable fixes will stall here, so the help must print the exact paste-ready type.
>
> **Q3: A.** Reasoning: `run_pure` was checked as if `cb` were pure, so its row has no `IO`. Through the slot, it would run an effectful callback that no row accounts for, which is a soundness hole. Parameter contravariance is the standard rule, and the label that names the inner position keeps the error readable. Concern: users will find this direction surprising, so the label and `blink explain` must show the reason, not only the types.
>
> **Q4: A.** Reasoning: the typechecker already knows which operation added the effect when it infers the row, so the note costs nothing at run time and saves a manual search through the closure body. Concern: when the effect comes from a nested call several levels down, "first operation" must point at the call in the literal, not deep inside a callee.
>
> **Q5: A.** Reasoning: invariance is the sound, conservative default (Rust `&mut T`, Go generics), and relaxing it later breaks no programs, while tightening it later would. "Behavior unspecified" in a language that is training data invites both compiler drift and wrong user code. Coercing literal elements one by one keeps the common case easy. Concern: users of immutable list pipelines will hit spurious E0574 errors until the friction ticket settles covariance, so the note should name the friction rule ("rows inside a type argument must match").

- **Web/Scripting:** A, A, A, A, A

> web Phase C votes: Q1 A, Q2 A, Q3 A, Q4 A, Q5 A.
>
> Q1: A. A dedicated code gives one meaning and one fix. Users and LLMs search for it, and `blink explain E0574` can teach "pure is a subtype of effectful" in one place. If this went to E0300, the cause would sit in a note under a generic type error. Kotlin's `suspend` mismatch shows how confusing that is.
> Concern: users may confuse E0574 with E0500 unless the label and the `note:` clearly name the slot, not the caller's own row.
>
> Q2: A. The compiler cannot know which side the user wants to change. An auto-fix that widens a library's parameter on save is a bad surprise. Two clear `help:` lines, with the widened param written out in full, are enough for an IDE to offer both as choices.
> Concern: someone new to the language may not know what `! _` means. The help or explain page should say "accepts a callback with any effects".
>
> Q3: A. It is the only sound answer: `run_pure` would get an IO callback it promised never to receive. TypeScript users know the same rule from strictFunctionTypes. A label that names the inner parameter keeps it readable.
> Concern: nested fn-type mismatches are rare and hard to read; if the label falls back to two long whole types, users will give up on it.
>
> Q4: A. This is the biggest DX gain on the ballot. The user wrote no `!` at all, so "where did IO come from?" is the first question. Pointing at `io.println` at 6:39 answers it right away.
> Concern: if inference follows a long chain (closure calls closure), "first operation" may point somewhere unexpected; keep it to a direct operation in the literal's body.
>
> Q5: A. Invariant now and relaxed later is a non-breaking change; "unspecified" means users see behavior shift under them, and spec text an LLM cannot learn from. Literal elements still coerce, so `[pure_f, eff_f]` works, which is the 90% case.
> Concern: the `let es = ps` error will surprise JS/Python users. The message must say "rows inside a type argument must match" and show the `_` escape, not just two types.

- **PLT:** A, A, A, A, A

> PLT Phase C votes: A, A, A, A, A.
>
> **Q1: A.**
> Reasoning: The row check is one clause of the fn subtyping judgment, and its fix is different from a plain type mismatch. So it earns a dedicated code, as E0563 and E0310 do. A named code also turns "every coercion site checks rows" into a contract that tests can check. The 6-0 rule that closures are charged at the call depends on that contract for soundness.
> Concern: Implementers may wire E0574 at the argument site only and leave let, return, field and element unchecked. The soundness hole would then stay open under a green catalog row. Each site needs its own corpus row.
>
> **Q2: A.**
> Reasoning: Widening the slot changes the HOF's contract for every caller, and removing the effect changes the callback. The two repairs do different things, and no tool can choose between them. A machine fix that widens types quietly also weakens what a signature guarantees.
> Concern: Agents may apply the first `help:` line by reflex, so `! _` spreads through APIs. The help should print the widened param in full, but not first by default when the callee is in another package.
>
> **Q3: A.**
> Reasoning: Parameters are contravariant: `fn(A) -> B <: fn(A') -> B` requires `A' <: A`. `run_pure` was checked with a pure `cb`, so it would run IO under a pure row when the slot gives it an effectful `cb`. Option B is unsound. It hides an effect, which is exactly what the 6-0 closure decision forbids.
> Concern: Users find contravariant errors confusing. The label must name the inner position, or the message will read as backwards.
>
> **Q4: A.**
> Reasoning: An inferred row is not visible in the source. Naming the operation that produces it is the minimum a user needs to explain the judgment. It costs nothing for a named fn value.
> Concern: When the extra effect comes through a nested call chain, the note must name the call in the lambda, not some deep operation in another module.
>
> **Q5: A.**
> Reasoning: Without a variance rule, the only sound default is invariance. Covariance of a mutable container lets a pure-typed alias read an effectful fn written through the wider alias. Option B leaves behavior unspecified, so the compiler would pick a rule by accident. Relaxing invariance later breaks no one; tightening covariance later breaks users.
> Concern: Invariance will reject some safe programs, such as reading through an immutable list. The friction ticket must be worked, not parked, or users will learn to write `! _` to escape the rule.

- **DevOps:** A, A, A, A, A

> devops Phase C votes: A, A, A, A, A.
>
> Q1: A
> Reasoning: A distinct code gives the error its own `blink explain` page, LSP filter and JSON code. E0563 is the precedent for a subtype check at a coercion site. Under E0300, two types that print the same except for the row would confuse users and tools.
> Concern: E0574 needs an emit site in every coercion path. If the checker misses one path (for example, assignment to a field), the soundness gap stays hidden behind a catalog row that looks complete.
>
> Q2: A
> Reasoning: Adding `! _` changes the callee's signature and makes its row polymorphic for every caller. On a `pub` fn that breaks the API, and a tool must not make that change without a human. An LSP may still list the two helps as code actions that are not preferred.
> Concern: Agents and users lose a quick fix in the common local case, and they will ask for one again.
>
> Q3: A
> Reasoning: The slot's callers pass effectful callbacks. `run_pure` calls its callback as pure, and because a closure is charged where it is called, its body is charged nothing, so `IO` runs with no row that names it. Accepting this breaks soundness, and a label that names the inner position tells the user where to look.
> Concern: Errors in a contravariant position are hard to read. If the label does not name the inner position clearly, users will read the error as being the wrong way round.
>
> Q4: A
> Reasoning: A row inferred on a literal has nothing written that the user can point to. The note that names the operation is what lets the user act on the error, and it costs nothing at the other sites.
> Concern: In a long literal, "first operation" may not be the one the user wants to remove. The note must say that it names one of possibly several.
>
> Q5: A
> Reasoning: Option B leaves the behavior unspecified, which means whatever the compiler does today: it accepts the program, and that is unsound. Invariant is sound, and loosening it later breaks no user. Tightening later would break users.
> Concern: Users will hit false positives on immutable lists until the friction ticket settles variance, so that ticket must not go stale.

- **AI/ML:** A, A, A, A, A

> aiml Phase C votes: Q1 A, Q2 A, Q3 A, Q4 A, Q5 A
>
> Q1: A
> Reasoning: The spec already prints `error[EffectMismatchInFnType]`, and names are frozen. A dedicated code tells a model the cause is the effect row, not the param types, so it edits the row and does not rewrite types or delete the effect call. `blink explain E0574` can teach the subtyping direction in one place.
> Concern: A user may read "fires only when shapes match" as "the effect check is skipped" when a case also has E0300; after the E0300 fix, E0574 appears as a second round.
>
> Q2: A
> Reasoning: Two repairs are valid, and a tool must not pick between them. A help that prints the full widened param gives a model a line to copy, which is all the auto-apply flag would add. `"fixes":[]` is honest JSON.
> Concern: Agents that only apply `fixes` and skip `help:` text will stall on this error; tool docs must say to read the help.
>
> Q3: A
> Reasoning: B is unsound. The slot hands an effectful callback to `run_pure`, which calls it and charges nothing. A label that names the inner position plus a note ("`run_pure` calls its callback as pure") keeps the error clear for people and models.
> Concern: Contravariance is the hardest rule here to learn. Without a worked example in §4.15.1 and in `explain`, models will "fix" it by adding `! IO` to the wrong fn.
>
> Q4: A
> Reasoning: The note on the operation that adds the effect is the most useful line for a model: it names what to remove, or which effect the slot must allow. One line, first operation only, low token cost.
> Concern: When the first operation sits in a nested call or a derived op, the note can point to a line far from the literal, and that can confuse.
>
> Q5: A
> Reasoning: Behavior that the spec leaves unspecified is the worst case for LLM accuracy: models learn whatever one compiler build does, and that becomes training data. Invariant now is sound and can relax later with no breaking change, while A keeps element-by-element coercion for literals.
> Concern: Users will hit `let es: [fn() -> Int ! IO] = ps` and file it as a bug; the friction ticket must exist before release, and the message must say "rows inside a type argument must match".

- **Minimalism:** A, A, A, A, A

> min Phase C votes.
>
> Q1: A
> Reasoning: The spec has already published the name in two sections and two decisions, so B means removing settled text. That is more churn, not less. A costs one row, one number and no new concept. B hides the one fact the user needs (only the row differs) inside a generic mismatch.
> Concern: The site rule of E0574 and E0563 could drift apart unless the catalog states one shared rule.
>
> Q2: A
> Reasoning: B's fix changes the public signature of the callee for every caller. A tool must never make an API change unasked. Two valid repairs means the choice belongs to the user. Help text is enough, and `"fixes": []` is the honest output.
> Concern: Users of AI tools may want a one-step fix, and they will apply the `! _` help by hand without thinking about other callers.
>
> Q3: A
> Reasoning: The slot promises its callers that they may pass an effectful callback, and `run_pure` cannot take one, so B is unsound. One subtyping rule at every depth is smaller than a rule plus a special case for parameter positions.
> Concern: Users rarely meet contravariance, so the label must name the inner position plainly or the error will look backwards.
>
> Q4: A
> Reasoning: The note costs no new concept: E0500 already names where an effect comes from, and an inferred row with no source is the hardest case to debug. It is a note, not a code.
> Concern: If the checker does not record the source op, implementers may build new machinery just for this note. Leave the note out in that case, not the error.
>
> Q5: A
> Reasoning: Strict now and relaxed later is a change that breaks nothing. B leaves a hole in a soundness rule, and the closure-effects panel said one missed site lets an effectful closure travel as a pure one. Invariant is the smallest rule that is sound for mutable lists, and literal coercion keeps the common case working.
> Concern: Code that should be legal under a later covariance rule (immutable views) will get errors until the friction ticket lands.

### Final Spec

```blink
fn run_pure(cb: fn() -> Int) -> Int {
    cb()
}

fn main() ! IO.Log {
    let ps: List[fn() -> Int] = [fn() -> Int { 1 }]
    let s: fn(fn() -> Int ! IO.Log) -> Int = run_pure    // ERROR E0574: parameter 1
    let es: List[fn() -> Int ! IO.Log] = ps              // ERROR E0574: rows inside a type argument must match
}
```

- `EffectMismatchInFnType` is E0574, category Effects, §4.15.1. An error: `@allow` does not apply.
- `fn(A) -> B ! R1` fits `fn(A2) -> B2 ! R2` when `A2` fits `A`, `B` fits `B2`, and each effect of `R1` is in `R2`; a sub-effect is in its parent, and `_` in `R2` takes any row. The rule holds at each depth, reversed in a parameter position.
- E0574 fires only when the parameter and return types match and a row does not fit; otherwise E0300 alone. Never both.
- Sites: those of E0563, plus each element of a list or map literal with a declared element type. A `let` with no type never fires it.
- In a type argument (List, Map, Option, Result, tuple) a fn type's row must match exactly, until a later decision relaxes it. Each literal element fits on its own. A row slot `T[! R]` follows §4.15.5.
- No machine-applicable fix. `help:` lines suggest widening the parameter (written in full) or, for a field, a `[! _]` slot; or removing the effect.
- A fn literal with an inferred row gets a `note:` naming the first operation in its body that adds the effect; a named binding gets a `note:` at the row it declares.
