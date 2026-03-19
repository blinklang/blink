# Pact Language Reference

> Pact is a statically-typed, effect-tracked language compiling to C. **Compiler v0.22.0**.

## What's New (v0.22)

| Change | Details |
|--------|---------|
| `TcpSocket` / `TcpListener` types | Typed wrappers for TCP file descriptors. `TcpSocket` has `.read()→Str`, `.read_all()→Str`, `.write(data)→Void`, `.close()→Void`, `.set_timeout(ms)→Void`. `TcpListener` has `.close()→Void`. |
| `std.net` TCP stdlib | `tcp_listen(host, port)→Result[TcpListener, NetError]`, `tcp_connect(host, port)→Result[TcpSocket, NetError]`, `listener_accept(listener)→Result[TcpSocket, NetError]` |
| `net.*` namespace methods | `net.listen`, `net.accept`, `net.read`, `net.write`, `net.close`, `net.connect`, `net.set_timeout`, `net.read_all` — low-level TCP via namespace dispatch |
| `NetError` enum | `Timeout`, `ConnectionRefused`, `DnsFailure`, `TlsError`, `InvalidUrl`, `BindError`, `ProtocolError` |
| Codegen fixes | Result/Option type mismatches for enums/generics, nested compound type codegen, recursive enum list codegen, trait dispatch |
| Typecheck/parser fixes | String method typechecking, stale codegen state, @module annotations, LSP parser AST reset, daemon parser reset, async spawn |

### Prior: What's New (v0.21)

| Change | Details |
|--------|---------|
| `Set[T]` builtin type | Generic hash set: `Set()` constructor, `.insert(elem)→Bool`, `.remove(elem)→Bool`, `.contains(elem)→Bool`, `.len()→Int`, `.is_empty()→Bool`, `.union(other)→Set[T]` |
| LSP completion | Dot-triggered symbol + keyword completion with type info, capped at 100 items |
| LSP documentSymbol | File symbol listing with name, kind, signature, range info |
| LSP signatureHelp | Function signature on `(` and `,` with parameter info and active param highlighting |
| LSP rename | Cross-file symbol rename via workspace edits |
| LSP codeAction | Quickfix actions generated from diagnostic registry |
| Diagnostic path fix | Stdlib paths in diagnostics normalized to strip `build/` prefix |

### Prior: Breaking Changes (v0.20)

| Change | Before | After |
|--------|--------|-------|
| `path_param()` removed | `path_param(name)` (global state) | `req_path_param(req, name)` on Request object (per-request) |

| Change | Details |
|--------|---------|
| Trait declarations | Builtin traits for core types in `lib/std/traits.pact`: Sized, Contains[T], StrOps, ListOps[T], MapOps[K,V], SetOps[T], BytesOps, StringBuildOps, Joinable |
| Trait-based method dispatch | Builtin type methods routed through trait impl registry instead of hardcoded type checks |
| Trait impl validation | Compiler rejects `impl` blocks for undefined traits (E0904), validates method signatures match trait contracts at compile time |
| Concurrent HTTP server | `server_serve_async()` with threadpool handling, per-request path params via `req_path_param()` |
| HTTP backpressure | `server_max_connections(srv, max)` limits concurrent in-flight connections via semaphore pattern |
| Route matching perf | HTTP route patterns pre-split at registration time instead of per-request |
| Struct return in closures | Struct return from if/else expressions inside closures now generates correct C code |
| Map type in closures | Map types no longer lost when captured by closures |
| List[EnumType] codegen | `List[EnumType]` from function returns now generates correct C type (was `int64_t`) |
| Channel codegen gaps | Fixed Channel-related codegen issues |
| 4 codegen/typechecker fixes | Additional codegen and typechecker bug fixes |

### Prior: What's New (v0.19)

| Change | Details |
|--------|---------|
| List HOFs stdlib | `list_map`, `list_filter`, `list_fold`, `list_any`, `list_all`, `list_for_each`, `list_concat`, `list_slice` — generic higher-order functions via `@module("")` prelude |
| Map HOFs stdlib | `map_for_each`, `map_filter`, `map_fold`, `map_map_values`, `map_merge` — generic higher-order functions for maps |
| String ops → Pact stdlib | `str_split`, `str_join`, `str_replace`, `str_lines`, `str_trim`, `str_to_upper`, `str_to_lower` migrated from C runtime to Pact |
| HTTP client → Pact stdlib | `http_do_request`, `get`, `post`, `put`, `delete`, `head`, `parse_url`, `parse_response` migrated from C runtime to Pact |
| Generic monomorphization fix | Generic functions returning `Option[T]` or `Result[T,E]` now produce correct C types (was emitting `void`) |
| Match expression type inference | `match opt { Some(x) => x, None => default }` now correctly types the result variable for non-Int inner types |
| Diagnostic file attribution | Warnings in `@module("")` stdlib modules now report the correct source file instead of the main compilation unit |
| Data enums in List | `List.push()`, `.get()`, and `match` now work with data enum elements |
| LSP textDocument/references | Find all usages of a symbol across files |
| Test compilation ~3x faster | Parallel test compilation on multi-core machines |
| Package system v1 | Git + path dependencies verified end-to-end with lockfile |
| Pub visibility in generics | Visibility now enforced for types inside generic type parameters and trait annotations |

### Prior: What's New (v0.18)

| Change | Details |
|--------|---------|
| LSP support | textDocument/diagnostics, go-to-definition, hover (type signatures + docs), incremental compilation on didSave |
| `--trace` execution tracing | Structured NDJSON to stderr: enter/exit, effect invocations (IO, FS, DB), state mutations. Filters: `fn:`, `module:`, `depth:`, `effect:`, `state:`, `event:`. `--trace-limit N`. `PACT_TRACE` env var. |
| `json_encode_pretty()` | Pretty-printed JSON with 2-space indent. `json_encode_indent(idx, n)` for custom width. Shared `json_serialize_leaf()` helper. |
| `process_run_with_stdin` | New builtin: pipe input to child processes |
| SIGINT forwarding | `process_run` now forwards SIGINT to child processes |
| `??` type inference fix | `??` operator now correctly infers `T` instead of `Option[T]` for variable bindings |
| Void match arm fix | Void function calls in match arms no longer silently dropped |
| JSON unicode escapes | `\uXXXX` unicode escapes and runtime UTF-8 encoding in JSON parser |
| Iterator type safety | Iterator adapter `next()` functions take `void*` for type-safe casts |

### Prior: What's New (v0.17)

| Change | Details |
|--------|---------|
| Stdlib migrations | Duration/Instant, StringBuilder, string functions, Bytes migrated from C runtime to Pact stdlib |
| I/O primitives | `io.read_line()`, `io.read_bytes(n)`, `io.write(s)`, `io.write_bytes(b)` — stdin/stdout binary and line-oriented I/O |
| StringBuilder extras | `.write_int(n)`, `.write_float(f)`, `.write_bool(b)`, `StringBuilder.with_capacity(n)` |

### Prior: What's New (v0.16.1)

| Change | Details |
|--------|---------|
| Git dep resolution fix | Git dependency imports resolved to wrong cache subdirectory — now uses correct commit-specific path |

### Prior: Breaking Changes (v0.16)

| Change | Before | After |
|--------|--------|-------|
| pub visibility enforcement | Non-pub enums/traits/types/let/const accessible across modules | Must be `pub` to use cross-module — compiler now errors on non-pub access |
| `--trace` renamed | `--trace` | `--pact-trace` (avoids conflicts with user flags) |
| Path utils → stdlib | `path_join(a, b)` (builtin) | `import std.path` then `path_join(a, b)` |

| Change | Details |
|--------|---------|
| StringBuilder type | Compiler-intrinsic: `StringBuilder.new()`, `.write()`, `.write_char()`, `.to_str()`, `.len()`, `.capacity()`, `.clear()`, `.is_empty()` |
| `std.path` module | `path_join(a, b)`, `path_dirname(path)`, `path_basename(path)` — moved from C builtins to Pact stdlib |
| `--dump-ast` flag | Dump parsed AST for debugging: `build/pactc --dump-ast file.pact` |
| Auto-resolve deps | `pact build/run/test/check` auto-resolves dependencies before compilation |
| Self-bootstrap | Compiler bootstraps from PATH `pact`; checked-in C bootstrap files removed |
| Quiet test output | `pact test` quiet by default; `--verbose` for detail |
| O(N²) concat → StringBuilder | Lexer/formatter performance: StringBuilder replaces repeated string concat |
| Bugfixes | Lockfile not loaded on second build (src/ root), 3,718 compiler warnings eliminated, CT_TAGGED_ENUM leak as Void, nested list type lost in type pool |

### Prior: What's New (v0.15)

| Change | Details |
|--------|---------|
| FFI system | `@ffi("lib", "symbol")` annotation for C interop, `@trusted` audit marker, `Ptr[T]` type with methods (deref, addr, write, is_null, to_str, as_cstr), `ffi.scope()` resource management |
| Keyword arguments | Named args in calls: `greet(name: "Alice", greeting: "Hi")` |
| `@allow` diagnostic suppression | Suppress specific warnings: `@allow(W0600)` on functions or types |
| `@invariant` struct assertions | Struct-level invariants: `@invariant(self.balance >= 0)` checked at construction |
| Vendored C cross-compilation | Compile vendored C source files with cross-compile support; SQLite3 amalgamation bundled |
| `pact audit` command | FFI audit: inventory `@ffi` calls, audit status, pointer operations |
| Native dependencies | `pact.toml [native-dependencies]` section for linking C libraries |
| Bugfixes | `\r` escape bootstrap, comment preservation in type/trait/impl bodies, UnaryOp type inference, TokenKind annotations |

### Prior: What's New (v0.14)

| Change | Details |
|--------|---------|
| Unused variable warnings | Compiler emits W0600 for `let` bindings that are never read; prefix with `_` to suppress |
| Cross-compilation fix | Removed spurious libcurl link dependency that caused linker failures on non-host targets |

### Prior: What's New (v0.13.3)

| Change | Details |
|--------|---------|
| `List[List[T]]` function parameter fix | Nested list parameters now propagate inner element types correctly — `.get()` on inner list no longer produces `pact_Option_int` |

### Prior: What's New (v0.13.2)

| Change | Details |
|--------|---------|
| Nested struct type propagation | `List[List[Struct]]` and `Option[List[Struct]]` now correctly propagate inner struct types through `for` loops, `let` bindings, `??`, `.unwrap()`, and `match Some(x)` |

### Prior: What's New (v0.13.1)

| Change | Details |
|--------|---------|
| `List[List[T]]` codegen fix | `.get()`, `.pop()`, `.unwrap()`, and `??` on nested lists now produce correct C types (`pact_Option_list` instead of `pact_Option_int`). Also fixes `db.query_one()` return type. |
| Extended string lexer fix | `"#{"` no longer misparsed as extended string end delimiter |

### Prior: What's New (v0.13)

| Change | Details |
|--------|---------|
| SQLite `db.*` namespace | 16 methods for database operations — `db.open`, `db.exec`, `db.query`, `db.execute`, `db.query_one`, `db.prepare`/`bind`/`step`/`column`/`finalize`, `db.begin`/`commit`/`rollback`, `db.close`, `db.errmsg` |
| `pact.toml` versioning | `pact init` stamps `pact-version` in project manifest for toolchain compatibility |
| `\r` escape sequence | Carriage return (`\r`) now supported in string literals |

### Prior: What's New (v0.12)

| Change | Details |
|--------|---------|
| Tuple destructuring | `let (a, b) = some_tuple` — destructure tuples in let bindings |
| Extended strings | `#"literal "quotes" and \backslashes"#` — no escaping needed, `#{expr}` for interpolation |
| Struct field defaults | `type Point { x: Int = 0, y: Int = 0 }` — omit fields with defaults at construction |
| `@requires` contracts | Precondition annotations: `@requires(amount > 0)` checked at call sites |
| Nested generics | `List[List[Int]]` and other parameterized inner types now work correctly |
| `--release` flag | Optimized builds with `-O2`: `bin/pact build src/main.pact --release` |
| Multi-target builds | Cross-compile: `bin/pact build -T linux -T macos-arm64` |
| Error catalog | `pact explain E1234` with machine-applicable fix suggestions |
| List[T] param fix | Struct element types preserved through function parameters (`.get().unwrap()` on `List[Struct]` params) |
| `mod {}` parser error | Helpful E1015 error for inline module blocks instead of generic parse failure |

### Prior: What's New (v0.11.1)

| Change | Details |
|--------|---------|
| Cross-module error locations | Diagnostics in imported modules now report the correct source file instead of always showing the main file |

### Prior: What's New (v0.11)

| Change | Details |
|--------|---------|
| `pact doc --list` | List available stdlib modules for discoverability |
| Type error locations | Type errors now report source file + line number |
| `set_version(p, ver)` | Set version string on ArgParser — shows in `--version` output and help text |
| `args_get_all(a, name)` | Get all values for a repeated option (returns `List[Str]`) |
| `parse_argv(p, argv)` | Parse an explicit `List[Str]` argv instead of reading process args |
| `add_command_alias(p, alias, target)` | Register command aliases in CLI argument parser |
| Better CLI error messages | Bare-word errors in argument parsing now produce clearer diagnostics |

### Prior: What's New (v0.10)

| Change | Details |
|--------|---------|
| `pact doc <module>` | Print module documentation — types, functions, traits with full signatures and `///` doc comments. `--json` flag for machine-readable output. Works with embedded stdlib: `pact doc std.args` |
| Embedded stdlib | Stdlib source files compiled into CLI binary via `#embed`. No source files needed on disk for `pact doc` or future tooling |
| Stdlib doc comments | `///` doc comments with usage examples added to std.args, std.json, std.toml, std.semver, std.http_* modules |

### Prior: What's New (v0.9)

| Change | Details |
|--------|---------|
| List pattern matching | `match list { [] => ..., [a, b] => ..., [first, ...] => ... }` — match lists by length + element values in `match` expressions. Rest wildcard `...` matches zero or more trailing elements (tail only, no binding). Wildcard `_` or `...` arm required for exhaustiveness. |
| Nested subcommands (`std.args`) | Dotted paths: `add_command(p, "daemon.start", "...")`. `args_command()` returns space-joined `"daemon start"`. New `args_command_path()` returns `List[Str]`. `command_add_positional()` and `generate_command_help()` added. |
| Parallel test execution | `pact test --parallel` / `-P` runs tests in parallel (default 4 workers) |
| `pact init` idempotent | `pact init` now safe to re-run on existing projects |

### Prior: Breaking Changes (v0.8)

| Change | Before | After |
|--------|--------|-------|
| `str_from_char_code()` removed | `str_from_char_code(65)` | `Char.from_code_point(65)` — static method, returns `Str` |
| `\b`/`\f` escape sequences | Not supported | `\b` (backspace), `\f` (form feed) now valid in strings |
| CLI flag scoping | Flags global | Flags scoped to subcommands (`build --emit`, `run --`, etc.) |

### Prior: What's New (v0.7)

| Change | Details |
|--------|---------|
| `process_exec(cmd, args)` builtin | Exec a binary directly (replaces current process) |
| `args_rest(a)` stdlib function | Returns `List[Str]` of arguments after `--` from argparser |
| 5 codegen/lexer bugfixes | C reserved word escaping, closure captures, match codegen, chained methods, iterator type detection |

### Prior: Breaking Changes (v0.6)

| Change | Before | After |
|--------|--------|-------|
| `List.get()` returns `Option[T]` | `let x = items.get(0)` | `let x = items.get(0) ?? default` or `match items.get(0) { Some(x) => ... None => ... }` |
| `const` keyword | `let X = 42` at module level | `const X = 42` — compile-time constants use `const`, not `let` |
| `#embed("path")` intrinsic | N/A | `const DATA = #embed("file.txt")` — compile-time file inclusion as `Str` |

**CRITICAL — Read before writing any Pact code:**
- `fn` keyword, `{ }` braces, NO semicolons — newlines separate statements
- `"double quotes"` ONLY — no single quotes for strings
- Universal string interpolation: `"Hello, {name}!"` — every string supports `{expr}`
- `io.println(...)` NOT `print(...)` — IO goes through effect handles
- NO `+` on strings — use interpolation `"{a}{b}"` or `.concat()`
- Square bracket generics: `List[T]` NOT `List<T>`
- Method calls always: `x.len()` NOT `x.len` (no properties)
- `main` has implicit effects — no annotation needed on `fn main()`

## FFI (Foreign Function Interface)

Pact can call C functions via the `@ffi` annotation and `Ptr[T]` type.

### @ffi Annotation

```pact
@ffi("sqlite3", "sqlite3_open")
fn sqlite3_open(filename: Ptr[Int], db: Ptr[Ptr[Int]]) -> Int
```

`@ffi("library", "symbol")` — first arg is library name, second is C symbol name.

### @trusted Audit Marker

```pact
@trusted
@ffi("libc", "malloc")
fn malloc(size: Int) -> Ptr[Int]
```

`@trusted` marks FFI functions as audited for safety.

### Ptr[T] Type

| Method | Returns | Purpose |
|--------|---------|---------|
| `.deref()` | T | Dereference pointer |
| `.addr()` | Int | Get raw address |
| `.write(val)` | Void | Write value at pointer |
| `.is_null()` | Bool | Null check |
| `.to_str()` | Str | Convert to string (for char*) |
| `.as_cstr()` | Str | Read as C string |

### ffi.scope() Resource Management

```pact
ffi.scope(fn(scope) {
    let cstr = scope.cstr("hello")     // allocate C string (auto-freed)
    let buf = scope.alloc(1024)        // allocate raw memory (auto-freed)
    let result = scope.take(ptr)       // take ownership of pointer
})
```

`ffi.scope()` provides automatic memory management for FFI operations. All allocations are freed when the scope exits.

### Native Dependencies (pact.toml)

```toml
[native-dependencies]
sqlite3 = { vendored = "vendor/sqlite3.c" }
libcurl = { system = true }
```

### pact audit

```sh
bin/pact audit src/main.pact          # FFI audit report
```

Lists all `@ffi` calls, their audit status (`@trusted` or unaudited), and pointer operations.

## Syntax Quick Reference

```pact
// Variables
let x = 42                       // immutable
let mut count = 0                // mutable
let name: Str = "Alice"          // type annotation
let (a, b) = (10, 20)           // tuple destructuring

// Functions
fn add(a: Int, b: Int) -> Int {
    a + b                        // last expression is return value
}

fn greet(name: Str) ! IO {       // ! declares effects
    io.println("Hello, {name}!")
}

// Keyword arguments
greet(name: "Alice", greeting: "Hi")

// Closures
let double = fn(x: Int) -> Int { x * 2 }
numbers.map(fn(x) { x * 2 })

// Structs
type Point { x: Float, y: Float }
let p = Point { x: 1.0, y: 2.0 }
io.println("x={p.x}")

// Struct field defaults
type Config { host: Str = "localhost", port: Int = 8080 }
let c = Config { host: "0.0.0.0" }  // port gets default 8080

// Enums (ADTs)
type Shape {
    Circle(radius: Float)
    Rect(w: Float, h: Float)
}
let s = Shape.Circle(5.0)

// Pattern matching (expression — returns value)
let area = match s {
    Circle(r) => 3.14 * r * r
    Rect(w, h) => w * h
}

// List patterns in match
match args {
    [] => show_help()
    ["build"] => build()
    ["daemon", sub] => handle_sub(sub)
    [cmd, ...] => io.println("unknown: {cmd}")  // ... = rest wildcard (no binding)
}

// Control flow
if x > 0 { "positive" } else { "non-positive" }  // expression
for item in list { io.println(item) }
while count < 10 { count += 1 }
loop { if done { break } }

// Error handling
fn parse(s: Str) -> Result[Int, Str] {
    if s == "" { Err("empty") } else { Ok(s.to_int()) }
}
let val = parse(input)?           // propagate error (in Result-returning fn)
let val = maybe_val ?? "default"  // unwrap Option with default

// Traits
trait Display {
    fn display(self) -> Str
}
impl Display for Point {
    fn display(self) -> Str { "({self.x}, {self.y})" }
}

// Tests (built-in, no framework needed)
test "addition works" {
    assert_eq(add(2, 3), 5)
}
```

## Types

| Type | Example | Notes |
|------|---------|-------|
| Int | `42`, `-1` | 64-bit signed integer |
| Float | `3.14`, `-0.5` | 64-bit double |
| Str | `"hello"` | Immutable UTF-8 string |
| Bool | `true`, `false` | Boolean |
| List[T] | `[1, 2, 3]` | Dynamic array |
| Map[K, V] | `Map()` | Hash map (construct with `Map()`, not `{}`) |
| Set[T] | `Set()` | Hash set (construct with `Set()`) |
| Option[T] | `Some(v)`, `None` | Nullable value |
| Result[T, E] | `Ok(v)`, `Err(e)` | Error-or-value |
| Bytes | `Bytes.new()` | Byte buffer |
| StringBuilder | `StringBuilder.new()` | Mutable string builder |
| Instant | `time.read()` | Point in time |
| Ptr[T] | `Ptr[Int]` | Raw pointer (FFI) |
| Duration | `Duration.ms(100)` | Time span |

## Escape Sequences

| Escape | Produces |
|--------|----------|
| `\n` | newline |
| `\r` | carriage return |
| `\t` | tab |
| `\\` | literal `\` |
| `\"` | literal `"` |
| `\b` | backspace |
| `\f` | form feed |
| `\{` | literal `{` (suppresses interpolation) |
| `\}` | literal `}` |

### Extended Strings

Extended strings `#"..."#` allow literal `"` and `\` without escaping. Use `#{expr}` for interpolation.

```pact
let raw = #"path\to\file"#              // no escaping needed
let json = #"{"key": "value"}"#         // literal quotes
let msg = #"Hello, #{name}!"#           // interpolation with #{...}
let nested = ##"contains #"inner"#"##   // depth-2 nesting
```

## Operators

| Op | Types | Notes |
|----|-------|-------|
| `+` `-` `*` `/` `%` | Int, Float | Arithmetic (NO `+` on Str) |
| `==` `!=` `<` `>` `<=` `>=` | Int, Float, Str | Comparison |
| `&&` `\|\|` `!` | Bool | Logical |
| `?` | Result[T,E] | Propagate error — enclosing fn must return Result |
| `??` | Option[T] | Unwrap or default |
| `\|>` | Any | Pipe: `x \|> f()` = `f(x)` |
| `+=` `-=` `*=` `/=` | Int, Float | Compound assignment (mut only) |

## Builtin Functions

| Function | Returns | Purpose |
|----------|---------|---------|
| `read_file(path)` | Str | Read file to string |
| `write_file(path, content)` | Void | Write string to file |
| `file_exists(path)` | Int | 1 if exists, 0 if not |
| `is_dir(path)` | Int | 1 if directory |
| `path_join(a, b)` | Str | Join path components — **moved to `std.path`**, use `import std.path` |
| `path_dirname(path)` | Str | Directory part of path — **moved to `std.path`** |
| `path_basename(path)` | Str | Filename part of path — **moved to `std.path`** |
| `file_mtime(path)` | Int | Modification time (ms) |
| `get_env(name)` | Option[Str] | Environment variable |
| `shell_exec(cmd)` | Int | Run shell command, return exit code |
| `process_run(cmd, args)` | ProcessResult | Run command with args (`List[Str]`), capture stdout/stderr/exit_code |
| `process_run_with_stdin(cmd, args, input)` | ProcessResult | Like `process_run` but pipes `input` (Str) to child's stdin |
| `process_exec(cmd, args)` | Void | Exec binary directly (replaces process). `args` is `List[Str]` |
| `exit(code)` | Void | Exit with code |
| `arg_count()` | Int | CLI argument count |
| `get_arg(idx)` | Str | CLI argument by index |
| `time_ms()` | Int | Current time in milliseconds |
| `getpid()` | Int | Process ID |
| `Char.from_code_point(n)` | Str | Convert char code to 1-char string (was `str_from_char_code`) |
| `unix_socket_listen(path)` | Int | Listen on Unix domain socket |
| `unix_socket_connect(path)` | Int | Connect to Unix domain socket |
| `unix_socket_accept(fd)` | Int | Accept incoming connection |
| `unix_socket_accept_timeout(fd, ms)` | Int | Accept with timeout (ms) |
| `unix_socket_close(fd)` | Void | Close socket |
| `socket_read_line(fd)` | Str | Read line from socket |
| `socket_write(fd, data)` | Void | Write data to socket |
| `ffi_scope(fn)` | Void | FFI resource scope — auto-frees allocations on exit |
| `tcp_listen(host, port)` | Int | Listen on TCP socket |
| `tcp_connect(host, port)` | Int | Connect to TCP host:port |
| `tcp_accept(fd)` | Int | Accept incoming TCP connection |
| `tcp_read(fd, max_bytes)` | Str | Read up to max_bytes from TCP socket |
| `tcp_read_all(fd)` | Str | Read all available data from TCP socket |
| `tcp_write(fd, data)` | Void | Write data to TCP socket |
| `tcp_close(fd)` | Void | Close TCP socket |
| `tcp_set_timeout(fd, ms)` | Void | Set read timeout on TCP socket |

## Namespace Methods

```pact
// IO (effect: IO)
io.println("text")              // print + newline to stdout
io.print("text")                // print without newline
io.eprintln("error")            // print to stderr + newline
io.eprint("error")              // print to stderr, no newline
io.log("debug info")            // stderr with [LOG] prefix
io.read_line()                  // -> Str (read line from stdin)
io.read_bytes(n)                // -> Bytes (read n bytes from stdin)
io.write(s)                     // write string to stdout (no newline)
io.write_bytes(b)               // write Bytes to stdout

// Filesystem (effect: FS)
fs.read(path)                   // -> Str
fs.write(path, content)         // -> Void
fs.list_dir(dir)                // -> List[Str] (filenames)

// Environment
env.args()                      // -> List[Str] (all CLI args)

// Time
time.read()                     // -> Instant
time.sleep(duration)            // sleep for Duration

// Async (effect: Async)
async.scope { ... }             // synchronous scope for spawned tasks
async.spawn(fn() { ... })       // spawn task, returns Handle

// Database (effect: DB) — requires SQLite
db.open(path)                   // open SQLite database, sets implicit connection
db.exec(sql)                    // execute SQL (no results), e.g. CREATE TABLE
db.execute(sql)                 // execute SQL, returns last insert rowid (Int)
db.query(sql)                   // -> List[List[Str]] (all rows, all columns as strings)
db.query_one(sql)               // -> Option[List[Str]] (first row or None)
db.prepare(sql)                 // -> Int (statement handle)
db.bind_int(stmt, idx, val)     // bind Int to parameter index
db.bind_text(stmt, idx, val)    // bind Str to parameter index
db.bind_real(stmt, idx, val)    // bind Float to parameter index
db.step(stmt)                   // -> Int (SQLITE_ROW=100, SQLITE_DONE=101)
db.column_text(stmt, idx)       // -> Str (column value as string)
db.column_int(stmt, idx)        // -> Int (column value as integer)
db.reset(stmt)                  // reset prepared statement for re-use
db.finalize(stmt)               // free prepared statement
db.begin()                      // BEGIN TRANSACTION
db.commit()                     // COMMIT
db.rollback()                   // ROLLBACK
db.errmsg()                     // -> Str (last error message)
db.close()                      // close database connection

// Net (effect: Net.Listen for listen/accept, Net.Connect for connect)
net.listen(host, port)          // -> Int (listen fd)
net.accept(fd)                  // -> Int (connection fd)
net.read(fd, max_bytes)         // -> Str (read up to max_bytes)
net.read_all(fd)                // -> Str (read all available data)
net.write(fd, data)             // -> Void
net.close(fd)                   // -> Void
net.connect(host, port)         // -> Int (connection fd)
net.set_timeout(fd, ms)         // -> Void (set read timeout)
```

## String Methods

| Method | Returns | Purpose |
|--------|---------|---------|
| `.len()` | Int | Length in bytes |
| `.is_empty()` | Bool | Check if empty |
| `.contains(s)` | Bool | Substring check |
| `.starts_with(s)` | Bool | Prefix check |
| `.ends_with(s)` | Bool | Suffix check |
| `.index_of(s)` | Int | Find index (-1 if not found) |
| `.concat(s)` | Str | Concatenate |
| `.substring(start, len)` | Str | Extract by position + length |
| `.slice(start, end)` | Str | Extract by range |
| `.split(sep)` | List[Str] | Split by separator |
| `.lines()` | List[Str] | Split by newlines |
| `.trim()` | Str | Strip whitespace |
| `.to_upper()` | Str | Uppercase |
| `.to_lower()` | Str | Lowercase |
| `.replace(old, new)` | Str | Replace all occurrences |
| `.to_int()` | Int | Parse as integer |
| `.parse_float()` | Float | Parse as float |
| `.char_at(idx)` | Int | Char code at index |

## List[T] Methods

| Method | Returns | Purpose |
|--------|---------|---------|
| `.len()` | Int | Length |
| `.is_empty()` | Bool | Check if empty |
| `.push(item)` | Void | Append (mutates) |
| `.pop()` | Option[T] | Remove last |
| `.get(idx)` | Option[T] | Element at index (None if OOB) |
| `.set(idx, val)` | Void | Set element (mutates) |
| `.concat(other)` | List[T] | Concatenate lists |
| `.slice(start, end)` | List[T] | Sub-list |
| `.join(sep)` | Str | Join as string (List[Str]) |
| `.map(fn(T)->U)` | List[U] | Transform each |
| `.filter(fn(T)->Bool)` | List[T] | Keep matching |
| `.fold(init, fn(A,T)->A)` | A | Reduce |
| `.find(fn(T)->Bool)` | Option[T] | First match |
| `.any(fn(T)->Bool)` | Bool | Any match? |
| `.all(fn(T)->Bool)` | Bool | All match? |
| `.count()` | Int | Count elements (drives iterator) |
| `.for_each(fn(T)->Void)` | Void | Apply to each element |
| `.chain(other)` | Iterator[T] | Concatenate iterators |
| `.flat_map(fn(T)->List[U])` | Iterator[U] | Map + flatten |
| `.zip(other)` | List[List] | Pair elements (eager, returns list-of-pairs) |
| `.enumerate()` | List[List] | With indices (eager, returns list-of-pairs) |
| `.take(n)` | Iterator[T] | First n |
| `.skip(n)` | Iterator[T] | Skip first n |
| `.collect()` | List[T] | Iterator to list |

## Map[K, V] Methods

| Method | Returns | Purpose |
|--------|---------|---------|
| `Map()` | Map[K,V] | Create empty map (NOT `{}`) |
| `.set(key, val)` | Void | Insert/update |
| `.get(key)` | V | Get value (use `.has()` first) |
| `.has(key)` | Bool | Key exists? |
| `.remove(key)` | Bool | Remove key |
| `.len()` | Int | Entry count |
| `.keys()` | List[K] | All keys |
| `.values()` | List[V] | All values |

## Set[T] Methods

| Method | Returns | Purpose |
|--------|---------|---------|
| `Set()` | Set[T] | Create empty set |
| `.insert(elem)` | Bool | Add element to set |
| `.remove(elem)` | Bool | Remove element from set |
| `.contains(elem)` | Bool | Membership check |
| `.len()` | Int | Number of elements |
| `.is_empty()` | Bool | Check if empty |
| `.union(other)` | Set[T] | Union of two sets |

## Bytes Methods

| Method | Returns | Purpose |
|--------|---------|---------|
| `Bytes.new()` / `Bytes()` | Bytes | Create empty byte buffer |
| `Bytes.from_str(s)` | Bytes | Create from string |
| `.push(byte)` | Void | Append byte (mutates) |
| `.get(idx)` | Option[Int] | Byte at index |
| `.set(idx, byte)` | Void | Set byte (mutates) |
| `.len()` | Int | Length |
| `.is_empty()` | Bool | Check if empty |
| `.slice(start, end)` | Bytes | Sub-buffer |
| `.concat(other)` | Bytes | Concatenate |
| `.to_str()` | Result[Str, Str] | Convert to UTF-8 string |
| `.to_hex()` | Str | Hex encoding |

## StringBuilder Methods

| Method | Returns | Purpose |
|--------|---------|---------|
| `StringBuilder.new()` | StringBuilder | Create empty builder |
| `StringBuilder.with_capacity(n)` | StringBuilder | Create with pre-allocated capacity |
| `.write(s)` | Void | Append string |
| `.write_char(ch)` | Void | Append single character |
| `.write_int(n)` | Void | Append integer as string |
| `.write_float(f)` | Void | Append float as string |
| `.write_bool(b)` | Void | Append bool as string |
| `.to_str()` | Str | Build final string |
| `.len()` | Int | Current length |
| `.capacity()` | Int | Allocated capacity |
| `.clear()` | Void | Reset to empty |
| `.is_empty()` | Bool | Check if empty |

## Option[T] Methods

| Method | Returns | Purpose |
|--------|---------|---------|
| `.unwrap()` | T | Extract value (panics on None) |
| `.is_some()` | Bool | Has value? |
| `.is_none()` | Bool | Empty? |

Use `??` operator for safe unwrap with default: `opt_val ?? "default"`

## Result[T, E] Methods

| Method | Returns | Purpose |
|--------|---------|---------|
| `.unwrap()` | T | Extract Ok value (panics on Err) |
| `.unwrap_err()` | E | Extract Err value (panics on Ok) |
| `.is_ok()` | Bool | Success? |
| `.is_err()` | Bool | Failure? |

Use `?` operator to propagate errors: `let val = fallible()?`

## ProcessResult Fields

```pact
let result = process_run("ls", ["-la"])
result.out          // Str — stdout
result.err_out      // Str — stderr
result.exit_code    // Int — exit code
```

## Duration Methods

| Method | Returns | Purpose |
|--------|---------|---------|
| `Duration.nanos(n)` | Duration | From nanoseconds |
| `Duration.ms(n)` | Duration | From milliseconds |
| `Duration.seconds(n)` | Duration | From seconds |
| `Duration.minutes(n)` | Duration | From minutes |
| `Duration.hours(n)` | Duration | From hours |
| `.to_nanos()` | Int | As nanoseconds |
| `.to_ms()` | Int | As milliseconds |
| `.to_seconds()` | Int | As seconds |
| `.add(other)` | Duration | Add durations |
| `.sub(other)` | Duration | Subtract durations |
| `.scale(n)` | Duration | Multiply by integer |
| `.is_zero()` | Bool | Zero duration? |

## Instant Methods

| Method | Returns | Purpose |
|--------|---------|---------|
| `time.read()` | Instant | Current time |
| `Instant.from_epoch_secs(n)` | Instant | From unix timestamp |
| `.elapsed()` | Duration | Time since this instant |
| `.since(other)` | Duration | Difference between instants |
| `.add(dur)` | Instant | Add duration |
| `.to_unix_ms()` | Int | As unix milliseconds |
| `.to_unix_secs()` | Int | As unix seconds |
| `.to_rfc3339()` | Str | ISO-8601 formatted string |

```pact
let start = time.read()
// ... work ...
let elapsed = start.elapsed()
io.println("Took {elapsed.to_ms()} ms")

let d = Duration.seconds(5)
time.sleep(d)
```

## JSON (with @derive)

```pact
@derive(Serialize, Deserialize)
type Task { id: Int, title: Str, done: Bool }

let task = Task { id: 1, title: "Test", done: false }
let json = task.to_json()                    // -> Str
let back = Task.from_json(json)              // -> Result[Task, Str]
```

Low-level JSON API (`import std.json`):

| Function | Returns | Purpose |
|----------|---------|---------|
| `json_parse(input)` | Int | Parse JSON string, returns root node index (-1 on error) |
| `json_encode(idx)` | Str | Serialize node tree to compact JSON |
| `json_encode_pretty(idx)` | Str | Serialize to pretty-printed JSON (2-space indent) |
| `json_encode_indent(idx, n)` | Str | Serialize to pretty-printed JSON (custom indent width) |
| `json_type(idx)` | Int | Node type (JSON_NULL/BOOL/INT/FLOAT/STRING/ARRAY/OBJECT) |
| `json_get(idx, key)` | Int | Get child by key from object (-1 if missing) |
| `json_at(idx, i)` | Int | Get child by index from array |
| `json_len(idx)` | Int | Child count of array/object |
| `json_as_str(idx)` | Str | Extract string value |
| `json_as_int(idx)` | Int | Extract integer value |
| `json_new_object()` | Int | Create empty object node |
| `json_new_array()` | Int | Create empty array node |
| `json_new_str(s)` | Int | Create string node |
| `json_new_int(n)` | Int | Create integer node |
| `json_set(obj, key, val)` | Void | Set key-value on object (add or replace) |
| `json_push(arr, val)` | Void | Append value to array |
| `json_remove(obj, key)` | Void | Remove key from object |
| `json_clear()` | Void | Reset all JSON state for next parse |

## CLI Argument Parsing (std.args)

```pact
import std.args

fn main() {
    let mut p = argparser_new("myapp", "Description")
    p = set_version(p, "1.0.0")                          // shows in --version and help
    p = add_command(p, "run", "Run the app")
    p = add_command(p, "daemon.start", "Start daemon")   // nested subcommand
    p = add_command(p, "daemon.stop", "Stop daemon")
    p = add_command_alias(p, "d", "daemon")              // "d start" = "daemon start"
    p = add_flag(p, "--verbose", "-v", "Verbose output")
    p = command_add_flag(p, "run", "--watch", "-w", "Watch mode")  // command-scoped flag
    p = add_option(p, "--output", "-o", "Output file")
    p = add_positional(p, "file", "Input file")
    p = command_add_positional(p, "daemon.start", "target", "File to watch")

    let a = argparse(p)                  // parse process args
    // let a = parse_argv(p, my_argv)    // or parse explicit List[Str]
    let cmd = args_command(a)            // "daemon start" (space-joined)
    let path = args_command_path(a)      // ["daemon", "start"] (List[Str])
    let verbose = args_has(a, "verbose")
    let output = args_get(a, "output")
    let all_outputs = args_get_all(a, "output")  // all values for repeated option
    let file = args_positional(a, 0)
    let rest = args_rest(a)              // args after "--"
}
```

## Imports & Modules

```pact
import lexer                     // import module
import std.args                  // import stdlib module
```

Files are modules. `pub` marks items visible to importers. `import` brings `pub` items into scope.

## Annotations (ordered)

| Annotation | Target | Purpose |
|------------|--------|---------|
| `@module(name)` | module | Module declaration |
| `@capabilities(...)` | module | Effect ceiling |
| `@derive(...)` | type | Auto-generate traits (Serialize, Deserialize, Eq, Ord, Hash, Debug, Clone, Display) |
| `@src(req)` | fn | Requirement traceability |
| `@requires(expr)` | fn | Precondition |
| `@ensures(expr)` | fn | Postcondition (`result` = return value) |
| `@where(expr)` | fn, type | Type constraint |
| `@invariant(expr)` | type | Type invariant |
| `@ffi("lib", "sym")` | fn | FFI binding — link to C function |
| `@trusted` | fn | FFI audit marker — function reviewed for safety |
| `@allow(W0600)` | fn, type | Suppress specific diagnostic warning |
| `@deprecated(msg)` | fn, type | Deprecation warning. Optional: `since`, `removal`, `replacement`, `fix` fields |

## Common Patterns

```pact
// Read + process file
let content = read_file("data.txt")
let lines = content.split("\n")
for line in lines {
    if line.contains("TODO") {
        io.println("Found: {line}")
    }
}

// Error handling chain
fn load_config(path: Str) -> Result[Config, Str] {
    if file_exists(path) == 0 {
        return Err("config not found")
    }
    let json = read_file(path)
    Config.from_json(json)
}
let config = load_config("config.json")?

// Build output with list
let mut parts: List[Str] = []
parts.push("header")
parts.push("body")
let output = parts.join("\n")
write_file("out.txt", output)

// Map usage
let mut scores: Map[Str, Int] = Map()
scores.set("alice", 95)
if scores.has("alice") {
    io.println("Score: {scores.get("alice")}")
}

// Process execution
let result = process_run("git", ["rev-parse", "HEAD"])
if result.exit_code == 0 {
    io.println("Commit: {result.out.trim()}")
}
```

## Standard Library

| Module | Description | Example |
|--------|-------------|---------|
| `std.args` | CLI argument parsing (flags, options, commands) | `import std.args` |
| `std.http` | HTTP client and server | `import std.http` |
| `std.json` | JSON parser and serializer | `import std.json` |
| `std.net` | TCP networking: `TcpSocket`, `TcpListener`, `NetError`, `tcp_listen`, `tcp_connect`, `tcp_accept` | `import std.net` |
| `std.path` | Path utilities: `path_join(a, b)`, `path_dirname(path)`, `path_basename(path)` | `import std.path` |
| `std.semver` | Semantic version parsing and constraints | `import std.semver` |
| `std.toml` | TOML parser | `import std.toml` |

### Prelude Modules (auto-imported, no `import` needed)

| Module | Functions |
|--------|-----------|
| `std.str` | `str_split`, `str_join`, `str_replace`, `str_lines`, `str_trim`, `str_to_upper`, `str_to_lower`, `json_escape_str` |
| `std.list` | `list_map[T,U]`, `list_filter[T]`, `list_fold[T,U]`, `list_any[T]`, `list_all[T]`, `list_for_each[T]`, `list_concat[T]`, `list_slice[T]` |
| `std.map` | `map_for_each[V]`, `map_filter[V]`, `map_fold[V,U]`, `map_map_values[V,U]`, `map_merge[V]` |
| `std.num` | `parse_int`, `parse_float`, `int_to_str`, `float_to_str` |
| `std.sb` | StringBuilder extensions |
| `std.bytes` | Bytes type operations |
| `std.time` | Duration/Instant constructors and methods |

Run `pact doc <module>` for full documentation (e.g. `pact doc std.args`).
Run `pact doc --list` to list available modules.

## Gotchas

- `{}` is NOT an empty map — use `Map()`. `{}` in expression position is a compile error. Similarly, use `Set()` for empty sets.
- `file_exists()` returns `Int` (0/1), not `Bool` — use `== 1` or `== 0`
- `is_dir()` also returns `Int`, not `Bool`
- `shell_exec()` returns exit code (Int), not stdout — use `process_run()` for output capture
- No `return` needed for last expression in function body
- `match` must be exhaustive — cover all variants or use `_ =>` wildcard
- List patterns in `match` ALWAYS need a wildcard `_` or rest `...` arm — finite patterns can't cover unbounded lists
- `let mut` required for any variable you want to reassign
- Function args separated by commas in calls, but by newlines in multi-line definitions
- `assert`, `assert_eq`, `assert_ne` only available inside `test` blocks and debug mode

## Build & Run

```sh
bin/pact build src/main.pact     # compile to build/main
bin/pact run src/main.pact       # compile + run
bin/pact test                    # discover + run all test blocks
bin/pact check src/main.pact     # typecheck without compiling
bin/pact fmt src/main.pact       # format in place
bin/pact doc --list              # list available stdlib modules
bin/pact doc std.args            # print module documentation
bin/pact doc std.json --json     # module docs as JSON
bin/pact audit src/main.pact     # FFI audit report
bin/pact update                  # update deps + pact-version in pact.toml

# Release builds (optimized with -O2)
bin/pact build src/main.pact --release
bin/pact build src/main.pact -R

# Cross-compilation (single target)
bin/pact build src/main.pact --target linux
bin/pact build src/main.pact -T macos-arm64

# Multi-target builds (compile to C once, link per target)
bin/pact build src/main.pact -T linux -T macos-arm64
# Produces: build/main-linux, build/main-macos-arm64

# Combined
bin/pact build src/main.pact --release -T linux -T macos-arm64
# Aliases: linux, linux-arm64, macos, macos-arm64, macos-amd64
# Also accepts raw zig target triples: x86_64-linux-gnu, aarch64-macos, etc.
```

### Debugging & Inspection Flags

```sh
# Debug builds (debug_assert enabled, -g -O0)
bin/pact build src/main.pact --debug
bin/pact build src/main.pact -d

# AST dump (JSON) — inspect parsed syntax tree
bin/pact ast src/main.pact                    # full AST as JSON
bin/pact ast src/main.pact --imports          # resolve imports, show merged AST
bin/pact ast src/main.pact --node 42          # dump subtree for node ID 42

# Compiler phase tracing — trace lex/parse/typecheck/codegen phases
bin/pact build src/main.pact --pact-trace all
bin/pact build src/main.pact --pact-trace parse    # single phase

# Treat warnings as errors
bin/pact build src/main.pact --strict
```

### Runtime Execution Tracing (`--trace`)

Emits structured NDJSON to stderr with function enter/exit, state mutations, and effect invocations. Zero cost when not enabled.

```sh
# Trace everything
bin/pact run app.pact --trace all

# Filter by function, module, or depth
bin/pact run app.pact --trace "fn:parse_expr"
bin/pact run app.pact --trace "module:parser,depth:2"
bin/pact run app.pact --trace "fn:skip_ws+parse_block"   # OR with +

# Filter by event type
bin/pact run app.pact --trace "event:enter+exit"          # only enter/exit
bin/pact run app.pact --trace "event:effect"              # only effect invocations
bin/pact run app.pact --trace "event:state"               # only state mutations

# Filter by effect or state variable
bin/pact run app.pact --trace "effect:FS.Write"
bin/pact run app.pact --trace "state:count"

# Cap output to N events
bin/pact run app.pact --trace all --trace-limit 100

# Environment variable (same filter syntax)
PACT_TRACE=all bin/pact run app.pact
PACT_TRACE_LIMIT=50 PACT_TRACE=all bin/pact run app.pact
```

Trace event types:

| Event | Fields | Description |
|-------|--------|-------------|
| `enter` | `span`, `args` | Function entry with source location and arguments |
| `exit` | `duration_us`, `return` | Function exit with duration and return value |
| `effect` | `effect`, `op`, `args` | Effect invocation (IO, FS, DB) |
| `state` | `var`, `op`, `value` | State mutation (assign, push, insert) |

All events include: `ts_us`, `event`, `fn`, `module`, `depth`. Values truncated at 200 chars.

### Low-level Compiler Flags (pactc)

```sh
build/pactc src/main.pact output.c              # compile to C
build/pactc src/main.pact output.c --dump-ast    # dump AST during compilation
build/pactc src/main.pact output.c --stats       # print compilation statistics
build/pactc src/main.pact output.c --debug       # debug mode
build/pactc src/main.pact output.c --emit pact   # emit formatted Pact (formatter)
```
