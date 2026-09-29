[< All Decisions](../DECISIONS.md)

# UDP Gate: `SockAddr`, `recvfrom_bytes`/`sendto_bytes`, and `MsgFlags` — Design Rationale

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in
independent-proposal → debate → vote rounds, plus one focused second round on the flags type. Resolves
the post-v1 UDP gate deferred 6-0 by [`libc-bytes-wrapper-coverage`](libc-bytes-wrapper-coverage.md):
`recvfrom_bytes`/`sendto_bytes` were held back because `SockAddr` was undefined, no UDP socket existed,
and no stdlib code called them. The BDFL scoped this gate as the full gate: the peer-address type
(`SockAddr`), a std.net datagram-socket caller, `recvfrom_bytes`/`sendto_bytes`, and the flagged
variants of `recv_bytes`/`send_bytes`. The growth gate says no wrapper ships ahead of a real caller,
so the caller is in scope.

#### Phase A — Independent proposals

Six proposals. All six chose a plain Blink value type for the address (not `@ffi.struct`, `@ffi.opaque`
or raw `Bytes`), a keyword `flags` parameter on the existing names, a tuple return from `recvfrom_bytes`,
a `UdpSocket` caller in std.net, and pure numeric address parsing with no hidden DNS.

- **Systems:** *"The design question is what crosses the boundary on every datagram. UDP servers run at millions of packets per second, so the peer address must be a plain value: no heap allocation, no GC pointer, and cheap Eq and Hash so it can be a Map key for per-peer state."*
- **Web/Scripting:** *"The std.net caller is the product, and `libc.recvfrom_bytes` is the part it is built on."* On DNS: *"A DNS lookup that hides inside `send_to(data, "example.com", 53)` is the Node footgun: a lookup on every packet, with failures reported the wrong way."*
- **PLT:** "So whatever `recvfrom_bytes` returns must be **total over every address family the kernel can hand back**." On flags: "Adding a parameter after v1 is **not additive**, even with a default".
- **DevOps/Tooling:** *"The rule is that no `Ptr`, `@ffi.struct` or `@ffi.opaque` shows in the user-facing type."* On `send_to`: *"A per-packet DNS lookup is a hidden latency trap, and it hides `Net.DNS` in the effect row."*
- **AI/ML:** *"Can a model learn it from the spec alone? How many choices does it force on the caller? How many tokens does the common case cost?"* On the peer address: *"The most common UDP server keeps per-peer state in `Map[SockAddr, Session]`. Models write that pattern by reflex, and it must typecheck."*
- **Minimalism:** *"The gate needs one new type, two new libc wrappers and one std.net type. Everything else in it can either reuse something that already exists or be left out."*

#### Phase B — Debate highlights

Four codebase facts drove most of the movement: **(a)** `lib/std/libc.bl` defines its POLL constants as hardcoded Blink literals, so no header-sourced constant mechanism exists; **(b)** §2.21 allows a struct literal or an enum variant with const payloads as a const expression, so a newtype constant is a legal keyword default; **(c)** labels are call-site sugar, so adding a parameter changes the fn-value type; **(d)** v1 has not shipped.

Key shifts:

- **Correction on `blink_bytes_slice` clamping (Systems, against its own Phase A claim).** Sys: "I read `blink_bytes_slice` in bootstrap/runtime_core.h (lines 1620-1636). It clamps `end` to `b->len` and **copies** into a new Bytes. So a Linux `MSG_TRUNC` return larger than `max` does NOT read out of bounds today. My "memory-safety rule" was wrong as a safety claim." The same reading gave the cost fact used later: *"The same code shows that each received datagram costs two allocations and two byte passes: `Bytes.zeroed(max)` (alloc plus memset), then `slice` (alloc plus memcpy)."* The rule stays as spec text, not as a safety rule. **Sys:** *"I still want normative spec text: "the returned `.len()` is `min(rc, max)`". Then the behaviour is specified, not left to whatever the slice helper's clamp happens to do."*

- **Address representation converged on separate all-`Int` IP types.** **PLT:** *"1c and 1e (devops, min) put `Bytes` in the IP fields. This admits bad states that the type cannot rule out …"* **DevOps** conceded: *"A wrong length that surfaces as a runtime EINVAL, far from the typo, is a bad error."* **Systems:** *"each decoded peer costs a GC allocation. The type also admits invalid lengths"* (against `ip: Bytes`, the DevOps and Minimalism forms).

- **`flowinfo` dropped (four voices, then PLT with a different reason).** **PLT:** *"I concede `flowinfo`: drop it. My reason is Eq, not "it is almost always 0". If `flowinfo` is inside a derived Eq, the same peer can compare unequal to itself when a flow label is set, and that silently splits `Map[SockAddr, Session]`."*

- **Totality: Sys conceded to PLT, then PLT and the rest moved to `Option[SockAddr]`.** **Systems:** *"PLT is right that `libc.recvfrom_bytes` takes `fd: Int` and cannot know the family."* **Web:** *"PLT's fix makes every user `match` on a peer carry three dead arms (`Unix`, `Unnamed`, `Other`) on a socket that we know is IP."* **PLT:** *"The partiality moves to the layer where it belongs, the libc layer, where `fd: Int` has no family type."*

- **Flags go on `recv_bytes`/`send_bytes` now.** **PLT:** *"Fact (c) makes my Phase A argument decisive. Adding a parameter changes the fn-value type, so it is only free before v1 ships."* **Web** withdrew its own risk: *"My Phase A "risk" (the fn-value type changes) goes away if we do this before v1 (fact d)."*

- **Flag constants: header-sourced values do not exist.** **Minimalism:** *"Fact (a) disproves sys's "come from header macros … as `POLLIN` does today": POLL is made of Blink literals."* **Systems** moved to Blink-owned bits: *"The C shim maps them to native `MSG_*` using the real header macros. That costs a few ANDs and ORs per call, which is nothing next to a syscall."*

- **`sendto_bytes` argument order.** **PLT:** *"This is the literal POSIX order: `sendto(fd, buf, len, flags, dest, addrlen)` with the buffer pair replaced in place."*

- **Errors: one `Os` arm, a typed code.** **Systems:** *"Against min's `IoError("recvfrom failed: errno {e.code()}")`: it formats a string on every error and makes EAGAIN (timeout), EMSGSIZE and ECONNREFUSED unmatchable."* **Minimalism** conceded: *"My plan to map errors into `IoError(msg)` flattens EMSGSIZE and ECONNREFUSED into a Str, which breaks the fs precedent `FsError { code: Errno }`."* On the parse error: **AI/ML:** *"A `?` type mismatch is the most common error in generated code."*

- **`resolve` ships.** **Web:** *"Resolve is the caller of the no-hidden-DNS decision."*

- **`recv_from` max.** **Systems:** *"The shortest call must not be the slowest by three orders of magnitude."* **Web:** *"Make the correct call the default and the fast call the option."*

#### Phase C — Final vote

- **V1: address representation** — **A: separate `Ipv4Addr { bits: Int }` / `Ipv6Addr { hi: Int, lo: Int }` plus `SockAddr { V4(ip, port)  V6(ip, port, scope_id) }`** (6-0; B was one enum with no IP types)
  - **Systems:** A — *"A gives the IP its own type at zero cost, and `resolve`, allowlists and per-IP grouping need that name."*
  - **Web:** A — *"With B, a user who wants "is this peer 10.0.0.1?" must compare a raw `Int` against `167772161`, and that is a Stack Overflow question."*
  - **PLT:** A — *"Dropping flowinfo is correct because a flow label is not part of peer identity, and keeping it in a derived Eq would split one peer into two Map keys."*
  - **DevOps:** A — *"Int words mean no wrong-length state, so no bad value turns into a runtime EINVAL far from the typo."*
  - **AI/ML:** A — *"A named IP type gives `is_loopback()`, allowlists and `.octets()` one obvious home instead of a hand-written `match` to remove the port."*
  - **Minimalism:** A (moved from B) — *"But my claim that `Ipv4Addr` "can be added later without breaking anything" is wrong: changing `V4(ip: Int)` to `V4(ip: Ipv4Addr)` breaks every pattern and constructor."*

- **V2: peer value from libc `recvfrom_bytes`** — **A: `Option[SockAddr]`, V4/V6 only; `None` covers `addrlen == 0` and unmodelled families; std.net unwraps** (6-0; B was a total enum with `Unix`, `Unnamed`, `Other`)
  - **Systems:** A — *"I withdraw my round-1 concession to B."* and *"`Option[SockAddr]` costs one tag word and keeps the kernel's already-dequeued datagram from becoming an `Err`."*
  - **Web:** A — *"B makes every match on a peer carry `Unix`, `Unnamed` and `Other` arms that cannot occur on a UDP socket, which is noise that each new user must learn to ignore."*
  - **PLT:** A — *"`Option[SockAddr]` is total: the datagram is never lost, and no family becomes `Err` or an ICE."*
  - **DevOps:** A — *"`Option[SockAddr]` keeps every UDP user's `match` to two arms with no dead `Unix`/`Unnamed`/`Other` arms and no `_ =>` that hides a future family."*
  - **AI/ML:** A — *"`Option` at libc keeps every user `match` on SockAddr at two arms, so the exhaustiveness check still forces the IPv6 arm instead of a `_ =>` catch-all."*
  - **Minimalism:** A — *"`Option` gives the same soundness as the total enum (no lost datagram, no invented address) with zero extra variants."*

- **V3: flags type** — **3-3 in Phase C (A `Int`: web, aiml, min; B one `MsgFlags` newtype: sys, plt, devops). Sent to Phase D, where it resolved B 6-0.**
  - **Systems:** B — *"A transparent newtype is zero-cost. It owns the bit space, so the numbering is Blink's, not the platform's."*
  - **Web:** A — *"`flags:` is a required label after `--`, so the swapped-argument hazard that a newtype prevents cannot occur."*
  - **PLT:** B — *"The newtype still stops an unrelated Int from reaching a flags slot, which is the same case that justified `Errno`."*
  - **DevOps:** B — *"A newtype gives completion after `flags:` that lists only flag constants, hover that says `MsgFlags` instead of `Int`, and a type error for a pasted raw number."*
  - **AI/ML:** A — *"With flags as a labelled keyword, the swap that justified a newtype cannot occur, so a newtype adds one more concept per call with no error it prevents."*
  - **Minimalism:** A — *"`Int` is what `POLL_EVT_*` already uses in libc.bl."*

- **V4: flag constants** — **A: ratify only `PEEK` now (value 2 on every platform); add others under the growth gate** (6-0; B was five Blink-defined portable bits translated in C)
  - **Systems:** A (moved off its own B) — *"I move off my own B. TRUNC is useless under V11.10, because `.len()` is clamped to `min(rc, max)` and the true length it reports is thrown away."*
  - **Web:** A — *"A wrong constant is a silent bug that works on Linux and fails on macOS, which is worse than a missing constant."*
  - **PLT:** A — *"A constant whose value is right on Linux and wrong on macOS is a silent miscompile, and no header-sourced constant mechanism exists today."*
  - **DevOps:** A — *"PEEK is 2 everywhere and has a caller."*
  - **AI/ML:** A — *"PEEK is the one flag with the same value everywhere and a real caller."*
  - **Minimalism:** A — *"Only PEEK has the same value on every platform and a caller (peek before read)."*

- **V5: std.net `recv_from` result** — **A: tuple `(Bytes, SockAddr)`** (5-1)
  - **Systems:** A — *"A tuple and a struct have the same layout and cost, so my domain does not decide this one."*
  - **Web:** A — *"`let (data, peer) = sock.recv_from()?` is the Python and Rust idiom, and every developer from those languages knows it on sight."*
  - **PLT:** A — *"The fields have different types, so a swapped destructure is a type error."*
  - **AI/ML:** A — *"One shape at both layers (libc and std.net) is one thing to learn."*
  - **Minimalism:** A — *"`Bytes` and `SockAddr` are different types, so a swapped destructure is a type error."*
  - *(dissent)* **DevOps:** B (`Datagram { data, from }`) — *"`Datagram { data, from }` gives field completion (`dg.`), "did you mean `from`" on a typo, and a named type in hover and in error messages."*

- **V6: std.net `send_to` result** — **A: `Result[Void, NetError]`; the wrapper returns an error if the kernel sent less than the whole datagram** (6-0; B was `Int`)
  - **Systems:** A — *"An AF_INET/AF_INET6 datagram send is atomic: all bytes are sent, or the call fails with EMSGSIZE."*
  - **Web:** A — *"`TcpSocket.write_bytes` already returns `Result[Void, NetError]`, so the two sockets agree."*
  - **PLT:** A — *"This is sound only because the wrapper checks `n == data.len()` and returns an error otherwise, rather than assuming it."*
  - **DevOps:** A — *"The wrapper checks the count and returns an error, so nothing is assumed."*
  - **AI/ML:** A (moved from B) — *"An `Int` result on an atomic datagram invites a dead `if n < data.len()` check in generated code."*
  - **Minimalism:** A — *"The libc layer keeps the count, so the law is unaffected."*

- **V7: `recv_from` max** — **B: keyword with default, `-- max: Int = 65535`** (4-2; A was a required positional `max` plus a named constant `MAX_UDP_PAYLOAD = 65507`)
  - **Web:** B — *"The shortest call must be the correct call: `sock.recv_from()?` must never truncate a datagram without a signal."*
  - **DevOps:** B — *"Silent truncation is the worst diagnostic outcome: no error, no warning, only lost data, found in production."*
  - **AI/ML:** B — *"With a default, the shortest call is the correct one."*
  - **Minimalism:** B — *"The default makes the shortest call unable to truncate silently, which is a data-loss bug with no error."*
  - *(dissent)* **Systems:** A — *"The shortest call must not be the slowest by three orders of magnitude."*
  - *(dissent)* **PLT:** A — *"A default of 65535 hides a 64 KiB allocation and memset for each call behind the shortest spelling, and sys showed the runtime cost."*
  - **Soft consensus.** The concern fields of the four B voters endorse Systems' per-packet allocation cost. **DevOps:** *"sys's measured cost is real: 64 KiB zeroed plus a copy per packet at the default, so the implementation must skip the zeroing and the doc must tell hot-path callers to pass `max:`."* **AI/ML:** *"the per-call 64 KiB allocation sys measured makes the default call slow on a hot path; the spec must state that cost next to the default."* **Minimalism:** *"sys is right that the default costs a 64 KiB zeroed allocation per packet; the implementation should skip the zeroing and the docs should say to pass `max:` on hot paths."* **Systems** set the floor for the implementation: *"If B wins, the implementation ticket must at least remove the memset (uninitialized allocation) and should size the result from `rc` without a second copy, or the default makes a slow-by-default API."* The user signed off on this soft consensus.

- **V8: `UdpSocket.local_addr`** — **A: include `local_addr(self) -> Result[SockAddr, NetError]` (getsockname)** (6-0; B was defer)
  - **Systems:** A — *"Bind to port 0 is how every test and every client gets an ephemeral port, and getsockname is the only way to learn it."*
  - **Web:** A — *"Without `local_addr`, a user cannot write a working test of a UDP echo server."*
  - **PLT:** A (moved from defer) — *"A socket bound to port 0 without `getsockname` does not compose: nothing else can tell you the port you got, so this gate's own tests cannot be written."*
  - **DevOps:** A — *"Tests bind port 0 to avoid collisions under `blink test --parallel`, and they cannot learn the port without `local_addr`."*
  - **AI/ML:** A (moved from B) — *"Every generated UDP test will bind port 0 to avoid collisions in parallel runs, and it cannot learn the port without `local_addr`."*
  - **Minimalism:** A — *"Binding port 0 is how this gate's own parallel tests avoid port collisions, and nothing else returns the port the kernel chose."*

- **V9: address parse error** — **A: `SockAddr.parse(s) -> Result[SockAddr, NetError]` with a new arm `NetError.InvalidAddr(input: Str)`** (6-0; B was a separate error type plus a conversion)
  - **Systems:** A — *"One `NetError` arm composes with `?` with no conversion impl."*
  - **Web:** A — *"With a separate error type, the first echo server a new user writes fails to compile at `SockAddr.parse(...)?` until they find the conversion."*
  - **PLT:** A — *"§05 7.2 says `?` requires the error types to match exactly and does no implicit conversion."*
  - **DevOps:** A — *"One error type means `?` works in `! Net` code with no conversion, so the std.net examples compile as written."*
  - **AI/ML:** A — *"A `?` type mismatch is the most common error in generated code."*
  - **Minimalism:** A — *"One new arm on an enum that already exists, against a new type plus a conversion."*

- **V10: `SockAddr.to_canonical()`** — **B: defer; keep a doc note on `::ffff:` mapped addresses** (5-1)
  - **Systems:** B — *"It is pure and cheap, but it has no caller in this gate."*
  - **PLT:** B — *"It is also not a neutral equality: if you canonicalize, `::ffff:10.0.0.1` and `10.0.0.1` become equal, and that decision belongs with a caller that needs it."*
  - **DevOps:** B — *"No caller in this gate needs it, and adding it later breaks nothing."*
  - **AI/ML:** B — *"No caller needs it in this gate, and each extra method is one more choice a model must make at every compare."*
  - **Minimalism:** B — *"No caller in this gate needs it, and adding the method later breaks nothing."*
  - *(dissent)* **Web:** A — *"On a dual-stack socket, an IPv4 peer arrives as `::ffff:10.0.0.1`, and an allowlist of `10.0.0.1` does not match it."*

- **V11: points held by all six at the end of Phase B** — **all 12 items yes, 6-0:**
  1. Flags are the trailing keyword `-- flags` on `recv_bytes`, `send_bytes`, `recvfrom_bytes` and `sendto_bytes`. They are added to `recv_bytes`/`send_bytes` now, before v1.
  2. `sendto_bytes(fd: Int, data: Bytes, dest: SockAddr, -- flags)`.
  3. Naming-law amendment (min's merged text, with the flags type from V3): "The `(buf, len)` pair is replaced in place by `max: Int` (reads) or `data: Bytes` (writes). A non-buffer out-parameter moves into the success value as a tuple after the `Bytes` or count, in C order. A pointer-typed out-parameter that may be empty is `Option`. `flags` is always the trailing keyword `-- flags`, exempt from C order."
  4. `udp_bind(addr: SockAddr) -> Result[UdpSocket, NetError] ! Net.Listen`. socket/bind go through one runtime intrinsic; there is no `libc.socket` or `libc.bind`.
  5. `UdpSocket` has `set_timeout(self, ms: Int)` and `close(self)`. No `connect`, `udp_unbound`, `recv` or `send` in this gate.
  6. `resolve(host: Str, port: Int) -> Result[List[SockAddr], NetError] ! Net.DNS` ships in this gate.
  7. New arm `NetError.Os(op: Str, code: Errno)` for errno failures. EAGAIN after a timeout maps to `NetError.Timeout` (plt).
  8. The §4 NetError list is made to match the implementation in this gate.
  9. SockAddr derives Eq and Hash and has Display (`10.0.0.1:53`, `[::1]:53`, `[fe80::1%2]:53`).
  10. Normative spec text: the received `.len()` is `min(rc, max)`; a 0-length datagram is not EOF; a datagram larger than `max` is truncated without an error; libc `! IO` wrappers are not subject to Net attenuation.
  11. The stale §07 line `std.libc.connect(sock: I32, ...)` is replaced with the real `libc.recvfrom_bytes` signature.
  12. The spec states that libc `None` from recvfrom_bytes means "no address, or a family SockAddr does not model", and is not an error (plt's condition).

#### Phase D — Round 2 (V3 flags type)

Phase C V3 came in 3-3, so the panel debated V3 alone. All other questions stayed closed. Every A voter had named the same failure as the concern in their own vote (a pasted man-page value such as `flags: 0x40`), and the debate turned on that. All six ended the debate holding B.

Key shifts:

- **Systems** moved the question off the swap hazard: *"I did not rest B on the swap; my Phase B reply and my vote rest on the meaning of the bits."* Under `Int`, the argument means native `MSG_*` bits, so a later portable flag forces either a per-platform miscompile or a translation layer that changes what existing call sites mean.
- **Web** changed to B: *"A spec sentence is not a fix, and DX is about the bugs people actually hit, not the ones the docs warn about."* Web also named the boundary rule: *"The wrapper translates each named bit to the native `MSG_*` value in C, and it rejects unknown bits with `Err(Errno(EINVAL))` on every platform."*
- **AI/ML** changed to B: *"My own Phase C concern is the case for B."* and *"All three A voters named the same failure. B is the only option that turns it into a compile error."*
- **Minimalism** changed to B: *"sys's argument answers the concern I stated in my own vote."* and *"A newtype that replaces future complexity is the kind of addition I vote for."*
- **DevOps** held B: *"Prose is the diagnostic surface of last resort, and models do not read it at the call site."*
- **PLT** held B and added a condition, the opaque form: "Position: B. One `MsgFlags` type, with the condition that its representation is opaque (no public constructor)." and *"The set of values is then exactly the closure of the named constants under `|`."*

**V3: flags type** — **B: one `MsgFlags` type, default `MsgFlags.NONE`, Blink-owned bit numbering translated to native `MSG_*` in C** (6-0)
  - **Systems:** B — *"It makes the bits Blink's from day one, so every later flag (DONTWAIT, WAITALL) is one constant plus one row in the C translation table, and no existing call site changes meaning."*
  - **Web:** B — *"All three A votes, mine too, named the same bug as their concern: a pasted man-page value such as `flags: 0x40` works on Linux and does the wrong thing on macOS."*
  - **PLT:** B — *"Under `MsgFlags`, Blink owns the numbering. Each value has one meaning on every platform, a later flag is purely additive, and the cost at run time is zero (one word)."*
  - **DevOps:** B — *"Blink owns the bit numbering from day one, so a later DONTWAIT is one constant plus one table row and breaks no call site."*
  - **AI/ML:** B — *"Under A the meaning "native bits" is fixed at v1, and a later portable DONTWAIT changes what existing calls mean."*
  - **Minimalism:** B — *"With `MsgFlags`, Blink owns the numbering, and each later flag is one constant plus one table row."*

**V3-sub: B1 (opaque, no public constructor; values only from named constants) vs B2 (transparent `MsgFlags(Int)`; raw constructor is the visible escape; unknown bits return `Err(Errno(22))` before the syscall)** — **3-3 (B1: web, devops, aiml; B2: sys, plt, min). User (BDFL) tiebreak: B1.**
  - **Web:** B1 — *"B1 turns that into a compile error, which is the better error for a new user and for an LLM that pastes `0x40`."*
  - **DevOps:** B1 — *"B1 turns that runtime EINVAL into a `blink check` error, which is the better diagnostic every time."*
  - **AI/ML:** B1 — *"Under B1 that fix also fails at `blink check`, so the only thing that compiles is a named constant, which is the portable path."*
  - **Systems:** B2 — *"B2 uses the mechanism the law already uses for `Errno` (a transparent newtype), and it depends on nothing new. B1 depends on field privacy for a stdlib type."*
  - **PLT:** B2 — *"B1 is the stronger typing rule, but Blink has no field-privacy mechanism that user code can write."* and *"I will not make a typing rule depend on a mechanism that does not exist."*
  - **Minimalism:** B2 — *"Under B2 the wrapper rejects any unknown bit with EINVAL before the syscall on every platform, so a raw native value can never reach the kernel as a native flag."*
  - **Tiebreak record.** The user asked for a code sample of each form, then chose B1. B1 depends on a field-privacy rule that the spec does not define today. A separate spec ticket covers that rule. The EINVAL check on unknown bits stays as a normative backstop: all three B1 voters asked for it in their concerns. **Web:** *"If Blink cannot hide a stdlib field today, B1 falls back to B2 in practice, and the spec must still state the EINVAL rule so both forms fail the same way on every platform."* **DevOps:** *"If non-pub fields do not stop a struct literal such as `MsgFlags { bits: 0x40 }` outside std.libc, B1 falls back to B2 without an EINVAL check, so the implementation ticket must confirm construction is blocked (or add the EINVAL check anyway)."* **AI/ML:** *"if a plain stdlib type cannot hide its field today, B1 falls back to B2 in practice, and the spec must then state the EINVAL rule for unknown bits so the escape at least fails the same way on every platform."*

### Final Spec

```blink
// std.libc
pub type MsgFlags { bits: Int }        // opaque: no public constructor or field
// MsgFlags.NONE, MsgFlags.PEEK — Blink bit numbering, translated to native MSG_* in C

fn recv_bytes(fd: Int, max: Int, -- flags: MsgFlags = MsgFlags.NONE) -> Result[Bytes, Errno] ! IO
fn send_bytes(fd: Int, data: Bytes, -- flags: MsgFlags = MsgFlags.NONE) -> Result[Int, Errno] ! IO
fn recvfrom_bytes(fd: Int, max: Int, -- flags: MsgFlags = MsgFlags.NONE) -> Result[(Bytes, Option[SockAddr]), Errno] ! IO
fn sendto_bytes(fd: Int, data: Bytes, dest: SockAddr, -- flags: MsgFlags = MsgFlags.NONE) -> Result[Int, Errno] ! IO

// std.net
pub type Ipv4Addr { bits: Int }
pub type Ipv6Addr { hi: Int, lo: Int }
pub type SockAddr {
    V4(ip: Ipv4Addr, port: Int)
    V6(ip: Ipv6Addr, port: Int, scope_id: Int)
}

impl SockAddr {
    fn parse(s: Str) -> Result[SockAddr, NetError]     // NetError.InvalidAddr(input)
}

fn udp_bind(addr: SockAddr) -> Result[UdpSocket, NetError] ! Net.Listen
fn resolve(host: Str, port: Int) -> Result[List[SockAddr], NetError] ! Net.DNS

impl UdpSocketOps for UdpSocket {
    fn recv_from(self, -- max: Int = 65535) -> Result[(Bytes, SockAddr), NetError]
    fn send_to(self, data: Bytes, dest: SockAddr) -> Result[(), NetError]   // ! Net.Connect
    fn local_addr(self) -> Result[SockAddr, NetError]
    fn set_timeout(self, ms: Int)
    fn close(self)
}

// NetError gains Os(op: Str, code: Errno) and InvalidAddr(input: Str)
```

- **Address type.** `SockAddr` is a plain value type made only of `Int` words: no `Bytes`, no `List`, no allocation on the hot path. `flowinfo` is dropped; `scope_id` stays. It derives Eq and Hash and has Display (`10.0.0.1:53`, `[::1]:53`, `[fe80::1%2]:53`). Minimalism's concern (not voted): the IP types ship only `new`, `octets`, Display, Eq and Hash. `SockAddr.to_canonical()` is deferred; the docs on `recv_from` and `SockAddr` say that a dual-stack socket reports an IPv4 peer as `::ffff:a.b.c.d`, and that this address does not equal the plain IPv4 address.
- **libc peer value.** `recvfrom_bytes` returns `Option[SockAddr]`. `None` means "no address, or a family SockAddr does not model", and is not an error. The datagram is never lost. `UdpSocket.recv_from` unwraps it, because its sockets are AF_INET or AF_INET6. Systems' concern (not voted): an unexpected `None` must be an error value, not a panic. An AF_UNIX peer gets its own address type in its own gate.
- **Naming-law amendment (V11 item 3).** The `(buf, len)` pair is replaced in place by `max: Int` (reads) or `data: Bytes` (writes). A non-buffer out-parameter moves into the success value as a tuple after the `Bytes` or count, in C order. A pointer-typed out-parameter that may be empty is `Option`. `flags` is always the trailing keyword `-- flags`, exempt from C order. `sendto_bytes` takes `(fd, data, dest, -- flags)`. `recvmsg`/`sendmsg` and the vectored calls stay outside the law.
- **Flags.** `MsgFlags` is one type. Its bits are Blink's own; the C runtime translates them to native `MSG_*` in one shared function, and the same function rejects unknown bits with `Err(Errno(22))` (EINVAL) before the syscall, on every platform. Only `NONE` and `PEEK` ship now (`PEEK` has one value on every platform). `DONTWAIT`, `WAITALL`, `TRUNC` and `NOSIGNAL` come under the growth gate, with the `|` impl arriving with the second constant. Flags are added to `recv_bytes` and `send_bytes` before v1, because a new parameter changes the fn-value type.
- **Opaque form depends on a rule the spec does not define.** The chosen form (B1) has no public constructor or field. The spec has no field-privacy rule for user-visible types today. A separate spec ticket covers that rule. Until the rule lands, the EINVAL check is the normative backstop, and it stays after the rule lands.
- **std.net caller.** `udp_bind` takes a `SockAddr`, never a host `Str`, so DNS never hides in a bind or a send. Socket creation and bind go through one runtime intrinsic, as `blink_tcp_listen` does; there is no `libc.socket` or `libc.bind`. `resolve` returns every address. `send_to` returns no count: the wrapper checks that the kernel sent the whole datagram and returns an error if it did not. `recv_from` returns a tuple. `local_addr` and `set_timeout` ship. No `connect`, `udp_unbound`, `recv` or `send`, and no `Datagram` type.
- **`recv_from` max.** `max` is a keyword with default 65535, so the shortest call cannot truncate a datagram without a signal. The default costs a 64 KiB allocation per packet. The implementation must not zero the buffer and must not copy the result a second time. The docs state the cost next to the default and tell hot-path callers to pass `max:`.
- **Errors.** `NetError.Os(op: Str, code: Errno)` carries errno failures, so EMSGSIZE and ECONNREFUSED stay matchable. EAGAIN after a timeout maps to `NetError.Timeout`. `NetError.InvalidAddr(input: Str)` is the parse error. The §4 `NetError` list is made to match the implementation in this gate.
- **Normative text.** The received `.len()` is `min(rc, max)`. A 0-length datagram is not EOF. A datagram larger than `max` is truncated without an error. libc `! IO` wrappers are not subject to Net attenuation.
- **Stale spec line.** The §07 line `std.libc.connect(sock: I32, ...)` is replaced with the real `libc.recvfrom_bytes` signature.
- **Unit type spelling.** V6 voted `Result[Void, NetError]`, copying the TcpSocket implementation; the spec spells the unit type `()` (the `Void` rule under "The `Ptr[T]` Type", §07), so the spec text uses `Result[(), NetError]`. The meaning (no count) is unchanged.
