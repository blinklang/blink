## 9. Trust Boundaries & FFI

Pact's type system, effect system, and contract system form a closed verification envelope. Everything inside that envelope is compiler-checked. FFI crosses the boundary of that envelope — foreign code is unverified, untyped (from Pact's perspective), and potentially unsafe. The language treats this boundary explicitly.

### 9.1 FFI Rules and Annotations

Every foreign function call requires three annotations. No exceptions.

#### `@ffi` — Declaring the Foreign Binding

```pact
@ffi("libsodium", "crypto_secretbox_easy")
@effects(Crypto)
@trusted(audit: "SEC-042")
fn sodium_secretbox(
    ciphertext: Ptr[U8],
    message: Ptr[U8],
    msg_len: U64,
    nonce: Ptr[U8],
    key: Ptr[U8]
) -> Int
```

The `@ffi("library", "symbol")` annotation names the shared library and the symbol to link. The compiler does not type-check the foreign function's body — it does not have one. The signature is the developer's claim about what the foreign function expects and returns.

#### `@effects` — Manually Declared Effects

Because the compiler cannot analyze foreign code, effects **must** be declared manually on FFI functions. The compiler trusts this declaration — it cannot verify it. This is the one place in Pact where effect annotations are not compiler-proven.

```pact
@ffi("libcurl", "curl_easy_perform")
@effects(Net, IO)
@trusted(audit: "NET-007")
fn curl_perform(handle: Ptr[Void]) -> Int
```

Omitting `@effects` on an `@ffi` function is a compile error. The compiler refuses to guess.

#### `@trusted` — Audit Trail

The `@trusted` annotation links to an external audit record. It signals that a human has reviewed the FFI binding for correctness (types match the C header, effects are accurate, memory safety is maintained by the wrapper).

```pact
@ffi("sqlite3", "sqlite3_open")
@effects(IO)
@trusted(audit: "DB-003", reviewer: "nhumrich", date: "2026-01-15")
fn sqlite3_open(filename: Ptr[U8], db: Ptr[Ptr[Void]]) -> Int
```

FFI without `@trusted` compiles but emits a warning:

```
warning[W0800]: unaudited foreign function
 --> db/sqlite.pact:4:1
  |
4 | fn sqlite3_open(filename: Ptr[U8], db: Ptr[Ptr[Void]]) -> Int
  | ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  |
  = note: FFI function `sqlite3_open` has no @trusted annotation
  = help: add @trusted(audit: "AUDIT-ID") after review
```

#### Mandatory Safe Wrappers

FFI functions are **not callable from application code directly**. They must be wrapped in a safe Pact function that validates inputs, translates error codes, and presents a Pact-native API.

```pact
// The raw FFI binding — private, unsafe, audited
@ffi("sqlite3", "sqlite3_open")
@effects(IO)
@trusted(audit: "DB-003")
fn raw_sqlite3_open(filename: Ptr[U8], db: Ptr[Ptr[Void]]) -> Int

// The safe wrapper — this is what application code calls
pub fn open_database(path: Str) -> Result[Database, DbError] ! IO {
    let db_ptr = alloc_ptr[Void]()
    let rc = raw_sqlite3_open(path.as_cstr(), db_ptr.addr())
    match rc {
        0 => Ok(Database.from_ptr(db_ptr))
        _ => Err(DbError.from_code(rc))
    }
}
```

The compiler enforces this: any call to an `@ffi` function from outside the declaring module is a compile error. FFI functions are implicitly private — `pub` on an `@ffi` function is rejected.

```
error[E0801]: FFI function cannot be public
 --> db/sqlite.pact:3:1
  |
3 | pub fn sqlite3_open(...) -> Int
  | ^^^ FFI functions must be wrapped in safe Pact functions
  |
  = help: make the FFI function private and create a pub wrapper
```

#### Contract Ineligibility

FFI functions cannot carry `@requires` or `@ensures` annotations. The compiler cannot verify contracts against foreign code. The safe wrapper is where contracts belong:

```pact
@ffi("zlib", "compress")
@effects(IO)
@trusted(audit: "COMP-001")
fn raw_compress(dest: Ptr[U8], dest_len: Ptr[U64], src: Ptr[U8], src_len: U64) -> Int

@requires(data.len() > 0)
@ensures(result.is_ok() => result.unwrap().len() <= data.len())
pub fn compress(data: List[U8]) -> Result[List[U8], CompressError] ! IO {
    // safe wrapper with contracts
}
```

#### `pact audit` — FFI Inventory

The `pact audit` command lists every FFI call site in the project with its declared effects and audit status:

```
$ pact audit

FFI Summary: 7 bindings across 3 modules

  db/sqlite.pact:
    sqlite3_open      effects: IO        audit: DB-003   OK
    sqlite3_exec      effects: IO, DB    audit: DB-004   OK
    sqlite3_close     effects: IO        audit: DB-005   OK

  crypto/sodium.pact:
    crypto_secretbox  effects: Crypto    audit: SEC-042  OK
    crypto_sign       effects: Crypto    audit: SEC-043  OK

  net/curl.pact:
    curl_easy_init    effects: Net       audit: NONE     WARNING
    curl_easy_perform effects: Net, IO   audit: NET-007  OK

Audit coverage: 6/7 (85.7%)
Unaudited: net/curl.pact:curl_easy_init

Raw Query Summary: 2 raw queries across 1 module

  db/legacy.pact:
    Raw()           line 42    UNAUDITED
  db/migration.pact:
    Raw()           line 8     audit: MIG-001  OK

Raw query audit coverage: 1/2 (50%)
```

This output is structured JSON when `--json` is passed. CI pipelines can enforce `pact audit --require-all` to block merges with unaudited FFI.

### 9.2 System Boundary — Runtime Validation

Inside Pact, contracts (`@requires`, `@ensures`) are verified statically by the SMT solver wherever possible. But at the edges of the system — HTTP handlers, CLI entry points, message consumers, gRPC endpoints — input arrives from the outside world. External input cannot satisfy `@requires` statically because the compiler has no control over what a client sends.

The compiler detects system boundary functions and **automatically inserts runtime validation** at these points. This is the one place where runtime contract checking is implicit rather than opt-in.

```pact
@requires(id > 0)
@requires(email.len() > 0)
pub fn create_user(id: Int, email: Str) -> Result[User, ValidationError] ! DB {
    // Inside here, id > 0 and email.len() > 0 are guaranteed
    // ...
}

// When called from an HTTP handler, the compiler inserts runtime checks:
pub fn handle_create_user(req: Request) -> Response ! IO, DB {
    let id = req.param("id").parse_int()?
    let email = req.param("email")?
    // Compiler inserts: runtime check that id > 0 and email.len() > 0
    // Violation returns a structured 400 error, not a panic
    let user = create_user(id, email)?
    Response.json(user)
}
```

How the compiler identifies system boundaries:

1. **HTTP handlers** — functions registered as route handlers via the web framework's effect system
2. **`fn main()`** — the program entry point, when it processes `env.args()`
3. **Message consumers** — functions bound to queue/topic handlers via the messaging effect
4. **gRPC/RPC handlers** — functions exposed as service methods

At these boundaries, `@requires` violations produce structured error responses (HTTP 400, gRPC INVALID_ARGUMENT) rather than panics. The compiler generates the validation code — the developer writes the contract, and the boundary enforcement is automatic.

For internal function calls (Pact calling Pact), the compiler still attempts static proof. If it can prove the caller always satisfies the callee's `@requires`, no runtime check is emitted. If it cannot prove it, a warning is emitted and a runtime assertion is inserted — same as the standard contract behavior described in the contracts section.

### 9.3 Injection Safety — `Query[C]` Parameterized Queries

**Status: v1. Resolved by unanimous panel vote (3-0).**

Pact's universal string interpolation creates an injection risk when interpolated strings flow to databases, shells, or HTML renderers. The `Query[C]` type solves this at the type boundary without taint tracking.

**v1 mechanism:** Effect handle methods that execute interpreted strings accept `Query[C]` instead of `Str`. When an interpolated string literal appears where `Query[C]` is expected, the compiler constructs a parameterized query — `{expr}` becomes a bound parameter, not string concatenation.

```pact
// Developer writes this — identical to a normal interpolated string:
fn get_user(id: Int) -> User? ! DB.Read {
    db.query_one("SELECT * FROM users WHERE id = {id}")
    // Compiler sees: Query.param("SELECT * FROM users WHERE id = $1", [id])
}

// Str → Query is a compile error:
let q: Str = "SELECT * FROM users WHERE id = {id}"
db.query_one(q)  // ERROR: expected Query[DB], got Str
```

**Escape hatch:** `Raw(expr)` is a compiler-known marker type that bypasses parameterization for individual interpolated expressions within `Query[C]` strings. It emits a compiler warning and is tracked by `pact audit --raw-queries` alongside FFI.

```pact
// Auditable escape hatch for dynamic SQL:
db.query_one("SELECT * FROM {Raw(table)} WHERE id = {id}")
// WARNING: Raw() bypasses parameterization for {Raw(table)}
// Note: {id} is still safely parameterized
```

**Extensibility:** The phantom type `C` in `Query[C]` enables the same mechanism for shell commands (`Query[Shell]`), HTML templates (`Query[HTML]`), and other injection contexts. See section 3.12 for the full type specification.

See [DECISIONS.md](../DECISIONS.md) for the full deliberation record.

### 9.4 Information Flow Tracking (v2+ Roadmap)

**Status: v2+ roadmap. Deferred — `Query[C]` covers 95% of injection cases for v1.**

The eventual goal is taint tracking via effect provenance. Values originating from certain effects would carry their provenance through the program, and the compiler would enforce sanitization policies:

```pact
// FUTURE SYNTAX — not finalized
fn handle_query(req: Request) -> Response ! IO, DB {
    let user_input = req.param("q")           // tainted: Net.Read
    // let results = db.query(user_input)      // ERROR: Net.Read value flows to DB.Write
    let sanitized = sql.escape(user_input)     // sanitized: taint cleared
    let results = db.query(sanitized)          // OK
    Response.json(results)
}
```

This requires tracking effect provenance on values — a significant type system extension that interacts with inference, generics, and the effect system. The design challenges:

- **Type inference interaction** — taint labels on values multiply the type space. Inference must track provenance without requiring manual annotation everywhere.
- **Performance** — provenance tracking must not impose runtime cost in production builds. It should be a compile-time-only analysis.
- **Granularity** — which effects produce tainted values? All of them? Only `Net`? Configurable per project?

This is deferred to v2+. The `Query[C]` mechanism in v1 covers the most critical injection cases (SQL, shell, HTML) at the type boundary. Full information flow tracking would catch additional categories (reflected XSS through non-handle paths, data flow between unrelated effects) but at significantly higher implementation cost.

---

## 10. Module System

This section resolves open questions 10.1 (module mapping), 10.3 (visibility), and partially 10.8 (FFI, covered in section 9).

### 10.1 File = Module, Directory = Package

A Pact source file is a module. A directory containing Pact files is a package. No ceremony required.

```
myapp/
  pact.toml           # project manifest
  src/
    main.pact          # module: main (entry point)
    auth/
      login.pact       # module: auth.login
      token.pact       # module: auth.token
      rate_limit.pact  # module: auth.rate_limit
    db/
      connection.pact  # module: db.connection
      queries.pact     # module: db.queries
```

The module name is derived from the file path relative to `src/`. The directory structure IS the package hierarchy. There is no `mod.pact` index file, no `__init__` file, no module declarations in a parent file.

**Why file = module:** Go proved this works at scale. One file, one module, one namespace. No indirection. An AI agent looking at `auth/login.pact` knows immediately that it's the `auth.login` module. No configuration to parse, no module maps to resolve.

#### `@mod` — Explicit Module Naming

The `@mod` annotation at the top of a file overrides the path-derived name. This is optional — most files don't need it.

```pact
// File: src/auth/login.pact
// Without @mod, this module is auth.login
// With @mod, it can be renamed:
@mod("auth")

// Now this file's public items are importable as auth.login(), auth.Token, etc.
// rather than auth.login.login(), auth.login.Token
```

The primary use case for `@mod` is when a directory has a single "main" file that should represent the package itself:

```
auth/
  auth.pact        # @mod("auth") — the package's primary module
  rate_limit.pact  # module: auth.rate_limit
  token.pact       # module: auth.token
```

Without `@mod`, you'd import as `auth.auth.login()`. With `@mod("auth")` on `auth.pact`, you import as `auth.login()`.

**Constraint:** `@mod` can only set the name to the parent package name. You cannot use `@mod` to move a module into a completely different package. The compiler rejects `@mod("billing")` on a file inside `auth/`.

#### Imports

Imports are explicit. No auto-imports, no implicit prelude (except for a minimal set: `Option`, `Result`, `Ok`, `Err`, `Some`, `None`).

```pact
import auth                          // import the auth package
import auth.token                    // import a specific module
import auth.token.{Token, verify}    // import specific items
```

Namespace usage after import:

```pact
import auth

fn handle_login(req: Request) -> Response ! IO, DB, Crypto {
    let session = auth.login(req.email, req.password)?
    // ...
}
```

Or with specific item imports:

```pact
import auth.{login, AuthError}

fn handle_login(req: Request) -> Response ! IO, DB, Crypto {
    let session = login(req.email, req.password)?
    // ...
}
```

**No wildcard imports.** `import auth.*` does not exist. Every name in scope is explicitly imported. This is non-negotiable for locality of reasoning — an AI reading a file can determine every available name from the import block alone.

### 10.2 Visibility: `pub`, Default Private

All items (functions, types, constants, traits) are **module-private by default**. The `pub` keyword makes an item visible to other modules.

```pact
// Private — only this module can call it
fn hash_password(pwd: Str) -> Str ! Crypto {
    crypto.argon2(pwd)
}

// Public — importable by other modules
pub fn login(email: Str, pwd: Str) -> Result[Session, AuthError] ! DB, Crypto {
    let user = find_user(email)?
    let hashed = hash_password(pwd)
    verify(user, hashed)
}

// Public type — part of the module's API
pub type AuthError {
    BadCredentials
    AccountLocked
    RateLimited
}

// Private type — implementation detail, invisible outside this file
type PasswordHash {
    value: Str
    algorithm: Str
    salt: Str
}
```

There is no `pub(crate)`, no `protected`, no `internal`, no `friend`. Two levels: private and public. This is a deliberate constraint.

**Why only two levels:** Visibility modifiers beyond private/public create decision paralysis for both humans and AI. Rust's `pub(crate)`, `pub(super)`, `pub(in path)` are almost never used correctly on the first try. Two levels means zero ambiguity: either something is part of the API or it isn't.

**Package-level visibility:** If a module needs to expose items only to sibling modules within the same package (not to external consumers), use a convention: create an `internal.pact` module that re-exports internal items. External consumers see the package's public API; internal modules import from `internal`. This is a convention, not a language feature — keeping the language simple.

### 10.3 Module Capability Budgets

A module can declare a capability ceiling with `@capabilities`. This sets a hard upper bound on what effects any function in the module is allowed to perform.

```pact
@mod("auth")
@capabilities(DB, Crypto, IO)

// OK — DB and Crypto are within budget
pub fn login(email: Str, pwd: Str) -> Result[Session, AuthError] ! DB, Crypto {
    // ...
}

// COMPILE ERROR — Net is not in the capability budget
pub fn call_external_api(url: Str) -> Str ! Net {
    // ...
}
```

```
error[E0900]: effect exceeds module capabilities
 --> auth/login.pact:15:1
  |
1 | @capabilities(DB, Crypto, IO)
  | ----------------------------- module capability budget
  ...
15| pub fn call_external_api(url: Str) -> Str ! Net {
  |                                             ^^^ effect `Net` not in budget
  |
  = note: module `auth` allows: DB, Crypto, IO
  = help: add `Net` to @capabilities or move this function to a different module
```

**Why capability budgets:** They enforce architectural boundaries at compile time. The auth module should never make network calls — that's a code smell indicating misplaced responsibility. Without capability budgets, an AI might add a "convenient" HTTP call inside an auth function, slowly eroding module boundaries. With `@capabilities`, the compiler stops it immediately.

Capability budgets compose hierarchically. A package-level `@capabilities` in the directory's primary module constrains all modules in that package:

```pact
// auth/auth.pact
@mod("auth")
@capabilities(DB, Crypto, IO)
// All modules under auth/ inherit this ceiling
```

A child module can declare a **narrower** budget but never a wider one:

```pact
// auth/token.pact — can narrow the budget
@capabilities(Crypto)

// Only Crypto is allowed here, not DB or IO
pub fn issue_token(user: User) -> Token ! Crypto {
    // ...
}
```

Omitting `@capabilities` means "no restrictions" — the module can use any effect. This is the default for application code. Library authors should always set capability budgets.

### 10.4 Provenance Tracking (`@src`)

The `@src` annotation links code to external artifacts: requirements documents, design RFCs, issue trackers, compliance mandates.

```pact
@src(req: "AUTH-001")
@src(design: "RFC-2026-07")
@src(issue: "GH-1234")
@src(compliance: "SOC2-CC6.1")
pub fn login(email: Str, pwd: Str) -> Result[Session, AuthError] ! DB, Crypto {
    // ...
}
```

Provenance is metadata — it does not affect compilation, type checking, or code generation. It is tracked by the compiler and queryable through tooling.

#### `pact trace` — Requirement Traceability

```
$ pact trace AUTH-001

Requirement: AUTH-001
Linked code:

  auth/login.pact:
    pub fn login(...)           @src(req: "AUTH-001")
    fn verify_credentials(...)  @src(req: "AUTH-001")

  auth/rate_limit.pact:
    pub fn check_rate(...)      @src(req: "AUTH-001")

  auth/token.pact:
    pub fn issue_token(...)     @src(req: "AUTH-001")

Coverage: 4 functions, 2 test blocks
Last modified: 2026-01-28
```

Reverse tracing works too:

```
$ pact trace --reverse auth.login

Function: auth.login
Links:
  req: AUTH-001 (User authentication)
  design: RFC-2026-07 (Auth system redesign)
  issue: GH-1234 (Add rate limiting to login)
  compliance: SOC2-CC6.1 (Logical access controls)
```

**Why provenance in the language:** Compliance-heavy environments (healthcare, finance, government) require traceability from requirements to code. Currently this lives in spreadsheets, Jira queries, and tribal knowledge. Embedding it in the source makes it versionable, verifiable, and impossible to lose. For AI agents, provenance provides context about _why_ code exists — not just what it does.

---

## 11. Metadata & Annotations

Annotations use the `@` prefix and are compiler-checked. They are not comments, not decorators, not optional. They participate in type checking, verification, optimization, and tooling.

### 11.1 Complete Annotation Reference

| Annotation | Target | Purpose | Checked by |
|------------|--------|---------|------------|
| `@i("text")` | fn, type, module | Intent declaration. Natural-language description of purpose. | Tooling (versioned, queryable, drift detection) |
| `@src(kind: "ID")` | fn, type, module | Provenance link to requirement, design doc, issue, or compliance mandate. | `pact trace` tooling |
| `@requires(expr)` | fn | Precondition. Must hold when the function is called. | SMT solver (compile-time) or runtime assertion |
| `@ensures(expr)` | fn | Postcondition. Must hold when the function returns. `result` refers to the return value. | SMT solver (compile-time) or runtime assertion |
| `@where(expr)` | fn, type | Type-level constraint on generics or refinements. | Compile-time type checker |
| `@invariant(expr)` | type | Invariant that must hold for all instances of this type at all times. | SMT solver + runtime checks on construction/mutation |
| `@perf(constraint)` | fn | Performance contract. Benchmark assertion, not statically provable. | `pact bench --check-contracts` |
| `@capabilities(list)` | module | Hard ceiling on effects permitted in this module. | Compile-time effect checker |
| `@ffi("lib", "sym")` | fn | Declares a foreign function binding. | Linker (compile-time) |
| `@trusted(audit: "ID")` | fn (with @ffi) | Audit trail for reviewed FFI bindings. | `pact audit` tooling |
| `@effects(list)` | fn (with @ffi) | Manually declared effects for foreign functions. | Compile-time effect checker |
| `@alt("ID", "desc")` | fn | Marks an alternative implementation. | Tooling (`pact alt list`, `pact alt select`) |
| `@verify(strategy)` | fn | Hints to the SMT solver about verification strategy. | Verification engine |
| `@derive(Trait, ...)` | type | Auto-generate trait implementations. Compiler-known traits only in v1: `Eq`, `Ord`, `Hash`, `Debug`, `Clone`, `Display`. | Compile-time codegen |
| `@deprecated("msg")` | fn, type | Deprecation notice with migration guidance. Emits warning at call sites. | Compiler warning |

#### Canonical Ordering

`pact fmt` enforces a deterministic annotation order. No style debates.

```pact
@mod("auth")                          // 1. module declaration
@capabilities(DB, Crypto)             // 2. capability budget
@src(req: "AUTH-001")                 // 3. provenance

@i("Main authentication flow")       // 4. intent
@src(req: "AUTH-001")                 // 5. provenance (on function)
@requires(email.len() > 0)           // 6. preconditions
@ensures(result.is_ok() => result.unwrap().token.is_valid())  // 7. postconditions
@perf(p99 < 200ms)                   // 8. performance contracts
@deprecated("Use login_v2 instead")  // 9. deprecation
pub fn login(email: Str, pwd: Str) -> Result[Session, AuthError] ! DB, Crypto {
    // ...
}
```

The ordering: `@mod` > `@capabilities` > `@derive` > `@src` > `@i` > `@requires` > `@ensures` > `@where` > `@invariant` > `@perf` > `@ffi` > `@trusted` > `@effects` > `@alt` > `@verify` > `@deprecated`.

Rationale: metadata about the container (module, capabilities) comes first. Then intent and provenance (why does this exist?). Then contracts (what must be true?). Then operational concerns (performance, FFI). Then lifecycle (alternatives, deprecation).

### 11.2 Performance Contracts (`@perf`)

Performance contracts are **benchmark assertions**. They are explicitly NOT statically provable — the SMT solver does not attempt to verify them. They exist in a separate verification domain from `@requires`/`@ensures`.

```pact
@perf(p99 < 200ms)
@perf(memory < 50mb)
@perf(throughput > 1000rps)
pub fn process_batch(items: List[Item]) -> Summary ! DB, IO {
    // ...
}
```

#### What `@perf` Is

- A **benchmark target** checked by `pact bench --check-contracts`
- A **CI gate** — the benchmark runner fails if the constraint is violated
- A **regression detector** — performance changes are caught the same way type errors are
- A **documentation signal** — developers and AI know the performance expectations from the signature

#### What `@perf` Is Not

- Not a compile-time guarantee. The compiler does not attempt to prove performance properties.
- Not a runtime enforcement mechanism. `@perf` does not insert timing checks into production code.
- Not a contract in the formal verification sense. It will never be fed to the SMT solver.

#### Supported Constraints

| Constraint | Meaning | Example |
|------------|---------|---------|
| `p50 < Xms` | 50th percentile latency | `@perf(p50 < 50ms)` |
| `p95 < Xms` | 95th percentile latency | `@perf(p95 < 150ms)` |
| `p99 < Xms` | 99th percentile latency | `@perf(p99 < 200ms)` |
| `memory < Xmb` | Peak memory usage | `@perf(memory < 50mb)` |
| `throughput > Xrps` | Requests per second | `@perf(throughput > 1000rps)` |
| `allocs < N` | Heap allocations per call | `@perf(allocs < 100)` |

#### Usage in CI

```sh
pact bench                     # run all benchmarks
pact bench --check-contracts   # run and fail if any @perf violated
pact bench --module auth       # benchmark a specific module
pact bench --json              # structured output for CI integration
```

Example CI failure:

```
$ pact bench --check-contracts

FAIL  auth.login
  @perf(p99 < 200ms) — measured p99: 342ms (exceeded by 142ms)
  Benchmark: 10000 iterations, 3 warmup rounds

PASS  auth.check_rate
  @perf(p99 < 50ms) — measured p99: 12ms

1 of 2 performance contracts violated.
```

### 11.3 Provenance (`@src`)

Provenance links code to the external artifacts that justify its existence. Four categories are supported:

| Kind | Purpose | Example |
|------|---------|---------|
| `req` | Requirement document | `@src(req: "AUTH-001")` |
| `design` | Design document or RFC | `@src(design: "RFC-2026-07")` |
| `issue` | Issue tracker reference | `@src(issue: "GH-1234")` |
| `compliance` | Regulatory or compliance mandate | `@src(compliance: "SOC2-CC6.1")` |

Multiple `@src` annotations can stack:

```pact
@src(req: "AUTH-001")
@src(design: "RFC-2026-07")
@src(issue: "GH-1234")
@src(compliance: "SOC2-CC6.1")
pub fn login(email: Str, pwd: Str) -> Result[Session, AuthError] ! DB, Crypto {
    // ...
}
```

#### Provenance on Types

Types can carry provenance too — useful when a type exists because of a specific requirement:

```pact
@src(compliance: "PCI-DSS-3.4")
@invariant(self.value.len() == 16)
pub type MaskedCardNumber {
    value: Str
}
```

#### Provenance on Modules

Module-level provenance applies to the entire module:

```pact
@mod("auth")
@src(req: "AUTH-001", "AUTH-002", "AUTH-003")
@src(design: "RFC-2026-07")

// All functions in this file inherit the module-level provenance context
```

#### Tooling Integration

Provenance is queryable through the compiler-as-service API and the CLI:

```sh
pact trace AUTH-001              # find all code linked to AUTH-001
pact trace --reverse auth.login  # find all artifacts linked to auth.login
pact trace --coverage            # report which requirements have implementing code
pact trace --orphans             # find code with no provenance links
pact trace --stale               # find provenance links to closed/deleted issues
```

The `--coverage` report is designed for compliance audits:

```
$ pact trace --coverage

Requirement Coverage:
  AUTH-001  4 functions, 2 tests    COVERED
  AUTH-002  2 functions, 1 test     COVERED
  AUTH-003  0 functions, 0 tests    MISSING
  PAY-001   3 functions, 0 tests    PARTIAL (no tests)

Coverage: 2/4 fully covered (50%)
```

Provenance is metadata — it has zero runtime cost, zero impact on compilation, and zero interaction with the type system. It exists purely for traceability and tooling. But it is compiler-tracked, meaning the compiler knows about it, stores it in the AST, and exposes it through the query API. It is not a comment that can silently drift.
