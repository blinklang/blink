## 4. Effect System

### 4.1 Thesis: Effects Are Capabilities Are Security

Blink's effect system is not a type annotation convenience. It is the security architecture of the language.

Every side effect a function can perform -- printing, reading a database, opening a socket, spawning a process -- is a **capability** that must be explicitly declared in the function's signature and granted by its caller. This is the object-capability model (ocap), as pioneered by Mark Miller's E language, applied at the type level: no ambient authority, no implicit permissions, no action-at-a-distance.

The consequences are structural:

- A function with no `!` in its signature **cannot** perform side effects. The compiler proves it, and no built-in free function is an exception (§4.4 *Every side effect has a row*). One exception: a private function or a closure with no `!` can still have `State` in its effective row. The compiler adds `State` when the body reads or writes a module-level `let mut` binding, and the body shows the access. A `pub` function must declare it (§4.16).
- A function declaring `! DB.Read` can query a database but **cannot** write to it, delete from it, or administer it. The compiler proves it.
- A package declaring `capabilities(Net.Connect)` in its manifest **cannot** open a listening socket. The compiler proves it.
- An effect handler can attenuate capabilities -- handing a function a `Net.Connect` that only permits connections to a specific allowlist. The runtime enforces it.

There is no separate "permissions" system, no runtime ACLs, no sandbox configuration files. The effect system **is** all of these things. Capabilities are tracked through the type system, enforced by the compiler, and attenuated through handlers. If your code compiles, the capability discipline is guaranteed.

**Why fine-grained effects must be v1, not v2:**

Coarse effects collapse to meaninglessness within three call levels. Consider a real application:

```blink
// Coarse effects: what actually happens in practice
fn handle_request(req: Request) -> Response ! IO, DB, Net {
    // This function does IO (logging), DB (queries), Net (external API calls)
    // But so does EVERY request handler. The annotation carries zero information.
    // You learn nothing from the signature that you didn't already know.
}

fn validate_order(order: Order) -> Result[Order, ValidationError] ! IO, DB {
    // "IO" because somewhere deep inside, something logs.
    // "DB" because it checks inventory.
    // But can it WRITE to the DB? Can it DELETE? Who knows? ! DB says nothing.
}
```

With coarse effects, the steady state of any non-trivial codebase is that nearly every function is annotated `! IO, DB, Net`. The effect system degenerates into a binary: "pure" or "everything." This is not a security architecture. This is a boolean.

Fine-grained effects remain meaningful at every level of the call stack:

```blink
fn validate_order(order: Order) -> Result[Order, ValidationError] ! DB.Read, IO.Log {
    // This function can READ the database (check inventory, look up prices)
    // It can LOG (audit trail)
    // It CANNOT write to the database
    // It CANNOT make network calls
    // It CANNOT read environment variables
    // This is a meaningful, enforceable security boundary
}
```

Deferring fine-grained effects to v2 means shipping v1 with a type system feature that provides no security value. The whole thesis -- effects as capabilities -- depends on granularity. Without it, you have Haskell's `IO` monad: one big escape hatch that everything passes through.

---

### 4.2 Effect Declaration Syntax

Effects are declared in function signatures using `!` (bang) after the return type (or after the parameter list if the function returns `()`):

```blink
// Pure function -- no effects, no bang
fn add(a: Int, b: Int) -> Int {
    a + b
}

// Single effect, returns ()
fn log_message(msg: Str) ! IO.Log {
    io.log(msg)
}

// Single effect with return type
fn read_config(path: Str) -> Result[Config, FsError] ! FS.Read {
    let text = fs.read(path)?
    Ok(parse_config(text))
}

// Multiple fine-grained effects
fn process_order(id: Int) -> Result[Receipt, OrderError] ! DB.Read, DB.Write, IO.Log {
    let order = db.query_one(t"SELECT * FROM orders WHERE id = {id}")?
    io.log("Processing order {id}")
    let receipt = Receipt { order_id: id, total: order.total }
    db.execute(t"INSERT INTO receipts ...")?
    Ok(receipt)
}

// Parent effect grants all children
fn dangerous_migration() ! DB {
    // DB grants DB.Read and DB.Write -- the whole tree
    db.exec(t"DROP TABLE legacy_data")?
    db.exec(t"INSERT INTO migrations ...")?
    db.query(t"SELECT count(*) FROM migrations")?
}
```

The `!` was chosen by 3-2 vote over `/`. It universally signals danger or impurity (`!` in Scheme for mutation, Rust for macros, Swift for throwing). It is a single character -- maximally token-efficient. It is visually distinctive in a signature. It does not collide with any operator in expression position.

**The explicit empty row `! ()`.** `! ()` is the empty effect row written out. It means "no effects", the same as an omitted row; it is not a return type. Its one use is on an `@ffi` decl, where the row is a claim the author must write and a missing row is an error (§9.1). On any other function, fn type or trait method signature, the compiler already proves purity, so `! ()` is an error there. The grammar admits `()` after `!` everywhere, but `! ()` outside an `@ffi` decl is an error. Both spellings denote the same row, so `c_strlen` still checks against `fn(Ptr[U8]) -> Int`.

```blink
// intentional-error example
fn add(a: Int, b: Int) -> Int ! () {   // error[EmptyRowOutsideFfi]
    a + b
}
```

```
error[EmptyRowOutsideFfi]: `! ()` is only for `@ffi` declarations
 --> math.bl:2:31
  |
2 | fn add(a: Int, b: Int) -> Int ! () {
  |                               ^^^^ no row already means no effects
  |
  = help: remove `! ()`; it is required only on an `@ffi` decl whose foreign
          code has no effects (§9.1)
```

In a fn type the help says the same thing: `let f: fn(Ptr[U8]) -> Int ! () = c_strlen` is rejected with "in a fn type, no row already means pure; remove `! ()`". `()` cannot be combined with an effect name: `! (), IO` is a parse error.

---

### 4.3 Effect Hierarchy

Effects are declared as hierarchical trees. A parent effect grants all of its children. Children are independent capabilities that can be granted individually.

```blink
effect FS {
    effect Read       // read file contents, list directories, read file metadata
    effect Write      // create files, write contents, rename
    effect Delete     // remove files and directories
    effect Watch      // watch for filesystem changes
}

effect Net {
    effect Connect    // outbound TCP/UDP/HTTP connections
    effect Listen     // bind and listen on ports
    effect DNS        // DNS resolution
}

effect DB {
    effect Read       // SELECT, read-only queries
    effect Write      // INSERT, UPDATE, DELETE, CREATE, DROP, ALTER — all mutations
}

effect IO {
    effect Print      // stdout
    effect Log        // structured logging subsystem
    @handle_all
    effect Read       // read standard input (operations in §4.4.9)
}

effect Env {
    effect Read       // read environment variables
    effect Write      // set environment variables
    effect Exit       // terminate the process
}

@handle_all            // a handler implements every primitive operation (§4.7.1)
effect Time {
    effect Read       // read the wall clock and the monotonic clock
    effect Sleep      // sleep / delay execution
}

@handle_all
effect Rand           // generate random numbers (leaf effect, operations in §4.4.7)

effect Crypto {
    effect Hash       // hash functions (SHA, BLAKE, etc.); a plain digest is a pure function in std.digest and needs no effect
    effect Sign       // digital signatures
    effect Encrypt    // symmetric/asymmetric encryption
    effect Decrypt    // decryption
}

effect Process {
    effect Spawn      // spawn child processes
    effect Signal     // send signals to processes
}

effect State          // reads or writes module-level `let mut` (leaf effect: no operations, no handler, §4.16)

```

**Granting rules:**

| Declaration | What you can use |
|---|---|
| `! FS.Read` | `fs.read(...)`, `fs.list_dir(...)`, `fs.stat(...)` -- read-only FS operations |
| `! FS.Read, FS.Write` | Read and write, but not delete or watch |
| `! FS` | All FS operations: read, write, delete, watch |
| `! DB.Read` | Read-only database queries: `db.query(...)`, `db.query_one(...)` |
| `! DB.Write` | Database mutations: `db.exec(...)`, `db.execute(...)`, `db.begin()`, `db.commit()`, `db.rollback()` |
| `! DB` | Full database access: read and write |

**An effect name must exist.** Every name in an effect row must be a built-in effect (above) or one the program declares (§4.12). Any other name is rejected with `UnknownEffect` (E0538). There is no `FFI` effect, so `! FFI` is the usual way to meet this error; for that name the diagnostic adds a help line that points to §9.1:

```
error[UnknownEffect]: unknown effect `FFI`
 --> sys.bl:3:24
  |
3 | fn c_getpid() -> Int ! FFI
  |                        ^^^ no effect named `FFI`
  |
  = help: a foreign call is not an effect of its own; declare the effects the
          foreign code has (`IO`, `Net`, ...), or `! ()` if it has none (§9.1)
```

No fix is machine-applicable: an effect row on an `@ffi` decl is a claim about foreign code, and no tool writes that claim for the author.

Declaring a parent is syntactic sugar for declaring all children. `! FS` and `! FS.Read, FS.Write, FS.Delete, FS.Watch` are identical to the compiler. The short form exists for the (rare) functions that genuinely need everything; the long form is what most functions should use.

**Why hierarchical and not flat:**

A flat list of 30+ effects is unusable. Hierarchy provides two things: (1) grouping -- `FS.*` are all filesystem-related, so the handle namespace is coherent; and (2) a short form -- when a function genuinely needs all filesystem operations, `! FS` is one annotation, not four. The hierarchy matches how humans and AI think about capability domains.

---

### 4.4 Effect Handles

Declaring an effect in a function signature brings a **handle** into scope. The handle is the only way to access the effect's operations. There are no free functions for IO, no global `print` -- only `io.print(...)`, available when the function declares `! IO.Print` or `! IO`.

```blink
fn example() ! IO.Print, FS.Read, DB.Read, Net.Connect, Crypto.Hash {
    io.print("Starting...")          // IO.Print handle (no newline)
    io.println("Done!")              // IO.Print handle (with newline)
    let data = fs.read("input.txt")? // FS.Read handle
    let rows = db.query(t"SELECT *..")? // DB.Read handle — t"..." builds a Template[DB]
    let resp = net.get(url)?          // Net.Connect handle
    let hash = crypto.hash(data)     // Crypto.Hash handle
}
```

**IO operations by dispatch mode:**

| Operation | Argument | Behavior | Handler-dispatched | Handler-interceptable | Trace |
|---|---|---|---|---|---|
| `io.print(x)` | `T: Display` | stdout, no newline | Yes (`IO.Print`) | Yes | Yes |
| `io.println(x)` | `T: Display` | stdout, with newline | Yes (`IO.Print`) | Yes | Yes |
| `io.log(x)` | `T: Display` | stderr, `[LOG]` prefix + newline | Yes (`IO.Log`) | Yes | Yes |
| `io.read_line()` | — | next stdin line, `None` at end of input (§4.4.9) | Yes (`IO.Read`) | Yes | Yes |
| `io.read_all()` | — | all stdin that is left (§4.4.9) | Yes (`IO.Read`) | Yes | Yes |
| `io.read_bytes(n)` | `Int` | exactly `n` stdin bytes, fewer only at end of input (§4.4.9) | Yes (`IO.Read`) | Yes | Yes |
| `io.eprintln(x)` | `T: Display` | stderr, with newline | No | No | Yes |
| `io.eprint(x)` | `T: Display` | stderr, no newline | No | No | Yes |
| `io.print_raw(s)` | `Str` | raw stdout, no newline | Yes (`IO.Print`) | Yes | Yes |
| `io.eprint_raw(s)` | `Str` | raw stderr, no newline | No | No | Yes |
| `io.print_raw_bytes(b)` | `Bytes` | raw stdout, the bytes as they are | Yes (`IO.Print`) | Yes | Yes |

`io.print_raw` and `io.print_raw_bytes` are operations of `IO.Print`. The innermost `IO.Print` handler receives them, a handler can intercept them, and they emit trace records. `io.eprint_raw` has the same dispatch as `io.eprint`. Use the `_raw` operations when you need exact output with no newline added and an immediate flush (for example, streaming JSON fragments or progress indicators). Prefer `io.print`/`io.println` for application code; reserve `_raw` for low-level tooling.

**`_raw` writes.** The default (root) `IO.Print` handler keeps the byte contract of the `_raw` operations: it writes every byte of the argument, and it flushes them before the operation returns. `io.print_raw_bytes(b)` writes NUL bytes and bytes that are not UTF-8 as they are, for binary output such as an image or a protocol frame. Under the default `IO.Print` handler, output from `io.print`, `io.println` and the stdout `_raw` operations appears on stdout in call order. A handler that intercepts these operations decides where its output goes, so the byte contract and the order rule do not apply to it.

A handler that omits `print_raw_bytes` forwards the call to the enclosing handler (§4.7.1 *Completeness and auto-delegation*). `IO.Print` is not marked `@handle_all`, so the omission gives no `PartialHandler` warning (W0545). A handler that omits `print_raw` runs the default body, which calls `print_no_nl`, so the handler receives the text as a `print_no_nl` call. The default handler implements both `_raw` operations itself, so it keeps the byte contract.

A handler operation that delegates to the enclosing `default` can still send output outward. The row that such a delegation adds at the `with` site is an open question (§4.7.1 *Completeness and auto-delegation*).

```blink
fn progress(done: Int, total: Int) ! IO.Print {
    io.println("copying")
    io.print_raw("\r{done}/{total}")  // appears after "copying"
}
```

**Argument types.** Each non-`_raw` operation takes any `Display` value, as `sb.write` and `"{x}"` do (§3.6 *Display Format Protocol*). So `io.println(42)`, `io.println(p)` and `io.println("n = {n}")` all compile, and a value with no `Display` impl is `error[E0523]` at the argument. `io.print_raw` and `io.eprint_raw` take `Str` only, and `io.print_raw_bytes` takes `Bytes`. The split follows the `_raw` name, not the dispatch mode: `io.eprint` is not interceptable and still takes `Display`. A non-`Str` argument to a `_raw` operation is a type mismatch:

```
error[TypeError]: mismatched types
 --> progress.bl:4:18
  |
4 |     io.print_raw(done)
  |                  ^^^^ expected `Str`, found `Int`
  |
  = help: render it first: `io.print_raw("{done}")`
```

**Print and log handler operations take `Str`.** The generic surface is a stdlib wrapper, not a generic effect operation. `io.println(x)` renders `x` via `x.display()`, then performs the handler operation with the result; `io.print` and `io.log` do the same. `io.eprint` and `io.eprintln` render the same way, then write the `Str` to stderr. The handler operations are:

| Effect | Operation | Called by |
|---|---|---|
| `IO.Print` | `fn print(msg: Str)` | `io.println(x)`; the default handler writes `msg` and a newline |
| `IO.Print` | `fn print_no_nl(msg: Str)` | `io.print(x)` |
| `IO.Print` | `fn print_raw(s: Str)` | `io.print_raw(s)`; derived: the default body calls `print_no_nl(s)` |
| `IO.Print` | `fn print_raw_bytes(b: Bytes)` | `io.print_raw_bytes(b)`; primitive |
| `IO.Log` | `fn log(msg: Str)` | `io.log(x)` |
| `IO.Read` | `fn read_bytes(n: Int) -> Bytes` | `io.read_bytes(n)`; primitive |
| `IO.Read` | `fn read_line() -> Option[Str]` | `io.read_line()`; derived (§4.4.9) |
| `IO.Read` | `fn read_all() -> Str` | `io.read_all()`; derived (§4.4.9) |

The `IO.Read` operations take and return other types (§4.4.9). The wrapper selects the operation; it does not add the newline to `msg`. A handler therefore sees the same `msg` for `io.println(42)` and `io.println("42")`: the text `42`, with no newline.

**Handle naming is deterministic:**

| Effect | Handle | Operations |
|---|---|---|
| `IO` / `IO.*` | `io` | `io.print(...)`, `io.println(...)`, `io.log(...)`, `io.eprintln(...)`, `io.eprint(...)`, `io.print_raw(...)`, `io.eprint_raw(...)`, `io.print_raw_bytes(...)`, `io.read_line()`, `io.read_all()`, `io.read_bytes(...)` (§4.4.9) |
| `FS` / `FS.*` | `fs` | `fs.read(...)`, `fs.write(...)`, `fs.list_dir(...)`, `fs.stat(...)`, `fs.delete(...)`, `fs.watch(...)` (§4.4.5) |
| `DB` / `DB.*` | `db` | `db.query(...)`, `db.query_one(...)`, `db.exec(...)`, `db.execute(...)`, `db.prepare(...)`, `db.begin()`, `db.commit()`, `db.rollback()` |
| `Net` / `Net.*` | `net` | `net.request(...)`, `net.get(...)`, `net.post(...)`, `net.listen(...)`, `net.dns(...)` |
| `Env` / `Env.*` | `env` | `env.args()`, `env.var(...)`, `env.vars()`, `env.cwd()`, `env.pid()`, `env.set_var(...)`, `env.remove_var(...)`, `env.exit(...)` (§4.4.3) |
| `Time` / `Time.*` | `time` | `time.read() -> Instant` (wall clock), `time.monotonic() -> Monotonic`, `time.sleep(Duration)` (§3.2.3) |
| `Rand` | `rand` | `rand.int(Range[Int])`, `rand.float()`, `rand.bytes(Int)` (§4.4.7) |
| `Crypto` / `Crypto.*` | `crypto` | `crypto.hash(...)`, `crypto.sign(...)`, `crypto.encrypt(...)`, `crypto.decrypt(...)`; a plain SHA-256 digest is the pure `Sha256.of` in `std.digest` and needs no effect |
| `Process` / `Process.*` | `process` | `process.run(...)`, `process.spawn(...)`, `process.wait(...)`, `process.signal(...)`, `process.exec(...)` (§4.4.8) |

The handle is always the lowercase form of the top-level effect name. Sub-effects do not create separate handles -- they control which *methods* on the handle are available. Declaring `! FS.Read` gives you the `fs` handle, but only `fs.read(...)`, `fs.list_dir(...)` and `fs.stat(...)` compile. Calling `fs.write(...)` with only `FS.Read` declared is a compile error:

```blink
fn read_only() ! FS.Read {
    let data = fs.read("config.toml")  // OK
    fs.write("config.toml", data)      // COMPILE ERROR
}
```

```
error[UndeclaredEffect]: insufficient effect capability
 --> config.bl:3:5
  |
3 |     fs.write("config.toml", data)
  |     ^^^^^^^^ `fs.write` requires effect `FS.Write`
  |
  = note: function `read_only` only declares `FS.Read`
  = fix: add `FS.Write` to effect declaration:
  |
1 | fn read_only() ! FS.Read, FS.Write {
  |                         +++++++++
```

**Why handles instead of free functions:**

When you read `fs.read(path)`, you know two things immediately: (1) this is a filesystem read, and (2) the enclosing function must declare `! FS.Read`. The handle is a visual anchor that traces directly back to the capability in the signature. An AI reading the function body can verify effect correctness locally -- no import resolution, no global namespace lookup.

Handles also enable the handler mechanism (section 4.7). Because all effect operations route through a handle object, swapping the implementation behind the handle is straightforward. The handle is simultaneously a namespace, a capability proof, and a dispatch point.

**Every side effect has a row.** Three rules make the §4.1 claim ("a function with no `!` cannot perform side effects") true for the whole language, the stdlib included:

1. No compiler-known free function performs a side effect.
2. Every stdlib function and method declares a row that is a sound upper bound on its observable effects. An empty row means that the function is pure, or that it diverges with result type `Never`.
3. An operation that consumes a value that a handle op made is a handle op of the same effect. The handler that made the value answers the operation. Under a mock `Process` handler, `process.spawn` returns a mock `Child`, and `process.wait(child)` goes to the same mock, never to the real runtime (§4.4.8).

Rule 2 permits a second tier: a std function or method that has a row but is not a handle op, such as `udp_bind` and `unix_listen` (§4.4.6). Rule 3 permits this only when no handle op made the value that the function consumes. The effect row gates a second-tier function as it gates a handle op, but no handler can intercept it (§4.10).

**A handle op has one call form.** A program calls a handle op through its handle: `handle.op(value, ...)`, as in `process.wait(child)` and `net.serve(server)`. A value that a handle op made is an argument. It is never the receiver. `v.op(...)` is a method call: it searches traits only (§3c.4 *Trait Method Lookup*) and never reaches a handler, also when `v` holds a value that a handle op made. So `child.wait()` is E0505 (UnresolvedMethod). This rule does not apply to `.await` (§4.13).

**E0505 help for a handle op.** Suppose method lookup fails for `v.op(args)`, and a visible effect has an op `op` whose declared first parameter type equals the type of `v`. The type of `v` is its type after inference and alias expansion. The two types must be equal. A type that only converts to the parameter type does not match. Then E0505 names the op and its effect. The first line of the help gives the handle form, `h.op(v, args)`, with `h` the handle of that effect. If the type of `v` is a type parameter or the poison type, no op matches, and the error is plain E0505. If two or more visible effects match, the help lists each match, and the fix is not machine-applicable.

```blink
pub fn finish(child: Child) -> Result[ProcessResult, ProcessError] {
    child.wait()
}
```

```
error[UnresolvedMethod]: no method `wait` on type `Child`
 --> build.bl:2:11
  |
2 |     child.wait()
  |           ^^^^ `Child` has no method `wait`
  |
  = help: call it through the handle: `process.wait(child)`
  = note: `wait` is an operation of `Process.Spawn`; the fix also adds `Process.Spawn` to the row of `finish`
```

In the structured output (§6.5), this fix carries two edits: the call rewrite and, when the enclosing row lacks the effect, the addition of the effect to that row. Both are machine-applicable when the replacement takes the same arguments. `h.op(v, args)` takes the arguments of the call, in the same order, so both are machine-applicable. No tool writes the row of an `@ffi` declaration, so inside one there is no row edit. The fix has the shape of the removed-name rows below, because a respelled call and a call to a removed name are the same kind of rewrite: each replaces a call by a call to a handle op. The structured output reports the row edit. A change to the row of a `pub fn` changes a public signature, so the report names each row that the fix changes.

**Removed free functions.** Earlier versions of Blink had free functions that performed side effects. Rule 1 removes them. A call to one of these names gives the usual undefined-function error (E0504), with a fix that names the replacement and its effect. The compiler keeps the table below for good. It looks in the table only when name lookup fails, so a program that declares its own `fn read_file` still compiles and calls that function. The table also holds removed handle operations and removed `std` functions that took the place of a handle. A row for a handle operation follows the method rule of §3.2 *Removed methods*: the compiler looks at it only when lookup of that operation fails, and the error is E0505. The fourth column has the same meaning as the third column of the §3.2 table.

| Removed name | Replacement | Effect | Result changes |
|---|---|---|---|
| `read_file(p)` | `fs.read(p)` | `FS.Read` | yes: `Str` becomes `Result[Str, FsError]` |
| `write_file(p, s)` | `fs.write(p, s)` | `FS.Write` | yes: the result becomes `Result[(), FsError]` |
| `list_dir(p)` | `fs.list_dir(p)` | `FS.Read` | yes: the result becomes a `Result` |
| `fs_remove(p)` | `fs.delete(p)` | `FS.Delete` | yes: the result becomes a `Result` |
| `file_exists(p)`, `is_dir(p)`, `file_mtime(p)` | `fs.stat(p)` (§4.4.5) | `FS.Read` | yes: `Int` becomes `Result[FileInfo, FsError]` |
| `exit(c)` | `env.exit(c)` | `Env.Exit` | no |
| `arg_count()`, `get_arg(i)` | `env.args()` | `Env.Read` | yes: `Int` or `Str` becomes `List[Str]` |
| `getpid()` | `env.pid()` | `Env.Read` | no |
| `time_ms()` | `time.monotonic()` to measure elapsed time; `time.read().to_unix_ms()` for a timestamp (§3.2.3) | `Time.Read` | yes: `Int` becomes `Monotonic` or `Instant` |
| `shell_exec(cmd)` | `process.run("sh", ["-c", cmd])` | `Process.Spawn` | yes: the result becomes `Result[_, ProcessError]` |
| `process_run(cmd, args)` | `process.run(cmd, args)` | `Process.Spawn` | yes: the result becomes `Result[_, ProcessError]` |
| `process_run_with_stdin(cmd, args, input)` | `process.run(cmd, args, stdin: Some(input))` | `Process.Spawn` | yes: the result becomes `Result[_, ProcessError]` |
| `process_spawn(cmd, args)` | `process.spawn(cmd, args)` | `Process.Spawn` | yes: `Int` becomes `Result[Child, ProcessError]` |
| `process_pid_wait(pid)` | `process.wait(child)` | `Process.Spawn` | yes: the argument is a `Child`, and the result becomes a `Result` |
| `process_pid_kill(pid, sig)`, `process_pid_send_signal(pid, sig)` | `process.signal(child, sig)` | `Process.Signal` | yes: the argument is a `Child`, and the result becomes a `Result` |
| `child.kill(sig)` on `Child` | `process.signal(child, sig)`; `child.kill(0)` becomes `process.signal(child, SIGKILL)` | `Process.Signal` | yes: `Int` becomes `Result[(), ProcessError]` |
| `child.send_signal(sig)` on `Child` | `process.signal(child, sig)` | `Process.Signal` | yes: `Int` becomes `Result[(), ProcessError]` |
| `process_exec(cmd, args)` | `process.exec(cmd, args)` | `Process.Spawn`, `Env.Exit` | yes: the result becomes `Result[Never, ProcessError]` |
| `unix_socket_listen(p)`, `unix_socket_accept(l)` | `unix_listen(p)`, `listener.accept()` in `std.net` (§4.4.6) | `Net.Listen` | yes: `Int` becomes a `Result` |
| `unix_socket_connect(p)` | `unix_connect(p)` in `std.net` (§4.4.6) | `Net.Connect` | yes: `Int` becomes `Result[UnixStream, NetError]` |
| `socket_read_line(s)`, `socket_write(s, x)`, `unix_socket_close(s)` | `stream.read_line()`, `stream.write(x)`, `stream.close()` on `UnixStream`; `conn.read_line()`, `conn.write(x)`, `conn.close()` on `UnixConn` (§4.4.6) | `Net.Connect` on `UnixStream`, `Net.Listen` on `UnixConn` | yes: reads and writes return a `Result` |
| `io.write(s)` | `io.print_raw(s)` | `IO.Print` | no |
| `io.write_bytes(b)` | `io.print_raw_bytes(b)` | `IO.Print` | no |
| `db_connect(path)`, `sqlite_connect(path)` in `std.db_sqlite` | `with db.connect(path)? { }` (§4.7.2 *Scoped effect handlers*) | `DB` | yes: the result becomes `Result[Connection, DBError]` |
| `sqlite_handler(handle)` in `std.db_sqlite` | `with db.connect(path)? { }` | `DB` | yes: the argument is a path, and the result becomes `Result[Connection, DBError]` |

```
error[UndefinedFunction]: undefined function `read_file`
 --> build.bl:4:16
  |
4 |     let text = read_file(path)
  |                ^^^^^^^^^ not found in this scope
  |
  = note: `read_file` is not a built-in function; file reads go through the `fs` handle
  = fix: fs.read(path)
  = help: `fs.read` needs `FS.Read` in the effect row and returns `Result[Str, FsError]`
```

In the structured output (§6.5), the fix carries two edits: the call rewrite and the addition of the effect to the enclosing row. Both are machine-applicable when the replacement takes the same arguments. The rewrites for `time_ms`, `file_exists`, `is_dir`, `file_mtime`, `arg_count`, `get_arg` and `sqlite_handler` change the shape of the code, so for these names the fix is a suggestion and only the row edit is machine-applicable. (Panel vote on the `io`, `std.db_sqlite` and handle-operation rows and the fourth column: 6-0. See [Duplicate APIs rationale](../decisions/duplicate-apis.md).)

**Rows for methods of `Child`.** The E0505 help for a handle op finds `child.wait()` by its name, so no row lists it. The help cannot find `child.kill(sig)` or `child.send_signal(sig)`, because the op is named `signal`. Rows keyed by the receiver type `Child` cover them (§3.2 *Removed methods*). The released `kill` method used the signal `0` to mean `SIGKILL`. A literal `0` argument to `kill` becomes `SIGKILL`, and a literal argument other than `0` stays as it is. A `kill` argument that is not a literal gets a suggestion, not a machine-applicable fix, because the argument can be `0`. (Panel vote: 6-0. See [One Call Form for Handle Operations rationale](../decisions/handle-op-call-form.md).)

---

#### 4.4.1 Net.Connect Operations

The `Net.Connect` effect has one core operation and convenience default methods for HTTP verbs:

```blink
effect Net {
    effect Connect {
        fn request(req: Request) -> Result[Response, NetError]

        // Default methods — desugar to request() calls
        fn get(url: Str) -> Result[Response, NetError] {
            net.request(Request.new("GET", url))
        }
        fn post(url: Str, body: Str) -> Result[Response, NetError] {
            net.request(Request.new("POST", url).with_body(body))
        }
        fn put(url: Str, body: Str) -> Result[Response, NetError] {
            net.request(Request.new("PUT", url).with_body(body))
        }
        fn delete(url: Str) -> Result[Response, NetError] {
            net.request(Request.new("DELETE", url))
        }
        fn head(url: Str) -> Result[Response, NetError] {
            net.request(Request.new("HEAD", url))
        }
        fn patch(url: Str, body: Str) -> Result[Response, NetError] {
            net.request(Request.new("PATCH", url).with_body(body))
        }
    }

    effect Listen   // server-side binding (§4.4.2)
    effect DNS      // DNS resolution (§4.4.3, future)
}
```

**Handler implementors implement `request()` only.** The verb methods are derived operations (§4.7.1): each one builds a `Request` and calls `net.request`. When a handler omits a verb, the verb's body runs and its `net.request` call reaches that same handler. A handler can also implement a verb directly (e.g., for caching GET responses) and omit `request`; the omitted `request` then goes to the enclosing handler.

```blink
// Minimal mock — one method covers all HTTP verbs
fn mock_net(responses: Map[Str, Str]) -> Handler[Net.Connect] {
    handler Net.Connect {
        fn request(req: Request) -> Result[Response, NetError] {
            match responses.get(req.url) {
                Some(body) => Ok(Response { status: 200, body: body, headers: Map.new() })
                None => Err(NetError.ConnectionRefused("mock: no response for {req.url}"))
            }
        }
    }
}
```

**The `Request` type** is a struct with builder methods for progressive configuration:

```blink
type Request {
    method: Str
    url: Str
    body: Str = ""
    headers: Map[Str, Str] = Map.new()
    timeout_ms: Int = 30000
}
```

`Request.new()` is compiler-provided (same pattern as `Map.new()`, `Set.new()`). Builder methods are provided via the `RequestOps` trait:

```blink
trait RequestOps {
    fn with_body(self, body: Str) -> Request
    fn with_header(self, name: Str, value: Str) -> Request
    fn with_timeout(self, ms: Int) -> Request
}
```

Simple cases stay simple. Complex cases use the builder:

```blink
// Simple GET
let resp = net.get("https://api.example.com/users")?

// GET with headers
let req = Request.new("GET", url)
    .with_header("Authorization", "Bearer {token}")
    .with_timeout(5000)
let resp = net.request(req)?

// POST with JSON body
let resp = net.post("https://api.example.com/users", json.stringify(user))?
```

**The `Response` type** is a transparent struct — fields are directly accessible and pattern-matchable:

```blink
type Response {
    status: Int
    body: Str
    headers: Map[Str, Str]
}
```

Convenience methods are provided via the `ResponseOps` trait:

```blink
trait ResponseOps {
    fn json(self) -> Result[JsonValue, JsonError]
    fn header(self, name: Str) -> Option[Str]
    fn is_ok(self) -> Bool
}
```

Pattern matching on responses is natural:

```blink
match net.get(url)? {
    Response { status: 200, body, .. } => process(body)
    Response { status: 404, .. } => Err(AppError.NotFound("resource gone"))
    Response { status, .. } => Err(AppError.Http("unexpected status {status}"))
}
```

**The `NetError` type** covers transport-level failures:

```blink
type NetError {
    Timeout(msg: Str)
    ConnectionRefused(msg: Str)
    DnsFailure(msg: Str)
    TlsError(msg: Str)
    InvalidUrl(msg: Str)
    BindError(msg: Str)
    ProtocolError(msg: Str)
    IoError(msg: Str)
    Os(op: Str, code: Errno)
    InvalidAddr(input: Str)
}
```

- `Os(op, code)` reports an OS error from a socket call. `op` names the call (for example `"recvfrom"`), and `code` is the `Errno` (§9.1.3.3), so a caller can match on the errno value. `IoError` is not used for errno failures.
- `InvalidAddr(input)` reports a string that `SockAddr.parse` (§4.4.6) cannot read. `input` is the string as given.
- An `EAGAIN` or `EWOULDBLOCK` after a socket timeout (`set_timeout`) is `Timeout`, not `Os`.

HTTP error status codes (4xx, 5xx) are **not** `NetError` variants — they are successful responses with non-2xx status codes. The application decides what constitutes an error via pattern matching on `response.status`.

**WebSocket and SSE:** Deferred to v2. `Net.Connect` covers HTTP request/response only in v1. WebSocket requires persistent bidirectional channels with different algebraic semantics.

---

#### 4.4.2 Net.Listen Operations

**Status: v1. Resolved by panel vote: 3-2 minimal value-server, 4-1 functional middleware, 3-2 typed error handler, 4-1 validation effect.**

The `Net.Listen` effect provides HTTP server capabilities. It has two operations: `listen` makes a `Server`, and `serve` starts it. Convenience methods register routes:

```blink
effect Net {
    effect Listen {
        fn serve(server: Server) -> Result[(), ServerError]

        // Makes an empty Server value
        fn listen(host: Str, port: Int) -> Server
    }
}
```

**The `Server` type** is a value built up by route registration, then started:

```blink
type Server {
    host: Str
    port: Int
    routes: List[Route]
    middleware: List[fn(fn(Request) -> Response) -> fn(Request) -> Response]
    error_handler: fn(Request, ServerError) -> Response = default_error_handler
}
```

Route registration and server startup follow the familiar Flask/Express/Go pattern:

```blink
fn start_server(config: ServerConfig) ! Net.Listen, IO {
    let server = net.listen(config.host, config.port)
    server.route("GET", "/users/:id", handle_get_user)
    server.route("POST", "/users", handle_create_user)
    net.serve(server)
}
```

Route registration builds the `Server` value and is not a `Net.Listen` operation; `net.serve(server)` is the operation that a handler answers.

**Convenience verb methods** mirror `Net.Connect`'s pattern — sugar over `.route()`:

```blink
// These are equivalent:
server.route("GET", "/users/:id", handle_get_user)
server.get("/users/:id", handle_get_user)

server.route("POST", "/users", handle_create_user)
server.post("/users", handle_create_user)
```

**Handler function signature:** Every route handler receives a `Request` and returns a `Response`, declaring whatever effects it needs:

```blink
pub fn handle_get_user(req: Request) -> Response ! IO, DB.Read {
    let id = match req.param("id").parse_int() {
        Ok(n) => n
        Err(_) => return Response.bad_request("Invalid ID")
    }
    match get_user(id) {
        Ok(user) => Response.json(user)
        Err(ApiError.NotFound(msg)) => Response.not_found(msg)
        Err(e) => Response.internal_error("{e}")
    }
}
```

**The `Route` type** is internal to `Server`:

```blink
type Route {
    method: Str
    pattern: Str
    handler: fn(Request) -> Response
    error_handler: Option[fn(Request, ServerError) -> Response] = None
}
```

##### Middleware

Middleware uses functional wrapping: `fn(handler) -> handler`. A middleware function takes a handler and returns a new handler that wraps it:

```blink
fn with_logging(handler: fn(Request) -> Response) -> fn(Request) -> Response ! IO.Log {
    fn(req: Request) -> Response {
        io.log("Request: {req.method} {req.path}")
        let resp = handler(req)
        io.log("Response: {resp.status}")
        resp
    }
}

fn with_auth(handler: fn(Request) -> Response) -> fn(Request) -> Response {
    fn(req: Request) -> Response {
        match req.header("Authorization") {
            Some(token) => {
                // validate token...
                handler(req)
            }
            None => Response.unauthorized("Missing Authorization header")
        }
    }
}
```

Compose by nesting — outermost wrapper runs first:

```blink
// Logging wraps auth wraps handler: log → auth check → handler → log response
server.route("GET", "/users/:id", with_logging(with_auth(handle_get_user)))
```

Global middleware applies to all routes:

```blink
server.use(with_logging)    // applies to all subsequently registered routes
server.use(with_auth)
server.get("/users/:id", handle_get_user)
server.post("/users", handle_create_user)
```

**Why functional wrapping over effect handler stacking (4-1 vote):** Wrapping runs once at server startup, not per request. Effect handler stacking would run the nested `with` blocks again for each request. Functional composition is also the most universal middleware pattern across web frameworks (Express, Rack, WSGI, Go), giving LLMs strong training signal for correct code generation.

##### Error Recovery

The `ServerError` sum type covers server-level failures:

```blink
type ServerError {
    HandlerPanic(msg: Str)
    Timeout(msg: Str)
    Internal(msg: Str)
}
```

Error handling is configurable via the `error_handler` field on `Server`:

```blink
fn json_error_handler(req: Request, err: ServerError) -> Response {
    match err {
        ServerError.HandlerPanic(msg) => Response.internal_error(json.stringify({
            error: "internal_error",
            message: msg
        }))
        ServerError.Timeout(msg) => Response { status: 504, body: json.stringify({
            error: "timeout",
            message: msg
        }), headers: Map.new() }
        ServerError.Internal(msg) => Response.internal_error(json.stringify({
            error: "internal_error",
            message: msg
        }))
    }
}

let server = net.listen(config.host, config.port)
server.error_handler = json_error_handler
```

Per-route overrides are supported:

```blink
// API routes return JSON errors
server.get("/api/users/:id", handle_get_user).on_error(json_error_handler)

// Page routes return HTML errors
server.get("/pages/:slug", handle_page).on_error(html_error_handler)
```

The default error handler returns a plain-text 500 response. The server catches a panic in a route handler, so the panic does not stop the server.

##### @requires Validation at System Boundaries

When a route handler calls a function with `@requires` contracts, the compiler generates `validation.contract_violation()` effect operations instead of panics. The default handler returns a structured 400 JSON response. Users can swap the handler for custom behavior (422, localized messages, JSON:API format).

```blink
@requires(id > 0)
pub fn get_user(id: Int) -> Result[User, ApiError] ! DB.Read {
    // ...
}

// The compiler sees get_user(id) called from a route handler.
// It generates: validation.contract_violation("id", "id > 0", id)
// when the contract would fail.
// Default handler returns:
// Response { status: 400, body: '{"error":"validation_failed","violations":[{"param":"id","constraint":"id > 0","value":-1}]}' }
```

Custom validation handler via effect system:

```blink
fn custom_validation_handler() -> Handler[Validation] {
    handler Validation {
        fn contract_violation(param: Str, constraint: Str, value: Str) -> Response {
            Response { status: 422, body: json.stringify({
                errors: [{ field: param, rule: constraint, received: value }]
            }), headers: Map.new() }
        }
    }
}

// Apply to server
fn start_server(config: ServerConfig) ! Net.Listen, IO {
    let server = net.listen(config.host, config.port)
    server.get("/users/:id", handle_get_user)
    with custom_validation_handler() {
        net.serve(server)
    }
}
```

The validation effect works outside HTTP contexts too — CLI argument validation, batch processing, message consumers. See §9.2 for full system boundary detection rules.

**Mock validation in tests:**

```blink
test "validation collects violations" {
    let violations = []
    let mock_validation = handler Validation {
        fn contract_violation(param: Str, constraint: Str, value: Str) -> Response {
            violations.push({ param: param, constraint: constraint, value: value })
            Response.bad_request("test")
        }
    }
    with mock_validation, mock_db_with_users([]) {
        let resp = handle_get_user(Request.new("GET", "/users/-1"))
        assert_eq(violations.len(), 1)
        assert_eq(violations.get(0).unwrap().param, "id")
    }
}
```

##### Server Handler Implementation

A `Net.Listen` handler implements `listen` and `serve`. Route registration methods build the `Server` value; the handler receives the fully-configured server:

```blink
fn mock_server() -> Handler[Net.Listen] {
    handler Net.Listen {
        fn listen(host: Str, port: Int) -> Server {
            Server { host: host, port: port, routes: [], middleware: [],
                     error_handler: default_error_handler }
        }
        fn serve(server: Server) -> Result[(), ServerError] {
            // Test implementation: verify routes are registered
            assert(server.routes.len() > 0)
            Ok(())
        }
    }
}

test "server starts with routes" {
    with mock_server() {
        let server = net.listen("localhost", 8080)
        server.get("/health", fn(req: Request) -> Response { Response.ok("ok") })
        net.serve(server)
    }
}
```

**Static file serving:** Not a language-level concern. Implement as a handler function:

```blink
fn static_files(root: Str) -> fn(Request) -> Response ! FS.Read {
    fn(req: Request) -> Response {
        let path = "{root}/{req.path}"
        match fs.read(path) {
            Ok(content) => Response.ok(content)
            Err(_) => Response.not_found("File not found")
        }
    }
}

server.get("/static/*", static_files("./public"))
```

---

#### 4.4.3 Env Operations

The `Env` effect provides access to the process environment: command-line arguments, environment variables, working directory, process ID, and process exit. Operations are split between `Env.Read` (observation), `Env.Write` (mutation) and `Env.Exit` (process termination).

```blink
effect Env {
    effect Read {
        /// Command-line arguments (argv). Always returns at least one element (program name).
        fn args() -> List[Str]

        /// Read a single environment variable. Returns None if the variable is not set.
        /// Non-UTF-8 values are lossy-converted to UTF-8 or returned as None.
        fn var(name: Str) -> Option[Str]

        /// Snapshot of all environment variables at time of call.
        fn vars() -> Map[Str, Str]

        /// Current working directory.
        fn cwd() -> Str

        /// The operating-system process ID of this process.
        fn pid() -> Int
    }

    effect Write {
        /// Set an environment variable. Creates it if it does not exist.
        fn set_var(name: Str, value: Str)

        /// Remove an environment variable. No-op if the variable does not exist.
        fn remove_var(name: Str)
    }

    effect Exit {
        /// Terminate the process with an exit code. Requires Env.Exit (or Env), not Read or Write.
        /// This is a non-resumable operation — handlers intercept but cannot resume past exit.
        fn exit(code: Int) -> Never
    }
}
```

**Capability boundaries:**

| Declaration | Available operations |
|---|---|
| `! Env.Read` | `env.args()`, `env.var(...)`, `env.vars()`, `env.cwd()`, `env.pid()` |
| `! Env.Write` | `env.set_var(...)`, `env.remove_var(...)` |
| `! Env.Exit` | `env.exit(...)` |
| `! Env` | All of the above |

`env.exit()` requires `! Env.Exit` (granted by `! Env`) because it is neither pure observation nor environment mutation — it is process termination. A function declaring only `! Env.Read` or `! Env.Write` cannot call `env.exit()`. A CLI entry point that only reads arguments and exits can declare `! Env.Read, Env.Exit` and leave out `Env.Write`:

```blink
fn load_config() -> Config ! Env.Read {
    let db = env.var("DATABASE_URL") ?? panic("DATABASE_URL not set")
    let port = match (env.var("PORT") ?? "8080").parse_int() {
        Ok(n) => n
        Err(_) => 8080
    }
    Config { db_url: db, port: port }
}

fn run_cli() ! Env.Read, Env.Exit, IO {
    let args = env.args()
    if args.len() < 2 {
        io.println("Usage: mytool <command>")
        env.exit(1)  // requires ! Env.Exit; ! Env grants it
    }
    let verbose = env.var("VERBOSE").is_some()
    let cwd = env.cwd()
    io.println("Running from {cwd}")
}
```

**Why `env.exit()` is an effect operation, not standalone:**

`panic()` is untracked divergence — it represents a program error (invariant violation). `exit()` is intentional control flow with an observable result (the exit code). Making it an effect operation means:

1. Handlers can intercept it for testing — a mock `Env` handler captures exit codes instead of terminating the test runner
2. The capability system tracks which code can terminate the process
3. Sandboxed code cannot exit unless granted `! Env.Exit` (or `! Env`)

**A handler cannot return from an op declared `-> Never`.** This rule applies to every effect op declared `-> Never`, not only to `exit`. A handler gives an op its result when the op's `fn` returns (§4.7 *Defining a handler*). No value of type `Never` exists (§3.2), so the handler's `fn` for such an op cannot return. Its body must diverge (§3.3 *Divergence and Body Completeness*). The mock below ends its `exit` with `panic`.

```blink
test "CLI exits with 1 on missing args" {
    let mut exit_code = -1
    let mock = handler Env {
        fn args() -> List[Str] { ["mytool"] }
        fn var(name: Str) -> Option[Str] { None }
        fn vars() -> Map[Str, Str] { Map.new() }
        fn cwd() -> Str { "/tmp" }
        fn pid() -> Int { 4242 }
        fn set_var(name: Str, value: Str) { }
        fn remove_var(name: Str) { }
        fn exit(code: Int) -> Never {
            exit_code = code
            panic("env.exit({code})")
        }
    }
    assert_panics(matching: "env.exit(1)") {
        with mock, capture_log([]) {
            run_cli()
        }
    }
    assert_eq(exit_code, 1)
}
```

`assert_panics` (§2.20) stops the run: it catches the panic from `exit`, and the test continues after its block. `exit_code` only records the code. It is a captured `let mut`, so it is a shared cell, and the write in `exit` is visible after the block (§4.7 *Defining a handler*). The op writes the cell before it panics, because nothing after the `panic` runs.

**A handler cannot end the `with` body early.** A test observes a diverging op by panicking in it and wrapping the `with` in `assert_panics`. Production code that needs early exit declares an op whose result type carries the outcome (e.g. `Result[T, E]`), and the caller propagates it with `?`.

The mock lists all eight operations at one level. A handler for an effect with children gives every operation of the tree, whichever child declares it (§4.12 *Leaf effects and effect trees*).

**`env.vars()` returns a snapshot:** The returned `Map[Str, Str]` is a copy of the environment at the time of the call. Subsequent `env.set_var()` or `env.remove_var()` calls do not affect previously returned maps. This ensures deterministic behavior in concurrent code.

**Thread safety:** `env.set_var()` and `env.remove_var()` are process-global mutations. Calls are serialized. In concurrent programs using `! Async`, only one task can modify the environment at a time. Use sparingly — prefer configuration structs over environment mutation.

**Children.** `env.set_var()` and `env.remove_var()` change this program's environment for all later children. To change the environment of one child, pass `env:` to the op (§4.4.8). There is no `set_cwd`: to run one child in another directory, pass `cwd:` to the op (§4.4.8).

---

#### 4.4.4 DB.Write Scoped Transaction

`db.transaction` implements the `Scoped` trait (see §4.7.2), providing automatic `BEGIN`/`COMMIT`/`ROLLBACK` semantics via `with`. It requires the `DB.Write` effect.

```blink
fn transfer(from_id: Int, to_id: Int, amount: Int) -> Result[(), DBError] ! DB.Write {
    with db.transaction() {
        let from = db.query_one(t"SELECT balance FROM accounts WHERE id = {from_id}")?
        let to_acct = db.query_one(t"SELECT balance FROM accounts WHERE id = {to_id}")?

        if from.get_int("balance").unwrap() < amount {
            return Err(DBError.ExecError("insufficient funds"))
        }

        db.execute(t"UPDATE accounts SET balance = balance - {amount} WHERE id = {from_id}")?
        db.execute(t"UPDATE accounts SET balance = balance + {amount} WHERE id = {to_id}")?
        Ok(())
    }
}
```

**Semantics:**

- `enter()` calls `db.begin()` before the block body executes
- On normal completion: `exit(true)` calls `db.commit()`
- On error (`?` propagation or `return`): `exit(false)` calls `db.rollback()`
- `return` inside the block returns from the **enclosing function**, not just the transaction — same as `async.scope`
- The block's type is `Result[T, DBError]` where `T` is inferred from the last expression
- The `with db.transaction()` expression is itself an expression — it can appear on the right side of `let`

**Block semantics, not closure semantics:** The transaction body is a block that runs in the enclosing function's context. The `?` operator propagates errors directly to the enclosing function's `Result` return type, and `return` exits the enclosing function. This is distinct from a closure, where `?` and `return` would operate within the closure's own scope.

**Effect operations go through handles, not bindings:** When `as tx` is used (e.g., to access a savepoint handle), `db.execute()` still routes through the `db` effect handle — `tx` is the `Scoped.Context` value, not a replacement for the effect handle.

**Manual API:** `db.begin()`, `db.commit()`, `db.rollback()` remain available for advanced patterns (nested transactions via SAVEPOINTs, long-running operations). See [db-module-design.md](../decisions/db-module-design.md) Q6.

**History:** Originally specified as special syntax (3-1 vote, see [transaction-block-syntax.md](../decisions/transaction-block-syntax.md)). Superseded by the general `Scoped` mechanism (5-0 vote, see [scoped-block-mechanism.md](../decisions/scoped-block-mechanism.md)), which gives the same block semantics through a trait.

---

#### 4.4.5 Filesystem Operations

The `fs` handle is in scope when a function declares `! FS` or one of its sub-effects (`FS.Read`, `FS.Write`, `FS.Delete`, `FS.Watch`). Every filesystem operation can fail — a path may not exist, permission may be denied, a disk may be full — so each returns `Result[T, FsError]`. A failure is never a silent sentinel value; it is a typed error the caller must handle or propagate with `?`.

| Operation | Signature | Effect |
|---|---|---|
| `fs.read` | `fs.read(path: Str) -> Result[Str, FsError]` | `FS.Read` |
| `fs.write` | `fs.write(path: Str, content: Str) -> Result[(), FsError]` | `FS.Write` |
| `fs.list_dir` | `fs.list_dir(path: Str) -> Result[List[Str], FsError]` | `FS.Read` |
| `fs.stat` | `fs.stat(path: Str) -> Result[FileInfo, FsError]` | `FS.Read` |
| `fs.delete` | `fs.delete(path: Str) -> Result[(), FsError]` | `FS.Delete` |

Directory listing and file metadata are reads, so `fs.list_dir` and `fs.stat` need only `FS.Read` — there is no `FS.List` or `FS.Stat` sub-effect.

```blink
fn load(path: Str) -> Result[Config, FsError] ! FS.Read {
    let text = fs.read(path)?
    Ok(parse_config(text))
}
```

**The error type: `FsError`.** A filesystem failure carries three fields — the operation that failed, the path it failed on, and the underlying OS error code:

```blink
pub type FsOp {
    Read
    Write
    ListDir
    Stat
    Delete
}

pub type FsError {
    op: FsOp
    path: Str
    code: Errno
}
```

`code` is the `Errno` newtype from `std.errno` — the same `Errno` value that `libc.*` and `io.*` return. `fs` wraps it with the operation and the path so the message can name *what* was being done and *to what*. `Errno` on its own says `ENOENT`; `FsError` says that reading `/etc/app.toml` gave `ENOENT`.

`FsError` implements `Display`. The rendered form follows the convention `op path: message`:

```blink
match fs.read("/etc/app.toml") {
    Ok(text) => process(text)
    Err(e)   => io.eprintln("{e}")   // read /etc/app.toml: No such file or directory
}
```

For the common branch — "did this fail because the file was not there?" — `FsError` provides a predicate so callers do not compare error codes by hand:

```blink
fn read_cache(cache_path: Str) -> Result[Option[Str], FsError] ! FS.Read {
    match fs.read(cache_path) {
        Ok(text) => Ok(Some(text))
        Err(e) => {
            if e.not_found() {
                Ok(None)          // an absent cache is not an error here
            } else {
                Err(e)
            }
        }
    }
}
```

**File metadata: `fs.stat`.** `fs.stat` returns the metadata of the file at `path`. It follows symbolic links.

```blink
@derive(Eq)
pub type FileKind {
    File
    Dir
    Other
}

pub type FileInfo {
    kind: FileKind
    size: Int        // length in bytes
    mtime: Instant   // time of the last change to the contents (wall clock, §3.2.3)
}
```

**Existence is a `not_found()` match on `fs.stat`.** Blink has no `fs.exists`. To ask whether a path exists, match the result of `fs.stat`:

```blink
import std.fs.{FsError, FileKind}

fn is_stale(src: Str, out: Str) -> Result[Bool, FsError] ! FS.Read {
    let src_info = fs.stat(src)?
    match fs.stat(out) {
        Ok(out_info) => Ok(out_info.mtime < src_info.mtime)
        Err(e) => {
            if e.not_found() {
                Ok(true)          // no output yet, so it is stale
            } else {
                Err(e)
            }
        }
    }
}

fn is_dir(path: Str) -> Result[Bool, FsError] ! FS.Read {
    Ok(fs.stat(path)?.kind == FileKind.Dir)
}
```

Do not use `fs.stat(p).is_ok()` as an existence test. It reads every error as "absent", so a path that the program may not read (`EACCES`) looks like a path that does not exist.

**Propagation is exact.** `?` on an `fs` call propagates `FsError` unchanged; it does not convert to the enclosing function's error type. A function that reads a file and returns a different error type must adapt with `.map_err(...)` — there is no implicit `.into()` (see error propagation, §3c).

`FsError`, `FsOp`, `FileInfo` and `FileKind` live in `std.fs` and are named with `import std.fs` — the same way `net.request`'s `NetError` is named with `import std.net`. The `fs` operation handle needs no import (it comes from the `! FS` effect on the signature), but the error *type* a caller matches on does.

**No file handles in v1.** The `fs` surface is exactly the five path-taking operations above. There is no `fs.open`, no `fs.create`, and no handle-taking read — a read is `fs.read(path)`, never `fs.read(handle)`. Streaming and incremental access are a post-v1 addition and will arrive as `fs` handle ops that take a file handle (rule 3 of §4.4), not as overloads of `fs.read` — Blink has no function overloading. Examples in §4.7 (*Scoped resources: `with...as`*) that open a `Closeable` file handle with `with ... as` illustrate the scoped-resource mechanism against that planned handle API; they are marked there as post-v1.

#### 4.4.6 Sockets in `std.net`: UDP and Unix-Domain

Decided by panel deliberation [`udp-gate-sockaddr-flags`](../decisions/udp-gate-sockaddr-flags.md). `std.net` gives UDP a socket type built on `libc.recvfrom_bytes` and `libc.sendto_bytes` (§9.1.3.4).

**Addresses.** `SockAddr` is a plain Blink enum. It is not an `@ffi.struct`.

```blink
pub type Ipv4Addr { bits: Int }             // 32-bit address, host order
pub type Ipv6Addr { hi: Int, lo: Int }      // 128-bit address as two 64-bit halves

@derive(Eq, Hash)
pub type SockAddr {
    V4(ip: Ipv4Addr, port: Int)
    V6(ip: Ipv6Addr, port: Int, scope_id: Int)
}
```

- `SockAddr` derives `Eq` and `Hash`, so it can be a `Map` key for per-peer state.
- `Display` prints `10.0.0.1:53`, `[::1]:53`, and `[fe80::1%2]:53` (`%` followed by the numeric `scope_id` when it is not 0).
- `SockAddr.parse(s: Str) -> Result[SockAddr, NetError]` reads a numeric address in the same forms. It does no DNS lookup. A string it cannot read gives `NetError.InvalidAddr(input: s)`.
- IPv6 `flowinfo` is not modelled; the runtime sends 0.
- An IPv4-mapped IPv6 address (`::ffff:a.b.c.d`) stays a `V6` value. `SockAddr` has no conversion to `V4` in this gate. Code that compares peers from a dual-stack socket must allow for the mapped form.

**Sockets.**

```blink
pub fn udp_bind(addr: SockAddr) -> Result[UdpSocket, NetError] ! Net.Listen
pub fn resolve(host: Str, port: Int) -> Result[List[SockAddr], NetError] ! Net.DNS

pub trait UdpSocketOps {
    fn recv_from(self, *, max: Int = 65535) -> Result[(Bytes, SockAddr), NetError] ! Net.Listen
    fn send_to(self, data: Bytes, dest: SockAddr) -> Result[(), NetError] ! Net.Connect
    fn local_addr(self) -> Result[SockAddr, NetError] ! Net.Listen
    fn set_timeout(self, ms: Int) ! Net.Listen
    fn close(self) ! Net.Listen
}
```

- `udp_bind` creates the socket and binds it. Bind to port 0 to get a free port, then read it with `local_addr`.
- `recv_from` returns one datagram and its sender. The semantics of §9.1.3.4 apply: a 0-length datagram is `Ok` with empty `Bytes`, and a datagram larger than `max` is truncated without an error. The default `max` of 65535 holds any UDP datagram. A program that expects only small datagrams can pass a smaller `max`.
- `send_to` sends the whole datagram or returns an error. If the kernel sends fewer bytes than `data.len()`, `send_to` returns an `Err`, so no count is returned.
- `resolve` returns every address that the name resolves to, in resolver order. It uses the same resolver as `net.request`.
- `UdpSocket` has no `connect`, no unbound constructor, and no `recv` or `send` without an address in this gate.

```blink
import std.net.{SockAddr, NetError, udp_bind}

fn echo_once() -> Result[(), NetError] ! Net.Listen, Net.Connect {
    let addr = SockAddr.parse("127.0.0.1:0")?
    let sock = udp_bind(addr)?
    let (data, peer) = sock.recv_from(max: 512)?
    sock.send_to(data, peer)?
    sock.close()
    Ok(())
}
```

##### Unix-domain stream sockets

`std.net` gives Unix-domain stream sockets the same second-tier shape as UDP: std functions and methods with rows, not `net` handle ops (§4.4 *Every side effect has a row*).

```blink
pub fn unix_listen(path: Str) -> Result[UnixListener, NetError] ! Net.Listen
pub fn unix_connect(path: Str) -> Result[UnixStream, NetError] ! Net.Connect

pub trait UnixListenerOps {
    fn accept(self) -> Result[UnixConn, NetError] ! Net.Listen
    fn close(self) ! Net.Listen
}

pub trait UnixConnOps {
    fn read_line(self) -> Result[Str?, NetError] ! Net.Listen
    fn write(self, data: Str) -> Result[(), NetError] ! Net.Listen
    fn close(self) ! Net.Listen
}

pub trait UnixStreamOps {
    fn read_line(self) -> Result[Str?, NetError] ! Net.Connect
    fn write(self, data: Str) -> Result[(), NetError] ! Net.Connect
    fn close(self) ! Net.Connect
}
```

- `unix_listen` creates a socket node at `path` and listens on it. It needs `Net.Listen` only. A sandbox that denies `FS.Write` but grants `Net.Listen` therefore still lets code create a socket node in any directory that the process can write to.
- `unix_listen` never removes a file. If `path` already exists, it returns `Err(NetError.Os(op: "bind", code: ...))` with the code `EADDRINUSE`. To replace a stale socket node, the caller deletes it first with `fs.delete(path)`, which needs `FS.Delete`.
- `accept` blocks until a client connects, then returns the connection to that client. `accept` returns a `UnixConn`; `unix_connect` returns a `UnixStream`. The two types have the same methods and different rows (see below).
- `read_line` returns the next line without its line terminator, or `None` at end of stream.
- `write` sends all of `data` or returns an error.

**Rows of socket methods.** Rule 2 (§4.4) requires a row on every method of an open socket. The row of a method on an open socket follows this rule (panel deliberation [`open-socket-rows`](../decisions/open-socket-rows.md)):

> A method on an open socket carries the row of the function or method that made the socket. A method that sends to a peer address that the caller gives as an argument carries `Net.Connect` in its place.
>
> Each socket type has exactly one maker row: when two std functions with different rows make sockets, they return different types.

The first sentence gives `send_to` the row `Net.Connect` alone. It does not add `Net.Connect` to the row of the maker. A later method of a socket type gets its row from this rule.

The second sentence is why `accept` and `unix_connect` return different types. A method has one row for every value of its type. If one type had two makers with different rows, only the union row `! Net.Listen, Net.Connect` would be sound, and it would make a client ask for `Net.Listen` and a server ask for `Net.Connect`. The sentence does not bar a later trait over both stream types. Such a trait takes the union row, and each impl narrows its row (§3.6 *Effect-row subtype for trait impls*, E0904).

| Type | Made by | Method | Row |
|---|---|---|---|
| `UdpSocket` | `udp_bind` | `recv_from` | `Net.Listen` |
| `UdpSocket` | `udp_bind` | `send_to` | `Net.Connect` (the peer address is an argument) |
| `UdpSocket` | `udp_bind` | `local_addr`, `set_timeout`, `close` | `Net.Listen` |
| `UnixListener` | `unix_listen` | `accept`, `close` | `Net.Listen` |
| `UnixConn` | `UnixListener.accept` | `read_line`, `write`, `close` | `Net.Listen` |
| `UnixStream` | `unix_connect` | `read_line`, `write`, `close` | `Net.Connect` |

When a `UnixConn` is given where a `UnixStream` is expected, or the other way, the type-mismatch error names the other type and the function that makes it:

```
error[TypeError]: mismatched types
 --> relay.bl:12:12
   |
12 |     handle(conn)
   |            ^^^^ expected `UnixConn`, found `UnixStream`
   |
   = note: `UnixStream` is made by `unix_connect`; `UnixConn` is made by `UnixListener.accept`
```

```blink
import std.net.{NetError, unix_listen}

fn serve_once(path: Str) -> Result[(), NetError] ! Net.Listen {
    let listener = unix_listen(path)?
    let conn = listener.accept()?     // a UnixConn
    match conn.read_line()? {
        Some(line) => conn.write("echo: {line}\n")?
        None => ()
    }
    conn.close()
    listener.close()
    Ok(())
}
```

A client uses `unix_connect`. It needs `Net.Connect` alone:

```blink
import std.net.{NetError, unix_connect}

fn ask(path: Str, question: Str) -> Result[Str?, NetError] ! Net.Connect {
    let conn = unix_connect(path)?    // a UnixStream
    conn.write("{question}\n")?
    let reply = conn.read_line()?
    conn.close()
    Ok(reply)
}
```

#### 4.4.7 Rand Operations

The `Rand` effect gives random values. It is a leaf effect with three operations:

```blink
@handle_all
effect Rand {
    /// A uniform random integer in the closed interval [lo, hi]. The caller makes sure lo <= hi.
    fn int(lo: Int, hi: Int) -> Int

    /// A uniform random float in the half-open interval [0.0, 1.0).
    fn float() -> Float

    /// n uniform random bytes. The caller makes sure n >= 0. The result has length n.
    fn bytes(n: Int) -> Bytes
}
```

**Handler operations are monomorphic.** As with `IO` (§4.4), the surface that a program calls is a stdlib wrapper, not the effect operation. Each wrapper does exactly one operation call:

| Wrapper on the `rand` handle | Operation it calls | Argument rule |
|---|---|---|
| `rand.int(r: Range[Int]) -> Int` | `int(lo, hi)` | `a..b` gives `int(a, b - 1)`; `a..=b` gives `int(a, b)`. An empty range panics |
| `rand.float() -> Float` | `float()` | None |
| `rand.bytes(n: Int) -> Bytes` | `bytes(n)` | `n < 0` panics |

```blink
fn roll() -> Int ! Rand {
    rand.int(1..=6)
}

fn token() -> Bytes ! Rand {
    rand.bytes(32)
}
```

User code calls only the wrappers. `rand.int(lo, hi)` with two `Int` arguments does not compile. The two-`Int` form is the operation that a `handler Rand { ... }` implements, and that a handler calls as `default.int(lo, hi)` (§4.7.1).

```blink
fn always_low() -> Handler[Rand ! Rand] {
    handler Rand {
        fn int(lo: Int, hi: Int) -> Int { lo }
        fn float() -> Float { default.float() }
        fn bytes(n: Int) -> Bytes { default.bytes(n) }
    }
}
```

Under `with always_low() { ... }`, `rand.int(1..=6)` returns 1. `float` and `bytes` forward on purpose to the enclosing handler. `Rand` is marked `@handle_all`, so a handler that omits them gets the warning `PartialHandler` (§4.7.1).

**Empty range.** `rand.int` panics when its range holds no value: `5..5`, `5..2`, or `5..=4`. The panic message names `rand.int` and the range, for example `rand.int: empty range 5..5`. A range with literal ends gets no compile-time check here; it panics at run time like a computed range.

**Uniformity.** Every handler must give exactly uniform results. `int(lo, hi)` gives each value in `[lo, hi]` with the same probability, with no modulo bias. `float()` gives a uniform value in `[0.0, 1.0)`. `bytes(n)` gives `n` independent uniform bytes. This is an obligation on each handler, the default handler and user handlers alike. The spec names no algorithm.

**The wrapper checks each result.** A user handler can return a value that breaks the operation contract. Each wrapper checks the result of every call, in every build mode:

- `int(lo, hi)`: the result is in `[lo, hi]`.
- `float()`: the result is in `[0.0, 1.0)`.
- `bytes(n)`: the result length is `n`.

A failed check panics with `Rand handler contract violated`, then the operation, its arguments and the value it returned, for example `Rand handler contract violated: int(0, 4) returned 9`. Code that uses a result, such as an index into a list, can trust it.

**The default handler.** The stdlib default handler is a cryptographically secure generator. It has these properties:

- Its output cannot be predicted from earlier output.
- It is seeded from operating-system entropy.
- No two threads share a stream.
- After a process fork, the child does not repeat the stream of the parent.

The spec names no algorithm. The default handler is suitable for secret material such as keys and tokens. An installed `with` handler replaces it, so code that makes secrets must not run under a handler it does not trust.

**Seeding is a handler concern.** `Rand` has no seed, reseed or fork operation. To get a deterministic stream, install a handler, for example `with mock_rand(seed).as_handler() { ... }` in a test (§8.10.4). The stdlib has no production seeded handler.

**Helpers in `std.random`.** Generic helpers are free functions in `std.random`, not methods on the handle:

```blink
pub fn shuffle[T](xs: List[T]) -> List[T] ! Rand
pub fn choice[T](xs: List[T]) -> Option[T] ! Rand
```

- `shuffle` returns a new list. It does a Fisher-Yates shuffle with exactly `xs.len() - 1` calls to `rand.int` (none for an empty list). `xs` does not change.
- `choice` returns `None` for an empty list and makes no draw. Otherwise it returns one element from one call to `rand.int`.

```blink
import std.random.{shuffle, choice}

fn deal(deck: List[Card]) -> List[Card] ! Rand {
    shuffle(deck)
}

fn pick_server(servers: List[Str]) -> Option[Str] ! Rand {
    choice(servers)
}
```

**`rand.<name>` always means the handle.** `rand` is a reserved handle name (§3c.4 *Effect Handle Operations*), so `rand.shuffle(xs)` does not find the free function. It is `UnresolvedMethod` (E0505). The diagnostic lists the operations of `Rand` and gives the import:

```
error[E0505]: `shuffle` is not an operation of effect `Rand`
  = note: `Rand` operations are `int`, `float`, `bytes`
  = help: `shuffle` is a function in `std.random`
  = fix: add `import std.random.{shuffle}` and call `shuffle(deck)`
```

**Python-style integer calls.** `rand.int(0, 10)` and `rand.int(10)` do not compile. Each diagnostic gives the fix as a range:

```
error: `rand.int` takes 1 argument (a Range), found 2
  = fix: rand.int(0..10)
  = note: use `0..=10` to include 10 (Python's randint includes the upper bound)
```

```
error[TypeError]: mismatched types
  = note: expected `Range[Int]`, found `Int`
  = fix: rand.int(0..10)
```

#### 4.4.8 Process Operations

The `process` handle is in scope when a function declares `! Process` or one of its sub-effects. `Process.Spawn` runs other programs, waits for them, and replaces this program with another one. `Process.Signal` sends signals to child processes.

`ChildEnv` says which environment variables a child gets. It describes the child's environment only. The type lives in `std.process`:

```blink
@derive(Eq, Debug)
pub type ChildEnv {
    Inherit                    // this program's environment, as it is when the op runs
    Change(Map[Str, Str?])     // that environment; Some(v) sets a name to v, None removes it
    Only(Map[Str, Str])        // exactly these variables, nothing inherited
}
```

```blink
effect Process {
    effect Spawn {
        /// Run cmd with args, wait for it to exit, and return what it wrote.
        fn run(cmd: Str, args: List[Str], *, stdin: Str? = None, env: ChildEnv = ChildEnv.Inherit, cwd: Str? = None) -> Result[ProcessResult, ProcessError]

        /// Start cmd with args and return at once.
        fn spawn(cmd: Str, args: List[Str], *, env: ChildEnv = ChildEnv.Inherit, cwd: Str? = None) -> Result[Child, ProcessError]

        /// Wait for a child that spawn started to exit, and return what it wrote.
        fn wait(child: Child) -> Result[ProcessResult, ProcessError]

        /// Replace this program with cmd. Returns only if cmd cannot start.
        /// A call also needs Env.Exit (see below).
        fn exec(cmd: Str, args: List[Str], *, env: ChildEnv = ChildEnv.Inherit, cwd: Str? = None) -> Result[Never, ProcessError]
    }

    effect Signal {
        /// Send signal number sig to a child that spawn started.
        fn signal(child: Child, sig: Int) -> Result[(), ProcessError]
    }
}
```

| Operation | Signature | Effect |
|---|---|---|
| `process.run` | `process.run(cmd: Str, args: List[Str], *, stdin: Str? = None, env: ChildEnv = ChildEnv.Inherit, cwd: Str? = None) -> Result[ProcessResult, ProcessError]` | `Process.Spawn` |
| `process.spawn` | `process.spawn(cmd: Str, args: List[Str], *, env: ChildEnv = ChildEnv.Inherit, cwd: Str? = None) -> Result[Child, ProcessError]` | `Process.Spawn` |
| `process.wait` | `process.wait(child: Child) -> Result[ProcessResult, ProcessError]` | `Process.Spawn` |
| `process.exec` | `process.exec(cmd: Str, args: List[Str], *, env: ChildEnv = ChildEnv.Inherit, cwd: Str? = None) -> Result[Never, ProcessError]` | `Process.Spawn`, `Env.Exit` |
| `process.signal` | `process.signal(child: Child, sig: Int) -> Result[(), ProcessError]` | `Process.Signal` |

**`cmd` is a program, not a command line.** `process.run("git", ["status", "--short"])` runs `git` with two arguments. No shell reads the arguments, so a space or a `$` in an argument is not special. Blink has no shell op. To run a shell command line, run the shell:

```blink
fn disk_usage(dir: Str) -> Result[Str, ProcessError] ! Process.Spawn {
    let r = process.run("sh", ["-c", "du -sh {dir}"])?
    Ok(r.out)
}
```

The shell reads `dir` here, so a `dir` from user input can inject commands. Prefer a program and an argument list.

**A non-zero exit is data.** The types live in `std.process`:

```blink
pub type ProcessResult {
    out: Str          // everything the child wrote to standard output
    err_out: Str      // everything the child wrote to standard error
    exit_code: Int
}

pub type ProcessOp {
    Run
    Spawn
    Wait
    Exec
    Signal
}

pub type ProcessError {
    op: ProcessOp
    cmd: Str
    code: Errno
}

pub opaque type Child
```

`process.run` and `process.wait` return `Ok` when the child ran to the end, whatever its exit code. `Err` means that the operation itself failed: the program was not found or could not start, the wait failed, or the signal could not be sent. `ProcessError` has the shape of `FsError` (§4.4.5): the operation, the command, and the `Errno`. Its `Display` follows the same convention, `op cmd: message`, for example `run gti: No such file or directory`.

```blink
import std.process.{ProcessError}

fn build(target: Str) -> Result[Bool, ProcessError] ! Process.Spawn, IO.Print {
    let r = process.run("make", [target])?
    if r.exit_code != 0 {
        io.println(r.err_out)
    }
    Ok(r.exit_code == 0)
}
```

**Standard input.** With `stdin: None`, the default, the child reads its standard input from the null device, so its first read sees end of input. A child never starts with its standard input closed. With `stdin: Some(s)`, the child reads `s` and then end of input. `process.spawn` gives the child the null device as standard input.

```blink
fn word_count(text: Str) -> Result[Str, ProcessError] ! Process.Spawn {
    let r = process.run("wc", ["-w"], stdin: Some(text))?
    Ok(r.out.trim())
}
```

**The child's environment.** With `env: ChildEnv.Inherit`, the default, the child gets this program's environment as it is when the op runs. `ChildEnv.Change(m)` gives the child that environment with each name in `m` set to its `Some(v)` value, and each name with a `None` value removed. `ChildEnv.Only(m)` gives the child exactly the variables in `m` and nothing else. The parameter works the same on `process.run`, `process.spawn` and `process.exec`; on `process.exec` the new program gets that environment.

This program's own environment does not change, and later children do not see the change. The op needs no `Env` effect. A child sees each write of `env.set_var` and `env.remove_var` (§4.4.3) whole or not at all: the read of the inherited environment does not interleave with those writes. A user `handler Env` or `mock_env` (§8.10.3) changes what `env.var` returns to Blink code. It does not change what a real child inherits.

To set one variable for one child, use `Change`:

```blink
fn test_in_ci() -> Result[ProcessResult, ProcessError] ! Process.Spawn {
    process.run("make", ["test"], env: ChildEnv.Change(Map.from([("CI", Some("1"))])))
}
```

To remove a variable, give it the value `None`:

```blink
fn build_without_proxy() -> Result[ProcessResult, ProcessError] ! Process.Spawn {
    process.run("make", [], env: ChildEnv.Change(Map.from([("HTTP_PROXY", None)])))
}
```

To start a child with a known environment, use `Only`. A bare `cmd` is found on the `PATH` of the child (see *Finding the program*), so give `Only` a `PATH`, or give an absolute `cmd`:

```blink
fn hermetic_build() -> Result[ProcessResult, ProcessError] ! Process.Spawn {
    let clean = ChildEnv.Only(Map.from([("PATH", "/usr/bin:/bin"), ("HOME", "/nonexistent")]))
    process.run("make", ["all"], env: clean)
}
```

A `Change` map has values of type `Str?`. When a map has `Str` values where `Str?` is expected, the type error (`TypeError`, E0300) has a help line that shows the call with each value wrapped in `Some(...)`.

**Finding the program.** A `cmd` that holds no `/` is found on the `PATH` of the child. This is the `PATH` after `env` applies, so a `Change` that sets `PATH` also changes the search. The search happens before the child starts. If no program is found, the call returns `Err` with `ENOENT`; this is not an exit code of a child. Under `Only(m)`, when `m` has no `PATH`, a bare `cmd` gives `ENOENT`.

**Working directory.** With `cwd: None`, the default, the child runs in the working directory of this program. With `cwd: Some(dir)`, the child runs in `dir`. A relative `dir` is relative to the working directory of this program. This program's working directory does not change. `cwd` replaces the `sh -c "cd {dir} && ..."` pattern, which lets a `dir` from user input inject commands.

A relative `cmd` that holds a `/` (for example `./configure`) is resolved against `dir`. A relative entry in the child's `PATH` (for example `.` or `bin`) is also resolved against `dir`. So a `PATH` entry `.` can run a program that is in `dir`: use only absolute `PATH` entries when `dir` is not trusted.

If `dir` does not exist, is not a directory, or the program is not found, the call returns `Err` with `ENOENT`, or with the code the operating system gives (for example `ENOTDIR`), and no child starts. This also holds when `dir` goes away just before the child starts: the call returns `Err`, never an exit code of a child.

```blink
fn configure(src: Str) -> Result[ProcessResult, ProcessError] ! Process.Spawn {
    process.run("./configure", ["--prefix=/usr/local"], cwd: Some(src))
}
```

**Strings that cannot reach a child.** An empty environment name, a name that holds `=` or NUL, a value that holds NUL, and a NUL in `cmd` or in any element of `args`, give `Err` with `EINVAL`, and no child starts. This holds for `process.run`, `process.spawn` and `process.exec`.

**`Child` is a handle-op value.** `process.spawn` makes a `Child`, so the operations that consume one, `process.wait` and `process.signal`, are `process` handle ops too (§4.4, rule 3). Code with no `Process` effect can hold a `Child` but cannot wait on it or signal it. `Child` is opaque and has no methods. `process.wait` on a child that already exited returns the same `ProcessResult` again. The signal numbers are constants in `std.process` (`SIGHUP`, `SIGINT`, `SIGQUIT`, `SIGKILL`, `SIGTERM`).

```blink
import std.process.{ProcessResult, ProcessError, SIGTERM}
import std.time.{Duration}

fn run_with_deadline(cmd: Str, args: List[Str], limit: Duration) -> Result[ProcessResult, ProcessError] ! Process, Time.Sleep {
    let child = process.spawn(cmd, args)?
    time.sleep(limit)
    let _ = process.signal(child, SIGTERM)   // an Err here means the child already exited
    process.wait(child)
}
```

**`process.exec` ends this program.** On success, the operating system replaces this program with `cmd`, so the call does not return. The result type is `Result[Never, ProcessError]`: `process.exec(cmd, args)?` has type `Never`, and the code after it is unreachable. Because a successful call ends the program, a call to `process.exec` needs `Env.Exit` as well as `Process.Spawn`. A function that cannot call `env.exit` cannot end the program through `process.exec`.

```blink
fn launch(tool: Str, args: List[Str]) ! Process.Spawn, Env.Exit, IO {
    let e = process.exec(tool, args).unwrap_err()   // exec returns only on failure
    io.eprintln("{e}")
    env.exit(127)
}
```

**Mock handlers.** A `handler Process` replaces every operation, so a test can run code that starts programs without starting any. Operations that the mock leaves out delegate to the enclosing handler (§4.7.1).

```blink
test "build reports a failed make" {
    let mock = handler Process {
        fn run(cmd: Str, args: List[Str], stdin: Str?, env: ChildEnv, cwd: Str?) -> Result[ProcessResult, ProcessError] {
            Ok(ProcessResult { out: "", err_out: "no rule for target", exit_code: 2 })
        }
    }
    with mock {
        assert_eq(build("all"), Ok(false))
    }
}
```

A handler implements each op with all its parameters. A default value applies at the call site only. When a handler leaves out a parameter, the error names the missing parameter and offers a fix that adds it.

#### 4.4.9 Standard Input (`IO.Read`)

The `IO.Read` sub-effect reads the standard input of the process. It has one primitive operation, `read_bytes`, and two derived operations, `read_line` and `read_all` (§4.7.1):

```blink
effect IO {
    effect Print
    effect Log

    @handle_all
    effect Read {
        /// Exactly n bytes, or fewer only at end of input. Empty at end of input.
        fn read_bytes(n: Int) -> Bytes

        /// The next line without its terminator, or None at end of input.
        fn read_line() -> Option[Str] {
            let mut line = Bytes.new()
            loop {
                let b = io.read_bytes(1)
                if b.is_empty() {
                    if line.is_empty() { return None }
                    break
                }
                if b.get(0) == Some(10) {
                    let n = line.len()
                    if n > 0 && line.get(n - 1) == Some(13) {
                        line = line.slice(0, n - 1)
                    }
                    break
                }
                line = line.concat(b)
            }
            match line.to_str() {
                Ok(s) => Some(s)
                Err(_) => panic("io.read_line: input is not valid UTF-8; read it with io.read_bytes")
            }
        }

        /// All of the input that is left. Empty at end of input.
        fn read_all() -> Str {
            let mut all = Bytes.new()
            loop {
                let chunk = io.read_bytes(65536)
                all = all.concat(chunk)
                if chunk.len() < 65536 { break }
            }
            match all.to_str() {
                Ok(s) => s
                Err(_) => panic("io.read_all: input is not valid UTF-8; read it with io.read_bytes")
            }
        }
    }
}
```

The bodies above define what the two derived operations return. The default handler answers all three operations from one buffer and gives the same results.

**The `io` methods.** A program calls `io.read_bytes(n)`, `io.read_line()` and `io.read_all()`. Each method calls its operation once. `io.read_bytes(n)` with `n <= 0` panics before the operation runs, so a handler never sees such an `n`. With `n > 0`, an empty result means end of input and nothing else.

```blink
fn main() ! IO {
    let mut sum = 0
    loop {
        match io.read_line() {
            Some(line) => sum = sum + (line.parse_int().ok() ?? 0)
            None => break
        }
    }
    io.println(sum)
}
```

**Lines.** A line ends at `\n` or at `\r\n`. `read_line` removes the terminator. A last line with no terminator is still a line. A blank line is `Some("")`, and end of input is `None`, so the two never look the same:

| Input left | `read_line()` calls give |
|---|---|
| `"a\nb\n"` | `Some("a")`, `Some("b")`, `None` |
| `"a\r\nb"` | `Some("a")`, `Some("b")`, `None` |
| `"\n"` | `Some("")`, `None` |
| `""` | `None` |

A line has no length limit.

**One stream.** The three operations take bytes from the front of one input stream, in the order the program calls them. A program can mix them in any order. A message with a header line and a body of known length reads both from the same stream:

```blink
fn read_message() -> Option[Str] ! IO.Read {
    let header = io.read_line()?
    let size = match header.strip_prefix("Content-Length: ")?.parse_int() {
        Ok(n) => n
        Err(_) => return None
    }
    if size <= 0 { return Some("") }
    match io.read_bytes(size).to_str() {
        Ok(body) => Some(body)
        Err(_) => None
    }
}
```

`io.read_bytes(n)` waits until it has `n` bytes or the input ends. A short result means the input ended. No `io` operation returns only the bytes that are ready now.

**Handler contract.** A handler for `IO.Read` must keep the same rules as the default handler:

1. Its `read_bytes(n)` returns exactly `n` bytes, or fewer only at end of input. The derived `read_all` stops at the first short result, so a handler that returns short chunks before the end cuts the input.
2. If it implements `read_line` or `read_all`, the results must be the same as the bodies above give over its own `read_bytes`. So `read_all()` returns the same text as the lines from repeated `read_line()` calls, each one followed by its terminator.

The compiler does not check these rules. `std.testing.stdin_from` keeps them (§8.10.1). `IO.Read` is marked `@handle_all`, so a handler for it that omits `read_bytes` gets the `PartialHandler` warning (W0545, §4.7.1). A derived operation that a handler omits runs its body above over that handler's `read_bytes`.

**Errors.** If the operating system reports a read failure, the operation panics. The panic message names the operation and the errno. If the bytes for `read_line` or `read_all` are not valid UTF-8, the operation panics, and the message names the operation and `io.read_bytes`. The operations do not replace bad bytes with U+FFFD: that gives wrong data with no signal. Code that must recover from a read failure uses `libc.read_bytes(0, n) -> Result[Bytes, Errno]` (§9.1.3.3) and makes no `io.read_*` call.

**Mixing with file descriptor 0.** The `io` stream can hold bytes that file descriptor 0 has already given. After any `io.read_*` call, the order of the bytes that `libc.read_bytes(0, ..)` or `std.io.read_fully(0, ..)` returns is not specified. A program reads standard input through `io` or through file descriptor 0, not both.

**Every line.** The v1 iterator is pure (§3c.1), so there is no `io.lines()`. Use one of these two forms:

```blink
fn count_words() -> Int ! IO.Read {
    let mut count = 0
    for line in io.read_all().lines() {
        count = count + line.split(" ").len()
    }
    count
}

fn echo_upper() ! IO.Read, IO.Print {
    loop {
        match io.read_line() {
            Some(line) => io.println(line.to_upper())
            None => break
        }
    }
}
```

The first form reads all the input before the loop starts. The second form reads one line at a time. `Str.lines()` uses the same line rules as `read_line` (§3), so both forms give the same lines.

A call to `io.lines()` is E0505 (UnresolvedMethod), with a help line that shows the two forms:

```
error[UnresolvedMethod]: no method `lines` on the `io` handle
 --> wc.bl:2:17
  |
2 |     for line in io.lines() {
  |                 ^^^^^^^^ no method `lines`
  |
  = help: read all the input, then split it: `for line in io.read_all().lines() { ... }`
  = help: or read one line at a time: `loop { match io.read_line() { Some(line) => ..., None => break } }`
```

**Migration.** In earlier versions, `io.read_line()` returned `Str`, with `""` for both a blank line and end of input. Code that uses the result as a `Str` now gets a type error. When the value comes from `io.read_line()`, the error has a help line that shows the `match` form:

```
error[TypeError]: mismatched types
 --> sum.bl:4:19
  |
3 |         let line = io.read_line()
4 |         if line == "" { break }
  |            ^^^^^^^^^^ expected `Option[Str]`, found `Str`
  |
  = note: `io.read_line()` returns `None` at end of input and `Some("")` for a blank line
  = help: match on it: `match io.read_line() { Some(line) => ..., None => break }`
```

No fix is machine-applicable. The help does not show `?? ""`, because that form gives back the old behavior, where a blank line and end of input look the same.

**Tests.** `std.testing.stdin_from(text)` gives a handler that reads `text` as standard input (§8.10.1). A test with no `IO.Read` handler reads the null device, so its first read sees end of input (§8.10.1).

```blink
import std.testing.{stdin_from, capture_print}

test "echo_upper prints each line in capitals" {
    let out: List[Str] = []
    with stdin_from("ab\n\ncd"), capture_print(out) {
        echo_upper()
    }
    assert_eq(out, ["AB", "", "CD"])
}
```

---

### 4.5 Effect Composition Rules

Effects propagate upward through the call graph. If function A calls function B, A must declare at least all of B's effects. The compiler enforces this transitively across the entire program.

```blink
fn check_inventory(item_id: Int) -> Result[Int, DBError] ! DB.Read {
    db.query_one(t"SELECT quantity FROM inventory WHERE id = {item_id}")?
}

fn log_check(item_id: Int) ! DB.Read, IO.Log {
    let qty = check_inventory(item_id)  // OK: caller has DB.Read
    io.log("Checked inventory for item {item_id}: {qty}")
}

fn caller_missing_effects() ! IO.Log {
    log_check(42)  // COMPILE ERROR: missing DB.Read
}
```

```
error[UndeclaredEffect]: undeclared effect
 --> order.bl:9:5
  |
9 |     log_check(42)
  |     ^^^^^^^^^ `log_check` requires effects `DB.Read, IO.Log`
  |
  = note: function `caller_missing_effects` declares `IO.Log` but is missing `DB.Read`
  = fix: add effect to signature:
  |
7 | fn caller_missing_effects() ! IO.Log, DB.Read {
  |                                     +++++++++
```

**Composition with parent effects:**

A function declaring a parent effect satisfies callee requirements for any of that parent's children:

```blink
fn do_everything() ! DB {
    check_inventory(42)  // OK: DB >= DB.Read
}
```

But a function declaring a child effect does NOT satisfy a callee requiring the parent:

```blink
fn write_task() ! DB.Write {
    db.exec(t"ALTER TABLE ...")?
}

fn read_only_caller() ! DB.Read {
    write_task()  // COMPILE ERROR: DB.Read does not grant DB.Write
}
```

**Effect subtyping:**

Effects follow a subtyping relationship: parent > child. A function that requires `! DB.Read` can be called by anything that has `! DB.Read`, `! DB.Read, DB.Write`, or `! DB`. The capability lattice is:

```
DB > DB.Read
DB > DB.Write
DB.Read + DB.Write = DB
```

This is standard capability attenuation: you can always pass a more-powerful capability where a less-powerful one is expected, but never the reverse.

**Proven and assumed rows.** Every effect row in Blink is either compiler-proven (including discharge by handler or `with`) or is the declared row of an @ffi decl, assumed under audit key K. An assumed row is an upper bound on the foreign call's behaviour; handlers do not intercept foreign calls. FFI regions change Ptr rules only, never rows.

No Blink operation skips a handler that its row names; only an `@ffi` call does.

This is the one normative statement of these rules. §9.1 (*The Effect Row*, *`@trusted`*) and §4.7 refer to it. An `@ffi` decl's row enters the program at the decl and from there propagates by the rules above, with no special case. `@trusted` does not discharge or narrow a row: a wrapper that calls an `@ffi` decl with row `! Net.Connect` must itself declare `Net.Connect` or discharge it in the usual way. The FFI regions of §9.1.1 (an `@ffi` or `@trusted` body, `with ffi.scope()`) decide where a `Ptr[T]` may appear; they do not change what any row says.

**Effect rows on trait impls.** When a trait declares a method `m` with effect row `R_t`, every `impl` that provides `m` must declare a row `R_i` such that `R_i ⊆ R_t` under the lattice above. The rule covers required methods and overrides of open defaults alike. An impl may *narrow* the signature (drop effects the trait declares but the impl does not use) but may not *widen* it (introduce effects the trait does not declare). A trait method with no `!` has the empty row, so its impls must have no `!` either. This preserves the trait's stated capability contract for every implementation: callers parameterized over `T: Trait` can rely on the trait's row as a sound upper bound on `m`'s effects across all `T`. A widening impl is rejected with `error[TraitContractEffectMismatch]` (E0904). Sealed (`final`) defaults have no override site and are therefore effect-monomorphic at their declaration. See §3.6 *Effect-row subtype for trait impls* for an example and §3.6 *The `final` Modifier* for the override-prevention semantics.

---

### 4.6 Effects on `main`

`main` is the root of the capability tree. It implicitly holds all effects. The root has a handler for each built-in effect (§4.3) except `State`, and those are the capabilities `main` holds. `main` also holds `State`, which has no handler (§4.16.1). A user-declared effect has no root handler (§4.12): `main` must discharge it with `with`, or the program does not compile (see *Unhandled user effects* below).

```blink
// Valid -- main implicitly has all effects
fn main() {
    io.print("Hello, world!")
    let data = fs.read("config.toml")
    let rows = db.query(t"SELECT * FROM users")?
}

// Also valid -- explicit annotation, but unnecessary
fn main() ! IO.Print, FS.Read, DB.Read {
    io.print("Hello, world!")
    let data = fs.read("config.toml")
    let rows = db.query(t"SELECT * FROM users")?
}
```

`main` is where ambient authority lives. It is the **only** place where capabilities are created from nothing. Every other function in the program receives its capabilities from its caller, tracing back to `main`. This is the ocap discipline: authority flows downward through explicit delegation, never materializes from thin air.

The LSP displays `main`'s actual effect set as an inlay hint, computed from the transitive closure of everything `main` calls. If `main` only calls pure functions and one `io.print`, the hint shows `! IO.Print` -- not "all effects." This is documentation, not enforcement.

**Why implicit on `main`:** Requiring `main` to declare effects is pure ceremony. `main` is the program. Its effect set is "whatever the program does." An explicit annotation on `main` would just be a worse version of what the compiler already computes. Every other public function must declare effects explicitly -- `main` is the single exception.

#### Unhandled user effects

A user-declared effect that reaches `main`'s body with no `with` that discharges it is a compile error, `UnhandledEffect` (E0539). The check uses the effect rows of the program (§4.5, §4.15), closures and `! _` rows included, and the same discharge rule as `with` (§4.7, and §4.7.2 *Scoped effect handlers* for a `Scoped` type whose `Context` is `Handler[E]`). Test blocks are the other root, and the same code reports them (§2.20).

```blink
effect Store {
    fn get(key: Str) -> Int
}

fn load() -> Int ! Store {
    store.get("count")
}

// COMPILE ERROR: nothing discharges `Store`
fn main() {
    io.println("{load()}")
}
```

```
error[UnhandledEffect]: unhandled effect `Store` in `main`
  --> src/app.bl:11:18
   |
11 |     io.println("{load()}")
   |                  ^^^^^^ `load` requires `! Store`
   |
   = help: user-declared effects have no root handler; wrap the call in `with <handler> { ... }` (§4.12)
```

The fix installs a handler:

```blink
fn main() {
    with memory_store() {
        io.println("{load()}")
    }
}
```

A partial handler adds its effect to the row at its `with` (§4.7.1, *The clause row*), so this check reports a partial handler that has no outer handler for its effect. An operation call that finds no handler at run time still panics (§4.7.1 *Completeness and auto-delegation*).

---

### 4.7 Effect Handlers

Effect handlers replace the implementation behind effect handles. They are the mechanism for dependency injection, testing, sandboxing, and capability attenuation.

For how handlers relate to calls into foreign code, see §4.5 *Proven and assumed rows*; §9.1 *The Effect Row* shows how a safe wrapper makes a foreign effect replaceable.

#### Basic handler syntax

```blink
with handler_expression {
    // code in this block uses the replaced implementation
}
```

A `handler E { ... }` expression captures bindings from its enclosing scope exactly as a closure does (§2.8). A captured `let mut` binding is a shared cell (§3.6 *Shared cells*): writes in a handler op are visible to the enclosing scope and to any closure that captured the same binding. This differs from `Scoped` block bodies (§4.7.2), which run in the caller's scope and capture nothing. The `std.testing` mock controllers (§8.10.3) depend on this rule.

#### Testing: mock handlers

The most common use case. Replace real effects with test doubles:

```blink
fn process_order(id: Int) -> Result[Receipt, OrderError] ! DB.Read, DB.Write, IO.Log {
    let order = db.query_one(t"SELECT * FROM orders WHERE id = {id}")?
    io.log("Processing order {id}")
    let receipt = Receipt { order_id: id, total: order.total }
    db.execute(t"INSERT INTO receipts ...")?
    Ok(receipt)
}

test "process_order creates receipt for valid order" {
    let fake_orders = [Order { id: 42, total: 99.99 }]
    let log_messages: List[Str] = []

    with mock_db(fake_orders), capture_log(log_messages) {
        let result = process_order(42)
        assert(result.is_ok())
        assert_eq(result.unwrap().total, 99.99)
    }

    assert_eq(log_messages.len(), 1)
    assert(log_messages.get(0).unwrap().contains("Processing order 42"))
}
```

The code under test calls `db.query_one(...)` and `io.log(...)` as normal. The handler intercepts these calls and routes them to the mock implementation. The function being tested does not know or care -- it interacts with the same handle interface either way.

#### Dependency injection: swapping backends

Handlers replace traditional DI containers:

```blink
fn run_with_postgres(config: DBConfig) ! DB, IO.Log {
    with postgres_handler(config) {
        start_server()  // all DB operations inside route to Postgres
    }
}

fn run_with_sqlite(path: Str) -> Result[(), DBError] ! DB, IO.Log {
    with db.connect(path)? {
        start_server()  // same code, SQLite backend
    }
    Ok(())
}

fn main() {
    let config = load_config()
    match config.db_backend {
        "postgres" => run_with_postgres(config.pg_config)
        "sqlite" => if run_with_sqlite(config.sqlite_path).is_err() {
            io.eprintln("cannot open {config.sqlite_path}")
        }
    }
}
```

No interfaces, no factory patterns, no service locators. The handler is the injection point. The code inside the `with` block is agnostic to the concrete implementation.

#### Sandboxing: restricting capabilities

Handlers can provide a restricted implementation that narrows what the inner code can do:

```blink
fn run_plugin(plugin: Plugin) ! Net.Connect, FS.Read, IO.Log {
    let allowed_hosts = ["api.example.com", "cdn.example.com"]

    with restricted_net(allowed_hosts), readonly_fs("/plugins/data/") {
        plugin.execute()
    }
}
```

Inside the `with` block, `net.get(url)` checks the URL against the allowlist and returns an error for disallowed hosts. `fs.read(path)` is scoped to `/plugins/data/` -- attempts to read outside that directory fail. The plugin code declares `! Net.Connect, FS.Read` and has no idea it is sandboxed.

#### Defining a handler

Handlers implement the operations for an effect:

```blink
fn mock_db(data: List[Row]) -> Handler[DB] {
    handler DB {
        fn read(query: Template[DB]) -> Result[List[Row], DBError] {
            // query.template = "SELECT ...", query.params = [...]
            Ok(data.filter(fn(row) { matches_query(row, query) }))
        }

        fn write(query: Template[DB]) -> Result[(), DBError] {
            // No-op for tests, or append to a log
            Ok(())
        }

        fn admin(query: Template[DB]) -> Result[(), DBError] {
            Err(DBError.PermissionDenied("admin operations disabled in mock"))
        }
    }
}
```

A handler must implement all operations for the effect it covers (or explicitly delegate unhandled operations to the outer handler). The compiler checks completeness -- you cannot create a `Handler[DB]` that forgets to implement `admin`.

#### Handler composition

Multiple handlers compose with `,`:

```blink
with handler_a, handler_b, handler_c {
    // handler_a covers its effects
    // handler_b covers different effects
    // handler_c covers yet others
    do_work()
}
```

Items nest from left to right (see *Disambiguation rules* below), so the rightmost item is the innermost one. If two handlers cover the same effect, the rightmost wins. This is deterministic and predictable.

#### Handlers are values

Handlers are first-class values. They can be stored in variables, passed as arguments, and returned from functions. The type of a handler can name the effects that its operation bodies perform outside the handler (see *The clause row* in §4.7.1):

```blink
fn make_test_env() -> (Handler[DB], Handler[IO]) {
    let db_handler = mock_db(test_fixtures())
    let io_handler = capture_log([])
    (db_handler, io_handler)
}

test "integration test with shared environment" {
    let (db_h, io_h) = make_test_env()
    with db_h, io_h {
        run_migration()
        verify_schema()
    }
}
```

#### Scoped resources: `with...as`

Effect handlers manage long-lived, framework-level resources — connection pools, capability providers, test doubles. But functions also acquire short-lived, individual resources: a file handle for one read, a lock held for one critical section, a temp file for one transformation.

The `with...as` construct handles this second tier. The file-handle examples below (`fs.open`, `fs.create`, and the `fs` handle ops that take a file, such as `fs.read_all`) are **planned post-v1 API**, shown to illustrate the scoped-resource mechanism — they are not part of the v1 `fs` surface, which is the four path operations in §4.4.5:

```blink
// Planned (post-v1): the file-handle API. Shown here to illustrate `with ... as`
// scoped resources; the v1 fs surface is the four path operations in §4.4.5.
fn copy_file(src_path: Str, dst_path: Str) -> Result[(), FsError] ! FS {
    with fs.open(src_path)? as src, fs.create(dst_path)? as dst {
        let data = fs.read_all(src)?
        fs.write_all(dst, data)?
    }
}
```

Both `src` and `dst` implement the `Closeable` trait. When the block exits — normally or via `?` — their `close()` methods run in LIFO order (dst first, then src).

#### Two-tier resource model

| Tier | Mechanism | Lifetime | Examples |
|------|-----------|----------|----------|
| Framework resources | `with handler { }` | Application/request scope | Connection pools, capability providers, test mocks |
| Individual resources | `with expr as name { }` | Block scope | File handles, locks, temp files, cursors |

The tiers compose naturally:

```blink
// The scoped-resource file handle (`fs.create ... as out`, `out.write`) is the
// planned post-v1 handle API; the two-tier `with` composition it illustrates is v1.
fn export_data(query: Str, path: Str) -> Result[(), AppError] ! DB.Read, FS {
    with fs.create(path)? as out {
        let rows = db.query(query)?
        for row in rows {
            out.write(row.to_csv())?
        }
    }
}

test "export_data writes CSV" {
    with mock_db(fixtures), temp_fs() {
        with fs.create("test_out.csv")? as f {
            export_data("SELECT *", "test_out.csv")?
        }
        let content = fs.read("test_out.csv")?
        assert(content.contains("Alice"))
    }
}
```

The outer `with mock_db(fixtures), temp_fs()` installs effect handlers. The inner `with fs.create(...)? as f` is a scoped resource, and `as` binds it to `f`. The compiler tells them apart by the type of the item, not by `as`.

#### Disambiguation rules

The type of a `with` item decides what the item does. A `with` item has one of two typing rules:

| Item type | Meaning |
|-----------|---------|
| `Handler[E]` or `Handler[E ! R]` | Install the handler for `E`, run the body, uninstall the handler. The enclosing code must hold `R` (§4.7.1, *The clause row*). |
| A scoped value: `T` where `T: Scoped`, which includes every `Closeable` type (§4.7.2) | Call `enter()`. If `T.Context` is `Handler[E]` with a concrete `E`, install the handler that `enter()` returned. Run the body. Uninstall that handler. Call `exit(ok)`. |

`arena` is a keyword item with its own typing rule (§5.2). A `handler E { ... }` expression has type `Handler[E]`, so it takes the first rule.

An item of any other type is a compile error (E0839). If the type is a `Result` or an `Option`, the help text says to add `?`.

`as` binds a name and does nothing else. `as` never changes what a `with` item does:

- For a `Handler[E]` item, `name` is the handler. It is the same first-class value (see *Handlers are values*). It is not a scoped value, so W0610, W0611 and E0601 do not apply to it.
- For a scoped value, `name` is the value that `enter()` returns (the `Context`). For a `Closeable` type, that is the value itself.
- Without `as`, a scoped value runs `enter()` and `exit(ok)` as before, and the compiler discards the `Context`. This is legal for every `Context`.

```blink
with mock_db(fixtures) {
    // Handler[DB]: installed
}

with mock_db(fixtures) as h {
    // The same install. h is the same handler value
}

with db.transaction() {
    // Scoped value: enter() and exit(ok) run. The Context is discarded
}

with db.transaction() as tx {
    // The same, and tx is the Context
}
```

The typing rule and evaluation order for a scoped value are in §4.7.2, *Scoped effect handlers*.

**Comma-separated items nest from left to right.** `with a, b { body }` means `with a { with b { body } }`. The compiler evaluates and type-checks item *i* after items *0..i-1* are entered and their handlers installed, so a later item can use an effect that an earlier item installs. Teardown is LIFO. If item *i* fails through `?`, the `?` fires before item *i* is entered, and the normal unwind of items *0..i-1* runs their `exit(false)` or `close()` (§4.7.2, *Catchable unwind*; §5.5, *Multiple resources*).

The rightmost item is the innermost. In `with a, b { body }`, `b` is inside `a`: an operation of `b` that forwards reaches `a` first (§4.7.1, *The clause row*), and `b` wins over `a` for an effect that both handle. The clause row of each item is checked where the item is installed. The row `R_a` of `a` is checked against the row of the enclosing code. The row `R_b` of `b` is checked against the row of the enclosing code plus the effect that `a` handles.

All forms can appear in the same comma-separated `with`:

```blink
with mock_db(fixtures), fs.open("x.txt")? as f {
    // mock_db provides DB handler, f is a Closeable file handle
}

with mock_db(fixtures), db.transaction() {
    // mock_db provides DB handler, transaction is a scoped value
}

with db.connect("app.db")?, db.transaction() {
    // db.connect installs the DB handler; db.transaction() uses it
}
```

#### Interaction with structured concurrency

Scoped resources respect structured concurrency boundaries. A `Closeable` bound in a `with...as` cannot be sent to a spawned task (it would escape the scope):

```blink
fn bad_example() ! FS, Async {
    with fs.open("data.txt")? as file {
        async.spawn(fn() {
            fs.read_all(file)  // COMPILE ERROR E0601: closeable `file` escapes scope
        })
    }
}
```

If concurrent tasks need the resource, open it outside or pass the data:

```blink
fn good_example() ! FS, Async {
    let data = with fs.open("data.txt")? as file {
        fs.read_all(file)?
    }
    async.scope {
        async.spawn(fn() { process(data) })
    }
}
```

---

### 4.7.1 Handler Type System

`Handler[E]` is a compiler-known generic type parameterized by an effect. It is the type of values produced by `handler E { ... }` expressions. At the source level, `Handler[E]` is a single type constructor. A handler type is `Handler[E]` or `Handler[E ! R]`, where the optional `! R` is the clause row (see *The clause row* below).

#### Type identity

`Handler[E]` is parameterized by a concrete effect. `Handler[DB]`, `Handler[IO]`, and `Handler[Net.Connect]` are distinct types. `Handler[DB]` and `Handler[DB ! IO.Log]` also differ, because the clause row is part of the type. The type parameter must be a declared effect — `Handler[Int]` is a compile error:

```
error[InvalidHandlerTypeParam]: invalid handler type parameter
 --> app.bl:3:10
  |
3 | let h: Handler[Int] = ...
  |                ^^^ `Int` is not an effect
  |
  = note: Handler[E] requires E to be a declared effect
```

#### The clause row

A handler type is `Handler[E]` or `Handler[E ! R]`. `R` is the **clause row**: the effects that the operation bodies of the handler perform outside the handler. `Handler[E]` means that `R` is empty. `R` is a concrete effect row, written as on a function type (§4.15.1). In a parameter type it can also be `_` (§4.15.2). The compiler infers `R` for a `handler E { ... }` expression.

`R` is part of the type, in the way the row of a function type is part of that type. A value of type `Handler[E ! R1]` fits where `Handler[E ! R2]` is expected only if every effect of `R1` is in `R2`. This is the same rule as for function types (§4.15.1). `Handler[DB]` fits where `Handler[DB ! IO.Log]` is expected. The reverse is a type error. Projection (*Effect projection* below) keeps `R`.

**What `R` holds.** The body of an operation does not get `E` added to its row. Each of these performs `E` outside the handler, and `E` goes in `R`:

- `default.op(args)` in an operation body.
- A call through the handle of `E` in an operation body. A handler does not handle its own operations (below), so such a call reaches the same place as `default.op(args)`.
- An omitted primitive operation. It forwards as if `default.op(args)` were written (below).

An omitted derived operation adds nothing, because its body runs at the call site. A call that an operation body makes through another effect, such as `io.log`, also goes in `R`. It reaches the handlers in force where the operation runs. Handlers of other effects stay in force.

**Where a forward goes.** A forward is a `default.op(args)` call, a call through the handle of `E` in an operation body, or an omitted primitive operation. A forward reaches the handler in force for `E` at the `with` that installed this handler. A handler value that leaves the block where it was built forwards to the handler in force where it is installed, not where it was built.

**Charge at the `with`.** Let `h` have the type `Handler[E ! R]`. Then `with h { body }` needs `R` in the row of the enclosing code. That row is the row of the fn plus the effects that enclosing `with` items install. A missing effect is `UndeclaredEffect` (E0500) at the `with` item. A note points at the call in the operation body that performs the effect, such as the `default.op` call, or at the handler head for an omitted primitive operation. A function with no `!` in its signature therefore cannot reach a real effect through a handler (§4.1):

```blink
pub fn needs_print() ! IO.Print {
    io.println("x")
}

pub fn deleg() {
    let h = handler IO.Print {
        fn print(msg: Str) { default.print(msg) }
        fn print_no_nl(_msg: Str) { }
    }
    with h {            // error: `h` performs `IO.Print` outside the handler
        needs_print()
    }
}
```

```
error[UndeclaredEffect]: undeclared effect
  --> deleg.bl:10:10
   |
10 |     with h {
   |          ^ handler `h` performs `IO.Print` outside the handler
   |
  ::: deleg.bl:7:30
   |
 7 |         fn print(msg: Str) { default.print(msg) }
   |                              ------- this call forwards to the enclosing handler
   |
   = note: function `deleg` declares no effects
   = fix: add `IO.Print` to the signature:
   |
 5 | pub fn deleg() ! IO.Print {
   |                 +++++++++
```

When the declared return type of a factory is narrower than the row that the handler expression has, the type mismatch carries a fix. The fix writes the inferred row in the declared type:

```
error[TypeError]: mismatched types
 --> db.bl:1:30
  |
1 | fn logging_db(label: Str) -> Handler[DB] {
  |                              ^^^^^^^^^^^ expected `Handler[DB]`, found `Handler[DB ! DB, IO.Log]`
  |
  = note: the operations of this handler perform `DB, IO.Log` outside the handler
  = fix: write the row in the declared type: `Handler[DB ! DB, IO.Log]`
```

#### First-class values

Handlers are full first-class values. They can be stored in variables, struct fields, collections, closures, passed as arguments, and returned from functions:

```blink
// Store in a variable
let h: Handler[DB] = mock_db(test_data)

// Store in struct fields
type TestEnv {
    db: Handler[DB]
    io: Handler[IO]
}

// Store in collections
let handlers: List[Handler[DB]] = [mock_db(data1), mock_db(data2)]

// Return from functions
fn make_handler(config: Config) -> Handler[DB] {
    handler DB {
        fn read(query: Template[DB]) -> Result[List[Row], DBError] {
            run_query(config.connection, query)
        }
        fn write(query: Template[DB]) -> Result[(), DBError] {
            run_mutation(config.connection, query)
        }
        fn admin(query: Template[DB]) -> Result[(), DBError] {
            if config.allow_admin {
                run_admin(config.connection, query)
            } else {
                Err(DBError.PermissionDenied("admin disabled"))
            }
        }
    }
}

// Pass as function argument
fn run_with(h: Handler[DB ! _]) ! _ {
    with h {
        do_work()   // do_work has the row `! DB`; `with h` discharges DB
    }
}
```

Here `run_with` takes any handler for `DB`. The clause row of the argument becomes part of the row of the call (§4.15.2, *Handler parameters*).

A handler value can be stored beyond the scope that created it. It never becomes a dangling reference.

#### Effect projection

A `Handler[E]` where `E` is a parent effect can be used where a `Handler[E.Sub]` is expected. The compiler converts it implicitly to a handler for the sub-effect:

```blink
fn read_only_test(h: Handler[DB.Read]) ! DB.Read {
    with h {
        let rows = db.query(t"SELECT * FROM users")?
    }
}

let full: Handler[DB] = mock_db(data)
read_only_test(full)  // OK: DB converts to DB.Read
```

This is not subtyping. The conversion is implicit at the call site. The resulting handler handles only the operations of `E.Sub`.

Projection only works in one direction. A `Handler[DB.Read]` cannot be used where `Handler[DB]` is expected — the handler is missing `write` and `admin` operations:

```
error[InsufficientHandlerCoverage]: insufficient handler coverage
 --> test.bl:5:15
  |
5 | run_full(read_handler)
  |          ^^^^^^^^^^^^ expected `Handler[DB]`, found `Handler[DB.Read]`
  |
  = note: `Handler[DB]` requires operations: read, write, admin
  = note: `Handler[DB.Read]` only provides: read
```

#### Completeness and auto-delegation

Handlers may be **partial**: a handler can omit operations of its effect. An operation that has no body in the effect declaration is a **primitive operation**. An operation that has a body in the effect declaration is a **derived operation** (the `Net.Connect` verbs in §4.4.1 are derived operations over the primitive `request`). An omitted primitive operation forwards to the enclosing handler as if `default.op(args)` were written. The forward performs the effect outside the handler, so the effect is in the clause row (*The clause row* above). A handler that forwards, or whose operation bodies call other effects, has that row in its type:

```blink
fn logging_db(label: Str) -> Handler[DB ! DB, IO.Log] {
    handler DB {
        fn read(query: Template[DB]) -> Result[List[Row], DBError] {
            io.log("{label}: read {query}")
            default.read(query)  // explicit delegation
        }
        // write and admin omitted — auto-delegate to enclosing handler
    }
}
```

The compiler desugars the above as if `write` and `admin` were defined with `default.write(query)` and `default.admin(query)` respectively. Explicit `default.op(args)` remains available for custom delegation logic (e.g., logging before forwarding, as shown for `read` above).

**Derived operations.** A call to an operation goes to the innermost handler of its effect. If that handler implements the operation, its body answers. If the handler omits a derived operation, the body from the effect declaration runs at the call site, with the same handlers in force. The calls that this body makes through the effect's handle therefore reach the same innermost handler. The body does not run as an operation of that handler, so the rule that a handler does not handle its own operations (below) does not apply to it. Only an omitted primitive operation forwards to the enclosing handler.

```blink
fn mock_net(responses: Map[Str, Str]) -> Handler[Net.Connect] {
    handler Net.Connect {
        fn request(req: Request) -> Result[Response, NetError] {
            match responses.get(req.url) {
                Some(body) => Ok(Response { status: 200, body: body, headers: Map.new() })
                None => Err(NetError.ConnectionRefused("mock: no response for {req.url}"))
            }
        }
        // get, post, ... omitted: their bodies run and call this handler's request
    }
}

fn logging_get() -> Handler[Net.Connect ! Net.Connect, IO.Log] {
    handler Net.Connect {
        fn get(url: Str) -> Result[Response, NetError] {
            io.log("GET {url}")
            default.get(url)
        }
        // request omitted: forwards to the enclosing handler
    }
}

fn main() ! Net, IO {
    with logging_get() {
        with mock_net(Map.new()) {
            net.get("https://example.com")   // mock_net answers; logging_get does not run
        }
    }
}
```

In `main`, the innermost `Net.Connect` handler is `mock_net`. It omits `get`, so the `get` body from the effect declaration runs, and its `net.request(...)` reaches `mock_net`. The program does not search the outer handlers for a `get` clause, so `logging_get` does not run. The innermost handler alone decides what a derived operation does.

`default` is a contextual name, not a keyword. In the body of a handler operation, `default.op(args)` delegates to the handler in force for the effect at the `with` that installed this handler (see *The clause row*). Elsewhere, including in a closure written inside an operation body, an unshadowed use of `default` is a compile error (E0544). A local binding named `default` shadows it.

```blink
effect Audit {
    effect Log {
        fn record(msg: Str)
    }
}

fn log_it() ! Audit.Log {
    default.record("x")   // error: not in a handler operation
}
```

```
error[DefaultOutsideHandlerOp]: `default` is only valid inside a handler operation body
 --> audit.bl:8:5
  |
8 |     default.record("x")   // error: not in a handler operation
  |     ^^^^^^^
  |
  = help: `default` forwards to the handler in force for the effect at the `with` that installed the enclosing operation's handler
  = help: to call the effect from ordinary code, use its handle: `audit.record("x")`
```

The second help line shows the call through the effect's handle (§4.4), built from the handle and the operation of the call. When the compiler cannot build it, the line says: "Outside an operation, call the effect operation directly through its handle, or move this call into a handler operation." There is no machine-applicable fix: a call through the handle goes to the innermost handler, so it does not do the same thing as a delegation.

A closure body is not a handler operation body, even when the closure is written inside one. `default` in such a closure is E0544, whether or not the closure outlives the operation. The message names the closure:

```blink
with handler Audit {
    fn record(msg: Str) {
        msg.split("\n").for_each(fn(l) { default.record(l) })   // error: inside a closure
    }
} {
    audit.record("a\nb")
}
```

```
error[DefaultOutsideHandlerOp]: `default` is not valid inside a closure, even in a handler operation
 --> audit.bl:3:42
  |
3 |         msg.split("\n").for_each(fn(l) { default.record(l) })   // error: inside a closure
  |                                          ^^^^^^^
  |
  = help: a closure body is not an operation body; call `default.record` in the operation body itself
  = help: a closure that runs while the operation runs can call `audit.record(l)`, which reaches the same handler
```

The second help line follows from the next rule. There is no machine-applicable fix, because a closure that runs after the operation has returned does not reach the same handler.

**A handler does not handle its own operations.** While an operation body of a handler runs, that handler is not in force for the effect it handles. Every call through the effect's handle made while the body runs reaches the handler in force for the effect at the `with` that installed this operation's handler. This holds whether the call is written in the body, in a closure that the body calls, or in a function that the body calls. Handlers of other effects stay in force. In an operation body, `audit.record(m)` and `default.record(m)` therefore do the same thing, and the closure above can be written as:

```blink
with handler Audit {
    fn record(msg: Str) {
        msg.split("\n").for_each(fn(l) { audit.record(l) })   // reaches the outer handler
    }
} {
    audit.record("a\nb")
}
```

When the operation returns or panics, the handler is in force again. A closure that runs after the operation has returned performs its effects with the handlers in force where it is called (§4.15.4). If no outer handler implements the operation, the call panics, as below.

Auto-delegation means a handler that only overrides `read` is still a complete handler for `DB`. Its type is `Handler[DB ! DB]`, because the omitted `write` and `admin` forward. The type system does not track which operations a handler omits. It tracks only the clause row. At runtime, an omitted primitive operation goes to the nearest enclosing handler that implements it.

When no enclosing handler implements the operation, the operation panics. This happens when a partial handler omits it and no outer handler implements it, or when a handler calls `default.op(args)` with no outer handler. For a user effect, the compile-time check at the roots (§4.6 *Unhandled user effects*, §2.20) sees the forward, because the clause row of the partial handler holds the effect. The `with` of such a handler is an error at a root that has no outer handler for the effect:

```blink
effect Cache {
    fn get(key: Str) -> Option[Int]
    fn put(key: Str, value: Int)
}

fn read_only_cache() -> Handler[Cache ! Cache] {
    handler Cache {
        fn get(key: Str) -> Option[Int] { None }
        // put omitted -- auto-delegates, and no outer handler implements it
    }
}

fn main() {
    with read_only_cache() {   // error E0539: `Cache` is not discharged outside this handler
        cache.put("hits", 1)
    }
}
```

The run-time rule stays: a call that reaches no handler panics.

The operation never returns and never produces a default value, whatever its return type, `-> Never` included. The panic message contains the operation as a program calls it, `<handle>.<op>` (for example `cache.put`; handles are described in §4.4). The rest of the message and the source location are not specified, so a test matches on the operation: `assert_panics(matching: "cache.put") { ... }` (§2.20).

#### Whole-handler effects: `@handle_all`

For most effects, a partial handler is correct code: `logging_db` above changes `read` and keeps the enclosing handler for the rest. For some effects, all operations are views of one resource. The three `Rand` operations read one random stream, the `Time` operations read one clock, and the `IO.Read` operations read one input stream. A handler that answers some of these operations and forwards the rest mixes two streams or two clocks. Only the author of the effect knows which kind of effect it is, so the author marks it:

```blink
@handle_all
effect Dice {
    fn roll(sides: Int) -> Int
    fn coin() -> Bool
}
```

`@handle_all` attaches to an effect declaration. It covers the sub-effects of the effect too. It can also mark a nested sub-effect, and then it covers only that sub-effect. The stdlib marks `Rand` (§4.4.7), `Time` (§4.3) and `IO.Read` (§4.4.9), and no other effect.

When a handler expression for a marked effect omits a primitive operation of the effect that it handles, the compiler gives the warning `PartialHandler` (W0545). A derived operation never counts, because the effect declaration supplies its body. A handler for a sub-effect counts only the operations of that sub-effect. A handler for a parent effect counts the operations of a marked sub-effect only if it implements one or more of them: a `handler IO { ... }` that implements only `print` gets no warning, and one that implements `read_line` but not `read_bytes` does. The warning is about the handler expression, so it fires in all code, not only in tests:

```blink
fn always_high() -> Handler[Rand ! Rand] {
    handler Rand {
        fn int(lo: Int, hi: Int) -> Int { hi }
    }
}
```

```
warning[PartialHandler]: handler for `Rand` does not implement `float`, `bytes`
 --> dice.bl:2:5
  |
2 |     handler Rand {
  |     ^^^^^^^^^^^^ `Rand` is marked `@handle_all`
  |
  = note: omitted operations go to the enclosing handler, which reads a different random stream; in a test that is the runner's seeded stream (§8.10.4), not this handler's
  = note: `default.float()` answers from the outer handler; if this handler answers `int` from its own state, answer `float` from the same state
  = help: implement them, or forward on purpose: `fn float() -> Float { default.float() }`
```

The second note is the same for every marked effect. The compiler fills in one omitted operation and one operation that the handler implements: "`default.<op>()` answers from the outer handler; if this handler answers `<other op>` from its own state, answer `<op>` from the same state." When the omitted operation returns an opaque type (§2.12.2), the help also names the `pub` type-scoped functions that build that type. The compiler takes these names from the return type, so no list per effect exists. They are the functions that the `PrivateItemAccess` help (E1003) names for that type. An operation that returns a type that is not opaque, such as `Int` or `Bytes`, adds no such line.

`Time` is the case that needs this line. A `Time` handler that answers `read` and omits `monotonic`:

```blink
fn fixed_clock() -> Handler[Time] {
    handler Time {
        fn read() -> Instant { Instant.from_epoch_secs(0) }
        fn sleep(d: Duration) { }
    }
}
```

```
warning[PartialHandler]: handler for `Time` does not implement `monotonic`
 --> clock.bl:2:5
  |
2 |     handler Time {
  |     ^^^^^^^^^^^^ `Time` is marked `@handle_all`
  |
  = note: `default.monotonic()` answers from the outer handler; if this handler answers `read` from its own state, answer `monotonic` from the same state
  = help: build the reading with `Monotonic.from_offset(d)` (§3.2.3), or forward on purpose: `fn monotonic() -> Monotonic { default.monotonic() }`
```

The forward fix is wrong for `Time` in a test. A test block has no outer `Time` handler (§2.20), so `default.monotonic()` finds no handler and panics at run time (*Completeness and auto-delegation*). The fix itself does not change. It stays `default.op(args)`, and the help only says which way to answer.

To silence the warning, write the operation. Any body counts: `default.op(args)` to forward on purpose, a constant, or a panic. An explicit `default.op(args)` gives the same program as the omitted operation. `@allow(PartialHandler)` on a function and the `[lints]` table also work (§4.16.8).

The diagnostic carries a machine-applicable fix. The fix adds each missing operation with the exact signature from the effect declaration and the body `default.op(args)`. It uses the operation signature (`fn int(lo: Int, hi: Int) -> Int`), not the stdlib wrapper (`rand.int(r)`). For the handler above, the fix adds:

```blink
        fn float() -> Float { default.float() }
        fn bytes(n: Int) -> Bytes { default.bytes(n) }
```

#### Generic handler parameters

In v1, handler type parameters must be concrete effects: `Handler[DB]`, `Handler[IO]`, `Handler[Net.Connect]`. Effect-kinded generic parameters (e.g., `fn foo[E: Effect](h: Handler[E])`) are deferred to v2, alongside named effect variables.

---

### 4.7.2 Scoped Trait — Scoped Blocks

Records in `decisions/` and DECISIONS.md cite this section as §4.6.3, its earlier number.

The `Scoped` trait provides a general mechanism for types that need enter/exit semantics around a block of code. It lets a type accept a block without new syntax for each API.

```blink
trait Scoped {
    type Context

    fn enter(self) -> Self.Context
    fn exit(self, ok: Bool)
}
```

**`enter()`** is called before the block body executes. Its return value is bound via `as` (or discarded if `as` is absent). If `Context` is `Handler[E]`, the return value is also installed as the handler for `E` (see *Scoped effect handlers* below). **`exit(ok)`** is called after the block body completes — `ok` is `true` for normal completion, `false` for any **catchable unwind** (see below).

#### Catchable unwind

`exit(self, false)` runs on every exit path that terminates at a runtime-defined catch boundary. The set is closed and exhaustively defined:

| Path | `ok` value |
|------|-----------|
| Normal block completion | `true` |
| `?` propagation | `false` |
| `return` from enclosing function | `false` |
| Assertion failure (`assert`, `assert_eq`, `assert_ne`, `assert_matches`) | `false` |
| `skip()` in a test block | `false` |
| Expected panic caught by `assert_panics` (the *armed* boundary, §2.20) | `false` |
| Uncaught panic (`panic()`, arithmetic overflow, OOB index) outside a runtime catch frame, or a fatal runtime error | *bypasses `exit()` entirely* |

A **fatal runtime error** is a fault the runtime cannot recover from: OOM, stack overflow, or foreign code that ends the process. The runtime ends the process at once. Nothing unwinds, and no `exit()` or `close()` runs.

The runtime catch frames are the test runner's per-test boundary, the `?`/`return` desugar, and — within a test only — the boundary armed by an `assert_panics` block (§2.20). The set of runtime catch boundaries is **exhaustively defined by this spec and cannot be extended by user code**. Introducing user-level panic recovery (e.g., `recover`, `catch_panic`) would require a separate spec amendment that re-evaluates `exit()`/`close()` semantics under the new boundary set.

**Amendment — `assert_panics` extends the catchable-unwind set (compiler-managed, not user-extensible).** Be precise about what changed: outside a test, a real `panic()` does *not* unwind to any in-process catch frame — it terminates the process and bypasses `exit()`/`close()` (the last row above). `assert_panics` (§2.20) genuinely *adds* a new catch boundary: within the dynamic extent of its block, a panic is caught and converted to a test pass/fail rather than terminating the process. This boundary is **compiler-managed and test-only** — only an `assert_panics` block arms it, is rejected outside a test (E0833), is not nestable (E0834), and exposes **no user-nameable symbol** (there is no `recover`/`catch_panic` a user can call). It therefore does not extend the set of catch boundaries reachable by *user code*; the user-extensible set remains empty, and the fence above holds.

The `panic: Never` typing claim (§2.20, *`panic()` Function*) is preserved: the `assert_panics` construct has type `()`, its body is a recognized block (not a reified `fn` value), and the `matching:` argument binds nothing into user scope — so no user expression acquires a type that witnesses the panic. As with `Scoped.exit(false)` itself, the cleanup that runs during an armed-panic unwind cannot receive the panic value, cannot inspect any discriminant beyond `ok: Bool`, cannot suppress the unwind, and cannot rescue the test.

The cleanup asymmetry is intentional and must be read carefully: an **armed** (expected) panic runs in-scope `exit(false)`/`close()`; an **unarmed/uncaught** panic still terminates and bypasses them. A resource opened inside an `assert_panics` body is therefore released on the expected panic, whereas the same panic escaping a plain test body is not — armed test boundaries are controlled, like `skip()`, and uncaught divergence is not.

**Concurrency.** The armed state is **per-test (thread-local)**. An `assert_panics` in one test or task must never catch a panic raised on a different spawned task; arming is scoped to the calling frame's thread. This is normative, not implementation-defined.

**Cleanup that itself panics during an armed unwind.** If an in-scope `exit(false)`/`close()` *itself* panics while unwinding an armed expected panic, the original body panic remains "the expected panic" for `matching:` (E0832) purposes and stays load-bearing as the test's result and unwind cause; the cleanup fault surfaces as a **secondary `warning`-severity `E0824`** on the **same trace frame** (the test runner records it in the per-test record's `cleanup_warnings[]`, additive to the original status — see E0824, §5.5), not as a separate failing record. The panicking cleanup body's own control flow is abandoned at the panic point; remaining LIFO handlers still run (`continue-drain`, per line below).

This rule is uniform across `Scoped.exit()` and `Closeable.close()` (§5.5) — every catchable structured unwind runs registered cleanup; uncaught divergence does not.

#### Block semantics

`Scoped` blocks have block semantics, not closure semantics:

- `?` propagates errors to the **enclosing function's** `Result` return type
- `return` exits the **enclosing function**, not just the block
- Variables from the enclosing scope are directly accessible (no capture)

This is the same behavior as `async.scope { }` — the block runs in the caller's context, not in a separate closure scope.

#### Usage

```blink
// With binding — Context is meaningful
with db.transaction() as tx {
    db.execute(t"INSERT INTO orders ...")?
}

// Without binding — the Context is discarded
with metrics.timer("request_duration") {
    handle_request()?
}

// As an expression
let result = with db.transaction() {
    db.query_one(t"SELECT count(*) FROM users")?
}
```

#### Implementing Scoped

Any type can implement `Scoped`. A scoped value gets all its state when it is built: `self` is a by-value copy (§3.6), so `enter()` cannot pass new state to `exit()`. Put the build in a function, and call that function in the `with` item. Step 1 of the *Order* below evaluates the item right before `enter()`, so each `with` gets a new value:

```blink
pub type Timer {
    label: Str
    start: Instant
}

pub fn timer(label: Str) -> Timer ! Time.Read {
    Timer { label: label, start: time.read() }
}

impl Scoped for Timer {
    type Context = ()

    fn enter(self) -> () {}

    fn exit(self, ok: Bool) ! Time.Read, IO.Log {
        let elapsed = self.start.elapsed()
        io.log("{self.label}: {elapsed} (ok={ok})")
    }
}

// Usage
with timer("db_query") {
    db.query(t"SELECT * FROM large_table")?
}
```

Nested items are correct for the same reason. In `with timer("a") { with timer("b") { } }`, each value is built right before its own `enter()`, and the two `exit()` calls run in LIFO order.

A value that is stored and then goes into two `with` items runs `exit()` twice on one state. The scope lints (§5.5) warn about this: W0610 for a value that reaches no `with`, and W0611 for a value that reaches more than one.

`enter()` cannot write to `self`. An assignment such as `self.start = time.read()` is a parameter assignment, which is a compile error (§3.6). Inside `enter()` of a `Scoped` impl, that error's help text names the fix: set the field when the value is built, and build the value in the `with` item.

#### Closeable types are scoped values

A type that implements `Closeable` (§3.6) also implements `Scoped`, with these members:

- `type Context = Self`
- `enter(self)` returns `self`
- `exit(self, ok)` calls `self.close()`

The effects of `close` are the effects of `exit`. This impl counts for trait bounds: `T: Scoped` accepts a `Closeable` type. A `with` item of a `Closeable` type therefore follows the scoped-value rule of §4.7, and `as` binds the value itself.

A type that writes both `impl Closeable` and `impl Scoped` has two overlapping impls of `Scoped`. This is the ordinary overlapping-impl error. Its help text says "`Closeable` already provides `Scoped` for `T`".

`Handler[E]` has its own rule (§4.7). It does not implement `Scoped`, and it is not a scoped value. W0610, W0611 and E0601 do not apply to a `Handler[E]` item or to the name that `as` binds for it, and a program can store, pass and return a handler. This is different from a scoped effect handler: there the `Handler[E]` is the `Context` of a scoped value, and its binding follows *Interaction with async* below.

#### Scoped effect handlers

A `Scoped` type whose `Context` is `Handler[E]` is a **scoped effect handler**. The `with` block installs the handler that `enter()` returns, for the block body only. This joins an effect handler and a cleanup in one `with` item. In this example, `sqlite_open` returns `Result[Sqlite3, DBError]`, with `Err(ConnectionError(..))` when the open fails:

```blink
pub type Connection {
    handle: Sqlite3
}

impl Scoped for Connection {
    type Context = Handler[DB]

    fn enter(self) -> Handler[DB] {
        sqlite_handler(self.handle)
    }

    fn exit(self, ok: Bool) {
        sqlite_close(self.handle)
    }
}

pub fn connect(path: Str) -> Result[Connection, DBError] {
    let handle = sqlite_open(path)?
    Ok(Connection { handle: handle })
}

// Usage
with db.connect(":memory:")? {
    db.exec(t"CREATE TABLE users (name TEXT)")?
}
```

**Order.** For `with expr { body }`:

1. Evaluate `expr`
2. Call `enter()`
3. Install the returned `Handler[E]`
4. Run `body`
5. Uninstall the handler
6. Call `exit(ok)`

Steps 5 and 6 run on every catchable unwind, as for every scoped value. `exit()` runs after the uninstall, with the outer handlers in place. A `db.*` call inside `exit()` therefore goes to the outer `DB` handler, not to the one this item installed. Use `self` in `exit()`.

**Typing rule.** The item discharges `E` from the effect row of the body. `enter()` and `exit()` are checked against the outer effect row. When `Context` is `Handler[E ! R]`, the outer row also holds `R` (§4.7.1, *The clause row*):

```
Γ ⊢ e : T    T : Scoped    T.Context ≡ Handler[E ! R]
Γ ⊢ body : U ! ρ ∪ {E}
───────────────────────────────────────────────
Γ ⊢ with e { body } : U ! ρ ∪ R ∪ eff(enter) ∪ eff(exit)
```

The rule applies only when `T.Context` normalizes to `Handler[E]` with a concrete `E` at the `with` site. In generic code such as `fn run[T: Scoped](t: T) { with t { } }`, `Context` is abstract: the item installs no handler and discharges no effect. `enter()` and `exit()` still run, and the compiler discards the `Context` or binds it to the `as` name. There are no effect-kinded generics in v1 (§4.7.1), so `E` is always concrete where the rule applies.

**Binding.** `with expr as name { }` installs the handler and binds `name` to the same `Handler[E]` value. `name` follows the scoping rules in *Interaction with async* below.

**Acquire before the block.** `self` is passed by value, so `enter()` cannot hand new state to `exit()`. A scoped effect handler therefore holds its resource from construction, like a `Closeable`. Build it in the `with` item, as `connect` does above. Entering the same value in two `with` blocks runs `exit()` twice; W0611 (§5.5) warns about it.

A second `exit()` on a value whose resource is already released should do nothing, or should fail with a defined error. The stdlib's native handles do this: after `close`, a call on the handle returns an error such as `Err(ConnectionError("connection is closed"))`, not a use-after-free. This is guidance for user impls, not a rule the compiler checks. `std.testing`'s `Cleanup` runs its action on each `exit()`, so a second entry runs the action a second time.

A failed acquisition uses `?` on the item: `with db.connect(p)? { }`. The `?` fires before the scope is entered, so a failed open needs no cleanup.

#### `exit()` constraints

`exit()` is a finalizer, not a control flow mechanism. It **cannot**:

- **Inspect or suppress the unwind value** — `exit(self, ok: Bool)` receives only the success bit; it cannot read the panic message, the propagated error, or the `skip()` reason
- **Retry the block** — no mechanism to re-enter the block body
- **Transform the block's result** — `exit()` returns `()`, not a modified value
- **Replace errors** — if `exit()` itself panics on a catchable-unwind path, the original panic is preserved as the unwind cause; the test runner reports the original failure as the test's result, not the cleanup panic. The cleanup panic surfaces as a secondary `warning`-severity `E0824` (`CleanupPanickedDuringUnwind`) on the same trace frame, so the author can see the cleanup bug without losing the primary cause. On a stacked `with...as` chain, remaining handlers in the LIFO stack still run — the ordering matches the multi-cleanup test registrar decision's Q2 ruling (`continue-drain`, 6-0): short-circuiting would leak resources held by deeper-stacked handlers
- **Catch uncaught panics** — process-terminating panics bypass `exit()` entirely

Because `exit(false)` cannot observe *which* path triggered the unwind, handler authors must design `exit` to be safe under every catchable-unwind path. A handler that should commit on success and roll back on any failure pattern-matches on `ok`; a handler that always releases (timer, lock) ignores `ok`.

#### Interaction with async

`Scoped` bindings follow the same scoping rules as `Closeable` bindings (E0601, E0602). This includes the `Handler[E]` that `as` binds for a scoped effect handler: that handler uses a resource that `exit()` releases. A `Scoped` binding cannot be sent to a spawned task:

```blink
fn bad_example() ! DB, Async {
    with db.transaction() as tx {
        async.spawn(fn() {
            // COMPILE ERROR: `tx` escapes Scoped scope
            use_tx(tx)
        })
    }
}
```

#### Relationship to existing scoped blocks

| Block form | Mechanism | Migration status |
|-----------|-----------|-----------------|
| `db.transaction { }` | `Scoped` | Migrated — uses `with db.transaction() { }` |
| `async.scope { }` | Special syntax | v1: remains special syntax. v2: migrate to `Scoped` |

`async.scope` is not a `Scoped` type in v1, because its structured concurrency semantics (task cancellation, panic propagation, implicit join at scope exit) need more than `enter()/exit()` provides. Once `Scoped` proves itself on simpler use cases, `async.scope` migration will be evaluated for v2.

**Panel vote: 5-0 (runoff).** See [decisions/scoped-block-mechanism.md](../decisions/scoped-block-mechanism.md).

---

### 4.8 Module Capability Budgets

Modules can declare a hard ceiling on the effects any function inside them may use:

```blink
@capabilities(DB.Read, DB.Write)
module inventory

fn check_stock(item_id: Int) -> Result[Int, DBError] ! DB.Read {
    db.query_one(t"SELECT quantity FROM inventory WHERE id = {item_id}")?
}

fn update_stock(item_id: Int, delta: Int) -> Result[(), DBError] ! DB.Write {
    db.exec(t"UPDATE inventory SET quantity = quantity + {delta} WHERE id = {item_id}")?
}

fn drop_table() -> Result[(), DBError] ! DB.Write {
    db.exec(t"DROP TABLE inventory")?
    // This works if the module's capability budget includes DB.Write
}
```

```
error[CapabilityBudgetExceeded]: capability budget exceeded
 --> inventory.bl:12:5
  |
12|     db.exec(t"DROP TABLE inventory")
  |     ^^^^^^^^ requires `DB.Write`
  |
  = note: module `inventory` declares capabilities `DB.Read`
  = note: `DB.Write` is not within the module's capability budget
```

**Why module budgets:**

Module budgets are a defense against both mistakes and malice. A module responsible for inventory reads should never perform network calls, spawn processes, or mutate the database. The budget makes this constraint explicit and compiler-enforced. When an AI generates code in this module, the compiler immediately rejects anything that exceeds the budget -- no human review needed to catch a misplaced `db.exec(...)` call in a read-only module.

Module budgets are also the **audit surface** for security review. Instead of reviewing every function in a module, a reviewer checks the `@capabilities` declaration. If the budget is `DB.Read, DB.Write`, the reviewer knows -- with compiler-level certainty -- that nothing in this module touches the network, filesystem, process table, or database schema.

---

### 4.9 Package Capability Declarations

Every published package declares its maximum capabilities in its manifest file:

```toml
# blink.toml
[package]
name = "std/http-client"
version = "2.1.0"

[capabilities]
required = ["Net.Connect", "Net.DNS"]
optional = ["IO.Log"]  # only used if caller provides logging handler
```

Capabilities flow through the dependency graph and are recorded in the lockfile:

```toml
# blink.lock (auto-generated, checked into version control)

[[package]]
name = "std/http-client"
version = "2.1.0"
hash = "sha256:abc123..."
capabilities = ["Net.Connect", "Net.DNS"]

[[package]]
name = "std/json-parser"
version = "1.0.3"
hash = "sha256:def456..."
capabilities = []  # pure package -- no effects

[[package]]
name = "std/orm-toolkit"
version = "3.4.0"
hash = "sha256:789ghi..."
capabilities = ["DB.Read", "DB.Write"]
```

**Capability escalation triggers review:**

When a package version bump introduces new capabilities, the lockfile diff shows it:

```diff
 [[package]]
 name = "std/http-client"
-version = "2.1.0"
+version = "2.2.0"
-capabilities = ["Net.Connect", "Net.DNS"]
+capabilities = ["Net.Connect", "Net.DNS", "FS.Write"]
```

`blink update` refuses to auto-accept capability escalations:

```
warning: capability escalation detected

  std/http-client 2.1.0 -> 2.2.0
    + FS.Write (NEW)

  This package previously had no filesystem access.
  Run `blink update --accept-escalation std/http-client` to approve.
```

This is the supply-chain security story. A JSON parser declaring `capabilities = []` that suddenly requests `Net.Connect` in a patch release is immediately visible. The lockfile is the audit trail. CI can enforce `blink audit --no-escalation` to block builds where capability budgets have grown without explicit approval.

**Why package-level capabilities:**

In current ecosystems, `npm install` grants a package the full authority of the running process. A compromised leftpad can exfiltrate environment variables, phone home, or overwrite files. Blink's package capabilities mean a package declaring `capabilities = []` (pure computation) is **provably** unable to perform IO, regardless of what malicious code its author injected. The compiler will not compile a function with effects that exceed its package's declared capabilities.

---

### 4.10 Capability Attenuation

Capabilities can be narrowed but never widened. A handler that receives `Net.Connect` can restrict it to a subset of allowed behaviors:

```blink
fn restricted_net(allowed_hosts: List[Str]) -> Handler[Net.Connect ! Net.Connect] {
    handler Net.Connect {
        fn request(req: Request) -> Result[Response, NetError] {
            let host = parse_host(req.url)
            if allowed_hosts.contains(host) {
                default.request(req)  // delegate to the outer handler
            } else {
                Err(NetError.ConnectionRefused("host {host} not in allowlist"))
            }
        }
    }
}

fn run_third_party_code() ! Net.Connect, IO.Log {
    with restricted_net(["api.trusted.com"]) {
        // Inside this block, net.get("https://api.trusted.com/data") works
        // But net.get("https://evil.com/exfiltrate") returns Err
        third_party_library.fetch_data()
    }
}
```

Attenuation follows the principle of least privilege. When calling untrusted or semi-trusted code, wrap it in a handler that narrows the capabilities to exactly what it needs:

```blink
fn sandbox_plugin(plugin: Plugin) ! FS.Read, Net.Connect, IO.Log, Time.Read {
    let fs_scope = scoped_fs("/var/plugins/{plugin.id}/data/")
    let net_allow = restricted_net(plugin.manifest.allowed_hosts)
    let time_frozen = frozen_time(Instant.from_epoch_secs(1735689600))  // 2026-01-01, deterministic

    with fs_scope, net_allow, time_frozen {
        plugin.run()
    }
}
```

The plugin receives handles that look identical to unrestricted ones. It calls `fs.read(...)`, `net.get(...)`, `time.read()` through the same interface. It has no mechanism to detect or bypass the attenuation. This is the ocap principle: capabilities are unforgeable and can only be attenuated, never amplified.

**Second-tier functions are gated, not virtualized.** A std function or method that has a row but is not a handle op, such as `udp_bind` or `unix_listen` (§4.4.6), needs its effect like any handle op, so a sandbox can deny it by not granting that effect. But no handler can intercept it. Under `with restricted_net(...)`, a call to `udp_bind` still binds a real socket. To restrict such a function, deny the effect.

**Attenuation is compositional:**

```blink
with restricted_net(["*.example.com"]) {
    // net can connect to *.example.com

    with restricted_net(["api.example.com"]) {
        // net can ONLY connect to api.example.com
        // the inner handler narrows further, never widens
    }
}
```

---

### 4.11 What Effects Subsume

The effect system replaces several ad-hoc features that exist as separate mechanisms in other languages:

| Traditional Feature | Blink Replacement | How |
|---|---|---|
| `try`/`catch`/exceptions | `Result[T, E]` + `?` | Errors are values. No invisible control flow. Effect system is orthogonal to error handling. |
| `async`/`await` | `! Async` effect | Concurrency is an effect. Functions that suspend declare it. Handlers provide the runtime (tokio-like, goroutine-like, etc.). |
| Dependency injection | Effect handlers | `with postgres_handler(config) { ... }` replaces constructor injection, service locators, DI containers. |
| Mocking / test doubles | Test handlers | `with mock_db(fixtures) { ... }` replaces mockito, unittest.mock, testdouble. |
| IO monads (Haskell) | `! IO.*` effects | Same purity tracking without monadic syntax (`>>=`, `do` notation). Effects compose with `,`, not monad transformers. |
| Global mutable state | The `State` effect (§4.16) | A function that reads or writes a module-level `let mut` has `State` in its row: declared on `pub` functions, inferred on private ones. Write sets name the bindings each function writes. |
| `synchronized` / locks | `! Sync` effect (future) | Shared mutable state as an explicit effect, not an invisible side channel. |
| Sandbox / permissions | Capability attenuation | `with restricted_net(allowlist) { ... }` replaces OS-level sandboxing, seccomp, AppArmor for application-level policy. |
| Feature flags | Handler selection | `with feature_handler(flags) { ... }` routes effect operations based on runtime configuration. |

The critical insight: these are not different features. They are all manifestations of the same underlying mechanism -- controlling what code is *allowed to do*. The effect system unifies them into a single, compositional, compiler-verified framework.

---

### 4.12 User-Defined Effects

The built-in effects cover standard IO categories, but real applications have domain-specific side effects. Blink allows user-defined effects with the same declaration syntax:

```blink
effect Metrics {
    effect Emit      // emit a metric data point
    effect Query     // query metric history
}

effect Email {
    effect Send
    effect Read
}

effect Payment {
    effect Charge
    effect Refund
    effect Query
}
```

User-defined effects follow all the same rules as built-in effects: hierarchical, handle-based, handler-swappable, composable, budget-constrained.

```blink
fn charge_customer(order: Order) -> Result[Charge, PaymentError] ! Payment.Charge, IO.Log {
    io.log("Charging {order.total} for order {order.id}")
    payment.charge(order.customer_id, order.total)
}

test "charge_customer succeeds for valid order" {
    with mock_payment(), capture_log([]) {
        let result = charge_customer(sample_order())
        assert(result.is_ok())
    }
}
```

User-defined effects get their own handles. The handle name is the lowercase form of the effect name:

| User Effect | Handle |
|---|---|
| `Metrics` | `metrics` |
| `Email` | `email` |
| `Payment` | `payment` |

**Defining effect operations:**

When you declare a user-defined effect, you must define its operations -- the methods available on its handle:

```blink
effect Metrics {
    effect Emit {
        fn counter(name: Str, value: Int)
        fn gauge(name: Str, value: Float)
        fn histogram(name: Str, value: Float)
    }

    effect Query {
        fn get(name: Str, range: TimeRange) -> List[DataPoint]
    }
}
```

A function declaring `! Metrics.Emit` gets `metrics.counter(...)`, `metrics.gauge(...)`, and `metrics.histogram(...)` but not `metrics.get(...)`.

**Leaf effects and effect trees:**

An effect with no sub-effects is a *leaf effect*. A leaf effect declares its operations directly in its body:

```blink
effect Store {
    fn get(key: Str) -> Int
    fn put(key: Str, value: Int)
}

fn load() -> Int ! Store {
    store.get("count")
}
```

`! Store` grants `store.get(...)` and `store.put(...)`. A leaf has no sub-effects, so a row grants all of its operations or none of them. The built-in `Rand` (§4.4.7) is a leaf of this kind.

Four rules govern an effect body:

1. **Operations or sub-effects, never both.** A body holds operations (`fn` items) or sub-effects (`effect` items), never both. The rule applies to every node of every effect tree, built-in or user-declared. So an operation always sits on a node with no sub-effects, and every operation has a node that a row can name. A body with both is `MixedEffectBody` (E0541):

   ```
   error[MixedEffectBody]: effect `Store` declares both operations and sub-effects
    --> store.bl:3:5
     |
   1 | effect Store {
   2 |     effect Read { fn get(key: Str) -> Int }
   3 |     fn clear()
     |     ^^^^^^^^^^ operation beside a sub-effect
     |
     = help: an effect body holds operations or sub-effects, not both;
             move the operations into a sub-effect of their own:
                 effect Ops { fn clear() }
             then give `Ops` a name that says what it grants
   ```

   The fix moves every operation of the body into one new sub-effect. Its name is a placeholder that does not collide with an existing sub-effect. The fix never moves an operation up to the parent.

2. **Two levels at most.** In v1 an effect tree has at most two levels: the top-level effect and one level of sub-effects. A sub-effect cannot declare sub-effects. A sub-effect inside a sub-effect is `EffectNestingTooDeep` (E0542). Rule 1 does not depend on depth, so it stays true if a later version lifts the limit.

3. **Operation names are unique across one tree.** Every operation goes through the one top-level handle (`metrics.counter`, not `metrics.emit.counter`), and a handler lists the operations of the whole tree at one level. So no two nodes of one top-level effect may declare operations with the same name. A duplicate is `DuplicateEffectOp` (E0543), and the diagnostic names both declarations, for example `Metrics.Emit.get` and `Metrics.Query.get`. Two different top-level effects may share an operation name (`store.get`, `cache.get`) because their handles differ.

4. **An empty body is no body.** `effect Audit {}` means the same as `effect Audit`: a leaf with no operations. `blink fmt` rewrites `effect Audit {}` to `effect Audit`. When the braces hold a comment, `blink fmt` keeps the braces and the comment.

The grammar of an effect declaration:

```
effect_decl  ::= "pub"? "effect" IDENT effect_body?
effect_body  ::= "{" ( op_sig* | child_effect* ) "}"
child_effect ::= "effect" IDENT ( "{" op_sig* "}" )?
op_sig       ::= "fn" IDENT "(" params? ")" ( "->" type )?
```

`op_sig` is a function signature with no body; `params` and `type` are as in a `fn` declaration (§2). A `child_effect` has no `effect_body`, which is the two-level limit of rule 2. A `child_effect` with empty braces is the same as a bare `child_effect` (rule 4).

**A row names effects, not operations.** `! Store.get` and `! Clock.now_ms` name no effect, so each is `UnknownEffect` (E0538, §4.3). When the name before the dot is a leaf effect, the diagnostic adds a note that lists the leaf's operations and a help line that names the whole effect. Only the error is normative; the note and help text below are guidance for tools:

```
error[UnknownEffect]: unknown effect `Store.get`
 --> load.bl:1:20
  |
1 | fn load() -> Int ! Store.get {
  |                    ^^^^^^^^^ `Store` has no sub-effect `get`
  |
  = note: `Store` is a leaf effect; its operations are `get` and `put`
  = help: write `! Store`
```

**Splitting a leaf later:** A leaf can grow sub-effects without breaking its users. When `Store` above becomes

```blink
effect Store {
    effect Read {
        fn get(key: Str) -> Int
    }

    effect Write {
        fn put(key: Str, value: Int)
    }
}
```

the following stay valid with no change:

- **Rows.** `! Store` grants every operation of the tree, as before (§4.3).
- **Handlers.** `handler Store { fn get(...) ... fn put(...) ... }` is still complete, because completeness covers every operation of the tree (§4.7.1 *Completeness and auto-delegation*).
- **Calls.** `store.get(...)` is the same call, because operations go through the top-level handle.

Only the declaration changes. Functions can then narrow their rows to `! Store.Read` one at a time. The built-in `Env` (§4.4.3) is an example: moving `exit` into `Env.Exit` kept every `! Env` row and every `handler Env` valid.

**Standard library handlers:**

The standard library ships default handlers for built-in effects (real filesystem, real network, real database drivers). `State` is the exception: it has no handler, and the roots hold it (§4.16.1). User-defined effects have no default handler -- you must provide one. This is intentional: the compiler forces you to explicitly wire up your domain effects, making the architecture visible. A user-defined effect that reaches `main` or a test block with no `with` that discharges it is `UnhandledEffect` (E0539, §4.6 *Unhandled user effects*). No operation answers a default value: an operation that finds no handler at run time panics (§4.7.1 *Completeness and auto-delegation*).

```blink
fn main() {
    let stripe = stripe_payment_handler(config.stripe_key)
    let datadog = datadog_metrics_handler(config.dd_api_key)

    with stripe, datadog {
        start_server()
    }
}
```

**Why user-defined effects matter:**

Without user-defined effects, domain logic bleeds into generic IO. A function that sends an email would declare `! Net.Connect` -- technically accurate but semantically empty. With `! Email.Send`, the function's signature tells you what it does at the domain level. Module budgets can enforce `@capabilities(Payment.Charge, Payment.Query)` -- a billing module cannot send emails. This is where the capability model becomes a real architecture tool, not just an IO tracker.

---

### 4.13 Concurrency as an Effect

Concurrency in Blink is not a language keyword or a function color — it is an effect. The `Async` effect declares that a function may suspend, spawn concurrent tasks, or interact with the runtime scheduler. This means concurrency follows all the same rules as every other effect: declared in signatures, propagated through call graphs, swappable via handlers, constrained by module budgets.

**Core primitives:**

| Primitive | Purpose |
|-----------|---------|
| `async.scope { ... }` | Structured concurrency boundary. All spawned tasks must complete before the scope exits. *(v1: special syntax; v2: may become a `Scoped` type — see §4.7.2)* |
| `async.spawn(fn() { ... })` | Launch a concurrent task within the current scope. Returns `Handle[T]`. |
| `handle.await` | Wait for a spawned task's result. Postfix keyword on a `Handle[T]`, not a method call. Returns `T`. |
| `channel.new[T](buffer: N)` | Create a buffered channel for inter-task communication. |

**The dashboard pattern — fork-join concurrency:**

```blink
fn load_dashboard(user_id: UserId) -> Dashboard ! Async, Http {
    async.scope {
        let user = async.spawn(fn() { fetch_user(user_id) })
        let posts = async.spawn(fn() { fetch_posts(user_id) })
        Dashboard {
            user: user.await
            posts: posts.await
        }
    }
}
```

`async.spawn` returns a `Handle[T]` — an opaque value representing a running task. `handle.await` is a postfix keyword on a `Handle[T]`, not a method call. It is a suspension point: the current task suspends until the spawned task completes, and the expression has the result as its value. The compiler requires `! Async` in the function's effect declaration.

**Handle[T].** A `Handle[T]` is a synchronized object (§3.6 *Synchronized objects*): a copy names the same task. A second `.await`, on the same handle or on a copy, returns the same result again. It does not run the task again. The shared cells that the result reaches are shared between the two results, as with a bind (§3.6 *Shared cells*).

A `Handle[T]` stays in the task that spawned its task. It cannot reach another task through a `ch.send` value or an `async.spawn` capture:

- Where the type shows the handle, this is a compile error. Examples are `channel.new[Handle[Int]]`, a sent struct with a `Handle[T]` field, and a generic `T` that monomorphization makes a `Handle`. For the generic case, the message shows each instantiation from the call site to the send or capture.
- Where the type does not show it, `ch.send` or `async.spawn` panics. A closure type does not show its captures, so a closure that captured `h` panics when it is sent or captured by a spawn. The message names the send or capture site and the `async.spawn` site of the handle.

The compile error is not complete; the panic is the guarantee.

```blink
fn main() {
    async.scope {
        let h = async.spawn(fn() { 21 * 2 })
        let a = h.await
        let b = h.await              // 42 again; the task does not run twice
        assert_eq(a, b)

        async.spawn(fn() { h.await })       // COMPILE ERROR: the capture `h` is a Handle
        let wait = fn() { h.await }
        async.spawn(fn() { wait() })        // PANIC: the capture `wait` reaches a Handle
    }
}
```

A spawned task performs effect operations with the handlers in force at its `async.spawn` site. Spawn is not a root: the closure's row is part of its caller's row (§4.15.4), so the check in §4.6 *Unhandled user effects* covers operations the task performs. A handler in force there whose captures reach a shared cell runs its ops on the task that ran its `with` (§2.8 *Handlers in a spawned task*).

**Why `handle.await` and not `async.join(handle)`:**

Blink uses namespaced functions for *creating* concurrent primitives (`async.scope`, `async.spawn`, `channel.new`) but a postfix keyword for *consuming* results (`handle.await`). A postfix keyword chains naturally with error propagation:

```blink
let user = user_handle.await?   // await, then propagate error
```

**Why not implicit join at scope exit:**

Implicit join only works when you don't need individual task results. The common case — using spawned results to build a composite value — requires explicit access to each task's return value. Implicit join would force a separate mechanism (futures, promises) to extract values, merely renaming the problem.

**Structured concurrency guarantees:**

- No spawn without a scope — tasks cannot outlive their parent
- Scope exit waits for all spawned tasks (awaited or not)
- Un-awaited tasks are cancelled when the scope exits, not silently leaked
- Task panic propagates to the scope, which cancels sibling tasks

**Channels — inter-task communication:**

```blink
fn producer_consumer() ! Async {
    let ch = channel.new[Int](buffer: 10)

    async.scope {
        async.spawn(fn() {
            for i in 0..100 {
                ch.send(i)
            }
            ch.close()
        })

        for value in ch {
            process(value)
        }
    }
}
```

**Channel operations:**

| Method | Behavior |
|--------|----------|
| `ch.send(value: T)` | Blocks while the buffer is full, then adds `value`. **Panics if `ch` is closed.** Copies each shared cell `value` reaches (see *Shared cells cross a channel as copies* below). |
| `ch.recv() -> Option[T]` | Blocks until a value is ready or `ch` is closed. Returns `Some(value)` for the next value. Returns `None` only when `ch` is closed **and** every buffered value is received. |
| `ch.close()` | Marks `ch` closed. Values already in the buffer stay receivable. A second `close()` does nothing. |

`recv()` is the only blocking receive. There is no `try_recv` and no `is_closed()`: a check before a receive races with other consumers, and `recv()` already gives the answer in one step.

**Shared cells cross a channel as copies.** `ch.send(value)` copies each shared cell (§3.6 *Shared cells*) that `value` reaches, at any depth. The receiver gets its own cells. A later change on either side does not show on the other, so a buffer can be sent and then reused:

```blink
let mut batch = [1, 2]
ch.send(batch)
batch.clear()          // the receiver still gets [1, 2]
```

The copy takes time in proportion to the size of the cells it copies. It is the only deep copy in the language, and no function exposes it on its own: `clone()` and binding share a cell (§3.6.1 *Clone Semantics*). A capture in `async.spawn` is not copied; the spawn freezes the cells it reaches instead (§2.8 *Shared cells in a spawned task*). See [decisions/spawn-shared-cell-freeze.md](../decisions/spawn-shared-cell-freeze.md).

The copy does not look inside a synchronized object (§3.6 *Synchronized objects*). A `Channel` in a sent value names the same queue on both sides. A `Handle` in a sent value is an error (*Handle[T]* above).

**The delivery guarantee.** A drain of the channel receives every sent value, in the order sent. A sent value never ends the stream. Closed is a state of the channel, never a value of `T`. `0`, `""`, `false` and — on a `Channel[Option[T]]` — `None` all arrive as `Some(...)`:

```blink
let ch = channel.new[Option[Int]](buffer: 2)
ch.send(None)
ch.close()
assert_eq(ch.recv(), Some(None))   // the sent value
assert_eq(ch.recv(), None)         // closed and drained
```

**Who closes.** One owner closes a channel, after every producer has finished sending. With several producers, the owner joins them first, then closes. A `send` after `close()` is a bug in the program, so it panics and does not drop the value.

**Receiving.** `for value in ch` is the common form: it receives until the channel is closed and drained, then stops (see §3c.1 for the desugaring). When a single receive must deal with a closed channel, use the same tools as for any other `Option`:

```blink
// Fan-in: stop when every producer is done and the channel is closed
let mut total = 0
loop {
    match results.recv() {
        Some(n) => total += n
        None => break
    }
}

// A default when the channel is closed
let first = results.recv() ?? 0

// Propagate "closed" to an Option-returning caller
fn recv_pair(ch: Channel[Int]) -> Option[(Int, Int)] ! Async {
    let a = ch.recv()?
    let b = ch.recv()?
    Some((a, b))
}
```

Discarding the result of `recv()` is legal. Code that must not go on after the channel closes says so with `.unwrap()`, which panics at the `recv()` call:

```blink
sem.recv().unwrap()   // wait for a permit; a closed semaphore is a bug
```

**Panel vote: 6-0** on every question. See [decisions/channel-recv-closed-empty.md](../decisions/channel-recv-closed-empty.md).

**Effects on `main` — implicit `Async`:**

`main` has implicit effects (see section 4.6), which includes `Async`. This means `main` can use `async.scope` directly without declaring `! Async`:

```blink
fn main() {
    async.scope {
        let result = async.spawn(fn() { fetch_data() })
        io.println(result.await)
    }
}
```

The runtime schedules tasks implicitly. Every other function that suspends must declare `! Async` explicitly.

**Panel vote: 5-0** for `handle.await`. See [OPEN_QUESTIONS.md](../OPEN_QUESTIONS.md).

---

### 4.14 Full Example: Effect System in Practice

Putting it all together -- a small order processing service demonstrating hierarchical effects, handlers, module budgets, and testing:

```blink
@capabilities(DB.Read, DB.Write, Payment.Charge, IO.Log)
module orders

@derive(Debug)
type OrderError {
    NotFound
    InsufficientStock(item_id: Int, available: Int)
    PaymentFailed(reason: Str)
    InvalidOrder(reason: Str)
}

fn validate(order: Order) -> Result[Order, OrderError] {
    // Pure function -- no effects, no handle access
    if order.items.is_empty() {
        Err(OrderError.InvalidOrder("empty order"))
    } else {
        Ok(order)
    }
}

fn check_inventory(order: Order) -> Result[(), OrderError] ! DB.Read {
    for item in order.items {
        let stock = db.query_one(t"SELECT quantity FROM inventory WHERE id = {item.id}")?
        if stock < item.quantity {
            return Err(OrderError.InsufficientStock(item.id, stock))
        }
    }
    Ok(())
}

fn reserve_stock(order: Order) -> Result[(), DBError] ! DB.Write {
    for item in order.items {
        db.exec(t"UPDATE inventory SET quantity = quantity - {item.quantity} WHERE id = {item.id}")?
    }
}

fn charge(order: Order) -> Result[ChargeId, OrderError] ! Payment.Charge {
    payment.charge(order.customer_id, order.total)
        .map_err(fn(e) { OrderError.PaymentFailed(e.to_str()) })
}

fn place_order(order: Order) -> Result[Receipt, OrderError] ! DB.Read, DB.Write, Payment.Charge, IO.Log {
    let order = validate(order)?
    check_inventory(order)?
    reserve_stock(order)
    let charge_id = charge(order)?
    let receipt = Receipt { order_id: order.id, charge_id, total: order.total }
    io.log("Order {order.id} placed: {receipt.charge_id}")
    Ok(receipt)
}

// --- Tests ---

fn mock_inventory(stock: Map[Int, Int]) -> Handler[DB] {
    handler DB {
        fn read(query: Template[DB]) -> Result[Any, DBError] {
            // query.template and query.params available for matching
            let item_id = parse_item_id(query)
            match stock.get(item_id) {
                Some(qty) => Ok(qty)
                None => Err(DBError.NotFound)
            }
        }
        fn write(query: Template[DB]) -> Result[(), DBError] { Ok(()) }
        fn admin(query: Template[DB]) -> Result[(), DBError] {
            Err(DBError.PermissionDenied("not in test scope"))
        }
    }
}

fn mock_payment_success() -> Handler[Payment] {
    handler Payment {
        fn charge(customer_id: Int, amount: Float) -> Result[ChargeId, PaymentError] {
            Ok(ChargeId.fake("test_charge_001"))
        }
        fn refund(charge_id: ChargeId) -> Result[(), PaymentError] { Ok(()) }
        fn query(charge_id: ChargeId) -> Result[ChargeInfo, PaymentError] {
            Ok(ChargeInfo.fake())
        }
    }
}

test "place_order succeeds with sufficient stock" {
    let stock = Map.of([(1, 100), (2, 50)])

    with mock_inventory(stock), mock_payment_success(), capture_log([]) {
        let order = Order { id: 1, customer_id: 42, items: [Item { id: 1, quantity: 5 }], total: 49.99 }
        let result = place_order(order)
        assert(result.is_ok())
        assert_eq(result.unwrap().total, 49.99)
    }
}

test "place_order fails with insufficient stock" {
    let stock = Map.of([(1, 2)])

    with mock_inventory(stock), mock_payment_success(), capture_log([]) {
        let order = Order { id: 2, customer_id: 42, items: [Item { id: 1, quantity: 10 }], total: 99.99 }
        let result = place_order(order)
        assert_matches(result, Err(OrderError.InsufficientStock(_, _)))
        match result {
            Err(OrderError.InsufficientStock(id, avail)) => {
                assert_eq(id, 1)
                assert_eq(avail, 2)
            }
            _ => panic("expected InsufficientStock")
        }
    }
}
```

Notice what the effect system gives you in this example:

1. **`validate` is pure.** No `!`, no handle. It cannot accidentally log, query, or charge. The compiler guarantees it.
2. **`check_inventory` is read-only.** `! DB.Read`. It cannot modify stock, cannot charge payment. If someone adds a `db.exec(...)` call, the compiler rejects it.
3. **`charge` only touches payment.** It cannot read the database. It cannot log. Separation of concerns is compiler-enforced, not a convention.
4. **The module budget is `DB.Read, DB.Write, Payment.Charge, IO.Log`.** If someone adds `! Net.Connect` to any function, the module budget rejects it. The orders module does not make network calls -- period.
5. **Tests swap all effects with handlers.** No real database, no real payment processor, no real logging. The same code runs in both contexts because the interface (handles) is identical.
6. **Every function's capability surface is in its signature.** An AI reading `place_order`'s type knows exactly what it can do. A security reviewer scanning `@capabilities` on the module knows the outer bound.

This is effects as capabilities as security, end to end.

---

### 4.15 Effect Polymorphism

Function types can carry effect annotations, and higher-order functions can forward those effects to their own signatures using the wildcard `! _`.

#### 4.15.1 Effects on Function Types

Function types follow the same `!` syntax as function declarations. A function type without `!` is pure; a function type with `!` declares the effects the callback may perform:

```blink
// Pure callback — no effects
fn apply[T, U](f: fn(T) -> U, x: T) -> U {
    f(x)
}

// Effectful callback — specific effects
fn with_logging(f: fn(Str) -> () ! IO.Log) ! IO.Log {
    f("starting")
    f("done")
}

// Function type with multiple effects
fn transform(f: fn(Row) -> Row ! DB.Read, IO.Log) -> List[Row] ! DB.Read, IO.Log {
    let rows = db.query(t"SELECT * FROM data")?
    rows.map(fn(r) { f(r) })
}
```

The effect annotation on a function type is part of the type identity. `fn(Int) -> Int` and `fn(Int) -> Int ! IO` are different types — the compiler rejects passing an effectful callback where a pure one is expected:

```
error[EffectMismatchInFnType]: effect mismatch in function type
 --> app.bl:5:12
  |
5 |     apply(logger, 42)
  |           ^^^^^^ expected pure `fn(Int) -> Int`, found `fn(Int) -> Int ! IO.Log`
  |
  = note: `apply` requires a pure callback
  = fix: use a HOF that accepts effectful callbacks, or remove effects from the callback
```

The reverse is safe: a pure callback satisfies an effectful parameter (pure is a subtype of effectful — a function that *can* do IO doesn't *have to*):

```blink
fn for_each(items: List[T], f: fn(T) -> () ! IO.Log) ! IO.Log {
    for item in items {
        f(item)
    }
}

// OK: pure fn passed where effectful fn expected
for_each(names, fn(name) { let _ = name.len() })
```

#### 4.15.2 Wildcard Effect Forwarding

When a higher-order function should propagate whatever effects its callback performs, use `! _` (wildcard) in both the callback type and the function's own effect list:

```blink
// Iterator.map forwards callback effects
fn map[U](self, f: fn(T) -> U ! _) -> Iterator[U] ! _ {
    // effects from f flow through to caller
}

// filter forwards callback effects
fn filter(self, pred: fn(T) -> Bool ! _) -> Iterator[T] ! _ {
    // effects from pred flow through to caller
}

// fold forwards callback effects
fn fold[U](self, init: U, f: fn(U, T) -> U ! _) -> U ! _ {
    let mut acc = init
    for item in self {
        acc = f(acc, item)
    }
    acc
}

// for_each forwards callback effects
fn for_each(self, f: fn(T) -> () ! _) ! _ {
    for item in self {
        f(item)
    }
}
```

> **v1 note.** The `Iterator` adapters above illustrate the *shape* of wildcard forwarding; they do not describe v1 `Iterator`. In v1 the built-in `Iterator[T]` carrier is **pure** — an adapter callback that performs effects is a compile error, and no v1 surface signature spells the effect row (§3c.1 *Effectful Iteration: Deferred to v2*). The `! _` forwarding shown here is the reserved v2 shape and the live mechanism for ordinary user higher-order functions. It is used here because it is the clearest worked example of the wildcard rule.

The wildcard `_` means: "whatever effects the callback has, this function has too." At call sites, the compiler resolves `_` to the concrete effects of the callback passed:

```blink
fn process_items(items: List[Item]) ! DB.Read, IO.Log {
    items.into_iter()
        .filter(fn(item) { item.is_active() })          // pure callback: _ = (nothing)
        .map(fn(item) {
            let price = db.query_one(t"SELECT ...")?       // _ = DB.Read
            io.log("Processing {item.id}")               // _ = IO.Log
            item.with_price(price)
        })
        .for_each(fn(item) {
            io.log("Done: {item.id}")                    // _ = IO.Log
        })
}
```

**Multiple wildcard parameters:** When a function takes multiple effectful callbacks, their effects are unioned:

```blink
fn zip_with[A, B, C](
    iter_a: Iterator[A],
    iter_b: Iterator[B],
    f: fn(A, B) -> C ! _
) -> Iterator[C] ! _ {
    // _ in return position = union of all _ parameters
}
```

**Wildcard with explicit effects:** A function may have both its own effects and forwarded callback effects:

```blink
fn logged_map[U](self, label: Str, f: fn(T) -> U ! _) -> Iterator[U] ! IO.Log, _ {
    io.log("Starting {label}")
    self.map(f)
}
```

Here `! IO.Log, _` means: this function always requires `IO.Log` (for its own logging), plus whatever the callback needs.

**Handler parameters.** A handler parameter can carry the wildcard in its clause row (§4.7.1, *The clause row*). `Handler[E ! _]` forwards the effects that the operation bodies of the handler perform:

1. `Handler[E ! _]` may appear only where `fn(..) ! _` may: in a parameter type of a function whose own row has `_`.
2. Inside the callee, `_` is opaque. `with h` is charged `_`, as a call of a `fn() ! _` parameter is.
3. At each call site, `_` is one union of the rows of all the `! _` arguments: the rows of the closures and the clause rows of the handlers. A handler with an empty clause row adds nothing.
4. Projection (§4.7.1) keeps the clause row and runs before the union.
5. The row is never reduced. The caller is charged the full row of each argument (the row of a closure or the clause row of a handler), even when the callee discharges part of it with an inner `with`. This holds the same for closure arguments and handler arguments.
6. If the caller lacks an effect of the union, E0500 fires at the argument, with the same message shape as for closures.

```blink
fn run_job(job: fn() -> () ! _, h: Handler[DB ! _]) ! _ {
    with h {
        job()
    }
}

fn nightly() ! DB, IO.Log {
    run_job(fn() { io.log("start") }, logging_db("nightly"))
    // _ = IO.Log (the closure) + DB, IO.Log (the clause row of logging_db)
}

fn bad_nightly() ! IO.Log {
    run_job(fn() { io.log("start") }, logging_db("nightly"))   // ERROR E0500: missing DB
}
```

#### 4.15.3 Call-Site Resolution

- **Concrete effect function types** (`fn(T) -> U ! IO.Log`): The caller must hold the required effects at the call site.

- **Wildcard forwarding** (`! _`): `_` resolves at each call site to the concrete effects of the callback argument. A `Handler[E ! _]` argument counts with its clause row (§4.15.2, *Handler parameters*).

- **Pure callbacks in wildcard positions**: When a pure callback is passed to a `! _` function, `_` resolves to the empty effect set. The function is pure at that call site.

#### 4.15.4 Interaction with Existing Features

**Effect composition (§4.5):** Wildcard effects compose with explicit effects following the same propagation rules. A caller must declare at least all effects that resolve through `_`:

```blink
fn caller() ! DB.Read {
    items.map(fn(x) { db.query(t"...") })  // OK: _ resolves to DB.Read, caller has it
}

fn bad_caller() {
    items.map(fn(x) { db.query(t"...") })  // ERROR E0500: missing DB.Read
}
```

**Handlers (§4.7):** Handlers can intercept effects that flow through wildcards:

```blink
test "map with mock DB" {
    with mock_db() {
        let results = items.map(fn(x) { db.query(t"...") })
        // handler intercepts DB.Read flowing through map's _
    }
}
```

**Closures (§2.8):** Closures used as effectful callbacks follow the same capture rules. Effect annotations on the closure type describe what the closure *body* does, not what it captures.

**async.spawn (§4.13):** `async.spawn` takes `fn() -> T ! _` — the spawned task inherits whatever effects the closure declares. The existing E0650 restriction on `let mut` captures still applies, and so does the freeze of the shared cells its captures reach (§2.8 *Shared cells in a spawned task*). A handler in force at the spawn site whose captures reach a shared cell is homed (§2.8 *Handlers in a spawned task*). A function value whose row contains `State` cannot be spawned (E0651, §4.16.6).

#### 4.15.5 What Is Deferred to v2

**Named effect variables (row polymorphism):** v1 uses `_` which covers the common case of "forward all callback effects." v2 may introduce named effect variables for advanced use cases:

```blink
// v2 potential syntax — NOT v1
fn map[T, U, e](f: fn(T) -> U ! e) -> Iterator[U] ! e
fn zip_with[A, B, C, e1, e2](f: fn(A) -> B ! e1, g: fn(B) -> C ! e2) -> Iterator[C] ! e1, e2
```

Named variables enable: distinguishing effect sets from different callbacks, constraining effects (e.g., "callback may do IO but not DB"), and composing effect sets algebraically. The `_` wildcard is forward-compatible — it can desugar to an anonymous effect variable when named variables are added.

**Effectful iteration:** The vote deferring effectful iteration to v2 remains in effect. In v1 the `Iterator[T]` carrier is pure and its reserved effect row is invisible on every surface signature (§3c.1). Surfacing that row so effectful callbacks in `map`, `filter`, `fold`, and `for_each` become expressible is a conservative v2 extension, gated on real-world feedback.

---

### 4.16 Module-Level State

A module can hold mutable state in module-level `let mut` bindings. Each function that reads or writes such a binding shows it in its row with the built-in effect `State`. The compiler also computes the **write set** of each function: the bindings it writes. Diagnostics and tools use the write set.

```blink
let mut count = 0

fn bump() {                          // private: `State` is inferred
    count = count + 1
}

pub fn next_id() -> Int ! State {    // public: `State` is declared
    bump()
    count
}
```

#### 4.16.1 The `State` Effect

`State` is a built-in leaf effect (§4.3). A function's row contains `State` when the function touches module state:

- its body reads or writes a module-level `let mut` binding of its module (§4.16.2), or
- it calls a function whose row contains `State`, in any module, through a direct call, a function value, a trait method or a `! _` row (§4.15.2).

`State` is not like the other effects:

- **No operations and no handler.** `State` has no handle and no operations. A `handler State { ... }`, or a `with` that names `State`, is `StateNotHandleable` (E0545). Nothing discharges `State`: it stays in the row of every caller up to the root.
- **The roots hold it.** `main` (§4.6) and each test block (§2.20) hold `State`. `UnhandledEffect` (E0539) never fires for `State`.
- **Not a capability.** Module capability budgets (§4.8, §4.9) ignore `State`. Module state stays inside its module and does not cross a trust boundary, so a package that declares `capabilities = []` can still use module-level `let mut`.
- **No run-time cost.** `State` changes no generated code (§4.16.9).

**Declared at the boundary, inferred inside.** A function at the module boundary must write `State` in its row when it touches module state. The boundary functions are:

- each `pub fn`,
- each `pub` method,
- each method in a trait `impl`.

A boundary function whose body touches module state, and whose row does not name `State`, is `UndeclaredModuleState` (E0552). This is also the code when the only cause is a call to a function that declares `State`; E0500 does not fire for `State`. The diagnostic has one `note:` line for each binding the function touches. The note names the binding, says whether it is read or written, and gives the location of the access. When the access is in a callee, the note also names the call. The fix adds `State` to the row, and it is machine-applicable (§8.6).

```blink
let mut count = 0

fn bump() {
    count = count + 1
}

pub fn next_id() -> Int {
    bump()
    count
}
```

```
error[UndeclaredModuleState]: `next_id` touches module state but does not declare `State`
 --> src/ids.bl:7:8
  |
7 | pub fn next_id() -> Int {
  |        ^^^^^^^ a public function declares `State` in its row
  |
  = note: writes `count` at src/ids.bl:4:5, through the call to `bump` at src/ids.bl:8:5
  = note: reads `count` at src/ids.bl:9:5
  = help: add `State` to the row: `pub fn next_id() -> Int ! State`
```

A private function or a closure does not need to write `State`. The compiler adds it to the function's **effective row**: the declared row, plus `State` when the function touches module state. A private function can write `State` in its row; the effective row is the same.

Every rule that checks a row checks the effective row:

- **Calls (§4.5).** A call puts the callee's effective row into the caller's row.
- **Function values (§4.15.1).** The type of a function value carries its effective row. A closure literal whose body touches module state has a type with `! State`. The usual row checks then apply where the value goes. For example, a closure that reads `count` cannot be passed where `fn() -> Int` is expected; the parameter type must be `fn() -> Int ! State` or `fn() -> Int ! _`.
- **Trait impls (§4.5).** `TraitContractEffectMismatch` (E0904) compares the impl method's effective row with the trait method's row. A trait method with no `!` cannot have an impl that touches module state (§4.16.6).
- **`@pure` (§3b.2).** A `@pure` function has an empty effective row (§4.16.3).

#### 4.16.2 What Puts `State` in a Row

| Access | `State` in the row? | In the write set? | Rationale |
|--------|---------------------|-------------------|-----------|
| Assign to module-level `let mut` (`pos = pos + 1`) | **Yes** | **Yes** | Direct mutation |
| Mutating method call on module-level `let mut` (`tokens.push(t)`) | **Yes** | **Yes** | Mutation through a method |
| Read module-level `let mut` (`return pos`) | **Yes** | No | The result depends on state that a call can change |
| Call a function whose row contains `State` | **Yes** | The callee's write set, if the callee is in this module | `State` propagates like any effect; write sets do not cross modules (§4.16.4) |
| Read module-level `let` (immutable) or `const` | No | No | Immutable — equal to a constant |
| Read/write function-local `let mut` | No | No | Contained within function scope |
| Mutate collection received as parameter | No | No | The parameter must be declared `mut`, so the signature shows it (§3.6 *Mutable Parameters*) |
| Mutate captured function-local `let mut` in closure | No | No | Lexically scoped — visible within enclosing function body |

A read counts because the module can change the binding between two calls. The write set counts writes only, because W0550 and W0551 (§4.16.7) need to know which bindings a function can change.

**A `let mut` that nothing writes.** A module-level `let mut` that no code in its module writes is `ModuleLetMutNeverWritten` (W0552). Its readers have `State` in their rows for no reason. The `help:` line says to declare it with `let`, and that fix is machine-applicable (§8.6). Set its level with `W0552` under `[lints]` (§4.16.8). Since `pub let mut` is forbidden (E1013, §2.12.1), only code in the binding's module can write it, so the check is exact.

```
warning[ModuleLetMutNeverWritten]: module-level `let mut` `limit` is never written
 --> src/config.bl:1:9
  |
1 | let mut limit = load_limit()
  |         ^^^^^ no code in this module writes `limit`
  |
  = note: each function that reads `limit` has `State` in its row
  = help: declare it with `let`: `let limit = load_limit()`
```

#### 4.16.3 Purity

A function whose effective row is empty is **pure**: its result depends only on its arguments. It performs no side effects and touches no module state. A function that only reads module state is not pure; its row has `State`.

`@pure` (§3b.2) asks the compiler to prove that a function is pure. A `@pure` function whose effective row is not empty, `State` included, is `ImpureBodyForPureAnnotation` (E1307).

```blink
let mut pos = 0

// Effective row: State — reads `pos`, so the result depends on call order
fn current_pos() -> Int {
    pos
}

// Pure — empty effective row
fn add(a: Int, b: Int) -> Int {
    a + b
}

// Effective row: State — writes {pos}
fn advance() {
    pos = pos + 1
}
```

The three functions are private, so their signatures do not write `State`. A `pub` version of `current_pos` or `advance` declares `! State`.

#### 4.16.4 Write Sets

The compiler computes the write set of each function in a module: the module-level `let mut` bindings that the function, or a callee in the same module, writes. `State` says that a function touches module state. The write set says which bindings it writes.

**Properties:**

- **Inferred** — no signature shows a write set.
- **Writes only** — a read does not add to the write set.
- **Includes method calls** — `list.push(x)` on a module-level `let mut` binding is a write.
- **Transitive within the module** — if `fn a()` calls `fn b()`, which writes `pos`, then `pos` is in the write set of `a`.
- **Closures** — a write in a closure counts in the write set of the enclosing function.

```
advance()               → writes {pos}
skip_newlines()         → writes {pos, pending_comments}
at()                    → writes {}  (reads pos, so its row has State)
looks_like_struct_lit() → writes {pos, pending_comments}
```

```blink
let mut pos = 0
let mut pending_comments: List[Comment] = []

fn advance() {                           // writes {pos}
    pos = pos + 1
}

fn skip_newlines() {                     // writes {pos, pending_comments}
    while at() == CH_NEWLINE {
        advance()
        if at() == CH_HASH {
            pending_comments.push(parse_comment())
        }
    }
}

fn looks_like_struct_lit() -> Bool {     // writes {pos, pending_comments}
    let saved_pos = pos
    let saved_comments = pending_comments.clone()
    skip_newlines()
    let result = at() == CH_LBRACE
    pos = saved_pos
    pending_comments = saved_comments
    result
}
```

The compiler knows that `looks_like_struct_lit` writes `{pos, pending_comments}` through `skip_newlines`, so it can check that both are saved and restored. When a save/restore pattern misses a binding, it reports W0550 (§4.16.7):

```
warning[IncompleteStateRestore]: speculative lookahead may leave stale state
 --> parser.bl:42:5
  |
42 |     let saved = pos
  |         ^^^^^ saves `pos` before calling `skip_newlines`
  |
  = note: `skip_newlines` writes {pos, pending_comments}
  = note: only `pos` is restored after the call
  = help: also save and restore `pending_comments`, or use a
          non-mutating alternative
```

**Write sets do not cross modules.** The compiler does not look inside a function from another module, so a call to it adds nothing to the write set. `State` still crosses modules: the callee's row declares it, and the caller's row gets it (§4.16.1).

**Tooling (not normative).** `blink query --fn` (§8.3), `blink doc` and the LSP show the write set of a function on hover and as an inlay hint, next to its row.

#### 4.16.5 User-Defined Effects as Labels

`State` says only that a function touches module state. A module can also tell its callers what kind of change a call makes with a **user-defined effect** (§4.12). This label is optional, and it does not take the place of `State`: a boundary function that touches module state declares `State` as well.

```blink
effect Parse {
    effect Advance
    effect Reset
}

pub fn next_token() -> Token ! Parse.Advance, State {
    pos = pos + 1
    // ...
}

pub fn reset(saved: ParserState) ! Parse.Reset, State {
    pos = saved.pos
    pending_comments = saved.comments
}
```

Callers see `! Parse.Advance` and know that the call moves the parser. A user-defined effect follows all the rules of §4.12: it is hierarchical, and a root must discharge it with `with` (§4.6 *Unhandled user effects*).

#### 4.16.6 Interaction with Existing Features

**Trait impls (§4.5, §3.6).** A trait impl method is a boundary function, and E0904 checks its effective row. So a method that touches module state can implement only a trait method whose row contains `State`. A `Display.fmt`, `Eq.eq`, `Hash.hash` or `Ord.cmp` impl that reads or writes a module-level `let mut`, for example to cache a result, is `TraitContractEffectMismatch` (E0904). Hold the cache in a value that the caller passes in.

**`async.spawn` (§4.13, §2.8).** Two tasks that touch one module-level `let mut` race. A function value passed to `async.spawn` whose effective row contains `State` is `SpawnTouchesModuleState` (E0651). The rule covers a closure literal and a named function alike. The `help:` line says to pass the data in, return it from the task, or use a `Channel` (§4.13).

```blink
let mut items: List[Int] = []

fn add(n: Int) {
    items.push(n)
}

fn main() {
    async.scope {
        let task = async.spawn(fn() { add(1) })
        add(2)
        task.await
    }
}
```

```
error[SpawnTouchesModuleState]: spawned task touches module state
 --> src/app.bl:9:32
  |
9 |         let task = async.spawn(fn() { add(1) })
  |                                ^^^^^^^^^^^^^^^ the row of this function contains `State`
  |
  = note: writes `items` at src/app.bl:4:5, through the call to `add` at src/app.bl:9:39
  = help: pass the data in, return it from the task, or use a `Channel`
```

**`main` and test blocks (§4.6, §2.20).** Both hold `State`, so they can touch module state with no `with`. A test whose row has `State` is not free of side effects (§2.20).

**Module capability budgets (§4.8, §4.9).** Budgets ignore `State` (§4.16.1).

**Iterator adapters (§3c.1).** A v1 adapter closure is pure (§3c.1), so a closure whose row has `State` cannot be an adapter closure. Use a `for` loop, or a `List` method that takes `! _` (§4.15.2).

**Closures (§2.8).** A closure's own effective row carries `State` when its body touches module state. The enclosing function gets `State` only when it calls the closure, or passes it to a callee whose row forwards it with `_`. A closure that captures only function-local `let mut` bindings does not get `State`.

#### 4.16.7 Diagnostic Precision: W0550 and W0551

The write-set analysis (§4.16.4) produces two warnings related to save/restore patterns in speculative code (lookahead, backtracking):

**W0550 (IncompleteStateRestore):** Fires when a function saves SOME module-level `let mut` bindings before a call, but the callee's write set includes additional bindings that are not saved or restored. This is the high-value diagnostic — it catches exactly the speculative-lookahead bugs that motivated the analysis.

```
warning[IncompleteStateRestore]: speculative lookahead may leave stale state
 --> parser.bl:42:5
  |
42 |     let saved = pos
  |         ^^^^^ saves `pos` before calling `skip_newlines`
  |
  = note: `skip_newlines` writes {pos, pending_comments}
  = note: only `pos` is restored after the call
  = help: also save and restore `pending_comments`, or verify the mutation is intentional
```

**W0551 (UnrestoredMutation):** Fires when a function that already has a save/restore pattern (i.e., it is doing speculative work) calls a function whose write set includes unsaved bindings. Unlike W0550, W0551 applies to call sites where the caller has *no* saves for the *specific callee* — but the presence of save/restore patterns elsewhere in the function indicates speculative intent.

**Context-aware firing:** W0551 only fires inside functions that already exhibit at least one save/restore pattern. Functions with no save/restore patterns at all are doing normal sequential mutation and do not trigger W0551. This eliminates false positives from normal code calling utility functions with large write sets.

```blink
fn looks_like_struct_lit() -> Bool {     // has save/restore → speculative context
    let saved_pos = pos                  // save pattern detected
    let saved_comments = pending_comments.clone()
    skip_newlines()                      // W0550 would fire if saves were incomplete
    let result = at() == CH_LBRACE
    pos = saved_pos                      // restore
    pending_comments = saved_comments    // restore
    result
}

fn compile_module(path: Str) -> Result[Module, CompileError] ! IO {
    // No save/restore patterns → not speculative → W0551 does NOT fire
    diag_emit("error", name, code, msg, line, col, help)  // OK, no warning
}
```

**No threshold.** W0551 does not use a write-set size threshold. Inside a speculative context, any unsaved mutation is potentially a bug regardless of how many globals the callee writes. The context-aware heuristic (save/restore pattern present) is the sole gating condition.

#### 4.16.8 Warning Suppression

Write-set warnings can be suppressed at two levels:

**Per-function: `@allow(WarningName)`**

```blink
@allow(UnrestoredMutation)
fn parse_with_fallback() -> Node {
    let saved_pos = pos
    // Intentionally not saving all state — we know what we're doing
    try_parse_complex()
    pos = saved_pos
    parse_simple()
}
```

`@allow` takes the warning name (PascalCase) as its argument. It suppresses all instances of that warning within the annotated function. Multiple warnings can be suppressed: `@allow(UnrestoredMutation, IncompleteStateRestore)`.

**Project-wide: `blink.toml` `[lints]` section**

```toml
[lints]
W0551 = "off"       # disable UnrestoredMutation globally
W0550 = "error"     # upgrade IncompleteStateRestore to error
```

Valid severity levels: `"off"` (suppress), `"warn"` (default for W0550/W0551), `"error"` (fail compilation).

**Precedence:** Function-level `@allow` always overrides project-level `blink.toml` configuration. A function annotated with `@allow(UnrestoredMutation)` will not emit W0551 even if `blink.toml` sets `W0551 = "error"`.

**Only warnings.** `@allow` and `[lints]` reach only the diagnostics listed under *Warning Names* in ERROR_CATALOG.md. The catalog row decides, not the severity in effect: a warning that `--strict`, `--strict-struct-layout` or `"error"` under `[lints]` makes fail the build is still a warning name, so `@allow` reaches it. Any other live name is the error `NotAWarningName` (E0847): a name under *Error Names* (`ContractUnverifiable` V0003 included), a name under *Info Names*, or an internal compiler error. An error means the compiler cannot give the program a meaning, so a suppressed error would reach code generation or run as wrong code. Like E0842, E0847 is refused, not ignored. No `@allow` or `[lints]` entry suppresses it or changes its severity, every level is refused (`"error"` included), and the compiler reports each such argument and key, not only the first. The named error still fires at its own site; E0847 does not replace it.

```blink
type Color { Red Green Blue }

// intentional-error example
@allow(NonExhaustiveMatch)   // error[NotAWarningName]: `NonExhaustiveMatch` is an error;
                             //   `@allow` takes warning names only
                             // help: remove this argument
fn name(c: Color) -> Str {
    match c {                // error[NonExhaustiveMatch]: missing pattern `Blue`
        Red => "red"
        Green => "green"
    }
}
```

The first `help:` line says to remove the argument or key. The next line gives the repair from the named error's own help. Some errors have a better repair through their own control: `ContractUnverifiable` (V0003) through `@verify(fallback: ...)` (§3b.4), `CapabilityBudgetExceeded` (E0501) through a wider `@capabilities` (§4.8). ERROR_CATALOG.md *Conventions* records that repair as catalog data. When no repair fits the `@allow` site, the help is generic and a `note:` names `blink explain <Name>`. The help never proposes another `@allow` argument and never proposes a `_ => panic(...)` arm.

**Check order.** The compiler checks for E0842 first, so a name that is not live gets E0842 and nothing else. A live name then gets at most one of `AuditGatedSuppression` (E0837, an audit-gated warning, §9.1) and E0847 (a name not under *Warning Names*). The two sets do not overlap, because the audit-gated list holds warnings only (§9.1), so no order between them is given.

**Unknown names.** Each `@allow` argument and each `[lints]` key must identify a live diagnostic. A misspelled name, a retired name or code, or a code given to `@allow` is the error `UnknownDiagnosticName` (E0842). It is an error, so no `@allow` or `[lints]` entry reaches it (*Only warnings*, above), and a typo cannot silently disable a suppression or an `"error"` gate.

```blink
@allow(UnrestoredMutaton)   // error[UnknownDiagnosticName]: help: did you mean `UnrestoredMutation`?
fn parse_fast() -> Node {
    parse_simple()
}
```

ERROR_CATALOG.md *Conventions* gives the `help:` line for each case and what `blink explain` prints for a retired or unknown name.

**Invalid levels.** Each `[lints]` value must be one of the three levels above. Any other value, such as `W0551 = "loud"` or `W0551 = "warning"`, is the error `InvalidLintLevel` (E0843). Like E0842, it is refused, not ignored. It is an error, so no `@allow` or `[lints]` entry reaches it (*Only warnings*, above), and `--strict` does not change it. The span is the value token, quotes included (§8.9.8), and the help line lists the valid levels.

#### 4.16.9 No Runtime Effect

`State` and write sets change no program behavior. They produce only diagnostics and tooling data, and `State` adds nothing to the generated code.
