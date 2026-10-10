[< All Decisions](../DECISIONS.md)

# Unknown Contracts Default to a Runtime Check — Design Rationale

Spec gap: a contract the checker cannot prove gave V0003 unless the code added `@verify(...)`. With no solver, every contract is Unknown, so the rule was ceremony and pushed users to `@verify(fallback: "trust")`. The question was what an Unknown outcome means by default, and what `@verify` is for after that.

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in independent-proposal → debate → vote rounds. Phase B ran one round; all six seats then signalled "stable, ready to vote". No question was closer than 5-1, so Phase D did not run. The user approved the tally.

#### Phase A — Independent proposals

Each seat's preferred proposal, verbatim. All six preferred proposals made an Unknown outcome a runtime check by default.

- **Systems:** *Sys-1 (PREFERRED): Unknown defaults to a runtime check in every build mode, with an explicit `"static"` mode for zero-cost-or-reject*

> **Rules**
>
> 1. **Unknown with no `@verify` gives a runtime check.** It is a check, not an error. V0003 stops being the default error and becomes `info[V0004]: runtime check inserted`, which appears in the verification report and in `blink query`.
> 2. **The checks run in every build mode, release included.** This matches `unreachable()` (02_syntax:1743) and `@where` (03b:9). It also matches what the compiler does today. There is no `--release` switch that removes contracts. 5c7p4d asks "does release keep them?" The answer is yes, and the 03b:540 phrase "debug builds (and optionally in release builds)" is deleted.
> 3. **New value `@verify(fallback: "static")`.** The solver must prove the contract. If the result is Unknown, the compiler gives V0003 as an error. This is the "explicit static mode" from the ticket. For systems code it is the important one, because it guarantees the contract costs nothing at runtime or the build fails. Use it on hot-loop functions.
> 4. **`"trust"` is unchanged.** It emits nothing and stays easy to search for. It is still E0913 on a trait method.
> 5. **An explicit `@verify(fallback: "runtime")` stays valid but is now redundant.** A lint hint suggests removing it, and it is never an error. The 85 places in the repo that use it keep compiling, and a later chore removes them.
> 6. **A trait method may carry `"runtime"` or `"static"`.** A trait-level `"static"` means "every impl must prove this." It follows the same replace-whole rule as today, and E0913 is unchanged.
> 7. **A failed check panics through a cold, never-inlined path.** The site description lives in rodata.
>
> ```blink
> // Default: no annotation. Unknown means an entry check plus an exit check, in every build.
> @requires(amount > 0)
> @ensures(result.is_ok() => result.unwrap().balance == old(acct.balance) + amount)
> pub fn deposit(acct: Account, amount: Int) -> Result[Account, AccountError] {
>     if amount > acct.limit {
>         return Err(AccountError.OverLimit)
>     }
>     Ok(Account { balance: acct.balance + amount, limit: acct.limit })
> }
>
> // Hot path: prove it or fail the build. No hidden check can enter this loop.
> @requires(i >= 0 && i < xs.len())
> @verify(fallback: "static")
> fn at(xs: List[Int], i: Int) -> Int {
>     xs.get(i).unwrap()
> }
>
> // The solver cannot reason about this. It is documentation only, and grep finds it.
> @ensures(result.entropy() >= 256)
> @verify(fallback: "trust")
> fn generate_key() -> PrivateKey ! Crypto {
>     crypto.random_key()
> }
> ```
>
> **The report must show the cost of each check.** For every runtime check, `blink query` and the verification report show the site, which kind it is (entry, exit, or inherited from a trait), and a cost class: O(1), calls a function, or walks a collection. They also show which `old()` snapshots the check copies. Without this report I would not accept a default that adds checks without a word.
>
> **Tradeoffs**
> - **For:** the common case adds one predicted branch. Codegen is the same in every build, so the binary you test is the binary you ship. The Principle 4 text ("runtime-checks the rest") becomes true. The rule removes the push toward `"trust"` that the ticket describes, because writing nothing now gives the safe result.
> - **For:** `"static"` gives systems code what Rust and C do not have, a compiler guarantee of zero contract cost. Today a hot function can only get zero cost through `"trust"`, which also removes all checking.
> - **Against:** checks are added without a word at the call site. The mitigation is the V0004 info, the report, and `"static"`. When a solver arrives, many of these checks disappear on their own, and no source change is needed.
> - **Against:** a costly `@ensures`, such as one that walks a list, now runs by default. An author who writes such a contract on a hot function must choose `"static"` or `"trust"`. I accept this: the author wrote the predicate, so the author asked for it to be checked.
>
> **Cross-language:** Rust `assert!` is always on and `debug_assert!` is debug-only. The Rust ecosystem regrets `debug_assert` for invariants because it hides release-only bugs. Zig ReleaseFast removes safety checks and turns violations into undefined behaviour, which Blink rejects in principle (see `unreachable`). Ada/SPARK has `Assertion_Policy` per build, and the result is a different program in each mode. Eiffel and D both made contracts depend on the build mode, and the common complaint is that the contracts are off in production, where the bugs are.
>
> ---

- **Web/Scripting:** *Web-1 (PREFERRED): Unknown means a runtime check by default, in every build mode*

> ```blink
> @requires(amount > 0)
> @ensures(result.is_ok() => result.unwrap().balance == old(acct.balance) + amount)
> pub fn deposit(acct: Account, amount: Int) -> Result[Account, AccountError] {
>     ...
> }
> ```
>
> No `@verify` is needed. The outcomes become:
> - **Proven:** the check is removed. No cost.
> - **Disproven:** V0002, a compile error, as today.
> - **Unknown:** a runtime check is inserted. `@requires` is checked at entry and `@ensures` at exit. A failure panics with the contract text, the function name and the caller's location.
>
> The opt-outs are explicit and easy to search for:
>
> ```blink
> @ensures(result.entropy() >= 256)
> @verify(fallback: "trust")        // no check: an audited gap, as today
> fn generate_key() -> PrivateKey ! Crypto { ... }
>
> @requires(i < self.len())
> @verify(fallback: "error")        // NEW: Unknown is a compile error (V0003)
> fn get_unchecked(self, i: Int) -> T { ... }
> ```
>
> `"error"` is the ticket's "explicit static mode". The new value keeps the existing `fallback:` key, so users learn one rule: the `fallback:` value says what happens when the solver cannot decide. There is no new attribute and no new keyword. With no solver, `"error"` always fails today. That is correct: the user asked for proof, and the compiler cannot give it.
>
> **Build mode policy (this also closes 5c7p4d):** runtime contract checks run in every build mode, release included. This is what the compiler already does. To remove a check, write `"trust"` on that function. There is no global flag that strips checks.
>
> **Diagnostics:**
> - V0003 fires only under `"error"`. Its help drops the "simplify the predicate" advice while no solver exists, which also fixes ebt5jr.
> - The verification report and `blink query` list each function's checks as proven, runtime or trust. The inherited trait rows already appear there.
>
> **Existing `@verify` values:**
> - `"runtime"` stays legal. It is now the same as writing nothing. Add a lint, "redundant @verify", with an automatic fix that removes it, so 85 lines leave the repo with one command.
> - `"runtime"` on a trait method declaration becomes a no-op. E0913 (`"trust"` on a trait method) stays as it is.
> - The Systems seat's vote condition from the trait-method debate holds automatically: inherited checks and plain-function checks now follow one rule.
>
> **Tradeoffs:**
> - **Win:** the 90% path becomes "write the contract, done". The `@verify` that remains (`"trust"` or `"error"`) always records a real decision, so a search for `"trust"` finds only real gaps.
> - **Cost:** checks in hot loops cost time. Two answers: (1) a proven contract costs nothing once a solver ships, and (2) an audited `"trust"` is the per-function way out. A slow program that is correct is a better default than a fast one that is silently wrong.
> - **Cost:** "the compiler holds you to it" is weaker. Under this proposal the compiler holds you to it at run time, not at compile time. A runtime check is far stronger than a comment, so the spec's real concern ("not treated as comments") still holds.
> - **Spec consistency:** this matches Principle 4 ("the compiler proves what it can, runtime-checks the rest") and the existing `@where` rule ("at boundaries when not"). Contracts are the only feature that disagrees with those today.
>
> **Cross-language:**
> - Kotlin `require()` and `check()` run in every build, and nobody asks about it on Stack Overflow.
> - Python's `assert` is removed under `-O`, and "why did my assert not fire in production" is a standing Stack Overflow question.
> - Java's `assert` is off by default, so in practice it never runs.
> - Ada/SPARK uses the same model I propose: runtime checks by default, with proof as an opt-in.
>
> ---

- **PLT:** *PLT-1 (preferred): Unknown defaults to a runtime check. Static proof becomes an explicit opt-in*

> **Rule.** Each contract gets a verification status from this ordered set: **Proven < Checked < Assumed**. For a fn `f`:
>
> ```
> status(f) = Proven                    if the solver proves {P} body {Q}
>           = Disproven (V0002)         if the solver finds a counterexample
>           = policy(f) otherwise, where
>             policy(f) = own @verify ?? trait-method @verify ?? "runtime"
> ```
>
> The `fallback:` values become:
>
> - `"runtime"`: the default. A check runs at entry (`@requires`) and at exit (`@ensures`).
> - `"trust"`: Assumed. Nothing is emitted. This value is unchanged and still the only gap.
> - `"error"` (new): Unknown is V0003. The author uses it to require a proof.
>
> I keep the key `fallback` and add `"error"`, not a `"static"` mode, because the value answers the key's own question: what happens on Unknown. This way there is one key with three values, and no second key.
>
> ```blink
> @requires(amount > 0)
> @ensures(result.is_ok() => result.unwrap().balance == old(acct.balance) + amount)
> pub fn deposit(acct: Account, amount: Int) -> Result[Account, AccountError] {
>     // no @verify: Unknown is checked at runtime, Proven costs nothing
>     Ok(Account { balance: acct.balance + amount, ..acct })
> }
>
> @requires(i >= 0 && i < xs.len())
> @verify(fallback: "error")       // this hot path must be proven; Unknown is V0003
> fn get_unchecked(xs: List[Int], i: Int) -> Int {
>     xs.get(i).unwrap()
> }
> ```
>
> **Interaction with the trait decision.** The decision text stays valid. One change: a trait method may now also carry `"error"`. This is sound because it can only *reject* impl bodies, never trust them. `"trust"` on a trait method stays E0913. An impl's own `@verify` still replaces the trait default whole. The systems seat's re-vote concern (an inherited default follows the same build-mode policy as a plain fn) now holds by construction, because there is only one policy.
>
> **Effects.** A runtime check panics, or it calls `validation.contract_violation` at a `Net.Listen` boundary, as decided. The fn's effect row does not change, so this default change breaks no API. This matches `@where` (03b:9), which already checks at boundaries with no annotation. Contracts and refinements then share one rule, "prove what you can, check the rest", and Principle 4 (01:56) holds as written.
>
> **Auditability survives in full.** In the new model the gaps are exactly the `trust` sites, so a search for `fallback: "trust"` still finds every one. The old rationale's second claim, "contracts are not comments", also holds: a runtime check is not a comment.
>
> **Diagnostics.**
> - V0003 fires only under `"error"`.
> - A Checked contract gets an `info`-level line in the verification report and in `blink query`. It gets **no warning**. A warning on the default path would rebuild today's pressure to silence it with `trust`.
> - Redundant `@verify(fallback: "runtime")` (no trait default that it overrides) gets a lint warning with an autofix. That handles the 85 existing uses. It is not redundant on an impl that overrides a trait's `"error"`, so the lint must check that case.
>
> **Tradeoff.** A contract gets a runtime cost without the author writing anything visible. The defence:
> - The cost shows in the report.
> - A proof removes it.
> - The author can remove it with an auditable `trust`, or turn it into a compile-time demand with `"error"`.
>
> The systems seat's hot-loop concern gets a per-body answer, not a global switch.

- **DevOps:** *DevOps-1 (preferred): an Unknown contract gets a runtime check by default, in every build. You can opt in to "must prove".*

> **Rules**
> 1. **Unknown means a runtime check.** `@requires` is checked at the function's entry, `@ensures` at its exit, with `old()` snapshots. No annotation is needed. This is what `"runtime"` does today, and it matches Principle 4 ("runtime-checks the rest") and what `@where` already does.
> 2. **One policy for every build mode.** A check present in debug is present in release. This closes 5c7p4d with "release keeps them". To remove a check, you either prove the contract or write `"trust"`. Both are visible in the source. No global flag strips them.
> 3. **A new value `@verify(fallback: "none")`** means Unknown stays an error (V0003, same name). It is for code that must be proven. A project can set the same default in `blink.toml`:
>    ```toml
>    [verify]
>    unknown = "error"   # default: "runtime"
>    ```
>    I picked "none" over "static" because it reads correctly after `fallback:`: there is no fallback. Like E0913, `"none"` on a trait method is allowed and applies to its impls.
> 4. **`"trust"` does not change.** It is still the only way to accept a contract with no check, so a grep for `"trust"` still finds every gap. The gap list gets more accurate, because runtime-checked contracts are no longer mixed in with trusted ones.
> 5. **Explicit `"runtime"` is still legal**, but lint W06xx `RedundantVerify` flags it, and `blink fix` removes it. It is redundant unless the project sets `unknown = "error"`, where it becomes the per-function opt-out. The lint knows this and stays quiet then.
>
> **Example**
> ```blink
> @requires(amount > 0)
> @ensures(result.is_ok() => result.unwrap().balance == old(acct.balance) + amount)
> pub fn deposit(acct: Account, amount: Int) -> Result[Account, AccountError] {
>     if acct.frozen {
>         return Err(AccountError.Frozen)
>     }
>     Ok(Account { ..acct, balance: acct.balance + amount })
> }
>
> @ensures(result.len() == input.len())
> @verify(fallback: "none")
> pub fn encode_block(input: Bytes) -> Bytes {
>     input.map(fn(b) { b ^ 0x5a })
> }
> ```
>
> **Diagnostic surface**
> - New **info V0004 ContractRuntimeChecked** sits beside V0001 (proven). It is silent by default and shown with `blink check --verify-report`:
>   ```
>   info[V0004]: contract checked at runtime
>    --> bank.bl:2:1
>     |
>   2 | @ensures(result.is_ok() => ...)
>     | ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ solver returned unknown
>     = note: checked on every exit from `deposit`
>     = help: to remove the check, prove it or add @verify(fallback: "trust")
>   ```
> - `blink check --verify-report --json` lists each contract with `outcome: proven|disproven|runtime|trust` and `source: default|explicit|inherited(Trait.method)`. This also satisfies Systems' earlier condition that the inherited row must show. `blink query --fn deposit` prints the same per-contract status. The Systems "hot loop" worry has a direct answer: `blink check --verify-report --outcome runtime` lists every check the binary pays for, and perf work starts there.
> - **The runtime failure message is part of the spec, not left to the implementation.** It gives the contract text, the span, the function, the clause kind, and the values of the free variables:
>   ```
>   panic: contract violated: @requires(amount > 0) in bank.deposit
>     --> bank.bl:1:1
>     = values: amount = -5
>     = caller: transfer_all at bank.bl:45:9
>   ```
>   This is the runtime version of V0002's counterexample. An AI agent can act on it without a debugger. The Net.Listen auto-400 path keeps working, because it consumes the same violation.
> - V0003's help changes to name real fixes in this order: "add a runtime fallback" is gone, since it is now the default. The help offers `"runtime"` (stay checked under a strict project), then simplify, then trust. This closes ebt5jr.
> - 1kgxkk folds in. A bad value gives E1110, which lists `runtime|trust|none`. `@verify` on a function with no contract gets W06xx `VerifyWithoutContract`.
>
> **Tradeoffs**
> - A program with no solver compiles. Checks are visible and countable, the trust list is exact, and debug and release behave the same, so no bug shows up only in release.
> - Cost: a runtime check now arrives without being asked for. I accept that. The cost shows up in `--verify-report`, and a check that runs costs less than a contract that gets trusted only to make an error go away.
> - When the solver ships, results only get better: Unknown turns into Proven, and checks drop out. Nothing that compiled stops compiling. Under today's rule, every solver timeout regression can break a build.
>
> **Cross-language:** Ada/SPARK runs checks unless you prove them (`gnatprove` is opt-in per unit). Dafny is all-or-nothing, which is why it is used only for verified cores. Eiffel ties checks to build mode, and that is the release-only-bug trap rule 2 avoids. Rust keeps `assert!` in release, and only `debug_assert!` is stripped.

- **AI/ML:** *AIML-1 (preferred): Unknown means a runtime check, and `@verify` names exceptions only*

> **Rule.** If a contract is Unknown and no `@verify` applies, the compiler inserts a runtime check. It does not give an error. `@verify(fallback: ...)` keeps one key and one axis: what to do on Unknown.
>
> | Value | On Unknown | Use |
> |---|---|---|
> | *(none)* | runtime check | default |
> | `"runtime"` | runtime check | redundant on a fn (lint), valid on a trait method |
> | `"trust"` | nothing emitted | audited gap, still greppable |
> | `"error"` | V0003 | opt-in strict mode: "this must be proven" |
>
> I propose `"error"`, not a new `static` key. It keeps one annotation shape, so the model learns one table and not two axes. `@verify(fallback: "error")` also reads literally: if verification falls back, fail.
>
> ```blink
> @requires(amount > 0)
> @ensures(result.is_ok() => result.unwrap().balance == old(acct.balance) + amount)
> pub fn deposit(acct: Account, amount: Int) -> Result[Account, AccountError] {
>     if amount <= 0 {
>         return Err(AccountError.InvalidAmount)
>     }
>     Ok(Account { balance: acct.balance + amount, ..acct })
> }
>
> @ensures(result >= 0)
> @verify(fallback: "error")    // must be proven; V0003 if the solver says Unknown
> fn clamp_index(i: Int, n: Int) -> Int {
>     if i < 0 { 0 } else if i >= n { n - 1 } else { i }
> }
> ```
>
> **Why this fits AI generation:**
> - **The program is valid whatever the solver does.** The same source compiles with or without a solver and with any timeout. The solver can only remove checks; it cannot reject code. Generated code stops breaking when the solver changes.
> - **One fewer decision for each contract.** The common case needs no annotation. Each non-default value records an intent a reviewer cares about.
> - **Contracts still are not comments.** Section 3b.4 gives this as the reason for the error default, and AIML-1 keeps it: every contract is either proven or checked at runtime. The audit argument also holds, because `"trust"` stays explicit and greppable. Only the reflex to use it goes away.
> - **The spec agrees with itself.** Principle 4 ("proves what it can, runtime-checks the rest") and `@where` ("at boundaries when not") already work this way. Today, 3b.4 is the one exception the model must memorize.
>
> **Migration and diagnostics:**
> - A fn-level `"runtime"` becomes a W-level lint, "redundant @verify", with a fmt/fix autofix that removes it.
> - The `"runtime"` default on a trait method is redundant too, but keep it legal. It costs nothing, and the trait decision stays intact.
> - Add an info-level V0004 "runtime check inserted". It stays quiet by default and shows in the verification report and in `blink query`, which lists, for each contract, Proven / runtime / trust, inherited rows included. This keeps the Systems condition from the trait debate.
> - V0003 help no longer says "simplify the predicate" when no solver exists. This also closes ebt5jr.
>
> **Cross-language:**
> - Eiffel and Ada (`Assertion_Policy`) check contracts at runtime by default. SPARK proof is an opt-in mode that you apply to a scope, which is the same shape as `"error"`.
> - Dafny makes Unknown an error, but Dafny is a verifier first. Blink is a general-purpose language that must compile on day one with no solver.
> - C++26 contracts also choose a runtime evaluation semantic by default, not rejection.
>
> ---

- **Minimalism:** *Min-1 (preferred): Unknown means a runtime check, and `@verify` keeps one value*

> 1. An Unknown contract gets a runtime check, with no annotation. This is the rule `@where` already uses, so all contract predicates follow one rule.
> 2. `@verify(fallback: "trust")` stays. It is the only value that still does something: it is the visible, greppable gap marker that §3b.4's rationale asks for. That rationale survives in full. Only the "error" half goes.
> 3. `@verify(fallback: "runtime")` becomes redundant. It gets a warning, and `blink fix` deletes it. After one deprecation cycle it is removed. Trait methods: the trait-level runtime default is now the language default, so that annotation is a no-op as well. E0913 (trust on a trait method) stays. An impl's own trust still replaces the default.
> 4. There is no build-mode split. The checks run in every build, which is what the compiler does now. If someone wants to remove a check, they write trust on that one function, where the choice is local and can be audited. This also closes 5c7p4d: there are no debug-only contract checks, so "debug build" never needs a definition in the contracts section.
> 5. There is no `"static"` mode. The solver does not exist yet, and a strict mode for a solver that does not exist is YAGNI. When the solver ships, the strict guarantee can be a tool switch (`blink check --contracts proven`) or a `blink query` filter that lists Unknown contracts. That is tooling, not syntax.
> 6. The V0003 error goes away. V0001 and V0002 stay as they are. Edit the stale 07 annotation-table row to: "`@verify(fallback: "trust")` | fn, impl method | accept an unproven contract without a runtime check."
>
> ```blink
> @requires(amount > 0)
> @ensures(result.is_ok() => result.unwrap().balance == old(acct.balance) + amount)
> pub fn deposit(acct: Account, amount: Int) -> Result[Account, AccountError] {
>     if acct.frozen {
>         return Err(AccountError.Frozen)
>     }
>     Ok(Account { balance: acct.balance + amount, ..acct })
> }
>
> @ensures(result.entropy() >= 256)
> @verify(fallback: "trust")
> fn generate_key() -> PrivateKey ! Crypto {
>     // The solver cannot reason about entropy, and a runtime check cannot measure it
>     crypto.random_key()
> }
> ```
>
> The language loses one annotation value, one error code and one undefined concept ("debug builds"). It gains nothing.
>
> **Tradeoffs**
> - **"Writing a contract now costs CPU silently."** Not silently, because the contract is written right there in the signature. Systems raised the hot-loop concern in the trait debate. The answer is per-site trust, which is explicit, rather than a global switch.
> - **"Trust is still the easy path to speed."** Yes, but trust is now the only annotation left, so `rg 'fallback: "trust"'` finds exactly the places that are not checked. Today that same grep has to dig through 85 lines of runtime noise. The audit gets better.
> - **"We lose the push to make contracts provable."** That push does not exist with no solver, because every contract is Unknown. When a solver ships, V0001 (proven, zero cost) is the reward, and that is a better incentive than an error.
> - **Migration.** About 85 lines are deleted by a tool, and nothing breaks.
>
> **Cross-language:** Eiffel and Ada 2012 (`Pre`/`Post`) check contracts at run time by default and let a static prover remove checks as an upgrade (SPARK). Dafny is the only language here that uses "error unless proven", and it is a verifier, not a general-purpose language.

- **PLT** (side constraint): *PLT-3 (side constraint, any option): executable predicates*

> A runtime fallback requires the predicate to be executable: pure, total and finite. Blink has no quantifiers or ghost state today, so every predicate is executable. If Blink later adds `forall` over an infinite domain or ghost fields, an Unknown non-executable predicate cannot fall back to `"runtime"`. It must be V0003 unless it is `trust`. The spec should state this now as the rule "the default is `runtime` *when the predicate is executable*", so that a later feature cannot silently weaken the default.

#### Phase B — Debate highlights

Each seat's own account of how its position changed from Phase A, verbatim.

- **Systems:**

> 1. **`"static"` becomes `"error"`.** It reads as an outcome, and three seats already chose it.
> 2. **I withdraw Sys-2 (`"debug"`).** PLT showed that removing a check also breaks proofs in other functions, not only the local check.
> 3. **The redundant-`"runtime"` lint rises from a hint to a warning,** because this repo is training data.
>
> STATUS: stable, ready to vote

- **Web/Scripting:**

> - Withdrawn: Web-3 (the module-level default). Its only reason to exist was a kept error default, and nobody wants that now.
> - New: a warning, not a hint, for redundant `"runtime"`; the cost-class column (Sys); `"none"` opposed because people will read it as "trust"; PLT-3 accepted.
> - Unchanged: Web-1 core, the `"error"` spelling, and no build-mode split.
>
> STATUS: stable, ready to vote

- **PLT:**

> - S1 naming: I now accept "static" as equal to "error". I reject "none" because it can be confused with trust.
> - S4: I withdraw my S4-c fallback (`--assume-contracts`) and reject every build-dependent opt-out.
> - New: the report addition about trust-conditional proofs under S5-a, and the argument against "debug" from the verifier's assumptions.
>
> STATUS: stable, ready to vote

- **DevOps:**

> 1. "none" becomes "error" (majority wording, and it matches V0003).
> 2. I withdraw the manifest default. CI strictness becomes a `--verify-report --deny` gate, with no change to semantics.
> 3. I adopt Sys's cost class and PLT's executable constraint.
>
> STATUS: stable, ready to vote

- **AI/ML:**

> In AIML-2 I said a global switch, if the panel wants one, belongs in the manifest. I withdraw that. PLT's locality argument and DevOps' own S3-a show that any manifest policy also changes what a function means, out of sight of the model that writes it. I now hold "no global switch" with no manifest fallback. AIML-3 stays rejected. Every other Phase A position stands.
>
> STATUS: stable, ready to vote

- **Minimalism:**

> 1. S1: from "no strict value" to `"error"` per fn and per trait method (Systems' zero-cost-or-reject argument).
> 2. S2: from "deprecate `runtime`" to "legal, lint where redundant" (follows from 1).
> 3. S4: Min-2 withdrawn.
>
> STATUS: stable, ready to vote

- **PLT** on build-dependent opt-outs (the argument that moved Systems off "debug"): *S4: build-dependent opt-out. I reject all of them, including Sys-2 "debug".*

> New point against Sys-2: "the optimizer must never assume a removed check holds" is not enough. The **verifier** assumes it. Under §3b.3, each caller's V0001 is proven under the hypothesis that the callee's `@ensures` holds. In release that hypothesis is unchecked, so in release `"debug"` is `trust` for every downstream proof. To make `"debug"` sound, a debug-only contract could not serve as a hypothesis in callers' proofs. That would be a fourth status with weaker composition, and it costs too much for one O(n) postcondition. A `test` block covers that case (Sys's own advice). S4-b and S4-d have the same problem at whole-program scale. S4-c was my own fallback, and I withdraw it: no seat wants a global switch, so it is not needed.

#### Phase C — Final vote

- **Q1: Default when a contract's outcome is Unknown and no `@verify` applies** (6-0, A: runtime check)

  - **Systems:** *Q1: A*

    > **Reasoning:** For the common case, a runtime check compiles to one compare and one predicted branch. The error default does not give zero cost. It pushes authors to `"trust"`, which removes the check and leaves a hidden gap. A check costs a known, small amount.
    >
    > **Concern:** A costly `@ensures` that walks a list now runs on every call, and an author will not see this unless the report shows it (see 6b).

  - **Web/Scripting:** *Q1*

    > **Vote:** A
    >
    > **Reasoning:** A developer who writes `@requires(amount > 0)` expects it to do something. They do not expect to have to fill in a required annotation before the build passes. A runtime check by default makes the safe path the one you get by writing nothing, so `"trust"` stops being the reflex fix. This also matches Principle 4 and `@where`, so a newcomer learns one rule.
    >
    > **Concern:** Users will not realize their checks cost time in hot code until a profiler shows it, so the report and `blink query` must make those checks easy to find.

  - **PLT:** *Q1: A*

    > **Vote:** A
    >
    > **Reasoning:** A runtime check soundly discharges an Unknown obligation. When the check fails, execution stops, so the callee's `@ensures` holds every time a call returns. That justifies every caller proof under §3b.3 that assumes it. An error default makes nothing more sound. It only moves users toward `trust`, the one option that is not sound.
    >
    > **Concern:** Authors may write costly `old()` snapshots of large values without knowing their cost. The report (6b) must make that cost visible, or users will reach for `trust` again for speed.

  - **DevOps:** *Q1*

    > **Vote:** A
    >
    > **Reasoning:** V0003 as the default is a diagnostic that every user silences the same way, which the 85 pasted `"runtime"` lines prove. A runtime check gives a precise failure message at the moment the contract breaks, and that is more useful than a compile error with no fix. Also, a later solver upgrade can only remove checks. It can never turn CI red.
    >
    > **Concern:** users may not notice that checks were added, unless V0004 and the report are easy to find from `blink check` output.

  - **AI/ML:** *Q1. Default when Unknown and no @verify applies*

    > **Vote:** A
    >
    > **Reasoning:** With A, whether code compiles no longer depends on the solver's strength or its timeouts, which no model can learn from the spec. The common case then needs no annotation, so the model does not learn a reflex of pasting `"runtime"` or `"trust"`.
    >
    > **Concern:** Generated code may stack costly `@ensures` predicates on hot paths, and only the report shows the cost.

  - **Minimalism:** *Q1. Default for Unknown*

    > **Vote:** A
    >
    > **Reasoning:** This is a subtraction: it removes a default error that every user silences the same way, as the 85 repo copies show. It makes contracts follow the same rule as `@where` and Principle 4, so the spec has one rule where it now has two. Nothing new is added to the language.
    >
    > **Concern:** Users may write costly predicates (walks over large lists) without noticing the cost, because the default is now silent.

- **Q2: Build-mode policy for runtime contract checks** (6-0, A: every build mode; "trust" is the only per-body opt-out)

  - **Systems:** *Q2: A*

    > **Reasoning:** The binary we test must be the binary we ship. Removing a check in one build also breaks every caller whose check the compiler dropped because it relied on that contract, so a build mode would change what the program means. `unreachable()` and `@where` already follow this rule, so contracts must too.
    >
    > **Concern:** Users will ask for a global switch to remove checks after their first profile. The spec must say clearly that the opt-out is local: prove the contract, or write `"trust"` on that function.

  - **Web/Scripting:** *Q2*

    > **Vote:** A
    >
    > **Reasoning:** Python's `-O` and Java's `-ea` show what happens when checks depend on the build mode: tests pass and production runs without the checks. Net.Listen auto-400 also needs `@requires` to run in production. With one rule for every build mode, nobody needs to post "why did my contract not fire in prod".
    >
    > **Concern:** Someone will ask for a global off switch for benchmarks, and the spec must explain why per-fn `"trust"` is the answer.

  - **PLT:** *Q2: A*

    > **Vote:** A
    >
    > **Reasoning:** Each caller's proof is conditional on the hypotheses the verifier took from its callees. A check that a build mode strips works as a hidden `trust` for every downstream proof, and no search of the source can find it. Contract semantics must not depend on build configuration.
    >
    > **Concern:** Pressure about hot-loop cost may bring a strip flag back later. Any such proposal must be judged as a global `trust`, because that is what it is.

  - **DevOps:** *Q2*

    > **Vote:** A
    >
    > **Reasoning:** One policy means the binary that tests ran is the binary that ships, and the report never needs to say which profile was active. Every opt-out stays visible at its site as `"trust"`, so `blink audit`-style greps and `blink query` give the full answer.
    >
    > **Concern:** a costly `@ensures` on a hot path may show up as a perf regression before anyone opens the report, so the cost class (6b) must ship with this change.

  - **AI/ML:** *Q2. Build-mode policy*

    > **Vote:** A
    >
    > **Reasoning:** The source is the whole truth: the program that the tests run is the program that ships. A model cannot see a build mode, so behavior that depends on it would be a silent class of bugs.
    >
    > **Concern:** Systems users may answer real perf pressure with many `"trust"` annotations, and the gap list then grows.

  - **Minimalism:** *Q2. Build-mode policy*

    > **Vote:** A
    >
    > **Reasoning:** One behavior in every build means no "debug build" concept to define (closes 5c7p4d) and no extra flag or profile key. The per-body "trust" opt-out already exists, so nothing new is needed. A global strip is C's NDEBUG again.
    >
    > **Concern:** Pressure for a global switch will come back once a large program profiles slow, and the spec must hold the line.

- **Q3: Explicit "must be proven" value** (6-0, A: `@verify(fallback: "error")`)

  - **Systems:** *Q3: A*

    > **Reasoning:** `"error"` is the only way to get a compile-time promise of zero cost for one hot function while the rest of the program stays checked. The value says what happens on Unknown, so the key and its values keep one meaning.
    >
    > **Concern:** With no solver, every `"error"` fails today. Authors who expect it to work will see this as broken, so the V0003 text must say that no solver ran.

  - **Web/Scripting:** *Q3*

    > **Vote:** A
    >
    > **Reasoning:** `fallback: "error"` reads as plain English: when the solver cannot decide, the build fails. Without a strict value, `"trust"` is the only zero-cost path, which brings back the trust-easy-path problem. `"none"` would be misread as `"trust"`.
    >
    > **Concern:** With no solver, `"error"` always fails today. If V0003 does not say that plainly, users will lose time trying to fix it.

  - **PLT:** *Q3: A*

    > **Vote:** A
    >
    > **Reasoning:** The obligation to prove a contract is part of the fn or trait interface, so it must be written in the source and not depend on how a tool is invoked. "error" states what an Unknown outcome does. Unlike "none", it cannot be read as "no check", which is what `trust` means.
    >
    > **Concern:** Until a solver ships, every contract that uses `"error"` fails to compile. The spec must say so, so that users do not read V0003 as a bug in their code.

  - **DevOps:** *Q3*

    > **Vote:** A
    >
    > **Reasoning:** `"error"` matches what the user sees (V0003 is an error), and it keeps one `fallback:` key whose values the LSP can offer as completions. It is the majority wording, and I withdrew "none".
    >
    > **Concern:** with no solver, every `"error"` contract fails. V0003 must say plainly that no solver ran, so nobody wastes time rewriting the predicate.

  - **AI/ML:** *Q3. Explicit "must be proven" value*

    > **Vote:** A
    >
    > **Reasoning:** `"error"` answers the key's own question ("what happens on Unknown?") with the same word as the diagnostic that results. So there is one key, a table of four values, and nothing to infer.
    >
    > **Concern:** While no solver exists, a model that copies `"error"` from an example writes a function that never compiles. The spec example must say that it needs a solver.

  - **Minimalism:** *Q3. Explicit "must be proven" value*

    > **Vote:** A
    >
    > **Reasoning:** Systems showed a real per-function intent ("zero cost or fail the build") that trust cannot express and a tool switch cannot put in source. It adds a value under the existing key, not a new key or axis. `"error"` reads correctly after `fallback:` and matches V0003.
    >
    > **Concern:** With no solver, `"error"` always fails, and someone will later ask for a "warn when no solver ran" escape that would turn it into a no-op.

- **Q3b: Strict value on a trait method declaration** (6-0, A: allowed as the impl default)

  - **Systems:** *Q3b: A*

    > **Reasoning:** A trait-level `"error"` can only reject impl bodies. It cannot add a gap, so it is safe. It lets the author of a hot-path trait require zero-cost impls.
    >
    > **Concern:** If a trait author adds `"error"` to a published trait later, impls downstream start to give V0003. Treat this addition as a breaking change.

  - **Web/Scripting:** *Q3b*

    > **Vote:** A
    >
    > **Reasoning:** A strict default is stricter than the language default, so E0913's reason (a trait author cannot vouch for unseen bodies) does not apply. It follows the same replace-whole rule as `"runtime"` does today, so there is nothing new to learn.
    >
    > **Concern:** If a trait author adds `"error"` to a published trait after release, downstream impls break, so docs should warn that this is a breaking change.

  - **PLT:** *Q3b: A*

    > **Vote:** A
    >
    > **Reasoning:** A strict default can only reject impl bodies. It can never accept one without verification. So E0913's reason (a trait author cannot vouch for bodies they cannot see) does not apply. An impl can still step down with its own `"runtime"` or `"trust"` under the replace-whole rule.
    >
    > **Concern:** A strict default on a widely used trait can break downstream impls when a solver upgrade turns Proven into Unknown, so changes to the solver must be treated as compatibility-relevant.

  - **DevOps:** *Q3b*

    > **Vote:** A
    >
    > **Reasoning:** A strict trait default can only reject impl bodies, never trust them, so E0913's reasoning does not apply. `blink query` must show it as an inherited row, the same as the runtime default.
    >
    > **Concern:** the error at the impl must name the trait method that set `"error"`, or the user cannot see where the rule comes from.

  - **AI/ML:** *Q3b. Strict value on a trait method*

    > **Vote:** A
    >
    > **Reasoning:** On a trait method it can only reject bodies, never trust them, so the reason for E0913 does not apply. The trait default rule stays one rule for every value except trust.
    >
    > **Concern:** A trait author's `"error"` can break every downstream impl when the solver changes. The V0003 message must name the trait as the source.

  - **Minimalism:** *Q3b. Strict value on a trait method*

    > **Vote:** A
    >
    > **Reasoning:** It can only reject impl bodies, never weaken them, so it is sound. It reuses the existing replace-whole rule and adds no mechanism.
    >
    > **Concern:** A strict trait default with no solver blocks every impl until each one writes `"runtime"`, which is boilerplate of a new kind.

- **Q4: Explicit `@verify(fallback: "runtime")`** (6-0, A: legal; warning lint with autofix where redundant)

  - **Systems:** *Q4: A*

    > **Reasoning:** This repo is training data. A hint leaves 85 lines that do nothing for models to copy, and a warning with an autofix removes them. On an impl, the value still has a job: it steps down from a trait's `"error"` to a check, so it must stay legal.
    >
    > **Concern:** If the lint misses the trait-override case, its autofix deletes a meaningful `"runtime"` and turns a working impl into a V0003 error.

  - **Web/Scripting:** *Q4*

    > **Vote:** A
    >
    > **Reasoning:** `"runtime"` still has a job: overriding a strict trait default. So it cannot be removed. A warning with an autofix costs one command. A hint would leave 85 copies in place for agents to keep copying.
    >
    > **Concern:** If the lint fires where `"runtime"` overrides a strict default, people will distrust it, so the quiet case must be correct from the first release.

  - **PLT:** *Q4: A*

    > **Vote:** A
    >
    > **Reasoning:** `"runtime"` must stay legal, because an impl needs it to step down from a strict trait default without falling back to `trust`. A warning with an autofix cleans up the 85 existing uses. Hint severity is too quiet to make the repo's own training corpus converge.
    >
    > **Concern:** If the lint's check for redundancy ignores the trait default, it will remove an override that has a meaning. The lint must resolve the trait-method policy before it fires.

  - **DevOps:** *Q4*

    > **Vote:** A
    >
    > **Reasoning:** A warning shows in CI logs, so the 85 redundant sites leave the repo, and with them the training data, through one `blink fix` run. The value must stay legal so an impl can override a trait `"error"` without reaching for `"trust"`.
    >
    > **Concern:** the lint must decide "redundant" using the trait default. A false positive on an override would teach users to delete the one meaningful use.

  - **AI/ML:** *Q4. Explicit "runtime"*

    > **Vote:** A
    >
    > **Reasoning:** A warning shows the 85 redundant copies, and the autofix removes them, so they leave the corpus that trains future models. The value stays needed to override a trait's `"error"`.
    >
    > **Concern:** If the lint does not stay quiet on a correct override of a trait `"error"`, models learn to delete a line that has meaning.

  - **Minimalism:** *Q4. Explicit "runtime"*

    > **Vote:** A
    >
    > **Reasoning:** Once a trait can demand `"error"`, an impl needs `"runtime"` to opt back into a run-time check, so the value has a real job and must stay. Warning severity makes CI show it, so the boilerplate leaves the repo, which is training data. The autofix makes the migration one commit.
    >
    > **Concern:** The lint must check the trait default correctly, or it will tell users to delete an override that matters.

- **Q5: Policy scope beyond the fn and its trait method** (6-0, A: no project or module default; CI gate on the report)

  - **Systems:** *Q5: A*

    > **Reasoning:** The cost and the meaning of a contract must come from the function signature, its trait, and the spec. A config file in another project must not change them. A CI gate on the report gives a project its strictness, and no contract changes meaning.
    >
    > **Concern:** Some teams will want a project-wide "error" setting. Without one, they may write their own lint scripts that do not agree with each other.

  - **Web/Scripting:** *Q5*

    > **Vote:** A
    >
    > **Reasoning:** With a project-level default, the same code compiles in one repo and fails in another, and a snippet copied from Stack Overflow or an agent would behave differently depending on a file the reader cannot see. A CI gate on the report gives teams strictness without changing what the code means.
    >
    > **Concern:** Teams may not find the report gate, so the docs must show it as the documented way to go strict.

  - **PLT:** *Q5: A*

    > **Vote:** A
    >
    > **Reasoning:** Locality: an agent or a reader must be able to derive a contract's policy from the signature, its trait and the spec, as §3b.3 claims. A CI gate on the report constrains the build without changing what a contract means.
    >
    > **Concern:** Teams may build their own gates on the report output without a common format, so the report's JSON schema must be stable.

  - **DevOps:** *Q5*

    > **Vote:** A
    >
    > **Reasoning:** Locality makes `blink query --fn` complete without reading the manifest. A `--verify-report --deny runtime,trust` gate gives a team lead the CI strictness they want without changing what a contract means.
    >
    > **Concern:** the deny gate needs a stable flag and JSON schema in §6, or every team writes its own grep.

  - **AI/ML:** *Q5. Policy scope*

    > **Vote:** A
    >
    > **Reasoning:** A model writes a function from what it can see. A blink.toml default would change what the same text means without the model knowing. CI strictness as a report gate keeps what a contract means fixed.
    >
    > **Concern:** Teams may ask for a project default again later. The decision record must state the locality reason.

  - **Minimalism:** *Q5. Policy scope*

    > **Vote:** A
    >
    > **Reasoning:** The signature, the trait and the spec default are the whole policy, so a reader (human or AI) sees it locally. A manifest key would let the same source compile in one package and fail in another. CI strictness belongs in a report filter, which does not change what a contract means.
    >
    > **Concern:** Teams may build ad-hoc CI scripts around the report, and the report format then becomes an unofficial API that is hard to change.

- **Q6: Diagnostics package** (6a, 6b, 6c, 6d, 6f YES 6-0; 6e W 5-1, Minimalism dissent for E)

  - **Systems:**

    > - **6a: YES.** Each runtime check must appear somewhere a perf engineer can query, and not as warning noise.
    > - **6b: YES.** This is my condition for Q1A. Without a cost class, finding the expensive checks means reading every predicate.
    > - **6c: YES.** A useful failure message is good only if a passing check stays at one branch. The spec must include the cold-path rule, or "helpful" formatting will cost something on every call.
    > - **6d: YES.** Help text that offers a fix that cannot work wastes time in every fix loop.
    > - **6e: W.** An edit that removes a function's last contract must not break the build.
    > - **6f: YES.** A "proven" result that relies on someone's trust is not zero risk, so the report must show it. Report only, with no syntax and no runtime cost.

  - **Web/Scripting:**

    > - **6a:** YES. Users can see the checks when they look for them, with no noise on the default path.
    > - **6b:** YES. It is cheap, and it is what lets someone find the slow check without a profiler.
    > - **6c:** YES. Of everything here, this does the most for developer experience. The failure message should read like V0002's counterexample, so a user or agent can fix the bug without a debugger.
    > - **6d:** YES. A help message that suggests a fix that cannot work generates support questions.
    > - **6e:** W. A leftover annotation that does no harm should not fail a build.
    > - **6f:** YES. If a "proven" result secretly rests on a `"trust"` somewhere else, the developer is misled, and showing the assumption in the report costs nothing in syntax.

  - **PLT:**

    > - **6a: YES.** The level must be info. A warning on the default path would bring back the pressure to silence it with `trust`.
    > - **6b: YES.** A cost that is hidden produces a demand for a global opt-out. When the cost is visible, the author can decide for each function.
    > - **6c: YES.** The failure message is the runtime counterpart of V0002's counterexample. Formatting values only on the cold failure path keeps a passing check cheap.
    > - **6d: YES.** A help text that names a fix no one can apply is a wrong diagnostic.
    > - **6e: W.** A `@verify` on a fn with no contract is dead code, not unsound code. A warning with an autofix is proportionate.
    > - **6f: YES.** Without it, a Proven status whose hypothesis no one verified looks as strong as an unconditional proof.
    >
    > **Concern:** 6f needs the verifier to record which callee contracts each proof used. If the solver backend cannot report those assumptions, the report must say "dependencies unknown". It must not omit them.

  - **DevOps:**

    > - **6a:** YES. It gives the report and the LSP (hover, inlay hint) one status per contract, with no warning noise on the default path.
    > - **6b:** YES. It makes the hot-loop concern sortable data, and it is the condition Systems set for accepting the default.
    > - **6c:** YES. A fixed failure format gives agents and log tools one stable shape, the same text the Net.Listen 400 uses. The cold-path rule keeps a passing check cheap.
    > - **6d:** YES. The help must name only fixes that work today.
    > - **6e:** W. The annotation does nothing, but it is not wrong. A warning with an autofix removes it without breaking a build over a no-op.
    > - **6f:** YES. It is report-only, and it shows how far a `"trust"` gap spreads, which is the audit use case the old rationale cited.
    >
    > **Concern:** 6b's cost class must be computed the same way everywhere (from the lowered IR), or the report will disagree between compiler versions and break diff-based CI gates.

  - **AI/ML:**

    > - **6a:** YES. Visibility at no cost, and no warning that would push code toward trust.
    > - **6b:** YES. It is report-only, and it gives perf agents a list to work from.
    > - **6c:** YES. This is the most valuable item for agents: a fixed counterexample-style message that a model can repair code from without a debugger.
    > - **6d:** YES. Help text that names a fix that does not exist makes models loop.
    > - **6e:** W. An annotation with no effect is noise, not unsound, and the autofix handles it.
    > - **6f:** YES. It makes trust's effect on downstream proofs visible, at no syntax cost.
    >
    > **Concern:** For 6c, if the free-variable values are not bounded in size, a large collection can flood the agent's context window. The spec should cap the length of each value.

  - **Minimalism:** *(dissent on 6e)*

    > - **6a:** YES. It matches V0001, is silent by default and costs nothing on the default path.
    > - **6b:** YES. It is report content, not language surface, and it meets the Systems condition for accepting a silent default.
    > - **6c:** YES. A fixed failure message makes a run-time violation as useful as a V0002 counterexample, and the cold-path rule keeps a passing check cheap.
    > - **6d:** YES. Help text must not name a fix that cannot work.
    > - **6e:** E. An `@verify` on a fn with no contract can do nothing, and a meaningless annotation should not compile. An error is simpler than a warning plus an autofix.
    > - **6f:** YES. It is report only, adds no syntax, and shows where a proof depends on a trust gap.
    >
    > **Concern:** The report (6a, 6b, 6f) may grow into a large tool surface that the spec then has to describe and keep stable.

- **Q7: Executable-predicate constraint (PLT-3)** (5-1, A: in the spec text; Minimalism dissent for B)

  - **Systems:** *Q7: A*

    > **Reasoning:** The compiler must never emit a runtime check that cannot finish. This rule must be in the spec, where whoever designs a future `forall` or ghost-state feature will read it. A decision file is too easy to miss.
    >
    > **Concern:** "Finite" can still allow a predicate that is very slow, such as a `forall` over all of `Int32`. The executable test must also send predicates like that to V0003 or `"trust"`.

  - **Web/Scripting:** *Q7*

    > **Vote:** A
    >
    > **Reasoning:** The spec is the blueprint, and the people who will add `forall` or ghost state later will read the spec. A note kept only in decisions/ will be missed. One sentence now stops the safe default from quietly becoming no check at all.
    >
    > **Concern:** Readers today may wonder what "executable" excludes, since every current predicate is executable, so the sentence should give one example.

  - **PLT:** *Q7: A*

    > **Vote:** A
    >
    > **Reasoning:** This sentence is a rule of the language: it says when the default applies. It is not design rationale. If it lives only in decisions/, a later feature that adds quantifiers or ghost state could be specified against sections/ with no sign of the rule, and the default could silently become `trust`. Today the sentence costs nothing, because every predicate can be evaluated.
    >
    > **Concern:** "Executable" must be defined precisely (pure, terminating, no ghost state) when the first non-executable construct arrives, or the boundary will be decided case by case.

  - **DevOps:** *Q7*

    > **Vote:** A
    >
    > **Reasoning:** A rule that decides whether code compiles belongs in sections/, where `blink llms` and the LSP docs read from it. A rationale file that the tools never surface does not help. Stating it now also fixes the V0003 note ("predicate is not executable") before quantifiers arrive.
    >
    > **Concern:** "executable" needs a definition the checker can test (pure, total, finite), or the diagnostic will depend on how each implementation reads the word.

  - **AI/ML:** *Q7. Executable-predicate constraint*

    > **Vote:** A
    >
    > **Reasoning:** A rule in sections/ is something a model learns from the spec. A rule kept only in decisions/ is not part of what it reads. Stating it now stops a later `forall` from weakening the default without notice.
    >
    > **Concern:** "Executable" needs a precise definition (pure, total, finite), or the rule is an ambiguity that models resolve in different ways.

  - **Minimalism:** *(dissent)* *Q7. Executable-predicate constraint*

    > **Vote:** B
    >
    > **Reasoning:** Blink has no quantifiers or ghost state, so the rule describes a case that cannot occur today. Any panel that adds `forall` must decide its run-time story anyway, and the decision rationale is enough to remind it. Spec text about features that do not exist is surface that readers must learn for no gain.
    >
    > **Concern:** If A wins, readers (and AI) will look for "non-executable predicates" in the language and find none, which costs them time.

### Final Spec

```blink
// Default: no annotation. Unknown -> runtime check (V0004, silent).
@requires(amount > 0)
@ensures(result.balance == old(self.balance) - amount)
fn withdraw(self: Account, amount: Int) -> Account {
    Account { balance: self.balance - amount, ..self }
}

// Must be proven: Unknown -> V0003.
@requires(i >= 0 && i < xs.len())
@verify(fallback: "error")
fn read_at(xs: List[Int], i: Int) -> Int {
    xs.get(i).unwrap()
}

// No check: accepted without proof.
@ensures(result.entropy() >= 256)
@verify(fallback: "trust")
fn generate_key() -> PrivateKey ! Crypto {
    // ...
}

// A trait method may set "error" (or "runtime") as the impl default; "trust" is E0913.
trait Score {
    @ensures(result >= 0 && result <= 100)
    @verify(fallback: "error")
    fn score(self) -> Int
}
```

- An Unknown `@requires`/`@ensures` gets a runtime check by default: `@requires` at entry, `@ensures` at each exit with `old()` snapshots taken at entry. A failure panics, or raises `validation.contract_violation` at a system boundary.
- The check runs in every build mode. No flag, profile or `blink.toml` setting removes it. `"trust"` on one function is the only opt-out.
- `@verify(fallback: "error")` makes an Unknown outcome V0003. A trait method may carry it as the impl default; an impl's own `@verify` replaces it as a whole. Adding it to a published trait is a breaking change.
- `"runtime"` stays legal. W0901 `RedundantVerifyFallback` (autofix) flags it where it is redundant; it is quiet where it replaces a trait method's `"error"`.
- No project-level or module-level policy. CI strictness comes from `blink verify --deny runtime,trust`, which does not change what a contract means.
- Info V0004 `ContractRuntimeChecked` is silent by default and shows its source (`default`, `explicit`, `inherited(Trait.method)`) in the report and `blink query`.
- The report shows each runtime check's cost class and `old()` snapshots, and marks a Proven contract whose proof assumes a callee's `"trust"` (or says `dependencies unknown`).
- The spec fixes the runtime failure message: contract text, clause kind, function, span, each free-variable value cut to a fixed length, and caller. The message is built only on the cold failure path.
- V0003 says when no solver ran, and offers "simplify the predicate" only when a solver ran.
- `@verify` on a function with no contract is W0902 `VerifyWithoutContract` (autofix).
- The runtime default applies to an executable predicate. A non-executable predicate whose outcome is Unknown is V0003 unless it has `"trust"`.
