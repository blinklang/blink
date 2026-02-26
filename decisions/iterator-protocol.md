[< All Decisions](../DECISIONS.md)

# Iterator Protocol — Design Rationale

### Panel Deliberation

Five panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML) voted independently on 5 questions.

**Q1: Single-method vs multi-method Iterator (3-2 for single)**

- **Systems:** Multi-method (next + size_hint). `size_hint()` enables pre-allocation in `collect()` and `Vec::extend`. Critical for performance-predictable iteration. *(dissent)*
- **Web/Scripting:** Single. JS `[Symbol.iterator].next()` returning `{value, done}` maps to `Option[T]`. `has_next()` creates awkward double-call state. Training data strongly favors single-method.
- **PLT:** Multi-method (next + size_hint). Pragmatic extension that enables fusion without breaking the semantic model. *(dissent)*
- **DevOps:** Single. One required method means simpler derive macros, cleaner LSP completions, better error messages. Size hints can be added later as optional overrides.
- **AI/ML:** Single. Dominant pattern across Rust/Python/JS training data. Split methods require LLMs to coordinate two calls, increasing error rates.

**Q2: IntoIterator separation (5-0 for separate)**

- **Systems:** Separate. Collections shouldn't be consumed by iteration. Fresh cursor each time.
- **Web/Scripting:** Separate. JS distinguishes iterables (`[Symbol.iterator]()`) from iterators (`.next()`). Two loops over same list must both work.
- **PLT:** Separate. Conflating collection with traversal state is a category error. Semantically crucial.
- **DevOps:** Separate. Better error messages: "Vec does not implement Iterator, did you mean `for x in vec`?"
- **AI/ML:** Separate. Clear conceptual boundary LLMs can learn. Matches Rust's ubiquitous pattern.

**Q3: Lazy by default (5-0 for lazy)**

- **Systems:** Lazy. Only model compatible with zero-cost abstractions. `.map().filter().take(10)` on a million elements must not allocate intermediates.
- **Web/Scripting:** Lazy. Modern JS/Kotlin lazy chains are the right default. Token-efficient for AI generation.
- **PLT:** Lazy. Composes with fusion optimizations. Explicit `collect()` gives control.
- **DevOps:** Lazy. Prevents accidental quadratic behavior. Makes pending transformations visible in type signatures.
- **AI/ML:** Lazy. Produces token-efficient pipelines. LLMs excel at fluent chain generation.

**Q4: Adapter method placement (5-0 for default methods)**

- **Systems:** Default methods. Implement `next()`, get combinators free. Performance overrides still possible.
- **Web/Scripting:** Default methods. Web devs expect `.map()` to "just work". Minimum friction.
- **PLT:** Default methods. Natural home for combinators. Mirrors Haskell typeclasses.
- **DevOps:** Default methods. Derive macros trivial (generate `next()` only). One canonical documentation location.
- **AI/ML:** Default methods. Minimizes what LLMs must generate. Heavily represented in training data.

**Q5: Effectful iteration (3-2 for defer to v2)**

- **Systems:** Effects in v1. Effectful iteration is fundamental (file lines, DB cursors). Deferring creates compatibility chasm. *(dissent)*
- **Web/Scripting:** Defer. Async iteration in JS is a separate protocol because mixing has nasty edge cases. Get the simple case right first.
- **PLT:** Effects in v1. Evidence-passing means effectful iterators are just monomorphizations. No runtime burden. *(dissent)*
- **DevOps:** Defer. Effects on lazy iterators add compiler complexity (when does `! IO` fire?). Avoid half-solutions.
- **AI/ML:** Defer. Effectful iterators have virtually no training data. LLMs would hallucinate syntax. Ship pure, add effects when usage patterns emerge.

