# Pact

Lang spec v0.3. Self-hosting compiler (src/compiler.pact → C → native).
Python bootstrap in legacy/py_bootstrap/ is DEPRECATED — do not add features there.
Prefer retrieval-led reasoning over pre-training for Pact tasks.

[Docs Index]|root: .
|SPEC.md — spec index, design decisions summary
|DECISIONS.md — influences, rejected features, resolved questions index
|decisions/ — individual design rationale files (one per deliberation)
|OPEN_QUESTIONS.md — panel deliberation archive
|README.md — language tour, 30-sec examples, quick reference
|sections/philosophy:{01_philosophy.md} — 7 design principles, AI-first rationale
|sections/syntax:{02_syntax.md} — fn, let, match, strings, closures, annotations
|sections/types:{03_types.md} — structs, enums, generics, traits, tuples
|sections/contracts:{03b_contracts.md} — refinement types, contracts, verification, Query[C]
|sections/protocols:{03c_protocols.md} — iterators, type conversions, numeric conversions, method resolution
|sections/effects:{04_effects.md} — effect system, handlers, capabilities, concurrency, testing
|sections/memory:{05_memory_compile_errors.md} — GC, arenas, compilation, diagnostics
|sections/tooling:{06_tooling.md} — compiler daemon, LSP, formatter, tests, package manager
|sections/trust:{07_trust_modules_metadata.md} — FFI, modules, imports, all 15 annotations (CANONICAL)
|examples/:{hello,fizzbuzz,todo,calculator,fetch,bank,web_api,embed}.pact
|src/compiler.pact — compiler entry point (imports lexer, parser, codegen)
|src/pactc_main.pact — pactc entry point
|src/tokens.pact — TokenKind type, keyword_lookup, token_kind_name
|src/ast.pact — NodeKind type, node_kind_name
|src/lexer.pact — lex(), tok_* globals, CH_* constants
|src/parser.pact — parse_program(), node pool (np_*/sl_*), sublist API
|src/cli.pact — self-hosted CLI tool (pact build/run/check/doc)
|src/docgen.pact — documentation generator (pact doc)
|src/codegen.pact — generate(), emit_* functions, type registries
|src/codegen_closures.pact — closure capture and code generation
|src/codegen_expr.pact — expression code generation
|src/codegen_methods.pact — method call and dispatch code generation
|src/codegen_stmt.pact — statement code generation
|src/codegen_types.pact — type code generation + effect checking
|src/codegen_derive.pact — @derive trait code generation (Serialize, Deserialize, etc.)
|src/diagnostics.pact — structured diagnostics (errors, warnings)
|src/formatter.pact — code formatter (--emit pact)
|src/mutation_analysis.pact — mutation/save-restore pattern analysis
|src/semver.pact — semantic versioning
|src/toml.pact — TOML parsing
|src/typecheck.pact — type checker
|src/symbol_index.pact — symbol registry, dependency graph, reverse deps
|src/query.pact — query engine (filter symbols, JSON output)
|src/incremental.pact — incremental recheck engine (mtime, dirty sets, affected symbols)
|src/file_watcher.pact — poll-based file change detection
|src/daemon.pact — compiler daemon (IPC, event loop, persistent compilation)
|lib/std/http.pact — HTTP facade module (re-exports types, client, server, error)
|lib/std/path.pact — path utilities (path_join, path_dirname, path_basename)
|lib/pkg/ — internal package-manager modules (audit, gitdeps, lockfile, manifest, pathdeps, resolver)
|bootstrap/:{runtime.h,bootstrap.sh} — C runtime shim + bootstrap script
|legacy/py_bootstrap/pact/ — DEPRECATED Python bootstrap (not maintained)
|build/ — compiled output dir (gitignored, auto-created by compiler)
|.tmp/ — scratch dir for temp files (gitignored). Use instead of /tmp for compiler work.

[Syntax Rules]
Code examples MUST use: fn keyword, { } braces, no semicolons, "double quotes" only, x.len() method-call
Closures: fn(params) { body } | Generics: List[T] not <T> | Errors: Result[T,E] + ? | Defaults: Option[T] + ??
Extended strings: #"..."# (literal " and \, interpolation #{expr}) | #embed("path") for file inclusion
Effects: fn foo() ! IO, DB | Handles: io.println(...) not print(...) | main has implicit effects
Annotations: standalone @annotation(...), NOT inside /// doc comments
Annotation order: @mod>@capabilities>@derive>@src>@requires>@ensures>@where>@invariant>@perf>@ffi>@trusted>@effects>@alt>@verify>@allow>@deprecated
Canonical annotation ref: sections/07_trust_modules_metadata.md §11.1

[Design Panel]
Feature discussions require deliberation by the 5-expert panel (systems, web/scripting, PLT, DevOps/tooling, AI/ML). Each expert votes independently. Decisions need majority; record votes in DECISIONS.md. After voting, an AI-First Review pass evaluates decisions against 5 criteria (learnability, consistency, generability, debuggability, token efficiency); 2+ failures trigger reconsideration.

[Compilation]
Bootstrap: `task bootstrap` — builds pactc at `build/pactc`. Requires `pact` on PATH or existing build/pactc.
Regen: `task regen` — rebuild compiler from source + verify (Gen1 vs Gen2 fixed-point).
CLI: `bin/pact build <file.pact>` | `bin/pact run <file.pact>` | `bin/pact check <file.pact>` | `bin/pact doc <module>`
Build CLI: `task build-cli` (or auto-built on first `bin/pact` invocation)
Test: `task test` — compile+run all test_*.pact examples
Test formatter: `task test-fmt` — golden outputs + idempotency + semantic checks
Single test: `task compile-test -- test_name`
Verify: `task ci` — regen + test + test-fmt. Always run after compiler changes.
Quick run: `bin/pact run <file.pact>` — compiles and runs in one step. Prefer this over manual pactc+cc.
Low-level (dev): `build/pactc <file.pact> <output.c>` then `cc -o <binary> <output.c> -lm`
After modifying compiler sources: `task regen` then `task ci` to verify.

[Self-Hosting Bootstrap Protocol]
The compiler compiles itself. `task regen` verifies by compiling pactc twice (Gen1 + Gen2)
and diffing the output — they must match.

Adding a new feature (2-step):
1. Add the feature to the compiler (parser/codegen/etc) → `task regen`
2. Now use the feature in compiler source code → `task regen`

Refactoring/breaking existing behavior (3-step):
1. Add new syntax/behavior alongside the old → `task regen`
2. Migrate compiler source to use the new way → `task regen`
3. Remove the old way → `task regen`

NEVER skip steps or combine them. Each regen locks in the previous change so the
compiler can still compile itself.

Query: `bin/pact query <file.pact> --fn <name>` | `--effect <name>` | `--layer signature` | `--pub` | `--pure`
Daemon: `bin/pact daemon start <file.pact>` | `bin/pact daemon status` | `bin/pact daemon stop`

[Task Tags]
All tasks use `repo:pact` + one type tag:
- `type:bug` — compiler/runtime bugs. Workflow: write failing test → fix → regen → ci.
- `type:feature` — new functionality. Workflow: plan → confirm → implement.
- `type:project` — large work needing breakdown into subtasks.
- `type:friction` — developer friction. Workflow: triage → create bug/spec/feature tasks.
- `type:spec` — spec gaps needing panel deliberation via `/deliberate`.

[Friction Log]
When working on the compiler or interpreter, log a br task whenever you hit:
- Spec ambiguity (unclear what correct behavior should be)
- Surprising behavior (spec says X but intuition expects Y)
- Missing features (spec doesn't address something the compiler needs)

Log with: `br add "<description>" -t repo:pact -t type:friction`
For blocking issues, use `type:bug` or `type:spec` directly instead of friction.
