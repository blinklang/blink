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

Pipeline: lexer → parser → typecheck → mono → lowering to IR → C printer
Codegen layer: src/cg.bl (driver, four emit modes) over src/cg_*.bl (stages), src/mono.bl,
src/layout.bl (C shape of a tid), src/cname.bl (C symbol names), src/ir.bl (typed lowered IR)
IMPORTANT: the tid-native emitters land stage by stage. A stage that has not landed
reports ICE I0004 CodegenStageNotBuilt, so this tree cannot yet emit C. Every task that
compiles a program is therefore NOT runnable until the emitters return: `bootstrap`,
`build-cli`, `regen`, `test`, `test-fmt`, `compile-test`, `ci-release`, and everything
under Debugging below. `task ci` is the only gate that runs, and it measures the tree
with the pinned gen0
Entry points: src/compiler.bl (compiler), src/cli.bl (CLI tool), src/blinkc_main.bl (compiler binary)
Stdlib: lib/std/. Tests: tests/. Spec: sections/. Decisions: decisions/
Build output: build/ (gitignored)

## Build & Verify

Bootstrap: `task bootstrap` — builds blinkc at `build/blinkc`. Requires `blink` on PATH or existing build/blinkc + build/blink (gen0 needs both: blinkc to emit gen1.c, blink to build the stdlib archive). NOT runnable during the codegen rewrite: it self-compiles, which needs an emitter
Regen: `task regen` — rebuild compiler from source + verify (Gen1 vs Gen2 fixed-point). NOT runnable during the codegen rewrite: the tree cannot emit C until the emitters land
Adding a lib/std or lib/pkg module: just run `task regen` — the embedded registry refresh is automatic (no manual edit to src/embedded_stdlib_registry.bl)
CLI: `build/blink build <file.bl>` | `build/blink run <file.bl>` | `build/blink check <file.bl>` | `build/blink doc <module>`
Build CLI: `task build-cli` — produces `build/blink`. NOT runnable during the rewrite (depends on bootstrap). Use `task gen1`, which produces `build/gen1/bin/{blinkc,blink}`
Test: `task test` — compile+run all test_*.bl in tests/. NOT runnable during the rewrite
Test formatter: `task test-fmt` — golden outputs + idempotency + semantic checks. NOT runnable during the rewrite (depends on bootstrap); `task ci` runs the goldens under gen1
Single test: `task compile-test -- test_name`. NOT runnable during the rewrite (depends on build-cli)
Rewrite gate: `task ci` — gen0 compiles src (gen1) + corpus monotone + lint + fmt goldens + typecheck suite. Run after every change during the codegen rewrite. See docs/codegen-rewrite/harness.md
Release gate: `task ci-release` — regen + test + test-fmt + per-module invariants. Run at release points. Also not runnable until the emitters land
Corpus: `task corpus` — every tests/test_*.bl compiled+run on its own under gen1 (the current source compiled by the pinned gen0); result in build/corpus.json; `task corpus-check` gates it against scripts/corpus_baseline.json
Quick run: `build/blink run <file.bl>` — compiles and runs in one step. Prefer this over manual blinkc+cc
Low-level (dev): `build/blinkc <file.bl> <output.c>` then `cc -o <binary> <output.c> -lm`
Archive-linked (dev): `build/blinkc --link-archive build/libblink_std.h <file.bl> <out.c>` then `cc -o <bin> <out.c> -Ibuild build/libblink_std.a -lm -lgc -pthread -Wl,--gc-sections`
After modifying compiler sources: `task ci` during the rewrite; `task regen` then `task ci-release` at release points

## Debugging

IMPORTANT: every command in this section needs a compiler that can emit C, so none of them
works on this tree until the tid-native emitters land. They describe a released build.
Front-end work (lexer, parser, typecheck, mono) is still debuggable: `build/gen1/bin/blink
check <file.bl>` and the trace flags below stop before codegen.

Inspect generated C: `build/blink build --emit c <file.bl>` — output goes to `build/<name>.c`
Trace compiler phases: `build/blink run --blink-trace typecheck <file.bl>` (also: lex, parse, mono, all)
Fine-grained trace: `BLINK_TRACE_CHANNELS=<ch>[,<ch>...|all] build/blink build --emit c <file.bl>` — must
be built from `src/cli.bl` (not `src/blinkc_main.bl`); `build/blinkc` ignores this env var. Channels are
defined via `dbg_trace(channel, msg)` calls (`grep dbg_trace\( src/`) — read the call site for what a
channel means.
Runtime trace: `build/blink run --trace all <file.bl>` (NDJSON to stderr, filter: `fn:name`, `module:mod`, `depth:N`)
Debug build: `build/blink run --debug <file.bl>` — enables debug_assert, compiles with `-g -O0`

## Self-Hosting Bootstrap Protocol

The compiler compiles itself. `task regen` verifies by compiling the compiler twice (Gen1 + Gen2)
and diffing the output — they must match

IMPORTANT: this whole protocol is suspended during the codegen rewrite. `task regen` needs an
emitter and this tree has none, so a feature cannot be locked in by a regen. Add the feature,
run `task ci`, and leave the two-step and three-step dances below for when the emitters return

Adding a new feature (2-step):
1. Add the feature to the compiler (parser/codegen/etc) → `task regen`
2. Now use the feature in compiler source code → `task regen`

Refactoring/breaking existing behavior (3-step):
1. Add new syntax/behavior alongside the old → `task regen`
2. Migrate compiler source to use the new way → `task regen`
3. Remove the old way → `task regen`

NEVER skip steps or combine them. Each regen locks in the previous change so the
compiler can still compile itself

## Design Panel

Feature discussions require the 5-expert panel (systems, web/scripting, PLT, DevOps/tooling, AI/ML)
Majority vote required. Record in DECISIONS.md. See OPEN_QUESTIONS.md for archive

## Task Tags

All tasks use `repo:blink` + one type tag:
- `type:bug` - write failing test → fix → regen → ci
- `type:feature` - plan → confirm → implement
- `type:project` - break down into subtasks
- `type:friction` - triage → create bug/spec/feature tasks
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

## Tests
Name a test for what it proves, not for a `br` ticket ID. `br` is local-only, so a ticket ID
(e.g. `7xgbh6`) means nothing to another reader or to this repo as training data — the same
reason `br` IDs stay out of commit messages and source comments. 
Keep the test-to-ticket link in a `br note`, not in
the file name or the test body.
Keep every test file name unique. `blink test` writes a fixture to `build/<basename>`, so two
files with the same base name collide. 
