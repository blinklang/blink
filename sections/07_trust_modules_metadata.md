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

### 9.1.1 FFI Type Specification

This section formally defines the pointer types, operations, and lifetime semantics used by FFI bindings. These types exist **exclusively for C interop** — they are not general-purpose Pact types and are not available in the module prelude.

#### The `Ptr[T]` Type

`Ptr[T]` is a compiler-known generic type representing a typed C pointer. It maps directly to `T*` in the generated C code.

```pact
import pact.ffi.{Ptr, Void, alloc_ptr, null_ptr}
```

**Nullability:** `Ptr[T]` is **non-null by default**. A `Ptr[T]` value is guaranteed to point to valid memory. Nullable pointers use `Ptr[T]?` (sugar for `Option[Ptr[T]]`), consistent with Pact's existing `Option` semantics.

```pact
// Non-null pointer — guaranteed to point to something
fn raw_sqlite3_exec(db: Ptr[Void], sql: Ptr[U8]) -> Int

// Nullable pointer — C function may return NULL
@ffi("libc", "getenv")
@effects(Env)
@trusted(audit: "ENV-001")
fn raw_getenv(name: Ptr[U8]) -> Ptr[U8]?
```

At FFI return boundaries, the compiler inserts a null-check for functions declared as returning non-null `Ptr[T]`. If C returns `NULL` where the Pact signature promises `Ptr[T]`, the program panics with a diagnostic. FFI functions that may return `NULL` **must** declare `Ptr[T]?` as the return type.

**Nesting:** `Ptr[Ptr[T]]` is allowed and maps to `T**`. This is required for C out-parameters (e.g., `sqlite3_open`'s `sqlite3**` parameter).

**The `Void` type:** `Void` is a special opaque type valid **only** as a `Ptr` type parameter. It maps to C's `void` — `Ptr[Void]` is `void*`. `Void` cannot be used as a standalone type, function parameter, or return type outside of `Ptr`.

**Valid type parameters:** `Ptr[T]` accepts only FFI-compatible types: `Void`, `U8`, `U16`, `U32`, `U64`, `I8`, `I16`, `I32`, `Int` (maps to `int64_t`), `Float` (maps to `double`), and `Ptr[T]` itself (for pointer-to-pointer). Using a GC-managed type (e.g., `Ptr[Str]`, `Ptr[List[T]]`) is a compile error.

```
error[E0810]: invalid Ptr type parameter
 --> db/sqlite.pact:5:20
  |
5 | fn bad(data: Ptr[Str]) -> Int
  |                  ^^^ `Str` is GC-managed and cannot be pointed to
  |
  = help: use `Ptr[U8]` for C strings, convert with `.as_cstr()`
```

#### Pointer Operations

All pointer operations are methods on `Ptr[T]` and functions in the `pact.ffi` module. They are available only in modules that `import pact.ffi`.

| Operation | Signature | C Mapping | Description |
|-----------|-----------|-----------|-------------|
| `alloc_ptr[T]()` | `fn alloc_ptr[T]() -> Ptr[T]` | `calloc(1, sizeof(T))` | Allocate zero-initialized memory for one `T` |
| `null_ptr[T]()` | `fn null_ptr[T]() -> Ptr[T]?` | `NULL` | Create a null pointer (returns `None`) |
| `.deref()` | `fn deref(self) -> Option[T]` | null-check + `*ptr` | Read the value behind the pointer. Returns `None` if null |
| `.write(value)` | `fn write(self, value: T)` | `*ptr = value` | Write a value through the pointer |
| `.is_null()` | `fn is_null(self) -> Bool` | `ptr == NULL` | Check if pointer is null |
| `.addr()` | `fn addr(self) -> Ptr[Ptr[T]]` | `&ptr` | Get pointer-to-pointer for C out-parameters |
| `.as_cstr()` | `fn as_cstr(self: Str) -> Ptr[U8]` | `strdup(s)` | Convert Pact `Str` to null-terminated C string copy |
| `.to_str()` | `fn to_str(self: Ptr[U8]) -> Option[Str]` | null-check + copy | Convert null-terminated C string to Pact `Str` |

**`.deref()` semantics:** Returns `Option[T]`. If the pointer is null, returns `None`. If non-null, reads the value and returns `Some(value)`. On a non-null `Ptr[T]`, the compiler may optimize away the null check — but the return type remains `Option[T]` for uniformity.

**`.write()` restriction:** Writing a GC-managed reference through a pointer is a compile error. Only FFI-compatible values (integers, floats, other pointers) can be written.

**`.as_cstr()` semantics:** Creates a `malloc`'d null-terminated copy of the Pact string's bytes. The copy is allocated outside the GC and must be freed via `ffi.scope()` or manual cleanup. This is a method on `Str`, not on `Ptr[T]`.

**`.to_str()` semantics:** Reads bytes from a `Ptr[U8]` until a null terminator, creates a GC-managed Pact `Str`. Returns `None` if the pointer is null.

#### Example: Complete FFI Wrapper

```pact
import pact.ffi.{Ptr, Void, alloc_ptr}

@ffi("sqlite3", "sqlite3_open")
@effects(IO)
@trusted(audit: "DB-003")
fn raw_sqlite3_open(filename: Ptr[U8], db: Ptr[Ptr[Void]]) -> Int

@ffi("sqlite3", "sqlite3_close")
@effects(IO)
@trusted(audit: "DB-004")
fn raw_sqlite3_close(db: Ptr[Void]) -> Int

pub fn open_database(path: Str) -> Result[Database, DbError] ! IO {
    with ffi.scope() as scope {
        let db_ptr = scope.alloc[Void]()
        let cstr = scope.cstr(path)
        let rc = raw_sqlite3_open(cstr, db_ptr.addr())
        match rc {
            0 => {
                match db_ptr.deref() {
                    Some(raw_db) => Ok(Database.from_ptr(scope.take(raw_db)))
                    None => Err(DbError.NullResult)
                }
            }
            _ => Err(DbError.from_code(rc))
        }
    }
}
```

#### Lifetime and Cleanup: `ffi.scope()`

Pointer memory is managed through **scoped allocation** using `ffi.scope()`, which integrates with Pact's existing `Closeable` trait and `with...as` syntax (§5.5).

```pact
import pact.ffi

with ffi.scope() as scope {
    let ptr = scope.alloc[U8]()       // allocated within scope
    let cstr = scope.cstr("hello")    // C string copy within scope
    raw_process(ptr, cstr)
}
// scope.close() runs here: frees ptr, cstr, and all scope allocations
```

**`ffi.scope()` operations:**

| Operation | Signature | Description |
|-----------|-----------|-------------|
| `scope.alloc[T]()` | `fn alloc[T](self) -> Ptr[T]` | Allocate zero-initialized memory, tracked by scope |
| `scope.cstr(s)` | `fn cstr(self, s: Str) -> Ptr[U8]` | Create scoped null-terminated C string copy |
| `scope.take(ptr)` | `fn take[T](self, ptr: Ptr[T]) -> Ptr[T]` | Transfer pointer ownership out of scope (not freed at scope exit) |

**Scope rules:**
- All allocations made through a scope are freed when the `with` block exits (normal return, `?` early return, or any other exit path).
- `scope.take(ptr)` removes a pointer from the scope's cleanup list. The caller assumes responsibility for the pointer's lifetime — typically by wrapping it in a safe Pact type whose `Closeable.close()` calls the appropriate C cleanup function.
- Scope-allocated pointers that escape the scope without `.take()` trigger a compile error (reusing E0601 from `Closeable` diagnostics).

**Long-lived pointers:** For C handles that must outlive a lexical scope (e.g., a database connection stored in a struct field), use `scope.take()` to transfer ownership, then wrap in a `Closeable` type:

```pact
pub type Database {
    handle: Ptr[Void]
}

impl Closeable for Database {
    fn close(self) ! IO {
        raw_sqlite3_close(self.handle)
    }
}

pub fn open_database(path: Str) -> Result[Database, DbError] ! IO {
    with ffi.scope() as scope {
        let db_ptr = scope.alloc[Void]()
        let cstr = scope.cstr(path)
        let rc = raw_sqlite3_open(cstr, db_ptr.addr())
        match rc {
            0 => {
                match db_ptr.deref() {
                    Some(raw_db) => Ok(Database { handle: scope.take(raw_db) })
                    None => Err(DbError.NullResult)
                }
            }
            _ => Err(DbError.from_code(rc))
        }
    }
}
```

**Standalone `alloc_ptr[T]()`:** The top-level `alloc_ptr[T]()` function (not on a scope) allocates GC-registered memory with a finalizer that calls `free()` on collection. This is the fallback for simple cases where scoped allocation is unnecessarily ceremonial. Prefer `ffi.scope()` for deterministic cleanup.

```pact
// Simple case: GC handles cleanup
let buf = alloc_ptr[U8]()  // GC-registered, freed on collection
let rc = raw_gethostname(buf, 256)
let hostname = buf.to_str() ?? "unknown"
// buf freed whenever GC collects it
```

**Guidance:** Use `ffi.scope()` when the C library requires deterministic cleanup (databases, file handles, allocated buffers). Use standalone `alloc_ptr` only for trivial, short-lived allocations where GC collection is acceptable.

#### Diagnostic Integration

Pointer types integrate with Pact's existing diagnostic infrastructure:

```
error[E0810]: invalid Ptr type parameter
 --> crypto/sodium.pact:5:20
  |
5 | fn bad(data: Ptr[List[U8]]) -> Int
  |                  ^^^^^^^^ `List[U8]` is GC-managed
  |
  = help: use `Ptr[U8]` and convert manually

error[E0811]: Ptr[T] used outside FFI context
 --> app/main.pact:12:5
  |
12|     let p = alloc_ptr[Int]()
  |     ^^^^^^^^^^^^^^^^^^^^^^^^ pointer allocation outside @ffi module
  |
  = note: Ptr types are for FFI interop only
  = help: use normal Pact types for application code

warning[W0810]: unscoped pointer allocation
 --> db/sqlite.pact:15:5
  |
15|     let ptr = alloc_ptr[Void]()
  |     ^^^^^^^^^^^^^^^^^^^^^^^^^^^ allocated outside `ffi.scope()`
  |
  = help: wrap in `with ffi.scope() as scope { scope.alloc[Void]() }`
  = note: unscoped pointers rely on GC finalization (non-deterministic)
```

`pact audit` includes pointer allocations alongside FFI call sites and `Raw()` query sites:

```
Pointer Allocations: 3 across 2 modules
  db/sqlite.pact:
    ffi.scope()       line 15    scoped (OK)
    ffi.scope()       line 28    scoped (OK)
  net/curl.pact:
    alloc_ptr[Void]   line 7     unscoped (WARNING)
```

### 9.1.2 Native Dependency Resolution

When Pact code uses `@ffi` to bind a C library, the compiler must *link* against that library. On the host system, dynamic linking (`-l`) works if the library is installed. Cross-compilation breaks this: the target system's libraries are not available on the build machine.

This section specifies how native C dependencies are declared, resolved, and linked — for both user `@ffi` bindings and compiler-provided built-in modules.

#### Two-Tier Model: Compiler-Managed vs User-Managed

Native C dependencies fall into two categories:

**Compiler-managed** dependencies back language-defined effect domains. The `db.*` operations (backed by sqlite3) and `net.*` operations (backed by POSIX sockets) are language primitives — they participate in the effect system, have compiler-known semantics, and are defined by the language, not imported from C headers. The compiler is responsible for providing these dependencies on all supported targets. Users never declare them in `pact.toml`.

**User-managed** dependencies are C libraries bound via `@ffi`. The user is responsible for declaring how to resolve them. The compiler cannot know what arbitrary C libraries a project needs.

The boundary is crisp: if the API is behind a Pact effect handle (`db.*`, `net.*`, `io.*`), the compiler manages its native deps. If it's raw `@ffi`, the user manages it.

#### `[native-dependencies]` in `pact.toml`

User `@ffi` bindings require a corresponding entry in the `[native-dependencies]` section of `pact.toml`. An `@ffi` annotation referencing a library not declared in `[native-dependencies]` is a compile error.

```toml
[native-dependencies]
# System library — dynamic link, must be installed on target
libsodium = { type = "system" }

# Vendored source — compiled alongside generated C
libpq = { type = "vendored", path = "vendor/libpq.c" }

# pkg-config lookup (host builds only, cross-compile falls back to vendored)
zlib = { type = "pkg-config", name = "zlib" }
```

**Schema:**

| Field | Type | Description |
|-------|------|-------------|
| `type` | `"system"` \| `"vendored"` \| `"pkg-config"` | How to resolve the library |
| `path` | `Str` (optional) | Path to vendored C source file(s), relative to project root |
| `name` | `Str` (optional) | pkg-config package name (defaults to dependency key) |
| `link` | `"static"` \| `"dynamic"` (optional) | Override default linking strategy |

**Diagnostic — missing native dependency:**

```
error[E0820]: @ffi references undeclared native dependency
 --> crypto/sodium.pact:3:1
  |
3 | @ffi("libsodium", "crypto_secretbox_easy")
  | ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ library "libsodium" not in [native-dependencies]
  |
  = help: add to pact.toml:
  = help:   [native-dependencies]
  = help:   libsodium = { type = "system" }
```

#### Linking Strategy

The compiler uses different linking strategies for host and cross-compilation targets:

**Host builds** (`pact build` with no `--target`): Dynamic linking by default. The compiler uses system-installed libraries via `-l` flags. `pkg-config` entries are resolved via the host's `pkg-config` tool.

**Cross-compilation** (`pact build --target <triple>`): Static linking by default. The compiler compiles vendored C sources alongside the generated C output using the cross-compiler (e.g., `zig cc -target <triple>`). Dependencies declared as `type = "system"` with no vendored fallback produce a clear error:

```
error[E0821]: native dependency unavailable for cross-target
 --> pact.toml:8:1
  |
8 | libsodium = { type = "system" }
  | ^^^^^^^^^ "libsodium" is system-only but target is aarch64-linux-gnu
  |
  = note: cross-compilation requires vendored source or static archive
  = help: provide source: libsodium = { type = "vendored", path = "vendor/sodium.c" }
  = help: or override linking: libsodium = { type = "system", link = "dynamic" }
```

The `link = "dynamic"` override forces dynamic linking for a cross-target. This is an explicit opt-in — the user accepts that the target system must have the library installed.

**Compiler-managed deps** follow the same strategy automatically: the compiler bundles source for its own dependencies (e.g., the sqlite3 amalgamation) and compiles them from source during cross-compilation, or dynamically links on the host. Users never interact with this.

#### Compiler-Managed Dependency List

The following native C dependencies are compiler-managed. This list is exhaustive — additions require a spec revision:

| Module | C Dependency | Strategy |
|--------|-------------|----------|
| `db.*` | sqlite3 | Amalgamation bundled with compiler |
| `net.*` | POSIX sockets | System headers (no library linkage) |
| runtime | libc, libm | System (always available) |
| `async.*` | pthreads | System (`-pthread` flag) |

#### Interaction with `pact audit`

`pact audit` includes native dependency status alongside FFI call sites:

```
Native Dependencies:
  compiler-managed:
    sqlite3           bundled (3.45.0)    OK
    pthreads          system              OK
  user-managed:
    libsodium         vendored            vendor/sodium.c    OK
    zlib              pkg-config          host-only          WARNING (no cross-target source)
```

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

1. **HTTP handlers** — functions passed to `server.route()`, `server.get()`, `server.post()`, etc. (§4.4.2). The compiler marks these as boundary entry points at route registration time.
2. **`fn main()`** — the program entry point, when it processes `env.args()`
3. **Message consumers** — functions bound to queue/topic handlers via the messaging effect
4. **gRPC/RPC handlers** — functions exposed as service methods

At these boundaries, `@requires` violations are routed through the `Validation` effect (§4.4.2). The compiler generates `validation.contract_violation(param, constraint, value)` calls instead of panics. The default `Validation` handler returns a structured 400 JSON response:

```json
{
    "error": "validation_failed",
    "violations": [
        { "param": "id", "constraint": "id > 0", "value": "-1" }
    ]
}
```

Users can swap the validation handler via `with custom_handler { server.serve() }` to customize the response format (422, JSON:API, localized messages) without modifying handler code.

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

Imports are explicit. No auto-imports beyond the module prelude (§10.6), which provides all compiler-known types, constructors, and traits.

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

#### 10.1.1 No Inline Modules

Pact has no `mod name { }` syntax for creating sub-modules within a file. The `mod` keyword is reserved but unused in v1.

**The rule is absolute: one file = one module.** If you need a sub-module, create a separate file in a subdirectory.

```
// WRONG — not valid Pact syntax:
mod schema {
    type SchemaRule { ... }
    pub fn validate(obj: Map) -> Result[(), Error] { ... }
}

// RIGHT — create a separate file:
//   json_validator/schema.pact
// Then import it:
import json_validator.schema.{SchemaRule, validate}
```

**Why no inline modules:** Inline modules create a second module-like entity alongside file-modules, introducing ambiguity about visibility, importability, and identity. Go demonstrated that "package = directory" scales without inline namespaces. Maintaining one kind of module keeps the import story, tooling (LSP go-to-definition, symbol search), and AI code generation maximally simple.

**Panel vote: 4-1** (Web/Scripting dissented, preferring file-scoped namespaces for lightweight grouping). See [DECISIONS.md](../DECISIONS.md).

If `mod name { }` syntax is encountered, the compiler reports:

```
error[E1015]: inline modules are not supported
 --> app.pact:10:1
  |
10| mod schema {
  | ^^^ Pact uses file-based modules
  |
  = help: create a separate file `schema.pact` in a subdirectory instead
  = note: see §10.1 — one file = one module
```

### 10.2 Visibility: `pub`, Default Private

All items (functions, types, constants, let bindings, traits) are **module-private by default**. The `pub` keyword makes an item visible to other modules.

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

**`pub let` exports immutable module-level bindings.** A module-level `let` (without `mut`) marked `pub` is importable by other modules as a read-only value. `pub let mut` is a compile error (E1006) — mutable state must be accessed through functions, with mutation tracked by the compiler's write-set analysis (§4.16). See §2.12.1 for full rules on module-level bindings.

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

### 10.5 Import Resolution

This section specifies how the compiler resolves `import` declarations to source files, handles dependency versions, detects cycles, and supports re-exports.

#### Resolution Algorithm

Import resolution is a deterministic function from module path to file path. No search path lists, no environment variables, no `PACT_PATH`.

**Local modules** (project source):

```
resolve("auth.token") → <project>/src/auth/token.pact
resolve("auth")       → <project>/src/auth.pact (if @mod("auth"))
                        OR <project>/src/auth/ (package — exposes pub items)
```

The compiler resolves module paths relative to the project's `src/` directory. The path segment separator `.` maps to the filesystem `/`. The file extension `.pact` is implicit and must not appear in the import.

```pact
import auth.token           // resolves to src/auth/token.pact
import auth.token.{Token}   // resolves to src/auth/token.pact, imports Token
import db.connection        // resolves to src/db/connection.pact
```

**External dependencies** (from `pact.lock`):

```pact
import std.http            // stdlib or dependency declared in pact.toml
import std.json.{parse}    // specific item from dependency
```

External packages are namespaced by their registry org/name (§8.9.2, §8.9.7). The `std/http` package is imported as `std.http`. The compiler resolves them from the lockfile's content-addressed store (or from the bundled stdlib for implicit deps — see §10.7). The resolution order:

1. Check local `src/` for a matching path
2. Check dependencies declared in `pact.toml` (resolved via `pact.lock`)
3. No match → compile error

Local modules shadow dependencies with the same name. This is intentional — it allows wrapping a dependency without changing consumer imports. The compiler emits a warning when shadowing occurs:

```
warning[W1000]: local module shadows dependency
 --> src/http.pact:1:1
  |
1 | @mod("http")
  | ^^^^^^^^^^^^ shadows package `pact.http` from pact.toml
  |
  = help: this is allowed but may confuse consumers expecting the library
```

#### `@mod` Resolution

When a file declares `@mod("parent_package")`, its public items merge into the parent package namespace. The compiler validates that `@mod` only refers to the immediate parent:

```
src/auth/
  auth.pact         @mod("auth") — items available as auth.X
  token.pact        items available as auth.token.X
  rate_limit.pact   items available as auth.rate_limit.X
```

If two files in the same directory both declare `@mod` with the same name, or if `@mod` conflicts with a sibling module name, the compiler rejects it:

```
error[E1001]: duplicate module name
 --> src/auth/helpers.pact:1:1
  |
1 | @mod("auth")
  | ^^^^^^^^^^^^ module name `auth` already claimed by src/auth/auth.pact
```

#### Cycle Detection

**Intra-package cycles are allowed.** Modules within the same package (directory) may import each other freely. The compiler resolves all declarations within a package before type-checking bodies — the same approach used by ML-family languages.

```pact
// src/auth/login.pact
import auth.types.{AuthError}    // sibling — allowed

// src/auth/types.pact
import auth.login.{LoginEvent}   // sibling — allowed (intra-package cycle)
```

Within a package, the compiler:
1. Collects all declarations (function signatures, types, traits) from all modules in the package
2. Builds a unified symbol table for the package
3. Type-checks all function bodies against the unified table

**Cross-package cycles are compile errors.** If package `auth` imports from package `billing` and `billing` imports from `auth`, the compiler rejects it:

```
error[E1002]: circular package dependency
  |
  = note: auth → billing → auth
  = help: extract shared types into a common package
```

Cross-package cycles indicate an architectural boundary violation. The fix is always to extract shared types into a third package that both depend on.

#### Diamond Dependencies

**Exactly one version per package.** If two dependencies require different versions of the same transitive dependency, the compiler reports a conflict:

```
error: dependency version conflict
  myapp depends on http 0.5
  auth 1.0 depends on http 0.6

  resolution: only one version of `http` allowed in the dependency graph

  help: run `pact update http` to find a compatible version
        or pin auth to a version compatible with http 0.5
```

One-version-per-package is required for type identity. If `auth` produces an `http.Response` from http 0.6 and `myapp` expects `http.Response` from http 0.5, these are incompatible types. Allowing both silently would violate Pact's explicit-over-implicit philosophy.

The `pact update` command uses minimum version selection: it picks the lowest version that satisfies all constraints. This makes builds reproducible — adding a dependency never upgrades unrelated transitive deps.

#### Re-exports (`pub import`)

A module can re-export items from other modules using `pub import`. This decouples a package's public API from its internal file structure.

```pact
// src/auth/auth.pact
@mod("auth")
pub import auth.token.{Token, verify}
pub import auth.login.{login, AuthError}
pub import auth.rate_limit.{RateLimiter}

// Consumers import from the package directly:
// import auth.{Token, login, AuthError}
// instead of knowing the internal module structure
```

`pub import` rules:
- Re-exported items must be `pub` in their source module
- Re-exports are transitive — `pub import` of a `pub import` works
- The compiler tracks the original declaration for go-to-definition (LSP lands on the source, not the re-export)
- `pub import` of an entire module re-exports all its `pub` items: `pub import auth.token` makes `auth.Token`, `auth.verify` etc. available
- Circular re-exports are detected and rejected at compile time

Re-exports enable API evolution: moving a type from `auth.token` to `auth.session` internally only requires updating the `pub import` in the package root — downstream consumers' imports don't change.

#### Import Errors

| Code | Error | Cause |
|------|-------|-------|
| E1000 | Module not found | No file at resolved path, no matching dependency |
| E1001 | Duplicate module name | Two files claim same `@mod` name |
| E1002 | Circular package dependency | Cross-package import cycle |
| E1003 | Item not found | Named item doesn't exist or isn't `pub` in the target module |
| E1004 | Version conflict | Diamond dependency with incompatible versions |
| E1005 | Ambiguous import | Item name exists in multiple imported modules (use qualified path) |

```
error[E1003]: item `Token` is private in module `auth.internal`
 --> src/api/handler.pact:2:1
  |
2 | import auth.internal.{Token}
  |                       ^^^^^ not visible — `Token` is not `pub`
  |
  = help: import from the public API: `import auth.{Token}`
```

```
error[E1005]: ambiguous import `Error`
 --> src/main.pact:4:1
  |
2 | import auth.{Error}
3 | import db.{Error}
  |
  = note: `Error` exists in both `auth` and `db`
  = help: use qualified names: `auth.Error` and `db.Error`
         or rename: `import auth.{Error as AuthError}`
```

#### Import Aliases

Imports can be renamed at the import site to resolve ambiguity or improve local clarity:

```pact
import auth.{AuthError as LoginError}
import db.connection.{Connection as DbConn}
```

Aliases are local to the importing file. They do not affect the imported module or any other consumers.

### 10.6 Module Prelude

Every Pact module has a set of names automatically in scope — the **module prelude**. These are compiler-known items whose semantics are baked into the language: operator desugaring, literal typing, `for` loop expansion, `?`/`??` expansion, `@derive`, and string interpolation all depend on them. Requiring explicit imports for items the compiler already knows about would add ceremony without information.

The prelude is fixed. It cannot be extended by users or libraries. Only compiler-known items are eligible.

#### Keywords and Literals

The following are **language keywords** recognized by the parser, not identifiable names:

- `true`, `false` — the two values of type `Bool`
- `fn`, `let`, `mut`, `type`, `trait`, `impl`, `match`, `if`, `else`, `for`, `in`, `while`, `loop`, `break`, `continue`, `return`, `pub`, `import`, `mod`, `with`, `as`, `test`, `effect`, `handler`, `async`

Keywords cannot be used as identifiers, shadowed, or imported.

#### Prelude Types

All built-in types are in the prelude. They are available in every module without import.

**Primitive types:**

| Name | Description |
|------|-------------|
| `Int` | 64-bit signed integer (the default integer type) |
| `I8`, `I16`, `I32` | Sized signed integers |
| `U8`, `U16`, `U32`, `U64` | Unsigned integers |
| `Float` | 64-bit IEEE 754 floating point |
| `Str` | UTF-8 string, GC-managed |
| `Char` | Unicode scalar value |
| `Bool` | Boolean (`true` / `false`) |
| `()` | Unit type |

**Parameterized collection types:**

| Name | Description |
|------|-------------|
| `List[T]` | Growable ordered sequence. `[T]` is sugar for `List[T]` |
| `Map[K, V]` | Hash map |
| `Set[T]` | Hash set |

**Core ADTs and their constructors:**

| Name | Description |
|------|-------------|
| `Option[T]` | Optional value type |
| `Some(T)` | `Option` variant: value present |
| `None` | `Option` variant: value absent |
| `Result[T, E]` | Success-or-error type |
| `Ok(T)` | `Result` variant: success |
| `Err(E)` | `Result` variant: error |
| `Ordering` | Comparison result type |
| `Less`, `Equal`, `Greater` | `Ordering` variants |

#### Prelude Traits

All compiler-known traits are in the prelude. These traits participate in operator desugaring, `for` loop expansion, `@derive`, string interpolation, and conversion protocols. Requiring imports for them would mean every file using `==`, `<`, `for`, or `"{value}"` needs boilerplate imports.

| Trait | Used by |
|-------|---------|
| `Eq` | `==`, `!=` operators |
| `Ord` | `<`, `>`, `<=`, `>=` operators |
| `Hash` | `Map`, `Set` key requirements |
| `Display` | String interpolation `"{value}"` |
| `Clone` | `@derive(Clone)` |
| `Add`, `Sub`, `Mul`, `Div`, `Rem`, `Neg` | Arithmetic operators (sealed) |
| `From[T]` | Infallible conversion, `Into` auto-derivation |
| `Into[T]` | `.into()` method (auto-derived from `From`) |
| `TryFrom[T]` | Fallible conversion |
| `Closeable` | `with...as` scoped resources |
| `Iterator[T]` | Lazy iteration, adapter methods |
| `IntoIterator[T]` | `for x in expr` desugaring |

#### Test Builtins

Inside `test` blocks, the following functions are auto-available without import:

| Name | Signature |
|------|-----------|
| `assert(cond)` | `fn assert(cond: Bool)` |
| `assert_eq(a, b)` | `fn assert_eq[T: Eq + Display](left: T, right: T)` |
| `assert_ne(a, b)` | `fn assert_ne[T: Eq + Display](left: T, right: T)` |
| `prop_check(f)` | `fn prop_check[...](f: fn(...) -> ())` |

These are compiler intrinsics — not library functions. They capture source locations, generate diffs, and are stripped from release builds. They are scoped to `test` blocks; using them outside a test block is a compile error.

User-defined names shadow test builtins within test blocks (standard scoping rules). The compiler warns when a test builtin is shadowed.

#### What Is NOT in the Prelude

The following compiler-known types are **not** in the prelude — they are used by specific subsystems and should be imported when needed:

- `ConversionError` — used by `TryFrom`. Import from `pact.core` when implementing `TryFrom` manually
- `Range[T]` — used by `..`/`..=` syntax. The compiler creates ranges from range expressions; explicit construction is rare
- `Handler[E]` — used by effect handlers. Import when writing handler functions

This keeps the prelude focused on items that participate in core language semantics (operators, loops, pattern matching, string interpolation) and excludes items used only in specific programming patterns.

#### Shadowing Rules

Prelude names can be shadowed by local bindings, module-level definitions, or explicit imports. Shadowing is allowed but the compiler emits a warning:

```
warning[W1010]: name shadows prelude type
 --> math/vector.pact:3:1
  |
3 | type Ordering { ... }
  |      ^^^^^^^^ shadows prelude type `Ordering`
  |
  = help: consider a different name to avoid confusion
```

Keywords (`true`, `false`, `fn`, etc.) cannot be shadowed — they are reserved by the parser.

### 10.7 Standard Library Resolution

The standard library is a set of packages that ship with the Pact compiler. They are available to every Pact program without explicit declaration in `pact.toml`. The compiler treats them as **implicit dependencies** — they participate in the same resolution algorithm as explicit deps (§10.5), with no special resolution step.

#### Stdlib as Implicit Dependencies

Tier 1 stdlib packages (§8.1, OPEN_QUESTIONS §2.2) are injected into the dependency graph as if the user had declared them in `pact.toml`. They are pinned to the compiler version and cannot be overridden.

Conceptually, the compiler prepends these implicit entries before resolving dependencies:

```toml
# Implicit — injected by compiler, not written by user
[dependencies]
std/core = { builtin = true }       # pact.core types (ConversionError, Range, Handler)
std/collections = { builtin = true } # additional collection utilities
std/io = { builtin = true }         # io.println, io.print, etc.
std/fs = { builtin = true }         # fs.read, fs.write, fs.list_dir
std/toml = { builtin = true }       # TOML parser
std/json = { builtin = true }       # JSON codec — completes Serialize/Deserialize (§10.7.1)
std/semver = { builtin = true }     # version parsing and constraint matching
```

The exact set of Tier 1 packages is determined by the compiler version. `pact --version` reports both: `pact 0.3.0 (stdlib 0.3.0)`.

#### Import Syntax

Stdlib packages live under the `std` namespace, matching the `std/` org on the registry (§8.9.2). Import paths follow the `org/name` → `org.name` mapping established in §8.9.7:

```pact
import std.toml                    // TOML parser
import std.semver                  // version parsing
import std.toml.{toml_parse, toml_get}  // selective import
```

The `std` prefix is mandatory. There are no bare stdlib imports — `import toml` resolves only to local `src/toml.pact`, never to stdlib. This avoids the ambiguity that plagues Python's stdlib (is `json` local or stdlib?) and matches Rust's `std::` convention.

The `pact.*` namespace remains reserved for compiler-internal pseudo-modules (`pact.core`, `pact.ffi`) that are part of the language definition, not distributable packages.

#### Resolution Order

The resolution algorithm from §10.5 is unchanged:

1. Check local `src/` for a matching path
2. Check dependencies declared in `pact.toml` (resolved via `pact.lock`) — **stdlib packages are included here as implicit entries**
3. No match → compile error

Local modules shadow stdlib with warning W1000 (same as any dependency shadowing). Explicit `pact.toml` entries for `std/` packages override the bundled version — this is the escape hatch for pinning a specific stdlib version when needed.

#### Physical Location

Stdlib source ships alongside the compiler binary in `<pactc_dir>/lib/std/`. The compiler discovers this path relative to its own binary — no environment variables, no configuration. This satisfies the existing 5-0 decision: "no env vars, no configurable roots."

```
pact/
  bin/pact              # compiler binary
  lib/std/
    toml.pact           # std.toml module
    semver.pact         # std.semver module
    core.pact           # std.core (ConversionError, Range, Handler)
    ...
```

When the compiler encounters `import std.toml`, it resolves to `<pactc_dir>/lib/std/toml.pact` through the normal dependency resolution path.

#### Tier 2 Packages

Tier 2 "batteries" packages (§8.1) version independently from the compiler. They require explicit declaration in `pact.toml`:

```toml
[dependencies]
std/http = "1.2"        # Tier 2 — explicit version required
std/crypto = "0.5"      # Tier 2 — explicit version required
```

They are imported identically to Tier 1:

```pact
import std.http.{Client, Request}
import std.crypto.{sha256}
```

The distinction between Tier 1 and Tier 2 is purely about distribution and versioning — Tier 1 is implicit and version-locked to the compiler, Tier 2 is explicit and independently versioned. The import syntax is the same for both.

#### 10.7.1 Web-Service Module Tier Classification

The following classification was decided by 5-expert panel vote. The guiding principle: **effect system types are compiler-known regardless of tier** — `Request`, `Response`, `Headers`, `NetError`, `Query[C]`, `JsonValue`, `Serialize`, `Deserialize` all ship with the compiler as part of effect and trait definitions. Stdlib modules provide convenience layers above these primitives.

| Module | Tier | Vote | Rationale |
|--------|------|------|-----------|
| `std.json` | **1** | 5-0 | `JsonValue` and `Serialize`/`Deserialize` traits are compiler-known. The codec functions (`parse`, `stringify`, `decode[T]`, `encode[T]`, `pretty`) complete the semantic loop — `@derive(Serialize)` is useless without `json.stringify()`. Stable spec (RFC 8259), small API, universal need. |
| `std.http` | **2** | 3-2 | Core HTTP types (`Request`, `Response`, `Headers`, `NetError`) are compiler-known via effect definitions (§4.4.1). The `std.http` package provides convenience layers: builder patterns (`.with_header()`, `.with_timeout()`), retry policies, redirect following, connection pooling. These evolve faster than the compiler. |
| `std.http.server` | **2** | 5-0 | Server frameworks (routing, middleware, error handling) are opinionated and evolve rapidly. `Net.Listen` effect provides the primitive; the framework iterates independently. |
| `std.db` | **2** | 5-0 | `Query[C]` is compiler-known for injection safety. DB drivers are backend-specific (Postgres, SQLite, MySQL). Connection pools, transaction wrappers, row mapping version independently per driver. |
| `std.log` | **2** | 4-1 | `io.log()` effect handle is the Tier 1 primitive — the runtime provides a default stderr handler. Structured logging (levels, formatters, sinks, JSON output, trace correlation) is policy above capability. |
| `std.config` | **2** | 5-0 | `std.toml` (T1) + `env.var()` (effect) cover basic config loading. Layered config merging, validation, and multi-source overlay are opinionated framework concerns. |

**Tier 1 implicit deps** (updated):

```toml
# Implicit — injected by compiler, not written by user
std/core = { builtin = true }
std/fs = { builtin = true }
std/toml = { builtin = true }
std/semver = { builtin = true }
std/json = { builtin = true }          # JSON codec — completes Serialize/Deserialize
```

**Tier 2 web-service packages** (require `pact.toml` entry):

```toml
[dependencies]
std/http = "0.1"           # HTTP client convenience + server framework
std/db = "0.1"             # DB driver abstractions
std/log = "0.1"            # Structured logging
std/config = "0.1"         # Layered config loading
```

**Onboarding mitigation:** `pact init --template web` auto-generates a `pact.toml` with all Tier 2 web-service deps pre-declared. The "first 5 minutes" experience is zero-friction for web projects despite Tier 2 classification. Templates bridge the gap between correct layering and practical onboarding.

**Compiler diagnostics:** When an `import std.http` fails due to missing `pact.toml` entry, the compiler suggests the fix:

```
error[E1052]: package not found
 --> app.pact:2:1
  |
2 | import std.http
  |        ^^^^^^^^ package `std/http` is not declared in pact.toml
  |
  = help: add `std/http = "0.1"` to [dependencies] in pact.toml
  = help: or run `pact add std/http`
```

#### Stdlib Errors

| Code | Error | Cause |
|------|-------|-------|
| E1050 | Stdlib not found | Compiler installation is incomplete or corrupted |
| E1051 | Stdlib version mismatch | Lockfile records a different stdlib version than current compiler |

```
error[E1050]: stdlib module not found
 --> app.pact:2:1
  |
2 | import std.toml
  |        ^^^^^^^^ module `std.toml` not found
  |
  = note: expected at /usr/lib/pact/lib/std/toml.pact
  = help: your Pact installation may be incomplete; reinstall with `pact self update`
```

### 10.8 Compilation Model

The Pact compiler uses an **emit-all** compilation model. When a module is imported, all of its items — both `pub` and non-pub — are included in the generated C output. The `pub` keyword controls Pact-level visibility, not C-level inclusion.

#### Why Emit-All

The compiler generates a single `.c` file per program. When module `auth.token` is imported, every function, type, and constant defined in `auth/token.pact` appears in the C output — including private helpers that pub functions call internally. This eliminates the class of linker errors where pub functions reference missing private dependencies.

```pact
// auth/token.pact

fn validate_format(token: Str) -> Bool {
    token.len() > 0 && token.contains(".")
}

pub fn verify(token: Str) -> Result[Claims, AuthError] ! Crypto {
    if !validate_format(token) {
        return Err(AuthError { message: "invalid token format" })
    }
    // ... verification logic
}
```

When another module writes `import auth.token.{verify}`, both `verify` and `validate_format` appear in the C output. The importer can call `verify` but **cannot** call `validate_format` — the compiler rejects it:

```
error[E1010]: item `validate_format` is private to module `auth.token`
 --> app.pact:5:12
  |
5 |     let ok = validate_format(raw)
  |              ^^^^^^^^^^^^^^^^ not accessible from this module
  |
  = note: `validate_format` is defined in `auth.token` but not marked `pub`
  = help: if this item should be accessible, add `pub` to its declaration
```

#### Visibility Enforcement

Visibility is enforced at **compile time** by the name resolution pass, not at the C level:

1. **Name resolution** builds a symbol table of all items and their declaring modules
2. When a function call or type reference crosses a module boundary, the resolver checks `pub` status
3. Non-pub items from other modules produce error E1010
4. Items within the same module can access all sibling items regardless of `pub`

This means `pub` is a **hard guarantee**, not advisory. Code that compiles respects all module boundaries. The emit-all model is an implementation detail of the C backend, not a visibility loophole.

#### Symbol Naming

All symbols in generated C use **module-qualified names** to prevent collisions and aid debugging:

```c
// Generated from auth/token.pact
int pact_auth_token_validate_format(pact_string* token) { ... }
pact_result pact_auth_token_verify(pact_string* token) { ... }

// Generated from auth/session.pact
pact_session* pact_auth_session_create(pact_claims* claims) { ... }
```

The naming scheme is `pact_<module_path>_<item_name>`, where module path separators (`.`) become underscores. This applies to **all** items — pub and private alike. Benefits:

- **No collisions**: Two modules defining private `helper()` produce distinct C symbols
- **Debuggable**: gdb/lldb backtraces show which module a function belongs to
- **Separate-compilation ready**: Symbols are already globally unique when the compiler eventually moves to one `.c` per module

#### Relationship to Separate Compilation

Emit-all is the v1 compilation model. The intended v2 optimization is **separate compilation**: each module emits its own `.c` file, compiled to `.o`, then linked. The design choices made here — enforced `pub`, module-qualified symbols — ensure that the migration path from emit-all to separate compilation requires no language-level changes. User code written against v1 will compile identically under v2's separate compilation.

| Property | v1 (emit-all) | v2 (separate compilation) |
|----------|---------------|--------------------------|
| C files per program | 1 | 1 per module |
| Dead code | Included (gcc may optimize) | Excluded by linker |
| Incremental rebuild | Full recompile | Per-module |
| `pub` enforcement | Name resolution | Name resolution + linker |
| Symbol naming | Module-qualified | Module-qualified (unchanged) |

#### Compilation Model Errors

| Code | Error | Cause |
|------|-------|-------|
| E1010 | Private item access | Referencing a non-pub item from outside its declaring module |
| E1011 | Ambiguous import | Two imported modules export the same pub name (use selective import to disambiguate) |

---

## 11. Metadata & Annotations

Annotations use the `@` prefix and are compiler-checked. They are not comments, not decorators, not optional. They participate in type checking, verification, optimization, and tooling.

### 11.1 Complete Annotation Reference

| Annotation | Target | Purpose | Checked by |
|------------|--------|---------|------------|
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
| `@derive(Trait, ...)` | type | Auto-generate trait implementations. Compiler-known traits only in v1: `Eq`, `Ord`, `Hash`, `Debug`, `Clone`, `Display`, `Serialize`, `Deserialize`. | Compile-time codegen |
| `@deprecated(since, removal, replacement, fix)` | fn, type | Edition-aware deprecation with structured migration. Fields: `since` (edition, required), `removal` (edition, optional), `replacement` (qualified name, optional), `fix` (`"replace"`/`"inline"`/`"manual"`, optional). Emits W2000 when current edition < `removal`, E2001 when current edition >= `removal`. Machine-applicable fixes in structured diagnostics when `fix` is `"replace"` or `"inline"`. See §8.15.2. | Compiler warning/error (edition-gated) |

#### Canonical Ordering

`pact fmt` enforces a deterministic annotation order. No style debates.

```pact
@mod("auth")                          // 1. module declaration
@capabilities(DB, Crypto)             // 2. capability budget
@src(req: "AUTH-001")                 // 3. provenance

@src(req: "AUTH-001")                 // 4. provenance (on function)
@requires(email.len() > 0)           // 5. preconditions
@ensures(result.is_ok() => result.unwrap().token.is_valid())  // 6. postconditions
@perf(p99 < 200ms)                   // 7. performance contracts
@deprecated(since: "2026", removal: "2028", replacement: "login_v2", fix: "replace")  // 8. deprecation
pub fn login(email: Str, pwd: Str) -> Result[Session, AuthError] ! DB, Crypto {
    // ...
}
```

The ordering: `@mod` > `@capabilities` > `@derive` > `@src` > `@requires` > `@ensures` > `@where` > `@invariant` > `@perf` > `@ffi` > `@trusted` > `@effects` > `@alt` > `@verify` > `@deprecated`.

Rationale: metadata about the container (module, capabilities) comes first. Then provenance (why does this exist?). Then contracts (what must be true?). Then operational concerns (performance, FFI). Then lifecycle (alternatives, deprecation).

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
