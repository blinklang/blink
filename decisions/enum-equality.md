[< All Decisions](../DECISIONS.md)

# Enum Equality — Design Rationale

**Gap:** "Must a data enum write @derive(Eq) for ==, or is it Eq when its payloads are?" The container-equality decision ([container-equality.md](container-equality.md), Q9) set an interim rule in §3.6 *Container Equality*: an enum with no `Eq` impl and no `@derive(Eq)` is `Eq` only if every payload type is `Eq`, and a payload-free enum is `Eq`. The final rule was open.

**Facts given to the panel (measured with build/blink, main @ f1148235):**

- `type Color { Red  Green }`: `Color.Red == Color.Green` compiles (interim rule).
- `type Shape { Circle(r: Int)  Sq(s: Int) }`: `Shape.Circle(1) == Shape.Circle(1)` compiles; `Option[Shape] == Option[Shape]` compiles.
- `type Bag { Items(xs: List[Widget])  Empty }` with non-Eq Widget: `Bag.Empty == Bag.Empty` is rejected: "`Bag` does not implement `Eq` / note: `Bag` is `Eq` only if `List[Widget]` is `Eq` ... help: add `@derive(Eq)` to `type Widget`".
- Struct `Widget { id: Int }` `==` is rejected with help "add `@derive(Eq)` to `type Widget`".
- `Set[Color]` for payload-free Color is rejected: E1400 MapKeyNotHashable, help "add @derive(Hash, Eq)".
- Same-enum `Color.Red < Color.Green` (payload-free) compiles with no derive(Ord).
- Data enum `Shape.Circle(1) < Shape.Circle(2)` with no Ord reaches an internal compiler error (a bug, being filed separately; not this question, but it shows Ord already splits payload-free vs data).
- Migration size under a "derive required" rule has NOT been measured. The compiler source (src/) compares payload-free enums such as NodeKind/TokenKind with `==` heavily.

**Already decided (given to the panel as constraints):**

- **Container Equality (6-0):** Option/Result/List/Set/Map/tuples are Eq conditionally when their parts are Eq. The check recurses. Wrapping must never change what `==` means: the rule must give the same answer for `E` and `Option[E]`. (sections/03_types.md, "Container Equality", ~line 2956)
- **Structs:** a user struct is Eq only through `@derive(Eq)` or a written `impl Eq`. The spec example: `type Widget { id: Int }` then `ws == ws` is an error "Widget does not implement Eq".
- **Tuples:** anonymous, so Eq/Ord/Hash/Display/Debug/Clone are auto-derived structurally when elements satisfy them (5-0). §3.8 "Auto-Derived Trait Implementations".
- **@derive:** compiler-known traits only (5-0). Derive infers bounds on generics, auto supertrait derivation; field-by-field for structs, variant-match for enums (5-0). For `@derive(Eq)`, a container field is checked by Container Equality; `E1401 NonDerivableTrait` names the inner type when it fails.
- **Hash / keys:** `Hash: Eq`. Map keys / Set elements need Hash. A user struct or enum used as a key needs `@derive(Hash, Eq)` or a written impl — including payload-free enums (fvceqe closed by keeping that written rule).
- **Enums nominally distinct from Int (6-0):** no assignability. Tag operations on a fieldless enum: comparison with Int (`==`,`!=`,`<`,`<=`,`>`,`>=` compare the tag), `Enum.to_int()`, `Enum.from_int(n) -> Option[Enum]`.
- **Eq laws:** reflexive, symmetric, transitive; containers rely on them.
- **Failed-Eq diagnostic:** names the innermost type with no Eq plus the chain, offers machine-applicable `@derive(Eq)` on a user struct/enum, and `.is_none()` for `== None`.
- **assert_eq / assert_ne:** need `T: Eq` and `T: Debug`. A user type needs `@derive(Debug)` or `impl Debug` (no implicit Debug for user types).
- **Current interim spec text (§3.6):** "**Enums (interim rule).** An enum with no `Eq` impl and no `@derive(Eq)` is `Eq` only if every payload type is `Eq`. An enum with no payloads is `Eq`. So `Option[Color]` is `Eq` for a payload-free `Color`, and `Option[Shape]` is not `Eq` if a `Shape` variant carries a `List[Widget]`."

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated
in independent-proposal → debate → vote rounds.

#### Phase A — Independent proposals

Full texts, verbatim.

**Systems:**

> Systems: Phase A proposal (nxd4s5)
>
> **Cost is the same either way.** An implicit structural impl and an `@derive(Eq)` impl compile to the same per-type function. It does one tag compare, then compares the payloads of the matching variant (`cc_enum_eq_stmts`). For a payload-free enum it is one integer `cmp`. Both rules monomorphize and neither needs a vtable. So the choice is about where the error appears and what the API promises, not about speed. I am changing my position from the earlier panel ("Eq only when payloads are Eq") for the reason below.
>
> ### Proposal S1 (preferred): payload-free enums are Eq implicitly; a data enum needs `@derive(Eq)` or `impl Eq`
>
> ```blink
> type Color { Red  Green  Blue }          // Eq with no derive: tag compare
>
> @derive(Eq, Debug)
> type Shape { Circle(r: Int)  Sq(s: Int) }
>
> type Bag { Items(xs: List[Widget])  Empty }
>
> fn main() {
>     let a = Color.Red == Color.Green          // ok
>     let b = Shape.Circle(1) == Shape.Sq(2)    // ok, derived
>     let c = Some(Shape.Circle(1)) == None     // ok, Option[Shape]: Eq
>     let d = Bag.Empty == Bag.Empty            // error: `Bag` does not implement `Eq`
>                                               // help: add `@derive(Eq)` to `type Bag`
> }
> ```
>
> If someone writes `@derive(Eq)` on `Bag`, it fails at the declaration with `E1401`, which names `List[Widget]` → `Widget`.
>
> **Why, from the systems side:**
>
> 1. **The error appears where the cause is.** Under the structural rule, adding `Items(xs: List[Widget])` to an enum gives no error in that file. The errors show up at every `==` site, and also through `Option[Bag]` and `List[Bag]`, possibly in other modules or packages. With a required derive, the error is on the declaration line, where the change was made.
> 2. **Eq-ness is a stated API contract.** Under the structural rule, a library enum is Eq or not depending on its payload types. Adding a payload in a minor release can take `Eq` away and break code downstream. Go shows this: a struct is `comparable` when its fields are, so adding one slice field breaks every downstream map key and `==`, and the library's own build never catches it. Rust requires `derive(PartialEq)` for exactly this reason.
> 3. **The split already exists in the spec.** It is not a new rule. The fieldless-enum *tag operations* are already decided: compare with Int, `<`, `to_int`, `from_int`. Same-enum `==` on a payload-free enum is one more tag operation. "Adding the first payload loses the tag operations" is one rule, and `to_int` and `<` already work that way. That answers aiml's concern: the model learns one fact about fieldless enums, not a special case for Eq. When a model adds the first payload, the compiler gives a machine-applicable `@derive(Eq)` fix at each `==` site. That is a fast, mechanical loop.
> 4. **Structs and data enums match.** A data variant is a struct with a tag. A struct needs `@derive(Eq)` (decided), so a data enum does too.
> 5. **Wrapping is consistent.** `E: Eq` is a property of `E` alone, so `E` and `Option[E]` always give the same answer.
>
> **Generic enums:** `@derive(Eq) type Tree[T] { Leaf(v: T)  Node(l: Tree[T], r: Tree[T]) }` infers `T: Eq` (already decided), and mono emits one function per instantiation. Without a derive, `Tree[Int]` is not Eq.
>
> **Swift does exactly this.** An enum with no associated values gets Equatable and Hashable on its own. An enum with associated values must declare `: Equatable`, and the compiler then fills in the impl. Swift has shipped this for years without trouble.
>
> **Migration (code changes once):**
> - The interim rule never asked anyone to *remove* anything. The only edit is adding `@derive(Eq)` to data enums that are compared, and each enum is edited once.
> - Step 1: for one release, `==` on a data enum that is Eq only through the interim rule gives a warning with a machine-applicable `@derive(Eq)` fix (`blink fix` applies it). Step 2: the warning becomes an error.
> - src/ mostly compares payload-free enums (`NodeKind`, `TokenKind`), so those do not change. The bootstrap order: add derives to src/lib data enums (derive already works), regen, then flip the typecheck. **We must count the data-enum `==` sites in src/, lib/ and tests/ before the vote.** That number is not known yet.
>
> ### Proposal S2 (fallback): make the interim structural rule final
>
> ```blink
> type Shape { Circle(r: Int)  Sq(s: Int) }   // Eq because Int is Eq
> ```
>
> This needs no migration, and it is how Go and Zig (`std.meta.eql`) do it. The cost is points 1 and 2 above: the error appears far from its cause, and any payload edit can silently change the API. If the panel picks S2, I would add a rule that a `pub` enum's structural Eq is part of its API, so dropping it counts as a breaking change. Tooling would have to check that, which is worse than writing the derive.
>
> ### Not proposed
>
> - **Derive required for every enum, payload-free included (plt).** This conflicts with the tag operations already decided. `Color.Red < Color.Green` compiles with no derive, so `==` failing would be inconsistent.
> - **Payload-free `Hash`:** decided (keys need `@derive(Hash, Eq)`), so I am not reopening it. I only note that a payload-free hash is also just the tag.
>
> **Preference: S1 > S2.**

**Web/Scripting:**

> ## Web/Scripting proposals: enum Eq (nxd4s5)
>
> ### Proposal W1 (preferred): fieldless enums get Eq for free, data enums write `@derive(Eq)`
>
> **Rule:** An enum with no payload on any variant is `Eq` (tag compare). An enum with at least one payload is `Eq` only through `@derive(Eq)` or a written `impl Eq`, the same as a struct. The rule applies the same way to `E` and `Option[E]`.
>
> ```blink
> type Color { Red  Green  Blue }
>
> @derive(Eq, Debug)
> type Shape { Circle(r: Int)  Sq(s: Int) }
>
> type Bag { Items(xs: List[Int])  Empty }
>
> fn main() {
>     let c = Color.Red
>     if c == Color.Green { print("green") }          // ok: fieldless
>     let s = Shape.Circle(1)
>     assert_eq(s, Shape.Circle(1))                    // ok: derived
>     let maybe: Option[Shape] = Some(s)
>     if maybe == Some(Shape.Sq(2)) { print("sq") }    // ok: Shape: Eq
>     // Bag.Empty == Bag.Empty                        // error: `Bag` does not implement `Eq`
>     //   help: add `@derive(Eq)` to `type Bag`  (machine-applicable)
> }
> ```
>
> **Why this is the 90% case:**
> - `if tok == TokenKind.Eof` is the most common enum use in every language. Making it cost ceremony is friction with no safety gain, because a fieldless enum has exactly one sane equality.
> - One mental model: **a fieldless enum is a set of named constants. An enum with fields is a struct.** A JS/Python dev gets that in under a minute, and it matches the struct rule decided earlier.
> - It agrees with what is already decided for fieldless enums. Same-enum `<` already works with no derive, and `Color.Red == 0` compares the tag. A rule where `Color.Red < Color.Green` and `Color.Red == 0` compile but `Color.Red == Color.Green` does not would be a Stack Overflow classic. That is my main objection to plt's derive-only rule.
>
> **Answer to aiml's "first payload" concern:** it is real, but the failure is loud and local. Adding `Circle(r: Int)` makes each `==` site fail with a one-line machine-applicable fix (`@derive(Eq)` on the enum). The same thing happens today when you add a non-Eq field to a derived struct. A silent behavior change would be bad; a compile error with an auto-fix is acceptable.
>
> **Tradeoffs:**
> - (+) Familiar, least ceremony where it matters, consistent with structs and with the decided Ord and tag rules.
> - (−) Two rules rather than one. The edge case is the first-payload transition.
> - (−) The `Set[Color]` asymmetry stays: `==` works with no derive, but a key needs `@derive(Hash, Eq)`. That is already decided. I only flag that the E1400 help text must say "fieldless enums get Eq automatically, Hash is opt-in" or it will cause confusion.
>
> **Migration (code changes once, not twice):**
> 1. One release with warning W-xxxx on `==`, `!=`, `assert_eq` and containers for any data enum that is Eq only through the interim structural rule. The warning carries a machine-applicable `@derive(Eq)` fix (`blink fix`, or the LSP quick-fix).
> 2. The next release turns the warning into the standard "does not implement `Eq`" error.
> 3. Fieldless enums need no change, so the heavy NodeKind/TokenKind `==` use in src/ is untouched. Before we vote, someone should count the data-enum `==` sites in src/, lib/ and tests/ (that is the whole migration).
>
> **Cross-language:** This is exactly Swift. Enums with no associated values are automatically `Equatable` and `Hashable`. Enums with associated values need `: Equatable` declared, and the conformance is synthesized. Kotlin is similar: `enum class` compares freely, while a sealed class needs `data class` to get structural `equals`. TypeScript is the cautionary tale: `===` on discriminated-union objects compares references, which causes endless bug reports. Blink avoids that either way.
>
> ### Proposal W2 (acceptable fallback): make the interim rule final, Eq when all payloads are Eq
>
> ```blink
> type Shape { Circle(r: Int)  Sq(s: Int) }
> fn main() {
>     if Shape.Circle(1) == Shape.Circle(1) { print("eq") }   // ok, no derive
> }
> ```
>
> - (+) One rule, zero migration, and it "just works" the way Python dataclasses do (`eq=True` by default).
> - (−) Data enums and structs disagree: `type Widget { id: Int }` needs a derive, but `Circle(id: Int)` does not. People will ask "why does my enum compare but my struct doesn't?"
> - (−) Eq is lost far from the edit. Adding a `List[Widget]` payload to one variant silently removes Eq from the whole enum and from every `Option[E]` that wraps it. The diagnostic chain helps, but the user never opted in, so the user never knew they relied on it.
>
> ### Rejected: derive-only for every enum (plt)
>
> `@derive(Eq)` on every `Color`/`TokenKind`/`Direction` is pure ceremony, and it conflicts with the tag `==`/`<` rules already decided. Under that rule, `Color.Red == 0` and `Color.Red < Color.Green` compile, but `Color.Red == Color.Green` does not.
>
> **Vote preference:** W1 > W2 >> derive-only.

**PLT:**

> **PLT panelist: Phase A proposals (nxd4s5)**
>
> **Core claim.** `Eq` is a semantic claim: the author says "structural identity is the equivalence I intend." It is more than a structural capability. The spec already uses this reasoning for structs (`Widget` without a derive is not `Eq`). A sum type and a product type are both nominal ADTs. If they follow different rules, the language is inconsistent. A single-variant enum `type P { P(x: Int, y: Int) }` and a struct `type P { x: Int  y: Int }` would get different `Eq` behaviour for the same data.
>
> The interim rule has three soundness or compositionality defects:
>
> 1. **It leaks representation.** Add a payload to a variant (even a private type) and every downstream `==`, `Option[E] ==` and `assert_eq` can flip without a warning. The type's interface changes because of a body edit.
> 2. **It gives wrong answers with no warning.** In `type Frac { F(n: Int, d: Int) }`, structural `==` says `F(1,2) != F(2,4)`. When the author opts in with a derive, the author has made that choice. With an implicit rule, the language made it for them.
> 3. **It leaves recursion undefined.** I measured this with build/blink: `type Json { Null  Arr(xs: List[Json]) }` makes `Json` `Eq` iff `List[Json]` is `Eq` iff `Json` is `Eq`. The compiler takes the greatest fixed point (`a == b` prints `true`), but the spec does not choose. A least-fixed-point reading rejects it. With a derive the question goes away: the declared impl is the hypothesis, like Haskell's `deriving` or Rust's coinductive impl solving.
>
> A fourth point: for generic enums, the implicit rule needs bound inference (`Tree[T]: Eq` when `T: Eq`). §3.8 already defines that inference for `@derive`. The interim rule is a second, invisible derive that the spec must define again.
>
> ---
>
> **Proposal A (preferred): every user enum is `Eq` only through `@derive(Eq)` or `impl Eq`. This includes payload-free enums.**
>
> ```blink
> @derive(Eq, Debug)
> type Color { Red  Green }
>
> @derive(Eq, Hash, Debug)
> type Shape { Circle(r: Int)  Sq(s: Int) }
>
> type Frac { F(n: Int, d: Int) }
> impl Eq for Frac {
>   fn eq(self, other: Frac) -> Bool { self.n * other.d == other.n * self.d }
> }
>
> type Mode { On  Off }
> fn f(m: Mode) -> Bool { m == Mode.On }   // error: `Mode` does not implement `Eq`
>                                          // fix: add `@derive(Eq)` to `type Mode`
> ```
>
> - **Same answer bare and wrapped:** yes. The rule is nominal per type, and Container Equality only recurses into impls that exist.
> - **Consistency with what is already decided:** it matches structs. It matches Hash, which already needs a derive even for payload-free enums (fvceqe). It matches `assert_eq`'s Debug, which has no implicit form. One rule covers all user ADTs and all compiler-known traits.
> - **Adding the first payload flips nothing,** which answers aiml's concern.
> - **Cost:** `c == 1` (a decided tag operation) still compiles while `c == Color.Red` does not. That is surprising, but it is sound: the tag comparison is a separate operator on `(Enum, Int)` and makes no claim about `Eq` on `Enum`. Same-enum `<` on payload-free enums (it compiles today) should then need `@derive(Ord)`. That belongs on a follow-up ticket, but the rule should be stated so Ord does not drift.
> - **Migration (one change for users, not two):**
>   - Release N: wherever the interim rule grants `Eq` and `==` is used, the compiler emits a warning with the machine-applicable `@derive(Eq)` fix, and `blink fix` applies it.
>   - Release N+1: the warning becomes an error.
>   - src/ (NodeKind, TokenKind) follows the 3-step bootstrap dance. Its size should be measured before the vote, not guessed.
> - **Cross-language:** Haskell, Rust and OCaml-with-ppx all require `deriving`. Only SML's `eqtype` is implicit, and SML has no user `Eq` impls to conflict with, so that design does not transfer.
>
> **Proposal B (fallback): payload-free enums are implicitly `Eq`. Any enum with a payload needs the derive.**
>
> ```blink
> type Color { Red  Green }          // Eq implicitly (fieldless)
> @derive(Eq)
> type Shape { Circle(r: Int)  Sq(s: Int) }
> ```
>
> - **For:** "fieldless enum" is already a category in the spec (Tag Operations, §3.x). Adding the first payload already breaks `to_int`, `from_int` and Int comparison, so the extra break on `==` comes at the same edit, with a fix-it. Equality on a finite set of tags is decidable and has no representation to hide. It also has the smallest migration.
> - **Against:** structs and enums still follow different rules, and implicit `Eq` sits next to explicit `Hash` (`Set[Color]` still needs `@derive(Hash)`, which supplies `Eq` as the supertrait anyway). A user still cannot override a fieldless enum's `Eq`. Is that an error, or does a written impl replace the implicit one? The spec must answer that coherence question.
>
> **Rejected: keep the interim rule as final.** Defects 1–3 above stay. At minimum the spec would have to choose a fixed point for recursive enums and define bound inference a second time.
>
> **Also required whichever option wins:** the spec says that a `@derive(Eq)` on a recursive type is resolved coinductively (the impl being defined is assumed while its own fields are checked). That is what the compiler does today: I measured `type Json { Null  Arr(xs: List[Json]) }` with build/blink, and `a == b` prints `true`.
>
> **Vote preference:** A, then B. A is the principled choice: one rule for all nominal types, and no inference to undo later.

**DevOps:**

> **DevOps/Tooling panelist: Phase A proposal**
>
> My lens is where the error lands, whether a tool can fix it, and whether the LSP can answer "is this Eq?" by reading the declaration.
>
> ---
>
> ### Proposal D1 (preferred): any enum is Eq only through `@derive(Eq)` or `impl Eq`, with a `blink fix` migration
>
> ```blink
> @derive(Eq, Debug)
> type Shape { Circle(r: Int)  Sq(s: Int) }
>
> @derive(Eq)
> type Color { Red  Green }
>
> type Bag { Items(xs: List[Widget])  Empty }
>
> fn main() {
>     let a = Shape.Circle(1) == Shape.Circle(1)   // ok
>     let b = Some(Color.Red) == Some(Color.Red)   // ok: Container Equality + derive
>     let c = Bag.Empty == Bag.Empty               // error
> }
> ```
>
> Diagnostic at the use site:
>
> ```
> error[E0xxx]: `Bag` does not implement `Eq`
>   --> main.bl:10:13
>    |
> 10 |     let c = Bag.Empty == Bag.Empty
>    |             ^^^^^^^^^^^^^^^^^^^^^^
> help: add `@derive(Eq)` to `type Bag`   [machine-applicable]
> ```
>
> If the user then adds the derive and `Widget` has no Eq, `E1401` fires at the derive line in the declaration and names `List[Widget]`. That is the place the fix belongs.
>
> **Why this wins on diagnostics:**
>
> 1. **No action at a distance.** Under the interim rule, `Bag.Empty == Bag.Empty` breaks because a *different* variant has a non-Eq payload. Worse, adding a variant to `Shape` silently turns every `==` on `Shape` across the codebase into an error, reported at call sites far from the edit. With an explicit derive, the same edit gives one `E1401` at the declaration that changed. rust-analyzer and Go vet users expect the error to point at the edit.
> 2. **The LSP can answer from the declaration.** Hover over `Shape` shows `derives: Eq, Debug`. Completion can offer `==` only when the derive or impl is there. Under the structural rule the server has to walk every payload type (recursively, across modules) to answer hover. That is slower, and the answer is invisible to a human reading the source.
> 3. **One rule for structs and enums.** Structs already need the derive. A single error template and a single fix-it cover both. A payload-free/data split would need two help texts, and per aiml's point it changes behaviour when the first payload is added. Tools pay for that: the fix-it has to fire *at the moment of the payload edit*, which is a worse experience than "you never had implicit Eq".
> 4. **Consistent with Hash.** Keys already need `@derive(Hash, Eq)` even for payload-free enums (fvceqe). Today a user can write `Color.Red == x` freely, then gets E1400 on `Set[Color]`. Requiring the derive removes that surprise. The `Set` fix-it and the `==` fix-it become the same edit.
> 5. **Bare vs wrapped is trivially the same answer.** `Option[E]` defers to `E: Eq`, and `E: Eq` depends only on a visible annotation.
>
> **Migration (this answers the "changes twice" concern):** use the rollout pattern §3.6 already defines (line ~2774). For one release, an enum that relies on implicit Eq gives a **warning** with a machine-applicable `@derive(Eq)` that `blink fix` inserts on the declaration, not at each call site. So the edit count is one per enum type, not one per `==`. src+lib has ~157 type declarations, a bounded mechanical sweep with `blink fix`. The next release makes it an error. Decide now so the interim rule never reaches a release as a stable promise.
>
> **Tag comparison carve-out:** `Color.Red < Color.Green` and `Color.Red == 2` stay tag operations on fieldless enums, per the decided Int-distinct rule. They are not Eq/Ord. The diagnostic for `==` between two `Color`s with no derive must not suggest `.to_int()` as a workaround. It must offer the derive.
>
> Cross-language: Rust (explicit derive everywhere; the derive line is what every reader and tool keys off), Haskell `deriving (Eq)`. Swift auto-synthesizes Equatable only for payload-free enums, and its "type does not conform" errors after a payload is added are a known pain point.
>
> ---
>
> ### Proposal D2 (fallback): payload-structural Eq, made legible
>
> If the panel keeps "Eq when all payloads are Eq", tooling needs three things:
>
> - The error must name the **variant** that blocks Eq: `note: variant Bag.Items carries List[Widget], which is not Eq`, not just the payload type.
> - LSP hover shows `Eq: inferred (all payloads Eq)` or `Eq: no (Bag.Items)`.
> - A lint `implicit_enum_eq` (off by default) for teams that want D1's locality.
>
> Cost: two answers to "how do I get Eq" (structs derive, enums infer), and errors at call sites remote from the edit.
>
> ---
>
> ### Rejected: payload-free implicit, data enums derive
>
> Adding the first payload flips every `==` site from ok to error. That is the worst diagnostic shape of the three options.
>
> **Preference: D1**, with the warning-first `blink fix` migration shipped in the same release that fixes the rule.

**AI/ML:**

> I prefer Proposal 1: an enum is Eq when all of its payloads are Eq. A payload-free enum is just the zero-payload case of that rule.
>
> # AI/ML panelist: Phase A proposal (nxd4s5)
>
> ## Proposal 1 (preferred): make the interim rule final, as one rule for all enums
>
> Proposed text for §3.6 (it replaces "Enums (interim rule)"):
>
> > **Enums.** An enum with no `impl Eq` is `Eq` when every payload type of every variant is `Eq`. A payload-free enum has no payloads, so it is always `Eq`. A written `@derive(Eq)` on an enum is allowed and has the same effect. A written `impl Eq` replaces the structural rule.
>
> ```blink
> type Color { Red  Green }
> type Shape { Circle(r: Int)  Sq(s: Int) }
> type Bag { Items(xs: List[Widget])  Empty }   // Widget has no Eq
>
> Color.Red == Color.Green                 // OK
> Shape.Circle(1) == Shape.Circle(1)       // OK: Int is Eq
> Some(Shape.Sq(2)) == None                // OK: same answer bare and wrapped
> Bag.Empty == Bag.Empty                   // error: `Bag` is `Eq` only if `List[Widget]` is `Eq`
>                                          // help: add `@derive(Eq)` to `type Widget`
> ```
>
> **Why this fits generation and learning:**
> - **No split between payload-free and data enums.** A model does not need to know which kind of enum it has. Last round I said a split "is a rule a model will apply wrongly when it adds the first payload". Under this rule, adding `Circle(r: Int)` to an enum keeps every `==` working. Only a non-Eq payload breaks it, and then the diagnostic names that payload type.
> - **It agrees with the tag operations, which are already decided.** §3.3 "Tag Operations" defines `==` between a payload-free enum and `Int` with no derive. Under any "derive required" rule, `s == 2` compiles but `s == State.Running` fails until you add a derive. A model cannot predict that from the spec, and a human cannot either. This alone rules out Proposal 2 unless we reopen tag operations.
> - **It holds whatever habits the model brings from training data.**
>   - Rust-trained models write `@derive(Eq, Debug)` on every enum out of habit. That stays legal and silent, so it costs zero fix rounds. The spec must say a redundant derive gets no warning.
>   - Python, TypeScript, Kotlin and Swift-trained models expect `if c == Red` to work. It does.
> - **No migration.** Same-enum `==` already works this way today. Nothing changes and nothing is rewritten. The concern four panelists raised, that user code would change twice, goes away.
> - **Low token cost.** The common pattern, comparing a state or kind enum, needs no annotation. `src/` alone has about 68 type declarations and compares NodeKind and TokenKind everywhere.
> - **The diagnostic does not change.** It names the innermost failing type and offers `@derive(Eq)` there. That fix can be applied by a machine.
>
> **Tradeoffs (stated honestly):**
> - **Structs and enums differ.** A struct needs `@derive(Eq)`, an enum does not. That is one extra sentence for a model to learn. I accept it because the alternative breaks against tag operations.
> - **Hash still needs a derive.** `Set[Color]` needs `@derive(Hash, Eq)`, which was decided in fvceqe. A model that has seen `Color == Color` work will expect `Set[Color]` to work, and it fails. That gap is real, but it gives an early error with a fix that a machine can apply, so it is cheap. I do not reopen it here. I flag it so the record says this is now the only remaining difference.
> - **A payload change can break `==` far away.** If a payload type loses Eq, `==` fails at a distant call site. The diagnostic's chain covers this.
>
> ## Proposal 2 (rejected, listed for the record): every user type needs a derive or impl, Rust-style
>
> ```blink
> @derive(Eq)
> type Color { Red  Green }
> ```
>
> - **For:** one sentence covers structs, enums, Eq and Hash. It matches Rust, which has the most training data for "a derive is needed".
> - **Against:**
>   - It contradicts the decided rule that `Enum == Int` needs no derive, as shown above.
>   - It is a large migration, done in three bootstrap steps. Step one adds the derive alongside the old rule, step two migrates src/ and lib/, step three removes the old rule. NodeKind, TokenKind and about 68 type declarations in src/ alone. User code changes twice (interim, then final), which is the concern four panelists raised.
>   - A model trained on Python, TypeScript, Kotlin or Swift needs one fix round on the most common enum pattern (`if c == Red`).
>   - About 6 tokens added to each enum declaration.
>
> **Side note for the moderator (Ord):** Payload-free `Color.Red < Color.Green` compiles through the tag today. Data-enum `<` with no Ord reaches an internal compiler error. To match Proposal 1, the Ord ticket should say: payload-free enums are ordered by tag (this follows from tag operations); data enums are Ord only through `@derive(Ord)` or a written impl. There is no structural Ord, because using variant order as a ranking is a semantic choice the user must make on purpose. Separate ticket.
>
> **Cross-language:**
> - Swift synthesizes Equatable with no declaration only for enums without associated values. Enums with associated values must declare it. That is min's split, and Swift users often hit it.
> - Rust and Haskell always need a derive.
> - OCaml has structural `=` on all variants.
> - Kotlin enum classes compare by identity; sealed hierarchies need `data` classes.
>
> Proposal 1 is closest to OCaml for enums and stays nominal for structs. Its payload-free case matches what Swift, Kotlin, Python and TypeScript users expect.
>
> **Preference: Proposal 1** (structural: an enum is Eq when all payloads are Eq; redundant `@derive(Eq)` is legal and gets no warning; a written `impl Eq` replaces the structural rule). Reason: one rule for every enum, no migration, and it agrees with the decided tag operations (`Enum == Int` needs no derive).

**Minimalism:**

> **Minimalism panelist, Phase A: enum Eq (nxd4s5)**
>
> I am changing my earlier position. I no longer prefer "data enums need a derive". I now say the interim rule should become the final rule. The reasons come from things the panel has already decided.
>
> ---
>
> **Proposal M1 (preferred): Make the interim rule final. Keep the spec text, delete the word "interim".**
>
> An enum is `Eq` when one of these is true: it has a written `impl Eq`, it has `@derive(Eq)`, or every payload type is `Eq`. A payload-free enum is therefore always `Eq`. `@derive(Eq)` on an enum is optional. It works as a check at the declaration: if a payload has no Eq, E1401 fires on the `type` line and not at some distant `==`.
>
> ```blink
> type Color { Red  Green }
> type Shape { Circle(r: Int)  Sq(s: Int) }
> type Bag { Items(xs: List[Widget])  Empty }   // Widget has no Eq
>
> fn main() {
>     assert(Color.Red != Color.Green)            // ok
>     assert(Shape.Circle(1) == Shape.Circle(1))  // ok: Int is Eq
>     let a: Option[Shape] = Some(Shape.Sq(2))
>     assert(a == Some(Shape.Sq(2)))              // ok: same answer wrapped
>     // Bag.Empty == Bag.Empty  -> error: `Bag` is Eq only if `List[Widget]` is Eq
> }
>
> @derive(Eq)          // optional check; E1401 here if a payload is not Eq
> pub type Event { Click(x: Int, y: Int)  Key(code: Int) }
> ```
>
> Why this is the smallest choice:
> - **No new rule.** It is the same recursive check that Container Equality already uses. An enum becomes "a tagged container of its payloads". The predicate is already in the spec and already in the compiler (measured: all three cases in the brief behave this way today).
> - **Zero migration.** Nothing changes for user code, src/, or lib/. That fully answers the four-panelist worry that "code changes twice".
> - **One rule, not two.** aiml was right that a payload-free/data split breaks when someone adds the first payload. Under M1, adding `Circle(r: Int)` keeps Eq. Adding a non-Eq payload gives a precise error that names the payload and offers a fix.
> - **Payload-free enums must be Eq anyway.** The panel decided that `Color.Red == 1` compares the tag. A rule where `Color.Red == 1` compiles but `Color.Red == Color.Green` does not would be absurd. That rules out plt's "derive or impl only" rule for payload-free enums, so the only open question is about data enums. M1 answers it with the predicate we already have.
> - **The difference from structs has a real reason.** A struct can hold fields that should not count for equality (caches, counters, handles), so a written `@derive(Eq)` is the author's statement that field-by-field comparison is correct. Enum payloads are all visible through `match`, so structural `==` shows nothing that pattern matching does not already show. Tuples are auto-derived for the same reason (5-0).
>
> What it costs:
> - **A library-evolution risk.** A `pub` enum can silently lose Eq when someone adds a non-Eq payload, which breaks downstream `==`. Go has the same risk with struct comparability and lives with it. The fix is the optional `@derive(Eq)` check above: library authors who care pin the contract with it. It needs no new feature. A lint for "pub data enum without derive(Eq)" is YAGNI until someone actually reports this problem.
> - **Hash stays explicit** (decided, fvceqe). So `@derive(Hash, Eq)` is still written for keys, and the `Eq` in that list is redundant for enums. That is harmless and keeps one spelling for keys across structs and enums.
>
> Cross-language: Go structural comparability (implicit, recursive); Haskell and Rust need `deriving` / `#[derive]`; Swift synthesizes `Equatable` for enums without associated values but needs a declared conformance once payloads exist (aiml's critique of that split applies to Swift too).
>
> ---
>
> **Proposal M2 (fallback): Data enums need `@derive(Eq)`. Payload-free enums stay implicit.** This was my old position.
>
> ```blink
> @derive(Eq)
> type Shape { Circle(r: Int)  Sq(s: Int) }
> ```
>
> It matches structs and Rust. But it means two rules, the trap of adding the first payload, and a migration (a machine-applicable fix that inserts `@derive(Eq)`, a warning cycle, then an error). That is the "change twice" churn the earlier panel warned about. It adds ceremony and removes nothing.
>
> ---
>
> **Rejected: "Eq only through derive or impl" for every enum (plt).** It clashes with the decided tag comparison against Int, and it means a large migration of src/ (NodeKind, TokenKind) for no gain in soundness.
>
> **Out of scope, but noted:** data-enum `Ord` reaches an ICE today. It needs its own ticket. I would not extend M1's implicit rule to `Ord`, because declaration order as a sort order is a choice the author should state.
>
> **I prefer M1:** it costs nothing, needs no migration, uses one predicate, and the current compiler already does it.

#### Phase B — Debate

##### Round 1

The mechanical dedupe of Phase A gave three options:

- **Option A — every user enum is Eq only through `@derive(Eq)` or a written `impl Eq`, payload-free included.** Preferred by plt (Proposal A) and devops (D1). Both attach a warning-for-one-release → error migration with a machine-applicable `@derive(Eq)` fix.
- **Option B — a payload-free enum is Eq implicitly; an enum with any payload is Eq only through `@derive(Eq)` or `impl Eq`.** Preferred by sys (S1) and web (W1). Fallback of plt (Proposal B). min's earlier position (now M2 fallback). Same warning → error migration for data enums only.
- **Option C — make the interim rule final: an enum with no impl/derive is Eq iff every payload type is Eq; payload-free is always Eq; `@derive(Eq)` is optional.** Preferred by min (M1) and aiml (Proposal 1). Fallback of sys (S2), web (W2) and devops (D2).

Replies, verbatim:

**Systems:**

> Systems, Phase B round 1. Ranking: B > C > A (unchanged).
>
> **B answers every plt defect, and does it without A's cost.**
> plt listed three defects in the interim rule. B removes all three:
> 1. Representation leak: a payload-free enum has no payloads, so it has nothing to leak. A data enum states its Eq with a derive.
> 2. Silent wrong answers (`Frac`): under B, `Frac` needs a derive or an impl, so the author makes that choice.
> 3. Recursion: a payload-free enum cannot refer to itself, so it needs no fixed point. A recursive data enum goes through `@derive`, which is coinductive. I agree the spec must say this whichever option wins.
> A adds only one thing over B: a derive on payload-free enums. That clashes with the decided tag operations. plt is right that `(Enum, Int) ==` is a separate operator, so A is sound. But plt then needs `@derive(Ord)` for same-enum `<`, which reopens a decided rule. A buys no soundness over B and costs a src/ migration.
>
> **To min and aiml (C):**
> - min: "Enum payloads are all visible through `match`, so structural `==` shows nothing." Struct fields are visible too, and the panel still required a derive for structs. Visibility is not the issue. The issue is whether structural identity is the right equivalence, and `Frac` shows it can be wrong.
> - min: "the optional `@derive(Eq)` pins the contract." Only for authors who already know the risk. The safe choice should be the default. Under C, the derive is an annotation that changes nothing unless it fails.
> - aiml: "the first payload breaks under a split." Under B it breaks at every `==` site with a machine-applicable fix, at the same edit that already removes `to_int`, `from_int` and `<`. That is one boundary, "fieldless or not", and the spec already draws it. Under C, the breakage happens later and far away: someone adds a non-Eq payload, and `Option[E]` sites in other packages fail.
> - devops (hover): under B, the LSP still answers from the declaration in O(1): either there is no payload, or it looks for a derive or impl. Under C it has to walk payload types across modules.
>
> **Variations:**
> 1. A redundant `@derive(Eq)` on a payload-free enum: legal, no warning (Rust habit, as aiml says).
> 2. A written `impl Eq` on a payload-free enum: it replaces the implicit tag compare, the same way a user impl replaces a derive. Tag operations against `Int` stay as they are. The spec must say this, or there are two impls and no coherence rule.
> 3. Recursive: coinductive resolution for derive and impl, stated in the spec (plt). Agreed.
> 5. Ord (separate ticket): payload-free enums are ordered by tag. Data enums get Ord only through a derive or impl, with no structural Ord. I agree with aiml and min.
> 6. If C wins, my S2 condition stands: losing structural Eq on a `pub` enum is a breaking change, and the error names the blocking variant (devops D2).
>
> **Codegen note:** all three options emit the same per-type eq function. This choice costs nothing at runtime.
>
> **Migration count:** B touches only data enums compared with `==`. I will read the number when it arrives. It changes my ranking only if B's cost comes close to A's, and it cannot exceed A's.
>
> STABLE: ready to vote

**Web/Scripting:**

> Web Phase B round 1: I keep Option B (fieldless enums Eq implicitly, data enums derive). C is my second choice, A last.
>
> **For B, against the "first payload" objection (aiml, devops, min):** plt's own fallback text answers it. Adding the first payload already breaks `to_int`, `from_int`, `Enum == Int` and tag `<`. The spec already treats "fieldless" as a separate category, and that edit already changes the category. One more break at the same edit, with a machine-applicable fix, is no new surprise. B also gives the same split as the Ord direction that aiml and min proposed (fieldless ordered by tag, data enums Ord only through a derive). B makes Eq and Ord follow one rule. C makes Eq structural and Ord nominal, which is two rules.
>
> **Against C (min, aiml):** the familiar web languages do not give records structural `==` for free. They make you opt in: Python `@dataclass`, Kotlin `data class`, Java `record`, and TS has no structural `===` at all. So "data needs an opt-in, constants compare freely" is what a JS, Python or Kotlin developer already expects. C's real cost is the question "I didn't touch this file, why did `==` break?" A payload edit in module X causes errors at call sites in module Y (sys, devops). Under B the error is on the line the author edited. min's "enum payloads are visible through match" argument is fair, but an enum payload can hold a handle or a cache just as a struct field can.
>
> **Against A (plt, devops):** plt calls it sound. Sound is not the same as learnable. If `c == 1` compiles and `c == Color.Red` does not, that becomes a Stack Overflow question on day one. devops's carve-out (tag ops are not Eq) means teaching two meanings of `==` on the same type. Hash is the only asymmetry left under B, and it is already decided.
>
> **Variations:**
> 1. A redundant `@derive(Eq)` on a fieldless enum is legal and silent, because Rust habits should cost nothing (aiml). Under B it still triggers the E1401 declaration check, which is harmless.
> 2. A written `impl Eq` on a fieldless enum is an error ("fieldless enums compare by tag"). Letting it replace the tag compare would split `==` from `Enum == Int` and from `@derive(Hash)`, which hashes the tag. That breaks the Hash/Eq law. Nobody needs custom Eq on a set of constants (YAGNI). For data enums, `impl Eq` is the normal opt-in.
> 3. Recursive types: I agree with plt that derive resolves coinductively. B needs no implicit fixed point.
> 4. Covered under "Against A" above.
> 5. Ord: fieldless enums by tag, data enums only through derive or impl. That is exactly B's shape.
> 6. If C wins, I support all of devops D2 (error names the variant, LSP hover, opt-in lint) and sys's rule that a `pub` enum's structural Eq is API.
> 7. Migration under B touches data enums only, one `@derive(Eq)` per type through `blink fix`, and fieldless NodeKind/TokenKind need no change. I want the counts before the vote.
>
> NOT STABLE: migration counts for A and B are still pending, and variation 2 (`impl Eq` on a fieldless enum: error or replace) needs a ruling.

**PLT:**

> plt Phase B round 1: I move from A to B. B is now my preference, and I rank C last.
>
> **Concession (A to B).** My Phase A defence of A ("the tag comparison is a separate (Enum, Int) operator") is sound for typing. It fails a stronger test: whether the operators of one type agree with each other. The tag operations are decided. A fieldless enum already has `c == 1`, `to_int` and `from_int`, and these fix the meaning of its values as tags. Suppose a fieldless enum could carry a written `impl Eq` that differs from tag identity. Then `c == 1 && d == 1` could hold while `c != d`. That breaks no Eq law on `Color` alone, but two `==` operators on the same values would disagree. So the decided tag operations already commit a fieldless enum to one equality: tag identity. A rule that makes you write a derive for an equality with only one possible value is ceremony, not principle. web, sys, min and aiml were right on this point.
>
> **Refinement of B (answers variation 2):**
> - A fieldless enum is `Eq` by tag identity.
> - `@derive(Eq)` on a fieldless enum is legal and gets no warning. That keeps `@derive(Hash, Eq)` one spelling for keys.
> - A written `impl Eq` on a fieldless enum is an error, for the reason above: one equality per type, so coherence holds.
> - An enum with at least one payload is `Eq` only through `@derive(Eq)` or `impl Eq`, the same as a struct.
>
> **B removes the open recursion question (variation 3).** A fieldless enum cannot recurse. A data enum gets `Eq` only through a declared impl, which is resolved coinductively (the compiler does this today). The spec never needs to choose a fixed point for an implicit rule. C still needs that choice (greatest fixed point, matching the compiler) and also needs the bound inference of §3.8 written a second time for implicit `Eq`.
>
> **Rebuttals to C:**
> - min: "payloads are visible through match, so structural == shows nothing." Visibility is not the issue. The issue is which equivalence the author intends. `type Frac { F(n: Int, d: Int) }` is fully visible, and structural `==` on it is wrong. The same argument applies to structs, and the panel already decided that structs need a derive.
> - aiml: "no split on the first payload." C has the split too, just at another point. Adding the first payload under C keeps `==` but loses `<`, `to_int`, `from_int` and Int comparison. B puts every one of these losses on that same edit, so "fieldless" is the only line to learn. That is less for a model to learn than C's "some tag operations survive a payload, some do not".
> - "Code changes twice": the edit is one `@derive(Eq)` per compared data enum, and `blink fix` applies it. The interim text was never a stable promise. The measured count will set the size, but I do not expect it to change the ranking.
>
> **Ord (variation 5):** I withdraw "fieldless `<` needs `@derive(Ord)`". Under B, the consistent rule is that fieldless enums are ordered by tag, and data enums are Ord only through a derive or impl. That matches aiml and min. It stays a separate ticket.
>
> **Ranking:** B > A > C.
>
> STABLE: ready to vote

**DevOps:**

> DevOps, Phase B round 1: I change my preference from A to B. Order is now B > A >> C.
>
> **Concession: I was wrong about B.** I called B "the worst diagnostic shape" because the first payload flips `==` sites. On reread that edit is not action at a distance. The break follows a deliberate edit to that same declaration. Each error carries one fix-it that targets that declaration. `blink fix` dedupes it to one `@derive(Eq)` per type. And the same edit already removes `to_int`, `from_int` and Int comparison (sys, plt B). So users learn one fact: a payload ends the "named constants" category.
>
> **Why B over A, on tooling grounds.** web, sys, min and aiml are right about the tag-ops conflict. plt's operator argument is sound, but my objection is to the diagnostic. Under A, `m == 0` compiles and `m == Mode.On` is an error. Users will route around the error with `m.to_int() == Mode.On.to_int()`, and an LSP quick-fix list cannot stop that. That code is weaker and the lint surface gets worse. A diagnostic that invites a worse workaround is a bad diagnostic.
>
> **Why B keeps my Phase A criteria.** My two key criteria were (1) Eq depends only on the type's own declaration, and (2) the LSP answers hover with no payload walk. B meets both: "has no payloads" is visible on the `type` line. A meets them. C fails both: Eq depends on payload types in other modules, and adding a non-Eq payload breaks `==` in places that never changed. That is why C stays last. I drop D2 as a fallback, except as minimum requirements if C wins.
>
> **Positions on the flagged variations (under B):**
> 1. A redundant `@derive(Eq)` on a payload-free enum is legal and gets no warning. Rust-trained output must not cost a fix round.
> 2. A written `impl Eq` on a payload-free enum replaces the implicit impl, the same as a derive does. The implicit impl exists only when there is no impl and no derive. That is one coherence rule with nothing new to diagnose.
> 3. Recursive types: coinductive, as plt states. That is what the compiler does today.
> 5. Ord, on the separate ticket: payload-free enums are ordered by tag, data enums need a derive. This matches B exactly.
> 6. B needs these tooling requirements:
>    - The `==` error on a data enum adds `note: only enums with no payloads are Eq without @derive(Eq)`.
>    - The E1400 help on `Set[Color]` says "payload-free enums are Eq automatically; keys also need `@derive(Hash)`", as web asked.
>    - The migration warning fires at the use site, but its fix-it edits the declaration, one per type.
>    - The LSP hover shows `Eq (payload-free)` or `Eq (derived)`.
> 7. The count changes the size of the migration, not the rule. Under B, src NodeKind/TokenKind need no edit, and only compared data enums need a derive. I do not need the number to vote.
>
> STABLE: ready to vote

**AI/ML:**

> aiml, Phase B round 1: I keep C, I now accept B as a fallback, and I still reject A.
>
> **Against A (plt, devops).** plt is right that a separate `(Enum, Int)` operator is sound. But it is not learnable from the spec. Under A, `c == 1` and `c < Color.Green` compile, while `c == Color.Green` fails. A model reads "fieldless enums have tag comparison" and generalizes it to same-enum `==`, and so would a human. A rule that is sound but goes against what a reader predicts costs a fix round on the most common enum line there is. Hash consistency (devops point 4) does not outweigh that: that surprise happens once per key type, while `if tok == Kind.Eof` happens everywhere.
>
> **Concession to sys (point 3).** The first payload already removes `to_int`, `from_int` and comparison with Int. So under B, "fieldless enum = named constants, data enum = struct" is one boundary the spec already draws. My "first payload" objection to B is now weaker, and I move B from rejected to acceptable fallback.
>
> **Why C still beats B for generation:**
> - **Fix rounds.** Under C, Rust-style output (which over-derives) and Swift/Python-style output (which never derives) both compile on the first try. Under B, the second group needs one fix round per data enum.
> - **plt defect 2 (Frac).** A required derive does not make the semantic choice deliberate when an AI writes the code: models write `@derive(Eq, Debug)` by reflex. What protects Frac is the written `impl Eq`, and that is available under every option.
> - **Action at a distance (sys, devops).** This is real, so I adopt min's refinement: a written `@derive(Eq)` on an enum is a check at the declaration. E1401 fires on the `type` line. Library authors pin the contract with it, and no new feature is needed.
>
> **Refinements to C. Each is one spec sentence:**
> 1. **Redundant derive:** legal, no warning, and it checks at the declaration (min). This settles variation 1.
> 2. **Written `impl Eq`:** replaces the structural rule, never conflicts with it. This settles variation 2 and also applies to fieldless enums under B.
> 3. **Recursion (plt):** the structural predicate resolves coinductively, like a derive: the enum is assumed Eq while its payloads are checked. That is the greatest fixed point, and it is what the compiler does today with `Json`. plt asks that the same sentence be stated whichever option wins.
> 4. **Tooling (devops D2):**
>    - Yes to naming the blocking variant: `variant Bag.Items carries List[Widget]`.
>    - Yes to an LSP hover that shows whether Eq is inferred and why.
>    - No to an `implicit_enum_eq` lint: YAGNI.
> 5. **sys S2 (pub API):** one non-normative note that a `pub` enum's structural Eq is part of its API, with the fix being to pin it with `@derive(Eq)`. Tooling that enforces it is YAGNI.
>
> **Ord (variation 5).** Under A, plt's "same-enum `<` needs `@derive(Ord)`" would also gate tag `<`. That is the same learnability problem again. My position stays: fieldless enums are ordered by tag, data enums are Ord only through a derive or impl.
>
> **Preference: C > B >> A.**
>
> NOT STABLE: the measured migration count for A/B is still pending, and B and C still need the coinductive recursion sentence (point 3) written into the spec text.

**Minimalism:**

> min, Phase B round 1: I move to Option B. C is now my fallback, and I still reject A.
>
> **Why I am leaving C.** In Phase A I said C adds "no new rule". plt showed that this is wrong. Container Equality covers built-in containers with fixed type parameters. Applied to user nominal enums, C becomes an implicit derive. It needs its own bound inference for generics (`Tree[T]`), its own fixed point for recursion (`Json`), and its own override rule (aiml: "a written impl Eq replaces the structural rule"). §3.8 already defines all three for `@derive`. Under C the spec says each of them twice. Minimalism counts spec concepts, not keystrokes.
>
> **Why B is the smaller spec.** B adds no category. "Fieldless enum" already exists (tag operations, decided 6-0), and "a data type needs a derive" already exists (structs, decided). sys answers aiml's first-payload trap, and I accept the answer: the first payload already removes `to_int`, `from_int` and comparison with Int, so `==` going too at the same edit is the same fact, not a second one. plt's single-variant case decides it for me: `type P { P(x: Int, y: Int) }` and `type P { x: Int  y: Int }` must not get different Eq rules. Under C they do. Under B they do not.
>
> **Against A (plt, devops).** A turns a fieldless enum into the one type where `c == 0` and `c < Color.Blue` compile but `c == Color.Red` does not. plt calls this "sound", and it is. It is also a second operator for the same question. Hash needing a derive is the fixed cost of keys (fvceqe). It does not argue for adding ceremony to `==`.
>
> **Positions on the variations:**
> 1. A redundant `@derive(Eq)` on a fieldless enum is legal and gets no warning (aiml's point about training habits).
> 2. Under B, a written `impl Eq` on a fieldless enum is an **error**. It should not replace the implicit rule. If an override were allowed, `Color.Red == 0` (tag) and `Color.Red == Color.Zero` (impl) could disagree. Forbidding it removes the coherence question plt raised and costs nothing, because tag equality is the only sane Eq on a fieldless enum.
> 3. Recursion: I adopt plt's sentence. A derive on a recursive type resolves coinductively. Under B that is the only place the sentence is needed.
> 5. Ord, for its own ticket: fieldless enums are ordered by tag, data enums only through a derive or an impl. No structural Ord.
> 6. If C wins anyway: the diagnostic names the blocking variant (cheap, and it helps). I reject the `implicit_enum_eq` lint and the "pub structural Eq is API" rule. Both add tooling to patch over the rule, which argues against C.
> 7. Migration: B changes only data enums, and `blink fix` inserts the derive once per declaration. If the measured count is large, I will weigh C again, but I expect it to be small.
>
> NOT STABLE: the measured migration count for B (data-enum declarations that rely on implicit Eq) is still open. I am ready to vote once it is posted.

##### Round 2

Measured fact given to the panel:

> Method: a scratch copy of the tree. A baseline compiler and one compiler per rule were built from src/cli.bl, then `check` ran on 2016 files (src/compiler.bl, src/cli.bl, lib/std/*, lib/pkg/*, all 1964 tests/test_*.bl). The baseline gives 0 Eq errors. Each site is counted once per file:line:col. `@derive(Ord)` / `@derive(Hash)` count as derived Eq (that is how the compiler treats them; this was not tested separately).
>
> Rule B (payload-free implicit, data enums need derive/impl): 24 new sites.
> - src/: 0, lib/: 0, tests/: 24.
> - 5 enums in 4 test files: Shape (12), Chain (4), Tree (3), ByValSlot (3), AggShape (1), plus 1 wrapper report (List[Shape]).
>
> Rule A (every enum needs derive/impl): 1730 new sites.
> - src/: 1504, lib/: 0, tests/: 226.
> - 28 distinct payload-free enums (20 in src/). TyKind 1244 sites, NodeKind 221, TokenKind 99, SlotForm 50; the rest have 6 or fewer.
>
> Rule C (interim rule final): 0 new sites (it is the current behavior).

Replies, verbatim:

**Systems:**

> Systems, Phase B round 2. Ranking: B > C > A (unchanged).
>
> **Migration counts settle the cost question.** B: 24 sites, all in tests/, from 5 enums in 4 files, so 5 `@derive(Eq)` lines. src/ and lib/ need nothing, so no bootstrap dance and no gen0 re-pin. A: 1730 sites, 1504 of them in src/ (TyKind alone has 1244), which needs a full 3-step bootstrap for zero soundness gain over B. C: 0. B costs almost nothing. That answers the "code changes twice" concern from the earlier panel: user code changes once at most, and in practice almost nobody's does.
>
> **Variation 2: I change from "replaces" to "error"** (agreeing with plt, min and web). The argument that convinced me is plt's: the decided tag operations already define a fieldless enum's equality as tag identity. If a written `impl Eq` could override it, `c == 1 && d == 1` with `c != d` becomes possible, and web is right that `@derive(Hash)`, which hashes the tag, would then break `Hash: Eq`. From the systems side, an error also guarantees that same-enum `==` on a fieldless enum is always one integer compare. Codegen never has to check for an override, and `match`-on-tag and `==` can never disagree. devops and aiml: "replace" needs one more coherence rule, while "error" needs none, because the type has exactly one equality.
>
> So my full B text:
> - A fieldless enum is `Eq` by tag identity.
> - A redundant `@derive(Eq)` on it is legal and silent.
> - A written `impl Eq` on it is an error, and the error text says "fieldless enums compare by tag".
> - An enum with any payload is `Eq` only through `@derive(Eq)` or `impl Eq`, the same as a struct.
> - A derive or impl on a recursive type resolves coinductively (plt's sentence).
> - Migration: one release of warnings at use sites, with a fix-it that edits the declaration (devops), then an error.
>
> **To aiml (C):** "models write `@derive(Eq, Debug)` by reflex, so the derive protects nothing." It still places the error at the declaration and makes Eq readable from the `type` line, which was my point and devops's. The Frac protection is a separate argument. And under B, a Python/Swift-style model pays one fix round per data enum. The measured count shows that is rare: 5 enums in a 2016-file corpus.
>
> **devops's tooling list (note on data-enum `==` error, E1400 help text, hover):** I support it as requirements on the implementation ticket.
>
> STABLE: ready to vote

**Web/Scripting:**

> Web Phase B round 2: B, unchanged. The counts close my migration concern, and I add one new argument on variation 2.
>
> **Migration count:** under B there are 24 sites, all in tests/, across 5 enums, with 0 in src/ and 0 in lib/. That is one `@derive(Eq)` on each of 5 declarations, so "code changes twice" is not a real cost for B. Under A there are 1730 sites, 1504 of them in src/, for derives on enums where only one equality is possible. The numbers back the conclusion plt, devops and min reached by argument. B > C > A stands.
>
> **To aiml (C over B for fix rounds):** with 24 sites in 2016 files, the fix-round cost under B is small, and each fix is a machine-applicable one-liner on the declaration. aiml also concedes that a reflexive `@derive(Eq, Debug)` does not make the choice deliberate. That holds under C too, so it does not favor C. B's real gain is still locality: the error appears where the payload was added, not in another package.
>
> **Variation 2 (written `impl Eq` on a fieldless enum), the 3-3 split. I hold "error", and I add a tiebreaker for sys, devops and aiml:**
> - **Forward compatibility.** If we ship "error" and someone later finds a real need, changing it to "allowed, replaces the tag compare" is non-breaking, because no existing program changes meaning. If we ship "replaces" and later find the coherence problem real, going back to "error" is breaking. When the panel is split and the need is unproven, take the choice that can be relaxed later.
> - **The coherence problem is real (plt, min).** `c == 1` stays a tag compare under every option. With a replacing impl, `c == 1 && d == 1` can be true while `c != d`. "impl replaces derive" (sys, devops) works for data types because they have no second built-in `==`. A fieldless enum has one.
> - **No use case was named.** Nobody in Phase A or round 1 gave an example of a fieldless enum that needs a non-tag Eq. If a user wants `Gray`/`Grey` to be equal, the honest model is a data enum or an alias, not an override.
> - **Diagnostic** (for devops's tooling list): "fieldless enum `Color` already compares by tag; a written `impl Eq` is not allowed. help: give the enum a payload, or remove the impl".
>
> I accept aiml's one-sentence coinductive recursion note in the spec. Under B it covers only `@derive`/`impl` on recursive data enums.
>
> The main question can go to a vote now. If variation 2 is still split, it should go on the ballot as its own sub-question (error vs replace), not block the vote.
>
> STABLE: ready to vote

**PLT:**

> plt Phase B round 2: the counts confirm my ranking of B > A > C. On variation 2, I hold that a written impl is an error.
>
> **Migration counts.** Rule B touches 24 sites. All are in tests/, across 5 data enums in 4 files. src/ and lib/ have none, so B needs no bootstrap work: the tests add their derives, then the typecheck changes. The "changes twice" concern costs 24 test lines. Rule A's 1730 sites, 1504 of them in src/, settle A as a fallback only. I keep it second only because it is sound and C is not settled.
>
> **Variation 2: a written `impl Eq` on a fieldless enum should be an error.** sys, devops and aiml want the impl to replace tag equality.
>
> 1. **Hash/Eq law (web's point; I make it formal).** `@derive(Hash)` on a fieldless enum hashes the tag. Suppose a written `impl Eq` makes `Red == Crimson` with different tags. Then `a == b` holds while `hash(a) != hash(b)`, and every `Set` and `Map` that uses the type is unsound. The replacement rule would need a second rule ("then Hash must also be written") with a check of its own. Making the impl an error needs no such rule.
> 2. **Operator coherence.** A fieldless enum already has `c == 1` and `from_int`, which treat each value as its tag. Replacement lets `c == 1 && d == 1 && c != d` hold. sys says "tag operations against Int stay as they are". That is the problem: two `==` on the same values would then mean different things.
> 3. **It answers sys's coherence question.** sys: "there are two impls and no coherence rule." The error rule is that coherence rule: a fieldless enum has exactly one Eq, tag identity, and its single diagnostic is "a fieldless enum compares by tag; to change the equality, give a variant a payload or write a function." devops's "nothing new to diagnose" works the other way: replacement must also say what happens to Hash, tag ops and `Ord`-by-tag. Error says it once.
> 4. **It costs nothing (measured).** I checked every `impl Eq for` in src/, lib/ and tests/. All of them are on structs (`Written`, `Both`, `Keyed`, `N`, `W`, `Celsius`). None is on an enum. The error breaks no existing code, and no one has shown a use for it (YAGNI). Going from error to replacement later is a compatible change. The reverse is not.
>
> **Agreed and settled, for the spec text:**
> - A redundant `@derive(Eq)` on a fieldless enum is legal, gets no warning, and is checked at the declaration (all six agree).
> - `@derive(Eq)` or `impl Eq` on a recursive data enum resolves coinductively. This is the one sentence aiml asked for. Under B it applies only to declared impls.
> - Ord (separate ticket): fieldless enums are ordered by tag; data enums get Ord only through a derive or impl.
> - devops's B tooling list (the "only enums with no payloads are Eq without @derive" note, the E1400 help text, a declaration-targeted fix-it, LSP hover) is fine as non-normative implementation work.
>
> **To aiml (C, fix rounds).** Under B, a model that never derives needs one fix round per compared data enum, and the fix can be applied by a machine. Under C, that round moves to whoever later adds a non-Eq payload, often in another module, which is worse to debug. "Models derive by reflex" argues that derive is cheap. It does not argue for removing it.
>
> STABLE: ready to vote

**DevOps:**

> DevOps, Phase B round 2: B is still my choice. Ranking: B > C > A. I moved C above A because of the count, and I changed my answer on variation 2.
>
> **Migration count.** B gives 24 sites, all in tests/: 5 enums in 4 files, and 0 in src/ and lib/. A gives 1730 sites, 1504 of them in src/ (TyKind alone has 1244). For B that is five `@derive(Eq)` lines, which `blink fix` adds once per declaration. The 3-step bootstrap dance is not needed, because no src/ code uses the old rule. A's cost settles it against A, even with a tool to do the edits: 20 src enums would need a dance over 1504 sites, and the gain over B is nothing. I still rank C below B because of the remote-error problem.
>
> **Variation 2: I change to "error". plt, web and min are right.** Under "replaces", I made a tooling mistake: a payload-free enum would have two `==` meanings that the reader cannot tell apart at the call site. `c == 1` compares tags, `c == d` runs the user impl, and `@derive(Hash)` hashes the tag. That breaks the Hash/Eq law with no diagnostic anywhere. An LSP hover would have to say "Eq: user impl, but tag ops still use the tag", which is a warning about the language itself. An error at the impl is cleaner:
>
> ```
> error[E0xxx]: a payload-free enum cannot implement `Eq`
>   --> color.bl:4:1
>    |
>  4 | impl Eq for Color {
>    | ^^^^^^^^^^^^^^^^^ `Color` has no payloads, so it compares by tag
> help: remove this impl; `Color` is already `Eq`   [machine-applicable]
> ```
>
> If the author adds a payload later, the impl becomes legal at that same edit. That is the same "fieldless" boundary again. sys and aiml: under "replaces", you need a coherence rule against the tag operations, and nobody has written one. Under "error", you do not need one.
>
> **Spec text I ask for under B (tooling requirements, one line each):**
> - A redundant `@derive(Eq)` on a payload-free enum is legal and gives no warning.
> - `==` on a data enum with no derive or impl gives the "does not implement `Eq`" error with `note: only enums with no payloads are Eq without @derive(Eq)` and a machine-applicable fix on the declaration.
> - Rollout follows §3.6: a warning for one release, then an error. The 24 test sites are migrated in the same change.
> - The E1400 help for a payload-free key says it is Eq already and needs `@derive(Hash)`. Whether the help suggests `@derive(Hash)` alone or `@derive(Hash, Eq)` is wording, not a rule.
> - `@derive(Eq)` and `impl Eq` on a recursive type resolve coinductively (plt's sentence).
>
> aiml and min wanted the count before voting, and it is now posted. Variation 2 has a 4-2 lean toward "error" after my change. I am ready.
>
> STABLE: ready to vote

**AI/ML:**

> aiml, Phase B round 2: I move from C to B. My ranking is now B > C >> A. On variation 2 I move to "error".
>
> **Why I leave C:**
> 1. **web's Eq/Ord point decides it for generation.** All six of us agree on Ord: fieldless enums are ordered by tag, data enums need a derive. Under B, Eq follows the same rule, so a model learns one line: "fieldless enum = named constants (`==`, `<`, Int comparison, `to_int` all free); anything with fields, struct or data enum, needs `@derive`." Under C, Eq is structural while Ord is nominal. That is a second rule, and models will carry structural Eq over to `<` on data enums. That shape already reaches an internal compiler error today.
> 2. **web is right about training data, and I was wrong.** My C case rested on "Python/Swift-style output never derives, so it costs a fix round." But records in those languages need an opt-in: `@dataclass`, Kotlin `data class`, Java `record`, Swift `: Equatable` on enums with associated values. "Constants compare freely, data opts in" is the pattern already in training data. C matches only OCaml and Go.
> 3. **min's single-variant case.** `type P { P(x: Int, y: Int) }` and `type P { x: Int  y: Int }` get different Eq rules under C. A model cannot guess which form the author chose, and it should not need to.
> 4. **The measured cost is small.** B needs 24 sites in 5 test enums, and 0 in src/ and lib/. That is one `@derive(Eq)` per declaration through `blink fix`. My "code changes twice" objection is gone. A needs 1730 sites, which confirms it is out.
> 5. **plt's spec-size point.** C needs a second bound inference and its own fixed point for implicit Eq. B needs only the coinductive sentence for derive and impl, which every option already needs.
>
> **Variation 2, I change to "error":**
> - **For learnability:** "replace" adds a decision point and a rule for which impl wins. "Error" leaves one fact: a fieldless enum compares by tag.
> - **For soundness:** web and plt show that a custom `impl Eq` would disagree with `Color.Red == 0`, and with the tag-based `@derive(Hash)`, which breaks the Hash/Eq law.
> - **The diagnostic** should say "fieldless enums compare by tag; remove this impl, or add a payload if the values carry data." The removal must be machine-applicable.
>
> **Required with B. Each is small, and each matters for a model learning from errors:**
> - **Note on the data-enum `==` error (devops):** `note: only enums with no payloads are Eq without @derive(Eq)`, plus a machine-applicable fix on the declaration. This note teaches the rule at the failure point, which is where models learn.
> - **E1400 help on `Set[Color]` (web/devops):** "payload-free enums are Eq automatically; keys also need `@derive(Hash)`".
> - **Redundant `@derive(Eq)` on a fieldless enum:** legal and silent.
> - **Spec sentence:** `@derive(Eq)` or `impl Eq` on a recursive type resolves coinductively.
> - **The §3.6 example set** should show all three cases: `Color` (free), `Shape` (derived), and `Bag` (derive fails with E1401 at the declaration). One example per case is what a model copies.
>
> STABLE: ready to vote

**Minimalism:**

> min, Phase B round 2: B > C >> A. My ranking has not changed. The count settles my only open condition.
>
> **Migration.** B needs 24 sites across 5 enums in 4 test files, with zero in src/ and zero in lib/. That is 5 `@derive(Eq)` lines added by `blink fix`. The "code changes twice" concern was real in principle, but it costs almost nothing here. A needs 1730 sites, 1504 of them in src/ (TyKind alone has 1244). Those edits would add ceremony and make nothing safer, which confirms that A is out.
>
> **To aiml (C).** You say models over-derive by reflex, so a required derive does not make the choice deliberate. That is true, but it argues against derives in general, and the struct rule already accepts that cost. Under C a single-variant enum and a struct with the same fields get different Eq rules. Under B they get the same rule. With only 5 derives at stake, "zero migration" can no longer outweigh a rule that is written down twice (bound inference, fixed point, override).
>
> **Variation 2: an `impl Eq` on a fieldless enum is an error.** I am staying with plt and web.
> - sys and devops argue "replace, the same way a user impl replaces a derive". That analogy fails here. A data enum has only one `==`. A fieldless enum already has a second equality that the panel decided on: the tag comparison with `Int`. If the impl replaces the tag compare, `a == 1 && b == 1` can hold while `a != b`. That is plt's argument, and plt changed position because of it.
> - web's point decides it: `@derive(Hash)` hashes the tag. A custom Eq can then call `a == b` true while their hashes differ, which breaks the Hash/Eq law inside every `Set` and `Map`. Under "replace", the spec would need a further rule to stop that. Under "error" it needs nothing.
> - Nobody has shown a use case for custom equality on a set of named constants (YAGNI). If one ever appears, an error can be relaxed later without breaking anyone. A "replace" rule cannot be tightened later without breaking code.
> - The error text should say "fieldless enums compare by tag; add a payload or use a struct for custom equality". It should not mention `.to_int()`. That keeps devops's concern about weaker workarounds in hand.
>
> **Other variations.**
> - Variation 3: one sentence. A derive or impl on a recursive type resolves coinductively. Under B no fixed point for an implicit rule is needed.
> - Ord: fieldless enums are ordered by tag, data enums only through a derive or impl. Separate ticket, and five panelists already agree.
> - Tooling: devops's notes for B are fine as diagnostic wording. I want no new lint.
>
> STABLE: ready to vote

#### Phase C — Final vote

Ballot:

- **Q1. Final rule for enum Eq**
  - A: every enum (payload-free or not) is Eq only through `@derive(Eq)` or a written `impl Eq`.
  - B: a payload-free enum is Eq by tag identity with no derive. An enum with at least one payload is Eq only through `@derive(Eq)` or a written `impl Eq`, the same as a struct.
  - C: the interim §3.6 rule becomes final: with no derive and no impl, an enum is Eq iff every payload type is Eq; payload-free enums are Eq.

- **Q2. A written `impl Eq` on a payload-free enum**
  - ERROR: it is a compile error (the enum already compares by tag).
  - REPLACE: it replaces the implicit tag compare.

- **Q3. A redundant `@derive(Eq)` on a payload-free enum**
  - LEGAL: legal, no warning.
  - WARN: legal, with a warning.

- **Q4. Recursive types**
  - COIND: the spec states that `@derive(Eq)` and `impl Eq` on a recursive type resolve coinductively (the type is assumed Eq while its payloads are checked).
  - SILENT: the spec says nothing.

- **Q5. Migration for data enums that rely on the interim rule**
  - STAGED: one release where `==` on such an enum is a warning, with a machine-applicable fix that adds `@derive(Eq)` at the declaration; then an error.
  - IMMEDIATE: an error at once, with the same machine-applicable fix.

Tally: Q1 B 6-0. Q2 ERROR 6-0. Q3 LEGAL 6-0. Q4 COIND 6-0. Q5 IMMEDIATE 4-2 (DevOps, Web/Scripting STAGED), so Q5 went to Phase D.

Votes, verbatim:

**Systems:**

> Q1. Vote: B
> Reasoning: The emitted code is the same under all three options, so the choice is about where errors land and what the API promises. B makes Eq readable from the `type` line. It puts the error on the declaration that changed, not at distant `Option[E]` sites, and it fixes every plt soundness defect without a fixed-point rule for an implicit derive. Measured cost: 5 data enums in tests/, nothing in src/ or lib/. A would cost 1504 src/ sites for no soundness gain.
> Concern: the E1400 help on `Set[Color]` must say that payload-free enums are Eq automatically but keys still need `@derive(Hash)`. Otherwise B's one remaining asymmetry becomes the new friction report.
>
> Q2. Vote: ERROR
> Reasoning: The decided tag operations already fix a payload-free enum's equality as tag identity. An override could make `c == 1 && d == 1` hold while `c != d`, and it would break `Hash: Eq` against a derived tag hash. ERROR also guarantees that same-enum `==` on a payload-free enum is always one integer compare, with no override check in codegen.
> Concern: someone who wants a coarser equivalence on constants (for example "all error codes equal") gets an error. The message must point them to a named method, not to `.to_int()` comparisons.
>
> Q3. Vote: LEGAL
> Reasoning: It costs nothing at runtime and generates the same code, and it keeps `@derive(Hash, Eq)` the single spelling for keys on every user type. A warning would add a fix round for Rust-trained output and for every key enum.
> Concern: some readers may think the derive is required on payload-free enums and spread that cargo cult. Docs examples should show `type Color { Red  Green }` with no derive.
>
> Q4. Vote: COIND
> Reasoning: The compiler already resolves it this way (`Json` with `Arr(xs: List[Json])` compares correctly). Codegen emits one recursive eq function per type. The spec must state the rule so a later reimplementation does not reject valid recursive types or loop in the trait solver.
> Concern: the sentence must cover mutual recursion across modules (A holds `List[B]`, B holds `Option[A]`), not only direct self-reference, or the solver will diverge in exactly those cases.
>
> Q5. Vote: IMMEDIATE
> Reasoning: The measured blast radius is 24 sites from 5 enums, all in tests/, with no src/ or lib/ change. A staged release would keep the interim structural predicate (the path that already produced ICEs) alive in typecheck for one more release just to issue warnings. A clean cut with the same machine-applicable fix is cheaper and leaves one Eq predicate in the compiler.
> Concern: if users outside this tree have more data-enum `==` than our corpus shows, an immediate error breaks their builds without notice. The release notes must name the change and the `blink fix` command.

**Web/Scripting:**

> **Q1. Vote: B**
> Reasoning: B gives the rule a JS, Python or Kotlin developer already expects. Constants compare freely (`if tok == Kind.Eof`), and record-like data opts in, as with `@dataclass`, `data class` and `record`. It agrees with the decided tag operations, so there is no "`c == 1` compiles but `c == Color.Red` does not" trap, which A has. Errors appear on the declaration the author edited, not in a distant module, which C causes. The measured cost is 24 test sites across 5 enums, against 1730 under A.
> Concern: users who add the first payload to a widely compared enum get many `==` errors at once. The diagnostic must say "only enums with no payloads are Eq without @derive(Eq)", and its fix must edit the declaration once, not each site.
>
> **Q2. Vote: ERROR**
> Reasoning: a payload-free enum already has one built-in equality, the tag (`c == 1`). A replacing impl lets two `==` operators on the same values disagree, and it can break Hash/Eq agreement with `@derive(Hash)`. Nobody named a use case. Shipping ERROR now and allowing it later breaks no existing program, but the reverse would break programs.
> Concern: if REPLACE wins, the spec must say clearly that `Enum == Int` stays a tag compare even when a user impl exists, or users will hit inconsistent results with no diagnostic.
>
> **Q3. Vote: LEGAL**
> Reasoning: Rust-trained habits and copy-paste write `@derive(Eq, Debug)` everywhere, and `@derive(Hash, Eq)` should stay one spelling for keys across structs and enums. A warning on harmless, correct code is noise that teaches people to ignore warnings.
> Concern: readers may think the derive is required on payload-free enums. The docs should state once that it is optional there.
>
> **Q4. Vote: COIND**
> Reasoning: `type Json { Null  Arr(xs: List[Json]) }` is an everyday shape for web developers (JSON, ASTs, trees), and it must just work. The compiler already does this, so stating it costs one sentence and prevents a future implementation from rejecting it.
> Concern: keep the sentence short and plain. If it reads as type theory, a non-PLT reader will skip it and the "why" is lost.
>
> **Q5. Vote: STAGED**
> Reasoning: the measured count covers only this repo. User code outside it is unmeasured, and a warning release with a machine-applicable fix is the normal deprecation path (Python DeprecationWarning, TS deprecation notices). The cost is one release of delay for a tiny in-repo change.
> Concern: the staged release must name the exact version where the warning becomes an error, or the interim rule turns into a permanent second rule.

**PLT:**

> **Q1. Vote: B**
> Reasoning: The decided tag operations (`c == 1`, `to_int`, `from_int`) already fix tag identity as the only equality a payload-free enum can have. Making the type declare it again is ceremony, not soundness. For data enums, B uses the same nominal rule as structs, so `type P { P(x: Int, y: Int) }` and the struct form `type P { x: Int  y: Int }` agree. It also removes C's open questions: the spec does not have to choose a fixed point for an implicit rule or define bound inference a second time. Wrapping gives the same answer by construction, because `E: Eq` depends only on E's own declaration.
> Concern: if "payload-free" is ever extended (for example, a generic fieldless enum `type K[T] { A  B }`, or variants with zero-arity parentheses), the spec must state that the rule tests "no variant has a payload" syntactically on the declaration, or the boundary will drift.
>
> **Q2. Vote: ERROR**
> Reasoning: A replacement impl could make `a == b` true where the tags differ. Then `@derive(Hash)` (which hashes the tag) breaks the Hash/Eq law, and `c == 1 && d == 1 && c != d` becomes possible, so two `==` operators on the same values disagree. ERROR is the coherence rule: exactly one Eq per payload-free enum. I measured the cost: every `impl Eq for` in src/, lib/ and tests/ is on a struct, none on an enum. ERROR can be relaxed to REPLACE later without breaking anything, but the reverse breaks code.
> Concern: if REPLACE wins, the spec must also say that `Hash` (and the future tag `Ord`) must be written by hand to agree, or `Set` and `Map` of such enums give wrong answers silently.
>
> **Q3. Vote: LEGAL**
> Reasoning: The derive produces exactly the impl the rule already grants, so it changes no meaning. A warning would flag code that is correct. It also keeps `@derive(Hash, Eq)` as one spelling for keys on every user type, and it keeps the derive working as a check at the declaration.
> Concern: a model or reader may infer that the derive is required, and so expect to need it on payload-free enums. The diagnostic notes should say once that it is optional there.
>
> **Q4. Vote: COIND**
> Reasoning: Recursive data types such as `type Json { Null  Arr(xs: List[Json]) }` need a stated rule. Under a least-fixed-point reading they are never Eq; under coinduction they are. The compiler already resolves them coinductively (measured: `a == b` prints `true`). This is the standard reading for declared instances (Haskell `deriving`, Rust coinductive trait solving), and it is sound because the impl is declared, not inferred. A spec that says nothing leaves a correct program dependent on how the compiler happens to work.
> Concern: the sentence must also cover mutually recursive types in different modules, or one implementation may resolve a cross-module cycle differently from another.
>
> **Q5. Vote: IMMEDIATE** (this changes my Phase A position, because of the measured count)
> Reasoning: The measured cost is 24 sites, all in tests/, with no src/ or lib/ sites, so no bootstrap steps are needed. The §3.6 text was labelled "interim", so it was never a stable promise. STAGED would put a third, temporary rule in the spec (a warning-only state) and then require removing it, which is extra spec and compiler surface for 24 test lines. The machine-applicable fix gives users the same one-edit migration either way.
> Concern: users outside this repo who wrote data-enum `==` against the interim rule get a hard error in one release. The release notes must point to `blink fix` explicitly so the upgrade stays mechanical.

**DevOps:**

> **Q1. Vote: B**
> Reasoning: Whether an enum is Eq is decided by its own declaration. "No payloads" or "has a derive or impl" is visible on the `type` line, so the LSP answers hover without walking payload types, and every Eq error points at a line the author edited. A creates a diagnostic that invites a worse workaround (`m.to_int() == Mode.On.to_int()`) and costs 1504 src/ sites. C puts errors at call sites in modules that never changed.
> Concern: Two things can go wrong when the first payload is added. The `==` errors must carry the note "only enums with no payloads are Eq without @derive(Eq)". Their fix must edit the declaration once, not each call site. Without both, the transition feels arbitrary.
>
> **Q2. Vote: ERROR**
> Reasoning: Under REPLACE, a payload-free enum has two meanings of `==` that a reader cannot tell apart at the call site. Tag ops and `@derive(Hash)` use the tag, while `c == d` runs the user impl, which breaks the Hash/Eq law with no diagnostic. An error at the impl, with a machine-applicable fix that removes the impl, is a single local diagnostic.
> Concern: The error text must explain why ("compares by tag; add a payload to define custom equality"). Otherwise users read it as an arbitrary ban.
>
> **Q3. Vote: LEGAL**
> Reasoning: Rust-trained code and `@derive(Hash, Eq)` for keys both write it. A warning would cost a fix round and noise for no correctness gain. The derive still runs the declaration-site check, which is harmless.
> Concern: The formatter and linter must not later grow a "redundant derive" lint by default, which would reopen this through tooling.
>
> **Q4. Vote: COIND**
> Reasoning: It matches what the compiler does today (`Json` with `List[Json]`). It also gives the typecheck and the LSP one stated rule, so a recursive derive is never reported as a cycle error.
> Concern: An implementation that checks inductively by mistake would emit a confusing "Json does not implement Eq because Json does not implement Eq" chain. The diagnostic chain printer needs a cycle guard.
>
> **Q5. Vote: STAGED**
> Reasoning: §3.6 already defines this rollout for new errors in that subsection: a warning with a `blink fix` fix, then an error. Following it keeps one migration story for users. In-tree the cost is tiny (24 test sites, 0 in src/lib), and code outside the tree that relied on the interim rule gets one release to run `blink fix`.
> Concern: The warning release must not slip and leave a permanent warning. The follow-up that flips it to an error needs a ticket filed with the warning change.

**AI/ML:**

> **Q1. Vote: B.**
> Reasoning: B gives a model one line to learn. A fieldless enum is a set of named constants: `==`, `<`, Int comparison and `to_int` all come free. Anything with fields, struct or data enum, needs `@derive`. Eq and the agreed Ord direction share that one line. B also matches the pattern most common in training data (Swift associated values, Kotlin `data class`, Python `@dataclass`, Java `record`), and the measured migration is small (24 test sites, 0 in src/ or lib/). A makes `c == 1` legal and `c == Color.Red` an error, which nobody can predict. C splits Eq (structural) from Ord (nominal).
> Concern: models that add the first payload to a compared enum will hit the `==` error, so the note "only enums with no payloads are Eq without @derive(Eq)" and the declaration fix-it must ship with the rule, not after it.
>
> **Q2. Vote: ERROR.**
> Reasoning: "A fieldless enum compares by tag" stays one fact with no override rule to learn. A custom impl would disagree with `Color.Red == 0` and with the tag-based `@derive(Hash)`, which breaks the Hash/Eq law.
> Concern: the error must say why and offer a machine-applicable removal, or models will loop trying to write the impl another way.
>
> **Q3. Vote: LEGAL.**
> Reasoning: Rust-trained output writes `@derive(Eq, Debug)` on every enum by reflex. A warning costs a fix round for code that is correct, and it splits the one spelling for keys, `@derive(Hash, Eq)`.
> Concern: none of note. Readers may wrongly infer that the derive is needed, which is harmless.
>
> **Q4. Vote: COIND.**
> Reasoning: a recursive data enum such as `Json` or `Tree` is a common generated pattern. A spec silent on recursion leaves a model, and a second implementer, unable to predict the answer. One sentence matching current compiler behavior removes that doubt.
> Concern: the sentence must also cover generic recursive enums (`Tree[T]`) with the inferred `T: Eq` bound, or the same gap reopens there.
>
> **Q5. Vote: IMMEDIATE.**
> Reasoning: the rule was labeled interim, and the measured cost is 24 sites in 5 test enums with a machine-applicable fix. A staged release leaves a period where code with no derive compiles. That code ends up in the corpus and in training data that contradicts the spec. One rule from the day it lands is easier to learn than a warning phase.
> Concern: user code outside this repo that relies on the interim rule breaks without notice, so the release notes must name the change and the `blink fix` command.

**Minimalism:**

> **Q1. Vote: B**
> Reasoning: B adds no new category to the spec. "Fieldless enum" already exists through the decided tag operations, and "a data type needs a derive" already exists through the struct rule. C would make the spec state bound inference, a fixed point and an override rule a second time for an implicit derive. A adds 1730 ceremony edits for no gain in soundness. B's measured cost is 5 derives in tests, none in src/ or lib/.
> Concern: the `Set[Color]` gap (`==` needs no derive, but a key needs `@derive(Hash)`) stays. Unless the E1400 help text explains it, users will report it as a bug.
>
> **Q2. Vote: ERROR**
> Reasoning: a fieldless enum already has one decided equality, the tag comparison with Int. A custom impl would let `a == 1 && b == 1` hold while `a != b`, and it would break the Hash/Eq law against a derived tag hash. An error needs no extra spec rule, has no known use case to block, and can be relaxed later without breaking anyone. "Replace" cannot be tightened later.
> Concern: if REPLACE wins, the spec still needs a rule that keeps Hash consistent with a custom Eq on fieldless enums, and that rule tends to get left out.
>
> **Q3. Vote: LEGAL**
> Reasoning: a warning on a harmless annotation adds a diagnostic and costs fix rounds for Rust-trained code. `@derive(Hash, Eq)` stays one spelling for keys across structs and enums.
> Concern: none worth a rule. At worst some code carries redundant derives.
>
> **Q4. Vote: COIND**
> Reasoning: it is one sentence. It matches what the compiler does today (the `Json` measurement), and it closes a real gap in the spec. Saying nothing leaves the least-fixed-point reading open, and that reading rejects valid recursive types.
> Concern: the sentence must cover `impl Eq` and `@derive(Eq)` together, and must not grow into a general coinduction section.
>
> **Q5. Vote: IMMEDIATE**
> Reasoning: the rule was labelled interim and was never a stable promise. The measured blast radius is 24 sites in 4 test files, with zero in src/ and lib/. A staged release adds a warning code, a deprecation cycle and a later step to remove it. That is process that outlives a 5-line fix, and the machine-applicable `@derive(Eq)` fix already makes the error cheap to resolve.
> Concern: if STAGED wins, the warning-to-error flip needs a tracked ticket, or the warning stays forever and the "interim" rule becomes final through neglect.

#### Phase D — Round 2 (Q5 only)

Fact given to the panel:

> sections/03_types.md:2774 reads: "**Rollout.** Each new error in this subsection ships first as a warning with a machine-applicable fix that `blink fix` applies, and becomes an error in the next release." That sentence sits in the subsection "#### Mutable Parameters" (line 2675). It is the only "Rollout" rule in sections/. The "Container Equality" subsection (~line 2956) has no rollout sentence.

Tally: Q5 IMMEDIATE 6-0 in round 2, after 4-2 in round 1. DevOps and Web/Scripting changed from STAGED to IMMEDIATE.

Votes, verbatim:

**Systems:**

> Systems, Phase D on Q5.
>
> **Debate.** devops cites the rollout precedent, but the spec fact shows it is scoped to "#### Mutable Parameters". It is not a language-wide deprecation policy. That rollout covered errors on code that had been stable. Here the text said "interim", so nobody was promised anything (plt, min). Using a local subsection rule as a global rule would be a spec change of its own. If the panel wants a general deprecation policy, that is a separate type:spec ticket.
>
> web: "user code outside the repo is unmeasured." True, but STAGED does not reduce what that code has to do. The fix is the same one-line `@derive(Eq)` per enum either way, and `blink fix` applies it. STAGED only delays it. Meanwhile the compiler carries two Eq predicates for a release: the interim structural one, which is the path that already ICEd, plus the new one with a warning tier. aiml's point also stands: code without a derive written during that release ends up in the corpus and teaches the wrong rule.
>
> devops, web and min all name the same risk: a warning tier needs a flip ticket, or it becomes permanent. IMMEDIATE has no such state, so the risk does not exist.
>
> I keep my ask that the release notes name the change and `blink fix`. That covers web's concern at much lower cost.
>
> **Final vote**
> 1. Vote: IMMEDIATE
> 2. Reasoning: The measured cost is 5 enums, 24 test sites, and nothing in src/ or lib/. The interim rule was never a stable promise, and the only rollout rule in the spec is local to Mutable Parameters. STAGED keeps the interim predicate that already ICEd alive for a release, plus a temporary warning tier, and it leaves the user edit unchanged. One predicate from day one is cheaper and safer.
> 3. Concern: users outside this tree get a hard error with no warning release, so the release notes must state the change and the `blink fix` command.

**Web/Scripting:**

> Web Phase D (Q5): I switch to IMMEDIATE.
>
> Debate: my STAGED vote rested on unmeasured code outside the repo. Three points outweigh that. (1) The spec fact weakens devops's precedent. The §3.6 "Rollout" sentence belongs to Mutable Parameters, not Container Equality, so STAGED would add a new process here rather than follow an existing one. (2) aiml is right about DX: a warning phase means code with no derive compiles for a release and gets copied into examples and Stack Overflow answers that the next release breaks. One rule from day one is easier to learn. (3) sys and plt are right that the text said "interim" and was never a promise. Blink is pre-1.0 (0.54), and the fix is one machine-applicable line per declaration. Moving fast with an automatic fix is the normal pre-1.0 path in JS and Python tooling, and it makes the version-naming concern from my STAGED ballot moot.
>
> Final vote:
> 1. Vote: IMMEDIATE
> 2. Reasoning: the measured cost is 24 test sites across 5 enums, the rule was labelled interim, and the same machine-applicable `@derive(Eq)` fix makes the error a one-edit upgrade. A warning phase would put contradicting examples into circulation and keep the structural predicate alive in the compiler for no real gain.
> 3. Concern: users outside the repo get a hard error with no warning, so the release notes and the error itself must name the change ("enums with a payload now need @derive(Eq)") and the `blink fix` command.

**PLT:**

> plt Phase D (Q5): debate, then my final vote.
>
> **To devops:** the cited sentence (03_types.md:2774) is scoped to "Mutable Parameters": "each new error *in this subsection*". It is not a language-wide rollout policy. Applying it to Container Equality by analogy would make it a general rule without a vote. If the panel wants a general deprecation policy, that is a separate spec question for a separate ticket. Taking it on here, for 24 test lines, is the wrong place.
>
> **To web:** the risk from unmeasured external code is real, and I do not dismiss it. But STAGED does not reduce the work: each affected enum still needs one `@derive(Eq)`, and the IMMEDIATE error carries the same machine-applicable fix. The only thing STAGED changes is when a build fails, and in exchange it keeps the interim predicate in the typechecker for one more release (sys's point). That predicate already produced ICEs, and it is the source of the "which fixed point?" ambiguity that Q4 just closed. Python's DeprecationWarning covers behaviour that was once stable. The §3.6 enum text was explicitly labelled interim, so nothing stable is being deprecated.
>
> **Common ground:** all six concerns ask for the same thing, namely that the change and the `blink fix` command are named in the release notes. I support writing that into the decision as a requirement, whichever option wins.
>
> **Final vote:**
> 1. Vote: IMMEDIATE
> 2. Reasoning: The rule being removed was labelled interim in the spec, so no stable promise breaks. The measured cost is 24 test sites, with none in src/ or lib/. A warning release would keep a second Eq predicate alive in the compiler, the same one that produced ICEs and the recursion ambiguity. And the only rollout sentence in the spec is scoped to another subsection, so it sets no precedent here.
> 3. Concern: external users get a hard error with no warning release, so the release notes must name the change and `blink fix`, and the error's fix-it must target the declaration, one edit per enum.

**DevOps:**

> DevOps Phase D, Q5: I switch to IMMEDIATE.
>
> Debate: my STAGED vote rested on one fact, that §3.6 already sets a warning-then-error rollout for this subsection. The posted spec fact shows that is wrong. The Rollout sentence belongs to "Mutable Parameters", not to "Container Equality". So STAGED has no precedent here and would be new process. Without that argument, sys's point decides it for me: STAGED keeps the interim structural predicate in typecheck for one more release only to produce warnings. That is a second Eq code path, and that path already produced an ICE. aiml is also right on the tooling side: during a warning release, code with no derive compiles, gets copied into the corpus, and goes against the spec. web, your point about code outside this repo is real. But both options give that code the same machine-applicable fix. The only difference is one release of notice, and release notes give that notice at no cost.
>
> Final vote:
> 1. Vote: IMMEDIATE
> 2. Reasoning: The rule was labelled interim, the measured cost is 24 test sites with 0 in src/ and lib/, and the Rollout rule I cited does not cover this subsection. An immediate error with the same machine-applicable `@derive(Eq)` fix on the declaration leaves one Eq predicate in the compiler and one rule in the spec. Users outside the repo get the same one-edit migration through `blink fix`.
> 3. Concern: The error is the only notice users outside the repo get. It must carry the fix that `blink fix` applies plus the note "only enums with no payloads are Eq without @derive(Eq)". The release notes must name the change and the `blink fix` command.

**AI/ML:**

> aiml, Phase D (Q5)
>
> **Debate.**
> - **devops:** the spec fact weakens your precedent. The only "Rollout" sentence in sections/ sits under Mutable Parameters, and it covers new errors in that subsection only. Container Equality has none. Copying it here is a new choice, not keeping one migration story. If the panel wants staged rollouts as a general policy, that belongs in its own spec ticket, so every future change follows one written rule. It should not be decided case by case through this vote.
> - **web:** the unmeasured outside code is a fair point. But the fix is the same machine-applicable `@derive(Eq)` either way, so the only thing a warning release buys is one more release before the fix is applied. Against that, sys and plt name the costs: a third temporary rule in the spec and a second Eq predicate in typecheck, which is the code path that already produced ICEs.
> - **From the learning side:** during the warning release, code with no derive compiles and spreads into examples and the corpus. That trains the wrong rule against a spec that already says the opposite.
> - **Agreed with all:** whichever option wins, the release notes must name the change and the `blink fix` command. If STAGED wins, I support min's and web's conditions: name the version where the warning becomes an error, and file the follow-up ticket in the same change.
>
> **Final vote: IMMEDIATE.**
> Reasoning: the §3.6 rule was labeled interim. The measured cost is 24 test sites in 5 enums with a machine-applicable fix, and the spec's only rollout sentence does not cover this subsection. One rule from the day it lands is easier to learn and to implement than a warning phase, and no code with no derive compiles in the meantime to contradict the spec.
> Concern: user code outside this repo breaks in one release with no warning, so the release notes must state the change and the `blink fix` command clearly.

**Minimalism:**

> min, Phase D, Q5
>
> **Debate.**
> - devops: the §3.6 rollout sentence does not apply here. The spec fact says it sits under "Mutable Parameters" and covers "each new error in this subsection". It is not a general rule, and Container Equality has no rollout sentence. Following it here would be a choice, and that choice would turn a local rule into a precedent for every future tightening. Each future tightening would then carry a warning code and a flip ticket by default. If the panel wants a general deprecation policy, it should go to its own spec ticket. It should not slip in through a 24-site migration.
> - web: users outside the tree are unmeasured, and that is a fair point. But the rule they would be using was labelled "interim" in the spec text itself, and the language is pre-1.0. The cost of the error for such a user is one `blink fix` run per enum. Python's DeprecationWarning protects stable APIs, and an interim rule is not one.
> - devops and web each named the same risk in their concern: the flip slips and the warning stays. When both STAGED voters name the same failure, and IMMEDIATE removes it at no cost, IMMEDIATE is the better choice. sys's point adds to that: STAGED keeps the interim predicate, which already produced ICEs, alive in typecheck for one more release.
> - I agree with sys, plt and aiml that the release notes must name the change and `blink fix`. That is the honest cost of IMMEDIATE, and it is cheap.
>
> **Final vote**
> 1. Vote: IMMEDIATE
> 2. Reasoning: the interim rule was never a stable promise, and the measured cost is 5 derives in tests with a machine-applicable fix. The §3.6 rollout sentence covers only Mutable Parameters. Extending it here would add a warning state, a second predicate in typecheck and a flip ticket, all for one release. One rule from the day it lands is the smaller surface.
> 3. Concern: users outside the tree hit a hard error with no prior warning, so the release notes must state the change and the `blink fix` command.

#### AI-first review

Learnability, consistency, generability, debuggability and token efficiency: 5/5 pass. Debuggability depends on the diagnostics that the panel's concerns require (below).

### Final Spec

```blink
type Color { Red  Green  Blue }                 // fieldless: Eq with no derive

@derive(Eq)
type Shape { Circle(r: Int)  Sq(s: Int) }       // has a payload: Eq only by derive or impl

type Widget { id: Int }

@derive(Eq)
type Bag { Items(xs: List[Widget])  Empty }     // error (E1401): `Widget` does not implement `Eq`
```

- **Q1 (B, 6-0):** a fieldless enum is `Eq` by variant with no derive. An enum with at least one payload is `Eq` only through `@derive(Eq)` or a written `impl Eq`, the same as a struct.
- **Q2 (ERROR, 6-0):** a written `impl Eq` on a fieldless enum is a compile error.
- **Q3 (LEGAL, 6-0):** a redundant `@derive(Eq)` on a fieldless enum is legal, with no warning, and the compiler checks it.
- **Q4 (COIND, 6-0):** `@derive(Eq)` and `impl Eq` on a recursive type resolve coinductively, also for types that contain each other across modules and for generic types such as `Tree[T]`.
- **Q5 (IMMEDIATE, 6-0 R2 after 4-2 R1):** `==` on a data enum with no derive and no impl is an error at once, with a machine-applicable fix that adds `@derive(Eq)` at the declaration. The release notes name the change and `blink fix`.
- **Out of scope:** `Ord` for enums goes to its own ticket.

**Panel concerns that the implementation must address:**

- The data-enum `==` error notes that only fieldless enums are `Eq` with no `@derive(Eq)`, and has one fix, which edits the declaration.
- The error for `impl Eq` on a fieldless enum says that the enum compares by variant, has a machine-applicable fix that removes the impl, and does not suggest `.to_int()`.
- The E1400 help for a fieldless enum key (`Set[Color]`) says that the enum is `Eq` already and needs only `@derive(Hash)`.
- "Fieldless" is decided from the declaration as written.
- The chain printer ("is `Eq` only if ...") has a cycle guard.
- No default lint for a redundant derive.
- The docs show fieldless enums with no derive.
- The 5 test enums that rely on the interim rule get `@derive(Eq)` in the same change.

Spec: §3.6 *Container Equality* (**Enums**), §3.6 *Hash Contract and Seeding* (non-hashable keys).
