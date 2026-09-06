[< All Decisions](../DECISIONS.md)

# Operators / Methods on `Self` in a Trait Default Body — Design Rationale

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML,
minimalism) ran as independent background agents. Phase A produced six proposals;
Phase A.5 dedupe found all six had converged on one rule (Phase B skipped, ≤2
options, no flagged variation); Phase C was a silent vote — **unanimous 6-0 on every
question**, so Phase D was not triggered. The Phase C ballot carried **five**
questions (Q1–Q5), Q5 being "the sealed-case diagnostic should NOT suggest `: Add`."

## The resolution

Inside a trait's default method body, `self` has the abstract type `Self`, treated as
an **implicit type parameter of the trait, bounded by the trait's guarantee set**: the
methods the trait itself declares, plus every method of each trait named in its
supertrait clause, transitively. An operator (which desugars to a trait method per
§3.6 *Operator Desugaring*) or a plain method call on a value of type `Self` is
well-formed **only when its backing trait is in the guarantee set**. Violations are
reported at the **trait definition** site with `error[UnlicensedSelfOperation]`
(E0305). This is the *Polymorphic Trait Implementations* parametricity rule
(03_types.md:2330) applied to `Self`, matching the sibling def-site check
for declared type parameters.

## Vote tally (6-0 on every question)

| Q | Question | Result |
|---|----------|--------|
| Q1 | Bound-required (not permit-then-check-later)? | **Yes 6-0** |
| Q2 | Reported at the trait **definition** (not impl/mono)? | **Yes 6-0** |
| Q3 | Sealed-arithmetic consequence intended, no carve-out? | **Yes 6-0** |
| Q4 | Uniform over all operator families + plain method calls? | **Yes 6-0** |
| Q5 | Sealed-case diagnostic: **B** (do NOT suggest `: Add`)? | **B 6-0** |

---

## Phase A — independent proposals (verbatim)

### Systems

> ## Recommended: P1 — Definition-site bound rule ("Self is the trait's implicit type parameter")
>
> Rule: Inside a trait `T`'s default method body, `self: Self` may only be used with a method `m` if `m` is reachable through the *visible bound set of Self at the definition site*, which is exactly: the methods declared by `T` itself, plus the methods of every trait `U` with `T: U` declared (transitively). Operators desugar first (§3.6), so `self + self` must find `Add.add` in that bound set. Unbounded use is a definition-site error. This is the exact analogue of the sibling declared-type-parameter check for declared type parameters — Self is simply the trait's implicit, self-bounded type parameter.
>
> ### Answers
> - **Q1**: Licensed ONLY when the trait declares the corresponding (super)trait bound. Symmetric with the declared-type-parameter check. No "always permit, check later."
> - **Q2**: At the trait DEFINITION site, before any implementor exists. Crucially, this is *sound and complete with no per-monomorphization re-check needed*: the default body only calls methods guaranteed present by declared supertrait bounds; §3 already forces every `impl T` to satisfy `T`'s supertrait bounds; therefore concrete Self always has those methods and every monomorphization succeeds by construction. A mono-site ICE (I0001) is defense-in-depth only, not a correctness requirement.
> - **Q3**: Yes — since arithmetic traits are sealed to numerics, `trait X: Add` restricts X's implementors to built-in numerics, so `self + self` in a user trait default is legal only for numeric-only traits. This is *intended and correct*, not a wart. A body that adds Self to Self is definitionally a numeric operation; there is no zero-cost lowering of `+` for a non-numeric type — it literally cannot compile. The type system honestly saying "only numerics need apply" is the right outcome. The diagnostic should say exactly this ("`+` requires `Self: Add`, and Add is sealed to built-in numeric types").
> - **Q4**: Fully general — one rule covers all operator families (Add/Sub/Mul/Div/Rem/Neg, Ord, Eq) AND plain named method calls on self. Ord/Eq differ from arithmetic only in satisfiability (OPEN, so `trait Sortable: Ord` is usable by user types); the licensing rule is identical.
>
> ### Systems tradeoffs (why this is the zero-overhead, predictable answer)
> - **Predictable codegen.** The legal operation set of a default body is fixed and readable at the trait declaration — independent of the cross-product of implementors. Every default that typechecks at definition monomorphizes cleanly for every valid implementor. Zero surprises at the C boundary; the current "reaches the C compiler and fails there" failure mode becomes structurally impossible.
> - **Zero-cost preserved.** Bounds resolve statically to concrete methods at each mono instantiation → direct calls / inlined operators, no vtables, exactly as trait methods already lower.
> - **No expressiveness loss.** The pattern "some implementors use the default, others can't" is precisely the unsoundness we reject. If a trait author wants "every implementor must supply this," that is already an abstract method (no default body) — served today.
>
> ## For the record: P2 — Mono-site-only check (I recommend AGAINST)
> Permit any operator/method on self at the trait definition; typecheck the default body only when monomorphized for concrete Self. [...] this is the old-C++ model — errors surface late at instantiation, depend on which implementors exist and in what order they monomorphize, and are far less predictable. [...] Inferior on every Systems axis.
>
> ## Recommendation
> Adopt **P1**: definition-site check against the declared (super)trait bound set, general across all operator families and plain method calls, reported at the trait definition. It is sound-by-construction (no mandatory mono re-check), preserves zero-overhead monomorphization, makes the sealed-arithmetic consequence in Q3 an honest and intended restriction, and aligns Blink with Rust/Haskell rather than pre-concepts C++.

### Web/Scripting

> ## Recommended position (one line)
> Check at the trait DEFINITION. Inside a default body, `self`/`Self` may only use what the trait GUARANTEES: methods declared in this trait or a declared supertrait, and operators whose backing trait is a declared supertrait. Anything else is a compile error at the definition, before any impl exists. This makes a default body behave exactly like `fn f[Self: ThatTrait](self)` — same rule the sibling declared-type-parameter check already set for a type parameter `T`.
>
> ## Why this is the only acceptable DX outcome
> The MVCE `trait Doubler { fn double(self) -> Self { self + self } }` compiles today and blows up in the C compiler for a non-numeric implementor. That is the single worst thing we can do to a JS/Python dev: an error in generated code they never wrote, with a message about the wrong file. [...] The check has to land where the mistake was made — the trait author's line — not on some innocent `impl Doubler for Str` and never on the C compiler.
>
> ## The 90% case must keep working (this is the real constraint)
> Everyday devs almost never write arithmetic-generic traits. What they write constantly is method-call default bodies and Eq/Ord defaults [...] Both must compile with zero ceremony, because the operation used is guaranteed on `Self`.
>
> ## Q1–Q4 answered
> - Q1: Bound-required, checked at definition. License = the trait guarantees the op (declared method / declared supertrait). Not "always permit, check later."
> - Q2: At the trait DEFINITION. Not impl, not mono. The author who wrote it is the one who must fix it; blaming implementors or C is unacceptable.
> - Q3: Yes — `self + self` becomes legal only via `trait Doubler: Add`, satisfiable ONLY by built-in numerics. That is honest and consistent with the 4-1 sealing vote; do NOT carve out. Arithmetic-generic-over-numerics is a real (if rare) use; for user types the answer is named methods (`.add()`), same as `Decimal`/`BigInt` already do.
> - Q4: ALL operator families (Add/Ord/Eq) AND plain method calls on self, one uniform rule, one error code. "You may call on self only what Self is known to provide." Uniformity is a learnability win: one concept, one thing to search.
>
> ## Alternative I explicitly reject
> "Always permit at definition, check at each impl/mono." Rejected: it defers the error onto implementors (who didn't write the bug) or onto monomorphization (cryptic, far from source), and for `impl Doubler for Int` it would never error at all [...] That is the current broken behavior with extra steps.

### PLT

> ## Core thesis
> `Self` inside a trait default body is a BOUNDED, RIGID type variable — not a concrete receiver, not a free type parameter. Its bound set is fixed at the trait declaration:
>
>     B(Trait) = { Trait } ∪ transitive-supertraits(Trait)
>
> A default body may call an operation on `self: Self` IFF that operation is justified by B(Trait). This is the impl-body parametricity rule (§3.4, lines 2324–2330) extended to default bodies, with `Self` playing `T`'s role.
>
> ## Typing rule (precise)
> In a default method body of trait D:
> - `self : Self`, a rigid type variable, assumed to satisfy EXACTLY B(D) = {D} ∪ transitive-supertraits(D), nothing more.
> - `self.m(...)` well-typed IFF `m` is a required/default method of some U ∈ B(D); its result+effect row read from U.
> - An operator on `self` well-typed IFF its backing trait (§3.6 table: `+`→Add, `<`→Ord, `==`→Eq…) ∈ B(D).
> - Otherwise DEFINITION-site error. [...] Checked ONCE per default body at the trait definition, independent of implementors/mono. This closes today's bug (unchecked default reaches cc).
>
> ## Q1–Q4
> - Q1: Licensed ONLY when the trait declares the corresponding (super)trait (or the method is the enclosing trait's own). Require the bound; check at definition. NOT "always permit, check later."
> - Q2: At the trait DEFINITION, before implementors known. One modular check covers all implementors. Deferring to impl/mono is unsound-by-omission (never-instantiated default escapes) with far-from-cause diagnostics.
> - Q3 (the honest resolution): Requiring the bound does NOT make `self+self` never legal. `trait Doubler: Add` is legal and meaningful — it restricts implementors to Add-satisfying types = the built-in numerics. `impl Doubler for Int` works; user structs fail at the impl site. [...] Sealing bounds WHO can implement, not WHETHER the bound may be named. Correct and intended.
> - Q4: ALL operator families (Add…Neg, Eq, Ord) AND all plain trait-method calls on self. One uniform rule — arithmetic isn't special. Calls to the enclosing trait's own methods (e.g. Eq.ne → self.eq) always fine since D ∈ B(D).
>
> ## Soundness
> `Self` is a skolem whose only capabilities are B(D). Mono substitutes implementor S; impl coherence already forces S to satisfy every trait in B(D). So every type-checked operation is available on S — one definition check ⟹ correctness for all implementors.
>
> ## Rejected
> - B (permit at def, check per impl/mono): unsound-by-omission (today's cc bug), breaks modular checking, poor diagnostics.
> - C (infer the bound from the body): a supertrait changes the public contract (who may implement); implicit is non-modular. Blink already forbids implicit defaulting (E0301) and implicit type app (W0604). Bounds must be explicit.

### AI/ML

> ## Recommended position: ONE rule, reused verbatim from the impl-body parametricity rule
>
> Blink already has a normative rule for abstract types in bodies (§3.6, line 2330): "the only legal way for a body to vary behavior based on an abstract type is to introduce a trait bound and call a method on that bound." A trait's `Self` in a default body is exactly that situation. So we should not invent a new rule — we should extend the one that exists.
>
> ### THE RULE
> Inside a trait default body, a call on `self`/`Self` (including an operator that desugars to a trait method per §3.6) is licensed ONLY when the target method belongs to:
> 1. the trait being declared itself, OR
> 2. a trait named in the trait's supertrait clause (`trait T: Super`).
>
> Otherwise: compile error AT THE TRAIT DEFINITION.
>
> ### Answers to Q1–Q4
> - **Q1 — licensed when?** Only when the corresponding (super)trait bound is declared. No "always permit."
> - **Q2 — where reported?** At the trait DEFINITION (def-site). This mirrors the sibling declared-type-parameter check [...] NOT at impl / monomorphization.
> - **Q3 — sealing / arithmetic never legal for user traits?** Arithmetic on Self in a default body is legal only when the trait declares `: Add` (etc.). Because arithmetic traits are sealed to numerics, such a trait is satisfiable ONLY by builtin numeric implementors [...] That is the intended, coherent consequence of sealing [...] The rule is NOT vacuous — `trait Doubler: Add` is a legal, useful trait; its universe of implementors is just the numeric builtins.
> - **Q4 — scope?** All operator families (Add/Sub/…, Ord, Eq) AND plain trait-method calls on self. Uniform. Calls to the trait's OWN methods are always licensed — that is the whole point of a default body.
>
> ### AI-first scorecard
> - **Learnability (from spec alone): STRONG.** It is not a new rule — it is the §3.6 parametricity rule ("name the bound you use") applied to Self. [...]
> - **Consistency: STRONG.** Same principle as impl-body parametricity (line 2330) and same def-site timing as the declared-type-parameter check. No special case, no carve-out [...]
> - **Generability: STRONG [...]** LLMs already emit supertrait clauses correctly when the body needs them, BECAUSE the error is local and immediate. The alternative (defer to mono) gives the model an error far from the offending body — much harder to attribute.
> - **Debuggability: STRONG.** The error points at `self + self` (or `self < other`) and the help line names the exact fix [...] Single-hop self-correction.
> - **Token Efficiency: NEUTRAL-to-GOOD.** The common case — a default that only calls the trait's own methods (like `ne` calling `eq`) — needs NO extra clause. A supertrait clause is required only when the body reaches for a capability outside the trait [...]
>
> ### Cross-language note (what LLMs actually get right/wrong)
> In Rust, calling a foreign trait's method inside a default method requires `where Self: OtherTrait` (or a supertrait). Models routinely OMIT this bound on the first try and hit "method not found for type `Self`" — but they recover reliably BECAUSE the error is at the definition and the compiler names the missing bound. [...] That argues directly FOR def-site checking here.

### Minimalism

> RECOMMENDED POSITION: The honest minimal rule is exactly the one you named. Adopt it with ZERO new syntax and ZERO new concepts. Reject "do nothing" (it fails the soundness bar), and reject any carve-out that makes `Doubler` compile.
>
> ## The reframe (this is the whole fix)
> `Self` in a trait declaration is ALREADY an implicitly-bounded type parameter. Its bounds are precisely:
>   (a) the trait being declared (self implements it — that's why `Eq.ne`'s default can call `self.eq()`), plus
>   (b) the trait's declared supertraits, transitively (`trait Ord: Eq` → within Ord's defaults, `Self: Eq`).
> The parametricity rule (03_types.md line 2330) already governs bounded type parameters. So the entire fix is ONE normative sentence: "The parametricity rule applies to `Self` in a trait default body; the guarantee set is the trait's own methods plus those of its declared supertraits." Operators are covered for free because §3.6 desugars `self + self` → `Add.add(self, self)`, i.e. it requires `Self: Add`.
>
> ## Subtraction analysis / concept count
> - New syntax: 0
> - New semantic concepts: 0 (Self-as-bounded-typaram is already true; supertraits already exist; parametricity already normative; def-site check precedent already set by the sibling declared-type-parameter check)
> - New spec text: 1 normative sentence + 1 diagnostic help-variant
> - New mechanism: 0 — reuses the declared-type-parameter check's def-site type-parameter-arith check, generalized from "declared type parameter" to "Self bounded by its supertraits", and reuses the existing supertrait-chain traversal.
>
> ## Q3 — sealing consequence (the sharp one)
> YES: because Add/Sub/… are sealed to numerics, `trait X: Add` is unsatisfiable, so arithmetic on Self in a USER trait default body is NEVER licensable. This is INTENDED and correct — it is the sealing vote (4-1) telling the truth, not a wart. [...] Do NOT invent an allowance to paper over it. [...] Note the built-in numeric traits are unaffected: within `trait Add`, Self is bounded by Add, so their own defaults are fine. Same rule, different outcome — that IS the minimality.
>
> ## Q4 — scope
> UNIFORM rule over ALL operators (Add/Ord/Eq) AND plain method calls on self. This is the MINIMAL answer, not over-reach: operators ARE method calls after the §3.6 desugar, so treating arithmetic specially would INVENT a distinction the desugar erased and would leave `self < self` (no declared `Self: Ord`) as a live soundness hole. One rule = fewer words, whole class closed.
>
> BOTTOM LINE: one normative sentence + one help-text variant. No new syntax, no new concept. Self is a type parameter bounded by its supertraits; the parametricity rule already answers Q1–Q4.

### DevOps/Tooling

> ## Position in one line
> `self`-in-a-default-body is the trait's implicit self-type parameter, bound by the trait itself plus its declared supertraits. Treat an operator/method on `Self` EXACTLY like an operator/method on a type parameter `T` (the sibling declared-type-parameter check): licensed only when the backing trait is in the trait's supertrait closure, and checked ONCE at the trait DEFINITION site.
>
> ## Why def-site (the whole argument is diagnostic quality)
> Today the `Doubler` MVCE produces the WORST diagnostic in the language: no Blink error at all, just a raw C compiler error (`invalid operands to +`) in generated C, no `.bl` span for the real cause. That is strictly below C++'s template walls (C++ at least names the instantiation). [...]
> - Def-site: ONE error, on the `+` in the trait body, the moment it is written. No impl needs to exist. This is Rust's model [...] Fastest possible self-correction.
> - Impl-site: re-reports the same authoring mistake N times [...] the impl author gets blamed for someone else's body.
> - Mono-site: latent — an un-exercised impl never triggers it [...] This is the C++ trap and it is what we have now via C.
>
> ## Answers to Q1–Q4
> - Q1: License ONLY when the trait declares the corresponding supertrait bound (or the trait itself declares the method). [...] Not "always permitted, checked later."
> - Q2: DEFINITION site — the trait declaration, pointing at the operator/call token. Not impl, not mono.
> - Q3: YES — arithmetic on `Self` in a user trait default body becomes PERMANENTLY illegal, because `: Add` is sealed/unsatisfiable. This is intended and honest, and the diagnostic must own it: it must NOT offer `: Add` as a fix (a repair that can never compile is a cruel help line). It offers the real repairs instead (make the method required; or target a concrete numeric).
> - Q4: ALL operator families AND plain method calls on self, unified under one rule. Eq/Ord/Hash are OPEN, so `: Eq`/`: Ord` bounds are satisfiable and DO license `==`/`<`/`.hash()`. Plain `self.foo()` is licensed when a supertrait declaring `foo` is in the closure (this is exactly why `Display.display`'s default may call `self.fmt()` [...]). Arithmetic is just the sub-case where the licensing bound happens to be unsatisfiable.
>
> ## The diagnostic — recommend a DEDICATED code, `UnlicensedSelfOperation`
> Note: the declared-type-parameter check reused the generic `E0300 TypeError` for the type-parameter case [...] That reuse is a wart — a shared generic code can't drive a quick-fix. I recommend this feature introduce a dedicated code [...] The two cases are the same phenomenon.
>
> Two-layer story = ONE code, help line switches on whether the backing trait is sealed. Sealed → no `: X` fix, offer required-method/concrete-numeric. Open → offer the one-click `: X` supertrait.
>
> ## Buildability (the "must be BUILDABLE" constraint)
> [...] This is a direct extension of the declared-type-parameter check's existing `tc_tp_arith_names`/`tc_tp_arith_bits` scope stack (typecheck.bl:233): push `Self` as a type parameter whose bound set = the trait's supertrait closure, generalize the per-op arith bit into a backing-trait-membership check covering all operator families and method calls, then walk the default body's arms. the declared-type-parameter check already exempts `Self` at st==-1 (typecheck.bl:10465) — this proposal removes exactly that exemption and gives Self its real bound set. Same machinery, no new pass architecture.

---

## Phase C — silent votes (verbatim)

Ballot: **Q1** bound-required; **Q2** report at trait definition; **Q3**
sealed-arithmetic consequence intended; **Q4** uniform over operators + methods;
**Q5** sealed-case diagnostic should NOT suggest `: Add`. All six voted
**Yes/Yes/Yes/Yes/B** — unanimous 6-0.

### Systems

> Q1: Yes. Bound-required makes the guarantee set static, so codegen resolves every self-method concretely. CONCERN: a numeric-only default now needs a supertrait annotation even when the trait author "obviously meant numbers."
>
> Q2: Yes. Definition-site is sound-by-construction (impl-site supertrait enforcement guarantees mono succeeds), earliest possible error. CONCERN: needs the node_arms walk in tc that doesn't exist yet — a real checker to build, not free.
>
> Q3: Yes. `self+self` is definitionally numeric; there is no zero-cost lowering of `+` for a non-numeric Self, so the restriction is honest. CONCERN: users hitting it may read it as a compiler limitation rather than an intended dead-end unless the diagnostic is explicit.
>
> Q4: Yes. One rule over all operator families + plain method calls keeps codegen uniform; own-trait methods always licensed. CONCERN: none material — plain method calls already had to resolve statically; this just names the rule.
>
> Q5: B. Suggesting `trait Doubler: Add` points at an unsatisfiable bound (sealed), so it would send users down a dead-end; better to suggest making the method required or targeting a concrete numeric. CONCERN: option B must still name WHY (`Add` is sealed to built-in numerics) or the error looks arbitrary.

### Web/Scripting

> Q1: Yes. REASONING: definition-time errors match TS/Rust/Kotlin and beat cryptic-C for beginners. CONCERN: devs must learn to write `: Super` supertrait syntax they may not know exists.
>
> Q2: Yes. REASONING: the author who wrote the bug fixes it, never an innocent implementor or the C compiler. CONCERN: none material; only risk is a confusing message if the span points at desugared `+` instead of source `+` — must point at source.
>
> Q3: Yes. REASONING: honest and consistent with the 4-1 sealing vote; a carve-out would reopen "why can Money not use +". CONCERN: the rare arithmetic-generic-over-numerics author hits a wall and must fall back to named `.add()` — acceptable but needs the diagnostic to say so.
>
> Q4: Yes. REASONING: one uniform rule ("call on self only what Self guarantees") is one concept to learn and one code to search; own-trait methods licensed keeps the 90% default-method pattern ceremony-free. CONCERN: none — this is the safe, intuitive scope.
>
> Q5: B. REASONING: suggesting `trait Doubler: Add` sends a beginner down an unsatisfiable dead-end (no user type can ever implement it); a fix-it that cannot compile is worse than no fix-it. Suggest making the method required or targeting a concrete numeric instead. CONCERN: must still NAME why (`Add` is sealed) so they understand the wall, not just omit the suggestion silently.

### PLT

> - **Q1: Yes.** — Bound-required is the only modular, sound reading; permit-then-check-later leaks unsound bodies to cc. CONCERN: authors of numeric-only default traits must now write `: Add` they didn't before (minor migration).
> - **Q2: Yes.** — One definition-site check is total over all implementors, mirroring impl-body parametricity (2330). CONCERN: requires actually typechecking default bodies against abstract Self, which today's tc_infer_program skips — real new work, not just a diagnostic.
> - **Q3: Yes** (with precision). — For *user* types it's never legal; but `trait Doubler: Add` remains legal and satisfiable by built-in numerics, so no carve-out is needed and none should be added. CONCERN: users may read "self+self forbidden" as "arithmetic traits are second-class" — the numeric-implementor path must be documented so it doesn't feel like a dead end.
> - **Q4: Yes.** — Uniformity is the principled invariant; arithmetic is just one instance of "operation on abstract Self must be justified by a bound." CONCERN: none from PLT; Eq/Ord defaults calling `==`/`<` on self now require `: Eq`/`: Ord` to be declared, which is correct but will surface in stdlib traits.
> - **Q5: B.** — For sealed families, suggesting `trait Doubler: Add` points at a bound no user type can satisfy; the diagnostic must not send users down an unsatisfiable path. Suggest making the method required, or that only built-in numerics can back it. CONCERN: the diagnostic must special-case sealed vs open backing traits (suggest the supertrait for Eq/Ord, withhold it for Add-family) — a two-branch message, slightly more complex to author correctly.

### DevOps/Tooling

> Q1: Yes. Permit-then-check-later is the C++ instantiation-wall path; bound-required gives one actionable error. CONCERN: none material; the guarantee-set must be computed transitively or a supertrait's supertrait method silently mis-reports.
>
> Q2: Yes. Def-site is the only surface with a `.bl` span for the real cause and is sound with zero downstream re-checks. CONCERN: requires actually walking default-body arms against Self (not done today) — if the walk is skipped the rule is silently unenforced.
>
> Q3: Yes. Sealed arithmetic on abstract Self is genuinely unsatisfiable; a carve-out would just relocate the C error. CONCERN: users will read "never legal" as a compiler limitation, not a design choice — the diagnostic note must state arithmetic is sealed to numerics.
>
> Q4: Yes. One uniform rule across operators + method calls keeps the mental model and the LSP completion list consistent; own-trait methods licensed is what makes `Display.display` call `self.fmt()`. CONCERN: none.
>
> Q5: B. Suggesting `: Add` is a fix that can never compile — a dead-end help line trains users wrong and blocks a valid LSP quick-fix. Offer required-method / concrete-numeric instead. CONCERN: the diagnostic must branch on sealed-vs-open backing trait, so open cases (`: Ord`) still get the one-click supertrait fix — a single generic help string can't serve both.

### AI/ML

> Q1: **Yes** — REASONING: reuses the §3.6 "name the bound you use" rule, zero new concepts for a model to learn. CONCERN: none material; risk is only if future non-sealed traits make "bound-required" feel redundant for own-trait calls (already exempted).
>
> Q2: **Yes** — REASONING: local, nameable error is exactly the signal that lets an AI self-correct in one edit. CONCERN: def-site check must fire even for an unused default body, or models learn the wrong "it compiled" lesson.
>
> Q3: **Yes** — REASONING: matches the MVCE and sealing; a carve-out would be an unlearnable special case. CONCERN: the dead-end may confuse a model that "correctly" adds `: Add` and still can't implement it — mitigated by Q5.
>
> Q4: **Yes** — REASONING: uniform scope = one rule to generalize; per-family exceptions multiply decision points. CONCERN: none; own-trait licensing keeps the terse `ne`-calls-`eq` case clause-free.
>
> Q5: **B** — REASONING: suggesting `trait Doubler: Add` sends the model down an unsatisfiable path it will loop on; naming the real fix (make the method required, or target a concrete numeric) is the self-correctable one. CONCERN: diagnostic must clearly state Add is sealed to numerics, else the model reads "make required" as arbitrary and reverts.

### Minimalism

> **Q1: Yes**
> - REASONING: Permit-then-check-later lets bad C reach users; bound-required is one check at the source.
> - CONCERN: A trait author must now declare supertraits they previously left implicit — mild upfront friction on legitimate open-trait defaults.
>
> **Q2: Yes**
> - REASONING: The offending code lives in the default body; one def-site check beats N innocent-impl reports.
> - CONCERN: Def-site checking of default bodies is machinery the compiler doesn't run today (impl defaults are untypechecked), so the check must not accidentally over-reject valid own-trait method calls.
>
> **Q3: Yes**
> - REASONING: `trait X: Add` is unsatisfiable by the sealing vote; a carve-out would add surface to hide a soundness hole.
> - CONCERN: `self + self` reads as obviously-intended to newcomers; without an excellent diagnostic they'll perceive it as an arbitrary restriction.
>
> **Q4: Yes**
> - REASONING: Operators ARE method calls post-desugar; one uniform rule closes the whole class with fewer words than any subset.
> - CONCERN: The guarantee set must include the trait's own methods transitively through supertrait chains — a traversal bug would wrongly reject `self.eq()`-style legitimate defaults.
>
> **Q5: B**
> - REASONING: Suggesting `trait Doubler: Add` sends the user down an unsatisfiable dead-end; honest help names the real options (make the method required, or target a concrete numeric).
> - CONCERN: The diagnostic must distinguish sealed (`+` → option B) from open (`<` → suggest `: Ord`) traits, or it gives the wrong advice for the open case.

---

## Load-bearing concerns the implementation must honor

- **Transitive guarantee set.** The guarantee set must traverse the full supertrait
  chain, or a supertrait's supertrait method is silently mis-reported and legitimate
  `self.eq()`-style defaults are wrongly rejected. (devops Q1, min Q4)
- **New checker machinery.** Trait default bodies are not walked against `Self` today
  (`tc_infer_program` has no such walk); if the walk is skipped the rule is silently
  unenforced. The walk must not over-reject valid own-trait method calls. (sys Q2,
  plt Q2, devops Q2, min Q2)
- **Fire on unused default bodies.** The check runs at the definition even when no
  implementor exercises the body. (aiml Q2)
- **Sealed dead-end must be explained.** Option B must state *why* — `Add` is sealed
  to built-in numerics — or the error reads as arbitrary. (sys, web, devops, aiml, min)
- **Two-branch diagnostic.** Open backing trait (`<`→`Ord`, `==`→`Eq`) offers the
  one-click supertrait fix; sealed backing trait (`Add`-family) withholds it. A single
  generic help string cannot serve both. (plt Q5, devops Q5, min Q5)
- **Numeric-implementor path documented.** `trait Doubler: Add` is legal and
  satisfiable by the built-in numerics; the spec must say so, so `: Add` does not read
  as vacuous. (plt Q3)
- **Migration friction, accepted.** Numeric-only defaults and `Eq`/`Ord` defaults now
  need an explicit supertrait clause; this surfaces in stdlib traits and is the
  intended, honest cost. (sys Q1, plt Q1/Q4, web Q1, min Q1)

Step 8.5 AI-First review — PASS (0 fail). Learnability / Consistency / Generability /
Debuggability all STRONG (it is the existing parametricity rule reused, not a new
one); Token Efficiency neutral-to-good (own-method defaults need no clause; a
supertrait clause appears only when the body genuinely depends on it).

---

## Final spec

Recorded in `sections/03_types.md`, new subsection *Operations on `Self` in a Default
Body* (between *The `Self` Type* and *Arithmetic Traits*). In a trait default method
body, `self` has the abstract type `Self`, an implicit type parameter bounded by the
trait's guarantee set (own methods + transitive supertrait closure). An operator (per
*Operator Desugaring* §3.6) or a plain method call on `Self` is well-formed only when
its backing trait is in the guarantee set; any other operation is rejected at the
trait definition with `error[UnlicensedSelfOperation]` (E0305). The check is complete
at the definition — never re-run per implementor or per monomorphization — because
every `impl` must satisfy the trait's supertraits. The arithmetic traits
(`Add`/`Sub`/`Mul`/`Div`/`Rem`/`Neg`) are sealed to built-in numerics, so `self + self`
in a default body is licensed only for numeric-restricted traits and can never be
satisfied by a user type; the sealed diagnostic states the seal and offers
make-required / concrete-numeric rather than an unsatisfiable `: Add`. The rule is
uniform across every operator family and every plain method call on `self`; a call to
one of the trait's own methods is always licensed.
