[< All Decisions](../DECISIONS.md)

# Assertion Failure in a Cleanup During an Unwind — Design Rationale

§4.7.2 and §8.10 say that a cleanup that panics during a catchable unwind is a `warning`-severity E0824 entry and that
the original cause stays the test result. They did not say what a failed assertion (`assert`, `assert_eq`,
`assert_ne`, `assert_matches`) in `exit(false)`/`close()` does. The runtime dispatched a drain assertion as a panic.
So an armed `assert_panics` unwind whose cleanup asserted gave `passed` and an E0824 entry. On a `skip()` unwind the
cleanup assertion appeared nowhere (`skipped`, no entry). Under a `for_each` case, the same `skip()` shape gave
`failed` with the cleanup assertion as the payload.

## Summary

| Q | Question | Result | Vote |
|---|---|---|---|
| Q1 | Armed `assert_panics` unwind, `matching:` holds | A: `failed`; the cleanup assertion is the payload; no E0824 entry | 6-0 (Phase A 3-3) |
| Q2 | `skip()` unwind and `skip()` in a `for_each` case | A: `failed`; the cleanup assertion is the payload; the skip reason is dropped | 6-0 |
| Q3 | E0824 entry shape | A: unchanged (`code`, `message`) | 6-0 |
| Q4 | ERROR_CATALOG E0824 row text | A: "`exit(false)`/`close()` panicked, or failed an assertion after an earlier failure" | 6-0 |
| Q5 | Where the skip rule is stated | A: one sentence in §2.20 `skip()` plus the §4.7.2 edits | 5-1 (Minimalism dissent: B) |

Phase D did not run. AI-First: 5/5.

Agreed points, not balloted: no language change and no new code; E0824 keeps its code and name; normal completion,
`?` and `return` fail the test with the cleanup assertion as the payload; after a recorded failure the cleanup
assertion is an E0824 entry; a cleanup panic keeps the decided behaviour; the lost failure on a `skip()` unwind is a
runtime bug; an armed unwind with a `matching:` mismatch keeps E0832 as the result and the assertion is an E0824
entry; the E0824 message carries the full assertion text.

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in
independent-proposal, debate, vote rounds. Phase A and Phase B are excerpted from each panelist's own text, with "…"
for cuts. Phase C is quoted in full from each panelist's file, without its heading lines.

#### Phase A — Independent proposals

On the armed path Phase A split 3-3: `passed` plus E0824 (Systems, DevOps, Minimalism) against `failed` with the
cleanup assertion as the payload (Web/Scripting, PLT, AI/ML). On the `skip()` path five seats held `failed` and DevOps
held `skipped` plus an E0824 entry.

- **Systems:** "**Rule.** A cleanup assertion failure is a *cleanup fault* (secondary E0824 warning) only when an earlier **cause** is already recorded or armed: an assertion failure, an expected panic in an armed `assert_panics`, or a propagated panic. In every other case it is the test's **first failure** and is recorded as a normal `failed` record (full span, user message, introspection). `skip()` is not a cause. A failing assertion beats a skip." … "q3 and q9 are runtime bugs under this rule (the failure is lost). q14 is correct." … "A new code (E0825) adds a catalog row, a JSON enum value and a second check in the runtime for the same state. It buys no hardware-visible or tooling gain, since the message already shows \"assertion failed\"."
- **Web/Scripting:** "Rule: an assertion failure (`assert`, `assert_eq`, `assert_ne`, `assert_matches`) inside `exit(false)`/`close()` is a test failure, on every path. §4.7.2's table already lists it as a row separate from \"panic\", so E0824 (\"panics\") does not cover it. If the test already holds a failure when the cleanup assertion fails, the first failure stays the result and the later one becomes an E0824 entry (a second failure, not lost)." … "Why a user would expect this: a dev writes `assert` inside `close()` to check that cleanup released something. If the test then shows green with a small warning (q1) or green/skipped with nothing (q3, q9), the check did nothing. A skipped result that hides a failed assert is the worst case: CI reads it as \"not run\", not \"broken\"." … "Weaker: a pass with a failed check inside. I oppose it, but it is the smallest edit."
- **PLT:** "A test outcome is a join over a lattice: `passed < skipped < failed(assertion) < panicked`, with one rule: **a failed assertion is a verdict, never a fault report, and a verdict cannot be lost.** A panic in cleanup is a fault: it cannot replace a primary cause, so it is a warning (E0824, decided). An assertion failure in cleanup is a verdict: it decides the test unless a failing primary outcome already decides it." … "Skip is the key case. `skipped` means \"no verdict\"; a failed assertion is a verdict, so `skipped` + lost assertion (q3/q9) is unsound."
- **DevOps:** "**Rule.** An assertion failure inside `exit(false)`/`close()` is a cleanup fault, the same as a panic. What the test does depends on one question: did the test already have a result-determining cause when the cleanup ran?" … "- Cause present (armed `assert_panics` unwind, assertion-failure unwind, `skip()` unwind): the cause stays the status. The cleanup fault adds an `E0824` entry. No separate failing record." … "q14 is a bug under this rule. A `skip()` case must stay `skipped` and gain an E0824 entry." … "Add optional `kind` (`\"panic\"` or `\"assertion\"`) and `location` (`\"file:line\"`)." … "**Tradeoffs.** A warning is easy to miss in CI. The author of a broken teardown sees `passed`." … "Tools that read only `status` never see the fault. That cost is accepted: it matches Q6."
- **AI/ML:** "**Rule (one sentence, for the spec):** A failed assertion inside `exit(false)`/`close()` is a test failure. If the unwind already carries a failure (assertion, `?` error, `E0832`), that failure stays the result and the cleanup assertion becomes an `E0824` entry. Otherwise the cleanup assertion becomes the result." … "An expected panic caught by `assert_panics` and a `skip()` are not failures. A cleanup assertion therefore fails the test on those paths." … "Silent green is the worst result for LLM-written tests. A model that writes `assert(self.released)` in `close()` expects a red test when it fails. Today q1 passes, q3 and q9 lose the failure, and the author sees only a warning or nothing." … "Add no `kind` field (YAGNI)."
- **Minimalism:** "Rule: an assertion failure inside `exit(false)`/`close()` counts as a cleanup panic for E0824 **only when the test already holds a result that is a failure or an expected panic**. If no such result exists, it is a normal assertion failure and fails the test. A `skip()` is not a failure, so it holds nothing." … "Why skip: q3/q9 report `skipped` while an assertion failed and appears nowhere. A test that hides a failed check is a correctness bug. q14 shows the runtime already does the right thing under `for_each`; q3 and q9 are the outliers." … "A second code (\"E08xx CleanupAssertionFailed\") adds a catalog row, a docs page and an AI decision point to separate two things authors treat the same: \"my cleanup is wrong\"."

#### Phase B — Debate highlights

Round 1 ran as a written exchange. Every seat read all six Phase A files. Systems and DevOps moved to the `failed`
reading on the armed path. Minimalism held `passed` plus E0824 and said it would move if the panel treated a green
test with a failed check as a defect. DevOps withdrew `skipped` plus E0824, `kind` and `location`.

- **Systems:** "**I change my position on O1.** I now hold plt-1. In sys-1 I counted an armed expected panic as a \"cause\". That was wrong. The caught expected panic is a success outcome, not a failure to retain. Q6 (6-0) rules on a cleanup *panic*; it says nothing about a failed assertion, which is a separate row in the §4.7.2 table. A `passed` record that hides a failed check is a false green, and the cost to fix it is one flag test on a cold path (the armed flag already exists)." Text now held: "A failed assertion in `exit(false)`/`close()` is the test's first failure unless the unwind already carries a failure (an assertion failure, or an E0832 mismatch). Then the first failure stays the result and the later assertion is an E0824 entry. An expected panic caught by `assert_panics`, and `skip()`, are not failures."
- **DevOps:** "**Why I move.** My devops-1 rule treated `skip()` and an expected panic as \"causes\". A cause is something the test fails on. A skip and a caught expected panic are non-failing outcomes. If a cleanup assertion fails after one of them, no failure is recorded yet, so the assertion is the first failure." … "A `skipped` or `passed` record with a failed check is also the worst diagnostic: CI reads `skipped` as \"not run\". The warning line is the weaker surface." … "I withdraw \"q14 is a bug\"."
- **PLT:** "**O1: `failed` with the cleanup assertion as payload.** Q6's ballot question was \"Cleanup panic during an armed `assert_panics` unwind\". It did not rule on assertion failures, and §4.7.2's table lists the two as separate rows. So `failed` does not reopen Q6." … "devops-1's \"an assertion counts as a cleanup panic\" would make `assert(false)` and `panic(\"\")` equal in cleanup but different in the body."
- **Web/Scripting:** "**O1 (armed, `matching:` holds).** I hold `failed`, cleanup assertion as payload, no E0824. This is the real split (web, plt, aiml vs sys, devops, min). My reason is the 90% case: a dev puts `assert` in `close()` to check teardown. A green test with a warning line means the check did nothing, and CI tools that read only `status` never see it."
- **AI/ML:** "The deciding AI point: the Q6 ballot question was \"Cleanup *panic* during an armed unwind\". An assertion is a verdict and the §4.7.2 table lists it as its own row, so Q6 does not decide it." … "An LLM reads §2.20 for skip behaviour and will not look in §4.7.2."
- **Minimalism:** **(dissent on O1, held)** "**O1: hold min-1 (E0824 entry, test stays `passed`).** The armed-path vote was 6-0 on \"cleanup panic during an armed unwind\" (Q6, V5c). The runtime already dispatches a drain assertion as a panic, so this is zero change and zero new text beyond the two-word edit." … "I will not move unless the panel treats the green result as a defect; then I take plt-1 over web-1, since it has the lattice reason." On placement: "**O6: one place only.** State the skip rule once, in §4.7.2 as a note under the table. A second sentence in §2.20 repeats it and will drift. If the panel wants a pointer in §2.20, make it a cross-reference, not new rule text."

#### Phase C — Final vote

Fresh panelists voted alone after they read the Phase A and Phase B files.

- **Q1: Armed `assert_panics` unwind, `matching:` holds (q1, q8)** (6-0; Phase A was 3-3, Systems and DevOps moved in Phase B, Minimalism moved in Phase C)
  - Option A: `failed`; the cleanup assertion is the payload (span, user message, introspection); no E0824 entry.
  - Option B: the expected panic stays the result (`passed`); the cleanup assertion is an E0824 entry.
  - **Systems:** A — Reasoning: "An expected panic caught by `assert_panics` is a success outcome, not a failure to retain. A failed assertion is a verdict, and `passed` with a failed check inside is a false green that tools reading only `status` cannot see. The runtime cost is one flag test on the cold drain path in `__blink_test_fail_unless_first` (record the failure first unless `__blink_test_failed` or a pending E0832 failure is set). It adds no state and no cost outside tests." Concern: "The armed path now differs from a cleanup panic on the same path (`failed` versus `passed` + E0824), so authors must learn that `assert` and `panic()` differ in cleanup."
  - **Web/Scripting:** A — Reasoning: "A dev who writes `assert` in `close()` wants a red test when the check fails. Under B the test shows `ok` with a warning line, and CI tools, dashboards and agents read `status`, so the check does nothing. An expected panic caught by `assert_panics` is a success, not a failure to keep. Q6 ruled on a cleanup panic, not on a check the author wrote, and §4.7.2 lists the two as separate rows." Concern: "A makes the armed path differ from a cleanup panic (warning), and a JS/Python dev may ask why `assert` and `panic()` in the same `close()` give different results."
  - **PLT:** A — Reasoning: "`assert_panics` catches the expected panic and its verdict is success, so the primary outcome is non-failing. A failed assertion is a verdict, and a verdict must not be lost. Q6 ruled on a cleanup panic (a fault); the §4.7.2 table lists assertion failure as a separate row, so A does not reopen Q6. Only a failed primary (assertion failure, E0832) outranks a later assertion." Concern: "Armed-path cleanup panic gives `passed` + E0824 while cleanup assertion gives `failed`, so authors must know that `panic(\"\")` and `assert(false)` differ in cleanup; the spec needs one sentence defining \"cleanup fault\" as panic only, and must not adopt the \"assertion counts as a cleanup panic\" wording."
  - **DevOps:** A — Reasoning: "CI dashboards, agents and editor test panels read `status`. A `passed` record with a failed check inside shows green, and the warning line sits under it where nobody looks. A caught expected panic is the test's success, not a failure to keep, so the cleanup assertion is the first failure and should carry the full span, message and introspection in a normal failure block. Q6 voted on a cleanup panic, a fault in the cleanup; an assertion is a check the author wrote, and §4.7.2 lists it as its own row." Concern: "Armed-path cleanup panic gives `passed` + E0824 while armed-path cleanup assertion gives `failed`, so authors and tools must learn two outcomes for what looks like one situation."
  - **AI/ML:** A — Reasoning: "A model that writes `assert(self.released)` in `close()` expects a red test when the check fails. Option B gives `passed`, and agents and CI read `status`, not warning lines. Q6 voted on a cleanup panic; an assertion is a separate row in the §4.7.2 table. A also gives one rule (\"is a failure already held?\") that a model can derive from the spec alone." Concern: "B-side seats are right that the armed path now differs from a cleanup panic, so a reader may ask why `assert(false)` and `panic(\"\")` in `close()` give different statuses."
  - **Minimalism:** A — Reasoning: "In B1 I held B and said I would move if the panel treated a green test with a failed check as a defect. Five seats now do, and sys and devops dropped their \"armed expected panic is a cause\" reading. Rule A needs one question (\"does the unwind already carry a failure?\") and no special case per path. It also removes the one row where a failed check ends as `passed`. Q6 voted on a cleanup panic, so A does not reopen it." Concern: "The runtime must tell a held failure from a caught expected panic, and a wrong flag test in `__blink_test_fail_unless_first` brings back either a lost failure or a false green."

- **Q2: `skip()` unwind (q3, q9) and `skip()` in a `for_each` case (q14)** (6-0)
  - Option A: `failed`; the cleanup assertion is the payload; the skip reason is dropped; q14 is already right.
  - Option B: `skipped`; the cleanup assertion is an E0824 entry; q14 changes. DevOps withdrew B in Phase B, so B drew no vote.
  - **Systems:** A — Reasoning: "`skip()` holds no result, so it cannot outrank a failed assertion. `skipped` with a warning reads as \"not run\" and hides a broken check. q14 is already right, so A gives one rule for q3, q9 and q14 with no runtime change on the `for_each` path." Concern: "The skip reason is lost when the record becomes `failed`, so an author sees only the cleanup assertion."
  - **Web/Scripting:** A — Reasoning: "`skipped` reads as \"not run\" in every CI. A skip that hides a failed check is the worst result, and q14 already gives `failed`. One rule for q3, q9 and q14 is easy to learn. The skip reason is lost, which costs little next to a hidden failure." Concern: "A dev who skips on purpose gets a red test and no skip reason, and may not see why until they read the failure block."
  - **PLT:** A — Reasoning: "`skipped` means no verdict. A failed assertion is a verdict, so `skipped` plus a lost or warned-only assertion is unsound. A also makes q3, q9 and q14 one rule, and q14 needs no change. The join `passed < skipped < failed` gives `failed` here." Concern: "The skip reason is dropped from the record, so a user who skips on purpose sees only the cleanup failure; the runtime fix must not lose q14's behaviour."
  - **DevOps:** A — Reasoning: "`skipped` reads as \"not run\" in every CI consumer, so a failed check hidden behind it is the worst diagnostic result. I withdraw my Phase A position: q14 is right, and one rule must cover q3, q9 and q14. The skip reason is lost, which costs little because the failure outranks it." Concern: "A test author who calls `skip()` sees `failed` with a payload from `close()` and no mention of the skip, which could confuse them unless the failure block names the unwind path."
  - **AI/ML:** A — Reasoning: "`skipped` reads as \"not run\" in CI. It must not hide a failed check. A keeps q14 as it is, so q3, q9 and q14 follow one rule with no special case for `for_each`. The skip reason is less urgent than a failure." Concern: "The author loses the skip reason when the cleanup assertion fails, so a deliberate skip can show as a failure."
  - **Minimalism:** A — Reasoning: "`skip()` holds no result, so the same one-question rule gives `failed`, and q14 already works that way. Option B needs q14 to change and needs a skip-only exception. That adds a rule and removes none. A `skipped` record that hides a failed check reads as \"not run\" in CI." Concern: "A dropped skip reason may confuse an author who sees `failed` with no trace of the skip, so the failure block should be clear that the assertion ran in cleanup."

- **Q3: E0824 entry shape** (6-0)
  - Option A: unchanged: `code` and `message`.
  - Option B: add optional `kind` (`"panic"` | `"assertion"`) and `location` (`"file:line"`). DevOps withdrew B in Phase B, so B drew no vote.
  - **Systems:** A — Reasoning: "The message prefix (`assertion failed:`, `ASSERT_EQ FAILED:`) already tells assertion entries from panic entries. Under Q1=A an assertion entry appears only after a failing primary, where the failure block holds the detail. Two more JSON fields cost every consumer a parse path for no gain; a field can be added later without breaking old readers." Concern: "A consumer that must tell a panic entry from an assertion entry has to parse the message text."
  - **Web/Scripting:** A — Reasoning: "After Q1=A, an E0824 entry for an assertion appears only after a failing primary, and the failure block already holds the detail. Two more fields add one more thing for every consumer to learn. The message carries the full assertion text, so the warning is useful alone." Concern: "If B wins, tools that parse the entry will want `kind` later, and it will arrive as a second additive change."
  - **PLT:** A — Reasoning: "Under A of Q1, an assertion entry appears only after a failed primary, where the failure block already carries span and detail. The message prefix already tells assertion from panic. Added fields are surface for every consumer with no decision they enable; an optional field can be added later without breakage." Concern: "A consumer that wants to separate assertion entries from panic entries must parse the message prefix."
  - **DevOps:** A — Reasoning: "With Q1 = A, an E0824 entry for an assertion appears only after a failing primary, and the failure block already shows the detail. The message prefix (`assertion failed:`, `ASSERT_EQ FAILED:`) tells the cases apart. I withdraw `kind` and `location`. A later additive field stays possible, and old consumers would ignore it." Concern: "The runtime must put the full assertion text (user message and span as one string) in the message, or the warning stays too thin to act on, and the spec does not force that."
  - **AI/ML:** A — Reasoning: "`kind` and `location` add two fields and one more decision for every consumer. The message prefix (`assertion failed:`, `ASSERT_EQ FAILED:`) already separates the cases. Under Q1=A, an assertion entry appears only after a failing primary, whose failure block carries the detail. An additive field stays possible later." Concern: "A tool that wants to separate cleanup panics from cleanup assertions must parse the message prefix."
  - **Minimalism:** A — Reasoning: "No new field. Under Q1 = A, an entry for an assertion appears only after a failing primary, and the message prefix (`assertion failed:`, `ASSERT_EQ FAILED:`) already names the case. A later additive field stays possible if a consumer needs one." Concern: "A consumer that wants to count assertion entries separately from panic entries must parse the message text."

- **Q4: ERROR_CATALOG E0824 row text** (6-0; code and name stay)
  - Option A: "`exit(false)`/`close()` panicked, or failed an assertion after an earlier failure".
  - Option B: "panicked or failed an assertion", with the same words in §4.7.2 and §8.10. B drew no Phase C vote.
  - **Systems:** A — Reasoning: "E0824 must describe every case that emits it. A says \"after an earlier failure\", which matches Q1=A exactly; B (\"panicked or failed an assertion\") would imply any cleanup assertion becomes an entry, which is false under Q1=A. Code and name stay." Concern: "The row text is longer and must be kept in step with §4.7.2 and §8.10 by hand."
  - **Web/Scripting:** A — Reasoning: "The row must name the cases that raise E0824, and \"after an earlier failure\" tells the reader where a later cleanup assertion goes. This matches my B1 position for Q1=A. Code and name stay." Concern: "B is shorter, but under Q1=A it says too much: it implies an assertion in cleanup is always a warning."
  - **PLT:** A — Reasoning: "The row must describe every case that emits E0824. Under Q1 = A, an assertion emits it only after an earlier failure, and \"panicked, or failed an assertion after an earlier failure\" says exactly that. B (\"panicked or failed an assertion\") would imply every cleanup assertion is a warning, which contradicts Q1 = A. I withdraw my earlier \"row unchanged\"." Concern: "If Q1 goes to B, row text A is false, so the writer must tie Q4 to the Q1 result."
  - **DevOps:** A — Reasoning: "The row must name the cases that emit the code, and users look up the catalog from the warning line. Under Q1 = A the assertion case emits E0824 only after an earlier failure, so \"panicked, or failed an assertion after an earlier failure\" is accurate. B's \"panicked or failed an assertion\" would tell a reader that any cleanup assertion gives a warning, which is false." Concern: "The human line still says \"cleanup panicked during unwind\" for an assertion entry, so the line and the row use different words."
  - **AI/ML:** A — Reasoning: "The catalog row must say which cases raise E0824. A model reads the row to learn this, and \"panicked\" alone leaves a later cleanup assertion without a home. A's text states the \"after an earlier failure\" condition, which matches the Q1=A rule. B's shorter text is correct only if Q1=B." Concern: "\"after an earlier failure\" is easy to read as \"after any earlier problem\", so a reader may expect an E0824 entry after a caught expected panic."
  - **Minimalism:** A — Reasoning: "My B1 wanted the shortest text, \"panicked or failed an assertion\". That text is only honest if an assertion always raises E0824. Under Q1 = A it raises E0824 only after an earlier failure, so the short text is false. The row must say \"after an earlier failure\". If Q1 goes to B, I vote B here." Concern: "A longer row text must be copied the same in §4.7.2 and §8.10, or the three places drift."

- **Q5: Where the skip rule is stated** (5-1, Minimalism dissent)
  - Option A: one sentence in §2.20 `skip()` (a failed assertion in a cleanup that runs during a `skip()` unwind makes the test `failed`), plus the §4.7.2 edits.
  - Option B: state it once, in §4.7.2 as a note under the table; §2.20 gets at most a cross-reference, not new rule text.
  - **Systems:** A — Reasoning: "A reader looks in §2.20 for what `skip()` does, and the skip rule changes the visible result of `skip()`. One sentence there, backed by the §4.7.2 edits, costs little. The rule is one clause; drift risk is small, and a cross-reference only would hide a behaviour change." Concern: "The same rule now appears in two places and can drift when §4.7.2 changes."
  - **Web/Scripting:** A — Reasoning: "A dev reads §2.20 to learn what `skip()` does. They will not look in §4.7.2. One sentence there prevents a surprise. Drift risk is small because the sentence is short and ties to one rule." Concern: "The same rule now sits in two places, and an edit to §4.7.2 may leave §2.20 stale."
  - **PLT:** A — Reasoning: "A reader asks §2.20 what `skip()` does and will not look under the §4.7.2 table. One sentence there, tied to the §4.7.2 rule, is the cost of a discoverable spec. Drift risk is real but small for a single sentence that cites §4.7.2 as the rule's home." Concern: "Two places state the rule, so a later edit to one can leave the other stale."
  - **DevOps:** A — Reasoning: "Users and LLMs look up skip behaviour under `skip()` in §2.20, not in an effects section. One sentence there, next to the §4.7.2 edits, puts the answer where the question is asked. Drift risk is real but small for one sentence; the rule can also point to §4.7.2." Concern: "If the §4.7.2 rule changes later, the §2.20 sentence can go stale, and a writer should add a cross-reference between the two."
  - **AI/ML:** A — Reasoning: "An LLM looks in §2.20 for what `skip()` does. It will not look in §4.7.2 for it. One sentence there costs few tokens and prevents a wrong guess. The §4.7.2 note stays the source of the full rule." Concern: "The two places can drift, as min says, if a later edit changes only one."
  - **Minimalism:** *(dissent)* B — Reasoning: "I hold B1. A rule stated in two places drifts, and the §4.7.2 note under the table is the one place that defines every row. A cross-reference in §2.20 costs one clause and gives the reader of `skip()` a pointer, with no second statement of the rule." Concern: "aiml is right that an LLM reads §2.20 for skip behaviour; with only a pointer there, a model may skip the follow and miss the rule."

#### Phase D — Round 2

Phase D did not run. No question went below 5-1.

### Reading gaps

- Q6 of the Panicked Status Reporting decision voted on a "cleanup panic during an armed `assert_panics` unwind". It did not name a failed assertion. The §4.7.2 table lists assertion failure and panic as separate rows. The panel read Q6 as a rule about panics only, and wrote "cleanup fault" as panic only. Minimalism held the other reading (Q6 covers the assertion) in Phase B and moved in Phase C.
- No text in `sections/` said whether an assertion failure in `exit(false)`/`close()` is a "cleanup panic". §2.20 and some decision files call an assertion failure an "assertion failure panic" in places.
- The §4.7.2 table lists an assertion failure as a catchable-unwind path. The probe of a plain test body (an assertion failure inside `with`, no `for_each`) showed that `close` does not run. A separate implementation ticket covers it. This decision does not rule on it.
- The `for_each` parent-record ruling was awaiting sign-off when the panel met. The panel did not rely on it.
- The opt-in "fail a test on E0824 cleanup warnings" runner option stays valid for cleanup panics. This decision does not change it.
- Two concerns carry to the writer: the human line says "cleanup panicked during unwind" for an assertion entry (DevOps), and the failure block should make clear that the assertion ran in a cleanup (DevOps, Minimalism). The spec fixes neither. DevOps also noted that the ruling did not force the runtime to put the full assertion text in the message; §4.7.2 and §8.10 now say that the message holds it.

### Final Spec

```blink
import std.testing

type Lease { held: Bool }

impl Closeable for Lease {
    fn close(self) {
        assert(!self.held, "lease still held")
    }
}

test "close fails after an expected panic" {
    assert_panics(matching: "boom") {
        with Lease { held: true } as _l {
            panic("boom")
        }
    }
    // failed: payload "lease still held"; no E0824 entry
}

test "close fails after a skip" {
    with Lease { held: true } as _l {
        testing.skip("later")
    }
    // failed: payload "lease still held"; the skip reason is dropped
}
```

- A failed `assert`, `assert_eq`, `assert_ne` or `assert_matches` in `exit(false)`/`close()` is the test's first failure, unless the unwind already carries a failure (an assertion failure or an E0832 mismatch).
- An expected panic that `assert_panics` catches, and `skip()`, are not failures. An armed unwind whose `matching:` holds, and a `skip()` unwind, give `failed` with the cleanup assertion as the payload and no E0824 entry. `?`, `return` and normal completion give `failed`.
- After a failure, the first failure stays the result and the later cleanup assertion is an E0824 entry. An E0832 mismatch stays the result and the cleanup assertion is an E0824 entry.
- A cleanup panic keeps the decided behaviour. "Cleanup fault" means a panic only. The spec does not say that an assertion counts as a cleanup panic.
- E0824 keeps its code, name and entry shape (`code`, `message`). The message carries the full assertion text. The catalog row reads "`exit(false)`/`close()` panicked, or failed an assertion after an earlier failure, during catchable unwind; original cause preserved, cleanup surfaces as warning".
- §4.7.2 gets the rule, a note under the catchable-unwind table, and a sentence in *Replace errors*. §8.10 *Cleanup warnings* says an assertion entry exists only after an earlier failure. §2.20 `skip()` gets one sentence that cites §4.7.2.
