[< All Decisions](../DECISIONS.md)

# Associated Function Qualified Call — Design Rationale

The question: two traits declare an associated function with the same name (no `self`) for one type, for example `trait Alpha { fn make() -> Self }` and `trait Beta { fn make() -> Self }`, both implemented for `Widget`. `Widget.make()` is `AmbiguousMethodCall` (E0522). The qualified form `Trait.method(receiver, args)` gets `Self` from its receiver, so `Alpha.make()` has no way to name `Widget` and is refused. Blink had no form that names both the trait and the type, so the only fixes were to rename a method or drop an impl.

Panelist text below is verbatim. Local tracker IDs are replaced by bracketed descriptions.

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in independent-proposal → debate → vote rounds. Phase A gave six distinct forms, so Phase B ran. All six signalled "stable, ready to vote" after one round. Every question passed 6-0 except Q5 (5-1), so Phase D did not run.

#### Phase A — Independent proposals

**Systems:**

> **Systems panelist — Phase A proposal ([the spec ticket])**
>
> Framing: every candidate spelling compiles to the same thing: one direct C call to one monomorphized impl symbol, with no vtable and no runtime dispatch. The real question is which spelling names the **mono key** (trait instance, Self type) most directly. Typecheck must fix that key with no later lookup by name (the spec already requires this). I want the syntax to *be* the key.
>
> ### Proposal 1 (preferred): impl-qualified call `(Trait for Type).method(args)`
>
> The call site repeats the impl header. The header is the identity of the code that runs.
>
> ```blink
> fn main() {
>     let a = (Alpha for Widget).make()
>     let b = (Beta for Widget).make()
>     let _keep = a.v + b.v
> }
>
> // generic trait: the trait instance is explicit
> let w = (From[U8] for Widget).from(byte)
>
> // type parameter: same form, T is the Self slot
> fn build[T: Alpha + Beta]() -> T {
>     (Alpha for T).make()
> }
>
> // works for receiver methods too, but adds nothing over Display.display(u)
> (Display for User).display(u)
> ```
>
> Rules:
> - `(Trait for Type)` is valid only as the callee prefix of a method call. It is not a value. A type checker still has a first-class type, and `Self` stays a type-position alias.
> - `Type` must implement `Trait`. If not, the error is the same E-code as a missing impl at a bound.
> - The existing `Trait.method(receiver, args)` form stays as it is. For receiver methods it is shorter, and the receiver already supplies Self.
>
> E0522 help for an associated function:
> ```
> = help: name the impl to call:
>   |   (Alpha for Widget).make()
>   |   (Beta for Widget).make()
> ```
> For a receiver method the help keeps today's `Alpha.method(w)` hint.
>
> Tradeoffs (systems):
> - + 1:1 with the mono key and with the `impl Alpha for Widget` block, so a reader can grep the call to the impl. Monomorphization needs no inference step, and the C symbol is visible in the source.
> - + It parses without ambiguity. `(` Ident … `for` cannot start any other expression, because `for` never follows an expression.
> - + It covers generic traits (`From[U8]` vs `From[Char]` on one type) with no extra rule.
> - − Parens plus a keyword make it the noisiest option. That is acceptable: it appears only where an ambiguity error forced it.
> - − It is a second qualified-call form. Mitigation: the diagnostic picks the form for the user.
>
> ### Proposal 2 (fallback): Self as explicit type application `Alpha.make[Widget]()`
>
> This reuses §3.4 Explicit Type Application. A qualified associated call takes Self as its first bracket argument: `Alpha.make[Widget]()`, `Alpha.make[T]()`, `From[U8].from[Widget](b)`.
>
> Tradeoffs: it adds no new syntax, and it matches how mono actually treats Self (as a leading type parameter). But it overloads the bracket list. For a trait method that has its own type parameters, the list becomes `Codec.decode[Widget, A]`, with Self in position 0 and the method's parameters after it. Readers will misread that. Brackets after a callee mean "this function's type parameters" everywhere else, so I rank this second.
>
> ### Rejected
> - `Widget.Alpha.make()`: collides with enum variant access. If `Color` has a variant `Alpha`, `Color.Alpha.make()` already means a method call on the value `Color.Alpha`. That is a real parse/resolve ambiguity.
> - `(Widget as Alpha).make()`: in Blink, `as` binds names (`import … as`, `with … as`). Using it here would read as a cast, which Blink does not have.
> - Inferring Self from the expected type (`let w: Widget = Alpha.make()`): it is deterministic and safe, because a new impl cannot change it, but it only works when Self appears in the return type. `fn count() -> Int` gets nothing from it. YAGNI. Revisit it later as a convenience on top of an explicit form, not as a replacement.
> - Do nothing / rename: not acceptable. Renaming is impossible when both traits come from third-party packages, and the spec promises that a new impl causes only loud, *fixable* errors. Today the error has no fix at the call site.
>
> ### Cross-language
> - Rust `<Widget as Alpha>::make()` names the same pair. Proposal 1 is that pair in Blink's existing `impl X for Y` word order, with no turbofish.
> - C++ and Zig avoid the problem through namespacing or explicit function pointers. Neither has trait coherence, so they offer no useful precedent.
> - Swift has no spelling for this case at all. Ambiguous protocol static requirements there need a wrapper, and that is the failure we should not copy.
>
> Bottom line: Proposal 1. Zero runtime cost, the call names the exact impl that runs, it is unambiguous, and the existing qualified form does not change.

**Web/Scripting:**

> Web/Scripting panelist, Phase A proposal for [the spec ticket]: add the form `(Type as Trait).fn()`.
>
> ## Proposal 1 (recommended): `(Type as Trait).fn(args)`
>
> ```blink
> trait Alpha { fn make() -> Self }
> trait Beta { fn make() -> Self }
> type Widget { v: Int }
> impl Alpha for Widget { fn make() -> Self { Widget { v: 1 } } }
> impl Beta for Widget { fn make() -> Self { Widget { v: 2 } } }
>
> fn main() {
>     let a = (Widget as Alpha).make()     // v == 1
>     let b = (Widget as Beta).make()      // v == 2
> }
>
> // type parameter
> fn build[T: Alpha + Beta]() -> T {
>     (T as Alpha).make()
> }
>
> // generic trait
> type Code { n: Int }
> impl From[U8] for Code { fn from(value: U8) -> Self { Code { n: value.to_int() } } }
> impl From[Char] for Code { fn from(value: Char) -> Self { Code { n: 0 } } }
> let c = (Code as From[U8]).from(b)
> ```
>
> Rules:
> - `(X as Tr)` is legal only as the head of a `.fn()` call. X is a type (a concrete type or a type parameter in scope) and Tr is a trait, with type arguments if it has any. It is not an expression and not a value.
> - It selects exactly one impl. If X does not implement Tr, report E0306/TraitBoundNotSatisfied at the parens.
> - A value in place of X, as in `(w as Alpha)`, is an error with the help "`as` names a type, not a value; to call a method on `w`, write `Alpha.method(w)`".
> - The receiver form `Trait.method(x)` stays as it is. Do not make the `as` form also accept self-methods (`(Config as Serializable).serialize(c)`). That gives two spellings for one job.
>
> E0522 help when the callee is an associated function:
> ```
> = help: name the type and the trait together:
>   |   (Widget as Alpha).make()
>   |   (Widget as Beta).make()
> ```
> For a self-method the help stays the current `Alpha.method(x)`. The compiler picks the form, so the user never has to know two rules. They copy the line.
>
> Tradeoffs from my seat:
> - A Python, JS or Kotlin dev reads "Widget as Alpha" aloud and understands it on first sight. The parens show the grouping: "this Widget, viewed as an Alpha". It needs no new sigil, no `::`, no `<>`, and it reuses a keyword Blink already has (`import x as y`, `with x as name`).
> - Risk: TypeScript devs know `as` as an unchecked cast. Here it is checked, applies to types only, and appears only in call-head position, which is narrow enough that the wrong reading fails loudly. Blink has no value-cast `as` (I found none in sections/), so nothing else competes for the meaning. I expect one FAQ entry, not a stream of Stack Overflow questions.
> - It is the same mental model as Rust's `<Widget as Alpha>::make()` without the angle brackets or `::`. People coming from Rust map it in two seconds.
> - Rare case, rare syntax. A long spelling is fine because the 90% path (`Widget.make()`) is untouched.
>
> ## Alternatives I considered and reject
>
> - `Alpha.make[Widget]()`: this overloads explicit type application. §3.6 says impl selection admits no type-argument list, and the form collides with methods that have their own binders (`From[U8].from[Code](b)`: which bracket is which?). Expect many questions.
> - `Widget.Alpha.make()`: reads like module or field access. Readers will look for a field named `Alpha`.
> - Expected-type inference (`let w: Widget = Alpha.make()`): Rust allows this and it feels nice, but it works only when Self is in the return type. `fn describe() -> Str` would still need another form, so we would teach two mechanisms. It also makes the code mean something different when someone deletes an annotation. Leave it out for now (YAGNI). It can be added later without conflict.
> - Rename-only / do nothing: I reject it. Two third-party libraries can declare `make` / `default` / `new`, and the user owns neither. "Rename one" is not available to them, so the language must give them a spelling.
>
> ## Cross-language note
> - Rust: `<T as Trait>::f()`. Same semantics.
> - Kotlin: `super<Alpha>.f()`. It names the interface in the call, but only for super-calls.
> - Swift: has no way to disambiguate, and its users complain about that. We should not copy it.
> - TypeScript: `x as T` is a cast. This is the one place where a learner's prior knowledge could mislead, and the value-position error message covers it.

**PLT:**

> ## PLT proposal: name the impl at the call site
>
> **The typing issue.** An associated function of trait `Tr` has the type `∀Self. Tr[σ̄] Self ⇒ sig`. A call has to fix both the trait (and its arguments σ̄) and `Self`. The receiver form `Tr.m(x, …)` works only because `Self` sits in the first parameter, so it gets solved from `x`. When `Self` is not in a parameter, nothing at the call site fixes it. The gap is a missing binder supply, not a missing lookup rule. So the fix must let the program write `Self` itself. Choosing an impl because "only one impl exists" breaks modularity, and the ticket is right to reject it.
>
> ### Proposal A (primary): an impl-selector head, `(Tr for τ)`
>
> ```blink
> fn main() {
>     let a = (Alpha for Widget).make()
>     let b = (Beta for Widget).make()
> }
>
> fn pick[T: Alpha + Beta]() -> T {
>     (Alpha for T).make()
> }
>
> fn widen(byte: U8) -> Widget {
>     (From[U8] for Widget).from(byte)
> }
>
> (Serializable for Config).serialize(c)   // also valid on receiver methods
> ```
>
> **Typing rule.** If τ is a type in Γ, τ satisfies `Tr[σ̄]` (by an impl or by a bound in scope), and m is a method of `Tr`, then `(Tr[σ̄] for τ).m` has type `sig_m[Self := τ, params := σ̄]`. If τ does not satisfy `Tr[σ̄]`, the call is E0306 TraitBoundNotSatisfied at the head.
>
> Why I want this spelling:
> - **It repeats the impl header.** `impl Alpha for Widget` declares the impl and `(Alpha for Widget)` selects it, so a reader sees which impl runs without learning anything new.
> - **It composes.** It names the whole witness (τ, Tr, σ̄) at once, so generic traits (`From[U8]` and `From[Char]` on one type), type parameters and sealed traits (`(StrOps for Str).trim(s)`) all work the same way.
> - **No binder collisions.** Putting `Self` in the method's type-argument list (`Alpha.make[Widget]()`, the Haskell `@Widget` style) breaks E0303's rule that a callee's list holds only its own binders. Its position would also clash with method binders (`Tr.decode[Widget, A]`) and with trait arguments (`From[U8]`). I reject it.
> - **No term/type mixing.** I also reject `Alpha.make(Widget)`, because it passes a type as a value argument.
> - **Narrow grammar.** The form is valid only as a callee head, never in a type position (YAGNI). `for` cannot appear in the middle of an expression today, so `(Ident[…] for Type)` inside parentheses is unambiguous.
> - **Fixed at type check, as before.** Resolution stays at type check: one trait per call, and mono gets a concrete or bound-dictionary witness. Adding a new impl elsewhere cannot change what this call means, because it states both coordinates.
>
> **Fallback spelling:** `(Widget as Alpha).make()`, which matches Rust's `<Widget as Alpha>::make()`. It is equally sound. I rank it second for two reasons:
> - `as` already does two other jobs in Blink: aliasing in imports and binding in `with`.
> - Readers from TypeScript, Rust or Kotlin read `x as T` as a cast. Blink has no casts and does conversions through `From`, so that reading would be wrong.
>
> ### Proposal B (secondary, separable): solve `Self` in the qualified call by ordinary inference
>
> Treat `Tr.m(args)` as instantiating `Self` (and σ̄) as metavariables. Ordinary unification then solves them from the arguments and the expected type, exactly like any generic function:
>
> ```blink
> let w: Widget = Alpha.make()   // Self := Widget from the expected type
> let n = Alpha.make()           // error[CannotInferType] E0301, help: (Alpha for Widget).make()
> ```
>
> - **It extends the current form without changing it.** Today's "receiver as first argument" form becomes the case where argument 1 fixes `Self`, so every program that compiles today keeps its meaning.
> - **It stays modular.** Unification is local, so a new impl elsewhere cannot change the result. This is not the global "only one impl" rule the ticket rejects.
> - **It cannot be the only fix.** It fails when `Self` occurs in neither the parameters nor the return type. Haskell needed AllowAmbiguousTypes plus TypeApplications for exactly that case. A is therefore required and B is optional.
> - **The cost is readability.** Which impl runs depends on an annotation that may be far from the call. I support B only together with A, and I will not fight for it.
>
> ### E0522 help text (under A)
>
> ```
> error[AmbiguousMethodCall]: ambiguous call `Widget.make()`
>   = note: `make` is defined in both `Alpha` and `Beta` for `Widget`
>   = help: name the impl to call:
>   |   (Alpha for Widget).make()
>   |   (Beta for Widget).make()
> ```
>
> For a receiver method, the hint keeps the shorter existing form `Serializable.serialize(c)`. For a type parameter it prints `(Alpha for T).make()`. Rename stays in the explain text as a second option, not as the main fix.
>
> ### Cross-language notes
> - **Rust:** `<T as Tr>::m` is the same witness-naming idea.
> - **Haskell:** `make @Widget` with TypeApplications works only because a class has a single parameter. Blink's generic traits make the positional version ambiguous.
> - **OCaml modules / Scala given instances:** selecting a witness explicitly is the standard, sound answer.
> - **Koka:** it avoids the problem with overloading by qualified name, which Blink's "every method belongs to a trait" rule rules out.
>
> ### Vote position
> - I vote A with the `for` spelling, and B only as an add-on.
> - "Do nothing / rename" is a sound position but an incomplete one: the generic case `T: Alpha + Beta` cannot be renamed away when both traits come from libraries the user does not own.

**DevOps:**

> ## DevOps/Tooling panelist: Phase A proposal for [the spec ticket]
>
> ### What I judge on
>
> A fix earns its place by what it does to E0522. Today the help line for an ambiguous associated function says "rename or drop an impl", which is not a fix. I want help text the user can paste, a quick-fix the LSP can apply, and one canonical form that `blink fmt` never has to choose between.
>
> ### Proposal 1 (recommended): `(Type as Trait).method(args)`
>
> This form names both the type and the trait at the call site, as Rust does, and spells it with Blink's `.` and `[ ]`.
>
> ```blink
> fn main() {
>     let a = (Widget as Alpha).make()
>     let b = (Widget as Beta).make()
>     let n = (Widget as From[U8]).from(byte)
> }
>
> fn build[T: Alpha + Beta]() -> T {
>     (T as Alpha).make()
> }
> ```
>
> Rules:
> - The left side of `as` is a type: a concrete type, a type parameter, or an applied generic such as `List[Int]`. The right side is a trait the type implements, with its type arguments.
> - The parenthesized form is valid only as a callee prefix: it must be followed by `.method(`. Written as a bare value, it fails with one targeted message: "`(Widget as Alpha)` names an impl, not a value."
> - The receiver form stays as it is: `Serializable.serialize(c)`. The new form also accepts methods that take `self` (`(Config as Serializable).serialize(c)`), so the rule is uniform and generated code has one form that always works. E0522 help always suggests the shortest form that fixes the call, and fmt never rewrites one form into the other.
>
> E0522 under this proposal:
> ```
> error[AmbiguousMethodCall]: ambiguous method call
>  --> main.bl:14:13
>    |
> 14 |     let w = Widget.make()
>    |                    ^^^^ `make` is declared by both `Alpha` and `Beta` for `Widget`
>    |
>    = help: name the trait:
>    |   (Widget as Alpha).make()
>    |   (Widget as Beta).make()
> ```
> For the generic case the help prints `(T as Alpha).make()` with the parameter's own name. For a receiver call the help stays `Serializable.serialize(c)`.
>
> Tooling surface:
> - **LSP completion:** after `(Widget as `, the LSP lists exactly the traits Widget implements, a small and correct set. After `).`, it lists only that trait's methods.
> - **Go-to-definition:** it jumps to the impl's method body, not to the trait declaration. Today a qualified call cannot give you that, because the trait alone does not pick an impl.
> - **Code action:** each E0522 help line becomes one quick-fix. It is a mechanical edit: wrap the type, insert `as Trait`.
> - **fmt:** one canonical spacing, `(T as Trait)`. Nothing is left to the user's taste.
> - **Bonus:** `as` in expression position gives us a parse site for the most common newcomer error. When a user writes `x as Int` expecting a cast, they get a pointed error ("Blink has no `as` cast; use `x.to_int()` or `Int.from(x)`") instead of a generic parse failure. That is a real gain in diagnostics.
>
> Costs:
> - `as` takes a third role, after `import ... as` and `with ... as`. All three roles keep one meaning: "this thing, seen as that name". I can live with that.
> - Rust users may read `(w as Alpha)` with a value on the left as a cast. It is a compile error with a direct fix ("use `Alpha.method(w)`"), not a silent behavior.
> - The parser needs a new parenthesized-type form in expression position. The `as` token cannot start or continue any expression today, so it is unambiguous.
>
> Cross-language: Rust has `<Widget as Alpha>::make()`, which is the same idea with different punctuation. C# needs a cast for explicit interface members (`((IAlpha)w).Make()`), and its error messages for the static case are notoriously poor. Haskell uses a type annotation, which fails when the return type is not `Self`.
>
> ### Proposals I reject, and why (diagnostic view)
>
> - **`Widget.Alpha.make()`**: completion after `Widget.` would mix trait names with methods, which is noisy. It also reads as if `Alpha` is nested in `Widget`, which blocks any future nested or associated type names.
> - **`Alpha.make[Widget]()`**: it collides with the method's own type parameters, and the error "expected 0 type arguments" would mislead.
> - **`Alpha[Widget].make()`**: it collides with generic traits. `From[U8][Widget]` is unreadable, and its errors would be worse.
> - **Infer `Self` from the binding (`let w: Widget = Alpha.make()`)**: it fails for `Alpha.make().v` and for associated functions that do not return `Self`. We would still need an explicit form, so it adds a second mechanism without removing the first. YAGNI. Reconsider later if users ask for it.
> - **Do nothing / rename**: this is not acceptable from a tooling view. A third-party trait can collide with yours, and you cannot rename code you do not own. A diagnostic that offers no fix is a support ticket.
>
> ### Summary
>
> Adopt `(Type as Trait).method(args)` as the general qualified form. Keep `Trait.method(receiver)` unchanged. Make E0522 print one pasteable line per candidate, and make each line an LSP quick-fix.

**AI/ML:**

> ## AI/ML panelist: Phase A proposal
>
> ### Proposal 1 (recommended): treat `Self` in a qualified call as an ordinary type variable
>
> Keep `Trait.method(args)` as the only qualified form. Drop the rule that the first argument is a receiver. In a qualified call, `Self` is a type variable like any other. Inference fixes it from the arguments or from the expected type, the same way it fixes any binder (§3.4). When nothing fixes it, the call is E0301 CannotInferType, reported at the `let` like every other under-determined type (8vcj2c).
>
> ```blink
> fn main() {
>     let w: Widget = Alpha.make()
>     let _keep = w.v
> }
>
> fn f[T: Alpha + Beta]() -> T {
>     Alpha.make()
> }
>
> fn g[T: Alpha + Beta]() -> Int {
>     let t: T = Beta.make()
>     use_it(t)
> }
>
> fn widen[T: From[U8]](byte: U8) -> T { From.from(byte) }
> ```
>
> In the `From` case, the argument fixes `From[U8]` and the return type fixes `Self = T`.
>
> The receiver form does not change. `Display.display(user)` still works, because the first argument's type is `Self`, so it fixes the type variable. Today's special rule, "expects the receiver as its first argument", becomes one case of the general rule.
>
> E0522 help under this proposal:
>
> ```
> = help: name the trait, and give the result a type so `Self` is known:
>   |   let w: Widget = Alpha.make()
>   |   let w: Widget = Beta.make()
> ```
>
> For a method with a receiver, the existing help (`Alpha.m(x)`) stays.
>
> If the call has no expected type, for example `Alpha.make().v`:
>
> ```
> error[CannotInferType]: cannot infer `Self` for `Alpha.make()`
>   = help: bind the result with a type: `let w: Widget = Alpha.make()`
> ```
>
> **Why this is right for my domain:**
> - **No new syntax and no new decision points.** An AI that knows `let x: T = ...` and `Trait.method(...)` already knows how to write the fix. Nothing new has to be learned from the spec.
> - **It matches what models have already seen.** Rust allows `let w: Widget = Alpha::make();` and `Default::default()` with an ascribed type. That is the most common way the pattern appears in training data, and copying it into Blink only needs `::` changed to `.`. Haskell's `mempty :: T` and Swift's `let x: T = .init()` follow the same idea: the expected type picks the impl.
> - **Low token cost.** The fix adds `: Widget` (2–3 tokens) at the binding, which usually exists already. Rust's `<Widget as Alpha>::make()` costs about 8 tokens and needs punctuation that Blink has nowhere else.
> - **Stable.** Inference uses only local type information and never counts impls, so a new impl elsewhere cannot change or break the call. Coherence stays loud-only.
> - **The diagnostic is learnable.** E0522 and E0301 each give one repair, and both repairs are edits to code the model already wrote.
>
> **Tradeoffs:**
> - `Self` is fixed by the context the call sits in, not at the call itself. A reader has to look at the `let` or the return type, which is a little more distance than Rust's turbofish-style form.
> - Blink has no expression-level type ascription, so a chained use (`Alpha.make().v`) needs an extra `let`. I accept that. It is rare, the error says exactly what to do, and adding expression ascription would be a second mechanism for the same thing.
> - The 5-0 decision fixed the receiver-first wording in §3c.4. This proposal generalizes that wording but does not reverse it: every program that compiles today still means the same thing.
>
> ### Alternatives I reject (with reasons from my domain)
>
> - **`Widget.Alpha.make()`**: Blink reads `X.Y` as module, type, or member access. A trait used as a path segment is a new form that no model would guess. It also makes `Widget.Alpha` look like a nested type.
> - **`(Widget as Alpha).make()` or `<Widget as Alpha>.make()`**: `as` would get a third meaning, in expression position, alongside `import ... as` and `with ... as`. Models would then also guess `x as Int` casts. That adds decision points and causes wrong-syntax mistakes.
> - **`Alpha.make[Widget]()`**: this clashes with explicit type application (§3.4). `[...]` after a method names the method's own type parameters. With `From[U8].from` and a generic method, the reader and the model cannot tell which binder each bracket fills.
> - **"Rename is the answer"**: often you cannot rename. Both traits may come from other packages, and `From[U8]` with `From[Char]` hits the same gap in generic code. A gap with no spelling at all hurts AI accuracy, because the model keeps retrying spellings that do not exist.
>
> ### Optional secondary item (only if the panel wants a form at the call site)
>
> If other panelists insist that `Self` must be named at the call site, I prefer explicit type application on the trait head, `Alpha[Self = Widget].make()`, over any new punctuation. I rank it second because it creates a second way to do the same thing, and every second way is a decision point that a model gets wrong some of the time.
>
> **My vote leans to Proposal 1:** one rule (`Self` is inferred like any binder), no new syntax, and repairs that reuse E0301.

**Minimalism:**

> Minimalism Phase A proposal ([the spec ticket]): add one path-shaped form, Type.Trait.method(args). No new token, no keyword, no Self-inference trick.
>
> ## Is this foundational? Yes. I vote to close it.
> "Rename" only works if you own one of the traits. Take two library traits that both declare `fn make() -> Self`, and a user type that must meet both bounds (it goes to lib A and to lib B). That program has no correct spelling today. The same holds for `fn f[T: Alpha + Beta]() -> T`. Here the language itself cannot say it, so a convention cannot fix it. Do-nothing is out.
>
> ## Proposal 1 (recommended): Type.Trait.method(args)
> ```blink
> fn main() {
>     let a = Widget.Alpha.make()      // Self = Widget, trait = Alpha
>     let b = Widget.Beta.make()
> }
>
> fn pair[T: Alpha + Beta]() -> (T, T) {
>     (T.Alpha.make(), T.Beta.make())
> }
>
> // generic trait: the trait's own type args stay in brackets
> let w = Widget.From[U8].from(byte)   // rarely needed: arg types already pick the impl
> ```
> Rule (one sentence for the spec): "`Type.Trait.method(args)` calls `Trait`'s `method` from `Type`'s impl of `Trait`. The args are exactly the declared parameters. `Type` must implement `Trait` (for a type parameter, through its bounds)."
>
> Why this shape:
> - It reuses what exists. `.` is already Blink's only path separator, and `Type.method()` is already how you call an associated function. We add one segment, not a new grammar (`<T as Tr>::`, `as`, a new bracket meaning).
> - Both names sit at the call site, so nothing depends on how many impls exist. That kills the "a new impl elsewhere breaks this call" failure.
> - `Widget.Alpha` cannot collide with anything. A type has no static fields, function names are lowercase, and `mod.Widget.Alpha.make()` still reads left to right.
> - The receiver form falls out of it (`Config.Serializable.serialize(c)` is legal under the same rule). I do NOT propose to promote or lint it. `Trait.method(recv)` (5-0) stays the documented form for methods. One rule, no special case.
>
> E0522 help under P1:
> ```
> = help: name the type and the trait:
> |   Widget.Alpha.make()
> |   Widget.Beta.make()
> ```
> For a call with a receiver, the help keeps today's `Alpha.method(x)` text unchanged.
>
> ## Proposal 2 (rejected by me, listed so the panel can reject it with eyes open): infer Self from the expected type
> `let w: Widget = Alpha.make()` would solve Self like any other type parameter the signature supplies (§3.4). It needs zero syntax. Still, I vote against it:
> - It is partial. A Self-free associated fn (`fn default_port() -> Int`) has no source for Self, so we would still need P1, and then we have two mechanisms.
> - It moves the type to a distant binding, so the call site alone does not say which impl runs. That is worse for readers and for LLM generation.
> - If we later want Self inference anyway, P1 does not block it.
>
> ## Proposal 3 (rejected): `Alpha.make[Widget]()`
> It overloads explicit type application. Self would become a hidden first bracket argument, which collides with a method's own type params (`Codec.decode[Widget, Foo]` — which slot is which?) and with generic traits (`From[U8].from[Widget]`?). That is new positional magic, the opposite of minimal.
>
> ## Interaction cost of P1 (what we must say in spec)
> 1. Parse: `Path.Ident.Ident(args)` with an optional `[TypeArgs]` on the trait segment. The parser needs no lookahead beyond what `mod.Type.fn()` already needs, since name resolution decides Type vs module.
> 2. Typecheck: the existing resolver, with owner set to {Trait} and Self set to Type. No lookup by name at mono, which matches the current rule.
> 3. Errors: `Type` does not implement `Trait` → the existing missing-impl/bound error. `Trait` has no `method` → the existing no-method error.
> That is three lines of spec and no new diagnostic code beyond the help text.
>
> ## Cross-language
> - Rust: `<Widget as Alpha>::make()` gives the same information in a heavier, special-purpose grammar.
> - Swift has no spelling for this case and users rename. That is the trap we avoid.
> - Haskell uses annotations (P2 style) and needed `TypeApplications` for the Self-free case. That is evidence that inference alone leaves a hole.
> - Go and Lua avoid the problem by having no associated functions. We have them, so we pay the minimal price.
>
> Vote intent: yes on P1. No on P2 and P3 as additions.

#### Phase A.5 — Moderator dedupe

The moderator grouped the six proposals into options and listed the variations for debate (mechanical grouping, no votes):

> # Phase A.5 — mechanical dedupe (moderator)
>
> Full Phase A proposals, verbatim, one file per panelist in this directory:
> phaseA_sys.md, phaseA_web.md, phaseA_plt.md, phaseA_devops.md, phaseA_aiml.md, phaseA_min.md
> Read all six before you reply.
>
> ## Distinct options proposed
>
> - **F — `(Trait for Type).method(args)`**: proposed by Systems (primary) and PLT (primary, "Proposal A").
> - **A — `(Type as Trait).method(args)`**: proposed by Web (primary) and DevOps (primary); PLT lists it as fallback.
> - **P — `Type.Trait.method(args)`**: proposed by Minimalism (primary).
> - **I — `Self` in `Trait.method(args)` is an ordinary type variable solved by inference from arguments and expected type; E0301 when nothing fixes it** (`let w: Widget = Alpha.make()`): proposed by AI/ML (primary, as the only fix) and PLT (secondary, "Proposal B", only as an add-on to an explicit form).
> - **T — Self as explicit type application on the method, `Alpha.make[Widget]()`**: Systems fallback.
> - **H — Self named on the trait head, `Alpha[Self = Widget].make()`**: AI/ML fallback.
> - Rejected by all six in Phase A: do nothing / rename only.
>
> ## Variations flagged for debate
>
> 1. **Explicit form at all?** AI/ML proposes I as the only fix (no new form). Sys, Web, PLT, DevOps and Min say an explicit form is required because I does not reach an associated fn whose signature does not mention `Self`.
> 2. **Spelling of the explicit form:** F vs A vs P (vs T/H fallbacks).
> 3. **Add I alongside an explicit form?** PLT: optional add-on. Sys, Web, DevOps, Min: no / not now (YAGNI). AI/ML: I is primary.
> 4. **Does the explicit form accept receiver methods?** Web: no (two spellings for one job). DevOps: yes, uniform. Sys, PLT: legal but not promoted. Min: legal under the same rule, not promoted.
> 5. **E0522 help content:** every explicit-form proposal keeps `Trait.method(x)` in the help for a receiver call and prints the new form only for an associated fn.
>
> ## Facts checked by the moderator (from sections/)
> - The spec has no value cast spelled `as` (no `x as Int` anywhere in sections/).
> - Systems' Phase A states that `Color.Alpha.make()` already reads as a method call on enum variant `Color.Alpha` when `Color` has a variant `Alpha`. Enum variants are written `Enum.Variant` in Blink.
> - Blink has no associated types and no nested types today.

#### Phase B — Debate (round 1)

Each panelist read the deduped options and replied once. Position shifts: all six moved to F; Minimalism withdrew P after the enum-variant collision; AI/ML withdrew Self inference as the primary form; Web and DevOps moved from A to F.

**Systems:**

> **Systems — Phase B round 1**
>
> **(1) Positions**
>
> 1. **Explicit form at all? Yes.** AI/ML's inference-only plan (I) cannot express `fn default_port() -> Int` or `fn describe() -> Str` on two traits. In those signatures `Self` appears in no parameter and not in the return type, so no annotation can supply it. That leaves a program with no spelling, which is the exact defect the ticket reports. Haskell needed TypeApplications for this case, and PLT already cited that.
>
> 2. **Spelling: F `(Trait for Type)` first, A `(Type as Trait)` an acceptable second, P `Type.Trait` no.** F and A carry the same pair (trait, Self type) and produce the same direct call, so my domain does not split them hard. I keep F because it is the impl header word for word: a reader can grep `Alpha for Widget` and land on the impl block that becomes the C symbol. A reuses `as` in a third role, and TypeScript readers will read it as a cast. If the vote goes A, I will not block it.
>
> 3. **Add I alongside? No, not now.** It is sound because it stays local and modular. But it is a second mechanism for something F/A already cover, and with it the call site no longer shows which impl runs. YAGNI. We can add it later with no conflict.
>
> 4. **Explicit form on receiver methods? Legal, not promoted.** One typing rule is cheaper in the checker and the spec than "only if the method has no `self`". With Web's restriction we would need a special-case error and a second rule for generated code to learn. E0522 help still prints the shorter `Trait.method(x)` form.
>
> 5. **E0522 help: agree.** Print `Trait.method(x)` for receiver calls and the new form for associated functions, with `T` printed by name in generic code.
>
> **(2) Rebuttals**
>
> - **Minimalism, "`Widget.Alpha` cannot collide with anything, a type has no static fields": this is wrong.** Enum variants are `Enum.Variant`, and the moderator confirmed it. Take `type Color { Alpha, Beta }`. Today `Color.Alpha.make()` already means "call `make` on the value `Color.Alpha`". Under P the resolver must pick between the variant and the trait.
>   - If the trait wins, adding or importing a trait named `Alpha` silently changes what an existing call does. That breaks the rule that a new item may only cause loud errors.
>   - If the variant wins, P cannot reach that impl at all.
>   - Either way it is a priority rule, and §3c.4 has none. P is out for me.
> - **AI/ML, on token cost:** `(Alpha for Widget)` is about 5 tokens, and it appears only where E0522 printed it verbatim. A model copies the help line, so it has nothing to guess.
> - **DevOps, on the bonus of a parse site for `x as Int`:** we can get that targeted error without giving `as` a real meaning. The parser can recognize `expr as Type` only to reject it. That point does not favor A over F.
> - **DevOps and Min, on "LSP lists the traits Widget implements":** F gets the same completion after `for Widget`, or after `(Alpha for ` it lists the implementing types. The tooling is equal either way.
> - **Web, "Widget as Alpha reads aloud":** "Alpha for Widget" also reads aloud, and it is the sentence the user already wrote in the impl.
>
> **(3)** I am stable and ready to vote: F, with A as acceptable second, no I, receiver methods legal but not promoted.

**Web/Scripting:**

> Web/Scripting, Phase B round 1: I move from A to F, `(Trait for Type)`. I keep "no I now", and I now accept receiver methods in the explicit form.
>
> **1. Need an explicit form at all? Yes.** I alone cannot reach `fn default_port() -> Int`, and neither can a chained `Alpha.make().v`. Pointing a learner at an error with no call-site fix gives us the Swift story. AI/ML's own help text needs a `let` the user may not want. One more point: in the generic case, `fn f[T: Alpha + Beta]() -> T { Alpha.make() }` solves Self from the return type. That is spooky action for a JS or Python reader: the code that runs is decided by a line they are not looking at.
>
> **2. Spelling: F, with A as my second choice. I change my lead.** Systems and PLT have the better teaching story: "copy your impl header." The user typed `impl Alpha for Widget` minutes ago, and `(Alpha for Widget).make()` is the same words in the same order. That beats my "read it aloud" argument, because it needs no new mental model at all. It also avoids the cast reading of `as` that three panelists raised. I still think the cast risk is small (Blink has no casts), but zero beats small. P is out for me: Systems found a real collision (`Color.Alpha.make()` when `Color` has a variant `Alpha`), and `Widget.Alpha` reads like a nested member to every OOP developer. T and H are out because brackets after a callee already mean the callee's own binders.
>
> **3. Add I alongside? No, not now.** Correction to my own Phase A: I said that deleting the annotation "changes meaning". It does not. Deleting it gives a loud E0301, so I withdraw that argument. My remaining objection is learnability: two mechanisms for one rare problem, and the second one only works sometimes. Add it later if users ask. Nothing in F blocks it.
>
> **4. Receiver methods in the explicit form: changed to "legal, not promoted."** Under F, refusing `(Display for User).display(u)` would be a special case that someone must explain on Stack Overflow ("why does the impl-header form work here but not there?"). One rule: "`(Tr for T)` selects the impl, and then you call any of its methods with their declared parameters." The help and the docs still show `Display.display(u)` for receiver calls. That is the same position as Sys, PLT and Min.
>
> **5. E0522 help: agree.** Print `Trait.method(x)` for a receiver call and `(Alpha for Widget).make()` for an associated fn, with the type parameter's own name in generic code (`(Alpha for T).make()`). Each line should be pasteable and should map 1:1 to an LSP quick-fix (DevOps).
>
> **Rebuttals**
> - To AI/ML ("I matches Rust training data"): Rust users who reach for `let w: Widget = Alpha::make()` hit `<Widget as Alpha>::make()` for every non-Self return. Models have seen both, and F carries the same pair of names as the second. I also find "no new syntax" overstated: I changes what a qualified call means, and that costs learning effort even with no new tokens.
> - To DevOps (A over F): every tooling benefit you list (completion after the keyword, go-to-impl, a mechanical quick-fix, a canonical fmt) holds just as well for F. The `x as Int` → "no casts here" diagnostic is a nice bonus, but we can give it to a stray `as` without making `as` the syntax for this form.
>
> **Status: stable, ready to vote.** F first, A second. No to I for now. Receiver methods legal under F but not promoted.

**PLT:**

> PLT, Phase B round 1: I vote F, `(Trait for Type)`. A is my second choice. I reject I as the only fix, and I drop I as an add-on.
>
> **(1) The five variations**
>
> 1. **Is an explicit form needed? Yes.** Without one, I (inference only) leaves programs the language cannot express. Example: `trait Alpha { fn port() -> Int }` together with `trait Beta { fn port() -> Int }`. `Self` occurs in no parameter and not in the return type, so no ascription can fix it, and no edit at the call site can name which impl runs. Haskell had exactly this hole and closed it with AllowAmbiguousTypes and TypeApplications. We should not ship the same hole.
> 2. **Spelling: F first, A second. Reject P, T and H.** F and A are equally sound: both name the full pair (τ, Tr[σ̄]) at one callee head and have the same typing rule. My reasons for F over A, in order:
>    - F repeats the impl header, so it names the declaration it selects.
>    - `as` has no "view at" meaning anywhere else in Blink.
>
>    I accept DevOps's point about completion order: `(Widget as ` gives a smaller list than `(Alpha for `. It is a real point, but a small one for a form that appears only when a diagnostic produces it. I would vote A over P, T or H without complaint.
> 3. **Add I alongside? No, not now.** I withdraw my add-on. I is a conservative extension: it turns metavariables on where today there is an error, so every program that compiles keeps its meaning. It can therefore land later with no breaking change. YAGNI wins here.
> 4. **Does the form accept receiver methods? Yes, but do not promote it.** The typing rule is "select a witness, then project a method". Refusing methods that take `self` would add a restriction with no gain in soundness, and it would make the head mean different things depending on the method. That non-uniform rule is worse than two spellings. `fmt` does not rewrite either form into the other. Help prints the shorter form.
> 5. **E0522 help: agree.** Two additions:
>    - When the call is on a type parameter, print its own name: `(Alpha for T)`.
>    - When the trait is a generic instance, print the instance with its arguments: `(From[U8] for Widget)`.
>
> **(2) Rebuttals**
>
> - **To Minimalism, on P (`Type.Trait.method`).** The enum-variant collision Systems found is fatal. `Color.Alpha` already means a variant, so under P the meaning of `Color.Alpha.make()` depends on which names are in scope. Adding a trait named `Alpha`, or a variant named `Alpha`, would change how existing code resolves. That breaks the principle the panel guards in §3c: a new declaration may only cause loud errors, never a different resolution. P also puts a trait in a path-segment position where nothing else ever stands. That is not less grammar, it is overloaded grammar.
> - **To AI/ML, on H (`Alpha[Self = Widget]`).** H brings in named type arguments, which Blink does not have. It also mixes `Self` with the trait's own positional arguments in one list (`From[U8, Self = Widget]`). That is a bigger language change than F or A, not a smaller one.
> - **To AI/ML, on training data.** The Rust training data supports me too: `<Widget as Alpha>::make()` is the form that always works, and ascription is only the convenience on top of it.
> - **To Web, on refusing receiver methods.** Under Web's rule, `(Config as Serializable)` would be valid or invalid depending on which method follows it. That makes a fragment's meaning depend on what comes after it, the same complaint Web makes about overloading. It also means generated code needs two forms in place of one.
> - **To DevOps, on catching `x as Int`.** Pointing a user who writes `x as Int` to `Int.from(x)` is parser error recovery. Blink can do that whether or not `as` belongs to the grammar, so it does not favour A.
>
> **(3) Stable, ready to vote.**

**DevOps:**

> DevOps Phase B round 1, full reply.
>
> (1) Variations
> 1. Explicit form: required. Under I alone, an associated fn whose signature does not mention Self (`fn default_port() -> Int`) gets an E0301 whose help cannot name any fix. We would be back to the dead-end diagnostic this ticket exists to remove.
> 2. Spelling: I move from A to F, `(Alpha for Widget).make()`. A stays my second choice. Reasons from tooling:
>    - Grep: `rg "Alpha for Widget"` finds the impl header and every call site that selects it. No other spelling gives that.
>    - No cast reading. The TS/Rust "as = cast" worry goes away. The `x as Int` newcomer diagnostic I wanted does not depend on A; the parser can catch `as` after an expression under any spelling.
>    - The completion order is weaker under F: after `(Alpha for `, the list is every implementor of Alpha, not Widget's few traits. That is minor, because users get this form by pasting from E0522 help or applying the quick-fix, not by typing it.
>    - P: no. Systems' enum-variant point decides it: `Color.Alpha.make()` already has a meaning. The resolver would have to guess, and the error for a wrong guess would be confusing. It also mixes trait names into completion after `Type.`.
> 3. I as an add-on: not now. It is a second mechanism with its own error path (E0301 pointing at a distant `let`). It can be added later without conflict.
> 4. Receiver methods in the explicit form: legal, not promoted. I give up "promote it uniformly" and agree with Sys/PLT/Min. Banning it (Web) needs a new diagnostic rule for code that is correct. Under "legal, not promoted", help never prints it and fmt never rewrites it.
> 5. E0522 help: agree. One pasteable line per candidate trait, each line a quick-fix. The receiver form stays `Trait.m(x)`, and the new form appears only for an associated fn. Generic case: print the parameter's own name, `(Alpha for T).make()`. Generic trait: print the full instance, `(From[U8] for Widget).from(b)`. Explain text keeps "rename" as a secondary option. When the type does not implement the trait, report E0306 at the head, not at the method name.
>
> (2) Rebuttals
> - AI/ML on token cost: `: Widget` is cheap only when a `let` exists. `Alpha.make().v`, an argument position, and a Self-free fn each need a rewrite or have no fix. For a model, a help line it can copy as-is beats a rule it has to apply at the binding.
> - AI/ML on `as` causing cast guesses: under F this no longer matters.
> - Min "no new diagnostic code": P still needs a new rule for the Type-vs-variant resolve conflict, plus its error. That is not zero.
>
> (3) Stable, ready to vote: F first, A acceptable, P no, I not now.

**AI/ML:**

> AI/ML Phase B round 1: I concede variation 1, vote F for the spelling, and drop I.
>
> **1. Explicit form at all? Yes, I concede.** Sys, Min, PLT and Web are right. An associated fn whose signature has no `Self`, such as `fn default_port() -> Int`, gives inference nothing to work with. A fix that covers only part of the cases is worse for a model than one form that always works, because the model has to learn when the fix stops working. I withdraw I as the only fix.
>
> **2. Spelling: F `(Alpha for Widget).make()`. A second, P rejected.**
> - F repeats the impl header word for word. Every Blink user, and every model that read the spec, has already written `impl Alpha for Widget`. Writing the call is a copy of a form in the same language, so nothing new has to come from training data. That is the property I weigh most.
> - A puts `as` in expression position. The biggest risk with LLM output is not this rare call. It is that models already reach for `x as Int` casts. If `(T as Tr)` is legal, Blink code in training data shows `as` in expression position, which makes that wrong habit stronger. F leaves `for` doing the same job it does in `impl`.
> - P has the real conflict Sys found with enum variants (`Color.Alpha.make()`). A model cannot tell those two readings apart from the text, so I reject it.
> - T and H: the bracket-slot problem that PLT, Min and Web described. Rejected, and that includes my own H.
>
> **3. I next to the explicit form: no, not now.** Once F exists, I is a second way to write the same call. Every second way is a decision point, and models will choose between the two at random. YAGNI. It can come later without conflict, as Web and Sys say.
>
> **4. Receiver methods in the explicit form: legal under the same rule, not promoted.** Agree with Sys, PLT and Min. A uniform rule matters to a code generator: one form that always compiles is easier to emit than a rule with an exception ("not for self-methods"), which models will break. The E0522 help and the docs still show `Trait.method(x)` for receiver calls. fmt never rewrites one form into the other.
>
> **5. E0522 help: agree.** Give one line to paste per candidate. Print the type parameter's own name (`(Alpha for T).make()`). Print the new form only for associated fns. Also, a swapped head like `(Widget for Alpha)` should get a targeted error: "`Alpha` is a trait; write `(Alpha for Widget)`". Models trained on Rust's `<Widget as Alpha>` order will make that mistake, and a direct fix closes the loop in one retry.
>
> **Rebuttals:**
> - DevOps: the "bonus" of a parse site for `x as Int` does not need A. The parser can catch `as` after any expression and give the same pointed error whether or not `(T as Tr)` is legal. Under F that error is simpler: "`as` is not an operator in Blink."
> - Web: "reads aloud on first sight" is equally true of F. "Alpha for Widget" is the phrase the user wrote one screen up in the impl. A carries the TypeScript cast reading, and F carries none.
>
> **Stable, ready to vote:** F, with receiver methods legal but not promoted, no I for now, and help text as in item 5.

**Minimalism:**

> Minimalism, Phase B round 1: I withdraw P (Type.Trait.method) and move to F, (Trait for Type).method(args). My positions on variations 1–5 follow, then rebuttals. Stable, ready to vote.
>
> **Withdrawing P.** Systems is right. `Color.Alpha.make()` already means "call `make` on the enum value `Color.Alpha`" when `Color` has a variant `Alpha`. A type can have a variant `Alpha` and implement a trait `Alpha` at the same time. To fix that, P would need a resolution priority rule. That is extra spec, and it is a silent-meaning trap, which is worse than new syntax. My Phase A claim that "Widget.Alpha cannot collide with anything" was wrong.
>
> **1. Explicit form at all? Yes.** I alone is incomplete. It cannot reach an associated fn whose signature does not mention `Self` (`fn default_port() -> Int`), and it cannot reach `Alpha.make().v` without an extra `let`. So I cannot close the gap, and some form is required. AI/ML's cost argument (a new form is a new decision point) is real. But a gap with no spelling is the worst decision point: the model keeps guessing forms that do not exist. AI/ML says the same against "rename".
>
> **2. Spelling: F, `(Alpha for Widget).make()`.**
> - F reuses `for` with the meaning it already has in `impl Alpha for Widget`. It gives the existing word order and keyword a second site, but not a second meaning.
> - A gives `as` a third role, in expression position, where every Rust, TS and Kotlin reader sees a cast. Blink has no casts. DevOps' "bonus" diagnostic for `x as Int` is a reason to keep `as` out of expressions, not to bring it in. We should not create the parse site that makes the wrong guess look plausible.
> - T and H overload brackets. PLT showed this breaks the E0303 binder rule. Both are no.
>
> **3. Add I alongside? No, not now.** I is a pure extension: every program that compiles today keeps its meaning. So we can add it later at zero migration cost if real code asks for it. With F in place it would be a second spelling for the same job, with no capability gain. YAGNI. To AI/ML: I agree that `let w: Widget = Alpha.make()` is what models will write first. If that shows up in practice, the E0522 help can point those programs to F, and we can revisit I with evidence.
>
> **4. Receiver methods in F: legal, not promoted.**
> - The minimal rule is uniform: "`(Tr for τ).m(args)` passes exactly m's declared params with Self := τ". Excluding self-methods adds a carve-out sentence and a new error. That is more spec, not less.
> - Web's worry about two spellings is real. The answer is the help text and the docs, which always show `Trait.method(x)` for receivers. fmt never rewrites one form into the other.
>
> **5. E0522 help: agree.** A receiver call keeps `Alpha.method(x)`. An associated fn gets `(Alpha for Widget).make()`, one line per candidate trait. For a type parameter it prints the parameter's own name. Rename moves to explain text as a secondary option.
>
> **Rebuttals:**
> - DevOps: "the LSP lists only the traits Widget implements" applies to F just as well, after `(` … `for Widget)`. Completion order is a tooling detail and should not pick our syntax.
> - AI/ML: "Rust's `let w: Widget = Alpha::make()` is the common pattern". In Rust that works only because Rust has inference and an explicit form (`<W as A>::make()`) side by side. Copying the convenience without the floor reproduces Haskell's AllowAmbiguousTypes hole.
> - Web (no receivers in A): see 4. I accept the outcome if the majority wants the carve-out. It is not worth blocking a vote.

#### Phase C — Final vote

The ballot, as the moderator sent it:

> # Phase C — silent vote (moderator ballot)
>
> All six panelists signalled "stable, ready to vote" after Phase B round 1. Phase B round 1 replies, verbatim, are in phaseB1_*.md in this directory (read them if you have not).
>
> Vote on each question. For each: **Vote** (option label), **Reasoning** (2–4 sentences, your domain), **Concern** (one sentence on what could go wrong with the option you expect to win, from your POV).
>
> **Q1 — Explicit call form that names both the trait and the Self type**
> - F: `(Trait for Type).method(args)` — e.g. `(Alpha for Widget).make()`, `(Alpha for T).make()`, `(From[U8] for Widget).from(b)`
> - A: `(Type as Trait).method(args)`
> - P: `Type.Trait.method(args)`
> - T: `Alpha.make[Widget]()`
> - H: `Alpha[Self = Widget].make()`
> - N: no explicit form (Self inference only)
>
> **Q2 — Self solved by ordinary inference in `Trait.method(args)` (e.g. `let w: Widget = Alpha.make()`), in addition to the Q1 form**
> - Y: add now
> - L: not now (may be added later as a conservative extension)
>
> **Q3 — Does the Q1 form accept methods that take `self`?**
> - U: legal under the same rule; not promoted (help/docs keep `Trait.method(x)` for receiver calls; fmt never rewrites either form)
> - X: refused; the form is only for associated functions
>
> **Q4 — E0522 help content (spec fixes content, not wording)**
> - C: receiver call keeps `Trait.method(x)`; associated fn gets one pasteable line per candidate trait in the Q1 form; generic code prints the type parameter's own name; a generic trait prints the full instance (`From[U8]`); type not implementing the trait is E0306 reported at the head; rename stays in explain text as a secondary option.
> - O: other (state it)
>
> **Q5 — Targeted diagnostic for a swapped head (e.g. `(Widget for Alpha)` under F): "`Alpha` is a trait; write `(Alpha for Widget)`"**
> - Y: yes, spec requires the diagnostic content
> - N: no, leave to implementation / generic error

Results: **Q1 F** 6-0 · **Q2 L** 6-0 · **Q3 U** 6-0 · **Q4 C** 6-0 · **Q5 Y** 5-1 (Minimalism *(dissent)*: N). The user signed off on the tally, including the 5-1 on Q5.

Each ballot, verbatim:

**Systems:**

> **Systems — Phase C ballot**
>
> **Q1 — Vote: F** `(Trait for Type).method(args)`
> Reasoning: The call has to fix the mono key (trait instance, Self type) at type check. F writes that key in the same words as the `impl Alpha for Widget` header that becomes the C symbol. It compiles to one direct call with no runtime cost, no inference step and no lookup by name at mono. It parses without ambiguity, because `for` never follows an expression. It also covers generic trait instances (`From[U8]` vs `From[Char]`) and type parameters (`(Alpha for T)`) under one rule.
> Concern: The parser must stay strict that `(Tr for τ)` is valid only as a callee head. If it leaks into value or type position, we take on a half-built first-class impl value that codegen has no shape for.
>
> **Q2 — Vote: L** (not now)
> Reasoning: Inference is sound and local, but it is a second way to choose the same impl, and the reader can no longer see at the call which impl runs. F already covers every case, and inference cannot reach a Self-free associated fn. It is a conservative extension, so it can land later with no breakage if real code asks for it.
> Concern: Users from Rust will write `let w: Widget = Alpha.make()` first. The E0522 help must lead them straight to F, so we do not get pressure to add I without evidence.
>
> **Q3 — Vote: U** (legal, not promoted)
> Reasoning: One typing rule (select the impl, then call any of its methods with its declared parameters) is cheaper in the checker and the spec than a carve-out with its own error. Both forms resolve to the same symbol, so allowing both costs nothing at runtime. Help and docs keep the shorter `Trait.method(x)`.
> Concern: Generated code may use the long form where the short one would do. That costs style only, and fmt must not churn between the two.
>
> **Q4 — Vote: C**
> Reasoning: Each help line names exactly one impl, the same thing codegen will emit, so a pasted fix is right the first time. Printing the type parameter's own name and the full generic-trait instance keeps each line pasteable in generic code. Reporting E0306 at the head puts the error where the wrong impl was named.
> Concern: In a generic body the help must print the bound's instance as the user spelled it (for example `From[U8]`), not a resolved or internal form, or the pasted line will not compile.
>
> **Q5 — Vote: Y**
> Reasoning: A swapped head is the most likely mistake, because Rust's `<Type as Trait>` uses the opposite order. It is cheap to detect: the name in the trait slot resolves to a type, and the name in the type slot resolves to a trait. A targeted fix turns a confusing resolve error into a one-step repair at no runtime cost.
> Concern: The check must fire only when the swap really resolves (a type in the trait slot and a trait in the type slot). Otherwise it will suggest a nonsense swap for plain typos.

**Web/Scripting:**

> Web/Scripting — Phase C ballot
>
> **Q1 — Vote: F** `(Trait for Type).method(args)`
> Reasoning: The learner already wrote `impl Alpha for Widget`. The call `(Alpha for Widget).make()` uses the same words in the same order, so it needs no new mental model and gets no cast reading from TS or Rust readers. It covers type parameters and generic traits (`From[U8]`) with no extra rule. It appears only where E0522 prints it, so a long spelling costs little.
> Concern: Readers who come from Rust's `<Widget as Alpha>` will write the operands in the wrong order. That is a learning cost, and Q5 must pay it.
>
> **Q2 — Vote: L** (not now)
> Reasoning: It is a second mechanism for a rare problem, and it works only when Self appears in a parameter or in the return type. Two half-overlapping rules generate more confused questions than one rule that always works. It is a conservative extension, so it can land later if real code asks for it.
> Concern: Users from Rust will write `let w: Widget = Alpha.make()` first and get an error. E0522 and E0301 help must show them the F line to paste.
>
> **Q3 — Vote: U** (legal, not promoted)
> Reasoning: A rule like "the head is valid only when the method that follows has no `self`" is a special case that someone must explain on Stack Overflow. One sentence covers the uniform rule: "`(Tr for T)` selects the impl, then you call its methods with their declared parameters." Help and docs keep `Trait.method(x)` for receivers, so learners still see one spelling per case.
> Concern: A blog post or LLM output may promote `(Display for User).display(u)` as "the safe form". The docs must state that `Trait.method(x)` is the normal spelling.
>
> **Q4 — Vote: C**
> Reasoning: Every help line must be pasteable and must map 1:1 to an LSP quick-fix. Printing the type parameter's own name and the full generic-trait instance means the user never edits the suggestion. E0306 at the head points at the part the user must change.
> Concern: An implementation may print only the trait name and drop `[U8]` or the parameter name. The spec should give one example of each case.
>
> **Q5 — Vote: Y**
> Reasoning: The swapped order is the most likely mistake under F: Rust's `<Widget as Alpha>` and my own first proposal both put the type first. A direct "write `(Alpha for Widget)`" fixes it in one retry for a human or a model. A generic "expected a trait" error would create the Stack Overflow question this panel set out to avoid.
> Concern: None for the diagnostic itself. When neither side resolves to a trait, the message must stay correct and must not suggest a swap that is also wrong.

**PLT:**

> PLT ballot, Phase C
>
> **Q1 — Vote: F** `(Trait for Type).method(args)`
> Reasoning: The call has to supply the whole witness (τ, Tr[σ̄]). F does this at one callee head with one typing rule: select the witness, then take the method with Self := τ and params := σ̄. It handles type parameters, generic trait instances and sealed traits with no extra rule. It does not clash with E0303's rule that a callee's bracket list holds its own binders, as T and H do. It does not depend on which names are in scope, as P does. It reuses `for` with the meaning it already has in the impl header.
> Concern: The spec must say that `(Tr for τ)` is only a callee head, never a type or a value. Otherwise it drifts toward first-class impl or dictionary terms without a typing rule for them.
>
> **Q2 — Vote: L** (not now)
> Reasoning: Inference of Self is a conservative extension. It replaces an error with a solved metavariable, so every program that compiles keeps its meaning, and it can land later with no breaking change. With F in place, it adds no power, only a second spelling, and the impl that runs would depend on a binding away from the call.
> Concern: Models and Rust users will write `let w: Widget = Alpha.make()` first. The help must send them to F, not to a dead end.
>
> **Q3 — Vote: U** (legal, not promoted)
> Reasoning: The rule "select a witness, then take any of its methods with their declared parameters" is uniform. Refusing methods that take `self` would add a carve-out, and the head would mean different things depending on which method follows it. That gains no soundness.
> Concern: Two valid spellings for receiver calls could drift in docs and in generated code, unless help and fmt keep `Trait.method(x)` as the one form they print.
>
> **Q4 — Vote: C**
> Reasoning: Every help line is a complete, well-typed program fragment that the user can paste. A missing impl is E0306 at the head, the same judgment as an unmet bound anywhere else.
> Concern: In generic code the help must print the bound that is really in scope (`(Alpha for T)`), never a concrete type found by looking at callers.
>
> **Q5 — Vote: Y**
> Reasoning: `(Widget for Alpha)` is a kind error: a trait stands where a type belongs, and a type where a trait belongs. Rust users reverse the order (`<Widget as Alpha>`), so this mistake is predictable. The check decides it from the two names alone, and the message gives the one fix that converges.
> Concern: The check must fire only when both names resolve and their kinds are swapped. Otherwise it would hide a genuine unresolved-name error behind a wrong "swap" suggestion.

**DevOps:**

> DevOps/Tooling ballot
>
> Q1 — Vote: F
> Reasoning: F gives one canonical form that fmt prints the same way every time. A search for `Alpha for Widget` lands on both the impl header and every call that selects it. Go-to-definition can jump straight to the impl's method body, because the head names the exact witness. The completion order is weaker than under A, but users get this form from the E0522 help line or the quick-fix, not by typing it.
> Concern: users who know Rust will write `(Widget for Alpha)` or `(Widget as Alpha)` out of habit. Without targeted errors (Q5) they get a generic parse failure.
>
> Q2 — Vote: L
> Reasoning: a second mechanism means a second error path (E0301 pointing at a distant `let`), and that path cannot fix a Self-free signature. It is a conservative extension, so it can land later with no breaking change if real code asks for it.
> Concern: models will write `let w: Widget = Alpha.make()` first. E0522/E0301 must then steer them to F in one step, not leave them guessing.
>
> Q3 — Vote: U
> Reasoning: refusing it needs a new error for code that is correct, and the meaning of the head would depend on the method that follows. Under U, help and docs never print the form for receiver calls, and fmt never rewrites either form, so users see one form per job.
> Concern: lint rules or style guides may later argue over which form to prefer for receiver calls. The spec should say plainly that both are fine and neither is rewritten.
>
> Q4 — Vote: C
> Reasoning: every help line is pasteable and maps 1:1 to an LSP quick-fix. Printing the type parameter's own name and the full generic trait instance means the pasted line compiles without edits. Reporting E0306 at the head points the user at the part they must change.
> Concern: when a type has many candidate traits, a long list of help lines can bury the note. Implementations should keep the note first and the candidates in declaration order.
>
> Q5 — Vote: Y
> Reasoning: Rust's `<Widget as Alpha>` order makes the swapped head the single most likely mistake, for humans and for models. A targeted "`Alpha` is a trait; write `(Alpha for Widget)`" fixes it in one retry. The resolver already knows which side is a trait, so the check costs little, and putting its content in the spec keeps tools consistent.
> Concern: the spec must fix only the content (which side is the trait, plus the corrected head), not the wording, or it will freeze diagnostic text.

**AI/ML:**

> AI/ML ballot
>
> **Q1 — Vote: F** `(Trait for Type).method(args)`
> Reasoning: The form copies the impl header the user or model already wrote (`impl Alpha for Widget`). A model can learn it from the spec alone, with no need for the pattern to exist in training data. It covers Self-free associated fns, generic traits (`From[U8]`) and type parameters with one rule, so a generator only has to learn one thing. It keeps `as` out of expression position, so Blink code does not make models' wrong habit of writing `x as Int` casts stronger.
> Concern: Models trained on Rust's `<Widget as Alpha>` order will write the head swapped (`(Widget for Alpha)`) or reach for `as`. Without a targeted diagnostic (Q5), they will burn retries.
>
> **Q2 — Vote: L** (not now)
> Reasoning: Once F exists, inference is a second way to write the same call, and a decision point that models resolve at random. It is a conservative extension, so it can land later with no breaking change if real code shows models writing `let w: Widget = Alpha.make()`.
> Concern: Models will still write `let w: Widget = Alpha.make()` first, from Rust habit. The E0522/E0301 help must print the F form for that shape, or the model loops.
>
> **Q3 — Vote: U** (legal, not promoted)
> Reasoning: A uniform rule is easier for a code generator: one form that always compiles beats a rule with an exception ("not for self-methods"), which models will break. The help and docs keep the shorter `Trait.method(x)` for receiver calls, so models see only one promoted form.
> Concern: Generated code may drift to F for receiver calls too, which gives two styles in the corpus. Since fmt never rewrites either form, that drift becomes permanent in training data.
>
> **Q4 — Vote: C**
> Reasoning: Every help line can be pasted as-is and names the exact instance (`T`, `From[U8]`). That is the best case for an LLM fix loop: copy the line, compile, done. E0306 at the head points to the token to change.
> Concern: If the wording leaves out the generic instance or the type parameter name in some path (for example nested generics), models will paste a line that does not compile.
>
> **Q5 — Vote: Y**
> Reasoning: The swapped head is the most predictable error a model will make under F, given Rust's Type-then-Trait order in training data. A diagnostic that names the fix closes the loop in one retry, at almost no spec cost. The spec should fix the content (name the trait, show the corrected head), not the wording.
> Concern: If someone has both a type and a trait with the same name in scope, the "is a trait" claim could be wrong. The diagnostic must check the kind of each side before it suggests the swap.

**Minimalism:** *(dissent on Q5)*

> Minimalism ballot ([the spec ticket])
>
> **Q1 — Vote: F** `(Trait for Type).method(args)`
> Reasoning: The language cannot express this call today, so a form is foundational, and F adds the least new meaning. It reuses `for` in the same word order and sense as `impl Alpha for Widget`. That adds a site, not a concept. A gives `as` a third role in expression position. P has the enum-variant collision, which needs a priority rule. T and H overload brackets.
> Concern: Users from Rust will write the order backwards (`(Widget for Alpha)`, after `<Widget as Alpha>`), so the head-swap error must be clear in practice.
>
> **Q2 — Vote: L** (not now)
> Reasoning: With F in place, inference adds no capability, only a second spelling that works for part of the cases. It is a conservative extension: every program that compiles today keeps its meaning. So we can add it later with evidence and no migration cost. YAGNI.
> Concern: Models will write `let w: Widget = Alpha.make()` first, and the E0522/E0301 help must send them to F in one step, or that friction will push for I early.
>
> **Q3 — Vote: U** (legal, not promoted)
> Reasoning: The uniform rule, "select the impl, then call any of its methods with their declared parameters", is one sentence. Refusing methods that take `self` adds a carve-out and a new error for code that is correct. More spec, no gain in soundness.
> Concern: Two valid spellings for receiver calls could drift in style. Help and docs must show only `Trait.method(x)` there, and fmt must never rewrite either form.
>
> **Q4 — Vote: C**
> Reasoning: The content follows from rules we already have: the receiver form is unchanged, one pasteable line per candidate, the type parameter's own name, the full generic trait instance, and the existing E0306 at the head. It adds no new diagnostic machinery beyond help text, and rename stays as a secondary note.
> Concern: None material; implementations must make sure the printed line compiles as-is (e.g. module-qualified type names when the type is imported under a path).
>
> **Q5 — Vote: N** (leave to implementation)
> Reasoning: The spec already makes a swapped head an error: the left side of `for` must be a trait, so `(Widget for Alpha)` fails loud with "`Widget` is not a trait". Good wording for that error is quality of implementation. It does not belong in the language definition, and every diagnostic the spec pins adds to its surface. I expect, and would encourage, the implementation to print the swap fix anyway.
> Concern: If the generic "not a trait" error ships without the swap hint, Rust-trained users and models will lose a retry, so a Q5=N outcome should still lead to a non-normative note or implementation ticket.

### Final Spec

```blink
trait Alpha { fn make() -> Self }
trait Beta { fn make() -> Self }

impl Alpha for Widget { fn make() -> Self { Widget { v: 1 } } }
impl Beta for Widget { fn make() -> Self { Widget { v: 2 } } }

let a = (Alpha for Widget).make()             // the impl `impl Alpha for Widget`
let b = (From[U8] for Widget).from(byte)       // a generic trait takes its full instance

fn pair[T: Alpha + Beta]() -> (T, T) {
    ((Alpha for T).make(), (Beta for T).make())  // a type parameter, under its own name
}
```

- `(Trait for Type).method(args)` selects the impl that `impl Trait for Type` declares, then calls the method with `Self := Type` and the trait's declared parameters. Resolution is fixed at type check.
- The head is valid only directly before `.method(`. It is never a type or a value.
- A type that does not implement the trait is E0306, reported at the head.
- A left side that does not name a trait is E0740 `QualifiedHeadNotTrait`. When the left side is a type and the right side a trait, the help gives the swapped head; otherwise it suggests no swap. Content is fixed, not wording.
- The head is legal on methods that take `self` (the receiver is the first argument), but help and docs print `Trait.method(x)` for those calls, and `blink fmt` rewrites neither form.
- `Self` is not inferred from an expected type: `let w: Widget = Alpha.make()` stays an error, and its help gives the impl-qualified form. Inference may be added later as a conservative extension.
- E0522 help: receiver calls keep `Trait.method(x)`; an associated function gets one pasteable impl-qualified line per owner; rename moves to `blink explain E0522`.

Spec: §3c.4 *Impl-Qualified Calls*. Catalog: E0740.
