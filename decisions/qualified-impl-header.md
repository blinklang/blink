[< All Decisions](../DECISIONS.md)

# Qualified Names in Impl Headers — Design Rationale

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated
in independent-proposal → debate → vote rounds. The gap: the spec never showed or forbade a
module-qualified trait (`impl lib.Tr for W`) or receiver type (`impl Sh for lib.Pt`) in an impl
header, and the parser rejected both at the dot, while a bound (`U: lib.Tr`) and a type position
(`lib.Pt`) accepted a qualified name. The ticket asked: allow it, or say in the spec that an impl
header names its trait bare and the file must select it.

#### Moderator facts

Facts the moderator gave every seat in the Phase A brief:

- §10.1 *Qualified Access* (sections/07_trust_modules_metadata.md:2027): "Qualified access works for functions (`auth.login()`), types (`auth.Token`), and constants (`auth.MAX_RETRIES`)." Selective imports do not restrict qualified access; every import binds its qualifier. The list does not name traits.
- §3b (sections/03b_contracts.md:820): a `type`, a type alias, a `trait` and an `effect` share one namespace (§10.6 *Shadowing Rules*).
- §3.6 *Impl visibility* (sections/03_types.md:5062-5066): "No syntax imports an impl." An impl in `T`'s package goes with the value. Any other impl needs its trait in scope: "A trait is in scope when the module declares it, when a selective import binds its name (`import ext.{Extra}`), when the prelude gives it (§10.6), or when it bounds the receiver's type parameter. A whole-module import (`import ext`) does not put the traits of `ext` in scope for method calls. ... The qualified call `ext.Extra.zap(x)` works with `import ext`."
- §3.4 (sections/03_types.md:2832): "A trait name in a bound (`T: Ord`) or an impl header does not occupy a type position — it constrains a type parameter rather than denoting a type (§3.6)."
- §3.6 *Orphan Rule* / *Impl Placement* (03_types.md:4945, :5036): `impl Trait for Type` is allowed only in the package that defines `Trait` or `Type`; within the package any module may hold it. The *Impl Placement* example uses `import models.{User}` then `impl Display for User`.
- §3c *Impl-Qualified Calls* (sections/03c_protocols.md:723): `(Alpha for Widget).make()` names a trait and a type. The spec examples use bare names only.
- No spec text or example shows a module-qualified name in an impl header, in either the trait slot or the receiver slot, and none forbids it. No spec text shows a qualified bound (`[U: lib.Tr]`) either.

**Compiler today (build/gen1/bin/blink, probe package)**
- `impl lib.Tr for W { ... }` → `error[UnexpectedToken]: expected {, got .`, then a cascade (`unexpected `Tr` in impl `lib for ``).
- `impl Sh for lib.Pt { ... }` (local trait, receiver type from a sibling module) → the same parse error at the dot, plus `unknown type `lib` in receiver of impl `Sh``.
- `fn show[U: lib.Tr](u: U) -> Str { u.name() }` compiles and runs (qualified bound works).
- `let p: lib.Pt = lib.Pt { x: 2 }` works (qualified type in a type position).
- `import lib.{Tr}` then `impl Tr for W` works.
- `lib.Tr.name(w)` (qualified trait call, which §3.6 says works) gives an internal compiler error (NoTypeForNode). A bug ticket is filed; treat it as a bug, not as a design input.
- `(Mk for W).make()` does not parse yet (the impl-qualified call has an open implementation ticket).

#### Phase A — Independent proposals

- **Systems:**

  No runtime cost either way. A trait name resolves at compile time to one identity (defining module + name); impl symbols come from that identity, not from the spelling. `impl lib.Tr for W` and `import lib.{Tr}` + `impl Tr for W` must give the same symbols, dispatch and mono instances. The spelling must never reach codegen.

  **sys-1 (recommended): one path rule for every trait and type slot**

  Trait and receiver slots take the form a type position takes: a bare name, or `q.Name` with `q` a §10.1 qualifier (an import's binding name or alias). This holds for both impl header slots, bounds, `where` constraints and the impl-qualified call.

  ```blink
  import lib

  type W {
      v: Int
  }

  impl lib.Tr for W {
      fn name(self) -> Str { "w{self.v}" }
  }

  trait Sh {
      fn sh(self) -> Str
  }

  impl Sh for lib.Pt {
      fn sh(self) -> Str { "pt{self.x}" }
  }

  fn show[U: lib.Tr](u: U) -> Str { u.name() }

  fn main() {
      let w = W { v: 1 }
      io.println(show(w))
      io.println(lib.Tr.name(w))
      io.println((lib.Mk for W).make().name())
  }
  ```

  **Scope.** A header is a use of the name, not a binding. `impl lib.Tr for W` does not put `Tr` in scope, and §3.6 rule 2 stays as written: only a declaration, a selective import, the prelude or a bound put a trait in scope. Thus `w.name()` in this file needs `import lib.{Tr}` or the qualified call `lib.Tr.name(w)`. Scope stays readable from import lines alone, with no scan of impl headers. Rust does the same: `impl fmt::Display for X` does not let you call `x.fmt(..)` without `use std::fmt::Display`.

  **Orphan rule.** No change; it tests identity, not spelling. `impl Tr for W` plus `impl lib.Tr for W` is a duplicate impl.

  **Diagnostics** (existing codes where they exist):
  - `impl nolib.Tr for W` with no `import nolib`: undefined qualifier at `nolib`, help: `import nolib`.
  - `impl lib.Hidden for W` with `Hidden` not `pub`: the visibility error that `lib.Hidden` gives in a type position.
  - `impl lib.Pt for W` (`Pt` is a type): "`lib.Pt` is a type, not a trait" at the name. Today the parser gives `expected {, got .` and a cascade; that message must go in any outcome.
  - A path with more than one qualifier segment (`impl a.b.Tr for W`): the same error that `a.b.Tr` gives in a type position.

  **Spec text.** §10.1: "Qualified access works for functions, types, traits, effects and constants," plus one line: "A qualified name works wherever its bare form works: an impl header, a bound, an impl-qualified call." §3.6 *Impl visibility*: "An impl header that names a qualified trait does not put the trait in scope."

  **Tradeoffs.** The slots reuse the type path production and the qualified-bound nr check. Two modules that each export `Encode` need no alias. Cost: a second spelling of a header, but one users already write in bounds and types.

  **sys-2 (rejected): bare names only, say so in the spec**

  Same codegen, but bounds and headers then differ, and a user must add a selective import (or alias) only to write a header. Haskell (`instance Q.Show T`), Rust and Swift (`extension T: Mod.Proto`) all take the qualified form. No codegen reason to refuse it.

- **Web/Scripting:**

  **web-1 (recommended): "`module.Name` works wherever a name works"**

  One rule a JS/Python dev already has in their head: if `lib.Pt` works in a type position and `lib.Tr` works in a bound, it works in an impl header too. Allow a qualified name in both header slots, in a bound, and in the impl-qualified call.

  ```blink
  // src/main.bl, same package as src/lib.bl
  import lib

  type W { n: Int }

  impl lib.Tr for W {
      fn name(self) -> Str { "w{self.n}" }
  }

  trait Sh {
      fn sh(self) -> Str
  }

  impl Sh for lib.Pt {
      fn sh(self) -> Str { "pt {self.x}" }
  }

  fn show[U: lib.Tr](u: U) -> Str { u.name() }

  fn main() {
      let w = W { n: 1 }
      print(show(w))
      print(w.name())             // works: the impl lives in W's package (§3.6 rule 1)
      print((lib.Mk for W).make().name())
  }
  ```

  **Scope: the header changes nothing.** `impl lib.Tr for W` does not put `Tr` in scope as a bare name. Reasons:
  - §10.1 says only a selection binds a bare name. A header that silently binds one is a second, hidden import form. That is the kind of "why does this work in file A but not file B" question that fills Stack Overflow.
  - It rarely matters. The orphan rule puts every impl in the trait's package or the type's package. When the impl sits with `W`, rule 1 already gives `w.name()` at every call site where `Tr` is visible. Only a foreign receiver in the trait's package needs `import lib.{Tr}` for method calls, and that is the same rule users meet today.

  **Orphan rule:** unchanged. It checks where the trait and type are defined, not how the header spells them. `impl ext.Display for ext.Thing` in a third package is E-orphan, the same as the bare form.

  **Diagnostics** (no new codes; reuse name resolution):
  - `impl lib.Nope for W` → "unknown trait `Nope` in module `lib`", label on `Nope`.
  - `impl lib.Pt for W` → "`lib.Pt` is a type, not a trait; an impl header names a trait before `for`".
  - `impl lib.Tr for W` with no `import lib` → "unknown module `lib`" + help: "add `import lib`".
  - Private trait → the existing visibility error.
  The current "expected {, got ." cascade must go either way; it is the worst result possible.

  **Spec text:**
  - §10.1 *Qualified Access*: "Qualified access works for functions, types, traits, effects and constants. A qualified name may appear wherever the bare name may: expressions, type positions, bounds, impl headers and impl-qualified calls."
  - §3.6: one sentence + the example above: "Either slot of an impl header may use a qualified name (§10.1). Spelling does not change scope: the header does not bind the bare trait name for method calls."

  **Tradeoffs:** Zero new concepts; it removes an exception. Cost is parser work in the header and the impl-qualified call, which must happen anyway for bounds parity. Two spellings of one header exist, but `blink fmt` need not pick; both read clearly.

  **Cross-language:** Rust `impl fmt::Display for X` is the most common impl line in Rust. TypeScript `class X implements ns.Iface`, Python `class X(mod.Base)`, Kotlin `class X : pkg.Iface`, Swift `extension X: Mod.Proto`, and Haskell `instance Q.Show T` all accept it. No mainstream language forces a bare trait in this slot. A user from any of them will type `impl lib.Tr` first.

  **web-2 (fallback, oppose): forbid and say so**

  If the panel forbids it, the parser must still recognize the dot and give one error: "an impl header names its trait bare; add `import lib.{Tr}`", with a fix-it. I oppose this: it makes users edit the import list to write one line, and it adds an exception to a rule (qualified names) that holds everywhere else.

- **PLT:**

  **plt-1: one "trait reference" form, used in every trait slot; naming binds nothing**

  **Rule.** The spec defines one production, *trait reference* = `Name` or `q.Name`, where `q` is a name an `import` binds (the same qualified form §10.1 gives a type). Every slot that names a trait takes a trait reference: a bound (`[U: lib.Tr]`), the trait slot of an impl header (`impl lib.Tr for W`), a supertrait list, and the impl-qualified call (`(lib.Mk for W).make()`). The receiver slot of an impl header is a type position, so §10.1 already allows `impl Sh for lib.Pt`; today's parse error there is a bug, not a design question.

  ```blink
  import lib

  type W {
      v: Int
  }

  impl lib.Tr for W {
      fn name(self) -> Str { "w{self.v}" }
  }

  trait Sh {
      fn shape(self) -> Str
  }

  impl Sh for lib.Pt {
      fn shape(self) -> Str { "pt" }
  }

  fn show[U: lib.Tr](u: U) -> Str { u.name() }

  fn main() {
      let w = W { v: 1 }
      io.println(show(w))
      io.println(lib.Tr.name(w))
      io.println((lib.Mk for W).make().name())
  }
  ```

  **Typing argument.** Name resolution maps `lib.Tr` and a selected `Tr` to the same trait identity. Every later judgment (coherence, the orphan rule, impl lookup, bound entailment) is stated over that identity, never over spelling. So the change is purely at the resolution layer and is sound by construction: there is no program whose meaning differs between `impl lib.Tr for W` and `import lib.{Tr}` + `impl Tr for W`. Today the bound slot accepts the qualified form and the header slot rejects it. That is a non-compositional grammar: the same trait has two different "names" by position. A user who writes `[U: lib.Tr]` and then the matching impl hits an arbitrary wall.

  **Scope: the header changes nothing.** §3.6 says only a selection binds a bare name. Naming `lib.Tr` in a header is a use, not a binding, so `Tr` does not enter scope. This matters less than it looks: for `impl lib.Tr for W` with a local `W`, rule 1 already makes the impl a candidate wherever `Tr` is visible, so `w.name()` works anyway. For `impl lib.Tr for lib.Pt` inside `lib`'s package, the same holds. A header that silently binds would make scope depend on which impls a file holds. That is a non-local effect, and I oppose it.

  **Orphan rule.** Unchanged; it checks the resolved trait's and type's defining packages. `impl ext.Tr for ext.Pt` in a third package fails with the same orphan diagnostic as the bare form.

  **Diagnostics for forms that stay illegal.**
  - `impl lib.Pt for W` → the existing "`Pt` is a type, not a trait" error (one namespace, §3b), now pointing at `lib.Pt`.
  - `impl nomod.Tr for W` with no such import → the existing unknown-qualifier error that `nomod.Pt` gives in a type position.
  - `impl lib.Hidden for W` with a non-`pub` trait → the existing visibility error.
  No new codes; the qualified form reuses the qualified-type paths.

  **Spec text.** §10.1: "Qualified access works for functions, types, traits (in a bound, an impl header, a supertrait list and an impl-qualified call), and constants." Add one sentence: "Naming a trait by its qualifier does not bring it into scope for method calls (§3.6)." §3.6 *Impl Placement*: add the qualified example beside the selected one. §3.4 note at :2832 stays true.

  **Cross-language.** Rust: `impl fmt::Display for X` is the norm, and the path form is uniform across bounds, impls and `<X as fmt::Display>::fmt`; naming the path does not bring `Display`'s methods into scope (a `use` does). Haskell: `instance Q.Show T` is legal with `import qualified M as Q`; instance heads take qualified class names exactly like constraints. Swift: `extension Foo: ModuleA.Proto` is legal. OCaml functor/module types qualify freely. No mainstream language with qualified bounds forbids a qualified instance head.

  **plt-2 (rejected by me): forbid in the header, require a selection**

  It is sound but non-compositional: it keeps a slot-dependent grammar and makes `(lib.Mk for W)` and `[U: lib.Tr]` legal while the header is not, or forces us to also forbid the qualified bound, which breaks working code. I list it only for completeness.

- **DevOps:**

  **devops-1: one name grammar for every trait and type slot (recommended)**

  Every slot that names a trait or a type takes the same form: a bare name or `qualifier.Name`. That covers the impl header (both slots), a bound, and the impl-qualified call head. The qualifier is a leaf or an `as` alias, as in §10.1.

  ```blink
  import lib

  type W { n: Int }

  impl lib.Tr for W {
      fn name(self) -> Str { "w" }
  }

  trait Sh {
      fn shape(self) -> Str
  }

  impl Sh for lib.Pt {
      fn shape(self) -> Str { "pt" }
  }

  fn show[U: lib.Tr](u: U) -> Str { u.name() }

  fn main() {
      let w = W { n: 1 }
      println(show(w))
      let m = (lib.Mk for W).make()
  }
  ```

  **Scope.** A header that names `lib.Tr` changes nothing about file scope. Inside that impl block, the trait counts as in scope for `self`, the same way a bound does. Outside the block, `w.name()` needs `import lib.{Tr}`, as §3.6 rule 2 says now. Scope that comes only from imports gives the LSP and the reader one place to look. If a header 300 lines down could change method lookup, "why does `w.name()` resolve here?" would have no answer the editor can show. The E0505 help already gives the fix: change `import lib` to `import lib.{Tr}`.

  **Orphan rule.** No change. The check runs on the resolved trait and type, not on how the source spells them.

  **Diagnostics.** The parser always reads a path in these slots. The resolver decides what is legal. This removes today's cascade (`unexpected Tr in impl lib for`) and gives one error at the right span:
  - `impl lib.Pt for W`: E0740 `QualifiedHeadNotTrait`, reused. Note: "`lib.Pt` is a type". If the receiver is a trait, the help gives the swapped header.
  - `impl lib.Nope for W`: unresolved name, with "did you mean `lib.Tr`" over the `pub` traits of `lib`.
  - `impl std.fmt.Display for W`: the existing leaf-only error from §10.1, with help `fmt.Display`.
  - A private trait: the existing visibility error, which names the module that declares it.

  **Tooling.** Completion after `impl lib.` lists only the `pub` traits of `lib`. Completion after `for lib.` lists only its types. Go-to-definition and rename follow the resolved item, so a rename of `Tr` updates qualified headers too. `blink fmt` keeps the spelling the user wrote. It never adds or removes a qualifier, because doing so would need an import change.

  **Spec text.**
  - §10.1 rule 1: "Qualified access works for functions, types, traits, effects and constants. A qualified trait or type name may appear in any slot that takes a bare one: a type position, a bound, an impl header, and the head of an impl-qualified call."
  - §3.6 *Impl visibility* rule 2: add "An impl header does not put its trait in scope outside its own block."
  - §3c: add one qualified example of `(lib.Mk for W)`.

  **Tradeoffs.** Small parser change, no new diagnostic code, and one fewer special case to teach. The cost is two ways to spell one header. The rule "the spelling never changes scope" keeps that harmless.

  **Cross-language.** Rust accepts `impl fmt::Display for X` and treats it as a path like any other. rust-analyzer handles it with no special case. Haskell accepts `instance M.C T` in instance heads. Swift accepts `extension X: Mod.Proto`. No mainstream language forbids a qualified name in this slot, so a ban would surprise users and AI tools.

  **devops-2: forbid, say so (fallback, I oppose)**

  If the panel bans it, the parser must still read the path and give one error: "an impl header names its trait bare; add `import lib.{Tr}`", with a machine-applicable fix. Bounds and type positions already accept qualified names, so the ban is a special case that tooling must explain each time.

- **AI/ML:**

  **aiml-1: One rule — "a qualified name works wherever its bare name works"**

  Allow `m.Name` in every slot that takes a trait or type name: the impl trait slot, the impl receiver slot, a bound, and both halves of an impl-qualified call. Scope rules do not change.

  ```blink
  import lib

  type W { n: Int }

  impl lib.Tr for W {
      fn name(self) -> Str { "w{self.n}" }
  }

  trait Sh {
      fn shape(self) -> Str
  }

  impl Sh for lib.Pt {
      fn shape(self) -> Str { "pt {self.x}" }
  }

  fn show[U: lib.Tr](u: U) -> Str { u.name() }

  fn main() {
      let w = W { n: 1 }
      println(w.name())
      println(show(w))
      let m = (lib.Mk for W).make()
  }
  ```

  `w.name()` works with no selective import. The reason is rule 1 of §3.6 (the impl lives in `W`'s package), not the header. The header does not put `Tr` in scope. A value of a type from a third package still needs `import lib.{Tr}` for `x.name()`, exactly as today.

  **Why, from the model-generation side:**
  - **Fewer decision points.** Today a model has to know three different answers: a qualified name works in a type position, works in a bound, fails in an impl header. That gap is not deducible from the spec; a model must memorize it. One uniform rule ("`m.X` is a name; use it anywhere `X` fits") is learnable from §10.1 alone.
  - **Training prior.** Rust `impl fmt::Display for X` and `impl serde::Serialize for X` appear in a huge amount of training code. Models will write `impl lib.Tr for W` in Blink. Today that gives a parse error plus a cascade (`unexpected Tr in impl lib for`), the worst kind of feedback for a repair loop. Allowing it costs zero tokens and removes a common generation failure.
  - **Token cost.** For a one-off impl, `import lib` + `impl lib.Tr for W` adds no line; the bare form forces an extra `import lib.{Tr}` edit at the top of the file, which is a non-local edit that models get wrong more often than local ones.
  - **Scope stays simple.** If the header put `Tr` in scope, a model would need to know that an impl header is a fourth way to scope a trait, and that moving the impl to another file changes method resolution elsewhere in this file. That is action at a distance. Rejected.

  **Orphan rule:** unchanged. It checks the package that defines the resolved trait and type, not how the header spells them. `impl lib.Tr for W` and `impl Tr for W` are the same impl.

  **Diagnostics** (for forms still invalid):
  - `impl lib.Nope for W` → the same "unknown trait" error a bare name gives, with the qualifier in the span: `error: module `lib` has no pub trait `Nope``.
  - `impl lib.Pt for W` (type, not trait) → `error: `lib.Pt` is a type, not a trait`.
  - `impl fs.Tr for W` with no `import fs` → the existing unknown-module error, with a fix-it `add import fs`.

  **Spec text:**
  - §10.1: "Qualified access works for functions, types, traits, effects, and constants" — and add one sentence: "A qualified name is valid wherever its bare name is valid: a type position, a bound, an impl header, and an impl-qualified call."
  - §3.6: one sentence after *Impl visibility* rule 2: "An impl header does not put its trait in scope; `impl lib.Tr for W` and `impl Tr for W` declare the same impl." Add `impl lib.Tr for W` to the *Impl Placement* example.

  Cross-language: Rust (`impl fmt::Display`), Haskell (`instance M.Show T`), Swift (`extension X: Mod.Proto`) and Kotlin (`: pkg.Iface`) all allow a qualified trait in the header. No mainstream language forbids it; forbidding it in Blink makes Blink the one outlier a model has to special-case.

  **aiml-2 (fallback, oppose): forbid and document**

  If the panel forbids it, the spec must say so in §3.6 with an example, and the parser must give `error: an impl header names its trait bare; add `import lib.{Tr}`` with a fix-it, not a cascade. I oppose this: it adds a rule that exists only to be memorized.

- **Minimalism:**

  **min-1 (recommended): one name rule, no exception — a qualified name is legal wherever a trait or type name is**

  The language already has qualified names: types (`lib.Pt`), bounds (`[U: lib.Tr]`, which the compiler accepts today), and qualified trait calls (`lib.Tr.name(w)`, §3.6). The impl header is the one place that rejects them. Forbidding it there does not save surface. It adds a rule ("except in an impl header"), a new diagnostic, and a spec sentence to explain why. Allowing it removes the exception. For a minimalist, the smaller language is the one with fewer special cases, not the one with fewer accepted spellings.

  ```blink
  import lib

  type W { n: Int }

  impl lib.Tr for W {
      fn name(self) -> Str { "w" }
  }

  trait Sh {
      fn shape(self) -> Str
  }

  impl Sh for lib.Pt {
      fn shape(self) -> Str { "pt" }
  }

  fn show[U: lib.Tr](u: U) -> Str {
      u.name()
  }

  fn main() {
      io.println(show(W { n: 1 }))
      io.println(lib.Tr.name(W { n: 2 }))
  }
  ```

  The rule, all slots:
  - **Trait slot** of an impl header, a **bound**, and the trait slot of an impl-qualified call `(lib.Mk for W).make()` take the same form: a bare trait name or `module.Trait`.
  - **Receiver slot** of an impl header and of `(Mk for lib.Pt)` takes what a type position takes, so `lib.Pt` is legal.
  - No new grammar beyond reusing the existing qualified-name production in these slots.

  **Scope: the header changes nothing.** `impl lib.Tr for W` does not put `Tr` in scope for bare method calls (§3.6 rule 2). The header is a definition, not an import. If it did bind `Tr`, we would have a second import form hidden in impl headers, the very thing §3.6 says does not exist ("No syntax imports an impl"). In the example, `W { n: 1 }.name()` outside a bound still needs `import lib.{Tr}` unless the impl lives in `W`'s package (rule 1, which it does here, so it works anyway). The qualifier is spelling only.

  **Orphan rule: unchanged.** The check runs on the resolved trait and type, not on how the file spelled them. Inside one package, either slot may name a sibling module's item qualified.

  **Diagnostics: none new.** A qualified name that does not resolve gives the error a bad bound gives today (unknown trait or `UnknownType`, E0507). A qualified name that resolves to a type where a trait is needed gives the error the bare form gives. One code path, one set of messages.

  **Spec text.**
  - §10.1 *Qualified Access*: change the list to "functions, types, traits, and constants", and add one sentence: "A qualified trait or type name is legal in a bound, an impl header, and an impl-qualified call."
  - §3.6: one line under *Impl visibility*: "Naming a trait in an impl header, bare or qualified, does not put it in scope."
  - Add one qualified example to §3.6 *Impl Placement* so the form exists in training data.

  **Tradeoff.** Two spellings for one header. Accepted: the same two spellings already exist for every type and bound, so a reader learns nothing new. `blink fmt` must not rewrite one to the other (the same rule as for variants).

  **Cross-language.** Rust `impl fmt::Display for X` is the common case and nobody calls it surface growth. Haskell allows `instance M.Show T`. Swift allows `extension Foo: Mod.Proto`. Go has no impl headers but qualifies every foreign name. I know of no language that allows a qualified name in a bound but forbids it in an impl head.

  **min-2 (rejected by me): forbid and say so**

  "An impl header names its trait bare; select it with `import lib.{Tr}`." This needs a new diagnostic, a spec carve-out, and an inconsistency with bounds that a future ticket will ask to remove. It also forces a selective import whose only job is to make the header parse, and that import then changes method-call scope for the whole file as a side effect. That is more coupling, not less. I oppose it.

#### Phase B — Debate highlights

One round. The moderator merged the six Phase A texts into two options and four variations (V1 scope inside the impl block, V2 which slots the rule lists, V3 effects in the §10.1 list, V4 the diagnostic for a type in the trait slot) and gave the facts below.

**Options after mechanical dedupe**

**Option 1: a qualified name is legal in every trait slot and type slot; the spelling never changes scope or the orphan check.** First choice of all six (sys-1, devops-1, plt-1, aiml-1, web-1, min-1). Covers `impl lib.Tr for W`, `impl Sh for lib.Pt`, `[U: lib.Tr]`, `(lib.Mk for W)`. A header that names `lib.Tr` does not put `Tr` in scope; the orphan rule tests the resolved trait and type.

**Option 2: forbid a qualified trait in an impl header; say so in the spec.** Listed as a rejected or opposed fallback by all six (sys-2, devops-2, plt-2, aiml-2, web-2, min-2). Those who describe it say the parser must still give one error with a fix that adds `import lib.{Tr}`.

**Variations (flagged for debate)**

**V1. Scope inside the impl block.** devops-1: "Inside that impl block, the trait counts as in scope for `self`, the same way a bound does. Outside the block, `w.name()` needs `import lib.{Tr}`." The other five: the header binds nothing (sys, plt, aiml, web, min). devops's §3.6 text: "An impl header does not put its trait in scope outside its own block."

**V2. Which slots the rule lists.** sys-1: impl header (both slots), bound, `where` constraint, impl-qualified call. plt-1: bound, impl trait slot, supertrait list, impl-qualified call; "the receiver slot ... is a type position, so §10.1 already allows `impl Sh for lib.Pt`; today's parse error there is a bug, not a design question." devops, aiml, web, min: impl header, bound, impl-qualified call (web adds "expressions, type positions"). Nobody named `@derive(...)`.

**V3. Effects in the §10.1 list.** sys-1, devops-1, aiml-1, web-1 add "effects" to "Qualified access works for functions, types, traits, effects and constants". plt-1 and min-1 add only "traits".

**V4. Diagnostic for `impl lib.Pt for W` (a type in the trait slot).** devops-1: reuse E0740 `QualifiedHeadNotTrait`. sys-1, plt-1, aiml-1, web-1: "`lib.Pt` is a type, not a trait" (plt: "the existing ... error"). min-1: "the error the bare form gives". All six: no new error code.

**Facts (surfaced from the repo; no position implied)**
- E0740 `QualifiedHeadNotTrait` (ERROR_CATALOG.md:172, sections/03c_protocols.md:753) today covers only "the left side of `for` in an impl-qualified call head `(Trait for Type)`".
- Supertrait clauses exist: `trait Hash: Eq` (sections/03_types.md:3819). `where` constraints exist on impls: `impl Render for List[T] where T: Display` (03_types.md:5003).
- sections/07_trust_modules_metadata.md:2935 lists the slots where a written trait name resolves by scope: "a bound `T: Eq`, `impl Eq for P`, a supertrait clause `trait Shape: Eq`, and the argument of `@derive(Eq)`".
- No spec text shows a module-qualified effect in an effect row (`! lib.Eff`), and none forbids it.

- **Systems:**

  **Option 1: support.** **Option 2: oppose.** Codegen is the same under either option, because the compiler resolves both spellings to one trait identity. Option 2 only adds a special case to the parser and the spec.

  **V1 (scope inside the impl block): oppose, mildly.** plt's point settles most of it: when the impl is in `W`'s package, §3.6 rule 1 already makes it a candidate wherever `W` goes, so `self.name()` resolves with no extra rule. The case that is left is an impl in `Tr`'s package for a foreign type. There, `lib.Tr.name(self)` works with no new rule. I do not want a third source of scope, even a lexically local one: then method lookup would depend on which block holds the call. No cost argument either way, so I do not block on it.

  **V2 (slots): use a general clause plus examples.** "A qualified trait or type name works in every slot that takes the bare name." Then list the slots that 07:2935 lists (bound, impl header, supertrait clause, `@derive` argument), plus `where` constraints and the impl-qualified call head. A closed list will miss a slot again, as the Phase A lists did with the supertrait clause and `@derive`. I agree with plt that the receiver slot is a type position already, so today's parse error there is a bug.

  **V3 (effects): change from Phase A. Traits only.** No spec text addresses `! lib.Eff` in an effect row. Adding "effects" to §10.1 here would decide that question as a side effect of this ticket. Log it as its own ticket.

  **V4: reuse E0740 `QualifiedHeadNotTrait`** and widen its catalog entry to cover the impl-header trait slot. Use "`lib.Pt` is a type, not a trait" as the note, and give the swapped header as help when the kinds are swapped. No new code.

  STATUS: ready to vote

- **Web/Scripting:**

  **Option 1: support.** All six seats agree. **Option 2: oppose**, for the reasons in web-2.

  **V1 (scope inside the impl block): lean support, not a blocker.** A Python or Kotlin dev expects `self.other()` to work inside the class that implements it. If `self.name()` failed inside `impl lib.Tr for ext.Pt { ... }` because the file has only `import lib`, that would be the strangest error in this whole area. devops's rule is lexical, so it does not cause the action at a distance that plt and I object to. A header 300 lines down still changes nothing outside its own block. In most cases rule 1 already covers it, since the impl sits with `W`. So the rule matters only for a foreign receiver in the trait's package, and there it prevents a real trap. If plt shows that a bound-like scope inside the block is unsound or redundant, I give way.

  **V2 (slots): change from Phase A.** Write the rule as a principle with a list: "a qualified trait name may appear in any slot that takes a bare one". List the slots that 07:2935 already names: bound, impl header (both slots), supertrait clause, `where` constraint, impl-qualified call head, `@derive(...)` argument. A list that leaves out supertraits and `where` will create the same ticket again. I agree with plt that `impl Sh for lib.Pt` is a type position that §10.1 already allows, so today's error there is a bug.

  **V3 (effects): concession.** I drop "effects" from this decision. No text shows `! lib.Eff`, and effect rows are a separate surface that raises questions of its own (handlers, row syntax). Keep this decision to traits, and file a separate spec ticket for qualified effects so it does not get lost.

  **V4 (type in trait slot): accept devops.** Widen E0740 `QualifiedHeadNotTrait` to cover the impl header trait slot. The message must still say plainly "`lib.Pt` is a type, not a trait". That reuses one code across the two places where `Trait for Type` is written, which helps the user. No new code.

  STATUS: ready to vote

- **PLT:**

  **Option 1: support.** No change from Phase A. Resolution maps a qualified name and a selected name to one trait identity. Every later judgment is stated over identity, so the change is sound by construction. **Option 2: oppose.** It keeps a grammar that changes by slot.

  **V1 (devops: the header's trait is in scope inside its own block): oppose, with repo evidence.** §3c (sections/03c_protocols.md:885) says: "**An impl body gets no special treatment.** ... The body does not prefer its own trait". That passed 6-0 ("no special case in an impl body", decisions/sealed-method-name-collision.md). V1 adds the special case that vote removed, and only for the qualified spelling. Then `impl lib.Tr for X` and `import lib.{Tr}` + `impl Tr for X` would differ in more than spelling. That breaks the one property that makes Option 1 sound. The case V1 aims at is narrow anyway: if `W` is local, rule 1 covers `self.name()`. The open case is `impl lib.Tr for ext.Pt`, with `lib` a sibling module and `ext` a foreign package. There the user writes `Tr.name(self)` or selects `Tr`, as for any other call. devops, please drop V1. If you want it, it needs its own ticket that reopens the 885 vote.

  **V2 (slots): list them all, by reference to 07:2935.** The spec already lists the slots where a user-written trait name resolves by scope: bound, impl header, supertrait clause, `@derive(...)` argument. Add `where` constraints and the impl-qualified call head. A qualified form must be legal in *every* such slot, or we get the same wall one slot over: `trait Shape: lib.Tr` and `@derive(lib.Tr)` included. I accept sys's addition of `where`. The receiver slot stays a type position under §10.1.

  **V3 (effects): not in this ticket.** An effect row `! lib.Eff` is a different construct with its own resolution rules (handlers, effect subsumption). No spec text or probe covers it here. I would rather file a separate spec question than pass it as one word in a list. I could accept it if the panel shows that effect names already resolve by the same path as types.

  **V4 (diagnostic): no strong view.** "`lib.Pt` is a type, not a trait" is the right message. Reusing E0740 is fine if its catalog entry widens to cover the impl header. Either way, no new code.

  STATUS: ready to vote

- **DevOps:**

  **Option 1: support. Option 2: oppose.** No change from Phase A.

  **V1 (scope inside the impl block): I withdraw it.** The others are right that it adds a fifth way to put a trait in scope. It also does very little work. Under the orphan rule, an impl lives in the type's package, where rule 1 already gives `self.name()`, or in the trait's package. A gap is left only for a foreign receiver in a module that does not select the trait, and there `import lib.{Tr}` or `lib.Tr.name(self)` is the fix E0505 already gives. "The header binds nothing" gives the LSP one rule. I adopt the §3.6 sentence from aiml/min: "Naming a trait in an impl header, bare or qualified, does not put it in scope."

  **V2 (slots): use the list in 07_trust_modules_metadata.md:2935.** That line already lists where a written trait name resolves: a bound, an impl header, a supertrait clause, and `@derive(...)`. Add `where` constraints (sys) and the impl-qualified call. If §10.1 lists fewer slots, the next ticket is "`trait S: lib.Tr` is a parse error". For tooling, the rule must hold in every slot where a trait name goes. I agree with plt that the receiver slot is a type position and that today's parse error there is a bug.

  **V3 (effects): leave them out.** No spec text shows `! lib.Eff`, and this ticket does not test it. Putting it in §10.1 without a check or an example makes a promise that nothing verifies. File it as a separate friction ticket. I change my Phase A text to "traits" only, as plt and min have it.

  **V4 (`impl lib.Pt for W`): withdraw E0740.** It covers only the call head, and its name says so. New evidence: the bare form is broken today too. With `import lib.{Pt}` and `impl Pt for W`, gen1 gives `error[TraitContract]: trait Pt is not defined`, which is false, plus an `UnusedImport` warning on `Pt` that has an empty fix. The rule: the bare form and the qualified form give one diagnostic, "`lib.Pt` is a type, not a trait", at the name, with no new code. The bare-form message is a bug to file whatever we decide.

  STATUS: ready to vote

- **AI/ML:**

  **Option 1: support.** No change from Phase A. **Option 2: oppose.**

  **V1 (scope inside the impl block): mild support for devops-1.** The case is narrow. Rule 1 already covers an impl in the type's package. V1 matters only for an impl in the trait's package for a foreign type, written under a whole-module `import lib`. There, `self.name()` inside `impl lib.Tr for ext.X` would fail under the five-seat reading. A model writing a method body assumes it can call the trait's other methods on `self`. A rule that matches that assumption costs nothing to learn, and a rule that breaks it costs a repair loop. It also mirrors the existing "a bound puts its trait in scope for a generic body" text. V1 does not change file scope, so it creates no action at a distance. I will not block on it.

  **V2 (slots): state the general rule, then list every slot.** Write "a qualified trait or type name is valid in every slot that takes the bare name", then list the slots: type position, bound, `where` constraint, supertrait list, both impl-header slots, and the impl-qualified call. Keep the list aligned with 07_trust_modules_metadata.md:2935, which already lists the trait slots that resolve by scope. That list includes `@derive(...)`. A partial list makes a model ask "does `where T: lib.Tr` work?", which is the same gap this ticket came from. I agree with plt that the receiver slot was already a type position.

  **V3 (effects): concede to plt and min.** Leave effects out of this decision. No spec text shows `! lib.Eff`, and effect rows need a separate review. File a follow-up ticket so the gap does not stay hidden.

  **V4 (type in trait slot): one message, bare and qualified.** New evidence from gen1: today `type Pt` + `impl Pt for W` gives `error[TraitContract]: trait Pt is not defined`. That is wrong, because `Pt` is defined, as a type. So "reuse the bare-form error" (min-1) would inherit that bad message. Both forms should say "`Pt` is a type, not a trait" at the name's span. I am against reusing E0740: its name `QualifiedHeadNotTrait` uses "qualified" to mean the impl-qualified call head. Putting module-qualified headers under that name gives one word two meanings in the catalog, and models read the catalog. Use or create one "type where a trait is expected" diagnostic for every trait slot. Fix the bare-form message in the same change.

  STATUS: ready to vote

- **Minimalism:**

  **Option 1: support.** **Option 2: oppose.** No change from Phase A.

  **V1 (scope inside the impl block): I now support devops-1, limited to the block.** My Phase A said "the header changes nothing", but I missed a case. A bare header `impl Tr for W` always has `Tr` in scope, because the bare name had to resolve. A qualified header `impl lib.Tr for W` does not. Take a trait in a sibling module of the same package and a receiver from another package. The impl lives only in the trait's package, so rule 2 applies, and `self.other()` in the body would fail without `import lib.{Tr}`. Under devops's sentence, the qualified header acts the same as the bare one inside the body, which is my "no exception" principle. Outside the block, nothing changes. That costs one sentence and no new rule, since a bound already counts as "in scope" in the same way.

  **V2 (slots): one general sentence, not a list.** "Wherever the spec takes a trait name, it takes `module.Trait`." This covers the four slots at 07:2935 (bound, impl header, supertrait, `@derive`), `where`, and `(lib.Mk for W)`. A list invites the next ticket about the slot someone left out. `@derive(lib.X)` then goes through the existing derive checks with no special case. I agree with plt that the receiver slot is already a type position under §10.1, so the parse error there is a bug.

  **V3 (effects): traits only.** The ticket does not ask about effect rows (`! lib.Eff`), and no spec text shows one. Adding effects widens this decision past its evidence. If someone wants it, file a separate ticket.

  **V4 (type in the trait slot): the bare and qualified forms must give one error.** I checked: bare `impl Pt for W` with `import lib.{Pt}` gives `error[TraitContract]: trait `Pt` is not defined`, which is false because `Pt` is defined as a type. So "the error the bare form gives" is wrong today. I support one message, "`Pt` is a type, not a trait", for both spellings, and widening E0740 to impl headers rather than adding a code. The bare-form message is a bug to fix with it.

  STATUS: ready to vote

#### Phase C — Final vote

Each seat voted alone on the ballot below.

**Moderator facts surfaced after Phase B (no position implied)**
- sections/03c_protocols.md:885: "**An impl body gets no special treatment.** Inside `impl Tidy for Str`, `self` has type `Str`, and `self.trim()` follows the same lookup as any other call. It is E0522. The body does not prefer its own trait, so the call is neither a recursive call nor a silent call to the built-in."
- sections/07_trust_modules_metadata.md:2935: "In the declaring module, a bound `T: Eq`, `impl Eq for P`, a supertrait clause `trait Shape: Eq`, and the argument of `@derive(Eq)` all name the local trait."
- aiml, devops and min report (gen1): with `import lib.{Pt}`, bare `impl Pt for W` gives `error[TraitContract]: trait Pt is not defined`. devops adds an `UnusedImport` warning on `Pt` with an empty fix.
- B1 positions on V1: devops withdrew V1. aiml (mild), min and web (lean, "not a blocker") now support it. sys (mild) and plt oppose.

- **Q1: A module-qualified name in an impl header.** (6-0)

  - A: A qualified name is legal in every trait slot and type slot; the spelling never changes scope or the orphan check. The orphan rule, impl lookup and bound checks test the resolved trait and type. (Option 1: sys-1, web-1, plt-1, devops-1, aiml-1, min-1)
  - B: Forbid a qualified trait in an impl header; say so in the spec, with one error and a fix that adds `import lib.{Tr}`. (Option 2: all six list it as rejected or opposed)

  - **Systems:**

    **Vote:** A
    **Reasoning:** Both spellings resolve to one trait identity, so the symbols, dispatch and mono instances are identical and the spelling never reaches codegen. A ban adds a parser special case for no runtime or codegen benefit, and it makes the header slot disagree with bounds and type positions, which already take `lib.Tr`.
    **Concern:** If any pass keys impls on the spelled name and not on the resolved identity, `impl Tr for W` and `impl lib.Tr for W` could produce two C symbols or slip past the duplicate-impl check. The tests must prove that the two spellings collide.

  - **Web/Scripting:**

    **Vote: A**
    **Reasoning:** A dev from Rust, TS, Python, Kotlin or Swift types `impl lib.Tr for W` first, and today they get "expected {, got .". One rule fixes it: `module.Name` works anywhere a bare name does. That removes an exception rather than adding a feature, and because spelling never changes meaning, it adds nothing new to learn.
    **Concern:** Parity fixed in the header but not in the impl-qualified call or supertrait slot would leave the same "works here, fails there" trap in a new place.

  - **PLT:**

    **Vote:** A
    **Reasoning:** Resolution maps `lib.Tr` and a selected `Tr` to one trait identity, and coherence, the orphan rule, impl lookup and bound entailment are all stated over identity. So the change touches only the resolution layer and cannot change the meaning of any program. B keeps a grammar that changes by slot: the bound takes the qualified form and the matching impl header does not.
    **Concern:** The implementation may resolve the qualified header through a different path than the bound does, so the two forms drift apart (the `lib.Tr.name(w)` ICE shows this kind of drift already exists).

  - **DevOps:**

    **Vote:** A
    **Reasoning:** One rule for the name in every slot means the parser always reads a path and the resolver reports one error at the right span, not today's `expected {, got .` cascade. Completion, go-to-definition and rename then work the same in a bound, a header and a call head, with no special case in the language server. A ban would need a diagnostic of its own and a spec carve-out that tooling must explain each time.
    **Concern:** The parser change may land only in the trait slot of the header, so the receiver slot, the supertrait clause or `(lib.Mk for W)` keep the old cascade. The test suite must cover every slot.

  - **AI/ML:**

    **Vote:** A
    **Reasoning:** One rule ("`m.Name` works wherever `Name` works") is learnable from §10.1 alone. Today the grammar depends on the slot, so a model must memorize the exceptions. Rust, Haskell, Swift and Kotlin training data all show qualified trait names in impl headers, so models will write the form either way; A turns a parse-error cascade into working code.
    **Concern:** The parser change may land for the trait slot and miss the receiver slot or the impl-qualified call head, and leave a new partial grammar.

  - **Minimalism:**

    **Vote: A**
    Reasoning: Bounds and type positions already take a qualified name. Forbidding it only in impl headers would add a carve-out, a new error and a forced selective import that changes method-call scope for the whole file. Option A removes an exception and adds no grammar.
    Concern: the receiver-slot parse error and the qualified-call ICE get fixed in a different order, so for a while the spec promises a form that the compiler half-accepts.

- **Q2: Scope inside the impl block (V1).** (6-0)

  - A: The header binds nothing. "Naming a trait in an impl header, bare or qualified, does not put it in scope." (sys, plt; devops in B1 adopting the aiml/min text; Phase A of web, aiml, min)
  - B: Inside its own block, the header's trait is in scope for `self`, the same way a bound is; outside the block, nothing changes. (devops-1 Phase A, withdrawn in B1; aiml, min, web in B1)

  - **Systems:**

    **Vote:** A
    **Reasoning:** 03c:885 already says an impl body gets no special treatment: `self.trim()` inside `impl Tidy for Str` follows normal lookup. B would contradict that rule or force a carve-out from it. With A, method lookup depends only on module scope and the receiver, not on which block holds the call. §3.6 rule 1 already covers the common case (an impl in `W`'s package), and `lib.Tr.name(self)` covers the rest.
    **Concern:** Users of the rare "impl in the trait's package for a foreign type" case will hit E0505 on `self.name()` in the body, so its help must name the qualified call or the selective import.

  - **Web/Scripting:**

    **Vote: A** (change from B1)
    **Reasoning:** 03c:885 already says an impl body gets no special treatment and does not prefer its own trait. Option B would make the header a special case inside the body, which contradicts that rule and adds a scope exception for users to learn. Rule 1 already covers the common case, and the fix for the rare foreign-receiver case is one selective import that the E0505 help can offer.
    **Concern:** A user who calls `self.other()` in `impl lib.Tr for ext.Pt` with only `import lib` gets an error that feels wrong, so the E0505 help must name `import lib.{Tr}` exactly.

  - **PLT:**

    **Vote:** A
    **Reasoning:** §3c (03c_protocols.md:885) already settles this 6-0: "An impl body gets no special treatment ... The body does not prefer its own trait." B adds back that special case, so `impl lib.Tr for X` and `import lib.{Tr}` + `impl Tr for X` would differ in more than spelling, which breaks the property that makes Q1-A sound. The case B aims at is narrow (rule 1 covers a local receiver), and `Tr.name(self)` or a selection handles the rest.
    **Concern:** If B wins, the spec holds two contradicting rules (03c:885 and the new clause), and the decision must amend 03c:885 explicitly or the contradiction stays.

  - **DevOps:**

    **Vote:** A
    **Reasoning:** 03c:885 already says "An impl body gets no special treatment". Option B would contradict that line and add a scope source that the LSP must model per block. With A, the import lines alone decide scope, and the E0505 help already gives the fix (`import lib.{Tr}` or `lib.Tr.name(self)`) in the one case that rule 1 does not cover.
    **Concern:** A user who writes `self.name()` in `impl lib.Tr for ext.Foo` gets E0505 and may think the qualified header is broken. The E0505 note must say that the header does not import the trait.

  - **AI/ML:**

    **Vote:** A (change from B1)
    **Reasoning:** 03c_protocols.md:885 already says "An impl body gets no special treatment." That is a rule a model can learn and apply everywhere. B would add a body-local exception to it, for a narrow case (a trait-package impl for a foreign type under a whole-module import). One consistent rule is cheaper for generation than an exception that matches intuition in one corner. The E0505 fix (select the trait) already repairs the narrow case in one edit.
    **Concern:** A model writes `self.other_method()` inside `impl lib.Tr for ext.X` and hits E0505; the help text must name the exact `import lib.{Tr}` fix.

  - **Minimalism:**

    **Vote: A** (I changed my vote from B1.)
    Reasoning: 03c:885 already says "An impl body gets no special treatment". Option B would put a scope exception into the body, which goes against that rule and adds a second meaning to "in scope". The gap I raised in B1 is real but narrow: a qualified header with a sibling-module trait and a foreign receiver. Inside the body, `lib.Tr.other(self)` or `import lib.{Tr}` closes it with no new rule.
    Concern: users who hit that narrow case will read the failed `self.other()` as a bug, so the E0505/method-not-found help should name `import lib.{Tr}`.

- **Q3: How the spec states which slots take a qualified name (V2).** (6-0)

  - A: A general clause, then the list of slots: those at 07:2935 (bound, impl header, supertrait clause, `@derive(...)` argument), plus `where` constraints and the impl-qualified call head; the receiver slot is a type position that §10.1 already covers. (sys, web, plt, devops, aiml in B1)
  - B: One general sentence, not a list: "Wherever the spec takes a trait name, it takes `module.Trait`." (min in B1)

  - **Systems:**

    **Vote:** A
    **Reasoning:** The general clause makes the rule total. The list ties it to the slots the spec already names at 07:2935, so the compiler implementer and the test author have a checklist. Each slot is its own parser and resolver entry point, and a slot with no test is where a bug like this one hides.
    **Concern:** A slot added later (a new trait-taking form) can fall off the list. The general clause must stay normative and the list only illustrative.

  - **Web/Scripting:**

    **Vote: A**
    **Reasoning:** A general clause gives the principle, and the list gives the reader and the AI a concrete check. If the list leaves out supertrait and `where`, this ticket comes back. Listing the slots that 07:2935 already names keeps the two sections consistent.
    **Concern:** A new trait slot added later could miss the list. The general clause must govern, and the list must say it is not exhaustive.

  - **PLT:**

    **Vote:** A
    **Reasoning:** A general clause plus the explicit list ties the rule to 07:2935, which already lists the slots where a written trait name resolves. A reader and an implementer can then check each slot one by one. A bare general sentence leaves "where does the spec take a trait name?" for the reader to work out, and a slot that gets missed brings back the wall this ticket removes.
    **Concern:** A new trait slot added later may update one list and not the other; the clause should say that the list is complete only for the spec as it stands.

  - **DevOps:**

    **Vote:** A
    **Reasoning:** An explicit list is what the test suite and a corpus row can check, slot by slot. A general sentence leaves a reader, and a tool author, to work out the slots for themselves. The list at 07:2935 already exists, so reusing it keeps the two sections in step.
    **Concern:** A future slot, such as a new attribute that takes a trait, may get added without an update to the list. Put the general clause first so the list reads as examples of the rule, not as its limits.

  - **AI/ML:**

    **Vote:** A
    **Reasoning:** An explicit list answers "does `where T: lib.Tr` work?" with no inference. Gaps in an implied list are what caused this ticket. The general clause covers future slots, and the list removes doubt about current ones.
    **Concern:** A slot added later (for example a new attribute that takes a trait) gets left off the list, and a reader reads the list as exhaustive.

  - **Minimalism:**

    **Vote: A** (I changed my vote from B1.)
    Reasoning: Option A keeps the general clause I asked for and adds the list under it. The clause covers any slot the list leaves out, and the list gives readers and models concrete cases. That costs a few lines of text and adds no rules.
    Concern: when a new trait slot joins the language, someone has to remember to add it to this list.

- **Q4: Effects in the §10.1 list (V3).** (6-0)

  - A: Traits only. Effects stay out of this decision; a separate ticket takes qualified effect names (`! lib.Eff`). (all six in B1)
  - B: Add "effects" to the §10.1 list. (sys-1, devops-1, aiml-1, web-1 Phase A; all withdrawn in B1)

  - **Systems:**

    **Vote:** A
    **Reasoning:** No spec text addresses `! lib.Eff` in an effect row. Effect rows feed handler identity and the evidence passing that the compiler generates, so they deserve their own decision, not one made as a side effect of this ticket.
    **Concern:** The separate ticket may stall and leave traits and effects asymmetric for a long time. File it now.

  - **Web/Scripting:**

    **Vote: A**
    **Reasoning:** Keep the decision to the ticket's scope. Qualified effects in rows touch handler and row syntax, which deserve their own debate. A separate ticket keeps the gap from being lost.
    **Concern:** The separate effects ticket could sit for a long time, and users who write `! lib.Eff` get an unclear error until it lands.

  - **PLT:**

    **Vote:** A
    **Reasoning:** An effect row has its own resolution and subsumption rules (handlers, effect sets), and no fact or probe in this ticket covers `! lib.Eff`. Deciding it as one word in a list is not sound practice. It needs its own ticket.
    **Concern:** The follow-up ticket for qualified effect names may never get filed, and `! lib.Eff` stays unspecified.

  - **DevOps:**

    **Vote:** A
    **Reasoning:** Nothing in the spec shows or tests `! lib.Eff`, so putting effects in the list would make a promise that no check or diagnostic backs. A separate ticket can work out what an effect row does with a qualifier, including what the formatter and the error messages print.
    **Concern:** The separate ticket may never get filed, and §10.1 then stays silent on effects. The decision should name the follow-up ticket.

  - **AI/ML:**

    **Vote:** A
    **Reasoning:** No spec text covers `! lib.Eff`. Effect rows interact with handlers and inference and deserve their own review. A separate ticket keeps the gap visible and does not slip it in under a trait decision.
    **Concern:** The follow-up ticket never gets filed, and effect rows stay the one slot where the qualified form is undefined.

  - **Minimalism:**

    **Vote: A**
    Reasoning: The ticket and the evidence cover traits only. Effect rows have their own grammar and no example. Keep this decision small and send effects to a separate ticket.
    Concern: none, as long as the separate ticket is filed and not forgotten.

**Position changes in Phase C.** Against the Phase B ballot text and the seats' own Phase C text:

- Q2: aiml, web and min changed their vote from B (Phase B: aiml mild, min and web lean) to A. devops had withdrawn V1 in Phase B.
- Q3: min changed its vote from B (one general sentence) to A (clause and list).
- Q5: the ballot listed sys, web and min under A. sys and web voted B (web marks "change from B1"). min stayed on A and dissents. plt voted B and accepts A if the entry widens to every trait slot.

**Moderator reading of Q5, pending the user's sign-off.** B won 5-1 and names no code. The moderator reads it as: keep the number E0740 and rename the code to a neutral name for the general condition. This record uses `TypeNotTrait`. The name is a proposal and an open point.

**Compiler finding (gen1).** With `import lib.{Pt}`, the bare form `impl Pt for W` gives `error[TraitContract]: trait Pt is not defined`, which is false: `Pt` is defined, as a type. devops also saw an `UnusedImport` warning on `Pt` with an empty fix. The diagnostic in Q5 replaces this message for the bare and the qualified spelling.

### Final Spec

```blink
import lib

trait Sh {
    fn sh(self) -> Str
}

type W {
    v: Int
}

impl lib.Tr for W {                 // the trait slot
    fn name(self) -> Str { "w{self.v}" }
}

impl Sh for lib.Pt {                // the receiver slot
    fn sh(self) -> Str { "pt{self.x}" }
}

fn show[U: lib.Tr](u: U) -> Str { u.name() }    // a bound

impl Pt for W { }                   // COMPILE ERROR E0740: `Pt` is a type, not a trait
```

- A module-qualified trait or type name works in every slot that takes the bare name. The qualifier is the import's leaf name or its alias (§10.1).
- The spelling never changes scope or the orphan check. The orphan rule, impl lookup, duplicate-impl detection and bound checks test the resolved trait and type (§3.4 *Identity, not spelling, selects behavior*).
- An impl header, bare or qualified, puts no trait in scope. A body call repairs with `import lib.{Tr}` or `lib.Tr.name(self)` (§3.6 *Impl visibility*).
- The slots: a bound, a `where` constraint, both names of an impl header, a supertrait clause, the argument of `@derive(...)`, the head of an impl-qualified call. The receiver slot is a type position.
- §10.1 names traits in its list. Effects are not part of this decision.
- One diagnostic, E0740 `TypeNotTrait`, covers a type where a trait is expected in every trait slot. It absorbs the impl-qualified call head case.
