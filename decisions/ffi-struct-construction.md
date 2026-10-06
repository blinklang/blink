[< All Decisions](../DECISIONS.md)

# FFI Struct Construction & Buffer Bridges — Design Rationale

Bridge task `tg8st2` — "Spec: Ptr[U8] offset access / FFI struct construction from Blink." Driver: wink.app's `poll(2)` binding (third wink module to hit the FFI wall). Section 9.1.1 fixes `Ptr[T]` as an opaque single-cell handle with a frozen 8-op table; that's right for SQLite-handle-shaped pointer types but cannot construct values whose C declaration is a multi-field struct or an N-element array (`pollfd[]`, `iovec[]`, `sigaction`).

### Problem Statement

The compiler's `Ptr[T]` is an opaque, single-cell C-pointer surface. The codebase fact (`bootstrap/runtime_core.h:146-174`, `benchmarks/http_lookup/blink/server.c:468-483`) is that `Bytes.data` is `GC_MALLOC`/`GC_REALLOC`-allocated. The driver case is `pollfd[]` for `poll(2)`, but the same gap blocks every libc syscall taking a struct or array of structs. The 6-expert panel deliberated five mechanism options (α-1, α-2, α-3, α-4 — variants of Bytes-pin; β-minimal — `@ffi.struct` records; γ — pure stdlib `libc.*` wrappers / no language addition).

### Panel Deliberation

Six panelists (Systems, Web/Scripting, PLT, DevOps, AI/ML, Minimalism) deliberated across two rounds of open debate (Phase B-r1, Phase B-r2) followed by a silent vote (Phase C).

#### Phase A — Independent proposals

- **Systems:** `Bytes.with_ptr` (P1) — closure-scoped raw-buffer borrow on `Bytes`. *"`Bytes` is already a contiguous, owns-its-storage, FFI-shaped C struct. Building `pollfd` is just writing 8 little-endian bytes into a `Bytes` and handing the `data` field to `poll()`."* Defends with `! BytesGrow` effect to forbid realloc during the borrow.
- **Web/Scripting:** W1 — `scope.bind(bytes) -> Ptr[U8]` bridge tied to `ffi.scope`. *"Don't invent a new buffer type. `Bytes` already has `write_i32_le`, `write_u16_be`, `set`, `get`, `slice`, `len`, `read_*_le/be`. Every JS/Python/TS/Kotlin dev already knows 'build a byte buffer, hand its address to C.'"*
- **PLT:** P1 — `Buf[T]` as N-cell sibling of `Ptr[T]`, scope-bound, with `field_addr` on `Ptr[@ffi struct]` for typed field access. Explicitly rejects any Bytes↔Ptr bridge: *"There is **no** Bytes↔Ptr bridge in P1 — Bytes stays opaquely GC-managed, which is exactly what soundness wants."* Names §9 moving-GC firewall as load-bearing.
- **DevOps:** Two-mechanism proposal — *"`Ptr[Struct].field` access on `@ffi.struct` types — the primary mechanism"* plus *"`Buf[T]` — a typed, fixed-length, scope-tied raw buffer — the secondary mechanism for `[N]T` arrays."* Explicit rejection of Bytes-as-buffer as primary: *"It is expressible (Bytes already has `read_u32_le` etc.) but the diagnostic surface is awful: every OOB error is a runtime `Result.Err(Str)` with no caret, no field name, no hover, no completion, no audit category. Bytes-as-buffer is a 2014 LuaJIT idiom; we are not shipping that as the recommended path in 2026."*
- **AI/ML:** P1 — *"`Bytes` IS the struct, surfaced via `scope.pin(b)` to hand the GC-managed buffer to C as a `Ptr[U8]` for the duration of the ffi scope. Zero new types. Zero new allocators. The byte-builder methods Blink already ships *are* the struct constructor."*
- **Minimalism:** P0 — REJECT. *"Formalize the C-shim path. No language addition."* Fallback P1 admits `Bytes.as_ptr` only if the foundational gap is proven. Minimalism explicitly champions "do nothing / solve via stdlib" as a first-class option.

#### Phase B — Debate highlights

**Round 1.** PLT's §9 moving-GC objection landed as load-bearing: any α variant that hands a `Ptr[U8]` aliasing `Bytes.data` to user code makes a future moving-GC migration ABI-breaking. Sys answered with the BDW non-moving design contract plus closure-capture-keeps-`self`-reachable plus `! BytesGrow` forbids realloc — three layers of defense. Web argued α-3 (`FfiScope.pin`) over α-1 to avoid nested-closure friction on multi-buffer cases (`readv`, `sendmsg`). DevOps's silent-corruption attack on α (wrong width / wrong offset / field-reorder after libc bump = silent CVE) shifted weight toward β. Min flagged that α-as-family creates a moving-GC migration debt that β does not.

**Round 2.** Web pivoted: *"I'm pivoting from α-3 to β-minimal with α-1 as stdlib helper. The codebase facts killed my R1 position and I'm not going to defend an unsound proposal because of pride."* On reading `runtime_core.h`, web confirmed `GC_REALLOC` swaps the data pointer today — *"aiml is correct: this is observable today, on the existing non-moving Boehm collector."* Web conceded E0820 is dead because detection requires alias analysis which the panel rejected. Web's conversion to β converged with PLT and DevOps.

Min pivoted: *"With one shape requirement... `blink audit` over `@ffi.struct` declarations is qualitatively better than `blink audit` over a directory of C files that the compiler cannot parse. I had been treating 'FFI under @trusted' as a flat audit surface; devops is right that it isn't — it's stratified by what the compiler can introspect. β raises the floor."* Min then proposed `β + γ-doctrine`: β-minimal as the mechanism, with `std.libc.*` as the curated user-facing surface and user-defined `@ffi.struct` "discouraged but allowed."

AI/ML stress-tested PLT's nested-closure charge: *"plt is wrong for the single-call case (pollfd loop), right for the two-buffer case (readv/writev with iovec)."* Stayed with α-1 as primary but accepted α-3 as fallback if multi-buffer composition wins the room.

Sys held α-1 over β as primary: *"β forces a typed-struct detour for the entire `void*`/`u8*` libc surface (`read`, `write`, `recv`, `send`, `mmap`, `ioctl`-data, `getrandom`) where the C side already wants raw bytes and the Blink side already has them."*

PLT's R2 framed the convergence as `β-minimal + α-1-as-helper + γ-doctrine`. DevOps converged on the same.

#### Phase C — Final vote

**Q-Mechanism: A (β-minimal + α-1 helper + γ-doctrine)** — vote 4-2 (Sys, AI/ML voted B = α-1 primary).

- **PLT (A):** *"Only A admits a sound typing rule for the design-driver class (poll/readv/writev/sendmsg — buffer-of-pointers shapes), because β's `Buf[T]^σ` + `@ffi.struct` composes via σ-tag unification while α-1's CPS bracket cannot express dynamic-arity nested pins. α-1 alongside as a stdlib helper preserves the cheap one-shot `(ptr, len)` case (`write(fd, b, n)`) without forcing a copy, and the γ doctrine layer captures min's correct insight that user-facing surface should be curated `std.libc.*` modules."*
- **DevOps (A):** *"β-minimal as primary gives the diagnostic surface my domain requires — typed field access on `Ptr[@ffi struct]` makes width/endian/padding mistakes either uncatchable or caught at the field declaration with a caret span. The α-1 stdlib-helper carve-out is acceptable because it lives under `@trusted` in `std.libc.*`, not in user code, so the audit surface stays clean."*
- **Web (A):** *"β-minimal gives JS/TS-shaped devs the field-name DX they expect (`p.fd.write(v)` reads like a TS interface), with static-assert turning silent corruption into compile-time error — the failure mode JS devs are least equipped for. α-1 retained as helper preserves the Node `Buffer`-familiar path for opaque-byte syscalls (read/write/recv/send) without forcing offset arithmetic into the struct path."*
- **Min (A):** *"The β-minimal + γ-doctrine compromise is the only option that prices auditability, conceptual surface, and v2-flexibility on the same scale. β-minimal puts the C-shape information where the compiler can introspect it (devops's load-bearing R1 point), γ-doctrine keeps user code on the curated `std.libc.*` path so the language surface doesn't compound through user-defined `@ffi.struct` proliferation."*
- **Sys (B, dissent):** *"From the systems voice, α-1 is zero-overhead and closes the actual capability gap. β forces a typed-struct detour for the entire `void*`/`u8*` libc surface where the C side already wants raw bytes and the Blink side already has them. β-as-primary plus α-1-as-helper means writing two FFI styles for one capability."*
- **AI/ML (B, dissent):** *"α-1 has the lowest learnability cost of the three (zero new language concepts; reuses Bytes + closure + Ptr[U8] which the LLM already knows from spec), and locality-of-failure at the call site is the strongest AI-first property. Option A bundles three mechanisms behind one curated surface — that is three things the LLM has to learn the boundaries between, and 'user-defined @ffi.struct discouraged but allowed' is exactly the dual-path ambiguity that destroys first-try generation accuracy."*

Soft consensus: dissenters' concerns (β surface tax, dual-mechanism learnability) are explicitly acknowledged in the majority's Concern fields, and option A explicitly retains α-1 for the byte-payload cases Sys defends. No Phase D triggered.

**Q-α-realloc-rule: C (closure-lexical no-grow check)** — vote 4-1-1 (PLT voted A = `! BytesGrow` effect; Web voted D = runtime debug-assert).

- **Sys (C):** *"α-1's closure body is a syntactic region with a single literal receiver name; the parser already has every fact needed to check 'does the body call any growth-effecting method on that name.' This is a flat AST walk, not alias analysis, and it explicitly does not poison Bytes-mutator signatures the way `! BytesGrow` would."*
- **DevOps (C):** *"Under α-1 the closure has no rebindable name for the pinned `Bytes`, so a parser-level 'no growing op syntactically present in the closure body' check is sound and trivial. `! BytesGrow` poisons every `Bytes` signature in the language; E0820 is silently unsound under transitive aliasing; runtime asserts catch nothing at compile time and ship as production failures."*
- **AI/ML (C):** *"Under α-1 the pinned `Ptr[U8]` is bound only inside the closure body and is not rebindable from outside, so the no-grow check is purely a parser/typecheck-local question over the closure body's AST — no alias analysis, no new effect, no runtime assert."*
- **Min (C):** *"Under option A's mechanism, α-1 is *only* used closure-scoped — there is no rebindable Ptr[U8] name to track, so a parser-level lexical no-grow check inside the closure body is sufficient and precise."*
- **PLT (A, dissent):** *"Once you take the indirect case seriously (`helper(b)` where `helper` may grow `b`), B and C collapse into either over-rejection or signature-level annotation — and signature-level annotation *is* an effect. `! BytesGrow` is the honest framing of the propagation the typechecker must do anyway."*
- **Web (D, dissent):** *"α-1's closure body is one short lexical region — production cost of a runtime check is negligible, and `--debug` catches the mistake during dev/test before it ships. Effect-token (A) poisons every Bytes-touching signature in the language for one helper; static error (B) requires alias analysis we explicitly rejected. Parser-level check (C) is fragile against helper functions called from inside the closure body."*

**Q-α-bytes-offset-API: SHIP** — vote 6-0.

All panelists agreed `set_*_le/be(off, v)` is the missing symmetric half of the existing `read_*_le/be(off)` family and ships regardless of mechanism. PLT: *"Bounds-check semantics must return `Result[(), Str]` (matching the read family) rather than panic, or the two families diverge in error model."*

**Q-static-assert-codegen: SHIP-v1** — vote 6-0.

- **DevOps:** *"This is the single highest-leverage item across the entire proposal package and works under any Q-Mechanism outcome — it locks Blink-side declarations to the C definition at `cc` time, catching every cross-compile / libc-version drift bug before the segfault."*
- **PLT:** *"Without `_Static_assert(sizeof == N && offsetof == M)`, β is 'trust me, the layout matches' — the C compiler is the only authoritative oracle for ABI layout."*

**Q-shim-tooling-orthogonal: SHIP** — vote 6-0.

`blink shim init` ships regardless of the mechanism vote. AI/ML: *"Even under α as winner, escape-hatch C shims will exist for SIMD/aligned/exotic-layout cases."* Min: *"It is the difference between 'FFI is an undocumented escape hatch' and 'FFI has an official, scaffolded, audited entry point.' That's real engineering value at zero language cost."*

**Q-bytes-bridge-coexistence: FORBID-user-with-stdlib-copy** — vote 4-1-1 (Sys voted ALLOW-as-escape; AI/ML voted FORBID-strictly).

- **PLT:** *"The moving-GC firewall stays intact only if no Bytes→Ptr address ever crosses into user code. Stdlib `libc.copy_to_buf` / `libc.copy_from_buf` cross *byte values*, not addresses, so the language-level invariant ('no `Ptr` or `Buf` value names GC-managed memory') is preserved."*
- **DevOps:** *"Forbidding user-code Bytes→Ptr preserves plt's moving-GC firewall as a mechanically-checkable type-system rule, and the `libc.copy_to_buf`/`copy_from_buf` v1 stdlib commitment from plt covers the real use cases (HTTP body → C parser, JSON bytes → libxml). The memcpy cost is negligible for the workloads that hit this path, and 'values cross, addresses don't' is the only soundness story I can defend at audit time."*
- **Web:** *"User-code Bytes→Ptr is the soundness violation we just spent two rounds rejecting; allowing it as an 'escape hatch' means it shows up in tutorials and Stack Overflow answers and becomes the de-facto path."*
- **Min:** *"Forbidding the bridge in user code closes the C++-style accretion path where today's 'escape hatch' becomes tomorrow's 'common pattern.'"*
- **Sys (ALLOW-as-escape, dissent):** *"Under α-1-primary this question is a non-issue (the bridge IS the recommended path). Under the β-leaning consensus this vote anticipates, FORBID-user-with-stdlib-copy mandates a copy on every byte-shaped FFI call (`read`, `write`, `recv`, `send`, `getrandom`) where zero-copy was the whole point — that's a runtime tax the Systems voice cannot endorse."*
- **AI/ML (FORBID-strictly, dissent):** *"FORBID-strictly produces the cleanest single mental model: Bytes is for in-Blink data, Ptr[U8]/Buf is FFI-only, no bridge in either direction."*

Note: Sys's zero-copy concern is addressed by retaining `Bytes.with_ptr` as the in-stdlib helper for `read`/`write`/`recv`/`send`/`mmap` — those bindings keep zero-copy via `with_ptr`, while the user-facing `copy_*` helpers handle the cases where the syscall semantics require a bridge.

**Q-extra-warnings: DROP-all-three (W0811, W0813, E0818)** — vote 6-0.

All six panelists agreed to drop W0811 (init-flow analysis), W0813 (zero-len Buf), and E0818 (endian-tag tracking) from v1. Min: *"Each warning is conceptual surface that ships forever, and none of these have driver-grounded justification — they're speculative defenses against errors no panelist can name a real instance of."*

### Final Spec

```blink
// β-minimal: typed C-shaped record
@ffi.struct(header: "poll.h", name: "pollfd")
pub type Pollfd {
    fd: I32,
    events: I16,
    revents: I16,
}

// Field access on Ptr[@ffi.struct T]
with ffi.scope() as scope {
    let p = scope.alloc[Pollfd]()
    p.fd.write(fd)
    p.events.write(POLLIN)
    let rc = c_poll(p, 1, timeout_ms)
    let revents = p.revents.read()
}

// Array allocation
let pfds = scope.alloc_n[Pollfd](fds.len())
let p = pfds.offset(i)

// α-1 helper for opaque byte payloads (stdlib only)
let buf = Bytes.zeroed(n)
let got = buf.with_ptr(fn(p) { c_read(fd, p, n) })

// Bytes ↔ Buf only via copy, only in stdlib
let buf = libc.copy_to_buf(my_bytes)
let bytes = libc.copy_from_buf(c_buf)
```

Locked design points:

- **β-minimal** is the primary mechanism — `@ffi.struct(header, name)`, typed `Ptr[T].field.read()/write(v)` desugar, `scope.alloc_n[T](n)`.
- **α-1** (`Bytes.with_ptr`) ships as a stdlib helper for opaque-byte FFI bindings (`read`/`write`/`recv`/`send`/`mmap`/`iovec.iov_base`). It is `! FFI`-effected and used only inside `std.libc.*` and other curated bindings.
- **γ-doctrine** — `std.libc.*` is the recommended user-facing surface; user-defined `@ffi.struct` outside stdlib is discouraged but not banned. Tripwire: panel reconvenes if `blink audit` shows >50 user-defined `@ffi.struct` types (or 5+ projects vendoring equivalent `@ffi.struct` declarations) within 12 months.
- **Closure-lexical no-grow check** — parser-level rejection of growth-effecting calls on the receiver inside `Bytes.with_ptr`'s closure body. Diagnostics `E0814` (growth call) and `E0815` (Bytes argument escape).
- **`set_*_le/be(off, v)`** — 12 new methods on `Bytes` (6 widths × 2 endians), bounds-checked vs `len`, `Result[Void, Str]`. Plus `Bytes.zeroed(n)`. Symmetric counterpart of existing `read_*_le/be(off)` family.
- **`_Static_assert(sizeof == N && offsetof == M)` codegen** — emitted per `@ffi.struct` declaration, sourced from `[native-dependencies].headers`. `--strict-struct-layout` flag default-on for `@ffi` modules; `W0812` (missing canonical header) escalates to error under the flag.
- **Bytes ↔ Ptr/Buf bridge forbidden in user code.** Sanctioned crossings: `Bytes.with_ptr` (stdlib closure-pin), `libc.copy_to_buf` (Bytes → Buf, copy), `libc.copy_from_buf` (Buf → Bytes, copy). Diagnostic `E0817` for user-code violations.
- **`blink shim init`** — CLI scaffolds vendored C shim + `[native-dependencies]` registration + `@trusted` wrapper template. Third-tier escape (after `std.libc.*` and `@ffi.struct`).
- **Diagnostics added:** `E0812`, `E0813`, `E0814`, `E0815`, `E0817`, `W0812`. `E0601` gains `value-escape` and `tag-mismatch` sub-kinds. `W0811`, `W0813`, `E0818` rejected.
