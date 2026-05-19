[< All Decisions](../DECISIONS.md)

# Multi-Cleanup Test Registrar — Design Rationale

The original spec gap (br 8y2s5x): "Spec + impl: `testing.scope()` registrar API for multi-cleanup tests." This was the Q4 dissent (devops, 5-1) from the [Defer Keyword Rejection](defer-keyword-rejection.md) panel — the worry that `testing.cleanup(fn)` is one-shot and that multi-cleanup tests would devolve into deeply nested `with` blocks. The ticket directive: "Ship if real-world test patterns prove flat `cleanup` is too clunky."

The panel rejected the registrar 4-2 with soft consensus, on the grounds that the conditional has not fired: there is no evidence of real-world clunk, the prior helper has zero callers in the repo, and consciously shipping a `defer`-shaped API risks inviting exactly the pattern-matching failure mode the original defer rejection was designed to prevent.

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated through Phase A → Phase A.5 → Phase B → Phase C. Phase D was not triggered (Q1 4-2 result qualified for the soft-consensus skip rule; Q2/Q3 were 6-0 / convergent).

> **Note on quotation:** Phase A/B verbatim transcripts were preserved in the team channel and per-panelist Concern fields recorded in the Phase C tally. Excerpts below preserve panelist attribution.

#### Phase A — Independent proposals (option-space)

After Phase A.5 mechanical dedupe, three distinct shapes were on the table:

- **S — Ship Scope BlockHandler now (Sys, Web, PLT, DevOps original):** add `testing.scope()` returning a `Scope` value implementing `BlockHandler`. `Scope` has a `cleanup(self, action: fn() -> Void)` method that pushes onto an internal `List[fn() -> Void]`; `exit(ok)` drains LIFO. Used as `with testing.scope() as s { s.cleanup(...); s.cleanup(...) }`. Rationale: solves the multi-cleanup pyramid; mirrors `defer` semantics intentionally.
- **L — Ship as plain `List[fn() -> Void]` helper (no new type):** expose `testing.cleanups() -> List[fn() -> Void]` and have the test author iterate the list themselves inside `with cleanup(fn() { ... })`. Rationale: avoids inventing a new BlockHandler; surface is just stdlib list ops.
- **R — Reject, revisit only on evidence (Min, AI/ML; DevOps and PLT migrated to R in Phase B):** do not ship. Document a reopening trigger so the question can be re-litigated when the conditional from the parent ticket actually fires. Rationale: zero callers of the existing `testing.cleanup` helper; shipping a registrar now is speculative API surface.

#### Phase B — Debate highlights

The debate turned on two pieces of evidence surfaced by the Minimalism and AI/ML panelists. Excerpts (attributed):

- **Min (evidence):** "`rg -l 'testing\.cleanup'` in this repo returns zero callers. The conditional from 8y2s5x — *'ship if real-world test patterns prove flat cleanup is too clunky'* — hasn't fired. We don't yet have the data to know whether the pyramid is even a real problem, let alone whether `Scope` is the right shape for it. Shipping S preemptively burns the option to ship a *better* shape we'd learn from real use."
- **AI/ML:** "S deliberately mimics the shape of `defer`. The original [Defer Keyword Rejection](defer-keyword-rejection.md) panel rejected `defer` partly because users will unconsciously pattern-match it onto Go's semantics. Consciously aping that shape in a library function inherits the same hazard — LLMs and humans alike will assume LIFO drain on every catchable unwind, register-multiple-actions, etc. without checking. The fact that we *intend* the resemblance doesn't help the reader who never read the rationale."
- **PLT (position shift S → R):** "My Phase A argument was that body-local reasoning about `s.cleanup(...)` is no worse than `list.push(...)`. On reflection that was over-generous to S — the difference is that `list.push` doesn't carry implicit unwind semantics, and `s.cleanup` does. Min's 'no callers yet' challenge is symmetric: it applies to L just as much as to S. My real vote is R unconditionally."
- **DevOps (position shift S → R, originator):** "I filed this ticket. I was wrong in Phase A to wave off the Go-shape concern as 'aping consciously.' Conscious aping doesn't protect users — user pattern-matching is unconscious. If we ship S with no demand evidence, we're shipping a feature whose primary readers will be wrong about it. Reopen only when there's an MVCE."
- **Sys (held S):** "I'd still ship S now to lock the test surface — there's a codegen audit owed on stacked `with` LIFO ordering regardless of whether we add `Scope`. But I accept that 'no callers' is symmetric evidence, and I won't push past R if the majority lands there. Reopen within two release cycles if real demand emerges."
- **Web (held S):** "The 3-deep `with` pyramid *is* a real UX cost — I've seen it in the panel's own example. If we ever ship S, the spec must include a worked B-then-C-then-A example so readers see LIFO drain order. For now I'll defer to the evidence, but mark this for re-litigation on the first friction ticket."

#### Phase C — Final vote

- **Q1: Ship registrar now (S), ship as plain list (L), or reject pending evidence (R)?** — **REJECT 4-2 (soft consensus)**
  - **AI/ML:** R — `Scope` shape inherits the Go-prior hazard from `defer`. Concern: reopening trigger must be concrete enough that a future panel won't re-litigate the same speculative arguments.
  - **DevOps:** R — I filed this; I'm withdrawing it. Conscious shape-mimicry doesn't protect users. Concern: friction tickets must be filable against absence-of-feature, not just bugs; needs a ticketing convention note.
  - **Min:** R — zero callers of the prior helper. Concern: someone will eventually want this; reopening criteria must be reachable, not impossibly high.
  - **PLT:** R — list.push analogy was wrong; `s.cleanup` carries unwind semantics that `list.push` doesn't. Concern: the spec text for §4.6.3 LIFO order on stacked `with...as` must be tightened regardless of this decision — that's an independent latent ambiguity.
  - **Sys:** *(dissent)* S — codegen audit owed on stacked LIFO regardless; would prefer to lock the test surface now. Concern: "Min's 'no callers yet' is symmetric. We will reopen this within two release cycles."
  - **Web:** *(dissent)* S — pyramid is a real UX cost. Concern: "If we ever ship S, spec must include the B-then-C-then-A worked example so readers see LIFO drain order."

- **Q2: When `exit(false)` itself panics mid-drain on a stacked `with...as`, do remaining cleanups still run?** — **CONTINUE DRAIN 6-0**. Remaining handlers in the stack still fire. The first panic is preserved as the unwind cause; secondary panics surface as `E0824` warnings in the trace (consistent with the BlockHandler Catchable-Unwind amendment, point 2). No short-circuit: short-circuiting would leak resources held by deeper-stacked handlers.

- **Q3: Reopening trigger.** Convergent across all six panelists. The registrar question may be reopened when **all three** of the following hold:
  1. A friction ticket (br `type:friction`) with an MVCE showing ≥3 distinct test sites that legitimately need 3+ cleanups (not the same cleanup pattern copy-pasted).
  2. A documented attempt to use the plain-list shape (L) — appending closures to a `List[fn() -> Void]` inside one `with cleanup(fn)` block — that demonstrably fails or is materially worse than what `Scope` would offer.
  3. An RFC-style proposal that locks the API shape *and* states the spec text it requires, so reopening is not a from-scratch deliberation.

If only condition (1) holds, the reply is "use L for now and add the test sites to the ticket." If conditions (1) and (2) hold but (3) is missing, the response is "file an RFC."

### Final Spec

**No new API.** No new spec text. The decision is to record this deliberation and the reopening trigger; no section of the spec is amended by this decision.

Cross-references for future readers:

- For one-shot cleanup, use `with cleanup(fn() { ... }) { body }` — see [BlockHandler Catchable-Unwind](blockhandler-catchable-unwind.md).
- For multi-resource cleanup, use stacked `with...as` blocks (LIFO drain per §4.6.3).
- For the parent dissent that spawned this ticket, see [Defer Keyword Rejection](defer-keyword-rejection.md) Q4.

```blink
// What multi-cleanup looks like under the current API (no registrar).
// Stacked `with` blocks drain LIFO on every catchable unwind.
fn test_with_multiple_resources() {
    let temp = make_temp_dir()
    with cleanup(fn() { remove_dir(temp) }) {
        let port = reserve_port()
        with cleanup(fn() { release_port(port) }) {
            let mock = install_log_mock()
            with cleanup(fn() { restore_log_mock(mock) }) {
                // body — assertion failure here drains mock → port → temp
                assert_eq(run(temp, port), 42)
            }
        }
    }
}
```

### Notes on the soft-consensus call

The 4-2 split would normally trigger Phase D. The skill's soft-consensus rule applies because:

- Both S-voters (Sys, Web) explicitly endorsed the reopening criterion in their Concern fields rather than challenging the R verdict.
- The R-majority's Concern fields explicitly acknowledged that real demand may emerge and that reopening must remain reachable.
- The substantive disagreement is **timing**, not direction: nobody on the panel argued the registrar shape is wrong in principle if the conditional fires.

Phase D would have re-litigated timing without new evidence; the better use of cycles is to let the conditional fire (or not) over the next release cycles and revisit then.
