[< All Decisions](../DECISIONS.md)

# Collection Methods — Design Rationale

### Panel Deliberation

Five panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML) voted independently on 5 questions. Each expert ran as a separate agent and returned votes without seeing other experts' reasoning.

**Q1: Trait organization — per-type vs generic shared vs hybrid (5-0 for hybrid: shared Contains + per-type)**

- **Systems:** Hybrid. `Contains[T]` is justified — containment has identical semantics across collections. But `Indexable[K,V]` or `Growable[T]` are false unifications: `List.get(Int)` and `Map.get(K)` have fundamentally different memory access patterns (contiguous vs hash lookup). Per-type traits let the C backend emit type-specific code without trait dispatch indirection for hot-path operations.
- **Web/Scripting:** Hybrid. Web devs expect `contains`/`includes` to work uniformly across collections — Python's `in`, JS's `.includes()/.has()`. Per-type for the rest because List, Map, and Set have genuinely different semantics (push vs insert-with-key); forcing them into shared abstractions creates leaky APIs.
- **PLT:** Hybrid. A pure per-type approach misses shared algebraic structure (the point of traits). Full generic conflates fundamentally different structures. `Contains[T]` is a legitimate shared predicate (membership testing is universal set-theoretic), while per-type traits handle operations with genuinely different signatures.
- **DevOps:** Hybrid. Shared `Contains[T]` is gold for tooling — LSP resolves `.contains(` once for all collections. Per-type traits keep autocomplete focused. Generic traits like `Indexable` produce confusing diagnostics: "type X doesn't implement Indexable" is harder to act on than "type X doesn't implement MapOps."
- **AI/ML:** Hybrid. Shared `Contains[T]` minimizes generation errors (most common LLM pattern: "is X in collection"). Per-type traits keep method discovery unambiguous — models don't confuse List methods with Map methods.

**Q2: List[T] method surface (3-2 for expanded: 12 methods)**

- **Systems:** 8 methods (Option A). `insert`/`remove` at arbitrary indices are O(n) on contiguous arrays — including them signals they're cheap when they're not. `index_of` and `last` are expressible via iterator methods already in the spec. Keep the core API tight. *(dissent)*
- **Web/Scripting:** 12 methods (Option B). `indexOf`, `splice`/`insert`, `remove`, and `last` are bread-and-butter operations in web code. Leaving them out means everyone writes the same helpers on day one.
- **PLT:** 8 methods (Option A). The 8-method surface covers core algebraic operations on sequences. `insert`/`remove` are O(n) and advertising them as first-class methods violates least-surprise regarding performance. *(dissent)*
- **DevOps:** 12 methods (Option B). `insert`, `remove`, `index_of`, and `last` are methods people reach for constantly. 12 methods is table stakes for a list type. Every time someone hand-rolls these, that's friction and a potential bug.
- **AI/ML:** 12 methods (Option B). LLMs trained on Python/Rust/JS constantly generate `insert`, `remove`, `index_of`, `last`. Omitting them causes hallucinated methods or verbose workarounds.

**Q3: Map[K,V] method surface (3-2 for expanded: 8 methods)**

- **Systems:** 6 methods (Option A). `entries` is sugar for what `IntoIterator` already gives (Map yields `(K, V)` tuples). `get_or_default` is one line with `??`. Six methods keep the vtable small and C codegen simple. *(dissent)*
- **Web/Scripting:** 8 methods (Option B). `entries` is used constantly when iterating maps, and `get_or_default` eliminates the most common Map boilerplate pattern (Python's `dict.get(k, default)`).
- **PLT:** 6 methods (Option A). Maps are finite functions K→V; 6 methods precisely capture CRUD plus canonical projections. `get_or_default` conflates two concerns better expressed as `map.get(k) ?? default`. *(dissent)*
- **DevOps:** 8 methods (Option B). `entries` is critical for iteration and debugging. `get_or_default` eliminates a massive class of "key not found" runtime errors.
- **AI/ML:** 8 methods (Option B). `entries` and `get_or_default` are extremely high-frequency LLM patterns. `get_or_default` eliminates the "check then get" anti-pattern models frequently generate incorrectly.

**Q4: Set[T] method surface (3-2 for core: 4 methods)**

- **Systems:** Core 4 (Option A). `union` is worth including because it's non-trivial to implement correctly in userspace. `intersection`/`difference` are expressible as iterator filter chains. Most code only uses `contains` and `insert`.
- **Web/Scripting:** Core 4 (Option A). Web developers rarely do set algebra beyond union. The 95% case is covered. Set algebra can be added later without breaking anything — YAGNI.
- **PLT:** Full algebra (Option B). Sets form a Boolean algebra under union, intersection, difference, and symmetric difference. Omitting these is like defining a numeric type without subtraction. *(dissent)*
- **DevOps:** Full algebra (Option B). If you're going to have a Set type at all, you need intersection and difference. Without them, developers will roll their own buggy versions. *(dissent)*
- **AI/ML:** Core 4 (Option A). Full set algebra appears rarely in generated code. Small surface means models are less likely to confuse method names and signatures.

**Q5: Construction and mutability (5-0 for `Type.new()` + `let mut`)**

- **Systems:** `Type.new()` + `let mut`. Mutability at the binding, not the type. C backend can emit `const` qualifiers for immutable bindings. Split types double the surface for no gain with GC. Literal-only makes empty construction awkward.
- **Web/Scripting:** `Type.new()` + `let mut`. Most familiar for devs from Rust/Swift/Kotlin, straightforward for JS/Python devs. Split types create confusion and double the API surface. Literal-only breaks the `Type.new()` pattern already in the compiler.
- **PLT:** `Type.new()` + `let mut`. Mutability is a property of the binding, not the type — same insight as ML's `ref`. Split types double the type surface and create trait coherence nightmares (do both implement `Sized`?). `Type.new()` has clear formal semantics.
- **DevOps:** `Type.new()` + `let mut`. LSP flags mutation on non-mut bindings at edit time. `let mut` is greppable, lintable. Split types double surface for autocomplete, docs, and errors. `Type.new()` is unambiguous for tooling.
- **AI/ML:** `Type.new()` + `let mut`. Most consistent with Rust-influenced training data. LLMs handle "declare mutable, then mutate" well. Split types doubles type vocabulary and confuses models.

