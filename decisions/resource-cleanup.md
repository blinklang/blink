[< All Decisions](../DECISIONS.md)

# Resource Cleanup — Design Rationale

### Problem Statement

Section 5.1 hand-waved "defer/drop semantics" without specifying them. Effect handlers manage DI'd resources (connection pools, FS capability) but not individual resources acquired within a function. The `?` operator causes early returns that skip cleanup code — the same problem that motivated Python's `with`, Go's `defer`, and Rust's `Drop`.

### Cross-Language Survey

| Language | Mechanism | Strengths | Weaknesses |
|----------|-----------|-----------|------------|
| Python | `with X as Y` + `__enter__`/`__exit__` | Scoped, familiar to LLMs | Two dunder methods, context manager protocol verbose |
| Go | `defer` | Simple, one keyword | Forgettable, no type signal, resource stays in scope after cleanup |
| Rust | `Drop` trait + RAII | Automatic, zero overhead | Tied to ownership system Pact doesn't have |
| Java | `try-with-resources` + `AutoCloseable` | Trait-based, scoped | Verbose syntax, bolted onto exception system |
| C# | `using` + `IDisposable` | Clean syntax | Requires explicit `IDisposable` cast in some cases |
| Swift | `defer` | Simple | Same problems as Go's defer |

### Proposals Considered

**Proposal A: `Closeable` trait + `with...as`** (selected)
- Single compiler-known trait signals resource-holding types
- `with...as` guarantees cleanup on all exit paths
- Reuses existing `with` keyword; `as` disambiguates from effect handlers
- Scopes the resource — cannot escape the block

**Proposal B: `defer` statements**
- `let f = fs.open(path)?` then `defer f.close()`
- Forgettable — no type signal, compiler can't warn when you forget
- Two steps to manage one resource
- Resource stays in scope after logical cleanup point

**Proposal C: Lint-only approach**
- Warn when `Closeable` values aren't closed
- No enforcement mechanism — easy to ignore
- No scoping guarantees

### Decision: Proposal A (3-0)

Why not `defer`:
1. **Forgettable** — no type signal, compiler can't warn when you forget
2. **Two steps** — acquire then defer, vs single `with...as` construct
3. **Principle 2** — adds a second resource management mechanism alongside `with`
4. **Training data** — `with X as Y` is Python (dominant in LLM training data); `defer` is Go/Zig (smaller representation)
5. **Scope leaking** — `defer` leaves the resource in scope after cleanup; `with...as` scopes it

