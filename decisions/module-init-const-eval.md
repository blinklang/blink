[< All Decisions](../DECISIONS.md)

# Module-Level Initializer Is a Const Context — Design Rationale

**Gap:** "Spec: does E0546 ConstEvalPanic apply to const parts of a module-level static initializer? The module-level initializers ruling (decisions/module-level-initializers.md) makes every const expression a static initializer, and panelists described static initializers as total. But 2.21 lists four const-eval contexts and says 'let a = 10 / 0 compiles and panics at run time'. The spec does not say whether a module-level let with a const initializer is a fifth context (compile error E0546) or panics before main. MVCE: let a = 10 / 0 at module scope; fn main() {}."

**Result:**

- **Rule (Q1, 6-0, A):** a module-level `let` or `let mut` initializer is a fifth §2.21 const context. A const expression in it that would panic (integer `/` or `%` by zero, signed `MIN / -1`, overflow) is `ConstEvalPanic` (E0546), not a panic before `main`. This covers the whole initializer, a list or tuple element, a struct field, a variant payload, and a `const` reference (`10 / Z`).
- **Where it lives (Q2, 6-0, A):** a fifth item in the §2.21 list.
- **Lead line (Q3, 6-0, B; 3-3 in Phase C):** "Const expressions are evaluated in five contexts".
- **Item 5 (Q4, 6-0, F):** "**Module-level `let` initializers** — each const expression in a static expression (§2.12.1)".
- **§2.12.1 sentence (Q5, 3-3 → BDFL ruling):** "A const expression in an initializer that would panic is error E0546 (§2.21)." with an example of a top-level `let a = 10 / 0`, a top-level `let xs = [1, 10 / 0]`, and a local `let b = 10 / 0` in `fn main`.
- **Table cell (Q6, 6-0, A):** "Compile time for const parts; program start for the rest".
- **W0704 and W0708 (Q7, 6-0, A):** no change to the catalog rows. Both do not fire in a module-level initializer, because it is a const context.
- **Heading (Q8, 6-0, A):** *Const Evaluation Must Succeed* stays; "four" becomes "five" in the body.
- **Unchanged:** a local `let a = 10 / 0` compiles, warns and panics at run time. A function-literal body is not evaluated at initialization. An out-of-range literal stays E0318.
- **Count change, not a rule change (no vote):** the *Final Spec* line of [Overflow in Literal Arithmetic](let-constant-overflow.md), "\"Const expression\" has meaning only in the four contexts of §2.21", now says "five". Its Q1 (outside the const contexts, overflow compiles, panics at run time and warns) is intact.

**AI-First review:** 5/5 pass.

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in independent-proposal → debate → vote → focused-debate rounds. Each panelist's text below is a verbatim excerpt; `[…]` marks a cut.

#### Phase A — Independent proposals

Every seat proposed the same rule as its first choice. Every seat listed "run-time panic before `main`" as a fallback and opposed it in its own text.

- **Systems:**

> ## sys-1: a static initializer is a fifth const context (compile error E0546)
>
> Every const expression inside a module-level `let` / `let mut` initializer is evaluated at compile time. If that evaluation would panic, the program does not compile: E0546 `ConstEvalPanic`. This covers the whole initializer, a static part of one (list or tuple element, struct field, variant payload), and a `const` reference.
>
> […]
>
> - The C backend emits a module `let` with a const initializer as a static-storage constant (`static int64_t a = 5;`). That needs the value at compile time. The compiler has already folded it. A panic at that point is a compile-time fact. Deferring it to a startup thunk adds code, ordering and a failure site that §2.12.1 says do not exist ("No user code runs before `main`").
> - I said in the prior vote that S promises a total initializer. E0546 is what makes that true. Without it, "total" is false for `let a = 10 / 0`.
> - A panic before `main` is bad for the user: `blink test` shows no test record (r12), a service dies with no log line from `main`, and the panic names a line in a file that no test ran. A compile error shows the location with the normal diagnostic.
>
> […]
>
> - let-constant-overflow.md Final Spec line "has meaning only in the four contexts" needs an amendment: "five". This is a count change. The idea that a const expression is a context-defined notion stays.
>
> Tradeoff: it adds a fifth context, a small cost to learn. It makes a literal `let a = 10 / 0` differ between module and local scope. I accept that: module scope is static, local scope is run-time code.
>
> […]
>
> ## sys-2 (fallback): run-time panic before `main`, document it
>
> […] I oppose this. It makes "no user code before `main`" an approximation, forces a startup thunk in the backend, and makes `blink test` crash before any test record. I list it only because it needs no new context. I would vote sys-1.

- **Web/Scripting:**

> ## web-1 (recommended): a module-level initializer is a fifth const-eval context; a panicking part is E0546
>
> Rule: every const expression inside a module-level `let` / `let mut` / `pub let` initializer is evaluated at compile time. If the evaluation would panic (integer `/` or `%` by zero, signed `MIN / -1`, overflow), the program does not compile. The error is E0546. This holds for the whole initializer, for a static part (list or tuple element, struct field, variant payload), and through a `const` reference.
>
> […]
>
> What the user sees: `error[E0546]: ConstEvalPanic: integer division by zero in the initializer of module binding a`, with a span on `10 / 0`. `blink test` reports the same compile error. Today (r12) a bad module `let` in a test file kills the run with no test record; this removes that.
>
> Warnings: W0704 and W0708 do not fire in a module initializer, because E0546 fires there. This matches the existing line "Not in a const context (E0546 there)". Local `let` and function bodies keep the decided behavior (run-time panic, W0704/W0708).
>
> […]
>
> Tradeoffs (DX): the error shows at build time with a line number. No program starts and then dies before `main` with no stack. A JS/Python dev expects a bad top-level constant to fail loudly and early. One rule: "if it is in a `const` or at module scope, bad math is a compile error."
>
> […]
>
> ## web-2 (fallback): keep the panic before `main`
>
> […] I oppose this: it contradicts "total initializer" and gives the worst DX of the three choices.

- **PLT:**

> ## plt-1: a module-level static initializer is a fifth const context (recommended)
>
> **Rule.** Every const expression inside a module-level `let` / `let mut` / `pub let` initializer is evaluated at compile time. If that evaluation would panic (integer `/` or `%` by zero, signed `MIN / -1`, overflow), the program does not compile. The error is E0546 `ConstEvalPanic`. This covers the whole initializer, a static part (list or tuple element, struct field, variant payload), and a const reference (`10 / Z`). A function-literal body is not evaluated, so `let f = fn() -> Int { 10 / 0 }` still compiles. A local `let` is unchanged: run-time panic, and W0704/W0708 fire.
>
> […]
>
> A panic is divergence, and so an effect. If `let a = 10 / 0` may panic before `main`, then (a) the totality those votes relied on is false, (b) a program can die before any entry point runs, with no handler and no `blink test` record (probe r12: exit 1, no test record), and […] Plt-1 makes totality a theorem: all static expressions are total because the compiler has already evaluated every partial operation in them.
>
> […]
>
> **Prior votes.** The statement "'Const expression' has meaning only in the four contexts" is a premise about literal arithmetic *outside* those contexts. It does not decide module scope, because §2.12.1 already says a static initializer *is* a const expression. This proposal amends the count and says so; it does not contradict Q1 of let-constant-overflow […]. The panel should record that amendment.
>
> […]
>
> ## plt-2: run-time panic before `main` (rejected)
>
> Matches today's gen1 behavior and keeps four contexts. It makes "total" false, so Q3/Q4's reasoning would need rewording, and leaves the unhandled pre-`main` failure. I would vote against it.

- **DevOps:**

> ## devops-1 (recommended): module-level initializers are a fifth const context; E0546 at compile time
>
> Rule. The const-evaluable parts of a module-level `let` / `let mut` initializer are evaluated at compile time. If evaluation would panic (integer `/` or `%` by zero, signed `MIN / -1`, overflow), the program does not compile. The error is `ConstEvalPanic` (E0546). This holds for the whole initializer, for each static part (list or tuple element, struct field, variant payload), and through a `const` reference.
>
> […]
>
> Tooling.
> - `blink test` reports the error at compile time with a span. Today (probe r12) it prints `panic: Int division by zero at src/main.bl:1`, exits 1, and writes no test record. The runtime message names no binding and says nothing about initialization.
> - The LSP shows a squiggle at edit time.
> - W0704 and W0708 do not fire in these positions, because E0546 owns them. This matches the W0708 catalog text "Not in a const context (E0546 there)".
>
> […]
>
> ## devops-2 (fallback): keep four contexts
>
> Keep §2.21's list as "where a const expression is required". Add the E0546 rule only in §2.12.1. Same user result. Weaker: two lists of const contexts. Pure run-time panic (status quo) is rejected: it gives a certain failure only at run time, and it breaks the "total initializer" promise of Q3 and Q4.

- **AI/ML:**

> ## aiml-1: module-level static initializer is a fifth const context (compile error E0546)
>
> Rule: the const parts of a module-level `let` / `let mut` / `pub let` initializer are evaluated at compile time. If that evaluation would panic (integer `/` or `%` by zero, signed `MIN / -1`, overflow), the program does not compile. The error is E0546. This holds for the whole initializer, for each static part (list or tuple element, struct field, variant payload), and through a `const` reference.
>
> […]
>
> AI/ML tradeoffs:
> - One rule: "If the compiler runs it, a panic is an error." A model does not need a split between "static but may panic" and "const but may not."
> - A pre-`main` panic is the worst case for a model's repair loop. The trace shows no `main` frame and no test record. A compile error with a span is the best feedback.
> - Cost: the spec has five contexts to list, and a model must know local `let` differs from module `let`. This difference already exists (§2.12.1).
>
> […]
>
> ## aiml-2 (fallback): no fifth context; run-time panic before `main`
>
> […] I oppose this. It keeps a model's code that compiles and fails with no test record. It contradicts the Q3/Q4 reasons.

- **Minimalism:**

> ## min-1: A module-level initializer is a fifth const context. Add one list item. Delete the pre-main panic.
>
> **Rule.** Every const expression inside a module-level `let` / `let mut` initializer is evaluated at compile time under the same rule as the four contexts. If the evaluation would panic (integer `/` or `%` by zero, signed `MIN / -1`, overflow), the error is E0546. This holds for the whole initializer, for a static part of one (list or tuple element, struct field, variant payload), and through a `const` reference.
>
> […]
>
> - It removes a failure mode. After this change a static initializer cannot panic, so "an initializer has no effects" and "S promises a total initializer" become true. Today they are false (probes r1, r4, r5, r6, r8, r9, r13).
> - It reuses the evaluator that E0546 already needs for `const` declarations. No second mechanism.
> - The rule stays simple: a module has no run time, so a panic that can be known statically is a compile error there. A function body has a run time, so it panics at run time. The `let a = 10 / 0` line in §2.21 is the local-`let` case, and the text should say "local".
>
> […]
>
> - "Const expression has meaning only in the four contexts" (let-constant-overflow Final Spec) is a list that grows to five. […] If the panel reads that line as frozen at four, I accept min-2.
>
> […]
>
> ## min-2 (fallback): Do nothing to the four contexts; specify the pre-main panic
>
> […] Costs more text, keeps "total" false, and `let` runs code at start-up. I oppose it, but it is the lesser change if the panel freezes the list at four.

#### Phase B — Debate highlights

The moderator's digest listed the points all six Phase A files state, and six variations: V1 where the rule lives, V2 a sentence in §2.12.1, V3 the table cell, V4 the W0704 and W0708 rows, V5 the heading, V6 recording the amendment. Each seat read all six Phase A files and answered. Each seat's text below is an excerpt.

- **Systems:**

> All six converge on sys-1. I hold it unchanged. […]
>
> - **V1: fifth item in the §2.21 list.** Oppose devops-2. The C backend needs one rule for "the compiler folds this". Two lists drift. […]
> - **V2: add the §2.12.1 sentence.** Hold: "A const expression in an initializer must evaluate without panic (§2.21)." That sentence states the rule at the place a reader of initializers looks. I accept adding "total" only if the sentence defines it ("an initializer cannot panic or have effects"). I do not insist.
> - **V3: table cell.** Take devops-1: "Compile time for const parts; the value is in static data at program start". It says what the hardware sees: no start-up code for const parts. […] I accept plt-1's wording as second choice.
> - **V4: W0704/W0708 rows.** No text change. Both rows say "Not in a const context (E0546 there)", and the new context is a const context. […]
> - **V5: do not retitle "Const Evaluation Must Succeed".** §3.2 and §3.6 cite that heading by name. A retitle breaks two cross-references for no gain. […]
> - **V6: record the amendment.** Yes. Record it as a count change to the let-constant-overflow *Final Spec* line. […]

- **Web/Scripting:**

> Position: web-1 stands. No change to my rule. I move on two wording points.
>
> - **V1: support the fifth list item.** Reject devops-2. A reader who looks up "where are const expressions checked" finds one list in §2.21. Two lists make a reader miss one. […] Change the lead line to "five contexts". The list heading stays.
> - **V2: support one sentence in §2.12.1.** Use "A const part that would panic is E0546 (§2.21)." A reader of §2.12.1 alone must learn the rule there. Oppose adding "total": it is a term from the votes, not from the user's code, […]
> - **V3: I concede to plt-1.** Table cell: "Compile time for const parts; program start for the rest". […]
> - **V4: no text change to W0704/W0708 rows.** […] Add the context only to the E0546 row. All six agree on that row.
> - **V5: do not retitle.** […]
> - **V6: record the amendment.** Put a short note in the decision file: the Final Spec line "four" becomes "five". I agree with plt-1: that line is about literal arithmetic outside the contexts. […]

- **PLT:**

> **V1.** […] Ballot: fifth item only. I prefer the plt-1 wording: "5. Module-level initializers: each const expression in a static expression (§2.12.1)." (I take "static expression" from min-1 and aiml-1; it is the §2.12.1 term, and plt-1 said "static initializer".)
>
> **V2.** […] I change my position: plt-1 named no §2.12.1 edit; I now hold: "A static expression is total: a const expression in it must evaluate without panic (§2.21), and the rest cannot panic." Check the second clause: list, tuple, struct, variant and function-literal forms and empty constructors cannot panic, so it is true. If the panel wants a smaller edit, sys-1's sentence is acceptable. Reject adding "total" with no definition.
>
> **V3.** Keep my plt-1 text: "Compile time for const parts; program start for the rest". Reject devops-1's "static data": it names a layout, and the spec states no implementation detail. […]
>
> **V4.** […] A copied list in each row is a third place to drift. Ballot: no change.
>
> **V5.** I withdraw the retitle. […]
>
> **V6.** Record it. […] I keep my reading that the line is a premise about code outside the contexts, but the safest record is an explicit amendment, not an argument about its meaning.

- **DevOps:**

> I hold devops-1. I drop devops-2 from the ballot: no seat supports it.
>
> **V1.** […] One note: the section heading says "Required". A module `let` does not require a const expression, it requires a static one. Change the lead line to "Const expressions are evaluated in five contexts" and leave the heading unchanged (see V5).
>
> **V2.** […] "A const part that would panic is E0546 (§2.21)." This puts the rule where the initializer reader looks. I oppose adding the word "total" (aiml). […]
>
> **V3.** […] I withdraw my "static data" wording: it states a backend detail, and the spec must not (see the no-impl-details rule).
>
> **V4.** No text change where a row says "Not in a const context". Check each row: if a row lists the contexts by name, add the fifth. The E0546 row always changes.
>
> **V5.** Keep "Const Evaluation Must Succeed". […]
>
> **V6.** Yes. The decision file must say that the let-constant-overflow line "has meaning only in the four contexts" is amended to five. I accept plt's reading (that line is about literals outside the contexts). The record removes the doubt that min raised.

- **AI/ML:**

> All six seats hold the same rule. I support it. I change my view on V2 and V4.
>
> - **V1: fifth list item in §2.21.** Support. […] I oppose devops-2: two lists make a model guess which one is complete. […]
> - **V2: one sentence in §2.12.1.** Support "A const part that would panic is E0546 (§2.21)." A model that reads only §2.12.1 then learns the rule there. I drop my request to add the word "total". It is jargon, the spec does not use it, and the sentence already makes the claim true. […]
> - **V3: table cell.** Prefer plt-1: "Compile time for const parts; program start for the rest". […] I withdraw my own wording, which kept "before `main`" and so invited the old reading. […]
> - **V4: catalog W0704/W0708 rows.** I now support "no text change". […] Add the module-level initializer to the E0546 row only, where all six agree. I withdraw my edit to W0704/W0708.
> - **V5: heading.** Do not retitle. […]
> - **V6: record the amendment.** Support plt-1 and sys-1: record it as a count change, in the decision file and in the let-constant-overflow Final Spec line. […]

- **Minimalism:**

> All six seats converge on the fifth context. I hold min-1. I change two details to cut text, and I drop two edits I proposed.
>
> - **V1. Fifth item in the §2.21 list. Support.** devops-2 keeps two lists of const contexts, which is more text, not less. […]
> - **V2. One sentence in §2.12.1: support, without "total".** Use sys-1's text: "A const expression in an initializer must evaluate without panic (§2.21)." I oppose aiml's "total". […] I withdraw my own wording ("is evaluated as in §2.21"): it does not state the E0546 outcome.
> - **V3. Table: one cell, the Evaluation cell. I now support an edit.** Today's "Program start, before `main`" is false for const parts, so I concede my "no table edit". The shortest text is plt-1: "Compile time for const parts; program start for the rest". […]
> - **V4. W0704/W0708 rows: no change. I withdraw my edit.** […]
> - **V5. Heading: do not retitle.** […]
> - **V6. Amendment: record it.** The Final Spec line becomes "five contexts". plt-1 is right that the old line was about literal arithmetic outside the contexts. Even so, the literal words say "only four", so amend the words and state in the decision file that this is a count change, not a change of rule. No ballot item.

#### Phase C — Silent ballot

Each seat voted alone on eight questions. Each vote below is complete and verbatim, except that the "Files read" line at the top of each file is dropped.

**The options.**

- **Q1. The rule.** A: a module-level `let` / `let mut` initializer is a fifth §2.21 const context, and a const expression in it that would panic is E0546. B: the four contexts stay; the initializer compiles and panics at run time before `main`.
- **Q2. Where the rule lives.** A: a fifth item in the §2.21 list. B: the §2.21 list stays as "where a const expression is required"; the rule is stated only in §2.12.1.
- **Q3. The §2.21 lead line** (then "Const expressions are required in four contexts:"). A: change only the count, to "required in five contexts:". B: "Const expressions are evaluated in five contexts".
- **Q4. Text of §2.21 item 5.**
  - A: "**Static initializers** - the const expressions in a module-level `let` initializer (§2.12.1)."
  - B: "5. Module-level `let` initializers (§2.12.1)"
  - C: "5. Module-level initializers: each const expression in a static expression (§2.12.1)."
  - D: "5. **Module-level `let` / `let mut` initializers**: each const expression in a static expression (§2.12.1)"
  - E: "Module-level `let` initializers — the const parts of a static expression (§2.12.1)"
  - F: "5. **Module-level `let` initializers** — each const expression in a static expression (§2.12.1)"
- **Q5. The §2.12.1 sentence.**
  - A: "A const expression in an initializer must evaluate without panic (§2.21)."
  - B: "A const part that would panic is E0546 (§2.21)."
  - C: "A static expression is total: a const expression in it must evaluate without panic (§2.21), and the rest cannot panic."
  - D: no §2.12.1 sentence.
- **Q6. The `let` Evaluation cell** (then "Program start, before `main`"). A: "Compile time for const parts; program start for the rest". B: "Compile time for const parts; the value is in static data at program start". C: no edit.
- **Q7. The W0704 and W0708 catalog rows.** A: no text change. B: add "a module-level `let` initializer" to the rows.
- **Q8. The *Const Evaluation Must Succeed* heading.** A: keep it; change "four" to "five" in the body. B: retitle it.

##### Systems (sys)

**Q1. The rule.**
- **Vote:** A
- **Reasoning:** The C backend emits a const-initialized module `let` as static storage. That needs the folded value at compile time. A panicking const part deferred to a start-up thunk adds code, an ordering question and a failure site that §2.12.1 says do not exist. E0546 makes "no user code runs before `main`" and "total initializer" true as written.
- **Concern:** The compiler must fold const parts in module initializers exactly as it folds `const` RHS, or the E0546 check and the emitted value can disagree.

**Q2. Where the rule lives.**
- **Vote:** A
- **Reasoning:** One rule for "the compiler folds this" needs one list. A second statement in §2.12.1 only would give two places that can drift, and the backend needs a single definition of the context.
- **Concern:** The §2.21 heading says "Required", and a module `let` does not require a const expression, so the list now mixes "required" and "evaluated" contexts.

**Q3. The §2.21 lead line.**
- **Vote:** A
- **Reasoning:** Change only the count. It is the smallest edit, it keeps the heading and lead line consistent, and the item text states the static-expression nuance. The spec need not teach a new verb for a cost-neutral rule.
- **Concern:** "Required in five contexts" is slightly false for item 5, and a reader may think a module `let` must be a const expression.

**Q4. Text of §2.21 item 5.**
- **Vote:** F
- **Reasoning:** "each const expression in a static expression" uses the §2.12.1 term, so it covers list elements, struct fields and variant payloads, which are the parts the backend folds. It matches the existing "N. **Bold name** - text" form. My own text (A) says "the const expressions in a module-level `let` initializer" and is less exact about static parts.
- **Concern:** A reader may not link "static expression" to §2.12.1 without following the reference.

**Q5. The §2.12.1 sentence.**
- **Vote:** A
- **Reasoning:** It states the property at the place where initializers are read, in plain words, and says "evaluate without panic", which is what the backend relies on. Option C adds a claim about the non-const forms that is true but needs upkeep when the static list grows.
- **Concern:** If a new static form that can panic is added later, this sentence will not catch it, and nothing else in the spec will.

**Q6. Evaluation cell.**
- **Vote:** A
- **Reasoning:** B was my first choice but it names a layout (static data), and the spec must not state backend detail. A is accurate for both const parts (compile time) and the rest such as `Map.new()` (program start), and it costs no hardware promise.
- **Concern:** "Program start for the rest" invites readers to expect start-up code, while an implementation may emit none, so the cell may be read as stronger than needed.

**Q7. W0704 and W0708 rows.**
- **Vote:** A
- **Reasoning:** The rows say "Not in a const context (E0546 there)". The module initializer is now a const context, so they stay true by reference. A copied list is a third place to drift.
- **Concern:** A reader who checks only the row text may not know the module initializer is a const context unless they open §2.21.

**Q8. The heading.**
- **Vote:** A
- **Reasoning:** §3.2, §3.6 and the explain text cite the heading by name. A retitle breaks those links for no gain, and the heading stays accurate with "five" in the body.
- **Concern:** If the heading is ever changed later, the cross-references need a sweep, and no check enforces that today.

##### Web/Scripting (web)

**Q1. Vote: A**
Reasoning: One rule a JS/Python dev can hold: bad math at module scope or in a `const` fails the build, not the first run. A panic before `main` gives a trace with no `main` frame and no test record under `blink test` (probe r12). Every compiled peer (Go, Rust, C, C++, Kotlin `const val`) rejects `10 / 0` at module scope.
Concern: A user must learn that module `let a = 10 / 0` is an error and local `let a = 10 / 0` is a warning plus a run-time panic.

**Q2. Vote: A**
Reasoning: A reader asks "where does the compiler evaluate const expressions?" and should find one list. Two lists (B) let a reader miss one, and they can drift.
Concern: The §2.21 heading says "Required", and a module `let` requires a static expression, not a const one; a pedantic reader may notice.

**Q3. Vote: A**
Reasoning: Change the count only. The lead line and heading stay, so cross-references and a reader's memory of the section stay valid. Option B rewords the lead line to fix a nuance that item 5 already states.
Concern: "Required in five contexts" is slightly loose for item 5, since a module `let` also takes non-const static forms.

**Q4. Vote: F**
Reasoning: It matches the existing "N. **Bold** - text" form, so item 5 reads like items 1-4. "Each const expression in a static expression" says it is the const parts that are checked, not the whole initializer; B alone would suggest `Map.new()` must be const. I prefer F to D because `let mut` adds no information (§2.12.1 says the rule is the same for `let`, `let mut` and `pub let`).
Concern: "Static expression" is a spec term a newcomer meets only in §2.12.1, so item 5 needs the (§2.12.1) pointer to be understood.

**Q5. Vote: B**
Reasoning: A reader of §2.12.1 alone must learn the outcome, and "E0546" names it; the user gets an error code to search for. B is the shortest sentence that states the outcome. C uses "total", a word from the votes that the user never sees.
Concern: "A const part" is informal; a reader may not know which parts of an initializer are const.

**Q6. Vote: A**
Reasoning: "Compile time for const parts; program start for the rest" is short and true. Today's "Program start, before `main`" would mislead a user into expecting a run-time panic. B names static data, which is a backend detail.
Concern: "The rest" may leave a reader unsure which values run at start-up (for example `Map.new()`).

**Q7. Vote: A**
Reasoning: The rows say "Not in a const context (E0546 there)", which is true once §2.21 lists five contexts. Fewer edits means fewer places to drift.
Concern: A reader who sees only the W0704 row and knows only the old four contexts will think a module `let` gets the warning.

**Q8. Vote: A**
Reasoning: §3.2 and §3.6 cite the heading by name. The heading is still accurate; only the count in the body changes.
Concern: The heading says "Const Evaluation" and a reader may not link it to module initializers; item 5 in the list has to carry that.

##### PLT (plt)

**Q1. Vote: A**
Reasoning: Q3 and Q4 of the module-level initializers vote excluded `List.with_capacity(n)` and interpolation because a static initializer must be total. A panic is divergence, so with B that premise is false and "an initializer has no effects" is false too. With A, totality holds by construction: the compiler evaluates every partial operation in a static expression before any code runs, and the rule goes by subterm (`10 / Z`, `[1, 10 / 0]`) with no special case.
Concern: The compiler needs a const evaluator for module `let` and must reject on every subterm, including through `const` references. Until that lands, the spec states a guarantee that gen1 does not give.

**Q2. Vote: A**
Reasoning: One list of const contexts keeps the classification single-sourced. A rule only in §2.12.1 leaves §2.21's "const context" predicate silently incomplete, and W0704/W0708 and the catalog cite that predicate.
Concern: §2.21 and §2.12.1 both now mention the rule, so the two texts can drift apart.

**Q3. Vote: B**
Reasoning: devops is right that a module `let` does not require a const expression. It requires a static expression, and the compiler evaluates the const parts. "Evaluated in five contexts" is true of all five items, including the four where const is required. "Required in five" is false for item 5.
Concern: The unchanged heading *Where Const Expressions Are Required* now fits the lead line less well. I accept this, because §3.2 and §3.6 cite the neighbouring heading and the list heading is not an anchor.

**Q4. Vote: F**
Reasoning: F matches the existing form "N. **Bold name** - text". It uses the §2.12.1 term "static expression", so a reader can follow the link. "Each const expression in a static expression" states the per-subterm rule that I need. D adds `let mut` and gains nothing, because §2.12.1 already says the rule is the same for `let`, `let mut` and `pub let`.
Concern: A reader may take "static expression" as one expression and miss that every const part is checked, including parts of a list or struct.

**Q5. Vote: C**
Reasoning: The votes rely on totality, so the spec should state the property. C is true: the list, tuple, struct, variant, function-literal and empty-constructor forms cannot panic, and a const part is checked by §2.21. The second clause makes the typing claim complete. It is a statement of fact in plain words. I second A as acceptable if C fails.
Concern: C uses "total", a word §2.12.1 does not define today, and a reader may ask what "total" means. The rest of the sentence defines it in plain words.

**Q6. Vote: A**
Reasoning: "Program start, before `main`" is false for const parts once E0546 applies. A states when an error appears (compile time) and when the rest runs, and it names no layout. B names a backend detail, which the spec must not.
Concern: "The rest" is vague about which parts run at program start. The empty constructors and function literals are the only such parts, and §2.12.1 lists them.

**Q7. Vote: A**
Reasoning: The rows say "Not in a const context (E0546 there)". That is true by reference once §2.21 lists five contexts. A copy of the list in each row is a third place to drift.
Concern: A reader of the W0704 row alone cannot tell that a module `let` is a const context without following the link to §2.21.

**Q8. Vote: A**
Reasoning: I withdrew the retitle. §3.2 and §3.6 cite the heading as an anchor, and it stays accurate. Only "four" becomes "five" in the body.
Concern: The heading and the body keep the same count words only if every "four" is found. The writer must grep for all of them.

##### DevOps/Tooling (devops)

**Q1. The rule.**
- **Vote:** A
- **Reasoning:** A compile error with a span on the sub-expression is the best diagnostic surface. The run-time option gives `panic: Int division by zero at src/main.bl:1` before `main`, with no binding name and no test record under `blink test` (probe r12). The LSP can show the E0546 squiggle at edit time; it cannot show a start-up panic.
- **Concern:** E0546 is not implemented yet, so the spec states a rule that gen1 breaks until the open implementation ticket lands.

**Q2. Where the rule lives.**
- **Vote:** A
- **Reasoning:** A user who looks up "const context" or E0546 finds one list. Two lists of const contexts can drift, and `blink explain E0546` text would have to point at both.
- **Concern:** The §2.21 list heading says "Required", and a module `let` does not require a const expression, so the heading reads slightly off (Q3 fixes the lead line).

**Q3. The §2.21 lead line.**
- **Vote:** B
- **Reasoning:** A module `let` requires a static expression, not a const expression. "Evaluated in five contexts" is true for all five items. "Required in five contexts" is false for item 5, and a user who reads it will look for a const-expression error that does not exist. The heading stays, so no cross-reference breaks.
- **Concern:** The heading *Where Const Expressions Are Required* and the lead line now use different verbs.

**Q4. Text of §2.21 item 5.**
- **Vote:** F
- **Reasoning:** The four items today use "N. **Bold name** — text". F matches that form with an em dash; D uses a colon. F says "static expression", the §2.12.1 term, so a reader can search for it. `let` covers `let mut` and `pub let` by §2.12.1 ("The rule is the same for `let`, `let mut` and `pub let`").
- **Concern:** A reader may take "`let` initializers" to exclude `let mut`, which only §2.12.1 settles.

**Q5. The §2.12.1 sentence.**
- **Vote:** B
- **Reasoning:** It names E0546, so a user who reads §2.12.1 after the error finds the rule and the code in one place. It is the shortest sentence. C adds a claim about the non-const parts that the compiler does not check as a rule.
- **Concern:** "A const part" is a new phrase that §2.12.1 does not define; a reader must connect it to "const expression" in the list above.

**Q6. Table, `let` column, Evaluation cell.**
- **Vote:** A
- **Reasoning:** It says when the error appears (compile time) and when the rest runs (program start). B names a backend detail, which the no-impl-details rule keeps out of the spec. No edit leaves "Program start, before `main`" false for const parts.
- **Concern:** "Program start for the rest" may confuse a reader, because `Map.new()` and `[]` run no user code.

**Q7. ERROR_CATALOG W0704 and W0708 rows.**
- **Vote:** A
- **Reasoning:** The rows say "Not in a const context (E0546 there)", and item 5 is now a const context. A copied list in each row is a third place to keep in sync. The writer must check each row: if a row lists the contexts by name, add the fifth (my B1 note).
- **Concern:** The catalog is read on its own, so a reader of the W0704 row alone has no list to see which contexts are meant.

**Q8. The *Const Evaluation Must Succeed* heading.**
- **Vote:** A
- **Reasoning:** §3.2, §3.6 and the diagnostic explain text cite this heading by name. A retitle breaks the links and gains nothing. The body changes "four" to "five".
- **Concern:** None that matters; the heading stays accurate.

##### AI/ML (aiml)

**Q1. Vote: A**
Reasoning: One rule, "if the compiler evaluates it, a panic is an error", is the easiest for a model to learn from the spec alone. A panic before `main` gives the worst repair-loop signal: no `main` frame, no test record (probe r12). A compile error with a span is the best feedback.
Concern: A model must now know that a module `let` and a local `let` differ for `10 / 0`, and may miss it if the "local" word is not on the example.

**Q2. Vote: A**
Reasoning: A model reads §2.21 to find where const evaluation happens. One list is one place to look; two lists make it guess which is complete.
Concern: The same rule then appears in §2.21 and §2.12.1, and the two can drift.

**Q3. Vote: B**
Reasoning: The new item does not require a const expression; it requires a static one, and the const parts get evaluated. "Evaluated in five contexts" is true for all five items. "Required" would be false for item 5, and a model would take it literally.
Concern: The heading *Where Const Expressions Are Required* still says "Required" next to a lead line that says "evaluated", and that mismatch can confuse a reader.

**Q4. Vote: F**
Reasoning: It keeps the existing form "N. **Bold name** — text", so the five items read the same way. "each const expression in a static expression" says the unit that is evaluated, and it uses the §2.12.1 term.
Concern: "`let` initializers" alone does not name `let mut`, so a model may think `let mut` is outside the rule; §2.12.1 says the rule is the same for both.

**Q5. Vote: B**
Reasoning: It is short, and it states the outcome (E0546), which is the fact a reader of §2.12.1 needs. It adds no new word that the spec must define.
Concern: It says "const part", and §2.12.1 does not define that term; a reader must infer it from the §2.21 link.

**Q6. Vote: A**
Reasoning: "Program start, before `main`" is false for const parts today and invites the old reading. The short plt text tells a model when the error appears. It names no layout detail.
Concern: "Program start for the rest" may suggest that user code runs before `main`, against §2.12.1.

**Q7. Vote: A**
Reasoning: The rows say "Not in a const context (E0546 there)", and that is true once §2.21 lists five contexts. A copied list in each row is one more place to drift.
Concern: A reader who sees only the W0704 row will not learn that a module initializer is a const context.

**Q8. Vote: A**
Reasoning: §3.2 and §3.6 cite the heading by name; a retitle breaks those anchors. The heading stays accurate with "five" in the body.
Concern: A heading that does not name the new context gives no hint of it to a reader who scans only headings.

##### Minimalism (min)

**Q1. The rule.**
- **Vote**: A
- **Reasoning**: A module has no run time. A panic the compiler can see is a compile error there, and this removes a failure class (a panic before `main`, no test record) instead of specifying it. It adds one list item and no new mechanism, because E0546 needs the evaluator for `const` anyway. Option B would need new text for what a pre-main panic prints and what `blink test` reports, and would make "total" false.
- **Concern**: The `let a = 10 / 0` line now differs between module scope and local scope, and a reader who skips the word "local" will get it wrong.

**Q2. Where the rule lives.**
- **Vote**: A
- **Reasoning**: One list of const contexts is less text and cannot drift. Option B keeps the §2.21 list as "required" and states the rule in a second place, which is two lists.
- **Concern**: §2.21's heading says "Required" and a module `let` requires a static expression, so the heading is slightly loose.

**Q3. The §2.21 lead line.**
- **Vote**: A
- **Reasoning**: Change one word. Devops' point about "required" is fair, but the heading and the lead line then disagree with each other, and §3.2/§3.6 anchor on this section. A count change is the smallest edit and matches the amendment record ("four" to "five").
- **Concern**: The lead line says "required" for an item that is only evaluated, and a later editor may "fix" it and widen the diff.

**Q4. Text of §2.21 item 5.**
- **Vote**: F
- **Reasoning**: The four existing items use "N. **Bold name** — text". F follows that form and uses the §2.12.1 term "static expression", so it adds no new vocabulary. B drops the form; D adds "`let` / `let mut`" words the rest of the spec does not repeat.
- **Concern**: "each const expression in a static expression" is a little dense, and a reader may not see that it covers a bare `let a = 10 / 0`.

**Q5. The §2.12.1 sentence.**
- **Vote**: A
- **Reasoning**: One sentence, no new term, and it states the rule where the initializer reader looks. C adds a "cannot panic" clause that the spec must then keep true for every future static form. D leaves the reader of §2.12.1 without the rule.
- **Concern**: The sentence does not say the outcome is E0546, so the reader must follow the §2.21 link.

**Q6. §2.21 table, `let` Evaluation cell.**
- **Vote**: A
- **Reasoning**: "Program start, before `main`" is false for const parts, so the cell must change. A is the shortest correct text and names no backend detail. B states a layout, which the spec must not.
- **Concern**: "program start for the rest" may suggest that static forms such as `Map.new()` run code, which §2.12.1 says no user code does.

**Q7. W0704 and W0708 rows.**
- **Vote**: A
- **Reasoning**: The rows say "Not in a const context (E0546 there)". That stays true once §2.21 lists five contexts. A copied list in each row is a third place to drift.
- **Concern**: A reader of a row alone does not learn that a module initializer is a const context, and must go to §2.21.

**Q8. The *Const Evaluation Must Succeed* heading.**
- **Vote**: A
- **Reasoning**: §3.2 and §3.6 cite it by name, and it stays accurate. A retitle breaks those anchors and gains nothing.
- **Concern**: None of weight; the body must be checked so that no "four" remains in it.

##### Phase C tally

| Question | sys | web | plt | devops | aiml | min | Result |
|---|---|---|---|---|---|---|---|
| Q1 | A | A | A | A | A | A | A, 6-0 |
| Q2 | A | A | A | A | A | A | A, 6-0 |
| Q3 | A | A | B | B | B | A | 3-3 |
| Q4 | F | F | F | F | F | F | F, 6-0 |
| Q5 | A | B | C | B | B | A | A 2, B 3, C 1 |
| Q6 | A | A | A | A | A | A | A, 6-0 |
| Q7 | A | A | A | A | A | A | A, 6-0 |
| Q8 | A | A | A | A | A | A | A, 6-0 |

Q3 tied 3-3. Q5 had no majority (B had 3 of 6). Both went to Phase D.

#### Phase D — Debate on Q3 and Q5

Each seat read all six Phase C files and the moderator's digest, then wrote one reply. The text below is an excerpt of each reply (`[…]` marks a cut). The digest added one repo fact: the heading *Where Const Expressions Are Required* is cited nowhere else in sections/. The heading that §3.2 and §3.6 cite is *Const Evaluation Must Succeed*, and Q8 keeps it.

**Q3. The §2.21 lead line.** sys, web and min changed from A to B. plt, devops and aiml held B.

- **sys (changed A to B):**

> The B side has the strongest point: "required" is false for item 5. A module `let` requires a static expression, and a reader who takes "required in five contexts" literally will look for a const-expression error that does not exist. […] A wrong word in a rule statement is worse than a mismatched verb.

- **web (changed A to B):**

> The other side's point answers it: a lead line that says "required" is false for item 5, and a user who reads it will look for a const-expression error that does not exist. The item text cannot undo a false lead line, because readers take the lead line first. […] The heading and the lead line then use different verbs. That is a smaller fault than a false statement, and a later chore can fix the heading with no cross-reference sweep.

- **min (changed A to B):**

> My Phase C case was "smallest edit". It is not smaller. A and B both change one phrase in one line, so the edit size is equal. […] A false lead line is a defect in the spec, not a style point. […] I now hold B: "Const expressions are evaluated in five contexts".

- **plt (held B):**

> sys and web both say in their own Concern lines that "required" is false for item 5. A rule text that its supporters call false is a defect. The lead line defines the list, and every item inherits its verb, so the nuance cannot sit in item 5 alone.

- **devops (held B):**

> The edit is one word in both options: "required" becomes "evaluated". […] A mismatch between a heading and a lead line costs a reader a moment. A false lead line costs a reader a wrong model: they look for a const-expression error on a module `let` that does not require one.

- **aiml (held B):**

> A model takes a lead line literally. "Required in five contexts" tells it that a module `let` needs a const expression, and it will write `const`-only code or look for an error that does not exist. […] A known-false word costs more than one changed word. B is true of all five items.

**Q5. The §2.12.1 sentence.** plt changed from C to A. No seat held C after this round. sys and min held A. web, devops and aiml held B.

- **sys (held A):**

> "A const expression in an initializer must evaluate without panic (§2.21)." […] B uses "const part", a phrase the spec does not define. Three seats list that phrase as their own concern. A uses "const expression", the term the §2.12.1 list and §2.21 already define. […] §2.21 *Const Evaluation Must Succeed* already names `ConstEvalPanic` (E0546) one link away, so the outcome has one source and cannot drift.

- **min (held A):**

> The strongest B point is that B names E0546 and §2.12.1 already names codes elsewhere. That is true. But B adds "const part", a phrase the spec does not define, and its own three supporters list that as their Concern. A uses "const expression", the term §2.12.1's list already uses, so it adds no vocabulary.

- **plt (changed C to A):**

> The strongest point against C (sys, min, devops) is that "the rest cannot panic" is a standing claim about every future static form, and nothing checks it. That is a fair cost. […] A uses the defined term "const expression" and says "evaluate without panic", the property the Q3 and Q4 votes of the earlier decision rely on.

- **web (held B):**

> A says "must evaluate without panic" but not what the user sees. B gives the error code, and §2.12.1 already names codes in its text (E1013, E1129), so B follows the local pattern. "A const part" is informal, but the list directly above says "A const expression (§2.21)" and B links to §2.21, so the reader can resolve it.

- **devops (held B):**

> A user who has the error E0546 and opens §2.12.1 finds "must evaluate without panic" and no code. […] I oppose C. […] If B fails, I accept A over C.

- **aiml (held B):**

> A model that reads §2.12.1 after a failure needs the code to find the rule. A leaves the outcome out, as min's own Concern says. […] B states the outcome in the shortest text. Its "const part" gap is small: the sentence links to §2.21, and item 5 defines the term.

#### Phase D — Silent re-vote (Q3 and Q5)

Q3 options: A "... required in five contexts:" or B "Const expressions are evaluated in five contexts". Q5 options: A "A const expression in an initializer must evaluate without panic (§2.21)." or B "A const part that would panic is E0546 (§2.21)." Each vote is complete and verbatim, except that the "Files read" line is dropped.

##### sys

**Q3. Vote: B**
Reasoning: "Required" is false for item 5. A module `let` requires a static expression, and the compiler folds the const parts. "Evaluated in five contexts" is true of all five items and costs the backend nothing. The edit is one word in both options, and the heading is cited nowhere else in sections/.
Concern: The heading *Where Const Expressions Are Required* and the lead line use different verbs, and a later editor may widen the diff to "fix" the heading.

**Q5. Vote: A**
Reasoning: "A const expression in an initializer must evaluate without panic (§2.21)" states the property the backend relies on, in a term the §2.12.1 list already defines. B adds "const part", which the spec does not define, and all three of its supporters list that as their own Concern. The error code is one link away in §2.21 *Const Evaluation Must Succeed*, so the code has one source and cannot drift.
Concern: The sentence does not name E0546, so a user who arrives from the error must follow the §2.21 link to connect the code to the rule.

##### web

**Q3. Vote: B**
Reasoning: "Evaluated in five contexts" is true of all five items. "Required" is false for item 5, and a JS/Python dev reads the lead line first and takes it literally. All six seats now hold B, and the heading is cited nowhere else in sections/, so no link breaks.
Concern: The heading *Where Const Expressions Are Required* now sits above a lead line with a different verb, and a later editor may "fix" one to match the other.

**Q5. Vote: B**
Reasoning: A user who hits E0546 and opens §2.12.1 should find the code in the sentence they read, not one link away. §2.12.1 already names codes in its text (E1013, E1129), so B follows the local pattern. "Const part" is informal, but the list directly above says "A const expression (§2.21)" and the sentence links to §2.21, so the reader can resolve it.
Concern: If A wins, the sentence "must evaluate without panic" gives the reader no error code to search for, and they must follow the §2.21 link to learn the outcome.

##### plt

**Q3. Vote: B**
Reasoning: The lead line states the rule for the whole list, and every item inherits its verb. "Required" is false for item 5, because a module `let` requires a static expression and the compiler evaluates its const parts. "Evaluated in five contexts" is true of all five items. The heading is cited nowhere else in sections/, so the verb mismatch breaks no reference.
Concern: The heading *Where Const Expressions Are Required* keeps "Required" next to a lead line that says "evaluated", and a later editor may copy the old verb back.

**Q5. Vote: A**
Reasoning: A uses the defined term "const expression" and says "evaluate without panic", the property the earlier totality votes (Q3 and Q4 of the module-level initializers ruling) rely on. B introduces "const part", which §2.12.1 does not define. C states a standing claim about every future static form, and nothing checks it. A links §2.21, which names `ConstEvalPanic` (E0546).
Concern: A does not name E0546, so a reader of §2.12.1 alone must follow the §2.21 link to learn the error code.

##### devops

**Q3. The §2.21 lead line.**
- **Vote:** B
- **Reasoning:** A module `let` requires a static expression, not a const expression. "Evaluated in five contexts" is true of all five items. "Required in five contexts" is false for item 5, and a user who reads it will look for a const-expression error that does not exist. The heading is cited nowhere else in sections/, so the verb mismatch breaks no reference. Sys, web and min moved to B for the same reason.
- **Concern:** The heading *Where Const Expressions Are Required* and the lead line use different verbs, so a later editor may reopen the wording.

**Q5. The §2.12.1 sentence.**
- **Vote:** B
- **Reasoning:** A user who has E0546 on screen and opens §2.12.1 must find the code there. B names it, and §2.12.1 already names codes in its text (E1013, E1129), so B follows the local form. The `blink explain E0546` text and the sentence then use the same code. A states the property but not the outcome; that is one link away, and a user should not need to follow it. "Const part" is informal, but the list above it says "A const expression (§2.21)" and B links to §2.21.
- **Concern:** "A const part" is a phrase that §2.12.1 does not define, and a reader may not know which parts of an initializer are const.

##### aiml

**Q3. Vote: B**
Reasoning: A model takes the lead line literally and reads it before the items. "Required in five contexts" says a module `let` needs a const expression, which is false for item 5, and the model will write const-only code or look for an error that does not exist. "Evaluated in five contexts" is true for all five items. All six seats now hold B, and the heading is cited nowhere else in sections/, so no link breaks.
Concern: The heading *Where Const Expressions Are Required* still says "Required" above a lead line that says "evaluated", and a later chore should align them.

**Q5. Vote: B**
Reasoning: A model that gets E0546 and opens §2.12.1 needs the code to find the rule. B states the outcome in one short sentence, and §2.12.1 already names codes (E1013, E1129). A says "must evaluate without panic" but not what the user sees, so the model must follow a link to learn the outcome. The "const part" gap is small: the list above names "A const expression (§2.21)" and B links to §2.21.
Concern: If A wins, the sentence omits the error code, and a reader of §2.12.1 alone learns the property but not the diagnostic.

##### min

**Q3. The §2.21 lead line.**
- **Vote:** B
- **Reasoning:** The edit is one phrase in one line under both options, so size does not decide. "Required in five contexts" is false for item 5, because a module `let` requires a static expression, not a const one. The list heading is cited nowhere else in sections/, so the verb mismatch breaks no reference. A true lead line costs nothing more than a false one.
- **Concern:** The heading *Where Const Expressions Are Required* now sits over a lead line that says "evaluated", and a later editor may widen the diff to fix it.

**Q5. The §2.12.1 sentence.**
- **Vote:** A
- **Reasoning:** "A const expression in an initializer must evaluate without panic (§2.21)." uses "const expression", the term the §2.12.1 list and §2.21 already define, so it adds no vocabulary. B adds "const part", a phrase the spec does not define, and its own three supporters list that as their concern. The code E0546 is one link away, in the section A points to, so the outcome has one source and cannot drift.
- **Concern:** A does not name E0546, so a user who arrives from the error must follow the §2.21 link to find the code.

##### Phase D tally

| Question | sys | web | plt | devops | aiml | min | Result |
|---|---|---|---|---|---|---|---|
| Q3 | B | B | B | B | B | B | B, 6-0 |
| Q5 | A | B | A | B | B | A | 3-3 |

#### Owner tiebreak (Q5)

Q5 stayed tied 3-3 after Phase D: A (sys, plt, min) against B (web, devops, aiml). The owner ruled as BDFL: wording-only tie; take A's defined term and B's error code. The sentence in §2.12.1 is:

> A const expression in an initializer that would panic is error E0546 (§2.21).

Under it, an example: a top-level `let a = 10 / 0` (error E0546), a top-level `let xs = [1, 10 / 0]` (E0546 on the element), and a local `let b = 10 / 0` in `fn main` (compiles, warns, panics at run time).

Why: this answers A's concern (no undefined "const part") and B's concern (the code is named in §2.12.1). Each side named the other's point as its own concern: sys, plt and min wrote that A "does not name E0546"; devops wrote that "const part" is not defined.

### Final Spec

```blink
let a = 10 / 0                  // error[ConstEvalPanic]: division by zero
let xs = [1, 10 / 0]            // error[ConstEvalPanic]: at the list element

fn main() {
    let b = 10 / 0              // compiles, gives a warning, and panics at run time
}
```

- §2.21 lists five const contexts. Item 5: "**Module-level `let` initializers** — each const expression in a static expression (§2.12.1)". The lead line reads "Const expressions are evaluated in five contexts:". The heading *Where Const Expressions Are Required* does not change.
- A const expression in a module-level `let` or `let mut` initializer that would panic is E0546. This holds for the whole initializer, a list or tuple element, a struct field, a variant payload, and a `const` reference.
- §2.12.1 states: "A const expression in an initializer that would panic is error E0546 (§2.21)."
- The `let` Evaluation cell reads "Compile time for const parts; program start for the rest".
- W0704 and W0708 do not fire in a const context, so they do not fire in a module-level initializer. Their catalog rows do not change. The E0546 row names the new context.
- The heading *Const Evaluation Must Succeed* stays. Its body says "five contexts".
- A local `let a = 10 / 0` in a function body keeps the earlier behavior: it compiles, gives W0704, and panics at run time.
- The let-constant-overflow *Final Spec* line says "five contexts". This is a count change. The rule of that decision is the same.

### Dissents and concerns

No seat dissented on a final result: Q1, Q2, Q3, Q4, Q6, Q7 and Q8 passed 6-0, and the owner settled Q5. The concerns below are each seat's own words from Phase C and Phase D.

- **Heading and lead line use different verbs** (sys, web, plt, devops, aiml, min, Phase D):

> The heading *Where Const Expressions Are Required* and the lead line use different verbs, and a later editor may widen the diff to "fix" the heading. (sys)

- **gen1 does not give the guarantee yet** (plt, devops, Phase C Q1):

> Until that lands, the spec states a guarantee that gen1 does not give. (plt)
>
> E0546 is not implemented yet, so the spec states a rule that gen1 breaks until the open implementation ticket lands. (devops)

- **Module `let` and local `let` differ for `10 / 0`** (web, aiml, min, Phase C Q1):

> A user must learn that module `let a = 10 / 0` is an error and local `let a = 10 / 0` is a warning plus a run-time panic. (web)

- **"The rest" in the Evaluation cell** (sys, web, devops, aiml, min, Phase C Q6):

> "Program start for the rest" may suggest that static forms such as `Map.new()` run code, which §2.12.1 says no user code does. (min)

### Reading gaps

- The ruling does not state the diagnostic span or the notes for an error inside a module initializer. The spec keeps the existing text for E0546: the span is on the failing sub-expression.
- The ruling does not say when gen1 will reject these initializers. The spec leads the compiler; the implementation ticket for E0546 and W0704 must add the module-level context.
- The ruling names no edit to llms.md or llms-full.md. No line there covers E0546 or const evaluation, so they are unchanged.


