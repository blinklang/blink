[< All Decisions](../DECISIONS.md)

# Variant Patterns on a Scrutinee That Is Not an Enum — Design Rationale

The spec did not say what a variant pattern does when the type at its position is not an enum, in three forms. Two tickets raised them. One asked about a bare uppercase name on a builtin generic type (`List`, `Map`). The other asked about a qualified variant `Q.V` whose qualifier `Q` is not an enum, such as `Point.Zed` on a `Color` scrutinee. This record covers both. A third form, a qualified enum pattern or a struct pattern on a type-parameter scrutinee, came up in the same debate.

Facts before the vote:

- §3.5 *Pattern Forms* named a closed list of non-enum types: "(a builtin scalar, a struct, a tuple or a type parameter)". `List` and `Map` were not on it.
- §3.5 *Qualified names and the wrong type* (earlier votes) fixes the order of checks for `Q.V`: resolve `Q` (E0507), look up `V` in `Q` (E0547), then compare `Q` with the type at the position (E0300). The first failure is the only error.
- §3.4 *Enums Nominally Distinct from Int* (earlier vote) says a variant pattern on a builtin scalar is E0308 `EnumPatternNeedsEnumScrutinee`.
- Earlier votes also fix: `Other.Q(v)` on a `T` scrutinee is E0300; `check` and `build` must report the same diagnostics.
- gen1 `blink check`, measured before the vote (probes p01 to p19):
  - A bare uppercase name on `List` or `Map` (p01, p02) is already E0308. A bare name on an `Int` (p03) is E0308.
  - `Int.Zed` (p04), `List.Zed(v)` (p05), `Str.Zed` (p10) and `Map.Zed` (p19) in a pattern stop with an internal compiler error (`NodeCarriesNoType`) in `check`. In an expression, `Int.Zed` (p15) and `Point.Zed(1)` (p16) also stop with an internal compiler error.
  - `Point.Zed` on a `Color` scrutinee (p17) is already E0547 with the header "`Point` is a struct; it has no variants". So is `Point.Zed` on a `Point` scrutinee (p08).
  - A qualified enum pattern or a struct pattern on a type parameter, with or without a bound (p06, p07, p09, p13, p14), is already an error.
  - `K.B` on an `Int` (p11) is E0308 with the help "cross the boundary explicitly with K.from_int(...)".
  - `Option.Some(v)` on a `List[Int]` (p12) is E0300.
  - A qualified pattern through a type alias of an enum (p18) is legal.
- An open bug on `T.NOPE` (a qualified name on a type parameter in an expression) is a different bug. This decision does not fix it.

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in independent-proposal, debate, vote and re-vote rounds. Quoted text is each panelist's own, verbatim. `[...]` marks a cut. Local ticket IDs are replaced with a short name.

The questions on the ballot:

- Q1, the core rule: form 1 (bare uppercase on a builtin generic) is E0308; form 2 (`Q.V`, `Q` not an enum) is E0547 at step 2, span the variant name, whatever the scrutinee type; form 3 (type-parameter scrutinee) is E0300, stated in words; §3.4 construction gets the same rule for `Q.V` as a value.
- Q2, the header for a scalar qualifier (`Int.Zed`).
- Q3, the parenthetical in *A variant the enum does not declare*.
- Q4, the sentence added to step 2.
- Q5, the sentence added for a type parameter.
- Q6, the §3.4 construction text.
- Q7, `K.B` on an `Int` (p11): E0308, or E0300 by step 3.
- Q8, the step 3 text for the Q7 exception.
- Q9 (new in Phase D), whether the §3.5 scalar sentence says "bare or qualified".

#### Phase A — Independent proposals

All six seats proposed the same rule: forms 1 and 3 keep their codes (E0308, E0300), and form 2 is E0547 at step 2 for every non-enum `Q`, with no new code. They differed in wording. Excerpts:

- **Systems:**

> Step 2 fails: E0547 `NoSuchVariant`, span is the variant name `V`. The message names `Q` and says why: "`Q` is a struct; it has no variants" or "`Q` is not an enum; it has no variants". This holds whether or not `Q` is the scrutinee type. `Point.Zed` on a `Color` scrutinee is E0547, not E0308 and not E0300, because the order is E0507, E0547, E0300 (Q8a) and the first failure is the only error.
>
> [...]
>
> Why not E0308 for the non-scrutinee case: E0308 would make the code depend on whether `Q` equals the scrutinee type. The struct case would then read E0547 on a `Point` scrutinee (p08) and E0308 on a `Color` scrutinee, which is the incoherence ticket 2 asks about.
>
> [...]
>
> Add after the "different struct type" sentence: "A type parameter is a rigid type inside the generic body. A qualified enum or struct pattern on a value of type `T` is E0300, with or without a bound on `T`. A match does not refine `T`."

- **Web/Scripting:**

> The 90% error is a typo or a wrong-type guess. A JS or Python dev reads "`Point` is a struct; it has no variants" and fixes it in seconds. The rule must give the same answer for `Point.Zed` on a `Point` scrutinee and on a `Color` scrutinee. Today it does (p08, p17).
>
> [...]
>
> The bare form stays E0308, because the position is at fault there. In the qualified form the qualifier is at fault.
>
> [...]
>
> "A qualified pattern on a scrutinee whose type is a type parameter is E0300 at the pattern: the type parameter is not `Q`. A bound does not change this. The compiler reports it where the generic function is defined."

- **PLT:**

> Principle: each check in the order E0507, E0547, E0300 must depend only on the inputs named in its step. Step 2 ("look up `V` in `Q`") does not read the scrutinee type. So a `Q` that is not an enum has no variants, and the result is the same on every scrutinee.
>
> [...]
>
> Add to step 2: "If `Q` is a type that is not an enum, `Q` declares no variant, and the error is E0547. The message says what `Q` is. The scrutinee type does not change this."
>
> [...]
>
> Add to step 3: "A type parameter is equal only to itself. A qualified enum pattern or a struct pattern on a scrutinee of a type parameter is E0300, with or without bounds. The compiler reports it where the generic function is defined."

- **DevOps/Tooling:**

> Rule: the code follows the first thing that is wrong. The diagnostic surface stays small and predictable. A user who reads an error must know which token to edit.
>
> [...]
>
> Why E0547 and not E0308: the error is in `Q.V`, not in the position. The bare-name rule gives E0308 because the position is the only fact there. A qualifier gives a second fact. [...] A type with no variants declares none. One rule, no new branch.
>
> [...]
>
> Add to step 3: "A type parameter is a different type from every enum and struct, including when it has a bound. A qualified pattern on a scrutinee of a type parameter is E0300. The compiler reports it where the generic function is defined."

- **AI/ML:**

> Principle: an AI learns "first failing step wins" once. Each extra "it depends on the scrutinee" branch is a decision point and a likely wrong guess.
>
> [...]
>
> Bare vs qualified differ by design: bare names "the type at the position", so a non-enum there is a position error (E0308); qualified names its own type, so a non-enum there lacks the variant (E0547).
>
> [...]
>
> Add one sentence to *Qualified names and the wrong type*: "A type parameter is a different type from every enum and struct, so `K.A(v)` or `Q { y }` on a `T` scrutinee is E0300, reported where the generic function is defined."

- **Minimalism:**

> Position: no new code, no new check step, no new syntax. The three forms follow from rules the panel already voted. The spec only needs words. The compiler needs to stop the ICEs.
>
> [...]
>
> Add to step 2: "A type that is not an enum declares no variants, so `Q.V` with such a `Q` (a struct, a builtin scalar, `List`, `Map`) is E0547 for every `V`, whatever the type at the pattern position is."
>
> [...]
>
> Seat note: I vote yes only for these spec words and no new feature.

#### Phase B — Debate

Each seat read the other Phase A files and replied on six variations. Reading note: in Phase B, Minimalism read the Web and PLT files in part. Highlights, as excerpts:

- Five variations needed no vote. V1 was the header for a scalar qualifier. V2 was the parenthetical. V3 was the step 2 sentence. V4 was the type-parameter sentence. V5 was the §3.4 sentence. The seats moved toward one text for each, and the Phase C ballot lists the texts that remained.
- **Systems, on the parenthetical (V2):**

> I prefer the plt-style list plus "any type that is not an enum" as the rule. The list alone goes stale the next time a builtin type is added.

- **PLT, on the step 2 sentence (V3):**

> Any text that says three things is acceptable: a non-enum `Q` declares no variants; the code is E0547; the scrutinee type does not change it. [...] I hold the third clause because it is the soundness point: step 2 must not read the position type.

- **Minimalism, on the type-parameter sentence (V4):**

> I drop min-3 and take plt-1: it carries "reported where the generic function is defined", which min-3 lost and which the bare-name rule already says.

- **Web/Scripting, on `K.B` on an `Int` (V6):**

> This is the real open point, and I ask for a ballot item. My Phase A text was confused here, and I correct it.

- V6 was the one real conflict. Step 3 said a different type is E0300, and §3.5 said a variant pattern on a builtin scalar is E0308. All six seats held E0308 for `K.B` on an `Int`, kept as a stated exception. Systems added a limit that all six kept:

> If the panel extends A to other non-enum positions (struct, `List`, tuple, type parameter with a qualified enum pattern), I oppose it. Q4 and Q3 fix those as E0300. V6 is only about scalars.

- **DevOps:**

> The exception is narrow: it applies only when the position type is a scalar and `Q` is an enum. p12 (`Option.Some(v)` on `List[Int]`) stays E0300, because no such help exists there.

- Two points all six B1 replies kept (V4): "with or without bounds" and "where the generic function is defined" stay in whichever text wins. Four seats (PLT, DevOps, AI/ML, Minimalism) also said p12 stays E0300 under either option of V6.

#### Phase C — Silent ballot

Each seat voted alone on Q1 to Q8, with a vote, a reason and a concern for each. Reading note: in Phase C, Web skimmed five of the Phase A files. Result:

| Q | Subject | Result |
|---|---------|--------|
| Q1 | The core rule | A 6-0 |
| Q2 | Header for a scalar qualifier | A 6-0 |
| Q3 | The parenthetical | B 3 (web, plt, aiml), C 3 (sys, devops, min) |
| Q4 | The step 2 sentence | A 4 (sys, web, devops, aiml), B 1 (plt), C 1 (min) |
| Q5 | The type-parameter sentence | A 1 (sys), C 4 (plt, devops, min, aiml), D 1 (web) |
| Q6 | The §3.4 construction text | C 5 (sys, web, plt, devops, aiml), A 1 (min) |
| Q7 | `K.B` on an `Int` | A 6-0 |
| Q8 | The step 3 text for Q7 | A 1 (sys), B 1 (web), C 1 (plt), D 2 (devops, aiml), E 1 (min) |

**Q1. The core rule.** Vote A: form 1 is E0308; form 2 is E0547 at step 2, span the variant name, whatever the type at the position; form 3 is E0300, stated in words; §3.4 gets the same rule for `Q.V` as a value. Verbatim, per seat:

- **Systems:**

> **Q1. Vote: A.**
> Reasoning: Step 2 is a symbol-table miss at resolve time. It reads no scrutinee type, so it costs nothing, cannot depend on inference order, and gives check/build parity. A type-parameter pattern must typecheck once in the generic body, so mono needs no type test.
> Concern: E0547 on `Int.Zed` reads odd to a user who expected a type error; the header text must carry the meaning.

- **Web/Scripting:**

> **Q1. Vote: A.**
> Reasoning: One rule per mistake is what a JS or Python dev can hold in their head: the qualifier names a thing with no variants, so it is E0547, wherever it sits. It also settles ticket 2 and kills the ICEs in p04, p05, p10 and p19 with no new code. The type-parameter case stated in words stops a silent "prints 0" run.
> Concern: E0547 for `Int.Zed` reads like a name error to someone who expects a type error, so the header text must carry the load.

- **PLT:**

> **Q1. Vote: A.**
> Reasoning: Step 2 (lookup of V in Q) takes only Q and V as inputs. A non-enum Q declares no variants, so the result cannot depend on the scrutinee type. Form 1 is a position fault (E0308), form 3 is a type equality fault (E0300). Each fault keeps one code.
> Concern: E0547 for `Int.Zed` reads as a "variant" error to a user who wrote a type; only the header text prevents that.

- **DevOps/Tooling:**

> **Q1. Vote: A.**
> Reasoning: One code per cause. The bare-name form is a position fault (E0308). A `Q.V` form with a non-enum `Q` is a qualifier fault (E0547 at the variant name, step 2). A type parameter with a qualified pattern is E0300 stated in words. The user edits the same token the span marks, and `check` and `build` agree.
> Concern: E0547 for `Int.Zed` reads oddly to a user who made a type error, so the header must name what `Q` is in every message.

- **AI/ML:**

> **Q1. Vote:** A
> **Reasoning:** One rule per step, and the scrutinee never picks the code, is the shape a model learns once. Form 1 is E0308, Form 2 is E0547 at step 2, Form 3 is E0300 in words. Each form has one code and one span, so there are no branches to guess.
> **Concern:** E0547 on `Int.Zed` reads odd to a person who expected a type error, so the header text must carry the meaning.

- **Minimalism:**

> **Q1. Vote: A.**
> Reasoning: Every seat states the rule, and it adds no code and no step. Each form already follows from a vote the panel took, and the rule removes four ICEs (p04, p05, p10, p19).
> Concern: E0547 for `Int.Zed` reads as a type error to a user who never thought of variants, so the header text must carry the meaning.

**Q2. Header for a scalar qualifier.** Vote A: "`Int` is not an enum; it has no variants". Option B was "`Int` is a scalar; it has no variants". Verbatim, per seat:

- **Systems:**

> **Q2. Vote: A.**
> Reasoning: "is not an enum" is one template for scalar and builtin generic. The compiler needs no kind switch beyond struct, and a new builtin type needs no new message.
> Concern: A user may ask whether `Str` or `Bool` count as scalars; the A text avoids that, B invites it.

- **Web/Scripting:**

> **Q2. Vote: A.**
> Reasoning: One template ("is not an enum; it has no variants") for scalar and builtin generic is easier to learn than two. The struct header keeps its own text.
> Concern: "scalar" would have helped a beginner more than "enum" does, but two templates cost more.

- **PLT:**

> **Q2. Vote: A.**
> Reasoning: "is not an enum" is true of every non-struct Q with no variants. It needs no kind switch and no decision about which builtin is a "scalar". The struct header keeps its own text.
> Concern: "scalar" and "not an enum" can drift into two templates if a later edit adds a kind word.

- **DevOps/Tooling:**

> **Q2. Vote: A.**
> Reasoning: One template ("is not an enum; it has no variants") covers scalar and builtin generic. The message needs no kind switch, and ERROR_CATALOG needs one example. "Is a scalar" forces a decision for `Str`, `Bool` and `Char`.
> Concern: A scalar user may read "not an enum" as a hint to use an enum, so the help must not suggest a variant.

- **AI/ML:**

> **Q2. Vote:** A
> **Reasoning:** I leaned to B for match with p03, but devops is right that "scalar" forces a call on `Str`, `Bool` and `Char`. One template for scalar and builtin generic means fewer kinds to learn and to extend.
> **Concern:** "is not an enum" teaches less about why than "is a scalar", but the fix is the same.

- **Minimalism:**

> **Q2. Vote: A.**
> Reasoning: One template for scalar and builtin generic means one fewer message and no list of kinds to extend. "Is a scalar" forces a ruling on each new builtin (`Str`, `Bool`, `Char`).
> Concern: "not an enum" says what the type is not, not what it is; the wording is a little less informative.

**Q3. The parenthetical in *A variant the enum does not declare*.** No majority: 3-3. Option B (aiml-1): "any type that is not an enum, such as a builtin scalar, a builtin generic like `List` or `Map`, a struct, a tuple or a type parameter". Option C (min B1): "When the type at the pattern position is not an enum (for example a builtin scalar, a builtin generic such as `List` or `Map`, a struct, a tuple or a type parameter), ...". Option A was the plain list with `List` and `Map` added. Verbatim, per seat:

- **Systems (C):**

> **Q3. Vote: C.**
> Reasoning: The rule is "not an enum"; the list is examples. A closed list went stale once (it missed `List`). C states the rule first and marks the list as examples.
> Concern: "for example" lets a reader think the list is partial in a way that matters; the rule still decides.

- **Web/Scripting (B):**

> **Q3. Vote: B.**
> Reasoning: Opening with "any type that is not an enum" gives the rule, and the list is only examples. A closed list invites a new ticket for the next type nobody named.
> Concern: A reader may skip the examples and wonder if a tuple counts, but the rule text covers it.

- **PLT (B):**

> **Q3. Vote: B.**
> Reasoning: The rule is "not an enum"; the list is examples. A closed list leaves the next builtin generic as a new gap, which is how this ticket arose. B states the rule first and the examples after.
> Concern: "such as" lets a reader treat the list as non-normative, and a rare type (a trait object, a function type) is then decided by inference from the examples.

- **DevOps/Tooling (C):**

> **Q3. Vote: C.**
> Reasoning: The rule is "not an enum"; the list is examples. A closed list went stale once (it missed `List`), and an open rule cannot go stale. C keeps the sentence frame of the existing text and says "for example", so no reader takes the list as complete.
> Concern: "For example" lets a reader doubt whether a rare type (a closure, a function type) counts, but the rule word "not an enum" answers it.

- **AI/ML (B):**

> **Q3. Vote:** B
> **Reasoning:** The rule is "not an enum"; the list only gives examples. A closed list is what let `List` go missing, and a model reads the rule, not the list. Option B states the rule first.
> **Concern:** A model may treat "such as" as a closed list unless the lead clause is read first.

- **Minimalism (C):**

> **Q3. Vote: C.**
> Reasoning: The rule is "not an enum"; the list gives examples. A closed list went stale once already (this ticket exists because `List` was missing).
> Concern: "for example" opens a list that a later edit may grow, and the spec text will drift from the rule.

**Q4. The sentence added to step 2.** A 4-1-1. Option A (plt-1): "If `Q` is a type that is not an enum, `Q` declares no variant, and the error is E0547. The message says what `Q` is. The scrutinee type does not change this." Option B (min-2): "A type that is not an enum declares no variants, so `Q.V` with such a `Q` (a struct, a builtin scalar, `List`, `Map`) is E0547 for every `V`, whatever the type at the pattern position is." Option C (min B1): "A `Q` that is not an enum declares no variants, so every `Q.V` fails here, whatever the type at the pattern position is." Option D (sys-1): "A `Q` that is not an enum declares no variants, so every `Q.V` fails here." Verbatim, per seat:

- **Systems (A):**

> **Q4. Vote: A.**
> Reasoning: It states code, what the message says, and that the scrutinee type does not change the result. That clause stops step 2 from reading the position type, which keeps the check a plain lookup. D omits it, so I vote against my own sys-1 text.
> Concern: B lists "(a struct, a builtin scalar, `List`, `Map`)", and that list can go stale.

- **Web/Scripting (A):**

> **Q4. Vote: A.**
> Reasoning: It says what `Q` is, names the code, and states "the scrutinee type does not change this", which is the sentence that settles ticket 2. It is plain, active, and short.
> Concern: "The message says what `Q` is" puts a message promise in the spec; the devs who read it will expect the exact header text.

- **PLT (B):**

> **Q4. Vote: B.**
> Reasoning: The sentence must carry three things: a non-enum Q declares no variants, the code is E0547, and the scrutinee type does not change it. The third is the soundness point: step 2 must not read the position type. B (min-2) has all three; C and D drop the code or the examples, and D drops the scope clause.
> Concern: The parenthetical list in B can go stale, though the rule before it ("a type that is not an enum") stays correct.

- **DevOps/Tooling (A):**

> **Q4. Vote: A.**
> Reasoning: plt-1 says three things: a non-enum `Q` declares no variant, the code is E0547, and the scrutinee type does not change it. It also says the message says what `Q` is, which is the diagnostic contract I want in the spec. It has no list that can go stale.
> Concern: D (no scrutinee clause) would leave ticket 2 implicit, and a later implementer could read the scrutinee in step 2.

- **AI/ML (A):**

> **Q4. Vote:** A
> **Reasoning:** It says all three things: a non-enum `Q` declares no variant, the code is E0547, and the scrutinee type does not change it. The last clause settles ticket 2 in words. "The message says what `Q` is" tells the implementer the header must differ by kind.
> **Concern:** Option A has no examples in the text, so a model may not see that `Q` can be a struct on a Color scrutinee.

- **Minimalism (C):**

> **Q4. Vote: C.**
> Reasoning: It is the shortest text that keeps the scrutinee clause. That clause settles ticket 2 and bars step 2 from reading the position type. D omits it, and A and B add words with no new content.
> Concern: "fails here" does not name E0547, so a reader must take the code from the sentence above it.

**Q5. The sentence added for a type parameter.** C 4 of 6 in Phase C. Option A (sys-1): "A type parameter is a rigid type inside the generic body. A qualified enum or struct pattern on a value of type `T` is E0300, with or without a bound on `T`. A match does not refine `T`." Option B (web-1): "A qualified pattern on a scrutinee whose type is a type parameter is E0300 at the pattern: the type parameter is not `Q`. A bound does not change this. The compiler reports it where the generic function is defined." Option C (plt-1): "A type parameter is equal only to itself. A qualified enum pattern or a struct pattern on a scrutinee of a type parameter is E0300, with or without bounds. The compiler reports it where the generic function is defined." Option D (devops-1): "A type parameter is a different type from every enum and struct, including when it has a bound. A qualified pattern on a scrutinee of a type parameter is E0300. The compiler reports it where the generic function is defined." Option E (aiml-1): "A type parameter is a different type from every enum and struct, so `K.A(v)` or `Q { y }` on a `T` scrutinee is E0300, reported where the generic function is defined." Verbatim, per seat:

- **Systems (A):**

> **Q5. Vote: A.**
> Reasoning: "A type parameter is rigid" and "a match does not refine `T`" give the reason: the body checks once and monomorphizes the same for every `T`. The phrases "with or without a bound" and "where the generic function is defined" must stay in the final text (V4 point); I want "reported where the generic function is defined" appended to A.
> Concern: If the winning text drops "reported where the generic function is defined", a reader may infer a call-site check, which would force per-instantiation tests in mono.

- **Web/Scripting (D):**

> **Q5. Vote: D.**
> Reasoning: "A different type from every enum and struct, including when it has a bound" answers the question a dev asks first: "what if T has a trait bound?". It keeps "where the generic function is defined", so the error shows once at the definition, not at each call.
> Concern: Devs from TypeScript or Kotlin will try `is`-style narrowing and hit this, so the help text should point to taking the enum type or a trait bound.

- **PLT (C):**

> **Q5. Vote: C.**
> Reasoning: "A type parameter is equal only to itself" is the typing fact. It gives E0300 for a qualified enum or a struct pattern by step 3, with no rule special to patterns. "With or without bounds" and "where the generic function is defined" make the check independent of any call site, so mono needs no type test and parametricity holds.
> Concern: A reader may take "equal only to itself" to cover a bound's trait methods too, so a later spec change that adds refinement through a bound must reopen this sentence.

- **DevOps/Tooling (C):**

> **Q5. Vote: C.**
> Reasoning: C keeps "with or without bounds" and "where the generic function is defined". The second phrase is the one place the diagnostic site differs from a call, and the LSP must put the squiggle in the generic body. "Equal only to itself" is short and exact.
> Concern: Without "A match does not refine `T`" (A), a user from Scala or Kotlin may expect narrowing, so the E0300 help should say a generic body cannot test `T`.

- **AI/ML (C):**

> **Q5. Vote:** C
> **Reasoning:** My B1 said "with or without bounds" and "where the generic function is defined" must stay. E lacks the bounds clause, and plt-1 (C) has both. "Equal only to itself" is short and gives the model the rule to apply.
> **Concern:** C names no example pattern, so a model may not link it to `K.A(v)` on `T`.

- **Minimalism (C):**

> **Q5. Vote: C.**
> Reasoning: It states the rule, "with or without bounds", and "where the generic function is defined". All six B1 files call those two phrases load-bearing. A, B and D add reasons that the rule needs no more than C does. E drops "with or without bounds".
> Concern: "equal only to itself" is a type-theory phrase, and a user who has not met it may still try a bound as a way out.

**Q6. The §3.4 construction text.** C 5-1. Option A (sys-1): add "a `K` that is not an enum has no variants" to the "order of checks is also the same" sentence. Option B (web-1): "A qualifier that is not an enum declares no variant, so it is E0547." Option C (plt-1): "A `Q` that is not an enum is E0547 in an expression too (`Int.Zed`, `Point.Zed(1)`)." Option D (aiml-1): "`Q.V` where `Q` is not an enum is E0547 at the variant name, as for patterns." Option E (min-2): "`Q.V` as an expression, where `Q` is not an enum, is E0547 by the same rule." Verbatim, per seat. In the Web reply, the bracket marks a replaced ticket ID:

- **Systems (C):**

> **Q6. Vote: C.**
> Reasoning: It names `Int.Zed` and `Point.Zed(1)` as expression examples, so the §3.4 text matches the pattern text and the p15/p16 ICEs have a stated rule. A one-clause form (A) is shorter but gives no example.
> Concern: A separate sentence in §3.4 can drift from the §3.5 step 2 text over time.

- **Web/Scripting (C):**

> **Q6. Vote: C.**
> Reasoning: The two examples (`Int.Zed`, `Point.Zed(1)`) make the rule concrete in the section a dev reads when they write a value, and they match the probes p15 and p16.
> Concern: The [open bug on `T.NOPE`] is a different bug and the text must not imply it is fixed.

- **PLT (C):**

> **Q6. Vote: C.**
> Reasoning: The examples `Int.Zed` and `Point.Zed(1)` fix the expression case in the text, so §3.4 and §3.5 cannot drift. The sentence reuses the pattern rule and adds no new step.
> Concern: A separate sentence in §3.4 is one more place to edit if step 2 changes.

- **DevOps/Tooling (C):**

> **Q6. Vote: C.**
> Reasoning: The two examples (`Int.Zed`, `Point.Zed(1)`) give a model and a reader the rule by pattern. One sentence in §3.4 stops the two sections from drifting. Option A hides the rule inside an existing sentence.
> Concern: The sentence in §3.4 is a second place to edit if the pattern rule changes; the fix is a cross-reference check in the spec lint.

- **AI/ML (C):**

> **Q6. Vote:** C
> **Reasoning:** A model reads examples, not the rule. C names `Int.Zed` and `Point.Zed(1)` as values, which closes the p15 and p16 shapes. A sentence is better than a clause that can drift from the §3.5 text.
> **Concern:** C says "in an expression too" without the span, so the span rule is only implied by "as for patterns".

- **Minimalism (A):**

> **Q6. Vote: A.**
> Reasoning: One clause added to the existing "order of checks is also the same" sentence. The two sections cannot drift because there is no second sentence to drift.
> Concern: A reader skims the clause, and an LLM learns from examples; no `Int.Zed` example appears in §3.4.

**Q7. An enum qualifier on a builtin scalar scrutinee (`K.B` on `Int`, p11).** Vote A 6-0: E0308 `EnumPatternNeedsEnumScrutinee` for a variant pattern, bare or qualified, on a builtin scalar, as gen1 does today; the spec states the exception to step 3 in words. Option B was E0300 by step 3 with no exception. Verbatim, per seat:

- **Systems:**

> **Q7. Vote: A.**
> Reasoning: The 6-0 enum/Int vote says a variant pattern on a builtin scalar is E0308, and it does not say "bare only". gen1 does this today, so there is no codegen change. The `K.from_int(...)` help has no E0300 path.
> Concern: If the panel extends the exception beyond scalars (struct, `List`, tuple, type parameter), it overturns the decided E0300 for other-type patterns; I oppose that.

- **Web/Scripting:**

> **Q7. Vote: A.**
> Reasoning: The help on p11 shows `K.from_int(...)`, the fix a dev who mixed up an int and an enum needs. E0300 would lose it. All six B1 replies agree, and §3.5 already says a variant pattern on a scalar is E0308.
> Concern: It is one more exception to the step 1-3 order, so a future change to step 3 can break it without notice; a test should pin p11.

- **PLT:**

> **Q7. Vote: A.**
> Reasoning: The decided rule says a variant pattern on a builtin scalar is E0308, with no "bare" limit. Reopening it is out of scope. The exception is narrow: only a scalar position, and the `K.from_int(...)` help has no E0300 path.
> Concern: Step 3 now has one position-dependent exception, and a later builtin scalar-like type (a newtype over Int) may need a ruling on whether it falls in it.

- **DevOps/Tooling:**

> **Q7. Vote: A.**
> Reasoning: Six seats hold that the decided scalar rule covers the qualified form. gen1 gives E0308 with the help "cross the boundary explicitly with K.from_int(...)", and no E0300 path can give that help. It is the migration path for a user who matches an `Int` against an integer-backed enum.
> Concern: A is an exception to step 3, and a reader may extend it to struct or `List` positions; p12 must stay E0300 and a test must pin it.

- **AI/ML:**

> **Q7. Vote:** A
> **Reasoning:** The decided rule says "a variant pattern on a builtin scalar", with no "bare" qualifier. A keeps the `K.from_int(...)` help, which is what a model needs when it matches an `Int` on an enum. B would overturn a decided rule and lose that help.
> **Concern:** A is an exception to step 3, so a model that learns "different type is E0300" will guess wrong for scalars unless the text is clear.

- **Minimalism:**

> **Q7. Vote: A.**
> Reasoning: All six B1 replies hold A, and the enum/Int vote already says "a variant pattern on a builtin scalar", with no "bare". B would reopen a 6-0 vote and lose the `K.from_int(...)` help. The cost is one stated exception.
> Concern: The exception is a special case in step 3, and the next scalar-like type (a newtype over `Int`) will ask whether it joins it.

**Q8. The text for Q7 A** (applies only if Q7 is A). No option had a majority in Phase C. Option A (sys B1): say "bare or qualified" in the §3.5 scalar sentence. Option B (web B1, in step 3): "If the type at the position is a builtin scalar, the error is E0308, not E0300." Option C (plt B1, in step 3): "A qualified variant pattern on a builtin scalar is E0308, not E0300." Option D (devops B1, in step 3): "If the type at the position is a builtin scalar, a variant pattern of an enum is E0308, as for a bare name (§3.4 *Enums Nominally Distinct from Int*)." Option E (min B1, in step 3): "When the type at the pattern position is a builtin scalar, a qualified variant of a real enum is E0308 (§3.4 *Enums Nominally Distinct from Int*), not E0300." Verbatim, per seat:

- **Systems (A):**

> **Q8. Vote: A.**
> Reasoning: The scalar sentence in §3.5 is where the E0308 rule already lives. Adding "bare or qualified" there is a minimal change and keeps step 3 unchanged. A reader of step 3 alone would still see E0300, so I ask that step 3 add a pointer to the scalar sentence.
> Concern: Step 3 read alone still says "a different type is E0300", so the exception sits in a second place and a reader can miss it.

- **Web/Scripting (B):**

> **Q8. Vote: B.**
> Reasoning: It sits in step 3, where the dev reads the E0300 rule, so the exception is next to the rule it changes. It is short and covers bare and qualified forms.
> Concern: It does not name a "variant of a real enum", so a reader may ask what happens for `Int.Zed`; step 2 answers that (E0547) before step 3 runs.

- **PLT (C):**

> **Q8. Vote: C.**
> Reasoning: Step 3 is where a reader meets "different type is E0300", so the exception belongs there. "A qualified variant pattern on a builtin scalar is E0308, not E0300" is the shortest text that names the form, both codes, and nothing else. It does not widen the exception to struct, List, tuple or type parameter, which Q4 and Q5 keep at E0300.
> Concern: C omits the cross-reference to §3.4 *Enums Nominally Distinct from Int*, so a reader cannot find the reason for the exception from step 3.

- **DevOps/Tooling (D):**

> **Q8. Vote: D.**
> Reasoning: D says "a variant pattern of an enum", ties the rule to the nominal-distinctness section, and says "as for a bare name", so the two forms read as one rule. It sits in step 3, where a reader looks when they see E0300 versus E0308. It limits the exception to a scalar position.
> Concern: Any step 3 wording needs a matching change to the §3.5 scalar sentence, or the two places will say different things.

- **AI/ML (D):**

> **Q8. Vote:** D
> **Reasoning:** The exception must sit in step 3, where the model looks for the E0300 rule. D covers bare and qualified variant patterns and links the decided section. It says "a builtin scalar" and "an enum", so it does not extend to struct, `List` or type parameter (p12 stays E0300).
> **Concern:** The words "as for a bare name" may be read as a rule for all non-enum positions, which Q4 and Q5 forbid.

- **Minimalism (E):**

> **Q8. Vote: E.**
> Reasoning: Step 3 is where a reader meets the E0300 rule, so the exception must stand there, not in §3.5 only. E names the case (a qualified variant of a real enum, a builtin scalar) and the vote it comes from, in one clause.
> Concern: The same exception now appears in step 3 and §3.5, and the two can drift.

#### Phase D — Focused round and re-vote

Phase D covered Q3, Q4, Q5 and Q8, the four questions without a clear result. Each seat read the Phase C files and replied with its position (D1). Then each seat voted alone (D2). Reading notes: in D1, Systems and Web read the digest's verbatim quotes of the Phase C files, not the raw files. In D2, PLT did not read the Phase A files, which the D2 ballot did not require.

D1 positions, excerpted:

- **Q3.** Systems, DevOps and PLT moved or held C; Web, AI/ML and Minimalism held B. Systems: "The two differ only in frame ("such as" versus "for example"), and both lead with the rule "not an enum". Either settles it for me; I do not mind which wins." Web: "The 3-3 split is about word order, so either text is fine to me."
- **Q4.** All six held A. PLT: "I oppose C and D: C does not name E0547, and D drops the scope clause that bars step 2 from reading the position type."
- **Q5.** Systems and Web moved to C. AI/ML asked for an amended C (C′) that adds "A match does not refine the type parameter." Systems, on its move: "I lose "a match does not refine `T`". That is the reason, and the rule stands without it, so I do not ask for an amendment."
- **Q8.** Systems, DevOps and AI/ML held D. PLT asked for an amended C (C′): "A qualified variant pattern of an enum on a builtin scalar is E0308 (§3.4 *Enums Nominally Distinct from Int*), not E0300." Web asked for an amended D (D′): "If the type at the position is a builtin scalar, a variant pattern of an enum, bare or qualified, is E0308 (§3.4 *Enums Nominally Distinct from Int*), not E0300." Minimalism held C. Systems, DevOps, PLT, Web and AI/ML each asked that the §3.5 scalar sentence say "bare or qualified", under any option. This became Q9.

D2 ballot, as sent:

- **Q3.** B: aiml-1 (web, aiml, min). C: min B1 (sys, plt, devops).
- **Q4.** A: plt-1 (all six). B: min-2 (no seat).
- **Q5.** A: sys-1 (no seat). C: plt-1 (sys, web, plt, devops, min). C′: aiml D1 (aiml). D: devops-1 (no seat).
- **Q8.** C: plt B1 (min). C′: plt D1 (plt). D: devops B1 (sys, devops, aiml). D′: web D1 (web). E: min B1 (no seat).
- **Q9, new.** A: add "bare or qualified" to the §3.5 scalar sentence "A variant pattern on a builtin scalar is `EnumPatternNeedsEnumScrutinee` (E0308, §3.4 *Enums Nominally Distinct from Int*)." B: leave it as it is.

D2 result:

| Q | Subject | Result |
|---|---------|--------|
| Q3 | The parenthetical | 3-3: B (web, aiml, min), C (sys, plt, devops) |
| Q4 | The step 2 sentence | A 6-0 |
| Q5 | The type-parameter sentence | C 5-1 (aiml C′; Phase C was 4-1-1) |
| Q8 | The step 3 text for Q7 | No majority: D 3 (sys, devops, aiml), D′ 1 (web), C′ 1 (plt), C 1 (min) |
| Q9 | The §3.5 scalar sentence | A 6-0 |

D2 votes, verbatim, per seat:

- **Systems:**

> **Q3. Vote: C.**
> Reasoning: Both options lead with the rule "not an enum" and give the list as examples, so the compiler and the reader get the same fact. C drops into the existing sentence frame ("When the type at the pattern position is not an enum ..."), and B is a fragment that must replace the parenthetical. A rule checked as "is this tid an enum?" costs nothing and has no closed list to go stale.
> Concern: "for example" may make a reader doubt a rare type (a closure, a function type) counts, but the rule word "not an enum" decides it.
>
> **Q4. Vote: A.**
> Reasoning: Step 2 is a symbol-table lookup of V in Q. A says a non-enum Q declares no variant, gives the code, and says the scrutinee type does not change it, so step 2 never reads the position type and check and build stay the same. It has no list that can go stale.
> Concern: A has no example in the text, so an implementer may not see that Q can be a struct at an enum position (ticket 2).
>
> **Q5. Vote: C.**
> Reasoning: C has the two phrases that fix the cost model: "with or without bounds" and "where the generic function is defined". The body typechecks once, so mono needs no type test per instantiation. "Equal only to itself" is the same fact as my "rigid" wording.
> Concern: With no "a match does not refine T", a user from Kotlin or Scala may expect narrowing, so the E0300 help must say a generic body cannot test T.
>
> **Q8. Vote: D.**
> Reasoning: The exception sits in step 3, where a reader meets the E0300 rule, and it links §3.4 *Enums Nominally Distinct from Int*. It names a builtin scalar position and an enum, so struct, List, tuple and type parameter stay E0300 and gen1 needs no codegen change. D gives the same result for bare and qualified forms.
> Concern: "As for a bare name" may be read as a rule for every non-enum position, which Q4 and Q5 forbid, so a test must pin p12 at E0300.
>
> **Q9. Vote: A.**
> Reasoning: Step 3 will say "bare or qualified" in effect, so the §3.5 scalar sentence must say it too. Two places with different words will drift, and a reader of one will get the wrong code for `K.B` on `Int`.
> Concern: The exception is now stated in two places, and a later edit to one can leave the other stale.

- **Web/Scripting:**

> **Q3. Vote: B.**
> Reasoning: B opens with "any type that is not an enum", so a dev reads the rule first and the examples second. C and B give the same rule, so I take the shorter one. I accept C if it wins.
> Concern: A dev may skip the examples and ask if a tuple or a function type counts; the rule "not an enum" answers it.
>
> **Q4. Vote: A.**
> Reasoning: It states the code (E0547), what `Q` is in the message, and that the scrutinee type does not change the result. That last clause settles ticket 2 in plain words. No list can go stale.
> Concern: "The message says what `Q` is" puts a message promise in the spec, and devs will expect the exact header text.
>
> **Q5. Vote: C.**
> Reasoning: Five seats hold C. It has "with or without bounds", which answers the first question a dev asks, and "where the generic function is defined", which puts the error in one place. The Kotlin or TypeScript narrowing question is a job for the help text.
> Concern: "Equal only to itself" is a type-theory phrase, so the E0300 help must say in plain words that a generic body cannot test `T`.
>
> **Q8. Vote: D'.**
> Reasoning: It sits in step 3, where a dev reads the E0300 rule. It says "bare or qualified" and links §3.4, so a dev who meets E0308 can find the reason and the `K.from_int(...)` help. It drops "as for a bare name", so no reader takes it as a rule for every non-enum position, and p12 stays E0300.
> Concern: Step 3 and the §3.5 scalar sentence now state the same exception, and they can drift; Q9 A reduces that risk.
>
> **Q9. Vote: A.**
> Reasoning: The §3.5 scalar sentence must say "bare or qualified", or it contradicts step 3 and a dev who reads only §3.5 gets the wrong rule. Every option for Q8 needs it.
> Concern: The two places still repeat one rule, so a later edit to one must change the other.

- **PLT:**

> **Q3. Vote: C.**
> Reasoning: Both options state the rule "not an enum" first; the list only gives examples, so neither changes the typing content. C keeps the frame of the existing sentence ("When the type at the pattern position is not an enum ..."), so the clause composes with what follows it, while B is a fragment that must replace a parenthetical. "For example" marks the list as non-exhaustive more plainly than "such as".
> Concern: A reader may take the list as normative for rare types (function types, trait objects); the rule word "not an enum" must decide those.
>
> **Q4. Vote: A.**
> Reasoning: Step 2 is a lookup of `V` in `Q`; its inputs are `Q` and `V` only. A states that a non-enum `Q` declares no variant, that the code is E0547, and that the scrutinee type does not change it. That last clause keeps step 2 independent of the position type, which is the soundness point, and A has no list that can go stale.
> Concern: A gives no example, so a reader may not see that `Q` can be a struct at an enum position (ticket 2).
>
> **Q5. Vote: C.**
> Reasoning: "A type parameter is equal only to itself" is the typing fact; E0300 for a qualified enum or struct pattern then follows from step 3 with no rule special to patterns. "With or without bounds" and "where the generic function is defined" make the check independent of any instantiation, so mono needs no type test. C′ adds "a match does not refine the type parameter", which is true but is a consequence, not a premise; I accept C′ as second.
> Concern: A later spec change that adds refinement through a bound must reopen this sentence.
>
> **Q8. Vote: C′.**
> Reasoning: The exception to step 3 is a typing rule about one position (builtin scalar) and one pattern form (a variant of an enum). The text stays in step 3, where E0300 is stated, and gives the cross-reference to the decided rule. It does not use "as for a bare name", which a reader may extend to every non-enum position, contrary to Q4 and Q5 (p12 stays E0300). I accept D′ as second.
> Concern: Whichever text wins repeats the exception in step 3 and §3.5, so the two places can drift; Q9 A reduces that risk.
>
> **Q9. Vote: A.**
> Reasoning: Q7 decided E0308 for a variant pattern, bare or qualified, on a builtin scalar. The §3.5 scalar sentence must state the same scope as step 3, or the spec contradicts itself. Adding "bare or qualified" removes the ambiguity and costs three words.
> Concern: The same exception now lives in two sentences; a spec lint cross-check would keep them aligned.

- **DevOps/Tooling:**

> **Q3. Vote: C.**
> Reasoning: Both options lead with the rule "not an enum" and give examples, so the choice is frame only. C drops into the existing sentence ("When the type at the pattern position is not an enum (for example ...), ..."), so the spec reads as one sentence and an edit touches one place. "For example" marks the list as open, so the next builtin type needs no new ticket.
> Concern: B, if it wins, is a fragment that replaces the parenthetical and reads awkwardly after "When the type ... is"; the editor must fix the frame.
>
> **Q4. Vote: A.**
> Reasoning: It states that a non-enum `Q` declares no variant, that the code is E0547, and that the scrutinee type does not change it. The last clause settles ticket 2 and bars step 2 from reading the position type. "The message says what `Q` is" fixes the header contract that tooling needs, and the text has no list that can go stale.
> Concern: A has no example, so a reader may not see that `Q` can be a struct on a `Color` scrutinee; the ERROR_CATALOG entry must show that case.
>
> **Q5. Vote: C.**
> Reasoning: C has "with or without bounds" and "where the generic function is defined", which every seat called load-bearing. The second phrase tells the LSP to put the squiggle in the generic body, not at a call. "Equal only to itself" is short and exact.
> Concern: Without "a match does not refine the type parameter", a Scala or Kotlin user may expect narrowing; the E0300 help must say that a generic body cannot test `T`.
>
> **Q8. Vote: D.**
> Reasoning: D sits in step 3, where a reader meets E0300 against E0308. It links §3.4 *Enums Nominally Distinct from Int*, so a user finds the reason and the `K.from_int(...)` help. It names "a builtin scalar" and "an enum", so struct, `List`, tuple and type parameter stay E0300.
> Concern: "As for a bare name" may be read as a rule for every non-enum position; the test that pins p12 at E0300 prevents that drift.
>
> **Q9. Vote: A.**
> Reasoning: Q7 decided that a variant pattern on a builtin scalar is E0308 whether bare or qualified. The §3.5 scalar sentence must say so, or step 3 and §3.5 give two different rules for `K.B` on `Int`. The user reads one of the two places, so both must agree.
> Concern: The exception now lives in two places (step 3 and §3.5), and a later edit to one can leave the other stale; a spec lint that checks the cross-reference would catch it.

- **AI/ML:**

> **Q3. Vote:** B
> **Reasoning:** B and C state the same rule, "not an enum", before the examples. A model reads the lead clause as the rule and the list as examples in both. I hold B because it opens with the rule; I take C without objection if it wins.
> **Concern:** A model may read "such as" as a closed list unless it reads the lead clause first.
>
> **Q4. Vote:** A
> **Reasoning:** It gives all three facts: a non-enum `Q` declares no variant, the code is E0547, and the scrutinee type does not change it. The last clause settles ticket 2 in words and keeps step 2 a plain lookup. "The message says what `Q` is" tells the implementer that the header differs by kind.
> **Concern:** A has no example in the text, so a model may not see that `Q` can be a struct on a `Color` scrutinee.
>
> **Q5. Vote:** C′
> **Reasoning:** C′ is C plus "A match does not refine the type parameter". A model trained on Scala, Kotlin or TypeScript expects narrowing, and one five-word sentence blocks that guess in the text itself. It costs few tokens and adds no decision point. C is my second choice.
> **Concern:** Without the narrowing sentence, a model may try a bound or an `is`-style test as a way around E0300.
>
> **Q8. Vote:** D
> **Reasoning:** The exception sits in step 3, where a model looks for the E0300 rule. D names the scalar position and "an enum", so struct, `List` and type parameter stay E0300 (p12). It links §3.4 *Enums Nominally Distinct from Int*, so a model can find the reason and the `K.from_int(...)` help. D′ is my second choice.
> **Concern:** "as for a bare name" may be read as a rule for every non-enum position, which Q4 and Q5 forbid.
>
> **Q9. Vote:** A
> **Reasoning:** Step 3 says "bare or qualified" under every Q8 option. If §3.5 keeps the old sentence, a model sees two statements of one rule and reads the shorter one as bare only. One rule stated twice must say the same words.
> **Concern:** The same exception now sits in two places, and a later edit may change one and not the other.

- **Minimalism:**

> **Q3. Vote: B.**
> Reasoning: B and C state the same rule, "not an enum", and give the list as examples. B is the shorter text and drops the "When ... is" frame, so it adds fewer words to the spec. The rule decides, not the list.
> Concern: A later edit may grow the example list until it reads as the rule.
>
> **Q4. Vote: A.**
> Reasoning: A has the three facts: a non-enum `Q` declares no variant, the code is E0547, and the scrutinee type does not change it. It has no list to go stale. My C was shorter but did not name the code.
> Concern: A has no example, so a reader may not see that `Q` can be a struct on a `Color` scrutinee.
>
> **Q5. Vote: C.**
> Reasoning: C holds the rule, "with or without bounds" and "where the generic function is defined", which every seat called load-bearing. C' adds a sentence that gives the reason, and the rule needs no reason to hold. Five seats hold C, and it adds the fewest words.
> Concern: A user from Scala or Kotlin may expect narrowing, so the E0300 help text, not the spec, must say a generic body cannot test `T`.
>
> **Q8. Vote: C.**
> Reasoning: C is the shortest text. It stands in step 3 where a reader meets E0300, and it names only the qualified form on a builtin scalar, so p12 stays E0300. The link to *Enums Nominally Distinct from Int* already sits in the §3.5 scalar sentence, so step 3 need not repeat it.
> Concern: Step 3 and the §3.5 scalar sentence now state the same exception, and they can drift.
>
> **Q9. Vote: A.**
> Reasoning: The paragraph above the §3.5 scalar sentence is about bare names, so "a variant pattern" reads as bare there. Two words, "bare or qualified", stop a later ticket and keep it equal to step 3. This is a fix to the wording, not a new rule.
> Concern: Each place that restates the exception is one more place to edit if the rule changes.

#### Owner decision

Q3 and Q8 ended without a majority after Phase D. The owner (BDFL) broke both ties: use plain wording and examples, and no panel text. The spec text in *A variant the enum does not declare* and in *Qualified names and the wrong type* is therefore not a quote of any option above. The owner's reading of the two questions:

- **Q3.** A variant pattern needs an enum. On any other type, it is an error. The rule word is "not an enum"; the types the text names are examples, not a full list.
- **Q8.** One exception: on an `Int` (or another builtin number type), the error suggests a conversion (`Color.from_int(n)`). The exception goes in step 3. It is limited to a builtin scalar position; a struct, a `List`, a tuple and a type parameter stay E0300.

The panel also agreed on these points, and the spec states them:

- A type alias resolves at step 1, so `J.A` with `type J = K` follows `K` (p18 stays legal).
- Any list of non-enum types is a list of examples. The rule is "not an enum".
- The type-parameter text keeps "with or without bounds" and "where the generic function is defined".
- The §3.5 scalar sentence says "bare or qualified" (Q9).

#### Dissents and concerns

No seat dissented on Q1, Q2, Q4, Q7 or Q9. The recorded dissents and shared concerns:

- **Q5.** Web voted D in Phase C and Systems voted A; both voted C in Phase D. AI/ML held C′ in Phase D and accepted C. AI/ML's concern, in its own words: "Without the narrowing sentence, a model may try a bound or an `is`-style test as a way around E0300." Systems, Web, DevOps and Minimalism named the same worry for the help text of E0300: it should say that a generic body cannot test `T`. The spec does not say this; it is open to the diagnostics work.
- **Q6.** Minimalism voted A, one clause in the existing sentence. Its concern: "A reader skims the clause, and an LLM learns from examples; no `Int.Zed` example appears in §3.4." The spec adds an example for this reason.
- **Q8.** Systems, DevOps and AI/ML shared one risk about option D, in AI/ML's words: "The words "as for a bare name" may be read as a rule for all non-enum positions, which Q4 and Q5 forbid." Systems and DevOps asked for a test that pins p12 at E0300. The owner's text does not use "as for a bare name", and it names the limit.
- **Exception in two places.** Every seat's concern on Q8 and Q9: the exception to step 3 is stated in step 3 and in the §3.5 scalar sentence, and a later edit to one can leave the other stale. DevOps and PLT suggested a spec lint that cross-checks them.
- **Web, on Q6 (the bracket marks a replaced ticket ID):** "The [open bug on `T.NOPE`] is a different bug and the text must not imply it is fixed." The §3.4 text does not claim that it is fixed.

### Final Spec

```blink
type Color { Red, Green }
type Point { x: Int, y: Int }

fn a(xs: List[Int]) -> Int {
    match xs {
        Empty => 0                // error[EnumPatternNeedsEnumScrutinee]: `List[Int]` is not an enum; it has no variants
        _ => 1
    }
}

fn b(c: Color) -> Int {
    match c {
        Point.Zed => 1            // error[NoSuchVariant]: `Point` is a struct; it has no variants
        _ => 0
    }
}

fn c(n: Int) -> Int {
    match n {
        Int.Zed => 1              // error[NoSuchVariant]: `Int` is not an enum; it has no variants
        _ => 0
    }
}

fn d(n: Int) -> Str {
    match n {
        Color.Red => "red"        // error[EnumPatternNeedsEnumScrutinee]; help: Color.from_int(...)
        _ => "other"
    }
}

fn e(p: Point) -> Str {
    match p {
        Color.Red => "red"        // error[TypeError]
        _ => "other"
    }
}

fn f[T](t: T) -> Str {
    match t {
        Color.Red => "red"        // error[TypeError], reported here, with or without bounds
        _ => "other"
    }
}

fn main() {
    let x = Int.Zed               // error[NoSuchVariant]
}
```

- A variant pattern needs an enum. On a type that is not an enum, a bare name with a payload, and a bare uppercase name with no payload, is E0308 `EnumPatternNeedsEnumScrutinee`. The rule is "not an enum"; a builtin scalar, a struct, a tuple, a `List`, a `Map` and a type parameter are examples (Q1, Q3).
- A type alias resolves first, so an alias of an enum is an enum (agreed point).
- A qualified `Q.V` where `Q` is a type that is not an enum is E0547 `NoSuchVariant` at step 2, span the variant name, whatever the type at the pattern position. The header says what `Q` is: "`Int` is not an enum; it has no variants" for a scalar or a builtin generic, and "`Point` is a struct; it has no variants" for a struct (Q1, Q2, Q4).
- A qualified enum pattern or a struct pattern on a scrutinee of a type parameter is E0300, with or without bounds, reported where the generic function is defined (Q1, Q5).
- A `Q` that is not an enum is E0547 in an expression too (`Int.Zed`, `Point.Zed(1)`) (Q6).
- A variant pattern on a builtin scalar, bare or qualified, is E0308 (Q7, Q9). The exception to step 3 stays in step 3, limited to a builtin scalar position: `K.B` on an `Int` is E0308 with the help `K.from_int(...)`. A struct, a `List`, a tuple or a type parameter stays E0300; `Option.Some(v)` on a `List[Int]` is E0300 (Q7, Q8).
- The order of checks stays E0507, then E0547, then E0300 (earlier vote). No new error code.
- `check` and `build` report the same diagnostics. Today `Int.Zed`, `List.Zed(v)`, `Str.Zed` and `Map.Zed` in a pattern, and `Int.Zed` and `Point.Zed(1)` in an expression, stop the compiler with an internal error; the spec leads the compiler here.
