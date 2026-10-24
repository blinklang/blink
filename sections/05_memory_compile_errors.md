## 5. Memory Management

### 5.1 Tracing GC as Default

Blink uses a tracing garbage collector as its default memory management strategy.

The programmer does not think about memory. There are no lifetime annotations, no ownership transfers, no borrow checker. You allocate, you use, the runtime cleans up.

```blink
fn process_request(req: Request) -> Response ! DB, IO {
    let user = db.find_user(req.user_id)?
    let items = db.get_items(user.id)?
    let summary = build_summary(items)     // the runtime frees it when it is no longer in use
    io.println("Processed {items.len()} items")
    Response.ok(summary)
}
```

No annotation on `summary`. No `Box`, `Rc`, `Arc`. No `&'a`. It just works.

**Why not ownership/borrowing (Rust-style):**

1. **AI fails the borrow checker.** LLMs produce incorrect lifetime annotations 30-40% of the time in non-trivial code. The fix loops diverge -- the AI fights the compiler, tries random lifetime permutations, and burns tokens without converging. This directly violates "optimize the generate-compile-check-fix loop."

2. **Algebraic effects and ownership interact badly.** Effect handlers capture continuations that hold references. Tracking lifetime variance across effect handler boundaries turns every effectful function into a lifetime puzzle. The effect system is more important to Blink's identity than manual memory control.

3. **Cognitive overhead destroys locality.** A function with three lifetime parameters requires understanding the lifetime relationships of its entire call graph. This is the opposite of "a function's behavior is determinable from its signature."

4. **GC is proven at scale.** Go serves millions of RPS with sub-millisecond GC pauses in its own collector; Java runs the world's financial infrastructure. That is industry evidence that GC at scale is viable -- the "GC is slow" argument died somewhere around 2015 -- not a claim about Blink's collector. Discord moved from Go to Rust for specific tail-latency reasons; most services never hit that bar.

5. **Deterministic resource cleanup is orthogonal to GC.** File handles, sockets, database connections -- these are managed through the `Closeable` trait and `with...as` scoped resource blocks, not by the GC. The GC manages memory. `Closeable` manages resources. See section 5.5.

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
  = fix: remove `! Arena` and let the value live outside the arena, or copy the value explicitly:
  |
3 |     some_global_cache.store(leaked.clone())
  |                                   ++++++++
```

#### 5.2.1 Arena Semantics

This subsection fixes four semantic points of the arena effect: return-value promotion, escape classification, handler behavior, and nesting. See the [Arena Allocation Semantics deliberation](../decisions/arena-allocation-semantics.md) for rationale.

##### Promotion

A value that crosses a `with arena { }` boundary is copied out of the arena. The copy is deep: the copy of a value includes everything the value refers to (struct fields, list elements, map entries). The copy goes into the nearest enclosing arena. If no arena is active, it goes into the garbage-collected heap.

A type that contains a cycle, directly or through other types, cannot cross an arena boundary. The compiler rejects it with `error[E0701]: arena type contains a cycle`.

##### Escape rule

An allocation site inside an `! Arena` function is classified as either **promoted** or **escaped**:

- **Promoted** — the value flows (possibly through `if` / `match` / early `return`) to the block's result expression. The value is copied out of the arena at the boundary.
- **Escaped** — the value flows anywhere else: captured by a closure that outlives the block, stored into a field of a non-arena-local struct, passed as an argument to a function whose parameter is not itself arena-local, or written to a module-level `let mut`. These sites produce `error[E0700]: ArenaValueEscapes` at compile time.

"Arena-local parameter" is inferred from the callee's signature: an `! Arena` function's parameters are arena-transparent for the caller's escape analysis. No region-variable annotations are required or accepted.

##### Handler behavior

`with arena { body }` is a keyword item with its own typing rule for promotion and escape (this section). It runs in order like a scoped value (§4.7.2) whose `Context` is `()`. `arena` is a keyword form, not a value that a program can store and enter again. On entry, it makes a new arena the active arena. On exit, it makes the previous arena active again and destroys the new arena. Commit and rollback exits behave the same way: the life of the arena does not depend on `ok`.

Arena enter and exit events appear in `--blink-trace` and `--trace all` output, as for every other block-scoped construct. `! Arena` on a function signature is a *marker* effect. The escape check uses it. It does not select a handler.

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

The nearest enclosing arena is the promotion target. A value promoted from the outermost `with arena` block goes into the garbage-collected heap.

##### Error codes

- `E0700 ArenaValueEscapes` — an allocation site reaches a non-return position (closure capture, field store on non-arena target, argument to a non-arena-local parameter, module-level `let mut` assignment). The message prints the resolved promotion target: `would be promoted into: outer arena` when the escaping block is nested inside another `with arena`, otherwise `would be promoted into: GC heap`.
- `E0701 ArenaTypeContainsCycle` — a type crossing a `with arena { }` boundary contains a cycle (directly or transitively). Break the cycle or allocate the cyclic value on the GC heap outside the arena.
- `E0702a ArenaClosureTailNonLiteral` — the tail evaluates to a closure whose origin isn't a closure literal bound in this block (e.g. returned from a call, or reassigned through a variable). Fix: construct the closure outside the `with arena { }` block, or bind it via `let f = fn(…) { … }` immediately inside the block.
- `E0702d ArenaClosureUnsupportedCapture` — a closure-tail capture is of a kind that cannot be copied out of the arena. Fix: construct the closure outside the arena block.

##### Warning codes

- `W0701 ArenaEffectRedundant` — a function declares `! Arena` but every Arena-effectful call in its body is already contained inside a `with arena { }` block. Because `with arena { }` is the escape boundary for the `! Arena` marker, the outer annotation adds no information. Fix: drop the `! Arena` from the function signature.

##### Expression-form semantics

The seven points below fix how `with arena { body }` behaves as an expression,
how early exits interact with promotion, and how the promotion target is
discovered. See [Arena Expression-Form Semantics](../decisions/arena-expression-form-semantics.md).

**1. Tail-return semantics.** `with arena { body }` evaluates to the value of
`body`'s tail expression, deep-copied into the
target at the closing `}`. A block whose last statement is `let x =
...; x` yields `x`. A block with a statement-only tail (type `()`) yields `()`
and promotion is a no-op. Tail position propagates through `if`/`match` arms;
all branches must be tail.

**2. Early return and `?`.** `return expr` or `expr?` inside `with arena { }`
promotes `expr` into the **nearest enclosing arena, else the caller-site
target, else the GC heap**, runs `arena.exit(false)` (which destroys the
inner arena), then propagates the return/error. The target is identical to
what would apply to the block's tail value at that program point.

**3. Handler composition order.** `with h1, arena, h2 { body }` runs:

1. `h1.enter()`, `arena.enter()` (which records the promotion target),
   `h2.enter()`
2. `body`, producing `tail` in the inner arena
3. `h2.exit(ok)` (inner arena still live)
4. Promotion of `tail` into the target recorded at `arena.enter()`
5. `arena.exit(ok)` — makes the previous arena active again and destroys the
   inner arena
6. `h1.exit(ok)` (post-promotion; can observe the promoted value)

Non-arena handlers **right** of `arena` in the `with` clause observe
pre-promotion state; handlers **left** observe post-promotion state.

Run `blink llms --topic arena` for a worked handler-composition timeline example.

**4. Promotion target.** The promotion target of a `with arena { }` is the
nearest enclosing arena at the moment the block starts. If no arena is active
then, the target is the garbage-collected heap.

**5. Escape boundary for `! Arena`.** `with arena { }` is the **escape
boundary** for the `! Arena` marker effect: an `! Arena` callee invoked inside
a `with arena { body }` does not cause the enclosing function to require
`! Arena` on its signature. Conversely, any `! Arena` callee invoked outside
such a block requires the enclosing function to carry `! Arena`. `! Arena`
remains a marker effect: it drives the escape check only.

**6. Resources in the same `with` clause.** `with arena, file = open(...)? as
file { body }` runs `body` with both `file` open and the arena active, then
evaluates the tail, promotes it, then runs LIFO cleanup of non-arena
resources, and finally runs `arena.exit`. The tail expression may reference
resource-backed memory during promotion. However, the **promoted value must
not retain references into any `Closeable`'s buffers** — such capture is
E0700 (value escapes into a non-promotable reference).

**7. Nested closure captures in promoted tails.** A closure-typed tail of
`with arena { expr }` is promoted together with all of its captures. This
includes captured closures, to any depth. There is no restriction on what a
captured closure may itself capture: primitive, struct, list, map, mut cell,
or nested closure. See
[arena-nested-closure-capture-promotion](../decisions/arena-nested-closure-capture-promotion.md).

### 5.5 Deterministic Resource Cleanup: `Closeable` + `with...as`

The GC handles memory. But file handles, sockets, locks, database cursors, and temp files need deterministic cleanup — released at a specific program point, not at some later, unspecified time.

Blink solves this with two pieces: the `Closeable` trait (section 3.6) and the `with...as` syntax (section 2.18).

#### The `Closeable` trait

```blink
trait Closeable {
    fn close(self) ! _
}
```

Any type holding non-memory resources implements `Closeable`. The compiler knows this trait and uses it to power diagnostics and the `with...as` construct.

A `Closeable` type is a scoped value (§4.7.2). It also implements `Scoped`, with `type Context = Self`, an `enter` that returns `self`, and an `exit(ok)` that calls `close()`. The synthesized `exit` has the row of `close`. This impl counts for trait bounds: `T: Scoped` accepts a `Closeable` type. A type that writes both `impl Closeable` and `impl Scoped` gets the overlapping-impl error (§4.7.2).

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

`as name` only binds a name. `with expr { body }` runs the same steps, and the compiler discards the value. The call `name.close()` is charged like any call of an impl-chosen row (§4.15.3). The compiler inserts it on **every catchable unwind**: normal completion, `?` propagation, `return`, assertion failure, and `skip()` in test blocks. The catchable-unwind set is closed and runtime-defined — see §4.7.2 for the exhaustive enumeration and the soundness fence around future user-level panic recovery. Uncaught panics (process-terminating divergence) bypass `close()` entirely.

This rule is uniform with `Scoped.exit()` (§4.7.2): both run on every structured catchable exit, and both bypass on uncaught divergence. A `with db.connect()? as conn { assert(...) }` block releases `conn` on assertion failure inside a test block, because a failed assertion is a catchable unwind (§4.7.2).

#### Multiple resources

```blink
with expr1 as a, expr2 as b { body }
```

Cleanup is LIFO — `b.close()` runs before `a.close()`. If `expr2` fails (via `?`), only `a` is cleaned up. The `?` in the expression propagates **before** the scope is entered — if acquisition fails, no cleanup is needed for that binding.

#### Compiler diagnostics

**W0610 `ScopedValueWithoutWith`: scoped value that does not go into a `with`**

The lint applies to every **scoped value**: a value whose type implements `Scoped` (§4.7.2). Every `Closeable` type implements `Scoped`. A `Handler[E]` value is not a scoped value. It fires when such a value reaches anything other than a `with` item. The check follows the value, not its construction: `let tx = db.transaction()` followed by `with tx { }` does not warn. A scoped value returned from a function is not reported in that function.

The code for this lint is W0610. Code W0600 is `UnusedVariable`, and it never refers to this lint.

```
warning[ScopedValueWithoutWith]: `Closeable` value used without `with...as`
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
  = note: if this function manages the lifetime by hand, add `@allow(ScopedValueWithoutWith)`
  = note: upgrade to error in blink.toml: [lints] W0610 = "error"
```

For a `Scoped` type that is not `Closeable`, the help names the `with` form that the type takes:

```
warning[ScopedValueWithoutWith]: `Scoped` value used without `with`
 --> app.bl:3:9
  |
3 |     let conn = db.connect("app.db")?
  |         ^^^^ `Connection` implements `Scoped`, but `conn` never goes into a `with`
  |
  = help: use it as a `with` item so that `exit()` runs:
  |
3 |     with db.connect("app.db")? {
4 |         // db.* calls here use this connection
5 |     }
```

W0610 is a warning by default, and is upgradeable to an error with `W0610 = "error"` under `[lints]`. Framework code that manages scoped-value lifetimes by hand, such as a connection pool, suppresses it with `@allow(ScopedValueWithoutWith)` on the function. A function-level `@allow` overrides the `[lints]` setting (§4.16.8). `@trusted(audit: K)` does not suppress it (§9.1). When W0610 fires in a function that has `@trusted`, the output adds this note:

```
  = note: `@trusted` does not suppress `ScopedValueWithoutWith`; use `@allow(ScopedValueWithoutWith)`
```

The diagnostic lists the `with` fix first. It lists the `@allow` fix second, and the `applicability` of that fix is `suggestion` (§8.6).

**W0611 `ScopedValueEnteredTwice`: scoped value that goes into more than one `with`**

A scoped value must reach exactly one `with` item. W0611 counts the `with` items that one execution path takes the value into, and fires when the count is two or more. Items on paths that exclude each other (`if`/`else` branches, `match` arms) count once. A `with` in a loop body that enters a value built outside the loop counts as two, unless every path through the body after that `with` leaves the loop. A copy of a scoped value is the same value: `let copy = conn` followed by `with copy` enters `conn`. Its state was fixed when it was built, so a second `exit()` releases it again. It uses the same flow analysis as W0610, and it has the same limit: it does not follow a value into a function it is passed to. No W0611 is not a proof that a value goes into one `with` only, and W0611 is not a safety check: a type that wraps a foreign handle should make a second `exit()` safe (§4.7.2).

```
warning[ScopedValueEnteredTwice]: `Scoped` value goes into more than one `with`
 --> app.bl:4:14
  |
2 |     let conn = db.connect("app.db")?
  |         ---- `conn` is built once here
3 |     for job in jobs {
4 |         with conn {
  |              ^^^^ `conn` goes into this `with` on each pass of the loop
  |
  = note: `exit()` runs at the end of each `with`, on the same `conn`
  = help: build a new value in each `with` item:
  |
4 |         with db.connect("app.db")? {
  |
  = note: if running `exit()` more than once is intended, add `@allow(ScopedValueEnteredTwice)`
  = note: upgrade to error in blink.toml: [lints] W0611 = "error"
```

When the value is a call result bound to a name, the fix moves the call into each `with` item. That fix is machine-applicable (§8.6) if the call has no other use. W0611 is a warning by default, and is upgradeable to an error with `W0611 = "error"` under `[lints]` without a change to W0610. Suppress it on a function with `@allow(ScopedValueEnteredTwice)` (§4.16.8). `@trusted(audit: K)` does not suppress it (§9.1). A type whose `exit()` is correct to run more than once, such as `std.testing`'s `Cleanup` when the action is meant to run twice, is a case for that suppression. When W0611 fires in a function that has `@trusted`, the output adds this note:

```
  = note: `@trusted` does not suppress `ScopedValueEnteredTwice`; use `@allow(ScopedValueEnteredTwice)`
```

As for W0610, the diagnostic lists the `with` fix first, and the `@allow` fix second. The `applicability` of the `@allow` fix is `suggestion` (§8.6).

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

These three diagnostics form a closed net: ScopedValueWithoutWith (W0610) catches forgotten `with...as`, E0601 catches escape via return or assignment, E0602 catches escape via collections. Together they ensure `Closeable` values are always scoped and always cleaned up.

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

2. **Algebraic effects fit native code.** Native code gives direct control of the stack. Such control is painful on a VM that wasn't designed for delimited continuations (see: Project Loom's multi-year slog).

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

### 6.2 `blink eval` Interpreter Mode

For development and AI iteration loops, Blink includes an interpreter that runs code directly, without building a native binary:

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

The compiler checks every identifier reference in the program before it produces any output.

#### 6.3.1 Resolution Before Output

Names resolve before the compiler produces output. If the program has a name error, the compiler produces no output (§6.3.5).

#### 6.3.2 What Resolution Checks

- Every identifier refers to a declaration that is in scope.
- Every function call refers to a function.
- Every method call refers to a method of the receiver type.
- Every struct literal refers to a type.

#### 6.3.3 Name Errors and Method Errors

A name error means that an identifier does not refer to anything. A method error means that the receiver type has no such method. The two kinds of error have different codes.

A name error is E0504 (UndefinedFunction) for a function, or E1003 for a name that is not visible. A call `x.foo()` with no method `foo` for the type of `x` is E0505 (UnresolvedMethod). The `?` operator checks the operand type, the return type of the enclosing function, and the error types (§3c.2). Violations give E0502, E0508, E0509, or E0512.

```blink
fn example(items: List[Str]) -> Int {
    let count = items.len()       // `items` is a parameter; `.len()` is Sized.len on List[Str]
    let x = unknown_fn()          // E0504 — `unknown_fn` not defined
    items.nonexistent()           // E0505 — no method `nonexistent` on List[Str]
    count
}
```

If the compiler cannot find the type of the receiver, it reports an error. It never accepts the call without a check.

#### 6.3.4 Module Scope

Every declaration belongs to one module. This gives these rules:

- **`pub` enforcement** (§10.8): Using a non-pub item from outside its module produces E1003 (PrivateItemAccess)
- **Qualified error messages**: "cannot access `json.internal_parse`, it is private to module `std.json`"
- **Ambiguity detection**: Two imports in one file that bind one name to different items produce E1005 (AmbiguousImport)

Name lookup follows standard lexical scoping priority:

1. Local bindings (let, for-loop variable, match arm bindings)
2. Function parameters
3. Enclosing closure scope (shared reference capture, §2.8)
4. Module-level declarations (fn, type, let)
5. Imported items (filtered by `pub` for cross-module access)
6. Module prelude (§10.6) — built-in types, Option/Result, compiler-known traits

Effect handles occupy a reserved namespace separate from variables (§3c.4). Attempting to shadow an effect handle name produces E0710 (EffectHandleShadowed).

#### 6.3.5 Error Recovery

The compiler reports all name errors of the program in one run. If the program has a name error, the compiler produces no output.

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

**A callee that names a type.** When the callee names a type and no function of that name is in scope, the call is E0504, and the first `help:` names the one empty form of that type (§3.2.2 *Construction and Mutability*):

- For `List`, the form is `[]`.
- For a type `T` that has a type-scoped `new` with no parameters, the form is `T.new()`. A `new` that takes parameters is never named.
- For a struct that the caller can write as a literal, the form is the struct literal.
- Otherwise the help names no form. An opaque type from another module is one case.

One rule covers every type. It has no case for a name such as `List` or `StringBuilder`. A row of the §3.2 *Removed function forms* table, when it exists for the callee, gives the fix and applies first.

```
error[UndefinedFunction]: undefined function `List`
 --> main.bl:2:14
  |
2 |     let xs = List()
  |              ^^^^ `List` is a type, not a function
  |
  = help: an empty list is `[]`; the annotation or a later use gives the element type
```

When a missing import causes cascading errors (one unresolved name triggers many downstream failures), the compiler applies cascade suppression: downstream references to a poison symbol suppress their own diagnostics. A pattern or a construction that names a variant its enum does not declare (`NoSuchVariant`, §3.5 *Pattern Forms*) also makes poison: each binder under the pattern, and each binding of the construction's value, has the poison type. An error count cap (~20 errors) prevents terminal flooding.

### 6.4 Compiler-as-Service Daemon Architecture

The Blink compiler can run as a persistent daemon process. The daemon keeps its answers current as source files change.

**Key properties:**

- **Incremental checking.** After a change to one function, the daemon checks only that function and the code that depends on it.
- **Target: a type-check of a single changed function in under 200 ms.** This is a tooling goal, not a language rule. The generate-compile-check-fix loop of an AI agent runs at the speed of the compiler.
- **Unified with LSP.** The daemon is also the language server. Completions, hover information, go-to-definition, and refactoring come from the same compiler.
- **File watching built in.** The daemon watches source files. A query never returns an answer for an old version of a file.

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
      "fixes": [
        {
          "description": "Add missing match arm for `Cancelled`",
          "applicability": "machine-applicable",
          "edits": [
            {
              "file": "order.bl",
              "span": { "start": { "line": 16, "col": 0 }, "end": { "line": 16, "col": 0 } },
              "insert": "        Cancelled => todo()\n"
            }
          ]
        }
      ],
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
| `fixes` | The fixes, preferred first. Each has `applicability` and `edits`. The AI applies the `edits` of a `machine-applicable` fix directly. No parsing, no guessing. Absent when the diagnostic has no fix (§8.6). |
| `related` | Links to the declaration or definition that caused the error. |

The AI workflow:

1. AI generates or modifies code.
2. AI calls `blink check --format json`.
3. If diagnostics come back, the AI reads `fixes` from each diagnostic.
4. AI applies the edits of the first `machine-applicable` fix.
5. Repeat until zero diagnostics.

This loop is mechanical. The AI does not need to "understand" the error -- it applies the compiler's suggested fix. When no fix is machine-applicable (`fixes` is absent, or every fix is a `suggestion`), the `help` text and `related` spans give the AI enough context to reason about a solution.

### 6.6 CLI Commands

| Command | Description | Output |
|---------|-------------|--------|
| `blink build` | AOT compile to native binary | `./myapp` static binary |
| `blink build --target arm64` | Cross-compile | `./myapp` for target arch |
| `blink run` | Compile + execute in one step | Program output |
| `blink check` | Type-check without codegen | Structured diagnostics (JSON) |
| `blink check --format json` | Machine-readable type-check | JSON diagnostics with `fixes` |
| `blink fix <file>` | Apply machine-applicable fixes | One line per applied fix; the rest as `check` prints them |
| `blink eval <expr>` | Interpret expression | Result + effect/allocation report |
| `blink verify` | SMT-based contract verification | Proof results per contract |
| `blink verify --deny runtime,trust` | Fail when a contract has a named outcome | Non-zero exit; report unchanged |
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
fn read_config(path: Str) -> Result[Config, ConfigError] ! FS.Read {
    let text = fs.read(path)?             // returns Err(FsError) on failure
    let parsed = toml.parse(text)?        // returns Err(ParseError) on failure
    let config = validate(parsed)?        // returns Err(ValidationError) on failure
    Ok(config)
}
```

The `?` operator desugars to:

```blink
// `let text = fs.read(path)?` becomes:
let text = match fs.read(path) {
    Ok(val) => val
    Err(e) => return Err(e)
}
```

The `?` operator requires the error type to **match exactly** — there is no implicit conversion. When the callee's error type differs from the function's declared error type, convert explicitly with `.map_err()` and `From`:

```blink
type ConfigError {
    Fs(FsError)
    Parse(ParseError)
    Validation(ValidationError)
}

impl From[FsError] for ConfigError {
    fn from(e: FsError) -> ConfigError { ConfigError.Fs(e) }
}

impl From[ParseError] for ConfigError {
    fn from(e: ParseError) -> ConfigError { ConfigError.Parse(e) }
}

impl From[ValidationError] for ConfigError {
    fn from(e: ValidationError) -> ConfigError { ConfigError.Validation(e) }
}

// Explicit error conversion at each ? site
fn read_config(path: Str) -> Result[Config, ConfigError] ! FS.Read {
    let text = fs.read(path)
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
    Err(ConfigError.Fs(e)) => io.println("Can't read config: {e}")
    Err(ConfigError.Parse(e)) => io.println("Bad config syntax: {e}")
    Err(ConfigError.Validation(e)) => io.println("Invalid config: {e}")
}
```

The match is exhaustive. Add a new variant to `ConfigError` and the compiler tells you everywhere you forgot to handle it.

### 7.3 Option Type and `??` Operator

```blink
type Option[T] {
    None
    Some(T)
}
```

`Option` is for the absence of a value -- not an error, just "nothing here."

```blink
fn find_user(id: Int) -> Option[User] ! DB {
    db.query_one(t"SELECT * FROM users WHERE id = {id}")
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

The right operand of `??` is the body of the `None` arm, so it may be a jump (§2.11 *Jumps*): `let user = find(id) ?? return Err(NotFound)`.

`T?` is the one spelling of `Option[T]` in a type (§3.2 *One Spelling for List and Option Types*):

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

### 7.5 Panicking Accessors: `unwrap` and `unwrap_err`

`unwrap` and `unwrap_err` take the payload out of a `Result` or an `Option`. When the value holds the other arm, they panic. The panic message shows the value that was there, so the arm a method panics on must implement `Debug` (§3.6.1 *Debug vs Display*). The methods are built in and behave as if declared:

```blink
impl[T, E] Result[T, E] where E: Debug {
    fn unwrap(self) -> T        // panics on Err(e)
}

impl[T, E] Result[T, E] where T: Debug {
    fn unwrap_err(self) -> E    // panics on Ok(v)
}

impl[T] Option[T] {
    fn unwrap(self) -> T        // panics on None; no bound, None holds no value
}
```

**The rule.** A `Result` or `Option` method that panics on an arm requires `Debug` on that arm's payload type. The rule applies to every such method, including any method added in a later version. A form that never panics carries no bound: `ok`, `map`, `map_err`, `ok_or`, `?`, `??` and `match` (§7.6).

**Checked at the call.** The compiler checks the bound at each call against the receiver's type. A missing `Debug` is `error[TraitBoundNotSatisfied]` (E0306), the same code that assertions use (§2.20 *Built-in Assertions*). A generic function does not get the bound from its body. A function that calls `.unwrap()` on a `Result[T, E]` with a type parameter `E` declares `E: Debug` itself:

```blink
fn first_ok[T, E: Debug](results: List[Result[T, E]]) -> T {
    results.get(0).unwrap().unwrap()
}
```

There is no placeholder. A program that could print a value it cannot render does not compile.

**Panic message.** The text after the prefix is exactly `debug()` of the payload:

| Call | Panics on | Message |
|------|-----------|---------|
| `r.unwrap()` | `Err(e)` | `unwrap called on Err: ` followed by `e.debug()` |
| `r.unwrap_err()` | `Ok(v)` | `unwrap_err called on Ok: ` followed by `v.debug()` |
| `o.unwrap()` | `None` | `unwrap called on None` |

This text is normative, so a test can match it with `assert_panics` (§2.20):

```blink
@derive(Debug)
type ParseError {
    Empty
    BadDigit(ch: Char)
}

test "unwrap shows the error" {
    let r: Result[Int, ParseError] = Err(ParseError.BadDigit('x'))
    assert_panics(matching: "unwrap called on Err: BadDigit('x')") {
        let _ = r.unwrap()
    }
}
```

The runtime may add a lead-in such as `panic: ` and a location suffix such as ` at main.bl:12`. Those parts are not normative; do not match on them. A change to the `Debug` format of a type (§3.6.1) also changes this message.

**Diagnostic.** The primary span is the `.unwrap()` call. When the payload type is a type parameter, a secondary label points at its binder. The help lists the fixes in this order:

1. Add `@derive(Debug)` to the type, or `: Debug` to the binder. The compiler offers the `@derive(Debug)` fix only for a type the user declares. It never offers it for a stdlib type or a type from another package.
2. Use `match` and call `panic` with a message.
3. Use `??` on an `Option`, or `.ok() ??` on a `Result`, when the code must not panic. This changes behavior.

```
error[E0306]: trait bound not satisfied
 --> src/config.bl:8:16
   |
 8 |     let port = parse_port(raw).unwrap()
   |                ^^^^^^^^^^^^^^^^^^^^^^^^ `PortError` does not implement `Debug`
   |
   = note: `unwrap` panics on `Err` and shows the error with `debug()`
   = help: add `@derive(Debug)` to `PortError`
   = help: or use `match` and call `panic` with a message
   = help: or use `.ok() ??` to give a default (this does not panic)
```

The stdlib error types, such as `ConversionError`, `FsError`, `DBError` and `NetError`, implement `Debug`, so `.unwrap()` on a stdlib `Result` compiles. Their `Display` impls stay.

### 7.6 Option and Result Methods

The tables below are the full method set of `Option[T]` and `Result[T, E]`. The other forms are `?`, `??` and `match`. A name that is in no table is not a method of the type.

**`Option[T]`**

| Method | Signature | Result |
|--------|-----------|--------|
| `is_some` | `fn is_some(self) -> Bool` | `true` for `Some` |
| `is_none` | `fn is_none(self) -> Bool` | `true` for `None` |
| `unwrap` | `fn unwrap(self) -> T` | The payload of `Some`; panics on `None` (§7.5) |
| `map` | `fn map[U](self, f: fn(T) -> U ! _) -> U? ! _` | `Some(f(x))` for `Some(x)`; `None` for `None` |
| `ok_or` | `fn ok_or[E](self, e: E) -> Result[T, E]` | `Ok(x)` for `Some(x)`; `Err(e)` for `None` |

**`Result[T, E]`**

| Method | Signature | Result |
|--------|-----------|--------|
| `is_ok` | `fn is_ok(self) -> Bool` | `true` for `Ok` |
| `is_err` | `fn is_err(self) -> Bool` | `true` for `Err` |
| `unwrap` | `fn unwrap(self) -> T` | The payload of `Ok`; panics on `Err` (§7.5) |
| `unwrap_err` | `fn unwrap_err(self) -> E` | The payload of `Err`; panics on `Ok` (§7.5) |
| `map` | `fn map[U](self, f: fn(T) -> U ! _) -> Result[U, E] ! _` | `Ok(f(x))` for `Ok(x)`; the same `Err(e)` for `Err(e)` |
| `map_err` | `fn map_err[F](self, f: fn(E) -> F ! _) -> Result[T, F] ! _` | The same `Ok(x)` for `Ok(x)`; `Err(f(e))` for `Err(e)` |
| `ok` | `fn ok(self) -> T?` | `Some(x)` for `Ok(x)`; `None` for `Err(_)` |

`unwrap` and `unwrap_err` keep the `Debug` bounds of §7.5. No other method in the tables panics.

The callback of `map` and `map_err` has the effect row `! _`. The method forwards the effects of the callback to its caller, in the same way as `List.map` (§3.2.2, §4.15.2). A callback with no effects makes a call with no effects.

Each method has the meaning of this `match`:

```blink
impl[T] Option[T] {
    fn is_some(self) -> Bool { match self { Some(_) => true, None => false } }
    fn is_none(self) -> Bool { match self { Some(_) => false, None => true } }
    fn map[U](self, f: fn(T) -> U ! _) -> U? ! _ {
        match self { Some(x) => Some(f(x)), None => None }
    }
    fn ok_or[E](self, e: E) -> Result[T, E] {
        match self { Some(x) => Ok(x), None => Err(e) }
    }
}

impl[T, E] Result[T, E] {
    fn is_ok(self) -> Bool { match self { Ok(_) => true, Err(_) => false } }
    fn is_err(self) -> Bool { match self { Ok(_) => false, Err(_) => true } }
    fn map[U](self, f: fn(T) -> U ! _) -> Result[U, E] ! _ {
        match self { Ok(x) => Ok(f(x)), Err(e) => Err(e) }
    }
    fn map_err[F](self, f: fn(E) -> F ! _) -> Result[T, F] ! _ {
        match self { Ok(x) => Ok(x), Err(e) => Err(f(e)) }
    }
    fn ok(self) -> T? {
        match self { Ok(x) => Some(x), Err(_) => None }
    }
}
```

`ok_or(e)` evaluates `e` before the call, as each argument is. Use `match` when `e` is costly to build and the value is usually `Some`.

To get a default from a `Result`, drop the error with `ok` and use `??`. To change the error type before `?`, use `map_err`:

```blink
let n = s.parse_int().ok() ?? 0

fn read_config(path: Str) -> Result[Config, ConfigError] ! FS.Read {
    let text = fs.read(path).map_err(fn(e) { ConfigError.from(e) })?
    parse_config(text)
}
```

**Names not in the table.** A call to a name that is in no table is E0505 `UnresolvedMethod`. Where a Blink form does the same job, the help names that form. The list below is closed. It holds only names that this specification once used. A new row needs a panel vote. The list is not part of the §3.2 table of removed names, because no released Blink accepted these names.

| Name | Blink form |
|------|------------|
| `unwrap_or(d)` | `o ?? d` on an `Option`; `r.ok() ?? d` on a `Result` |
| `unwrap_or_else(f)` | The same, with the expression that `f` returns in place of `d`; or `match` |
| `expect(msg)` | `match` with `panic("msg")` in the arm that fails; or `unwrap` |
| `and_then(f)` | `?` in a function that returns an `Option` or a `Result`; or `match` |

The edit from `unwrap_or(d)` to `??` is machine-applicable only when `d` has no effect and cannot panic: a literal, a local name, or a field read of a local name. In all other cases the diagnostic has help text and no edit. The reason: the argument of a method call runs before the call, but the default of `??` runs only when the left side is `None` (§2.22 *Evaluation Order*). A rewrite of `o.unwrap_or(load())` to `o ?? load()` would stop `load()` from running when the value is `Some`. The help says so.

```
error[UnresolvedMethod]: no method `unwrap_or` on `Int?`
 --> src/main.bl:6:15
   |
 6 |     let n = o.unwrap_or(load())
   |               ^^^^^^^^^ `Option` has no method `unwrap_or`
   |
   = help: use `o ?? load()` to give a default
   = note: `load()` does not run when the value is `Some`; as an argument of `unwrap_or`, it ran every time
```
