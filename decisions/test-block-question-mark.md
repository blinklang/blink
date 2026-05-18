[< All Decisions](../DECISIONS.md)

# `?` Operator in Test Bodies — Design Rationale

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in independent-proposal → debate → vote rounds. Originating ticket: br `ka3pw4`. Blocking bug: `knhwcf` (`blink check` accepted `?` in test bodies; `blink test` rejected with E0508).

The deliberation resolved six questions. Q1, Q2, Q3, Q4, Q6 ended **6-0 unanimous**. Q5 ended **5-1**, AI/ML dissenting on whether to record the annotation form as **rejected** vs **deferred**; the majority took soft-consensus reject with a documented reopen path.

#### Phase A — Independent proposals (representative excerpts)

- **Systems:** *"Implicit elaboration is the zero-cost surface choice. The compiler already knows where `?` sites are; rewriting the body to a fallible form is a local desugar with no new tokens, no new parse paths, and no per-test annotation overhead. Codegen stays predictable: one lowering rule, one shape."*
- **Web/Scripting:** *"Implicit elaboration is the JS/TS/Python ergonomic default; a dev writing `let x = parse()?` in a test body shouldn't have to learn a second signature ritual. Kotlin's `runTest` and pytest's plain `def test_x()` both win by being invisible."*
- **PLT:** *"Test bodies are not a regular call site; the runner is the sole caller, so implicit elaboration is a property of the test grammar form, not an exception in the function type system. This preserves the 'one principal type' discipline for ordinary functions while giving tests a sound desugaring into `() -> Result[Void, E]`. The elaboration is hygienic because the surface form is closed (no user can name the elaborated type)."*
- **DevOps/Tooling:** *"Implicit elaboration is what every modern test runner does (Go's t.Fatal-style flow, Rust's `?` in `#[test]`, Jest's awaited promises). Authoring tests should not require ceremony; the toolchain elaborates."*
- **AI/ML:** *"Implicit elaboration is the token-efficient default. Across a realistic suite (50 tests × 3 fallible calls) annotation costs ~600 extra tokens that carry zero semantic signal for an LLM that already inferred fallibility from `?`. Implicit also matches the dominant pattern LLMs have seen for `?` in Rust-family training data, so few-shot transfer is high."*
- **Minimalism:** *"Implicit elaboration adds zero new surface tokens. The `test \"name\" { body }` shape already exists; threading `?` through it is a lowering rule, not a language feature. Go and Lua both refuse to multiply surface for cases that compose from existing primitives; this is the same call."*

Phase A surfaced a load-bearing disagreement on **Q2 (what is `E`?)** across α (anonymous compiler-synthesized union), β (single inferred E), γ (sealed erased carrier), and a δ hybrid proposed by DevOps. Phase B rounds resolved this to **γ1** (eager `Display[E].display(e)` render to a sealed `TestError { message: Str, ... }`), with γ2 (vtable / `Box[dyn Error]`-like) treated as a hard no by Systems and PLT because it would require `dyn Trait` machinery Blink hasn't specified.

#### Phase B — Debate highlights

- **Systems on γ vs γ2:** *"γ2 is a hard no: requires `dyn Trait` machinery we haven't specified, drags in runtime vtables and pointer indirection on every `?`. γ1 is acceptable — eager `Display` render is bounded, happens only on error path, zero happy-path cost. The runner ABI must always be `(status, message, origin)`; nothing else."*
- **Systems on δ hybrid:** *"(δ) creates two test-failure shapes in the codegen. When all `?` sites agree, the thunk returns `Result[Void, E]`; when they disagree, it returns `Result[Void, TestError]`. The runner ABI now needs to handle both, or the compiler needs to always lower to `TestError` and only use inferred `E` as a typecheck-time fiction. If it's the latter, then (δ) is γ with a sugar layer — call it that, not a new option. (δ) collapses into γ if specified honestly."*
- **Web/Scripting on δ:** *"The one-sentence learnability test fails. Try writing the rule: 'Your test returns `Result[Void, E]` where E is the unified error type if all `?` sites agree, otherwise it's `TestError` which wraps any error.' That's two failure modes a user has to internalize. Spooky-action-at-a-distance on test return types."*
- **PLT on δ:** *"δ is not a new option, it's 'γ but with a special case.' The rule 'infer when possible, fall back to TestError' creates two observable test-failure shapes the user has to learn, determined by non-local properties of the test body. Adding one `?` to a new subsystem silently changes the failure shape of all other `?` sites in that test. This is the worst kind of action-at-a-distance."*
- **AI/ML on δ:** *"δ saves zero tokens vs γ1 in source. Its only claimed benefit is 'preserves hover specificity.' That benefit is exactly the failure mode for AI: hover specificity that *changes shape with refactors* trains the AI to expect a thing that isn't stable."*
- **Minimalism on δ:** *"δ is not a separable choice from γ. It is γ + an inference layer that sometimes hides the lifting. The user-visible behavior changes based on a property they can't see at the test site — 'did all my `?` sites happen to agree on `E`?'. Add one new fallible call and the inferred type silently flips from `Result[Void, pg.Error]` to `Result[Void, TestError]`. That is action-at-a-distance in the type system."*
- **DevOps withdrawing δ:** *"Re-reading my own pitch, the hybrid creates exactly the two-failure-shapes problem the panel is trying to avoid. min and web were right. δ is dead."*
- **PLT on `TestError` carrier:** *"γ1 is a principled injection `E → Str` via the `Display` type class; sound and composes with the rest of the type system without `dyn Trait`. At the test-runner boundary, the only thing the runner does with `e` is print it — so render to `Str` at the `?` site and carry the string."*
- **Systems on `TestError` shape:** *"`TestError` carries `{ message: Str, error_type: Str, origin: SourceLocation }`. The runner already emits source locations for assertion failures and panics; `?`-propagated errors should match. Free, since the compiler knows the `?` site."*

Phase B also surfaced unanimous agreement that **`TestError` must be sealed/opaque** — users cannot `match` on its variants — and that closures passed to HOFs (`for_each`, `prop_check`) follow standard `?` rules against their own return type, **not** the enclosing test's elaborated return type.

#### Phase C — Final vote

**Q1: Surface syntax for fallible tests.** (6-0 for (a) implicit elaboration)

- **Systems (a):** *"Implicit elaboration is the zero-cost surface choice. One lowering rule, one shape."*
- **Web/Scripting (a):** *"Invisible elaboration matches what JS/TS/Python devs expect. Concern: diagnostics must point back to the `?` site, not the synthetic signature."*
- **PLT (a):** *"Test bodies are not a regular call site; the runner is the sole caller, so implicit elaboration is a property of the test grammar form, not an exception in the function type system."*
- **DevOps (a):** *"What every modern test runner does. LSP hover must clearly indicate the elaborated return type."*
- **AI/ML (a):** *"~600 tokens saved across a realistic suite. Matches the dominant `?` pattern LLMs have seen in Rust-family training data."*
- **Minimalism (a):** *"Zero new surface tokens. Threading `?` through the existing shape is a lowering rule, not a language feature."*

**Q2: What is `E`?** (6-0 for (γ1) eager `Display[E].display` → sealed `TestError`)

- **Systems (γ1):** *"Eager `Display[E].display(e)` into a `TestError { message: Str }` carrier is the only option whose cost model I can defend on a slide. Happy path zero overhead. Error path is one bounded Display call plus one Str allocation. γ2 is a hard no. δ's two-shape failure mode means tooling has to branch on which carrier they got."*
- **Web/Scripting (γ1):** *"Eager `Display[E].display(e)` to `TestError { message: Str }` is the simple mental model: an error becomes a readable string in the report, exactly like a Python traceback or a Jest failure message."*
- **PLT (γ1):** *"Eager `Display[E].display(e)` is a principled injection `E → Str` via a type class, which composes with the rest of the type system without introducing existentials, vtables, or `dyn Trait`. δ keeps two shapes and loses uniqueness of the principal type."*
- **DevOps (γ1):** *"`TestError { message: Str }` gives a fixed, stable shape for diagnostics, NDJSON consumers, LSP hovers, and IDE failure panes. δ's two-shape carrier is hostile to CI parsers."*
- **AI/ML (γ1):** *"One sentence in the spec: 'errors become strings via `Display`, full stop.' The LLM never has to reason about union arity, vtable identity, or cross-call type unification."*
- **Minimalism (γ1):** *"Smallest addition: a stdlib struct plus a lowering rule, no new language machinery (no `dyn Trait`, no anonymous unions, no inference flavor). β leaks inference into a surface contract; α invents structural unions for one use site; γ2 imports vtable infra we don't have."*

**Q3: Failure status when test body returns `Err(e)`.** (6-0 for (a) reuse `"failed"` + `cause` discriminator)

- **Systems (a):** *"Adding a new NDJSON status fragments downstream consumers (CI dashboards, IDE integrations) for what is semantically still a test that did not pass. The discriminator field is free."*
- **Web/Scripting (a):** *"JS/Python devs already think of 'test failed' as one bucket; runners (Jest, pytest, vitest) don't distinguish assertion-fail from raised-exception at the status level, they put detail in the message."*
- **PLT (a):** *"`cause` is a refinement, not a new top-level state, so downstream consumers don't need to learn a new status. Concern: `cause` values must be a closed enum in the spec, not an open string, or it will drift."*
- **DevOps (a):** *"Reusing the existing status keeps every CI ingester, dashboard, and grep pattern working unchanged. Concern: schema the `cause` field now (type name + rendered message) so we don't paint ourselves into a corner when γ1 evolves."*
- **AI/ML (a):** *"Keeps the status vocabulary at the 4 already-decided values; adding `\"errored\"` forces every consumer to learn a 5th state whose only distinguishing feature is provenance."*
- **Minimalism (a):** *"This is subtraction (one status, richer payload) not addition. Nail down the `cause` schema in the spec so runners don't each invent their own shape."*

**Q4: knhwcf — single rule across `blink check` and `blink test`.** (6-0 for (a) confirm)

- All six panelists voted to apply one validation rule consistently. Concern from Systems: *"regression test must exercise both `blink check` and `blink test` on the same fixture to lock the invariant."* Concern from PLT: *"the rule statement should be phrased over the elaborated test type, not the surface form, to remain stable under future surface sugar."*

**Q5: Should the decision record explicitly reject the annotation form (b)?** (5-1 for (a) explicit reject)

- **Systems (a):** *"Two surfaces for the same semantics is a maintenance and teaching burden with zero codegen benefit; implicit elaboration subsumes everything (b) could do. Closing the door now prevents a future panel from reopening it under feature-creep pressure."*
- **Web/Scripting (a):** *"Deferring leaves a 'maybe someday' shadow feature that tutorial writers will speculate about; rejecting closes the door cleanly and we can revisit via a new spec gap if real demand emerges."*
- **PLT (a):** *"Leaving (b) merely 'deferred' invites speculative design pressure on the elaboration rules; an explicit reject with a documented reopen path is cleaner for the language reference."*
- **DevOps (a):** *"Allowing the explicit form too gives us two ways to spell the same thing, which means two formatter paths, two LSP code-action targets, and inevitable style-guide bikeshedding."*
- **AI/ML (b)** *(dissent)*: *"If (a) wins Q1 then explicit annotation is unused surface; shipping it now bakes a second syntax into the training data before we know if anyone wants it. Defer keeps the spec minimal and lets real usage drive the decision. Concern: a later addition is a breaking-ish docs churn for LLM context windows."*
- **Minimalism (a):** *"'Deferred' means 'we'll add it if users ask.' The user who would ask is the same user who will be told 'use the implicit form instead' — i.e., never. Deferral here is dishonesty about our actual intent. Better to say 'no' cleanly."*

Soft-consensus disposition: the dissent's concern (docs churn from a future addition) is *explicitly addressed* by the majority's reopen-path framing (revisit via a new spec deliberation, not silent addition). The record states reject **with** a documented reopen criterion.

**Q6: HOF closures follow normal `?` rules.** (6-0 for (a) confirm)

- All six panelists confirmed that closures passed to `for_each`, `prop_check`, etc. obey Rules 2 and 3 of §3c.2 against their own return type — the test body's implicit `Result[Void, TestError]` elaboration does **not** propagate inward. Concern from Systems: *"error message when a user hits this needs to point at the closure boundary explicitly, or it'll read as a spec bug."* Concern from PLT: *"ensure the elaboration of the test body does not leak its synthesized `E` into closures defined inside it — closures keep their own inferred `E`."*

#### Sibling tickets filed alongside this decision

- **Improve `.unwrap()` panic message** to embed the `Display`-rendered error value (proposed by Minimalism, accepted by silence). Cheap fix for the runtime-message complaint that drove some of the pressure toward this feature. Benefits every `.unwrap()` site, not just tests.
- **`prop_check` generic-`E` follow-up** (proposed by DevOps, unanimously deferred). Depends on ka3pw4 landing first.

### Final Spec

A test body uses `?` on `Result[T, E]` or `Option[T]` with no annotation. The compiler implicitly elaborates the body's return type to `Result[Void, TestError]` when any `?` appears.

```blink
test "connect and query" {
    let conn = pg.connect(url)?
    let row = pg.query(conn, "SELECT 1")?
    assert_eq(row.get_int(0), 1)
}
```

`TestError` is a sealed stdlib type:

```blink
pub type TestError {
    message: Str,
    error_type: Str,
    origin: SourceLocation,
}
```

**Locked design points:**

- Surface form `test "name" { body }` is unchanged. The annotation form `test "name" -> Result[Void, E] { ... }` is rejected — it does not exist now or in v1, and reopening requires a new spec deliberation citing a use case the implicit form cannot serve.
- Lowering at each `?` site rewrites the `Err(e)` arm to `return Err(TestError { message: Display.display(e), error_type: "<static name>", origin: <span> })`. For `Option[T]`, the `None` arm produces `Err(TestError { message: "None", error_type: "Option", origin: <span> })`.
- `Display[E]` is a hard requirement at every `?` site. Missing impl → E0512 at the `?` site.
- `TestError` is sealed: no user pattern-match, no construction outside the compiler-emitted lowering, no extension.
- Allocation occurs only on the error path. Passing tests are zero-cost for this elaboration.
- `blink check` and `blink test` apply the same elaboration rule. The knhwcf incoherence is resolved.
- Failure NDJSON: `status: "failed"`, `cause: "propagated_error"`, with `error.message` (rendered Str) and `error.error_type` (static name of `E` at the `?` site). The `cause` enum is closed: `"assertion" | "propagated_error"`.
- HOF closures (`for_each`, `prop_check`, etc.) obey §3c.2 Rules 2 and 3 against their own return type. The test-body elaboration does **not** propagate into nested closures.
- Power-assert introspection does not apply to `?`-propagated failures (there is no `assert(...)` site to decompose); the `TestError.message` carries the rendered context.
