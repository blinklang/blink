[< All Decisions](../DECISIONS.md)

# Payload Variants as Fn Values — Design Rationale

§3.4 *A generic function named as a value* lets a generic function's name stand wherever a function value is expected, and solves its binders from the expected type. The spec gave no such rule for a variant constructor. The *Bare variant and value names* ruling said that a bare variant is not a function value today and left the question out of scope. The compiler took the conservative reading: `let f = Some`, `xs.map(Some)`, `Option.Some`, `Ok`, `Err` and a user payload variant named with no argument list were `error[TypeError]` (E0300), "variant `Some` takes 1 argument(s) and is not a function value", with the help "wrap the constructor in a closure: `fn(x) { Some(x) }`". This ruling answers the question: is a payload variant constructor a function value?

The panel wrote against two rulings that land first: *Qualified variants in expressions* (a user variant is qualified in an expression, `Tree.Leaf`; only `Some`, `None`, `Ok` and `Err` stay bare; E0554 is `UnqualifiedVariant`) and *Variant and static method name case*.

This ruling closes the item that [Bare Variant and Value Names](bare-variant-value-names.md) left out of scope.

## Summary

| Q | Question | Result | Vote |
|---|---|---|---|
| Q1 | A payload variant named with no argument list | A positional-payload variant is a fn value `fn(P1, ..., Pn) -> E[binders]`, binders solved by §3.4 (E0301 at the reference when nothing fixes them); labels drop; a brace payload is E0300 "has named fields and is not a function value"; a no-payload variant stays a value; as a value `Ok` is only the one-argument form; a bare user variant is E0554 first | 6-0 |
| Q2 | The `Ok()` zero-argument form | Not part of this ruling | 6-0 |
| Q3 | Bare `Ok` where `fn() -> Result[(), E]` is expected | E0300, help `fn() { Ok(()) }` | 6-0 |
| Q4 | A no-payload variant where a fn is expected | E0300, help `fn() { Color.Red }` | 6-0 |
| Q5 | The "takes N argument(s) and is not a function value" diagnostic | Narrow it: E0300 stays the code for an arity mismatch against an expected fn type; only the "not a function value" message goes for positional variants | 6-0 |

AI-First review: 5/5 pass.

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated
in independent-proposal → debate → vote rounds.

#### Phase A — Independent proposals

Each seat proposed alone. All six seats put the same rule first: a positional-payload variant is a fn value under the §3.4 generic-function rule, and a brace payload is not. Five seats listed "keep today's rule and state it in the spec" as a fallback and argued against it; PLT rejected it.

- **Systems:**

  > ## What the hardware sees
  >
  > `xs.map(fn(x) { Some(x) })` already compiles to a capture-free closure: mono emits one C function per instantiation and the env is empty. A constructor named as a value can compile to the exact same thing: a synthesized thunk `Option_Some__Int(int64_t x) -> Option_Int`, emitted once per (variant, instantiation), passed with a null env. Same code, same cost, no allocation. So the current rule refuses a spelling whose output is identical to its own repair. That is the §3.4 generic-fn rationale word for word, and it applies here with no change.
  >
  > ## sys-1 (preferred): a positional payload variant is a fn value, by the §3.4 generic-fn rule
  >
  > A positional payload variant named with no argument list, where a fn value is expected, has type `fn(P1, ..., Pn) -> E[binders]`. The enum's binders are solved by unifying against the expected type. If nothing fixes them, that is E0301 at the reference (no new rule).
  >
  > ```blink
  > type Tree {
  >     Leaf(Int)
  >     Pair(Int, Int)
  >     Circle { radius: Float }
  >     Empty
  > }
  >
  > fn main() {
  >     let xs = [1, 2, 3]
  >     let a = xs.map(Some)                          // OK -- fn(Int) -> Option[Int]
  >     let b = xs.map(Tree.Leaf)                     // OK -- fn(Int) -> Tree, not generic
  >     let f = Tree.Leaf                             // OK -- no binders to solve
  >     let g: fn(Int, Int) -> Tree = Tree.Pair       // OK -- arity 2, not a tuple
  >     let h = Some                                  // error[CannotInferType] (E0301)
  >                                                   // help: annotate the binding:
  >                                                   //   `let h: fn(Int) -> Option[Int] = Some`
  > }
  > ```
  >
  > - **Multi-field:** `fn(A, B) -> E`, flat arity. Not a tuple. A tuple parameter would force a pack/unpack the closure form does not pay (the OCaml trap).
  > - **Brace payload:** not a fn value. Fields are named; a fn value carries no labels (§2.13 *Limit of the guard*), so field order would become silently load-bearing. Keep E0300, new help: "`Tree.Circle` has named fields; write `fn(r) { Tree.Circle { radius: r } }`".
  > - **`Some`, `Ok`, `Err`, `Option.Some`, `Result.Ok`:** same rule. `xs.map(Ok)` usually leaves `E` unfixed: E0301, help names the annotation.
  > - **`Ok` with no payload:** bare `Ok` is only ever the 1-arg constructor value. It never means `Ok()`. Against an expected `Result[(), E]` it is E0300 with help "write `Ok()`". One meaning per spelling; no expected-type-driven overload between a value and a fn.
  > - **No-payload variant (`None`, `Tree.Empty`):** stays a value of the enum. It is not `fn() -> E`.
  > - **Effects:** a constructor is pure; the value has an empty effect row.
  >
  > Spec: new paragraph in §3.4 after *A generic function named as a value*, "A payload variant named as a value", pointing at that rule. E0300's "is not a function value" text stays only for brace payloads and the `Ok`-as-`Ok()` case. tests/test_typecheck_payload_variant_is_not_a_value.bl flips to an accept test plus the brace/`Ok`/E0301 rejects.
  >
  > ## sys-2 (fallback): keep the rule, state it in the spec
  >
  > If the panel rejects sys-1, the spec must still say it: add the rule and E0300 to §3.4 so the compiler's behaviour is not a silent reading. I oppose this on cost grounds only weakly (there is no runtime cost either way), but it keeps a filter §3.4 already deleted once.
  >
  > ## Tradeoffs
  >
  > - Zero runtime cost: thunk equals the closure. Codegen adds one synthesized fn per used instantiation; mono already dedups.
  > - No new binder machinery: reuses the generic-fn solve path.
  > - Brace and `Ok()` stay errors, so there is no ambiguity a reader must resolve.
  >
  > ## Cross-language
  >
  > Rust: tuple variants are fns, struct variants are not. sys-1 is exactly that split. Swift `Optional.some` same. OCaml refuses because constructors are not curried fns; Blink has no currying, so that reason does not carry over.

- **Web/Scripting:**

  > ## web-1 (preferred): a positional-payload constructor is a fn value, by the §3.4 rule
  >
  > `xs.map(Some)` is the 90% case. A Python dev passes a class to `map` every day (`map(Point, pairs)`); a Swift dev writes `.map(Optional.some)`; a Rust dev writes `.map(Some)`. Today they get E0300 and a help that tells them to write the same program longer. §3.4 already deleted that exact rule for generic fns: "its prescribed repair — wrapping the name in a closure — means the same program." A constructor is the same case. One rule for "a callable name with no argument list" is less to learn than two.
  >
  > ```blink
  > type Tree {
  >     Leaf(Int)
  >     Node(Tree, Tree)
  > }
  >
  > fn main() {
  >     let xs = [1, 2, 3]
  >     let opts = xs.map(Some)                    // fn(Int) -> Option[Int]
  >     let leaves = xs.map(Tree.Leaf)             // fn(Int) -> Tree
  >     let mk: fn(Tree, Tree) -> Tree = Tree.Node // two params, not a tuple
  >     let r: fn(Str) -> Result[Str, Int] = Ok    // T = Str, E = Int from the annotation
  >     io.println("{opts.len()} {leaves.len()}")
  > }
  > ```
  >
  > Rules:
  > - **Type.** A variant `V(A1, ..., An)` of `E[T...]` named with no argument list has type `fn(A1, ..., An) -> E[T...]`. Applies to `Some`, `Ok`, `Err`, `Option.Some`, `Result.Ok`, `Tree.Leaf`.
  > - **Binders.** Solved from the expected type exactly as §3.4 does for `identity`. Under-determined is E0301 at the reference:
  >   ```blink
  >   let f = Some      // error[CannotInferType] (E0301): `T` of `Some` is unbound here
  >                     // help: annotate the binding: `let f: fn(Int) -> Option[Int] = Some`
  >   ```
  >   `Ok` and `Err` are always partly under-determined without context (one side of `Result` has no source), so they need an expected type. That is fine: in `map`/`and_then` and in an annotated `let` the context exists.
  > - **Multi-field.** n params, no tuple. Same as Rust; avoids the OCaml trap.
  > - **Brace payload.** Not a value. Field names are the whole point of the form; a positional fn would drop them and invent an order. Keep E0300, reword: "variant `Shape.Circle` has named fields and is not a function value"; help `fn(r) { Shape.Circle { radius: r } }`.
  > - **`Ok` with no payload.** The value form is the one-arg form only. `Ok()` stays call-only sugar for `Ok(())`. The spec does not mention `Ok()` today; it should, in the same edit.
  > - **No-payload variant.** Unchanged: `None`, `Color.Red` are values of the enum type.
  > - **Bare user variant** (`Leaf`): E0554 from the qualified-variants ruling, not this rule.
  >
  > Spec changes: §3.4 *A generic function named as a value* gains one sentence: "A variant constructor with a positional payload is named as a value by the same rule; its type is `fn(payload...) -> Enum[...]`." Add the brace-payload exception with its E0300 text. Delete the "takes N argument(s) and is not a function value" diagnostic for positional variants. Flip tests/test_typecheck_payload_variant_is_not_a_value.bl (keep the brace and under-determined rows as errors).
  >
  > Tradeoffs: a JS/TS dev has never passed a union member as a fn, but the form reads plainly, and the error they hit (E0301 on `let f = Some`) carries an annotation help. Cost: one more Stack Overflow question ("why does `let f = Some` fail but `map(Some)` works?"), which §3.4 already accepted for `identity`.
  >
  > ## web-2 (fallback): keep the current rule, but state it
  >
  > If the panel rejects web-1, the spec must say it in §3.4 next to the generic-fn rule, with the E0300 text and the closure help. Silence is the worst choice: an LLM or a Rust dev will write `map(Some)` and the spec will not tell them why it fails. I oppose web-2 because its own rationale contradicts the paragraph above it.

- **PLT:**

  > ## plt-1: a call-form variant constructor is a fn value, under the §3.4 generic-fn rule (preferred)
  >
  > **Typing rule.** Let `type E[ᾱ] { ... V(x1: T1, ..., xn: Tn) ... }`, n ≥ 1. In an expression, the name `E.V` (or bare `Some`/`Ok`/`Err`) with no argument list has type `fn(T1, ..., Tn) -> E[ᾱ]`, with an empty effect row. The binders `ᾱ` are the reference's binders. They are solved by unification against the expected type, as for a generic fn named as a value. If the expected type does not fix them, that is E0301 at the reference. This adds no new rule. It removes an exception.
  >
  > ```blink
  > type Tree[T] {
  >     Leaf(T)
  >     Node(Tree[T], Tree[T])
  > }
  >
  > fn main() {
  >     let xs = [1, 2, 3]
  >     let os = xs.map(Some)                      // OK: fn(Int) -> Option[Int]
  >     let ts = xs.map(Tree.Leaf)                 // OK: fn(Int) -> Tree[Int]
  >     let mk: fn(Tree[Int], Tree[Int]) -> Tree[Int] = Tree.Node   // OK: n-ary, not tupled
  >     let rs: List[Result[Int, Str]] = xs.map(Ok)                 // OK: the annotation fixes E = Str
  >     let f = Some                               // error[CannotInferType] (E0301)
  >                                                // help: annotate the binding:
  >                                                //   `let f: fn(Int) -> Option[Int] = Some`
  > }
  > ```
  >
  > **Why.** §3.4 says it already: "A rule that distinguishes a term from its own η-expansion is a syntactic filter standing in a typing rule's position, and its prescribed repair — wrapping the name in a closure — means the same program." Today's E0300 help, "wrap the constructor in a closure: `fn(x) { Some(x) }`", is that deleted repair word for word. `Some` and `fn(x) { Some(x) }` are the same term. A spec that refuses one and accepts the other must give a typing reason, and none exists.
  >
  > **Edges. Each follows from the rule; none needs a special case.**
  > - *Labelled positional payload* `Circle(radius: Float, tag: Int)`: type `fn(Float, Int) -> Figure`. The labels drop, as for any fn value (§2 *Limit of the guard*).
  > - *Brace payload* `Shape.Circle { radius: Float }`: **not a value.** It has no call form, so it has no η-expansion to be equal to. `error[TypeError]` E0300: "variant `Shape.Circle` has labelled fields and is not a function value"; help: `fn(r) { Shape.Circle { radius: r } }`. A value form would bring in positional construction of a literal that the spec makes labelled-only.
  > - *No-payload variant* (`None`, `Color.Red`): already a value of type `E`, never `fn() -> E`. If a fn is expected, it is a plain type mismatch; help: `fn() { Color.Red }`.
  > - *`Ok` with no argument*: `Ok` has one principal type, `fn(T) -> Result[T, E]`. `Ok()` is call-site sugar for `Ok(())`, not an overload, because a value has one type. Against `fn() -> Result[(), E]`, it is a type mismatch; help: `fn() { Ok() }`.
  > - *Unqualified user variant* `xs.map(Leaf)`: E0554 UnqualifiedVariant first. The qualification rule does not change.
  > - *Effects*: the row is empty, so the value fits any `fn(T) -> U ! _` parameter by row subsumption.
  >
  > **Spec changes.** §3.4: add *A variant constructor named as a value* after the generic-fn paragraph, with the rule, the brace and no-payload edges, and a cross-reference to E0301. Reword E0300's not-a-value message so that it covers only brace payloads. decisions/bare-variant-value-names.md:347: add a note that this ruling closes the item it left out of scope. Flip tests/test_typecheck_payload_variant_is_not_a_value.bl to positive cases, and keep the brace and no-payload cases as errors.
  >
  > **Tradeoffs.** Soundness: no new judgement. The rule reuses one already in the spec, so it composes with HM metavars and E0301 placement as is. The cost is that `xs.map(Ok)` with nothing to fix `E` now reports E0301 at `Ok`, not E0300. The new message is better, because it names the true defect.
  >
  > **Cross-language.** Haskell, OCaml (for a single constructor argument), Rust, Swift and Scala all type constructors as functions. Brace exclusion matches Rust: struct-like variants are not fns, but tuple-like variants are.
  >
  > ## plt-2: keep E0300 and state it in the spec (rejected by me)
  >
  > This choice is coherent only if §3.4's η-argument is withdrawn for generic fns too. Keeping both is the inconsistency the earlier ruling deleted. If the panel keeps the rule, the spec must say why constructors are different, and I cannot write that sentence.

- **DevOps:**

  > ## devops-1 (preferred): a positional-payload constructor is a fn value; a brace payload is not
  >
  > Rule: a variant with a positional payload `V(T1, ..., Tn)`, named with no argument list, has type `fn(T1, ..., Tn) -> E[binders]`. Binders are solved from the expected type by the §3.4 *generic function named as a value* rule. No new inference rule; the constructor is one more generic name.
  >
  > ```blink
  > type Tree { Leaf(Int)  Node(Tree, Tree) }
  > type Pair { Two(Int, Str) }
  >
  > fn main() {
  >     let xs = [1, 2, 3]
  >     let opts = xs.map(Some)                       // fn(Int) -> Option[Int]
  >     let leaves = xs.map(Tree.Leaf)                // fn(Int) -> Tree
  >     let mk: fn(Int, Str) -> Pair = Pair.Two       // multi-field: n-ary fn
  >     let r: fn(Int) -> Result[Int, Str] = Ok
  >     let _ = (opts, leaves, mk, r)
  > }
  > ```
  >
  > Cases:
  > - `Some`, `Ok`, `Err`, `Option.Some`, `Result.Ok`: generic fn values. `Ok` as a value is always `fn(T) -> Result[T, E]`. `Ok()` for `Result[(), E]` stays a call form. It does not make `Ok` an overloaded value. One value form gives one hover type and one error.
  > - No-payload variant (`None`, `Color.Red`): unchanged. It is a value of the enum.
  > - Bare user variant `Leaf`: E0554 UnqualifiedVariant comes first, as today.
  > - Brace payload `Shape.Circle { radius: Float }`: not a fn value. E0300, message "variant `Circle` has named fields and is not a function value", help `fn(r) { Shape.Circle { radius: r } }`. Why: a positional order taken from declaration order means a field reorder silently changes the type of every `xs.map(Shape.Circle)`. The user sees an error far from the change, or worse, none, when two fields share a type. Named fields exist to stop that.
  >
  > Diagnostics:
  > - `let f = Some` gives E0301 CannotInferType at the reference: "`T` of `Some` is unbound at this reference". Help: "annotate the binding: `let f: fn(Int) -> Option[Int] = Some`". This is the §3.4 text, unchanged.
  > - `strs.map(Tree.Leaf)` with `strs: [Str]` gives E0300: "expected `fn(Str) -> _`, found `fn(Int) -> Tree`" with the span on `Tree.Leaf`. The type printer already renders fn types. No new code.
  > - `let f = Some[Int]` gives E0314 TypeArgsWithoutCall, as for a generic fn.
  >
  > Tooling: LSP hover on `Tree.Leaf` shows `fn(Int) -> Tree`. Completion after `Tree.` lists each variant with that signature. That is the same data rust-analyzer shows for a tuple variant. `blink fmt` needs no change. The current help, "wrap in a closure", is the exact repair §3.4 calls a syntactic filter. A diagnostic whose fix means the same program is noise. I want to delete it, not restate it in the spec.
  >
  > Spec changes: §3.4, add a paragraph after *A generic function named as a value*: a positional-payload variant is a generic fn with these binders; a brace-payload variant is not a value. Close the out-of-scope note in decisions/bare-variant-value-names.md. E0300 keeps its code. Its "not a function value" message narrows to brace payloads. tests/test_typecheck_payload_variant_is_not_a_value.bl flips to pass rows, with new reject rows for the brace payload and the E0301 under-determined case.
  >
  > Gap I flag: the spec does not say whether a static method (`Duration.ms`) is a fn value. With devops-1, `Tree.Leaf` is a value and `Duration.ms` maybe not. The two look alike after the case ruling. That needs its own ticket. It does not block this one.
  >
  > Cross-language: Rust, Haskell and Swift (`.map(Optional.some)`) do this. Rust also refuses brace (struct-like) variants as fns, which is the same split as devops-1.
  >
  > ## devops-2 (fallback): keep the current rule and write it into the spec
  >
  > State in §3.4: a payload variant is not a value; E0300 with the closure help. Cheapest. But it contradicts the §3.4 rationale. It keeps a help line that tells users to type more for the same program. An AI or human who learned `map(Some)` from Rust gets an error on correct-looking code. I vote against unless devops-1 hits a soundness block.

- **AI/ML:**

  > ## aiml-1 (preferred): a positional-payload constructor is a generic fn named as a value
  >
  > **Rule.** A variant with a positional payload, named with no argument list, is the value of a generic fn. Its type is `fn(P1, ..., Pn) -> E[T...]`. The enum's binders are solved from the expected type by the §3.4 *A generic function named as a value* rule, with no new rule. Under-determined is E0301 at the reference.
  >
  > ```blink
  > type Tree {
  >     Leaf(Int)
  >     Node(Tree, Tree)
  > }
  >
  > type Pair {
  >     Two(Int, Str)
  > }
  >
  > fn main() {
  >     let xs = [1, 2, 3]
  >     let opts = xs.map(Some)                    // fn(Int) -> Option[Int]
  >     let leaves = xs.map(Tree.Leaf)             // fn(Int) -> Tree
  >     let mk: fn(Int, Str) -> Pair = Pair.Two    // two params, not one tuple
  >     let f = Some                               // error[CannotInferType] (E0301)
  >                                                // help: annotate the binding:
  >                                                //   `let f: fn(Int) -> Option[Int] = Some`
  > }
  > ```
  >
  > - **Four prelude names.** `Some`, `Err` and `Option.Some`, `Result.Err` follow the rule. `Ok` as a value is `fn(T) -> Result[T, E]` only. Its zero-argument call form is call syntax, not a second value. `Ok` with `T = ()` still fits `fn(()) -> Result[(), E]`. One meaning for one name.
  > - **Multi-field payload.** n params, in declaration order. No tuple form.
  > - **No-payload variant.** Unchanged: `None`, `Color.Red` is a value of the enum type, never `fn() -> E`.
  > - **Brace payload.** Not a value. A brace variant has named fields and no positional order, so it has no fn type. `let f = Shape.Circle` stays error[TypeError] E0300 with new text: "variant `Circle` has named fields and is not a function value", help: `fn(r) { Shape.Circle { radius: r } }`.
  > - **Spec change.** §3.4: add one sentence and one example after *A generic function named as a value*: "A variant with a positional payload names a function of its payload types to its enum type and follows the same rule." The variants section (§3.x *Enums*) gets a cross-reference and the brace-payload exclusion. The E0300 payload message goes away except for the brace case. Flip tests/test_typecheck_payload_variant_is_not_a_value.bl to positive tests plus the brace and E0301 cases.
  >
  > **Why, from my seat.**
  > 1. **Learnability from the spec.** §3.4 already says a term and its η-expansion must not differ, and that wrapping in a closure "means the same program". A model that learns that rule will predict `map(Some)` works. Today the constructor is the one exception that rule does not name, and an exception the reader must memorize is a decision point. aiml-1 removes it. The constructor *is* a fn in the reader's mental model, so the rule needs no new idea.
  > 2. **Prior training data agrees.** Rust (`.map(Some)`, `.map_err(MyErr::Io)`), Haskell, Swift (`.map(Optional.some)`) and Scala all accept this. Models emit it by reflex. Each rejection costs a full compile-fix round trip.
  > 3. **Tokens.** `xs.map(Some)` is about 5 tokens. `xs.map(fn(x) { Some(x) })` is about 12. The pattern is common in `Result` pipelines (`map_err(AppError.Io)`).
  > 4. **The diagnostic stays good.** The bad case (`let f = Some`) is E0301 with an annotation repair, the same message a model already sees for `let f = identity`. One message shape for two cases.
  >
  > **Risk.** Brace variants become the one exception. That exception has a reason the reader can see in the declaration (no field order), so a model can derive it, not memorize it.
  >
  > ## aiml-2 (fallback): keep the current rule, but write it in the spec
  >
  > If the panel rejects aiml-1, §3.4 must state: "A variant with a payload is not a function value; name it in a closure." Today the compiler enforces a rule the spec does not contain. A model that reads only the spec cannot predict E0300, and the §3.4 rationale text predicts the opposite. That is the worst state for learnability. aiml-2 also needs the §3.4 rationale reworded, as it argues against this exact rule.
  >
  > **Cross-language.** Kotlin and TS reject constructors as values. They are the minority, and they have no η-expansion rule in their spec to contradict.

- **Minimalism:**

  > My default is "reject". I do not take it here. The current rule is not "less language". It is one more rule: a filter, plus its own error message and help text, that §3.4 already deleted for generic fns. The rationale there ("a rule that distinguishes a term from its own η-expansion is a syntactic filter") applies word for word. Keeping the filter for constructors keeps a second answer to one question. Subtraction says: remove it.
  >
  > ## min-1 (preferred): a positional-payload constructor is a generic fn, and §3.4 covers it
  >
  > No new typing rule. One sentence in §3.5 (variants), next to the §3.4 paragraph:
  >
  > > A variant with a positional payload names a function from its payload types to its enum type, with the enum's type parameters as binders. Named as a value, it follows §3.4 *A generic function named as a value*.
  >
  > ```blink
  > type Tree {
  >     Leaf(Int)
  >     Node(Tree, Tree)
  >     Empty
  > }
  >
  > fn main() {
  >     let xs = [1, 2, 3]
  >     let opts = xs.map(Some)                   // fn(Int) -> Option[Int]; T fixed by map's parameter
  >     let leaves = xs.map(Tree.Leaf)            // fn(Int) -> Tree
  >     let mk: fn(Tree, Tree) -> Tree = Tree.Node
  >     let r: fn(Str) -> Result[Str, Int] = Ok   // T = Str, E = Int from the annotation
  >     io.println("{opts.len()} {leaves.len()}")
  > }
  > ```
  >
  > Per form:
  > - **`Some`, `Ok`, `Err`, `Option.Some`, `Result.Ok`**: `fn(T) -> Option[T]`, `fn(T) -> Result[T, E]`, `fn(E) -> Result[T, E]`. Binders come from the expected type. `let f = Some` with no expected type is E0301 at the reference, help: annotate `let f: fn(Int) -> Option[Int] = Some`. Same code, same repair as `let f = identity`.
  > - **Multi-field `Tree.Node`**: `fn(Tree, Tree) -> Tree`. Blink fns take several parameters, so no tuple trick (unlike OCaml).
  > - **Brace payload `Shape.Circle`**: not a fn value. It has no positional call form, so it names no function. Error stays E0300: "variant `Shape.Circle` has named fields and is not a function value", help: `fn(r) { Shape.Circle { radius: r } }`.
  > - **No-payload `None`, `Tree.Empty`**: unchanged; a value of the enum type.
  > - **Bare `Leaf`**: E0554 UnqualifiedVariant first, as the new ruling says. No change.
  > - **`Ok()` zero-arg form**: not in the spec (I grepped: no `Ok()` in sections/). As a value `Ok` has one type, `fn(T) -> Result[T, E]`; there are no overloads, so `fn() -> Result[(), E]` does not match (E0300). The compiler-only `Ok()` needs its own ticket: spec it or remove it.
  >
  > Spec/code changes: one sentence above; delete the "is not a function value" case for positional payloads; the test file flips from error to pass, and keeps the brace-payload row as an error.
  >
  > Tradeoff: one fewer rule, one fewer help text to teach. The cost is in codegen (a thunk per instantiation), which mono already pays for generic fn values. Interaction risk is small: the form reuses §3.4 whole, so no new binder or inference path.
  >
  > ## min-2 (fallback): keep the current rule, but write it in the spec
  >
  > If the panel keeps the filter, the spec must say so. One sentence plus the E0300 example. A rule the compiler enforces and the spec omits is the worst of both. I vote against this: it keeps what §3.4 called a syntactic filter.
  >
  > ## Out of scope, flagged
  >
  > Static methods (`xs.map(Duration.ms)`): spec silent; gen1 today gives a confusing E0301 on the `let`, not on the reference. Do not widen this ticket. File it as its own question.
  >
  > ## Cross-language
  >
  > Rust, Haskell, Swift (`.map(Optional.some)`): constructors are fns. Go and Lua have no sum-type constructors to compare. Kotlin needs `::Leaf`, which is extra syntax; min-1 adds none.

#### Phase B — Debate highlights

One round. Each seat read all six Phase A texts and answered seven variations inside the shared rule: the `Ok()` zero-argument form, bare `Ok` against `fn() -> Result[(), E]`, a no-payload variant where a fn is expected, where the text goes, a labelled positional payload, static methods as values, and the brace-payload message. All six seats still backed their first choice and were ready to vote. Web withdrew "the same edit should add `Ok()`"; PLT withdrew "labelled fields" for "named fields"; Sys withdrew the help "write `Ok()`"; Min conceded the §3.4 placement. PLT objected to deleting the arity diagnostic, which became Q5.

- **Systems:**

  > I still back FN (sys-1). All six seats agree on it; the open points are edges.
  >
  > 1. **`Ok()`.** Out of this ruling. Agree with min: "The compiler-only `Ok()` needs its own ticket: spec it or remove it." This ruling should say only that, as a value, `Ok` has one type, `fn(T) -> Result[T, E]`. Writing `Ok()` into the spec here would decide a second question with no debate.
  > 2. **Bare `Ok` against `fn() -> Result[(), E]`.** I withdraw my help "write `Ok()`". It answers the wrong shape, since the expected type is a fn. I take plt's: a plain type mismatch (E0300), help `fn() { Ok() }`, if item 1 keeps `Ok()`. If `Ok()` is removed, the help becomes `fn() { Ok(()) }`.
  > 3. **No-payload variant where a fn is expected.** Agree with plt: plain type mismatch, help `fn() { Color.Red }`. It is not `fn() -> Color`. One C value, no thunk.
  > 4. **Where.** The normative paragraph in §3.4 after the generic-fn rule, plus min's one-sentence cross-reference in the variants section. Both, not one or the other.
  > 5. **Labelled positional payload.** Agree with plt: `fn(Float, Int) -> Figure`, labels drop. §3.5 already allows a positional argument in a paren payload ("A paren payload with a positional argument keeps the argument-count `TypeError`"), so declaration order is already load-bearing there. The thunk is the same C function as for an unlabelled payload.
  > 6. **Static methods.** Separate ticket. Do not widen.
  > 7. **Brace message.** I object to plt's "variant `Shape.Circle` has labelled fields and is not a function value". By item 5, `Figure.Circle(radius: Float, tag: Int)` also has labelled fields and *is* a fn value, so that text contradicts the rule. Use "named fields" in the brace-only sense, as web, devops, aiml and min wrote: "variant `Shape.Circle` has named fields and is not a function value", help `fn(r) { Shape.Circle { radius: r } }`. Better still is "has a brace payload", which names the form exactly.
  >
  > Codegen note, unchanged from Phase A: each used (variant, instantiation) gives one synthesized C function with an empty env, the same code as the closure. No runtime cost, and no new mono path.
  >
  > STATUS: ready to vote

- **Web/Scripting:**

  > I still back FN (web-1). Six of six first choices agree; the debate is only about edges.
  >
  > 1. **`Ok()` form.** I concede to min. My Phase A text ("the same edit should add it") widens this ruling. Whether `Ok()` exists at all is a separate question, and it has its own design cost (a second spelling of `Ok(())`). This ruling says only: as a value, `Ok` is the one-argument form. File a separate ticket for `Ok()`.
  >
  > 2. **Bare `Ok` against `fn() -> Result[(), E]`.** E0300. I object to sys's help "write `Ok()`": the expected type is a fn, so `Ok()` (a `Result`) does not fit either, and it leans on a form the spec does not have. Use plt's closure shape, but with the specced spelling: help `fn() { Ok(()) }`. If the `Ok()` ticket later specs that form, the help can change with it.
  >
  > 3. **No-payload variant against `fn() -> Color`.** Support plt: plain E0300, help `fn() { Color.Red }`. A JS dev who writes this wanted a thunk; the closure help tells them so.
  >
  > 4. **Placement.** The rule goes in §3.4 after *A generic function named as a value* (it is the same typing rule). Add one line in §3.5 that points to it, so a reader who starts from variants finds it. Both, not either.
  >
  > 5. **Labelled positional payload.** Support plt: `fn(Float, Int) -> Figure`, labels drop. It matches §2 *Limit of the guard* for every other fn value, so no new rule to learn.
  >
  > 6. **Static methods as values.** Separate ticket. Do not widen this one.
  >
  > 7. **Brace-payload text.** "named fields" over "labelled fields": it is the plain word, and the spec's own brace form calls them fields. Message: "variant `Shape.Circle` has named fields and is not a function value"; help `fn(r) { Shape.Circle { radius: r } }`. Code stays E0300.
  >
  > STATUS: ready to vote

- **PLT:**

  > I still back FN (plt-1). All six seats reach the same typing rule, and no seat has given a soundness objection.
  >
  > 1. **`Ok()`.** This ruling should say one thing only: the value `Ok` has one principal type, `fn(T) -> Result[T, E]`. Whether `Ok()` exists as a call form is a separate question about call syntax. It does not affect this rule. I agree with min: "spec it or remove it" gets its own ticket. Web's "same edit" would bundle an unvoted call-syntax rule into a value-typing ruling.
  > 2. **Bare `Ok` against `fn() -> Result[(), E]`.** This is a type mismatch, and a mismatch is E0300 TypeError, so sys, min and I agree on the code. The help must name a term of the expected type, `fn() { Ok() }`. Sys's "write `Ok()`" is correct, but for a different case: the expected type `Result[(), E]` (`let r: Result[(), Str] = Ok`). Both cases should be in the spec, each with its own help. Writing `Ok()` where a fn is expected would give a second mismatch.
  > 3. **No-payload variant against a fn type.** E0300 mismatch, help `fn() { Color.Red }`. A nullary variant is a value, not a thunk, so `Color.Red` and `fn() { Color.Red }` are different terms. The η-argument does not apply here.
  > 4. **Placement.** The typing rule goes in §3.4 next to its sibling, because it is the same judgement. §3.5 gets min's one-sentence cross-reference. These two do not conflict, so use both.
  > 5. **Labelled positional payload.** The labels drop, as for any fn value (§2 *Limit of the guard*). No seat disagrees, and the spec should state it.
  > 6. **Static methods.** Out of scope; give them their own ticket. §3.4 covers "a generic function's name". A static method is a path, not a binding, so the answer is not automatic.
  > 7. **Brace message.** Use "named fields". sections/ uses that term (03_types.md: 3 hits; "labelled fields": 0). So: "variant `Shape.Circle` has named fields and is not a function value", help `fn(r) { Shape.Circle { radius: r } }`. I withdraw my "labelled".
  >
  > I object to one line in web: "Delete the 'takes N argument(s) and is not a function value' diagnostic for positional variants." I agree with the intent. But E0300 stays the code for an arity mismatch against an expected fn type, for example `Tree.Node` where `fn(Tree) -> Tree` is expected. The ruling should say "narrow the message", not "delete the diagnostic".
  >
  > STATUS: ready to vote

- **DevOps:**

  > I still back FN (devops-1). All six seats agree on the core. The variations are diagnostic detail, so I take each one.
  >
  > 1. **`Ok()`.** It stays a call form. This ruling should not spec it or remove it. I agree with min: "The compiler-only `Ok()` needs its own ticket: spec it or remove it." The web line "the same edit should add it" pulls a separate question into this vote. This ruling only needs: "as a value, `Ok` is the one-argument constructor."
  > 2. **Bare `Ok` against `fn() -> Result[(), E]`.** E0300, a type mismatch "expected `fn() -> Result[(), E]`, found `fn(T) -> Result[T, E]`". Help: plt's `fn() { Ok() }`, not sys's "write `Ok()`". `Ok()` there is a `Result` value, not a fn, so the sys help gives a second error if a user or tool applies it as written. A help line must compile when applied.
  > 3. **No-payload variant against a fn type.** Plain E0300 mismatch, help `fn() { Color.Red }` (plt). The same reason as 2 applies.
  > 4. **Where the text goes.** §3.4, a paragraph after the generic-fn rule, plus a one-line pointer from §3.5. The E0301 text and help live in §3.4, and a reader who hits the error looks there.
  > 5. **Labelled positional payload.** I agree with plt: `fn(Float, Int) -> Figure`. §3.5 (03_types.md:2346) already allows a positional call to `Figure.Circle(radius:, tag:)`, so the η-expansion exists. A field reorder already breaks those positional callers. The value form adds no new hazard. My Phase A reorder concern applies only to brace payloads.
  > 6. **Static methods.** Separate ticket, do not widen this one. min's measured fact (E0301 reported on the `let`, not the reference) is a diagnostic bug worth its own row.
  > 7. **Brace-payload message.** Use "named fields". The §3.5 heading and §2.14 call them fields. "labelled" is the word for paren payloads (2346), so plt's text would mix up the two forms. Qualified name in the message: "variant `Shape.Circle` has named fields and is not a function value"; help `fn(r) { Shape.Circle { radius: r } }`.
  >
  > STATUS: ready to vote

- **AI/ML:**

  > I still back FN (aiml-1). All six seats agree on it. What is left to settle is wording.
  >
  > **1. `Ok()`.** I agree with min: this ruling says only that `Ok` *as a value* is `fn(T) -> Result[T, E]`. Whether to spec `Ok()` or remove it goes to its own ticket. Adding a call form here widens the ticket. But a form the compiler accepts and the spec omits is a gap a model cannot learn, so that ticket must be filed, not just noted.
  >
  > **2. Bare `Ok` against `fn() -> Result[(), E]`.** This is a plain type mismatch (E0300). It is not a special case. I object to the help text in sys ("write `Ok()`") and in plt ("`fn() { Ok() }`"). Both teach a form that sections/ does not contain (min grepped and found no `Ok()`). A help line is training data. It must use only spec forms: `fn() { Ok(()) }`. If the `Ok()` ticket later specs the short form, the help can change then.
  >
  > **3. No-payload variant where a fn is expected.** Agree with plt: a plain type mismatch, help `fn() { Color.Red }`.
  >
  > **4. Where the text goes.** Both. The rule goes in a §3.4 paragraph after *A generic function named as a value* (sys, plt, web). Add one sentence in §3.5 (min's text) that points at it. A model that reads only the variants section must find the rule there, and a model that reads only §3.4 must find it there too. This costs one line.
  >
  > **5. Labelled positional payload.** Agree with plt: `fn(Float, Int) -> Figure`, labels drop. The spec should say this in the §3.4 paragraph, because a model will ask.
  >
  > **6. Static methods.** Separate ticket (devops, min). Do not widen.
  >
  > **7. Brace message.** Use the spec's own term. sections/03_types.md:3041-3042 says "variant with named fields". sections/ has no "labelled fields". So use min's text: "variant `Shape.Circle` has named fields and is not a function value", help `fn(r) { Shape.Circle { radius: r } }`. I object to plt's "labelled fields": a second term for one idea makes a reader search for two things.
  >
  > STATUS: ready to vote

- **Minimalism:**

  > I still back FN (min-1). All six seats agree on the core. My job now is to keep the edit small.
  >
  > 1. **`Ok()`.** Oppose web's "the same edit should add it." `Ok()` is a second spelling of `Ok(())`. That is a decision point, the kind Principle 2 removes, and this ticket did not ask about it. Writing it into the spec as part of this ruling would add surface with no debate. The FN text must not depend on it: "As a value, `Ok` has one type, `fn(T) -> Result[T, E]`." Whether to spec or remove `Ok()` (src/typecheck.bl:17774: "`Ok()` is `Ok(())`") is its own ticket. Not blocking.
  > 2. **Bare `Ok` against `fn() -> Result[(), E]`.** E0300 is a plain type mismatch. No special rule. On the help text: sys's "write `Ok()`" and plt's `fn() { Ok() }` both teach a form the spec does not have. If a help line is needed, use `fn() { Ok(()) }`. aiml is right that `Ok` fits `fn(()) -> Result[(), E]`. That follows from the rule and needs no text.
  > 3. **No-payload variant where a fn is expected.** A plain mismatch, as plt says. The spec sentence "never `fn() -> E`" is enough. No new help rule.
  > 4. **Where.** I concede: a §3.4 paragraph after the generic-fn one. It should be short (rule, one example, brace exclusion), plus a one-line cross-reference in the variants section.
  > 5. **Labelled positional payload.** Agree with plt: `fn(Float, Int) -> Figure`, and the labels drop. §3.5 line 2346 already allows positional arguments for a paren payload, so the paren form already has an order. Brace does not. That is the line.
  > 6. **Static methods.** Separate ticket, as devops and I said. Do not widen this one.
  > 7. **Brace message.** Use the spec's own term, "named fields" (§3.5 grammar line 3041: "variant with named fields"). Not plt's "labelled fields": in §3.5 "labelled" means a paren payload with labels (line 2346), which this rule makes a value. Calling the brace form "labelled" would contradict that. Text: "variant `Shape.Circle` has named fields and is not a function value", help `fn(r) { Shape.Circle { radius: r } }`.
  >
  > KEEP: oppose, for the reason all six gave.
  >
  > STATUS: ready to vote

#### Phase C — Final vote

Each seat voted alone on a silent ballot.

- **Q1: A payload variant named with no argument list** (6-0, for A)

  > **Q1. A payload variant named with no argument list.**
  > - A: FN. A variant with a positional payload, named with no argument list, is a fn value of type `fn(P1, ..., Pn) -> E[binders]` (n parameters, not a tuple; empty effect row), with binders solved by §3.4 *A generic function named as a value* (nothing fixes them = E0301 at the reference). Labels of a labelled positional payload drop (`Circle(radius: Float, tag: Int)` is `fn(Float, Int) -> Figure`). A brace-payload variant is not a fn value: E0300, message "variant `Shape.Circle` has named fields and is not a function value", closure help. A no-payload variant stays a value of the enum, never `fn() -> E`. As a value, `Ok` is only the one-argument form. A bare user variant is still E0554 first. Text: a new §3.4 paragraph after the generic-fn rule, plus a one-line pointer in the variants section. Static methods as values: out of scope (separate ticket).
  > - B: KEEP. Keep today's rule and state it in the spec.

  - **Systems:** A

    > **Q1.** **Vote:** A
    > **Reasoning:** A constructor value compiles to one synthesized C function per used instantiation with an empty env. That is the same code as `fn(x) { Some(x) }`, so the current rule refuses a spelling with an identical output and no cost difference. FN reuses the existing generic-fn solve path and mono dedup, so codegen gains no new path. The brace exclusion keeps declaration order from becoming load-bearing where the source form says it is not.
    > **Concern:** The thunk synthesis must key on (variant, full instantiation) and dedup with the closure path, or each `map(Some)` site emits its own copy and code size grows.

  - **Web/Scripting:** A

    > **Q1. Vote: A (FN)**
    > Reasoning: `xs.map(Some)` is what Rust, Swift and Python devs already write, and a callable name that cannot be passed is a surprise with no payoff. §3.4 already made this call for generic fns: the closure repair means the same program, so refusing the short form is friction for its own sake. One rule ("a callable name with no argument list is a fn value") is less to learn than two.
    > Concern: `let f = Some` still fails (E0301) while `xs.map(Some)` works, and users will ask why unless the E0301 help shows the annotation clearly.

  - **PLT:** A

    > **Q1.** **Vote:** A
    > **Reasoning:** A positional constructor and its η-expansion are the same term. §3.4 already says the spec must not tell them apart, and its rationale applies to constructors word for word. A adds no new judgement. It reuses the generic-fn rule, so it composes with HM metavars and with E0301 placement as is. B keeps a filter without a typing reason, and it contradicts the paragraph next to it.
    > **Concern:** When nothing fixes `E`, `xs.map(Ok)` reports E0301, and the spec text must show that case clearly, or readers will think it is a bug.

  - **DevOps:** A

    > **Q1. Vote: A (FN)**
    > Reasoning: Today's E0300 help gives a repair that means the same program, which §3.4 already calls noise. Under FN, the bad case (`let f = Some`) reports E0301 at the reference with an annotation help. That is the same message shape a user already sees for `let f = identity`, so tools and readers learn one diagnostic, not two. LSP hover gets a real type (`fn(Int) -> Tree`) for a constructor name, the same as rust-analyzer shows for a tuple variant.
    > Concern: `xs.map(Ok)` almost always leaves `E` unfixed, so E0301 on `Ok` becomes a common error; its help must name a concrete annotation, not a bare "annotate the binding".

  - **AI/ML:** A

    > ## Q1
    > **Vote:** A
    > **Reasoning:** §3.4 already teaches that a name and its closure wrapper mean the same program, so a model that learns the spec will predict `xs.map(Some)` works. FN makes that prediction true and removes an exception a reader must memorize. Models write `map(Some)` and `map_err(AppError.Io)` by reflex from Rust, Haskell and Swift, and FN saves about 7 tokens and a compile-fix cycle each time. The one exclusion (brace payload) has a reason a reader can see in the declaration.
    > **Concern:** If the §3.4 paragraph does not show the E0301 case (`let f = Some`) with its annotation repair, models will write the bare binding and get an error they do not expect.

  - **Minimalism:** A

    > **Q1.** Vote: **A** (FN)
    > Reasoning: The current rule is not less language. It is one extra filter with its own message and help, and §3.4 already deleted that filter for generic fns. FN removes a special case and adds no syntax, no new inference path and no new code. It reuses §3.4 whole. The brace exclusion is visible in the declaration, so a reader does not need to memorize it.
    > Concern: The thunk-per-instantiation codegen and the brace/positional split could grow special cases in the compiler that the one-paragraph spec text does not show.

- **Q2: The `Ok()` zero-argument form** (6-0, for A)

  > **Q2. The `Ok()` zero-argument form (if Q1 = A).**
  > - A: Not in this ruling. A separate ticket decides whether to write `Ok()` into the spec or remove it (min; B1: sys, web, plt, devops, aiml).
  > - B: The same edit writes `Ok()` into the spec as a call-only short form for `Ok(())` (web Phase A, withdrawn in B1).

  - **Systems:** A

    > **Q2.** **Vote:** A
    > **Reasoning:** `Ok()` is a separate question: spec it or remove it. Deciding it here would settle a second surface with no debate. This ruling needs only "as a value, `Ok` has one type".
    > **Concern:** The follow-up ticket may sit, leaving a compiler-only form that the spec still does not name.

  - **Web/Scripting:** A

    > **Q2. Vote: A (separate ticket)**
    > Reasoning: whether `Ok()` exists is its own design question with its own cost (a second spelling of `Ok(())`). Folding it into this ruling widens scope and skips the debate it needs. This ruling only needs "as a value, `Ok` is the one-argument form."
    > Concern: the compiler keeps an unspecced `Ok()` until that ticket lands, and examples in the wild may spread it first.

  - **PLT:** A

    > **Q2.** **Vote:** A
    > **Reasoning:** `Ok()` is a question about call syntax. It has no effect on the principal type of the value `Ok`. If this ruling also decided it, the value-typing vote would carry a call form that no seat proposed as part of it.
    > **Concern:** The separate ticket can go stale, and then `Ok()` stays a compiler-only form for a long time.

  - **DevOps:** A

    > **Q2. Vote: A (separate ticket)**
    > Reasoning: `Ok()` is a compiler-only form that the spec does not name. Whether to keep it is its own question, and putting it into this edit carries an unvoted surface change on the back of a different ruling. This ruling needs only "as a value, `Ok` is the one-argument form".
    > Concern: the separate ticket may sit open, so the compiler keeps an unspecified form longer than it should.

  - **AI/ML:** A

    > ## Q2
    > **Vote:** A
    > **Reasoning:** Adding a call form widens the ticket. But the compiler accepts `Ok()` and the spec does not mention it, and a model cannot learn a form that is not in the spec. So the separate ticket must be filed now, not left as a note.
    > **Concern:** The `Ok()` ticket may sit unresolved, and the form stays in compiler output that models train on.

  - **Minimalism:** A

    > **Q2.** Vote: **A** (separate ticket)
    > Reasoning: `Ok()` is a second spelling of `Ok(())`, which is a decision point, and this ticket did not debate it. Putting it into the spec as a side effect would add surface with no vote of its own. The FN text does not depend on it.
    > Concern: The separate ticket could sit unworked, so the compiler keeps accepting a form the spec does not have.

- **Q3: Bare `Ok` where `fn() -> Result[(), E]` is expected** (6-0, for A)

  > **Q3. Bare `Ok` where `fn() -> Result[(), E]` is expected (if Q1 = A).** All seats: a type mismatch (E0300). The help line:
  > - A: `fn() { Ok(()) }` (web, aiml, min).
  > - B: `fn() { Ok() }` (plt; sys and devops in B1).

  - **Systems:** A

    > **Q3.** **Vote:** A
    > **Reasoning:** I change from my B1 position. With Q2 = A, `Ok()` is not in the spec, so a help line must not teach it. `fn() { Ok(()) }` is spec-legal under either outcome of the follow-up ticket and compiles to the same code.
    > **Concern:** If the follow-up specs `Ok()`, this help line reads longer than needed, but it stays correct.

  - **Web/Scripting:** A

    > **Q3. Vote: A (`fn() { Ok(()) }`)**
    > Reasoning: a help line should only show forms the spec has. `Ok(())` is specced; `Ok()` is not, and Q2 leaves it undecided. If the `Ok()` ticket specs the short form, the help can change with it.
    > Concern: if `Ok()` is later specced, this help will look clumsy until someone updates it.

  - **PLT:** A

    > **Q3.** **Vote:** A
    > **Reasoning:** I change from my B1 text. Q2 sends `Ok()` to a separate ticket, so a help line must not use a form that ticket may remove. `fn() { Ok(()) }` is in the spec now, and it stays correct whichever way that ticket goes. A help line has to name a term the spec guarantees.
    > **Concern:** If the separate ticket keeps `Ok()`, the help may look longer than it needs to be. That is a cosmetic cost only.

  - **DevOps:** A

    > **Q3. Vote: A (`fn() { Ok(()) }`)**
    > I change from my B1 line. With Q2 = A, `Ok()` is not in the spec, and the separate ticket may remove it. A help line must compile when applied in every future state of the spec. `Ok(())` is in the spec and always will be, while `fn() { Ok() }` could become a broken repair the day that ticket lands.
    > Concern: users who write `Ok()` today may read `Ok(())` in the help as a hint that `Ok()` is wrong.

  - **AI/ML:** A

    > ## Q3
    > **Vote:** A
    > **Reasoning:** A help line is training data, so it must use only forms that are in the spec. `Ok()` is not in sections/. `fn() { Ok(()) }` is correct today under any outcome of the Q2 ticket.
    > **Concern:** If the Q2 ticket later specs `Ok()`, the help text must change too, and nothing ties the two edits together.

  - **Minimalism:** A

    > **Q3.** Vote: **A** (`fn() { Ok(()) }`)
    > Reasoning: A help line must teach only forms the spec has. `Ok()` is not in sections/, so a help that shows it teaches unspecified surface. `Ok(())` is correct under any outcome of the Q2 ticket.
    > Concern: If the Q2 ticket later specs `Ok()`, someone must remember to revisit this help text.

- **Q4: A no-payload variant where a fn is expected** (6-0, for A)

  > **Q4. A no-payload variant where a fn is expected (`Color.Red` against `fn() -> Color`) (if Q1 = A).** All seats: a plain type mismatch.
  > - A: With help `fn() { Color.Red }` (plt; web, sys, devops, aiml in B1).
  > - B: No help line; the spec sentence "never `fn() -> E`" is enough (min B1).

  - **Systems:** A

    > **Q4.** **Vote:** A
    > **Reasoning:** The help costs nothing and gives the one repair that compiles. The no-payload variant is a plain constant in C; the closure is the only way to get a `fn() -> Color`, and saying so saves a round trip.
    > **Concern:** None from my seat; the risk is only message drift if the help text and spec examples diverge.

  - **Web/Scripting:** A

    > **Q4. Vote: A (help `fn() { Color.Red }`)**
    > Reasoning: a dev who passes `Color.Red` where a fn is expected wanted a thunk; the help shows them the one-line fix. Spec sentences do not reach a user staring at an error; help lines do. It costs nothing.
    > Concern: none of substance; at worst the help is redundant for an expert.

  - **PLT:** A

    > **Q4.** **Vote:** A
    > **Reasoning:** A no-payload variant is a value, not a fn of no arguments, so `Color.Red` and `fn() { Color.Red }` are different terms. A help line that names the second term shows that difference. The help names the correct term, and it does not weaken the rule.
    > **Concern:** Users may read the help as proof that a no-payload variant "almost" is a fn of no arguments.

  - **DevOps:** A

    > **Q4. Vote: A (help `fn() { Color.Red }`)**
    > Reasoning: A spec sentence does not reach the user at the error site. The diagnostic does. A mismatch of "expected `fn() -> Color`, found `Color`" without a fix makes the user work out the thunk themselves, and the repair is mechanical, so the tool should give it.
    > Concern: none of weight; a help on a plain mismatch can look like the tool suggests wrapping values in thunks as an idiom.

  - **AI/ML:** A

    > ## Q4
    > **Vote:** A
    > **Reasoning:** A help line that shows the repair costs nothing and gives a model a fix it can apply at once. A bare mismatch makes the model look up the spec sentence first.
    > **Concern:** Low. The help could fire in contexts where the user meant a different value and not a thunk.

  - **Minimalism:** A

    > **Q4.** Vote: **A** (help `fn() { Color.Red }`)
    > Reasoning: I concede. A help line is diagnostic surface, not language surface, and it costs the spec one example line at most. My B1 point was only that no new rule is needed, and A adds none.
    > Concern: A help that suggests a closure for every no-payload mismatch could fire in cases where the user meant something else, such as a missing call on a fn.

- **Q5: The existing "takes N argument(s) and is not a function value" diagnostic** (6-0, for A)

  > **Q5. The existing "takes N argument(s) and is not a function value" diagnostic for positional variants (if Q1 = A).**
  > - A: Narrow it: E0300 stays the code for an arity mismatch against an expected fn type (for example `Tree.Node` where `fn(Tree) -> Tree` is expected); only the "not a function value" message goes for positional variants (plt B1).
  > - B: Delete the diagnostic for positional variants (web Phase A).

  - **Systems:** A

    > **Q5.** **Vote:** A
    > **Reasoning:** An arity mismatch against an expected fn type is a real type error and must keep a code; `Tree.Node` against `fn(Tree) -> Tree` must not compile. Only the "not a function value" claim becomes false for positional variants, so only that message goes. Deleting the whole diagnostic would leave the arity case with no named report.
    > **Concern:** The narrowed message must print both fn types (expected and found) so the arity gap is visible, not a generic "type mismatch".

  - **Web/Scripting:** A

    > **Q5. Vote: A (narrow)**
    > Reasoning: my Phase A "delete" meant the "not a function value" message, not the code. An arity mismatch like `Tree.Node` against `fn(Tree) -> Tree` is still a type mismatch and should read like every other E0300, naming both fn types. Narrowing says that precisely.
    > Concern: the arity-mismatch message must show both fn types side by side, or users will not see that the count is what differs.

  - **PLT:** A

    > **Q5.** **Vote:** A
    > **Reasoning:** An arity mismatch against an expected fn type is a type error that the rule still produces, and E0300 is its code. Only the "not a function value" claim becomes false for positional variants, so only that message goes.
    > **Concern:** The narrowed message for a positional variant must print both fn types, or the arity mismatch will be hard to read.

  - **DevOps:** A

    > **Q5. Vote: A (narrow)**
    > Reasoning: An arity mismatch against an expected fn type (`Tree.Node` where `fn(Tree) -> Tree` is expected) still needs a precise E0300 that names both fn types. Delete only the "is not a function value" text for positional variants. Deleting the whole diagnostic risks a generic or worse message on a real error.
    > Concern: the implementation may keep a variant-specific code path for the arity case when the general fn-type mismatch already prints it; it should go through the one mismatch printer.

  - **AI/ML:** A

    > ## Q5
    > **Vote:** A
    > **Reasoning:** An arity mismatch against an expected fn type is a real error and needs a diagnostic. Narrowing keeps one code (E0300) for one defect. Deleting it leaves the case with no clear message, which an agent then has to guess at.
    > **Concern:** The arity-mismatch message must name both fn types, or a model cannot tell which side to fix.

  - **Minimalism:** A

    > **Q5.** Vote: **A** (narrow)
    > Reasoning: An arity mismatch against an expected fn type is an ordinary type mismatch, so E0300 is the right code without any constructor-specific rule. A states that plainly. B reads as if positional constructors lose all diagnostics, which is not what anyone meant.
    > Concern: The narrowed message could keep a constructor-specific wording branch in the compiler when the generic fn-type mismatch text would serve.

### Final Spec

```blink
type Tree {
    Leaf(Int)
    Node(Tree, Tree)
    Empty
}

type Shape {
    Circle { radius: Float }
    Point
}

type Color { Red, Green }

fn main() {
    let xs = [1, 2, 3]
    let opts = xs.map(Some)                         // OK -- fn(Int) -> Option[Int]
    let leaves = xs.map(Tree.Leaf)                  // OK -- fn(Int) -> Tree
    let mk: fn(Tree, Tree) -> Tree = Tree.Node      // OK -- two parameters, not a tuple
    let rs: List[Result[Int, Str]] = xs.map(Ok)     // OK -- the annotation fixes E = Str

    let f = Some                                    // error[E0301] at the reference
                                                    // help: annotate the binding: `let f: fn(Int) -> Option[Int] = Some`
    let c = Shape.Circle                            // error[E0300]: variant `Shape.Circle` has named fields and is not a function value
                                                    // help: write `fn(r) { Shape.Circle { radius: r } }`
    let r: fn() -> Color = Color.Red                // error[E0300]: a type mismatch
                                                    // help: write `fn() { Color.Red }`
    let k: fn() -> Result[(), Str] = Ok             // error[E0300]: a type mismatch
                                                    // help: write `fn() { Ok(()) }`
    let g: fn(Tree) -> Tree = Tree.Node             // error[E0300]: a type mismatch (arity)
    let l = Leaf                                    // error[E0554]: variant `Leaf` needs its enum in an expression
}
```

- A variant with a positional payload, named with no argument list, is a fn value of type `fn(P1, ..., Pn) -> E[binders]`: n parameters, not a tuple, and an empty effect row.
- §3.4 *A generic function named as a value* solves the binders. When nothing fixes them, it is E0301 at the reference (`let f = Some`; `xs.map(Ok)` with `E` unfixed), and the help names an annotation.
- A labelled positional payload drops its labels: `Circle(radius: Float, tag: Int)` gives `fn(Float, Int) -> Figure`.
- A variant with named fields (a brace payload) is not a fn value: E0300, "variant `Shape.Circle` has named fields and is not a function value", help `fn(r) { Shape.Circle { radius: r } }`.
- A no-payload variant stays a value of the enum, never `fn() -> E`. Where a fn is expected, it is E0300 with help `fn() { Color.Red }`.
- As a value, `Ok` is only the one-argument form. Where `fn() -> Result[(), E]` is expected, it is E0300 with help `fn() { Ok(()) }`.
- E0300 stays the code for an arity mismatch against an expected fn type. Only the "not a function value" message goes for positional variants.
- A bare user variant is still E0554 first.
- Out of this ruling: the `Ok()` zero-argument form, and static methods named as values. Each is a separate question.

Concerns the panel raised, answered in the spec text:

- The §3.4 paragraph shows the E0301 case (`let f = Some`, and `xs.map(Ok)` with `E` unfixed) with a concrete annotation repair (Web, AI/ML, PLT, DevOps).
