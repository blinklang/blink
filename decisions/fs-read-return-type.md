[< All Decisions](../DECISIONS.md)

# Filesystem `fs.read` Return Type (`Result[T, FsError]`) — Design Rationale

Resolves **br jr4xf7** — "What does `fs.read` return — spec says `Result`, the compiler emits a bare `Str`." Three questions were on the table:

- **Q1** — return type and error type of the four v1 `fs` operations.
- **Q2** — one path-taking API, or a two-form API that also takes a file handle.
- **Q3** — names: the spec's `fs.list` / `fs.delete`, or the implementation's `fs.list_dir` / `fs.remove`.

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in
independent-proposal → debate → vote rounds.

#### Phase A — Independent proposals

Five of six opened on **bare `Errno`** (Option E); only DevOps opened on a **rich struct** (Option I). Every panelist independently reached "one path-taking `fs.read`, no handle API in v1."

- **Systems:** *"All four ops return `Result[T, Errno]`. `E = Errno`, not a new `IOError`. Delete `IOError` from the spec."* Verified two ticket facts wrong and load-bearing: *"`fs.read` does not return `""` on failure. It aborts the process."* (`blink_read_file` → `exit(1)`), and the FS vtable already reserves the error slot (`blink_fs_default_write` … `return 0;` is *"a hardcoded lie in the ABI slot that was reserved for the truth."*) Measured all three `Result[T, Errno]` carriers at **16 bytes** (register-pair return); argued a rich `IOError` widens to 32 bytes and *"past the two-register threshold, so SysV returns it through a hidden `sret` pointer."* Q3: spec names win (`fs.list`, `fs.delete`) — *"`list_dir` leaks `opendir`/`readdir`… `remove` is literally the C stdlib function we call."*

- **Web/Scripting:** Proposal A, *"Errno everywhere, but make it speak English"* — `Result[T, Errno]` with a **blocking** `impl Display for Errno` (*"`{e}` must print `No such file or directory (ENOENT)`, not `Errno(2)`"*). Named the decisive DX argument: *"One error type for all of I/O means `?` composes across `fs`, `libc`, `io`, and `net` for free."* Stated Proposal B (`IoError` struct) explicitly *"so the panel can reject it,"* conceding it is *"Better in exactly one way: the message names the file."* Q3: implementation names (`fs.list_dir`, `fs.remove`) on familiarity + zero churn.

- **PLT:** `Result[T, Errno]`, with a typing rule (T-FsRead) making the error type *"a fixed constant of the operation's interface, not an inferred position"* — required because the op dispatches through a handler vtable, so *"an inferred or polymorphic `E` would make the handler interface open."* Q2: one `fs.read`, handle examples *"non-normative and must be removed."* Q3: follow the spec (`fs.list`, `fs.delete`).

- **DevOps:** the lone Option-I opener — *"`Result[T, IoError]`, where `IoError` is a 3-field prelude struct (`op`, `path`, `code: Errno`) with a `Display` impl. NOT bare `Errno`."* Three blocking tooling findings: (1) E0514 makes `fs.read(p)?` illegal in a `test` block without `Display`; (2) *"there is no unused-`Result` lint, so `fs.write` stays silent even after the change"* → demands `W0603 UnusedResult` same-change; (3) the error type must be prelude-reachable, so *"'Errno is the cheap option' is false. The cost is identical; only the payload differs. Decide on the payload."* Q3: `fs.list_dir` + `fs.delete`.

- **AI/ML:** `Result[T, Errno]` + four riders (named errno constants, delete the handle API, `?` on every example, a did-you-mean diagnostic). Scored AIML-1 highest (5/5/5/4) and flagged the status quo as the worst case for a code model — *"Correctness here costs exactly one token"* (`?`) against a wrong defensive idiom that costs more. Ruled out `Option[Str]`: *"Option = absence is normal and has exactly one cause; Result = several distinct failure causes."*

- **Minimalism:** *"`Result[T, Errno]` for all four. Reuse `Errno`. Do not invent `IoError`/`IOError` — delete that name from the spec."* P1: *"four functions, one error type, zero new types."* Q2: delete the handle API — *"They have never compiled, and the handle form requires function overloading, which Blink does not have."*

#### Phase B — Debate highlights

Phase B is where five panelists moved from Option E to Option I. Two verified facts drove the flip, plus DevOps's measured neutralisation of the systems cost objection.

**The premise-breaking fact (DevOps, PLT):** Blink's stdlib *already* runs per-domain rich error types. PLT: *"`net_error.bl` — `NetError` with 8 variants… `db_error.bl` — `DbError`… plus `JsonError`, `ConversionError`. `Errno` is not the general I/O error type. It is the raw syscall layer type… Under the existing convention, an `fs` namespace returning `Errno` would be the inconsistent choice."* DevOps: *"`ConversionError` is literally the shape I proposed — a 3-field struct of Strs — accepted by this project for integer conversion."*

**The `path` argument (DevOps), the field that cannot be added later:** *"No method on `Errno(2)` can ever recover which file… `kind` is additive, `path` is not, and `path` is the field users actually need. Rust proved this empirically — `io::Error` carries the kind and omits the path, and the ecosystem wrote the `fs_err` crate whose entire purpose is re-attaching the path."*

**The size objection, measured and dissolved (DevOps, confirmed by Systems):** DevOps measured `Result[Str, PathError]` inline = 32, boxed = 16, *"byte-identical to `Errno` on the success path,"* and proposed change **C2**: *"a struct-typed error arm of `Result` is stored by pointer."* Systems confirmed the numbers and conceded: *"my Phase B claim that 'the caller reconstructs the path, it passed it in' is false the moment `?` fires… My argument only held for code that never uses `?`, which defeats the operator."*

**PLT switches, E → I:** *"devops's challenge is correct, and two further facts I verified during this round falsify the load-bearing premise of my Phase A argument."* Attached amendments: **A1** (`Errno` stays for `libc.*`/`io.*`, do not migrate), **A2** (`op: Str` must become an enum or be dropped — *"a stringly-typed operation name has no exhaustiveness, no contract, and no refactor safety"*), **A3** (named-field construction only), **A4** (name it `FsError`, not `IoError` — *"`NetError.IoError` already exists as a variant"*, an implementation hazard under bare-variant resolution).

**The naming collision (DevOps, PLT, AI/ML independently):** `IoError` collides with the existing `NetError.IoError` variant (`lib/std/net_error.bl:9`). DevOps first proposed `PathError` (Go's name) then conceded `FsError`: *"In-tree convention beats fidelity to another language's name… `net`→`NetError`, `db`→`DbError`, `json`→`JsonError`, so `fs`→`FsError`."*

**`map_err` surfaced as the real gap (AI/ML, PLT):** AI/ML: *".map_err() is SPEC'D, in three places, and implemented nowhere."* PLT: *"Blink today has no error-adaptation mechanism at all. A user cannot call `fs.read` and `db.query` in one function, full stop. That is the real defect this deliberation has surfaced, and it is bigger than Q1."*

**Bugs found during the investigation (DevOps):** emitting the actual C for a struct with an `Errno` field does not compile — three defects filed as `cz10bb` (silent miscompile: *"the errno is silently discarded and an invalid tag is stored. Compiles clean, runs, wrong."*) and `fsr5ew` (whole-value `Err(e)` binder emits invalid C). *"Bug A is reachable by any user who puts an `Errno` in a struct today."*

#### Phase C — Final vote

**Q1 — return / error type: `Result[T, FsError]` (Option I), 6-0** (after Phase A's 5-1 for Option E; every E-opener flipped on the verified facts above). Error type `FsError { op: FsOp, path: Str, code: Errno }`, `FsOp { Read Write ListDir Delete }`.

- **Systems:** **I** (op = enum `FsOp`). *"I am switching from E to I. Three arguments I built my position on have each been answered… my 40-byte objection is neutralised by C2 boxing… my claim that 'the caller reconstructs the path' is false the moment `?` fires."* Concern: C2 boxing *"is not a PathError-local rule… It should land as its own staged change, verified green, BEFORE FsError is introduced."*
- **Web/Scripting:** **I** (op: **drop**; second choice `FsOp`; reject `op: Str`). *"ship I and find it heavy, users ignore the extra field and `{e}` still prints; ship E and find you need the path, every user rewrites signatures."*
- **PLT:** **I** (op = enum `FsOp`, A2 resolved). *"Rust made the E choice… and the ecosystem routed around it with the `fs_err` wrapper crate; Go made the I choice… and no such crate was ever needed. devops's layering is Go's, exactly."* keep-`Str` *"is my one unacceptable element."* Concern: C2 must *"box struct error arms while leaving the transparent-newtype path alone — ship it with a test that pins `Result[Bytes, Errno]` still emitting a bare `int64_t`."*
- **DevOps:** **I** (as `FsError`, op = enum `FsOp`). Accepted A1/A3/A4 and A2-enum, rejected only the drop: *"the set is closed and frozen: Q2 just fixed it at exactly four operations, so YAGNI does not apply."* Held `code: Errno`: *"changing the field type later is the same breaking change I have spent this deliberation arguing against."*
- **AI/ML:** **I** (op = `enum FsOp`; drop acceptable, `Str` not). *"a model reasoning by analogy from the stdlib will expect `PathError` and be wrong under E — Errno-for-fs is the exception a model must memorise."* Concern: record *why* fs earns a rich error *"so the next namespace has a test to fail rather than a precedent to cite."*
- **Minimalism:** **I** (op: **drop**; *"two fields: `path: Str` + `code: Errno`"*). *"A minimalist counts concepts, not type declarations; on that metric E is the inconsistent choice and plt is right… the real fork is 'small now and permanently pathless' vs 'one type, complete,' and my own criterion picks the latter."*

*On the `op` field:* 4 of 6 (sys, plt, devops, aiml) landed on the enum; web and min preferred dropping it; nobody accepted `op: Str`. The user (BDFL) fixed the outcome at **`enum FsOp { Read Write ListDir Delete }`**, and set `code: Errno` retained.

**Q2 — one path-taking `fs.read`, no handle API in v1: 6-0.** No `fs.open` / `fs.create` / `fs.read(handle)`; streaming is post-v1 as *methods on a file handle*, never an `fs.read` overload (Blink has no function overloading). The Closeable / E0601 teaching examples (§04:1122-1135) are re-spelled against a real `Closeable`, not deleted (plt carve-out, confirmed 6/6). The sub-variation (hard-delete vs. a `blink-planned` fenced appendix) was left to implementation, gated on a CI doc-check that every ```blink fence under `sections/` compiles.

**Q3a — the lister: `fs.list_dir`, 6-0.** *"listing is `FS.Read`, there is no `FS.List` sub-effect,"* so `list_dir` creates no off-rule effect entry; every mainstream ecosystem names it after the directory (`os.ReadDir`, `fs::read_dir`, `os.listdir`).

**Q3b — the remover: `fs.delete` + `FS.Delete`, 5-1** (web dissent: `fs.remove` + `FS.Remove`). The matched-pair framing was decisive — the method name and the sub-effect must match, and `fs.delete`/`FS.Delete` is derivable, spec-precedented, and zero manifest churn (`src/codegen_methods.bl:3192` already emits `"FS.Delete"`). plt: *"a one-entry exception table lives in the effect checker, which is the security-relevant path."* Web dissented on ecosystem familiarity (`os.remove` in Python/Go/Rust/C) but committed to flip on a tie; aiml, min, and plt all explicitly accepted `fs.remove` + `FS.Remove` as a valid pair and rejected only the *unmatched* pair.

**Riders (final):**
- **Ra** prelude-promote `FsError` + `FsOp` — 6-0 same-change (an intrinsic cannot return an un-nameable type).
- **Rb** `impl Display for FsError` (Go-style `op path: message`) + `not_found()` — 6-0 same-change, blocker (E0514 makes `fs.read(p)?` in a `test` block a compile error without it).
- **Rc** user-facing named errno constants — deferred. **But** (web's shutdown correction, endorsed) the internal errno→message+NAME table is a *same-change dependency of Rb*, since `Display` renders `No such file or directory (ENOENT)` and `not_found()` compares against ENOENT internally. Only the exported named-constant surface defers.
- **Rd** `W0603 UnusedResult` lint, `let _ =` opt-out — 6-0 same-change. Without it a bare `fs.write(p, s)` statement silently drops the error — *"the ticket's headline bug survives its own fix."* Systems: *"this ticket is a strict regression on write and delete"* without it.
- **Re** implement `map_err` — v1-blocking, tracked as its own ticket (spec'd in three sections, voted 5-0, implemented nowhere). Sequence behind `fsr5ew`.
- **Rf** fix `cz10bb` + `fsr5ew` (the transparent-newtype struct-field seams) — same-change; `cz10bb` is a silent miscompile gating `code: Errno`.

#### Phase D — focused re-vote

Q1 re-ran after Phase B's movement and converged 6-0 for Option I (from the Phase A 5-1 for Option E). Q3b remained 5-1 with web's dissent recorded; per the soft-consensus rule the majority's Concern fields endorsed web's `os.remove` familiarity point (all agreed `fs.remove`+`FS.Remove` is a legitimate matched pair), so it shipped as majority-with-dissent rather than re-debating.

### Final Spec

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

fs.read(path: Str)                -> Result[Str, FsError]        ! FS.Read
fs.write(path: Str, content: Str) -> Result[Void, FsError]       ! FS.Write
fs.list_dir(path: Str)            -> Result[List[Str], FsError]  ! FS.Read
fs.delete(path: Str)              -> Result[Void, FsError]       ! FS.Delete
```

Locked design points:

- **Error type is a per-domain rich `FsError`**, matching `net`→`NetError` / `db`→`DbError`, *not* a bare `Errno`. The stdlib already runs per-domain errors, so bare-Errno would be the special case; and a path is permanently unrecoverable once `?` propagates past the call frame.
- **`op` is `enum FsOp { Read Write ListDir Delete }`** — closed, frozen at four by Q2, matchable and exhaustiveness-checked. Never `op: Str`.
- **`code` is the transparent zero-cost `Errno`** newtype from `std.errno`. `libc.*` / `io.*` keep bare `Errno` (A1); this decision does *not* add a general `IoError`.
- **`FsError` implements `Display`** (Go-style `op path: message`, e.g. `read /etc/app.toml: No such file or directory`) and ships a `not_found()` predicate. `FsError` + `FsOp` are prelude-promoted.
- **Names follow the spec where the spec is clearer, the impl where it is:** `fs.list_dir` (Q3a — listing is `FS.Read`, no `FS.List`), `fs.delete` + `FS.Delete` (Q3b — matched verb/effect pair).
- **No file-handle API in v1:** exactly the four path ops. Streaming/incremental access is post-v1 as *methods on a file handle* (`file.read_line()`), never an `fs.read` overload.
- **`?` is exact** (no implicit `.into()`); cross-error adaptation uses `.map_err` (Re, v1-blocking).
- **Staged implementation** (user directive): fix `cz10bb` + `fsr5ew` → the C2 "box struct error arms by pointer" codegen rule (guarded by a `Result[Bytes, Errno]` transparent-emit pin-test) → `map_err` → the `FsError` fs-intrinsics + `W0603`.
