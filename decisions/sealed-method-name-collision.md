[< All Decisions](../DECISIONS.md)

# Sealed Method Name Collision — Design Rationale

The question: a user trait gives a built-in type a method whose name a sealed built-in trait already uses, for example `trait Tidy { fn trim(self) -> Str }` with `impl Tidy for Str`. What does `text.trim()` call? The compiler let the built-in win without a diagnostic, in both type checking and code generation. It already reported E0522 for a `List` receiver, but only for six higher-order method names. §3c.4 said the built-in surfaces are trait-based at spec level, and that adding a trait impl can only cause ambiguity errors, never silent behavior changes.

Panelist text below is verbatim. Local tracker IDs are replaced by bracketed descriptions. Some Phase A replies were cut off when they were relayed; `[…]` marks the cut, and each panelist's own last line, sent again in Phase B, follows it.

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in independent-proposal → debate → vote rounds. Q2 split 3-3 in Phase C, so it went to a Phase D debate and re-vote.

#### Phase A — Independent proposals

**Systems:**

> Panel response (Systems):
>
> ## Systems expert, Phase A proposals
>
> All three options cost the same at runtime. Resolution is static in every case. `StrOps.trim(s)` lowers to a direct call to `str_trim`, and `Tidy.trim(s)` lowers to a direct call to the user function. No vtable is involved and the emitted code is the same. The real question is which choice keeps codegen **predictable**: can the reader tell from the source which C function runs? Silent builtin-wins fails that test.
>
> ### Proposal 1 (favoured): sealed surface counts as one owner in lookup, E0522 on every built-in receiver
>
> In §3c.4 lookup, the sealed surface of a built-in receiver counts as one more trait that defines the method. A user trait method with the same name gives 2 matches, so the call fails with E0522. This rule covers Str, Bytes, StringBuilder, List (all names, not only the six HOFs), Map, Set and Iterator.
>
> ```blink
> trait Tidy { fn trim(self) -> Str }
> impl Tidy for Str { fn trim(self) -> Str { "X" } }   // OK: orphan rule allows it
>
> fn main() ! IO {
>     let text = "  hi  "
>     let a = text.trim()          // error
>     let b = StrOps.trim(text)    // "hi", direct call to the builtin
>     let c = Tidy.trim(text)      // "X", direct call to the user impl
>     io.println(b + c)
> }
> ```
> ```
> error[AmbiguousMethodCall]: ambiguous method call `trim` on Str
>   --> main.bl:5:20
>    |  `trim` is defined by StrOps (built-in) and by Tidy
> help: write StrOps.trim(text) or Tidy.trim(text)
> ```
>
> **Tradeoffs**
> - It follows the 5-0 rule (error at the call site, not the impl site) and the §3c.4 promise that adding an impl only gives loud errors. No new concept is added; the sealed surface is just one more owner.
> - **Language growth is the case that decides it.** Say v1.4 adds `StrOps.pad` and a user already has `trait Fmt { fn pad(self) }` for Str. Under builtin-wins, `text.pad()` quietly starts calling a different function after the upgrade: same source, different machine code, no diagnostic. That is the worst kind of change for a systems user. Under Proposal 1 the upgrade gives E0522 with a fix-it, and `blink upgrade` can rewrite the call to the qualified form mechanically.
> - Compile-time cost is one extra lookup in the user-impl table per method call on a built-in receiver. That is small.
> - It removes today's inconsistency: the List HOFs already behave this way, and the other receivers do not.
> - Cost to users: once a user defines `trim` for Str, every unqualified `.trim()` on Str is an error. That is the price of a colliding name, and the diagnostic states it.
>
> ### Proposal 2: error at the impl site
>
> A user trait method whose name matches a sealed method on that receiver is rejected at the `impl` with a new E-code.
>
> - Pro: the collision is found in one place, early.
> - Con: this goes against the 5-0 composability decision. It also blocks code that would only ever use the qualified form.
> - Con: on language growth it breaks the *impl* in a downstream package that the user may not own. Proposal 1 breaks only the user's own call sites. Rejected.
>
> ### Proposal 3: builtin wins silently (today's behaviour)
>
> Rejected. It breaks the §3c.4 rationale word for word ("never silent behavior changes"). The user impl can only be reached by a spelling that nobody has a reason to guess. It also turns every future StrOps addition into a possible silent miscompile of existing programs.
>
> ### Add-on to Proposal 1 (optional): warning at the impl site
>
> The impl gets a warning such as "`Tidy.trim` shares a name with built-in `StrOps.trim`; unqualified `.trim()` on Str will be ambiguous". It is suppressible with `@allow`. It is never an error, so it does not reopen the 5-0 decision.
>
> ### Cross-language note
>
> - **Rust**: an inherent method beats a trait method, which is how Rust gets silent shadowing. Blink has no inherent methods, and the reason it gave them up was to avoid this exact problem.
> - **Rust**: two traits that define the same method name give E0034, with `<T as Trait>::m` as the fix. Proposa
> […]

*Last line of the proposal, as sent again in Phase B:*

> **I favour Proposal 1, applied the same way on every built-in receiver, with the optional impl-site warning.**

**Web/Scripting:**

> # Web/Scripting panelist: Phase A proposal for [this ticket]
>
> **I favour Proposal A.**
>
> ## Proposal A: the sealed surface counts as a trait, so a clash is E0522 at the call site and a warning at the impl
>
> ```blink
> trait Tidy { fn trim(self) -> Str }
> impl Tidy for Str { fn trim(self) -> Str { "X" } }
> // warning[W-new] ShadowsBuiltinMethod: `trim` matches built-in StrOps.trim on Str
> //   = note: every unqualified `.trim()` on a Str where Tidy is in scope is now ambiguous
> //   = help: rename it, or callers must write `Tidy.trim(s)`
>
> fn main() ! IO {
>     let text = "  hi  "
>     let a = text.trim()         // error[E0522] AmbiguousMethodCall: `trim` is in StrOps and Tidy
>                                 //   = help: write `StrOps.trim(text)` or `Tidy.trim(text)`
>     let b = StrOps.trim(text)   // ok, built-in
>     let c = Tidy.trim(text)     // ok, user impl
>     io.println(b)
> }
> ```
>
> Rules:
> - The sealed surface (StrOps, ListOps, Sized and the rest) enters §3c.4 lookup as one owner, the same as any other trait. Two owners produce E0522. This changes no existing rule. It only stops the compiler from skipping the user's trait.
> - The same rule covers every built-in receiver and every sealed method. The special case for the six List HOFs goes away, because they become one example of the general rule.
> - The impl site gets a warning, not an error. The author learns about the clash when they write the impl, not when a consumer files a bug.
> - When a release adds a new sealed method, for example `StrOps.slugify`, the user's `Slug.slugify` impl gets the warning, and each unqualified call gets E0522 with a fix you can apply by machine (`blink fix` rewrites it to the qualified form). The upgrade fails loudly at a known spot and never changes behaviour silently.
>
> **Tradeoffs (DX):**
> - A Python or JS developer reads "ambiguous: trim is in StrOps and Tidy" and knows what to do inside 5 minutes. The hint shows both spellings.
> - It keeps the promise in §3c.4: "adding a trait impl can only cause ambiguity errors, never silent behavior changes." Today's builtin-wins rule breaks that promise for exactly the receivers people use most.
> - Cost: one impl can make `.trim()` ambiguous in every file that has Tidy in scope. That is noisy, and it is why the impl-site warning matters. The scope part depends on [the open impl-scope question].
>
> **Cross-language:**
> - Rust lets an inherent `str::trim` silently shadow a trait `trim`, and Clippy needs a `same_name_method` lint to catch it.
> - Kotlin lets a member silently beat an extension and only warns "extension is shadowed by a member".
> - JS monkeypatching led to "smooshgate", where new built-ins broke deployed code.
>
> All three show what silent shadowing costs. Blink should not copy it.
>
> ## Proposal B: error at the impl site
>
> ```blink
> impl Tidy for Str { fn trim(self) -> Str { "X" } }
> // error[E-new] ImplCollidesWithBuiltin: Str already has `trim` from sealed StrOps
> ```
>
> This is the simplest model ("you can't reuse a built-in name on a built-in type"), and it gives few Stack Overflow questions on day one. But:
> - It contradicts the 5-0 decision that collisions are a call-site matter.
> - It turns every new sealed method into a hard break for libraries. A package that defines `slugify` on Str stops compiling for all its consumers, and they cannot fix it, because the error is in someone else's code.
> - For an ecosystem that wants to grow StrOps and ListOps, this is the worst upgrade story of the three.
>
> ## Proposal C (rejected): keep builtin-wins silently
>
> - It produces a top-10 Stack Overflow question: "why is my trim never called?"
> - It is undetectable without reading the spec.
> - It already disagrees with how List behaves today.
>
> ## Summary
>
> Treat the sealed surface as one ordinary trait owner, use E0522 at call sites with a fix you can apply by machine, and warn at the impl. Apply it to every built-in receiver.

**PLT:**

> **PLT panelist: Phase A proposals for [this ticket]**
>
> **Framing.** §3c.4 says the built-in method surfaces are "trait-based at spec level" and calls hardcoded dispatch "an implementation shortcut." If we take that at its word, this is not a new question. `StrOps.trim` and `Tidy.trim` are two traits that both define `trim` for `Str`. The existing 5-0 rule already gives the answer: E0522 at the call site. The other two options make the sealed traits a special priority tier, which the spec says they are not.
>
> ---
>
> **Proposal A (favoured): the sealed surface counts as an ordinary ambiguity owner, on every built-in receiver**
>
> ```blink
> trait Tidy { fn trim(self) -> Str }
> impl Tidy for Str { fn trim(self) -> Str { "X" } }   // OK: orphan rule allows it
>
> fn main() ! IO {
>     let text = "  hi  "
>     let a = text.trim()          // ERROR E0522
>     let b = StrOps.trim(text)    // OK: "hi"
>     let c = Tidy.trim(text)      // OK: "X"
> }
>
> fn g[T: Tidy](x: T) -> Str { x.trim() }   // OK: resolves to Tidy.trim, also when T = Str
> ```
>
> ```
> error[AmbiguousMethodCall]: ambiguous method call
>  --> tidy.bl:6:18
>   |
> 6 |     let a = text.trim()
>   |                  ^^^^ method `trim` found in multiple traits
>   = note: `trim` is defined in both `StrOps` (built-in) and `Tidy`
>   = help: StrOps.trim(text)
>   |       Tidy.trim(text)
> ```
>
> Typing rule: let `M(τ, m)` be the set of in-scope traits that give `τ` a method `m`, with the prelude's sealed traits always in that set. If `|M| = 1`, the call resolves to that trait. If `|M| = 0`, it is an error. If `|M| ≥ 2`, it is E0522. No trait ranks above another. This turns the List-HOF special case into the general rule for every name on every built-in receiver: Str, Bytes, StringBuilder, List, Map, Set, Iterator, and the multi-receiver traits Sized and Contains.
>
> **Soundness point the brief does not raise.** In `g[T: Tidy]`, the call `x.trim()` resolves against T's bounds, so it must mean `Tidy.trim`. Monomorphisation must carry the resolved trait into the instance and must never look the method up again by name. If it does, `g[Str]` silently calls the built-in `str_trim`, and `g` behaves differently at `Str` than at every other type. That breaks parametricity. It is the dictionary-passing guarantee we get for free in Haskell and OCaml, and builtin-wins with name-based codegen breaks it. The rule must say this, and a test must pin it.
>
> **When the language adds a method later.** A user ships `impl Shout for Str { fn shout ... }` and calls `s.shout()`. A later release adds `StrOps.shout`.
> - Under A, `s.shout()` becomes a loud E0522 error. `Shout.shout(s)` fixes it, and code inside generic functions keeps working. This is exactly the behaviour §3c.4 promises: "only ambiguity errors, never silent behavior changes."
> - Under builtin-wins, the program changes behaviour silently. That directly breaks the stated reason for having no inherent methods.
> - Under an impl-site error, the user's impl stops compiling, along with every package that depends on the `Shout` API. The only fix is to rename a public trait method. That is the most breaking choice, and it is the composability failure the 5-0 vote rejected.
>
> **Tradeoffs.**
> - The error falls on the user's code even though the language caused the collision. That is unavoidable in an open world (Rust's inherent-versus-trait problem has the same shape), and it is loud and fixable.
> - A cost on the implementation side: typecheck must collect the sealed method names per receiver as data, not as arms checked before user impls. That is the correct design anyway.
>
> ---
>
> **Proposal B (add-on to A, weakly favoured): a warning at the impl site**
>
> ```
> warning[ImplShadowsBuiltinMethod]: `Tidy.trim` has the same name as built-in `StrOps.trim` on `Str`
>   = note: unqualified `.trim()` on a `Str` will be ambiguous (E0522)
> ```
>
> This warning is diagnostic only and has no effect on semantics. It tells the author, before any call exists, that unqualified calls to this name will be ambiguous. On a langua
> […]

*Last line of the proposal, as sent again in Phase B:*

> **My position:** A, with the requirement that mono keeps the trait it resolved. B as an optional addition.

**DevOps:**

> **DEVOPS / TOOLING — Phase A proposals for [this ticket]**
>
> The panel should judge this by one case: **the language adds a new sealed method in release N+1, and that method collides with a user trait method that already ships.** Each option makes the compiler say something different at that moment.
>
> **Proposal 1 (FAVOURED): the sealed surface counts as one ambiguity owner, reported as E0522 at the call site. The impl site gets a warning.**
>
> ```blink
> trait Tidy { fn trim(self) -> Str }
> impl Tidy for Str { fn trim(self) -> Str { "X" } }   // W: see below
>
> let a = text.trim()          // error[AmbiguousMethodCall]
> let b = Tidy.trim(text)      // OK: "X"
> let c = StrOps.trim(text)    // OK: built-in trim
> ```
> ```
> error[AmbiguousMethodCall]: ambiguous method call
>  --> app.bl:4:14
>   |
> 4 | let a = text.trim()
>   |              ^^^^ method `trim` found in multiple traits
>   = note: `trim` is a built-in `StrOps` method and is also defined by `Tidy`
>   = help: use qualified syntax:
>   |   StrOps.trim(text)
>   |   Tidy.trim(text)
>
> warning[BuiltinMethodNameCollision]: `Tidy.trim` has the same name as built-in `StrOps.trim` on `Str`
>  --> app.bl:2:22
>   = note: every unqualified `.trim()` call on a `Str` becomes ambiguous
>   = help: rename the method, or call it as `Tidy.trim(x)`
> ```
>
> - **Consistent with the rules we have.** This is §3c.4 rule 3 applied as written: the sealed traits are "trait-based at spec level", so `StrOps` is one more trait with `trim`. The compiler already does this for the six List HOFs, and this proposal makes every built-in receiver behave the same way. No new concept to teach.
> - **Upgrade story.** When `StrOps` gains `pad`, every user `.pad()` call on a `Str` fails loudly with a mechanical fix. That matches the stated §3c.4 rationale ("ambiguity errors … never silent behavior changes"). The LSP offers a code action, "Qualify as `Tidy.pad(x)`", and a `blink fix` pass can apply it across a whole package on upgrade, like `go fix` and `cargo fix`.
> - **LSP completion.** On `text.tr|`, show two entries, `trim — StrOps` and `trim — Tidy`. Accepting the `Tidy` entry inserts the qualified form. Hover on an ambiguous call lists both owners.
> - **Cost.** An upgrade can break a dependency's call sites. To lower that risk, a library lint recommends qualified calls for user-trait methods on built-in receivers.
>
> **Proposal 2: error at the impl site.**
>
> ```
> error[BuiltinMethodCollision]: `Tidy.trim` collides with sealed `StrOps.trim` on `Str`
> ```
> The message is clear but the upgrade story is bad. A compiler upgrade turns a valid impl into a hard error that only a **rename** fixes, and a rename breaks every downstream user of `Tidy`. If a dependency you do not own does this, you have no fix at all. It also contradicts the 5-0 decision that collisions are a call-site problem. I reject it.
>
> **Proposal 3: keep the current behaviour, where the built-in wins with no message.**
>
> This gives no diagnostic, so there is nothing for the LSP to show. The worst case is the upgrade: when `StrOps` gains a method, user code silently switches to the built-in, which is exactly the failure §3c.4 exists to prevent. Hover would say `Tidy.trim` while the program runs `StrOps.trim`, so tooling would report the wrong thing. I reject it.
>
> **Generalisation.** One rule for all sealed surfaces (StrOps, BytesOps, StringBuildOps, Sized, Contains, ListOps, MapOps, SetOps, Joinable, IteratorOps): built-in names join the candidate set for §3c.4 lookup. The same candidate list then drives the diagnostic, the completion entries and the code action, so the three cannot disagree. The current special case for six List HOFs goes away.
>
> **Cross-language.**
> - **C#:** an instance method silently beats an extension method of the same name, which is a known source of behaviour changes on upgrade.
> - **Rust:** inherent methods beat trait methods. When std added `Iterator::intersperse`, it collided with `Itertools::intersperse`, and Rust had to add the `unstable_name_collisions` future-incompat
> […]

*Last line of the proposal, as sent again in Phase B:*

> **Favoured: Proposal 1.** E0522 at the call site, a warning at the impl site, and a quick-fix code action to the qualified form.

**AI/ML:**

> **AI/ML panelist: Phase A proposals for [this ticket]**
>
> **What decides it for me:** an LLM that writes `impl Tidy for Str { fn trim(self) ... }` expects `text.trim()` to call its own impl. Training data from Python, JS and Kotlin extensions teaches that. If the builtin silently wins, the program compiles, runs and is wrong, and nothing in the output tells the model or the human to look. That is the worst failure mode for generated code. §3c.4 already rules it out: "adding a trait impl can only cause ambiguity errors, never silent behavior changes." So silent builtin-wins is out under a binding constraint, not just my preference.
>
> ---
>
> ### Proposal A (favoured): the sealed surface is one more trait at the call site, so E0522 applies everywhere
>
> ```blink
> trait Tidy { fn trim(self) -> Str }
> impl Tidy for Str { fn trim(self) -> Str { "X" } }   // OK, orphan rule allows it
>
> fn main() ! IO {
>     let text = "  hi  "
>     let a = text.trim()          // error[E0522]
>     let b = Tidy.trim(text)      // "X"
>     let c = StrOps.trim(text)    // "hi"
>     io.println(a)
> }
> ```
> ```
> error[E0522]: ambiguous method call `trim` on `Str`
>   --> main.bl:6:18
>    |  candidates: StrOps.trim (built-in, sealed), Tidy.trim (main.bl:2)
>    = help: write `StrOps.trim(text)` or `Tidy.trim(text)`
> ```
>
> - **Generalises:** every sealed surface (StrOps, BytesOps, ListOps, MapOps, SetOps, Sized, Contains, Joinable, StringBuildOps, IteratorOps) counts as one ambiguity owner for every method name. The List case already works this way for six HOFs, so this extends a rule the compiler already has. It does not invent a new one.
> - **Inside a generic bound** (`fn f[T: Tidy](x: T) { x.trim() }`), only Tidy is visible, so the call resolves to Tidy. There is no ambiguity there.
> - **When the language later adds `StrOps.foo`:** user code with `Tidy.foo` gets E0522 at its unqualified calls. That is loud, local, and one mechanical edit fixes it. It is the same outcome as two user traits colliding (the 5-0 decision).
>
> **AI tradeoffs:**
> - There are no new concepts or diagnostics, and no new rule to learn. A model that knows §3c.4 already predicts this behaviour. The spec loses the special case "built-ins skip lookup" and gets simpler.
> - The diagnostic gives the exact fix, and models repair reliably from a concrete `help:` line.
> - Cost: a few extra tokens at the colliding call sites (`Tidy.trim(text)`). That is rare: no file in the corpus does this today.
>
> ### Proposal B (add-on to A): a warning at the impl site
>
> ```
> warning[W05xx]: `Tidy.trim` has the same name as built-in `StrOps.trim` on `Str`
>   --> main.bl:2:28
>    = note: every unqualified `.trim()` on Str in scope of Tidy is ambiguous (E0522)
>    = help: rename the method, or call it as `Tidy.trim(x)`
> ```
>
> This tells the author where the problem starts, before the call-site errors spread. Debugging gets faster: one cause, one location. It is a warning, not an error, so composability stays intact and future growth of the sealed surface does not break builds at the impl site. I support it, but A must ship first. B is only a convenience.
>
> ### Proposal C (rejected): an error at the impl site
>
> This gives the model a single, clear rule ("don't reuse builtin names"), which I like. But it breaks the earlier 5-0 composability decision. Worse, every release that adds a StrOps/ListOps method can turn a valid user trait into a compile error at its declaration. The only fix is to rename the trait method, which spreads to every implementer and every package downstream. LLMs trained on the old release will keep generating the colliding name. The failure is loud but the repair is expensive, and the trigger is outside the user's control.
>
> ### Cross-language note
>
> - Rust: inherent methods silently win. When std adds a method that itertools also has, users end up calling the std one without knowing. Rust needed the `unstable_name_collisions` lint because of this. That is the failure Blink avoids by having no inherent methods.
> - C#: an instance method sil
> […]

*Last line of the proposal, as sent again in Phase B:*

> **Vote intent:** A, with B as a follow-up. Silent builtin-wins and impl-site error both get a no.

**Minimalism:**

> I'm the Minimalism panelist. My Phase A proposal is below.
>
> # Minimalism: Phase A proposal ([this ticket])
>
> ## Favoured: Proposal M1, which needs no new rule
>
> We need no new rule for this. Section §3c.4 already says how it works:
>
> - The sealed surfaces are "trait-based at spec level", so `StrOps` is just another trait that `Str` implements, and it is always in scope.
> - The lookup rule is: one match calls the method, two or more give E0522.
> - So `text.trim()` with `Tidy` in scope has two owners, `StrOps` and `Tidy`, and that is E0522.
>
> The bug is that the compiler skips the spec. The fix takes code away: drop the builtin-first shortcut in typecheck, and fold the six-name List HOF special case into the general rule. It is not a new feature.
>
> ```blink
> trait Tidy { fn trim(self) -> Str }
> impl Tidy for Str { fn trim(self) -> Str { "X" } }   // OK: no impl-site error (5-0 call-site decision)
>
> fn main() ! IO {
>     let text = "  hi  "
>     let a = text.trim()          // error[E0522]: AmbiguousMethodCall: `trim` on Str is defined by
>                                  //   StrOps (built-in) and Tidy
>                                  //   help: write `StrOps.trim(text)` or `Tidy.trim(text)`
>     let b = StrOps.trim(text)    // OK: built-in (already accepted today)
>     let c = Tidy.trim(text)      // OK: user impl
>     let n = text.len()           // OK: only Sized owns `len`
>     io.println("{b}{c}{n}")
> }
> ```
>
> **Inside the impl:** if the `Tidy` body calls `self.trim()`, it is also ambiguous, and the user writes `StrOps.trim(self)`. That is correct: it makes clear which `trim` runs, and it removes the accidental-recursion trap.
>
> **When the language grows:** say release N+1 adds `StrOps.slugify`, and the user already has `Slug.slugify` for `Str`. Their `s.slugify()` calls start to give E0522 with a fix-it hint. That is the same loud, fixable breakage §3c.4 already accepts for any two traits. The two alternatives are both worse:
> - The impl-site error option breaks their *declaration* at once, and the only fix is to rename.
> - The builtin-wins option silently changes what `s.slugify()` does. That is the exact case §3c.4 says can never happen.
>
> **For all receivers:** one rule covers `Str`, `List`, `Map`, `Set`, `Bytes`, `StringBuilder` and `Iterator`, so the per-receiver inconsistency goes away.
>
> **Tradeoffs**
> - (+) It adds no diagnostic, no keyword and no spec paragraph. We only add one clarifying sentence to §3c.4 saying sealed surfaces count as one owner in the lookup. The compiler loses code.
> - (+) It keeps the "never silent" guarantee that justified removing inherent methods.
> - (-) Users who wanted to override builtin behaviour get friction. That is intended: the surface is sealed.
> - (-) A language release can add E0522 errors to user code. A migration tool (`blink fix` writing the qualified form) can deal with that. It is tooling, not language.
>
> ## Rejected options
>
> **M2: keep builtin-wins, document it, maybe warn at the impl.** This is the Kotlin model ("extension is shadowed by member"). It needs a new precedence rule that §3c.4 does not have. It brings back a tier of methods that act like inherent methods, which the 4-1 vote removed. It also leaves a user method that can be declared but never called by dot syntax, which is dead surface. If we choose this, it must at least be a hard error at the impl, but then see M3.
>
> **M3: error at the impl site.** This contradicts the 5-0 call-site decision. It also makes every future sealed-method addition a breaking change to declarations, even for code that never calls the colliding name through dot syntax. It is the most expensive option and it protects nothing that M1 does not.
>
> **"Require the qualified form to reach the impl."** This is not a separate option. It is M2 with an extra rule, and M1 already gives qualified access with no special case.
>
> ## Other languages
>
> - **Rust:** an inherent method silently beats a trait method. Blink removed inherent methods to avoid this. Two clashing trait methods give E
> […]

*Last line of the proposal, as sent again in Phase B:*

> **Vote: M1.** Implement the spec we already have, and delete the List-only special case.

#### Phase A.5 — Dedupe

All six favoured the same main proposal: the sealed surface counts as one ordinary owner in §3c.4 lookup, on every built-in receiver, so a collision is E0522 at the call and a qualified call resolves it. All six rejected an error at the impl and the built-in winning without a diagnostic. Open for Phase B: **V1**, a warning at the impl (Systems, Web, PLT, DevOps and AI/ML proposed it; Minimalism did not); **S1**, PLT's point that monomorphization must keep the trait the type checker chose; Minimalism's point that `self.trim()` inside the impl is E0522; and DevOps's tooling items (LSP code action, `blink fix`, library lint).

#### Phase B — Debate

One round. All six reported stable.

**Systems:**

> **(1) V1, the impl-site warning: weak yes.** It costs nothing at runtime and has no effect on semantics. It tells the impl author about the clash once, where the clash starts. Without it, each caller finds out separately through E0522. I want it suppressible with `@allow`, and I want it listed as a lint, not a rule of the language. That keeps Minimalism's point: the spec defines no new semantics for it. I do not block either way.
>
> **(2) S1: yes, put it in the spec text and pin it with a test.** This is the systems point that matters most. Lookup resolves `x.trim()` once, against T's bounds, to an exact (trait, impl) pair. Monomorphisation copies that pair into the instance and never looks the name up again. If mono looks the name up again with T=Str, it finds the builtin, and the generic body then compiles to different machine code than the checked body described. That is the silent behaviour change Option A exists to prevent. The test should be `fn g[T: Tidy](x: T) -> Str { x.trim() }` called with a Str, and it must give "X".
>
> Other sub-points:
> - Min's `self.trim()` inside the impl body: in, as one example sentence. It follows from Option A and needs no rule of its own.
> - LSP, `blink fix`, `blink upgrade` and the library lint: keep them out of the spec. They are tooling.
>
> **(3) Stable, ready to vote:** A + S1 in the spec, V1 as an optional lint.

**Web/Scripting:**

> # Web/Scripting panelist: Phase B round 1 positions
>
> **(1) V1, the impl-site warning: yes, as a lint.** It should be suppressible with `@allow` and never an error.
>
> The reason is who sees the error and when. Under Option A alone, the author of `impl Tidy for Str` may never write an unqualified `.trim()`. The E0522 then lands in the consumer's code, and the consumer did not cause the clash. The warning moves the first signal to the author, who can rename before publishing.
>
> min's cost is real but small: one lint paragraph and no new semantics. In this case a missing warning gives the user nothing at all.
>
> **(2) Sub-points:**
> - **S1: in, with a test.** In `fn f[T: Tidy](x: T) { x.trim() }`, the call resolves to `Tidy.trim`. That is the answer a Python or TypeScript developer would expect from reading the bound. A monomorphised `f[Str]` that silently switched to `StrOps.trim` would be the exact silent change we just rejected. The spec should say that the resolved trait is fixed at typecheck.
> - **min's `self.trim()` inside the impl body: in, as one example line.** It is not a new rule; it follows from Option A. But it is the first place users will hit E0522, so a worked example saves a pile of forum questions.
> - **devops LSP, code action and library lint: out of the spec.** They are tooling notes for the implementation ticket.
> - **`blink fix` on upgrade: out of the spec.** It is tooling, but I want it named in the decision record as expected follow-up.
>
> **(3) Stable, ready to vote.**

**PLT:**

> (1) **V1 (impl-site warning): weak yes, but keep it apart from the rule.** The warning changes no semantics, so soundness does not depend on it. It tells the author about the clash before any call exists, and it tells them again when a release adds a colliding sealed method. Minimalism has a fair point: the warning also fires for library authors who only ever use the qualified call. So make it a lint that `@allow` can silence. Spec it as non-normative so that it cannot hold back the vote on A. If the panel wants a smaller spec, I will drop it before I split the vote.
>
> (2) **S1 must go into the normative text.** Resolution happens once, at typecheck, against the bounds of a type parameter or the in-scope traits of a concrete type. Monomorphisation keeps the trait it resolved and never looks the method up again by name. Without that sentence, `g[T: Tidy]` at `T = Str` can silently call the built-in `str_trim`. That is the same silent change of behaviour that A exists to stop, moved one layer down. A corpus test must pin it.
>
> **min's point that `self.trim()` in the impl body is ambiguous: include it, with an example.** It follows from A, but implementers will be tempted to prefer the enclosing impl's own trait inside its body. That is a priority rule, the same kind A rejects. The spec should say the body gets no special treatment.
>
> **devops tooling (LSP, `blink fix`, code actions): keep out of the spec.** Those are tooling decisions, not language rules.
>
> (3) **Stable, ready to vote:** A + S1 + the self-in-impl clarification. V1 as an optional, non-normative lint.

**DevOps:**

> **DEVOPS / TOOLING — Phase B round 1**
>
> **(1) V1: yes, I want the warning, and it should be a named lint in the spec.**
> - The author writes the impl once, but the call sites break wherever the method is used. A warning at the impl reaches the one person who can rename the method at no cost, before anyone calls it.
> - It must stay a warning, never an error. A language upgrade will also trigger it on code that already ships, and that must not break a build.
> - It is suppressible with `@allow(BuiltinMethodNameCollision)` and has no effect on semantics.
> - To answer min: yes, it adds one diagnostic. If the spec does not name it, the LSP, `blink check` and CI will each word it in their own way. One named lint in the spec costs less than three versions in tools.
>
> **(2) Sub-points:**
> - **S1: in the spec, with a test.** It also binds tooling. Hover and go-to-definition on `x.trim()` inside `g[T: Tidy]` must show `Tidy.trim`, and the LSP must never report E0522 there. If mono looks the method up again by name, the editor and the compiler disagree. That is the worst kind of tooling bug.
> - **min's `self.trim()` inside the impl: in the spec, as one example.** A wrapper that calls the built-in is the most common way people will hit this. The E0522 help line must then suggest `StrOps.trim(self)`.
> - **The E0522 note text: in the spec.** It must name the built-in owner, e.g. "`trim` is a built-in `StrOps` method and is also defined by `Tidy`".
> - **Out of the spec:** the code action, the `blink fix` upgrade pass, the completion layout and the library lint. Record them as tooling follow-up tickets.
>
> **(3) Stable, ready to vote:** Option A with V1, S1 and the `self.trim()` example.

**AI/ML:**

> **Phase B round 1 (aiml)**
>
> **(1) V1, the warning at the impl site: yes, but weakly. Suppressible with `@allow`, and never an error.**
> - **For it:** when a model writes the impl, the warning points at the one line that causes the problem. Without it, the model sees N separate E0522 errors at call sites and has to work back to the cause. That shortens the repair loop.
> - **Against it:** it is one more diagnostic to learn, though no semantics depend on it.
> - **If it does not pass:** A alone is still correct and loud, so I will not block on this.
>
> **(2) Sub-points.**
> - **S1: yes, in the spec text, with a pinned test.** Lookup happens where the generic fn is defined, not where it is instantiated. `g[T: Tidy]` instantiated with `T = Str` must call `Tidy.trim`. It must not become ambiguous after monomorphisation, and it must not fall back to the builtin. If a model cannot predict that from the spec, generated generic code is not safe.
> - **Min's point that `self.trim()` inside the impl body is E0522: yes, as a one-line example.** It follows from the rule anyway, but models often read `self.trim()` inside `impl Tidy` as "my own method" (recursion) or as "the builtin". An explicit example removes the guess.
> - **Tooling (LSP, `blink fix`, the library lint): keep it out of the spec.** It belongs in tooling docs or tickets.
>
> **(3) Stable, ready to vote.**

**Minimalism:**

> **Minimalism, Phase B round 1**
>
> **(1) V1, the impl-site warning: no, not in the spec.**
> - **It repeats E0522 too early.** E0522 already fires at the place where the ambiguity matters. A warning at the impl would also fire on code that is fine: an impl written only for a generic bound (`g[T: Tidy]`), or only for qualified calls. That code would have to carry `@allow` to stay clean.
> - **It makes language growth noisy.** Every new sealed method would trigger warnings on upgrade, even for users who never call that name with dot syntax.
> - **The spec gains a diagnostic and pays for it forever.**
>
> If DevOps wants it, it can live in the tooling as an opt-in lint, the same as the LSP and `blink fix` items. That keeps it out of the language and reversible. If the panel puts it in the spec anyway, it must not be on by default, and I vote against.
>
> **(2) Sub-points:**
> - **S1 goes in, as one sentence plus a test.** It adds nothing new. It states what bound-based lookup already means: the trait is resolved at typecheck and mono never looks the method up again by name. It is the guarantee that stops builtin-wins coming back through mono, so it belongs in the text.
> - **`self.trim()` inside the impl body:** keep it as one line in the E0522 example, because people will hit it first. It is not a new rule.
> - **LSP, code actions, `blink fix`, library lint:** these are tooling and stay out of the spec.
> - **Spec change overall:** one sentence in §3c.4 saying "each sealed built-in surface counts as one owner in lookup". Delete the List HOF special case.
>
> **(3) Stable, ready to vote: Option A without V1 in the spec, plus S1.**

#### Phase C — Final vote

Questions:

- **Q1:** The sealed surface is one ordinary owner on every built-in receiver for every name; E0522; the impl is legal; qualified calls resolve; the List special case folds in.
- **Q2:** A — a warning at the impl in the spec, on by default. B — not in the spec.
- **Q3:** Resolution is fixed at type check against the bounds or the traits in scope; monomorphization never looks a method up again by name; `g[T: Tidy]` at `T = Str` calls `Tidy.trim`. Normative, with a pinned test.
- **Q4:** `self.trim()` inside `impl Tidy for Str` gets no special treatment: E0522, with a `StrOps.trim(self)` example.
- **Q5:** The E0522 note names the built-in owner.

Tally: **Q1 6-0 A. Q2 3-3** (A: Web, DevOps, AI/ML; B: Systems, PLT, Minimalism) → Phase D. **Q3 6-0 A. Q4 6-0 A. Q5 6-0 A.**

**Systems:**

> **Q1: A**
> - **Reasoning:** Each call resolves statically to one exact function, so codegen stays predictable and there is no runtime cost. When the language later adds a sealed method, any collision shows up as a loud E0522. Under builtin-wins the same source would silently compile to different machine code. This also makes every built-in receiver behave the same, so the List-HOF special case goes away.
> - **Concern:** In the compiler, typecheck and codegen each have their own builtin-first lookup. If one of them is not changed, the two can disagree again and the result is a silent miscompile. A test must pin the behaviour on every receiver, not only on Str.
>
> **Q2: B**
> - **Reasoning:** The warning has no effect on semantics or on the emitted code. It belongs in tooling, not in the rules of the language. Option A already makes the collision loud where it matters, at the call.
> - **Concern:** If the tooling never ships the lint, an impl author finds the clash only when callers start getting E0522.
>
> **Q3: A**
> - **Reasoning:** This is the rule that matters for codegen. If monomorphisation looks the name up again with T = Str, it finds the builtin. The instance then runs code that typecheck never approved: the body was checked against Tidy, but the binary calls StrOps. The resolved (trait, impl) pair must go from typecheck through to the C printer unchanged.
> - **Concern:** Today's mono registry or lowering may still find methods by bare name somewhere. A single test case could miss that path, so the test must cover the generic case at T = Str.
>
> **Q4: A**
> - **Reasoning:** It follows from Q1 with no new rule, and a special case inside impl bodies would mean a second lookup path to keep in step. `StrOps.trim(self)` compiles to the same direct call.
> - **Concern:** Users may find it odd that a call inside their own impl is an error, so the example has to be easy to find.
>
> **Q5: A**
> - **Reasoning:** Unless the note names `StrOps`, the user cannot tell which qualified spelling gives the builtin. Naming the owner makes the fix mechanical and lets `blink fix` apply it.
> - **Concern:** Fixing the wording in the spec may tie error-message changes to spec edits, so the spec should fix only what the note contains (the names of both owners), not its exact text.

**Web/Scripting:**

> # Web/Scripting panelist: Phase C ballot
>
> **Q1: A**
> - **Reasoning:** A Python or TypeScript developer who reads "ambiguous: `trim` is in StrOps and Tidy" fixes it in a minute. B turns every new built-in method into a library break that the library's consumers cannot fix, and C keeps an invisible bug. A is the only option that keeps the §3c.4 promise for the receivers people use most, and it removes the List-only special case.
> - **Concern:** Without [the open impl-scope question] settled, a single impl in a widely imported package could make `.trim()` ambiguous in many files the user never thought about.
>
> **Q2: A**
> - **Reasoning:** Under Q1-A, the consumer gets the E0522, but the author caused the clash. Only a default-on warning at the impl tells the author before they publish. If the spec leaves the warning out or makes it opt-in, almost no library author will turn it on, which in practice means no warning. Naming it in the spec also keeps the LSP, `blink check` and CI wording the same.
> - **Concern:** If B wins, library authors ship clashing names without ever seeing a signal, and every consumer pays with E0522 and a forum question.
>
> **Q3: A**
> - **Reasoning:** Reading the bound `T: Tidy`, anyone expects `x.trim()` to mean `Tidy.trim`. If monomorphisation looked the method up again by name and switched to `StrOps.trim` at `T = Str`, that would be the same silent change we rejected in Q1-C, only hidden inside generics. A pinned test makes sure it stays fixed.
> - **Concern:** The implementation may still look up by name in some path through monomorphisation, and only the pinned test will catch it, so the test must cover a Str instance.
>
> **Q4: A**
> - **Reasoning:** No special case means one rule to learn. Inside the impl body is where users will first hit this error, so a worked example with the `StrOps.trim(self)` fix will head off a lot of "why is my own impl ambiguous" questions.
> - **Concern:** Users may find it annoying to qualify `self` calls inside their own impl, but that is a fair price for a rule with no exceptions.
>
> **Q5: A**
> - **Reasoning:** "Ambiguous between StrOps and Tidy" only helps if the user knows that StrOps is the built-in surface and not some import they forgot. Naming the built-in owner in the note makes the fix obvious.
> - **Concern:** If the wording is too fixed, new built-in surfaces may need spec edits just to name them, so the spec should fix only what the note must contain, not its exact text.

**PLT:**

> **Q1: A**
> Reasoning: The spec already says the sealed surfaces are traits. A applies the existing §3c.4 rule to them with no new priority tier, so the typing rule stays one rule. It is also the only option that turns a later addition to a sealed surface into a loud error at the call rather than a silent change in behaviour or a broken impl.
> Concern: The implementation may only extend the six-name List HOF list instead of treating the sealed method names of every receiver as data. That would leave the inconsistency between receivers in place under a new name.
>
> **Q2: B**
> Reasoning: The warning changes no semantics, so it has no place in the language rules. Making it normative and on by default puts a diagnostic on correct library code that only uses the qualified call. That is noise, and the spec would then have to keep it stable forever.
> Concern: If it lives only in tooling, the LSP, `blink check` and CI may each word it differently, as devops warns. The tooling follow-up must name one lint ID.
>
> **Q3: A**
> Reasoning: This is the soundness core. Without it, `g[T: Tidy]` behaves differently at `T = Str` than at every other type, which breaks parametricity. Option A then gets bypassed during monomorphisation, and the silent capture moves into codegen. A pinned test is the only proof that codegen keeps to the rule.
> Concern: Today codegen dispatches by method name on built-in receivers ("table first"), so the test may fail on landing. It must not be marked xfail and then forgotten.
>
> **Q4: A**
> Reasoning: If the body of an impl preferred its own trait, that would be a scope-sensitive priority rule, the exact mechanism the panel rejects. One rule everywhere composes, and the `StrOps.trim(self)` example stops implementers from adding the shortcut.
> Concern: Users may find it surprising that `self.trim()` inside the `Tidy` impl is ambiguous. The diagnostic's hint must show both qualified forms.
>
> **Q5: A**
> Reasoning: The user did not write a `StrOps` impl and cannot see one. If the note does not name the built-in owner, the error points at an ambiguity with nothing visible in the source. Naming the owner as built-in also tells the user which of the two qualified forms gives the old behaviour.
> Concern: The required wording may drift from the general E0522 format. Keep the wording in a single place in the spec.

**DevOps:**

> **DEVOPS / TOOLING — Phase C ballot**
>
> **Q1: A**
> - **Reasoning:** Under A, the same set of candidate owners drives the diagnostic, the LSP completion entries and the code action, so those three cannot disagree. It turns the future "a new sealed method was added" event into a loud, fixable error with a fix a tool can apply. B makes a language upgrade an error that only a rename fixes. C is silent, and then hover lies about which method runs.
> - **Concern:** A compiler upgrade can break call sites in a dependency the user does not own. The upgrade tooling (`blink fix`) must exist when the first new sealed method ships.
>
> **Q2: A**
> - **Reasoning:** A diagnostic that the spec does not name gets three spellings: in the LSP, in `blink check` and in CI. That splits `@allow` names and docs, and it is the kind of tooling drift this panel exists to prevent. It is on by default because the impl author is the only person who can rename the method at no cost, and an opt-in lint never reaches that person. It has no effect on semantics and is never an error.
> - **Concern:** If B wins, the lint gets no stable name in the spec, so each tool's `@allow` spelling can drift and break suppressions across releases.
>
> **Q3: A**
> - **Reasoning:** If monomorphisation looks the method up again by name, the editor shows `Tidy.trim` at the generic call while the binary runs `StrOps.trim`. That is the worst kind of tooling bug, because hover and go-to-definition become false. The rule must be normative and a test must pin it.
> - **Concern:** The pinned test can be too narrow, for example covering only Str, while the bug comes back on another receiver such as List or Map. The test should cover at least two receivers.
>
> **Q4: A**
> - **Reasoning:** A wrapper that calls the built-in is how most people will first hit this, so the spec example with the `StrOps.trim(self)` fix will answer the most common question. A special case for `self` would be one more exception that the LSP and the docs must explain.
> - **Concern:** Users may find E0522 on `self.trim()` inside their own `trim` impl surprising. The help line must show the exact `StrOps.trim(self)` spelling, or they will think the compiler is wrong.
>
> **Q5: A**
> - **Reasoning:** "Found in `StrOps` and `Tidy`" tells a user nothing if they have never heard of `StrOps`. The note must say "built-in" so they know which owner is the language's. The help line must show both qualified spellings.
> - **Concern:** If the note text is fixed too tightly in the spec, the compiler cannot improve the wording later without a spec change. The spec should require the content (the built-in owner, named as built-in), not the exact characters.

**AI/ML:**

> **Ballot (aiml)**
>
> **Q1: A**
> - **Reasoning:** This is the rule §3c.4 already states. Built-ins stop being a hidden exception, so a model that has read the spec predicts the result without learning a special case. Ambiguity is loud, local, and the diagnostic gives the exact one-edit fix. B makes every release that grows a sealed surface into an expensive rename, and C is a silent wrong answer, the worst failure for generated code.
> - **Concern:** When a release adds a sealed method, old models trained on the earlier release will keep writing the now-ambiguous unqualified call until fix tooling and new training data catch up.
>
> **Q2: A**
> - **Reasoning:** A warning on by default puts the cause on the one line that causes it. Without it, the model sees N separate call-site errors and has to work back to the cause, which wastes repair turns. Naming it in the spec gives the CLI, LSP and CI the same wording, and stable wording is what models learn from. It has no effect on semantics and is never an error.
> - **Concern:** If it loses, the impl site stays quiet and authors find the clash only through call-site E0522s. That is slower to debug, but still correct.
>
> **Q3: A**
> - **Reasoning:** Generic code is only safe to generate if lookup is fixed where the code is written. A method that changes meaning when instantiated with `T = Str` is something no model can predict from the spec. A pinned test stops the compiler from drifting back to name-based lookup.
> - **Concern:** Existing mono code may still look methods up by name in places nobody has audited, so the test has to cover a Str instance specifically.
>
> **Q4: A**
> - **Reasoning:** Models often read `self.trim()` inside `impl Tidy` either as recursion or as the builtin, and those two guesses are both common and opposite. One example in the spec removes the guess at almost no cost in spec text.
> - **Concern:** Authors will find `StrOps.trim(self)` noisy in impl bodies that delegate to the builtin, and will ask for a shorthand later.
>
> **Q5: A**
> - **Reasoning:** The note is the main thing a model reads when it repairs code. If it names the built-in owner and both qualified forms, the fix is mechanical and correct on the first try. Vague wording leads to wrong fixes, such as renaming the builtin call.
> - **Concern:** Normative wording may lock in phrasing that later reads badly across all receivers. Specify the content (the owners and the qualified forms), not the exact text.

**Minimalism:**

> **Minimalism, Phase C ballot**
>
> **Q1: A**
> - **Reasoning:** This adds no rule. §3c.4 already says sealed surfaces are "trait-based at spec level" and gives the lookup rule: one match calls the method, two or more give E0522. A applies that rule as written. It deletes the builtin-first shortcut and the List-only special case, so the compiler gets smaller. B contradicts the 5-0 call-site decision. C brings back inherent-method precedence, which the 4-1 vote removed.
> - **Concern:** Each new sealed method a release adds can turn existing `x.m()` calls into E0522. If `blink fix` is not ready to rewrite those calls, upgrades will cause friction.
>
> **Q2: B**
> - **Reasoning:** E0522 already reports the clash at the call, which is the only place it changes behaviour. A warning at the impl would also fire on code that is correct: impls written only for generic bounds or only for qualified calls. A spec-level diagnostic is surface we maintain forever. An opt-in tooling lint gives DevOps what they want and can be removed later.
> - **Concern:** If the tooling follow-up is never built, authors learn about the clash only when someone first calls the method with dot syntax.
>
> **Q3: A**
> - **Reasoning:** This is not new surface. It states what bound-based lookup already implies, and it stops builtin-wins coming back through monomorphisation. One sentence plus one pinned test is a cheap guarantee.
> - **Concern:** The current mono path looks methods up again by name, so the fix may touch more code than the spec sentence suggests.
>
> **Q4: A**
> - **Reasoning:** It gets no special treatment, which is the minimal choice. The example costs one line and covers the first place users will hit this. It also removes the accidental-recursion trap.
> - **Concern:** Users may see writing `StrOps.trim(self)` inside their own impl as ceremony and push to add special-case shadowing later.
>
> **Q5: A**
> - **Reasoning:** E0522 already lists every owner. This only makes sure the sealed surface is listed by its trait name, not shown as an anonymous "built-in". Users need that name to write the qualified fix, so it costs nothing new.
> - **Concern:** If the spec fixes the exact wording, implementations lose room to improve the message later. The spec should require the owner's name, not the sentence.

#### Phase D — Round 2 (Q2 only)

The moderator told the panel two facts before this round: the spec already has on-by-default W-codes that change neither semantics nor emitted code (W0604, W0731, W0816), and it already has a non-normative lint note (`sections/03b_contracts.md:566`).

**Debate:**

**Systems:**

> The precedent breaks my Phase C argument. The spec already has on-by-default W-codes for issues that change neither semantics nor emitted code; W0731 OverrideOfDeprecatedDefault is the closest one. So "no effect on semantics, so it belongs in tooling" does not hold in this language.
>
> DevOps is right about wording. A diagnostic the spec does not name gets three spellings and three `@allow` names, and that is a real maintenance cost. PLT's own concern in Phase C says the same thing.
>
> Language growth decides it for me. Say v1.4 adds `StrOps.pad`. An on-by-default warning then fires in the library that holds `impl Fmt for Str`, when its author upgrades. The author can rename at no cost before consumers see E0522. An opt-in lint never fires there.
>
> Min's false positive is real but narrow. An impl written only for generic bounds or only for qualified calls gets `@allow` once, on the impl. That costs one line for a deliberate design choice.
>
> My refinement of A has three rules:
> - The warning fires at the impl method only, never at a call or through a generic binder.
> - Its note names the sealed owner.
> - It is never an error, and the spec does not require it to stay at warning level under `--strict`.
>
> **Current Q2 position: A, with the refinement above. Ready to re-vote.**

**Web/Scripting:**

> # Web/Scripting panelist: Phase D, Q2 re-debate
>
> **To plt and min ("it fires on correct code"):** The impls they describe, written only for generic bounds or qualified calls, are a design choice. Writing `@allow(...)` on that one impl records the choice where the next reader will look. That is one line per impl, against N E0522s in every consumer.
>
> **To sys and plt ("no semantics, so it does not belong in the rules"):** The spec already has warnings like that. W0731 OverrideOfDeprecatedDefault changes no semantics, has a W-code, is on by default, and exists to warn an author. The precedent is there.
>
> **To min ("surface we maintain forever"):** The spec freezes only the code and the name, not the wording. A non-normative note, like the one at 03b_contracts.md:566, fixes neither the ID nor the default, so devops' "three spellings" problem stays.
>
> **Refinement A′:**
> - A named W-code in the spec's diagnostic catalog, on by default and `@allow`-suppressible, never an error.
> - It fires only when the user trait is `pub`, meaning code outside its module can import it.
> - A private trait's clash shows up only in the author's own code, where the author already gets E0522. That removes most of the "noise on correct code" cases min and plt raised. It keeps the warning for the one case that matters: a library author whose consumers would get the errors.
>
> **Position:** A′ is my first choice and A is my fallback. Ready to re-vote.

**PLT:**

> I am changing my vote to A, with a refinement.
>
> Web's reply removes my noise argument. Even when the library author only uses the qualified call, every consumer who writes `x.trim()` still gets E0522. The clash is a defect in the author's public API, so a warning at the impl is correct even in that case. If the author wants the name anyway, one `@allow` on the impl records that choice in the source.
>
> My other argument was that the spec would have to keep the warning stable forever. W0731 OverrideOfDeprecatedDefault already sets that precedent: an impl-site, on-by-default W-code with no semantic effect. And devops is right that a lint with no name in the spec will get three different spellings. Minimalism's opt-in version would never reach the one person who can rename the method for free.
>
> The refinement, to keep the warning sound and narrow:
> 1. A named W-code. It fires only at the method declaration inside an `impl` block where the receiver is a built-in type and the method name is in that receiver's sealed surface. It never fires at call sites and never fires through a generic binder.
> 2. It never affects resolution or emitted code. `@allow` suppresses it, and it is never an error.
> 3. The spec states that a release which grows a sealed surface can make this warning appear on code that compiled before, and that this does not count as a breaking change.
>
> Current Q2 position: A, with refinements 1 to 3. Ready to re-vote.

**DevOps:**

> **DEVOPS / TOOLING — Phase D, Q2 re-debate**
>
> **What B gets right.** min and plt are correct that the warning fires on correct code: an impl written only for a generic bound, or a library that only ever uses the qualified call. That is real noise, but `@allow` is a one-line fix. W0731 sets the precedent: it is a default-on warning with no effect on semantics, and it is already in the catalog.
>
> **Where we already agree.** plt's own concern is my concern: "The tooling follow-up must name one lint ID." What I need from the spec is one identity, not a mandate to fire.
>
> **Refinement A′:**
> 1. **Normative:** the diagnostic catalog reserves `W0xxx BuiltinMethodNameCollision`, with its span (the `fn` in the impl), its `@allow` spelling, and "never an error".
> 2. **Non-normative:** a note in the same style as `03b_contracts.md:566` says tooling (`blink check` and the LSP) should report it by default. The compiler is not required to emit it.
>
> **What A′ gives each side:**
> - One name, so the LSP, `blink check` and CI cannot drift.
> - Web and aiml get the author-facing warning in the tools authors actually run.
> - min's "surface we maintain forever" shrinks to one catalog row, and dropping the "should" later needs no spec rule change.
> - sys's concern ("tooling never ships it") is covered, because the catalog row makes the lint a tracked deliverable.
>
> **Position:** A′. If A′ is not on the ballot, I vote A. Ready to re-vote.

**AI/ML:**

> **Phase D, Q2 (aiml)**
>
> **The noise objection (plt, min).** The warning fires only when an author picks a name that a sealed surface already owns. No file in the corpus does that today, so the noise is small. When the collision is deliberate (an impl used only through generic bounds or qualified calls), `@allow(...)` on the impl records that choice. A reader or a model then sees the intent on that line, not a surprise later. The spec already handles legal-but-likely-mistake cases this way: W0731 OverrideOfDeprecatedDefault is on by default and suppressible.
>
> **"Belongs in tooling" (sys, min).** An opt-in lint never reaches the one person who can rename the method for free, the author. Plt's own concern also concedes the tooling must name one ID. If the ID has to be fixed, the catalog is where it gets fixed.
>
> **Refinement R, to close the tie:**
> - Put one named W-code in the diagnostic catalog, on by default and `@allow`-suppressible.
> - The spec text says explicitly that the warning has no effect on resolution or semantics. It is a lint whose ID and trigger are fixed, so the CLI, LSP and CI cannot drift apart.
> - It fires only at the impl that collides, never at uses through a generic bound and never at qualified calls.
>
> Under R, sys and plt get "no semantics in the rules", and devops and web get one stable name.
>
> **Position: A, refined as R. Ready to re-vote.**

**Minimalism:**

> **Minimalism, Phase D (Q2)**
>
> **The web and devops argument holds.** Under the orphan rule, `impl Tidy for Str` is legal only in the package that owns `Tidy`. So whoever writes the impl always owns the name and is the only person who can rename it cheaply. If the lint is opt-in, it never reaches that person. I cannot answer that with "tooling can do it".
>
> **My noise objection is still real, but small.** An impl used only through bounds or qualified calls needs one `@allow` line, which also records that the clash is on purpose. The catalog already has W-codes with `@allow`, so this adds no new mechanism, only one entry.
>
> **Refinement A′. I accept A on these conditions:**
> 1. **One named W-code in the catalog,** on by default and suppressible with `@allow`. The language never makes it an error.
> 2. **It fires at the impl method only,** once for each colliding method. It never fires at call sites or through generic binders, and it never changes resolution or the emitted code.
> 3. **The spec says plainly that it is diagnostic only,** so that removing it later is not a breaking change.
> 4. **When a language release adds a sealed method,** the warning fires on existing impls on upgrade. That is intended: the author learns before callers get E0522.
>
> **Current Q2 position: A′ (A with conditions 1–4). Ready to re-vote.**

Ballot: **A1** — a named W-code in the catalog, on by default, suppressed with `@allow`, never an error; fires once per method at the impl method only, when the receiver is a built-in type and the name is in its sealed surface; never at calls, generic binders or qualified calls; diagnostic only, so removing it later is not breaking; may fire on upgrade when a surface grows, which is not breaking; its note names the sealed owner. **A2** — A1, but only for a `pub` trait (Web). **A3** — a reserved catalog row with a non-normative "should report" (DevOps). **B** — not in the spec. A side question asked whether to keep Systems's sentence that the spec does not require the warning to stay a warning under `--strict`.

**Re-vote: 6-0 A1.** The `--strict` sentence lost 4-2 (yes: Web, DevOps; no: Systems, PLT, AI/ML, Minimalism), so the spec says "never an error".

**Systems:**

> **Vote: A1**
>
> - **Reasoning:** One named W-code fixes the wording, span and `@allow` spelling in a single place. The CLI, the LSP and CI then cannot drift apart, and there is no effect on resolution or on the emitted code. Firing only at the impl method reaches the one person who can rename at no cost, including when a release grows a sealed surface. A2 misses a private trait in a large module, where the clash is equally real. A3 leaves the compiler free to skip the warning, so in practice it brings back option B.
> - **Concern:** A library author who uses only qualified calls on purpose must write `@allow` on each colliding method. If more sealed names are added later, that one line per method could add up to noise.
> - **--strict wording:** No. I drop my wording and accept "never an error" as plain text. One rule is simpler, and a `--strict` exception would give the spec a second diagnostic level to keep.

**Web/Scripting:**

> # Web/Scripting panelist: Phase D re-vote on Q2
>
> **Vote: A1**
>
> **Reasoning:** A1 gives what my side asked for: one name, on by default, raised where the clash starts, at the impl method the author can rename at no cost. I drop my `pub`-only filter (A2). A1 fires once per colliding method, never at call sites and never through generics, which already handles most of the "noise on correct code" concern. A single `@allow` covers the rest. One rule with no visibility exception is also easier to teach.
>
> **--strict wording: yes, I accept it.** A team that opts into `--strict` has chosen to treat warnings as errors, as with `-Werror` or TypeScript's `strict`. The spec should not override that choice.
>
> **Concern:** A release that adds sealed methods may cause a burst of these warnings across the ecosystem with no guidance on what to do. The release notes and the `blink fix` follow-up must ship together with each surface growth.

**PLT:**

> **Vote: A1**
>
> **Reasoning:** A1 keeps the warning strictly diagnostic, which matches my refinements. It fires only at the method that causes the clash, has no effect on resolution or codegen, and can be removed later without a breaking change. A2's `pub`-only condition is arbitrary from the type-theory side: a private trait still produces E0522 inside its own module, so the author still needs the warning. A3 reserves a name but does not require any tool to emit it, so the split in wording that motivated A comes back.
>
> **sys's `--strict` wording: no.** If `--strict` could turn this warning into an error, a release that grows a sealed surface would break strict builds of code that is correct. That contradicts the A1 clause that such growth is not a breaking change. The warning must stay "never an error" in every mode. Suppression goes through `@allow`, not through promotion.
>
> **Concern:** Implementations may check sealed names with a hardcoded per-receiver list that drifts from the actual sealed surface, so the warning stops firing for newly added methods. Both the warning and E0522 must read the same per-receiver sealed method table.

**DevOps:**

> **DEVOPS / TOOLING — Phase D re-vote on Q2**
>
> **Vote: A1**
>
> **Reasoning:**
> - A1 gives the one named W-code I asked for, so the LSP, `blink check` and CI share one spelling and one `@allow`.
> - It is on by default, so it reaches the impl author, who is the only person who can rename the method at no cost.
> - Its tight scope (only the method declaration inside the impl, never at call sites, never through a generic binder) removes the false positives min and plt raised.
> - A1 is stronger than my own A3 because it is normative in the compiler, so no tool can skip it.
> - I reject A2: a non-`pub` trait still makes every unqualified call inside its own module ambiguous, so its author needs the warning too.
>
> **sys's --strict wording: yes.** `--strict` is an opt-in CI policy, the same pattern as `-Werror`, and promoting warnings there is the user's choice. The spec text must still say "never an error by default". The spec should not single out this one warning: `--strict` should apply to every catalog warning the same way.
>
> **Concern:** A release that grows a sealed surface will make this warning fire on code that compiled before. Under `--strict`, that fails CI builds on a compiler upgrade, so the release notes must list each new sealed method name.

**AI/ML:**

> **Ballot (aiml): A1**
>
> **Reasoning:** A1 gives one named W-code with a fixed trigger and fixed wording. That is the stable signal a model learns from and repairs against, and it points at the one line that causes the clash. The trigger rule is simple and syntactic (an impl on a built-in receiver whose method name is in the sealed surface), so a model can predict when it will fire. A2 adds a second condition, `pub`, which is one more decision point. A3 leaves emission optional, which brings back the drift between tools that naming the code was meant to remove.
>
> **On sys's `--strict` wording: no.** I searched sections/ and the spec has no general `--strict` mode. The only escalation is the per-warning `--strict-struct-layout` for W0812. Writing "may escalate under `--strict`" would refer to a mode the spec never defines. The text should say "never an error". If a general warnings-as-errors mode is added later, it should apply to every warning the same way, under its own rule.
>
> **Concern:** Library authors who collide on purpose will add `@allow` everywhere without thinking, and models will copy that habit into code where the collision is a real mistake.

**Minimalism:**

> **Minimalism, Phase D re-vote on Q2**
>
> **Vote: A1**
>
> **Reasoning:**
> - **A1 holds the fewest rules.** It adds one catalog entry and reuses the W-code and `@allow` mechanisms we already have. It fires at one site and states that it has no effect on semantics, so removing it later breaks nothing.
> - **A2 adds a `pub` condition without enough reason.** A private trait's clash still produces E0522 for callers in the same module, so a `pub` gate only hides the warning from the author.
> - **A3 splits one diagnostic into normative and non-normative parts, and makes the compiler optional.** That brings back the divergence between tools that naming the code was meant to stop.
>
> **sys's `--strict` wording: no.** A1 should not mention `--strict` at all. Whatever general rule `--strict` applies to all warnings also applies to this one. A per-warning sentence is extra spec text with no new effect.
>
> **Concern:** Libraries that grow alongside the language may collect `@allow` lines on impls they keep on purpose, and the warning may come to read as noise.

### Final Spec

```blink
trait Tidy {
    fn trim(self) -> Str
}

impl Tidy for Str {               // W0734 SealedMethodNameCollision
    fn trim(self) -> Str { "X" }
}

let text = "  hi  "
text.trim()                       // E0522: `trim` is a built-in `StrOps` method and is also defined by `Tidy`
StrOps.trim(text)                 // "hi"
Tidy.trim(text)                   // "X"

fn g[T: Tidy](x: T) -> Str { x.trim() }
g(text)                           // "X": the bound selects Tidy.trim, also at T = Str
```

- A sealed built-in trait is one ordinary, always-in-scope owner in §3c.4 lookup, on every built-in receiver and for every method name. No trait ranks above another. The List special case for six names is now one case of the general rule.
- A user impl that reuses a sealed method name on a built-in type is legal. An unqualified call of the name is E0522; a qualified call resolves it.
- When one owner is sealed, the E0522 note names that trait as built-in, and the help lists each qualified call. The spec fixes the content, not the wording.
- `self.m()` inside the impl gets no special treatment: it is E0522, and the fix is `StrOps.m(self)`.
- The type checker resolves each call once, to one trait. Monomorphization keeps that trait and never looks the method up again by name.
- **W0734 `SealedMethodNameCollision`:** at the method declaration in the impl only, once per method; never at calls, qualified calls or through bounds; note names the sealed trait; on by default; `@allow` suppresses it; never an error; no effect on resolution or emitted code. Its appearance on upgrade, or its later removal, is not a breaking change.
- Growth of a sealed surface turns a collision into E0522 at calls and W0734 at the impl, never into a silent change.

Spec text: §3c.4 *Built-in Type Method Dispatch* (`sections/03c_protocols.md`), §3.2.2 sealed-trait note (`sections/03_types.md`), `ERROR_CATALOG.md` (W0734; E0522 spec reference corrected to §3c.4).

### Concerns for the implementation

- Type checking and code generation both lose builtin-first lookup; if only one changes, they disagree again (Systems).
- Tests cover more than one receiver — at least two in the bound test — and cover a `Str` instance of a generic function (Systems, DevOps, Web, AI/ML).
- The pinned test must not be marked xfail and forgotten (PLT).
- The sealed method names of each receiver are data, read by both E0522 and W0734; do not extend the six-name List list (PLT).
- Each release that grows a sealed surface lists the new names in its release notes and ships the `blink fix` rewrite to the qualified form (Web, DevOps, Minimalism).
- `@allow` lines may pile up on deliberate collisions, and models may copy them where the collision is a mistake (Systems, Minimalism, AI/ML).
- Interaction with the open impl-scope question: one impl in a widely imported package could make a call ambiguous in many files (Web).
