# Pact Language Reference

> Pact is a statically-typed, effect-tracked language compiling to C. Language spec v0.3. Self-hosting compiler.

**CRITICAL — Read before writing any Pact code:**
- `fn` keyword, `{ }` braces, NO semicolons — newlines separate statements
- `"double quotes"` ONLY — no single quotes for strings
- Universal string interpolation: `"Hello, {name}!"` — every string supports `{expr}`
- `io.println(...)` NOT `print(...)` — IO goes through effect handles
- NO `+` on strings — use interpolation `"{a}{b}"` or `.concat()`
- Square bracket generics: `List[T]` NOT `List<T>`
- Method calls always: `x.len()` NOT `x.len` (no properties)
- `main` has implicit effects — no annotation needed on `fn main()`

## Syntax Quick Reference

```pact
// Variables
let x = 42                       // immutable
let mut count = 0                // mutable
let name: Str = "Alice"          // type annotation

// Functions
fn add(a: Int, b: Int) -> Int {
    a + b                        // last expression is return value
}

fn greet(name: Str) ! IO {       // ! declares effects
    io.println("Hello, {name}!")
}

// Closures
let double = fn(x: Int) -> Int { x * 2 }
numbers.map(fn(x) { x * 2 })

// Structs
type Point { x: Float, y: Float }
let p = Point { x: 1.0, y: 2.0 }
io.println("x={p.x}")

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
| Bool | `true`, `false` | Boolean |
| List[T] | `[1, 2, 3]` | Dynamic array |
| Map[K, V] | `Map()` | Hash map (construct with `Map()`, not `{}`) |
| Option[T] | `Some(v)`, `None` | Nullable value |
| Result[T, E] | `Ok(v)`, `Err(e)` | Error-or-value |
| Bytes | `Bytes.new()` | Byte buffer |
| Instant | `time.read()` | Point in time |
| Duration | `Duration.ms(100)` | Time span |

## Escape Sequences

| Escape | Produces |
|--------|----------|
| `\n` | newline |
| `\r` | carriage return |
| `\t` | tab |
| `\\` | literal `\` |
| `\"` | literal `"` |
| `\{` | literal `{` (suppresses interpolation) |
| `\}` | literal `}` |

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
| `path_join(a, b)` | Str | Join path components |
| `path_dirname(path)` | Str | Directory part of path |
| `path_basename(path)` | Str | Filename part of path |
| `file_mtime(path)` | Int | Modification time (ms) |
| `get_env(name)` | Option[Str] | Environment variable |
| `shell_exec(cmd)` | Int | Run shell command, return exit code |
| `process_run(cmd)` | ProcessResult | Run command, capture stdout/stderr/exit_code |
| `exit(code)` | Void | Exit with code |
| `arg_count()` | Int | CLI argument count |
| `get_arg(idx)` | Str | CLI argument by index |
| `time_ms()` | Int | Current time in milliseconds |
| `getpid()` | Int | Process ID |

## Namespace Methods

```pact
// IO (effect: IO)
io.println("text")              // print + newline to stdout
io.print("text")                // print without newline
io.eprintln("error")            // print to stderr
io.log("debug info")            // stderr with [LOG] prefix

// Filesystem (effect: FS)
fs.read(path)                   // -> Str
fs.write(path, content)         // -> Void
fs.list_dir(dir)                // -> List[Str] (filenames)

// Environment
env.args()                      // -> List[Str] (all CLI args)

// Time
time.read()                     // -> Instant
time.sleep(duration)            // sleep for Duration

// Async (effect: Async)
async.scope { ... }             // synchronous scope for spawned tasks
async.spawn(fn() { ... })       // spawn task, returns Handle
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
| `.trim()` | Str | Strip whitespace |
| `.to_upper()` | Str | Uppercase |
| `.to_lower()` | Str | Lowercase |
| `.replace(old, new)` | Str | Replace all occurrences |
| `.to_int()` | Int | Parse as integer |
| `.parse_float()` | Float | Parse as float |
| `.char_at(idx)` | Int | Char code at index |

## List[T] Methods

| Method | Returns | Purpose |
|--------|---------|---------|
| `.len()` | Int | Length |
| `.is_empty()` | Bool | Check if empty |
| `.push(item)` | Void | Append (mutates) |
| `.pop()` | Option[T] | Remove last |
| `.get(idx)` | T | Element at index |
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
| `.enumerate()` | Iterator[(Int,T)] | With indices |
| `.take(n)` | Iterator[T] | First n |
| `.skip(n)` | Iterator[T] | Skip first n |
| `.collect()` | List[T] | Iterator to list |

## Map[K, V] Methods

| Method | Returns | Purpose |
|--------|---------|---------|
| `Map()` | Map[K,V] | Create empty map (NOT `{}`) |
| `.set(key, val)` | Void | Insert/update |
| `.get(key)` | V | Get value (use `.has()` first) |
| `.has(key)` | Bool | Key exists? |
| `.remove(key)` | Bool | Remove key |
| `.len()` | Int | Entry count |
| `.keys()` | List[K] | All keys |
| `.values()` | List[V] | All values |

## ProcessResult Fields

```pact
let result = process_run("ls -la")
result.out          // Str — stdout
result.err_out      // Str — stderr
result.exit_code    // Int — exit code
```

## Instant & Duration

```pact
let start = time.read()
// ... work ...
let elapsed = start.elapsed()           // -> Duration
io.println("Took {elapsed.to_ms()} ms")

let t = Instant.from_epoch_secs(1700000000)
io.println(t.to_rfc3339())             // ISO-8601

let d = Duration.seconds(5)
time.sleep(d)
```

## JSON (with @derive)

```pact
@derive(Serialize, Deserialize)
type Task { id: Int, title: Str, done: Bool }

let task = Task { id: 1, title: "Test", done: false }
let json = task.to_json()                    // -> Str
let back = Task.from_json(json)              // -> Result[Task, Str]
```

## CLI Argument Parsing (std.args)

```pact
import std.args

fn main() {
    let mut p = argparser_new("myapp", "Description")
    p = add_command(p, "run", "Run the app")
    p = add_flag(p, "--verbose", "-v", "Verbose output")
    p = add_option(p, "--output", "-o", "Output file")
    p = add_positional(p, "file", "Input file")

    let a = argparse(p)
    let cmd = args_command(a)
    let verbose = args_has(a, "verbose")
    let output = args_get(a, "output")
    let file = args_positional(a, 0)
}
```

## Imports & Modules

```pact
import lexer                     // import module
import std.args                  // import stdlib module
```

Files are modules. `pub` marks items visible to importers. `import` brings `pub` items into scope.

## Annotations (ordered)

| Annotation | Target | Purpose |
|------------|--------|---------|
| `@mod(name)` | module | Module declaration |
| `@capabilities(...)` | module | Effect ceiling |
| `@derive(...)` | type | Auto-generate traits (Serialize, Deserialize, Eq, Ord, Hash, Debug, Clone, Display) |
| `@src(req)` | fn | Requirement traceability |
| `@requires(expr)` | fn | Precondition |
| `@ensures(expr)` | fn | Postcondition (`result` = return value) |
| `@where(expr)` | fn, type | Type constraint |
| `@invariant(expr)` | type | Type invariant |
| `@deprecated(msg)` | fn, type | Deprecation warning |

## Common Patterns

```pact
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
scores.set("alice", 95)
if scores.has("alice") {
    io.println("Score: {scores.get("alice")}")
}

// Process execution
let result = process_run("git rev-parse HEAD")
if result.exit_code == 0 {
    io.println("Commit: {result.out.trim()}")
}
```

## Gotchas

- `{}` is NOT an empty map — use `Map()`. `{}` in expression position is a compile error.
- `file_exists()` returns `Int` (0/1), not `Bool` — use `== 1` or `== 0`
- `is_dir()` also returns `Int`, not `Bool`
- `shell_exec()` returns exit code (Int), not stdout — use `process_run()` for output capture
- No `return` needed for last expression in function body
- `match` must be exhaustive — cover all variants or use `_ =>` wildcard
- `let mut` required for any variable you want to reassign
- Function args separated by commas in calls, but by newlines in multi-line definitions
- `assert`, `assert_eq`, `assert_ne` only available inside `test` blocks and debug mode

## Build & Run

```sh
bin/pact build src/main.pact     # compile to build/main
bin/pact run src/main.pact       # compile + run
bin/pact test                    # discover + run all test blocks
bin/pact check src/main.pact     # typecheck without compiling
bin/pact fmt src/main.pact       # format in place
```
