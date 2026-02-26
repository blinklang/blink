[< All Decisions](../DECISIONS.md)

# Web-Service Stdlib Tier — Design Rationale

### Panel Deliberation

Five panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML) voted independently on 6 module tier placements. The core question: which web-service modules should be Tier 1 (ships with compiler, version-locked) vs Tier 2 (blessed separate package under `std/` org, versions independently)?

**Key architectural distinction:** Effect system types (`Request`, `Response`, `Headers`, `NetError`, `Query[C]`, `JsonValue`) are compiler-known and ship with the compiler regardless of tier classification. Stdlib modules provide convenience layers ABOVE effect operations — retry logic, connection pooling, routing frameworks, structured logging formatters. The tier question is about these convenience layers, not the core types.

**Q1: JSON codec — std.json (5-0 for Tier 1)**

- **Systems:** `Serialize`/`Deserialize` traits and `JsonValue` are compiler-known. The codec functions are the only way to USE those types. Shipping them separately creates a bizarre split. Pure implementation, tiny codegen footprint.
- **Web/Scripting:** Most clear-cut T1. Every language Pact competes with has JSON built-in. `import std.json` must work on day one with zero `pact.toml` entries. The `fetch.pact` example already uses `json.parse()`.
- **PLT:** `@derive(Serialize)` generates `fn to_json(self) -> JsonValue`. The function consuming `JsonValue -> Str` must be in the same versioning domain. Separating derive mechanism from codec breaks compositionality.
- **DevOps:** LSP autocomplete for `json.parse()` and `@derive(Serialize, Deserialize)` should work on `pact init` with zero config. JSON spec is stable (RFC 8259), so version-lock risk is near zero.
- **AI/ML:** JSON is the single most generated code pattern in LLM web/API code. Making it T2 means every AI-generated web project has a "did you `pact add`?" failure on first compile.

**Q2: HTTP client — std.http.client (3-2 for Tier 2; PLT/Web dissented)**

- **Systems:** HTTP semantics evolve (HTTP/2, HTTP/3). Version-locking convenience types violates zero-cost — unused HTTP types in every hello-world. Effect system already provides the core types.
- **Web/Scripting:** *(dissent — T1)* `Request`/`Response` are the output types of `net.get()` effect handles. Making effect handle return types live in a separate package is a DX nightmare.
- **PLT:** *(dissent — T1)* `fn request(req: Request) -> Result[Response, NetError]` is the core `Net.Connect` operation. These types ARE the effect's operational interface. Version mismatch breaks handler soundness.
- **DevOps:** Effect system already provides `Net.Connect` with `Request`/`Response` types. `std.http.client` adds higher-level conveniences (retry, redirect following, connection pooling) that version independently. `pact init --template web` auto-adds it.
- **AI/ML:** HTTP client APIs are large and evolving. Training data shows massive variance across languages. T2 with stable import path allows API evolution.

**Resolution note:** The PLT/Web dissent highlights that core HTTP types (`Request`, `Response`, `Headers`, `NetError`) must be compiler-known and ship with the compiler as part of the effect system definition (§4.4.1). The `std.http` Tier 2 package provides convenience layers above these types — builder patterns, retry policies, redirect following, connection pooling. The types themselves are not in Tier 2.

**Q3: HTTP server — std.http.server (5-0 for Tier 2)**

- **Systems:** Server module is the largest stdlib module by code volume. Including it in every binary unconditionally is wasteful. The `Net.Listen` effect handle provides the primitive.
- **Web/Scripting:** Server frameworks are opinionated. Go's `net/http` locked in 2012 is the cautionary tale. The effect system provides the primitive; the framework should iterate independently.
- **PLT:** `Server`, routing, middleware are application-level composition patterns built ON TOP of `Net.Listen`. These are framework choices, not type-theoretic necessities.
- **DevOps:** Server frameworks evolve fast. `pact init --template web-server` auto-adds it. Version-locking a web framework to compiler release cadence is Go's `net/http` stagnation.
- **AI/ML:** Server routing patterns have the widest variance in LLM training data. Freezing a pattern as T1 creates training/reality mismatch as the framework evolves.

**Q4: SQL/DB — std.db (5-0 for Tier 2)**

- **Systems:** DB drivers require linking against external C libraries (`libpq`, `libsqlite3`). T1 would break the "single compiler binary, no external deps" model.
- **Web/Scripting:** PostgreSQL, SQLite, MySQL each have different type systems and drivers. `Query[C]` and `db.*` effect handles are already the thin interface (like Go's `database/sql`).
- **PLT:** `Query[C]` is compiler-known for injection safety. Types around it (connection pools, transaction builders, row mapping) are library-level concerns with high domain variability.
- **DevOps:** Different projects need different drivers. No single DB package satisfies everyone. Templates (`pact init --template api`) handle onboarding.
- **AI/ML:** Training data shows massive fragmentation (SQLAlchemy vs diesel vs GORM vs prisma). No single API dominates.

**Q5: Logging — std.log (4-1 for Tier 2; DevOps dissented)**

- **Systems:** `io.log()` is the primitive. Structured logging varies by deployment target (cloud JSON logs vs minimal stderr). Version-locking one opinion is unnecessary.
- **Web/Scripting:** `io.log()` is already T1 via the effect system. Structured logging wraps it — a deliberate architectural choice, not a default.
- **PLT:** The effect is the capability; the library is the policy. Coupling policy to compiler version violates capability/policy separation.
- **DevOps:** *(dissent — T1)* `io.log()` compiles but if the default handler lives in T2, calling it does nothing useful without adding a dep. The default IO.Log handler must exist somewhere T1.
- **AI/ML:** LLMs will reach for `io.log("message")` as the default, which already works. Structured logging is a deliberate choice, not something AI should auto-generate.

**Resolution note on DevOps dissent:** The default `IO.Log` handler (which writes to stderr) is part of the **runtime**, not a stdlib module. When `main` has implicit effects, the compiler provides default handlers for all declared effects. `io.log()` works out of the box because the runtime includes a basic handler — no `std.log` import required. `std.log` would add structured logging policy (levels, formatters, sinks) above this default, which is correctly Tier 2.

**Q6: Config — std.config (5-0 for Tier 2)**

- **Systems:** `std.toml` is already T1 for file parsing. Config merging, env var overlay, validation are convenience — not infrastructure.
- **Web/Scripting:** Between `env.var()` and `std.toml`, basic config loading already works. A unified layer is framework-level.
- **PLT:** No compiler-known types, no effect system integration beyond FS.Read and Env.Read. Cleanest T2 case.
- **DevOps:** TOML + Env.Read cover basics. Config patterns are opinionated. Let community converge, then bless.
- **AI/ML:** Config patterns are the most fragmented in training data. Worst possible T1 candidate — novel API with zero training data representation.

