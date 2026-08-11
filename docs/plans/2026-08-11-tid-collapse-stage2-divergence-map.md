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
- **Divergence sweep: archive-linked only.** `BLINK_TRACE_CHANNELS` is read at
  `src/cli.bl:3520`; `src/blinkc_main.bl` never initialises `dbg_channels`, so
  `build/blinkc` — the only monolithic emitter — cannot be traced, and `blink build` has
  no monolith flag (`--emit binary|c|per-module-dir`). Stage 3 needs monolithic-mode
  measurement to prove the counter reaches zero in both modes, so `blinkc` must learn the
  channel env var first.
- **Tap proven to fire by hand**, not inferred from corpus hits: a constructed probe emitted
  three `bucket=diverge` rows before the LetBinding tid memo was published and zero after.

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
