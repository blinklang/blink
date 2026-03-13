# Contributing to Pact

How to work on the Pact interpreter and compiler.

## Prerequisites

- A C compiler (gcc or clang)

## Setup

```sh
git clone https://github.com/nhumrich/pact.git
cd pact
./bootstrap/bootstrap.sh
```

This builds the compiler toolchain. The `bin/pact` wrapper auto-builds the CLI on first use.

## Project Structure

```
src/cli.pact                # CLI tool (pact build/run/check/fmt)
src/compiler.pact           # Compiler core (import resolution, module merging)
src/pactc_main.pact         # Standalone compiler entry point (dev/bootstrap)
src/lexer.pact              # Lexer
src/parser.pact             # Parser
src/codegen.pact            # Code generation
src/typecheck.pact          # Type checker
bootstrap/
  pactc_bootstrap.c         # Checked-in C bootstrap seed
  runtime.h                 # C runtime header
  bootstrap.sh              # Build script
tests/                      # All test_*.pact files
```

## Compiling Programs

```sh
bin/pact build examples/hello.pact
bin/pact run examples/hello.pact
bin/pact check examples/hello.pact
```

## Updating the Bootstrap

After modifying compiler sources, regenerate and verify:

```sh
task regen    # regenerate bootstrap C from source + verify
task ci       # full CI: regen + test + test-fmt
```

## Tests

```sh
task test         # compile+run all test_*.pact in tests/
task test-fmt     # formatter golden outputs + idempotency
task ci           # full verification (regen + test + test-fmt)
```

## Architecture

```
source.pact → pact CLI (lexer → parser → typecheck → codegen) → output.c → cc → binary
```

The compiler is self-hosting and split across multiple source files. `src/cli.pact` is the user-facing CLI that embeds the full lex→parse→typecheck→codegen pipeline in-process. `src/pactc_main.pact` is the standalone compiler entry point used for bootstrapping. The checked-in `bootstrap/pactc_bootstrap.c` provides the initial seed.

## Spec & Design Docs

- [SPEC.md](SPEC.md) — spec index and design decisions summary
- [sections/](sections/) — detailed spec sections (philosophy, syntax, types, effects, etc.)
- [DECISIONS.md](DECISIONS.md) — influences, rejected features, resolved questions
- [OPEN_QUESTIONS.md](OPEN_QUESTIONS.md) — panel deliberation archive
- Use GitHub Issues for bug reports and feature requests
