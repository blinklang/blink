# Contributing to Blink

How to work on the Blink interpreter and compiler.

## Prerequisites

- A C compiler (gcc or clang)

## Setup

```sh
git clone https://github.com/blinklang/blink.git
cd blink
./bootstrap/bootstrap.sh
```

This builds the compiler toolchain. The `bin/blink` wrapper auto-builds the CLI on first use.

## Project Structure

```
src/cli.bl                # CLI tool (blink build/run/check/fmt)
src/compiler.bl           # Compiler core (import resolution, module merging)
src/blinkc_main.bl         # Standalone compiler entry point (dev/bootstrap)
src/lexer.bl              # Lexer
src/parser.bl             # Parser
src/codegen.bl            # Code generation
src/typecheck.bl          # Type checker
bootstrap/
  blinkc_bootstrap.c         # Checked-in C bootstrap seed
  runtime.h                 # C runtime header
  bootstrap.sh              # Build script
tests/                      # All test_*.bl files
```

## Compiling Programs

```sh
bin/blink build examples/hello.bl
bin/blink run examples/hello.bl
bin/blink check examples/hello.bl
```

## Updating the Bootstrap

After modifying compiler sources, regenerate and verify:

```sh
task regen    # regenerate bootstrap C from source + verify
task ci       # full CI: regen + test + test-fmt
```

## Tests

```sh
task test         # compile+run all test_*.bl in tests/
task test-fmt     # formatter golden outputs + idempotency
task ci           # full verification (regen + test + test-fmt)
```

## Architecture

```
source.bl → blink CLI (lexer → parser → typecheck → codegen) → output.c → cc → binary
```

The compiler is self-hosting and split across multiple source files. `src/cli.bl` is the user-facing CLI that embeds the full lex→parse→typecheck→codegen pipeline in-process. `src/blinkc_main.bl` is the standalone compiler entry point used for bootstrapping. The checked-in `bootstrap/blinkc_bootstrap.c` provides the initial seed.

## Spec & Design Docs

- [SPEC.md](SPEC.md) — spec index and design decisions summary
- [sections/](sections/) — detailed spec sections (philosophy, syntax, types, effects, etc.)
- [DECISIONS.md](DECISIONS.md) — influences, rejected features, resolved questions
- [OPEN_QUESTIONS.md](OPEN_QUESTIONS.md) — panel deliberation archive
- Use GitHub Issues for bug reports and feature requests
