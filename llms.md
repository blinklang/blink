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

Tags: `latest`, `0.39`, `0.39.0` (semver). Image is `debian:bookworm-slim` with `gcc`, `zig`, `blink`, `libgc-dev`, and `libsqlite3-dev`.

## Recent Changes

See `CHANGELOG.md` (also printed by `blink llms`).

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
