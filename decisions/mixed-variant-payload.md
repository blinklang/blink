[< All Decisions](../DECISIONS.md)

# Fields of a Paren Variant and a Mixed Payload — Design Rationale

§3.4 *Variant Construction* gave a variant paren payload whose arguments are all labelled the field rules of §2.14
(`NoSuchField`, `DuplicateField`, `MissingField`), and gave a payload with a positional argument the argument-count
`TypeError` (E0300) with a `note:` that lists the fields. A payload that mixes a position and a label, with the right
count, fell between the two rules. The spec also gave no grammar for the fields of a paren variant: it did not say
whether one variant may declare both unnamed and named fields, or whether a call may omit labels on a variant declared
with named fields. The compiler accepted both.

With `type Figure { Circle(radius: Float, tag: Int) }`, the call `Figure.Circle(1.0, radius: 2.0)` passed
`blink check` and stopped `blink build` with an internal error (a field left unfilled). The questions were: does a
position fill the field at its index, must positions precede labels, may one variant declare both unnamed and named
fields (`M(Int, b: Int)`), and does the list of fields mark a field that a position filled.

## Summary

| Q | Question | Result | Vote |
|---|---|---|---|
| Q1 | A variant that declares both unnamed and named fields | A: forbid it; a declaration error `MixedVariantFields` (E0320), help "name every field or none" | 6-0 |
| Q2 | If the mix stays, what `M(b: 1)` reports | A: `MissingField` for field 0, help "write it by position" (moot: Q1 forbids the mix) | 6-0 |
| Q3 | Code for a positional argument after a label in a payload | A: reuse E0527 `PositionalAfterKeyword`; widen the catalog row and the §2.13 sentence | 6-0 |
| Q4 | Mark the fields that a position filled in the fields note | A: one mark, `(given)`, the same for position-filled and label-filled fields | 5-1 (Minimalism dissent: B) |
| Q5 | Which diagnostics print the marked list | A: the E0300 count error and `MissingField` | 6-0 |
| Q6 | What §3.4 states about writing a field by position | A: one sentence | 6-0 |

Points the panel agreed on and did not ballot: positional arguments come first; positional argument `i` fills field
`i`; a label fills the field of that name. `DuplicateField` (E0316) names the argument that filled the field. The
order stays Duplicate, `NoSuchField`, Missing. `Circle(1.0, 2)` and `Circle(1.5, tag: 2)` stay legal. E0300 applies
only to a payload with no label, and to a payload with more positional arguments than fields. Every internal-error
shape becomes a checker error. The existing checker test that declares a mixed variant is kept and changed to expect
the new declaration error.

No question was closer than 5-1, so no Phase D ran. AI-First review: 5/5.

### Compiler behavior before the decision

The moderator ran probes with the gen1 compiler and gave the results to the panel:

- With `Circle(radius: Float, tag: Int)`: `Circle(1.0, 2)` and `Circle(1.5, tag: 2)` pass and run (`1.5 2`).
  `Circle(1.0, radius: 2.0)` passes check and stops the build (field `tag` unfilled). `Circle(tag: 2, 1.0)` gives
  `TypeError: argument 2 of Figure.Circle expects Int, got Float`. `Circle(1.0, tagg: 2)` gives `NoSuchField` with
  "did you mean `tag`?". `Circle(1.0)` gives the E0300 count error and
  `note: fields of Figure.Circle, in order: radius (Float), tag (Int)`.
- With `Circle(tag: Int, radius: Int)`: `Circle(radius: 5, 7)` passes check and stops the build (`tag` unfilled).
  `Circle(radius: 5, tag: 7)` runs.
- With `M(Int, b: Int)`: `M(1, b: 2)` and `M(1, 2)` pass. `M(b: 1)` gives the E0300 count error. `M(b: 2, 1)` passes
  check and stops the build (field `_0` unfilled).
- `type K { M(a: Int, Int) }` with `K.M(1, 2)` runs and prints `1 2`.
- The only mixed declaration in the repository is one checker test
  (`tests/test_typecheck_literal_field_checks_cover_every_literal_form.bl`, `Both(Int, b: Int)`). None is in `lib/`,
  `src/`, `examples/` or `sections/`.

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in
independent-proposal, debate, vote rounds. Phase A is excerpted from each panelist's own text. Phase B and Phase C are
quoted in full from each panelist's file, without its heading line and without the line that lists the files read.

#### Phase A — Independent proposals

All six seats proposed that positional arguments come first, that position `i` fills field `i`, and that the §2.14
rules run on the filled set. They split on the declaration: sys, aiml and min forbade a mixed declaration; web, devops
and plt kept it.

- **Systems** (`A/sys.md`):

> Rule:
> 1. A positional argument at index `i` claims field `i`.
> 2. Positional arguments come first. A positional argument after a label is an error (reuse the E0527 `PositionalAfterKeyword` text, adapted to fields). Order among labels is free, as in a fully labelled payload.
> 3. Each label names a field not yet claimed. The §2.14 set rules run on the whole payload, with the positionally claimed fields already in the set: `DuplicateField` (E0316), then `NoSuchField` (E0525), then `MissingField` (E0315). Count error E0300 stays only for an all-positional payload.
> 4. Declaration: one variant may not declare both unnamed and named fields. This removes the `M(Int, b: Int)` shape. Unnamed fields cannot be named by a label, so such a variant forces a second rule for no gain in layout or speed.
>
> [...]
>
> Fields note: mark position-filled fields `(given by argument 1)` in the declares list for Duplicate and Missing diagnostics. The note is cheap to build and shows the index rule. Today it marks labels only.

- **Web/Scripting** (`A/web.md`):

> **Rule.** In a variant paren payload, positional arguments must come before labelled ones. Positional argument i fills field i. A label then names a field that no position has filled. After that, the §2.14 field rules run on the whole payload, in the existing order: DuplicateField, NoSuchField, MissingField. A labelled argument after a positional one is the normal case. A positional argument after a labelled one is an error.
>
> [...]
>
> **Fields note.** Mark every field a position or a label filled with `(given)`. The error then shows the user which slot is missing without counting. Marking labels only (today) hides the exact case this ticket is about.
>
> **Declarations.** No change. Keep accepting mixed `M(Int, b: Int)` and calls that omit labels on named fields. Do not forbid either now. Forbidding would break the 90% shape `Circle(1.5, tag: 2)`, which works today and reads like Kotlin/Python.

- **PLT** (`A/plt.md`):

> Model. A paren variant declares an ordered field list. Each field has an index; a field may also have a label. A call writes a list of arguments. Positional argument k claims field k. A label claims the field that carries that name. The call is well typed only if the claims form a bijection onto the fields: no field claimed twice, none unclaimed. This is one total function from argument lists to fill maps, so lowering never meets an unfilled field (the ICE is a hole in this function, not a codegen bug).
>
> [...]
>
> 1. Positional arguments come first, labelled arguments after. A positional after a label is `PositionalAfterKeyword` (E0527, widened from function calls to payloads). Order is then significant only in that way. Report it and stop; the fill map is not defined for that call.
>
> [...]
>
> Declaration. Do not change it. A mixed declaration `M(Int, b: Int)` is sound under the fill-map model: a label is an optional name on an index. Banning it would remove a rule, but also shrink the language for a gain no soundness argument needs. Record in §3.4 that a field is an index with an optional label.

- **DevOps** (`A/devops.md`):

> **Rule.** In a variant paren payload:
> 1. Positional arguments come first. A positional argument after a labelled one is E0527 (`PositionalAfterKeyword`), reused from §2.13 and worded for a variant payload. It reports at the positional argument with a `note:` at the first label. The code is the same as for functions, so users and tools learn one rule.
>
> [...]
>
> **Declaration.** I do not forbid mixed declarations. I do ask the spec to state that a variant may declare unnamed then named fields, and that unnamed fields can only be given by position. Forbidding mixed declarations is simpler for the checker. It is the min seat's likely proposal, and I would accept it. The diagnostics above need no change either way.

- **AI/ML** (`A/aiml.md`):

> 1. **A variant declares all-named fields or all-unnamed fields, never both.** `M(Int, b: Int)` is a declaration error (new code or an existing declaration code; devops to pick). Repo check: `rg` finds one mixed declaration in `lib/ src/ tests/`, and it is the test written for this question (`tests/test_typecheck_literal_field_checks_cover_every_literal_form.bl:50`). No stdlib or compiler code needs it.
> 2. **In a paren payload, positional arguments come first.** A positional argument after a label is an error, like Python and Swift. The positional at index `i` fills field `i`. A label then fills the field of that name.
>
> [...]
>
> - `Circle(tag: 2, 1.0)`: positional-after-label error. The current "argument 2 expects Int, got Float" misleads. Do not reuse E0527 (a function-call code); a new code, same spirit.

- **Minimalism** (`A/min.md`):

> Subtract first. Spec §3.4 gives no grammar for a variant with both unnamed and named fields, and the repo uses none [...]. So:
>
> 1. **A paren variant declares all-positional fields or all-named fields. Never a mix.** A mixed declaration is a declaration error (new code or reuse the nearest declaration-shape code; devops picks the text). This deletes the second note of the ticket: `M(b: 1)` cannot arise, because `M` cannot exist.
>
> [...]
>
> 4. **The fields note lists fields in order; it does not mark which ones a position filled.** The note exists to show the declaration. A "given" mark is a second display mode with its own formatting and tests. The `DuplicateField` message already says which field the position filled: "`radius` is already given by argument 1". That wording carries the information with no new note format.

#### Phase B — Debate (one round)

The moderator gave each seat a digest of the six Phase A files. The digest listed the points all six stated and five
variations: V1 (a variant that declares both unnamed and named fields), V1a (what `M(b: 1)` reports if the mix stays),
V2 (the code for a positional after a label), V3 (mark position-filled fields), V4 (when E0300 applies) and V5 (what
§3.4 states about writing a field by position). Each seat replied in full. Three seats changed their V1 position.

- **Systems:**

> **V1 (mixed declaration).** Forbid. The layout is the same either way, so I do not argue speed. I argue rule count: a mixed variant needs an "unnamed, positional-only" arm in every diagnostic. One mixed declaration exists, and it sits in a checker test, so the break cost is one file. Do not delete that test: keep its case and make it expect the new declaration error. Ballot: forbid / keep. I vote forbid. A new declaration error needs a code and a line: "a variant declares all-named or all-unnamed fields". `K.M(a: Int, Int)` is covered by the same rule.
>
> **V1a.** Only matters if V1 loses. Then `MissingField` for field 0 with "write it by position" (a user can follow that help; the web objection is about the "add `x:`" wording, so change the help, not the code). Ballot: MissingField with positional help / E0300 plus note.
>
> **V2.** Reuse E0527 and widen its text and the catalog entry to "a positional argument follows a labelled one in the same call or payload". One code per concept. A new code for the same mistake costs a second table row and a second explain page. Edit 02_syntax.md:1316 as min says.
>
> **V3.** Mark position-filled fields in the note, but only in Duplicate and Missing diagnostics, using the same `(given)` mark labels get. I drop my longer `(given by argument 1)`: one mark, not two. min's "second display mode" is wrong: the mark already exists for labels; this only makes it complete. Today's note lies when a position filled a field.
>
> **V4.** E0300 only when the payload has no label. Too many positionals with labels present: E0300 on the prefix is fine, same count test.
>
> **V5.** State it in §3.4, one sentence: a call may write any field by position or by label; a position claims the field at its index. Without it the spec leaves the rule implicit, which is how this ticket began.
>
> STATUS: ready to vote

- **Web/Scripting:**

> **V1. I change my vote: forbid mixed declarations.** In A I said "file the ban separately". The Facts change my mind. One test file declares a mixed variant, and nothing else in the repo does. A JS/Python dev understands "a variant is a tuple or a record". Nobody asks "which field can a label name?" if no mix exists. The ban removes the second note, the `M(b: 2, 1)` ICE, and the whole V1a question. I still want calls to keep both forms on an all-named variant (`Circle(1.0, 2)` and `Circle(1.5, tag: 2)`). That is the 90% case. Ballot: forbid / keep.
>
> **V1a. Moot if V1 passes.** If the ban loses, my vote stays E0300 plus a note. A MissingField help that says "write it by position" is also usable, and I accept it. I do not hold this point.
>
> **V2. Reuse E0527.** One idea across fn calls and payloads, one entry to look up. The catalog line needs a small widening ("in the same call or variant payload"). A second code for the same mistake adds a Stack Overflow question. Apply min's one edit to 02_syntax.md:1316. Ballot: reuse / new code.
>
> **V3. Mark filled fields, but keep it small.** I accept min's concern that a second display mode costs something. The cost is low: one `(given)` word, and the note already lists every field. The note is the only place a user sees which slot is left. Ballot: mark / do not mark. I vote mark. If it loses, DuplicateField must say "already set by argument N".
>
> **V4. Agree with plt, aiml and sys.** E0300 count error only when the payload has no label. With a label present, the field rules decide. Too many positionals with labels present: E0300 on the positional prefix.
>
> **V5. Yes, state it in §3.4 in one sentence:** "A call may write any field by position or, if the variant names it, by label." That keeps `Circle(1.0, 2)` legal on purpose. Do not add the "index with optional label" model (plt). It is a theory, and users do not need it.
>
> STATUS: ready to vote

- **PLT:**

> **V1 (mixed declaration). I change my position: forbid it.** In Phase A I called a mixed declaration sound, and it is. But sound is not the same as needed. With a ban, every field has either a label or no label across the whole variant, so the fill map is total on names: `MissingField` always has a name to print, and the V1a split (E0300 versus MissingField) disappears. The facts show one use, in a checker test, none in lib/, src/, examples/. Four of six seats forbid. Cost is a declaration error (code for devops) and a rewrite of the line 50 test shape; the test is replaced, not deleted. Ballot: forbid / keep.
>
> **V1a (if kept).** `MissingField` for field 0, not E0300. E0300 is a count error, and here the count is right; the web claim that MissingField help "cannot be followed" is a wording problem. Help text: "field 0 of M has no label; write it by position". Reporting a count error for a correct count is a wrong diagnosis. Note shows an unlabelled field as `Int  [position 0]` (devops form; I drop my "field 0 of M" form). Ballot: MissingField / E0300.
>
> **V2 (code).** Reuse E0527. One idea, one code: "positionals first". Edit 02_syntax.md:1316 as min says, and the ERROR_CATALOG.md:132 text and category. Ballot: reuse / new code.
>
> **V3 (given mark).** Keep my position: mark. I partly concede to min: the `DuplicateField` message names the position already, so it needs no mark. The case that needs it is `MissingField`: the note lists fields, and a position-filled field shown unmarked reads as unfilled. One mark, same form as labels. Ballot: mark / no mark.
>
> **V4.** E0300 only when the payload has no label, or has more positionals than fields. Any label means field rules. I agree with plt-1, aiml, sys, devops. min's text says the same when counts match; the only gap is labels with too few positionals, which gets field rules, not count.
>
> **V5.** Yes: §3.4 states that a field is an index, a named field may be written by position, and positional arguments fill by index. Without it the rule `Circle(1.0, 2)` is legal by accident of implementation. Required.
>
> Not on the ballot: positional-after-label as legal (nobody proposes it), ban on mixed calls (min and plt-2 treat it as fallback only).
>
> STATUS: ready to vote

- **DevOps/Tooling:**

> **V1. Ban mixed declarations: I move to support the ban.** My Phase A accepted either. The `M(b: 1)` case shows the cost of keeping: a label-only call that no diagnostic can finish, because field 0 has no name for a help line to use. A ban removes that shape, the `(a: Int, Int)` shape, and one `MissingField` text variant. The only user is a checker test. The ban needs one declaration code, with help "name every field or none". I do not want the ban to hold up the call-side rule: ballot V1 as a separate question.
>
> **V1a. If mixed stays: `MissingField` for field 0, not E0300.** I concede to plt, sys and aiml. In `M(b: 1)` the count is truthful, but E0300 plus a note gives no step the user can take, and `MissingField` keeps one family for "a field has no value". Text: `field 0 of M has no label, so only a position can fill it`. In the fields note an unnamed field shows as `_0`-free text: `(position 1)`. No label syntax.
>
> **V2. Reuse E0527.** A second code for the same mistake splits search, docs and quick fixes. Edits: ERROR_CATALOG line 132 ("in the same call or variant payload"), and the 02_syntax.md:1316 sentence gains min's exception. A category change to "Name resolution" is not needed; the check is on call shape. I oppose aiml's new code.
>
> **V3. Mark given fields, one mark, `(given)`, for position and label.** I answer min: the DuplicateField text names the filled position, but the E0300 note on `Circle(1.0)` and the MissingField note do not. Without the mark the note shows `radius` as if missing after the user wrote it. It is one word on a line that already exists, not a second mode.
>
> **V4. E0300 only for a payload with no label.** With a label, field rules run. Exception: more positionals than fields is E0300 on the extra positional, with or without labels, because no field can claim it.
>
> **V5. Yes, record it in §3.4:** a field is an index with an optional label, and a call may write a named field by position. Without it the `Circle(1.0, 2)` case rests on compiler behaviour only.
>
> **Ballot:** V1 {ban, keep}; V1a {MissingField, E0300+note} only if keep; V2 {reuse E0527, new code}; V3 {mark, no mark}.
>
> STATUS: ready to vote

- **AI/ML:**

> **V1 (forbid mixed declarations): support.** web and plt say a ban is a bigger change with no soundness gain. It is smaller than they say: the repo has one mixed declaration, in a checker test. A mixed variant is the only shape where a label cannot name a field. With it banned, the rule "any label means the field rules apply" has no exception. A model learns one rule, not one rule plus an exception for unnamed fields. Spec text should state the declaration rule in §3.4, so a model can learn it from the spec alone. Ballot: forbid vs keep.
>
> **V1a (if mixed stays): `MissingField` for the unnamed field.** devops and web want E0300 here. That keeps a second rule ("count error when some field has no name") that a model must predict from the declaration. `MissingField` with `help: field 0 of M has no name; write it by position` gives one rule for every payload that has a label, and the help text gives a repair that works. Ballot: MissingField vs E0300.
>
> **V2 (code): I change my vote. Reuse E0527.** Four seats reuse it. One code for "positional after a label" in calls and in payloads is one concept for a model to learn. A new code makes it two concepts with the same repair. §2.13 line 1316 needs the one-sentence edit min states. Ballot: reuse E0527 vs new code.
>
> **V3 (mark position-filled fields): keep `(given)`.** I reject min's view. The `DuplicateField` message names the argument, but `MissingField` for `tag` also prints the note, and the note then says `radius` is unfilled when the user wrote it. The note must match what the user wrote. Use one mark word, `(given)`, without an argument number; sys's `(given by argument 1)` is longer and adds nothing the Duplicate message lacks. Ballot: mark vs no mark.
>
> **V4 (E0300): only a payload with no label.** Agreed by all. A payload with any label uses the field rules. Too many positionals with labels present is E0300 on the positional prefix (plt).
>
> **V5 (state in §3.4 that an all-named variant call may write a field by position): yes, state it.** Today the spec is silent, and a model cannot learn from silence that `Circle(1.0, 2)` is legal. Use min's wording: a call may write each argument positionally or labelled. Put it in §3.4 as a rule, not a note.
>
> STATUS: ready to vote

- **Minimalism** *(dissent on V3)*:

> **V1. Forbid mixed declarations.** I hold. Facts: one mixed declaration exists, inside a checker test source; none in lib/, src/, examples/, sections/. web says a ban has a "bigger surface". It does not: it removes a form the spec never described. plt says a mixed declaration is sound. I agree it is sound, but sound is not the test. The test is whether the form earns its place, and nothing uses it. Keeping it costs a rule (V1a), a note format for unnamed fields, and a §3.4 sentence ("a field is an index with an optional label"). The ban costs one declaration error. The same ban also covers the named-then-unnamed shape `K { M(a: Int, Int) }` from p12. Ballot: "forbid" vs "keep".
>
> **V1a. If "keep" wins:** `M(b: 1)` gets `MissingField` for field 0, with help "field 0 of M has no name; write it by position". web's point that "add `x:`" cannot be followed is right, so the help text must differ. But one error family beats a second count-error path. Do not invent a label syntax for unnamed fields (devops is right).
>
> **V2. Reuse E0527.** I hold. A new code for the same idea ("positionals first") adds a catalog row and a second thing to learn. Widen the E0527 text and category, and make the one §2.13 edit at 02_syntax.md:1316. aiml's objection (a function-call code) is a naming point, not a cost point.
>
> **V3. No `(given)` mark.** I hold, with one concession. Five seats want the mark, so it will likely pass. If it passes, ship exactly one mark text, applied to position-filled and label-filled fields alike, and nothing else (no "given by argument N" variant). The DuplicateField message should still name the argument; that is free.
>
> **V4. E0300 only for a payload with no label.** Support. This is one test ("any label present?"), and it matches 03_types.md:2451 once reworded. For too many positionals with a label present, report E0300 on the positional prefix, as plt says; no new code.
>
> **V5. Say it in one sentence, not a new model.** `Circle(1.0, 2)` stays legal. Put one sentence in §3.4: "positional argument i fills field i." Do not add plt's "index with an optional label" model unless "keep" wins V1, because under "forbid" it is dead text.
>
> **Ballot:** V1 {forbid, keep}; V1a {MissingField, E0300}; V2 {reuse E0527, new code}; V3 {mark, no mark}; V4 {no-label only}; V5 {one sentence}.
>
> STATUS: ready to vote

#### Phase C — Final vote

Each seat voted alone on a ballot of six questions. Each entry gives the vote, the reasoning and the concern, quoted
in full.

- **Q1: A variant that declares both unnamed and named fields (`M(Int, b: Int)`, and `M(a: Int, Int)`)** (6-0). A: forbid it, a declaration error. B: keep it.
  - **Systems:** A — "A variant with an unnamed field forces an "unnamed, positional-only" arm in every diagnostic, and one test file is the only user. With the ban, a label always names a field, and the field rules have no exception." (From its reasoning: "The layout is the same either way, so I do not argue speed. I argue rule count.") Concern: "The ban breaks the one existing test shape at line 50 (it must be kept and changed to expect the new declaration error), and a user may later want to label only some fields."
  - **Web/Scripting:** A — "A JS or Python dev reads a variant as a tuple or a record, and nobody asks which field a label can name when no mix exists. The repo has one mixed declaration, in a checker test, so the break cost is one file. The ban removes the `M(b: 2, 1)` ICE shape and the second note format. Calls to an all-named variant keep both forms, which is the 90% case." Concern: "The declaration error needs a clear help line ("name every field or none"), or a user who copies a Swift-style mixed enum gets a terse rejection."
  - **PLT:** A — "With all-named or all-unnamed variants, every field has a total name map or a total index map. The fill-map rule then has no partial case: a label always names a field, and `MissingField` can always print the field it reports. A mixed declaration is sound, but it adds an arm to every diagnostic for a form that one checker test uses." Concern: "The declaration error needs a code and a clear help ("name every field or none"), and the line-50 test must be rewritten to expect that error, not deleted."
  - **DevOps/Tooling:** A — "A label cannot name an unnamed field, so every diagnostic that prints a field list or a MissingField help needs a second text for the unnamed case. A ban removes `M(Int, b: Int)` and `K(a: Int, Int)` and that second text. The help line is "name every field or none", which a user can follow." Concern: "The one mixed test at `tests/test_typecheck_literal_field_checks_cover_every_literal_form.bl:50` must change its expectation to the new declaration error, not be deleted, or the ban ships with no test."
  - **AI/ML:** A — "A variant that is all-named or all-unnamed is a rule a model can learn from the spec in one sentence. A mixed variant adds a decision point ("which field takes a label?") and an exception to "any label means the field rules apply". The repo uses no mixed declaration outside one checker test." Concern: "A model that writes `M(Int, b: Int)` from Swift habit gets a declaration error, so the error text must say "name every field or none" and show the fix."
  - **Minimalism:** A — "The spec never described the form, and the only user is one checker test. Forbidding it removes the `M(b: 1)` shape, the `M(b: 2, 1)` ICE and the `K.M(a: Int, Int)` shape. A label then always names a field, so the field rules have no exception. Adding the form back later costs less than removing it later. The test at line 50 stays and expects the new declaration error." Concern: "A declaration error is a new code and a new catalog row, and a user who wrote `M(Int, b: Int)` gets a hard break with no deprecation step."

- **Q2: If Q1 is B (keep), what `M(b: 1)` reports** (6-0). A: `MissingField` for field 0, with help such as "field 0 of M has no name; write it by position". B: the E0300 count error plus the fields note. Moot, because Q1 forbids the mix.
  - **Systems:** A — "The count of `M(b: 1)` is right, so E0300 gives a wrong diagnosis. MissingField keeps one error family for "a field has no value", and the help text can name a step the user can follow. This only matters if Q1 loses." Concern: "The diagnostic path gains an "unnamed field" arm that exists only because mixed declarations survived."
  - **Web/Scripting:** A — "I hold this point loosely, as B1 said. Five seats prefer one error family for "a field has no value", and the help text gives a step a user can follow. My objection was to the "add `x:`" wording, and the new help text fixes that. It only matters if Q1 loses." Concern: "A MissingField for a field that has no name can read oddly, since the user cannot write a label for it."
  - **PLT:** A — "The argument count in `M(b: 1)` is right, so E0300 gives a wrong diagnosis. `MissingField` states the true fault: field 0 has no value. The wording of the help text, not the code, is what the web seat objected to." Concern: "If B wins Q1, the spec has a second `MissingField` text variant that a reader must learn."
  - **DevOps/Tooling:** A — "The count is right, so E0300 names the wrong fault, and it gives the user no step to take. MissingField keeps one diagnostic family for "a field has no value". Its help must say "field 0 of M has no name; write it by position", not "add `x:`"." Concern: "If keep wins, the fields note needs a text for an unnamed field (`Int  [position 0]`) that no other diagnostic uses."
  - **AI/ML:** A — "The count is right in `M(b: 1)`, so E0300 diagnoses the wrong fault. `MissingField` keeps one family for "a field has no value", and the help gives a step a model can follow. This matters only if Q1 loses." Concern: "An unnamed field needs its own text arm in the diagnostic path, which is one more pattern to learn."
  - **Minimalism:** A — "This only matters if Q1 loses. Then one error family ("a field has no value") is smaller than a second count-error path. The count is right in `M(b: 1)`, so E0300 would report a wrong cause. Do not invent a label syntax for unnamed fields." Concern: "If Q1 loses, the diagnostic path needs an extra "unnamed field" arm, and every later change to MissingField must keep that arm correct."

- **Q3: The code for a positional argument after a label in a variant payload** (6-0). A: reuse E0527 `PositionalAfterKeyword`; widen the catalog row and edit §2.13 with the exception. B: a new code.
  - **Systems:** A — "One code per concept. A second code for "positionals first" costs a second catalog row and a second explain page for the same repair. The check is on call shape, and the cost to run time is zero in both options." Concern: "A function-call code now has a second use, and its explain text must cover both cases or it confuses readers of either."
  - **Web/Scripting:** A — "A Python dev knows "positional argument follows keyword argument" as one rule. One code for calls and payloads is one entry to look up, and one Stack Overflow answer. A second code for the same mistake gives two answers to the same question." Concern: "The E0527 category "Name resolution" and section reference §2.13 fit a payload less well, so the widened text must not mislead a reader of the catalog."
  - **PLT:** A — "The rule "positional arguments precede labels" is one rule with one typing condition on the argument list. One code for one rule composes across calls and payloads. A second code splits lookup with no gain." Concern: "E0527 sits in category "Name resolution", and a payload-shape error may read oddly there."
  - **DevOps/Tooling:** A — "One mistake, one code: search, `blink explain`, docs and quick fixes all key on the code. Two codes for the same repair split them. The cost is the ERROR_CATALOG.md:132 wording and the 02_syntax.md:1316 exception." Concern: "The catalog category for E0527 is "Name resolution" and §2.13 only; if the catalog and `explain` text are not widened in the same change, `blink explain E0527` will describe function calls only."
  - **AI/ML:** A — "One code for "positionals first" in calls and in payloads is one concept for a model to learn, and one entry to look up. I changed to this in B1. A second code gives two concepts with the same repair." Concern: "E0527 is filed under "Name resolution" and §2.13, so a model that searches the catalog for payloads may miss it unless the catalog text names payloads."
  - **Minimalism:** A — "One idea, "positionals first", gets one code. A new code adds a catalog row and an explain page for the same mistake. The 02_syntax.md:1316 sentence needs the one exception so that it does not contradict the rule." Concern: "E0527 sits in the "Name resolution" category and cites §2.13, so a payload error under it may mislead a user who searches by category."

- **Q4: Mark the fields that a position filled in a list of fields** (5-1, Minimalism dissent). A: one word, `(given)`, the same mark a label-filled field gets. B: no mark.
  - **Systems:** A — "The mark already exists for labels. Without it the note says a field is unfilled when the user wrote it, which is wrong in the exact case this ticket covers. One word on a line that already prints is not a second display mode." Concern: "Two mark texts may appear later, such as "given by argument N", if a later change adds detail to one site only. Keep one text."
  - **Web/Scripting:** A — "The note is the one place a user sees which slot is left. If a position-filled field shows unmarked, the note says `radius` is unfilled when the user wrote it. It is one word on a line that already exists, and labels already get it." Concern: "If a second mark text creeps in later (such as "given by argument 1"), the note becomes a display mode a user must learn."
  - **PLT:** A — "The note must describe the fill map the checker built. A note that shows a position-filled field as unfilled states a false fact about the program. One mark text for both fill sources keeps the note total." Concern: "Any mark text becomes output that tools and tests match, so a later change breaks them."
  - **DevOps/Tooling:** A — "The note lists the fields. A field a position filled, shown unmarked, reads as unfilled in a MissingField report for the same call. Labels already get this mark, so this makes it complete and adds no new display mode. One word, one text, as min asks." Concern: "If a later diagnostic prints the list without computing the position-filled set, it will show the wrong marks; build the list in one shared function."
  - **AI/ML:** A — "Without the mark, a note that lists `radius` as plain text reads as unfilled after the user wrote it. One word, the same word labels get, adds no second display mode. A model repairs from the note without counting arguments." Concern: "If the mark text is not used the same way on every note, models see two forms."
  - **Minimalism:** B *(dissent)* — "I hold. The `DuplicateField` message names the argument that filled the field, and that wording is free. A mark is a second display mode on a line that today means "fields of the declaration". If A wins anyway, ship exactly one mark text, `(given)`, for position-filled and label-filled fields alike, and nothing else." Concern: "Without a mark, the `MissingField` and E0300 notes list `radius` as if unfilled when the user wrote it by position, and a user may read the note as wrong."

- **Q5: Which diagnostics print the list of fields with the marks** (6-0). A: the E0300 count error and `MissingField`. B: `DuplicateField` and `MissingField`. C: the E0300 count error and `DuplicateField`.
  - **Systems:** A — "I changed from my B1 text ("only Duplicate and Missing"). Q4 A means the note carries marks wherever it prints. The E0300 note on `Circle(1.0)` also shows `radius` as unfilled after the user wrote it, so it needs the mark as much as MissingField does. DuplicateField needs no list: its message names the argument that filled the field." Concern: "Two sites build the note, and they can drift. Both must call one shared function."
  - **Web/Scripting:** A — "These two diagnostics ask "what is left to write", so the user needs the filled slots in view. `DuplicateField` already names the argument that filled the field, so the note adds nothing there. Printing the list in fewer places keeps the output short." Concern: "If `DuplicateField` loses its list and its message ever stops naming the argument, the user has to count positions by hand."
  - **PLT:** A — "The note is useful where the user must see which slot is left: `MissingField`, and the E0300 case `Circle(1.0)`. `DuplicateField` already names the argument that filled the field, so a note adds no new fact there." Concern: "A user who gets `DuplicateField` alone must count arguments by hand to see the full fill map."
  - **DevOps/Tooling:** A — "DuplicateField already names the argument that filled the field, so a list adds nothing there. The count error and MissingField say a field lacks a value, and the user needs the list to see which. This keeps the note where it exists today." Concern: "DuplicateField then shows no list, so a user with a long variant must count to find the argument it names."
  - **AI/ML:** A — "The note misleads where it lists a field the user filled as unfilled: on `MissingField` (`radius` filled, `tag` missing) and on the E0300 note for `Circle(1.0)`. `DuplicateField` already names the argument that filled the field, so a note there adds tokens and no information. I move from my Phase A choice (C) for this reason." Concern: "`DuplicateField` with no note gives a model less context when the repeated label is far from the position that filled it."
  - **Minimalism:** A — "These two diagnostics already print, or must print, the list, and they are the two where a reader asks "which field is left". `DuplicateField` has the argument in its message and needs no list. Option A also keeps the existing E0300 note unchanged, so it adds no new print site. Options B and C add a list to `DuplicateField`, which is new surface." Concern: "The `MissingField` note is a new print site for the list, so the note and the message can drift apart in later edits."

- **Q6: What §3.4 states about writing a field by position** (6-0). A: one sentence: a call may write any field by position or, if the variant names it, by label; a position fills the field at its index. B: state the model: a field is an index with an optional label.
  - **Systems:** A — "The rule is "a position fills the field at its index", and one sentence states it and keeps `Circle(1.0, 2)` legal on purpose. A model of "an index with an optional label" adds a concept the user does not need once mixed declarations are banned." Concern: "The sentence leaves the all-unnamed case implicit, and a reader may not see that it is the same rule."
  - **Web/Scripting:** A — ""A call may write any field by position or, if the variant names it, by label" is what a user needs, and it makes `Circle(1.0, 2)` legal on purpose. The "index with an optional label" model is a theory; a user does not need it. Under the Q1 ban it also describes a shape that no longer exists." Concern: "One sentence may leave the fill-by-index rule implicit, so the E0316 text must say which argument filled the field."
  - **PLT:** A — "I voted B in B1. Q1 A changes this: with no mixed declaration, "a field is an index with an optional label" describes a form the language no longer has. The one-sentence rule must still state that a position fills the field at its index, because that is the typing rule the ticket lacked." Concern: "One sentence may leave out the order rule (positionals first) unless the sentence or its neighbour states it."
  - **DevOps/Tooling:** A — "With Q1 forbid, every field is all-named or all-unnamed, so "an index with an optional label" is a model with no case that needs it. One sentence states the rule the compiler and the tooling use: a position fills the field at its index. Signature help and label completion follow from that sentence alone." Concern: "If Q1 goes to keep, one sentence will not cover unnamed fields and §3.4 needs the longer model."
  - **AI/ML:** A — ""A call may write any field by position or, if the variant names it, by label; a position fills the field at its index" states the legal calls and the fill rule in one line. The "index with optional label" model is theory a model does not need. With Q1 forbidding mixed declarations, the model has no case to describe." Concern: "If Q1 fails, the one sentence leaves unnamed fields in mixed variants unexplained."
  - **Minimalism:** A — "One sentence states the rule: a call may write any field by position or, if the variant names it, by label, and a position fills the field at its index. "A field is an index with an optional label" is a model that Q1-A makes dead text, because under the ban a field has a label or none by variant. Say the rule, not the theory." Concern: "A rule without the model leaves the next question (for example, pattern matching on a named field by position) to a later ticket."

#### Phase D — Round 2

Phase D did not run. No question was closer than 5-1.

#### Dissent and owner decision

Minimalism dissented on Q4 (no mark). Its own condition, in Phase B and Phase C: "If A wins anyway, ship exactly one mark text, `(given)`, for position-filled and label-filled fields alike, and nothing else." The spec ships exactly that text. The owner approved the tally; there was no tiebreak.

#### Reading gaps

- Phase A: the aiml, devops, min and plt files ran over the 500-word limit. No seat ran the probes. aiml, min and plt searched the repository only. plt read only one passage of the spec beyond the brief.
- Phase B: web read the digest and all six Phase A files, and ran no probes. devops read only 4 of the 6 Phase A files (not sys, not min). sys first drafted from the digest, then read all six files and kept its position.
- Phase C: all six seats report that they read every listed file.

### AI-First Review

| Criterion | Result |
|---|---|
| Learnability | Pass: positionals first, then labels, is the rule of Python and Kotlin calls; a variant is a tuple or a record, as in Rust |
| Consistency | Pass: one code (E0527) for a positional after a label in a call and in a payload; one mark (`(given)`) for every filled field |
| Generability | Pass: `Circle(1.0, 2)`, `Circle(1.5, tag: 2)` and `Circle(tag: 2, radius: 1.5)` all stay legal |
| Debuggability | Pass: every shape that stopped the build now fails in `blink check`, and the note shows which field an argument filled |
| Token Efficiency | Pass: no new syntax; every legal call is as short as before |

### Final Spec

```blink
type Figure { Circle(radius: Float, tag: Int) }
type Shape {
    Pair(Int, Int)                     // ok: no field has a name
    Both(Int, b: Int)                  // error[MixedVariantFields]
}

fn main() {
    let a = Figure.Circle(1.0, 2)                 // ok
    let b = Figure.Circle(1.5, tag: 2)            // ok
    let d = Figure.Circle(1.0, radius: 2.0)       // error[DuplicateField], error[MissingField]
    let e = Figure.Circle(tag: 2, 1.0)            // error[PositionalAfterKeyword]
}
```

- **Declaration (Q1).** A paren variant names every field or none. A mix, in either order, is `MixedVariantFields` (E0320) at the variant, help "name every field or none".
- **Order (Q3).** Positional arguments come first. A positional after a label is E0527, widened from calls to payloads.
- **Fill.** Argument `i` fills field `i`; a label fills the field it names; then `DuplicateField`, `NoSuchField`, `MissingField` run, in that order.
- **E0300.** Only for a payload with no label, or with more positional arguments than fields.
- **Note (Q4, Q5).** The fields note marks a filled field `(given)`, by position or by label, on the E0300 error and on `MissingField`.
- **§3.4 (Q6).** One sentence: a call may write any field by position or, if the variant names it, by label; a position fills the field at its index.
- **Breaking change.** A user who wrote a mixed declaration gets a hard error with no deprecation step. The one such declaration in the repository is a checker test, kept and changed to expect the new error.
