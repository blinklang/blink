# Pact

> Pact is a statically-typed, effect-tracked programming language that compiles to C. Designed for AI-first development: minimal syntax, no semicolons, universal string interpolation, algebraic effects, and contracts.

Language spec v0.3. Self-hosting compiler. Targets native binaries via C codegen.

Key facts:
- `fn` keyword, `{ }` braces, no semicolons, newline-separated statements
- `"double quotes"` only, universal interpolation: `"Hello, {name}!"`
- Square bracket generics: `List[T]`, `Map[K, V]`, `Result[T, E]`
- Error handling: `Result[T, E]` + `?` propagation, `Option[T]` + `??` default
- Effects: `fn foo() ! IO, DB` — tracked in signatures, provided by handlers
- `io.println(...)` not `print(...)` — IO goes through effect handles
- No string `+` operator — use interpolation or `.concat()`

## Docs

- [Full LLM Reference](llms-full.md): Complete self-contained language reference with all syntax, builtins, methods, and examples
- [Language Spec Index](SPEC.md): Design decisions, philosophy, detailed specification
- [Syntax & Closures](sections/02_syntax.md): fn, let, match, strings, closures, annotations
- [Types & Generics](sections/03_types.md): Structs, enums, generics, traits, tuples
- [Effects & Concurrency](sections/04_effects.md): Effect system, handlers, capabilities, async
- [Modules & FFI](sections/07_trust_modules_metadata.md): Imports, modules, all 14 annotations

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
