[< All Decisions](../DECISIONS.md)

# Accept With a Wait and the Peer User Id on Unix-Domain Sockets — Design Rationale

### Panel Deliberation

The ticket (verbatim, with the reference to the ticket that it blocks removed):

> **Title:** std.net Unix API: spec has no row for accept with a timeout or for the peer uid (daemon needs both)
>
> sections/04_effects.md §4.4.6 and the Removed free functions table map unix_socket_listen/accept/connect/close and socket_read_line/socket_write to unix_listen/unix_connect/UnixStream methods. unix_socket_accept_timeout and unix_socket_peer_uid have no row. src/daemon.bl uses both, so the src migration off the raw builtins cannot finish without an answer: what is the API (for example listener.accept_timeout(ms) -> Result[Option[UnixConn], NetError], conn.peer_uid() -> Result[Int, NetError]), and which Net effect op holds each?

The filer's example API did not limit the panel. The compiler's own daemon (`src/daemon.bl`) is the one caller today. It uses `unix_socket_accept_timeout` (the call gives `-1` for a timeout and for an error) and reads the peer uid on an accepted connection and on a connected client stream through two `@ffi` bindings of one runtime call. The runtime call uses `SO_PEERCRED` on Linux and `getpeereid(2)` on macOS and the BSDs. It gives `-1` when the call fails and `-2` where the platform has no such call. `lib/std/net_unix.bl` has `accept` and no accept with a wait and no `peer_uid`.

Questions:

- Q1: the shape of an accept with a wait. **1A:** a second method `accept_timeout`; a timeout is `Ok(None)`. **1B:** a `timeout:` keyword on `accept`; a timeout is `Err(NetError.Timeout(msg))`.
- Q1w: the type of the wait argument. **W-D:** `Duration`. **W-I:** `ms: Int`, like `UdpSocketOps.set_timeout`.
- Q2: `peer_uid` where the platform has no such call. **2A:** `Result[Int, NetError]`; gives `Err(Os(op: "peer_uid", code: ENOTSUP))`. **2B:** `Result[Int?, NetError]`; gives `Ok(None)`.
- Q3: a probe that needs no socket. **3A:** add `unix_peer_uid_supported() -> Bool`; `false` if and only if `peer_uid` gives `ENOTSUP`. **3B:** no probe.
- Q4: a Removed-free-functions row for `unix_socket_peer_uid`. **4A:** no row. **4B:** a row that maps it to `conn.peer_uid()` and `stream.peer_uid()`.

Quotes below are verbatim copies of each seat's reply, whole except its title line. Two lines that named a task-tracker ticket are cut and marked with "…".

#### Phase A — Independent proposals

Five seats (sys, web, plt, devops, aiml) proposed a second method `accept_timeout` that gives `Ok(None)` at the limit. Min proposed a `timeout: Duration?` keyword on `accept` that gives `Err(Timeout)`. On the wait type, sys, web, plt and aiml proposed `ms: Int`; devops and min proposed `Duration`. On the uid, sys, plt, devops and min proposed `Result[Int, NetError]` with `Err(Os(op: "peer_uid", code: ENOTSUP))` where the platform has no call; web and aiml proposed `Result[Int?, NetError]` with `Ok(None)`. The seats differed on whether a probe is needed.

- **Systems:**

  > ## Proposal S1 (my pick): a per-call accept deadline, and peer_uid as a plain Result
  >
  > ```blink
  > pub trait UnixListenerOps {
  >     fn accept(self) -> Result[UnixConn, NetError] ! Net.Listen
  >     fn accept_timeout(self, ms: Int) -> Result[UnixConn?, NetError] ! Net.Listen
  >     fn close(self) ! Net.Listen
  > }
  > // UnixConnOps gets:   fn peer_uid(self) -> Result[Int, NetError] ! Net.Listen
  > // UnixStreamOps gets: fn peer_uid(self) -> Result[Int, NetError] ! Net.Connect
  > ```
  >
  > Both rows come from the maker rule as it stands. `peer_uid` reads kernel state of the fd and sends nothing, so it takes the maker row. No new rule is needed.
  >
  > **accept_timeout behavior**
  > - A client within `ms`: `Ok(Some(conn))`. No client in time: `Ok(None)`. A timeout is the normal result of a poll loop, not an error, so it is not `Err(Timeout)`.
  > - `ms == 0`: one check, no wait. `ms < 0`: `Err(Os(op: "accept", code: EINVAL))`, checked first. Poll reads a negative value as "wait for ever"; `accept()` does that already, so the negative case must not silently become a second spelling of it.
  > - Closed listener: `Err(Os(op: "accept", code: EBADF))`, the same as `accept`.
  > - EINTR in poll: retry with the time that is left on a monotonic deadline. Do not report it as a timeout.
  > - Fix to the runtime, which today returns -1 for a timeout, an error and EINTR alike. It must return the real errno. It must also not block after poll: if a second thread or process accepts first, a blocking `accept()` hangs past the deadline. Do the accept with the fd non-blocking for that call (or keep the listener non-blocking), and map EAGAIN to `Ok(None)`.
  > - Cost: one `poll` + one `accept`. No allocation on the `None` path (`Option` of a one-field struct).
  >
  > **peer_uid behavior**
  > - Linux: `SO_PEERCRED`. macOS and the BSDs: `getpeereid(2)`. Success is `Ok(uid)`. A failure is `Err(Os(op: "peer_uid", code: errno))`.
  > - A platform with no such call: `Err(Os(op: "peer_uid", code: ENOTSUP))`, always, before the fd is looked at. This is how `process.run` reports a limit the host cannot enforce (§4.4.8).
  > - Why not `Ok(None)` for "unsupported": this is a security check. With `Err`, the short form `match conn.peer_uid() { Ok(u) => u == own, Err(_) => false }` fails closed. A caller who wants the daemon's fallback must name `ENOTSUP`. A `None` arm invites `.unwrap_or(own)`, which fails open.
  > - Cost: one `getsockopt`, no allocation. `uid_t` is 32 bits unsigned, so `Int` holds every value.
  >
  > **The daemon, rewritten**
  >
  > ```blink
  > import std.net.{NetError, UnixListener, UnixConn}
  > import std.libc.{ERR_NOTSUP}
  >
  > fn peer_allowed(uid: Result[Int, NetError], own: Int) -> Bool {
  >     match uid {
  >         Ok(u) => u == own
  >         Err(NetError.Os(op, code)) => match code {
  >             Errno(c) => c == ERR_NOTSUP
  >         }
  >         Err(_) => false
  >     }
  > }
  >
  > fn accept_own(l: UnixListener, ms: Int, own: Int) -> Result[UnixConn?, NetError] ! Net.Listen {
  >     match l.accept_timeout(ms)? {
  >         None => Ok(None)
  >         Some(conn) => {
  >             if peer_allowed(conn.peer_uid(), own) {
  >                 return Ok(Some(conn))
  >             }
  >             conn.close()
  >             Ok(None)
  >         }
  >     }
  > }
  > ```
  >
  > `daemon_peer_check_supported` becomes a call on a real stream: `!is_notsup(stream.peer_uid())`. The trick of calling the runtime on -1 goes away.
  >
  > **Removed-free-functions row**
  >
  > | Removed name | Replacement | Effect | Result changes |
  > |---|---|---|---|
  > | `unix_socket_accept_timeout(l, ms)` | `listener.accept_timeout(ms)` in `std.net` (§4.4.6) | `Net.Listen` | yes: `Int` becomes `Result[UnixConn?, NetError]` |
  >
  > Not machine-applicable: the `Int` fd becomes a `UnixListener` receiver, and each `>= 0` check must change. `unix_socket_peer_uid` needs no row. It is not a compiler builtin (typecheck and cg_call know only `unix_socket_accept_timeout`). The daemon binds `blink_unix_socket_peer_uid` itself through `@ffi`, so no user program can call that name.
  >
  > ## Rejected: S2, `listener.set_timeout(ms)` + `Err(NetError.Timeout)`
  >
  > This matches `UdpSocket.set_timeout`, but:
  > - It puts state in the shared fd box, so every copy of the listener changes. That is action at a distance.
  > - `SO_RCVTIMEO` on a listening socket: Linux applies it to `accept`, but the BSDs and macOS do not apply it reliably. So the runtime needs poll anyway, and the setter only hides that.
  > - The daemon then must match `Timeout` in each loop, as a normal result dressed as an error.
  >
  > ## Cross-language
  >
  > Go: `SetDeadline` + a timeout error (that is the stateful S2 shape). Rust std has no accept timeout. People set non-blocking mode and poll, which is S1 done by hand. Rust `UCred` (unstable) and Go `GetsockoptUcred` are Linux-only. A credentials record with pid/gid is YAGNI: `getpeereid` gives no pid, so a record would be partial on macOS on day one.

- **Web/Scripting:**

  > ## Proposal W1 (my pick): a timeout gives `None`, the uid gives `Int?`
  >
  > ```blink
  > pub trait UnixListenerOps {
  >     fn accept(self) -> Result[UnixConn, NetError] ! Net.Listen
  >     fn accept_timeout(self, ms: Int) -> Result[UnixConn?, NetError] ! Net.Listen
  >     fn close(self) ! Net.Listen
  > }
  > // UnixConnOps:   fn peer_uid(self) -> Result[Int?, NetError] ! Net.Listen
  > // UnixStreamOps: fn peer_uid(self) -> Result[Int?, NetError] ! Net.Connect
  > pub fn unix_peer_uid_supported() -> Bool ! ()
  > ```
  >
  > `accept_timeout(ms)`:
  > - A client before `ms` ends: `Ok(Some(conn))`.
  > - No client before `ms` ends: `Ok(None)`. A timeout is not an error. A poll loop gets one every lap, and an error you `match` away on each lap is noise.
  > - `ms == 0` checks once and returns at once. `ms < 0` gives `Err(Os(op: "accept", code: EINVAL))`. I do not want a "negative means forever" rule: `accept()` already does that, and a JS/Python dev does not guess the rule.
  > - EINTR waits again for the time that is left. A closed listener gives `Os(op: "accept")` with `EBADF`, the same as `accept`.
  >
  > `peer_uid()`:
  > - Linux (SO_PEERCRED), macOS and the BSDs (getpeereid): `Ok(Some(uid))`.
  > - A platform with no such call: `Ok(None)`. Code that checks `== Some(me)` then refuses the peer, which is the safe default. Only code that asks for "allow" gets it.
  > - The call failed: `Err(Os(op: "getsockopt" or "getpeereid", code))`. Closed: `EBADF`.
  > - `unix_peer_uid_supported()` is a fact of the target, so its row is `! ()`. The client side of the daemon needs it before it has a socket (`daemon_proc_identity`).
  >
  > Rows follow the open-socket-rows rule with no new case: the maker's row.
  >
  > ```blink
  > import std.net.{UnixListener, UnixConn, NetError}
  >
  > // A client within ms that the daemon may serve. Another user's connection is closed unread.
  > fn accept_own(l: UnixListener, ms: Int, own: Int) -> Result[UnixConn?, NetError] ! Net.Listen {
  >     let conn = match l.accept_timeout(ms)? {
  >         Some(c) => c
  >         None => return Ok(None)
  >     }
  >     let allowed = match conn.peer_uid() {
  >         Ok(Some(uid)) => uid == own
  >         Ok(None) => true
  >         Err(_) => false
  >     }
  >     if !allowed {
  >         conn.close()
  >         return Ok(None)
  >     }
  >     Ok(Some(conn))
  > }
  > ```
  >
  > An old call gives E0504:
  >
  > ```
  > error[E0504]: undefined function `unix_socket_accept_timeout`
  >   = help: use `listener.accept_timeout(ms)` on `UnixListener` in `std.net` (§4.4.6)
  >   = note: needs `Net.Listen`; `Int` becomes `Result[UnixConn?, NetError]`
  > ```
  >
  > Removed-free-functions rows (neither is machine-applicable: an `Int` fd becomes a typed socket, and `-1`/`-2` become `None`/`Err`):
  >
  > | Removed name | Replacement | Effect | Result changes |
  > |---|---|---|---|
  > | `unix_socket_accept_timeout(l, ms)` | `listener.accept_timeout(ms)` | `Net.Listen` | yes: `Int` becomes `Result[UnixConn?, NetError]` |
  > | `unix_socket_peer_uid(s)` | `conn.peer_uid()` on `UnixConn`; `stream.peer_uid()` on `UnixStream` | `Net.Listen` on `UnixConn`, `Net.Connect` on `UnixStream` | yes: `Int` becomes `Result[Int?, NetError]` |
  >
  > ## Proposal W2 (fallback): `set_timeout` on the listener
  >
  > `UnixListener.set_timeout(ms) ! Net.Listen`, then `accept()` gives `Err(NetError.Timeout(...))`. This matches `UdpSocket.set_timeout` and the §4.4.6 rule "EAGAIN after `set_timeout` is `Timeout`". The cost: each loop needs a third `match` arm, and the daemon calls with 0, 1 and 500 ms, so it must call `set_timeout` before each `accept`. That is hidden state, and a hidden-state bug is a Stack Overflow question.
  >
  > ## Tradeoffs
  >
  > - W1 adds two methods and one free function. A dev reads `UnixConn?` and knows a timeout is normal. W2 is one setter but moves the timeout into `Err`, which `?` then sends up the stack by mistake.
  > - `Int?` for "the platform cannot say" puts the choice in plain sight. An errno `ENOTSUP` would make each caller match on a magic code.
  > - No credentials record (pid, gid): macOS gives no pid, and the daemon needs only the uid. Add a record when a user asks. A record would replace nothing here.
  >
  > ## Other languages
  >
  > Python: `sock.settimeout(t); sock.accept()` raises `socket.timeout` (W2's shape). Most Python code catches it on each lap, which is the noise W1 removes. Rust: `UnixStream::peer_cred() -> io::Result<UCred>`, and `Unsupported` is an error kind. Go: `SetDeadline`, then `err.Timeout()`. Node has no peer-credential API.

- **PLT:**

  > ## Proposal P1 (recommended): `accept_timeout` returns an Option; `peer_uid` on the two connected types; a pure support query
  >
  > ```blink
  > pub trait UnixListenerOps {
  >     fn accept(self) -> Result[UnixConn, NetError] ! Net.Listen
  >     fn accept_timeout(self, ms: Int) -> Result[UnixConn?, NetError] ! Net.Listen
  >     fn close(self) ! Net.Listen
  > }
  > // added to UnixConnOps:   fn peer_uid(self) -> Result[Int, NetError] ! Net.Listen
  > // added to UnixStreamOps: fn peer_uid(self) -> Result[Int, NetError] ! Net.Connect
  > pub fn unix_peer_uid_supported() -> Bool ! ()
  > ```
  >
  > What each one does:
  > - `accept_timeout(ms)`: `Ok(Some(conn))` when a client connects within `ms`. `Ok(None)` when no client connects in that time. A timeout is an expected result of a poll loop, not a failure. It is `None`, as end of stream is `None` from `read_line`, so `?` cannot pass it up as an error by mistake. `ms == 0` polls once. `ms < 0` gives `Err(Os(op: "accept", code: EINVAL))`, because waiting with no limit is `accept()`. On EINTR the call waits again for the time that is left. A closed listener gives `EBADF`, the same as `accept`.
  > - `peer_uid()`: `Ok(uid)` from SO_PEERCRED (Linux) or getpeereid(2) (macOS, BSDs). A failed call gives `Err(Os(op: "peer_uid", code: errno))`. On a platform that has no such call it gives `Err(Os(op: "peer_uid", code: ENOTSUP))`.
  > - `unix_peer_uid_supported()` is a constant of the target, so its row is `! ()`. The daemon asks it before it connects (`daemon_proc_identity`). Today it asks by giving fd -1 to the call. A typed API cannot do that, because no socket value exists yet.
  > - `UnixListener` has no `peer_uid`. A listener has no peer, so the type removes the case where the call can never succeed.
  >
  > Rows follow open-socket-rows: the maker row and nothing more. The rule gives each row, so no new rule is needed.
  >
  > ```blink
  > import std.net.{UnixListener, UnixConn, NetError, unix_peer_uid_supported}
  >
  > fn accept_own(l: UnixListener, ms: Int, own: Int) -> Result[UnixConn?, NetError] ! Net.Listen {
  >     let conn = match l.accept_timeout(ms)? {
  >         Some(c) => c
  >         None => return Ok(None)
  >     }
  >     if !unix_peer_uid_supported() {
  >         return Ok(Some(conn))
  >     }
  >     match conn.peer_uid() {
  >         Ok(uid) => {
  >             if uid == own { return Ok(Some(conn)) }
  >         }
  >         Err(_) => {}
  >     }
  >     conn.close()          // another user, or a failed check: closed unread
  >     Ok(None)
  > }
  > ```
  >
  > The old name gives this error:
  > ```
  > error[UndefinedFunction]: undefined function `unix_socket_accept_timeout`
  >   = help: use `listener.accept_timeout(ms)` on `UnixListener` (std.net, §4.4.6)
  >   = note: needs `Net.Listen`; `Int` becomes `Result[UnixConn?, NetError]`
  > ```
  >
  > **Removed free functions** (one row only):
  >
  > | Removed name | Replacement | Effect | Result changes |
  > |---|---|---|---|
  > | `unix_socket_accept_timeout(l, ms)` | `listener.accept_timeout(ms)` | `Net.Listen` | yes: `Int` becomes `Result[UnixConn?, NetError]` |
  >
  > This fix is not machine-applicable: the receiver changes from an `Int` fd to a `UnixListener`.
  >
  > Check this assumption in the ticket: `unix_socket_peer_uid` was never a Blink name. It is not in `cc_builtin_free_table` (src/cg_call.bl:1754). The daemon reaches the C symbol through its own `@ffi`. The table lists removed Blink names, so a row for this name would teach a name that never existed. Give it no row.
  >
  > Tradeoffs:
  > - The support query and `ENOTSUP` say the same fact twice. I accept this. The query answers before a socket exists. `ENOTSUP` keeps `peer_uid` total on every target.
  > - `ms: Int` matches `UdpSocketOps.set_timeout(ms: Int)`. A `Duration` from std.time has more types in it. But if only one socket method took a `Duration`, the API would not agree with itself. Change both later, or neither.
  > - `Int`, not a `Uid` newtype. A newtype helps only when `env` gives a `Uid` to compare with. That is out of scope (YAGNI).
  >
  > ## Rejected P2: `listener.set_timeout(ms)` as on UDP
  >
  > The fd box is shared by every copy of the socket. So a set timeout is shared state that changes what `accept()` means, and the type does not show it. `accept` would then have to report a timeout as an `Err`, so `?` passes it up as a failure. A call-site argument keeps the contract of `accept` the same everywhere. Note for the writer: §4.4.6 does not say what `recv_from` returns after `set_timeout` expires. That is a separate gap.
  >
  > Cross-language: Rust `UnixStream::peer_cred` returns `io::Result<UCred>`. OCaml/Go give a timeout as an error value. Here it is `Option`, as in Koka-style total APIs, because a timeout in a poll loop is a normal result, not a failure.

- **DevOps/Tooling:**

  > ## Proposal D1 (I recommend this): a timeout gives `None`, an unsupported platform gives `ENOTSUP`
  >
  > ```blink
  > pub trait UnixListenerOps {
  >     fn accept(self) -> Result[UnixConn, NetError] ! Net.Listen
  >     fn accept_timeout(self, timeout: Duration) -> Result[UnixConn?, NetError] ! Net.Listen
  >     fn close(self) ! Net.Listen
  > }
  > // UnixConnOps:   fn peer_uid(self) -> Result[Int, NetError] ! Net.Listen
  > // UnixStreamOps: fn peer_uid(self) -> Result[Int, NetError] ! Net.Connect
  > pub fn unix_peer_uid_supported() -> Bool ! ()
  > ```
  >
  > How it behaves:
  > - `accept_timeout`: `Ok(Some(conn))` when a client connects, and `Ok(None)` when the time runs out. A timeout is not an error, because a daemon loop expects it on every idle tick. `Duration.ms(0)` polls once. A negative duration gives `Os(op: "accept", EINVAL)`. An EINTR retries with the time that is left. A closed listener gives `EBADF`, the same as `accept`.
  > - `peer_uid`: `Ok(uid)`. A failed call gives `Os(op: "peer_uid", code)`. A platform with no such call gives `Os(op: "peer_uid", ENOTSUP)` (SO_PEERCRED on Linux, getpeereid on macOS and the BSDs). This is the `process.can_limit` pattern: `ENOTSUP` comes back exactly when `unix_peer_uid_supported()` is `false`. That function is a fixed fact about the platform, so it has no row, and a client can ask it before it connects (the daemon does this in `daemon_peer_check_supported`).
  > - Rows: each row comes from the maker rule. There is no new rule and no new Net op.
  >
  > ```blink
  > fn accept_own(l: UnixListener, wait: Duration) -> Result[UnixConn?, NetError] ! Env.Read, Net.Listen {
  >     let conn = match l.accept_timeout(wait)? {
  >         Some(c) => c
  >         None => return Ok(None)
  >     }
  >     let allowed = match conn.peer_uid() {
  >         Ok(uid) => uid == env.uid()
  >         Err(NetError.Os(op: _, code: c)) => c == ENOTSUP
  >         Err(_) => false
  >     }
  >     if !allowed {
  >         conn.close()
  >         return Ok(None)
  >     }
  >     Ok(Some(conn))
  > }
  > ```
  >
  > (`env.uid()` stands in for the daemon's `getuid` binding. That needs a ticket of its own.)
  >
  > The error when the caller forgets the timeout case:
  >
  > ```
  > error[TypeError]: mismatched types
  >  --> daemon.bl:3:16
  >   |
  > 3 |     serve(l.accept_timeout(wait)?)
  >   |           ^^^^^^^^^^^^^^^^^^^^^^^ expected `UnixConn`, found `UnixConn?`
  >   |
  >   = help: `accept_timeout` gives `None` when the time runs out; match on it
  > ```
  >
  > Removed-free-functions rows:
  >
  > | Removed name | Replacement | Effect | Result changes |
  > |---|---|---|---|
  > | `unix_socket_accept_timeout(l, ms)` | `listener.accept_timeout(Duration.ms(ms))` | `Net.Listen` | yes: `Int` (-1 on timeout) becomes `Result[UnixConn?, NetError]` |
  >
  > The fix is not machine-applicable: the fd argument becomes the receiver, and the result changes. `unix_socket_peer_uid` gets no row. It was never a builtin (only typecheck.bl and cg_call.bl know `accept_timeout`), and the daemon binds it with its own `@ffi`, so name lookup never fails on it.
  >
  > ## Tradeoffs (tooling view)
  >
  > - **Why `None` and not `Err(Timeout)`.** UDP maps EAGAIN after `set_timeout` to `NetError.Timeout`. If I copy that, `l.accept_timeout(ms)?` type-checks, and the daemon exits on its first idle tick. No diagnostic catches that. With `UnixConn?`, the compiler stops every caller that forgot. I accept the difference from UDP to get that error.
  > - **Why `Duration` and not `ms: Int`.** Hover shows the unit, and `accept_timeout(500)` gives a type error rather than a silent bug when someone reads it as seconds. `process.run(timeout:)` already takes a `Duration`. UDP `set_timeout(ms: Int)` is the odd one, and I would log it as friction, not copy it.
  > - **Name.** `accept_timeout` starts with `accept`, so the LSP lists it next to `accept`. `try_accept` reads like "never blocks", and that is wrong.
  > - **Fail-closed `peer_uid`.** `conn.peer_uid()?` refuses a peer on an unsupported platform unless the caller opts in by matching on `ENOTSUP`. That is the safe default for a security check. If the result were `Result[Int?, _]`, `Ok(None)` would look like "no user" and invite `unwrap_or(own)`.
  >
  > ## Proposal D2 (fallback): a timeout setter
  >
  > `listener.set_timeout(d) ! Net.Listen`, and then `accept()` gives `Err(NetError.Timeout)`, the same as UDP. I reject it. The state is hidden, the LSP cannot show that `accept` now times out, and `?` still swallows the idle case.
  >
  > Other languages: Go uses `SetDeadline` plus `err.Timeout()`, and that check is the bug I want to avoid. Python's `settimeout` raises `socket.timeout`. Rust std has no timeout on accept. Go's `syscall.GetsockoptUcred` and Rust's `UnixStream::peer_cred` (unstable) both return a `Result`, as `peer_uid` does here.

- **AI/ML:**

  > ## Proposal 1 (my pick): two methods, "no result" is `None`, not an error
  >
  > ```blink
  > pub trait UnixListenerOps {
  >     fn accept(self) -> Result[UnixConn, NetError] ! Net.Listen
  >     fn accept_timeout(self, ms: Int) -> Result[UnixConn?, NetError] ! Net.Listen
  >     fn close(self) ! Net.Listen
  > }
  > // UnixConnOps:   fn peer_uid(self) -> Result[Int?, NetError] ! Net.Listen
  > // UnixStreamOps: fn peer_uid(self) -> Result[Int?, NetError] ! Net.Connect
  > ```
  >
  > Behavior:
  > - `accept_timeout(ms)`: a client connects before `ms` ms → `Ok(Some(conn))`. No client → `Ok(None)`. `ms == 0` polls once. `ms < 0` → `Err(Os(op: "accept", code: EINVAL))`, so each value has one meaning. An EINTR before the deadline does not end the wait. A closed listener → `Os(op: "accept")` with `EBADF`, the same as `accept`.
  > - `peer_uid()`: `Ok(Some(uid))` on Linux (SO_PEERCRED), macOS and the BSDs (getpeereid). `Ok(None)` on a platform with no such call. `Err(Os(op: "peer_uid", code))` when the call fails. `op` is the same string on every platform. A closed socket → `EBADF`.
  > - Rows come from the open-socket-rows rule: no new rule, no new effect op.
  >
  > Removed-free-functions rows:
  >
  > | Removed name | Replacement | Effect | Result changes |
  > |---|---|---|---|
  > | `unix_socket_accept_timeout(l, ms)` | `listener.accept_timeout(ms)` | `Net.Listen` | yes: `-1` becomes `Ok(None)` or `Err` |
  > | `unix_socket_peer_uid(s)` | `conn.peer_uid()` on `UnixConn`, `stream.peer_uid()` on `UnixStream` | `Net.Listen` on `UnixConn`, `Net.Connect` on `UnixStream` | yes: `Int` becomes `Result[Int?, NetError]`; `-2` becomes `Ok(None)` |
  >
  > Neither fix is machine-applicable: the receiver changes from an `Int` fd to a socket value, the same as the current `unix_socket_accept` row.
  >
  > Daemon loop, rewritten:
  >
  > ```blink
  > // A connection the daemon may serve, or None. Another user's connection is closed unread.
  > fn accept_own(l: UnixListener, ms: Int, own: Int) -> Result[UnixConn?, NetError] ! Net.Listen {
  >     match l.accept_timeout(ms)? {
  >         None => Ok(None),
  >         Some(conn) => {
  >             match conn.peer_uid() {
  >                 Ok(Some(uid)) => {
  >                     if uid == own {
  >                         return Ok(Some(conn))
  >                     }
  >                     conn.close()
  >                     Ok(None)
  >                 }
  >                 Ok(None) => Ok(Some(conn))      // no peer check here; the 0700 directory guards
  >                 Err(_) => {
  >                     conn.close()
  >                     Ok(None)
  >                 }
  >             }
  >         }
  >     }
  > }
  > ```
  >
  > A call that forgets the `None` case gets the normal non-exhaustive match error, and `let c = l.accept_timeout(ms)?` followed by `c.read_line()` fails to typecheck (`UnixConn?` has no `read_line`). The type says "a timeout can happen" at the call site.
  >
  > Tradeoffs (AI/ML):
  > - Same shape as `read_line -> Result[Str?, NetError]`, which the model already learned from this section: `None` is the ordinary "nothing", `Err` is a fault. One rule, two uses.
  > - `Err(Timeout)` would let the common pattern `let conn = l.accept_timeout(ms)?` compile and end the server loop on the first idle tick. That is the top bug I see in generated Python (`socket.timeout` caught too wide or not at all) and Go (`ne.Timeout()` check forgotten).
  > - `Int?` for the uid makes the natural check `conn.peer_uid()? == Some(own)` fail closed on a platform with no call. A model that writes the short form gets the safe behavior; allowing "unsupported" takes an explicit `Ok(None)` arm.
  > - No `import std.libc` and no errno guard to test ENOTSUP: about 15 fewer tokens per check, and no platform-specific constant to recall.
  >
  > ## Proposal 2 (rejected): `set_timeout(ms)` on `UnixListener`, as on `UdpSocket`
  >
  > `accept()` would then return `Err(NetError.Timeout(...))`. It reuses one name, but it adds hidden state (the model must track whether a timeout was set earlier), it puts a normal outcome in `Err`, and `?` silently turns it into an exit. Reject.
  >
  > ## Note for Minimalism
  >
  > Do not add `unix_peer_uid_supported()`. The daemon can ask on the real stream; `Ok(None)` gives the same answer. Add it only if a caller needs the answer before any socket exists.
  >
  > Cross-language: Go uses `SetDeadline` + `Timeout()` checks; Python uses `settimeout` + an exception; Rust std has no accept timeout. All three are stateful or exception-based. A per-call argument with an `Option` result has fewer decision points than each.

- **Minimalism:**

  > The daemon needs both features, and the opaque `UnixListener`/`UnixConn` hides the fd, so a local `@ffi` cannot do them. That makes both a real gap, not sugar. My aim is to fill it with the fewest new shapes.
  >
  > ## Proposal M1 (my vote)
  >
  > **Timeout: a keyword on the existing `accept`. No new method.**
  >
  > ```blink
  > fn accept(self, *, timeout: Duration? = None) -> Result[UnixConn, NetError] ! Net.Listen
  > ```
  >
  > - `None` (the default): blocks, as `accept()` does now.
  > - If no client connects before the timeout ends: `Err(NetError.Timeout(msg))`. §4.4.6 already says "a socket timeout is `Timeout`, not `Os`", so std.net keeps one way to report a timeout.
  > - `Duration.ms(0)`: checks once and does not wait. The daemon uses this after its own `poll`.
  > - A negative duration: `Err(Os(op: "accept", code: EINVAL))`.
  > - The shape comes from `process.run(..., limits: ChildLimits { timeout: Duration? = None })`.
  >
  > **Peer uid: one method on each stream type.**
  >
  > ```blink
  > fn peer_uid(self) -> Result[Int, NetError]   // UnixConnOps: ! Net.Listen, UnixStreamOps: ! Net.Connect
  > ```
  >
  > - Linux (SO_PEERCRED), macOS/BSD (getpeereid): `Ok(uid)`.
  > - The kernel call fails: `Err(Os(op: "peer_uid", code))`.
  > - The platform has no such call: `Err(Os(op: "peer_uid", code: ENOTSUP))`. `process` uses the same answer for a limit the host cannot enforce. It fails closed: a `?` refuses the peer, so the unsafe path is the one the caller must write out.
  > - The rows follow open-socket-rows. No new rule is needed.
  >
  > **Removed free functions: one new row.**
  >
  > | Removed name | Replacement | Effect | Result changes |
  > |---|---|---|---|
  > | `unix_socket_accept_timeout(l, ms)` | `listener.accept(timeout: Some(Duration.ms(ms)))` | `Net.Listen` | yes: `Int` becomes `Result[UnixConn, NetError]`; -1 on timeout becomes `Err(Timeout)` |
  >
  > The fix is not machine-applicable: the receiver changes from an `Int` fd to a `UnixListener`, the same as for the `unix_socket_accept` row. `unix_socket_peer_uid` gets **no row**. It was never a builtin name: it is only a runtime C symbol that `src/daemon.bl` binds with `@ffi`, and no user program can call it by that name.
  >
  > ```blink
  > import std.net.{UnixListener, UnixConn, NetError}
  > import std.errno.{Errno}
  > import std.libc.{ERR_NOTSUP}
  > import std.time.{Duration}
  >
  > // A connection from this user within `wait`, or None. Another user's connection is closed unread.
  > fn accept_own(l: UnixListener, wait: Duration, own: Int) -> Result[UnixConn?, NetError] ! Net.Listen {
  >     let conn = match l.accept(timeout: Some(wait)) {
  >         Ok(c) => c
  >         Err(NetError.Timeout(_)) => return Ok(None)
  >         Err(e) => return Err(e)
  >     }
  >     let allowed = match conn.peer_uid() {
  >         Ok(uid) => uid == own
  >         Err(NetError.Os(_, Errno(c))) => c == ERR_NOTSUP   // no peer check here: the closed dir guards
  >         Err(_) => false
  >     }
  >     if !allowed {
  >         conn.close()
  >         return Ok(None)
  >     }
  >     Ok(Some(conn))
  > }
  > ```
  >
  > An old call `unix_socket_accept_timeout(fd, 500)` gives E0504 with a fix that names `listener.accept(timeout: Some(Duration.ms(500)))` and `Net.Listen`.
  >
  > ## Rejected, and why
  >
  > - **`set_timeout(ms)` on the listener** (the UDP/TCP precedent): it puts mutable state in the fd box that every copy shares. The daemon uses a different wait on each call (0, 1, 500 ms), so it would need two calls each time. TCP's `set_timeout` also ignores `ms <= 0`, so the daemon's 0 would mean "block forever".
  > - **`accept_timeout(ms) -> Result[UnixConn?, NetError]`**: a second method for the same operation, and a second timeout shape (`None`) next to `NetError.Timeout`.
  > - **A credentials record (pid, gid)**: getpeereid gives no pid, and nothing reads gid. YAGNI.
  > …
  >
  > ## A gap the ticket misses
  >
  > `daemon_accept_during_build` (src/daemon.bl ~1140) runs `poll` on the listener fd and a pipe fd together. An opaque `UnixListener` has no fd, so the migration also stops there. Do not add `.fd()` in this ticket. File it on its own, so the panel can weigh fd access or a wait on several sockets separately.
  >
  > **Cross-language:** Go has `SetDeadline`, which is state on the listener. Rust std has no accept timeout, and `peer_cred` is unstable. Python has `settimeout`, which is state, plus `SO_PEERCRED` through `getsockopt`. M1 takes the timeout as an argument of the call, so the listener keeps no state.

#### Phase B — Debate highlights

One round. All six seats ended it ready to vote. Min took 1A. Sys, web, plt, aiml and min took `Duration` for the wait (the language already takes a `Duration` in `process.run`). Devops moved the other way, from `Duration` to `ms: Int`, because UDP `set_timeout` takes `ms: Int` and one std.net method on `Duration` beside it makes the API disagree with itself.

- **Systems:**

  > ## Q1: 1A. I accept `Duration` (a change from my Phase A `ms: Int`)
  >
  > I keep 1A. 1B puts a normal result in `Err`, so `l.accept(timeout: Some(d))?` compiles and the daemon exits on its first idle tick. No diagnostic stops that. Under 1A the type stops it. min is right that §4.4.6:743 maps a timeout to `Timeout`. But that line covers `set_timeout` state, which all six seats reject here. A per-call wait with an `Option` result follows the shape of `read_line` (`None` = nothing yet).
  >
  > **Wait type: I change to `Duration`.** `Duration` is `{ nanos: Int }` (lib/std/time.bl:196), a struct with one field. In C it is one `int64_t` passed by value, so the cost is the same as `ms: Int`. It removes the ms/seconds bug devops showed, and `process.run(timeout:)` already takes one. UDP `set_timeout(ms: Int)` is the odd one out; file it as friction.
  >
  > New behavior: poll takes whole ms, so the runtime **rounds up** to the next ms. A wait is never shorter than asked, and `Duration.nanos(1)` does not become a check with no wait.
  >
  > ```blink
  > match l.accept_timeout(Duration.nanos(1))? {   // the runtime polls for 1 ms, not 0
  >     None => io.println("idle")
  >     Some(c) => c.close()
  > }
  > // output with no client: idle
  > ```
  >
  > `Duration.ms(0)` is the one check with no wait. A negative wait gives `EINVAL`.
  >
  > ## Q2: 2A, unchanged
  >
  > aiml's `peer_uid()? == Some(own)` also fails closed under 2A: `peer_uid()? == own` passes up an `Err` on an unsupported platform. That is loud, and it is right for a security check: the operator finds out on the first connection. It does not quietly let peers in. Under 2B, an `Ok(None)` arm reads as "no user", and `unwrap_or(own)` lets every peer in. Writing out `ENOTSUP` is the extra cost of the unsafe path, and that cost is the point.
  >
  > ## Q3: I change to 3A
  >
  > I checked the call order. `daemon_identity` (src/cli.bl:6099) calls `daemon_proc_identity` **before** the client connects, and that function asks for support first. So the answer is needed before a socket exists. The probe is a constant of the target (a `#if` in the runtime) and costs nothing. Its row is `! ()`. Tie it as `process.can_limit` does: `peer_uid` gives `ENOTSUP` exactly when `unix_peer_uid_supported()` is `false`. With the probe, the fd -1 trick goes away.
  >
  > ## Q4: 4A, unchanged
  >
  > The name was never a builtin, so a row would teach a name that never existed.
  >
  > ## Variations
  >
  > - `op` string: `"peer_uid"` on every platform. A match on `op` must not depend on the platform.
  > - min's poll gap (`daemon_accept_during_build` waits on the listener and a pipe at once) is real. File it on its own ticket. An `.fd()` or a multi-wait design is a separate cost question.
  >
  > ## Writer notes
  >
  > - Say that the runtime rounds a sub-ms wait up, and that it never blocks in `accept` after `poll` (non-blocking accept, EAGAIN → `Ok(None)`).
  >
  > STABLE: ready to vote

- **Web/Scripting:**

  > ## Q1: 1A, and I change to `Duration`
  >
  > I keep 1A. With 1B, `l.accept(timeout: Some(wait))?` compiles and ends the loop on the first idle tick. Python devs hit that bug all the time with `socket.timeout`. 1A turns it into a type error.
  >
  > On the wait type, I concede to devops: use `timeout: Duration`. JS devs think in ms, Python devs in seconds, so a bare `500` will be read wrong. `process.run(timeout:)` already takes a `Duration`; UDP `set_timeout(ms: Int)` is the odd one out (log it as friction, do not copy it). The cost is one `import std.time.{Duration}`.
  >
  > ## Q2: I concede to 2A, but only together with 3A
  >
  > sys and min are right that the short form `Err(_) => false` fails closed. My objection was the ENOTSUP incantation (`import std.libc`, matching on `Errno(c)`), and the probe in 3A removes it. The daemon asks the probe and never matches on an errno:
  >
  > ```blink
  > import std.net.{UnixListener, UnixConn, NetError, unix_peer_uid_supported}
  > import std.time.{Duration}
  >
  > fn accept_own(l: UnixListener, wait: Duration, own: Int) -> Result[UnixConn?, NetError] ! Net.Listen {
  >     let conn = match l.accept_timeout(wait)? {
  >         Some(c) => c
  >         None => return Ok(None)
  >     }
  >     let allowed = match conn.peer_uid() {
  >         Ok(uid) => uid == own
  >         Err(_) => !unix_peer_uid_supported()
  >     }
  >     if !allowed {
  >         conn.close()
  >         return Ok(None)
  >     }
  >     Ok(Some(conn))
  > }
  > ```
  >
  > A peer from another user gets `Ok(None)`, and its connection is closed unread. On a platform with no such call, every peer is let in. Code that only writes `peer_uid()?` refuses everyone there.
  >
  > `op` string: I concede `"peer_uid"` on every platform. A caller should not need to know which syscall the runtime used.
  >
  > ## Q3: 3A
  >
  > `daemon_proc_identity` (src/daemon.bl:415) has no socket to ask, yet it must know the answer. Under 3B its only choice is to connect first, just to learn a fact that cannot change at runtime. With 2A, the probe also gives the daemon its fallback without errno matching (above), so 3A pays for itself twice.
  >
  > ## Q4: I concede to 4A
  >
  > I checked `src/cg_call.bl:1757`: the builtin table has `unix_socket_accept_timeout` but no `unix_socket_peer_uid`. A row for a name nobody could ever call would teach a name that never existed. No row.
  >
  > ## Writer notes
  >
  > - The mismatch from devops (`expected UnixConn, found UnixConn?`) should get a help line saying that `None` means the time ran out. That line answers most of the Stack Overflow questions here before anyone asks them.
  > - The `unix_socket_accept_timeout` row: `listener.accept_timeout(Duration.ms(ms))`.
  >
  > STABLE: ready to vote

- **PLT:**

  > ## Q1: 1A, and I now take `Duration`
  >
  > I keep 1A. A timeout is an expected result, so it belongs in the success type. Then a caller must deal with it before it gets a `UnixConn`. With 1B, `l.accept(timeout: Some(d))?` typechecks and passes an idle tick up as a failure. The type lets a wrong program through.
  >
  > min cites §4.4.6:743. That line covers EAGAIN after a timeout that `set_timeout` put on the socket. The setting changes every later read, so an `Err` there is a fault the caller did not ask for at that call. A wait given as an argument of one call is different. The caller asked for "a client or nothing", so "nothing" is an answer, as `read_line` gives `None`. The two rules do not conflict.
  >
  > **Wait type: I change to `Duration`.** In Phase A I said "change both or neither". devops shows the language already took a side: `process.run(timeout:)` takes a `Duration`. The odd one is UDP `set_timeout(ms: Int)`, so copying it would spread the mistake. A unit in the type is the sound choice: `accept_timeout(500)` fails to typecheck, where with `Int` it is quietly read as milliseconds. File UDP `set_timeout` as friction.
  >
  > ```blink
  > fn accept_timeout(self, wait: Duration) -> Result[UnixConn?, NetError] ! Net.Listen
  > ```
  >
  > ## Q2: 2A, and it needs 3A
  >
  > I keep 2A. "This target has no peer-credential call" is a fact about the target, the same for every socket. With 2B, every `peer_uid` result on Linux has a `None` case that never occurs on that target, and the type cannot say when it does occur. 2A keeps the success type exact (`Int`). The short form `conn.peer_uid()?` fails closed, which is aiml's goal.
  >
  > aiml's real objection is that the opt-in path needs an errno import. 3A removes that. The caller asks the target fact through its own function and does not decode it from an error:
  >
  > ```blink
  > let allowed = if !unix_peer_uid_supported() {
  >     true                              // no peer check on this target: the 0700 directory guards
  > } else {
  >     match conn.peer_uid() {
  >         Ok(uid) => uid == own
  >         Err(_) => false
  >     }
  > }
  > ```
  >
  > On Linux, a peer with another uid gives `allowed == false`, and the daemon closes the connection unread.
  >
  > Variation (the `op` string): `"peer_uid"` on every platform. `op` names the Blink operation, so a match on it works on every platform.
  >
  > ## Q3: 3A
  >
  > src/daemon.bl:415-416 asks before any socket exists (`daemon_proc_identity` is called before `unix_connect`). 3B cannot answer that question, so it fails the migration. The row `! ()` is sound: the result is constant for each compiled target, and the call reads nothing from the world.
  >
  > ## Q4: 4A
  >
  > No row. Name lookup can never fail on a name that was never a Blink name.
  >
  > ## Outside the ballot
  >
  > I agree with min. `poll` on several fds (src/daemon.bl ~1140) is a separate gap. File it on its own, and do not add `.fd()` here.
  >
  > ## Writer notes
  >
  > - State that 1A's `None` and 743's `Timeout` cover different cases: a wait passed to one call, and a timeout set on the socket.
  > - `peer_uid` gives `ENOTSUP` exactly when `unix_peer_uid_supported()` is `false`. Say this once, as one rule.
  >
  > STABLE: ready to vote

- **DevOps/Tooling:**

  > ## Q1: 1A (I keep it). On the wait type, I move to `ms: Int`
  >
  > 1B lets `l.accept(timeout: Some(d))?` compile, and that call ends the daemon on its first idle tick. No diagnostic can catch it, because `Err(Timeout)` is a valid thing to pass up with `?`. 1A turns the same mistake into an `expected UnixConn, found UnixConn?` error at the call. The rule at :743 is about state that `set_timeout` sets. Every seat rejects that state here, so the rule does not cover a per-call wait, and 1A does not break it.
  >
  > Wait type: plt is right that one std.net method on `Duration` beside UDP's `set_timeout(ms: Int)` makes the API disagree with itself. Hover shows `ms: Int`, so the unit is visible. I move to `ms: Int`. I will log a friction ticket to move both UDP and Unix to `Duration` together.
  >
  > ## Q2: 2A (I keep it)
  >
  > aiml's short form also fails closed under 2A. `conn.peer_uid()? == own` passes `ENOTSUP` up as an error, so it refuses the peer. Under 2B the short form that compiles and fails open is `conn.peer_uid()?.unwrap_or(own) == own`. Under 2A that form does not type-check. For logs, `Err(Os(op: "peer_uid", ENOTSUP))` prints "peer_uid: Operation not supported". `Ok(None)` prints nothing a user can search for.
  >
  > aiml's cost point (an errno import) goes away if we also take 3A: the caller tests the probe, not the errno.
  >
  > ```blink
  > let allowed = !unix_peer_uid_supported() || conn.peer_uid() == Ok(own)
  > ```
  >
  > That needs no `std.libc` and no `Errno` pattern. (This assumes `Result` derives `Eq`. If it does not, use `match` with `Ok(u) => u == own` and `Err(_) => false`.)
  >
  > Variation: the op string is `"peer_uid"` on every platform. A log grep and a test assert then do not depend on the platform.
  >
  > ## Q3: 3A (I keep it). I checked the claim from 3B
  >
  > `daemon_identity` (src/cli.bl:6099) calls `daemon_proc_identity` to build the request before it connects. The answer decides whether to send the full environment (daemon.bl:409-411). So "ask on a real stream" means a connect, then the identity, then the send. That changes the protocol, and the ticket does not cover that. The probe has row `! ()`, because it is a fixed fact about the target.
  >
  > ## Q4: 4A
  >
  > A row for a name that no user could call would put a name that never existed into E0504 text and training data.
  >
  > ## Gaps
  >
  > I agree with min: file the `poll`-on-the-listener gap on its own ticket, with no `.fd()` here. sys's runtime note (the call must not block after `poll`, and it must return the real errno, not -1) is a requirement for the implementation, not a ballot item.
  >
  > ## Writer notes
  >
  > - The E0504 help for `unix_socket_accept_timeout` should say that `-1` on timeout becomes `Ok(None)`, so a reader does not look for an `Err` arm.
  >
  > STABLE: ready to vote

- **AI/ML:**

  > ## Q1: 1A (no change). Wait type: I change to `Duration`.
  >
  > I keep 1A. With 1B, `l.accept(timeout: Some(wait))?` compiles and ends the loop on the first idle tick. A model that learned `?` from the rest of §4.4.6 writes exactly that. The "one way to report a timeout" argument covers a socket that has a setter (UDP). It does not hold for a wait that the caller asks for on this call, where no answer is the expected result. 1B also costs 3 match arms per call against 2.
  >
  > Wait type: I change from `ms: Int` to `Duration` (devops). This is the strongest AI/ML point on the ballot. Models trained on Python `settimeout(5.0)` (seconds) and Go `time.Second` write `accept_timeout(5)` and mean 5 s. With `Int` that is a silent 5 ms poll. With `Duration` it is a type error:
  >
  > ```
  > error: mismatched types: expected `Duration`, found `Int`
  >   |  l.accept_timeout(5)
  > ```
  >
  > `Duration.ms(500)` costs about 4 tokens, and the unit shows at the call site. `process.run(timeout:)` already takes a `Duration`. UDP `set_timeout(ms: Int)` is the odd one: log it as friction, do not copy it.
  >
  > ## Q2: I change to 2A (`Err(Os(op: "peer_uid", code: ENOTSUP))`), on the condition that 3A also passes
  >
  > sys is right that `.unwrap_or(own)` is a likely generated pattern on `Int?`, and it fails open. My objection to 2A was the cost of the errno match (`import std.libc`, `Errno(c)`, a constant to recall). The probe in 3A removes that cost: a caller that wants the fallback asks `unix_peer_uid_supported()` and never matches ENOTSUP. That gives a short form that fails closed and a fallback that is plain to read:
  >
  > ```blink
  > fn accept_own(l: UnixListener, wait: Duration, own: Int) -> Result[UnixConn?, NetError] ! Net.Listen {
  >     let conn = match l.accept_timeout(wait)? {
  >         Some(c) => c
  >         None => return Ok(None)
  >     }
  >     if !unix_peer_uid_supported() {
  >         return Ok(Some(conn))       // no peer check here; the 0700 directory guards
  >     }
  >     let allowed = match conn.peer_uid() {
  >         Ok(uid) => uid == own
  >         Err(_) => false
  >     }
  >     if !allowed {
  >         conn.close()
  >         return Ok(None)
  >     }
  >     Ok(Some(conn))
  > }
  > ```
  >
  > If 3A fails, I go back to 2B.
  >
  > `op` string: `"peer_uid"` on every platform. A model cannot know which syscall a platform uses.
  >
  > ## Q3: I change to 3A
  >
  > `daemon_proc_identity` (daemon.bl:415) asks before it has a socket, so the probe is needed, not a case of YAGNI. It is also the `process.can_limit` pattern, which the model already learns from §4.4.8: the probe is `false` exactly when the call gives ENOTSUP.
  >
  > ## Q4: I change to 4A
  >
  > I checked: `src/cg_call.bl:1757` lists `unix_socket_accept_timeout` and has no `unix_socket_peer_uid`. A row would teach a name that never existed, which is bad training data.
  >
  > ## Writer notes
  >
  > - The spec example uses the probe for the fallback, not an ENOTSUP match.
  > - State "`ENOTSUP` if and only if `unix_peer_uid_supported()` is `false`", in the same words as `can_limit`.
  > - The Removed row's fix text: `listener.accept_timeout(Duration.ms(ms))`.
  >
  > STABLE: ready to vote

- **Minimalism:**

  > ## Q1: I concede 1B and move to 1A
  >
  > The `?` point from aiml and devops beats my "one way to report a timeout" point. Under 1B, `let c = l.accept(timeout: Some(w))?` typechecks, and the daemon exits on its first idle tick. No diagnostic catches it. Under 1A, the same line is a type error at the call site. A keyword on `accept` cannot give `UnixConn?` only when the keyword is present, because the return type does not depend on it. So 1B cannot take that fix, and a second method is the smallest form that can. 1A also matches `read_line -> Result[Str?, NetError]`, so it adds no new pattern to std.net. It only uses one again.
  >
  > **Wait type: `Duration`.** This is a weak preference, and I will not block on it. The nearest per-call timeout in the spec is `process.run(limits: ChildLimits { timeout: Duration? })`. `UdpSocketOps.set_timeout(ms: Int)` is a setter, and we just rejected that shape here. `Duration` also stops the seconds-versus-ms bug at the type level. plt's "change both or neither" argument is fair. If the panel picks `ms: Int`, I accept it, and the UDP mismatch then goes to friction.
  >
  > ## Q2: 2A stays
  >
  > `Result[Int, NetError]`, with `Err(Os(op: "peer_uid", code: ENOTSUP))` where the platform has no call. 2B adds a nested `Int?` shape, and `Ok(None)` invites `.unwrap_or(own)`, which fails open on a security check. Under 2A, `Err(_) => false` and `?` both fail closed. The libc import costs a few tokens, and I accept that cost.
  >
  > **`op` string:** use `"peer_uid"` on every platform. A caller should not have to match on a string that changes with the OS.
  >
  > ## Q3: I concede 3B and move to 3A
  >
  > My Phase A condition was: "add a probe only if `daemon_proc_identity` has to know before it connects". It does. `src/cli.bl:6102` calls `daemon_proc_identity` from `daemon_identity()`, which builds the identity that goes in the request, before any stream exists. Without a probe, the client must reorder its connect around a hash of its environment, and that is a worse cost than one `! ()` function. So the probe has a real caller on day one:
  >
  > ```blink
  > import std.net.{unix_peer_uid_supported}
  >
  > fn main() {
  >     io.println("peer check: {unix_peer_uid_supported()}")
  > }
  > ```
  >
  > On Linux this prints `peer check: true`.
  >
  > There is one condition. It must be a constant of the target that agrees with `peer_uid`: `false` if and only if `peer_uid` gives `ENOTSUP`. That is the `can_limit` pattern.
  >
  > ## Q4: 4A stays
  >
  > There is no row for `unix_socket_peer_uid`. It was never a Blink name, so a row would teach a name that never existed.
  >
  > ## Writer notes
  >
  > - Say that `Ok(None)` from `accept_timeout` means "no client in time", and nothing else.
  > …
  >
  > STABLE: ready to vote

#### Phase C — Silent vote

| Question | Result |
|---|---|
| Q1 shape of the accept | **1A 6-0** |
| Q1w type of the wait | **W-D 5-1** (DevOps *(dissent)*: W-I) |
| Q2 `peer_uid` with no such call | **2A 6-0** |
| Q3 probe | **3A 6-0** |
| Q4 Removed row for `unix_socket_peer_uid` | **4A 6-0** |

Each seat's vote, reasoning and concern:

- **Systems:**

  > ## Q1: 1A
  > **Reasoning:** The runtime cost is the same for both: one `poll`, then one `accept` that does not block, and the `None` path allocates nothing. The difference is in the type. Under 1A, an idle tick cannot pass up through `?` as an error. Under 1B, the most natural line in a daemon loop (`accept(timeout:)?`) compiles and stops the server on its first idle tick. The `Timeout` line in §4.4.6 covers `set_timeout` state, which all six seats rejected, so 1A breaks no rule.
  > **Concern:** The runtime must accept with the fd non-blocking and map EAGAIN to `Ok(None)`. If it keeps today's blocking accept after `poll`, a second process that accepts the same client first makes the call hang past its deadline.
  >
  > ## Q1w: W-D
  > **Reasoning:** `Duration` is `{ nanos: Int }`, one `int64_t` passed by value in C, so it costs the same as `ms: Int`. It turns a unit mix-up (ms read as seconds) into a type error, and `process.run(timeout:)` already takes a `Duration`. UDP `set_timeout(ms: Int)` is the odd one out and should be filed as friction.
  > **Concern:** `poll` takes whole ms, so the spec must say the runtime rounds a sub-ms wait up. Without that rule, `Duration.nanos(1)` becomes a 0 ms wait and the loop spins.
  >
  > ## Q2: 2A
  > **Reasoning:** This is a security check, so the short form must refuse the peer. Under 2A, `Err(_) => false` and `peer_uid()?` both refuse, and only an arm that names `ENOTSUP` lets a peer in. Under 2B, `Ok(None)` reads as "no user", and `unwrap_or(own)` lets every peer in. `ENOTSUP` already has this meaning in `process` (§4.4.8).
  > **Concern:** On a platform with no such call, a daemon that writes `peer_uid()?` passes up an error on every connection. That is loud, not unsafe, but its users may file it as a bug.
  >
  > ## Q3: 3A
  > **Reasoning:** `daemon_identity` (src/cli.bl:6099) asks before the client has a socket, so 3B cannot serve the one real caller without moving its code around. The probe is a `#if` constant of the target with the row `! ()`, so it costs nothing at runtime. It also retires the trick of passing fd -1.
  > **Concern:** The spec must tie the probe to `peer_uid` both ways (`false` exactly when `peer_uid` gives `ENOTSUP`), or the two answers can drift apart on a new target.
  >
  > ## Q4: 4A
  > **Reasoning:** `unix_socket_peer_uid` was never a Blink name. `cg_call.bl` and `typecheck.bl` know only `unix_socket_accept_timeout`, and the daemon reaches the C symbol through its own `@ffi`. A row would teach a name that never existed, and the compiler would keep it for good.
  > **Concern:** Someone who copies the old daemon `@ffi` binding gets no hint that `peer_uid()` exists. That cost is small, because the binding is that caller's own code.

- **Web/Scripting:**

  > ## Q1: 1A
  > **Reasoning:** A timeout in a poll loop is the normal case, so the type should say so. With 1B, `l.accept(timeout: Some(w))?` compiles and ends the server on the first idle tick. That is the bug Python devs hit with `socket.timeout`, and 1A makes it a compile error. `None` for "nothing yet" also matches `read_line`, so there is one rule to learn.
  > **Concern:** A dev may expect the keyword form from Python and look for `accept(timeout:)`. The doc for `accept` should point to `accept_timeout`.
  >
  > ## Q1w: W-D
  > **Reasoning:** JS devs read `500` as ms, Python devs read it as seconds. A type error beats a silent 1000x bug. `process.run(timeout:)` already takes a `Duration`, so the newer API sets the pattern, and UDP's `ms: Int` is the odd one out.
  > **Concern:** `UdpSocketOps.set_timeout(ms: Int)` and `accept_timeout(Duration)` now disagree in one section. File a friction ticket to move UDP to `Duration`, or users will guess wrong on one of them.
  >
  > ## Q2: 2A
  > **Reasoning:** This is a security check, so the short form must fail closed: `peer_uid()?` and `Err(_) => false` both refuse the peer. Together with the 3A probe, the fallback needs no errno matching (`Err(_) => !unix_peer_uid_supported()`), and that removes my only objection to 2A.
  > **Concern:** If 3B wins, the daemon's fallback goes back to `import std.libc` and a match on `Errno(c)`, which few users will get right on the first try.
  >
  > ## Q3: 3A
  > **Reasoning:** `daemon_proc_identity` must know the answer before it has a socket, and a typed API cannot pass fd -1. The probe is one obvious function with no row, and it lets 2A callers check "unsupported" without knowing an errno.
  > **Concern:** The spec must state that `false` holds if and only if `peer_uid` gives `ENOTSUP`, or the two will drift on a new target.
  >
  > ## Q4: 4A
  > **Reasoning:** `unix_socket_peer_uid` was never a callable Blink name; `src/cg_call.bl:1757` has only `unix_socket_accept_timeout`. A row would teach users a name that never existed.
  > **Concern:** A user who copies daemon code that binds the C symbol may still look for that name. The normal undefined-name error gives them no hint, which is acceptable.

- **PLT:**

  > ## Q1
  > **Vote:** 1A
  > **Reasoning:** The caller asked for "a client or nothing", so "nothing" belongs in the success type, as `None` from `read_line` does. Then a caller must deal with it before it can use a `UnixConn`. With 1B, `accept(timeout:)?` typechecks and passes an expected result up as a failure, so the type accepts a wrong program. §4.4.6:743 covers a timeout set on the socket, not a wait passed to one call, so 1A does not conflict with it.
  > **Concern:** If 1A wins, readers may find two timeout shapes in std.net (`Ok(None)` here, `Timeout` after UDP `set_timeout`) unless the spec states the rule that tells them apart.
  >
  > ## Q1w
  > **Vote:** W-D
  > **Reasoning:** A unit in the type stops `accept_timeout(5)` from being read as seconds without any error. `process.run(timeout:)` already takes a `Duration`, so the language has picked this side, and UDP `set_timeout(ms: Int)` is the one that does not match. To copy the odd one would spread the mistake.
  > **Concern:** UDP `set_timeout(ms: Int)` stays inconsistent until a friction ticket aligns it.
  >
  > ## Q2
  > **Vote:** 2A
  > **Reasoning:** "No peer-credential call" is a fact about the target, the same for every socket. So it does not belong in each result as a `None` that can never occur on Linux. 2A keeps the success type exact (`Int`), and the short form `peer_uid()?` refuses the peer by default. With 3A, a caller that wants the fallback asks the target fact directly and does not decode `ENOTSUP`.
  > **Concern:** A caller without 3A who wants the fallback must match on the errno, and a match that is too wide (`Err(_) => true`) would let a failed check through.
  >
  > ## Q3
  > **Vote:** 3A
  > **Reasoning:** `daemon_proc_identity` (src/daemon.bl:415-416) asks before any socket exists, so 3B cannot serve the migration. The row `! ()` is sound: the result is constant for each compiled target, and the call reads nothing from the world. It also gives Q2's fallback a typed path.
  > **Concern:** The spec must state that the probe and `ENOTSUP` agree ("false if and only if"), or the two can drift apart in the runtime.
  >
  > ## Q4
  > **Vote:** 4A
  > **Reasoning:** The table holds Blink names that were removed. `unix_socket_peer_uid` was only a C symbol, reached through a local `@ffi`, so name lookup has never failed on it. A row would teach a name that never existed.
  > **Concern:** A user who copied the daemon's `@ffi` binding sees no hint toward `peer_uid()`, but the binding still compiles, so this costs little.

- **DevOps/Tooling:**

  > ## Q1
  > **Vote:** 1A
  > **Reasoning:** Under 1B, `accept(timeout: ...)?` compiles and stops the server on an idle tick, and no lint or type error catches it. Under 1A, the same mistake is a type error at the call site: `expected UnixConn, found UnixConn?`. That diagnostic is the reason for the extra method. It also shows in LSP completion right next to `accept`.
  > **Concern:** A user can still write `accept_timeout(ms)?.unwrap()`, which panics on the first timeout. The writer should give the `match` form in the spec example.
  >
  > ## Q1w
  > **Vote:** W-I
  > **Reasoning:** One std.net socket method that takes `Duration`, next to UDP `set_timeout(ms: Int)`, makes the API disagree with itself. Hover and signature help show `ms: Int`, so the unit is visible at the call. Moving to `Duration` is right, but std.net should move all at once, on a friction ticket.
  > **Concern:** A user can pass seconds where milliseconds are expected (`accept_timeout(5)`), and no diagnostic catches it until std.net moves to `Duration`.
  >
  > ## Q2
  > **Vote:** 2A
  > **Reasoning:** The short form fails closed. `conn.peer_uid()?` refuses the peer, and the fail-open `unwrap_or(own)` does not type-check. The error has a printed form that users can search for ("peer_uid: Operation not supported"). `Ok(None)` has no such text. This is the same `ENOTSUP` pattern as `process`, so std has one answer for "this host cannot do this".
  > **Concern:** Callers who want the fallback must match an errno, unless the spec example uses the probe (3A).
  >
  > ## Q3
  > **Vote:** 3A
  > **Reasoning:** `daemon_identity` (src/cli.bl:6099) needs the answer before it connects, so 3B forces a change to the protocol. With the probe, a caller can test support without an `std.libc` import or an `Errno` pattern. Its row is `! ()`, because the answer is a fixed fact about the target.
  > **Concern:** The probe and `ENOTSUP` can drift apart in the runtime. A test must assert that `unix_peer_uid_supported()` is `false` if and only if `peer_uid` gives `ENOTSUP`.
  >
  > ## Q4
  > **Vote:** 4A
  > **Reasoning:** No Blink user could ever call `unix_socket_peer_uid`. A table row would put a name that never existed into E0504 text and into training data. The normal undefined-name error is correct here.
  > **Concern:** Code that copies the daemon's private `@ffi` binding gets no hint toward `peer_uid()`. Only the daemon has such code, and the src migration covers it.

- **AI/ML:**

  > ## Q1: 1A
  > **Reasoning:** The most likely generated form is `l.accept_timeout(wait)?`. Under 1A the type checker stops it. Under 1B it compiles and ends the server on the first idle tick, and no diagnostic catches that. 1A also has the same shape as `read_line -> Result[Str?, NetError]`, so the model learns one rule: `None` is the ordinary "nothing". It needs 2 match arms, against 3 for 1B.
  > **Concern:** A model may write `.unwrap()` on the `Option` to make the type error go away, which turns an idle tick into a panic.
  >
  > ## Q1w: W-D
  > **Reasoning:** Python `settimeout` takes seconds and Go uses `time.Second`, so generated code writes `accept_timeout(5)` and means 5 s. With `Int` that is a silent 5 ms poll; with `Duration` it is a type error. `Duration.ms(500)` costs about 4 tokens and shows the unit at the call site, and it matches `process.run(timeout:)`.
  > **Concern:** `UdpSocketOps.set_timeout(ms: Int)` now uses a different unit type in the same section, and models will mix the two up until someone files that friction and fixes it.
  >
  > ## Q2: 2A
  > **Reasoning:** `.unwrap_or(own)` on `Int?` is a pattern models write often, and it lets any peer in. Under 2A the short forms (`?`, `Err(_) => false`) refuse the peer. I vote 2A because 3A takes away its cost: the fallback becomes a `Bool` probe, not an errno match that needs `import std.libc`.
  > **Concern:** If 3A fails, callers who want the fallback must match `Errno(c)` against `ERR_NOTSUP`, and models will get that import and that constant wrong.
  >
  > ## Q3: 3A
  > **Reasoning:** `daemon_proc_identity` asks before it has a socket, so a real caller needs the probe now; it is not a case of YAGNI. The probe follows the `process.can_limit` pattern that §4.4.8 already teaches, so the model has nothing new to learn. It also replaces the ENOTSUP match in the common fallback code.
  > **Concern:** A model may call the probe and then skip `peer_uid`, as if "supported" meant "allowed". The spec example must show both calls.
  >
  > ## Q4: 4A
  > **Reasoning:** `unix_socket_peer_uid` is not in `src/cg_call.bl:1757`, so it was never a Blink name. A row would teach a name that never existed, and this spec is training data.
  > **Concern:** A model that read the old daemon source may still guess the name. It then gets an undefined-name error with no hint to `peer_uid`.

- **Minimalism:**

  > ## Q1
  > **Vote:** 1A
  > **Reasoning:** A keyword cannot change the return type of `accept`, so 1B leaves the `?` trap that no diagnostic catches. 1A reuses the `Str?` shape that `read_line` already has, so std.net gains a method but no new pattern. That is the smallest form that the compiler can check.
  > **Concern:** Someone may later ask for `accept_timeout` on TCP and UDP too. Each one must clear the same bar of a real caller, and must not get added just for symmetry.
  >
  > ## Q1w
  > **Vote:** W-D
  > **Reasoning:** The nearest per-call timeout in the spec, `ChildLimits.timeout`, already takes a `Duration`. The `ms: Int` precedent is a setter, and this panel just rejected that shape. A unit bug that the type catches costs no new concept, because `Duration` already exists.
  > **Concern:** std.net then has one socket timeout in `Int` (UDP `set_timeout`) and one in `Duration`. Log that as friction so that the UDP setter changes too, and the mismatch does not stay for good.
  >
  > ## Q2
  > **Vote:** 2A
  > **Reasoning:** It adds no nested `Int?` shape and uses the `ENOTSUP` answer that `process` already gives. Both short forms, `?` and `Err(_) => false`, fail closed on a security check. To fail open, the caller must write it out.
  > **Concern:** Callers who want the daemon's fallback must import `ERR_NOTSUP` from `std.libc` to match it, and some will instead write `Err(_) => true`.
  >
  > ## Q3
  > **Vote:** 3A
  > **Reasoning:** The probe has a real caller on day one. `src/cli.bl:6102`, in `daemon_identity()`, needs the answer before any stream exists, and without the probe the client must reorder its connect. One `! ()` function costs less than that reorder.
  > **Concern:** The probe and `peer_uid` can drift apart. Both must read the same compile-time platform check, and a test must assert `!supported` if and only if `ENOTSUP`.
  >
  > ## Q4
  > **Vote:** 4A
  > **Reasoning:** `unix_socket_peer_uid` was never a Blink name. The table holds removed names that users could call, so a row here would teach a name that never existed, and the table would grow for nothing.
  > **Concern:** A reader who greps for the C symbol may think a row is missing. The writer can say in one line why it has none.

#### Phase D

Not triggered. The closest result was Q1w at 5-1.

### Dissent

**DevOps, Q1w (voted W-I, `ms: Int`).** Quoted from its Phase C reply above: "One std.net socket method that takes `Duration`, next to UDP `set_timeout(ms: Int)`, makes the API disagree with itself. Hover and signature help show `ms: Int`, so the unit is visible at the call. Moving to `Duration` is right, but std.net should move all at once, on a friction ticket." Its concern: "A user can pass seconds where milliseconds are expected (`accept_timeout(5)`), and no diagnostic catches it until std.net moves to `Duration`." The majority took `Duration` for a different reason (see the Phase B and C replies above): the unit shows at the call, `accept_timeout(5)` is a type error, and `process.run` already takes a `Duration`. UDP `set_timeout` stays `ms: Int` until a later panel moves it (see the open cases).

### Final Spec

```blink
pub fn unix_peer_uid_supported() -> Bool

pub trait UnixListenerOps {
    fn accept(self) -> Result[UnixConn, NetError] ! Net.Listen
    fn accept_timeout(self, wait: Duration) -> Result[UnixConn?, NetError] ! Net.Listen
    fn close(self) ! Net.Listen
}

pub trait UnixConnOps {          // made by accept and accept_timeout
    fn read_line(self) -> Result[Str?, NetError] ! Net.Listen
    fn write(self, data: Str) -> Result[(), NetError] ! Net.Listen
    fn peer_uid(self) -> Result[Int, NetError] ! Net.Listen
    fn close(self) ! Net.Listen
}

pub trait UnixStreamOps {        // made by unix_connect
    fn read_line(self) -> Result[Str?, NetError] ! Net.Connect
    fn write(self, data: Str) -> Result[(), NetError] ! Net.Connect
    fn peer_uid(self) -> Result[Int, NetError] ! Net.Connect
    fn close(self) ! Net.Connect
}
```

Locked points:

- `accept_timeout(wait)` is a second method. `accept` keeps its shape. `Ok(Some(conn))` is a client; `Ok(None)` means no client came in time and nothing else; `Err` is a failure of the call.
- `wait` is a `Duration`. A wait under 1 ms rounds up to 1 ms. `Duration.ms(0)` is the only wait that checks once and does not wait. A negative wait gives `Err(Os(op: "accept", code: EINVAL))`. A signal (EINTR) makes the call wait again for the time that is left. A closed listener gives `EBADF`, as `accept` does.
- The listener has no `set_timeout` and there is no credentials record (pid, gid).
- `peer_uid` is on `UnixConn` (`! Net.Listen`) and on `UnixStream` (`! Net.Connect`) by the maker rule of the open-socket-rows decision. `UnixListener` has none. No new rule and no new `Net` op.
- `peer_uid` gives `Ok(uid)` (not negative), or `Err(Os(op: "peer_uid", code))` when the call fails, or `Err(Os(op: "peer_uid", code: ENOTSUP))` where the platform has no such call. The `op` text is `"peer_uid"` on every platform.
- `unix_peer_uid_supported()` has no effect row, needs no socket, and is `false` if and only if `peer_uid` gives `ENOTSUP`. A test must assert that equality (devops).
- The spec example uses the probe for the fallback, not a match on `ENOTSUP`, and shows both calls (aiml). The examples use `match`, not `.unwrap()` (devops, aiml).
- The rule that tells `Ok(None)` from `NetError.Timeout`: `Timeout` is the result of a socket whose `set_timeout` state ran out; `Ok(None)` is the result of a wait that one call took as an argument. The existing `Timeout`, not `Os` sentence of §4.4.1 stays true.
- The type-error help for `let c = l.accept_timeout(wait)?` followed by use of `c` as a `UnixConn` says that `None` means the time ran out (web).
- Removed-functions table: `unix_socket_accept_timeout(l, ms)` maps to `listener.accept_timeout(Duration.ms(ms))`. The fix is not machine-applicable: the `Int` fd becomes a `UnixListener` receiver, and `-1` after the wait ran out is now `Ok(None)` (devops). There is no row for `unix_socket_peer_uid` (4A): a call gets the normal undefined-name error.

### Amendments

None.

### Implementation notes

These are not spec text.

- `lib/std/net_unix.bl` has `accept` and no `accept_timeout` or `peer_uid`. The compiler lists `unix_socket_accept_timeout` as a builtin (`src/cg_call.bl`) and has no entry for `unix_socket_peer_uid`; `src/daemon.bl` binds the runtime call with two `@ffi` declarations, one per row.
- The compiler's own daemon (`src/daemon.bl`) reads `-1` from `unix_socket_accept_timeout` for both a timeout and an error. The new call splits the two: `Ok(None)` and `Err`. The daemon's "peer check not supported" branch (`-2` today) moves to the probe (`daemon_identity` in `src/cli.bl` needs the answer before it connects).
- Linux reads the uid with `SO_PEERCRED`; macOS and the BSDs use `getpeereid(2)`. The wait uses `poll(2)` on the listener fd.
- The compiler's own message for a method call on `T?` is `UnresolvedMethod`, not `expected X, found X?`. The help line for a `None` that ran out of time needs a site in the type checker for both shapes (see the open cases).

### Open cases and follow-ups

- Poll on a `UnixListener` together with other fds (min). `src/daemon.bl` waits on a listener and a pipe fd at once (`daemon_accept_during_build`). `accept_timeout` takes one listener, and `UnixListener` is opaque, so that wait has no spelling in the new API. The panel did not decide it. It needs its own question.
- What UDP `recv_from` returns after its timeout (plt). The `NetError` text says an `EAGAIN` or `EWOULDBLOCK` after `set_timeout` is `Timeout`. The panel did not decide whether `recv_from` then gives `Err(Timeout)` or an `Ok(None)` like the new accept. Not decided.
- UDP `set_timeout(ms: Int)` against `Duration` (devops, plt). `accept_timeout` takes a `Duration`; `UdpSocketOps.set_timeout` takes `ms: Int`. The API disagrees with itself until one of them moves. Not decided.
- A help line for the `UnresolvedMethod` error when the receiver is `UnixConn?` after `let c = l.accept_timeout(wait)?` (see implementation notes). Not decided whether it carries the same help as the argument-mismatch error.
