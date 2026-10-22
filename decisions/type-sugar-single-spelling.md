[< All Decisions](../DECISIONS.md)

# Single Type Spellings for List and Option — Design Rationale

**Question.** `T?` and `Option[T]` are the same type, and `[T]` and `List[T]` are the same type, so each has two spellings. Principle 2 says there is one way to do each thing; the panel picked one spelling for each.

**Result.** `List[T]` is the only list spelling; `[T]` in a type is W1120 `ListTypeBrackets`. `T?` is the only Option spelling in a type; `Option[T]` there is W1121 `OptionTypeLongForm`. Both are warnings with a machine-applicable fix for one minor release, then errors. The type parser reads `??` as two `?` suffixes (`Int??` = `Option[Option[Int]]`). The §3 "whichever the project chooses" sentence is deleted; no setting picks a spelling. Diagnostics print only the canonical spelling. Spec: §2.2, §3.2 *One Spelling for List and Option Types*, §5, §7 prelude table; ERROR_CATALOG W1120, W1121.

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in independent-proposal → debate → vote rounds. Panelist text below is verbatim; "..." marks a cut.

#### Phase A — Independent proposals

- **Systems:**
  > `T?` is the only spelling of Option in type position. Keep the locked §2.2 row. Fix the formatter, not the spec.

  > `T?` saves 8 characters, or 1 token against 3 to 4. Optionals appear in every signature, so the savings add up.

  > `[T]` is not a type. `List[T]` is the only spelling.

  > Keep `[T]` parsing for one release as a warning, with a machine-applicable fix to `List[T]`. Then make it a hard error with the same fix text.

- **Web/Scripting:**
  > Keep `T?` and `List[T]`. Remove `Option[T]` and `[T]` as written spellings. Ship one project-wide rule: the surface is `T?` and `List[T]`, and the formatter rewrites toward them.

  > The compiler accepts `Option[T]` and warns (lint, auto-fixable) toward `T?`. Do not make it a hard error.

  > I will not accept "project chooses" as the answer. That recreates the problem and no mechanism for it exists.

- **PLT:**
  > Remove both type-position sugars. The canonical forms are the ordinary applied constructors `Option[T]` and `List[T]`. Amend the locked §2.2 "Option sugar" row.

  > They do not compose. `Option[Option[Int]]` has no sugared spelling. `Int??` lexes as the `??` operator, and `[Int]?` is a parse error.

  > Alternative B (fallback): Keep `T?` as the only Option spelling and drop `[T]`... It is the cheaper choice if the panel treats the §2.2 row as binding.

- **DevOps/Tooling:**
  > `[T]` type sugar: remove it. Canonical is `List[T]`.

  > `T?`: keep it as the single canonical spelling. Deprecate `Option[T]` in type position.

  > `Int??` fails today because the lexer produces the `??` token. The type parser should split `??` into two `?` tokens in type position, so `Int??` means `Option[Option[Int]]`.

  > Summary vote: `List[T]` only. `T?` only. Split `??` in type position. Make `blink fmt` emit `T?`. Add migration diagnostics with fixes.

- **AI/ML:**
  > Remove both sugars. The canonical forms are `List[T]` and `Option[T]`.

  > A model that learns "`T?` means Option" will write `[Int]?` or `Int??` and get a parse error. This is a learnability trap, and the long form never has it.

  > Proposal B (fallback, if the panel insists on one sugar): keep `T?`, drop `[T]`.

- **Minimalism:**
  > `T?` is the one spelling for Option. `Option[T]` stays only as the name of the type.

  > `[T]` sugar for List is removed. `List[T]` is the one spelling.

  > Fix by lexing `?` in type position only, as two `?` tokens. Then `Int??` is `Option[Option[Int]]`, and `[Int]?` works.

  > Vote lean: yes on P1 (with the `??` lexing fix), yes on P2 (removal with a one-release warning).

#### Phase A.5 — Option space

Facts from the brief: the §2.2 *Locked Syntax Decisions* table says "None are revisitable" and holds the `T?` row; `[T]` has no §2.2 row. The measured `blink fmt` rewrites both `[Int]` to `List[Int]` and `Int?` to `Option[Int]`. `Int??` and `[Int]?` are parse errors today.

- **Q1 — List type spelling.** L1: `List[T]` only, `[T]` removed (proposed by all six). L1-a: warning with a machine-applicable fix for one release, then a hard error (Sys, PLT, DevOps, AI/ML, Min). L1-b: hard error with a fix at once (Web).
- **Q2 — Option type spelling.** O1: `T?` only in type position (Sys, Web, DevOps, Min; second choice of PLT and AI/ML). O2: `Option[T]` only in type position, `T?` removed from types (PLT, AI/ML; second choice of Sys and DevOps). O2 requires an explicit recorded override of the §2.2 row.
- **Q2n — nested Option under O1.** N1: split `??` into two `?` in the type parser. N2: `Option[Option[Int]]` stays, named in the spec as the one place the long form is used. N3: parentheses `(Int?)?`.
- **Q2l — `Option[T]` written in a type annotation under O1.** G1: legal, `blink fmt` rewrites to `T?`, no diagnostic. G2: default-on lint with a fix. G3: warning with a fix for one release, then a hard error with a fix.
- **Q3 — the §3 sentence "the canonical formatter normalizes to whichever the project chooses".** Delete it; no project setting (all six proposed this).
- **Q4 — diagnostics print only the canonical spelling** (raised by DevOps).

#### Phase B — Debate highlights

- **AI/ML moved to O1, on two conditions.**
  > I shift. I now accept O1 (`T?` only) on two conditions.

  > Condition 1 is O1-nest: **split `??` into two `?` in type position**, so `Int??` is `Option[Option[Int]]`.

  > Condition 2 is O1-long: **after migration, `Option[T]` in a type annotation is a hard error with a fix-it, not a legal alternative.** "Legal and rewritten by fmt" is exactly the dual spelling this ticket removes.

  > If O1 fails the vote on nesting or on O1-long, I go back to O2.

- **Minimalism moved to O2.**
  > I move to O2 (`Option[T]` only). I changed my mind after reading PLT and AI/ML.

  > O1 is not free. It needs a new lexer rule in type position: split `??` into two `?` tokens... The language gets smaller with O2.

  > My ranking: O2 first, O1 with the split second, keep both never.

- **PLT kept O2.**
  > I keep O2, with a conditional concession.

  > Two accepted spellings is the defect that this ticket exists to remove. The lint must be on by default and must fail `task ci`-style checks.

- **Systems moved to N1 (nesting) and held O1.**
  > O1-nest: I change my position. Split `??` into two `?` tokens in type position. My Phase A said the formatter keeps `Option[Option[Int]]`. Min is right that this leaves two spellings for one type, which breaks the rule we are trying to enforce.

  > O1-long: legal, `blink fmt` rewrites to `T?`. No hard error.

- **Web moved to G1.**
  > O1-long: I shift my position. Make `Option[T]` legal, and have `blink fmt` rewrite it to `T?`. Do not warn on it. I said "warn" in Phase A, but a warning in every generic file is noise, and the formatter already enforces one spelling.

  > Q1 (L1-a vs L1-b): I concede L1-a.

- **DevOps moved to G1.**
  > O1-long: I shift. Drop my "hard error or lint after migration". Make `Option[T]` legal, and have `blink fmt` normalize it to `T?`, as Sys and Min propose.

  > The corpus counts argument is circular. `blink fmt` rewrites `Int?` to `Option[Int]` today, so 2957 `Option[` in tests partly measures the formatter, not what authors or models choose.

All six stated L1-a in Phase B, and all six stated "Delete the sentence" for Q3 and canonical-spelling diagnostics for Q4.

#### Phase C — Final vote

##### Q1 — List migration: L1-a, 6-0

- **Systems:** L1-a — "The bootstrap protocol needs the parser to accept `[T]` until src, lib and tests migrate, so a one-release warning is the safe path. The fix-it still corrects AI-written code in one step."
- **Web/Scripting:** L1-a — "The bootstrap protocol already needs a warn stage, so the warning costs nothing extra. A JS or Python dev who hits the old form gets a fix-it, then a hard error. One release is enough."
- **PLT:** L1-a — "One warning release with a machine-applicable fix keeps existing projects building. The formatter already rewrites `[T]`, so the fix costs nothing."
- **DevOps:** L1-a — "Shipping a release at the warning stage gives users with their own code a clean `blink fix` path. The hard error carries the same fix, so nothing is lost."
- **AI/ML:** L1-a — "The bootstrap protocol already requires stepwise migration, and a warning release lets the corpus and the compiler source move before the hard error lands... L1-b would also be acceptable."
- **Minimalism:** L1-a — "The sugar must leave src, lib and tests before the parser rejects it, because of the bootstrap protocol. So a warning stage exists anyway."

Concerns on the warning stage: Systems: "The warning period may become permanent if nobody schedules the hard-error release." DevOps: "If the warning stage lingers past one release, the corpus keeps both spellings." Minimalism: "A warning stage can stay open for many releases if nobody schedules the hard error." Web: "The warning period can drag on and leave two spellings in the corpus." PLT: "If the warning release is skipped or the hard-error date slips, two spellings stay in training data." AI/ML: "Models trained on text from the warning release will keep seeing both forms for a while."

##### Q2 — Option type spelling: O1, 4-2

- **Systems:** O1 — "`T?` and `Option[T]` produce the same type node, tid and C layout, so the choice is about tokens and honoring a locked §2.2 row. `T?` is about half the tokens at every signature and field. The corpus counts for `Option[` come from the formatter bug, not from user choice." Concern: "Postfix `?` in types sits next to the `?` and `??` expression operators, so the parser and error messages must stay precise."
- **Web/Scripting:** O1 — "`Str?` is the form a JS, Kotlin or Swift dev reads with no explanation, and Option appears in most signatures. The §2.2 row already locks it, so O1 needs no override. The nesting and `?` overload objections are parser fixes, not reasons to remove the sugar." Concern: "`Option` and `List` end up unequal (one has sugar, one does not), and the `Ptr[T]?` reservation needs care."
- **PLT:** O2 *(dissent)* — "`Option[T]` is an ordinary applied constructor and composes with no extra rule. `T?` is incomplete today (`Int??` fails to parse) and reuses a token that is also an expression operator. Deleting the sugar removes a grammar special case and matches what the formatter does now." Concern: "O1 may win on the "locked row" argument, and then every `Option[` use in 3000+ tests and the stdlib is rewritten for a notation that needs a grammar fix."
- **DevOps:** O1 — "`T?` is in the locked §2.2 row, and the formatter disagreeing with it is a tool bug, not a spec defect. The type suffix and the expression `?` are never ambiguous to a parser." Concern: "`T?` leaves `?` with several meanings across type and expression position, which may confuse learners and models."
- **AI/ML:** O1 — "With `[T]` gone, `List[Int]?` parses, and the only composition failure left is `Int??`, which N1 fixes. O1 keeps the locked §2.2 row, so it needs no override, and `T?` costs fewer tokens in signatures. One spelling per type is the goal, and O1 reaches it if Q2l is strict." Concern: "If Q2l ends up lenient, O1 leaves two spellings of Option and is worse than O2."
- **Minimalism:** O2 *(dissent)* — "O2 removes the most surface. There is no type-suffix `?`, no `??` split rule, and no nest rule. `?` and `??` mean one thing each, in expressions." Concern: "It overrides a row marked "none are revisitable", and it adds 1 to 3 tokens per signature."

##### Q2n — Nested Option under O1: N1, 6-0

- **Systems:** N1 — "Splitting `??` into two `?` in type position is a parser-only change with zero runtime cost. N2 leaves two spellings of one type, which breaks the goal." Concern: "Token splitting in the type parser is context-dependent, and a bug there could change how `??` parses in expressions."
- **Web/Scripting:** N1 — "In type position `??` can only mean two suffixes, so the parser can split it with no ambiguity. This keeps one spelling for nested Option." Concern: "Splitting a token in the type parser is a special case that must have tests, including `Int??` next to the `??` operator."
- **PLT:** N1 — "The type parser can read one `??` token as two `?` suffixes, with no lexer mode. Then `T?` composes for every depth, and no second spelling is needed." Concern: "The split rule is context-dependent parser behavior that the grammar text must state exactly, or expression and type readings of `??` drift apart."
- **DevOps:** N1 — "Splitting `??` in the type parser (not the lexer) gives nested Option a sugar spelling, so the sugar composes. N2 leaves a second spelling in the spec, and N3 adds a third." Concern: "Context-sensitive token splitting needs a precise rule, or `x as Int??` and `a ?? b` edge cases will produce confusing parse errors."
- **AI/ML:** N1 — "The type parser already knows it is in type position, so it can read a `??` token as two `?` suffixes. This keeps one spelling for every Option, including nested ones." Concern: "`Int??` reads like the default operator to a human or model skimming code, so the spec needs one example."
- **Minimalism:** N1 — "N2 keeps two spellings of one type, which defeats the point of choosing O1. N3 adds a parenthesized type form. N1 is one lexer rule in type position and leaves one spelling." Concern: "N1 makes the lexer depend on context."

##### Q2l — `Option[T]` in a type annotation under O1: 2-2-2 (G1 Web/DevOps, G2 Sys/Min, G3 PLT/AI-ML)

- **Systems:** G2 — "`Option` stays a real type name, so a hard error would be too strong. A default-on auto-fixable lint plus the fmt rewrite enforces one spelling without blocking code. G1 gives no signal to AI authors."
- **Web/Scripting:** G1 — "`Option[T]` is the real type name and stays legal. The formatter already enforces one spelling, so a diagnostic is noise in generic code and in docs." Concern: "With no diagnostic, hand-written `Option[T]` stays in code not run through the formatter, and the corpus keeps both spellings."
- **PLT:** G3 — "Two accepted spellings is the defect this ticket removes. One warning release with a fix, then a hard error with a fix, matches the L1-a path and leaves one spelling. `Option` stays a valid type name outside annotations, for example in `Option.some(x)`." Concern: "A hard error on `Option[T]` may surprise users who write the full name of a type they know from the prelude."
- **DevOps:** G1 — "The formatter normalizes it, which satisfies Principle 2 without a flag day over thousands of test sites." Concern: "Silent acceptance means hand-written `Option[T]` persists in the corpus until someone runs fmt."
- **AI/ML:** G3 — "G1 and G2 leave `Option[T]` legal, which is the dual spelling this ticket removes. A warning for one release, then a hard error with a fix-it, matches the `[T]` path in Q1 and makes the corpus converge on one form." Concern: "`Option[T]` appears about 3000 times in tests and 187 times in src, so the migration is large and must be fully mechanical."
- **Minimalism:** G2 — "`Option` is a real prelude name, so a hard error is wrong. A default-on lint with a fix steers users to `T?` without a second migration stage." Concern: "A lint that `blink fmt` also fixes is redundant for users who run the formatter."

##### Q3 — Delete the §3 "whichever the project chooses" sentence: YES, 6-0

- **Systems:** YES — "No project setting exists, and one would split the corpus and break Principle 2. Delete the sentence."
- **Web/Scripting:** YES — "No setting exists, and a project choice splits the corpus and breaks Principle 2." Concern: "Other spec text may repeat the same claim, so grep for it."
- **PLT:** YES — "No project setting exists, and a setting would break Principle 2. The spec should say that `blink fmt` is the single normalizer." Concern: "The sentence may be copied into other text (llms docs, the §7 prelude row), so a grep sweep must find all copies."
- **DevOps:** YES — "No project setting exists, and one would break Principle 2 and split the corpus. The sentence is also wrong about current behavior."
- **AI/ML:** YES — "No project setting exists, and the sentence breaks Principle 2. A model reading it would conclude that the spelling is a per-project choice." Concern: "None significant; check that no other section repeats the claim."
- **Minimalism:** YES — "No project setting exists. The sentence contradicts Principle 2."

##### Q4 — Diagnostics print only the canonical spelling: YES, 6-0

- **Systems:** YES — "The printer renders from the type node, so one canonical rule (Option as `T?`, List as `List[T]`) is cheap and consistent. The text a user sees then matches what fmt emits." Concern: "Messages that quote user source may then differ from the spelling in that source, which can confuse a reader."
- **Web/Scripting:** YES — "A message should show what the formatter writes, so a user can copy the text into the code. A fix text in a different spelling than the formatter creates a loop." Concern: "Printing `Str?` for a user type that shadows `Option` could mislead, so the printer should use the compiler-known type, as the identity rule says."
- **PLT:** YES — "A message that prints the non-canonical form teaches the wrong spelling to users and to models that train on the output." Concern: "Existing diagnostic goldens must change in the same commit as the formatter and spec, or the gate breaks."
- **DevOps:** YES — "Messages and fix text should show what `blink fmt` emits, so a user can paste a suggestion and not see it rewritten." Concern: "Types written long-form by the user will print in sugar, which can look like a different type until users learn the equivalence."
- **AI/ML:** YES — "What a model reads in an error must match what it should write." Concern: "Messages that echo user source text could still show a non-canonical spelling during the warning release."
- **Minimalism:** YES — "The text a model sees in an error should match the text it writes." Concern: "Fix text in old diagnostics (E0301) must be updated in the same change, or it will print the removed form."

#### Phase D — Round 2 (Q2 and Q2l)

Trigger: Q2 split 4-2 and Q2l split 2-2-2. Q1, Q2n, Q3 and Q4 were closed at 6-0. The moderator noted that AI/ML's Phase C ballot said "If Q2l ends up lenient, O1 leaves two spellings of Option and is worse than O2."

**Debate highlights.**

- **AI/ML (Q2l stays G3; Q2 follows Q2l):**
  > Web's argument that the formatter enforces Principle 2 holds for whitespace and layout. It does not hold for syntax. If two token sequences both compile and mean the same type, the language has two ways.

  > If G3 wins, O1 gives one spelling, keeps the locked row, and costs fewer tokens. I vote O1. If G1 or G2 wins, O1 leaves two accepted spellings of Option... Then O2 is the only option that reaches one spelling, and I vote O2.

- **PLT:**
  > I propose the error only for `Option[T]` in a type annotation, where `T?` has the same meaning. `Option.some(x)`, `impl` headers, trait bounds, and docs that name the type stay legal.

  > The formatter acts on files that someone formats. A model that writes `Option[Int]` and never runs fmt keeps the second spelling in the corpus.

- **Systems moved G2 to G3:**
  > fmt is a tool, and the compiler is the spec. A spelling the compiler accepts is a spelling in the corpus. The `[T]` path in Q1 already accepted this: warning, then error.

  > If G3 loses and Q2l ends lenient, I would then switch to O2, because I will not accept two spellings of Option.

- **Web moved G1 to G3:**
  > If `Option[T]` stays legal with no signal, O1 leaves two Option spellings in the corpus. That is the exact defect in the ticket, and then O2 is the better answer.

  > A lint that fmt fixes silently (G2) is ignored by anyone who never runs fmt. This is Sys's own concern. A hard error cannot be ignored.

- **DevOps moved G1 to G3:**
  > AI/ML's condition is correct. If `Option[T]` stays legal with no hard stop, O1 leaves two spellings of Option, and the ticket exists to remove exactly that.

  > Tests are rewritten by tool, not by hand, so 2957 sites cost CPU time, not review time.

- **Minimalism moved G2 to G3:**
  > A lint stays forever, and a lint that fmt fixes is a rule with no end. G3 has an end: one warning release, then a hard error with a fix.

  > So my vote is: G3 and O1 together, or else O2. I do not want O1 with G1.

**Re-vote.**

##### Q2 — O1, 5-1 (PLT dissent: O2)

- **Systems:** O1 — "With N1 settled, the composition objection is gone, and with G3 the two-spelling objection is gone." Concern: "If Q2l ends lenient, O1 leaves two spellings of Option and O2 would be the better result."
- **Web/Scripting:** O1 — "With G3, O1 ends with one Option spelling in type position, so the ticket closes. `Str?` is the form JS, Kotlin and Swift devs read with no explanation, and it needs no override of the locked §2.2 row." Concern: "If G3 fails, O1 leaves two spellings, and the panel should then revisit O2."
- **PLT:** O2 *(dissent)* — "`Option[T]` is an ordinary applied constructor and needs no grammar rule beyond type application. `T?` needs the N1 split rule and reuses a token that is also an expression operator." Concern: "If O1 wins with a lenient Q2l, the corpus keeps both spellings and the ticket's goal is missed."
- **DevOps:** O1 — "`T?` is in the locked §2.2 row, so O1 needs no override. With N1 the nesting defect is fixed, and with `[T]` gone `List[Int]?` already parses." Concern: "`?` now has meanings in type and expression position, so parser errors and docs must keep them clearly separate."
- **AI/ML:** O1 — "Sys, DevOps, Web and Min all moved to G3, which was my stated condition. Under G3 only `T?` parses in type position after one release, so O1 gives one spelling per type." Concern: "If the final Q2l result is not G3, my condition fails and O1 would leave two spellings of Option."
- **Minimalism:** O1 — "With G3 the panel can reach one spelling of Option without an override of the locked row. O1 keeps the shorter form in the most common signatures." Concern: "If Q2l ends G1 or G2, O1 leaves two spellings and O2 would have been better."

##### Q2l — G3, 6-0

- **Systems:** G3 — "Principle 2 requires one accepted spelling, and a tool that rewrites a spelling the compiler still accepts does not remove it from the corpus. G3 follows the same warning-then-error path as `[T]` in Q1, so both sugars end the same way." Concern: "`Option[T]` appears about 3000 times in tests and 187 times in src, so the migration must be fully mechanical, and src needs a scoped rewrite, not `blink fmt`."
- **Web/Scripting:** G3 — "The compiler is the spec, and a spelling it accepts is a spelling in the corpus. A warning for one release and then a hard error with a fix-it matches the Q1 path (6-0)... Only the type annotation position rejects the long form." Concern: "About 3,000 test sites plus lib and spec must be migrated by tool, and the `Option[T]` error must say "write `T?`" so one round trip fixes it."
- **PLT:** G3 — "One warning release with a fix, then a hard error with a fix, matches the Q1 path and leaves one spelling. The error applies only to `Option[T]` in a type annotation. `Option.some(x)`, `impl` headers, and trait bounds stay legal." Concern: "Users who know `Option` from the prelude may find the hard error surprising, so the message must name the `T?` fix."
- **DevOps:** G3 — "G3 makes Option follow the same warn-then-error path as `[T]` in Q1, so the rule is uniform and the corpus converges on one form. A hard error with a fix-it gives a model a clear signal, which a lint that fmt silently fixes does not." Concern: "`Option[T]` is the real prelude type name, so users may find an error on it surprising unless the message names the fix."
- **AI/ML:** G3 — "The compiler is the spec, and a spelling it accepts without a hard stop stays in the corpus. G3 copies the Q1 path... The error applies only to `Option[T]` in a type annotation, so `Option.some(x)` and other uses of the name stay legal." Concern: "The migration covers about 3000 test sites plus lib, src and spec, so it must be fully mechanical, and src must not be rewritten with `blink fmt`."
- **Minimalism:** G3 — "G3 is the only option that ends with one spelling in the language. It follows the same path as Q1 (warning for one release, then a hard error with a fix)." Concern: "About 3000 test sites and 187 src sites need a mechanical rewrite before the hard error can land."

#### Final tally

| Q | Decision | Tally |
|---|---|---|
| Q1 | L1-a: `List[T]` only; `[T]` is a warning with a fix for one release, then an error | 6-0 |
| Q2 | O1: `T?` only in type position | 5-1 R2 after 4-2 R1 (PLT dissent: O2) |
| Q2n | N1: the type parser reads `??` as two `?` suffixes | 6-0 |
| Q2l | G3: `Option[T]` in a type annotation is a warning with a fix for one release, then an error | 6-0 R2 after 2-2-2 R1 |
| Q3 | YES: delete the "whichever the project chooses" sentence; no setting | 6-0 |
| Q4 | YES: diagnostics print only the canonical spelling | 6-0 |

User signed off on the tally. AI-First review: 5/5 pass.

### Final Spec

```blink
type Profile {
    name: Str
    tags: List[Str]
    bio: Str?
    scores: List[Int?]
}

fn lookup(cache: Map[Str, Int?], key: Str) -> Int?? {
    cache.get(key)
}
```

- `List[T]` is the only list spelling. `[T]` in a type is W1120 `ListTypeBrackets`: a warning with a machine-applicable fix for one minor release, then an error.
- `T?` is the only Option spelling in a type. `Option[T]` in a type annotation is W1121 `OptionTypeLongForm`: the same warning-then-error path.
- The type parser reads `??` as two `?` suffixes, so `Int??` is `Option[Option[Int]]`. The expression operator `a ?? b` does not change.
- `Option` stays a name for paths (`Option.Some`), impl header self types, trait bounds and prose.
- `?` is a type suffix: `List[Int]?` and `List[Int?]` are different types, and `(Int, Str)?` is an Option of a tuple.
- `T?` names the compiler-known Option by identity; a user type named `Option` does not change what `T?` means.
- `blink fmt` writes `List[T]` and `T?`.
- No setting picks a spelling. The §3 "whichever the project chooses" sentence is deleted.
- Diagnostics, fix text and the E0301 suggestions print only `List[T]` and `T?`.

### Concerns raised for the implementation

- **Mechanical migration (AI/ML, Systems, Minimalism, Web):** about 3000 test `Option[` sites and 187 src sites. AI/ML: "so it must be fully mechanical". Minimalism: "About 3000 test sites and 187 src sites need a mechanical rewrite before the hard error can land." Web: "About 3,000 test sites plus lib and spec must be migrated by tool".
- **src uses a scoped rewrite, not `blink fmt` (Systems, AI/ML):** "src needs a scoped rewrite, not `blink fmt`." AI/ML: "src must not be rewritten with `blink fmt`."
- **Error text must say "write `T?`" (Web, PLT, DevOps):** Web: "the `Option[T]` error must say "write `T?`" so one round trip fixes it." PLT: "the message must name the `T?` fix."
- **Test the `??` split next to the `a ?? b` operator (Web, DevOps, Systems, PLT):** Web: "Splitting a token in the type parser is a special case that must have tests, including `Int??` next to the `??` operator." DevOps: "`x as Int??` and `a ?? b` edge cases will produce confusing parse errors." Systems: "a bug there could change how `??` parses in expressions." PLT: "the grammar text must state exactly" the split rule.
- **The formatter today rewrites the other way (DevOps, Systems, Minimalism):** `blink fmt` writes `Int?` as `Option[Int]` today; it must change in the same commit as the spec. Minimalism: "Fix text in old diagnostics (E0301) must be updated in the same change, or it will print the removed form." PLT: "Existing diagnostic goldens must change in the same commit as the formatter and spec, or the gate breaks."
- **The printer uses the compiler-known Option by identity (Web):** "Printing `Str?` for a user type that shadows `Option` could mislead, so the printer should use the compiler-known type, as the identity rule says."
- **Schedule the error release so the warning does not linger (Systems, DevOps, Minimalism, Web, PLT):** Systems: "The warning period may become permanent if nobody schedules the hard-error release." DevOps: "If the warning stage lingers past one release, the corpus keeps both spellings."
- **Sweep every copy of the old text (PLT, Web, AI/ML):** PLT: "a grep sweep must find all copies" of the "whichever the project chooses" sentence, including llms docs and the §7 prelude row. AI/ML: "check that no other section repeats the claim."
- **Spec needs a nested-Option example (AI/ML):** "`Int??` reads like the default operator to a human or model skimming code, so the spec needs one example."
- **Messages that echo user source (AI/ML, Systems):** AI/ML: "Messages that echo user source text could still show a non-canonical spelling during the warning release." Systems: "Messages that quote user source may then differ from the spelling in that source, which can confuse a reader."
- **`?` has several meanings across type and expression position (DevOps):** "parser errors and docs must keep them clearly separate."
- **Surprise at the `Option[T]` error (PLT, DevOps):** PLT: "Users who know `Option` from the prelude may find the hard error surprising". DevOps: "`Option[T]` is the real prelude type name, so users may find an error on it surprising unless the message names the fix."
- **Bootstrap (Systems):** the `??` split and the formatter change are compiler features and need the 2-step dance: "Parser accepts both and warns, regen, migrate, regen, then error, regen."
