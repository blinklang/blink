[< All Decisions](../DECISIONS.md)

# Parameter Mutation — Design Rationale

The spec stated the mutation rule for bindings only. It said nothing about parameters. A function could call `push` on a collection it received as a parameter, with no `mut` on the parameter, and the caller's list changed. This made the stated reason for `let mut` false: `grep "let mut"` did not find every mutation source. The earlier decision [Non-Local Mutable State](non-local-mutable-state.md) voted 5-0 to defer "mutate collection received as parameter" to v2. This decision closes that gap for parameters, without the ownership or alias tracking that decision deferred.

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in independent-proposal → debate → vote rounds. Quotes are verbatim from each panelist. "…" marks a cut.

#### Phase A — Independent proposals

Each panelist measured the current compiler first, then proposed a rule. All six recommended that a parameter follows the `let` rule, with `mut` as the opt-in. No panelist proposed a mark at the call site, and all six rejected it. Each panelist ranked reading (A) of the ticket, "params mutate freely", as a fallback at best. Web rejected it outright.

- **Systems:**
  > **Rule.** A param `name: T` binds like `let name = arg`, and `mut name: T` binds like `let mut name = arg`. All binding rules apply unchanged:
  > - a mutating method call needs a `mut` root
  > - a field write needs a `mut` root
  > - rebinding needs a `mut` root
  > - `+=` needs a `mut` root
  >
  > "Root" means the first name of the receiver path. `p.xs.push(1)` needs `p` to be mut, and this applies to lets and params equally. It closes the `q.xs.push` hole my probe found. `self` follows the same rule and is spelled `mut self`. That is a binding property, not `&mut self`, and it gives the callee no route to the caller's value.
  > …
  > One extra rule for `self`: a field write or rebind of `self` is always an error, even with `mut self`. It can only change a local copy,…. Pushing to `self.items` with `mut self` is allowed, because that is a real shared-cell mutation and the caller sees it.

- **Web/Scripting:**
  > === P1 (RECOMMENDED): mut params, checked at the call ===
  > Rules:
  > 1. A parameter is immutable unless declared `mut`. A mutating method (push, pop, insert, remove, set, clear, extend) on a non-mut param gives the same MutationRequiresMut error as on a `let`.
  > 2. An argument to a `mut` param must be a `let mut` binding, a `mut` param, or a fresh value (literal or call result). An immutable `let` argument is an error.
  > 3. Assigning to a field of ANY param (`p.x = 5`, `self.x = 5`) is ALWAYS an error, `mut` or not, because the write never reaches the caller. Rebinding a param (`n = 3`) is also an error: copy it into a new local.
  > 4. No call-site marker. The caller's `let mut` already marks it.

- **PLT:**
  > 1. **Desugaring.** `fn f(mut x: T) { body }` means `fn f(x0: T) { let mut x = x0  body }`. A param without `mut` is a `let`. This gives the typing rules for free; there is one mutability judgement, not two.
  > 2. **Mutating is a signature property.** A method is mutating iff it declares `mut self`. The stdlib declares `fn push(mut self, x: T)`, `set`, `insert`, `remove`, `pop`, `clear`, `extend`, `StringBuilder.write`, and so on. This replaces the name list at :302 with a rule users can apply to their own types.
  > 3. **Rooted-place rule.** A mutating call `e.m(..)`, a field write `e.f = v`, a compound assignment and a rebind all need a *place* whose root is a `let mut` binding or a `mut` param. A place is `x`, `x.f`, `x.f.g`, and so on. This closes `p.xs.push(2)` on an immutable `p`.
  > 4. **Interface rule (subsumption).** `mut` on a param of a declared fn or trait method is part of its interface (`blink query` shows it). An impl may DROP a `mut` that the trait declares. It may not ADD one: a non-mutating body can stand in for a mutating contract, not the reverse.
  > 5. **Function values erase it.** `fn(List[Int])` has no mutable form. A lambda may write `mut` on its own params; this is binding-local only. This respects the 5-0 vote that deferred collection-mutation tracking to v2. It is also why a call-site marker (reading C) is not sound: the code that calls a closure cannot know whether the closure mutates.
  > 6. **Lost write is an error.** A field write or rebind on a place rooted at a `mut` param is an error when no read of it can follow before the function returns. `self` is a copy (§3.6), so such a write never reaches the caller. This keeps the desugaring uniform….

- **DevOps:**
  > **Rule.**
  > 1. A parameter is immutable unless it is declared `mut name: T`. That includes `self`, whose form is `mut self`. The rule covers `self` too, so the diagnostic has no special case.
  > 2. Two things need a `mut` parameter: a call to a mutating method (push, pop, insert, remove, set, clear, extend, StringBuilder.write…), and a field write on the parameter. Rebinding the parameter (`n = 3`) is a separate question, covered in point 4.
  > 3. An argument passed to a `mut` parameter must be one of these:
  >    - a `let mut` binding
  >    - a `mut` parameter
  >    - a fresh value: a literal, a constructor, or a call result
  >
  >    Without this rule, `let a = [1]; g(a)` becomes the new hole. The check is local: the compiler looks at the declaration of the argument's binding. It does no flow analysis.
  > 4. `mut` on a scalar parameter (`mut n: Int`) allows rebinding inside the callee. The caller cannot see it, so rule 3 does not apply to scalar types. The lint notes it and does not require it.

- **AI/ML:**
  > P1 RULE:
  > 1. A non-mut param has the same limits as `let`. You cannot call a mutating method on it or on any place rooted in it (`xs.push`, `p.items.push`). The error is the existing MutationRequiresMut.
  > 2. A `mut` param allows mutating method calls, and the caller sees the change (shared cell).
  > 3. ARG RULE: an argument to a `mut` param must be a place whose root is a `let mut` or a `mut` param, or a fresh value (literal, `List.new()`, call result). Otherwise it is error[MutArgRequiresMut]: "`fill` mutates its parameter `xs`, but `b` is not `let mut`", with fix: declare `let mut b`.
  > 4. A field write to or rebind of ANY param, self included, is an error with or without mut: error[WriteToParam], "write to a field of parameter `p` does not reach the caller", with fix: return the new value, or `let mut p = p`. Local rebinding uses shadowing: `let mut n = n`.
  > 5. `mut` on a param whose type has no mutating methods (Int, Str, plain struct) is an error, because it does nothing.
  > 6. StringBuildOps mutators join the mutating set. Display.fmt becomes `fn fmt(self, mut sb: StringBuilder)`.

- **Minimalism:**
  > **Rule.** A parameter follows the same rule as a `let`:
  >
  > - A parameter is immutable unless you write `mut name: T`.
  > - On a parameter, `mut` means what it means on `let`. You may call a gated mutating method on the name, assign to the name, or assign a field of it.
  > - `self` cannot be `mut`.
  > - The call site shows nothing.

#### Phase B — Debate highlights

Two rounds. After round 1, only Web said "STABLE"; the other five said "NOT STABLE". After round 2, all six said "STABLE — ready to vote".

**Round 1.** The open points were the argument rule (V1), field writes and rebinds of a parameter (V2), `mut self` (V3), the rooted-place rule (V4), `StringBuilder.write` (V5), and how to define a mutating method (V6). Systems found that an argument rule does not stop a callee from aliasing an immutable `let`:

- **Systems (round 1):**
  > V1 as written does not stop any of these three. A callee with NO `mut` param mutates an immutable `let` in two lines.
  > …
  > - **V1 (argument rule):** reject it as a rule and as a spec promise. I moved from "optional add-on" to "lint at most". A W-level lint on the direct `fill(a)` form is fine.
  > - **V2 (field write / rebind):** adopt PLT rule 6 (`LostWrite`). I moved from my `SelfFieldWriteDiscarded`.
  > …
  > **To AI/ML, Web, DevOps (V1).** Your proposed :320 text says "an immutable let is never mutated, by this function or any callee." The probe above shows that is false with V1 in place. A callee launders the alias with `let mut c = xs`. Closing that path also needs a `let mut`-from-non-mut rule (my S1b). Closing the constructor path needs fresh-value analysis through struct literals. Closing the return path (`id(a)`) needs escape analysis. That is ownership, and the panel deferred it to v2 (5-0).
  > …
  > **N1 — warning[UnusedMut].** Replaces V8. Warn on a `let mut` or `mut` param whose mutability the body never uses: no mutating call, write or rebind rooted at it. rg shows no such lint today.

- **Web/Scripting (round 1):**
  > - **V1 (argument rule):** Yes, as a rule, and extended to `let mut b = a` where `a` is not mut (Sys S1b's reach). A literal, a constructor or a call result counts as fresh. Details in section 2.
  > - **V2 (field write / rebind on a param):** Always an error, `mut` or not, `self` included. My second choice is PLT's `LostWrite`. I oppose Min and DevOps allowing it under `mut p`.
  > …
  > **PLT (V1 laundering).** You are right that `h(a)` launders an alias. I have moved on the wording, not the rule. The spec must not claim a whole guarantee. But `fill(a)` with a plain `let a` is the common mistake, and `let mut c = h(a)` is rare. A rule that catches the common case, with a stated limit, beats no rule. The same holds for `let mut b = a`: Python and JS developers think that line makes a copy. An error there answers the most likely question before anyone has to ask it.
  > …
  > **My own Phase A was wrong in one place.** My help text said "or pass a copy". The spec gives no way to copy a list: §3.2.2 Clone Semantics (03_types.md ~:3030) says `List.clone()` shares storage.

- **PLT (round 1):**
  > - **V1 argument rule:** a W-level lint (Sys S1b, `MutAliasOfImmutable`), not an error. If the panel makes it an error, it must cover `let mut b = a` too, and the spec must not claim that an immutable `let` is never changed (see AI/ML below).
  > …
  > **To AI/ML (V1, :320 text).** Your proposed :320 sentence, "An immutable let is never mutated, by this function or any callee", is false under your own rule 3. Each line below passes rule 3 and mutates `a`:
  >
  > ```blink
  > let a: List[Int] = [1]
  > fill(id(a))              // a call result counts as "fresh"
  > fill_p(P { xs: a })      // a constructor counts as "fresh"; fill_p pushes p.xs
  > let mut b = a
  > fill(b)                  // b is `let mut`
  > ```
  > …
  > **To Sys (V2), and where I moved.** My `LostWrite` kept the `mut p` = `let mut p` desugaring exact, but it needs liveness analysis, and it gives `mut p` two meanings (a local write, and mutation of a shared cell). Web and AI/ML's rule is total and needs no flow analysis. Under it, `mut` on a param means one thing: authority to call `mut self` methods through that root. The escape is explicit (`let mut q = p`). I adopt it. Your self-only special case works too, but it keeps a local-write meaning for `mut p` that has no use the escape cannot give.

- **DevOps (round 1):**
  > - **V1 argument rule:** I MOVED. It should be a lint, not an error (Sys S1b, `MutAliasOfImmutable`, also covering `let mut b = a`).
  > - **V2 field write / rebind:** a write to a field of `self`, or a rebind of `self`, is always an error (Sys `SelfFieldWriteDiscarded`). Other params follow the let rule under `mut`, plus PLT's `LostWrite` error when the write is dead. I MOVED from my "local copy only" note.
  > …
  > **To AI/ML and Web (V1). Why I moved.** Rule 3 does not give the guarantee your :320 text claims ("an immutable let is never mutated, by this function or any callee"). Three counterexamples:
  > …
  > **O1-staged (a rollout rule, not a semantics change).** Each new check ships in three stages:
  > 1. Warning, with a machine-applicable fix, and `blink fix` applies all of them.
  > 2. Migrate src and lib/std with that tool.
  > 3. Promote to an error.
  >
  > This is the 3-step bootstrap dance, stated as the user-facing policy too, so external code gets one release of warnings. Also keep my P2 as it was: LSP inlay hints for `mut` at arguments. PLT's V9 limits it: the LSP cannot show a hint for a closure call. That limit is fine to state.

- **AI/ML (round 1):**
  > - **V1 argument rule:** MOVED. Not as a hard rule sold as a guarantee. I now back Sys S1b as a lint (or a rule that also covers `let mut b = a`), plus PLT's honest :320 text. See §2.
  > …
  > **To PLT and Sys (V1): you are right, and I move.** In Phase A I claimed rule 3 makes "an immutable let is never mutated, by this function or any callee" true. It does not. `let mut b = a; fill(b)` and `fill(id(a))` both launder the cell, and both compile under my rule 3. For AI/ML this matters more than for anyone: a model learns a rule from its errors. If `fill(a)` errors but `let mut b = a; fill(b)` passes, the model learns "wrap it in a `let mut`", which is the laundering pattern. The error then teaches the bad habit and the spec claim is still false. A rule that looks like a guarantee but is not one is worse for generated code than no rule.
  > …
  > **To DevOps and Min (V2):** a `mut p` that lets `p.items.push` reach the caller while `p.x = 5` silently does not gives one keyword two meanings on the same name. …Rust and Go habits make models write exactly this. An always-error rule has one meaning: `mut` on a param means "the caller sees the change". PLT's LostWrite is acceptable, but it is flow-sensitive: a model cannot predict it without doing the dead-write analysis itself.

- **Minimalism (round 1):**
  > - **V2 (field write or rebind of a param):** I MOVED. A field write or rebind of any param is always an error, with or without `mut`, and `self` is included (Web/AI/ML). To rebind, copy into a new name: `let mut m = n`.
  > - **V3 (`mut self`):** I MOVED. Allow `mut self`. I forbade it only to stop lost writes, and V2 now does that for every param.
  > - **V4 (rooted place):** I MOVED. Yes: `p.xs.push(x)` needs `p` to be `mut`, for lets and params alike. My objection ("it breaks `self.items.push`") fell away once V3 allows `mut self`. There are 0 `self.<field>.push/insert/set/...` sites in src and lib/std, so the cost is near zero.
  > …
  > **3. New option: bundle "O1-core" for the ballot**
  >
  > This is the variations above, taken together, as one coherent rule.
  >
  > - A param is immutable unless declared `mut`, and `self` may be `mut self`.
  > - A mutating call needs a `mut` root, for lets and params alike (V4).
  > - A method is mutating if and only if it declares `mut self` (V6), and StringBuilder.write is one such method (V5).
  > - An assignment to a param, or to a field of one, is always an error (V2).
  > - `mut` erases in fn types (V9). A trait impl may drop `mut` but not add it (V7).
  > - No argument rule. Two lints instead: `MutAliasOfImmutable` (V1) and `UnusedMut` (V8).
  > - :320 takes PLT's text (V10).

**Round 2.** The argument rule moved to a lint for five of six, and Web moved in round 2 (**dissent** in round 1: Web held it as an error). The last open point was V2. Web and AI/ML held "always an error" from the start. PLT and Minimalism moved to it in round 1. DevOps and Systems moved to it in round 2, and Systems said why. Minimalism's bundle "O1-core" became the single ballot option.

- **Systems (round 2):**
  > - **V2:** I MOVED. A field write or rebind of any param, `self` included, is always an error, with or without `mut`.
  > …
  > **To PLT, Min, AI/ML, Web (V2): why I moved.** My case for `LostWrite` had two parts, and neither survives.
  >
  > - *The builder idiom* (`fn with_x(mut self, x: Int) -> Self { self.x = x; self }`). Blink has struct update: `Self { x: x, ..self }` (03b_contracts.md:161). That builds the same value, and gcc emits the same stores.
  > - *The rebind loop* (`gcd(mut a, mut b)`). It costs one `let mut m = a` line. The generated C is identical: the param is already a local copy in C, so a copy into a second local is a register rename at -O2.
  >
  > So a blanket error costs no runtime and one line of source. It also drops the liveness pass. DevOps says SetButNotRead already computes that data, but a hard error must not depend on how a flow analysis handles loops, closures captured after the write, and `?` early returns. A total, local rule has no edge cases to argue in bug reports.
  >
  > Min's point settles it for me: param `mut` then means one thing, "this function mutates the shared cells you pass". That is the only meaning the caller cares about, and `blink query` shows it.
  > …
  > lib/std/sb.bl has 10 `sb_*(sb: StringBuilder, ...)` FFI stubs with empty bodies. Under the lexical rule, an FFI fn that changes its argument on the C side shows no mutating call, so it needs no `mut`. The rule cannot see that mutation, just as it cannot see a mutation through a closure (V9).
  >
  > Proposed text beside V9: "A foreign function's params carry `mut` by declaration only. The compiler cannot check the C body. Declare `mut` on any param the foreign code mutates."

- **Web/Scripting (round 2):**
  > - **V1 (argument rule):** MOVED, from an error rule to a W-level lint `MutAliasOfImmutable`. The lint also fires on `let mut b = a` when `a` is not mut. Reasons in section 2.
  > …
  > **To Sys, PLT, DevOps, Min (V1): I moved.** The case that changed my mind is Sys's probe-sys/b.bl. There, `f(xs: List[Int]) { let mut c = xs; c.push(9) }` mutates the caller's immutable `a`, and `f` has no `mut` param at all. Extending V1 to cover `let mut b = a` closes that path. It still leaves `W { xs: a }` and `id(a)` open.
  > …
  > **To Sys and DevOps (V2).** Sys, the `gcd(mut a, mut b)` loop is a fair case, and so is Python's `items = items or []`. The problem is what `mut n: Int` does in the signature. `blink query` and hover show it to the caller, who reads "this changes my argument". A signature that exists to tell the caller something must mean one thing. The cost of always-error is one `let mut m = n` line in the callee. The cost of letting `mut` also mean "local rebind" is that every reader of every signature has to ask which meaning it has. `LostWrite` is sound, but a user cannot predict a flow-sensitive error until they hit it. Min's count also matters: 0 sites need a live write through a param. The two options are close, and I can live with either. This is a vote, not an open debate.

- **PLT (round 2):**
  > - **V2:** always an error, `mut` or not, `self` included. This is unchanged since round 1.
  > …
  > **To Sys (V2): you moved to my old rule as I moved away from it.** My reasons:
  >
  > 1. **One meaning.** Under `LostWrite`, `mut p` means two things: "the caller sees mutating calls through `p`", and "you may make local writes to `p`". Min and AI/ML put this well: a param `mut` exists to tell the CALLER something, so it should say one thing. Under always-error, `mut p` means exactly this: the function may call `mut self` methods on cells that the caller shares.
  > 2. **Predictability.** `LostWrite` is flow-sensitive. The same `self.x = x` compiles or fails depending on whether a later line reads `self`. A user or model cannot predict this without doing the liveness analysis. A total syntactic rule is decidable by looking at the line.
  > 3. **Your two examples cost one line each and lose nothing.** Examples:
  >    ```blink
  >    fn gcd(a: Int, b: Int) -> Int {
  >        let mut x = a
  >        let mut y = b
  >        while y != 0 {
  >            let t = y
  >            y = x % y
  >            x = t
  >        }
  >        x
  >    }
  >
  >    impl Point {
  >        fn with_x(self, x: Int) -> Point {
  >            Point { x: x, y: self.y }
  >        }
  >    }
  >    ```
  >    The functional update is also the more honest form: it builds a new value and does not suggest a write to the receiver. The count is 0 field writes or rebinds of a param in either tree, so no existing code pays the cost.
  > 4. **The rule can loosen later without breaking code.** Relaxing always-error to `LostWrite` later breaks no program. Tightening `LostWrite` to always-error later does.

- **DevOps (round 2):**
  > - **V2:** I MOVED to always-error (Web, PLT, AI/ML, Min). A field write or rebind of any param, `self` included, is an error with or without `mut`.
  > …
  > **To Sys (V2). Why I moved off LostWrite.** In round 1 I backed LostWrite because SetButNotRead already exists. From the tooling side, the always-error rule is the better diagnostic:
  > - It is flow-free. The LSP can report it as you type, with no false positive on a half-written function whose read you have not typed yet. LostWrite fires on `p.x = 1` until you add the read line, then goes away. That flicker is a bad editor experience.
  > - It has one message, one span and one fix-it: "copy it to a local: `let mut q = p`". A dead-write error needs a second span that shows "no read after this", and that is hard to show in a terminal.
  > - `mut` on a param then has one meaning: "the caller sees changes to the cells you pass". Hover can say exactly that.
  >
  > Your gcd case costs one line (`let mut x = a`). I accept that cost for a rule that users and the LSP can predict.

- **AI/ML (round 2):**
  > - **V2:** always an error, `self` included, `mut` or not.
  > …
  > **To Sys and DevOps (V2, LostWrite).** Sys, your `gcd(mut a: Int, mut b: Int)` example is the exact shape models copy from Rust and C. I accept it will fire. The question is which error teaches better.
  > - Always-error gives one message with a fix that always works: "parameters cannot be assigned; `let mut x = a`". A model applies it once and never meets the rule again in that shape.
  > - `LostWrite` fires only when the write is dead. So `self.x = 1; return self` passes and `self.x = 1` at the end fails. A model cannot tell which case it is in without doing the liveness analysis in its head. For generated code, a rule you cannot predict from the text is a rule you learn by trial and error, and each trial costs a compile round.
  >
  > The flat rule also keeps `mut` on a param with one meaning: "this function changes the cells you pass". Four of six panelists now hold always-error (Web, PLT, Min, AI/ML). DevOps, your SetButNotRead reuse is cheap, but cost to build was not the question; the question is predictability.

- **Minimalism (round 2):**
  > **PLT's O1-L and my O1-core are now the same bundle:** O1 + V2 always-error + V3 + V4 + V6 (thus V5) + V7 subsumption + V9 + V1 as a lint + N1. I ask the moderator to put it on the ballot as one option. Individual V-items can still be split out.
  > …
  > **To Sys and DevOps (V2, LostWrite over always-error).** My decisive point is that V7 makes param `mut` part of the interface. It shows in `blink query`, in docs and in trait conformance.
  >
  > - Under LostWrite, `fn gcd(mut a: Int, mut b: Int)` puts a purely local choice into the signature. A caller reads `mut a` and asks what gets changed. The answer is nothing.
  > - Rust gets away with `mut a` on a param only because there the keyword is pattern-local and not in the signature. Blink's is in the signature, by our own V7.
  > - Under always-error, param `mut` means exactly one thing: "this function mutates the shared cells you pass".
  > - The gcd case costs two `let mut x = a` lines. With N1 in place, `mut a: Int` would warn anyway.
  > - LostWrite also adds a flow-sensitive error class that users and models must predict. The count of existing field writes and rebinds of a param is 0.
  >
  > The simpler rule loses nothing we use.

#### Phase C — Final vote

Each panelist voted alone. The ballot had eight questions. Each panelist gave a vote, reasoning and one concern. Quotes below are the full text for each question.

- **Q1: Core rule.** (6-0 for A)
  - **Systems:**
    > **Q1. Core rule: A (O1-core).**
    > - **Reasoning:** `mut` is one bit on the binder. It costs nothing at run time, and it changes no ABI, layout or monomorphization. The only open issue is whether the spec's claim is true, and O1-core makes a claim that holds: every mutation starts at a `mut` name, and the checker verifies this locally. O2 leaves the one mutation that crosses a function boundary with no mark.
    > - **Concern:** users will still read `let` as "this storage never changes". The :320 text and the §3.6 aliasing paragraph must say the opposite plainly.
  - **Web/Scripting:**
    > **Q1. Core rule**
    > 1. **Vote:** A
    > 2. **Reasoning:** One rule, "`mut` means you may change it", for lets and params alike. A JS or Python developer learns it in five minutes, and each error comes with a one-token fix-it. O2 leaves `let` promising something the compiler does not keep across a function call. That would bring a steady stream of "why did my `let` list change?" questions.
    > 3. **Concern:** Users will still hit aliasing (`let mut b = a` shares storage) and read it as a broken promise, unless the :320 text and the lint help explain it in plain words.
  - **PLT:**
    > **Q1. Vote: A.**
    > Reasoning: O1-core has one mutability judgement for lets, params and `self`, and a mutating method is defined by its signature, not by a list of names. It claims only what it can enforce: every mutation starts at a `mut` root. It keeps the 5-0 decisions intact (mutability belongs to the binding, not the type; alias tracking is deferred to v2).
    > Concern: `mut` is erased in fn types, so a higher-order function can mutate through a closure with no mark at its caller. The spec must state this plainly, or readers will assume the guarantee is stronger than it is.
  - **DevOps:**
    > **Q1. Vote: A.**
    > Reasoning: O1-core gives one rule for lets and params, and each error lands at the name to fix with a one-token fix-it. Because V6 makes "mutating" a visible signature property, hover, `blink query` and `blink doc` can explain every error with no hidden name list.
    > Concern: the V4 root rule and the V6 signature rule both need E0610's text rewritten. If the new messages don't name the method's `mut self` declaration, users will see "why is `.foo` mutating?" with no answer on screen.
  - **AI/ML:**
    > **Q1. Vote: A (O1-core)**
    > Reasoning: One rule covers lets, params and self: a mutation needs a `mut` root, and the signature says `mut self`. A model learns it once and can check any call against `blink query` output. O2 keeps `let` in the text but not in the compiler, and models reason from the word.
    > Concern: The spec must say plainly that `mut` marks where a change starts, not every value that changes. If the doc or `llms` text drifts back to "let never changes", models will generate unsafe spawn and caching code.
  - **Minimalism:**
    > **Q1. Core rule: A (O1-core)**
    >
    > **Reasoning.** O1-core removes an exception rather than adding one: a param now follows the `let` rule. It adds no syntax, since the parser already accepts `mut` on params. V6 also replaces the hardcoded list of mutating method names with one rule that users can apply to their own types.
    >
    > O2 is cheaper on paper. But it leaves the one mutation that crosses a function boundary as the one mutation the rule does not see.
    >
    > **Concern.** V4 plus V6 changes stdlib signatures across many builtin methods at once. A missed `mut self` on one builtin mutator would reopen the hole without any warning.

- **Q2: Field write or rebind of a param.** (6-0 for A)
  - **Systems:**
    > **Q2. Field write or rebind of a param: A (always an error).**
    > - **Reasoning:** param copies are already C locals, so `let mut m = n` and `Self { x: x, ..self }` produce the same stores at -O2. The rule costs one line of source and no runtime. A total, local rule needs no liveness pass, so its behavior does not depend on how a flow analysis treats loops, closures or `?` returns.
    > - **Concern:** the ShadowedVariable warning on `let mut n = n` will push users toward awkward renames. The help text must suggest a new name.
  - **Web/Scripting:**
    > **Q2. Field write or rebind of a param**
    > 1. **Vote:** A
    > 2. **Reasoning:** A JS developer expects `p.x = 5` to reach the caller. Blink silently drops it, so a flat error is the only safe answer. `mut` on a param should mean one thing to the reader of the signature: "the caller sees the change". A flow-sensitive `LostWrite` is sound, but users cannot predict it until they hit it.
    > 3. **Concern:** Python-style param rebinding (`items = items or []`) and Go/C-style `gcd(mut a, mut b)` loops will each cost an extra `let mut` line. Some people will call that friction.
  - **PLT:**
    > **Q2. Vote: A.**
    > Reasoning: this rule decides a write from the line alone, so no flow analysis is needed. It gives a `mut` param one meaning for the caller: this function may call `mut self` methods on the cells you share with it. `LostWrite` is flow-sensitive, and a later read can change whether a line compiles. If the always-error rule is loosened later, no program breaks; the reverse change would break programs.
    > Concern: users from Rust and Go will reach for `fn f(mut n: Int) { n = ... }` and must learn the `let mut m = n` idiom from the error's help text. That help text must be good.
  - **DevOps:**
    > **Q2. Vote: A.**
    > Reasoning: an always-error rule needs no flow analysis. The LSP can report it as you type with no flicker, and it has one span and one fix ("copy to a local: `let mut q = p`"). `mut` on a param then has one meaning that hover can state exactly.
    > Concern: the gcd-style rebind loop costs a copy line. The help text must offer `let mut m = n` (a new name), or the fix-it trips ShadowedVariable.
  - **AI/ML:**
    > **Q2. Vote: A (always an error)**
    > Reasoning: A model can predict the rule from the text alone, and the fix (`let mut m = n`) always works. LostWrite depends on liveness, so a model learns it by trial and error, one compile round per trial. It also keeps one meaning for param `mut`: "the caller sees changes to the cells you pass".
    > Concern: Rust/C-trained models will write `fn gcd(mut a: Int, mut b: Int)` often. The error text must lead with the exact fix, or repair loops will be longer than needed.
  - **Minimalism:**
    > **Q2. Field write / rebind of a param: A (always an error)**
    >
    > **Reasoning.**
    > - Param `mut` is in the signature (V7, `blink query`), so it should mean exactly one thing: "this function mutates the shared cells you pass."
    > - LostWrite gives `mut` a second, local meaning that leaks into the interface.
    > - LostWrite also adds a flow-sensitive error class. There are 0 existing sites that it would permit.
    > - The escape (`let mut q = p`) costs one line.
    >
    > **Concern.** Users coming from C, Go or Rust will write `fn gcd(mut a: Int, mut b: Int)` and hit a rule that looks arbitrary. The help text must explain why and show the new-name idiom.

- **Q3: Argument to a `mut` param from a non-`mut` binding.** (6-0 for A)
  - **Systems:**
    > **Q3. Argument from a non-`mut` binding: A (lint).**
    > - **Reasoning:** the rule has at least three measured bypasses (probe-sys/b.bl): `let mut c = xs` in the callee, a constructor, and `id(a)`. Closing them needs escape or ownership analysis, which was deferred to v2 by 5-0. An error with known holes is a promise the compiler does not keep, and that is the fault this ticket was opened for.
    > - **Concern:** the lint may be noisy on common `let mut b = a` copies. It needs a clean way to say "I meant to alias".
  - **Web/Scripting:**
    > **Q3. Argument to a `mut` param from a non-`mut` binding**
    > 1. **Vote:** A
    > 2. **Reasoning:** As an error, the rule spreads up the call chain the way C++ `const` does. It also has known bypasses (`id(a)`, `W { xs: a }`), so it would teach the `let mut b = a` workaround rather than the model. A warning whose help says "this aliases `a`; a change through `b` is visible through `a`" teaches the real model. It aims straight at the Python developer who thinks assignment copies.
    > 3. **Concern:** A lint is easy to ignore. Its help text needs a real one-level copy to offer, and the spec has none today: `List.clone()` shares storage per 03_types.md ~:3030.
  - **PLT:**
    > **Q3. Vote: A.**
    > Reasoning: an error with known bypasses (`id(a)`, `W { xs: a }.xs`, a copy made inside the callee) looks like a guarantee to users and to the type system, and it is not one. A lint catches the common one-hop case without claiming soundness. Closing the bypasses needs ownership, which is deferred to v2.
    > Concern: users may read the lint's silence as proof that no alias exists. The lint's explain text must say that it checks only direct aliases.
  - **DevOps:**
    > **Q3. Vote: A.**
    > Reasoning: an error with a one-line bypass (`let mut c = xs` in the callee) teaches the bypass. A precise warning with a fix-it teaches the true aliasing model. It also avoids the semver break that an error rule causes every time a trait method adds `mut`.
    > Concern: if the lint is noisy (for example, it fires on fresh values or on call results), people will blanket-suppress it. It must fire only on a direct alias of a non-mut root.
  - **AI/ML:**
    > **Q3. Vote: A (lint)**
    > Reasoning: An error with three known bypasses (`let mut b = a` inside the callee, `id(a)`, a struct literal) teaches models the bypass and not the model of shared cells. A warning with a fix catches the common one-hop case and makes no false promise.
    > Concern: Models and users often ignore warnings. The spawn data race stays open until the separate spawn-capture ticket lands.
  - **Minimalism:**
    > **Q3. Argument from a non-`mut` binding: A (lint)**
    >
    > **Reasoning.** The error rule has three known bypasses:
    > - `let mut b = a`, if it were not covered
    > - `id(a)`
    > - `P { xs: a }`
    >
    > An error that one line silences teaches the laundering idiom and looks like a guarantee. The lint catches the common one-hop case and makes no false promise.
    >
    > **Concern.** Users may still read `let` as "this value never changes". The :320 text and the lint message must state the aliasing model plainly, or the old misreading comes back.

- **Q4: `StringBuilder.write`.** (6-0 for A)
  - **Systems:**
    > **Q4. StringBuilder.write: A (in this decision).**
    > - **Reasoning:** once V6 holds, `write(self, ...)` without `mut self` is a name-list exception written into a signature. The cost is 5 impls, the trait signature and 2 src functions. The same `blink fix` pass migrates them, and there is no runtime change.
    > - **Concern:** every external `Display` impl breaks at once, so Q8's warning release matters most here.
  - **Web/Scripting:**
    > **Q4. StringBuilder.write**
    > 1. **Vote:** A
    > 2. **Reasoning:** Once "mutating" means "declares `mut self`", leaving `write` out is a hidden exception that users and hover cannot see. The cost is `mut sb` in `Display.fmt`, which users copy from the trait signature, and a miss gets an exact fix-it.
    > 3. **Concern:** `Display.fmt` is the impl users write most often, so every existing user impl breaks. The staged rollout (Q8) must cover this with a working `blink fix`.
  - **PLT:**
    > **Q4. Vote: A.**
    > Reasoning: once V6 defines mutating as "declares `mut self`", leaving `write` out would put back the same special case V6 removes. StringBuilder is a shared cell, just like List. The migration is mechanical and changes only signatures.
    > Concern: every user `Display` impl must add `mut sb`, and this is the most visible break the decision causes. Without the Q8 warning phase and `blink fix`, that break will hurt.
  - **DevOps:**
    > **Q4. Vote: A.**
    > Reasoning: under V6 an exemption for `write` would be a special case that the tools cannot explain. The migration is small and mechanical: 7 fns, the trait and 5 impls. The trait-mismatch diagnostic can point at `Display.fmt`'s declared `mut sb`.
    > Concern: every external `Display.fmt` impl breaks at once. Without Q8-A, that is the worst upgrade experience in this decision.
  - **AI/ML:**
    > **Q4. Vote: A (in this decision)**
    > Reasoning: Leaving `write` out keeps `push` and `write` under different rules, with no signal in the code. A model can only learn that by memorizing it, and V6 exists to remove it. The measured cost is small and mechanical: 5 lib/std impls, 2 src fns, and FFI stub signatures.
    > Concern: Every user `Display` impl breaks once. Without the Q8 staged rollout and a clear fix-it, that is the most visible churn this decision causes.
  - **Minimalism:**
    > **Q4. StringBuilder.write: A (in this decision)**
    >
    > **Reasoning.** Once V6 passes, deferring means declaring `fn write(self, ...)` on a method that plainly mutates. That puts back the exception list V6 removes, and a later vote could only undo it. The measured cost is 5 `fmt` bodies, the trait line, and 2 src functions.
    >
    > **Concern.** Every user `Display` impl breaks. If rollout (Q8) does not ship a fix-it first, this is the break users will notice most.

- **Q5: Trait/impl `mut` matching.** (6-0 for A)
  - **Systems:**
    > **Q5. Trait/impl matching: A (an impl may drop `mut`, not add it).**
    > - **Reasoning:** it is sound. A body that does not mutate can stand in for a mutating contract, and nothing changes in dispatch or vtable layout because `mut` is not in the type. Exact match would force a dead `mut` on impls that do not mutate, and `UnusedMut` would then fire on them.
    > - **Concern:** `UnusedMut` must not fire on a `mut` that an impl keeps only to mirror its trait. It should only fire when the trait lacks `mut` too.
  - **Web/Scripting:**
    > **Q5. Trait/impl `mut` matching**
    > 1. **Vote:** A
    > 2. **Reasoning:** An impl that does not mutate should not have to carry a `mut` that then fires `UnusedMut` on it. With exact match, a Display impl that ignores `sb` would need either a warning suppression or a pointless write. "May drop, may not add" is also how TypeScript users think about narrower implementations.
    > 3. **Concern:** Users who read only the impl will not see that the trait allows mutation, so hover and docs must show the trait's signature.
  - **PLT:**
    > **Q5. Vote: A.**
    > Reasoning: this is the standard contravariance rule: an implementation may promise more than its contract, never less. Exact match would force a non-mutating impl to carry a `mut` that `UnusedMut` then warns about, and the user could not remove it.
    > Concern: an impl that drops `mut` might not show that the trait mutates. Hover and doc output must show the trait's signature.
  - **DevOps:**
    > **Q5. Vote: A.**
    > Reasoning: subsumption gives a clear one-direction error (`impl adds mut to x; trait declares x without it`), with a related span on the trait line. It never forces a non-mutating impl to carry a `mut` that UnusedMut would then flag, which would put two tools in conflict.
    > Concern: UnusedMut must not fire on an impl param whose trait declares `mut`, or subsumption and the lint will give contradictory advice.
  - **AI/ML:**
    > **Q5. Vote: A (an impl may drop `mut`, but not add it)**
    > Reasoning: Under exact match, an impl that does not mutate must carry a `mut` that UnusedMut then warns on, so our own lints would fire on correct code. "May drop, may not add" is one sentence that a model can apply from the trait text.
    > Concern: A model that copies the trait signature and then drops `mut` will be confused if the body later mutates. The error must point at the trait line.
  - **Minimalism:**
    > **Q5. Trait/impl `mut` matching: A (an impl may drop `mut`)**
    >
    > **Reasoning.** Under exact match, an impl that does not mutate must carry a `mut` it never uses, and UnusedMut then fires on it or needs an exemption. Subsumption avoids both, and it is the standard direction for a contract (a stronger implementation may stand in for a weaker contract).
    >
    > **Concern.** A user reading an impl alone may not see that the trait allows mutation elsewhere. That cost is small, and the docs cover it.

- **Q6: `@ffi` params.** (6-0 for A)
  - **Systems:**
    > **Q6. `@ffi` params: A (declared, not checked).**
    > - **Reasoning:** C mutates through the pointer whatever Blink says. Writing `mut` on a param the foreign code changes keeps the signature an honest contract, and `blink query` shows it. Option B would make every FFI fn a silent hole in the rule, which is the same fault as :320.
    > - **Concern:** nothing checks the declaration, so a wrong one stays wrong. The stdlib's sb stubs should stay private behind the checked `mut self` methods.
  - **Web/Scripting:**
    > **Q6. `@ffi` params**
    > 1. **Vote:** A
    > 2. **Reasoning:** The signature is the caller's documentation, and `mut` should mean the same thing everywhere: "this changes what you pass". An `@ffi` fn that fills a buffer is exactly where a caller needs that signal. It is declared only and cannot be checked, the same as any foreign type claim.
    > 3. **Concern:** A wrong or missing `mut` on an `@ffi` param gives false confidence, and no diagnostic can catch it.
  - **PLT:**
    > **Q6. Vote: A.**
    > Reasoning: a foreign fn's signature is an interface that the checker must trust, just as it trusts foreign types. The declared `mut` is the axiom the caller-side rules build on. With no `mut`, a C function that fills a buffer would be an unmarked mutation source, which is the gap this ticket closes. The claim is unchecked by nature, and the spec should say so, the same way @trusted code is unchecked.
    > Concern: a wrong `mut` annotation on a binding gives callers a false picture, and no tool can detect it.
  - **DevOps:**
    > **Q6. Vote: A.** (I moved from my round 2 position.)
    > Reasoning: from the tooling side, a declared `mut` on a foreign param is the only place the LSP and the docs can learn that the C side mutates it. Leaving it off hides a real mutation from hover. What I need is that UnusedMut never fires on `@ffi` params, because their bodies are not checked. I read A as including that.
    > Concern: the marker is not checked, so it can lie. The spec should say plainly that an `@ffi` `mut` is a promise by the binding author, not verified by the compiler.
  - **AI/ML:**
    > **Q6. Vote: A (declare `mut` on @ffi params the foreign code mutates)**
    > Reasoning: The signature is the only place a reader or model can learn that a foreign call changes a cell. Leaving it off hides exactly the mutation this ticket is about. It is unchecked, like every @ffi contract, but it is still the documentation.
    > Concern: Because it is unchecked, wrong or missing `mut` on @ffi params will go unnoticed. UnusedMut must stay silent on @ffi params, or authors will delete correct markers.
  - **Minimalism:**
    > **Q6. `@ffi` params: A (declare `mut`, unchecked)**
    >
    > **Reasoning.** The signature is what `blink query` and readers see. A stub such as `sb_write(sb: StringBuilder, ...)` that mutates its argument with no `mut` would be the one place in the language where a signature hides a mutation. The marker cannot be checked, but it keeps the interface honest.
    >
    > UnusedMut must skip @ffi fns in either option. B needs the same exemption, so B is not simpler.
    >
    > **Concern.** An unchecked marker can drift from the C body. Write it only where the foreign code plainly mutates, and keep the set of FFI stubs small.

- **Q7: Ptr writes.** (4-2 for A, settled in Phase D, see below)
  - **Systems:**
    > **Q7. Ptr writes: A (no `mut self` on Ptr writes).**
    > - **Reasoning:** a Ptr is a raw address. `p.offset(1).write(x)` or any call that returns a Ptr yields a "fresh" value, so a `mut` rule on Ptr is laundered in one call and guards nothing. FFI code is already inside the trusted boundary (`@trusted`, W0310), and C's `T* const p` allows `*p = v` for the same reason. List, Map, Set and StringBuilder are Blink-owned cells, and there the rule can hold.
    > - **Concern:** the spec must state the line, "Ptr writes are outside the `mut` rule", or users will ask why Ptr is exempt.
  - **Web/Scripting:**
    > **Q7. Ptr writes**
    > 1. **Vote:** A
    > 2. **Reasoning:** A `Ptr` is an address. Writing through it changes foreign memory, not the `Ptr` value, the same as `int *const p` in C. Requiring `let mut` on a `Ptr` to write through it would change the meaning of `mut` from "this name's storage" to "anything reachable". That is harder to explain.
    > 3. **Concern:** FFI newcomers may expect that an immutable `let p: Ptr` cannot write, so the FFI docs must say this plainly.
  - **PLT:**
    > **Q7. Vote: B.**
    > Reasoning: a `Ptr` is a handle to storage, just as a List handle is. Writing through it starts a mutation, and "`mut` marks where a mutation starts" should have no exceptions based on who owns the memory. Exempting `Ptr` would put a list of names back into a rule that V6 made depend on signatures only. The cost is small: 3 sites in libc.bl become `let mut`.
    > Concern: FFI code with many pointers gets more `mut`s, and authors may read the marker as noise.
  - **DevOps:**
    > **Q7. Vote: A.**
    > Reasoning: a `Ptr` write changes foreign memory, not the binding, so `mut self` there would force `let mut` on every pointer for no gain. It would also break lib/std/libc.bl:53-55, with an error that points at the wrong thing.
    > Concern: users may read `mut self` as "any side effect" and expect `Ptr.write` to need `mut`. The docs for `Ptr` should state the exception in one line.
  - **AI/ML:**
    > **Q7. Vote: A (Ptr writes do not declare `mut self`)**
    > Reasoning: `mut` on a binding means the value behind that name changes. A Ptr write changes foreign memory, not the Ptr value. This matches Rust, where a write through `*mut T` does not need a `mut` binding, so models trained on Rust FFI code will guess right.
    > Concern: A reader of `p.write(...)` on a plain `let p` sees a mutation with no `mut` anywhere. The spec must state this Ptr exception in one line next to V6.
  - **Minimalism:**
    > **Q7. Ptr writes: B (declare `mut self`)**
    >
    > **Reasoning.** A List is a pointer to a shared heap cell, and `push` changes the cell, not the pointer. `Ptr.write` changes the memory it points to in the same way. Exempting Ptr would put back the name-based exception list that V6 removes: "a method is mutating iff it declares `mut self`" should have no footnote. The cost is 3 sites (libc.bl:53-55) that need a `mut` root.
    >
    > **Concern.** FFI-heavy code gets noisier. If that proves painful, a later decision can revisit it with data. It should not start as an exception.

- **Q8: Rollout.** (6-0 for A)
  - **Systems:**
    > **Q8. Rollout: A (warning first, then error).**
    > - **Reasoning:** the 3-step bootstrap dance needs a warning phase anyway: accept, migrate, enforce. Stating that as user policy gives external code one release to run `blink fix`. It costs one release cycle and nothing at run time.
    > - **Concern:** warnings that last more than one release get ignored. Promotion to an error must be scheduled, not left open.
  - **Web/Scripting:**
    > **Q8. Rollout**
    > 1. **Vote:** A
    > 2. **Reasoning:** Q1 and Q4 together break real user code: every mutating function signature and every `Display` impl. One release of warnings with `blink fix` turns a wall of errors into one command. It also matches the 3-step bootstrap dance the compiler needs anyway.
    > 3. **Concern:** If `blink fix` does not cover every case (V4 field paths, trait signatures), users will get errors with no automatic migration when the warnings turn into errors.
  - **PLT:**
    > **Q8. Vote: A.**
    > Reasoning: the semantics do not depend on the rollout, and a warning release that comes with a machine-applicable fix is the same as the 3-step bootstrap applied to users. It changes no typing rule.
    > Concern: during the warning release, code that will soon be rejected still compiles, so the error has to come on schedule. It must not get stuck at warning level.
  - **DevOps:**
    > **Q8. Vote: A.**
    > Reasoning: Q4 breaks every user `Display.fmt` impl, and the new param rule breaks every function that mutates a param. A one-release warning with a machine-applicable `fix` (diagnostics.bl:546) and `blink fix` turns that into one command. It also matches the 3-step bootstrap the compiler itself must do.
    > Concern: the `fix` edits must be exact and idempotent, including for multi-line param lists that the formatter wraps. A bad auto-fix is worse than no fix.
  - **AI/ML:**
    > **Q8. Vote: A (warning first, then error)**
    > Reasoning: A machine fix that `blink fix` applies turns the migration into one command for users and for AI agents working in their repos. The one-release warning window lets generated code and docs catch up before the rule becomes an error.
    > Concern: If the warning release is skipped or runs too long, models trained on code from that window will learn that `mut` on params is optional.
  - **Minimalism:**
    > **Q8. Rollout: A (warning plus fix, then error)**
    >
    > **Reasoning.** This is the bootstrap dance the compiler already needs, stated as user-facing policy. It adds no language surface, and the fix channel already exists (diagnostics.bl:546).
    >
    > **Concern.** The warning phase must have a fixed end date or release number. Without one, "warning for a release" becomes permanent, and permanent warnings train people to ignore them.

#### Phase D — Round 2 (Q7 only)

Q7 was 4-2 in Phase C (A: AI/ML, DevOps, Systems, Web; B: Minimalism, PLT). The panel held one more round on Q7 and then re-voted alone. In the debate, Web, DevOps and AI/ML moved from A to B, and PLT moved from B to A. Systems stayed on A but withdrew its first reasoning.

- **Systems (debate):**
  > I stay on A. But I withdraw my Phase C reasoning, and I want the A side to stop using the reasoning Web and AI/ML gave.
  >
  > **To Min and PLT: you are right about two of our arguments.**
  > - Web and AI/ML say "a Ptr write changes foreign memory, not the Ptr value". `push` does not change the List handle either; it changes the cell behind it. So that distinction does not separate Ptr from List.
  > - My laundering point (`p.offset(1).write(x)`) applies to List too: `id(a).push(1)`. It does not separate them either.
  >
  > I concede both.
  >
  > **The line that does hold is what kind of state is changed, not who owns the memory.** Take your principle, "`mut` marks where a mutation starts, with no exception based on who owns the memory", one step further than Ptr. `TcpConn.write(self, data: Str)` (lib/std/net_tcp.bl:15) changes kernel buffers. `db.exec` changes a database. A file write changes the disk. If Ptr.write must declare `mut self`, then by the same rule every socket, file and DB handle does too. Every handle-holding binding becomes `let mut`, and `mut` turns into a second, weaker effect system. Blink already has a precise one: `!` effects and `@trusted`/W0310 at the FFI boundary. Neither of you proposed that extension, but B gives no stopping point short of it.
  >
  > A stopping point that holds:
  >
  > > `mut self` marks a change to state the language models as a *value*: the contents of a List, Map, Set or StringBuilder, which Blink code reads back through the same type's methods. A change to state outside the language (foreign memory, sockets, files, databases) is an *effect*, and the effect row and the trust boundary track it, not `mut`.
  >
  > Under that line:
  > - Ptr, TcpConn and File all fall on the effect side.
  > - There is no name list: the test is the kind of state the method changes, and it is stated once next to V6.
  > - `grep "mut "` still finds every place a Blink value is mutated. `grep` on the effect row finds foreign side effects. That split is useful to a reader, not a footnote.
  >
  > **Cost check.** B costs 3 `let mut cell` sites in libc.bl:53-55 today. It costs more with each FFI binding, and more still once someone applies it to the I/O handles, which B's own principle requires.
  >
  > **To Min specifically.** You wrote that "a later decision can revisit it with data". Revisiting in the A to B direction later is additive: add `mut self` to Ptr.write, with the warning-first rollout. Going B to A later removes a check, which users see as a rule quietly dropping. Start from the version you can tighten.
  >
  > **To Web, AI/ML, DevOps.** Please adopt the effect/value wording for the spec line, not "the Ptr value does not change". The latter is false for List as well, and PLT will rightly call it inconsistent in review.
  >
  > Vote unchanged: A, with the spec text above.

- **Web/Scripting (debate):**
  > **I move from A to B.**
  >
  > **To Min and PLT: you are right, and my own reasoning fails.** I wrote that a Ptr write changes "anything reachable" rather than "this name's storage". But a `List` binding is also a handle, and `push` also changes a heap cell reachable through the handle, not the handle itself. My test does not separate Ptr from List. So under V6 and PLT's :320 text ("`mut` marks where a mutation starts"), `Ptr.write` is the same case as `List.push`.
  >
  > **To Sys.** Your laundering argument (`p.offset(1).write(x)`, where the call result counts as fresh) applies equally to List (`id(a).push(1)`). The panel already accepted that limit for collections, with PLT's :320 text naming it. So it is not a reason to treat Ptr differently. The owner split (Blink-owned vs foreign) is real, but a user does not learn a rule by who owns the memory. They learn "`.write` changed something, so the name needs `mut`".
  >
  > **To AI/ML and DevOps.** Every A vote, mine included, came with the same concern: "the spec must state the Ptr exception in one line." That is the tell. For my domain, a rule that needs a footnote is a rule that generates Stack Overflow questions ("why does `p.write` work on a plain `let` when `sb.write` doesn't?"). Having `.write` on two types follow two rules makes it worse. AI/ML, Rust's model does not carry over. In Rust the capability sits in the pointer TYPE (`*mut T` vs `*const T`). Blink rejected a type split 5-0, so the binding is the only place a mark can go.
  >
  > **Cost.** 3 sites (lib/std/libc.bl:53-55) need a `mut` root, and each comes with a machine-applicable fix (Q8). FFI authors are a small minority of users. The 90% user gets one rule with no exceptions, and hover on `.write` shows `mut self` the same way on every type.
  >
  > **Remaining concern.** FFI code with many pointers gets more `mut`. If that proves painful, revisit it with data, as Min says. A later relaxation is cheap. Removing an exception once users rely on it is not.

- **PLT (debate):**
  > **I move to A.**
  >
  > **To Sys: your laundering point decides it, and here is the precise version.** For List, the rooted rule is a lexical marker on the usual mutation site, and bypasses need deliberate work (`id(a)`, `outer.get(0).unwrap()`). For Ptr, the bypass IS the usual idiom. `p.offset(i).write(x)` has a call result as its receiver, not a rooted place. So under B we must choose between two things:
  > - reject a temporary receiver, which forces `let mut q = p.offset(i); q.write(x)` on every indexed write, or
  > - allow it, which leaves `p.write(x)` needing `mut` while `p.offset(0).write(x)` does not.
  >
  > The first is noise with no meaning, and the second is an incoherent marker. A rule that is vacuous in the common case is worse than an honest boundary. I voted B on uniformity, but a uniform rule that guards nothing is not a principled one.
  >
  > **To Min: my own objection dissolves under V6.** I argued that A puts back a name-based exception. It does not. V6 says a method is mutating if and only if its signature declares `mut self`. Under A, `Ptr.write` simply does not declare it. That is a choice in the stdlib signature, not a footnote in the rule. The rule stays one line, and the spec only has to say why the stdlib makes that choice.
  >
  > **To Web and AI/ML: the right precedent is Rust's type, not C's const.** Rust puts pointer mutability in the TYPE (`*const T` vs `*mut T`), not on the binding, because a raw pointer's permission comes from where it came from, not from which name holds it. Blink's `mut` is a binding marker for Blink-managed cells. Foreign memory sits behind the `@trusted` boundary (W0310), and the checker makes no claims about it. So A is the principled line, not merely the convenient one. If Blink ever needs pointer write permission, it belongs in a `Ptr`/`ConstPtr` type split in v2, not in `let mut`.
  >
  > **Spec text I want with A** (next to V6 in 03_types.md §3.2.2): "`mut` governs storage that Blink manages: List, Map, Set and StringBuilder. A `Ptr` write changes foreign memory, which the `@trusted` boundary governs, so `Ptr` write methods do not declare `mut self`." The spec should state this boundary in one sentence, not leave users to infer it from an exemption.
  >
  > **To Min:** your "revisit with data" still applies, pointed the other way. If typed pointer permissions become necessary, the type split is the tool for it, and `let mut` should not be pressed into that role.

- **DevOps (debate):**
  > **I MOVE from A to B.** Min and PLT are right, and my own Phase C reasoning does not hold up.
  >
  > **To Web and AI/ML ("it changes foreign memory, not the binding").** The same is true of List. `a` is a `blink_list*`. `a.push(1)` changes the heap cell, not the pointer, and we still require `let mut a`: that is §3.2.2, 5-0. Q1-A (V10) redefined `mut` as "marks where a mutation starts", not "this name's storage changes". Under that definition, a `Ptr` write starts a mutation exactly as a push does. The Rust precedent does not carry over. Rust exempts `*mut T` because `Vec` has ownership and a raw pointer does not. Blink has no ownership, so List and Ptr sit on the same side of that line.
  >
  > **To Sys ("laundered in one call").** `p.offset(1).write(x)` launders exactly as `id(a).push(1)` does for List. A call result has no root name under V4. So the laundering argument applies to every handle type, and we accepted it for List in Q3 and V4. It is not a reason to exempt only Ptr.
  >
  > **My own Phase C claim was wrong.** I said B makes lib/std/libc.bl:53-55 fail "with an error that points at the wrong thing". It does not. Under V4 the span lands on the root `cell`, and the fix-it is "declare `let mut cell`" at its `let` line. That is the right place and a one-token fix.
  >
  > **The tooling argument now favors B:**
  > - Under V6 with no footnote, every mutating-call error has one explanation: "`write` declares `mut self`", with a related span on the declaration. Hover shows it, `blink query` shows it, and the error text needs no special case.
  > - Under A, the tools must explain why `p.write(x)` on a plain `let` is fine while `xs.push(x)` is not. That explanation lives only in docs, which is the kind of hidden name list V6 was voted in to remove.
  > - A models-and-users trap that has no diagnostic is worse than a small `mut` cost that does.
  >
  > **Cost, for the record.** There are 3 lib/std sites, all one-token `let mut` edits, and the Q8-A warning-first rollout gives external FFI code one release plus `blink fix`. If FFI-heavy code turns out noisy, Min's point stands: revisit it with data, and do not start with an exception.
  >
  > **Concern with B.** FFI authors coming from C (`T* const p`) and Rust (`*mut T`) will expect a write through an immutable pointer to compile. So the `MutationRequiresMut` explain text needs one Ptr example that says why.

- **AI/ML (debate):**
  > **I move from A to B.**
  >
  > **To Min and PLT: you are right, and my own reasoning was wrong.** I wrote that "`mut` on a binding means the value behind that name changes; a Ptr write changes foreign memory, not the Ptr value". By that test `push` is not mutating either: a List binding holds a pointer to a shared cell, and `push` changes the cell, not the pointer. In round 1 and Q1 I voted for "`mut` marks where a mutation starts", and a Ptr write starts one. My A vote contradicted my own Q1 vote.
  >
  > **The AI/ML test decides it.** My concern line under A already asked for "a one-line Ptr exception next to V6". An exception that needs its own line is a fact a model must memorize, with no signal in the code. That is exactly the hidden name list I argued against in Q4 (StringBuilder). Under B, a model applies one rule with no footnote: `blink query --fn write` shows `mut self`, and the fix-it says "declare `let mut p`".
  >
  > **To Sys (laundering through `p.offset(1).write(x)`).** True, but it is not Ptr-specific. `make_list().push(x)` is the same shape for a List, and we accepted that in Q1 and Q3: `mut` marks where a mutation starts in the text; it does not guard storage. A bypass that every handle type shares is no reason to exempt one of them. On C's `int *const p`: C's `const` there is about the pointer variable, and Blink deleted the `const` sentence from :320 because `mut` is not C `const`.
  >
  > **To Web ("this name's storage" vs "anything reachable").** V4 already made `mut` reach one hop past the name (`p.xs.push` needs `mut p`). "Storage reached through this name" is the rule we voted, and a Ptr fits it.
  >
  > **To DevOps ("error points at the wrong thing").** The error points at the root binding, with a one-token fix, the same as for `xs.push`. Measured cost: 3 sites (libc.bl:53-55). Q8 gives external FFI code a warning release with `blink fix`.
  >
  > **On Rust.** My Rust analogy was weak. Rust encodes the permission in the pointer type (`*mut T` vs `*const T`), so the mark still exists in the text. Blink has one `Ptr` type, so the only place to put the mark is the root, as for every other handle.
  >
  > Remaining concern with B: FFI-heavy code gets more `let mut`. If that proves noisy, revisit it with data (Min).

- **Minimalism (debate):**
  > I hold B. The stakes are low, and I will accept A without protest if it wins. But three of the four arguments for A also apply to List, which we did not exempt.
  >
  > **To Sys (laundering)**
  >
  > `p.offset(1).write(x)` launders the rule in one call. But `xs.clone().push(1)` launders it for List in the same way: `clone()` shares storage (Web's side finding), and the receiver is a fresh call result.
  >
  > We accepted that in round 2. The adopted :320 text says `mut` marks where a mutation starts lexically, not what it reaches. So laundering does not tell Ptr apart from List. If it were a reason to exempt Ptr, it would be a reason to exempt List too.
  >
  > **To Web and AI/ML ("mut means this name's storage changes")**
  >
  > That is not the definition we voted for. `xs.push(1)` does not change the value of `xs`. The pointer stays the same; the shared cell changes. `p.write(v)` has exactly that shape.
  >
  > Web's `int *const p` analogy applies equally to `blink_list* const`, and Sys used that fact in Phase A to delete the `const` sentence. Under the adopted text, "anything reachable" is already what `mut` means for List. Ptr is not a stretch of the rule; it is the same case.
  >
  > **To AI/ML (Rust precedent)**
  >
  > This is the strongest point for A. Rust's raw-pointer write needs no `mut` binding. But Rust exempts raw pointers because they sit outside its borrow checker. Blink has no borrow checker, and its `mut` rule is lexical for every type. The Rust exemption has no counterpart here.
  >
  > **To everyone (consistency with Q6, decided 6-0)**
  >
  > Q6 says: "declare `mut` on any param the foreign code mutates." So `sb_write(mut sb: StringBuilder, ...)` declares `mut`, while under A `Ptr.write(self, ...)` does not. That puts two opposite conventions into one FFI layer. A reader of `libc.bl` would see `mut` on one foreign mutation and not on the next.
  >
  > **To DevOps (error points at the wrong thing)**
  >
  > Under V4 the error lands on `cell`, the root of `cell.fd.write(...)`, with the fix "declare `let mut cell`". That is the right line, and it is a one-token edit, 3 times in the tree.
  >
  > **Summary**
  >
  > A needs a footnote in the spec. B needs none.
  >
  > If A wins, the footnote must be one line next to V6 and must name Ptr exactly: "`Ptr` write methods do not declare `mut self`; FFI memory is outside the `mut` rule." It must not be a general "foreign memory" carve-out that the next type can grow into.

**Re-vote: 6-0 for A** (Ptr writes do not declare `mut self`). The round 1 tally was 4-2 for A; the round 2 tally is 6-0 for A. Web, DevOps and AI/ML moved back to A after Systems' argument about sockets, files and databases. Minimalism moved from B to A. PLT moved to A in the debate and stayed.

- **Systems (re-vote):**
  > 1. **Vote:** A
  >
  > 2. **Reasoning:**
  >    - No Phase D reply answered the point that decides this: under B's principle, `TcpConn.write`, file writes and `db.exec` start mutations of state outside Blink too, and nothing in B stops `mut self` from spreading to every I/O handle. That duplicates the `!` effect row as a second, weaker effect system.
  >    - PLT's version of the laundering point also stands. For Ptr, the temporary receiver `p.offset(i).write(x)` is the normal indexed-write idiom, not a deliberate workaround. So B is either noise on every indexed write, or a marker that `p.offset(0)` skips.
  >    - Min's Q6 point is consistent with A under the value/effect line. `sb_write(mut sb: ...)` mutates a Blink-owned StringBuilder value, which is value state. A Ptr write changes foreign memory, which is effect state.
  >    - The spec line should name the boundary (Blink-managed value state vs foreign state behind `@trusted` and effects), per PLT's wording. Min's worry about a carve-out that grows is answered by naming Ptr exactly.
  >
  > 3. **Concern:** if B wins, the next vote will have to decide whether I/O handles (sockets, files, DB connections) need `mut self` under the same "mutation starts here" principle. B gives no rule to say no, so `let mut` risks turning into an effect marker.

- **Web/Scripting (re-vote):**
  > 1. **Vote:** A. I move back from my Phase D reply, for a reason that reply did not address.
  >
  > 2. **Reasoning:** Sys's stopping-point argument decides it for my domain. If "`Ptr.write` starts a mutation, so it needs `mut self`" holds, then `TcpConn.write`, file writes and `db.exec` need it too. Every web handler would then need `let mut conn` and `let mut db`, which JS and Python developers would reject on first contact. The effect row already tracks that I/O, so the mark would say nothing new. PLT's point adds to this: for `Ptr`, the common idiom `p.offset(i).write(x)` has a call result as receiver, so B guards nothing in the usual case, where for List the bypass is rare. I vote A with Sys's value/effect wording for the spec line. `mut` covers state Blink models as a value (List, Map, Set, StringBuilder), and changes to outside state are effects. I do not accept "the Ptr value does not change", which Min correctly showed is false for List too.
  >
  > 3. **Concern:** The value/effect line must be one clear sentence next to V6, with `Ptr` and I/O handles named as examples. Without that, users will read `p.write(x)` on a plain `let` as an unexplained exception, which is Min's footnote objection.

- **PLT (re-vote):**
  > 1. **Vote: A.**
  >
  > 2. **Reasoning.** Sys's value/effect line is the principled boundary, and B has no stopping point short of it. B's own principle ("`mut` marks where a mutation starts, whoever owns the memory") equally requires `mut self` on `TcpConn.write` (lib/std/net_tcp.bl:15), file writes and `db.exec`. That would make `mut` a second, weaker effect system beside `!`. So B needs a footnote too, drawn between Ptr and TcpConn, and that line is arbitrary.
  >
  >    The rule under A is: `mut` governs state the language models as a value (List, Map, Set, StringBuilder). Changes to foreign state are effects, governed by the effect row and the `@trusted` boundary. This also answers Min's Q6 point: `sb_write(mut sb: StringBuilder)` is `mut` because StringBuilder is a Blink value, on the value side of the line.
  >
  >    The measured idiom also shows B's marker lands on the wrong name. libc.bl:52-55 is `let cell = buf.offset(i)` followed by `cell.fd.write(...)`, so B would require `let mut cell`, a derived alias. The name `buf` that owns the memory stays unmarked. Pointer indexing always goes through such an alias, so under B the mark is off target in the normal case, not only in rare ones.
  >
  > 3. **Concern.** The spec line must state the value/effect test, not "the Ptr value does not change". The second wording is false for List, and a later type will grow an exemption from the vaguer text.

- **DevOps (re-vote):**
  > 1. **Vote: A**, with Sys's value/effect wording and PLT's spec sentence, not "the Ptr value does not change". I move back from my Phase D reply (B). Sys's and PLT's Phase D arguments are new, and they beat the ones I conceded.
  >
  > 2. **Reasoning:**
  >    - The only real Ptr idiom in the tree is lib/std/libc.bl:52-55: `let cell = buf.offset(i)`, then `cell.fd.write(...)`. Under B, the one-expression form `buf.offset(i).fd.write(...)` has a call-result root and passes. So B gives an error with a one-line bypass on the most common Ptr shape. I voted against exactly that in Q3, because such an error teaches the bypass and not the model (PLT's point).
  >    - Sys's stopping point decides the tooling question. B's principle also reaches `TcpConn.write(self, ...)` (net_tcp.bl:15), file writes and DB handles, and it gives no stopping point short of `let mut` on every I/O handle.
  >    - A splits the tools cleanly. Hover on `mut self` means "changes a Blink value". Hover on `! IO` or `@trusted` means "changes the outside world". That split is also consistent with Q6: `sb_write(mut sb: StringBuilder)` marks a Blink value, so it takes `mut`.
  >
  > 3. **Concern:** the spec line must state the value/effect boundary in one sentence next to V6, and the `MutationRequiresMut` explain text needs a Ptr example that says why no `mut` is needed. Without them, FFI users will file "why does `p.write` compile on a plain `let`?" as a bug.

- **AI/ML (re-vote):**
  > 1. **Vote: A.** This moves me back from my Phase D reply (B). My Phase C reasoning ("the Ptr value does not change") stays withdrawn. I vote A on Sys's and PLT's reasons, not on my own.
  >
  > 2. **Reasoning.**
  >    - **Predictability.** PLT's point is the one I used for Q2. Under B, `p.write(x)` needs `let mut p`, but `p.offset(i).write(x)` does not, because the call result has no root. The indexed form is the usual FFI idiom. A model cannot predict when the rule fires, so it learns it by trial and error.
  >    - **A clear stopping point.** Sys's line is one a model can learn from the spec alone: `mut` covers Blink-managed values (List, Map, Set, StringBuilder), and changes to the outside world (Ptr memory, sockets, files, DBs) are effects that the effect row and `@trusted` track. B's principle has no stopping point short of `mut self` on `TcpConn.write`.
  >    - **Q6 stays consistent.** Under this line, `sb_write(mut sb: StringBuilder)` marks a Blink value, and `Ptr.write` does not, which answers Min's point.
  >
  > 3. **Concern.** The spec line must be the general value/effect sentence (Sys, PLT), not a Ptr-only footnote. Otherwise models will see `sb.write` and `p.write` follow different rules with no stated principle, and will guess wrong on the next foreign-handle type.

- **Minimalism (re-vote):**
  > **1. Vote**
  >
  > A. I move from B.
  >
  > **2. Reasoning**
  >
  > Sys's TcpConn argument decides it for me.
  >
  > - My B principle, "no exception for who owns the memory", has no stopping point short of `mut self` on every socket, file and DB handle. `lib/std/net_tcp.bl:15` already declares `fn write(self, data: Str)`.
  > - Taken that far, `mut` becomes a second, weaker effect system that overlaps `!` effects and the `@trusted` boundary. Two mechanisms for one concern is the thing my lens exists to stop, and it costs more than a one-line boundary.
  > - Sys's value/effect line is not a name list. `mut` covers state that Blink models as a value (List, Map, Set, StringBuilder contents). Effects cover state outside the language. Under V6 it is a stdlib signature choice, stated once.
  > - Sys's direction point also holds. A to B later is additive, with the Q8 rollout. B to A later removes a check that users already rely on.
  >
  > **3. Concern**
  >
  > A wins only if the spec states Sys's value/effect wording next to V6, not "the Ptr value does not change". The latter is false for List too, and it will make the boundary look arbitrary and reopen this debate.
  >
  > Also, for the record: PLT's claim that `p.offset(i).write(x)` is the common idiom has no support in the tree. There are 0 `.offset(...).write` sites in lib/std or src. The case for A rests on the effect overlap, not on laundering.

**Condition carried by the vote.** The spec states the value/effect line: `mut` covers state that Blink holds as a value (List, Map, Set, StringBuilder contents). Ptr memory, sockets, files and databases are effects. The spec must not say "the Ptr value does not change", because that is also true of a List handle. The `MutationRequiresMut` explain text needs a Ptr example.

### Final Spec

```blink
type Server {
    routes: List[Route]
}

fn add_route(mut srv: Server, r: Route) {
    srv.routes.push(r)
}

type Counter {
    items: List[Int]
}

impl Counter {
    fn add(mut self, v: Int) {
        self.items.push(v)
    }
}

trait Display {
    fn fmt(self, mut sb: StringBuilder)
}

fn next_count(n: Int) -> Int {
    let mut m = n
    m = m + 1
    m
}
```

- **Q1:** A parameter is immutable unless it is declared `mut` (`mut self` is allowed). A mutating call needs a mutable root, for lets and params alike: `p.xs.push` needs `mut p`. A method is mutating if and only if it declares `mut self`. This replaces the name list. `mut` is erased in function types, and the spec states the higher-order hole. `warning[UnusedMut]` judges use, not type. The rationale in §3.2.2 is rewritten, and the `const` sentence is deleted. The rebind idiom uses a new name (`let mut m = n`), not a shadow (W0603).
- **Q2:** Assigning to a parameter, or to a field of a parameter, is always an error, with or without `mut`. `self` is included. Use a functional or struct-update form to build a new value.
- **Q3:** No argument rule. `warning[MutAliasOfImmutable]` fires on direct aliases only: an argument to a `mut` param from a non-mut root, and `let mut b = a`. The spec does not claim that an immutable `let` never changes.
- **Q4:** The `StringBuilder` `write*` methods declare `mut self`. `Display.fmt` is `fmt(self, mut sb: StringBuilder)`.
- **Q5:** An impl may drop `mut` but not add it (`ImplAddsMut`). `UnusedMut` does not fire on a `mut` kept to mirror the trait.
- **Q6:** `@ffi` params carry `mut` by declaration only. The compiler does not check it. `UnusedMut` never fires on them.
- **Q7:** Ptr writes do not declare `mut self`. The spec states the value/effect line: `mut` covers state Blink holds as a value; Ptr memory, sockets, files and databases are effects.
- **Q8:** Each new error ships first as a warning with a `blink fix` machine fix. It becomes an error one release later, with a fixed end release.
- **Spec files:** `sections/03_types.md` (§3.2.2 Construction and Mutability, §3.6 Mutable Parameters), `sections/02_syntax.md` (Bindings row), `sections/04_effects.md` (§4.16 table row), `sections/07_trust_modules_metadata.md` (Ptr `.write` row).
