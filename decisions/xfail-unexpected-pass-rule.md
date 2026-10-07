[< All Decisions](../DECISIONS.md)

# Unexpected-Pass Rule Text in §8.10.6 — Design Rationale

The §8.10.6 suite-failure rule said `status == "passed" && expected_fail` is an unexpected pass. The example beside it, the runtime (`bootstrap/runtime_test.h`) and the locked encoding ([xfail-and-parking.md](xfail-and-parking.md) Q3, [panicked-status-reporting.md](panicked-status-reporting.md) Q3) all give an unexpected pass as `status: "failed"`, `cause: "assertion"`, `assertion: "expected failure, got pass"`. A `passed` record with `expected_fail: true` is an expected red. A tool that followed the old rule failed every known-red test. Follow-up F3 of the panicked-status panel (6-0, "fix, not debate").

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated
in independent-proposal → debate → vote rounds.

Facts the moderator gave the panel from the codebase:

- **F1.** `bootstrap/runtime_test.h:478-497`: the only code path that sets failed on an `expected_fail` test is the unexpected-pass inversion. Any observed failure of an `expected_fail` test is cleared to passed. So in the runtime, failed && expected_fail occurs only for an unexpected pass.
- **F2.** A `test.failing` body can call `skip()`. The runtime then emits status "skipped" and does not print `expected_fail` on that record. The field table says `expected_fail` is "`true` iff the test was registered with `test.failing`".
- **F3.** The only copy of the wrong rule was `sections/06_tooling.md:1424`.
- **F4.** The runtime does not emit status "panicked" yet (the panicked-status decision is spec, impl pending).

#### Phase A — Independent proposals

All six proposed the same core: change the rule, keep the example, add no field, status or cause value.

- **Systems:** "The suite-failure rule is mechanical. The suite fails when `failed + panicked > 0`. A record counts as follows: ... `status == "failed"` and `expected_fail == true`: unexpected pass. ... `status == "panicked"`: panic. `expected_fail` is never true here." Add-on: "`expected_fail` is a property of the test, not the outcome. A consumer MUST NOT infer pass or fail from `expected_fail` alone."
- **Web/Scripting:** "`status == "failed" && expected_fail` - unexpected pass. ... `status == "panicked"` - panic. `expected_fail` is never true here." Add-ons: "An unexpected pass is the only record with `status: "failed"` and `expected_fail: true`. A consumer finds it with that pair. It never needs to match the `assertion` text." and "An unexpected-pass record does not carry `xfail_observed`."
- **PLT:** "The suite-failure rule is mechanical. It reads only `status`. The `expected_fail` field never changes whether a record counts as a failure. ... `status == "skipped"`: the suite does not fail. A record with `expected_fail: true` never has `status == "panicked"`." Add-on: "An unexpected pass is the only record with `expected_fail: true` and `status: "failed"`."
- **DevOps:** "`status == "failed"` — the suite fails. This holds for both values of `expected_fail`. ... `status == "passed" && expected_fail` — expected red. The suite does not fail." Add-on: "A consumer MUST NOT use `expected_fail` alone to find an unexpected pass. To list unexpected passes, select `status == "failed" && expected_fail`. To list known reds, select `status == "passed" && expected_fail`."
- **AI/ML:** "Read `status` and `expected_fail` only: `status == "failed"` — suite fails. ... `status == "skipped"` — no effect." Add-on in §8.10: "The exit code is non-zero when `failed + panicked > 0`. An unexpected pass counts as `failed`."
- **Minimalism:** "change the rule text only, nothing else. ... `status == "failed" && expected_fail` - unexpected pass (`cause: "assertion"`, `assertion: "expected failure, got pass"`). The suite fails." "I suggest NOT adding a new bullet that says 'a consumer must check expected_fail to find unexpected passes'."

#### Phase B — Debate highlights

- **PLT** on the rule shape: "A total function has no gaps, and V1a leaves `skipped` undefined." On F2: "this is a real spec bug ... File F2 as a separate ticket. Do not widen cwbd65."
- **Web** dropped pair keys: "A dev can read it as a switch statement. ... I drop my V1a." On F2: "V1b's skipped bullet must not mention `expected_fail`, so the new text stays true under both fixes."
- **Systems** and **DevOps** dropped pair keys for the same reason. DevOps withdrew the long consumer note: "I withdraw my longer B text if V1b and V2 are in, since they carry the selectors."
- **AI/ML** on the consumer warning: "A MUST NOT line adds a rule to learn. Fewer rules, fewer errors."
- **Minimalism** *(dissent on Q2, Q6)*: "Prefer V1a. Bullets keyed by (status, expected_fail) pairs show the unexpected pass next to the example." On the §8.10 sentence: "Editing two places creates two copies that can drift."

#### Phase C — Silent vote

- **Q1: replace the rule so it matches the example** (6-0, A)
  - **Systems:** "The rule then matches the example and the runtime. It uses the same `failed + panicked > 0` test as the exit rule, so the harness needs no new code."
  - **Web/Scripting:** "Without it a dev reading the rule counts known reds as failures."
  - **PLT:** "the current rule contradicts the decided encoding and the runtime."
  - **DevOps:** "A CI tool that follows the old text fails every known red test. The fix is mechanical."
  - **AI/ML:** "the rule must match the example and the locked encoding; the runtime already follows the example."
  - **Minimalism:** "Changing only the rule is the smallest fix."
- **Q2: rule shape** (5-1, B: keyed by `status` alone over all four statuses; Minimalism dissent)
  - **Systems:** "A rule keyed on `status` alone is total and costs one compare. Pair keys leave `skipped` undefined."
  - **Web/Scripting:** "status-only bullets read like a switch; a dev checks one field first."
  - **PLT:** "a rule keyed by status alone is a total function over the closed enum."
  - **DevOps:** "A rule keyed on `status` alone covers all four statuses, so a consumer switches on one field."
  - **AI/ML:** "one key (`status`) with all four statuses listed leaves no gap, so a model cannot guess a missing case."
  - **Minimalism:** *(dissent)* "the pairs sit next to the example and show the one case that changed. V1b adds a skipped bullet that states a fact nobody disputes."
- **Q3: invariant sentence** (3-3: A for Systems, AI/ML, Minimalism; B for PLT, Web, DevOps → Phase D)
- **Q4: consumer sentence** (3-3: A none for AI/ML, Web, Minimalism; B for PLT, Systems, DevOps → Phase D)
- **Q5: `panicked` / `xfail_observed` sentences** (4-1-1: B for PLT, Web, DevOps, Systems; A for Minimalism; C for AI/ML → Phase D)
- **Q6: add "An unexpected pass counts as `failed`." to §8.10** (5-1, A; Minimalism dissent)
  - **Systems:** "The exit rule is where a CI user looks first. One sentence there removes the question at no cost."
  - **Web/Scripting:** "a reader of the exit rule gets the answer at the place they look."
  - **PLT:** "the exit rule is the source of truth for the verdict, and one added sentence keeps the two sections agreeing in one reading."
  - **DevOps:** "People read the exit rule in §8.10 and may not read §8.10.6."
  - **AI/ML:** "a model that reads only §8.10 gets the exit rule right. One sentence, low cost."
  - **Minimalism:** *(dissent)* "A second statement is a second copy that can drift."
- **Q7: F2, skipped `test.failing` records** (3-2-1: A for PLT, Web, Minimalism; B for AI/ML, Systems; C for DevOps → Phase D)

#### Phase D — Round 2 (Q3, Q4, Q5, Q7)

Debate highlights:

- **Web** on Q3: "the invariant says which pair to test; the clause says not to test a string. Those are two facts. ... If the panel wants it shorter, I accept: "A consumer tests the pair, not the `assertion` text.""
- **AI/ML** moved on Q3: "The "never match the `assertion` text" clause is not a repeat. It keeps a string out of the contract." And on Q5: "I concede the first sentence ... I hold against the `xfail_observed` sentence. It repeats lines 1402-1406."
- **DevOps** on Q4: "Concede. I drop the MUST NOT." On Q7: "Concede to A. ... Condition: file the F2 ticket in the same change."
- **Systems** on Q7: "I withdraw B, with one condition: file the F2 ticket in the same change, as DevOps asked."
- **Minimalism** on Q5: "Lines 1402-1406 already say xfail_observed appears only when expected_fail is true and status is "passed". An unexpected pass has status "failed", so the rule already excludes it."

Final ballot:

- **Q3: invariant sentence** (5-1, B2: "An unexpected pass is the only record with `expected_fail: true` and `status: "failed"`. A consumer tests the pair, not the `assertion` text."; Systems dissent)
  - **Web/Scripting:** "the clause keeps a string out of the consumer contract, and B2 says it in one short line."
  - **PLT:** "the short form keeps the practical point (test the pair, not a string) in one line, and it answers the repeat objection by being shorter than B1."
  - **DevOps:** "It gives the same contract as B1 in one short line. It keeps the string out of the contract."
  - **AI/ML:** "the short clause ... says the same as B1 in fewer words and keeps the string out of the contract."
  - **Minimalism:** "B2 is the shortest form that states it."
  - **Systems:** *(dissent)* "The invariant alone gives a field-only test, and a field-only test already means no string match. The clause adds words, not a case."
- **Q4: "`expected_fail` is a property of the test, not the outcome."** (3-3 → user broke tie for A, no sentence)
  - **Web/Scripting:** A — "Q3 and the status bullets already say what each pair means; a third statement is another place to keep in sync."
  - **AI/ML:** A — "the `status`-keyed bullets and the Q3 sentence already carry the point; a third statement is a third place to keep in sync."
  - **Minimalism:** A — "Q2=B and Q3 already carry the point. A third statement is a third place to keep in sync."
  - **Systems:** B — "One sentence blocks the inference that caused this ticket. No MUST NOT is needed."
  - **PLT:** B — "one plain sentence blocks the exact misreading that caused this ticket, with no normative word."
  - **DevOps:** B — "One sentence blocks the misreading that caused this ticket. It costs little."
  - **User tiebreak:** A (leave out).
- **Q5: invariant sentences** (3-3 → user broke tie for A: "`expected_fail` is never true on a `panicked` record." only)
  - **PLT:** A — "it closes a real gap, since a panicked record with expected_fail true would otherwise be unclassified. The xfail_observed sentence duplicates lines 1402-1406, so I move from B to A to cut the repeat."
  - **AI/ML:** A — "the "never on `panicked`" sentence closes a case the bullets leave open. The `xfail_observed` sentence repeats lines 1402-1406."
  - **Minimalism:** A — "the "never on panicked" sentence closes a gap no bullet covers. The second sentence repeats lines 1402-1406."
  - **Web/Scripting:** B — "both sentences close a gap for a validator or consumer, and each is one line."
  - **Systems:** B — "Both sentences close a gap for a validator: no `panicked` record is expected red, and no unexpected pass has `xfail_observed`."
  - **DevOps:** B — "The second stops a validator from accepting an unexpected pass with `xfail_observed`."
  - **User tiebreak:** A.
- **Q7: F2** (6-0, A: keep this change narrow, file a follow-up in the same change)
  - **Web/Scripting:** "F2 needs its own choice (B or C) and C needs a runtime change; folding it in would delay a 6-0 fix. The new text says nothing about expected_fail on skipped records."
  - **Systems:** "The choice between B and C is a separate decision. The new text says nothing about skipped records, so it holds under either fix."
  - **PLT:** "F2 needs its own choice between fixing the table and fixing the runtime, and the new text holds under both."
  - **DevOps:** "The new text holds under either fix, and the choice between table and runtime needs its own decision."
  - **AI/ML:** "the F2 fix needs its own choice (table or runtime), and the new text holds under both."
  - **Minimalism:** "File the follow-up in the same change with the MVCE and both fixes listed."

### Final Spec

§8.10.6:

```
The suite-failure rule is mechanical. It reads only `status`:

- `status == "failed"` — the suite fails. When `expected_fail` is absent or `false`,
  this is an ordinary test failure. When `expected_fail` is `true`, this is an
  unexpected pass, with `cause: "assertion"` and `assertion: "expected failure, got pass"`.
- `status == "panicked"` — the suite fails.
- `status == "passed"` — the suite does not fail. When `expected_fail` is `true`,
  this is an expected red (see `xfail_observed`).
- `status == "skipped"` — the suite does not fail.

An unexpected pass is the only record with `expected_fail: true` and `status: "failed"`.
A consumer tests the pair, not the `assertion` text. `expected_fail` is never true on
a `panicked` record.
```

§8.10 exit rule gains: "An unexpected pass counts as `failed` (§8.10.6)."

- The suite verdict is a function of `status` alone. The exit rule `failed + panicked > 0` is unchanged.
- No new field, status or cause value. The example and the runtime do not change.
- The text says nothing about `expected_fail` on `skipped` records. A follow-up ticket decides that (F2).
- No implementation ticket: the runtime already emits this encoding.
