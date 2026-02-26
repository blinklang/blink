[< All Decisions](../DECISIONS.md)

# Module-Level Let Semantics — Design Rationale

### Panel Deliberation

Five panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML) voted independently on 3 questions. All votes unanimous.

**Context:** Friction log (Feb 7, 2026) discovered that duplicate `let mut` declarations at module level silently collapse — codegen's `is_emitted_let()` dedup skips the second declaration with no error or warning. The spec had no guidance on module-level `let` uniqueness, `pub let` visibility, or how shadowing rules differ from function-local scope.

**Q1: What happens with duplicate module-level `let` names? (5-0 for compile error)**

- **Systems:** Silent dedup hides ambiguity at static-storage level. Both `static const` and `static` in C require unique names per translation unit. Every systems language errors on redeclaration. The codegen workaround (first-binding-wins) is an implementation accident, not a feature.
- **Web/Scripting:** JavaScript/TypeScript `let` redeclaration in the same scope is a `SyntaxError`. Pact developers coming from these languages expect the same. Silent dedup is the worst possible behavior — it looks like it works but does the wrong thing.
- **PLT:** Module-level scope is a flat namespace. There is no inner scope for shadowing to inhabit, so "redeclaration" has no well-defined semantics under lexical scoping. Compile error preserves referential transparency — every name has exactly one binding.
- **DevOps:** Silent dedup is a tooling nightmare. LSP go-to-definition becomes ambiguous, no diagnostic is available, and the developer has no signal that their code is wrong. An early compile error is cheap and saves hours of debugging.
- **AI:** Silent-first-wins means an LLM generates `x = 2` but runtime has `x = 1` from an earlier binding. Compile error provides a strong training signal — the model learns immediately that duplicate bindings are wrong.

**Q2: Should `pub let mut` be allowed? (5-0 for immutable only)**

- **Systems:** `pub let` maps to `static const` in C — zero synchronization cost, safe to read from any context. `pub let mut` maps to mutable global state — a concurrency landmine that requires synchronization primitives the language doesn't yet provide.
- **Web/Scripting:** Maps directly to `export const` in JavaScript. Mutable exports cause chaos — even Python developers regret the pattern. Cross-module mutable state should go through functions.
- **PLT:** An immutable export is semantically equivalent to a nullary function — clean, compositional, no side effects. Cross-module mutation is an effect and should be tracked through the effect system.
- **DevOps:** Read-only constants support LSP hover-for-value and dead-code analysis. `pub let mut` creates "who changed this?" questions that are unanswerable without full program tracing.
- **AI:** `pub const`/`export const` patterns are well-represented in training data. Cross-module mutable state has a high error rate in LLM-generated code because models can't track mutation across files.

**Q3: Should function-local and module-level shadowing rules differ? (5-0 for yes)**

- **Systems:** Different codegen contexts justify different rules. Function-local shadowing is stack-based (cheap, scoped). Module-level would require static storage reallocation. Rust draws this exact line.
- **Web/Scripting:** TypeScript and Rust developers expect function-local `let x = parse(x)` as an idiomatic pipeline pattern. Module-level shadowing has no such ergonomic justification.
- **PLT:** Function bodies use sequential lexical scoping — each `let` opens a new scope (compositional). Modules use a flat namespace — all bindings coexist (collision). The scoping models are fundamentally different.
- **DevOps:** LSP handles function-local shadowing well — hover shows the right binding by scope. Module-level "which x?" creates confusion in every tool that processes the file.
- **AI:** Rust's shadowing model (allowed in functions, forbidden at module level) is the best-represented pattern in training data. Module-level shadowing has essentially zero training signal — models would have to guess.

### Resolution

Module-level `let` bindings must have unique names — duplicates are a compile error (`DuplicateModuleBinding`, E1004). Only immutable `pub let` is allowed; `pub let mut` is a compile error (`PubLetMutForbidden`, E1006). Function-local `let` shadowing remains permitted. See §2.12.1 for the full specification.

