[< All Decisions](../DECISIONS.md)

# `Self` as a Value Path or Pattern Head — Design Rationale

**Gap:** §3.6 said `Self` in an impl body is a type-position alias, "not a constructor", and DECISIONS.md recorded that 4-1. It did not say what `Self.make(0)`, `Self.Red` and the patterns `Self.Rgb(n)` and `Self { x, y }` do. It did not say what refuses these forms in a trait default body, where `Self` is abstract.

## Summary

| Q | Question | Result | Vote |
|---|---|---|---|
| Q1 | What a `Self`-headed value path or pattern does in an impl body | `Alias`: `Self` is the target type in every position. Each form compiles as the type name does, and a form the type name refuses gets the type name's code | 6-0 after Phase D (4-2 for `TypeParam` in Phase C) |
| Q2 | What refuses a `Self`-headed build form or pattern in a trait default body | `NewCode-all`: one new code, E0570 `SelfShapeInDefaultBody`, for every build form and every `Self`-headed pattern | 4-2 (PLT and Minimalism dissent for `TCodes`) |

This **reverses** the row `Self` as constructor (4-1, "Type-position alias only, not a constructor") in DECISIONS.md.

Shared by all six seats (not on the ballot):

- `Self.f()` in a trait default body is legal when `f` is in the guarantee set, and E0305 when it is not.
- Outside a trait or impl, E0569 is unchanged.

## Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in independent-proposal, debate, vote rounds. Phase C put Q1 at 4-2 for `TypeParam`, so one focused Phase D round ran on Q1 and then a re-vote on Q1 and Q2. Each panelist's text below is a verbatim excerpt of the panelist's own reply.

### Phase A — Independent proposals


- **Systems:**

> ## G2: value paths and patterns headed by `Self`
>
> ### Proposal G2-A (my pick): in an impl body, `Self` is the type, in every position
>
> Inside an impl body, `Self` is a plain alias for the impl's target type, in type position, value paths and patterns. So all of these compile and mean exactly what the written type means:
>
> ```blink
> type Color { Red, Rgb(Int) }
> type Point { x: Int, y: Int }
>
> trait Mk {
>     fn mk(n: Int) -> Self
>     fn zero() -> Self
> }
>
> impl Mk for Color {
>     fn mk(n: Int) -> Self {
>         if n == 0 { Self.Red } else { Self.Rgb(n) }      // OK: same as Color.Red / Color.Rgb(n)
>     }
>     fn zero() -> Self { Self.mk(0) }                       // OK: static call, same as Color.mk(0)
> }
>
> impl Mk for Point {
>     fn mk(n: Int) -> Self { Self { x: n, y: n } }         // OK: same as Point { x: n, y: n }
>     fn zero() -> Self {
>         match Self.mk(0) {
>             Self { x, y } => Self { x: y, y: x }          // OK: pattern
>         }
>     }
> }
> ```
>
> In a trait declaration (default bodies included), `Self` is a type variable bounded by the guarantee set:
>
> - `Self.f(args)` where `f` is a static method in the guarantee set: OK. Same rule as `T.zero()` (§3.6 *Polymorphic Trait Implementations*). Any other `Self.f(..)`: `UnlicensedSelfOperation`, at the trait.
> - `Self { .. }`, `Self(..)`, `Self.V`, `Self.V(..)` as values, and `Self { .. }`, `Self.V`, `Self.V(..)` as patterns: `SelfNotConstructor`, one error at the `Self` token, with a new catalog code next to E0569 (the catalog picks the number). The help says that `Self` here is any implementing type, so it has no fields or variants, and names the guarantee-set route (a static method such as `fn new() -> Self`).
>
> ```blink
> trait Shape {
>     fn new() -> Self
>     fn twice() -> Self { Self.new() }                     // OK: `new` is in the guarantee set
>     fn origin() -> Self { Self { x: 0 } }                 // SelfNotConstructor (new code)
>     fn is_red(self) -> Bool {
>         match self { Self.Red => true, _ => false }       // SelfNotConstructor (new code)
>     }
> }
> ```
>
> Outside a trait or impl body, every form stays E0569, as the catalog row says.
>
> Systems tradeoffs:
>
> - Cost: none. `Self` resolves to one concrete type (or, in a generic impl, `Box[T]`) at the body `{`. After that the checker and codegen see `Color.Rgb(n)`; no new IR node, no new lowering. Mono already instantiates a trait default body per impl, so `Self.new()` there lowers to a direct call, as `T.zero()` does.
> - One rule for the code: "after `{`, `Self` is the target type" is simpler for the compiler than a list of value positions where the alias is switched off. The measured crashes (I0023, NodeCarriesNoType) come from half-resolving `Self` in value paths; full resolution removes the half state.
> - This drops the old "not a constructor" text for impl bodies. That text has no code, no emit site and no rationale on cost; in a concrete impl `Self { .. }` builds the same bytes as `Point { .. }`.
>
> Cross-language: Rust allows `Self { .. }`, `Self::V(..)`, `Self::new()` and `Self` patterns in impls, and refuses them on a bare type parameter. Zig's `@This()` is a full type alias. Swift allows `Self(...)` only through a required init, which is the guarantee-set rule.
>
> ### Proposal G2-B (fallback): keep "not a constructor", widen it to every value form, give it a code
>
> Inside an impl body: `Self.f(..)` static calls are OK (same as `T.new()`); `Self { .. }`, `Self(..)`, `Self.V`, `Self.V(..)` as values and as patterns are `SelfNotConstructor` with the new code and a help that writes the concrete name (`Color.Rgb(7)`). Trait default bodies: same as G2-A.
>
> Tradeoff: also zero cost and it fixes the crashes, but the split "`Self.mk(0)` OK, `Self.Red` refused" is two kinds of value path through one alias. That split needs its own resolution path in the checker. I rank it second.
>
> ### Not proposed
>
> "Do nothing". The current text gives no code, the compiler crashes on two forms, and patterns are unstated. The spec must say something.
>
> ---

- **Web/Scripting:**

> ## G2: Self in value paths and patterns
>
> Fact: DECISIONS.md:166 already ruled 4-1 "`Self` is a type-position alias only, not a constructor" (web was the 1). I offer both shapes; my pick is A, B is the minimum fix if the panel keeps the old vote.
>
> ### Proposal G2-A (my pick): in an impl body, `Self` is the type name in every place
>
> Inside an impl body, `Self` means the target type, in value position and in patterns, the same as writing the name. In a trait default body, `Self` is a type parameter: a static call works when the guarantee set has the method; a shape (struct literal, variant, struct or variant pattern) is an error.
>
> ```blink
> type Color { Red, Rgb(Int) }
> type Point { x: Int, y: Int }
>
> trait Mk {
>     fn make(n: Int) -> Self
>     fn origin() -> Self { Self.make(0) }        // OK: `make` is in the guarantee set, like T.zero()
>     fn bad() -> Self { Self { x: 0, y: 0 } }    // ERROR SelfNotConstructor (new code): Self is a type parameter here, it has no fields
> }
>
> impl Mk for Color {
>     fn make(n: Int) -> Self {
>         if n == 0 { Self.Red } else { Self.Rgb(n) }      // OK: same as Color.Red, Color.Rgb(n)
>     }
> }
>
> impl Mk for Point {
>     fn make(n: Int) -> Self { Self { x: n, y: n } }   // OK: same as Point { x: n, y: n }
> }
>
> impl Point {
>     fn sum(self) -> Int {
>         match self { Self { x, y } => x + y }       // OK: struct pattern
>     }
>     fn twice() -> Point { Self.make(2) }            // OK: static call, same as Point.make(2)
> }
>
> fn main() {
>     print(Point.twice().sum())    // prints 4
> }
> ```
>
> - Q1 yes. Q2 yes. Q3 yes.
> - Q4: in a trait default body, `Self.m(..)` is legal when `m` is in the guarantee set (the rule at :6451, and the same as `T.new()`); otherwise `UnlicensedSelfOperation`. `Self { .. }`, `Self(..)`, `Self.V`, `Self.V(..)` and a `Self { x }` or `Self.V(..)` pattern are `SelfNotConstructor`: there is no known shape.
> - Q5: `SelfNotConstructor` gets its own code in the E05xx block (not E0569, which means "outside a trait/impl"). Help: "`Self` is a type parameter in a trait default body; add a trait method that builds the value, and call `Self.method(..)`".
>
> Tradeoffs (DX):
> - An alias that works in `-> Self` but not in `Self { }` is a surprise. "Why can I write it here but not there?" is a classic Stack Overflow question. Rust allows all of these, and Rust is where most models learned impl blocks; AI output will write `Self { .. }` and `Self.new()` in Blink. Today the compiler crashes on two of them (exit 101), so users already hit this.
> - Rename the type, and every `Self` in the impl still works. Fewer edits, fewer diff lines.
> - Python has `cls(...)` in a classmethod; Kotlin and TS use the class name. No one gets confused by `Self { }` inside the type's own impl.
> - Cost: two spellings for one thing inside an impl. `blink fmt` does not need to pick one.
>
> ### Proposal G2-B (if the panel keeps the 4-1 vote): one rule, one code, no gaps
>
> `Self` never heads a shape in any context: `Self { .. }`, `Self(..)`, `Self.V`, `Self.V(..)` in value position, and `Self { x }`, `Self.V`, `Self.V(..)` in a pattern. Each is `SelfNotConstructor` with its own new E05xx code, one error at the `Self` token, and a help that writes the concrete name (`Color.Rgb(7)`, `Point { x: 0, y: 0 }`). In a trait default body the help says to add a trait method instead.
>
> A static call is not a constructor: `Self.new()` is OK in an impl, and in a trait default body under the guarantee-set rule. Banning it would make `Self` weaker than a type parameter `T`, which can do `T.zero()`.
>
> ```blink
> impl Mk for Color {
>     fn make(n: Int) -> Self {
>         if n == 0 { Self.Red } else { Color.Rgb(n) }   // ERROR SelfNotConstructor at `Self`; help: write `Color.Red`
>     }
> }
> ```
>
> The pattern `Self.Rgb(n)` that runs today becomes an error. Pre-1.0, so fine. The point of B: today the same idea gives a crash, a run, and a wrong code. Any single rule beats that.
>
> Q0: yes, the spec must say more under either proposal. Today it names `Self { }` and `Self(args)` only, not `Self.V`, patterns, or static calls, and the error has no code.

- **PLT:**

> ## G2: `Self` as the head of a value path or pattern
>
> ### G2-A (my pick): in an impl body, `Self` is the alias it claims to be
>
> The spec already calls `Self` a type alias, and an alias "creates no type"; the compiler replaces it with its right-hand side (03:~2372). A user alias of an enum heads a qualified pattern (03:5036) and a type path (03:2658). So in an impl body, `Self` may head every value path and pattern that the target type's name may head, with the same meaning and the same codes. Remove the `SelfNotConstructor` rule for impl bodies.
>
> In a trait default body, `Self` is a type parameter (03:6451). It follows the type-parameter rules. An associated function of the trait (or of a supertrait) through `Self` is legal, as `T.zero()` is (03:7860, 03:3696). The guarantee-set rule extends to it: an associated function outside the set is E0305 `UnlicensedSelfOperation`.
>
> | Form | impl for an enum | impl for a struct | generic `impl[T] Tr for Box[T]` | trait default body |
> |---|---|---|---|---|
> | `Self.V(args)`, `Self.V` | OK, as `Color.V` | E0547 (struct has no variants) | OK, type is exactly `Self` (`Box[T]`) | E0570 |
> | `Self { x: 1 }` | as `Color { .. }` | OK, as `Point { x: 1 }` | OK, type is exactly `Self` | E0570 |
> | `Self(args)` | E0504, as `Color(..)` | E0504, as `Point(..)` | E0504 | E0570 |
> | `Self.f()`, `f` type-scoped or associated | OK, as `Color.f()` | OK | OK | OK if `f` is an associated fn in the guarantee set, else E0305 |
> | pattern `Self.V(n)`, `Self.V` | OK | E0308 | OK | E0308 at the trait (type parameter, 03:4869) |
> | pattern `Self { x }` | as `Color { x }` | OK | OK | E0308 at the trait |
>
> E0570 `SelfNotConstructor` is the new code (checked free in ERROR_CATALOG.md). It fires once at the `Self` token when a default body tries to build a value of the abstract `Self`. Its help points to an associated function the trait can declare (`fn make() -> Self`) and call as `Self.make()`. E0569 stays as it is, for `Self` outside a trait or impl and in an impl header.
>
> ```blink
> type Color { Red, Rgb(Int) }
>
> trait Mk {
>     fn make(n: Int) -> Self
>     fn twice(self, n: Int) -> Self { Self.make(n + n) }   // OK: `make` is in the guarantee set
>     fn red(self) -> Self { Self.Red }                     // E0570: `Self` is abstract here
> }
>
> impl Mk for Color {
>     fn make(n: Int) -> Self {
>         if n == 0 { Self.Red } else { Self.Rgb(n) }       // OK: same as Color.Red, Color.Rgb(n)
>     }
>     fn twice(self, n: Int) -> Self {
>         match self {
>             Self.Rgb(k) => Self.make(k + n)               // OK: pattern and static call
>             Self.Red => Self.Red
>         }
>     }
> }
> ```
>
> `Color.Rgb(2).twice(3)` returns `Color.Rgb(5)`, and `Color.Red.twice(3)` returns `Color.Red`.
>
> PLT tradeoffs:
> - **Substitution is the whole rule.** Inside an impl, any term with `Self` means the same as the term with the target type written in. One rule, no list of forms to keep up to date. Today's state (the pattern `Self.V(n)` runs, the construction `Self.V(n)` fails) is an asymmetry with no type-theoretic basis: a pattern and its constructor are duals.
> - **Generic impls.** `Self` fixes the type arguments: in `impl[T] Tr for Box[T]`, `Self.Full(x)` has type `Box[T]`, never a fresh `Box[?]`. That is stronger than `Box.Full(x)`, and it is sound because `Self` is one fixed instance in the body. `Self.f()` names `Box.f` with inference as for `Box.f()`. It is not E0314 (`Map[Str, Int].new()`), because no list is written.
> - **Default bodies stay parametric.** A type parameter has no fields and no variants. Building one from parts would assume a shape the trait does not guarantee, which is the same flaw E0305 blocks for operators. An associated function is the licensed way, the same as `T.zero()`.
> - **Why a code for the default body.** The present codes do not fit. E0547 speaks of a missing variant and E0525 of a missing field. A brace literal `Self {}` with no labels would get neither, and would build a value of an abstract type. Side finding: `T {}` for a plain type parameter `T` has the same hole in the spec. I flag it; it is outside this group.
>
> Cross-language: Rust allows `Self::V(..)`, `Self { .. }` and `Self::new()` in an impl, and in a trait default body only calls through `Self::f()`. Haskell and OCaml have no `Self`, but a class method's default body can build a value only through the class's own methods (`mempty`), which is the guarantee-set rule.
>
> ### G2-B (weaker alternative): keep "Self is not a constructor", give it a code
>
> In impls and default bodies, `Self.V(..)`, `Self.V`, `Self { .. }` and `Self(..)` as expressions are E0570 `SelfNotConstructor`. Patterns and `Self.f()` follow G2-A.
>
> - Pro: one spelling of each construction (the type name).
> - Con: the pattern/constructor asymmetry stays, `Self` stops being a plain alias, and every generic impl must spell `Box[T]` in full. I rank it second.

- **DevOps:**

> ## G2: `Self` value paths and patterns inside a trait or impl
>
> Q0: yes, the spec must say it. Today two of the forms crash `blink check` (I0023, `NodeCarriesNoType`, exit 101). A form the spec bans (`Self { x }`) gets a code (E0308) that names the wrong fault.
>
> ### Proposal G2-A (my pick): `Self` in a body is the type, in every position; in a default body it is a type parameter, in every position
>
> **Impl body.** `Self` is an alias for the impl's target type, in a type, a value path and a pattern. Anything you can write with the type name, you can write with `Self`, and it means the same thing. Anything the type name refuses, `Self` refuses with the same code. Drop `SelfNotConstructor` and its text.
>
> ```blink
> type Color { Red, Rgb(Int) }
> type Point { x: Int, y: Int }
>
> trait Mk {
>     fn make(n: Int) -> Self
>     fn tag(self) -> Int
> }
>
> impl Mk for Color {
>     fn make(n: Int) -> Self {
>         if n == 0 { Self.Red } else { Self.Rgb(n) }      // OK: same as Color.Red, Color.Rgb(n)
>     }
>     fn tag(self) -> Int {
>         match self {
>             Self.Red => 0                                  // OK
>             Self.Rgb(n) => n                               // OK
>         }
>     }
> }
>
> impl Mk for Point {
>     fn make(n: Int) -> Self { Self { x: n, y: Self.zero().y } }   // OK: literal and static call
>     fn tag(self) -> Int {
>         match self {
>             Self { x, .. } => x                            // OK: same as Point { x, .. }
>         }
>     }
> }
>
> fn Point.zero() -> Point { Point { x: 0, y: 0 } }
>
> fn main() {
>     println("{Color.make(7).tag()} {Point.make(4).tag()}")
> }
> ```
>
> Prints `7 4`. In `impl Mk for Color`, `Self.Blue` is E0547 NoSuchVariant, as `Color.Blue` is; `Self { x: 1 }` is the code `Color { x: 1 }` gets. `impl[T] Mk for Box[T]` makes `Self` mean `Box[T]`, so `Self { v: x }` works there too.
>
> **Trait default body.** `Self` is the implicit type parameter of §3.6 *Operations on `Self` in a Default Body*. Each form does what it does on a type parameter `T` with the trait's guarantee set as bounds, and reports at the trait definition:
>
> | Form in a default body | Result |
> |---|---|
> | `Self.f(..)`, `f` a static fn of a trait in the guarantee set | OK, like `T.zero()` |
> | `Self.f(..)`, any other `f` | E0305 UnlicensedSelfOperation |
> | `Self.V`, `Self.V(..)` (expression or pattern) | E0547 NoSuchVariant: "`Self` is a type parameter; it has no variants" |
> | `Self { x: .. }` literal, `Self { x }` pattern | E0525 NoSuchField: a type parameter declares no fields (03_types.md:7852) |
>
> ```blink
> trait Zero {
>     fn zero() -> Self
>     fn twice_zero() -> List[Self] { [Self.zero(), Self.zero()] }   // OK: zero is in the guarantee set
>     fn bad() -> Self { Self.Red }                                   // E0547: `Self` is a type parameter; it has no variants
> }
> ```
>
> Tradeoffs from my seat:
> - **One rule the language server can implement once.** Completion after `Self.` lists what completion after the type name lists (variants and static fns in an impl; guaranteed static fns in a default body). Go-to-definition on `Self.Rgb` jumps to `Rgb`. Rename of `Color` does not touch `Self`, which is why people write `Self`. rust-analyzer does all of this for Rust's `Self`.
> - **No new code.** Every refused form reuses a code that already has a help and a nearest-name suggestion. `SelfNotConstructor` needs a code, a catalog row and a fix-it only to tell users to type a longer name for the same value.
> - **Splitting `Self.V` (path) from `Self { }` (literal), as G2-B does, gives a rule users must guess.** If `Self.Rgb(7)` builds a value, `Self { x: 0 }` failing reads as a bug.
> - Also fixes the measured `Self { x }` pattern: it stops being E0308 (a code about variant patterns) and becomes plain OK in an impl, E0525 in a default body.
>
> Cross-language: Rust allows `Self { .. }`, `Self::V(..)`, `Self::new()` in impls and patterns. Swift allows `Self(...)` and `Self.staticMember`. Kotlin and Java have no `Self`, so they are no guide.
>
> ### Proposal G2-B (fallback): allow paths, keep the literal ban with a code
>
> `Self.V`, `Self.V(..)`, `Self.f()` and `Self.V` patterns are OK in an impl body. `Self { .. }` (literal and pattern) and `Self(..)` stay refused, with a new code `SelfNotConstructor` (next free code in the E05xx name-resolution range) and a machine-applicable fix that writes the type name. The default-body table is the same as G2-A. If the panel keeps the ban, this is the version with a code and a fix; an E-less error is not acceptable either way.
>
> ---

- **AI/ML:**

> ## G2: `Self` in value paths and patterns inside a trait or impl
>
> Facts I checked: patterns already find a variant from the scrutinee type, so `Rgb(n)` works bare (03_types.md ~4594). Expressions must write `Enum.Variant` (E0554). A type parameter takes a static call: `T.zero()` (~7860). In a default body `Self` is an implicit type parameter bounded by the guarantee set (~6451). `SelfNotConstructor` has text but no code.
>
> ### G2-P1 (my pick): `Self` in a value path acts as a type parameter does, in both a trait and an impl
>
> One rule for both places: **`Self` may head a static call. `Self` may not build a value or head a pattern.**
>
> | Form | Impl body | Trait default body |
> |---|---|---|
> | `Self.new()`, `Self.zero()` (static call) | OK, calls the impl type's static fn | OK when the fn is in the guarantee set, else `UnlicensedSelfOperation` |
> | `Self { x: 1 }`, `Self(1)` | SelfNotConstructor | SelfNotConstructor |
> | `Self.Red`, `Self.Rgb(7)` | SelfNotConstructor | SelfNotConstructor |
> | pattern `Self.Rgb(n)`, `Self.Red`, `Self { x }` | SelfNotConstructor | SelfNotConstructor |
> | any of the above outside a trait/impl | E0569, no second error (unchanged) | E0569 (unchanged) |
>
> `SelfNotConstructor` gets a new error code. One code for every form, one error at the `Self` token, no second error. In an impl body the help is machine-applicable and writes the concrete name (`Color.Rgb(7)`, `Point { x: 0 }`; for a variant pattern it drops `Self.`, so `Rgb(n)`). In a trait default body there is no concrete name, so the help says to make the method required, or to call a static fn of the trait (`Self.zero()`).
>
> ```blink
> trait Mk {
>     fn make() -> Self
>     fn zero() -> Self
>     fn twice() -> (Self, Self) { (Self.zero(), Self.zero()) }   // OK: zero is in Mk's guarantee set
> }
>
> type Color {
>     Red
>     Rgb(Int)
> }
>
> impl Mk for Color {
>     fn make() -> Self { Self.Rgb(7) }      // error[SelfNotConstructor], help: `Color.Rgb(7)`
>     fn zero() -> Self { Color.Red }        // OK
> }
>
> impl Color {
>     fn level(self) -> Int {
>         match self {
>             Self.Rgb(n) => n               // error[SelfNotConstructor], help: `Rgb(n)`
>             Red => 0                       // OK: a pattern finds the variant from `self`
>         }
>     }
>     fn fresh() -> Color { Self.make() }    // OK: static call
> }
> ```
>
> Why, from my seat:
>
> - **One rule, two places.** A model learns "Self is like `T`": it can call static fns on it, and it cannot build or match with it. The same sentence holds in a trait and in an impl, so the model does not need to know which one it is in. P2 below needs two rules.
> - **Static calls are needed.** In a trait default body there is no concrete name, and `T.zero()` is already the spec's form for a type parameter. Refusing `Self.zero()` would leave no way to write `twice` above.
> - **One spelling per value.** Patterns already take the bare variant, and expressions already take `Enum.Variant`. `Self.V` would be a second spelling of each, which is a choice point for a model and a second form to grep for. The spec already refuses `Self { }` and `Self(..)`. `Self.V` is the same thing, and the table makes that plain.
> - **The cost of the wrong guess is low.** Models with Rust priors will write `Self { .. }` and `Self::V`. Each wrong guess is a compile error with a machine-applicable help that writes the concrete name. One step to repair.
> - **Today's state is the worst case.** `Self.Rgb(7)` gives I0023 and exit 101, and `Self.Red` gives an ICE. A model reads an ICE as "my code is fine, the tool broke" and does not repair it. Any coded error is better than this.
>
> Cross-language: Rust allows `Self { }`, `Self(..)`, `Self::V` and `Self::new()` in an impl. Swift allows `Self(...)` and `Self.staticFn()`. Kotlin and Java have no `Self`. So the Rust and Swift priors push toward allowing more; the help text is the counterweight.
>
> ### G2-P2: in an impl body `Self` is a full alias; in a trait it acts as a type parameter
>
> In an impl body every value path and pattern that takes the concrete name also takes `Self` (`Self.Rgb(7)`, `Self { x: 1 }`, `Self.new()`). In a trait default body only static calls work, as in P1. The `SelfNotConstructor` text is removed for impls.
>
> Tradeoffs: closest to Rust, so the fewest first-try errors. But it gives two spellings for every construction and pattern in an impl, and the rule differs between a trait body and an impl body. Code moved from an impl into a trait default breaks. It also reverses the current spec text ("not a constructor"), which I see no new reason to do.
>
> ---

- **Minimalism:**

> ## G2: value paths through `Self`
>
> The spec must say something (Q0: yes): two forms crash the compiler today and `SelfNotConstructor` has no code. But the fix is to remove a rule, not to add codes.
>
> ### Proposal G2-A (my pick): `Self` is what the spec already says it is, an alias in an impl and a type parameter in a trait
>
> - In an impl body, `Self` is an alias of the target type. Every path an alias may head (§3.4 *Dotted heads*, step 2; a qualified pattern through an alias is legal, :5036), `Self` may head, with the same meaning as the target's name. Delete the `SelfNotConstructor` paragraph and its sample. No new code.
> - In a trait default body, `Self` is a type parameter bounded by the guarantee set (*Operations on `Self` in a Default Body*). Every path gets what the same path on a type parameter `T` gets today. No new code.
>
> ```blink
> type Color { Red, Rgb(Int) }
> type Point { x: Int, y: Int }
>
> trait Mk {
>     fn mk() -> Self
>     fn twice() -> List[Self] { [Self.mk(), Self.mk()] }  // OK: mk is in the guarantee set
>     fn bad() -> Self { Self.Red }                         // E0547 NoSuchVariant, as `T.Red` on a type parameter
>     fn bad2(self) -> Int {
>         match self {
>             Self.Rgb(n) => n                              // E0300, as a qualified pattern on a type parameter
>             _ => 0
>         }
>     }
> }
>
> impl Mk for Color {
>     fn mk() -> Self { Self.Rgb(7) }                       // OK: same as Color.Rgb(7)
> }
>
> trait Zero { fn zero() -> Self }
>
> impl Zero for Color {
>     fn zero() -> Self {
>         let c = Self.Red                                  // OK: same as Color.Red
>         match c {
>             Self.Rgb(n) => Self.Rgb(n + 1)                // OK: pattern and construction
>             Self.Red => Self.mk()                         // OK: static call, same as Color.mk()
>         }
>     }
> }
>
> impl Zero for Point {
>     fn zero() -> Self {
>         let p = Self { x: 0, y: 0 }                       // OK: same as Point { x: 0, y: 0 }
>         match p {
>             Self { x, y } => Self { x: y, y: x }          // OK: struct pattern
>         }
>     }
> }
>
> fn main() {
>     let c = Color.zero()
>     let p = Point.zero()
>     print(p.x)                                            // prints 0
> }
> ```
>
> Answers:
> - Q1, Q2, Q3: yes, all of them, in an impl body.
> - Q4: in a trait default body each form is what it is on a type parameter: a static call is legal when its trait is in the guarantee set (else `UnlicensedSelfOperation`, the existing rule); a variant (`Self.V`, `Self.V(..)`) is E0547; a qualified or struct pattern is E0300 (catalog row E0300, "on a scrutinee of a type parameter"); a struct literal gets whatever `T { .. }` gets today.
> - Q5: no new code. Each refused form takes the code that the same form on the target name or on a type parameter takes. `SelfNotConstructor` goes away. `Self(args)` in an impl is what `Point(args)` is (a newtype is built with braces, :2362), so it needs no `Self` rule either.
>
> Tradeoffs:
> - Removes a paragraph and a code-less error. Adds one sentence ("`Self` is an alias of the target in an impl body"), which §3.6 already nearly says ("type alias").
> - One mental model: replace `Self` with the type name. A model or a person never has to learn which alias uses are banned.
> - The old reason for the ban ("use the concrete type name") is style, and `blink fmt` or a lint can carry style. It does not need an error.
> - The crashes (I0023, NodeCarriesNoType) become plain alias lookups, which the compiler already does for aliases. Smallest compiler change too.
> - Cost: reverses a line of current text. Pre-1.0, and nothing compiles against it today (it has no emit site).
>
> Cross-language: Rust allows `Self { .. }`, `Self::V(..)`, `Self::new()` and `Self::V` patterns in impls; nobody finds it confusing. Swift allows `Self.init` and `.case`.
>
> ### Proposal G2-B (fallback): keep the ban, one code for it
>
> If the panel wants to keep "not a constructor": every value use of `Self` in an impl or trait body other than a static call (`Self.f()`) is refused with one code, `SelfNotConstructor` with a new E-number, help "write `Color.Rgb(7)`". Patterns too. I vote against: it keeps a ban that buys nothing and adds a code; and banning `Self.Rgb(n)` in a pattern breaks code that runs today.
>
> ---


### Phase B — Debate highlights

Two facts reached the panel between Phase A and Phase B: the DECISIONS.md row `Self` as constructor (4-1), and the fact that no rationale file backs it. PLT and DevOps each wrote a note about it, quoted first. The Phase B digest then split the group into G2-Q1 and G2-Q2.

- **PLT** (note for Phase B):


> # PLT note for Phase B (G2)
>
> DECISIONS.md:166 (4-1): "`Self` as constructor | Type-position alias only, not a constructor. Use concrete type name". No rationale file in decisions/.
>
> Effect on my Phase A:
> - G2-A asks to remove SelfNotConstructor for impl bodies. That re-opens a decided vote, so I drop it. G2-B becomes my pick for constructions: Self.V(..), Self.V, Self { .. }, Self(..) used as an expression are E0570 SelfNotConstructor, in impls and in default bodies.
> - Open reading: does "type-position alias only" also refuse a pattern head (Self.V(n)) and a static call (Self.f())? Neither builds a value, so the constructor vote does not plainly cover them. But "type-position only" read literally puts every value path out.
>   - PLT view: the rule must pick one reading and state it. Option R1, the literal reading: Self is type-position only, so every value path and pattern headed by Self is refused (E0570 for all). One rule with no exceptions, and it matches the vote text. Option R2, the narrow reading: only constructions are refused, and patterns and Self.f() stay legal. Then the pattern/constructor asymmetry is a decision, not an accident.
>   - In a trait default body, Self.f() is the only way to call an associated fn without a receiver. Under R1, the replacement is a free fn with `T: Tr` and `T.f()`, the same move that 04:5890 already gives for `_`. That is a workable path, so R1 stays sound.
>   - Lean: R1 (literal), with a help that writes the concrete type in an impl and the free-fn form in a default body. Confirm against the other seats in Phase B.

- **DevOps** (note for Phase B):

> devops (after the DECISIONS.md:166 fact, before Phase B), verbatim:
>
> devops: got the G2 fact (DECISIONS.md:166, "Self as constructor: type-position alias only", 4-1). I will deal with it in Phase B. My Phase A pick G2-A (Self is the type in every position) re-opens that vote, so I drop it as my pick. Under the decided rule, my Phase B position will be close to G2-B: an impl's `Self` builds no value. `Self { .. }`, `Self(..)` and also `Self.V` / `Self.V(..)` construction get one coded error (SelfNotConstructor, which needs a real E05xx code) with a machine-applicable fix that writes the type name. I also count `Self.V` construction as "constructor" use, which the vote did not say. The open points for Phase B are static calls (`Self.new()`) and patterns (`Self.V(n)`, `Self { x }`), because the old vote covered only construction. I lean to allowing both: they read a value, they do not build one. The trait default-body table (E0305 / E0547 / E0525) stays as I wrote it.


- **Systems:**

> ## G2-Q1: Self inside an impl body
>
> Position: **G2-TypeParam** (aiml). I drop G2-Alias. G2-NoBuild is my second.
>
> Why I move: DECISIONS.md:166 settled "Self is not a constructor" 4-1. My Phase A case for Alias was "zero cost". That was true at the earlier vote too, so it is no new fact and no ground to re-open it.
>
> Between the two options that keep the vote, TypeParam is the simpler compiler and the simpler rule:
> - One rule in impls and traits: a value path headed by `Self` may only be a static call. The checker resolves `Self` in a value path one way everywhere. The I0023 and NodeCarriesNoType crashes came from `Self` being resolved halfway. TypeParam removes that half-resolved state by refusing it, and NoBuild removes it by resolving it.
> - NoBuild makes `Self.Rgb(n)` legal as an impl pattern but refused in a default body, and legal as a pattern but refused as an expression. That is two splits for a form that only spells a name already reachable another way. aiml's point stands: a pattern already takes the bare `Rgb(n)`, so `Self.Rgb(n)` is a second spelling of it.
> - The fix is cheap: a machine-applicable help writes `Color.Rgb(7)` or `Rgb(n)`.
>
> Against G2-Alias: it re-opens a 4-1 vote with no new fact.
> Against plt's R1 (refuse `Self.f()` too): in a default body there is no other way to call a static method of the trait without moving the code into a free function. That loses a common shape and does not save the compiler any work. `T.zero()` is already legal, so `Self.zero()` is the same lowering.
>
> ## G2-Q2: Self inside a trait default body
>
> Position: **G2-NewCode**, one `SelfNotConstructor` code for every build form and every pattern, the same code as in an impl. G2-TCodes is acceptable.
>
> Argument: under TypeParam the same mistake (`Self.Red`) gets one code in an impl and in a trait. Under TCodes it gets the new code in an impl but E0547 in a trait, and a tool must learn both. TCodes also leans on `T { .. }`, which plt shows has no code today. The hole for a plain `T` should be fixed on its own ticket, with the same code or E0525.

- **Web/Scripting:**

> ## G2-Q1: inside an impl body
>
> **Position: G2-Alias. Fallback order: G2-TypeParam, then G2-NoBuild.**
>
> On the 4-1 vote (DECISIONS.md:166): Phase A says only rollout is settled, so we may re-open it. There are three reasons to do so now:
> 1. The vote has no rationale file. Its text covers construction only, and it never ruled on `Self.V`, patterns or `Self.f()`. Every option on this ballot already extends it, so no option "keeps the vote as is".
> 2. New fact: the pattern `Self.Rgb(n)` runs today, and two build forms crash. Users and models already write these.
> 3. A majority of Phase A picks (web, sys, min, plt before the fact, devops before the fact) chose Alias on its merits.
>
> DX case: "replace `Self` with the type name" is a rule a person learns once. Any ban on top of it is a list of exceptions to learn. Rust-trained models write `Self { .. }` and `Self::V(..)` in every impl. Under Alias they are right on the first try.
>
> Against aiml's "one spelling per value": in an impl, `Self` vs `Color` is the same kind of choice as `Self` vs `Color` in `-> Self`, which the spec already allows. No one reports confusion from that in Rust.
>
> If Alias loses, I rank **TypeParam over NoBuild**. NoBuild lets you match `Self.Rgb(n)` and refuses `Self.Rgb(n)` as an expression. A pattern and its constructor look the same, so users will ask "why can I match it but not build it?". TypeParam at least gives one sentence: "`Self` can only head a static call". It has a machine-applicable fix that writes the concrete name.
>
> ## G2-Q2: trait default body
>
> **Position: G2-NewCode, one code for every Self-headed build form and pattern.**
>
> Against G2-TCodes: E0547 "no variant `Red` on `Self`" and E0300 describe the symptom, not the mistake. The user meant "build a value of the implementing type". The useful help is "declare `fn make() -> Self` in the trait and call `Self.make()`", and a dedicated code can carry that help. plt's point also holds: `Self {}` with no labels gets no existing code at all. I would put patterns under the same new code rather than E0308. One code means one docs page and one search term. If plt wants E0308 for patterns because it is the general type-parameter rule, that is acceptable, provided the E0308 help names the same fix.

- **PLT:**

> ## G2-Q1: inside an impl body
>
> Position: **G2-Alias**, then G2-NoBuild, then G2-TypeParam.
>
> On the vote (DECISIONS.md:166): Alias reverses it. The moderator put Alias on the ballot, so I vote for it openly. If Alias wins, DECISIONS.md must record the reversal. My reasons to reverse:
> - The vote has no rationale file. Its stated reason, "use the concrete type name", is a style rule, and style needs no error.
> - In an impl, `Self` is the target type in every type position (`fn f() -> Self { Color.Red }` checks because `Self` is `Color`). Refusing the same alias at a value head gives one name two meanings in one body.
> - Today `Self.Rgb(n)` runs as a pattern and `Self.Rgb(7)` crashes as an expression. A constructor and its pattern are duals, and only Alias treats them alike with no extra rule.
>
> If the panel treats the vote as binding, I pick **G2-NoBuild**. It is the narrowest reading of the vote text, "not a constructor". A pattern takes a value apart and a static call is an ordinary call; neither builds through `Self`.
>
> Snippet (the requested G2-NoBuild one):
>
> ```blink
> type Color { Red, Rgb(Int) }
> type Point { x: Int, y: Int }
>
> trait Mk { fn make(n: Int) -> Self }
>
> impl Mk for Color {
>     fn make(n: Int) -> Self {
>         if n == 0 { Self.Red } else { Color.Rgb(n) }     // `Self.Red`: SelfNotConstructor, help: `Color.Red`
>     }
> }
>
> impl Color {
>     fn bump(self) -> Color {
>         match self {
>             Self.Rgb(k) => Self.make(k + 1)              // OK: pattern, then static call
>             Self.Red => Color.Red                        // OK: pattern
>         }
>     }
> }
>
> impl Mk for Point {
>     fn make(n: Int) -> Self {
>         let p = Self { x: n, y: n }                      // SelfNotConstructor, help: `Point { x: n, y: n }`
>         match p { Self { x, y } => Point { x: y, y: x } } // OK: struct pattern
>     }
> }
> ```
>
> Under NoBuild, `Self(..)` is SelfNotConstructor too, not E0504: one code for every build form headed by `Self`. All refused forms get one new code next to E0569. E0570 is free in the catalog.
>
> Against G2-TypeParam (aiml):
> - In an impl, `Self` is not a type parameter. `self.x` resolves, and a `Color` value checks where `Self` is expected. TypeParam keeps `Self` concrete for types and calls it abstract for value heads. That is two meanings, the same flaw as NoBuild and one step wider.
> - It is not the literal reading of the vote either. `Self.f()` is a value path, and TypeParam allows it.
> - It breaks a pattern that runs today and fixes no unsound program.
> - aiml argues that code moved from an impl into a trait default would break under Alias. That argument does not tell the options apart. A default body cannot build `Color.Red` under any option, because `Self` there is abstract.
> - aiml's "one spelling" point is real for patterns: `Rgb(n)` already works bare. It is a lint-level point, not a soundness point.
>
> ## G2-Q2: inside a trait default body
>
> I correct my Phase A. I put the patterns at E0308. The catalog says otherwise: E0300's row covers "a qualified enum pattern or a struct pattern on a scrutinee of a type parameter", and E0308 is for bare names. min is right about that.
>
> Position: this depends on Q1.
> - **If Alias wins: G2-TCodes.** `Self` in a default body is a type parameter, so each form gets what the same form on `T` gets: `Self.V` and `Self.V(..)` are E0547; a qualified or struct pattern is E0300; `Self { x: 0 }` is E0525 at the label. No code names `Self`.
> - **If NoBuild or TypeParam wins: G2-NewCode** for the build forms, with the same code as in impls, so the language has one rule ("`Self` builds nothing"). Patterns stay E0300, as for `T`.
>
> Under TCodes, `Self {}` with no labels has no refusing code. Neither has `T {}` (my Phase A side finding). That hole must close for `T` in any case. When it closes, the fix covers `Self` too. Until it closes, TCodes is incomplete, and a seat that votes TCodes votes for that fix as well.

- **DevOps:**

> ## G2-Q1: impl body
>
> **Position: G2-TypeParam. Second: G2-NoBuild. Alias only if the panel re-opens DECISIONS.md:166 by name and records the amendment.**
>
> I move from NoBuild (my note after the fact) to TypeParam, after reading aiml and plt's R1 note:
> - One code, one rule in both contexts: "`Self` may head a static call; it heads no value and no pattern." The diagnostic is the same code at the `Self` token everywhere; only the help differs (impl: write the type name, machine-applicable; default body: add a trait fn and call `Self.f()`).
> - The banned pattern costs nothing: a variant pattern already takes the bare variant (`Rgb(n)`), and a struct pattern writes the type name. The fix-it drops `Self.` or writes the name.
> - NoBuild keeps a pattern/build split (`Self.Rgb(n)` OK in `match`, error in an expression) that each user must learn by hitting it. TypeParam has no split.
> - Static calls stay: `Self.make()` is the only way a default body reaches an associated fn, and `T.zero()` is already in the spec. A static call does not construct by syntax; the vote text targets construction.
>
> Against Alias: it is the best design on its own (my Phase A pick), but it reverses a recorded 4-1 vote. If four seats now want it, that should be a named re-vote of :166, not a side effect of this ticket.
>
> Snippet for G2-NoBuild (requested). Builds refused, patterns and static calls legal:
>
> ```blink
> type Color { Red, Rgb(Int) }
> type Point { x: Int, y: Int }
>
> trait Mk {
>     fn make(n: Int) -> Self
>     fn tag(self) -> Int
> }
>
> impl Mk for Color {
>     fn make(n: Int) -> Self {
>         if n == 0 { Self.Red } else { Color.Rgb(n) }   // error[SelfNotConstructor] at `Self`
>                                                         //   help: write `Color.Red` (machine-applicable)
>     }
>     fn tag(self) -> Int {
>         match self {
>             Self.Rgb(n) => n                            // OK under NoBuild: a pattern builds nothing
>             Self.Red => 0                               // OK
>         }
>     }
> }
>
> impl Mk for Point {
>     fn make(n: Int) -> Self { Self.origin() }           // OK: static call
>     fn tag(self) -> Int {
>         match self { Self { x, .. } => x }              // OK under NoBuild
>     }
> }
>
> fn Point.origin() -> Point { Point { x: 0, y: 0 } }   // `Self { x: 0, y: 0 }` here is E0569 (outside an impl)
> ```
>
> Under G2-TypeParam the two `match` arms headed by `Self` are also `SelfNotConstructor`, help `Rgb(n)` / `Red` / `Point { x, .. }`.
>
> ## G2-Q2: trait default body
>
> **Position: G2-NewCode, for build forms and patterns. I drop G2-TCodes.**
>
> TCodes made sense when Q1 had no new code. Once Q1 adds `SelfNotConstructor`, the default body should give the same code for the same form, so one form has one code in both contexts. plt's hole also settles it: `Self {}` with no labels gets neither E0547 nor E0525, so TCodes leaves a form with no code. Patterns too (not E0308): E0308's help talks about binding a lowercase name, which is the wrong fix for `Self.Red =>`; the `SelfNotConstructor` help ("`Self` has no known shape here; add a trait fn") is the right one.

- **AI/ML:**

> ## G2-Q1: inside an impl body
>
> **Position: G2-TypeParam.**
>
> First, scope. The moderator listed DECISIONS.md:166 (4-1, "type-position alias only, not a constructor") as already decided. G2-Alias removes SelfNotConstructor for impls, so it re-opens that vote. web, sys and min still pick Alias. I ask the moderator to rule whether Alias is on the ballot. If it is not, the choice is TypeParam or NoBuild.
>
> Against G2-NoBuild (plt's fallback, devops's new pick): it lets the same text be legal on one side of `=>` and an error on the other.
>
> ```blink
> match self {
>     Self.Rgb(k) => Self.Rgb(k + 1)     // NoBuild: the pattern is OK, the expression is SelfNotConstructor
> }
> ```
>
> A model learns from what it sees. It sees `Self.Rgb(k)` accepted as a pattern and writes `Self.Rgb(k + 1)` next to it. Under NoBuild that is a guaranteed miss on every enum impl. devops says a pattern "reads a value and does not build one". That is true for the compiler, but text gives no clue to it: the two forms look the same. Also, patterns do not need `Self` at all. A pattern already takes the bare variant (`Rgb(k)`, 03_types.md ~4594), which is shorter. So refusing `Self.V` in a pattern costs nothing, and the help can drop `Self.` as a machine fix.
>
> TypeParam is one sentence that holds in both a trait and an impl: "`Self` in a value path can call a static fn. It cannot build or match." A model does not need to know which body it is in.
>
> Against plt's R1 (refuse `Self.f()` too): in a trait default body there is no concrete name, so `Self.f()` is the only short way to call an associated fn. The free-fn workaround (04:5890) works, but it is a rewrite of the method's shape. A model will not find it from an error message. `T.zero()` is already legal, so refusing `Self.zero()` makes `Self` weaker than `T` for no gain. I keep static calls legal.
>
> If the panel does put Alias on the ballot, my ranking is TypeParam > Alias > NoBuild. Alias is one rule (substitution) and matches Rust, so it gives the fewest first-try errors. NoBuild is the only option with a split that the text does not show.
>
> ## G2-Q2: inside a trait default body
>
> **Position: G2-NewCode, one code for every build form and every Self-headed pattern.**
>
> Against G2-TCodes (min, devops): the codes would tell a model the wrong thing to fix.
> - `Self.Red` as E0547 NoSuchVariant says "this type has no variant `Red`". The natural repair is to add a variant, or to look for a spelling mistake. Neither is the problem. The problem is that `Self` is abstract here.
> - E0300 for a pattern points at the scrutinee type, not at `Self`.
>
> One code, at the `Self` token, with a help that says "`Self` is any implementing type here; declare `fn make() -> Self` and call `Self.make()`", points straight at the repair. It is the same code that the same forms get in an impl body under TypeParam, so one code covers one idea in both places. plt's E0308 for patterns in a default body has the same problem as E0300: it talks about the scrutinee type, not about `Self`.

- **Minimalism:**

> ## G2: honor the 4-1 vote; Self acts as a type parameter everywhere
>
> I drop G2-Alias. It re-opens a recorded vote with no new fact. The crashes (I0023, NodeCarriesNoType) are bugs under any option, so they give no reason to re-open it.
>
> ### G2-Q1: G2-TypeParam (aiml)
>
> My pick is one model for both places: `Self` in a value path acts as a type parameter does. It may head a static call, and nothing else. Every build form and every pattern headed by `Self` gets one new code, SelfNotConstructor, with a help that writes the concrete name.
>
> - Against G2-NoBuild: it asks users to learn that `Self.Rgb(n)` is fine in a pattern but not in an expression. The pattern form buys nothing, because a pattern already finds the variant from the scrutinee: bare `Rgb(n)` works (aiml's fact, 03 ~4594). An exception that buys nothing is the first thing to cut.
> - Against plt's R1 (refuse static calls too): `Self.f()` is the only way a default body calls a static fn of its own trait. R1 forces a free fn with `T: Tr` to replace it. That gives up a working, already-specified form (`T.zero()`) to make the rule shorter by one clause. Type parameters already head static calls, so allowing it adds no rule.
>
> ```blink
> type Color { Red, Rgb(Int) }
>
> trait Mk {
>     fn make() -> Self
>     fn twice() -> (Self, Self) { (Self.make(), Self.make()) }   // OK: static call, make is in the guarantee set
> }
>
> impl Mk for Color {
>     fn make() -> Self { Self.Rgb(7) }      // error[SelfNotConstructor]; help: `Color.Rgb(7)`
> }
>
> impl Color {
>     fn level(self) -> Int {
>         match self {
>             Self.Rgb(n) => n               // error[SelfNotConstructor]; help: `Rgb(n)`
>             Red => 0                       // OK
>         }
>     }
>     fn fresh() -> Color { Self.make() }    // OK: static call
> }
> ```
>
> ### G2-Q2: G2-NewCode, patterns included (moved from G2-TCodes)
>
> My Phase A G2-TCodes only made sense under G2-Alias. Under G2-TypeParam, `Self.Red` in an impl is SelfNotConstructor. If the same text in a default body were E0547, one form would get two codes depending on where it sits, which is a second rule. So it should be the same new code in both places. Patterns included, against plt's E0308 split for patterns, for the same reason.


### Phase C — Silent ballot

| Question | Sys | Web | PLT | DevOps | AI/ML | Min | Result |
|----------|-----|-----|-----|--------|-------|-----|--------|
| Q1. `Self` as a value-path or pattern head in an impl body | TypeParam | Alias | Alias | TypeParam | TypeParam | TypeParam | TypeParam 4, Alias 2: a 4-2 result, so one focused Phase D round |
| Q2. In a trait default body | NewCode-all | NewCode-all | if Q1 = Alias then TCodes; else NewCode-build | NewCode-all | NewCode-all | if Q1 = TypeParam then NewCode-all; if Q1 = NoBuild then NewCode-build; if Q1 = Alias then TCodes | NewCode-all 4 (Sys, Web, DevOps, AI/ML), TCodes 2 (PLT, Min) |


- **Systems:**

> ## G2-Q1
> **Vote:** TypeParam
> **Reasoning:** DECISIONS.md:166 settled "not a constructor" 4-1, and "zero cost" was already true then, so I see no new fact to reverse it. TypeParam gives the checker one path for a `Self` value path in impls and in traits: a static call or nothing. That removes the half-resolved state behind the I0023 and NodeCarriesNoType crashes. The machine-applicable help keeps the fix to one edit.
> **Concern:** Rust-trained users and models will write `Self.Rgb(n)` in impl patterns often, and each one costs a compile round trip.
>
> ## G2-Q2
> **Vote:** NewCode-all
> **Reasoning:** The same mistake (`Self.Red`, `Self { x }`) gets the same code in an impl and in a default body, so a tool or a model learns one code. TCodes depends on the `T {}` hole, which has no code today. NewCode-all needs nothing else fixed first.
> **Concern:** If G2-Q1 picks Alias, NewCode-all puts a Self-only code on a form that also fails on `T`, and the two can drift apart.

- **Web/Scripting:**

> ## G2-Q1
> **Vote:** Alias
> **Reasoning:** "Inside an impl, `Self` is the type name" is learned once, with no list of exceptions. Rust-trained users and models write `Self { .. }`, `Self.V(..)` and `Self.new()` in every impl, and today the pattern form already runs while two build forms crash. If Alias loses, TypeParam is better DX than NoBuild, because "I can match `Self.Rgb(n)` but cannot build it" will be a standing Stack Overflow question.
> **Concern:** Code moved from an impl into a trait default body stops compiling, so the trait-body error must say why and how to fix it.
>
> ## G2-Q2
> **Vote:** NewCode-all
> **Reasoning:** One code means one docs page, one search term and one help: "declare `fn make() -> Self` in the trait and call `Self.make()`". E0547, E0300 and E0525 describe a symptom ("no variant", "no field") and send the user the wrong way, because the real mistake is building or matching an abstract `Self`. The label-less `Self {}` also gets a code at once, with no separate fix.
> **Concern:** If Q1 = Alias, the new code fires only in trait default bodies, so its name and help must say "abstract `Self` in a trait default body", not imply the impl case is refused too.

- **PLT:**

> ## G2-Q1
> **Vote:** Alias
> **Reasoning:** In an impl body, `Self` is the target type in every type position, so a value head should mean the same thing. Then the whole rule is substitution. A constructor and its pattern are duals, and today one runs while the other crashes; only Alias treats them alike. The vote at DECISIONS.md:166 has no rationale file, and its reason ("use the concrete type name") is a style rule, which needs no error.
> **Concern:** If Alias wins, the reversal must be recorded in DECISIONS.md and the SelfNotConstructor text removed, or the spec will hold two contradicting rules.
>
> ## G2-Q2
> **Vote:** if Q1 = Alias then TCodes; if Q1 = NoBuild or TypeParam then NewCode-build
> **Reasoning:** In a default body, `Self` is a type parameter, so under Alias it should get exactly the codes `T` gets, and no code needs to name `Self`. If a SelfNotConstructor code exists for impls, build forms in a default body should get that same code, so "Self builds nothing" is one rule. Patterns stay E0300 as on `T`, because that is the existing catalog rule for a type-parameter scrutinee.
> **Concern:** Under TCodes, `Self {}` with no labels stays unrefused until the `T {}` hole is closed, and that fix must land with this one.

- **DevOps:**

> ## G2-Q1
> **Vote:** TypeParam
> **Reasoning:** One rule and one code at the `Self` token in both contexts: `Self` heads a static call and nothing else. Only the help differs, and in an impl it is machine-applicable (write the type name, or drop `Self.` in a variant pattern), so the cost of a Rust-trained guess is one fix-it. NoBuild leaves a pattern/build split that users learn only by hitting it. Alias is the cleanest design, but it reverses a recorded vote for convenience, and the panel has no new fact that requires it.
> **Concern:** Rust-trained users and models will hit `SelfNotConstructor` often, so the help and the language-server quick fix must be exact on every form, or the rule reads as friction.
>
> ## G2-Q2
> **Vote:** NewCode-all
> **Reasoning:** One form should have one code in both contexts, and the help in a default body ("`Self` has no known shape here; add a trait fn and call `Self.f()`") is the right fix. E0300's and E0308's help is about qualified paths and binding names, which is the wrong fix for `Self.Red =>`. TCodes also leaves the label-less `Self {}` with no code. If Alias wins Q1, I still want this new code for the default body only.
> **Concern:** If Alias wins Q1, a code named `SelfNotConstructor` that fires only in trait bodies needs a name and message that say "abstract `Self`", or users will read it as a ban on `Self` in impls too.

- **AI/ML:**

> ## G2-Q1
> **Vote:** TypeParam
> **Reasoning:** "`Self` in a value path may call a static fn; it never builds or matches" is one sentence, and it holds in both a trait and an impl, so a model does not need to know which body it is in. Every refused form has a machine-applicable fix (write the type name, or drop `Self.` in a pattern, where the bare variant already works). NoBuild is the worst option for my seat: `Self.Rgb(k) => Self.Rgb(k + 1)` is legal on the left and an error on the right, and a model copies the pattern into the expression. If TypeParam loses, I prefer Alias over NoBuild.
> **Concern:** Rust priors make models write `Self { .. }` and `Self::V` often, so the first-try error rate stays high, and the help must be machine-applicable for this to be cheap.
>
> ## G2-Q2
> **Vote:** NewCode-all
> **Reasoning:** One code at the `Self` token, with a help that says "`Self` is any implementing type here; declare `fn make() -> Self` and call `Self.make()`", points at the true repair. TCodes give E0547 NoSuchVariant, which tells a model to add a variant or fix a spelling, and E0300, which points at the scrutinee: both lead to the wrong edit. If Q1 = Alias, I still vote NewCode-all, because a code that names `Self` is the clearest signal that the abstract `Self` is the problem.
> **Concern:** If Q1 = Alias, a code used only in default bodies is rare, and its text must explain why the same form works in an impl.

- **Minimalism:**

> ## G2-Q1
> **Vote:** TypeParam
> **Reasoning:** It keeps the 4-1 vote and gives one model for both places: `Self` in a value path acts as a type parameter, so it heads a static call and nothing else. A `Self.V` pattern buys nothing, because bare `Rgb(n)` already works in a pattern. So NoBuild's pattern exception is pure cost. Alias reverses a recorded vote with no new fact; the crashes are bugs under every option.
> **Concern:** Users from Rust will write `Self { .. }` and `Self.V` often, so the help must be machine-applicable or this code becomes friction.
>
> ## G2-Q2
> **Vote:** if Q1 = TypeParam then NewCode-all; if Q1 = NoBuild then NewCode-build; if Q1 = Alias then TCodes
> **Reasoning:** The same text should get the same code in an impl and in a default body. So the default-body answer follows whatever Q1 picks. Under TypeParam that is one SelfNotConstructor code for every build form and every pattern. Two codes for one form, chosen by where it sits, would be a second rule to learn.
> **Concern:** Under TCodes the label-less `Self {}` / `T {}` hole stays open until a separate fix lands.


### Phase D — Focused debate on Q1

The Phase C result on Q1 was 4-2, so the panel held one focused round on Q1 only. Every other question stayed closed. The lead sent each seat the digest below, with each seat's Phase C text. Each seat replied, then voted again on Q1 and Q2 (Q2 as a conditional on the Q1 result).

#### Phase D digest


> # Phase D: focused debate on G2-Q1 only
>
> Phase C result on G2-Q1 (Self as a value-path or pattern head inside an impl body): TypeParam 4 (sys, aiml, devops, min), Alias 2 (web, plt), NoBuild 0. A 4-2 result triggers one focused round. Every other question is decided and stays closed. G2-Q2 follows whatever G2-Q1 picks.
>
> Options (unchanged from the ballot):
> - **Alias**: Self is the target type in every position. `Self.Red`, `Self.Rgb(7)`, `Self { x: 1, y: 2 }`, `Self.make(0)`, and the patterns `Self.Rgb(n)`, `Self { x, y }` all compile as the type name would. Reverses DECISIONS.md:166.
> - **NoBuild**: build forms (`Self.Red`, `Self.Rgb(7)`, `Self { .. }`, `Self(..)` as expressions) are SelfNotConstructor (new code). Static calls and patterns compile.
> - **TypeParam**: only static calls (`Self.make(0)`) compile. Every build form and every Self-headed pattern is SelfNotConstructor (new code); the help writes the concrete name, or drops `Self.` in a variant pattern.
>
> Each seat's Phase C G2-Q1 text, verbatim:
>
> ### sys
> **Vote:** TypeParam
> **Reasoning:** DECISIONS.md:166 settled "not a constructor" 4-1, and "zero cost" was already true then, so I see no new fact to reverse it. TypeParam gives the checker one path for a `Self` value path in impls and in traits: a static call or nothing. That removes the half-resolved state behind the I0023 and NodeCarriesNoType crashes. The machine-applicable help keeps the fix to one edit.
> **Concern:** Rust-trained users and models will write `Self.Rgb(n)` in impl patterns often, and each one costs a compile round trip.
>
>
> ### web
> **Vote:** Alias
> **Reasoning:** "Inside an impl, `Self` is the type name" is learned once, with no list of exceptions. Rust-trained users and models write `Self { .. }`, `Self.V(..)` and `Self.new()` in every impl, and today the pattern form already runs while two build forms crash. If Alias loses, TypeParam is better DX than NoBuild, because "I can match `Self.Rgb(n)` but cannot build it" will be a standing Stack Overflow question.
> **Concern:** Code moved from an impl into a trait default body stops compiling, so the trait-body error must say why and how to fix it.
>
>
> ### plt
> **Vote:** Alias
> **Reasoning:** In an impl body, `Self` is the target type in every type position, so a value head should mean the same thing. Then the whole rule is substitution. A constructor and its pattern are duals, and today one runs while the other crashes; only Alias treats them alike. The vote at DECISIONS.md:166 has no rationale file, and its reason ("use the concrete type name") is a style rule, which needs no error.
> **Concern:** If Alias wins, the reversal must be recorded in DECISIONS.md and the SelfNotConstructor text removed, or the spec will hold two contradicting rules.
>
>
> ### devops
> **Vote:** TypeParam
> **Reasoning:** One rule and one code at the `Self` token in both contexts: `Self` heads a static call and nothing else. Only the help differs, and in an impl it is machine-applicable (write the type name, or drop `Self.` in a variant pattern), so the cost of a Rust-trained guess is one fix-it. NoBuild leaves a pattern/build split that users learn only by hitting it. Alias is the cleanest design, but it reverses a recorded vote for convenience, and the panel has no new fact that requires it.
> **Concern:** Rust-trained users and models will hit `SelfNotConstructor` often, so the help and the language-server quick fix must be exact on every form, or the rule reads as friction.
>
>
> ### aiml
> **Vote:** TypeParam
> **Reasoning:** "`Self` in a value path may call a static fn; it never builds or matches" is one sentence, and it holds in both a trait and an impl, so a model does not need to know which body it is in. Every refused form has a machine-applicable fix (write the type name, or drop `Self.` in a pattern, where the bare variant already works). NoBuild is the worst option for my seat: `Self.Rgb(k) => Self.Rgb(k + 1)` is legal on the left and an error on the right, and a model copies the pattern into the expression. If TypeParam loses, I prefer Alias over NoBuild.
> **Concern:** Rust priors make models write `Self { .. }` and `Self::V` often, so the first-try error rate stays high, and the help must be machine-applicable for this to be cheap.
>
>
> ### min
> **Vote:** TypeParam
> **Reasoning:** It keeps the 4-1 vote and gives one model for both places: `Self` in a value path acts as a type parameter, so it heads a static call and nothing else. A `Self.V` pattern buys nothing, because bare `Rgb(n)` already works in a pattern. So NoBuild's pattern exception is pure cost. Alias reverses a recorded vote with no new fact; the crashes are bugs under every option.
> **Concern:** Users from Rust will write `Self { .. }` and `Self.V` often, so the help must be machine-applicable or this code becomes friction.
>
>
> ---
> Reply: your strongest argument on G2-Q1 only, answering the other side's points above. You may change your position. Write to S/D/r-<seat>.md, SendMessage it to team-lead, end with STABLE. A silent re-vote follows.


#### Phase D replies


- **Systems:**

> # Phase D, G2-Q1, Systems seat (sys)
>
> Position: **TypeParam** (unchanged).
>
> To plt, "the whole rule is substitution": that is true inside an impl, and only there. A trait default body cannot substitute, because `Self` is abstract, so Alias still needs a second rule for traits. web names the result as Alias's own concern: code moved from an impl into a default body stops compiling. Under TypeParam the same text means the same thing in both bodies, so a move never changes the verdict. I count one rule for two bodies as simpler than substitution in one body plus a refusal in the other.
>
> To plt, "constructor and pattern are duals, only Alias treats them alike": TypeParam treats them alike as well, because it refuses both. Only NoBuild splits them. The crash on the build side and the run on the pattern side are compiler bugs. Every option must fix them, so they are no argument for one option over another.
>
> To plt, "a style rule needs no error": as I read the 4-1 vote, it was about which spelling the language has, not only about style. From my seat, an error with a machine-applicable fix costs one edit, once. It also keeps one spelling for each value in the corpus that models train on, which aiml and min count as a gain. The absence of a rationale file is a gap in the record. It is not a new fact about the language, and I hold that reversing a recorded vote needs a new fact.
>
> Cost check, for the record: all three options lower to the same C. Alias does not save the runtime or the generated code anything. Its only gain is fewer compile errors for Rust-trained authors, and the help that writes the type name covers that.
>
> STABLE

- **Web/Scripting:**

> # Web seat, Phase D, G2-Q1
>
> **Position: Alias (unchanged). TypeParam is my clear second; NoBuild is last.**
>
> **1. TypeParam does not "keep" the 4-1 vote. It is a new and wider ruling.** DECISIONS.md:166 refused construction: "Use concrete type name". It said nothing about patterns or static calls. TypeParam adds a ban on `Self.Rgb(n)` and `Self { x, y }` in patterns, which no vote ever made, and it turns a form that runs today into an error. So both options decide something the old vote did not. The real choice is between two new rules on their merits, not between "honor the vote" and "reverse it".
>
> **2. All four TypeParam votes name the same concern, and that concern is the case against TypeParam.** sys, devops, aiml and min each wrote some form of "Rust-trained users and models will hit this often". A rule whose own supporters expect it to fire often on code that reads as correct is friction by design. A machine-applicable fix makes each hit cheap, but it does not make it free. Each hit is a failed check, a fix, and a re-run, and a user who wonders why a type alias cannot do what its name can will post on Stack Overflow. Alias makes those first tries correct, with no code, no help text and no quick fix to keep exact.
>
> **3. "One sentence for both bodies" holds under Alias too.** Under Alias the sentence is "`Self` is the type, and in a trait the type is abstract, so it has no shape to build or match". That is the same rule a user already knows for `T`, and it needs no knowledge of which body you are in: a known type has a shape, an abstract one does not. TypeParam gives `Self` in an impl less power than the type name it stands for, even though the type is fully known there. That is the exception a user has to learn.
>
> **4. The cost of Alias is style, and style is not an error.** The only stated reason for the old ban is "write the concrete name". If a team wants that, a lint or `blink fmt` can enforce it, without a compile error on correct code.
>
> I accept that the crashes are bugs under every option, so they are not the reason for Alias. If the re-vote stays TypeParam, I want its help to be machine-applicable on every form (devops's concern), and the DECISIONS.md row must record that patterns were added to the ban, so the next reader does not take it as the 4-1 vote unchanged.
>
> STABLE

- **PLT:**

> # PLT, Phase D, G2-Q1
>
> Position: **Alias**, then TypeParam, then NoBuild. I agree with aiml and web that NoBuild is the worst: a form legal on the left of `=>` and an error on the right is the asymmetry I objected to in Phase A.
>
> ## All three are sound
>
> No option admits a bad program. So this vote picks a model, not a fix to a hole. I judge the options by whether the model each claims is the model it implements.
>
> ## TypeParam's "one model in both places" does not hold in an impl
>
> sys, devops, aiml and min all say that under TypeParam, `Self` in a value path "acts as a type parameter" in both contexts. In an impl it does not, and TypeParam has to choose on a case that nobody has ruled on:
>
> ```blink
> type Color { Red, Rgb(Int) }
>
> fn Color.parse(s: Str) -> Color { if s == "red" { Color.Red } else { Color.Rgb(0) } }   // type-scoped, no trait
>
> trait Mk { fn make(n: Int) -> Self }
>
> impl Mk for Color {
>     fn make(n: Int) -> Self {
>         Self.parse("red")       // TypeParam: OK or SelfNotConstructor?
>     }
> }
> ```
>
> - **If it compiles:** `Self` resolved `parse` through the concrete type `Color`. A type parameter cannot do that, because a type parameter reaches only the functions of its bounds. So in an impl, TypeParam is really "the alias, minus build and match". It is two refusals cut out of Alias, not one model shared with traits.
> - **If it is refused:** the rule refuses a call that cannot go wrong, and that has its own fix (`Color.parse`). It gives `Self` a third meaning: concrete in type position (`-> Self` takes a `Color` value, and `self.x` resolves), abstract for calls, and refused for build and match.
>
> The same question applies to `fn bump(self) -> Self { Color.Rgb(1) }`. That compiles under every option, because `Self` is `Color` in type position. So "Self is a type parameter in an impl" is false in TypeParam's own examples.
>
> ## "No new fact"
>
> min, sys and devops say Alias reverses the vote with no new fact. There are two:
> 1. The vote covered construction only. Self-headed patterns were never voted on, and they run today. TypeParam refuses them, so TypeParam also goes beyond DECISIONS.md:166, toward the opposite side from Alias. It is not the conservative reading. NoBuild is.
> 2. The measured state is new. The pattern runs, two build forms crash, and the old text's error has no code. The old vote did not see any of this.
>
> ## What I concede
>
> min is right that `Self.V` patterns buy little, since bare `Rgb(n)` works. devops and aiml are right that a machine-applicable help makes a refusal cheap. If the panel keeps TypeParam, its rule text must answer the `Self.parse` case above in plain words. I would rule "compiles", and state that in an impl, `Self` in a call head is the target type.
>
> STABLE

- **DevOps:**

> # devops, Phase D, G2-Q1 only
>
> **Position: I change to Alias.** (Second: TypeParam. NoBuild last.)
>
> My Phase C reasoning for TypeParam had one leg that was not procedure: "the cost of a wrong guess is one fix-it". Read the four TypeParam concerns side by side. sys, aiml, min and I all wrote the same sentence: users and models will hit `SelfNotConstructor` often, so the fix must be machine-applicable. That is the case against the error, from my own seat:
>
> - **A machine-applicable fix that always yields an equal program is a lint, not an error.** Every TypeParam fix-it rewrites `Self.Rgb(7)` to `Color.Rgb(7)`, a program with the same type and the same value. The compiler knows the answer every time and makes the user ask for it. Go and rust-analyzer keep that kind of rewrite in the formatter or an assist, not in a compile error. The four of us predicted a high first-try error rate. That is a code with no safety value and a known, constant cost: each hit is a check round trip for a person and a repair step for an agent.
> - **The procedural leg is weak.** DECISIONS.md:166 has no rationale file. Its stated reason, "use the concrete type name", is a style preference (plt's point). Since then there are new facts: the pattern form runs today, two build forms crash with exit 101, and the ticket shows users write all of these forms. Pre-1.0 we change rules when the facts change. The vote stays on record as reversed, with the reason.
> - **Alias has the smallest diagnostic surface.** It needs no new code in impls and no help text per form. Every refused form gets the code the type name would get (`Self.Blue` is E0547, as `Color.Blue` is), so the existing helps and nearest-name suggestions apply. The language server treats `Self` as the type: completion, go-to-definition and rename work, as in rust-analyzer.
> - **Web's concern (code moved into a trait default body stops compiling) belongs to G2-Q2.** There `Self` is abstract, and a coded error with the help "add a trait fn and call `Self.f()`" is a real fault with a real fix. That is the one place where a `Self` error tells the user something they did not know.
>
> Against TypeParam's "one rule in both bodies" (aiml, min): the two bodies differ in fact. In one, `Self` is a known type; in the other it is not. A rule that hides that difference makes the user pay for the trait-body limits in the impl body, where they do not apply.
>
> If TypeParam wins, my Phase C concern stands: the help and the quick fix must be exact and machine-applicable on every form.
>
> STABLE

- **AI/ML:**

> # aiml, Phase D, G2-Q1 only
>
> **Position: TypeParam (unchanged).**
>
> I grant web and plt their best point. Today, Alias gives the fewest first-try errors for a model trained on Rust. My case is about what a model learns over time. It is not about the first try.
>
> **1. Alias makes the rule depend on where the code is, and a model often does not track that.** Under Alias, `Self.Rgb(7)` is legal in an impl body and an error in a trait default body. web names this cost: "code moved from an impl into a trait default body stops compiling." For a person this happens now and then. For a model it is a steady cost. A model writes default bodies, moves helpers between impls and traits, and fills in method bodies with no clear view of which kind of body it is in. TypeParam gives the same answer in both bodies. A model that learns "`Self` heads a static call and nothing else" is right in every body, with no context to track.
>
> **2. Blink's own code is training data, so two spellings now become two habits later.** Under Alias, the corpus (lib/std, tests, user code) will mix `Self.Rgb(n)` and `Color.Rgb(n)` in impls. Models trained on that mix will carry `Self.X` into the places where it fails: trait default bodies, and free fns (E0569). Under TypeParam the corpus has one spelling, the type name. Each new model trained on Blink code then needs the help less.
>
> **3. On plt's "it's a style rule, so it needs no error":** a style rule kept by a lint or by `blink fmt` does not shape what a model writes. Models learn from the source they see, and a warning that a model can leave in place does not change that source. Only a rule that refuses the code keeps the corpus to one spelling. The reason in point 2 is not a style preference: it is about what the corpus teaches.
>
> **4. On plt's "a constructor and its pattern are duals":** TypeParam keeps the two alike. It refuses both, just as Alias allows both. That is why I rank NoBuild last and TypeParam first. The duality argument counts against NoBuild, not against TypeParam.
>
> **5. The cost web and plt fear is one machine-applicable edit.** Each refused form has an exact fix: write the type name, or drop `Self.` in a variant pattern, where the bare variant already works. A model with a language server or `blink fix` repairs it in one round trip, and after a few rounds of training the error stops coming up. Under Alias, the error in point 1 has no single mechanical fix, because the trait body has no concrete type name to write.
>
> STABLE

- **Minimalism:**

> # min, Phase D, G2-Q1 only
>
> **Position: I move to Alias.**
>
> I moved from Alias to TypeParam in Phase B for one reason: the DECISIONS.md:166 vote. That was deference to process, not a minimalism argument. Measured on my seat's own question, "what does the language need?", Alias is the smaller language, and I should say so.
>
> Count what each option adds:
>
> - **Alias** adds no error code, no help, no fix-it and no language-server quick fix. It deletes one paragraph (SelfNotConstructor) and one code that has never had an emit site. The whole rule is one sentence: in an impl body, `Self` is the target type.
> - **TypeParam** adds a new error code, a catalog row, a machine-applicable help for each form, a quick fix, and tests for all of them. Every seat that voted for it, me included, gave the same concern: Rust-trained users and models will hit this error often. A rule that every supporter expects to fire often, and that exists only to tell the user to write a name the compiler already knows, is a cost with no matching benefit.
>
> Answers to the TypeParam side:
>
> - **"Keeps the 4-1 vote."** That vote has no rationale file. Its only stated reason is "use the concrete type name", which is a style preference, and a style preference does not need a compile error. A vote with no recorded reason should not outweigh a reason the panel can state now: Alias has no exceptions, and TypeParam's error costs a compile round trip each time it fires.
> - **"One model for trait and impl" (aiml, devops).** `Self` already means two things: an abstract parameter in a trait and a concrete type in an impl. `fn eq(self, other: Self)` in an impl takes a `Color`, not an abstract type. TypeParam does not remove that split. It only hides the concrete meaning in value position while type position keeps it. Alias makes value position agree with type position in the same body, and that is the smaller rule.
> - **"The crashes" (sys).** Under Alias, `Self.Red` and `Self.Rgb(7)` take the alias lookup that `Color.Red` already takes. That is less checker code than a new refusal path, not more.
> - **"The `Self.V` pattern buys nothing" (my own Phase B point).** That argued against NoBuild's split, and it still holds against NoBuild. Under Alias the pattern needs no rule at all: it is the type-name pattern.
>
> Against NoBuild (unchanged): it is the only option with an asymmetry that users learn only by hitting it.
>
> If Alias loses, TypeParam remains my second choice over NoBuild.
>
> STABLE


#### Phase D re-vote ballot


> # Phase D re-vote: G2-Q1 and G2-Q2
>
> All six Phase D replies are in S/D/r-<seat>.md. Read the other five before you vote.
>
> Vote silently on two questions. For each: **Vote**, **Reasoning** (2-4 sentences), **Concern** (one sentence). Write to S/D/vote-<seat>.md, then SendMessage the same text to team-lead. Do not message other seats.
>
> ## G2-Q1: Self as a value-path or pattern head inside an impl body
> - **Alias**: Self is the target type in every position. Reverses DECISIONS.md:166.
> - **NoBuild**: build forms are SelfNotConstructor (new code); static calls and patterns compile.
> - **TypeParam**: only static calls compile; every build form and every Self-headed pattern is SelfNotConstructor (new code).
>
> ## G2-Q2: inside a trait default body (Self is abstract)
> G2-Q2 follows G2-Q1, so give an unconditional vote for the case "G2-Q1 = Alias" and one for "G2-Q1 = TypeParam".
> - **NewCode-all**: every build form and every Self-headed pattern is SelfNotConstructor (under Alias this code fires only in trait default bodies).
> - **NewCode-build**: build forms are SelfNotConstructor; Self-headed patterns get E0300, as on a type parameter.
> - **TCodes**: each form gets what the same form on `T` gets (`Self.V` E0547, qualified or struct pattern E0300, `Self { x: 0 }` E0525); the label-less `Self {}` / `T {}` hole closes separately.


#### Phase D re-votes


- **Systems:**

> # Phase D re-vote, Systems seat (sys)
>
> ## G2-Q1
> **Vote:** Alias (I change from TypeParam)
> **Reasoning:** I voted TypeParam because I thought it gave the checker the simplest path. plt's `Self.parse("red")` case shows that this is false. In an impl, a static call through `Self` must find an inherent fn of the concrete type, so TypeParam is really "substitute `Self` with the type, then refuse build and match": substitution plus a refusal path. Alias is the substitution alone. `Self` binds to the target type at the body `{`, and every form then takes the path `Color.X` takes, with its existing codes. devops's point also holds from my seat: every fix TypeParam's help writes gives the same program and the same C, so the error guards nothing. web and plt are right that TypeParam also goes past the 4-1 vote, by banning patterns that the vote never covered.
> **Concern:** The reversal of DECISIONS.md:166 and the removal of the SelfNotConstructor text for impls must land in the same change, or the spec holds two rules that contradict.
>
> ## G2-Q2, if G2-Q1 = Alias
> **Vote:** NewCode-all
> **Reasoning:** In a trait default body, a build form or pattern headed by `Self` is a real fault: the type has no known shape. One code with one help ("add a trait fn and call `Self.f()`") tells the user exactly that. It also answers web's concern about code moved from an impl into a trait body. It does not depend on closing the `T {}` hole first.
> **Concern:** The same form on a plain `T` gets other codes (E0547, E0300, E0525), so the two families must say the same thing in their help text.
>
> ## G2-Q2, if G2-Q1 = TypeParam
> **Vote:** NewCode-all
> **Reasoning:** Under TypeParam, one code at the `Self` token in both bodies is the whole point of the rule. Splitting trait bodies onto E0300 or E0547 would undo it.
> **Concern:** The help must tell an impl site (write the type name) apart from a trait site (add a trait fn), or the machine-applicable fix will be wrong in trait bodies.

- **Web/Scripting:**

> # Web seat, Phase D re-vote
>
> ## G2-Q1
> **Vote:** Alias
> **Reasoning:** In an impl, `Self` already means the target type in type position (`-> Self` takes a `Color`), so value position should agree. That is one rule with no exceptions to learn, and it adds no code, help or quick fix. plt's `Self.parse("red")` case shows that TypeParam is really "the alias minus build and match" in an impl, not a type parameter, so its "one model in both bodies" claim does not hold. On aiml's corpus point: in Rust, a mixed `Self`/name corpus has not taught models to misuse `Self` in free functions, and E0569 already catches that case with a clear message.
> **Concern:** Code moved from an impl body into a trait default body stops compiling, so the trait-body error and its help must explain that `Self` is abstract there.
>
> ## G2-Q2, if G2-Q1 = Alias
> **Vote:** NewCode-all
> **Reasoning:** Under Alias this is the only place a `Self` value-path error fires, and it marks a real mistake with a real fix: "declare `fn make() -> Self` in the trait and call `Self.make()`". One dedicated code can carry that help for build forms and patterns alike. E0547, E0300 and E0525 describe a symptom ("no variant", "no field") and point the user the wrong way.
> **Concern:** The code's name and message must say "in a trait default body", so no one reads it as a ban on `Self` in impls.
>
> ## G2-Q2, if G2-Q1 = TypeParam
> **Vote:** NewCode-all
> **Reasoning:** Under TypeParam, the same refusal in an impl and in a trait must have the same code, or users meet two codes for one rule. The help differs per body: in an impl it writes the type name; in a trait it says to add a trait fn and call `Self.f()`.
> **Concern:** The impl-side help must be machine-applicable on every form, or the frequent hits become pure friction.

- **PLT:**

> # PLT, Phase D re-vote
>
> ## G2-Q1
> **Vote:** Alias
> **Reasoning:** In an impl body, `Self` is the target type in every type position. Making value and pattern heads agree with that gives one meaning per body. In a trait, `Self` is abstract and follows the rule every `T` follows, so neither body adds an exception. sys says "one rule for two bodies", but the two bodies differ in fact: one has a known type and one does not. Alias states that fact, and TypeParam hides it only in value position. As web and I noted, TypeParam also bans patterns, which no earlier vote did, so it does not simply keep DECISIONS.md:166.
> **Concern:** aiml's corpus point is real. lib/std and the docs should pick one spelling by convention (I suggest the type name), so the training corpus does not mix forms.
>
> ## G2-Q2, if G2-Q1 = Alias
> **Vote:** TCodes
> **Reasoning:** In a default body, `Self` is a type parameter, so each form gets the code it gets on `T`, and no code names `Self` alone. A new code that fires only for `Self` in trait bodies would make `Self` differ from `T` in the one place where the two are the same thing. The help on E0547 / E0300 / E0525 can still name the guarantee-set route (declare `fn make() -> Self`, call `Self.make()`) for a `Self` head, which covers web's moved-code concern without a new code.
> **Concern:** The label-less `Self {}` / `T {}` hole stays open until its separate fix lands.
>
> ## G2-Q2, if G2-Q1 = TypeParam
> **Vote:** NewCode-all
> **Reasoning:** Under TypeParam, a Self-headed pattern in an impl is SelfNotConstructor. So a default body should give the same code for the same text, and the rule "Self heads a static call and nothing else" stays one rule with one code. NewCode-build would give a Self pattern two different codes depending on the body, which is the inconsistency TypeParam exists to avoid. I change from my Phase C conditional (NewCode-build) for this reason.
> **Concern:** The default-body help cannot write a concrete name, so it must name the guarantee-set route, or the error gives no fix.

- **DevOps:**

> # devops, Phase D re-vote
>
> ## G2-Q1
> **Vote:** Alias
> **Reasoning:** Each TypeParam form gets a machine-applicable fix that rewrites the code to the same program, and an error like that adds cost and no safety: a failed check, an edit and a re-run on code that was correct. plt's `Self.parse` case shows that TypeParam in an impl is not one model with the trait body. It is the alias with two refusals cut out, and its rule text would still have to rule on calls through the concrete type. aiml's corpus point (one spelling) is real, but a lint or `blink fmt` can keep lib/std and tests to one spelling without failing user code that is correct. Alias needs no new code in impls, and every refused form reuses the code and help the type name already gets.
> **Concern:** Code moved from an impl into a trait default body stops compiling, so the trait-body error (G2-Q2) must say that `Self` is abstract there and name the fix.
>
> ## G2-Q2, if G2-Q1 = Alias
> **Vote:** NewCode-all
> **Reasoning:** A trait default body is the one place a `Self` build or match is a real fault, and a dedicated code can give the right help ("`Self` is abstract here; add a trait fn and call `Self.f()`"). E0300, E0308 and E0525 give the wrong fix for `Self.Red` or `Self { x: 0 }`, and TCodes leaves the label-less `Self {}` with no code. One code for build forms and patterns keeps the help the same for the code a user moves from an impl.
> **Concern:** The code's name and message must say "abstract `Self` in a trait default body", or users will read it as a ban on `Self` in impls.
>
> ## G2-Q2, if G2-Q1 = TypeParam
> **Vote:** NewCode-all
> **Reasoning:** The same code then covers the same form in both bodies, and only the help changes (write the type name in an impl; add a trait fn in a trait). Splitting patterns off to E0300 would give one form two codes, depending on the body it sits in.
> **Concern:** The help must be machine-applicable on every impl form, or the frequent hits that every TypeParam voter predicted become friction.

- **AI/ML:**

> # aiml, Phase D re-vote
>
> ## G2-Q1
> **Vote:** Alias (changed from TypeParam)
> **Reasoning:** plt's `Self.parse("red")` case breaks my main argument. Under TypeParam that call compiles through the concrete type, because a type parameter cannot reach `parse`. So a static call already works in an impl and fails in a trait default body. "Same text, same verdict in both bodies" was never true of TypeParam: it is the alias with build and match cut out. That leaves my corpus argument (one spelling) against a cost that every TypeParam voter, me included, expects to fire often on correct code. web's rule, "a known type has a shape and an abstract one does not", is the rule a model already applies to `T`, so Alias adds nothing new to learn.
> **Concern:** Blink code will mix `Self.Rgb(n)` and `Color.Rgb(n)`, and models trained on it will write `Self.V` in trait default bodies more often, so the G2-Q2 help must be exact.
>
> ## G2-Q2
> **Vote if G2-Q1 = Alias:** NewCode-all
> **Vote if G2-Q1 = TypeParam:** NewCode-all
> **Reasoning:** Under Alias, the default body is the one place where a `Self` value form is a real mistake. The error must name `Self` and say "`Self` is abstract here; declare `fn make() -> Self` and call `Self.make()`". TCodes give E0547 "no such variant" for `Self.Red`, which tells a model to add a variant or fix a spelling, and E0300 or E0525, which point away from `Self`. NewCode-build splits patterns from build forms for no gain.
> **Concern:** Under Alias the new code fires only in trait default bodies, so its text must also say why the same form compiles in an impl, or a model will think the impl form is wrong too.

- **Minimalism:**

> # min, Phase D re-vote
>
> ## G2-Q1
> **Vote:** Alias
> **Reasoning:** Alias is the smallest language: no new code, no help per form, no quick fix, and one paragraph deleted. web and plt also show that TypeParam is not the conservative reading. It bans patterns that no vote ever covered and that run today. So both options are new rulings, and on merit Alias has no exceptions inside an impl. aiml's corpus argument (one spelling) is a style goal, which `blink fmt` or a lint can serve without refusing correct code.
> **Concern:** Code moved from an impl into a trait default body stops compiling, so the trait-body errors must say that `Self` is abstract there.
>
> ## G2-Q2
> **Vote (if G2-Q1 = Alias):** TCodes
> **Vote (if G2-Q1 = TypeParam):** NewCode-all
> **Reasoning:** Under Alias, `Self` in a default body is a type parameter, and every form already has the code it gets on `T`. A new code that fires only there would be a second name for errors the spec already has. Under TypeParam, one code for each form in both bodies keeps the rule to one sentence.
> **Concern:** Under TCodes, the E0547/E0300/E0525 helps must name `Self` as abstract and point to a trait fn and `Self.f()`, or the user moving code from an impl gets a bare "no variant" message.


| Question | Sys | Web | PLT | DevOps | AI/ML | Min | Result |
|----------|-----|-----|-----|--------|-------|-----|--------|
| Q1. Impl body | Alias | Alias | Alias | Alias | Alias | Alias | Alias, 6-0 |
| Q2, if Q1 = Alias | NewCode-all | NewCode-all | TCodes | NewCode-all | NewCode-all | TCodes | NewCode-all, 4-2 |
| Q2, if Q1 = TypeParam | NewCode-all | NewCode-all | NewCode-all | NewCode-all | NewCode-all | NewCode-all | NewCode-all, 6-0 (moot) |

Q1 is `Alias`, so the "if Q1 = TypeParam" re-votes are moot. They are recorded here. PLT changed its `TypeParam` conditional from `NewCode-build` (Phase C) to `NewCode-all` (Phase D). Q2 is `NewCode-all` under the result that won.

#### Concerns and notes the writer carried into the spec

- **PLT, AI/ML** (Q1 concern): the spec text and the corpus can contain both spellings. `lib/std` and the docs should pick one spelling by convention. This is implementation and documentation work. The spec carries no style rule: both spellings are legal and mean the same.
- **Systems** (Q1 concern, from Phase C): the old `SelfNotConstructor` text in §3.6 must go in the same change as the reversal. The commit removes the paragraph and its sample.
- **Systems** (Q2 concern): the same form on a plain type parameter `T` gets E0547, E0300 or E0525. The help on those codes should not contradict the help of E0570. This is a note for the compiler work. The spec fixes only E0570.
- **Web, DevOps, AI/ML** (Q2 concern, naming): the code name and the label must say "in a trait default body", so that nobody reads the code as a ban in impls. The code is `SelfShapeInDefaultBody`. The label says `Self` is abstract in a trait default body. A `note:` says the same form compiles in an impl body.
- **PLT, Minimalism** (Q2 dissent for `TCodes`): in a default body `Self` is a type parameter, so each form could get the code that `T` gets and no code would name `Self` alone. The label-less `Self {}` / `T {}` hole in that route closes separately.

## Final Spec

The rules are in `sections/03_types.md`, §3.6 *`Self` as the head of a value path or a pattern*. The `SelfNotConstructor` paragraph and its sample are removed. `ERROR_CATALOG.md` has the new row E0570 `SelfShapeInDefaultBody`, and the E0305 row names the static-call case. The DECISIONS.md row `Self` as constructor is marked reversed.

```blink
type Color {
    Red
    Rgb(Int)
}

type Point {
    x: Int
    y: Int
}

trait Mk {
    fn make(n: Int) -> Self
    fn origin() -> Self { Self.Red }    // E0570: `Self` is abstract in a trait default body
}

impl Mk for Color {
    fn make(n: Int) -> Self {
        if n == 0 { Self.Red } else { Self.Rgb(n) }   // OK: the same as Color.Red and Color.Rgb(n)
    }
}

impl Point {
    fn swap(self) -> Self {
        let Self { x, y } = self                      // OK: the same as Point { x, y }
        Self { x: y, y: x }                           // OK: the same as Point { x: y, y: x }
    }
}
```

Locked points, one line each:

- In an impl body, `Self` is the target type in every position.
- `Self.V` and `Self.V(..)` build a variant, as `Color.V` and `Color.V(..)` do.
- `Self { x: 1, y: 2 }` builds the struct, as `Point { x: 1, y: 2 }` does.
- `Self(..)` compiles where `Point(..)` compiles, and gives the code that `Point(..)` gives where it fails.
- `Self.f(..)` calls a type-scoped fn of the target type. It needs no trait.
- The patterns `Self.V`, `Self.V(..)` and `Self { x, y }` match as the type name does.
- A form the type name refuses gets the type name's code: `Self.Blue` on `Color` with no `Blue` is E0547.
- In a trait default body, every build form and every `Self`-headed pattern is E0570 `SelfShapeInDefaultBody`: `Self.V`, `Self.V(..)`, `Self { .. }` with labels or none, `Self(..)`, and the patterns `Self.V`, `Self.V(..)`, `Self { x }`.
- The E0570 label: "`Self` is abstract in a trait default body; it has no fields or variants to build or match". The help: "declare `fn make() -> Self` in the trait and call `Self.make()`". A note says the same form compiles in an impl body.
- `Self.f()` in a default body is legal when `f` is in the guarantee set, and E0305 when it is not.
- `Self` outside a trait or impl is E0569, unchanged.
- The spec has no style rule on which spelling `lib/std` and the docs use.
