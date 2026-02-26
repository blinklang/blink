[< All Decisions](../DECISIONS.md)

# While/Loop — Design Rationale

### Panel Deliberation

Five panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML) voted independently on 4 questions.

**Q1: `while` vs `loop` vs both (3-2 for both)**

- **Systems:** Both share the same IR lowering. `while` and `loop` express different *intent* — conditional vs unconditional. `while true` adds a dead constant that communicates nothing. Event loops, server accept loops are conceptually infinite.
- **Web/Scripting:** `while` only. Every JS/TS/Python dev knows `while`. `while true` for infinite is immediately readable. `loop` as separate keyword violates Principle 2. *(dissent)*
- **PLT:** Both. `while` and `loop` have different typing — `while` may execute zero times (type `()`), `loop` without reachable `break` diverges (type `Never`). Collapsing them forces special-casing `while true` in the type checker.
- **DevOps:** Both. Linter can warn on `while true` → suggest `loop`. LSP can offer context-appropriate snippets. Two constructs, two distinct intents.
- **AI/ML:** `while` only. `while` is dominant in training data across Python/JS/Java/C/Go. `loop` is basically Rust-only. Models frequently fumble Rust's `loop`. *(dissent)*

**Q2: Break-with-value (3-2 for plain break)**

- **Systems:** Break-with-value. Polling/retry/search loops all produce a value. Without `break expr`, forced into `let mut` + assign — the declare-then-assign antipattern expression-oriented design exists to eliminate. *(dissent)*
- **Web/Scripting:** Plain break. Break-with-value is alien to web devs. `let mut` + assign + `break` is universal and obvious.
- **PLT:** Break-with-value. If `if/else` and `match` are expressions, `loop` should be too. Without it, unnecessary mutation to work around a missing semantic feature. *(dissent)*
- **DevOps:** Plain break. Break-with-value is a diagnostic nightmare — compiler must verify all break paths return compatible types. YAGNI for v1.
- **AI/ML:** Plain break. `break expr` is a Rust-ism LLMs get wrong constantly. Plain break matches Python/JS/Java/C/Go training data.

**Q3: Labeled breaks (4-1 no labels)**

- **Systems:** No. Rare need, extract-to-function handles it. Labels can be added in v2 without breaking changes.
- **Web/Scripting:** No. In 15+ years, can count on one hand. Nested loops needing coordinated exit is a code smell.
- **PLT:** No. Labels add continuation points that interact with algebraic effects — semantics get hairy. Extract a function.
- **DevOps:** Yes. Retry-with-timeout (outer=timeout, inner=retry), polling multiple endpoints. `@outer` reuses annotation sigil. *(dissent)*
- **AI/ML:** No. Rare in training data. Models routinely botch label placement. Extract-to-function is more common and correctly generated.

**Q4: `while let` (5-0 reject)**

- **Systems:** No. Same construct as rejected `if let`. Interacts awkwardly with potential future break-with-value.
- **Web/Scripting:** No. Consistent with `if let` rejection. `loop { match ... }` is explicit.
- **PLT:** No. Pattern matching should live in `match`. Adding `while let` after rejecting `if let` would be inconsistent.
- **DevOps:** No. One fewer special form for formatter, linter, and LSP. `loop + match` is more flexible.
- **AI/ML:** No. Rust/Swift-specific syntax with thin training signal. LLMs frequently generate wrong destructuring patterns.

