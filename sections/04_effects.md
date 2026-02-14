## 4. Effect System

### 4.1 Thesis: Effects Are Capabilities Are Security

Pact's effect system is not a type annotation convenience. It is the security architecture of the language.

Every side effect a function can perform -- printing, reading a database, opening a socket, spawning a process -- is a **capability** that must be explicitly declared in the function's signature and granted by its caller. This is the object-capability model (ocap), as pioneered by Mark Miller's E language, applied at the type level: no ambient authority, no implicit permissions, no action-at-a-distance.

The consequences are structural:

- A function with no `!` in its signature **cannot** perform side effects. The compiler proves it.
- A function declaring `! DB.Read` can query a database but **cannot** write to it, delete from it, or administer it. The compiler proves it.
- A package declaring `capabilities(Net.Connect)` in its manifest **cannot** open a listening socket. The compiler proves it.
- An effect handler can attenuate capabilities -- handing a function a `Net.Connect` that only permits connections to a specific allowlist. The runtime enforces it.

There is no separate "permissions" system, no runtime ACLs, no sandbox configuration files. The effect system **is** all of these things. Capabilities are tracked through the type system, enforced by the compiler, and attenuated through handlers. Zero runtime cost for the checks themselves -- if your code compiles, the capability discipline is guaranteed.

**Why fine-grained effects must be v1, not v2:**

Coarse effects collapse to meaninglessness within three call levels. Consider a real application:

```pact
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

```pact
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

```pact
// Pure function -- no effects, no bang
fn add(a: Int, b: Int) -> Int {
    a + b
}

// Single effect, returns ()
fn log_message(msg: Str) ! IO.Log {
    io.log(msg)
}

// Single effect with return type
fn read_config(path: Str) -> Result[Config, IOError] ! FS.Read {
    let text = fs.read(path)?
    parse_config(text)
}

// Multiple fine-grained effects
fn process_order(id: Int) -> Result[Receipt, OrderError] ! DB.Read, DB.Write, IO.Log {
    let order = db.read("SELECT * FROM orders WHERE id = {id}")?
    io.log("Processing order {id}")
    let receipt = Receipt { order_id: id, total: order.total }
    db.write("INSERT INTO receipts ...", receipt)?
    Ok(receipt)
}

// Parent effect grants all children
fn dangerous_migration() ! DB {
    // DB grants DB.Read, DB.Write, DB.Admin -- the whole tree
    db.admin("DROP TABLE legacy_data")
    db.write("INSERT INTO migrations ...")
    db.read("SELECT count(*) FROM migrations")
}
```

The `!` was chosen by 3-2 vote over `/`. It universally signals danger or impurity (`!` in Scheme for mutation, Rust for macros, Swift for throwing). It is a single character -- maximally token-efficient. It is visually distinctive in a signature. It does not collide with any operator in expression position.

---

### 4.3 Effect Hierarchy

Effects are declared as hierarchical trees. A parent effect grants all of its children. Children are independent capabilities that can be granted individually.

```pact
effect FS {
    effect Read       // read file contents, list directories
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
    effect Write      // INSERT, UPDATE
    effect Admin      // DDL, DROP, GRANT, schema changes
}

effect IO {
    effect Print      // stdout
    effect Log        // structured logging subsystem
}

effect Env {
    effect Read       // read environment variables
    effect Write      // set environment variables
}

effect Time {
    effect Read       // get current time
    effect Sleep      // sleep / delay execution
}

effect Rand           // generate random numbers (leaf effect, no children)

effect Crypto {
    effect Hash       // hash functions (SHA, BLAKE, etc.)
    effect Sign       // digital signatures
    effect Encrypt    // symmetric/asymmetric encryption
    effect Decrypt    // decryption
}

effect Process {
    effect Spawn      // spawn child processes
    effect Signal     // send signals to processes
}
```

**Granting rules:**

| Declaration | What you can use |
|---|---|
| `! FS.Read` | `fs.read(...)`, `fs.list(...)` -- read-only FS operations |
| `! FS.Read, FS.Write` | Read and write, but not delete or watch |
| `! FS` | All FS operations: read, write, delete, watch |
| `! DB.Read` | Read-only database queries |
| `! DB` | Full database access including admin/DDL |

Declaring a parent is syntactic sugar for declaring all children. `! FS` and `! FS.Read, FS.Write, FS.Delete, FS.Watch` are identical to the compiler. The short form exists for the (rare) functions that genuinely need everything; the long form is what most functions should use.

**Why hierarchical and not flat:**

A flat list of 30+ effects is unusable. Hierarchy provides two things: (1) grouping -- `FS.*` are all filesystem-related, so the handle namespace is coherent; and (2) an escape hatch -- when a function genuinely needs all filesystem operations, `! FS` is one annotation, not four. The hierarchy matches how humans and AI think about capability domains.

---

### 4.4 Effect Handles

Declaring an effect in a function signature brings a **handle** into scope. The handle is the only way to access the effect's operations. There are no free functions for IO, no global `print` -- only `io.print(...)`, available when the function declares `! IO.Print` or `! IO`.

```pact
fn example() ! IO.Print, FS.Read, DB.Read, Net.Connect, Crypto.Hash {
    io.print("Starting...")          // IO.Print handle
    let data = fs.read("input.txt")  // FS.Read handle
    let rows = db.read("SELECT *..") // DB.Read handle — string literal auto-parameterized to Query[DB]
    let resp = net.connect(url)      // Net.Connect handle
    let hash = crypto.hash(data)     // Crypto.Hash handle
}
```

**Handle naming is deterministic:**

| Effect | Handle | Operations |
|---|---|---|
| `IO` / `IO.*` | `io` | `io.print(...)`, `io.log(...)` |
| `FS` / `FS.*` | `fs` | `fs.read(...)`, `fs.write(...)`, `fs.delete(...)`, `fs.watch(...)` |
| `DB` / `DB.*` | `db` | `db.read(...)`, `db.write(...)`, `db.admin(...)` |
| `Net` / `Net.*` | `net` | `net.connect(...)`, `net.listen(...)`, `net.dns(...)` |
| `Env` / `Env.*` | `env` | `env.read(...)`, `env.write(...)` |
| `Time` / `Time.*` | `time` | `time.read()`, `time.sleep(...)` |
| `Rand` | `rand` | `rand.int(...)`, `rand.float(...)`, `rand.bytes(...)` |
| `Crypto` / `Crypto.*` | `crypto` | `crypto.hash(...)`, `crypto.sign(...)`, `crypto.encrypt(...)`, `crypto.decrypt(...)` |
| `Process` / `Process.*` | `process` | `process.spawn(...)`, `process.signal(...)` |

The handle is always the lowercase form of the top-level effect name. Sub-effects do not create separate handles -- they control which *methods* on the handle are available. Declaring `! FS.Read` gives you the `fs` handle, but only `fs.read(...)` and `fs.list(...)` compile. Calling `fs.write(...)` with only `FS.Read` declared is a compile error:

```pact
fn read_only() ! FS.Read {
    let data = fs.read("config.toml")  // OK
    fs.write("config.toml", data)      // COMPILE ERROR
}
```

```
error[InsufficientCapability]: insufficient effect capability
 --> config.pact:3:5
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

---

### 4.5 Effect Composition Rules

Effects propagate upward through the call graph. If function A calls function B, A must declare at least all of B's effects. The compiler enforces this transitively across the entire program.

```pact
fn check_inventory(item_id: Int) -> Int ! DB.Read {
    db.read("SELECT quantity FROM inventory WHERE id = {item_id}")
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
 --> order.pact:9:5
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

```pact
fn do_everything() ! DB {
    check_inventory(42)  // OK: DB >= DB.Read
}
```

But a function declaring a child effect does NOT satisfy a callee requiring the parent:

```pact
fn admin_task() ! DB {
    db.admin("ALTER TABLE ...")
}

fn read_only_caller() ! DB.Read {
    admin_task()  // COMPILE ERROR: DB.Read does not grant DB (which includes DB.Admin)
}
```

**Effect subtyping:**

Effects follow a subtyping relationship: parent > child. A function that requires `! DB.Read` can be called by anything that has `! DB.Read`, `! DB.Read, DB.Write`, or `! DB`. The capability lattice is:

```
DB > DB.Read
DB > DB.Write
DB > DB.Admin
DB.Read + DB.Write + DB.Admin = DB
```

This is standard capability attenuation: you can always pass a more-powerful capability where a less-powerful one is expected, but never the reverse.

---

### 4.6 Effects on `main`

`main` is the root of the capability tree. It implicitly holds all effects:

```pact
// Valid -- main implicitly has all effects
fn main() {
    io.print("Hello, world!")
    let data = fs.read("config.toml")
    let rows = db.read("SELECT * FROM users")
}

// Also valid -- explicit annotation, but unnecessary
fn main() ! IO.Print, FS.Read, DB.Read {
    io.print("Hello, world!")
    let data = fs.read("config.toml")
    let rows = db.read("SELECT * FROM users")
}
```

`main` is where ambient authority lives. It is the **only** place where capabilities are created from nothing. Every other function in the program receives its capabilities from its caller, tracing back to `main`. This is the ocap discipline: authority flows downward through explicit delegation, never materializes from thin air.

The LSP displays `main`'s actual effect set as an inlay hint, computed from the transitive closure of everything `main` calls. If `main` only calls pure functions and one `io.print`, the hint shows `! IO.Print` -- not "all effects." This is documentation, not enforcement.

**Why implicit on `main`:** Requiring `main` to declare effects is pure ceremony. `main` is the program. Its effect set is "whatever the program does." An explicit annotation on `main` would just be a worse version of what the compiler already computes. Every other public function must declare effects explicitly -- `main` is the single exception.

---

### 4.7 Effect Handlers

Effect handlers replace the implementation behind effect handles. They are the mechanism for dependency injection, testing, sandboxing, and capability attenuation.

#### Basic handler syntax

```pact
with handler_expression {
    // code in this block uses the replaced implementation
}
```

#### Testing: mock handlers

The most common use case. Replace real effects with test doubles:

```pact
fn process_order(id: Int) -> Result[Receipt, OrderError] ! DB.Read, DB.Write, IO.Log {
    let order = db.read("SELECT * FROM orders WHERE id = {id}")?
    io.log("Processing order {id}")
    let receipt = Receipt { order_id: id, total: order.total }
    db.write("INSERT INTO receipts ...", receipt)?
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
    assert(log_messages[0].contains("Processing order 42"))
}
```

The code under test calls `db.read(...)` and `io.log(...)` as normal. The handler intercepts these calls and routes them to the mock implementation. The function being tested does not know or care -- it interacts with the same handle interface either way.

#### Dependency injection: swapping backends

Handlers replace traditional DI containers:

```pact
fn run_with_postgres(config: DBConfig) ! DB, IO.Log {
    with postgres_handler(config) {
        start_server()  // all DB operations inside route to Postgres
    }
}

fn run_with_sqlite(path: Str) ! DB, IO.Log {
    with sqlite_handler(path) {
        start_server()  // same code, SQLite backend
    }
}

fn main() {
    let config = load_config()
    match config.db_backend {
        "postgres" => run_with_postgres(config.pg_config)
        "sqlite" => run_with_sqlite(config.sqlite_path)
    }
}
```

No interfaces, no factory patterns, no service locators. The handler is the injection point. The code inside the `with` block is agnostic to the concrete implementation.

#### Sandboxing: restricting capabilities

Handlers can provide a restricted implementation that narrows what the inner code can do:

```pact
fn run_plugin(plugin: Plugin) ! Net.Connect, FS.Read, IO.Log {
    let allowed_hosts = ["api.example.com", "cdn.example.com"]

    with restricted_net(allowed_hosts), readonly_fs("/plugins/data/") {
        plugin.execute()
    }
}
```

Inside the `with` block, `net.connect(url)` checks the URL against the allowlist and returns an error for disallowed hosts. `fs.read(path)` is scoped to `/plugins/data/` -- attempts to read outside that directory fail. The plugin code declares `! Net.Connect, FS.Read` and has no idea it is sandboxed.

#### Defining a handler

Handlers implement the operations for an effect:

```pact
fn mock_db(data: List[Row]) -> Handler[DB] {
    handler DB {
        fn read(query: Query[DB]) -> Result[List[Row], DBError] {
            // query.template = "SELECT ...", query.params = [...]
            Ok(data.filter(fn(row) { matches_query(row, query) }))
        }

        fn write(query: Query[DB]) -> Result[(), DBError] {
            // No-op for tests, or append to a log
            Ok(())
        }

        fn admin(query: Query[DB]) -> Result[(), DBError] {
            Err(DBError.PermissionDenied("admin operations disabled in mock"))
        }
    }
}
```

A handler must implement all operations for the effect it covers (or explicitly delegate unhandled operations to the outer handler). The compiler checks completeness -- you cannot create a `Handler[DB]` that forgets to implement `admin`.

#### Handler composition

Multiple handlers compose with `,`:

```pact
with handler_a, handler_b, handler_c {
    // handler_a covers its effects
    // handler_b covers different effects
    // handler_c covers yet others
    do_work()
}
```

If two handlers cover the same effect, the leftmost wins (innermost-scope semantics). This is deterministic and predictable.

#### Handlers are values

Handlers are first-class values. They can be stored in variables, passed as arguments, and returned from functions:

```pact
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

The `with...as` construct handles this second tier:

```pact
fn copy_file(src_path: Str, dst_path: Str) -> Result[(), IOError] ! FS {
    with fs.open(src_path)? as src, fs.create(dst_path)? as dst {
        let data = fs.read(src)?
        fs.write(dst, data)?
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

```pact
fn export_data(query: Str, path: Str) -> Result[(), AppError] ! DB.Read, FS {
    with fs.create(path)? as out {
        let rows = db.query(query)?
        for row in rows {
            fs.write(out, row.to_csv())?
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

The outer `with mock_db(fixtures), temp_fs()` installs effect handlers (no `as`). The inner `with fs.create(...)? as f` is a scoped resource (`as` present). The compiler distinguishes them by the presence of `as`.

#### Disambiguation rules

| Syntax | `as` present? | Type check | Meaning |
|--------|--------------|------------|---------|
| `with expr { }` | No | `expr: Handler[E]` | Effect handler |
| `with expr as name { }` | Yes | `expr: T where T: Closeable` | Scoped resource |

Both can appear in the same comma-separated `with`:

```pact
with mock_db(fixtures), fs.open("x.txt")? as f {
    // mock_db provides DB handler, f is a Closeable file handle
}
```

#### Interaction with structured concurrency

Scoped resources respect structured concurrency boundaries. A `Closeable` bound in a `with...as` cannot be sent to a spawned task (it would escape the scope):

```pact
fn bad_example() ! FS, Async {
    with fs.open("data.txt")? as file {
        async.spawn(fn() {
            fs.read(file)  // COMPILE ERROR E0601: closeable `file` escapes scope
        })
    }
}
```

If concurrent tasks need the resource, open it outside or pass the data:

```pact
fn good_example() ! FS, Async {
    let data = with fs.open("data.txt")? as file {
        fs.read(file)?
    }
    async.scope {
        async.spawn(fn() { process(data) })
    }
}
```

---

### 4.7.1 Handler Type System

`Handler[E]` is a compiler-known generic type parameterized by an effect. It is the type of values produced by `handler E { ... }` expressions. At the source level, `Handler[E]` is a single type constructor; at the C level, each `Handler[E]` compiles to an effect-specific vtable struct managed by the GC.

#### Type identity

`Handler[E]` is parameterized by a concrete effect. `Handler[DB]`, `Handler[IO]`, and `Handler[Net.Connect]` are distinct types. The type parameter must be a declared effect — `Handler[Int]` is a compile error:

```
error[InvalidHandlerTypeParam]: invalid handler type parameter
 --> app.pact:3:10
  |
3 | let h: Handler[Int] = ...
  |                ^^^ `Int` is not an effect
  |
  = note: Handler[E] requires E to be a declared effect
```

#### First-class values

Handlers are full first-class values. They can be stored in variables, struct fields, collections, closures, passed as arguments, and returned from functions:

```pact
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
        fn read(query: Query[DB]) -> Result[List[Row], DBError] {
            run_query(config.connection, query)
        }
        fn write(query: Query[DB]) -> Result[(), DBError] {
            run_mutation(config.connection, query)
        }
        fn admin(query: Query[DB]) -> Result[(), DBError] {
            if config.allow_admin {
                run_admin(config.connection, query)
            } else {
                Err(DBError.PermissionDenied("admin disabled"))
            }
        }
    }
}

// Pass as function argument
fn run_with(h: Handler[DB]) ! DB {
    with h {
        do_work()
    }
}
```

At the C level, handler values are GC-managed copies of the vtable struct. Storing a handler copies the struct (function pointers + captured state); the GC tracks the copy. This means handlers are safe to store beyond the scope that created them — no dangling references.

#### Effect projection

A `Handler[E]` where `E` is a parent effect can be used where a `Handler[E.Sub]` is expected. The compiler automatically projects the relevant vtable slots:

```pact
fn read_only_test(h: Handler[DB.Read]) ! DB.Read {
    with h {
        let rows = db.read("SELECT * FROM users")
    }
}

let full: Handler[DB] = mock_db(data)
read_only_test(full)  // OK: compiler projects DB → DB.Read
```

This is not subtyping — the compiler extracts the relevant operation slots from the parent handler's vtable and constructs a projected handler. The projection is implicit at the call site but explicit in the generated code.

Projection only works in one direction. A `Handler[DB.Read]` cannot be used where `Handler[DB]` is expected — the handler is missing `write` and `admin` operations:

```
error[InsufficientHandlerCoverage]: insufficient handler coverage
 --> test.pact:5:15
  |
5 | run_full(read_handler)
  |          ^^^^^^^^^^^^ expected `Handler[DB]`, found `Handler[DB.Read]`
  |
  = note: `Handler[DB]` requires operations: read, write, admin
  = note: `Handler[DB.Read]` only provides: read
```

#### Completeness and auto-delegation

Handlers may be **partial** — omitted operations automatically delegate to the dynamically enclosing handler. The compiler generates `default.op(args)` forwarding for each unimplemented operation:

```pact
fn logging_db(label: Str) -> Handler[DB] {
    handler DB {
        fn read(query: Query[DB]) -> Result[List[Row], DBError] {
            io.log("{label}: read {query}")
            default.read(query)  // explicit delegation
        }
        // write and admin omitted — auto-delegate to enclosing handler
    }
}
```

The compiler desugars the above as if `write` and `admin` were defined with `default.write(query)` and `default.admin(query)` respectively. Explicit `default.op(args)` remains available for custom delegation logic (e.g., logging before forwarding, as shown for `read` above).

Auto-delegation means a `Handler[DB]` that only overrides `read` is still a complete `Handler[DB]` — the type system does not distinguish partial from total handlers. At runtime, unhandled operations bubble up to the nearest enclosing handler that implements them.

#### Generic handler parameters

In v1, handler type parameters must be concrete effects: `Handler[DB]`, `Handler[IO]`, `Handler[Net.Connect]`. Effect-kinded generic parameters (e.g., `fn foo[E: Effect](h: Handler[E])`) are deferred to v2, alongside named effect variables.

#### Compilation model

Each `Handler[E]` compiles to a C struct containing one function pointer per operation in effect `E`, plus a `void*` for captured closure state:

```c
// Generated for Handler[DB] (conceptual)
typedef struct {
    pact_result (*read)(void* state, pact_query query);
    pact_result (*write)(void* state, pact_query query);
    pact_result (*admin)(void* state, pact_query query);
    void* state;  // captured environment (GC-managed)
} pact_handler_DB;
```

Handler values are heap-allocated via the GC. Storing a handler in a struct field or list copies the struct (function pointers are plain pointers; `state` is a GC root). The evidence-passing model (§4.5, Codegen Backend in DECISIONS.md) installs handler vtables into the evidence vector when entering a `with` block.

Effect projection (`Handler[DB]` → `Handler[DB.Read]`) generates a new struct containing only the relevant function pointer slots, populated from the source handler.

---

### 4.8 Module Capability Budgets

Modules can declare a hard ceiling on the effects any function inside them may use:

```pact
@capabilities(DB.Read, DB.Write)
module inventory

fn check_stock(item_id: Int) -> Int ! DB.Read {
    db.read("SELECT quantity FROM inventory WHERE id = {item_id}")
}

fn update_stock(item_id: Int, delta: Int) ! DB.Write {
    db.write("UPDATE inventory SET quantity = quantity + {delta} WHERE id = {item_id}")
}

fn drop_table() ! DB.Admin {
    db.admin("DROP TABLE inventory")
    // COMPILE ERROR: module `inventory` does not have capability `DB.Admin`
}
```

```
error[CapabilityBudgetExceeded]: capability budget exceeded
 --> inventory.pact:12:5
  |
12|     db.admin("DROP TABLE inventory")
  |     ^^^^^^^^ requires `DB.Admin`
  |
  = note: module `inventory` declares capabilities `DB.Read, DB.Write`
  = note: `DB.Admin` is not within the module's capability budget
```

**Why module budgets:**

Module budgets are a defense against both mistakes and malice. A module responsible for inventory should never perform network calls, spawn processes, or administer the database schema. The budget makes this constraint explicit and compiler-enforced. When an AI generates code in this module, the compiler immediately rejects anything that exceeds the budget -- no human review needed to catch a misplaced `db.admin(...)` call.

Module budgets are also the **audit surface** for security review. Instead of reviewing every function in a module, a reviewer checks the `@capabilities` declaration. If the budget is `DB.Read, DB.Write`, the reviewer knows -- with compiler-level certainty -- that nothing in this module touches the network, filesystem, process table, or database schema.

---

### 4.9 Package Capability Declarations

Every published package declares its maximum capabilities in its manifest file:

```toml
# pact.toml
[package]
name = "std/http-client"
version = "2.1.0"

[capabilities]
required = ["Net.Connect", "Net.DNS"]
optional = ["IO.Log"]  # only used if caller provides logging handler
```

Capabilities flow through the dependency graph and are recorded in the lockfile:

```toml
# pact.lock (auto-generated, checked into version control)

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

`pact update` refuses to auto-accept capability escalations:

```
warning: capability escalation detected

  std/http-client 2.1.0 -> 2.2.0
    + FS.Write (NEW)

  This package previously had no filesystem access.
  Run `pact update --accept-escalation std/http-client` to approve.
```

This is the supply-chain security story. A JSON parser declaring `capabilities = []` that suddenly requests `Net.Connect` in a patch release is immediately visible. The lockfile is the audit trail. CI can enforce `pact audit --no-escalation` to block builds where capability budgets have grown without explicit approval.

**Why package-level capabilities:**

In current ecosystems, `npm install` grants a package the full authority of the running process. A compromised leftpad can exfiltrate environment variables, phone home, or overwrite files. Pact's package capabilities mean a package declaring `capabilities = []` (pure computation) is **provably** unable to perform IO, regardless of what malicious code its author injected. The compiler will not compile a function with effects that exceed its package's declared capabilities.

---

### 4.10 Capability Attenuation

Capabilities can be narrowed but never widened. A handler that receives `Net.Connect` can restrict it to a subset of allowed behaviors:

```pact
fn restricted_net(allowed_hosts: List[Str]) -> Handler[Net.Connect] {
    handler Net.Connect {
        fn connect(url: Url) -> Result[Response, NetError] {
            if allowed_hosts.contains(url.host) {
                default.connect(url)  // delegate to the outer handler
            } else {
                Err(NetError.Forbidden("host {url.host} not in allowlist"))
            }
        }
    }
}

fn run_third_party_code() ! Net.Connect, IO.Log {
    with restricted_net(["api.trusted.com"]) {
        // Inside this block, net.connect("https://api.trusted.com/data") works
        // But net.connect("https://evil.com/exfiltrate") returns Err
        third_party_library.fetch_data()
    }
}
```

Attenuation follows the principle of least privilege. When calling untrusted or semi-trusted code, wrap it in a handler that narrows the capabilities to exactly what it needs:

```pact
fn sandbox_plugin(plugin: Plugin) ! FS.Read, Net.Connect, IO.Log, Time.Read {
    let fs_scope = scoped_fs("/var/plugins/{plugin.id}/data/")
    let net_allow = restricted_net(plugin.manifest.allowed_hosts)
    let time_frozen = frozen_time(Time.of(2026, 1, 1))  // deterministic time for reproducibility

    with fs_scope, net_allow, time_frozen {
        plugin.run()
    }
}
```

The plugin receives handles that look identical to unrestricted ones. It calls `fs.read(...)`, `net.connect(...)`, `time.read()` through the same interface. It has no mechanism to detect or bypass the attenuation. This is the ocap principle: capabilities are unforgeable and can only be attenuated, never amplified.

**Attenuation is compositional:**

```pact
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

| Traditional Feature | Pact Replacement | How |
|---|---|---|
| `try`/`catch`/exceptions | `Result[T, E]` + `?` | Errors are values. No invisible control flow. Effect system is orthogonal to error handling. |
| `async`/`await` | `! Async` effect | Concurrency is an effect. Functions that suspend declare it. Handlers provide the runtime (tokio-like, goroutine-like, etc.). |
| Dependency injection | Effect handlers | `with postgres_handler(config) { ... }` replaces constructor injection, service locators, DI containers. |
| Mocking / test doubles | Test handlers | `with mock_db(fixtures) { ... }` replaces mockito, unittest.mock, testdouble. |
| IO monads (Haskell) | `! IO.*` effects | Same purity tracking without monadic syntax (`>>=`, `do` notation). Effects compose with `,`, not monad transformers. |
| `synchronized` / locks | `! Sync` effect (future) | Shared mutable state as an explicit effect, not an invisible side channel. |
| Sandbox / permissions | Capability attenuation | `with restricted_net(allowlist) { ... }` replaces OS-level sandboxing, seccomp, AppArmor for application-level policy. |
| Feature flags | Handler selection | `with feature_handler(flags) { ... }` routes effect operations based on runtime configuration. |

The critical insight: these are not different features. They are all manifestations of the same underlying mechanism -- controlling what code is *allowed to do*. The effect system unifies them into a single, compositional, compiler-verified framework.

---

### 4.12 User-Defined Effects

The built-in effects cover standard IO categories, but real applications have domain-specific side effects. Pact allows user-defined effects with the same declaration syntax:

```pact
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

```pact
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

```pact
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

**Standard library handlers:**

The standard library ships default handlers for built-in effects (real filesystem, real network, real database drivers). User-defined effects have no default handler -- you must provide one. This is intentional: the compiler forces you to explicitly wire up your domain effects, making the architecture visible.

```pact
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

Concurrency in Pact is not a language keyword or a function color — it is an effect. The `Async` effect declares that a function may suspend, spawn concurrent tasks, or interact with the runtime scheduler. This means concurrency follows all the same rules as every other effect: declared in signatures, propagated through call graphs, swappable via handlers, constrained by module budgets.

**Core primitives:**

| Primitive | Purpose |
|-----------|---------|
| `async.scope { ... }` | Structured concurrency boundary. All spawned tasks must complete before the scope exits. |
| `async.spawn(fn() { ... })` | Launch a concurrent task within the current scope. Returns `Handle[T]`. |
| `handle.await` | Wait for a spawned task's result. Method on `Handle[T]`, returns `T`. |
| `channel.new[T](buffer: N)` | Create a buffered channel for inter-task communication. |

**The dashboard pattern — fork-join concurrency:**

```pact
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

`async.spawn` returns a `Handle[T]` — an opaque value representing a running task. `handle.await` is a method on `Handle[T]` that suspends the current task until the spawned task completes and returns its result. The compiler recognizes `.await` as a suspension point and requires `! Async` in the function's effect declaration.

**Why `handle.await` and not `async.join(handle)`:**

Pact uses namespaced functions for *creating* concurrent primitives (`async.scope`, `async.spawn`, `channel.new`) but method syntax for *consuming* results (`handle.await`). This follows the data flow: the handle is the thing you're waiting on, so the operation belongs to the handle. It also chains naturally with error propagation:

```pact
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

```pact
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

**Effects on `main` — implicit `Async`:**

`main` has implicit effects (see section 4.6), which includes `Async`. This means `main` can use `async.scope` directly without declaring `! Async`:

```pact
fn main() {
    async.scope {
        let result = async.spawn(fn() { fetch_data() })
        io.println(result.await)
    }
}
```

The runtime (green thread scheduler, M:N threading) is wired implicitly. Every other function that suspends must declare `! Async` explicitly.

**Panel vote: 5-0** for `handle.await`. See [OPEN_QUESTIONS.md](../OPEN_QUESTIONS.md).

---

### 4.14 Full Example: Effect System in Practice

Putting it all together -- a small order processing service demonstrating hierarchical effects, handlers, module budgets, and testing:

```pact
@capabilities(DB.Read, DB.Write, Payment.Charge, IO.Log)
module orders

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
        let stock = db.read("SELECT quantity FROM inventory WHERE id = {item.id}")?
        if stock < item.quantity {
            return Err(OrderError.InsufficientStock(item.id, stock))
        }
    }
    Ok(())
}

fn reserve_stock(order: Order) ! DB.Write {
    for item in order.items {
        db.write("UPDATE inventory SET quantity = quantity - {item.quantity} WHERE id = {item.id}")
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
        fn read(query: Query[DB]) -> Result[Any, DBError] {
            // query.template and query.params available for matching
            let item_id = parse_item_id(query)
            match stock.get(item_id) {
                Some(qty) => Ok(qty)
                None => Err(DBError.NotFound)
            }
        }
        fn write(query: Query[DB]) -> Result[(), DBError] { Ok(()) }
        fn admin(query: Query[DB]) -> Result[(), DBError] {
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
2. **`check_inventory` is read-only.** `! DB.Read`. It cannot modify stock, cannot charge payment. If someone adds a `db.write(...)` call, the compiler rejects it.
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

```pact
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
    let rows = db.read("SELECT * FROM data")
    rows.map(fn(r) { f(r) }).collect()
}
```

The effect annotation on a function type is part of the type identity. `fn(Int) -> Int` and `fn(Int) -> Int ! IO` are different types — the compiler rejects passing an effectful callback where a pure one is expected:

```
error[EffectMismatchInFnType]: effect mismatch in function type
 --> app.pact:5:12
  |
5 |     apply(logger, 42)
  |           ^^^^^^ expected pure `fn(Int) -> Int`, found `fn(Int) -> Int ! IO.Log`
  |
  = note: `apply` requires a pure callback
  = fix: use a HOF that accepts effectful callbacks, or remove effects from the callback
```

The reverse is safe: a pure callback satisfies an effectful parameter (pure is a subtype of effectful — a function that *can* do IO doesn't *have to*):

```pact
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

```pact
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

The wildcard `_` means: "whatever effects the callback has, this function has too." At call sites, the compiler resolves `_` to the concrete effects of the callback passed:

```pact
fn process_items(items: List[Item]) ! DB.Read, IO.Log {
    items.iter()
        .filter(fn(item) { item.is_active() })          // pure callback: _ = (nothing)
        .map(fn(item) {
            let price = db.read("SELECT ...")?           // _ = DB.Read
            io.log("Processing {item.id}")               // _ = IO.Log
            item.with_price(price)
        })
        .for_each(fn(item) {
            io.log("Done: {item.id}")                    // _ = IO.Log
        })
}
```

**Multiple wildcard parameters:** When a function takes multiple effectful callbacks, their effects are unioned:

```pact
fn zip_with[A, B, C](
    iter_a: Iterator[A],
    iter_b: Iterator[B],
    f: fn(A, B) -> C ! _
) -> Iterator[C] ! _ {
    // _ in return position = union of all _ parameters
}
```

**Wildcard with explicit effects:** A function may have both its own effects and forwarded callback effects:

```pact
fn logged_map[U](self, label: Str, f: fn(T) -> U ! _) -> Iterator[U] ! IO.Log, _ {
    io.log("Starting {label}")
    self.map(f)
}
```

Here `! IO.Log, _` means: this function always requires `IO.Log` (for its own logging), plus whatever the callback needs.

#### 4.15.3 Compilation

Effect polymorphism compiles via the existing evidence-passing model (§4.2, Codegen Backend in DECISIONS.md):

- **Concrete effect function types** (`fn(T) -> U ! IO.Log`): The callback receives the caller's evidence vector. The compiler verifies the caller holds the required effect slots at the call site. Zero additional overhead — same as any effectful function call.

- **Wildcard forwarding** (`! _`): The compiler resolves `_` at each call site to the concrete effects of the callback argument. The HOF is monomorphized per distinct effect set (same as generic type parameters). At the C level, the evidence vector is threaded through — no new mechanism, just one more monomorphization axis.

- **Pure callbacks in wildcard positions**: When a pure callback is passed to a `! _` function, `_` resolves to the empty effect set. The function becomes pure at that call site. The evidence vector threading is elided entirely.

#### 4.15.4 Interaction with Existing Features

**Effect composition (§4.5):** Wildcard effects compose with explicit effects following the same propagation rules. A caller must declare at least all effects that resolve through `_`:

```pact
fn caller() ! DB.Read {
    items.map(fn(x) { db.read("...") })  // OK: _ resolves to DB.Read, caller has it
}

fn bad_caller() {
    items.map(fn(x) { db.read("...") })  // ERROR E0500: missing DB.Read
}
```

**Handlers (§4.7):** Handlers can intercept effects that flow through wildcards:

```pact
test "map with mock DB" {
    with mock_db() {
        let results = items.map(fn(x) { db.read("...") })
        // handler intercepts DB.Read flowing through map's _
    }
}
```

**Closures (§2.8):** Closures used as effectful callbacks follow the same capture rules. Effect annotations on the closure type describe what the closure *body* does, not what it captures.

**async.spawn (§4.13):** `async.spawn` takes `fn() -> T ! _` — the spawned task inherits whatever effects the closure declares. The existing E0650 restriction on `let mut` captures still applies.

#### 4.15.5 What Is Deferred to v2

**Named effect variables (row polymorphism):** v1 uses `_` which covers the common case of "forward all callback effects." v2 may introduce named effect variables for advanced use cases:

```pact
// v2 potential syntax — NOT v1
fn map[T, U, e](f: fn(T) -> U ! e) -> Iterator[U] ! e
fn zip_with[A, B, C, e1, e2](f: fn(A) -> B ! e1, g: fn(B) -> C ! e2) -> Iterator[C] ! e1, e2
```

Named variables enable: distinguishing effect sets from different callbacks, constraining effects (e.g., "callback may do IO but not DB"), and composing effect sets algebraically. The `_` wildcard is forward-compatible — it can desugar to an anonymous effect variable when named variables are added.

**Effectful iteration:** The 3-2 vote deferring effectful iteration to v2 remains in effect. However, with `! _` on Iterator adapter signatures, effectful callbacks in `map`, `filter`, `fold`, and `for_each` become expressible once the Iterator trait is updated to carry wildcards. This update is a v2 change gated on real-world feedback.
