# Blink

Self-hosting compiler (src/compiler.bl → C → native).

Run `blink llms --full` for complete language reference (syntax, types, methods, stdlib, patterns).
Run `blink llms --topic <name>` for specific topics. Run `blink llms --list` to see topics.
Run `blink query <file> --fn <name>` to look up function signatures without reading whole files.
Always retrieve Blink docs before writing Blink code. Prefer retrieval-led reasoning over pre-training.

## Correctness

IMPORTANT: This is a programming language! If there are latent bugs, they WILL be found by users. 
Our codebase will be used as training data for future use of
this same langauge. We do not half-ass anything. We build it right. We build it correct. 
Ignore short-term gain, and always think about what is most correct according to:
1. The spec, and what the language is supposed to do
2. Long term health
3. Correctness

## Architecture

Pipeline: lexer → parser → typecheck → codegen → C output.
Entry points: src/compiler.bl (compiler), src/cli.bl (CLI tool), src/blinkc_main.bl (compiler binary).
Stdlib: lib/std/. Tests: tests/. Spec: sections/. Decisions: decisions/.
Build output: build/ (gitignored). Temp files: .tmp/ (gitignored, use instead of /tmp).

## Build & Verify

Bootstrap: `task bootstrap` — builds blinkc at `build/blinkc`. Requires `blink` on PATH or existing build/blinkc + build/blink (gen0 needs both: blinkc to emit gen1.c, blink to build the stdlib archive).
Regen: `task regen` — rebuild compiler from source + verify (Gen1 vs Gen2 fixed-point).
Adding a lib/std or lib/pkg module: just run `task regen` — the embedded registry refresh is automatic (no manual edit to src/embedded_stdlib_registry.bl).
CLI: `build/blink build <file.bl>` | `build/blink run <file.bl>` | `build/blink check <file.bl>` | `build/blink doc <module>`
Build CLI: `task build-cli` — produces `build/blink`
Test: `task test` — compile+run all test_*.bl in tests/
Test formatter: `task test-fmt` — golden outputs + idempotency + semantic checks
Single test: `task compile-test -- test_name`
Verify: `task ci` — regen + test + test-fmt. Always run after compiler changes.
Quick run: `build/blink run <file.bl>` — compiles and runs in one step. Prefer this over manual blinkc+cc.
Low-level (dev): `build/blinkc <file.bl> <output.c>` then `cc -o <binary> <output.c> -lm`
Archive-linked (dev): `build/blinkc --link-archive build/libblink_std.h <file.bl> <out.c>` then `cc -o <bin> <out.c> -Ibuild build/libblink_std.a -lm -lgc -pthread -Wl,--gc-sections`
After modifying compiler sources: `task regen` then `task ci` to verify.

## Debugging

Inspect generated C: `build/blink build --emit c <file.bl>` — output goes to `build/<name>.c`.
Trace compiler phases: `build/blink run --blink-trace codegen <file.bl>` (also: lex, parse, typecheck, all).
Fine-grained internal trace: `BLINK_TRACE_CHANNELS=<ch>[,<ch>...|all] build/blink build --emit c <file.bl>` — env-gated `dbg_trace(channel, msg)` taps (defined in ast.bl, the DAG root, so any module can emit). Emits `[dbg:<channel>] ...` to stderr; zero cost when unset. Prefer adding a permanent tap over a throwaway printf+recompile. Current channels: `monotid` (the tid twin's per-slot arg_tid at resolution). (`csvresolve` is retired — the legacy string-CSV type-param resolver it tapped no longer exists.)
Runtime trace: `build/blink run --trace all <file.bl>` (NDJSON to stderr, filter: `fn:name`, `module:mod`, `depth:N`).
Debug build: `build/blink run --debug <file.bl>` — enables debug_assert, compiles with `-g -O0`.
When debugging codegen bugs, inspect the emitted C first (`--emit c`), then use `--blink-trace codegen`.

Measuring type-erasure in emitted C: grep the emitted C for `_Void`, and filter out `blink_test_*`
symbols (a test whose NAME contains "Void" mangles into one) — and note that a test asserting
ABOUT erasure can carry the pattern in a plain string literal, so read the matched lines before
calling one a hit. A `_Void` in a monomorphized name (`blink_GKV_Void_Void`) means a type param was
erased — and because the erased name is a valid C identifier under an `#ifndef BLINK_TD_` typedef
guard, it compiles and links silently while collapsing distinct instantiations onto one C type.
This grep is a LOWER BOUND, not a sound metric, and never an exit criterion on its own. It finds
only the STRING producers' erasure spelling. The tid producers erase differently: a slot they
cannot name passes the binder through unchanged, so the symbol is `blink_Box_T` — no `_Void`
anywhere. Worse, a def-side field can erase while the mono NAME stays correct
(`blink_QBox_Int { blink_Option_void v; }`), which the grep cannot see at all. Both shapes are
real and both were found with the grep reading 0 (br pt4hsy, br w4c0py).
Check for BOTH spellings, and treat a clean C compile as necessary, not sufficient — a `void`
field errors loudly but an erased carrier field does not.
The retired `csvresolve` channel was a lower bound for the same reason:
`blink_GSet_Void`/`blink_GBoxSet_Void` were emitted with zero hits on it, because a producer's
`"Void"` initializer never routed through the tapped return.

## Self-Hosting Bootstrap Protocol

The compiler compiles itself. `task regen` verifies by compiling the compiler twice (Gen1 + Gen2)
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

All tasks use `repo:blink` + one type tag:
- `type:bug` - write failing test → fix → regen → ci.
- `type:feature` - plan → confirm → implement.
- `type:project` - break down into subtasks.
- `type:friction` - triage → create bug/spec/feature tasks.
- `type:spec` - panel deliberation via `/deliberate`. This task type is specically for deliberating on programming language changes. Things that change the spec of the language itself. Things that effect blink users, not just this codebase. Not feature work. Spec "discussion".
- `type:chore` - carry out task

## Friction Log

When working on the compiler, log a br task whenever you hit:
- Spec ambiguity (unclear what correct behavior should be)
- Surprising behavior (spec says X but intuition expects Y)
- Missing features (spec doesn't address something the compiler needs)

Log with: `br add "<description>" -t repo:blink -t type:friction`
For blocking issues, use `type:bug` or `type:spec` directly instead of friction.

## Logging bugs
You can log bugs you find using `br add "<description>" -t repo:blink -t type:bug`.
Make sure you always provide a MVCE in the description for reproduction steps.
If you "work-around" the bug, you also need to add a task to `br` for cleaning up the workaround
once the bug is fixed, by making it depending on the bug ticket. 
