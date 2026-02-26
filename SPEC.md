# Pact Language Specification v0.3 (Feb 2026)

7 sections by domain experts. All blocking decisions resolved (5-0 unanimous). Self-hosting compiler achieved (Pact compiles itself via C backend).

## Sections
1. [Philosophy](sections/01_philosophy.md) — 7 principles, AI-first
2. [Syntax](sections/02_syntax.md) — fn, let, match, strings, keyword args, struct defaults, annotations
3. [Types](sections/03_types.md) — structs, enums, generics, traits, tuples
3b. [Contracts](sections/03b_contracts.md) — refinement types, contracts, verification, Query[C]
3c. [Protocols](sections/03c_protocols.md) — iterators, type conversions, numeric conversions, method resolution
4. [Effects](sections/04_effects.md) — capabilities, handlers, concurrency, testing
5. [Memory/Compilation](sections/05_memory_compile_errors.md) — GC, arenas, diagnostics
6. [Tooling](sections/06_tooling.md) — compiler daemon, LSP, formatter, package mgr
7. [Trust/Modules](sections/07_trust_modules_metadata.md) — FFI, modules, 15 annotations

## Key decisions (detail in DECISIONS.md)
fn keyword|{ } braces|no semicolons|"double quotes" only|List[T] generics|keyword args (-- separator)|struct field defaults
Result[T,E]+?|Option[T]+??|no null|no exceptions|no inheritance|Query[C] injection safety
Effects ! IO,DB|fine-grained capabilities|green threads|structured concurrency|Closeable trait + with...as scoped resources
Annotations standalone|15 types|canonical order in §11.1 of section 7

## Rejected (detail in DECISIONS.md)
Ownership/lifetimes|gradual typing|null|exceptions|inheritance|implicit conversions
Operator overloading|macros|significant whitespace|multiple string delimiters|optional keyword args (caller's choice)|mixed positional+keyword at call site
Semicolons|structural typing|full dependent types|JIT|coarse effects|sigils|:= bindings|:: return|<> generics

## Open (v2+ deferrals)
Information flow tracking (taint; Query[C] covers injection for v1)|row polymorphism|higher-kinded types

## References
- [Design decisions & rationale](DECISIONS.md)
- [Panel deliberation](OPEN_QUESTIONS.md)
- [Language tour](README.md)
