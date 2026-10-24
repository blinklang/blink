[< All Decisions](../DECISIONS.md)

# An Arm With E0308 Is a Bad Arm — Design Rationale

§3.5 *Exhaustiveness* says that an arm with a bad pattern covers nothing, and lists the errors that make a bad arm:
`NoSuchVariant` (E0547), the pattern `TypeError` (E0300) errors, `NoSuchField` (E0525) and `DuplicateField` (E0316).
The list did not name `EnumPatternNeedsEnumScrutinee` (E0308), which a bare variant name gets on a type that is not
an enum: a builtin scalar, a struct, a tuple or a type parameter. The compiler already treated an unguarded E0308 arm
as a bad arm, so the spec and the compiler disagreed in text only.

```blink
fn f[T](x: T) -> Int {
    match x {
        None => 0          // E0308 only today
    }
}

fn g[T](x: T) -> Int {
    match x {
        None if true => 0  // E0308 and E0004 today
    }
}
```

The question was whether an arm with E0308 is a bad arm, and so whether E0004 may appear beside it.

## Summary

| Q | Question | Result | Vote |
|---|---|---|---|
| Option | Is an arm with E0308 a bad arm? | Option 1: yes. The three consequences of §3.5 apply unchanged; E0308 joins the named list right after E0547; the list stays normative | 6-0 in Phase B (aiml dropped its fallback) |
| Q1 | A criterion sentence next to the list | A: one sentence as a guide; the list governs | 5-1 (Minimalism dissent: B) |
| Q2 | Wording of that sentence | B: "An error is a bad-arm error when the user cannot repair it without changing which values the arm matches." | 6-0 after Phase D (Phase C: A 3, C 2, B 1) |
| Q3 | Detail after the code name in the list | Wording to the writer | 3-3 after Phase D: A (sys, devops, aiml) vs B (web, plt, min) |

Points all six seats stated, not balloted: Option 1; the consequences at §3.5 (an unguarded bad arm turns off E0004,
a guarded one does not, no unreachable report for the bad arm itself) apply unchanged; the list stays normative;
E0308 goes after E0547; the four non-enum types are not listed again in the bad-arm list (the rule in *Bare names:
variant or binding* and the paragraph on a type that is not an enum hold them).

### Compiler behavior before the decision

gen1 matched Option 1. An unguarded `None => 0` on a type parameter `T` gives E0308 only. `None if true => 0` gives
E0308 and E0004. rustc 1.99 on `match x { Some(y) => y, }` with `x: i32` prints E0308 and no E0004. No compiler
change is needed.

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in independent-proposal →
debate → vote → focused-debate → re-vote rounds.

#### Phase A — Independent proposals

All six seats proposed that an arm with E0308 is a bad arm. Excerpts, with attribution.

- **Systems:** "**Rule.** An arm whose pattern, at any depth, has an `EnumPatternNeedsEnumScrutinee` (E0308) error is
  a bad arm. This holds for a bare name or a name with a payload, on a scalar, struct, tuple or type parameter. The
  three consequences at 03_types.md:3699-3701 apply with no change" … "Lowering sees zero bad arms: any E0308 stops
  the compile before decision-tree construction. The rule has no codegen cost. It only decides which diagnostic text
  the user sees." … "Keep the named list." … "I propose a one-line rule of thumb next to the list: an error makes a
  bad arm when the pattern can never match any value of the scrutinee type. E0319 alone does not meet that test,
  because the checker repairs it by treating the pattern as if it had `..`. The list stays normative and the rule of
  thumb is a guide." Systems also wrote: "Rust reports E0308 on a mismatched pattern and also reports E0004 on a
  non-exhaustive match, because rustc still counts the arm." (Struck in Phase B, see below.)
- **Web/Scripting:** "The user who writes `None` against a type parameter or `Red` against an `Int` made a typo or a
  type mix-up. They fix the one error we show, recompile, and then see whatever comes next. If we print E0004 beside
  E0308, the second message ... is one the fix may remove, and the user cannot tell which message to act on." … "It
  would be odd to hide E0004 for `Colour.Gren` and show it for `Gren` on an `Int`." … "Keep the named list. ... But
  fix the cost of a list: the ticket exists because the list went stale when E0308 was added. Add a one-line test to
  the rule so the next author can decide without a panel: \"A pattern error makes a bad arm when the user cannot
  repair it without changing what the arm matches; it does not when the repair only adds syntax (E0319).\" This is
  the principle the list already follows, stated once. The list stays the normative text".
- **PLT:** "Coverage is defined only on well-typed patterns. The judgment `Γ ⊢ p : τ ⇝ Δ` has no derivation for `None`
  at type `T`, `Int` or `(Int, Int)`: `τ` is not an enum, so the constructor rule does not apply. A pattern with no
  derivation has no denotation. The only sound denotation that the checker may give it is the empty set of values.
  Any other choice (`_` in particular) invents coverage the user did not write." … "The spec still names every
  member. The criterion explains the list. It does not replace it."
- **DevOps/Tooling:** "E0004 beside E0308 gives the user two errors for one mistake. The E0004 text for a type
  parameter says \"matched by no arm that always runs\". The user reads that as \"add `_`\". The real fix is to change
  the pattern (`x`, `_`, a literal). The user then finds that the E0004 was a side effect." … "A named list can be
  checked by a test and by a grep." … "**Also add one sentence** under line 3699, so the test is plain: \"An error
  makes a bad arm when the user must change the pattern to fix it, and the fix can change which values the arm
  covers. E0319 does not: the checker supplies `..`.\" This explains the list. It is not a second rule. The list
  stays normative."
- **AI/ML:** "A model that writes a match learns one rule: \"any error inside an arm pattern silences E0004 for the
  unguarded arm\". A list of codes with E0308 missing is a trap." … "The rule for a reader is one test: \"Can the user
  fix this arm only by changing the pattern, so that it might then cover values?\" If yes, the arm is bad. E0319
  fails the test, because the checker already treats the pattern as if it had `..`." … "Tradeoff: the general test is
  judgment-based. Mitigation: keep the explicit list. The list is normative; the test is the guide for new errors."
  aiml also wrote a fallback, aiml-2: "E0308 is not a bad arm: Report E0004 beside E0308. ... I do not recommend it."
- **Minimalism:** "The compiler already does this. The ticket asks the spec to say so. This is the smallest change
  that makes spec and compiler agree: one name added to an existing sentence, no new concept." … "E0308 and E0547 both
  say \"this name is not a variant here\". The user's repair is open: a literal, a range, a lowercase binding (the
  compiler's own help text says \"write a lowercase name\"), or a different scrutinee. A lowercase binding covers
  everything. So an E0004 beside the E0308 may become false after the repair." … "Add no other text. The consequence
  bullets at 3699–3701 already apply."

#### Phase B — Debate highlights

The moderator's digest named Option 1 (E0308 is a bad arm, from all six Phase A files) and Option 2 (E0308 is not a bad
arm; aiml's fallback). It also gave one fact, F1: rustc 1.99.0 on `match x { Some(y) => y, }` with `x: i32` prints
`error[E0308]: mismatched types` and no E0004.

- **AI/ML:** "**Option 1 over Option 2.** All six seats agree. I drop aiml-2." "**V5: sys's claim is wrong.** F1 shows
  rustc prints E0308 and no E0004 for a pattern type error. Cite Rust as support for Option 1, not against it."
- **Systems:** "**V5: I was wrong.** F1 shows rustc gives E0308 and no E0004 on a pattern type error. My cross-language
  note is false. Strike it. Replace it with: \"Rust reports E0308 on a mismatched pattern and skips the exhaustiveness
  check.\" This supports Option 1." Systems also withdrew its own wording: "\"Can match no value of the scrutinee
  type\" is true of the E0308 arm, but it is vague for E0300 and E0525, where the pattern has a type error but a reader may not call it \"matching no value\"".
- **DevOps/Tooling:** "**Option 1 over Option 2.** Option 2 gives the user two errors for one mistake, and the E0004
  text (\"add an arm that always runs\") sends them to the wrong fix." "I oppose sys's \"can match no value of the
  scrutinee type\": E0525 and E0316 arms name a real type, so the sentence is false for them."
- **PLT:** "Option 2 gives the arm a meaning (it covers nothing) and then reports a gap that the arm's own fault caused."
  "I concede" on the position: "**V4: position.** After E0547. I concede: it groups the name-resolution faults, and my
  order has no reason."
- **Web/Scripting:** "One typo should give one error. F1 supports this: rustc prints E0308 alone." On the wording, web
  backed devops in Phase B: "I drop my own sentence and back devops".
- **Minimalism:** *(dissent on V1)* "**V1: no criterion sentence.** I keep my position. The list is normative. A second
  sentence is a second source of truth. Readers then ask whether the sentence or the list wins, and the next pattern
  error must pass both." "**V3: no shape detail.** Lines 3175 and 3249 already define when E0308 occurs. Repeating the
  four types in the bad-arm sentence makes a second place to update." "**Concession:** if the criterion sentence is
  added, state it as a reason only, and say the list governs."

Result of Phase B: Option 1, 6-0. The panel dropped the cross-language claim of sys from the text. It agreed on the
points listed under *Summary*.

#### Phase C — Final vote

- **Q1: A criterion sentence next to the list?** (5-1, Minimalism dissent). A: add one sentence as a guide; the list
  governs. B: no criterion sentence.
  - **Systems:** A — "The rule has no codegen cost; it only picks which diagnostic the user sees. Checker and spec must
    agree on one predicate, and a one-line test lets the next author of a pattern error classify it without a panel.
    The list stays normative, so the sentence adds no second rule." Concern: "A reader may take the sentence as the
    rule and the list as an example, and the two may drift; the text must say the list governs."
  - **Web/Scripting:** A — "This ticket exists because the list went stale. A short test lets the next author decide
    whether a new pattern error joins the list without a panel, and it explains why E0319 is an exception. Five seats
    want it, and min accepts it if it is a reason only and the list governs." Concern: "A second sentence can drift
    from the list, and a reader may ask which one wins, so the text must say the list governs."
  - **PLT:** A — "The list stays normative, so the sentence adds no second rule. It states why E0319 is outside the
    list and gives the next author a test for a new pattern error. Without it the E0319 exception looks arbitrary. The
    sentence says only why a code is on the list and never replaces the list, so it cannot become a second source of
    truth." Concern: "A reader may take the sentence as the rule and the list as an example, so a later pattern error
    could enter by the sentence alone."
  - **DevOps/Tooling:** A — "The ticket exists because the list went stale when E0308 was added. A compiler author who
    adds the next pattern error needs a test to decide list membership, and the LSP and diagnostic code need the same
    answer. One sentence marked as a guide costs little. It also explains why E0319 is the exception." Concern: "A
    second sentence can drift from the list, and a reader may then ask which one wins. The text must say the list
    governs."
  - **AI/ML:** A — "The list is complete for today but gives a model, or a compiler author, no test for the next
    pattern error. One short sentence costs about 25 tokens and removes that decision point. Stating it as a guide,
    with \"the list governs\", answers min's second-source-of-truth worry." Concern: "If the sentence and the list
    drift apart, readers will not know which wins; the text must say the list governs."
  - **Minimalism:** *(dissent)* B — "The list at 03_types.md:3697 is normative, and the E0319 sentence already gives
    its reason in the same paragraph. A second sentence is a second source of truth, and the five proposed wordings
    disagreed with each other until B1. The fix for the ticket is one name added to the list." Concern: "Without a test
    sentence, the next author who adds a pattern error must guess whether it joins the list, and may need another
    panel."

- **Q2: Wording of that sentence** (Phase C: A 3, C 2, B 1; re-voted in Phase D, see below). A: devops's wording, "An
  error makes a bad arm when the user must change the pattern to fix it, and the fix can change which values the arm
  covers. E0319 does not: the checker supplies `..`." B: web's wording, "An error is a bad-arm error when the user
  cannot repair it without changing which values the arm matches." C: web's sentence, then devops's second sentence.
  - **Systems:** A — "The devops sentence gives a test a reader can run on any error, and it names the E0319 exception
    in the same place, so no second lookup is needed. It is true for E0525 and E0316, where the pattern still has a
    type; my own wording was false for those. Web's sentence alone leaves E0319 unexplained." Concern: "\"The fix can
    change which values the arm covers\" is a judgment call, and a future error may be argued either way."
  - **Web/Scripting:** A — "devops's sentence gives a test a contributor can run, and it names the E0319 exception in
    the same place, so a reader needs no second lookup. My own sentence says nothing about E0319 and would leave that
    exception looking arbitrary. sys's and plt's wordings fail for E0525 and E0316, where the pattern still has a
    type." Concern: "\"the fix can change which values the arm covers\" is a judgment test, and two authors may
    classify a future error differently, so the list must stay normative."
  - **PLT:** A — "The devops sentence gives a test a reader can run: the user must change the pattern, and the fix can
    change which values it covers. It covers E0316 and E0525, where the pattern still has a type, which my own \"no
    type\" wording did not. Its second sentence names E0319 and gives the reason (the checker supplies `..`), so the
    reader needs no second lookup. Web's sentence alone omits E0319." Concern: "\"Can change which values the arm
    covers\" is a judgment test, so two authors may classify a future error differently."
  - **DevOps/Tooling:** C — "Web's sentence is the test a contributor can run on any new error. Devops's second
    sentence names the E0319 exception, so the reader needs no second lookup. Together they give the test and the one
    known edge case. Neither sentence is false for E0525 or E0316, unlike the sys and plt wordings." Concern:
    "\"Cannot repair it without changing which values the arm matches\" is a judgment test. Two authors may classify a
    future error in different ways, so the list must stay the normative text."
  - **AI/ML:** C — "Web's first sentence is a test any reader can run on any error code, with no hedge. Devops's second
    sentence (\"E0319 does not: the checker supplies `..`\") names the one exception, so a reader needs no second
    lookup. Together they give the rule and its known edge in two short sentences." Concern: "Option A or B alone would
    leave either the E0319 exception implicit (B) or a hedged first clause that is harder to test (A)."
  - **Minimalism:** B — "I vote only in case Q1 goes to A. Then the shortest sentence is best: web's states the test,
    and the E0319 clause repeats what the text before it already says. Q2-C would state E0319 twice in one paragraph."
    Concern: "Web's sentence does not name E0319, so a reader may need to read the previous sentence to see why E0319
    fails the test."

- **Q3: Detail after the code name in the list** (Phase C: A 3, B 2, D 1; re-voted in Phase D, see below). A: "(a
  variant name on a type that is not an enum, with or without a payload)". B: "(a variant name on a type that is not
  an enum)". C: "(a variant name where the type is not an enum, with or without a payload)". D: the code name only.
  - **Systems:** A — "\"(a variant name on a type that is not an enum, with or without a payload)\" tells the reader
    the shape at the point of use. It does not repeat the four non-enum types, which 3175 and 3249 hold, so only the
    payload clause can drift, and 3175 states the same fact." Concern: "The payload clause is a second copy of a fact
    stated at 3175, and it could go stale if the pattern rules change."
  - **Web/Scripting:** B — "\"(a variant name on a type that is not an enum)\" tells a reader what E0308 means in one
    short phrase. Line 3175 already says the name may have a payload, and line 3249 lists the four types, so repeating
    either here is a second copy that can drift. \"At any depth\" already covers nesting." Concern: "A reader who skips
    3175 may think a name with a payload is outside the rule, so the sentence at 3697 must not narrow the case."
  - **PLT:** B — "The parenthesis tells the reader which E0308 shape the list means. \"With or without a payload\"
    repeats 03_types.md:3175, and a repeat can drift. \"On a type that is not an enum\" is exact: the type at the
    pattern position fixes the fault, not the name's shape. My own option C differs from B only in wording, and B is
    shorter." Concern: "If 3175 later changes the set of shapes that give E0308, the short parenthesis stays true, but
    option A would go stale."
  - **DevOps/Tooling:** A — "The code name alone does not tell a user reading the spec what E0308 means in a pattern.
    The parenthesis tells them in one line, and \"with or without a payload\" matches the diagnostic surface: the same
    error fires for `None` and for `Some(y)`. The cost is a short repeat of 3175, but the repeat is a gloss and holds no
    list of types." Concern: "If the shape detail at 3175 or 3249 changes, the parenthesis in the list can go stale.
    This is a small risk because it holds no list of types."
  - **AI/ML:** A — "The parenthesis tells a reader which E0308 case the list means, and it costs about 15 tokens. \"With
    or without a payload\" prevents a model from reading the entry as bare names only. Lines 3175 and 3249 hold the full
    rule, so the four non-enum types stay out of this list." Concern: "The payload clause repeats line 3175, so the two
    places must stay in step; if the payload rule changes, this parenthesis goes stale."
  - **Minimalism:** D — "Lines 3175 and 3249 define when E0308 occurs, so the list needs only the code name. Every
    shape detail in the list is a second place to update. \"At any depth\" already covers nesting, and \"with or without
    a payload\" repeats 3175." Concern: "A reader who sees only the list sees \"EnumPatternNeedsEnumScrutinee\" and must
    follow the code to 3175 to learn its shape."

Phase C result: Q1 A 5-1. Q2: A 3 (sys, web, plt), C 2 (devops, aiml), B 1 (min). Q3: A 3 (sys, devops, aiml), B 2
(web, plt), D 1 (min). Q2 and Q3 went to a focused debate.

#### Phase D — Round 2 (Q2 and Q3)

**Focused debate (round 1).** Each seat stated its option and answered another seat. Full text, in the order the seats
answered.

- **AI/ML:** "**Q2: I change my vote from C to B.** min's point holds: the E0319 sentence (\"the checker treats the
  pattern as if it had `..`\") sits right before the new sentence in the same paragraph. Options A and C then state
  E0319 twice. My reason for C, \"a reader needs no second lookup\", fails, because the first lookup is one sentence
  up. I also answer sys, web and plt, who say \"Web's sentence alone omits E0319\" (plt) as a defect. It is not a
  defect, because the paragraph already covers E0319. B is the shortest wording and costs the fewest tokens. Devops's
  hedge \"the fix can change\" is the part I find harder to test, and B drops it." "**Q3: I hold A.** I answer plt and
  web: \"'With or without a payload' repeats 03_types.md:3175, and a repeat can drift.\" The repeat is two words with
  no list of types. A model that reads the bad-arm list alone, which is how it will often meet it, needs those two
  words to see that `Some(y)` on `Int` is in scope. The drift risk is small, and a stale clause is cheaper than a wrong
  reading. I also answer min's D: a bare code name forces a lookup for the one fact a reader needs."
- **DevOps/Tooling:** "**Q2: I hold C. No change.** The wording of A has the hedge \"and the fix can change which values
  the arm covers\". Web's first sentence has no hedge, so a contributor can test it more easily. I wrote A, and I now
  think web's test is better. I answer min: \"Q2-C would state E0319 twice in one paragraph.\" The existing E0319
  sentence says what the checker does (it treats the pattern as if it had `..`). It does not say why E0319 fails the
  test. The second sentence ties the exception to the test, so it is not a repeat. If C loses, I accept A over B,
  because B leaves E0319 outside the test." "**Q3: I hold A. No change.** I answer web: \"Line 3175 already says the
  name may have a payload, so repeating either here is a second copy that can drift.\" Web's own Concern says \"A reader
  who skips 3175 may think a name with a payload is outside the rule.\" That is the reason for A. A bad-arm list is a
  lookup table. A reader who looks up E0308 there should not need a second section to learn that `Some(y)` and `None`
  both count. I answer min (D): a bare code name in a list gives no shape, and the user who sees E0308 in the
  diagnostic cannot tell from the list that it covers a payload form. The payload clause is a gloss, not a list of
  types, so the drift risk is small."
- **Minimalism:** "**Q2: I hold B.** Q1 is decided, so the sentence exists. Two seats want devops's second sentence for
  E0319. aiml says: \"Option A or B alone would leave ... the E0319 exception implicit (B)\". That is wrong. The text at
  03_types.md:3697 already says \"`PatternMissingRest` (E0319) alone does not make a bad arm: the checker treats the
  pattern as if it had `..`\". The reason sits in the same paragraph. Option A and C state it twice, which is the second
  source of truth I argued against in Q1. web's sentence alone is the test, and the E0319 text already stands beside
  it." "**Q3: I change from D to B.** D has one vote and I see no path for it. devops says: \"The code name alone does
  not tell a user reading the spec what E0308 means in a pattern.\" The name `EnumPatternNeedsEnumScrutinee` already
  says it, and 3175 and 3249 define it. But a short gloss is cheap. B holds no payload clause, so it has no second copy
  of 3175 to drift. A has that copy. I vote B."
- **PLT:** "**Q2: I change my vote from A to B.** min's argument is right: \"Q2-C would state E0319 twice in one
  paragraph.\" The paragraph at 03_types.md:3697 already says, right after the list, that E0319 alone is not a bad arm
  because \"the checker treats the pattern as if it had `..`\". Option A's second sentence (\"E0319 does not: the
  checker supplies `..`\") repeats that. Option C repeats it too. A second statement of one fact is a second place to
  keep in step. Web's sentence is the test, and the existing E0319 sentence supplies the exception and its reason. I
  also find web's sentence easier to test than the hedged \"the fix can change\" clause in A." "**Q3: I hold B.** I
  answer aiml: \"'With or without a payload' prevents a model from reading the entry as bare names only.\" The
  parenthesis \"(a variant name on a type that is not an enum)\" names a variant, and the code applies to a variant name
  in every form. Line 3175 states the payload case. The clause adds a copy that can drift, which is the risk sys,
  devops and aiml each list as their own concern. I reject min's D: a code name alone gives no shape, and one short
  phrase costs little."
- **Systems:** "**Q2: I hold A. No change.** Wrong argument, aiml: \"a hedged first clause that is harder to test.\" The
  hedge is the test. Web's clause says the user \"cannot repair it without changing which values the arm matches.\" A
  reader cannot apply that to E0319. Adding `..` also changes nothing the user wrote, so E0319 looks like a bad-arm
  error under web's wording and needs the second sentence to correct it. Devops's first sentence has the E0319 case
  built in: the user must change the pattern, and the fix can change coverage. For E0319 the user need not change the
  pattern. On min's point, \"Q2-C would state E0319 twice\": A and C both carry devops's second sentence, so the repeat
  does not separate them. The repeat is short, and it gives the reason at the point where a reader applies the test."
  "**Q3: I hold A. No change.** Wrong argument, web and plt: \"'With or without a payload' repeats 03_types.md:3175,
  and a repeat can drift.\" A reader who sees \"a variant name\" may read bare names only, and a payload form is the
  common typo (`Some(y)` on an `Int`). The clause is a gloss of one fact and holds no list of types. If 3175 changes,
  the same edit pass fixes both lines. Min's D leaves the reader with a code name and no shape."
- **Web/Scripting:** "**Q2. I hold A (devops's two sentences).** I do not change my vote. I answer aiml: \"Option A ...
  a hedged first clause that is harder to test.\" The clause is not a hedge. \"The user must change the pattern\" is the
  condition a reader can test. \"The fix can change which values the arm covers\" says why that matters for E0004. A
  reader runs one check, not two. C's first sentence, \"cannot repair it without changing which values the arm
  matches\", is the same test with the reason cut out. I now see that the reason is what makes the test usable, because
  a reader sees why E0004 must stay off. I also keep the E0319 clause, which min's C reading drops. Min says C \"would
  state E0319 twice\". A already states it once in the new sentence and once in the old one, and the old one gives no
  test." "**Q3. I hold B.** I do not change my vote. I answer aiml: \"'With or without a payload' prevents a model from
  reading the entry as bare names only.\" A name with a payload is still \"a variant name\", and line 3175 says so in its
  first sentence. The phrase adds a second copy that can go stale, as devops, aiml and sys all state in their own
  Concern lines. I side with min on the principle, but keep the short parenthesis because a bare code name tells a
  reader nothing at the point of use."

**Changes in the focused debate.** Q2: plt A to B; aiml C to B. Q3: min D to B.

**Re-vote.**

- **Q2: Wording of that sentence** (6-0 for B; Phase C was A 3, C 2, B 1)
  - **Systems:** B — "I held A because I thought web's test would put E0319 inside the list. That was wrong. The user
    repairs E0319 by adding `..`, and the checker already treats the pattern as if it had `..`, so the repair changes no
    value the arm matches. Web's test therefore excludes E0319 by itself. The paragraph at 03_types.md:3697 already
    states E0319 and its reason, so A and C say it twice. B is the shortest and has no codegen or checker cost."
    Concern: "\"Without changing which values the arm matches\" is a judgment test, so two authors may classify a future
    error in different ways; the list must stay the normative text."
  - **Web/Scripting:** B — "The test \"cannot repair it without changing which values the arm matches\" is one clause a
    contributor can run on any error. It already gives the right answer for E0319: adding `..` changes no value the arm
    matches, so E0319 fails the test. The sentence at 03_types.md:3697 states the E0319 exception and its reason one
    line away, so A and C say it twice in one paragraph, and a reader who sees the same fact twice asks if the two
    differ. I moved off A because the extra sentence buys nothing that the paragraph does not already give." Concern:
    "The test is a judgment call, so two authors may sort a future error in different ways; the list must stay the
    normative text."
  - **PLT:** B — "The paragraph at 03_types.md:3697 already says that E0319 alone is not a bad arm and why: the checker
    treats the pattern as if it had `..`. Options A and C state that fact a second time, and a fact stated twice has two
    places to keep in step. Web's sentence is the test: an error makes a bad arm when the user cannot repair it without
    changing which values the arm matches. For E0319 the repair adds `..` and changes no value set, so the test already
    excludes it. It is also true for E0525 and E0316, where the pattern still has a type." Concern: "The test is a
    judgment call, so two authors may classify a future pattern error in different ways; the list must stay
    normative."
  - **DevOps/Tooling:** B — "In D1 I held C. I now test web's sentence on E0319: the user can repair a missing `..`
    without changing which values the arm matches, because the checker already supplies `..`. So web's sentence
    classifies E0319 correctly by itself. The exception is derivable, and the E0319 sentence one line above already
    states it. A and C repeat that fact, and the repeat is a second place to keep in step. Web's test has no hedge, so a
    contributor can apply it to a new error code." Concern: "\"Cannot repair it without changing which values the arm
    matches\" is a judgment test, so two authors may classify a future error differently; the list must stay
    normative."
  - **AI/ML:** B — "The E0319 sentence sits in the same paragraph and already says the checker supplies `..`. A model
    that reads the paragraph meets the exception once, so a second statement adds tokens and a second place to keep in
    step. Web's sentence is one test with one decision point and no hedge clause to weigh." Concern: "Web's sentence
    does not name E0319, so a reader who applies it alone may count E0319 as a bad-arm error; the existing E0319
    sentence must stay next to it."
  - **Minimalism:** B — "The paragraph at 03_types.md:3697 already says that E0319 alone is not a bad arm and why: the
    checker treats the pattern as if it had `..`. Web's sentence is the test, and that existing text supplies the
    exception. Options A and C state the E0319 exception twice in one paragraph, and each copy is a place that can
    drift. B is the shortest wording, and plt and aiml moved to it for this reason." Concern: "Web's sentence does not
    name E0319, so a reader who skips the line before it may think E0319 fails the test, and \"cannot repair it without
    changing which values the arm matches\" is a judgment test that two authors may apply in different ways."

- **Q3: Detail after the code name** (3-3: A vs B; wording to the writer; Phase C was A 3, B 2, D 1)
  - **Systems:** A — "The common typo is a payload form, such as `Some(y)` matched on an `Int`. A reader who sees only
    the list should not read the entry as bare names only. The clause is a gloss of one fact and holds no list of types,
    so the drift risk is small, and one edit pass fixes both lines if 3175 changes." Concern: "The payload clause is a
    second copy of a fact at 3175, and it can go stale if the pattern rules change."
  - **DevOps/Tooling:** A — "A bad-arm list is a lookup table. A user who sees E0308 on `Some(y)` against an `Int`
    should see in the list that payload forms count, with no second section to read. The clause is a gloss that holds no
    list of types, so the drift risk is small. The diagnostic fires for `None` and for `Some(y)`, and the list should
    say so." Concern: "The payload clause is a second copy of 03_types.md:3175, and it goes stale if the pattern rules
    change."
  - **AI/ML:** A — "A model often meets the bad-arm list alone, as a lookup table. The two words \"with or without a
    payload\" show that `Some(y)` on an `Int` is in scope, and they cost about five tokens. A stale clause costs less
    than a wrong reading, and no list of types is repeated." Concern: "If the pattern rules at 3175 change, the payload
    clause can go stale and the list will state a fact the spec no longer holds."
  - **Web/Scripting:** B — "\"(a variant name on a type that is not an enum)\" tells a reader what E0308 means in a
    pattern, in one short phrase. A name with a payload is still a variant name, and 03_types.md:3175 says so. A second
    copy of the payload rule can go stale, and a bare code name (D) sends the reader to a lookup for the one fact they
    need." Concern: "A reader who looks only at the list may think `Some(y)` on an `Int` is outside the rule, so the
    spec must keep 3175 clear and the parenthesis must not read as bare names only."
  - **PLT:** B — "The type at the pattern position fixes the fault, not the shape of the name. \"(a variant name on a
    type that is not an enum)\" says that. A payload form is still a variant name, and 03_types.md:3175 states the
    payload case. The extra clause in A adds a copy of that fact that can drift." Concern: "A reader who skips 3175 may
    think a name with a payload is outside the rule, so the list entry must not read as narrower than 3175."
  - **Minimalism:** B — "I moved from D to B in D1 and I hold B. The parenthesis \"(a variant name on a type that is
    not an enum)\" is true for every form, with or without a payload, so it needs no second copy of the payload fact at
    3175. Option A adds that copy and it can drift. The four non-enum types stay at 3175 and 3249." Concern: "A reader
    who sees only the list may think a name with a payload is outside the rule, so the spec text must not narrow the
    case."

Phase D result: Q2 B 6-0. Q3 A 3 (sys, devops, aiml), B 3 (web, plt, min). A tie on wording only goes to the writer
(BDFL process rule). No owner tiebreak was needed or used.

**Writer's reading of Q3.** Both sides name the risk of the other. Side A fears an entry that reads as bare names only.
Side B fears a copy of the payload rule at §3.5 that drifts from it. The entry reads "(a variant name on a type that is
not an enum, in any form)". "In any form" covers a payload form without copying the payload rule, and a new example
(`Some(y)` on an `Int`) shows a payload form in the list's own paragraph.

### Final Spec

```blink
fn pick(n: Int) -> Int {
    match n {
        Some(y) => y       // error[EnumPatternNeedsEnumScrutinee]; no E0004
    }
}

fn pick_guarded[T](x: T) -> Int {
    match x {
        None if true => 0  // error[EnumPatternNeedsEnumScrutinee]
    }                      // error[NonExhaustiveMatch]
}
```

- An arm whose pattern, at any depth, has `EnumPatternNeedsEnumScrutinee` (E0308) is a bad arm. The entry in the list
  follows `NoSuchVariant` (E0547).
- The three consequences of §3.5 apply unchanged: an unguarded bad arm turns off E0004 for that match, a guarded one
  does not, and the bad arm gets no `UnreachableArm` (W0710) report.
- The list stays normative. One sentence after the E0319 sentence is a guide: "An error is a bad-arm error when the
  user cannot repair it without changing which values the arm matches." The text says the list governs.
- The four non-enum types are not listed again in the list; the rule for bare names and the paragraph on a type
  that is not an enum hold them.

### Reading gaps

- The panel struck the claim of sys about Rust (F1 shows rustc prints no E0004). The spec text holds no
  cross-language note.
- The test sentence is a judgment test. All six seats state this as a concern. The spec keeps the list normative so
  that two authors need not agree on a new error.
- gen1 does not give E0004 for a guarded E0308 arm on an `Int` scrutinee (`None if true => 0` with `n: Int`). It gives
  E0004 for the same arm on a type parameter. The ruling says a guarded arm does not turn off E0004. This is a gap
  between the compiler and the rule, not a change to the rule. The spec example for a guarded arm uses a type
  parameter, which gen1 accepts as the ruling says.

