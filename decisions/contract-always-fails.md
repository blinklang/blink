[< All Decisions](../DECISIONS.md)

# Contract That Always Fails (V0002) — Design Rationale

**Gap:** "sections/03b_contracts.md ('Disproven (Compile Error with Counterexample)', near line 497) makes V0002 a hard compile error. Rand Q7c (decisions/random-stdlib-module.md) voted 6-0 against a compile error for rand.int(5..5). ERROR_CATALOG.md has V0001, V0003, V0004 but no V0002 row. The constant-zero-divisor panel (all six) asked that this be settled before any empty-literal-range check ships, since such a check must come from a rule the API states in its declaration (e.g. @requires)."

The panel found that "Disproven" covered two cases. One is a call that fails on every run (every argument is a literal and the predicate is false). The other is a solver counterexample on a dynamic input, where some runs fail and some pass. The first is a certain panic, and gets the same treatment as `10 / 0` ([Constant Zero Divisor](constant-zero-divisor.md)). The second is Unknown, with a runtime check.

**Result:**

- **Q1 (6-0, A):** V0002 is a warning lint for a `@requires` that is false on every run that reaches the call. The runtime check stays. A counterexample on a dynamic input is Unknown, with a V0004 runtime check. The shape is that of W0704: it does not look through `let` or `const`; it fires in dead branches; it does not fire inside an `assert_panics` body; `@allow` and `[lints]` control it.
- **Q2 (6-0):** the name is `ContractAlwaysFails`.
- **Q3 (6-0):** a `@where` refinement on a parameter acts as an implied `@requires`, with the same code and the same diagnostic.
- **Q4 (6-0):** V0002 fires under every `@verify` value, `"trust"` included. The sentence that `@verify(fallback:)` has no effect on this outcome stays. A counterexample on a dynamic input is an Unknown outcome, so `"error"` gives V0003 for it. Only `[lints]` changes the level of V0002.
- **Q5 (6-0):** a counterexample shows in a note on V0004, in the `blink verify` report, and in V0003 under `"error"`.
- **Q6 (5-1, L1; Minimalism dissent for L2):** a literal is the W0708 literal tree plus list, string and range literals whose parts are literal trees. The predicate must fold in the const evaluator behind E0546. Only the arguments that the predicate reads must be literal. A `let` or `const` reference stops the tree.
- **Q7 (3-3 in Phase C; 6-0 S1 in Phase D; wording 6-0 T-Sys):** a solver may add a V0002 hit only where it proves that some run reaches the call and that the predicate is false on every run that reaches it. One counterexample never counts. Literal hits fire in dead branches.
- **Q8 (6-0):** `@ensures` is not part of V0002 for now.
- **Q9 (6-0):** no V0002 when the fold panics, when the predicate cannot be evaluated, or when the evaluator reaches its limit. The outcome stays Unknown.
- **Q10 (6-0):** no `rand` API change. `Range[T]` bound accessors are a separate decision; `rand.int(5..5)` can get V0002 later through its own `@requires`.
- **Q11 (5-1, H1; AI/ML dissent for H2):** the §3b.4 heading is "Always Fails (Warning)".

**AI-first review:** 5/5 pass. Learnability pass, Consistency pass (same shape as W0704 and W0708), Generability pass, Debuggability pass (the warning names the call site and the folded predicate), Token efficiency pass — 0 fails.

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in independent-proposal → debate → vote rounds. Each panelist's text below is a verbatim excerpt.

#### Phase A — Independent proposals

- **Systems:**

> **Proposal S1 (main): V0002 is a must-fail warning; may-fail stays Unknown**
>
> 1. **V0002 `ContractViolatedOnLiteral`, warning.**
>    - **When it fires:** a `@requires` predicate evaluates to `false` by const folding. Every value it reads comes from a literal expression at the call site (with parentheses, unary `-`, and literal range `a..b`). A `let` or `const` reference stops the check. This is the scope of W0704 and W0708.
>    - **Where it fires:** in a branch that never runs. It does not fire inside an `assert_panics` body.
>    - **Control:** suppress with `@allow(ContractViolatedOnLiteral)`. Set the level with `V0002 = "off"` or `"error"` under `[lints]`.
>    - **The check stays:** the call still panics at run time. This keeps Rand Q7c and constant-zero-divisor Q2 as one rule: a literal certain panic is a warning plus a runtime panic. It also meets Q3-R, because the check comes only from the API's own `@requires`.
> 2. **A solver counterexample on dynamic input is Unknown, not Disproven.** It gets the runtime check (V0004). The note carries the counterexample when the solver has one.

- **Web/Scripting:**

> ## Proposal W1: V0002 is a warning, and it fires only when the check always fails
>
> **Rule.** A call reports V0002 only when every value the `@requires` predicate reads is known at compile time and the predicate is false. In that case the check fails on every run that reaches the call. Severity is **warning**, with the lint name `ContractAlwaysFails`. It follows the W0704 shape:
>
> - `@allow(ContractAlwaysFails)` turns it off. `[lints] ContractAlwaysFails = "error"` makes it an error.
> - It does not fire inside an `assert_panics` body.
> - It fires in dead branches, the same as W0704.
> - It does not look through `let` or `const` names. Only literals at the call site count.
> - The runtime check still runs, so the program still panics. The warning does not change behaviour.
>
> ```blink
> @requires(sides > 0)
> fn roll(sides: Int) -> Int ! Rand {
>     rand.int(1..=sides)
> }
>
> fn main() ! Rand {
>     roll(0)              // warning[V0002]: contract always fails: sides = 0 violates sides > 0
> }
>
> test "zero sides panics" {
>     assert_panics { roll(0) }    // no warning: the panic is the point
> }
> ```

- **PLT:**

> ## Proposal P1 (my recommendation)
>
> **1. Refuted gives a warning.** `V0002 ContractViolated` has warning severity. You can silence it with `@allow(ContractViolated)` or set it to "error" under `[lints]`. A call that is certain to fail is still well-typed: it has a defined result, which is a panic or `validation.contract_violation`. That is the same reasoning as W0704 and Q7c.
>
> **2. Counterexample gives no diagnostic beyond the existing runtime check.** It is an Unknown-class outcome: a V0004 runtime check, plus the counterexample in the `blink verify` report. It is never an error.
>
> **3. Scope before a solver exists.** V0002 fires only when φ is closed after substitution: every argument it reads is a literal, and the compiler can evaluate the pure predicate at compile time and get `false`. This matches W0704: a `let`/`const` reference does not trigger it, it fires in dead branches, and it does not fire in an `assert_panics` body. If evaluating the predicate itself panics, V0002 does not fire. A later solver may widen the scope to all Refuted cases under the same code. It must check that Γ is satisfiable, or else every dead branch would be "refuted" for no reason.

- **DevOps/Tooling:**

> ## P1 (my pick): V0002 becomes a warning, and it fires only when a check fails on every run
>
> **The problem I see.** §3b.4 lets the word "Disproven" cover two different cases.
> - **Symbolic counterexample.** The solver finds *one* input that fails, such as `amount = -5` from a parameter or `config.port = 0` from a field. That means "this call can fail", which is the Unknown case. §3b.1 already says "When the value is dynamic, the compiler inserts a check at the boundary". So the V0002 examples at §3b.1:37 and §3b.2:128 contradict their own block.
> - **Certain failure.** Every argument the predicate reads is a literal tree, and the predicate is false. The check fails on every run that reaches the call. This has the same shape as W0704 and W0708.
>
> **Rules:**
> 1. V0002 keeps its code, gets the name `ContractAlwaysFails`, and becomes a **warning**. It fires when a `@requires` is false for every execution that reaches the call. With no solver, it fires only when each argument the predicate reads is a literal tree (W0708 leaf rule: literals, parentheses, unary `-`, arithmetic) and the compiler can evaluate the predicate as a const expression. A `let` or `const` reference stops the tree.
> 2. It fires in dead branches. It does not fire inside an `assert_panics` body. You can suppress it with `@allow(ContractAlwaysFails)`, and set its level with `V0002 = "off"` or `"error"` under `[lints]`. It fires whatever the callee's `@verify` says, because with `"trust"` there is no check to catch the bad value.
> 3. A symbolic counterexample is an **Unknown** outcome. The runtime check stays. `blink verify` and the V0004 detail line show the counterexample. Under `@verify(fallback: "error")`, V0003 shows it. This gives strict teams a control that already exists, with no new one.

- **AI/ML:**

> ### P1 (recommend): Disproven = must-fail; V0002 is a warning lint
>
> 1. **Scope.** A check is *Disproven* only when it fails on every run that reaches it. "Some input violates it" (may-fail) is *Unknown* → default runtime check (V0004). Before a solver exists, Disproven covers one case: every argument the predicate reads is a literal (number, string, list, range literal) and the predicate evaluates false. Same scope as W0704/W0708: `let`/`const` refs do not count.
> 2. **Severity.** `warning[V0002] ContractViolated`. A lint: `"error"` under `[lints]`, `@allow(ContractViolated)`. Does not fire inside an `assert_panics` body. Fires in dead branches. The runtime check stays; the warning adds to it, never replaces it.
> 3. **`@verify(fallback: "trust")`** removes the runtime check but not the warning (a model can still read the literal call site against the trusted contract).

- **Minimalism:**

> ### P1 (my pick). V0002 becomes a warning for a certain violation; any other counterexample falls to Unknown
>
> **Rule.**
> 1. **Certain violation.** Every argument that a `@requires` clause (or a `@where` refinement) reads is a literal at the call site, and the folded clause is `false`. This gives **warning V0002 ContractViolation**. It has the same shape as W0704 and W0708:
>    - It does not fire on `let` or `const` references.
>    - It fires in dead branches.
>    - It does not fire inside an `assert_panics` body.
>    - `@allow(ContractViolation)` suppresses it, and `[lints]` can set it to `"error"`.
>    - The runtime check stays, so the call still panics in every build mode.
> 2. **Counterexample on a free input** (a parameter, a struct field, I/O). This is not a disproof of the program. It means the solver could not prove the clause, so the outcome is **Unknown**: a runtime check, V0004.
> 3. The text "Disproven (Compile Error with Counterexample)" changes to "Disproven (Warning with Counterexample)". F2 stays true: `@verify(fallback:)` has no effect on this outcome.

#### Phase B — Debate highlights

The dedupe left more than two options, so Phase B ran. Every seat rejected Option B (an error that `assert_panics` silences) and every seat chose `ContractAlwaysFails` as the name. All six replied `READY` after round 1.

**The name.** Each seat dropped its own earlier name for `ContractAlwaysFails`:

- **Systems:**

> **V1. Lint name: `ContractAlwaysFails`.** I withdraw `ContractViolatedOnLiteral`. "OnLiteral" names the scope before a solver exists. The name goes stale on the day a solver widens the scope (V6), and the code and name must stay fixed. `ContractViolated` and `ContractViolation` read like the runtime `validation.contract_violation(...)` and the panic message, so a reader cannot tell the compile-time lint from the run-time failure. `ContractAlwaysFails` says what the rule is: it fails on every run.

- **Web/Scripting:**

> **V1. Lint name: `ContractAlwaysFails`.** The name should say what happens, because users read lint names in `@allow(...)` and in `[lints]`. `ContractViolation` (Min) and `ContractViolated` (AI/ML, PLT) read like the runtime panic, the event itself, and not like a compile-time warning that it will happen. A Python dev who sees `@allow(ContractViolation)` will think it turns off the runtime check. `ContractViolatedOnLiteral` (Sys) is accurate today, but it goes wrong as soon as a solver adds must-fail cases that are not literals (V6). `ContractAlwaysFails` stays true under both.

- **PLT:**

> **V1. Name: I switch to `ContractAlwaysFails`.**
> - `ContractViolated` (my own pick) is not precise enough. It also reads like the runtime event `validation.contract_violation`, and a lint name should name the static fact, not the runtime one.
> - I reject Sys's `ContractViolatedOnLiteral` and DevOps's `LiteralContractViolation`. "Literal" names today's trigger, not the meaning. Under V6 a later solver widens the trigger past literals, and the name would then be wrong.

- **DevOps/Tooling:**

> **V1. Name: `ContractAlwaysFails`.** My second choice is `ContractViolated`.
> - Against Min's `ContractViolation`: a failed check at a system boundary raises `validation.contract_violation(...)` (§4.4.2). Then one name means two things, a compile-time lint and a runtime error. A user who greps logs or a model that reads `@allow(ContractViolation)` will mix them up.
> - Against Sys's `ContractViolatedOnLiteral`: PLT and AI/ML say a later solver may widen the scope under the same code (V6). Then "OnLiteral" becomes false, and we cannot rename a lint without breaking every `@allow` and `[lints]` entry.
> - `ContractAlwaysFails` states the trigger, which is certainty, and does not tie it to how the compiler found it.

- **AI/ML:**

> **V1. Lint name: `ContractAlwaysFails`.** I drop my `ContractViolated`. The name should say what triggers it, so a model can guess when it fires from the name alone. "Violated" and "Violation" read like "some input fails", which is the very confusion this ticket fixes. Sys's `ContractViolatedOnLiteral` turns false the day a solver widens the scope (V6), and then the name lies. `ContractAlwaysFails` stays true before and after a solver.

- **Minimalism:**

> **V1. Name: `ContractAlwaysFails`.** I drop my `ContractViolation`. It says less than the rule does: a violation found on some input sounds the same as a violation on every run, and Option A splits exactly those two cases. Against Sys's `ContractViolatedOnLiteral`: it puts the scope we use before a solver exists into the name. Under V6 a solver widens the scope under the same code, and the name would then be false. `ContractViolated` (PLT, AI/ML) has the same problem as mine.

**Systems withdrew its rule 3** (to change F2 so that `"error"` treats a may-fail counterexample as V0003):

> I withdraw my rule 3 (change F2). PLT rule 5 is right: once may-fail is Unknown, `"error"` already makes it V0003 under the current text, and no F2 edit is needed.

**Minimalism conceded the Range and `rand` point:**

> **V9. I concede the fact.** The user-facing wrapper is `rand.int(r: Range[Int])`, not the two-`Int` op (04_effects.md:1287). So the `rand.int(5..5)` case does need Range bound accessors, and that is a separate ticket, as Sys, Web, AI/ML and PLT said. My point still holds: this decision does not wait on that ticket, and it adds no Range API. My Phase A example stands as a plain user function, renamed so it does not look like `rand.int`:

#### Phase C — Final vote

Each ballot gave a vote, a reasoning and a concern. The reasoning of each seat is below, verbatim. The concerns are in the Concerns list at the end. Tallies:

**Q1. Core rule** — 6-0 A

- **Systems** (A): Severity changes no code; only Proven removes a check. An error adds no runtime safety, and it lets solver version decide whether a build passes. A also keeps `10 / 0` and `safe_div(10, 0)` at one severity.
- **Web/Scripting** (A): A user learns one rule. A literal input that is certain to panic gets a warning, and the program still panics at run time. That covers `/ 0`, overflow and `@requires` alike. B means `10 / 0` warns while `safe_div(10, 0)` errors, which is the kind of split that keeps generating "why?" questions. A also means a solver arriving later never breaks a green build.
- **PLT** (A): Under A, whether a program is accepted does not depend on solver strength, so a stronger solver can never reject a program an older one accepted. The meaning of a call is also the same wherever it is written; only the lint is scoped by context. B makes `assert_panics` change whether a program is well-formed, and that does not compose. A also gives `/ 0`, literal overflow and `@requires` one rule.
- **DevOps/Tooling** (A): A warning gives one model for W0704, W0708 and V0002: the same `assert_panics` fence, the same `@allow`, the same `[lints]` level. The build result never depends on solver strength, so upgrading the compiler cannot turn a green build red. B would add the first error that a block turns off, and no config could change its level.
- **AI/ML** (A): One rule now covers `/ 0`, literal overflow and `@requires`: if a literal must panic, the compiler warns and the panic stays. A model learns it once. B gives the same shape two severities and adds an error that a block silences, which is two exceptions to memorize. A also makes compile success independent of the solver, so code written from the spec does not stop compiling when the solver changes.
- **Minimalism** (A): Option A keeps one rule for the whole certain-panic family: a warning plus the runtime panic, the same as W0704, W0708 and Rand Q7c. B adds a second severity for the same fault, plus a special exemption for `assert_panics` that it only needs because it chose an error. A also means a later solver can never break a build.

**Q2. Lint name** — 6-0 `ContractAlwaysFails`

- **Systems** (`ContractAlwaysFails`): It names the rule, not the scope before a solver exists, so it stays correct when a solver widens the scope. It does not clash with the runtime `validation.contract_violation`.
- **Web/Scripting** (`ContractAlwaysFails`): The name says what the compiler knows: this call will fail. `ContractViolation` reads like the runtime event. A user who sees `@allow(ContractViolation)` could easily think it turns off the check. The name also stays true once a solver adds must-fail cases that are not literals.
- **PLT** (`ContractAlwaysFails`): The name states the static fact, which is that the check fails on every run that reaches the call. It does not name the trigger, which is literals today and a solver later. It does not read like the runtime event `validation.contract_violation`.
- **DevOps/Tooling** (`ContractAlwaysFails`): It names the trigger (certainty), not the method. So it stays true when a solver widens the scope. It avoids a collision with the runtime `validation.contract_violation(...)`, which `ContractViolation` would cause in logs and in `@allow` lists.
- **AI/ML** (`ContractAlwaysFails`): The name states the trigger, so a model can guess when it fires without the catalog. It stays true when a solver later widens the scope. "Violated" reads like "some input fails", which is the mix-up this ticket fixes.
- **Minimalism** (`ContractAlwaysFails`): The name states the trigger, which is false on every run, so it marks the split from a may-fail counterexample. It does not put the pre-solver literal scope into the name, so it stays true when a solver widens the scope.

**Q3. `@where` refinements** — 6-0 yes

- **Systems** (yes): One fold, one code, one diagnostic for `@requires` and `@where`. Without this, the fixed §3b.1 `listen(0)` example has no rule behind it.
- **Web/Scripting** (yes): `fn listen(port: Port)` and the same rule written as `@requires` must behave the same. If they did not, the spelling would quietly change the diagnostic, and nobody could explain why in five minutes. §3b.1 `listen(0)` relies on this rule.
- **PLT** (yes): `fn listen(port: Port)` and `@requires(port > 0 && port <= 65535) fn listen(port: Int)` mean the same thing. If they gave different diagnostics, the two spellings would not be interchangeable, which breaks a basic equivalence the language should keep. The §3b.1 example fixes already assume this.
- **DevOps/Tooling** (yes): `fn listen(port: Port)` and the equivalent `@requires` must give the same code, name and related span. Otherwise the LSP and `@allow` act differently for two spellings that mean the same thing. The related span points to the `@where` clause.
- **AI/ML** (yes): `fn listen(port: Port)` and the `@requires` spelling must behave the same, or a model has one more decision point between two spellings that mean the same thing. The §3b.1 `listen(0)` fix needs this rule.
- **Minimalism** (yes): A refinement is a `@requires` with a type name on it. Two spellings with one meaning must give one diagnostic. If they do not, we add surface area that does nothing.

**Q4. `@verify`** — 6-0 yes

- **Systems** (yes): Under `"trust"` the runtime check is gone, so a literal call that is sure to fail runs the body on bad input. The warning is the only signal left. Classing a may-fail counterexample as Unknown gives V0003 under `"error"` with no new control.
- **Web/Scripting** (yes): Under `"trust"` there is no runtime check, so the warning is the only signal left. It has to stay. Saying "a counterexample on a dynamic input is Unknown" makes it plain that strict teams get V0003 through a control that already exists.
- **PLT** (yes): An always-fails outcome holds whatever `@verify` says, so F2 stays true as written. Under `"trust"` the warning matters most, because no check catches the bad value. Once may-fail is classified as Unknown, `"error"` gives V0003 with no new rule.
- **DevOps/Tooling** (yes): With `"trust"` there is no runtime check, so the warning is the only signal left. It must fire. F2 stays true as written, and the added sentence sends the may-fail case to V0003 through a control that already exists, with no new flag.
- **AI/ML** (yes): The warning reads only the call site and the declared contract, so the fallback should not change it. Under `"trust"` it is the only signal left. The added sentence ends the §3b.1 contradiction without a new rule, because "error" already covers Unknown.
- **Minimalism** (yes): F2 stays as it is, and the added sentence only states what Option A already implies: a may-fail counterexample is Unknown. That gives strict teams `"error"` → V0003 with no new knob. Firing under `"trust"` is right, because under `"trust"` the warning is the only signal left.

**Q5. Where a may-fail counterexample shows** — 6-0 yes

- **Systems** (yes): It is the same data in three places, and none of them changes codegen. Strict teams get the counterexample where they already look.
- **Web/Scripting** (yes): The counterexample stays available to anyone who looks for it, and the default build gets no noisier, because V0004 is silent by default.
- **PLT** (yes): These three sites carry the same information at different levels of strictness, and none of them conflicts with another. The counterexample is useful whenever the solver has one, and none of these sites changes acceptance by default.
- **DevOps/Tooling** (yes): Under `"error"`, the V0003 message is where the user needs the counterexample most. V0004 is silent by default, so the note costs nothing in a normal build. `blink verify` is the report that tools and CI read.
- **AI/ML** (yes): There is one location for each outcome and no new code. The counterexample stays visible to tools and agents that read `blink verify`, and it does not break any build.
- **Minimalism** (yes): None of the three places is a new diagnostic. Each one reuses an output that already exists, and V0004 is silent by default, so it adds no noise.

**Q6. Which arguments count as literal** — 5-1 L1 (Minimalism dissent)

- **Systems** (L1): The predicate goes through the const evaluator anyway. Its bound is the evaluator, not the leaf grammar. Leaving out string, list and range literals would miss common predicates such as `s.len() > 0` on `""` for no cost saving.
- **Web/Scripting** (L1): `get_unchecked([], 0)` is the first example any user will try. If it does not warn, the result looks broken. Folding through the E0546 const evaluator keeps the scope exact. Stopping at `let`/`const` matches W0704.
- **PLT** (L1): The rule that matters is semantic: after the arguments are put in, the predicate is closed and folds to `false`. The leaf set only marks which terms count as closed. List, string and range literals are as closed as numbers, and E0546's evaluator already folds them. If they are left out, `get_unchecked([], 0)` and range calls get a false negative for no principled reason.
- **DevOps/Tooling** (L1): The spec examples that we fix, such as `get_unchecked([], 0)`, need a list literal. A `@requires` reads values of any type, but W0704 and W0708 read only integers, so a wider leaf set does not split the family. The const evaluator that E0546 uses gives every tool the same answer with no solver.
- **AI/ML** (L1): The W0704 and W0708 operands are scalars, so list, string and range leaves cannot conflict with those rules. They only add the cases V0002 needs: `get_unchecked([], 0)`, and later `rand.int(5..5)`. L1 states an exact list of leaves now, which a model can apply the same way every time. L2 leaves a known gap and promises a second spec edit.
- **Minimalism** (L2 (dissent)): The family should share one definition of "literal". V0002 should not grow its own wider leaf rule while W0704 and W0708 keep the narrow one. Widening the shared rule to include list, string and range literals is the certain-panic ticket's job, and that ticket can do it for every lint in the family at once.

**Q7. Text on later solver widening** — 3-3 (S1: Systems, PLT, DevOps; S2: Web, AI/ML, Minimalism). Sent to Phase D

- **Systems** (S1): "False on every run that reaches the call" is meaningless without a satisfiable path condition. Dead code would be refuted for free and flood dead branches with hits. State the rule exactly now, so the solver ticket implements a rule and does not invent one.
- **Web/Scripting** (S2): One plain sentence holds the guarantee users care about: one counterexample never counts. The satisfiability detail is solver design work and belongs in the solver ticket, not in user-facing spec text.
- **PLT** (S1): The satisfiability condition is part of the rule's meaning, not an implementation detail. If no run reaches the call, the statement "false on every run that reaches the call" is vacuously true, so S2 without the condition would flag every dead branch. That is the case the spec should rule out in its own text.
- **DevOps/Tooling** (S1): The path-condition rule is what keeps a solver from warning on every `if false` body. Without it, a solver release would flood builds with false positives. The rule is short, so it should be in the spec now rather than left to a future ticket.
- **AI/ML** (S2): The spec should state what the user sees: a hit only where every run fails, and never on one counterexample. That one sentence is enough for a model to predict the behaviour. The satisfiability check is how a solver meets that promise, so it belongs in the solver ticket.
- **Minimalism** (S2): We have no solver. One sentence fixes the constraint that matters: a single counterexample never counts. The satisfiability rule is correct, but it is solver design. Putting it in the spec now writes rules for a component that does not exist.

**Q8. `@ensures`** — 6-0 out for now

- **Systems** (out for now): An `@ensures` with literal arguments needs the body evaluated, which is solver or interpreter work with no bound on compile time.
- **Web/Scripting** (out for now): With literal arguments, `@ensures` still needs the function body evaluated, and that is solver work. Keep this ticket small.
- **PLT** (out for now): An always-false `@ensures` is a fault at the definition site, and finding it means evaluating the body. That is a different judgment, so it needs its own rule.
- **DevOps/Tooling** (out for now): An `@ensures` with literal arguments needs the body evaluated, and that is solver work. Leaving it out keeps the trigger something a tool can check without running a solver.
- **AI/ML** (out for now): With literal arguments, an `@ensures` check still needs the body to be evaluated, which is solver work. Keeping the scope to `@requires` and `@where` keeps the rule small and exact.
- **Minimalism** (out for now): An `@ensures` check needs the callee body evaluated even when every argument is a literal, and that is solver work. Adding it now gives no gain.

**Q9. Fold failure** — 6-0 yes

- **Systems** (yes): The fold must be bounded and the same on every machine. A panic, an FFI call or a step-limit hit in the folder is the compiler's limit, not a fact about the user's call.
- **Web/Scripting** (yes): We must never say "contract always fails" when we could not evaluate the contract. Falling back to the runtime check loses nothing.
- **PLT** (yes): A fold that does not finish proves nothing, so the outcome is Unknown and the runtime check is the sound default. A false negative here is safe. The runtime panic and W0704/W0708 still cover the subexpression.
- **DevOps/Tooling** (yes): The user did not write the predicate at the call site, so a fold failure must not show up there as a diagnostic. A fold that cannot finish means nothing is certain, which is the Unknown case. That keeps the lint free of false positives.
- **AI/ML** (yes): Without this, two tools could give different answers for the same code. Falling back to Unknown keeps the runtime check, so nothing becomes less safe.
- **Minimalism** (yes): V0002 reports only what the fold proves. A fold that panics, cannot run, or hits its limit proves nothing, so the outcome falls back to the safe default, which is Unknown with a runtime check.

**Q10. Range bounds** — 6-0 yes

- **Systems** (yes): The user calls `rand.int(r: Range[Int])`. A `@requires` on the `int(lo, hi)` effect op would fire inside the stdlib wrapper, never at the user's literal call site. Bound accessors are a separate API decision.
- **Web/Scripting** (yes): The user-facing API is `rand.int(r: Range[Int])`, and this ticket should not reshape it. Once Range has bound accessors, `rand.int(5..5)` warns for free through its own `@requires`.
- **PLT** (yes): The user-facing `rand.int` takes a `Range[Int]`, so its `@requires` needs bound accessors. That is an API decision this panel was not asked to make. Once it exists, the general rule covers `rand.int(5..5)` with no list of special APIs, which is what Q3-R asked for.
- **DevOps/Tooling** (yes): `rand.int` takes `Range[Int]`, so its `@requires` cannot read the bounds until `Range` has accessors. That is a separate API decision. This rule then covers `rand.int(5..5)` with no API list in the typecheck, as Q3-R asks.
- **AI/ML** (yes): This keeps the ticket on one subject and avoids designing a Range API without a panel. The follow-up gives F11 a clear path through the API's own `@requires`.
- **Minimalism** (yes): This keeps the decision small and adds no Range API until an API needs one. The `rand.int(5..5)` case then goes through the same `@requires` path as everything else, with no special case for `rand`.

**Q11. §3b.4 heading** — 5-1 H1 (AI/ML dissent)

- **Systems** (H1): It is short and matches the lint name. The example output can still show the counterexample block, because the literal values are the counterexample.
- **Web/Scripting** (H1): The heading is short and plain. For a literal call, the "counterexample" is just the arguments the user already typed, so the heading does not need to mention one. The example output can still show it.
- **PLT** (H1): On all-literal input there is no counterexample to search for. The "counterexample" is just the call's own arguments, so the word brings back the old may-fail reading. The heading should match the lint name.
- **DevOps/Tooling** (H1): In the literal case, the values come from the call site, not from a search. "Counterexample" suggests a solver, and there is no solver today. The short heading matches the lint name.
- **AI/ML** (H2 (dissent)): The heading matches the lint name and tells the reader that the diagnostic carries the failing values, which is the main help for a model fixing the call.
- **Minimalism** (H1): For a literal call, the counterexample is the call's own arguments, so "with Counterexample" says nothing new. A shorter heading that matches the lint name is enough.

#### Phase D — Q7 (solver widening text)

Q7 was 3-3 in Phase C. Each seat wrote a reply to the other side and offered a wording. Three seats moved: Web, AI/ML and Minimalism changed from S2 to S1. The cause, in PLT's words: "In S2's sentence, 'every run that reaches the call' is vacuously true when no run reaches the call. The spec text itself then permits dead-branch hits". Replies, verbatim:

<details>
<summary>Systems — Phase D debate</summary>

**Sys seat — Phase D, Q7**

All three S2 seats name the same concern: dead branches would flood with false V0002 hits. They agree the guard is correct, and they disagree only on where it goes. So the guard itself is not disputed. The open question is whether the spec text, read alone, allows the flood.

S2's sentence does allow it. "False on every run that reaches the call" is vacuously true when no run reaches the call. A solver that follows S2 to the letter may flag every dead branch, and that would still be conformant. A rule that relies on a ticket to stay correct is not a rule. Tickets are local-only and do not ship with the spec.

DevOps's point makes this worse. The literal tier does fire in dead branches, on purpose (the W0704 shape). A reader of S2 will take that as the model for the solver tier.

My position is unchanged on substance, and I accept S2's plain wording with one added clause:

> "A solver may add a V0002 hit only where some run reaches the call and every run that reaches it fails the predicate. One counterexample never counts. This applies only to solver hits; literal hits fire in dead branches."

It uses no solver jargon, it rules out the flood, and both tiers sit next to each other.

</details>

<details>
<summary>Web/Scripting — Phase D debate</summary>

**Web seat — Phase D, Q7**

**Position changed: S2 → S1.**

PLT's point holds. If no run can reach the call, then "false on every run that reaches the call" is true with nothing to check. So the S2 sentence, read as written, allows a hit in every dead branch. That makes S2 more than a short version of S1. It is a wrong rule. All three S2 seats, me included, wrote the same concern: "the solver ticket may forget the guard". When every supporter of an option names the same hole in it, the fix belongs in the text.

I still want the words to stay plain for users, so I support S1 with two limits:
- Use one sentence and everyday words. For example: "A solver may add a V0002 hit only where it proves that some run can reach the call and that every such run fails the check. One counterexample never counts."
- State that this applies only to solver hits, as PLT and Sys both asked. The literal tier still fires in dead branches. Put that rule next to this one, as DevOps asked, so readers do not see a conflict between the two.

</details>

<details>
<summary>PLT — Phase D debate</summary>

**PLT seat: Phase D, Q7**

The S2 side is right that the spec should describe what the user sees, not how a solver works. "Path condition" and "satisfiable" are solver words.

But all three S2 seats name the same concern: the solver ticket might drop the guard. A guard that keeps the rule true does not belong in a ticket. In S2's sentence, "every run that reaches the call" is vacuously true when no run reaches the call. The spec text itself then permits dead-branch hits, and a solver that flags dead branches would be following the spec, not breaking it. Web's remedy, "link that ticket to this decision", only means the guard lives somewhere less visible than the spec.

The guard needs no jargon. I propose S2's single sentence with one word added:

> A solver may add a V0002 hit only where the call is reachable and the predicate is false on every run that reaches it. One counterexample never counts.

"Reachable" is plain English, and it is exactly the satisfiability condition. This also covers DevOps's point: next to the literal rule, it says outright that the literal tier fires in dead branches and the solver tier does not.

My position: on substance, S1 does not change. On wording, I accept S2's form if "reachable" is added. If the vote must be one of the two texts as written, I stay S1.

</details>

<details>
<summary>DevOps/Tooling — Phase D debate</summary>

**DevOps/Tooling seat: Phase D, Q7**

All three S2 seats name the same concern: "the solver ticket could drop the satisfiability check, and then dead branches would get false V0002 hits" (Min, and Web and AI/ML in other words). The S2 side agrees that the rule is correct. What we disagree on is where the rule lives. A rule that only a ticket holds is not a rule. A second implementation, an LSP or a model that reads the spec will not see the ticket. S2's sentence, read literally, is vacuously true for dead code, so the spec text itself would permit the flood.

Web, AI/ML and Min also have a fair point: solver terms in user-facing text are premature. So I offer a wording that gives S1's meaning in S2's plain words:

> "A solver may add a V0002 hit only where it shows that some run reaches the call and that every such run fails the check. One counterexample never counts."

This has no "path condition" and no "satisfiable", and it does not leave the dead-branch case open. Right next to it, the spec says that the literal tier fires in dead branches.

My position has not changed: S1 in meaning. I accept the wording above as S1 or as an amended S2.

</details>

<details>
<summary>AI/ML — Phase D debate</summary>

**AI/ML seat — Phase D, Q7**

**My position changed: S2 → S1.**

PLT's point is about how the text reads, not about solver design. "False on every run that reaches the call" is vacuously true when no run reaches the call. A model reading S2 literally would predict a solver hit in every dead branch. My own Phase C concern was that this flood might happen, and I put the fix in a ticket that may never be read. A spec sentence that is wrong when read literally is worse for a model than one extra clause. So the condition belongs in the text.

Web and Min worry about writing rules for a solver that does not exist. That is answered if the sentence is scoped. I adopt the two conditions from PLT's and DevOps's concerns:

1. The satisfiability clause applies only to hits a solver adds. The literal tier needs no solver.
2. The literal rule ("fires in dead branches") and the solver rule ("only under a satisfiable path condition") sit side by side, so readers do not take them as a conflict.

Suggested text: "A solver may add a V0002 hit only where it proves the predicate false under a satisfiable path condition. One counterexample never counts. The literal tier above needs no solver and fires in dead branches."

</details>

<details>
<summary>Minimalism — Phase D debate</summary>

**Min — Q7 debate**

**I change my position to S1.**

PLT's point holds. If no run reaches the call, "false on every run that reaches the call" is vacuously true. So the S2 sentence does not leave a detail for later. As written, it allows every dead branch to get a hit. A spec sentence that says the wrong thing on a plain reading is a latent bug, and it is not "less surface". Leaving the fix to the solver ticket means the spec and the ticket can disagree, and the spec wins.

The cost is about ten words, not a new concept. My YAGNI objection was that this writes rules for a component that does not exist. Every S2 seat also states the same concern ("the solver ticket could drop the satisfiability check"). When both sides name the same failure, the cheap fix is to write the rule down.

I take two conditions from the S1 seats:
- **PLT:** say the condition applies only to hits from a solver.
- **DevOps:** put the two tiers side by side. The literal tier fires in dead branches by design (the W0704 shape), and the solver tier requires a satisfiable path condition.

**Suggested text:** "A solver may add a V0002 hit only when it proves the predicate false under a satisfiable path condition. One counterexample never counts. The literal rule above is unchanged and still fires in dead branches."

</details>

Each seat then voted alone on S1 or S2 (Q7) and on the wording of the sentence (Q7w), from six texts that came from the replies.

- **Q7 (6-0, S1):** the guard that some run reaches the call is part of what the rule means. The spec carries it, not only a later solver design.
- **Q7w (6-0, T-Sys):** T-Sys is in plain words and is the only text that says, in the same sentence, that literal hits still fire in dead branches.
- **Editorial edits taken from the concerns**: Systems asked that the burden of proof sit on the solver, so "where some run reaches the call" became "where it proves that some run reaches the call" (from T-Web). Web and DevOps asked for "the predicate is false" in place of "fails the predicate", to match the rest of §3b.4. Systems, PLT, DevOps and Minimalism asked that the text make clear it governs only solver hits, so a reader does not take it as a rule for a compiler that has no solver; the final sentence keeps "A solver may add" and ends with "This applies only to solver hits".

<details>
<summary>Systems — Phase D ballot</summary>

**Sys seat — Phase D re-vote**

**Q7. Vote: S1**
- **Reasoning:** Without the reachability guard, the spec text allows a solver to flag every dead branch and still conform. The rule must hold from the spec alone; a local ticket does not ship with the spec. Plain wording removes the "solver jargon" objection, so the remaining choice is only the exact text.
- **Concern:** Someone may read the sentence as a requirement that applies today, before any solver exists, so the text must keep "a solver may add".

**Q7w. Vote: T-Sys**
- **Reasoning:** It is the only text that names both tiers next to each other. Literal hits fire in dead branches, and solver hits need a run that reaches the call. That stops readers from taking the W0704 dead-branch shape as the model for the solver tier, which is the conflict DevOps flagged. It also uses no solver jargon. I accept T-Web's "proves that" in place of "where" as an edit, because it puts the burden on the solver to show reachability, not to assume it.
- **Concern:** The third sentence makes the paragraph longer, and an editor may cut it as redundant with the literal rule above. If that happens, the two-tier contrast is lost.

</details>

<details>
<summary>Web/Scripting — Phase D ballot</summary>

**Web seat — Phase D ballot**

**Q7. Vote: S1**
- Reasoning: The S2 sentence, read literally, allows a hit in every dead branch, because "every run that reaches it fails" is true when no run can reach it. All three S2 seats named that same hole in Phase C, so the guard belongs in the spec text. The cost is one short clause.
- Concern: Readers who have never seen a solver may think the reachability clause applies to the literal tier too.

**Q7w. Vote: T-Sys**
- Reasoning: T-Sys is the only text that meets both of my limits. It uses plain words ("some run reaches the call", with no "satisfiable path condition"), and it states in the same place that literal hits still fire in dead branches. That last sentence answers my concern on Q7 and the concern DevOps raised. T-AI/ML and T-Min also scope the literal tier, but they use solver jargon. T-PLT, T-DevOps and my own T-Web leave the literal-tier sentence out.
- Concern: The phrase "every run that reaches it fails the predicate" puts "fails" next to "predicate". It may read more smoothly as "the predicate is false on every run that reaches it".

</details>

<details>
<summary>PLT — Phase D ballot</summary>

**PLT seat: Phase D vote**

**Q7. Vote: S1.**
Reasoning: The guard that some run reaches the call is what keeps "fails on every run" from being vacuously true, so it is part of the rule's meaning. Every one of the six Phase D texts now states that guard, and every S2 seat named its loss as their concern. The guard belongs in the spec, not only in a later ticket.
Concern: Readers may take the sentence as a requirement on today's compiler, which has no solver. The text must make clear it governs only solver hits.

**Q7w. Vote: T-Sys.**
Reasoning: It states the reachability guard in plain words, with no "path condition" or "satisfiable". It is also the only text that says, in the sentence itself, that the solver tier and the literal tier differ on dead branches, which settles DevOps's concern that the two rules look like they conflict. T-Web and T-DevOps are equally sound but leave that difference out, and T-AI/ML and T-Min bring back solver jargon.
Concern: "Some run reaches the call" does not say outright that the solver must establish this rather than assume it. The words "only where" carry that meaning, but an implementer could read the condition loosely.

</details>

<details>
<summary>DevOps/Tooling — Phase D ballot</summary>

**DevOps/Tooling seat: Phase D re-vote**

**Q7. Vote: S1**
Reasoning: Every seat agrees that the reachability rule is correct. The S2 seats name its loss as their own concern. A rule that only a ticket holds does not bind a second implementation, the LSP or a model that reads the spec. The Phase D wordings show that the rule fits in plain words, so the "solver jargon" objection no longer holds.
Concern: Readers may take the sentence to mean that the compiler needs a reachability check before a solver exists, so the text must say that it covers only solver hits.

**Q7w. Vote: T-Sys**
Reasoning: It is in plain words: no "path condition" and no "satisfiable". It is also the only text that says, in the same place, that the rule covers only solver hits and that literal hits still fire in dead branches. That answers my Phase C concern that the two tiers would read as a conflict. My own T-DevOps says the same thing about solver hits but leaves out the tier contrast.
Concern: "fails the predicate" is loose. The editor should write "the predicate is false" so that the text matches the rest of §3b.4.

</details>

<details>
<summary>AI/ML — Phase D ballot</summary>

**AI/ML seat — Phase D re-vote**

**Q7. Text on later solver widening**
- **Vote:** S1
- **Reasoning:** Read literally, S2 is vacuously true for dead code, so a model reading it would predict a solver hit in every dead branch. The reachability condition is part of what the rule means. It costs one clause, and the spec text stays exact.
- **Concern:** Readers may take the solver rule and the literal rule to conflict, unless the sentence states both of them.

**Q7w. Wording of the solver sentence**
- **Vote:** T-Sys
- **Reasoning:** T-Sys says "some run reaches the call", so it states the condition in plain words, where "satisfiable path condition" is jargon a model has to translate. It is the only text that is plain and also states both tiers next to each other ("literal hits fire in dead branches"), so it answers the conflict concern in the same sentence. I drop my own wording (T-AI/ML) in favour of this one.
- **Concern:** "Some run reaches the call" can be read as asking for proof of reachability, which no solver can always give. The solver ticket must say that a solver that cannot prove reachability adds no hit.

</details>

<details>
<summary>Minimalism — Phase D ballot</summary>

**Min — Phase D re-vote**

**Q7. Solver widening text**
- **Vote:** S1
- **Reasoning:** The S2 sentence is vacuously true for a call that no run reaches, so a plain reading of it allows a hit on every dead branch. A sentence that is wrong when read literally is a bug, not a saving. Fixing it costs a few words and adds no new concept.
- **Concern:** Readers may take the sentence to mean the compiler checks reachability today, before any solver exists.

**Q7w. Wording**
- **Vote:** T-Sys
- **Reasoning:** It says "some run reaches the call" in plain words. The other texts use "satisfiable path condition", which is solver jargon, and that includes my own text. T-Sys is the only option that states, in one place, both the reachability rule and the fact that literal hits still fire in dead branches. That answers the DevOps concern that the two tiers will look like they conflict.
- **Concern:** "This applies only to solver hits" could later be read as a loophole that frees literal hits from the "one counterexample never counts" rule, though a literal hit is never a single counterexample.

</details>

### Final Spec

```blink
@requires(amount > 0)
fn withdraw(balance: Int, amount: Int) -> Int {
    balance - amount
}

fn demo(balance: Int, n: Int) {
    withdraw(balance, -5)       // warning[V0002]: `-5 > 0` is false
    withdraw(balance, n)        // runtime check (V0004); no V0002
    let k = -5
    withdraw(balance, k)        // no V0002: a `let` reference stops the tree
}

test "a negative amount panics" {
    assert_panics { withdraw(10, -5) }   // no V0002 inside assert_panics
}
```

Locked points:

- V0002 `ContractAlwaysFails` is a warning. It fires when a `@requires`, or a `@where` refinement as an implied `@requires`, is false on every run that reaches the call. The runtime check stays.
- Without a solver, it fires when every argument that the predicate reads is a literal at the call site and the folded predicate is `false`.
- A literal is the W0708 literal tree, or a list, string or range literal whose parts are literal trees. A `let` or `const` reference stops the tree. The predicate folds in the const evaluator behind E0546.
- No V0002 when the fold panics, the predicate cannot be evaluated, or the evaluator reaches its limit. The outcome is Unknown, with a runtime check.
- A solver may add a V0002 hit only where it proves that some run reaches the call and that the predicate is false on every run that reaches it. One counterexample never counts. This applies only to solver hits; literal hits fire in dead branches.
- The shape of W0704: no `let`/`const` reference, dead branches fire, no hit inside an `assert_panics` body, `@allow(ContractAlwaysFails)`, level under `[lints]`. Only `[lints]` changes the level; `@verify(fallback: "error")` does not.
- V0002 fires under every `@verify` value, `"trust"` included. A counterexample on a dynamic input is an Unknown outcome; `"error"` gives V0003 for it.
- A counterexample shows in a note on V0004, in the `blink verify` report, and in V0003 under `"error"`.
- `@ensures` is not part of V0002 for now.
- No `rand` API change. The sentence in §4 that a range with literal ends gets no compile-time check stays true. `Range[T]` bound accessors are a separate decision.
- The §3b.4 heading is "Always Fails (Warning)". The §3b.1 and §3b.2 examples change: a dynamic `config.port` or a parameter `items` gets a runtime check; a literal call gets V0002.

### Concerns

Points the ballots raised for the implementation:

- The evaluator limit decides whether V0002 fires near the edge (Q9: DevOps, PLT, Systems, AI/ML, Web, Minimalism). Tie the limit to the E0546 evaluator, and state it, so two compiler versions do not disagree.
- The certain-panic ticket for `/ 0`, `% 0` and empty literal ranges must reuse the leaf rule of Q6 (AI/ML, DevOps, PLT, Systems, Web). Otherwise W0704, W0708 and V0002 have three definitions of "literal".
- The empty-literal-range case waits on `Range[T]` bound accessors (Q10: DevOps, AI/ML, Web, Minimalism, Systems, PLT). Link the two tickets.
- The message must say "fails on every run that reaches this call", and must name the call site (DevOps, Minimalism, Systems Q2).
- For a refinement, the diagnostic names the alias and the `@where` clause, and its related span points there (DevOps, Web, Minimalism Q3). The implementation turns the refinement into the implied `@requires` before it checks (PLT). The rule covers a parameter refinement; a `let p: Port = 0` site is not a call (Minimalism, Systems).
- The help line for V0002 names `@allow(ContractAlwaysFails)`, because a user may expect `@verify(fallback: "trust")` to silence it (DevOps Q4). The text says that `@verify` does not change V0002 (Systems, AI/ML, Minimalism Q4).
- The text of a counterexample is not stable between solver versions, so tests must not snapshot it (DevOps Q5). A missing counterexample does not mean "safe" (Systems Q5).
- A solver that cannot prove reachability adds no V0002 hit (AI/ML Q7w).
