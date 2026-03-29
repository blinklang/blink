[< All Decisions](../DECISIONS.md)

# DB Module Design — Design Rationale

### Panel Deliberation

Five panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML) voted independently on 6 questions plus 2 follow-up naming/effect decisions. Resolves gap: "db module — SQLite bindings design for connection management, query API, prepared statements, result iteration."

**Prior decisions referenced:**
- [Web-Service Stdlib Tier](web-service-stdlib-tier.md): DB is Tier 2 (5-0)
- [Native C Dependency Resolution](native-c-dependency-resolution.md): SQLite3 is compiler-managed, bundled (3-2)
- [OPEN_QUESTIONS.md 3.1](../OPEN_QUESTIONS.md): `Query[C]` phantom-typed parameterized queries (3-0)
- [OPEN_QUESTIONS.md 3.2](../OPEN_QUESTIONS.md): `Raw(expr)` marker type escape hatch (2-1)

---

**Q1: Connection management model (5-0 for effect handler scoping)**

- **Systems:** Global `__pact_db` is a concurrency hazard. Effect handler scoping threads the connection through evidence-passing, same as IO/FS/Net. Zero-cost at call sites.
- **Web/Scripting:** `db.exec(sql)` with no handle but `db.begin(handle)` with one is inconsistent. Effect scoping matches how every other effect works. `with db.connect(":memory:") { ... }` is the natural pattern.
- **PLT:** Effects are capabilities. The connection IS the capability's implementation — it belongs in the handler. A global `void*` breaks referential transparency and makes handler composition unsound.
- **DevOps:** Effect scoping lets LSP show which connection is in play at every point. Trace output naturally associates operations with handlers. Testing: `with mock_db(fixtures) { ... }`.
- **AI/ML:** LLMs generate `db.query("...")` without handles. Effect scoping means generated code just works.

**Q2: Query result types (5-0 for Row type)**

- **Systems:** `List[List[Str]]` leaks SQLite internals. `Row` with `row.get_int("age")` provides typed access without overhead. C runtime already captures column names (discarded by current codegen).
- **Web/Scripting:** `row.get(0).unwrap()` requires knowing SQL column order. `row.get_str("name")` is self-documenting. Every web developer expects named column access.
- **PLT:** `Row` must be runtime-typed (not static fields) since schema isn't known at compile time. `row.get_int("age")` returns `Option[Int]`.
- **DevOps:** LSP autocomplete on `Row` suggests `.get_int()`, `.get_str()`, `.column_names()`. On `List[Str]` it can only suggest generic list methods.
- **AI/ML:** `row.get_str("name")` matches dominant training patterns (JDBC ResultSet, Python sqlite3.Row, Go sql.Row).

Row API:
- `row.get("column")` → `Option[Str]`
- `row.get_int("column")` → `Option[Int]`
- `row.get_str("column")` → `Option[Str]`
- `row.column_names()` → `List[Str]`
- `row.get_at(index)` → `Option[Str]` (positional fallback)

**Q3: Prepared statement ergonomics (5-0 for both layers)**

- **Systems:** Batch inserts of 100k rows need prepare-once, bind-many. High-level `Query[DB]` handles 95% of cases. Keep both.
- **Web/Scripting:** Most developers should never touch prepared statements directly. `Query[DB]` auto-parameterization is the killer feature.
- **PLT:** Current `Int` handles for statements are unsound — nothing prevents `db.bind_int(42, 1, val)` where 42 isn't a statement. Need a proper `Stmt` type.
- **DevOps:** High-level in docs, low-level in "advanced" section.
- **AI/ML:** LLMs will never correctly generate the 5-step prepare/bind/step/column/finalize sequence. High-level must be the default.

High-level: `db.query("SELECT * FROM users WHERE age > {min_age}")` with `Query[DB]` auto-parameterization.
Low-level: `Stmt` type with `stmt.bind()`, `stmt.step()`, `stmt.finalize()`. Implements `Closeable` for `with...as` auto-cleanup.

**Q4: Result iteration pattern (5-0 for for-in on List[Row])**

- **All panelists:** `for row in rows { ... }` already works since `db.query()` returns `List[Row]` and for-in works on Lists. No new features needed. Lazy cursors deferred to v2 alongside effectful iteration resolution.

**Q5: Error handling (5-0 for Result types everywhere)**

- **Systems:** Silently printing errors to stderr is a bug factory. `db.open()` returning null handle causes UB in all subsequent operations.
- **Web/Scripting:** `?` operator makes error handling ergonomic. Web framework catches errors at request handler boundary.
- **PLT:** Totality. `db.query() -> List[Row]` is a lie — it can fail. `db.query() -> Result[List[Row], DBError]` is honest.
- **DevOps:** Result types mean the compiler requires error handling. LSP shows error types on hover.
- **AI/ML:** `db.query("...")?` is the dominant pattern in Rust training data.

`DBError` type: `type DBError { code: Int, message: Str }`

**Q6: Transaction API (4-1 for both scoped + manual; Web dissented for scoped-only)**

- **Systems:** Scoped for common case, manual for nested transactions (SAVEPOINTs) and long-running operations.
- **Web/Scripting:** *(dissent — scoped only)* Manual transactions are "forgot to rollback" bugs. Django's `@transaction.atomic` and Rails' `transaction` block prove scoped is sufficient.
- **PLT:** Scoped transactions compose correctly. `?` within a block triggers rollback. Manual breaks compositionality but is sometimes necessary.
- **DevOps:** Scoped is testable. Linting: warn if `db.begin()` has no corresponding `db.commit()` in all paths.
- **AI/ML:** LLMs forget `db.rollback()` in error paths. Scoped eliminates the bug class.

Primary: `db.transaction { ... }` (auto-commit/rollback).
Secondary: `db.begin()`, `db.commit()`, `db.rollback()`.

---

### Follow-up: Effect Hierarchy Simplification

**Decision: Drop `DB.Admin`, simplify to `DB.Read` + `DB.Write` (user + panel consensus)**

Original spec defined `DB { Read, Write, Admin }`. The `Admin` sub-effect covered DDL (CREATE, DROP, ALTER, GRANT).

**Rationale:** No real-world function needs "can INSERT but can't CREATE TABLE." The Read vs Write boundary is the meaningful one for effect tracking. DDL permission granularity is a database RBAC concern, not a compiler concern. Migration scripts that run DDL also INSERT seed data, so they need `DB.Write` anyway. Application code does reads and writes — never schema operations in isolation.

Simplified hierarchy:
```
effect DB {
    effect Read       // SELECT — read-only queries
    effect Write      // INSERT, UPDATE, DELETE, CREATE, DROP, ALTER — all mutations
}
```

### Follow-up: API Naming Convention

**Decision: SQL-familiar method names with effect-enforced mapping (user + panel consensus)**

Method names don't need to mirror effect sub-names. Precedent: `Net.Connect` uses `net.get()`, `net.post()`, not `net.connect()`.

| Method | Effect Required | Return Type |
|--------|----------------|-------------|
| `db.connect(path)` | `DB` | connection handler (scoped) |
| `db.query(sql)` | `DB.Read` | `Result[List[Row], DBError]` |
| `db.query_one(sql)` | `DB.Read` | `Result[Option[Row], DBError]` |
| `db.exec(sql)` | `DB.Write` | `Result[Void, DBError]` |
| `db.execute(sql)` | `DB.Write` | `Result[Int, DBError]` (rowid) |
| `db.transaction { }` | `DB.Write` | `Result[T, DBError]` |
| `db.prepare(sql)` | `DB.Read` or `DB.Write` | `Result[Stmt, DBError]` |
| `db.begin()` | `DB.Write` | `Result[Void, DBError]` |
| `db.commit()` | `DB.Write` | `Result[Void, DBError]` |
| `db.rollback()` | `DB.Write` | `Result[Void, DBError]` |
| `db.errmsg()` | `DB.Read` | `Str` |
