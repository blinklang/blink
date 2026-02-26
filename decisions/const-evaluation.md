[< All Decisions](../DECISIONS.md)

# Const Evaluation — Design Rationale

### Panel Deliberation

Five panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML) voted independently on 4 questions about compile-time constant evaluation rules. Two unanimous, two contested.

**Q1: What qualifies as a const expression? (5-0 for B: Literals + arithmetic/boolean ops)**

- **Systems:** Literal folding + arithmetic maps directly to `static const` in C. Option D (any pure expression) requires whole-program purity analysis that doesn't exist. Option C (`const fn`) needs a compiler interpreter. B covers 90%+ of real uses: `let TK_FN = 0`, `let BUFFER_SIZE = 1024 * 64`.
- **Web/Scripting:** Devs expect `MAX_SIZE = 1024 * 1024` to work. Literals-only forces precomputed magic numbers. Option D creates a "is this const?" guessing game like TypeScript's `as const`. B is the sweet spot.
- **PLT:** Option D conflates compile-time evaluability with runtime purity — evaluating `fib(40)` at compile time is undecidable. Option C introduces function coloring. B gives a decidable, syntactic set of const expressions. `"hello".len()` being non-const may feel arbitrary, but opening method calls is `const fn` in disguise.
- **DevOps:** Closed set = precise error messages. "function call 'config.port()' is not a compile-time constant" vs "this expression might have effects." B is the only option where constness is syntactically obvious without type information.
- **AI/ML:** Simple arithmetic folding has near-zero LLM error rate in training data. `const fn` causes 15-20% error rates in Rust training data. Option D requires deep semantic reasoning transformers fail at.

**Q2: Should Pact have a `const` keyword? (3-2 for B: Required keyword)**

- **PLT:** `const` and `let` inhabit different evaluation phases. Conflating them (Option A) violates the principle that distinct concepts deserve distinct syntax. Option C (optional) creates two forms with identical semantics — Principle 2 violation.
- **DevOps:** With `const`, LSP shows "compile-time constant" on hover without analysis. `pact fmt` can enforce UPPER_SNAKE_CASE. Changing a const's RHS to non-const errors at the *definition*, not downstream use sites.
- **AI/ML:** `const` is top-5 most recognized keywords across all LLM training data (C, C++, Rust, JS, TS, Go). Distinct token for the model to key on. Without it, `let MAX = 100` has noisy semantics across training data.
- **Systems:** *(dissent)* The compiler already emits `static const` for immutable module-level `let` with simple RHS. A separate keyword is a distinction without a difference — if the RHS is const and the binding is immutable, it IS const. `let` + `let mut` already encodes the important information.
- **Web/Scripting:** *(dissent)* Pact already has `pub let api_version = "2.0"` described as "equivalent to a named constant" (§2.12.1). Adding `const` creates a decision at every module-level binding. TS's `const` vs `let` is a constant source of confusion. One keyword, one concept.

**Q3: Can struct/enum constructors appear in const expressions? (3-1-1 for B: Struct literals with const fields)**

- **PLT:** A struct is a product type. If components are const, the composite is const — this follows from compositional semantics. Denying this (Option A) would be a compositionality failure. B is the natural first step; C follows trivially later.
- **DevOps:** Struct defaults are already const contexts. If `const DEFAULT_CONFIG = ServerConfig { port: 8080 }` doesn't work, users repeat defaults everywhere — drift and CI failures. `Type.new()` is not const (function call), but `Type { field: value }` is (literal syntax).
- **AI/ML:** Struct literal constants are ubiquitous in training data (C, Rust, TS, Go). LLMs generate these correctly. Nested structs (C over B) follow naturally. *(voted C, counted as supporting B since B is the minimal version of C)*
- **Web/Scripting:** *(voted C)* Every web framework has nested config structs. Blocking nested structs creates an arbitrary cliff devs trip over.
- **Systems:** *(voted A)* Struct const literals require C compound literals or static initializers — reworking codegen. Current compiler uses `__pact_init_globals()` runtime initialization. Ship v1 with scalar-only, add struct const in v1.1.

**Q4: How does const evaluation interact with C codegen? (5-0 for C: Compiler-evaluated, emitted as literals)**

- **Systems:** Only option giving Pact compiler full control. `#define` loses type safety. C static initializer rules vary by standard version. Compiler folds `1024 * 64` to `65536` and emits literal — maximally portable.
- **Web/Scripting:** Maximum flexibility on Pact side, dead simple C output. Compiler is source of truth, not the C compiler. Extend const-eval later without changing codegen strategy.
- **PLT:** Cleanest phase factoring. Pact compiler owns const-eval semantics; C backend is emission target, not semantic participant. Backend independence essential for future WASM/LLVM targets.
- **DevOps:** Cleanest diagnostics, most portable C. No macro expansion bugs, no compound literal portability issues, no platform-dependent static initializer behavior.
- **AI/ML:** Simplest generated C for LLM-assisted debugging. Plain literals have zero ambiguity. Decouples const-eval complexity from C codegen complexity.

