[< All Decisions](../DECISIONS.md)

# Shadowing a Prelude Trait — Design Rationale

**Gap:** What do `==`, `<`, and `@derive(Eq/Ord)` mean inside a module that shadows the prelude `Eq`/`Ord`? Spec §10.6 lets a module-level trait shadow a prelude trait (W1010), and the local one wins in that module, but the spec did not say what happens to the forms that are defined in terms of the prelude trait. The compiler also removed the prelude trait from the whole program when any module declared the name.

```blink
trait Eq { fn eq(self, other: Int) -> Bool }
@derive(Eq)
type P { x: Int }
fn main() { assert(P { x: 1 } == P { x: 1 }) }
```

## Result

| Question | Result | Vote |
|---|---|---|
| Q1 Core design | Names that the user writes (`T: Eq`, `impl Eq for`, supertrait clauses, the `@derive` argument) resolve by scope; forms that the compiler inserts (operators, prelude bounds, the `Eq` that `@derive(Ord)` derives) use the compiler-known trait by identity; the aliased import is the only escape | 6-0 |
| Q2 Error code | New E14xx code (E1402 `NotDerivable`) for a `@derive` argument that is not a derivable compiler-known trait; E1401 keeps its field-type meaning | 6-0 |
| Q3 W1010 note | A note on every shadowed prelude trait that a desugaring uses; the spec sets the content, not the words | 5-1 (Min dissent: `Eq`/`Ord`/`Hash` only) |
| Q4 Scope | One normative §10.6 sentence: a shadow has module scope; the program-wide compiler behavior is a separate bug | 6-0 |

AI-first review: 5/5 pass. The user signed off on the tally.

**Post-vote fact.** After the vote, the moderator found that the compiler already has `E1112 UnknownDerive`, which matches the `@derive` argument by spelling and is in neither the spec nor ERROR_CATALOG.md. The user ruled: "what the code does is irrelevant, this is the SPEC. We build it right, we dont match what we just \"happened\" to build". The spec uses the code the panel voted for, E1402 `NotDerivable`. The implementation ticket removes E1112 in favor of E1402.

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in independent-proposal → debate → vote rounds. All panelist text below is verbatim.

#### Phase A — Independent proposals

<details><summary><b>Systems</b></summary>

> # Sys proposal: resolve by identity, and keep operator codegen the same in every module
>
> Hardware view: `==` on a `P` turns into one direct call, or an inlined field compare, for each monomorphized `(trait identity, type)` pair. Shadowing must not add per-module dispatch, and it must not make two traits share one C symbol or vtable. The rule below does both, and it follows from decided facts 3, 4 and 5. No new mechanism is needed.
>
> ## Proposal S1: operators and derives use the compiler-known trait; written names resolve in scope
>
> ### 1. Operators always mean `blink.core.Eq` / `blink.core.Ord`, by identity
> `a == b`, `!=`, `<`, `>`, `<=`, `>=` desugar to the compiler-known `Eq.eq` / `Ord.cmp` in every module. §3.4 *Hygiene* already says this, so this ruling only confirms it. A local `trait Eq` never takes part in operator resolution, even when it has a method named `eq`. If the operands have no `blink.core.Eq` impl, the normal "type does not implement Eq" diagnostic fires. It gets the §10.6 item-2 `note:`/`help:`, because the name `Eq` is shadowed in this module.
>
> ```blink
> trait Eq { fn eq(self, other: Int) -> Bool }    // W1010
>
> type P { x: Int }
> impl Eq for P { fn eq(self, other: Int) -> Bool { self.x == other } }
>
> fn main() {
>     let a = P { x: 1 }
>     assert(a.eq(1))       // ok: method call, resolves the local trait
>     assert(a == a)        // error: `P` does not implement `Eq` (blink.core)
> }
> ```
> ```
>   = note: `Eq` here is `trait Eq` (main.bl:1), which shadows the compiler-known `Eq` (blink.core)
>   = help: import blink.core.{Eq as CoreEq}
> ```
>
> **Cost:** zero. Operator lowering does not look at module scope, so the mono key and the C symbol for `==` on `P` are the same everywhere. If operators followed the name in scope, `p == q` could compile to two different functions depending on the module it is in. Each mono pass would then need scope context, and equality would stop being one global fact per type. That gives you a Map whose key equality differs between the module that inserts and the module that looks up, which is a correctness bug as well as a cost.
>
> The `Ord: Eq` supertrait, `Hash: Eq`, the Map/Set key bounds, `assert_eq[T: Eq + Debug]` and container equality all name the core traits by identity, because the prelude declares them. A local `Eq` cannot satisfy any of them.
>
> ### 2. Written bounds resolve by name, so `T: Eq` means the local trait
> `T: Eq` is a name the user wrote. Under §3.4 *Type Name Resolution*, the local declaration wins. A bound is part of the function's signature identity, so a caller in another module satisfies `m.Eq` only with an impl of `m.Eq`. A prelude impl does not count, because two identities are two traits.
>
> ```blink
> trait Eq { fn eq(self, other: Self) -> Bool }
>
> fn same[T: Eq](a: T, b: T) -> Bool {
>     a == b        // error: `T` is bounded by `Eq` (app.util), `==` needs `Eq` (blink.core)
> }
>
> import blink.core.{Eq as CoreEq}
> fn same2[T: CoreEq](a: T, b: T) -> Bool { a == b }    // ok
> ```
>
> **Cost:** none at runtime. The instantiation key already carries the bound. It must carry the trait's *declaration identity* (module + name), never the spelling. Otherwise `app.Eq` and core `Eq` impls for one type would produce the same mangled C name and break at link time, or worse, link silently.
>
> ### 3. `@derive(X)` resolves `X` in scope and accepts only a compiler-known trait
> `@derive(Eq)` is a name the user writes. The compiler does not insert it, so the scope rule applies, as it does in part 2. Then:
>
> - If `X` resolves to a compiler-known derivable trait, directly or through an alias, the compiler derives it.
> - If `X` resolves to a user trait (the shadowing case), that is a compile error. Derive is only for compiler-known traits in v1 (decided fact 7). The error carries the item-2 note and the help `@derive(CoreEq)` after `import blink.core.{Eq as CoreEq}`.
>
> ```blink
> import blink.core.{Eq as CoreEq, Ord as CoreOrd}
> trait Eq { fn eq(self, other: Int) -> Bool }
>
> @derive(CoreEq, CoreOrd)     // ok: derives blink.core Eq + Ord
> type P { x: Int }
>
> @derive(Eq)                  // error: cannot derive `Eq` (app.util): derive takes compiler-known traits
> type Q { x: Int }
> ```
>
> With this, the MVCE becomes an error at `@derive(Eq)` instead of compiling against a trait the reader did not mean. `@derive(Ord)` still adds the core `Eq` supertrait impl when it is missing. That supertrait is core `Eq` by identity, whatever `Eq` names locally.
>
> **Why not "derive is always core by identity" (S1-alt)?** It is also zero-cost and simpler to build. But in a module where `T: Eq` means the local trait, `@derive(Eq)` would silently mean the other one. That puts one spelling, one module and two meanings in front of a reader. I would accept S1-alt only with a mandatory warning on that line. The hard error is cheaper for readers.
>
> ### 4. Qualified access to the core trait
> Use the aliased pseudo-module import, `import blink.core.{Eq as CoreEq}`, as decided fact 2 already allows. With the alias in scope, `impl CoreEq for P`, `T: CoreEq` and `@derive(CoreEq)` are all valid. No path form such as `blink.core.Eq` in type position is needed. YAGNI: one escape hatch is enough.
>
> ### 5. Scope fix, which is the compiler bug in the ticket note
> `tc_shadowed_prelude_traits` drops the prelude `Eq`/`Ord`/`Hash`/`Clone`/`Debug` from the whole program as soon as any module declares one of those names. That breaks Map, `assert_eq` and `==` across the whole program because of one module's local name, and it is wrong under §10.6. The fix:
>
> - Key the trait table by declaration identity.
> - Resolve trait *names* in each module's scope.
> - Never unregister a prelude trait.
>
> In codegen, `cname` must mangle trait method and vtable symbols by module identity. Then `app.util.Eq.eq` and core `Eq.eq` for `P` are distinct C symbols, and no "last writer wins" can happen at link time.
>
> ## Tradeoffs (systems view)
> - **For:** operators lower the same way in every module. No mono pass needs scope context. Program-wide equality and ordering stay one fact per type, which Hash/Map soundness needs. A local trait gets its own symbols, so it cannot corrupt core dispatch.
> - **Against:** in a shadowing module, `T: Eq` with `a == b` gives an error, which surprises readers. I accept this. The diagnostic names both identities and shows the alias fix. Silently using core `Eq` from a local bound would hide a missing impl until the code was monomorphized.
> - **Compile cost:** one scoped lookup per bound and per derive argument. This is too small to measure.
>
> ## Other languages
> - **Rust:** `==` always means `core::cmp::PartialEq`, even when a local `trait PartialEq` is in scope. That is the same hygiene. `#[derive(PartialEq)]` resolves the derive macro by path, and a local *trait* cannot be derived, so a user trait in that position is an error, as in S1.
> - **Haskell:** with `import Prelude hiding (Eq)` plus a local `class Eq`, `deriving Eq` resolves to the class in scope and fails for a user class. That is the same as S1 part 3.
> - **Zig/Go:** they have no operator overloading, so the risk does not arise there, and their codegen for `==` is the same everywhere. That is the property S1 keeps.

</details>

<details><summary><b>Web/Scripting</b></summary>

> # Web/Scripting proposal: "Operators follow identity, names follow scope, derive refuses to guess"
>
> ## The 90% case
>
> Hardly anyone shadows `Eq` on purpose. When someone does, it is usually one of three things:
> - a port from another language,
> - a domain trait that happens to have that name (`trait Eq` in a constraint solver, say),
> - a mistake.
>
> So the ruling has two jobs. The common path must stay the same, and the one confusing moment must produce one clear diagnostic with a fix the user can paste. It must not produce a quiet difference in behavior. My test for each rule: can a Python or TypeScript developer tell what `==` does by reading the file? Each sub-question below gets one rule.
>
> ### Proposal 1: Operators always use the compiler-known traits
>
> `==`, `!=`, `<`, `>`, `<=` and `>=` lower to `blink.core` Eq/Ord by identity in every module. That covers `ne` and the `Ord: Eq` supertrait check on the operator path too. The §3.4 Hygiene rule (already decided, item 4) says so already; we only need to spell it out for the shadowing module. A local `trait Eq` has no effect on `==`.
>
> The diagnostic is the part that matters for usability:
>
> ```blink
> trait Eq { fn eq(self, other: Int) -> Bool }
>
> type P { x: Int }
> impl Eq for P { fn eq(self, other: Int) -> Bool { self.x == other } }
>
> fn main() {
>     assert(P { x: 1 } == P { x: 1 })
> }
> ```
>
> ```
> error[E0306]: `==` needs `P: blink.core.Eq`
>   |     assert(P { x: 1 } == P { x: 1 })
>   |            ^^^^^^^^^^^^^^^^^^^^^^^^
>   = note: `Eq` in this module is `trait Eq` (app/main.bl:1), which shadows the prelude Eq.
>           Operators always use the prelude Eq.
>   = help: import blink.core.{Eq as CoreEq}  then  @derive(CoreEq) on `type P`
> ```
>
> The W1010 warning on `trait Eq`, `trait Ord` or `trait Hash` gets one extra note line: "`==`, `<`, `@derive`, Map/Set keys and `assert_eq` still use the prelude trait." Readers learn this when they declare the trait, not three files later.
>
> **Cross-language:** Kotlin `==` always calls `equals` and Python `==` always calls `__eq__`. No import changes what the operator means, and users expect that.
>
> ### Proposal 2: `T: Eq` and other trait names resolve by scope, like every other name
>
> In the shadowing module, `fn f[T: Eq](...)`, `trait Foo: Eq` and `impl Eq for X` all name the local trait. §3.4 already says one name denotes one identity. A special case for bounds would be the clever exception we should avoid.
>
> - **Cross-module callers:** a caller in another module must satisfy the local trait. A prelude impl does not count, because they are different traits.
> - **Diagnostic on mismatch:** when the bound fails and the type does implement the prelude trait, add this note:
>
> ```
>   = note: `Eq` in `geo` is geo.Eq, not the prelude Eq; `P` implements only the prelude Eq
> ```
>
> This failure is loud and happens at compile time, so I accept it. It is the price of shadowing, and W1010 already warned about it.
>
> ### Proposal 3: `@derive(X)` resolves `X` like any other name and fails loudly when the result is not compiler-known
>
> `@derive` accepts only compiler-known traits (item 7). The shadowing module asks for `@derive(Eq)`, and `Eq` there resolves to the local trait, which cannot be derived. That is an error. The compiler does not silently derive the prelude trait.
>
> ```
> error[E????]: cannot derive `Eq`: `Eq` here is `trait Eq` (app/main.bl:1), not the prelude Eq
>   = help: to derive the prelude Eq: import blink.core.{Eq as CoreEq}  then  @derive(CoreEq)
> ```
>
> An aliased name works, because it resolves to the compiler-known identity:
>
> ```blink
> import blink.core.{Eq as CoreEq, Ord as CoreOrd}
>
> trait Eq { fn eq(self, other: Int) -> Bool }
>
> @derive(CoreEq, CoreOrd)
> type P { x: Int }
>
> fn main() { assert(P { x: 1 } == P { x: 1 }) }
> ```
>
> **Why I reject a silent prelude derive:** Rust's `#[derive(PartialEq)]` is hygienic only because macros live in their own namespace. Blink has no separate macro namespace. A reader who sees `@derive(Eq)` four lines below `trait Eq` will reasonably assume the derive targets the trait on screen. If it silently targeted another trait, that would be the guess that generates Stack Overflow questions. A one-line fix beats a silent guess.
>
> - **Supertrait auto-derive:** `@derive(CoreOrd)` auto-derives the prelude Eq supertrait, by identity, as today. It never touches the local `Eq`.
>
> ### Proposal 4: Qualified access goes through an aliased import, with no new syntax
>
> The only way to reach the prelude trait is `import blink.core.{Eq as CoreEq}`, the same mechanism already decided for types (item 2). I would not add inline paths such as `blink.core.Eq` in bound or derive position. That would give users two ways to write the same thing, which means more to learn and more lint rules. The W1010 help line already points at the alias.
>
> ### Proposal 5: Fix the scope bug
>
> The program-wide unregistering in `tc_shadowed_prelude_traits` is a bug against §10.6. Shadowing must stay per module.
> - A `trait Eq` in `geo` must not change `==`, `@derive(Eq)` or `Map[K, V]` key checks in any other module.
> - It must not change them in `geo` either, because of Proposal 1.
>
> Without this fix, a dependency can quietly break a user's `@derive(Eq)`. That is the worst kind of action at a distance in an ecosystem.
>
> ## The MVCE under these rules
>
> ```blink
> trait Eq { fn eq(self, other: Int) -> Bool }   // W1010, plus the note about operators
> @derive(Eq)                                    // error: `Eq` here is your trait; help: alias blink.core Eq
> type P { x: Int }
> fn main() { assert(P { x: 1 } == P { x: 1 }) }
> ```
>
> The program fails at the derive with a fix the user can paste. After the fix, `==` uses the prelude Eq and the program passes.
>
> ## Tradeoffs from my domain
>
> - **Pro:** every rule fits in one sentence.
>   - Operators: identity.
>   - Names: scope.
>   - Derive: name resolution, and refuse when the target is not compiler-known.
>
>   None of these rules is new. Each one applies a rule we already decided.
> - **Pro:** no silent behavior split. Every place where the two traits differ is a compile error that names both declarations.
> - **Con:** Proposal 3 adds one more error code, and code that shadows `Eq` needs an alias line to derive. I accept that cost, because shadowing `Eq` should cost something.
> - **Con:** Proposal 2 means a generic helper in a shadowing module will not accept callers' prelude-Eq types. That is correct, but some users will find it surprising, so the extra diagnostic note is mandatory, not optional.

</details>

<details><summary><b>PLT</b></summary>

> # PLT proposal: closing the shadowed-prelude-`Eq`/`Ord` gap
>
> ## Core principle: split by who wrote the name
>
> The spec already holds the rule we need. Under §3.4, a name resolves to exactly one declaration identity. Under §3.4 *Hygiene*, anything the compiler inserts refers to the compiler-known item by identity. So the ruling only has to sort each form into one of two groups:
>
> - **Compiler-inserted (hygienic, by identity):** operators, auto-derived supertraits, and prelude declarations' own bounds.
> - **User-written (resolved by lexical scope, then by identity):** `T: Eq` bounds, `impl Eq for`, `@derive(Eq)` arguments, and supertrait clauses in user code.
>
> With this split there are no special cases. Every question below follows from it.
>
> ## Proposal A (recommended): hygiene for inserted forms, scope for written names
>
> **1. `==` / `!=` / `<` / `>` / `<=` / `>=`.** These always desugar to `blink.core` `Eq.eq`/`ne` and `Ord.cmp`, by identity. §3.4 already says this ("`==`/`<` and the other operators (their traits)"), so the ruling only restates it in §10.6. A local `trait Eq` never takes part in operator dispatch.
>
> Effect soundness is the main reason this is the only acceptable answer. The prelude `Eq.eq` has a fixed signature with no effects. If `==` dispatched by spelling, a module could declare `trait Eq { fn eq(self, other: Int) -> Bool ! IO }` and make `a == b` perform IO, or change its typing rule (`other: Int`, not `Self`). The operator's typing rule would then depend on the scope at the use site. That is non-compositional: an expression's type and effects would change when someone adds an unrelated declaration.
>
> **2. `@derive(X)`.** The argument is a name the user wrote, so it resolves by ordinary scope to an identity. That identity must be one of the eight derivable compiler-known traits. If it resolves to a local trait, the program gets a new error:
>
> ```blink
> trait Eq { fn eq(self, other: Int) -> Bool }   // warning[W1010]
>
> @derive(Eq)          // error[NotDerivable]: `Eq` here is `trait Eq (app)`, not a derivable trait
> type P { x: Int }    //   note: shadows the compiler-known `Eq` (blink.core)
>                      //   help: import blink.core.{Eq as CoreEq}  then  @derive(CoreEq)
> ```
>
> The working form:
>
> ```blink
> import blink.core.{Eq as CoreEq, Ord as CoreOrd}
>
> trait Eq { fn eq(self, other: Int) -> Bool }
>
> @derive(CoreEq, CoreOrd)
> type P { x: Int }
>
> fn main() {
>     assert(P { x: 1 } == P { x: 1 })    // blink.core Eq.eq, by identity
>     assert(P { x: 1 } < P { x: 2 })
> }
> ```
>
> I reject the other option, "`@derive(Eq)` silently derives the prelude Eq". It would make one spelling (`Eq`) mean two identities in one module: the local trait inside `T: Eq` and the prelude trait inside `@derive(Eq)`. That breaks §3.4's "a type name denotes one declaration identity". The error has a mechanical fix and is honest about what the name means.
>
> **Auto-derived supertraits are compiler-inserted.** `@derive(CoreOrd)` auto-derives the supertrait of the prelude `Ord`, which is the prelude `Eq` by identity, whatever `Eq` means in the module.
>
> **3. `T: Eq` bounds.** These are user-written, so `Eq` names the local trait. A caller in another module cannot satisfy that bound with a prelude impl, because the two traits have different identities (§3.4: "different types everywhere"). Inside such a generic body, `a == b` needs the **prelude** `Eq` on `T`. A local-`Eq` bound does not give it:
>
> ```blink
> trait Eq { fn same(self, other: Self) -> Bool }
>
> fn f[T: Eq](a: T, b: T) -> Bool {
>     a == b    // error: `==` requires `T: Eq (blink.core)`; `T` is bounded by `Eq (app)`
> }             //   help: import blink.core.{Eq as CoreEq}; fn f[T: CoreEq](...)
> ```
>
> This is the existing §3.6 rule ("`<` desugars to `Ord.cmp`, but `Ranked` does not require `Ord`"), plus the §10.6 diagnostic rule 2 note.
>
> **4. Supertrait clauses and prelude signatures.** A declaration's names resolve in the scope where it is declared. So prelude `trait Ord: Eq`, `Hash: Eq`, `assert_eq[T: Eq + Debug]`, and the `Hash + Eq` bound on Map/Set keys all name the prelude `Eq`, from any module. A user `trait Ord: Eq` in a module that shadows `Eq` names the local `Eq`. This is ordinary lexical scoping, which ML signatures and Haskell class contexts both use.
>
> **5. Reaching the prelude trait.** Use the aliased import: `import blink.core.{Eq as CoreEq}`. The spec already gives this form, and §10.6 E1012 already forbids the unaliased import alongside the declaration. No new syntax is needed. Qualified method calls use the alias: `CoreEq.eq(a, b)`. When `p.eq(q)` is ambiguous between a local-trait impl and a prelude impl, it follows the existing ambiguous-method rule, which requires qualified syntax.
>
> **6. Scope of the shadow (fixes the ticket note).** A trait's identity is (declaring module, name). A local `trait Eq` changes name resolution only in its declaring module, and in modules that import it by name (which also get W1010). The current `tc_shadowed_prelude_traits` behaviour, which unregisters the prelude trait for the whole program, is unsound against §3.4: a declaration in module A changes the meaning of `==` in module B. The compiler must key compiler-known traits by identity and never unregister them.
>
> **Typing rule (informal).** In module M:
>
> - `Γ_M ⊢ a == b : Bool` iff `Γ ⊢ a : τ`, `Γ ⊢ b : τ`, and `τ : core.Eq` holds by impl or bound.
> - `Γ_M` affects only how written names resolve, never the premise `core.Eq`.
>
> **Tradeoffs**
>
> - Pro: sound, compositional, needs no new concepts, and one name has one identity per module.
> - Con: the MVCE's author gets an error at `@derive(Eq)` and must write an alias. That is the intended cost of shadowing a trait that operators depend on, and W1010 already flagged the declaration.
>
> **Cross-language.**
>
> - Haskell's `RebindableSyntax` is the opposite design: operators and `do` dispatch by the name in scope. It is opt-in per module because it makes desugaring non-hygienic. Blink has no such opt-in, so hygiene must hold.
> - Racket and Scheme hygienic macros are the model here: an expansion refers to bindings at the definition site, not the use site.
> - OCaml: a local `module Stdlib = ...` cannot change what the built-in `=` means.
>
> ## Proposal B (fallback, if the panel wants fewer moving parts)
>
> Mark the operator-backing traits (`Eq`, `Ord`, `Hash`, and the arithmetic operator traits) as **non-redefinable**, the same way the sealed method-surface traits are under §3.2.2. The MVCE becomes a single "cannot redefine `Eq`" error, and every sub-question disappears.
>
> - Pro: the smallest rule surface, with no "`T: Eq` means something else here" problem for readers or for LLM training data.
> - Con: it partly reverses the 6-0 "every prelude trait name may be declared" decision. It also takes a common domain name (`Ord` in an order-management module) away from users. In my view that cost is too high, because Proposal A is already sound.
>
> **Recommendation: A.** It adds no new theory. It applies §3.4's identity and hygiene rules, which are already normative, to the forms §10.6 left open, plus one new diagnostic (NotDerivable on a non-derivable identity) and a compiler scope fix.

</details>

<details><summary><b>DevOps</b></summary>

> # DevOps/Tooling proposal: names resolve normally, syntax uses the builtin, and the tools always show which `Eq` is in use
>
> ## Proposal A (my recommendation): "the name follows scope, the operator uses the builtin"
>
> This proposal applies one rule throughout: **anything the user spells resolves by scope, and anything the compiler inserts uses the compiler-known identity.** §3.4 *Hygiene* already decides the operators. The open items are the places where the user writes the name `Eq`. The test I use for each one: does go-to-definition on the text send you to the declaration that actually takes effect? If it does, the LSP stays truthful.
>
> **1. `==` `!=` `<` `>` `<=` `>=`.** These always use prelude `Eq.eq` and `Ord.cmp`. No name appears at the use site, so applying hygiene here hides nothing. The local trait's `eq` method has no effect on `==`. The `Ord: Eq` supertrait is prelude `Eq`.
>
> **2. `T: Eq` bounds.** `Eq` resolves by scope, so in the shadowing module it means the local trait. A caller in another module cannot satisfy that bound with a prelude impl. These are different identities (§3.4 rule 5). Each side prints with the module-qualified form that §10.6(3) already requires:
>
> ```blink
> // geo/sim.bl
> trait Eq {
>     fn eq(self, other: Int) -> Bool
> }
>
> pub fn same[T: Eq](a: T, n: Int) -> Bool { a.eq(n) }
> ```
> ```
> error[E0306]: trait bound not satisfied
>  --> app/main.bl:6:15
>   |
> 6 |     sim.same(P { x: 1 }, 1)
>   |              ^^^^^^^^^^ `P` does not implement `Eq (geo.sim)`
>   |
>   = note: `P` implements `Eq (blink.core)`; `Eq (geo.sim)` is a different trait
>           declared at geo/sim.bl:2, which shadows the compiler-known `Eq`
> ```
>
> **3. `@derive(Eq)`.** The argument is a name the user wrote, so it resolves by scope. When it resolves to a user trait, the result is **E1401 NonDerivableTrait**. It must not silently derive the prelude trait. If derive were hygienic, hovering `Eq` in the attribute would point at `trait Eq` on line 1 while the generated impl is for a different trait. The LSP would then give wrong information, which is the worst case for tooling.
>
> The ticket's MVCE then gives:
>
> ```
> warning[W1010]: name shadows compiler-known trait
>  --> main.bl:1:7
>   |
> 1 | trait Eq { fn eq(self, other: Int) -> Bool }
>   |       ^^ shadows compiler-known trait `Eq` (blink.core)
>   |
>   = note: `==` and `!=` in this module still use `Eq` (blink.core)
>   = help: to use the compiler-known trait in this module, import it under another name:
>           import blink.core.{Eq as CoreEq}
>
> error[E1401]: cannot derive `Eq`: `Eq` here is a user trait
>  --> main.bl:2:10
>   |
> 2 | @derive(Eq)
>   |         ^^ `trait Eq` (main.bl:1); @derive takes compiler-known traits only
>   |
>   = help: import blink.core.{Eq as CoreEq}, then write @derive(CoreEq)
> ```
>
> The fix can be machine-applicable (§8.6): add the import, then rewrite the derive argument. The fix picks an alias that is not already bound, the same way the E1005 help does.
>
> The fixed form:
>
> ```blink
> import blink.core.{Eq as CoreEq}
>
> trait Eq {
>     fn eq(self, other: Int) -> Bool
> }
>
> @derive(CoreEq)
> type P {
>     x: Int
> }
>
> fn main() {
>     assert(P { x: 1 } == P { x: 1 })
> }
> ```
>
> `@derive(Ord)` in a module that shadows only `Eq` is valid. `Ord` resolves to the prelude trait, and its automatic `Eq` supertrait derive uses prelude `Eq` by identity. Hover on the derive shows both impls: `impl Ord (blink.core) for P`, `impl Eq (blink.core) for P`.
>
> **4. Add a W1010 note for operator traits.** For `Eq`, `Ord`, and `Hash`, W1010 adds one line telling the user that the operators (and `Map`/`Set` keys, for `Hash`) do not follow the shadow. Without that note, the user finds out only from a confusing E0306 at a `==`. That E0306 also gets the §10.6(2) note:
>
> ```
> error[E0306]: `Q` does not implement `Eq (blink.core)`
>   |
> 9 |     if a == b {
>   |        ^^^^^^ `==` needs `Eq (blink.core)`
>   |
>   = note: `Q` implements `Eq (main)` (main.bl:1), which shadows the compiler-known `Eq`;
>           `==` always uses `Eq (blink.core)`
>   = help: import blink.core.{Eq as CoreEq}, then add @derive(CoreEq) to `type Q`
> ```
>
> **5. Qualified access.** Use the aliased import only, as already decided in §10.6. Do not add a `blink.core.Eq` path form in bound or derive position. One escape, already named in every help line, is better than two (YAGNI). `T: CoreEq` and `@derive(CoreEq)` both work.
>
> **6. Scope bug.** The ticket note says `tc_shadowed_prelude_traits` (src/typecheck.bl:10342) unregisters the prelude trait for the whole program. That breaks the spec, and the fix belongs with this ruling. A shadow affects only name lookup inside its own module. The prelude trait stays registered everywhere. Separate trait identities hold the local one and the prelude one at the same time. Any other module's `@derive(Eq)`, `==`, and `Map` keys must work the same as before.
>
> **Tooling summary.** Hover and go-to-definition always match the semantics. `blink fmt` needs no change. Completion after `@derive(` offers derivable traits that are in scope by their bound names, so `CoreEq` appears when it is imported.
>
> **Cross-language.** In Rust, operators bind to `core::cmp::PartialEq` through lang items, so a local `trait PartialEq` does not change `==`. Bounds resolve by scope, and the two-trait mismatch error is a known confusion point. rustc does not add a "different trait with the same name" note in every case, and Blink should beat it here. TypeScript LSP hover always shows which declaration a name points to. That is the property Proposal A protects.
>
> ## Proposal B (fallback, if the panel wants fewer diagnostics): `Eq`/`Ord`/`Hash` cannot be redefined
>
> Add `Eq`, `Ord`, and `Hash` to the §3.2.2 set that cannot be redefined, and report a declaration as an error with a "choose another name" help, the way reserved names are. Every question in the ticket then disappears, and so do all the two-identity diagnostics above.
>
> The cost: it goes back on part of the 6-0 shadowing decision. It also creates a second class of non-redefinable names, chosen for operator syntax rather than for sealing, which users must learn. Today `Hash` also has no operator. I prefer A, because its diagnostics are clear enough and it keeps one shadowing rule for every name. If the panel finds the cross-module E0306 too subtle in practice, B is the honest fallback.

</details>

<details><summary><b>AI/ML</b></summary>

> ## AI/ML proposal: names you write resolve by scope; syntax resolves by identity
>
> I'm proposing one rule. Once a model learns it, it can answer every sub-question in this ticket without memorising special cases.
>
> > **A trait name the programmer writes resolves by scope, like every other name. A trait the compiler inserts resolves by identity, as §3.4 Hygiene already says.**
>
> Most of this ticket is already settled by Hygiene (brief facts 3 and 4). The spec only needs to say which forms count as "written" and which count as "inserted". The table below does that.
>
> | Form in the shadowing module | Kind | Trait it means |
> |---|---|---|
> | `a == b`, `!=` | inserted | `blink.core` Eq, by identity |
> | `<`, `>`, `<=`, `>=` | inserted | `blink.core` Ord, by identity |
> | Supertrait of prelude `Ord`/`Hash` | inserted (fixed in the prelude declaration) | `blink.core` Eq |
> | Auto-derive of the Eq supertrait under `@derive(Ord)` | inserted | `blink.core` Eq |
> | Map/Set key bound, `assert_eq`'s bound | declared in another module | that module's Eq, which is `blink.core` |
> | `T: Eq` in a bound | written | the **local** Eq |
> | `impl Eq for P` | written | the **local** Eq |
> | `@derive(Eq)` | written | the **local** Eq, which is an error (see below) |
> | `trait Ord: Eq` (local) | written | the local Eq |
>
> ### Sub-question answers
>
> **1. `==` and `<`.** These always use the compiler-known Eq/Ord. In the shadowing module, a type that implements only the local `Eq` is not `==`-comparable. The error must show the identity split, per §10.6 diagnostic rule 2:
>
> ```
> error[MissingTraitImpl]: `==` needs `Eq (blink.core)`; `P` implements only `Eq (app/main)`
>   = note: `Eq` here is `trait Eq` (app/main.bl:1), which shadows the compiler-known `Eq` (blink.core)
>   = help: import blink.core.{Eq as CoreEq} and write @derive(CoreEq)
> ```
>
> **2. `@derive(Eq)`.** The argument is a written name, so it resolves by scope. §3.6.1 limits `@derive` to compiler-known traits, so naming a local trait is a new error. The MVCE would give:
>
> ```
> error[NotDerivable]: `Eq` here is `trait Eq` (app/main.bl:1), not a derivable trait
>   = note: shadows the compiler-known `Eq` (blink.core)
>   = help: import blink.core.{Eq as CoreEq}, then @derive(CoreEq)
> ```
>
> The fix is:
>
> ```blink
> import blink.core.{Eq as CoreEq}
>
> trait Eq {
>     fn eq(self, other: Int) -> Bool
> }
>
> @derive(CoreEq)
> type P {
>     x: Int
> }
>
> fn main() {
>     assert(P { x: 1 } == P { x: 1 })
> }
> ```
>
> `@derive(CoreOrd)` (after `import blink.core.{Ord as CoreOrd}`) auto-derives `blink.core` Eq, never the local `Eq`, because that supertrait impl is compiler-inserted.
>
> **3. `T: Eq` bounds.** In the shadowing module, `T: Eq` names the local trait. A caller in another module cannot satisfy it with a prelude Eq impl. These are two identities, and §3.4 already says "different types everywhere". For a prelude bound, write `T: CoreEq`.
>
> **4. Qualified access.** Use the aliased import only: `import blink.core.{Eq as CoreEq}`. Do not add a second spelling such as an inline `blink.core.Eq` type path. One escape hatch means one form for a model to learn, and the W1010 help line already teaches it.
>
> **5. Scope fix.** The shadow is per module. `tc_shadowed_prelude_traits` currently unregisters the prelude Eq/Ord/Hash/Clone/Debug for the whole program. That breaks `==`, `assert_eq` and Map keys in modules that never declared anything. The ruling should require the shadow to hold only in the declaring module and in modules that import that name, as §10.6 already says for types. This is a correctness bug, not a design choice.
>
> ### Tradeoffs from the AI/ML side
>
> - **No new decision points.** A model already has to know "written names resolve by scope" and "`?`/`for`/operators use the builtin by identity". This proposal only puts each form on the correct side of that line. Each special case such as "derive args are magic keywords" is one more fact a model must memorise, and it will get it wrong under pressure.
> - **Failures are loud.** The likely LLM mistake is to declare `trait Eq` for some unrelated reason and then write `@derive(Eq)` from habit. Under this proposal that gives a compile error with a one-line fix. Under the main alternative (below), it silently derives a different trait than the `T: Eq` bound on the next line names. Silent mismatches are the worst case for generated code because nothing tells the model to repair them.
> - **Token cost.** Zero in normal code. In the rare shadowing module, the cost is one import line plus `CoreEq` in place of `Eq`.
> - **Diagnostics teach the fix.** Each error prints `Eq (blink.core)` against `Eq (app/main)` and gives the exact import line. A model with only the error text can apply the fix in one step.
>
> ### Alternative considered: treat derive arguments as a fixed list
>
> Under this alternative, `@derive(Eq)` always means the `blink.core` Eq, whatever is in scope. The MVCE would compile and pass.
>
> I reject it. In the same module, `@derive(Eq)` and `T: Eq` would spell the same name with two meanings, and `P` would fail the module's own `T: Eq` bound with no hint of why. That is the "spelling selects behavior" situation §3.4 rules out ("Identity, not spelling, selects behavior"). I rank it second if the panel decides MVCE-compiles-as-written matters more.
>
> ### Not proposed: reserving Eq/Ord/Hash
>
> Making Eq, Ord and Hash reserved, like the scalar types, would remove the whole question. But it reverses a 6-0 decision, and the per-module rule above already keeps the risk contained. Fact 1 stands.
>
> ### Cross-language note
>
> - **Rust** works the same way. `==` uses the `core::cmp::PartialEq` lang item by identity, whatever `PartialEq` is in scope. `#[derive(PartialEq)]` and `T: PartialEq` resolve by path in scope, so a local trait of that name in a derive gives an error, not the std derive. A lot of Rust is in training data, so models already expect this split.
> - **Haskell** behaves the same way. After `import Prelude hiding (Eq)` plus a local `class Eq`, `deriving Eq` fails with "not a stock derivable class". `==` in that module refers to whatever `==` is in scope. Blink's Hygiene rule is stricter on operators, and for model accuracy that is better: an operator never changes meaning based on module context.

</details>

<details><summary><b>Minimalism</b></summary>

> # Minimalism (Min) proposal: Eq/Ord shadowing
>
> ## Position: add no new rules, write the existing rules down for this case
>
> The spec already answers every sub-question. Two rules we already ratified decide each case:
>
> - **§3.4 Name Resolution:** a name the user writes denotes one declaration identity. Inside the shadowing module that is the local declaration.
> - **§3.4 Hygiene:** syntax the compiler expands uses the compiler-known trait by identity. The text names `==` and `<` explicitly.
>
> The ticket exists because nobody applied these two rules to traits in writing. The fix is about six lines in §10.6 plus one compiler bug fix. It needs no new syntax, no new qualified-path form and no special case for derive.
>
> ### Proposal M1 (primary): "Written names resolve, inserted names are by identity"
>
> Rule per sub-question:
>
> | Form, inside the module that declares `trait Eq` | Means | Why |
> |---|---|---|
> | `a == b`, `a != b` | prelude `Eq` (blink.core) | Hygiene §3.4, already normative |
> | `< > <= >=` | prelude `Ord.cmp` | Hygiene §3.4 |
> | The supertrait of prelude `Ord` | prelude `Eq` | Resolved where the prelude declares it, not at the use site |
> | `T: Eq` written by the user | local `Eq` | Name resolution §3.4 |
> | `impl Eq for P` | local `Eq` | Name resolution |
> | `@derive(Eq)` | local `Eq`. That is an error, because derive only accepts compiler-known traits (§3.6.1) | The user wrote the name, so it resolves. Derive has no hygiene exemption |
> | `@derive(Ord)` auto-deriving its `Eq` supertrait | prelude `Eq` | The compiler inserts it, so it is by identity |
> | `Map[K, V]` keys, `assert_eq`, container `==` | prelude `Hash`/`Eq` | Their bounds were resolved in the prelude |
> | Reaching the prelude trait | `import blink.core.{Eq as CoreEq}` | This path already exists in §10.6. Add no second one |
> | Scope of the shadow | one module only | §10.6 already says "wins in its module". Making it program-wide is a compiler bug, not a spec question |
>
> The ticket's MVCE is then an error with a fix that is easy to find:
>
> ```blink
> trait Eq {
>     fn eq(self, other: Int) -> Bool
> }
>
> @derive(Eq)          // error: `Eq` here is `trait Eq` (app/main.bl:1), not derivable
> type P {
>     x: Int
> }
> ```
>
> ```
> error[NotDerivable]: `@derive` supports compiler-known traits only
>  --> app/main.bl:5:10
>   = note: `Eq` here is `trait Eq` (app/main.bl:1), which shadows the compiler-known `Eq` (blink.core)
>   = help: import blink.core.{Eq as CoreEq} and write @derive(CoreEq)
> ```
>
> The correct version:
>
> ```blink
> import blink.core.{Eq as CoreEq}
>
> trait Eq {
>     fn eq(self, other: Int) -> Bool
> }
>
> @derive(CoreEq)
> type P {
>     x: Int
> }
>
> fn main() {
>     assert(P { x: 1 } == P { x: 1 })   // prelude Eq, by identity
> }
> ```
>
> If the user writes `impl Eq for P` and then uses `==`, they get an E0300-family error: "no impl of `Eq (blink.core)` for `P`; `P` implements `Eq (app/main.bl)`". §10.6 diagnostic rules (2) and (3) already require that two-identity output. Nothing new to specify.
>
> Across modules, `fn f[T: Eq](x: T)` in the shadowing module is bound to the local `Eq`. A caller elsewhere whose type has only a prelude `Eq` impl does not satisfy it. That is §3.4: "Two types with the same name and different identities are different types everywhere." No exception.
>
> **Tradeoffs from my domain.**
> - **Cost:** zero new concepts. Derive resolves its arguments like every other written name, so a reader learns no "derive looks past scope" exception.
> - **Cost:** `@derive(CoreEq)` looks odd. It shows up only in a module that chose to shadow `Eq` and already got a W1010 warning for it. Paying the ugliness at the place that caused it is correct. Paying it as a language-wide special case is not.
> - **Combinatorics:** the operator rule is one line ("operators use the trait by identity"). It does not multiply against every trait, bound, derive and impl.
>
> **Cross-language note.** Rust is the closest model. `#[derive(PartialEq)]` resolves the name in scope (a local `PartialEq` breaks it), while `==` always goes through `core::cmp::PartialEq` by lang item. Rust has lived with exactly this split for ten years with little complaint. Go never has the question, because operators are not user-overloadable. Lua's metatables show the opposite failure: when `__eq` is looked up dynamically by name, who wins is a runtime surprise.
>
> ### Alternative M2 (rejected, listed for completeness): derive by identity
>
> Here `@derive(Eq)` always means the prelude trait, whatever is in scope. It reads nicer in the MVCE, but it adds a special case: one annotation position where a written name does not resolve. It also blocks a future in which derive opens up to user traits (a v2 extension), because `@derive(Eq)` would then change meaning. I reject it: it adds a rule to save a few characters in a rare, warned-about situation.
>
> ### Alternative M3 (subtraction, considered): reserve the core prelude traits
>
> Make `Eq`, `Ord`, `Hash` and `Clone` reserved like `Int`, so the question cannot arise. In favour: it deletes a whole class of edge cases. Against: it reopens a 6-0 decision, and the cost it removes is small once M1 exists, since M1 is about six lines that only repeat existing rules. The burden of proof sits on the change, so I do not propose it. If any other panelist's proposal needs **new** machinery to answer this ticket (new qualified-path syntax, per-module operator rebinding, derive exemptions), I would vote for M3 over that, because subtraction beats addition.
>
> ### Spec text I would add to §10.6 *Shadowing Rules*
>
> > A module that shadows a prelude trait keeps the prelude trait for every form the compiler expands: operators (`==`, `!=`, `<`, `>`, `<=`, `>=`), container equality, supertrait closure of prelude traits, and the `Eq` that `@derive(Ord)` adds. Every trait name the user writes, in a bound, an `impl` header or a `@derive` argument, resolves by §3.4 and so names the local trait. `@derive` of a non-compiler-known trait is an error. The shadow is local to its module. Other modules still see the prelude trait.
>
> ### Compiler consequence
>
> `tc_shadowed_prelude_traits` (src/typecheck.bl:10342) unregisters the prelude trait for the whole program. That breaks the existing "wins in its module" text and should become a bug ticket, not part of the ruling. Operator dispatch must look up the prelude trait by identity, never by its name `"Eq"`.
>
> **Vote intent:** M1. I would accept M3 if the alternative is new machinery. I oppose any proposal that adds a qualified-trait-path syntax (`blink.core.Eq` in type position) only for this case.

</details>

#### Phase A.5 — Mechanical dedupe (moderator)

> # Phase A.5 mechanical dedupe (moderator)
>
> Full Phase A texts: scratchpad/phaseA_{sys,web,plt,devops,aiml,min}.md (same directory as this file). Read any you want.
>
> ## Option 1 — "written names resolve by scope, compiler-inserted forms by identity"
> Proposed as primary by: sys (S1), web (Proposals 1–5), plt (Proposal A), devops (Proposal A), aiml (single rule), min (M1).
> Shared content across all six:
> - `==` `!=` `<` `>` `<=` `>=` use blink.core Eq/Ord by identity in every module; a local trait never takes part.
> - Prelude declarations' own bounds (Ord: Eq, Hash: Eq, Map/Set keys, assert_eq, container equality) name blink.core traits.
> - `@derive(Ord)`'s auto-derived Eq supertrait is blink.core Eq by identity.
> - User-written `T: Eq`, `impl Eq for`, user `trait X: Eq`, and the `@derive(X)` argument resolve by scope; in the shadowing module they name the local trait. A prelude impl from another module does not satisfy a local `T: Eq`.
> - `@derive(X)` where X resolves to a non-compiler-known trait is an error; help: `import blink.core.{Eq as CoreEq}` then `@derive(CoreEq)`.
> - The only escape is the aliased import; no new `blink.core.Eq` path form (all six).
> - The shadow holds only in the declaring module (plt, aiml: "and in modules that import that name"); the program-wide unregistration in tc_shadowed_prelude_traits is a compiler bug.
>
> ## Option 2 — reserve / make non-redefinable `Eq`, `Ord`, `Hash` (min M3 adds `Clone`; plt B adds the arithmetic operator traits)
> Listed as FALLBACK by: plt (Proposal B), devops (Proposal B), min (M3: "only if another proposal needs new machinery"). No panelist proposed it as primary.
>
> ## Rejected by its own authors (listed for completeness)
> - Derive by identity (`@derive(Eq)` always means blink.core Eq): sys "S1-alt" (would accept only with a mandatory warning), min M2 (rejected), aiml (ranks second "if MVCE-compiles-as-written matters more"), plt and web and devops reject.
>
> ## Variations flagged for debate (within Option 1)
> - V1 — Error code for `@derive` of a non-derivable identity: reuse existing **E1401 NonDerivableTrait** (devops) vs a **new code** `NotDerivable` (plt, aiml, min) vs unspecified `E????` (web) / unspecified (sys).
> - V2 — W1010 extra note for operator-backing traits: web wants the note on `trait Eq`/`Ord`/`Hash` ("`==`, `<`, `@derive`, Map/Set keys and `assert_eq` still use the prelude trait"); devops wants it for `Eq`, `Ord`, `Hash` (operators, and Map/Set keys for Hash). sys, plt, aiml, min did not propose it.
> - V3 — Where the scope fix goes: in this ruling's spec text (devops: "the fix belongs with this ruling"; aiml: "the ruling should require..."; plt §6) vs a separate bug ticket, not part of the ruling (min: "should become a bug ticket, not part of the ruling").
> - V4 — Implementation requirement wording: sys asks that trait identity (module + name) key the trait table and that C symbols for trait methods/vtables include the module. (Spec-vs-implementation placement is for the panel.)

#### Phase B — Debate (round 1; all six signalled STABLE)

Position shifts: devops withdrew Option 2 and conceded a new error code (V1); all six fallbacks to Option 2 were withdrawn; devops corrected the W1010 note so that it does not list `@derive`.

<details><summary><b>Systems</b></summary>

> # Sys — Phase B round 1
>
> **Option 1: support.** It matches my S1, and all six panelists proposed it. Operators lower the same way in every module, so no mono pass needs scope context, and equality stays one fact per type, which Map/Set soundness depends on.
>
> **Option 2: oppose.** Reserving `Eq`/`Ord`/`Hash` adds a third class of name between "reserved" and "shadows". That reopens the 6-0 shadowing decision, and it buys nothing at runtime or in codegen, because under Option 1 operators already ignore the local trait. A reserved list also grows every time a new trait backs a desugaring. Hygiene by identity scales; a reserved list does not.
>
> **V1: new code, and do not reuse E1401.** E1401 means "the trait is derivable, but a field's type does not implement it". The fix for that is on the field type. `@derive(X)` with X not derivable is a different failure, and its fix is on the derive argument. Tools and agents branch on the code, so one code with two meanings and two fixes is a real cost. The new code also closes a gap beyond shadowing: `@derive(MyTrait)` for any user trait has no spec diagnostic today. Name it `NotDerivable` (or similar). It carries the §10.6 item-2 note when the name shadows a compiler-known trait. Concession: if the panel wants fewer codes, E1401 with a distinct primary message is tolerable, but it is not my preference.
>
> **V2: support, scoped to `Eq`, `Ord` and `Hash`.** It is one extra `note:` line, printed at compile time, with no runtime cost. It tells the reader at the declaration what Option 1 means: `==`, `<`, derive, Map/Set keys and `assert_eq` still use the core trait. Other shadowable traits do not need it, because no operator uses them.
>
> **V3: split it.** The ruling's spec text must state the semantics: the shadow holds only in the declaring module (and in modules that import that name), and the prelude trait is never removed. The ticket asks this directly. The compiler change to `tc_shadowed_prelude_traits` goes in a `type:bug` ticket with an MVCE, linked to this ruling. Spec text says what is true, not how the compiler does it.
>
> **V4: concede, it is implementation.** Keying the trait table by declaration identity and including the module in trait-method and vtable C symbols belongs in the bug ticket's notes, not in sections/. The spec already says "identity, not spelling" (§3.4), and that is sufficient normative text. I withdraw V4 as spec wording.
>
> STABLE, ready to vote

</details>

<details><summary><b>Web/Scripting</b></summary>

> # Web, Phase B round 1
>
> ## Option 1 vs Option 2
>
> **Option 1.** All six of us converged on it, and each rule in it applies a rule we already decided: operators use identity (§3.4 Hygiene), and names use scope (§3.4 Type Name Resolution). Users have nothing new to learn.
>
> **Option 2: reject.** Reserving `Eq`/`Ord`/`Hash` reopens a 6-0 decision (every prelude trait name may be shadowed) to fix a case that Option 1 already makes loud. It also creates a new class of question: "why can I name my type `Option` but not my trait `Eq`?" One exception list (the sealed traits) is enough. I would keep Option 2 only as a fallback if the implementation turns out to need new machinery, and nobody has shown that it does.
>
> ## V1: error code
>
> **A new code (`NotDerivable` or similar), not E1401.** The codebase fact settles it for me. E1401 means "this field's type lacks the trait you derived". A user who searches E1401 and lands on that explanation will chase field types that are fine. One code should mean one fix. The new code's explanation can carry the alias help line. I concede `E????` in my Phase A was a placeholder.
>
> ## V2: extra W1010 note
>
> **Keep it, merged with devops:** on `trait Eq`, `trait Ord` and `trait Hash` only, W1010 adds one note line: "`==`/`<`, `@derive`, Map/Set keys and `assert_eq` still use the prelude trait". Hash names Map/Set keys explicitly.
>
> This is the cheapest point at which to teach the rule: the moment the user does the surprising thing. It adds no rule and no code, only text on a warning that already fires. If the panel wants it smaller, I accept a single note, "operators and prelude bounds still use blink.core Eq", for all three traits.
>
> ## V3: scope fix
>
> **A split, conceding most of min's point.** §10.6 already says "wins in its module"; the program-wide unregistration simply violates it.
>
> - **Ruling text:** restate the scope in one sentence, so the spec is explicit for traits, given this ticket asked exactly that.
> - **Compiler change:** a `type:bug` ticket with the MVCE (a dependency's `trait Eq` breaking `@derive(Eq)` in another module). It is not part of the spec ruling.
>
> ## V4: identity-keyed trait table / C symbols
>
> **Not spec text.** Spec text says what the language means, not how the compiler lays out tables or C symbols. sys is right that the implementation needs it; it belongs in the bug/chore ticket for V3 as an acceptance criterion: "two traits named `Eq` in different modules coexist in one program". I support recording it there.
>
> STABLE, ready to vote

</details>

<details><summary><b>PLT</b></summary>

> # PLT — Phase B round 1
>
> **Option 1 vs Option 2: Option 1.** All six panelists reached it on their own, and it adds no new theory. It applies §3.4 identity and hygiene to the forms §10.6 left open. Option 2 stays a fallback only. It would partly reverse a 6-0 decision to remove a problem that Option 1 already handles soundly. I withdraw my Proposal B unless someone shows a soundness hole in Option 1. No one has.
>
> **V1 — error code: new code, not E1401.** A diagnostic code should name one judgment. E1401 says "the trait is derivable, but a field's type does not implement it". That is a check on the type's structure. The new case says "this name does not resolve to a derivable trait at all", which is a check on how the name resolves. The two have different causes, different fixes (implement the trait on the field type vs. use an aliased import) and different `--explain` text. One code would make tools and LLM training data treat the two as one failure. I propose `E1402 NotDerivable` (or the next free code in the E14xx range), with the §10.6 rule-2 note when the name shadows a compiler-known trait. Concession: I do not care which number it gets, as long as it is a separate code.
>
> **V2 — W1010 extra note: support.** It changes diagnostic text only, not meaning, and it shows the hygiene rule at the place where users meet the surprise. Wording: list the forms that still use the prelude trait. Scope: every prelude trait that a desugaring uses (Eq, Ord, Hash, and the operator traits), not only Eq/Ord/Hash. The arithmetic operators have the same issue.
>
> **V3 — where the scope fix goes: both, split by layer.** The meaning is already in the spec: §10.6 says "wins in its module". The ruling should add one normative sentence: "A declaration that shadows a prelude trait changes name resolution only in its module, and in modules that import that name. It never changes what another module's names, operators or derives mean." The compiler's program-wide unregistration is a `type:bug` ticket (with an MVCE across two modules) that the ruling cites. On the implementation side I agree with min. On the spec sentence I agree with devops and aiml.
>
> **V4 — implementation wording: keep it out of the spec.** "Trait identity = declaring module + name" is already normative as §3.4's "one declaration identity". Keying the trait table and putting the module in C symbols are codegen details. Put them in the V3 bug ticket as acceptance criteria. sys's point is correct, but it belongs in the ticket, not in sections/.
>
> STABLE, ready to vote

</details>

<details><summary><b>DevOps</b></summary>

> # DevOps — Phase B round 1
>
> **Option 1 over Option 2.** All six of us proposed Option 1. It needs no new rule, only what §3.4 *Hygiene* and §10.6 already say, written out for `Eq`/`Ord`. Option 2 was my fallback in case the two-identity diagnostics proved too subtle. With the §10.6(3) `Name (module)` printing they are clear enough, so I withdraw Option 2. It would also make a second class of non-redefinable names that users must learn.
>
> **V1: error code. I concede to a new code.** The moderator's fact settles it. E1401 means "a field's type lacks the derived trait". If one code covered two causes, `blink explain E1401` and any tool that branches on the code would have to guess. Give it a new code, `NotDerivable`, in the E14xx block, with this message: "`Eq` here is `trait Eq` (main.bl:1), a user trait; @derive takes compiler-known traits only". The help is the aliased-import fix, and it is machine-applicable. The same code also covers `@derive(Foo)` for any trait that is not derivable. The brief says no spec diagnostic covers that today, so the code closes a second gap.
>
> **V2: W1010 note. Keep it, with corrected wording.** It costs one line, and it warns the user before the first confusing E0306 at a `==`. Web's list included `@derive`, which is wrong under Option 1: `@derive(Eq)` resolves by scope. Only the automatic supertrait from `@derive(Ord)` uses the built-in identity. Proposed wording (not normative):
> - On `trait Eq`: "note: `==`, `!=`, `assert_eq` and Map/Set keys in this module still use `Eq` (blink.core)"
> - On `trait Ord`: the same note, naming `<`, `>`, `<=`, `>=` and `sort`
> - On `trait Hash`: the same note, naming Map/Set keys
>
> The spec should require the note's content (which forms do not follow the shadow) and leave the exact wording open.
>
> **V3: the scope fix. Split it.** The ruling's spec text should add one normative sentence: "A shadow changes name lookup in the declaring module, and in a module that imports that declaration, only. Every other module still resolves the name to the compiler-known trait." §10.6 implies this, but the ticket shows that the implementation misread it, so the spec should say it outright. The code fix in `tc_shadowed_prelude_traits` goes on a separate `type:bug` ticket that depends on this ruling, with a two-module MVCE. That matches Min's position for the code and mine for the text.
>
> **V4: trait-table key and C symbols. Keep them out of the spec.** "Trait identity is module + name" already follows from §3.4 rule 5 ("a type name denotes one declaration identity"). How the trait table is keyed and how C symbols are named are codegen and implementation details. They belong in the V3 bug ticket as acceptance criteria, not in sections/. Sys's point is correct; it belongs in a different document.
>
> STABLE, ready to vote

</details>

<details><summary><b>AI/ML</b></summary>

> ## AI/ML — Phase B round 1
>
> **Option 1 vs Option 2.** I vote Option 1. All six panelists reached it on their own, and it adds no rule a model does not already need. Option 2 reverses a 6-0 decision. It also creates a new exception to "every prelude trait name may be declared": a model has to memorise which trait names are reserved, and that list would differ between proposals (Clone? the arithmetic traits?). That is a new decision point to fix a case Option 1 already handles with a clear error. I reject it.
>
> **V1, error code: a new code.** One code should mean one failure and one fix, because a model maps the code it sees to the fix it applies. E1401 today means "a field's type lacks the derived trait", and the fix is to add the trait to that field's type. The new case means "this name is not a derivable trait", and the fix is the aliased import. Putting both under one code makes `blink explain E1401` describe two unrelated repairs. Concession: the name `NonDerivableTrait` fits the new case better than the field case. If the panel prefers to reuse it, the field case should move to its own code, so that each code still keeps one meaning. I won't block on the number.
>
> **V2, extra W1010 note for Eq/Ord/Hash: support.** It costs one line, and only in the rare shadowing module. It warns at the declaration, before a model writes `==` or `@derive(Eq)` and only finds out at the point of use. Warnings that say which operators still use the prelude trait are high-value context for generated code. Keep it to Eq, Ord and Hash, the traits that operators or Map/Set keys use.
>
> **V3, scope fix: both, with a split.** §10.6 already says the declaration "wins in its module", so the spec needs at most one sentence. That sentence should say the shadow covers the declaring module and modules that import the name, never the whole program. The compiler change belongs in a `type:bug` ticket with the MVCE. I concede to min that the ruling should not carry the implementation fix.
>
> **V4, keying traits by identity: not spec text.** The spec already requires this through §3.4 ("a type name denotes one declaration identity"). How the trait table and the C symbols carry the module is a codegen detail, and spec text should not describe it. Put it on the bug ticket from V3 as an acceptance criterion: two traits named `Eq` in different modules must compile and link without a collision.
>
> STABLE, ready to vote

</details>

<details><summary><b>Minimalism</b></summary>

> # Min — Phase B round 1
>
> ## Option 1 vs Option 2
> I vote **Option 1**. My condition for Option 2 was "only if another proposal needs new machinery". No proposal does. All six agree there is no new path form, no derive exemption and no rebinding of operators per module. Option 1 only states rules we already have, so reserving names would reopen a 6-0 decision to remove a cost that is already close to zero. I withdraw M3 as a live option. It stays on record as the fallback if a later round adds machinery.
>
> ## V1 — error code
> **Use a new code, not E1401.** Given the codebase fact, E1401 today means "a field's type lacks the derived trait". That is a different cause with a different fix: add an impl to the field type, versus import the core trait under an alias. If two causes share one code, `--explain` gets worse, and so does an agent that keys its fix on the code. A code costs one row in the table. Reusing one code for two meanings is the C++ path. I would accept a reuse only if someone shows that E1401's explain text already covers both causes. It does not.
>
> ## V2 — extra W1010 note for Eq/Ord/Hash
> **Accept, scoped to Eq, Ord and Hash.** This is diagnostic text, not language surface, and it shows the one fact that surprises users (`==` ignores your trait) where they make the mistake. One `note:` line per trait. Do not widen it to every prelude trait.
>
> ## V3 — where the scope fix goes
> **I concede in part.** The ruling text must restate "the shadow is local to its declaring module (and to modules that import that name)". My proposed paragraph already says so, and I accept plt/aiml's import wording. The code change in tc_shadowed_prelude_traits is tracked as an implementation bug that the ruling makes concrete. We agree on the substance. The disagreement was only about bookkeeping.
>
> ## V4 — trait identity keys and C symbols
> **Not in the spec.** Table keys and C symbol names are lowering details. Spec text should say only what §3.4 already says: identity, not spelling. Put sys's requirement in the implementation ticket as an acceptance criterion: two traits named `Eq` in different modules must not collide in the trait table or in emitted C. That matters, but it belongs in the ticket.
>
> STABLE, ready to vote

</details>

#### Phase C — Final vote

Ballot:

> # Phase C ballot (silent vote)
>
> Final positions from Phase B round 1 are in scratchpad/phaseB1_*.md. Vote independently; do not coordinate.
>
> ## Q1 — Core design
> - **1**: Option 1 — written trait names (`T: Eq`, `impl Eq for`, user supertrait clauses, `@derive(X)` argument) resolve by scope; compiler-inserted forms (`==` `!=` `<` `>` `<=` `>=`, prelude declarations' own bounds incl. Map/Set keys, `assert_eq`, container equality, and the Eq supertrait that `@derive(Ord)` auto-derives) use the blink.core trait by identity. `@derive(X)` where X resolves to a non-derivable trait is an error with help `import blink.core.{Eq as CoreEq}` + `@derive(CoreEq)`. Aliased import is the only escape; no new path form.
> - **2**: Option 2 — make `Eq`, `Ord`, `Hash` (± Clone / arithmetic traits) non-redefinable.
>
> ## Q2 — Error code for `@derive(X)` where X is not a derivable compiler-known trait
> - **a**: reuse E1401 NonDerivableTrait.
> - **b**: a new code in the E14xx block (`NotDerivable`); it covers any non-derivable trait argument (local shadow or any user trait). E1401 keeps its field-type meaning.
>
> ## Q3 — Extra W1010 note listing the forms that do not follow the shadow
> - **a**: no extra note.
> - **b**: for `trait Eq`, `Ord`, `Hash` only; the spec requires the content (which forms keep the blink.core trait), the wording is open.
> - **c**: for every shadowed prelude trait that some desugaring uses (incl. arithmetic operator traits etc.), same content rule.
>
> ## Q4 — Scope of the shadow, and where the compiler fix goes
> - **a**: one normative §10.6 sentence: a shadow changes name lookup only in the declaring module and in modules that import that declaration; every other module still resolves the name to the compiler-known trait. The program-wide unregistration in tc_shadowed_prelude_traits goes to a separate `type:bug` ticket with a two-module MVCE; identity-keyed trait table and module-qualified C symbols are acceptance criteria on that ticket, not spec text.
> - **b**: same spec sentence, but the compiler fix is folded into this ruling's implementation ticket instead of a separate bug ticket.
>
> ## Format (per question)
> 1. Vote — option label.
> 2. Reasoning — 2–4 sentences from your domain.
> 3. Concern — one sentence on what could go wrong with the option that wins.

Tally: Q1 6-0 (1); Q2 6-0 (b); Q3 5-1 (c; **Minimalism dissent**: b); Q4 6-0 (a). Phase D was not needed (no result closer than 5-1). Sys and web changed their Q3 position from their Phase B text.

<details><summary><b>Systems</b></summary>

> # Sys — Phase C ballot
>
> ## Q1
> 1. Vote: **1**
> 2. Reasoning: Operators and prelude bounds lower to the core trait by identity in every module, so mono needs no scope context and the C symbol for `==` on a type is one global fact. Map/Set key equality cannot differ between the module that inserts and the module that looks up. Option 2 adds a reserved class that buys nothing at runtime and has to grow with every new desugaring.
> 3. Concern: In a shadowing module, `T: Eq` with `a == b` gives an error, which surprises readers, so the diagnostic must name both identities or users will think the compiler is broken.
>
> ## Q2
> 1. Vote: **b**
> 2. Reasoning: E1401's fix is on a field type, while this failure's fix is on the derive argument, and tools and agents branch on the code. The new code also covers `@derive(UserTrait)` in general, which has no spec diagnostic today.
> 3. Concern: The new code must still carry the §10.6 item-2 shadow note when the argument is a shadow, or the alias fix is invisible at the error site.
>
> ## Q3
> 1. Vote: **c**
> 2. Reasoning: I change my B1 position here. §3.6 declares `Add`, `Sub`, `Mul` and `Neg` as prelude traits that back `+ - * -x`, and §10.6 lets you shadow them. A local `trait Add` therefore gives the same surprise for `+` as a local `Eq` gives for `==`. One content rule, "the note fires for any shadowed trait that a desugaring uses", is easier to implement as a single table lookup than a hand-picked list, and it costs nothing at runtime.
> 3. Concern: The set of "traits that a desugaring uses" must be defined in one place in the spec, or the note will drift from the real desugaring list.
>
> ## Q4
> 1. Vote: **a**
> 2. Reasoning: The spec sentence states the semantics, and the program-wide unregistration is a bug that breaks `==` and Map in modules that never declared anything, so it needs its own type:bug ticket with a two-module MVCE that can be tracked and regression-tested. Identity-keyed trait tables and module-qualified C symbols are acceptance criteria, not spec text; §3.4 "identity, not spelling" already covers them.
> 3. Concern: If the bug ticket does not require the module-qualified C symbols, a local `Eq.eq` and the core `Eq.eq` for one type could still collide at link time after the typecheck fix.

</details>

<details><summary><b>Web/Scripting</b></summary>

> # Web, Phase C ballot
>
> ## Q1
> 1. Vote: **1**
> 2. Reasoning: Each rule applies a rule users already know: operators use identity, written names use scope. Every place where the two traits differ is a compile error that names both declarations, so no behavior changes silently. Option 2 adds a second exception list and a new question ("why can I shadow `Option` but not `Eq`?") to fix a case that Option 1 already makes loud.
> 3. Concern: Users will hit the alias-import step (`CoreEq`) rarely enough that they forget it, so the help line must be good enough to paste and use as written.
>
> ## Q2
> 1. Vote: **b**
> 2. Reasoning: One code should mean one fix. E1401 already means "a field's type lacks the derived trait", and reusing it for this case would send users who search the code to the wrong fix. A new code also covers `@derive(MyTrait)` for any user trait, which today has no spec diagnostic.
> 3. Concern: The new code's explanation must cover both cases (local shadow and plain user trait) without reading like two errors.
>
> ## Q3
> 1. Vote: **c**
> 2. Reasoning: I proposed Eq/Ord/Hash only, but I change to c for uniformity. A user who shadows `Add` and finds `+` ignores their trait has the same surprise as with `==`. One rule ("every shadowed trait that a desugaring uses gets the note") is easier to state, implement and learn than a list of three traits. The cost is only text on a warning that already fires.
> 3. Concern: If the wording is not short, the note becomes noise that users stop reading, so keep it to one line.
>
> ## Q4
> 1. Vote: **a**
> 2. Reasoning: The spec sentence makes the module scope explicit for traits, which is the question this ticket asked. The compiler fix is a plain violation of existing spec text, so it belongs in a `type:bug` ticket with a two-module MVCE that someone can test and close on its own. Table layout and C symbol names are implementation details, not language meaning.
> 3. Concern: The bug ticket must keep a dependency's `trait Eq` from breaking a user's `@derive(Eq)` today, so it should not wait in the backlog behind this ruling's other work.

</details>

<details><summary><b>PLT</b></summary>

> # PLT — Phase C ballot
>
> ## Q1
> 1. Vote: **1**
> 2. Reasoning: Option 1 only applies §3.4's normative identity and hygiene rules. The typing rule for `==`/`<` stays fixed in every module (premise `τ : core.Eq`), so a local declaration can never change an operator's type or effects, and one spelling keeps one identity per module. Option 2 buys simplicity by reversing a 6-0 decision, and it does not fix any soundness hole.
> 3. Concern: Readers may still expect `T: Eq` in a shadowing module to make `==` legal in a generic body, so the error for that case must give the aliased-bound fix.
>
> ## Q2
> 1. Vote: **b**
> 2. Reasoning: A diagnostic code should name one judgment. E1401 is a structural check (a field's type does not implement a derivable trait). The new case is a name-resolution check (the argument does not denote a derivable trait). The two have different causes, fixes and `--explain` text, and merging them would blur the distinction for tools and for LLM training data.
> 3. Concern: The new code must cover every non-derivable argument (user traits, effects, non-trait types), or a third, silent path will appear.
>
> ## Q3
> 1. Vote: **c**
> 2. Reasoning: Hygiene applies to every desugaring, not only Eq/Ord/Hash. A local `trait Add` has the same problem with `+` as a local `Eq` has with `==`. A rule scoped by "which desugarings use this trait" is principled and needs no special-case list to maintain. Because the spec fixes the content and leaves the wording open, this adds no new semantics.
> 3. Concern: The note's list of forms must come from one source of truth for "which desugaring uses which trait", or it will drift from the real hygiene set.
>
> ## Q4
> 1. Vote: **a**
> 2. Reasoning: The scope sentence is semantics and belongs in §10.6, because it makes the existing "wins in its module" text exact for traits. The program-wide unregistration breaks §3.4 today, so it is a bug with its own MVCE and a red/green test, separate from new feature work. Table keys and C symbol names are codegen details and do not belong in sections/.
> 3. Concern: If the bug ticket is not wired as a blocker of the ruling's implementation ticket, the spec will claim per-module scope while the compiler stays program-wide.

</details>

<details><summary><b>DevOps</b></summary>

> # DevOps — Phase C ballot
>
> ## Q1
> 1. Vote: **1**
> 2. Reasoning: With Option 1, hover and go-to-definition always match the semantics. Each name the user writes points to the declaration that takes effect. The operators have no written name, so hygiene hides nothing from the user. Every failure case already has a clear diagnostic shape: `Name (module)` printing, the §10.6(2) note, and the aliased-import help. We do not need a second class of non-redefinable names.
> 3. Concern: The cross-module E0306 (`P` implements `Eq (blink.core)` but not `Eq (geo.sim)`) is still confusing for users if an implementation leaves out the "different trait, same name" note.
>
> ## Q2
> 1. Vote: **b**
> 2. Reasoning: One code must mean one cause, or `blink explain`, the LSP code actions and CI filters that branch on the code have to guess. E1401 already means "a field's type lacks the trait". A new `NotDerivable` code also closes the separate gap where `@derive(Foo)` for any user trait had no specified diagnostic.
> 3. Concern: Each tool that matches on E1401 today keeps working, but the new code needs its own `diag_explain` entry and its own fix, or users get a bare error.
>
> ## Q3
> 1. Vote: **c**
> 2. Reasoning: The user is confused in the same way whether they shadow `Eq` and `==` ignores it, or shadow the trait behind `+` or `for` and those ignore it. A rule keyed on "some desugaring uses this trait" is a single table lookup in the compiler. It is easier to keep correct than a hand-picked list that drifts when the language adds a new desugaring. The content requirement stays the same; only the coverage grows.
> 3. Concern: If the note lists every desugaring for a heavily used trait, it can get long. The wording must stay at one line per trait.
>
> ## Q4
> 1. Vote: **a**
> 2. Reasoning: The spec sentence is the language rule, and it belongs in the ruling. The fix to `tc_shadowed_prelude_traits` is a compiler bug with its own failing two-module test, so it should follow the normal `type:bug` path (red test, then fix, then ci). Implementation details such as how the trait table is keyed and how C symbols are named do not belong in sections/.
> 3. Concern: The bug ticket must be linked as a dependency of the ruling's implementation. Otherwise the spec text lands while the program-wide unregistration stays in place, and other modules keep breaking.

</details>

<details><summary><b>AI/ML</b></summary>

> ## AI/ML — Phase C ballot
>
> ### Q1
> 1. Vote: **1**
> 2. Reasoning: One rule, "written names by scope, inserted forms by identity", answers every sub-question, and a model already needs that rule for `?`, `for` and `..`. Option 2 adds a list of reserved trait names to memorise, and it reverses a 6-0 decision when no case needs that. The wrong use gives a loud error with a one-line fix, never a silent change in meaning.
> 3. Concern: Models trained on code that has no shadowing will write `@derive(Eq)` in a shadowing module from habit, so the error's help line must give the exact import and the `@derive(CoreEq)` form.
>
> ### Q2
> 1. Vote: **b**
> 2. Reasoning: A model maps the code it sees to the fix it applies, so each code must mean one failure and one fix. E1401's fix is to give a field's type the trait. The new case's fix is to name a derivable trait, or to use the aliased import. Covering every non-derivable argument under one new code also keeps the rule simple: "`@derive` takes compiler-known derivable traits only."
> 3. Concern: The names `NonDerivableTrait` (E1401) and `NotDerivable` are close enough to confuse, so the explain text for each should say which case it is not.
>
> ### Q3
> 1. Vote: **c**
> 2. Reasoning: A rule is easier to learn than a hand-picked list: "if a desugaring uses the trait you shadow, W1010 says which forms still use the builtin." With b, a model would have to know why `Add` gets no note when `Eq` does, and there is no good answer. The note fires only in the rare shadowing module, so the token cost is negligible.
> 3. Concern: The set of desugarings that use a trait can grow, so the note's content must come from one table in the spec, or it will drift from the real list.
>
> ### Q4
> 1. Vote: **a**
> 2. Reasoning: The spec needs only the one normative sentence on scope. The compiler bug is its own failure, with its own MVCE, and a separate ticket keeps its test named for what it proves. Identity keying and C symbols are implementation, not spec.
> 3. Concern: Until the bug ticket lands, the compiler stays program-wide and contradicts the new sentence, so the bug ticket should be P1 and block release of this ruling.

</details>

<details><summary><b>Minimalism</b> <i>(dissent on Q3)</i></summary>

> # Min — Phase C ballot
>
> ## Q1 — Core design
> 1. Vote: **1**
> 2. Reasoning: Option 1 adds no concept. It writes down what §3.4 Name Resolution and §3.4 Hygiene already require for traits. Option 2 removes a small edge-case cost by reopening a 6-0 decision, and that trade is worth it only when the alternative brings new machinery. This one does not.
> 3. Concern: users will find `@derive(CoreEq)` odd, and someone will later propose a derive-by-identity exemption to "fix" it. That is the rule the panel rejected here.
>
> ## Q2 — Error code
> 1. Vote: **b**
> 2. Reasoning: one code should mean one cause with one fix. E1401's field-type cause ("add an impl to the field's type") and this cause ("you named a trait that is not derivable") need different fixes, so one code would make `--explain` and code-keyed agent fixes worse. A new row in the code table costs less than an overloaded meaning.
> 3. Concern: the new code could drift into a catch-all for any derive problem. Its explain text must keep it to "the argument does not name a derivable compiler-known trait".
>
> ## Q3 — Extra W1010 note
> 1. Vote: **b**
> 2. Reasoning: this is diagnostic text, not language surface. It shows the one surprising fact (`==` ignores your trait) where the user makes the mistake. Keep it to Eq, Ord and Hash, where the surprise happens in practice. Do not widen it to every trait that some desugaring touches: each extra trait adds spec text that someone must maintain, for little benefit.
> 3. Concern: if the note's listed forms are spelled out in the spec, they can drift out of date as desugarings change. The content rule should point to §3.4 Hygiene, not keep its own list.
>
> ## Q4 — Scope and compiler fix
> 1. Vote: **a**
> 2. Reasoning: the spec sentence states the language rule. The program-wide unregistration is a defect against text that already exists, so it gets a `type:bug` ticket with a two-module MVCE and a failing test first. Identity-keyed tables and C symbols are lowering details and belong as acceptance criteria, not spec text.
> 3. Concern: if the bug ticket is not linked as a blocker of the ruling's implementation, the spec could say "local" while the compiler stays program-wide.

</details>

### Final Spec

```blink
import blink.core.{Eq as CoreEq}

trait Eq {
    fn eq(self, other: Int) -> Bool
}                                    // warning[W1010] + note: `==`, `!=`, `assert_eq`
                                     // and Map/Set keys still use Eq (blink.core)

@derive(CoreEq)                      // @derive(Eq) here is E1402 NotDerivable
type P {
    x: Int
}

fn same[T: CoreEq](a: T, b: T) -> Bool {
    a == b
}
```

- Names that the user writes resolve by scope: bounds, `impl` heads, supertrait clauses, the `@derive` argument.
- Forms that the compiler inserts use the compiler-known trait by identity: operators, prelude declarations' own bounds, `assert_eq`/`assert_ne`, container equality, and the `Eq` supertrait that `@derive(Ord)` derives.
- `import blink.core.{X as Y}` is the only way to name the builtin in a shadowing module. No `blink.core.Eq` path form.
- `@derive(X)` where X is not a derivable compiler-known trait by identity is E1402 `NotDerivable`; for a shadow it has the §10.6 note and the aliased-import help.
- W1010 on a shadowed trait that a desugaring uses has one note that names the forms that still use the builtin. The list comes from §3.4 *Hygiene* and the *Prelude Traits* table, never from a separate list. `@derive` is never in it.
- A shadow has module scope: the declaring module and modules that import the declaration. The compiler's program-wide removal of the prelude trait is a bug, with its own ticket.

Spec: §10.6 *Shadowing a Prelude Trait* (07_trust_modules_metadata.md), §3.4 *Hygiene* and §3.6.1 *Derive Mechanics* (03_types.md), ERROR_CATALOG.md E1402.
