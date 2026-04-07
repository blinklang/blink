# Blink

> Blink is a statically-typed, effect-tracked programming language that compiles to C. Designed for AI-first development: minimal syntax, no semicolons, universal string interpolation, algebraic effects, and contracts.

Targets native binaries via C codegen.

## Install

**Binary** (Linux/macOS): download from [GitHub Releases](https://github.com/blinklang/blink/releases/latest) and place on PATH.

**Docker**:
```
docker pull ghcr.io/blinklang/blink:latest
docker run --rm -v "$PWD":/workspace ghcr.io/blinklang/blink run myfile.bl
```

Tags: `latest`, `0.32`, `0.32.0` (semver). Image is `debian:bookworm-slim` with `gcc`, `zig`, `blink`, `libgc-dev`, and `libsqlite3-dev`.

## Recent Breaking Changes (v0.32)

- **BREAKING: DB moved to stdlib** — database operations are now a user-defined effect in `lib/std/db.bl` instead of compiler magic. `import std.db` required. `DbRow` renamed to `Row`, `CT_ROW` removed.
- **BREAKING: `Template[C]` replaces raw SQL strings** — DB queries now use `Template[DB]` for automatic parameterization and injection safety. String interpolation in templates auto-extracts parameters. Use `Raw(expr)` to opt out.
- **BREAKING: DB operations return `Result`** — all `db.*` operations now return `Result[T, DBError]` instead of bare types. New `DBError` enum: `QueryError`, `ExecError`, `ConnectionError`, `NotFound`.
- **Associated types on traits** — traits can declare `type Name` members that implementers must define (e.g., `BlockHandler` has `type Context`)
- **`BlockHandler` trait** — scoped resource management with `enter()`/`exit()` methods and associated `Context` type. Enables `with db.transaction() { ... }` pattern.
- **`Closeable` trait cleanup** — `close()` now correctly called on early exit from `with`-blocks (break, return, error propagation)
- **Scoped `db.transaction()`** — auto-commit on success, auto-rollback on failure via `BlockHandler` implementation
- **`Stmt` type** — prepared statement support with `bind_int`, `bind_text`, `step`, `column_int`, `column_text`, `reset`, `finalize` methods
- **Handler captures** — handlers can capture values from their enclosing scope
- **E0601 diagnostic** — new error when `with...as` bindings escape via `async.spawn`
- **Fix** — W0602 false positive on Handler/Template type params
- **Fix** — `_self` param in impl methods generating invalid C void type
- **Fix** — `List[Str]` element type lost across function boundaries
- **Fix** — double-evaluation in `Result.unwrap()`/`unwrap_err()` codegen
- **Fix** — 4 codegen bugs: Set params, Map structs, for-in keys, if-expr methods
- **Fix** — list element type leak through struct impl method calls
- **Fix** — Option types and user-effect dispatch codegen bugs
- **Fix** — 2 formatter bugs: handler body collapse and import inlining

### Prior: What's New (v0.31)

- **Pact references removed** — all remaining `pact` references and `pact.toml` fallback support removed; `.pact` file extension fallback also removed
- **C output renamed** — generated C symbols now use `blink_` prefix instead of `pact_` (no user-facing impact unless inspecting emitted C)
- **Fix** — nested compound type codegen (`Option[Option[T]]`, `Result[Option[T]]`, etc.) now generates correct C types
- **Fix** — `unwrap()` on compound inner types no longer incorrectly returns `Void`
- **Fix** — match type inference for data enum pattern-bound variables
- **Fix** — nested generic return types no longer lose type information in the type tree
- **Fix** — intrinsic method shadowing with nested `Result` codegen
- **Fix** — `Result`+`Option` typedef collisions and function name collisions in C codegen
- **Build** — all compiler and C-level build warnings eliminated

### Prior: What's New (v0.30)

- **`std.testing` module** — `capture_log`, `capture_print`, `capture_eprint` handler factories for intercepting IO in tests
- **IO vtable dispatch** — `io.print`, `io.println`, `io.eprint`, `io.eprintln` now dispatch through the effect vtable, enabling handler interception
- **`io.print_raw` / `io.eprint_raw`** — bypass vtable for direct stdout/stderr output (escape hatches for when you need guaranteed raw output)
- **Fix** — codegen resolution of module-qualified type names (`Result[net.TcpSocket, net.NetError]` now works correctly)
- **Fix** — `Result.unwrap()` type propagation for `List` and `Map` inner types
- **Fix** — codegen type resolution for C-reserved variable names

### Prior: What's New (v0.29)

- **`Handler[E]` as first-class return type** — functions can return `Handler[E]`, store handlers in variables, and pass them as parameters; handlers are heap-allocated to survive beyond their creation scope
- **Fix** — false `UnusedVariable` warnings on pattern matches with built-in enum variants (`None`, `Some`, `Ok`, `Err`)
- **Fix** — handler metadata leakage when multiple functions returned handlers, causing incorrect behavior in `with` blocks
- **Fix** — static name collisions when multiple functions used handler expressions

### Prior: What's New (v0.28)

- **`std.traits` in prelude** — compiler-known traits (`Closeable`, `BlockHandler`, `Sized`, `Contains`, `StrOps`, `ListOps`, `MapOps`, `SetOps`, `BytesOps`, `StringBuildOps`, `Joinable`) are now auto-imported; no explicit `import std.traits` needed
- **`blink add` for Tier 2 stdlib** — `blink add std/http`, `std/net`, `std/db`, `std/log`, `std/config` now work without `--path` or `--git`; packages are added with automatic version pinning
- **Fix** — `@module("")` annotation on trait-only modules now detected correctly (was ignored, causing false W0602)
- **Fix** — unused import checker skips empty module entries

### Prior: Breaking Changes (v0.27)

- **BREAKING: Selective import enforcement** — `import foo` now only provides qualified access (`foo.bar()`). Unqualified access requires selective imports: `import foo.{bar}`. Per-file scoping enforced.
- **Pub re-export semantics** — `pub import` re-exports formalized: consumers see re-exported items as if locally defined; name collisions (define + re-export same name) produce E1012
- **New module error codes** — E1004 (VersionConflict), E1007 (reject module-qualified type member access), E1008 (InvalidModuleAnnotation), E1009 (DuplicateModuleBinding), E1012 (DuplicatePubSymbol), E1052 (PackageNotDeclared for tier-2 imports)
- **`capture_log` test instrumentation** — `std.testing.capture_log` handler factory spec'd for intercepting `io.log()` calls in tests
- **Fix** — module qualifier mangling, loop return type inference, `std.*` resolution
- **Fix** — pub import warnings and enum qualification errors
- **Fix** — false W0602 (unused import) on `pub let mut` assignment

### Prior: Breaking Changes (v0.26)

- **BREAKING: Language renamed Pact → Blink** — binary `pactc` → `blinkc`, env vars `PACT_*` → `BLINK_*`, file extension `.pact` → `.bl`, `pact.toml` → `blink.toml`. Compiler entry point renamed `src/pactc_main.bl` → `src/blinkc_main.bl`. Fallbacks removed in v0.31.
- **Cross-package cycle detection (E1002)** — circular dependencies between packages are now detected and reported at compile time
- **Pub import re-export flattening** — `pub import` re-exports are semantically flattened so downstream consumers see the original module's symbols
- **LSP inlayHints** — inferred types on `let` bindings shown as inline hints in editors
- **@capabilities budget enforcement** — `@capabilities` annotations on modules are now enforced during typechecking
- **Fix** — false `UnusedVariable` warnings on unqualified enum match arms eliminated

### Prior: What's New (v0.25)

- **Qualified module access** — `import auth` then `auth.login()`, `auth.Token`, `auth.MAX_RETRIES`. Covers functions, types, and constants. Selective imports don't restrict qualified access. Resolves name ambiguity (E1005) at the call site.

### Prior: What's New (v0.24)

- **Selective imports & aliases** — `import mod.{add, multiply as mul}` restricts which items are imported; aliases rename items at import site; ambiguous names across modules produce a compile error
- **`Closeable` trait** — `impl Closeable for T` enables `with expr as name { ... }` blocks that auto-call `.close()` on scope exit (reverse order for multi-resource)
- **Rich panic messages** — `unwrap()` / `unwrap_err()` panics now include source file and line number
- **LSP workspace/symbol & formatting** — `workspace/symbol` for project-wide symbol search; `textDocument/formatting` for in-editor format
- **Fix** — closures returning `Option[T]` now generate correct C type
- **Fix** — helpful E1109 error when `mut` is used on struct/enum fields (mutability is on the binding, not the field)

### Prior: What's New (v0.23.3)

- **Portable cross-compilation** — vendored GC source/headers embedded in binary; `blink build --target` now works from standalone installs without the source tree
- **Docker** — image includes `libgc-dev` for native builds and zig for cross-compilation
- **Perf** — `#embed` codegen uses byte arrays instead of escaped string literals; `escape_c_string` and other hot-path functions use StringBuilder (O(n) vs O(n²))

### Prior: What's New (v0.23.2)

- **Fixes** — for-in loop over `List[DataEnum]` now registers enum type for match inference
- **Docker** — image now includes zig for cross-compilation via `--target`

### Prior: What's New (v0.23.1)

- **Fixes** — recursive self-referencing data enum variants, data enum values in list literals, `?` operator Result type when fn returns struct

### Prior: What's New (v0.23)

- **`?` operator on `Option[T]`** — propagates None in Option-returning functions (mirrors Result `?`)
- **User-defined effects** — `effect` declarations with sub-effects, `with handler` blocks, namespaced dispatch (`metrics.counter(...)`)
- **Boehm GC** — automatic garbage collection via libgc, replaces manual memory management
- **`List.clear()` / `Map.clear()`** — in-place mutation to empty collections
- **Fixes** — Result/Option type resolution in match/? expressions, impl method return types, enum variant codegen

### Prior: What's New (v0.22)

- **`TcpSocket` / `TcpListener` types** — typed wrappers for TCP file descriptors with trait-based methods (`read`, `read_all`, `write`, `close`, `set_timeout`)
- **`std.net` TCP stdlib** — `tcp_listen`, `tcp_connect`, `tcp_accept`, `tcp_read`, `tcp_write`, `tcp_close`, `tcp_set_timeout`, `tcp_read_all`
- **`net.*` namespace methods** — `net.listen`, `net.accept`, `net.read`, `net.write`, `net.close`, `net.connect`, `net.set_timeout`, `net.read_all`
- **`NetError` enum** — Timeout, ConnectionRefused, DnsFailure, TlsError, InvalidUrl, BindError, ProtocolError
- **Fixes** — typecheck string methods, Result/Option type mismatches for enums/generics, nested compound type codegen, trait dispatch, LSP parser reset, async spawn, daemon parser reset

### Prior: What's New (v0.21)

- **`Set[T]` builtin type** — generic hash set with `insert`, `remove`, `contains`, `len`, `is_empty`, `union` methods
- **LSP completion** — dot-triggered symbol + keyword completion with type info
- **LSP documentSymbol** — file symbol listing with kinds and ranges
- **LSP signatureHelp** — function signature display on `(` and `,` with active parameter highlighting
- **LSP rename** — cross-file symbol rename
- **LSP codeAction** — quickfix actions from diagnostics
- **Fix** — stdlib diagnostic paths normalized to strip `build/` prefix

### Prior: Breaking Changes (v0.20)

- **BREAKING: `path_param()` removed** — replaced by `req_path_param(req, name)` on the Request object (per-request instead of global state)
- **Trait declarations** — builtin traits for all core types: Sized, Contains[T], StrOps, ListOps[T], MapOps[K,V], SetOps[T], BytesOps, StringBuildOps, Joinable
- **Trait-based method dispatch** — builtin type methods now routed through trait impl registry instead of hardcoded type checks
- **Trait impl validation** — compiler rejects `impl` blocks for undefined traits (E0904), validates method signatures match trait contracts
- **Concurrent HTTP server** — `server_serve_async()` with threadpool, `server_max_connections()` for backpressure
- **Fixes** — struct return from if/else in closures, Map type loss in closures, List[EnumType] codegen, Channel codegen gaps, multi-fn query, 4 codegen/typechecker bugs
- **Perf** — pre-split HTTP route patterns at registration time

### Prior: What's New (v0.19)

- **List HOF stdlib** — `list_map`, `list_filter`, `list_fold`, `list_any`, `list_all`, `list_for_each`, `list_concat`, `list_slice` — generic higher-order functions
- **Map HOF stdlib** — `map_for_each`, `map_filter`, `map_fold`, `map_map_values`, `map_merge`
- **String ops → Blink stdlib** — `str_split`, `str_join`, `str_replace`, `str_lines`, `str_trim`, `str_to_upper`, `str_to_lower` migrated from C runtime
- **HTTP client → Blink stdlib** — full HTTP client migrated from C runtime to Blink
- **Data enums in List** — `push`, `get`, and `match` now work with data enum elements
- **LSP textDocument/references** — find all usages of a symbol across files
- **Test compilation ~3x faster** — parallel test compilation on multi-core machines
- **Package system v1** — git + path dependencies verified end-to-end
- **Fixes** — generic monomorphization Option[T]/Result[T,E], match expression type inference for pattern bindings, diagnostic file attribution for @module("") modules, pub visibility in generic type params

### Prior: What's New (v0.18)

- **Stdlib migrations** — Duration/Instant, StringBuilder, string functions, Bytes migrated from C runtime to Blink stdlib
- **I/O primitives** — `io.read_line()`, `io.read_bytes(n)`, `io.write(s)`, `io.write_bytes(b)`

### Prior: What's New (v0.16.1)

- **Bugfix** — git dependency import resolution used wrong cache subdirectory

### Prior: Breaking Changes (v0.16)

- **pub visibility enforcement** — enum variants, trait names, type references, and `let`/`const` bindings must be `pub` to use across modules. Existing cross-module references to non-pub items will now error.
- **`--trace` → `--blink-trace`** — compiler phase tracing flag renamed to avoid conflicts
- **`std.path` module** — `path_join`, `path_dirname`, `path_basename` moved from C builtins to `import std.path` (stdlib). Old builtin calls still work but prefer the import.
- **StringBuilder type** — new compiler-intrinsic `StringBuilder` with `new()`, `write()`, `write_char()`, `to_str()`, `len()`, `capacity()`, `clear()`, `is_empty()`
- **`--dump-ast` flag** — dump parsed AST for debugging
- **Auto-resolve deps** — `blink build/run/test/check` now auto-resolves dependencies (no manual `blink update` needed)
- **Self-bootstrap** — compiler bootstraps from PATH `blink`; no checked-in C bootstrap files
- **Quiet test output** — `blink test` is quiet by default; use `--verbose` for detail
- **Perf: O(N²) concat → StringBuilder** — lexer/formatter performance improvement
- **Bugfixes** — lockfile not loaded on second build, 3,718 compiler warnings eliminated, CT_TAGGED_ENUM leak as Void, nested list element type lost in type pool

### Prior: What's New (v0.15)

- **FFI system** — `@ffi("lib", "symbol")` annotation, `@trusted` audit marker, `Ptr[T]` type with methods (deref, addr, write, is_null, to_str, as_cstr), `ffi.scope()` resource management (alloc, cstr, take)
- **Keyword arguments** — named arguments in function calls: `fn(pos, name: val)`
- **`@allow` diagnostic suppression** — suppress specific warnings: `@allow(W0600)`
- **`@invariant` struct assertions** — struct-level invariants: `@invariant(self.balance >= 0)`
- **Vendored C cross-compilation** — compile vendored C sources with cross-compile support; SQLite3 amalgamation bundle included
- **`blink audit`** — FFI audit command: inventory @ffi calls, audit status, pointer operations
- **`blink update`** — updates dependencies, lockfile, and stamps `blink-version` in `blink.toml`
- **Native dependencies** — `blink.toml [native-dependencies]` section for linking C libraries
- **Bugfixes** — `\r` escape bootstrap, comment preservation in type/trait/impl bodies, UnaryOp type inference, TokenKind type annotations

### Prior: What's New (v0.14)

- **Unused variable warnings** — compiler emits W0600 for `let` bindings that are never read; prefix with `_` to suppress
- **Cross-compilation fix** — removed spurious libcurl link dependency that caused linker failures on non-host targets

### Prior: What's New (v0.13.3)

- **`List[List[T]]` function parameter fix** — nested list parameters now propagate inner element types correctly (`.get()` on inner list no longer produces `blink_Option_int`)

### Prior: What's New (v0.13.2)

- **Nested struct type propagation** — `List[List[Struct]]` and `Option[List[Struct]]` now correctly propagate inner struct types through `for` loops, `let` bindings, `??`, `.unwrap()`, and `match Some(x)`

### Prior: What's New (v0.13.1)

- **`List[List[T]]` codegen fix** — `.get()`, `.pop()`, `.unwrap()`, and `??` on nested lists now produce correct C types (`blink_Option_list` instead of `blink_Option_int`)
- **Extended string lexer fix** — `"#{"` no longer misparsed as end delimiter in extended strings

### Prior: What's New (v0.13)

- **SQLite `db.*` namespace** — 16 methods for database operations: `db.open`, `db.exec`, `db.execute`, `db.query`, `db.query_one`, `db.prepare`, `db.bind_int`, `db.bind_text`, `db.bind_real`, `db.step`, `db.column_text`, `db.column_int`, `db.reset`, `db.finalize`, `db.close`, `db.errmsg`
- **`blink.toml` versioning** — `blink init` stamps `blink-version` in project manifest
- **`\r` escape sequence** — carriage return now supported in string literals

### Prior: What's New (v0.12)

- **Tuple destructuring** — `let (a, b) = some_tuple` in let bindings
- **Extended strings** — `#"literal "quotes" and \backslashes"#` with `#{expr}` interpolation
- **Struct field defaults** — `type Point { x: Int = 0, y: Int = 0 }`, omit fields at construction
- **`@requires` contracts** — precondition annotations on functions
- **Nested generics** — `List[List[Int]]` and other parameterized inner types
- **`--release` flag** — optimized builds with `-O2`
- **Multi-target builds** — `bin/blink build -T linux -T macos-arm64`
- **Error catalog** — `blink explain E1234` with machine-applicable fix suggestions
- **Closure const-qualifier fix** — eliminated dozens of C compiler warnings in bootstrap
- **List[T] param fix** — struct element types now preserved through function parameters
- **`mod {}` parser error** — helpful E1015 error instead of generic parse failure

### Prior: What's New (v0.11.1)

- **Cross-module error locations** — diagnostics in imported modules now report the correct source file (was always showing main file)

### Prior: What's New (v0.11)

- **`blink doc --list`** — list available stdlib modules for discoverability
- **Type error locations** — type errors now report source file + line number
- **`set_version(p, ver)`** — set version string on ArgParser (shows in `--version` / help)
- **`args_get_all(a, name)`** — get all values for a repeated option (returns `List[Str]`)
- **`parse_argv(p, argv)`** — parse an explicit argv list instead of process args
- **`add_command_alias(p, alias, target)`** — register command aliases in CLI parser
- **Better CLI error messages** — bare-word errors in argument parsing

### Prior: What's New (v0.10)

- **`blink doc <module>`** — print module documentation (types, functions, traits with signatures and doc comments). Supports `--json` for machine-readable output
- **Embedded stdlib** — stdlib modules are compiled into the CLI binary; `blink doc std.args` works without source files on disk
- **Stdlib doc comments** — `///` doc comments with examples added to std.args, std.json, std.toml, std.semver, std.http_*

### Prior: What's New (v0.9)

- **List pattern matching** in `match`: `[]`, `[a, b]`, `[first, ...]` with rest wildcard
- **Nested subcommands** in `std.args`: dotted paths (`add_command(p, "daemon.start", ...)`), `args_command_path()` returns `List[Str]`
- **Parallel test execution**: `blink test --parallel` / `-P` (default 4 workers)
- `blink init` now idempotent for existing projects

### Prior: Breaking Changes (v0.8)

- `str_from_char_code()` removed → use `Char.from_code_point(n)` (returns `Str`)
- `\b` (backspace) and `\f` (form feed) escape sequences added
- CLI flags now scoped to subcommands

### Prior: What's New (v0.7)

- `process_exec(cmd, args)` — exec a binary directly (replaces current process)
- `args_rest(a)` — get remaining args after `--` from argparser
- 5 codegen/lexer bugfixes, test suite migrated to `test` blocks, CI parallelized

### Prior: Breaking Changes (v0.6)

- `List.get(idx)` returns `Option[T]` (was `T`). Use `?? default` or `match`.
- `const NAME = expr` for compile-time constants (was `let` at module level).
- `#embed("path")` compile-time file inclusion intrinsic.

Key facts:
- `fn` keyword, `{ }` braces, no semicolons, newline-separated statements
- `"double quotes"` only, universal interpolation: `"Hello, {name}!"`
- Square bracket generics: `List[T]`, `Map[K, V]`, `Result[T, E]`
- Error handling: `Result[T, E]` + `?` propagation, `Option[T]` + `??` default
- Effects: `fn foo() ! IO, DB` — tracked in signatures, provided by handlers
- `io.println(...)` not `print(...)` — IO goes through effect handles
- No string `+` operator — use interpolation or `.concat()`

## Standard Library

`std.args` (CLI parsing), `std.db` (SQLite database with effect-based API), `std.http` (HTTP client/server), `std.json` (JSON), `std.net` (TCP networking), `std.path` (path utilities), `std.semver` (versions), `std.toml` (TOML).
Prelude (auto-imported): `std.str` (string ops), `std.list` (list HOFs), `std.map` (map HOFs), `std.num`, `std.sb`, `std.bytes`, `std.time`, `std.traits` (core traits).
Run `blink doc --list` to list modules, `blink doc <module>` for details.

## Docs

- [Full LLM Reference](llms-full.md): Complete self-contained language reference with all syntax, builtins, methods, and examples
- [Language Spec Index](SPEC.md): Design decisions, philosophy, detailed specification
- [Syntax & Closures](sections/02_syntax.md): fn, let, match, strings, closures, annotations
- [Types & Generics](sections/03_types.md): Structs, enums, generics, traits, tuples
- [Effects & Concurrency](sections/04_effects.md): Effect system, handlers, capabilities, async
- [Modules & FFI](sections/07_trust_modules_metadata.md): Imports, modules, all 15 annotations

## Examples

- [Hello World](examples/hello.bl): CLI args, string interpolation, effects
- [Todo App](examples/todo.bl): Structs, enums, traits, Result, pattern matching, tests
- [Calculator](examples/calculator.bl): Recursive ADTs, contracts, refinement types
- [FizzBuzz](examples/fizzbuzz.bl): Basic control flow
- [Web API](examples/web_api.bl): HTTP server with effects

## Optional

- [Tooling](sections/06_tooling.md): Compiler daemon, LSP, formatter, test framework, package manager
- [Contracts](sections/03b_contracts.md): Refinement types, @requires/@ensures, verification
- [Memory & Errors](sections/05_memory_compile_errors.md): GC, arenas, compilation, diagnostics
