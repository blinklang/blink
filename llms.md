# Blink

> Blink is a statically-typed, effect-tracked programming language that compiles to C. Designed for AI-first development: minimal syntax, no semicolons, universal string interpolation, algebraic effects, and contracts.

Targets native binaries via C codegen.

## Install

**Binary** (Linux/macOS): download from [GitHub Releases](https://github.com/blinklang/blink/releases/latest) and place on PATH.

**Docker**:
```
docker pull ghcr.io/blinklang/blink:latest
docker run --rm -v "$PWD":/workspace ghcr.io/blinklang/blink run myfile.bl
```

Tags: `latest`, `0.60`, `0.60.0` (semver). Image is `debian:bookworm-slim` with `gcc`, `zig`, `blink`, and `libgc-dev`.

## Recent Changes

See `CHANGELOG.md` (also printed by `blink llms`).

Key facts:
- `fn` keyword, `{ }` braces, no semicolons, newline-separated statements
- `"double quotes"` only, universal interpolation: `"Hello, {name}!"`
- A hole must not start with `{` (E1130): write `\{` for a literal brace, `"{({ ... })}"` for a block
- Square bracket generics: `List[T]`, `Map[K, V]`, `Result[T, E]`
- Error handling: `Result[T, E]` + `?` propagation, `Option[T]` + `??` default
- Effects: `fn foo() ! IO, DB` — tracked in signatures, provided by handlers
- `io.println(...)` not `print(...)` — IO goes through effect handles
- NO `+` or `+=` on strings (E0521) — use interpolation or `.concat()`
- `mut` goes on each name in a pattern: `let (mut x, y) = pair`, `for (k, mut v) in pairs`, `Some(mut n) =>`. `let mut (x, y)` is `E0613`; `blink fix` rewrites it
- The unit type is `()`. `Void` exists only in `Ptr[Void]`
- No silent type defaults: an empty `[]`, a bare `None` or an unused `Map.new()` is `E0301`. Annotate it, or write `Map.new[K, V]()`, `Set.new[T]()`
- One empty form per type: `[]` for `List`, `Map.new()`, `Set.new()`, `Bytes.new()`, `StringBuilder.new()`. `Map()`, `Set()`, `Bytes()` and `List.new()` do not exist: each is an error (E0504 or E0505) with a fix
- `K.zed` or `K.zed(1)`, where the type has no such member and the name does not start with an uppercase letter, is E0505 (UnresolvedMethod): 'no member `zed` on type `K`', span on the member. A module path `m.nope` has the same head and span. The help names the nearest function, constant or variant. A fix is offered only when the edited site type-checks, the payload forms agree, and one candidate is nearest. A struct field gets a note: read it on a value (`p.x`). An uppercase member (`K.Zed`) stays E0547, and its help lists the type-scoped constants.
- `K.A { }` or `K.A { x: 1 }` on a unit variant is E0300 (TypeError): 'variant `A` has no payload, and the literal has braces', span on the braces, and a label in them gets no other error. The help writes `K.A`. A fix is offered only when the braces are empty and `K.A` type-checks at that place. `K.A()` is 'variant `A` takes no arguments' (E0300; it moves to E0321 with the other variant count errors), span on `()`, help only.
- Integer literals are decimal, `0x`, `0b` or `0o`; `_` goes between digits (`0xFF_00`, `1_000`); no leading zero (`0755` is `E1137`, write `0o755`). `1e5` and `1.5e-3` are `Float`; the exponent is lowercase `e` with `-` only. An integer literal must fit its type (`let x: U8 = 300` is `E0318`); a literal with no expected type, or one that meets an unsolved type variable (`id(N)`), is `Int`. `-128` and `-(128)` are one literal, so `let b: I8 = -128` is valid. A tree of only literals (`x + (2 * 3)`) takes the type of the other operand
- Type parameters are rigid in a generic body: arithmetic on `T` needs a bound (`T: Add`). Bounds are checked at the call (`E0306`). Explicit call type arguments: `f[T](x)`
- `Self` is the impl's type only in the impl body. A `Self` in an impl header (the trait, the target, their type arguments, the binders, the `where` clause) is `E0569`: write the type, `impl From[Point] for Point`. A trait header keeps `Self`
- `E0324 InstantiationCycle`: a generic fn or type that needs a larger copy of itself, for example `fn r[T](x: T, n: Int) { r[List[T]]([x], n - 1) }` or `type P[T] { Node(p: P[(T, T)]) }`. It is an error even if unused, and `n` plays no part. Repair with a recursive type: `type Nest[T] { One(v: T), Many(items: List[Nest[T]]) }`
- An alias whose expansion reaches itself (`type A = A`, `type L = List[L]`, `type F = fn(Int) -> F`) is error E0327 CyclicTypeAlias. To make a recursive type, declare a struct: `type L { items: List[L] }`.
- `E0325 InstanceLimit`: the program needs more than 1,048,576 total weight of generic instances. An instance weighs 1 plus the nodes in its type arguments. No flag changes the limit.
- A call from a fn to itself follows the rule of any other call: `r([], n - 1)` in `fn r[T]` is `E0301`; write `r[T]([], n - 1)`.
- A method may declare its own type parameters: `fn m[U](self, ...)` in a trait, impl or default method. One instance exists per (impl binders, method binders). Brackets after a method name fill only the method's own binders: `c.m[Int]()`, `Tr.m[Int](c)`. A wrong count is E0303. An impl method repeats its trait method's binder list: same count, same position, same bounds, names may differ. A mismatch is E0906. An unfixed binder at a bare call is E0301, and the help prints the receiver. W0604 on a trait method binder fires only on a `final` default. No two type binders in scope share a name (E0326).
- Ranges: `0..n` excludes `n`, `0..=n` includes it (Kotlin's `1..n` includes the end). A bound is any expression: `for i in 0..n + 1` is `0..(n + 1)`, `lo..hi` and `xs.len()..4` are legal. No open-ended range (`0..`) and no `0..<n`; `a..b..c` is `E1141`
- `(0..3) == (0..=2)` is `false`: `==` on ranges compares start, end and kind (`..` or `..=`), not the elements. Collect both sides to compare elements: `let a: List[Int] = (0..3).into_iter().collect()`. `Range[T]` is `Eq` for every `T`, and `Debug` and `Clone` when `T` is. It has no `Hash` (E1400 as a `Map` key or `Set` element), no `Ord` and no `Display` (E0523).
- `Bytes.debug()` is `"Bytes(" + b.to_hex() + ")"`: `Bytes.from_str("hi").debug()` is `Bytes(6869)`, empty bytes are `Bytes()`. The text is the same in `@derive(Debug)` fields, in the `debug()` of a `List`, `Option` or `Map`, in traces, and in the `unwrap` and `assert_eq` message of a `Bytes` value. `debug()` never cuts its output (a trace cuts at 200 characters). The text is not source: `Bytes(6869)` is not a call and does not rebuild the value
- Keyword parameters follow `--`: `fn f(a: Int, -- b: Str = "x")`. Defaults are constants
- A default must fit every instance of a parameter type that names a type parameter: `x: T = 3` is `E0300`, `x: Option[T] = None` and `xs: List[T] = []` fit. A default never fixes `T`. `[]` is a const only as a keyword or field default
- `Map.remove` returns `Option[V]`. `m[k] = v` is an error; use `m.insert(k, v)`. `channel.new[T](buffer: n)`; `ch.recv()` returns `Option[T]`
- `Float` has a total order (`NaN == NaN`, `-0.0 == 0.0`); use `x.ieee_eq(y)` for IEEE equality. `x == -0.0` is also true for `0.0` and warns (W0706); test the sign with `x.is_sign_negative()`; test for NaN with `x.is_nan()` and for a finite value with `x.is_finite()` (`x.is_infinite()` for `Float.INF` or `-Float.INF`)
- `Float` and `F32` have built-in math methods (`x.sqrt()`, `x.ln()`, `y.atan2(x)`) and constants (`Float.PI`, `Float.INF`); there is no `math.sqrt(x)` and no `.log()`
- Random values: `rand.int(1..=6)` (a Range, never `rand.int(0, 10)`), `rand.float()` in `[0.0, 1.0)`, `rand.bytes(n)`; effect `Rand`. The default is a CSPRNG. `shuffle` and `choice` come from `import std.random.{shuffle, choice}`; `rand.shuffle(xs)` is E0505
- `@trusted(audit: "ID")` needs an audit id. `@ffi.opaque(header: "h.h", name: "c_type")` declares a C handle type; it needs both `header` and `name` (E1134), and a `blink_` or `__blink_` name is E0849. `lib/std` declares a handle to a runtime C type as `@runtime("blink_x") type T`, with no body
- `blink build`, `run` and `test` compile one C unit per module. `--no-per-module` or `BLINK_PER_MODULE=0` builds one C unit, to bisect a per-module bug
- An uncaught panic exits with code 101. That covers `panic`, `todo`, `unreachable`, a failed `assert` outside a test, and a panic the runtime raises (an index out of bounds, an overflow). Under `blink test` the runner records the panic as a failed test, and `blink test` exits 1
- Hook: `with on_panic(f)` in main's body, once, f: fn(PanicInfo) -> Never. PanicInfo { message: Str, file: Str, line: Int? }. `PanicInfo` is a type of `std.panic`: write `import std.panic.{PanicInfo}` to name it. `with on_panic(f)` and a closure hook `fn(p) {...}` need no import. A qualifier is used only in `q.y`; `panic("x")` stays the built-in after `import std.panic.{PanicInfo}`. Runs at the panic point, nothing unwinds, row charged to main. Not a catch. A panic in the hook gives the default report and exit 101. A hook elsewhere or a second hook is E0565. E0565 labels: `on_panic` is only a `with` item / outside `main` (a closure adds a note) / in a `test` block / a second `on_panic` in `main` / `with on_panic(f) as x` gives no value to bind (span `as x`, help remove `as x`). A binding named `on_panic` hides the built-in; the E0300/E0839 at the item notes the hiding binding. Under `blink test` the hook never runs; test it by calling it directly under mock_env(Map.new()) and assert_panics.
- `trace.log(channel, msg)` writes `[trace:<channel>] <msg>` to stderr when `BLINK_TRACE_CHANNELS` turns the channel on. It has no row and no handler sees it. The program reads the var once, at start: a `,` list, each item trimmed of space and tab, empty items skipped, exact case, `all` anywhere turns on every channel. `msg` is not evaluated when the channel is off. Under `--trace` it writes a `note` event in place of the line, with `channel` and `msg`, or nothing when no traced frame is on its thread; `event:note`, `fn:`, `module:` and `depth:` select it, and `effect:` and `state:` never do. `msg` is lazy and may only read state; anything else is E0566. A fn, parameter or local named `trace` hides `trace.log` in its own scope; a fn of another module does not
- `blink test` ends each test binary after a 10m timeout. `--timeout`, `--memory` and `--processes` set the limits (`30m`, `2G`, `1024`; `none` turns one off); `[test] timeout = "30m"` in blink.toml sets the timeout. A bad value exits 2 before any build

## Standard Library

`std.args` (CLI parsing), `std.db` (SQLite database with effect-based API), `std.http` (HTTP client/server), `std.json` (JSON), `std.net` (TCP networking), `std.panic` (`PanicInfo`), `std.path` (path utilities), `std.random` (`shuffle`, `choice`), `std.semver` (versions), `std.toml` (TOML).
Prelude (auto-imported): `std.str` (string ops), `std.list` (list HOFs), `std.map` (map HOFs), `std.num`, `std.sb`, `std.bytes`, `std.time`, `std.traits` (core traits).
Run `blink doc --list` to list modules, `blink doc <module>` for details.

## Docs

- [Full LLM Reference](llms-full.md): Complete self-contained language reference with all syntax, builtins, methods, and examples
- [Language Spec Index](SPEC.md): Design decisions, philosophy, detailed specification
- [Syntax & Closures](sections/02_syntax.md): fn, let, match, strings, closures, annotations
- [Types & Generics](sections/03_types.md): Structs, enums, generics, traits, tuples
- [Effects & Concurrency](sections/04_effects.md): Effect system, handlers, capabilities, async
- [Modules & FFI](sections/07_trust_modules_metadata.md): Imports, modules, all 15 annotations

## Examples

- [Hello World](examples/hello.bl): CLI args, string interpolation, effects
- [Todo App](examples/todo.bl): Structs, enums, traits, Result, pattern matching, tests
- [Calculator](examples/calculator.bl): Recursive ADTs, contracts, refinement types
- [FizzBuzz](examples/fizzbuzz.bl): Basic control flow
- [Web API](examples/web_api.bl): HTTP server with effects

## Optional

- [Tooling](sections/06_tooling.md): Compiler daemon, LSP, formatter, test framework, package manager
- [Contracts](sections/03b_contracts.md): Refinement types, @requires/@ensures, verification
- [Memory & Errors](sections/05_memory_compile_errors.md): GC, arenas, compilation, diagnostics
