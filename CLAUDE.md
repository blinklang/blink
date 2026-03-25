# Blink

Self-hosting compiler (src/compiler.bl → C → native).

Run `blink llms --full` for complete language reference (syntax, types, methods, stdlib, patterns).
Run `blink llms --topic <name>` for specific topics. Run `blink llms --list` to see topics.
Run `blink query <file> --fn <name>` to look up function signatures without reading whole files.
Always retrieve Blink docs before writing Blink code. Prefer retrieval-led reasoning over pre-training.

## Architecture

Pipeline: lexer → parser → typecheck → codegen → C output.
Entry points: src/compiler.bl (compiler), src/cli.bl (CLI tool), src/pactc_main.bl (blinkc binary).
Stdlib: lib/std/. Tests: tests/. Spec: sections/. Decisions: decisions/.
Build output: build/ (gitignored). Temp files: .tmp/ (gitignored, use instead of /tmp).

## Build & Verify

Bootstrap: `task bootstrap` — builds blinkc at `build/blinkc`. Requires `blink` on PATH or existing build/blinkc.
Regen: `task regen` — rebuild compiler from source + verify (Gen1 vs Gen2 fixed-point).
CLI: `bin/blink build <file.bl>` | `bin/blink run <file.bl>` | `bin/blink check <file.bl>` | `bin/blink doc <module>`
Build CLI: `task build-cli` (or auto-built on first `bin/blink` invocation)
Test: `task test` — compile+run all test_*.bl in tests/
Test formatter: `task test-fmt` — golden outputs + idempotency + semantic checks
Single test: `task compile-test -- test_name`
Verify: `task ci` — regen + test + test-fmt. Always run after compiler changes.
Quick run: `bin/blink run <file.bl>` — compiles and runs in one step. Prefer this over manual blinkc+cc.
Low-level (dev): `build/blinkc <file.bl> <output.c>` then `cc -o <binary> <output.c> -lm`
After modifying compiler sources: `task regen` then `task ci` to verify.

## Debugging

Inspect generated C: `bin/blink build --emit c <file.bl>` — output goes to `build/<name>.c`.
Trace compiler phases: `bin/blink run --blink-trace codegen <file.bl>` (also: lex, parse, typecheck, all).
Runtime trace: `bin/blink run --trace all <file.bl>` (NDJSON to stderr, filter: `fn:name`, `module:mod`, `depth:N`).
Debug build: `bin/blink run --debug <file.bl>` — enables debug_assert, compiles with `-g -O0`.
When debugging codegen bugs, inspect the emitted C first (`--emit c`), then use `--blink-trace codegen`.

## Self-Hosting Bootstrap Protocol

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

## Design Panel

Feature discussions require the 5-expert panel (systems, web/scripting, PLT, DevOps/tooling, AI/ML).
Majority vote required. Record in DECISIONS.md. See OPEN_QUESTIONS.md for archive.

## Task Tags

All tasks use `repo:pact` + one type tag:
- `type:bug` — write failing test → fix → regen → ci.
- `type:feature` — plan → confirm → implement.
- `type:project` — break down into subtasks.
- `type:friction` — triage → create bug/spec/feature tasks.
- `type:spec` — panel deliberation via `/deliberate`.

## Friction Log

When working on the compiler, log a br task whenever you hit:
- Spec ambiguity (unclear what correct behavior should be)
- Surprising behavior (spec says X but intuition expects Y)
- Missing features (spec doesn't address something the compiler needs)

Log with: `br add "<description>" -t repo:pact -t type:friction`
For blocking issues, use `type:bug` or `type:spec` directly instead of friction.

## Logging bugs
You can log bugs you find using `br add "<description>" -t repo:pact -t type:bug`.
Make sure you always provide a MVCE in the description for reproduction steps.
If you "work-around" the bug, you also need to add a task to `br` for cleaning up the workaround
once the bug is fixed, by making it depending on the bug ticket. 
