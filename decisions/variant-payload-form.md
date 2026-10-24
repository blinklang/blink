[< All Decisions](../DECISIONS.md)

# The Payload Form of a Variant Construction — Design Rationale

§3.4 gave field rules for a variant brace literal and for a paren payload with labels, and kept the argument-count
error for a positional paren payload. No text said which declared forms a paren payload may construct. The compiler
accepted all of these on `type Shape { At { x: Int, y: Int }, Circle(radius: Float, tag: Int), Pair(Int, Int), Dot }`:

```blink
let a = Shape.At(1, 2)
let b = Shape.At(x: 1, y: 2)
let c = Shape.At(y: 2, x: 1)
let d = Shape.At(x: 1, 2)
let e = Shape.Circle(radius: 1.0, 3)
let f = Shape.Circle { radius: 1.0, tag: 3 }
```

An earlier panel voted that a paren pattern on a variant declared with braces is `TypeError` (E0300). The DevOps seat
dissented there, because construction accepts `At(1, 2)`, and asked that construction and patterns agree. The
question was: is a paren payload on a brace variant legal (positional, labelled, or neither)?

## Summary

| Q | Question | Result | Vote |
|---|---|---|---|
| Q1 | An all-labelled paren payload on a brace variant (`Shape.At(x: 1, y: 2)`) | A: an error; a paren payload constructs only a variant declared with parens | 4-2 R2 (Web/Scripting, PLT dissent: B) |
| Q2 | A brace literal on a labelled paren variant (`Shape.Circle { radius: 1.0, tag: 3 }`) | A: legal | 6-0 |
| Q3 | Diagnostic code for the construction errors | A: reuse E0300 `TypeError`, a distinct message for each case; the pattern error stays E0300 | 6-0 |
| Q4 | A brace literal on an unlabelled paren variant (`Shape.Pair { a: 1, b: 2 }`) | A: `NoSuchField` (E0525) with the help "`Pair` has positional fields; write `Shape.Pair(1, 2)`" | 5-1 (Minimalism dissent: B) |
| Q5 | A labelled paren pattern on a brace variant (`At(x: a, y: b)`) | B: one sentence says it follows the Q1 construction rule, so it is an error | 5-1 R2 (Minimalism dissent: A; Phase C was 4-2 for A) |
| Q6 | `blink fix` | A: `blink fix` applies the fix with this change | 3-3 R2, user broke the tie for A |

Points all six seats stated in Phase B, not balloted:

- A positional paren payload on a brace variant (`Shape.At(1, 2)`, bare `At(1, 2)`) is a hard error, with no warning
  period. Sweep `src/`, `lib/` and `tests/` first, in the bootstrap step order.
- A positional paren payload on a paren variant stays legal; a wrong count keeps its count error and its `note:`.
- A payload that mixes labelled and positional arguments is an error. On a brace variant only the brace-form error
  shows (one error per payload). On a paren variant the mixed-payload error shows, and its code is E0527.
- The help on a paren payload for a brace variant shows the brace literal built from the call's arguments, and is
  machine-applicable when each argument maps to a field.
- The pending pattern vote (`At(a, b)` on a brace variant is E0300) stands.

Phase C, 6-0: a brace literal on a labelled paren variant stays legal (AI/ML withdrew its error); E0300 is reused with
a distinct message for each case (Systems, Web/Scripting and AI/ML withdrew their new codes).

## Final spec

- §3.4, new paragraph *The payload form of a construction*: a paren payload constructs only a variant declared with
  `( )`; a brace literal constructs a variant declared with `{ }` and a variant declared with `( )` whose fields all
  have names. A table gives the nine cases. A paren payload on a `{ }` variant is E0300 whatever its arguments, with one
  error for the payload; the help writes the brace literal, machine-applicable when each argument fills one field,
  and `blink fix` applies it. A brace literal on a `( )` variant with no names stays E0525, with a help that writes the
  paren payload.
- §3.4, *Variant Construction*: the construction and pattern rule is stated once (the declared form decides).
- §3.5 *Constructor*: one sentence says a labelled paren pattern follows the construction rule.
- ERROR_CATALOG: rows E0300, E0525 and E0527.
- No new error code.

## Reading gaps and how the writer read them

- The panel brief quoted the construction text as it stood on `main`. The branch this text builds on had already
  changed it: the wrong-count error is `VariantArgumentCount` (E0321), and a positional argument after a label in a
  paren payload is `PositionalAfterKeyword` (E0527). The text keeps E0321 for the count.
- The ruling names `Circle(radius: 1.0, 3)` and says it is a mixed-payload E0300. The base text gave that input E0527.
  The owner kept E0527 from the earlier ruling (mixed-variant-payload, Q3), so the text does not narrow E0527 to
  calls and does not make that input E0300. A positional argument before a label
  (`Circle(1.5, tag: 2)`) is a legal example in the base text, and the ruling does not name it, so it stays legal.
- The seats wrote "a payload is all positional or all labelled" without that example in view. The text does not
  extend the mixed-payload error to a positional argument before a label on a paren variant.
- On a brace variant, a payload with a bad label (`At(x: 1, z: 2)`) gets the form error and no field error. The panel
  said one error per payload for the mixed case; the text applies it to every paren payload on a brace variant.
- The panel did not ballot the help for a payload whose argument count does not match the variant. The text says the
  help is then not machine-applicable.
- The duality sentence that the ruling puts at the start of §3.4 has no host in the current text (the sentence that
  said bare construction mirrors the existing forms no longer exists). The sentence sits after *Patterns do not
  change*.

## Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated
in independent-proposal → debate → vote rounds. Phase D ran for Q1, Q5 and Q6.

#### Phase A — Independent proposals

Excerpts, each from the seat's own file.

- **Systems:** "A paren payload constructs only a variant declared with parens. A brace literal constructs any variant
  whose fields are all named: a brace variant, or a paren variant with labels. Labels are field names, so `Circle {
  radius: 1.0, tag: 3 }` stays legal. A brace literal on an unlabelled paren variant stays `NoSuchField` (E0525). Its
  help changes. A paren payload may be all-positional or all-labelled, not mixed." Systems proposed new codes
  `ParenOnBraceVariant` and `MixedPayloadLabels`, and moved the pattern to the same code. On the reason: "`Shape.At(1,
  2)` binds by position and breaks silently when someone swaps `x` and `y` in the declaration (both `Int`, so no type
  error). Rust, Zig and Swift all keep the two forms apart".
- **Web/Scripting:** "Rule: a variant has a *shape* from its declaration. `At { x, y }` and `Circle(radius: Float, tag:
  Int)` are **named-field** variants. `Pair(Int, Int)` is **positional**. A payload is either all labelled or all
  positional." Web proposed that a brace literal and an all-labelled paren payload both construct a named-field
  variant, and that a positional paren payload on a brace variant is a new `PositionalOnBraceVariant`. On the reason:
  "Swift and Kotlin devs write `.at(x: 1, y: 2)` with parens and labels, so we accept that. Labelled paren variants
  already accept braces, so the rule makes the two named-field shapes fully interchangeable."
- **PLT:** "Reason: a label denotes a field name, so a labelled payload (paren or brace) is a set of name bindings and
  the field rules of §2.14 apply to both. A positional payload denotes order, which only a paren declaration
  promises as its interface. A brace declaration promises names, so positional construction is outside its
  interface." PLT proposed E0300 for a positional paren payload on a brace variant and for a mixed payload, and a
  labelled paren payload legal on a brace variant.
- **DevOps:** "I dissented on the pattern vote because construction accepted `At(1, 2)`. The panel chose to reject the
  pattern. So I now ask that construction agree: reject a paren payload on a brace variant. One declaration then has
  one spelling, and the tools can rely on it." DevOps proposed E0300 with no new code, and: "The help is a
  machine-applicable fix when each argument maps to a field. A labelled payload maps by label. A positional payload
  maps by position."
- **AI/ML:** "A variant is built in the form it is declared in. A brace variant takes a brace literal. A paren variant
  takes a paren payload. Patterns follow the same rule, so construction and patterns agree." AI/ML proposed
  `VariantFormMismatch` and `MixedPayloadArgs`, an error for a brace literal on any paren variant, and: "One
  declared form gives one spelling. The spec states it in one sentence: "spell it as you declared it"."
- **Minimalism:** "A variant is built with the form it is declared with. A paren payload `V(...)` builds only a
  variant declared with parens. A brace literal `V { f: e }` builds a brace variant, and a paren variant whose fields
  are all labelled (the labels are field names; this already compiles and the pattern `Circle { radius, tag }`
  already matches it)." Minimalism proposed no new code: "Reuse the E0300 `TypeError` the pattern vote already
  uses."

#### Phase B — Debate highlights

The moderator's digest split the proposals into Option D (Systems, DevOps, AI/ML, Minimalism: a paren payload, positional
or labelled, constructs only a variant declared with parens) and Option N (Web/Scripting, PLT: a variant with field names
takes a brace literal or an all-labelled paren payload; only a positional payload needs a paren declaration). It flagged
eight variations, V1 to V8. Position shifts, in the seats' words:

- **AI/ML on V1:** "I move to: a brace literal may build a paren variant whose fields are all labelled. It compiles
  today, the pattern `Circle { radius, tag }` already matches, and it avoids a break with no gain."
- **AI/ML on V3:** "Keep NoSuchField, with sys's help ... I withdraw my replacement."
- **Systems on V2:** "I drop my request for a new code on the pattern side. I accept E0300 with a distinct message
  for paren-on-brace and for mixed payloads".
- **Systems on V8:** "I withdraw `blink fix` as a requirement. Printing the exact rewrite is enough."
- **DevOps on V1:** "Aiml's rule would make the pattern legal and the construction illegal, which is the
  disagreement I came to remove."
- **DevOps on V4:** "One error wins: the brace-form error only. A second error on the same argument list is noise."
- **PLT on D versus N:** "D is not the simple rule it claims. All five seats in D keep a brace literal legal on a
  labelled paren variant (V1). So under D a labelled paren declaration accepts a labelled paren payload and a brace
  literal, while a brace declaration accepts only the brace literal. That is an exception keyed to the declaration."
  PLT then conceded: "I concede D is sound. If N fails, I vote D with V1 legal."
- **Web/Scripting on D versus N:** "D's own exception admits that field names, not the declared bracket, decide the
  form. N states this as one rule". Web also: "If the panel picks D, I accept it. D is a smaller language, and the fix
  text is clear."
- **Minimalism on V1:** "I concede this is the weak point of D: legal brace-on-labelled-paren is a second spelling,
  which my own argument opposes. I keep it legal only because it compiles today and the pattern `Circle { radius, tag
  }` already matches".
- **Systems on V6:** "Under D, `At(x: a, y: b)` as a pattern is also an error. I ask the moderator to note this as a
  consequence."
- **Web/Scripting on V6, Phase A:** "Labelled paren patterns `At(x: a, y: b)` are out of scope here, but the rule above
  says they would be legal for symmetry."

#### Phase C — Final vote

- **Q1: An all-labelled paren payload on a brace variant (`Shape.At(x: 1, y: 2)`)** (A 4-2: Web/Scripting, PLT dissent)
  - **Systems:** A — "Both spellings lower to the same payload struct, so the cost is equal. The difference is in the
    compiler: option B needs two parse paths and two diagnostic paths for one layout fill, and it keeps a rule ("a
    label makes a paren payload legal") that every tool must carry. Option A has one rule: a paren payload builds
    only a paren variant. The brace literal already shows the field names at the call site."
    Concern: "B-side seats are right that A removes a payload that compiles today, so the migration sweep must reach
    every test and lib file before the cut."
  - **Web/Scripting:** *(dissent)* B — "A JS, Kotlin or Swift developer reads `Shape.At(x: 1, y: 2)` as a call with
    named arguments, and it compiles today. Five seats keep a brace literal on a labelled paren variant, so under D
    the declared bracket does not decide the form; field names do. N states that as one rule: a label needs a
    declared field name, a positional argument needs a paren declaration. N also avoids a second break for code that
    is already safe, because the labels bind by name and survive a field reorder."
    Concern: "Under D, the model and the user meet two rules ("braces always work for names, parens only if declared
    with parens"), and a developer who wrote `At(x: 1, y: 2)` gets an error for code that was never order-dependent."
  - **PLT:** *(dissent)* B — "A label denotes a field name, so a labelled payload, in braces or in parens, is a set
    of name bindings and the field rules of 2.14 apply to both. A positional payload denotes order, and only a paren
    declaration promises order. Option D keeps a brace literal on a labelled paren variant (Q2 A), so D has an
    exception keyed to the declaration. N has one question per payload: "has names?" and "has order?"."
    Concern: "Under B a brace variant has two construction spellings (`At { .. }` and `At(x: .., y: ..)`), and the
    tools must handle both."
  - **DevOps:** A — "One brace variant gets one construction spelling. Completion after `Shape.At` offers `{` and the
    field names, the fix text names one form, and grep and `blink fix` handle one form. Option N keeps two spellings
    for a brace variant, and the help for a wrong paren payload would have to name both."
    Concern: "The table under D is not symmetric (a labelled paren variant takes a brace literal, a brace variant
    does not take a labelled paren payload), and users may ask why."
  - **AI/ML:** A — "One declared form gives one spelling, so a model copies the declaration and makes no choice.
    Option B adds the rule "a label makes a paren payload legal on a brace variant", and that rule must be
    memorised. The brace literal already carries every field name, so B adds no power. The only cost of A is a
    one-time break, and the printed fix repairs it in one turn."
    Concern: "A model that learned Swift or Kotlin habits writes `At(x: 1, y: 2)` and hits an error, though the fix
    text corrects it at once."
  - **Minimalism:** A — "A brace variant already has one spelling that carries field names. An all-labelled paren
    payload on it adds a second spelling with no new power. B swaps a one-time migration for a permanent two-way
    choice, and it adds a rule ("a label makes a paren payload legal") that every reader and model must learn. The
    break is mechanical, and the help prints the fix."
    Concern: "The labelled paren payload on a brace variant compiles today, so A is a second break for code that is
    already correct and safe against field reordering."

- **Q2: A brace literal on a labelled paren variant (`Shape.Circle { radius: 1.0, tag: 3 }`)** (A 6-0)
  - **Systems:** A — "A brace literal on a labelled paren variant builds the same layout and matches the pattern
    `Circle { radius, tag }`, which is already decided and legal. Making it an error would break working code and gain
    no layout or codegen benefit. Construction and patterns stay dual."
    Concern: "this leaves a second spelling for labelled paren variants, which weakens the "one spelling per
    declaration" argument for option A on Q1."
  - **Web/Scripting:** A — "It compiles today, the pattern `Circle { radius, tag }` already matches, and aiml
    withdrew the error. Removing it would add a break and no safety, since labels bind by name."
    Concern: "None of note; a second spelling of a paren variant stays, which min and aiml dislike."
  - **PLT:** A — "The brace literal on a labelled paren variant needs no new typing rule, because the names exist. It
    compiles today and the pattern `Circle { radius, tag }` already matches. Making it an error breaks working code
    and splits construction from patterns."
    Concern: "The brace literal on a paren variant stays a second spelling of that variant."
  - **DevOps:** A — "`Circle { radius: 1.0, tag: 3 }` compiles today, and the pattern `Circle { radius, tag }` is
    already legal. My dissent was that construction and patterns must agree. An error here would leave the pattern
    legal and the construction illegal, which is the disagreement I came to remove."
    Concern: "A labelled paren variant keeps two construction spellings, which weakens the "one declaration, one
    spelling" argument used for Q1."
  - **AI/ML:** A — "I withdrew B in Phase B. The code compiles today and the pattern `Circle { radius, tag }` already
    matches, so an error here is a second break for no gain. The model-facing rule stays short: labels in braces
    always work, positional needs parens."
    Concern: "This leaves two spellings for a labelled paren variant, which is the exception plt names against D."
  - **Minimalism:** A — "The brace literal on a labelled paren variant compiles today, and the pattern `Circle {
    radius, tag }` already matches it. Making it an error means a second break and a second pattern change for a small
    gain. All seats except aiml keep it, and aiml withdrew."
    Concern: "Under A, a labelled paren variant keeps two spellings while a brace variant gets one, so the rule has an
    exception keyed to the declaration (plt's point)."

- **Q3: Diagnostic code for the construction errors** (A 6-0: reuse E0300, no new code)
  - **Systems:** A — "The code does not change what the hardware sees. One code for one mistake, with a message that
    names the declared form, matches the pattern vote. I withdraw my request for new codes. A new code costs docs,
    explain text and a catalog entry for one help string."
    Concern: "one code (E0300) now covers count errors, form errors and mixed payloads, so a tool that matches on the
    code alone cannot tell them apart without reading the message."
  - **Web/Scripting:** A — "The pattern vote already uses E0300, and one code for one mistake is easier to search
    for and teach. A distinct message and a machine-applicable help carry the difference, which is what a developer
    reads. I concede my new codes: they buy no behaviour."
    Concern: "E0300 now covers count, form and mixed errors, so an `explain` page for it must keep three short cases
    apart."
  - **PLT:** A — "The two errors do not differ in typing. Both say that a payload form does not fit the declaration,
    and the pattern vote already uses E0300. A distinct message and help carry the difference, and a new code adds
    catalog and `blink explain` surface for no type-theory gain."
    Concern: "One code covers several different mistakes, so tools that filter by code cannot tell them apart
    without reading the message."
  - **DevOps:** A — "The pattern error is already E0300. A user who makes one mistake in a pattern and in a
    construction should see one code. A distinct message and help for each case gives the tools what they need. A new
    code costs a `blink explain` entry, docs and a diagnostics-table row for one help string."
    Concern: "Code E0300 now covers count, pattern form, construction form and mixed payload, so a tool cannot tell
    these apart from the code alone and must read the message."
  - **AI/ML:** A — "One code for one mistake helps a repair loop: the model sees the same code for the same error in
    patterns and in construction. A distinct message that names the declared form carries the signal. New codes add
    docs and `blink explain` surface for one help string."
    Concern: "A shared E0300 code also covers the plain count error, so a tool that keys on the code alone cannot
    tell form errors from count errors."
  - **Minimalism:** A — "Each new code costs a catalog entry, a `blink explain` text and tests, for one family of
    mistake. E0300 already serves the pattern vote. A distinct message and help for each case gives the user the
    distinction without new surface."
    Concern: "A user who searches for E0300 finds one code with three unrelated meanings (count, form, mix), which
    makes the code less useful as a key."

- **Q4: A brace literal on an unlabelled paren variant (`Pair { a: 1, b: 2 }`)** (A 5-1: Minimalism dissents; keep
  E0525, add a positional help)
  - **Systems:** A — "`Pair` has no field names, so NoSuchField (E0525) is the exact error and needs no new code.
    Only the help is wrong: "did you mean" has nothing to suggest. The new help ("`Pair` has positional fields;
    write `Shape.Pair(1, 2)`") gives the fix at no runtime or code-surface cost."
    Concern: "the help must be built from the declaration, and a generic variant or an unlabelled variant with many
    fields could produce a long or wrong rewrite."
  - **Web/Scripting:** A — "`NoSuchField` is exact, because no field name exists. The "did you mean" hint has
    nothing to suggest, so the help `Pair has positional fields; write Shape.Pair(1, 2)` gives the developer the
    working spelling at no cost in codes."
    Concern: "Two help variants on one code (a name suggestion and a positional hint) must be chosen by whether the
    variant has labels; a bug there shows a wrong hint."
  - **PLT:** A — "`Pair` has no field names, so `NoSuchField` is the exact error under the rule "labels need
    declared names". Only the "did you mean" help is wrong, because no name exists to suggest. The new help points
    to the positional form, and no new code is needed."
    Concern: "The help names a form (`Shape.Pair(1, 2)`) that the user may not have meant, if the brace literal was
    a typing slip for a different variant."
  - **DevOps:** A — "`NoSuchField` is exact, because `Pair` has no field names. The current help ("did you mean")
    has nothing to suggest, so it misleads. A help that shows `Shape.Pair(1, 2)` gives the user the fix and costs no
    new code."
    Concern: "The help line is built from the call's field expressions, and a brace literal with a mismatched field
    count may give a poor rewrite."
  - **AI/ML:** A — "The `did you mean` hint on `Pair { a: 1, b: 2 }` points at fields that do not exist and
    misleads a model. A help that shows `Shape.Pair(1, 2)` gives the exact rewrite. It costs no new code."
    Concern: "B leaves the misleading hint in place, and a model may then loop on guessed field names."
  - **Minimalism:** *(dissent)* B — "`NoSuchField` is exact: `Pair` has no field named `a`. This case is rare and
    the ticket does not ask for it. B adds no new help branch to the diagnostic, so it keeps this change to the one
    gap the ticket names."
    Concern: "The "did you mean" help on `Pair { a: 1, b: 2 }` may suggest a field that does not exist, and a model
    may loop on it."

- **Q5: A spec sentence for a labelled paren pattern on a brace variant (`At(x: a, y: b)`)** (A 4-2 in Phase C:
  say nothing; B had Systems and PLT. Phase D reversed it, see below)
  - **Systems:** B — "Under option A of Q1, `At(x: a, y: b)` as a pattern follows the same rule as construction. A
    pattern is a match on the same layout, so the compiler should reject it on the same grounds. One spec sentence
    closes the gap. Without it, the compiler picks a behaviour and the spec stays silent again."
    Concern: "if the construction rule changes later, this sentence must change with it, so the two rules are
    coupled."
  - **Web/Scripting:** A — "The pattern vote has not decided it, and this panel's agreed list covers only the
    positional pattern. Stating it here would decide a pattern question by side effect. If Q1 is N, a later pattern
    ticket can state the symmetry with one sentence."
    Concern: "With Q1 at N and Q5 silent, `At(x: a, y: b)` as a pattern stays unspecified while its construction
    twin is legal, and a user will file the gap."
  - **PLT:** B — "Construction and patterns are duals (03_types.md:2229), so the spec must say which labelled forms
    a pattern accepts. With Q1 B the rule is: a labelled paren pattern needs field names, as a labelled paren
    payload does. Leaving it unsaid repeats the gap this ticket exists to close."
    Concern: "If Q1 goes to A, this line reads "an error", and the spec then states a rule that no panel has debated
    for patterns."
  - **DevOps:** A — "The pattern panel did not decide a labelled paren pattern, and this ballot is about
    construction. Under D the compiler will already reject it with the same form error, so the diagnostic surface is
    covered. Spec text can state this later if the question comes up."
    Concern: "The spec stays silent on `At(x: a, y: b)` in a pattern, so a second ticket is likely."
  - **AI/ML:** A — "The pattern vote did not decide it, and this ballot should not extend it. Under Q1 A the answer
    follows from the rule, but stating it now adds spec text before the pattern vote is signed off."
    Concern: "Silence leaves a labelled paren pattern on a brace variant undefined until someone files a ticket."
  - **Minimalism:** A — "The pending pattern vote covers positional paren patterns. A labelled paren pattern is not
    a form the spec lists, and I do not want to add surface. Q1 already gives the answer by implication: a paren
    payload needs a paren declaration. The spec need not say it twice."
    Concern: "With A, `At(x: a, y: b)` in a pattern has no stated rule, and a later reader must infer it from Q1."

- **Q6: `blink fix` ships with the change** (3-3 in Phase C: A had Web/Scripting, PLT, DevOps; B had Systems, AI/ML,
  Minimalism. Phase D did not break it; the user broke it for A, see below)
  - **Systems:** B — "The printed machine-applicable help gives the exact rewrite. A `blink fix` pass is separate
    tooling work and must not block the cut. Ship it as a follow-up."
    Concern: "without `blink fix` in the same change, users with many hits in their own code must apply the rewrite
    by hand until the follow-up lands."
  - **Web/Scripting:** A — "This is a hard break with no warning period, and the help is already machine-applicable.
    Shipping `blink fix` with the change lets a user migrate a code base in one command instead of hand-editing each
    site. The ground work is the same as the printed help."
    Concern: "If `blink fix` ships with the cut and has a bug, it rewrites user code wrongly; it needs tests on the
    same corpus sweep."
  - **PLT:** A — "The migration is a hard error with no warning period, and the fix is mechanical when each argument
    maps to a field. A fix shipped with the break removes the sweep cost for users. The pattern side gets the same
    treatment, so one tool serves both."
    Concern: "`blink fix` support adds scope to the change, and a bug in the rewrite could change a working
    program's meaning if the argument-to-field mapping is wrong."
  - **DevOps:** A — "A hard error with no warning period needs a way to migrate. The help is already
    machine-applicable, and `blink fix` is the tool users run for that. Shipping both together means the break and
    the fix land in one release, and the help text is tested through the same path."
    Concern: "`blink fix` work may delay the cut, and a fix that mis-maps arguments on a large codebase is a worse
    failure than a compile error."
  - **AI/ML:** B — "The printed help already gives the exact rewrite, which is enough for a model to fix each hit in
    one turn. A `blink fix` pass is extra tool surface and must not block the cut. Ship it as a follow-up."
    Concern: "Without `blink fix`, users with many hits must rewrite by hand, and the break feels larger."
  - **Minimalism:** B — "The compiler prints a machine-applicable help, and the hits are few and mechanical. `blink
    fix` support is more tool surface and it should not block the cut. It can follow when the sweep shows a need."
    Concern: "Users with many hits in downstream code get no bulk rewrite, so the break costs them more than it costs
    the repo."

#### Phase D — Focused debate and re-vote (Q1, Q5, Q6)

Q2, Q3 and Q4 were decided in Phase C and not debated.

**Debate positions (D1).** Each seat answered the strongest argument against its Phase C vote.

- **Q1.** Systems, DevOps, AI/ML and Minimalism held A. Web/Scripting and PLT held B. PLT: "D's rule "a brace literal
  builds any variant with names; a paren payload builds only a paren variant" names the declared bracket for one form
  and field names for the other. B uses field names for both." Systems: "One is a kept legacy form, the other is a new
  rule."
- **Q5.** Web/Scripting, DevOps and AI/ML changed from A to B. Systems and PLT held B. Minimalism held A. Web/Scripting:
  "I accept the side effect, since the sentence only restates Q1 and invents no new pattern form." Minimalism: "I would
  accept one sentence that only points to Q1 and adds no rule."
- **Q6.** Web/Scripting, PLT and DevOps held A. Systems, AI/ML and Minimalism held B. PLT: "The fix stays safe if it
  is machine-applicable only when each argument maps to one field." AI/ML: "Ship the help now. Add `blink fix` when a
  sweep shows downstream need."

**Phase D2 re-vote, verbatim.**

- **Q1: All-labelled paren payload on a brace variant** (A 4-2: Web/Scripting, PLT dissent)
  - **Systems:** A — "Both spellings lower to the same payload layout, so the runtime cost is equal. The difference
    is in the front end: B keeps a second accepted form for every brace variant, and the parser, the formatter,
    completion and the help text must all carry it. A has one rule: a paren payload builds only a paren variant. The
    brace literal on a labelled paren variant is a kept legacy form (Q2 A), not a new accepted one, so A adds no new
    exception."
    Concern: "A breaks `At(x: 1, y: 2)`, which compiles today and is safe against field reordering, so the sweep of
    src/, lib/ and tests/ must finish before the cut."
  - **Web/Scripting:** *(dissent)* B — "A JS, Kotlin or Swift developer reads `Shape.At(x: 1, y: 2)` as a call with
    named arguments. It compiles today, and the labels bind by name, so it is safe against a field reorder. Q2 A
    already keeps a brace literal on a labelled paren variant, so field names decide the form, not the bracket. B
    states that as one rule and adds no parse path, because the labelled paren payload path and its field checks
    already exist. A adds a new reject for code that is correct."
    Concern: "Under B a brace variant keeps two construction spellings, and completion, the formatter and the help
    text must handle both."
  - **PLT:** *(dissent)* B — "A label denotes a field name, so a labelled payload, in braces or in parens, is a set
    of name bindings that the field rules of 2.14 already check. A positional payload denotes order, and only a paren
    declaration promises order. Q2 A already keeps a brace literal on a labelled paren variant, so field names, not
    the declared bracket, decide the form under both options. Option B states that as one rule. Option A needs a new
    reject for a form that compiles today and is safe against field reorder, and it keeps the exception that Q2
    introduced."
    Concern: "Under B a brace variant keeps two construction spellings (`At { x: 1, y: 2 }` and `At(x: 1, y: 2)`),
    and the formatter, completion and help must handle both."
  - **DevOps:** A — "One brace variant gets one construction spelling, so completion, the help text, grep and the
    formatter handle one form. The brace literal carries the field names and works on every variant that has names. A
    paren payload carries order, so it needs a paren declaration. The break is one mechanical rewrite, and the help
    prints it."
    Concern: "A labelled paren payload on a brace variant compiles today and is safe against field reorder, so A
    breaks correct code and users will ask why the table is not symmetric."
  - **AI/ML:** A — "A brace variant gets one construction spelling, so a model copies the declaration and makes no
    choice. Under B a model sees `At(x: 1, y: 2)` and `At { x: 1, y: 2 }` as two valid spellings of one variant, and
    it must pick one. The brace literal on a labelled paren variant (Q2) is a kept legacy form with a one-line rule:
    labels in braces always work, positional needs parens. The break has a printed, machine-applicable fix."
    Concern: "A model with Swift or Kotlin habits writes `At(x: 1, y: 2)` and hits an error on code that is
    order-safe, though the help corrects it in one turn."
  - **Minimalism:** A — "A brace variant already has one spelling that carries field names, the brace literal. A
    labelled paren payload on it adds a second spelling with no new power, and it keeps a permanent two-way choice for
    every reader and model. The one-way exception for a brace literal on a labelled paren variant is legacy kept by Q2
    A, not a new rule. The break is mechanical and the help prints the rewrite."
    Concern: "The labelled paren payload on a brace variant compiles today and is safe against field reordering, so A
    breaks code that is already correct."

- **Q5: A spec sentence for a labelled paren pattern on a brace variant** (B 5-1: Minimalism dissents)
  - **Systems:** B — "A pattern matches the same layout that construction fills, and 03_types.md:2229 says the two
    are duals. One spec sentence that applies the Q1 result to patterns costs one line and decides no new pattern
    form. Without it the compiler picks a behaviour and the spec is silent again, which is the gap this ticket exists
    to close."
    Concern: "If the Q1 rule changes later, this sentence must change with it, so the two rules are coupled."
  - **Web/Scripting:** B — "I changed from A in D1. Construction and patterns are duals (03_types.md:2229), and one
    sentence that says a labelled paren pattern follows the Q1 construction rule decides nothing new. It reads "legal"
    under B and "an error" under A, so it is right under either Q1 result. Silence would leave the compiler to pick a
    behaviour and invite a second ticket."
    Concern: "If Q1 later changes, this sentence must change with it, so the two rules are coupled."
  - **PLT:** B — "Construction and patterns are duals (03_types.md:2229), so the spec must say which labelled forms a
    pattern accepts. One sentence that applies the Q1 result to patterns decides no new pattern question: it reads
    "legal" under Q1 B and "an error" under Q1 A. Silence leaves the compiler to choose, which is the gap this ticket
    exists to close."
    Concern: "If Q1 goes to A, the sentence states an error rule for patterns that no panel debated on its own,
    though it follows from the construction rule."
  - **DevOps:** B — "03_types.md:2229 says construction and patterns are duals, so the spec must state the labelled
    paren pattern rule. The sentence applies the Q1 result and adds no new pattern form. A compiler rejection that no
    spec text backs is a behaviour, not a rule, and the gap would reopen as a second ticket."
    Concern: "If Q1 goes to A, the sentence states "an error" for a pattern form that no panel debated on its own, so
    the pattern sign-off must carry it."
  - **AI/ML:** B — "The spec says construction and patterns are duals (03_types.md:2229). A spec that is silent on the
    labelled paren pattern leaves a gap that an AI cannot fill from the spec alone. The sentence "a labelled paren
    pattern follows the construction rule" restates Q1 and adds no new pattern form. It is correct under either Q1
    result."
    Concern: "If Q1 changes later, this sentence must change with it, and a reader may treat it as a separate pattern
    decision."
  - **Minimalism:** *(dissent)* A — "The pending pattern vote covers positional paren patterns only. A labelled paren
    pattern follows from Q1 A (a paren payload needs a paren declaration), so the spec need not state it twice. I
    accept that the compiler will reject the form with the same form error. If B wins, the sentence should only point
    to the Q1 rule and add no pattern form."
    Concern: "With A, `At(x: a, y: b)` in a pattern has no stated rule, and a later reader must infer it from Q1,
    which may cost a second ticket."

- **Q6: `blink fix` ships with the change** (3-3, tie broken by the user for A)
  - **Systems:** B — "The printed machine-applicable help already gives the exact rewrite, and most hits are in this
    repo. A `blink fix` pass is separate tooling work with its own mapping risk, and it must not block the cut. Ship
    it as a follow-up when the sweep shows downstream need."
    Concern: "Users with many hits in their own code must apply the rewrite by hand until the follow-up lands."
  - **Web/Scripting:** A — "The break is a hard error with no warning period. The help is machine-applicable, so
    `blink fix` reuses the same argument-to-field mapping and adds little. A user with a large code base migrates in
    one command instead of hand-editing each site. The fix applies only when each argument maps to one field."
    Concern: "A bug in the argument-to-field mapping would rewrite working code wrongly, so the mapping needs tests on
    the corpus sweep."
  - **PLT:** A — "The migration is a hard error with no warning period, so users need a bulk path. The compiler
    computes the argument-to-field mapping for the printed help anyway, and `blink fix` reuses it. The fix stays sound
    if it applies only when each argument maps to exactly one field (positional by position, labelled by label) and a
    count mismatch gets no machine fix. Tests on the corpus sweep cover that mapping once for both uses."
    Concern: "A wrong argument-to-field mapping in `blink fix` would change the meaning of a working program, which
    is worse than a compile error."
  - **DevOps:** A — "A hard error with no warning period needs a bulk path for downstream code. The
    machine-applicable help already computes the argument-to-field mapping, so `blink fix` applies a result the
    compiler has. It rewrites only when each argument maps to one field, and a count mismatch gets no fix. The help
    text and the fix are tested through the same path."
    Concern: "A bug in the argument-to-field mapping rewrites a working program wrongly, which is worse than a compile
    error, so the mapping needs tests on the corpus sweep."
  - **AI/ML:** B — "The printed machine-applicable help gives the exact rewrite for each hit, and a model repairs
    each site in one turn. `blink fix` is extra tool surface, and a wrong argument-to-field mapping would change a
    working program. Add it as a follow-up if the sweep shows downstream need."
    Concern: "Users with many hits in downstream code must edit by hand until the follow-up lands, so the hard break
    costs them more than it costs this repo."
  - **Minimalism:** B — "The printed machine-applicable help already gives the exact rewrite at each site, and the
    hits are few. `blink fix` is more tool surface with its own risk: a wrong argument-to-field mapping changes a
    working program's meaning. It can follow when the sweep shows downstream need."
    Concern: "Users with many hits in downstream code get no bulk rewrite, so the break costs them more than it costs
    this repo."

#### Dissents

- **Q1 (Web/Scripting, PLT):** a label names a field, so a labelled paren payload on a brace variant should stay
  legal. Under the ruling, `Shape.At(x: 1, y: 2)` is an error although it compiles today and is safe against a field
  reorder.
- **Q4 (Minimalism):** keep the help unchanged on `Pair { a: 1, b: 2 }`.
- **Q5 (Minimalism):** the spec need not state the labelled paren pattern rule, because Q1 implies it.
- **Q6 (Systems, AI/ML, Minimalism):** ship `blink fix` as a follow-up, not with the change.

#### User tiebreak

Q6 stood at 3-3 after Phase D2. The user broke the tie for A: `blink fix` ships with the change. Reason: `blink fix`
already exists (06 §8.6, generic over machine-applicable fixes) and the help is already agreed 6-0 as
machine-applicable, so A needs no dedicated work. No extra corpus-sweep test is required.
