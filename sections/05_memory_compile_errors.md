## 5. Memory Management

### 5.1 Tracing GC as Default

Pact uses a modern tracing garbage collector as its default memory management strategy. The GC is generational, concurrent, and optimized for low pause times (sub-millisecond target).

The programmer does not think about memory. There are no lifetime annotations, no ownership transfers, no borrow checker. You allocate, you use, the runtime cleans up.

```pact
fn process_request(req: Request) -> Response ! DB, IO {
    let user = db.find_user(req.user_id)?
    let items = db.get_items(user.id)?
    let summary = build_summary(items)     // allocated on heap, GC manages it
    io.println("Processed {items.len()} items")
    Response.ok(summary)
}
```

No annotation on `summary`. No `Box`, `Rc`, `Arc`. No `&'a`. It just works.

**Why not ownership/borrowing (Rust-style):**

1. **AI fails the borrow checker.** LLMs produce incorrect lifetime annotations 30-40% of the time in non-trivial code. The fix loops diverge -- the AI fights the compiler, tries random lifetime permutations, and burns tokens without converging. This directly violates "optimize the generate-compile-check-fix loop."

2. **Algebraic effects and ownership interact badly.** Effect handlers capture continuations that hold references. Tracking lifetime variance across effect handler boundaries turns every effectful function into a lifetime puzzle. The effect system is more important to Pact's identity than manual memory control.

3. **Cognitive overhead destroys locality.** A function with three lifetime parameters requires understanding the lifetime relationships of its entire call graph. This is the opposite of "a function's behavior is determinable from its signature."

4. **GC is proven at scale.** Go serves millions of RPS with sub-millisecond GC pauses. Discord moved from Go to Rust for specific tail-latency reasons -- most services never hit that bar. Java runs the world's financial infrastructure. The "GC is slow" argument died somewhere around 2015.

5. **Deterministic resource cleanup is orthogonal to GC.** File handles, sockets, database connections -- these are managed through the `Closeable` trait and `with...as` scoped resource blocks, not GC finalization. The GC manages memory. `Closeable` manages resources. See section 5.5.

### 5.2 Opt-in Arenas via the Arena Effect

For hot paths where GC pressure is measurable and problematic, Pact provides arena allocation as an effect:

```pact
fn process_batch(items: List[Item]) -> Summary ! Arena {
    // All allocations inside this function use the arena.
    // The arena is freed in one shot when the effect handler scope ends.
    let transformed = items.map(fn(i) { transform(i) })
    let filtered = transformed.filter(fn(t) { t.score > threshold })
    summarize(filtered)
}

fn main() {
    let items = load_items()
    // The `with arena` handler creates the arena and frees it on scope exit.
    let summary = with arena {
        process_batch(items)
    }
    io.println(summary.display())
}
```

Arena rules:

- Arena-allocated values **cannot escape** their arena scope. The compiler enforces this statically.
- If a value must outlive the arena, it is automatically promoted to the GC heap at the handler boundary (the return value of the `with arena` block).
- Arena allocation is a **local decision**. It does not infect calling code with annotations. The caller sees `process_batch` returns `Summary` -- it doesn't care how memory was managed internally.

```pact
fn bad_example() -> List[Item] ! Arena {
    let temp = Item.new("ephemeral")
    [temp]  // OK: the list is the return value, promoted to GC heap at handler boundary
}

fn worse_example() ! Arena {
    let leaked = Item.new("trouble")
    some_global_cache.store(leaked)
    // COMPILE ERROR: arena-allocated value `leaked` escapes via `some_global_cache`
}
```

```
error[E0700]: arena-scoped value escapes
 --> batch.pact:3:5
  |
3 |     some_global_cache.store(leaked)
  |                             ^^^^^^ `leaked` is arena-allocated and cannot escape
  |
  = note: arena values are freed when the arena scope exits
  = fix: remove `! Arena` and let the value be GC-managed, or copy the value explicitly:
  |
3 |     some_global_cache.store(leaked.clone())
  |                                   ++++++++
```

### 5.3 Compiler-Driven Optimization

The compiler performs several optimizations that reduce GC pressure without programmer intervention:

**Escape analysis:** Values proven not to escape a function are stack-allocated. No GC involvement. This is invisible to the programmer but handles the common case of temporary values.

```pact
fn distance(a: Point, b: Point) -> Float {
    let dx = a.x - b.x   // stack-allocated, never escapes
    let dy = a.y - b.y   // stack-allocated, never escapes
    math.sqrt(dx * dx + dy * dy)
}
```

**Region inference:** The compiler identifies groups of allocations with correlated lifetimes and batches their deallocation. Within a loop body, temporaries created per iteration are freed together rather than individually traced.

```pact
fn process_all(items: List[Item]) -> List[Result] {
    items.map(fn(item) {
        // The compiler infers that `parsed`, `validated`, and `enriched`
        // all die at the end of this closure. They are batch-freed.
        let parsed = parse(item)
        let validated = validate(parsed)
        let enriched = enrich(validated)
        enriched.to_result()
    })
}
```

**Generational hypothesis:** Short-lived objects (most objects) are collected cheaply in the young generation. Long-lived objects are promoted to old generation and collected infrequently. The effect system provides scope information that helps the GC tune generation boundaries.

### 5.5 Deterministic Resource Cleanup: `Closeable` + `with...as`

The GC handles memory. But file handles, sockets, locks, database cursors, and temp files need deterministic cleanup — released at a specific program point, not whenever the GC runs a finalizer.

Pact solves this with two pieces: the `Closeable` trait (section 3.6) and the `with...as` syntax (section 2.17).

#### The `Closeable` trait

```pact
trait Closeable {
    fn close(self)
}
```

Any type holding non-memory resources implements `Closeable`. The compiler knows this trait and uses it to power diagnostics and the `with...as` construct.

#### `with...as` desugaring

```pact
with expr as name { body }
```

Desugars to:

```pact
{
    let name = expr
    let __result = { body }
    name.close()
    __result
}
```

The compiler inserts `name.close()` on **all** exit paths: normal completion, `?` early return, and any other control flow that leaves the block.

#### Multiple resources

```pact
with expr1 as a, expr2 as b { body }
```

Cleanup is LIFO — `b.close()` runs before `a.close()`. If `expr2` fails (via `?`), only `a` is cleaned up. The `?` in the expression propagates **before** the scope is entered — if acquisition fails, no cleanup is needed for that binding.

#### Compiler diagnostics

**W0600: `Closeable` value used outside `with...as`**

```
warning[W0600]: `Closeable` value used without `with...as`
 --> data.pact:5:9
  |
5 |     let file = fs.open("data.txt")?
  |         ^^^^ `file` implements `Closeable` but is not in a `with...as` block
  |
  = help: wrap in `with...as` to ensure cleanup:
  |
5 |     with fs.open("data.txt")? as file {
6 |         // use file here
7 |     }
  = note: suppress with `@trusted` for manual resource management
  = note: upgrade to error in pact.toml: [lints] W0600 = "error"
```

This is a warning by default, upgradeable to a hard error via `pact.toml`. Suppressible with `@trusted` for framework code (connection pools, resource managers) that deliberately manages `Closeable` lifetimes manually.

**E0601: closeable escapes scope**

```
error[E0601]: `Closeable` value escapes `with...as` scope
 --> handler.pact:8:12
  |
6 |     with fs.open("data.txt")? as file {
  |                                   ---- `file` is scoped here
7 |         cache.store(file)
  |                     ^^^^ `file` cannot escape this scope
  |
  = note: `file.close()` will run when this block exits
  = fix: extract the data you need instead of storing the handle:
  |
7 |         cache.store(fs.read(file)?)
  |                     ++++++++++++++
```

Analogous to arena escape (E0700 in section 5.2). A `Closeable` binding cannot be returned from its `with` block or stored anywhere that outlives the block.

**E0602: closeable stored in field or collection**

```
error[E0602]: `Closeable` value stored in collection
 --> pool.pact:12:9
  |
10|     with db.open_cursor(query)? as cursor {
   |                                    ------ `cursor` is scoped here
11|         let results = []
12|         results.push(cursor)
   |                      ^^^^^^ cannot store `Closeable` in collection
   |
   = note: storing in a collection could allow the value to escape
   = fix: extract data from the cursor instead:
   |
12|         results.push(cursor.next()?)
```

These three diagnostics form a closed net: W0600 catches forgotten `with...as`, E0601 catches escape via return or assignment, E0602 catches escape via collections. Together they ensure `Closeable` values are always scoped and always cleaned up.

### 5.6 Future: Compiler Optimization Improvements

The GC-first design leaves room for the compiler to get smarter over time without changing the language:

- **Profile-guided arena insertion:** The compiler could automatically insert arena allocation for functions that show high allocation rates in profiling data, without the programmer adding `! Arena`.
- **Escape analysis improvements:** More aggressive interprocedural escape analysis could stack-allocate values that pass through multiple functions but never truly escape.
- **Value types:** Small, immutable structs could be passed by value (unboxed) rather than heap-allocated. The compiler can make this decision based on size and usage patterns.
- **GC tuning per effect scope:** Different effect handlers could configure GC behavior -- e.g., a request handler scope could use a bump allocator that bulk-frees on scope exit.

None of these changes require language syntax changes. The programmer writes the same code. The compiler gets smarter underneath.

---

## 6. Compilation

### 6.1 AOT Native Compilation

Pact compiles ahead-of-time to a single static binary. No VM, no runtime dependency, no "install this first."

```sh
$ pact build
# Produces: ./myapp (single static binary, ~10-20MB)

$ file ./myapp
myapp: ELF 64-bit LSB executable, x86-64, statically linked

$ ./myapp
Hello, world!
```

**Why AOT native:**

1. **Single binary deployment.** Copy one file. Run it. No JVM, no .NET runtime, no Python interpreter, no node_modules. Ops teams want `scp myapp server:` and done. Container images are a single `FROM scratch` + `COPY myapp`.

2. **Algebraic effects compile well to native code.** Effect handlers are implemented via direct stack manipulation -- segmented stacks or continuation-passing. This is natural in native code and painful on a VM that wasn't designed for delimited continuations (see: Project Loom's multi-year slog).

3. **Predictable performance.** No JIT warmup curve. The first request is as fast as the millionth. An AI agent cannot distinguish "slow because JIT is warming up" from "slow because the generated code is buggy." Nondeterminism in performance is noise that wastes AI iteration cycles.

4. **Fast startup.** Milliseconds, not seconds. Critical for CLI tools, serverless functions, autoscaling events. A JVM-based language starts with a 2-5 second tax before your code runs.

5. **Small footprint.** 10-20MB static binary vs. 200MB+ with a bundled runtime. In a cold-start autoscaling event, container pull time is deployment latency. Smaller image = faster scale-out.

**Why not bytecode + VM:**

- The JVM and CLR were not designed for algebraic effects. Bolting delimited continuations onto an existing VM is an engineering nightmare.
- Bytecode portability is a 1990s selling point. Modern deployment is Linux containers on amd64 or arm64. Cross-compile both and ship a multi-arch image. Problem solved.
- A VM adds runtime size, startup latency, and operational complexity (GC tuning, JIT configuration, classloader debugging).

**Why not JIT:**

- Two compilation pipelines means two sets of optimization bugs and two performance profiles to reason about.
- JIT warmup introduces nondeterminism. "It's slow for the first 10 requests then fast" is not acceptable for latency-sensitive services or AI-assisted profiling.
- Julia's time-to-first-call problem is infamous. Pact's compiler-as-service architecture provides fast iteration without a JIT.

### 6.2 `pact eval` Interpreter Mode

For development and AI iteration loops, Pact includes an AST-walking interpreter that executes code directly without codegen:

```sh
$ pact eval 'add(2, 3)'
5

$ pact eval 'process_order(42)' --effects mock
{
  "result": "Ok(Receipt { order_id: 42, total: 99.50 })",
  "effects_observed": ["DB.read", "IO.write"],
  "effects_declared": ["DB", "IO"],
  "allocations": "1.2KB"
}
```

`pact eval` enforces the full type system and effect tracking. It is not a shortcut around safety -- it is a faster path to the same guarantees.

**Use cases:**

- **AI iteration loops.** Generate a function, eval it, check the output, fix, repeat. No waiting for full AOT compilation.
- **REPL-like exploration.** Test expressions, inspect types, experiment with APIs.
- **Test execution during development.** Run tests against the interpreter for instant feedback. CI runs them against the AOT binary for production confidence.

**What `pact eval` is not:**

- Not a production runtime. Production is always AOT-compiled native binaries.
- Not a separate language. The same code runs under both eval and AOT. If it type-checks, it runs the same either way (modulo performance).

### 6.3 Compiler-as-Service Daemon Architecture

The Pact compiler runs as a persistent daemon process that maintains an incremental compilation state:

```
┌─────────────────────────────────────────────┐
│               pact daemon                    │
│                                              │
│  ┌──────────┐  ┌──────────┐  ┌───────────┐  │
│  │ Incremental│  │   LSP    │  │ Structured│  │
│  │ Dependency │  │  Server  │  │ Diagnostic│  │
│  │   Graph    │  │          │  │  Emitter  │  │
│  └──────────┘  └──────────┘  └───────────┘  │
│        │              │              │        │
│  Symbol-level    Completions     JSON with    │
│  granularity     Hover info    machine fixes  │
│                  Refactoring                  │
└─────────────────────────────────────────────┘
          │                    │
     IDE / Editor         AI Agent
     (human-facing)    (machine-facing)
```

**Key properties:**

- **Symbol-level incremental compilation.** The dependency graph tracks individual functions, types, and traits -- not files. Changing one function only retypechecks that function and its direct dependents.
- **Target: sub-200ms incremental type-check** for a single changed function. This is the critical number -- the AI's generate-compile-check-fix loop runs at the speed of the compiler.
- **Unified with LSP.** The compiler daemon IS the language server. Completions, hover info, go-to-definition, and refactoring are not a separate tool -- they are the same compiler answering different questions.
- **File watching built in.** The daemon watches source files and keeps its internal state current. Queries against a stale state are impossible.

### 6.4 Structured Diagnostics

All compiler output is structured JSON with error codes, source spans, human-readable messages, and machine-applicable fixes.

```json
{
  "diagnostics": [
    {
      "severity": "error",
      "code": "E0004",
      "message": "non-exhaustive match",
      "span": {
        "file": "order.pact",
        "start": { "line": 12, "col": 5 },
        "end": { "line": 12, "col": 10 }
      },
      "labels": [
        {
          "span": { "line": 12, "col": 5, "len": 5 },
          "message": "missing pattern: `Cancelled`"
        }
      ],
      "help": "add arm: `Cancelled => <expr>`",
      "fix": {
        "description": "Add missing match arm for `Cancelled`",
        "edits": [
          {
            "file": "order.pact",
            "span": { "start": { "line": 16, "col": 0 }, "end": { "line": 16, "col": 0 } },
            "insert": "        Cancelled => todo()\n"
          }
        ]
      },
      "related": [
        {
          "message": "`Cancelled` variant defined here",
          "span": { "file": "types.pact", "line": 8, "col": 5 }
        }
      ]
    }
  ]
}
```

Every diagnostic includes:

| Field | Purpose |
|-------|---------|
| `code` | Stable, searchable error code. `E0004` always means non-exhaustive match. |
| `span` | Exact source location -- file, line, column, length. |
| `message` | Human-readable description of the problem. |
| `help` | Short suggestion text. |
| `fix.edits` | Machine-applicable edits. The AI reads this array and applies the insertions/replacements directly. No parsing, no guessing. |
| `related` | Links to the declaration or definition that caused the error. |

The AI workflow:

1. AI generates or modifies code.
2. AI calls `pact check --format json`.
3. If diagnostics come back, the AI reads `fix.edits` from each diagnostic.
4. AI applies the edits.
5. Repeat until zero diagnostics.

This loop is mechanical. The AI does not need to "understand" the error -- it applies the compiler's suggested fix. When the fix is not mechanical (no `fix.edits` provided), the `help` text and `related` spans give the AI enough context to reason about a solution.

### 6.5 CLI Commands

| Command | Description | Output |
|---------|-------------|--------|
| `pact build` | AOT compile to native binary | `./myapp` static binary |
| `pact build --target arm64` | Cross-compile | `./myapp` for target arch |
| `pact run` | Compile + execute in one step | Program output |
| `pact check` | Type-check without codegen | Structured diagnostics (JSON) |
| `pact check --format json` | Machine-readable type-check | JSON diagnostics with `fix.edits` |
| `pact eval <expr>` | Interpret expression | Result + effect/allocation report |
| `pact verify` | SMT-based contract verification | Proof results per contract |
| `pact test` | Run all tests | Structured test results (JSON) |
| `pact test --filter "name"` | Run matching tests | Filtered test results |
| `pact fmt` | Format to canonical style | Reformatted files (in-place) |
| `pact daemon` | Start compiler daemon | Persistent process (LSP + incremental) |

All commands that produce diagnostics support `--format json` for machine consumption. The human-readable format is the default for terminal use; the JSON format is the default when stdout is not a TTY (pipe detection).

---

## 7. Error Handling

### 7.1 No Exceptions

Pact has no exceptions, no `try`, no `catch`, no `finally`, no `throw`. All error handling uses values and types.

**Why:**

1. **Exceptions are invisible control flow.** A function signature `fn process(data: Str) -> Report` tells you nothing about whether it might throw `IOException`, `ParseException`, `ValidationError`, or any other exception. You have to read the body -- and every function it calls, transitively -- to know. This violates locality of reasoning. For an AI with a finite context window, this means loading potentially the entire call graph to understand error behavior.

2. **Exception handling is a footgun for AI.** LLMs generate incorrect `try`/`catch` blocks at high rates: catching too broadly (`catch Exception`), catching in the wrong order, forgetting cleanup in `finally`, swallowing errors silently. The `?` operator is one character with exactly one meaning.

3. **`Result[T, E]` makes errors visible in the type signature.** When you see `-> Result[Config, ParseError]`, you know this function can fail, you know how it can fail, and the compiler enforces that you handle it. No surprises.

4. **Effect handlers already replace the useful part of exceptions.** The "throw and catch at a distance" pattern that exceptions enable is handled by effect handlers in Pact -- but with the effect declared in the type signature, making it visible.

### 7.2 Result Type and `?` Operator

```pact
type Result[T, E] {
    Ok(T)
    Err(E)
}
```

Functions that can fail return `Result`:

```pact
fn read_config(path: Str) -> Result[Config, ConfigError] ! IO {
    let text = io.read_file(path)?        // returns Err(IOError) on failure
    let parsed = toml.parse(text)?        // returns Err(ParseError) on failure
    let config = validate(parsed)?        // returns Err(ValidationError) on failure
    Ok(config)
}
```

The `?` operator desugars to:

```pact
// `let text = io.read_file(path)?` becomes:
let text = match io.read_file(path) {
    Ok(val) => val
    Err(e) => return Err(e)
}
```

The `?` operator requires the error type to **match exactly** — there is no implicit conversion. When the callee's error type differs from the function's declared error type, convert explicitly with `.map_err()` and `From`:

```pact
type ConfigError {
    IO(IOError)
    Parse(ParseError)
    Validation(ValidationError)
}

impl From[IOError] for ConfigError {
    fn from(e: IOError) -> ConfigError { ConfigError.IO(e) }
}

impl From[ParseError] for ConfigError {
    fn from(e: ParseError) -> ConfigError { ConfigError.Parse(e) }
}

impl From[ValidationError] for ConfigError {
    fn from(e: ValidationError) -> ConfigError { ConfigError.Validation(e) }
}

// Explicit error conversion at each ? site
fn read_config(path: Str) -> Result[Config, ConfigError] ! IO {
    let text = io.read_file(path)
        .map_err(fn(e) { ConfigError.from(e) })?
    let parsed = toml.parse(text)
        .map_err(fn(e) { ConfigError.from(e) })?
    validate(parsed)
        .map_err(fn(e) { ConfigError.from(e) })?
    Ok(parsed)
}
```

**Matching on Result:**

```pact
match read_config("app.toml") {
    Ok(config) => start_server(config)
    Err(ConfigError.IO(e)) => io.println("Can't read config: {e}")
    Err(ConfigError.Parse(e)) => io.println("Bad config syntax: {e}")
    Err(ConfigError.Validation(e)) => io.println("Invalid config: {e}")
}
```

The match is exhaustive. Add a new variant to `ConfigError` and the compiler tells you everywhere you forgot to handle it.

### 7.3 Option Type and `??` Operator

```pact
type Option[T] {
    Some(T)
    None
}
```

`Option` is for the absence of a value -- not an error, just "nothing here."

```pact
fn find_user(id: Int) -> Option[User] ! DB {
    db.query_one("SELECT * FROM users WHERE id = {id}")
}
```

The `??` operator provides a default when the value is `None`:

```pact
let name = user.nickname ?? user.full_name ?? "Anonymous"
```

This desugars to nested match:

```pact
let name = match user.nickname {
    Some(n) => n
    None => match user.full_name {
        Some(f) => f
        None => "Anonymous"
    }
}
```

`T?` is sugar for `Option[T]` in type position:

```pact
type UserProfile {
    name: Str
    bio: Str?        // Option[Str]
    avatar_url: Str?  // Option[Str]
}
```

**Combining `?` and `??`:**

```pact
// `?` propagates Result errors, `??` defaults Option values
fn get_display_name(user_id: Int) -> Result[Str, DBError] ! DB {
    let user = db.find_user(user_id)?          // propagate DBError
    let name = user.nickname ?? user.email      // default if no nickname
    Ok(name)
}
```

### 7.4 Error Propagation Examples

**Simple propagation through a call chain:**

```pact
type AppError {
    DB(DBError)
    Net(NetError)
    Parse(ParseError)
}

fn fetch_weather(city: Str) -> Result[Weather, AppError] ! Net {
    let response = net.get("https://api.weather.com/{city}")?
    let weather = json.parse[Weather](response.body)?
    Ok(weather)
}

fn fetch_and_store(city: Str) -> Result[(), AppError] ! Net, DB {
    let weather = fetch_weather(city)?
    db.insert("weather", weather)?
    Ok(())
}

fn update_all_cities() -> Result[Int, AppError] ! Net, DB, IO {
    let cities = db.query[Str]("SELECT name FROM cities")?
    let mut count = 0
    for city in cities {
        fetch_and_store(city)?
        count = count + 1
    }
    io.println("Updated {count} cities")
    Ok(count)
}
```

**Handling errors at the boundary:**

```pact
fn main() {
    match update_all_cities() {
        Ok(n) => io.println("Done. Updated {n} cities.")
        Err(AppError.DB(e)) => {
            io.eprintln("Database error: {e}")
            env.exit(1)
        }
        Err(AppError.Net(e)) => {
            io.eprintln("Network error: {e}")
            env.exit(2)
        }
        Err(AppError.Parse(e)) => {
            io.eprintln("Parse error: {e}")
            env.exit(3)
        }
    }
}
```

**Partial error handling (handle some, propagate others):**

```pact
fn resilient_fetch(city: Str) -> Result[Weather?, AppError] ! Net, IO {
    match fetch_weather(city) {
        Ok(w) => Ok(Some(w))
        Err(AppError.Net(_)) => {
            io.println("Network error for {city}, skipping")
            Ok(None)
        }
        Err(e) => Err(e)  // propagate DB and Parse errors
    }
}
```

Errors are values. They compose, propagate, and pattern-match like any other value. Every error path is visible in the type signature. The compiler enforces exhaustive handling. The AI never has to guess what can go wrong.
