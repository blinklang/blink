# Blink Changelog

Single source of truth for release history. `blink llms` and `blink llms --full` both append this file after the reference text, and every release version is indexed as a topic (e.g. `blink llms --topic v0.36`). **Edit only here** — `llms.md` and `llms-full.md` hold only a `## Recent Changes` stub pointing at this file.

## Breaking Changes (v0.39)

- **`Str.char_at(i)` now returns `Option[Char]`** (was `Int`). Returns `None` if
  out of range or `i` points at a UTF-8 continuation byte. Use `Str.byte_at(i)`
  for raw byte access.
- **`Char.from_code_point(n)` now returns `Result[Char, ConversionError]`** (was `Str`).
  Use `str_from_code_point(n)` (from `std.str`) to get the old `Str` behaviour.

## What's New (v0.39)

- **`Char` primitive type** — Unicode scalar value with single-quote literals
  (`'a'`, `'\n'`, `'\t'`, `'\\'`, `'\''`). Instance methods: `.to_int()`, `.to_str()`.
  `Char.from_code_point(n)` returns `Result[Char, ConversionError]`; use
  `str_from_code_point(n)` for the single-character `Str`.
- **Struct-style enum variants** — enums may now declare struct variants:
  `enum E { Variant { field: Type } }`. Construct as `E.Variant { field: val }`,
  destructure in `match` with `Variant { field } =>`.
- **`Str.byte_at(i) -> Int`** — raw byte access for byte-indexed scanning
  (replaces the old `char_at` when byte values are what you actually want).
- **`Str.trim_right()` / `Str.trim_left()`** — strip trailing / leading
  whitespace. Complement to the existing `.trim()`.
- **Parser diagnostics** — error messages now show token names ("expected IDENT,
  got `let`") instead of numeric kind IDs, and include a Rust-style source line
  with a caret gutter. Multi-character tokens produce `^^^^^` underlines.

### Fixes

- `str_to_upper` / `str_to_lower` no longer corrupt non-ASCII text. They now
  iterate codepoints instead of raw bytes.
- Qualified struct literals `module.Type { field: val }` now compile correctly
  (were rejected with "unknown type 'module'").
- Formatter idempotency: wrapped multi-line method calls and block-like
  expressions (`match`, `if`, closures, handlers, `async.scope`/`async.spawn`)
  in expression position now round-trip cleanly. `format(format(x)) == format(x)`.
- Truncated or malformed input (unterminated string interpolations, unclosed
  `match`/`impl`/`trait`/struct-lit/list-lit/`type` blocks) no longer panics
  or OOMs the parser — a structured diagnostic is emitted instead.
- `assert(cond, msg)` now prints `msg` on failure. Previously codegen dropped the
  second argument and hardcoded "assertion failed".
- `assert(cond, msg)` / `debug_assert(cond, msg)` evaluate `msg` lazily — only
  when the assertion actually fails, matching Rust/C semantics.

## What's New (v0.38)

- **Sized scalar integer types** — `I8`, `I16`, `I32`, `U8`, `U16`, `U32`, `U64`
  as first-class types (previously only inner types of `Ptr[T]`). Conversion
  methods `.to_i8` / `.to_i16` / `.to_i32` / `.to_u8` / `.to_u16` / `.to_u32`
  / `.to_u64` / `.to_int` with C-style wrapping casts. No implicit promotion
  with `Int`. Unblocks FFI against libc signatures like
  `int isatty(int fd)` and `uint32_t htonl(uint32_t)`.
- **`fs.remove(path)`** — built-in file deletion backed by `unlink(2)`.
- **Binary-safe TCP I/O** — `std.net` gains `tcp_read_bytes` / `tcp_write_bytes`
  returning `Result[Bytes, NetError]`, preserving null bytes and non-UTF-8
  sequences that the `Str`-based variants truncated. New `NetError.IoError`
  variant for these paths.
- **Fixed-width `bytes` accessors** — 16 new big-endian / little-endian
  integer accessors: `read_u16_be`, `read_u16_le`, `read_u32_be`, `read_u32_le`,
  `read_i32_be`, `read_i32_le`, `read_i64_be`, `read_i64_le` and matching
  `write_*` methods. Reads return `Result[Int, Str]` with explicit bounds
  check.

### Fixes

- `Result[Bytes, E].unwrap()` now emits the correct `Bytes` type (was `Int`),
  so downstream method calls on unwrapped bytes type-check.
- `let mut` captured and *read* inside a closure no longer raises W0601
  (dead-store) on writes in the enclosing scope — the closure can observe
  later writes when called, so the read is live.
- LSP no longer emits E0506 / E0300 false positives on `with arena { … }`
  blocks (the `arena` keyword is no longer mis-parsed as an undefined
  variable).

## What's New (v0.37)

- **`with arena { }` arena allocation** — opt-in bump allocator scoped to a block. Tail of `with arena { expr }` is deep-copied (promoted) into the enclosing arena or GC heap, so scratch work is reclaimed while the result survives. Functions that allocate into the caller's arena carry `! Arena`. Supports primitives, `Str`, structs (including `Str` fields), `List`, `Map`, `Option`, `Result`, nested arenas, and closure tails (including closures that capture other closures). See spec §5.2 / §5.2.1 and `blink llms --topic arena`.
- **Arena diagnostics** — E0700 (value escapes arena), E0701 (cyclic type across arena boundary), E0702a–d (unsupported closure tails), W0701 (redundant `! Arena`).
- **`std.arena.bytes_used()`** — live bytes in the innermost active arena. Intended for tests and introspection.
- **`arena.promote` trace event** — spanned begin/end events around each tail promotion, with target (`outer arena` / `GC heap`) and descriptor. Available under `--trace` and `--blink-trace codegen`.
- **`task bench`** — arena vs GC benchmark harness (`benchmarks/arena_process_batch.bl`).

### Fixes

- `List[Map[K, V]].get` / `.pop` no longer lose the inner `Map` type in codegen (previously produced `Option[Int]` and downstream `UnresolvedMethod` on `.get(key)`).
- Parser accepts `if` / `while` with the condition wrapped to a new line — `bin/blink fmt` output now round-trips through `check`.
- Formatter emits trailing `+` / `&&` (not leading) on wrapped binop chains, matching what the parser accepts.

## Breaking Changes (v0.36)

- **BREAKING: `Map.get` now returns `Option[V]`** — `Map.set`, `Map.has`, and `Map.raw_get` removed. Use `map[key] = value` for insertion and pattern-match the `Option` from `map.get(k)`.
- **BREAKING: `Option[Struct]` stores pointer** — `Option[T]` for struct `T` no longer stores an inline copy. Affects FFI/interop code that assumed inline layout.
- **BREAKING: mutation lints promoted to errors** — previously soft warnings around implicit mutation now hard-fail compilation.
- **`..` spread operator** — struct copy-update (`Point { x: 1, ..source }`) and list spread (`[..a, x, ..b]`). See spec §2.16.
- **String-backed enums** — enums can be declared with `Str` discriminants (`Open = "open"`), with auto-generated `to_str` / `from_str` and Serialize/Deserialize using the string values.
- **`@derive(Eq, Clone)`** — generates field-wise equality and value-copy clone for structs and enums.
- **`@deprecated`** — emits W2000 (DeprecatedUsage) at call sites. Supports `since` / `replacement` metadata; suppress with `@allow(DeprecatedUsage)`.
- **`std.term` honors `NO_COLOR`** — when set, style/color functions return strings unchanged per the no-color.org standard.
- **Fix** — Option[Map/List] type loss through `Map.get_opt`.
- **Fix** — `db.connect` handle leak.

## What's New (v0.35.1)

- **Fix** — if-expr type inference for module-qualified calls
- **Fix** — fn return type collisions in multi-file codegen
- **Fix** — cross-module private fn collisions and empty facade docs
- Doc comments added to undocumented stdlib modules

## Breaking Changes (v0.35)

- **BREAKING: `get_env()` removed** — use `env.var(name)` instead (returns `Option[Str]`, dispatches through Env effect vtable)
- **BREAKING: `std.flat_json` removed** — use `std.json` instead
- **Env effect namespace** — new `env.var(name)`, `env.cwd()`, `env.set_var(name, value)`, `env.remove_var(name)`, `env.exit(code)` methods dispatch through vtable, enabling handler interception
- **`db.connect(path)`** — convenience method to open a SQLite connection directly: `with db.connect(path) { ... }`
- **Map/List type unification** — struct field types for `Map` and `List` now use parameterized `tp_id` instead of duplicated type info
- **Fix** — formatter mangling tuple syntax and codegen losing tuple type in List elements
- **Fix** — List elem type leaking across function boundaries in codegen
- **Fix** — Map[K,V] type loss through struct field access
- **Fix** — `--trace codegen` undeclared `__trace_enter_ts` in effect handlers
- **Fix** — `db.exec` failing on PRAGMA statements that return result rows
- **Fix** — FFI lib detection improvements

## What's New (v0.34)

- **Tier-2 stdlib removed** — all `std.*` modules are now tier-1: embedded in the compiler binary, version-locked, no `blink.toml` entry required. `std.db` and `std.term` no longer need explicit dependency declarations. E1052 (PackageNotDeclared) gate removed for `std.*` imports.
- **Fix** — `blink doc std.db` now works on installed binaries (modules are embedded)

## What's New (v0.33)

- **`std.term` module** — ANSI styling (`bold`, `dim`, `italic`, `underline`, `strikethrough`, colors, background colors), TTY detection (`is_tty`, `terminal_width`, `terminal_height`), cursor control (`move_up`, `clear_screen`, `hide_cursor`, etc.). `import std.term`
- **Template[C] introspection** — new methods `parts()`, `count()`, `type_tag(idx)`, `get_str(idx)`, `get_int(idx)`, `get_float(idx)`, `get_bool(idx)` expose template internals, enabling DB drivers written in pure Blink
- **SQLite rewritten in pure Blink** — `std.db` no longer uses C runtime helpers for template query execution; uses Template introspection + low-level FFI bindings instead
- **Fix** — codegen handler state leak and W0501 Template parameter count diagnostic

## Breaking Changes (v0.32)

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

## What's New (v0.31)

- **Pact references removed** — all remaining `pact` references and `pact.toml` fallback support removed; `.pact` file extension fallback also removed
- **C output renamed** — generated C symbols now use `blink_` prefix instead of `pact_` (no user-facing impact unless inspecting emitted C)
- **Fix** — nested compound type codegen (`Option[Option[T]]`, `Result[Option[T]]`, etc.) now generates correct C types
- **Fix** — `unwrap()` on compound inner types no longer incorrectly returns `Void`
- **Fix** — match type inference for data enum pattern-bound variables
- **Fix** — nested generic return types no longer lose type information in the type tree
- **Fix** — intrinsic method shadowing with nested `Result` codegen
- **Fix** — `Result`+`Option` typedef collisions and function name collisions in C codegen
- **Build** — all compiler and C-level build warnings eliminated

## What's New (v0.30)

- **`std.testing` module** — `capture_log`, `capture_print`, `capture_eprint` handler factories for intercepting IO in tests
- **IO vtable dispatch** — `io.print`, `io.println`, `io.eprint`, `io.eprintln` now dispatch through the effect vtable, enabling handler interception
- **`io.print_raw` / `io.eprint_raw`** — bypass vtable for direct stdout/stderr output (escape hatches for when you need guaranteed raw output)
- **Fix** — codegen resolution of module-qualified type names (`Result[net.TcpSocket, net.NetError]` now works correctly)
- **Fix** — `Result.unwrap()` type propagation for `List` and `Map` inner types
- **Fix** — codegen type resolution for C-reserved variable names

## What's New (v0.29)

- **`Handler[E]` as first-class return type** — functions can return `Handler[E]`, store handlers in variables, and pass them as parameters; handlers are heap-allocated to survive beyond their creation scope
- **Fix** — false `UnusedVariable` warnings on pattern matches with built-in enum variants (`None`, `Some`, `Ok`, `Err`)
- **Fix** — handler metadata leakage when multiple functions returned handlers, causing incorrect behavior in `with` blocks
- **Fix** — static name collisions when multiple functions used handler expressions

## What's New (v0.28)

- **`std.traits` in prelude** — compiler-known traits (`Closeable`, `BlockHandler`, `Sized`, `Contains`, `StrOps`, `ListOps`, `MapOps`, `SetOps`, `BytesOps`, `StringBuildOps`, `Joinable`) are now auto-imported; no explicit `import std.traits` needed
- **`blink add` for stdlib** — `blink add std/<pkg>` works without `--path` or `--git`; packages are added with automatic version pinning
- **Fix** — `@module("")` annotation on trait-only modules now detected correctly (was ignored, causing false W0602)
- **Fix** — unused import checker skips empty module entries

## Breaking Changes (v0.27)

- **BREAKING: Selective import enforcement** — `import foo` now only provides qualified access (`foo.bar()`). Unqualified access requires selective imports: `import foo.{bar}`. Per-file scoping enforced.
- **Pub re-export semantics** — `pub import` re-exports formalized: consumers see re-exported items as if locally defined; name collisions (define + re-export same name) produce E1012
- **New module error codes** — E1004 (VersionConflict), E1007 (reject module-qualified type member access), E1008 (InvalidModuleAnnotation), E1009 (DuplicateModuleBinding), E1012 (DuplicatePubSymbol)
- **`capture_log` test instrumentation** — `std.testing.capture_log` handler factory spec'd for intercepting `io.log()` calls in tests
- **Fix** — module qualifier mangling, loop return type inference, `std.*` resolution
- **Fix** — pub import warnings and enum qualification errors
- **Fix** — false W0602 (unused import) on `pub let mut` assignment

## Breaking Changes (v0.26)

- **BREAKING: Language renamed Pact → Blink** — binary `pactc` → `blinkc`, env vars `PACT_*` → `BLINK_*`, file extension `.pact` → `.bl`, `pact.toml` → `blink.toml`. Compiler entry point renamed `src/pactc_main.bl` → `src/blinkc_main.bl`. Fallbacks removed in v0.31.
- **Cross-package cycle detection (E1002)** — circular dependencies between packages are now detected and reported at compile time
- **Pub import re-export flattening** — `pub import` re-exports are semantically flattened so downstream consumers see the original module's symbols
- **LSP inlayHints** — inferred types on `let` bindings shown as inline hints in editors
- **@capabilities budget enforcement** — `@capabilities` annotations on modules are now enforced during typechecking
- **Fix** — false `UnusedVariable` warnings on unqualified enum match arms eliminated

## What's New (v0.25)

- **Qualified module access** — `import auth` then `auth.login()`, `auth.Token`, `auth.MAX_RETRIES`. Covers functions, types, and constants. Selective imports don't restrict qualified access. Resolves name ambiguity (E1005) at the call site.

## What's New (v0.24)

- **Selective imports & aliases** — `import mod.{add, multiply as mul}` restricts which items are imported; aliases rename items at import site; ambiguous names across modules produce a compile error
- **`Closeable` trait** — `impl Closeable for T` enables `with expr as name { ... }` blocks that auto-call `.close()` on scope exit (reverse order for multi-resource)
- **Rich panic messages** — `unwrap()` / `unwrap_err()` panics now include source file and line number
- **LSP workspace/symbol & formatting** — `workspace/symbol` for project-wide symbol search; `textDocument/formatting` for in-editor format
- **Fix** — closures returning `Option[T]` now generate correct C type
- **Fix** — helpful E1109 error when `mut` is used on struct/enum fields (mutability is on the binding, not the field)

## What's New (v0.23.3)

- **Portable cross-compilation** — vendored GC source/headers embedded in binary; `blink build --target` now works from standalone installs without the source tree
- **Docker** — image includes `libgc-dev` for native builds and zig for cross-compilation
- **Perf** — `#embed` codegen uses byte arrays instead of escaped string literals; `escape_c_string` and other hot-path functions use StringBuilder (O(n) vs O(n²))

## What's New (v0.23.2)

- **Fixes** — for-in loop over `List[DataEnum]` now registers enum type for match inference
- **Docker** — image now includes zig for cross-compilation via `--target`

## What's New (v0.23.1)

- **Fixes** — recursive self-referencing data enum variants, data enum values in list literals, `?` operator Result type when fn returns struct

## What's New (v0.23)

- **`?` operator on `Option[T]`** — propagates None in Option-returning functions (mirrors Result `?`)
- **User-defined effects** — `effect` declarations with sub-effects, `with handler` blocks, namespaced dispatch (`metrics.counter(...)`)
- **Boehm GC** — automatic garbage collection via libgc, replaces manual memory management
- **`List.clear()` / `Map.clear()`** — in-place mutation to empty collections
- **Fixes** — Result/Option type resolution in match/? expressions, impl method return types, enum variant codegen

## What's New (v0.22)

- **`TcpSocket` / `TcpListener` types** — typed wrappers for TCP file descriptors with trait-based methods (`read`, `read_all`, `write`, `close`, `set_timeout`)
- **`std.net` TCP stdlib** — `tcp_listen`, `tcp_connect`, `tcp_accept`, `tcp_read`, `tcp_write`, `tcp_close`, `tcp_set_timeout`, `tcp_read_all`
- **`net.*` namespace methods** — `net.listen`, `net.accept`, `net.read`, `net.write`, `net.close`, `net.connect`, `net.set_timeout`, `net.read_all`
- **`NetError` enum** — Timeout, ConnectionRefused, DnsFailure, TlsError, InvalidUrl, BindError, ProtocolError
- **Fixes** — typecheck string methods, Result/Option type mismatches for enums/generics, nested compound type codegen, trait dispatch, LSP parser reset, async spawn, daemon parser reset

## What's New (v0.21)

- **`Set[T]` builtin type** — generic hash set with `insert`, `remove`, `contains`, `len`, `is_empty`, `union` methods
- **LSP completion** — dot-triggered symbol + keyword completion with type info
- **LSP documentSymbol** — file symbol listing with kinds and ranges
- **LSP signatureHelp** — function signature display on `(` and `,` with active parameter highlighting
- **LSP rename** — cross-file symbol rename
- **LSP codeAction** — quickfix actions from diagnostics
- **Fix** — stdlib diagnostic paths normalized to strip `build/` prefix

## Breaking Changes (v0.20)

- **BREAKING: `path_param()` removed** — replaced by `req_path_param(req, name)` on the Request object (per-request instead of global state)
- **Trait declarations** — builtin traits for all core types: Sized, Contains[T], StrOps, ListOps[T], MapOps[K,V], SetOps[T], BytesOps, StringBuildOps, Joinable
- **Trait-based method dispatch** — builtin type methods now routed through trait impl registry instead of hardcoded type checks
- **Trait impl validation** — compiler rejects `impl` blocks for undefined traits (E0904), validates method signatures match trait contracts
- **Concurrent HTTP server** — `server_serve_async()` with threadpool, `server_max_connections()` for backpressure
- **Fixes** — struct return from if/else in closures, Map type loss in closures, List[EnumType] codegen, Channel codegen gaps, multi-fn query, 4 codegen/typechecker bugs
- **Perf** — pre-split HTTP route patterns at registration time

## What's New (v0.19)

- **List HOF stdlib** — `list_map`, `list_filter`, `list_fold`, `list_any`, `list_all`, `list_for_each`, `list_concat`, `list_slice` — generic higher-order functions
- **Map HOF stdlib** — `map_for_each`, `map_filter`, `map_fold`, `map_map_values`, `map_merge`
- **String ops → Blink stdlib** — `str_split`, `str_join`, `str_replace`, `str_lines`, `str_trim`, `str_to_upper`, `str_to_lower` migrated from C runtime
- **HTTP client → Blink stdlib** — full HTTP client migrated from C runtime to Blink
- **Data enums in List** — `push`, `get`, and `match` now work with data enum elements
- **LSP textDocument/references** — find all usages of a symbol across files
- **Test compilation ~3x faster** — parallel test compilation on multi-core machines
- **Package system v1** — git + path dependencies verified end-to-end
- **Fixes** — generic monomorphization Option[T]/Result[T,E], match expression type inference for pattern bindings, diagnostic file attribution for @module("") modules, pub visibility in generic type params

## What's New (v0.18)

- **Stdlib migrations** — Duration/Instant, StringBuilder, string functions, Bytes migrated from C runtime to Blink stdlib
- **I/O primitives** — `io.read_line()`, `io.read_bytes(n)`, `io.write(s)`, `io.write_bytes(b)`

## What's New (v0.17)

- **Stdlib migrations** — Duration/Instant, StringBuilder, string functions, Bytes migrated from C runtime to Blink stdlib
- **I/O primitives** — `io.read_line()`, `io.read_bytes(n)`, `io.write(s)`, `io.write_bytes(b)` — stdin/stdout binary and line-oriented I/O
- **StringBuilder extras** — `.write_int(n)`, `.write_float(f)`, `.write_bool(b)`, `StringBuilder.with_capacity(n)`

## What's New (v0.16.1)

- **Bugfix** — git dependency import resolution used wrong cache subdirectory

## Breaking Changes (v0.16)

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

## What's New (v0.15)

- **FFI system** — `@ffi("lib", "symbol")` annotation, `@trusted` audit marker, `Ptr[T]` type with methods (deref, addr, write, is_null, to_str, as_cstr), `ffi.scope()` resource management (alloc, cstr, take)
- **Keyword arguments** — named arguments in function calls: `fn(pos, name: val)`
- **`@allow` diagnostic suppression** — suppress specific warnings: `@allow(W0600)`
- **`@invariant` struct assertions** — struct-level invariants: `@invariant(self.balance >= 0)`
- **Vendored C cross-compilation** — compile vendored C sources with cross-compile support; SQLite3 amalgamation bundle included
- **`blink audit`** — FFI audit command: inventory @ffi calls, audit status, pointer operations
- **`blink update`** — updates dependencies, lockfile, and stamps `blink-version` in `blink.toml`
- **Native dependencies** — `blink.toml [native-dependencies]` section for linking C libraries
- **Bugfixes** — `\r` escape bootstrap, comment preservation in type/trait/impl bodies, UnaryOp type inference, TokenKind type annotations

## What's New (v0.14)

- **Unused variable warnings** — compiler emits W0600 for `let` bindings that are never read; prefix with `_` to suppress
- **Cross-compilation fix** — removed spurious libcurl link dependency that caused linker failures on non-host targets

## What's New (v0.13.3)

- **`List[List[T]]` function parameter fix** — nested list parameters now propagate inner element types correctly (`.get()` on inner list no longer produces `blink_Option_int`)

## What's New (v0.13.2)

- **Nested struct type propagation** — `List[List[Struct]]` and `Option[List[Struct]]` now correctly propagate inner struct types through `for` loops, `let` bindings, `??`, `.unwrap()`, and `match Some(x)`

## What's New (v0.13.1)

- **`List[List[T]]` codegen fix** — `.get()`, `.pop()`, `.unwrap()`, and `??` on nested lists now produce correct C types (`blink_Option_list` instead of `blink_Option_int`)
- **Extended string lexer fix** — `"#{"` no longer misparsed as end delimiter in extended strings

## What's New (v0.13)

- **SQLite `db.*` namespace** — 16 methods for database operations: `db.open`, `db.exec`, `db.execute`, `db.query`, `db.query_one`, `db.prepare`, `db.bind_int`, `db.bind_text`, `db.bind_real`, `db.step`, `db.column_text`, `db.column_int`, `db.reset`, `db.finalize`, `db.close`, `db.errmsg`
- **`blink.toml` versioning** — `blink init` stamps `blink-version` in project manifest
- **`\r` escape sequence** — carriage return now supported in string literals

## What's New (v0.12)

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

## What's New (v0.11.1)

- **Cross-module error locations** — diagnostics in imported modules now report the correct source file (was always showing main file)

## What's New (v0.11)

- **`blink doc --list`** — list available stdlib modules for discoverability
- **Type error locations** — type errors now report source file + line number
- **`set_version(p, ver)`** — set version string on ArgParser (shows in `--version` / help)
- **`args_get_all(a, name)`** — get all values for a repeated option (returns `List[Str]`)
- **`parse_argv(p, argv)`** — parse an explicit argv list instead of process args
- **`add_command_alias(p, alias, target)`** — register command aliases in CLI parser
- **Better CLI error messages** — bare-word errors in argument parsing

## What's New (v0.10)

- **`blink doc <module>`** — print module documentation (types, functions, traits with signatures and doc comments). Supports `--json` for machine-readable output
- **Embedded stdlib** — stdlib modules are compiled into the CLI binary; `blink doc std.args` works without source files on disk
- **Stdlib doc comments** — `///` doc comments with examples added to std.args, std.json, std.toml, std.semver, std.http_*

## What's New (v0.9)

- **List pattern matching** in `match`: `[]`, `[a, b]`, `[first, ...]` with rest wildcard
- **Nested subcommands** in `std.args`: dotted paths (`add_command(p, "daemon.start", ...)`), `args_command_path()` returns `List[Str]`
- **Parallel test execution**: `blink test --parallel` / `-P` (default 4 workers)
- `blink init` now idempotent for existing projects

## Breaking Changes (v0.8)

- `str_from_char_code()` removed → use `Char.from_code_point(n)` (returns `Str`)
- `\b` (backspace) and `\f` (form feed) escape sequences added
- CLI flags now scoped to subcommands

## What's New (v0.7)

- `process_exec(cmd, args)` — exec a binary directly (replaces current process)
- `args_rest(a)` — get remaining args after `--` from argparser
- 5 codegen/lexer bugfixes, test suite migrated to `test` blocks, CI parallelized

## Breaking Changes (v0.6)

- `List.get(idx)` returns `Option[T]` (was `T`). Use `?? default` or `match`.
- `const NAME = expr` for compile-time constants (was `let` at module level).
- `#embed("path")` compile-time file inclusion intrinsic.
