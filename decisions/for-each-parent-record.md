[< All Decisions](../DECISIONS.md)

# The Parent Record of a `for_each` Test — Design Rationale

§8.10.2 said the parent status of a `for_each` test is the most severe case status (`panicked > failed > passed`,
`skipped` only if every case skips). It did not say which case's `message`, `span`, `cause` and cause fields the parent
carries when two or more cases differ, nor which `reason` an all-skipped parent carries. It did not define a parent
`case` field, although the runtime writes one on `failed` and `panicked` parents. It said nothing on a `for_each`
inside a case, on a panic after the loop, on `assert_panics` around a `for_each` whose case panics, or on the human
output. A `failed` entry in `cases` held only `label` and `status`.

## Summary

| Q | Question | Result | Vote |
|---|---|---|---|
| Q1 | The parent `case` field | A: on `failed` and `panicked` parents only; absent on `passed`, on `skipped` and when body code supplied the outcome | 3-3 after Phase D (A: sys, devops, min; B: web, plt, aiml); BDFL broke the tie for A |
| Q2 | Nested `for_each` | B: the label of an inner case is the `/`-joined path, an opaque display key; the outer case also gets its own row | 6-0 in Phase D after B3 C2 A1 in Phase C |
| Q3 | `reason` on skipped `cases` entries | A: a skipped entry carries its own `reason` | 5-1 (min dissent: B) |
| Q4 | Full payload on `failed` `cases` entries | A: a failed entry carries `message`, `span`, `cause` and its cause-specific fields | 4-2 (sys, min dissent: B); Phase C and D the same |
| Q5 | Human output | A: the spec says only that the human output names the case label of the outcome it prints | 6-0 in Phase D after A3 B2 C1 in Phase C |
| Q6 | `assert_panics` around a `for_each` whose case panics | A: one sentence in observable terms; a case records its own panic, an enclosing `assert_panics` does not consume it, the parent is `panicked` | 5-1 (min dissent: B) |

Agreed by all six seats and not balloted: no language change; the outcomes of a test are its cases plus the body's own
outcome (code outside any case); the parent status is the most severe outcome; within the top tier the first outcome
in execution order wins, and the parent takes every payload field from that one outcome; an all-skipped parent's
`reason` is the first skipped case's reason; a panic in plain code after a failed case makes the parent `panicked`
(the runtime is wrong today); `assert_panics` around a `for_each` whose case panics gives a `panicked` parent; an empty
case list passes, and `skipped` needs at least one case; no spec text claims an E0831 outcome for that last shape.

AI-First: 5/5 pass (a schema rule, no syntax; Q1 either way is one sentence).

### Follow-ups the panel named (not in this decision)

- A cap on the failing payloads a runner retains. Every concern on Q4, winners included, names the memory of a large
  all-failing table. A cap needs its own spec text.
- Whether the runtime also reports E0831 for `assert_panics` around a `for_each` whose case panics (web, Phase B).
- Runtime work to match the spec: a post-loop panic after a failed case wins; `/`-path labels and an outer row for
  nested cases; the full payload on failed entries; `reason` on skipped entries; an empty list passes.

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in
independent-proposal, debate, vote rounds, then a focused second vote on the four contested questions. Phase A and
Phase B are excerpts from each panelist's own text, cut with "…". Phases C and D are quoted in full from each
panelist's file, without its heading line. Probe names (p1 to p9) are the nine fixture packages the panel ran under
the compiler: p1 the MVCE (cases a, b, c with `assert(v == 1)`), p2 a failed case then a panicking case, p3 every case
skipped, p4 a nested `for_each`, p5 a panic after the loop after a failed case, p6 `assert_panics` around a
`for_each` whose case panics, p7 a skipped, a failed and a passed case, p8 and p9 an assertion after the loop after a
failed case.

#### Phase A — Independent proposals

- **Systems:**

> ## sys-1: one slot, severity-ranked, first-in-tier wins; test code competes too

> The runner keeps one reported-outcome slot per test. Outcomes come from cases and from test code outside any case. An outcome replaces the slot only when strictly more severe (`panicked > failed`). Equal severity keeps the earlier one. `skipped` never takes the slot. The parent record copies the slot.

> **Nesting.** A `for_each` inside a `for_each` body panics: `for_each: nested call`, as with E0834. One slot and a flat `cases[]` cannot hold a label path. Users flatten with computed labels. Fallback: flat rows in completion order, `case` names the outermost label.

> **Systems cost.** O(1) memory, one label copy per strict upgrade, no allocation on the passing path, and output is a pure function of execution order. A list of all failures in the parent grows with a 10k-case table; `cases[]` already holds every row.

> ## sys-2 (alternative): no `case` field
> Same table minus `case`. A consumer finds the first `cases[]` entry whose status equals the parent status. Saves a field, but every consumer must reimplement the scan rule. I prefer sys-1.

- **Web/Scripting:**

> ## web-1: one representative outcome; most severe wins, first wins within a tier

> The parent record copies ONE outcome, never a mix. Outcomes are the cases plus the test body's own failure or panic (code outside every case, such as code after the loop). The representative is the first outcome, in execution order, of the most severe tier (`panicked > failed`). The parent takes `status`, `message`, `span` and every cause-specific field (`cause`, `assertion`, `expected`, `actual`, `introspection`, `omitted`, `error`) from it. This keeps §8.10: `message` and `span` are the outcome's text and place.

> **Nested `for_each`.** The label is the `/`-joined path, `outer1/inner2` (Go `t.Run` form). `cases[]` stays flat, one entry per case at every level, written when the case ends. The parent's `case` is the path of the first entry in the representative tier (p4 gives `outer1/inner2`). A `/` in a label is allowed; nobody parses the path.

> **Human output.** One line per failing or panicking case, each with its own message and span, so a dev fixes every broken row in one run (pytest and Jest do this)

> ## web-2: leave it unspecified (fallback)
> Say only "a representative outcome; `cases[]` is authoritative". Cheap, but two runtimes would show different rows and CI scripts could not rely on `case`. I oppose it.

- **PLT:**

> ## plt-1: the parent record is a fold over outcomes, with one representative outcome

> The **representative outcome** is the first outcome, in execution order, that has the parent's status. The parent record takes ALL its outcome fields (`message`, `span`, `cause`, `assertion`, `expected`, `actual`, `error`, `reason`) from the representative, and only from it. A record never mixes fields from two outcomes: `span` is where the outcome fired, `message` is its text (§8.10 line "one meaning on every status").

> **`case` field.** Add one optional parent field, `case`: the label of the representative's case. It is present on a `failed` or `panicked` parent only when the representative is a case, and absent when the representative is body code (no case owns it). It is absent on `skipped` (a skip has no single owner). The runtime already behaves this way, so this documents it.

> **Tradeoffs (soundness).** The fold is a total, associative, order-stable choice (max with first-wins), so it is deterministic and composes with nesting. "First failing, ignore severity" is unsound against Q5: a later panic would be hidden. "Most severe fields from different outcomes" breaks Q2.

- **DevOps/Tooling:**

> ## devops-1: one carried outcome, most severe first, labelled by a `case` field

> **Rule.** The parent record reports one outcome: the most severe outcome in the test (`panicked > failed > passed`). Within a tier the first outcome in time wins. The candidates are the case outcomes and the outcome of the body's own code outside any case. The parent takes `status`, `message`, `span`, `cause` and the cause fields from that one outcome. It never mixes fields from two outcomes.

> **`case` field (record schema addition).** A `failed` or `panicked` parent carries `case`, the label of the case whose outcome it carries. If the body's own code supplied the outcome, `case` is absent. `passed` and `skipped` records never carry it. The runtime already emits it. The spec needs it because a `failed` entry in `cases[]` holds only `label` and `status`, so `case` is the only link from the parent's assertion to a table row.

> - Nested `for_each` (p4): `cases[]` stays flat, in completion order. An inner label is the path joined with `/`, for example `outer1/inner2`. Today `inner1` appears twice with no way to tell the rows apart. The parent has `case: "outer1/inner2"`.
> - `assert_panics` around `for_each` (p6): a case frame records the panic, so the block returns normally and the panic is not consumed. The parent is `panicked`. E0831 would add only a `failed` outcome, which `panicked` outranks. The spec says `assert_panics` cannot consume a case's panic.

> **Skips.** The parent is `skipped` only when the list has at least one case, every case skips, and the body's own code does not fail or panic. An empty list passes. The parent `reason` is the reason of the first skipped case in `cases[]` order. A skipped entry also carries its own `reason`, so none is lost.

- **AI/ML:**

> ## aiml-1: one selection rule, payload on every case entry, `case` names the source

> An AI reads one record and needs three answers without scanning: which outcome the parent reports, which case it came from, and whether any detail was dropped. Today `cases[]` entries for `failed` cases hold only label and status, so a second failing case loses its assertion, `expected`, `actual` and `span`. The parent copies one case and the rest vanish. That is the main accuracy risk: an AI fixes case b, reruns, and finds case c.

> 1. **Case entry = record payload.** Each `cases[]` entry holds `label`, `status`, and the payload a top-level record of that status holds: `cause` and its fields for `failed`; `message` and `span` for `panicked`; `reason` for `skipped`.

> 4. **`"case"` field.** The parent carries `"case": <label>` exactly when its payload came from a case, on every status including `skipped`. It is absent when the payload came from the body, and on `passed`. The schema gets one new optional field; it has one meaning: the `cases[]` entry the parent copied.
> 5. **Nested `for_each` is a panic**: `for_each: nested call inside case "<label>"`. This mirrors E0834 (no nesting for `assert_panics`) and keeps `cases[]` flat with unambiguous labels. Users flatten with a product list. Alternatives (path labels such as `outer/inner`) add a join rule and collide with labels containing `/`.

- **Minimalism:**

> ## min-1: one rule, no new field, no new syntax (recommended)

> The test body is one more outcome source. Treat the parent record as a fold over outcomes: the cases, plus the body's own outcome (code after the loop). No new schema field. No new syntax.

> **The `"case"` field: do not specify it.** The spec has no such field, and the existing sentence already puts the label in the failure message. `cases[]` is the attribution record. A second place for the same fact is surplus, and it has an unclear meaning on `skipped` and on a body outcome that has no case. Runtime may keep emitting it as an extension, but the spec does not promise it. If panel wants it: it must be absent when the winning outcome came from the body.

> - Nested `for_each` (p4): `cases` stays flat, in completion order, each row carries its own label only. Do not add nesting or label prefixes. Spec says nothing more. Nesting is rare; a path-style label is a library convention (`"outer/inner"`), not a schema feature.

> **Tradeoffs.** Cost: a reader sees one failure when several exist; they read `cases[]` for the rest. Gain: zero schema growth; one rule to learn and to test.

#### Phase B — Debate highlights

Each seat read all six Phase A files and the moderator's digest, with the facts it surfaced: probe p6 holds no E0831
text; E0834 is a lexical compile-time rule; §4 names no `for_each` case frame as a catch boundary; `inner1` and `inner2`
each appear twice in the `cases` of p4.

- **Systems:**

> **O1 `case` field: specify it.** One optional Str, present only on a `failed` or `panicked` parent whose outcome came from a case. Absent on `passed`, on `skipped` and when body code supplied the outcome. I concede `skipped`: with four seats against, a skip has no single owner, and aiml's `skipped` variant adds a case with no failure to attribute. min's point that `cases[]` is the attribution record is weak, because a `failed` entry holds only `label` and `status`, so `case` is the only link to the assertion.

> **O4 full payload on every entry: no.** A `failed` payload includes `introspection` and rendered `expected`/`actual`. Keeping them for each failing case in a 10k-case table is unbounded memory held until the test ends.

> **O6 `assert_panics` sentence: add one sentence.** Fact: p6 shows no E0831 text in the record. That is correct under the rule, because `panicked` outranks the E0831 `failed`, and the single slot has no room for the loser.

- **Web/Scripting:**

> **O1 `case` field: specify.** Min's objection (a second place for one fact) is weak: a `failed` entry in `cases[]` holds only `label` and `status`, so `case` is the only link from the parent's assertion to a row (devops). I move on the skipped variation. I now hold aiml's rule: `case` is present exactly when the parent's payload came from a case, so it is also present on a `skipped` parent (the first skipped case owns the `reason`). One rule, no per-status list.

> **O2 nested: path label.** `outer1/inner2`. A nested-call panic (sys, aiml) fails at runtime, and a shared helper that calls `for_each` inside a case would break with no compile error. Repeated flat labels (plt, min) make the parent's `case` ambiguous (p4 has `inner1` twice).

> **O6 `assert_panics` sentence: add it.** I withdraw "E0831 outcome". The p6 record holds no E0831 text, so I do not know what the runtime does there. ... Open for the runtime: is E0831 reported too?

- **PLT:**

> **O1 (`case`): specify. I change one detail.** Rule: `case` is the label of the case that supplied the parent's payload. It is present whenever a case did, on `failed`, `panicked` and `skipped`. ... min-1's objection (a second place for one fact) fails: the label is not in a `failed` entry's payload, and the message does not hold it.

> **O2 (nesting): I change my position to path labels.** A flat row labelled `inner2` twice (p4) makes `case` an ambiguous key into `cases[]`. That breaks O1. The nested call composes under the fold with no extra rule, so a ban (sys-1, aiml-1) adds a restriction that has no soundness reason, and a runtime panic cannot catch a call made through a function.

> **O6: add one sentence, with a correction.** ... Write: "A `for_each` case frame ends a case's panic. `assert_panics` around the call does not see it, and the case records `panicked`." The sentence also names the case frame as a runner-owned catch boundary, which §4 (~2667) does not list; flag that for the §4 text.

- **DevOps/Tooling:**

> **O1 (`case`).** Specify it, optional, on `failed` and `panicked` only, absent when body code supplied the outcome. I rebut min-1 and sys-2: a consumer would have to rerun a scan rule, and a `failed` entry carries no payload, so the scan finds nothing to compare. On `skipped`: absent (aiml-1 differs). A skipped parent carries `reason`, which has no single owner.

> **O2 (nesting).** I keep the `/` path. Concession to aiml-1: a label that contains `/` can collide, but uniqueness is per call and the path is for display and keys, so a collision is rare and harmless. I oppose a runtime panic for nested calls (sys-1, aiml-1): E0834 is a compile-time lexical rule, and a nested call reached through a helper fn would fail only at run time, in a test that is otherwise correct.

> **O4 (full payload on `cases[]`).** I move from "later" to support it for `failed` and `panicked` entries, as a separate question. Today a CI tool sees a second failure only as a label and `status`. Concern: record size for a large table.

- **AI/ML:**

> **O1 `case` field: specify it.** Concession: absent on `skipped`. Four seats say so, and once skipped entries carry `reason` (O3) the skipped parent has no hidden link to recover. ... Against min-1: the "failure message already has the label" claim is false for assertion records, whose text is the assertion.

> **O2 nested.** ... I vote (a). Fact: E0834 is lexical, so the mirror is by analogy only. The panic is a runtime rule like duplicate labels, one sentence, and nothing in the record is ambiguous. (c) leaves p4's repeated `inner1` rows indistinguishable and breaks the per-call uniqueness a model would assume. (b) is second choice

> **O4 full payload on every entry: keep on the ballot.** It is my main point and only one seat holds it. If it loses, the parent plus `case` still works, but a second failing row has no detail in JSON.

- **Minimalism:**

> **Change of position.** I concede O1. The runtime already emits `case`, and a `failed` entry in `cases[]` holds only `label` and `status` (devops), so without `case` a consumer must re-scan for the matching entry (sys-2). One optional field with one meaning is cheaper than that rule.

> **O3.** I oppose, mildly. A per-entry `reason` is new schema that nobody has asked for. …

#### Phase C — Silent vote

Each seat voted on six questions with the A/B/C options on the ballot. Votes are in the seat's own words.

**Systems**

> **Q1. Parent `"case"` field**
> - **Vote:** A
> - **Reasoning:** The runtime already emits `case` on `failed` and `panicked` parents, and a `failed` entry in `cases[]` holds only `label` and `status`, so `case` is the only cheap link from the parent's payload to a row. Without it every consumer must re-run the scan rule. A skipped parent's `reason` has no single failing owner, so `skipped` stays out and the rule is one short sentence the runtime already follows.
> - **Concern:** B's "one meaning, no per-status list" is neater, but it makes the runtime add a field to `skipped` records, which carries no failure to attribute.
>
> **Q2. Nested `for_each`**
> - **Vote:** C
> - **Reasoning:** One depth counter in the runner is O(1) and allocates nothing. Path labels (B) force a string concatenation per nested case and are ambiguous when a label contains `/`. Flat rows (A) are free but leave `case` an ambiguous key into `cases[]` when `inner1` repeats (p4). The panic keeps one label meaning per call and becomes the outer case's `panicked` outcome. Flat rows are my second choice.
> - **Concern:** A helper that calls `for_each` inside a case fails only at run time, not at compile time, so the check is weaker than E0834.
>
> **Q3. `reason` on skipped `cases[]` entries**
> - **Vote:** A
> - **Reasoning:** The runtime already holds the string, and one string per skipped case is bounded by the case count. It matches `panicked` entries carrying `message`, and it hides no reason behind the parent's first-skip rule.
> - **Concern:** B's "new schema nobody asked for" is a fair point if the schema grows by one field per status without limit.
>
> **Q4. Full payload on `failed` `cases[]` entries**
> - **Vote:** B
> - **Reasoning:** A `failed` payload holds rendered `expected`/`actual` and `introspection`. Keeping that for every failing case in a 10k-case table is unbounded memory held until the test ends, and the cost grows with failures, the case you least want it to. The parent rule already works with one payload; a later ticket can add opt-in detail.
> - **Concern:** A model or CI tool still sees a second failure only as a label and status, so "fix b, rerun, find c" stays real.
>
> **Q5. Human output**
> - **Vote:** A
> - **Reasoning:** The spec should say only that the output names the case label of the outcome it prints. Line form and extra per-case lines are tooling policy and can change without a language revision. C leaves the label unspecified, and B binds every runner to print every case.
> - **Concern:** Two runners may print different numbers of lines, and a user may see one failure per run.
>
> **Q6. `assert_panics` around a `for_each` whose case panics**
> - **Vote:** A
> - **Reasoning:** The case frame ends the panic, so the observable result needs one sentence in observable terms: the case records `panicked`, an enclosing `assert_panics` does not consume it, and the parent is `panicked`. Without it, two runtimes may differ on whether the block sees a panic.
> - **Concern:** The sentence makes the case frame a runner-owned catch boundary that §4 (~2667) does not list, so §4 needs a matching edit.

**Web/Scripting**

> **Q1. Vote: B**
> - Reasoning: A dev reads a record and asks "which case owns this payload?" One rule, "present whenever a case supplied the payload", is learned in one sentence. A per-status list ("failed and panicked, but not skipped") is the kind of exception that makes people open the spec. A skipped parent has a `reason` that came from the first skipped case, so the same link is useful there.
> - Concern: A wins and the field becomes "present on some statuses", so every consumer needs a status check before reading `case`.
>
> **Q2. Vote: B**
> - Reasoning: Go `t.Run` users already know `outer/inner`, and the path keeps `case` a usable key into `cases[]` (p4 has `inner1` twice under flat rows). A nested-call panic would fail at run time, in a shared helper that calls `for_each` inside a case, with no compile error. That is the worst outcome for a dev who did nothing odd. Flat rows are my second choice.
> - Concern: A label that contains `/` can collide with a path, and a dev may try to parse the path.
>
> **Q3. Vote: A**
> - Reasoning: `panicked` entries already carry `message`; a skipped entry carrying `reason` is the same pattern. The string is already held, and the cost is bounded by the case count. A dev who sees "skipped" in a row expects to see why.
> - Concern: None of weight; a case with a long reason string makes rows larger.
>
> **Q4. Vote: A**
> - Reasoning: Without it a dev fixes case b, reruns, and meets case c with no detail in the JSON. That costs a run per failing case. pytest and Jest both show every failing case. With full entries the parent is a copy of one entry, so the rule is one line.
> - Concern: A table with 10k failing cases makes a large record, and the runner holds that memory until the test ends (sys).
>
> **Q5. Vote: B**
> - Reasoning: A terminal user has no `cases[]`, so a parent-only line gives one failure per run. The spec says "every non-passing case is reported" and leaves the line form to tooling. That is the 90% case: fix every broken row in one run.
> - Concern: A choice of A or C means two runtimes can print different things, and CI log scrapers cannot rely on seeing every failing case.
>
> **Q6. Vote: A**
> - Reasoning: Devs will guess both ways on whether `assert_panics` around a `for_each` catches a case's panic. One sentence in observable terms removes the guess and costs nothing. It makes no claim about E0831.
> - Concern: The sentence implies a runner-owned catch boundary that §4 does not list (plt), so the effects section may need a matching edit.

**PLT**

> **Q1. The parent `"case"` field.**
> - **Vote:** B
> - **Reasoning:** The parent takes every payload field from one outcome, so `case` is the key that names that outcome in `cases[]`. A skipped parent's `reason` also comes from one case (the first skipped), so by single-source it needs the same link. One meaning ("the case that supplied the payload") with no per-status exception composes better than a status list. A `failed` entry holds only `label` and `status`, so without `case` a consumer must re-derive the selection rule.
> - **Concern:** Option A leaves `skipped` as the one status whose payload has an owner that the record does not name, and the field's meaning then depends on a status list.
>
> **Q2. Nested `for_each`.**
> - **Vote:** B
> - **Reasoning:** The nested call composes under the fold with no extra rule, so a ban has no soundness reason. A runtime panic also cannot be a static guarantee, because a call made through a helper fn is not lexically visible. Flat rows make the label a non-key: p4 holds `inner1` twice, so the parent's `case` (Q1) would point at an ambiguous row. The path makes the label unique across the whole record.
> - **Concern:** A label that contains `/` can collide with a path, so uniqueness holds only up to that ambiguity; the writer should say the path is a display key and not parsed.
>
> **Q3. `reason` on skipped `cases[]` entries.**
> - **Vote:** A
> - **Reasoning:** A skipped entry then carries its payload like a `panicked` entry carries `message`, so the record loses no outcome that the parent cannot hold. The cost is one bounded string per skipped case, and it needs no new rule.
> - **Concern:** Option B leaves every skip after the first without its reason anywhere in the JSON.
>
> **Q4. Full payload on `failed` `cases[]` entries.**
> - **Vote:** A
> - **Reasoning:** The parent then equals a copy of one entry, so the parent rule is one line, and the "second failure is lost" gap closes without touching the parent. It also makes `case` a true key into complete records. This is the follow-up the sub-tests vote already named.
> - **Concern:** Option A retains rendered `expected`/`actual` for every failing case, so a very large failing table holds memory until the test ends; the runtime may need a cap, and a cap would need its own spec text.
>
> **Q5. Human output.**
> - **Vote:** A
> - **Reasoning:** The spec needs one property: the human output names the case label of the outcome it prints, so a reader can link it to `cases[]`. The line form and per-case lines are presentation, not schema, and the spec should not fix them. Option B's "every non-passing case" also leaves skipped cases undefined (aiml and web differ).
> - **Concern:** Option A lets two runners print only the parent's outcome, and a terminal reader sees one failure per run.
>
> **Q6. `assert_panics` around a `for_each` whose case panics.**
> - **Vote:** A
> - **Reasoning:** The `for_each` case frame ends a case's panic, which is a catch point that §4 does not list. Without one observable sentence, a reader can derive either result (the panic reaches `assert_panics` or it does not). The sentence fixes the behaviour in observable terms only, with no E0831 claim.
> - **Concern:** The sentence makes a runner-owned catch boundary visible in §6 while §4 (~2667) says the user-extensible set of catch boundaries stays empty, so the writer must flag §4 for the same edit.

**DevOps/Tooling**

> **Q1. Parent `"case"` field.**
> - **Vote:** A
> - **Reasoning:** A CI tool reads one parent record and needs the link to a table row. A `failed` entry in `cases[]` holds only `label` and `status`, and the assertion text does not hold the label, so `case` is the only key. A skipped parent has no single owner: its `reason` is one of several, and the runtime already omits `case` there. Option A also documents what the runtime does today, so no consumer breaks.
> - **Concern:** B's single rule ("present whenever a case supplied the payload") is simpler to state, and the A list leaves a consumer with one per-status exception to remember.
>
> **Q2. Nested `for_each`.**
> - **Vote:** B
> - **Reasoning:** The parent `case` and the `cases[]` rows are keys that CI tools and the LSP match on. Flat rows give two rows named `inner1` (p4), so the key is ambiguous. A nested-call panic fires only at run time, in a test that may use a shared helper and be otherwise correct, and the compiler cannot warn about it. The `/` path (Go `t.Run` form) gives unique keys with one join rule.
> - **Concern:** A label that contains `/` can collide with a path, so a tool must treat the path as an opaque key and not parse it.
>
> **Q3. `reason` on skipped `cases[]` entries.**
> - **Vote:** A
> - **Reasoning:** A skipped parent shows only the first reason, so the other skip reasons are lost. A per-entry `reason` costs one bounded string per skipped case and matches `message` on `panicked` entries. Tools that list skips (a dashboard, an LSP test view) need it.
> - **Concern:** It adds schema that no consumer has asked for yet, so the field may sit unused.
>
> **Q4. Full payload on `failed` `cases[]` entries.**
> - **Vote:** A
> - **Reasoning:** The parent shows one failure per run. Without payload on the entry, a second failing case is a label and a status, and the dev must fix b and rerun to see c. The record must then hold all failures for tools to show them. The parent rule stays the same, and the parent equals a copy of one entry.
> - **Concern:** Record size and memory held for a large table (10k failing cases, each with `introspection`), so the runner may need a cap that the spec does not yet define.
>
> **Q5. Human output.**
> - **Vote:** A
> - **Reasoning:** The spec should fix what a reader must learn: the outcome printed and its case label. The line form (`test t::case[b] ... FAIL`) is tooling that changes with terminals and CI log parsers, and the machine contract is the JSON record. Per-case lines are a runner policy that can improve without a spec change.
> - **Concern:** Two runners can print different amounts, so a dev may see one failure on one runner and all failures on another.
>
> **Q6. `assert_panics` around a `for_each` whose case panics.**
> - **Vote:** A
> - **Reasoning:** A dev who wraps a `for_each` in `assert_panics` will expect either result, and tools show a `panicked` parent. One sentence in observable terms removes the guess and does not name E0831, which p6 does not show. It gives the diagnostics a fixed rule to test against.
> - **Concern:** The sentence makes the case frame a runner-owned catch boundary that §4 (~2667) does not list, so the §4 text may now disagree with §8.10.2.

**AI/ML**

> **Q1. Vote: B**
> Reasoning: One rule ("`case` is present whenever a case supplied the parent's payload") has no per-status list to memorise, so a model reading the spec cannot guess wrong about `skipped`. The first skipped case owns the parent `reason`, so the same single-source link applies. I moved to A in B1 to follow four seats; the learnability argument still favours B, and once Q3 passes the cost of the extra field on `skipped` is one string.
> Concern: The runtime today omits `case` on `skipped`, so B needs a runtime change, and a consumer may read `case` as "something failed" on a skipped parent.
>
> **Q2. Vote: C**
> Reasoning: A nested call that panics leaves `cases[]` flat with unambiguous labels and adds no join rule, so there is one fewer decision point for a model writing tests. Option A leaves repeated labels (p4 `inner1` twice) and makes `case` an ambiguous key; option B adds a `/` join rule that collides with labels containing `/`. A wrong guess about nesting is cheap to learn from a clear panic message and costly to learn from a silent ambiguous record.
> Concern: A shared helper that calls `for_each` inside a case fails only at run time, in a test that otherwise reads as correct (web).
>
> **Q3. Vote: A**
> Reasoning: It mirrors `message` on `panicked` entries, so the entry schema stays regular: each non-passed status carries its own text. A model never has to guess which reasons were dropped. The cost is one bounded string per skipped case.
> Concern: Min is right that it is schema nobody asked for, and it widens the entry shape if Q4 later fails.
>
> **Q4. Vote: A**
> Reasoning: With only the first outcome in the parent, an AI fixes case b, reruns, and meets case c with no earlier detail; full entries remove that rerun loop. A `failed` entry that carries the same payload as a parent also makes the parent "a copy of one entry", one line of spec. Bounded by failure count, not table size, in normal use.
> Concern: A large all-failing table makes the record big and holds rendered `expected`/`actual` in memory until the test ends (sys, devops).
>
> **Q5. Vote: B**
> Reasoning: The terminal has no `cases[]`, so a human or an AI reading CI logs sees only the printed lines. "Every non-passed case is reported, line form is tooling" is one sentence and removes the "fix b, find c" loop in text output too. Option A leaves a parent-only line, which hides the second failure.
> Concern: Printing every case's own outcome depends on Q4; if Q4 loses, the runtime must keep per-case detail separately, or print only label and status.
>
> **Q6. Vote: A**
> Reasoning: Models will guess either way whether `assert_panics` around a `for_each` consumes a case's panic; one observable-terms sentence settles it with no mention of E0831. The rule already implies the answer, but an AI reading the spec alone should not have to derive it from the catch-boundary text.
> Concern: The sentence implies a `for_each` case frame is a runner-owned catch boundary that §4 does not list (plt); the §4 text needs the same fix.

**Minimalism**

> **Q1. The parent `"case"` field.**
> - **Vote:** A
> - **Reasoning:** The runtime already emits `case`, and a `failed` entry in `cases[]` holds only `label` and `status`, so the field is the only link from the parent's assertion to a row. That makes it a foundational link and not surplus, so I drop my "do not specify". A is the narrowest wording: it names the two statuses that have a failing row to point at. A `skipped` parent has no single owner for its reason, so B adds a per-status case for no gain.
> - **Concern:** If B wins, the runtime must start emitting `case` on `skipped` parents, a change nobody asked for that spends schema on a status with no row to attribute.
>
> **Q2. Nested `for_each`.**
> - **Vote:** A
> - **Reasoning:** Nesting is rare, and no user has asked for a rule. Flat rows in completion order need no new text, no join rule and no runtime check, and the fold already composes. B adds a join rule that collides with labels holding `/`. C adds a runtime panic that a call through a helper function hits only at run time, in a test that is otherwise correct.
> - **Concern:** The same label can appear twice in `cases[]`, so the parent's `case` can be ambiguous in a nested test, and a tool that keys on label alone will confuse the rows.
>
> **Q3. `reason` on skipped `cases[]` entries.**
> - **Vote:** B
> - **Reasoning:** The parent `reason` rule (first skipped case's reason) answers the ticket. A per-entry `reason` is new schema that no one asked for, and it widens a closed entry shape. A later ticket can add it without changing the parent.
> - **Concern:** With A winning, a skipped test hides no reason, but every entry shape now varies by status, and the next request will be for the full payload (Q4).
>
> **Q4. Full payload on `failed` `cases[]` entries.**
> - **Vote:** B
> - **Reasoning:** It copies every payload, including `introspection` and rendered `expected`/`actual`, into every failing row. sys notes that memory is unbounded in a 10k-case table, and the ticket does not ask for it. The parent rule works without it, and an entry can gain fields later without a break.
> - **Concern:** If A wins, the record grows with failure count and the runtime holds every failing payload until the test ends, which is the cost the table-driven case exists to make cheap.
>
> **Q5. Human output.**
> - **Vote:** C
> - **Reasoning:** Human text is not a schema. The runtime already prints `t::case[b]`, and the label is the line's identity, so a spec sentence only binds tooling that has no consumer. A and B would make the terminal form a conformance point. If the panel passes A, I accept it as the least cost of the two.
> - **Concern:** With C, another runner can print a failing case with no label, and the spec has no line to cite against it.
>
> **Q6. `assert_panics` around a `for_each` whose case panics.**
> - **Vote:** B
> - **Reasoning:** The parent rule (`panicked` outranks everything) already gives the answer for p6. The sentence would also name the `for_each` case frame as a catch boundary, which §4 (~2667) does not list and which says the user-extensible set "remains empty". That question belongs in §4, not in a test-record sentence.
> - **Concern:** With B, a reader and an AI must derive the p6 result from the severity rule alone, and two runtimes could differ on whether the block's own E0831 outcome is also recorded.

**Phase C tally**

| Question | sys | web | plt | devops | aiml | min | Result |
|----------|-----|-----|-----|--------|------|-----|--------|
| Q1 `case` field | A | B | B | A | B | A | A 3, B 3: tie |
| Q2 nested `for_each` | C | B | B | B | C | A | B 3, C 2, A 1 |
| Q3 `reason` on skipped entries | A | A | A | A | A | B | A 5, B 1 |
| Q4 full payload on failed entries | B | A | A | A | A | B | A 4, B 2 |
| Q5 human output | A | B | A | A | B | C | A 3, B 2, C 1 |
| Q6 `assert_panics` sentence | A | A | A | A | A | B | A 5, B 1 |

Q3 and Q6 passed. Q1 tied. Q2, Q4 and Q5 had no majority of the six seats, so the moderator ran a second round on Q1, Q2, Q4 and Q5.

#### Phase D1 — Focused second round

The moderator showed each seat the Phase C reasoning on Q1, Q2, Q4 and Q5. Each seat answered "Hold" or "Move" with a reason.

**Systems**

> **Q1. Hold A.** web, plt and aiml argue that one rule beats a status list. The cost of B is a new field on `skipped` records, which the runtime does not emit today, and the field would point at a row that did not fail. The A rule is one sentence: "`case` is on `failed` and `panicked` parents." A consumer who reads `case` on a skipped parent gains nothing: `reason` is already in the first skipped entry, which Q3 now carries. If B wins I will not object further, because the cost is one string.
>
> **Q2. Move from C to B.** My C reasoning rested on the cost of a path join. That cost falls only on nested calls, which are rare, and the non-nested path allocates nothing extra. web and devops raise the point that decides it: a helper that calls `for_each` inside a case would fail only at run time, in a test that is otherwise correct, and I conceded that in my Phase C Concern. Flat rows (A) leave `inner1` twice in `cases[]` and make `case` an ambiguous key. B gives unique keys. The spec should say the path is an opaque display key and that a `/` inside a label is not parsed.
>
> **Q4. Hold B.** The memory argument is still unanswered. A `failed` payload holds rendered `expected`, `actual` and `introspection`. plt and devops both name the 10k-failing-case table as a concern and both say a cap would need spec text that does not exist. A passing Q4 would force that cap design into this ticket. Keep entries to `label`, `status`, `message`/`span` on panicked and `reason` on skipped. A separate ticket can add opt-in detail with a cap.
>
> **Q5. Hold A.** The line form is tooling. Option B ("every non-passing case") has an open definition: aiml counts skipped cases and web does not say. It also depends on Q4, because per-case lines need per-case detail that Q4 B does not store. A says the one thing a reader needs: the printed outcome names its case label.

**Web/Scripting**

> **Q1. Hold B.** The sys, devops and min argument is that the runtime omits `case` on `skipped` today. That is a reason to change one line of runtime, not a reason for the spec. The skipped parent's `reason` comes from one named case, so the link is real. A dev or script that reads `case` then needs no status check. The A text is "present on `failed` and `panicked`", a list a reader must memorise. The sys concern (no failure to attribute) mixes two things: `case` names the owner of the payload, not a failure. I hold B.
>
> **Q2. Hold B.** The sys and aiml answer to my concern is that a nested call in a helper fails at run time. They keep that as their concern, and it is the strongest point against C. A JS or Python dev who moves a table loop into a shared helper gets a panic in a test that is otherwise correct. Min's A leaves `inner1` twice in `cases[]`, so `case` is an ambiguous key and Q1 loses its value. The `/` collision is rare, and plt's text says the path is a display key. I hold B, with flat rows as second choice.
>
> **Q4. Hold A.** The memory concern (sys, min) is real for a 10k-case all-failing table, but that table is already a broken test. The common table has a few failures, and for those the rerun loop ("fix b, find c") is the cost a dev feels every day. A runner can cap a payload later, and plt and devops note that a cap needs its own text. That is a follow-up, not a reason to drop the payload. I hold A.
>
> **Q5. Move to A.** B has two votes, and plt shows its weak point: "every non-passing case" leaves skipped cases undefined, and it binds every runner to print all cases. Runners will print every failing case anyway, because devs ask for it, as pytest and Jest do. A keeps the one property a scraper needs (the label of the printed outcome) and leaves policy to tooling. I accept A. My concern stays: two runners may print different amounts.

**PLT**

> **Q1. Hold B.** A skipped parent's `reason` has one owner, the first skipped case. The claim "a skip has no single owner" (sys, devops, min) is false for the payload. Single-source then gives a total rule: `case` is present iff a case supplied the payload. Under A the field means "the payload's owner, but only on two statuses". The cost is one string, and `status` already tells a reader that nothing failed.
>
> **Q2. Hold B.** The `case` key is sound only if labels in `cases[]` are unique per record, and flat rows break that (p4). A runtime panic (C) is O(1), but it is a dynamic check for a shape that composes without one, and it fires in a correct test that reaches `for_each` through a helper. The path restores uniqueness up to `/` in labels; the spec should call it an opaque display key. If B loses, my second choice is C, not A, because A leaves Q1's key ambiguous.
>
> **Q4. Hold A.** sys's memory point bounds the implementation, not the semantics. The parent already holds one full payload, and a runner can drop rendered text once the entry is written to the stream. The gain is that the parent is a copy of one entry, so the selection rule has one statement and no second failure is lost. A cap, if needed, is a follow-up with its own text.
>
> **Q5. Hold A.** B binds every runner to a per-case rule that leaves skipped cases undefined (web and aiml differ). The property that matters is that the printed outcome names its case, so a reader can link it to `cases[]`. Line count is tooling policy. If A loses, I prefer C to B.

**DevOps/Tooling**

> **Q1: hold A.** web, plt and aiml want one rule with no status list. That is a fair point for a reader, but the cost sits in tooling. The runtime emits `case` on `failed` and `panicked` today, so A breaks no consumer. B makes every `skipped` record carry a field that a CI tool will read as "a case failed here". The status check that web fears is one line: a consumer reads `case` only when `status` is `failed` or `panicked`, and the parent `reason` on a skipped parent already shows what was skipped. Q3 passed, so each skipped row carries its own `reason`; a skipped parent loses nothing. I stay with A.
>
> **Q2: hold B.** The panel split three ways on the shape, and C has two seats. C turns a correct test into a run-time panic when a shared helper calls `for_each` in a case, and the compiler and LSP cannot warn about it. A leaves duplicate keys (`inner1` twice in p4), and tools that match rows by label then fail without a message. B costs one join rule. I accept sys's point that a `/` in a label can collide; the spec should say the path is an opaque key, and tools must not parse it. If B loses, A is my second choice, not C.
>
> **Q4: hold A.** sys and min raise memory for a 10k-case failing table. That is a real cost, but it is a runner policy: a runner can cap the rows it keeps and say so. The spec rule is the payload on each failed entry. I accept that the writer should flag the cap as a follow-up. Without the payload, the second failure has no detail in JSON, and the LSP and CI tools cannot show it.
>
> **Q5: hold A.** B would make "every non-passing case" a conformance point, and aiml and web differ on whether skipped counts. A fixes the one thing a reader needs: the printed outcome names its case label. Runners can print more lines without a spec change. I accept A as my choice over B, and min says A is its second choice, so A has the widest support.

**AI/ML**

> **Q1. Hold B.** The runtime-compat argument (A documents today) is real, but it fixes a spec by what one runtime does. A model reading A must memorise a status list ("failed, panicked, not skipped") and then ask why. B is one sentence: `case` is the case that supplied the payload. web, plt and I give the same reason, and no seat refuted it; the A seats concede B is simpler to state. The cost is one string on a `skipped` record.
>
> **Q2. Move to B.** I voted C to leave labels unambiguous. web and devops show the cost: a shared helper that calls `for_each` inside a case panics at run time in a test that reads as correct. For a model that writes helpers, that is the worse failure. A path keeps `case` a unique key, and Go `t.Run` users already know `outer/inner`. I accept the `/`-collision concern; the spec should say the path is an opaque display key. Flat rows (A) stay my last choice, because they leave `case` ambiguous.
>
> **Q4. Hold A.** The memory argument (sys, min) bites only for very large all-failing tables. A model that gets one failure per run pays a run per failing case, every time. If the panel fears the size, a cap is a runtime policy for a later ticket; it is not a reason to drop the payload. A also makes the parent a copy of one entry, one line of spec.
>
> **Q5. Move to A.** My B concern was that a parent-only line hides the second failure. With Q4 passing, the JSON entries carry full detail, so the machine contract is complete. A binds every runner to the case label of the printed outcome and no more. B leaves "non-passed" open for skipped cases (plt's point), and that is a new decision point. I move rather than bind every runner to print every case. If Q4 fails, this move costs more; I still vote A.

**Minimalism**

> **Q1. Hold A.** The 3-3 split is about one status. B's one rule is tidy, but it adds `case` to `skipped` records, which the runtime does not emit today. Nobody has asked for that, and the skipped parent's `reason` is already a first-case reason that the spec states. A documents what runs now. web and aiml are right that A has a status list; the list has two entries and the sentence "absent on `skipped`" costs one clause. I count the runtime change under B as the real cost.
>
> **Q2. Move to B.** I held A because nesting is rare and a rule is surplus. plt, web and devops show that Q1 changes this: once the parent carries `case`, `case` is a key into `cases[]`, and flat rows give p4 two rows named `inner1`. A key that is not unique is a defect that Q1 introduces. The smallest repair is the `/` path: one join sentence, no runtime check, no new panic, no restriction on users. C is a new run-time failure for a shape that is correct today, and it fires through a helper fn with no compile error. I rank B over C, and C last of the three only if A is off the table. The writer should say the path is a display key, not parsed.
>
> **Q4. Hold B.** Q3 passed, so entries now carry `reason` on skips. Q4 is a different size of change: it copies `cause`, `expected`, `actual` and `introspection` into every failing row. plt, devops and aiml each name the memory cost in their own Concern line, and plt adds that a cap "would need its own spec text". That is an open consequence the vote does not settle. "Fix b, rerun, find c" is real but not new: the runner runs every case already, and the human output (Q5) can name each failing case. An entry can gain fields later without a break; a payload in the schema cannot be removed.
>
> **Q5. Move to A.** I said in Phase C that I accept A as the least cost. A binds only the property that matters, that the output names the case label of the outcome it prints, and leaves line form to tooling. B would bind every runner to print every case and leaves skipped cases undefined (plt). With A holding 3 votes, I move so the label is cited somewhere.

#### Phase D2 — Silent vote on Q1, Q2, Q4 and Q5

Each seat voted alone. Q3 (A, 5-1) and Q6 (A, 5-1) were already settled and were not on this ballot.

**Systems**

> **Q1. The parent `"case"` field.**
> - **Vote:** A
> - **Reasoning:** The runtime already emits `case` on `failed` and `panicked` parents, so A costs no runtime change and no consumer breaks. A `skipped` parent has no failure to attribute, and Q3 now gives each skipped row its own `reason`, so the parent loses nothing. The A rule is one sentence with two statuses.
> - **Concern:** If B wins, every `skipped` record carries a field that a CI tool may read as "a case failed here", and a consumer must still check `status` before it trusts `case`.
>
> **Q2. Nested `for_each`.**
> - **Vote:** B
> - **Reasoning:** A path join runs only for nested cases, so the non-nested path allocates nothing extra. A nested-call panic (C) turns a correct test into a run-time failure when a shared helper calls `for_each` in a case, and no compile check can catch it. Flat rows (A) give two `inner1` rows in p4, so `case` is not a unique key. The spec must say the path is an opaque display key and that a `/` inside a label is not parsed.
> - **Concern:** A label that holds `/` can collide with a path, and a tool that parses the path will mis-split it.
>
> **Q4. Full payload on `failed` `cases[]` entries.**
> - **Vote:** B
> - **Reasoning:** A `failed` payload holds rendered `expected`, `actual` and `introspection`. Retaining that for every failing case of a 10k-case table is unbounded memory held until the test ends, and the cost grows with failures. plt and devops both say a cap would need spec text that does not exist, so A forces cap design into this ticket. An entry can gain fields later without a break; a payload in the schema cannot be removed.
> - **Concern:** A model or CI tool sees a second failure only as a label and status, so "fix b, rerun, find c" stays real until a follow-up adds opt-in detail with a cap.
>
> **Q5. Human output.**
> - **Vote:** A
> - **Reasoning:** The spec should say only that the output names the case label of the outcome it prints. Line form and per-case lines are tooling policy and can change without a language revision. B binds every runner to print every case and leaves skipped cases undefined.
> - **Concern:** Two runners may print different numbers of lines, so a user may see one failure per run on one runner and all failures on another.

**Web/Scripting**

> **Q1. The parent `"case"` field.**
> - **Vote:** B
> - **Reasoning:** A dev reads a record and asks "which case owns this payload?" One rule, "present whenever a case supplied the payload", takes one sentence to learn and needs no status check in a script. A skipped parent's `reason` comes from one named case, so the link is real there too, and `case` names the owner of a payload, not a failure. The A list ("failed and panicked, not skipped") is an exception a reader must memorise; sys says he will not object if B wins, since the cost is one string.
> - **Concern:** The runtime does not emit `case` on `skipped` today, so B needs a one-line runtime change, and a CI tool may read `case` as "a case failed" without checking `status`.
>
> **Q2. Nested `for_each`.**
> - **Vote:** B
> - **Reasoning:** Go `t.Run` users already know `outer/inner`, and the path keeps `case` a unique key into `cases[]` (p4 has `inner1` twice under flat rows). A nested-call panic (C) fails only at run time, when a JS or Python dev moves a table loop into a shared helper, in a test that is otherwise correct. Six seats now hold or move to B, with the spec text saying the path is an opaque display key.
> - **Concern:** A label that contains `/` can collide with a path, and a dev may try to parse the path, so the spec must say it is opaque.
>
> **Q4. Full payload on `failed` `cases[]` entries.**
> - **Vote:** A
> - **Reasoning:** Without it a dev fixes case b, reruns, and meets case c with no detail in the JSON, which costs one run per failing case. pytest and Jest show every failing case. With full entries the parent is a copy of one entry, so the selection rule is one line. The 10k-failing-case table is already a broken test, and a runner cap is a follow-up with its own text.
> - **Concern:** A large all-failing table makes a big record held in memory until the test ends, and the spec has no cap yet.
>
> **Q5. Human output.**
> - **Vote:** A
> - **Reasoning:** The spec needs the one property a reader and a scraper rely on: the printed outcome names its case label. "Every non-passing case" (B) leaves skipped cases undefined and binds every runner. Runners will print every failing case anyway, because devs ask for it, so line count can stay tooling policy.
> - **Concern:** Two runners may print different amounts, so a dev may see one failure on one runner and all failures on another.

**PLT**

> **Q1. The parent `"case"` field.**
> - **Vote:** B
> - **Reasoning:** The parent takes every payload field from one outcome, so `case` names the owner of that payload. A skipped parent's `reason` has one owner, the first skipped case, so the single-source rule covers `skipped` with no exception. B states one meaning ("the case that supplied the payload"); A defines the field by a status list. The claim that a skip has no single owner is false for the payload, and `status` already tells a reader that nothing failed.
> - **Concern:** If A wins, `skipped` is the one status whose payload owner the record does not name, and the meaning of `case` depends on a status list.
>
> **Q2. Nested `for_each`.**
> - **Vote:** B
> - **Reasoning:** Under Q1, `case` is a key into `cases[]`, and a key is sound only if labels are unique per record; flat rows give p4 two rows named `inner1`. A nested-call panic (C) is a dynamic check for a shape that composes under the fold, and it fires in a correct test that reaches `for_each` through a helper, so it is not a static guarantee. The `/` path restores uniqueness up to `/` in labels, and the spec should say the path is an opaque display key that tools do not parse.
> - **Concern:** A label that contains `/` can collide with a path, so uniqueness holds only up to that ambiguity.
>
> **Q4. Full payload on `failed` `cases[]` entries.**
> - **Vote:** A
> - **Reasoning:** The parent is then a copy of one entry, so the selection rule has one statement and no second failure is lost. The memory argument bounds the implementation, not the semantics: a runner can drop rendered text once it writes the entry to the stream. B leaves `case` pointing at an entry that holds only `label` and `status`.
> - **Concern:** The runtime retains rendered `expected`/`actual` for every failing case, so a very large failing table holds memory until the test ends, and a cap would need its own spec text.
>
> **Q5. Human output.**
> - **Vote:** A
> - **Reasoning:** One property matters: the printed outcome names its case label, so a reader can link it to `cases[]`. Line form and per-case lines are presentation, not schema. B's "every non-passing case" leaves skipped cases undefined and binds every runner to a per-case rule.
> - **Concern:** Two runners may print different numbers of lines, so a terminal reader may see one failure per run.

**DevOps/Tooling**

> **Q1. The parent `"case"` field.**
> - **Vote:** A
> - **Reasoning:** A CI tool reads the parent and needs the link to a `cases[]` row. That link matters where a failing row exists, so `failed` and `panicked` carry `case`. A skipped parent loses nothing under A, because Q3 gives each skipped entry its own `reason`. A also records what the runtime emits today, so no consumer changes. The status check B's seats fear is one line in a tool.
> - **Concern:** If B wins, a CI tool may read `case` on a `skipped` parent as "a case failed here", and the runtime must change for no tool request.
>
> **Q2. Nested `for_each`.**
> - **Vote:** B
> - **Reasoning:** Once the parent carries `case`, `case` is a key into `cases[]`, and tools and the LSP match rows by it. Flat rows give two rows named `inner1` (p4), so the key is ambiguous. C turns a correct test into a run-time panic when a shared helper calls `for_each`, and no compile-time check or LSP warning can find it. The `/` path gives unique keys with one join rule. The spec must say the path is an opaque display key and tools must not parse it.
> - **Concern:** A label that contains `/` can collide with a path, so a tool that splits the path on `/` gets wrong rows.
>
> **Q4. Full payload on `failed` `cases[]` entries.**
> - **Vote:** A
> - **Reasoning:** The parent shows one failure per run. Without payload on the entries, the LSP test view and CI annotations show a second failing case as a label and a status, and the dev must fix b and rerun to see c. The JSON is the machine contract, so it must hold every failure. The parent then equals a copy of one entry, and the selection rule has one statement.
> - **Concern:** A large all-failing table makes a big record held in memory until the test ends, and the spec has no cap, so the writer must flag the cap as a follow-up.
>
> **Q5. Human output.**
> - **Vote:** A
> - **Reasoning:** The spec should fix what a reader must learn: the printed outcome names its case label, so the reader can find the row in `cases[]`. Line form and extra per-case lines are tooling that changes with terminals and log parsers. B leaves skipped cases undefined and binds every runner. Runners may print every failing case without a spec change.
> - **Concern:** Two runners can print different amounts, so a dev sees one failure on one runner and all failures on another.

**AI/ML**

> **Q1. The parent `"case"` field.**
> - **Vote:** B
> - **Reasoning:** One rule ("`case` is present whenever a case supplied the parent's payload") has no status list to memorise, so a model reading the spec cannot guess wrong about `skipped`. The first skipped case owns the parent `reason`, so the owner link is real there too. `case` names the payload's owner, not a failure, and `status` already says whether anything failed. The runtime change is one string on a `skipped` record.
> - **Concern:** A consumer may read `case` on a skipped parent as "something failed", and the runtime must change to emit it.
>
> **Q2. Nested `for_each`.**
> - **Vote:** B
> - **Reasoning:** Flat rows give `inner1` twice (p4), so `case` is an ambiguous key. A nested-call panic fires only at run time, in a correct test that reaches `for_each` through a helper, and a model that writes helpers meets it often. The `/` path costs one join sentence and keeps keys unique. The spec must say the path is an opaque display key and that a `/` inside a label is not parsed.
> - **Concern:** A label that contains `/` can collide with a path, and a tool may try to parse it.
>
> **Q4. Full payload on `failed` `cases[]` entries.**
> - **Vote:** A
> - **Reasoning:** With only the first outcome in the parent, a model fixes case b, reruns, and meets case c with no earlier detail, so it pays one run per failing case. With full entries the parent is a copy of one entry, one line of spec. The memory cost bites only on a very large all-failing table, and a cap is runner policy for a follow-up ticket.
> - **Concern:** A large all-failing table makes a big record and holds rendered `expected`/`actual` until the test ends, and a cap would need its own spec text.
>
> **Q5. Human output.**
> - **Vote:** A
> - **Reasoning:** I moved from B because Q4 passing makes the JSON entries complete, so the machine contract holds every failure. B leaves "non-passed" open for skipped cases, a new decision point. A fixes the one property a reader needs: the printed outcome names its case label. Runners can print more lines without a spec change.
> - **Concern:** Two runners may print different numbers of lines, so a reader of CI text may see one failure on one runner and all failures on another.

**Minimalism**

> **Q1. The parent `"case"` field.**
> - **Vote:** A
> - **Reasoning:** The runtime already emits `case` on `failed` and `panicked` parents, so A states what exists and adds no field. B adds `case` to `skipped` records, a change no consumer asked for. The `skipped` parent's `reason` is already specified as the first skipped case's reason, and Q3 gives each skipped row its own `reason`, so a skipped parent loses nothing under A.
> - **Concern:** A leaves a two-status list that web, plt and aiml say a reader must memorise, and a consumer must check `status` before it reads `case`.
>
> **Q2. Nested `for_each`.**
> - **Vote:** B
> - **Reasoning:** Once Q1 makes `case` a key into `cases[]`, flat rows give p4 two rows named `inner1`, and a non-unique key is a defect that Q1 introduces. One join sentence restores uniqueness with no runtime check and no new panic. C turns a correct test into a run-time failure when a shared helper calls `for_each`. The spec must call the path an opaque display key that tools do not parse.
> - **Concern:** A `/` inside a label can collide with a path, so uniqueness holds only up to that ambiguity.
>
> **Q4. Full payload on `failed` `cases[]` entries.**
> - **Vote:** B
> - **Reasoning:** A copies `cause`, `expected`, `actual` and `introspection` into every failing row, and a payload in the schema cannot be removed later, while an entry can gain fields without a break. Four seats name the 10k-failing-case memory cost, and a cap would need spec text that this ticket does not have. The parent rule works without it, and Q5 A names each printed outcome's case, so nothing needs the full payload now.
> - **Concern:** With A winning, the runner holds every failing payload until the test ends, and the spec may need a cap clause in a follow-up.
>
> **Q5. Human output.**
> - **Vote:** A
> - **Reasoning:** A binds one property: the output names the case label of the outcome it prints. The line form and extra lines stay tooling, and B would make "every non-passing case" a conformance point with skipped cases undefined. I accept A over C because the label then has a citable line.
> - **Concern:** Two runners may print different numbers of lines, so a user may see one failure per run on one runner and all failures on another.

**Phase D2 tally**

| Question | sys | web | plt | devops | aiml | min | Result |
|----------|-----|-----|-----|--------|------|-----|--------|
| Q1 `case` field | A | B | B | A | B | A | A 3, B 3: tie |
| Q2 nested `for_each` | B | B | B | B | B | B | B 6, passes |
| Q4 full payload on failed entries | B | A | A | A | A | B | A 4, B 2, passes |
| Q5 human output | A | A | A | A | A | A | A 6, passes |

#### Owner tiebreak on Q1

Q1 stayed at 3-3 after the second round. The owner (BDFL) broke the tie for A: `case` appears on `failed` and `panicked` parents only. It is absent on `passed`, on `skipped`, and when body code supplied the outcome. Option A records what the runtime emits today, and a skipped parent loses nothing because each skipped `cases[]` entry carries its own `reason` (Q3).

PLT, web and AI/ML voted B in both rounds. Their Phase D2 Concern lines are above. PLT: "If A wins, `skipped` is the one status whose payload owner the record does not name, and the meaning of `case` depends on a status list."

#### Reading gaps and follow-ups

- Probe p6 holds no E0831 text. The spec text makes no claim about E0831 for an `assert_panics` around a `for_each`. Whether the runtime also reports E0831 there goes to the runtime work.
- The matching §4 edit is done: the case frame of `std.testing.for_each` is a runner-owned catch boundary that user code cannot create.
- A cap on the failing payloads a runner retains is a follow-up. Q4 passed 4-2 and the spec sets no cap.
- The runtime does not yet match the spec in two places that the probes showed. It loses a panic after the loop when an earlier case failed (p5). It labels nested cases flat, not by `/` path (p4). These go to the runtime work.

### Final Spec

A parent record takes its status, message, span and cause from one outcome. This test has one failing case and one passing case:

```blink
import std.testing

test "signs" {
    testing.for_each([("a", 1), ("b", 2), ("c", 3)], fn(v: Int) {
        assert_eq(v, 1)
    })
}
```

Cases `b` and `c` fail, and `b` ran first. The parent record is `failed` and its `case` field is `"b"`. The `cases` entry for `a` is `passed`. The entries for `b` and `c` each carry the full failed payload.

Locked design points:

- No language change. The outcomes of a test are its cases and the body's own outcome.
- Parent status is the most severe outcome: panicked, then failed, then passed. It is `skipped` only when at least one case ran, every case skipped, and the body did not fail or panic. An empty list passes.
- The first outcome in execution order that has the parent's status supplies the message, span, cause and cause fields. An all-skipped parent takes the first skipped case's reason.
- `case` is on `failed` and `panicked` parents only. It is absent on `passed`, on `skipped`, and when body code supplied the outcome (Q1, tie broken by the owner for A).
- A nested `for_each` labels an inner case with the `/`-joined path. The path is an opaque display key. The outer case also gets its own row (Q2, 6-0).
- A skipped `cases` entry carries its own `reason` (Q3, 5-1).
- A failed `cases` entry carries the full payload (Q4, 4-2).
- Human output names the case label of the outcome it prints. Line form is tooling (Q5, 6-0).
- A case's panic is recorded by the case. An enclosing `assert_panics` does not consume it, and the parent is `panicked`. Section 4 names the case frame as a runner-owned catch boundary (Q6, 5-1).


