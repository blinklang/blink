[< All Decisions](../DECISIONS.md)

# Effect Rows for the Handle Ops the Spec Never Named — Design Rationale

### Panel Deliberation

The ticket (verbatim):

> The compiler knows these handle ops but the spec handle tables (04_effects 4.4) give them no
> effect: io.debug; fs.errno (4.4.5 says the fs surface is exactly five path ops); term.isatty,
> term.width, term.height; net.connect, accept, read, read_all, read_line, read_bytes, write,
> write_bytes, set_timeout, close. Each needs an effect row, or removal from the surface. Until the
> panel maps them the row check leaves them uncharged. MVCE: @pure fn w() -> Int { term.width() }
> compiles.

The question was how to give each of these ops an effect row, or to remove it from the surface. The ticket blocks the handler clause row `Handler[E ! R]`, which needs every handle op to have a known row.

**Questions:**

1. **Q1.** What are the terminal queries (`term.isatty`, `term.width`, `term.height`)?
2. **Q2.** What is the type of a TCP socket, and what row do its operations take?
3. **Q3.** What does a user call to `fs.errno()` give?

#### Phase A — Independent proposals

Each seat wrote a proposal alone. The six replies follow in full.

- **Systems:**

> My main point: none of these ops is a real handle op. Each is a raw libc call or a read of a runtime thread-local, typed on raw `Int`, and a handler cannot answer it in a useful way. A mock `Net` handler cannot make an fd number, and a mock `FS` handler does not set `blink_fs_errno`. So all four groups leave the handle surface. The std code that calls them becomes second-tier `@ffi` bindings with honest rows (§4.4 rule 2), under the rules we already have: fd-table S1 and ffi-hidden-state Q2a. The generated C stays the same: an intrinsic call and an `@ffi` call both compile to one direct C call. Rows exist only at compile time, so nothing gets slower.
>
> ## P1 (my vote): remove all four groups from the handle surface and use the existing row rules
>
> **`io.debug`**: delete it from `is_intrinsic_method`. It has no codegen, and a call already gives E0505. No user-visible change.
>
> **`fs.errno`**: it leaves the `fs` handle, and §4.4.5 keeps exactly five ops. fs_ops.bl reads the thread-local through private `@ffi` decls, one decl for each producer, all on the same C symbol (net_unix.bl already binds `blink_unix_close_fd` twice like this):
>
> ```blink
> @ffi("blink_fs_errno_get")
> @trusted(audit: "Reads the thread-local errno that the last raw fs op set.")
> fn read_errno() -> Int ! FS.Read {}
>
> @ffi("blink_fs_errno_get")
> @trusted(audit: "Reads the thread-local errno that the last raw fs op set.")
> fn write_errno() -> Int ! FS.Write {}
> ```
>
> The symbol name is a placeholder: the runtime has the `blink_fs_errno` TLS variable but no getter yet. The result is one TLS load, the same as now. A user call to `fs.errno()` gives E0505 with a help line: "the error is in the `Err(e)` of the fs op; read `e.code`". This goes in as a removed-op table row, as a suggestion only, because the fix changes the shape of the code.
>
> **`term.*`**: §4.3 has no `Term` effect, so a `term` handle has no capability to stand for. The ops become private `@ffi` decls in term_detect.bl, and S1 gives each one its row:
>
> | std fn | row | why |
> |---|---|---|
> | `is_tty()`, `terminal_width()`, `terminal_height()` | `IO.Print` | ioctl/isatty on fd 1 |
> | `is_stderr_tty()` | `IO.Log` | fd 2, per S1 |
> | `is_fd_tty(fd: Int)` | union of every fd maker (as §9.1 `read_bytes`), or remove it | a raw fd has no single maker |
>
> The row is not only bookkeeping. `terminal_width()` changes after SIGWINCH, so if it had no row, `@pure` would let the optimizer CSE it or hoist it out of a redraw loop, and that is a miscompile. MVCE: `@pure fn w() -> Int { term.width() }` gives E0505 on `term.width`, with the help `terminal_width()` in `std.term` (`IO.Print`). Written as `terminal_width()`, it gives E0500 UndeclaredEffect (`IO.Print`) on `w`.
>
> No handler intercepts these (§4.10). The rows stay the same if a later panel adds `io.is_tty` as a real IO op, so P1 does not block that.
>
> **`net.*` fd ops**: they leave the `net` handle. Of the TCP ops, only `listen` stays, because §4.4.2 names it. net_tcp.bl binds the libc calls as `@ffi` decls, the way net_unix.bl does. For rows, the §4.4.6 maker rule says one type has one maker row, and `TcpSocket` has two makers: `tcp_connect` and `listener_accept`. The sound fix copies Unix: a `TcpStream` with `Net.Connect` and a `TcpConn` with `Net.Listen`. That split is the separate TCP-rows question. This ticket needs only soundness, so in the interim `TcpSocketOps` takes the union `! Net.Connect, Net.Listen` (rule 2 permits a sound upper bound). The pub raw-fd free fns (`tcp_read(fd: Int)` and the rest) take the same union. They also skip the handle box that stops a write to a reused fd number, so I would make them private once http_server.bl moves to the methods.
>
> ```blink
> import std.net.{tcp_connect}
> fn go() -> Bool {
>     match tcp_connect("localhost", 1) { Ok(_) => true  Err(_) => false }
> }
> ```
> This now gives E0500 UndeclaredEffect: `go` needs `Net.Connect`. A direct `net.connect("h", 1)` gives E0505 with the help `tcp_connect` in `std.net`.
>
> Once this lands, every remaining handle op has a known row, so the work on `Handler[E ! R]` can start.
>
> ## P2 (alternative): keep `term` as ops on the `io` handle
>
> Add `io.is_tty(stream)` and `io.width()` as real `IO.Print` ops. A mock IO handler could then answer width 80 for golden tests of TUI output. The cost is new spec surface and a new dispatch point. A handle op with a statically known handler still compiles to a direct call, so the runtime cost is zero. The cost is in the spec. I would defer P2: P1 gives the same rows and does not block it.
>
> ## Cross-language
>
> - Rust keeps `isatty` and errno behind `std::io::IsTerminal` and `io::Error::last_os_error()`. Neither is in the public effect surface. Errno never escapes as a free global.
> - Go's `net.Conn` has one type for both directions, so Go would have the same union-row problem; Blink's Unix split avoids it.
> - Koka puts console size in the `console` effect, which is P2.

- **Web/Scripting:**

> ## Proposal W1 (recommended): remove the raw ops from the user surface; std wrappers carry rows
>
> The 90% user never types `term.width()`. They type `import std.term` and `term.terminal_width()`. Today `term.width()` (an intrinsic) and `term.terminal_width()` (a function in std.term) share one prefix and do different things. A Python dev cannot see which one is real. Remove the raw ops from what a user can call, and charge the std functions that a user calls.
>
> **`io.debug`: remove.** It has no codegen and nothing in sections/ names it. A call keeps today's E0505 (no member `debug` on `io`). Add no removed-name row: the op never worked, so no program can need a migration.
>
> **`fs.errno`: remove as an op.** The raw `@ffi` bindings in fs_ops.bl return the errno code with the result (an Int out value, or a pair), so std needs no separate call. §4.4.5 "exactly five" stays true. A user call gives E0505 with a help: "fs errors come back in the `FsError` of each `fs` op". No handler sees it, because no op is left.
>
> **`term.isatty/width/height`: internal to std. The std.term functions become second-tier (no handler, like `udp_bind`) and use the fd-table-rows S1 mapping:**
>
> | std.term fn | row | why |
> |---|---|---|
> | `is_tty()`, `terminal_width()`, `terminal_height()` | `IO.Print` | they ask about fd 1, which `IO.Print` makes |
> | `is_stderr_tty()` | `IO.Log` | fd 2 |
> | `is_fd_tty(fd: Int)` | remove from `pub` | a raw Int fd has no known maker, so no row is sound |
>
> This is the DX win. Code that checks for a tty before it adds color already has `! IO.Print`, so a normal CLI gets no new row. A raw `term.width()` call gets E0505 with a removed-name row: fix `term.terminal_width()` after `import std.term`, effect `IO.Print`.
>
> **MVCE:**
> ```blink
> import std.term
> @pure
> fn w() -> Int { term.terminal_width() }
> ```
> gives E0500 UndeclaredEffect: `terminal_width` needs `IO.Print`. The ticket's exact text, `term.width()`, gives E0505 first, with the fix above.
>
> **`net.*` fd ops: internal to std. Model TCP on the §4.4.6 Unix sockets, which users will learn first:**
> ```blink
> import std.net.{tcp_connect}
> fn go() -> Bool ! Net.Connect {
>     match tcp_connect("localhost", 1) {
>         Ok(_) => true
>         Err(_) => false
>     }
> }
> ```
> With no `! Net.Connect` on `go`, this gives E0500. Rows: `tcp_connect` and the methods of the stream it returns take `Net.Connect`. `tcp_listen`, `listener.accept()` and the methods of the connection that `accept` returns take `Net.Listen`. The §4.4.6 rule "one type, one maker" means `TcpSocket` splits in two (`TcpStream` from connect, `TcpConn` from accept), like `UnixStream`/`UnixConn`. The raw-fd free functions (`tcp_read(fd, n)`, `tcp_write(fd, s)`, `tcp_close(fd)` and the others) leave `pub` for the same reason as `is_fd_tty`. http_server/http_client keep them as private helpers. A user call to a raw `net.connect(...)` gives E0505 with a removed-name row that names `tcp_connect`.
>
> **Handlers:** none intercept these functions (second tier, §4.10). That matches Go and Python: you test a TCP client against a real localhost listener, and you test tty logic by running the program under a pipe. `blink test` already gives no tty.
>
> **Tradeoffs:**
> - Plus: one name per job, rows that a CLI author already writes, and TCP that matches Unix sockets exactly. That is about the smallest set of things a dev must learn.
> - Minus: `TcpSocket` becomes two types. It breaks callers outside std, but the type has no spec text yet, so now is the cheap time to do it. The panel can scope it to the TCP-rows chore, but the row rule forces the split.
> - Minus: no handler can mock `is_tty()`. Node devs mock `process.stdout.isTTY` often. I accept this for v1; a test under `blink test` is never on a tty.
>
> Cross-language: Rust `std::io::IsTerminal` is a method on the stream (stdout), the same idea as "the fd 1 row". Go keeps `syscall` raw and gives users `net.Dial`. Koka charges terminal queries to the console effect.
>
> ## Proposal W2 (alternative): make the tty queries `IO.Print` handle ops
>
> `io.is_tty()`, `io.term_width()`, `io.term_height()` as ops of `IO.Print`, so a capture handler can answer "no tty, 80 columns". I reject it: it adds three ops that every user `IO.Print` handler must write, and that cost falls on the 90% of handlers that only capture text. W1 can add the ops later if users ask for them.

- **PLT:**

> ## Core rule (applies to all four groups)
>
> The set of compiler-known handle ops must equal the set of ops in the spec's effect declarations. An op outside every declaration has no row, so it breaks §4.1. It also has no clause a handler can supply, so `Handler[E ! R]` cannot be typed for it. Each ticket op either joins a declared effect or leaves the compiler. If it leaves, std reaches the runtime through an `@ffi` binding with a declared row (second tier, Rule 2). A test can check the invariant: walk `is_intrinsic_method` against the effect decls. The handler-row work needs exactly this.
>
> ## P1: what happens to each group
>
> **`io.debug`: remove.** It has no codegen and never compiled, so there is no user to migrate and no removed-table row. A call stays plain E0505.
>
> **`fs.errno`: remove from the surface.** It is a read of hidden state that a handle op made. Rule 3 then requires the handler that made the state to answer the read. A mock `FS` handler cannot do that, because `errno` is not in `FS`. So as a handle op it is unsound under handlers, not only missing a row. In std it becomes a binding whose row is the row of the producer (Q2a, fd-table S1): `c_fs_errno_read ! FS.Read`, `..._write ! FS.Write`, `..._delete ! FS.Delete`. All three use one C symbol. The union row `FS` would widen `fs.read`, so it is wrong. A better end state removes the side channel: each raw op returns its code. A user call gives E0505 `no member errno on module fs`, with a note that `FsError.code` carries the code.
>
> **`term.*`: move into `IO`, as primitive ops.** "Is stdout a terminal?" is a fact about the channel that the `IO.Print` handler owns. A second-tier `isatty(1)` lies under a capturing mock: the program colours output that goes into a buffer. A handle op answered by the same handler gets this right. Auto-delegation (§4.7.1) means existing partial handlers still compile.
> - `IO.Print`: `stdout_is_tty() -> Bool`, `stdout_size() -> Option[(Int, Int)]`
> - `IO.Log`: `stderr_is_tty() -> Bool`
> - `IO.Read`: `stdin_is_tty() -> Bool`
>
> The `std.term` wrappers keep their names and take these rows. `is_fd_tty(fd: Int)` goes away. A forged `Int` fd has no known maker, so the only sound row is `State`, and the 0/1/2 cases are covered above. The current 80/24 fallback becomes `None`, because a fake size is a lie the type can avoid.
>
> **`net.*` fd ops: remove from the surface.** The ops are typed on raw `Int`. An `Int` is forgeable, so Rule 3 ("the handler that made the value answers") cannot hold: `net.read(7, n)` reaches a handler that never made fd 7. std.net reaches the runtime through `@ffi` bindings. Its rows follow §4.4.6: `tcp_connect ! Net.Connect`, `tcp_listen`/`accept ! Net.Listen`. `TcpSocket` has two makers with different rows, which the one-maker-row rule forbids. So it splits the same way the Unix pair does: `TcpStream` (`Net.Connect`) and `TcpConn` (`Net.Listen`). The raw-fd free fns (`tcp_read(fd: Int)`, ...) leave `pub`. The interim alternative is the union row `Net.Connect, Net.Listen`. A user `net.connect(h, p)` gives E0505 through a new removed-table row: replace with `tcp_connect(h, p)` in `std.net`, effect `Net.Connect`, result changes (`Int` becomes `Result`). Side flag: the compiler types `net.listen` as `-> Int`, but §4.4.2 says `-> Server`.
>
> ## Example
>
> ```blink
> @pure
> fn w() -> Int { term.width() }
> ```
> → E0505 `no member width on module term`, fix `terminal_width()` + row `IO.Print` (removed-table row).
>
> ```blink
> import std.term.{terminal_width}
>
> @pure
> fn w() -> Int {
>     match terminal_width() { Some(n) => n  None => 80 }
> }
> ```
> → E1307 ImpureBodyForPureAnnotation: `terminal_width` needs `IO.Print`. With `fn w() -> Int ! IO.Print` it compiles. Under `with capture_print { w() }`, the mock answers `stdout_size`, and the result is `None`.
>
> ## Tradeoffs
>
> - Promoting `term` to IO grows a built-in effect by four ops. In return it is the only option that composes with handlers. P2 (below) is smaller, but gives wrong answers under mocks.
> - Removing `net.*` breaks any user calls to it. That is acceptable: TCP was never in sections/, and the replacement is one call away.
> - Per-producer errno readers duplicate one symbol three times. That is honest until the side channel goes.
>
> ## P2 (fallback for term)
>
> `std.term` fns stay second tier with rows `is_tty ! IO.Print` and `is_stderr_tty ! IO.Log`. `terminal_width` and `terminal_height` take `! IO.Print`, because they query stdout. No handler can answer them. This is sound for the row check but wrong under capture handlers.
>
> ## Cross-language
>
> Koka and Eff: an op exists only as a member of a declared effect, with no ambient ops. Go's `term.IsTerminal(fd)` and Rust's `IsTerminal` on `Stdout` are the analogues. Rust puts the query on the typed stream, not on a raw fd, which is the shape P1 takes. Haskell's `hIsTerminalDevice :: Handle -> IO Bool` asks the handle as well.

- **DevOps/Tooling:**

> My test for each op: when a user types `term.` or `net.`, what does completion offer, and what error comes back? Today the answer is wrong in both places. Completion can offer `io.debug`, and the call then fails with E0505. `term.width()` compiles in an `@pure` fn. So no op in this group stays a user-visible handle op. Each one gets a std wrapper that has a row, or goes away.
>
> ## Proposal 1 (recommended): make all four groups std-internal, put rows on the wrappers
>
> The compiler accepts `term.*`, `fs.errno` and the raw `net.*` fd ops only inside lib/std modules, as it already does for `range_bounds`. A handler cannot intercept them; they are second tier (§4.4 rule 2), in the same way as `udp_bind`.
>
> | Group | Fate | Row |
> |---|---|---|
> | `io.debug` | remove from `is_intrinsic_method`. It has no codegen and no spec text | none |
> | `fs.errno` | remove. Each raw `@ffi` op returns its errno with its result. `fs_do_*` already carries `FS.Read`/`Write`/`Delete` | the row of the op that made the code (Q2a) |
> | `term.*` | std-internal. `is_tty`, `terminal_width`, `terminal_height` get `! IO.Print` (the runtime does `ioctl(STDOUT_FILENO)`; per fd-table S1, fd 1 is made by `IO.Print`). `is_stderr_tty` gets the fd-2 row. `is_fd_tty(fd)` goes away: a bare fd has no maker | fd rule |
> | `net.*` fd ops | std-internal. TCP takes the §4.4.6 Unix shape: `tcp_connect -> TcpStream ! Net.Connect`, `TcpListener.accept -> TcpConn ! Net.Listen`, methods per the maker rule. The raw-`Int` free fns (`tcp_read(fd, ...)` etc.) go in the removed-names table | maker row |
>
> A user program today:
>
> ```blink
> @pure
> fn w() -> Int { term.width() }
> ```
>
> ```
> error[UndefinedVariable]: `term` is not a handle
>  --> w.bl:2:17
>   |
> 2 | fn w() -> Int { term.width() }
>   |                 ^^^^ not found in this scope
>   |
>   = fix: import std.term.{terminal_width}, then call terminal_width()
>   = help: `terminal_width` needs `IO.Print` in the effect row
> ```
>
> After that fix, `@pure` refuses the call (E0500, `terminal_width` requires `IO.Print`). That is the right answer, because the width is a fact about stdout.
>
> ```blink
> import std.net.{tcp_connect}
> fn go() -> Bool {
>     match tcp_connect("localhost", 1) { Ok(_) => true  Err(_) => false }
> }
> ```
>
> gives E0500: `tcp_connect` requires `Net.Connect`. The machine fix adds `! Net.Connect` to `go`. `tcp_read(fd, 10)` gives E0504 with the fix `stream.read(10)` from the removed-names table. That fix is a suggestion, not machine-applicable, because the receiver changes shape.
>
> Tradeoffs:
> - LSP completion on `term.`/`net.` shows only the spec handle table. Rust-analyzer and gopls offer only what you can call. The compiler should do the same.
> - One E0500 path covers the whole surface. No special-case diagnostic is needed.
> - Cost: the TCP type split breaks `TcpSocket` users (http_server/http_client inside std, and any user code). The `UnixConn`/`UnixStream` mismatch note (`X is made by Y`) already exists, so the error for a wrong type is ready to reuse.
> - `fs.errno` folded into the return value removes a hidden thread-local channel. Go's `(n, err)` and Rust's `io::Result` both make this choice, for the same reason: a later call cannot overwrite the code.
>
> ## Proposal 2 (fallback): std-internal, but no TCP split
>
> As Proposal 1, but `TcpSocket` stays one type, and each method carries the union row `! Net.Connect, Net.Listen`. This is a smaller change. But it breaks the §4.4.6 sentence "each socket type has exactly one maker row", and every client must then declare `Net.Listen`. The diagnostic gets worse too: a client that adds only `Net.Connect` gets a second E0500 for `Net.Listen`, and the user cannot see why. I vote against it unless the panel wants TCP out of scope for now.
>
> ## Handler interaction
>
> There is none. All of these ops are second tier. If the panel later wants `Term` to be mockable (for example, a test sets the width to 120), that needs a new `Term` effect with a `term` handle, which is a new §4.3 entry. YAGNI: no user ticket asks for it, and a `width: Int` parameter tests it today. Koka and Unison also keep terminal size outside their effect sets.
>
> ## Cleanup for tooling
>
> After this change, `is_intrinsic_method` has no entry that is outside the spec handle table and also outside the std-internal allow-list. A lint or unit test should assert that, so the gap cannot open again.

- **AI/ML:**

> ## Lens
>
> A handle is a promise to a model: `h.op(...)` means "the row needs the effect of `h`" (§4.4, "An AI reading the function body can verify effect correctness locally"). Each op in this ticket breaks that promise. `term` looks like a handle but has no effect. `fs.errno` is a sixth `fs` op where §4.4.5 says five. `net.connect` returns an `Int`, so `net.write(1, "x")` writes stdout under any row. A model that learns "handle = row" from the spec then writes code that is wrong. My rule: **an op stays a handle op only if the spec can give it a row with no new concept. Otherwise std keeps it internal, and the user sees a std function with a row that the decided rules give.** This proposal adds no new effect and no new rule.
>
> ## Proposal P1: remove all four groups from the user surface; std wrappers take derived rows
>
> **`io.debug`**: delete it from the compiler-known list. It has no codegen and no spec text. A call keeps the plain E0505 it gives today. It needs no removed-name row, because the name never worked.
>
> **`fs.errno`**: internal to std. Best: each raw `@ffi` op in fs_ops returns its errno with its value, so no hidden state is left to read. Interim: a std-private binding with the producer's row (Q2a, `FS.Read`). A user call gives E0505 with the help "the code is in `FsError.code`; match the `Err` of the `fs.*` call". That help is one removed-name row.
>
> **`term.*`**: delete the `term` pseudo-handle. The std.term functions take the S1 fd rows (fd-table-rows), because isatty and TIOCGWINSZ read the state of fd 1 or fd 2:
>
> | fn | row |
> |---|---|
> | `is_tty`, `terminal_width`, `terminal_height` | `IO.Print` (fd 1) |
> | `is_stderr_tty` | the fd-2 row from S1 |
> | `is_fd_tty(fd)` | no sound row for a raw `Int`. Replace it with `is_stdin_tty ! IO.Read` |
>
> These are second-tier functions, so no handler intercepts them (§4.10). Token cost: a CLI that asks for the width almost always prints, so it already has `IO.Print`. The common case adds zero tokens.
>
> MVCE:
> ```blink
> @pure
> fn w() -> Int { term.width() }
> ```
> gives E0505 through a removed-name row: fix `terminal_width()` from `std.term`, effect `IO.Print`. The rewrite is machine-applicable (an import and the call). `@pure` still rejects the fixed code with E0500, which is correct, because the width varies by environment.
>
> **`net.*` fd ops**: internal to std. `TcpSocket`'s methods and the `tcp_*` free fns take rows by the §4.4.6 maker rule. That rule has one consequence that the panel must accept: `TcpSocket` has two makers (`tcp_connect ! Net.Connect`, `accept ! Net.Listen`), so it splits into `TcpStream` and `TcpConn`, the same as `UnixStream`/`UnixConn`. The free fns on a raw `Int` fd (`tcp_read(fd, ...)`, `tcp_close(fd)`) have no sound row. They go away with removed-name rows to the methods. So does the `fd()` method, which gives the raw `Int` back.
>
> ```blink
> import std.net.{tcp_connect, NetError}
> fn go() -> Result[Str, NetError] ! Net.Connect {
>     let s = tcp_connect("localhost", 1)?
>     Ok(s.read(1024))
> }
> ```
> Without `! Net.Connect`, this gives E0500.
>
> Also flag a collision: the compiler's `net.listen(host, port) -> Int` and the §4.4.2 handle op `net.listen(host, port) -> Server` have the same name. A model cannot tell them apart. The internal fd op must get a different name.
>
> **Tradeoffs.** For: one rule ("a handle op has a row; everything else is a std function with a row"). The removed-name table already teaches the fix. Two fewer namespaces to learn. Against: a churn of four names. Also, a mock `Net.Connect` handler cannot intercept TCP. That matches UDP and Unix, but a test author can be surprised by it.
>
> ## Proposal P2 (rejected): add `effect Term`
>
> This adds a sibling effect that a model must choose between `IO.Print` and. It is a new decision point for each CLI program, and no sandbox story needs it. It also leaves `fs.errno` and the raw net ops unsolved.
>
> ## Cross-language
>
> Go and Python expose `isatty`/`fileno` as raw-fd functions, and models copy that idiom. Removing the raw-fd forms stops the training-data prior from leaking in. Rust's `std::net::TcpStream` keeps the raw fd behind `AsRawFd`, outside the common surface. Koka puts its `extern` primitives in std and gives users only the typed wrappers with effects.

- **Minimalism:**

> **What if we just don't?** None of these 17 ops is in sections/. Each one has a single caller (a std
> file), or none. They are plumbing that leaked into the handle namespace. The smallest correct fix
> is to remove the leak, not to make it part of the spec. No new effect, no new handle op, no new
> handler surface.
>
> ## Proposal M1 (preferred): delete every op from the handle surface; std binds the runtime through `@ffi` with honest rows
>
> `fs_ops.bl` already does this for `blink_fs_stat_size` (`@ffi`, row given). Each op becomes a
> private `@ffi` binding in the std file that uses it. All of them are second tier (§4.4 rule 2), so
> no handler intercepts them.
>
> | Group | Fate | Row |
> |---|---|---|
> | `io.debug` | delete from `is_intrinsic_method`. It has no codegen and today gives E0505 | none; plain E0505, no removed-ops row (nothing to migrate) |
> | `fs.errno` | private `@ffi("blink_fs_errno") fn c_fs_errno() -> Int ! FS.Read` in fs_ops.bl | `FS.Read` (Q2a: the interim binding takes the producer's row). The five public `fs` ops do not change |
> | `term.*` | private `@ffi` bindings in term_detect.bl | `is_tty`, `terminal_width`, `terminal_height` get `! IO.Print` (fd 1). `is_stderr_tty` gets `! IO.Log` (fd 2). This is fd-table-rows S1, so no `Term` effect |
> | `is_fd_tty(fd)` | delete it. No caller, and a raw `Int` fd has no knowable producer | none |
> | `net.*` fd ops | private `@ffi` bindings in net_tcp.bl | `tcp_connect ! Net.Connect`. `tcp_listen` / `tcp_accept` / `listener_accept ! Net.Listen`. `TcpSocket` methods and the raw-fd free fns get the union `! Net.Connect, Net.Listen` for now, because two producers make a `TcpSocket` (a sound upper bound by rule 2) |
>
> The TCP type shape (a split into a stream type and a conn type like Unix, or no raw-fd free fns)
> stays the separate TCP question that open-socket-rows names. M1 only makes the TCP rows sound now.
>
> **Removed-ops rows** (the §4.4 table, E0505 with a fix): add only rows that have a replacement:
> `net.connect(h, p)` → `tcp_connect(h, p)` in `std.net`, `Net.Connect`, result changes. `term.width()`
> → `terminal_width()` in `std.term`, `IO.Print`, no change. Do the same for `height`, and map `isatty(1)` → `is_tty()` and `isatty(2)` → `is_stderr_tty()`.
> Do not add `fs.errno` or `io.debug`: their help would be noise.
>
> The MVCE gives E0505, and then the fix gives E1307:
>
> ```blink
> @pure
> fn w() -> Int { term.width() }
> ```
> ```
> error[UnresolvedMethod]: no member `width` on module `term`
>   = fix: terminal_width()   (import std.term.{terminal_width})
>   = help: `terminal_width` needs `IO.Print`
> ```
> After the fix, `@pure fn w() -> Int { terminal_width() }` gives E1307 (ImpureBodyForPureAnnotation).
> If you remove `@pure`, the function gives E0500 until it declares `! IO.Print`. This program is
> correct:
>
> ```blink
> import std.term.{terminal_width}
> import std.net.{tcp_connect}
>
> fn go() -> Bool ! Net.Connect {
>     match tcp_connect("localhost", 1) { Ok(_) => true  Err(_) => false }
> }
> fn main() ! IO.Print, Net.Connect {
>     io.println("{terminal_width()} {go()}")
> }
> ```
>
> **Tradeoffs.** For: the compiler loses 17 special cases in `is_intrinsic_method`,
> `register_ns_intrinsic_sigs` and cg_call. The spec gets no text for ops that it never promised. The
> `Handler[E ! R]` blocker goes away because these are no longer handle ops. `@ffi` rows are already
> the std mechanism. Against: a test cannot mock the terminal width or a TCP read with a handler.
> That is the present state and nobody asked for it. If a need for a mock appears, a `Term` effect
> or TCP handle ops can go to a panel with a real use case. The `TcpSocket` union row is too wide for
> a client-only program. It is sound, and the TCP ticket fixes it. Users of raw `net.connect` break,
> but that op was never in the spec, and the removed-ops row gives the fix.
>
> **Cross-language.** Go has `term.IsTerminal` and `syscall` in the library, not in the language.
> In Rust, `isatty` is `std::io::IsTerminal`, a library trait. In Koka, effects are only what the
> language declares, and the FFI carries the rest. None of them puts errno or fd plumbing in the core
> surface.
>
> ## Proposal M2 (fallback): keep the ops but make them handle ops of existing effects
>
> Map `term.*` → `IO.Print`/`IO.Log`, `fs.errno` → `FS.Read` and `net.*` → `Net.Connect`/`Net.Listen`,
> and add them to §4.4 tables. I oppose this. It adds 17 ops to the spec, it makes the handler surface
> take raw `Int` fds (rule 3 cannot follow an `Int` back to its producer), and §4.4.5 says that `fs`
> has exactly five ops. It is all cost for no user.
>
> **Vote: M1.**

#### Phase B — Debate highlights

Round 1 gave each seat the grouped options. All six seats said the options were stable, so the debate ended after one round. The replies follow in full.

- **Systems:**

> ## Q1: T-S (no change)
>
> plt has a fair point: `is_tty()` gives a wrong answer under a capture handler. But T-H puts four ops on the three most common effects in the language to fix a colour bug in tests. T-S and T-H give the same rows (`IO.Print` for fd 1, `IO.Log` for fd 2), so we can move to T-H later and no user row changes. Under `blink test` no fd is a tty, so the bug does not show there.
>
> No-terminal width: I keep `Int` with 80/24 in this ticket. `Option` is more honest, but it changes the type of a public function and has nothing to do with rows. Log it as friction and send it to its own question.
>
> ## Q2: I concede to N-S
>
> devops is right: §4.4.6 already says "Each socket type has exactly one maker row". `TcpSocket` is a `std.net` socket, so a union row breaks the spec as written. It is not an interim. Split it: `TcpStream ! Net.Connect`, `TcpConn ! Net.Listen`. The raw-fd free fns leave `pub`. I also accept aiml's point that `fd()` goes: a forged `Int` has no sound row. The machine code does not change, because every method is the same `@ffi` call on the boxed fd.
>
> ## Q3: E-H
>
> `fs.errno()` compiled and ran before this change, so real callers can exist, and a migration help for them is not noise. `io.debug` never compiled, so it gets no row.
>
> ## Variations
>
> - **How std reaches the runtime:** private `@ffi`, not a std-only intrinsic allow-list. The C is the same, and `@ffi` already carries a declared row. An allow-list keeps a second, rowless path in the compiler, and that path is how this gap opened.
> - **`fs.errno` in std:** one decl for each producer. I oppose min's single `! FS.Read`. If `fs_do_delete` reads errno through `FS.Read`, its row becomes `FS.Read, FS.Delete`. A sandbox that grants `FS.Delete` alone then cannot delete. The end state (each raw op returns its code) is a std chore, not a spec point.
> - **`net.listen`:** I withdraw "only `listen` stays". The compiler's `net.listen -> Int` is the fd op. The §4.4.2 op returns `Server`. The fd op leaves the handle with the rest, and `tcp_listen` binds it through `@ffi`.
> - **Guard test:** yes. A test should fail if any compiler-known handle op is not in a spec effect decl.
> - **MVCE code:** I concede E1307 for `@pure`. E0500 applies only when `@pure` is absent.
>
> ```blink
> import std.term.{terminal_width}
> @pure
> fn w() -> Int { terminal_width() }
> ```
> → E1307 ImpureBodyForPureAnnotation (`terminal_width` needs `IO.Print`).
>
> ## Writer notes
>
> - The error code for `term.width()` depends on imports. With no `import std.term`, `term` is an unbound name (E0506). With the import, it is E0505 `no member width on module term`. The removed-ops row must fire in both cases, so the table must not be keyed only on E0505.
>
> STABLE: ready to vote

- **Web/Scripting:**

> ## Q1: T-S, unchanged, but I withdraw one argument
>
> My Phase A objection to T-H was wrong. I wrote that every `IO.Print` handler must write the new ops. §4.7.1 auto-delegation (04_effects.md:385) means a handler that omits an op forwards it. So T-H costs user handlers nothing.
>
> I still vote T-S, for two reasons:
> 1. T-S and T-H give the same rows (`IO.Print` for fd 1, `IO.Log` for fd 2). T-S unblocks `Handler[E ! R]` now and does not block T-H later. It is the smaller step for a blocker ticket.
> 2. Auto-delegation also weakens plt's "lies under a mock" point. A user `capture_print` that omits `stdout_is_tty` forwards it to the real handler and still gets "tty". The fix only works when each capture handler writes the op. That is a design for its own panel, with a real TUI test case.
>
> The width when there is no terminal: keep `Int` with 80/24 (Python `shutil.get_terminal_size` does this). `Option[(Int, Int)]` makes the 90% case write a match for every call. If T-H wins, `None` can come with it.
>
> ## Q2: N-S, unchanged
>
> N-U goes against spec text that exists now: "Each socket type has exactly one maker row" (§4.4.6, 04_effects.md:1402). With the union row, every HTTP client must declare `Net.Listen`, and devops showed the second E0500 that the user cannot explain. The split copies a pair (`UnixStream`/`UnixConn`) that users already learn, so it adds no new idea. TCP has no spec text yet, so this is the cheap time to break it.
>
> ## Q3: E-H, weakly
>
> A Python dev looks for `errno`. One help line ("the code is in the `Err(e)` of the fs op: `e.code`") saves a search. If the panel thinks this is noise, I accept E-P. I will not hold the vote for it.
>
> ## Flagged variations
>
> - **How std reaches the runtime:** `@ffi` bindings with rows. That is one mechanism that std already uses, and a reader of std sees the row on the binding. A std-only intrinsic list is a second mechanism.
> - **The code for `term.width()`:** E0505. After `import std.term`, `term` is a module, so "no member `width` on module `term`" is the true message.
> - **`fs.errno` in std:** best, each raw op returns its code. Interim, one binding for each producer (sys/plt). A single `! FS.Read` binding (min) puts `FS.Read` on `fs.write`, which is too wide.
> - **`net.listen`:** rename the internal fd op. Two `net.listen` calls with different result types will cause confusion.
> - **Guard test:** yes.
>
> ## Writer notes
>
> - I concede E1307, not E0500, for the `@pure` MVCE after the fix (ERROR_CATALOG.md:339).
>
> STABLE: ready to vote

- **PLT:**

> ## Q1: concede to T-S
>
> My T-H argument was that a capturing mock should answer "is stdout a tty?". It is weaker than I said. Under auto-delegation, a capture handler that omits `stdout_is_tty` forwards that op to the real runtime, so it gets the same wrong answer as T-S. T-H fixes the problem only for handlers that write the clause. Also, T-S rows are sound under §4.4 Rule 2, and a later `IO` op keeps them unchanged (sys made this point), so T-S does not paint us into a corner. I vote **T-S**. A mockable terminal goes to a later panel, with a use case behind it.
>
> Width with no terminal: I drop `None` from this ticket. It changes the type, and the row question does not need it. File it as its own friction ticket.
>
> ## Q2: hold N-S
>
> N-U breaks a normative sentence that is already in the spec: "Each socket type has exactly one maker row" (§4.4.6). Rule 2 allows a wide row, but that sentence is a separate rule, and a union row on one type with two makers is the case it forbids. "TCP is not in sections/" does not exempt it. Once this ticket gives TCP rows, TCP is in the spec. The split also costs little now, because the only callers are `http_server` and `http_client`. **N-S**, with the raw-`Int` free fns and `fd()` removed from `pub` (aiml).
>
> ## Q3: weak E-H, E-P acceptable
>
> The help line saves one lookup, but it has no call to rewrite to, so it is a note, not a fix. I would not split the vote over it.
>
> ## Variations
>
> - **Mechanism: private `@ffi` bindings, not std-only intrinsics.** A std-only intrinsic is still a compiler-known op. Its row then lives in a compiler table instead of a declaration that the reader can see. That gives two ways to declare a row and an exception in the guard test. With `@ffi` there is one way.
> - **`fs.errno` in std: one decl per producer, or the code returned with the result. Not a single `! FS.Read` decl (min).** `fs_do_write ! FS.Write` cannot call a `! FS.Read` binding without E0500, unless `FS.Read` goes into the row of `fs.write`. That widens a spec row.
> - **`net.listen`**: the §4.4.2 op `-> Server` stays. The `Int`-typed fd form takes a private `@ffi` name, so the two do not collide (aiml, sys).
> - **Guard test**: keep it. It must cover every compiler-known handle op, with no allow-list.
> - **MVCE code after the fix is E1307, not E0500**: `@pure` fails E1307. A function with no `@pure` and no row fails E0500.
>
> ```blink
> import std.term.{terminal_width}
>
> @pure
> fn w() -> Int { terminal_width() }
> ```
> → `error[ImpureBodyForPureAnnotation]` (E1307): `terminal_width` needs `IO.Print`.
>
> ## Writer notes
>
> - The code for `term.width()` depends on scope. With no import, `term` is an unbound name, not a module. With `import std.term`, the call is E0505 "no member `width`". The removed-ops lookup must fire in both cases and give the same fix.
>
> STABLE: ready to vote

- **DevOps/Tooling:**

> ## Q1: T-S
>
> I vote T-S. plt's point is real: under `capture_print`, `is_tty()` says true and colour codes go into the buffer. But the problem exists today. It is a std.term behavior bug, not a row gap, and T-S does not stop a later panel from adding IO ops. T-H adds four ops that every full `IO` handler must cover, and the error a user gets for a missing clause is new surface for a case nobody has reported.
>
> The width when there is no terminal: keep `Int` (80/24) in this ticket. A change to `Option[Int]` breaks every caller (E0308 at each use), so it needs its own std API ticket. Go's `term.GetSize` returns an error for the same reason plt gives, so I do not object to it later.
>
> ## Q2: N-S, held
>
> Under N-U, a client writes `fn fetch() ! Net.Connect, Net.Listen`. When the TCP ticket splits the type, `Net.Listen` becomes extra in every client row, and users must edit each signature a second time. If users must edit their rows, they should do it once. I accept N-U only if this ticket blocks the TCP split ticket, which then lands in the same release.
>
> ## Q3: E-H
>
> A user who calls `fs.errno()` wants the error code. One help line costs nothing:
>
> ```
> error[UnresolvedMethod]: no member `errno` on module `fs`
>   = help: the code is in the `Err(e)` of the fs op: `e.code`
> ```
>
> min calls this noise. It is not: it is the only answer to the question that the user had.
>
> ## Flagged variations
>
> - **How std reaches the runtime: I concede `@ffi` bindings.** `range_bounds` is pure, so it is no precedent for an effectful intrinsic. With `@ffi`, the rows are in std source, where `blink query` and the LSP hover can show them.
> - **Code for `term.width()`: I concede E0505 with a removed-ops row.** It uses the same table as `io.write`.
> - **`fs.errno` in std: one binding per producer (sys/plt) for the interim, and the return code as the end state.** min's single `! FS.Read` decl breaks `fs_do_write ! FS.Write` with E0500, unless std widens `fs.write` to `FS.Read, FS.Write`. That is a wrong row on a public op.
> - **`net.listen`:** the internal fd binding gets a new name (aiml). The spec `net.listen -> Server` stays. File the `-> Int` mismatch as a separate bug.
> - **Guard test: yes.** Every name in `is_intrinsic_method` must be in a spec effect declaration. With `@ffi`, no std-only allow-list is needed.
> - **MVCE after the fix:** E1307, per the catalog. I concede.
>
> ## Writer notes
>
> - Spell the removed-ops rows for `term.isatty(1)` → `is_tty()` and `term.isatty(2)` → `is_stderr_tty()` (min).
>
> NOT STABLE: Q2 (N-S vs N-U) is still open.

- **AI/ML:**

> **Q1: T-S.** plt is right that a second-tier `is_tty()` gives the wrong answer under a capture mock. But T-H has a flaw: §4.3 marks `IO.Read` `@handle_all`. So with `stdin_is_tty`, every user `IO.Read` handler must write a new clause, and auto-delegation does not save it. A model that writes a stdin mock from the §4.4.9 examples then gets an error it cannot predict. sys's point holds: the T-S rows are the same rows that T-H would give, so T-H can go to its own panel later and nothing has to change back. **Width when there is no terminal:** this ticket keeps `-> Int` with 80/24. `Option` is the honest type, but it is a signature change that adds a `match` at each call site, which costs tokens in every CLI. Put it in its own ticket. Do not bundle it here.
>
> **Q2: N-S, unchanged.** §4.4.6 already says "Each socket type has exactly one maker row". `TcpSocket` is a `std.net` socket type, so N-U does not leave a gap open for later. It breaks a rule the spec already has. From my seat: every client snippet with a union row puts `! Net.Connect, Net.Listen` into the code models learn from, and that pattern is wrong. The split costs the same now as it does later, and §4.4.6 has the template (`UnixStream`/`UnixConn` and the mismatch note).
>
> **Q3: E-H.** C, Python and Go programmers type `errno` from habit. A help line that says "read `e.code` in the `Err` of the `fs.*` call" turns a dead end into a one-step fix. That is not noise for a name that models will guess.
>
> **Variations**
> - **How std reaches the runtime:** use `@ffi` bindings with declared rows. Then the row is in the source, where `blink query` and a model can read it. With a std-only allow-list, the row stays hidden inside the compiler, which is the bug this ticket is about.
> - **`fs.errno` in std:** I join sys and plt: one decl for each producer as the interim. A single `! FS.Read` decl would charge `FS.Read` to `fs.write` and `fs.delete`, and that widens two public rows. The end state is that each op returns its errno.
> - **`net.listen`:** the handle op is the §4.4.2 one (`-> Server`). The fd form becomes a private `@ffi` with a different name.
> - **Guard test:** yes. It is the check that keeps the gap from opening again.
> - **MVCE code:** I concede E1307 for `@pure` after the fix (ERROR_CATALOG.md:339). E0500 applies only once `@pure` is removed.
>
> ```blink
> import std.term.{terminal_width}
> @pure
> fn w() -> Int { terminal_width() }
> ```
> → E1307 ImpureBodyForPureAnnotation (`terminal_width` needs `IO.Print`).
>
> ## Writer notes
> - The removed-ops lookup for `term.width()` must fire with and without `import std.term`. With the import, the error is E0505 (no member on module `term`). Without it, the error is whatever an unknown name gives. Each form needs the same fix line. That settles devops's code question with no new option.
> - In the table, write the fd-2 row as S1 gives it (`IO.Log`). Do not paraphrase it as "stderr".
>
> STABLE: ready to vote

- **Minimalism:**

> ## Q1: T-S (hold)
>
> T-H adds four ops to a built-in effect. It also does not fix the lie that plt names. Auto-delegation
> sends `stdout_is_tty` from a partial `capture_print` handler to the outer handler, which is the real
> stdout. So T-H gives the same wrong answer, unless each capture handler writes the op. A capture
> handler that wants plain text can write it as a parameter today:
>
> ```blink
> fn render(msg: Str, color: Bool) -> Str {
>     if color { "\x1b[1m{msg}\x1b[0m" } else { msg }
> }
> ```
>
> No user ticket asks to mock the terminal. If one comes, a panel can add the ops then, with a real
> case. **Width with no terminal:** this ticket is about rows. A change from `Int` to `Option[Int]`
> is a std API change. Keep 80/24 here and file it as its own question.
>
> ## Q2: N-S (I change my position)
>
> The fact at §4.4.6:1402 settles it. "Each socket type has exactly one maker row." My union row
> breaks a rule that the spec already has. A split adds no new concept. It applies the Unix rule a
> second time, and the `UnixConn`/`UnixStream` mismatch note is already there to reuse. I agree with
> aiml that the raw-`Int` free fns, `fd()` and `tcp_socket_from_fd` go away, with removed-name rows to
> the methods. A forgeable `Int` has no sound row, so less surface means less to make sound.
>
> ## Q3: E-H (I change my position)
>
> `fs.errno` shows in completion today, so some user has typed it. One table row whose help is
> "read `e.code` from the `Err`" costs almost nothing. `io.debug` stays plain.
>
> ## Flagged variations
>
> - **How std reaches the runtime:** use `@ffi`. A std-only intrinsic keeps the 17 special cases in
>   the compiler and adds a visibility rule. `@ffi` with a declared row is already the std mechanism.
> - **Code for `term.width()`:** E0505. `term` resolves (std.term is `@module("term")`). "Not a
>   handle" would be a new diagnostic for no gain.
> - **`fs.errno` in std:** my single `! FS.Read` decl was wrong, because it widens `fs.write` and
>   `fs.delete`. I prefer that each raw `@ffi` op returns its code with its result. That needs fewer
>   decls and no hidden thread-local. Per-producer readers are an acceptable interim.
> - **`net.listen`:** it stays, because §4.4.2 names it. The `-> Int` sig against `-> Server` is a
>   compiler bug for a separate ticket, not panel scope.
> - **Guard test:** yes. A unit test checks that `is_intrinsic_method` holds only the spec handle ops.
>   It is cheap, and it keeps this gap closed.
>
> ## Writer notes
>
> - After the fix, the `@pure` MVCE is E1307 (ERROR_CATALOG:339), not E0500.
>
> STABLE: ready to vote

#### Phase C — Silent vote

Each seat voted alone on the three questions.

| Question | Option | Systems | Web/Scripting | PLT | DevOps/Tooling | AI/ML | Minimalism | Result |
|---|---|---|---|---|---|---|---|---|
| Q1 | T-S: second-tier std functions with fd rows; no handler answers them | T-S | T-S | T-S | T-S | T-S | T-S | 6-0 |
| Q2 | N-S: split `TcpSocket` now | N-S | N-S | N-S | N-S | N-S | N-S | 6-0 |
| Q3 | E-H: E0505 with a removed-names row and a help line | E-H | E-H | E-H | E-H | E-H | E-H | 6-0 |

- **Systems:**

> ## Q1. Terminal queries
>
> **Vote:** T-S
>
> **Reasoning:** Each query compiles to one direct `@ffi` call (`isatty` or `ioctl`). There is no dispatch point and no spec surface. The rows (`IO.Print` for fd 1, `IO.Log` for fd 2) come straight from fd-table S1, so this needs no new rule. T-H gives the same rows, so moving to it later changes no user signature. A real request for mock-friendly terminal queries can pay for that change when it comes.
>
> **Concern:** A program running in a real terminal under a capture handler still sees `is_tty()` as true, so it puts colour escapes in the buffer it captures, and someone will file that as a bug.
>
> ## Q2. TCP socket types
>
> **Vote:** N-S
>
> **Reasoning:** §4.4.6 already says that each socket type has exactly one maker row, so N-U breaks the spec as written. It is not an interim. Under N-U, a client must declare `Net.Listen`, and a sandbox that denies `Net.Listen` blocks every HTTP client. That is a real loss of attenuation. The split costs nothing at run time: both types wrap the same fd box and call the same `@ffi` symbols.
>
> **Concern:** If `fd()` leaves `pub`, std callers that need the raw fd (poll/epoll integration, http_server) must get it through a private path. A careless port could reach for a pub escape hatch again.
>
> ## Q3. A user call to `fs.errno()`
>
> **Vote:** E-H
>
> **Reasoning:** `fs.errno()` compiled and ran before this change, so real callers can exist, and a one-line help that points at `e.code` costs one table row. It also stops a user from reaching for a thread-local errno idiom, which is the very thing a mock `FS` handler cannot honour.
>
> **Concern:** The help assumes that the user has the `Err(e)` of the fs op in hand. Code that called a raw op and then `fs.errno()` has no `Result` to match on, so the fix is a suggestion, not machine-applicable.

- **Web/Scripting:**

> ## Q1. Terminal queries
>
> **Vote:** T-S
>
> **Reasoning:** A CLI that checks for a tty before it adds color already declares `! IO.Print`, so the 90% user writes no new row and learns no new op. T-S and T-H give the same rows. T-S unblocks `Handler[E ! R]` now, and T-H can still come later as an additive change. With auto-delegation, T-H answers correctly only when each capture handler implements the new ops. That needs its own panel and a real TUI test case.
>
> **Concern:** A user who writes a capturing `IO.Print` mock can still see `is_tty()` return `true` and get colored text in the buffer. The spec or docs must say that no handler intercepts the tty queries.
>
> ## Q2. TCP socket types
>
> **Vote:** N-S
>
> **Reasoning:** N-U goes against current spec text, §4.4.6: "Each socket type has exactly one maker row". It also makes every HTTP client declare `Net.Listen`, and no JS or Python dev could explain that second E0500. The split copies the `UnixStream`/`UnixConn` pair that users already know, so it adds no new idea. TCP has no spec text yet, so a break costs the least now.
>
> **Concern:** Two types for one wire protocol can confuse a newcomer who wants "a socket". The mismatch note ("`TcpStream` is made by `tcp_connect`") must be as clear as the Unix one.
>
> ## Q3. A user call to `fs.errno()`
>
> **Vote:** E-H
>
> **Reasoning:** A dev from Python or C who wants the OS error looks for `errno` first. One help line that points at `e.code` saves a web search, and it costs one table row. A plain E0505 tells them only what is missing, not where the code went.
>
> **Concern:** If E-P wins, the docs for `FsError` must show `e.code` near the top, or users will file "where is errno" questions.

- **PLT:**

> ## Q1: Terminal queries
>
> **Vote:** T-S
>
> **Reasoning:** T-S rows are a sound upper bound under §4.4 Rule 2, and they come from the decided fd-table S1 rule. So they need no new concept. T-H fixes a capturing mock only when the handler writes the clause. A handler that omits it forwards the query to the real runtime (auto-delegation), which gives the same answer as T-S. Later `IO` ops would keep these rows unchanged, so T-S leaves that path open.
>
> **Concern:** a capture handler that colours output gets a real `is_tty()` answer for a stream that does not reach the terminal. That answer is wrong, and no diagnostic flags it.
>
> ## Q2: TCP socket types
>
> **Vote:** N-S
>
> **Reasoning:** §4.4.6 says, as a normative rule, "Each socket type has exactly one maker row". N-U is the exact case that rule forbids: one type with two makers that have different rows. Rule 2 permits a wide row, but it does not override a separate rule. N-U also makes every client name `Net.Listen`, a capability it never uses. The raw-`Int` free fns must also leave `pub`. An `Int` is forgeable, so no maker row can be shown for it.
>
> **Concern:** a later trait over both TCP stream types must take the union row, and each impl narrows it (E0904). If the split does not leave room for that, `http_*` code that is generic over both types becomes clumsy.
>
> ## Q3: A user call to `fs.errno()`
>
> **Vote:** E-H
>
> **Reasoning:** a removed-ops row turns a dead end into a pointer to the place the value now lives, `FsError.code`. This keeps the §4.4 table complete for every op that the compiler once accepted. The row has no call to rewrite to, so it is a note and not a machine fix. The stakes are low.
>
> **Concern:** a row with no rewrite can teach a tool or model to expect a machine-applicable fix where there is none.

- **DevOps/Tooling:**

> ## Q1. Terminal queries
>
> **Vote:** T-S
>
> **Reasoning:** T-S gives these functions honest rows. It adds no new handler surface, so it adds no new diagnostic for a missing handler clause. The capture-and-colour problem exists today, and it is a std.term behavior question. A later panel can add IO ops without a change to these rows. T-H makes every full `IO` handler write four more clauses before any user has asked for them.
>
> **Concern:** under `capture_print`, `is_tty()` still says true, so colour codes go into captured golden output. Someone needs to log that as a std.term friction ticket so it does not get lost.
>
> ## Q2. TCP socket types
>
> **Vote:** N-S
>
> **Reasoning:** with N-U, every TCP client writes `Net.Listen` in its row now. When the split lands, those users must edit each signature a second time. If users must change their rows, they should do it once. The Unix pair already has the type-mismatch note ("`X` is made by `Y`"), so the split gets a good diagnostic for free.
>
> **Concern:** if N-U wins, the split ticket must block a release. If not, the extra `Net.Listen` stays in every user signature.
>
> ## Q3. A user call to `fs.errno()`
>
> **Vote:** E-H
>
> **Reasoning:** a user who calls `fs.errno()` wants the error code, and one help line sends them straight to `e.code`. A plain E0505 forces them to find out the `Result` design on their own. The row costs one table entry.
>
> **Concern:** if each raw op later returns its code and `FsError` changes shape, the help line must point to the new field, or it gives wrong advice.

- **AI/ML:**

> ## Q1. Terminal queries
> **Vote:** T-S
> **Reasoning:** The rows come straight from fd-table S1, so a model learns no new op and no new rule. A normal CLI already declares `IO.Print`, so the common case costs zero extra tokens. T-H adds `stdin_is_tty` to the `@handle_all` effect `IO.Read`. Then every stdin mock that a model writes from the §4.4.9 examples fails with an error it cannot predict. The T-S rows are the rows T-H would give, so T-H can still come later and nothing changes back.
> **Concern:** A model that writes a capture mock for `IO.Print` will expect `is_tty()` to answer `false` under the mock. It gets the real terminal instead. The spec text must say this plainly, or golden tests of coloured output will fail without warning.
>
> ## Q2. TCP socket types
> **Vote:** N-S
> **Reasoning:** §4.4.6 already says "Each socket type has exactly one maker row", so N-U breaks a spec rule that is in force. It does not defer an open question. The union row would put `! Net.Connect, Net.Listen` on every TCP client snippet, and models learn that wrong pattern. The split matches the `UnixStream`/`UnixConn` pair, so a model learns one shape for both socket families.
> **Concern:** The split breaks every caller of `TcpSocket` and of the raw-fd free fns, http_server/http_client included. If the removed-name rows and the mismatch note do not ship in the same change, users and models get a bare type error with no fix.
>
> ## Q3. A user call to `fs.errno()`
> **Vote:** E-H
> **Reasoning:** C, Python and Go habits make `errno` a name models will guess. A one-line help that points at `e.code` turns a dead end into a one-step fix. It costs one row in a table that already exists.
> **Concern:** The fix changes the shape of the code (a `match` on the `Err` of the fs call), so it must stay a suggestion. If tooling marks it machine-applicable, it will produce code that does not compile.

- **Minimalism:**

> ## Q1. Terminal queries
> **Vote:** T-S
> **Reasoning:** T-H adds four ops to a built-in effect, and no user ticket asks for them. Auto-delegation
> also sends the ops of a partial capture handler to the real stdout, so T-H still gives the wrong answer
> unless each capture handler writes the ops. T-S makes the rows sound with no new spec surface. If a real
> mock need appears, a panel can add the ops later. To remove an op after users depend on it is harder.
> **Concern:** A program that colours output under a capture handler still sees the real stdout's TTY state,
> and nothing tells the user that the query ignores the handler.
>
> ## Q2. TCP socket types
> **Vote:** N-S
> **Reasoning:** §4.4.6 already says that each socket type has exactly one maker row, and N-U breaks that
> rule. The split adds no concept: it applies the Unix rule a second time and reuses the mismatch note that
> exists. When the raw-`Int` free fns and `fd()` go, the surface gets smaller, and a forgeable `Int` has no
> sound row to give.
> **Concern:** The split breaks every `TcpSocket` user, inside std (http_server/http_client) and outside it,
> in one change. The removed-name rows must cover each raw-fd fn, or users get bare E0504s.
>
> ## Q3. A user call to `fs.errno()`
> **Vote:** E-H
> **Reasoning:** `fs.errno` shows in completion today, so some user may have typed it. One table row that
> points to `e.code` costs almost nothing, and it tells the user what replaces the op.
> **Concern:** The row stays in the table for good (§4.4 keeps removed names permanently), so it is a small
> permanent cost for an op that the spec never had.

#### Phase D — Not triggered

All three questions had a 6-0 result in Phase C. There was no Phase D.

### Dissent

None. Every seat voted for the winning option on all three questions.

### Final Spec

Terminal queries (§4.4.11):

- `is_tty()`, `terminal_width()` and `terminal_height()` are std functions with the row `IO.Print`. `is_stderr_tty()` has the row `IO.Log`. They are second-tier (§4.4 rule 2). No handler answers them: under a capture handler, `is_tty()` still answers for the real terminal.
- With no terminal, the width is 80 and the height is 24. The result stays `Int`.
- `is_fd_tty(fd)` is not public.

TCP sockets (§4.4.6):

- `tcp_connect` returns `TcpStream` with `Net.Connect`. `TcpListener.accept` returns `TcpConn` with `Net.Listen`. `tcp_listen` returns `TcpListener` with `Net.Listen`. The methods of each type take the row of the function that made it. `TcpSocket` does not exist.
- The raw `Int` free functions and `fd()` are not public. The removed-names table points each raw function to the method.
- The type-mismatch note names the maker of each type, as it does for `UnixConn` and `UnixStream`.

Last error code (§4.4.5, §4.4):

- The `fs` handle has no `errno` operation. A call is E0505 with a removed-names row whose help points to the code in the `Err`. The row is not machine-applicable.

Shared (§4.4):

- `io.debug` leaves the compiler-known list. A call is E0505 with no row.
- `fs.errno`, `term.*` and the raw `net.*` descriptor operations leave the handle surface. Std reaches them with private bindings that have declared rows. No new effect and no new rule.
- Removed-names rows: `net.connect` to `tcp_connect`; `term.width` and `term.height` to `terminal_width` and `terminal_height`; `term.isatty(1)` to `is_tty()`; `term.isatty(2)` to `is_stderr_tty()`. The `term.width()` lookup applies with and without `import std.term`: E0505 with the import and E0506 without it, with the same fix.
- `net.listen -> Server` in §4.4.2 stays. A form with an `Int` descriptor gets a private name.
- Every compiler-known handle op is in a spec effect declaration, with no list of exceptions (§4.4 *Every handle op is in a declaration*).
- Inside std, `fs.errno` has one binding for each producer row (`FS.Read`, `FS.Write`, `FS.Delete`) for now. An end state where each raw operation returns its own code is the aim.

### Amendments

None.

### Implementation notes

- The spec text says the help of the `fs.errno()` row is `e.errno.code`, because the spec names the field of `FsError` `errno` (§4.4.5). The panel text wrote `e.code`. The library `FsError` has a field `code` today. The spec and the library differ; the implementation ticket must settle which name is right before the help line ships.
- The rows for `term.isatty(1)` and `term.isatty(2)` match the literal argument. Another argument has no row and no fix. The panel did not say what a call with another argument gives; this record picks plain E0505 or E0506, with no fix.
- The rows for the raw TCP free functions (`tcp_read`, `tcp_read_all`, `tcp_read_bytes`, `tcp_write`, `tcp_write_bytes`, `tcp_set_timeout`, `tcp_close`, `tcp_accept`) and for `listener_accept` follow from Q2. The panel did not list them one by one.
- `fd()`, `tcp_socket_from_fd` and `tcp_listener_from_fd` have no replacement, so they have no row.
- The spec fixes the names and rows of the TCP methods. It does not fix their result types.
- A test must check that every compiler-known handle op is in a spec effect declaration, with no list of exceptions.

### Open cases and follow-ups

These were raised in the panel and not decided:

- **`terminal_width()` and `terminal_height()` with no terminal.** They return `Int` (80 and 24) in this change. A later change can make them return an `Option` when there is no terminal.
- **`net.listen` has the type `-> Int` in the compiler.** Section 4.4.2 says `listen(host, port) -> Server`. The compiler and the spec differ.
- **Mockable terminal queries.** A capture handler cannot answer `is_tty()` or the width today (PLT, Minimalism). A later change can add handler operations for the terminal queries.
