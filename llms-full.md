# Blink Language Reference

> Blink is a statically-typed, effect-tracked language compiling to C. **Compiler v0.58.0**.

## Install

**Binary** (Linux/macOS): download from [GitHub Releases](https://github.com/blinklang/blink/releases/latest) and place on PATH.

**Docker**:
```
docker pull ghcr.io/blinklang/blink:latest
docker run --rm -v "$PWD":/workspace ghcr.io/blinklang/blink run myfile.bl
```

Tags: `latest`, `0.58`, `0.58.0` (semver). Image is `debian:bookworm-slim` with `gcc`, `zig`, `blink`, and `libgc-dev`.

## Recent Changes

See `CHANGELOG.md` (also printed by `blink llms --full`).

**CRITICAL — Read before writing any Blink code:**
- `fn` keyword, `{ }` braces, NO semicolons — newlines separate statements
- `"double quotes"` ONLY — no single quotes for strings
- Universal string interpolation: `"Hello, {name}!"` — every string supports `{expr}`
- `io.println(...)` NOT `print(...)` — IO goes through effect handles
- NO `+` or `+=` on strings (E0521) — use interpolation `"{a}{b}"` or `.concat()`
- Square bracket generics: `List[T]` NOT `List<T>`
- Method calls always: `x.len()` NOT `x.len` (no properties)
- `main` has implicit effects — no annotation needed on `fn main()`

## FFI (Foreign Function Interface)

Blink can call C functions via the `@ffi` annotation and `Ptr[T]` type.

### @ffi Annotation

```blink
@ffi("sqlite3", "sqlite3_open")
fn sqlite3_open(filename: Ptr[Int], db: Ptr[Ptr[Int]]) -> Int ! FFI
```

`@ffi("library", "symbol")` — first arg is library name, second is C symbol name.

### @trusted Audit Marker

```blink
@trusted(audit: "SEC-101")
@ffi("c", "malloc")
fn malloc(size: Int) -> Ptr[Int] ! FFI
```

`@trusted(audit: "ID")` marks an FFI function as audited for safety. The `audit:` text is required: a bare `@trusted` or an empty `audit:` is `E0836`. The text is free-form (a ticket or review ID). `@allow` and `[lints]` cannot name an audit-gated diagnostic (`W0800`, `W0310`); this is `E0837`. Write `@trusted(audit: ...)` on the function instead. A `@trusted` fn, as an `@ffi` fn, may name `Ptr[T]`, or an `@ffi.struct` that holds a `Ptr`, in its signature; elsewhere that is `E0811`.

### Ptr[T] Type

| Method | Returns | Purpose |
|--------|---------|---------|
| `.deref()` | T | Dereference pointer. `T` is the pointee type: `Ptr[U8].deref()` is `U8` |
| `.addr()` | Int | Get raw address |
| `.write(val)` | () | Write value at pointer |
| `.is_null()` | Bool | Null check |
| `.to_str()` | Str | Convert to string (for char*) |
| `.as_cstr()` | Str | Read as C string |
| `.offset(i)` | Ptr[T] | Advance by `i * sizeof(T)` strides. Only valid for pointers from `scope.alloc_n[T](n)`; rejected (`E0813`) on a singleton `scope.alloc()`, and `E0838` when the stride is unknown |
| `.field.read()` / `.field.write(v)` | T / () | Typed field access for `Ptr[@ffi.struct T]` — lowered to direct C field reads/writes |

### ffi.scope() Resource Management

`ffi.scope()` is a `Closeable` — bind it with `with ... as` (§9.1.1). All allocations made through the scope are freed when the `with` block exits (normal return, `?` early return, or any other exit path). Binding it directly (`let s = ffi.scope()`) is rejected with **E0819**: without a block to exit, the arena would never be freed.

```blink
with ffi.scope() as scope {
    let cstr = scope.cstr("hello")          // C string copy (auto-freed)
    let buf: Ptr[U8] = scope.alloc[U8]()    // zero-initialized cell (auto-freed)
    let arr = scope.alloc_n[MyStruct](16)   // contiguous array of 16 cells, returns Ptr[MyStruct] to first
    let kept = scope.take(buf)              // transfer ownership out of scope (not freed at exit)
}
// scope frees every allocation here, at block exit
```

| Method | Signature | Description |
|--------|-----------|-------------|
| `scope.alloc[T]()` | `fn alloc[T](self) -> Ptr[T]` | Allocate one zero-initialized cell of `T`, tracked by the scope |
| `scope.alloc_n[T](n)` | `fn alloc_n[T](self, n: Int) -> Ptr[T]` | Allocate a contiguous array of `n` cells; combine with `Ptr.offset(i)` for stride-correct iteration |
| `scope.cstr(s)` | `fn cstr(self, s: Str) -> Ptr[U8]` | Scoped null-terminated C string copy |
| `scope.take(ptr)` | `fn take[T](self, ptr: Ptr[T]) -> Ptr[T]` | Transfer ownership out of the scope so it survives block exit (wrap in a `Closeable` for long-lived handles) |

A scope-allocated pointer that escapes the block without `.take()` is a compile error (E0601, reused from `Closeable`).

### @ffi.opaque (C handle type)

```blink
@ffi.opaque(header: "stdio.h", name: "FILE")
type CFile

@ffi("c", "fopen")
@trusted(audit: "SEC-103")
fn c_fopen(path: Ptr[U8], mode: Ptr[U8]) -> Option[CFile] ! FFI { }
```

`@ffi.opaque(header, name)` declares a nominal type for a C handle such as `FILE*` or `sqlite3*`. It lowers to a bare pointer. It has no deref, `==`, fields or arithmetic, and `Option[CFile]` uses `NULL` for `None`. `blink audit --ffi` lists it as `opaque-ffi-handle`. A struct literal whose head is an `@ffi.opaque` type is `E0300`.

#### Closed state for a wrapper over a C handle

A `Closeable` or `BlockHandler` wrapper over a C handle must make a second `close()` or `exit()` do nothing, and a call after close return an error. Keep the closed state behind the handle, not in a `Bool` field: values are copied, so a field flag in one copy goes stale in the others. Point the opaque type at a small C box that your shim allocates (GC memory, so it outlives the C resource). Close frees the resource and clears the box. Every shim checks the box first:

```c
typedef struct { FILE* f; } my_file;          /* f is NULL once closed */

int64_t my_file_close(my_file* b) {
    if (!b->f) return 0;                       /* second close: no-op */
    FILE* f = b->f;
    b->f = NULL;
    return fclose(f);
}
int64_t my_file_is_closed(my_file* b) { return b->f ? 0 : 1; }
```

```blink
@ffi.opaque(name: "my_file")
type File

@ffi("my_file_is_closed")
@trusted(audit: "SEC-104")
fn file_is_closed(f: File) -> Int ! FFI { }

pub fn read_line(f: File) -> Result[Str, FileError] {
    if file_is_closed(f) != 0 {
        return Err(FileError.Closed("file is closed"))
    }
    // ...
}
```

`std.db` does this: after a `Connection` closes, every `db.*` call through it returns `Err(ConnectionError("connection is closed"))`, and a `Stmt` call after `finalize()` returns `Err(ExecError("statement is finalized"))`. `std.net` does it too: after a `TcpSocket` closes, `read_bytes` and `write_bytes` return `Err(IoError("socket is closed"))` and `.fd()` returns -1.

`Ptr[T]` accepts only FFI-valid pointee types (`E0810` otherwise, also inside aliases, fields, payloads, closure and trait signatures, and nested `Ptr[Ptr[T]]`). `Bool` is not a valid pointee. A field read through a `Ptr` types only when the pointee is an `@ffi.struct`.

### @ffi.struct (C struct layout twin)

```blink
@ffi.struct(header: "sys/stat.h", name: "struct stat")
type Stat {
    st_dev: U64,
    st_ino: U64,
    st_mode: U32,
    // ...
}
```

`@ffi.struct(header, name)` declares the Blink type as the layout twin of the named C struct. Codegen emits `_Static_assert` for `sizeof` and each field's `offsetof` so a drift in field order or padding fails the C compile rather than silently corrupting memory. Fields are restricted to non-GC-managed types (`E0812` rejects `Str`, `Bytes`, `List`, `Map`, `Set`, `Result`, `Option`, traits, non-`@ffi.struct` types). Headers must be declared in `[native-dependencies].<dep>.headers` in `blink.toml`, otherwise `W0812` fires (escalates to error under `--strict-struct-layout`).

### Bytes.with_ptr (Bytes ↔ Ptr[U8] alias)

```blink
let b = Bytes.zeroed(64)
b.with_ptr(fn(p) { libc_memcpy(p, src_ptr, 64) })
```

`Bytes.with_ptr(fn(p) { ... })` is the only sanctioned path from a `Bytes` to a `Ptr[U8]`. The closure body pins the buffer and may hold statements; a parser-level no-grow check rejects mutating receiver methods that could relocate the buffer (`E0814` for `push`/`append`/`concat`/`extend`/`clear`/`truncate`/`resize`/`write_*_le/be`), and rejects passing the receiver as an argument (`E0815`). Calling `Bytes.as_ptr()` outside a `with_ptr` closure is rejected with `E0817`.

### blink shim init (third-tier FFI escape hatch)

```sh
build/blink shim init <name>
```

Scaffolds `vendor/<name>.c`, `vendor/<name>.h`, and `src/<name>.bl` with a `@trusted(audit:"TODO")` Blink wrapper around vendored C. Use this when neither `std.libc.*` nor `@ffi.struct` covers the case — varargs, signal handlers, packed structs, alignment overrides.

### Native Dependencies (blink.toml)

```toml
[native-dependencies]
sqlite3 = { vendored = "vendor/sqlite3.c" }
libcurl = { system = true }
```

SQLite is itself a registry-resolved native dep: installed binaries ship a default sidecar under `share/blink/native/sqlite3/` and link it statically only when a program imports `std.db_sqlite`. The `sqlite3 = { ... }` entry above is the override path — use it to pin your own build (`vendored`) or force the system shared library (`system`).

### blink audit

```sh
build/blink audit src/main.bl          # FFI audit report
```

Lists all `@ffi` calls, their audit status (`@trusted` or unaudited), and pointer operations.

## Syntax Quick Reference

```blink
// Variables
let x = 42                       // immutable
let mut count = 0                // mutable
let name: Str = "Alice"          // type annotation
let (a, b) = (10, 20)           // tuple destructuring
let (mut lo, hi) = (0, 9)       // mut goes on each name: only `lo` is mutable

// Functions
fn add(a: Int, b: Int) -> Int {
    a + b                        // last expression is return value
}

fn greet(name: Str, -- greeting: Str = "Hello") ! IO {   // ! declares effects
    io.println("{greeting}, {name}!")
}

// Keyword arguments: parameters after `--` must be passed by label.
// A default must be a constant, and may only follow `--`.
greet("Alice", greeting: "Hi")
greet("Bob")                     // greeting gets "Hello"

// Closures
let double = fn(x: Int) -> Int { x * 2 }
numbers.map(fn(x) { x * 2 })

// Structs
type Point { x: Float, y: Float }
let p = Point { x: 1.0, y: 2.0 }
io.println("x={p.x}")

// Struct field defaults
type Config { host: Str = "localhost", port: Int = 8080 }
let c = Config { host: "0.0.0.0" }  // port gets default 8080

// Enums (ADTs)
type Shape {
    Circle(radius: Float)
    Rect(w: Float, h: Float)
}
let s = Shape.Circle(5.0)   // an expression names the enum; only Some, None, Ok, Err are bare

// Pattern matching (expression — returns value)
let area = match s {
    Circle(r) => 3.14 * r * r
    Rect(w, h) => w * h
}

// List patterns in match
match args {
    [] => show_help()
    ["build"] => build()
    ["daemon", sub] => handle_sub(sub)
    [cmd, ..] => io.println("unknown: {cmd}")  // .. = rest wildcard (no binding)
}

// OR-patterns: every alternative binds the same names, with the same types and mut
match e {
    Click(x, y) | Touch(x, y) => io.println("at {x},{y}")
    Quit => {}
}

// mut on a binder in a match arm
match o {
    Some(mut n) => {
        n *= 2
        io.println("{n}")
    }
    None => {}
}
match p {
    Point { mut x, .. } => {
        x += 10                  // changes the binder `x` only, not `p.x`
        io.println("{x}")
    }
}

// Control flow
if x > 0 { "positive" } else { "non-positive" }  // expression
for item in list { io.println(item) }
for c in "héy" { io.println("{c}") }      // over a Str: each Unicode scalar value, as a Char
for x in some_set { io.println("{x}") }   // over a Set
for (k, v) in some_map { io.println("{k}={v}") }   // over a Map
for (name, mut score) in pts {            // only `score` is mutable
    score += 1
    io.println("{name}={score}")
}
while count < 10 { count += 1 }
loop { if done { break } }

// Error handling
fn parse(s: Str) -> Result[Int, Str] {
    if s == "" { Err("empty") } else { Ok(s.to_int()) }
}
let val = parse(input)?           // propagate error (in Result-returning fn)
let val = maybe_val ?? "default"  // unwrap Option with default

// Traits
impl Display for Point {
    fn fmt(self, sb: StringBuilder) { sb.write("({self.x}, {self.y})") }
}
let s = Point { x: 1, y: 2 }.display()   // "(1, 2)" — display() is synthesized from fmt

// Tests (built-in, no framework needed)
test "addition works" {
    assert_eq(add(2, 3), 5)
}
```

## Types

| Type | Example | Notes |
|------|---------|-------|
| Int | `42`, `-1` | 64-bit signed integer |
| Float | `3.14`, `-0.5` | 64-bit double |
| Str | `"hello"` | Immutable UTF-8 string |
| Char | `'a'`, `'\n'` | Unicode scalar value (single-quote literal) |
| Bool | `true`, `false` | Boolean |
| List[T] | `[1, 2, 3]` | Dynamic array. Empty list: `[]`; the type comes from an annotation or a later use. All elements of a list literal must have one type. |
| () | `()` | Unit type: the type of "no value". Write `-> ()`, `Result[(), E]`, `Map[Str, ()]`. `Void` is valid only inside `Ptr[...]` |
| Map[K, V] | `Map.new()` | Hash map (empty: `Map.new()`, or `Map.new[K, V]()` to write the types; not `{}`) |
| Set[T] | `Set.new()` | Hash set (empty: `Set.new()`, or `Set.new[T]()` to write the type) |
| Option[T] | `Some(v)`, `None` | Nullable value |
| Result[T, E] | `Ok(v)`, `Err(e)` | Error-or-value |
| Ordering | `Ordering.Less`, `Ordering.Equal`, `Ordering.Greater` | Result of `.cmp(other)`; prelude enum auto-imported via `std.traits`. Produced by `@derive(Ord)` and the ordering operators. |
| Bytes | `Bytes.new()` | Byte buffer |
| StringBuilder | `StringBuilder.new()` | Mutable string builder |
| Instant | `time.read()` | Point in time |
| Ptr[T] | `Ptr[Int]` | Raw pointer (FFI) |
| Duration | `Duration.ms(100)` | Time span |
| Template[C] | `"SELECT * FROM t WHERE id = {id}"` | Parameterized template string (context `C` = `DB`, etc.). Interpolated values auto-extracted as parameters. `Raw(expr)` escapes parameterization. |
| I8 / I16 / I32 | — | Sized signed integers (8/16/32-bit). C-style wrapping casts. FFI use. |
| U8 / U16 / U32 / U64 | — | Sized unsigned integers. C-style wrapping casts. FFI use. |
| Errno | `Errno { code: rc }` | Newtype over `Int`: a one-field struct (`pub type Errno { code: Int }`, `import std.errno`). The error arm of the libc `*_bytes` wrappers. Read the code with `e.code`. See **Newtypes** below. |

**One spelling per type.** Write `List[T]` for a list type and `T?` for an option type. `[T]` in a type is error `ListTypeBrackets` (E1131). `Option[T]` in a type is error `OptionTypeLongForm` (E1132). Both have a machine-applicable fix.

**One empty form per type.** An empty `List` is `[]`. An empty `Map`, `Set`, `Bytes` or `StringBuilder` is `Type.new()`. These forms do not exist: `Map()`, `Map[K, V]()`, `Set()`, `Set[T]()`, `Bytes()`, `List.new()`, `List.new[T]()`, `List()`, `StringBuilder()`. The first seven are errors (E0504 or E0505) with a fix. `List()` and `StringBuilder()` are E0504 with help that names the one empty form.

**Enums are nominally distinct from `Int`.** An enum value is not interchangeable with `Int` at `let` / argument / return positions — passing one where the other is expected is a type error. Convert explicitly with `.to_int()` / `Type.from_int(n)`. (`==` between an enum and its int still works.)

**Newtypes.** A newtype is a struct with exactly one field (`pub type Errno { code: Int }`). It is a new type, distinct from its field type, so `Result[Int, Errno]` cannot confuse the count with the errno. Build it with `Errno { code: 5 }`, read it with `e.code`. There is no implicit conversion in either direction. `type X = Int` is an alias, not a newtype. Blink has no tuple structs and no `newtype` keyword. Name the field for what it holds; use `value` when nothing better fits. JSON follows struct rules (`{"code":2}`). A variant with the name of its own enum (`type Token { Token(Str), End }`) is error E0518.

### Type Inference and Checking Rules

- **A type that nothing fixes is `E0301 CannotInferType`.** This covers an empty `[]`, a bare `None`, `Map.new()` or `Set.new()` that no use types, a `channel.new` whose element type nothing fixes, an unannotated closure parameter that no context types, `for x in []`, and a generic call whose type parameter no argument or return names. Fix it with an annotation (`let xs: List[Int] = []`) or an explicit type argument (`Map.new[Str, Int]()`, `Set.new[Int]()`, `channel.new[Int](buffer: 4)`).
- **A keyword default must fit every instance of the parameter type.** The compiler checks it once, at the declaration, with each type parameter abstract: `fn h[T](-- x: T = 3)` is `E0300` at the default, and `x: Option[T] = None` or `xs: List[T] = []` fits. An omitted argument fixes no type parameter, so `g()` with nothing else that fixes `T` is `E0301`; write `g[Int]()`. A field default on a generic type follows the same rule. `[]` is a const only as a keyword or field default; each fill builds a new list, and `const E = []` is an error.
- **Explicit type arguments at a call:** `pair[Int, Str](1, "a")`, `x.method[T]()`, `mod.f[T]()`. A wrong count is `E0307 CallSiteTypeArgs`. A bare `List` or `Map[Int]` is `E0303 TypeArgArity`.
- **A type parameter is rigid inside its generic body.** `T` is not `Int`: using it as one is `E0300` at the definition. Arithmetic on `T` needs the trait in the bound (`+` needs `Add`, `-` `Sub`, `*` `Mul`, `/` `Div`, `%` `Rem`, unary `-` `Neg`): `fn add[T: Add](a: T, b: T) -> T { a + b }`.
- **Bounds and arguments are checked at the call.** `sum("a", "b")` for `fn sum[T: Add]` is `E0306`. Arguments must agree on each type parameter: `pick(1, "a")` is `E0300`.
- **A polymorphic impl proves each supertrait under its own bounds.** `impl[T] Ord for H[T]` is `E0911` when `H[T]` is `Eq` only where `T: Eq`: write `impl[T: Eq] Ord for H[T]`. `T: Ord` also passes, because it gives `T: Eq`. The compiler adds no bound you did not write. A derived supertrait impl counts, with the bounds `@derive(Eq)` would carry.
- **A fn's tail is checked against its declared return type.** A fn with a return type whose body can end with no value (a `while`, a `for`, or a `loop` that a `break` leaves) is `E0311 MissingReturn`. An `if` with no `else` used as a value is `E0304 MissingElse`.
- **An undeclared type name is `E0507 UnknownType`.** A user type named `Tuple`, `Fn` or `Self` is `E0524 ReservedTypeName`.
- **Operators need operands they apply to.** `+ - * / %`, unary `-` and the compound forms on `Bool`, `()`, structs, `Str - Str` or opaque handles are `E0300`.
- **There is no index operator.** Any `[...]` after a value (read or write: `xs[0]`, `m["k"]`, `xs[i] = v`) is `E0313 NoIndexOperator`. Use `.get(i)` (returns `Option`), `.set(i, v)` on a `List` or `Bytes`, `.insert(k, v)` on a `Map`. A tuple field is `t.0`; `t._0` is rejected. A field that does not exist is `E0525 NoSuchField`.
- **A variant that its enum does not declare is `E0547 NoSuchVariant`**, in a pattern at any depth (`Somee(v)`, `Some(Somee(v))`, `K.Zed`) and in a qualified construction (`K.Zed`, `K.Zed(1)`, `K.Zed { .. }`). The help names the nearest variant, or lists the variants. A qualified variant of another enum, or a struct pattern of another struct, is `E0300`. An arm with a bad pattern covers nothing; when it has no guard, the match gets no `E0004`.
- **In a `match` arm pattern (and in `assert_matches`), a bare name that starts with an uppercase letter is a variant, never a binding.** `Dott =>` on a `Shape` is `E0547`; `MAX =>` or `Red =>` on an `Int` is `E0308 EnumPatternNeedsEnumScrutinee`. To bind the value, write a lowercase name. To compare with a value, write a guard: `n if n == MAX =>`. In `let`, `for` and parameters, any bare name binds.
- **A variant name starts with an uppercase letter; a function after `T.` does not.** `type Shape { circle(Float) }` is `E0555 LowercaseVariant` (also `_x` and a caseless first letter: write `Circle`). `fn Conn.New()` is `E0556 UppercaseTypeScopedFn` (write `fn Conn.new()`). So in a pattern a bare lowercase name with no payload always binds, and `zed(1)` is `E0547` on an enum. In an expression `K.Upper` is a variant or a constant (a miss on an enum is `E0547`), and `K.lower` is a function or a constant, never a variant.
- **A struct or variant literal must name each field once.** A field with no default and no `..source` is `E0315 MissingField`; a label twice is `E0316 DuplicateField`; `..source` in a variant brace literal is `E0317 VariantSpread` (copy-update is for structs only).
- **A struct or variant brace pattern gets the same label checks.** An unknown label is `E0525 NoSuchField` (the fix for a punned `yy` is `y: yy`), a label twice is `E0316 DuplicateField`, and fields left out with no `..` are `E0319 PatternMissingRest` (the fix adds `..`). `E0525` and `E0316` make a bad arm; `E0319` alone does not.
- **An integer literal must fit the type it takes, else `E0318 IntLiteralOutOfRange`** (`300 does not fit in U8 (0 to 255)`). The check uses the exact value of the written digits, so no literal wraps. A literal with no expected type is `Int`; the help offers `let big: U64 = N` when the value fits `U64`. `-` on a literal, also through parens (`-(128)`), is one literal: `let b: I8 = -128` is valid, and under an unsigned type every negative literal is `E0318`, `-0` included. Literal patterns, range bounds and `const` values get the same check. `@allow` does not turn it off.
- **In an expression, write a variant with its enum: `Color.Red`, `Shape.Circle(1.0)`, `QueryError.NotFound { msg: m }`.** A bare `Red`, `Circle(1.0)` or `NotFound { ... }` is `E0554 UnqualifiedVariant`, also with an expected type, and also for stdlib enums: `Ordering.Less`, `JsonValue.Bool(true)`. Only `Some`, `None`, `Ok` and `Err` are bare (`Option.Some(1)` is also legal). A pattern does not change: `match c { Red => ... }` finds the variant from the matched value's type.
- **A variant with a positional payload, written with no argument list, is a function value.** `xs.map(Some)` and `xs.map(Tree.Leaf)` work; `Tree.Node` of `Node(Tree, Tree)` is `fn(Tree, Tree) -> Tree` (two parameters, not a tuple), and payload labels drop. The enum's type parameters come from the expected type, as for a generic fn named as a value; when nothing fixes them it is `E0301` at the reference (`let f = Some`, or `xs.map(Ok)` with `E` unfixed): annotate, `let f: fn(Int) -> Option[Int] = Some`. A variant with named fields is not a function value (`E0300`; write `fn(r) { Shape.Circle { radius: r } }`). A variant with no payload is a value, not `fn() -> E`: write `fn() { Color.Red }`. As a value, `Ok` is only `fn(T) -> Result[T, E]`: write `fn() { Ok(()) }` for `fn() -> Result[(), E]`.
- **Two `impl` blocks that can apply to one type for one trait are `E0526 OverlappingImpls`.**
- **Two module-scope declarations of one name in one namespace are `E1016 DuplicateModuleBinding`** (values: `let`, `const`, `fn`; types: `type`, `alias`, `trait`, `effect`). A `let`, `fn` or type named `Some`, `None`, `Ok` or `Err` is also `E1016`, and so is an import entry that binds one (alias it: `import pal.{Ok as PalOk}`). A name of any other variant is free for a value or a type. A struct named like a variant of an enum in the package or the prelude is `E0518 NameCollision`, also at an import entry that binds it. A bare `Name { ... }` is only a struct literal; write `Enum.Variant { ... }` for the variant.
- **A local named `Some`, `None`, `Ok` or `Err` hides the prelude variant and warns `W1011 ShadowedVariant`.**
- **A selective import of a name that the module does not declare is `E1023 UnknownImportName`** (`import other.{x, nothre}`; also `pub import`). The compiler reports it when it reads the import, used or not, with the span on the listed name. The help names the nearest `pub` item or `pub import` name of the module, or lists the candidates. A name that the module declares without `pub` is `E1003`. The entry gets no `W0602`, and a use of the name gets no `E0504`, `E0507` or `E1006`. With one suggestion, the fix renames the listed name and every use that resolves to it; with an alias (`nothre as n`) it renames the listed name only.
- **A hole in a template literal `t"..."` whose type is not a Template value type is `E0534 TemplateHoleType`.**
- **`type`, `trait` or `effect` named like a builtin type or prelude trait shadows it and warns `W1010 ShadowedPreludeName`.** To reach the builtin, write `import blink.core.{Eq as CoreEq}`.
- **A fn declared `-> Never` must not return, else `E0311`.** `panic(msg)`, `todo()`, `unreachable()` and `skip()` have type `Never`, so they fit any expected type. `todo()` warns `W0703 TodoInCode`.
- **A statement that drops the result of `append`, `slice`, `reverse`, `sort`, `sort_by` (List) or `union` (Set) warns `W0606 DiscardedCollectionCopy`:** they return a new value and do not mutate.
- **A write through a name that is not `mut` is `E0610`.** This covers `=`, `op=` and a mutating method (`push`, `pop`, `set`, `clear`, `insert`, `remove`) on a plain `let` or on a pattern binder. Use `let mut x`, or `mut` before the binder: `Some(mut ys) => ys.push(1)`.
- **A field behind a `Ptr` is not a place.** `p.f = v` and `p.f += v` for `p: Ptr[S]` are `E0611 NotAPlace`, whatever the root is. Write `p.f.write(v)`, or `p.f.write(p.f.read() + v)`, which is a read and then a write, not one atomic step.
- **A parameter is never assigned.** `c.at = 5` or `self.n += 1` on a parameter is `E0612 ParamAssign`, with or without `mut`: the write changes only this function's copy. Copy it to a `let mut` name, or return a new value. In this release E0612 is a warning; it becomes an error in a later one.
- **`mut` goes before a name, not before a pattern.** `let mut (x, y) = pair` and `for mut (k, v) in pairs` are `E0613 MutOnPattern`; write `let (mut x, mut y) = pair`. `blink fix` makes this edit.
- **The alternatives of an OR-pattern must bind the same names, with the same types and the same `mut`** (`E0005 InconsistentPatternBindings`). `Click(mut x, y) | Touch(x, y)` is an error; write `mut x` in both.
- **`for x in <non-iterable>` is `E0302`.**
- **A value in a string interpolation must implement `Display`** (`E0523`).
- **`==`, `!=`, `assert_eq` and `assert_ne` need `Eq`**, also through `Option`, `Result`, containers and enum payloads (`E0306`, with the `@derive(Eq)` fix). `x.into()`, `T.from(x)` and `T.try_from(x)` need a matching `From`/`TryFrom` impl (`E0312`). `Int` widens to `Float` through `From[Int]`.
- **`const X = some_fn()` is `E0533`.** A const takes a constant expression.

### Sized Integer Type Methods

Conversion methods available on `I8`, `I16`, `I32`, `U8`, `U16`, `U32`, `U64`, and `Int`:

| Method | Returns | Purpose |
|--------|---------|---------|
| `.to_i8()` | I8 | Cast to 8-bit signed (wrapping) |
| `.to_i16()` | I16 | Cast to 16-bit signed (wrapping) |
| `.to_i32()` | I32 | Cast to 32-bit signed (wrapping) |
| `.to_u8()` | U8 | Cast to 8-bit unsigned (wrapping) |
| `.to_u16()` | U16 | Cast to 16-bit unsigned (wrapping) |
| `.to_u32()` | U32 | Cast to 32-bit unsigned (wrapping) |
| `.to_u64()` | U64 | Cast to 64-bit unsigned (wrapping) |
| `.to_int()` | Int | Widen to 64-bit signed `Int` |

Arithmetic on sized ints (`+`, `-`, `*`, `/`, `%`, unary `-`) **traps on
overflow**, division by zero, and signed `INT_MIN / -1`. Use the
explicit modular escape hatches when you want wrap-around (there is no `wrapping_div`, `wrapping_rem` or `wrapping_neg`):

| Method | Returns | Purpose |
|--------|---------|---------|
| `.wrapping_add(rhs)` | self type | Modular addition |
| `.wrapping_sub(rhs)` | self type | Modular subtraction |
| `.wrapping_mul(rhs)` | self type | Modular multiplication |

`Type.from(x)` and `Type.try_from(x)` cover the widening / narrowing
conversion matrix between sized ints — see the `From` / `TryFrom`
traits in `std.traits`.

No implicit promotion between sized types and `Int`. Always use `.to_int()` to widen.

`Int`, the sized ints, `Char` and `Str` have `.eq(other) -> Bool` and `.cmp(other) -> Ordering`. `Bool` has `.eq(other)`.

## Escape Sequences

| Escape | Produces |
|--------|----------|
| `\n` | newline |
| `\r` | carriage return |
| `\t` | tab |
| `\\` | literal `\` |
| `\"` | literal `"` |
| `\'` | literal `'` (in Char literals) |
| `\b` | backspace |
| `\f` | form feed |
| `\{` | literal `{` (suppresses interpolation) |
| `\}` | literal `}` |

A hole must not start with `{`, whitespace skipped: `"a {{x}} b"` and `"a { {x} } b"` are E1130 InterpDoubleBrace, in every string form. For a literal brace write `\{` or use `#"..."#`. A hole that starts with a block needs parentheses: `"{({ ... })}"`.

### Extended Strings

Extended strings `#"..."#` allow literal `"` and `\` without escaping. Use `#{expr}` for interpolation.

```blink
let raw = #"path\to\file"#              // no escaping needed
let json = #"{"key": "value"}"#         // literal quotes
let msg = #"Hello, #{name}!"#           // interpolation with #{...}
let nested = ##"contains #"inner"#"##   // depth-2 nesting
let text = #"{{x}}"#                    // a lone { is text: "{{x}}"
```

## Operators

| Op | Types | Notes |
|----|-------|-------|
| `+` `-` `*` `/` `%` | Int, Float | Arithmetic (NO `+` on Str, E0521). A `Bool` operand is rejected (`E0300`) — Blink has no truthiness, so count with `if c { 1 } else { 0 }`. |
| `==` `!=` `<` `>` `<=` `>=` | Int, Float, Str, `Instant`/`Duration`, `Bytes`, and any struct/enum with `@derive(Eq)` (for `==`/`!=`) or `@derive(Ord)` (for ordering) | Comparison. Operands are type-checked (`E0300` on mismatched/unordered types); struct/enum comparisons desugar to derived `eq`/`cmp`. |
| `&&` `\|\|` `!` | Bool | Logical |
| `?` | Result[T,E] | Propagate error — enclosing fn must return Result |
| `??` | Option[T] | Unwrap or default |
| `\|>` | Any | Pipe: `x \|> f()` = `f(x)` |
| `+=` `-=` `*=` `/=` | Int, Float | Compound assignment (mut only). NO `+=` on Str (E0521) |
| `&` `\|` `^` `~` | Int, sized ints | Bitwise AND / OR / XOR / NOT. Shifts and each of `&` `^` `\|` are separate groups: mixing two groups, or a group with `+ - * / %`, needs parentheses (`(d << 24) \| (d << 16)`, error E1127 otherwise). All bind tighter than comparison: `flags & 0x0F == 0` is `(flags & 0x0F) == 0` |
| `<<` `>>` | Int, sized ints | Shift (amount is `U32`; arithmetic on signed, logical on unsigned). Out-of-range literal shifts caught at compile time; non-literal amounts get a runtime bounds check. |

## Builtin Functions

| Function | Returns | Purpose |
|----------|---------|---------|
| `write_file(path, content)` | () | Write string to file |
| `file_exists(path)` | Int | 1 if exists, 0 if not |
| `is_dir(path)` | Int | 1 if directory |
| `path_join(a, b)` | Str | Join path components — **moved to `std.path`**, use `import std.path` |
| `path_dirname(path)` | Str | Directory part of path — **moved to `std.path`** |
| `path_basename(path)` | Str | Filename part of path — **moved to `std.path`** |
| `file_mtime(path)` | Int | Modification time (ms) |
| ~~`get_env(name)`~~ | — | **Removed in v0.35** — use `env.var(name)` |
| `shell_exec(cmd)` | Int | Run shell command, return exit code |
| `process_run(cmd, args)` | ProcessResult | Run command with args (`List[Str]`), capture stdout/stderr/exit_code |
| `process_run_with_stdin(cmd, args, input)` | ProcessResult | Like `process_run` but pipes `input` (Str) to child's stdin |
| `process_exec(cmd, args)` | () | Exec binary directly (replaces process). `args` is `List[Str]` |
| `process_spawn(cmd, args)` | Int | Fork + exec a child process; returns raw pid handle. Idiomatic API: `std.process.spawn` |
| `process_pid_wait(pid)` | ProcessResult | Block until child exits; returns its `ProcessResult` |
| `process_pid_kill(pid, sig)` | Int | Send signal to child by pid; returns 0 on success |
| `process_pid_send_signal(pid, sig)` | Int | Alias of `process_pid_kill` for the `send_signal` trait method |
| `exit(code)` | () | Exit with code |
| `panic(msg)` | Never | Abort with `msg`; never returns |
| `todo()` | Never | Mark unfinished code; panics; warns `W0703` |
| `unreachable()` | Never | Mark code that must not run; panics |
| `arg_count()` | Int | CLI argument count |
| `get_arg(idx)` | Str | CLI argument by index |
| `time_ms()` | Int | Current time in milliseconds |
| `getpid()` | Int | Process ID |
| `str_from_code_point(n)` | Str | Convert char code to 1-char string (was `str_from_char_code`) |
| `unix_socket_listen(path)` | Int | Listen on Unix domain socket; -1 on failure, and for a path longer than a socket address holds (107 bytes on Linux) |
| `unix_socket_connect(path)` | Int | Connect to Unix domain socket; -1 on failure, and for a path longer than a socket address holds |
| `unix_socket_accept(fd)` | Int | Accept incoming connection |
| `unix_socket_accept_timeout(fd, ms)` | Int | Accept with timeout (ms) |
| `unix_socket_close(fd)` | () | Close socket |
| `socket_read_line(fd)` | Str | Read one line of any length, without its newline; `""` at end of input |
| `socket_write(fd, data)` | Int | Write all of `data`; returns the bytes written, or -1 when the peer has closed or the write fails |

The `tcp_*` functions are not builtins. They live in `std.net`: `import std.net` (see Standard Library). `tcp_connect`, `tcp_listen` and `tcp_accept` return `Result[TcpSocket, NetError]` or `Result[TcpListener, NetError]`; `tcp_read_bytes` returns `Result[Bytes, NetError]`. Read a socket's fd with `.fd()` (-1 once closed); wrap an fd you own with `tcp_socket_from_fd(fd)` or `tcp_listener_from_fd(fd)`.

## Namespace Methods

```blink
// IO (effect: IO)
io.println("text")              // print + newline to stdout
io.print("text")                // print without newline
io.eprintln("error")            // print to stderr + newline
io.eprint("error")              // print to stderr, no newline
io.log("debug info")            // stderr with [LOG] prefix
io.read_line()                  // -> Option[Str]: next stdin line without \n or \r\n; Some("") blank, None at end
io.read_all()                   // -> Str: the rest of stdin
io.read_bytes(n)                // -> Bytes: exactly n bytes, fewer only at end of input; n <= 0 panics
io.write(s)                     // write string to stdout (no newline)
io.write_bytes(b)               // write Bytes to stdout
io.print_raw("text")            // raw printf (bypasses vtable)
io.eprint_raw("error")          // raw fprintf stderr (bypasses vtable)

// Filesystem (effect: FS) — the signed surface returns Result[T, FsError];
// `import std.fs` to name FsError/FsOp in a caller that handles the error.
fs.read(path)                   // -> Result[Str, FsError]
fs.write(path, content)         // -> Result[(), FsError]
fs.delete(path)                 // -> Result[(), FsError] (delete file, backed by unlink(2))
fs.list_dir(dir)                // -> Result[List[Str], FsError] (filenames)
fs.stat(path)                   // -> Result[FileInfo, FsError] (follows symlinks; FileInfo { kind: FileKind (File|Dir|Other), size: Int, mtime: Instant }; effect: FS.Read)
// FsError { op: FsOp, path: Str, errno: Errno } — the error the fs.* surface returns.
"{err}"                         // Display renders `op path: message`, e.g. `read /etc/app.toml: No such file or directory`
err.not_found()                 // -> Bool: true only when the failure was ENOENT (file not there)

// Environment (effect: Env)
env.args()                      // -> List[Str] (all CLI args)
env.var(name)                   // -> Option[Str] (read env var, effect: Env.Read)
env.cwd()                       // -> Str (current working directory, effect: Env.Read)
env.set_var(name, value)        // set env var (effect: Env.Write)
env.remove_var(name)            // remove env var (effect: Env.Write)
env.exit(code)                  // terminate process (effect: Env.Exit)

// Time
time.read()                     // -> Instant
time.sleep(duration)            // sleep for Duration

// Async (effect: Async)
async.scope { ... }             // synchronous scope for spawned tasks
async.spawn(fn() { ... })       // spawn task, returns Handle

// Channel[T]
let ch = channel.new[Int](buffer: 8)  // bounded queue; the buffer size is required
ch.send(v)                      // blocks while full; panics if ch is closed
ch.recv()                       // -> Option[T]: Some(next value), None once closed AND drained
ch.close()                      // a second close does nothing
for v in ch { ... }             // one recv() per turn; ends on the first None
let v = ch.recv() ?? 0          // handle the closed case; .unwrap() panics on it

// Database (effect: DB) — stdlib module, requires `import std.db`
// Connection: effect-handler scoped (no global state)
// The enclosing fn must return a Result whose error takes DBError (`import std.db_error.{DBError}`)
with db.connect(path)? {        // returns Result[Connection, DBError]; `?` unwraps it. Installs DB handler for scope
    // all db.* operations use this connection within scope
}
// Or with explicit imports for more control:
import std.db_sqlite.{sqlite_connect}
with sqlite_connect(path) {     // equivalent to db.connect(path)
    // all db.* operations use this connection within scope
}
// Or for handle access (transactions, prepared statements):
import std.db_sqlite.{db_connect, sqlite_handler}
with db_connect(path) as conn, sqlite_handler(conn.handle) {
    // conn.handle available for sqlite_transaction(), sqlite_prepare(), etc.
}

// Queries use Template[DB] for injection safety
// String interpolation auto-parameterizes:
let name = "Alice"
db.query("SELECT * FROM users WHERE name = {name}")?
// Compiles to: SELECT * FROM users WHERE name = ?  [params: "Alice"]
// Use Raw() to opt out: db.query("SELECT * FROM {Raw(table_name)}")?

// Queries (effect: DB.Read) — return Result[T, DBError]
db.query(tpl)                   // -> Result[List[Row], DBError] (all rows)
db.query_one(tpl)               // -> Result[Option[Row], DBError] (first row or None)

// Mutations (effect: DB.Write)
db.exec(tpl)                    // -> Result[(), DBError] (DDL/DML, no return)
db.execute(tpl)                 // -> Result[Int, DBError] (returns last insert rowid)

// Row type (named column access)
row.get("col")                  // -> Option[Str] (by column name)
row.get_int("col")              // -> Option[Int] (typed access)
row.get_str("col")              // -> Option[Str] (explicit string)
row.get_at(idx)                 // -> Option[Str] (positional fallback)
row.column_names()              // -> List[Str]

// Prepared statements (low-level, for batch operations)
db.prepare(tpl)                 // -> Result[Stmt, DBError] (Closeable — use with...as)
stmt.bind_int(idx, val)         // bind integer parameter
stmt.bind_text(idx, val)        // bind string parameter
stmt.step()                     // -> Result[StepResult, DBError]
stmt.column_int(idx)            // -> Int
stmt.column_text(idx)           // -> Str
stmt.reset()                    // reset for re-use
stmt.finalize()                 // free statement

// Transactions (effect: DB.Write) — via BlockHandler
with db.transaction() {         // scoped: auto-commit on success, auto-rollback on error
    db.exec("INSERT ...")?
}
db.begin()                      // -> Result[(), DBError] (manual)
db.commit()                     // -> Result[(), DBError]
db.rollback()                   // -> Result[(), DBError]

// DBError enum variants: QueryError, ExecError, ConnectionError, NotFound

// Net (effect: Net.Listen for listen/accept, Net.Connect for connect)
net.listen(host, port)          // -> Int (listen fd)
net.accept(fd)                  // -> Int (connection fd)
net.read(fd, max_bytes)         // -> Str (read up to max_bytes)
net.read_all(fd)                // -> Str (read all available data)
net.write(fd, data)             // -> ()
net.close(fd)                   // -> ()
net.connect(host, port)         // -> Int (connection fd)
net.set_timeout(fd, ms)         // -> () (set read timeout)
```

## String Methods

| Method | Returns | Purpose |
|--------|---------|---------|
| `.len()` | Int | Length in codepoints (O(1)) |
| `.is_empty()` | Bool | Check if empty |
| `.contains(s)` | Bool | Substring check |
| `.starts_with(s)` | Bool | Prefix check |
| `.ends_with(s)` | Bool | Suffix check |
| `.index_of(s)` | Option[Int] | Codepoint index of first match |
| `.concat(s)` | Str | Concatenate |
| `.substring(start, end)` | Str | Codepoint range `[start, end)`; clamps |
| `.split(sep)` | List[Str] | Split by separator |
| `.lines()` | List[Str] | Split at `\n` and `\r\n`; no empty last item |
| `.trim()` | Str | Strip leading and trailing whitespace |
| `.trim_right()` | Str | Strip trailing whitespace |
| `.trim_left()` | Str | Strip leading whitespace |
| `.to_upper()` | Str | Uppercase |
| `.to_lower()` | Str | Lowercase |
| `.replace(old, new)` | Str | Replace all occurrences |
| `.to_int()` | Int | Leading digits as an integer (lax) |
| `.parse_int()` | Result[Int, ConversionError] | Optional `-` then digits; `Err` on any other text or overflow |
| `.parse_float()` | Result[Float, ConversionError] | `-? DIGITS ('.' DIGITS)? ('e' '-'? DIGITS)?`, `NaN`, `inf`, `-inf`; correctly rounded |
| `.char_at(idx)` | Option[Char] | Char at codepoint index, `None` if out of range |
| `.byte_len()` | Int | Length in bytes (O(1)) |
| `.byte_at(idx)` | U8 | Raw byte at byte offset; panics when out of bounds |
| `.byte_slice(start, end)` | Str | Byte range `[start, end)`; clamps; panics inside a codepoint |
| `.byte_index_of(s, from)` | Option[Int] | Byte offset of first match at or after `from` |
| `.eq(other)` / `.cmp(other)` | Bool / Ordering | Equality and byte order |
| `.into_iter()` | Iterator[Char] | Lazy iterator over the chars |

## Char Methods

`Char` is a Unicode scalar value. Literal: `'a'`, `'\n'`, `'\t'`, `'\\'`, `'\''`.

| Method | Returns | Purpose |
|--------|---------|---------|
| `.to_int()` | Int | Unicode code point as integer |
| `.to_str()` | Str | Single-character string |
| `.eq(other)` / `.cmp(other)` | Bool / Ordering | Equality and order by code point |

**Construction:**
```blink
let c: Char = 'a'
let result = Char.from_code_point(65)   // -> Result[Char, ConversionError]
let result2 = Char.try_from(65)         // -> Result[Char, ConversionError] (TryFrom[Int] trait impl)
let s = str_from_code_point(65)         // -> Str ("A"), from std.str
```

## List[T] Methods

| Method | Returns | Purpose |
|--------|---------|---------|
| `[]` | List[T] | Create an empty list; T comes from the annotation or a later use |
| `List.with_capacity(n)` | List[T] | Create an empty list with room for at least n elements; T as for `[]`, or write `List.with_capacity[T](n)`. n <= 0 is the same as `[]` |
| `.len()` | Int | Length |
| `.capacity()` | Int | Elements the list holds before it grows; always >= `.len()` |
| `.is_empty()` | Bool | Check if empty |
| `.push(item)` | () | Append (mutates) |
| `.pop()` | Option[T] | Remove last |
| `.get(idx)` | Option[T] | Element at index (None if OOB) |
| `.last()` | Option[T] | Last element (None if empty) |
| `.index_of(v)` | Option[Int] | Index of first element `== v`; needs `T: Eq` |
| `.set(idx, val)` | () | Set element (mutates) |
| `.insert(idx, val)` | () | Insert at idx, shift the rest right (mutates); idx == len appends, idx outside 0..=len panics |
| `.remove(idx)` | T | Remove and return the element at idx, shift the rest left (mutates); idx outside 0..len panics |
| `.contains(elem)` | Bool | Membership check by `==`; needs `T: Eq` |
| `.append(other)` | List[T] | Concatenate, returns a new list |
| `.slice(start, end)` | List[T] | Sub-list |
| `.join(sep)` | Str | Join as string (List[Str]) |
| `.map(fn(T)->U)` | List[U] | Transform each |
| `.filter(fn(T)->Bool)` | List[T] | Keep matching |
| `.fold(init, fn(A,T)->A)` | A | Reduce |
| `.find(fn(T)->Bool)` | Option[T] | First match |
| `.any(fn(T)->Bool)` | Bool | Any match? |
| `.all(fn(T)->Bool)` | Bool | All match? |
| `.count()` | Int | Count elements |
| `.for_each(fn(T)->())` | () | Apply to each element |
| `.chain(other)` | List[T] | Concatenate, returns a new list (eager) |
| `.flat_map(fn(T)->List[U])` | List[U] | Map then flatten (eager) |
| `.zip(other)` | List[(T,U)] | Pair elements (eager, list of tuples) |
| `.enumerate()` | List[(Int,T)] | Index each element (eager, list of tuples) |
| `.take(n)` | List[T] | First n (eager) |
| `.skip(n)` | List[T] | All but first n (eager) |
| `.sort()` | List[T] | Stable sorted copy; receiver unchanged; needs `T: Ord` |
| `.sort_by(fn(T,T)->Ordering)` | List[T] | Stable sorted copy; receiver unchanged |
| `.clear()` | () | Remove all elements (mutates); does not lower `.capacity()` |

Use `List.with_capacity(n)` only when the final size is known. `.capacity()` is for tests and diagnostics; do not branch on it.

## Iterator[T] (Lazy)

Blink has two iteration worlds. Collections (`List`, `Set`, `Map`, `Range`, `Str`) are **eager** — an adapter like `list.map(f)` runs now and returns a new collection. `Iterator[T]` is the **lazy** world — a single-pass recipe that touches no elements until a consuming method or a `for` loop pulls from it.

`.into_iter()` is the one door into the lazy world; `.collect()` is the one door back to a `List`. There is no implicit conversion in either direction, so the boundary is always visible in source. `.collect()` is an iterator method only — a collection is already collected, so `list.collect()` is a compile error (`E0505`).

```blink
let first_two = names
    .into_iter()                       // cross into the lazy world
    .filter(fn(n) { n.len() > 3 })
    .take(2)
    .collect()                         // cross back — first_two : List[Str]
```

| Method | Returns | Purpose |
|--------|---------|---------|
| `.map(fn(T)->U)` | Iterator[U] | Transform each (lazy) |
| `.filter(fn(T)->Bool)` | Iterator[T] | Keep matching (lazy) |
| `.flat_map(fn(T)->Iterator[U])` | Iterator[U] | Map then flatten (lazy) |
| `.take(n)` | Iterator[T] | First n (lazy) |
| `.skip(n)` | Iterator[T] | Skip first n (lazy) |
| `.zip(other)` | Iterator[(T,U)] | Pair with another iterator (lazy) |
| `.enumerate()` | Iterator[(Int,T)] | Index each element (lazy) |
| `.chain(other)` | Iterator[T] | Concatenate iterators (lazy) |
| `.collect()` | List[T] | Drain into a List (door back) |
| `.fold(init, fn(A,T)->A)` | A | Reduce (drains) |
| `.count()` | Int | Count elements (drains) |
| `.any(fn(T)->Bool)` | Bool | Any match? (drains) |
| `.all(fn(T)->Bool)` | Bool | All match? (drains) |
| `.find(fn(T)->Bool)` | Option[T] | First match (drains) |
| `.for_each(fn(T))` | () | Apply to each (drains) |

`Iterator[T]` is a sealed, opaque built-in: it is not user-implementable, exactly as `Str` and `List` are closed. It is a restartable recipe, not a stateful cursor — collecting it twice recomputes from the source.

## Map[K, V] Methods

`K` may be `Str`, `Int`, `Bool`, `Char`, any sized-int (`I8`..`U64`), a tuple of hashable types, or a user `struct`/`enum` with `@derive(Hash, Eq)`. `Float`/`F32`/`F64` keys and user types without `@derive(Hash, Eq)` are rejected with `E1400 MapKeyNotHashable`. Tuples auto-derive `Hash`/`Eq` structurally.

| Method | Returns | Purpose |
|--------|---------|---------|
| `Map.new()` / `Map.new[K, V]()` | Map[K,V] | Create empty map (NOT `{}`). Index assignment `m[k] = v` is an error; use `insert` |
| `.insert(key, val)` | () | Insert/update (method form) |
| `.get(key)` | Option[V] | Safe lookup — pattern-match `Some(v)` / `None` |
| `.contains_key(key)` | Bool | Key exists? |
| `.contains(key)` | Bool | Key exists? (alias of `contains_key`) |
| `.remove(key)` | Option[V] | Remove key, returns the old value, or `None` if absent |
| `.len()` | Int | Entry count |
| `.keys()` | List[K] | All keys |
| `.values()` | List[V] | All values |
| `.entries()` | List[(K,V)] | All (key, value) pairs, in the order `for (k, v) in m` gives |
| `.clear()` | () | Remove all entries (mutates) |

## Set[T] Methods

| Method | Returns | Purpose |
|--------|---------|---------|
| `Set.new()` / `Set.new[T]()` | Set[T] | Create empty set |
| `.insert(elem)` | Bool | Add element to set |
| `.remove(elem)` | Bool | Remove element from set |
| `.contains(elem)` | Bool | Membership check |
| `.len()` | Int | Number of elements |
| `.is_empty()` | Bool | Check if empty |
| `.union(other)` | Set[T] | Union of two sets |

## Bytes Methods

| Method | Returns | Purpose |
|--------|---------|---------|
| `Bytes.new()` | Bytes | Create empty byte buffer |
| `Bytes.zeroed(n)` | Bytes | Create zero-filled buffer of length `n` |
| `Bytes.from_str(s)` | Bytes | Create from string |
| `.push(byte)` | () | Append byte (mutates) |
| `.get(idx)` | Option[Int] | Byte at index |
| `.set(idx, byte)` | () | Set byte (mutates) |
| `.len()` | Int | Length |
| `.is_empty()` | Bool | Check if empty |
| `.slice(start, end)` | Bytes | Sub-buffer |
| `.concat(other)` | Bytes | Concatenate |
| `.to_str()` | Result[Str, Str] | Convert to UTF-8 string; Err on bad UTF-8 or a NUL byte |
| `.to_hex()` | Str | Hex encoding |
| `.read_u16_be(offset)` | Result[Int, Str] | Read unsigned 16-bit big-endian at offset |
| `.read_u16_le(offset)` | Result[Int, Str] | Read unsigned 16-bit little-endian at offset |
| `.read_u32_be(offset)` | Result[Int, Str] | Read unsigned 32-bit big-endian at offset |
| `.read_u32_le(offset)` | Result[Int, Str] | Read unsigned 32-bit little-endian at offset |
| `.read_i32_be(offset)` | Result[Int, Str] | Read signed 32-bit big-endian at offset |
| `.read_i32_le(offset)` | Result[Int, Str] | Read signed 32-bit little-endian at offset |
| `.read_i64_be(offset)` | Result[Int, Str] | Read signed 64-bit big-endian at offset |
| `.read_i64_le(offset)` | Result[Int, Str] | Read signed 64-bit little-endian at offset |
| `.write_u16_be(val)` | () | Append unsigned 16-bit big-endian (grows buffer) |
| `.write_u16_le(val)` | () | Append unsigned 16-bit little-endian (grows buffer) |
| `.write_u32_be(val)` | () | Append unsigned 32-bit big-endian (grows buffer) |
| `.write_u32_le(val)` | () | Append unsigned 32-bit little-endian (grows buffer) |
| `.write_i32_be(val)` | () | Append signed 32-bit big-endian (grows buffer) |
| `.write_i32_le(val)` | () | Append signed 32-bit little-endian (grows buffer) |
| `.write_i64_be(val)` | () | Append signed 64-bit big-endian (grows buffer) |
| `.write_i64_le(val)` | () | Append signed 64-bit little-endian (grows buffer) |
| `.set_u16_be(off, v)` | Result[(), Str] | In-place write unsigned 16-bit big-endian at offset (no growth, bounds-checked) |
| `.set_u16_le(off, v)` | Result[(), Str] | In-place write unsigned 16-bit little-endian at offset |
| `.set_i16_be(off, v)` | Result[(), Str] | In-place write signed 16-bit big-endian at offset |
| `.set_i16_le(off, v)` | Result[(), Str] | In-place write signed 16-bit little-endian at offset |
| `.set_u32_be(off, v)` | Result[(), Str] | In-place write unsigned 32-bit big-endian at offset |
| `.set_u32_le(off, v)` | Result[(), Str] | In-place write unsigned 32-bit little-endian at offset |
| `.set_i32_be(off, v)` | Result[(), Str] | In-place write signed 32-bit big-endian at offset |
| `.set_i32_le(off, v)` | Result[(), Str] | In-place write signed 32-bit little-endian at offset |
| `.set_u64_be(off, v)` | Result[(), Str] | In-place write unsigned 64-bit big-endian at offset |
| `.set_u64_le(off, v)` | Result[(), Str] | In-place write unsigned 64-bit little-endian at offset |
| `.set_i64_be(off, v)` | Result[(), Str] | In-place write signed 64-bit big-endian at offset |
| `.set_i64_le(off, v)` | Result[(), Str] | In-place write signed 64-bit little-endian at offset |
| `.with_ptr(fn(p) { ... })` | T | Pin buffer and call closure with `Ptr[U8]` (FFI alias path; no growth allowed inside) |

## StringBuilder Methods

| Method | Returns | Purpose |
|--------|---------|---------|
| `StringBuilder.new()` | StringBuilder | Create empty builder |
| `StringBuilder.with_capacity(n)` | StringBuilder | Create with pre-allocated capacity |
| `.write(s)` | () | Append string |
| `.write_char(ch)` | () | Append one `Char` |
| `.to_str()` | Str | Build final string |
| `.len()` | Int | Current length |
| `.capacity()` | Int | Allocated capacity |
| `.clear()` | () | Reset to empty |
| `.is_empty()` | Bool | Check if empty |

## Float Methods

| Method | Returns | Purpose |
|--------|---------|---------|
| `.eq(other)` / `.cmp(other)` | Bool / Ordering | Total order, as `==` and `<` below |
| `.ieee_eq(other)` | Bool | IEEE 754 equality: `NaN.ieee_eq(NaN)` is `false`, `0.0.ieee_eq(-0.0)` is `true` |
| `.is_nan()` | Bool | NaN check (needs `import std.float`) |
| `.truncate()` | Int | Drop the fraction |
| `.to_int_checked()` | Result | Float to Int; fails out of range |
| `.to_bits()` | U64 | IEEE 754 bit pattern (`F32`: `U32`); not a conversion |
| `Float.from_bits(b)` | Float | Value with bit pattern `b: U64` (`F32.from_bits(U32)`); every pattern is valid, NaN payloads are kept |
| `.is_sign_negative()` | Bool | The sign bit: `true` for `-0.0` and for a NaN with the sign bit set |

`Float` has a total order: `==`, `<` and sort treat `NaN` as equal to itself and above all numbers, and `-0.0` as equal to `0.0`. Use `ieee_eq` for IEEE comparison. No `Float` equality tells `-0.0` from `0.0`; to test the sign, use `x.is_sign_negative()`. A comparison with a written `-0.0` operand (`x == -0.0`, `x < -0.0`, `x.ieee_eq(-0.0)`, `assert_eq(x, -0.0)`) gives the same result for `0.0` and warns `NegativeZeroComparison` (W0706). To test for negative zero, use `x == 0.0 && x.is_sign_negative()`. Equal bits imply `==`, but `==` does not imply equal bits. `to_bits`, `from_bits` and `is_sign_negative` need no import.

## Option[T] Methods

| Method | Returns | Purpose |
|--------|---------|---------|
| `.is_some()` | Bool | Has value? |
| `.is_none()` | Bool | Empty? |
| `.unwrap()` | T | Extract value (panics on None) |
| `.map(fn(T) -> U ! _)` | U? | `Some(f(x))` for `Some(x)`, else `None`. The callback effects pass to the caller |
| `.ok_or(e)` | Result[T, E] | `Ok(x)` for `Some(x)`, else `Err(e)` |

Not provided: `unwrap_or` (use `??`: `opt_val ?? "default"`), `unwrap_or_else`, `expect`, `and_then` (use `?` or `match`).

Use `??` operator for safe unwrap with default: `opt_val ?? "default"`

Use `?` operator to propagate None: `let val = opt_fn()?` (in Option-returning fn)

## Result[T, E] Methods

| Method | Returns | Purpose |
|--------|---------|---------|
| `.is_ok()` | Bool | Success? |
| `.is_err()` | Bool | Failure? |
| `.unwrap()` | T | Extract Ok value (panics on Err) |
| `.unwrap_err()` | E | Extract Err value (panics on Ok) |
| `.map(fn(T) -> U ! _)` | Result[U, E] | `Ok(f(x))` for `Ok(x)`, else the same `Err`. The callback effects pass to the caller |
| `.map_err(fn(E) -> F ! _)` | Result[T, F] | `Err(f(e))` for `Err(e)`, else the same `Ok`. The callback effects pass to the caller |
| `.ok()` | T? | `Some(x)` for `Ok(x)`, else `None` |

Default from a Result: `r.ok() ?? d`.

Not provided: `unwrap_or` (use `.ok() ??`), `unwrap_or_else`, `expect`, `and_then` (use `?` or `match`).

Use `?` operator to propagate errors: `let val = fallible()?`

## Template[C] Methods

| Method | Returns | Purpose |
|--------|---------|---------|
| `.parts()` | List[Str] | Template string parts (split around interpolation points) |
| `.count()` | Int | Number of substitution values |
| `.type_tag(idx)` | Int | Type tag at index (1=INT, 2=FLOAT, 3=BOOL, 4=STR) |
| `.get_str(idx)` | Str | String value at index |
| `.get_int(idx)` | Int | Integer value at index |
| `.get_float(idx)` | Float | Float value at index |
| `.get_bool(idx)` | Bool | Boolean value at index |

These methods enable writing database drivers entirely in Blink without C FFI helpers.

## ProcessResult Fields

```blink
let result = process_run("ls", ["-la"])
result.out          // Str — stdout
result.err_out      // Str — stderr
result.exit_code    // Int — exit code
```

## Duration Methods

| Method | Returns | Purpose |
|--------|---------|---------|
| `Duration.nanos(n)` | Duration | From nanoseconds |
| `Duration.ms(n)` | Duration | From milliseconds |
| `Duration.seconds(n)` | Duration | From seconds |
| `Duration.minutes(n)` | Duration | From minutes |
| `Duration.hours(n)` | Duration | From hours |
| `.to_nanos()` | Int | As nanoseconds |
| `.to_ms()` | Int | As milliseconds |
| `.to_seconds()` | Int | As seconds |
| `.add(other)` | Duration | Add durations |
| `.sub(other)` | Duration | Subtract durations |
| `.scale(n)` | Duration | Multiply by integer |
| `.is_zero()` | Bool | Zero duration? |
| `.to_iso8601()` | Str | ISO 8601 duration (`PT1H2M3.5S`) |

## Instant Methods

| Method | Returns | Purpose |
|--------|---------|---------|
| `time.read()` | Instant | Current time |
| `Instant.from_epoch_secs(n)` | Instant | From unix timestamp; panics outside the std.time range |
| `Instant.parse(s)` | Result[Instant, ConversionError] | RFC 3339 text, offset applied to give UTC |
| `.since(other)` | Duration | Difference between instants (`later.since(earlier)`) |
| `.add(dur)` | Instant | Add duration; panics outside the std.time range |
| `.date()` | Date | UTC calendar day |
| `.hour()` / `.minute()` / `.second()` | Int | UTC fields; the fraction is dropped |
| `.to_unix_ms()` | Int | As unix milliseconds |
| `.to_unix_secs()` | Int | As unix seconds |

The std.time range is 1677-09-22T00:00:00Z ..= 2262-04-11T23:47:16.854775807Z. The calendar
fields round down: 500 ms before the epoch is `1969-12-31`, hour 23, second 59.

```blink
let start = time.read()
// ... work ...
let elapsed = time.read().since(start)
io.println("Took {elapsed.to_ms()} ms")
io.println("Took {elapsed}")          // Display: "1.234s"

let d = Duration.seconds(5)
time.sleep(d)
```

## Date and Weekday

`import std.time.{Instant, Date, Weekday}`. There is no `DateTime`: an `Instant` is already a
point in UTC, and a `Date` is a calendar day with no time and no zone.

| Function / Method | Returns | Purpose |
|-------------------|---------|---------|
| `Date.from_ymd(y, m, d)` | Result[Date, ConversionError] | Day from year, month, day |
| `Date.parse(s)` | Result[Date, ConversionError] | `YYYY-MM-DD` only |
| `.year()` / `.month()` / `.day()` | Int | Calendar fields |
| `.weekday()` | Weekday | Day of the week |
| `.add_days(n)` | Date | `n` may be negative; panics outside 1677-09-22..2262-04-11 |
| `.days_since(earlier)` | Int | Days from `earlier`; negative when `earlier` is later |
| `.to_instant()` | Instant | 00:00:00Z on this day |
| `time.read().date()` | Date | Today in UTC (needs `! Time.Read`) |

`Weekday` is `Monday, Tuesday, Wednesday, Thursday, Friday, Saturday, Sunday`.
`Weekday.Monday.to_int()` is 0 and `Weekday.Sunday.to_int()` is 6. The ISO 8601 day number
is `to_int() + 1`. `Display` writes `2026-10-17` for a Date and `Saturday` for a Weekday;
`Debug` writes the same text. Both are `Eq`, `Ord`, `Hash` and `Clone`, so they key a Map.

`Instant.parse` accepts `YYYY-MM-DDTHH:MM:SS[.f]` then `Z` or `+HH:MM` / `-HH:MM`. The
separator is `T` or one space. Seconds and an offset are required; the fraction has 1 to 9
digits. Nothing else is accepted: no lowercase `t` or `z`, no comma fraction, no second 60.
Errors give the byte and what was found:

```blink
Date.parse("2026-1-07")          // Err: "invalid date: expected digit at byte 6 (found '-')"
Date.parse("2026-02-30")         // Err: "invalid date: day 30 out of range 1..28 for 2026-02"
Instant.parse("2026-02-14 12:00:00")
// Err: "invalid timestamp: no UTC offset at byte 19; append Z if the time is UTC"
Instant.parse("2026-02-14 12:00:00+01:00")   // Ok: 2026-02-14T11:00:00Z
```

Group log lines by day. Cut the stamp with `substring`, never `split(" ")`: a space
separator splits the stamp in two.

```blink
import std.time.{Instant, Date, Weekday}

// Each line starts with a 20-byte stamp: "2026-10-17 09:30:00Z GET /"
fn count_by_date(lines: List[Str]) -> Result[Map[Date, Int], ConversionError] {
    let mut counts: Map[Date, Int] = Map.new()
    for line in lines {
        let d = Instant.parse(line.substring(0, 20))?.date()
        counts.insert(d, (counts.get(d) ?? 0) + 1)
    }
    Ok(counts)
}

fn report(launch: Date) ! Time.Read, IO.Print {
    let today = time.read().date()
    io.println("{today} is a {today.weekday()}, {today.days_since(launch)} days after launch")
}
```

Not in v1: time zones, `add_months`, format strings, `today()`, leap seconds. Interpolate
the fields instead: `"{d.year()}/{d.month()}"`.

## JSON (with @derive)

```blink
@derive(Serialize, Deserialize)
type Task { id: Int, title: Str, done: Bool }

let task = Task { id: 1, title: "Test", done: false }
let json = task.to_json()                    // -> Str
let back = Task.from_json(json)              // -> Result[Task, Str]
```

Low-level JSON API (`import std.json`):

| Function | Returns | Purpose |
|----------|---------|---------|
| `json_parse(input)` | Int | Parse JSON string, returns root node index (-1 on error) |
| `json_encode(idx)` | Str | Serialize node tree to comblink JSON |
| `json_encode_pretty(idx)` | Str | Serialize to pretty-printed JSON (2-space indent) |
| `json_encode_indent(idx, n)` | Str | Serialize to pretty-printed JSON (custom indent width) |
| `json_type(idx)` | Int | Node type (JSON_NULL/BOOL/INT/FLOAT/STRING/ARRAY/OBJECT) |
| `json_get(idx, key)` | Int | Get child by key from object (-1 if missing) |
| `json_at(idx, i)` | Int | Get child by index from array |
| `json_len(idx)` | Int | Child count of array/object |
| `json_as_str(idx)` | Str | Extract string value |
| `json_as_int(idx)` | Int | Extract integer value |
| `json_new_object()` | Int | Create empty object node |
| `json_new_array()` | Int | Create empty array node |
| `json_new_str(s)` | Int | Create string node |
| `json_new_int(n)` | Int | Create integer node |
| `json_set(obj, key, val)` | () | Set key-value on object (add or replace) |
| `json_push(arr, val)` | () | Append value to array |
| `json_remove(obj, key)` | Int | Remove key from object; returns 1 if removed, else 0 |
| `json_clear()` | () | Reset all JSON state for next parse |

## CLI Argument Parsing (std.args)

```blink
import std.args

fn main() {
    let mut p = argparser_new("myapp", "Description")
    p = set_version(p, "1.0.0")                          // shows in --version and help
    p = add_command(p, "run", "Run the app")
    p = add_command(p, "daemon.start", "Start daemon")   // nested subcommand
    p = add_command(p, "daemon.stop", "Stop daemon")
    p = add_command_alias(p, "d", "daemon")              // "d start" = "daemon start"
    p = add_flag(p, "--verbose", "-v", "Verbose output")
    p = command_add_flag(p, "run", "--watch", "-w", "Watch mode")  // command-scoped flag
    p = add_option(p, "--output", "-o", "Output file")
    p = add_positional(p, "file", "Input file")
    p = command_add_positional(p, "daemon.start", "target", "File to watch")

    let a = argparse(p)                  // parse process args
    // let a = parse_argv(p, my_argv)    // or parse explicit List[Str]
    let cmd = args_command(a)            // "daemon start" (space-joined)
    let path = args_command_path(a)      // ["daemon", "start"] (List[Str])
    let verbose = args_has(a, "verbose")
    let output = args_get(a, "output")
    let all_outputs = args_get_all(a, "output")  // all values for repeated option
    let file = args_positional(a, 0)
    let rest = args_rest(a)              // args after "--"
}
```

## Imports & Modules

```blink
import lexer                     // import module (all pub items)
import std.args                  // import stdlib module
import mylib.{add, multiply}     // selective: only add and multiply
import mylib.{add as plus}       // alias: import add, call it plus
import mylib.{add as plus, multiply}  // mix alias + plain
```

Files are modules. `pub` marks items visible to importers. `import` brings `pub` items into scope.

A file's module name comes from its path under `src/` (`src/auth/token.bl` is `auth.token`). The file that declares `fn main` follows the same rule: `blink run src/main.bl` runs the module `main`, and a sibling can `import main` and call `main.shared()`. The package entry is `src/<name>.bl`, where `<name>` is `[package].name`. A file is one module however the build reaches it. A file outside `src/` (a script, `tests/`, `examples/`) has no module name, and no file can import it.

**Qualified access:** `import auth` enables qualified access only — `auth.login()`, `auth.Token`, `auth.Verifier` (a trait), `auth.MAX_RETRIES`. Bare (unqualified) names like `login()` require selective imports (`import auth.{login}`). Only the leaf module name works as qualifier (`num.parse_int()`, not `std.num.parse_int()`). Local variables shadow module names. A qualified trait or type name works in every slot that takes the bare name: a bound (`U: lib.Tr`), a `where` constraint, both names of an impl header (`impl lib.Tr for lib.Pt`), a supertrait clause, the argument of `@derive(...)`, and the head of an impl-qualified call (`(lib.Mk for W).make()`). The qualifier changes neither scope nor the orphan check, and an impl header does not put its trait in scope: call its methods with `import lib.{Tr}` or `lib.Tr.name(x)`. A type in a trait slot is `E0740 TypeNotTrait`.

Selective imports (`import mod.{a, b}`) restrict which *unqualified* items are visible — unselected items produce a compile error for bare names, but qualified access (`mod.item`) still works. Aliases (`as`) rename the item at the import site; the original name is no longer accessible. When two modules export the same name and both are imported without selection, the compiler emits an ambiguity error — use qualified access (`foo.name()` vs `bar.name()`) or selective imports to disambiguate.

## Annotations (ordered)

| Annotation | Target | Purpose |
|------------|--------|---------|
| `@module(name)` | module | Module declaration |
| `@capabilities(...)` | module | Effect ceiling |
| `@derive(...)` | type | Auto-generate traits. Accepted names: `Serialize`, `Deserialize`, `Eq`, `Ord`, `Clone`, `Hash`, `Debug`. `Ord` synthesizes a lexicographic `.cmp(other) -> Ordering` and auto-includes `Eq` (`Ord: Eq`); enables `<`/`>`/`<=`/`>=`. Each name resolves by scope: in a module that declares its own `Eq`, `@derive(Eq)` names that trait and is rejected; write `import blink.core.{Eq as CoreEq}` and `@derive(CoreEq)`. Any name that is not a derivable compiler-known trait is `E1402 NotDerivable`. |
| `@src(req)` | fn | Requirement traceability |
| `@perf(constraint)` | fn | Performance contract, such as `@perf(p99 < 200ms)` or `@perf(memory < 50mb)`. `blink bench --check-contracts` runs the benchmarks and fails when a constraint is violated. `blink fmt` puts it after `@where` |
| `@alt("ID", "label")` | fn | An alternative implementation of the function with the same name, kept in the codebase and type-checked. `blink alt list`, `blink alt select ID` and `blink alt compare` work with alternatives. `blink.toml` selects the active one per environment (`[alternatives]`) |
| `@requires(expr)` | fn | Precondition. Needs `@verify(fallback: ...)` on the fn, or it is `V0003 ContractUnverifiable` |
| `@ensures(expr)` | fn | Postcondition (`result` = return value). Needs `@verify(fallback: ...)` on the fn, or it is `V0003 ContractUnverifiable`; with `"runtime"` it is checked at every return. Inside the predicate, `old(arg)` snapshots an argument's value at fn entry. |
| `@where(expr)` | fn, type | Type constraint; on a fn, runtime-checked at param/return coercion |
| `@invariant(expr)` | type | Type invariant |
| `@pure` | fn | No effects, no mutation, no FFI; may only call other `@pure` fns. Recursion allowed. |
| `@modifies(...)` | fn | Reserves syntax for the future SMT backend (parses-and-validates only) |
| `@ffi("lib", "sym")` | fn | FFI binding — link to C function |
| `@trusted` | fn | FFI audit marker — function reviewed for safety |
| `@verify(fallback: "runtime" \| "trust")` | fn | What to do with a `@requires`/`@ensures` the compiler cannot prove (today: every one). `"runtime"` checks it and panics on violation; `"trust"` accepts it unchecked |
| `@allow(UnusedVariable)` | fn, type | Suppress specific diagnostic warning, by name |
| `@deprecated(msg)` | fn, type | Deprecation warning. Optional: `since`, `removal`, `replacement`, `fix` fields |

## Common Patterns

```blink
// Read + process file
import std.fs

fn print_todos(path: Str) -> Result[(), FsError] ! FS.Read, IO {
    let content = fs.read(path)?
    for line in content.split("\n") {
        if line.contains("TODO") {
            io.println("Found: {line}")
        }
    }
    Ok(())
}

// Error handling chain
fn load_config(path: Str) -> Result[Config, Str] ! FS.Read {
    let json = fs.read(path).map_err(fn(e) { "config not readable: {e}" })?
    Config.from_json(json)
}

// Build output with list
let mut parts: List[Str] = []
parts.push("header")
parts.push("body")
let output = parts.join("\n")
write_file("out.txt", output)

// Map usage
let mut scores: Map[Str, Int] = Map.new()
scores.insert("alice", 95)
match scores.get("alice") {
    Some(s) => io.println("Score: {s}")
    None => io.println("No score")
}

// Process execution
let result = process_run("git", ["rev-parse", "HEAD"])
if result.exit_code == 0 {
    io.println("Commit: {result.out.trim()}")
}
```

## User-Defined Effects

Declare custom effects with `effect` blocks. Sub-effects group related operations.

```blink
effect Metrics {
    effect Emit {
        fn counter(name: Str, value: Int)
        fn gauge(name: Str, value: Float)
    }
    effect Query {
        fn get_counter(name: Str) -> Int
    }
}
```

Use effects via namespaced dispatch:

```blink
fn record(name: Str, val: Int) ! Metrics.Emit {
    metrics.counter(name, val)
}
```

Handle effects with `with handler`:

```blink
with handler Metrics {
    fn counter(name: Str, value: Int) {
        io.println("captured: {name} = {value}")
    }
    fn gauge(_name: Str, _value: Float) {}
    fn get_counter(_name: Str) -> Int { 42 }
} {
    metrics.counter("requests", 1)  // intercepted by handler
    let v = metrics.get_counter("requests")  // returns 42
}
// after with-block, default handler restored
```

Handlers nest — inner handlers shadow outer ones for the same effect.

An effect and an effect operation take no type parameters (`fn put[T](x: T)` and `effect Cell[T]` are `EffectOpTypeParams`, E0558). Declare the operation with concrete types and write a generic `fn` that calls it, as `io.println` does.

An operation can have a default body in the effect declaration (`fn b() { ... }`); a handler may omit it. The body may perform only the leaf sub-effect it is declared in; any other effect is `DerivedOpForeignEffect` (E0557), so move that logic to a plain `fn` with its own `!` row. `@handle_all` on an effect (or sub-effect) says a handler must write every operation that has no body; a handler that omits one warns `W0545 PartialHandler`. `IO.Read` is such an effect, so a test can handle it with `std.testing.stdin_from(text)`:

```blink
import std.testing.{stdin_from}
with stdin_from("1\n2") { /* code that reads stdin sees "1\n2" */ }
```

## `with` Items, `as`, and Closeable

A `with` item is one of two things:

- a `Handler[E]`: the block runs with that handler installed;
- a scoped value: a type that implements `BlockHandler` (from `std.traits`). Its `enter()` runs before the block and its `exit(ok)` runs after it, on every exit path.

Any other item is E0839, with or without `as`. A `Result` or `Option` item needs `?` first: `with open_resource(path)? as f { ... }`.

`as` only binds a name. It does not change what the item does. `with h as name` installs the handler and binds it; `with v as name` binds the scoped value's Context (what `enter()` returns). Without `as`, the Context is discarded, whatever its type.

A type that implements `Closeable` is a scoped value. The compiler gives it `BlockHandler` with `Context` = the type itself, `enter()` returning the value, and `exit` calling `close()` (with `close()`'s effects). So `close()` runs at block exit, including early exits (break, return, error propagation), and `T: BlockHandler` accepts a Closeable type. Do not also write `impl BlockHandler` for a Closeable type: the two impls overlap, which is a compile error.

```blink
import std.traits

impl Closeable for MyResource {
    fn close(self) {
        // cleanup logic
    }
}

// close() is called on scope exit
with open_resource("file.txt") as f {
    io.println("using: {f.name}")
}

// Without `as`: the value is entered and closed, but not named
with open_resource("lock") {
    io.println("holding the lock")
}

// Multiple resources: closed in reverse order (b, then a)
with open_resource("a") as a, open_resource("b") as b {
    io.println("using: {a.name} and {b.name}")
}
```

A type parameter is a scoped value only when a bound makes it one: `fn hold[T: Closeable](t: T) { with t { ... } }` is accepted, and `fn hold[T](t: T) { with t { ... } }` is E0839. In a generic body the Context is abstract, so a `with t` there installs no handler.

## BlockHandler Trait & Scoped Blocks

Types that implement `BlockHandler` (from `std.traits`) provide scoped enter/exit semantics with an associated `Context` type.

```blink
pub trait BlockHandler {
    type Context
    fn enter(self) -> Self.Context
    fn exit(self, ok: Bool)
}

// Example: database transactions
with db.transaction() {
    db.exec("INSERT INTO users (name) VALUES ({name})")?
    db.exec("UPDATE stats SET count = count + 1")?
}
// auto-commit on success, auto-rollback on error/early exit
```

`self` is passed by value, so `enter()` cannot pass state to `exit()`, and `self.x = ...` in `enter()` is a compile error. Give the value all its state when it is built, and call the builder in the `with` item, so each `with` gets a new value:

```blink
pub fn timer(label: Str) -> Timer ! Time.Read {
    Timer { label: label, start: time.read() }
}

impl BlockHandler for Timer {
    type Context = ()
    fn enter(self) -> () {}
    fn exit(self, ok: Bool) ! Time.Read, IO.Log {
        io.log("{self.label}: {self.start.elapsed()}")
    }
}

with timer("db_query") { run_query()? }
```

A scoped value must reach exactly one `with`. W0611 `ScopedValueEnteredTwice` warns when one execution path takes a value into two, for example a value built before a loop and entered inside it. A copy of a scoped value is the same value.

## Associated Types on Traits

Traits can declare associated type members with `type Name`. Implementers must define these types.

```blink
trait BlockHandler {
    type Context                    // associated type declaration
    fn enter(self) -> Self.Context  // used in method signatures
    fn exit(self, ok: Bool)
}

impl BlockHandler for Transaction {
    type Context = ()               // implementer defines the type
    fn enter(self) -> () { ... }
    fn exit(self, ok: Bool) { ... }
}
```

## Display Trait

`Display` (from `std.traits`) is the canonical "make my type printable" trait. You implement **one** method — `fn fmt(self, sb: StringBuilder)` — rendering your value into the given `StringBuilder`. The compiler synthesizes a sealed `fn display(self) -> Str` for every impl (it allocates a fresh `StringBuilder`, calls your `fmt`, and returns the result), so you never write `display()` yourself.

```blink
import std.traits

impl Display for Point {
    fn fmt(self, sb: StringBuilder) {
        sb.write("({self.x}, {self.y})")
    }
}

let p = Point { x: 1, y: 2 }
io.println(p.display())   // "(1, 2)" — display() is synthesized, not written

// Built in for the scalar types
42.display()      // "42"
3.5.display()     // "3.5"
true.display()    // "true"
'x'.display()     // "x"
"hi".display()    // "hi"

// Usable as a generic bound
fn show[T: Display](x: T) -> Str { x.display() }
show(p)           // "(1, 2)"
show(42)          // "42"
```

`display()` is **sealed** — writing your own `fn display(self) -> Str` inside an `impl Display` is rejected with E0731. Implement `fmt` and delete the override; `display()` is derived from it.

## Standard Library

| Module | Description | Example |
|--------|-------------|---------|
| `std.args` | CLI argument parsing (flags, options, commands) | `import std.args` |
| `std.arena` | Arena introspection: `bytes_used()` returns live bytes in the innermost active `with arena { }` block | `import std.arena` |
| `std.db` | SQLite database with effect-based API (`DB.Read`, `DB.Write`), `Template[DB]` parameterization, `Row`, `Stmt`, `DBError`, transactions | `import std.db` |
| `std.float` | Float helpers: `fabs(x)` and `is_nan(x)` are `@pure`; `close_to(x, y, tol)` carries an `@ensures` clause. Methods: `x.fabs()`, `x.is_nan()`, `x.close_to(y, t)`. Float's `==` and `<` are a total order (NaN == NaN, NaN sorts above every other value, -0.0 == 0.0); the built-in `x.ieee_eq(y)` is the IEEE 754 escape, where NaN is unequal to everything | `import std.float` |
| `std.http` | HTTP client and server | `import std.http` |
| `std.io` | Derived I/O combinators. `read_fully(fd: Int, n: Int) -> Result[Bytes, Errno] ! IO` loops `libc.read_bytes` until exactly `n` bytes are read or EOF (a short read keeps looping; fewer than `n` is returned only at EOF, still `Ok`) | `import std.io` |
| `std.errno` | `Errno` — newtype over `Int` (`pub type Errno { code: Int }`), the error arm of the `*_bytes` syscall wrappers. Read the code with `e.code` | `import std.errno` |
| `std.json` | JSON parser and serializer | `import std.json` |
| `std.libc` | Curated libc syscall wrappers. `Pollfd`, `POLL_EVT_IN/PRI/OUT/ERR/HUP/NVAL`, `poll(fds, timeout_ms) -> Result[List[Pollfd], Str] ! IO` (semantics match `poll(2)`). Binary syscall wrappers returning `Result[…, Errno] ! IO`: `read_bytes(fd, max)` / `recv_bytes(fd, max)` / `getentropy_bytes(n)` → `Result[Bytes, Errno]`, `write_bytes(fd, data)` / `send_bytes(fd, data)` → `Result[Int, Errno]` (count written). A short read/write is `Ok` with a shorter `Bytes` / smaller count; only a `-1` syscall return is `Err(Errno { code: rc })` | `import std.libc` |
| `std.net` | TCP networking: `TcpSocket`, `TcpListener`, `NetError` (`Timeout`, `ConnectionRefused`, `DnsFailure`, `TlsError`, `InvalidUrl`, `BindError`, `ProtocolError`, `IoError`), `tcp_listen`, `tcp_connect`, `tcp_accept`, `tcp_read`, `tcp_write`, `tcp_read_bytes`, `tcp_write_bytes` | `import std.net` |
| `std.path` | Path utilities: `path_join(a, b)`, `path_dirname(path)`, `path_basename(path)`, `path_parent(path)` (POSIX `dirname(1)` semantics — strips trailing slashes before walking up) | `import std.path` |
| `std.process` | Process spawning: `spawn(cmd, args) -> Pid`, `Pid.wait()`, `Pid.kill()`, `Pid.send_signal(sig)`. POSIX signal constants: `SIGHUP`, `SIGINT`, `SIGQUIT`, `SIGKILL`, `SIGTERM` | `import std.process` |
| `std.semver` | Semantic version parsing and constraints | `import std.semver` |
| `std.testing` | Test helpers: `capture_log`, `capture_print`, `capture_eprint` (handler factories that intercept IO for assertions); `assert_close(a, b, tol)`, `assert_close_rel(a, b, rel)` (float assertions, panic on NaN / negative tol); `for_each[T](cases: List[(Str, T)], body: fn(T))` (table-driven test helper); `skip(reason: Str)` (skip a test from its body; rejected outside tests as `E0827`); `cleanup(fn: fn())` (register a teardown to run at end of test) | `import std.testing` |
| `std.term` | Terminal styling and control: ANSI colors (`red`, `green`, `blue`, etc.), text styles (`bold`, `dim`, `italic`, `underline`, `strikethrough`), background colors, TTY detection (`is_tty`, `terminal_width`, `terminal_height`), cursor control (`move_up`, `clear_screen`, `hide_cursor`, etc.) | `import std.term` |
| `std.toml` | TOML parser | `import std.toml` |

### Prelude Modules (auto-imported, no `import` needed)

| Module | Functions |
|--------|-----------|
| `std.str` | `str_split`, `str_join`, `str_replace`, `str_lines`, `str_trim`, `str_to_upper`, `str_to_lower`, `json_escape_str` |
| `std.list` | `list_map[T,U]`, `list_filter[T]`, `list_fold[T,U]`, `list_any[T]`, `list_all[T]`, `list_for_each[T]`, `list_concat[T]`, `list_slice[T]` |
| `std.map` | `map_for_each[K,V]`, `map_filter[K,V]`, `map_fold[K,V,U]`, `map_map_values[K,V,U]`, `map_merge[K,V]` |
| `std.num` | `parse_int`, `parse_float`, `int_to_str`, `float_to_str` |
| `std.sb` | StringBuilder extensions |
| `std.bytes` | Bytes type operations |
| `std.time` | Duration/Instant constructors and methods |
| `std.traits` | Core traits: `Closeable`, `BlockHandler`, `Sized`, `Contains`, `From[T]`, `Into[T]`, `TryFrom[T]`, `ConversionError`, `StrOps`, `ListOps`, `MapOps`, `SetOps`, `BytesOps`, `StringBuildOps`, `Joinable`. `Sized` is the canonical length / emptiness trait — `Str`, `List`, `Map`, `Set`, `Bytes`, and `StringBuilder` all provide it (uniform `.len()` / `.is_empty()`). |

Run `blink doc <module>` for full documentation (e.g. `blink doc std.args`).
Run `blink doc --list` to list available modules.

## Gotchas

- `{}` is NOT an empty map — use `Map.new()`. `{}` in expression position is a compile error. Similarly, use `Set.new()` for empty sets.
- `file_exists()` returns `Int` (0/1), not `Bool` — use `== 1` or `== 0`
- `is_dir()` also returns `Int`, not `Bool`
- `shell_exec()` returns exit code (Int), not stdout — use `process_run()` for output capture
- No `return` needed for last expression in function body
- `match` must be exhaustive — cover all variants or use `_ =>` wildcard
- List patterns in `match` ALWAYS need a wildcard `_` or rest `...` arm — finite patterns can't cover unbounded lists
- `let mut` required for any variable you want to reassign. In a pattern, `mut` goes on each name: `let (mut x, y) = pair`, not `let mut (x, y) = pair`
- Function args separated by commas in calls, but by newlines in multi-line definitions
- `assert`, `assert_eq`, `assert_ne` only available inside `test` blocks and debug mode
- `assert_panics { ... }` (and `assert_panics(matching: "substr") { ... }`) is a compiler-recognized, test-only block assertion that passes only if its body panics — valueless and non-nestable

## Build & Run

```sh
build/blink build src/main.bl     # compile to build/main
build/blink run src/main.bl       # compile + run
build/blink test                    # discover + run all test blocks
build/blink check src/main.bl     # typecheck without compiling
build/blink fix src/main.bl       # apply the machine-applicable fixes of its diagnostics
build/blink fmt src/main.bl       # format in place
build/blink doc --list              # list available stdlib modules
build/blink doc std.args            # print module documentation
build/blink doc std.json --json     # module docs as JSON
build/blink audit src/main.bl     # FFI audit report
build/blink update                  # update deps + blink-version in blink.toml

# Output format: --format json prints what --json prints; human is the default.
# check, build, fmt, run and test take it. --json beside another --format value is an error.
# A check --json diagnostic can carry "fix" (an edit blink fix applies) and "assist" (an edit
# a person must finish or choose, such as E0319's `f: _`). Each has action, text and span.
build/blink check src/main.bl --format json

# blink test --json: per test file, {"results": [...], "summary": {...}}.
# Each result status is passed | failed | panicked | skipped (a panic carries
# its message). summary has total, passed, failed, panicked, skipped, duration_ms.
build/blink test --json

# Default builds (no mode flag) compile the C at -O1
build/blink build src/main.bl

# Release builds (optimized with -O2). They leave out `test` blocks; check and build still
# typecheck each test body.
build/blink build src/main.bl --release
build/blink build src/main.bl -R

# build, run and test compile one C unit per module by default, in parallel and
# cached one object per unit, so an edit recompiles only the units it changed.
# --jobs N (or BLINK_JOBS=N) caps the units compiled at once; the default is
# the CPU count.
build/blink run src/main.bl --jobs 4

# One C unit for the whole program, to bisect a per-module bug. A flag beats
# BLINK_PER_MODULE (0 or 1), which beats the default. --per-module asks for the
# default by name.
build/blink build src/main.bl --no-per-module
BLINK_PER_MODULE=0 build/blink test tests/main_test.bl

# Cross-compilation (single target)
build/blink build src/main.bl --target linux
build/blink build src/main.bl -T macos-arm64

# Multi-target builds (compile to C once, link per target)
build/blink build src/main.bl -T linux -T macos-arm64
# Produces: build/main-linux, build/main-macos-arm64

# Combined
build/blink build src/main.bl --release -T linux -T macos-arm64
# Aliases: linux, linux-arm64, macos, macos-arm64, macos-amd64
# Also accepts raw zig target triples: x86_64-linux-gnu, aarch64-macos, etc.
```

### Emit modes (`--emit`)

`blink build --emit <mode>` selects the output shape:

```sh
# Default: emit a linked native binary.
build/blink build src/main.bl

# Emit a single monolith C file (build/main.c). Use this to inspect
# generated C, or to bisect a codegen regression against one TU.
build/blink build src/main.bl --emit c

# Emit one .c per program module into a directory, with the headers each
# unit includes (blink.types.h, <m>.h, <m>.priv.h). The output target is a DIRECTORY:
# pass it as the second positional, or via -o.
build/blink build src/main.bl --emit per-module-dir build/main_modules
build/blink build src/main.bl --emit per-module-dir -o build/main_modules

# Link the per-module set with a pinned (sorted) link order:
cc -o build/main_modules/bin $(ls build/main_modules/*.c | sort) -Ibuild -lm -lgc
```

`per-module-dir` is the documented surface for per-module emit. Each module
`.c` includes the headers of the symbols it names so cross-module calls and
typedefs resolve; the entry module owns runtime globals and every other module
externs them. The legacy hidden `__emit-per-module <file.bl> <outdir>`
subcommand still works as a deprecation alias for one release. See
`docs/build/per-module-o-default.md` for the rationale and for how the default
build uses per-module units.

### Compiler Daemon

The compiler daemon is a background process that keeps checked programs in memory, watches their files and rechecks a program when one of its files changes. A project has one daemon; its socket is in `.blink/` at the project root. While it runs, `blink check`, `blink query`, `blink build` and `blink run` use it. When it cannot serve a build or run (its compiler, environment or settings differ from the client's), the command builds cold, with the same result.

```sh
# Start the daemon for the project that holds this entry file
blink daemon start src/main.bl
blink daemon start src/main.bl --max-entries 4   # entry files kept checked at once (default 8)

# Status and stop take no file argument
blink daemon status      # uptime, memory, graph size
blink daemon stop

# These commands use the daemon when it runs:
blink check src/auth.bl  # incremental recheck
blink query src/auth.bl  # symbol lookup from the cached index
blink build src/main.bl  # warm build; falls back to a cold build
blink run src/main.bl
```

Start the daemon at the start of an edit session to get faster checks and builds.

### Debugging & Inspection Flags

```sh
# Debug builds (debug_assert enabled, -g -O0)
build/blink build src/main.bl --debug
build/blink build src/main.bl -d

# AST dump (JSON) — inspect parsed syntax tree
build/blink ast src/main.bl                    # full AST as JSON
build/blink ast src/main.bl --imports          # resolve imports, show merged AST
build/blink ast src/main.bl --node 42          # dump subtree for node ID 42

# Compiler phase tracing — trace lex/parse/typecheck/codegen phases
build/blink build src/main.bl --blink-trace all
build/blink build src/main.bl --blink-trace parse    # single phase

# Treat warnings as errors
build/blink build src/main.bl --strict
```

### Runtime Execution Tracing (`--trace`)

Emits structured NDJSON to stderr with function enter/exit, state mutations, and effect invocations. Zero cost when not enabled.

```sh
# Trace everything
build/blink run app.bl --trace all

# Filter by function, module, or depth
build/blink run app.bl --trace "fn:parse_expr"
build/blink run app.bl --trace "module:parser,depth:2"
build/blink run app.bl --trace "fn:skip_ws+parse_block"   # OR with +

# Filter by event type
build/blink run app.bl --trace "event:enter+exit"          # only enter/exit
build/blink run app.bl --trace "event:effect"              # only effect invocations
build/blink run app.bl --trace "event:state"               # only state mutations

# Filter by effect or state variable
build/blink run app.bl --trace "effect:FS.Write"
build/blink run app.bl --trace "state:count"

# Cap output to N events
build/blink run app.bl --trace all --trace-limit 100

# Environment variable (same filter syntax)
BLINK_TRACE=all build/blink run app.bl
BLINK_TRACE_LIMIT=50 BLINK_TRACE=all build/blink run app.bl
```

Trace event types:

| Event | Fields | Description |
|-------|--------|-------------|
| `enter` | `span`, `args` | Function entry with source location and arguments |
| `exit` | `duration_us`, `return` | Function exit with duration and return value |
| `effect` | `effect`, `op`, `args` | Effect invocation (IO, FS, DB) |
| `state` | `var`, `op`, `value` | State mutation (assign, push, insert) |

All events include: `ts_us`, `event`, `fn`, `module`, `depth`. Values truncated at 200 chars.

### Low-level Compiler Flags (blinkc)

```sh
build/blinkc src/main.bl output.c              # compile to C
build/blinkc src/main.bl output.c --dump-ast    # dump AST during compilation
build/blinkc src/main.bl output.c --stats       # print compilation statistics
build/blinkc src/main.bl output.c --debug       # debug mode
build/blinkc src/main.bl output.c --emit blink   # emit formatted Blink (formatter)
```

## Arena

Opt-in bump allocation via the `! Arena` effect. See spec §5.2 / §5.2.1 for the
full semantics; this topic covers the one rule you cannot derive from prose:
**handler composition order around `arena`**.

### The `! Arena` effect marker

Functions that allocate into the caller's arena carry `! Arena` in their
effect row:

```blink
fn build_node(x: i32) -> Node ! Arena {
    Node { value: x, next: none }   // allocated in caller's arena
}
```

Callers inside `with arena { }` satisfy the effect automatically. Callers
outside must either propagate the effect (by carrying `! Arena` themselves)
or wrap the call in `with arena { }` so the allocation has a target.

**Lint W0701** warns when `! Arena` is redundant — e.g. a function whose body
is a single `with arena { }` already captures the effect at the block level,
so the outer signature doesn't need it.

### When to reach for `with arena { }`

Wrap a hot path where GC pressure is measurable and all transient allocations
can die at the same program point:

```blink
let summary = with arena {
    process_batch(items)   // allocates freely inside; freed at `}`
}
```

The block is an expression. Its tail value is deep-copied (promoted) into the
next allocator out — the **nearest enclosing arena** if one is active,
otherwise the **GC heap**. Allocations not reachable from the tail are freed
in one shot at `}`.

### Execution timeline: `with h1, arena, h2 { body }`

Blink composes `with` handlers left-to-right on entry, right-to-left on exit
(standard LIFO). The arena is just another `BlockHandler`, so the rule that
matters is **positional**: anything right of `arena` runs its `exit()` before
promotion; anything left runs `exit()` after.

Timeline for `with h1, arena, h2 { body }`:

1. `h1.enter()`
2. `arena.enter()` — snapshots `__blink_current_arena` (the promotion target)
3. `h2.enter()`
4. `body` executes; produces `tail` allocated inside the inner arena
5. `h2.exit(ok)` — **pre-promotion**: `tail` still points into the inner arena
6. `blink_promote_<T>(tail, snapshot_target)` — deep-copies `tail` into the
   allocator captured at step 2
7. `arena.exit(ok)` — restores TLS, destroys the inner arena
8. `h1.exit(ok)` — **post-promotion**: observes the promoted `tail`

**Rule of thumb:** handlers **right** of `arena` see pre-promotion state;
handlers **left** see post-promotion state. Position in the `with` clause =
position in the teardown timeline.

### Worked example

```blink
// `logger` logs the final promoted value. `trace` records the raw
// in-arena shape before it's deep-copied out.
fn main() {
    with logger, arena, trace {
        let tmp = [1, 2, 3]
        tmp                       // tail expression
    }
    // trace.exit saw `tmp` as an arena-local list.
    // logger.exit saw `tmp` after promotion into the GC heap —
    // .len() etc. read through a freshly-walked copy.
}
```

If `trace` tried to stash a reference to `tmp` past `arena.exit()`, that
reference would dangle — which is why `! Arena` escape analysis exists
(`E0700`). Handlers **left** of `arena` are the safe place to retain the
result, because by the time their `exit()` runs, the value has already been
copied out.

### Nested arenas

Each `with arena { }` snapshots its own outer target at `enter()`. Inner
tails promote into the outer arena; the outermost block promotes into the
GC heap. No handler-stack walk, no extra TLS slots — see spec §5.2.1 pt 4.

### Nested closure captures

Closure-typed tails whose captures include other closures (or arena-allocated
values reachable through those closures) now promote correctly. Each
`blink_closure` carries a per-capture type-descriptor table; the generated
`blink_promote_closure_<Mangled>` walks it and recurses structurally, so a
closure capturing a closure capturing a list-of-records deep-copies in one
pass. See `decisions/arena-nested-closure-capture-promotion.md`.

### Early exits

`return expr` and `expr?` inside `with arena { body }` promote `expr` into
the same target the tail would have used, then run `arena.exit(false)` (which
still destroys the inner arena), then propagate. See spec §5.2.1 pt 2.

### Diagnostics

- `E0700 ArenaValueEscapes` — value allocated in the block reaches a
  non-promotable position (closure capture, field store on an outside
  target, argument to a non-arena-local parameter, etc.). E0700 prints the
  resolved promotion target (`GC heap` or `outer arena`) so nested-arena
  escapes are debuggable.
- `E0701 ArenaTypeContainsCycle` — a type crossing the boundary has a cyclic
  field graph; the walker cannot materialize it into another allocator.
- `E0702a ArenaClosureTailNonLiteral` — the tail evaluates to a closure whose
  origin isn't a closure literal bound in this block (e.g. returned from a
  call, or reassigned through a variable). Fix: construct the closure outside
  the `with arena { }` block, or bind it via
  `let f = fn(…) { … }` immediately inside the block.
- `E0702d ArenaClosureUnsupportedCapture` — a closure-tail capture is of a
  kind the descriptor walker can't materialize. Rare after the nested-closure
  capture work (see "Nested closure captures" above); fix by constructing the
  closure outside the arena block.

See §5.2.1 "Expression-form semantics" point 3 for the spec cross-reference.
