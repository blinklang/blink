# Getting Started with Blink

Blink is a statically typed, effect-tracked language designed for correctness and clarity.
For a full language tour, see [README.md](README.md).

> **Note:** Blink is in early development. Installation methods below describe the intended experience;
> some are not yet available.

## Installation

### Package Manager (planned)

```sh
blink install
```

### Binary Download (planned)

Download a prebuilt binary from the [releases page](#) for your platform.

### Build from Source

Blink is self-hosting — the compiler is written in Blink and compiles itself. A checked-in C file provides the bootstrap:

```sh
git clone https://github.com/blinklang/blink.git
cd blink
./bootstrap/bootstrap.sh
```

This compiles the bootstrap C file with your system's C compiler, then uses it to compile the Blink compiler source, verifying the self-compilation is stable. After bootstrap, `bin/blink` is ready to use (auto-builds the CLI on first invocation).

## Your First Program

Create a file called `hello.bl`:

```blink
fn greet(name: Str) ! IO {
    io.println("Hello, {name}!")
}

fn main() {
    let name = env.args().get(1) ?? "world"
    greet(name)
    io.println("Welcome to Blink.")
}
```

Run it:

```sh
bin/blink run hello.bl
# Hello, world!
# Welcome to Blink.
```

## Compiling

Build a native binary:

```sh
bin/blink build hello.bl
# built: build/hello

bin/blink build hello.bl --output ./hello
# built: ./hello
```

Check for errors without producing a binary:

```sh
bin/blink check hello.bl
# ok: hello.bl
```

## Running Tests

Blink supports test blocks directly in source files:

```blink
fn add(a: Int, b: Int) -> Int {
    a + b
}

test "addition" {
    assert add(1, 2) == 3
}
```

Run tests with:

```sh
blink test myfile.bl
```

## Packages

Blink projects use a `blink.toml` manifest to declare metadata and dependencies.

### Creating a Package

A package is a directory with a manifest and a `src/` folder:

```
mylib/
  blink.toml
  src/
    mylib.bl
```

The manifest declares the package name and version:

```toml
[package]
name = "mylib"
version = "0.1.0"
```

Mark public API with `pub` — only `pub` symbols are visible to consumers:

```blink
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
blink add mylib --path ../mylib
# or from git:
blink add mylib --git https://github.com/org/mylib --tag v0.1.0
```

This updates your `blink.toml`:

```toml
[dependencies]
mylib = { path = "../mylib" }
```

Import and use the dependency:

```blink
import mylib

fn main() {
    let sum = add(2, 3)
    io.println("{sum}")
}
```

Selective imports pull in specific symbols: `import mylib.{add}`.

Build or run as usual — dependencies resolve automatically:

```sh
blink build src/main.bl
blink run src/main.bl
```

Blink generates a `blink.lock` file on first build. Commit it to version control for reproducible builds.

Other dependency commands:

```sh
blink add mylib --dev       # dev-only dependency
blink remove mylib          # remove a dependency
blink update                # re-resolve all deps
```

## Debugging & Tracing

Debug builds enable `debug_assert` and include debug symbols:

```sh
bin/blink build hello.bl --debug
bin/blink run hello.bl -d
```

Trace runtime execution with structured NDJSON output to stderr:

```sh
# Trace all function calls, effects, and state mutations
bin/blink run hello.bl --trace all

# Filter by function or module
bin/blink run hello.bl --trace "fn:main"
bin/blink run hello.bl --trace "module:parser,depth:2"

# Trace only specific event types
bin/blink run hello.bl --trace "event:effect"       # IO/FS/DB operations
bin/blink run hello.bl --trace "event:state"        # variable mutations

# Filter by effect type or variable name
bin/blink run hello.bl --trace "effect:FS.Write"
bin/blink run hello.bl --trace "state:count"

# Cap output to avoid runaway traces
bin/blink run hello.bl --trace all --trace-limit 100
```

Trace can also be enabled via environment variables: `BLINK_TRACE=all` and `BLINK_TRACE_LIMIT=100`.

Inspect the parsed AST:

```sh
bin/blink ast hello.bl              # JSON AST dump
bin/blink ast hello.bl --imports    # with resolved imports
```

## Next Steps

- [README.md](README.md) — language tour and quick reference
- [SPEC.md](SPEC.md) — full language specification
- [examples/](examples/) — working example programs
- [sections/](sections/) — detailed spec sections (types, effects, contracts, etc.)
- [Package management spec](sections/06_tooling.md) — dependency resolution, version constraints, lockfile format
