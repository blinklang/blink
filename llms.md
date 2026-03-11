# Pact

> Pact is a statically-typed, effect-tracked programming language that compiles to C. Designed for AI-first development: minimal syntax, no semicolons, universal string interpolation, algebraic effects, and contracts.

Language spec v0.3. Self-hosting compiler. Targets native binaries via C codegen.

## Recent Breaking Changes (v0.16)

- **pub visibility enforcement** — enum variants, trait names, type references, and `let`/`const` bindings must be `pub` to use across modules. Existing cross-module references to non-pub items will now error.
- **`--trace` → `--pact-trace`** — compiler phase tracing flag renamed to avoid conflicts
- **`std.path` module** — `path_join`, `path_dirname`, `path_basename` moved from C builtins to `import std.path` (stdlib). Old builtin calls still work but prefer the import.
- **StringBuilder type** — new compiler-intrinsic `StringBuilder` with `new()`, `write()`, `write_char()`, `to_str()`, `len()`, `capacity()`, `clear()`, `is_empty()`
- **`--dump-ast` flag** — dump parsed AST for debugging
- **Auto-resolve deps** — `pact build/run/test/check` now auto-resolves dependencies (no manual `pact update` needed)
- **Self-bootstrap** — compiler bootstraps from PATH `pact`; no checked-in C bootstrap files
- **Quiet test output** — `pact test` is quiet by default; use `--verbose` for detail
- **Perf: O(N²) concat → StringBuilder** — lexer/formatter performance improvement
- **Bugfixes** — lockfile not loaded on second build, 3,718 compiler warnings eliminated, CT_TAGGED_ENUM leak as Void, nested list element type lost in type pool

### Prior: What's New (v0.15)

- **FFI system** — `@ffi("lib", "symbol")` annotation, `@trusted` audit marker, `Ptr[T]` type with methods (deref, addr, write, is_null, to_str, as_cstr), `ffi.scope()` resource management (alloc, cstr, take)
- **Keyword arguments** — named arguments in function calls: `fn(pos, name: val)`
- **`@allow` diagnostic suppression** — suppress specific warnings: `@allow(W0600)`
- **`@invariant` struct assertions** — struct-level invariants: `@invariant(self.balance >= 0)`
- **Vendored C cross-compilation** — compile vendored C sources with cross-compile support; SQLite3 amalgamation bundle included
- **`pact audit`** — FFI audit command: inventory @ffi calls, audit status, pointer operations
- **`pact update`** — updates dependencies, lockfile, and stamps `pact-version` in `pact.toml`
- **Native dependencies** — `pact.toml [native-dependencies]` section for linking C libraries
- **Bugfixes** — `\r` escape bootstrap, comment preservation in type/trait/impl bodies, UnaryOp type inference, TokenKind type annotations

### Prior: What's New (v0.14)

- **Unused variable warnings** — compiler emits W0600 for `let` bindings that are never read; prefix with `_` to suppress
- **Cross-compilation fix** — removed spurious libcurl link dependency that caused linker failures on non-host targets

### Prior: What's New (v0.13.3)

- **`List[List[T]]` function parameter fix** — nested list parameters now propagate inner element types correctly (`.get()` on inner list no longer produces `pact_Option_int`)

### Prior: What's New (v0.13.2)

- **Nested struct type propagation** — `List[List[Struct]]` and `Option[List[Struct]]` now correctly propagate inner struct types through `for` loops, `let` bindings, `??`, `.unwrap()`, and `match Some(x)`

### Prior: What's New (v0.13.1)

- **`List[List[T]]` codegen fix** — `.get()`, `.pop()`, `.unwrap()`, and `??` on nested lists now produce correct C types (`pact_Option_list` instead of `pact_Option_int`)
- **Extended string lexer fix** — `"#{"` no longer misparsed as end delimiter in extended strings

### Prior: What's New (v0.13)

- **SQLite `db.*` namespace** — 16 methods for database operations: `db.open`, `db.exec`, `db.execute`, `db.query`, `db.query_one`, `db.prepare`, `db.bind_int`, `db.bind_text`, `db.bind_real`, `db.step`, `db.column_text`, `db.column_int`, `db.reset`, `db.finalize`, `db.close`, `db.errmsg`
- **`pact.toml` versioning** — `pact init` stamps `pact-version` in project manifest
- **`\r` escape sequence** — carriage return now supported in string literals

### Prior: What's New (v0.12)

- **Tuple destructuring** — `let (a, b) = some_tuple` in let bindings
- **Extended strings** — `#"literal "quotes" and \backslashes"#` with `#{expr}` interpolation
- **Struct field defaults** — `type Point { x: Int = 0, y: Int = 0 }`, omit fields at construction
- **`@requires` contracts** — precondition annotations on functions
- **Nested generics** — `List[List[Int]]` and other parameterized inner types
- **`--release` flag** — optimized builds with `-O2`
- **Multi-target builds** — `bin/pact build -T linux -T macos-arm64`
- **Error catalog** — `pact explain E1234` with machine-applicable fix suggestions
- **Closure const-qualifier fix** — eliminated dozens of C compiler warnings in bootstrap
- **List[T] param fix** — struct element types now preserved through function parameters
- **`mod {}` parser error** — helpful E1015 error instead of generic parse failure

### Prior: What's New (v0.11.1)

- **Cross-module error locations** — diagnostics in imported modules now report the correct source file (was always showing main file)

### Prior: What's New (v0.11)

- **`pact doc --list`** — list available stdlib modules for discoverability
- **Type error locations** — type errors now report source file + line number
- **`set_version(p, ver)`** — set version string on ArgParser (shows in `--version` / help)
- **`args_get_all(a, name)`** — get all values for a repeated option (returns `List[Str]`)
- **`parse_argv(p, argv)`** — parse an explicit argv list instead of process args
- **`add_command_alias(p, alias, target)`** — register command aliases in CLI parser
- **Better CLI error messages** — bare-word errors in argument parsing

### Prior: What's New (v0.10)

- **`pact doc <module>`** — print module documentation (types, functions, traits with signatures and doc comments). Supports `--json` for machine-readable output
- **Embedded stdlib** — stdlib modules are compiled into the CLI binary; `pact doc std.args` works without source files on disk
- **Stdlib doc comments** — `///` doc comments with examples added to std.args, std.json, std.toml, std.semver, std.http_*

### Prior: What's New (v0.9)

- **List pattern matching** in `match`: `[]`, `[a, b]`, `[first, ...]` with rest wildcard
- **Nested subcommands** in `std.args`: dotted paths (`add_command(p, "daemon.start", ...)`), `args_command_path()` returns `List[Str]`
- **Parallel test execution**: `pact test --parallel` / `-P` (default 4 workers)
- `pact init` now idempotent for existing projects

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

`std.args` (CLI parsing), `std.http` (HTTP client/server), `std.json` (JSON), `std.path` (path utilities), `std.semver` (versions), `std.toml` (TOML).
Run `pact doc --list` to list modules, `pact doc <module>` for details.

## Docs

- [Full LLM Reference](llms-full.md): Complete self-contained language reference with all syntax, builtins, methods, and examples
- [Language Spec Index](SPEC.md): Design decisions, philosophy, detailed specification
- [Syntax & Closures](sections/02_syntax.md): fn, let, match, strings, closures, annotations
- [Types & Generics](sections/03_types.md): Structs, enums, generics, traits, tuples
- [Effects & Concurrency](sections/04_effects.md): Effect system, handlers, capabilities, async
- [Modules & FFI](sections/07_trust_modules_metadata.md): Imports, modules, all 15 annotations

## Examples

- [Hello World](examples/hello.pact): CLI args, string interpolation, effects
- [Todo App](examples/todo.pact): Structs, enums, traits, Result, pattern matching, tests
- [Calculator](examples/calculator.pact): Recursive ADTs, contracts, refinement types
- [FizzBuzz](examples/fizzbuzz.pact): Basic control flow
- [Web API](examples/web_api.pact): HTTP server with effects

## Optional

- [Tooling](sections/06_tooling.md): Compiler daemon, LSP, formatter, test framework, package manager
- [Contracts](sections/03b_contracts.md): Refinement types, @requires/@ensures, verification
- [Memory & Errors](sections/05_memory_compile_errors.md): GC, arenas, compilation, diagnostics
