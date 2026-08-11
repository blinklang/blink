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

`k9agr8` gates the *measurement*, not the code: without it Stage 3 can only demonstrate 0
in archive-linked mode.

## copy_list_compound_elem — an unexercised tap, not a clean result

`.src` fired **once** across the entire corpus, as *missing*. `.no_arm` — the instrumented
stand-in for the absent `CT_SET` / `CT_LIST` / `CT_STRUCT` arms, three open 03p551 cells
verbatim — **never fired at all**. Per `feedback_corpus_sweep_is_not_coverage` a zero-hit
sweep is an unexercised tap and proves nothing: the shapes must be constructed by hand
before the three missing arms can be called live or theoretical.

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
**flat universe is strictly more informative than the tid**:

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
