# Stage 2 divergence map — tid collapse

Produced by the Stage 2 instrument (`sv_ty_or_flat` / `ty_divergence_*` in
`src/typecheck.bl`) over a sweep of `tests/` + `examples/` + `src/` with
`BLINK_TRACE_CHANNELS=tydiv`. Plan: "Collapse codegen's flat type universe onto
typecheck's tid", Stage 2 exit criterion — *a concrete enumerated list of divergence
sites replacing the open cell tickets*.

Date: 2026-08-11. Compiler state: Stages -1, 0, 1, 2 applied; `task ci` green.

## What the instrument measures

At `emit_let_binding`, immediately ahead of the declaration chain that turns a variable's
type into C, it compares two answers to "what type is this variable":

- **tid** — typecheck's own answer, published on the `let` node (`final_tid`) and read back
  via `tc_lookup_node_tid`.
- **flat** — what codegen re-derives from `ScopeVar`'s six flat fields, rendered through the
  `tp_*` pool by `sv_tp` + `tp_display`.

Buckets: **agree** (structurally same shape), **diverge** (both present, different),
**missing** (no tid at all). The comparison is structural, not string equality: it walks
`tc_tid_child` against `tp_get_child1/2` and requires `tk_to_ct(kind)` to match the tp
kind at every level. The tid is returned either way — **the answer is discarded**, the flat
fields still govern every emit decision, which is what keeps emitted C byte-identical.

## Totals

```
site                          agree     diverge  missing
emit_let_binding.decl         216997    8070     39
copy_list_compound_elem.src   0         0        1
copy_list_compound_elem.no_arm  — never fired —
```

Deduplicated (occurrences collapse because ~780 corpus roots each recompile the stdlib and
the compiler modules):

- **428 distinct shape cells** — `(bucket, site, tid-spelling, flat-spelling)`
- **989 distinct named cells** — the above plus the variable name
- 3873 distinct `(bucket, site, var, tid, flat, root-file)` rows

428 is the finite list Stage 3 has to drive to zero. It replaces "an unbounded backlog".

## Families

| | family | cells | occurrences | disposition |
|---|---|---|---|---|
| A | `tid=?` — typecheck says Unknown, codegen has a concrete type | 94 | 2103 | **blocks Stage 3** |
| B | `tid=Void` — typecheck erases to Void | 7 | 3154 | **blocks Stage 3** |
| M | no tid at all | 1 | 39 | **blocks Stage 3** |
| C | flat side erased (`List[Void]`, `List[]`, `Result[X, ]`, `Map[K, Void]`) | 100 | 731 | killed structurally by Stage 3 |
| D | enum stored as `Int` in codegen | 18 | 639 | resolved by construction |
| E | same spelling both sides, differing `CT_*` (enum-vs-struct) | 28 | 864 | resolved by construction |
| F | spelling / mono-stem / typevar-vs-concrete / fabricated payload | 180 | 579 | per-cell triage in Stage 3 |

### A + B + M — 102 cells, 5296 occurrences (65% of all divergence)

Not one root cause but four, all of the same *shape*: **typecheck answers `Unknown` or
`Void` where codegen's parallel registries hold the right answer.** Each was reproduced by
hand (`.tmp/s2v/p1.bl` … `p4.bl`); the earlier name-matched attributions that did **not**
reproduce have been removed rather than guessed at.

**B1 — a failed `lookup_named_type` falls back to `TYPE_VOID`** (3124 occ in one cell,
the largest single divergence in the corpus). `src/typecheck.bl:5810`, `:5815`, `:5822`:

```blink
let pr = lookup_named_type("ProcessResult")
if pr != -1 { return pr }
return TYPE_VOID          // <- fail-open erasure
```

`lookup_named_type` returns `-1` whenever `ProcessResult` is not a declared type in the
compiling unit, and typecheck then reports `Void`. Codegen's parallel registry has it right:
`src/codegen.bl:634` `reg_fn_struct_ret("process_pid_wait", "ProcessResult")`. The same
fail-open shape sits at `src/typecheck.bl:8797` for `Instant`. All four sites are one fix.

**B2 — `List.pop()` returns `Void`, not `Option[T]`.** Verified minimal case:

```blink
let mut xs: List[Option[Int]] = []
xs.push(Some(1))
let popped = xs.pop()     // tid=Void   flat=Option[Option_int]
```

Reproduces for a scalar element inside the `Option` too, so it is not the compound-element
family — `pop()`'s return type is simply not computed.

**A1 — `let mut` on the receiver loses the method's return type.** The sharpest finding of
the sweep, and the source of the large `Str` / `Int` / `Bytes` cascade families. The two
functions below differ only in `mut`:

```blink
fn a() -> Int {
    let sb = StringBuilder.new()
    let s = sb.to_str()      // AGREES — Str
    s.len()
}
fn b() -> Int {
    let mut sb2 = StringBuilder.new()
    let s2 = sb2.to_str()    // tid=?  flat=Str   <- diverges
    s2.len()
}
```

Both receivers are themselves `tid=?` (`StringBuilder.new()` is untyped — see A2), yet only
the non-`mut` one resolves `to_str()`. This is what makes `src/lexer.bl:800-801`
(`let buf_str = string_buf.to_str()` -> `tid=? flat=Str`, 357 occ; `let buf_len =
buf_str.len()` -> `tid=? flat=Int`, 247 occ) diverge — reproduced verbatim in
`.tmp/s2v/p2.bl`.

**A2 — intrinsic constructors are untyped.** `let sb = StringBuilder.new()` is `tid=?`
against `flat=StringBuilder` (715 occ), and `let r = process.run(...)` in a user file is
`tid=? flat=Void` — *both* sides erased there. This is the same shape as the open Stage 0
finding `vag3wc` (`TyKind.Closure / Iterator / Handle / Channel` are unconstructible —
`new_type` never emits them — while `CT_CLOSURE / CT_ITERATOR / CT_HANDLE / CT_CHANNEL`
exist).

**M — async bindings carry no tid at all.** All 39 missing occurrences are
`tests/test_async_*` (`let r1 = ...`, `let awaited_val = async.scope { ... }`), plus
`src/cli.bl:2187-2189` `let mut err_text = br.out` (a cascade: field access on the
`Void`-typed `br` from B1 yields no tid), plus `conn_fd` from `net` accept (`vag3wc`).

**Stage 3 cannot claim the tid is authoritative while typecheck's universe is missing types
codegen has `CT_*` for.** A1, A2, B1, B2 and `vag3wc` are prerequisites, not Stage 3 work.

### C — 100 cells: the depth >= 2 money bucket

The flat pair `(CT_*, sname)` represents depth 1, so a container's struct element is simply
gone. Top cells:

```
220  tid=List[MatchScrutEntry]        flat=List[Void]
189  tid=List[NativeDep]             flat=List[]
 47  tid=List[Pollfd]                flat=List[Void]
 40  tid=List[HandlerCapture]        flat=List[Void]
 27  tid=Map[Str, List[Str]]         flat=Map[Str, List[Int]]     <- sv_tp's type_map(type_string(), type_int())
 14  tid=Result[Char, ConversionError] flat=Result[Char, ]
 13  tid=Result[TcpSocket, NetError] flat=Result[, ]
  9  tid=Map[Str, Box[Int]]          flat=Map[Str, Void]
  9  tid=List[Row]                   flat=List[Void]
  8  tid=Map[Str, Str]               flat=Map[Str, Int]           <- same fabrication
```

`Map[Str, List[Str]] -> Map[Str, List[Int]]` and `Map[Str, Str] -> Map[Str, Int]` are
`sv_tp` fabricating `type_map(type_string(), type_int())` when the flat slot is `-1`,
caught in the act. This whole family is what `csv-authority-retirement` (03p551) has been
issuing one ticket at a time; Stage 3's recursive lowering kills it structurally, and
Stage 5 closes those tickets as *subsumed*.

### D + E — 46 cells: the flat universe cannot tell an enum from a struct or an Int

`CT_ENUM` is referenced at only 8 sites in `codegen_types.bl` (one of them `sv_tp`), so an
enum-typed variable is stored as `CT_INT` (family D: `tid=TyKind flat=Int` 483,
`tid=TokenKind flat=Int` 95, `Color` 16, `Direction` 11) or as `CT_STRUCT`-with-sname
(family E: `TyKind` 598, `TokenKind` 141, `NetError`, `Event`, `DbError`, `QueryError`,
`Msg`, `Cmd`, `Errno`, ...). Both spellings match on the name, so the divergence is in
`CT_*` alone. The comparator is correctly strict here: these are real representational
facts about the flat universe, not instrument artifacts, and they vanish by construction
once codegen reads `TyKind.Enum` off the tid.

### F — 180 cells: triage individually in Stage 3

Includes fabricated payloads (`tid=Handle flat=Handle[Int]` 77, `tid=Ptr flat=Ptr[Int]`
70), mono stems (`tid=Tree flat=Tree_0Int`), tuple naming (`tid=(Int, Int)
flat=Tuple2_int_int` 22), and the reverse direction where **codegen is more precise than
typecheck** because it has monomorphised (`tid=K flat=Str` 14, `tid=List[K] flat=List[Str]`
14, `tid=List[K] flat=List[Int]` 8). That last group is expected at generic definition
sites and must not be "fixed" by making the tid concrete.

The `tid=Ptr flat=Ptr[Int]` cell named here is **retired**, and reading why is worth more than the
cell: `Ptr` on the tid side was not a fabricated payload at all, it was the *whole* type — a bare
typevar, because `TyKind.Ptr` did not exist. `w13xgb` split it into three faithful cells in which
the **flat** side is the fabrication. Family F is therefore not a single triage bucket: some of its
cells are codegen guessing, some are typecheck having nothing to say, and the two look identical in
the instrument. Check which side is the liar before triaging one.

## Prerequisites for Stage 3 (filed)

Stage 3's exit criterion is the divergence counter at **0**. It cannot reach 0 while
typecheck's universe is missing types codegen has `CT_*` for, so these are prerequisites,
not Stage 3 work:

| ticket | | |
|---|---|---|
| `b907wt` | P1 | `lookup_named_type` failure falls back to `TYPE_VOID`, erasing `ProcessResult` / `Instant` (family B1, 3124 occ) |
| `pvyrdb` | P1 | a `let mut` receiver loses its method's return type; the identical non-mut receiver resolves it (family A1) |
| `7cq6w2` | P2 | `StringBuilder.new()` and other intrinsic constructors produce no type (family A2, 715 occ) |
| `dvzt90` | P2 | `List.pop()` returns `Void` instead of `Option[T]` (family B2) |
| `e0wmt6` | P2 | async block / spawn `let` bindings carry no tid at all (family M, all 39 missing) |
| `vag3wc` | — | `TyKind.Closure / Iterator / Handle / Channel` unconstructible while their `CT_*` exist (from Stage 0) |
| `k9agr8` | P2 | `build/blinkc` ignores `BLINK_TRACE_CHANNELS`, so the counter cannot be measured monolithically |
| `sskpk8` | P2 | declared `let` type compared against the initializer, never unified into it, leaving ctor metavars unbound |
| `twq9kz` | P2 | `copy_list_compound_elem` never reached across the corpus — prove its 3 missing arms are live |
| `pgc3d9` | P1 | *(filed later, from re-measuring `missing` for the Stage 3 kickoff)* closure and `handler` bodies in argument position never typechecked — 13 of the 14 residual `missing` cells |
| `nz7drz` | P2 | *(the first Stage 3 root cause worked)* a closure literal had no type at all, and an `fn(..)` annotation lowered to a bare typevar — 16 family-A cells, plus 5 more retired as knock-on |
| `bfq7nf` | P2 | *(the 2 cells `nz7drz` left)* a block whose tail is a bare Ident bound inside that block infers nothing — not arena- or closure-specific |
| `3c4g71` | P2 | *(`bfq7nf` one NodeKind over, found by `at=` attribution)* a match arm body naming its own pattern binding infers nothing; a diverging sibling arm cannot cover for it — 17 declaration sites, 4 in the compiler's own source |
| `8wk3xg` | P2 | *(by-product of adding `at=`)* a local `let at = ..` resolves to `parser.bl`'s PRIVATE `fn at` and reports `ImportNotSelected`; blocks renaming `ty_div_trace`'s `at_str` back |
| `zs7khh` | P2 | *(first sub-mechanism of the ranked top cause)* static `Type.from` / `Type.try_from` resolved no return type — the fnsig key is source-typed `{T}_{m}_{Src}`, and neither key the call site tried can name it — 10 family-A cells |
| `3xhh59` | P2 | *(exposed by `zs7khh`)* an impl method spelling `-> Self` registers the literal `Self` typevar as its fnsig return; a typevar is as permissive as `TYPE_UNKNOWN`, so the compare stays disabled |
| `2r96m9` | P2 | *(second sub-mechanism of the ranked top cause)* `Bytes.zeroed` / `Bytes.from_str` produced no type — `get_builtin_fn_ret` is keyed on the type name alone, so a mirror gated on `method == "new"` could not name them — **−354 family-A rows, the largest reduction so far**, and it was masking a real miscompile |
| `w13xgb` | P1 | *(the outright #1 after `rbd0a4`, and the largest row reduction of the campaign at −177)* `Ptr[T]` had **no `TyKind` variant at all**, so `Ptr[Pollfd]` lowered to a bare typevar named `"Ptr"` and the receiver was untyped before any method arm could run. Five regens: variant → `resolve_type_ann` → `types_compatible` → the `Ptr` method block → `Str.as_cstr`. It was hiding a raw `cc` error, not a missing diagnostic |
| `rbd0a4` | P2 | *(#2, same audit)* `Str` intrinsic aliases `substr` / `charAt` and `Int.to_string()` resolve no return type — **−157 rows**; the ticket's four names split three ways, and `charAt` turned out to name a method that does not exist at all |
| `xfrd4j` | P2 | *(exposed while scoping `rbd0a4`)* typecheck's allow-list affirms `Int.to_str()`, `Str.to_float()` and `to_string()` on a `Bool` or sized int, which codegen does not implement — the error lands at codegen, so `blink check` is untrustworthy for them |
| `jzvxav` | P1 | *(the untyped-receiver shape a fourth time, after `w13xgb` / `ps5br9` / `nrrs28`)* `self` was bound as `TYPE_UNKNOWN` in **every impl method body in every Blink program** — `resolve_param_type` answers UNKNOWN for an un-annotated param and `self` is the one param that never carries one. It was hiding a raw `cc` error: `self.get(42)` against `fn get(self, k: Str)` passes `blink check` |
| `ya8qyf` | P1 | *(found as the one row that stayed red under `jzvxav`; `zd1tz3` closed as its duplicate)* an impl method's declared **return** type was never checked — `tc_mangle_impl_fnsig` registers `{type}_{trait}_{method}` and the check side looked up `{type}_{method}`, so `lookup_fnsig` always missed and `tc_current_fn_ret` was never installed. Divergence-neutral; a pure diagnostic/escape fix |
| `h3q81d` | P2 | *(the ranked #1 after `jzvxav`)* an effect **operation** had no typecheck-side signature anywhere — only the handle name, for warning suppression — while codegen carried the same signatures across **eight flat return fields**, the last pair existing only because `Result[Option[Row], DBError]` is depth 2. **−49 rows**, and both halves were escaping to `cc` |
| `w089a0` | P2 | *(`h3q81d`'s residual, and the untyped-receiver shape a **fifth** time)* the with-resource `as` binder carries no type, so `with db.prepare(..).unwrap() as stmt` leaves `stmt.step()` with an untyped receiver even though `db.prepare` now resolves. `let bad: Str = r.value()` compiles clean and prints `7` |

`k9agr8` gates the *measurement*, not the code: without it Stage 3 can only demonstrate 0
in archive-linked mode.

## copy_list_compound_elem — an unexercised tap, not a clean result

`.src` fired **once** across the entire corpus, as *missing*. `.no_arm` — the instrumented
stand-in for the absent `CT_SET` / `CT_LIST` / `CT_STRUCT` arms, three open 03p551 cells
verbatim — **never fired at all**. Per `feedback_corpus_sweep_is_not_coverage` a zero-hit
sweep is an unexercised tap and proves nothing: the shapes must be constructed by hand
before the three missing arms can be called live or theoretical.

**Resolved — see `twq9kz` in the progress log.** The shapes were constructed. The three arms are
**dead by caller gating**, and the exercise turned up a blocker for Stage 3's planned replacement
of this very function.

## Build-mode attribution

The plan requires attributing sweeps in both build modes. The honest split achieved:

- **Byte-identity gate: monolithic.** `build/blinkc <f> <out.c>` over the whole corpus,
  compared against the Stage 1 baseline: **751 identical, 12 differ, 0 missing**. All 12 are
  compiler-introspection tests, and every delta is representational (`tp_display`
  static -> non-static, panic-message line shifts, `ScopeVar` literals gaining `.ty`,
  global-init temp renumbering from the new `ty_div_rows` global, new function bodies).
  **Zero ordinary corpus programs changed.**
- **Divergence sweep: archive-linked only** *(fixed — see `k9agr8` in the progress log;
  the monolithic sweep is now the authoritative one and it is a strict superset)*.
  `BLINK_TRACE_CHANNELS` was read only at `src/cli.bl:3520`; `src/blinkc_main.bl` never
  initialised `dbg_channels`, so `build/blinkc` — the only monolithic emitter — could not be
  traced, and `blink build` has no monolith flag (`--emit binary|c|per-module-dir`). Stage 3
  needs monolithic-mode measurement to prove the counter reaches zero in both modes, so
  `blinkc` had to learn the channel env var first.
- **Tap proven to fire by hand**, not inferred from corpus hits: a constructed probe emitted
  three `bucket=diverge` rows before the LetBinding tid memo was published and zero after.

## Progress log — prerequisite fixes, measured against this baseline

Re-swept identically after each fix (`BLINK_TRACE_CHANNELS=tydiv build/blink build --emit c`
over `tests/ examples/ src/`, 786 roots, archive-linked). One correction to the baseline
first: **grep must be run with `-a`.** One captured stderr contains a NUL byte, so grep
treats the whole sweep file as binary and silently under-reports. Binary-safe recount of the
pre-fix sweep gives **429** shape cells, not the 428 stated above and in the appendix title —
the appendix itself is complete, the count line was one short.

### b907wt — runtime-backed types fail open to Void (CLOSED)

`ProcessResult` is a runtime-backed compiler-known type: the C struct is in
`bootstrap/runtime_process.h:10` and codegen names it with no Blink declaration at all
(`src/codegen.bl:634` `reg_fn_struct_ret` plus `:650-652` for the fields), so
`let r = process_pid_wait(pid)` compiles and runs in a file that never writes
`import std.process` — `src/cli.bl:2187` is exactly that. Typecheck knew the type only if
`lib/std/process.bl` happened to be in the program, and on a miss returned `TYPE_VOID`.

Fix: `ensure_runtime_struct_type` in `src/typecheck.bl` mints the declaration on demand —
`new_type(TyKind.Struct)` + `named_type_map` + `sfield_pool` field entries — and defers to a
real declaration because the lookup runs first. Registering the fields is the load-bearing
half; a fieldless mint would turn a silent erasure into a spurious "no field" error on
`r.out`. Test: `tests/test_b907wt_runtime_backed_type_fail_open.bl`.

| | pre | post | delta |
|---|---|---|---|
| shape cells | 429 | 428 | **−1** (exactly `tid=Void flat=ProcessResult`, no new cell) |
| diverge occurrences | 8070 | 5015 | **−3055 (−38%)** |
| agree occurrences | 216997 | 229126 | +12129 |
| missing | 40 | 40 | 0 |

The 3055 cleared exceeds the cell's own 3124-occurrence count minus what re-attributed, and
includes the downstream cascade this cell fed (`let err_text = br.out`): `src/cli.bl` alone
went 225 → 184 rows while its own `ProcessResult` rows went 26 → 0.

The `Instant` twin at the old `:8797` was made symmetric but is **not** live and cannot be
tested end-to-end: that branch also requires `is_import_module_name("time")`, so with no
`std.time` in the program the call types as Unknown before reaching the lookup — and
`std.time` is a prelude module (`compiler.bl:1357`), so the lookup normally hits.

Byproduct filed: **exb557** — `blink test <dir>` builds each test binary into `build/<dir>/`,
and `std.*` resolution is `argv[0]`-relative (`compiler.bl:634`), so no `lib/std` sits beside
the binary and **the entire prelude is silently absent** — with only an unflushed
`ModuleNotFound` to show for it. `blink test <file>` builds into `build/`, which does have
`build/lib/std`, so the same test file sees two different programs. This is why two halves of
the b907wt test passed standalone and failed under `task ci`; they now skip via a
`stdlib_loadable()` probe. It also means every compiler-introspection test in the suite runs
without prelude, so their coverage is weaker than it reads.

### 7cq6w2 — StringBuilder was not a type typecheck could name (CLOSED)

The appendix's largest family-A cell. Codegen has had `CT_STRINGBUILDER`
(`src/codegen_types.bl:49`) lowering to `blink_sb*` since forever, with the full method
surface in `emit_sb_method` (`src/codegen_methods.bl:2017`) — but `TyKind` had no
corresponding variant, `StringBuilder` is declared in no `.bl` file anywhere (`lib/std/sb.bl`
declares only *functions over* it), so `resolve_type_name("StringBuilder")` answered `-1` and
every `sb: StringBuilder` param, `-> StringBuilder` return, and `StringBuilder.new()` call
inferred `Unknown`.

Fix, all in `src/typecheck.bl`: a `StringBuilder` variant on `TyKind`; `type_stringbuilder()`
minting **one interned** tid via `ty_intern_simple` (not `new_type`, which is deliberately
un-interned to keep metavars fresh and would have produced one tid per mention — measured: 10);
arms in `resolve_type_name`, `get_builtin_fn_ret`, `type_to_str`, `tk_to_ct` (→ the existing
`CT_STRINGBUILDER`), `tc_tid_child_count`/`tc_tid_child`, and both `tc_tid_tag_at` spellers
(Pascal at the carrier position, lowercase inside a segment, mirroring
`type_name_from_ct` / `c_type_tag`); the seven instance methods mirrored method-for-method
against `emit_sb_method`; and both static constructors resolved from the receiver's **name
before `infer_type(obj_node)` runs** — load-bearing, because a `TyKind` in scope now owns a
variant spelled `StringBuilder`, and bare-variant resolution would otherwise infer the
receiver Ident as that enum and reject the constructor with E0505. `with_capacity` also
joined `is_builtin_method`, retiring a spurious `W0501` for a constructor codegen has always
emitted. Not added to the four conservative encodability allowlists — those admit only shapes
*proven* byte-identical; omission is the safe side.

Test: `tests/test_7cq6w2_stringbuilder_type.bl` (4 tests: one interned tid + kind + chain
coverage, the seven method returns, `let s: Int = buf.to_str()` is a `TypeError`, and a
runtime half). Receivers are named `buf`/`cap`, never `sb` — see mjsbwm below.

| | pre | post | delta |
|---|---|---|---|
| shape cells | 428 | **427** | **−1** (exactly `tid=? flat=StringBuilder`, no new cell) |
| diverge occurrences | 5015 | **4190** | **−825 (−16%)** |
| agree occurrences | 229126 | 229975 | +849 |
| missing | 40 | 40 | 0 |

The −825 is the cell's own 744 occurrences plus the cascade it fed: `tid=? flat=Str`
305 → 251 (the `.to_str()` results) and `tid=? flat=Int` 251 → 224 (`.len()` / `.capacity()`).
Counts exclude the new test file as a sweep root, which is new coverage rather than a delta
(it adds ~9.8k agree rows on its own since it compiles the whole compiler).

Build-mode attribution: the divergence sweep is still archive-linked only (blocked on
`k9agr8`), so the cell's *behaviour* was attributed in both modes by hand instead —
`.tmp/sb7/mono.bl` exercising `new`/`write`/`write_char`/`to_str`/`len`/`with_capacity`/
`capacity`/`is_empty` plus a `StringBuilder` param prints `abc 3 true true` identically under
`build/blinkc` + `cc` (monolithic) and `build/blink run` (archive-linked).

Byproducts filed: **mjsbwm** (P1, depends on this) — with the receiver Unknown, inference fell
through to the static-call path at `src/typecheck.bl:8878`, which builds a fnsig key by
*string concatenation*: `"{obj_name}_{method}"`. A receiver spelled `sb` therefore keyed
`sb_to_str`, `lib/std/sb.bl:31`'s FFI free fn, so `sb.to_str()` typed as `Str` for the wrong
reason while the identical call on `zz` stayed Unknown. Reproducible in pure user code with
only a warning (`let foo = 42; let s: Int = foo.bar()` adopts `foo_bar`'s return type). Two
defects: no check that the receiver Ident names a type rather than a bound value, and
resolution by name concatenation. This fix is what removes the compiler's own reliance on the
accident, hence the sequencing.

Also disproven and closed: **pvyrdb**, which claimed `mut` erases a method's return type. The
axis was the receiver's *name*, not its mutability — `nr_is_mut` has zero callers, and
`.tmp/pv/p8.bl` showed non-mut `zz` and mut `qq` both diverging while `sb` agreed.

### mjsbwm — a value receiver adopted `{name}_{method}`'s return type (CLOSED)

Not a divergence cell of its own: it is the *wrong answer* 7cq6w2 exposed. With
`StringBuilder` unrepresentable, `sb.to_str()` was resolving through
`src/typecheck.bl:8955`, which built a fnsig key by string concatenation —
`"{obj_name}_{method}"` → `sb_to_str`, `lib/std/sb.bl:31`'s FFI free fn. That path is
legitimate for a receiver that *names a type*: Blink has no inherent methods at all
(`sections/03c_protocols.md:758`), so the stdlib spells every static constructor as a
type-prefixed free fn (`pub fn Duration_seconds(s: Int) -> Duration` **is**
`Duration.seconds(2)`). It was gated on nothing, so an ordinary local adopted an unrelated
function's return type in pure user code — `let foo = 42; let s: Int = foo.bar()` with a
`fn foo_bar(x: Int) -> Str` in scope produced `error[TypeError]: variable 's': declared type
Int but got Str`, blaming the user's correct annotation for a type typecheck invented.

Fix: `nr_has_binding(name)` — a **pure** existence probe (`nr_is_defined` marks
`nr_scope_reads`/`nr_scope_captured`, so asking it at inference time would silence
W0310/W0601 for every name asked about; same contract as `nr_top_binding_is_global`) — and
`obj_is_value == 0` on all three receiver-name-keyed static paths: the sealed-builtin `new`,
the trait-qualified `{Type}_{trait}_{method}`, and the bare `{Type}_{method}`. Name
resolution follows scope: a name with a binding is a value, and `value.method()` is an
instance call whatever a same-spelled type could have offered.

Test: `tests/test_mjsbwm_value_receiver_static_fnsig.bl` (4 tests) — the defect, the
annotation-blaming diagnostic, the pseudo-static that must keep working (a locally declared
`Widget_make`, not a stdlib import: prelude presence is harness-mode-dependent per exb557),
and the shadowed-type case.

| | pre | post | delta |
|---|---|---|---|
| shape cells | 427 | 427 | 0 |
| diverge occurrences | 4190 | 4190 | **0** |
| agree occurrences | 229975 | 229999 | +24 |
| missing | 40 | 40 | 0 |

**Divergence-neutral by construction, and that is the point**: these were answers where
typecheck and codegen were wrong *together* (both resolve by receiver spelling), so the
instrument could never have flagged them. Recorded here because Stage 3 makes the tid
authoritative — a cell that "agrees" on a fabricated type is exactly what would have been
promoted silently.

End-to-end, both build modes: `foo.bar()` now reports `warning[UnknownMethod]` at `check`
and the identical `error[UnresolvedMethod]: unresolved method '.bar' on type Int in 'main'`
under `build/blink run` (archive-linked) and `build/blinkc` (monolithic) — previously the
annotated form produced the bogus TypeError instead. A shadowed *user* pseudo-static
(`let Widget = 7; Widget.make(3)`) also now reaches that error correctly.

Byproducts filed: **mfqnp0** — codegen's static-constructor intrinsics are keyed on the
receiver's *spelling* (`src/codegen_methods.bl:2605` `node_name(obj_node) == "Duration"`,
same at `:2639`/`:2525`/`:2557`/`:2583`) with no scope check, so `let Duration = 5;
Duration.seconds(2)` still emits `blink_Duration_seconds(2)` and prints `<value>`. The
`io.*` dispatch 46 lines below already carries the right guard (`mc_obj_is_local == 0`).
**mnf8m9** — one `task ci` run reported `BUILD FAILED` for two unrelated test files at
`--parallel 24` with no diagnostic captured; the next run of the identical tree was 619/619.
Both files build clean standalone, so it is the harness. A note was added to **vctk7f**: an
unresolved method on a *scalar* receiver is `check`-vs-`build` fail-open, because
`tc_method_resolvable_on_type` is reached only for Struct/Enum receivers.

Also filed from the 7cq6w2 work: **zb0bwm** — `Color.Purple` on `type Color { Red, Green }`
passes typecheck and fails only at C compile (`'blink_Color_Purple' undeclared`). Found when
a `TyKind.StringBuilder` written before the variant existed typechecked clean; it reproduces
on a plain user enum with no compiler introspection.

### k9agr8 — `blinkc` ignored BLINK_TRACE_CHANNELS, so half the corpus was never swept (CLOSED)

Not a type bug: a one-line startup omission that invalidated the *scope* of every number
above. `dbg_trace`'s sink (`src/ast.bl:230`) gates on the mutable global `dbg_channels`, and
only `src/cli.bl:3520` ever assigned it. `src/blinkc_main.bl` — the monolithic compiler
binary — did not, so every channel was permanently dark there. Fix: mirror cli's one line at
the top of blinkc's `main` (`dbg_channels = env.var("BLINK_TRACE_CHANNELS") ?? ""`) plus the
`import ast.{dbg_channels}`. `tests/test_k9agr8_blinkc_trace_channels.bl` spawns the binary
for real — the defect was in a startup path, and only a child process can observe one — and
covers all four states: named channel on, unset silent, unrelated name still off (the
wildcard must not degrade into "any non-empty value means all"), `all` on. Red 2/4, green 4/4.

The monolithic sweep it unlocks is a **strict superset** of the archive-linked one, and the
gap is systematic rather than incidental:

| | roots with codegen | agree | diverge | missing | shape cells |
|---|---|---|---|---|---|
| archive-linked (`blink build --emit c`) | 789 | 247990 | 4396 | 40 | 425 |
| monolithic (`build/blinkc <f> <out.c>`) | 869 | 316728 | 4552 | 40 | **433** |

Mode-exclusive cells: **8 monolith-only, 0 archive-only.** Every one belongs to a *stdlib
module body* — `args.bl`'s `CommandDef`/`FlagDef`/`OptionDef`/`PositionalDef`,
`http_server.bl`'s `RouteSegment`, `testing.bl`'s `Cleanup`:

```
? | Cleanup
List[CommandDef]    | List[Void]   (and | List[])
List[FlagDef]       | List[Void]
List[OptionDef]     | List[Void]
List[PositionalDef] | List[Void]
List[RouteSegment]  | List[Void]   (and | List[])
RouteSegment        | RouteSegment
```

That is exactly the blindness `feedback_corpus_sweep_is_not_coverage` warns about, with a
mechanism: archive-linked builds put every `lib/std` module in `cg_skip_modules`, so an
archive sweep cannot see any stdlib module's own let-bindings **by construction** — no
number of extra corpus roots would have found these. The 80 extra monolithic roots are files
`blink build` refuses outright (module-only sources with no `main`: `src/pub_import_*.bl`,
`src/multifile_helper.bl`, and the like), which the monolithic emitter compiles anyway.

Two things the map should be read with from here on:

- **The monolithic sweep is the authoritative one.** The published 425-cell archive figure is
  a floor; Stage 3's exit condition (counter at 0) must be evaluated against the 433.
- **`RouteSegment | RouteSegment` is a divergence where both sides spell the same thing.**
  `RouteSegment` is the named-payload enum at `lib/std/http_server.bl:9`; the flat universe
  carries it as a struct, and the counter compares tids via `tc_tid_same_type`, not strings.
  It is the one cell that proves spelling equality is not type equality — a future
  "just compare the two strings" shortcut in the instrument would silently erase it, along
  with the whole D+E enum-vs-struct family it belongs to.

`task regen` green, `task ci` green (620 test files). One flaky `task ci` run first reported
`tests/test_cli_cascade_no_phantom_failures.bl` failing its `"build_errors":1` assertion; that
test spawns a nested parallel `blink test` inside the outer `--parallel 24` harness, it passes
standalone on repeat, and the identical tree was green on re-run — noted on **mnf8m9** as a
second instance of the same harness-contention family.

### dvzt90 — `List.pop()` was sharing `clear()`'s Void arm (CLOSED)

One line, `src/typecheck.bl:8513`: `if method == "pop" || method == "clear" { return TYPE_VOID }`.
`clear` is genuinely Void; `pop` removes **and returns** the last element —
`sections/03_types.md:390` (`let last = items.pop()  // Some(9)`) and `lib/std/traits.bl:56`
(`fn pop(self) -> Option[T]`) both say so, and codegen has built the Option since gemr3z
(`src/codegen_methods.bl:1285`/`:1316` exist only to nest it for `Option`/`Result` elements).
Split into `pop -> make_option_type(elem)` and `clear -> TYPE_VOID`.

First measurement in the **monolithic** mode k9agr8 unlocked, and the first fix whose
divergence delta is fully accounted for row by row:

| | cells | diverge | agree | missing |
|---|---|---|---|---|
| before | 433 | 4552 | 316728 | 40 |
| after | **426** | **4494** | 316786 | 40 |

−58 diverge, +58 agree, **0 new cells** — the same 58 rows moved buckets, nothing was
reshaped. Seven cells died, two of them one hop downstream:

```
Void | Option[Int]                        direct
Void | Option[Big]                        direct
Void | Option[Option[Int]]                direct  (the gemr3z nesting)
Void | Option[Option[Map[Int, Str]]]      direct
Void | Option[Result[Int, Str]]           direct
?    | Big                                cascade — unwrap() of a Void
?    | DiagEntry                          cascade — src/diagnostics.bl:435
```

`src/diagnostics.bl:435` (`let d = diag_entries.pop().unwrap()`) is the cascade in one line:
unwrapping a Void yields `?`, so a single wrong return type produced a *second* family of
cells at every consumer. The ticket predicted 4 cells; the honest count is 7.

Half B of `tests/test_dvzt90_list_pop_option.bl` is the load-bearing half — a type computed
but never *checked* is relabelled, not fixed, so `let n: Int = xs.pop()` must actually report
a TypeError. It did not before (Void was compatible with everything, which is precisely why
the mislabel survived).

Byproducts, both filed rather than fixed here:

- **tavvwj** — a let bound to `List[Option[T]].get()`/`.pop()` records only the OUTER Option
  in codegen's flat `ScopeVar`, so both readers of it break: `outer.unwrap().is_some()` errors
  with `UnresolvedMethod` from the backstop (which *names the type correctly*, `Option[Int]` —
  codegen knows the spelling and still has no dispatchable receiver), and the equivalent
  nested `match` emits C with an undeclared binding. Pre-existing and independent: `.get()`
  has returned `Option[T]` far longer than `.pop()` and breaks identically, while the same
  shape as an annotated literal (`let outer: Option[Option[Int]] = Some(Some(7))`) works for
  both readers. Family C; expected to be subsumed by Stage 3.
- **xrhq1c** — `warning[UnusedImport]` fires on the `import codegen_expr` these test files
  need, and obeying it fails the C compile with `'expr_option_inner' undeclared`. The import's
  only job is to close `codegen_types`' merged-program global back-references, which the
  checker's "did this file name an imported symbol" notion cannot see. Notable because the
  right fix may be to delete the back-references — several are the flat side-channels Stage 4
  removes — rather than to weaken the warning.

`task regen` green, `task ci` green.

### 1b7ggq — the `.await` operand was never name-resolved (CLOSED, divergence-neutral)

Found while scoping `e0wmt6`, not from the map. Recorded here anyway because it is the first
prerequisite that turned out **not** to be a divergence cell, and the list needs to be honest
about containing both kinds.

The parser stores the awaited operand in `obj` (`src/parser.bl:2865`,
`AstNode { kind: NodeKind.AwaitExpr, obj: node, ... }`). `nr_check_node` read `value`:

```blink
if kind == NodeKind.AwaitExpr {
    nr_check_node(node_value(node))     // -1 — should be node_obj(node)
    return
}
```

`node_value` is -1 for that kind, so the recursion terminated immediately and the entire
operand subtree went unvisited. Typecheck was the sole outlier — formatter, cli and
codegen_expr all read `node_obj` for this node. Two consequences, and the second is the
serious one:

1. `h1.await` did not count as a **read** of `h1`, so correct code drew
   `warning[UnusedVariable]: variable 'h1' is never read`, whose suggested fix (`_h1`) would
   mark a load-bearing binding as deliberately discarded.
2. An **undefined** identifier in that position was never reported at all.
   `build/blink check` printed `ok` and the name reached the C compiler as
   `'totally_undefined_name' undeclared` — the same check-vs-build fail-open class as vctk7f.

Divergence-neutral by construction (name resolution, not `infer_type`), and measured rather
than assumed: on a consistent basis — excluding the two test roots added since the dvzt90
baseline, since every new file is also a new sweep root — the monolithic sweep reads **426
cells / 4494 diverge** both before and after. `tests/test_1b7ggq_await_operand_resolved.bl`
asserts against the diagnostic stream (both halves *are* diagnostics; the emitted program was
correct all along in the well-formed case), plus one end-to-end
`async.scope`/`async.spawn`/`await` run.

Left standing: `infer_type` has no arm for `AsyncSpawn`, `AwaitExpr`, `AsyncScope` or
`ChannelNew` at all — that is `e0wmt6`, now blocked on **vag3wc** (`TyKind.Handle` and its
three siblings are unconstructible, which needs the construct-vs-delete decision).

`task regen` green. `task ci` green on re-run; the run immediately after the fix failed
`tests/test_cli_cascade_no_phantom_failures.bl`, the third instance of the **mnf8m9** harness
flake — not attributable here (three targeted reproduction attempts all passed, and the fix
adds only a traversal).

### sskpk8 — a declared container type was compared to the initializer, never unified into it (CLOSED)

The map's `tid=Map[?, ?]` and `tid=Set[?]` cells all reduced to one line. `let m: Map[Str,
List[Int]] = Map()` left the ctor node at `Map[α, β]` with **both metavars unbound** while the
fully concrete declared instantiation sat two tokens away. Codegen then read the ctor and got
a hole.

Everything needed to fix it already existed: `tc_pin_tail_ret_generic` performs exactly this
unify, and `tc_pin_admits_declared` already admits a `Map`/`Set` head. The only thing standing
in the way was the caller-side pre-check in the LetBinding arm:

```blink
if tc_node_has_ret_mint(val) != 0 { tc_pin_tail_ret_generic(declared_tid, inferred_tid) }
```

`tc_node_has_ret_mint` asks "did `instantiate_return_type` register a return-only metavar
group for this call node", which **only a generic fn call ever does**. A builtin container
ctor mints its metavars elsewhere and so could never qualify — the same defect `3dpshm` was,
one node kind over.

Deleting the pre-check outright is wrong, and the corpus said so: it turned five pinned rows
red across `test_6cvvh8`, `test_wzm47q`, `test_f8t5wb`, `test_23tfxg` and `test_5htahp`, four
as `BLINK_COMPILER_BUG_kops_unsupported_*`. So the second way in is narrow, and **each clause
paid for itself by breaking a specific pinned test when it was absent**:

- **`Map`/`Set` head only.** The struct/enum heads `tc_pin_admits_declared` also admits stay
  mint-gated. In `let e: GT[QB[Int]] = GT { s: Set() }` the α belongs to a *field*, not the
  binding, and making `Set[QB[Int]]` concrete drives `kops_table_name` down its fail-closed
  branch — `QB` carries no `Hash` derive, so there genuinely is no table. That program's hazard
  is real and pre-existing (the annotation-only hashability validators, br `xcx9wc`);
  surfacing it here would report it as a C compile error instead of a diagnostic.
- **No bare typevar** (`tc_tid_has_bare_typevar`, new). `let m: Map[K, V] = Map()` inside
  `fn f[K, V]()` must not pin: **α and T are not interchangeable**. α can still be bound — by
  a later use, an argument-position unify, or monomorphization — whereas `tc_is_unbound_metavar`
  counts only `TyKind.Unknown` with `inner1 < 0` and `tc_unify`'s typevar arm returns 1
  *without* binding. `α := T` therefore trades a solvable hole for an unsolvable one, and it
  emitted `BLINK_COMPILER_BUG_kops_unsupported_K_ct23_` — the kops selector had been recovering
  the concrete key from the instantiation.
- **No transparent alias** (`tc_tid_has_alias`, new). Over `type Port = Int`,
  `let m: Map[Port, Int] = Map()` keeps `Port` in the tid's key slot because `resolve_alias_tid`
  peels only the **outermost** alias, while the parallel annotation-node path
  (`type_from_name`) lowers it to `Int`. Pinning commits the un-canonical spelling and
  `blink_kops_i64` is never selected. Filed as **bvh7qt** (needs a structural alias resolver);
  the predicate and this clause are its workaround, to delete when it lands.

Two byproduct tickets, both with MVCEs:

- **jqb7gj** — a `let` inside a block expression in **call-argument position** is never walked
  by typecheck's LetBinding arm at all, so no tid lands on the let node, the initializer keeps
  its metavars, and no `E0301` is even possible. Same shape as `1hg8b6`, one node kind over.
  It is the **last surviving `tid=Set[?]` cell** in the map (`test_6ph073`).
- **bvh7qt** — above.

`tests/test_sskpk8_declared_let_unified_into_initializer.bl`: 13 rows, red 5/9 before, green
13/13 after. Half A pins the four initializer tids (`Map[Str, List[Int]]`, `Map[Int, Str]`,
`Set[Str]`, `Map[Str, Map[Int, Bool]]`); half B pins that a mismatch is still `TypeError` and
an unannotated `Map()` still `CannotInferType`; half C pins the `3dpshm` mint control, both
refusals (each with a *runtime* kops witness — `blink_kops_i64` present, sentinel absent), and
that monomorphic lets are untouched. The depth-2 **read-through** is deliberately omitted:
`n.get("k").unwrap().get(1)` still fails with `unresolved method '.get' on type
Map[Int, Bool]` — codegen NAMES the receiver correctly and has no dispatchable method for it,
because a value recovered from a container reader keeps only the outer level in the flat
`ScopeVar` (br `tavvwj`, family C). Expected to be subsumed by Stage 3.

**Divergence: neutral, and the raw counter moved anyway.** The monolithic sweep reads 426
cells / 4572 diverge / 317046 agree / 40 missing against the dvzt90 baseline of 426 / 4494 /
316786 / 40 — **+78 diverge and +260 agree**. That is not a regression, it is the instrument
measuring its own fix: the two new predicates and the gate add **13 `let` statements to
`src/typecheck.bl`**, and each of the 26 sweep roots that compiles the compiler measures all
13. Three of the 13 diverge and ten agree: 26 × 3 = 78, 26 × 10 = 260, per-file deltas exactly
uniform. Cell count is unchanged because both new diverge shapes (`tid=TyKind flat=Int` from
`let dk`, `tid=TyKind flat=TyKind` from `let k`) already appear in the pre-change map. **A new
trap for the sweep protocol: new *compiler* source adds new *sites* to every root, the same way
a new test file adds a new root.** Compare cells, and reconcile row counts against lines added.

Residual metavar-carrying tids after the fix: `List[?]` ×4, `Result[Int, ?]` ×3,
`Result[?, Str]` ×1, `Set[?]` ×1. The last is jqb7gj's; the other three are heads
`tc_pin_admits_declared` deliberately excludes.

`task regen` green. `task ci` green — 623 test files, 623 passed, 0 failed, 0 build errors.

### vag3wc — four TyKind variants that `new_type` was never called with (CLOSED, 3 of 4)

Stage 0 made `TyKind` a real enum, and that immediately raised a question the `TK_* = let Int`
constants had hidden: **which variants does anything actually construct?** `new_type`
(`src/typecheck.bl:605`) is the sole writer of `TypePoolEntry.kind`, and four of the 29 variants
never reached it — `Closure`, `Iterator`, `Handle`, `Channel`. They existed in the enum,
`tk_to_ct` mapped them to `CT_VOID` / `CT_ITERATOR` / `CT_HANDLE` / `CT_CHANNEL`, the spellers
had arms for them, `is_primitive_type` claimed their names, and every one of those arms was
unreachable. Four variants reading as coverage while representing nothing.

The cause is one line. `resolve_type_ann` has arms for List / Option / Result / Map / Set /
Tuple / Bytes, then `resolve_type_name(name)`, then a fall-through:

```blink
make_typevar(name)
```

So `let ch: Channel[Int] = ...` produced **a bare typevar wearing the name "Channel"** — inner
dropped, kind wrong, and unifiable with anything.

**This is not cosmetic, and the diagnostic proved it.** `is_deferred_iterable` decides
for-loop iterability by asking `iter_tk == TyKind.Channel`. A typevar is not that kind, so
*annotating* a channel made it un-iterable while the identical program without the annotation
compiled:

```blink
let ch: Channel[Int] = Channel(4)
for v in ch { }
error[NotIterable]: cannot iterate over type 'Channel' with a `for` loop --
  only List, Set, Map, Range, Str, Bytes, Channel, and Iterator implement iteration
```

One line contradicting itself — it names Channel as iterable while refusing a Channel — because
`type_to_str` had no arm either and rendered the typevar's bare name.

**Why it gates Stage 3.** Measured on the `tydiv` channel, these four are the cells where the
flat universe *appears* strictly more informative than the tid:

```
var=cl tid=? flat=Fn(int64_t(*)(const blink_closure*, int64_t))
var=ch tid=? flat=Channel[Int]
var=h  tid=? flat=Handle[Int]
var=it tid=? flat=Void
```

Stage 3 flips authority onto the tid and Stage 4 deletes the flat fields. At these sites there
would be **nothing to read**, so the divergence counter could never reach 0. Hence direction
(a), construct — not direction (b), delete the variants and let codegen keep a private universe,
which would make "the tid is the single authority" false by construction.

**"Appears", because that `Int` is a fabrication — found while starting `e0wmt6`, and it
strengthens the case rather than weakening it.** `src/codegen_stmt.bl:3508` reads
`get_var_channel_inner(val_str)` and, on `-1`, falls back to `set_var_channel(name, CT_INT)`;
`set_var_handle(name, CT_INT)` sits directly above it. So `flat=Channel[Int]` is not information
recovered from the program, it is the `sv_tp` erasure factory guessing — and the guess is right
across the whole corpus only because every Channel in `tests/` happens to carry `Int`. It is
also a live silent miscompile (br `hgd2az`): `let ch: Channel[Str] = Channel(4)` +
`for v in ch` prints `got 94225742992982`, because the receive seam emits
`int64_t v = (int64_t)(intptr_t)__chrecv_0` whatever the element is, and a `Channel[Float]`
fails in the C compiler rather than with a Blink diagnostic. Post-vag3wc the *tid* for the
annotated form is correct while the flat field is a fabricated `Int`, which is the collapse's
thesis stated as a bug: 429 divergence cells and a green 624-file suite all agreed with a lie.

The four did not land the same way, and that is the substance of the ticket:

- **`Channel` and `Handle` — CONSTRUCTED.** `make_channel_type` / `make_handle_type`, shaped
  exactly like `make_set_type` (one inner, name = the type's own name), plus `resolve_type_ann`
  arms, plus `type_to_str` / `tc_tid_child_count` / `tc_tid_child` arms. Both have unambiguous
  spec text — `sections/04_effects.md:1711` documents `async.spawn -> Handle[T]` and `.await` as
  a method on `Handle[T]`.
- **`Closure` — DELETED.** `TyKind.Fn` is already constructed (`make_fn_type`), a closure's
  declared type is spelled `Fn(..) -> T`, and `tk_to_ct` collapsed *both* to `CT_VOID`. The
  variant represented nothing Fn does not. A deletion is unobservable at runtime, so the
  evidence is compile-time: `tests/test_tc_tid_structural_accessors.bl` holds a second,
  independent enumeration of `TyKind` that fails to **compile** if a variant appears or
  disappears without that file being updated. It did, and was updated.
- **`Iterator` — DEFERRED to br `qzdz2e`, and stays unconstructed.** Not a representation
  problem; a spec one, and constructing it would have been a user-visible regression.

**The Iterator blocker, in full, because it is the one genuinely undecided thing here.**
`Iterator[T]` is registered *twice*: as a builtin **trait** (`tc_trait_names.push("Iterator")`
with arity 1; `sections/03c_protocols.md` defines `trait Iterator[T]` with
`map/filter/take/skip/zip/enumerate/chain/flat_map` all returning `Iterator[..]`, plus
`impl IntoIterator[T] for List[T]`), and as a concrete builtin **type** (`is_primitive_type`
claims the name, codegen has `CT_ITERATOR`, and `blink llms --topic "List[T] Methods"`
documents `.take/.skip/.chain/.flat_map -> Iterator[T]` as a return type). Typecheck's own
adapter table agrees with neither doc:

```blink
let a = [1, 2, 3]
let x: Bool = a.take(2)   # declared type Bool but got List[Int]   <- docs say Iterator[Int]
let z: Bool = a.skip(1)   # declared type Bool but got List[Int]   <- docs say Iterator[Int]
let y: Bool = a.chain(a)  # NO ERROR AT ALL — inferred Unknown
```

`types_compatible`'s container family requires `ka == kb`, so a *constructed* `Iterator[Int]`
annotation rejects every initializer that exists today. The doc-conformant
`let it: Iterator[Int] = a.take(2)` compiles right now **only** because the annotation degrades
to a typevar that unifies with the `List[Int]` typecheck actually infers. Constructing the kind
turns that program into a hard error. Deciding whether `Iterator[T]` is a trait, a concrete lazy
carrier, or a trait whose sole implementor is the carrier — and then aligning the adapter return
types with the answer — is user-visible and belongs to a panel, not to this ticket. Until it
lands, `tid=? flat=Iterator[Int]` remains a **live Stage 3 divergence site with a named owner**,
which is the honest state: 3 of 4 variants resolved, the 4th tracked.

`tests/test_vag3wc_channel_handle_iterator_tids.bl`: 10 rows, red before / green after. Half A
pins the representation with three *different* inner types on purpose (`Channel[Str]`,
`Handle[Bool]`, `Iterator[Int]`) — a shared `Int` would let a constructor that ignores its
argument and returns a cached entry pass every row. Kind is rendered through a **local**
`kind_str` match, not typecheck's `type_kind_name`: a test that renders the kind through the
function it is checking passes even when both sides are wrong about the same variant. Half B
pins the consequence — annotated channel for-loop 0 `NotIterable`, unannotated control 0 (the
row that makes it a bug report and not a preference), and `for x in 5` still **1**, because
widening iterability by kind must not swallow a real error. Half C runs the programs: annotated
channel sums to 7, annotated handle awaits 42. Two rows are deliberately shaped for the
deferral: the Iterator structural row **pins the current wrong answer** (`Typevar`, 0 children)
with a pointer to `qzdz2e`, so the fix breaks the row rather than sliding in silently; and the
last row is the **regression guard** asserting the documented
`let it: Iterator[Int] = a.take(2)` keeps compiling and running, so whichever way `qzdz2e`
lands, that program's status is a recorded decision.

One byproduct bug, found while writing the runtime rows and worth more than the ticket that
found it: **svsag8** — a closure with no declared return type is emitted as C `void`
(`static void __closure_0(const blink_closure* __self, int64_t x)`), silently discarding its
tail value; the caller casts to `int64_t(*)(...)` and reads whatever is in RAX. It hits the
**documented** form `.map(fn(x) { x * 2 })`, and `let f = fn(x: Int) { x * 10 }; f(2)`
interpolates as `<value>`. Distinct from `s663bm` (RAX:RDX truncation) and `nz7drz`.

**Divergence: corpus-wide delta exactly 0, and that is the expected result, not a miss.** On a
shared basis (baseline `sweep_mono_ss_final` vs the post-fix sweep, both excluding the one new
test root) every number is identical: 872 summary lines, 4888 diverge rows, 429 cells,
agree 344457, missing 40. The reason is visible in the rows themselves — **every**
`flat=Channel[Int]` / `flat=Handle[Int]` cell in the corpus comes from an *unannotated* let
(`tests/test_channel_param.bl:18` `let a = Channel(10)`, `tests/test_async_cancel.bl:30`
`let ch2 = Channel(20)`, `:32` `let a = async.spawn(...)`), and an unannotated let never touches
`resolve_type_ann`. What this ticket fixed is the ANNOTATION path; the INFERENCE path is
`e0wmt6`. The corpus sweep therefore cannot show the fix, which is precisely
`feedback_corpus_sweep_is_not_coverage`: **a zero-delta sweep is an unexercised tap, so the
shape was constructed by hand**, all three forms in one file:

```
let ch: Channel[Int] = Channel(4)   # annotated   -> no diverge row; counted in agree
let h:  Handle[Int]  = async.spawn(fn() { 1 })   # annotated   -> no diverge row
let cu = Channel(4)                 # unannotated -> the file's ONLY diverge row
[dbg:tydiv] bucket=diverge site=emit_let_binding.decl var=cu tid=? flat=Channel[Int]
[dbg:tydiv] summary emit_let_binding.decl agree=75 diverge=1 missing=0
```

The annotated pair moved from unrepresentable to agreeing; `cu` is `e0wmt6`'s. So the honest
accounting for Stage 3 is: this ticket removed the *representational* impossibility at these
cells — before it, no amount of inference work could have driven them to 0, because the tid had
nowhere to put the element — and `e0wmt6` now has something to construct and is unblocked. The
new test root contributes 106 diverge rows of its own purely by importing the compiler; on the
raw all-roots basis the sweep reads 5034 rows, which is the same
new-root-is-a-new-root bookkeeping recorded under sskpk8 above.

Also filed: the four-`tid=?` measurement in this section is why `e0wmt6` (`infer_type` has no
arm for `ChannelNew` / `AsyncSpawn` / `AwaitExpr` / `AsyncScope`) depended on this ticket — it
had nothing to construct until now.

### e0wmt6 — a statement-position `async.scope` body was never typechecked (CLOSED)

Opened as the four `bucket=missing` cells in this map — `tid=- flat=-`, the only bucket with no
fallback once Stage 4 deletes the flat fields. Reproducing it turned up something strictly worse
in the same code path, and the ticket split into two defects.

**Defect 1 — the walk gap. `async.scope { ... }` in STATEMENT position was not typechecked at
all.** Not "typed as Unknown": not visited.

```
fn main() {
    async.scope {
        let bad: Int = "not an int"
        io.println("{bad}")
    }
}
$ build/blink check hole.bl
ok: hole.bl                 <- no error
$ build/blink run hole.bl
not an int                  <- a Str lives in an Int-declared variable, and prints
```

The same body in INITIALIZER position (`let v = async.scope { ... }`) reported `TypeError`
correctly, so **position alone decided whether code was checked** — which is what makes this a
bug rather than a known limitation. The blast radius is every per-statement check in the
language, not just types.

Root cause, and the safeguard that was supposed to prevent it: a statement-position
`async.scope` arrives ExprStmt-wrapped and lands in `tc_check_body`'s ExprStmt arm
(`src/typecheck.bl:10131`), which re-dispatches into a body only for kinds the predicate claims:

```blink
if is_block_bearing(vk) || vk == NodeKind.MethodCall { tc_check_body(val) }
```

`infer_type` had no `AsyncScope` arm, so it returned Unknown without visiting the body, and
`is_block_bearing` (`src/ast.bl:187`) listed IfExpr / MatchExpr / WhileLoop / LoopExpr / ForIn /
WithBlock — **not AsyncScope**. That arm's own comment already says the predicate is "the single
source of truth for THIS re-dispatch so a future block-bearing kind cannot silently lose
statement-walking coverage here." The mechanism was right; `async.scope` was never registered in
it. The fix is one line plus the reason: a kind that bears a block answers 1.

**Defect 2 — publication.** Three `infer_type_uncached` arms: `AsyncScope` -> its block's tail
type; `AwaitExpr` -> the operand's `Handle` inner (reading the operand from `obj`, not `value` —
br `1b7ggq`); and `async.spawn` -> `make_handle_type(...)`. The spawn arm goes in the
**MethodCall** arm, because `NodeKind.AsyncSpawn` **has no producer anywhere in `src/` or
`lib/`** — `async.spawn(f)` parses as an ordinary `MethodCall{method: "spawn", obj: Ident
"async"}`. That is the same dead-variant shape as `TyKind.Closure` in vag3wc, and it cost real
time: four handled call sites read as coverage for a node kind that never exists (br `q6ytta` to
delete it). The arm is also gated on `nr_get_type("async") == TYPE_UNKNOWN` so a user variable
named `async` cannot be hijacked. `tc_closure_declared_ret` (`:2100`) answers `TYPE_VOID` for an
un-annotated closure, so the corpus form `async.spawn(fn() { compute(100) })` must infer the
body tail instead — annotation first, body second.

**This ticket needed vag3wc.** Until `TyKind.Handle` was constructible there was nothing to
answer `.await` or `spawn` with; `make_handle_type` did not exist.

| | pre (post-vag3wc) | post | delta |
|---|---|---|---|
| shape cells | 429 | 423 | **−6** |
| diverge occurrences | 4888 | 4799 | **−89** |
| agree occurrences | 344457 | 344688 | +231 |
| missing | 40 | **14** | **−26** |

Monolithic, both sides on the same 872-file basis (both new test roots excluded from both).
`missing` fell by 26, not the 4 the ticket was opened for: the walk gap was suppressing a tid for
*every* `let` in a statement-position scope, so fixing the walk published far more than the four
named cells. Eight `tid=?` cells were eliminated — the whole `Handle[...]` family
(`Handle[Int]`, `Handle[Str]`, `Handle[Bool]`, `Handle[Float]`, `Handle[List[Int]]`,
`Handle[Option[Int]]`, `Handle[Result[Int, Str]]`, `Handle[]`).

**The sskpk8 trap, reproduced exactly, and why the +231 is not noise.** Of the 18 files whose
counters moved beyond it, **26 files moved by precisely `+4 agree, 0 diverge, 0 missing`** — the
26 compiler-importing roots × the 4 new `let` statements this fix adds to `src/typecheck.bl`, all
four of which agree. 26 × 4 = 104 of the +231; the remaining +127 is real conversion in the 18
async-touching files. Per-file deltas are exactly uniform, as they were for sskpk8. New
*compiler* source adds new *sites* to every root.

**Two cells appeared, and both are the flat universe's errors becoming visible** — the reverse of
a regression:

```
tid=Handle[Point] flat=Handle[]      tests/test_async_spawn_types.bl  var=h
tid=Handle[Void]  flat=Handle[Int]   tests/test_async_codegen.bl      var=_h
```

The first: the flat pair cannot hold a struct element at all, so it spells the inner as *empty*.
The second: `let _h = async.spawn(fn() { do_nothing() })` in a test titled **"void spawn"**, where
`do_nothing()` is `fn do_nothing() { let _ = 1 }` — the tid's `Void` is correct and the flat's
`Int` is the fabricated default at `codegen_stmt.bl:3508`, the same fabrication documented under
vag3wc. These two cells are Stage 3 work with the answer already known.

`tests/test_e0wmt6_async_let_tids.bl`: 9 rows, **red 4/9 before, green 9/9 after**. Half A pins
the walk gap by diagnostic *count* (statement position reports 1, the initializer-position
control reports 1, a correct body reports 0 — the last row is what proves the widened walk does
not invent errors). Half B pins the four tids with three *different* result types (Str, Bool,
Int) so a spawn arm that ignored the closure and answered a fixed inner cannot pass. Half C runs
a real fork-join (sums to 42) and an `async.scope { 7 }`. `task regen` green; `task ci` green —
**625 test files, 625 passed, 0 failed, 0 build errors**.

**All 14 residual `missing` cells are now attributed**, and 13 of them are one newly-found bug:

- **br `pgc3d9` (filed, 13 cells)** — closure and handler bodies passed as **call arguments** are
  never typechecked, and it is **not async-specific**. `take(fn() { let bad: Int = "not an int" })`
  passes `check` *and* `run`, and prints `not an int`. Position does not rescue it here (unlike
  this ticket, initializer position is equally unchecked), and a `let`-bound closure *is* checked
  — so the body is walkable, it is only unwalked as an argument. It also exposes a **check/run
  divergence**: a `.map` closure body is re-walked by a later mono pass, so `run` reports the
  `TypeError` that `check` misses, i.e. `blink check` is unsound relative to `blink run`. Cells:
  `err_text` ×2 (`src/cli.bl:2189`, `src/build_stdlib.bl` — our own source), `i` ×1
  (`test_async_channels.bl`), `x` ×10 (`tests/fmt/*_handler_*`, the `handler MyEff { ... }`
  argument form).
- **br `twq9kz` (1 cell)** — `copy_list_compound_elem.src` in `test_yvq32w`, unrelated and
  already tracked.

**ChannelNew deliberately excluded → br `w3v2e6`** (blocked on `hgd2az`). It reads `tid=?`
(diverge), not `missing`, so it was never one of this ticket's cells. `Channel(4)` names no
element anywhere in the expression: `Channel[Unknown]` would launder an unknown into a structured
type, and the correct `Channel[α]` makes every `let ch = Channel(4)` an `E0301` under the gqg3rk
boundary check until the element is bound from `.send`/`.recv`/`for-in`. It is an inference task,
not a publication one — and its codegen half (`hgd2az`, `Channel[T]` is int64-only) would turn a
newly-published element tid into a wider set of silent miscompiles.

### twq9kz — the three missing arms are dead by caller gating (CLOSED), and Stage 3's one-liner does not work as written

The last Stage 3 prerequisite. `copy_list_compound_elem` (`src/codegen_methods.bl:1083`) is this
plan's named archetype — 26 lines of hand case analysis to copy one variable's type to another,
with no `CT_SET` / `CT_LIST` / `CT_STRUCT` arm, three open 03p551 cells verbatim. The question was
whether those absences are a live hole or a theoretical one.

**They are unreachable, and not because the shapes do not occur — because every caller gates on
exactly the arms that exist.**

```
src/codegen_stmt.bl:3699     if expr_list_elem_type == CT_OPTION || CT_RESULT || CT_MAP
src/codegen_stmt.bl:9156     identical gate (the second copy of this block)
src/codegen_methods.bl:4354  if carrier != "" — and carrier comes from list_compound_carrier_tag
                             (src/codegen_expr.bl:165), which returns non-empty ONLY for
                             CT_OPTION and CT_RESULT
```

`compound_tag_ct` (`codegen_types.bl:7079`) likewise knows only `Option_` / `Result_` / `Map_`.
So no constructible source can reach the `else if` — "add three arms" would have been a **no-op
fix** on three tickets.

Constructed by hand rather than inferred from corpus silence, per
`feedback_corpus_sweep_is_not_coverage`: a `List[Set[Int]]` and a `List[List[Int]]` rebind emit
**no `copy_list_compound_elem` row at all**, while the `List[Option[Int]]` control emits one. The
tap is not broken; the function is not entered.

**The Stage 3 blocker.** All three reaching call sites report `bucket=missing`, and the `var=`
field says why:

```
bucket=missing site=copy_list_compound_elem.src var=blink_u_mk_opt() tid=- flat=-
bucket=missing site=copy_list_compound_elem.src var=blink_u_mk_res() tid=- flat=-
bucket=missing site=copy_list_compound_elem.src var=blink_u_mk_map() tid=- flat=-
```

`src` is not a Blink variable — it is `expr_result_str`, the **emitted C expression text** for the
producing call. `get_var_ty("blink_u_mk_opt()")` is `< 0` because nothing ever stamped a tid on a
key like that. So the plan's stated replacement —

```blink
set_var_ty(dst, get_var_ty(src))    // Stage 3, as written
```

— would copy `-1` and lose everything these three arms carry today. **Stage 3 must source the tid
from the producing call NODE's memoized tid, not from a var keyed on the emitted expression
string.** That is a real change to the sub-step, found before it was written rather than after it
broke the corpus.

One thing this does *not* prove, and the instrument is the reason to be careful: in the `missing`
branch `ty_div_trace` is called with a hardcoded `-1` for the flat argument
(`src/typecheck.bl:11330`), so the `flat=-` in a `missing` row is **not a measurement** and says
nothing about whether a backing `ScopeVar` exists. Only the `tid=-` half is real. Whether the
three live arms currently do useful work or are already no-ops at these sites is therefore still
open — but it does not change the Stage 3 conclusion, which rests on the missing tid alone.

`tests/test_twq9kz_list_compound_elem_rebind.bl`: **6 rows, green from the start** — a regression
net for a function about to be rewritten, not a bug fix, and recorded as such. Rows 1-3 pin the
three live arms through the unannotated `let g = mk_*()` rebind that reaches them (leaving them
unannotated is load-bearing: an annotation re-stamps the element independently and bypasses the
copy), and each pins *both* variants — `None` as well as `Some`, `Err` payload as well as `Ok` —
since an element erased to a boxed int64 still reads correctly on the happy arm. Rows 4-5 pin the
two gate-excluded shapes that work anyway, so Stage 3's unconditional copy must not regress them.
Row 6 pins the one tuple form that works. Verified against the instrument: rows 1-3 fire `.src`,
rows 4-6 fire nothing, `.no_arm` stays silent.

`task ci` green — **626 test files, 626 passed, 0 failed**; fmt 1472 passed.

**Bug found while constructing, filed not fixed: br `6g6g7t`.** A `List[(Int, Str)]` returned from
a function loses its tuple element, **silently**:

```
fn make_tups() -> List[(Int, Str)] { let l: List[(Int, Str)] = []; l.push((7, "seven")); l }
let first = make_tups().get(0).unwrap()
io.println("n={first.0} s={first.1}")     ->  n=<value> s=<value>
```

Emitted C degrades the element to the boxed-int64 default and the interpolation falls back to a
literal placeholder: `const int64_t first = _ounw_2.value;` then
`blink_str_format("n=%s s=%s", "<value>", "<value>")`. A typed use instead escapes as a **raw C
error** — `const void n = first._0;` → *request for member '_0' in something not a structure or
union*. Two controls locate it: a **local** list is fine, and an **annotated** rebind is fine
(row 6), so the receiver temp of a `List[(..)]`-returning call is where the tuple dies.

Its Set/List siblings fail **loudly** instead — `unresolved method '.len' on type Set[Int]`,
`... on type List[Int]` — codegen naming the receiver correctly and having nothing to dispatch,
i.e. family C / `tavvwj`. The tuple case is the same mechanism with a silent outcome, because a
tuple degrades to a scalar that `Display` will print as `<value>` rather than refuse. Expected to
be subsumed by Stage 3 — the diagnostics *spell* `Set[Int]` and `List[Int]` correctly, which is
direct evidence typecheck holds the right type at those nodes and only the flat pair cannot carry
it to the consumer.

**Stage 3's prerequisite list was empty at this point** — and then re-measuring the `missing`
bucket for the Stage 3 kickoff showed 14 cells still there, 13 of them one bug. See `pgc3d9`.

### pgc3d9 — closure and handler bodies in argument position were never typechecked (CLOSED)

The `missing` bucket is the one with no fallback once Stage 4 deletes the flat fields, so it is
the bucket that decides whether Stage 3 can exit. After `e0wmt6` it still held **14** cells.
**Thirteen were a single typecheck walk bug** with the same shape as `e0wmt6`: a body that is
never visited, so nothing publishes a tid for anything inside it.

Doing it before Stage 3 rather than during was deliberate. Stage 3 flips the tid to authoritative;
if a walk-widening rides along with the flip, a new `missing` cell cannot be attributed to either
change. Fixed on the green tree first, against a known baseline.

**Three defects, one missing dispatch each, all in `tc_check_body`.**

| | shape | why it was unwalked |
|---|---|---|
| D1 | closure argument to a plain `Call` — `take(fn() { ... })` | no `Call` arm at all (silent `let _skip = 0` fallthrough), *and* the ExprStmt arm re-dispatched only for `is_block_bearing(vk) \|\| vk == MethodCall` — dropped twice over, in both statement and initializer position |
| D2 | closure argument to a **non-List** `MethodCall` — `async.spawn(fn() { ... })` | the arm `return`ed after its List branch, under the comment *"Only List has closure-taking HOFs"* |
| D3 | `handler` method bodies, in **every** position | no `HandlerExpr` arm at all |

D2's comment is the instructive one. It is true of the **stdlib** and false of the **language**:
any `fn`-typed param takes a closure, and `async.spawn` is a MethodCall on a receiver that is not
a List — the shape in our own `src/cli.bl`.

D3 is wider than the ticket recorded. It was filed as argument-position; in fact a handler as a
call argument, written inline in a `with`, and bound to a `let` were all equally unchecked.
`tc_check_body`'s WithBlock arm *already routed* an inline handler in — the route existed and
landed on the fallthrough. **The arm was missing, not the route.** Worth stating because "add the
route" would have been a no-op fix, the same trap as `twq9kz`'s "add three arms".

**Fix.** Two new functions in `src/typecheck.bl`:

- `tc_check_handler_method(m)` — the third entry point into a body that is its own fn context.
  A handler method is an ordinary `parse_fn_def()` FnDef living in a HandlerExpr's `methods`
  sublist rather than the program's, so the top-level `tc_check_fn` walk never reaches it and
  `lookup_fnsig` has no entry under its bare name. Mirrors `tc_check_fn` with the fnsig lookup
  replaced by `tc_closure_declared_ret(m)`, which reads only `node_type_ann` — set by the same
  `parse_type_annotation()` a closure's is — so it resolves the return with no closure-specific
  behavior, including the generic-instance re-intern a hand-rolled `resolve_type_ann` would drop.
- `tc_check_callable_arg_bodies(args_sl, skip_idx)` — walks `Closure` / `HandlerExpr` arguments,
  descending through `NamedArg` so a labelled closure argument is not mistaken for a non-closure.

Wired at four points: a new `HandlerExpr` arm, a new `Call` arm, the `MethodCall` arm after its
List branch, and `NodeKind.Call` added to the ExprStmt re-dispatch.

`skip_idx` is load-bearing, not defensive. The List-HOF path already walks arg 0 (arg 1 for
`fold`) with the element/accumulator type bound, which is strictly better than the generic walk
can do for an *unannotated* param; without the skip every `.map` / `.filter` / `.fold` closure in
the corpus grows a duplicate diagnostic. Two test rows assert the count is exactly **1**.

**One correction to the ticket.** Its MVCE 3 claimed `blink check` misses a `.map` closure's
TypeError that `blink run` catches — i.e. that `check` is *unsound relative to* `run`. It is not.
`check` reports it for both `.map` and `.filter`; the original reading came from output piped
through `| head -6`, which truncated exactly above the error line. List HOFs were never part of
this bug. MVCEs 1, 2 and 4 reproduce verbatim and stand.

**Second bug, pre-existing, exposed by the widened walk.** Walking closure arguments broke
`tests/test_for_each_skip_stops.bl` with `error[SkipOutsideTest]`. `tc_in_test_body` was answering
two questions that want **opposite** answers inside a closure:

| flag | question | inside a closure |
|---|---|---|
| `tc_in_test_body` | does `?` elaborate against the test block's implicit `Result[Void, TestError]`? | **no** — a closure gates `?` against its own declared return (spec §3c.2), which is why the closure walkers reset it |
| `tc_in_test_lexical` | is this code lexically inside a `test { }` block? | **yes** — and the test-only symbol fences (E0827 `skip`, E0833 `assert_panics`) are the readers that mean this |

Both fences read the elaboration flag. Split; the fences now read the lexical half, which
`tc_check_test_block` sets and the closure/handler walkers never reset. **Not introduced by
pgc3d9** — `skip()` inside a *List-HOF* closure in a test was already wrongly fenced, on a path
this ticket never touched, verified directly. Two places already documented the intended behavior
against the code: `tc_fence_test_only_symbol`'s comment (*"and inside closures lexically within
it — testing.for_each's case body relies on this"*) and the header of
`tests/test_e0833_assert_panics_outside_test.bl` (*"because tc_in_test_body stays set through such
closures"*). It did not stay set; the split is what makes both statements true.
`tc_in_test_lexical` joins its sibling in `tests/test_reset_staleness.bl`'s allowlist.

**Measured.** Monolithic sweep, `tests/ examples/ src/`, on a strictly shared 873-root basis with
both post-baseline test roots excluded:

| | before | after |
|---|---|---|
| `missing` | 14 | **1** |
| `diverge` | 5008 | 5008 |
| `agree` | 362979 | 363457 |
| shape cells | 423 | 421 |

All 13 pgc3d9 cells gone — 10 handler `x` in `tests/fmt/*_handler_*`, 1 `i` in
`tests/test_async_channels.bl`, 2 `err_text` in `src/cli.bl` + `src/build_stdlib.bl`. Diverge
unchanged, so no new disagreements were introduced; `agree` up 478 because the newly-walked
bodies now publish tids.

The single surviving `missing` row is `copy_list_compound_elem.src` — `twq9kz`, which Stage 3
replaces outright. **So the counter's no-fallback bucket is no longer blocked by a typecheck walk
bug, and Stage 3's exit criterion is reachable.**

`task regen` passed on the first attempt after the walk widened: the compiler's own
previously-unwalked bodies, `src/cli.bl`'s `async.spawn` closure included, held no latent type
errors. Test: `tests/test_pgc3d9_closure_arg_body_walk.bl`, 18 rows, red 9/15 before the fix —
all three defects in every position, both dedup guards, an all-correct program asserting 0
invented errors, the `skip`-in-closure / `skip`-in-helper pair, a *"`?` still gates against the
closure's own return"* row that fails if the flag were merely un-reset instead of split, two
tid-publication rows (the property Stage 3 needs), and two runtime rows.

### nz7drz — a closure literal had no type at all (CLOSED)

The largest single family-A root cause, and two defects rather than one. The ticket named the
first; the second is what actually produced its reported symptom.

**D1 — typecheck constructed no `Fn` type on either path.** `infer_type`'s Closure arm was a
literal `return TYPE_UNKNOWN`, and `resolve_type_ann` had no `Fn` arm, so an *annotated*
`fn(Int) -> Str` fell through to `make_typevar("Fn")`. This is the `vag3wc` shape exactly:
`make_fn_type` and the `TyKind.Fn` arms in `tc_tid_child_count` / `tc_tid_child` already
existed and nothing constructed them. A bare typevar unifies with anything, so the annotation
path was also unsound — `let bad: fn(Int) -> Int = 5` typechecked clean, and is a `TypeError`
now. An omitted `-> T` resolves to `TYPE_VOID`, not `TYPE_UNKNOWN`, matching
`tc_closure_declared_ret` and the named-fn default.

**D2 — codegen lost a closure's signature across a rebind.** `let g = c` then `g(21)`:

```
$ build/blink check   ok
$ build/blink run     error[UndefinedFunction]: undefined function 'g' called in 'main'
```

A real check-passes/run-fails divergence (the one the ticket description claimed was not).
`emit_expr` clears `expr_closure_sig` on entry and only ever *set* it from
`cg_expect_fn_value_sig`, an argument-position hint — so an Ident RHS propagated nothing,
`set_var_closure` stamped `""`, and the call fell past the closure-variable path into the
`UndefinedFunction` backstop. One restore-on-read block in the Ident arm, the same shape
`CT_ITERATOR` already had beside it. Annotating did not rescue it; direct calls and passing
through an `fn`-typed param already worked, so the spec question was settled
(`sections/02_syntax.md:1382`, `:1264`) and the fix was to make it work, not to reject it.

**Measurement** (tydiv, monolithic, shared exclusion basis). The Stage 3 kickoff figure "62 of
82" mixed units — 62 counted distinct `tid=?` *(var, file) pairs* grouped by initializer callee,
not cells:

| | before | after | |
|---|---:|---:|---:|
| family A (`tid=?`) cells | 84 | 61 | −23 |
| family A rows | 1323 | 1224 | −99 |
| `Fn`-flat `tid=?` cells | 16 | 2 | −14 |
| `Fn`-flat `tid=?` rows | 88 | 5 | −83 |
| total cells | 423 | 421 | −2 |
| agree | 362979 | 363711 | +732 |
| diverge rows | 5008 | 5003 | −5 |
| missing | 14 | 1 | −13 |

*(**Basis: the intersection of the two sweeps' file sets** — see the master table under
`3c4g71` below, which is where every figure in this section now comes from. These numbers were
published twice before and wrong both times, from the same mistake made two ways: first
`372979 → 382138` / `421 → 424` with the new test root excluded from only ONE side, then
`372712 → 372974` / `424 → 424` with it excluded from both sides but nothing else. Excluding
"the new test roots" is not enough. Sweeps taken weeks apart differ by **every** file added in
between, and any one of those that links the compiler contributes ~9000 `agree` rows by itself
— which is the entire ~9700 gap between the second attempt's `before` and the real one.
Intersecting the file sets is the only basis that cannot drift, and `scratchpad/cells.sh` now
takes that allow-list as a required argument so the shortcut is no longer reachable. The
conclusion below is unaffected in direction and slightly stronger in size: 2 cells, not 0.)*

21 family-A cells retired, not 14: the Call arm's `TyKind.Fn` branch (`typecheck.bl:8552`) was
dead code until a closure had a structured tid, and making it live means `let y = c(...)` gets
the closure's *return* tid too — which retired the residual `tid=? flat=Float` and five
`tid=? flat=Tuple2_*` cells as knock-on.

The **2 residual `Fn` cells are not this ticket** — they are `bfq7nf`, a separate and more general
hole: a block whose tail is a bare **Ident bound inside that block** infers nothing. The corpus
spelling is `let g = with arena { let h = fn(..) {..}  h }`
(`test_with_arena_closure_tail.bl:50`, `test_arena_promote_nested.bl:179/195/210/225`), which is
what first made this look like a `with arena` cause. It is not. Two probes settle it:

| probe | result |
|---|---|
| `let g = with arena { fn(x: Int) -> Int { x*2 } }` — literal tail | `tid=Fn(Int) -> Int` ✓ |
| `let g = { let h = 5  h }` — Ident tail, no arena, not a closure | `tid=? flat=Int` ✗ |

`infer_type` already has a `WithBlock` arm (`src/typecheck.bl:9507`), so nothing is missing there;
the tail type propagates for every shape except a bare Ident. The Ident arm resolves through
`nr_get_type(name)`, and the block's name-resolution scope is not live when the enclosing `let`'s
initializer is inferred. The closure fix is complete everywhere it is not composed with `bfq7nf`.

**Why the counter did not drop (424 → 424 cells), stated honestly.** The 14 retired cells did not
become `agree`; they changed *spelling* from `tid=?` to `tid=Fn(Int) -> Int` and stayed in
`diverge`, because `ty_tp_same_shape` rejects `TyKind.Fn` up front — `tk_to_ct` maps it to
`CT_VOID` and the `ct == CT_VOID && k != TyKind.Void` guard is deliberate (a kind the flat
universe provably cannot describe must not report agreement). A `Fn` ↔ `CT_CLOSURE` bridge needs
a tid → C-signature speller, because the flat side holds nothing structural to compare against —
only a rendered C signature string. That speller is Stage 3's `c_type_from_tid`; writing a second
one into typecheck to move a counter would be the drift this plan exists to undo. **Deferred to
Stage 3, where the same speller closes the cells and the comparator together.**

The 17 `Fn` rows are verified correct by hand against the flat C spelling beside them, which is
the evidence the comparator cannot yet give:

```
tid=Fn(Int, Int) -> Int              flat=Fn(int64_t(*)(const blink_closure*, int64_t, int64_t))
tid=Fn(Str, Int) -> Result[Int, Str] flat=Fn(blink_Result_int_str(*)(…, const char*, int64_t))
tid=Fn(Request, Str) -> Response     flat=Fn(blink_std_http_types_Response(*)(…, Request, const char*))
tid=Fn(Int) -> Bool                  flat=Fn(int(*)(const blink_closure*, int64_t))
```

The last row is the Bool-is-C-`int` case, which also rules out an `int64_t`-shaped guess.

**Two existing rows updated, not deleted.** `an un-annotated closure's own Map() tail fails
closed with I0001` (duplicated in `test_i0001_unsolved_typevar_at_codegen.bl` and
`test_farq9f_declared_container_ret_pins_ctor.bl`) no longer reaches codegen: an omitted `-> T`
is a Void return now, so typecheck rejects `c()` in a `Map`-returning tail with the ordinary
`error[TypeError]: return value type Void does not match function 'a' return type Map[Int, Str]`
— byte-identical to what `fn c() { Map() }` has always produced. An ICE backstop replaced by the
correct upstream diagnostic is the outcome I0001 exists to enable. Both rows moved to the closure
shape that still gets past the front end (`fn a[K,V]() { let c = fn() -> Map[K,V] { Map() } }`,
verified to still raise I0001), and the retired spelling is pinned as a *TypeError-not-ICE* row
so it can never regress into an ICE or a silent `kops_str` guess.

**Spun out.** `r398vj` — a closure *call*'s `List`/`Map`/`Set` return is lost, because
`codegen_expr.bl:5232` recovers the return type by re-parsing the emitted C signature string;
`Int`/`Str`/`Option` survive only because `closure_ret_tag_is_recognized` happens to decode their
C spelling. Pre-existing and independent: `receiver_type_name_for_diag` already read the tid, so
this change only improved the diagnostic's type *name*. It is a Stage 3 cell of the purest kind —
the call node's own memoized tid already holds the answer.

`3ejrqa`'s stated precondition is now met, and noted on that ticket: a closure literal's node tid
carries the *instance* return, measured on its own MVCE as `Fn(Int) -> Box[Int]`, so
`tc_resolve_tparam_tid`'s `Fn` arm can read `tc_tid_child` instead of parsing an annotation name.

Test: `tests/test_nz7drz_closure_fn_tid.bl`, 15 rows — 7 D1 rows red before (4 more D2 rows were
outright build errors), all green after. `task ci` green.

### bfq7nf — a block's tail could not name a binding of that block (CLOSED)

**The first Stage 3 root cause to move the counter itself.** `let x = { let h = 5  h }` gave the
binding no tid at all, for any type, in any block. The two cells `nz7drz` left were this, and so
were twelve more it had nothing to do with.

**Cause, and it is an ORDERING one, not a missing arm.** `tc_check_body`'s `LetBinding` arm infers
the initializer at `typecheck.bl:9999` and only *then* walks it at `:10001`. `infer_type`'s Block
arm resolves the tail, the tail is an `Ident`, and the `Ident` arm resolves through
`nr_get_type` — but the block's own nr frame is pushed by the walk that has not run yet. So the
name misses, the tail is `TYPE_UNKNOWN`, and `TYPE_UNKNOWN` unifies with anything. Two checks went
silent as a result:

| shape | before | after |
|---|---|---|
| `let x: Str = { let h = 5  h }` | accepted | `error[TypeError]` |
| `let g = { let h = fn(a: Int) -> Int {..}  h }` then `g(1,2,3)` | accepted | `error[TypeError]` |

An `Ident` tail naming an **outer** binding always worked — that frame is live — which is what
localizes the defect to block-*local* names and rules out "blocks don't propagate their tail".
`infer_type` already has `WithBlock` and `AsyncScope` arms; nothing was missing there.

**Fix: read the tid, do not re-derive it.** The walk at `:10001` *does* have the frame, and its
`ExprStmt` arm memoizes the tail with the right answer — the tid existed, it was merely written one
step late. `tc_block_tail_memo` reads it, and the `LetBinding` arm consults it right after the walk
and before the declared/inferred compare. Recovery only: it can never overwrite an answer
`infer_type` already gave, so no shape that resolved before takes a different tid.

Re-inferring the block instead would have been one line shorter and wrong — `infer_type` REPORTS as
a side effect (its `IfExpr` arm emits "if branches have incompatible types", the hazard
`typecheck.bl:9955` already names), so recovering the tail that way double-reports every such
tail. Duplicating nr's scope machinery inside `infer_type` was the other candidate and is worse
still: `nr_pop_scope` carries the E0301 region-boundary check, so a speculative frame either
fires it twice or needs `tc_boundary_check_active` suppressed around it.

**Measurement** — see the master table under `3c4g71` below; the `after bfq7nf` column is this
ticket. Headline: **423 → 409 cells**, family A **84 → 47**, and the last `Fn`-flat `tid=?` cell
gone (2 → 0), which is what closes out `nz7drz`'s deferred residual.

14 family-A cells retired for a fix aimed at 2, because the recovery is keyed on the *initializer
being block-bearing*, not on the tail being a closure: `flat=CmgPoint`, `flat=Pair`,
`flat=List[Char]`, `flat=List[I32]`, and seven `flat=Map[..]` cells went with them.

**Two NEW `diverge` cells, and the flat side is the wrong one.** Both from
`tests/test_arena_promote_nested.bl`:

```
site=emit_let_binding.decl var=m tid=Map[Bool, Int] flat=Map[Int, Int]
site=emit_let_binding.decl var=m tid=Map[Int, I32]  flat=Map[Int, Int]
```

The source declares `let mut m: Map[Bool, Int]` (`:56`) and `let mut m: Map[Int, I32]` (`:140`).
The tid spells both exactly; the flat universe widened the `Bool` key and the `I32` value to `Int`.
These were `tid=?` cells before, so nothing regressed — giving the tid an answer **revealed** two
more instances of the flat universe's width erasure, which is the instrument working. Note the
asymmetry it exposes: an `I32`/`I8`/`U8`/`Char` **key** survives the flat encoding (those cells now
agree) while an `I32` **value** does not. Stage 3's authority flip closes both for free.

Test: `tests/test_bfq7nf_block_ident_tail_tid.bl`, 14 rows — 6 red before, all green after, with
the 8 controls (literal tail, outer-scope tail, and the runtime answers through the arena promote
path) green throughout to pin that the fix adds a tid without moving one byte of behavior.
`task regen` + `task ci` green.

### The instrument now names its own site (`at=module:line`)

Between `bfq7nf` and `3c4g71` the trace gained a field, because grep-based attribution had run
out of resolution and was **producing wrong answers, not just vague ones**.

A sweep row carried `var=` and the `file=` the harness appended — and `file=` is the **entry**
file, not the declaring one. Every test compile re-emits the whole stdlib, so one
`lib/std/libc.bl` binding is blamed on ~90 different entry files at once. Ranking causes by
grepping `let <var> =` out of the blamed file therefore mis-attributed most of the corpus: **501
of 767 `(var, flat, file)` triples had no such line in that file at all**, and many that did
matched a same-named variable in an unrelated module — short names (`r`, `p`, `v`, `b`, `inner`)
collide freely across 90 modules.

`sv_ty_or_flat` now delegates to `sv_ty_or_flat_at(name, site, node)`, and `codegen_stmt.bl`'s
`emit_let_binding.decl` tap threads the `let` node so `ty_div_trace` can append
`at={node_source_module(node)}:{node_line(node)}`. The field is **last on the line** on purpose:
a flat spelling can contain spaces (`Fn(int64_t(*)(const blink_closure*, int64_t))`), so every
sweep script strips fixed trailing tokens to reach the cell, and both `at=` and the harness's
`file=` are suffixes — `sed 's| at=[^ ]* file=[^ ]*$||'` stays sufficient.
`copy_list_compound_elem`'s two taps keep the node-less wrapper; that function is handed only
`Str src, Str dst` and has no node to thread.

Two by-products, neither part of this work:

- **`8wk3xg` (filed).** A local `let at = ...` in `ty_div_trace` does not resolve to itself —
  name resolution reaches `src/parser.bl:585`'s **private** `fn at(kind: TokenKind)` and reports
  `error[ImportNotSelected]: 'at' is not in scope — add it to the import list`, i.e. it suggests
  importing a private item to fix a local binding. Shadowing runs the wrong way. Not
  interpolation-specific (a plain `at.concat("")` fails identically). Worked around by naming the
  local `at_str`; the comment there says to rename it back when `8wk3xg` closes.
- Recorded in `8wk3xg`'s description as explicitly separate: a `@module helper` line in a
  same-package module file makes the **entry** file fail to parse with
  `error[UnexpectedToken]: unexpected token at top level: IDENT`, pointed at the entry's own
  `import` line — wrong file, wrong span.

`at=` is what turned the remaining family-A backlog from 364 unattributable rows into a ranked
list of causes, which is how `3c4g71` was found.

### 3c4g71 — a match arm body could not name its own pattern binding (CLOSED)

`bfq7nf` one `NodeKind` over, and the same root cause: `tc_check_body`'s `LetBinding` arm infers
the initializer before walking it, so a value that names a binding **the construct itself
introduces** is inferred with that frame unpushed. For `bfq7nf` the construct was a block and the
binding a `let`; here it is a `match` arm and the binding comes from the arm's **pattern**.

What made it look like a different bug is the merge in `infer_type`'s `MatchExpr` arm:

```blink
if merged == TYPE_UNKNOWN { merged = arm_t }
```

so the match keeps its type whenever **some** sibling arm dodges the defect. Only a match where
no arm dodges loses it — which is why every compiler-source instance is spelled with a diverging
arm. A `None => return 0` body is `TYPE_UNKNOWN` too (`infer_type_uncached` has no
`NodeKind.Return` arm and falls through), so it cannot cover for the pattern-bound arm beside it.
Two probes separate the axes:

| probe | result |
|---|---|
| `match sh { Circle(a) => a  Square(a) => a }` — every arm pattern-bound | `tid=? flat=Int` ✗ |
| `match sh { Circle(a) => a  Square(_) => 0 }` — one literal arm covers | `tid=Int` ✓ |
| `match o { Some(v) => v  None => return 0 }` — diverging arm cannot cover | `tid=? flat=Int` ✗ |

**The diagnostic hole, and the `if` asymmetry that proves it is a bug.** `TYPE_UNKNOWN` unifies
with anything, so the declared-type compare went silent — while the `if` analogue was rejected
correctly all along, because its arm carries an explicit
`if then_t == TYPE_UNKNOWN { return else_t }` pair:

```blink
let a: Str = match o { Some(v) => v  None => return 0 }   // accepted, no error
let b: Str = if c { 5 } else { return 0 }                 // error[TypeError], correct
```

**Fix.** `tc_block_tail_memo` became `tc_scoped_value_memo(node, depth)` — recursive rather than a
loop, because a match fans out — and gained a `MatchExpr` case that merges the arm bodies' memos
through `type_merge`. Same principle as `bfq7nf`: the in-scope walk (`tc_check_body`'s `MatchExpr`
arm pushes the arm scope, binds the pattern, then walks the body) already memoized every arm body
with the right answer, so the tid exists and is merely written one step late. Read it; do not
re-derive it. Re-inferring is still not an option — `infer_type` REPORTS as a side effect.

A **diverging** arm body contributes nothing, skipped by kind (`Return`/`Break`/`Continue`) in the
new `tc_arm_body_value`. That is the bottom-type rule, not an omission, and it has to be explicit:
leaning on the `Return` node's memo happening to be `TYPE_UNKNOWN` would break silently the day
something memoizes it, and folding the `return`'s own operand in would type
`fn f(o: Option[Str]) -> Int { match o { Some(v) => v  None => return 0 } }` as the merge of `Str`
and `Int`.

**Measurement — the master table.** Every figure in this document's progress log now derives from
these sweeps, tallied on the **intersection of their file sets** (874 files; the 5 files that
do not appear in all of them are listed under the `nz7drz` correction note). `scratchpad/cells.sh`
takes that allow-list as a required argument.

| | before `nz7drz` | after `nz7drz` | after `bfq7nf` | after `3c4g71` | after `zs7khh` | after `2r96m9` | after `rbd0a4` | after `w13xgb` | after `jzvxav` | after `h3q81d` |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| **total cells** | 423 | 421 | 409 | 407 | 405 | 404 | 404 | 405 | 404 | **402** |
| family A (`tid=?`) cells | 84 | 61 | 47 | 45 | 35 | 34 | 34 | 33 | 32 | **28** |
| family A rows | 1323 | 1224 | 1190 | 1050 | 1015 | 661 | 504 | 327 | 310 | **261** |
| `Fn`-flat `tid=?` cells | 16 | 2 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | **0** |
| agree | 362979 | 363711 | 363924 | 364187 | 364289 | 364674 | 364831 | 364883 | 364934 | **365243** |
| diverge rows | 5008 | 5003 | 4976 | 4837 | 4828 | 4474 | 4317 | 4296 | 4279 | **4249** |
| missing | 14 | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 1 | **1** |

The `after jzvxav` column covers **two** fixes, `jzvxav` and `ya8qyf`, because they were measured in
one sweep; the attribution in those sections shows all 17 rows belong to `jzvxav`, so `ya8qyf` is
divergence-neutral **by inference, not by its own sweep**. Both are recorded that way on purpose:
`ya8qyf` is a diagnostic/escape fix, and this instrument only watches declaration sites.

The `w13xgb` column is the first one where **total cells go up**, by one, and it is progress — see
that section for the reading. Every figure in it is reproducible with
`scratchpad/tally_common.sh <sweep> common.lst`, which supersedes `tally.sh`: the older script took
*exclusion* roots, which the `cells.sh` note already records as the wrong basis.

**Cells move by 2 while rows move by 140, and that is the honest reading.** A cell is a
`(site, tid, flat)` shape triple, so the 17 retired *declaration sites* mostly shared their flat
spelling (`Int`, `Str`, `Person`, `Color`) with other still-open causes; the cell only clears when
the last site holding that spelling clears. Rows are the better progress signal for a
cause-by-cause phase, cells for Stage 3's exit gate. All 17 match-initialized family-A sites are
gone and **zero remain** — including the four in the compiler's own source
(`src/typecheck.bl:5362`, `:5415`, `:5456`, `src/symbol_index.bl:621`, every one the
`match m.get(k) { Some(v) => v  None => return ... }` shape).

Test: `tests/test_3c4g71_match_arm_pattern_binding_tid.bl`, 14 rows — 6 red before, all green
after. The 3 controls (the literal-arm cover, the `if` analogue, and closure-literal arms, which
need no scope because `nz7drz` reads the *signature* and never the body) and the 5 clean/run rows
were green throughout, pinning that the fix adds a tid without moving one runtime answer.
`task regen` + `task ci` green.

### `zs7khh` — a static `Type.from` / `Type.try_from` resolved no return type (CLOSED)

The first sub-mechanism out of the ranked list's top entry. `tc_mangle_impl_fnsig`
(`src/typecheck.bl:295`) keys From/TryFrom **source-typed**, `{Type}_{method}_{Src}`, because one
target can carry several source impls — `lib/std/int_conv.bl` declares `try_from` on `I8` from
`Int`, from `I32` and from `I16`, all three named `try_from` on `I8`. The static-call site tried
only the trait-qualified key (`I8_TryFrom_try_from`) and the bare key (`I8_try_from`). Neither can
name `I8_try_from_Int`, so every static From/TryFrom call fell through to `TYPE_UNKNOWN`. The
comment above that block asserted the opposite — *"From/TryFrom … keep the bare `{Type}_{method}`
key"* — which is the false premise that kept the hole open; it is corrected in place.

Codegen never had the hole. `codegen_methods.bl`'s static From/TryFrom dispatch spells `src` from
the **argument's** type, then goes through `find_from_impl` / `find_tryfrom_impl` +
`mangle_from_method`. The fix mirrors it: infer the single argument, spell it with `tc_type_str`,
look up the third key. A miss returns `TYPE_UNKNOWN` rather than falling through, because the
shared fall-through re-infers every argument and `infer_type` reports as a side effect.

Diagnostic consequence, now fixed: `let x: Str = I8.try_from(5)` compiled clean, because
`TYPE_UNKNOWN` unifies with anything.

**Two follow-on causes the fix exposed.** Both were hidden behind `tid=?`, so this is visibility
gained, not ground lost — and it is why 10 family-A cells retired while total cells moved only 2:

- Seven new cells `tid=Result[X, ConversionError]` vs `flat=Result[X, ]`. The flat side holds the
  Err *CT* but not the enum *name*. Family D, retired structurally by Stage 3's
  `c_type_from_tid` — deliberately **not** filed as a cell ticket, per the plan's non-goal.
- One new cell `tid=Self flat=ConfigError`. An impl method spelling `-> Self` registers the literal
  `Self` typevar as its fnsig return (`typecheck.bl:5103`). A typevar is as permissive as
  `TYPE_UNKNOWN`, so the declared-type compare stays disabled — the defect class did not change,
  only its spelling. Filed as **`3xhh59`**.

Test: `tests/test_zs7khh_static_from_tryfrom_ret_tid.bl`, 14 rows — 6 red before, all green after.
The source-selecting row (`I8.try_from(i32val)`) is the one that fails a fix picking "the first
`try_from` for `I8`". Controls green throughout: the bare-key `Duration.seconds(2)`, the builtin
`Bytes.new()`, and the `mjsbwm` shadowing gate (`let I8 = 42`). `task regen` + `task ci` green.

### `2r96m9` — two of three `Bytes` static intrinsics produced no type (CLOSED)

The second sub-mechanism out of the ranked list's top entry, and **the largest single row
reduction of the campaign so far: family-A rows 1015 → 661, −354 (−35%)**.

Codegen's `Bytes` static block (`codegen_methods.bl:2545`) dispatches three intrinsics — `new`,
`from_str`, `zeroed` — and **none is backed by a `.bl` function**, so no fnsig can answer for any
of them. The typecheck static branch mirrored exactly one, gated on the literal method name:

```blink
if method == "new" && is_builtin_fn(obj_name) != 0 && obj_is_value == 0 {
    return get_builtin_fn_ret(obj_name)
}
```

`get_builtin_fn_ret` is keyed on the **type name alone** and so cannot tell two constructors of one
type apart, which is exactly why `Bytes.new` was fine while `from_str` and `zeroed` fell through
every lookup to `TYPE_UNKNOWN`. Third instance of `project_is_intrinsic_method_must_match_handlers`
in this campaign: a typecheck mirror of a codegen intrinsic list, gated on a *name* rather than
enumerated against the list, silently omits whatever the list grows.

The fix is `tc_builtin_static_ret(tname, method)`, keyed on the type **and** the method. It is
strictly more permissive at the fall-through than the gate it replaces, which returned
`get_builtin_fn_ret`'s answer for `new` even when that answer was Unknown, ending resolution there.
Deliberately absent, each for its own reason: `Duration.*`, `Instant.from_epoch_secs` and
`Char.from_code_point` are real stdlib functions already answered by the bare `{Type}_{method}` key,
and `StringBuilder` keeps its own earlier block, which has to run *before* the receiver is inferred
so a same-spelled enum variant cannot shadow it into E0505. Probing every builtin static block
confirmed the hole is exactly these two methods.

| | after `zs7khh` | after `2r96m9` | delta |
|---|---:|---:|---:|
| family A rows | 1015 | **661** | **−354 (−35%)** |
| `tid=? flat=Bytes` rows | 201 | 12 | −189 |
| diverge rows | 4828 | 4474 | −354 |
| total cells | 405 | 404 | −1 |
| family A cells | 35 | 34 | −1 |

**Why one cell for 354 rows.** A cell is a `(site, tid, flat)` triple, and other producers still
leave `tid=? flat=Bytes` at `emit_let_binding.decl` (`std_net_tcp:128`, `lsp:50`). The 354 rows are
the three `Bytes.zeroed` sites in `lib/std/libc.bl` — `:143` (read), `:161` (recv), `:207`
(getentropy) — times the 55 roots that link libc, **plus their knock-on**: each buffer is fed
straight into `buf.with_ptr(fn(p) -> .. { .. })`, whose result was unknown only because its
receiver was (`libc:144`, `:162` as `Int`; `:208` as `I32`). So this retires most of the separate
ranked cause *"`buf.with_ptr`, ~6 sites"* as a by-product, and the one cell that cleared is
`tid=? flat=I32` at `libc:208` — the last site holding that spelling.

**The hole was masking a miscompile, not merely a missing type.** Found while writing the test:
`Bytes.to_str()` returns `Result[Str, Str]`, which has no `Display` impl, so interpolating it
unwrapped is an error. With the receiver untyped that check could not run, and the program compiled
and **printed the literal `<value>`** — a wrong answer reaching the user. Now
`error[MissingDisplayImpl]`, pinned by its own row. This is the second family-A cause shown to be
hiding a user-visible defect rather than only a divergence, and it is the strongest argument yet
that the family-A prerequisites are worth doing on their own terms.

Test: `tests/test_2r96m9_bytes_static_intrinsic_tid.bl`, 13 rows — 3 red before (the 2 intended
plus the miscompile), 13 green after. Argument type/arity checking for the `Bytes` statics was
deliberately **not** added: that is a new diagnostic surface and a separate decision. `task regen` +
`task ci` green.

### `rbd0a4` — `Str` and numeric intrinsics with no arm in the return dispatch (CLOSED)

The first cause taken from the 172-name audit below, and the first one whose **scope the ticket got
wrong**. The ticket named four methods as one hole. Probing split them three ways, and only the
first group was a missing return type:

1. **Real, working, and unnamed in typecheck** — the fix. `substr` on a `Str`; `to_string` on an
   `Int` and on a `Float` (`codegen_methods.bl:3879`, `:3884`); `to_float` on an `Int` (`:3777`);
   `to_int` on a `Float` (`:3782`). A **`Float` receiver had no block at all** in the dispatch —
   `to_int` was answered only inside the `Str` block — so `1.7.to_int()` resolved nothing although
   codegen had implemented it all along. `substr` shares the `substring` arm rather than getting a
   copy of it, because codegen dispatches both from **one** arm (`codegen_methods.bl:922` spells
   `"substring" || "substr"`) and two arms could drift.
2. **Does not exist at all** — `charAt`. It was the *only* mention of that spelling in the whole
   compiler: no codegen arm, no stdlib function, zero uses across `src/ lib/ tests/ examples/`. Its
   only effect was to suppress the one `UnknownMethod` warning a user would get before the hard
   `UnresolvedMethod` at codegen. The fix is to **remove it from the allow-list**, not to give it a
   return type — that list asserts a method *exists* (it also gates the resolution check at
   `typecheck.bl:388`), so a name with nothing behind it belongs out of it.
3. **Deferred** — `as_cstr` returns `CT_PTR` (`codegen_methods.bl:857`) and typecheck has no
   `TyKind.Ptr` variant at all. That is `w13xgb`, which has to add the variant first.

Deliberately **not** widened: `to_string` on a `Bool` or a sized int, and `to_float` on a `Str`.
Codegen implements none of the three, so answering them here would invent surface. Together with
`Int.to_str()` — which the allow-list affirms and codegen lacks — they are the inverse defect and
are filed separately as **`xfrd4j`**: the error lands at codegen, so `blink check` is untrustworthy
for them.

| | after `2r96m9` | after `rbd0a4` | delta |
|---|---:|---:|---:|
| family A rows | 661 | **504** | **−157 (−23.8%)** |
| `tid=? flat=Str` rows | 217 | 61 | −156 |
| `tid=? flat=Int` rows | 86 | 85 | −1 |
| diverge rows | 4474 | 4317 | −157 |
| total cells | 404 | 404 | **0** |
| family A cells | 34 | 34 | **0** |

The retired rows attribute to exactly nine source lines times the roots that link them: **147** are
the five `.substr()` let-bindings in the compiler's own source (`codegen_types:4647`, `:6663`,
`typecheck:7553`, `codegen_stmt:1804`, `:2116`), **6** are `lib/std/http_server.bl:229,230`
(`resp.status.to_string()` and `resp.body.len().to_string()`), and 4 are two small pairs in test
roots.

**Zero cells retired** — the first fix in the campaign to move rows without moving a single cell.
`tid=? flat=Str` at `emit_let_binding.decl` still has other producers, 61 rows of them, and what
remains there is now a **scattered tail rather than one cause**: a cross-module `List[Str]` element
(`symbol_index.si_file_path.get(i).unwrap()`), `List.join`, and `io.read_line()`. Each is already a
separate entry in the ranking below. This is the clearest case yet that rows are the honest progress
signal during the cause-by-cause phase and cells are Stage 3's exit gate, not a per-fix scorecard.

Test: `tests/test_rbd0a4_str_num_intrinsic_ret_tid.bl`, 16 rows — 6 red before, all green after. The
`charAt` row cannot use `compile_test_helpers.expect_warning`: that helper (like `expect_error`,
`expect_contains` and `expect_clean`) only **prints** a PASS/FAIL line and asserts nothing, so a row
built on it passes green either way. It uses `compile_and_capture` + `assert`. Controls green
throughout: `substring`, `char_at` (→ `Option[Char]`), `Str.to_int`, `parse_float`, `Int.to_i32` —
these catch a fix that reorders the receiver blocks or puts the new `Float` block ahead of the `Str`
one. `task regen` + `task ci` green.

### `w13xgb` — `Ptr[T]` was never a type typecheck could hold (CLOSED)

**The largest row reduction of the campaign: family-A rows 504 → 327, −177 (−35.1%).** And the
first cause whose real mechanism was *worse* than the ticket described. The ticket read as another
`rbd0a4` — three intrinsic names missing from the return dispatch. It was one step further down:
**`TyKind.Ptr` did not exist.** Typecheck only ever inspected `Ptr[T]` *syntactically*
(`PtrOutsideFFI`, `InvalidPtrType`, `is_valid_ptr_inner`), so `resolve_type_ann` fell through to
`make_typevar("Ptr")` — as permissive as `TYPE_UNKNOWN`, and permissive at the **receiver**, which
is why no method arm could have helped and why `as_cstr` had to be deferred out of `rbd0a4`.

**It was hiding a raw `cc` error, not a missing diagnostic.** This program passed typecheck:

```blink
let buf: Ptr[Pollfd] = scope.alloc_n(2)
let r: Ptr[Int] = buf
```

and failed as
`build/d.c:142: error: initialization of 'int64_t *' from incompatible pointer type 'blink_Pollfd *'`
— no Blink diagnostic, no source span, and a file path pointing into `build/`. Third family-A cause
proven to be masking a user-visible defect (after `dvzt90` and `2r96m9`), and the worst-presenting
of the three: `2r96m9` printed a wrong answer, this one hands the user the C compiler's output.

**Five regens, because five different things were absent.** Each is its own step per the bootstrap
protocol; the split is not ceremony — regen 1 is purely representational, regens 2-5 each change
behavior:

1. **The variant, unconstructible.** `TyKind.Ptr` + `make_ptr_type(pointee)` via
   `ty_intern_simple`, shaped like `make_handle_type` — **one inner = the pointee** — so
   `tc_tid_child`, `tc_tid_child_count`, the spellers and `tk_to_ct` reach it through arms they
   already had. Interned, so the two `Ptr[T]` mentions in a signature and at its call site are
   integer-equal. Arms added at `tk_name`, `type_to_str`, `tc_tid_tag_at` (both `TAGPOS_TOP` and
   `TAGPOS_INNER`), `tk_to_ct` (+ `CT_PTR` in typecheck's selective import), `tc_tid_child_count`,
   `tc_tid_child`, and `return false` in **both** seg-injectivity predicates — `Ptr` spells a bare
   `"Ptr"`/`"ptr"` and drops the pointee, so two pointees collide on one segment, non-injective for
   the same reason `List` and `Set` are.
2. **The lowering.** `if name == "Ptr"` in `resolve_type_ann`, recursing through `resolve_type_ann`
   for the pointee rather than reading it as a name, so `Ptr[Ptr[Void]]` nests. Nothing here
   re-validates the pointee: `check_ptr_in_type_ann` / `is_valid_ptr_inner` walk the annotation tree
   independently and must keep doing so — they are the only thing that sees a `Ptr` in a position
   that never reaches `resolve_type_ann`.
3. **`types_compatible`** — and *this*, not the variant or the lowering, is what closed the `cc`
   escape. With both tids finally correct the assignment still passed, because that function's
   `ka == kb` block recurses for `List`/`Option`/`Iterator`/`Set`, `Map`, `Result`, `Tuple` and
   `Struct`/`Enum` and then ends in a bare `return 1`. `Ptr[Int]` matched `Ptr[Pollfd]` on the
   fall-through. `Ptr[Void]` is deliberately **not** special-cased into a universal pointer: C
   converts `void*` implicitly both ways, so importing that rule would make every `Ptr` assignable
   to every other via one `Void` hop — the exact hole the arm closes. `tc_tid_same_type` was
   checked and is fully structural; only `types_compatible` had the hole.
4. **The `Ptr` receiver block** — and only the three methods where the spec and codegen agree, or
   where codegen is the sole authority *and* `lib/std` depends on it: `is_null() -> Bool`,
   `offset(Int) -> obj_t` (**pointee preserved** — pointer arithmetic returns the receiver's own
   tid, not its child), `to_str() -> Option[Str]`.
5. **`Str.as_cstr() -> Ptr[U8]`**, deferred here by `rbd0a4` because there was no `TyKind.Ptr` to
   name. `sections/07_trust_modules_metadata.md:221` and `codegen_methods.bl:857` agree on it, and
   its partner `.to_str(self: Ptr[U8]) -> Option[Str]` (`:222`) landed in regen 4, so the spec's
   documented round trip now types end to end.

**Deliberately out of scope, each recorded rather than dropped.** `.deref()` and `.addr()`: the spec
(`:217`, `:220`) says `Option[T]` and `Ptr[Ptr[T]]` while `codegen_methods.bl:4774-4835` implements
a bare `Int` for both, and `lib/std/libc.bl` depends on the bare form at five sites — an arm here
would have to pick a side, so **which side moves is `mwsy85`** (`type:spec`). `.read()`/`.write()`:
`5efs37` is the miscompile that has to be fixed before a return type means anything for them. The
`scope.alloc / alloc_n / cstr / take` surface: my own pre-session scope note claimed three regens
including this, and it was wrong — that surface needs a `TyKind` for the **ffi-scope object**, which
does not exist, so it is a different cause, filed as `ps5br9`.

| | after `rbd0a4` | after `w13xgb` | delta |
|---|---:|---:|---:|
| family A rows | 504 | **327** | **−177 (−35.1%)** |
| `tid=? flat=Ptr[Int]` rows | 176 | 5 | −171 |
| diverge rows | 4317 | 4296 | −21 |
| agree | 364831 | 364883 | +52 |
| total cells | 404 | **405** | **+1** |
| family A cells | 34 | 33 | −1 |

**The cell count went up by one and that is progress.** Two cells retired
(`tid=? flat=Bool`, `tid=Ptr flat=Ptr[Int]`) and three appeared — `tid=Ptr[Pollfd] flat=Ptr[Int]`
(230 rows), `tid=Ptr[U8] flat=Ptr[Int]` (3), `tid=Ptr[Void] flat=Ptr[Int]` (1). One **degenerate**
cell, where the tid rendered as the meaningless bare typevar `"Ptr"`, split into three **faithful**
ones, and the divergence **flipped sides**: the tid is now right and the *flat* side is the liar.
`sv_tp`'s `CT_PTR` arm fabricates `type_ptr(type_int())` whenever `inner1 < 0`
(`codegen_types.bl:1599`), so flat says `Ptr[Int]` for every pointer in the corpus. That
fabrication is **Stage 4 group 1** of the collapse plan — `sv_tp`, the erasure factory, is deleted
— not a new bug, and 232 rows is now a measured justification for that deletion rather than an
argument from the plan's thesis. **This is the first cause in the campaign whose residual
divergence is codegen's rather than typecheck's**, which is what the back half of Stage 3 looks
like. The 21-row `diverge` delta versus 177 family-A rows is the same accounting: 171 rows moved
*out* of family A into a truthful-tid cell, they did not all leave the divergence set.

The 5 residual `tid=? flat=Ptr[Int]` rows are all `scope.cstr` (4) and `scope.take` (1) — `ps5br9`.
`scope.alloc` / `alloc_n` contribute **zero**, because every corpus use annotates the let; an
unannotated `let p = scope.alloc()` is genuinely under-determined and per
`decisions/under-determined-types.md` must become E0301, **not** be answered with `Ptr[Int]`.

**Two spin-outs, each verified by MVCE before filing.** `ps5br9` — the ffi-scope receiver has no
type either; codegen carries `CT_FFI_SCOPE = 18` with a full method block while
`rg 'ffi_scope|CT_FFI_SCOPE' src/typecheck.bl` finds nothing. `tk903s` — `types_compatible` has the
**same** missing recursion for `Handle` and `Channel`, left behind by `vag3wc` when it made them
constructible: `let ch: Channel[Int] = Channel(2)` then `let bad: Channel[Str] = ch` checks `ok`.
That trailing `return 1` is itself the defect generator this plan names; converting the block to an
exhaustive `match` would make the next omission a compile error.

Test: `tests/test_w13xgb_ptr_tid_and_intrinsic_ret.bl`, 14 rows — 5 red before, 14 green after. Two
rows pin the escape, not one: a row that only asserts the `TypeError` still passes while the `cc`
path reopens, so its partner asserts `compile_and_run`'s captured toolchain stderr does **not**
contain `"incompatible pointer type"`. Three harness traps are recorded in-test because each made a
row lie: `\{` inside the test's *own* interpolation is an escape, so `"\{r.out}\{r.err_out}"` built
the literal haystack `{r.out}{r.err_out}` and the row went vacuously green; `@ffi("c", ...)` names
the **C function**, not a library; and a user `fn c_poll` collides with `lib/std/libc.bl`'s exported
`blink_c_poll` (`project_namespace_builtin_vs_free_fn_collision`). One intended red row was also
wrong about the language rather than the compiler — `let b: Int = p.is_null()` cannot error, because
`types_compatible:7914` makes `Int` and `Bool` deliberately interchangeable (C-style truthiness);
the row declares `Str`, the nearest annotation that discriminates.

**Bootstrap note for the next `TyKind` variant.** Regen 4's `task ci` failed with
`error: 4 test file(s) failed to compile` **and no file names**, and `rg -l "Ptr\[" tests/` found
nothing because none of the four ever spells `Ptr[`. They were found by brute force —
`ls tests/*.bl | xargs -P 24 -I{} sh -c "build/blink check {} >/dev/null 2>&1 || echo CHECKFAIL {}"`
— and all four were `error[NonExhaustiveMatch]: missing pattern 'Ptr'`: **four `tests/*.bl` carry
their own total `match` over `TyKind`** (`test_e0wmt6_async_let_tids.bl`,
`test_nz7drz_closure_fn_tid.bl`, `test_tc_tid_structural_accessors.bl`,
`test_vag3wc_channel_handle_iterator_tids.bl`), deliberately, as a second independent enumeration
of the kind set. That is Stage 0's exhaustiveness net working exactly as intended, in the one place
the ticket-side checklist forgets. `task regen` + `task ci` green after **each** of the five regens.

### `jzvxav` — `self` had no type in any impl method, in any program (CLOSED)

**The untyped-receiver shape for the fourth time**, and the broadest instance of it: not one intrinsic
family, not one namespace — **every impl method body in the language**. `resolve_param_type` answers
`TYPE_UNKNOWN` for a param with no annotation, and `self` is the one param that never carries an
annotation. `tc_infer_program`'s impl loop had `impl_type` in hand three lines before it called
`tc_check_fn`, and threw it away.

**Two observable halves, and only one of them produces a divergence row.** The row-producing half is
the declared-type compare over `let val: Str = self.get(col)` — vacuous, because `TYPE_UNKNOWN`
unifies with anything. The half with **no row at all** is the argument check: an argument is not a
`ScopeVar` declaration, so nothing in this instrument sees it. That half is the `cc` escape:

```blink
trait KV { fn get(self, k: Str) -> Str }
// ... impl body calls self.get(42)
```

passes `blink check` and lands as
`build/b_args.c:138: note: expected 'const char *' but argument is of type 'int'`. Same escape class
as `w13xgb`, and **the row count therefore understates this fix** — 17 rows is the visible half only.

**Two regens.** Regen 1 is purely additive: `resolve_type_ann` splits into a delegating head plus
`resolve_type_parts(name, elems_sl, ann_node)`, because an impl header stores its receiver as `name`
plus a `recv_type_args` sublist (`parser.bl:2088-2091`) and has **no annotation node** to pass —
which also means `ann_node` can now be `-1`, so three sites were hardened for it (the `Fn` branch's
`node_type_ann`, and the `ann_node >= 0` guard in **both** `tc_produce_struct_instance_tid` and
`tc_produce_enum_instance_tid`, whose existing guard admitted `-1`). Regen 2 binds it:
`tc_impl_self_tid(im)` resolves the header **structurally, not as the erased base** — a poly
`impl[T] Firstish[T] for List[T]` carries its type-arg slots exactly the way
`tc_fnsig_param_instance_tid` does for an annotated generic param — parked in `tc_current_self_tid`
across the impl's methods, and consumed in `tc_check_fn`'s param loop **only when the param is still
UNKNOWN**, so an explicitly annotated `self` keeps its own annotation. A trait's own default-method
bodies get `TYPE_UNKNOWN` deliberately: the parser leaves `name` empty for a header with no `for`
clause, and there is no receiver type to speak of. Validation is suppressed during the resolve
because `check_impl_type_arg_names` (`typecheck.bl:4643`) already reports against the same header.

| | after `w13xgb` | after `jzvxav`+`ya8qyf` | delta |
|---|---:|---:|---:|
| family A rows | 327 | **310** | **−17** |
| family A cells | 33 | **32** | −1 |
| total cells | 405 | **404** | −1 |
| diverge rows | 4296 | 4279 | −17 |
| agree | 364883 | 364934 | +51 |
| missing | 1 | 1 | 0 |

**All 17 rows accounted for, and every one is a `self`-in-initializer site.** The retired cell is
`site=emit_let_binding.decl tid=? flat=Cleanup`. By producer: `std_db_row:35` **−12** — the exact
`let val = self.get(col)` inside `impl RowOps for Row` the ticket was found on; `std_testing:74`
**−3** (`let _ = self` inside `impl BlockHandler for Cleanup`); `__main__:43` 3→2; `__main__:59` 2→1.

**`ya8qyf` contributed ~0 divergence rows** — this is an inference from that attribution, not a
separately measured sweep: all 17 rows are `self` sites, and the return-type fix touches no
initializer. Recorded as an inference on purpose.

**Attribution trap, worth writing down.** `grep -o 'at=[^ ]*'` is wrong — it also matches **inside
`flat=`**, because the string `"flat="` ends with `"at="`. It reported phantom sites (`at=Option[Str]`
13, `at=Str` 61, `at=Cleanup`). The boundary has to be explicit: `grep -oa ' at=[^ ]*'`.

Test: `tests/test_jzvxav_self_receiver_impl_tid.bl`, 13 rows — 6 red before, all green after. Rows pin
both halves: the declared-type compare over `self.get(..)`, over a differently-named `self.fetch(..)`
(so a reader cannot mistake it for a builtin-name collision), and over bare `self`; the argument
mismatch; and a `compile_and_run` row asserting the captured toolchain stderr contains neither
`"argument is of type"` nor `"C compilation failed"`, because a row that only asserts the `TypeError`
stays green while the `cc` path reopens. Controls: a local (non-`self`) receiver both ways, a matching
declared type that compiles *and runs*, a self-call chained through another self-call, field access
both ways, `self` passed as a value into a struct literal (`sections/03c_protocols.md:32`), a generic
`impl[T] Firstish[T] for List[T]`, and the `db_row` shape in miniature.

### `ya8qyf` — no impl method in the language ever had its return type checked (CLOSED)

Found as **the single row that stayed red** after `jzvxav`, which is the only reason it was found at
all: it had been filed 2026-07-25 as a P1 with this exact analysis and fix shape, and I re-filed it as
`zd1tz3` before `br show` turned up the original. `zd1tz3` closed as the duplicate.

`tc_mangle_impl_fnsig` (`typecheck.bl:296`) registers an impl method's signature under
`{impl_type}_{trait_name}_{method}`. The check side installed `{impl_type}_{method}`. `lookup_fnsig`
therefore **always missed**, `tc_current_fn_ret` was never installed, and **every** consumer of it
went quiet for methods: the explicit-`return` compare, the implicit-tail compare, and
`tc_check_missing_tail_value`. Not a nested-type or erasure problem at all — a key mismatch. The fix
is one line, parking `tc_mangle_impl_fnsig(..)`'s result in `tc_current_method_sig_key` at the same
place `jzvxav` parks the receiver tid, and preferring it in `tc_check_fn`.

**The proof that the cause is the key and not the receiver** is a row with no `self` in it:

```blink
fn probe(self) -> Int { "nope" }
```

reaches `cc` as *"returning int from a function with return type const char \*"*. **Blast radius
zero** — the compiler's own methods were all correct, merely unchecked; `task ci` was green on the
first run of this regen. Side benefit: the `r9krgr` declared-return pin now reaches methods, so
`ya8qyf`'s second MVCE stops being under-determined (E0301) and compiles, matching what the
free-function spelling already did.

Test: `tests/test_ya8qyf_impl_method_declared_return.bl`, 14 rows, including both of the ticket's
MVCEs verbatim, the free-function control, a `Void` method, two traits sharing a method name, a `From`
impl (the `tc_mangle_impl_fnsig` carve-out at `:297`), a generic impl's typevar return, a `Result`
method using `?`, and a `compile_and_run` row asserting the absence of `"makes pointer from integer"`
/ `"makes integer from pointer"`.

**Two rows in `tests/test_skdxkv_implicit_tail_ret_compare.bl` deliberately asserted the broken
behavior**, under a ticket I had not read, and turned red. They were **flipped, not deleted** — that
file holds the free-function parity twin, and parity between the two spellings is the property worth
guarding. The section header there now records that the gap is closed.

**Both fixes needed the same bootstrap guard.** The first `task ci` failed
`test_reset_staleness.bl`: *"2 variable(s) not in init_types() or allowlist: tc_current_self_tid,
tc_current_method_sig_key"*. Two new compiler globals, two missing resets — exactly the stale-state
guard this project keeps for cross-compilation leakage. `task regen` green after each of the three
regens; `task ci` **EXIT=0, 636/636 test files**. The missing-tail row was confirmed red against
`build/blinkc.bak` and green against the new `build/blinkc`, which is how "was this actually red
before?" gets answered without a second checkout.

### `h3q81d` — an effect operation had no signature anywhere in typecheck (CLOSED)

The #1 remaining cause, and the cleanest illustration of this plan's thesis in the whole campaign.
Typecheck registered the lowercased effect **name** and nothing else — `register_ue_handle`,
`typecheck.bl:5214` — read back for exactly one purpose: suppressing the `UnknownMethod` warning.
No operation signatures at all. Codegen holds the same signatures in `UeMethod`
(`codegen_types.bl:1817`, filled at `codegen.bl:751-909`) across **eight flat return fields** —
`ret`, `ret_ct`, `ret_inner_ct`, `ret_inner_struct`, `ret_inner_ct2`, `ret_inner_struct2`,
`ret_ok_elem_ct`, `ret_ok_elem_struct` — the last pair existing *solely* because
`Result[Option[Row], DBError]` is depth 2 and the flat `(CT_*, sname)` pair stops at depth 1. The op
node is a real `NodeKind.FnDef` carrying its whole annotation tree, so **one tid holds what eight
fields approximate**.

**Both halves escaped to the C compiler**, which makes this the fourth such cause after `dvzt90`,
`2r96m9`, `w13xgb` and `jzvxav`:

```
let bad: Int = storage.get_names()   ->  "returning 'blink_list *' ... makes integer from pointer"
storage.find_name(42)                ->  "expected 'const char *' but argument is of type 'int'"
```

**Two regens.** Regen 1 is additive: `register_ue_op_sigs(ed)` registers one fnsig per op, keyed
`{handle}.{op}` — the key the call site already spells, with the handle (`str_to_lower(effect name)`)
both sides already agreed on — walking `node_elements(ed)` → `node_methods(child)` exactly as
codegen does. Ops live **only** under a sub-effect: `parse_effect_decl` (`parser.bl:1554`) demands
`effect` for every member of the outer body, so a flat `effect Foo { fn op() }` is a parse error and
the two-level walk is complete. `register_fn_sig` needs no special case; the op name is swapped for
the qualified key and restored, the `tc_infer_program` impl-method precedent, because registering
under the bare op name would collide with any free function of that name. `tc_suppress_ann_validation`
is raised, for the same reason `tc_impl_self_tid` raises it: the op's types are validated where the
effect is *declared*, and a consuming module that never selectively imported `Row` must not be told
about it at registration. Regen 2 is one arm in the `MethodCall` Ident block —
`lookup_fnsig("{handle}.{method}")` → `check_arg_shapes` → `fs.ret` — gated on
`nr_is_defined(obj_name) == 0` so a local binding sharing the handle's spelling keeps its own type.

**Blast radius zero**: 637/637 test files green on the first run, so every `db.*` declared type in
the corpus was already correct — merely unchecked.

| | after `jzvxav` | after `h3q81d` | delta |
|---|---:|---:|---:|
| family A rows | 310 | **261** | **−49** |
| family A cells | 32 | **28** | −4 |
| total cells | 404 | **402** | −2 |
| diverge rows | 4279 | 4249 | −30 |
| agree | 364934 | 365243 | +309 |
| missing | 1 | 1 | 0 |

Four family-A cells retired and **none appeared**: `tid=? flat=Row`, `flat=Option[Row]`,
`flat=Option[Str]`, `flat=Result[List[Int], Void]`. Rows in db/sqlite/template-named files fell
**57 → 15**. `agree` rose by 309 against a 30-row `diverge` fall because more comparisons now happen
at all — `db.prepare` resolving to `Result[Stmt, DBError]` changes which instances get emitted — so
the row *totals* are not conserved here the way they were for `dvzt90`.

**Residual, filed as `w089a0`.** Of the 15 rows left in those files, 6 are `nrrs28`'s `Template`
site and the other 9 are every one of `tests/test_db_stmt.bl`'s
`with db.prepare(..).unwrap() as stmt` bindings. `db.prepare` now resolves correctly and the
with-resource **`as` binder drops it**: `let bad: Str = r.value()` inside a `with .. as r` block
compiles clean and prints `7`. That is **the untyped-receiver shape for the fifth time** — `w13xgb`
(`Ptr`), `ps5br9` (the ffi scope), `jzvxav` (`self`), `nrrs28` (`Template`), and now the `as`
binder. The pattern is now the most productive prior in this campaign: when a bucket resists, ask
what the receiver is before asking which method arm is missing.

Test: `tests/test_h3q81d_effect_op_signatures.bl`, 14 rows — 11 red before, all green after. It uses
a plain user-declared effect rather than `std.db`, because the registry is shared and a sidecar adds
nothing to the mechanism; the depth-2 `Result[Option[Str], Str]` row is the `db.query_one` shape in
miniature, and it is the shape that forces codegen's seventh and eighth flat fields. Rows cover
`List`/`Option`/`Int`/`Result[List]`/`Result[Option]`/`Void` returns, the argument check, two
cc-escape assertions, an inferred-result method chain, keying by handle **and** op (a same-named
method on an unrelated type keeps its own signature), and two effects sharing an op name with
different return types. **Helper trap:** `expect_no_error(src, tag, "")` asserts
`!output.contains("")`, which is always false — pass the code you expect *not* to appear.

### Remaining family-A causes, ranked (28 cells / 261 rows)

Re-ranked from the post-`h3q81d` sweep, by **rows on the 874-file common basis**, grouped by the
innermost producer (the outermost call is usually a symptom — `.unwrap()` heads many chains, but its
receiver is already unknown). Rows, not sites: the earlier site-count ranking is what let one entry
hide three unrelated mechanisms.

**The organizing principle, found by auditing the whole allow-list rather than one cause at a time.**
`is_builtin_method` (`src/typecheck.bl:5867-6074`) is a flat **172-name** list whose only job is to
suppress the `UnknownMethod` warning. Return types live in a **separate**, per-receiver-type dispatch
inside `infer_type_uncached`. The two lists are not coupled, so a name in the first with no arm in
the second resolves to `TYPE_UNKNOWN` — silently, because the warning that would have named it is
exactly what the first list suppressed. **73 of the 172 names have no `method == "<name>"`
comparison anywhere in `typecheck.bl`.** Many are legitimately answered elsewhere (`Duration.to_ms`
and friends are real stdlib functions reached through the bare `{Type}_{method}` fnsig key), but
every one that is a pure codegen intrinsic is a family-A cause by construction. This is the same
defect class as `mjsbwm`, `7cq6w2` and `2r96m9` — `project_is_intrinsic_method_must_match_handlers`,
now measured rather than met one instance at a time.

**The entries left are now one shape: a namespace or handle whose operations codegen dispatches and
typecheck has no signature table for — or, more often than not, a RECEIVER with no type at all.**
With the `Str`, `Bytes`, `Ptr`, `self` and effect-op causes closed, the intrinsic-method list is no
longer the leading mechanism. `net.*`/`io.*` is now #1 and needs a *table*; the untyped-receiver
family (`nrrs28`, `ps5br9`, `w089a0`) needs a `TyKind` or a binding, not an arm.

**The old 72-row `db.*` bucket split four ways, and this is the lesson the map keeps re-teaching: a
shared bucket is not a shared cause.** `jzvxav` took the 12 `at=std_db_row:35` rows (`row.get`, never
a `db.*` signature problem at all — it is `self` inside `impl RowOps for Row`), `nrrs28` owns the 9
`at=std_db_sqlite:140` rows (`tpl.type_tag` — `Template[T]`, not `db`), `h3q81d` took the ~42 genuine
effect-op rows, and the 9 that survived are the with-resource `as` binder (`w089a0`).

| cause | rows | ticket | note |
|---|---:|---|---|
| `net.*` / `io.*` — `net.connect` / `listen` / `accept` / `read_bytes` / `write_bytes`, `io.read_line` | 49 | — | **Now the outright #1, 19% of what is left.** `lib/std/net_tcp.bl:68,83,92,128,137`, `src/lsp.bl:32`. The seam is `is_intrinsic_method(namespace, method)` — `pub` in **`src/codegen_types.bl:8084`** and called from `typecheck.bl:9227`, where the *only* two answers are `time.read` (→ `Instant`) and `time.sleep` (→ Void). Typecheck asks codegen's intrinsic list whether the method exists and then has no table of return types behind it. Counted by **producer**: `at=std_net_tcp` 40 (`fd` / `conn` / `rc` as `flat=Int`), `at=lsp` 6, `at=std_http_server` 3. The earlier figure of 55 folded in the `Response`/`Request` rows counted separately below. **`h3q81d` is the template for the fix** — this is the same "codegen has the signatures, typecheck has none" shape, one namespace over |
| ~~`db.*` effect operations — `db.query` / `query_one` / `execute`, `stmt.step`~~ | ~~51~~ | **`h3q81d`** | **CLOSED** — −49 rows, section above. Typecheck held **no** operation signatures, only the handle name for warning suppression; codegen held the same signatures across eight flat return fields. 9 rows survive, all `with db.prepare(..) as stmt` → **`w089a0`** |
| the with-resource `as` binder — `with db.prepare(..).unwrap() as stmt` | 9 | `w089a0` | Split out of `h3q81d`'s residual. `db.prepare` now resolves to `Result[Stmt, DBError]` and the binder drops it, so `stmt.step()` has an untyped receiver. **Untyped-receiver shape, fifth instance**; the tid is already in hand at the binding site, so the fix is the `jzvxav` shape — bind the binder |
| `Template[T]` introspection — `tpl.type_tag` / `count` / `get_int` / `get_float` / `get_str` | 9 | `nrrs28` | Split out of the old `db.*` bucket. All 9 are `at=std_db_sqlite:140`, one per db-flavoured root. **The untyped-receiver shape again**, for the fifth time: `Template` is not a `TyKind`, so the receiver is as permissive as `TYPE_UNKNOWN` before any method arm can run — `w13xgb` / `ps5br9` / `jzvxav` in a fourth costume, and it should be fixed the way `w13xgb` was (variant first, then the lowering, then the method block) |
| `Iterator` adapters — `.zip`, `.chain`, `.enumerate`, `.collect` | 34 | `qzdz2e` | **deferred** (panel decision, user-visible). Was invisible in the previous ranking and is now #3: `tests/test_combining_iterators.bl` (16) and `tests/test_44xww4_enumerate_zip_compound.bl` (18), showing as `flat=List[Void]` and `flat=Tuple2_int_int` — the adapter loses the element type *and* the pair shape |
| `Channel(n)` / `ch.recv` | 24 | — | **likely genuinely under-determined** — the arg is a capacity, not an element type, so this may be `decisions/under-determined-types.md` / E0301, not a missing rule. `tests/test_channels.bl` (11), `tests/test_async_cancel.bl` (7), `src/cli.bl:2162` |
| a cross-module `pub let` container element — `symbol_index.si_file_path.get(i)` | 12 | — | `src/incremental.bl:44,75`, `src/file_watcher.bl:40,73`. Part of the `flat=Str` tail `rbd0a4` uncovered, and **the largest remaining cause inside the compiler's own source** |
| `Response` / `Request` from the http surface | 10 | — | `tests/test_net_integration.bl`, `test_middleware.bl`, `test_http_server.bl`, all `at=__main__`. Same shape as the `net.*` entry and may close with it |
| calling a closure-typed **field** (`route.callback`, `logger.log_msg`) | ~11 | — | |
| `@derive(Deserialize)` / str-backed-enum `Result` returns | 15 | — | 8 `flat=Result[Void, Str]` + 7 `flat=Result[Int, Void]`, in `test_derive_*.bl`, `test_str_backed_enum.bl`, `test_fmt_iife_with_block.bl`. **Un-triaged**: a compiler-*synthesized* fn is the likely producer, which would make it a different mechanism from every entry above — needs its own probe before it gets a ticket |
| `List.join` on a `List[Str]` | ~4 | — | `src/cli.bl:935`, `:3561`, `:3563`. From the `rbd0a4` tail; the last of the allow-list-vs-dispatch shape |
| `Status.from_str` — the compiler-synthesized static on a str-backed enum, returning `Option[Enum]` | 4 | — | third sub-mechanism of the old top entry; also no fnsig |
| ~~`Ptr[T]` intrinsics — `buf.offset(i)`, `p.is_null()`, `s.as_cstr()`~~ | ~~176~~ | **`w13xgb`** | **CLOSED** — −177 rows, section above. `Ptr[T]` had no `TyKind` at all. 5 rows remain, all `scope.cstr` / `scope.take` → **`ps5br9`** |
| ~~`Str` intrinsic aliases — `s.substr(a,b)`, `s.charAt(i)`, `n.to_string()`~~ | ~~147~~ | **`rbd0a4`** | **CLOSED** — −157 rows. `charAt` was not a missing return type; the method does not exist |
| ~~`row.get(col)` inside `impl RowOps for Row`~~ | ~~12~~ | **`jzvxav`** | **CLOSED** — was filed under the `db.*` bucket and was not a `db.*` cause: `self` had no type in **any** impl method in **any** program. −17 rows visible, and an argument-check `cc` escape that produces no row at all |

Note what the `db.*` and iterator entries did **not** do: they did not get bigger. They rose to the
top because the causes above them were removed, and both were already in the map. The one genuinely
new line is the `@derive`/`Result` group, which the earlier `flat=` tail hid behind `Str` and
`Ptr[Int]`.

**Cross-check by source module** (` at=` on the post-`h3q81d` sweep — note the leading space; without
it the pattern also matches inside `flat=`), because the flat spelling and the producing module answer
different questions and disagreeing on which is "the" count is how the Ptr entry once acquired two
figures:

| module | family-A rows | | after `jzvxav` | after `w13xgb` | after `rbd0a4` |
|---|---:|---|---:|---:|---:|
| `__main__` (the root being compiled) | 174 | | 223 | 225 | 237 |
| `std_libc` | **0** | | 0 | 0 | 165 |
| `std_net_tcp` | 40 | | 40 | 40 | 40 |
| `std_db_row` | **0** | | 0 | 12 | 12 |
| `cli` | 11 | | 11 | 11 | 11 |
| `std_db_sqlite` | 9 | | 9 | 9 | 9 |
| `lsp` / `incremental` / `file_watcher` | 6 each | | 6 each | 6 each | 6 each |
| `std_testing` | **0** | | 0 | 3 | 3 |
| `std_http_server` / `pkg_resolver` / `build_stdlib` | 3 each | | 3 each | 3 each | 3 each |

**`std_libc` went from a third of everything left to zero**, and it was one cause; `std_db_row` and
`std_testing` went to zero on `jzvxav`, and it was one cause covering both. The `__main__` bucket is
not a residual cause of its own: `__main__` is whatever root is under compilation, so it is the
*corpus* redistributing the same handful of mechanisms across roots — which is why the ranking is
organized by producer and not by this table. `h3q81d` is the first cause to move `__main__`
substantially (223 → 174) precisely because effect ops are called from roots rather than from a
stdlib module, and `std_net_tcp`'s flat 40 across five sweeps is the mirror image: one cause, one
module, untouched until someone builds it a table.

**The `db.*` mechanism, diagnosed (read-only) — kept as written, because it is the diagnosis
`h3q81d` was fixed from and the prediction it confirms.** These are **effect operations**, declared in
`lib/std/db.bl` as `pub effect DB { effect Read { fn query(..) -> Result[List[Row], DBError] } .. }`.
Typecheck registers only the lowercased effect **name** — `register_ue_handle(str_to_lower(eff_name))`
at `src/typecheck.bl:5126` — and reads it back at `:7358` for one purpose only: suppressing the
`UnknownMethod` warning. It holds **no operation signatures whatsoever**, so `db.query(..)` cannot
resolve. Codegen holds them in the `UeMethod` registry (`src/codegen_types.bl:1817`, populated at
`src/codegen.bl:751-901`) with **eight flat return fields** — `ret`, `ret_ct`, `ret_inner_ct`,
`ret_inner_struct`, `ret_inner_ct2`, `ret_inner_struct2`, `ret_ok_elem_ct`, `ret_ok_elem_struct` —
where the last pair exists solely because `Result[Option[Row], DBError]` is depth 2 and the flat
`(CT_*, sname)` pair stops at depth 1. That is this plan's thesis in one struct. The fix has a clean
source: the op's `node_type_ann` through `resolve_type_ann` (`typecheck.bl:2357`), keyed by
`{handle}.{op}`, walking `node_elements(effect_decl)` → `node_methods(sub_effect)` exactly as
codegen does.

## Appendix — all 428 shape cells

Format: `family | occurrences | tid | flat`.

```
A |    715 | ? | StringBuilder
A |    357 | ? | Str
A |    247 | ? | Int
A |    169 | ? | Bytes
A |    152 | ? | Ptr[Int]
A |     52 | ? | Handle[Int]
A |     47 | ? | I32
A |     42 | ? | Fn(int64_t(*)(const blink_closure*, int64_t))
A |     27 | ? | List[Void]
A |     24 | ? | Channel[Int]
A |     23 | ? | DiagEntry
A |     16 | ? | Fn(int64_t(*)(const blink_closure*))
A |     16 | ? | List[Str]
A |     16 | ? | Option[Str]
A |     10 | ? | Response
A |     10 | ? | Row
A |      9 | ? | Option[Int]
A |      9 | ? | Tuple2_int_int
A |      8 | ? | List[Int]
A |      8 | ? | Result[Void, Str]
A |      7 | ? | Result[Char, ]
A |      7 | ? | Result[Int, Void]
A |      6 | ? | Point
A |      6 | ? | Result[I8, ]
A |      5 | ? | Fn(const char*(*)(const blink_closure*, const char*))
A |      5 | ? | Result[U8, ]
A |      4 | ? | Fn(const char*(*)(const blink_closure*))
A |      4 | ? | Fn(void(*)(const blink_closure*))
A |      4 | ? | QueryError
A |      3 | ? | Bool
A |      3 | ? | Fn(int64_t(*)(const blink_closure*, int64_t, int64_t))
A |      3 | ? | Map[Int, Int]
A |      3 | ? | Option[Row]
A |      3 | ? | Result[Int, Str]
A |      3 | ? | Result[Str, Str]
A |      3 | ? | Tuple2_int_Option_int
A |      2 | ? | DbError
A |      2 | ? | Event
A |      2 | ? | Fn(blink_list*(*)(const blink_closure*))
A |      2 | ? | Fn(blink_Option_int(*)(const blink_closure*, int64_t))
A |      2 | ? | Fn(blink_Result_int_str(*)(const blink_closure*, const char*, int64_t))
A |      2 | ? | Fn(blink_Tuple2_int_Option_Cmd(*)(const blink_closure*, int))
A |      2 | ? | Handle[Option[Int]]
A |      2 | ? | Handle[Result[Int, Str]]
A |      2 | ? | PgError
A |      2 | ? | Result[I16, ]
A |      2 | ? | Result[I32, ]
A |      2 | ? | Result[List[Int], Void]
A |      2 | ? | Shape
A |      2 | ? | Tuple2_GctModel_int
A |      2 | ? | Tuple2_int_Option_Cmd
A |      2 | ? | Tuple2_int_Result_int_str
A |      2 | ? | Tuple2_Option_int_Option_int
A |      2 | ? | Tuple2_Result_int_str_Result_int_str
A |      2 | ? | Tuple3_int_int_int
A |      1 | ? | Big
A |      1 | ? | CmgPoint
A |      1 | ? | Color
A |      1 | ? | ConfigError
A |      1 | ? | Duration
A |      1 | ? | Float
A |      1 | ? | Fn(blink_Option_str(*)(const blink_closure*, int64_t))
A |      1 | ? | Fn(blink_Point(*)(const blink_closure*, blink_Color))
A |      1 | ? | Fn(blink_Point(*)(const blink_closure*, int))
A |      1 | ? | Fn(double(*)(const blink_closure*, double))
A |      1 | ? | Fn(int(*)(const blink_closure*, int64_t))
A |      1 | ? | Fn(void(*)(const blink_closure*, int64_t))
A |      1 | ? | Handle[]
A |      1 | ? | Handle[Bool]
A |      1 | ? | Handle[Float]
A |      1 | ? | Handle[List[Int]]
A |      1 | ? | Handle[Str]
A |      1 | ? | List[Char]
A |      1 | ? | List[I32]
A |      1 | ? | Map[Char, Int]
A |      1 | ? | Map[I32, Int]
A |      1 | ? | Map[I8, Int]
A |      1 | ? | Map[Int, Str]
A |      1 | ? | Map[Str, Int]
A |      1 | ? | Map[U32, Int]
A |      1 | ? | Map[U8, Int]
A |      1 | ? | Msg
A |      1 | ? | Pair
A |      1 | ? | Person
A |      1 | ? | Request
A |      1 | ? | Result[U16, ]
A |      1 | ? | Result[U32, ]
A |      1 | ? | Result[U64, ]
A |      1 | ? | Result[Void, Void]
A |      1 | ? | Tuple2_GctModel_str
A |      1 | ? | Tuple2_Model_Option_test_295z9x_generic_tuple_option_body_helper_Cmd
A |      1 | ? | Tuple2_Model_Option_test_vy5113_tuple_import_carrier_helper_Cmd
A |      1 | ? | Tuple2_str_int
A |      1 | ? | Tuple2_Z9Model_Option_Z9Cmd
B |   3124 | Void | ProcessResult
B |     23 | Void | Option[Int]
B |      3 | Void | Int
B |      1 | Void | Option[Big]
B |      1 | Void | Option[Option[Int]]
B |      1 | Void | Option[Option[Map[Int, Str]]]
B |      1 | Void | Option[Result[Int, Str]]
C |    220 | List[MatchScrutEntry] | List[Void]
C |    189 | List[NativeDep] | List[]
C |     47 | List[Pollfd] | List[Void]
C |     40 | List[HandlerCapture] | List[Void]
C |     21 | List[NativeDep] | List[Void]
C |     14 | Result[Char, ConversionError] | Result[Char, ]
C |     13 | Result[TcpSocket, NetError] | Result[, ]
C |      9 | List[Row] | List[Void]
C |      9 | Map[Str, Box[Int]] | Map[Str, Void]
C |      7 | Result[TcpListener, NetError] | Result[, ]
C |      6 | Map[Str, Point] | Map[Str, Void]
C |      5 | List[CmgPoint] | List[Void]
C |      5 | List[Item] | List[Void]
C |      5 | Result[Int, Errno] | Result[Int, ]
C |      5 | Result[Option[Item], LookupError] | Result[Option[Int], ]
C |      4 | List[(Int, Int)] | List[Void]
C |      4 | List[Node] | List[Void]
C |      4 | List[Person] | List[Void]
C |      4 | Map[Str, Box] | Map[Str, Void]
C |      3 | List[Hook] | List[Void]
C |      3 | List[Int] | List[]
C |      3 | List[LocalPoint] | List[Void]
C |      3 | List[Route] | List[Void]
C |      3 | List[RouteSegment] | List[]
C |      3 | List[(Str, Int)] | List[Void]
C |      3 | List[Value] | List[]
C |      3 | Map[Str, Item] | Map[Str, Void]
C |      3 | Result[Box[Int], Str] | Result[Void, Str]
C |      3 | Result[Color, Str] | Result[, Str]
C |      3 | Result[Point, Str] | Result[, Str]
C |      2 | List[Color] | List[]
C |      2 | List[HelperBox[Int]] | List[Void]
C |      2 | List[List[Person]] | List[List[Void]]
C |      2 | List[Point] | List[Void]
C |      2 | List[(Str, (Int, Bool))] | List[Void]
C |      2 | Map[Int, NineBox] | Map[Int, Void]
C |      2 | Map[Str, Row] | Map[Str, Void]
C |      2 | Result[Bytes, NetError] | Result[Bytes, ]
C |      2 | Result[Coord, MathError] | Result[, ]
C |      2 | Result[Foo_Bar, Baz_Qux] | Result[Void, Void]
C |      2 | Result[Int, DBError] | Result[Int, ]
C |      2 | Result[Int, E] | Result[Int, ]
C |      2 | Result[Item, MyError] | Result[, ]
C |      2 | Result[QBox[Int], QBox[Str]] | Result[, ]
C |      2 | Result[RBox[Int], RBox[Str]] | Result[, ]
C |      2 | Result[Status, Str] | Result[, Str]
C |      2 | Result[Void, NetError] | Result[Void, ]
C |      1 | List[BatchSummary] | List[Void]
C |      1 | List[Big] | List[Void]
C |      1 | List[Box[Box[Int]]] | List[Void]
C |      1 | List[Box[Int]] | List[Void]
C |      1 | List[Box] | List[Void]
C |      1 | List[Box[Str]] | List[Void]
C |      1 | List[CmgBox[Int]] | List[]
C |      1 | List[Color] | List[Void]
C |      1 | List[Expr] | List[Void]
C |      1 | List[HelperBox[HelperPoint]] | List[Void]
C |      1 | List[HelperPoint] | List[Void]
C |      1 | List[(Int, Int, Bool)] | List[]
C |      1 | List[(Int, Str)] | List[]
C |      1 | List[Item] | List[]
C |      1 | List[LBox[Int]] | List[Void]
C |      1 | List[LBox[Str]] | List[Void]
C |      1 | List[(Map[Str, Int], Int)] | List[]
C |      1 | List[MathOpList] | List[Void]
C |      1 | List[(Option[Int], Int)] | List[]
C |      1 | List[Option[(Int, Int)]] | List[Option[Void]]
C |      1 | List[(Option[List[Int]], Int)] | List[Void]
C |      1 | List[(Option[Map[Str, Int]], Int)] | List[Void]
C |      1 | List[(Option[P], Int)] | List[Void]
C |      1 | List[(Option[QBox[Int]], Int)] | List[Void]
C |      1 | List[Row] | List[]
C |      1 | List[SbBox8zdwqy[Int]] | List[]
C |      1 | List[Shape] | List[Void]
C |      1 | List[Thing] | List[Void]
C |      1 | List[T] | List[Void]
C |      1 | List[U] | List[Void]
C |      1 | Map[K, V] | Map[Str, Void]
C |      1 | Map[Str, Big] | Map[Str, Void]
C |      1 | Map[Str, Box[Box[Box[T]]]] | Map[Str, Void]
C |      1 | Map[Str, Box[Box[T]]] | Map[Str, Void]
C |      1 | Map[Str, CmgBox[Int]] | Map[Str, Void]
C |      1 | Result[AcceptSocket, AcceptError] | Result[Void, Void]
C |      1 | Result[Bytes, NetError] | Result[Bytes, Void]
C |      1 | Result[CmgPoint, Str] | Result[Void, Str]
C |      1 | Result[Foo_Bar, Str] | Result[Void, Str]
C |      1 | Result[Int, IIFEErr] | Result[Int, ]
C |      1 | Result[Int, MathError] | Result[Int, ]
C |      1 | Result[Int, Thing] | Result[Int, Void]
C |      1 | Result[Labeled, Str] | Result[, Str]
C |      1 | Result[List[Str], AppError] | Result[List[Int], ]
C |      1 | Result[LocalPoint, Str] | Result[Void, Str]
C |      1 | Result[LocBox[Int], Str] | Result[Void, Str]
C |      1 | Result[Person, Str] | Result[, Str]
C |      1 | Result[P, Int] | Result[, Int]
C |      1 | Result[Point, Str] | Result[Void, Str]
C |      1 | Result[P, Str] | Result[, Str]
C |      1 | Result[Timer, Str] | Result[, Str]
C |      1 | Result[Void, NetError] | Result[Void, Void]
C |      1 | T | Result[Int, Void]
D |    483 | TyKind | Int
D |     95 | TokenKind | Int
D |     16 | Color | Int
D |     11 | Direction | Int
D |      9 | K | Int
D |      6 | U | Int
D |      3 | Errno | Int
D |      3 | Kind9 | Int
D |      3 | T | Int
D |      2 | V | Int
D |      1 | A | Int
D |      1 | Big | Int
D |      1 | B | Int
D |      1 | Coord | Int
D |      1 | (Int, Bytes) | Int
D |      1 | Mode | Int
D |      1 | NoDisplay | Int
D |      1 | Status | Int
E |    598 | TyKind | TyKind
E |    141 | TokenKind | TokenKind
E |     25 | Shape | Shape
E |     16 | Duration | Duration
E |     12 | Instant | Instant
E |     10 | NetError | NetError
E |      8 | Expr | Expr
E |      8 | Node | Node
E |      7 | Option[Cmd] | Option[Cmd]
E |      6 | QueryError | QueryError
E |      5 | Color | Color
E |      4 | Wrapper | Wrapper
E |      3 | DbError | DbError
E |      3 | Event | Event
E |      2 | Box | Box
E |      2 | EvNestedMap | EvNestedMap
E |      2 | Option[Errno] | Option[Errno]
E |      2 | Result2 | Result2
E |      1 | Cmd | Cmd
E |      1 | Ev | Ev
E |      1 | EvPointList | EvPointList
E |      1 | Key | Key
E |      1 | Map[Color, Int] | Map[Color, Int]
E |      1 | Msg | Msg
E |      1 | MyResult | MyResult
E |      1 | Option[Z9Cmd] | Option[Z9Cmd]
E |      1 | Point | Point
E |      1 | SoleState | SoleState
F |     77 | Handle | Handle[Int]
F |     70 | Ptr | Ptr[Int]
F |     27 | Map[Str, List[Str]] | Map[Str, List[Int]]
F |     22 | (Int, Int) | Tuple2_int_int
F |     14 | K | Str
F |     14 | List[K] | List[Str]
F |     11 | (Option[Int], Int) | Tuple2_Option_int_int
F |      8 | List[K] | List[Int]
F |      8 | Map[Str, Str] | Map[Str, Int]
F |      8 | Tree | Tree_0Int
F |      7 | Handler | Unknown
F |      7 | (M, Option[Cmd]) | Tuple2_M_Option_Cmd
F |      6 | Map[Str, Box] | Map[Str, Int]
F |      6 | Result[Option[Str], Str] | Result[Option[Int], Str]
F |      6 | (Str, T) | Tuple2_str_int
F |      5 | Int | Bool
F |      5 | Result[Box[Int], Str] | Result[Int, Str]
F |      4 | (Int, Bytes) | Tuple2_int_bytes
F |      4 | (Int, Str) | Tuple2_int_str
F |      4 | List[?] | List[Int]
F |      4 | Map[K, V] | Map[Str, Int]
F |      4 | Map[Str, Box[Int]] | Map[Str, Int]
F |      4 | (Map[Str, Int], Int) | Tuple2_Map_str_int_int
F |      4 | Option[(Int, Int)] | Option[Tuple2_int_int]
F |      4 | Result[Int, P] | Result[Int, Int]
F |      4 | Result[Result[Str, Int], Str] | Result[Result[Int, Str], Str]
F |      4 | (Set[Int], Int) | Tuple2_set_int
F |      4 | (Str, Int) | Tuple2_str_int
F |      4 | T | Option[Int]
F |      3 | Box | Box_0Int
F |      3 | Either | Either_0Int_0Str
F |      3 | Fn | Fn(blink_std_http_types_Response(*)(const blink_closure*, blink_std_http_types_Request, const char*))
F |      3 | (Int, Int, Int, Int) | Tuple4_int_int_int_int
F |      3 | List[U] | List[Int]
F |      3 | Map[K, V] | Map[Int, Int]
F |      3 | Map[Str, Point] | Map[Str, Int]
F |      3 | (Model, Cmd) | Tuple2_Model_Cmd
F |      3 | Option[Map[Str, Str]] | Option[Map[Int, Int]]
F |      3 | Option[Option[Str]] | Option[Option[Int]]
F |      3 | Option[UserRow] | Option[Int]
F |      3 | Result[Int, ?] | Result[Int, Str]
F |      3 | Result[P, Int] | Result[Int, Int]
F |      3 | Result[Result[Result[Int, Str], Str], Str] | Result[Result[Int, Str], Str]
F |      3 | Set[(Int, Str)] | Set[Tuple2_int_str]
F |      3 | (Set[Str], Int) | Tuple2_set_int
F |      2 | (Int, Option[Cmd]) | Tuple2_int_Option_Cmd
F |      2 | (Int, Str, Int) | Tuple3_int_str_int
F |      2 | (Map[Int, NineBox], Int) | Tuple2_map_int
F |      2 | (Map[Int, Str], Int) | Tuple2_map_int
F |      2 | Map[Int, Str] | Map[Str, Int]
F |      2 | Map[K, U] | Map[Str, Float]
F |      2 | Map[K, U] | Map[Str, Str]
F |      2 | Map[K, V] | Map[Str, Float]
F |      2 | (Map[Point, Int], Int) | Tuple2_map_int
F |      2 | (Map[Str, Int], Int) | Tuple2_map_int
F |      2 | Map[Str, U] | Map[Str, Float]
F |      2 | Map[Str, U] | Map[Str, Str]
F |      2 | M | Model
F |      2 | (M, Option[Payload]) | Tuple2_M_Option_Payload
F |      2 | (M, Option[Result[Int, Str]]) | Tuple2_M_Option_Result_int_str
F |      2 | (M, Result[Int, Str]) | Tuple2_M_Result_int_str
F |      2 | (Option[AnaqcPoint], Int) | Tuple2_Option_AnaqcPoint_int
F |      2 | (Option[Char], Int) | Tuple2_Option_char_int
F |      2 | (Option[Cmd], Int) | Tuple2_Option_Cmd_int
F |      2 | (Option[Float], Int) | Tuple2_Option_double_int
F |      2 | Option[(Int, Int)] | Option[Int]
F |      2 | (Option[List[Int]], Int) | Tuple2_Option_list_int
F |      2 | (Option[Map[Str, Int]], Int) | Tuple2_Option_Map_str_int_int
F |      2 | Option[Map[Str, List[Int]]] | Option[Map[Int, Int]]
F |      2 | (Option[Str], Int) | Tuple2_Option_str_int
F |      2 | Pair2 | Pair2_0Int_0Str
F |      2 | (Result[Int, Int], Int) | Tuple2_Result_int_int_int
F |      2 | Result[Int, Option[Str]] | Result[Int, Option[Int]]
F |      2 | (Result[Int, Str], Int) | Tuple2_Result_int_str_int
F |      2 | Result[List[Pollfd], Str] | Result[List[Int], Str]
F |      2 | Result[Nest, Int] | Result[Int, Int]
F |      2 | Result[Option[Item], Str] | Result[Option[Int], Str]
F |      2 | Result[P, Q] | Result[Int, Int]
F |      2 | Result[P, Str] | Result[Int, Str]
F |      2 | (Result[Str, Int], Int) | Tuple2_Result_str_int_int
F |      2 | Result[T, Str] | Result[Int, Str]
F |      2 | (Set[Point], Int) | Tuple2_set_int
F |      2 | (Str, T) | Tuple2_str_str
F |      2 | (Str, T) | Tuple2_str_Tuple3_int_int_int
F |      2 | T | Map[Str, Int]
F |      2 | T | Option[Str]
F |      2 | T | Option[Thing]
F |      2 | T | Option[Tuple2_int_int]
F |      2 | T | Result[Int, Str]
F |      2 | T | Thing
F |      2 | T | Tuple2_int_int
F |      2 | U | Str
F |      1 | A | Option[Int]
F |      1 | B | Option[Int]
F |      1 | Choice | Choice_0Int_0Str
F |      1 | (Int, Float, Bool) | Tuple3_int_double_bool
F |      1 | (Int, Int, Bool) | Tuple3_int_int_bool
F |      1 | (Int, (Int, Int)) | Tuple2_int_Tuple2_int_int
F |      1 | (Int, Int, Int) | Tuple3_int_int_int
F |      1 | ((Int, Int), Str) | Tuple2_Tuple2_int_int_str
F |      1 | (List[Int], Int) | Tuple2_list_int
F |      1 | List[K] | List[U64]
F |      1 | List[Map[K, V]] | List[Map[Str, Int]]
F |      1 | List[Str] | List[Int]
F |      1 | (LocBox[Int], Int) | Tuple2_LocBox_0Int_int
F |      1 | (LocBox[Int], LocBox[Int]) | Tuple2_LocBox_0Int_LocBox_0Int
F |      1 | (LocBox[LocBox[Int]], Int) | Tuple2_LocBox_0LocBox_10Int_int
F |      1 | Map[HBox[HBox[T]], Int] | Map[HBox_0HBox_10Int, Int]
F |      1 | Map[(Int, Int), Str] | Map[Tuple2_int_int, Str]
F |      1 | Map[(Int, Str), Int] | Map[Tuple2_int_str, Int]
F |      1 | Map[Int, U] | Map[Int, Int]
F |      1 | Map[Int, U] | Map[Int, Str]
F |      1 | Map[K, Int] | Map[Int, Int]
F |      1 | Map[K, Int] | Map[Str, Int]
F |      1 | Map[K, Int] | Map[U64, Int]
F |      1 | Map[K, Str] | Map[Tuple2_int_int, Str]
F |      1 | Map[K, U] | Map[Int, Int]
F |      1 | Map[K, U] | Map[Int, Str]
F |      1 | Map[K, V] | Map[Int, Str]
F |      1 | Map[Str, Box[Box[Box[Int]]]] | Map[Str, Int]
F |      1 | Map[Str, Box[Box[Int]]] | Map[Str, Int]
F |      1 | Map[(Str, Int), Int] | Map[Tuple2_str_int, Int]
F |      1 | Map[Str, List[Int]] | Map[Str, Int]
F |      1 | Map[Str, T] | Map[Str, Int]
F |      1 | (Model, Option[Cmd], Int) | Tuple3_Model_Option_test_295z9x_generic_tuple_option_body_helper_Cmd_int
F |      1 | M | Z9Model
F |      1 | (Option[Bytes], Int) | Tuple2_Option_bytes_int
F |      1 | (Option[Cmd], Str) | Tuple2_Option_Cmd_str
F |      1 | (Option[Color], Int) | Tuple2_Option_Color_int
F |      1 | Option[Either] | Option[Either_0Int_0Str]
F |      1 | (Option[I32], Int) | Tuple2_Option_i32_int
F |      1 | Option[List[Str]] | Option[List[Int]]
F |      1 | Option[LocElem] | Option[Int]
F |      1 | Option[Map[Str, Str]] | Option[Map[Str, Int]]
F |      1 | (Option[Option[Int]], Int) | Tuple2_Option_Option_int_int
F |      1 | (Option[P], Int) | Tuple2_Option_P_int
F |      1 | (Option[QBox[Int]], Int) | Tuple2_Option_QBox_0Int_int
F |      1 | (Option[Result[List[Int], Int]], Int) | Tuple2_Option_Result_list_int_int
F |      1 | (Option[Result[Map[Str, Int], Int]], Int) | Tuple2_Option_Result_Map_str_int_int_int
F |      1 | (Option[Set[Int]], Int) | Tuple2_Option_set_int
F |      1 | Option[Thing] | Option[Int]
F |      1 | PairS | PairS_0Int_0Str
F |      1 | (Point, Int) | Tuple2_Point_int
F |      1 | (Pt, Int) | Tuple2_Pt_int
F |      1 | (Result[Bool, U8], Int) | Tuple2_Result_bool_u8_int
F |      1 | (Result[Bytes, Int], Int) | Tuple2_Result_bytes_int_int
F |      1 | (Result[Cmd, MyErr], Int) | Tuple2_Result_Cmd_MyErr_int
F |      1 | Result[Cmd, MyErr] | Result[Int, Int]
F |      1 | (Result[Cmd, MyErr], Str) | Tuple2_Result_Cmd_MyErr_str
F |      1 | Result[CmgBox[Str], Str] | Result[Int, Str]
F |      1 | Result[(Int, Int), Str] | Result[Int, Str]
F |      1 | (Result[Int, List[Int]], Int) | Tuple2_Result_int_list_int
F |      1 | (Result[Int, Map[Str, Int]], Int) | Tuple2_Result_int_Map_str_int_int
F |      1 | Result[Int, Option[Item]] | Result[Int, Option[Int]]
F |      1 | Result[Int, Set[Int]] | Result[Int, Set[?]]
F |      1 | Result[Int, Thing] | Result[Int, Int]
F |      1 | (Result[List[Int], Int], Int) | Tuple2_Result_list_int_int
F |      1 | Result[List[Str], Str] | Result[List[Int], Str]
F |      1 | Result[Map[Int, Str], Str] | Result[Map[Str, Int], Str]
F |      1 | (Result[Map[Str, Int], Int], Int) | Tuple2_Result_Map_str_int_int_int
F |      1 | Result[Map[Str, Str], Str] | Result[Map[Str, Int], Str]
F |      1 | Result[Option[Map[Str, Int]], Bytes] | Result[Option[Int], Bytes]
F |      1 | Result[Option[Option[Int]], Str] | Result[Option[Int], Str]
F |      1 | Result[Point, Str] | Result[Int, Str]
F |      1 | Result[RBox[Int], RBox[Str]] | Result[Int, Int]
F |      1 | Result[ReasP, Int] | Result[Int, Int]
F |      1 | Result[Result[Result[Result[Int, Str], Str], Str], Str] | Result[Result[Int, Str], Str]
F |      1 | Result[Set[Int], Bytes] | Result[Set[?], Bytes]
F |      1 | Result[?, Str] | Result[Int, Str]
F |      1 | Result[TwoBox[Int, Str], TwoBox[Str, Int]] | Result[Int, Int]
F |      1 | (Set[(Int, Str)], Int) | Tuple2_set_int
F |      1 | Set[?] | Set[Int]
F |      1 | Set[(Str, Int)] | Set[Tuple2_str_int]
F |      1 | Set[T] | Set[Point]
F |      1 | Set[T] | Set[Tuple2_int_int]
F |      1 | Set[T] | Set[Tuple2_int_str]
F |      1 | U | AccA
F |      1 | U | AccB
F |      1 | V | Float
F |      1 | (Z9Model, Option[Z9Cmd]) | Tuple2_Z9Model_Option_Z9Cmd
M |     39 | - | -
```
