[< All Decisions](../DECISIONS.md)

# Skipped `test.failing` Records — Design Rationale

The §8.10.6 field table says `expected_fail` is "`true` iff the test was registered with `test.failing`". The runtime (`bootstrap/runtime_test.h`) did not print `expected_fail` or `xfail_reason` on a record with `status: "skipped"`: the skipped branch printed neither key, while the passed and failed branches printed both. A `test.failing` body that calls `skip()` therefore gave a record that broke the table:

```blink
test.failing("skips inside", reason: "not yet") {
  skip("env gate")
}
```

The [unexpected-pass rule panel](xfail-unexpected-pass-rule.md) (Q7, 6-0) sent this question to its own ticket. Its new suite rule reads only `status`, so it holds whichever side changes.

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated
in independent-proposal → debate → vote rounds.

Facts the moderator gave the panel from the codebase:

- The inversion runs only when `expected_fail && !skipped`. The skipped branch prints `reason` (the skip reason), `duration_ms`, `tags`, `cleanup_warnings` and `cases`, and neither `expected_fail` nor `xfail_reason`.
- `scripts/corpus_one.sh` counts known failures with `select(.expected_fail == true and .status == "passed")`. Its comment says a skipped `test.failing` row "does not carry expected_fail in the report, so it is not counted."
- `for_each`: a parent test is `skipped` only when every case is skipped.

#### Phase A — Independent proposals

Five panelists proposed C (both fields on every record of a `test.failing` test, `skipped` included, with a runtime fix). Minimalism proposed B made tighter (neither field on a skipped record, spec edit only).

- **Systems:** "I recommend C+ (keep the table, make it exact, print both xfail fields on skipped records)." "The flag is a static property of the registration. It sits in `tests[i].expected_fail` at compile time. To print it on every record costs one predictable branch and about 20 bytes per skipped xfail record." "B keeps today's runtime, but it puts runtime behavior into the spec. The runtime is the bug: the skipped branch is a copy of the passed branch that lost the two lines."
- **Web/Scripting:** "I back C, keep the table. expected_fail + xfail_reason go on every record of a test.failing test, skipped records included." "A JS/Python dev reads "true iff registered with test.failing" and believes it. Then their `jq 'select(.expected_fail)'` misses a test they marked `test.failing`." "C keeps the rule anyone guesses first: you marked it, so the record says so."
- **PLT:** "Recommendation: C, stated as a rule rather than only as a table row." "The table defines `expected_fail` as "`true` iff registered with `test.failing`". That is a header fact. Option B turns it into an outcome fact that means "inversion ran"." "Under C, the rule is total: the key is present (and `true`) exactly when the registration is `test.failing`." Proposed: "A record with `expected_fail: true` and `status: "skipped"` did not show red or green. It is neither a known failure nor an unexpected pass."
- **DevOps:** "a refined form of option C." "A dashboard that tracks how many `test.failing` registrations exist, how old their reasons are, and whether the count goes down has to see every registration. Under B, a test that skips on CI (an env gate, a missing platform) drops out of that inventory, which then reads low." "`scripts/corpus_one.sh` selects `.expected_fail == true and .status == "passed"`, and its `status` filter already excludes skipped rows. Under C+ the count stays the same."
- **AI/ML:** "Recommendation: C, with `xfail_reason` included." "Under B, the field depends on both how the test was registered and what status it had, which is a second decision point. Models often drop that kind of side condition when they write consumers."
- **Minimalism:** "Recommendation: B, made tighter. Change only the spec text. Do not change the runtime." "The spec already ties `expected_fail` to the outcome. It is "never true on a `panicked` record", and "an unexpected pass is the only record with `expected_fail: true` and `status: "failed"`"." "A skip did not run, so it is not a known red." ""How many test.failing registrations exist?" is a source question."

Mechanical dedupe gave two options (B-tight, C) and five wording variations: the `expected_fail` row (V1), where the `xfail_reason` presence rule goes (V2), the sentence on a skipped record (V3), human-readable output (V4) and `for_each` (V5).

#### Phase B — Debate highlights

All six sent "stable, ready to vote" after round 1.

- **Minimalism** moved from B-tight to C: "PLT's header/outcome argument beats my strongest point. I said "never true on panicked" shows the spec already ties the field to the outcome. It does not. That rule holds structurally, because inversion maps every panic to "passed". It is not a carve-out keyed on status." "My "source question" point also fails for env-gated skips. "Which known reds skip on this CI box" is a run question, and rg cannot answer it."
- **PLT:** "The "only record" rule reads the pair (expected_fail, status). Under C it partitions exactly: passed = expected red, failed = unexpected pass, skipped = no verdict." "B makes presence a function of (registration, status) and takes away the one total field consumers can join on."
- **Systems** withdrew a Phase A claim: "PLT and Minimalism are right about TAP. Each line carries one directive, `# SKIP` or `# TODO`. I withdraw the claim that TAP supports C." **DevOps:** "Panelists disagree on what TAP allows, so TAP decides nothing here. Drop it from the rationale."
- **Web** and **AI/ML** withdrew "a known red that did not run this time". AI/ML: "One point from Minimalism I accept: a skipped xfail is not a "known red". My Phase A wording said so; I withdraw it."
- **Minimalism** on the variations: "V4: no normative human-output text. The spec should not fix that format here." "V5: the parent rule already follows from "every record of a test.failing test", so add no parent note. Because "every record" could be read to cover cases[] entries, I accept one short clause in the same sentence: "not on its `cases` entries"."

#### Phase C — Silent vote

- **Q1: what a skipped `test.failing` record carries** (6-0, C)
  - **Systems:** "Under C the key's presence depends on one input, the registration. B-tight adds the status as a second input, and every consumer must re-derive it. The skipped branch lost two lines that the other two branches have, so the runtime has the bug, not the spec."
  - **Web/Scripting:** "you marked it test.failing, so the record says so. That is the rule a JS or Python dev guesses without reading the doc."
  - **PLT:** "The registration is known before the run, so it belongs with the facts that do not depend on the outcome. Under C the key is present exactly when the test is test.failing, and `status` alone says what happened."
  - **DevOps:** "a dashboard that reads stored reports must see every `test.failing` registration. It has no source tree to search."
  - **AI/ML:** "one presence condition (the registration) is easier for a model to learn from the spec than the registration times a status subset."
  - **Minimalism:** "The field describes the registration, so one rule covers every record." "C keeps settled text and fixes a printer branch that someone forgot. B rewrites the spec to describe that bug."
- **Q2: where the `xfail_reason` presence rule goes** (5-1, Q2a: in the `xfail_reason` row; Systems dissent)
  - **Web/Scripting:** "people look in the table row first. A rule after the table is easy to skim past."
  - **PLT:** "the presence rule for `xfail_reason` belongs on its own row, defined in terms of `expected_fail`."
  - **DevOps:** "a presence rule belongs in the field's own row. A schema reader or a generated TypeScript type looks there first."
  - **AI/ML:** "Keying `xfail_reason` to `expected_fail` puts the fact in one place, so two copies cannot drift apart."
  - **Minimalism:** "One clause in the row that it governs, and no new rule block."
  - **Systems:** *(dissent, Q2b: one sentence after the table)* "One sentence states the presence rule for both fields at once. A reader then finds the whole rule in one place and does not have to piece it together from two table cells."
- **Q3: the `expected_fail` table row** (5-1, Q3a: unchanged; AI/ML dissent)
  - **Systems:** "Keeping the row means C changes no settled text, which is the honest frame for this fix."
  - **Web/Scripting:** "the row already says the right thing, and the runtime is what is wrong."
  - **PLT:** ""iff registered" is already a total rule about presence. It is correct, it survived the earlier tiebreak, and rewording it suggests the meaning changed when it did not."
  - **DevOps:** "the row is already correct. The runtime was the part that was wrong."
  - **Minimalism:** "The row is already correct. The smallest change is no change."
  - **AI/ML:** *(dissent, Q3b: reword the row)* ""true iff registered" does not say whether a plain `test` record has the key absent or set to `false`. A model writing a TypeScript type or a jq filter must guess, and Q3b removes that guess."
- **Q4: the sentence on a skipped record** (4-2 for Q4b, PLT's added sentence; DevOps and Minimalism for Q4a, no added sentence → Phase D)
  - **Systems:** "The added sentence tells a consumer that this pair (`expected_fail: true`, `skipped`) gives no verdict." Concern: "Q4b uses "known failure" while the rest of the section says "expected red"."
  - **DevOps:** *(Q4a)* Concern: "if Q4b wins, consumers may read "neither a known failure" as "exclude from the known-red inventory", which is the opposite of why we chose C."
  - **Minimalism:** *(Q4a)* ""Neither a known failure nor an unexpected pass" already follows from the suite rule and the "only record" invariant. Saying a fact twice gives two texts to keep in step."
- **Q5: human-readable output** (5-1, Q5b: informative note; Minimalism dissent)
  - **Systems:** "The text view and the JSON view should report the same facts." Concern: "The spec should label it as an example only, and no tool should parse human output."
  - **Web/Scripting:** "if the JSON says test.failing and the terminal says only SKIP, a human reading the log sees less than a machine does." "I prefer `[test.failing: not yet]`, because it repeats the user's source word, and "xfail" is pytest jargon."
  - **PLT:** "the text output and the JSON output should agree, and an informative note costs nothing normative."
  - **DevOps:** "A person scanning a CI log who sees only "skipped" forgets that the test is a known red." Concern: "The text must say the format is not stable."
  - **AI/ML:** "humans and models both scan text logs."
  - **Minimalism:** *(dissent, Q5a: nothing in the spec)* "A non-normative note about a string that the chore will pick anyway adds spec surface with no rule behind it."
- **Q6: `for_each`** (5-1, Q6b: the full line; Minimalism dissent)
  - **Systems:** "One line stops tools and models from putting the field on each case, and it states the parent rule for the all-cases-skipped parent. That parent is the `for_each` form of this exact bug."
  - **Web/Scripting:** "That case is exactly where people add fields to the wrong level."
  - **PLT:** "the fields belong to the test (the header), not to each case."
  - **DevOps:** "One explicit line stops `jq` queries that search `cases[]` and find nothing."
  - **AI/ML:** "whether `cases` entries carry the fields is a decision point that models will guess at if the spec does not say."
  - **Minimalism:** *(dissent, Q6a: one clause)* "The parent rule follows from "every record of a `test.failing` test". The only real ambiguity is whether `cases` entries count as records, and one clause settles that."

#### Phase D — Round 2 (Q4)

In the focused debate all six backed an added sentence that uses the section's term "expected red" and puts the "neither" on the run, not on the test.

- **DevOps:** "I accept Systems' and PLT's point. A consumer that counts known reds needs to be told that the (`expected_fail: true`, `skipped`) pair gives no verdict." "The sentence should talk about this run's result, not about the test."
- **Minimalism:** "Systems' point decides it for me. Under C, the only new consumer bug is counting a skipped xfail as an expected red, and the extra sentence blocks that bug directly. My "derived fact" argument is weaker than I made it." "I withdraw my objection."
- **PLT:** "DevOps' concern is correct. "Neither a known failure" can be read as "drop it from the known-red inventory", which is the opposite of why we chose C. The fix is to separate the two things: the run gave no verdict, but the registration stands."

Six wordings went to a silent vote. Each starts "A skipped `test.failing` test keeps `expected_fail: true` and `xfail_reason`. It has no `xfail_observed`." and adds:

- **D1** [Minimalism]: "The record is neither an expected red nor an unexpected pass."
- **D2** [Systems]: "The run gave no result for it: the record is neither an expected red nor an unexpected pass."
- **D3** [DevOps]: "The run gave no result: the record is neither an expected red nor an unexpected pass."
- **D4** [Web]: "This run gave no result, so the record is neither an expected red nor an unexpected pass."
- **D5** [AI/ML]: "The test did not run to a result, so the record is neither an expected red nor an unexpected pass."
- **D6** [PLT]: D5 plus "It is still a `test.failing` test."

- **Q4 (round 2)** (6-0 for an added sentence; wording D3 by plurality 3-2-1, and first in every two-way comparison from the ranked lists: 4-2 over D6, 5-1 over D1)
  - **Systems:** D3 — "It puts "no result" on the run and "neither" on the record, so the test itself stays in any inventory of `test.failing` registrations." ""The test did not run" (D5, D6) is less exact: a body can do real work before it calls `skip`, so the test did run, just not to a result."
  - **PLT:** D3 — "I am moving off my own D6." ""The run gave no result" puts the no-result fact on the run, not on the test. That answers the inventory concern without D6's extra sentence."
  - **DevOps:** D3 — "D3 uses the section's term "expected red" and adds the fewest words that still block the misreading."
  - **Web/Scripting:** *(D6)* "That last sentence closes DevOps' inventory concern in plain words, so no reader takes "neither an expected red" to mean "drop it from the count"."
  - **AI/ML:** *(D6)* "D6 guards against both wrong readings a model can take from the record."
  - **Minimalism:** *(D1)* "The prefix that the others add ("the run gave no result") gives a reason that `status: "skipped"` already states on the record. D1 is the shortest text that blocks the consumer bug Systems named."

The user signed off on the tally, Q4 wording D3 included.

### AI-First Review

5/5 pass. Learnability and generability: the key's presence depends on one input, the registration. Consistency: no new field, status or cause; every earlier invariant holds. Debuggability: the record states both the registration and the outcome. Token efficiency: two keys on a skipped record, no new consumer pattern ("test the pair" still counts expected reds).

### Final Spec

```json
{ "name": "skips inside",
  "status": "skipped",
  "reason": "env gate",
  "expected_fail": true,
  "xfail_reason": "not yet" }
```

- `expected_fail` and `xfail_reason` appear on every record of a `test.failing` test, whatever its `status`, and on no other record. The `expected_fail` row is unchanged; the `xfail_reason` row adds "It appears exactly when `expected_fail` appears."
- A skipped `test.failing` record has no `xfail_observed`. It is neither an expected red nor an unexpected pass.
- `cases` entries never carry either field. The parent record carries them whatever its status.
- The human output may mark a skipped `test.failing` test. The marker is not specified and not stable.
- No new field, status or cause value. The suite rule still reads only `status`.
- The runtime fix (print both fields on the skipped branch through one helper shared by all three branches, a corpus test of the record keys, and the stale comment in `scripts/corpus_one.sh`) is implementation work.
