[< All Decisions](../DECISIONS.md)

# Field Checks in Struct and Variant Literals — Design Rationale

**Resolution:** the labels of a literal form a set. An unknown label is `NoSuchField` (E0525, widened), a label given twice is `DuplicateField` (E0316), and a field with no default, no label and no `..source` is `MissingField` (E0315). `..source` in a variant brace literal is `VariantSpread` (E0317). Variant fields take no default.

**Vote:** 6-0 on every question (Q1–Q10, Q11a–c). AI-First 5/5 pass.

## The Gap

§2.14 says "Fields without defaults are always required at construction", but the Error Catalog had no name for a literal that leaves out a required field, labels a field the type does not declare, or labels one field twice. The `NoSuchField` row covered field access only. Measured on the compiler at the time (gen1):

| Program | `blink check` | `blink run` / `build` |
|---|---|---|
| `Point { x: 1.0, y: 2.0, bogus: 2.0 }` | ok | `bogus` dropped without a word |
| `Point { x: 1.0 }` (`y` has no default) | ok | `internal compiler error[StructLiteralFieldMissing]` |
| `Point { x: 1.0, x: 3.0, y: 2.0 }` | ok | the first `x` wins |
| `Shape.Rect { width: 1.0 }` | ok | `internal compiler error[VariantLiteralFieldMissing]` |
| `Shape.Circle(radius: 1.0, radius: 2.0)` against `Circle(radius: Float, tag: Int)` | ok; `tag` missing | — |
| `Shape.Rect { width: 1.0, ..s }` | ok | ICE in code generation |
| `Cfg { bogus: 2, ..a }` | ok | `bogus` dropped |
| `Shape.Circle(radius: 1.0, bogus: 2)` | `error[NoSuchField]` | — |

§3.4 also said "The `..` rest sigil is a pattern-only construct (§3.5); it has no meaning in construction, where every field must be supplied (or defaulted, see *Product Types*)". That disagrees with §2.16 copy-update, and the parser rejects a default on a variant field.

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in independent-proposal → debate → vote rounds. All six proposed the same three names on their own in Phase A.

#### Phase A — Independent proposals (excerpts)

- **Systems:**

  > **My stance.** Every one of these checks is a compile-time set comparison. It costs a bitset per literal and nothing at run time. What we have today is the worst result a systems person can get. One case is an ICE in `cg_expr.bl`, which is a rule enforced only at codegen and breaks §3.1 rule 2. The other cases drop a field without a word, or let the first `x:` win. With "first wins", does the second `x:` expression even run? If it has a side effect, the reader cannot tell from the source. All of these must be hard errors in `blink check`, not warnings.

- **Web/Scripting:**

  > **Position.** Whether you are a Python, TypeScript or Kotlin developer, you already know these three errors from your own tools. Blink should give the same three answers, with the same words, for every way a literal is written. Today the user gets silence, a value dropped without a word, or an ICE. That is the worst outcome for developer experience, because the bug shows up at run time or as a crash in the compiler.

- **PLT:**

  > A record literal checks its written labels against the declared fields. Let T declare fields F, with defaulted subset D ⊆ F. A literal writes the label multiset L, plus an optional spread `..s`:
  >
  > 1. L is a set. Fails with **DuplicateField**.
  > 2. L ⊆ F. Fails with **NoSuchField**.
  > 3. With no spread, F \ D ⊆ L. Fails with **MissingField**. With a spread, `s : T`, and T must be a struct (see P3).
  > 4. For each ℓ ∈ L, `e_ℓ : F(ℓ)`. The existing type errors cover this.
  >
  > Elaboration: an omitted field takes `s.f` if a spread is present, otherwise its default. This is §2.16's precedence. An explicit label beside `..s` is shadowing, not duplication. Only two explicit labels collide.

- **DevOps:**

  > I measured one more fact. `Shape.Circle(radius: 1.0, radius: 2.0)` against `Circle(radius: Float, tag: Int)` passes `blink check`. The arity matches, the duplicate goes unseen, and `tag` is missing with no error. The paren form has the same gap, not just the brace forms. `Shape.Circle(radius: 1.0, tagg: 2)` reports NoSuchField but gives no suggestion, although `tag` is the obvious fix.

- **AI/ML:**

  > Today an agent that writes `Point { x: 1.0, bogus: 2.0 }` gets a clean `blink check`. That is the worst outcome for a generate-check-fix loop. The agent believes the code is correct, so it never tries to fix it. The error shows up later as a runtime ICE, or as silently dropped data. LLMs make these exact mistakes all the time: a field name half-remembered from another library (`colour` for `color`), a forgotten new field after a struct grows, or a field written twice when merging two snippets. All three must be `blink check` errors (§3.1 rule 2). Each one needs a diagnostic that names the repair in one round trip.

- **Minimalism:**

  > **Position:** We cannot skip this one. §2.14 already makes the rule, and §3.1 rule 2 says `blink check` must see every typing rule. Today codegen catches a missing field as an ICE, which breaks the spec. So the question is how small the fix can be.
  >
  > My answer: widen one catalog row, add two names, and add no new concepts.

#### Phase B — Debate highlights

- **AI/ML** withdrew the `todo()` machine fix: "I withdraw `todo()`. No machine-applicable fix. Sys and Min convinced me … In a fix loop, the agent applies the fixes, `blink check` goes green, and the agent stops. An inserted `todo()` makes the loop end green on a program that panics."
- **Systems** on why a constructor `todo()` differs from a match-arm `todo()`: "A `todo()` in a match arm panics only when the program reaches that case. A `todo()` in a constructor panics **every time that line runs**."
- **Minimalism** withdrew "reword only" for `..` on a variant: "I withdraw 'reword only'. A rewording without a diagnostic leaves the ICE in place. … I accept PLT's **`VariantSpread`**."
- **Minimalism** on the ownership condition: "My Phase A help line broke §3.1 rule 1 for a type from a dependency. My mistake. Offer 'give it a default' only when the declaration is in the user's package."
- **PLT** held round 1 open on variant defaults *(the only NOT STABLE signal)*: "The Min and AI/ML rewordings keep 'supplied or defaulted', and that sentence would then be newly voted text promising a feature that no decision added and that the parser rejects." Systems, AI/ML, DevOps and Minimalism joined. **Web/Scripting:** "until variant defaults parse, the `MissingField` help on a variant never offers 'give it a default' … Min's and AI/ML's §3.4 wording should say 'supplied'."
- **PLT** on convergence: "what makes `yy`/`y` converge is the **suppression clause**, not the report order. Order alone still leaves two repairs, and applying both gives a DuplicateField."
- **DevOps** on why the order must be stated: "MissingField's span is the type name, which comes first in the source, so a sort by position would print it first. The first repair the user saw would then be the wrong one."
- **PLT** and **AI/ML** moved on struct patterns between Phase B and Phase C. **PLT:** "I change my vote from my round-1 position. Min and Web are right that a catalog row is a normative claim."

#### Phase C — Final vote

Each panelist voted alone on a written ballot. Every option on the ballot came from a panelist's own text.

- **Q1** Core option — **A adopt** (6-0)
- **Q2** Machine fix for `MissingField` — **A none** (6-0)
- **Q3** Labelled variant paren payload — **A in scope; a positional payload keeps the arity error plus a note** (6-0)
- **Q4** `..source` in a variant brace literal — **A `VariantSpread`** (6-0)
- **Q5** Variant field defaults — **A none; strike "(or defaulted)"; separate spec question** (6-0)
- **Q6** §3.4 sentence — **A "Variant construction does not accept `..source`; copy-update (§2.16) applies to struct literals only. Every variant field must be supplied."** (6-0)
- **Q7** Help that edits the declaration — **A only for a type declared in the package being compiled** (6-0)
- **Q8** Report order — **A `DuplicateField`, `NoSuchField`, `MissingField`** (6-0)
- **Q9** Struct patterns — **A the row names literals only now** (6-0)
- **Q10** Nearest-name rule — **A one general *Conventions* rule** (6-0)
- **Q11a** With no suggestion, list the declared fields — **Yes** (6-0); **Q11b** a shorthand diagnostic names the inferred type and the parameter — **Yes** (6-0); **Q11c** source order inside each kind — **Yes** (6-0)

Ballots, verbatim:

##### Systems

**Q1: A (adopt the core option).**
Reasoning: Each check compares field sets in typecheck, using a bitset per literal, so it costs nothing at run time. It replaces two codegen ICEs and three silent drops with errors in `blink check`. Codegen keeps its rule that every slot is filled, and typecheck now proves that rule instead of codegen asserting it.
Concern: The rule that leaves a field out of MissingField when a typo names it couples two checks. If someone writes them as separate passes, the coupling can break and §3.1 rule 3 fails again with no one noticing, so the golden tests must cover the `yy`/`y` case.

**Q2: A (no machine-applicable fix).**
Reasoning: A `todo()` in a constructor panics every time that line runs, not only on a rare path. It also turns `blink check` green. A fix that moves a compile error to a run-time panic on the hot path is the opposite of what a systems user wants from the tool.
Concern: The manual LSP action may later be promoted into `blink fix` by mistake, so the catalog row should state that MissingField has no machine-applicable fix.

**Q3: A (labelled paren payload in scope).**
Reasoning: `Circle(radius: 1.0, radius: 2.0)` passes check today with `tag` missing, which is a silent wrong value in the stored layout. Checking that the field sets are equal is the correct rule, while an argument count is only a proxy for it.
Concern: A payload that mixes positional and labelled arguments falls between the two branches, so the implementation must define where that case goes and test it.

**Q4: A (`VariantSpread`).**
Reasoning: A variant spread would need a run-time tag check, with a panic or a fallback, inside an expression that looks like a plain copy. A dedicated name lets the help name the real repair, which is `match` first. A widened type-mismatch row would be false, because `s: Shape` has the correct type.
Concern: If a variant-typed value (a refined `Shape.Rect` type) arrives later, this name must stay correct and not be repurposed, because names are frozen.

**Q5: A (no variant defaults; strike the parenthetical).**
Reasoning: Each variant then has a fixed set of fields, so construction, patterns and exhaustiveness never have to consider defaults. The parser already behaves this way, and the spec text should not promise a feature that no decision added.
Concern: Someone will later ask for variant defaults for API evolution (as with struct defaults in §2.14), and the `type:spec` ticket must weigh that need honestly.

**Q6: A ("Variant construction does not accept `..source`; copy-update (§2.16) applies to struct literals only. Every variant field must be supplied.").**
Reasoning: This text states the prohibition, the scope and the requirement directly, so a reader does not have to infer the variant case from what the text leaves out. B is shorter, but it leaves "every field must be supplied" implicit for variants.
Concern: There is some overlap with §2.16's own rules, and the two texts can drift apart if only one of them is edited later.

**Q7: A (offer the second repair only for types in the package being compiled).**
Reasoning: This is §3.1 rule 1 as written. Telling a user to edit a dependency's declaration prescribes a repair they cannot make.
Concern: "The package being compiled" needs a precise definition for workspaces and path dependencies, or the help line will differ between the CLI and the LSP.

**Q8: A (DuplicateField, then NoSuchField, then MissingField).**
Reasoning: A fixed order makes the output deterministic. It also puts the repairs that can clear other errors first, and it stops a sort by position from printing MissingField (whose span is the type name) first.
Concern: None of substance.

**Q9: A (literals only now).**
Reasoning: The catalog row must not name a check that no decision has defined. The pattern judgment has a different shape: under §3.5, `..` means "ignore", so its missing-field rule is its own question.
Concern: The pattern ticket may slip, and the pattern ICE stays live until it ships, so the moderator should file that ticket at P1.

**Q10: A (one general nearest-name convention).**
Reasoning: Four or more rows use one rule. Defining it once means the compiler, the LSP and `blink explain` share one implementation and give one answer.
Concern: The move must change no words that affect behavior, or E0842 output changes without a decision.

**Q11a: Yes.** The full field list in one diagnostic saves a lookup round. The cost is help text only.
**Q11b: Yes.** The type is already resolved at that point, so the extra text costs nothing. Without it, the user cannot see which type the compiler checked against.
**Q11c: Yes.** Source order applies within each kind, under the fixed order of kinds in Q8, and it keeps goldens stable.

##### Web/Scripting

**Q1 (core option): A, adopt.**
Reasoning: Six panelists reached the same three plain-English names independently, which is the strongest learnability signal we can get. Each name matches what the user wrote ("field") and has one repair, and the Rust, TS and Kotlin crowds will recognise every one.
Concern: The convergence suppression may hide a real missing field behind a wrong guess for one round. Users may then read the second error as a regression the fix caused.

**Q2 (machine fix for MissingField): A, none.**
Reasoning: A `todo()` turns a red `blink check` into a green one that panics every time the line runs. That is the "passes check, fails later" pattern this ticket removes. A manual LSP action keeps the convenience without lying to the user.
Concern: Users coming from IDEs that auto-fill fields may find `blink fix` weaker than they expect, unless the LSP action actually ships.

**Q3 (labelled variant paren payload): A, in scope.**
Reasoning: "Same mistake, same error" is the 5-minute rule. "Missing field `tag` (Int)" tells the user what to type, while "expects 2, got 1" makes them go count. DevOps showed the paren form already passes check with a field missing.
Concern: The boundary between a fully labelled payload and a positional one must be crisp. A mixed payload must land in exactly one bucket, or users will see different errors for near-identical calls.

**Q4 (`..src` in a variant literal): A, VariantSpread.**
Reasoning: The value has the right type and the wrong form. A type-mismatch name would send a JS or TS developer off to retype `s`, which is a guaranteed Stack Overflow question. A dedicated name with "write every field, or match on `s`" answers the question the user actually has.
Concern: Developers used to JS object spread will try this often. The help must show the match form concretely, not just name it.

**Q5 (variant field defaults): A, strike "(or defaulted)".**
Reasoning: The spec should not promise a feature the parser rejects and no decision added. Users and models copy what the spec shows. Variant defaults can come back through their own `type:spec` ticket if anyone asks.
Concern: Someone who already read the old §3.4 may file it as a regression, so the changelog should say so plainly.

**Q6 (§3.4 sentence): A, Min's full sentence.**
Reasoning: It says both halves out loud: variants reject `..`, and structs keep copy-update. A reader who lands on §3.4 alone does not have to cross-reference §2.16 to learn that `..` is fine on structs. Explicit beats terse for a reader in a hurry.
Concern: It repeats §2.16 a little, so a later edit to one section could drift from the other.

**Q7 (second repair in help): A, only for a type declared in the package being compiled.**
Reasoning: Telling a user to edit `std` or a vendored dependency is a repair they cannot make (§3.1 rule 1), and it wastes their time. The condition is easy to state and easy to test.
Concern: In a multi-package workspace, a user may own a sibling package and wonder why the help leaves the edit out. The definition of "this package" may need refining later.

**Q8 (report order): A, Duplicate, then NoSuchField, then Missing, fixed.**
Reasoning: Deterministic output matters for goldens, for agents and for a human who fixes only the first error. This order puts first the errors whose repairs can clear the others.
Concern: Within one literal the output no longer follows source position. A user who reads top to bottom may find that odd, but it is minor.

**Q9 (struct patterns): A, literals only now.**
Reasoning: The catalog should never promise a check that no rule defines and the compiler does not run. The pattern ticket can widen the row when it ships.
Concern: Until that ticket lands, a pattern with a bogus field still ICEs at check, so the ticket needs a real priority.

**Q10 (nearest-name rule): A, a general Conventions rule.**
Reasoning: Four rows now use it. One named rule means the compiler, the LSP and `blink explain` give the same suggestion. The meaning does not change.
Concern: Someone may later tune the rule for one diagnostic and silently change all the others.

**Q11a (list declared fields when there is no suggestion): Yes.**
Reasoning: It answers the user's next question ("so what *are* the fields?") without making them open the declaration.
Concern: For a type with many fields, the help gets long, so the implementation should trim it.

**Q11b (shorthand message names the inferred type and parameter): Yes.**
Reasoning: With the shorthand the type is invisible at the call site. Without the name, "missing field `host`" is a puzzle.
Concern: The message gets long. Keep it to one line.

**Q11c (source order inside each kind): Yes.**
Reasoning: It costs nothing, it makes the output stable and readable, and it works together with Q8.
Concern: None worth noting.

##### PLT

**Q1: A (adopt).**
Reasoning: The core option is one judgment over every brace form: labels form a set, labels ⊆ F, and F \ D ⊆ labels unless `..src` is present. Each failure gets one name with one repair. The suppression clause makes `yy`/`y` converge under §3.1 rule 3. The check runs at typecheck, which closes the §3.1 rule 2 breach.
Concern: An implementation might put the three checks in separate passes and lose the coupling between the suppression clause and the candidate set, so the convergence rule needs a test of its own.

**Q2: A (no machine fix).**
Reasoning: `todo()` has type `Never`, so it inhabits every field type. That is why it type-checks, and also why it is not a repair: it trades a static error for a panic every time the literal runs. A catalog fix must keep the program's meaning or refuse.
Concern: Agents may treat the manual LSP action as automatic and insert placeholders anyway, which is outside what this decision can control.

**Q3: A (in scope).**
Reasoning: A labelled payload is a record literal written with parentheses. The invariant is set equality, not count, and DevOps's `Circle(radius: 1.0, radius: 2.0)` shows that a count check is unsound. With D = ∅ for variants, MissingField is exact.
Concern: A mixed payload with some arguments labelled and some not is not named in the option. The implementation must pick one rule for it (I read "all labelled" strictly, so mixed keeps arity) and test it.

**Q4: A (`VariantSpread`).**
Reasoning: The typing rule needs `s : T`, where T is the literal's nominal type. `Shape.Rect` is not a type and `s : Shape` is well typed, so this is not a type mismatch. The fault is the form, and it needs a name whose repair matches.
Concern: If variant-refined types are ever added, this name's explain text will need care so that it does not read as permanently forbidding the form.

**Q5: A (no variant defaults; strike the parenthetical).**
Reasoning: With D = ∅, every variant has a fixed field set, so patterns and exhaustiveness never have to reason about defaults. The struck text described a feature that no decision added. The judgment extends to D ≠ ∅ unchanged if a later spec ticket wants defaults.
Concern: Someone may read the strike as a ban rather than "not yet decided", so the rationale should say it is deferred.

**Q6: A (Min's full sentence).**
Reasoning: Once the parenthetical is struck (Q5), the sentence must state both halves plainly: `..` is struct-only, and every variant field is supplied. Option A does this in one place. My B replaced only the clause about `..` and leaves the "supplied" half implied by the surrounding text.
Concern: None material. It needs a cross-check that §2.16's own text also says "struct literals only".

**Q7: A (ownership condition).**
Reasoning: §3.1 rule 1 is about repairs this user can make. Editing a dependency's declaration is not one, and the same holds for "add the field to `T`".
Concern: "The package being compiled" needs a precise definition for workspaces with several packages. The implementation should use the same notion the other ownership-gated helps use.

**Q8: A (Duplicate → NoSuchField → Missing).**
Reasoning: The order is presentation, not soundness, because convergence comes from spans plus suppression. But a fixed total order makes output deterministic, and putting MissingField last means the reader sees the repair that can remove entries from its list first.
Concern: A tool that sorts diagnostics by position (MissingField's span comes first in the source) would reverse this unless the order is part of the catalog text.

**Q9: A (row names literals only now).**
Reasoning: I change my vote from my round-1 position. Min and Web are right that a catalog row is a normative claim. Widening it to patterns before any decision defines the pattern check promises a judgment that does not exist yet. The pattern ticket will widen the row together with its rule.
Concern: The pattern ICE (`Point { x, bogus }`) and the missing-`..` hole (`Point { x }` passes check) stay live until that ticket ships, so it needs a filed ticket, not only a note.

**Q10: A (general Conventions rule).**
Reasoning: Several rows now share one algorithm. Defining it once is the only way to guarantee that the compiler, the LSP and `blink explain` give the same suggestion.
Concern: The move must be word for word, so that E0842's behaviour does not shift in the edit.

**Q11a: Yes.** When there is no suggestion, the full field set is the next fact the user needs. It is presentation only.
**Q11b: Yes.** The diagnostic must show the elaborated type, which is the type the judgment ran against.
**Q11c: Yes.** Source order inside each kind completes the total order from Q8, so the output is deterministic.

##### DevOps

**Q1: A (adopt).**
Reasoning: There is one name for each repair, the check runs in typecheck, and the suppression clause means a typo shows one error, not a pair. The LSP, `blink explain` and agents can all map each name to exactly one code action.
Concern: Implementers may wire the suppression clause to the report order and not to the suggestion. Then `yy`/`y` emits both errors and the convergence is lost. The tests must cover the `yy` case directly.

**Q2: A (none).**
Reasoning: A catalog fix runs with no user present. If it inserts `todo()`, `blink check` goes green, and the error moves to a panic each time the literal runs. A manual LSP "fill fields" action is safe, because a person or an agent still types every value.
Concern: Some editors offer every LSP code action in a "fix all" batch. The "fill fields" action must therefore not use the quickfix kind that "fix all" applies.

**Q3: A (in scope).**
Reasoning: I measured that `Shape.Circle(radius: 1.0, radius: 2.0)` passes check with `tag` missing. An arity count is the wrong check, and "missing field `tag` (Int)" tells the user what to type. The positional note gives the field names that the count message never showed.
Concern: Mixed payloads, with some arguments labelled and some positional, fall between the two rules. The implementation needs one clear rule for them, such as "any label present means the label rules apply", or the output will be the old arity error again.

**Q4: A (VariantSpread).**
Reasoning: `s: Shape` has the right type, so a type-mismatch name would point the user, the LSP and an agent at the wrong repair. A dedicated name gets `blink explain` text that matches its one repair.
Concern: If a later `type:spec` ticket adds variant-typed values, this name may need new help text. The name itself stays frozen, so the help must not claim more than "not in v1".

**Q5: A (no variant defaults now).**
Reasoning: If the spec keeps "or defaulted", the MissingField help for a variant would offer a repair the parser rejects, which breaks §3.1 rule 1. Striking the parenthetical makes the help truthful, and variant defaults can come later through their own ticket.
Concern: Users who read the old §3.4 text may already expect variant defaults. The parse error they get should say that variant fields take no default, and not give a generic token error.

**Q6: A (Min's full sentence, minus "or defaulted").**
Reasoning: The sentence states the VariantSpread rule and the supply rule directly, so the explain text and the error-catalog row can cite §3.4 word for word. B replaces only one clause and leaves the reader to put the two halves together.
Concern: The text is now stated in two places, §3.4 and §2.16. The editor must keep the two in step, or the old conflict comes back.

**Q7: A (ownership condition).**
Reasoning: To tell a user to edit `std` or a dependency is to prescribe a repair that does not exist for them (§3.1 rule 1). The rule "declared in the package being compiled" is simple, and the LSP can apply it the same way.
Concern: Workspaces and path dependencies blur what "the package being compiled" means. Define it as "the package whose sources are being compiled", and test it with a path dependency.

**Q8: A (Duplicate, NoSuchField, Missing).**
Reasoning: MissingField's span is the type name, so a sort by position alone would print it first, and the user would act on the wrong error. A fixed total order also keeps golden output stable.
Concern: The LSP shows diagnostics by range, not in emit order. The convergence must therefore come from suppression, as PLT says, and the order exists only for the CLI.

**Q9: A (literals only now).**
Reasoning: A catalog row that names a check no compiler runs sends `blink explain` users to the wrong place. The pattern ticket can widen the row when its check ships.
Concern: The pattern ticket may sit unworked, and the pattern ICE stays meanwhile. Give it a priority that matches the other ICE bugs.

**Q10: A (move to general *Conventions*).**
Reasoning: Four rows now suggest a nearest name, and one shared paragraph makes the compiler, the LSP and explain produce the same suggestion. The move is editorial, and the meaning does not change.
Concern: An editor may drop the clause "never suggest a retired name" when the paragraph moves. That clause applies only to the diagnostic-name rows, so it must stay with E0842.

**Q11a: Yes.** It gives the full field set in one diagnostic, so the user needs no lookup.
**Q11b: Yes.** An inferred type that does not appear in the source must appear in the error, or the user cannot read the error.
**Q11c: Yes.** Source order inside each kind keeps golden output and diffs stable, at no cost.

##### AI/ML

**Q1. Core option: A (adopt).**
Reasoning: Six panelists reached the same three names, one fix per name, on their own. That layout is also the Rust split that models have seen most in training, so an agent can learn it with almost no new decision points. Every case it covers passes `blink check` today, so each one becomes an error an agent can catch before it runs the code.
Concern: The rule that drops a field from `MissingField` when a suggestion claims it may be implemented as a filter applied after both diagnostics are built. If that filter misses a case, agents will see the two-error noise pair again.

**Q2. Machine fix for `MissingField`: A (none).**
Reasoning: An inserted `todo()` makes `blink check` pass, so the fix loop stops on a program that panics every time it builds the value. That is the same "passes check, fails later" outcome this ticket exists to remove. Sys's point decided it for me: a literal runs every time its line runs, but a match arm does not.
Concern: Help text that shows a placeholder such as `y: <Float>` may be copied into the code word for word by a weak agent. The placeholder must never parse as valid Blink.

**Q3. Labelled variant paren payload: A (in scope).**
Reasoning: "missing field `tag` (Int)" is a repair in one edit. "expects 2, got 1" forces the agent to look up the declaration first. DevOps measured `Circle(radius: 1.0, radius: 2.0)` passing check, a silent bug of the same kind as the brace form.
Concern: A payload that mixes labelled and positional arguments has to fall clearly to one side of the line. Otherwise agents get different diagnostics for code that is almost the same.

**Q4. `..src` in a variant brace literal: A (`VariantSpread`).**
Reasoning: A dedicated name maps to one repair. If this case shared a type-mismatch name, an agent would try to change the type of `s`, which is already correct. The pointer to §2.16 tells the agent where spread is legal.
Concern: Agents that know Rust's struct-update syntax will keep writing this form. The help line has to show the `match` rewrite clearly enough to fix it in one pass.

**Q5. Variant field defaults: A (strike the parenthetical).**
Reasoning: Models learn from spec text. A sentence that promises defaults the parser rejects will produce code that does not parse. Striking it removes a decision point and adds no rule.
Concern: A later ticket for variant defaults may forget to restore the help branch "give it a default" for variants.

**Q6. Text of the §3.4 sentence: A.**
Reasoning: The sentence states the ban where variant construction is described and states where `..` is allowed. An agent that reads only §3.4 gets both facts. Version B depends on the reader knowing the context, and a model retrieving one passage may not have it.
Concern: §2.16 must also say "struct literals only", so the two sections cannot drift apart again.

**Q7. Second repair in help lines: A (only when the user's own package declares the type).**
Reasoning: Without this condition, an agent is told to edit a dependency or `std`. That repair does not really exist (§3.1 rule 1), and the agent may try to vendor-patch the code.
Concern: The meaning of "package being compiled" for a path dependency in a workspace must be defined, or the LSP and the CLI will disagree.

**Q8. Report order: A (`DuplicateField`, then `NoSuchField`, then `MissingField`, fixed).**
Reasoning: A fixed order makes the output the same on every run, which goldens and agents need. DevOps showed that sorting by position would put `MissingField`, anchored at the type name, first. Agents act on the first error they read.
Concern: Agents may take the order as a priority between literals, when it only orders the diagnostics within one literal.

**Q9. Struct patterns: A (row names literals only now).**
I change from "harmless". Web and Min are right: models read the catalog as fact. A row that names a check no compiler performs teaches agents to expect a diagnostic that never fires.
Concern: The struct-pattern ticket may stall, and the pattern ICE stays in place until it lands.

**Q10. Nearest-name rule: A (general Conventions rule).**
Reasoning: One rule that four rows cite gives the same suggestion in the compiler, the LSP and `blink explain`. Rows citing "the E0842 rule" read as if the rule were specific to E0842.
Concern: The rule should not drift during the move. It has to be a straight text move, with no editing of the threshold.

**Q11a: Yes.** The full field list in one diagnostic saves the agent a lookup round.
**Q11b: Yes.** An agent cannot see an inferred type. Naming the type and the parameter makes the error fixable without reading the signature.
**Q11c: Yes.** Source order inside each kind keeps the output the same on every run.

##### Minimalism

**Q1 — Core option: A (adopt).**
Reasoning: Three rules, two new names and one widened row are the smallest set that meets §3.1 rules 1 to 3. Six panelists reached it independently, which is strong evidence it is the minimum, not a compromise. Every rejected program here passes `blink check` today, so the cost buys real errors and no new syntax.
Concern: Two new frozen names will be hard to rename later if pattern checks (Q9 ticket) want a slightly different wording of "missing".

**Q2 — MissingField fix: A (none).**
Reasoning: A fix that has to invent a value is not a repair. `todo()` moves the error to run time on every execution of the literal, which is the bug this ticket removes. The manual LSP action is editor surface, not language surface, so it costs the catalog nothing.
Concern: Tool authors may read "no catalog fix" as "no editor help" and skip the manual action.

**Q3 — Labelled variant paren payload: A (in scope).**
Reasoning: DevOps measured the same silent-missing-field bug in the paren form. Deciding it separately would mean two decisions for one judgment. Reusing the same three names adds no surface at all.
Concern: The line between "all labelled" and "positional" needs a precise rule for a mixed payload, so that the implementer does not have to invent one.

**Q4 — `..src` in a variant literal: A (`VariantSpread`).**
Reasoning: It ICEs today, so it needs a check-time name. No spread row exists to widen. `TypeError` names the wrong fact (`s: Shape` is the right type) and implies the wrong repair, which costs more than one rare row.
Concern: The name is used rarely, so its explain text may decay. Keep it short and point at §2.16.

**Q5 — Variant defaults: A (strike; separate ticket if wanted).**
Reasoning: This is subtraction. The spec stops promising a feature that no decision added and the parser rejects. If someone needs defaults, the core judgment already extends to them with D ≠ ∅.
Concern: An existing example or doc may rely on "or defaulted". Sweep sections/ for it when the edit lands.

**Q6 — §3.4 text: A.**
Reasoning: It states both halves (no `..` in variant construction, and every field supplied) in plain words. That stops a reader, human or model, from carrying `..src` across from §2.16. Text B leaves "supplied" implicit.
Concern: The first clause repeats §2.16, and the two texts could drift. §2.16 should say "struct literals only" in the same words.

**Q7 — Second repair: A (only for the package being compiled).**
Reasoning: My Phase A wording broke §3.1 rule 1. A repair the user cannot make must not be offered.
Concern: "Package being compiled" needs one definition for workspaces and path dependencies. Otherwise the compiler and the LSP will disagree.

**Q8 — Order: A (Duplicate, NoSuchField, Missing).**
Reasoning: Convergence needs only NoSuchField before MissingField. A fixed total order costs nothing and gives the same output every run, for goldens and agents.
Concern: None material. DevOps is right that it must be stated, because a span sort would otherwise print MissingField first.

**Q9 — Struct patterns: A (literals only now).**
Reasoning: The catalog should not promise a check that no decision defines. The pattern side needs its own missing-field rule under §3.5, so the ticket that decides it widens the row.
Concern: The pattern ticket may sit unclaimed, and the pattern ICE PLT found stays live. File it with a priority.

**Q10 — Nearest-name rule: A (general Conventions rule).**
Reasoning: Four rows already use it. One rule cited by each is less text than four rows pointing at E0842, and it changes no meaning.
Concern: The move must stay word-for-word, or it will become a quiet change to E0842's behaviour.

**Q11a: Yes.** This is help text only, and it saves a lookup. Trim it for wide types at the implementer's discretion.
**Q11b: Yes.** The type is already resolved, so it costs nothing. Without it, the shorthand error cannot be read.
**Q11c: Yes.** It makes output deterministic at zero cost.

### Final Spec

```blink
type Point {
    x: Float
    y: Float
}

let a = Point { x: 1.0 }                   // MissingField: y (Float)
let b = Point { x: 1.0, y: 2.0, z: 3.0 }   // NoSuchField: z
let c = Point { x: 1.0, x: 3.0, y: 2.0 }   // DuplicateField: x
let d = Point { x: 1.0, yy: 2.0 }          // one NoSuchField, help `y`; no MissingField
```

- One rule for struct literals, qualified and bare variant brace literals, all-labelled variant paren payloads, copy-update and the §2.15 shorthand. `blink check` reports it.
- `MissingField` (E0315): one per literal, at the type or variant name, each field and type in declaration order. No machine fix.
- `DuplicateField` (E0316): at the second label, note at the first, with or without `..source`. No machine fix.
- `NoSuchField` (E0525): the candidates are the declared fields not yet labelled. One suggestion gives a machine-applicable rename; none lists the fields.
- A missing field that is the unique suggestion of an unknown label leaves the `MissingField` list.
- Order: `DuplicateField`, `NoSuchField`, `MissingField`; source order inside each kind.
- A help that edits the declaration appears only for a type declared in the package being compiled.
- `VariantSpread` (E0317): `..source` in a variant brace literal. Variant fields take no default.
- A positional variant paren payload keeps the arity `TypeError`, with a note that lists the fields.
- The nearest-name rule lives once, in ERROR_CATALOG *Conventions*.
- Not decided here: struct-pattern field checks, variant field defaults, the diagnostic for an ambiguous §2.15 shorthand.
