[< All Decisions](../DECISIONS.md)

# `?` Operator Type Validation — Design Rationale

### Panel Deliberation

Five panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML) voted independently on 4 questions. All votes unanimous.

**Q1: Where should `?` validation live? (5-0 for A: type checking phase)**

- **Systems (A):** You never let invalid IR reach codegen in a sound compiler pipeline. Codegen should assume all invariants hold. Phase separation exists for a reason — Rust does this in HIR/type checking, not LLVM IR generation.
- **Web/Scripting (A):** Type checking is the natural home. It needs type information to differentiate Result vs Option, and putting it in a dedicated phase gives consistent error reporting and a clean contract to codegen.
- **PLT (A):** Phase separation exists for a reason. The `?` operator is fundamentally a type-level concern — it requires knowing the monadic container type, the return type signature, and proving compatibility. Codegen should consume validated ASTs.
- **DevOps (A):** Validation belongs in a dedicated phase gate — basic compiler hygiene. Type checking has all the context it needs, and catching errors early means better diagnostics and no wasted work downstream.
- **AI/ML (A):** AI code generators need deterministic error messages before hitting codegen. Catching `?` misuse in type checking gives clear, actionable errors the model can use in the next fix iteration.

**Q2: Should `?` work on both Result[T,E] and Option[T]? (5-0 for A: both)**

- **Systems (A):** `?` is early-return sugar — semantically identical whether unwrapping T|E or T|None. Separating them forces arbitrary syntactic distinctions for the same control flow pattern. The spec already committed to this.
- **Web/Scripting (A):** The obvious ergonomic win. Web devs are used to early-return patterns. Cross-type auto-wrapping (C) adds implicit magic that conflicts with the no-auto-into stance.
- **PLT (A):** Basic monad uniformity — `?` is sugar for early-return on the failure branch of a sum type. For Result that's Err(e), for Option it's None. Option C would be inconsistent with the 4-1 vote against implicit `.into()`.
- **DevOps (A):** Having two operators with subtly different semantics is a diagnostic nightmare. Developers expect `?` to mean "early return on sad path" regardless of container type.
- **AI/ML (A):** Training data across Rust/Swift/Kotlin shows this pattern. Both are "short-circuit on absence" — Option just has no error payload. Forcing Result-only would be an arbitrary restriction.

**Q3: How should error type compatibility be validated? (5-0 for A: exact structural match)**

- **Systems (A):** Structural equality is how the rest of the type system works. Nominal matching would spuriously unify two differently-defined types with the same name from different modules.
- **Web/Scripting (A):** The panel already voted 4-1 against auto `.into()`, so consistency demands exact match. If error types don't match, explicit `.map_err()` is the answer.
- **PLT (A):** The only sound choice that doesn't require runtime checks or implicit conversions. Nominal matching fails with generic error types or same-name-different-structure scenarios.
- **DevOps (A):** Structural equality gives precise, actionable errors: "expected Err(IoError), got Err(ParseError)" tells the developer exactly what's wrong.
- **AI/ML (A):** Exact match means clear errors that are greppable and fixable. Matches what AI models expect from typed languages.

**Q4: What error codes and diagnostics? (5-0 for A: separate codes per failure)**

- **Systems (A):** Systems programmers need actionable diagnostics. Separate codes point directly at the specific type mismatch. Generic codes with context text lead to "what does my error mean" questions.
- **Web/Scripting (A):** Separate error codes per failure mode make error docs easier to navigate. TypeScript and Rust nail this pattern.
- **PLT (A):** Separate codes let you write targeted diagnostics with fix suggestions (wrap in Result, use `??` instead, add `.map_err()`). The whole point of a type checker is giving actionable information.
- **DevOps (A):** Non-negotiable from a tooling perspective. IDE integrations, error parsers, CI failure messages all key off error codes. Parsing human-readable strings to determine what went wrong is barbaric.
- **AI/ML (A):** AI fix loops thrive on specificity. E0508/E0509/E0512 are different bugs with different fixes. Separate codes = separate fix patterns = faster convergence.

### Resolution

The `?` operator is validated during the **type checking phase** (Phase 2: type-aware), ensuring codegen never processes invalid `?` usage. `?` works on both **`Result[T, E]` and `Option[T]`** with no cross-type mixing — `?` on Result requires a Result return type, `?` on Option requires an Option return type. Error types require **exact structural match** (`E1 == E2`), consistent with the 4-1 no-auto-into vote. Four **separate error codes** provide targeted diagnostics: E0502 (invalid operand type), E0508 (Result `?` in non-Result fn), E0509 (Option `?` in non-Option fn), E0512 (error type mismatch). See §3c.2 for the full specification.

