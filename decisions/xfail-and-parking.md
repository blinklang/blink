[< All Decisions](../DECISIONS.md)

# Expected-Failure Tests + Parking — Design Rationale

Resolves br spec ticket **1c2zr6** ("should the testing framework support an expected-to-fail (xfail) marker?"). Motivating ticket: btvqbf — TDD red fixtures using `?` in test bodies that did not lex on the then-current compiler and triggered the runner's cancel-on-first-failure cascade when placed under `tests/`.

### Panel Deliberation

Six panelists (Systems, Web/Scripting, PLT, DevOps/Tooling, AI/ML, Minimalism) deliberated in independent-proposal → debate → vote rounds. The deliberation spanned three sub-questions:

- **Q1** — Parking workflow for fixtures that cannot build (formalized runner integration vs docs-only convention).
- **Q2** — Ship a runtime `xfail` mechanism now, or defer pending more evidence.
- **Q3** — If shipping, how to encode an expected-failure result without breaking the closed four-status / closed two-cause enums in §8.10.

#### Phase A — Independent proposals (excerpted)

- **Systems:** Proposed a new top-level `xfailed` status added to the `passed | failed | panicked | skipped` enum, with unexpected-pass surfacing as `xpassed`. Argued cost model: "a record-level boolean field paired with `status:"passed"` lies about what happened — the runner did observe a failure that was counted as success. A distinct status makes the cost legible at every NDJSON consumer." Concern: extending closed enum.
- **Web/Scripting:** Proposed `test.failing(name, reason, ticket) { ... }` as the source syntax — parallel to existing `test(name) { ... }` and `skip(reason)`. Cited pytest's `@pytest.mark.xfail(reason=..., strict=True)` as the familiar shape. "Mandatory `reason` + `ticket` is the only thing that keeps xfail from rotting — make the friction load-bearing."
- **PLT:** Voted to reject xfail. Position: parking + the existing `compile_test_helpers.expect_compile_error` wrapper already covers the TDD-red use case soundly without extending the runner's status surface. "Expected-failure is a process artifact, not a language-level concern. Encoding it in the test record's vocabulary couples the runner to a workflow."
- **DevOps/Tooling:** Proposed the boolean-field encoding (`expected_fail: Bool`, `xfail_reason: Str`) attached to ordinary status records. Argued LSP / formatter / `task ci` integration is cleaner if the enums stay closed and consumers learn one optional field rather than two new statuses. Authored the strict-by-default unexpected-pass rule and the closed-ticket lint requirement.
- **AI/ML:** Proposed the four-case mechanical decision rule (doesn't build → park; builds-runs-red-deliberate → `test.failing`; builds-runs-red-bug → ordinary `test`; should-not-run → `skip`). "An AI generating Blink code needs a rule that can be applied without judgment. Three of these four cases already have established mechanisms — adding the fourth fills a real gap."
- **Minimalism:** Proposed reject. "We already have `.tmp/<ticket>/` as a convention. The reported pain (cascade interaction) is a property of the runner's failure mode, not of the testing API. Fix the cascade, leave the API alone." Conceded later that strict-by-default + mandatory `reason` + `ticket` + closed-ticket lint mitigated the rot-vector concern.

#### Phase A.5 — Dedupe

Distinct Q1 options: docs-only convention (PLT/Minimalism); formalized parking with runner integration + lint (DevOps + AI/ML synthesis). Distinct Q3 options: new top-level status (Systems); new `cause` value (variant raised in debate); boolean field encoding (DevOps); reject Q2 entirely (PLT/Minimalism).

#### Phase B — Debate highlights

- **Systems → DevOps (excerpted):** "`status:"passed"` paired with `expected_fail:true` is fine on the page; it's wrong on the wire. Every downstream NDJSON consumer now needs to read two fields to know what to count." DevOps reply: "The four-status enum is closed by spec and load-bearing for tools already shipped. Opening it for a process artifact is the larger long-term cost — boolean fields are the standard idiom for ortho­gonal record metadata."
- **PLT (dissent, sustained):** "I'll accept Q2 = ship if Q3 stays closed-enum-preserving. My core objection is that we are encoding TDD-workflow state into the runner; if we must, do it in a way that doesn't widen the status vocabulary." Vote on Q3 went to F (boolean field) accordingly.
- **AI/ML (key swing argument on Q2):** "The four-case rule is the load-bearing piece. Without `test.failing`, three of four cases have a mechanism and the fourth degrades into ad-hoc commenting-out. That degradation is what produces the rot — and rot is harder to undo than a closed feature."
- **Minimalism (concession):** "If the lint is mechanical, ticket-coupled, and runs in `task ci`, I accept the package. The mitigations are doing the work that would otherwise require continuous human discipline."

#### Phase C — Final vote

- **Q1 (parking workflow with runner integration):** **5-1**
  - **Systems:** Aγ — runner integration with `--parked` flag and `parked_file` events; cascade suppression is the load-bearing fix.
  - **Web/Scripting:** Aγ — matches developer expectations from pytest's `xfail` and Rust's `#[ignore]`.
  - **PLT:** *(dissent)* Aα — docs-only convention; runner should not learn about parking as a concept.
  - **DevOps/Tooling:** Aγ — file-level NDJSON event is clean; lint over `.tmp/` is mechanical and offline-safe.
  - **AI/ML:** Aγ — the `parked_file` schema is distinct enough from per-test records to teach to consumers without ambiguity.
  - **Minimalism:** Aγ (conditional on mechanical lint) — accepted once the lint terms were locked.

- **Q2 (ship runtime xfail now):** **3-3 → user (BDFL) tiebreak in favor of shipping**
  - **Pro (ship now):** Web/Scripting, DevOps/Tooling, AI/ML — reasoning: real users requesting it (per BDFL), the four-case rule needs the fourth slot filled, mitigations bundled with shipping are sufficient.
  - **Con (defer):** Systems (status-enum concern), PLT (workflow-not-language concern), Minimalism (YAGNI — parking is enough).
  - **User BDFL:** "lets ship now. there are, in fact, blink users requesting it" — tiebreak recorded.

- **Q3 (encoding under closed enums):** **4-2** for F (boolean `expected_fail` + paired `xfail_reason`)
  - **Systems:** *(dissent)* — preferred new top-level `xfailed` status for record honesty.
  - **Web/Scripting:** F — closed enums are spec-load-bearing, boolean fields are the idiomatic alternative.
  - **PLT:** F — concession from the Q2 dissent: if shipping, preserve enum closure.
  - **DevOps/Tooling:** F — authored the encoding; suite-failure rule is mechanical.
  - **AI/ML:** F — fewer decision points for codegen; `status:"passed", expected_fail:true` is a single learnable pattern.
  - **Minimalism:** *(dissent)* — preferred not shipping at all; on Q3 conditional, would accept F over a new status.

#### Phase D

Not triggered for Q1 (5-1 with Phase C concerns endorsed by dissenter — soft consensus). Triggered procedurally for Q2 (3-3 tie); per the skill rules a 3-3 tie escalates to user BDFL after one focused round, and the user chose to break the tie directly without re-debate ("lets ship now"). Not triggered for Q3 (4-2 with Systems dissent reasoning explicitly preserved as a future reopen path if NDJSON consumers report ambiguity).

### Step 8.5 — AI-First Review

Scored 5/5: Learnability (one new test-registrar form with mandatory args), Consistency (parallels `test`/`skip`), Generability (four-case rule is mechanical), Debuggability (suite-failure rule is single boolean expression), Token Efficiency (no new keywords, optional fields only present when xfail is used).

### Final Spec

#### Parking — `.tmp/<ticket>/`

```
blink test --parked btvqbf
```

Emits file-level NDJSON events:

```json
{ "event": "parked_file",
  "path": ".tmp/btvqbf/red_question_mark.bl",
  "ticket": "btvqbf",
  "reason": "needs Phase-2 ? propagation in test bodies",
  "diagnostic": "lex error: unexpected token '?'" }
```

Cancel-on-first-failure cascade is suppressed under `--parked`. Outside `--parked`, the runner does not walk `.tmp/` at all. `task ci` lints `.tmp/` for closed tickets, missing tickets, and stale (>90d) directories.

#### Expected-failure test — `test.failing`

```blink
test.failing(
  "trait impl resolves through alias chain",
  reason: "Phase 3 trait elaboration not yet implemented",
  ticket: "btvqbf",
) {
  // ... test body, expected to fail today
}
```

NDJSON encoding (expected red):

```json
{ "name": "...", "status": "passed", "expected_fail": true,
  "xfail_reason": "br:btvqbf — Phase 3 trait elaboration not yet implemented" }
```

NDJSON encoding (unexpected pass — suite failure):

```json
{ "name": "...", "status": "failed", "cause": "assertion",
  "assertion": "expected failure, got pass",
  "expected_fail": true,
  "xfail_reason": "br:btvqbf — Phase 3 trait elaboration not yet implemented" }
```

#### Locked design points

- Four top-level statuses (`passed | failed | panicked | skipped`) remain closed.
- Two `cause` values (`assertion | propagated_error`) remain closed.
- `expected_fail: Bool` and `xfail_reason: Str` are the only new NDJSON fields.
- `reason` and `ticket` are **mandatory, non-empty** at the call site — separate `Str` fields, no regex parsing.
- Unexpected-pass policy: **strict by default, no soft mode**. The moment the test goes green it must be converted back to `test(...)` in the same commit.
- Mechanical closed-ticket lint via `br` integration runs in `task ci`; downgrades to warning if `br` is unreachable.
- Four-case decision rule (park / `test.failing` / ordinary `test` / `skip`) is normative spec text in §8.10.6.
