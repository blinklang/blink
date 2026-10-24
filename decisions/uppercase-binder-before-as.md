[< All Decisions](../DECISIONS.md)

# Uppercase Binder Before `as` — Design Rationale

§3.5 says that a bare name with an uppercase first character in a refutable pattern names a variant and never a
binder. It said nothing about the binder side of `name as pattern`. The compiler bound the name as a new variable, so
these programs compiled:

```blink
type Color { Red, Green }
const MAX = 10

fn f(c: Color) -> Int {
    match c {
        Red as Green => 1    // `Red` is a new binder
        _ => 0
    }
}

fn g(n: Int) -> Int {
    match n {
        MAX as m => m + 1    // `MAX` is a new binder that hides the constant
        _ => 0
    }
}
```

The question was whether the name before `as` may start with an uppercase letter, and if not, which error says so.

## Summary

| Q | Question | Result | Vote |
|---|---|---|---|
| Option | What the name may be | Option 1: in a refutable pattern, a binder before `as` that starts with an uppercase letter (`Lu` or `Lt`) is the new error `UppercaseBinder` (E0560). One code covers `Red as Green`, `MAX as m` and `Whole as Shape.Circle(r)`. E0308 and E0547 are not reused. An irrefutable pattern does not change | 6-0 |
| Q1 | Bad arm | A: a bad arm; add `UppercaseBinder` to the bad-arm list | 6-0 |
| Q2 | `help:` for `Red as Green` | A: two lines. Line 1 "to bind the value, write `red as Green`" is the only fix-it. Line 2 "to match the variant, write `Red`" is plain text, and appears only when the type has a variant of that name | 3-3 in Phase D, user tiebreak for A |
| Q3 | Guard help for a constant name | A: a second, non-applicable help names the guard `m if m == MAX`, only when a constant of that name is in scope | 5-1 (Minimalism dissent: B) |
| Q4 | The W1011 sentence in §10.6 | A: no change | 5-1 in Phase D (Minimalism dissent: B) |
| Q5 | The *binder* definition | A: add one sentence | 4-2 in Phase D (Systems, AI/ML dissent: B) |
| Q6 | *Pattern Binding (`as`)* | A: add one sentence | 4-2 in Phase D (PLT, Minimalism dissent: B) |
| Q7 | A lowercase variant name before `as` | B: no separate clause; "is a binder, never a variant" covers it | 5-1 in Phase D (Web dissent: A) |

Points all six seats stated in Phase B, not balloted: in a refutable pattern, the checker binds the name as written
for the arm body, so no `UndefinedVariable` (E0506) follows, and it never looks the name up as a variant or a
constant; the machine-applicable fix is the lowercase rename only, and only when the new name collides with no other
binder; no seat keeps `Red | Green` (Systems) or `red as Red` (AI/ML); the new text is one bullet after the
variant-or-binding bullets in §3.5, with the phrase "is a binder, never a variant".

### Compiler behavior before the decision

The moderator ran probes with the gen1 compiler and gave the results to the panel:

- `Red as Green => 1` then `_ => 0` on `Color { Red, Green }` compiles. `Red` is a new binder (an unused-variable
  warning); `f(Green)` is 1 and `f(Red)` is 0.
- `const MAX = 10` and `MAX as m => m + 1` on an `Int` compiles. `MAX` is a new binder that hides the constant.
- `Red as Green => 1` then `Red => 2` compiles and prints "1 2".
- `Whole as Shape.Circle(r) => r` compiles. `Whole` is a binder.
- `Red as x => 1` then `Green => 2` compiles. The first arm matches every value, and there is no unreachable report
  for the second.
- `match c { Red as x => 1 }` alone on `Color` compiles with no E0004.
- A nested `(Lo as a, b)` compiles. `Lo` is a binder.
- `let Blue as c = ...` is a parse error ("expected =, got as"), a separate open bug.
- A lowercase variant name before `as` (F2): on `type T { red, Green }`, `red as Green => 1` compiles with an
  unused-variable warning on `red`; `f(T.Green)` is 1 and `f(T.red)` is 0. The lowercase-variant bullet of §3.5 is
  not applied to the name before `as` today.

### Already decided (not reopened)

- Pattern binding syntax is `name as pattern` with the `as` keyword (DECISIONS.md, 4-1).
- In a refutable pattern, the first character of a bare name decides: an uppercase name is a variant (E0308 when the
  type is not an enum, E0547 when it has no such variant); otherwise the type-directed rule.
- In an irrefutable pattern, a bare name with no payload binds, and W1011 applies.
- The bad-arm rule and the W1011 rules in §10.6.

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in independent-proposal,
debate and vote rounds. Phase A and Phase B below are excerpts with attribution. Phase C and Phase D are verbatim.

#### Phase A — Independent proposals

All six seats proposed Option 1: a new error `UppercaseBinder` in a refutable pattern, one code for all three cases,
no reuse of E0308 or E0547, and no change in an irrefutable pattern. Sys and AI/ML also wrote an "allow it" fallback
that each opposed.

- **Systems:** "The arm is a bad arm (03_types.md:3697-3701). The compiler does not bind the name, does not look it up
  as a variant or a const, and checks the pattern after `as` as written." Help for `Red as Green`:
  "Did you mean `Red | Green`, or `x as Green`?"
- **Web/Scripting:** "A JS/Python dev reads `MAX as m` as "match MAX". Silent shadowing gives no error and `m` matches
  every value. That is the worst result: code runs and is wrong." Help: "to bind the value, write `red as Green`; to
  match the variant `Red`, write `Red`". Web first said the arm is a bad arm.
- **PLT:** "`binder as atomic_pattern` has two parts. The part after `as` is a pattern. The part before `as` is a
  binder." Bad arm: "no" in Phase A, with the reason "every repair renames the binder. A rename changes no coverage."
  Text: "is a binder, never a variant."
- **DevOps/tooling:** "Reading the binder as a variant would also make `Red as Green` mean "match `Red`, then match
  `Green`", and nobody writes that." Help: "write a lowercase binder: `red as Green`". The first help is
  machine-applicable "only when the new name collides with no other binder in the arm".
- **AI/ML:** "The text "Red as Green" is the most likely LLM mistake (it swaps the two sides, or reads `as` as a
  rename)." Help: "To match the variant and keep the value, write "red as Red"." Add the guard help "only when a const
  with that name is in scope".
- **Minimalism:** "Two rules for one lexical class ("uppercase never binds in a refutable pattern" and "except before
  `as`") is the surface growth to avoid. One rule, with no exception, is the smaller language." Help: "write a lowercase
  name, for example red".

#### Phase B — Debate highlights

- **PLT (changed position on the bad arm):** "I change my position: bad arm, yes. ... The bad-arm rule (F1) is the
  test: a report must stay true whatever repair the user makes. A coverage claim from the written arm does not pass
  that test."
- **Web (moved to PLT's Phase A position on the bad arm, then moved back in Phase C):** "I move to plt. Not a bad
  arm."
- **Systems:** "I concede. My text "does not bind the name" is wrong for the body. The checker binds the name as
  written, for the body only, so no `undefined variable` cascade appears." Also: "My `Red | Green` suggestion changes
  the meaning, so I drop it."
- **DevOps:** "It does not bind a "corrected" name; I wrote that wrongly." Also: "I oppose sys (`Red | Green` guesses
  an intent) and aiml (`red as Red` changes the arm into a different arm)."
- **AI/ML:** "I withdraw aiml-2." Also: "I drop `red as Red`." and, on F2: "State this in the new bullet: the type-directed
  rule does not apply to the binder side. Without that sentence a model will guess either way."
- **Minimalism:** "I drop my `MAX` guard help from Phase A; it adds a second help string to maintain." On F2: "Out of
  scope. The grammar says a binder is "a name the pattern binds", so a binder is never a variant."
- **Systems, PLT, DevOps (F2):** "Out of scope for this vote."

#### Phase C — Final vote

Each seat read all six Phase A files and all six Phase B replies, then voted alone.

**Q1. Bad-arm status of `UppercaseBinder`. A: bad arm, add it to the bad-arm list. B: not a bad arm. Result: A, 6-0.**

- **Systems — A.** Reasoning: A bad arm matches no value, so it never reaches lowering. The arm adds no catch-all, no
  lost switch and no lost exhaustiveness check. The compiler cannot know which repair the user picks (`Red as Green`
  can become `Red | Green`, which changes coverage). One uniform rule for every pattern error is cheaper to implement
  than a second class of errors. Concern: A user who renames the binder can see a new E0004 or unreachable report only
  after the repair, which looks like a second error.
- **Web — A.** Reasoning: In Phase B I argued that every repair is a rename. That claim fails against my own Q2 help:
  the help tells the user they may instead write `Red` to match, and that repair changes coverage. A report must stay
  true whatever repair the user picks, and a bad arm (matches no value) is the only reading that passes that test. It
  also keeps one rule for every pattern error, which a learner finds easier than a second class of errors. Concern:
  After the user renames `Red as x` to `red as x`, a new E0004 or "unreachable" report can appear that the first
  compile did not show, and a learner may see that as a new error.
- **PLT — A.** Reasoning: A report must stay true whatever repair the user picks. For `Red as x` the user may repair to
  `Red`, which changes coverage, so the written arm cannot claim the coverage of the pattern after `as`. A bad arm
  matches no value and keeps one rule for every pattern error. The checker still binds the name as written, so no E0506
  follows. Concern: A user who repairs by renaming the binder may see a new E0004 only after the fix, which reads as a
  late error.
- **DevOps — A.** Reasoning: The compiler cannot know which repair the user picks. `Red as x` may become `Red`, and
  `MAX as m` may become a guard. Both change coverage. If the arm counts as a catch-all, a later arm gets an
  "unreachable" report that can be false after the real repair, and E0004 goes silent. A bad arm matches no value, so
  each follow-up report stays true after any repair. It also uses the one existing rule, so the tools need no second
  class of error. Concern: A user may see E0004 after a lowercase rename, and read it as a second fault. The bad-arm
  text already accepts this cost.
- **AI/ML — A.** Reasoning: One rule is cheapest for a model to learn: an arm with an error matches no value. A split
  between bad-arm errors and non-bad-arm errors adds a decision point. A bad arm also removes the silent catch-all that
  hides later arms and turns off E0004. Concern: After the user repairs the arm, E0004 can show a gap that was hidden
  before, and a model may take that as a second, new error.
- **Minimalism — A.** Reasoning: One bad-arm rule with one reason (an arm with an error matches no value) is the smaller
  spec. Option B adds a second class of pattern errors that are not bad arms, with its own list entry and reason. A is
  also the safe choice: a repair such as `Red` instead of `Red as x` changes coverage, so no report from the written
  arm stays true. Concern: After the user renames the binder, an E0004 or a later-arm result can appear that the first
  compile hid.

**Q2. The `help:` for `Red as Green`. A: two repairs, bind with `red as Green`, or match with `Red`. B: one repair, the
lowercase rename. Phase C: A 3 (Web, PLT, DevOps), B 3 (Systems, AI/ML, Minimalism). Not decided in Phase C; re-voted in
Phase D.**

- **Systems — B.** Reasoning: The lowercase rename keeps the pattern the author wrote, and the compiler can state it with
  no guess. A second repair ("match with `Red`") names an intent the compiler cannot check. It also adds a second
  string to keep in step with the code. Concern: The user who meant a variant test gets one help that points away from
  that fix.
- **Web — A.** Reasoning: A JS or Python dev who writes `Red as Green` has one of two intents: bind the value, or match
  the variant. The help should name both, in that order. The bind repair is the only one the compiler can apply with no
  guess. Concern: A two-repair help is longer than a one-repair help, and a user may pick the matching repair when they
  wanted to bind.
- **PLT — A.** Reasoning: The error states a fault in the binder, and the user has two valid intents: bind, or test the
  variant. Naming both repairs is true for either intent. The rename stays the only machine-applicable fix. Concern:
  The `Red` repair drops the `as` and the pattern after it, so a user may apply it without seeing that it changes the
  arm.
- **DevOps — A.** Reasoning: The user who writes `Red as Green` can mean two things: bind the value, or test the
  variant. One repair line hides the second. Two lines in a fixed order cost little. Only the first line is
  machine-applicable, and only when the lowercase name collides with no other binder, so the LSP code action stays
  unambiguous. Concern: The second repair (`Red`) drops the `Green` pattern, so a user who applies it blindly may change
  the arm; the text must say "to match, write `Red`", not offer it as a fix-it.
- **AI/ML — B.** Reasoning: The compiler can state one repair with no guess: the lowercase rename `red as Green`. A
  second repair (`Red`) guesses intent, and a model that applies the wrong one changes coverage. One machine-applicable
  fix gives the fastest retry. Concern: A user who meant to match the variant `Red` gets no hint, and may need a second
  round to find the rule.
- **Minimalism — B.** Reasoning: One help string, one machine-applicable fix, no guess about intent. The second repair
  (`Red`) is a different arm, and the compiler cannot know the user wants it. The first repair already stops the error.
  Concern: A user who meant to test the variant `Red` gets a fix that binds instead.

**Q3. A guard help for a constant name (`MAX as m`). A: add a second, non-applicable `help:` line that names the guard
`m if m == MAX`. B: no guard help line. Result: A, 5-1 (Minimalism dissent).**

- **Systems — A.** Reasoning: `MAX as m` is the one case where the user most likely wants a constant compare. The guard
  `m if m == MAX` is the only existing way to write that, and the help costs the compiler one name lookup. It is not
  machine-applicable, so no fix can change meaning by mistake. Concern: A second help line is one more string that can
  go stale if a constant pattern is ever added.
- **Web — A.** Reasoning: A dev from Scala or Rust reads `MAX as m` as "match `MAX`". The lowercase rename alone does not
  teach that Blink has no constant patterns, so the user needs the guard form `m if m == MAX`. A second, non-applicable
  line costs little and answers the first question that dev will ask. Concern: The guard line is a second help string
  to maintain, and it must appear only when a constant of that name is in scope, or it misleads.
- **PLT — A.** Reasoning: Blink has no constant pattern, so the guard is the only way to compare with a constant. The
  user who wrote `MAX as m` almost surely wanted that comparison, and the rename alone leaves a catch-all arm. A second
  non-applicable line does not change the typing rule. Concern: The compiler must find that a constant of that name is
  in scope, which adds a lookup to a path that otherwise needs none.
- **DevOps — A.** Reasoning: `MAX as m` is the case where the user most likely wants to compare with the constant, and
  the lowercase rename alone sends them to a catch-all `max as m`. The guard line is the only text that shows the
  repair they need. It is a second `help:` string, but it is not applicable and has no edit logic. The compiler adds it
  only when a constant of that name is in scope. Concern: The compiler needs a constant lookup to decide when to print
  the line, and a wrong lookup prints a false help.
- **AI/ML — A.** Reasoning: `MAX as m` is the case where a model from other languages most likely wanted a constant
  test. The guard `m if m == MAX` is the only way to do that in Blink, and a model cannot learn it from the error
  alone. The second line is non-applicable, so it adds no auto-fix risk. The compiler emits it only when a const of
  that name is in scope. Concern: A second help string is more text to keep in step with the spec, and it can go stale
  if constant patterns are added later.
- **Minimalism — B.** Reasoning: A second help string needs a "const in scope" check, a text to maintain, and a test.
  The lowercase rename already ends the error. The guard idiom is language documentation, not a diagnostic duty.
  Concern: A user who meant to compare with `MAX` has no pointer to the guard form in the message.

**Q4. `sections/07_trust_modules_metadata.md`, the W1011 sentence "In a refutable pattern, a binder cannot have the name
of an uppercase variant, because an uppercase name there is the variant or an error (§3.5)." A: no change. B: replace it
with "In a refutable pattern, a binder cannot start with an uppercase letter (`UppercaseBinder`, §3.5)." Phase C: A 4
(Systems, PLT, DevOps, AI/ML), B 2 (Web, Minimalism). Not decided in Phase C; re-voted in Phase D.**

- **Systems — A.** Reasoning: The second sentence ("a binder cannot have the name of an uppercase variant") stays true
  under the new rule. It is narrower than the rule, but not false. Each extra edit in §10.6 is one more place to keep
  in step. Concern: The narrow sentence can make a reader think a non-variant uppercase binder is allowed in a
  refutable pattern.
- **Web — B.** Reasoning: The old sentence says a binder "cannot have the name of an uppercase variant". After this
  change the rule is wider: no uppercase first character at all, whether or not a variant has that name. A reader who
  sees only §10.6 must not learn a narrower rule than the real one. Concern: Two places now state the rule (3.5 and
  §10.6), and they can drift apart.
- **PLT — A.** Reasoning: The second sentence is still true under the new rule: a refutable binder cannot have an
  uppercase variant name, and it now also cannot have any uppercase first character. The third sentence (W1011 only
  for non-uppercase binders) stays true. The new rule lives in §3.5; one normative source is better than a restatement
  in §10.6. Concern: The sentence reads as narrower than the rule, so a reader of 07 alone may think `MAX as m` is
  allowed.
- **DevOps — A.** Reasoning: The second sentence ("a binder cannot have the name of an uppercase variant") stays true.
  It is narrower than the new rule, but it is not wrong, and the third sentence (W1011 only when the first character
  is not uppercase and no variant has the name) is still correct. A change to W1011 text adds risk for no gain in the
  diagnostic surface. Concern: A reader of W1011 alone may think an uppercase binder that is not a variant name is
  allowed; the new 3.5 bullet and the 3583 sentence are the only place that says it is an error.
- **AI/ML — A.** Reasoning: The existing W1011 sentence stays true: an uppercase binder never reaches W1011 in a
  refutable pattern. Each place that restates the rule is one more place that can drift, and a model reads the same
  fact twice. Concern: The sentence names only "uppercase variant", so a reader may think a non-variant uppercase
  binder is allowed there.
- **Minimalism — B.** Reasoning: The old sentence says a refutable binder cannot have the name of an uppercase variant.
  After Option 1 the true rule is wider: no uppercase first character. A sentence that is too narrow is a latent
  contradiction in the spec. The replacement is shorter and states the rule once. Concern: The same rule now sits in
  four places (3176 bullet, 3583, 2861, and the diagnostics table), which can drift apart.

**Q5. `sections/03_types.md`, the *binder* definition ("A **binder** is a name that a pattern binds: a variable
binding, a punned field name, or the name before `as`."). A: add one sentence: in a refutable pattern, a binder does not
start with an uppercase letter. B: no change. Phase C: A 4 (Web, PLT, DevOps, Minimalism), B 2 (Systems, AI/ML). Not
decided in Phase C; re-voted in Phase D.**

- **Systems — B.** Reasoning: The new bullet after 3176 and the sentence at 3563 already state the rule where a reader
  looks for it. A third copy at the *binder* definition repeats it for no gain. The definition at 3583 says what a
  binder is, and the rule says where it may start. Concern: The definition stays silent on the rule, so a reader of
  3583 alone misses it.
- **Web — A.** Reasoning: The definition of *binder* is the first place a reader looks to learn what a binder may be.
  One sentence there states the rule at the point of definition. It costs almost nothing. Concern: The sentence repeats
  the new bullet, so a later edit to one can miss the other.
- **PLT — A.** Reasoning: 3583 defines *binder*, and the grammar uses that term on the left of `as`. The constraint
  belongs with the definition, so the bullet after 3176 and the definition agree. It is one sentence. Concern: The
  rule now appears in two places, and a later edit to one can leave the other stale.
- **DevOps — A.** Reasoning: 3583 is where the definition of *binder* lives, and `blink explain` and the LSP hover will
  quote it. The rule should be on the definition, so a tool that shows the definition shows the constraint. Concern:
  Three places (bullet, 3583, 3563) say the same rule, and they can drift when it changes.
- **AI/ML — B.** Reasoning: The binder definition at 3583 says what a binder is. The rule on its first letter lives in
  the new bullet and in *Pattern Binding*. Three copies (3176, 3563, 3583) raise the drift risk for no gain in
  learnability. Concern: A reader who looks up "binder" alone does not see the uppercase restriction.
- **Minimalism — A.** Reasoning: The definition of *binder* is the one place every reader reaches for the term. One
  sentence there states the rule at its source, and the new bullet at 3176 can stay short. Concern: If 3583 and the
  3176 bullet differ in wording, a reader will look for a difference in meaning.

**Q6. `sections/03_types.md`, *Pattern Binding (`as`)*. A: after "Syntax: `name as pattern`." add "In a refutable
pattern, `name` starts with a lowercase letter or `_`." B: no change. Phase C: A 4 (Systems, Web, DevOps, AI/ML), B 2
(PLT, Minimalism). Not decided in Phase C; re-voted in Phase D.**

- **Systems — A.** Reasoning: A reader of *Pattern Binding (`as`)* sees the syntax and the rule in one place. The cost is
  one sentence and no runtime or codegen effect. Concern: Two places (the bullet and 3563) now state the rule and can
  drift.
- **Web — A.** Reasoning: A learner who reads only *Pattern Binding (`as`)* sees `name as pattern` and learns no limit
  on `name`. The `as` section is where a dev will write `Red as Green`, so the rule belongs there. One sentence is
  cheap. Concern: A third copy of the rule raises the drift risk further.
- **PLT — B.** Reasoning: With the bullet after 3176 and the sentence at 3583, a third statement adds a copy to keep in
  sync and no new fact. Section 3563 can stay a usage description. Concern: A reader who reads only *Pattern Binding
  (`as`)* does not learn the lowercase rule until the checker reports it.
- **DevOps — A.** Reasoning: A learner who reads only *Pattern Binding (`as`)* meets `name as pattern` there. One short
  sentence at the point of use prevents the error before the compiler reports it, and the explain page can link to it.
  The cost is one sentence. Concern: This is the third copy of the rule, so a later change must edit all three; a doc
  test that greps for the phrase would catch drift.
- **AI/ML — A.** Reasoning: *Pattern Binding (`as`)* is the first place a model looks for `name as pattern`. One
  sentence there stops the `Red as Green` mistake before the model writes it. This costs few tokens and adds no
  decision point. Concern: The sentence says "refutable", a term the reader must know, so a model may misread it for
  `let`.
- **Minimalism — B.** Reasoning: Q5 A and the 3176 bullet already state the rule. A third copy adds surface to keep in
  step and no new fact. Cut it. I said in B1 that I do not oppose it, but with Q5 A winning it is redundant. Concern: A
  learner who reads only the `as` section does not see the lowercase rule until the compiler reports it.

**Q7. A lowercase variant name before `as` (F2). A: the new bullet also says that the name before `as` is a binder even
when the type at that position has a variant of that name. B: leave it out of this text. Phase C: A 2 (Web, AI/ML), B 4
(Systems, PLT, DevOps, Minimalism). Not decided in Phase C; re-voted in Phase D.**

- **Systems — B.** Reasoning: A lowercase variant name before `as` is a separate rule about type-directed lookup. The
  phrase "is a binder, never a variant" already settles it, and the compiler already binds it. Keep this text to the
  uppercase question. Concern: Without the sentence, a model or reader can still guess that `red as Green` tests the
  variant `red`.
- **Web — A.** Reasoning: The 3176 bullet says a lowercase bare name is a variant when the type has one of that name. A
  dev who reads that will wonder if `red as Green` tests the variant `red`. One clause in the new bullet removes the
  question, and it matches what the compiler does today (F2). Without the clause, a model or a dev guesses either way.
  Concern: A rare case gets spec text, and a later change to the lowercase-variant rule must also change this clause.
- **PLT — B.** Reasoning: The phrase "is a binder, never a variant" already settles F2: the type-directed rule of the
  3176 bullet does not apply to the binder side. A separate clause would restate it and widen this decision to
  lowercase names. A lint for a lowercase binder equal to a variant name is a separate question. Concern: A reader may
  still ask whether `red as Green` on a type with variant `red` binds, because the text does not name that case.
- **DevOps — B.** Reasoning: A lowercase variant before `as` is a separate rule with its own diagnostic question (a lint
  for a binder that equals a variant name). Mixing it into this text delays the uppercase fix and widens the vote.
  File it as friction. Concern: Without a sentence, a model or user may guess that `red as Green` tests the variant
  `red`; the compiler binds it, and no tool reports the surprise until the friction ticket lands.
- **AI/ML — A.** Reasoning: Without the sentence, a model guesses whether `red as Green` tests the variant `red` or
  binds `red`. The spec must answer this, and one clause in the new bullet is cheaper than a separate ticket. Today's
  compiler already binds. Concern: The clause covers a rare case and widens this text beyond the uppercase rule, so a
  later change to the type-directed rule must edit two places.
- **Minimalism — B.** Reasoning: The grammar already says a binder is a name the pattern binds, and today's compiler
  agrees. Q5 A and the bullet "is a binder, never a variant" cover it without a special sentence. A lint for a binder
  that equals a variant name is a separate question for a friction ticket. Concern: A model or a reader may still
  guess that `red as Green` tests the variant `red` when the type has one.

#### Phase D — Round 2

Q1 (6-0) and Q3 (5-1) were decided in Phase C. Q2, Q4, Q5, Q6 and Q7 had no majority that the panel accepted, so the
moderator ran a focused debate on those five and then a second silent vote.

**Focused debate (excerpts).** Each seat answered the strongest argument against its Phase C vote.

- **Q2.** No seat changed. DevOps: "It states the other reading of the arm in one clause ("to match the variant, write
  `Red`"). The user with that intent gets a pointer, and the compiler guesses nothing. ... The help appears only when
  the type at that position has a variant of that name." PLT: "The text gives the rename as the fix-it, and gives `Red`
  as a plain statement ("to match the variant, write `Red`"), as devops asks." Minimalism: "devops says the text must
  not present it as a fix-it, which concedes the point."
- **Q4.** Web changed from B to A: "The old sentence is narrower than the rule, but it is not false. "The variant or an
  error" still holds, because `UppercaseBinder` is an error. The rule has one home in §3.5, and the sentence links
  there." Minimalism held B: ""not false" is not enough in a rule text. A reader of §10.6 alone sees "cannot have the
  name of an uppercase variant" and reads `MAX as m` as allowed."
- **Q5, Q6.** No seat changed. Systems: "a rule on its first letter is a constraint on where a binder may appear, not
  part of what a binder is." Web: "3583 is the definition of *binder*, and the grammar, `blink explain` and the LSP
  hover quote the definition." PLT on Q6: "A fourth statement of one rule is surface with no new fact."
- **Q7.** AI/ML changed from A to B: "plt's argument is right: "is a binder, never a variant" already settles the
  lowercase case, because "never" holds whatever the type has." Web held A: "It does not. The 3176 bullet right above
  says a lowercase bare name is a variant when the type has one of that name."

**Phase D vote.** Each seat voted alone after the focused debate.

**Q2. Result: A 3 (Web, PLT, DevOps), B 3 (Systems, AI/ML, Minimalism). Tie. User tiebreak: A.**

- **Systems — B.** Reasoning: The compiler can check only the rename. A line "to match, write `Red`" names a different
  arm and the compiler cannot verify the intent, so it is a hint, not a repair. One help string is also one string to
  keep in step with the code. Concern: The user who meant a variant test gets a help that points away from that fix.
- **Web — A.** Reasoning: A JS or Python dev who writes `Red as Green` may want to bind or may want to test the variant.
  The help gives the rename as the only fix-it, and states "to match the variant, write `Red`" as plain text (devops's
  wording). The compiler guesses nothing, and the dev with the second intent gets a pointer. Concern: The second clause
  is one more string to keep in step with the code, and a user may apply it without seeing that it drops the pattern
  after `as`.
- **PLT — A.** Reasoning: The error is a fault in the binder, and the user has two valid intents: bind the value, or
  test the variant. A help that names only the rename is true for one intent and silent on the other. The rename is
  the only fix-it; "to match the variant, write `Red`" is a plain statement and changes no edit logic, so no tool edit
  can change coverage. Concern: A user may apply the `Red` reading blindly and drop the `as` and the pattern after it,
  which changes the arm.
- **DevOps — A.** Reasoning: A user who writes `Red as Green` has two intents, bind or test the variant. The help names
  the rename as the fix-it and states "to match the variant, write `Red`" as plain text, so the compiler guesses
  nothing. Only the rename is machine-applicable, so no LSP edit changes coverage. Concern: A user or a model may apply
  the `Red` text blind, drop the `as` and the pattern after it, and change the arm.
- **AI/ML — B.** Reasoning: One help line with one machine-applicable fix gives a model one retry path and no intent to
  guess. The error text already says an uppercase name in a pattern is a variant, so a user who meant the variant test
  can read that from the message. devops and plt agree the `Red` clause is not a fix-it, so it adds a string to keep in
  step with the code and no edit. Concern: A user who meant to test the variant `Red` gets a help that points to a
  bind, and may need a second round.
- **Minimalism — B.** Reasoning: One help string, with one machine-applicable fix, is the smaller diagnostic. The `Red`
  line names a different arm, and devops, plt and web all agree it is not a fix-it, so it is a hint about intent that
  the compiler cannot check. The error text already says an uppercase name in a pattern is a variant, which tells the
  user the way to a variant test. Concern: If A wins, the help carries a second clause that must be kept in step with
  the code, and the compiler must test that the type has a variant of that name before it prints it.

- **User tiebreak: A.** The owner (BDFL) broke the 3-3 tie on Q2 for A. Reason: "under B the one suggested fix
  compiles but changes meaning for a user who meant the variant. Conditions kept: the variant line is plain text, never
  a fix-it, and appears only when the scrutinee type has a variant of that name."

**Q4. Result: A 5 (Systems, Web, PLT, DevOps, AI/ML), B 1 (Minimalism). A, 5-1 (Minimalism dissent).**

- **Systems — A.** Reasoning: "A binder cannot have the name of an uppercase variant" is narrower than the rule but not
  false, and the third sentence stays true. The rule has one normative home in 3.5, so no new copy in 07. web moved to
  A on the same ground. Concern: A reader of 07 alone may read an uppercase non-variant binder as allowed.
- **Web — A.** Reasoning: I moved in D1. The old sentence is narrower than the rule but not false, because
  `UppercaseBinder` is an error and "the variant or an error" still holds. The rule has one home in 3.5. A fourth copy
  costs more than a narrow true sentence. Concern: A reader of 07 alone may think `MAX as m` is allowed in a refutable
  pattern.
- **PLT — A.** Reasoning: "A binder cannot have the name of an uppercase variant" is narrower than the new rule but
  holds for every case the rule covers, and the third sentence of 2861 stays correct. The rule has one normative
  source, §3.5. A restatement in §10.6 is a copy that can drift. Concern: A reader of §10.6 alone may take `MAX as m`
  as allowed, because the sentence names only variants.
- **DevOps — A.** Reasoning: The second sentence of 07:2861 is narrower than the rule, but it is true: an uppercase
  binder is an error in 3.5, so it never reaches W1011. The rule keeps one normative source. A new sentence in 07 adds
  a fourth copy that can drift. Concern: A reader of W1011 alone may think an uppercase binder that is not a variant
  name is allowed.
- **AI/ML — A.** Reasoning: The old sentence is narrower than the rule, but it is not false, and the rule has one
  normative source in 3.5. A reader of 07 alone is sent to 3.5 by the section link. Each added copy is one more place
  to drift. Concern: A reader of W1011 alone may think an uppercase binder that is not a variant name is allowed.
- **Minimalism — B.** Reasoning: The replacement is shorter than the sentence it replaces, so it adds no surface. The
  old sentence says a binder cannot have the name of an uppercase variant, and the rule is now wider. A reader of
  §10.6 alone reads `MAX as m` as allowed, and four seats named that exact risk in their own Concerns. Concern: If A
  wins, the narrow sentence stays in 07 and the next edit to the rule will have to remember to widen it.

**Q5. Result: A 4 (Web, PLT, DevOps, Minimalism), B 2 (Systems, AI/ML). A, 4-2 (Systems, AI/ML dissent).**

- **Systems — B.** Reasoning: A rule on the first letter limits where a binder may appear. It is not part of what a
  binder is. The bullet after 3176 states it, and Q6 puts it at the `as` syntax, so a third copy adds drift risk and
  no new fact. Concern: A tool that quotes only the *binder* definition (hover, explain) does not show the rule.
- **Web — A.** Reasoning: 3583 defines *binder*, and the hover and `blink explain` quote the definition. A dev who looks
  up the term must see the constraint there. It costs one sentence. Concern: The sentence repeats the new bullet, so a
  later edit to one can miss the other.
- **PLT — A.** Reasoning: The grammar uses the term `binder` at 3126, and 3583 defines it. A constraint on what a binder
  may be belongs at that definition, which hover and `blink explain` quote. It is one sentence. Concern: The rule now
  sits in the bullet and at 3583, and an edit to one can leave the other stale.
- **DevOps — A.** Reasoning: 3583 defines *binder*, and `blink explain` and the LSP hover quote that definition. The
  constraint must be on the text those tools show. It costs one sentence. Concern: The bullet, 3583 and 3563 say the
  same rule, and they can drift when it changes.
- **AI/ML — B.** Reasoning: A rule on the first letter limits where a binder may appear. It is not part of what a binder
  is. The bullet after 3176 states it normatively. With Q6 A, the rule sits at the point where a model writes `name as
  pattern`, so a copy at the definition adds drift risk and no learnability. Concern: A tool that quotes the *binder*
  definition (hover, explain) shows no uppercase restriction.
- **Minimalism — A.** Reasoning: 3583 defines *binder*, the grammar uses that term left of `as`, and tools quote the
  definition. One sentence there keeps the bullet after 3176 short. Each of the three places then has one job: the
  bullet is normative, 3583 defines the term, and 2861 keeps W1011 true. Concern: The 3583 sentence and the bullet can
  differ in wording, and a reader will look for a difference in meaning.

**Q6. Result: A 4 (Systems, Web, DevOps, AI/ML), B 2 (PLT, Minimalism). A, 4-2 (PLT, Minimalism dissent).**

- **Systems — A.** Reasoning: A reader who writes `name as pattern` reads *Pattern Binding (`as`)*, so the sentence
  belongs at that point of use. It costs one sentence and has no codegen or runtime effect. Concern: Each added copy of
  the rule (bullet, 3563, and 3583 if Q5 A wins) can drift when the rule changes.
- **Web — A.** Reasoning: The `as` section is where a dev writes `Red as Green`, so the rule belongs at that point of
  use. Four seats on the Phase C result and three on the D1 holds give the same reason. The cost is one sentence.
  Concern: This is the third copy of the rule, so the drift risk grows.
- **PLT — B.** Reasoning: With the bullet after 3176 and the sentence at 3583, a third statement adds a copy to keep in
  step and no new fact. The compiler reports the rule with a help at the first mistake. Section 3563 stays a usage
  description. Concern: A reader who reads only *Pattern Binding (`as`)* does not learn the lowercase rule until the
  checker reports it.
- **DevOps — A.** Reasoning: The `as` section is where a user writes `Red as Green`, so one sentence at the point of use
  prevents the mistake before the compiler reports it. The explain page can link to it. A doc test that greps the
  phrase in each place controls drift. Concern: A learner who reads only *Pattern Binding (`as`)* sees the rule in a
  place that the other copies can later contradict.
- **AI/ML — A.** Reasoning: A model that writes `Red as Green` is reading *Pattern Binding (`as`)*, not the definition of
  *binder*. One sentence at that point stops the error before the compiler reports it. It costs few tokens and adds no
  decision point. Concern: The word "refutable" may be misread for `let`, and the rule now has several copies that can
  drift.
- **Minimalism — B.** Reasoning: With the bullet and the 3583 sentence, a third statement of the rule adds a copy and no
  new fact. The learner who writes `Red as Green` gets the error with a rename help at the first mistake. Cutting
  surface is what a copy count of three or four calls for. Concern: If A wins, a learner who reads only *Pattern
  Binding (`as`)* is better served, but the rule is now in a place that is easy to leave stale.

**Q7. Result: A 1 (Web), B 5 (Systems, PLT, DevOps, AI/ML, Minimalism). B, 5-1 (Web dissent).**

- **Systems — B.** Reasoning: "Is a binder, never a variant" holds whatever the type has, so it already settles a
  lowercase variant name before `as`. A separate clause ties this text to the type-directed rule, which may change.
  aiml moved to B on the same ground. Concern: A reader may still ask whether `red as Green` tests a variant `red`,
  until a lint or friction ticket covers it.
- **Web — A.** Reasoning: The 3176 bullet right above the new one says a lowercase bare name is a variant when the type
  has one of that name. A dev reads that and asks whether `red as Green` tests the variant `red`. "Is a binder, never a
  variant" is short, but one explicit clause removes the question and matches the compiler (F2). Concern: The clause
  ties this text to the type-directed lowercase rule, so a later change to that rule must edit two places.
- **PLT — B.** Reasoning: "Is a binder, never a variant" holds whatever the type has, so it settles the lowercase case:
  the type-directed rule of the 3176 bullet does not apply to the name before `as`. A separate clause restates it and
  ties this text to the lowercase-variant rule. A lint for a binder equal to a variant name is a separate friction
  ticket. Concern: A reader may still ask whether `red as Green` binds when the type has a variant `red`, because the
  text does not name that case.
- **DevOps — B.** Reasoning: "is a binder, never a variant" in the new bullet answers the lowercase case for every name,
  and the compiler binds today. A clause for lowercase variants ties this text to the type-directed rule, and the lint
  for a binder equal to a variant name is a separate diagnostic question. File it as friction. Concern: A reader may
  still guess that `red as Green` tests the variant `red`, and no tool reports the surprise until the friction ticket
  lands.
- **AI/ML — B.** Reasoning: "Is a binder, never a variant" holds for every name, lowercase included, so a model has no
  guess to make. A separate clause ties this text to the type-directed lowercase rule, which a later vote may change.
  The lint for a lowercase binder equal to a variant name is a separate friction ticket. Concern: A model may still
  guess that `red as Green` tests a variant `red` until a tool reports it.
- **Minimalism — B.** Reasoning: "Is a binder, never a variant" settles the lowercase case, because "never" holds for any
  type. aiml moved to B on this argument. A clause for a rare case ties this text to the type-directed rule, so a
  later change to that rule must edit two places. A lint for a binder equal to a variant name is a separate friction
  ticket. Concern: A reader may still ask whether `red as Green` tests the variant `red`, because the text does not
  name that case.

### Final Spec

```blink
type Color { Red, Green }
const MAX = 10

fn f(c: Color) -> Int {
    match c {
        Red as Green => 1       // error[UppercaseBinder]
        _ => 0
    }
}

fn g(n: Int) -> Int {
    match n {
        MAX as m => m + 1       // error[UppercaseBinder]
        _ => 0
    }
}

fn h(s: Shape) -> Int {
    match s {
        Whole as Shape.Circle(r) => r   // error[UppercaseBinder]
        _ => 0
    }
}

// correct forms
fn f2(c: Color) -> Int {
    match c {
        red as Green => red.to_int() + 1    // a lowercase binder, then the variant pattern
        _ => 0
    }
}

fn g2(n: Int) -> Int {
    match n {
        m if m == MAX => m + 1              // compare with a constant by a guard
        _ => 0
    }
}
```

```
error[UppercaseBinder]: binder `Red` starts with an uppercase letter
  help: to bind the value, write `red as Green`
  help: to match the variant, write `Red`
error[UppercaseBinder]: binder `MAX` starts with an uppercase letter
  help: to bind the value, write `max as m`
  help: to compare with the constant `MAX`, write a guard: `m if m == MAX`
error[UppercaseBinder]: binder `Whole` starts with an uppercase letter
  help: to bind the value, write `whole as Shape.Circle(r)`
```

- **Rule (Option 1, 6-0).** In a refutable pattern, a binder before `as` that starts with an uppercase letter (`Lu` or
  `Lt`) is the new error `UppercaseBinder` (E0560). One code covers a variant name, a constant name and a name that is
  neither. The name before `as` is "a binder, never a variant". E0308 and E0547 are not used. An irrefutable pattern
  does not change.
- **Body (Phase B, all six seats).** The checker binds the name as written for the arm body, so no `UndefinedVariable`
  (E0506) follows. It never looks the name up as a variant or as a constant.
- **Bad arm (Q1, 6-0).** The arm is a bad arm. `UppercaseBinder` joins the bad-arm list in §3.5 *Exhaustiveness*.
- **Help (Q2, 3-3, user tiebreak for A).** Line 1, "to bind the value, write `red as Green`", is the only fix-it, and
  only when the new name collides with no other binder. Line 2, "to match the variant, write `Red`", is plain text,
  never a fix-it, and appears only when the type at that position has a variant of that name.
- **Guard help (Q3, 5-1).** A second, non-applicable help names the guard `m if m == MAX`, only when a constant of that
  name is in scope.
- **§10.6 (Q4, 5-1).** The W1011 sentence in `07_trust_modules_metadata.md` does not change.
- **Binder definition (Q5, 4-2).** One sentence at the *binder* definition in §3.5: in a refutable pattern, a binder
  does not start with an uppercase letter.
- **Pattern Binding (Q6, 4-2).** One sentence at *Pattern Binding (`as`)*: in a refutable pattern, `name` starts with a
  lowercase letter or `_`.
- **Lowercase variant name (Q7, 5-1).** No separate clause. A lint for a binder that equals a variant name is a
  separate friction ticket, not part of this text.
- **Catalog.** ERROR_CATALOG.md has one new row, `UppercaseBinder` (E0560). `llms-full.md` has one new bullet.

### Notes

- The Phase C ballot named lines in the tree at that time. Main has moved, so the sentences sit at other lines in
  §3.5 and §10.6; the text above names each place by its heading.
- The W1011 sentence in §10.6 has been reworded since the panel voted. Q4 A leaves the current sentence as it is.
- The spec leads the compiler: the gen1 compiler of this tree accepts the three error examples above. The
  implementation of E0560 is separate work.
- The text does not say what type the binder has after the error, and it does not cover `mut Whole as ...`; the ruling
  does not speak to either.
- `let Blue as c = ...` does not parse today (a separate open bug), so the irrefutable half of the rule has no program
  to test yet.
