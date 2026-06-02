[< All Decisions](../DECISIONS.md)

# v1 `libc.*_bytes` Wrapper Minimum Coverage (A2 Ship Gate) — Design Rationale

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated
in independent-proposal → debate → vote rounds. Resolves the A2 ship gate `a5gtpj` flagged in
[`buf-u8-runtime-representation`](buf-u8-runtime-representation.md): the prior decision named only
three wrappers (`recv_bytes`, `read_bytes`, `getentropy_bytes`) and Web + AI/ML warned that A2
coverage is load-bearing — if v1 ships with gaps, users reach for the sealed-and-unnameable bridge
with no power-user fallback.

#### Phase A — Independent proposals

Six proposals spanning set membership, write-side mechanism, error type, `read_fully` placement,
and a naming discipline. Deduped mechanically into six distinct candidate sets:

- **Systems:** 5, read-side only — `{read, pread, recv, recvfrom, getentropy}`. "A wrapper earns v1 inclusion only if it crosses the bridge for a syscall whose return semantics (short counts, actual-byte-count) make hand-assembly with `scope.alloc_n[T]` + `copy_from_buf_n` genuinely error-prone." Write-side syscalls "take a `Bytes` we ALREADY have … the right lowering is `Bytes.with_ptr` (aliasing, zero-copy, `!FFI`) straight into the syscall — no bridge, no Buf, ZERO memcpy." Error type `Result[Bytes, Int]` (raw errno).
- **Web/Scripting:** 6 — `{read, write, recv, getentropy, read_fully, recvfrom}`. "The wall is: a normal dev … hits one missing primitive, and the only escape is `scope.alloc_n[T]` hand-assembly or hand-writing `@trusted @ffi.fn` bindings. That's a cliff, not a step." Flagged `read_fully_bytes` as "the wrapper that most justifies the whole `*_bytes` family existing." Structured `IoError`, hard NO on `Str`.
- **PLT:** 7 — `{read, pread, recv, write, pwrite, send, getentropy}` under **C1** (downward-closed under a direction × variant lattice) + **C2** (ship both members of a symmetric pair). "Bytes-out → `Result[Bytes, E]` where the result's `.len()` IS the actual count … Bytes-in → `Result[Int, E]` … Collapsing write-side to `Result[(), E]` would be unsound for the partial-write contract." Cited Haskell `unix` / OCaml `Unix` directional shapes.
- **DevOps/Tooling:** Tier-1 of 5 — `{read, write, recv, send, getentropy}`. "The ratified-minimum size is bounded by what the help text can name inline (~5)." Mandated ONE error type; proposed a "did-you-mean" diagnostic for missing wrappers.
- **AI/ML:** 9 — the four quadrants + offset pair + recvfrom + read_fully, anchored on a **naming law**: "a learnable, exception-free naming law is worth more than a small count." Structured `IoError`, one error type "non-negotiable."
- **Minimalism:** 3 — exactly `{recv, read, getentropy}`. "These three already span the three distinct shapes a user can hit: stream read, socket recv, and fd-less fill. That is the whole taxonomy." Cited Go: "expose the three high-level shapes in std, and shove the raw 1:1 syscall wrappers into a clearly-second-class package" — `scope.alloc_n[T]` + raw `@ffi.fn` is Blink's `x/sys`.

#### Phase B — Debate highlights

Five verified codebase facts were surfaced to the panel and drove most of the movement:
**F1** `SockAddr` is named in spec examples but undefined as a type; **F2** no UDP/datagram socket type exists in v1 (no caller for recvfrom/sendto); **F3** `NetError` is the only structured error type that exists (a new `IoError`/`Errno` would itself be gate scope); **F4** `net_tcp.TcpSocket` already covers the stream-socket read/write path; **F5** `scope.alloc_n[T]` and `Bytes.with_ptr` are real and shipped.

Key shifts:

- **recvfrom/sendto → deferred (6-0).** **Sys:** *"A wrapper whose return type (SockAddr) doesn't exist, that has no UDP socket to call it, and no stdlib caller — that's not closing a gap, it's shipping a sealed primitive into a vacuum."* **Web:** *"My 'UDP wall' argument assumed a dev could hit the wall in v1. F2 kills that … The wall is real but it moves to whenever UDP/SockAddr lands."* **AI/ML:** *"Shipping a wrapper whose return type (SockAddr) doesn't exist would be the worst possible thing for LLM correctness — it'd be a documented API that doesn't typecheck."*

- **`read_fully` → `std.io`, not `libc` (6-0).** **PLT:** *"read_fully is a derived combinator — pure Blink looping over read_bytes with zero new bridge crossing. Putting it in libc breaks the 1:1-syscall invariant that keeps the libc surface auditable; it's the same category error as bundling IoError into a primitive gate."* **AI/ML** conceded its libc-co-location argument: *"discoverability is solvable at the doc layer, not the module layer"* — retaining only a mandatory doc cross-reference from `read_bytes`.

- **Error type → thin `Errno` newtype (converged from three positions).** **DevOps** withdrew its "single IoError + rework NetError" plan once F3 showed that meant shipping new type-design at the gate: *"that's exactly the kind of elegant-but-expensive move my domain is supposed to veto, so I'll veto my own."* **PLT:** *"a raw `Int` return position means `Result[Int, Int]` for `write_bytes` — both arms are `Int`, count-written and errno, nominally indistinguishable. That's the exact confusion the type system exists to prevent."* **Min:** *"My split shipped a type-confusion to avoid shipping a type — that's false economy."* **AI/ML** withdrew NetError-reuse: *"a file write returning `NetError.IoError` is a semantic lie an LLM would find confusing."*

- **Write-side mechanism — PLT's auditability objection, then the §07.534 reversal.** PLT initially objected that `with_ptr` writes *"split the wrapper family across two trust surfaces … A reviewer auditing 'all byte-bridge crossings' via the bytes-bridge category sees the reads and MISSES the writes."* This pulled Sys to concede write-via-bridge in round 2. **DevOps** (audit-category owner) ruled the premise false: *"with_ptr is not audit-dark … its inner FFI call shows in `blink audit`. The REAL issue is a reporting gap in my category — fix it by adding a `byte-pin` subcategory, not by taxing every write with a memcpy."*

#### Phase C — Final vote

- **Q1: v1 ratified set** — **Option C (5): `{read_bytes, write_bytes, recv_bytes, send_bytes, getentropy_bytes}`** (5-1, Min dissent → A=3)
  - **Systems:** C — *"Once writes go through [their mechanism], the trust-surface objection that made me favor read-only A is gone … C is also where DevOps/AI/ML/PLT-fallback converge, so it's the stable Schelling point."*
  - **Web:** C — *"four-quadrant {read,write,recv,send} is the surface a Python/JS dev predicts after learning one member — least surprise … A blocks because read-without-write is the asymmetry wall I flagged."*
  - **PLT:** C — *"C is exactly the four base-shape direction×domain quadrants … plus the standalone CSPRNG. Every member is a base lattice point with a real v1 caller and a non-trivial crossing."* Adopted Min's foot-in-the-door argument to drop pread/pwrite: *"if 'base + a scalar arg' justifies a v1 wrapper, then pwrite, preadv, preadv2 all have identical claim."*
  - **DevOps:** C — *"A is the only option I block — it ships read with no write, so the E0822 help text's promise of 'byte-payload syscalls' is literally false."*
  - **AI/ML:** C — *"C is closed under read↔write / recv↔send symmetry, so an LLM never hits a half-pair gap that triggers name hallucination or a fall-back to copy_to_buf."*
  - *(dissent)* **Minimalism:** A (3) — *"The contested delta above 3 is entirely write-side, and write has no allocate-before difficulty — the user already holds the Bytes, so a wrapper saves nothing the read wrappers' sealing earns."* Accepted B/C, blocked nothing. **Soft consensus:** the majority's creep concern is addressed by the naming law (Q5) and the demonstrated-demand gate (Q6), both of which Min voted YES on.

- **Q2: wrapper mechanism** — **`with_ptr` (uniform)** (6-0, after Phase D — see below)

- **Q3: error type** — **thin transparent `Errno(Int)` newtype** (6-0). All six: `Result[Bytes, Errno]` / `Result[Int, Errno]`, no rich `IoError` at the gate, no `NetError` rework, transparent/zero-cost.

- **Q4: `read_fully`** — **`std.io`, not a libc member, ships at v1, doc cross-ref from `read_bytes`** (6-0).

- **Q5: naming law as normative rule** — **YES** (6-0). **Min:** *"A normative naming law is pure constraint, not surface — it ADDS nothing to the language and prevents future ad-hoc divergence."* PLT's vote bound the return shape to direction; DevOps's and AI/ML's flagged the out-of-scope carve-out (no Buf-naming, no iovec/vectored).

- **Q6: demonstrated-demand growth gate** — **recorded in DECISIONS.md** (Min YES). DevOps's "did-you-mean" diagnostic: **v1-release deliverable, not a ratification-gate blocker.**

#### Phase D — Round 2 (Q2 only)

Phase C Q2 came in 4-2 toward BRIDGE (Sys, Web, AI/ML[non-binding] vs DevOps, PLT). Before locking, a verified spec fact was surfaced:

> **F6/F7** — §07.532-545 already designates `Bytes.with_ptr` as *the* mechanism for the `read`/`write`/`recv`/`send` family, and the spec's existing worked example implements `read` (a Bytes-OUT syscall) as `Bytes.zeroed(n)` + `with_ptr` + `slice(0, got)` — **not** via `copy_from_buf_n`. A BRIDGE outcome would have contradicted ratified spec and required rewriting that example.

On the focused re-vote, **Q2 resolved 6-0 to `with_ptr`** — all four BRIDGE voters flipped:

- **Systems:** *"my BRIDGE vote was arguing against the spec's own ratified design, and my one premise (audit-darkness) is false … it matches the spec and it's the zero-copy path on the hottest I/O ops."* Concern: the `@ffi` call must stay inline in the closure (the pin-escape check is syntactic).
- **Web:** *"BRIDGE now means rewriting working spec to buy nothing and pay a memcpy."*
- **AI/ML:** *"BRIDGE would force a spec rewrite and split the family, the opposite of my goal … DevOps's byte-pin audit subcategory delivers the uniform single-category auditability I wanted without the memcpy."*
- **Minimalism:** *"with_ptr is the already-shipped primitive the spec ALREADY uses for reads (zero new mechanism) while the bridge path drags in copy_to_buf + Buf allocation + a memcpy on data we only read — with_ptr is unambiguously the LESS-machinery choice."*
- **PLT** reconciled its directional-typing model: *"I was conflating the typing asymmetry (real) and the mechanism asymmetry (an error) … It reduces to 'with_ptr for all, truncation is `slice(0, got)` not `copy_from_buf_n`' — and that's fine, because the soundness was always in the return type, never in which primitive does the memcpy."*
- **DevOps** confirmed the boundary and audit coverage: *"They're not 'reads vs writes' — that was the panel's wrong axis — they're 'user-owned Bytes (with_ptr) vs sealed Buf (bridge).' … byte-pin covers BOTH read-side and write-side with_ptr pins."*

### Final Spec

```blink
fn read_bytes(fd: Int, max: Int) -> Result[Bytes, Errno] ! IO
fn recv_bytes(fd: Int, max: Int) -> Result[Bytes, Errno] ! IO
fn write_bytes(fd: Int, data: Bytes) -> Result[Int, Errno] ! IO
fn send_bytes(fd: Int, data: Bytes) -> Result[Int, Errno] ! IO
fn getentropy_bytes(n: Int) -> Result[Bytes, Errno] ! IO
```

Locked design points:

- **v1 set = exactly these five** (file/socket × read/write quadrants + standalone CSPRNG). Blocks v1 release.
- **Mechanism = `Bytes.with_ptr`** for the whole family (read pins `Bytes.zeroed(n)` + `slice(0, got)`; write pins caller's `Bytes` read-only). `copy_to_buf`/`copy_from_buf_n` reserved exclusively for the sealed-`Buf` path. The `@ffi` call stays inline in the `with_ptr` closure.
- **Directional return-typing** — Bytes-out → `Result[Bytes, Errno]` (`.len()` = actual count, short read = success); Bytes-in → `Result[Int, Errno]` (count written, short write = `Ok(n)`).
- **Error type = thin transparent zero-cost `Errno(Int)` newtype.** Rich `IoError` is a separate post-v1 additive task; `Errno` is domain-neutral.
- **No `flags` arg in v1** — `recv_bytes`/`send_bytes` pass `flags = 0`; flagged variant post-v1.
- **Naming law (normative)** — `<posix>_bytes`, POSIX arg order with `(buf,len)` → trailing `max:Int`/`data:Bytes`, direction-bound return, `! IO`, `with_ptr` mechanism; post-v1 additions conform. Vectored/`msghdr`/non-`Bytes`-buffer syscalls are out of the law's scope.
- **`read_fully` → `std.io`** (pure Blink), ships at v1, doc cross-ref from `read_bytes`. Not a libc member.
- **`byte-pin` audit subcategory** under `bytes-bridge` (covers all `with_ptr` pins) — must ship with the wrappers.
- **Growth gate** — added only on demonstrated high-frequency Bytes-in/out usage where `alloc_n` is ergonomically prohibitive; never speculative.
- **Deferred:** recvfrom/sendto (post-v1 UDP gate with `SockAddr`); pread/pwrite (demonstrated-demand); readv/writev (needs `iovec` bridge).

### Follow-Up Tickets

- **Implementation** (`type:project`) — implement the five wrappers + `Errno` + `byte-pin` audit subcategory.
- **`std.io.read_fully`** (`type:feature`, v1-blocking, coupled) — pure-Blink, with `read_bytes` doc cross-ref.
- **did-you-mean diagnostic** (`type:feature`) — v1 release deliverable, not ratification-gate-blocking (DevOps).
- **post-v1 UDP gate** (`type:spec`) — `SockAddr` + `recvfrom_bytes`/`sendto_bytes` + flagged recv/send.
