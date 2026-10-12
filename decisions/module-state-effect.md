[< All Decisions](../DECISIONS.md)

# Module-Level State Effect — Design Rationale

The gap: a function that reads or writes a module-level `let mut` binding did not show it in its signature. The compiler inferred a write set, and only LSP hover showed it. §1.2 Principle 3 says "When it declares no effects, you know it is pure", while §4.1 said a function with no `!` "may still read or write module-level `let mut` bindings". The audit asked the panel to require an effect in the signature for module state, or to ban module-level `let mut`.

This re-audits [Non-Local Mutable State](non-local-mutable-state.md). Its Round 2 (PLT, Systems and AI/ML only, 3-0) chose write-set inference over a `! State` effect.

Facts the moderator gave the panel (facts, not votes):

1. The self-hosted compiler uses module-level `let mut` a lot: `src/typecheck.bl` alone has 157 top-level `let mut` bindings, and `lib/std` has 14.
2. A Phase A panelist ran `blink check` (gen1) on a program in which `async.spawn(fn() { add(1) })` and the parent both call an `add` that pushes onto a module `let mut` List. It passed. The §2.8 freeze rule and E0650 cover captures only.
3. gen1 accepts `fn main() ! Parse` (an effect with no operations) with no `with`, though §4.6 says E0539 fires.
4. §4.16.3 said "The language has no syntax to mark a function as pure", while `@pure` (E1307) exists.
5. `lib/std/json.bl` keeps scratch slots in module `let mut` bindings.

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in independent-proposal → debate → vote rounds, with a second round on Q2.

#### Phase A — Independent proposals

- **Systems:**

> I favour **S1**, which also fixes a data race the spec misses. S3 is a fallback if the panel rejects S1, and I oppose S2.
>
> **The race the spec misses**
>
> I ran this through gen1 with `blink check`, and it passes:
>
> ```blink
> let mut items: List[Int] = List.new()
>
> fn add(n: Int) {
>     items.push(n)
> }
>
> fn main() ! Async {
>     async.scope {
>         let h = async.spawn(fn() { add(1) })
>         add(2)
>         h.await
>     }
> }
> ```
>
> Two tasks push to one global list at the same time, and nothing stops it. E0650 (no `let mut` captures) and the §2.8 freeze rule only cover what a closure captures. A module `let mut` is never captured, so a task can reach it with no capture at all. On real threads this is heap corruption, not merely the wrong answer.
>
> Write-set inference cannot fix this, because it treats calls into other modules as opaque. If `add` lives in another module, a spawn site cannot see that it writes. Only a fact in the signature carries across the module edge. To me, that settles the ticket.
>
> **S1 (favoured): each module `let mut` names the effect that writes it**
>
> ```blink
> effect Lexer {
>     effect Advance
> }
>
> let mut pos = 0 ! Lexer.Advance
> let mut pending: List[Comment] = List.new() ! Lexer.Advance
>
> fn at() -> Int {
>     src.byte_at(pos)
> }
>
> fn advance() ! Lexer.Advance {
>     pos = pos + 1
> }
>
> pub fn next_token() -> Token ! Lexer.Advance {
>     advance()
>     // ...
> }
> ```
>
> **Normative rules:**
> 1. A module-level `let mut` must name exactly one writer effect with `! E`. `E` must be an effect declared in the same module, with no operations (a leaf or an op-less sub-effect).
> 2. Assigning to the binding, or calling a mutating method on it, performs `E`. The ordinary effect rules apply: a function that writes it, directly or through a callee, declares `E` (or a parent of `E`) in its row. Reads perform nothing.
> 3. Writer effects need no handler. `main` and test blocks hold every writer effect, as they hold built-ins. A `with` may not name a writer effect.
> 4. A closure passed to `async.spawn` whose row includes a writer effect is a compile error.
> 5. Writer effects are exempt from capability budgets (§4.16.6 stays true). Effect impls of trait methods still may not widen the row (E0904). So `Display.fmt` cannot write module state, which settles the open note from display-fmt-empty-effect-row.
> 6. Write-set inference stays, but only as an analysis. It still gives the exact set of bindings to W0550/W0551 and to hover. The effect gives a yes-or-no at the boundary, and the inferred set gives the detail.
>
> **Diagnostics:**
> - **E1017 `LetMutNeedsWriterEffect`:** "module-level `let mut pos` must name the effect that writes it". The help suggests `! <Module>.State`.
> - **E1018 `WriterEffectNotLocal`:** "writer effect `X` must be declared in this module and have no operations".
> - **Missing row:** the existing missing-effect error. Its note says "`advance` writes `pos`, which performs `Lexer.Advance`".
> - **E0651 `SpawnWritesModuleState`:** "a spawned task may not write module state: the closure performs `Lexer.Advance`". The help says "send values back through a Channel, or return them from the task".
>
> **What the hardware sees:** nothing. The effect is erased and has no handler, so a write is still a plain C store to a global. With rule 3, there is no evidence passing and no dispatch. Once an empty row really means "writes no globals", the compiler can reorder, hoist and memoize calls to row-less functions. Today that is unsound, because a function that looks pure may still write a global. Principle 3 ("no `!` means pure") becomes true for writes. Reads remain the documented gap, and they cannot corrupt state.
>
> **Cost:** you add the annotation to each function that writes, transitively. That is about 80 functions in the parser and more in typecheck.bl, where 157 globals can share a few effects. I said in R2 that this was pointless ceremony. I was wrong: the race above shows that the inferred fact does not reach where it is needed. Rust makes every parser method take `&mut self`, and nobody calls that noise. It is the honest signature. The migration needs the three-step bootstrap.
>
> **Other languages:**
> - Go leaves globals untracked and catches races at run time with `-race`.
> - Zig and C track nothing.
> - Rust makes a `static mut` access `unsafe` and forces `Sync`.
>
> S1 gives Rust's static guarantee with no locks and no `unsafe`.
>
> **S2 (opposed): ban module-level `let mut`**
>
> This is honest, and the codegen is fine: pass a context pointer, which costs one register. But it means rewriting about 230 globals in src and 14 in lib/std, and it pushes users toward hiding state in handlers, which costs more at run time. Banning the feature is a larger change than the problem needs.
>
> **S3 (fallback if S1 fails): check only at the boundary**
>
> Keep inference for private functions. Require the writer effect only on `pub fn`, trait impls, function values that escape the module, and spawn closures. Rules 1, 3, 4 and 5 stay, and the check runs only at those boundaries.
>
> This costs fewer annotations. The downside is that a private function's signature still hides its writes, which breaks Principle 3 inside the module. I accept it only as a compromise.
>
> **Votes on the locked points**
>
> - Writes only, reads free: keep.
> - Write sets transitive within a module: keep, for diagnostics.
> - Cross-module calls opaque: keep for the analysis. The signature now carries the fact.
> - "Not an effect": **reverse**.
> - Built-in `effect State`: stays removed. Each module defines its own effect.
>
> **Note to moderator**
>
> A spec-check: gen1 accepted `fn main() ! Parse` with no `with` for a user op-less effect, although §4.6 says E0539 should fire. That is a separate enforcement gap, not part of this ticket.

- **Web/Scripting:**

> **Web/Scripting — Phase A**
>
> **The real problem is one module boundary, not every function.** `pub let mut` is already banned (E1013). So code in another module can only reach module state through a `pub fn`. Inside one file the body is right there; a JS/Python dev reads it and sees the global. The leak is `counter.new_id()` called from another file with no `!`, which returns a new value on every call. That breaks Principle 3 ("declares no effects → pure").
>
> Also, today's Tier 2 is not just optional, it is a trap. A user effect such as `! Parse.Advance` must be discharged by a `with` before `main` (E0539, §4.6). So the §4.16.5 example forces every binary that imports the parser to write a handler for an effect that has no operations. Nobody will do that, so Tier 2 is dead in practice.
>
> **Proposal A (favoured): explicit at `pub`, inferred inside**
>
> Keep write-set inference for private functions, with no change. A function that code outside the module can call must show module-state writes in its row, through one built-in leaf effect, `State`.
>
> ```blink
> let mut next = 0
>
> fn bump() {                    // private: inferred, writes {next}, no annotation
>     next = next + 1
> }
>
> pub fn new_id() -> Int ! State {
>     bump()
>     next
> }
>
> pub fn peek() -> Int {         // reads are free
>     next
> }
> ```
>
> A caller in another module that calls `new_id()` needs `! State` in its own row, through the normal UndeclaredEffect check. Statefulness spreads through callers like `IO` does. That is the honest result.
>
> **Normative rules:**
> 1. `State` is a built-in leaf effect with no operations. No handler can be written for it, and no handler is needed. `with` on `State` is an error. It discharges like the built-in effects, so E0539 never fires for it. There is precedent: "gated, not virtualized" second-tier functions (§4.4.6).
> 2. These "boundary functions" must have `State` in their row when their transitive write set is non-empty: a `pub fn`, a pub method, a trait impl method, and a closure that escapes the module (returned or stored). If one does not, the compiler reports **UndeclaredStateWrite**: "`new_id` writes module state {next} but its signature does not declare `! State`", with the help text "add `! State` to the signature".
> 3. A boundary function that declares `State` but has an empty write set gets the existing unused-effect warning, or a new **UnusedStateEffect** warning.
> 4. `State` does not count against capability budgets (this keeps §4.16.6). A `capabilities = []` package may still declare it.
> 5. Wording fixes, needed whatever the panel picks:
>    - Principle 3: "When a function declares no effects, it changes nothing outside itself. Its result may still depend on module-level state that it reads."
>    - §4.1 line 11: "...a function with no `!` writes no module-level `let mut` that code outside its module can observe."
> 6. Tier 2 user effects stay as an optional, finer label (`! State, Parse.Advance`). They are no longer the only way to expose state.
>
> **Tradeoffs (DX):**
> - The 90% case costs nothing. Private helpers and scripts with one `main` file need no annotations. The compiler (157 globals in typecheck.bl) only changes its `pub` surface.
> - Error messages are mechanical: one fix, one token. An LLM learns it from one example.
> - Cost: caches and memo tables (Python `@lru_cache` style). A `pub fn lookup` that fills a module cache now needs `! State`, and so do all its callers. That will produce Stack Overflow questions ("why does my pure lookup need State?"). I accept this. The function *is* stateful, and the answer fits in one line. I propose no escape hatch in v1.
> - Conflict: under rule 2, a `Display.fmt` impl that writes module state widens the trait row, which is E0904. That reopens part of display-fmt-empty-effect-row (which says no spec rule, only a lint). I favour the error, because a `fmt` that writes globals is a bug. The panel can instead exempt trait impls and keep the lint.
> - R2 rejected `! State` for ceremony on ~80 parser functions. This proposal does not do that. Private functions stay clean, and only the `pub` boundary pays. Principle 6 asks for exactly that: "explicit at boundaries, terse within."
>
> **Cross-language:** Python makes you write `global x` before you write a module global, a marker where the write happens. JS/TS/Kotlin have no marker at all. Proposal A is closer to Python but moves the marker to where readers look: the exported signature.
>
> **Proposal B (fallback): keep inference, fix the text, fix Tier 2**
>
> If the panel will not add `State`, do these three things:
> - Make the wording fixes in rule 5.
> - Add a lint, **UndeclaredModuleState** (warning), on a `pub fn` with a non-empty write set and no user effect in its row.
> - Make a user effect that has no operations exempt from E0539, so Tier 2 can be used without a handler in `main`.
>
> This is cheaper, but the signature still does not tell all. A warning is something people learn to ignore.
>
> **Rejected**
>
> - **C. Ban module-level `let mut`.** Counters, registries, caches and singletons are how scripts work. The compiler itself has 157 of them in one file. Blink has no other place for long-lived state, so a ban forces state structs through every signature. That is a hard no from the 5-minute-test side.
> - **D. `! State` on every writer, private ones too.** R2 already rejected this for ceremony, and there is no new fact against that vote.
>
> **Vote intent:** A first, B second, never C.
>
> Note: the example above follows the syntax rules but I did not compile-check it. Today's compiler has no `State` effect, so it cannot check `! State`. While testing a scratch file I found that `print` is now an undefined function (expected after the effect-tracked-builtins change), so examples must not use it.

- **PLT:**

> **The problem, stated formally**
>
> Today the spec says two things that contradict each other. §1.2 P3 says "no `!` ⇒ pure, its output depends only on its inputs". §4.1 and §4.16 say a function with no `!` may read and write module state. Take this example:
>
> ```blink
> // module ids
> let mut count = 0
>
> pub fn next_id() -> Int {
>     count = count + 1
>     count
> }
> ```
>
> `next_id` has the type `() -> Int` with an empty row, so the signature says it is pure. But `next_id() == next_id()` is false. The typing judgement is unsound with respect to the spec's own meaning of an empty row.
>
> The R2 decision is sound inside a module, because the write set is a full analysis there. It breaks at three exits, because cross-module calls are opaque:
>
> 1. `pub` functions.
> 2. Function values. A private writer coerced to `fn() -> Int` loses its write set in the type.
> 3. Trait impl methods. A `Display.fmt` that writes a global is called through the trait from other modules.
>
> Write-set inference answers "which bindings". The type system must still answer "whether".
>
> ---
>
> **Proposal 1 (FAVOURED): one sealed `State` effect; declared at the boundary, inferred inside**
>
> This is the ML approach: inference inside a structure, an explicit signature at the `.mli`. It also follows Koka, where `st<h>` is an ordinary row entry.
>
> ```blink
> let mut count = 0
> let mut log: List[Str] = List.new()
>
> fn bump() {                          // private: `State` inferred, no annotation
>     count = count + 1
> }
>
> pub fn next_id() -> Int ! State {    // boundary: must declare
>     bump()
>     log.push("id")
>     count
> }
>
> pub fn current() -> Int ! State {    // reads also count at the boundary
>     count
> }
>
> fn main() ! State, IO.Log {
>     let a = ids.next_id()
>     io.log("{a}")
> }
> ```
>
> **Normative rules**
>
> 1. **R1 (built-in effect).** `State` is a built-in leaf effect with no operations. It is sealed: no handler, no `with`. It reaches `main` and test roots like any built-in effect. `@capabilities` budgets ignore it, which keeps §4.16.6.
> 2. **R2 (elaboration).** Let A(f) be the module-level `let mut` bindings that f reads or writes, directly or through calls within the module. The effective row of f is its declared row ∪ {`State` | A(f) ≠ ∅}. A call to a function whose declared row has `State` adds `State` to the caller's effective row.
> 3. **R3 (boundary).** If f is `pub`, or is an impl of a trait method, and its effective row has `State`, then its declared row must name `State`. Private functions, closures and lambdas get `State` by elaboration and need no annotation.
> 4. **R4 (function values).** A function value's type carries its effective row. So coercing a stateful private fn to `fn() -> Int` fails with the existing row-mismatch error. No special rule is needed.
> 5. **R5 (trait methods).** E0904 (no widening) applies to the effective row. An impl of `Display.fmt`, `Eq.eq`, `Hash.hash` or `Ord.cmp` that touches module state is rejected. This settles the soundness half of display-fmt-empty-effect-row.
> 6. **R6 (diagnostics keep the fine data).** Write sets W(f) ⊆ A(f) stay binding-level and writes-only for W0550/W0551, as they are now. `State` is the coarse type; the write set is the refinement used for diagnostics.
> 7. **Spec text.** §4.1 line 11 and §4.16.3/§4.16.6 change to: "an empty effective row means the function neither performs side effects nor reads or writes module-level `let mut`". P3 then holds as written.
>
> **Typing rule (sketch)**
>
> ```
> Γ ⊢ x : T   x ∈ ModMut(M)
> ─────────────────────────────  (read or write of module state)
> Γ ⊢ x : T ! {State}
>
> f pub ∨ f ∈ impl Tr   State ∈ eff(f)   State ∉ declared(f)
> ─────────────────────────────────────────────────────────  E-UndeclaredModuleState
> ```
>
> **Diagnostics**
>
> - **`UndeclaredModuleState` (new E-code).** "`pub fn next_id` reads or writes module state (`count`, `log`) but its row does not name `State`". The help line is "add `! State`", and a note lists A(f).
> - **Function-value and trait cases** reuse the existing row-mismatch error and E0904. Each gets a note naming the bindings.
>
> **Why reads count at the boundary**
>
> P3 is about referential transparency, not about corrupting state. `current()` with no `!` is not a function of its inputs. Inside a module, reads stay free for the write-set diagnostics. In the type they count, because purity is the property the type promises.
>
> **Answers to the R2 objections**
>
> - **"`State` is a boolean."** At the boundary a boolean is the right size. The bindings are private, so a pub signature must not name them.
> - **"Ceremony on 80 functions."** Only the pub and impl surface is annotated. Private parser functions stay clean.
> - **"Sealed is inconsistent."** `State` is a sealed, operation-free marker. That is the honest model, the same as Koka's `div`, and there is nothing to mock.
>
> **Tradeoffs**
>
> - It is sound.
> - It composes with closures, traits and async. A spawned closure's row now shows `State`, which a later race rule can key on.
> - It reuses the row machinery rather than adding a second, parallel judgement.
> - **Costs:**
>   - a migration of pub functions and impls in src/ and lib/std that touch globals;
>   - `State` comes back by name after it was removed;
>   - reads-at-boundary will annotate some getters.
>
> **Cross-language**
>
> OCaml leaves this untracked, and that is the failure mode in this ticket. Haskell puts `IORef` in `IO`. Koka infers `st<h>` and shows it in the type. Rust gates `static mut` behind `unsafe`.
>
> ---
>
> **Proposal 2: boundary rule with a user-declared effect (Tier 2 made mandatory)**
>
> Same R2–R5, but R3 accepts any effect declared in the same module, for example `! Parse.Advance`. Then rule E0539 forces callers to discharge it with a `with` handler. That gives a fake handler for an effect with no operations, which is ceremony without meaning. It also lets an author satisfy the check with an unrelated effect. **Reject**; Proposal 1 is the principled form of it.
>
> **Proposal 3: ban module-level `let mut` (state only through handlers)**
>
> This is the most principled option: all state is a handled effect, as in Koka/Eff. It is too costly for v1, with 157 bindings in typecheck.bl alone. It also adds an allocation and indirection model to hot compiler paths. **Reject for v1**; Proposal 1 does not rule it out later.
>
> **Proposal 4: keep R2 and weaken P3's wording**
>
> This makes the spec agree with itself by giving up the guarantee. **Reject**: that is "works in practice" over a broken typing claim.
>
> ---
>
> **Vote**
>
> Proposal 1. It is the smallest change that makes an empty row mean "pure" again.
>
> Open sub-question for the panel: reads at the boundary. I favour including them. Writes-only is the fallback, but then P3 must say "non-mutating", not "pure".

- **DevOps/Tooling:**

> My view: inference gives good tooling data, but the signature is still silent. Today the write set shows only in LSP hover and in W0550/W0551 notes. You cannot see it in `git diff`, code review, `blink doc` or the text an LLM reads. Principle 6 says "Effects are declared, not inferred", and Principle 3 says the signature tells all. Hover is not the signature.
>
> **Proposal 1 (FAVOURED): a required, checked `@modifies` that mirrors the inferred set**
>
> The compiler keeps the inference it does now; W0550/W0551 need it anyway. The signature must also state the result, and the compiler checks that the two are the same. The declared list can never drift from the code, and `blink fix` writes it, so nobody types it by hand.
>
> ```blink
> let mut pos = 0
> let mut pending: List[Str] = List.new()
>
> @modifies(pos)
> fn advance() {
>     pos = pos + 1
> }
>
> @modifies(pending, pos)
> fn skip_newlines() {
>     advance()
>     pending.push("c")
> }
>
> fn at() -> Int {
>     pos
> }
> ```
>
> I reuse `@modifies` and do not add `@writes`. The annotation table already reserves `@modifies(...)` as the frame condition for the future SMT backend. A frame condition that leaves out globals is unsound, which is why SPARK `Global =>` and ACSL `assigns` both list them. Two annotations for "what this function mutates" would break Principle 2. I checked that the file above passes `build/gen1/bin/blink check` today, so bare module idents already parse and validate.
>
> **Normative rules (§4.16.1, replacing "Fully inferred, no annotations"):**
>
> 1. The compiler computes each function's write set as it does now (transitive within the module, writes only, cross-module calls opaque).
> 2. If a function's write set is not empty, the function must have `@modifies(...)`. Its module-level names must be exactly that write set. The list can also name paths rooted at parameters, which keeps the SMT meaning.
> 3. If a function has no `@modifies`, its write set must be empty. A function with no `!` and no `@modifies` writes no module state, so §4.1 line 11 can drop its "may still write" note.
> 4. `@modifies` arguments may be module-level `let mut` names. This amends E1308, which today says arguments must be "rooted at a parameter or self".
> 5. `blink fmt` sorts the names alphabetically and wraps them one per line past the line width.
>
> **Diagnostics** (E0552 and E0553 are free):
>
> ```
> error[UndeclaredModuleWrite]: `skip_newlines` writes module state not listed in its signature
>  --> parser.bl:9:1
>   |
> 9 | @modifies(pos)
>   |           ^^^ missing `pending`
>   |
>   = note: `skip_newlines` writes {pending, pos}; `pending` via `pending.push` at 11:5
>   = help: write `@modifies(pending, pos)`
> ```
>
> ```
> error[StaleModifies]: `@modifies` on `at` names `pos`, which `at` does not write
>  --> parser.bl:14:11
>   |
>   = help: remove `pos`; drop the annotation if it is now empty
> ```
>
> Both have a machine-applicable fix, so `blink fix` resolves them in one pass. StaleModifies is an error, not a warning. A declared list that is allowed to grow stale soon becomes wrong, and a wrong list is worse than none. Rust's `unused_mut` is a warning, and in practice people ignore it.
>
> **LSP:** autocomplete inside `@modifies(` offers the module's `let mut` names. A "Sync @modifies" code action applies the fix. Hover now just repeats what the signature says.
>
> **Tradeoffs:**
> - **Set size.** Transitive closure puts large lists on driver functions; typecheck.bl has 157 `let mut` bindings. I accept this. The formatter keeps the list readable, and a 60-name list is true information: that function really does write all of that state, and reviewers should see it. I reject a `@modifies(*)` wildcard, because it is the boolean `! State` that R2 already turned down.
> - **Private names in a `pub fn` signature.** A rename of private state now changes a public annotation. I accept that, because the write is real behavior that callers depend on. `blink doc` shows the list as-is. Tier 2 user effects stay available for authors who want a domain-level name instead.
> - **Trait dispatch** (`Display.fmt` and similar) stays opaque, as cross-module calls are today. This proposal does not widen that gap or close it.
>
> **Migration:** this follows the 3-step bootstrap dance. First add the check at warning level and `task regen`. Then run `blink fix` over src/ and lib/std and `task regen`. Then make both errors hard and `task regen`.
>
> **Proposal 2 (rejected): require a user effect for writes**
>
> §4.12 says a user effect that reaches `main` with no `with` is E0539 UnhandledEffect. A write to private state has no meaningful handler, so every program would need a dummy `with parse_state_handler()`. The first error a user sees would name a handler for something that is not a capability. Effects are also coarse (one node per effect), so they lose the per-binding set that W0550 prints. The diagnostics get worse, not better.
>
> **Proposal 3 (rejected): ban module-level `let mut`**
>
> There are 157 bindings in typecheck.bl alone, plus 14 in lib/std. The ban would push everyone to thread a context struct through `mut` parameters. That is honest, but it is a large rewrite, and the error would amount to "restructure your whole module", which `blink fix` cannot apply automatically.
>
> **Proposal 4 (fallback only): make tooling show the set everywhere**
>
> `blink query --fn`, `blink doc` and LSP inlay hints would all show `writes {…}`, and the spec text would be changed to admit that the signature is silent. This is cheap and needs no migration, but it leaves the exact gap this ticket is about. I would vote for it only if Proposal 1 loses.
>
> **Spec contradiction (no fix proposed)**
>
> §4.16.3 says "The language has no syntax to mark a function as pure", but `@pure` exists in §3b contracts and in the annotation table, and E1307 enforces it.
>
> **My vote: Proposal 1.**

- **AI/ML:**

> **The problem, from the AI side**
>
> An LLM reads signatures. It does not read bodies of imported functions, and it never sees LSP hover. Today `pub fn next_token() -> Token` looks pure to every caller in another module. Because cross-module calls are opaque, the caller's signature also looks pure. So Principle 3 ("no `!` means pure") is false at exactly the place an AI depends on it. An AI will memoize the call, reorder it, or call it twice in a test, and the compiler stays silent.
>
> There is a concrete case in lib/std. `json.bl` uses `tmp_pos`, `tmp_str` and others as scratch return slots. That makes `json.parse` non-reentrant, but its signature does not show it.
>
> Principle 6 already gives the shape of the fix: "At boundaries ... explicit. Within boundaries, terse." The write set is fine as an inference inside a module. It is wrong to leave it hidden at the `pub` boundary.
>
> **Proposal A (I favour this): explicit at the boundary, inferred inside**
>
> Inside a module, nothing changes. Private functions keep their inferred write sets, and W0550/W0551 keep working. At the boundary, a function whose transitive write set is not empty must name an effect that its own module declares.
>
> ```blink
> effect Parse {
>     effect Advance
>     effect Reset
> }
>
> let mut pos = 0
> let mut pending_comments: List[Comment] = List.new()
>
> fn advance() {                       // private: write set {pos}, inferred, no row needed
>     pos = pos + 1
> }
>
> pub fn next_token() -> Token ! Parse.Advance {   // boundary: row required
>     advance()
>     // ...
> }
>
> pub fn peek() -> Token {             // OK: reads only, write set empty
>     tokens.get(pos).unwrap()
> }
> ```
>
> Callers in other modules then see `! Parse.Advance` and carry it up, the same as any user effect (§4.12). This turns Tier 2 from voluntary into checked.
>
> **Normative rules:**
>
> 1. A *boundary function* is one of these:
>    - a `pub fn` or `pub` method;
>    - a trait impl method;
>    - a function or closure whose value leaves the module (returned, stored in a `pub` value, or passed to a call into another module).
> 2. If a boundary function's write set (§4.16.1) is not empty, its effect row must contain at least one effect declared in the same module as the written binding. Otherwise the compiler reports `UndeclaredStateWrite` (next free E05xx).
> 3. Private functions do not need a row for writes. Their write sets stay inferred, as now.
> 4. An effect a module declares is always within that module's own capability budget, so `capabilities = []` packages keep working. Their callers in other modules see the effect.
> 5. Amend §4.1 line 11 and Principle 3 to say: "A `pub` function with no `!` neither performs side effects nor writes module state."
>
> **Diagnostic:**
> ```
> error[UndeclaredStateWrite]: `next_token` is public and writes module state {pos}
>   = note: callers in other modules cannot see this write
>   = help: declare an effect in this module and add it to the row:
>               effect Parse { effect Advance }
>               pub fn next_token() -> Token ! Parse.Advance
> ```
>
> **Tradeoffs (AI/ML lens):**
> - **Learnability.** It is one rule with one trigger: "a pub fn that writes a `let mut` needs a row." One example teaches it. It reuses existing syntax, so there is no new concept and no sealed special effect. That was the main objection in Round 2 to `! State`, and it does not apply here.
> - **Decision points.** Only one: what to name the effect. The help text proposes a name, and the diagnostic is fully actionable.
> - **Token cost.** It applies only to `pub` mutating functions, typically a few per stateful module. Private helpers, the bulk of a parser, cost zero tokens. That answers the Round 2 count of 80 functions: most of them are private.
> - **Generability.** Under-annotation becomes a compile error with an exact fix. Over-annotation is harmless, because declaring a row you do not use is an ordinary effect.
> - **Debuggability.** Write sets stay in diagnostics. The signature now also carries the domain name.
> - **Cost.** The callers of stateful modules propagate the effect, which is a real migration for src/ (157 globals in typecheck.bl, though mostly behind private functions). lib/std scratch globals (json, toml) will fail the rule. I count that as a feature: it surfaces non-reentrant code.
> - **Locked decision 7 (Display.fmt / Eq.eq / Hash.hash / Ord.cmp).** These have empty rows, and E0904 forbids widening them. Under rule 1, a trait impl that writes module state becomes an error. That supersedes "no spec rule" for `fmt`. I support this: a hidden write inside `==` is the most AI-hostile case there is. The panel must vote on it explicitly.
>
> **Cross-language.** Koka and Eff make state an effect everywhere, which costs tokens. Rust makes `static mut` `unsafe`, which is noisy and coarse. Python and JS track nothing, and that is the training-data norm, but it is also the source of the bugs. Proposal A uses Koka's honesty at module granularity and costs about as many tokens as Rust's `pub` keyword.
>
> **Proposal B: ban module-level `let mut`**
>
> All state would go in structs passed as `mut` parameters (§3.6). This is the cleanest for signatures, but it fights Python and JS training data. LLMs will reach for globals and then hit a wall. It also forces a large rewrite of src/. **Against.**
>
> **Proposal C: keep inference and fix only the text**
>
> Keep the current mechanism and amend Principle 3 and §4.1 to say "no `!` means no capability effects; the function may still write its own module's state". This is honest and costs zero tokens, but it leaves the AI hazard in place: signatures stay misleading across modules. **Fallback only**, if A fails.
>
> **Notes for the moderator**
>
> - Under A, module state also becomes visible to `async.spawn` reasoning, since a task that calls `! Parse.Advance` shows shared writes. §2.8 is silent on module-level `let mut`, so this needs a separate ticket. It is not a dependency of A.
> - Open question under A: how is an effect with no operations discharged? I expect it propagates to `main` or a test, or is handled by an empty `handler Parse {}`. The PLT seat should confirm that this works with today's handler rules.
>
> **Vote: A**, with C's text fix folded in.

- **Minimalism:**

> **Diagnosis**
> §4.16 builds a second, hidden "effect system" just for module state: an inference pass, W0550/W0551, a §4.1 line-11 exception, a §4.16.6 capability-budget carve-out, a separate E1013 for `pub let mut`, and a voluntary Tier 2 nothing enforces. After all that, Principle 3 still fails: `pub fn next_id() -> Int` has no `!` yet depends on call order.
>
> Tier 2 is also a poor marker: a user effect has no root handler, so `main` must discharge it (E0539). A "marker" effect forces a dummy handler on every program.
>
> lib/std evidence: json.bl uses `tmp_pos`/`tmp_str`/`tmp_int`/`parse_error` as scratch return slots — json parsing looks pure but shares globals, a data race under `async.spawn` (§2.8 says nothing about module globals). testing.bl uses globals as capture targets, which the spec already solves with stateful handlers (§4.7, line ~1554).
>
> **Proposal A (FAVOURED): remove module-level `let mut`**
> Subtraction. The language already has two signature-visible homes for changing state: a `mut` parameter (state struct, §3.6) and a handler capturing a local `let mut` (§4.7) behind a user effect.
>
> ```blink
> effect Ids {
>     effect Gen {
>         fn next() -> Int
>     }
> }
>
> fn label(name: Str) -> Str ! Ids.Gen {
>     "{name}_{ids.next()}"
> }
>
> fn main() {
>     let mut n = 0
>     let counter = handler Ids.Gen {
>         fn next() -> Int {
>             n = n + 1
>             n
>         }
>     }
>     with counter {
>         io.println(label("tmp"))
>     }
> }
> ```
>
> Parser case: `fn advance(mut p: Parser)`; save/restore is `let saved = p.clone()` — it saves all state, so the original bug (restore `pos`, forget `pending_comments`) cannot occur.
>
> Normative rules:
> - §2.12.1: "A module-level binding is `let` or `const`. Module-level `let mut` is a compile error."
> - §1.2 Principle 3 and §4.1 hold with no exception; delete §4.1 line-11 parenthetical.
> - Delete §4.16 entirely, W0550/W0551, and the §4.16.6 carve-out. display-fmt-empty-effect-row's "no rule for module let mut in fmt" becomes moot.
>
> Diagnostic: reuse E1013 (catalog: "not yet enforced", so no user break), renamed `ModuleLetMutForbidden`: "module-level `let mut` is not allowed"; help: "pass state as a `mut` parameter, or hold it in a handler for a user effect".
>
> Removes: ~200 spec lines, one compiler pass (src/mutation_analysis.bl), two warnings, one special-case error, the hidden-write hole, and the unspecified spawn/global race. Adds: nothing.
>
> Costs (honest): large migration (typecheck.bl alone 157 globals; hundreds in src; 14 in lib/std), via the 3-step bootstrap (warn → migrate → error). The handler path is spec'd but gen1 ICEs today on the example above (`SharedMutableCaptureNotLowered`) — a bug to fix first, not a reason to keep the feature. Interners/memo caches/NO_COLOR caching (term_style.bl) move to a state struct or handler; an externally-pure memo cache is the hardest case and I accept it costs a parameter or handler.
>
> Cross-language: Haskell/Elm/Roc have no mutable globals; state struct or effect covers it. Go/Python allow them and they are the classic source of test pollution and races. Rust gates `static mut` behind `unsafe` for this reason.
>
> **Proposal B (fallback if A fails on migration cost): enforce at the module boundary**
> Keep §4.16 inference inside the module; add one rule:
> - "A function callable from another module (a `pub fn`, or an impl method of a trait or type visible outside the module) whose transitive write set is non-empty must declare a non-empty effect row."
> - E0552 `HiddenModuleWrite`: "`pub fn next_id` writes module state {counter} but declares no effects"; help: "declare an effect, or move the state into a `mut` parameter".
>
> Tradeoffs: enforces exactly the Principle 3 promise ("no effects ⇒ pure") where callers cannot see the body; no new syntax, no built-in `State` (R2 objections stand). Weak: `! IO.Log` satisfies it while hiding the state write; still forces a dummy handler if a user effect is the honest choice; conflicts with display-fmt-empty-effect-row (a `Display.fmt` impl can no longer write module state, E0904 forbids widening — acceptable). Keeps all §4.16 machinery plus one rule; does not fix the spawn race.
>
> **Proposal C (REJECTED): do nothing, reword Principle 3**
> "No effects ⇒ no effects outside its own module." Zero surface, but gives up the promise that makes effects worth having. No.
>
> **Vote**
> A — the rare case where the correct fix is also the smaller language; the cost is migration work in this codebase, not user-facing complexity. If the panel will not fund the migration, B; never C.

#### Phase A.5 — Option-space after the moderator's mechanical dedupe

> Full Phase A texts: panel/A_sys.md, A_web.md, A_plt.md, A_devops.md, A_aiml.md, A_min.md. Read all six before replying.
>
> **Options (grouped mechanically; proposer attribution)**
>
> **Opt-1 — Writer effect bound to each binding, required on every writer** (Sys S1, favoured)
> `let mut pos = 0 ! Lexer.Advance`; E declared in the same module, no ops. Any function that writes the binding, directly or transitively, declares E (private ones too). Writer effects need no handler, `with` may not name one, exempt from budgets. A closure passed to `async.spawn` whose row has a writer effect is an error (E0651 SpawnWritesModuleState). Reads free.
>
> **Opt-2 — Boundary rule with one built-in sealed `State` effect** (PLT P1 favoured; Web A favoured)
> Private functions: inferred, no annotation. Boundary functions (pub fn / pub method / trait impl method / function value or closure that leaves the module) must declare `! State` when they touch module state. `State` has no ops, no handler, no `with`, ignored by budgets. Diagnostic UndeclaredModuleState / UndeclaredStateWrite.
> - Variation 2a (PLT): reads AND writes count; the effect is carried in function-value types (effective row); E0904 applies to the effective row.
> - Variation 2b (Web): writes only; reads free. Adds UnusedStateEffect warning.
>
> **Opt-3 — Boundary rule satisfied by a user-declared effect** (AI/ML A favoured; Sys S3 fallback; Min B fallback)
> Same boundary set as Opt-2, but the row must name an effect the module declares (AI/ML; Sys S3 = the Opt-1 writer effect), or any non-empty row (Min B, E0552 HiddenModuleWrite). Open sub-point raised by AI/ML: how an op-less user effect is discharged at `main` (E0539).
>
> **Opt-4 — Required, checked `@modifies(...)` naming the exact write set** (DevOps P1 favoured)
> Every function with a non-empty write set (private too) carries `@modifies(a, b)` equal to its inferred transitive write set; missing → E0552 UndeclaredModuleWrite, extra → E0553 StaleModifies, both machine-fixable. Reuses the existing `@modifies` annotation (amends E1308). Reads free. Trait dispatch stays opaque.
>
> **Opt-5 — Ban module-level `let mut`** (Min A favoured)
> Reuse E1013 as ModuleLetMutForbidden. Delete §4.16, W0550/W0551, §4.16.6 carve-out. State lives in `mut` parameters or in handlers capturing local `let mut`.
>
> **Opt-6 — Keep inference; fix the text, add tooling/lint** (AI/ML C fallback; Web B fallback; DevOps P4 fallback)
> Variants: reword P3/§4.1 (AI/ML C); a warning lint on pub writers plus E0539 exemption for op-less user effects (Web B); show write sets in `blink query`/`blink doc`/inlay hints (DevOps P4).
>
> Rejected by every proposer who raised it: "do nothing, only reword Principle 3" as a standalone (Min C, PLT P4).
>
> **Sub-questions / variations flagged for debate**
>
> - **SQ-a: Reads.** Do reads of module `let mut` count at the boundary (PLT 2a) or are reads free (everyone else)?
> - **SQ-b: Where the mark is required.** Every writer (Opt-1, Opt-4) or only the module boundary (Opt-2, Opt-3)?
> - **SQ-c: Shape of the mark.** Built-in `State` vs user/module-declared effect vs `@modifies(names)`.
> - **SQ-d: Spawn race.** Is the `async.spawn` + module `let mut` race in scope here (Sys rule 4) or a separate ticket (AI/ML note)?
> - **SQ-e: Trait impls.** Should a `Display.fmt` / `Eq.eq` / `Hash.hash` / `Ord.cmp` impl that writes module state become an error via E0904 (Sys, PLT, Web, AI/ML, Min B), superseding the "no spec rule, tooling lint" outcome of display-fmt-empty-effect-row Q5? DevOps P1 leaves trait dispatch opaque.
> - **SQ-f: Text.** Principle 3 / §4.1 line 11 / §4.16.3 wording after the change.
>
> **Facts surfaced from the codebase (facts, not votes)**
>
> 1. Sys ran `blink check` (gen1) on a program where `async.spawn(fn() { add(1) })` and the parent both call `fn add` that does `items.push(n)` on a module `let mut`. It passes. §2.8's freeze rule and E0650 cover captures only.
> 2. Sys reports gen1 accepts `fn main() ! Parse` (op-less user effect) with no `with`, though §4.6 says E0539 should fire. Spec text says E0539 fires; the compiler does not enforce it there.
> 3. Min reports the handler example (handler capturing a local `let mut`) ICEs in gen1 today: `SharedMutableCaptureNotLowered`.
> 4. DevOps reports `@modifies(pos)` with a bare module ident passes `blink check` in gen1 today, and that §4.16.3 ("no syntax to mark a function as pure") contradicts `@pure` in §3b (E1307).
> 5. lib/std/json.bl uses module `let mut` scratch slots (`tmp_pos`, `tmp_str`, ...) — raised by AI/ML and Min.
> 6. The R2 vote that chose inference over `! State` was 3-0 among PLT/Systems/AI only.

#### Phase B — Debate

One round. Each panelist replied to the deduped option-space and to the other five Phase A texts.

- **Systems:**

> **Where I shift**
>
> **I drop Opt-1 (my S1) as my first choice and move to Opt-2a (PLT P1): a built-in sealed `State`, declared at the boundary, carried by elaboration in effective rows (function values included), with reads counting.**
>
> My S1 had two goals:
> 1. get module-state access out of opaque bodies and into a type that reaches the spawn site;
> 2. keep it at zero runtime cost.
>
> PLT's R2 and R4 do the first without annotating every private writer. The effective row of a private fn or closure gets `State` by elaboration, and a function value's type carries that row. So a spawn site sees `State` on a closure that calls a private writer, and the `pub` row shows it across module edges. That was the gap that made me reject inference in Phase A, and PLT's version closes it. Annotating every writer gives the spawn check nothing more, so I withdraw the extra ceremony. Web and AI/ML are right that Principle 6 puts the mark at the boundary.
>
> I also shift on **SQ-c, built-in `State` vs a per-module effect**. A per-module effect forces one of two things: a dummy handler (E0539), or the special exemption I wrote as S1 rule 3, which makes it a sealed marker anyway. If it is sealed and erased, one built-in name is simpler than N user names, and the spawn rule needs only one bit. W0550/W0551 still give the exact bindings from the write sets.
>
> **Where I hold**
>
> **SQ-d: spawn race. In scope, with one rule.** I hold this firmly. The race is a direct consequence of the hidden set this ticket is about. Two tasks calling `add` corrupt the heap, and `blink check` passes today (fact 1). The shape we pick decides whether a static fix is possible:
> - Opt-2/2a with effective rows: yes.
> - Opt-4 `@modifies`: no row on function values, so no.
> - Opt-6: no.
> - Min B ("any non-empty row"): no, because `! IO.Log` hides it.
>
> The rule:
>
> > A closure passed to `async.spawn` whose effective row contains `State` is a compile error, **E0651 `SpawnTouchesModuleState`**: "a spawned task may not read or write module-level `let mut` (`items`, via `add`)". Help: "pass the data in, return it from the task, or use a Channel".
>
> It costs nothing at run time: no lock, no freeze counter, no branch on each global store. The alternative is a run-time freeze like §2.8, which puts a load and a branch on every global write in the program. I reject that for globals, because globals are the hottest stores in the compiler.
>
> If the moderator wants this as its own ticket, I accept that only if the vote here adopts effective rows on function values. Without them, the follow-up cannot be written.
>
> **SQ-a: reads count. I now favour 2a, for a systems reason as well as PLT's.** A read racing a write is also a data race: a task reading `items.len()` while the parent pushes sees a torn header. So the spawn rule needs reads in the row, or it is unsound. Also, only an empty row that excludes reads lets the optimizer CSE, hoist or memoize a call. With writes only, `f() + f()` still cannot fold, because `f` may read a counter that changed. That gives three reasons for 2a:
> - Principle 3's "pure" stays true as written;
> - the spawn check is sound;
> - an empty row becomes something the optimizer can use.
>
> Cost: getters at the `pub` boundary get `! State`. Config that never changes belongs in a module `let`, which stays free. lib/std's json.bl scratch slots will make `json.parse` carry `State` and keep it out of spawned tasks. That is correct, because it is non-reentrant today. Fix json.bl to use locals; that is a perf-neutral change.
>
> **SQ-e: trait impls. Error via E0904 on the effective row.** A `Hash.hash` that touches globals breaks every hash map that uses it, and an `Eq.eq` that writes breaks sort and dedup. These must be errors. This supersedes display-fmt-empty-effect-row Q5's "no spec rule". DevOps P1 leaves this opaque, which is a gap.
>
> **Zero cost holds.** `State` is erased like every row entry. It has no evidence parameter and no handler. A function-value type that carries `State` changes nothing in the C ABI or in mono, because rows are already erased before lowering. I checked this against my S1 claim: same property, same codegen.
>
> **Other options**
>
> - **Opt-2b (Web):** acceptable second. It is the same machinery but writes only. That leaves the read half of the race open and keeps "pure" false. If 2b wins, the spawn rule must still key on reads, which means computing a read set anyway. 2a costs the same.
> - **Opt-1 (my S1):** third. It is sound for writes but costs more annotations for no extra guarantee once effective rows exist.
> - **Opt-3 (AI/ML A):** acceptable only if op-less module effects need no `with` (fact 2 shows gen1 does not enforce E0539 today, but the spec does). Otherwise it is a dummy handler in every `main`. Min B's "any row" is unsound as a marker, and I reject it.
> - **Opt-4 (`@modifies`):** reject as the solution. A pub signature that lists private binding names couples callers to internals: a rename of a private global breaks the public API. Driver functions in typecheck.bl would carry 60+ names. The lists do not reach function values or spawn sites. I support DevOps's tooling half (show write sets in `blink query` / `blink doc`) as a non-normative addition. Agree with fact 4: §4.16.3's "no syntax to mark pure" must be fixed either way.
> - **Opt-5 (ban):** honest, and codegen for a state struct is fine (one pointer in a register). But the handler route Min offers costs real run time: a heap cell for the captured `let mut`, handler dispatch on each `next()`, and today an ICE (fact 3). For an interner on a hot path that is a regression from a plain global store. The migration across about 230 globals is large. I do not favour a ban, but I keep it above Opt-6.
> - **Opt-6 (text + lint):** reject. It leaves the race and the false "pure".
>
> **SQ positions (summary)**
>
> | SQ | Position |
> |----|----------|
> | a | Reads count in the effective row (2a). Write sets stay writes-only for W0550/W0551. |
> | b | Mark required at the boundary only (pub fn, pub method, trait impl). Private fns and closures carry `State` by elaboration. |
> | c | One built-in sealed `State`: no ops, no handler, no `with`, exempt from budgets. |
> | d | In scope: E0651 SpawnTouchesModuleState on the effective row. Splitting it out is acceptable only if effective rows on function values are adopted here. |
> | e | Error via E0904 on the effective row. Supersedes display-fmt Q5. |
> | f | P3 stays as written. §4.1 line 11 becomes "an empty effective row means no side effects and no access to module-level `let mut`". §4.16.3 is rewritten to agree with `@pure` (E1307). §4.16.6 "Not an effect" is replaced. |
>
> **Ranking**
>
> 2a > 2b > Opt-1 > Opt-3 (AI/ML form, with an E0539 exemption) > Opt-5 > Opt-4 > Opt-6.

- **Web/Scripting:**

> **Where things stand**
>
> Four of the six seats (PLT, AI/ML, Web, and Min's fallback B) already agree on the core idea. Code inside a module stays inferred, and the boundary is explicit. Sys's S3 fallback has the same shape. The real arguments are about the *shape of the mark* (SQ-c), *reads* (SQ-a) and *spawn* (SQ-d). I hold Opt-2 and shift on reads.
>
> **SQ-a: Reads. I shift to PLT 2a: reads count at the boundary**
>
> In Phase A I said reads are free. PLT changed my mind, and the deciding reason is a DX one, not a theory one:
>
> - **One rule is easier to teach than two.** "If a pub fn touches a module `let mut`, write `! State`" fits in one sentence. "Writes need it, reads don't, but your result still changes between calls" is the kind of fine print that produces Stack Overflow questions.
> - **Principle 3 stays true as written.** We then do not have to weaken "no effects means pure" into "no effects means non-mutating". Every reader of P3 (human or LLM) already believes the strong version. Keeping the text and making it true beats rewording it.
> - **The cost is small.** Getters such as `peek()` / `current()` get `! State`. Module `let` (immutable) and `const` stay free, so config values that are set once do not pay. Only `let mut` does.
>
> Inside the module, reads stay out of the write set, so W0550/W0551 do not change (PLT R6).
>
> I drop my UnusedStateEffect idea. With reads counted, the existing unused-effect handling (if any) is enough, and a new warning is not worth the surface.
>
> **SQ-b: Where the mark is required. Hold: boundary only**
>
> Sys's spawn race is the strongest new fact in this round, and it is real (fact 1). But it does not need a mark on every private writer. Under PLT's R2/R4, every function and closure has an *effective row* that includes `State` by elaboration, and that row is carried in function-value types. So the closure in Sys's example:
>
> ```blink
> let h = async.spawn(fn() { add(1) })
> ```
>
> already has `State` in its effective row, even though `add` is private and has no annotation. A spawn rule can key on that row. The fact crosses the module edge through the pub signature (`! State`), and stays exact inside the module through elaboration. That covers the race without 80+ annotations on parser internals.
>
> Opt-1 and Opt-4 put the mark on every private writer. For a Python or JS dev, that is the "first program is 50% annotations" failure we rejected in R1/R2. Private code in one file is already readable locally: the body is right there.
>
> **SQ-c: Shape of the mark. Hold built-in `State`. Opt-3 is my second choice**
>
> **Against `@modifies(names)` (Opt-4):** it puts *private* binding names into *public* signatures. Renaming a private variable then changes a public API, which no JS/TS/Kotlin/Python dev expects. DevOps accepts 60-name lists on driver functions. To me that is noise: a reviewer cannot use a 60-name list, and it shows up in every diff. `blink fix` writing it for you does not fix that it is unreadable. It also leaves trait dispatch opaque, so `==` can still hide a write.
>
> **Against a per-binding writer effect (Opt-1):** `let mut pos = 0 ! Lexer.Advance` is new syntax that no mainstream language has. Users must also design an effect tree for their globals before they can write one counter. The 5-minute test fails: "why do I need to declare an effect to have a counter?"
>
> **Opt-3 (user/module-declared effect at the boundary):** acceptable as a second choice, with two conditions:
> 1. An op-less effect declared in the same module needs no handler and is exempt from E0539 (Sys rule 3). Without that, every `main` writes a dummy handler. That is the trap in today's Tier 2, which Sys, DevOps, Min and I all named. (Fact 2 says gen1 does not enforce E0539 for op-less effects today, but the spec says it fires, so the spec must say otherwise.)
> 2. "Any non-empty row" (Min B) is not acceptable. `! IO.Log` must not satisfy a state rule.
>
> With those two conditions, Opt-3 is really built-in `State` under a user-chosen name. That adds a naming decision (Principle 2: one way) and gains a little domain meaning. I still prefer the single built-in name: there is nothing to design, nothing to name, and the help text says exactly one thing.
>
> **On the R2 "sealed is inconsistent" objection:** Blink already has "gated, not virtualized" second-tier functions (§4.4.6), so a gate with no handler is not new. `State` is the same kind of thing.
>
> **SQ-d: Spawn race. Separate ticket, but Opt-2a gives it the hook**
>
> I agree with AI/ML: file it separately. It is a real P1 race, but it is a concurrency rule (§2.8) and needs its own vote on details. For example, with reads counted, does a task that only *reads* a global that nobody writes count as a race? A blanket "spawned closure with `State` is an error" would forbid that safe case. The Opt-2a effective row makes the follow-up a short rule rather than a new analysis. Sys: I think this answers your "only a fact in the signature reaches where it is needed" point. It does reach there, without the per-writer cost.
>
> **SQ-e: Trait impls. Hold: error via E0904**
>
> A write (or, under 2a, a read of mutable state) inside `fmt`, `eq`, `hash` or `cmp` is a bug in nearly every real program. Think of a `==` that changes depending on call order. Supersede the "no spec rule" outcome of display-fmt-empty-effect-row Q5. DevOps's opaque-dispatch position leaves the worst case open.
>
> **SQ-f: Text**
>
> - Principle 3: no change. With 2a it is true as written.
> - §4.1 line 11: replace the parenthetical with "A function whose effective row is empty neither performs side effects nor reads or writes module-level `let mut`. Private functions get `State` by inference (§4.16); public functions, trait impl methods and escaping function values declare it."
> - §4.16.1 "Not an effect" and §4.16.6 "Not an effect": rewrite. The *write set* is an analysis, and *`State`* is an effect.
> - §4.16.3: fix the false sentence "The language has no syntax to mark a function as pure" (DevOps found `@pure` / E1307). This is a text bug whatever wins.
> - §4.16.5 Tier 2: say that user effects are an optional *extra* label, not the mechanism.
>
> **Opt-5 (ban). Hold reject**
>
> Min's case is clean on paper. In practice:
> 1. The replacement path ICEs in gen1 today (fact 3, `SharedMutableCaptureNotLowered`). We would ban a working feature in favour of one that does not compile.
> 2. The handler replacement for one counter means an effect tree, a handler, and a `with` in `main` (Min's own example). For a scripting dev, that is about 15 lines in place of `let mut n = 0`.
> 3. Memo caches become a parameter threaded through every caller. That is the "function coloring" complaint, made worse.
>
> Min's point that `p.clone()` saves *all* state, so the original save/restore bug cannot happen, is good. But a user can choose that pattern under Opt-2 too; the language does not need to force it.
>
> **Ranking**
>
> 1. **Opt-2a**: built-in sealed `State`, boundary only, reads and writes count, effective row carried in function types, E0904 on the effective row.
> 2. Opt-2b (writes only). Fallback if the panel thinks reads cost too much.
> 3. Opt-3 with the E0539 exemption and "must be a module-declared effect".
> 4. Opt-1. It is sound, but its ceremony fails the 5-minute test.
> 5. Opt-6. Honest but leaves the gap.
> 6. Opt-4. Private names in public APIs.
> 7. Opt-5. Never in v1.

- **PLT:**

> **Summary of where I stand**
>
> - **Hold:** the mark must be a row entry, so it lives in function types and composes with function values, traits and spawn. That rules out `@modifies` as the only mechanism.
> - **Hold:** the boundary rule (Opt-2), with the mark carried in the *effective* row of private functions and closures by elaboration.
> - **Shift:** on reads (SQ-a), I give way. Writes-only is acceptable if the Principle 3 text stops saying "pure" (see SQ-f).
> - **Shift:** I now rate Sys S3 as nearly equal to Opt-2. S3 is a writer effect bound to each binding, checked only at the boundary. It is sound, and it is Opt-2 with user-chosen names.
> - **New:** the elaboration in my P1 (R2/R4) already fixes Sys's spawn race without annotating every writer. I propose the spawn rule goes in this ticket.
>
> **Replies to the other panelists**
>
> **Sys (S1, every writer).** The race example is the strongest new fact this round, and I accept it. But it does not need annotations on every writer. Under Opt-2a R2/R4, the closure `fn() { add(1) }` has the effective row `{State}`, because `add` writes `items`. The row is inferred inside the module. Across modules it is declared, because `add` is `pub` and R3 forces `! State`. So the spawn site sees the fact in both cases, and E0651 can key on the effective row. The argument "only a fact in the signature carries across the module edge" is right, and the boundary rule puts the fact in exactly the signatures that cross that edge.
>
> What S1 adds over S3 is a written row on private functions. That gives readers locality, not soundness. Principle 3 lists "body" as an input, and a private function's effective row is a type fact the compiler holds and tooling shows. I count S1 as acceptable, but it is ceremony R2 rejected, and the soundness argument does not need it.
>
> One correction for Sys: "an empty row means you can reorder, hoist and memoize" stays false while reads are free. A row-less reader memoized across a `State` call returns a stale value. With writes-only, the optimiser may reorder row-less calls among themselves. It must not move a call across any call whose row has `State`. That is still a useful guarantee, but the spec must state it that narrowly.
>
> **DevOps (`@modifies`).** I reject this as the mechanism, for three reasons:
> 1. **Not compositional.** A function type `fn() -> Int` has no place for `@modifies`. So function values and trait dispatch stay holes, as DevOps admits ("trait dispatch stays opaque"). The ticket is about exactly that hole.
> 2. **Breaks abstraction.** It puts private binding names into `pub` signatures, so renaming private state becomes an API change. In type-theory terms, it exposes the representation of an abstract type.
> 3. **Clashes with the SMT frame meaning.** That meaning is per-call and needs a different checker. Sharing the name for a transitive closure invites confusion.
>
> I support DevOps's tooling half: write sets in `blink query`, `blink doc` and inlay hints. They also flagged that §4.16.3 says there is no syntax for "pure" while `@pure` exists (E1307). Under my proposal, `@pure` means: the effective row is empty and the function reads no module `let mut`. That gives `@pure` a precise meaning and puts the reads question (SQ-a) where it belongs.
>
> **AI/ML (Opt-3, a user effect declared in the module).** Answer to the PLT question asked of me: under §4.6 and §4.12 as written, an op-less user effect that reaches `main` without a `with` is E0539. Gen1 does not enforce this today (fact 2), but the spec rule stands. So a plain Opt-3 forces `with handler Parse {}` on every binary. The fix is a separate discharge rule for "state marker" effects, and that is exactly Sys's writer-effect class (no handler, no `with`). So Opt-3 done correctly *is* Sys S3. I could accept it.
>
> **Min (Opt-5, ban).** This is the most principled option, and I agree it is where state ought to live in the long run. But the handler path ICEs today (fact 3). The migration is hundreds of bindings. And state in a `mut` struct gives up nothing that Opt-2 cannot check. I vote against it for v1. Opt-2 does not close this door.
>
> On Min B ("any non-empty row"): this is unsound in the way that matters. `! IO.Log` satisfies it while hiding the state write, so the mark does not mean what it marks. I reject it.
>
> **Web (Opt-2b).** We agree on the structure. On SQ-a I move to Web's position, writes-only, with Web's honest P3 wording. On escaping closures, the effective-row formulation (my R4) is simpler than listing ways a closure can escape ("returned, stored, passed"). The type carries the row, and the existing coercion check does the work. No escape analysis is needed.
>
> **Positions on the sub-questions**
>
> | SQ | Position |
> |----|----------|
> | **a: reads** | Writes-only is acceptable; this is not a red line. Condition: the text must not say "pure" (see f). Reads count only for `@pure` (E1307). Note that a read-write race under spawn stays open (see d). |
> | **b: where** | At the boundary: `pub fn`, `pub` method, trait impl method. Function values need no listed rule, because they carry the effective row and existing row checks apply. S1 (every writer) is acceptable as a second choice. |
> | **c: shape** | Favour built-in sealed `State`. Accept Sys S3 (a writer effect named per binding, op-less, no handler, boundary-checked) as nearly equal. It gives finer names; its cost is a second class of user effect with its own discharge rule. Reject `@modifies` as the mechanism, and reject "any row". |
> | **d: spawn** | In scope, because it falls out of the same mark at no extra cost. Rule: a closure passed to `async.spawn` whose effective row has `State` (or a writer effect) is **E0651 SpawnWritesModuleState**. A spawned reader racing a writer in the parent is not covered by a writes-only mark. Open a separate ticket for it. |
> | **e: trait impls** | Error, via E0904 on the effective row. This supersedes the display-fmt-empty-effect-row Q5 "no spec rule" outcome; record it explicitly. DevOps's "opaque" is the hole this ticket exists to close. |
> | **f: text** | See below. |
>
> **Text I would adopt (SQ-f)**
>
> - **P3:** "When a function declares no effects, it performs no side effect and writes no module state. Its result may still depend on module-level `let mut` bindings that it reads. A function marked `@pure` does not read them either."
> - **§4.1 line 11:** "A function with no `!` in its effective row writes no module-level `let mut` binding. Inside a module, the compiler infers `State` for private functions (§4.16). A `pub` function or trait impl must declare it."
> - **§4.16.3:** delete "no syntax to mark a function as pure" and point to `@pure`.
> - **§4.16.6 "Not an effect":** replace with "`State` is a sealed built-in effect: it has no operations and no handler, and capability budgets ignore it. Write sets refine it for diagnostics."
>
> **Options I could accept, in order**
>
> 1. Opt-2 (built-in `State`, boundary rule, effective row, E0651, E0904).
> 2. Sys S3 (writer effect per binding, boundary-checked, same E0651 and E0904).
> 3. Sys S1 / Opt-1.
> 4. Opt-5 (not in v1).
>
> I reject: Opt-4 as the sole mechanism, Min B "any row", and Opt-6.

- **DevOps/Tooling:**

> **Where I shift: I withdraw Opt-4 (`@modifies` names) as my first choice**
>
> Three arguments from the other seats beat my Phase A proposal. I accept all three.
>
> 1. **The mark must live in the type, not in an annotation.** PLT R4 and Sys rule 4 show the leaks: function values, trait dispatch and `async.spawn`. `@modifies` is attached to a declaration. It is lost when a function becomes a value, so a spawn check or an E0904 check has nothing to read. An effect in the row goes with the value for free, and the existing row-mismatch and E0904 diagnostics report it. That is better tooling than a parallel annotation channel with its own checks.
> 2. **Private names in a pub signature are wrong.** PLT and AI/ML are right. With `pub let mut` forbidden, a caller can never name `pos`. Listing it in a public signature turns a private rename into a semver break and tells the caller nothing they can act on.
> 3. **Set size.** I said a 60-name list is "true information". Sys's per-binding writer effect gives the same truth in groups the author chooses (`Lexer.Advance`, `Typecheck.Env`), so a driver function's row holds a few names instead of 157. That is easier for the formatter, the LSP and review.
>
> `@modifies` stays as it is: the reserved SMT frame annotation, rooted at parameters. I no longer ask to extend E1308.
>
> **My ranking now**
>
> 1. **Opt-1 (Sys S1): a writer effect bound to each binding, required on every writer.** This is my new first choice.
> 2. **Opt-2b (Web A): built-in sealed `State` at the boundary, writes only.**
> 3. **Opt-3 (AI/ML A): boundary rule with a user-declared effect**, but only together with an explicit E0539 exemption for writer or op-less effects.
> 4. **Opt-6:** last resort. A warning lint plus hover is what we have now, with a better label.
> 5. **Opt-5 (ban):** never in v1. The fix is "restructure your module", and no tool can apply it mechanically. The handler alternative ICEs in gen1 today (fact 3).
>
> **Why Opt-1 is the best diagnostic surface**
>
> - **Every fix can be applied by a machine, and the fix is exact.** The binding names its effect. So for a missing row the help is always "add `! Lexer.Advance`", and `blink fix` can apply it across the call graph in one pass. Opt-2's fix ("add `! State`") is equally mechanical, but it loses the grouping.
> - **No new diagnostic family.** Missing-effect, row-mismatch, E0904 and unused-effect all exist already, with the IDE plumbing behind them. Opt-1 adds only E1017, E1018 and E0651. Each is one line, with a fix.
> - **The LSP gets go-to-definition from the effect to its bindings.** Autocomplete inside `! ` already lists effects in scope.
> - **Every writer is annotated, which answers the ticket title in full.** The signature of a private function also tells all, as Principle 3 says for "a function", not "a pub function". Principle 6 lists "function signatures" among its boundaries. The cost that R2 called ceremony is now a `blink fix` run plus diff noise that is honest: a new write to a leaf helper changes its callers' rows, exactly as a new `io.log` does today.
> - **Precedent:** Rust's `&mut self` on every parser method. Nobody runs a lint to hide it.
>
> **Opt-1 amendments I ask Sys to accept**
>
> - **A1. Where the mark goes.** In `let mut pos = 0 ! Lexer.Advance` the effect follows the initializer. For a multi-line initializer (`match`, `if`, a long call) the effect ends up after a `}`, many lines below the name. That is bad for reading, for `blink fmt` line-breaking and for grep. I propose putting it before `=`, after the optional type: `let mut pos: Int ! Lexer.Advance = 0`, or, if the parser sees a clash with function-type syntax, `let mut pos ! Lexer.Advance = 0`. I would accept either one. I reject the trailing form.
> - **A2. Visibility.** A `pub fn` whose row names a writer effect needs that effect to be `pub effect`. Use the existing private-in-public error, with the fix "make `Lexer` `pub`". Callers in other modules must be able to write the name.
> - **A3. A writer effect is never a capability.** It is exempt from E0539, and `with` may not name it. Name the fact behind this in the spec: gen1 accepts `fn main() ! Parse` today, but that is an enforcement gap (fact 2). The writer-effect exemption must be a written rule, not something that falls out of that bug.
> - **A4. One help line names a default.** E1017's help suggests `! <Module>.State` and creates the effect declaration as part of the same fix. A user with one global then gets a working program from a single quick-fix.
>
> **Positions on the sub-questions**
>
> - **SQ-a, reads:** writes only. Reads cannot corrupt state, the spawn race comes from writes, and counting reads would put a mark on every getter, which buries the signal. P3 is then reworded to say "writes nothing", not "pure" (see SQ-f). If the panel picks Opt-2, I accept PLT 2a's reads-count at the boundary only, but I vote 2b.
> - **SQ-b, where:** every writer (Opt-1). The boundary form (Opt-2/3) is my second choice. It needs a diagnostic for the non-obvious case, a private function coerced to a value, with a note that names the binding. Otherwise users see `! State` in an error with no `! State` anywhere in their source.
> - **SQ-c, shape:** a per-binding writer effect that the module declares, over built-in `State`, over `@modifies`. Built-in `State` is acceptable at the boundary only.
> - **SQ-d, spawn:** in scope, if the chosen mark is in the row. E0651 costs one check, the diagnostic is exact, and Sys showed a real heap race that passes `blink check` today. Shipping a row mark without using it at spawn leaves the key memory-safety payoff for a later ticket. With Opt-6 it goes to a separate ticket.
> - **SQ-e, trait impls:** shift. E0904 applies, so a `fmt`/`eq`/`hash`/`cmp` impl that writes module state is an error, and the display-fmt Q5 tooling lint is superseded. My Phase A left trait dispatch opaque. That was a gap: the hidden write in `==` is the worst case for every reader, human or LLM.
> - **SQ-f, text:**
>   - Principle 3 becomes: "When it declares no effects, it performs no side effects and writes no module state. Its result may still depend on module state it reads."
>   - §4.1 line 11: delete the "may still write" parenthetical.
>   - §4.16.1: replace "Fully inferred, no annotations" with the new rule. Inference stays for the W0550/W0551 detail and for hover.
>   - §4.16.3: fix the false sentence "The language has no syntax to mark a function as pure"; `@pure` exists (§3b, E1307).
>
> **What would move me further**
>
> If Sys rejects A1, so that the effect stays after the initializer, I would rank Opt-2b level with Opt-1. A mark the formatter places many lines from its name is a real tooling cost.
>
> **Status**
>
> Not fully stable. I am fixed on the *shape* (a mark in the row, writes only, trait impls fall under E0904, spawn in scope), but A1 (placement) needs Sys's answer.

- **AI/ML:**

> **Where I shift**
>
> **I withdraw Opt-3 (boundary rule satisfied by a user-declared effect) and move to Opt-2 (one built-in sealed `State`).**
>
> Web, PLT, DevOps and Min all hit the same flaw, and it is real: a user effect that reaches `main` needs a `with` (E0539, §4.6). An op-less marker effect therefore forces a dummy handler on every program that imports a stateful module. Sys reports that gen1 does not enforce E0539 here today, but the spec says it fires, and we must design against the spec, not against an enforcement gap. A dummy handler is the worst kind of token for an LLM: it means nothing, so the model cannot derive it from the code and has to memorise it.
>
> Opt-3 also had a second flaw that Min named: "any module-owned effect" lets an author satisfy the check with an unrelated effect. That is a decision point with no right answer.
>
> `State` fixes both. It is one fixed token, the diagnostic has exactly one fix ("add `! State`"), and there is nothing to name, declare or handle. In R2 I argued against `! State` because it went on every writer and was sealed and special. At the boundary only, the token count is small. The sealed, no-handler shape is honest for a marker with no operations (Koka `div`, Blink's own gated built-ins in §4.4.6), so the R2 objection does not hold here.
>
> **Where I hold**
>
> - **Boundary only, inferred inside (SQ-b).** Private functions stay clean. This is Principle 6 verbatim: explicit at boundaries, terse within. Web, PLT and Min B agree.
> - **Trait impls are a boundary (SQ-e).** A hidden write inside `==` or `fmt` is the most AI-hostile case there is, because LLMs treat those calls as pure without thinking. Apply E0904 to the effective row (PLT R5). This supersedes the display-fmt-empty-effect-row Q5 "no spec rule" result, and the panel should record that explicitly.
> - **Against the ban (Opt-5).** Min's argument is the cleanest in the abstract, but it fails on generability. Python and JS training data reaches for module globals constantly. Under a ban the model's first draft always fails, and the fix ("restructure into a state struct or a handler") is not mechanical. The handler path also ICEs in gen1 today (`SharedMutableCaptureNotLowered`). We would be pushing users onto the least-tested path.
>
> **Shift on reads (SQ-a): now I favour counting reads at the boundary (PLT 2a)**
>
> In Phase A I followed the locked "reads free". From the AI side, PLT's version is better for three reasons:
>
> 1. **One trigger, not two.** "Touches a module `let mut` → `! State`" is easier to generate than "writes one, but not if it only reads". With writes only, the model must classify each method call (`.push` is a write, `.get` is not, `.clone` is not, a user method on a struct field is ...?). Every such call is a decision point and a chance to be wrong.
> 2. **Principle 3 stays literally true.** With reads counted, "no `!` means its output depends only on its inputs" needs no footnote. An LLM that reads P3 in the spec and believes it will not be lied to. Writes-only forces P3 to say "non-mutating", which is a subtler idea and harder to apply.
> 3. **Memoisation and reordering hazards come from reads too.** `pub fn current() -> Int` with no row invites a model, or an optimiser, to cache it across a call to `next_id()`.
>
> The cost is that pub getters carry `! State`. That is a few tokens per stateful module, and it is true information.
>
> Write sets for W0550/W0551 stay binding-level and writes-only (PLT R6). Only the type-level marker counts reads.
>
> **Fallback:** 2b (writes only) if the panel keeps the locked "reads free". In that case P3 must say "non-mutating", not "pure", and I would ask for the wording to be that blunt.
>
> **Spawn race (SQ-d): in scope, one rule**
>
> Sys's gen1 repro moved me. The race is real, it compiles today, and it is exactly the bug an LLM will write, because nothing in `add`'s signature warns it off. Once `State` sits in effective rows (closures included, PLT R4), the rule is one line: a closure passed to `async.spawn` whose effective row contains `State` is an error (Sys E0651 SpawnWritesModuleState, renamed to SpawnTouchesModuleState if reads count). Splitting this into a separate ticket leaves a known memory-safety hole open while the mechanism that closes it ships. If the panel finds it contentious, split it, but do not drop it.
>
> **On Opt-1 (Sys S1: writer effect on every writer)**
>
> Sys's race argument is correct, but it does not need annotations on private functions. Opt-2 plus PLT R4 (rows carried in function values) already makes the fact cross the module edge, because every pub entry point and every escaping closure must show `State`. S1 adds:
> - new syntax, `let mut x = 0 ! E`;
> - a naming decision per module;
> - about 80+ annotations in a parser.
>
> That is more tokens and more decision points for the same guarantee at the spawn site. Sys S3 (boundary only) is close to Opt-2. Its remaining difference is "user-named sealed effect" vs "one built-in name", and one built-in name wins on learnability. I could accept S3 as a second fallback.
>
> **On Opt-4 (DevOps `@modifies` with exact names)**
>
> The DevOps diagnosis is right: hover is not the signature. The remedy has a high token cost:
> - Transitive lists on driver functions run to dozens of names.
> - Private binding names leak into `pub` signatures, so a private rename churns public API text.
> - An LLM must regenerate exact sets on every edit. `blink fix` helps humans, but a model that writes code in one pass will hit StaleModifies or UndeclaredModuleWrite on almost every edit to stateful code.
>
> It is also the only option where the mark is required on private functions and is exact rather than boolean, so it has the highest per-edit failure rate. **Against.**
>
> I strongly support DevOps P4 as a complement to Opt-2, not a replacement: `blink query --fn` and `blink doc` should print the inferred write set. That gives agents the binding-level detail without paying for it in source tokens.
>
> DevOps's catch on §4.16.3 vs `@pure` (E1307) should be fixed in the SQ-f text whichever option wins.
>
> **Current position per SQ**
>
> | SQ | Position |
> |----|----------|
> | a — reads | Count at the boundary (2a). Fallback: writes only, with P3 reworded to "non-mutating". |
> | b — where | Boundary only: pub fn, pub method, trait impl method, escaping function value or closure. Private functions are inferred. |
> | c — shape | One built-in sealed `State`: no ops, no handler, no `with`, ignored by budgets. User effects stay optional as finer labels (Web rule 6). |
> | d — spawn | In scope: spawn closure with `State` in its effective row is an error. |
> | e — trait impls | Error through E0904 on the effective row; supersedes display-fmt Q5 explicitly. |
> | f — text | PLT R7 wording for §4.1 / §4.16.3 / §4.16.6. P3 unchanged if 2a wins. Remove the "no syntax to mark pure" contradiction with `@pure`. |
>
> **Ranking**
>
> 1. Opt-2a
> 2. Opt-2b
> 3. Sys S3
> 4. Opt-6, only as a complement or a last resort
>
> Against: Opt-1 (full), Opt-4, Opt-5. Opt-3 is withdrawn and folded into Opt-2.

- **Minimalism:**

> **Where I shift**
> I withdraw Opt-5 (ban) as my vote. Five seats reject it, and the strongest point against it is fair: the language has no other home for long-lived state that is cheap today (the handler path ICEs in gen1). I keep it on record as the long-term ideal, not as this ticket's fix.
>
> With the ban gone, my lens is: which option adds the fewest new concepts and lets us delete the most existing text? That is **Opt-2 (built-in sealed `State`), variant 2a (PLT)**. I move to it.
>
> **Ranking the options by surface cost**
>
> **Opt-2 / 2a — one new name, nothing else.** It adds one built-in leaf effect. Everything else is reuse:
> - the missing-effect error and row propagation (callers in other modules);
> - function-value types carrying rows (no special rule for escaping closures);
> - E0904 for trait impls;
> - the root handler model (`main`/test hold built-ins, so no E0539 problem).
> It lets us delete: the §4.1 line-11 exception, "Not an effect" in §4.16.6, the voluntary Tier 2 as the mechanism (§4.16.5 shrinks to "you may also name your own effect"), and the open lint ticket from display-fmt-empty-effect-row. Net spec text goes down.
>
> **Opt-1 (Sys) — more surface than it needs.** New syntax on `let mut ... ! E`, a new kind of effect ("writer effect": no ops, no handler, `with` forbidden, budget-exempt), two new E-codes on declarations, and annotations on every private writer. Its goals — honesty across modules and a spawn rule — Opt-2 reaches with one built-in name and the elaborated row. The per-binding / per-domain naming is what W0550/hover already give. I would accept Opt-1 over anything below it, but not over Opt-2.
>
> **Opt-3 (user effect at boundary) — needs a new exemption.** Op-less user effects collide with E0539 (Web, DevOps, PLT all hit this). Making it work means a special "op-less effects need no handler" category, which is Opt-2's sealed effect with a user-chosen name and an extra decision point (what to call it). Min B's "any non-empty row" is weaker still: `! IO.Log` passes. I drop my own Proposal B in favour of Opt-2.
>
> **Opt-4 (`@modifies`) — most surface churn.** It gives `@modifies` a second job (frame condition AND module-state signature), amends E1308, puts private binding names into pub signatures (a rename of a private global becomes a public API change), produces 60-name lists on driver functions, and still leaves trait dispatch and function values opaque. It also annotates every private writer, which R2 rejected and no new fact overturns. Against.
>
> **Opt-6 (text + lint)** — fixes the spec's honesty by lowering the bar. A warning on a guarantee is not a guarantee. Against, except the wording fixes, which every option needs anyway.
>
> **Sub-questions**
>
> **SQ-a Reads: count them (2a).** The minimal rule is "touches module `let mut`", one predicate. Writes-only forces P3 to be reworded ("non-mutating, not pure"), which is more text and a weaker promise. Reads also race with concurrent writes, so SQ-d needs them anyway. Getters and caches paying `! State` is the true cost of being stateful. Module-level immutable `let` stays free. Inside a module the write-set analysis stays writes-only for W0550/W0551, as PLT R6 says.
>
> **SQ-b Where: boundary only.** Private functions get `State` by elaboration, never by annotation. Principle 6 ("explicit at boundaries, terse within") already says this. Every-writer annotation (Opt-1, Opt-4) is the ceremony R2 rejected.
>
> **SQ-c Shape: built-in `State`.** One name, no ops, sealed (no handler, `with State` is an error), held by `main` and test roots, ignored by `@capabilities` budgets (keeps §4.16.6). No new syntax.
>
> **SQ-d Spawn race: in scope, one line.** Once the elaborated row carries `State`, the fix is one rule: "a closure passed to `async.spawn` whose effective row contains `State` is a compile error" (Sys's E0651 SpawnTouchesModuleState). Leaving a known heap-corruption hole for another ticket when the fix is one sentence over machinery we are adding here is false economy. If the panel prefers a separate ticket, it must be filed blocking, not as a friction note.
>
> **SQ-e Trait impls: error via E0904.** No new rule; it falls out. A `fmt`/`eq`/`hash`/`cmp` that touches globals is a bug. This supersedes the "no spec rule" outcome of display-fmt-empty-effect-row Q5 for module state; the lint ticket closes.
>
> **SQ-f Text.**
> - Principle 3 stays as written. That is the point.
> - §4.1 line 11: "A function with no `!` performs no side effects and neither reads nor writes module-level `let mut` bindings. Private functions get `State` by inference (§4.16)."
> - §4.16: retitle "Module-Level State"; drop "Fully inferred / Not an effect"; §4.16.5 becomes a one-paragraph note that a module may also expose a domain effect.
> - §4.16.3: fix the `@pure` contradiction DevOps found (delete "the language has no syntax to mark a function as pure").
>
> **Note**
> I could not compile-check `! State` (gen1 has no such effect). `rg` shows no `effect State` in src/lib/sections, so the name is free.
>
> **Position**
> Opt-2a, with the SQ-d spawn rule. Second choice Opt-1. Against Opt-3, Opt-4, Opt-6 as the fix. Ban withdrawn.
>
> Stable, ready to vote.

#### Phase C — Final vote

The ballot (moderator text, every option taken from a panelist's Phase A or Phase B text):

> Post-debate option-space. Every option below comes from a panelist's Phase A or Phase B text (panel/A_*.md, panel/B1_*.md). Vote on each question independently. Do not message other panelists.
>
> For each question give:
> 1. **Vote** — the option label.
> 2. **Reasoning** — 2–4 sentences from your domain.
> 3. **Concern** — one sentence on what could go wrong with the option you expect to win, from your seat.
>
> Write your ballot to panel/C_<yourname>.md, then send team-lead a one-line "voted" message.
>
> **Q1 — Mechanism**
>
> - **Q1-A: Opt-2.** One built-in sealed `State` effect (no ops, no handler, `with State` an error, ignored by capability budgets, held by `main`/test roots). Required at the boundary: `pub fn`, `pub` method, trait impl method. Private functions and closures get `State` in their effective row by elaboration; function-value types carry the effective row (PLT R2/R4).
> - **Q1-B: Opt-1 (Sys S1) with DevOps amendments A1–A4.** A writer effect bound to each binding, required on every writer (private too). A1: mark before `=` (`let mut pos ! Lexer.Advance = 0`). A2: a pub fn row naming it needs `pub effect`. A3: writer effects exempt from E0539, `with` may not name them. A4: E1017 help offers `! <Module>.State` and creates the declaration.
> - **Q1-C: Opt-3 / Sys S3.** Boundary rule as in Q1-A, but the row names a module-declared op-less writer effect (exempt from E0539), not a built-in name.
> - **Q1-D: Opt-4.** Required, checked `@modifies(names)` on every writer (E0552/E0553).
> - **Q1-E: Opt-5.** Ban module-level `let mut`.
> - **Q1-F: Opt-6.** Keep inference; fix the text, add lint/tooling.
>
> **Q2 — Reads (applies to whichever mark wins Q1)**
>
> - **Q2-A: 2a.** Reads and writes of a module `let mut` both put the mark in the effective row. W0550/W0551 write sets stay writes-only.
> - **Q2-B: 2b.** Writes only; reads free. Principle 3 is reworded so it no longer says "pure" for a row-less function.
>
> **Q3 — Spawn race**
>
> - **Q3-A: In this ticket.** A closure passed to `async.spawn` whose effective row contains the mark is a compile error (E0651; name follows Q2: SpawnTouchesModuleState under 2a, SpawnWritesModuleState under 2b).
> - **Q3-B: Separate ticket.** File it blocking on this spec; this ticket only puts the mark in the effective row.
>
> **Q4 — Trait impls**
>
> - **Q4-A: Error via E0904 on the effective row.** A trait impl method (`fmt`, `eq`, `hash`, `cmp`, ...) whose effective row has the mark and whose trait method row lacks it is E0904. Record explicitly that this supersedes display-fmt-empty-effect-row Q5 ("no spec rule, tooling lint") for module state.
> - **Q4-B: Leave trait dispatch as display-fmt Q5 decided** (no spec rule; tooling lint).
>
> **Q5 — Text fixes**
>
> - **Q5-A: Adopt.** §4.16.3: delete "The language has no syntax to mark a function as pure" and point to `@pure` (§3b, E1307); `@pure` means an empty effective row and no reads of module `let mut`. §4.1 line 11: delete the "may still read or write module-level `let mut`" exception and state the new rule. §4.16 "Not an effect" (§4.16.1, §4.16.6) rewritten: the write set is an analysis, the mark is an effect. §4.16.5 Tier 2 user effects become an optional extra label. Principle 3 wording then follows Q2 (unchanged under 2a; reworded per Q2-B under 2b).
> - **Q5-B: Reject** (keep current text).
>
> **Q6 — Tooling (non-normative)**
>
> - **Q6-A: Adopt DevOps P4 as a complement.** `blink query --fn`, `blink doc` and inlay hints show the inferred write set.
> - **Q6-B: Leave out of this decision.**

- **Q1: Mechanism** (5-1, DevOps/Tooling dissent (Q1-B))
  - **Systems:**

    > **Q1 — Mechanism**
    > **Vote:** Q1-A
    >
    > **Reasoning:** One sealed, erased `State` costs nothing at run time: no evidence passing, no handler, and no change to the C ABI or to mono. Effective rows on function values carry the fact to every spawn site and across module edges, which is the gap that inference leaves open today. Annotating every private writer (Q1-B, Q1-D) adds no guarantee once effective rows exist.
    >
    > **Concern:** Elaboration must be fully sound for closures, `! _` rows and generic function values. A gap there leaves a hole as silent as today's.

  - **Web/Scripting:**

    > **Q1 — Mechanism**
    > **Vote:** Q1-A
    > **Reasoning:** Private code stays free of annotations, so a script or a single-file module pays nothing, and that is the 90% case. Only the pub/impl surface carries one fixed name with one fixed fix ("add `! State`"), and an LLM learns that from one example. Q1-B and Q1-D put a mark on every private writer: Q1-B adds new `let mut x ! E = 0` syntax and Q1-D puts private names in public signatures. Both fail the 5-minute test.
    > **Concern:** Memo-cache and lazy-init users will ask "why does my pure lookup need `State`?", and `State` will spread up to callers in other modules, so the help text and docs must explain this in one line.

  - **PLT:**

    > **Q1 — Mechanism: **Q1-A****
    >
    > **Reasoning.** The mark must be a row entry so that it lives in function types and composes with function values, traits and spawn. Elaboration of the effective row gives soundness without a written annotation on each private writer. One built-in sealed effect is one concept. Q1-C adds a second class of user effect with its own discharge rule, to gain names that the boundary does not need, because the bindings are private.
    >
    > **Concern.** Implementers may check only the declared row and forget the elaborated effective row of private fns and closures, which reopens the function-value hole.

  - **DevOps/Tooling:** *(dissent)*

    > **Q1 — Mechanism**
    > **Vote:** Q1-B
    > **Reasoning:** The binding names its effect, so every missing-row error has one exact fix, and `blink fix` can apply it across the whole call graph. It reuses the existing missing-effect, row-mismatch and E0904 diagnostics, and the LSP gets go-to-definition from effect to bindings. Requiring the effect on every writer makes a private function's signature tell all as well. With A1 the mark sits next to the name, where `blink fmt` and grep expect it.
    > **Concern:** The first migration of src/ makes very large row diffs, which will hide real changes in review unless it lands as one separate `blink fix` commit.

  - **AI/ML:**

    > **Q1 — Mechanism**
    > **Vote:** Q1-A
    > **Reasoning:** One fixed token with one mechanical fix ("add `! State`") is the easiest mark for an LLM to learn from a single example. There is nothing to name, declare or handle, so the mark adds no decision points. Private functions stay free of annotations, which follows Principle 6 (explicit at boundaries, terse within). Function-value rows close the closure escape without any special rule.
    > **Concern:** Callers of stateful `pub` functions must carry `State` up their own rows, which will feel like noise for memo-cache cases and may push models to sprinkle `! State` in places that do not need it.

  - **Minimalism:**

    > **Q1 — Mechanism**
    > **Vote:** Q1-A (Opt-2, built-in sealed `State`, boundary-required, elaborated inside).
    > **Reasoning:** It adds one built-in name and no syntax; everything else (row propagation, function-value row types, E0904, root-held built-ins) is reuse. It lets us delete the §4.1 exception, the "not an effect" text and the voluntary Tier 2 as mechanism, so net spec surface goes down. Q1-B adds declaration syntax, a new effect kind and per-writer annotations; Q1-D gives `@modifies` a second job and leaks private names into pub signatures.
    > **Concern:** "Required at the boundary" must also cover function values and closures that leave the module through the effective row, or the hole reopens through a callback.

- **Q2: Reads** (4-2 in Phase C (PLT and DevOps/Tooling for Q2-B); 6-0 for Q2-A in Phase D)
  - **Systems:**

    > **Q2 — Reads**
    > **Vote:** Q2-A
    >
    > **Reasoning:** A read racing a write is a data race (a torn List header), so the spawn rule is sound only if reads are in the row. Only an empty row that excludes reads lets the optimizer fold, hoist or memoize a call. Principle 3 stays true as written.
    >
    > **Concern:** Getters at the `pub` boundary must carry `! State`. Authors may then move config into module `let mut` and annotate it, where they should use an immutable `let`.

  - **Web/Scripting:**

    > **Q2 — Reads**
    > **Vote:** Q2-A
    > **Reasoning:** "Touch a module `let mut` in a pub fn, write `! State`" is one rule. A read/write split is fine print that produces confused questions. It also keeps Principle 3 true as written, which is better than rewording the promise every reader already believes. Immutable `let` and `const` stay free, so config that is set once costs nothing.
    > **Concern:** Getters on stateful modules gain `! State` and push it to their callers, which may feel noisy in large codebases.

  - **PLT:** *(dissent)*

    > **Q2 — Reads: **Q2-B****
    >
    > **Reasoning.** Per my Phase B shift, writes-only is sound for what the row now claims, provided Principle 3 stops saying "pure" for a row-less function. Optimisers may reorder row-less calls among themselves but not across a call whose row has the mark. `@pure` (E1307) carries the stronger "reads nothing" promise, so the stronger property still has a home.
    >
    > **Concern.** A spawned reader racing a writer in the parent stays unchecked, so the follow-up ticket for read races must actually be filed.

  - **DevOps/Tooling:** *(dissent)*

    > **Q2 — Reads**
    > **Vote:** Q2-B
    > **Reasoning:** Reads cannot corrupt state, and the spawn race is about writes. If reads count, every getter gets a mark, which buries the signal in noise the linter and the reviewer both learn to ignore. Principle 3 reworded to "writes nothing" is honest and easy to state in a diagnostic.
    > **Concern:** If 2a wins, users will hit "add `! State`" on plain getters, and that will read as a false positive unless the note names the binding that was read.

  - **AI/ML:**

    > **Q2 — Reads**
    > **Vote:** Q2-A
    > **Reasoning:** "Touches a module `let mut`" is one trigger. Writes-only forces the model to decide, call by call, which method calls mutate. Counting reads also keeps Principle 3 literally true, so an LLM that trusts the spec is never misled. A reader with no row invites wrong memoization or reordering across a call to a writer.
    > **Concern:** Pub getters gain `! State`, and authors may ask why a read-only accessor is "effectful". The spec must explain this in one plain line.

  - **Minimalism:**

    > **Q2 — Reads**
    > **Vote:** Q2-A (2a, reads and writes).
    > **Reasoning:** One predicate ("touches module `let mut`") is a smaller rule than a read/write split, and it keeps Principle 3 true as written instead of weakening it. Reads also race with concurrent writes, so Q3 needs them. Module-level immutable `let` stays free, and W0550/W0551 keep writes-only sets.
    > **Concern:** Getters and memo caches spread `! State` through callers, and people may push for an escape hatch that undoes the guarantee.

- **Q3: Spawn race** (5-1, Web/Scripting dissent (Q3-B))
  - **Systems:**

    > **Q3 — Spawn race**
    > **Vote:** Q3-A
    >
    > **Reasoning:** `blink check` passes a program in which two tasks push to one global List. That is heap corruption, and it comes straight from the hidden access this ticket is about. A static ban keyed on the effective row costs nothing at run time. A §2.8-style run-time freeze would put a load and a branch on every global store.
    >
    > **Concern:** Code that only reads module state that nothing changes after startup gets rejected in a task. The help text must point to an immutable module `let`.

  - **Web/Scripting:** *(dissent)*

    > **Q3 — Spawn race**
    > **Vote:** Q3-B
    > **Reasoning:** The race is real, but the rule needs its own care. Under 2a, a blanket ban would also reject tasks that only read a global nobody writes, which is safe and common. With the mark in the effective row, the follow-up is a short rule, not a new analysis. File it now, blocking on this spec.
    > **Concern:** A separate ticket may sit while users ship code that races on module state, so give it high priority.

  - **PLT:**

    > **Q3 — Spawn race: **Q3-A****
    >
    > **Reasoning.** The rule falls out of the same effective row at no extra cost. Splitting it off leaves a known heap-corruption race in a spec that now has the facts to reject it.
    >
    > **Concern.** Under 2b, E0651 covers spawned writers only, and readers concurrent with a parent writer need their own rule.

  - **DevOps/Tooling:**

    > **Q3 — Spawn race**
    > **Vote:** Q3-A
    > **Reasoning:** Once the mark is in the row, the spawn check is one check with an exact message and a clear help line ("send values back through a Channel"). Sys showed a heap race that passes `blink check` today. Shipping the mark without using it at spawn defers the main safety payoff for no reason.
    > **Concern:** The rule must use the effective row of a spawned function *value*, not only of a closure literal, or `async.spawn(worker)` will slip past it.

  - **AI/ML:**

    > **Q3 — Spawn race**
    > **Vote:** Q3-A
    > **Reasoning:** The race compiles today, and an LLM will write it, because nothing at the spawn site warns it off. Once the mark is in effective rows, the fix is one rule with one diagnostic. Shipping the mechanism without the rule would leave a known memory-safety hole open.
    > **Concern:** Under 2a, the rule also rejects spawned closures that only read module state. Some legitimate read-only fan-out will need restructuring, and the help text must say how.

  - **Minimalism:**

    > **Q3 — Spawn race**
    > **Vote:** Q3-A (in this ticket).
    > **Reasoning:** Once the mark is in the effective row, the fix is one sentence and one diagnostic over machinery this ticket already adds. Splitting it off leaves a known heap-corruption hole open for no saving in surface.
    > **Concern:** It forbids spawned tasks from calling any stateful library function (a counter-backed logger, say), which will feel strict until Channel-based patterns are documented.

- **Q4: Trait impls** (6-0)
  - **Systems:**

    > **Q4 — Trait impls**
    > **Vote:** Q4-A
    >
    > **Reasoning:** A `Hash.hash` or `Eq.eq` that touches globals silently breaks every map, sort and dedup that uses it. The trait method's empty row is the contract, so E0904 is the right check. Leaving this as a lint keeps a hole in trait dispatch, which is the most opaque call path we have.
    >
    > **Concern:** Debug-counter instrumentation inside `fmt` breaks. Authors need a clear note that a `with` handler or a `mut` parameter is the way out.

  - **Web/Scripting:**

    > **Q4 — Trait impls**
    > **Vote:** Q4-A
    > **Reasoning:** A `==`, `hash` or `fmt` whose result depends on, or changes, module state is a bug in nearly every real program, and the hardest kind to debug from a call site. Leaving trait dispatch opaque keeps the worst hiding place open. Record that this supersedes display-fmt Q5.
    > **Concern:** Someone who counts `fmt` calls for debugging will hit E0904 with no escape hatch, so the help text should point to a handler or a `mut` parameter.

  - **PLT:**

    > **Q4 — Trait impls: **Q4-A****
    >
    > **Reasoning.** Trait dispatch is one of the three exits this ticket exists to close. E0904 on the effective row closes it with an existing rule. Supersede display-fmt Q5 explicitly so the decisions stay consistent.
    >
    > **Concern.** Memoising `hash`/`fmt` impls that use module caches will break and need migration in src/ and lib/std.

  - **DevOps/Tooling:**

    > **Q4 — Trait impls**
    > **Vote:** Q4-A
    > **Reasoning:** A hidden write inside `==` or `fmt` is the worst case for any reader, and E0904 already has the diagnostic and the IDE plumbing. A lint at warning level would be ignored, which is just what the Q5 outcome predicted. Record the supersession explicitly so nobody revives the lint ticket.
    > **Concern:** Existing `fmt` impls that cache in module state (e.g. color detection) will break, and the help text must point to a concrete way out, not just "remove the write".

  - **AI/ML:**

    > **Q4 — Trait impls**
    > **Vote:** Q4-A
    > **Reasoning:** LLMs treat `==`, `fmt` and `hash` as pure without a second thought, so a hidden state touch there is the most AI-hostile case. E0904 on the effective row reuses an existing diagnostic, and the record of the supersession keeps the decision log consistent.
    > **Concern:** Lazy caches inside `hash` or `fmt` impls (interning, memoized formatting) become errors with no escape hatch, and the help must point to a concrete restructure.

  - **Minimalism:**

    > **Q4 — Trait impls**
    > **Vote:** Q4-A (error via E0904).
    > **Reasoning:** It needs no new rule; it falls out of the effective row and the existing no-widening check. A `fmt`/`eq`/`hash`/`cmp` that touches globals is a bug, and closing the open lint ticket removes a pending feature.
    > **Concern:** A legitimate interning or caching `hash` impl has no escape, so users may move the cache to a `mut` parameter in awkward ways.

- **Q5: Text fixes** (6-0)
  - **Systems:**

    > **Q5 — Text fixes**
    > **Vote:** Q5-A
    >
    > **Reasoning:** The spec contradicts itself on `@pure` and on "Not an effect". Once the mark exists, that text is wrong, and a wrong spec becomes wrong training data.
    >
    > **Concern:** §4.16 must keep the write set (an analysis for W0550/W0551) clearly separate from the mark (an effect), or readers will merge them again.

  - **Web/Scripting:**

    > **Q5 — Text fixes**
    > **Vote:** Q5-A
    > **Reasoning:** The spec contradicts itself today (P3 against §4.1/§4.16.3, and "no syntax for pure" against `@pure`). The text must match the rule we adopt.
    > **Concern:** If Q2-B wins instead, the Principle 3 rewording must be exact, or the spec keeps over-promising.

  - **PLT:**

    > **Q5 — Text fixes: **Q5-A****
    >
    > **Reasoning.** The current text contradicts itself in two ways: Principle 3 against §4.1 line 11, and §4.16.3 against `@pure`. Whatever mechanism wins, the spec must state one typing meaning for an empty row.
    >
    > **Concern.** The new Principle 3 wording must state the reads gap precisely, or readers will again take "no `!`" to mean referentially transparent.

  - **DevOps/Tooling:**

    > **Q5 — Text fixes**
    > **Vote:** Q5-A
    > **Reasoning:** The §4.16.3 sentence is false today (`@pure` and E1307 exist), and §4.1 line 11 contradicts any mark we adopt. Docs that contradict the compiler cost every `blink llms` user a round-trip.
    > **Concern:** `blink llms` topics and ERROR_CATALOG must change in the same patch, or the generated docs will contradict the spec.

  - **AI/ML:**

    > **Q5 — Text fixes**
    > **Vote:** Q5-A
    > **Reasoning:** The spec is training data, and today it contradicts itself in three places: Principle 3 against §4.1, `@pure` against §4.16.3, and "not an effect" against the new mark. A model reading contradictory text learns both rules and applies them at random.
    > **Concern:** The rewrite of §4.16 could leave stale "not an effect" phrasing in examples or the §7 catalog. The edit needs a full sweep, not a section-local patch.

  - **Minimalism:**

    > **Q5 — Text fixes**
    > **Vote:** Q5-A (adopt).
    > **Reasoning:** The current text contradicts itself (§4.16.3 vs `@pure`, §4.1 vs Principle 3). Fixing it removes text and exceptions; that is subtraction.
    > **Concern:** §4.16 rewrite must not keep stale "fully inferred / no annotation" phrasing anywhere, including the llms docs.

- **Q6: Tooling (not normative)** (5-1, Minimalism dissent (Q6-B))
  - **Systems:**

    > **Q6 — Tooling**
    > **Vote:** Q6-A
    >
    > **Reasoning:** Showing the exact write set in `blink query` and `blink doc` costs nothing and complements the boolean mark with per-binding detail. It is non-normative, so it does not tie down the spec.
    >
    > **Concern:** Tooling output may drift from the analysis unless it reads the same pass, src/mutation_analysis.bl.

  - **Web/Scripting:**

    > **Q6 — Tooling**
    > **Vote:** Q6-A
    > **Reasoning:** The exact write set is the useful detail when you debug inside a module, and showing it in `blink query`, `blink doc` and inlay hints costs nothing normative. It complements the signature mark, which says yes or no.
    > **Concern:** Inlay hints on large driver functions may be long, so tools should truncate them.

  - **PLT:**

    > **Q6 — Tooling: **Q6-A****
    >
    > **Reasoning.** The binding-level write set is the refinement of the coarse mark. Showing it in query, doc and hints costs nothing in the language and helps readers of private code.
    >
    > **Concern.** Tools must label the shown write set as inferred, not as part of the signature contract.

  - **DevOps/Tooling:**

    > **Q6 — Tooling (non-normative)**
    > **Vote:** Q6-A
    > **Reasoning:** The effect gives the yes-or-no and the inferred write set gives the detail. `blink query`, `blink doc` and inlay hints are where that detail belongs, and the analysis already exists.
    > **Concern:** If the hint and the row ever disagree, users will trust the wrong one, so both must come from the same analysis result.

  - **AI/ML:**

    > **Q6 — Tooling**
    > **Vote:** Q6-A
    > **Reasoning:** Agents work through `blink query` and `blink doc`, not hover. Printing the binding-level write set there gives the detail an LLM needs for save/restore code without paying for it in source tokens.
    > **Concern:** The output format must be stable and documented in `blink llms`, or agents will not know to look for it.

  - **Minimalism:** *(dissent)*

    > **Q6 — Tooling**
    > **Vote:** Q6-B (leave out).
    > **Reasoning:** It is non-normative and does not belong in a spec decision; the LSP already shows write sets and a tooling ticket can add query/doc output if users ask. YAGNI until the boundary mark ships and we see what is still missing.
    > **Concern:** If Q6-A wins, it becomes an implied commitment that the tooling team must build before the spec change is "done".

#### Phase D — Round 2 on Q2 (Reads)

Q2 split 4-2, so the panel debated Q2 alone for one round and then voted again. Replies:

- **Systems:**

> I hold Q2-A. I concede one point and press one.
>
> **Concession to PLT: the optimizer argument is weaker than I said**
>
> PLT is right that writes-only rows are enough for reordering. A row-less reader conflicts only with a writer, and the writer carries the mark, so the optimizer can see the barrier. I withdraw "only 2a lets the optimizer fold or hoist" as a deciding reason. It still holds for memoizing across calls, but that is minor.
>
> **The deciding point: Q3 is already decided, and 2b makes it unsound**
>
> Q3-A passed: the spawn ban keys on the mark in the effective row. Under 2b, this program passes `blink check`:
>
> ```blink
> let mut items: List[Int] = List.new()
>
> fn add(n: Int) ! State {
>     items.push(n)
> }
>
> fn count() -> Int {
>     items.len()
> }
>
> fn main() ! Async, State {
>     async.scope {
>         let h = async.spawn(fn() { count() })
>         add(1)
>         h.await
>     }
> }
> ```
>
> **DevOps** says "reads cannot corrupt state, and the spawn race is about writes". The first half is true for one thread, but the second half is false. Every memory model we target (C11, Go, Java, Rust) defines a data race as two accesses to the same location from two threads, at least one of them a write, with no ordering between them. In the example, the task reads while the parent writes. `push` can grow the List and swap its buffer pointer and length. The task can then read the new length with the old buffer and index past its end. That is not a stale value. It is an out-of-bounds read: memory unsafety, under GC or not.
>
> **PLT** proposes a follow-up ticket for read races. Look at what that ticket would need:
> - **Reads in the effective row.** That is 2a, decided later and after a second migration.
> - **A second mark for reads.** That is 2a with two names.
> - **A run-time freeze on module globals, like §2.8.** That puts a load and a branch on every global store in every program, the hottest stores in the compiler.
>
> `@pure` (E1307) cannot fill the gap. It is opt-in and absent from function-value types, so a spawn site never sees it. Writes-only does not avoid the cost of tracking reads; it only delays it.
>
> **On noise (DevOps, Web, AI/ML concerns)**
>
> I accept DevOps's fix as the condition of 2a: the E-code note must name the binding and the read site. For example: "`peek` reads module state `pos` at 12:5; add `! State`". Then a getter error reads as a fact, not as a false positive.
>
> The real cost is getters on stateful modules. That cost is honest: such a getter returns a different value after each write, which is what P3 forbids for a row-less function. Values that are set once go in an immutable `let`, which stays free.
>
> **Position**
>
> Q2-A. Under 2b, the Q3 rule this panel already adopted lets a memory-unsafe program compile.

- **Web/Scripting:**

> I hold Q2-A. Replies by name:
>
> **To DevOps ("every getter gets a mark; noise people learn to ignore"):** The mark is not on every getter. It is only on pub functions that read a module `let mut`. Getters over immutable `let`, `const`, struct fields and parameters stay free. A pub getter over mutable state is exactly the function whose answer changes between two calls with the same arguments, so the mark is the signal there, not noise. If a module has many such getters, the help text should push the author toward an immutable `let` or a state struct, which is the better design anyway. Your concern is fair and I would add it to the spec: the UndeclaredModuleState note must name the binding and say "read" or "written" (`peek` reads `pos`). Then the diagnostic does not look like a false positive.
>
> **To DevOps ("reads cannot corrupt state, and the spawn race is about writes"):** Sys answered the first part: a read during a concurrent `push` can tear a List header. So the Q3 follow-up needs reads in the row, or it must invent a second mark later. Under 2b we would ship one mark now and then add a different read mark for the spawn rule. That gives users two concepts where 2a gives one.
>
> **To PLT ("writes-only is sound for what the row claims; `@pure` carries the stronger promise"):** I agree it is sound once the text changes. My objection is about what people learn. Under 2b a user has three tiers to keep apart:
> - a row-less function writes nothing but may return different values;
> - `@pure` reads nothing;
> - `! State` writes.
>
> A JS/Python dev, and an LLM trained on "no effects = pure" (Principle 3 as it has stood), will memoize or cache the result of a row-less reader in their own code. The optimizer rule you give ("no reorder across a marked call") protects the compiler, but not the user who caches `config.level()` in a local and then calls `config.set_level()` in another module. Under 2a there are two tiers: no row means pure, and `State` means it touches module state. That fits in one sentence and keeps Principle 3 as written. `@pure` then simply means "no row", which removes a near-duplicate rather than making it load-bearing.
>
> **To PLT's concern (read races unchecked under 2b):** That concern is itself an argument for 2a. Under 2a the follow-up spawn ticket needs no new mark.
>
> **Cost I accept:** stateful-module getters spread `! State` to their callers. That spreading is the honest result, and it is also what makes the cross-module memoization case safe.
>
> Vote intent unchanged: Q2-A, with DevOps's diagnostic amendment (the note names each binding as read or written).

- **PLT:**

> I move back to **Q2-A**. Q2-A was my Phase A position (2a). I gave way in Phase B to help the panel converge, not because an argument beat it. This round brings two arguments that settle it on soundness.
>
> **Sys is right on the spawn rule.** We decided Q3-A: E0651 rejects a spawned closure whose row has the mark. Under 2b, that rule is unsound in the case Sys names. A spawned reader of `items` that races `items.push` in the parent tears the List header, and E0651 does not see it. My own Phase C concern said exactly this. A rule that we adopt to prevent a race, and that misses half the race, is the "works in practice" I object to. Under 2a the same rule covers both directions and needs no extra machinery. That makes 2a the only reading under which the Q3 decision is sound.
>
> **Sys and AI/ML are right on the optimiser.** Under 2b I had to qualify the guarantee: row-less calls may be reordered among themselves, but not across a call that carries the mark. That is a side condition every optimiser pass and every LLM must remember. Under 2a an empty effective row means what it says: the function is a function of its arguments. That is plain referential transparency, so fold, hoist and memoize are valid with no side condition.
>
> **Web and Min are right that one predicate is the smaller rule.** "Touches a module `let mut`" is one judgement. The read/write split asks the reader to classify method calls as mutating or not at each use. The write-set analysis must still do that for W0550/W0551, but users never have to.
>
> **Reply to DevOps.** "Reads cannot corrupt state" is true but answers a different question. The row does not claim "corrupts nothing". It claims "depends only on inputs", and a reader breaks that. On noise:
> - Immutable `let` and `const` stay free.
> - Private getters are inferred, so they cost nothing.
> - Only pub getters on stateful modules pay the cost, and those really are not pure. A caller that memoizes `parser.current_pos()` is wrong.
>
> I accept DevOps's concern as a diagnostic requirement. The UndeclaredModuleState note must name the binding and say "read" or "written", so the error never looks like a false positive.
>
> **Consequences if Q2-A wins:**
> - Principle 3 stays as written.
> - `@pure` (E1307) needs no separate "reads nothing" clause, because it equals an empty effective row. That simplifies Q5.
> - The E0651 name becomes SpawnTouchesModuleState.
> - No follow-up read-race ticket is needed.
>
> **Vote intent: Q2-A.**

- **DevOps/Tooling:**

> **I shift to Q2-A**
>
> **Sys** has refuted the main part of my Q2-B reasoning. I wrote "the spawn race is about writes". That is wrong. A spawned task that only *reads* `items` while the parent pushes to it reads a torn List header. That is the same memory-safety bug as two writers. Under 2b, that task's row is empty, so the E0651 check we adopted in Q3-A cannot see it. Q3-A is sound only with Q2-A. **PLT** accepts this gap and asks for a follow-up ticket. But a follow-up for "reads race too" would have to bring back reads-in-the-row anyway, and in the meantime we would ship a spawn check that claims more than it proves. From the diagnostics side that is the worst case: an error that is silent on half of the bug it names teaches users to trust a false all-clear.
>
> **AI/ML**'s point also lands in my domain. With writes-only, the analysis and every diagnostic must classify each method call on a module binding as mutating or not (`push` yes, `get` no, `iter()`? a method from a user trait taking `mut self`?). Each edge case is a place where the hint, the row and the user's guess can disagree. "Touches a module `let mut`" has no such edge cases. The LSP can underline every occurrence of the binding, and the user can check the rule by eye.
>
> **Web** and **Min** answer my noise objection: immutable `let` and `const` stay free. So the getters that gain a mark are exactly the ones whose result depends on call order. That is the signal, not noise.
>
> **What I still ask for (diagnostic surface, not a rule change)**
>
> These conditions answer my own Phase C concern and Sys's "config moved into `let mut`" concern:
>
> 1. **The note names the binding and the kind of access.** "`pub fn current` reads module state `count` (line 12)". For a read, the message must say *reads*, so it does not look like a false positive.
> 2. **A machine-applicable fix for a binding that is never written.** If a module `let mut` has an empty write set across the whole module, emit a warning: "`cfg` is never written; declare it with `let`", with the fix. Applying it removes the mark from every row that only reads it. This makes the cheap path also the correct one, and it stops authors from annotating config they should have made immutable. W0550/W0551 already compute module write sets, so this costs nothing new.
> 3. **W0550/W0551 stay writes-only**, as the ballot says. The hover and `blink query` output (Q6-A) shows reads and writes separately, so the detail is not lost.
>
> **PLT's alternative home for the stronger property**
>
> PLT says `@pure` can carry "reads nothing". That is true, but it means two promises for "no `!`" (plain row vs `@pure`). Users and LLMs will then trust the weaker one and act on the stronger one. With 2a, an empty row means one thing, and Principle 3 needs no rewording.
>
> **Revote intent: Q2-A.**

- **AI/ML:**

> I hold Q2-A.
>
> **To PLT**
>
> You say writes-only is sound "for what the row now claims", and that `@pure` (E1307) carries the stronger promise. Two problems from the generation side:
>
> 1. **`@pure` is opt-in, so it is absent from almost every signature an LLM reads.** The model must still interpret a row-less `pub fn current() -> Int`. Under 2b that signature means "writes nothing, may depend on hidden state". Under 2a it means "depends only on its inputs". A model that memoizes or reorders calls acts on the plain row, not on an annotation that is not there. A guarantee that lives in a rare annotation does not reach the common case.
> 2. **Your own concern concedes the hole.** "A spawned reader racing a writer in the parent stays unchecked, so a follow-up ticket must be filed." Sys gives the concrete failure: a torn List header. Under 2b, the Q3 spawn rule we just passed is unsound on day one, and closing it later needs a read mark anyway. So 2b does not avoid the read mark; it defers it, and ships a known race meanwhile.
>
> I accept your point that an optimiser may reorder row-less calls among themselves under 2b. But "reorder unless across a marked call" is a rule an LLM will not apply reliably. "Row-less means pure" is a rule it applies without thought.
>
> **To DevOps**
>
> 1. **"Reads cannot corrupt state, and the spawn race is about writes."** The second half is not right. A data race needs only one writer. A spawned task that reads `items` while the parent pushes to it reads a half-updated List. Sys's torn-header case is a read racing a write.
> 2. **"Every getter gets a mark ... noise the linter and the reviewer learn to ignore."** This is an error, not a lint, so nobody can learn to ignore it. And the set is small. Only `pub` functions and trait impls that touch a module `let mut` carry it. Immutable `let` and `const` stay free, as Web and Min note. A pub getter of *mutable* state is exactly the call whose result changes between two calls. That is signal, not noise.
> 3. **Noise vs decision points.** 2b trades a few tokens on getters for a classification on every call. The model must decide whether `.get`, `.iter`, `.len`, `.clone` or a user method on a field mutates. Each is a chance to omit the mark and get an error, or to add it and get an unused-effect warning. One predicate ("touches") has zero such decisions. For LLM accuracy, fewer decisions beats fewer tokens. Principle 6 says the same: ambiguity costs more than verbosity.
>
> **Your concern I adopt in full, whatever wins:** the UndeclaredModuleState diagnostic must name the binding and say "read" or "written", with the location. For example: "`current` reads module state `count` at 12:5". With that note, a getter error reads as a clear fact, not a false positive.
>
> **Summary**
>
> 2a keeps Principle 3 true as written. It makes the Q3 spawn rule sound now, not after a follow-up. It gives the model one predicate instead of a per-call classification. The cost is `! State` on pub getters of mutable state, which is true information.

- **Minimalism:**

> I hold Q2-A. Replies by name:
>
> **DevOps — "the spawn race is about writes."** It is not. A spawned task that only reads a module `List` while the parent pushes to it reads a torn header (Sys's point). Under 2b the Q3 rule (already decided: in this ticket) checks the writer task but lets the reader task through, so Q3 ships half-sound. To close it you need a second mechanism for reads later. That is more surface, not less: 2b now plus a read-race rule later is two rules where 2a is one.
>
> **DevOps — "every getter gets a mark; noise."** The mark is boundary-only (Q1-A). Private getters, which are the bulk, pay nothing. A *pub* getter of mutable state is exactly the function whose result changes between two identical calls; that is the signal, not noise. Your own concern has the fix: the note should name the binding read ("`peek` reads `pos`, which other functions write"). I support that diagnostic note. Config that never changes belongs in immutable `let`, which stays free — so 2a also pushes authors toward the right binding kind.
>
> **PLT — "writes-only is sound for what the row now claims, if P3 stops saying pure; `@pure` keeps the stronger promise."** Soundness of a weaker claim is not the bar; the claim users rely on is. 2b means: rewording Principle 3, rewording §4.1, keeping two notions of purity (empty row vs `@pure`) that users must tell apart, and filing a follow-up for read races. Each is extra text and an extra concept. 2a needs none of them. `@pure` then means "empty effective row" with no additional fine print — one notion, not two. Your own concern (the read race must be filed) is the cost 2a avoids.
>
> **Both — the optimizer point.** Under 2b, a row-less reader cannot be hoisted or memoized across any call that might write; the compiler must still consult the inferred read set, so the "pure" fact lives in an analysis again, not the signature. That is the problem this ticket exists to fix.
>
> **Cost I accept:** stateful-module getters spread `! State` to callers. That is the honest cost of the module being stateful. No escape hatch.
>
> Position: Q2-A, with DevOps's note naming the read binding.

**Phase D vote on Q2 (6-0 for Q2-A):**

- **Systems:**

> **Vote:** Q2-A
>
> **Reasoning:** Q3-A is sound only if reads are in the effective row. A spawned task reading a module List while the parent pushes to it is a data race and a possible out-of-bounds read, and under 2b E0651 cannot see it. Counting reads costs nothing at run time: `State` is erased, so there is no lock, no freeze check and no store barrier. I adopt DevOps's two conditions as part of the rule:
> - the note names the binding and says "read" or "written", with the location;
> - a module `let mut` that is never written gets a machine-applicable "declare it with `let`" warning.
>
> **Concern:** Memo caches behind a pub fn spread `State` to all callers. People will then push for an escape hatch, and that would bring the race back unless the hatch is also visible at spawn sites.

- **Web/Scripting:**

> **Vote:** Q2-A
>
> **Reasoning:** "Touches a module `let mut`" is one rule that a JS or Python dev learns from one error. With it, Principle 3 stays as written, and "no row" and `@pure` mean the same thing. Sys's torn-List example shows that writes-only would make the Q3 spawn rule unsound on day one, and PLT and DevOps now agree. DevOps's added conditions make the getter cost cheap and clear: the note names the binding and says "read" or "written", and a never-written `let mut` gets a "declare it with `let`" fix.
>
> **Concern:** Pub getters on stateful modules will spread `! State` to their callers, and people will ask for an escape hatch. The docs need a one-line answer: "use an immutable `let` or a state struct".

- **PLT:**

> **Vote:** Q2-A
>
> **Reasoning.** Q3-A is decided, and it is sound only if reads are in the row. A spawned reader racing a parent writer is a data race, the memory-unsafe torn-List case Sys showed, and under 2b E0651 cannot see it. Under 2a, an empty effective row means plain referential transparency, so Principle 3 holds as written and `@pure` equals an empty effective row with no extra clause. "Touches a module `let mut`" is one judgement. It needs no per-call classification of which methods mutate.
>
> **Concern.** Getters on stateful modules spread `! State` to their callers. So the diagnostic must name the binding and say "read" or "written", and a never-written `let mut` should get the DevOps "declare it with `let`" fix-it, or authors will feel the mark is noise.

- **DevOps/Tooling:**

> **Vote:** Q2-A
>
> **Reasoning:** Under writes-only, the E0651 spawn rule we adopted in Q3-A misses a spawned reader racing a parent writer, the torn List header Sys showed. A diagnostic that is silent on half the bug it names is worse than none, because users trust its all-clear. "Touches a module `let mut`" is also one predicate that the LSP can underline by eye, with no case-by-case decision on which method calls mutate. Immutable `let` and `const` stay free, so only getters whose result really depends on call order get the mark.
>
> **Concern:** The rule depends on two diagnostic details: the note must name each binding as "read" or "written" with its location, and a `let mut` that nothing in the module writes needs a warning with a machine fix to `let`. Without them, getter errors will read as false positives and config will pick up marks it does not need.

- **AI/ML:**

> **Vote:** Q2-A
>
> **Reasoning:** One predicate, "touches a module `let mut`", gives an LLM zero per-call decisions about which method calls mutate. It also keeps Principle 3 true as written, so a row with no `!` means one thing, not two tiers that differ from `@pure`. With Q3-A already decided, only 2a makes the spawn rule cover a reader racing a writer. The debate showed every seat converging on that point.
>
> **Concern:** Getters on stateful modules spread `! State` to their callers. Unless the diagnostic names the binding as "read" with its location, and the never-written-`let mut` → `let` fix-it that DevOps asked for ships, users and models will read the error as a false positive.

- **Minimalism:**

> **Vote:** Q2-A
>
> **Reasoning:** One predicate ("touches a module `let mut`") is the smallest rule, and it keeps Principle 3 and `@pure` as one notion instead of two. It makes the already-decided Q3 spawn rule sound now, with no second read mark or follow-up ticket later. I also support DevOps's two diagnostic conditions: the note names the binding with "read" or "written", and a never-written `let mut` gets a fix to make it `let`. Both cost nothing new and steer authors to the cheaper, correct binding.
>
> **Concern:** Stateful-module getters will spread `! State` through callers, and that pressure may later bring requests for an escape hatch that would undo the guarantee.

### AI-First Review

| Criterion | Result | Note |
|-----------|--------|------|
| Learnability | Pass | One trigger: "touches a module `let mut`". The spec states it with one example. |
| Consistency | **Fail** | `State` is the only effect that is inferred inside a module, has no operations and no handler, and is held by the roots. The gated built-ins of §4.4.6 are the nearest case. |
| Generability | Pass | Private code needs no mark. At the boundary, the rule is mechanical. |
| Debuggability | Pass | E0552 names each binding, says read or written, and gives the location, with a machine-applicable fix. |
| Token efficiency | Pass | `! State` only on boundary functions that touch module state. |

One criterion failed, so the decision went ahead. The user signed off on the tally and the two Q2 conditions.

### Final Spec

```blink
let mut count = 0

fn bump() {                          // private: `State` is inferred
    count = count + 1
}

pub fn next_id() -> Int ! State {    // public: `State` is declared
    bump()
    count
}
```

- **Q1 (mechanism).** One built-in leaf effect `State` (§4.3, §4.16.1). It has no operations and no handler: `handler State` or a `with` naming it is E0545. `main` and test blocks hold it, so E0539 never fires for it. Capability budgets ignore it. It costs nothing at run time.
- **Boundary rule.** A `pub fn`, a `pub` method and a trait impl method that touch module state declare `State` (E0552). A private function or closure gets `State` in its effective row. Function-value types carry the effective row, so existing row checks cover a value that leaves the module.
- **Q2 (reads).** Reads and writes of a module `let mut` put `State` in the row. Immutable `let` and `const` stay free. Write sets, and W0550/W0551, stay writes-only. Two conditions all six adopted: the E0552 note names each binding, says "read" or "written", and gives the location; and a module `let mut` that nothing writes gets W0552 "declare it with `let`", with a machine-applicable fix. W0552 answers the Web/Scripting Q3 concern about a read-only global: declared with `let`, it puts nothing in the row.
- **Q3 (spawn).** A function value passed to `async.spawn`, closure or named function, whose effective row contains `State` is E0651 `SpawnTouchesModuleState`.
- **Q4 (trait impls).** E0904 checks the impl method's effective row. This supersedes Q5 of [Display.fmt Effect Row](display-fmt-empty-effect-row.md) ("no spec rule; a tooling lint") for module state.
- **Q5 (text).** Principle 3 stays as written; it is now true. §4.1 drops its module-state exception. §4.16.3 points to `@pure` (E1307): an empty effective row. §4.16 no longer says "not an effect": the write set is an analysis, `State` is an effect. User-defined effects (§4.16.5) are an optional extra label next to `State`, not a replacement.
- **Q6 (tooling, not normative).** `blink query --fn`, `blink doc` and inlay hints show the inferred write set.
- **Supersedes** [Non-Local Mutable State](non-local-mutable-state.md) Round 2 in part: "Writes only", "Not an effect" and "Remove `effect State` from hierarchy". Its Round 1 (track module-level mutation), "Transitive within module" and "Cross-module: opaque" stay, for write sets.
