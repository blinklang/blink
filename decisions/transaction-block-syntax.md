[< All Decisions](../DECISIONS.md)

# Transaction Block Syntax — Design Rationale

### Panel Deliberation

Five panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML) voted independently on the syntax for `db.transaction { }`. Resolves gap: "spec says `db.transaction { }` but Blink lacks trailing closure/block syntax — need decision on implementation mechanism."

**Prior decisions referenced:**
- [db-module-design.md](db-module-design.md) Q6: Transaction API (4-1 for both scoped + manual)
- [OPEN_QUESTIONS.md](../OPEN_QUESTIONS.md) 1.1: Closure syntax is `fn(params) { body }` (5-0)
- `async.scope { }` precedent: parser special form (`NodeKind.AsyncScope`) already exists

---

**Q1: How should `db.transaction { }` be syntactically implemented? (3-1, Systems abstained)**

Options considered:
- **A: Parser special form** — `db.transaction { }` as a dedicated AST node, like `async.scope { }`
- **B: General trailing block syntax** — `foo { block }` desugars to `foo(fn() { block })` for all functions
- **C: Stdlib function with explicit closure** — `db.transaction(fn() { ... })`, no compiler changes
- **D: Effect operation with closure param** — extend effect system to support higher-order params

**Result: A (3-1)**

- **PLT:** Block semantics are essential — `?` must propagate to the enclosing function's Result, not a closure boundary. Option A is the only option preserving this. `async.scope` already established the precedent. Closure-based options (B, C, D) require extra `?` operators and explicit return type annotations, breaking compositionality.
- **DevOps:** Option A reuses the `async.scope` pattern already validated and instrumented. The formatter has `format_block_inline()`, LSP can provide transaction-specific completions, and error messages can be transaction-aware ("rollback triggered by `?` on line X"). Highest-fidelity diagnostic option.
- **AI/ML:** Special forms create a learnable, consistent pattern: "scoped APIs use `name { body }` syntax." This pattern already exists in `async.scope { }` and `test "name" { }`, so extending it is pattern-reinforcement, not pattern-addition. Zero decision points, optimal token efficiency.
- **Web:** *(dissent)* General trailing block syntax (B) is the most productive feature for block-accepting APIs. Developers from Kotlin/Swift/Ruby expect this. It unifies `async.scope`, `db.transaction`, and future APIs (`items.for_each { }`) under one pattern. Counter: trailing blocks give closure semantics (wrong `?` behavior for transactions).
- **Systems:** *(abstained — no response)*

**Key argument:** Block semantics vs closure semantics. In a block, `?` propagates to the enclosing function; in a closure, `?` propagates to the closure's return. For transactions, block semantics are essential — the transaction must see all error paths to auto-rollback correctly.

---

### Concerns Raised

- **Scalability of special forms (PLT, DevOps, AI/ML):** Each new block-accepting API needs parser + formatter + codegen support. If Blink accumulates many such forms, the parser becomes cluttered. Mitigating factor: only `async.scope` and `db.transaction` need this treatment in v1; a general mechanism can be designed in v2 if the pattern proliferates.
- **Principle 2 tension (Web):** Having both `fn()` closures and `{ }` block forms creates two syntactic mechanisms for "code passed to a function." Counter: blocks and closures have genuinely different semantics (`?`/`return` behavior), so this is not a Principle 2 violation — it's two distinct features.
