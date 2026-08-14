[< All Decisions](../DECISIONS.md)

# `Ptr[T]` Operations Table — Design Rationale

Resolves the spec gap: *"`Ptr[T]` operations table in §7/§9.1.1 contradicts the implementation on
deref/addr/null_ptr and omits offset/read/write."* Supersedes the deref/addr/null_ptr/nullability
points of the earlier FFI pointer decisions ([FFI Type Mapping](ffi-type-mapping.md), Q1 4-1 and Q2 5-0)
— those rows were written on paper before `lib/std/libc.bl` and `db_sqlite.bl` existed and drifted from
both the implementation and §9.1.3.

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in
independent-proposal → debate → vote rounds. Two panelists (PLT, AI/ML) falsified their own Phase A
positions with experiments run against `build/blink` during Phase B.

The live contradictions requiring votes were **deref**, **addr**, and **null_ptr**; the "omissions"
(`offset`, `alloc_n`, field `read`/`write`) were already specced in §9.1.3 and only needed folding into
one canonical table. `read_n` was confirmed a phantom — it is a **net** socket method
(`src/typecheck.bl:6706`), not a `Ptr` op — and unanimously not added.

#### Phase A — Independent proposals

- **Systems (S1):** "at the FFI boundary, the type system's job is to describe the ABI, not to relitigate
  the invariant the `@trusted(audit:)` string already asserts." `deref -> T` bare: "`Option[T]` is not
  uniformly expressible. `Ptr[Void].deref()` would have to produce `Option[Void]`. There is no such
  value." On addr, proposed `-> Ptr[Ptr[T]]` lowered to `&p` **lvalue-only** (S1) but also offered S4:
  "Since `.addr()` has no callers, the cheapest correct move is to not have it… `scope.alloc[Ptr[Void]]()`
  yields `Ptr[Ptr[Void]]` — the out-parameter type, directly." `null_ptr -> Ptr[T]` bare: "An `Option`
  that cannot be `Some` is not a safety feature; it is a compile-time constant wearing a tag byte."
- **Web/Scripting (W-1):** "spec §7 vs spec §9.1, and §9.1 has actual callers." `deref -> T`:
  "Option[T] here is safety theater with a syntax tax. It catches exactly one of the four ways an FFI
  deref kills you — null." Proposed `addr -> Ptr[Ptr[T]]` (impl bends to spec). `null_ptr -> Ptr[T]`:
  "A constructor for a sentinel must return the sentinel." Kept `to_str -> Option[Str]` as "the single,
  documented exception," and surveyed Python ctypes/Bun/Kotlin/Swift/Zig: "Not one of them wraps the load."
- **PLT (P1):** Opened by **revising its own prior 5-0 vote** for `deref -> Option[T]`: "That argument was
  conditional on the premise that a `Ptr[T]` may be null, and Q1… made that premise false… `Option[T]`
  models only the recoverable half of deref's failure space." Gave full typing rules: `deref : Ptr[τ] -> τ`,
  no rule on `Ptr[Void]` (proposed rejection), `addr : Ptr[τ] -> Int` ("an observation, not a
  construction. There is no `Ptr.from_addr(Int)`… parametricity intact"). Proposed **deleting** `null_ptr`
  entirely: "A null pointer is an ABI phenomenon, not a Blink value," NULL via `None ↦ NULL` at the call
  boundary. General law stated: "partiality observable as a value goes in `Option`; partiality that cannot
  be observed as a value goes to the context condition."
- **DevOps (D1):** "`.addr()` is not one operation with two return types. It is two different operations
  sharing one name." Proposed splitting: `addr -> Int` keeps the name (impl/tests/`llms-full.md` all mean
  numeric), plus a **new** `out_ptr -> Ptr[Ptr[T]]` for out-params. `deref -> T`, `null_ptr -> Ptr[T]`.
  Stated the principle "`Option` must be earned," and flagged a third contradicting table in the generated
  `llms-full.md`. Showed the two-compile-cycle diagnostic cost of `Option[T]` deref.
- **AI/ML (Proposal A):** The one-sentence rule: "Inside `@ffi`/`@trusted`, a pointer op returns exactly
  what C returns, bare. Only an op that builds a Blink value — `to_str` — returns `Option`." `deref -> T`,
  `null_ptr -> Ptr[T]`, and proposed **renaming** addr to `as_int -> Int` ("both current names lie").
  "across the entire training corpus, zero mainstream languages return an option from an op named deref…
  it is unattested." Also **revised its own prior 5-0 vote**: "I had the right fact and drew the wrong
  conclusion from it." Flagged the §7 sqlite example's `scope.alloc[Void]()` — "`sizeof(void)` is 1 under
  GCC… a heap overflow in the normative spec."
- **Minimalism (M1):** "Bless the bare values, delete the four dead ops." `deref -> T`, `addr -> Int`,
  `null_ptr -> Ptr[T]`, all bare — "exactly what codegen already emits, so the typecheck hole (0x2fv5)
  closes with zero codegen change and zero `lib/std` change." Proposed deleting `is_null` ("C has `NULL`
  and `p == NULL`… the producer is irreplaceable") and `alloc_ptr` ("its sole distinguishing property is
  that it leaks"). The discriminating test for `Option`: "`Option` earns its place only when the failure is
  not observable by other means." Offered M2 (rename `deref -> read` for one read verb) but "I do not
  champion it… a rename… buys zero reduction in op count."

#### Phase A.5 — Mechanical dedupe

- **Q1 `deref`:** unanimous `-> bare T` in Phase A. Locked; not re-debated.
- **Q2 `addr`:** substance unanimous (numeric `Int`, delete the `&ptr`/`Ptr[Ptr[T]]` meaning). Split on
  form: **A** keep the name `addr` (min, and the impl); **B** `-> Ptr[Ptr[T]]` lvalue-only (sys-S1, web-W-1);
  **C** keep both + new `out_ptr` (devops-D1); **D** rename `as_int` (aiml). Flagged for Phase B.
- **Q3 `null_ptr`:** **A** `-> Ptr[T]` bare (sys, web, devops, aiml, min) vs **B** delete + `None ↦ NULL`
  ABI lowering (plt). Flagged for Phase B.
- **Q4 reconciliation:** unanimous — one canonical table, §9.1.1 authoritative; §7-era table and the
  generated `llms-full.md` reference it. `read_n` not added.
- Two new sub-questions surfaced by the proposals, put to Phase B: **R-void** (what happens on
  `Ptr[Void].deref()`, which has no value representation) and **R-verb** (whether to add a `read` alias for
  `deref` given field projection uses `.read()`).

#### Phase B — Debate highlights

Two panelists reversed on Q2 after running experiments:

- **AI/ML** — *conceded its own rename.* "My Phase A case for the rename rested on one claim: 'under the
  name `addr` a model must guess whether it means `&p` or `(intptr_t)p` — both readings compile.' I tested
  that claim. It is false… The moment `addr` is typed `Int`… the wrong reading becomes a hard compile error
  that names both types at the call site. The rename buys nothing typing does not already buy." Moved D→**A**.
- **Web** — folded B→**A**: "verified call sites itself; industry-normal `addr→int`." Made its vote
  conditional on Q4 recording that "`deref()` on `Ptr[Ptr[T]]` yields `Ptr[T]` and `tc_tid_byvalue_ct`
  stops declining `TyKind.Ptr`" (typecheck.bl:14144).
- **Systems** — withdrew B, moved to **A**, self-correcting a Phase A error: "admitting its Phase A 'zero
  callers' claim rested on a bad `rg -r` command."
- **DevOps** — withdrew C, voted **D** (`as_int`) with A acceptable, on diagnostic grounds: a removed
  `.addr()` "is the one diagnostic I can attach arbitrary help to… routes each [historical meaning]."
  Attached a **rider**: "`scope.alloc[Ptr[T]]()` types as `?`… Q2-A and Q2-D both route C out-parameters
  through a construct that does not exist yet" (Fact 1); and Fact 2, "`Ptr[Void]` … currently supports no
  methods at all."
- **PLT** — moved Q2 A→**D** (rename, A as fallback) and, decisively, **withdrew Q3-B → voted Q3-A** on a
  new verified fact: "**F6** — the panel's own locked `to_str -> Option[Str]` entails Q3-A… `to_str`'s
  `None` branch is earned only if a null value can inhabit type `Ptr[U8]`… Q3-B and '`to_str` stays
  `Option[Str]`' cannot both hold." Plus "zero occurrences of `Ptr[T]?` anywhere in the tree." Attached a
  **non-negotiable amendment**: §7's "non-null by default… guaranteed to point to valid memory" is false
  next to `null_ptr()` and must become "non-null by convention, not by proof."

On **R-void**, all six converged on rejecting `deref`/`write` on `Ptr[Void]` via a new diagnostic. AI/ML's
Experiment 3: "`c_malloc(8).deref()` — `blink check` accepts it, and `x` binds as `Int`… That is bug
0x2fv5's exact shape, surviving on `Void`." DevOps and Minimalism required the rule be worded about the
**operations**, not the type: "`.is_null()`, the numeric-address op, and pass-through-to-C MUST work on
`Ptr[Void]`." AI/ML required the help text name the working path (`-> Ptr[T]` / `@ffi.struct`).

On **R-verb**, unanimous for **(i) deref only, no alias.** Minimalism: "(ii)… is the only choice on this
ballot that makes the table bigger." PLT: "`read` is already taken [by `p.f.read()`]… Voting (ii) would
resolve one name collision and create another in the same edit." AI/ML: "the receiver picks for it… Rust
carries the same split (`*p` vs `ptr::read`) without confusion."

#### Phase C — Final vote

The Phase B ballots arrived in final `vote / reasoning / concern` form with independent, experiment-backed
reasoning (two panelists reversing their own priors); the moderator recorded them as the vote and the user
signed off on the tally.

- **Q1 — `.deref()` returns bare `T`** (6-0, locked in Phase A)
  - Uniform across all six. **Systems:** "No systems language pays a tagged union per load." **PLT:**
    "`Option[T]` … falsely presents an exhaustive match over a failure space it cannot cover." The residual
    null-partiality is accounted for by the E0811 context gate, not the type.

- **Q2 — `.addr()` returns `Int`; the `&ptr`/`Ptr[Ptr[T]]` meaning is deleted** (6-0 on substance; name
  `addr` kept 4-2, soft consensus)
  - **Systems:** A — addr→Int, delete the `&ptr` op. **Web:** A — "industry-normal `addr→int`." **AI/ML:**
    A — "the rename buys nothing typing does not already buy." **Minimalism:** A — "Once `&ptr` is gone from
    the spec, `addr()` has exactly one referent."
  - *(minority, both accept `addr` as fallback)* **PLT:** D (`as_int`) — "Resolving the collision by decree
    leaves the misleading name in place." **DevOps:** D — the removed-method diagnostic can route both
    historical meanings. → soft consensus for `addr`; `as_int` recorded as the noted alternative.
  - **Concern (carried):** the out-param idiom `scope.alloc[Ptr[T]]()` must be made to yield a usable
    `Ptr[Ptr[T]]` (today `?`), or the address-of capability is deleted, not relocated → impl ticket.

- **Q3 — `null_ptr[T]() -> Ptr[T]` bare; `is_null()` retained** (6-0)
  - All six A. **PLT** *(moved from B)*: "given that `Ptr[T]` is de facto nullable (F6) and nothing at the
    boundary makes it otherwise, `null_ptr[T]() -> Ptr[T]` is not a new unsoundness. It is the honest
    spelling of an invariant the language does not enforce." **AI/ML:** "Q3-B proposes Zig's ceremony without
    Zig's invariant… A design that teaches a false non-null invariant is a net safety regression."
  - **Amendment adopted (PLT, required):** §7 nullability prose changed to "non-null **by convention, not by
    proof**"; `Ptr[T]?` and the FFI-return null-check recorded as **reserved / not yet implemented**.
  - **Definition adopted (Minimalism):** `is_null()` is specced as shorthand for `p == null_ptr()`.

- **Q4 — one canonical operations table in §9.1.1** (6-0)
  - §9.1.1 owns the table; §9.1.3 extends it with field projection and array regions and references it.
    Rider recorded: nested-`Ptr` deref (`Ptr[Ptr[T]].deref() -> Ptr[T]`; `tc_tid_byvalue_ct` must stop
    declining `TyKind.Ptr`) is required for the out-param idiom.

- **R-void — reject `.deref()` / `.write()` on `Ptr[Void]` (new diagnostic)** (6-0 adopt)
  - `Void` has no value representation; `*(void*)p` is a C constraint violation. Every other op
    (`addr`, `offset`, `==`, `is_null`, `null_ptr`, pass-through) stays legal so `Ptr[Void]` remains a
    usable opaque handle. Help text names `-> Ptr[T]` / `@ffi.struct`. *The panel named this `E0814`; that
    code was already taken by §9.1.3.1's Bytes-grow check, so it ships as **E0825**.*

- **R-verb — `deref` only; no `read` alias** (6-0)
  - The `deref` (cell) vs `.field.read()` (field) asymmetry is documented as a known wart rather than named
    around. A future uniformity change, if wanted, is a rename under the 3-step bootstrap protocol, filed
    separately — never a shipped alias.

### Final Spec

```blink
// §9.1.1 canonical Ptr[T] operations (excerpt)
fn alloc_ptr[T]() -> Ptr[T]        // calloc(1, sizeof(T)); GC-registered fallback
fn null_ptr[T]() -> Ptr[T]         // NULL — the only way to spell NULL in Blink
fn deref(self: Ptr[T]) -> T        // *ptr; no null check; rejected on Ptr[Void] (E0825)
fn write(self: Ptr[T], value: T)   // *ptr = value; rejected on Ptr[Void] (E0825)
fn is_null(self: Ptr[T]) -> Bool   // ptr == NULL; shorthand for p == null_ptr()
fn addr(self: Ptr[T]) -> Int       // (intptr_t)ptr; NOT &ptr — an observation, not an out-param
fn offset(self: Ptr[T], i: Int) -> Ptr[T]   // ptr + i; alloc_n regions only (E0813 on singleton)
fn as_cstr(self: Str) -> Ptr[U8]             // strdup(s)
fn to_str(self: Ptr[U8]) -> Option[Str]      // walk to NUL + copy; None if null — Option earned
```

Locked design points:

- **`deref -> T`, bare.** "Option must be earned": an op returns `Option[T]` only when a failure is
  observable as a value the op itself produces (`to_str` observes the NUL terminator). A load's
  null-partiality is not, so `deref` returns bare `T`; the residual unsafety is accounted for by the
  E0811 `@ffi`/`@trusted` context gate.
- **`addr -> Int`**, an observation with no inverse (`Ptr.from_int` does not exist). The `&ptr` /
  `Ptr[Ptr[T]]` operation is **deleted**. C out-parameters use `scope.alloc[Ptr[T]]()` + pass-the-cell +
  `.deref()`.
- **`null_ptr[T]() -> Ptr[T]`**, bare; `is_null()` = `p == null_ptr()`.
- **`Ptr[T]` is non-null by convention, not by proof.** `Ptr[T]?` (enforced nullability + FFI-boundary
  null-check) is reserved and not yet implemented; when it lands it must revisit `to_str`.
- **`Ptr[Void]`**: `deref`/`write` rejected (**E0825**); all other ops legal.
- **One canonical table in §9.1.1.** `read_n` is a net method, not a `Ptr` op — not added. No `read` alias
  for `deref`.
