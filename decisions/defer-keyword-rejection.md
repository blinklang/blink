[< All Decisions](../DECISIONS.md)

# Defer Keyword (Rejection) — Design Rationale

The original spec gap (br h8k8e7): "Spec: defer keyword for in-test (and general) teardown" — should Blink add a dedicated `defer fn() { ... }` keyword so test bodies (and general code) can register cleanup actions inline without nesting `with` blocks?

The panel rejected the keyword 6-0, but only after surfacing — and amending around — a real spec inconsistency that would have made `defer` a band-aid rather than a fix. See [BlockHandler Catchable-Unwind](blockhandler-catchable-unwind.md) for the independent amendment that resolves the underlying issue.

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated through Phase A → Phase A.5 → Phase B → Phase C. No Phase D was triggered (all questions resolved 6-0 except Q4 at 5-1, which qualified for the soft-consensus skip rule).

> **Note on quotation:** The panel artifacts preserved into morning review consist of the consolidated Phase C tally (`.tmp/deliberate_panel_votes.md`) and the per-panelist Concern fields recorded there. The pre-compaction Phase A and Phase B verbatim transcripts were not preserved as separate files; positions below are excerpted from the tally's "Key argument" and "Concerns flagged" sections with panelist attribution preserved.

#### Phase A — Independent proposals (option-space)

After Phase A.5 mechanical dedupe, four distinct shapes were on the table:

- **GENERAL_PRIMITIVE_UNWIND (Sys, original):** add `defer fn() { ... }` as a language primitive that fires on every unwind out of the enclosing scope. Rationale: covers test fixtures *and* general code; one mechanism, one keyword.
- **TEST_ONLY_SUGAR (Web):** `defer` only available in `#[test]` blocks; outside tests, use `with`. Rationale: tests are where the ergonomic pain is; general code already has `with`.
- **STDLIB_HELPER (Min, AI/ML):** no new keyword. Add `testing.cleanup(fn() -> Void) -> BlockHandler`, used as `with cleanup(fn() { ... }) { body }`. Rationale: stdlib already has `BlockHandler`; a new keyword adds learning surface for what is sugar over `with`.
- **REJECT (Min as alternate):** if the underlying problem is "with blocks leak on assertion failure", fix `BlockHandler.exit()` semantics, not the surface syntax.

#### Phase B — Debate highlights

The debate turned on a spec-correctness discovery. Excerpts (attributed):

- **Sys (re-reading §2.20 + §4.6.3):** "§4.6.3 says 'panics bypass `BlockHandler.exit()` entirely' but §2.20 line 1198 specs assert-failure panics as catchable unwind to the test runner. Today, `with db.transaction() { assert_eq(...) }` silently leaks the transaction on failure. That's a real bug, not a hypothetical. `defer` would paper over it without fixing the underlying soundness gap."
- **PLT:** verified Sys's reading and concurred. Position shift: "The `panic: Never` axiom is preserved if `exit(false)` runs on catchable unwind — the body cannot inspect, transform, or suppress the panic; it's runtime-driven finalization. Analogous to Rust `Drop` on unwind, Java `finally`. R3-forbidden fence on user-level recovery (no `recover`/`catch_panic` without a separate amendment) keeps the typing claim sound."
- **Min:** "Once `with` does the right thing on assertion failure, every motivating test pattern composes via `with cleanup(fn) { body }`. A new keyword would be additive without being foundational. YAGNI applies."
- **DevOps:** raised the only durable dissent — that flat `cleanup` doesn't compose well for tests with multiple cleanups, and proposed a `testing.scope() as s` registrar form alongside the one-shot helper. Did not attempt to revive `defer`.
- **Web, AI/ML:** both moved to REJECT_WITH_AMENDMENT once the §4.6.3 amendment was on the table; under the amendment the only motivating use case for `defer` (test cleanup that runs on assertion failure) is satisfied by `testing.cleanup`.

#### Phase C — Final vote

- **Q1: Which option resolves the spec gap?** — REJECT_WITH_AMENDMENT (6-0)
  - **Sys:** REJECT_WITH_AMENDMENT — the inconsistency I found means the bug is in `BlockHandler.exit()` semantics, not in the missing keyword. Concern: existing user-authored `BlockHandler.exit` impls assumed "panic bypasses"; they now run on more paths. Need migration disclosure + lint.
  - **Web:** REJECT_WITH_AMENDMENT — once `with` works correctly on assertion failure, no test pattern needs `defer`. Concern: ergonomics of multiple nested `with` blocks (deferred — see Q4 follow-up).
  - **PLT:** REJECT_WITH_AMENDMENT — soundness preserved (`panic: Never` survives because `exit(false)` is runtime-driven, not user-callable on the panic value). Concern: spec text must explicitly fence user-level recovery (R3-forbidden).
  - **DevOps:** REJECT_WITH_AMENDMENT — the diagnostic surface for `defer` was hard to reason about (when does it run? in what order? interaction with `with`?). Amending `with` keeps one mechanism. Concern: trace schema and E0824 (see Q4 dissent and concerns list).
  - **AI/ML:** REJECT_WITH_AMENDMENT — adding `defer` introduces a decision point at every cleanup site (`with` vs `defer`). Token cost and learnability both worse. Concern: stdlib helper must have a memorable name; `cleanup` clears that bar.
  - **Min:** REJECT_WITH_AMENDMENT — additions need foundational justification; once §4.6.3 is fixed, `defer` is sugar over `with cleanup(fn)`. Concern: the amendment is the load-bearing change; the rejection is downstream.

- **Q2: Should the amendment be recorded as a separate decision regardless of Q1 outcome?** — YES (6-0). The amendment fixes a real spec bug independent of the defer question. Filed as [BlockHandler Catchable-Unwind](blockhandler-catchable-unwind.md).

- **Q3: What does "catchable unwind" enumerate?** — closed set, R3-forbidden fence (6-0). The set is exactly `{? propagation, return, assert failure, skip()}`, runtime-defined and closed.

- **Q4: Naming for the stdlib helper** — `testing.cleanup(fn() { ... })` (5-1, devops dissent)
  - **Sys, Web, PLT, AI/ML, Min:** A — single HOF, mirrors `testing.for_each` (decision nyyt0s), no builder type, lowest LLM-hallucination surface.
  - **DevOps (dissent):** C — both `testing.cleanup` AND `testing.scope() as s` registrar shipped together. Concern: flat `cleanup` doesn't compose without nested `with` blocks; LSP needs a clean anchor for "registered cleanups in scope" hover.
  - **Soft-consensus interpretation (per skill Step 6):** majority's Concern fields explicitly endorse devops's worry. Treat as 5-1 with follow-up note: ship `testing.cleanup` first; revisit registrar form if real-world tests prove ergonomically bad. Phase D skipped.

- **Q5: Should `skip()` invoke `exit(false)` cleanup under the amendment?** — YES (6-0). Skip is controlled cooperative early-exit, structurally identical to `?` propagation at the runtime boundary. §2.20 line 1378 already specs skip as "the same machinery as assertion failure panics" — the amendment makes their cleanup behavior consistent.

### Final Spec

No `defer` keyword. The locked design points:

- Test (and general) teardown uses `with` blocks. For resources implementing `Closeable`: `with x = acquire() as x { body }`. For non-`Closeable` ad-hoc actions (temp paths, env-var resets, mock restores): `with cleanup(fn() { ... }) { body }`.
- The stdlib helper is `testing.cleanup(action: fn() -> Void) -> Cleanup` (a `BlockHandler`). Single HOF. See `lib/std/testing.bl`.
- Multiple cleanups compose via nested `with` blocks. If real-world tests show this is too noisy, a `testing.scope() as s` registrar form will be added as a follow-up — not as a replacement.
- Cleanup runs on every catchable unwind (normal exit, `?`, `return`, assertion failure, `skip()`) per the [BlockHandler Catchable-Unwind](blockhandler-catchable-unwind.md) amendment.

```blink
// Test cleanup that runs on every catchable unwind, including assertion failure
fn test_with_temp_dir() {
    let path = make_temp_dir()
    with cleanup(fn() {
        remove_dir(path)
    }) {
        // assertion failure here still runs the cleanup
        assert_eq(read_file(path / "config.toml").len(), 42)
    }
}
```
