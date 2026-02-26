[< All Decisions](../DECISIONS.md)

# Effect Polymorphism — Design Rationale

### Panel Deliberation

Five panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML) voted independently on 3 questions.

**Q1: Should function types carry effects? (5-0 for explicit effects)**

- **Systems:** The evidence vector is already threaded through every call. If a callback performs effects, that must be in the type so the compiler knows which vtable slots to pass. Hiding it makes C codegen unpredictable. Pure-only means you can't even log inside a map callback — non-starter.
- **Web/Scripting:** Web devs live and breathe HOFs — map, filter, forEach, middleware. If callbacks can't carry effects, the most natural JS/TS patterns become second-class citizens. TypeScript proved function types need full expressiveness. The `!` syntax is consistent with declarations — no new concept.
- **PLT:** A function type that cannot express its effects is unsound by construction. In Koka, Frank, and every serious effect calculus, the arrow type carries an effect row because `fn(T) -> U` and `fn(T) -> U ! IO` have fundamentally different denotations. Omitting effects from function types means the type system cannot express the contract of any HOF accepting effectful callbacks — a compositionality failure.
- **DevOps:** Explicit `! IO.Log` on function types is a massive win for LSP hover and diagnostic quality. When a user hovers over a callback parameter, the tooltip should show exactly what effects it can perform. Invisible semantics would make hover info misleading. Explicit syntax gives the formatter a clear layout rule.
- **AI/ML:** LLMs generate more correct code when syntax is uniform and local. If `fn foo() -> Int ! IO` works at declaration sites but `fn(Int) -> Int` silently drops effects at type sites, that's two rules where there should be one. Every special case increases error rates.

**Q2: Form of effect polymorphism (3-2 for wildcard forwarding)**

- **Systems:** Row-polymorphic effect variables. For C codegen, `e` compiles to "pass through whatever evidence sub-vector the caller provided." Monomorphizer specializes at call sites. Wildcard loses composability — can't distinguish effect sets from two different callback parameters. *(dissent)*
- **Web/Scripting:** Wildcard `_`. Row polymorphism is theoretically correct but `fn map[T, U, e](f: fn(T) -> U ! e) -> Iterator[U] ! e` will make web developers close the tab. The `_` is familiar from TypeScript's `any` and Rust's `_` patterns. Covers the 95% case without requiring developers to understand effect variables.
- **PLT:** Row polymorphism. The only approach that preserves principal types and decidable inference. Wildcard `_` cannot unify two wildcards from different parameters, which breaks `zip_with(f, g)` where both callbacks must share the same effect set. Give the variable a name; it costs one generic parameter and buys full expressiveness. *(dissent)*
- **DevOps:** Wildcard `_`. Row polymorphism produces horrific error messages — effect variable unification errors are nearly impossible for users to parse. `_` covers the 95% case and produces actionable diagnostics. Incremental compilation benefits since `_` is a local marker rather than a constraint variable propagating through the call graph.
- **AI/ML:** Wildcard `_`. Koka-style effect variables have vanishingly small training data. Models will hallucinate variable names, forget to thread `e` through return types, or invent nonsensical combinations. `_` is a single token learnable from one example, doesn't introduce naming decisions (Principle 2), and doesn't require reasoning about effect unification.

**Q3: Timeline (4-1 for fn-type effects v1, polymorphism v2)**

- **Systems:** Full in v1. If function types ship without effect information, every HOF signature becomes a lie you have to break later. Retrofitting changes calling conventions and ABI. The compilation strategy is known. Deferring borrows complexity at loan-shark interest rates. *(dissent)*
- **Web/Scripting:** Fn-type effects v1, polymorphism v2. Ship the `fn(T) -> U ! IO` syntax now so the type system is complete. Don't block v1 on getting polymorphism perfect — iterate after real users hit real friction.
- **PLT:** Fn-type effects v1, polymorphism v2. Pragmatic concession. Shipping `fn(T) -> U ! E1, E2` means library authors can write monomorphic effectful callbacks today. The type system remains sound; you just lose generality. The critical invariant: do not ship v1 with pure-only function types, because retrofitting `!` onto arrow types is breaking, while adding effect variables is additive.
- **DevOps:** Fn-type effects v1, polymorphism v2. Gives LSP and diagnostics a solid foundation. Trying to ship both at once means half-baked tooling for effect variables at launch. Better to have solid tooling for a smaller feature set.
- **AI/ML:** Fn-type effects v1, polymorphism v2. The foundation (`fn(T) -> U ! IO.Log`) is simple enough to ship now and unblocks real patterns. Deferring everything means v1 ships with a known hole that forces workarounds which become the patterns LLMs learn and then have to unlearn.

