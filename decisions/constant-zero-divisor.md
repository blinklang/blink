[< All Decisions](../DECISIONS.md)

# Constant Zero Divisor — Design Rationale

**Gap:** "Today 'let x = 7 % 0' compiles and panics at run time. Must handle the §2.20 example 'assert_panics { let _ = 10 / 0 }'. Sys and PLT lean yes, Min leans no (a lint can add it without a spec change; removing an error later breaks code). §3.2's constant-expression check covers overflow only. See decisions/remainder-by-zero.md Q2."

A sibling ticket asked for one general warning for literal operations that always panic: `10 / 0`, `10 % 0`, and an empty literal range passed to a range-taking API ([Random Stdlib Module](random-stdlib-module.md) Q7c). This panel took the `/` and `%` part of it.

**Result:**

- **Q1 (6-0, C-err):** in the four const contexts of §2.21, a const expression whose evaluation would panic is the compile error `ConstEvalPanic` (E0546). "Const evaluation must succeed" covers `/`, `%`, signed `MIN / -1`, and overflow.
- **Q2 (6-0, E-warn):** outside a const context, a known-zero divisor is not a compile error. The expression panics at run time and gets a warning.
- **V1 (6-0, (b)):** the warning fires when the divisor is an integer literal 0, with optional parentheses and unary `-`. It does not follow `const` references or `let` bindings.
- **V2 (6-0, (a)):** the spec says that the warning does not fire inside an `assert_panics` body. The rule belongs to this warning only.
- **V4 (6-0):** the warning fires in a branch that never runs. There is no flow analysis.
- **Q3 (6-0, S-split):** this decision settles `/` and `%`. Empty literal ranges are out of scope.
- **N1 (6-0):** the name is specific to zero divisors.
- **N2:** the name is `DivisionByLiteralZero` (W0704). Phase C tied 3-3; Phase D gave 5-1 (Web dissent, for `LiteralZeroDivisor`).
- **Q3-R:** the record does not choose a mechanism for empty ranges (r2: 4-2 in Phase C, 6-0 in Phase D). The wording is DevOps's, 4-2 after the runoff (Sys and Min ranked Min's wording first).
- **S1, S2, S3 (6-0 each):**
  - S1: §3.2 says that a zero divisor is not overflow.
  - S2: a follow-up ticket on what "constant expression" means in a `let` initializer.
  - S3: a codegen chore, so a known-zero divisor never lowers to C `x / 0`.

**AI-first review:** 4/5 pass. Consistency fails because the `assert_panics` rule is the first block-scoped rule of any warning. The panel limited it to this warning.

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in independent-proposal → debate → vote rounds. Each panelist's text below is a verbatim excerpt.

#### Phase A — Independent proposals

- **Systems:**

> **S1a. Const contexts: a panic during evaluation is a compile error.**
>
> Spec text for §2.21: "Evaluating a const expression must not panic. A zero divisor in `/` or `%`, or an overflow, makes the program ill-formed."
>
> ```blink
> const SHARDS = 0
> const PER_SHARD = 1024 / SHARDS
> // error[ConstEvalPanic]: this const expression divides by zero
> //   --> cfg.bl:2:19
> //   = note: `SHARDS` is 0 (cfg.bl:1)
> ```

- **Web/Scripting:**

> ## Proposal W1: a warning, not an error, for a known-zero divisor in normal code
>
> A JS or Python dev learns `/ 0` as "this blows up when it runs". A warning tells them "this line will blow up" and lets them run the program. An error stops them while they are still writing code, often in a branch they are about to delete. The 90% case is a typo or a placeholder. A loud warning fixes that case. The rare user who wants a hard stop can upgrade it in blink.toml.

- **PLT:**

> **Thesis: a failure belongs to the phase that does the evaluation.** In a const context the compiler does the evaluation, so a failure there is a compile error. In a runtime expression the program does the evaluation, so a failure there is a runtime panic. A warning may report a panic that is certain to happen. This one rule settles both tickets and does not depend on what a "literal" is.
>
> I change my earlier position. In the remainder-by-zero debate I said "a compile error makes fewer programs well-formed." That is true, but it does not make the language more sound. Soundness means a well-typed program does not go wrong. A panic is a defined outcome here, not "going wrong". `10 / 0` has type `Int` for the same reason that `panic("x")` has a type. So rejecting `10 / 0` in a runtime expression adds no soundness. It only adds a check that ignores reachability.

- **DevOps:**

> I judge this by what the user sees. When a check is wrong in an error, the build stops. When a check is wrong in a warning, the user sees noise. When a check is missing, the program panics in production. Expression position and `const` position are different cases, so I give them different answers.
>
> ## D1. Expression position: a warning named `AlwaysPanics`, for literals only

- **AI/ML:**

> ## Proposal A1: a warning in expression position, an error in `const` contexts
>
> **Rule 1: expression position gets a warning.** Take an integer `/` or `%` whose divisor is a const expression (§2.21) that evaluates to 0. The compiler emits the warning **W0704 `CertainPanic`**. The divisor is a const expression when it is made of literals, operators and `const` refs. The check never folds through `let`. Inside an `assert_panics` body, the warning does not fire.

- **Minimalism:**

> ### M1: In `let` and expression position, a zero divisor is not a compile error (first choice)
>
> Add one sentence to §3.6 *Integer Division*:
>
> > A divisor that is known at compile time to be 0 is not a compile error outside a const context (§2.21). The expression panics at run time like any other zero divisor.

#### Phase B — Debate highlights

The dedupe left more than two options, so Phase B ran. All six sent `STABLE: yes` after round 1.

- **Minimalism:**

> **Q2: I change from E-none to E-warn.**
> The strongest argument against my M1+M3 came from DevOps and from one fact I missed. A warning is not "tooling with no spec text." Its name is a `[lints]` key and an `@allow` argument, and E0842 makes a retired name an error in a user's blink.toml. So each warning is spec surface whether or not §3.6 mentions it. Also, `@allow` attaches only to a `fn`. If a lint exists and a project sets it to `"error"`, the §2.20 example stops compiling, and the user has no local fix. "Leave it to tooling" does not remove that interaction. It only hides it. A narrow rule written in the spec is smaller than a lint that is not in the spec. So I vote E-warn and drop E-none. I still vote against E-err, for the M4 reasons.
>
> **V1 trigger: (a), a §2.21 const expression equal to 0.** I change my scope guard here too. PLT is right: "literal only" needs a new definition (is `(0)` a literal? is `-0`?). "Const expression" already has one, and M2 needs the evaluator anyway. Reusing a term costs less than adding one. The rule stays: no folding through `let`.

- **PLT:**

> **V1: I change from (a) to (b), literal only.** Sys, Web and AI/ML should weigh this case:
> ```blink
> const SHARDS = 0
>
> fn bucket(n: Int) -> Int {
>     if SHARDS > 0 {
>         return n % SHARDS    // (a) warns here; the code is correct
>     }
>     0
> }
> ```
> A const ref equal to 0 is a configuration value, and code guards it like this. Under (a) the warning fires on correct code, and the fix would be flow analysis, which nobody proposed. Nobody writes a literal `0` divisor behind a guard. My Phase A point that "literal" has no definition still holds, so the spec must define it: *the divisor is an integer literal with the value 0, which may have parentheses and a unary `-`*. That is DevOps's list. The trigger can grow later, and a warning may grow.
>
> **V2: (a).** The spec states it, for the reason above. It is lexical, the same as the `assert_panics` fence.

- **Web/Scripting:**

> **V1: I change to (b), literal 0 only.** I proposed (a), "consts count". Reading the other texts, I found a false positive I missed:
>
> ```blink
> const PER_PAGE = 0
>
> fn pages(total: Int) -> Int {
>     if PER_PAGE == 0 {
>         return 0
>     }
>     total / PER_PAGE
> }
> ```
>
> Under (a) this correct, guarded code warns, because we do no flow analysis (V4). Config-style consts are the common case in web and script code, and a guard like this is the normal pattern. A literal `/ 0`, in contrast, is never correct outside `assert_panics`. So (b) gives zero false positives and the simpler rule: "a literal `0` divisor warns". A user learns that in 5 seconds, not 5 minutes. Const refs can join later. Adding a trigger to a warning breaks nothing for users at the default level.

- **Systems:**

> **V1: (a), a §2.21 const expression equal to 0.** From the codegen side, (a) costs nothing. C-err needs a const evaluator anyway, and V1(a) only asks it "is this divisor a const expression, and is it 0". The real bug shape is a config const: `const SHARDS = 0`, then `n / SHARDS`. That is the same certain panic as `n / 0`, and a literal-only trigger misses it.

- **DevOps:**

> - **V1: I change to (a), const expression equal to 0.** PLT is right: "literal only" has no definition in the spec (is `(0)` a literal? `-0`?), and §2.21 already defines a const expression. For tooling it is also better. The trigger is fixed by §2.21, so it does not grow each release. That removes my own D3 concern that a new trigger breaks a `"error"` build. The const evaluator must exist for Q1 anyway, so the LSP gets the value for free. Condition: when the divisor is a const ref, the warning adds a `note:` that names the const and its location. Without that note, `7 % PER_PAGE` warns with no visible zero, and users report it as a bug.

- **AI/ML:**

> **V1: (a), a §2.21 const expression equal to 0.** For learnability, (a) reuses a term the spec already defines. Look at (b): "`0`, `0x0`, `0_0`, `0b0`, parenthesized, unary `-`" is a new list that a model must learn as a separate rule, and every case in that list is already a const expression. (a) also catches the real bug class, `total / BUCKETS` with `const BUCKETS = 0`. C-err needs the const evaluator anyway, so (a) costs nothing extra. The guard stays: no folding through `let`.

#### Phase C — Final vote

Each panelist's ballot is below in full. Tallies:

- **Q1: const contexts** — 6-0 C-err.
- **Q2: expression position** — 6-0 E-warn.
- **Q2-V1: trigger** — 6-0 (b), literal 0. The positions in Phase B crossed: PLT and Web moved to (b), and Sys, DevOps, AI/ML and Min moved to (a). In Phase C every panelist voted (b). The deciding case was a guarded config const. AI/ML: "I change from (a). The guarded-const case from PLT and Web decides it: `if PER_PAGE == 0 { return 0 }` followed by `total / PER_PAGE` is correct, idiomatic code, and models write it often." Min: "PLT's and Web's guarded-config case (`if SHARDS > 0 { n % SHARDS }`) is a false positive on correct code under (a), and only flow analysis would fix it."
- **Q2-V2: `assert_panics`** — 6-0 (a), with the rule written as part of this warning's trigger.
- **Q2-V4: dead branches** — 6-0 fires.
- **Q3: sibling ticket** — 6-0 S-split.
- **Q3-R: range path** — 4-2 r2 (Sys, Web, PLT, Min); DevOps and AI/ML voted r1 (empty ranges join only through `@requires`). Before the vote, the moderator stated one fact: §3b defines V0002 (a disproven contract) as a hard compile error, and ERROR_CATALOG.md has no V0002 row. Min: "§3b already defines V0002 as a hard *error* for a disproven contract. So (r1)'s 'ranges join this warning through `@requires`' would put into this record a path that conflicts with §3b."
- **N1: name family** — 6-0 specific.
- **N2: name** — 3-3 tie: `DivisionByZero` (Web, AI/ML, Min) and `DivisionByConstantZero` (Sys, PLT, DevOps).
- **S1, S2, S3** — 6-0 yes each.

<details>
<summary>Systems — full Phase C ballot</summary>

Sys Phase C ballot: C-err, E-warn, V1(b), V2(a), V4 fires, S-split, r2, specific name (DivisionByConstantZero first), S1/S2/S3 yes. Round 1 changed three of my votes: V1, R and N1.

**Q1: C-err**
**Reasoning:** Const-evaluation Q4 says consts are emitted as literals, and a panic has no literal to emit. A range-pattern bound lowers to compares on literals, so it cannot panic at run time at all. "Const evaluation must succeed" is one branch in an evaluator that must exist anyway.
**Concern:** The evaluator must cover all four const contexts. If it misses field defaults or keyword defaults, `10 / 0` still reaches codegen there.

**Q2: E-warn**
**Reasoning:** A zero divisor in a dead branch costs nothing at run time, so an error buys no speed and no safety. The warning and its `assert_panics` exemption decide whether a build that sets the warning to "error" compiles, and that must not differ from tool to tool. I include Min's sentence: "not a compile error outside a const context; panics at run time".
**Concern:** §3.2 still marks `let bad: I8 = 127 + 1` as a COMPILE ERROR. Until S2 settles that, the spec treats two literal certain panics in `let` position in two different ways.

**Q2-V1: (b), literal 0 only. I change from (a).**
**Reasoning:** The guarded-const examples from PLT and Web (`if SHARDS > 0 { return n % SHARDS }`) decide this for me. Under (a), a warning with no flow analysis fires on correct, normal code. gcc's `-Wdiv-by-zero` on macro-folded zeros shows the same false-positive pattern in C. A literal `0` divisor is never correct outside `assert_panics`, so (b) has no false positives, and the definition is short: "an integer literal with value 0, with optional parentheses and unary `-`".
**Concern:** The real config-const bug (`n / SHARDS` with `const SHARDS = 0`, no guard) stays silent until a later panel adds guard-aware detection.

**Q2-V2: (a), stated in the spec**
**Reasoning:** `@allow` attaches only to a `fn`, so the exemption has to be language text. Otherwise the §2.20 example compiles under one tool and fails under another.
**Concern:** It can become a precedent, so that other warnings gain lexical exemptions without a panel vote.

**Q2-V4: fires**
**Reasoning:** No flow analysis means the rule is easy to predict, and with a literal-only trigger a dead `/ 0` is still a line nobody meant to write.
**Concern:** Generated code with dead literal divisors gets noise. The fix is `@allow` on the generated fn.

**Q3: S-split**
**Reasoning:** This decision settles `/` and `%` and closes the sibling ticket. It also rejects a list of range-taking APIs built into typecheck.
**Concern:** None from my domain.

**Q3-R: (r2). I change from (r1).**
**Reasoning:** The V0002 fact changes this for me. Under §3b, a disproven `@requires` is a hard compile error. If we bind ranges to `@requires` now, `rand.int(5..5)` may come back as an error, which Rand Q7c rejected 6-0. Leave the mechanism to the panel that designs it.
**Concern:** A future panel may build a list of APIs in typecheck after all, if nothing points it to a principled path.

**N1: specific. I change from general.**
**Reasoning:** PLT's point holds with the V0002 fact. The range path would get contract diagnostics, not this warning, so a general name would wait for triggers that never come. Under a general name, each new trigger also widens a user's "error" setting without notice. One name per trigger keeps the effect of a user's `[lints]` setting easy to predict.
**Concern:** If a second certain-panic trigger does arrive, users get two names for one idea.

**N2:** 1 `DivisionByConstantZero`, 2 `DivisionByZero`, 3 `AlwaysPanics`, 4 `CertainPanic`.
**Reasoning:** `@allow(DivisionByZero)` reads as if it suppresses the run-time panic itself. "ConstantZero" names the trigger and not the event.
**Concern:** "Constant" is a bit wider than the literal-only trigger under (b), and readers may expect `const` refs to trigger it.

**S1: yes.** "A zero divisor is not overflow", with a pointer to §2.21, removes the false reading of §3.2.
**S2: yes.** Keep `let b: U8 = 300` (a typing error) apart from `let bad: I8 = 127 + 1` (an evaluation question).
**S3: yes.** C `x / 0` is UB, and gcc can delete it, which loses the panic. Lower a known-zero divisor to an unconditional panic call. This is a codegen chore, not sections/ text.

</details>

<details>
<summary>Web/Scripting — full Phase C ballot</summary>

WEB — Phase C ballot

**Q1. Vote: C-err.**
Reasoning: A const that panics before `main` runs is the most confusing failure a new user can see. TS enums, Rust const and C++ constexpr all reject this at compile time, so users expect it.
Concern: the error must point at the failing subexpression and name each const in the chain, or users will not find the zero.

**Q2. Vote: E-warn.**
Reasoning: The §2.20 example is what users copy first. `@allow` attaches only to a `fn`, so the `assert_panics` rule and the warning name must be in the spec, or a strict `[lints]` project cannot compile the canonical test. Include the M1 sentence: "not a compile error outside a const context; it panics at run time."
Concern: users may read a warning as optional and ship `/ 0` anyway, but the panic message and location still catch it at run time.

**Q2-V1. Vote: (b) literal 0.**
Reasoning: Sys says the warning is "never wrong about the panic, only about reachability". For the user, that is the same as wrong. In the guarded `if PER_PAGE == 0 { return 0 }` / `total / PER_PAGE` case the code is correct. The only local fix is `@allow` on the whole fn, and that hides real hits too. A literal `/ 0` is never correct outside `assert_panics`, so (b) has zero false positives and a 5-second rule. Widening to (a) later breaks nobody at the default level.
Concern: if (a) wins, config-const code gets warnings with no good fix, and "how do I silence DivisionByZero on a guarded const" becomes a common question.

**Q2-V2. Vote: (a).**
Reasoning: A rule that decides whether code compiles under the user's config must be readable in the spec, not hidden in a lint. Agree with Min: write it as part of this warning's trigger, not as a general suppression mechanism.
Concern: other warnings may copy the exemption without a panel vote.

**Q2-V4. Vote: fires.**
Reasoning: Users can predict it. A literal `/ 0` in a dead branch is still a line nobody meant.

**Q3. Vote: S-split.**
Reasoning: This decision settles the spec part of the sibling (name, exemption). Ranges stay out.
Concern: none of note.

**Q3-R. Vote: (r2).** I change from my round 1 position.
Reasoning: The moderator's V0002 fact matters. A literal call that breaks a `@requires` clause is already a hard compile error in §3b. So r1 points ranges at a path that leads to the compile error Rand Q7c rejected 6-0. Record only "not a built-in list of APIs in the typecheck", and let a later panel choose the mechanism with that conflict in view.
Concern: without a named path, someone may add a one-off range check in the stdlib or typecheck anyway. The recorded "no built-in API list" line must be firm.

**N1. Vote: specific.** I change from round 1.
Reasoning: I picked a general name to avoid a later rename. PLT's point removes that reason: ranges reach users through contract diagnostics (V0002), not through this warning, so a general name has no planned second member. Min's cost is real for users: under a general name, a team's `"error"` setting grows each release without their choice. A Python dev knows `ZeroDivisionError`, so `DivisionByZero` needs no explanation.
Concern: if a future panel does want a shared certain-panic warning, we pay for a second name.

**N2. Ranking:** 1 `DivisionByZero`, 2 `AlwaysPanics`, 3 `CertainPanic`, 4 `DivisionByConstantZero`.
Reasoning: `DivisionByZero` matches the panic text "division by zero", so name, message and runtime panic share one phrase. `DivisionByConstantZero` is long, and under trigger (b) "constant" is less exact than "literal". Among general names, `AlwaysPanics` reads as plain English and matches the message.

**S1. yes.** Without it, §3.2 readers expect `7 % 0` to be a compile error.
**S2. yes.** `let b: U8 = 300` and `let bad: I8 = 127 + 1` are separate questions, and users will hit both.
**S3. yes.** C `x / 0` is UB. gcc can delete it, and then the user gets no panic at all.

</details>

<details>
<summary>PLT — full Phase C ballot</summary>

PLT, Phase C ballot.

**Q1. Vote: C-err**
Reasoning: §2.21 calls const evaluation total, and const-evaluation Q4 emits each const as a literal. A const whose evaluation panics has no value, so without this rule the semantics have a hole. One rule ("const evaluation must succeed") covers `/`, `%` and overflow in all four const contexts.
Concern: the spec may list the failing operations case by case and leave a later partial operation out. Say "const evaluation must succeed".

**Q2. Vote: E-warn**
Reasoning: in a runtime expression a panic is a defined outcome, so an error adds no soundness and breaks substitution (`if false { e }`). The warning's name and its `assert_panics` exemption decide whether a build that sets the warning to `"error"` compiles, so they are spec text. Min's sentence ("not a compile error outside a const context") should open the text.
Concern: readers may take the warning as a type-level guarantee. It catches one syntactic shape, not zero divisors in general.

**Q2-V1. Vote: (b)**
Reasoning: Sys's answer, "never wrong about the panic, only about reachability", is true. But reachability is exactly what a guarded config const changes: `if SHARDS > 0 { n % SHARDS }` is correct, normal code, and Web found the same shape on its own. A literal `0` divisor behind a guard does not occur. So (b) has no false positives and (a) has a common one. The spec must define the literal shape (parentheses, unary `-`), and that closes my Phase A objection.
Concern: if (a) wins, the DevOps `note:` naming the const is required, or users will report the warning on guarded code as a bug.

**Q2-V2. Vote: (a)**
Reasoning: under a user's `[lints]` setting, the exemption decides whether a program compiles. It is lexical, the same as the `assert_panics` fence, and it should be worded as part of this warning's trigger (Min's wording), not as a general way to suppress warnings.
Concern: it becomes a pattern that other warnings copy without a panel vote.

**Q2-V4. Vote: fires**
Reasoning: a syntactic trigger with no flow analysis gives one rule that every tool can predict.

**Q3. Vote: S-split**
Reasoning: settle `/` and `%` here. Record that an empty range on its own is not a panic (`for i in 5..5` is valid), so any range check depends on what the callee requires.
Concern: none of substance.

**Q3-R. Vote: (r2). I change from r1.**
Reasoning: the moderator's fact decides it. V0002 is a hard error, so a range check through `@requires` would make `assert_panics { rand.int(5..5) }` a compile error. That is the expression-position error this decision rejects, and it is the inconsistency I raised in Rand Q7c. Tying the range case to `@requires` would bind a future panel to a mechanism that conflicts with Q2. Record only "not a list of APIs built into the typecheck".
Concern: with no mechanism named, the range case may never be revisited.

**N1. Vote: specific**
Reasoning: the range case has no agreed mechanism, and the one most named (`@requires`) gives V0002 errors, not this warning. So a general name is a promise with no design behind it. Each new trigger under a shared name also widens every build that sets the warning to `"error"`.
Concern: if a range warning comes later, users see two related names. That is a fair cost for names that say what each warning checks.

**N2. Ranking:** 1 `DivisionByConstantZero`, 2 `DivisionByZero`, 3 `AlwaysPanics`, 4 `CertainPanic`.
Reasoning: `DivisionByZero` repeats the runtime panic text and suggests the warning fires on any zero divisor, including computed ones. Of the general names, `AlwaysPanics` matches the message text.

**S1: yes.** It removes the reading that `7 % 0` is a constant-overflow error.
**S2: yes.** A literal its type cannot hold (`let b: U8 = 300`) is a typing error, and `let bad: I8 = 127 + 1` is an evaluation question. Keep them apart.
**S3: yes.** C `x / 0` is UB, and the panic must not depend on how gcc folds it. Not spec text.

</details>

<details>
<summary>DevOps — full Phase C ballot</summary>

DevOps Phase C ballot. Votes: Q1 C-err, Q2 E-warn, V1 (b), V2 (a), V4 fires, Q3 S-split, Q3-R r1, N1 specific, N2 DivisionByConstantZero > DivisionByZero > AlwaysPanics > CertainPanic, S1 yes, S2 yes, S3 yes.

**Q1: C-err**
Reasoning: Q4 says a const is emitted as a literal, and a panic has no literal. The error points to the subexpression that fails and adds one `note:` for each const ref in the chain, so the user sees where the zero comes from.
Concern: a long const-ref chain can make a long list of notes. The printer should cap it, like any other chain diagnostic.

**Q2: E-warn**
Reasoning: The `[lints]` key and the `@allow` name are user-visible API (E0842). The `assert_panics` rule decides whether the §2.20 example compiles under `"error"`. Both need one fixed home in the spec, or the compiler and the LSP can disagree.
Concern: this is the first warning with a context rule. Reviewers must not let "quiet inside assert_panics" spread to other warnings without a vote (Min's concern, and I share it).

**Q2-V1: (b), literal 0 only. I change from (a).**
Reasoning: The PLT/Web case (`if SHARDS > 0 { n % SHARDS }`) decides it for tooling. A warning that fires on correct, guarded config code gets set to `"off"` in blink.toml, and then the user also loses the true literal cases. The only local fix is `@allow` on the whole fn, which hides other warnings there too. A literal `0` divisor outside `assert_panics` is never correct, so (b) has no false positives. The spec must define the literal list: an integer literal with value 0, with optional parentheses and unary `-`. My const-ref `note:` condition no longer applies.
Concern: the `const BUCKETS = 0` bug class gets no warning in v1. Widening the trigger later is safe at the default level, but release notes must list it, because it can break `"error"` builds.

**Q2-V2: (a)**
Reasoning: `@allow` attaches only to a fn, so without spec text a project at `"error"` cannot compile the canonical test. A rule that only the lint knows is one the LSP can get wrong.
Concern: the text must be scoped to this warning by name, not written as a general mechanism.

**Q2-V4: fires**
Reasoning: no flow analysis. The compiler and the LSP must give the same answer, and a dead literal `/ 0` is still a line nobody meant to write.
Concern: none worth recording under (b).

**Q3: S-split**
Reasoning: this decision settles the name and the exemption. The range part is not a built-in API list.
Concern: the sibling ticket must close with a pointer, so it does not stay open as a phantom ready item.

**Q3-R: r1**
Reasoning: `@requires` already exists in §3b with a static-check path (V0002). Naming it stops a future API list in typecheck, which is the one-off rule Rand Q7c rejected.
Concern: V0002 is a hard error, and Rand Q7c voted 6-0 against an error for `rand.int(5..5)`. The future panel must settle severity for contract checks on literal input, and V0002 also needs its missing ERROR_CATALOG row. I ask for both as a follow-up ticket.

**N1: specific. I change from general.**
Reasoning: PLT's fact decides it. A range violation on literal input is a contract diagnostic (V0002), so it would not join this warning, and a general name buys nothing. A specific name tells a reader of blink.toml what the key does. A general name lets the `"error"` setting grow without the user knowing.
Concern: if a future panel does want one certain-panic warning, it pays one rename. E0842's did-you-mean help makes that cost small.

**N2: 1 DivisionByConstantZero, 2 DivisionByZero, 3 AlwaysPanics, 4 CertainPanic**
Reasoning: `DivisionByZero` is also the substring of the runtime panic message, so a search in logs or docs mixes up the panic and the lint. `DivisionByConstantZero` says that the compiler knows the value. If the general family wins, `AlwaysPanics` matches the message words "always panics".
Concern: under V1(b) the word "Constant" means a literal. The catalog row must say "a literal 0 divisor" so that nobody reads it as "const refs count".

**S1: yes.** It removes the reading that `7 % 0` is a compile error.
**S2: yes.** Keep `let b: U8 = 300` (typing) apart from `127 + 1` (evaluation).
**S3: yes.** A C `x / 0` is UB, and gcc can remove it, so then there is no panic and no diagnostic.

</details>

<details>
<summary>AI/ML — full Phase C ballot</summary>

AI/ML, Phase C ballot.

**Q1. Const contexts**
**Vote:** C-err
**Reasoning:** The spec says the compiler evaluates a const and emits it as a literal, so a const that panics contradicts the spec. One rule, "const evaluation must succeed", covers `/`, `%` and overflow. A model can learn that rule from one sentence.
**Concern:** If the error does not add a `note:` for each const ref in the chain, a model cannot find which const holds the 0.

**Q2. Expression position**
**Vote:** E-warn
**Reasoning:** Two things a user can see depend on spec text: the warning's name (for `@allow` and `[lints]`) and whether the §2.20 example compiles under `"error"`. A model that reads only the spec must be able to predict both. The text should open with the plain sentence "not a compile error outside a const context; it panics at run time", so that no reader takes §3.2 to mean a compile error.
**Concern:** If the spec text leaves out that opening sentence, models will still read §3.2 and expect a compile error.

**Q2-V1. Trigger**
**Vote:** (b) literal 0, with optional parentheses and unary `-`
**Reasoning:** I change from (a). The guarded-const case from PLT and Web decides it: `if PER_PAGE == 0 { return 0 }` followed by `total / PER_PAGE` is correct, idiomatic code, and models write it often. A warning on correct code teaches a model to distort its code or to add `@allow` without need. That cost is larger than the cost of learning a short, defined list. Widening to (a) later breaks nothing at the default level.
**Concern:** The spec must define "integer literal 0" exactly (`0x0`, `0_0`, `(0)`, `-0`), or each tool picks its own set.

**Q2-V2. `assert_panics`**
**Vote:** (a)
**Reasoning:** Under (b) the behavior is the same but nobody can read it in the spec, so a model cannot tell whether the canonical test compiles under strict lints. Write it as part of this warning's trigger, not as a general suppression mechanism.
**Concern:** Readers may copy the exemption onto other warnings without a vote.

**Q2-V4. Dead branches**
**Vote:** fires. One lexical rule is easy to predict, and a literal `/ 0` in a dead branch is still a mistake.
**Concern:** None worth noting with the literal-only trigger.

**Q3. Sibling ticket**
**Vote:** S-split
**Reasoning:** The name and the `assert_panics` rule are spec text, so this decision settles part of the sibling. Ranges stay out.
**Concern:** The range part could stay open with no owner.

**Q3-R. Range path**
**Vote:** r1
**Reasoning:** `@requires` and its static verdicts (V0002) already exist in §3b, so this commitment names a mechanism the spec already has, not one it might add. It is the rule a model can predict: "a stated contract fails on literal input". A list of APIs that are checked silently would be impossible to predict.
**Concern:** r1 may be read as "ranges join this warning". They would get contract diagnostics.

**N1. Name family**
**Vote:** specific
**Reasoning:** I change from general. PLT's point about V0002 decides it: under r1, a range violation becomes a contract diagnostic, so no future trigger joins this warning. A general name would then promise something false. With a literal-only trigger, a name that says exactly what it checks is the easiest to learn.
**Concern:** If a later panel does add a second certain-panic trigger, it needs a new name.

**N2. Name ranking**
1. `DivisionByZero`
2. `DivisionByConstantZero`
3. `AlwaysPanics`
4. `CertainPanic`

**Reasoning:** `DivisionByZero` matches the pinned runtime substring `division by zero`, so a model links the warning and the panic it predicts with one fact. Under trigger (b), "Constant" is less exact and adds tokens. If the general family wins, I rank `AlwaysPanics` over `CertainPanic` because it matches the message text.
**Concern:** A model may think `DivisionByZero` fires on any divisor that might be zero, so the catalog row must say "literal 0 divisor".

**Side items**
- **S1:** yes. This is the most important fix for learnability.
- **S2:** yes. `let bad: I8 = 127 + 1` (error) next to `let a = 7 % 0` (warning) teaches a false general rule until it is resolved.
- **S3:** yes. Never emit C UB. This is not spec text.

</details>

<details>
<summary>Minimalism — full Phase C ballot</summary>

Min, Phase C ballot.

**Q1. Vote: C-err**
Reasoning: This adds no new idea. It makes const-evaluation Q4 and the "total operations" claim in §2.21 true. One rule, "const evaluation must succeed", covers `/`, `%` and overflow, and takes the place of case-by-case text.
Concern: Someone may later build a const evaluator that treats every certain panic as `ConstEvalPanic`, including a call to a stdlib function, and so widen "const expression" through the back door.

**Q2. Vote: E-warn**
Reasoning: The warning's name and its `assert_panics` rule decide whether a strict-lint build of the §2.20 example compiles. `@allow` is fn-only, and E0842 makes a name a contract. So a warning is spec surface either way, and a short, written rule is smaller than a hidden one. I keep M1's sentence inside it: the spec says first that this is not a compile error.
Concern: The text grows past about three sentences in §3.6 and one catalog row.

**Q2-V1. Vote: (b), literal 0 only**
Reasoning: I change from round 1. PLT's and Web's guarded-config case (`if SHARDS > 0 { n % SHARDS }`) is a false positive on correct code under (a), and only flow analysis would fix it. A warning that fires on correct code teaches users to put `@allow` everywhere. (b) is the narrower start, and the definition it needs is one clause: an integer literal with value 0, with optional parentheses and unary `-`.
Concern: A future widening to const refs may be done with no panel, and it can break builds that set the warning to `"error"`.

**Q2-V2. Vote: (a)**
Reasoning: Others are right that (b) hides a rule that decides whether a program compiles. Write it as part of this warning's trigger only, not as a general suppression mechanism. W0703 keeps firing in tests.
Concern: Later warnings may copy the exemption with no vote of their own.

**Q2-V4. Vote: fires.** No flow analysis. Under (b) a dead literal `/ 0` is still a line nobody meant to write.

**Q3. Vote: S-split.** Under E-warn the sibling has a spec part, and this decision settles it. Ranges are out.
Concern: The sibling's range part stays as a vague note that nobody owns.

**Q3-R. Vote: (r2)**
Reasoning: The moderator's fact settles it for me. §3b already defines V0002 as a hard *error* for a disproven contract. So (r1)'s "ranges join this warning through `@requires`" would put into this record a path that conflicts with §3b. Record only "not a built-in list of APIs in the typecheck", and leave the mechanism to the panel that designs it.
Concern: Without a named path, someone may add a one-off range check to typecheck. The (r2) text must forbid that clearly.

**N1. Vote: specific**
Reasoning: YAGNI. A general name with one trigger bets on a future that no one has designed. PLT showed that ranges would arrive as contract diagnostics (V0002), not as this warning, so a shared name gains nothing. One name per trigger also means a user's `"error"` setting never grows by itself.
Concern: If a second certain-panic trigger does appear, users may get many small W-codes and no one name to turn them all off.

**N2. Ranking:**
1. `DivisionByZero`: short, and under V1(b) the divisor is a literal, so "Constant" adds no information.
2. `DivisionByConstantZero`
3. `AlwaysPanics`
4. `CertainPanic`

**S1: yes.** It takes the place of my M1 sentence and removes the false reading of §3.2.
**S2: yes.** `let b: U8 = 300` (typing) and `let bad: I8 = 127 + 1` (evaluation) are two different questions.
**S3: yes.** A C `x / 0` is UB. This is a codegen chore, not spec text.

</details>

#### Phase D — Round 2 (N2 and Q3-R)

N2 was tied and Q3-R was 4-2, so both went to one focused debate round and a silent re-vote. N2 used a ranked ballot, counted by instant runoff with a threshold of 4.

- **N2** — **5-1 `DivisionByLiteralZero`** on the first count (Sys, PLT, DevOps, AI/ML, Min). **Web** *(dissent)* ranked `LiteralZeroDivisor` first and the winner second. Sys, PLT and Min proposed the name in the debate. Each side's attack on the other's name held: `@allow(DivisionByZero)` reads as if it turns off the run-time panic, and "Constant" suggests that `const` references trigger the warning. DevOps changed: "Min and PLT answered my rename objection with my own Phase C argument. When a name changes only when the check changes, a user who sets `"error"` sees every widening in the open, and a widening goes back to a panel anyway."
- **Q3-R** — **r2 6-0** (DevOps and AI/ML moved). The six panelists each proposed a wording, and the panel ranked them:
  - Count 1: R-devops 3 (Web, DevOps, AI/ML), R-min 2 (Sys, Min), R-plt 1 (PLT).
  - Count 2: R-plt drops out, and its vote goes to R-devops.
  - Result: **R-devops 4-2**. **Sys** and **Min** *(dissent)* ranked R-min first ("Empty literal ranges are out of this decision. A check for them must not use a list of APIs built into the typecheck. The panel that adds such a check chooses the mechanism and its severity, with Rand Q7c (no compile error for `rand.int(5..5)`) in view."). Both ranked R-devops second.

Phase D debate replies, verbatim:

<details>
<summary>Systems — Phase D debate</summary>

Sys Phase D: I propose `DivisionByLiteralZero` for N2 and hold r2 for Q3-R.

**N2.**
Strongest argument against my vote (Web, Min, AI/ML): under V1(b), "Constant" is less exact than "literal", and `DivisionByZero` shares one phrase with the pinned panic text.
Answer: I accept the first half. "Constant" is inexact, which is the concern I gave in my own ballot. But the second half is the problem I have with `DivisionByZero`. The warning and the panic would then share one name, while they are different events. In a log search, "DivisionByZero" mixes them up, as DevOps said. And `@allow(DivisionByZero)` reads as "turn off the division-by-zero panic". PLT also notes it suggests the warning fires on computed zeros.

Proposal: **`DivisionByLiteralZero`**. It states the V1(b) trigger exactly, so the catalog row cannot be misread as "const refs count", which was the concern DevOps and I both raised. It still holds the phrase "division by zero" for search and for models, which answers Web and AI/ML, but it does not claim to be the panic. Its cost is one extra word over `DivisionByZero`.
Ranking if it is on the ballot: 1 `DivisionByLiteralZero`, 2 `DivisionByConstantZero`, 3 `DivisionByZero`. If it is not on the ballot, I hold `DivisionByConstantZero`.

**Q3-R.**
Strongest argument against r2 (DevOps, AI/ML): with no named path, a future panel or a stdlib author adds a one-off range check anyway, and `@requires` already exists.
Answer: `@requires` exists, but on literal input its static verdict is V0002, a hard error. r1 would point ranges at the exact result that Rand Q7c rejected 6-0, and at the expression-position error that Q2 here rejects 6-0. An unclear path does less harm than a named path that conflicts with two decisions. I take the risk seriously, so I ask for two things in the record:
1. r2 wording that is firm: "No range-taking API gets a built-in check in typecheck. A range trigger needs its own panel."
2. The DevOps follow-up ticket, which I support: decide the severity of a static `@requires` verdict on literal input, and add the missing V0002 catalog row.
Hold r2.

STABLE: yes

</details>

<details>
<summary>Web/Scripting — Phase D debate</summary>

WEB — Phase D

**N2.** The strongest argument against `DivisionByZero` is Sys's: `@allow(DivisionByZero)` reads as "permit division by zero", that is, as if it turns off the panic. I accept that this is a real misreading for JS and Python devs. To them, "allow" means "permit". DevOps's log-grep point adds to it. A case-insensitive search for "division by zero" finds both the lint and the panic.

But `DivisionByConstantZero` has its own misreading, and Sys and DevOps both name it in their concerns: "Constant" makes readers expect `const` refs to trigger it, which V1(b) rejected 6-0. That gives us a different Stack Overflow question: "why does `x / ZERO` not warn?"

**I propose a third name: `LiteralZeroDivisor`.** It names the trigger exactly as V1(b) defines it. It does not contain the panic substring, so grep stays clean (DevOps). It names the cause, not the event, so `@allow(LiteralZeroDivisor)` reads as "allow a literal zero divisor here", not "allow the panic" (Sys). It does not say "constant" (Sys's and DevOps's own concern). It is about the same length as the other two. The message text still says "always panics", so users still learn the result.

My ranking: 1 `LiteralZeroDivisor`, 2 `DivisionByZero`, 3 `DivisionByConstantZero`. If the new name is not on the ballot, I hold `DivisionByZero`. Its misreading only affects a user who writes `@allow` on a literal `/ 0`, and that user already sees the warning text.

**Q3-R. I hold r2.** The strongest argument against r2 is DevOps's and AI/ML's: with no path named, a one-off API list may appear. My answer: make the r2 text firm ("range checks are not added as a built-in list of APIs in the typecheck") and add DevOps's follow-up ticket. That ticket must settle (1) the severity of a `@requires` clause that fails on literal input, given Rand Q7c, and (2) the missing V0002 catalog row. That gives the future panel the path and the conflict, and does not lock in a hard error now.

STABLE: yes

</details>

<details>
<summary>PLT — Phase D debate</summary>

PLT, Phase D.

**N2. I propose a third name: `DivisionByLiteralZero`. If the panel does not admit it, I hold `DivisionByConstantZero`.**

Strongest argument against my vote (Min, and also Sys and DevOps in their own concerns): under V1(b) the trigger is a literal, and "Constant" names something wider. In Blink, "constant" reads as `const`, so `x / ZERO` would look covered when it is not. That is true. Three of the six ballots, mine included, needed a catalog note to undo what the name says. A name that needs a correction note is the wrong name.

`DivisionByZero` has the opposite defect, which Sys and DevOps both named: `@allow(DivisionByZero)` reads as if it turns off the runtime panic. It also matches the pinned panic substring, so a search for logs or docs finds both the panic and the warning. The name and the message should share one phrase, not the name and the panic.

`DivisionByLiteralZero` names exactly what V1(b) checks, and it needs no note. If a later panel widens the trigger to const refs, that is the moment to choose a new name, because the check has changed. It costs one more word. I accept that cost for a name that is exact.

**Q3-R. I hold r2, and propose that it carry one constraint.**

Strongest argument against my vote (DevOps, AI/ML): with no named path, someone builds a one-off list of APIs. Answer: r2 already forbids that list in plain words. Naming `@requires` does not prevent the list. It points at a hard error that conflicts with Q2. A better guard is the property that any future mechanism must have, rather than a mechanism:

> Empty literal ranges are not covered. Any future check must not be a list of APIs built into the typecheck, and must keep `assert_panics { rand.int(5..5) }` compiling, as Q2 does for `/ 0`.

This keeps DevOps's point (severity must be settled first) without binding a later panel to V0002.

STABLE: yes

</details>

<details>
<summary>DevOps — Phase D debate</summary>

DevOps Phase D: I hold N2 (DivisionByConstantZero) and change Q3-R to r2, with firmer wording.

**N2: I hold `DivisionByConstantZero`.**
Strongest argument against me (Min/Web): under V1(b) the trigger is a literal, so "Constant" is less exact, and `DivisionByZero` matches the panic text. Answer: matching the panic text is the problem, not the benefit. Sys put it best: `@allow(DivisionByZero)` reads as if it turns off the runtime panic. A user who writes it in a hot fn believes they removed a check. In a log search, `division by zero` finds both the panic and the lint. The warning's job is "the compiler knows this divisor", and "Constant" says that. It is also the stable word. If a later panel widens the trigger to const refs (the closed V1 debate left that open, at default level), "Constant" stays true, but `DivisionByLiteralZero` would need a rename (E0842 makes every rename a breaking change for `[lints]` users). My condition stays: the catalog row says "the divisor is an integer literal 0".

**Q3-R: I change to r2.**
Strongest argument against me (Sys/PLT): V0002 is a hard error, so r1 points the range case at the compile error that Rand Q7c rejected 6-0, and at the expression-position error that Q2 rejected here. That is correct. I named V0002 to block an API list, but a pointer to a hard error is the wrong pointer. Proposed r2 text, to answer the shared concern that r2 is too weak:

> "A future check for empty literal ranges must not be a list of APIs built into the typecheck or the stdlib. It must come from a rule that the API states in its own declaration, so users can read it. The panel that adds the check sets its severity."

This blocks the one-off list, names no mechanism, and leaves the error/warning choice open. I still ask for one follow-up ticket: V0002 has no ERROR_CATALOG row, and the spec does not say how severe a contract check is when every argument is a literal.

STABLE: yes

</details>

<details>
<summary>AI/ML — Phase D debate</summary>

AI/ML, Phase D. I change both positions.

**N2: I change to `DivisionByConstantZero`.**
The strongest argument against my vote is Sys's: `@allow(DivisionByZero)` reads as if it suppresses the runtime panic. From my lens that argument wins. I argued that the shared substring links the warning to its panic. But that link is the problem DevOps names: it merges two separate things into one. Compare the wrong inference each name invites:
- `DivisionByZero`: a model sees a `division by zero` panic and writes `@allow(DivisionByZero)` to "fix" it. The code compiles, and it still panics. That is a silent, wrong repair, and it is a likely one, because models patch diagnostics by their names.
- `DivisionByConstantZero`: a model expects a `const` ref divisor to warn, and it does not. The result is a missed warning, never wrong code. And if the trigger later widens to const refs (Sys says widening breaks nothing), the name becomes exact with no rename.

The second error costs much less. I considered `DivisionByLiteralZero`, which is exact today. I reject it because widening the trigger would force a rename (E0842). The catalog row must still say "a literal 0 divisor".

**Q3-R: I change to r2, with firm wording.**
The strongest argument against r1 is PLT's and Sys's: V0002 is a hard error. So r1 points the range case at a compile error for `assert_panics { rand.int(5..5) }`. That conflicts with Rand Q7c (6-0) and with this decision's own Q2. I missed that the mechanism I named has the wrong severity. Under r1, a model would learn the wrong outcome.

To keep my real goal, which is a rule a model can predict, I propose this r2 text: "No check for empty literal ranges is built into the typecheck as a list of APIs. Any future check must come from something the API states in its declaration, so that a reader of the API can predict the check." This names no mechanism. It only forbids hidden lists.

I support DevOps's follow-up ticket: the V0002 catalog row, and the severity of contract checks on literal input.

STABLE: yes

</details>

<details>
<summary>Minimalism — Phase D debate</summary>

Min, Phase D. I change my N2 vote, propose wording for Q3-R, and support DevOps's follow-up ticket.

**N2: I change my vote. I propose `DivisionByLiteralZero` and rank `DivisionByConstantZero` above `DivisionByZero`.**
Sys made the strongest argument against my vote. `@allow(DivisionByZero)` reads as "allow division by zero here", as if it turned off the run-time panic. A name that suggests a change of meaning when the warning changes none is a trap. Short does not help if the name misleads, so I move.
Both camps share one concern: "Constant" is wider than trigger (b), and readers will expect `const` refs to count (Sys and DevOps both say so). `DivisionByLiteralZero` names exactly what V1(b) checks. It does not repeat the panic text, so it also answers DevOps's concern about log searches. And it is not much longer.
Cost: if a later panel widens the trigger to `const` refs, the name is wrong and a rename breaks users (E0842). I accept that cost. A widening should go back to a panel anyway, and the name then forces that question in the open.
My ranking: 1 `DivisionByLiteralZero`, 2 `DivisionByConstantZero`, 3 `DivisionByZero`.

**Q3-R: I keep (r2) and propose firm wording.**
The strongest argument against (r2) is DevOps's: with no path named, an API list may appear later. My answer: name what is forbidden, not what is allowed. Proposed record text:
> "Empty literal ranges are out of this decision. A check for them must not use a list of APIs built into the typecheck. The panel that adds such a check chooses the mechanism and its severity, with Rand Q7c (no compile error for `rand.int(5..5)`) in view."
This closes the API-list door that both camps fear, and it avoids sending ranges to V0002, which is a hard error.
I support DevOps's follow-up ticket: decide the severity of a contract check on literal input, and add the missing V0002 row to ERROR_CATALOG.md. It costs nothing here, and it is the right home for the question that (r1) tries to answer early.

STABLE: yes

</details>

Phase D re-vote ballots, verbatim:

<details>
<summary>Systems — Phase D re-vote</summary>

Sys Phase D re-vote: N2 `DivisionByLiteralZero` first; Q3-R r2, with R-min first.

**N2 ranking:**
1. `DivisionByLiteralZero`
2. `DivisionByConstantZero`
3. `LiteralZeroDivisor`
4. `DivisionByZero`

**Reasoning:** It names exactly the V1(b) trigger, and it does not read as a switch for the run-time panic. The DevOps/AI/ML case that "Constant" survives a later widening carries less weight than it looks: the guarded-const false positive is why V1(b) passed 6-0. So a widening needs its own panel, and that panel can choose the name then, as Min says.
**Concern:** If a later panel does widen the trigger to `const` refs, users pay for a rename (E0842) in `[lints]` and `@allow`.

**Q3-R:** r2.
Wording ranking:
1. R-min
2. R-devops
3. R-aiml
4. R-sys
5. R-plt
6. R-web

**Reasoning:** R-min forbids the API list built into typecheck, leaves both the mechanism and the severity to the panel that adds the check, and puts Rand Q7c in front of that panel. That is the most complete form of what I asked for. R-plt binds the outcome early through its `assert_panics` clause, and R-web is too weak to stop a one-off check.
**Concern:** The follow-up ticket (V0002 catalog row, plus the severity of a contract check on literal input) may never get filed. Then the next panel meets the hard-error conflict cold.

</details>

<details>
<summary>Web/Scripting — Phase D re-vote</summary>

WEB — Phase D re-vote

**N2 ranking:** 1 `LiteralZeroDivisor`, 2 `DivisionByLiteralZero`, 3 `DivisionByConstantZero`, 4 `DivisionByZero`.
Reasoning: Both "literal" names state the V1(b) trigger exactly and do not read as "turn off the panic". AI/ML's point changed my last two places: a wrong `@allow(DivisionByZero)` "fix" leaves code that still panics, and that is worse than a warning that does not fire on a `const` ref.
Concern: if `DivisionByLiteralZero` wins and a later panel widens the trigger to `const` refs, users pay for a rename. That panel must face that cost openly, not stretch the old name.

**Q3-R: r2.**
Wording ranking: 1 R-devops, 2 R-min, 3 R-plt, 4 R-aiml, 5 R-sys, 6 R-web.
Reasoning: R-devops blocks a hidden list in the stdlib as well as in the typecheck. It requires that the rule be stated in the API's own declaration, which is what makes a check predictable for a user reading the docs. It leaves severity to the panel that adds the check. R-min is a close second because it names Rand Q7c. My own wording is the weakest of the six, so I rank it last.
Concern: R-devops names no follow-up, so the follow-up ticket (severity of a contract check on literal input, plus the missing V0002 catalog row) must be filed with this decision, or the range case may never come back.

</details>

<details>
<summary>PLT — Phase D re-vote</summary>

PLT, Phase D re-vote.

**N2 ranking:** 1 `DivisionByLiteralZero`, 2 `LiteralZeroDivisor`, 3 `DivisionByConstantZero`, 4 `DivisionByZero`.
Reasoning: the two literal names state exactly what V1(b) checks and need no correction note. `DivisionByLiteralZero` keeps the searchable phrase without claiming to be the panic, so it ranks above Web's equally exact name.
Concern: if `DivisionByLiteralZero` wins and a later panel widens the trigger to const refs, the rename is a breaking change (E0842). That panel must count the rename as part of the cost of widening.

**Q3-R:** r2.
**Wording ranking:** 1 R-plt, 2 R-devops, 3 R-aiml, 4 R-min, 5 R-sys, 6 R-web.
Reasoning: R-plt states a property that any future check must keep (`assert_panics { rand.int(5..5) }` compiles, as Q2 does for `/ 0`), so a later panel cannot add a range error that conflicts with Q2. R-devops and R-aiml add a sound second property: a reader can predict the check from the API's own declaration, so the check depends only on local information. The last three only forbid the API list.
Concern: if R-devops or R-aiml wins, "a rule the API states in its declaration" still allows a declared rule that produces a hard error, so the follow-up ticket on the severity of contract checks with literal arguments must settle that before any range check ships.

</details>

<details>
<summary>DevOps — Phase D re-vote</summary>

DevOps Phase D re-vote. N2: 1 DivisionByLiteralZero, 2 DivisionByConstantZero, 3 LiteralZeroDivisor, 4 DivisionByZero. Q3-R: r2, wordings ranked 1 R-devops, 2 R-min, 3 R-aiml, 4 R-plt, 5 R-sys, 6 R-web.

**N2: 1 `DivisionByLiteralZero`, 2 `DivisionByConstantZero`, 3 `LiteralZeroDivisor`, 4 `DivisionByZero`.** I change my first choice.
Reasoning: Min and PLT answered my rename objection with my own Phase C argument. When a name changes only when the check changes, a user who sets `"error"` sees every widening in the open, and a widening goes back to a panel anyway. Under that rule, the exact name that needs no catalog correction is the better diagnostic surface.
Concern: if `DivisionByLiteralZero` wins and a later panel widens the trigger to const refs, the release must ship the rename with an E0842 did-you-mean help from the old name, or `[lints]` users get a hard error and no hint.

**Q3-R: r2.** Wordings ranked 1 R-devops, 2 R-min, 3 R-aiml, 4 R-plt, 5 R-sys, 6 R-web.
Reasoning: R-devops and R-min both forbid the API list and leave severity to a later panel. R-devops also requires the rule to be stated in the API's own declaration, which is what lets the LSP show it at the call site. R-plt fixes the severity early, and R-sys and R-web only forbid, with no positive property.
Concern: if R-min or R-sys wins, nothing requires the future check to be readable from the declaration, so a check that hides in the stdlib's body (not in the typecheck) stays possible. The follow-up ticket (severity of a contract check on literal input, plus the missing V0002 catalog row) must be filed either way.

</details>

<details>
<summary>AI/ML — Phase D re-vote</summary>

AI/ML, Phase D re-vote.

**N2 ranking**
1. `DivisionByLiteralZero`
2. `LiteralZeroDivisor`
3. `DivisionByConstantZero`
4. `DivisionByZero`

**Reasoning:** The two literal names avoid both wrong inferences: that `@allow` turns off the panic, and that `const` refs count. A model then learns the trigger from the name alone, with no correction note. I accept the rename cost if the trigger widens, because that widening is not designed yet (YAGNI). I put `DivisionByLiteralZero` first because it keeps the operator's word "Division", and a model links it to `/` and `%` at once.
**Concern:** If `DivisionByLiteralZero` wins, a later widening to `const` refs may keep the old name to avoid an E0842 rename, and the name then becomes false.

**Q3-R**
**Vote:** r2

**Wording ranking**
1. R-devops
2. R-aiml
3. R-plt
4. R-min
5. R-sys
6. R-web

**Reasoning:** R-devops makes any future check something a reader can see in the API's own declaration, so the check is predictable. It also covers the stdlib and leaves the severity open. That makes it a superset of my wording. R-plt's property that `assert_panics { rand.int(5..5) }` keeps compiling is the next best, because it fixes the outcome a test writer relies on.
**Concern:** If a wording without the "stated in the declaration" clause wins (R-sys, R-web, R-min), a future check can still come from a rule that users cannot see. The record forbids only an API list in the typecheck.

</details>

<details>
<summary>Minimalism — Phase D re-vote</summary>

Min, Phase D re-vote.

**N2 ranking:**
1. `DivisionByLiteralZero`
2. `LiteralZeroDivisor`
3. `DivisionByConstantZero`
4. `DivisionByZero`

Reasoning: The first two name the V1(b) trigger exactly and need no catalog note to correct them. I put mine first because it keeps the phrase "division by" for search but does not claim to be the panic. `DivisionByZero` is last because `@allow(DivisionByZero)` reads as if it turns off the panic.
Concern: If a later panel widens the trigger to `const` refs, `DivisionByLiteralZero` needs a rename that breaks `[lints]` users (E0842). That panel must weigh the rename cost before it widens the trigger, and must not slip the widening in under the old name.

**Q3-R: r2.**

Wording ranking:
1. R-min
2. R-sys
3. R-web
4. R-devops
5. R-aiml
6. R-plt

Reasoning: The record should forbid the hidden API list in firm words and bind nothing else. R-min and R-sys do that, and they leave mechanism and severity to the panel that designs the check. R-devops and R-aiml add a commitment to a declared-rule mechanism, and R-plt fixes severity in advance. Each of those decides early what the future panel should decide with the full design in view.
Concern: Under R-min, a reader may treat "with Rand Q7c in view" as optional, and a future panel may reach a hard error for `rand.int(5..5)` without an explicit vote that overrules Q7c.

</details>

### Final Spec

```blink
const SHARDS = 0
const PER_SHARD = 1024 / SHARDS     // error[ConstEvalPanic]: division by zero

fn main() {
    let a = 10 / 0                  // warning[DivisionByLiteralZero]; RUNTIME PANIC
}

test "division by zero panics" {
    assert_panics {
        let _ = 10 / 0              // no warning inside assert_panics
    }
}
```

- §2.21 *Const Evaluation Must Succeed*: `ConstEvalPanic` (E0546) applies in all four const contexts, also inside an `assert_panics` body. The error points at the subexpression that fails and has one `note:` for each `const` reference that leads to the failing value.
- Outside a const context, the compiler does not evaluate an expression as a const. `let a = 10 / 0` compiles and panics at run time.
- §3.6 *Integer Division*: `DivisionByLiteralZero` (W0704) fires for a literal 0 divisor of an integer `/` or `%`, with optional parentheses and unary `-`.
  - It does not follow `const` references or `let` bindings.
  - It fires in a branch that never runs.
  - It does not fire inside an `assert_panics` body. This rule belongs to this warning only.
- §3.2 *Overflow behavior*: a zero divisor is not overflow. The text points to §2.21 and §3.6.
- §2.20: the `assert_panics` example gives no warning.

**Record for empty literal ranges (Q3-R, R-devops):** "A future check for empty literal ranges must not be a list of APIs built into the typecheck or the stdlib. It must come from a rule that the API states in its own declaration, so users can read it. The panel that adds the check sets its severity."

**Constraints on future changes, from the Phase C and Phase D concerns:**

- If a later panel widens the trigger (for example, to `const` references), it renames the warning openly. The release ships an E0842 "did you mean" from the old name, because a widening can break a build that sets W0704 to `"error"`.
- No other warning copies the `assert_panics` rule without its own vote.
- A follow-up must settle how severe a contract (`@requires`) check is on literal input, given Rand Q7c. It must also add the missing V0002 row to ERROR_CATALOG.md. Every panelist asked for this before any range check ships.

