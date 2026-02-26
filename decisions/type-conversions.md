[< All Decisions](../DECISIONS.md)

# Type Conversions (From/Into/TryFrom) — Design Rationale

### Panel Deliberation

Five panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML) voted independently on 5 questions.

**Q1: From[T] trait shape (5-0 for single method)**

- **Systems:** Single method `fn from(value: T) -> Self` compiles to a single function pointer in evidence-passing, zero overhead. Into should be auto-derived, not user-implementable — two user-facing traits doubles vtable surface for no gain.
- **Web/Scripting:** Web devs are used to `String(x)`, `Number(x)` style conversion. One method, one direction, dead simple. Auto-derive Into for `.into()` ergonomics but never let users implement it directly.
- **PLT:** Single method is correct. Manual Into would allow incoherent pairs (A: Into[B] without B: From[A]), breaking the categorical dual.
- **DevOps:** Single method, clean. If Into exists as a writable trait, you get two places to look when debugging "why did this conversion happen." LSP should show "derived from From[X] for Y" on hover.
- **AI/ML:** Single method cleanest for LLM generation. Into creates "two ways to do the same thing" — models trained on Rust constantly confuse From vs Into. *(Dissent: wants no Into at all — but 4-1 for auto-derive.)*

**Q2: TryFrom existence and error type (5-0 exists; 3-2 for fixed ConversionError)**

- **Systems:** TryFrom should exist with generic error parameter `TryFrom[T, E]`. A single ConversionError is a runtime-typed escape hatch that undermines the type system. *(Dissent on error type.)*
- **Web/Scripting:** Yes to TryFrom. Concrete ConversionError is fine — don't over-engineer without associated types. A single error type carrying a message is plenty.
- **PLT:** TryFrom yes, but parameterize E on the trait itself: `TryFrom[T, E]`. A fixed ConversionError becomes a god-type that loses information. *(Dissent on error type.)*
- **DevOps:** TryFrom should exist with fixed ConversionError. Per-impl error types create boilerplate cascade — every TryFrom needs a custom error, every call site needs a From impl for that error.
- **AI/ML:** Fixed ConversionError is better than Rust's associated-type approach for LLMs — models frequently botch the error type. One concrete error type = one pattern to learn.

**Q3: Numeric conversion mechanism (4-1 for both methods and traits)**

- **Systems:** Both. Named methods for primitives — discoverable, compile to single instructions. Plus From/TryFrom impls for generic programming. Complementary, not redundant.
- **Web/Scripting:** Both. Named methods are autocomplete-friendly. But From impls needed for generic code.
- **PLT:** Both. Methods for readability, From/TryFrom for generic programming. Methods should be sugar over the trait machinery.
- **DevOps:** Both. LSP autocomplete on `my_int.to_` shows available conversions — that's the primary discovery mechanism. From/TryFrom enables generic conversion functions.
- **AI/ML:** Traits only, no named methods. Named methods create open-ended surface area LLMs hallucinate (`.to_float()` vs `.as_float()` vs `.to_f64()`). Having both violates "one way to do everything." *(Dissent.)*

**Q4: `?` auto-conversion on Err (4-1 for NO)**

- **Systems:** No. A language that rejected implicit conversions shouldn't have `?` silently calling `.into()`. Require exact match. `.map_err()` is explicit and greppable.
- **Web/Scripting:** No. Auto-conversion on `?` is one of Rust's most confusing features for newcomers. Explicit `.map_err()` is more verbose but readable and obvious. Start strict, loosen later.
- **PLT:** No. Makes inference harder — compiler must solve From constraints at every `?` site. Degrades error messages. Violates explicit-over-implicit philosophy.
- **DevOps:** Yes. The spec already showed this pattern. Invest in diagnostic quality — generate "implement From[X] for Y" suggestions and LSP quick-fix actions. *(Dissent.)*
- **AI/ML:** No. LLMs handling Rust's `?` with implicit `.into()` is a mess — models generate code that compiles only because of hidden From impls they didn't reason about.

**Q5: Generic From-bounded code (5-0 valid)**

- **Systems:** Basic bounded polymorphism. Evidence-passing handles it naturally. Standard orphan rules ensure at most one From[Str] impl per type.
- **Web/Scripting:** Standard generic programming, would be bizarre to disallow. Invest in good error messages when the bound isn't satisfied.
- **PLT:** Sound. T determined at call site, coherence maintained. Standard return-type polymorphism.
- **DevOps:** No tooling concerns. LSP can resolve T.from to the From trait and show all satisfying types on hover.
- **AI/ML:** Clean, well-constrained, LLMs generate reliably. Bound makes contract explicit.

