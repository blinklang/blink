[< All Decisions](../DECISIONS.md)

# Variant Names a Pattern's Enum Lacks (`NoSuchVariant`) — Design Rationale

A pattern or a qualified value can name a variant that its enum does not declare. The spec already made some of these forms illegal, but it named no diagnostic for them. The ticket said: "Blocks the v0.57.0 release: tests/test_fuzz.bl (seed 42) hits it, and task release runs ci-release." It asked for the code (reuse one or add one), the span, the help, whether binders under the bad arm are poisoned, and whether exhaustiveness still runs.

Facts before the vote:

- §3.5 *Bare names: variant or binding* (6-0) says: "A bare name with a payload must name a variant of the scrutinee type. The program-wide search of §3.4 (step 3) never runs in a pattern". So bare `Somee(v)` and `Q(v)` are already illegal. Only the diagnostic was open. A bare name with no payload is a new binding, and it is not in scope here.
- gen1 `blink check`, measured before the vote:
  - `K.Zed` in a pattern passes `check`, then `build` stops with an internal compiler error (`UnknownVariant`).
  - `Somee(v)` on `Option[Int]` gives two internal errors (`NodeCarriesNoType`) and no user error.
  - `Q(v)` on `T`, where `Q` belongs to another enum, gives only `NonExhaustiveMatch` (E0004) for the missing `A`.
  - `Other.Q(v)` on `T` gives no error at all.
  - In value position, `let x = K.Zed` gives no error. `let y = Zedd(1)` gives `UndefinedFunction` (E0504).
- Live codes: E0004 `NonExhaustiveMatch` and E0005 in the pattern range; E0300 `TypeError`; E0504, E0506, E0507 `UnknownType`, E0519 and E0525 `NoSuchField` in the name-resolution range. `EnumPatternNeedsEnumScrutinee` (E0308) fires only when the scrutinee is a builtin scalar. E0526 is used in `src/diagnostics.bl` (`OverlappingImpls`) and is not in the catalog. `UnknownVariant` exists in `src` only as a codegen ICE label.
- ERROR_CATALOG *Conventions* (nearest-name suggestion): the written name is compared with its candidates after the compiler ignores case, `_` and `-`. One nearest candidate gives a `help:` line; two equal candidates or none near enough give no suggestion. "Each row that suggests a name says which names are its candidates."
- §6.3.5: downstream references to a poison symbol suppress their own diagnostics. §3.5: every match must be exhaustive, and guarded arms do not count.

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in independent-proposal → debate → vote → focused round-2 rounds. Quoted text is each panelist's own, verbatim. `[...]` marks a cut, and local ticket IDs are replaced with a short name in square brackets.

In the dedupe, the options were:

- D1, the name: `NoSuchVariant` (five seats) or `UnknownVariantPattern` (Web).
- D2, value position (`let x = K.Zed`): the same code, decided now; the same code as a follow-up widening; or a pattern-only code now.
- D3, the number: E0006 in the pattern range, or the next free E05xx number next to E0525.
- D4, a qualified variant of a different enum (`Other.Q(v)` on `T`): the same new code, E0300 `TypeError`, or a second new code (E0007 `PatternEnumMismatch`).
- D5, a note that names another enum that declares the bare name.
- D6, help details: filter candidates by payload form or gate only the fix; mark variants other arms match; an "or add the variant" line; a cap on a long list.
- D7, other checks on a match with a bad arm: skip E0004 and all unreachable-arm checks; skip E0004 only; or skip E0004 and the unreachable checks after the first unguarded bad arm.
- Out of scope: a warning for a bare capitalized binder near a variant name (`Nnoe => 0`).

#### Phase A — Independent proposals

All six seats asked for a new code. Five chose the name `NoSuchVariant`. Four chose E0006 and two chose E05xx. PLT and Minimalism sent the wrong-enum case to E0300, Systems wanted a second code (E0007), and the other three wanted one code for all of it. Excerpts:

- **Systems:**

> There is no runtime cost question here. A variant lowers to a tag. A pattern that names no tag has no lowering, so codegen must never see one. Today `K.Zed` passes `check` and dies in `cg_stmt` as ICE "UnknownVariant". That breaks §3.1 Diagnostic Discipline ("no rule is enforced only at codegen"). It also means `check` and `build` disagree, which costs every tool that trusts `check`, including the LSP and AI loops.
>
> My bar: the front end resolves every variant pattern to a (enum tid, tag index) pair, or it poisons the arm. Mono and lowering may then assume the pair exists. A missing one is a real ICE, not a user error.
>
> [...]
>
> `Other.Q(v)` on scrutinee `T` is a different error. `Other.Q` exists, but it is the wrong type. Today the compiler is silent here, which is the worst case. The repair is also different: change the scrutinee or the qualifier, not rename the variant. So the name must differ, or the AI gets one name with two repairs.
>
> [...]
>
> 2. **Exhaustiveness.** A match with an E0006 or E0007 arm skips E0004. The bad arm's coverage is unknown: once renamed, it might cover the missing variant, as with `Somee` → `Some`.

- **Web/Scripting:**

> Lens: a JS/Python dev who types `Somee(v)` made a typo. They need ONE error, ON the typo, naming the fix. Today they get an ICE, silence, or a "missing `A`" error pointing at the wrong arm. An AI self-correcting needs the same thing.
>
> [...]
>
> One rule, one code, one `blink explain` page. E00xx range because it is a pattern error, next to E0004/E0005.
>
> [...]
>
> §3.5 makes `Nnoe` a binding, so it silently matches everything. This is the Python bug I worry about most. Propose lint W00xx `BindingShadowsVariantName`: fires when a bare pattern binding starts uppercase and names a variant of the scrutinee or is near one by the nearest-name rule.

  Web's first choice was the name `UnknownVariantPattern` with E0006. Its Proposal 2 was one name for pattern and value position.

- **PLT:**

> A constructor pattern has a typing rule only when its constructor C is in ctors(head(τ)). Today the bad case has no rule at all, so the checker falls through to the cg ICE.
>
> [...]
>
> Code: put it in E05xx (name resolution), because the failure is a lookup in ctors(E) and has nothing to do with pattern shape.
>
> [...]
>
> `Other.Q(v)` checked against `T`: Q ∈ ctors(Other), so the lookup succeeds. Unifying Other[ᾱ] with T is what fails. That is plain E0300, the same judgment the expression `let t: T = Other.Q(1)` uses. A new code here would put a second name on a failure that already has one.
>
> [...]
>
> So E0004 and unreachable-arm checks do not run for a match that has any arm with an ill-typed pattern.

- **DevOps:**

> **Name and range.** The name `NoSuchVariant` pairs with `NoSuchField`, so an AI that learned one can guess the other. It goes in E00xx because the decided ranges put pattern matching there and it is the next free code.
>
> [...]
>
> The rename is machine-applicable only when two conditions hold:
> 1. There is exactly one suggestion.
> 2. The suggested variant's payload form matches the written one: paren arity, brace or unit.
>
> [...]
>
> The same mistake should not get two names depending on which side of `=>` it is on: an LSP code action, a `blink fix` rule and an explain page then serve both positions.

- **AI/ML:**

> **Name:** `NoSuchVariant`, not `UnknownVariant`. It pairs with `NoSuchField`, so an AI that has seen one can guess the other. `UnknownVariant` is also the name of an uncatalogued codegen ICE in `src/cg_stmt.bl`, and reusing it would make search results harder to read.
>
> [...]
>
> **Reason (Diagnostic Discipline rule 3, and how agents behave):** if both errors fire, a model often applies both repairs. It renames `Somee` to `Some` and also adds the `Some(_) => ...` arm that E0004 asked for. The result is a duplicate arm, or an unreachable-arm warning and a fourth iteration.
>
> [...]
>
> I do NOT want two names for one mistake. Rust's split here is a known source of model confusion.

- **Minimalism:**

> The gap is wider than the ticket says:
> - `match x { Ok(v) => v  _ => 0 }` on `Option[Int]` ICEs with NodeCarriesNoType, like `Somee(v)`.
> - `match p { Q { y } => y }` with `p: P`, where `Q` and `P` are different structs, passes check with no error at all. This is the same silent wrong-type-pattern gap as `Other.Q(v)` on `T`.
>
> [...]
>
> There must be a new code. The other options do not fit:
> - Reusing E0525 NoSuchField fails because the name is frozen and says "Field". An AI reads the code name as its first fact.
> - E0300 TypeError does not fit because this is not a type mismatch. The type is right and the name is wrong.
>
> [...]
>
> I am against any cross-enum "did you mean `Result.Ok`?" note, because it brings back the program-wide search in patterns that §3.5 removes.

  Minimalism's M2 then sent a pattern of a different type, `Other.Q(v)` on `T` or `Q { y }` on `P`, to E0300: "`Other.Q(v)` on a `T` scrutinee names a real variant. The fault is the type, not the name."

#### Phase B — Debate highlights

One round. All six seats replied "stable, ready to vote". The seats agreed on these points before the vote: a new code is needed; the span of a bare name or of `K.Zed` is the variant-name token; candidates are the variants of the enum at that pattern position that are visible at the site; binders get the poison type and the arm body is still checked; the rule holds at every pattern depth (`Some(Somee(v))`); bare `Zedd(1)` stays E0504, an undefined qualifier stays E0507 and a builtin-scalar scrutinee stays E0308.

Moves:

- Systems moved to the same code for both positions, then to E05xx, then to E0300 for the wrong-enum case.
- Web withdrew `UnknownVariantPattern`.
- DevOps and AI/ML moved from the same code to E0300 for the wrong-enum case.
- PLT moved to E0007 as its first choice for the wrong-enum case (and moved back to E0300 in Phase C).
- Minimalism moved to E0006 so that the vote would not split, and moved back in Phase C.

- **Systems:**

> **D4 — `Other.Q(v)` on a `T` scrutinee**
> I withdraw S2 (E0007) and move to **(ii) E0300 TypeError** (plt P2, min M2). PLT's argument decides it: lookup succeeds (Q ∈ ctors(Other)), and unifying Other with T fails. That is the same judgment as `let t: T = Other.Q(1)`, which is already E0300. My reason for a separate code was "one name, one repair". E0300 keeps that, because its repair is "fix the type". Option (i) puts a false message on a true fact: "`T` has no variant `Q`" is beside the point when the author wrote `Other.Q` deliberately.

  On D6(a): "My filter hid a correct name in one real case (the author wrote the wrong payload *and* the wrong name). The devops form still stops a tool from auto-applying a fix that leads to an arity error, which was my concern."

- **Web/Scripting:**

> **D2 Value position: same code, decided now (plt/min/devops/aiml)**
> I move here; it was my Proposal 2. One mistake, one name, in both positions. A follow-up ticket only leaves `let x = K.Zed` silent for another release, and a silent pass is worse than any ICE.

  On D6(c): "A pattern typo almost never means a missing variant. For an AI-first language, this line invites a model to add a bogus variant instead of fixing the typo."

- **PLT:**

> **D4 Qualified variant of another enum. I move: (iii) first, (ii) second, against (i).**
>
> - Against (i). `Other.Q` passes the lookup: Q ∈ ctors(Other). What fails is the unification of Other with T. Giving it the "no such variant" code puts two judgments under one name, each with a different repair: rename, or change the qualifier or scrutinee.
>
> [...]
>
> - Order rule, which every option must state: resolve the qualifier (E0507), then look up the variant (NoSuchVariant on the *qualifier's* enum), then unify with the scrutinee type (D4 code). So `Other.Zed` on `T` is NoSuchVariant on `Other`, one error.

  On D5: "Q7 governs what a pattern *means*, that is, name resolution. A diagnostic may consult any information as long as it changes no typing derivation. The note does not suggest `Other.Q`, so it proposes no edit that is still an error."

  On D7, PLT proposed (C): skip E0004 only when an unguarded arm is bad, and skip unreachable checks only for arms after the first unguarded bad arm.

- **DevOps:**

> **D4, `Other.Q(v)` on a `T` scrutinee: I move from (i) to (ii), E0300 TypeError**
> plt's argument decides it for me. The name lookup succeeds; the type is what fails. In value position `let t: T = Other.Q(1)` already gives E0300. My own reason for D2 was "one mistake, one code in both positions", and that same reason puts the pattern form on E0300.
>
> Conditions, so the tooling stays good:
> - The span is the whole `Other.Q` path (the majority span).
> - The header names both types: "pattern has type `Other`, but the value matched has type `T`".
> - No nearest-name help and no `fix:`, because the right edit is unknown.

  On D7: "The bad arm counts as covering nothing, so it can never make a later arm "unreachable" by mistake."

- **AI/ML:**

> **D4 — `Other.Q(v)` on a `T` scrutinee: I MOVE from (i) to (ii), E0300 TypeError, on two conditions**
> [...]
> 1. Keep plt's help line `help: \`T\` declares: A(Int), B`. min's form with no help leaves the model with two types and no edit. That is close to a rule-1 failure, because the obvious repair is not named.
> 2. Add sys's qualifier swap: when `T` declares a variant of the same name and payload shape, the help says ``help: use `T.Q` `` and the fix is machine-applicable.

  On D5: "The note must state outright that the pattern still cannot use it".

- **Minimalism:**

> **D5, a note naming another enum: no note (not blocking)**
> - The variant list already gives the fix. A list of 2 to 10 names is enough for a human and an AI.
> - The note needs a program-wide lookup just to write a message. That is code to keep and test, for small gain.
> - If the panel adds it anyway, I accept only aiml's restriction: the note appears only when exactly one enum in scope declares the name.

  Minimalism also asked that the wrong-struct case (`Q { y }` on `P`) get a named code: "or the impl ticket fixes `Other.Q` and leaves this one silent."

#### Phase C — Final vote

Options for the questions, as the ballot gave them:

- Q1, name: A `NoSuchVariant`; B `UnknownVariantPattern` (withdrawn by its author).
- Q2, value position: A the same code, written into the spec now; B pattern-only now.
- Q3, number: A E0006; B E05xx (E0547; E0526 is taken in `src`).
- Q4, a qualified variant of a different enum: (i) the new code; (ii) E0300; (iii) E0007.
- Q5, the note: A add it, only when exactly one enum visible at the site declares the name; B no note.
- Q6a, payload form: A all candidates stay, the rename is machine-applicable only when the payload form matches; B filter candidates by payload form. Q6b: A plain list; B mark variants other arms match. Q6c: A add "or add the variant to `K`"; B no such line. Q6d: A no cap in the spec; B cap at 10; C cap the terminal text only.
- Q7, other checks: A skip E0004 and all unreachable checks; B the bad arm covers nothing, skip E0004 and the unreachable report for the bad arm itself; C skip E0004 and unreachable checks for arms after the first unguarded bad arm. Q7b: X any bad arm; Y only an unguarded bad arm.
- Q8a: the order qualifier, variant lookup, then type comparison. Q8b: the front end resolves every variant or reports; `check` and `build` report the same diagnostics. Q8c: a bare payload pattern on a struct, tuple or type parameter gets the new code; an unsolved type keeps its existing error.

- **Q1: Name `NoSuchVariant`** (6-0 A)

  - **Systems:**

    > **Vote:** A, `NoSuchVariant`
    > **Reasoning:** It pairs with `NoSuchField`: both mean "this aggregate does not declare this member". The string `UnknownVariant` is the codegen ICE label, so any name near it would mix up user errors with compiler defects in bug reports.

  - **Web/Scripting:**

    > **Vote:** A, `NoSuchVariant`
    > **Reasoning:** It pairs with `NoSuchField`, so someone who has seen one guesses the other at once. My withdrawn name put the position into the name, and that stops being true once the code covers value position too.

  - **PLT:**

    > **Vote:** A, `NoSuchVariant`
    > **Reasoning:** The judgment is a member lookup that fails, C ∉ ctors(E). It is the same shape as NoSuchField, field ∉ fields(S), so the names should match. The name says nothing about position, which Q2 needs.

  - **DevOps:**

    > **Vote:** A, `NoSuchVariant`
    > **Reasoning:** It pairs with `NoSuchField` (E0525), so a reader who knows one row can guess the other. It does not name a position, so it fits both the pattern and value sites.

  - **AI/ML:**

    > **Vote:** A, `NoSuchVariant`
    > **Reasoning:** It pairs with `NoSuchField` (E0525). A model that has learned one can predict the other's name, span and help without reading the row.

  - **Minimalism:**

    > **Vote:** A, `NoSuchVariant`.
    > **Reasoning:** It pairs with `NoSuchField`, so a reader learns one shape, not two. It does not put the position into the name, so one name serves patterns and values.

- **Q2: Same code for value position, decided now** (6-0 A)

  - **Systems:**

    > **Vote:** A, same code, written into the spec now
    > **Reasoning:** `K.Zed` in a `let` is the same lookup failure as in a pattern, and today it passes `check` silently. That is a gap that only codegen sees, the same failure class as this ticket. One sentence in §3.4 closes it.

  - **Web/Scripting:**

    > **Vote:** A, the same code, written into the spec now
    > **Reasoning:** `let x = K.Zed` passes check silently today, which is worse than any error. One mistake should get one name, one explain page and one fix in both positions.

  - **PLT:**

    > **Vote:** A, same code, decided now
    > **Reasoning:** `K.Zed` in an expression and in a pattern fail the same premise of the same rule. Two names for one judgment does not compose.
    > **Concern:** The value-position rule must give the expression the poison type, so `let x = K.Zed` does not cascade at every use of `x`.

  - **DevOps:**

    > **Vote:** A, same code, written into the spec now
    > **Reasoning:** `let x = K.Zed` passes `check` today with no error. A silent pass is the worst diagnostic outcome, and deferring it ships one more release with that pass.

  - **AI/ML:**

    > **Vote:** A, the same code, written into the spec now
    > **Reasoning:** `K.Zed` fails the same check in a `let` and in a `match`. A model learns one fact only when one name covers both positions. B leaves `let x = K.Zed` passing silently for another release, and a model cannot learn from silence.

  - **Minimalism:**

    > **Vote:** A, the same code, written into the spec in this decision.
    > **Reasoning:** One mistake gets one code. `let x = K.Zed` is silent today, and a follow-up ticket only extends that silence for one sentence of text.

- **Q3: Code E0547 (E05xx, next to E0525)** (6-0 B)

  - **Systems:**

    > **Vote:** B, E05xx (E0547)
    > **Reasoning:** Once the code covers value position, it is a member-lookup failure, not a pattern-shape failure. Its sibling NoSuchField is at E0525.
    > **Concern:** E0526 is in src without a catalog row. Whoever implements this must take E0547 exactly, not "the next free number" by a grep that misses src.

  - **Web/Scripting:**

    > **Vote:** B, E0547 (E05xx)
    > **Reasoning:** Once the code covers value position, it is a lookup failure like E0525, not a pattern-only error. [...] This is a weak preference.

  - **PLT:**

    > **Vote:** B, E05xx (E0547)
    > **Reasoning:** With Q2 at A, the code is not specific to patterns; it is a name lookup, and its sibling E0525 is already in that range.
    > **Concern:** Readers who look for pattern errors in E00xx will miss it, so §3.5 must cite the code inline.

  - **DevOps:**

    > **Vote:** B, E05xx (E0547)
    > **Reasoning:** Once the code covers value position, it is a lookup in a type's namespace, and its sibling E0525 is in E05xx. A pattern-range number would misfile every value-position use.

  - **AI/ML:**

    > **Vote:** B, E05xx (E0547)
    > **Reasoning:** I move from my weak E0006 to converge. Once Q2 covers value position, the code is a member lookup like E0525, and filing it in E00xx misfiles half its sites.

  - **Minimalism:**

    > **Vote:** B, the next free E05xx number (E0547).
    > **Reasoning:** With Q2 at A, the code is not pattern-only. Its sibling NoSuchField is in E05xx, so a reader finds both in one place. I said E0006 in round 1 only to avoid a split.

- **Q4: `Other.Q(v)` on `T` and wrong-struct `Q { y }` on `P` are E0300 TypeError** (6-0, (ii) first choice; the wrong-struct case goes under E0300 for all six)

  - **Systems:**

    > **Vote:** (ii) E0300 first, (iii) second. The wrong-struct pattern (`Q { y }` on `P`) goes under E0300 too.
    > **Reasoning:** Lookup succeeds and unification fails. That is the same judgment as `let t: T = Other.Q(1)`, which is already E0300, so one judgment keeps one name in both positions. Option (i) would print a false or misleading header.

  - **Web/Scripting:**

    > **Vote:** (ii) E0300 first, (i) second. Against (iii).
    > **Reasoning:** My own D2 argument decides this: one mistake should get one name in both positions, and `let t: T = Other.Q(1)` is already E0300. [...] I accept E0300 only with a header that names both types, a help line that lists `T`'s variants, the machine-applicable `T.Q` swap when it fits, and a span on the whole path.

  - **PLT:**

    > **Vote:** (ii) E0300 first, (iii) second, against (i).
    > **Reasoning:** In round 1 I leaned (iii), as a sibling of E0308. The stronger argument is the one I made for Q2: `let t: T = Other.Q(1)` is already E0300, and the pattern form is the same unification failure, so one judgment should keep one name in both positions. (ii) also covers the wrong-struct case with no new rule.

  - **DevOps:**

    > **Vote:** (ii) E0300 first, (iii) E0007 second, against (i).
    > **Reasoning:** The lookup succeeds and the type fails, and `let t: T = Other.Q(1)` is already E0300. One code for one failure, the same in both positions.
    > **Concern:** E0300 is a broad code, so a user who silences or filters it hides this case with every other mismatch.

  - **AI/ML:**

    > **Vote:** first (ii) E0300 TypeError; second (iii) E0007
    > **Reasoning:** The lookup succeeds and the type fails, and `let t: T = Other.Q(1)` is already E0300. The same judgment must get the same name in both positions, or a model learns two names for one mistake.
    > **Concern:** A bare E0300 with no help names no edit.

  - **Minimalism:**

    > **Vote:** First (ii), E0300 TypeError. Second (i). Against (iii).
    > **Reasoning:** [...] (ii) also covers the wrong-struct pattern (`Q { y }` on a `P` scrutinee) with no extra rule. Under every option, that struct case goes to E0300.
    > **Concern:** E0300's header is generic, so the message must name both types, or an AI has nothing to act on.

  The conditions on the E0300 row came from the ballots: the header names both types; the span is the whole path; the help lists `T`'s variants; the fix `T.Q` is machine-applicable when `T` declares `Q` with the same payload form; binders are poisoned; there is no E0004.

- **Q5: A note naming the other enum, only when exactly one visible enum declares the name** (5-1 A)

  - **Systems:**

    > **Vote:** A, add the note only when exactly one enum visible at the site declares the name
    > **Reasoning:** The lookup runs only after the pattern has failed, so it changes no meaning, and §3.5 Q7 holds. It costs nothing on the success path. It tells the author the likely real fault, a wrong scrutinee, which the variant list does not.

  - **Web/Scripting:**

    > **Vote:** A, the note, only when exactly one enum visible at the site declares the name
    > **Reasoning:** `Q(v)` on `T` usually means "wrong value matched" or "forgot the qualifier", and one line telling the user where `Q` lives answers that.

  - **PLT:**

    > **Vote:** A, the note, only when exactly one visible enum declares the name
    > **Reasoning:** Q7 constrains which typing derivation a pattern has. A note on the error path changes no derivation, so it does not reopen the program-wide search for meaning.
    > **Concern:** Implementers may reuse the §3.4 search function for the note and accidentally let it resolve the pattern, so a test must pin that the pattern stays an error.

  - **DevOps:**

    > **Vote:** A, add the note, only when exactly one enum visible at the site declares the name
    > **Reasoning:** The note tells a human or an AI why the name failed: it belongs to another type, it is not a typo. It does not change what the pattern means.

  - **AI/ML:**

    > **Vote:** A, only when exactly one enum visible at the site declares the name
    > **Reasoning:** The note tells a model *why* the name failed: it belongs to another type, it is not a typo. That stops a blind rename to the nearest variant.

  - **Minimalism:** **(dissent)**

    > **Vote:** B, no note.
    > **Reasoning:** The variant list of the scrutinee enum already gives the fix. The note is extra code on the error path for a small gain. I accept that it does not change meaning, so this is a cost argument, not a §3.5 argument.
    > **Concern:** If A wins, the note may tempt an edit to `Other.Q`, which then fails with E0300. aiml's wording ("a pattern for `x` can name only variants of `T`") must be the required text.

- **Q6a: All variants are candidates; the rename is machine-applicable only when the payload form matches** (6-0 A)

  - **Systems:**

    > **Vote:** A. **Reasoning:** I withdrew my filter. Every candidate stays, and the payload-form gate applies only to the machine-applicable `fix:`. So the right name is never hidden, and no auto-fix produces an arity error.

  - **Web/Scripting:**

    > **Q6a: A.** Keep all candidates; the fix is machine-applicable only when the payload form matches. Filtering hides `Some` exactly when the user got both the name and the payload wrong.

  - **PLT:**

    > **Q6a Vote:** A
    > **Reasoning:** The nearest-name rule stays the catalog's one rule. Payload form only gates whether the fix can be applied by a machine, which keeps fixes convergent and never hides the right name.

  - **DevOps:**

    > **Q6a vote:** A, keep all candidates; the fix is machine-applicable only when the payload form matches
    > **Reasoning:** The filter hides `Some` when a user writes unit `Somee` against `Some(T)`, which is the most likely case. The form check stops `blink fix` and LSP quick-fix from applying an edit that is known to fail.

  - **AI/ML:**

    > **Q6a — Vote:** A. **Reasoning:** Keep all candidates, and make the rename machine-applicable only when the payload form matches. A typo often gets the payload wrong too, and a filter would hide the right name exactly then.

  - **Minimalism:**

    > **Q6a:** Keep every candidate, and gate only the auto-fix on payload form. This stops a fix that produces a new error, and it adds no second suggestion rule.

- **Q6b: A plain variant list, with no "matched" marks** (5-1 A)

  - **Systems:**

    > **Q6b — Vote:** A, plain list. **Reasoning:** Marks depend on arm order and guards, so the output changes when an unrelated arm is edited. That breaks snapshot tests and buys little once the list is short.

  - **Web/Scripting:**

    > **Q6b: A, a plain list.** Marks that depend on arm order churn the output when the user edits an unrelated arm.

  - **PLT:** **(dissent)**

    > **Q6b Vote:** B, mark matched variants (low stakes)
    > **Reasoning:** When E0004 is suppressed, the marks are the only place the coverage facts show, and they point at the intended variant. Tie the marks to the E0004 rule: unguarded arms only.
    > **Concern:** The output changes when a different arm is edited, which makes snapshot tests churn.

  - **DevOps:**

    > **Q6b vote:** A, plain list
    > **Reasoning:** "(matched)" marks change when an unrelated arm or guard changes. That churns golden tests and LSP diagnostic diffs for no gain in the repair.

  - **AI/ML:**

    > **Q6b — Vote:** A, plain list. **Reasoning:** I drop my "(handled)" preference. devops is right that marks depending on arm order churn snapshots and LSP diffs.

  - **Minimalism:**

    > **Q6b:** A plain list does not change when another arm changes.

- **Q6c: No "or add the variant" line** (5-1 B)

  - **Systems:**

    > **Q6c — Vote:** B, no such line. **Reasoning:** A pattern typo almost never means a missing variant, and for an AI-first language a second help line that adds a bogus variant is a likely wrong edit.

  - **Web/Scripting:**

    > **Q6c: B, no "add the variant" line.** A pattern typo almost never means the enum lacks a variant, and an AI given that line will add a bogus variant instead of fixing the typo.

  - **PLT:** **(dissent)**

    > **Q6c Vote:** A
    > **Reasoning:** Two sibling rows (E0525, NoSuchVariant) should have the same help shape. In value position, adding a variant is often the real repair. It goes after the rename or the list, so the convergent repair comes first.
    > **Concern:** A model may add a bogus variant to fix a pattern typo, so the line must come last.

  - **DevOps:**

    > **Q6c vote:** B, no "or add the variant" line (I change my position)
    > **Reasoning:** web and min convinced me. A misspelled variant almost never means the enum lacks a variant, and an AI often follows the last help line it reads.

  - **AI/ML:**

    > **Q6c — Vote:** B, no such line. **Reasoning:** I move. web and min make an AI-domain argument that I accept: a pattern typo almost never means a missing variant, and a model that sees "add the variant to `K`" will sometimes add a bogus variant instead of fixing the spelling.

  - **Minimalism:**

    > **Q6c:** "Add the variant" is almost never the fix for a pattern typo, and it invites an AI to change the enum.

- **Q6d: Long variant lists** (round 1: 4-2 C, Web and Minimalism for A; round 2 below: 6-0 C)

  - **Systems:**

    > **Q6d — Vote:** C, cap the terminal text only, JSON carries the full list. **Reasoning:** Machine clients need the whole list in one round trip. A human terminal can drop the tail.

  - **Web/Scripting:** **(dissent in round 1)**

    > **Q6d: A, no cap in the spec.** Like "near enough", whether to shorten a long list is up to the implementation. JSON should carry the full list anyway.

  - **PLT:**

    > **Q6d Vote:** C, cap the terminal text only; JSON carries the full list
    > **Reasoning:** A cap is about how the text is shown, not about meaning. The machine-readable channel must stay complete.

  - **DevOps:**

    > **Q6d vote:** C, cap the terminal text only; JSON carries the full list
    > **Reasoning:** That is how the Go and rust-analyzer tools work: a short human render and full machine data. The spec should say only "the terminal render may shorten the list and give a count of the rest; structured output lists every variant." The number itself stays an implementation choice.

  - **AI/ML:**

    > **Q6d — Vote:** C, cap the terminal text only; JSON carries the full list. **Reasoning:** An agent reads JSON and needs every name to avoid a second lookup. A human terminal can stay short. **Concern:** An agent that reads terminal text and not JSON gets a cut list. The "… and N more" line must name `blink explain` or `--format json`.

  - **Minimalism:** **(dissent in round 1)**

    > **Q6d:** A cap is an implementation choice. It does not belong in the spec.

- **Q7: Other checks on a match with a bad arm** (round 1: 3-3, A for Systems, Web and Minimalism, B for PLT, DevOps and AI/ML; round 2 below: 6-0 B)

  - **Systems:**

    > **Vote:** A; trigger Q7b: X (any bad arm, guarded or not)
    > **Reasoning:** Coverage and reachability both need a typing derivation for every arm. One rule, "checked only for a match whose every arm pattern type-checks", is short to state and short to implement.

  - **Web/Scripting:**

    > **Vote:** A, skip E0004 and all unreachable-arm checks for that match; E0005 and the other checks still run. **Q7b:** X, any bad arm, guarded or not.
    > **Reasoning:** One error per mistake. Both coverage checks are computed from arms whose meaning is unknown, so any finding is likely noise until the user fixes the typo, and the next check reports anything real.

  - **PLT:**

    > **Vote:** (B), with aiml's rule that the bad arm itself gets no unreachable check. I move from (C).
    > **Reasoning:** Treating the bad arm as ∅ gives a lower bound on what the earlier arms cover. Unreachability of arm j is monotone in that coverage, so every unreachable report computed with ∅ stays true whatever repair the user makes: no false positives, and no lost findings. Exhaustiveness is the opposite direction, so ∅ there gives false E0004s, and that check alone must be skipped.
    > **Concern:** Implementers may treat the bad arm as `_` instead of ∅, which would report every later arm as unreachable; the spec text must say "covers nothing".

  - **DevOps:**

    > **Vote:** B, with aiml's tweak (skip E0004 and the unreachable check for the bad arm itself; the bad arm covers nothing); second choice A
    > **Reasoning:** A bad arm that covers nothing can never make another arm look unreachable, so the other unreachable checks give no false positives and still report true findings.

  - **AI/ML:**

    > **Vote:** B; Q7b: Y (only an unguarded bad arm)
    > **Reasoning:** The bad arm covers nothing, so it can never make another arm falsely unreachable. Unreachable checks on the other arms stay correct, and every true report there saves an agent a round trip.

  - **Minimalism:**

    > **Vote:** A, trigger X.
    > **Reasoning:** One sentence is enough: when any arm of a match fails to type-check, the compiler reports no coverage result (E0004 or unreachable arm) for that match. All other checks, E0005 included, still run.

- **Q7b: Which bad arms turn off E0004** (round 1: 4-2, X for Systems, Web, DevOps and Minimalism, Y for PLT and AI/ML; round 2 below: 6-0 Y)

  - **PLT:**

    > **Q7b Vote:** (Y), only an unguarded bad arm
    > **Reasoning:** By §3.5 a guarded arm adds nothing to coverage, so a guarded bad arm cannot change E0004's result in any repair. The E0004 it gets is a true finding, not a cascade.

  - **AI/ML:**

    > **Q7b: Y** [...] On Q7b, a guarded arm adds no coverage (§3.5). With `Somee(v) if v > 0`, the E0004 for `Some` is still true after the rename, so reporting it now is correct and is not a cascade.

  - **DevOps:**

    > **Q7b vote:** X, any bad arm, guarded or not
    > **Reasoning:** One rule is easier to state, test and explain. A guarded typo is still the user's attempt at a missing variant, so reporting E0004 next to it reports the same fault twice.

  The other three X votes (Systems, Web, Minimalism) are in the Q7 entries above.

- **Q8a: Order for a qualified pattern: qualifier (E0507), variant lookup (E0547), type comparison (E0300)** (6-0 yes)

  - **Systems:** "A fixed order gives each input exactly one error and makes the output the same in all tools. `Other.Zed` on `T` is one NoSuchVariant on `Other`."
  - **Web/Scripting:** "Qualifier first, then the variant lookup, then the type comparison gives exactly one error for `Other.Zed` on `T`."
  - **PLT:** "Qualifier, then lookup, then unify is the only order where each failure has one code, and it decides `Other.Zed` on `T`."
  - **DevOps:** "This gives exactly one error for `Other.Zed` on `T`, and the order is what makes the output deterministic."
  - **AI/ML:** "A fixed order gives `Other.Zed` on `T` exactly one error, and a model needs one error per point to converge (rule 3)."
  - **Minimalism:** "Without the order, `Other.Zed` on `T` has two possible errors. The order gives exactly one."

- **Q8b: The front end resolves every variant pattern and value or reports; `check` and `build` report the same diagnostics** (6-0 yes)

  - **Systems:**

    > This is the invariant that makes this a front-end rule, not a codegen accident: lowering may assume (enum, tag) is resolved, `check` equals `build`, and an unresolved variant at codegen is an ICE. A fuzz corpus row of the test_fuzz seed 42 shape should pin it.

  - **Web/Scripting:** "`check` passing and `build` ICEing is exactly the betrayal this ticket is about, and it must be stated as a rule."
  - **PLT:** "Every variant reference must have a front-end derivation; `check` and `build` must agree, and an unresolved variant in lowering is an ICE."
  - **DevOps:** "`check` and `build` must report the same diagnostics. An editor runs `check`; if `build` finds more, the LSP lies."
  - **AI/ML:** "This is the ticket's real failure: a user error that surfaces only as an ICE in build is invisible to an agent running `check`."
  - **Minimalism:** "It turns the "no ICE" constraint into a checkable rule. `check` and `build` must agree, or `check` is not worth running." Concern: "Q8b must stay a statement about the diagnostics users see. It must not become a codegen design rule in sections/."

- **Q8c: A bare payload pattern on a struct, tuple or type parameter gets the new code; an unsolved type keeps its existing error** (6-0 yes; the unsolved-type error is `CannotInferType`, E0301)

  - **Systems:** "Today a bare payload pattern against a non-enum reaches lowering unresolved. That is the same silent path, so it needs the same front-end error."
  - **Web/Scripting:** ""`Point` is a struct; it has no variants" is a message any JS developer understands at once."
  - **PLT:** "§3.5 requires a bare payload name to name a variant of τ; when τ has no variants, the premise fails the same way. An unsolved τ has no head to look up, so the under-determined error is the correct one."
  - **DevOps:** ""`Point` is a struct; it has no variants" is a clear, repairable header, and it closes another path where an unresolved pattern reaches lowering."
  - **AI/ML:** ""`Point` is a struct; it has no variants" names the real fault in one line, where today the compiler is silent or ICEs." Concern: "For a type parameter, the message must not suggest a variant, because none exists."
  - **Minimalism:** "A bare payload name against a type with no variants is still "no such variant", so it adds no new code. An unsolved type keeps its existing error."

#### Phase D — Round 2

Three results were closer than 5-1: Q6d (4-2), Q7 (3-3) and Q7b (4-2). The panel reopened these three and nothing else. Every other result stayed as voted. All six seats replied "stable, ready to vote" and then voted again.

The debate turned on PLT's monotonicity argument for Q7:

- **PLT:**

> Both A and B are sound. The difference is compositionality.
> - Under B, whether arm j is unreachable depends only on arms 1..j-1. That is the definition of reachability, and B keeps it.
> - Under A, a typo in arm 5 changes what the compiler says about arm 2, though nothing arm 2's status depends on has changed. A diagnostic that changes because of an unrelated arm is the non-local behavior the cascade rule (§6.3.5) exists to prevent. A turns it into the rule.
> - Every report B keeps is true after any repair, because ∅ is a lower bound on the bad arm's coverage. So B gives no false positives and no lost findings. A loses true findings on purpose.

- **Systems** (moved from A to B):

> plt's monotonicity argument decides it, and I did not answer it in Phase C. Treat the bad arm as covering ∅. Then what the arms before arm j cover is a lower bound on what they will cover after any repair. "Arm j is unreachable" is monotone in that coverage, so every report is still true after the fix. That means no false positives, and true findings arrive one cycle earlier.

- **Minimalism** (moved on all three):

> I move on all three questions. My Phase C votes counted the length of the rule. The round-1 texts show that these options cost about the same text, and that the other side reports only true findings. My seat is about language surface, not about hiding correct errors.

- **DevOps** (moved from X to Y):

> My Phase C reason for X was "reporting E0004 next to a guarded typo reports the same fault twice". plt and aiml showed that this is false. A guarded arm never counts toward coverage (§3.5), so the E0004 for a match whose only bad arm is guarded stays true after every repair of that arm. It is a second, real fault, not a cascade.

- **Web/Scripting** (moved on all three):

> The same principle decides Q7 and Q7b: **report a coverage finding only if it stays true after any repair of the bad arm.** That is one rule a user can learn, and B and Y both follow from it.

On Q6d, Systems, PLT, DevOps and AI/ML argued that option C puts no number in the spec and only writes down one guarantee, that structured output is complete. Web and Minimalism had voted A because "a cap is an implementation choice", and both moved to C. AI/ML asked that the "… and N more" line name `--format json` or `blink explain`; Minimalism called that "a rendering detail", and the final text keeps it in the spec as a requirement on the count line.

Revote:

- **Q6d: Long variant lists** (6-0 C, after 4-2 in round 1)

  - **Systems:**

    > **Vote:** C
    > **Reasoning:** The spec fixes the guarantee and leaves the number to the implementation. Structured output lists every variant, so an agent's repair loop never needs a second lookup. The terminal may shorten the list for a human, with a count of the rest that names `--format json` or `blink explain`.
    > **Concern:** The terminal and JSON outputs then differ, so tests must check the JSON list in full and the terminal count, not one golden for both.

  - **Web/Scripting:**

    > **Vote:** C
    > **Reasoning:** A human in a terminal can live with a short list and a count of the rest, but an agent reading JSON needs every name in one round trip. Leaving the number out of the spec keeps it an implementation choice, as with "near enough". The "… and N more" line should point to `--format json` so terminal readers know where the full list is.
    > **Concern:** If the terminal and JSON outputs drift apart, the "same suggestion in compiler, LSP and explain" convention gets harder to test.

  - **PLT:**

    > **Vote:** C
    > **Reasoning:** No number goes into the spec, so the implementation keeps the rendering choice web and min want. The spec still guarantees that structured output is complete. Agents and the LSP depend on that guarantee, and only the spec can give it.
    > **Concern:** Terminal and JSON outputs differ, so golden tests must check each channel separately.

  - **DevOps:**

    > **Vote:** C
    > **Reasoning:** The spec states no cap number, but it does guarantee that structured output (JSON, LSP) lists every variant. Agents and editors rely on that guarantee. The terminal render may stay short for humans, and its "… and N more" line should point to `--format json` or `blink explain`.
    > **Concern:** The two renders differ by design, so golden tests must check the JSON list and the terminal text on their own terms.

  - **AI/ML:**

    > **Vote:** C
    > **Reasoning:** An agent reads the structured output and needs every variant name to repair in one round, with no second lookup. C leaves the terminal render and the number to the implementation, as A wants, and adds only the guarantee that the JSON is complete.
    > **Concern:** An agent that reads only terminal text gets a cut list, so the "… and N more" line should say how to see the rest.

  - **Minimalism:**

    > **Vote:** C.
    > **Reasoning:** C puts no number in the spec. It adds only one guarantee: structured output lists every variant. That guarantee stops a capped JSON list, which would break AI repair on large enums. The terminal form stays an implementation choice.
    > **Concern:** The terminal text and the JSON output differ, so the tests must check each output on its own.

- **Q7: Other checks on a match with a bad arm** (6-0 B, after 3-3 in round 1)

  - **Systems:**

    > **Vote:** B
    > **Reasoning:** A bad arm that covers nothing gives a lower bound on what the earlier arms cover. Every unreachable report on the other arms then stays true after any repair, so there are no false positives, and true findings arrive one cycle earlier. Only E0004 runs in the unsafe direction, so only E0004 is skipped. It is also the cheaper code: the poisoned arm contributes no coverage, and the reachability pass needs no extra gate.
    > **Concern:** An implementer may treat the bad arm as `_` instead of as covering nothing, which would flag every later arm. The row and a test must pin "covers nothing".

  - **Web/Scripting:**

    > **Vote:** B
    > **Reasoning:** A bad arm that covers nothing can only gain coverage when it is fixed. So every unreachable-arm report on another arm stays true after any fix: it is a real second mistake, not a cascade. Reporting it now saves the user a compile cycle. The bad arm itself gets no unreachable report, so the user sees no false error on the line they are about to edit.
    > **Concern:** An implementer may treat the bad arm as `_` instead of as covering nothing, which would flag every later arm. The spec text must say "covers no values".

  - **PLT:**

    > **Vote:** B
    > **Reasoning:** Treating the bad arm as covering nothing is a lower bound on its coverage. Every unreachable report on another arm therefore stays true after any repair: no false positives, no lost findings. Reachability of arm j keeps depending only on arms before it, which is compositional. A makes a typo in one arm hide true facts about unrelated arms.
    > **Concern:** An implementation that treats the bad arm as `_` instead of as covering nothing reports every later arm as unreachable, so the spec must use the words "covers nothing" and a test must pin them.

  - **DevOps:**

    > **Vote:** B
    > **Reasoning:** A bad arm that covers nothing can only cover more after a fix. So every unreachable report on another arm stays true: no false positives and no lost findings. A drops true findings to save one clause, and each lost finding costs an LSP user or an agent one more edit-check round trip.
    > **Concern:** An implementation that treats the bad arm as `_` instead of covering nothing marks every later arm unreachable. The spec must say "covers nothing", and a test must put a valid arm after a bad arm.

  - **AI/ML:**

    > **Vote:** B
    > **Reasoning:** Treat the bad arm as covering nothing. Then every unreachable-arm report on the other arms stays true after any repair, so B gives no false positives and loses no findings. A true finding reported now saves an agent a round trip. The spec text is one sentence: the arm covers nothing, gets no unreachable-arm report, and the match gets no E0004.
    > **Concern:** An implementer might treat the bad arm as `_` instead of covering nothing, which would report every later arm as unreachable. The row must say "covers nothing", and a corpus row must pin it.

  - **Minimalism:**

    > **Vote:** B.
    > **Reasoning:** A pattern that fails to type-check matches no value. So an unreachable report on any other arm stays true after every fix: there are no false positives, and no true finding waits a cycle. E0004 alone is skipped, because the bad arm's real coverage is unknown. B's rule is the same length as A's.
    > **Concern:** An implementation may treat the bad arm as `_` instead of as matching nothing. That would report every later arm as unreachable, so the spec must say "matches no value" and a test must pin it.

- **Q7b: Which bad arms turn off E0004** (6-0 Y, after 4-2 in round 1)

  - **Systems:**

    > **Vote:** Y
    > **Reasoning:** By §3.5 a guarded arm adds no coverage, so a guarded bad arm cannot change E0004's result under any repair. The E0004 it would suppress is still true after the rename. It is a second, needed repair, not a cascade. The clause follows from the existing guard rule, so it adds nothing new to learn.
    > **Concern:** The clause is easy to drop in the impl. A test with a guarded bad arm that still reports E0004 must exist.

  - **Web/Scripting:**

    > **Vote:** Y
    > **Reasoning:** The same principle as Q7 applies: report a coverage finding only if it stays true after any fix of the bad arm. A guarded arm never adds coverage (§3.5), so the E0004 next to a guarded typo is still true after the rename. Showing it now lets the user fix both in one edit.
    > **Concern:** "Unguarded only" is one more clause to get wrong, so the impl ticket needs a corpus row in which a guarded bad arm still reports E0004.

  - **PLT:**

    > **Vote:** Y
    > **Reasoning:** By §3.5 a guarded arm adds no coverage. A guarded bad arm therefore cannot change E0004's result under any repair, and the E0004 it gets is a true, independent finding, not a cascade. Y only applies the rule users already know for E0004.
    > **Concern:** "Unguarded only" adds a clause the implementation can get wrong, so it needs a test with a guarded bad arm that still reports E0004.

  - **DevOps:**

    > **Vote:** Y
    > **Reasoning:** A guarded arm never counts toward coverage (§3.5). So with a guarded bad arm, the E0004 stays true after any repair of that arm; it is a real second fault, not a cascade. This follows from the same "report only what stays true" rule as my Q7 vote.
    > **Concern:** "Unguarded" is one more condition to get wrong, so the impl ticket needs a test where a guarded bad arm still gets E0004.

  - **AI/ML:**

    > **Vote:** Y
    > **Reasoning:** A guarded arm adds no coverage (§3.5), so a guarded bad arm cannot change the E0004 result under any repair. The E0004 it gets is a true, separate fault (the match needs an unguarded arm), not a cascade. Y lets a model fix both faults in one round, and it applies the existing guard rule instead of adding an exception.
    > **Concern:** "Unguarded only" is one more clause to implement, so it needs a test where a guarded bad arm still reports E0004.

  - **Minimalism:**

    > **Vote:** Y.
    > **Reasoning:** E0004 is skipped only because a fix might make the bad arm cover a variant. A guarded arm never counts toward coverage (§3.5), so the E0004 it gets is a true second fault. Y costs one word and follows from the existing rule.
    > **Concern:** The impl may forget the guard condition, so a test with a guarded bad arm that still reports E0004 is required.

#### AI-First review

- Learnability: pass. One name for one mistake in both positions. `NoSuchVariant` pairs with `NoSuchField`, and the rule for what a bad arm covers is "nothing".
- Consistency: pass. The qualifier, variant lookup and type comparison run in one order in patterns and in values. A different enum is the same `TypeError` as `let t: T = Other.Q(1)`. Guards follow the existing §3.5 rule.
- Generability: pass. The nearest variant is a machine-applicable rename when the payload forms agree. The help never says "add the variant", so a model does not add a wrong variant.
- Debuggability: pass. A bad arm gives one error, with no internal error and no cascade from its binders. `check` and `build` report the same diagnostics. The structured output lists every variant.
- Token efficiency: pass. The terminal list may shorten, and one line names the other enum.

5/5 pass, so the decision is not flagged.

### Final Spec

```blink
type Shape { Circle(Float), Square(Float), Dot }

fn area(s: Shape) -> Float {
    match s {
        Circel(r) => 3.14159 * r * r   // error[NoSuchVariant]
        Shape.Square(w) => w * w
        Shape.Dott => 0.0              // error[NoSuchVariant]
    }
}

type Level { Low, High }

fn main() {
    let x = Level.Hihg     // error[NoSuchVariant]
    let y = x              // no further error: `x` has the poison type
}

fn get(x: Option[Int]) -> Int {
    match x {
        Somee(v) => v      // error[NoSuchVariant]; no E0004 for `Some`
        None => 0          // checked as usual; not unreachable
    }
}

fn get_pos(x: Option[Int]) -> Int {
    match x {
        Somee(v) if v > 0 => v   // error[NoSuchVariant]
        None => 0
    }                            // error[NonExhaustiveMatch]: missing `Some`
}
```

```
error[NoSuchVariant]: `Shape` has no variant `Circel`
  help: did you mean `Circle`?
error[NoSuchVariant]: `Level` has no variant `Hihg`
  help: did you mean `High`?
```

- A variant pattern, or a qualified construction `K.Zed`, `K.Zed(1)` or `K.Zed { .. }`, that names a variant its enum does not declare is `NoSuchVariant` (E0547). It is one code for both positions. The code sits in the name-resolution range next to `NoSuchField` (E0525).
- The same code covers a bare payload pattern on a struct, a tuple or a type parameter ("`Point` is a struct; it has no variants"). A type that is not known yet is `CannotInferType` (E0301). A variant pattern on a builtin scalar stays E0308. A bare name with no payload is still a binding.
- The rule holds at every pattern depth. The span is the variant name. The candidates are the variants of the enum at that position that are visible at the site, including variants that other arms match. Variants of a `pub opaque type` are never listed or suggested outside its module.
- With one suggestion, the rename is machine-applicable only when the payload forms agree (none and unit, `( )` and `( )`, `{ }` and `{ }`). Otherwise the help names the variant and the fix is not machine-applicable. With none, the help lists the declared variants as a plain list. The help never says "add the variant".
- The terminal text may shorten a long list and count the rest; the count line names `--format json` and `blink explain NoSuchVariant`. Structured output lists every variant. The spec states no number.
- When exactly one visible enum declares a bare name, a `note:` names it. The lookup only writes the note; it never changes what the pattern means.
- A qualified pattern `Q.V` is checked in this order, and the first failure is the only error: resolve `Q` (E0507), look up `V` in `Q` (E0547), compare `Q` with the type at the position (E0300). A qualified variant of a different enum (`Other.Q(v)` on `T`) and a struct pattern of a different struct (`Q { y }` on `P`) are E0300. The header names both types, the span is the whole path or type name, and the help lists the variants of the expected type. When that type declares a variant with the same name and payload form, the fix `T.Q` is machine-applicable.
- Binders under a bad pattern, and a binding such as `x` in `let x = K.Zed`, have the poison type (§6.3.5). A bad arm still has its body checked.
- A bad arm covers nothing. It is never treated as `_`. A match with an unguarded bad arm reports no E0004. A guarded bad arm does not turn off E0004. The bad arm gets no unreachable report. Every other check runs, E0005 included, and a valid arm after a bad arm is not unreachable because of it.
- The front end resolves every variant pattern and every `E.V` value, or it reports an error. `check` and `build` report the same diagnostics. A variant that reaches lowering unresolved is an internal compiler error.

Spec: §3.4 *Variant Construction* (*A variant the enum does not declare*), §3.5 *Pattern Forms* and *Exhaustiveness* (*An arm with a bad pattern covers nothing*), §6.3.5 *Error Recovery*. ERROR_CATALOG: E0547 `NoSuchVariant` and the pattern case of E0300 `TypeError`.

### Follow-ups the panel asked for

- Implementation ([the impl ticket]). The panel asked for these tests and checks:
  - A valid arm after a bad arm gets no unreachable report. This pins "covers nothing", not `_`. An unreachable arm after a bad arm is still reported.
  - A guarded bad arm still reports E0004, and an unguarded bad arm does not.
  - A fuzz corpus row of the `tests/test_fuzz.bl` seed 42 shape. The codegen `UnknownVariant` label must never fire for user input.
  - A `check` versus `build` parity test that compares the diagnostics they print on the same error corpus.
  - Value-position tests for `K.Zed`, `K.Zed(1)` and `K.Zed { .. }`, and a test that `x` in `let x = K.Zed` has the poison type.
  - Terminal and JSON output tests, checked on their own terms: the full list in JSON, and the count line in the terminal text that names `--format json`.
  - The note for a name that another enum declares never resolves the pattern: the pattern stays an error.
  - Wrong-struct `Q { y }` on `P`, and nested `Some(Somee(v))`.
  - An explain entry for `NoSuchVariant` in the same change, and the E0547 row reserved in the catalog.
  - The payload-form gate on the machine-applicable fix, defined exactly (unit, paren, brace).
- A warning for a capitalized catch-all binder near a variant name (`Nnoe => 0` binds the whole value and compiles silently). Web and AI/ML raised it. It differs from W1011. It needs its own ticket and, if it is a language change, its own vote.
