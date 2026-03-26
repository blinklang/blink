# Blink

A programming language designed by AI for the age of AI-assisted development.

Blink was created through a multi-expert AI panel process — multiple AI specialists independently designed, debated, and voted on every language decision. AI made every decision, and every single lanaguage feature is chosen for reasons which are documented. The result is a language optimized for the human-AI-compiler collaboration loop: unambiguous syntax that AI generates correctly on the first try, an effect system that makes side effects visible in every signature, and a contract system where the compiler proves your code does what you said it would.

**Status:** Self-hosting compiler achieved — the Blink compiler, written in Blink, compiles itself to native binaries via C. [Read the full spec →](SPEC.md)

---

## Install

**Prerequisite:** A C compiler (`cc`, `gcc`, or `clang`) must be on your PATH.
- macOS: `xcode-select --install`
- Ubuntu/Debian: `sudo apt install build-essential`
- Fedora: `sudo dnf install gcc`
- Arch: `sudo pacman -S base-devel`

### Binary download

Download `blink` for your platform from the [latest release](https://github.com/blinklang/blink/releases/latest), then:

```sh
chmod +x blink-*
sudo mv blink-* /usr/local/bin/blink
```

### Build from source

```sh
git clone https://github.com/blinklang/blink.git
cd blink
task build    # bootstrap, compile, install to ~/.local/bin/
```

### Docker

```sh
docker run --rm -v "$PWD":/workspace ghcr.io/blinklang/blink build src/main.bl
docker run --rm -v "$PWD":/workspace ghcr.io/blinklang/blink run src/main.bl
```

---

## 30-Second Tour

### Hello World

```blink
fn main() {
    io.println("Hello, world!")
}
```

No imports. No ceremony. `main` has implicit effects.

### Variables and Strings

```blink
fn main() {
    let name = "Alice"
    let mut count = 0
    io.println("Hello, {name}!")    // every string interpolates
    count = count + 1
}
```

Immutable by default. `let mut` is an explicit opt-in. Every string supports `{expr}` — no prefix needed.

### Functions and Effects

```blink
fn add(a: Int, b: Int) -> Int {
    a + b
}

fn greet(name: Str) ! IO {
    io.println("Hello, {name}!")
}
```

Pure functions declare no effects. Functions that touch the outside world declare them with `!`. If a function says `! IO`, it can print. If it doesn't, it can't. The compiler enforces this.

### Types

```blink
// Product type (struct)
type User {
    name: Str
    email: Str
}

// Sum type (enum)
type Status {
    Active
    Banned(reason: Str)
}

// Refinement type
type Port = Int @where(self > 0 && self <= 65535)
```

One keyword for all type definitions. Refinement types let the compiler prove constraints at compile time.

### Pattern Matching

```blink
fn describe(s: Status) -> Str {
    match s {
        Active => "Active"
        Banned(reason) => "Banned: {reason}"
    }
}
```

Exhaustive. The compiler rejects missing cases.

### Error Handling

```blink
fn parse_port(s: Str) -> Result[Port, ParseError] {
    let n = s.parse_int()?           // ? propagates errors
    if n < 1 || n > 65535 {
        return Err(ParseError.OutOfRange(n))
    }
    Ok(n)
}

let port = env.var("PORT") ?? "8080"  // ?? defaults on None
```

No exceptions. No null. `Result[T, E]` for errors, `Option[T]` for absence.

### Contracts

```blink
@requires(amount > 0)
@ensures(result.is_ok() => result.unwrap().balance == old(acct.balance) + amount)
pub fn deposit(acct: Account, amount: Int) -> Result[Account, AccountError] {
    if amount <= 0 {
        return Err(AccountError.InvalidAmount)
    }
    Ok(Account { id: acct.id, owner: acct.owner, balance: acct.balance + amount })
}
```

`@requires` is a precondition. `@ensures` is a postcondition. The compiler attempts to prove them via SMT solver — proven means zero cost, disproven means compile error with counterexample, unknown means a runtime check is inserted.

### Traits

```blink
trait Display {
    fn display(self) -> Str
}

impl Display for User {
    fn display(self) -> Str {
        "{self.name} <{self.email}>"
    }
}
```

### Generics

```blink
fn first[T](items: List[T]) -> T? {
    items.get(0)
}

let users: Map[Str, List[User]] = build_index()
```

Square brackets. No angle-bracket ambiguity. `T?` is shorthand for `Option[T]`.

### Effects and Handlers

```blink
fn fetch_data(url: Str) -> Result[Str, NetError] ! Net.Connect, IO.Log {
    io.log("Fetching {url}")
    net.get(url)?.body
}

// Mock the network for testing
fn mock_net(responses: Map[Str, Str]) -> Handler[Net.Connect] {
    handler Net.Connect {
        fn request(req: Request) -> Result[Response, NetError] {
            match responses.get(req.url) {
                Some(body) => Ok(Response { status: 200, body: body, headers: Map.new() })
                None => Err(NetError.ConnectionRefused("no mock for {req.url}"))
            }
        }
    }
}

test "fetch with mock" {
    with mock_net(Map.of([("https://example.com", "ok")])) {
        let result = fetch_data("https://example.com")
        assert_eq(result.unwrap(), "ok")
    }
}
```

Effects are capabilities. Handlers provide implementations. Swap them in tests for free dependency injection — no frameworks, no interfaces, no boilerplate.

### Tests

```blink
test "deposit increases balance" {
    let acct = open_account(1, "Test")
    let result = deposit(acct, 500)
    assert(result.is_ok())
    assert_eq(result.unwrap().balance, 500)
}
```

First-class. No test framework to import. Just `test "name" { ... }`.

### Intent and Provenance

```blink
/// Move money from one account to another atomically
@src(req: "BANK-004")
@requires(amount > 0)
pub fn transfer(amount: Int, -- from: Account, to: Account) -> Result[(Account, Account), AccountError] {
    let updated_from = withdraw(from, amount)?
    let updated_to = deposit(to, amount)?
    Ok((updated_from, updated_to))
}
```

The first `///` line declares human intent — structured, versioned, queryable. `@src` links to requirements. These aren't comments. They're compiler-checked metadata.

---

## Design Principles

1. **Optimize the generate-compile-check-fix loop.** Sub-200ms incremental compilation. Structured diagnostics. One way to write everything.
2. **One way to do everything.** No style debates. One string syntax, one error model, one test runner, one formatter.
3. **Locality of reasoning.** A function's behavior is determinable from its signature, body, and imports. No action-at-a-distance.
4. **Make correctness cheap.** Types → effects → contracts → tests. Each layer catches more bugs for less effort.
5. **Effects are capabilities.** A function that doesn't declare `! Net` cannot touch the network. Period.
6. **Precise, not verbose.** Explicit at boundaries, terse within them. Every piece of information appears exactly once.
7. **Errors are the teaching signal.** Every diagnostic includes a machine-applicable fix. The language is designed so errors are unambiguously correctable.

---

## CLI Reference

```sh
# Build and execute
blink build <file>              # Compile .bl to native binary
blink build <file> --output <path>  # Custom output path
blink build <file> --debug      # Debug mode (-g -O0)
blink run <file>                # Build and execute in one step
blink check <file>              # Type-check without producing binary

# Testing
blink test                      # Discover and run all test files
blink test <file>               # Run tests in a specific file
blink test --filter <pattern>   # Filter tests by name pattern
blink test --tags <tag>         # Run tests matching tag
blink test --json               # JSON output

# Formatting
blink fmt                       # Format all .bl files recursively
blink fmt <file>                # Format a single file
blink fmt --check               # Check formatting without modifying (exit 1 if unformatted)
blink fmt --json                # JSON output

# Query (semantic code inspection)
blink query <file> --fn <name>       # Look up a specific function
blink query <file> --effect <name>   # Find functions with a specific effect
blink query <file> --pub --pure      # Public pure functions
blink query <file> --layer intent    # Function names + doc summary
blink query <file> --layer signature # Function signatures (default)
blink query <file> --layer contract  # Signatures + @requires/@ensures
blink query <file> --layer full      # Complete implementation with source
blink query <file> --module <name>   # Filter by module

# Dependencies
blink add <pkg> --path <dir>    # Add a local path dependency
blink add <pkg> --git <url>     # Add a git dependency
blink add <pkg> --git <url> --tag <tag>  # Git dep with tag
blink remove <pkg>              # Remove a dependency
blink update [<pkg>]            # Re-resolve and update lockfile

# Audit
blink audit                     # Check for capability escalations

# Daemon (persistent compilation)
blink daemon start <file>       # Start compiler daemon
blink daemon status             # Show daemon status
blink daemon stop               # Stop running daemon

# AST inspection
blink ast <file>                # Dump parsed AST as JSON

# LLM reference
blink llms                      # Print short language reference
blink llms --full               # Print full language reference
blink llms --list               # List available topics
blink llms --topic <name>       # Print a specific topic

# Global options
blink --version                 # Print version
--format json                  # Machine-readable JSON diagnostics
--json                         # JSON output (shorthand)
```

---

## Examples

See [`examples/`](examples/) for complete programs:

| File | Demonstrates |
|------|-------------|
| [`hello.bl`](examples/hello.bl) | Hello world, CLI args, string interpolation |
| [`fizzbuzz.bl`](examples/fizzbuzz.bl) | Pattern matching, control flow |
| [`todo.bl`](examples/todo.bl) | Structs, enums, traits, error handling |
| [`calculator.bl`](examples/calculator.bl) | Refinement types, contracts, recursive ADTs |
| [`fetch.bl`](examples/fetch.bl) | Effects, handlers, mock testing, DI |
| [`bank.bl`](examples/bank.bl) | Capabilities, invariants, intent annotations |
| [`web_api.bl`](examples/web_api.bl) | HTTP handlers, system boundaries, refinement types |
| [`compiler.bl`](src/compiler.bl) | Self-hosting compiler (lexer + parser + codegen) |

---

## Quick Reference

| Concept | Syntax |
|---------|--------|
| Function | `fn name(x: T) -> R { }` |
| Keyword args | `fn f(x: T, -- y: U = val)` |
| Effects | `fn name() ! IO, DB { }` |
| Let binding | `let x = 1` / `let mut x = 1` |
| Generics | `List[T]`, `Map[K, V]` |
| Option | `T?`, default with `??` |
| Result | `Result[T, E]`, propagate with `?` |
| Match | `match val { Pat => expr }` |
| Strings | `"Hello, {name}!"` |
| Visibility | `pub fn` (public) / `fn` (private) |
| Contracts | `@requires(expr)` / `@ensures(expr)` |
| Tests | `test "name" { }` |
| Handlers | `with handler { body }` |

---

- **[Getting Started](GETTING_STARTED.md)** — install Blink, write your first program, compile and run
- **[Contributing](CONTRIBUTING.md)** — work on the interpreter/compiler, run tests, project architecture
- **[Full Spec](SPEC.md)** — complete language specification

*Blink is designed for the age of AI-assisted development.*
