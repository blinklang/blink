[< All Decisions](../DECISIONS.md)

# The Payload Form of a Variant Pattern — Design Rationale

§3.5 said that an uppercase bare name in a pattern names a variant "with or without a payload". It did not say what
`Circle =>` means when the variant is `Circle(Int)`: match any `Circle`, or a payload-form error. It also did not say
how many sub-patterns a paren pattern needs, what a paren pattern on a `{ }` variant means, or what a payload on a
unit variant means. The compiler accepted `Circle =>` on a payload variant (it matched every `Circle`), accepted
`Circle(a)` on a two-field variant (it bound the first field), accepted `At(a, b)` on a `{ }` variant, and gave an
internal error on `Dot(x)` for a unit variant `Dot`.

```blink
type Shape { Circle(Int), Dot }

fn f(s: Shape) -> Int {
    match s {
        Circle => 1       // compiled; matched every Circle
        Dot => 0
    }
}
```

## Summary

| Q | Question | Result | Vote |
|---|---|---|---|
| Option 1 | A bare name on a payload variant | A bare name (bare or qualified) fits a unit variant only. `Circle =>` on `Circle(Int)` or on a `{ }` variant is `TypeError` (E0300). A paren pattern needs one sub-pattern for each field; too few, too many and a payload on a unit variant are E0300 with a note that lists the fields in order. No new code. No paren rest form: no `Circle(..)` | 6-0 in Phase B (Web moved from Option 2) |
| Q1 | Bad-arm status of the payload-form errors | A: every payload-form E0300 makes a bad arm; the bad-arm paragraph does not change | 4-1-1 after Phase D (Systems: B, DevOps: C) |
| Q2 | A paren pattern with the right count on a `{ }` variant | A: E0300 | 5-1 (DevOps dissent: B) |
| Q3 | Irrefutable patterns | B: the payload-form rule applies there too; one sentence is added, and a bare name with no payload still binds | 5-1 after Phase D (Minimalism dissent: A); 3-3 in Phase C |
| Q4 | `V { .. }` on a paren variant | A: legal on every variant that has a payload | 6-0 |
| Q5 | Where the text goes | A: replace the "with or without a payload" clause, and add one sentence under **Constructor.** | 4-1-1 (AI/ML: B, Minimalism: C) |
| Q6 | The fix the diagnostic names | A: `V { .. }` first, then `V(_, _)` with one `_` for each field | 5-1 (AI/ML dissent: B) |

Out of scope: construction. `Shape.At(1, 2)` on a `{ }` variant compiles today. Five seats asked for a separate
ticket, and DevOps asked the panel to decide it together with patterns. This decision writes no rule on it.

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in
independent-proposal, debate, vote rounds. Phase A and Phase B are excerpted from each panelist's own text, with
attribution. Phases C and D are quoted in full from each panelist's file, without its heading line.

#### Phase A — Independent proposals

Five seats proposed the rule that became Option 1. Web proposed Option 2: a variant name with no payload matches
every value of that variant. All six seats made the other mismatches (wrong positional count, paren pattern on a
`{ }` variant, payload on a unit variant) E0300 with a note, and asked for one ticket.

- **Systems** (`A/sys.md`):

> A variant pattern must have the payload form that the variant declares. No payload on a payload variant is an error.

> One rule means one lowering shape for every variant pattern: tag test, then one sub-pattern per declared field.

- **Web** (`A/web.md`):

> In a refutable pattern, a variant name with no payload matches every value of that variant. It binds nothing and tests nothing in the payload.

- **PLT** (`A/plt.md`):

> The bare name `V` with no payload is the unit form. It is not "any V".

- **DevOps** (`A/devops.md`):

> A bare name (`Circle`, `Shape.Circle`) names a variant with no payload, so it fits only a unit variant.

- **AI/ML** (`A/aiml.md`):

> One meaning per spelling. If `Circle =>` is legal, a model has two spellings for "any Circle" and must pick.

- **Minimalism** (`A/min.md`):

> The grammar at 03_types.md:3120 already lists four forms: bare (unit variant), paren (constructor), brace (named fields). The compiler does not enforce it.

#### Phase B — Position shifts

Facts added to the digest: `Circle { .. }` compiles on a paren variant (F1); `Circle(a, ..)` is a parse error (F2);
construction accepts `At(1, 2)` on a `{ }` variant (F3); §3.5 says a bare name with no payload binds in an
irrefutable pattern (F4).

- **Web** moved from Option 2 to Option 1 (`B1/web.md`):

> I move to Option 1. Two facts decide it. F2: my spelling `Red(_, ..)` does not parse, so Option 2 as I wrote it had no equivalent form to point at.

- **AI/ML** (`B1/aiml.md`), **PLT** (`B1/plt.md`) and **Minimalism** (`B1/min.md`) dropped a rest form in a paren pattern:

> My Phase A text `Name(_, ..)` is wrong: F2 shows `..` is a parse error in a paren pattern.

> I withdraw it. A paren variant takes exactly one sub-pattern per field (`Circle(_)`, `Rect(_, _)`).

> I add no `Circle(..)`.

- **DevOps** (`B1/devops.md`) withdrew its sentence for the irrefutable rule and its position on paren patterns:

> I withdraw my 3180 addition.

> I withdraw my position. A pattern with the right count must be legal too, or the two sides disagree.

All six seats ended Phase B with `STATUS: ready to vote`.

#### Phase C — Silent vote

The ballot gave these options. Each seat voted alone.

| Q | Options |
|---|---|
| Q1 Bad-arm status of the payload-form E0300 errors | A: every one makes a bad arm; the bad-arm paragraph does not change. B: none makes a bad arm; the checker reads the arm as the declared form, with `_` for a missing field, and ignores extras. C: too many sub-patterns makes a bad arm; the other three do not |
| Q2 `At(a, b)` on `At { x: Int, y: Int }` | A: E0300. B: legal, to match construction; only a wrong count is E0300 |
| Q3 Irrefutable patterns | A: leave the paragraph unchanged. B: the payload-form rule applies there too; add a sentence |
| Q4 `V { .. }` on a paren variant whose fields are not labelled | A: legal on every payload variant. B: legal only when every field is labelled |
| Q5 Where the text goes | A: replace part of the bare-name bullet and add one sentence under **Constructor.** B: add the rule after the bullet and one sentence under **Constructor.** that points to it. C: replace in the bullet only |
| Q6 The fix the diagnostic names | A: `V { .. }` first, for every variant. B: the declared form: `Circle(_)` for a paren variant, `Rect { .. }` for a brace variant |

The ballot also gave a fifth fact (F5): the irrefutable rule comes from a past vote, in
`decisions/variant-spelling-and-pattern-case.md`: "`let`, parameters, closure parameters and `for` are irrefutable.
Any bare name with no payload binds there, and W1011 applies as §10.6 says."

Tally after Phase C: Q1 A 4 (web, plt, aiml, min), B 1 (sys), C 1 (devops). Q2 A 5, B 1 (devops). Q3 A 3 (web, plt,
devops), B 3 (sys, aiml, min). Q4 A 6. Q5 A 4 (sys, web, plt, devops), B 1 (aiml), C 1 (min). Q6 A 5, B 1 (aiml). The
seats' votes follow, in their own words.

##### Systems (`C/sys.md`)

> **Q1. Vote: B**
> Reasoning: The arm names a known variant, so the tag test is the same after the repair. The checker can lower it as the declared form (tag test, then one sub-pattern per field, `_` for a missing one), and E0004 stays accurate: `Circle =>` plus `Dot =>` should not report a false "missing pattern". A bad arm turns off E0004 and loses a real report for no gain in codegen, because no mismatch reaches lowering.
> Concern: If A wins, a payload typo in one arm hides every real E0004 in that match until the user fixes it, and 3697 keeps no way to tell a lost match set from a miscounted one.

> **Q2. Vote: A**
> Reasoning: One declared form, one lowering shape. A positional pattern on a brace variant adds a second field-addressing path (by position and by name) to the same variant for no zero-cost gain. Construction (F3) is the odd side and goes to its own ticket.
> Concern: If A wins and construction keeps accepting `At(1, 2)`, the two sides stay out of step until the separate ticket lands.

> **Q3. Vote: B**
> Reasoning: The rule is on the pattern, not on its position, so `let Circle(a, b) = s` needs the same count and form check as a `match` arm; otherwise the checker has two paths and the lowering can meet a mismatch it never sees in `match`. F5 keeps a bare name with no payload as a binding there, so the added sentence must cover payload forms only (paren count, paren on brace variant, payload on unit variant) and must not change the bare-name rule. I correct my B1: it read 3180 as making a bare name a variant in `let`, and F5 shows it does not.
> Concern: If A wins, `let`, parameter and `for` patterns can hit the NodeCarriesNoType ICE path and the wrong-count path with no spec text to reject them.

> **Q4. Vote: A**
> Reasoning: `V { .. }` already compiles on every payload variant (F1) and lowers to a bare tag test with no field access. Limiting it to labelled paren variants adds a check and removes the one spelling that works for every variant at zero cost.
> Concern: If A wins, `V { .. }` on an unlabelled paren variant looks odd to a reader, since the variant has no names to elide.

> **Q5. Vote: A**
> Reasoning: The rule belongs in the pattern-form text at 3175. The 3337 **Constructor.** entry is where a reader looks for how many sub-patterns a variant takes, so one sentence there prevents a reading of "matches enum variants" as "any variant name matches".
> Concern: If A wins, the two places can drift apart on the next edit.

> **Q6. Vote: A**
> Reasoning: `V { .. }` is the only spelling valid for every variant, paren, brace and any field count, so the `help:` can be one fixed rewrite with no per-variant count logic. It compiles to the same tag test as `V(_, _)`.
> Concern: If A wins, a user with a one-field variant gets `Circle { .. }` where `Circle(_)` is the form their training data holds.

##### Web (`C/web.md`)

> **Q1. Vote:** A
> **Reasoning:** One rule is easier to teach and to put in a diagnostic than a split list. E0300 is already in the bad-arm list at 03_types.md:3697, so a JS or Python dev who reads that line learns the whole rule, and the checker needs no pad-with-`_` path. The cost is that E0004 stays off for that match until the user fixes the E0300, and that is acceptable because the user must fix the E0300 first.
> **Concern:** A match with one payload typo hides every other missing-pattern report until the typo is fixed, which costs one more compile round.

> **Q2. Vote:** A
> **Reasoning:** A positional paren pattern names the declared form wrongly on a brace variant. One pattern rule, "the written form fits the declared form", is the only one a newcomer can hold in their head. Construction accepting `At(1, 2)` (F3) is the odd side and gets its own ticket.
> **Concern:** Until the construction ticket lands, `At(1, 2)` builds a value that `At(a, b)` cannot take apart, and that asymmetry will draw questions.

> **Q3. Vote:** A
> **Reasoning:** F5 shows a past vote made a bare uppercase name with no payload a binding in `let`, parameters, closure parameters and `for`. A sentence at 3180 that says "the payload-form rule applies" invites a reader to apply it to the bare name too, which contradicts that vote. 3180 already says a bare name with a payload must name a variant, so the payload-form rule follows from it without new text.
> **Concern:** A reader of 3180 alone may not learn that `let Circle(a, b) = s` with the wrong count is E0300.

> **Q4. Vote:** A
> **Reasoning:** `V { .. }` is the one spelling of "any value of this variant" that works for every variant and needs no new syntax. It compiles today (F1) and 3175 already lists it. Limiting it to labelled variants takes away the answer that the diagnostic must name for a Swift or Kotlin dev who wrote `Circle =>`.
> **Concern:** A brace pattern on a paren variant with unlabelled fields looks odd to a reader, because `Circle { .. }` hides that `Circle` is a paren variant.

> **Q5. Vote:** A
> **Reasoning:** The rule belongs where the grammar names the variant forms, at 3175. A dev who reads the Constructor entry at 3337 alone sees only "matches enum variants" and may still think `Circle` matches any Circle, so one sentence there closes that gap. Option C leaves that reader wrong.
> **Concern:** The sentence at 3337 and the text at 3175 can drift apart over time.

> **Q6. Vote:** A
> **Reasoning:** `V { .. }` is the same text for every variant, so the help line needs no lookup of the variant's field count or form. A web dev who wrote `Circle =>` reads "write `Circle { .. }` to match any Circle" and is done in one edit. The declared-form fix gives a different answer per variant and costs a second look.
> **Concern:** A user who follows the help gets `Circle { .. }` and never learns the positional form `Circle(_)`.

##### PLT (`C/plt.md`)

> **Q1. Vote: A.**
> Reasoning: Padding a short list with `_` or dropping extras is a guess about the user's match set. A checker rule "bad arm unless the repair is obvious" is not decidable, and 03_types.md:3697 already lists pattern E0300 with no exception. One rule needs no second list that the compiler and spec must keep in sync, and E0004 stays off, so the user sees one error.
> Concern: E0004 stays off for a match with one payload typo, so the user gets the real missing-pattern report only after the E0300 fix.

> **Q2. Vote: A.**
> Reasoning: The pattern checks against the declared form: `At(a, b)` on `At { x, y }` has no field labels to check, so it is a form misfit. Construction accepting `At(1, 2)` (F3) contradicts 03_types.md:2451 and is a separate construction bug. A mismatch between the two sides is a diagnostic gap, not a type hole.
> Concern: Until the construction ticket lands, `At(1, 2)` builds but `At(a, b)` does not match, which reads as an inconsistency.

> **Q3. Vote: A.**
> Reasoning: F5 is a past vote: a bare name with no payload binds in `let`, a parameter, a closure parameter and `for`. Option B makes `let Circle = x` E0300 and so reopens that vote. A bare name with a payload already "must name a variant" at 3180, so the payload-form rule covers the payload cases there without new text.
> Concern: `let Circle = x` on a payload variant binds a new name, with only the W1011 shadow warning to flag it.

> **Q4. Vote: A.**
> Reasoning: `V { .. }` binds no field and names no label, so no label check applies and it is sound on every payload variant. It is the one uniform spelling of "any value of this variant", and B would make that spelling depend on whether the fields are labelled. F1 already compiles; keep it.
> Concern: Two spellings of "any value" (`V { .. }` and `V(_, ..)` with right count) stay legal for a labelled-field or one-field variant.

> **Q5. Vote: A.**
> Reasoning: The rule replaces the "with or without a payload" clause at 3175, which is the false statement. One sentence at 3337 stops a reader of **Constructor.** alone from inferring that any variant name matches. A pointer or a copy at 3337 carries the same risk of drift as one sentence, so the sentence there is cheapest.
> Concern: The 3337 sentence can drift from 3175 over time.

> **Q6. Vote: A.**
> Reasoning: `V { .. }` is valid on every payload variant (F1), so one fix text is correct for every case and the checker needs no per-form branch. A fix that depends on the declared form could name a wrong spelling when the variant changes. The note lists the fields in order for the user who wants `V(_, _)`.
> Concern: A Rust-trained user expects `Circle(_)` and sees a brace form on a paren variant first.

##### DevOps (`C/devops.md`)

> **Q1. Vote: C**
> Reasoning: A user who writes `Circle =>` or pads too few fields wants a known match set, so the checker can check the arm as the declared form, and E0004 then reports the real missing pattern. If the arm is a bad arm, E0004 goes quiet and the user loses a true report while one E0300 is open. Too many sub-patterns has no single repair, since the extra pattern may be refutable, so that case is a bad arm.
> Concern: 3697 now has an exception, and the compiler and the spec must keep the exception list in sync.

> **Q2. Vote: B**
> Reasoning: Construction accepts `At(1, 2)` on a brace variant (F3). If the pattern side rejects `At(a, b)` with the right count, the user sees two sides that disagree, and an LSP rename or quick fix between them has no rule to follow. A wrong count stays E0300 with the `note:` that lists fields in order.
> Concern: Option B makes the pattern rule depend on a construction behavior that the panel has not yet confirmed as intended (F3 may be a construction bug), so a later fix of construction would force a second breaking change to patterns.

> **Q3. Vote: A**
> Reasoning: F5 shows an earlier vote made a bare name with no payload a binding in irrefutable positions, with W1011. A sentence at 3180 would contradict that vote, and I withdrew my own addition for this reason. The sentence "A bare name with a payload must name a variant" already covers the payload case.
> Concern: `let Circle = s` on a payload variant binds silently, and only W1011 warns the user.

> **Q4. Vote: A**
> Reasoning: `V { .. }` works on every variant today (F1). It is the one spelling that the `help:` can name for every variant without a count lookup. Limiting it to labelled fields would add a new error and a new message for a form that has no fault.
> Concern: `V { .. }` on a paren variant reads as a brace form on a type that has no named fields, which may confuse a user who reads the declaration.

> **Q5. Vote: A**
> Reasoning: A reader who lands on the 3337 **Constructor.** entry from the LSP hover or from a diagnostic link must see the form rule there, not only at 3175. Replacing the old "with or without a payload" text at 3175 removes the false statement. Keeping two places short avoids a drifting copy.
> Concern: Two places carry the rule, and a later edit may change one and not the other.

> **Q6. Vote: A**
> Reasoning: `V { .. }` is valid for every variant, so the `help:` text is correct without knowing the field count, and a quick fix can apply it with no edit of arity. I would name `V(_, _)` with the right count as the second choice. The declared form (B) needs a different fix per variant kind, but the Rust-trained user sees it in the second choice.
> Concern: For a one-field paren variant, `Circle { .. }` is less familiar than `Circle(_)`, so users may copy the help once and then ask why the declared form differs.

##### AI/ML (`C/aiml.md`)

> **Q1. Vote: A**
> Reasoning: A model learns one rule more easily than a rule with an exception. "Every payload-form E0300 makes a bad arm" needs no change at 3697 and no pad-with-`_` step that a model or a user must predict. The cost is one missing E0004 report until the user fixes the E0300, and one repair round fixes both.
> Concern: A user who writes `Circle =>` gets E0300 and no E0004 report for other missing variants in the same match, so the first fix can reveal a second error.

> **Q2. Vote: A**
> Reasoning: One form per declared variant form gives a model one spelling to learn: paren for paren, brace for brace. A legal `At(a, b)` on a brace variant adds a second spelling and hides field names the reader needs. Construction (F3) is a separate ticket.
> Concern: Construction accepts `At(1, 2)` while patterns reject it, so a model that copies the construction form into a pattern gets an error.

> **Q3. Vote: B**
> Reasoning: A model sees one rule for `match`, `let` and parameters. The sentence at 3180 states that paren count and brace form apply there too, and keeps the F5 decision that a bare name with no payload binds. It adds no new rule, only a pointer.
> Concern: A reader may take the sentence to change the F5 binding rule for a bare name, so the wording must say the bare-name case is unchanged.

> **Q4. Vote: A**
> Reasoning: `V { .. }` works on every payload variant today (F1), so one spelling means "any value" for all variants. It is the only form that needs no field count, which cuts a decision point for a model. Limiting it to labelled paren variants adds a condition a model must check.
> Concern: `Circle { .. }` on a positional paren variant looks like a brace variant to a reader, so a reader may look for a brace declaration that does not exist.

> **Q5. Vote: B**
> Reasoning: A reader of 3337 alone must not infer that any variant name matches. A pointer there costs one sentence and no copy of the rule. One rule text, placed after 3175, stays the single source.
> Concern: If the pointer at 3337 drifts from the rule text, the spec says two things.

> **Q6. Vote: B**
> Reasoning: The diagnostic names the fix in the form the declaration uses: `Circle(_)` for a paren variant, `Rect { .. }` for a brace variant. A model repairs from the note without the spec, and the match to the declaration teaches the form rule. `Circle(_)` is also what training data holds from Rust, Swift and OCaml.
> Concern: For a paren variant with many fields the note must write one `_` per field, and a note that names `V { .. }` first would be shorter and always correct.

##### Minimalism (`C/min.md`)

> **Q1. Vote: A**
> Reasoning: 03_types.md:3697 already lists pattern E0300 as a bad arm, so A needs no text change and no second checker rule. B needs the checker to pad with `_` and drop extras, which is a guess about a pattern the user did not write. C needs a split list that the compiler and spec must keep in sync, for the gain of one fewer error line.
> Concern: A turns off E0004 for a match that has a payload typo, so the user must fix the E0300 before the real missing-pattern report appears.

> **Q2. Vote: A**
> Reasoning: One form per declared form is the rule the grammar already states, and it keeps the pattern side to one spelling. B adds a second legal pattern spelling to match an F3 construction behaviour that 2451 itself calls an error. Fix construction in its own ticket.
> Concern: The pattern side and the construction side disagree until the construction ticket lands.

> **Q3. Vote: B**
> Reasoning: The bare name in an irrefutable pattern stays a binding (F5). Once a payload is present, the pattern names a variant, and the same count and form check must apply. Add one sentence at 3180 that points to the 3175 rule, with no new rule and no copy of the text.
> Concern: A reader may take the sentence to change the bare-name binding rule, so it must say that a bare name with no payload still binds.

> **Q4. Vote: A**
> Reasoning: F1 compiles today and `V { .. }` is the one "any value" spelling that fits every variant. The labelled-only limit in B adds a rule and makes the diagnostic fix differ by variant. I add no `V(..)`.
> Concern: `{ .. }` on a paren variant reads as a brace-variant form, so a reader may think the variant has named fields.

> **Q5. Vote: C**
> Reasoning: One place holds the rule, so there is one text to keep correct. A copy or a pointer at 3337 is a second place that can drift. 3337 already says "destructuring their fields", which does not contradict the rule.
> Concern: A reader who lands on 3337 alone may infer that any variant name matches, with no pointer to 3175.

> **Q6. Vote: A**
> Reasoning: `V { .. }` works for every variant and is one fix text for all diagnostics. B makes the compiler pick a form per variant and teaches two spellings. The `V(_, _)` form with the right count can stay as a second choice in the help.
> Concern: A user with a one-field paren variant is told `Circle { .. }` where `Circle(_)` is the more common spelling.

Q2, Q4 and Q6 were decided in Phase C. Q1, Q3 and Q5 went to a focused debate.

#### Phase D1 — Focused debate (Q1, Q3, Q5)

Each seat answered the strongest argument against its own vote, and held or changed it.

##### Systems (`D1/sys.md`)

> **Q1. Hold B.**
> Strongest argument against (plt): padding with `_` and dropping extras is a guess, and a rule "bad arm unless the repair is obvious" is not decidable. Reply: the rule is not "unless obvious". It is one rule for every payload-form error: check the arm as the declared form. That is decidable and needs one code path. The guess costs nothing in codegen, because an arm with an E0300 never reaches lowering. The cost of A is real: one typo in one arm turns off E0004 for the whole match. I concede that extras go unchecked; the checker should still type them, and report errors in them.

> **Q3. Hold B.**
> Strongest argument against (plt): B makes `let Circle = x` E0300 and reopens F5. Reply: it does not, if the sentence covers payload forms only. My Phase C file says so, and min's wording is the one to use: the bare name with no payload still binds, and the sentence points to the 3175 rule. Web says 3180 already implies it. It does not: "must name a variant" says nothing on count or form, and `let Circle(a, b) = s` needs that text.

> **Q5. Hold A.**
> Strongest argument against (min): a second place can drift. Reply: a reader who looks up how many sub-patterns a variant takes goes to 3337. One sentence there costs less than a wrong reading.

##### Web (`D1/web.md`)

> **Q1. Hold A.** The strongest argument against is sys and devops: a bad arm turns off E0004, so a payload typo hides a real missing-pattern report. That cost is one extra compile round, and the user must fix the E0300 first anyway. Option B and C each need a second checker path and a split list at 03_types.md:3697. One rule with no exception is the one a JS or Python dev can learn from one line.

> **Q3. Change to B.** The strongest argument against my A vote is sys: the form rule belongs to the pattern, not its position, so `let Circle(a, b) = s` needs a spec sentence that rejects the wrong count. My Phase C reason (3180 already covers it) is weak, because 3180 only says a bare name with a payload "must name a variant". It does not say the count or form rule then applies. My fear that a sentence at 3180 would reopen the F5 vote does not hold if the wording covers payload forms only. Condition: the sentence must say that a bare name with no payload still binds, and must point to the 3175 rule instead of copying it (min).

> **Q5. Hold A.** The strongest argument against is min: two places can drift. A reader who lands on the 3337 **Constructor.** entry alone sees only "matches enum variants" and may think any variant name matches. One sentence there costs less than that reader's mistake.

##### PLT (`D1/plt.md`)

> **Q1. Hold A.** The strongest argument against (sys, devops): a bad arm turns off E0004, so a payload typo hides a real missing-pattern report. The cost is real but bounded: the user fixes one E0300 and E0004 returns on the next compile. The alternative needs the checker to guess a match set for `Circle(a, b, c)`, and it adds an exception list to 3697 that must stay in sync with the compiler. B or C also make the typing rule depend on a repair the checker picks for the user. I keep one rule.

> **Q3. Change to B.** I voted A because I read B as reopening F5. The Phase C files (sys, aiml, min) show B is narrower: the added sentence covers payload forms only (paren count, paren on brace variant, payload on unit variant) and says a bare name with no payload still binds. That leaves F5 intact. The argument for B holds on its merits: 3180 says only that a bare name with a payload "must name a variant". It does not say the count and form checks apply, so `let Circle(a, b) = s` has no text to reject it, and the pattern rule is on the pattern, not its position. My vote is B only with the bare-name carve-out written in the sentence, as a pointer to the 3175 rule.

> **Q5. Hold A.** The strongest argument against (min): a second place can drift. The risk is small. 3337 states a fact about count, and 3175 holds the rule. Without a sentence at 3337, a reader of **Constructor.** alone can still infer "any variant name matches". A pointer (B) has the same drift risk as one sentence and says less.

##### DevOps (`D1/devops.md`)

> **Q1. Hold C.** The strongest argument against is plt's: "bad arm unless the repair is obvious" is not decidable, and 3697 has no exception today. I disagree on decidability. The exception depends on the written form only: too many sub-patterns is a bad arm; a bare name, too few, and a payload on a unit variant are not. The checker needs no judgment. The cost under A is a lost E0004 report for `Circle =>` plus `Dot =>`, which the user would need to see. I accept that C has one vote and A has four. If A wins, I ask that the help text still name the fix.

> **Q3. Hold A.** The strongest argument against is sys's: the pattern rule should not depend on position, so `let Circle(a, b) = s` needs the count check. That is right, and A does not prevent it. 3180 already says a bare name with a payload must name a variant, so the payload-form rule applies there with no new text. B adds a sentence that sys, aiml and min all say must leave the bare-name binding alone. A sentence that says nothing new is noise in the spec.

> **Q5. Hold A.** The strongest argument against is min's: one place, no copy that can drift. A reader at 3337 alone would still infer "any variant name matches". One short sentence under **Constructor.** costs little and stops that.

##### AI/ML (`D1/aiml.md`)

> **Q1. Hold A.** Strongest argument against (sys, devops): a bad arm turns off E0004, so one payload typo hides real missing-pattern reports. That cost is real but small: the user fixes the E0300 and the next compile shows E0004. The split rule costs more for a model. It must learn which E0300 forms are bad arms, and the spec needs a list of exceptions at 3697. One rule with no exception is cheaper to learn.

> **Q3. Hold B.** Strongest argument against (web, plt): 3180 already says a bare name with a payload must name a variant, and a new sentence may reopen F5. I answer that the sentence can name the payload forms only (paren count, paren on a brace variant, payload on a unit variant) and state that a bare name with no payload still binds. Sys's Phase C text shows that a careful reader read 3180 wrongly, so a model will too. One explicit sentence costs little and removes that guess. If the panel wants no new text at 3180, I accept A.

> **Q5. Hold B.** Strongest argument against (sys, web, plt, devops): a reader of 3337 alone needs a real sentence, not a pointer. Every A voter also names drift between 3175 and 3337 as the risk. A pointer cannot drift, because it holds no rule text. The pointer can say "A variant pattern uses the form the variant declares; see Pattern Forms", which stops the "any variant name matches" reading.

##### Minimalism (`D1/min.md`)

> **Q1. Hold A.** The strongest argument against is from sys and devops: a bad arm turns off E0004, so a payload typo hides a real missing-pattern report. That cost is one extra compile round, and the user must fix the E0300 first in any case. The other two options need a checker rule that pads with `_` or drops extras, and a split list at 3697. That is more surface than one lost report.

> **Q3. Change to A.** The strongest argument against B is web's: 3180 already says a bare name with a payload must name a variant. Such a pattern is then a variant pattern, and the 3175 rule applies to it with no new text. plt adds that B reopens F5. A sentence limited to payload forms would not, but the risk of a reader taking it that way is real. My Phase C reason for B was a reference to the 3175 rule. That reference adds text and no rule, so Minimalism favors leaving 3180 unchanged.

> **Q5. Hold C.** The strongest argument against is that a reader who sees only 3337 may infer that any variant name matches. 3337 says only "Matches enum variants, destructuring their fields". That sentence does not say a bare name matches any payload. The false clause is at 3175, and C removes it. A second sentence at 3337 is a copy that can drift.

Changes in the debate: on Q3, Web A to B, PLT A to B, Minimalism B to A. DevOps held A in D1 and moved in D2. No
seat changed on Q1 or Q5.

#### Phase D2 — Silent re-vote (Q1, Q3, Q5)

Result: Q1 A 4 (web, plt, aiml, min), B 1 (sys), C 1 (devops): A. Q3 B 5 (sys, web, plt, devops, aiml), A 1 (min): B.
Q5 A 4 (sys, web, plt, devops), B 1 (aiml), C 1 (min): A.

##### Systems (`D2/sys.md`)

> **Q1. Vote: B**
> Reasoning: An arm that names a known variant has a fixed tag test, so the checker can lower it as the declared form with `_` for a missing field and still type the extras. E0004 then stays accurate for the rest of the match. An arm with an E0300 never reaches lowering, so B costs nothing in codegen and keeps one code path for every payload-form error. A turns off E0004 for the whole match because of one typo in one arm.
> Concern: If A wins, one payload typo hides every real E0004 in that match until the user fixes it, and the user pays an extra compile round.

> **Q3. Vote: B**
> Reasoning: The form rule belongs to the pattern, not to its position. `let Circle(a, b) = s` needs the same count and form check as a `match` arm, or the checker has two paths and the irrefutable path can reach the NodeCarriesNoType ICE with no spec text to reject it. The sentence at 3180 covers payload forms only, says that a bare name with no payload still binds (F5 stays), and points to the 3175 rule with no copy of it. Web and plt moved to B on this basis in D1.
> Concern: If A wins, 3180 says only that a bare name with a payload "must name a variant", and a reader or a model cannot tell that count and form checks apply in `let`, parameter and `for` patterns.

> **Q5. Vote: A**
> Reasoning: The rule replaces the false "with or without a payload" clause at 3175. A reader who looks up how many sub-patterns a variant takes goes to the 3337 **Constructor.** entry, and one sentence there stops the reading "any variant name matches". A pointer says less than that sentence and has the same drift risk.
> Concern: If A wins, the 3175 text and the 3337 sentence can drift apart on a later edit.

##### Web (`D2/web.md`)

> **Q1. Vote: A**
> Reasoning: One rule with no exception is the rule a JS or Python dev can learn from one line. E0300 is already in the bad-arm list at 03_types.md:3697, so A needs no text change and no second checker path. The lost E0004 report costs one more compile round, and the user must fix the E0300 first anyway.
> Concern: A match with one payload typo hides every other missing-pattern report until the typo is fixed, so the first fix can reveal a second error.

> **Q3. Vote: B**
> Reasoning: I move from A. My Phase C reason (3180 already covers it) is weak: "must name a variant" says nothing on count or form, so `let Circle(a, b) = s` has no text that rejects the wrong count. The pattern rule must not depend on position. The sentence must cover payload forms only, say that a bare name with no payload still binds (F5), and point to the 3175 rule instead of copying it.
> Concern: A reader may take the new sentence to change the bare-name binding rule, so the wording must state that the bare-name case is unchanged.

> **Q5. Vote: A**
> Reasoning: A dev who reads the 3337 **Constructor.** entry alone sees only "matches enum variants" and may think `Circle` matches any Circle. One sentence there closes that gap at low cost. A pointer says less than a sentence, and the 3175 text that said "with or without a payload" is replaced, so the false clause goes.
> Concern: The sentence at 3337 and the text at 3175 can drift apart on a later edit.

##### PLT (`D2/plt.md`)

> **Q1. Vote: A**
> Reasoning: A payload-form E0300 is a type error in the pattern. The checker cannot know which match set the user meant, so any repair it picks (pad with `_`, drop extras) is a guess, and the typing rule would then depend on that guess. One rule with no exception keeps 03_types.md:3697 unchanged, and E0004 returns once the user fixes the E0300.
> Concern: A match with one payload typo hides every real E0004 report until the user fixes it, which costs one more compile round.

> **Q3. Vote: B**
> Reasoning: The form rule belongs to the pattern, not to its position, so `let Circle(a, b) = s` needs the same count and form check as a `match` arm. 3180 says only that a bare name with a payload "must name a variant"; it does not say the count and form checks follow. The sentence must cover payload forms only, state that a bare name with no payload still binds (F5), and point to the 3175 rule without copying it.
> Concern: A reader may take the new sentence to change the bare-name binding rule of F5, so the wording must state the carve-out in plain words.

> **Q5. Vote: A**
> Reasoning: The false clause "with or without a payload" at 3175 must be replaced, and that is where the rule lives. One short sentence under **Constructor.** stops a reader of that entry alone from inferring that any variant name matches. A pointer carries the same drift risk and says less.
> Concern: The sentence at 3337 can drift from the rule at 3175 on a later edit.

##### DevOps (`D2/devops.md`)

> **Q1. Vote: C**
> Reasoning: The user who writes `Circle =>` or too few fields wants a known match set, so E0004 can still name the true missing variant (`Dot`). A bad arm turns E0004 off, and the user then sees one error where the compiler could report two true ones in one run. Too many sub-patterns has no single repair, so it stays a bad arm. The split depends on the written form only, so the checker needs no judgment.
> Concern: If A wins, a match with one payload typo hides every real E0004 until the user fixes it, which costs an extra compile round for each LSP and CLI user.

> **Q3. Vote: B**
> Reasoning: I change from A. My Phase C reason was that a sentence at 3180 contradicts F5. The D1 files show that B can be narrow: it covers payload forms only, says a bare name with no payload still binds, and points to the 3175 rule. Without text at 3180, `let Circle(a, b) = s` has no spec sentence to cite in the E0300 `help:` and doc link, and sys showed a careful reader misreads 3180 today. My vote needs the bare-name carve-out in the sentence.
> Concern: If B wins with loose wording, a reader may take it to reopen F5 and expect `let Circle = x` to be an error.

> **Q5. Vote: A**
> Reasoning: A diagnostic link and an LSP hover on **Constructor.** land on 3337 alone, so one sentence there must state the form rule. Replacing the false clause at 3175 removes the wrong statement. A pointer says less than a sentence, and one sentence drifts no faster than a pointer.
> Concern: Two places carry the rule, so a later edit may change one and not the other.

##### AI/ML (`D2/aiml.md`)

> **Q1. Vote: A**
> Reasoning: One rule with no exception is the cheapest for a model to learn from the spec alone. 03_types.md:3697 already lists pattern E0300 as a bad arm, so A needs no new text and no rule about which payload errors are exempt. The cost is one lost E0004 report until the user fixes the E0300.
> Concern: A payload typo in one arm hides every real E0004 in that match, so the first fix can reveal a second error.

> **Q3. Vote: B**
> Reasoning: The form rule belongs to the pattern, not to its position. 3180 says only that a bare name with a payload "must name a variant"; it does not say that count and form checks then apply, so a model has no text that rejects `let Circle(a, b) = s` with the wrong count. One sentence that covers payload forms only, says a bare name with no payload still binds (F5), and points to the 3175 rule adds no new rule and removes a guess.
> Concern: A reader may take the sentence to change the F5 binding rule for a bare name, so the wording must say the bare-name case is unchanged.

> **Q5. Vote: B**
> Reasoning: Replace the false clause at 3175, and put one pointer sentence at 3337 ("A variant pattern uses the form the variant declares; see Pattern Forms"). A pointer holds no rule text, so it cannot drift, and it stops a reader of **Constructor.** alone from inferring that any variant name matches. If B loses, A is my second choice over C, because C leaves that reader wrong.
> Concern: If the pointer sentence grows into a copy of the rule, the spec says two things.

##### Minimalism (`D2/min.md`)

> **Q1. Vote: A**
> Reasoning: 03_types.md:3697 already lists the pattern E0300 errors as bad arms, so A changes no text and adds no checker path. B and C need the checker to pad with `_` or to split the list, and the spec and compiler must keep that split in sync. One lost E0004 report, back after the E0300 fix, costs less than a second rule.
> Concern: A payload typo in one arm turns off E0004 for the whole match until the user fixes it.

> **Q3. Vote: A**
> Reasoning: 3180 says "A bare name with a payload must name a variant", so the pattern is a variant pattern and the 3175 rule applies to it by position-free reading. A sentence that says nothing new adds spec surface, and four D1 files show that its wording can read as a change to the F5 bare-name binding. Leave 3180 unchanged.
> Concern: 3180 alone does not say that `let Circle(a, b) = s` with the wrong count is E0300, so a reader or an implementer may skip the check there.

> **Q5. Vote: C**
> Reasoning: The false statement is the "with or without a payload" clause at 3175. Replace it there and the rule has one home. 3337 says "destructuring their fields" and does not say any variant name matches, so it needs no copy that can drift.
> Concern: A reader who lands on 3337 alone gets no pointer to the form rule at 3175.

### Dissents

The dissenters' reasons are in their votes above. In their own words, the one-sentence concern each gave:

- **Systems, Q1 (B)**: "If A wins, one payload typo hides every real E0004 in that match until the user fixes it, and the user pays an extra compile round."
- **DevOps, Q1 (C)**: "If A wins, a match with one payload typo hides every real E0004 until the user fixes it, which costs an extra compile round for each LSP and CLI user."
- **DevOps, Q2 (B)**: "Option B makes the pattern rule depend on a construction behavior that the panel has not yet confirmed as intended (F3 may be a construction bug), so a later fix of construction would force a second breaking change to patterns."
- **Minimalism, Q3 (A)**: "3180 alone does not say that `let Circle(a, b) = s` with the wrong count is E0300, so a reader or an implementer may skip the check there."
- **AI/ML, Q5 (B)**: "If the pointer sentence grows into a copy of the rule, the spec says two things."
- **Minimalism, Q5 (C)**: "A reader who lands on 3337 alone gets no pointer to the form rule at 3175."
- **AI/ML, Q6 (B)**: "For a paren variant with many fields the note must write one `_` per field, and a note that names `V { .. }` first would be shorter and always correct."

### Reading gaps

The panel did not rule on these points. This decision writes no rule on them.

- A brace pattern on a unit variant (`Dot { .. }`). The ruling names a payload on a unit variant (`Dot(x)`) only.
- The help for a payload on a unit variant. Q6 names `V { .. }` and `V(_, _)`; neither fits a unit variant.
- Construction. `Shape.At(1, 2)` on a `{ }` variant compiles today. It has its own ticket.
- The Phase C ballot said "Q3 B: add a sentence at 3180". The seats agreed that the sentence covers payload forms
  only, says that a bare name with no payload still binds, and points to the rule at 3175.
- A good example in the spec uses `let Range(lo, hi) = s`. The compiler at the time of this decision did not parse a
  variant pattern in `let`. The spec leads the compiler here.

### Final Spec

- A variant pattern uses the payload form that its variant declares (§3.5).
- A bare name (bare or qualified) fits a unit variant only. `Circle =>` on `Circle(Int)`, and on a variant declared
  with `{ }`, is `TypeError` (E0300).
- A paren pattern has one sub-pattern for each field. Too few, too many, a paren pattern on a variant declared with
  `{ }`, and a payload on a unit variant are each E0300, with a note that lists the fields in order.
- A paren pattern has no rest form. `V { .. }` is legal on every variant that has a payload.
- The help names `V { .. }` first, then `V(_, _)` with one `_` for each field.
- Each payload-form E0300 makes a bad arm. The bad-arm paragraph does not change.
- In an irrefutable pattern the payload-form rule applies; a bare name with no payload still binds.
- The text replaces the "with or without a payload" clause in the bare-name bullet and adds one sentence under
  **Constructor.** No new error code.
