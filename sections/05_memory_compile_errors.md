## 5. Memory Management

### 5.1 Tracing GC as Default

Blink uses a modern tracing garbage collector as its default memory management strategy. The GC is generational, concurrent, and optimized for low pause times (sub-millisecond target).

The programmer does not think about memory. There are no lifetime annotations, no ownership transfers, no borrow checker. You allocate, you use, the runtime cleans up.

```blink
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

2. **Algebraic effects and ownership interact badly.** Effect handlers capture continuations that hold references. Tracking lifetime variance across effect handler boundaries turns every effectful function into a lifetime puzzle. The effect system is more important to Blink's identity than manual memory control.

3. **Cognitive overhead destroys locality.** A function with three lifetime parameters requires understanding the lifetime relationships of its entire call graph. This is the opposite of "a function's behavior is determinable from its signature."

4. **GC is proven at scale.** Go serves millions of RPS with sub-millisecond GC pauses. Discord moved from Go to Rust for specific tail-latency reasons -- most services never hit that bar. Java runs the world's financial infrastructure. The "GC is slow" argument died somewhere around 2015.

5. **Deterministic resource cleanup is orthogonal to GC.** File handles, sockets, database connections -- these are managed through the `Closeable` trait and `with...as` scoped resource blocks, not GC finalization. The GC manages memory. `Closeable` manages resources. See section 5.5.

### 5.2 Opt-in Arenas via the Arena Effect

For hot paths where GC pressure is measurable and problematic, Blink provides arena allocation as an effect:

```blink
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

```blink
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
error[ArenaValueEscapes]: arena-scoped value escapes
 --> batch.bl:3:5
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

#### 5.2.1 Arena Semantics

This subsection fixes the four semantic points needed to implement the arena effect: return-value promotion, escape classification, handler plumbing, and nesting. See the [Arena Allocation Semantics deliberation](../decisions/arena-allocation-semantics.md) for rationale.

##### Promotion walkers

The compiler generates a per-type promotion function `blink_promote_<Type>(value, target_allocator)` for every type that crosses a `with arena { }` boundary. The walker:

- copies the top-level value into `target_allocator` (an outer arena if one is active, otherwise the GC heap);
- recurses into pointer fields structurally (struct fields, list elements, map entries);
- copies strings via `GC_MALLOC_ATOMIC` (they are non-pointer-containing);
- rejects cyclic types at compile time with `error[E0701]: arena type contains a cycle`, since a compile-time walker cannot safely materialize a cyclic graph into another allocator.

Walkers are emitted only for types that actually cross an arena boundary in the program (detected by escape analysis), so the code-size cost scales with usage, not with the type pool.

##### Escape rule

An allocation site inside an `! Arena` function is classified as either **promoted** or **escaped**:

- **Promoted** — the value flows (possibly through `if` / `match` / early `return`) to the block's result expression. The compiler inserts a `blink_promote_<Type>` call at the `with arena` boundary.
- **Escaped** — the value flows anywhere else: captured by a closure that outlives the block, stored into a field of a non-arena-local struct, passed as an argument to a function whose parameter is not itself arena-local, or written to a module-level `let mut`. These sites produce `error[E0700]: ArenaValueEscapes` at compile time.

"Arena-local parameter" is inferred from the callee's signature: an `! Arena` function's parameters are arena-transparent for the caller's escape analysis. No region-variable annotations are required or accepted.

##### Handler plumbing

`with arena { body }` is implemented as a `BlockHandler` (§4.6.3). The block handler's `enter()` captures the prior value of the thread-local `__blink_current_arena`, installs a freshly-created `blink_arena_t*`, and returns `()`. Its `exit(ok: Bool)` restores the saved pointer and destroys the inner arena unconditionally (commit and rollback paths are identical — arena lifetime is not tied to `ok`).

`blink_alloc(size)` takes the fast path through `__blink_current_arena`:

```c
// runtime_core.h (conceptual)
static void* blink_alloc(int64_t size) {
    blink_arena_t* a = __blink_current_arena;
    if (a != NULL) return blink_arena_alloc(a, size);
    return GC_MALLOC((size_t)size);
}
```

Because the block is a `BlockHandler`, arena enter/exit events are emitted by `--blink-trace` and `--trace all` uniformly with every other block-scoped construct. `! Arena` on a function signature is a *marker* effect consumed by escape analysis; it does not participate in evidence-passing dispatch.

##### Nesting

Nested `with arena { }` blocks create independent arenas. An inner block's allocations are freed when the inner block exits; the outer arena is untouched.

```blink
fn main() {
    with arena {
        let outer_work = build_tree()
        let summary = with arena {
            // inner arena: freed when this block exits
            let temps = compute_temporaries()
            summarize(temps)  // promoted into the OUTER arena at this `}`
        }
        use_summary(summary)  // `summary` lives in the outer arena
    }  // outer arena freed here; `build_tree` + promoted `summary` both gone
}
```

Because the nearest enclosing arena is the promotion target, `blink_promote_<Type>` takes the target allocator as a parameter rather than hardcoding `GC_MALLOC`. A value promoted from the outermost `with arena` block lands in the GC heap.

##### Error codes

- `E0700 ArenaValueEscapes` — an allocation site reaches a non-return position (closure capture, field store on non-arena target, argument to a non-arena-local parameter, module-level `let mut` assignment).
- `E0701 ArenaTypeHasCycle` — a type crossing a `with arena { }` boundary contains a cycle (directly or transitively). Break the cycle or allocate the cyclic value on the GC heap outside the arena.

### 5.3 Compiler-Driven Optimization

The compiler performs several optimizations that reduce GC pressure without programmer intervention:

**Escape analysis:** Values proven not to escape a function are stack-allocated. No GC involvement. This is invisible to the programmer but handles the common case of temporary values.

```blink
fn distance(a: Point, b: Point) -> Float {
    let dx = a.x - b.x   // stack-allocated, never escapes
    let dy = a.y - b.y   // stack-allocated, never escapes
    math.sqrt(dx * dx + dy * dy)
}
```

**Region inference:** The compiler identifies groups of allocations with correlated lifetimes and batches their deallocation. Within a loop body, temporaries created per iteration are freed together rather than individually traced.

```blink
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

Blink solves this with two pieces: the `Closeable` trait (section 3.6) and the `with...as` syntax (section 2.18).

#### The `Closeable` trait

```blink
trait Closeable {
    fn close(self)
}
```

Any type holding non-memory resources implements `Closeable`. The compiler knows this trait and uses it to power diagnostics and the `with...as` construct.

#### `with...as` desugaring

```blink
with expr as name { body }
```

Desugars to:

```blink
{
    let name = expr
    let __result = { body }
    name.close()
    __result
}
```

The compiler inserts `name.close()` on **all** exit paths: normal completion, `?` early return, and any other control flow that leaves the block.

#### Multiple resources

```blink
with expr1 as a, expr2 as b { body }
```

Cleanup is LIFO — `b.close()` runs before `a.close()`. If `expr2` fails (via `?`), only `a` is cleaned up. The `?` in the expression propagates **before** the scope is entered — if acquisition fails, no cleanup is needed for that binding.

#### Compiler diagnostics

**W0600: `Closeable` value used outside `with...as`**

```
warning[CloseableWithoutScope]: `Closeable` value used without `with...as`
 --> data.bl:5:9
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
  = note: upgrade to error in blink.toml: [lints] W0600 = "error"
```

This is a warning by default, upgradeable to a hard error via `blink.toml`. Suppressible with `@trusted` for framework code (connection pools, resource managers) that deliberately manages `Closeable` lifetimes manually.

**E0601: closeable escapes scope**

```
error[CloseableEscapesScope]: `Closeable` value escapes `with...as` scope
 --> handler.bl:8:12
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
error[CloseableStoredInCollection]: `Closeable` value stored in collection
 --> pool.bl:12:9
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

Blink compiles ahead-of-time to a single static binary. No VM, no runtime dependency, no "install this first."

```sh
$ blink build
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
- Julia's time-to-first-call problem is infamous. Blink's compiler-as-service architecture provides fast iteration without a JIT.

### 6.1.1 Internal Type Representation

The compiler represents types internally as an **interned type node pool** — a flat array of type nodes, each referenced by an integer handle (`TypeId`). Type nodes carry a kind tag and up to two child `TypeId` references for parameterized types, enabling arbitrary nesting depth.

```
TypeId 0: Int
TypeId 1: Str
TypeId 2: Option[Int]     → kind=Option, child1=0
TypeId 3: List[Option[Int]] → kind=List, child1=2
```

**Key properties:**

- **Recursive:** `List[Option[Result[Int, MyError]]]` is a chain of type-id references — no depth limit, no special-casing per nesting level.
- **Interned:** Each structurally unique type exists exactly once in the pool. Type equality is integer comparison (`==` on `TypeId`), O(1).
- **Unified across passes:** Typecheck and codegen share one type pool for identity. Phase-specific metadata (C type names, constraint sets) lives in separate side tables indexed by `TypeId`.
- **Parallel-array layout:** The pool uses parallel arrays (`tp_kind`, `tp_child1`, `tp_child2`, `tp_sname`), matching the parser's AST node pool pattern. This will migrate to an enum-based representation when the compiler supports enum-with-data in lists.

See [Compiler Internal Type Representation rationale](../decisions/compiler-type-representation.md) for the full panel deliberation.

### 6.2 `blink eval` Interpreter Mode

For development and AI iteration loops, Blink includes an AST-walking interpreter that executes code directly without codegen:

```sh
$ blink eval 'add(2, 3)'
5

$ blink eval 'process_order(42)' --effects mock
{
  "result": "Ok(Receipt { order_id: 42, total: 99.50 })",
  "effects_observed": ["DB.read", "IO.write"],
  "effects_declared": ["DB", "IO"],
  "allocations": "1.2KB"
}
```

`blink eval` enforces the full type system and effect tracking. It is not a shortcut around safety -- it is a faster path to the same guarantees.

**Use cases:**

- **AI iteration loops.** Generate a function, eval it, check the output, fix, repeat. No waiting for full AOT compilation.
- **REPL-like exploration.** Test expressions, inspect types, experiment with APIs.
- **Test execution during development.** Run tests against the interpreter for instant feedback. CI runs them against the AOT binary for production confidence.

**What `blink eval` is not:**

- Not a production runtime. Production is always AOT-compiled native binaries.
- Not a separate language. The same code runs under both eval and AOT. If it type-checks, it runs the same either way (modulo performance).

### 6.3 Name Resolution

The Blink compiler performs name resolution as a dedicated phase between parsing and code generation. After imports are merged into a single AST (§10.8, emit-all model), the name resolution pass validates every identifier reference in the program before any C code is emitted.

#### 6.3.1 Compilation Phases

```
Source → Lexer → Parser → Import Merge → Name Resolution → Type Checking → Codegen → C
                                              ↓
                                    Annotated AST (decorated nodes)
```

Name resolution runs post-parse, pre-codegen. It writes results back into the AST node pool as additional parallel arrays (`np_resolved_sym`, `np_resolved_type`). Codegen reads these annotations rather than performing its own name lookups.

#### 6.3.2 Annotated AST Architecture

The name resolution pass decorates AST nodes with resolution results using new parallel arrays in the node pool. This extends the existing parallel-array architecture naturally — the same pattern as `np_type_ann`, `np_line`, `np_col`.

After name resolution:
- Every `Ident` node carries a resolved symbol reference (or an error diagnostic)
- Every `Call` node carries a resolved function reference
- Every `MethodCall` node carries a resolved trait method reference (after the type-aware phase)
- Every `StructLit` node carries a resolved type reference

Codegen reads these annotations via node index — O(1) lookup, cache-friendly, no separate symbol table query.

#### 6.3.3 Two-Phase Method Resolution

Name resolution runs in two phases within the type checking stage:

**Phase 1 — Name Binding:** Resolves variables, function calls, type references — everything that does not require type information. Builds scope chains, checks that every referenced name exists in scope, validates import visibility.

**Phase 2 — Type-Aware Method Resolution and Operator Validation:** Walks function bodies again with type information from inference. Verifies that every method call (`x.foo()`) resolves against a known trait implementation for the receiver's type. Reports E0505 (UnresolvedMethod) for methods that don't exist on the inferred type. Also validates type-dependent operators: the `?` operator is checked here — verifying the operand is `Result[T, E]` or `Option[T]`, the enclosing function's return type is compatible, and error types match exactly (§3c.2). Reports E0502, E0508, E0509, E0512 for `?` operator violations.

This separation reflects a fundamental distinction: name binding answers "does this identifier refer to something?", while method resolution answers "which implementation does this call dispatch to?" These require different information and are correctly modeled as distinct phases.

```blink
fn example(items: List[Str]) -> Int {
    let count = items.len()       // Phase 1: `items` resolves to parameter
                                  // Phase 2: `.len()` resolves to Sized.len on List[Str]
    let x = unknown_fn()          // Phase 1: E0504 — `unknown_fn` not defined
    items.nonexistent()           // Phase 2: E0505 — no method `nonexistent` on List[Str]
    count
}
```

When the receiver type is unknown after inference (TYPE_UNKNOWN), the compiler reports a specific diagnostic rather than silently accepting the call.

#### 6.3.4 Module-Scoped Symbol Table

The symbol table maintains module identity for every declaration. Each symbol is tagged with its source module, enabling:

- **`pub` enforcement** (§10.8): Using a non-pub item from outside its module produces E1003 (PrivateItemAccess)
- **Qualified error messages**: "cannot access `json.internal_parse`, it is private to module `std.json`"
- **Ambiguity detection**: Two imported modules defining the same name produces E1005 (AmbiguousImport)
- **Module-qualified C symbols**: `blink_<module>_<name>` naming requires knowing the source module

Name lookup follows standard lexical scoping priority:

1. Local bindings (let, for-loop variable, match arm bindings)
2. Function parameters
3. Enclosing closure scope (shared reference capture, §2.8)
4. Module-level declarations (fn, type, let)
5. Imported items (filtered by `pub` for cross-module access)
6. Module prelude (§10.6) — built-in types, Option/Result, compiler-known traits

Effect handles occupy a reserved namespace separate from variables (§3c.4). Attempting to shadow an effect handle name produces E0710 (EffectHandleShadowed).

#### 6.3.5 Error Recovery

Name resolution accumulates all errors across the entire program, then halts compilation before codegen. Codegen never runs on a program with unresolved names.

This clean phase gate ensures:
- Users see all name errors in a single compilation run
- Codegen only processes fully-resolved programs — no garbage C output
- Error codes E0504/E0505 in codegen become unreachable assertions

```
error[UndefinedFunction]: undefined function `fetch_users`
 --> api.bl:12:15
   |
12 |     let users = fetch_users(db)
   |                 ^^^^^^^^^^^ not found in this scope
   |
   = help: did you mean `fetch_user` (defined in auth.bl:34)?
   = help: if this is from another module, add: `import auth.{fetch_users}`
```

When a missing import causes cascading errors (one unresolved name triggers many downstream failures), the compiler applies cascade suppression: downstream references to a poison symbol suppress their own diagnostics. An error count cap (~20 errors) prevents terminal flooding.

### 6.4 Compiler-as-Service Daemon Architecture

The Blink compiler runs as a persistent daemon process that maintains an incremental compilation state:

```
┌─────────────────────────────────────────────┐
│               blink daemon                    │
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

### 6.5 Structured Diagnostics

All compiler output is structured JSON with error codes, source spans, human-readable messages, and machine-applicable fixes.

```json
{
  "diagnostics": [
    {
      "severity": "error",
      "name": "NonExhaustiveMatch",
      "code": "E0004",
      "message": "non-exhaustive match",
      "span": {
        "file": "order.bl",
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
            "file": "order.bl",
            "span": { "start": { "line": 16, "col": 0 }, "end": { "line": 16, "col": 0 } },
            "insert": "        Cancelled => todo()\n"
          }
        ]
      },
      "related": [
        {
          "message": "`Cancelled` variant defined here",
          "span": { "file": "types.bl", "line": 8, "col": 5 }
        }
      ]
    }
  ]
}
```

Every diagnostic includes:

| Field | Purpose |
|-------|---------|
| `name` | Stable, searchable error name. `NonExhaustiveMatch` always means non-exhaustive match. See [ERROR_CATALOG.md](../ERROR_CATALOG.md). |
| `code` | Secondary comblink identifier. `E0004` is a shorthand alias for the error name. |
| `span` | Exact source location -- file, line, column, length. |
| `message` | Human-readable description of the problem. |
| `help` | Short suggestion text. |
| `fix.edits` | Machine-applicable edits. The AI reads this array and applies the insertions/replacements directly. No parsing, no guessing. |
| `related` | Links to the declaration or definition that caused the error. |

The AI workflow:

1. AI generates or modifies code.
2. AI calls `blink check --format json`.
3. If diagnostics come back, the AI reads `fix.edits` from each diagnostic.
4. AI applies the edits.
5. Repeat until zero diagnostics.

This loop is mechanical. The AI does not need to "understand" the error -- it applies the compiler's suggested fix. When the fix is not mechanical (no `fix.edits` provided), the `help` text and `related` spans give the AI enough context to reason about a solution.

### 6.6 CLI Commands

| Command | Description | Output |
|---------|-------------|--------|
| `blink build` | AOT compile to native binary | `./myapp` static binary |
| `blink build --target arm64` | Cross-compile | `./myapp` for target arch |
| `blink run` | Compile + execute in one step | Program output |
| `blink check` | Type-check without codegen | Structured diagnostics (JSON) |
| `blink check --format json` | Machine-readable type-check | JSON diagnostics with `fix.edits` |
| `blink eval <expr>` | Interpret expression | Result + effect/allocation report |
| `blink verify` | SMT-based contract verification | Proof results per contract |
| `blink test` | Run all tests | Structured test results (JSON) |
| `blink test --filter "name"` | Run matching tests | Filtered test results |
| `blink fmt` | Format to canonical style | Reformatted files (in-place) |
| `blink daemon` | Start compiler daemon | Persistent process (LSP + incremental) |

All commands that produce diagnostics support `--format json` for machine consumption. The human-readable format is the default for terminal use; the JSON format is the default when stdout is not a TTY (pipe detection).

---

## 7. Error Handling

### 7.1 No Exceptions

Blink has no exceptions, no `try`, no `catch`, no `finally`, no `throw`. All error handling uses values and types.

**Why:**

1. **Exceptions are invisible control flow.** A function signature `fn process(data: Str) -> Report` tells you nothing about whether it might throw `IOException`, `ParseException`, `ValidationError`, or any other exception. You have to read the body -- and every function it calls, transitively -- to know. This violates locality of reasoning. For an AI with a finite context window, this means loading potentially the entire call graph to understand error behavior.

2. **Exception handling is a footgun for AI.** LLMs generate incorrect `try`/`catch` blocks at high rates: catching too broadly (`catch Exception`), catching in the wrong order, forgetting cleanup in `finally`, swallowing errors silently. The `?` operator is one character with exactly one meaning.

3. **`Result[T, E]` makes errors visible in the type signature.** When you see `-> Result[Config, ParseError]`, you know this function can fail, you know how it can fail, and the compiler enforces that you handle it. No surprises.

4. **Effect handlers already replace the useful part of exceptions.** The "throw and catch at a distance" pattern that exceptions enable is handled by effect handlers in Blink -- but with the effect declared in the type signature, making it visible.

### 7.2 Result Type and `?` Operator

```blink
type Result[T, E] {
    Ok(T)
    Err(E)
}
```

Functions that can fail return `Result`:

```blink
fn read_config(path: Str) -> Result[Config, ConfigError] ! IO {
    let text = io.read_file(path)?        // returns Err(IOError) on failure
    let parsed = toml.parse(text)?        // returns Err(ParseError) on failure
    let config = validate(parsed)?        // returns Err(ValidationError) on failure
    Ok(config)
}
```

The `?` operator desugars to:

```blink
// `let text = io.read_file(path)?` becomes:
let text = match io.read_file(path) {
    Ok(val) => val
    Err(e) => return Err(e)
}
```

The `?` operator requires the error type to **match exactly** — there is no implicit conversion. When the callee's error type differs from the function's declared error type, convert explicitly with `.map_err()` and `From`:

```blink
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

```blink
match read_config("app.toml") {
    Ok(config) => start_server(config)
    Err(ConfigError.IO(e)) => io.println("Can't read config: {e}")
    Err(ConfigError.Parse(e)) => io.println("Bad config syntax: {e}")
    Err(ConfigError.Validation(e)) => io.println("Invalid config: {e}")
}
```

The match is exhaustive. Add a new variant to `ConfigError` and the compiler tells you everywhere you forgot to handle it.

### 7.3 Option Type and `??` Operator

```blink
type Option[T] {
    Some(T)
    None
}
```

`Option` is for the absence of a value -- not an error, just "nothing here."

```blink
fn find_user(id: Int) -> Option[User] ! DB {
    db.query_one("SELECT * FROM users WHERE id = {id}")
}
```

The `??` operator provides a default when the value is `None`:

```blink
let name = user.nickname ?? user.full_name ?? "Anonymous"
```

This desugars to nested match:

```blink
let name = match user.nickname {
    Some(n) => n
    None => match user.full_name {
        Some(f) => f
        None => "Anonymous"
    }
}
```

`T?` is sugar for `Option[T]` in type position:

```blink
type UserProfile {
    name: Str
    bio: Str?        // Option[Str]
    avatar_url: Str?  // Option[Str]
}
```

**Combining `?` and `??`:**

```blink
// `?` propagates Result errors, `??` defaults Option values
fn get_display_name(user_id: Int) -> Result[Str, DBError] ! DB {
    let user = db.find_user(user_id)?          // propagate DBError
    let name = user.nickname ?? user.email      // default if no nickname
    Ok(name)
}
```

### 7.4 Error Propagation Examples

**Simple propagation through a call chain:**

```blink
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

```blink
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

```blink
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
