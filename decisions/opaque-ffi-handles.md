[< All Decisions](../DECISIONS.md)

# Opaque FFI Handle Types (`@ffi.opaque`) — Design Rationale

Resolves br `wgk5ht`: *"Opaque FFI pointers have no honest type in Blink."* An opaque C
pointer — a handle whose C type is incomplete on the Blink side (`sqlite3*`, `sqlite3_stmt*`,
`FILE*`, an OpenSSL `SSL_CTX*`) — had no Blink type that both (a) names it honestly and (b) can
be held and passed through ordinary non-FFI Blink code. `lib/std/db_sqlite.bl` modelled ~43 such
handles as the async `Handle` carrier purely because it was E0811-exempt and free-flowing; the
ratified `TypeArgArity` rule (E0303) made bare `Handle` an error, exposing the gap. See
§9.1.4 *Opaque FFI handle types* for the normative spec.

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in
independent-proposal → mechanical-dedupe → open-debate → silent-vote rounds. All six judged the
gap **in scope** for the language (Minimalism: "in scope, narrowly").

#### Phase A — Independent proposals (excerpted with attribution)

Five of six proposed a new `@ffi.opaque` declaration form; the split within that camp was
**bare nominal type** vs **tag + generic**. Minimalism proposed no new syntax.

- **Systems (Option A — bare nominal):** "`@ffi.opaque type Sqlite3` lowers directly to
  `sqlite3*` — one machine word." Made a hard requirement: "`Option[T]` where T is `@ffi.opaque`
  MUST get null-pointer-optimized layout … non-negotiable." Rejected a generic `OpaqueHandle[Tag]`:
  "monomorphizing a builtin per tag is pure overhead for something that's just a pointer with a name."
- **Web/Scripting (Option A):** "reads exactly like `@ffi.struct` … kills the
  `null_ptr()`/`.is_null()` pattern in favor of `Option[T]`." Rejected widening `Handle`:
  "One name, one meaning."
- **PLT (Option B — tag + generic):** "`Opaque :: Type -> Type`, builtin, arity-1 — same shape as
  `Handle[E]`. Tag is uninhabited (like `Void`)." Rejected a transparent newtype over `Ptr[Void]`
  as unsound: "teaching E0811 to look through annotated newtypes means the containment rule can no
  longer be stated purely syntactically." Nullability non-null-by-convention; `Option` only where a
  C API makes NULL an observed/checked outcome.
- **DevOps/Tooling (Option A):** "`@ffi.opaque(header, c_type)` … zero NEW error codes — `.deref()`
  is just 'no method deref on `SqliteConn`'. New audit category `opaque-ffi-handle`. Nullability =
  real `Option[SqliteConn]` via `from_ptr` null-check at the boundary." Flagged sequencing:
  sbx4kk migrating to `Handle[Void]` now means a second migration hop if a new type wins.
- **AI/ML (Option B):** "`Opaque[T]`, second E0811-exempt capability token … no `.deref()` in the
  method set at all (absent, not rejected)." Win32 `HANDLE` prior: "an LLM will WANT to read
  `Handle[Void]` as a generic opaque pointer — giving opaque pointers their own name sidesteps the
  collision." Non-null-by-convention + `Opaque[T]?` reserved.
- **Minimalism (Option C, else reject):** "One real defect: nominal collision. Narrow E0811 for
  `Ptr[Void]` (subtraction, not addition); wrap in plain structs for distinctness." Against a new
  builtin: "any new parametric type interacts with E0303 arity, `Option`/`Result` carrier encoding,
  tid-mono CSV lowering, `@derive` — every one a seam, its own bugs. A plain struct rides infra that
  already works."

#### Phase A.5 — Mechanical dedupe

- **A** — `@ffi.opaque` **bare nominal** type (arity-0), lowers to `cname*`, E0811-exempt by
  construction, no deref method. *(Sys, Web, DevOps)*
- **B** — `@ffi.opaque` **tag + generic** `Opaque[Foo]` (arity-1 builtin, uninhabited phantom tag,
  `Handle[E]`-shape). *(PLT, AI/ML)*
- **C** — **Narrow E0811 for `Ptr[Void]`** only + wrapper structs; no new grammar. *(Min)*
- **D** — **Do nothing** (`Handle[Void]`). Baseline; recommended by no one.

Sub-questions flagged for debate: Q-null (`Option[Foo]` vs non-null-convention), Q-construct
(boundary crossing), Q-cost (Min's combinatorial objection to an arity-1 builtin), Q-soundness
(PLT's warning that narrowing E0811 makes containment non-syntactic). ≥3 distinct options + flagged
variations → Phase B triggered.

#### Phase B — Debate & Phase C — Final vote

The debate produced three pivots, each stated with reasoning. **PLT (B→A)**, **AI/ML (B→A)**, and
**Minimalism (C→A)** all moved to A, yielding a unanimous panel. Verbatim final reports:

**Systems — vote A / Option(i) with NPO / cost A / reject C (no pivot):**

> The runtime-cost axis does not separate A, B, and C: a bare nominal, an arity-1 builtin instance,
> and a single-pointer-field wrapper struct ALL lower to one machine word. So my Phase A objection
> to B was mis-aimed at "runtime overhead" — the true cost of B is compile-time seam surface, and
> there Min is right: a new parametric builtin must be taught E0303 arity, Option/Result carrier
> encoding, tid-mono CSV lowering, and @derive, four seams bought for zero runtime gain. The axis
> that DOES separate the options is null-pointer optimization, and that decides the vote. A (and B)
> let the compiler see Foo as a known-pointer type, so Option[Foo] is NPO-able to one word with NULL
> as None — my hard requirement holds. Min's wrapper struct (C) hides the pointer behind a struct
> field, so Option[SqliteConn] falls back to the general tagged-struct carrier: two words plus a
> branch. That is a real, measurable cost the wrapper imposes at every call site, and it is why C
> fails the zero-cost test even though its bare handle is one word. I also side with PLT on
> soundness: C's field is a Ptr[Void] that leaks via .addr()/== into non-FFI code, making E0811
> containment non-syntactic — A avoids this by construction (no deref method exists, E0811-exempt as
> a type, nothing to leak).
>
> Q-mechanism: A. … Q-null: (i) — Option[Foo], no is_null, NPO layout REQUIRED (non-negotiable). …
> Q-construct: @ffi.fn returns Option[Foo] directly, NULL→None at the boundary … equally content
> with DevOps's sealed from_ptr gated to @ffi/@trusted since it inlines to byte-identical code and
> buys an audit seam. … Q-cost: B does NOT pay for its seams. … Q-soundness: C is NOT sound —
> containment erosion.

**Web/Scripting — vote A / Option(i) / cost A / reject C (no pivot):**

> The A-vs-B split is a pure DX test, and B loses it. A Python/JS dev reads `SqliteConn` in zero
> seconds — it's just a type name, exactly like a Python class or a TS interface. `Opaque[Sqlite3]`
> (PLT, AI/ML) stops that same dev cold: "what is Opaque, why is it generic, what's the tag, and how
> do I make one?" That's three Stack Overflow questions per handle for zero user-visible benefit …
> Min's nominal-collision defect is real, but C's cure (hand-written wrapper structs over exposed
> Ptr[Void]) hands users MORE raw-pointer boilerplate, which is the opposite of what a scripting dev
> wants.
>
> Q-mechanism: A … Q-null: (i) Option[Foo], no is_null. Familiar Optional/None truthiness pattern;
> kills null_ptr()/.is_null() which is exactly the C-ism scripting devs migrate away from. …
> Q-construct: returned directly from @ffi.fn, boundary auto-wraps NULL→None. … Q-cost: B's arity-1
> generic does NOT pay for its seams … Q-soundness: narrowing E0811 for Ptr[Void] (C) is containment
> erosion.

**DevOps/Tooling — vote A / Option(i) / cost A / reject C (no pivot); sequencing recommendation:**

> I hold Option A (no pivot). Sys and Web reach A from the type/NPO side; I reach it from the
> diagnostics side … a bare nominal `SqliteConn` slots into every existing tooling path (symbol
> table, hover, autocomplete, fmt) with ZERO new machinery, and a bad `.deref()` reuses the existing
> "no method deref on SqliteConn" diagnostic that already reads well. PLT/AI-ML's `Opaque[Tag]` (B)
> … every error, hover, and completion now carries a phantom tag ("no method deref on
> Opaque[SqliteTag]") — that's worse copy for the exact humans hitting the error … Min's
> wrapper-struct (C) produces the worst forget-to-wrap failure mode: the user sees a raw-Ptr
> E0811/E0825 pointing at boundary machinery instead of "name this type," which is a diagnostic
> regression.
>
> Q-mechanism — A. … Q-null — (i) Option[SqliteConn] via sealed from_ptr, no is_null. An
> `.is_null()` convention is UN-LINTABLE: the toolchain can't warn on a skipped check, so the failure
> is a runtime segfault instead of a diagnostic. … Q-construct — sealed from_ptr/to_ptr gated by the
> new `opaque-ffi-handle` audit category … "returned directly" hides the conversion, leaving nothing
> to audit … I'd defer to PLT if they want the tighter E0826 lock. Q-cost — A (arity-0). …
> Q-soundness — narrowing E0811 for Ptr[Void] (C) is containment erosion, siding with PLT. …
> Q-sequencing (recommendation, not a vote) — Block sbx4kk on this decision. … If E0303 is actively
> breaking the build TODAY and can't wait, let the interim land but file a re-migration ticket that
> DEPENDS on the wgk5ht decision ticket so it can't be lost.

**PLT — PIVOT B→A / Option(i)+NPO / construct @ffi-boundary-only / cost A / reject C:**

> I PIVOT from B to A. My Phase-A soundness objection was aimed at a transparent newtype over
> Ptr[Void] — where E0811 must look *through* an annotation to see the guarded Ptr[T], which is
> non-syntactic and unsound. That objection does NOT touch A. A bare `@ffi.opaque type Foo` is a
> fresh abstract nominal type whose representation (a C pointer) is sealed at the boundary; E0811
> never sees a Ptr there, so the containment rule stays purely syntactic ("not Ptr[T] ⇒ not
> guarded"). This is textbook opaque-type import — OCaml .mli abstract types, Haskell empty-data-decl
> FFI. Crucially, B's `Opaque :: Type -> Type` is a type constructor with NO functorial content: the
> tag is uninhabited and used exactly once, so there is no meaningful `map`, no parametricity, no
> operation it constrains. That is not a phantom-type-as-constraint … it is a nominal type with extra
> syntax. The Handle[E] analogy is superficial (same arity/carrier shape), not deep (E is a live
> effect; the opaque tag is inert). A theorist should not introduce a type constructor it cannot give
> laws to. A is the cleaner, sound, compositional typing rule; B pays real seams for zero added
> soundness.
>
> Q-mechanism: A (pivot). … Q-null: (i) with NPO … `Option[Foo]` is the ONLY null representation,
> earned only where a C API makes NULL an observed outcome … with NULL as the None niche (Rust
> `Option<NonNull>` optimization), zero overhead. No is_null/null_opaque primitives (they manufacture
> ad-hoc null-testing, violating "Option must be earned"). Q-construct: @ffi/@trusted-boundary-only +
> E0826 (my position holds), folding DevOps's from_ptr->Option as the *nullable*-boundary shape. …
> Q-cost: A. … B does not pay for its arity-1 seams … Q-soundness (C rebuttal): Concede Min's narrow
> point, still reject C. Min is right that a Ptr[Void]-CONCRETE carve is a single-type syntactic rule,
> not a look-through — so it does NOT break the statability of containment (I withdraw that specific
> charge). BUT C still loses … (a) collapsing all handles to the one type Ptr[Void] destroys nominal
> distinctness (FILE* and sqlite3* become interchangeable — classic void* unsoundness) … (b)
> `.addr()`/`==` on an escaped Ptr[Void] leak raw-pointer identity/addresses into pure code … A
> dominates C.

**Minimalism — PIVOT C→A / Option(i) / cost A / soundness A:**

> PIVOT: C → A. Stated explicitly. … (1) Path of least resistance: correct — C does NOT close the
> defect, it makes closing it optional. The defect is a collision at the DEFAULT (bare Ptr[Void]); a
> convention whose lazy path IS the broken state is not a fix. … A makes the honest distinct type the
> only path, so the footgun is removed, not documented. (2) Residual raw-pointer surface: correct and
> decisive — narrowing E0811 for Ptr[Void] leaks .addr() and raw ==/pointer identity into non-FFI
> code. A has no deref/addr/offset methods by construction, so it exposes ZERO raw-pointer surface. A
> is strictly TIGHTER than C on the exact surface-conservation grounds I claimed to defend. … (3)
> Cost objection scope: correct — my combinatorial objection … targets B's arity-1 GENERIC. A is
> arity-0: one annotation form, no new generic constructor, no uninhabited tag, no new seams. … A adds
> one annotation form and REPLACES the Handle[Void] abuse (net subtraction of existing misuse). That
> clears the burden of proof — this is a foundational primitive (an honest name for an opaque C
> pointer), not ergonomic sugar. A is the real minimum. I withdraw the Ptr[Void]-concrete carve.
>
> Q-mechanism: A. … Reject B (arity-1 generic is overhead A already obviates), C (carve-out +
> discipline, unsound narrowing), D (footgun remains). … Q-null: (i) Option[Foo], no is_null. NPO
> gives honest nullability at zero cost and zero raw surface; null_opaque/reserved-Opaque[T] is
> speculative — YAGNI. Q-cost: A is the minimum … Q-soundness: A is sound BECAUSE it never narrows
> E0811 — exemption is by-construction of a distinct annotated declaration, so containment stays
> SYNTACTIC.

**AI/ML — PIVOT B→A (mechanism and null) / cost A / reject C:**

> On pure generability, A wins and I pivot from my Phase A position. My B rationale rested on two
> claims that don't survive scrutiny. First, the Win32-HANDLE collision I raised is a collision with
> the async `Handle` carrier — A avoids it just as well by using the concrete name (`Sqlite3`) with no
> generic wrapper at all … Second, B's "spelling teaches affordances" edge is real but weak: the
> no-deref/no-member constraint is compiler-enforced under BOTH designs … Meanwhile B introduces its
> OWN novel misuse vector A lacks — `Opaque[T]` where T must be an uninhabited FFI tag contradicts the
> universal `Foo[Bar]`=container-of-arbitrary-Bar prior, so an LLM will write
> `Opaque[Int]`/`Opaque[MyStruct]` expecting "pointer to that." A matches the C mental model exactly
> (`sqlite3*` → `Sqlite3`), reuses the nominal-type model wholesale … costs fewer tokens, and adds one
> fewer decision point. Honest verdict: A generates more reliably.
>
> Q-mechanism: A (pivot from B). … Q-null: (i) Option[Foo] at the NULL-observable boundary only, no
> is_null/null_opaque, no Opaque[T]? reservation (pivot from my Phase A (ii)). A second nullability
> channel … contradicts Blink's "no null, one way, Option must be earned" ethos … Q-construct:
> @ffi-boundary-only, returned directly, backstopped by construction error (merges PLT's E0826
> enforcement with Sys/Web ergonomics; DevOps `from_ptr` fine as the internal mechanism, not a
> user-visible step). … Q-cost: A does not pay B's costs and loses little. … Q-soundness: C erodes
> containment; A's inert token is the sound minimal choice.

#### Phase C — Tally

| Question | Result | Tally |
|----------|--------|-------|
| Q-mechanism | **A** (`@ffi.opaque` bare nominal, arity-0) | 6-0 (PLT + AI/ML pivot from B; Min pivot from C) |
| Q-null | **`Option[Foo]`, no `is_null`, guaranteed NPO** | 6-0 |
| Q-construct | **Sealed to the FFI boundary** | 6-0 in spirit; diagnostic-granularity sub-split (see below) |
| Q-cost | **A cheapest** (arity-0 avoids B's four seams) | 6-0 |
| Q-soundness | **Reject C** (A never narrows E0811; C erodes containment + nominal distinctness) | 6-0 |

No Phase D — every core question was 6-0.

**Soft-consensus sub-point (Q-construct diagnostic form).** All six agreed construction is
boundary-sealed and fabrication outside `@ffi` is rejected. They split only on *how* the rejection is
reported: PLT and AI/ML preferred a dedicated code (`E0826`, *opaque handle constructed outside FFI*);
DevOps, Min, Sys, and Web preferred reuse of the existing construction / type-mismatch diagnostics
plus the `opaque-ffi-handle` audit category ("zero new error codes"). Per the user's sign-off, the
spec ships **zero new codes + audit category**, and records `E0826` as an implementation-discretion
fallback if the reused error proves unclear in practice.

### Recorded concerns (for the implementation)

- **NPO must be guaranteed by the type system** (`Foo` known-pointer), not a best-effort optimizer
  pass, or the one-word `Option[Foo]` guarantee is a lie (Sys, Min, PLT).
- **`@ffi.opaque` must stay permanently method-free** — no `deref`/`addr`/`offset` ever accreting;
  the inertness invariant needs a test (Min, AI/ML).
- **`.addr()` / round-trip reconstruction must stay `@ffi`-confined**, or fabrication re-opens (PLT).
- The opaque nominal must **print as `SqliteConn`, not lowered `sqlite3*`**, in diagnostics/hover
  (DevOps).

### AI-First Review — 5/5 pass

Learnability (matches the `sqlite3*`→`Sqlite3` C prior), Consistency (reuses the nominal-type model
wholesale), Generability (one fewer decision point than `Opaque[Tag]`; no container-of-Bar misread),
Debuggability (reuses existing "no method"/type-mismatch diagnostics), Token Efficiency (`SqliteConn`
vs `Opaque[Sqlite3]`). The panel converged on A partly *on* these grounds.

### Final Spec

```blink
@ffi.opaque(header = "sqlite3.h", name = "sqlite3")
type Sqlite3

@ffi.opaque(header = "sqlite3.h", name = "sqlite3_stmt")
type Sqlite3Stmt

// flows through ordinary non-FFI code — Sqlite3 is not a Ptr, so no @trusted
pub type Connection {
    db: Sqlite3,
}

// raw FFI binding — private, audited
@ffi("sqlite3", "sqlite3_open")
@effects(IO)
@trusted(audit: "DB-003")
fn raw_sqlite3_open(path: Ptr[U8], out: Ptr[Sqlite3]) -> Int

// safe wrapper — mints the opaque handle at the boundary
pub fn open(path: Str) -> Option[Connection] ! IO {
    with ffi.scope() as scope {
        let out = scope.alloc[Sqlite3]()          // Ptr[Sqlite3] out-cell — a sqlite3**
        let cstr = scope.cstr(path)
        let rc = raw_sqlite3_open(cstr, out)
        if rc != 0 { return None }
        Some(Connection { db: out.deref() })      // Ptr[Sqlite3].deref() -> Sqlite3, at the boundary
    }
}
```

Locked design points:

- `@ffi.opaque(header, name) type Foo` — a **bare nominal, arity-0** handle type; no body; each
  declaration is its own nominal type.
- Lowers to `name *`, **one machine word**; **no `sizeof`/`offsetof` `_Static_assert`** (incomplete
  by design — the contrast with `@ffi.struct`).
- **E0811-exempt by construction** (it is not a `Ptr[T]`); containment stays purely syntactic — the
  gate is not narrowed.
- **Inert** — no `.deref()`/`.addr()`/`.offset()`/field access/`==`; hold, pass, return, store only.
  Zero raw-pointer surface in non-FFI code.
- **Absence is `Option[Foo]` only** — no `.is_null()`, no null sentinel — with **guaranteed
  null-pointer optimization** (C `NULL` is the `None` niche; one word, one compare).
- **Construction sealed to the FFI boundary** — an `@ffi` return, or a `Ptr[Foo]`-cell `.deref()`
  inside `@ffi`/`@trusted`. `Ptr[Foo]` is a legal FFI inner type (`name **`, the out-param shape).
- **Zero new error/warning codes**; one new `blink audit` category `opaque-ffi-handle`.
