[< All Decisions](../DECISIONS.md)

# Variant Argument Count (E0321) and the Rollout of a New Error — Design Rationale

A wrong payload count on a variant had no code of its own. `Ok(1, 2)`, `Some()`, `Err()`, `None(1)` and
`Shape.Sq(1.0)` (declared `Sq(Float, Float)`) all reported the general `TypeError` (E0300). `Ok()` passed
`blink check` at `Result[(), E]`, because the checker allowed `Ok` to take 0 or 1 arguments, and the spec writes the unit
success only as `Ok(())`. No spec text let a payload argument be left out. To retire `Ok()` the compiler needs a code
that a user can set under `[lints]`. The rollout sentence of §3.6 *Mutable Parameters* covered only that subsection, so
the spec had no rule that says how a new error reaches users. The questions were: how a wrong count on a variant is
reported, how `Ok()` becomes an error, and whether the rollout sentence becomes a general rule.

## Summary

| Q | Question | Result | Vote |
|---|---|---|---|
| Q1 | A general rollout rule | C: a rule in §8.16.1 with mandatory wording ("ships first as a warning") and an exception for a program that had no meaning | 5-1 after Phase D (Minimalism dissent: A) |
| Q2 | The exception in the rule | A: one test only, the rejected program had no meaning ("it ICEs or miscompiles, or the spec never allowed it") | 5-1 (Web/Scripting dissent: B) |
| Q3 | `let r = Ok()` while `Ok()` is a warning | A: `CannotInferType` (E0301) only | 4-2 after Phase D (PLT and AI/ML dissent: B) |
| Q4 | `let r = Ok()` once `Ok()` is an error | A: the arity error comes first; E0301 is not reported | 5-1 (Minimalism dissent: B) |
| Q5 | A help line for a no-payload variant called with arguments | A: the spec names the repair (remove the parentheses), not the exact words | 4-2 after Phase D (PLT and Minimalism dissent: B) |
| Q6 | The count errors in the mixed-payload spec | A: both count cases report `VariantArgumentCount`; E0300 stays for a type mismatch | 6-0 |

Points the panel agreed on and did not ballot: one new code, `VariantArgumentCount` (E0321), for every wrong payload
count on a carrier (`Some`, `Ok`, `Err`, `None`) or a user variant; E0300 stays the type-mismatch code. The filer's
options (b) (a W-code for `Ok()` alone, then an E-code) and (c) (E0300 at warning severity) are rejected. `Ok()` is not
legal. At `Result[(), E]` it is a warning under `VariantArgumentCount` with a machine-applicable fix to `Ok(())`, and an
error in the next release. At any other success type it is an error at once, with no fix. Every other wrong count is an
error at once. The fields `note:` shows on every variant that has fields, carriers included. A no-payload variant says
that it takes no arguments and has no note. The message drops "0 or 1": `Ok` takes 1 argument. Only `Ok()` to `Ok(())`
is machine-applicable; `None(x)` to `None` is not, because it deletes an expression that may have effects. The rule
lives in `06_tooling.md` beside the editions "Lint severity" text, and it states the one-code test of PLT: one code when
only the severity changes, two codes (the `W0731` and `E0731` shape) when the warning and the error name different
properties.

Q1 and Q3 and Q5 went to a second round (Phase D) after a first vote that was split 3-2-1, 3-2-1 and 4-2. AI-First
review: 5/5.

### Compiler behavior before the decision

The moderator ran probes with the gen1 compiler and gave the results to the panel:

- `fn f() -> Result[(), Str] { Ok() }` passes `blink check`.
- `fn f() -> Result[Int, Str] { Ok() }` passes `blink check` and stops `blink build` with an internal error: "typecheck
  must reject a carrier constructor of the wrong arity".
- `Ok(1, 2)` gives ``error[TypeError]: variant `Ok` expects 0 or 1 argument(s), got 2``.
- `Some()`, `Err()` and `None(1)` give ``error[TypeError]: variant `X` expects N argument(s), got M``, with no note.
- `Shape.Sq(1.0)` gives the same `TypeError` text and ``note: fields of `Shape.Sq`, in order: Float, Float``.
  `Shape.Dot(1.0)` on a no-payload variant gives the same text and no note.
- `let r = Ok()` gives `CannotInferType` (E0301).
- `Ok()` is not used in `lib/` or `examples/`. Five test files use it, and some of them expect `Ok()` to pass.
- Two rollout paragraphs existed. §3.6 *Mutable Parameters* gave its own new errors a warning first. `02_syntax.md` gave
  `NotAPlace` (E0611) and E0610 on an assignment an error from the first release, because "none of these programs had a
  meaning under this section". The brief said that the §3.6 paragraph was the only one; Minimalism found the second in
  Phase A, and the Phase B digest corrected the fact.

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in
independent-proposal, debate, vote rounds. Phase A is excerpted from each panelist's own text. Phase B, Phase C and
Phase D are quoted from each panelist's file, without its heading line and without the line that lists the files read.

#### Phase A — Independent proposals

Five seats proposed one new code and a one-release warning for `Ok()` at `()`, with a general rule in
`06_tooling.md`. Minimalism proposed the same code and path with no general rule. All six rejected options (b) and (c).

- **Systems** (`A/sys.md`):

> New `VariantArgumentCount`, E-code (next free in the type-check range), for every wrong payload count on a carrier or user variant. It replaces E0300 for this case. E0300 stays the value-mismatch code.
>
> [...]
>
> p6 matters: when `T` is not `()`, `Ok()` was never valid and its lowering is broken. Only the `Ok()` against `Result[(), E]` shape gets the warning step. Everything else reports at error severity from day one.
>
> [...]
>
> Yes, make it general, but narrow: a new error that rejects code that compiled before may ship as a warning under its own code for one release. Put it in 06_tooling.md next to the editions "Lint severity" text (line 2054), and have §3.6 point to it. Do not make it mandatory. A new error for code that miscompiles (p6) must not wait.

- **Web/Scripting** (`A/web.md`):

> The message says "takes 1 argument". It does not say "expects 0 or 1". That text exposes a compiler detail (`tc_carrier_arity`), and a JS or Python developer cannot act on it.
>
> [...]
>
> A new error that rejects code the compiler accepted before ships first as a warning with a machine-applicable fix, and becomes an error in the next release. It keeps its name and code. An error for code that never compiled needs no warning step.
>
> The last sentence matters. Without it, every new diagnostic would need a warning hop, and a warning cannot guard code that already fails.

- **PLT** (`A/plt.md`):

> `Ok()` applies a unary constructor to zero arguments. That is an arity violation, not a type mismatch. `Ok(())` is the only way to write unit success. A special case `Ok => (0,1)` is an unsound exception: p6 shows `check` accepts `Ok()` at `Result[Int, Str]` and `build` ICEs. The checker accepts a term that has no typing derivation.
>
> [...]
>
> Distinguish from the W0731 -> E0731 shape. That shape uses two codes because the warning and the error name two different properties (an override of a deprecated default, then a sealed-method override). Here the property is the same, only severity moves, so one code. State this test in the rule.

- **DevOps/Tooling** (`A/devops.md`):

> Only `Ok()` gets the warning step. Every other wrong count is an error from release N (they fail to compile today; no code to migrate).
>
> [...]
>
> Exception clause: a diagnostic for a soundness or memory-safety hole (the ICE shape) may ship as an error at once. Without that clause the P1 case waits one release.

- **AI/ML** (`A/aiml.md`):

> One rule ("unit is written `()`"), one code. An AI that sees the error, the note and the fix repairs in one step.
>
> [...]
>
> A new error that rejects code that never compiled (it ICEs, or the spec never allowed it) ships as an error at once. Then §3.6 points to it. A spec writer then has no per-feature rollout choice to make.

- **Minimalism** (`A/min.md`):

> 02_syntax.md:3138 (not listed in the brief) is a second "Rollout" paragraph and it says the opposite for E0610/E0611: error from the first release. Rollout is a per-feature choice that depends on whether old programs had a meaning. A global "every new error warns first" would delay real errors and bind future panels. Keep rollout text next to each feature.

#### Phase B — Round 1

The moderator sent a digest of the points that all six Phase A files stated, five variations (V1 a general rollout rule,
V2 `let r = Ok()`, V3 the fields note, V4 the message text, V5 machine fixes beyond `Ok()`), and two repo facts: the
second Rollout paragraph in `02_syntax.md`, and the E0300 wording of the mixed-payload spec. Each seat read all six
Phase A files. Every seat ended with `STATUS: ready to vote`.

- **Systems:**

> **V1. General rule: yes, permissive wording ("may"), with the never-compiled exception.** I keep my Phase A position. min is right that 02_syntax.md:3138 shows rollout depends on whether old programs had a meaning. That is an argument for "may" and for the exception, not against a rule. A mandatory "ships first as a warning" (web, aiml, devops) is wrong for the compiler: it holds back a fix for a miscompile, and it would put 02_syntax.md:3138 in conflict with the general text. I oppose the mandatory wording. I support plt's test (one code when only severity moves; two codes when the warning and the error name different properties) as a sentence in the rule. If the panel rejects a general rule, I accept min-1's one line for this feature, but the next chore repeats this debate.
>
> **V2. `let r = Ok()` (p9): keep E0301.** I change my Phase A text. With `T` unresolved, the compiler cannot tell whether the warning (T is `()`) or the error (T is not) applies. Only E0301 is correct. After `Ok()` becomes an error in all cases, arity fires first. aiml-1 has this right.
>
> **V3. Note: yes for every variant that has fields, carriers included.** A no-payload variant (`None(1)`, `Shape.Dot(1.0)`) says "takes no arguments", with help to remove the parentheses. No `note:`.
>
> **V4. Drop "0 or 1".** After the rollout, `Ok` has arity 1. Text: "takes 1 argument, got 2". min's "text stays" keeps a message that exposes `tc_carrier_arity`.
>
> **V5. Machine fix for `Ok()` only.** I oppose `None(x)` -> `None` as a machine fix: `x` may have side effects, and the edit drops it. Help text only for the others.
>
> **Mixed-payload spec.** devops is right: both specs must say that a wrong count on a variant reports VariantArgumentCount, and E0300 stays only for a type mismatch. The mixed-payload text "more positionals than fields" is an arity case and conflicts. The moderator should check it.

- **Web/Scripting:**

> **V1 (general rule): yes, and I move toward min.** min's find (02_syntax.md:3138) does not argue against a general rule. It is the same test applied by hand: E0611 never compiled, so it is an error at once. E0612 compiled, so it warns first. A general rule with the exception states that test once, so the next panel does not argue it again. Wording: previously accepted code warns first (mandatory, not "may"). A "may" rule gives a user no way to predict what a release does, and it is the same as no rule. I accept devops's exception for a soundness or memory-safety hole, since an accepted program that miscompiles is the case the warning step cannot protect. I accept plt's test for one code or two: one code when only severity moves, two when the warning and the error name different properties. 02_syntax.md:3138 then reads as an instance of the rule, and §3.6 and §3.x point to it. Where the rule lives: 06_tooling.md, next to line 2054.
>
> **V2 (`let r = Ok()`): I change my vote.** I wrote "no second error", and aiml says the same, but that text did not say which error stays. Report the arity diagnostic and suppress E0301 once arity has fired. During the warning stage the arity diagnostic is only a warning, so E0301 stays: the program does not compile and the user needs a reason. A user who sees E0301 "cannot infer type" for `Ok()` is misled.
>
> **V3 (note):** yes, for every variant with fields, carriers included. No-payload variants: "takes no arguments", help: write `Shape.Dot`.
>
> **V4 (text):** drop "0 or 1". It exposes `tc_carrier_arity`. I oppose min here: a message the user cannot act on keeps the gap the ticket describes.
>
> **V5 (fixes):** I oppose devops's `None(x)` to `None`. The argument can have side effects, so the edit is not certain and should not be machine-applicable. `Ok()` to `Ok(())` is certain. Help text only for the rest.
>
> **Cross-spec check (devops's point):** the mixed-payload spec says E0300 for "more positionals than fields". That is a count error. It should report `VariantArgumentCount`. E0300 stays for a label-free payload with a wrong type.

- **PLT:**

> **V1 (general rule).** Yes, in 06_tooling.md, but I move to a semantic test instead of "may". min is right that 02_syntax.md:3138 shows rollout varies; it varies by one fact: did the rejected program have a meaning (it compiled and ran)? Wording: "A new error that rejects a program that compiled and ran as written ships first as a warning with a machine-applicable fix, and becomes an error in the next release; it keeps its name and code. A new error for a program that had no meaning (it ICEs or miscompiles, or the spec never allowed it) is an error at once." This is one rule, so 3138 is an instance (its programs "had no meaning"), not a contradiction. Then min's per-feature line is not needed. I drop devops' "soundness hole may ship at once": a hole that still ran correctly deserves the warning step; the test is meaning, not category. Keep my one-code-vs-two-codes test as a second sentence. If the panel rejects a general rule, I vote min-1's single line, not nothing.
>
> **V2.** `Ok()` at warning stage: both fire. E0301 is independent (E is unconstrained even after the fix), so it is true, not derivative. At error stage: arity only; a rejected term supplies nothing, as E0303 already says.
>
> **V3.** Note on every variant that has fields, carriers included. A no-payload variant says "takes no arguments".
>
> **V4.** Drop "0 or 1". Say "takes 1 argument".
>
> **V5.** `Ok()` -> `Ok(())` only. `None(x)` -> `None` deletes `x`, which can have effects; that edit is not certain, so help text only. The fix must also be absent for `Ok()` at non-unit `T` (error at once, no fix).
>
> **Cross-spec.** The mixed-payload spec says E0300 for "more positionals than fields". That is a count error. It must say VariantArgumentCount; E0300 stays for an argument whose type is wrong. Require one edit there before sign-off.

- **DevOps/Tooling:**

> **V1. General rollout rule: yes, with a wider exception than I wrote.** min's find (02_syntax.md:3138: E0611 and E0610 are errors at once) shows my "soundness or memory-safety" exception was too narrow. It would make the 3138 text a violation. Use plt-1's test: a warning step is only for programs the compiler accepted and that ran. A rejection of code that never compiled or never had a meaning ships as an error at once. With that exception 3138 is an instance of the rule, not a counter-example. I accept "may" over "ships": the tooling gain is one lookup place for authors and for `blink explain`, not a hard mandate. I also want plt's one-code/two-code test in the rule text: one code when only severity moves, two codes when the warning and the error name different properties (W0731/E0731). min's per-feature fallback is acceptable only if the one line lands near 03_types.md:2451 and names the code.
>
> **V2. `let r = Ok()`: I withdraw "arity only".** I checked the logic: the fix `Ok(())` does not cure E0301, since `E` is still free. So in release N, E0301 is the only diagnostic (the program does not compile either way; a second warning is noise). When `Ok()` becomes an error in N+1, arity fires first. Concede to aiml-1.
>
> **V3. Yes**, `note:` on every variant with fields, carriers included.
>
> **V4. Drop "0 or 1".** min's "text stays" cannot hold: 0 is no longer legal for `Ok`.
>
> **V5. I withdraw `None(x)` -> `None`.** The fix deletes an argument that may have effects, so it is not machine-applicable. Only `Ok()` -> `Ok(())` carries a machine fix; the rest get help text.

- **AI/ML:**

> **V1. General rule: yes, with mandatory wording and the "never compiled" exception.** A rule that says "may" adds a decision for every spec writer and every model that reads the spec: warn first or not? "Ships first as a warning" plus the exception leaves one test: did the program compile and run before? min's fact (02_syntax.md:3138) fits this. E0610, E0611 and E0613 are errors at once because "none of these programs had a meaning". The rule states that case, so 3138 becomes an instance of the rule and not a conflict. This answers min-1: the per-feature choice has one input, and the rule can name it. I accept plt's test for one code or two: one code when only severity moves, two when the warning and the error name different properties. Put it in the rule in one sentence. The rule lives in 06_tooling.md. §3.6 and 02_syntax.md:3138 point to it.
>
> **V2. `let r = Ok()`: I change my position. The arity error comes first, and E0301 is not emitted.** Arity is the root cause. With E0301 first, an AI fixes the inference, then meets the arity error in a second round. One diagnostic, one repair. At warning stage, `Ok()` warns and E0301 does not fire. This needs a spec line, because "inference fails" and "arity fails" are then ordered.
>
> **V3. Note: every variant with fields, carriers included.** A no-payload variant gets "takes no payload" and `help: write Shape.Dot` (web). A model repairs from the help line without reading the declaration.
>
> **V4. Drop "0 or 1".** After the rollout `Ok` has arity 1. The text says "expects 1 argument, got 0". min's "text stays" keeps a message that states a rule the spec does not have.
>
> **V5. Machine fix for `Ok()` only.** `None(x)` to `None` drops an expression that may have effects. `blink fix` must not discard code. Help text covers the rest.

- **Minimalism:**

> **V1 (general rollout rule).** I still prefer no rule, but I move. Five seats want one, and its exception clause ("code that never compiled needs no warning step") is the part I wanted anyway. If a rule goes in, the ballot should hold two wordings, and I vote for the permissive one: "A new error that rejects code the compiler accepted before may ship first as a warning under its final name and code, and becomes an error in the next release." Reasons: a mandatory rule fights 02_syntax.md:3138, where E0611/E0610 correctly ship as errors at once because old programs had no meaning. Mandatory also adds an obligation to every future panel for a case this panel can settle in one line. The rule must say where §3.6 and 02_syntax.md:3138 stand after it (they cite it; neither keeps its own copy). I accept plt's test (one code when only severity moves). I do not accept devops's soundness clause as a separate exception; "never compiled" already covers p6. Ballot: (A) no general rule, one line near 03_types.md:2451; (B) permissive general rule in 06_tooling.md; (C) mandatory general rule. I rank A, B, C.
>
> **V2 (`let r = Ok()`).** Keep E0301, and write no ordering rule. During the warning stage `Ok()` is accepted, so E0301 is the only error. After it becomes an error, the checker reports whichever comes first; the spec should not fix that order. A rule here adds surface for a case that has one fix (`Ok(())`).
>
> **V3 (note).** Agree: the fields `note:` applies to every variant that has fields. A no-payload variant (`None(1)`, `Shape.Dot(1.0)`) gets no note; the message "takes no arguments" is enough. Do not add help lines to the spec; they belong to the diagnostic text.
>
> **V4 (text).** Agree with sys, web, plt, devops: drop "0 or 1". I withdraw "text stays". The rule is arity 1 for `Ok`.
>
> **V5 (fixes).** Oppose `None(x)` -> `None` as machine-applicable: `x` may have effects, and deleting it changes the program. Machine fix for `Ok()` only. Other arity errors get help text.

#### Phase C — Silent ballot

Six questions went to a silent ballot. Each seat read the brief, the Phase B digest, all six Phase A files and all six
Phase B files. Q1: A no general rule; B a general rule with "may" wording; C a general rule with "ships" wording and an
exception for a program that had no meaning. Q2: A one test (the program had no meaning); B also an exception for a
soundness or memory-safety hole in a program that compiled. Q3: A E0301 only; B the arity warning and E0301; C the arity
diagnostic only. Q4: A the arity error first; B no order in the spec. Q5: A the spec names the repair; B no help line in
the spec. Q6: A both count cases report `VariantArgumentCount`; B keep the mixed-payload text as voted.

First tally: Q1 C 3 (Web/Scripting, PLT, AI/ML), B 2 (Systems, DevOps/Tooling), A 1 (Minimalism). Q2 A 5-1 (Web/Scripting
B). Q3 A 3 (Systems, DevOps/Tooling, Minimalism), B 2 (Web/Scripting, PLT), C 1 (AI/ML). Q4 A 5-1 (Minimalism B). Q5 A 4-2
(PLT and Minimalism B). Q6 A 6-0. Q1, Q3 and Q5 went to Phase D.

- **Q1: A general rollout rule** (first tally C 3, B 2, A 1; final C 5-1).
  - **Systems:** B — "A rule that says "may" lets the compiler team ship a fix for a miscompile at once, and it still gives authors one place to look. A mandatory warning step puts a release delay on any case where the old program was accepted but the compiler produced bad code. The permissive text also fits 02_syntax.md:3138 without a conflict." Concern: ""may" gives a user no way to predict what a release does, so the next chore repeats this argument."
  - **Web/Scripting:** C — "A user must be able to predict what a release does to code that compiled. A rule that says "may" gives them no way to predict it, and it adds a choice for every spec writer. The "no meaning" exception already covers 02_syntax.md:3138, so the mandatory text does not conflict with it." Concern: "A mandatory warning step can hold back a fix that matters, if the "no meaning" test is read narrowly."
  - **PLT:** C — "The choice between warning-first and error-at-once has one input, whether the rejected program had a meaning. A rule can state that test, and then 02_syntax.md:3138 is an instance of it rather than a rival. "May" leaves the outcome of each release unpredictable to users and adds a decision for every spec writer, so it is close to no rule." Concern: "The word "ships" binds each future panel, and a real soundness fix for a program that compiled and ran must still wait one release."
  - **DevOps/Tooling:** B — "One rule in 06_tooling.md gives authors, `blink explain` and `blink fix` one place to look, and it makes 02_syntax.md:3138 an instance and not a conflict. "May" keeps the rule true for the case where a warning step protects nobody. A mandatory rule needs a second test (compiled and ran versus compiled and miscompiled) that a tool cannot decide from the code." Concern: "With "may", a release can skip the warning step for code that compiled, and users get no stable way to predict a release."
  - **AI/ML:** C — "A rule with "may" adds a decision for every spec writer and every model that reads the spec: warn first, or not? The mandatory wording leaves one input, which is whether the program compiled and ran before. 02_syntax.md:3138 then becomes an instance of the rule, not a conflict." Concern: "A mandatory rule may force a warning stage onto a case where the old and new meaning are hard to tell apart, and spec writers will argue about "had a meaning"."
  - **Minimalism:** A — "The one fact that decides rollout is whether old programs had a meaning. 02_syntax.md:3138 already states that fact for its own errors, in the section that owns them. A general rule in 06_tooling.md adds a third place to read and a rule every later panel must check its case against. One line near 03_types.md:2451 settles this feature and adds nothing else." Concern: "The next feature that adds an error repeats this debate, and §3.6, 02_syntax.md:3138 and this line can drift apart."

- **Q2: The exception in the rule** (5-1, Web/Scripting dissent).
  - **Systems:** A — "The test "the rejected program had no meaning (it ICEs or miscompiles, or the spec never allowed it)" already covers p6 and any miscompile, which is the case I care about. A second exception by category (soundness, memory safety) is a looser test and needs a judgment call for each case. One test is easier to apply and to check." Concern: "A program that compiled and ran correctly but is unsound waits one release for its error."
  - **Web/Scripting:** B — "An accepted program that miscompiles or breaks memory safety is the case the warning step cannot protect. A warning there tells the user to keep shipping a bug. Such a program does have a meaning to its author, so test A would not let it through, and I want that case named." Concern: "B adds a second exception clause, and authors may stretch "soundness hole" to cover ordinary strictness."
  - **PLT:** A — "The test is meaning, not category. A program that compiled and ran as written had a meaning, so it gets the warning step even when the new error closes a hole. A second exception by category would erase the test and let each panel argue whether a case is a "hole"." Concern: "A program that runs correctly today but is unsound by the typing rules keeps compiling for one more release."
  - **DevOps/Tooling:** A — "The test must be one a tool and a spec writer can apply: did the rejected program have a meaning. "Soundness hole" is a category with no clear edge, and a program that compiled and ran correctly deserves the warning step. p6 is already covered by "never compiled" (it ICEs)." Concern: "A hole that compiled and ran wrongly in some programs waits one release for its error."
  - **AI/ML:** A — "One test ("had no meaning") is one decision point; the soundness-hole carve-out in B adds a second test and a category judgement that a model cannot apply from the spec alone. A program that compiled and ran gets the warning step, and the machine fix makes that step cheap to follow." Concern: "A real soundness hole in an accepted program will ship as a warning for one release."
  - **Minimalism:** A — ""Had no meaning" is one test with one input. Option B adds a second category that needs a judgment ("is this a soundness hole?"), and it overlaps the first: a program that miscompiles has no meaning already. Fewer clauses, fewer disputes." Concern: "A program that compiled and ran correctly, but is unsound, gets a warning step and so stays open for one release."

- **Q3: `let r = Ok()` while `Ok()` is a warning** (first tally A 3, B 2, C 1; final A 4-2).
  - **Systems:** A — "With `T` unresolved, the compiler cannot tell if the warning (T is `()`) or the error (T is not) applies. It can report only what it knows: E0301. A warning for a shape the checker has not resolved would be a guess." Concern: "After the user fixes the inference, a second diagnostic (the arity warning) appears in a later round."
  - **Web/Scripting:** B — "At warning stage the arity diagnostic is only a warning, and the program still does not compile. The user needs an error that says why, and E0301 is true because E is still free after the fix. Removing it would hide a real problem." Concern: "Two diagnostics on one line (a warning and E0301) may make the user think `Ok(())` alone will fix it."
  - **PLT:** B — "In the warning stage `Ok()` elaborates to `Ok(())`, so T is `()` and the arity warning is true. E is unconstrained even after the fix `Ok(())`, so E0301 is a separate, true error and the warning's fix does not cure it. Suppressing a true diagnostic hides a fact the user must still fix." Concern: "The user sees two diagnostics on one line and may take the warning's fix to be the whole repair."
  - **DevOps/Tooling:** A — "With `T` unresolved, the compiler cannot say whether the arity diagnostic is a warning (T is `()`) or an error (T is not). Only E0301 is true at that point, and the fix `Ok(())` does not cure it, since `E` stays free. A warning that the user cannot act on alone is noise." Concern: "After the user fixes E0301 they may meet an arity warning in a second round."
  - **AI/ML:** C — "One diagnostic, one repair. With `Ok()` the arity warning names the root cause, and a model that applies the fix gets `Ok(())`, which then reports whatever remains. Two diagnostics on one line make a model fix both in one pass or chase the wrong one first." Concern: "With `T` unresolved the compiler cannot tell whether the warning or the error applies, so the implementation must pick one severity for the unresolved case."
  - **Minimalism:** A — "With `T` unresolved the compiler cannot tell whether the arity case is a warning or an error. E0301 is the only true statement, and it needs no new rule. Option B puts two diagnostics on one line; option C needs a suppression rule." Concern: "A user sees E0301, fixes inference, then meets the arity warning in the next run."

- **Q4: `let r = Ok()` once `Ok()` is an error** (5-1, Minimalism dissent).
  - **Systems:** A — "Once `Ok()` is an error for every `T`, no resolution is needed to know it is wrong, so arity can run first and E0301 adds nothing. The order is a fact of one typecheck rule, and a fixed order makes the output the same for every build. A rejected term supplies nothing to infer from, as E0303 already says." Concern: "The spec now fixes a diagnostic order, which a later checker refactor must keep."
  - **Web/Scripting:** A — "Once `Ok()` is an error, arity is the root cause. E0301 "cannot infer type" would send the user to the wrong repair. One line in the spec makes the order the same in every compiler and for every tool." Concern: "A written order is one more rule to keep in step with the checker's real order."
  - **PLT:** A — "Once `Ok()` is an error it has no typing derivation, so it supplies no type to infer from. A rejected term supplies nothing, as E0303 already says, and E0301 would be derivative. One order in the spec makes the output the same on every checker pass." Concern: "Fixing the order in the spec binds the checker's pass structure to a diagnostic detail."
  - **DevOps/Tooling:** A — "Once `Ok()` is an error, arity is the root cause, and E0301 would send the user to fix inference first. One diagnostic gives one repair, and a fixed order makes the output stable across compiler changes and across `blink check` and the LSP. The spec line is short and matches what E0303 already says about a rejected term." Concern: "The spec now fixes a reporting order that a later checker rewrite must keep."
  - **AI/ML:** A — "The spec must state the order, or two compilers report different first errors and a model sees a different repair path on each. Arity is the root cause, so it goes first." Concern: "The spec gains an ordering rule that other diagnostic pairs will want too."
  - **Minimalism:** B — "`Ok()` has one fix, and any order of the two errors leads to it. A spec line that fixes the order adds a rule to the checker and to the spec for no gain. Leave the order to the implementation." Concern: "The two compilers or two releases may report different codes for `let r = Ok()`, and a test pinned to one order breaks."

- **Q5: A help line for a no-payload variant called with arguments** (first tally A 4, B 2; final A 4-2).
  - **Systems:** A — "This costs nothing at run time, and the help line is a fixed text with one edit. "Remove the parentheses" is the only repair for a no-payload variant, so the spec can state it without choosing between options. Tools and models then get the same repair text." Concern: "Help text in the spec is hard to change later without a spec edit."
  - **Web/Scripting:** A — "A user who writes `Shape.Dot(1.0)` needs to be told what to write. "Remove the parentheses" is the whole repair, and a JS or Python developer finds it faster than a message that only says "takes no arguments"." Concern: "Help text in the spec may freeze wording that diagnostics should be free to improve."
  - **PLT:** B — "A help line is diagnostic text, not a typing or arity rule. The spec fixes the code, the message property ("takes no arguments") and the note; the exact repair wording can change without a spec change." Concern: "Without a spec line, the help for a no-payload variant may differ between tools or lapse."
  - **DevOps/Tooling:** A — ""Takes no arguments" says what is wrong, but not what to write. A help line to remove the parentheses is the repair, and the LSP can offer it as a quick fix. Naming it in the spec keeps all diagnostics for this code in step." Concern: "Help text in the spec can freeze wording that belongs to the diagnostic."
  - **AI/ML:** A — "A help line "write `Shape.Dot`" lets a model repair the call without reading the variant declaration. It costs one line of spec and saves a round trip." Concern: "Help text in the spec can drift from the real diagnostic text."
  - **Minimalism:** B — "Help lines are diagnostic text, and they change without a spec edit. "Takes no arguments" says what is wrong. Naming a help line in the spec binds the wording and adds surface that we must keep." Concern: "Without a spec line, a help line may be missing, and a user may not see that the parentheses are the fix."

- **Q6: The count errors in the mixed-payload spec** (6-0).
  - **Systems:** A — "A wrong count is one rule in the checker, so one code must own it for carrier and user variants alike. If the mixed-payload spec keeps E0300 for "more positionals than fields", the same mistake reports two codes depending on payload shape. Fix the text before sign-off." Concern: "The mixed-payload spec needs one more edit, and its owner sign-off waits for it."
  - **Web/Scripting:** A — "Two specs that give different codes to the same wrong count would confuse users and the catalog. E0300 stays for a type mismatch, and the count errors share one code. The edit is small and must land before sign-off." Concern: "It edits a spec that the panel already voted, so the owner must review the change again."
  - **PLT:** A — "Wrong count is an arity violation, the sibling of E0303, and E0300 stays for a type mismatch. If the mixed-payload spec keeps "more positionals than fields" under E0300, one count error has two codes depending on payload shape. One edit before sign-off removes that overlap." Concern: "The mixed-payload spec reopens for an edit after its vote, and the owner must re-read it."
  - **DevOps/Tooling:** A — "Two specs that give two codes to one wrong-count error make `[lints]` filters and `blink explain` depend on which spec a case falls under. A wrong count is `VariantArgumentCount` on every variant shape; E0300 keeps type mismatch. The edit to the mixed-payload text is one sentence and must land before sign-off." Concern: "The owner signs off the mixed-payload spec before the edit, and the two specs disagree on main."
  - **AI/ML:** A — "Two codes for one mistake (a wrong count on a variant payload) is two decision points, and the mixed-payload spec would then contradict this one. One code for count, E0300 for type, is a rule a model learns once." Concern: "The mixed-payload spec needs an edit after its vote, before owner sign-off."
  - **Minimalism:** A — "Two codes for one wrong-count mistake is surface we would have to teach and keep. One row owns the count; E0300 keeps type mismatch. The edit to the unsigned spec is one clause and removes an overlap." Concern: "Editing a voted spec before sign-off reopens it, and the owner may read the edit as a change to a closed decision."

#### Phase D — Round 2

Q1, Q3 and Q5 had no majority large enough to settle, so each got one focused round. The moderator posted the Phase C
reasoning and concerns of every seat. Each seat then wrote a short reply (D1) and voted again alone (D2). Q2, Q4 and Q6
were not reopened. Moves in D1: Systems and DevOps/Tooling moved Q1 from B to C (Systems on condition that the
exception keeps the word "miscompiles"); Web/Scripting moved Q3 from B to A; AI/ML moved Q3 from C to B, so option C had
no seat.

D1 replies:

- **Systems:**

> **Q1. I move from B to C.** My Phase C concern was a delay on a fix for code that was accepted but miscompiles. The C text answers it: its exception ("it ICEs or miscompiles, or the spec never allowed it") makes a miscompile a program with no meaning, so the error ships at once. With that clause, the mandatory wording costs the compiler team nothing I care about. It also gives a user a stable test: if the program compiled and ran as written, it gets a warning first. I want the exception to keep the word "miscompiles" in the final text. If the clause drops it, I move back to B. Against min's A: a rule in one place stops the three rollout texts from drifting, and the next chore does not repeat this debate.
>
> **Q3. I stay with A (E0301 only).** plt's B reads `Ok()` as `Ok(())`, but in p9 `T` is unresolved, so the checker cannot know that. It would have to guess warning or error severity for the arity diagnostic, and a guess in the checker is a hazard. aiml's C has the same problem and also needs a suppression rule. E0301 is the one fact the checker has. The cost is one more round for the user, and the machine fix then applies at once.
>
> **Q5. I stay with A.** The repair for a no-payload variant has one edit, so a fixed help line in the spec gives every tool the same text. The spec already fixes help text where order matters (03_types.md:2716). The drift concern is small for a one-edit line.

- **Web/Scripting:**

> **Q1. Hold C.** sys and devops say "may" lets a miscompile fix ship at once. The rule already covers that: a program that miscompiles had no meaning, so it is an error at once under the exception, and "ships" does not hold it back. So the "may" word buys nothing the exception does not give, and it costs predictability. A user who reads a release note must know whether `blink fix` will warn first. min's one-line option leaves §3.6, 02_syntax.md:3138 and the new line to drift apart, which is the cost of three copies of one test. I accept that the "no meaning" test needs careful words. I ask that the rule give the test in plain terms: "compiled and ran as written".
>
> **Q3. I change my vote to A.** sys is right on the implementation. With `T` unresolved, the compiler cannot say whether the warning (T is `()`) or the error (T is not) applies. Under B it must guess a severity. Under A it reports only what it knows. The warning's fix does not cure E0301, so the user needs E0301 first. My concern (two diagnostics, one fix taken as whole) disappears under A. The cost is a second round: the user fixes inference, then sees the arity warning. That cost is small, because the program did not compile either way.
>
> **Q5. Hold A.** plt and min say help text is diagnostic wording. The spec need not fix the words, only the repair: remove the parentheses. 03_types.md:2716 already names a normative `help:` repair for E0301, so the spec has a precedent. State the repair, not the exact text, and the drift risk (my own concern from Phase C) falls.

- **PLT:**

> **Q1. Vote stays C.** sys and devops want "may" so a miscompile fix can ship at once. Q2 A already settles that: a program that miscompiles had no meaning, so the exception covers it and the warning step never delays it. A "may" rule adds no case that "ships" plus the exception lacks. It only removes predictability. That also answers web's and aiml's concern: the exception test is one fact, "did the program compile and run as written". If the panel picks B, I accept it over A: one place beats per-feature lines that drift.
>
> **Q3. Vote stays B.** sys says that with T unresolved the compiler cannot pick the warning or the error. In the warning stage, `Ok()` is typed as `Ok(())` (that is the legacy rule), so T is `()`, and the stage has no unresolved case. A non-unit T from context is the error-at-once case. E0301 is about E, which the fix does not touch. I do not accept A: it hides a true warning, and the user then meets it in a second round. aiml's C needs a suppression rule that Q4 A gives only for the error stage. The concern (two diagnostics, one line) is real, but each says a different true thing.
>
> **Q5. Vote stays B.** The precedent at 03_types.md:2716 makes help order normative because two repairs exist, and the order changes the outcome. A no-payload variant has one repair, so nothing needs a normative order. The spec fixes the code, "takes no arguments", and the note; the repair text stays in the diagnostic, where tools can improve it.

- **DevOps/Tooling:**

> **Q1. I change my vote from B to C.** My Phase C reason for "may" was a second test: compiled and ran versus compiled and miscompiled. Q2 A settled that. The rule has one test, "had no meaning", and a miscompile or ICE has no meaning, so it ships as an error at once under the mandatory wording too. This removes sys's reason for "may". What is left in favour of "may" is only that a release can skip the warning step for code that compiled. That is the worst outcome for tooling: `blink fix`, `[lints]` pins and CI configs cannot plan for a release. A rule a tool user cannot predict gives them nothing. I accept plt's concern that a soundness fix for a program that ran must wait one release; Q2 already took that cost. min's A is my second choice, B my third.
>
> **Q3. I keep A.** At `let r = Ok()`, `T` has no value. Elaborating `Ok()` to `Ok(())` for the warning (plt's reading) is a choice the checker makes by guessing, and the warning's fix would be wrong if `T` later resolves to a non-unit type. E0301 is the only diagnostic that is true for every `T`. The user fixes inference, then the checker has `T` and reports the arity case with the right severity. Option B prints a warning with a machine fix that cannot cure the line. Option C needs a severity pick for unresolved `T`, as aiml's own concern says.
>
> **Q5. I keep A.** Help lines cost the spec little when the spec names the repair, not the wording: 03_types.md:2716 already makes help order normative. The spec can say the help names removal of the parentheses and leave the text free. That answers the drift concern of sys, web and aiml.

- **AI/ML:**

> **Q1. Stay C.** sys and devops want "may" so a miscompile fix can ship at once. Q2 A already covers that: a program that miscompiles had no meaning, so the exception clause lets it through. "May" is then not needed for sys's case. It would only add the open choice for programs that did compile and run, and that choice is the one a model cannot resolve from the spec. min's drift concern is real, and the answer is that 02_syntax.md:3138 and 03_types.md:4220 point to the rule and keep no copy (a ballot point already states this). One place, one test.
>
> **Q3. Change from C to B.** plt's argument holds: in the warning stage `Ok()` elaborates to `Ok(())`, so `T` is `()` and the arity warning is decidable. This answers sys's objection (the compiler "cannot tell"), which assumed `T` stays free. E is still free after the fix, so E0301 is true and the fix does not cure it. For a model, two diagnostics in one run are better than one: it applies both repairs in one pass. With A, it fixes inference, then meets the warning in a second round, which is the cost I wanted to avoid. My C needed a suppression rule and a severity choice for an unresolved `T`; B needs neither. Each diagnostic carries its own repair, so the concern that the warning fix is the whole repair is small.
>
> **Q5. Stay A.** Precedent exists: 03_types.md:2716 already makes the order of two `help:` repairs normative. plt's and min's concern (wording freeze) is real, but the line states the repair ("write `Shape.Dot`"), not the exact text. A model repairs from it without reading the variant declaration.

- **Minimalism:**

> **Q1. No change: A. Ranking if A loses: B over C.** Both "ships" and "may" need the same test (did the program have a meaning), and 02_syntax.md:3138 already applies it in place. aiml and plt name the cost of C in their own concerns: panels will argue "had a meaning" for every case, and "ships" binds a real fix to a one-release wait. Under B that cost is zero, and users still get one place to look. sys and devops already vote B; with B, the three non-C seats and I agree that mandatory wording is the larger risk. If A cannot win, B is the least surface that settles the question. web and plt: a rule users "cannot predict" is the same as today, where each feature states its own rollout next to its errors.
>
> **Q3. No change: A.** plt says that in the warning stage `Ok()` elaborates to `Ok(())`. That holds only when `T` is known. In `let r = Ok()`, `T` is unresolved, so the compiler cannot choose between the warning and the error. B reports a warning the compiler cannot justify. Reporting E0301 alone is the only claim the checker can prove. Concern from web and plt (user takes the warning fix as the whole repair) does not arise under A, since no warning shows.
>
> **Q5. No change: B.** 03_types.md:2716 makes help order normative because two repairs exist and the order is a decision. A no-payload variant has one repair, so there is no decision for the spec to fix. Four seats name the same cost: frozen wording and drift.

D2 votes (each seat read the ballot, all Phase C files, the D1 digest and all D1 replies):

| Q | Systems | Web/Scripting | PLT | DevOps/Tooling | AI/ML | Minimalism | Result |
|---|---|---|---|---|---|---|---|
| Q1 | C | C | C | C | C | A (B over C) | C 5-1 |
| Q3 | A | A | B | A | B | A | A 4-2 |
| Q5 | A | A | B | A | A | B | A 4-2 |

- **Q1 reasons and concerns.**
  - **Systems:** C — "The rule has one test, and the exception makes a miscompile or ICE an error at once, so the compiler team loses no fast fix. A program that compiled and ran as written gets a warning first, and a user or tool can plan for that. One rule in 06_tooling.md also stops the rollout text from drifting across §3.6, 02_syntax.md:3138 and the next feature. The final text must keep the word "miscompiles" in the exception, as I said in D1." Concern: "If a later panel reads "had no meaning" narrowly, a fix for generated code that is wrong but only sometimes observed waits a release."
  - **Web/Scripting:** C — "A user must be able to predict what a release does to code that compiled. Under C the answer is one fact: the program compiled and ran as written, so it gets a warning first; if it did not, it is an error at once. The "miscompiles" clause lets a real fix ship without delay, which removes the case that moved sys and devops from B to C." Concern: "If a panel reads "had no meaning" narrowly, a mandatory warning step can hold back a fix that matters; the rule should state the test in plain terms ("compiled and ran as written") and keep the word "miscompiles"."
  - **PLT:** C — "Whether a new error warns first has one input: did the rejected program compile and run as written. A mandatory rule states that test once, and a "may" rule leaves each release unpredictable, which is close to no rule. Q2 A already lets a miscompile or ICE fix ship at once, so sys and devops lose nothing under "ships"." Concern: ""Ships" binds each future panel, and a real soundness fix for a program that compiled and ran must still wait one release."
  - **DevOps/Tooling:** C — "Q2 A leaves one test, "compiled and ran as written". A miscompile or ICE has no meaning, so it is an error at once under the mandatory wording, and sys's reason for "may" is gone. `blink fix`, `[lints]` pins and CI configs need a release to behave the same way each time." Concern: "A real fix for a program that compiled and ran must wait one release, and panels may argue over "had no meaning" in each later case."
  - **AI/ML:** C — "The rule has one input a model can check: did the program compile and run as written. "May" adds a choice for each spec writer and each model that reads the spec, and Q2 A already lets a miscompile or ICE fix ship at once, so sys's reason for "may" is gone." Concern: "Spec writers will argue over "had no meaning" for edge cases, and a narrow reading can delay a fix that matters."
  - **Minimalism:** A — "Every seat agrees the one deciding fact is whether the old program had a meaning, and 02_syntax.md:3138 already states it in the section that owns those errors. A general rule in 06_tooling.md adds a place to read and a rule each later panel must test its case against. If A loses, B over C: "ships" binds each later fix to the "had a meaning" argument." Concern: "The next feature that adds an error repeats this debate, and the rule text, §3.6 and 02_syntax.md:3138 may drift apart."

- **Q3 reasons and concerns.**
  - **Systems:** A — "At `let r = Ok()`, T is unresolved, so the checker cannot know whether the arity diagnostic is a warning (T is `()`) or an error (T is not). Typing `Ok()` as `Ok(())` for that case is a guess in the checker, and a guess at severity is a codegen-hazard shape I do not want. E0301 is true for every T and needs no new rule." Concern: "The user fixes inference first and meets the arity warning in a second round."
  - **Web/Scripting:** A — "At `let r = Ok()` the type `T` is unresolved, so the checker cannot say whether the warning (T is `()`) or the error (T is not) applies. E0301 is true for every `T`, and the warning's fix `Ok(())` does not cure it." Concern: "The user meets the arity warning in a second round after fixing inference, and a model or user may find that slower than seeing both at once."
  - **PLT:** B — "While `Ok()` is at warning severity, the legacy rule types it as `Ok(())`, so `T` is `()` and the stage has no unresolved case. The objection that the checker must guess a severity assumes `T` stays free, and it does not: a non-unit `T` from context is the error-at-once case, and `let r = Ok()` has no such context. E0301 is about `E`, which the fix `Ok(())` does not touch, so both diagnostics are true." Concern: "The user sees two diagnostics on one line and may take the warning's fix to be the whole repair."
  - **DevOps/Tooling:** A — "At `let r = Ok()`, T is unresolved. The checker cannot know whether the arity diagnostic is a warning (T is `()`) or an error (T is not). Under B it must guess, and the machine fix `Ok(())` does not cure the line, because E stays free. E0301 is the one diagnostic true for every T." Concern: "The user sees the arity warning only after the E0301 fix, and may feel the compiler could have said both at once."
  - **AI/ML:** B — "In the warning stage `Ok()` is typed as `Ok(())` by the legacy rule, so `T` is `()` and the arity warning is decidable; the "unresolved T" objection does not apply. `E` stays free after the fix, so E0301 is a separate true error. Each diagnostic carries its own repair, and a model can apply both in one pass." Concern: "Two diagnostics on one line may lead a model or user to treat the warning fix as the whole repair."
  - **Minimalism:** A — "In `let r = Ok()` the type `T` is unresolved, so the checker cannot say whether the arity diagnostic is a warning (T is `()`) or an error (T is not). E0301 is the one claim true for every `T`, and it needs no new rule. Web moved to A for this reason; B needs the checker to guess a severity." Concern: "The user fixes inference, then meets the arity warning in a second run."

- **Q5 reasons and concerns.**
  - **Systems:** A — "A no-payload variant has one repair, remove the parentheses, so naming it in the spec chooses nothing and gives every tool and model the same repair. The spec states the repair, not the exact text, so wording stays free to improve." Concern: "Diagnostic text and the spec line can drift apart if nobody checks them together."
  - **Web/Scripting:** A — "A user who writes `Shape.Dot(1.0)` needs to be told what to write: remove the parentheses. The spec names the repair, not the exact wording, so tools stay free to improve the text. 03_types.md:2716 already sets a precedent for a normative `help:` repair." Concern: "A help line in the spec can freeze wording that the diagnostic should be free to improve, if a later reader treats the repair statement as the exact text."
  - **PLT:** B — "A help line is diagnostic text, not an arity or typing rule. The precedent at 03_types.md:2716 fixes help order because two repairs exist and the order changes the outcome; a no-payload variant has one repair, so nothing needs a normative order. The spec fixes the code, "takes no arguments", and the note." Concern: "Without a spec line, the help for a no-payload variant may differ between tools or lapse."
  - **DevOps/Tooling:** A — "The spec names the repair (remove the parentheses, write `Shape.Dot`), not the exact text. The diagnostic text stays free to change. The LSP can offer the repair as a quick fix, and every tool gives the same repair." Concern: "The spec line can still freeze the wording of the diagnostic if later editors read it as exact text."
  - **AI/ML:** A — "The spec names the repair (remove the parentheses, write `Shape.Dot`) and not the exact text. A model can then repair the call without reading the variant declaration, and every tool gives the same repair." Concern: "Help text in the spec can drift from the real diagnostic text, or freeze wording that tools should improve."
  - **Minimalism:** B — "A no-payload variant has one repair, so the spec has no order to fix, and 03_types.md:2716 fixes help order only because two repairs exist. "Takes no arguments" says what is wrong, and the help text stays in the diagnostic, where tools can improve it." Concern: "A tool may omit the help line, and a user may not see that the parentheses are the fix."

#### Dissent and owner decision

Minimalism dissented on Q1 (it preferred one line for this feature, and ranked the "may" rule over the mandatory one) and
on Q4 (no order in the spec). Web/Scripting dissented on Q2 (it wanted a second exception for a soundness hole in a
program that compiled). PLT and AI/ML dissented on Q3 (they wanted both the arity warning and E0301). PLT and
Minimalism dissented on Q5 (no help line in the spec). The Q3 dissent rests on a fact that the panel left open: PLT and
AI/ML say that the legacy rule types `Ok()` as `Ok(())` in the warning stage, so the success type is `()`; Systems,
DevOps/Tooling, Web/Scripting and Minimalism say that the type is unresolved in `let r = Ok()`. Today `let r = Ok()`
reports E0301 only. The owner approved the tally; there was no tiebreak.

#### Reading gaps

- Phase A: all six files ran over the 500-word limit. No seat ran the probes. AI/ML did not open the spec files and took its
  facts from the brief. DevOps/Tooling read only the rules, the brief and a few catalog rows. PLT did not check the next
  free E03xx number.
- Phase C: AI/ML read the Phase A and Phase B files in bulk, and read in full only the digest and its own files. The
  other five seats list every file.
- Phase D: no seat re-read the brief or the Phase A and Phase B files; the ballot did not ask for it.
- The brief missed the second Rollout paragraph in `02_syntax.md`. Minimalism found it, and the Phase B digest corrected
  the fact.
- The Q3 fact (what `let r = Ok()` types as in the warning stage) stayed open. The vote settled the spec text; it did not
  settle the fact.

### AI-First Review

| Criterion | Result |
|---|---|
| Learnability | Pass: `Ok(())` is the one spelling of unit success, as in Rust and as in every example of the spec; a count error names the variant, the count and the fields |
| Consistency | Pass: one code owns every wrong payload count, carriers and user variants alike; one rule owns every rollout |
| Generability | Pass: a model writes `Ok(())` and gets no diagnostic; a model that writes `Ok()` gets a fix it can apply |
| Debuggability | Pass: the message, the fields note and the repair name the fault, and `Ok()` at a non-unit type is an error instead of an internal error |
| Token Efficiency | Pass: `Ok(())` costs two more tokens than `Ok()`; nothing else grows |

### Final Spec

```blink
type Shape { Sq(Float, Float), Dot }

fn a() -> Result[(), Str] { Ok() }            // warning[VariantArgumentCount], fix: Ok(()); error in the next release
fn b() -> Result[Int, Str] { Ok() }           // error[VariantArgumentCount] at once, no fix
fn c() -> Option[Int] { Some() }              // error[VariantArgumentCount]
fn d() -> Shape { Shape.Dot(1.0) }            // error[VariantArgumentCount]: takes no arguments
fn e() -> Shape { Shape.Sq(1.0) }             // error[VariantArgumentCount], note: fields of `Shape.Sq`, in order: Float, Float
```

- **Code.** A wrong payload count on `Some`, `Ok`, `Err`, `None` or a user variant is `VariantArgumentCount` (E0321).
  E0300 stays for an argument of the wrong type.
- **Note.** The fields note shows on every variant that has fields, carriers included. A no-payload variant says that it
  takes no arguments and has no note.
- **`Ok()`.** At a success type of `()`: a warning with a machine-applicable fix to `Ok(())`, then an error in the next
  release under the same name and code. At any other success type: an error at once, with no fix. Every other wrong
  count is an error at once.
- **Help for a no-payload variant (Q5).** The spec names the repair (remove the parentheses), not the exact words.
- **`let r = Ok()` (Q3, Q4).** While `Ok()` is a warning, E0301 only. Once `Ok()` is an error, the arity error first and
  no E0301.
- **Rule (Q1, Q2).** In §8.16.1 *Rollout of a new error*: a new error for a program that compiled and ran as written
  ships first as a warning with a machine-applicable fix, then becomes an error in the next release, under the same name
  and code. A new error for a program that had no meaning (it ICEs or miscompiles, or the spec never allowed it) is an
  error at once. One code when only the severity changes; two codes when the warning and the error name different
  properties. §3.6 and `02_syntax.md` point to the rule and keep no copy.
- **Mixed payloads (Q6).** In the mixed-payload text, every wrong-count case reports `VariantArgumentCount`; E0300 stays
  for a type mismatch.
- **Breaking change.** `Ok()` at `Result[(), E]` compiles with a warning for one release, then stops compiling. The fix
  is `blink fix`.
