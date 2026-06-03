[< All Decisions](../DECISIONS.md)

# `?` in `prop_check` Property Closures — Design Rationale

Follow-up to [`?` Operator in Test Bodies](test-block-question-mark.md) (br `ka3pw4`). Originating ticket: br `6ttghp` — "Spec: prop_check generic-E error type." During the `ka3pw4` deliberation, DevOps proposed that `prop_check` should accept a closure whose body uses `?`; the panel deferred it (Q6: HOF closures do not inherit the test-body elaboration) until the test-body `Result` elaboration shipped. This decision resolves that follow-up.

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in independent-proposal → debate → vote rounds. The gap: today the `prop_check` property closure returns `()`/Void, so `?` inside it is rejected (E0508). Should it be made to work, and if so via a generic `E`, via the same implicit `TestError` elaboration the test body gets, or not at all?

The option-space converged to three:

- **α** — the property closure given as the direct argument of `prop_check` inherits the §2.20 `Result[Void, TestError]` elaboration on its own account (no annotation).
- **β** — `prop_check` also accepts an explicit `fn(...) -> Result[Void, E]` closure obeying plain §3c.2 Rule 2/4.
- **γ** — do nothing; `?` stays rejected; use `.unwrap()`.

#### Phase A — Independent proposals

- **Systems:** *"`prop_check` accepts a closure returning `()` (today), `Result[Void, E]`, or `Option[Void]`. ... This is γ1 applied at the closure boundary ... So the closure that the user writes as `fn([Int]) -> Result[Void, ParseError]` is monomorphized and lowered to a thunk the runner sees as `fn([Int]) -> Result[Void, TestError]`. The prop runner ABI is unchanged from the assertion-only case ... The firm line I will defend in Phase B: whatever we pick, the prop runner must see ONE return shape. I will hard-no any proposal that makes the runner thunk type depend on the user's `E` ... that's the δ two-shape failure mode reborn ... Render to the sealed `TestError` Str carrier at the `?` site, carry the string, keep the runner monomorphic."* (Proposed β with the render-at-`?`-site constraint; rejected γ: *".unwrap() inside a property body lowers to a panic, which the runner reports as `status: \"panicked\"` ... So a fallible property that hits an error gets classified as a panic, not a property failure."*)

- **Web/Scripting:** *"I back OPTION α ... The mental model a Python/JS dev brings is: 'my property body just does stuff; if something goes wrong, the framework reports it.' Hypothesis lets you `raise` anywhere. fast-check lets your predicate throw. ... `?` = their raise. Same shape, same shrinking payoff."* On β: *"it costs the scripting dev three things they'll resent: 1. An explicit return-type annotation ... 2. A trailing `Ok(())` ... 3. They must pick the concrete `E`. If the body calls two fallible functions with different error types, `?` won't compose."* On γ: *".unwrap() turns a falsified-property into a panic, which means `status: \"panicked\"`, NOT `status: \"failed\"`. That's a category error for the user."*

- **PLT:** *"The principled claim: ka3pw4's elaboration was justified not because 'it's a test' but because the surface form is closed and the runner is the sole caller. ... Both conditions hold for the prop_check property closure exactly as they hold for the test body. ... Does this reopen Q6? No ... Q6's recorded concern was precise: 'ensure the elaboration of the test BODY does not leak its synthesized E into closures defined inside it.' That is about non-propagation. P1 does not propagate anything. The prop_check closure gets elaboration on its own account, because IT is a closed intrinsic form ... The intrinsic/HOF distinction is exactly what keeps Q6 closed: elaboration attaches to closed compiler-driven surfaces (test body, prop_check argument), never to genuine higher-order values."* (Proposed α as P1; β as sound fallback P2; opposed γ on consistency.)

- **DevOps:** *"I am ABANDONING my original ka3pw4 pitch ('TestError via implicit elaboration') ... The diagnostics killed it."* Proposed β (P1) with a dedicated E0508-replacement diagnostic and preserved static `error_type` in NDJSON, and explicitly listed-and-rejected his own α-shaped P3: *"It DIRECTLY contradicts ka3pw4 Q6 (6-0) ... The error_type in NDJSON would always be the rendered-into TestError, LOSING the static source error type ... LSP hover becomes a LIE."* On the Err/shrinking crux: *"an `Err` return must be treated as 'property failed for this input' so the shrinker minimizes it, exactly like an assertion failure."* (DevOps reversed to α in Phase B.)

- **AI/ML:** *"I back OPTION α. ... ka3pw4 gave the test body INVISIBLE elaboration. If a prop_check closure does NOT get the same treatment, an AI now faces an INCONSISTENCY: `?` just works at test-body top level but is REJECTED one level down inside prop_check. ... A1 makes the natural emission correct. This is the single biggest generability win available."* On the Q6 cost: *"`prop_check` is not a general HOF — it is a compiler intrinsic, recognized by name, exactly like `test` itself. ... runner-intrinsic closures (test body, prop_check) elaborate; user-callable HOFs (for_each) don't."*

- **Minimalism:** *"Backed option, in order: γ (do nothing) first, α (TestError elaboration) as fallback. I formally drop ... β; I will vote against β."* On γ: *"Properties assert algebraic laws over pure functions ... The fallible call inside a property is the exception, and `.unwrap()` already handles it today."* On α-if-forced (P2): *"the only acceptable shape is to make the prop_check closure body a second site governed by the identical §2.20 elaboration ... That is the smallest possible delta."* Rejected generic-E P3: *"this is the C++-committee path ... an annotation form that ka3pw4 already rejected 5-1 for test bodies. Adding the annotation here, after rejecting it there, is incoherent."*

#### Phase A.5 — Mechanical dedupe

Three distinct options (α / β / γ) plus flagged sub-questions: **SQ1** runner ABI under β (render-at-`?`-site vs carry generic E); **SQ2** `Option[Void]` support; **SQ3** NDJSON `cause` (reuse closed enum vs new `"property"` value). Three options + flagged variations triggered Phase B.

#### Phase B — Debate highlights

The decisive move was **Systems reversing β→α** on a codegen-equivalence argument:

- **Systems:** *"under my S1 constraint, α and β emit the IDENTICAL machine code. S1 insists render-to-TestError happens AT THE ? SITE so the runner thunk is one monomorphic shape `fn(in) -> Result[Void, TestError]`. α and β differ only in whether the user WRITES the annotation and `Ok(())` tail ... Given equivalent codegen, α is strictly less surface and consistent with the test-body elaboration we shipped. On DevOps's hover objection: FALSE as stated. The static error_type is the static name of the source error type AT THE ? SITE; the compiler knows it under α exactly as under β. α loses nothing in NDJSON."*

- **DevOps (reversing β→α):** *"Systems' SQ1 framing dissolved my whole objection. ... My β stance rested on two diagnostic claims: (1) hover should show a real nameable return type; (2) NDJSON must preserve the STATIC error_type. ... carrying generic E through monomorphization to the runner buys NOTHING, because the runner only ever PRINTS. The `error_type` I cared about ... needs the `?`-site lowering to WRITE the static type name as a `Str` field into the TestError carrier. That's exactly what TestError already is. ... I was wrong that α loses static error_type."*

- **PLT (answering the hover/error_type challenge):** *"the `error_type: Str` field in TestError is written AT THE ?-SITE LOWERING as the static name of `E` at that exact site. This is strictly MORE precise than β ... Consider a property body with two `?` sites ... Under α, whichever site fails stamps ITS OWN static type name. Under β, the closure has ONE declared `E` ... α doesn't lose error_type — it carries better error_type than β can."* On hover: *"The honest type to show on hover is `fn(...) -> Result[Void, TestError]` — the elaborated principal type. ... DevOps cannot call it honest for §2.20 and a lie one closure-level deeper for the same closed intrinsic surface."* PLT also fixed the trigger as **syntactic**: *"elaboration applies when the closure is the direct syntactic argument in the `prop_check(...)` call. NOT 'any closure the runner ends up calling' ... a let-bound closure ... has already been type-checked against its own return type ... Syntactic trigger = the closed-surface precondition holds by construction."*

- **Web:** *"β makes the user write `-> Result[Void, E]` + trailing `Ok(())` and forces them to NAME a single concrete E — which falls apart the moment a property body calls two functions with different error types. α's TestError is the universal sink, so mixed-E bodies just work."*

- **AI/ML:** *"β as a surface still asks the AI to make a choice α doesn't: write the closure return annotation or not. That is the decision point I exist to flag. ... β's two distinguishing benefits are both already provided by α, while β adds a second surface and a per-property annotation cost. β is strictly dominated."*

- **Minimalism (conceding γ on the status crux):** *"Theirs is right, mine was wrong. `.unwrap()` on an Err calls `panic()` ... reported as `status:\"panicked\"`. There is no path by which an unwrap-panic surfaces as `status:\"failed\"` ... γ falls. I withdraw γ as a serious contender."* And: *"when two options compile to the same thing, you pick the one with less language surface, every time. ... α is my position. β is a reject."*

All six signaled "stable, ready to vote."

#### Phase C — Final vote

**Q1: How should a `prop_check` property closure body support `?`?** (6-0 for α; β rejected, γ withdrawn)

- **Systems (α):** *"Under the locked render-at-?-site constraint, α and β emit bit-identical code and an identical monomorphic runner ABI; the closure's `E` never reaches the runner in either. With codegen equal, α is strictly less surface and stays consistent with the test-body elaboration already shipped."* Concern: *"a future refactor that hoists the closure to a `let` silently flips it from elaborated to plain Rule 2/4 — the diagnostic at that boundary must name the cause or it reads as a spec bug."*
- **Web/Scripting (α):** *"α gives a scripting dev coming from Hypothesis/fast-check the exact mental model they already have ... no return annotation, no `Ok(())`, no naming a concrete E."* Concern: *"The 'direct syntactic argument vs let-bound' distinction must be diagnosed clearly (E0508 with a fix-it)."*
- **PLT (α):** *"It is the only option that keeps the runner ABI monomorphic over TestError AND preserves the zero-ceremony surface that ka3pw4 Q1 chose 6-0. ... a let-bound closure is a first-class VALUE ... must obey ordinary call-site typing (Rule 2/4)."* Concern: the syntactic trigger must be stated as a predicate, not a semantic one, or re-elaborating an already-typed value reintroduces the action-at-a-distance Q6 forbids.
- **DevOps (α):** *"My β objections are RESOLVED. ... the `?`-site lowering captures the static name of the source error type ... into `TestError.error_type: Str`. CI can still group by underlying error type."* Recorded conditions C1 (NDJSON `error_type` provenance + monomorphic runner), C2 (Err-failure prints the same `shrunk input:` line, shrinker treats Err identically to an assertion panic), C3 (LSP hover: elaborated `Result[Void, TestError]` on the closure node, per-`?`-site source error type on the `?` token).
- **AI/ML (α):** *"the AI's natural emission (two `?` sites, different errors) is uncompilable under β and just works under α. β doesn't merely add tokens — it can force the AI into a wrapper-enum dead-end on a common pattern."* Concern: spec must explicitly state Option is included so silence isn't misread.
- **Minimalism (α):** *"α was already my fallback. ... α reuses the one shipped §2.20 lowering rather than forking it — no annotation, no `Ok(())` tail, no generic-E, monomorphic runner ABI. β buys nothing α doesn't."*

**Q2: `Option`-operand `?` / `Option[Void]` property bodies?** (consensus: Option operands subsumed by α via the §2.20 None-arm lowering; no separate `Option[Void]`-returning closure form)

The panel split only on *labeling*, not behavior. Systems, AI/ML, and PLT held that `?` on an `Option` operand is covered for free by the inherited §2.20 lowering (None → `TestError{message:"None", error_type:"Option"}`); Web and DevOps registered "defer" but meant only "do not add a distinct `Option[Void]`-returning closure signature"; Minimalism supported "Option operands work inside the body" while opposing a separate return form. PLT recorded the resolution: *"under α, `?` on `Option[T]` inside the property closure ALREADY works ... there is no separate 'closure returns Option[Void]' form to add or defer."* Recorded as: Option operands supported via inheritance; no new surface; spec states it explicitly so it is not misread as rejected.

**Q3: NDJSON `cause` for a prop `?`-failure?** (6-0 for reuse the closed `"assertion" | "propagated_error"` enum)

- **Systems:** *"A `?`-propagated property failure is `cause: \"propagated_error\"` co-occurring with `shrunk_input`/`seed`/`reproduce` ... adding `\"property\"` fragments every downstream CI/dashboard consumer for zero new information — same reasoning as ka3pw4 Q3 (6-0)."* Concern: spec should state explicitly that prop-test fields are orthogonal to `cause`.
- **Web:** *"reusing the closed enum means every CI consumer already parsing §8.10 records needs zero changes."*
- **PLT:** *"The `cause` axis describes WHY the test failed; 'property' describes WHICH HARNESS ran it — that's an orthogonal axis ... Conflating harness-identity into the failure-cause enum is exactly the drift PLT warned about in ka3pw4 Q3."*
- **AI/ML, DevOps, Minimalism:** concur; DevOps explicitly killed his own `"property"` proposal (P2).

### Final Spec

A property closure given as the **direct syntactic argument** of the `prop_check` intrinsic inherits the §2.20 implicit elaboration: when it contains `?`, its body is elaborated to `Result[Void, TestError]`. No annotation, no `Ok(())` tail.

```blink
fn parse_port(s: Str) -> Result[Int, ParseError] { /* ... */ }

test "port strings round-trip" {
    prop_check(fn(p: Int) {
        let s = p.to_str()
        let back = parse_port(s)?           // Err = property failed for this input
        assert_eq(back, p)
    })
}
```

A `let`-bound closure passed to `prop_check` is a value, not a closed surface, and obeys plain §3c.2 Rules 2/3 (`?` requires it to return `Result`/`Option`):

```blink
test "let-bound is not elaborated" {
    let prop = fn(p: Int) {
        let back = parse_port(p.to_str())?  // E0508: not the direct argument of prop_check
        assert_eq(back, p)
    }
    prop_check(prop)
}
```

**Locked design points:**

- Elaboration triggers on a **syntactic predicate**: the closure literally appears as the argument in the `prop_check(...)` call. This keeps `ka3pw4` Q6 intact — `for_each` and any user-callable HOF closure are unaffected.
- Each `?` site renders via `Display[E]` and stamps `TestError.error_type` with the static name of `E` **at that site**; distinct `?` sites in one property may carry distinct `error_type` values (β's single declared `E` could not, since `?` performs no implicit conversion — §3c.2 Rule 4).
- `?` on an `Option` operand is subsumed: the `None` arm yields `TestError { message: "None", error_type: "Option", origin: <span> }`. There is no separate `Option[Void]`-returning closure form.
- Runner ABI stays monomorphic `fn(in) -> Result[Void, TestError]` for both assertion-only and fallible properties; the closure's `E` never reaches the runner (render-at-`?`-site). Generic-E carriers and `dyn Trait`/vtable carriers are rejected (γ2/δ from `ka3pw4`).
- A returned `Err(TestError { ... })` is a **property failure**: the shrinker minimizes the generated input identically to an assertion failure, and the failure block prints the rendered error beneath the same `shrunk input:` line. `Display[E]` is required at each `?` site (E0512 if missing).
- NDJSON reuses the closed `cause` enum (`"assertion" | "propagated_error"`); a prop `?`-failure record additionally carries `seed`/`shrunk_input`/`reproduce`. No new `"property"` `cause` value.
- The elaboration applies in both `blink check` and `blink test`.
- The explicit annotation form (β: `prop_check(fn(...) -> Result[Void, E] { ... })`) is **not required** and confers no benefit α lacks; the do-nothing/`.unwrap()` option (γ) is rejected because it routes a falsified property to `status: "panicked"`, breaking the shrink/reproduce UX.
