[< All Decisions](../DECISIONS.md)

# Name Resolution Pass — Design Rationale

### Panel Deliberation

Five panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML) voted independently on 4 questions. Each expert ran as a separate agent and returned votes without seeing other experts' reasoning.

**Context:** The Pact compiler has no complete name resolution. A partial `resolve_names()` pass in typecheck checks variables and function calls but does NOT verify method existence (which requires type information). Codegen maintains its own separate scope system with 11+ type-specific tracking lists. Undefined function calls log E0504 but continue emitting garbage C. Method calls silently generate invalid C identifiers like `x_nonexistent(x)`. The resolved import compilation model (5-0 emit-all) flattens all imported declarations into a single AST with no module scoping. The resolved `pub` enforcement decision (5-0 compile-time) is not yet implemented.

**Q1: How should the typecheck symbol table and codegen scope system be unified? (5-0 for C: annotated AST)**

- **Systems (C):** Extends the existing parallel-array architecture naturally. `np_resolved_type`/`np_resolved_fn` give codegen O(1) access via node index — data-oriented, cache-friendly, no layering violations. Option A forces typecheck to carry codegen-specific CT_* baggage.
- **Web/Scripting (C):** TypeScript's checker decorates AST nodes with type info that downstream phases consume — same pattern. Avoids the "two systems diverge" risk of B without the massive refactor of A. Data-flow model is easy to reason about: typecheck writes, codegen reads.
- **PLT (C):** The compiler already uses parallel arrays as its AST representation — this IS an annotated AST. Adding resolution annotations is the natural extension. Maintains the phase distinction principle: typecheck writes, codegen reads. Shared symbol table (A) forces premature coupling between semantic analysis and code emission.
- **DevOps (C):** Annotated AST nodes are the bread and butter of LSP: hover needs resolved type at a node, goto-definition needs resolved symbol — both are "read annotation off AST node" operations. A's shared symbol table fights the parallel-array design. B's separate systems produce inconsistent diagnostics.
- **AI/ML (C):** Parallel arrays are already the compiler's idiom, so adding resolution arrays is a pattern the model has learned. Shared symbol table (A) introduces a broken transitional period. Two systems (B) means tracking two separate mental models — documented failure mode in code generation benchmarks.

**Q2: Should method resolution be deferred to a type-aware pass? (5-0 for A: two-phase)**

- **Systems (A):** Method resolution is inherently type-directed — can't resolve `x.len()` without knowing what `x` is. Two-phase maps to the real dependency graph. The "double walk" cost is negligible in parallel arrays.
- **Web/Scripting (A):** The TypeScript/Kotlin model. When I write `x.foo()` and `foo` doesn't exist on that type, I want an error at typecheck time, not a cryptic C compiler error. Option B can't handle inferred types. Option C keeps semantic validation in codegen — dead end for tooling.
- **PLT (A):** The only sound option. Name binding answers "does this identifier refer to something?"; method resolution answers "which implementation does this call dispatch to?" These are distinct problems requiring distinct information. Conflating them (B) is a category error.
- **DevOps (A):** The only option that enables real LSP method completions. Option B can only complete methods on explicitly annotated types. Option C keeps method resolution in codegen — dead end for language server.
- **AI/ML (A):** Two-phase gives the AI a clean, ordered error sequence: first all "unknown name" errors, then all "no such method on type X" errors. This is the Rust/TypeScript pattern that dominates training data.

**Q3: What error recovery strategy for name resolution? (4-1 for A: accumulate, halt before codegen)**

- **Systems (A):** Hard gate: codegen only sees valid input. Every phase needs a clear contract. Option B imposes poison-value handling tax on every future codegen change.
- **Web/Scripting (A):** This is what every modern language does and what developers expect. Name errors are high confidence — no cascade ambiguity like type inference. One missing import can trigger 50 downstream errors with Option B — all meaningless noise.
- **PLT (A):** A program that is not well-scoped cannot be meaningfully typed. Continuing with unresolved names (B) requires introducing poison types that propagate through the type system — enormous complexity. Clean phase gate is the principled choice.
- **DevOps (B):** Developer feedback loop is king. When I have 3 typos, 1 missing import, and 1 type error, I want all 5 in one compiler run. Cascade suppression (poison symbols suppress downstream errors) mitigates false positives. *(dissent)*
- **AI/ML (A):** Models perform measurably better seeing ALL errors of a given category at once rather than one-at-a-time. Cascade errors from poison values are pure noise — LLMs cannot distinguish real errors from cascade artifacts.

**Q4: How should name resolution interact with imports and pub enforcement? (4-1 for B: module-scoped symbol table)**

- **Systems (A):** The 5-0 emit-all decision committed to flat compilation. Module-scoped tables contradict that architecture. Minimal delta: tag declarations with source module, check `np_is_pub` on cross-module references. *(dissent)*
- **Web/Scripting (B):** The panel already voted 5-0 for module-qualified C symbols and 5-0 for pub enforcement. A module-scoped symbol table is the natural implementation. Option A is the "allow then deny" anti-pattern. Every language (TypeScript modules, Python packages, Kotlin packages) has module-scoped resolution.
- **PLT (B):** The only compositional option. A flat scope cannot distinguish `module_a.helper` from `module_b.helper` — it structurally cannot represent pub boundaries. Module-scoped tables are standard in every language with a module system (ML, Haskell, Rust). Option C (defer) is unsound — allows programs to compile that should be rejected.
- **DevOps (B):** Module-scoped tables enable LSP scoped completions (`std.json.` shows JSON methods only). Proper go-to-definition. Useful `PrivateItemAccess` errors with module context. The flat model becomes a collision minefield as stdlib grows.
- **AI/ML (B):** Every major language in training data uses module-scoped resolution. LLMs have internalized `import X` → `X.thing`. A flat scope is novel and fights the training distribution. Option C creates a time-bomb: AI generates code using private items that compiles today, breaks when pub enforcement arrives.

### Resolution

Name resolution uses an **annotated AST** architecture: the typecheck phase decorates AST nodes with resolution results via new parallel arrays, and codegen reads these annotations instead of maintaining its own scope system. Method resolution runs in **two phases** — name binding first, then type-aware method resolution — reflecting the fundamental distinction between name binding and type-directed dispatch. Name resolution **accumulates all errors and halts before codegen**, ensuring codegen never processes unresolved names. The symbol table is **module-scoped**, with each declaration tagged by source module, enabling structural `pub` enforcement and module-qualified error messages. See §6.3 for the full specification.

