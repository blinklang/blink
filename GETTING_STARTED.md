# Getting Started with Pact

Pact is a statically typed, effect-tracked language designed for correctness and clarity.
For a full language tour, see [README.md](README.md).

> **Note:** Pact is in early development. Installation methods below describe the intended experience;
> some are not yet available.

## Installation

### Package Manager (planned)

```sh
pact install
```

### Binary Download (planned)

Download a prebuilt binary from the [releases page](#) for your platform.

### Build from Source

Pact is self-hosting — the compiler is written in Pact and compiles itself. A checked-in C file provides the bootstrap:

```sh
git clone https://github.com/nhumrich/pact.git
cd pact
./bootstrap/bootstrap.sh
```

This compiles the bootstrap C file with your system's C compiler, then uses it to compile the Pact compiler source, verifying the self-compilation is stable. After bootstrap, `bin/pact` is ready to use (auto-builds the CLI on first invocation).

## Your First Program

Create a file called `hello.pact`:

```pact
fn greet(name: Str) ! IO {
    io.println("Hello, {name}!")
}

fn main() {
    let name = env.args().get(1) ?? "world"
    greet(name)
    io.println("Welcome to Pact.")
}
```

Run it:

```sh
bin/pact run hello.pact
# Hello, world!
# Welcome to Pact.
```

## Compiling

Build a native binary:

```sh
bin/pact build hello.pact
# built: build/hello

bin/pact build hello.pact --output ./hello
# built: ./hello
```

Check for errors without producing a binary:

```sh
bin/pact check hello.pact
# ok: hello.pact
```

## Running Tests

Pact supports test blocks directly in source files:

```pact
fn add(a: Int, b: Int) -> Int {
    a + b
}

test "addition" {
    assert add(1, 2) == 3
}
```

Run tests with:

```sh
pact test myfile.pact
```

## Packages

Pact projects use a `pact.toml` manifest to declare metadata and dependencies.

### Creating a Package

A package is a directory with a manifest and a `src/` folder:

```
mylib/
  pact.toml
  src/
    mylib.pact
```

The manifest declares the package name and version:

```toml
[package]
name = "mylib"
version = "0.1.0"
```

Mark public API with `pub` — only `pub` symbols are visible to consumers:

```pact
pub fn add(a: Int, b: Int) -> Int {
    a + b
}

fn internal_helper() -> Int {
    42
}
```

`pub` works on `fn`, `struct`, and `enum`. Anything without `pub` is package-private.

If you publish via git, tag your releases so consumers can pin a version: `git tag v0.1.0`.

### Using Dependencies

Add a dependency with the CLI:

```sh
pact add mylib --path ../mylib
# or from git:
pact add mylib --git https://github.com/org/mylib --tag v0.1.0
```

This updates your `pact.toml`:

```toml
[dependencies]
mylib = { path = "../mylib" }
```

Import and use the dependency:

```pact
import mylib

fn main() {
    let sum = add(2, 3)
    io.println("{sum}")
}
```

Selective imports pull in specific symbols: `import mylib.{add}`.

Build or run as usual — dependencies resolve automatically:

```sh
pact build src/main.pact
pact run src/main.pact
```

Pact generates a `pact.lock` file on first build. Commit it to version control for reproducible builds.

Other dependency commands:

```sh
pact add mylib --dev       # dev-only dependency
pact remove mylib          # remove a dependency
pact update                # re-resolve all deps
```

## Debugging & Tracing

Debug builds enable `debug_assert` and include debug symbols:

```sh
bin/pact build hello.pact --debug
bin/pact run hello.pact -d
```

Trace runtime execution with structured NDJSON output to stderr:

```sh
# Trace all function calls, effects, and state mutations
bin/pact run hello.pact --trace all

# Filter by function or module
bin/pact run hello.pact --trace "fn:main"
bin/pact run hello.pact --trace "module:parser,depth:2"

# Trace only specific event types
bin/pact run hello.pact --trace "event:effect"       # IO/FS/DB operations
bin/pact run hello.pact --trace "event:state"        # variable mutations

# Filter by effect type or variable name
bin/pact run hello.pact --trace "effect:FS.Write"
bin/pact run hello.pact --trace "state:count"

# Cap output to avoid runaway traces
bin/pact run hello.pact --trace all --trace-limit 100
```

Trace can also be enabled via environment variables: `PACT_TRACE=all` and `PACT_TRACE_LIMIT=100`.

Inspect the parsed AST:

```sh
bin/pact ast hello.pact              # JSON AST dump
bin/pact ast hello.pact --imports    # with resolved imports
```

## Next Steps

- [README.md](README.md) — language tour and quick reference
- [SPEC.md](SPEC.md) — full language specification
- [examples/](examples/) — working example programs
- [sections/](sections/) — detailed spec sections (types, effects, contracts, etc.)
- [Package management spec](sections/06_tooling.md) — dependency resolution, version constraints, lockfile format
