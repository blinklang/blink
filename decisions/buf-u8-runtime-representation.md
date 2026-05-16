[< All Decisions](../DECISIONS.md)

# Buf[U8] Runtime Representation for FFI Bridge — Design Rationale

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in independent-proposal → debate → vote rounds. Resolves Tier 3 gap `gaf7gh`: "Spec: Buf[U8] runtime representation for FFI bridge."

#### Phase A — Independent proposals

The panel produced six initial proposals spanning six sub-questions: V1 (one generic type vs. two), V2 (user surface), V3 (nameability), V4 (bridge primitive shape), V5 (length API), and one diagnostic question (warn on non-`U8` element types). Proposals were deduped mechanically in Phase A.5 into a multi-dimensional option space; the bridge alphabet concept emerged from PLT's Phase A proposal.

#### Phase B — Debate highlights

Phase B ran five rounds. The major position shifts:

- **R1 → R2 (V1):** Two panelists (Sys, Min) initially favored two distinct types — `Buf[U8]` for the bridge, `Buf[T]^σ` for `scope.alloc_n[T]` — to keep the bridge type's permissible elements maximally explicit. PLT countered that "two types differing only by a permitted-element-set constraint" is a coverage-gate concern, not a parametricity concern, and proposed the **bridge alphabet** mechanism: one generic type, with a separate spec constant enumerating permitted bridge-flow element types. Min flipped on R2, citing "one nominal type costs less language surface than two." Sys flipped on R3 after PLT showed that source-determinism of `W0816` requires the alphabet to be a *language-version* constant, not a typing-rule restriction.

- **R2 → R3 (V3):** AI/ML and DevOps initially wanted `Buf` fully unnameable in user-typed positions to maximize learnability. PLT objected that fully unnameable closes off `@ffi.fn` bindings as well, which is the legitimate authoring surface. PLT proposed the **V3 carve-out**: nameable inside `@ffi.fn` / `@ffi.struct`, error `E0822` everywhere else, with inferred let-bindings (`let b = libc.copy_to_buf(bs)`) explicitly legal because they don't *name* the type. All six panelists converged on this on R3.

- **R3 → R4 (warning category):** DevOps initially proposed `W08xx` as a stdlib-version-coupled warning ("warn when `Buf[T]` is used and stdlib lacks a wrapper"). PLT rejected this as a **diagnostic category violation**: a warning whose firing depends on installed stdlib version is not reproducible across CI environments, and `-Werror` becomes flaky. The panel replaced W08xx with **W0816** — source-deterministic, fires on bridge-alphabet membership only. DevOps endorsed this on R4.

- **R4 → R5 (A2 coverage):** Web and AI/ML both raised that A2 wrapper coverage is **load-bearing** — if `libc.*_bytes` ships with gaps, users will be stranded since `Buf` is sealed. The panel adopted **A2 as ratified-minimum-set** (`recv_bytes`, `read_bytes`, `getentropy_bytes` at v1 ship) rather than "we'll add what people ask for."

- **R5 → R5b (final tightening):** Sys added two conditions: **C1** (per-declaration suppression `@allow(W0816)`) for vendored bindings; **C2** (help text never says "wait for v2") since the answer `scope.alloc_n[T]` is the working answer indefinitely. PLT refined the wording to "bridge alphabet" not "stdlib bridge constructors" to keep the diagnostic spec-grounded. All six panelists signaled stable/ready-to-vote.

#### Phase C — Silent vote

**Q: Adopt SYNTHESIS-R5b in full?** (6-0 YES)

- **Systems:** YES — "The runtime layout lands clean from a Systems lens — one `blink_buf_u8_t` struct, malloc'd, scope-tied free walk on `with ffi.scope` unwind, zero GC interaction, zero finalizer machinery, zero pin/unpin dance. The moving-GC firewall holds because no `Ptr[U8]` view of the bridge `Buf` exists in user code (no `.as_ptr()`, no `.read`/`.write`) and the address only materializes at the FFI codegen seam where the compiler controls it. `copy_to_buf`/`copy_from_buf` keep the per-call `memcpy` cost visible at the source line — that's the Go-`[]byte`-mistake we explicitly avoid — while A2's `recv_bytes`/`read_bytes` give the convenience path without hiding the primitive."
  - *Concern:* "SYNTHESIS-R5b commits us to *two* `memcpy`s on every Bytes→FFI→Bytes round trip — fine for sub-page payloads, but for multi-MB cases (compress/hash of a large `Bytes`) we will eventually want a pinned-Bytes or mmap-backed-view escape hatch, and if we don't record that as a known v2 question now, someone will reach for `.as_ptr()` and re-litigate V2."

- **Web/Scripting:** YES — "A2 makes the JS/Python-dev 90% case (`libc.recv_bytes(fd, cap) -> Bytes`) the primary user-facing API — the same shape that already ships in `lib/std/net_tcp.bl` as `tcp_read_bytes`, so devs get a validated, familiar pattern with `Bytes.len()` for free and never touch Buf, scope, or Ptr. The sealed bridge + PLT V3 carve-out + W0816 give the `@ffi.fn` binding-author the right loop: caret-at-decl-site warnings that redirect to the working `scope.alloc_n[T]` path instead of dead-ending in 'wait for v2.' Two-copy round-trip cost is paid by the bridge, not the user surface, and is grep-able in the implementation rather than hidden."
  - *Concern:* "A2's quality-of-coverage is load-bearing — if `libc.*_bytes` ships with gaps (no `recvfrom_bytes`, no `pread_bytes`, no `iovec` helper), users will end up reaching for the sealed-and-unnameable bridge as an escape hatch and hit a wall, since W0816 + E0822 + no-`.as_ptr()` together leave no power-user path short of writing `@trusted` wrappers; the v1 helper coverage list deserves explicit panel ratification before release, not a 'we'll add what people ask for' plan."

- **PLT:** YES — "SYNTHESIS-R5b preserves the load-bearing PLT properties — σ-tied region typing keeps the moving-GC firewall (R1) intact, parametricity is encoded as a type property with the bridge alphabet held as a separate spec constant, and a fully sealed user surface closes the slope from `.len()` to `.read(i)`/`.write(i,v)`. The V3 carve-out (E0822 in Blink-typed code, nameable in @ffi declarations) is the right type-theoretic shape: it treats the FFI seam as a foreign-import surface where opacity is *defined*, analogous to Haskell's `foreign import ccall` allowing `ForeignPtr` in import decls. W0816 with the 'bridge alphabet' wording is source-deterministic — a function of (source, language version) only — which keeps compiler diagnostics free of stdlib-version coupling."
  - *Concern:* "The bridge alphabet `{U8}` is a closed spec-encoded set today; if future panels ever make it user-extensible (third-party crates declaring 'this T is bridge-instantiable'), W0816's source-determinism collapses and we re-enter the W08xx category violation — the panel should treat bridge-alphabet expansion as a *language version* change, never an open extension point."

- **DevOps/Tooling:** YES — "Diagnostically clean — `Buf[T]` sealed (no `.len()`, no `.as_ptr()`, no `.read`/`.write`), bridge has a single deterministic API shape (`copy_to_buf` / `copy_from_buf` / `copy_from_buf_n`), and V3's `@ffi.fn` carve-out keeps E0822 narrow enough that everyday user code never has `Buf` appear in an error message. The governance triad (A1 audit category + `--no-unaudited-bridges`, A2 stdlib higher-level helpers as primary user API, A3 hover/doc opaque banner) gives both the dev loop and the security-review loop a clear, scriptable surface. W0816 in source-deterministic form preserves CI reproducibility and `-Werror` semantics across stdlib versions — the failure mode I cared most about."
  - *Concern:* "The two-construction-seams story (`copy_to_buf` returns `Buf[U8]` vs `scope.alloc_n[T]` returns `Buf[T]^σ` — same type, different origin and audit category) will demand unusually careful `blink doc` and onboarding material; if the doc page is sloppy, W0816 misfires and 'why does this Buf work here but not there' friction-log tickets are predictable."

- **AI/ML:** YES — "SYNTHESIS-R5b makes the correct user-facing code (`libc.recv_bytes`, `libc.getentropy_bytes`) the path of least resistance for both humans and LLMs, while keeping `Buf[T]` available exactly where LLMs already know how to write it — inside `@ffi.fn`/`@ffi.struct` declarations, which mirror C-header transcription (a well-trained task). Sealing the type in user code via E0822 plus omitting `.len()` removes the two surfaces where LLMs most often hallucinate — constructors and container-style methods. W0816's source-deterministic warning text is invariant across stdlib versions, so the diagnostic remains stable training-data signal. A2 shipping in v1 is the load-bearing piece that prevents `copy_to_buf` / `copy_from_buf` from becoming the canonical pattern LLMs learn first."
  - *Concern:* "If A2 wrapper coverage is incomplete at v1 ship (e.g., common syscalls like `pread`/`recvfrom`/`read_fully` missing), LLMs will reach for the `copy_to_buf` / `copy_from_buf` primitive and that usage pattern will leak into training data before we close the gap — so v1 needs an explicit minimum wrapper set, not just 'the three named here.'"

- **Minimalism:** YES — "The synthesis hits the minimalism floor on every variation that mattered — sealed bridge with zero methods (V2), no `.len()` surface (V5), E0822 keeping `Buf` out of regular Blink code (V3), source-deterministic W0816 redirecting users to an already-existing v1 tool (`scope.alloc_n[T]`). One nominal type (V1 Position A) costs less language surface than the two-type bridge I proposed in R2, and PLT's 'coverage gate, not parametricity restriction' preserves the cheap additive-retrofit property without a spec amendment to `ffi-struct-construction.md`. The §9.1 footnote rewrite is a contradiction-resolution, not a feature addition — that's net subtraction from the spec surface."
  - *Concern:* "A2's curated helpers (`libc.recv_bytes`/`read_bytes`/`getentropy_bytes`) are the foot in the door for unbounded stdlib growth; the panel must hold the line that future A2-style helpers ship only on demonstrated high-frequency Bytes-in/Bytes-out usage, not as a default policy for every `uint8_t*` C function."

#### Phase D — Round 2

Not triggered. 6-0 unanimous result skipped Phase D entirely.

### Final Spec

```blink
// Allowed in @ffi.fn / @ffi.struct declarations:
@ffi.fn("c", "read")
fn libc_read(fd: I32, buf: Buf[U8], cap: I64) -> I64

// Allowed (inferred let-binding — Buf name not written):
with ffi.scope() {
    let buf = libc.copy_to_buf(my_bytes)
    libc_some_call(buf)
}

// Forbidden in user Blink-typed code (E0822):
fn process(b: Buf[U8]) -> Buf[U8] { ... }       // E0822
let b: Buf[U8] = ...                            // E0822
struct Wrapper { inner: Buf[U8] }               // E0822

// W0816 — non-U8 element type in @ffi declaration:
@ffi.fn("c", "memcpy_i32")
fn memcpy_i32(dst: Buf[I32], src: Buf[I32], n: I64)
// → W0816: Buf[i32] declared in @ffi.fn signature; the byte-bridge
//          primitives only accept Buf[U8] in language v1. For a typed
//          scope-tied region use `scope.alloc_n[i32](n)` instead.

// Primary user-facing API (no Buf naming required):
let bs = libc.recv_bytes(fd, 4096)?
let entropy = libc.getentropy_bytes(32)?
let chunk = libc.read_bytes(fd, 8192)?
```

Locked design points:

- **One generic type** `Buf[T]^σ`, region-tied to its allocating `ffi.scope`, no GC management.
- **Bridge alphabet** `{U8}` in v1 — a language-version constant, never user-extensible.
- **Sealed surface** — no `.len()`, no `.as_ptr()`, no `.read`/`.write`, no public constructors.
- **V3 carve-out** — `Buf` nameable inside `@ffi.fn` / `@ffi.struct` and via type inference; `E0822` otherwise.
- **Free-return bridge primitives** — `copy_to_buf`, `copy_from_buf`, `copy_from_buf_n`; length read from struct.
- **W0816** — source-deterministic warning on non-bridge-alphabet `T` in `@ffi` declarations; per-decl suppressible via `@allow(W0816)`; help text never references future versions.
- **A1 audit category** — `bytes-bridge` with `bridge-call` and `buf-mention` subcategories; `--no-unaudited-bridges` CI flag.
- **A2 curated stdlib helpers** — `libc.recv_bytes`, `libc.read_bytes`, `libc.getentropy_bytes` ship in v1 as the primary user-facing API.
- **A3 documentation** — `blink doc` and LSP hover render an "opaque, σ-tagged, bridge-only" banner for `Buf[T]^σ`.

### Follow-Up Tickets

Open as `br` tasks tagged `repo:blink` after this decision lands:

- **Sys concern:** "Track v2 zero-copy escape hatch design — pinned-`Bytes` or mmap-backed-view" — `type:spec`, blocked on demonstrated large-payload need.
- **Web/AI-ML concern:** "Ratify v1 A2 wrapper coverage minimum set" — `type:spec`, blocking v1 ship gate.
- **DevOps concern:** "Write `blink doc` page distinguishing the two `Buf` construction seams" — `type:chore`.
- **PLT concern:** "Spec constraint: bridge alphabet expansion is a language-version change" — file as `type:spec` add-on to language-versioning section.
