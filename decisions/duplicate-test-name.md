[< All Decisions](../DECISIONS.md)

# Duplicate Test Names — Design Rationale

§2.20 said "Test names must be unique within their module scope. Duplicate names are a compile error." It named no
code. A test name is not a binding, so `DuplicateModuleBinding` (E1016, §2.12.1) did not fit. In the compiler,
two `test "a"` blocks in one file passed `blink check`. `blink test` then failed in the C compiler with
`redefinition of 'blink_test__a'`, an error in generated C. The same happened for a `test` plus a
`test.failing("a", ...)`, and for `"a\u{62}"` plus `"ab"`. A `fn a()` plus a `test "a"` had no conflict.

## Summary

| Q | Question | Result | Vote |
|---|---|---|---|
| Q1 | Number range of the new code | A: the E08xx group beside the test codes E0827 and E0831-E0835. The number was E0850 at vote time. E0851 when this was written: another approved branch took E0850 | 5-1 (Minimalism dissent: B) |
| Q2 | The help line | A: `give each test its own name`. The reason goes in `blink explain` | 3-3 after Phase D (Phase C: A 2, B 1, C 3), owner broke the tie for A |
| Q3 | A spec sentence "Two modules may use one test name." | B: no such sentence | 6-0 in Phase D after 4-2 in Phase C |
| Q4 | A line in §8.10.6 that `test.failing` shares the name space | A: add it, as a pointer to §2.20, not a restatement | 5-1 in Phase D after 4-2 in Phase C (Minimalism dissent) |
| Q5 | The later test's body after the error | A: typecheck it, then leave it out of lowering and the runner list | 6-0 |
| Q6 | How the diagnostic marks the first declaration | A: a secondary label "first declared here" at the first name literal | 6-0 |

Agreed by all six seats by the end of Phase B (not balloted): a new code `DuplicateTestName`, and E1016 and §2.12.1
do not change; "same name" is the `Str` value after escapes decode; `test` and `test.failing` share one name
space (stated in §2.20); a test name does not collide with a `fn`, `let`, `type` or other declaration; the check
runs at `blink check`, so `blink test` never reaches cc; the primary span is on the later name literal; N tests of
one name give N-1 diagnostics, each against the first; no machine-applicable fix; when the spellings differ, a note
shows the shared value; the message is "test `a` is declared twice in module `main`" (backticks); one invalid
example in §2.20; tests for both spelling cases and for the `test` plus `test.failing` pair, each through
`blink check` with no cc step.

The E-number moved. Q1 voted for "the E08xx group, next free number". At vote time that was E0850. Since then
another approved, unmerged branch (the one that specifies `BareFieldAddress`) took E0850. The next free number
after a fresh check is E0851. The ruling is the range, not the number.

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in
independent-proposal, debate, vote rounds. Phase A and Phase B are excerpted from each panelist's own text. Phases
C and D are quoted in full from each panelist's file, without its heading and files-read lines.

#### Phase A — Independent proposals

Five seats proposed a new code. Minimalism proposed to widen E1016.

- **Systems:**

> **Position.** Add a new code, `DuplicateTestName` (next free code in the E10xx module block; E1023 if free). Do not widen E1016.

> **Why not E1016.** E1016 says a binding is declared twice in a value or type namespace. A test binds nothing. Widening E1016 adds a third namespace to §2.12.1 and puts a thing in module scope that no code can name. A separate code keeps E1016's text and its `--explain` entry true.

- **Web/Scripting:**

> Add `DuplicateTestName` (E0850). Do not widen E1016.

> - "Same name" means the same string value, after escapes resolve. `test "a\u{62}"` and `test "ab"` are duplicates. A dev reads the name that the runner prints, and the runner prints the value.

> Today `blink check` prints `ok` and cc fails on generated C. A dev must never see a C error for a Blink mistake.

- **PLT:**

> **Typing view.** A test name is not a binding. It is not in the value namespace and not in the type namespace (§2.2), and no expression can refer to it. So `fn a()` and `test "a"` rightly coexist (checked: they build today).

> **One name space for `test` and `test.failing`.** Both register one entry under one `name` key in the JSON record (§8.10). Two spaces would give two records with the same key and `file`. One space.

- **DevOps:**

> A test name is a key. The runner, `--filter`, and every JSON `test` record (§8.10: `file` + `name`) use it as the only identity of a test. Two tests with one name make that identity ambiguous, so the compiler rejects the pair at `blink check`, not later in `cc`.

> **Pass.** Run it in the same typecheck pass as E1016. It then appears in `blink check`, in the LSP as a squiggle on the literal, and `blink test` never reaches `cc`.

- **AI/ML:**

> **Code.** A new code, `DuplicateTestName`, in the E08xx type-checking range next to E0827 and E0835 (number set when the catalog row is written). Do not widen E1016.

> Tests are the code an LLM writes most in bulk. It copies and edits test blocks, so duplicate names will happen often. A check-time error with a named code and a rename help gives the model a one-step repair.

- **Minimalism** *(the one seat that proposed no new code)*:

> **Position.** Do not add a code. Widen `DuplicateModuleBinding` (E1016). A test name is a declared name in module scope, so the existing rule fits.

> - No new code means no new catalog entry, no new explain text and no new row in the tools that list codes. One rule, one code, one message form.

#### Phase B — Debate highlights

Each seat read all six proposals. Minimalism moved to a new code. Systems, PLT and DevOps moved from E10xx to E08xx for the number
range, which became Q1 (Web/Scripting and AI/ML had proposed E08xx already). Excerpts:

- **Minimalism** *(moved on V1)*:

> **Change of position: I drop min-1 on V1.** I now support a new code `DuplicateTestName`.

> Reason: devops is right that E1016 is defined as a clash in the value and type namespaces. If I widen it, I must change its catalog row, its `blink explain` text and the §2.2 sentence, and the code then covers two unlike rules.

- **Minimalism** *(on the range; kept E10xx)*:

> **V1a.** Number in the E10xx module-scope group, beside E1016 (sys, plt, devops). The rule is about names in module scope, and the group already holds the sibling rule. Take the next free number in that group. Do not put it in E08xx: that group is about assertion and skip misuse inside a test body, not about names.

- **DevOps** *(moved on V1a)*:

> **V1a. Range: I change my position.** I wrote "next free E10xx". After reading web and aiml I support the E08xx test group, beside E0827 and E0835. A user who sees a test diagnostic looks for the other test codes.

> E10xx is the module-resolution group, and this check is not name resolution.

- **Systems** *(moved on V1a)*:

> **V1a. I change from E1023 to the test group.** Of the five who want a new code, web and aiml put it by E0827/E0835. A reader who looks for test errors goes to that group. The number has no hardware meaning. I accept E08xx. The moderator picks the number that is free.

- **PLT** *(moved on V1a)*:

> **V1a: number range.** I change my mind in part. I put it in the E08xx test group, beside E0827 and E0835, not beside E1016. Reason: the catalog groups by the construct, and those two codes already cover test blocks.

- **PLT** *(on the third namespace, against widening E1016)*:

> A namespace exists so that a use site resolves a name in it. A test name has no use site: nothing looks it up.

- **Systems** *(on V5; the body of the later test)*:

> **V5. I accept aiml's point and add one condition.** Check the later body (its other errors show). Then drop the later test from lowering and from the runner list, so no C symbol clashes. The two are compatible: typecheck the body, then do not lower it. The test needs a case with a second error in the duplicate's body.

- **DevOps** *(on the label, which became Q6)*:

> **Add to the vote.** Whether the first declaration appears as a secondary label (my text and E1016's form) or only as a note. I prefer the label: the LSP shows it as related information, and a note does not.

- **DevOps** *(on V4, two modules; became Q3)*:

> **V4. Spec text on two modules.** Keep one sentence. Without it, a reader sees "unique within their module" and cannot tell if another module may reuse a name. The ticket asked exactly this. It costs one sentence. Plt and I agree.

- **Systems** *(on V4, against)*:

> **V4. No text on other modules.** A statement that "two modules may reuse a name" is a rule the compiler has no check for and no need to check. The JSON `file` key already says it.

- **AI/ML** *(on V6, against a line in §8.10.6; became Q4)*:

> **V6. Other places.** One invalid example in §2.20, as devops says. No line in §8.10.6: §2.20 already says `test.failing` shares the name space, and a second statement can drift.

- **Web/Scripting** *(on V6, for it)*:

> **V6:** one invalid example in §2.20 (devops), plus my one line in §8.10.6. Not min's §2.2 change.

All six reported "STATUS: stable, ready to vote".

#### Phase C — Final vote (silent ballot)

Each seat voted alone, with a letter, a reasoning and a concern.

- **Q1: The number range of `DuplicateTestName`** (A 5-1, Minimalism dissent). A: E08xx beside the test codes E0827 and E0831-E0835 (next free then: E0850). B: E10xx beside E1016 (E1023).
  - **Systems:** A (E08xx, next free E0850)
    > Reasoning: The check is a test rule, not a name-resolution rule. It does not bind a name or look one up. The catalog and `blink explain` read by construct, and the other test codes (E0827, E0831-E0835) already sit in E08xx. The number has no cost on the hardware side, so I follow where a reader looks.
    > Concern: The catalog header says E08xx is "FFI", so the group label stays wrong and a reader may still miss the code.
  - **Web/Scripting:** A (E08xx, next free E0850)
    > Reasoning: A dev who greps the catalog for "test" finds E0827 and E0831-E0835 in one place, and the new code belongs with them. The E10xx group is "Module resolution / imports", and a duplicate test name is not a resolution error. A dev meets this code only after a copy-paste of a test block, so where it sits matters for the explain lookup, not for learning.
    > Concern: The code sits far from E1016, so a dev who knows the duplicate-binding error may not link the two; the §2.20 text must name both.
  - **PLT:** A (E08xx, next free E0850)
    > Reasoning: The rule is a uniqueness check on a registry key, not name resolution, so it belongs with the construct it serves. The test codes E0827 and E0831-E0835 already sit in E08xx, and the catalog groups by construct in practice. The E1016 definition stays true either way, because the code is new.
    > Concern: The catalog header labels E08xx "FFI", so the range label and the contents disagree until the category column or range table is corrected.
  - **DevOps:** A (E08xx, next free E0850)
    > Reasoning: A user who meets a test diagnostic looks for the other test codes. `blink explain` and the catalog read by group, and E0827 and E0831-E0835 already sit in E08xx. E10xx is module resolution, and this check is not name resolution. The §2.20 rule text can still link to E1016.
    > Concern: E08xx is labelled "FFI" in the catalog category table, so the table must say that the group also holds the test codes, or the catalog looks inconsistent.
  - **AI/ML:** A (E08xx, next free E0850)
    > Reasoning: A model that searches the catalog for test rules finds E0827, E0831-E0835 and this code in one place. E1016's row, help and explain text all describe bindings, and a test name binds nothing. The catalog groups by construct in practice, and these codes already cover test blocks.
    > Concern: The catalog's category column for E08xx reads "FFI", so a reader who goes by category and not by neighbouring rows may still miss it.
  - **Minimalism:** *(dissent)* B (E10xx, next free E1023)
    > Reasoning: The rule is about names declared in module scope, and E1016 is its sibling check. The catalog lists E08xx as "FFI", so the existing test codes there are already misfiled. A new code there adds to the misfiling and sets a pattern. The cost of B is that the code sits away from E0827.
    > Concern: If E08xx wins, the catalog gains another row under a heading ("FFI") that does not describe it, and the group grows by habit instead of by rule.

  Shared concern (Systems, PLT, DevOps, AI/ML): the range table labels E08xx "FFI". The catalog change in this branch makes the range table say that the group also holds the test codes.

- **Q2: The help line** (Phase C: A 2, B 1, C 3; see Phase D and the owner tiebreak). A: `= help: give each test its own name`. B: `= help: rename one of the two tests`. C: `= help: give each test its own name; `blink test --filter` and the test report identify a test by name`.
  - **Systems:** A ("= help: give each test its own name")
    > Reasoning: The help line says what to do. The reason (report and `--filter` key on the name) belongs in `blink explain`. A short fixed line costs the fewest bytes per diagnostic and is the same for every duplicate.
    > Concern: With C, a user who does not know why names must be unique gets no hint in the diagnostic itself, and has to run `blink explain`.
  - **Web/Scripting:** C
    > Reasoning: "give each test its own name; `blink test --filter` and the test report identify a test by name" tells the dev what to do and why in one line. A JS or Python dev expects duplicate test names to be legal (Jest, pytest), so the reason removes the "why is this an error?" question at once. The extra clause costs a few tokens once per error.
    > Concern: The long help line repeats on every one of the N-1 diagnostics for a file with many copies, which adds noise.
  - **PLT:** C (help names the two consumers)
    > Reasoning: The help line should state the invariant that makes the rule necessary: the name is the identity of a test in `--filter` and in the report. That makes the error self-justifying where the fix is not obvious, and one clause costs little. The `blink explain` text can carry the long form.
    > Concern: A long help line repeats in every diagnostic, so N-1 duplicates print the same sentence N-1 times.
  - **DevOps:** C ("= help: give each test its own name; `blink test --filter` and the test report identify a test by name")
    > Reasoning: The help line is the one place the author sees why the name must be unique, at the moment of the error. The reason names the two tools that break, so the author sees the cost of a copy. The extra clause is short and the same for every case.
    > Concern: The long line costs tokens on every diagnostic and may wrap in narrow terminals; the `blink explain` text must carry the full reason too.
  - **AI/ML:** B ("= help: rename one of the two tests")
    > Reasoning: Every diagnostic a model reads costs tokens, and the repair is the same each time. The reason (report and `--filter` key on the name) is stable and belongs once in the `blink explain` text. A short imperative gives one clear repair step.
    > Concern: With three or more copies "the two tests" is slightly off, and a long help line (C) repeated in each of N-1 diagnostics adds token cost for no new repair information.
  - **Minimalism:** A ("give each test its own name")
    > Reasoning: A help line says what to do. The reason is one clause in the spec and the `blink explain` text. Every diagnostic that repeats the reason costs tokens for a reader who already has the cause in the message.
    > Concern: If C wins, the help text names `--filter` and the report format, and it goes stale when the report changes.

- **Q3: A spec sentence "Two modules may use one test name."** (B 4-2 in Phase C; 6-0 in Phase D). A: add it. B: no such sentence.
  - **Systems:** B (no sentence on two modules)
    > Reasoning: "Unique within their module" already limits the rule. A sentence "two modules may reuse a name" states a permission that the compiler does not check and has no need to check. It ties the spec to the JSON `file` key, which can change.
    > Concern: A reader may guess a package-wide rule, and the winning option leaves that guess open.
  - **Web/Scripting:** B
    > Reasoning: "Within their module" already answers the question, and one file is one module. A sentence about other modules raises a question nobody asked, and it states a rule the compiler never checks. The JSON `file` key already separates modules.
    > Concern: A reader who wonders about a package-wide rule has no explicit answer and may file a ticket.
  - **PLT:** A (add "Two modules may use one test name.")
    > Reasoning: "Unique within their module" is a scope claim, and a scope claim is only complete when it says what lies outside the scope. The ticket asked this question directly. The sentence states the domain of the key and rules out a package-wide reading.
    > Concern: The sentence has no compiler check behind it, so it can go stale if the report format changes; it must be re-read when the record schema changes.
  - **DevOps:** A (add "Two modules may use one test name.")
    > Reasoning: "Unique within their module" does not say whether another module may reuse a name, and the ticket asked this exactly. A reader or an LSP user who sees a duplicate across files needs the answer in the spec. The JSON record has `file`, so the sentence matches the format.
    > Concern: If the record format or the package-wide `--filter` behaviour changes, the sentence must change with it.
  - **AI/ML:** B (no sentence on two modules)
    > Reasoning: "Unique within their module" already scopes the rule, and one file is one module. A sentence about other modules adds a case the reader must hold in mind and a claim the compiler never checks. Fewer rules to learn means fewer decision points.
    > Concern: A reader may still wonder whether a package-wide rule exists, and the ticket asked exactly this.
  - **Minimalism:** B (no sentence)
    > Reasoning: "Unique within their module" already limits the rule to one module. A sentence that says what the rule does not cover is a second rule to keep true, and the compiler does not check it.
    > Concern: If A wins, a reader may take the sentence to promise cross-module behavior (for example, how `--filter` treats two matches), which the spec does not define.

- **Q4: A line in §8.10.6 that `test.failing` shares the name space** (A 4-2 in Phase C; A 5-1 in Phase D). A: add the line. B: no line; §2.20 states it once.
  - **Systems:** A (line in §8.10.6)
    > Reasoning: `test.failing` is a second form with its own section. A reader of §8.10.6 should learn there that it shares the name space and not need §2.20. The line is one clause and states a fact that the check enforces.
    > Concern: Two statements of one rule can drift if the name space rule changes later.
  - **Web/Scripting:** A
    > Reasoning: A dev who reads the `test.failing` section sees one more form of test, and should learn there that it shares the name. Nobody reads §2.20 first. The line is one short sentence that points to the rule.
    > Concern: Two statements of one rule can drift apart if §2.20 changes.
  - **PLT:** A (line in §8.10.6)
    > Reasoning: `test.failing` is a second registration form, and the soundness of "one key per test" depends on both forms feeding the same space. A reader of §8.10.6 should see that at the point where the form is defined. The risk of drift is small, because both statements are one clause and one test covers both.
    > Concern: Two statements of one rule can diverge in a later edit.
  - **DevOps:** A (add the line in §8.10.6)
    > Reasoning: A reader of the `test.failing` section should learn the name rule there, without a jump to §2.20. The LSP hover on `test.failing` can link to that section. One line costs little.
    > Concern: Two statements of one rule can drift; a doc check should compare them.
  - **AI/ML:** B (no line in §8.10.6)
    > Reasoning: §2.20 states the shared name space once. A second statement in §8.10.6 can drift from the first, and a model then sees two sources. One source of truth is easier to learn from the spec alone.
    > Concern: A reader who goes straight to §8.10.6 for `test.failing` may miss the shared name space.
  - **Minimalism:** B (no line)
    > Reasoning: §2.20 states the shared name space once. A second statement in another section can drift from the first. A reader of §8.10.6 can follow one link.
    > Concern: If A wins, two sections state one rule, and a later change to one leaves the other wrong.

- **Q5: The later test's body after the error** (A 6-0). A: typecheck the later body, then leave it out of lowering and the runner list. B: drop the later test without checking its body.
  - **Systems:** A
    > Reasoning: I moved to this form in Phase B. Checking the body shows its other errors in one run. Leaving the test out of lowering and the runner list means no C symbol clashes and no second test runs under a name that is already taken. This needs a test case with a second error inside the duplicate's body.
    > Concern: The check path must not bind the later name, or a body error may report against the wrong test; two code paths (check, skip lowering) need to stay in step.
  - **Web/Scripting:** A
    > Reasoning: A dev who fixes the name error and then meets a second error in the same body loses a full edit cycle. Checking the body shows all errors in one run, as every other error path in the compiler does. Dropping the test from lowering and the runner list costs nothing for the user.
    > Concern: The check-then-drop split is an extra rule in the compiler, and a test must cover a second error in the duplicate's body.
  - **PLT:** A
    > Reasoning: A naming error says nothing about the body, so the body is still well-formed input for the checker. Skipping the check hides real errors behind a naming error and forces a second round trip. Leaving the test out of lowering keeps the C symbol set free of clashes.
    > Concern: The checker now processes a body that has no registered name, so any pass that assumes every checked test has an entry in the registry needs a guard.
  - **DevOps:** A
    > Reasoning: The author must see all real errors in one `blink check` run. A duplicate name must not hide a type error in the later body. No code generates after an error, so the drop from lowering is only a guard against the C symbol clash.
    > Concern: A body that refers to the poisoned test or its name could give a follow-on error; the test suite needs a case with a second error in the duplicate body.
  - **AI/ML:** A
    > Reasoning: A model repairs best when one run shows all errors. Hiding body errors behind a naming error costs a second repair round. Dropping the later test from lowering after the check keeps C symbols from clashing.
    > Concern: Checking a body that the compiler will drop adds a path that needs its own test (a second error inside the duplicate's body).
  - **Minimalism:** A
    > Reasoning: I preferred B in Phase B for fewer moving parts. On a second look, B needs a special skip of the body in the checker. A needs only that the later test is not registered, and the body takes the normal path. A also keeps real errors in the body from hiding behind a naming error.
    > Concern: The "leave out of lowering" step needs a test with a second error in the duplicate's body, or the two steps drift apart.

- **Q6: How the diagnostic marks the first declaration** (A 6-0). A: a secondary label at the first name literal. B: a note with the location.
  - **Systems:** A
    > Reasoning: It matches the E1016 sample in §2.2 (02_syntax.md:968), so tools handle one shape. The LSP shows a label as related information; a note with a location does not give that. The cost is none at run time.
    > Concern: With two names far apart in a long file, the label forces a multi-line snippet, which is longer output than a one-line note.
  - **Web/Scripting:** A
    > Reasoning: A secondary label shows both places in the terminal and in the editor, and it matches the E1016 sample in §2.2. A dev who sees a squiggle on the second name can jump to the first at once. A plain note gives a location the dev must find by hand.
    > Concern: Two labels on a very long name literal can make the rendered snippet wide.
  - **PLT:** A
    > Reasoning: The label follows the E1016 form in §2.2 and keeps the first declaration a structured span, not prose. The LSP can then present it as related information. A note with a location string carries the same fact in a form no tool can use.
    > Concern: When the first and later names sit far apart, the rendered snippet needs an elision, and the label must still survive in the JSON output.
  - **DevOps:** A
    > Reasoning: The LSP shows a secondary label as related information with a clickable location; a note line does not. It matches the E1016 sample in §2.2 (sections/02_syntax.md:968), so tools reuse one rendering path. The author sees both spans in the source view.
    > Concern: A label on a far-away first test produces a long multi-line snippet in the terminal; the renderer must elide the lines between.
  - **AI/ML:** A
    > Reasoning: It matches the E1016 sample in §2.2, so a model that has seen one predicts the other. The LSP shows a label as related information, and a note does not. One diagnostic shape for both duplicate rules is fewer patterns to learn.
    > Concern: Labels in a different file or far-apart lines render poorly in a terminal, but the first test is always in the same file here, so the risk is low.
  - **Minimalism:** A
    > Reasoning: E1016 in §2.2 already uses a secondary label, so A adds no new form. The LSP shows a label as related information. A second form for the same job would add surface.
    > Concern: If B wins, one duplicate-name diagnostic uses a note and the other uses a label, and tools must handle both.

#### Phase D1 — Focused debate (Q2, Q3, Q4)

Q1, Q5 and Q6 were closed. Each seat answered the strongest argument against its own Phase C vote.

- **Systems** (Q2 keep A, Q3 keep B, Q4 keep A). Note: Systems worked from the D1 excerpts of the Phase C reasoning, not from the full Phase C files.
  > Q2. Keep A. Strongest argument against: web and plt say a JS or Python dev expects duplicate names to be legal, so the help line must say why the name is a key. This is true for the first-time reader. But the primary message already says "declared twice", and the label marks both places. The fix is the same for every reader, and the reason is one `blink explain` away. C also costs bytes on each of N-1 diagnostics. It also names `--filter` and the report format in compiler output, so the text goes stale when those change (min's point). I do not change my vote. If C wins, I ask that the clause name the key in general terms ("a test is identified by its name") and not the two tools.
  >
  > Q3. Keep B. Strongest argument against: plt and devops say a scope claim is complete only when it says what lies outside, and the ticket asked this question. That is fair. But "unique within their module" plus "one file = one module" (§10.1) already puts a second module outside the rule. The added sentence grants a permission, and a permission needs a defined behaviour behind it. The spec has none for cross-module `--filter` matches (min's concern). I keep B. The ticket gets its answer from the decision record and the §2.20 rule text, not from a new spec promise.
  >
  > Q4. Keep A. Strongest argument against: aiml and min say a second statement can drift, and a model then sees two sources. All four A voters, me included, name this risk. I answer with what I voted for in Q5/Phase B: a test through `blink check` for the `test` plus `test.failing` pair. That test fails if either statement stops being true. The cost of one clause is lower than the cost of a reader of §8.10.6 who assumes `test.failing` has its own name space. I keep A. I would accept a cross-reference ("same name space as `test`, §2.20") in place of a restated rule, as that cannot drift in content.
- **Web/Scripting** (Q2 keep C, Q3 keep B, Q4 keep A)
  > Q2. Keep C. Strongest argument against: min's staleness point and sys's "the reason belongs in `blink explain`". If the help line names `--filter` and the report, it goes stale when the report changes; and N-1 diagnostics repeat the long text. Answer: staleness is bounded. `--filter` and the per-test `name` key are core to `blink test` (sections/06 §8.10), and the help line shows up only on a copy-paste error. The error is the one moment a Jest or pytest dev asks "why is this illegal?", and `blink explain` is a second step most devs never take. The repeat cost is real but small, since N is usually 2. If the report changes, the help line is one string to edit in the same change. I do not change my vote.
  >
  > Q3. Keep B. Strongest argument against: plt's "a scope claim is complete only when it says what lies outside", and the ticket asked this question directly. Answer: "unique within their module" is the complete rule. A sentence that grants permission to other modules adds a claim the compiler never checks, and min's concern is right that it invites readers to expect defined cross-module behavior (for example `--filter` over two matches) that the spec does not define. The ticket's two-file question has the answer "one file is one module", which §2.20 Test Scope already states at :2591. I do not change my vote.
  >
  > Q4. Keep A. Strongest argument against: aiml's drift point. Two statements of one rule can differ later, and a model then sees two sources. Answer: I accept the risk. A dev who reads §8.10.6 for `test.failing` does not read §2.20 first, and without the line may assume `test.failing("a", ...)` can sit beside `test "a"` (Jest-style expectation). Drift risk is small: one clause, and the test pair from the ballot (`test` plus `test.failing` through `blink check`) fails if either text becomes wrong. I do not change my vote.
  >
  > All three votes stay as cast.
- **PLT** (Q2 keep C, Q3 change to B, Q4 keep A)
  > Q2. Keep C. Strongest argument against: min's. A help line that names `--filter` and the report ties a diagnostic to tool behavior, and it goes stale when the report changes. It also repeats on each of the N-1 diagnostics. Answer: the staleness risk is real but small. The line names two consumers, not a format, and any change that makes a name stop identifying a test would remove the rule itself. The repeat cost is a few tokens on a rare error. The reason is the part that answers a Jest or pytest author, for whom duplicate names are legal. I keep C. If C loses, A is my second choice, not B: B's "the two tests" is wrong for three copies.
  >
  > Q3. I change to B. Strongest argument against my A: the sentence states a permission the compiler does not check, and it ties the spec to the report's `file` key. Min's concern adds that it can read as a promise about cross-module behavior, such as how `--filter` treats two matches. The spec does not define that. Answer: I concede. "Unique within their module" already fixes the domain of the key. A rule that constrains one scope does not constrain the others, and no other rule in §2.2 or the E1016 text adds such a sentence. My "complete scope claim" argument holds for the rule, and the rule already makes it. The sentence adds no information and one more thing to keep true. Four seats agree with that, so I vote B.
  >
  > Q4. Keep A. Strongest argument against: aiml's. Two statements of one rule can drift, and a model then sees two sources. Answer: sys, web and devops share my drift concern, and it is the cost I named. The §8.10.6 line is where a reader learns what `test.failing` does, and the name rule is part of that. The fix for drift is cheap: the line should point to §2.20 and state no more than "shares the name space of `test` (§2.20)". Then §2.20 holds the rule and §8.10.6 holds a cross-reference, which is the one-link position min asks for. I keep A with that wording.
- **DevOps** (Q2 keep C, Q3 keep A, Q4 keep A)
  > Q2. Vote stays C. Strongest argument against: min's. The help line names `--filter` and the report, so it goes stale when the report changes. It also repeats on each of N-1 diagnostics (aiml, sys: tokens, and `blink explain` is the place for reasons). Answer: Both facts are in the spec today. §8.10 fixes `name` as the test key, and `--filter` matches on it. If the report changes, the text changes in the same commit as the spec, and a diagnostic-text test catches a miss. N is 2 in nearly every real case, so the repeat cost is one line. A and B give the fix but not the reason. A Jest or pytest user expects duplicates to be legal, and sees only a rule with no cause. I do not change my vote. I accept A if C loses; I rank B last, because "the two tests" is wrong for three copies.
  >
  > Q3. Vote stays A. Strongest argument against: sys and aiml. The sentence states a permission that the compiler does not check, and it ties the spec to the JSON `file` key. Answer: The sentence is a scope claim, not a check. "Unique within their module" leaves open a package-wide rule, and the ticket asked this question directly. A spec that stays silent leaves the reader to guess, and an LSP user who sees the same name in two files has no written answer. The key `file` is already in §8.10; the sentence does not need it, and it does not name it. If the report format changes, the scope of uniqueness is still the module. I do not change my vote. If the panel prefers B, the catalog row for the new code should say "within one module" in its description, so the answer exists once.
  >
  > Q4. Vote stays A. Strongest argument against: aiml and min. Two statements can drift, and a reader can follow one link. Answer: Drift is real, and all four A voters named it. One test that uses `test` plus `test.failing` of one name, through `blink check`, already exists in the agreed test list, and it fails if either statement stops being true. A reader of §8.10.6 who sees `test.failing("a", ...)` has no reason to open §2.20. A one-clause line with a link costs less than the question it prevents. I do not change my vote.
- **AI/ML** (Q2 change to A, Q3 keep B, Q4 change to A)
  > Q2. Strongest argument against B: web's. A JS or Python dev expects duplicate test names to be legal, so a bare "rename" leaves the question "why is this an error?". The reason, in the same line, answers it at once. Against that: the message already says "declared twice", and the reason belongs in `blink explain`. The line repeats in N-1 diagnostics, and min is right that it goes stale if the report format changes. I also see a flaw in my own option: "the two tests" is wrong for three copies. B cannot win (1 vote). A keeps what I wanted, a short fixed imperative with no stale claim, and it has no "two" problem. **I change to A**: "= help: give each test its own name".
  >
  > Q3. Strongest argument against B: plt's. A scope claim is complete only when it says what lies outside the scope, and the ticket asked this question directly. Against that: the sentence has no compiler check behind it and ties the spec to the JSON `file` key (sys), and min warns that readers may take it as a promise about `--filter` across modules. A model that reads "two modules may use one test name" gets a new fact to hold, but a model that reads only "unique within their module" gets the correct reading from the one-file-one-module rule. The ticket's two-file question is answered by §10.1 already. **I keep B.**
  >
  > Q4. Strongest argument against B: web's, "Nobody reads §2.20 first." This is an aiml point too. `blink llms --topic` and spec retrieval load by section. A model that loads only §8.10.6 to write a `test.failing` would not see the shared name space and would reuse a name. That costs a failed `blink check` and a repair round. My drift concern is real but small: both statements are one clause, and plt says one test covers both. **I change to A**, on one condition: add one test that fails if the two statements disagree, and keep the §8.10.6 line a pointer to §2.20 in wording ("see §2.20"), not a restatement of the rule.
- **Minimalism** (Q2 keep A, Q3 keep B, Q4 keep B)
  > Q2. Help line. Vote stays A. Strongest argument against: web, plt and devops say the author needs the reason at the moment of the error, because a Jest or pytest user expects duplicate names to be legal. I answer that the message already states the fault ("declared twice") and the label shows both places. The reason clause names `--filter` and the report, two things the diagnostic does not own. The three C voters each name the cost on their own option: it repeats on N-1 diagnostics and may wrap. `blink explain` carries the reason once, for the author who wants it. I do not change my vote.
  >
  > Q3. Sentence on two modules. Vote stays B. Strongest argument against: plt says a scope claim is complete only when it says what lies outside, and the ticket asked this. The reply is that "unique within their module" already gives the answer by its scope, and one file is one module. The proposed sentence is a permission with no check behind it. It ties the spec to cross-module behavior (`--filter` matches, the `file` key) that the spec does not define. I do not change my vote. If the panel wants the ticket question answered in text, the right place is the catalog row, not the rule.
  >
  > Q4. A line in §8.10.6. Vote stays B. Strongest argument against: web says nobody reads §2.20 first, and four seats say the risk of drift is one clause that one test covers. This is the strongest of the three. I still hold B, because four voters name drift as the concern on their own option, and the test covers behavior, not the wording of two sections. A cross-reference in §8.10.6 ("see §2.20 for test names") gives the reader the path without a second statement of the rule. I count that as inside B, not as a new option. If the panel prefers A, I ask that it be written as that pointer and not as a restatement.

#### Phase D2 — Silent re-vote (Q2, Q3, Q4)

Each seat voted alone after D1.

| Question | Votes | Result |
|----------|-------|--------|
| Q2 help line | A: Systems, AI/ML, Minimalism. C: Web/Scripting, PLT, DevOps | 3-3 → owner broke tie for A. The owner gave no reason. |
| Q3 sentence on two modules | B: all six (DevOps moved from A; PLT moved from A in D1) | B 6-0 |
| Q4 line in §8.10.6 | A: Systems, Web/Scripting, PLT, DevOps, AI/ML. B: Minimalism | A 5-1 (Minimalism dissents) |

- **Systems**
  > Q2. Vote: A ("= help: give each test its own name"). Reasoning: The help line says what to do. The message already says "declared twice" and the label shows both places, so the fault is plain. The reason (the name is the key for `--filter` and the report) goes in `blink explain`. A fixed short line costs the fewest bytes on each of the N-1 diagnostics, and it names no tool whose behaviour can change. Concern: If C wins, the compiler output names `--filter` and the report format, and it goes stale when they change.
  >
  > Q3. Vote: B (no sentence on two modules). Reasoning: "Unique within their module" plus "one file = one module" (§10.1) already puts other modules outside the rule. The sentence would grant a permission, and the spec defines no behaviour for it (for example, `--filter` over two matches across files). The compiler has no check for it. Four seats and plt, after conceding in D1, agree. Concern: A reader may guess a package-wide rule, and B leaves that guess open; the catalog row text ("within one module") can answer it.
  >
  > Q4. Vote: A (add the line in §8.10.6). Reasoning: A reader who loads only §8.10.6 to write `test.failing` must learn there that it shares the name of `test`. I want the line as a pointer, "shares the test name space (§2.20)", with the rule stated once in §2.20. The `test` plus `test.failing` pair through `blink check` fails if either text stops being true. Concern: Two statements of one rule can drift; a pointer limits this, but a later edit to §2.20 can still leave §8.10.6 stale.
- **Web/Scripting**
  > Q2. Vote: C. Reasoning: A JS or Python dev expects duplicate test names to be legal (Jest, pytest). The help line is the one moment the dev asks "why is this illegal?", and `blink explain` is a second step most devs never take. The clause names the two tools that break, and N is 2 in nearly every real case, so the repeat cost is one line. A is my second choice; B is last because "the two tests" is wrong for three copies. Concern: The long line repeats on each of the N-1 diagnostics and goes stale if `--filter` or the report changes, unless the same commit edits the string and a diagnostic-text test catches a miss.
  >
  > Q3. Vote: B. Reasoning: "Unique within their module" plus "one file = one module" (§2.20 Test Scope, :2591) already answers the ticket. A sentence that grants permission to other modules has no compiler check behind it. It also invites readers to expect defined cross-module behaviour, such as `--filter` over two matches, which the spec does not define. plt moved to B in D1 for the same reason. Concern: A reader who wonders about a package-wide rule gets no explicit answer and may file a ticket.
  >
  > Q4. Vote: A. Reasoning: A dev who reads the `test.failing` section does not read §2.20 first. Without the line, that dev may assume `test.failing("a", ...)` can sit beside `test "a"`, as in Jest. I want the line as a pointer ("shares the name space of `test`, §2.20") and not a restatement, which answers aiml's and min's drift concern. The `test` plus `test.failing` pair test through `blink check` fails if either text stops being true. Concern: Two statements of one rule can drift apart if §2.20 changes, even with the pointer wording.
- **PLT**
  > Q2. Vote: C. Reasoning: The help line states the invariant that makes the rule necessary: the test name is the key that `--filter` and the report use to identify a test. A Jest or pytest author expects duplicate names to be legal, so the repair alone leaves the "why" open at the moment of the error. The line names two consumers, not a format. If A wins instead, I accept it as my second choice; I rank B last because "the two tests" is wrong for three copies. Concern: If A wins, the diagnostic gives the fix without the reason, and the author has to run `blink explain` to learn why a name must be unique.
  >
  > Q3. Vote: B. Reasoning: "Unique within their module" plus "one file = one module" already fixes the domain of the key. A constraint on one scope does not constrain the others, and no sibling rule (E1016 in §2.2) adds such a sentence. The proposed sentence grants a permission with no compiler check behind it, and it ties the spec to cross-module behaviour (`--filter` matches, the `file` key) that the spec does not define. Concern: A reader may still guess a package-wide rule, and the winning option gives no written answer to the ticket's two-file question outside the decision record.
  >
  > Q4. Vote: A. Reasoning: `test.failing` is a second registration form, and "one key per test" holds only if both forms feed the same name space. A reader of §8.10.6 should see that where the form is defined. I vote A on the condition that the line is a cross-reference, not a restatement: "shares the name space of `test` (§2.20)". Then §2.20 holds the rule and content cannot drift; the `test` plus `test.failing` pair test covers behaviour. Concern: If B wins, a reader or model that loads only §8.10.6 may assume `test.failing("a", ...)` can sit beside `test "a"`, and meet the error only at `blink check`.
- **DevOps**
  > Q2. Vote: C. Reasoning: The help line is the one place the author sees the cause at the moment of the error. A Jest or pytest user expects duplicate names to be legal, and "give each test its own name" alone leaves "why?" open. The clause names the two tools that break, and N is 2 in nearly every real case, so the repeat cost is one line. Concern: If A wins, the author gets the fix but not the cause, and must run `blink explain` to learn why a name is a key; I rank A second and B last ("the two tests" is wrong for three copies).
  >
  > Q3. Vote: B. Reasoning: I change from A. The sentence grants a permission that the compiler does not check and the spec does not back with defined cross-module behavior (for example `--filter` over two matches). "Unique within their module" plus "one file = one module" (§10.1) already puts a second module outside the rule. The ticket's question gets its answer from the `blink explain` text and the catalog row for the new code, which should say "within one module". Concern: A reader who wonders about a package-wide rule finds no explicit sentence in §2.20, so the explain text and catalog row must carry the answer.
  >
  > Q4. Vote: A. Reasoning: A reader of the `test.failing` section has no reason to open §2.20, and the LSP hover on `test.failing` links to its own section. The line must be a pointer, not a restatement, for example "shares the name space of `test` (§2.20)", so that §2.20 holds the rule and the content cannot drift. The agreed `test` plus `test.failing` check test fails if the behavior stops matching. Concern: If A wins in the form of a restated rule and not a pointer, two statements of one rule drift apart in a later edit.
- **AI/ML**
  > Q2. Vote: A ("= help: give each test its own name"). Reasoning: The help line gives one repair step, and the message and the label already state the fault. A fixed short line costs the fewest tokens on each of the N-1 diagnostics and names no tool whose behavior may change. The reason (name is the test key in `--filter` and the report) goes in the `blink explain` text once. Option B is out: "the two tests" is wrong for three copies. Concern: With C, the line repeats a claim about `--filter` and the report in every diagnostic, and it goes stale when those change.
  >
  > Q3. Vote: B (no sentence). Reasoning: "Unique within their module" plus "one file = one module" already puts other modules outside the rule. A permission sentence adds a fact to hold and a claim the compiler never checks. plt conceded this in D1; the cross-module `--filter` behavior is not defined in the spec. Concern: A reader may still guess a package-wide rule, so the catalog row or `blink explain` text should say "within one module".
  >
  > Q4. Vote: A (add it, worded as a pointer, not a restatement). Reasoning: Spec retrieval loads by section. A model that loads only §8.10.6 to write a `test.failing` would not see the shared name space and would reuse a name, which costs a failed `blink check` and a repair round. I change from my Phase C vote on this ground. The line should read as a cross-reference ("same name space as `test`, see §2.20") so §2.20 stays the only statement of the rule and the text cannot drift in content. Concern: If the line restates the rule and not just points to §2.20, the two sections can drift and a model sees two sources.
- **Minimalism**
  > Q2. Vote: A ("= help: give each test its own name"). Reasoning: The help line says what to do. The message already says "declared twice" and the label shows both places. The reason names `--filter` and the report, which the diagnostic does not own, and it repeats in each of N-1 diagnostics. `blink explain` carries the reason once. Concern: If C wins, the help text ties compiler output to `--filter` and the report format, and it goes stale when they change.
  >
  > Q3. Vote: B (no sentence on two modules). Reasoning: "Unique within their module" plus "one file = one module" already puts other modules outside the rule. The sentence grants a permission with no check and no defined behavior behind it, such as `--filter` over two matches. Fewer statements means fewer things to keep true. plt moved to B in D1, so this is 5-1 or better. Concern: A reader may still guess a package-wide rule, and the ticket asked this question.
  >
  > Q4. Vote: B (no line in §8.10.6). Reasoning: §2.20 states the shared name space once. I still hold B, because a second statement of one rule is a second place to keep true. A bare cross-reference ("see §2.20 for test names") sits inside B and answers web's and aiml's retrieval point. If A wins, I ask that the line be that pointer and not a restatement, as sys, plt, devops and aiml also ask. Concern: If A wins, two sections state one rule, and a later edit to one leaves the other wrong.

### Dissents

- **Minimalism, Q1** (E10xx beside E1016, next free E1023). In Phase C: "The rule is about names declared in module scope, and E1016 is its sibling check. The catalog lists E08xx as "FFI", so the existing test codes there are already misfiled. A new code there adds to the misfiling and sets a pattern." Concern: "If E08xx wins, the catalog gains another row under a heading ("FFI") that does not describe it, and the group grows by habit instead of by rule."
- **Minimalism, Q4** (no line in §8.10.6). In Phase D2: "§2.20 states the shared name space once. I still hold B, because a second statement of one rule is a second place to keep true." Minimalism asks that, if A wins, the line be a pointer and not a restatement. The panel ruling takes the line as a pointer.

### Reading gaps

- Systems wrote its Phase D1 reply from the D1 excerpts of the Phase C reasoning, not from the full Phase C files. The other five seats read the full files.
- The E-number moved from E0850 to E0851 after the votes (see the Summary). No seat voted on E0851 by number.

### Owner tiebreak

Q2: 3-3 → owner broke tie for A. The owner gave no reason.

### AI-First Review

The tally states no AI-First score, so none is recorded.

### Final Spec

§2.20 states the rule. A test and a `test.failing` of one module share one name space. Two names are the same when their `Str` values are equal after escapes decode. §8.10.6 carries one pointer line: a `test.failing` test shares the name space of `test` (§2.20). The error code is `DuplicateTestName` (E0851) in the E08xx group. No sentence says that two modules may use one test name.

```blink
// INVALID: compile error E0851
test "deposit" { assert(true) }
test "deposit" { assert(true) }    // error[E0851]: test `deposit` is declared twice in module `main`
```

```
error[E0851]: test `deposit` is declared twice in module `main`
 --> src/main.bl:2:6
  |
1 | test "deposit" { assert(true) }
  |      --------- first declared here
2 | test "deposit" { assert(true) }
  |      ^^^^^^^^^ declared again here
  |
  = help: give each test its own name
```
