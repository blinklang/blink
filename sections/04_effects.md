## 4. Effect System

### 4.1 Thesis: Effects Are Capabilities Are Security

Blink's effect system is not a type annotation convenience. It is the security architecture of the language.

Every side effect a function can perform -- printing, reading a database, opening a socket, spawning a process -- is a **capability** that must be explicitly declared in the function's signature and granted by its caller. This is the object-capability model (ocap), as pioneered by Mark Miller's E language, applied at the type level: no ambient authority, no implicit permissions, no action-at-a-distance.

The consequences are structural:

- A function with no `!` in its signature **cannot** perform side effects. The compiler proves it. (It may still read or write module-level `let mut` bindings, which are tracked separately by mutation analysis — see §4.16.)
- A function declaring `! DB.Read` can query a database but **cannot** write to it, delete from it, or administer it. The compiler proves it.
- A package declaring `capabilities(Net.Connect)` in its manifest **cannot** open a listening socket. The compiler proves it.
- An effect handler can attenuate capabilities -- handing a function a `Net.Connect` that only permits connections to a specific allowlist. The runtime enforces it.

There is no separate "permissions" system, no runtime ACLs, no sandbox configuration files. The effect system **is** all of these things. Capabilities are tracked through the type system, enforced by the compiler, and attenuated through handlers. Zero runtime cost for the checks themselves -- if your code compiles, the capability discipline is guaranteed.

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
    let order = db.query_one("SELECT * FROM orders WHERE id = {id}")?
    io.log("Processing order {id}")
    let receipt = Receipt { order_id: id, total: order.total }
    db.execute("INSERT INTO receipts ...")?
    Ok(receipt)
}

// Parent effect grants all children
fn dangerous_migration() ! DB {
    // DB grants DB.Read and DB.Write -- the whole tree
    db.exec("DROP TABLE legacy_data")?
    db.exec("INSERT INTO migrations ...")?
    db.query("SELECT count(*) FROM migrations")?
}
```

The `!` was chosen by 3-2 vote over `/`. It universally signals danger or impurity (`!` in Scheme for mutation, Rust for macros, Swift for throwing). It is a single character -- maximally token-efficient. It is visually distinctive in a signature. It does not collide with any operator in expression position.

**The explicit empty row `! ()`.** `! ()` is the empty effect row written out. It means "no effects", the same as an omitted row; it is not a return type. Its one use is on an `@ffi` decl, where the row is a claim the author must write and a missing row is an error (§9.1). On any other function, fn type or trait method signature, the compiler already proves purity, so `! ()` is an error there. The grammar admits `()` after `!` everywhere; a check after parsing rejects it outside an `@ffi` decl. Both spellings denote the same row, so `c_strlen` still checks against `fn(Ptr[U8]) -> Int`.

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
    effect Write      // INSERT, UPDATE, DELETE, CREATE, DROP, ALTER — all mutations
}

effect IO {
    effect Print      // stdout
    effect Log        // structured logging subsystem
}

effect Env {
    effect Read       // read environment variables
    effect Write      // set environment variables
    effect Exit       // terminate the process
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
| `! FS.Read` | `fs.read(...)`, `fs.list_dir(...)` -- read-only FS operations |
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

A flat list of 30+ effects is unusable. Hierarchy provides two things: (1) grouping -- `FS.*` are all filesystem-related, so the handle namespace is coherent; and (2) an escape hatch -- when a function genuinely needs all filesystem operations, `! FS` is one annotation, not four. The hierarchy matches how humans and AI think about capability domains.

---

### 4.4 Effect Handles

Declaring an effect in a function signature brings a **handle** into scope. The handle is the only way to access the effect's operations. There are no free functions for IO, no global `print` -- only `io.print(...)`, available when the function declares `! IO.Print` or `! IO`.

```blink
fn example() ! IO.Print, FS.Read, DB.Read, Net.Connect, Crypto.Hash {
    io.print("Starting...")          // IO.Print handle (no newline)
    io.println("Done!")              // IO.Print handle (with newline)
    let data = fs.read("input.txt")? // FS.Read handle
    let rows = db.query("SELECT *..")? // DB.Read handle — string literal auto-parameterized to Template[DB]
    let resp = net.get(url)?          // Net.Connect handle
    let hash = crypto.hash(data)     // Crypto.Hash handle
}
```

**IO operations by dispatch mode:**

| Operation | Argument | Behavior | Vtable-dispatched | Handler-interceptable | Trace |
|---|---|---|---|---|---|
| `io.print(x)` | `T: Display` | stdout, no newline | Yes (`IO.Print`) | Yes | Yes |
| `io.println(x)` | `T: Display` | stdout, with newline | Yes (`IO.Print`) | Yes | Yes |
| `io.log(x)` | `T: Display` | stderr, `[LOG]` prefix + newline | Yes (`IO.Log`) | Yes | Yes |
| `io.eprintln(x)` | `T: Display` | stderr, with newline | No | No | Yes |
| `io.eprint(x)` | `T: Display` | stderr, no newline | No | No | Yes |
| `io.print_raw(s)` | `Str` | raw stdout, no newline | No | No | No |
| `io.eprint_raw(s)` | `Str` | raw stderr, no newline | No | No | No |

The `_raw` variants are escape hatches for cases where direct C output is needed (e.g., streaming JSON fragments, progress indicators). They bypass the effect handler system entirely and emit no trace effects. Prefer `io.print`/`io.println` for application code; reserve `_raw` for low-level tooling.

**Argument types.** Each non-`_raw` operation takes any `Display` value, as `sb.write` and `"{x}"` do (§3.6 *Display Format Protocol*). So `io.println(42)`, `io.println(p)` and `io.println("n = {n}")` all compile, and a value with no `Display` impl is `error[E0523]` at the argument. The `_raw` operations take `Str` only. The split follows the `_raw` name, not the dispatch mode: `io.eprint` is not interceptable and still takes `Display`. A non-`Str` argument to a `_raw` operation is a type mismatch:

```
error[TypeError]: mismatched types
 --> progress.bl:4:18
  |
4 |     io.print_raw(done)
  |                  ^^^^ expected `Str`, found `Int`
  |
  = help: render it first: `io.print_raw("{done}")`
```

**Handler operations take `Str`.** The generic surface is a stdlib wrapper, not a generic effect operation. `io.println(x)` renders `x` via `x.display()`, then performs the handler operation with the result; `io.print` and `io.log` do the same. `io.eprint` and `io.eprintln` render the same way, then write the `Str` to stderr. The handler operations are:

| Effect | Operation | Called by |
|---|---|---|
| `IO.Print` | `fn print(msg: Str)` | `io.println(x)`; the default handler writes `msg` and a newline |
| `IO.Print` | `fn print_no_nl(msg: Str)` | `io.print(x)` |
| `IO.Log` | `fn log(msg: Str)` | `io.log(x)` |

The wrapper selects the operation; it does not add the newline to `msg`. A handler therefore sees the same `msg` for `io.println(42)` and `io.println("42")`: the text `42`, with no newline. (Implementation note: for a `Str` argument, `display()` returns the receiver, so the wrapper passes it on without a copy; §3.6.)

**Handle naming is deterministic:**

| Effect | Handle | Operations |
|---|---|---|
| `IO` / `IO.*` | `io` | `io.print(...)`, `io.println(...)`, `io.log(...)`, `io.eprintln(...)`, `io.eprint(...)`, `io.print_raw(...)`, `io.eprint_raw(...)` |
| `FS` / `FS.*` | `fs` | `fs.read(...)`, `fs.write(...)`, `fs.delete(...)`, `fs.watch(...)` |
| `DB` / `DB.*` | `db` | `db.query(...)`, `db.query_one(...)`, `db.exec(...)`, `db.execute(...)`, `db.prepare(...)`, `db.begin()`, `db.commit()`, `db.rollback()` |
| `Net` / `Net.*` | `net` | `net.request(...)`, `net.get(...)`, `net.post(...)`, `net.listen(...)`, `net.dns(...)` |
| `Env` / `Env.*` | `env` | `env.args()`, `env.var(...)`, `env.vars()`, `env.cwd()`, `env.set_var(...)`, `env.remove_var(...)`, `env.exit(...)` |
| `Time` / `Time.*` | `time` | `time.read() -> Instant`, `time.sleep(Duration)` |
| `Rand` | `rand` | `rand.int(...)`, `rand.float(...)`, `rand.bytes(...)` |
| `Crypto` / `Crypto.*` | `crypto` | `crypto.hash(...)`, `crypto.sign(...)`, `crypto.encrypt(...)`, `crypto.decrypt(...)` |
| `Process` / `Process.*` | `process` | `process.spawn(...)`, `process.signal(...)` |

The handle is always the lowercase form of the top-level effect name. Sub-effects do not create separate handles -- they control which *methods* on the handle are available. Declaring `! FS.Read` gives you the `fs` handle, but only `fs.read(...)` and `fs.list_dir(...)` compile. Calling `fs.write(...)` with only `FS.Read` declared is a compile error:

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

**Handler implementors implement `request()` only.** The verb methods are default implementations that construct a `Request` and delegate. A handler overriding `get` directly (e.g., for caching GET responses) can do so — partial handlers auto-delegate unimplemented operations.

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

`Request.new()` is compiler-provided (same pattern as `List.new()`, `Map.new()`). Builder methods are provided via the `RequestOps` trait:

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
    Response { status: 200, body } => process(body)
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

The `Net.Listen` effect provides HTTP server capabilities. Like `Net.Connect`, it has one core operation (`serve`) with convenience methods for route registration:

```blink
effect Net {
    effect Listen {
        fn serve(server: Server) -> Result[(), ServerError]

        // Route registration — builds the Server value
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
    server.serve()
}
```

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
    let id = req.param("id").parse_int() ?? return Response.bad_request("Invalid ID")
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

**Why functional wrapping over effect handler stacking (4-1 vote):** `fn(handler) -> handler` compiles to direct function pointer composition in C — the wrapping chain collapses at server startup, not per-request. Effect handler stacking would require per-request vtable traversal through nested `with` blocks. Functional composition is also the most universal middleware pattern across web frameworks (Express, Rack, WSGI, Go), giving LLMs strong training signal for correct code generation.

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

The default error handler returns a plain-text 500 response. Handler panics are caught by the server runtime (no `setjmp`/`longjmp` — the server event loop wraps each handler invocation in a safe call boundary).

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
        server.serve()
    }
}
```

The validation effect works outside HTTP contexts too — CLI argument validation, batch processing, message consumers. See §9.2 for full system boundary detection rules.

**Mock validation in tests:**

```blink
test "validation collects violations" {
    let violations = List.new()
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

Handler implementors implement `serve()` — the core operation. Route registration methods build the `Server` value; the handler receives the fully-configured server:

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

The `Env` effect provides access to the process environment: command-line arguments, environment variables, working directory, and process exit. Operations are split between `Env.Read` (observation), `Env.Write` (mutation) and `Env.Exit` (process termination).

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
| `! Env.Read` | `env.args()`, `env.var(...)`, `env.vars()`, `env.cwd()` |
| `! Env.Write` | `env.set_var(...)`, `env.remove_var(...)` |
| `! Env.Exit` | `env.exit(...)` |
| `! Env` | All of the above |

`env.exit()` requires `! Env.Exit` (granted by `! Env`) because it is neither pure observation nor environment mutation — it is process termination. A function declaring only `! Env.Read` or `! Env.Write` cannot call `env.exit()`. A CLI entry point that only reads arguments and exits can declare `! Env.Read, Env.Exit` and leave out `Env.Write`:

```blink
fn load_config() -> Config ! Env.Read {
    let db = env.var("DATABASE_URL") ?? panic("DATABASE_URL not set")
    let port = env.var("PORT") ?? "8080"
    Config { db_url: db, port: port.parse_int() ?? 8080 }
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

```blink
test "CLI exits with 1 on missing args" {
    let mut exit_code = -1
    let mock = handler Env {
        fn args() -> List[Str] { ["mytool"] }
        fn var(name: Str) -> Option[Str] { None }
        fn vars() -> Map[Str, Str] { Map.new() }
        fn cwd() -> Str { "/tmp" }
        fn set_var(name: Str, value: Str) { }
        fn remove_var(name: Str) { }
        fn exit(code: Int) -> Never {
            exit_code = code
            abort
        }
    }
    with mock, capture_log([]) {
        run_cli()
    }
    assert_eq(exit_code, 1)
}
```

The mock lists all seven operations at one level. A handler for an effect with children gives every operation of the tree, whichever child declares it (§4.12 *Leaf effects and effect trees*).

**`env.vars()` returns a snapshot:** The returned `Map[Str, Str]` is a copy of the environment at the time of the call. Subsequent `env.set_var()` or `env.remove_var()` calls do not affect previously returned maps. This ensures deterministic behavior in concurrent code.

**Thread safety:** `env.set_var()` and `env.remove_var()` are process-global mutations. The runtime serializes these calls (mutex-protected `setenv`/`unsetenv`). In concurrent programs using `! Async`, only one task can modify the environment at a time. Use sparingly — prefer configuration structs over environment mutation.

---

#### 4.4.4 DB.Write Scoped Transaction

`db.transaction` implements the `BlockHandler` trait (see §4.6.3), providing automatic `BEGIN`/`COMMIT`/`ROLLBACK` semantics via `with`. It requires the `DB.Write` effect.

```blink
fn transfer(from_id: Int, to_id: Int, amount: Int) -> Result[(), DBError] ! DB.Write {
    with db.transaction() {
        let from = db.query_one("SELECT balance FROM accounts WHERE id = {from_id}")?
        let to_acct = db.query_one("SELECT balance FROM accounts WHERE id = {to_id}")?

        if from.get_int("balance").unwrap() < amount {
            return Err(DBError.ExecError("insufficient funds"))
        }

        db.execute("UPDATE accounts SET balance = balance - {amount} WHERE id = {from_id}")?
        db.execute("UPDATE accounts SET balance = balance + {amount} WHERE id = {to_id}")?
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

**Effect operations go through handles, not bindings:** When `as tx` is used (e.g., to access a savepoint handle), `db.execute()` still routes through the `db` effect handle — `tx` is the `BlockHandler.Context` value, not a replacement for the effect handle.

**Manual API:** `db.begin()`, `db.commit()`, `db.rollback()` remain available for advanced patterns (nested transactions via SAVEPOINTs, long-running operations). See [db-module-design.md](../decisions/db-module-design.md) Q6.

**History:** Originally specified as a parser special form (3-1 vote, see [transaction-block-syntax.md](../decisions/transaction-block-syntax.md)). Superseded by the general `BlockHandler` mechanism (5-0 vote, see [scoped-block-mechanism.md](../decisions/scoped-block-mechanism.md)) which provides the same block semantics through a trait-based approach.

---

#### 4.4.5 Filesystem Operations

The `fs` handle is in scope when a function declares `! FS` or one of its sub-effects (`FS.Read`, `FS.Write`, `FS.Delete`, `FS.Watch`). Every filesystem operation can fail — a path may not exist, permission may be denied, a disk may be full — so each returns `Result[T, FsError]`. A failure is never a silent sentinel value; it is a typed error the caller must handle or propagate with `?`.

| Operation | Signature | Effect |
|---|---|---|
| `fs.read` | `fs.read(path: Str) -> Result[Str, FsError]` | `FS.Read` |
| `fs.write` | `fs.write(path: Str, content: Str) -> Result[(), FsError]` | `FS.Write` |
| `fs.list_dir` | `fs.list_dir(path: Str) -> Result[List[Str], FsError]` | `FS.Read` |
| `fs.delete` | `fs.delete(path: Str) -> Result[(), FsError]` | `FS.Delete` |

Directory listing is a read, so `fs.list_dir` needs only `FS.Read` — there is no `FS.List` sub-effect.

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
    Delete
}

pub type FsError {
    op: FsOp
    path: Str
    code: Errno
}
```

`code` is the `Errno` newtype from `std.errno` — the same zero-cost error code returned by `libc.*` and `io.*`. `fs` wraps it with the operation and the path so the message can name *what* was being done and *to what*. `Errno` on its own says `ENOENT`; `FsError` says that reading `/etc/app.toml` gave `ENOENT`.

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

**Propagation is exact.** `?` on an `fs` call propagates `FsError` unchanged; it does not convert to the enclosing function's error type. A function that reads a file and returns a different error type must adapt with `.map_err(...)` — there is no implicit `.into()` (see error propagation, §3c).

`FsError` and `FsOp` live in `std.fs` and are named with `import std.fs` — the same way `net.request`'s `NetError` is named with `import std.net`. The `fs` operation handle needs no import (it comes from the `! FS` effect on the signature), but the error *type* a caller matches on does.

**No file handles in v1.** The `fs` surface is exactly the four path-taking operations above. There is no `fs.open`, no `fs.create`, and no handle-taking read — a read is `fs.read(path)`, never `fs.read(handle)`. Streaming and incremental access are a post-v1 addition and will arrive as *methods on a file handle* (`file.read_line()`, `file.write_line(...)`), not as overloads of `fs.read` — Blink has no function overloading. Examples in §4.7 (*Scoped resources: `with...as`*) that open a `Closeable` file handle with `with ... as` illustrate the scoped-resource mechanism against that planned handle API; they are marked there as post-v1.

#### 4.4.6 Datagram Sockets (UDP)

Decided by panel deliberation [`udp-gate-sockaddr-flags`](../decisions/udp-gate-sockaddr-flags.md). `std.net` gives UDP a socket type built on `libc.recvfrom_bytes` and `libc.sendto_bytes` (§9.1.3.4).

**Addresses.** `SockAddr` is a plain Blink enum. It is not an `@ffi.struct`. The runtime converts it to and from the C `sockaddr_storage`.

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
pub fn udp_bind(addr: SockAddr) -> Result[UdpSocket, NetError]            // ! Net.Listen
pub fn resolve(host: Str, port: Int) -> Result[List[SockAddr], NetError]  // ! Net.DNS

pub trait UdpSocketOps {
    fn recv_from(self, -- max: Int = 65535) -> Result[(Bytes, SockAddr), NetError]
    fn send_to(self, data: Bytes, dest: SockAddr) -> Result[(), NetError]   // ! Net.Connect
    fn local_addr(self) -> Result[SockAddr, NetError]
    fn set_timeout(self, ms: Int)
    fn close(self)
}
```

- `udp_bind` creates the socket and binds it in one runtime call. `std.libc` has no `socket` or `bind` wrapper. Bind to port 0 to get a free port, then read it with `local_addr`.
- `recv_from` returns one datagram and its sender. The semantics of §9.1.3.4 apply: a 0-length datagram is `Ok` with empty `Bytes`, and a datagram larger than `max` is truncated without an error. The default `max` of 65535 holds any UDP datagram. Code on a hot path with small datagrams passes a smaller `max`, because each call allocates `max` bytes.
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

---

### 4.5 Effect Composition Rules

Effects propagate upward through the call graph. If function A calls function B, A must declare at least all of B's effects. The compiler enforces this transitively across the entire program.

```blink
fn check_inventory(item_id: Int) -> Result[Int, DBError] ! DB.Read {
    db.query_one("SELECT quantity FROM inventory WHERE id = {item_id}")?
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
    db.exec("ALTER TABLE ...")?
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

This is the one normative statement of these rules. §9.1 (*The Effect Row*, *`@trusted`*) and §4.7 refer to it. An `@ffi` decl's row enters the program at the decl and from there propagates by the rules above, with no special case. `@trusted` does not discharge or narrow a row: a wrapper that calls an `@ffi` decl with row `! Net.Connect` must itself declare `Net.Connect` or discharge it in the usual way. The FFI regions of §9.1.1 (an `@ffi` or `@trusted` body, `with ffi.scope()`) decide where a `Ptr[T]` may appear; they do not change what any row says.

**Effect rows on trait impls.** When a trait declares a method `m` with effect row `R_t`, every `impl` that provides `m` must declare a row `R_i` such that `R_i ⊆ R_t` under the lattice above. The rule covers required methods and overrides of open defaults alike. An impl may *narrow* the signature (drop effects the trait declares but the impl does not use) but may not *widen* it (introduce effects the trait does not declare). A trait method with no `!` has the empty row, so its impls must have no `!` either. This preserves the trait's stated capability contract for every implementation: callers parameterized over `T: Trait` can rely on the trait's row as a sound upper bound on `m`'s effects across all `T`. A widening impl is rejected with `error[TraitContractEffectMismatch]` (E0904). Sealed (`final`) defaults have no override site and are therefore effect-monomorphic at their declaration. See §3.6 *Effect-row subtype for trait impls* for an example and §3.6 *The `final` Modifier* for the override-prevention semantics.

---

### 4.6 Effects on `main`

`main` is the root of the capability tree. It implicitly holds all effects. The root has a handler for each built-in effect (§4.3), and those are the capabilities `main` holds. A user-declared effect has no root handler (§4.12): `main` must discharge it with `with`, or the program does not compile (see *Unhandled user effects* below).

```blink
// Valid -- main implicitly has all effects
fn main() {
    io.print("Hello, world!")
    let data = fs.read("config.toml")
    let rows = db.query("SELECT * FROM users")?
}

// Also valid -- explicit annotation, but unnecessary
fn main() ! IO.Print, FS.Read, DB.Read {
    io.print("Hello, world!")
    let data = fs.read("config.toml")
    let rows = db.query("SELECT * FROM users")?
}
```

`main` is where ambient authority lives. It is the **only** place where capabilities are created from nothing. Every other function in the program receives its capabilities from its caller, tracing back to `main`. This is the ocap discipline: authority flows downward through explicit delegation, never materializes from thin air.

The LSP displays `main`'s actual effect set as an inlay hint, computed from the transitive closure of everything `main` calls. If `main` only calls pure functions and one `io.print`, the hint shows `! IO.Print` -- not "all effects." This is documentation, not enforcement.

**Why implicit on `main`:** Requiring `main` to declare effects is pure ceremony. `main` is the program. Its effect set is "whatever the program does." An explicit annotation on `main` would just be a worse version of what the compiler already computes. Every other public function must declare effects explicitly -- `main` is the single exception.

#### Unhandled user effects

A user-declared effect that reaches `main`'s body with no `with` that discharges it is a compile error, `UnhandledEffect` (E0539). The check uses the effect rows the type checker infers (§4.5, §4.15), closures and `! _` rows included, and the same discharge rule as `with` (§4.7, and §4.6.3 *Scoped effect handlers* for a `BlockHandler` whose `Context` is `Handler[E]`). Test blocks are the other root, and the same code reports them (§2.20).

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

The check runs at compile time, so it cannot see every operation. A handler may be partial, and an operation it omits can still find no handler at run time. That operation panics (§4.7.1 *Completeness and auto-delegation*).

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

A `handler E { ... }` expression captures bindings from its enclosing scope exactly as a closure does (§2.8). A captured `let mut` binding is a shared cell (§3.6 *Shared cells*): writes in a handler op are visible to the enclosing scope and to any closure that captured the same binding. This differs from `BlockHandler` block bodies (§4.6.3), which run in the caller's scope and capture nothing. The `std.testing` mock controllers (§8.10.3) depend on this rule.

#### Testing: mock handlers

The most common use case. Replace real effects with test doubles:

```blink
fn process_order(id: Int) -> Result[Receipt, OrderError] ! DB.Read, DB.Write, IO.Log {
    let order = db.query_one("SELECT * FROM orders WHERE id = {id}")?
    io.log("Processing order {id}")
    let receipt = Receipt { order_id: id, total: order.total }
    db.execute("INSERT INTO receipts ...")?
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

If two handlers cover the same effect, the leftmost wins (innermost-scope semantics). This is deterministic and predictable.

#### Handlers are values

Handlers are first-class values. They can be stored in variables, passed as arguments, and returned from functions:

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

The `with...as` construct handles this second tier. The file-handle examples below (`fs.open`, `fs.create`, and the handle methods `read_all` / `write` / `read_line`) are **planned post-v1 API**, shown to illustrate the scoped-resource mechanism — they are not part of the v1 `fs` surface, which is the four path operations in §4.4.5:

```blink
// Planned (post-v1): the file-handle API. Shown here to illustrate `with ... as`
// scoped resources; the v1 fs surface is the four path operations in §4.4.5.
fn copy_file(src_path: Str, dst_path: Str) -> Result[(), FsError] ! FS {
    with fs.open(src_path)? as src, fs.create(dst_path)? as dst {
        let data = src.read_all()?
        dst.write(data)?
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

The outer `with mock_db(fixtures), temp_fs()` installs effect handlers (no `as`). The inner `with fs.create(...)? as f` is a scoped resource (`as` present). The compiler distinguishes them by the presence of `as`.

#### Disambiguation rules

| Syntax | `as` present? | Type check | Meaning |
|--------|--------------|------------|---------|
| `with expr { }` | No | `expr: Handler[E]` | Effect handler |
| `with expr { }` | No | `expr: T where T: BlockHandler, T.Context == Handler[E]` | Scoped effect handler: `enter()`, install the returned handler for `E`, body, uninstall, `exit(ok)` |
| `with expr { }` | No | `expr: T where T: BlockHandler, T.Context == ()` | Block handler (no binding) |
| `with expr as name { }` | Yes | `expr: T where T: Closeable` | Scoped resource |
| `with expr as name { }` | Yes | `expr: T where T: BlockHandler` | Block handler (with binding); if `T.Context == Handler[E]`, also a scoped effect handler |

When `as` is absent, the compiler checks `Handler[E]` first, then a `BlockHandler` whose `Context` is `Handler[E]`, then a `BlockHandler` whose `Context` is `()`. Any other `Context` without `as` is an error (E0839). When `as` is present, the compiler checks `Closeable` first, then `BlockHandler`. A type implementing both `Closeable` and `BlockHandler` is a compile error (ambiguity).

`as` never changes what a `with` item does. For a scoped effect handler, `with expr as name { }` installs the handler exactly as `with expr { }` does, and also binds `name` to the same `Handler[E]` value. The typing rule and evaluation order are in §4.6.3, *Scoped effect handlers*.

**Comma-separated items nest from left to right.** `with a, b { body }` means `with a { with b { body } }`. The compiler evaluates and type-checks item *i* after items *0..i-1* are entered and their handlers installed, so a later item can use an effect that an earlier item installs. Teardown is LIFO. If item *i* fails through `?`, the `?` fires before item *i* is entered, and the normal unwind of items *0..i-1* runs their `exit(false)` or `close()` (§4.6.3, *Catchable unwind*; §5.5, *Multiple resources*).

All forms can appear in the same comma-separated `with`:

```blink
with mock_db(fixtures), fs.open("x.txt")? as f {
    // mock_db provides DB handler, f is a Closeable file handle
}

with mock_db(fixtures), db.transaction() {
    // mock_db provides DB handler, transaction is a BlockHandler
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
            file.read_all()  // COMPILE ERROR E0601: closeable `file` escapes scope
        })
    }
}
```

If concurrent tasks need the resource, open it outside or pass the data:

```blink
fn good_example() ! FS, Async {
    let data = with fs.open("data.txt")? as file {
        file.read_all()?
    }
    async.scope {
        async.spawn(fn() { process(data) })
    }
}
```

---

### 4.6.3 BlockHandler Trait — Scoped Blocks

The `BlockHandler` trait provides a general mechanism for types that need enter/exit semantics around a block of code. It replaces the need for parser special forms for each new block-accepting API.

```blink
trait BlockHandler {
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
| Uncaught panic (`panic()`, arithmetic overflow, OOB index, OOM, abort) outside a runtime catch frame | *bypasses `exit()` entirely* |

The runtime catch frames are the test runner's per-test boundary, the `?`/`return` desugar, and — within a test only — the boundary armed by an `assert_panics` block (§2.20). The set of runtime catch boundaries is **exhaustively defined by this spec and cannot be extended by user code**. Introducing user-level panic recovery (e.g., `recover`, `catch_panic`) would require a separate spec amendment that re-evaluates `exit()`/`close()` semantics under the new boundary set.

**Amendment — `assert_panics` extends the catchable-unwind set (compiler-managed, not user-extensible).** Be precise about what changed: outside a test, a real `panic()` does *not* unwind to any in-process catch frame — it terminates the process and bypasses `exit()`/`close()` (the last row above). `assert_panics` (§2.20) genuinely *adds* a new catch boundary: within the dynamic extent of its block, a panic is caught and converted to a test pass/fail rather than terminating the process. This boundary is **compiler-managed and test-only** — it is armed exclusively by the compiler's `assert_panics` lowering, is rejected outside a test (E0833), is not nestable (E0834), and exposes **no user-nameable symbol** (there is no `recover`/`catch_panic` a user can call). It therefore does not extend the set of catch boundaries reachable by *user code*; the user-extensible set remains empty, and the fence above holds.

The `panic: Never` typing claim (§2.20, *`panic()` Function*) is preserved: the `assert_panics` construct has type `()`, its body is a recognized block (not a reified `fn` value), and the `matching:` argument binds nothing into user scope — so no user expression acquires a type that witnesses the panic. As with `BlockHandler.exit(false)` itself, the cleanup that runs during an armed-panic unwind cannot receive the panic value, cannot inspect any discriminant beyond `ok: Bool`, cannot suppress the unwind, and cannot rescue the test.

The cleanup asymmetry is intentional and must be read carefully: an **armed** (expected) panic runs in-scope `exit(false)`/`close()`; an **unarmed/uncaught** panic still terminates and bypasses them. A resource opened inside an `assert_panics` body is therefore released on the expected panic, whereas the same panic escaping a plain test body is not — armed test boundaries are controlled, like `skip()`, and uncaught divergence is not.

**Concurrency.** The armed state is **per-test (thread-local)**. An `assert_panics` in one test or task must never catch a panic raised on a different spawned task; arming is scoped to the calling frame's thread. This is normative, not implementation-defined.

**Cleanup that itself panics during an armed unwind.** If an in-scope `exit(false)`/`close()` *itself* panics while unwinding an armed expected panic, the original body panic remains "the expected panic" for `matching:` (E0832) purposes and stays load-bearing as the test's result and unwind cause; the cleanup fault surfaces as a **secondary `warning`-severity `E0824`** on the **same trace frame** (the test runner records it in the per-test record's `cleanup_warnings[]`, additive to the original status — see E0824, §5.5), not as a separate failing record. The panicking cleanup body's own control flow is abandoned at the panic point; remaining LIFO handlers still run (`continue-drain`, per line below).

This rule is uniform across `BlockHandler.exit()` and `Closeable.close()` (§5.5) — every catchable structured unwind runs registered cleanup; uncaught divergence does not.

#### Block semantics

`BlockHandler` blocks have block semantics, not closure semantics:

- `?` propagates errors to the **enclosing function's** `Result` return type
- `return` exits the **enclosing function**, not just the block
- Variables from the enclosing scope are directly accessible (no capture)

This is the same behavior as `async.scope { }` — the block runs in the caller's context, not in a separate closure scope.

#### Usage

```blink
// With binding — Context is meaningful
with db.transaction() as tx {
    db.execute("INSERT INTO orders ...")?
}

// Without binding — Context is ()
with metrics.timer("request_duration") {
    handle_request()?
}

// As an expression
let result = with db.transaction() {
    db.query_one("SELECT count(*) FROM users")?
}
```

#### Implementing BlockHandler

Any type can implement `BlockHandler`:

> **Note:** this example assigns to `self.start` in `enter`. That write does not persist: `self` is a by-value copy, and `exit` receives the value the `with` expression built (§3.6). How state passes from `enter` to `exit` is an open question (the BlockHandler state ticket). Do not copy the `self.start = ...` line.

```blink
struct Timer {
    label: Str
    start: Instant
}

impl BlockHandler for Timer {
    type Context = ()

    fn enter(self) -> () {
        self.start = time.now()
    }

    fn exit(self, ok: Bool) ! IO.Log {
        let elapsed = time.now().since(self.start)
        io.log("{self.label}: {elapsed}ms (ok={ok})")
    }
}

// Usage
with Timer { label: "db_query", start: time.now() } {
    db.query("SELECT * FROM large_table")?
}
```

#### Scoped effect handlers

A `BlockHandler` whose `Context` is `Handler[E]` is a **scoped effect handler**. The `with` block installs the handler that `enter()` returns, for the block body only. This joins an effect handler and a cleanup in one `with` item. In this example, `sqlite_open` returns `Result[Sqlite3, DBError]`, with `Err(ConnectionError(..))` when the open fails:

```blink
pub type Connection {
    handle: Sqlite3
}

impl BlockHandler for Connection {
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
    db.exec("CREATE TABLE users (name TEXT)")?
}
```

**Order.** For `with expr { body }`:

1. Evaluate `expr`
2. Call `enter()`
3. Install the returned `Handler[E]`
4. Run `body`
5. Uninstall the handler
6. Call `exit(ok)`

Steps 5 and 6 run on every catchable unwind, as for every `BlockHandler`. `exit()` runs after the uninstall, with the outer handlers in place. A `db.*` call inside `exit()` therefore goes to the outer `DB` handler, not to the one this item installed. Use `self` in `exit()`.

**Typing rule.** The item discharges `E` from the effect row of the body. `enter()` and `exit()` are checked against the outer effect row:

```
Γ ⊢ e : T    T : BlockHandler    T.Context ≡ Handler[E]
Γ ⊢ body : U ! ρ ∪ {E}
───────────────────────────────────────────────
Γ ⊢ with e { body } : U ! ρ ∪ eff(enter) ∪ eff(exit)
```

The rule applies only when `T.Context` normalizes to `Handler[E]` with a concrete `E` at the `with` site. In generic code such as `fn run[T: BlockHandler](t: T) { with t { } }`, `Context` is abstract: the item installs no handler and discharges no effect. It must then meet the `Context == ()` row. An abstract `Context` does not meet it, so the compiler reports E0839 and names the abstract `Context` as the cause. There are no effect-kinded generics in v1 (§4.7.1), so `E` is always concrete where the rule applies.

**Binding.** `with expr as name { }` installs the handler and binds `name` to the same `Handler[E]` value. `name` follows the scoping rules in *Interaction with async* below.

**Acquire before the block.** `self` is passed by value, so `enter()` cannot hand new state to `exit()`. A scoped effect handler therefore holds its resource from construction, like a `Closeable`. Entering the same value in two `with` blocks runs `exit()` twice. The scope lint (§5.5) warns about a scoped value that does not go into a `with`.

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

`BlockHandler` bindings follow the same scoping rules as `Closeable` bindings (E0601, E0602). This includes the `Handler[E]` that `as` binds for a scoped effect handler: that handler uses a resource that `exit()` releases. A `BlockHandler` binding cannot be sent to a spawned task:

```blink
fn bad_example() ! DB, Async {
    with db.transaction() as tx {
        async.spawn(fn() {
            // COMPILE ERROR: `tx` escapes BlockHandler scope
            use_tx(tx)
        })
    }
}
```

#### Relationship to existing scoped blocks

| Block form | Mechanism | Migration status |
|-----------|-----------|-----------------|
| `db.transaction { }` | `BlockHandler` | Migrated — uses `with db.transaction() { }` |
| `async.scope { }` | Parser special form | v1: remains special form. v2: migrate to `BlockHandler` |

`async.scope` remains a parser special form in v1 because its structured concurrency semantics (task cancellation, panic propagation, implicit join at scope exit) require deeper compiler integration than `enter()/exit()` provides. Once `BlockHandler` proves itself on simpler use cases, `async.scope` migration will be evaluated for v2.

**Panel vote: 5-0 (runoff).** See [decisions/scoped-block-mechanism.md](../decisions/scoped-block-mechanism.md).

---

### 4.7.1 Handler Type System

`Handler[E]` is a compiler-known generic type parameterized by an effect. It is the type of values produced by `handler E { ... }` expressions. At the source level, `Handler[E]` is a single type constructor; at the C level, each `Handler[E]` compiles to an effect-specific vtable struct managed by the GC.

#### Type identity

`Handler[E]` is parameterized by a concrete effect. `Handler[DB]`, `Handler[IO]`, and `Handler[Net.Connect]` are distinct types. The type parameter must be a declared effect — `Handler[Int]` is a compile error:

```
error[InvalidHandlerTypeParam]: invalid handler type parameter
 --> app.bl:3:10
  |
3 | let h: Handler[Int] = ...
  |                ^^^ `Int` is not an effect
  |
  = note: Handler[E] requires E to be a declared effect
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
fn run_with(h: Handler[DB]) ! DB {
    with h {
        do_work()
    }
}
```

At the C level, handler values are GC-managed copies of the vtable struct. Storing a handler copies the struct (function pointers + captured state); the GC tracks the copy. This means handlers are safe to store beyond the scope that created them — no dangling references.

#### Effect projection

A `Handler[E]` where `E` is a parent effect can be used where a `Handler[E.Sub]` is expected. The compiler automatically projects the relevant vtable slots:

```blink
fn read_only_test(h: Handler[DB.Read]) ! DB.Read {
    with h {
        let rows = db.query("SELECT * FROM users")?
    }
}

let full: Handler[DB] = mock_db(data)
read_only_test(full)  // OK: compiler projects DB → DB.Read
```

This is not subtyping — the compiler extracts the relevant operation slots from the parent handler's vtable and constructs a projected handler. The projection is implicit at the call site but explicit in the generated code.

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

Handlers may be **partial** — omitted operations automatically delegate to the dynamically enclosing handler. The compiler generates `default.op(args)` forwarding for each unimplemented operation:

```blink
fn logging_db(label: Str) -> Handler[DB] {
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

Auto-delegation means a `Handler[DB]` that only overrides `read` is still a complete `Handler[DB]` — the type system does not distinguish partial from total handlers. At runtime, unhandled operations bubble up to the nearest enclosing handler that implements them.

When no enclosing handler implements the operation, the operation panics. This happens when a partial handler omits it and no outer handler implements it, or when a handler calls `default.op(args)` with no outer handler. The compile-time check at the roots (§4.6 *Unhandled user effects*, §2.20) does not rule this out, because it sees a partial handler as a complete one:

```blink
effect Cache {
    fn get(key: Str) -> Option[Int]
    fn put(key: Str, value: Int)
}

fn read_only_cache() -> Handler[Cache] {
    handler Cache {
        fn get(key: Str) -> Option[Int] { None }
        // put omitted -- auto-delegates, but no outer handler implements it
    }
}

fn main() {
    with read_only_cache() {
        cache.put("hits", 1)   // panics: no handler for `cache.put`
    }
}
```

The operation never returns and never produces a default value, whatever its return type, `-> Never` included. The panic message contains the operation as a program calls it, `<handle>.<op>` (here `cache.put`; handles are described in §4.4). The rest of the message and the source location are not specified, so a test matches on the operation: `assert_panics(matching: "cache.put") { ... }` (§2.20).

#### Generic handler parameters

In v1, handler type parameters must be concrete effects: `Handler[DB]`, `Handler[IO]`, `Handler[Net.Connect]`. Effect-kinded generic parameters (e.g., `fn foo[E: Effect](h: Handler[E])`) are deferred to v2, alongside named effect variables.

#### Compilation model

Each `Handler[E]` compiles to a C struct containing one function pointer per operation in effect `E`, plus a `void*` for captured closure state:

```c
// Generated for Handler[DB] (conceptual)
typedef struct {
    blink_result (*read)(void* state, blink_query query);
    blink_result (*write)(void* state, blink_query query);
    blink_result (*admin)(void* state, blink_query query);
    void* state;  // captured environment (GC-managed)
} blink_handler_DB;
```

Handler values are heap-allocated via the GC. Storing a handler in a struct field or list copies the struct (function pointers are plain pointers; `state` is a GC root). The evidence-passing model (§4.5, [Codegen Backend rationale](../decisions/codegen-backend-bootstrap.md)) installs handler vtables into the evidence vector when entering a `with` block.

Effect projection (`Handler[DB]` → `Handler[DB.Read]`) generates a new struct containing only the relevant function pointer slots, populated from the source handler.

---

### 4.8 Module Capability Budgets

Modules can declare a hard ceiling on the effects any function inside them may use:

```blink
@capabilities(DB.Read, DB.Write)
module inventory

fn check_stock(item_id: Int) -> Result[Int, DBError] ! DB.Read {
    db.query_one("SELECT quantity FROM inventory WHERE id = {item_id}")?
}

fn update_stock(item_id: Int, delta: Int) -> Result[(), DBError] ! DB.Write {
    db.exec("UPDATE inventory SET quantity = quantity + {delta} WHERE id = {item_id}")?
}

fn drop_table() -> Result[(), DBError] ! DB.Write {
    db.exec("DROP TABLE inventory")?
    // This works if the module's capability budget includes DB.Write
}
```

```
error[CapabilityBudgetExceeded]: capability budget exceeded
 --> inventory.bl:12:5
  |
12|     db.exec("DROP TABLE inventory")
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
fn restricted_net(allowed_hosts: List[Str]) -> Handler[Net.Connect] {
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
| Global mutable state | Mutation analysis (§4.16) | Module-level `let mut` mutation tracked by compiler write-set inference. Cross-module statefulness via user-defined effects (§4.12). |
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

`! Store` grants `store.get(...)` and `store.put(...)`. A leaf has no sub-effects, so a row grants all of its operations or none of them. The built-in `Rand` (§4.3) is a leaf of this kind.

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

The standard library ships default handlers for built-in effects (real filesystem, real network, real database drivers). User-defined effects have no default handler -- you must provide one. This is intentional: the compiler forces you to explicitly wire up your domain effects, making the architecture visible. A user-defined effect that reaches `main` or a test block with no `with` that discharges it is `UnhandledEffect` (E0539, §4.6 *Unhandled user effects*). No operation answers a default value: an operation that finds no handler at run time panics (§4.7.1 *Completeness and auto-delegation*).

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
| `async.scope { ... }` | Structured concurrency boundary. All spawned tasks must complete before the scope exits. *(v1: parser special form; v2: may migrate to `BlockHandler` — see §4.6.3)* |
| `async.spawn(fn() { ... })` | Launch a concurrent task within the current scope. Returns `Handle[T]`. |
| `handle.await` | Wait for a spawned task's result. Method on `Handle[T]`, returns `T`. |
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

`async.spawn` returns a `Handle[T]` — an opaque value representing a running task. `handle.await` is a method on `Handle[T]` that suspends the current task until the spawned task completes and returns its result. The compiler recognizes `.await` as a suspension point and requires `! Async` in the function's effect declaration.

A spawned task performs effect operations with the handlers in force at its `async.spawn` site. Spawn is not a root: the closure's row is part of its caller's row (§4.15.4), so the check in §4.6 *Unhandled user effects* covers operations the task performs.

**Why `handle.await` and not `async.join(handle)`:**

Blink uses namespaced functions for *creating* concurrent primitives (`async.scope`, `async.spawn`, `channel.new`) but method syntax for *consuming* results (`handle.await`). This follows the data flow: the handle is the thing you're waiting on, so the operation belongs to the handle. It also chains naturally with error propagation:

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
| `ch.send(value: T)` | Blocks while the buffer is full, then adds `value`. **Panics if `ch` is closed.** |
| `ch.recv() -> Option[T]` | Blocks until a value is ready or `ch` is closed. Returns `Some(value)` for the next value. Returns `None` only when `ch` is closed **and** every buffered value is received. |
| `ch.close()` | Marks `ch` closed. Values already in the buffer stay receivable. A second `close()` does nothing. |

`recv()` is the only blocking receive. There is no `try_recv` and no `is_closed()`: a check before a receive races with other consumers, and `recv()` already gives the answer in one step.

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

The runtime (green thread scheduler, M:N threading) is wired implicitly. Every other function that suspends must declare `! Async` explicitly.

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
        let stock = db.query_one("SELECT quantity FROM inventory WHERE id = {item.id}")?
        if stock < item.quantity {
            return Err(OrderError.InsufficientStock(item.id, stock))
        }
    }
    Ok(())
}

fn reserve_stock(order: Order) -> Result[(), DBError] ! DB.Write {
    for item in order.items {
        db.exec("UPDATE inventory SET quantity = quantity - {item.quantity} WHERE id = {item.id}")?
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
    let rows = db.query("SELECT * FROM data")?
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

> **v1 note.** The `Iterator` adapters above illustrate the *shape* of wildcard forwarding; they do not describe v1 `Iterator`. In v1 the built-in `Iterator[T]` carrier is **pure** — an adapter callback that performs effects is a compile error, and the effect row is reserved in the carrier's internal representation, never spelled on a v1 surface signature (§3c.1 *Effectful Iteration: Deferred to v2*). The `! _` forwarding shown here is the reserved v2 shape and the live mechanism for ordinary user higher-order functions. It is used here because it is the clearest worked example of the wildcard rule.

The wildcard `_` means: "whatever effects the callback has, this function has too." At call sites, the compiler resolves `_` to the concrete effects of the callback passed:

```blink
fn process_items(items: List[Item]) ! DB.Read, IO.Log {
    items.into_iter()
        .filter(fn(item) { item.is_active() })          // pure callback: _ = (nothing)
        .map(fn(item) {
            let price = db.query_one("SELECT ...")?       // _ = DB.Read
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

#### 4.15.3 Compilation

Effect polymorphism compiles via the existing evidence-passing model (§4.2, [Codegen Backend rationale](../decisions/codegen-backend-bootstrap.md)):

- **Concrete effect function types** (`fn(T) -> U ! IO.Log`): The callback receives the caller's evidence vector. The compiler verifies the caller holds the required effect slots at the call site. Zero additional overhead — same as any effectful function call.

- **Wildcard forwarding** (`! _`): The compiler resolves `_` at each call site to the concrete effects of the callback argument. The HOF is monomorphized per distinct effect set (same as generic type parameters). At the C level, the evidence vector is threaded through — no new mechanism, just one more monomorphization axis.

- **Pure callbacks in wildcard positions**: When a pure callback is passed to a `! _` function, `_` resolves to the empty effect set. The function becomes pure at that call site. The evidence vector threading is elided entirely.

#### 4.15.4 Interaction with Existing Features

**Effect composition (§4.5):** Wildcard effects compose with explicit effects following the same propagation rules. A caller must declare at least all effects that resolve through `_`:

```blink
fn caller() ! DB.Read {
    items.map(fn(x) { db.query("...") })  // OK: _ resolves to DB.Read, caller has it
}

fn bad_caller() {
    items.map(fn(x) { db.query("...") })  // ERROR E0500: missing DB.Read
}
```

**Handlers (§4.7):** Handlers can intercept effects that flow through wildcards:

```blink
test "map with mock DB" {
    with mock_db() {
        let results = items.map(fn(x) { db.query("...") })
        // handler intercepts DB.Read flowing through map's _
    }
}
```

**Closures (§2.8):** Closures used as effectful callbacks follow the same capture rules. Effect annotations on the closure type describe what the closure *body* does, not what it captures.

**async.spawn (§4.13):** `async.spawn` takes `fn() -> T ! _` — the spawned task inherits whatever effects the closure declares. The existing E0650 restriction on `let mut` captures still applies.

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

### 4.16 Module-Level Mutation Analysis

Module-level `let mut` bindings are a real and necessary feature — the Blink compiler itself uses them extensively (parser position, token buffers, pending comments). But untracked mutation of these bindings caused three real bugs where speculative lookahead saved and restored `pos` but not `pending_comments`, because nothing indicated which state each function touched.

Blink addresses this with a **two-tier model**: automatic compiler analysis (intra-module) and opt-in user-defined effects (cross-module).

#### 4.16.1 Tier 1: Compiler Write-Set Inference

The compiler performs **mutation analysis** on every function in a module. For each function, it computes the **write set**: which module-level `let mut` bindings the function (or its callees within the module) writes to.

**Key properties:**

- **Fully inferred** — no annotations in signatures. Functions look clean.
- **Writes only** — reading a `let mut` binding is free, not tracked as mutation.
- **Includes method calls** — `list.push(x)` on a module-level `let mut` binding counts as a write.
- **Transitive within module** — if `fn a()` calls `fn b()` which writes `pos`, then `a`'s write set includes `pos`.
- **Zero runtime cost** — purely compile-time analysis. Generated C is identical.
- **Not an effect** — this is a compiler analysis like type inference, not a declared effect. No `!` annotations needed.

Example of what the compiler tracks internally:

```
advance()               → writes {pos}
skip_newlines()         → writes {pos, pending_comments}
at()                    → writes {}  (reads pos, but reads are free)
looks_like_struct_lit() → writes {pos, pending_comments}
```

The analysis enables rich diagnostics. The compiler can now detect when a save/restore pattern misses a binding:

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

The LSP shows inferred write sets on hover — developers and AI can see which globals a function touches without reading its body.

#### 4.16.2 What Counts as a Write

| Access | Tracked as write? | Rationale |
|--------|-------------------|-----------|
| Assign to module-level `let mut` (`pos = pos + 1`) | **Yes** | Direct mutation |
| Mutating method call on module-level `let mut` (`tokens.push(t)`) | **Yes** | Mutation through method |
| Read module-level `let mut` (`return pos`) | No | Reads are free — no state corruption risk |
| Read module-level `let` (immutable) | No | Immutable — equivalent to a constant |
| Read/write function-local `let mut` | No | Contained within function scope |
| Mutate collection received as parameter | No | The parameter must be declared `mut`, so the signature shows it (§3.6 *Mutable Parameters*) |
| Mutate captured `let mut` in closure | No | Lexically scoped — visible within enclosing function body |

#### 4.16.3 Purity and Non-Mutating Functions

A function with no `!` and an empty write set is **non-mutating** — it does not write to any module-level `let mut` bindings. This is weaker than full referential transparency because the function may still *read* mutable state and thus return different values on different calls.

Truly pure functions — those that neither read nor write module-level mutable state, with output depending only on inputs — can be identified by the compiler for optimization (memoization, reordering). This is an internal optimization analysis, not a user-facing annotation.

```blink
let mut pos = 0

// Non-mutating, but NOT pure — reads `pos`, return value depends on call order
fn current_pos() -> Int {
    pos
}

// Pure — output depends only on inputs, no module state access
fn add(a: Int, b: Int) -> Int {
    a + b
}

// Mutating — writes {pos}
fn advance() {
    pos = pos + 1
}
```

Note that `advance()` has **no `!` annotation**. Module-level mutation is tracked by the compiler's write-set analysis, not by the effect system. The function signature stays clean.

#### 4.16.4 Transitive Tracking

Write sets are computed transitively within a module. If `fn a()` calls `fn b()` which calls `fn c()` which writes `pos`, then all three have `pos` in their write sets.

```blink
let mut pos = 0
let mut pending_comments: List[Comment] = List.new()

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

The compiler knows `looks_like_struct_lit` writes `{pos, pending_comments}` transitively through `skip_newlines`. It can verify that both are saved and restored.

Cross-module calls are **not** transitively tracked. A call to an imported function is opaque — the compiler does not look inside it. This keeps compilation modular and avoids coupling internal implementation details across module boundaries.

#### 4.16.5 Tier 2: User-Defined Effects for Cross-Module State

If a module author wants callers to know about statefulness, they use **user-defined effects** (§4.12):

```blink
effect Parse {
    effect Advance
    effect Reset
}

pub fn next_token() -> Token ! Parse.Advance {
    pos = pos + 1
    // ...
}

pub fn reset(saved: ParserState) ! Parse.Reset {
    pos = saved.pos
    pending_comments = saved.comments
}
```

Callers see `! Parse.Advance` in the signature and know the call changes parser state. This is opt-in — most modules with private mutable state don't need it because the state is encapsulated behind the public API. User-defined effects follow all the same rules as built-in effects: hierarchical, handle-based, handler-swappable, testable.

#### 4.16.6 Interaction with Existing Features

**Not an effect.** Mutation analysis is orthogonal to the effect system. A function can have an empty write set and still declare `! IO.Log`. A function can write to module globals and still have no `!` in its signature. The two systems track different things: effects track capability usage (IO, DB, Net), mutation analysis tracks internal state changes.

**Module capability budgets (§4.8, §4.9):** Mutation analysis does not participate in capability budgets. Module-level mutable state is internal to a module and does not cross trust boundaries. A package declaring `capabilities = []` (pure computation) can still use module-level `let mut` bindings — the state is encapsulated.

**`main` (§4.6):** `main` is not special for mutation analysis. It has a write set like any other function, computed transitively from what it calls.

**Closures:** If a closure writes to a module-level `let mut` binding, the write is attributed to the enclosing function's write set. Closures that only capture function-local `let mut` are not tracked.

#### 4.16.7 Diagnostic Precision: W0550 and W0551

The mutation analysis produces two warnings related to save/restore patterns in speculative code (lookahead, backtracking):

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

Mutation analysis warnings can be suppressed at two levels:

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

#### 4.16.9 Compilation

Mutation analysis is a **purely compile-time pass**. It generates no runtime code. The generated C for a function is identical whether or not mutation analysis is enabled — module-level `let mut` compiles to a C global variable regardless. The analysis exists solely to enable diagnostics and tooling.

The analysis runs after parsing and type checking, as a separate compiler pass. It builds a call graph within each module and propagates write sets bottom-up. The time complexity is linear in the number of functions × call edges within a module.
