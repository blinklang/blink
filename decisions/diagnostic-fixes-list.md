[< All Decisions](../DECISIONS.md)

# More Than One Fix in a Diagnostic — Design Rationale

### Panel Deliberation

Six seats voted: Systems, Web/Scripting, PLT, DevOps, AI/ML, Minimalism. The question: the JSON diagnostic (§8.6) has one `fix` object and, in the compiler, one `assist`. E0319 needs two fixes, and E0844 and the handler clauses need more than one. Where does the second fix go?

Phase A and B are excerpts, marked with "…" where text is cut. Phase C and D are complete.

#### Phase A — Independent proposals

**Systems**: "Replace `fix` and `assist` with `fixes`: an array, ordered by preference. Omit the key when there are no fixes … Each fix has: `description` … `applicability` … `edits` … `fixes[0]` is the preferred fix. Order is part of the contract (E0319 stays: `..` first)." On the terminal: "Print every fix, preferred first, under the existing `help:` line … Cap the terminal at the first two fixes if more exist, then `(n more in --json)`." On Principle 7: "Delete the phrase. Nothing computes a score, and a float invites consumers to threshold on it."

**Web/Scripting**: "Replace `fix` with `fixes`: an array, never absent (empty when there is no fix). Order is preference … A fix with `edits: []` is advice only; it is always `suggestion`." On the terminal: "print every fix, in order, as a `help:` line. Mark a non-applicable one the way E0521 already does." On the choice of shape: "Keep the §8.6 shape (`description` + `edits[]`), not the emitted `action`/`text`/`span`. The emitted shape cannot hold a fix with two edits."

**PLT**: "A diagnostic carries `fixes: [Fix]`, ordered, possibly empty. Each fix is a total record … Applicability is a field of the fix, not of its position or of the key name. Position-coded meaning (`fix` vs `assist`) does not compose: every new fix kind forces a new key, and a consumer must know the key set in advance. A list with a tag is closed under adding fixes." PLT also proposed a reserved third value, `needs-input`, and the terminal form `= fix (not machine-applicable): …`.

**DevOps**: "Replace the single `fix` key with a `fixes` array. Zero fixes: omit the key. One fix: an array of one (no special case) … A fix with no `edits` is help only; it stays in `help`, not in `fixes` … `applicability` is required, never defaulted. A missing flag must not read as machine-applicable." On `blink fix`: "If one diagnostic has two machine-applicable fixes (E0844), `blink fix` applies the first and skips the rest of that diagnostic (they are alternatives, not a sequence)." On the terminal: "Hiding the second fix makes the terminal lie by omission and breaks Principle 7." Principle 7 text: "lists them in order, preferred first, and marks which are machine-applicable".

**AI/ML**: "An AI agent reads the JSON and must pick an edit. Every extra key name or shape is a decision point. I want one list, one item shape, and one enum." Zero fixes: "omit the key. Never `null`, never `[]`." Three values, with `template` reserved. "Order is significant: first is preferred. If a `machine` fix exists, it comes first." "Two keys that mean 'a fix' give a model two paths to learn; a list gives one."

**Minimalism**: "Keep one `fix`, add one optional key, and delete the 'confidence scores' sentence. Do not add a `fixes` list, a flag enum, or terminal output for suggestions … The key name carries the applicability, so there is no flag to read, forget or get wrong." "E0844 has two machine-applicable fixes. It is the only one in the spec. Do not build a list for one case." On the shape: "I favour the §8.6 shape (`description` + `edits[]`) … Two shapes for one concept is the worst result."

Agreement across all six seats in Phase A: delete "with confidence scores", and keep the §8.6 shape (`description` + `edits[]`) in place of the emitted `action`/`text`/`span` shape.

#### Phase B — Debate highlights

Option 1 is one `fixes` array. Option 2 keeps `fix` and `assist`. All six seats chose Option 1 (6-0).

- **Minimalism** moved from Option 2: "I concede to Option 1. Five seats agree, and E0844 breaks my case: it has two machine-applicable fixes, and Option 2 has no honest place for the second. One `fixes` array also replaces two keys (`fix`, `assist`) with one, so it removes surface. I withdraw the 'safe by default' argument only if the `applicability` field has no default: a fix without it is invalid."
- **PLT** on the same point: "Option 2 fails on the spec as written: E0844 states two machine-applicable fixes, and Option 2 gives one `fix` … The list answers it with a fail-closed rule: `applicability` is required, and a consumer applies a fix only when the value equals `"machine-applicable"`; a missing or unknown value is not applicable. Put this sentence in the spec."
- **Spelling and values.** AI/ML dropped `template` and PLT dropped `needs-input`. All six agreed on two values, `"machine-applicable"` and `"suggestion"`. DevOps: "A reserved value that no diagnostic emits is dead surface that every consumer must decide how to treat."
- **Advice with no edit.** Web and Systems gave up the empty-`edits` fix. Systems: "A fix with no edit is help text, and `help` already holds it. One meaning per field." A fix has a non-empty `edits` array.
- **`blink fix` and alternatives.** AI/ML withdrew "apply every machine fix". DevOps: "Two machine-applicable alternatives (E0844) often touch the same span. The §8.6 rule then says apply neither. Apply-all would turn every E0844 into a conflict. First fix per diagnostic only. The spec must say so."
- **Terminal.** Five seats print every fix. Minimalism moved from "no new output" to "Print each fix, with one rule: a suggestion carries the label '(not machine-applicable)', as E0521 does today." Systems kept a cap of two lines. DevOps and PLT wanted `fix:` as the label of an edit line. DevOps, PLT, Web, Minimalism and AI/ML rejected the cap: "a rule for a case that does not exist".
- **Zero fixes.** Web kept "always present" but said: "I do not oppose omit-when-empty if the spec says it in one sentence; one rule matters more than which rule."
- **Order.** AI/ML held "If a `machine` fix exists, it comes first". Systems and Web held that each diagnostic's own text sets the order.
- **Stale wording.** Systems, AI/ML and DevOps wanted the "never machine-applicable" sentences rewritten. Web and Minimalism first wanted a later chore. Phase C moved them.
- **Principle 7.** Four seats backed DevOps's sentence, "lists them in order, preferred first, and marks which are machine-applicable". Systems and AI/ML had other wording.

The moderator turned the open points into seven ballot questions (Q1 to Q7) for Phase C.

#### Phase C — Final vote

Points that all six Phase B replies stated, and that were not on the ballot: Option 1; two `applicability` values spelled `"machine-applicable"` and `"suggestion"`; a fix has at least one edit and advice with no edit stays in `help`; `blink fix` applies the first machine-applicable fix of a diagnostic and skips the rest; the LSP sets `isPreferred` on the first fix only when it is machine-applicable; the terminal prints the fixes and marks a fix that is not machine-applicable; "with confidence scores" goes from Principle 7.

Ballot options:

| Question | A | B | C |
|---|---|---|---|
| Q1 Zero fixes | Omit the `fixes` key | Always present, `[]` when empty | |
| Q2 Terminal label | `help:` for each fix, `(not machine-applicable)` on a suggestion, as E0521 does | `fix:` for a machine-applicable fix, `fix (not machine-applicable):` for a suggestion; `help:` stays the short line | |
| Q3 Terminal cap | No cap | Cap at 2 lines, then `(n more in --json)` | |
| Q4 Order | Preferred first, as each diagnostic's own text sets it | Preferred first, and machine-applicable before suggestions | |
| Q5 Principle 7 | "lists them in order, preferred first, and marks which are machine-applicable" | "in preference order, each marked with its applicability" | "When multiple fixes are possible, the diagnostic lists them in order of preference, and each says whether it is machine-applicable (§8.6)." |
| Q6 Missing or unknown `applicability` | The spec states the consumer rule (exact match to apply) | `applicability` is required; no consumer rule | |
| Q7 "Never machine-applicable" wording | Rewrite in the same spec change | A chore after the decision | |

Result: Q1 A 6-0. Q2 A 4 (Systems, Web, AI/ML, Minimalism), B 2 (DevOps, PLT). Q3 A 6-0. Q4 A 5, B 1 (AI/ML). Q5 A 4 (DevOps, Minimalism, PLT, Web), B 1 (AI/ML), C 1 (Systems). Q6 A 6-0. Q7 A 6-0.

**Systems**

**Q1. Vote:** A
**Reasoning:** Omitting the key costs zero bytes on a diagnostic with no fix, and a consumer needs one check (key present). An empty array and an absent key carry the same fact, so the spec allows one form. A consumer must already handle absent keys for older output.
**Concern:** A consumer that assumes `fixes` is always present throws on the common no-fix diagnostic, so the spec sentence must say "absent" and not leave it implied.

**Q2. Vote:** A
**Reasoning:** One `help:` line per fix, with the E0521 marker on a suggestion, adds one line per fix and reuses a label and wording that already exist. A second `fix:` line per fix doubles the lines for no new information. One label is cheaper to emit and to parse.
**Concern:** If the `fix:` line from today is dropped, scripts that parse the terminal form for the edit text lose it, so the exact `help:` wording needs a golden test.

**Q3. Vote:** A
**Reasoning:** I proposed the cap in Phase A. No diagnostic has more than two fixes, so the cap solves nothing today, and it makes the terminal and JSON list different fixes. I withdraw it. One fewer rule to implement and test.
**Concern:** A future diagnostic with many fixes (for example one fix per candidate import) floods the terminal, and the spec then needs a cap by a later change.

**Q4. Vote:** A
**Reasoning:** Each diagnostic's spec text already sets its order (E0319, W0610, E0844). A general "machine first" rule adds a constraint that no current diagnostic breaks, and it would forbid a diagnostic that rightly prefers a suggestion. The compiler stores the order the emitter writes; no sort step is needed.
**Concern:** Without a general rule, a diagnostic can list a suggestion first, and the LSP then marks no fix as preferred; that is correct but may surprise a user.

**Q5. Vote:** C
**Reasoning:** C names both facts (order of preference, applicability per fix) and points to §8.6, where the rule lives, so the principle does not repeat the field values. It stays accurate if the enum changes. The wording is short and uses no figure of speech.
**Concern:** A and C differ little; the risk is that a reader takes "order of preference" as a score, so §8.6 must say the first fix is the preferred one.

**Q6. Vote:** A
**Reasoning:** `blink fix` changes source files, so the safe default for an unknown value must be "do not apply". Stating the consumer rule in one sentence makes the check one string compare (`== "machine-applicable"`) and lets a later spec change add a value without breaking old consumers. The cost is one sentence of spec text.
**Concern:** A consumer that tests `!= "suggestion"` instead of `== "machine-applicable"` fails open on a new value, and the spec sentence cannot force the test it writes.

**Q7. Vote:** A
**Reasoning:** Leaving "never machine-applicable" beside the new `applicability` field gives the spec two vocabularies for one property, and the text then contradicts §8.6 on the day the decision lands. The edit is four short sentences plus the duplicate-declaration line. The spec is the blueprint and must be consistent when the decision merges.
**Concern:** A larger spec diff in one change is harder to review, and a missed sentence leaves a stale wording that a later chore must find.

**Web/Scripting**

**Q1. Zero fixes.**
- **Vote:** A
- **Reasoning:** I held "always present" for `d.fixes.length` without a null check. Five seats say omit, and I said I accept it if the spec states it in one sentence. A JS consumer writes `d.fixes ?? []` once. One rule matters more than which rule, and every other optional key in §8.6 is omitted when empty.
- **Concern:** Consumers that skip the `?? []` crash on every diagnostic with no fix, and the spec sentence must say "absent, never null, never empty array".

**Q2. Terminal label for a fix.**
- **Vote:** A
- **Reasoning:** `help:` is the label a developer already knows from rustc and from E0521 in this spec. Using `fix:` for a second label means two prefixes to learn and a question of which one is "the real advice". One label plus a `(not machine-applicable)` marker is the 5-minute version.
- **Concern:** A reader may scan past a `help:` line that carries a text edit and not see it as an applicable fix, so wording of the line must name the edit.

**Q3. Cap on terminal fixes.**
- **Vote:** A
- **Reasoning:** No diagnostic has more than two fixes. A cap is a rule for a case that does not exist, and "(n more in --json)" sends a human to a second tool to see a fix. The terminal and JSON must list the same fixes.
- **Concern:** If a diagnostic ever lists many fixes, the terminal output gets long, and we will need a cap then.

**Q4. Order of fixes.**
- **Vote:** A
- **Reasoning:** E0319, E0844 and W0610 already put the preferred fix first, and the compiler cannot break that. A general "machine first" rule adds text for no case and would force a suggestion down even when a diagnostic wants it first. One rule, "first is preferred", is enough.
- **Concern:** A later diagnostic may list a suggestion first, and `isPreferred` then goes unset, so the editor shows no preferred fix.

**Q5. Principle 7 replacement sentence.**
- **Vote:** A
- **Reasoning:** "lists them in order, preferred first, and marks which are machine-applicable" says what the reader sees in plain words and four seats already back it. Option B drops "preferred first", which is the one fact a developer needs. Option C is longer for no extra content.
- **Concern:** "marks which" in a principle can read as a promise of a visible mark in every output format, so §8.6 must define the mark.

**Q6. Missing or unknown `applicability`.**
- **Vote:** A
- **Reasoning:** A tool author reads one sentence and knows the safe default: apply only on an exact match. It stops a typo or a future value from becoming an unsafe auto-edit. It costs one line, and it lets a later revision add a value without breaking old consumers.
- **Concern:** A consumer that ignores the rule and tests `!== "suggestion"` applies unknown values, and the spec cannot enforce that.

**Q7. Rewrite of "never machine-applicable" in the four sections.**
- **Vote:** A
- **Reasoning:** I said "chore after the vote" in B1. I change my vote: the edit is four short sentences, and a spec that says "never machine-applicable" next to an `applicability` field has two vocabularies on the page the day it lands. A person who reads E0319 first sees a concept that §8.6 no longer uses. Doing it in the same change costs little and leaves no gap.
- **Concern:** The same-change edit may miss a section with similar wording that the sweep does not find, so the change needs a grep for "never machine-applicable" and "suggestion only".

**PLT**

**Q1. Zero fixes**
- **Vote:** A
- **Reasoning:** An absent key and an empty array state the same fact, so the schema should allow one form. Omission keeps the common diagnostic short, and a consumer must handle an absent key for older output anyway. One form is a smaller grammar.
- **Concern:** A consumer written as `d.fixes.length` throws on a missing key, so the spec sentence must say "absent, never `[]` or `null`" or implementations will drift.

**Q2. Terminal label for a fix**
- **Vote:** B
- **Reasoning:** `help:` is the short advice line and `fix:` is the edit; the terminal already prints a `fix:` line today, so B keeps the two roles apart and adds only the marker. `help:` for every fix would mix advice with edits under one label. Marking the suggestion with `fix (not machine-applicable):` keeps the applicability tag next to the word that names the kind of content.
- **Concern:** Two label spellings (`fix:` and `fix (not machine-applicable):`) are one more format that tools scraping the terminal must match.

**Q3. Cap on terminal fixes**
- **Vote:** A
- **Reasoning:** The terminal and the JSON must list the same fixes, or the output depends on the channel. A cap hides a fix by count instead of by kind, and no diagnostic has more than two fixes. A rule for a case that does not exist has no test.
- **Concern:** A diagnostic with many fixes could flood the terminal, and the spec has no answer ready.

**Q4. Order of fixes**
- **Vote:** A
- **Reasoning:** Order is a property of each diagnostic's spec text (E0319, W0610, E0844 already fix it). A general "machine first" rule constrains diagnostics that may rightly prefer a suggestion, and the compiler cannot break it today, so it needs no text. `isPreferred` is already safe: it goes on the first fix only when that fix is machine-applicable.
- **Concern:** With no general rule, a future diagnostic can put a suggestion first and its machine-applicable fix gets no `isPreferred`, which surprises an editor user.

**Q5. Principle 7 replacement sentence**
- **Vote:** A
- **Reasoning:** "Lists them in order, preferred first, and marks which are machine-applicable" states both facts the consumer needs, order and flag, in plain words. It names no enum spelling, so the principle stays valid if §8.6 changes. I withdraw my Phase A wording; four seats converged on this one.
- **Concern:** "Marks" is loose, and a reader may expect a visible mark in every output channel; §8.6 must carry the exact rule.

**Q6. Missing or unknown `applicability` value**
- **Vote:** A
- **Reasoning:** The list answers min's safety argument only with a fail-closed rule: a consumer applies a fix only when the value equals `"machine-applicable"`. That rule is also the extension rule, because a later spec revision can add a value and an old consumer treats it as not applicable. Without the sentence, a consumer may default a missing value to apply, and the type is no longer total in the sense that matters.
- **Concern:** A consumer that reads `applicability != "suggestion"` instead of `== "machine-applicable"` passes the spec text and still applies an unknown value.

**Q7. Rewrite of "never machine-applicable" wording**
- **Vote:** A
- **Reasoning:** If the §8.6 change lands and E0319, W0610, W0611, W0707 and the duplicate-declaration text still say "never machine-applicable", the spec has two vocabularies for one property and they can diverge. The edit is a few sentences, so one change keeps the spec consistent at every commit. A separate chore leaves a window where the spec contradicts itself.
- **Concern:** A larger spec diff is harder to review, and a missed sentence will still contradict §8.6 after the change lands.

**DevOps**

**Q1. Zero fixes.**
**Vote:** A
**Reasoning:** An absent key and an empty array state the same fact, so one form is enough. Omit keeps the common diagnostic short, and a consumer tests `has("fixes")` once. The spec says it in one sentence.
**Concern:** A consumer that reads `d.fixes.length` without a guard throws on the common case of no fix.

**Q2. Terminal label for a fix.**
**Vote:** B
**Reasoning:** The terminal today prints `help:` as the short line and `fix:` for the edit. Option B keeps both lines and adds one label, `fix (not machine-applicable):`, for a suggestion. A person and a script that greps the output can then tell the preferred, applicable fix from a suggestion by the label prefix. Reusing `help:` for every fix would make the short line and the edit lines look the same.
**Concern:** E0521 already prints `help: ... (not machine-applicable, ...)`, so the terminal has two labelling styles until E0521 moves to `fix (not machine-applicable):`.

**Q3. Cap on terminal fixes.**
**Vote:** A
**Reasoning:** The terminal and the JSON must list the same fixes. No diagnostic has more than two, so a cap solves no case and adds a rule plus a `(n more in --json)` string to test and format.
**Concern:** A future diagnostic with many fixes floods the terminal, and the spec then needs a cap anyway.

**Q4. Order of fixes.**
**Vote:** A
**Reasoning:** Each diagnostic's spec text already sets its order, and the first fix is the preferred one. A general "machine first" rule gives no new action, and it would force W0610-style diagnostics to put a worse fix first. The LSP rule (`isPreferred` only on a machine-applicable first fix) already protects the consumer.
**Concern:** With no general rule, a diagnostic can list a suggestion first and its machine-applicable fix second, and the user gets no preferred fix in the editor.

**Q5. Principle 7 replacement sentence.**
**Vote:** A
**Reasoning:** "Lists them in order, preferred first, and marks which are machine-applicable" names the order, the preferred fix, and the flag in one clause. It uses the same words as the §8.6 text, so a reader greps one term.
**Concern:** The sentence does not point to §8.6, so a reader of the philosophy section has no link to the shape.

**Q6. A missing or unknown `applicability` value.**
**Vote:** A
**Reasoning:** The fail-closed consumer rule is the only text that stops a missing flag from reading as machine-applicable. It also lets a later spec revision add a value without breaking old consumers. A required field with no consumer rule leaves each tool to guess.
**Concern:** Consumers that skip a fix with an unknown value hide it from the user without a message, so the compiler and tools must test this case.

**Q7. The rewrite of "never machine-applicable" in E0319, W0610, W0611, W0707 (and duplicate declaration).**
**Vote:** A
**Reasoning:** I changed my B1 position. The spec is the blueprint, and stale text in four sections would contradict the new §8.6 in the same commit that lands it. The edit is text only, with no compiler work, so a separate chore adds a ticket and a window with two vocabularies for no gain.
**Concern:** The rewrite touches five sections in one change, and a missed site leaves the old wording, so the writer must grep for "never machine-applicable" before landing.

**AI/ML**

**Q1. Zero fixes.**
**Vote:** A
**Reasoning:** An empty array and an absent key state the same fact, so the spec needs only one form. A model that learns from the spec alone writes `d.get("fixes")` once and handles both. One rule means fewer decision points.
**Concern:** A consumer that reads `fixes[0]` without a presence check fails on every diagnostic that has no fix.

**Q2. Terminal label for a fix.**
**Vote:** A
**Reasoning:** E0521 already prints `help:` with `(not machine-applicable)`, so a model finds one pattern in the spec and in the output. `fix:` and `help:` as two labels per diagnostic double the lines and add a case to learn. The label text matches the JSON value, so one term serves both.
**Concern:** A suggestion and the short `help` line can both print under `help:`, and a reader can take one for the other.

**Q3. Cap on terminal fixes.**
**Vote:** A
**Reasoning:** No diagnostic has more than two fixes, so a cap solves no case today and adds a rule to learn. A model or person that reads only the terminal must see every fix that the JSON holds.
**Concern:** A diagnostic with many fixes later prints a long block, and the spec has no rule to cut it.

**Q4. Order of fixes.**
**Vote:** B
**Reasoning:** One rule, "fixes[0] is the safe default", lets a model take the first fix with no check of `applicability`. Today every diagnostic already satisfies it, so the rule costs nothing and stops a later diagnostic from putting a suggestion first. It also makes `isPreferred` and "first machine-applicable" the same fix.
**Concern:** A diagnostic that wants a suggestion as its preferred fix (W0610-style) cannot say so, and that forces an awkward order or a spec exception.

**Q5. Principle 7 replacement sentence.**
**Vote:** B
**Reasoning:** "in preference order, each marked with its applicability" uses the field name, so a model that reads Principle 7 maps it to the JSON key with no gloss. The sentence is also the shortest of the three that name the field. A and C add wording without new information.
**Concern:** The sentence says "applicability" and not "machine-applicable", so a reader of Principle 7 alone does not see the two values.

**Q6. A missing or unknown `applicability` value.**
**Vote:** A
**Reasoning:** The rule fails closed in one sentence, and a model that writes a consumer from the spec alone gets the safe behaviour without a guess. It also lets a later spec revision add a value with no break for old consumers.
**Concern:** A producer that misspells the value silently gets a fix that `blink fix` never applies, and nothing reports the error.

**Q7. Rewrite of "never machine-applicable".**
**Vote:** A
**Reasoning:** If the old wording stays, the spec has two vocabularies for one fact, and a model that learns from it sees a conflict. The edit is a few lines, so one spec change can carry it. A later chore leaves a window where the spec contradicts itself.
**Concern:** The decision spec change grows, and a review of it can miss one of the five locations.

**Minimalism**

**Q1. Zero fixes**
**Vote:** A
**Reasoning:** An absent key and an empty array state the same fact, so one form is enough. Omission matches the other optional keys in section 8.6 and keeps the common error line short. The spec states it in one sentence.
**Concern:** A consumer that reads `d.fixes.length` without a presence check will throw on a diagnostic with no fix.

**Q2. Terminal label for a fix**
**Vote:** A
**Reasoning:** E0521 already prints `help:` with `(not machine-applicable)`, so this adds no new label. Option B adds a second line kind (`fix:` and `fix (not machine-applicable):`) next to the short `help:` line, which is new surface for the same content. One existing label is the smaller change.
**Concern:** The `help:` line and the fix text can read as duplicates when a fix repeats the help advice.

**Q3. Cap on terminal fixes**
**Vote:** A
**Reasoning:** No diagnostic has more than two fixes. A cap is a rule for a case that does not exist, and it makes the terminal and JSON disagree. Add a cap when a diagnostic needs one.
**Concern:** A future diagnostic with many fixes will print a long block, and the cap rule will then arrive as a separate spec change.

**Q4. Order of fixes**
**Vote:** A
**Reasoning:** Each diagnostic's own spec text already sets its order (E0319, W0610, E0844), and none breaks "machine-applicable first". A general rule that the compiler cannot break needs no text, and it would forbid a diagnostic that wants a suggestion first.
**Concern:** With no general rule, a new diagnostic can put a suggestion first and leave `isPreferred` unset on every fix.

**Q5. Principle 7 replacement sentence**
**Vote:** A
**Reasoning:** The devops sentence says the two facts a reader needs, order and which fixes are machine-applicable, in the fewest words. It matches the section 8.6 vocabulary. B and C say the same with more words.
**Concern:** "Preferred first" in Principle 7 and the per-diagnostic order text in the catalog can drift apart.

**Q6. Missing or unknown `applicability` value**
**Vote:** A
**Reasoning:** I conceded Option 1 only if a flag cannot default to safe-to-apply. One sentence makes that rule fail closed: only the exact value `"machine-applicable"` applies. It costs one sentence and closes the case that Option 2 handled by key name. It also lets a later revision add a value safely.
**Concern:** A fail-closed consumer that meets a new value in a later revision will silently skip a fix, and nothing tells the user.

**Q7. Rewrite of "never machine-applicable"**
**Vote:** A
**Reasoning:** A stale sentence in E0319, W0610, W0611, W0707 and the duplicate-declaration text would contradict section 8.6 on the day the decision lands. Spec text leads, so the rewrite belongs in the same spec change. A later chore leaves two vocabularies in the spec between the two commits.
**Concern:** The spec change grows to touch five sections, and a missed sentence can still survive review.

#### Phase D — Round 2

Q1, Q3, Q6 and Q7 were settled in Phase C. Q4 stood at A 5-1 (AI/ML dissent) and was not reopened. Q2 (A 4, B 2) and Q5 (A 4, B 1, C 1) went to a focused debate (D1), then a silent re-vote (D2).

**D1 — focused debate**

**Systems**

**Q2. I hold A.**
devops C: "`fix:` ... keeps both lines and adds one label ... Reusing `help:` for every fix would make the short line and the edit lines look the same." plt: "`help:` for every fix would mix advice with edits under one label."

I think this is wrong. A fix `description` is advice. The edit is its payload. One `help:` line that names the edit, in E0521 style, carries both, and it does not repeat the short line as a second `fix:` line. B also costs more: it adds two label spellings (`fix:` and `fix (not machine-applicable):`). devops's own Concern says the terminal then has two labelling styles until E0521 moves. A uses the one style that exists in the spec today, so nothing has to move. The cost of B is one more format for scripts to match, as plt's Concern says. If the wording of the `help:` line names the edit (web's Concern), A loses nothing.

**Q5. I change my vote from C to A.**
The difference between C and A is small. C adds the pointer "(§8.6)". devops's Concern says A lacks it. A pointer from a principle to a section is a small gain, and it can break when sections move. Four seats back A, and A uses the same words as §8.6 ("preferred first", "machine-applicable"). I accept A. aiml's B is the one I oppose: "applicability" names a field in a principle, and the principle then depends on a JSON key name.

**Web/Scripting**

**Q2. I hold A.** I do not change my vote.

devops: "Reusing `help:` for every fix would make the short line and the edit lines look the same." That is not a fault. Every fix line is advice about how to fix the error, and each one names the edit, so one label is correct for all of them. A developer already knows `help:` from rustc and from E0521 in this spec. B adds two new label spellings, `fix:` and `fix (not machine-applicable):`, and devops' own concern shows the cost: with B the terminal has two labelling styles until E0521 moves. A has one style from day one, and E0521 needs no change. The marker `(not machine-applicable)` already tells a reader which fix `blink fix` skips. Script authors read the JSON, not the terminal.

**Q5. I hold A.** I do not change my vote.

aiml: "The sentence says 'applicability' and not 'machine-applicable', so a reader of Principle 7 alone does not see the two values." B has the same fault in reverse: it drops "preferred first", the one fact a developer needs from the principle. A says "marks which are machine-applicable", which uses the spec's own words and the JSON value, so a reader can find it with one search. A principle should not name a JSON key. Against sys's C: "order of preference" is longer than "preferred first" and adds a pointer that §8.6 already gives.

**PLT**

**Q2. I hold B.**
Wrong argument, from sys: "A second `fix:` line per fix doubles the lines for no new information." B does not add a line per fix. Today the terminal already prints one `help:` line (the short advice) and one `fix:` line (the edit); B keeps that and adds the marker. A prints the same two things under one label, so `help:` names two different kinds of content. aiml's own concern says it: "a reader can take one for the other". min and web call `fix:` a new label; it exists in the compiler's output today (`fix: insert `..` ...`), so A is the change and B is the status quo.
I do not change my vote.

**Q5. I hold A.**
Wrong argument, from aiml: the shortest wording that "uses the field name" is better, because a model "maps it to the JSON key with no gloss". A principle should not name a field of one section; if §8.6 renames `applicability`, Principle 7 goes stale. B also drops "preferred first", the one fact the order carries. sys's C is sound but longer, and "order of preference" is the phrasing sys itself fears readers take as a score. A says "marks which are machine-applicable", the exact words §8.6 and the catalog use.
I do not change my vote.

**DevOps**

**Q2. I hold B.**

sys says: "A second `fix:` line per fix doubles the lines for no new information." This is wrong. Option B does not add a line per fix. The diagnostic keeps one short `help:` line. Each fix prints one `fix:` line, as the terminal does today (`fix: insert `..` at 5:17`). Option A prints the same number of lines, but gives the short advice and the edit the same label.

aiml names the cost in its own concern: "A suggestion and the short `help` line can both print under `help:`, and a reader can take one for the other." In Option B, `help:` is advice and `fix:` is an edit. A reader or a script finds the edit by its label.

min and web say E0521 already uses `help:`. That is true. E0521 moves to `fix (not machine-applicable):` in the same change, so one style remains. Today's terminal already prints `fix:`; Option A removes a label that exists, and Option B keeps it.

I do not change my vote.

**Q5. I hold A.**

aiml says: "the sentence says 'applicability' and not 'machine-applicable', so a reader of Principle 7 alone does not see the two values." That is the fault of Option B, and it is not a reason for B. Option B also drops "preferred first", the one fact that tells a reader which fix to take. A has both facts in plain words and uses the §8.6 spelling "machine-applicable".

sys's Option C points to §8.6, but the section number in a principle goes stale. A has no number to maintain.

I do not change my vote.

**AI/ML**

**Q2. I hold A.**
plt: "`help:` for every fix would mix advice with edits under one label." This is wrong. The E0521 line already puts the description and the edit text in one `help:` line, so one label carries both and a reader sees no mix. devops: "the terminal has two labelling styles until E0521 moves". This argues for A: A adds no second style, and B creates the split it names. B needs two label spellings (`fix:` and `fix (not machine-applicable):`) next to `help:`. A model that learns the format from the spec has one more pattern to learn and to emit. In A, the words `(not machine-applicable)` match the JSON value `"machine-applicable"`, so the terminal and JSON use one term.

**Q5. I change my vote from B to A.**
web: "Option B drops 'preferred first', which is the one fact a developer needs." This is right. My B wording says "preference order", which a model can read as a score, the idea we delete. A says "preferred first" in plain words, and `fixes[0]` follows from it directly. A also uses the same term as the §8.6 text. Four seats back A, and I have no argument left against it.

**Minimalism**

**Q2. I hold A.** No change.
devops says B keeps the two roles apart, and that "Reusing `help:` for every fix would make the short line and the edit lines look the same." That argument is wrong for two reasons. The `(not machine-applicable)` marker already tells a suggestion from a fix. And B does not give one style: devops' own Concern admits "the terminal has two labelling styles until E0521 moves". E0521, W0707 and the handler clauses print `help:` today. B asks every one of them to change to `fix (not machine-applicable):`, and it adds a second line kind. A changes none of them.
plt says `help:` for every fix would "mix advice with edits under one label". A fix `description` is advice. The edit text is its detail on the same line, so there is no mix.

**Q5. I hold A.** No change.
aiml says B maps to the JSON key "with no gloss". That is the flaw: a principle should not name a field. B also drops "preferred first", the one fact a reader needs about order, and it says "applicability" without the word "machine-applicable" that every other section uses. sys's C adds a pointer to section 8.6 and extra words. The principle can state the two facts and leave the rule to section 8.6.

After D1: Q2 stood A 4, B 2. Q5 stood A 6 (Systems moved C to A, AI/ML moved B to A).

**D2 — silent re-vote (Q2 and Q5)**

Result: Q2 A 4-2 (DevOps and PLT dissent, unchanged from Phase C). Q5 A 6-0.

**Systems**

**Q2. Terminal label for a fix.**
**Vote:** A
**Reasoning:** The compiler must print each fix once, with one label that exists today in E0521. Option A needs no change to E0521, W0707 or the handler clauses, and it emits one line per fix with one format string. Option B adds two label spellings to emit and to test, and it moves E0521 for no new information. The edit text sits in the same line as its description, so no content mixes.
**Concern:** If the `fix:` line is dropped, scripts that scrape the terminal for the edit text lose it, so the `help:` wording must name the edit and a golden test must pin it.

**Q5. Principle 7 replacement sentence.**
**Vote:** A
**Reasoning:** I moved from C to A in D1. A says "preferred first", which gives `fixes[0]` a direct reading and costs no sort step, and it uses the §8.6 words "machine-applicable". The "(§8.6)" pointer in C adds words and can go stale.
**Concern:** "Marks which are machine-applicable" can read as a promise of a visible mark in every output channel, so §8.6 must define the mark exactly.

**Web/Scripting**

**Q2. Terminal label for a fix.**
- **Vote:** A
- **Reasoning:** A developer already knows `help:` from rustc and from E0521 in this spec. Option A adds no label and moves no existing diagnostic. Option B adds two spellings (`fix:` and `fix (not machine-applicable):`) and forces E0521, W0707 and the handler clauses to change. devops and plt say `fix:` is today's output, but the spec has no `fix:` terminal rule to keep, and the spec is the blueprint. A fix `description` is advice, so one label is correct.
- **Concern:** A reader may scan past a `help:` line that carries a text edit, so the wording of each line must name the edit.

**Q5. Principle 7 replacement sentence.**
- **Vote:** A
- **Reasoning:** "Lists them in order, preferred first, and marks which are machine-applicable" gives the two facts a developer needs in plain words. It uses the §8.6 spelling and names no JSON key. sys and aiml now hold A, so it is 6 of 6 on content. B drops "preferred first", and C adds a section pointer that goes stale.
- **Concern:** "Marks which" can read as a promise of a visible mark in every output channel, so §8.6 must define the mark.

**PLT**

**Q2. Terminal label for a fix**
**Vote:** B
**Reasoning:** The diagnostic has two kinds of content: the short advice (`help`) and the fix (description plus edit). Distinct kinds get distinct labels, so a reader or a script finds the edit by its label and tells a suggestion from an applicable fix by the label prefix. The terminal prints `fix:` today, so B keeps the status quo and adds only the marker. The "one style" argument for A holds only if E0521, W0707 and the handler clauses stay on `help:`; B moves them once, in the same spec change that Q7 already authorizes.
**Concern:** If A wins, a suggestion's `help:` line and the short `help:` line share one label, and a reader or a terminal-scraping tool cannot tell advice from an edit by label alone.

**Q5. Principle 7 replacement sentence**
**Vote:** A
**Reasoning:** "Lists them in order, preferred first, and marks which are machine-applicable" states the two facts a reader needs, and it uses the exact words of §8.6 and the catalog. It names no JSON key and no section number, so the principle cannot go stale if §8.6 changes. B drops "preferred first", and C adds a pointer that can break.
**Concern:** "Marks" does not say where the mark appears, so §8.6 must define it in the JSON and in the terminal.

**DevOps**

**Q2. Terminal label for a fix.**
**Vote:** B
**Reasoning:** The terminal prints `help:` as the short advice line and `fix:` as the edit today, so B keeps both roles under their own labels and adds only the marker `fix (not machine-applicable):`. A reader, a grep, or a golden test finds the edit by its label prefix, and a suggestion differs from a machine-applicable fix by the label alone. A merges advice and edit under `help:`, so a diagnostic with two fixes prints three `help:` lines that serve two purposes. The cost of B is one change to E0521 text, which is a single golden update; A removes a label that the compiler prints now.
**Concern:** If A wins, the terminal has no stable prefix that marks an edit, and tools and models that scrape terminal output must tell advice from edits by wording.

**Q5. Principle 7 replacement sentence.**
**Vote:** A
**Reasoning:** "Lists them in order, preferred first, and marks which are machine-applicable" gives the order, the preferred fix, and the flag in the spec's own words, with no field name or section number that can go stale. I accept the D1 point that A and C differ only by the pointer, and that B drops "preferred first". Four seats and now six back A.
**Concern:** "Marks" can read as a promise of a visible mark in every channel, so §8.6 must define the mark for JSON, terminal, and LSP.

**AI/ML**

**Q2. Terminal label for a fix.**
**Vote:** A
**Reasoning:** One label with one marker is one pattern for a model to learn from the spec and to emit. E0521 already prints `help:` with `(not machine-applicable)`, so A needs no change to existing text, and B adds two label spellings. The marker words match the JSON value `"machine-applicable"`, so the terminal and the JSON use one term.
**Concern:** A suggestion and the short advice line both print under `help:`, so a reader can take one for the other unless the fix line names its edit.

**Q5. Principle 7 replacement sentence.**
**Vote:** A
**Reasoning:** "Lists them in order, preferred first, and marks which are machine-applicable" gives the order, the preferred fix and the flag in plain words, and it matches the words of §8.6. My B wording ("preference order") can read as a score, which this decision removes. A names no JSON key, so the principle does not go stale if §8.6 renames the field.
**Concern:** The sentence has no pointer to §8.6, so a model that reads only Principle 7 must search for the field name.

**Minimalism**

**Q2. Terminal label for a fix.**
**Vote:** A
**Reasoning:** A adds no new label and no new line kind: `help:` with `(not machine-applicable)` is the E0521 form that the spec has today. B adds two label spellings (`fix:` and `fix (not machine-applicable):`) and forces E0521, W0707 and the handler-clause text to move, so it adds surface and replaces nothing. The marker already separates a suggestion from a fix, and a script reads the JSON, not the terminal. If the compiler prints a `fix:` line today, that is current output, not spec text, and the spec leads.
**Concern:** The short `help:` line and a fix line can read as duplicates, so the fix line must name the edit.

**Q5. Principle 7 replacement sentence.**
**Vote:** A
**Reasoning:** "Lists them in order, preferred first, and marks which are machine-applicable" gives the two facts a reader needs, in the spec's own words, and names no JSON key. B drops "preferred first" and ties a principle to a field name. C adds a section pointer that goes stale and gains no content.
**Concern:** "Preferred first" in Principle 7 and the per-diagnostic order text in the catalog can drift apart.

### Final Spec

**Shape.** A diagnostic has one optional `fixes` array, in order, preferred first. Each fix has `description`, `applicability` and a non-empty `edits` array (the §8.6 shape). `applicability` is `"machine-applicable"` or `"suggestion"`, is required, and has no third value. The `fix` and `assist` keys go away. Advice with no edit stays in `help`.

**No fix.** The `fixes` key is absent. It is never `null` and never `[]` (Q1, 6-0).

**Consumers.** A consumer applies a fix only when `applicability` equals `"machine-applicable"`. A missing or unknown value is not applicable (Q6, 6-0). The fixes of one diagnostic are alternatives: `blink fix` applies the first machine-applicable fix of a diagnostic and skips the rest of it. The LSP maps a machine-applicable fix to `quickfix` and a suggestion to `refactor.rewrite`, and sets `isPreferred` only on `fixes[0]`, and only when it is machine-applicable.

**Order.** Each diagnostic's own text sets the order. No general rule puts machine-applicable fixes first (Q4, 5-1).

**Terminal.** The terminal prints every fix as a `help:` line that names its edit, with `(not machine-applicable)` after the description of a suggestion, the E0521 form (Q2, 4-2). It has no cap (Q3, 6-0). The `fix:` line goes away.

**Principle 7.** "lists them in order, preferred first, and marks which are machine-applicable" replaces "enumerates them with confidence scores" (Q5, 6-0).

**Wording.** E0319, W0610, W0611, W0707, the duplicate-declaration text and the handler clauses say `applicability` in the same change, in place of "never machine-applicable" (Q7, 6-0).

Example, E0319 with two fixes. The JSON lists both in `fixes`, and the first is machine-applicable. The terminal prints:

```
  = help: add `..`:
          Point3 { x, y, .. }
  = help: write `z: _` for the left-out field (not machine-applicable):
          Point3 { x, y, z: _ }
```

### Dissent

- **Q2 (DevOps, PLT).** Both wanted `fix:` for an edit and `fix (not machine-applicable):` for a suggestion, with `help:` as the short line. PLT's last words: "If A wins, a suggestion's `help:` line and the short `help:` line share one label, and a reader or a terminal-scraping tool cannot tell advice from an edit by label alone." The spec answers this in part: each fix line names its edit, and a golden test pins the wording.
- **Q4 (AI/ML).** AI/ML wanted machine-applicable fixes before suggestions. Last words: "A diagnostic that wants a suggestion as its preferred fix (W0610-style) cannot say so, and that forces an awkward order or a spec exception." The ruling gives the order to each diagnostic's own text.

### AI-First Review

Score 4/5. Learnability, consistency, generability and debuggability pass: one list, one item shape and one enum replace two keys; the terminal and the JSON show the same fixes; the consumer rule is one string compare. Token efficiency is the small cost: every fix carries a key for `applicability`, and a diagnostic with two fixes prints two fix lines.

### Open points

- About 20 other terminal examples in `sections/` still show a `= fix:` line. Each one needs a reading for its own diagnostic, so this change rewrites only the E0319 and E0525 example.
- The spec does not say whether the short `help:` line of a diagnostic prints beside its fix lines.
- The compiler emits `fix` and `assist` today and prints a `fix:` line. The spec leads the compiler here.

