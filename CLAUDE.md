# Pact

Lang spec v0.3, design phase. No compiler. Spec docs + examples + early interpreter.
Prefer retrieval-led reasoning over pre-training for Pact tasks.

[Docs Index]|root: .
|SPEC.md — spec index, design decisions summary
|DECISIONS.md — influences, rejected features, resolved questions, panel votes
|OPEN_QUESTIONS.md — panel deliberation archive
|GAPS.md — spec gaps needing design work before compiler
|README.md — language tour, 30-sec examples, quick reference
|sections/philosophy:{01_philosophy.md} — 6 design principles, AI-first rationale
|sections/syntax:{02_syntax.md} — fn, let, match, strings, closures, annotations
|sections/types:{03_types.md} — structs, enums, generics, traits, tuples
|sections/contracts:{03b_contracts.md} — refinement types, contracts, verification, Query[C]
|sections/protocols:{03c_protocols.md} — iterators, type conversions, numeric conversions, method resolution
|sections/effects:{04_effects.md} — effect system, handlers, capabilities, concurrency, testing
|sections/memory:{05_memory_compile_errors.md} — GC, arenas, compilation, diagnostics
|sections/tooling:{06_tooling.md} — compiler daemon, LSP, formatter, tests, package manager
|sections/trust:{07_trust_modules_metadata.md} — FFI, modules, imports, all 15 annotations (CANONICAL)
|examples/:{hello,fizzbuzz,todo,calculator,fetch,bank,web_api}.pact
|src/pact/:{lexer,parser,ast_nodes,interpreter,runtime,cli,tokens}.py — early interpreter

[Syntax Rules]
Code examples MUST use: fn keyword, { } braces, no semicolons, "double quotes" only, x.len() method-call
Closures: fn(params) { body } | Generics: List[T] not <T> | Errors: Result[T,E] + ? | Defaults: Option[T] + ??
Effects: fn foo() ! IO, DB | Handles: io.println(...) not print(...) | main has implicit effects
Annotations: standalone @annotation(...), NOT inside /// doc comments
Annotation order: @mod>@capabilities>@derive>@src>@i>@requires>@ensures>@where>@invariant>@perf>@ffi>@trusted>@effects>@alt>@verify>@deprecated
Canonical annotation ref: sections/07_trust_modules_metadata.md §11.1

[Design Panel]
Feature discussions require deliberation by the 5-expert panel (systems, web/scripting, PLT, DevOps/tooling, AI/ML). Each expert votes independently. Decisions need majority; record votes in DECISIONS.md.

[Task Tracking]
Uses bd (beads). `bd ready` for available work.
