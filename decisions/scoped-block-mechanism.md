[< All Decisions](../DECISIONS.md)

# Scoped Block Mechanism — Design Rationale

### Problem Statement

The transaction-block-syntax decision (3-1) established `db.transaction { }` as a parser special form, following the `async.scope { }` precedent. However, this approach requires dedicated parser + formatter + codegen support for every new block-accepting API, creating scalability concerns (raised by PLT, DevOps, AI/ML in that deliberation). This deliberation resolves the gap: "Blink needs a general mechanism for scoped blocks with enter/exit semantics, not an unbounded proliferation of parser special forms."

### Panel Deliberation

Five panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML) voted on four questions, followed by a runoff between the two leading options.

**Prior decisions referenced:**
- [transaction-block-syntax.md](transaction-block-syntax.md): `db.transaction { }` as parser special form (3-1)
- [resource-cleanup.md](resource-cleanup.md): `Closeable` trait + `with...as` for scoped resources (3-0)
- `async.scope { }` precedent: parser special form (`NodeKind.AsyncScope`)

---

**Q1: Should Blink add a general mechanism for scoped blocks, or continue adding parser special forms as needed?**

**Result: General mechanism (4-1)**

- **Systems:** General mechanism. Every special form is parser + formatter + codegen work. Two is fine, twenty is not. A trait-based mechanism scales.
- **Web:** General mechanism. Kotlin's `contract { }`, Swift's `withCheckedContinuation { }`, Ruby's block-passing — all show that a general mechanism is more productive than special forms.
- **PLT:** General mechanism. The two existing special forms (`async.scope`, `db.transaction`) already demonstrate the pattern. Abstract it before it proliferates.
- **AI/ML:** General mechanism. Special forms create a closed set that LLMs must memorize. A trait-based pattern is learnable from one example and generalizable.
- **DevOps:** *(dissent)* Keep special forms. The diagnostic quality (transaction-aware error messages, scope-aware completions) justifies per-form investment. A general mechanism will produce worse tooling.

---

**Q2: Which general mechanism? (No majority — proceeded to runoff)**

Options considered:
- **A: Trailing block syntax** — `foo { block }` desugars to `foo(fn() { block })`. General but gives closure semantics (wrong `?`/`return` behavior).
- **B: `ScopeGuard` trait** — `enter()`/`exit()` methods, compiler inserts calls at block boundaries. Simple but no binding, no block-semantic `?`.
- **C: Algebraic effect with Raise/Return** — Reify `?` and `return` as effects, handle them in the block provider. Most principled but heavy machinery.
- **D: `BlockHandler` trait** — `enter() -> T`/`exit(ok: Bool)` trait with `with expr as name { }` syntax. Leverages existing `with`/`as` keywords.
- **E: `with` + context manager protocol** — Python-style `__enter__`/`__exit__` but with Blink's type system. Similar to D but separate protocol from traits.
- **F: Hybrid `with` + `BlockHandler` trait with optional `as` binding** — Like D, but `as` is optional (for blocks that don't produce a binding, e.g., `async.scope`-like usage). `exit(self, ok: Bool)` receives whether the block completed normally.

Round 1 votes:
- **Systems:** D
- **Web:** B
- **PLT:** C
- **AI/ML:** E
- **DevOps:** D (conditional — only if diagnostics aren't degraded)

No majority. The two leading candidates (D and F, which emerged as a refinement of D during discussion) proceeded to a runoff.

---

**Runoff: Option F vs Option C**

**Result: Option F — 5-0 unanimous**

- **Systems:** F. The `BlockHandler` trait is a clean abstraction. Optional `as` means `db.transaction { }` (no binding) and `with lock.acquire() as guard { }` (binding) use the same mechanism. `exit(self, ok: Bool)` is enough for commit/rollback patterns.
- **Web:** F. Unifies the pattern without requiring effect system changes. `with` is already the keyword for "scoped stuff" in Blink. Adding `BlockHandler` to the existing `with` disambiguation is cleaner than inventing new syntax.
- **PLT:** F. *(Switched from C.)* Retrofitting Raise/Return as reified effects onto the existing effect system would produce an inconsistent hybrid — algebraic effects for IO/DB/FS but also for control flow. `BlockHandler` is a simpler, orthogonal mechanism that composes with effects rather than extending them.
- **DevOps:** F. The `exit(self, ok: Bool)` callback gives enough information for instrumentation (transaction duration, success/failure metrics) without requiring effect-level hooks. Formatter and LSP can pattern-match on `BlockHandler` impls.
- **AI/ML:** F. One trait, two methods, optional binding. This is the kind of pattern LLMs can learn from a single example in context. The `with` keyword reuse is net positive — it's the "scoped thing" keyword, and this is a scoped thing.

---

**Q3: How should `BlockHandler` blocks interact with async?**

**Result: Compile-time enforcement (consensus)**

A `BlockHandler` block runs synchronously in the enclosing function's context. If the body contains `async.spawn`, the spawned task cannot reference the `BlockHandler`'s binding (same restriction as `Closeable` — it would escape the scope). The compiler enforces this at the type level, not at runtime.

---

**Q4: Should `async.scope { }` be migrated to `BlockHandler`?**

**Result: Yes (4-1)**

- **Systems:** Yes. `async.scope` is the poster child for this pattern — enter sets up the scope, exit joins all tasks.
- **Web:** Yes. One mechanism for all scoped blocks reduces cognitive load.
- **PLT:** Yes. The parser special form can be replaced by a stdlib `BlockHandler` impl. The syntax remains `async.scope { }` via `with async.scope() { }` shorthand or similar.
- **AI/ML:** Yes. Fewer special forms = fewer things to memorize.
- **DevOps:** *(dissent)* No. `async.scope` has unique structured concurrency semantics (task cancellation, panic propagation) that don't map cleanly to `enter()/exit()`. It should remain a special form with bespoke compiler support.

**Note:** Migration is a v2 goal. `async.scope` remains a parser special form in v1 while `BlockHandler` proves itself on `db.transaction` and user-defined types.

---

### The `BlockHandler` Trait

```blink
trait BlockHandler {
    type Context

    fn enter(self) -> Self.Context
    fn exit(self, ok: Bool)
}
```

- `enter()` is called before the block body executes. Returns a value that is bound via `as`.
- `exit(ok: Bool)` is called after the block body completes. `ok` is `true` for normal completion, `false` if the block exited via `?` propagation or `return`.
- `exit()` **cannot** suppress panics, retry the block, or transform the block's result. It is purely for cleanup/finalization (commit, rollback, release, log).

### Syntax

```blink
// With binding (Context type is meaningful)
with db.transaction() as tx {
    db.execute("INSERT INTO ...")?
    // tx is the Context value from enter()
}

// Without binding (Context type is ())
with metrics.timer("request") {
    handle_request()?
}
```

Both forms use the existing `with ... { }` / `with ... as name { }` syntax. The compiler distinguishes `BlockHandler` from `Closeable` and `Handler[E]` by the type of the expression.

### `with` Disambiguation (Updated)

| Syntax | `as` present? | Type check | Meaning |
|--------|--------------|------------|---------|
| `with expr { }` | No | `expr: Handler[E]` | Effect handler |
| `with expr { }` | No | `expr: T where T: BlockHandler, T.Context == ()` | Block handler (no binding) |
| `with expr as name { }` | Yes | `expr: T where T: Closeable` | Scoped resource |
| `with expr as name { }` | Yes | `expr: T where T: BlockHandler` | Block handler (with binding) |

When `as` is absent, the compiler checks `Handler[E]` first, then `BlockHandler`. When `as` is present, the compiler checks `Closeable` first, then `BlockHandler`. A type implementing both `Closeable` and `BlockHandler` is a compile error (ambiguity).

### Concerns Addressed

1. **`with` keyword overload (Web, DevOps):** The disambiguation table above is the complete ruleset. `with` now means "scoped thing" — effect handler, closeable resource, or block handler. The `as` keyword and type system resolve all ambiguity at compile time.

2. **`exit()` constraints (PLT):** `exit(self, ok: Bool)` is a finalizer, not a control flow mechanism. It cannot:
   - Suppress panics (panics bypass `exit()` entirely — same as `Closeable.close()`)
   - Retry the block (no mechanism to re-enter)
   - Transform the block's result (it returns `()`, not a modified value)
   - Throw errors that replace the block's error (if `exit()` itself fails, it panics)

3. **Exit-on-every-path codegen (Systems):** The compiler emits `exit(true)` before the normal exit point and `exit(false)` at every early-exit point (`?` propagation, `return`). For nested blocks, exits run in LIFO order (innermost first). This is the same pattern as `Closeable.close()` codegen — no new complexity.

4. **`db.execute` vs `tx.execute` ambiguity (AI):** When `as tx` is used, the `tx` binding is the `Context` value from `enter()`. Effect operations (like `db.execute`) still go through effect handles, not through `tx`. The `tx` binding is for transaction-specific state (e.g., a savepoint handle), not for replacing the effect handle. If a `BlockHandler` needs to provide effect operations, it should also be a `Handler[E]` and be installed via `with` as a handler.
