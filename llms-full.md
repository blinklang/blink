# Blink Language Reference

> Blink is a statically-typed, effect-tracked language compiling to C. **Compiler v0.39.0**.

## Install

**Binary** (Linux/macOS): download from [GitHub Releases](https://github.com/blinklang/blink/releases/latest) and place on PATH.

**Docker**:
```
docker pull ghcr.io/blinklang/blink:latest
docker run --rm -v "$PWD":/workspace ghcr.io/blinklang/blink run myfile.bl
```

Tags: `latest`, `0.39`, `0.39.0` (semver). Image is `debian:bookworm-slim` with `gcc`, `zig`, `blink`, `libgc-dev`, and `libsqlite3-dev`.

## Recent Changes

See `CHANGELOG.md` (also printed by `blink llms --full`).

**CRITICAL — Read before writing any Blink code:**
- `fn` keyword, `{ }` braces, NO semicolons — newlines separate statements
- `"double quotes"` ONLY — no single quotes for strings
- Universal string interpolation: `"Hello, {name}!"` — every string supports `{expr}`
- `io.println(...)` NOT `print(...)` — IO goes through effect handles
- NO `+` on strings — use interpolation `"{a}{b}"` or `.concat()`
- Square bracket generics: `List[T]` NOT `List<T>`
- Method calls always: `x.len()` NOT `x.len` (no properties)
- `main` has implicit effects — no annotation needed on `fn main()`

## FFI (Foreign Function Interface)

Blink can call C functions via the `@ffi` annotation and `Ptr[T]` type.

### @ffi Annotation

```blink
@ffi("sqlite3", "sqlite3_open")
fn sqlite3_open(filename: Ptr[Int], db: Ptr[Ptr[Int]]) -> Int
```

`@ffi("library", "symbol")` — first arg is library name, second is C symbol name.

### @trusted Audit Marker

```blink
@trusted
@ffi("libc", "malloc")
fn malloc(size: Int) -> Ptr[Int]
```

`@trusted` marks FFI functions as audited for safety.

### Ptr[T] Type

| Method | Returns | Purpose |
|--------|---------|---------|
| `.deref()` | T | Dereference pointer |
| `.addr()` | Int | Get raw address |
| `.write(val)` | Void | Write value at pointer |
| `.is_null()` | Bool | Null check |
| `.to_str()` | Str | Convert to string (for char*) |
| `.as_cstr()` | Str | Read as C string |

### ffi.scope() Resource Management

```blink
ffi.scope(fn(scope) {
    let cstr = scope.cstr("hello")     // allocate C string (auto-freed)
    let buf = scope.alloc(1024)        // allocate raw memory (auto-freed)
    let result = scope.take(ptr)       // take ownership of pointer
})
```

`ffi.scope()` provides automatic memory management for FFI operations. All allocations are freed when the scope exits.

### Native Dependencies (blink.toml)

```toml
[native-dependencies]
sqlite3 = { vendored = "vendor/sqlite3.c" }
libcurl = { system = true }
```

### blink audit

```sh
bin/blink audit src/main.bl          # FFI audit report
```

Lists all `@ffi` calls, their audit status (`@trusted` or unaudited), and pointer operations.

## Syntax Quick Reference

```blink
// Variables
let x = 42                       // immutable
let mut count = 0                // mutable
let name: Str = "Alice"          // type annotation
let (a, b) = (10, 20)           // tuple destructuring

// Functions
fn add(a: Int, b: Int) -> Int {
    a + b                        // last expression is return value
}

fn greet(name: Str) ! IO {       // ! declares effects
    io.println("Hello, {name}!")
}

// Keyword arguments
greet(name: "Alice", greeting: "Hi")

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
let s = Shape.Circle(5.0)

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
    [cmd, ...] => io.println("unknown: {cmd}")  // ... = rest wildcard (no binding)
}

// Control flow
if x > 0 { "positive" } else { "non-positive" }  // expression
for item in list { io.println(item) }
while count < 10 { count += 1 }
loop { if done { break } }

// Error handling
fn parse(s: Str) -> Result[Int, Str] {
    if s == "" { Err("empty") } else { Ok(s.to_int()) }
}
let val = parse(input)?           // propagate error (in Result-returning fn)
let val = maybe_val ?? "default"  // unwrap Option with default

// Traits
trait Display {
    fn display(self) -> Str
}
impl Display for Point {
    fn display(self) -> Str { "({self.x}, {self.y})" }
}

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
| List[T] | `[1, 2, 3]` | Dynamic array |
| Map[K, V] | `Map()` | Hash map (construct with `Map()`, not `{}`) |
| Set[T] | `Set()` | Hash set (construct with `Set()`) |
| Option[T] | `Some(v)`, `None` | Nullable value |
| Result[T, E] | `Ok(v)`, `Err(e)` | Error-or-value |
| Bytes | `Bytes.new()` | Byte buffer |
| StringBuilder | `StringBuilder.new()` | Mutable string builder |
| Instant | `time.read()` | Point in time |
| Ptr[T] | `Ptr[Int]` | Raw pointer (FFI) |
| Duration | `Duration.ms(100)` | Time span |
| Template[C] | `"SELECT * FROM t WHERE id = {id}"` | Parameterized template string (context `C` = `DB`, etc.). Interpolated values auto-extracted as parameters. `Raw(expr)` escapes parameterization. |
| I8 / I16 / I32 | — | Sized signed integers (8/16/32-bit). C-style wrapping casts. FFI use. |
| U8 / U16 / U32 / U64 | — | Sized unsigned integers. C-style wrapping casts. FFI use. |

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

No implicit promotion between sized types and `Int`. Always use `.to_int()` to widen.

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

### Extended Strings

Extended strings `#"..."#` allow literal `"` and `\` without escaping. Use `#{expr}` for interpolation.

```blink
let raw = #"path\to\file"#              // no escaping needed
let json = #"{"key": "value"}"#         // literal quotes
let msg = #"Hello, #{name}!"#           // interpolation with #{...}
let nested = ##"contains #"inner"#"##   // depth-2 nesting
```

## Operators

| Op | Types | Notes |
|----|-------|-------|
| `+` `-` `*` `/` `%` | Int, Float | Arithmetic (NO `+` on Str) |
| `==` `!=` `<` `>` `<=` `>=` | Int, Float, Str | Comparison |
| `&&` `\|\|` `!` | Bool | Logical |
| `?` | Result[T,E] | Propagate error — enclosing fn must return Result |
| `??` | Option[T] | Unwrap or default |
| `\|>` | Any | Pipe: `x \|> f()` = `f(x)` |
| `+=` `-=` `*=` `/=` | Int, Float | Compound assignment (mut only) |

## Builtin Functions

| Function | Returns | Purpose |
|----------|---------|---------|
| `read_file(path)` | Str | Read file to string |
| `write_file(path, content)` | Void | Write string to file |
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
| `process_exec(cmd, args)` | Void | Exec binary directly (replaces process). `args` is `List[Str]` |
| `exit(code)` | Void | Exit with code |
| `arg_count()` | Int | CLI argument count |
| `get_arg(idx)` | Str | CLI argument by index |
| `time_ms()` | Int | Current time in milliseconds |
| `getpid()` | Int | Process ID |
| `str_from_code_point(n)` | Str | Convert char code to 1-char string (was `str_from_char_code`) |
| `unix_socket_listen(path)` | Int | Listen on Unix domain socket |
| `unix_socket_connect(path)` | Int | Connect to Unix domain socket |
| `unix_socket_accept(fd)` | Int | Accept incoming connection |
| `unix_socket_accept_timeout(fd, ms)` | Int | Accept with timeout (ms) |
| `unix_socket_close(fd)` | Void | Close socket |
| `socket_read_line(fd)` | Str | Read line from socket |
| `socket_write(fd, data)` | Void | Write data to socket |
| `ffi_scope(fn)` | Void | FFI resource scope — auto-frees allocations on exit |
| `tcp_listen(host, port)` | Int | Listen on TCP socket |
| `tcp_connect(host, port)` | Int | Connect to TCP host:port |
| `tcp_accept(fd)` | Int | Accept incoming TCP connection |
| `tcp_read(fd, max_bytes)` | Str | Read up to max_bytes from TCP socket |
| `tcp_read_all(fd)` | Str | Read all available data from TCP socket |
| `tcp_read_bytes(fd, max_bytes)` | Result[Bytes, NetError] | Binary-safe read; preserves null bytes and non-UTF-8 |
| `tcp_write(fd, data)` | Void | Write data to TCP socket |
| `tcp_write_bytes(fd, data)` | Result[Void, NetError] | Binary-safe write of Bytes buffer |
| `tcp_close(fd)` | Void | Close TCP socket |
| `tcp_set_timeout(fd, ms)` | Void | Set read timeout on TCP socket |

## Namespace Methods

```blink
// IO (effect: IO)
io.println("text")              // print + newline to stdout
io.print("text")                // print without newline
io.eprintln("error")            // print to stderr + newline
io.eprint("error")              // print to stderr, no newline
io.log("debug info")            // stderr with [LOG] prefix
io.read_line()                  // -> Str (read line from stdin)
io.read_bytes(n)                // -> Bytes (read n bytes from stdin)
io.write(s)                     // write string to stdout (no newline)
io.write_bytes(b)               // write Bytes to stdout
io.print_raw("text")            // raw printf (bypasses vtable)
io.eprint_raw("error")          // raw fprintf stderr (bypasses vtable)

// Filesystem (effect: FS)
fs.read(path)                   // -> Str
fs.write(path, content)         // -> Void
fs.remove(path)                 // -> Void (delete file, backed by unlink(2))
fs.list_dir(dir)                // -> List[Str] (filenames)

// Environment (effect: Env)
env.args()                      // -> List[Str] (all CLI args)
env.var(name)                   // -> Option[Str] (read env var, effect: Env.Read)
env.cwd()                       // -> Str (current working directory, effect: Env.Read)
env.set_var(name, value)        // set env var (effect: Env.Write)
env.remove_var(name)            // remove env var (effect: Env.Write)
env.exit(code)                  // terminate process (effect: Env)

// Time
time.read()                     // -> Instant
time.sleep(duration)            // sleep for Duration

// Async (effect: Async)
async.scope { ... }             // synchronous scope for spawned tasks
async.spawn(fn() { ... })       // spawn task, returns Handle

// Database (effect: DB) — stdlib module, requires `import std.db`
// Connection: effect-handler scoped (no global state)
with db.connect(path) {         // open SQLite DB, installs DB handler for scope (v0.35+)
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
db.exec(tpl)                    // -> Result[Void, DBError] (DDL/DML, no return)
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
db.begin()                      // -> Result[Void, DBError] (manual)
db.commit()                     // -> Result[Void, DBError]
db.rollback()                   // -> Result[Void, DBError]

// DBError enum variants: QueryError, ExecError, ConnectionError, NotFound

// Net (effect: Net.Listen for listen/accept, Net.Connect for connect)
net.listen(host, port)          // -> Int (listen fd)
net.accept(fd)                  // -> Int (connection fd)
net.read(fd, max_bytes)         // -> Str (read up to max_bytes)
net.read_all(fd)                // -> Str (read all available data)
net.write(fd, data)             // -> Void
net.close(fd)                   // -> Void
net.connect(host, port)         // -> Int (connection fd)
net.set_timeout(fd, ms)         // -> Void (set read timeout)
```

## String Methods

| Method | Returns | Purpose |
|--------|---------|---------|
| `.len()` | Int | Length in bytes |
| `.is_empty()` | Bool | Check if empty |
| `.contains(s)` | Bool | Substring check |
| `.starts_with(s)` | Bool | Prefix check |
| `.ends_with(s)` | Bool | Suffix check |
| `.index_of(s)` | Int | Find index (-1 if not found) |
| `.concat(s)` | Str | Concatenate |
| `.substring(start, len)` | Str | Extract by position + length |
| `.slice(start, end)` | Str | Extract by range |
| `.split(sep)` | List[Str] | Split by separator |
| `.lines()` | List[Str] | Split by newlines |
| `.trim()` | Str | Strip leading and trailing whitespace |
| `.trim_right()` | Str | Strip trailing whitespace |
| `.trim_left()` | Str | Strip leading whitespace |
| `.to_upper()` | Str | Uppercase |
| `.to_lower()` | Str | Lowercase |
| `.replace(old, new)` | Str | Replace all occurrences |
| `.to_int()` | Int | Parse as integer |
| `.parse_float()` | Float | Parse as float |
| `.char_at(idx)` | Option[Char] | Char at index, `None` if out of range or mid-codepoint |
| `.byte_at(idx)` | Int | Raw byte at index |

## Char Methods

`Char` is a Unicode scalar value. Literal: `'a'`, `'\n'`, `'\t'`, `'\\'`, `'\''`.

| Method | Returns | Purpose |
|--------|---------|---------|
| `.to_int()` | Int | Unicode code point as integer |
| `.to_str()` | Str | Single-character string |

**Construction:**
```blink
let c: Char = 'a'
let result = Char.from_code_point(65)   // -> Result[Char, ConversionError]
let s = str_from_code_point(65)         // -> Str ("A"), from std.str
```

## List[T] Methods

| Method | Returns | Purpose |
|--------|---------|---------|
| `.len()` | Int | Length |
| `.is_empty()` | Bool | Check if empty |
| `.push(item)` | Void | Append (mutates) |
| `.pop()` | Option[T] | Remove last |
| `.get(idx)` | Option[T] | Element at index (None if OOB) |
| `.set(idx, val)` | Void | Set element (mutates) |
| `.concat(other)` | List[T] | Concatenate lists |
| `.slice(start, end)` | List[T] | Sub-list |
| `.join(sep)` | Str | Join as string (List[Str]) |
| `.map(fn(T)->U)` | List[U] | Transform each |
| `.filter(fn(T)->Bool)` | List[T] | Keep matching |
| `.fold(init, fn(A,T)->A)` | A | Reduce |
| `.find(fn(T)->Bool)` | Option[T] | First match |
| `.any(fn(T)->Bool)` | Bool | Any match? |
| `.all(fn(T)->Bool)` | Bool | All match? |
| `.count()` | Int | Count elements (drives iterator) |
| `.for_each(fn(T)->Void)` | Void | Apply to each element |
| `.chain(other)` | Iterator[T] | Concatenate iterators |
| `.flat_map(fn(T)->List[U])` | Iterator[U] | Map + flatten |
| `.zip(other)` | List[List] | Pair elements (eager, returns list-of-pairs) |
| `.enumerate()` | List[List] | With indices (eager, returns list-of-pairs) |
| `.take(n)` | Iterator[T] | First n |
| `.skip(n)` | Iterator[T] | Skip first n |
| `.collect()` | List[T] | Iterator to list |
| `.clear()` | Void | Remove all elements (mutates) |

## Map[K, V] Methods

| Method | Returns | Purpose |
|--------|---------|---------|
| `Map()` | Map[K,V] | Create empty map (NOT `{}`) |
| `map[key] = val` | Void | Insert/update via index assignment |
| `.insert(key, val)` | Void | Insert/update (method form) |
| `.get(key)` | Option[V] | Safe lookup — pattern-match `Some(v)` / `None` |
| `.contains_key(key)` | Bool | Key exists? |
| `.remove(key)` | Bool | Remove key, returns `true` if removed |
| `.len()` | Int | Entry count |
| `.keys()` | List[K] | All keys |
| `.values()` | List[V] | All values |
| `.clear()` | Void | Remove all entries (mutates) |

## Set[T] Methods

| Method | Returns | Purpose |
|--------|---------|---------|
| `Set()` | Set[T] | Create empty set |
| `.insert(elem)` | Bool | Add element to set |
| `.remove(elem)` | Bool | Remove element from set |
| `.contains(elem)` | Bool | Membership check |
| `.len()` | Int | Number of elements |
| `.is_empty()` | Bool | Check if empty |
| `.union(other)` | Set[T] | Union of two sets |

## Bytes Methods

| Method | Returns | Purpose |
|--------|---------|---------|
| `Bytes.new()` / `Bytes()` | Bytes | Create empty byte buffer |
| `Bytes.from_str(s)` | Bytes | Create from string |
| `.push(byte)` | Void | Append byte (mutates) |
| `.get(idx)` | Option[Int] | Byte at index |
| `.set(idx, byte)` | Void | Set byte (mutates) |
| `.len()` | Int | Length |
| `.is_empty()` | Bool | Check if empty |
| `.slice(start, end)` | Bytes | Sub-buffer |
| `.concat(other)` | Bytes | Concatenate |
| `.to_str()` | Result[Str, Str] | Convert to UTF-8 string |
| `.to_hex()` | Str | Hex encoding |
| `.read_u16_be(offset)` | Result[Int, Str] | Read unsigned 16-bit big-endian at offset |
| `.read_u16_le(offset)` | Result[Int, Str] | Read unsigned 16-bit little-endian at offset |
| `.read_u32_be(offset)` | Result[Int, Str] | Read unsigned 32-bit big-endian at offset |
| `.read_u32_le(offset)` | Result[Int, Str] | Read unsigned 32-bit little-endian at offset |
| `.read_i32_be(offset)` | Result[Int, Str] | Read signed 32-bit big-endian at offset |
| `.read_i32_le(offset)` | Result[Int, Str] | Read signed 32-bit little-endian at offset |
| `.read_i64_be(offset)` | Result[Int, Str] | Read signed 64-bit big-endian at offset |
| `.read_i64_le(offset)` | Result[Int, Str] | Read signed 64-bit little-endian at offset |
| `.write_u16_be(val)` | Void | Append unsigned 16-bit big-endian (grows buffer) |
| `.write_u16_le(val)` | Void | Append unsigned 16-bit little-endian (grows buffer) |
| `.write_u32_be(val)` | Void | Append unsigned 32-bit big-endian (grows buffer) |
| `.write_u32_le(val)` | Void | Append unsigned 32-bit little-endian (grows buffer) |
| `.write_i32_be(val)` | Void | Append signed 32-bit big-endian (grows buffer) |
| `.write_i32_le(val)` | Void | Append signed 32-bit little-endian (grows buffer) |
| `.write_i64_be(val)` | Void | Append signed 64-bit big-endian (grows buffer) |
| `.write_i64_le(val)` | Void | Append signed 64-bit little-endian (grows buffer) |

## StringBuilder Methods

| Method | Returns | Purpose |
|--------|---------|---------|
| `StringBuilder.new()` | StringBuilder | Create empty builder |
| `StringBuilder.with_capacity(n)` | StringBuilder | Create with pre-allocated capacity |
| `.write(s)` | Void | Append string |
| `.write_char(ch)` | Void | Append single character |
| `.write_int(n)` | Void | Append integer as string |
| `.write_float(f)` | Void | Append float as string |
| `.write_bool(b)` | Void | Append bool as string |
| `.to_str()` | Str | Build final string |
| `.len()` | Int | Current length |
| `.capacity()` | Int | Allocated capacity |
| `.clear()` | Void | Reset to empty |
| `.is_empty()` | Bool | Check if empty |

## Option[T] Methods

| Method | Returns | Purpose |
|--------|---------|---------|
| `.unwrap()` | T | Extract value (panics on None) |
| `.is_some()` | Bool | Has value? |
| `.is_none()` | Bool | Empty? |

Use `??` operator for safe unwrap with default: `opt_val ?? "default"`

Use `?` operator to propagate None: `let val = opt_fn()?` (in Option-returning fn)

## Result[T, E] Methods

| Method | Returns | Purpose |
|--------|---------|---------|
| `.unwrap()` | T | Extract Ok value (panics on Err) |
| `.unwrap_err()` | E | Extract Err value (panics on Ok) |
| `.is_ok()` | Bool | Success? |
| `.is_err()` | Bool | Failure? |

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

## Instant Methods

| Method | Returns | Purpose |
|--------|---------|---------|
| `time.read()` | Instant | Current time |
| `Instant.from_epoch_secs(n)` | Instant | From unix timestamp |
| `.elapsed()` | Duration | Time since this instant |
| `.since(other)` | Duration | Difference between instants |
| `.add(dur)` | Instant | Add duration |
| `.to_unix_ms()` | Int | As unix milliseconds |
| `.to_unix_secs()` | Int | As unix seconds |
| `.to_rfc3339()` | Str | ISO-8601 formatted string |

```blink
let start = time.read()
// ... work ...
let elapsed = start.elapsed()
io.println("Took {elapsed.to_ms()} ms")

let d = Duration.seconds(5)
time.sleep(d)
```

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
| `json_set(obj, key, val)` | Void | Set key-value on object (add or replace) |
| `json_push(arr, val)` | Void | Append value to array |
| `json_remove(obj, key)` | Void | Remove key from object |
| `json_clear()` | Void | Reset all JSON state for next parse |

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

**Qualified access:** `import auth` enables qualified access only — `auth.login()`, `auth.Token`, `auth.MAX_RETRIES`. Bare (unqualified) names like `login()` require selective imports (`import auth.{login}`). Only the leaf module name works as qualifier (`num.parse_int()`, not `std.num.parse_int()`). Local variables shadow module names.

Selective imports (`import mod.{a, b}`) restrict which *unqualified* items are visible — unselected items produce a compile error for bare names, but qualified access (`mod.item`) still works. Aliases (`as`) rename the item at the import site; the original name is no longer accessible. When two modules export the same name and both are imported without selection, the compiler emits an ambiguity error — use qualified access (`foo.name()` vs `bar.name()`) or selective imports to disambiguate.

## Annotations (ordered)

| Annotation | Target | Purpose |
|------------|--------|---------|
| `@module(name)` | module | Module declaration |
| `@capabilities(...)` | module | Effect ceiling |
| `@derive(...)` | type | Auto-generate traits (Serialize, Deserialize, Eq, Ord, Hash, Debug, Clone, Display) |
| `@src(req)` | fn | Requirement traceability |
| `@requires(expr)` | fn | Precondition |
| `@ensures(expr)` | fn | Postcondition (`result` = return value) |
| `@where(expr)` | fn, type | Type constraint |
| `@invariant(expr)` | type | Type invariant |
| `@ffi("lib", "sym")` | fn | FFI binding — link to C function |
| `@trusted` | fn | FFI audit marker — function reviewed for safety |
| `@allow(W0600)` | fn, type | Suppress specific diagnostic warning |
| `@deprecated(msg)` | fn, type | Deprecation warning. Optional: `since`, `removal`, `replacement`, `fix` fields |

## Common Patterns

```blink
// Read + process file
let content = read_file("data.txt")
let lines = content.split("\n")
for line in lines {
    if line.contains("TODO") {
        io.println("Found: {line}")
    }
}

// Error handling chain
fn load_config(path: Str) -> Result[Config, Str] {
    if file_exists(path) == 0 {
        return Err("config not found")
    }
    let json = read_file(path)
    Config.from_json(json)
}
let config = load_config("config.json")?

// Build output with list
let mut parts: List[Str] = []
parts.push("header")
parts.push("body")
let output = parts.join("\n")
write_file("out.txt", output)

// Map usage
let mut scores: Map[Str, Int] = Map()
scores["alice"] = 95
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

## Closeable Trait & `with`-`as` Blocks

Types that implement `Closeable` (from `std.traits`) can be used in `with`-`as` blocks for automatic resource cleanup. `close()` is called on scope exit, including early exits (break, return, error propagation).

```blink
import std.traits

impl Closeable for MyResource {
    fn close(self) {
        // cleanup logic
    }
}

// Single resource — close() called on scope exit
with open_resource("file.txt") as f {
    io.println("using: {f.name}")
}
// f.close() called here automatically

// Multiple resources — close() called in reverse order (b, then a)
with open_resource("a") as a, open_resource("b") as b {
    io.println("using: {a.name} and {b.name}")
}
// b.close() called first, then a.close()
```

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

## Associated Types on Traits

Traits can declare associated type members with `type Name`. Implementers must define these types.

```blink
trait BlockHandler {
    type Context                    // associated type declaration
    fn enter(self) -> Self.Context  // used in method signatures
    fn exit(self, ok: Bool)
}

impl BlockHandler for Transaction {
    type Context = Void             // implementer defines the type
    fn enter(self) -> Void { ... }
    fn exit(self, ok: Bool) { ... }
}
```

## Standard Library

| Module | Description | Example |
|--------|-------------|---------|
| `std.args` | CLI argument parsing (flags, options, commands) | `import std.args` |
| `std.arena` | Arena introspection: `bytes_used()` returns live bytes in the innermost active `with arena { }` block | `import std.arena` |
| `std.db` | SQLite database with effect-based API (`DB.Read`, `DB.Write`), `Template[DB]` parameterization, `Row`, `Stmt`, `DBError`, transactions | `import std.db` |
| `std.http` | HTTP client and server | `import std.http` |
| `std.json` | JSON parser and serializer | `import std.json` |
| `std.net` | TCP networking: `TcpSocket`, `TcpListener`, `NetError` (`Timeout`, `ConnectionRefused`, `DnsFailure`, `TlsError`, `InvalidUrl`, `BindError`, `ProtocolError`, `IoError`), `tcp_listen`, `tcp_connect`, `tcp_accept`, `tcp_read`, `tcp_write`, `tcp_read_bytes`, `tcp_write_bytes` | `import std.net` |
| `std.path` | Path utilities: `path_join(a, b)`, `path_dirname(path)`, `path_basename(path)` | `import std.path` |
| `std.semver` | Semantic version parsing and constraints | `import std.semver` |
| `std.testing` | Test helpers: `capture_log`, `capture_print`, `capture_eprint` — handler factories that intercept IO for assertions | `import std.testing` |
| `std.term` | Terminal styling and control: ANSI colors (`red`, `green`, `blue`, etc.), text styles (`bold`, `dim`, `italic`, `underline`, `strikethrough`), background colors, TTY detection (`is_tty`, `terminal_width`, `terminal_height`), cursor control (`move_up`, `clear_screen`, `hide_cursor`, etc.) | `import std.term` |
| `std.toml` | TOML parser | `import std.toml` |

### Prelude Modules (auto-imported, no `import` needed)

| Module | Functions |
|--------|-----------|
| `std.str` | `str_split`, `str_join`, `str_replace`, `str_lines`, `str_trim`, `str_to_upper`, `str_to_lower`, `json_escape_str` |
| `std.list` | `list_map[T,U]`, `list_filter[T]`, `list_fold[T,U]`, `list_any[T]`, `list_all[T]`, `list_for_each[T]`, `list_concat[T]`, `list_slice[T]` |
| `std.map` | `map_for_each[V]`, `map_filter[V]`, `map_fold[V,U]`, `map_map_values[V,U]`, `map_merge[V]` |
| `std.num` | `parse_int`, `parse_float`, `int_to_str`, `float_to_str` |
| `std.sb` | StringBuilder extensions |
| `std.bytes` | Bytes type operations |
| `std.time` | Duration/Instant constructors and methods |
| `std.traits` | Core traits: `Closeable`, `BlockHandler`, `Sized`, `Contains`, `StrOps`, `ListOps`, `MapOps`, `SetOps`, `BytesOps`, `StringBuildOps`, `Joinable` |

Run `blink doc <module>` for full documentation (e.g. `blink doc std.args`).
Run `blink doc --list` to list available modules.

## Gotchas

- `{}` is NOT an empty map — use `Map()`. `{}` in expression position is a compile error. Similarly, use `Set()` for empty sets.
- `file_exists()` returns `Int` (0/1), not `Bool` — use `== 1` or `== 0`
- `is_dir()` also returns `Int`, not `Bool`
- `shell_exec()` returns exit code (Int), not stdout — use `process_run()` for output capture
- No `return` needed for last expression in function body
- `match` must be exhaustive — cover all variants or use `_ =>` wildcard
- List patterns in `match` ALWAYS need a wildcard `_` or rest `...` arm — finite patterns can't cover unbounded lists
- `let mut` required for any variable you want to reassign
- Function args separated by commas in calls, but by newlines in multi-line definitions
- `assert`, `assert_eq`, `assert_ne` only available inside `test` blocks and debug mode

## Build & Run

```sh
bin/blink build src/main.bl     # compile to build/main
bin/blink run src/main.bl       # compile + run
bin/blink test                    # discover + run all test blocks
bin/blink check src/main.bl     # typecheck without compiling
bin/blink fmt src/main.bl       # format in place
bin/blink doc --list              # list available stdlib modules
bin/blink doc std.args            # print module documentation
bin/blink doc std.json --json     # module docs as JSON
bin/blink audit src/main.bl     # FFI audit report
bin/blink update                  # update deps + blink-version in blink.toml

# Release builds (optimized with -O2)
bin/blink build src/main.bl --release
bin/blink build src/main.bl -R

# Cross-compilation (single target)
bin/blink build src/main.bl --target linux
bin/blink build src/main.bl -T macos-arm64

# Multi-target builds (compile to C once, link per target)
bin/blink build src/main.bl -T linux -T macos-arm64
# Produces: build/main-linux, build/main-macos-arm64

# Combined
bin/blink build src/main.bl --release -T linux -T macos-arm64
# Aliases: linux, linux-arm64, macos, macos-arm64, macos-amd64
# Also accepts raw zig target triples: x86_64-linux-gnu, aarch64-macos, etc.
```

### Compiler Daemon

The compiler daemon is a persistent background process that maintains a live dependency graph with file watching and incremental recheck. When running, `blink check` and `blink query` use it automatically for faster responses.

```sh
# Start daemon for a project (watches for file changes)
blink daemon start src/main.bl

# Check status and stop
blink daemon status      # uptime, memory, graph size
blink daemon stop

# These commands use the daemon automatically when it's running:
blink check src/auth.bl  # incremental recheck (sub-200ms for single function changes)
blink query src/auth.bl  # symbol lookup from cached index
```

Start the daemon at the beginning of iterative development sessions for significantly faster feedback loops.

### Debugging & Inspection Flags

```sh
# Debug builds (debug_assert enabled, -g -O0)
bin/blink build src/main.bl --debug
bin/blink build src/main.bl -d

# AST dump (JSON) — inspect parsed syntax tree
bin/blink ast src/main.bl                    # full AST as JSON
bin/blink ast src/main.bl --imports          # resolve imports, show merged AST
bin/blink ast src/main.bl --node 42          # dump subtree for node ID 42

# Compiler phase tracing — trace lex/parse/typecheck/codegen phases
bin/blink build src/main.bl --blink-trace all
bin/blink build src/main.bl --blink-trace parse    # single phase

# Treat warnings as errors
bin/blink build src/main.bl --strict
```

### Runtime Execution Tracing (`--trace`)

Emits structured NDJSON to stderr with function enter/exit, state mutations, and effect invocations. Zero cost when not enabled.

```sh
# Trace everything
bin/blink run app.bl --trace all

# Filter by function, module, or depth
bin/blink run app.bl --trace "fn:parse_expr"
bin/blink run app.bl --trace "module:parser,depth:2"
bin/blink run app.bl --trace "fn:skip_ws+parse_block"   # OR with +

# Filter by event type
bin/blink run app.bl --trace "event:enter+exit"          # only enter/exit
bin/blink run app.bl --trace "event:effect"              # only effect invocations
bin/blink run app.bl --trace "event:state"               # only state mutations

# Filter by effect or state variable
bin/blink run app.bl --trace "effect:FS.Write"
bin/blink run app.bl --trace "state:count"

# Cap output to N events
bin/blink run app.bl --trace all --trace-limit 100

# Environment variable (same filter syntax)
BLINK_TRACE=all bin/blink run app.bl
BLINK_TRACE_LIMIT=50 BLINK_TRACE=all bin/blink run app.bl
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
