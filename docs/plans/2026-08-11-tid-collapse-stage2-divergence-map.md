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
| C | flat side erased (`List[Void]`, `List[]`, `Result[X, ]`, `Map[K, Void]`) | 100 | 731 | killed structurally by **Stage 4** (see correction below) |
| D | enum stored as `Int` in codegen | 18 | 639 | resolved by construction |
| E | same spelling both sides, differing `CT_*` (enum-vs-struct) | 28 | 864 | resolved by construction |
| F | spelling / mono-stem / typevar-vs-concrete / fabricated payload | 180 | 579 | per-cell triage in Stage 3 |

**Correction, made while working family C in Stage 3.** Family C is not killed by Stage 3. Every one of
its rows is a `sv_tp` fabrication read through a flat slot that holds `-1`, so it survives as long as
`sv_tp` exists — and `sv_tp` is deletion group 1 of **Stage 4**. Stage 3 can only stop *consulting* it
per site, which is what each closed cell in this document does; the family clears wholesale when the
factory goes. Stage 3's exit gate is therefore not "428 cells at zero" but "no site still asks `sv_tp`
for an answer it can get from the tid".

**Instrument limitation, on the same gate.** The tap compares *rendered shapes* (`tc_type_str` against
the flat speller), so in principle it cannot see a wrong `CT_*` hiding under an identical spelling: a
zero counter is not a proof of agreement, and a class in that blind spot would have to arrive as a
hand-constructed shape rather than as a scheduled cell. Read with
`feedback_corpus_sweep_is_not_coverage`.

> **Retraction.** An earlier version of this note cited a tuple binder losing `CT_STRINGBUILDER` as a
> measured instance, from br `v71vxv`. That instance is not real — the probe behind it called
> `sb.append(...)`, which `StringBuilder` does not have, and the shape binds correctly on the pre-fix
> compiler. Every real row of that ticket's class was a **visible** `bucket=diverge` row. The general
> caution above stands and does have a measured instance — `Map[Str, List[Int]]` reads `agree` at the
> `emit_fn_params.param` cell because `sv_tp` fabricates the missing element as `Int` — but that is a
> fabrication matching by luck, not two spellings colliding, and it is a narrower hole than the note
> originally claimed. What is *not* narrow: the count of rows in a class says nothing about its size.
> `v71vxv` is six shapes wide and the whole corpus contained two rows of it.

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
| `w089a0` | P2 | *(`h3q81d`'s residual, and the untyped-receiver shape a **fifth** time)* the with-resource `as` binder carried no type, so `with db.prepare(..).unwrap() as stmt` left `stmt.step()` with an untyped receiver even though `db.prepare` now resolves. **−13 rows**; another **silent miscompile** — `let bad: Str = r.value()` compiled clean and printed `7`. The type was dropped one line above the walk that computes it, so the whole fix was `nr_define` → `nr_define_typed`. Blast radius one fixture, which gained a **correct** E0514 |
| `jw2yz2` | P2 | *(byproduct of `w089a0`'s ffi-scope control)* a `Ptr[T]` ffi-struct field read has no type: `let v = p.fd.read()` emits *"variable declared void"* and `"{p.fd.read()}"` compiles, runs and prints the literal `<value>`. Third link in the `Ptr` chain after `w13xgb` / `ps5br9` |
| `qjfwc6` | P2 | *(the ranked #1 after `h3q81d`, same shape one namespace over)* every namespace intrinsic but `time.read` / `time.sleep` had no typecheck signature, so `net.connect` / `io.read_line` / `term.width` / `env.args` all resolved to `TYPE_UNKNOWN`. **−45 rows**, `std_net_tcp` 40 → 0. The declared-type half was a **silent miscompile** — `let bad: Str = net.connect(host, port)` compiled, linked and *ran* — and arity was a **compiler panic** at `parser.bl:111` |
| `jr4xf7` | P2 `type:spec` | *(`qjfwc6`'s held group)* what does `fs.read` return? The spec spells `fs.read(path)?` as a `Result` and names the lister `fs.list`; codegen emits a bare `const char*` from `blink_read_file` and calls it `list_dir`. 4 rows, and typecheck cannot sign `fs.*` until it is answered |
| `n84s1p` | P3 | *(`qjfwc6`'s other residual)* **CLOSED, −8 rows.** `is_intrinsic_method` was short of the codegen arms by **twelve** names (7 `io.*`, 5 `env.*`), not the three the ticket claimed, so each took the bare-name `lookup_fnsig` path and resolved to nothing. **Five** fail-open modes including two **silent miscompiles**, a pointer-derived **exit status**, four `cc` escapes and a **compiler panic** on a missing argument. Fix is one-directional — **list ⊇ arms** — so `io.debug` stays listed. `src/lsp.bl` → 0 |
| `x3x0qj` | P2 | *(found by probing the un-triaged `@derive`/`Result` line, which turned out to be three causes)* an **immediately-invoked closure** was entirely unchecked: `infer_type`'s `Call` arm had branches for an `Ident` and a `FieldAccess` callee only, so a closure **literal** callee fell through to `TYPE_UNKNOWN` with its arguments un-inferred. Result type, arity **and** the callee body all unchecked at once — a **silent miscompile** (`let bad: Str = fn() -> Int { 7 }()` ran and printed `7`) plus two `cc` escapes. **−10 rows**, and the first fix whose rows moved family A → **class B** instead of leaving `diverge`. Callee position is the third position of `1hg8b6`'s family |
| `pvhaew` | P2 | *(`nxnnxe`'s byproduct, and the allow-list shape **inverted** — a fifth sighting)* `@derive(Hash)` registered, forward-declared and **emitted** `uint64_t {T}_hash`, and **neither** derive-dispatch block had an arm to call it, so `p.hash()` was a hard E0505. It survived because kops calls the same symbol internally for struct-keyed `Map`/`Set` — an emitted, exercised, load-bearing function that was never callable **by name**. Here the allow-list is right and the **dispatch table** is short; same repair, **a table not arms**. `hash` joins `register_derive_method_sigs` as `(self) -> U64`, completing that table. **Divergence-neutral, measured.** Byproduct: `173wtk` |
| `bf0jnj` | P2 | *(`nxnnxe`'s byproduct, and the `expr_result_*`-vs-`ScopeVar` split that Stage 4 deletes)* the `from_str` emitter stamped the Option's inner type on the temp **variable** and not on the **expression** channel, so a direct `match Status.from_str(..)` scrutinee was spelled `blink_Option_void` while an intermediate `let` worked. The `try_from`/`from_json` arm **one line above** writes its channel — a two-line asymmetry inside one function. **Divergence-neutral, measured** (every figure of the after-`nxnnxe` sweep reproduced exactly). Byproduct: `qne9k3` |
| `cttrag` | P2 | *(the ranked top cause inside the compiler's own source, and the entry whose axes were wrong)* a **module-qualified** top-level `let` had no type: `infer_type`'s `FieldAccess` arm had cases for an enum type qualifier, a struct field and a tuple index, and **no fourth for a module qualifier**, so `prov.count` fell off its tail as `TYPE_UNKNOWN` — while the *bare* form inside the declaring module was always typed, because `:11582` had already registered the type the qualified form never read. **Not** container-specific, **not** about `pub`, **not** about crossing a module boundary: two of the ranking row's three axes were wrong. Both halves failed open differently — `let bad: Str = prov.count` compiled, linked and **ran** printing `3`; `want_str(prov.count)` reached `cc` with **no diagnostic at all**. Fixed with a table keyed `"{module}.{name}"` rather than a bare-name `nr_get_type`, because the bare scope is **shadowable** and a wrong type is worse than no type. **−12 rows, exactly as predicted; `incremental` and `file_watcher` both to zero and nothing else moved** |
| `nxnnxe` | P2 | *(the ranked #1 after `x3x0qj`, and the allow-list-with-nothing-behind-it shape a **fourth** time)* every method `@derive` synthesizes had its **name** affirmed by `tc_method_resolvable_on_type` and **no signature anywhere** — so `to_json` / `from_json` / `clone` / `debug` / `eq` / `cmp` and the str-backed-enum statics all resolved to `TYPE_UNKNOWN`. Both halves failed open: `let bad: Int = u.to_json()` compiled, linked and **ran**, and `User.from_json(42)` escaped to `cc`. Fixed the `qjfwc6` way — **a table, not arms**. **−19 rows, exactly as predicted, and every one of the seven named files went to zero.** Three byproducts filed: `pvhaew`, `bf0jnj`, `169kjt` |
| `cjtxxr` | P2 | *(the largest actionable entry left, and the allow-list shape a **tenth** time)* calling a **closure-typed struct field** — `route.callback(req)`, `srv.error_handler.on_error(req, msg)`, the `handler: fn(Request) -> Response` the spec puts inside `type Route` — was the **last unchecked callable shape in the language**: return type, arity and every argument type failed open together. The closure *variable*, the IIFE, a fn-typed *parameter* and even the same field **hoisted through a `let`** were all already checked, which proved the field's tid was a real `TyKind.Fn` and only the dispatch was missing. `tc_method_resolvable_on_type` clause (d) fail-opened on `is_callable_field_name`, a **global** name list, on the strength of a comment that `nz7drz` had falsified. **Three silent miscompiles** (one propagating into the returned struct's own field access) plus five `cc` escapes. **−12 rows against 11 predicted**, the twelfth being a downstream `let` two lines below a cured producer |
| `9md3r1` | P2 | *(the six flat-tail enum spellings that were one cause)* a **qualified** struct-style variant literal — `Enum.Variant { field: v }`, the spelling `error[AmbiguousConstruction]` itself tells the user to write — resolved to `TYPE_UNKNOWN`, because `lookup_named_type` strips a dotted name to its **suffix** and the suffix of `Enum.Variant` is the variant, never a type. **Both phases had a mirror-image half**: codegen preferred a **global** variant-name→enum map over the explicit prefix, so `Right.Item { v: 2 }` emitted a `blink_Left` even after typecheck was fixed. **Seven fail-open modes**, including three silent miscompiles (one passing a wrong-nominal-type value to a typed parameter) and one **false positive** — correct code *rejected* with `expects Left, got Item` when an unrelated enum happened to be named like the variant. **−12 rows, exactly as predicted, all `__main__`**; all 12 landed in class B, and root-causing that landing found the Stage-3 hazard below (`tk_to_ct`'s Enum arm targets a dead `CT_ENUM`). Three byproducts filed: `x056sx`, `krwywm`, `5fn53v` |
| `hgd2az` | P2 | *(the spec's own concurrency primitive, and the fix the divergence counter could not see)* every seam that consumes a `Channel[T]` element — `send`, `recv`, the `for v in ch` drain — read the **flat** `get_var_channel_inner`, and that field was stamped by looking the initializer's emitted **C expression** up as a variable name, which never hits, so **every channel in every program** was `CT_INT`. The `CT_STRING` arms in both consumers were **dead by keying**. **Seven fail-open modes**, including two `cc` escapes, a `Bool` printing as `1`, and **silent data loss**: `(void*)(intptr_t)0` *is* `NULL`, `NULL` is the end-of-stream sentinel, so a drain over a channel whose first value is `0` printed nothing and dropped every value behind it. Fixed by **boxing** — one rule, no per-type cast — with the element type read from the node's tid: codegen's **first consumer of the Stage-1 structural accessors**. Only **−3 rows** (the corpus's three `channel.new[T]` sites), because the corpus had **zero** class-B Channel rows *before* the fix while all seven modes were live — see the caveat below |
| `nrrs28` | P2 | *(the untyped-receiver shape a **sixth** time)* `Template[C]` was not a type, so the phantom context parameter and all seven methods were unenforceable — **−9 rows**, section below |
| `ps5br9` | P2 | *(the **last** untyped receiver in the language)* the `ffi.scope()` receiver had no `TyKind` while codegen had carried `CT_FFI_SCOPE` and a four-method emitter since the FFI surface landed — **−5 rows**, and the family-A `tid=? flat=Ptr[Int]` cell is gone. Its residual is a *pointee* cell: **`0dtbe6`**, 238 class-B rows over 20 sites, the largest such population in the corpus |
| `ta51an` | P2 | *(the spec's own disambiguation form)* `Trait.method(receiver, args)` — §3c's **only** way to disambiguate a method two traits both define — was unchecked in typecheck and mis-resolved in codegen, so a **wrong trait qualifier silently called the other trait's method**. **−1 row**; byproduct `td3yx5` (`type:spec`: `Bool`/`Int` interchange contradicts the 5-0 no-truthiness vote) |
| `wnbsen` | P2 | *(the last unblocked family-A cause)* `tc_scoped_value_memo` had no `IfExpr` arm, so a block-`let` whose initializer ends in an `if`/`else` built from a block-local had **no type at all** — **−1 row, family A 101 → 100**, section below |
| `gmb211` | P2 | *(`wnbsen`'s byproduct, one line above it)* the recovery is gated on `inferred_tid == TYPE_UNKNOWN`, so a **partially** erased `List[?]` counted as an answer and the memo was never read. Every carrier erased; three silent miscompiles and a `cc` escape. Class B, so family A holds at **100**; fixed with a hole-only predicate plus a **position-wise** fill that cannot overwrite a concrete position or pin a metavar |
| `08a267` | P2 | *(the four `tid=List[?]` rows `gmb211` did **not** move)* **CLOSED, −4 rows.** A list literal whose **first** element is a spread — `[..a]` — inferred `List[?]`, because `infer_type`'s ListLit arm takes the element type from element 0 only and has **no `SpreadExpr` arm**. Position is the axis: `["q", ..a]` was already correct. A **silent wrong value**, not just a laundered declaration. Fixed by naming the right concept — what an element *contributes*, which for a spread is its operand's element — in one function; the signature diff is those four rows and nothing else. Byproducts: `q1pxhm`, `ehn3s9` |
| `q1pxhm` | P2 | *(the check §2.16 mandates and neither phase performed)* **CLOSED, divergence-neutral (+31 rows into family D, from the fix's own `let k: TyKind`).** the spread source's element type is never compared against the literal's — `sections/02_syntax.md:863`, panel vote 5-0 — so `["q", ..a]` with `a: List[Int]` **SIGSEGVs** (exit 139) with no diagnostic at all. Depends on `08a267`: a contribution cannot be compared until it can be computed |
| `ehn3s9` | P2 | **CLOSED, −2 rows (the shape flipped to `agree` in BOTH files carrying it).** *(`08a267`'s codegen half, and **not** a prerequisite — the first Stage-3 authority flip, at one seam.)* `emit_list_lit` recovers a leading spread's element with `get_list_elem_type(src_str)`, keyed on the **emitted C expression string** — the `hgd2az` hazard shape — so a variable source hits and a **call** source misses and defaults to `Int`. `let b = [..mk_strs()]` prints the `Str` pointer as an integer, and a `Str`-declared read of that element makes `.len()` a codegen `error[UnresolvedMethod]`. The tid already holds `List[Str]`, so the authority flip **fixes** this rather than breaking it; the shape is pinned in the corpus and the counter names it |
| `f9hgt9` | P2 | *(the level `gmb211` stops short of)* an unannotated **nested** list literal — `let ys = [["ab"]]`, no block-`let` anywhere — fabricates an `Int` element at depth 2; the tid is now `List[List[Str]]` and codegen's flat side is `List[List[Int]]`. A class-B cell Stage 3's lowering subsumes |

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

| | before `nz7drz` | after `nz7drz` | after `bfq7nf` | after `3c4g71` | after `zs7khh` | after `2r96m9` | after `rbd0a4` | after `w13xgb` | after `jzvxav` | after `h3q81d` | after `qjfwc6` | after `w089a0` | after `x3x0qj` | after `nxnnxe` | after `bf0jnj` + `pvhaew` | after `cttrag` | after `n84s1p` | after `jvy35h` | after `rb5wvb` | after `cjtxxr` | after `9md3r1` |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| **total cells** | 423 | 421 | 409 | 407 | 405 | 404 | 404 | 405 | 404 | 402 | 402 | 402 | 403 | 406 | 406 | 406 | 404 | 404 | **403** | **401** | **396** |
| family A (`tid=?`) cells | 84 | 61 | 47 | 45 | 35 | 34 | 34 | 33 | 32 | 28 | 28 | 28 | 26 | 23 | 23 | 23 | 21 | 21 | **20** | **18** | **12** |
| family A rows | 1323 | 1224 | 1190 | 1050 | 1015 | 661 | 504 | 327 | 310 | 261 | 216 | 203 | 193 | 174 | 174 | 162 | 154 | 148 | **143** | **131** | **119** |
| `Fn`-flat `tid=?` cells | 16 | 2 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | **0** | **0** | **0** |
| agree | 362979 | 363711 | 363924 | 364187 | 364289 | 364674 | 364831 | 364883 | 364934 | 365243 | 365505 | 365580 | 365705 | 366051 | 366051 | 366125 | 366133 | 366139 | **366205** | **366248** | **366400** |
| diverge rows | 5008 | 5003 | 4976 | 4837 | 4828 | 4474 | 4317 | 4296 | 4279 | 4249 | 4204 | 4191 | 4190 | 4185 | 4185 | 4173 | 4165 | 4190 | **4186** | **4174** | **4174** |
| missing | 14 | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 1 | **1** | **1** | **1** |

**`total cells` rose for three sweeps running (402 → 403 → 406) while `family A cells` fell
(28 → 26 → 23), and that is the campaign turning a corner rather than losing ground.** A family-A
cell is one *shape* of "codegen has no type"; the cells replacing them are class B, where typecheck
holds the right structured type and the flat `(CT_*, sname)` pair cannot spell it — so one erased cell
splits into as many cells as there are real types behind it. Class B is deleted wholesale by Stage 3's
`c_type_from_tid` and Stage 4's removal of `sv_tp`; family A is what has to be fixed one cause at a
time. Cell count going **up** for that reason is the instrument working.

The last column covers **two** fixes, `bf0jnj` and `pvhaew`, and reproduces the `nxnnxe` column
**digit for digit** — both were swept independently and both are divergence-neutral by measurement
rather than by inference. That is the expected result for this kind of fix and worth stating plainly:
a correctness fix that adds a missing dispatch arm or writes an already-known type onto a second
channel removes no *erasure*, so it moves no row. `ya8qyf` was called neutral by inference; these two
have their own sweeps.

**The `after cttrag` column is the first where the total number of comparisons *rises*, and the cause
is the fix's own source, not the corpus.** Total bumps = `agree + diverge + missing` = one per
`emit_let_binding.decl` call, so the total is a count of emitted `let` declarations. It went
370237 → 370299 (+62) while `diverge` fell 12 and `agree` rose 74. All of it is accounted: `cttrag`'s
fix adds **two `let` declarations to `src/typecheck.bl` itself** (`l_mod_key`, `qual_mod`), and 31 of
the 874 basis files compile `typecheck.bl` — 31 × 2 = 62. The per-site aggregate confirms only one
site moved at all, and the per-file deltas are exactly `+2` for those 31 roots plus `-4 diverge /
+4 agree` for the three that also compile `incremental.bl` and `file_watcher.bl`. So `agree`'s +74 is
62 new comparisons and 12 conversions, nothing else. **Worth stating because the tempting reading is
wrong:** "more comparisons after an erasure fix" invites the story that the erasure was suppressing
downstream comparisons, and it was not — the instrument counts a row for an unknown type just as it
does for a known one. Any future column whose total moves should be traced to added or removed `let`
declarations first.

The `after n84s1p` column holds the total steady at 370299 (`agree + diverge + missing`), which is the
control for the paragraph above: that fix adds no `let` declaration to the compiler's own source, and
the total does not move. All 8 rows it removed are conversions.

**`after jvy35h` is the cleanest instance of that arithmetic yet, and it goes the other way: `diverge`
went UP by 25 in a sweep that removed 6 family-A rows.** Total 370299 → 370330 (+31), and every figure
resolves without a residue. The fix adds **one** `let` declaration to `src/typecheck.bl` (`let ek =
type_kind(elem)`), 31 of the 874 basis roots compile that file, and all 31 new comparisons land in
`diverge` rather than `agree`: `var=ek tid=TyKind flat=Int at=typecheck:9285`. The flat universe cannot
spell an enum, so it says `Int`. So `Δdiverge = 31 − 6 = +25` and `Δagree = +6`, the 6 being exactly the
conversions. **The 31 new rows are class B, not family A** — both sides have a type and they disagree —
which is why `family A rows` falls while `diverge rows` rises, and why neither cell count moves: the
`(emit_let_binding.decl, TyKind, Int)` cell already held 682 rows across 22 sites and now holds 713
across 23. Stage 3's `c_type_from_tid` deletes that whole cell in one stroke. **The lesson for reading
this table: `diverge rows` is not the campaign's progress metric and never was.** Writing one more
enum-typed `let` anywhere in the compiler raises it by 31 without a single new defect; `family A rows`
is the number that counts causes.

**`after rb5wvb` shows the third variant of the same arithmetic — the fix's own `let`s land in `agree`,
so the total rises and `diverge` still falls.** Total 370330 → 370392 (+62): two new `let` declarations
in `src/typecheck.bl` (`inst_args`, `inst_got`) × 31 basis roots, and both are `Int`, which the flat
universe spells `Int` too, so all 62 agree. `Δagree = 62 + 4` and `Δdiverge = −4` against **5** retired
family-A rows, because 4 of the 5 converted to `agree` and the fifth moved from family A into an
*existing* class-B cell: `tests/test_time.bl:64` went `var=el tid=? flat=Duration` →
`tid=Duration flat=Duration`. That cell was already there, which is also why `total cells` falls by one
(the family-A cell vanished and no new cell was created) — the three arithmetic variants seen so far
are new-`let`s-into-`diverge` (`jvy35h`), no-new-`let`s (`n84s1p`), and new-`let`s-into-`agree` (here).

**And that fifth row exposes a measured Stage-3 artifact worth recording, because it is not a defect and
must not be "fixed" by an arm: every correctly-typed `Instant`/`Duration` `let` in the corpus is already
a class-B divergence row.** 27 `tid=Duration flat=Duration` plus 13 `tid=Instant flat=Instant` in the
874-file basis, all reading as a disagreement between two spellings of the same name. `TyKind` has no
`Instant` or `Duration` variant, so typecheck models both as `TyKind.Struct(name)`, and `tk_to_ct` maps
`TyKind.Struct` to `CT_STRUCT` — while the flat universe carries dedicated `CT_INSTANT` and
`CT_DURATION` slots. `ty_tp_same_shape`'s `ct != tp_get_kind(tp)` gate therefore fails *before* it ever
reaches the name comparison two lines below. These 40 rows are the flat universe having a kind that the
structured pool deliberately does not, they are counted as class B correctly, and they disappear with
`sv_tp` in Stage 4. It is the mirror image of the `TyKind`-flat-`Int` cell from `jvy35h`: there the pool
has a kind the flat side cannot spell, here the flat side has a kind the pool does not.

**`after cjtxxr` is the arithmetic closing with no residue at all, and it is the column to point at when
someone doubts the instrument.** One `let` added to `src/typecheck.bl` (`fld_tid`) × 31 basis roots =
+31 total (370392 → 370423), all 31 into `agree` because both sides spell it `Int`; 12 family-A rows
retired, all 12 converting rather than moving to another cell; so `Δagree = 31 + 12 = +43` and
`Δdiverge = −12`, and `total cells` falls by 2 with no new cell created. Every figure in the column is
predicted by those two facts.

**And its twelfth row is the argument for why a family-A row count is a floor on the damage, not a
measure of it.** Eleven rows were predicted from the ranking — the ten `var=resp` and the one `var=req`.
The twelfth, `var=hdr_val tid=? flat=Str at=__main__:155`, is `let hdr_val =
req.headers.get("X-Test").unwrap()` **two lines after** the `req` the fix cured: with `req` untyped its
`headers` field, the `Map` lookup and the `unwrap` were all untyped too, and typing the producer typed
the consumer for free. One missing signature was costing more counter rows than the site that lacked it,
and the ranking cannot show that in advance because the downstream row's `var=` and `flat=` name a
different shape entirely. Expect a fix's measured reduction to exceed its predicted one, and treat the
excess as a hint about what else the same hole was suppressing.

**The counter is not a severity ranking, and `n84s1p` is the clearest proof so far.** The worst defect
in that ticket — `env.var`, a *silent miscompile* that compiled, linked, ran and printed `<value>` for
`let bad: Int = env.var("HOME")` — contributed **zero divergence rows**, because `env.var` is nearly
always consumed as `env.var(x) ?? ""` and the coalesce handed the `let` a `Str` that codegen was
perfectly happy to hold. The instrument watches whether codegen *has* a type, not whether typecheck's
answer is *right*. Both silent miscompiles in that ticket were found by auditing the allow-list against
the codegen arms; the counter noticed one of them incidentally, at one site, and only because the value
was bound directly. Rank by rows to schedule Stage 3 — the rows are what `c_type_from_tid` has to be
able to answer for — but never read a low row count as "this one matters less".

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

*(Confirmed: `w089a0` retired exactly those 9, and `tests/test_db_stmt.bl` is down to the single
`nrrs28` row. The 6-vs-9 split predicted here is the one the closing sweep measured.)*

Test: `tests/test_h3q81d_effect_op_signatures.bl`, 14 rows — 11 red before, all green after. It uses
a plain user-declared effect rather than `std.db`, because the registry is shared and a sidecar adds
nothing to the mechanism; the depth-2 `Result[Option[Str], Str]` row is the `db.query_one` shape in
miniature, and it is the shape that forces codegen's seventh and eighth flat fields. Rows cover
`List`/`Option`/`Int`/`Result[List]`/`Result[Option]`/`Void` returns, the argument check, two
cc-escape assertions, an inferred-result method chain, keying by handle **and** op (a same-named
method on an unrelated type keeps its own signature), and two effects sharing an op name with
different return types. **Helper trap:** `expect_no_error(src, tag, "")` asserts
`!output.contains("")`, which is always false — pass the code you expect *not* to appear.

### `qjfwc6` — every namespace intrinsic but two had no signature in typecheck (CLOSED)

The #1 remaining cause after `h3q81d`, and the same shape one namespace over: codegen holds the
table, typecheck holds two entries. Each emitter at `codegen_methods.bl:2651-3640` sets
`expr_result_type` for its own method — `blink_tcp_connect` is `CT_INT`, `blink_stdin_read_line` is
`CT_STRING`, the `env.args` argv loop is `CT_LIST`/`CT_STRING` — and that is where the C types come
from. Typecheck's side of the gate (`typecheck.bl:9424`, `is_intrinsic_method(obj_name, method) != 0`)
had a body of exactly two arms, `time.read` and `time.sleep`, so every other intrinsic fell out of it
with no type at all. `TYPE_UNKNOWN` unifies with anything, so both halves failed open.

**The declared-type half was not escaping to `cc` — it was a silent miscompile.** That is new; the
four earlier causes at least reached the C compiler.

```
let bad: Str = net.connect("localhost", 8080)   ->  compiles, links, RUNS, exit 0
```

An `Int` reinterpreted as a `char*` and printed. **And arity was a compiler panic**: codegen indexes
the argument list positionally and unconditionally, so `net.listen("localhost")` died at
`unwrap called on None at src/parser.bl:111` rather than reporting anything.

**One regen**, because it is one behavior: typecheck learns the signatures.
`register_ns_intrinsic_sigs` registers **one `FnSigEntry` per intrinsic** into `fnsig_pool` under the
qualified key `{namespace}.{method}` — a key no user function can spell, since `register_fn_sig`
separates a module qualifier with a **colon**. So the whole existing fnsig machinery applies with no
new data structure: `lookup_fnsig` finds it, `check_arg_shapes` reports *"argument 2 of 'net.listen'
expects Int, got Str"*, and `.ret` is the return tid. It is called from the register pass beside
`register_ue_op_sigs`, because both are the same act. The call site is one arm after the `time.*`
arms, gated `nr_is_defined(obj_name) == 0 && is_intrinsic_method(obj_name, method) != 0` —
deliberately **not** on `is_import_module_name` like the arms above it, since an intrinsic needs no
import (that is what makes it intrinsic) and `is_intrinsic_method` already restricts the namespace.
The arity check reuses the ordinary fn-call wording verbatim.

Registered: `net.connect/listen/accept/read/read_all/read_line/read_bytes/write/write_bytes/`
`set_timeout/close`, `io.read_line`, `term.isatty/width/height`, `env.args`.

**A table, not an arm per method, and that is the point.** Codegen already carries one arm per
intrinsic; a second set of arms in typecheck would drift from it method by method, which is exactly
how the two representations came apart in the first place.

**Blast radius zero**: 638/638 test files green, `fmt` 1496, gen1-vs-gen2 per-module byte-equal. Every
intrinsic call in the corpus was already correctly typed *and* correctly ordered — merely unchecked.

| | after `h3q81d` | after `qjfwc6` | delta |
|---|---:|---:|---:|
| family A rows | 261 | **216** | **−45** |
| family A cells | 28 | 28 | **0** |
| total cells | 402 | 402 | 0 |
| diverge rows | 4249 | 4204 | −45 |
| agree | 365243 | 365505 | +262 |
| missing | 1 | 1 | 0 |

**`std_net_tcp` 40 → 0**, `lsp` 6 → 4, `__main__` 174 → 171. Nothing rose. The five `net.*` bindings
at `lib/std/net_tcp.bl:68,83,92,128,137` were 40 of the 45 on their own, because every net-using root
re-derives them — the mirror image of the flat-40 reading that stood across five sweeps.

**The cell count did not move at all, and the cell set is byte-identical.** This is the clearest case
yet that **cells are a lower bound on causes, not a count of them**: all 45 rows sat on
`(site, tid=?, flat)` triples — `flat=Int`, `flat=Str`, `flat=Bytes` at `emit_let_binding.decl` —
that other still-open causes also produce. Stage 3's exit gate is the counter at 0, so this costs
nothing there, but a cause-by-cause phase must be ranked on rows.

**Three groups deliberately left out**, each because *what its signature is* is an open question, not
where it lives:

- **`fs.read/write/list_dir/remove` → `jr4xf7` (`type:spec`).** `sections/04_effects.md:73,1053`
  spells `fs.read(path)?` as a `Result` and `:157,215` names the lister `fs.list`, while codegen emits
  a bare `const char*` from `blink_read_file` and calls it `list_dir`. Giving it the codegen signature
  would write *"an FS read cannot fail"* into the type system by accident. 4 rows, held.
- **`io.debug`, `io.read_bytes`, `env.var` → `n84s1p` (P3).** `is_intrinsic_method` disagrees with the
  arms **in both directions** — `io.debug` is listed and emitted by no arm (it fails closed at the
  codegen backstop), while `io.read_bytes` and `env.var` have arms and are not listed, so they take
  the `== 0` path and resolve through `lookup_fnsig` on the **bare** method name. 5 rows.
- **`net.request`** — its `Result[Response, NetError]` needs two stdlib struct types a consuming
  module need not have imported. 0 rows.

A speculated collision was **tested and does not reproduce**: `import std.libc` (which has
`read_bytes -> Result[Bytes, Errno]`) plus `let bad: Str = io.read_bytes(4)` passes `blink check`, so
the bare-name lookup misses there and the call stays untyped. The hazard in `n84s1p` is structural,
not observed — recorded that way on purpose.

Test: `tests/test_qjfwc6_ns_intrinsic_signatures.bl`, 27 rows — 23 red before, all green after. Rows
cover a declared-type compare over every return shape (`Int`, `Str`, `Bytes`, `Void`, `List[Str]`),
the argument check including the reversed-argument and the `write`/`write_bytes` `Str`-vs-`Bytes`
pair, two escape assertions, an inferred result carried into a following method call, and the
shadowing control (`let net = Sock { .. }` keeps its own `connect`, both directions).

### w089a0 — the with-resource `as` binder carried no type (CLOSED)

**Mechanism.** `tc_check_body`'s `WithBlock` branch bound the resource name with the **untyped**
spelling, `nr_define(node_name(wh_item2))`, and walked the resource expression on the very next
line. So the type was never missing — it was **dropped at the binding site**, one line above the
walk that computes it. The entry carried `TYPE_UNKNOWN`, which unifies with anything, so both
halves failed open: a declared type over `x.method()` was never compared, and the arguments to
that call were never checked.

**The declared-type half was a silent miscompile, the second one this campaign has found.**

```blink
with make() as r {
    let bad: Str = r.value()   // Res.value() -> Int
    io.println(bad)
}
```

compiled, linked, ran, exit 0, and printed `7`. `blink check` reported `ok`. The argument half
(`r.scaled("2")`) reported **nothing at all** from `check` but did escape to `cc`
(*"argument is of type"*), so it was a `cc` escape rather than a third miscompile.

**The fix is a binding, not an arm** — the second cause in a row whose whole repair is to use a
typed spelling that already existed. `tc_bind_with_resource` walks the resource, infers it,
publishes the tid **on the `WithResource` node** (exactly as the `LetBinding` arm publishes a
`let`'s tid — `infer_type` memoizes expression nodes only, so a resource clause carried no tid
at all), and binds the name with `nr_define_typed`. Codegen's `WithResource` emit gained the
matching Stage-2 stamp, `set_var_ty(binding, tc_lookup_node_tid(item))`, placed after all four
resource paths (`BlockHandler`, `Closeable`, `CT_FFI_SCOPE`, plain) and advisory only — no emit
decision changed. **An unresolvable resource binds `TYPE_UNKNOWN`, i.e. exactly what it bound
before**, which is what keeps the `ffi.scope()` receiver (`ps5br9`, not a Blink type at all)
working untouched.

The standalone `NodeKind.WithResource` arm in `tc_check_body` is deliberately left a value-walk:
it is a fallthrough route with no `nr_push_scope` around it, so binding a name there would leak
the binder into the enclosing scope.

| | after `qjfwc6` | after `w089a0` | delta |
|---|---:|---:|---:|
| family A rows | 216 | **203** | **−13** |
| family A cells | 28 | 28 | **0** |
| total cells | 402 | 402 | 0 |
| diverge rows | 4204 | 4191 | −13 |
| agree | 365505 | 365580 | +75 |
| missing | 1 | 1 | 0 |

**Attribution is exact, and it is three files — all three with-resource.** `test_db_stmt.bl`
10 → 1, `test_schfpd_with_qmark_binding.bl` 2 → 0, `test_arena_clause6_resource.bl` 2 → 0.
Nothing else in the corpus moved by a row, and nothing rose. The ticket predicted 9 rows in
`test_db_stmt.bl` and exactly 9 retired; **the one survivor there is `nrrs28`** —
`site=emit_let_binding.decl var=tag flat=Int at=std_db_sqlite:140`, the `tpl.type_tag(i)` row.
That closes the decomposition of the original 72-row `db.*` bucket into its four causes:
`h3q81d` (~51), `jzvxav` (12), `w089a0` (9), `nrrs28` (9, the last one standing).

**The cell set is byte-identical for the second sweep in a row** — not just the count, the set,
family A and total alike. Two consecutive fixes retiring 58 rows between them without moving one
cell is now the settled reading of the instrument, not a surprise: a cell is a
`(site, tid=?, flat)` triple, and `emit_let_binding.decl` × `flat=Int` is produced by most of the
remaining causes at once.

**Blast radius: one test file, and the diagnostic it gained is correct.**
`tests/test_schfpd_with_qmark_binding.bl` uses `with connect_handle(url)? as conn` directly in two
test bodies over `Result[Connection, PgError]`, and `PgError` had no `Display` impl — which
`sections/02_syntax.md` §2.20 / §3c.2 require for `?` in a test body (E0514, `fmj80a`). **Three**
rows fired, and the third is the interesting one: besides the two with-resource `?` operators,
`conn.query("SELECT 1")?` **inside** the block also fired, because its return type is only
knowable once the receiver is typed. That is the fix demonstrating itself through an unrelated
gate. The fixture got `impl Display for PgError`; no test was changed or removed.

Verified: `task regen` EXIT=0; `task ci` EXIT=0 — **639/639** test files, `fmt` 1498 passed / 86
skipped, gen1-vs-gen2 per-module byte-equal.

Test: `tests/test_w089a0_with_resource_binder_type.bl`, 18 rows — 13 red before, all green after.
Rows cover the declared-type compare over `Int` / `Str` / `List[Str]` returns and a plain field
read; both parser spellings of a resource (`expr as x` and `x = expr as x`); the `.unwrap()` chain
that is the `db.prepare` shape; the second resource of a comma-list; an outer binder read from
inside a nested `with`; the argument check; two escape assertions (including *"must not print
7"*, the miscompile itself); two inference-carry rows; and four controls that **run** — every
correct spelling, both spellings again, the `ffi.scope()` shape, and `with arena` (no binder at
all).

The `ffi.scope()` control had to be written as a comparison rather than an interpolation, which
turned up a byproduct bug: **`jw2yz2`** — a `Ptr[T]` ffi-struct field read has no type, so
`let v = p.fd.read()` emits *"variable declared void"* and `"{p.fd.read()}"` compiles, runs, and
prints the literal text `<value>`. Third link in the same `Ptr` chain as `w13xgb` and `ps5br9`.

### x3x0qj — an immediately-invoked closure was entirely unchecked (CLOSED)

**Mechanism.** `infer_type`'s `NodeKind.Call` arm branched on `callee_kind` for
`NodeKind.Ident` and `NodeKind.FieldAccess` **only**, then fell to `return TYPE_UNKNOWN`
without inferring the arguments or looking at the callee at all. A closure **literal** in callee
position — an immediately-invoked closure — hit that fallthrough. A closure **variable** call was
already fine (the `Ident` branch reads the local's `TyKind.Fn` tid, arity-checks, per-arg-checks
and answers `fn_ty.inner1`), so this was specific to the literal-callee shape.

**One missing branch, three things unchecked at once** — and this is the reason the cause was
worth taking ahead of larger row counts:

1. the call's **result type**, and `TYPE_UNKNOWN` unifies with anything, so
   `let bad: Str = fn() -> Int { 7 }()` compiled, linked, ran, exit 0, printed `7`, and
   `blink check` said `ok` — **the third silent miscompile of this campaign**;
2. the **arity** — `fn() -> Int { 7 }(1, 2)` escaped to `cc` (*"too many arguments"*);
3. the callee closure's **body** — `fn() -> Int { "notint" }()` escaped to `cc`
   (*"returning char \* from a function with return type int64\_t"*).

Half 3 is the **third position** of `1hg8b6`'s family. That ticket fixed call-**argument**
position (`tc_check_callable_arg_bodies`, commit `82a0dbd`) and still scopes
struct-literal-**field** position; **callee** position was neither, and `tc_check_body`'s `Call`
arm reached only the arguments.

**The fix is dispatch, not inference.** `infer_type`'s `Closure` arm already answers a real
`TyKind.Fn` tid built from the literal's own annotations (measured: `tid=Fn(Int) -> Int`), so the
new `callee_kind == NodeKind.Closure` branch infers the callee and hands the tid to the same
checking the closure-variable path performs. That checking was extracted verbatim out of the
`Ident` branch into `tc_check_call_against_fn_tid(fn_tid, args_sl, label, node)` — the two shapes
differ only in how the diagnostic names the callee (`"function 'g'"` vs `"closure"`), so the
label is the only parameter. `tc_check_body`'s `Call` arm gained a callee walk for half 3.

| | after `w089a0` | after `x3x0qj` | delta |
|---|---:|---:|---:|
| family A rows | 203 | **193** | **−10** |
| family A cells | 28 | **26** | **−2** |
| total cells | 402 | **403** | **+1** |
| diverge rows | 4191 | 4190 | −1 |
| agree | 365580 | 365705 | +125 |
| missing | 1 | 1 | 0 |

**Attribution is exact and the prediction was exact: the ticket named 10 rows in three files, and
all three files went to zero.** `test_fmt_iife_with_block.bl` 5 → 0,
`test_k4qp2c_test_body_compound_propagation.bl` 3 → 0, `test_promote_fwd_decl_ordering.bl` 2 → 0.
Nothing else in the corpus moved by a row.

**This is the first fix whose rows did not leave `diverge` — they MOVED, family A → class B, and
that is the outcome the plan wants.** Family A lost two cells and the total gained three:

```
- bucket=diverge site=emit_let_binding.decl tid=?                      flat=Result[Int, Void]
- bucket=diverge site=emit_let_binding.decl tid=?                      flat=Result[Void, Void]
+ bucket=diverge site=emit_let_binding.decl tid=Result[Int, IIFEErr]   flat=Result[Int, Void]
+ bucket=diverge site=emit_let_binding.decl tid=Result[Int, PgError]   flat=Result[Int, Void]
+ bucket=diverge site=emit_let_binding.decl tid=Result[UserRow, PgError] flat=Result[Void, Void]
```

Nine of the ten rows are now *"typecheck holds the right type and the flat pair cannot spell
it"*: `Result[Int, IIFEErr]` has two children and the flat `(CT_*, sname)` pair holds one, so the
**error type erases to `Void`** — and where both children are structs (`Result[UserRow, PgError]`)
both erase. The tenth row (`flat=Int`) simply agrees now. Rows leaving family A for class B are
not a regression: class B is exactly what Stage 3's `c_type_from_tid` and Stage 4's deletion of
`sv_tp` remove wholesale, whereas family A is what has to be fixed one cause at a time. `−1`
`diverge` with `−10` family A is that transition, measured.

`agree` rose by **125** on a `−10` fix, more than any prerequisite so far, because walking the
callee body infers every node inside it — the divergence instrument sees a body that was
previously invisible to typecheck entirely.

Verified: `task regen` EXIT=0; `task ci` EXIT=0 — **640/640** test files, `fmt` 1500 passed / 86
skipped, gen1-vs-gen2 per-module byte-equal.

Test: `tests/test_x3x0qj_iife_callee_unchecked.bl`, 20 rows — 14 red before, all green after. Four
declared-type compares (`Int`, `Str`, `Result`, and an IIFE taking arguments); the result as a
receiver, asserting the diagnostic reads *"on type Int"* and **not** *"on type ?"*; arity over and
under; the argument type; three body rows (return mismatch, a bad declaration inside the body, and
the body in **statement** position rather than initializer position); three `cc`-escape assertions
including *"must not print 7"*, the miscompile itself; three run controls (every correct spelling,
a `Result` return, nested IIFEs); and **three closure-variable controls that guard the
extraction** — the arity wording `function 'g' expects 1 argument(s), got 2` and the argument
wording `function 'g' argument 0 expects Int` asserted verbatim, plus a run.

**What it did not fix, and the evidence is now sharper.** A container return through an IIFE still
fails:

```
let m = fn() -> Map[Int, Str] { Map() }()
let l = fn() -> List[Int] { [1, 2, 3] }()
error[UnresolvedMethod]: unresolved method '.len' on type Map[Int, Str] in 'main'
```

Before this fix that diagnostic read *"on type ?"*. It now **names the type correctly**, which
makes it a clean instance of `r398vj` (the closure-call return recovered by re-parsing the emitted
C signature string, so only `Int` / `Str` / `Option` survive) — noted on that ticket, since the
IIFE form was not in its description. Typecheck holds the right tid; codegen throws it away.

### nxnnxe — `@derive`-synthesized methods had no signature in typecheck (CLOSED)

**Mechanism.** `tc_method_resolvable_on_type` (`typecheck.bl:346-380`) affirms the *names*: clause
(c) reads the `@derive` annotation off the type declaration and passes `to_json`, `from_json`,
`clone`, `debug`, `eq`, `cmp`; clause (c') fail-opens the str-backed-enum statics
(`if obj_k == TyKind.Enum && (method == "to_str" || method == "from_str") { return 1 }`).
**Nothing was behind either clause.** No `FnSigEntry` carried a return type or parameter types for
any of them, because `@derive` synthesizes the method in *codegen* — there is no `node_type_ann` to
read and no user-written fn to register.

`TYPE_UNKNOWN` unifies with anything, so both halves failed open at once:

1. the **declared-type compare** — `let bad: Int = u.to_json()` compiled, linked, **ran**, exit 0,
   and `blink check` said `ok`. For the five-method MVCE it printed
   `{"name":"a","age":1}<value><User><value>open`. **The fourth silent miscompile of this campaign.**
2. the **argument check** — `User.from_json(42)` escaped to `cc`. A missing tid produces *no
   divergence row at all* for this half, which is why the ticket's row count only measured half 1.
3. a **cascade**: `from_str` answering UNKNOWN made the `Some(v)` binder Unknown too, so the *next*
   method call on `v` read `on type ?` as well. One missing signature poisons a chain.

**This is the allow-list-with-nothing-behind-it shape for the fourth time** — after
`is_builtin_method` (172 names, 73 with no arm), `is_intrinsic_method` (`qjfwc6`, `n84s1p`), and now
`tc_method_resolvable_on_type`. **And the fix is the same one every time: a table, not arms.**
`register_derive_method_sigs(program)` walks the type declarations once and mints one signature per
derived method per deriving type, under the bare `{Type}_{method}` key that *both* resolution paths
already spell — the instance path at `:9461` and the static path at `:9647`. It runs **last** in
`check_types`, after every user-fn and impl-method registration, and `register_derive_method_sig`
skips a key a program has taken for itself (`fnsig_map` hit, or `tc_method_trait_count >= 1`), so a
hand-written method of the same name always wins. The instance path's `check_arg_shapes` then comes
free — which is the whole reason `u.eq(42)` and `u.cmp("nope")` now error.

Two names are **deliberately absent** from the table, and each is a filed ticket:

- **`hash`** — `p.hash()` is a hard `E0505` today (`pvhaew`, filed as a byproduct). Four places
  should agree and one does not: `codegen_derive.bl:123` registers the entry, `:199` emits
  `uint64_t {T}_hash({T} self)`, typecheck's clause (c) passes it, and the derive-dispatch blocks at
  `codegen_methods.bl:5176` (structs) / `:5225` (enums) have **no `hash` arm**, so control falls to
  the E0505 backstop at `:5382`. It works *internally* — kops calls `{T}_hash` for struct-keyed
  `Map`/`Set` — which is why it went unnoticed. **A signature for an uncallable method would claim
  it works**, so `hash` waits for `pvhaew`. This is the same defect class **inverted**, the fifth
  sighting: here the allow-list is right and the *dispatch table* is short.
- **`JsonValue` / `JsonError`** — `sections/03_types.md:2352` declares
  `to_json(self) -> JsonValue` and `from_json(JsonValue) -> Result[Self, JsonError]`, and
  `rg JsonValue src/ lib/` reads **0**. Codegen emits `const char*` and
  `blink_Result_{tag}_str`. I registered `Str`, matching the emitted C, because the spec spelling
  would reject every program that compiles today — filed as `169kjt` (`type:spec`) with the two ways
  out named, and `register_derive_method_sigs` is the one place the return types change if a real
  `JsonValue` wins. Recorded alongside it: the str-backed-enum feature has **no spec section at
  all**; `tests/test_str_backed_enum.bl` is its only definition.

`tc_is_str_backed_enum_decl` deliberately duplicates codegen's detection rule
(`codegen_stmt.bl:8749-8765`: **all** variants carry a string value, and there is at least one)
rather than sharing it, because codegen imports typecheck and not the reverse.

| | after `x3x0qj` | after `nxnnxe` | delta |
|---|---:|---:|---:|
| family A rows | 193 | **174** | **−19** |
| family A cells | 26 | **23** | **−3** |
| total cells | 403 | **406** | **+3** |
| diverge rows | 4190 | 4185 | −5 |
| agree | 365705 | **366051** | **+346** |
| missing | 1 | 1 | 0 |

**The prediction was exact and the attribution is exact: the ticket named 19 rows in seven files,
and all seven went to zero.** `test_str_backed_enum.bl` 6 → 0, `test_derive_clone.bl` 3 → 0,
`test_derive_deserialize.bl` 3 → 0, `test_derive_list_deser.bl` 3 → 0, `test_derive_enum_deser.bl`
2 → 0, `test_derive_nested.bl` 1 → 0, `test_derive_serialize.bl` 1 → 0. Nothing else in the corpus
moved by a row.

**14 of the 19 moved family A → class B; the other 5 now `agree`.** The whole corpus `diverge` delta
is `−5` and it is entirely these five, so the accounting closes exactly:

```
- tid=?  flat=Str            (×4)  →  agree          u.to_json()          — Str is depth 1, the flat pair spells it
- tid=?  flat=Point          (×1)  →  agree          p.clone()            — a struct name is depth 1 too
- tid=?  flat=Result[Void, Str] (×8) → tid=Result[User, Str] / [Color, Str] / [Config, Str] / [Priority, Str] / [Shape, Str]
- tid=?  flat=Option[Int]    (×4)  →  tid=Option[Status]
- tid=?  flat=Int            (×1)  →  tid=Color
- tid=?  flat=Shape          (×1)  →  tid=Shape      ← same spelling, still diverging
```

The four class-B groups are four *different* limits of the flat universe, which makes this fix a
compact demonstration of why Stage 3 exists at all:

- `Result[User, Str]` has **two** children and `(CT_*, sname)` holds one, so the **ok type erases to
  `Void`** — the `x3x0qj` erasure one position over;
- `Option[Status]` erases its **enum inner to `Int`**, because the flat universe has no way to say
  "an `Option` of a *named* enum";
- `tid=Color flat=Int` is the same erasure without the container;
- **`tid=Shape flat=Shape` diverges on identical spelling** — the D+E bucket, where the flat pair
  cannot tell an enum from a struct even when it has the right name.

Rows leaving family A for class B is progress, not a regression: class B is what Stage 3's
`c_type_from_tid` and Stage 4's deletion of `sv_tp` remove **wholesale**, whereas family A must be
fixed one cause at a time.

**`agree` rose by 346 — the largest of any prerequisite so far, on a −19 fix.** Same reason as
`x3x0qj`'s +125, one level up: a signature does not merely type the call, it types everything
downstream of it. The cascade in half 3 ran in reverse once the sigs existed — every binder that
took its type from a derived method's return, and every node under *those*, became visible to the
instrument at once.

Verified: `task regen` EXIT=0; `task ci` EXIT=0 — **641/641** test files, `fmt` 1502 passed /
86 skipped, gen1-vs-gen2 per-module byte-equal, all `ci-per-module-checks` ok.

Test: `tests/test_nxnnxe_derive_method_signatures.bl`, 25 rows — 18 red before, all green after.
Eight declared-type compares, one per registered method; two structured-shape assertions
(`Result[User, Str]`, `Option[Status]`) that a depth-1 answer would fail; two receiver rows
(`to_json` must not read `on type ?`, `clone` must read `on type User`); two argument-check rows
that exist only because the sig buys `check_arg_shapes`; three `cc`-escape rows asserting a
diagnostic instead of `C compilation failed`; **two binder-cascade rows** for half 3; and six
controls — every method run for real (`j=20 e=true d=true`), `from_json` matched as a `Result`,
`cmp` matched against a real `Ordering`, the str-enum round-trip, a non-deriving type still
reporting `unresolved method '.clone'`, and **a hand-written `impl` keeping its own signature
alongside `@derive`**, which is the collision guard.

**Note on arity, unchanged and still open.** `check_arg_shapes` is *"type only, no arity"*
(`typecheck.bl:1987`, the comment is explicit), so registering a signature buys per-argument type
checks and **not** arity. And the static path (`:9647`) calls no argument check at all, for **any**
static method in the language. `User.from_json(1, 2, 3)` is still a `cc` escape. That is a separate
gap from this ticket and wants its own.

**Latent defect recorded, not changed.** The derive registration loop at `typecheck.bl:7018-7031`
pushes onto `nr_impl_method_names` without pushing onto the parallel `nr_impl_type_names`. It is
benign only by luck: `method_names` ends up the *longer* list, so `nr_has_impl_method` (`:6738`)
iterating `type_names.len()` never indexes out of range, and derived names stay invisible to it
while still suppressing the name-only W0501 scan at `:7594`. **Do not add the missing push without
checking both readers** — it would change what `nr_has_impl_method` answers.

### bf0jnj — one type, two channels, and only one written (CLOSED, divergence-neutral)

**Mechanism.** `match Status.from_str("done") { .. }` failed to compile:

```
build/c3.c:167:5: error: unknown type name 'blink_Option_void'
  167 |     blink_Option_void _scrut_5 = _fromstr_4;
build/c3.c:167:34: error: incompatible types when initializing type 'int' using type 'blink_Option_Status'
```

The emitted **call** was always right — `blink_Option_Status _fromstr_4 = ...` — and only the
scrutinee temp copied out of it was wrong. Binding through an intermediate `let` worked, which is
why nothing in the corpus ever saw it: `tests/test_str_backed_enum.bl:18` writes
`let s = Status.from_str(..)` and then matches `s`.

The `from_str` static emitter (`codegen_methods.bl:2444`) stamped the Option's inner type on the
**temp variable** (`set_var_option_struct(tmp, CT_VOID, static_type_name)`) and left the
**expression side-channel** alone. The match-scrutinee branch (`codegen_stmt.bl:896-905`) reads the
expression channel — `expr_option_inner` / `expr_option_inner_struct` — found an empty struct name,
and spelled `Option_void`; anything that bound the call to a name first read the `ScopeVar` and got
`Status`. **The `try_from` / `from_json` arm one line above (`:2438`) writes its channel.** So the
fix is two lines, and the asymmetry between two adjacent arms in the same function is the whole
defect.

**This is the `expr_result_*`-vs-`ScopeVar` split, which is exactly what Stage 4 deletes.** One
type, two places to write it down, and a producer that wrote one. Until the side-channel is gone,
both have to be written together — there is no rule enforcing it, which is why this class keeps
recurring (`bf0jnj` is the same shape as the `1452w4` note at `codegen_expr.bl:4137`).

**`nxnnxe` is what exposed it.** Before typecheck knew `from_str`'s signature it rejected these
programs with `on type ?`, so the codegen bug behind them was unreachable. That is the second time
a signature fix has uncovered a codegen bug the missing type was hiding, after `2r96m9`.

**Divergence-neutral, by the same reasoning as `ya8qyf`, and measured rather than asserted.** A `cc`
escape produces no row: the instrument compares typecheck's tid against codegen's flat pair at a
*declaration site*, and this bug lives in an expression consumer with no binding at all. The sweep
after the fix reproduces **every figure** of the after-`nxnnxe` column exactly — 406 total cells, 23
family-A cells, 174 family-A rows, 4185 diverge, 366051 agree, 1 missing — so no column is added to
the master table for it. `ya8qyf` was recorded as neutral *by inference* because it shared a sweep;
this one has its own.

A note on the instrument while sweeping it: `scratchpad/sweep_mono.sh` takes the output path as a
**required argument** and, called without one, writes nothing and reports every count as zero. It
read as a clean corpus. Per `feedback_corpus_sweep_is_not_coverage`, an all-zero sweep is a broken
tap until proven otherwise — here it was the harness, not the compiler.

Test: `tests/test_bf0jnj_from_str_direct_match.bl`, 10 rows — 5 red before, all green after. The
direct match on both the `Some` and `None` paths; a nested variant match inside the `Some` arm; the
`Option_void` spelling asserted **absent from `compile_and_run`'s `err_out`**, because
`compile_and_capture` stops after `blinkc` and never invokes `cc`, so asserting on its output would
have been a permanent false green (it was, on the first draft, and the row read green while the bug
was live); `is_some` / `is_none` read directly; and four controls — the intermediate-`let` form that
always worked, the `from_json` sibling arm that is the reference implementation, a user fn returning
`Option[Color]` matched directly (which is what proved the bug was **emitter**-specific and not a
property of `Option`-of-enum), and `to_str`, which never touched the Option channel.

**Byproduct — `qne9k3` filed (P2): `Option[Enum].unwrap()` gives a receiver with no enum channel.**
`Status.from_str("open").unwrap().to_str()` still fails with
`unresolved method '.to_str' on type Status`, and it is **not** this emitter: a plain
`fn pick() -> Option[Status]` unwrapped fails identically, with no `from_str` and no `@derive`
anywhere. The unwrapped value is a correct `Status` in every other respect — it compares equal to a
variant, passes as a `Status` argument, and matches its own variant tags — so the value, its C type
and its tags are all right and only **method dispatch** fails. Codegen dispatches every enum method
on `get_var_enum(obj_str)` (`codegen_methods.bl:5232`, gating `to_json`, `debug`, `to_str`, `eq`,
`cmp`, `clone`), the unwrap temp carries the enum on the **struct** channel only, so `get_var_enum`
reads `""` and control falls to the E0505 backstop at `:5390` — which still prints the right type
name, because that reads a third channel. **This is the enum-vs-struct confusion of the D+E bucket,
in the variable channels rather than in `sv_tp`** — the same thing the `tid=Shape flat=Shape` row
records from the other side. Typecheck passes the program; the error is codegen-only.

### pvhaew — an emitted, load-bearing C function that could not be named in Blink (CLOSED, divergence-neutral)

`@derive(Hash)` generated a `hash` method, forward-declared it, emitted its body — and **no dispatch
arm ever called it**. `p.hash()` was a hard `error[UnresolvedMethod]: unresolved method '.hash' on
type P in 'main'`.

Four places had to agree and one did not:

| | |
|---|---|
| `codegen_derive.bl:124` | registers `DeriveMethodEntry{method_name: "hash"}` |
| `codegen_derive.bl:199` | emits `uint64_t {T}_hash({T} self);` |
| `codegen_derive.bl:390` / `:443` | emits the enum and struct bodies, both returning `uint64_t` |
| `codegen_methods.bl:5183` / `:5232` | the two derive-dispatch blocks — **no `hash` arm** |

so control fell out of both blocks to the E0505 backstop at `codegen_methods.bl:5390`.

**Why an emitted, exercised, load-bearing function was never once callable by name.** kops calls the
same symbol internally for struct-keyed `Map` / `Set` (`codegen_derive.bl:273`, `kops_hash_{cn}`).
The function was emitted, depended on, and covered by tests — just never *through method dispatch*.
The `Map` and `Set` control rows in the test are green before the fix and after it, which is the
evidence for that reading rather than an assertion of it.

**The allow-list-with-nothing-behind-it class, INVERTED — a fifth sighting.** With
`is_builtin_method`, `is_intrinsic_method` (`qjfwc6`, `n84s1p`) and `tc_method_resolvable_on_type`
(`nxnnxe`) the allow-list affirmed names the dispatch table had no arm for. Here the allow-list
(`has_derive_method`) is **right** and the **dispatch table is short**. The repair is the same in
both directions: make the table the authority.

Fix — one behavior, one regen, because the compiler's own source never calls `.hash()`:

1. `src/codegen_methods.bl` — a `hash` arm in **both** derive-dispatch blocks, emitting
   `{derive_method_cname(T, "hash")}({obj})` with `expr_result_type = CT_U64`. `derive_method_cname`
   yields `{c_type_c_name(T)}_hash`, byte-for-byte the forward declaration at `:199`.
2. `src/typecheck.bl` — `register_derive_method_sig(tname, "hash", [ttid], TYPE_U64)` in
   `register_derive_method_sigs`. `hash` was deliberately **held out** of `nxnnxe`'s table because a
   signature for an uncallable method claims it works; it joins now that both arms exist. That
   table's comment is rewritten from *"`hash` is absent"* to record the agreement.
3. `src/codegen_derive.bl:124` — `ret_type: CT_INT` -> `CT_U64`. **Record only, not behavior:** the
   sole reader `get_derive_method_ret` (`codegen_types.bl:1170`) has **zero callers**, and
   `has_derive_method` gates the arm on the entry's *name*. `CT_INT` contradicted both
   `sections/03_types.md:2352` and the `uint64_t` the body actually returns.

Test: `tests/test_pvhaew_derive_hash_callable.bl`, 11 rows — **8 red before, 11 green after.** Struct
and enum `hash` callable; `hash` over a `Str` field; the **determinism contract kops relies on**
(`same=true diff=true`), because a callable hash that broke it would be worse than an uncallable one;
the `U64` signature proved by `let bad: Str = p.hash()` being a `TypeError` — **without the signature
the return is `TYPE_UNKNOWN`, which unifies with anything, and that program would compile and *run***;
the receiver proved not to be `on type ?`; and four controls — the struct-keyed `Map`, the
struct-keyed `Set`, a non-deriving type still reaching the E0505 backstop (the arm is gated on
`has_derive_method`, so it must), and the sibling derived methods still dispatching from the same two
blocks.

**Divergence-neutral, measured not assumed.** The post-fix monolithic sweep reproduces the
after-`nxnnxe` column exactly: 4384 `bucket=` rows, 406 total cells, 23 family-A cells, 174 family-A
rows, 4185 diverge, 366051 agree, 1 missing. Expected — the fix adds a dispatch arm and a signature
for a method the corpus barely calls; it removes no erasure. (A caveat for the next sweep: the raw
sweep file is ~13748 lines, of which only 4384 are `bucket=` rows; the rest are per-file `summary`
lines. Compare `grep -c 'bucket='`, not `wc -l` — the two differ by 3x and reading the wrong one
looks like a corpus explosion.)

**Byproduct — `173wtk` filed (P2): a bare `@derive(Hash)` escapes to `cc`.** It emits the kops
equality adapter `kops_eq_blink_{T}` calling an **unemitted** `blink_{T}_eq`, and needs no `.hash()`
call at all — merely constructing the value is enough, so it predates this fix and is independent of
it. `Hash`'s supertrait is `Eq` (`sections/03_types.md:2352`), and `Ord`, which has the **same**
supertrait, **already synthesizes `eq`** (`typecheck.bl:2240`, and bare `@derive(Ord)` works end to
end: `a.eq(b)` -> `false`, `a.cmp(b) == Ordering.Less` -> `true`). So `173wtk` is an **asymmetry with
its own fix already in the tree**, not a design question — and either way a missing supertrait is a
compiler-diagnosable condition that must not reach `cc`. The test row was retargeted to what `pvhaew`
owns (dispatch reads `has_derive_method`, not the derive list's shape), with a note to widen it once
`173wtk` closes.

### cttrag — a module-qualified `let` had no type, and the ranking that found it had the axes wrong (CLOSED, −12 rows)

`module.name`, where `name` is a top-level `let`, resolved to `TYPE_UNKNOWN`. `infer_type`'s
`NodeKind.FieldAccess` arm (`src/typecheck.bl:9815`) had three cases — an **enum type** qualifier, a
**struct field**, a **tuple index** — and no fourth for a **module** qualifier, so the arm fell off its
tail. For `prov.count` the object `Ident` `prov` is not a type, `lookup_named_type` returns `-1`,
`infer_type` on the module `Ident` gives `TYPE_UNKNOWN`, and neither the `Struct` nor the `Tuple`
branch is entered.

**The type was already there.** `typecheck.bl:11582` resolves every top-level `let`'s annotation
through `resolve_type_ann` and registers it with `nr_define_typed` — which is exactly why the **bare**
form inside the declaring module was always typed. The qualified form never consulted it. That is the
whole bug: not a missing inference, a missing *lookup*.

**Two of the ranking entry's three axes were wrong.** The row below described this as a *"cross-module
`pub let` container element"* cause, generalized from the four sites in the compiler's own source that
happen to read a `List[Str]`. Probed rather than assumed, all three axes are narrower:

| the ranking said | what the controls show |
|---|---|
| container element | **not container-specific.** A scalar `pub let count: Int` loses its type identically |
| cross-module, `pub` | **neither.** The bare form inside the declaring module is typed — for a *private* `let` as much as a `pub let` |
| reached through a call | **not the call path.** A module-qualified user fn call resolves through the fnsig table and was always typed |

It is the **qualified form**, full stop. This is the second time a ranked entry generalized from the
shape its highest-count sites happened to have (`rbd0a4`'s `flat=Str` tail was the first), and the
lesson is the same: the ranking groups by *producer*, and the producer is a syntactic form, not a type.

**Both halves failed open, and differently** — `TYPE_UNKNOWN` unifies with anything, so the erasure is
not one bug with one symptom:

- **the declared-type compare is skipped** — `let bad: Str = prov.count` compiled, linked and **ran**,
  printing `3`. A silent miscompile.
- **the argument check is skipped** — `want_str(prov.count)` produced **no diagnostic at all** and
  reached the C compiler: `expected 'const char *' but argument is of type 'int64_t'`.
- **the erasure propagates one level** — `let e = prov.names.get(0).unwrap(); let bad2: Int = e` also
  ran, printing `alpha`.

That asymmetry dictates the test shapes. The cc-escape row goes through `run_xmod`, not
`compile_and_capture`: the latter stops after `blinkc` and would read green forever
(`project_call_arg_typecheck_and_carrier`'s trap, hit again).

Fix — one behavior, one regen, in three parts:

1. `tc_module_let_tid: Map[Str, Int]`, keyed `"{module}.{name}"`, cleared beside
   `tc_symbol_module.clear()`.
2. Populated **beside the existing `nr_define_typed` call** in the top-level-let pass, from the same
   `resolve_type_ann` result — not in a pass of its own, so the two spellings of one binding cannot
   drift.
3. Read in the `FieldAccess` arm behind the **same gate name resolution already uses** for this form
   (`:7764`: an `Ident` that names an import and is not shadowed by a binding), keyed on
   `tc_qualifier_to_module_or_self` so an aliased or dotted import resolves identically. **Fails
   closed** — an unregistered key falls through to the prior behavior rather than guessing.

**Why not `nr_get_type(fname)`, which is one line instead of a table.** Top-level lets are *also*
defined by bare name, and the bare-name scope is **shadowable**: with a local `count: Str` in scope,
`nr_get_type("count")` answers the **local**, and `prov.count` would silently acquire `Str`. A wrong
type is worse than no type — no type at least fails open loudly at `cc`, while a wrong one is
authoritative. Keying on the module makes the lookup immune to the ambient scope. Pinned by a row that
asserts the **message** `declared type Str but got Int`, which only holds if the qualified access
resolved to `prov`'s `Int` and not to the local `Str`.

Test: `tests/test_cttrag_qualified_module_let_type.bl`, 11 rows — **7 red before, 11 green after.** One
shared provider module carries the shape axis (two scalars, a `List`, a `Map`) and the visibility axis
(one private `let`) at once. Rows: `Int`-qualified vs `Str`-declared and the reverse; a `List` element
through `.get().unwrap()`; a `Map` value; the whole container bound unindexed (the tid must be the
container type, not merely recoverable from its elements); the argument channel via `run_xmod`; and
four controls — bare access inside the declaring module still printing `alpha|9|3`, a qualified fn call
still resolving, the **correctly typed** program of every shape still compiling and running
(`3|lbl|1|alpha|7`, which a fix that resolved to the *wrong* type would fail while satisfying every
error row above), and the shadowing row.

**Attributed, and the prediction was exact.** Family-A rows **174 → 162 (−12)**, diverge 4185 → 4173,
agree 366051 → 366125. Total cells (406) and family-A cells (23) both **unchanged** — the vacated rows
shared the `tid=? flat=Str` cell with other producers, which is the cells-are-coarser-than-rows effect
again; rank by rows. The per-site diff deletes **exactly four sites, three rows each** —
`src/file_watcher.bl:40,73` and `src/incremental.bl:44,75`, all
`symbol_index.si_file_path.get(i).unwrap()` — and **nothing else in the corpus moved.** Fourth
consecutive fix whose row count was predicted before the sweep. The +62 rise in total comparisons is
the fix's own two new `let`s in `typecheck.bl`; see the master table's note.

**Byproduct, not filed as new.** The shadowing row's bare `count` reference also earns an unrelated
`error[ImportNotSelected]` — a name importable from a module cannot be used bare *even when a local
binding of that name exists*. Same family as `8wk3xg` (a local `let at` resolving to `parser.bl`'s
private `fn at`), and the workaround comment at `typecheck.bl:12323` already records that one.

### n84s1p — an allow-list short of its own dispatch arms, and the counter's blind spot (CLOSED, −8 rows)

`is_intrinsic_method` (`codegen_types.bl:8084`) decides whether `ns.method(...)` is a **namespace
intrinsic**. It was short of the arms codegen actually emits by **twelve** names — not the three the
ticket claimed:

| namespace | arm exists, not listed |
|---|---|
| `io` | `eprint`, `eprint_raw`, `log`, `print_raw`, `read_bytes`, `write`, `write_bytes` |
| `env` | `cwd`, `exit`, `remove_var`, `set_var`, `var` |

An unlisted name falls out of the intrinsic gate at `typecheck.bl:9679` and into the **bare-name**
fallthrough at `:9697`, which asks `lookup_fnsig("write")` — not `lookup_fnsig("io.write")`. Nothing
answers, so the call is `TYPE_UNKNOWN`.

**Five distinct fail-open modes, all reproduced by *running* before the test was written.** This is
the point of the section: one missing table entry produced five different failures, and only two of
them were the `cc` escape the ticket predicted.

| # | mode | witness |
|---|---|---|
| 1 | **silent miscompile** | `let bad: Int = env.var("HOME")` compiled, linked, **ran**, printed `<value>` |
| 2 | **silent miscompile** | `let bad: Int = env.cwd()` ran and printed the real working directory |
| 3 | **garbage exit status** | `env.exit("1")` emitted `exit(<char*>)`; the process exited **86**, a pointer-derived value — address-dependent, so no test may assert on it |
| 4 | **`cc` escape** | `io.read_bytes` / `io.write` / `io.write_bytes` / `env.remove_var` reached the C compiler |
| 5 | **compiler panic** | `env.set_var("a")` hit `panic: unwrap called on None at src/parser.bl:111` — user input crashing the compiler |

Mode 5 is worth its own note: the arity check at `:9679` was **already written**, and had no
signature to read. A missing table entry did not merely weaken a check, it turned a diagnostic into
an ICE.

**A fourth surface, and it fired on *correct* code.** Of the twelve names exactly one made valid
spec-blessed code warn: `env.exit(0)` emitted `warning[UnknownMethod]: unknown method 'exit'`. That
gate (`typecheck.bl:7721`) is keyed on the **bare** method name via `is_builtin_method`, which happens
to know `var`, `cwd`, `write` and `read_bytes` for unrelated reasons and does not know `exit`. The
wrong repair is seductive and was available: adding `exit` to `is_builtin_method` silences the warning
and also silences `.exit()` on **every type in the language**. A namespace intrinsic has to be
recognized by *namespace and method*, which is what `is_intrinsic_method` answers, so that is what the
gate now consults.

**The invariant is `list ⊇ arms`, not `list == arms`** — which reverses half of the planned fix.
`io.debug` is listed with **no arm behind it** and **stays listed**. A listed-but-unsigned name gets no
type from either arm and falls to the loud E0505 codegen backstop; being listed is precisely what keeps
it **off** the bare-name path, where a free fn named `debug` could answer for it. `io.println` has been
in exactly that state all along. So *long* is harmless and *short* is the bug, and removing a name is
never the repair. The plan of record was to delete `io.debug`; reading what the two paths actually do
(they are mutually exclusive — `:9679` gates on `!= 0`, `:9697` on `== 0`) is what corrected it.

**Spec judgment, stated because it is the kind of call that should not be silent.**
`io.read_bytes` / `io.write` / `io.write_bytes` are **not in the spec** — the IO operations table at
`sections/04_effects.md:193` stops at the print family, and a grep of `sections/` finds none of the
three. They were signed anyway, on the same basis `qjfwc6` signed `io.read_line` (also unspec'd):
unlike `fs.read` (`jr4xf7`) there is no open question about what they *are*, because the emitted C
fixes each one completely — `blink_stdin_read_bytes(int) -> blink_bytes*`,
`blink_stdout_write(const char*) -> void`. Signing records the arm; it decides nothing the spec left
open. The `env.*` five are all spec-blessed, with `env.var` confirmed `Option[Str]` by
`env.var(...) ?? "8080"` and `.is_some()` at `:705-716`. The spec gap is real and is left as a gap:
these are unspec'd intrinsics, not new types.

The fix, one regen — one behavior, and no new syntax in the compiler's own source:

- `codegen_types.bl:8090`/`:8105` — the 7 `io` and 5 `env` names.
- `register_ns_intrinsic_sigs` — 8 signatures: `io.read_bytes(Int) -> Bytes`,
  `io.write(Str) -> Void`, `io.write_bytes(Bytes) -> Void`, `env.var(Str) -> Option[Str]`,
  `env.cwd() -> Str`, `env.set_var(Str, Str) -> Void`, `env.remove_var(Str) -> Void`,
  `env.exit(Int) -> Void`. The four value-typed-argument `io` statements (`print_raw`, `eprint`,
  `eprint_raw`, `log`) are listed-but-unsigned, exactly as `io.println` already was.
- `typecheck.bl:7721` — the `UnknownMethod` gate recognizes a namespace intrinsic.

The compiler's own source calls `env.var(...) ?? ""` in about twenty places and `io.write` in
`src/lsp.bl`, so `task regen` was a real test of all eight signatures rather than a formality.

**Measured: −8 rows** (162 → 154), cells 406 → 404, `agree` +8, total comparisons **unchanged** at
370299 — the control for the `cttrag` accounting note, since this fix adds no `let` to the compiler's
own source. Attribution is exact and the prediction was **6**:

| rows | site | cause |
|---:|---|---|
| 6 | `src/lsp.bl:50` (`var=bytes`) and `:51` (`var=result`), 3 roots each | `io.read_bytes`, and `:51` purely downstream of it |
| 1 | `tests/manual_stdio_stdin.bl:10` (`var=data`) | `io.read_bytes` |
| 1 | `tests/test_env_effect.bl:12` (`var=cwd`) | `env.cwd()` — **the unpredicted 8th** |

`src/lsp.bl` → **0**. The `:51` rows also retire the ranking's separate `bytes.to_str()` entry as a
mis-attribution: `Bytes.to_str` has had its signature since `typecheck.bl:9495` the whole time that
entry claimed it did not, and its rows were downstream of `:50` having no type.

**The counter has a blind spot, and this fix is the proof.** `env.var` — the worst defect in the
ticket, a silent miscompile — contributed **zero divergence rows**, because it is nearly always
consumed as `env.var(x) ?? ""` and the coalesce handed the `let` a `Str` that codegen held quite
happily. The instrument asks whether codegen *has* a type, never whether typecheck's answer is
*right*. Both silent miscompiles here were found by auditing the allow-list against the arms; the
counter caught one of them incidentally, at one site, and only because the value was bound directly.
**Rank by rows to schedule Stage 3 — they are what `c_type_from_tid` must answer for — and never read
a low row count as "this matters less".**

**Spun off.** `366d3m`: **`build/blinkc` reports compile errors and then exits 0**, for every error
kind including a plain `let bad: Str = 5`. Found because one test row asserted
`err_out.contains("TypeError")` through `compile_and_run` and could not pass — `compile_test_helpers.bl:438`
gates on `cresult.exit_code != 0` to decide whether to stop before `cc`, so it always proceeds, and
`cc` then fails on the `.c` file `blinkc` never wrote. Every `compile_and_run` row in the suite
asserting "nonzero exit and no `cc` diagnostic" is therefore passing on `cc`'s file-not-found rather
than on `blinkc` having stopped. Those rows still discriminate red from green — before a fix `blinkc`
*does* emit C and `cc` chokes on it **by name** — so they are not false greens, but they are weaker
than they read. `me77ay`: **`env.vars()` is spec-blessed `Map[Str, Str]` (`:209`, `:752`) with no
codegen arm at all**; deliberately **not** added to the allow-list, since an unimplemented intrinsic
must keep reaching the loud backstop, and pinned by a control row so the gap stays visible.

**Tests:** `tests/test_n84s1p_intrinsic_allowlist_arms.bl`, 26 rows, **17 red / 26 green**. `task ci`
green (645 test files, 0 failed; fmt 1510 passed).

### jvy35h — the other half of the allow-list defect, and the first one with a crash behind it (CLOSED, −6 rows)

`n84s1p` closed the **namespace** half of the allow-list-with-nothing-behind-it class
(`is_intrinsic_method`). This is the **receiver** half: `is_builtin_method`
(`src/typecheck.bl:6259`), a flat 171-name list whose only job is to suppress `UnknownMethod` and to
gate `E0505`/`W0501`. `join` is name #41 in it. Return types live in a separate per-receiver dispatch
in `infer_type_uncached`, whose builtin `List` block (`:9220`) had arms for
`len`/`get`/`push`/`set`/`pop`/`clear`/`slice`/`concat`/`contains` and **no `join`** — while codegen
has had exactly one arm for it since forever (`codegen_methods.bl:1620`, `str_join(obj, delim)` with
`expr_result_type = CT_STRING`). So the C was correct and the call had no type.

**The audit that found the shape is the useful part, and it is mechanical.** Diff the method names
`emit_list_method` handles against the names the builtin `List` block types:

| | names |
|---|---|
| codegen `emit_list_method` (`:1126-1657`) | `concat` `contains` `get` **`join`** `pop` `push` `set` `slice` |
| typecheck builtin `List` arm (`:9220-9309`) | `all` `any` `clear` `collect` `concat` `contains` `count` `filter` `find` `fold` `for_each` `get` `is_empty` `len` `map` `pop` `push` `set` `skip` `slice` `take` |

`join` is the **only** name on the emitting side with no arm on the typing side, which is why this
cause was 6 rows and not 60 — the two lists had drifted by exactly one name. (Typecheck's side is
much longer because the eager adapters are typed here and emitted elsewhere, in the shared
list-or-iterator block at `codegen_methods.bl:3973` — the `qzdz2e` territory.)

**Four fail-open modes, and two of them are worse than anything the campaign has hit so far.** All
four were reproduced by *running* the programs before the test was written:

| # | program | before |
|---|---|---|
| 1 | `let bad: Int = parts.join(",")` | compiled, linked, ran, **printed `a,b`** — a Str bound to an Int-declared name |
| 2 | `[1, 2].join(",")` | **SEGFAULT**, exit 139, core dumped — `str_join` reads `int64_t` elements as `const char*` |
| 3 | `[["a"], ["b"]].join(",")` | **exit 0 and binary noise on stdout** — the same cause one shape up, and it does not even crash |
| 4 | `parts.join(5)` | no diagnostic; `cc`: *passing argument 2 of `blink_std_str_str_join` makes pointer from integer without a cast* |

Modes 2 and 3 are new to this campaign: every earlier missing signature produced a silent
*miscompile* or a `cc` *escape*, and this one produces **memory unsafety in a compiled program from
type-correct-looking source**. Mode 3 is the worse of the pair — a segfault is loud, garbage on
stdout is not — and it is why the receiver check reads the element **kind** rather than enumerating
the scalar kinds the probes happened to cover.

**The spec pins both halves, so unlike `jr4xf7` there was nothing to decide.**
`sections/03_types.md:227-238` spells the impl header verbatim — `trait Joinable { fn join(self,
separator: Str) -> Str }`, `impl Joinable for List[Str]` — and the sealed-builtin-trait table at
`:521` reads `Joinable | List[Str] | join`. The receiver constraint is in the impl header, which is
why "nothing checked the receiver" is a bug against the spec and not a gap in it.

**The fix** is one arm beside `concat`: `check_builtin_arg(method, 0, TYPE_STR, ...)` for the
separator, an element-kind check against `TyKind.Str` for the receiver, `return TYPE_STR`. `join`
**stays** in `is_builtin_method` — the `n84s1p` invariant (**list ⊇ arms**) applies unchanged in this
half of the defect, and a name removed from that list starts erroring on a valid call.

**The element check fails open on `Unknown` and `Typevar`, deliberately.** `type_kind` resolves a
bound metavar, so an inferred `List[Str]` (`let mut xs = []` then `push("a")`) reads as `Str` and is
judged normally; what is left is a genuinely unresolved element. `fn f[T](xs: List[T]) -> Str {
xs.join(",") }` cannot be judged at its definition site, and whether that shape should require a
`T: Joinable` bound is a spec question about generic bounds. A control row pins the current answer so
a future decision is a deliberate change rather than a silent one.

**Attribution — exact, 6 rows, 3 lines:**

| rows | site | producer |
|---:|---|---|
| 2 | `src/cli.bl:935` (`var=cflags`) | `flags.join(" ")` |
| 2 | `src/cli.bl:3561` (`var=srcs`) | `stdlib_native_dep_source_paths(n).join(",")` |
| 2 | `src/cli.bl:3563` (`var=defs`) | `stdlib_native_dep_compile_defs(n).join(",")` |

Each line is counted twice — once as `at=cli:` and once as `at=__main__:` — so `cli` went 11 → 8 and
`__main__` 125 → 122 off the **same** three lines. The other 16 `.join(` call sites in the tree are
tail-position or interpolated, and the instrument only counts `let` declarations.

**The sweep's `diverge` count went UP by 25, and the fix's own source is the whole reason** — see the
master-table note. One new `let ek` in `typecheck.bl` × 31 basis roots, every one landing in
`diverge` as `tid=TyKind flat=Int`, because the flat universe cannot spell an enum. Class B, into a
cell that already held 682 rows.

**Spun off.** `sq67xq`: **omitting the arguments of a builtin container or `Str` method ICEs the
compiler** — `parts.join()`, `parts.push()`, `parts.get()`, `parts.contains()` and `"ab".contains()`
all panic with `unwrap called on None at src/parser.bl:111`. `check_builtin_arg` (`:2087`) returns
**silently** when the argument is absent, so typecheck reports nothing and codegen then `sublist_get`s
a short list, gets `-1`, and unwraps a `None` node accessor. One shared repair in the one place that
knows the expected arity; not part of this fix because it is not join-specific and it is loud rather
than silent.

**How this half of the defect stands now.** Of the 171 names in `is_builtin_method`, **64** still have
no `method == "<name>"` comparison anywhere in `typecheck.bl` (was 73 when the organizing note below
was written; `join` is one of the nine that have since been answered). But that metric is a **proxy
and it over-counts**: 11 of the 64 are namespace intrinsics now answered by `qjfwc6`/`n84s1p`'s
signature *table* rather than by an arm, and most of the remaining 53 are real stdlib functions
reached through the bare `{Type}_{method}` fnsig key (`Duration.to_ms`, the `Row.get_*` family) or are
already-open causes (the iterator adapters, `Channel.recv`/`send`, `Template.type_tag`, the
`io.print*` family that `n84s1p` deliberately left listed-but-unsigned). `join` was the last one that
was a plain missing arm on a **builtin container receiver**. What the audit did surface as genuinely
new: **`Instant.elapsed()` and `Instant.to_rfc3339()` have no type**, while every other method on
`Instant`/`Duration` does — `let bad: Int = t.elapsed()` runs and prints `<value>`, and
`let bad: Int = t.to_rfc3339()` runs and prints the timestamp.

**Test:** `tests/test_jvy35h_list_join_signature.bl`, 15 rows, **8 red / 15 green**. The 7 controls
(correct join with a length assertion, the empty and single-element edges, tail position and
interpolation, a struct field receiver, an inferred element, a **user trait method named `join`** on a
struct receiver keeping its own `-> Int` signature, and the typevar fail-open) were green throughout.
`task regen` + `task ci` green (646 test files, 0 failed; fmt 1512 passed, 0 failed).

### rb5wvb — the two-name residue of the same audit, and the fix that named an undiagnosed ranking entry (CLOSED, −5 rows)

`jvy35h` closed the last plain missing arm on a **builtin container** receiver. This is the same audit
applied to a **nominal stdlib** receiver, and it found the two-name residue: of `Instant`'s six methods,
four are declared in `lib/std/time.bl:16-19` and so resolve through the `{tname}_{method}` fnsig lookup
in the Struct/Enum arm, while `elapsed` and `to_rfc3339` have **no Blink declaration anywhere** —
`codegen_methods.bl:4695,:4716` emit `blink_Instant_elapsed` and `blink_Instant_to_rfc3339` directly. No
declaration, no fnsig, and the block fell through to `TYPE_UNKNOWN`. Both names are in
`is_builtin_method` (`:6429`, `:6432`), so `tc_method_resolvable_on_type` said yes and E0505 stayed
silent on a receiver whose type was **fully known** — the third receiver-half sighting of the
allow-list-with-nothing-behind-it class.

**The audit is the same one-command diff as `jvy35h`, one namespace over**, and it is worth writing down
as the general form: for a receiver type, diff the method names codegen's block handles against the names
typecheck answers. Here it splits three ways rather than two:

| | names |
|---|---|
| codegen `CT_INSTANT` block (`:4694-4731`) | `add` `elapsed` `since` `to_rfc3339` `to_unix_ms` `to_unix_secs` |
| declared in `lib/std/time.bl` (→ fnsig) | `add` `since` `to_unix_ms` `to_unix_secs` |
| **answered by neither** | **`elapsed` `to_rfc3339`** |
| codegen `CT_DURATION` block (`:4733-4780`) | `add` `is_zero` `scale` `sub` `to_ms` `to_nanos` `to_seconds` — **all seven declared**, so `Duration` is complete |

`Duration` being complete is the control that makes the result trustworthy: the same audit run on the
sibling type finds nothing, so the two names are a real gap and not an artifact of how the diff is taken.

**Five fail-open modes.** Two silent miscompiles — `let bad: Int = start.elapsed()` ran and printed
`bad=<value>`, `let bad: Int = now.to_rfc3339()` ran and printed `bad=2026-08-12T04:32:00Z` — plus a cc
escape in argument position, a *downstream* check disabled (`now.to_rfc3339().starts_with(5)` reached cc
because the receiver of `starts_with` was untyped, so its own argument check was skipped), and **arity
unchecked**: `now.elapsed(5)` and `now.to_rfc3339("extra")` both ran at exit 0 with the extra argument
silently discarded. That last one is the opposite tail of `sq67xq`, where the *missing* argument ICEs the
compiler — codegen never reads the argument list for these two, so an extra one is quiet rather than
fatal, which is the worse of the two failures.

**The spec pins both signatures** (`sections/03_types.md:566,:569` — `elapsed(self) -> Duration !
Time.Read`, `to_rfc3339(self) -> Str`), so return types and the zero arity were not decisions taken here.

**Two placement decisions, both load-bearing.** The arm sits **below** the fnsig lookup, not above it, so
a real declaration always wins: a future `Instant_elapsed` in `lib/std/time.bl` supersedes it untouched,
and the four declared siblings keep resolving through their own signatures (there is a control row for
exactly that). And it is keyed on `tname == "Instant"`, not on the method name, because **`elapsed` is an
overloaded name** — `sections/06_tooling.md:923` gives the mock clock handle its own `elapsed(self) ->
List[Duration]`. A name-keyed arm would have answered `Duration` for that receiver too. `elapsed` returns
`ensure_runtime_struct_type("Duration", ["nanos"], [TYPE_INT])`, which looks up before it mints, so the
result is the **declared** tid and `.to_ms()` on it still resolves through `Duration_to_ms` — the test row
that binds `now.elapsed().to_ms()` to a `Str` is what proves the identity, since a look-alike tid would
leave that call untyped and the row would fail.

**Attribution — exact, 5 rows, 3 lines:**

| rows | site | producer |
|---:|---|---|
| 3 | `lib/pkg/resolver.bl:312` (`var=generated`) | `time.read().to_rfc3339()` |
| 1 | `tests/test_time.bl:46` (`var=rfc`) | `fixed.to_rfc3339()` |
| 1 | `tests/test_time.bl:64` (`var=el`) | `before.elapsed()` |

**The `lib/pkg/resolver.bl:312` rows are the entry the ranking below carried as "not yet diagnosed" for
ten sweeps.** It cost one `sed -n '312p'` to name, and nobody had spent it — including the audit that
found this cause, which came at it from the allow-list side and never looked at the row. Two independent
paths to the same defect, and the cheaper one had been sitting in the document the whole time. That is
the third correction this ranking has taken from reading a row's own source line (`bytes.to_str()`,
`jr4xf7`, now this), and the first where the line was never read at all rather than read wrongly.

**How the allow-list stands after both halves.** Of `is_builtin_method`'s 171 names, **62** now have no
`method == "<name>"` comparison in `typecheck.bl` (73 when the organizing note above was written, 64
after `jvy35h`). The remaining 62 are, as far as the audit can tell, all answered elsewhere or already
ticketed: real stdlib functions reached through the bare `{Type}_{method}` fnsig key, namespace
intrinsics answered by `qjfwc6`'s signature table, the `io.print*` family `n84s1p` deliberately left
listed-but-unsigned, and the open causes (iterator adapters → `qzdz2e`, `Channel.recv`/`send`,
`Template`'s six → `nrrs28`, the Ptr names → `mwsy85`/`5efs37`, `ffi.scope` → `ps5br9`, the `fs.*` names
→ `jr4xf7`). Sixteen of the 62 are the `Instant`/`Duration` constructors and methods that
`lib/std/time.bl` declares, which is exactly the pattern this fix's audit was built to separate from a
real gap. **Every remaining receiver-side name already has a ticket**, so the receiver-block diff yields
no *new* prerequisite: the mechanism is spent as a source of them, and the tail below is what is left.

**Test:** `tests/test_rb5wvb_instant_intrinsic_signatures.bl`, 14 rows, **9 red / 14 green**. The 5
controls — spec types with a runtime assertion, the ISO-8601 *shape* (so the row also witnesses that
codegen was left alone; a `Str` return type would be satisfied by any string), the four declared siblings
still resolving through their fnsigs, tail-return plus interpolation, and a user trait method named
`elapsed` keeping its own `-> Int` — were green throughout. `task regen` + `task ci` green (647 test
files, 0 failed; fmt 1514 passed, 0 failed).

### cjtxxr — the last unchecked callable shape in the language (CLOSED, −12 rows)

`obj.field(args)` where the struct declares `field: fn(A) -> B` got **no type and no check of any
kind**: return type, arity, and every argument type all failed open at once. Every other callable shape
was already correct, which is what made this a gap rather than a design question — and the deciding
evidence was the *same field hoisted through a `let`*:

| form | checked before this fix? |
|---|---|
| a closure **variable** — `let f = fn(n: Int) -> Str {..}` then `f(3)` | yes (`nz7drz`, `typecheck.bl:9012`) |
| an **immediately-invoked** literal — `fn() -> Int { 7 }()` | yes (`x3x0qj`, `:9086`) |
| a **fn-typed parameter** — `fn take(cb: fn(Int) -> Str)` then `cb(1)` | yes |
| the field **hoisted** — `let g = h.cb` then `g(3)` | yes — it takes the closure-variable path |
| the field **called directly** — `h.cb(3)` | **no** |

The hoisted row is the whole diagnosis in one line: since `let g = h.cb; g(3)` errors correctly, the
field's tid is already a real structured `TyKind.Fn`, so nothing was missing from the *type* — only from
the *dispatch*.

**Two halves to the cause, and the second is the tenth sighting of the allow-list class.** The
`TyKind.Struct || TyKind.Enum` receiver block in `infer_type_uncached` (`:9638`) tries the
trait-qualified/bare fnsig, the `rb5wvb` Instant intrinsics, then the `display`/`eq`/`cmp` derive arms — a
closure **field** is none of those, so the call fell to `TYPE_UNKNOWN`. And E0505 did not catch it either:
`tc_method_resolvable_on_type` clause (d) (`:372-375`) fail-opens on `is_callable_field_name(method)`, a
**global** list of every field name declared `Fn` anywhere in the program, not a per-type check.

**Clause (d)'s comment is what kept the hole open, and it had been false since `nz7drz`.** It reads
*"closure fields lower to `TyKind.Typevar("Fn")`, not a closure kind, so reuse the callable-field name
registry"* — true when written, and `nz7drz` gave `resolve_type_ann` a real `Fn` arm (`:2756`) that builds
a structured tid via `make_fn_type`, which `register_struct_type` stores as the field's `sf.type_id`
(`:3462`). A **name registry standing in for a type** is exactly what a stale premise leaves behind, and
that premise is contradicted twice in the same file by comments written *for* `nz7drz` (`:753`, `:9005`).
Worth generalizing: when a comment justifies an allow-list by "the structured form does not exist yet",
that justification has an expiry date and nothing checks it.

**The fix is a third dispatch, not new inference** —
`tc_check_call_against_fn_tid(fld_tid, node_args(node), "closure field '{tname}.{method}'", node)`,
guarded on `obj_k == TyKind.Struct` (an enum has variants, not fields) and on the field tid actually being
a `Fn`, so a non-callable field sharing a name with some *other* struct's callable field still reaches
E0505 as before. One `let`, one call.

**Placement is fixed by codegen, and getting it wrong would have moved the miscompile rather than removed
it.** `codegen_methods.bl` dispatches synthesized `display`, then `lookup_impl_method` (`:5323`), then the
closure field (`:5333`) — so a trait-impl method of the same name wins there. The arm therefore sits
**after** the fnsig lookup and immediately **before** the E0505 gate, and the shadowing control row *runs*
the program and asserts on `99` (the impl's value) rather than `n=3` (the field's).

**Eight fail-open modes, three of them silent miscompiles** that compiled, linked and ran:
`let bad: Int = h.cb(3)` printed `bad=n=3`; a nested field receiver `o.inner.on_error(1, "x")` printed
`bad=1:x`; and a struct-returning field left the whole result untyped, so `let b = h.cb(3)` followed by
`let bad: Str = b.n` was accepted too — the hole propagating one hop past the call. The other five reached
`cc`: argument position, a chained receiver (`h.cb(3).starts_with(5)` — `starts_with`'s *own* argument
check was skipped because its receiver had no type), too many arguments, too few, and a wrong argument
type. Arity **and** argument types **and** the return type, all in one shape.

**The spec ships this shape as its own server design**, so the check invents nothing: `type Route` with
`handler: fn(Request) -> Response` (`sections/04_effects.md:453`), plus a middleware list and
`error_handler: fn(Request, ServerError) -> Response` (`:407-408`). `lib/std/testing.bl`'s
`type Cleanup { action: fn() -> Void }` is the same shape in the stdlib. The field's declared annotation
**is** its signature — the argument `nz7drz` made for the closure variable, one position over.

**Attribution — exact, 12 rows, 3 root files, one stdlib cause:**

| rows | invocation site | field declared in `lib/std/http_server.bl` |
|---:|---|---|
| 7 | `tests/test_net_integration.bl:58,69,80,107,120,162` (`var=resp`) and `:153` (`var=req`) | `Route.callback: fn(Request) -> Response`, `Hook.process: fn(Request) -> Request` |
| 2 | `tests/test_middleware.bl:34,43` (`var=resp`) | `ErrorHandler.on_error: fn(Request, Str) -> Response` |
| 2 | `tests/test_http_server.bl:39,89` (`var=resp`) | `Route.callback` |
| 1 | `tests/test_net_integration.bl:155` (`var=hdr_val`) | **downstream** — see below |

**Eleven rows were predicted and twelve moved, and the twelfth is the useful one.**
`var=hdr_val tid=? flat=Str` at `:155` is `let hdr_val = req.headers.get("X-Test").unwrap()`, two lines
after the `req` at `:153`: with `req` untyped, its `headers` field, the `Map` lookup and the `unwrap` were
untyped as well. Typing the producer typed the consumer for free. The ranking could not have shown that in
advance, because the downstream row's `var=` and `flat=` name an entirely different shape — so a family-A
row count is a **floor** on what a cause costs, not a measure of it, and a fix beating its prediction is a
hint about what else the same hole was suppressing.

**Test:** `tests/test_cjtxxr_closure_field_call_signature.bl`, 13 rows, **10 red / 13 green**. Eight error
rows and five controls: the correct call *running* and returning the closure's value, trait-impl
shadowing, the hoisted-through-a-`let` reference implementation (pinned so the two paths cannot diverge
again now that they are two dispatches to one function), a zero-arg `fn() -> Void` field of the `Cleanup`
shape in both directions, and a two-parameter handler field checking its **second** argument — that last
one witnesses `tc_check_call_against_fn_tid`'s argument loop rather than a one-argument special case.
`task regen` + `task ci` green (648 test files, 0 failed; fmt 1516 passed, 0 failed). **No corpus test
needed changing**, which also says no existing `fn(A) -> B` field declaration in `tests/`, `examples/`,
`src/` or `lib/` disagreed with how it is called.

### 9md3r1 — the qualifier was discarded in both phases (CLOSED, −12 rows)

**One line, two phases, six ranking entries.** The flat tail carried six separate family-A entries
named after their `flat=` spelling — `QueryError` (4 rows), `PgError` (2), `Event` (2), `DbError` (2),
`Msg` and `Shape` — 12 rows over five files. Six `sed -n '<line>p'` calls, one per entry, showed every
site to be the same expression: `let x = Enum.Variant { field: v }`, a **qualified struct-style variant
literal**. Not six causes. One.

**Typecheck's half.** `infer_type_uncached`'s `NodeKind.StructLit` arm reached
`lookup_named_type(sname)` for a dotted name (`typecheck.bl:1225-1244`), and that function strips a
dotted name to its **suffix**. For `mod.Type { .. }` — the module-qualified struct literal it was
written for — the suffix *is* the type name, so it is right. For `Enum.Variant { .. }` the suffix is
the **variant** name, which is never a type: `E0518` makes a struct named like a variant a
declaration-time collision, precisely so the two namespaces cannot overlap. So the site inferred
`TYPE_UNKNOWN`, which unifies with anything.

**Codegen's half, which had to be found separately.** `emit_struct_lit` chose the enum with
`if resolved_variant != "" { resolved_variant } else { <prefix> }` under the comment *"Prefer the
resolved enum."* `resolve_variant` is a **global** variant-name → enum map
(`codegen_types.bl:3868`), first-declared-wins, so for a variant name two enums share it answers the
wrong one. Fixing typecheck alone left correct code still emitting the wrong C. **Check both phases
for a mirror-image half** — the two spellings of "discard the qualifier" were written independently
and neither knew about the other.

**The spec is unambiguous and names the resolution order.** `sections/03_types.md:1040` rule 1: *"if
the site is already written `Enum.Variant { ... }`, that names the variant directly"*; `:1036` requires
the bare and qualified spellings to *"emit identical code"*; `:1063`: *"No path ever silently picks a
winner."* Both halves violated `:1063` in opposite directions — typecheck picked no winner at all,
codegen picked the wrong one silently.

**Seven fail-open modes, every one reproduced by *running* a program**, and every bare-form control
erroring correctly — the asymmetry that dated the bug to the lookup rather than to a missing check:

1. **Silent miscompile, cross-enum argument.** `want_left(Right.Item { v: 2 })` compiled, linked and
   ran, passing a `blink_Right` to a `Left` parameter. The bare `Item { v: 2 }` is correctly rejected.
2. **Silent miscompile, return position.** `fn f() -> Left { Right.Item { v: 2 } }` likewise.
3. **Silent miscompile, declared type.** `let e: Other = DbError.Timeout { ms: 5 }` compiled clean;
   the bare form reports *"declared type Other but got DbError"*.
4. **False positive — correct code rejected.** With an unrelated enum named like the variant in
   scope, `Left.Item { v: 9 }` was rejected with *"expects Left, got Item"*. The same discarded
   qualifier that silently built the wrong enum also **refuses** the right one. A fail-open cause can
   present as a spurious error, and that direction is often the sharpest MVCE.
5. **The diagnostic's own remedy was the broken path.** `error[AmbiguousConstruction]` tells the user
   to *"qualify it (e.g. `SomeEnum.Item { ... }`)"* — and qualifying produced mode 1.
6. **Wrong C emitted for correct code** (codegen's half): `Right.Item { v: 2 }` emitted a
   `blink_Left` initializer.
7. **`cc` escapes** in the generic-enum spellings, where no diagnostic fired at all.

**The fix is one behavior in one regen.** Typecheck resolves the **prefix** as an enum *before*
falling through to `lookup_named_type(sname)` — which stays, because the module-qualified struct
literal still needs it — and routes through `tc_enum_structlit_instance_tid` exactly as the bare path
does, so a generic enum reverse-infers its instance (`Tree[Int]`) and the two spellings stay
code-identical per `:1036`. The decl node comes from `tc_type_decl_nodes` keyed by the **enum**, not
from `tc_variant_enum_decl_nodes`, which is first-declared-wins per *variant* name and would have
reproduced the very confusion being fixed. Codegen makes the **qualifier win**, falling back to the
global map only when the prefix names no enum carrying the variant — which keeps `mod.Type { .. }`
falling through to the plain-struct path untouched. A prefix enum that lacks the named variant still
falls through to `TYPE_UNKNOWN`; that wants an unknown-variant diagnostic which does not exist for
any of the three variant spellings (`krwywm`).

**Attribution, checked twice.** Family-A rows 131 → 119: −12, exactly the 12 predicted sites, none
added, all `__main__` (108 → 96), and family-A cells 18 → 12 as all six spellings retired together.
Total cells 401 → 396. `diverge` was **unchanged** at 4174 and `agree` rose by **152**, and neither
figure was accepted at face value. A per-cell row-count diff showed all 12 rows converting in place
to class-B `tid=X flat=X` cells — the rows did not leave `diverge`, they changed family. A per-root
delta histogram accounted for the +152 exactly: **28 roots × 5 + 3 roots × 4**. The multiplier is
**per file, not per compiler** — 28 roots compile both `typecheck.bl` and `codegen_expr.bl` and gained
5 `let`s each, while 3 compile only `typecheck.bl` and gained 4. Earlier sections in this document
used a single "31 roots compile `typecheck.bl`" figure; measure the histogram instead of assuming one
multiplier. Zero residue.

**A verified Stage-3 hazard, found by root-causing the class-B landing instead of assuming it.**
`ty_tp_same_shape` (`typecheck.bl:12392`) compares `tk_to_ct(kind)` against `tp_get_kind(tp)` **before**
it compares names, and `tk_to_ct` maps `TyKind.Enum => CT_ENUM` (`:12253`). But `type_enum`
(`codegen_types.bl:166`) is `CT_ENUM`'s **only** tp producer and has **zero callers** — a data enum's
flat value is always `CT_STRUCT`, stamped by `set_var_struct` at `codegen_expr.bl:6750`. So **every
enum-typed variable reports class-B divergence by construction**, verified by hand: `let w = Wrap { n: 1 }`
agrees, `let p = Pay.Item { v: 2 }` diverges `tid=Pay flat=Pay`. Two consequences. Stage 3's
`c_type_from_tid` **must lower a `TyKind.Enum` tid to the same C form as a struct**, or every enum in
the corpus changes type. And the dead `CT_ENUM` plus the dead `tk_to_ct` Enum arm are fresh evidence
for Stage 4's deletion group 1.

**Test.** `tests/test_9md3r1_qualified_variant_structlit.bl`, 11 rows, 8 red before / 11 green after:
the cross-enum argument and return miscompiles, the declared-type and argument-position mismatches,
the unrelated-enum-named-like-the-variant row asserted as a **running** program (it was a false
positive, so the assertion is `left:9` at exit 0), the generic-enum equivalence proved by both
spellings emitting the identical `(blink_Tree_0Int){.tag = 0, .data.Leaf = {.value = 5}}`, the generic
wrong-slot rejection, bare/qualified interchangeability, the qualifier selecting between two enums
sharing a variant name, and two controls: the module-qualified struct literal
(`testing.Cleanup { action: .. }`) still resolving, and a struct named like a variant staying an
`E0518` declaration-time collision — which is *why* prefix-first resolution is unambiguous.
`task regen` + `task ci` green (649 test files, 0 failed; fmt 1518 passed, 0 failed).

**Three byproducts filed, all found while probing and none fixed inline.** `x056sx` — an enum-variant
struct-lit's field **names and types** are unchecked in *both* spellings. `krwywm` — an unknown
qualified variant in the unit and tuple spellings silently builds **another enum's** variant. `5fn53v`
— a generic enum's struct-style variant **pattern** erases its payload binding to `void`, found by
probing the bare control of the generic row and therefore not caused by this fix.

### hgd2az — seven fail-open modes at a counter reading zero (CLOSED, −3 rows)

The rows are the least interesting thing about this one. Read it for the caveat it puts on Stage 3's
exit gate.

**The cause, one line.** The three seams that consume a channel element — `send` and `recv`
(`codegen_methods.bl`) and the `for v in ch` drain (`codegen_stmt.bl`) — each asked
`get_var_channel_inner`, a read of codegen's **flat** `ScopeVar` field. That field is stamped at
`codegen_stmt.bl:3509` from `get_var_channel_inner(val_str)`, and `val_str` is the **emitted C
expression** for the initializer (`blink_channel_new(4)`), never a variable name. The lookup
therefore missed for every constructed channel and the `CT_INT` default one line below became the
element type of **every channel in every program**.

**Consequence, and it is the `twq9kz` / `pvhaew` shape a sixth time.** Both consumers already had a
`CT_STRING` arm. Both were **dead by keying**: nothing could put anything but `CT_INT` in that field,
so the arm existed, read as coverage, and could not be reached. Arms that cannot be reached are not
arms.

**The spec was checked first and it moved the ticket.** `sections/04_effects.md:1751` is the only
channel text in the spec and it spells the constructor `channel.new[Int](buffer: 10)` — **the element
type is written down at the construction site** — and drains with `for value in ch`. The plan doc's
own note guessed Channel was "likely genuinely under-determined … the arg is a capacity, not an
element type". That premise was wrong for the spec's spelling, and `parser.bl:2885` already kept the
type argument in `type_params`. So there was no inference problem to solve for `channel.new[T]`: there
was a type that had been written down explicitly and then discarded. Only the **bare** `Channel(n)` —
which appears in no spec section and in no `blink llms` topic, and which is what the whole corpus
uses — names no element at all, and that is `w3v2e6`.

**Seven fail-open modes, every one reproduced by *running* a program:**

| | shape | observed |
|---|---|---|
| 1 | `Channel[Str]` + `.recv()` | printed `94463530825302` — a pointer as an integer. Exit 0 |
| 2 | `Channel[Str]` + `for v in ch` | same garbage, from the spec's own drain idiom |
| 3 | `channel.new[Str](buffer: 4)` | same garbage — the element type was **explicit** and discarded anyway |
| 4 | `Channel[Bool]` | printed `1`, not `true` |
| 5 | `Channel[Float]` | `cc` escape: *cannot convert to a pointer type* on `(void*)1.5` |
| 6 | `Channel[Pt]` | same `cc` escape on `(void*)_s0` |
| 7 | `ch.send(0)`, any channel | **silent data loss.** `(void*)(intptr_t)0` *is* `NULL`, and `NULL` is `blink_channel_recv`'s end-of-stream sentinel, so a drain over a channel whose first value is `0` printed **nothing** — the `0` and every value behind it dropped, exit 0 |

Mode 7 is the one to remember. It needs no annotation, no generics and no unusual spelling: three
lines of ordinary Blink using the corpus's own idiom, and the program silently produces nothing.

**The fix is one rule, not six arms.** Every element is **boxed**: `send` GC-allocates a cell of the
element's own C type, stores the value and sends the cell's address; `recv` and the drain dereference
with the same C type. The per-type casts *are* modes 4–6, and a boxed representation has no per-type
arm to be short of. It also retires mode 7 for free and with **no runtime-header change**, because a
box address is never `NULL`: `NULL` now means exactly "closed and empty" and nothing else.

**This is codegen's first consumer of the Stage-1 structural accessors.** The element type comes from
`tc_lookup_node_tid` on the receiver/iterable node, through new `tc_channel_elem_ct` /
`tc_channel_elem_struct` in `typecheck.bl` built on `tc_tid_kind` / `tc_tid_child_count` /
`tc_tid_child` / `tc_tid_struct`. Two properties of that helper are worth copying at every later
Stage-3 seam:

- **The gate and the answer are the same function.** `tc_channel_elem_ct` returns a `CT_*` only for an
  element it can actually spell, and `-1` otherwise — and `-1` means the caller keeps its existing
  flat emission, byte for byte. A separate "is this supported" predicate would be a second list to
  drift out of sync with the arms, which is the allow-list defect this campaign has now seen **ten**
  times. One function cannot disagree with itself.
- **The exclusions are deliberate and named.** `List` / `Map` / `Set` / `Option` / `Result` / `Tuple` /
  `Ptr` / `Fn` / `Handle` / `Channel` / `Iterator` all answer `-1`. A container element round-trips
  through the box perfectly; what does not round-trip is **its own** element/key/value metadata, which
  lives in flat side fields a `recv()` result has no way to carry. Claiming them would move the wrong
  element type **one level down** — the exact defect being fixed. A generic struct instance is
  excluded for the same reason in a different currency: its C name is the monomorphised spelling, and
  emitting `blink_Box` for a `Box[Int]` element names a type that was never emitted. The `match` over
  `TyKind` is exhaustive, so Stage 0's net names any kind added later instead of letting it fall
  through to a plausible `CT_*`.

**The caveat, and the reason to read this entry at all: the instrument could not see any of it.**
Before the fix, the corpus contained **zero** class-B Channel rows. Not few — zero. The decisive
evidence for this ticket, `var=ch tid=Channel[Str] flat=Channel[Int]`, came from a hand-built MVCE,
because the entire corpus spells `Channel(n)` and **nothing in `tests/`, `examples/` or `src/`
annotated a channel or used the spec's own constructor with a non-`Int` element**. Seven live
fail-open modes, two of them `cc` escapes and one of them silent data loss, at a counter reading zero.

That is `feedback_corpus_sweep_is_not_coverage` at full strength, and it is a **caveat on this plan's
Stage-3 exit gate**: *the counter at 0 means the corpus stopped disagreeing, not that the tid is
authoritative.* The gate stays — it is still the only finite instrument this campaign has — but it
bounds divergence over shapes that are **written down somewhere**, and a shape absent from the corpus
is invisible to it no matter how broken it is. Two consequences adopted here:

- Rows 10–12 of the test write the annotated shapes **directly** rather than only through
  `compile_and_run`, so the corpus now contains an annotated `Channel[Str]`, an annotated
  `Channel[Pt]` drained by value, and a `channel.new[Str]`. Verified the tap now fires. A shape has to
  be written down before it can be counted.
- For each remaining ranked cause, ask what shapes the corpus does **not** contain before reading its
  row count as the size of the problem.

**Attribution, and all movement accounted for.** Family-A rows 119 → 116 on the 874-file common basis.
The three are precisely the corpus's only three `channel.new[T]` sites
(`tests/test_async_parse.bl:13`, `tests/fmt/{expected,input}_channel_new_wrap.bl:2`), which the new
`infer_type` arm now types. All three in `__main__`, making it eight consecutive `__main__`-only
deltas. Every remaining `flat=Channel[Int]` family-A row (21 of them) is a bare `Channel(n)` and
belongs to `w3v2e6`.

Total `sv_ty_or_flat_at` calls moved +491 — `agree` +463, `diverge` +28 — and the whole of it is the
compiler's own new `let`s, per the per-file-multiplier rule:

- +31 `diverge` from **one** new `TyKind`-typed `let` (`typecheck.bl:12961`, `let k = tc_tid_kind(e)`)
  × the 31 roots that compile `typecheck.bl`.
- +460 `agree` from the other 16 new `let`s: 4 × 31 in `typecheck.bl`, 7 × 28 in `codegen_methods.bl`,
  5 × 28 in `codegen_stmt.bl`.
- +3 `agree` / −3 `diverge` from the rows that flipped. 460 + 3 = 463 ✓, 31 − 3 = 28 ✓.

The +31 is the **already-documented `CT_ENUM` hazard**, not a regression: `tk_to_ct` maps
`TyKind.Enum => CT_ENUM`, `type_enum` is `CT_ENUM`'s only producer and has **zero callers**, so a data
enum's flat is always `CT_STRUCT` and **every enum-typed variable is class B by construction**. Every
`TyKind`-typed local added between now and Stage 3 adds one row per root. Do not chase them; Stage 3's
`c_type_from_tid` must lower `TyKind.Enum` to the struct C form and they go together.

**One residual row, stated honestly.** An annotated `Channel[Pt]` still reads `tid=Channel[Pt]
flat=Channel[]` at `emit_let_binding.decl`. `set_var_channel(name, CT_STRUCT)` has nowhere to put the
element's struct **name** — there is no `set_var_channel_full` — so the flat pair spans depth 1 and
stops, which is this plan's thesis showing up as a leftover. Behavior is correct because the seams
read the tid; only the flat shadow is short. Adding a flat field is what the non-goals forbid, and
Stage 3's `sv.ty` authority flip is what closes the row.

`task regen` + `task ci` green (650 test files, 0 failed; fmt 1520 passed, 0 failed). Test:
`tests/test_hgd2az_channel_element_type.bl`, 12 rows, 8 red of 9 → 12 green.

**Three byproducts filed, none fixed inline.** `crxrh3` — `channel.new[T](buffer: n)`'s arguments are
never name-resolved, so an undefined name there reaches `cc` with `blink check` reporting ok (the
`1b7ggq` shape). `eg0p6y` — `ch.send(x)` is never checked against the element type, so a
`Channel[Int]` accepts a `Str` (the allow-list shape). `yzan52` — `type:spec`: what should `.recv()`
answer on a **closed, empty** channel? Today it is the element's zero value, indistinguishable from a
sent zero value; four candidate answers are enumerated on the ticket. A documented concurrency
primitive's end-of-stream contract is not a codegen decision, so the boxing fix deliberately preserved
today's behavior.

### nrrs28 — `Template[C]` was not a type, so the phantom and all seven methods were unenforceable (CLOSED, −9 rows)

**The cause was one level above the ticket's title.** The ticket says the introspection intrinsics
resolve no return type. They *could not* have. `Template` is claimed by `is_primitive_type`
(`typecheck.bl:6865`), so no user type can take the name — but `resolve_type_parts` had **no arm for
it**, so a `tpl: Template[DB]` parameter fell through `resolve_type_name` to
`make_typevar("Template")`. The receiver was a typevar, i.e. exactly as permissive as `TYPE_UNKNOWN`,
so **no method arm could have helped**: both halves of the gate fail open at the receiver, before any
`method ==` comparison runs. The ticket's own open question — *"whether `Template[T]` should be a
`TyKind` at all"* — was the fix, and the answer is **yes** on the spec's own words
(`sections/03b_contracts.md:424`: "a compiler-known structural type"). Sixth sighting of the
untyped-receiver family and `w13xgb`'s (Ptr) shape verbatim.

**Blast radius measured before writing anything.** Only **6** matches are exhaustive over the whole
`TyKind` set (`tk_name`, `type_to_str`, `tk_to_ct`, `tc_tid_child_count`, `tc_tid_child`,
`tc_channel_elem_ct`) — plus **4 in `tests/`**, which each carry their own independent enumeration of
the kind set on purpose. Stage 0's net named all ten and the build stayed red until each was answered:
that is the exhaustiveness net doing precisely the job the plan added it for, including in test files
the plan never anticipated.

**Codegen needed no new knowledge, and the list ⊇ arms invariant came back CLEAN — the first time in
this campaign.** `CT_TEMPLATE` and the 7 emitters (`codegen_methods.bl:2108`) have always existed, and
`is_builtin_method` lists exactly the same 7 names. Ten previous causes were an allow-list disagreeing
with its own arms; this one was purely the tid side missing, so the new `tk_to_ct` arm makes the two
universes *agree* rather than adding knowledge to either.

**Six fail-open modes, every one reproduced by RUNNING a program:**

| | shape | observed |
|---|---|---|
| 1 | `let s: Str = tpl.count()` | printed `1` — an Int through a `Str` binding. Exit 0, **silent** |
| 2 | that same `s` passed to a `Str` parameter | `cc` escape, `-Wint-conversion`, no Blink span |
| 3 | `let f: Int = tpl.get_float(0)` | printed `1.5` from an `Int` binding |
| 4 | `let b: Str = tpl.get_bool(0)` | printed `false` from a `Str` binding |
| 5 | `tpl.count(1, 2, 3)` | three arguments to a nullary method, discarded, returned `1` |
| 6 | `tpl.type_tag("zero")` | a `Str` index, unchecked |

Mode 5 is **not** this cause — arity is unchecked for *every* builtin method block (`xs.len(1,2,3)`
compiles too), filed as `drnf86` and deliberately not asserted.

**A real type is STRICTER than a typevar, and that is the part the ranking row did not predict.** The
moment `Template[C]` became a type, every legitimate `db.query("SELECT …")` in the corpus became an
argument-type error — a `Str` where a `Template[DB]` is expected. Accepting the interpolated string
**literal** is not an extra; it *is* the feature (spec `:424`), so `tc_template_arg_ok` had to land in
the same change, on the same footing as the `is_int_literal_node` coercion beside it: a coercion at an
**argument position** granted to a literal, not a claim that `Str` and `Template[C]` are compatible
types. `types_compatible` must keep answering 0 for them — that is what makes the variable case an
error.

**And the rejection the whole feature exists to produce moved a phase earlier.** Spec `:465`/`:470`
writes it out in full: a pre-built `Str` variable is opaque, `E0310`, *"pass the string literal
directly, or wrap values in `Raw()`"*. That check lived in **codegen** (`codegen_methods.bl:3151`),
which means it only ever fired on the **effect-operation** path and only after typecheck had passed
the program. Reporting it from `check_arg_shapes` covers every call shape and stops at the phase that
knows the parameter's type. `tests/test_template.bl` pins `E0310` for exactly that program and stays
green — the code is unchanged, only the reporter is.

**The phantom is now carried AND compared, and the limit on the comparison is worth recording.**
`sections/03b_contracts.md:566` is normative: *"`Template[DB]` and `Template[Shell]` are distinct
types. You cannot pass a `Template[Shell]` to a function expecting `Template[DB]`."* One arm in
`types_compatible` recursing into the phantom — the `Ptr` arm's shape, for a third distinct reason —
enforces it. It is **vacuous for the spelling the spec itself uses**: `DB` and `Shell` there are
**effect** names, effect names are not in the type namespace, so each phantom resolves to a typevar
and typevars unify with anything by design. The arm bites only when the context is a real type. That
gap is `kfefsy` (`type:spec`) and it is a namespace question, not something a compatibility relation
can decide.

**Attribution, and all movement accounted for.** Family-A rows **116 → 107** on the 874-file common
basis. All 9 are `lib/std/db_sqlite.bl:140` (`let tag = tpl.type_tag(i)`), one per db-flavoured root —
exactly the rows this cause was predicted to own, and with them **`std_db_sqlite` goes 9 → 0**, which
puts **every `lib/std` module at zero**. The per-module tail is now `__main__` 93, `cli` 8,
`std_http_server` 3, `build_stdlib` 3. Totals: `diverge` 4202 → 4193 (**−9**), `agree` +40 = the 9
flipped rows plus **one** new `let args_sl` in `typecheck.bl` × the 31 roots that compile it — the
per-file multiplier again, and the whole delta is explained.

`task regen` + `task ci` green. Test: `tests/test_nrrs28_template_introspection_types.bl`, 15 rows,
9 red of 13 → 15 green. Three rows write the shape **directly** into the corpus (own effect, own
handler, every getter consumed at its own declared type) because `db_sqlite` reaches this API only
through a live SQLite connection and `compile_and_run`'s link line has no `-lsqlite3`.

**Five byproducts filed, none fixed inline, and the first is the worst thing found this session.**

- **`zhxq5p`** — a handler method body is **never typechecked at all** when the handler is a
  function's **return value**, which is the spelling all of `lib/std` uses
  (`pub fn sqlite_handler() -> Handler[DB]`). `let bad: Int = "not an int"` inside such a body passes
  `blink check` clean. `pgc3d9` wired `tc_check_handler_method` in at the **call-argument** position
  only, so the tail position was never reached. **This defect ate the first draft of this ticket's
  test**: the negative rows used a `-> Handler[Tpl]` helper and every one of them was asserting
  nothing. They were rewritten to the inline `with handler` form, and the file says so, so the
  workaround can be reverted when `zhxq5p` closes. *A test that asserts a compile error is only as
  trustworthy as the phase that would report it.*
- **`k7mng9`** — a **free** fn with a `Template[C]` param does not decompose its literal, because the
  decomposition gate sits inside the effect-op emitter; the program reaches `cc` with a
  `const char*` where a `blink_template*` is declared. Pre-existing, and the choice between
  "decompose at every Template param" and "restrict `Template[C]` to effect signatures" is a real
  one the spec does not make.
- **`drnf86`** — builtin-method **arity** is unchecked everywhere (mode 5 above), ~10 instances of
  one defect; wants arity attached to the arm as data, not a count check per arm.
- **`fqy7bz`** (`type:spec`) — the spec spells `Template[C]`'s surface as two **fields**
  (`parts: List[Str]`, `values: List[Any]`) while the compiler implements a **7-method** API.
  `values` is **inexpressible**: Blink has no `Any`, which is why the tag-plus-four-getters shape
  exists at all — and that shape also silently limits a template to four scalar types.
- **`kfefsy`** (`type:spec`) — the phantom is vacuous for effect-name contexts, above.

`k0dfjj` stays open and is why this test has **no** `std.db` row: declaring any user effect in a
program that imports `std.db` makes `db_sqlite.bl` itself fail to compile. Its diagnostic is a
tid-vs-flat divergence witness — the message names the receiver from the **tid**, correctly, while
dispatch reads the **flat** ctype — so it is a likely Stage-3 structural fix.

### ps5br9 — the last untyped receiver, and a signature the spec writes and the parser throws away (CLOSED, −5 rows)

**The cause, one line.** Codegen has carried `CT_FFI_SCOPE` (`codegen_types.bl:48`) and a
four-method emitter block — `alloc`, `alloc_n`, `cstr`, `take` (`codegen_methods.bl:4886`) — since the
FFI surface landed, while typecheck had **no `TyKind` for the scope object at all**
(`rg 'ffi_scope|CT_FFI_SCOPE' src/typecheck.bl` found nothing). So `with ffi.scope() as scope` bound
the binder at `TYPE_UNKNOWN` and the **receiver** was permissive before any method arm could run: the
declared type of a result was never compared and no argument was ever checked.

**The premise held, and then sharpened past the ticket — which changed the fix.** The ticket said an
unannotated `let p = scope.alloc()` is "genuinely under-determined" and belongs to E0301. It is not
under-determined. `sections/07_trust_modules_metadata.md:284-286` writes the pointee **at the call
site**:

    let p   = scope.alloc[T]()
    let buf = scope.alloc_n[T](n)

and that spelling **does not parse as a method call**. `parser.bl:2887` accepts a `[` after a member
name for exactly one hard-coded form, `channel.new[T]`; everything else falls through to
FieldAccess-then-index, so the spec's own spelling resolves no method at all and the type argument is
discarded. That is the `hgd2az` lesson verbatim — *a type the programmer wrote down, thrown away by
the front end* — now seen twice in three tickets, and it is the reason `alloc`/`alloc_n` return
`TYPE_UNKNOWN` here instead of a fabricated `Ptr[Int]`, or a `Ptr[α]` that would turn every allocation
in the corpus into E0301 (the `w3v2e6` trap). Filed as **`9qmrma`**; when it closes, both arms can
return `Ptr[T]` and the test row that pins today's `UnresolvedMethod` becomes a positive.

**Ten fail-open modes, every one reproduced by *running* a program:**

| | shape | observed |
|---|---|---|
| 1 | `let bad: Str = scope.cstr("hello")` | `blink check` ok, ran, printed `<value>` |
| 2 | `let bad: Int = scope.cstr("hello")` | same — a pointer laundered into an `Int` |
| 3 | cstr result passed to a **`Str` parameter`** | compiled, ran, and **printed the right answer** |
| 4 | `let bad: Ptr[Pollfd] = scope.cstr(..)` | `cc` escape: *incompatible pointer type* `uint8_t *` |
| 5 | `scope.cstr(42)` | `cc` escape: *expected `const char *`* |
| 6 | `let bad: Int = scope.take(p)` | ok, ran, printed `<value>` |
| 7 | `scope.take("not a pointer")` | accepted, ran. A `Str` freed as a `Ptr` |
| 8 | `scope.alloc_n("four")` | **silent.** `calloc((size_t)("four"), ..)` → NULL, and every later write is a null deref at some unrelated line |
| 9 | `ffi.scope(7)` | extra argument to a nullary intrinsic, discarded |
| 10 | `let taken = scope.take(p)` then `.deref()` | `cc` escape: *invalid use of void expression* — **not closed here**, see below |

Mode 3 is the one to remember, and it is the reason this cannot be left to `cc`: `Ptr[U8]` and `Str`
are the same C type, so passing a scoped C string to a `Str` parameter compiles, runs and prints the
correct text. It stays invisible right up to the first pointee that is not text.

**The fix needed no new inference, and two of its three parts were already built.** `cstr` is
monomorphic in the spec (`fn cstr(self, s: Str) -> Ptr[U8]`) and `take` is the identity on its
argument's type, so both are signable from the spec table with nothing more than the argument's tid:

- `TyKind.FfiScope` + `make_ffi_scope_type()`, **childless**. A scope is an opaque arena handle, not a
  container — §07:265-291 gives it three operations and no element type — so it takes `TyKind.Bytes`'s
  shape rather than `TyKind.Ptr`'s, and every structural accessor answers *no children* through arms
  it already has.
- `register_intrinsic_fn_sig("ffi.scope", [], make_ffi_scope_type())` — the `qjfwc6` table entry is
  what actually **types the binder**, because `tc_bind_with_resource` (`w089a0`) binds the binder to
  the resource expression's tid and that tid was `TYPE_UNKNOWN`. The comment in that function claiming
  an untyped `ffi.scope()` is what keeps things working is now the thing that changed. The entry also
  supplies the arity check of mode 9 **for free**: nullary is data in the table, not an arm.
- the four-method receiver block in `infer_type`, next to `TyKind.Template`'s. `take` passes an
  **unresolved** argument through unresolved on purpose — `scope.take(scope.alloc())` is the corpus's
  own spelling (`tests/test_ffi_scope_escape.bl`) and its argument has no tid by design, per `9qmrma`.

**Attribution, all movement accounted for.** Family-A rows 107 → **102** on the 874-file common basis,
and family-A **cells 12 → 11**: the `tid=? flat=Ptr[Int]` cell is now **gone from the map** — every
unannotated pointer binding in the corpus has a tid. The five rows are exactly the five the ticket
listed (`tests/test_ffi.bl:60,83`, `test_ffi_scope_with.bl:28`, `test_libc_bytes.bl:26`,
`test_yb9ytb_read_fully.bl:31`), all `at=__main__`. Four became **class B**
(`tid=Ptr[U8] flat=Ptr[Int]`) and the fifth went to **agree**, because `taken`'s pointee happens to be
`Int` and the flat fabrication happens to say `Int`.

Total `sv_ty_or_flat_at` calls moved **+93**, which is the three new `let`s in the `FfiScope` arm × the
31 roots that compile `typecheck.bl`, exactly: `agree` +63 = 2 `let`s × 31 + the 1 flip, `diverge` +30
= 1 `TyKind`-typed `let` × 31 − the 1 flip. The +31 is the **documented `CT_ENUM` hazard** and not a
regression (`tk_to_ct` maps `TyKind.Enum => CT_ENUM`, `type_enum` has zero callers, so every
`TyKind`-typed local is class B by construction); it retires when Stage 3's `c_type_from_tid` lowers
`TyKind.Enum` to the struct C form.

**What this fix deliberately does not close, and the largest class-B population in the corpus.** Mode
10 is a *pointee* defect, not a receiver defect: `resolve_ptr_inner_c` (`codegen_types.bl:5630`) reads
`cg_let_target_ann` and nothing else, and the `CT_PTR` declaration branch (`codegen_stmt.bl:3852`)
re-reads the same annotation, falling back to `void*`. So the tid is right and codegen does not read
it — filed as **`0dtbe6`** with two live halves: `Ptr[Float].deref()` **prints `1`** (silent; `deref`
hard-codes `expr_result_type = CT_INT`), and an unannotated take-then-deref is a `cc` error. The sweep
measures **238 class-B rows carrying `flat=Ptr[Int]` over 20 distinct sites** — the flat pair has no
room for a pointee, so it prints `Ptr[Int]` for `Ptr[Pollfd]`, `Ptr[U8]` and `Ptr[Void]` alike. That is
this plan's thesis in a single field, and it is a Stage-3 `c_type_from_tid` cell, not a ticket to fix
one arm at a time.

**The untyped-receiver family is now closed: six sightings, one shape.** `w13xgb` (`Ptr[T]`),
`jzvxav` (`self` in an impl), `w089a0` (the with-resource binder), `nrrs28` (`Template[C]`), `qjfwc6`
(the namespace intrinsics, the same defect one level up) and this one. Every time: **a value the type
pool cannot name makes the receiver permissive, so both halves of the gate fail open** — the declared
type is never compared and the arguments are never checked. The family also split cleanly in two, and
the split predicted the fix each time: `jzvxav` and `w089a0` were **declaration sites that dropped a
type they already had** (~10 lines each, swap in the typed spelling), while `w13xgb`, `nrrs28` and
`ps5br9` were **types the pool could not name** and each needed the same three parts — a `TyKind`
variant, a lowering, and a method block.

`task regen` + `task ci` green (652 test files, 0 failed). Test:
`tests/test_ps5br9_ffi_scope_receiver_type.bl`, 14 rows, red before / green after, with the two
corpus-direct rows written **directly** rather than through `compile_and_run` so the instrument can
see a typed scope (`feedback_corpus_sweep_is_not_coverage`).

### ta51an — the spec's own disambiguation form, unchecked in typecheck and mis-resolved in codegen (CLOSED, −1 row)

**The cause, in two halves, because there were two.** `sections/03c_protocols.md:697-712` makes
`Trait.method(receiver, args)` a first-class call form and the resolution table at `:773` makes it the
**only** way to disambiguate a method that two traits both define (§3c rule 3). Neither phase
implemented it:

- **typecheck had no arm for a trait-NAME receiver.** The MethodCall path tests `nr_has_binding(obj)`
  for a value and then falls through, so `Describe.describe(p)` returned `TYPE_UNKNOWN` and all four
  gates failed open at once — the declared type was never compared, arity was never checked, argument
  types were never checked, and the trait actually **named** was never verified.
- **codegen resolved the symbol right and the return type wrong.** `impl_type_implements_trait_method`
  picks the correct `blink_Point_A_go`, but the type came from
  `get_impl_method_ret(type_name, method)`, whose `impl_method_idx` is keyed `(type, method)` with **no
  trait** (`codegen_types.bl:1033`). With two traits defining `go` on one type, the last registration
  won — so the escape hatch the spec provides for exactly that collision was itself decided by
  registration order.

**Nine fail-open modes, each reproduced by *running* a program** (and the two that looked like silent
wrong output on the first pass were my own probe bug — a literal `{` in Blink escapes as `\{`, so a
generated `\{v}` prints `{v}` and interpolation was never involved):

| | shape | observed |
|---|---|---|
| 1 | `let bad: Str = Sizer.size(p)` | `cc` escape: `int64_t` into `const char*` |
| 2 | `let bad: Int = Describe.describe(p)` | `cc` escape, the mirror image |
| 3 | `let bad: Bool = Sizer.size(p)` | ran, printed `bad=5`, and `if bad` was taken |
| 4 | two traits sharing `go`, `let a: Bool = Flag.go(p)` | **silent.** printed `a=1`, and the C read `const int64_t sa = blink_Point_A_go(p)` from a `const char*` function in the `Str` variant |
| 5 | `B.go(p)` where `B` does **not** define `go` | **silent.** emitted `blink_Point_A_go` — the other trait's method |
| 6 | `Describe.describe(p, 42)` | extra argument discarded |
| 7 | `Describe.describe()` | no receiver at all, accepted |
| 8 | `Adder.add2(acc, "two", 9)` | arguments transposed against the signature, accepted |
| 9 | `Display.display(p)` | `Display` emitted as a bare C identifier — `cc`: undeclared |

Mode 5 is the one that matters: the qualifier is the disambiguation mechanism, so a wrong qualifier
silently calling the *other* trait's method is the precise failure the form exists to prevent.

**The fix, and why it needs no carve-out list.** typecheck gets one arm in `infer_type`'s MethodCall
path, placed immediately after `obj_is_value = nr_has_binding(obj_name)` so a **value** named like a
trait still wins (`mjsbwm`'s gate). It infers the first argument as the receiver, looks up the
trait-qualified fnsig `{recv_type}_{trait}_{method}` — the key `tc_mangle_impl_fnsig` has always
written — checks arity and `check_arg_shapes`, and returns the impl's declared return type. codegen's
`reg_impl_entry` now writes a second, trait-qualified `impl_method_idx` key
(`type\ttrait\tmethod`), and `get_impl_method_ret_q` consults it before falling back to the bare one;
all three qualified call sites (`codegen_methods.bl:3293`, `:3328`, `codegen_expr.bl:5449`) pass the
`owner_trait` they had already computed for the symbol.

Mode 5's rejection is gated on `tc_trait_declares_method` — an exact-name membership test against the
**trait's own declaration list** — and deliberately *not* on "no impl fnsig exists". That is the whole
reason the change carries no exemption table: trait **default** methods (`mwxtyj`), `Iterator`
adapters, and `From`/`TryFrom`'s source-typed keys all still resolve to today's answer, because their
trait does declare the method. Only a genuinely wrong trait name errors.

`Display.display(x)` (mode 9) is included rather than filed, because it is the same call site and the
same behavior statement — §3c:706 writes it out as the headline example. A `Display` impl declares
`fmt`, not `display`, so the impl-method registry has no entry to resolve; the route goes through
`synthesized_display_call`, already the sole resolution point for "call this type's `Display`", which
returns `""` when a real user `display` method owns the symbol so the ordinary impl path still wins
there.

**Deliberately out of scope, each verified rather than assumed.** The **sealed builtin ops traits**
(`StrOps`/`ListOps`/`BytesOps`/`StringBuildOps`) keep today's behavior and are **`9kgj76`**: their
qualified form dispatches to codegen intrinsics with no fnsig to read, so typing them needs a
per-method signature table, not another resolution arm. The new arm is gated on
`is_sealed_builtin_trait == 0`, and codegen's sealed-ops check still runs **first** (`sb3125`'s
ordering). Typevar and unknown receivers pass through untouched, which is what keeps the spec's
`fn show[T: Describe](v: T) -> Str { Describe.describe(v) }` compiling — pinned as a row. Trait default
methods stay broken for **both** spellings (`mwxtyj`).

**One mode did not close, and the reason is a 5-0 spec vote the compiler contradicts.** Mode 3 —
`let bad: Bool = Sizer.size(p)` — is *still accepted*, and not because the fix missed it:
`types_compatible` (`typecheck.bl:8402`) carries an explicit arm, *"Int and Bool are interchangeable in
Blink (C-style truthiness)"*. `sections/02_syntax.md` is the opposite and normative: *"No truthiness.
The condition must be `Bool`. `if 0 { }` and `if items { }` are compile errors"* — vote 5-0, on the
stated ground that requiring an explicit `Bool` eliminates a bug class. Today `if 0 { }`,
`while 1 { }`, `let n: Int = true` (which **prints `n=true`**), `takes_bool(7)`, `flag = 3` and
`List[Bool] = [1, 0]` all compile, and the sharpest one holds a non-canonical Bool:

    let b: Bool = 2
    if b == true { .. } else { .. }   // takes the ELSE branch
    io.println("b={b}")               // prints b=2

so a `Bool` can hold `2`, compare unequal to `true`, and display as `2` — while `let n: Int = true`
displays from the *declared* type instead. Filed as **`td3yx5`** and typed `type:spec`, not `type:bug`:
Blink lowers `Bool` to `int64_t` and the compiler's own source trades on the interchange at every
`-> Int` predicate, so removing the arm is a corpus-wide language decision, and it has to answer
whether the enum precedent (`dhggkg` — nominally distinct, `.to_int()`/`.from_int`, comparison
unaffected) applies verbatim. The test row is pinned at today's accepting answer with a pointer; it
becomes a positive when `td3yx5` closes.

**Attribution, all movement accounted for.** Family-A rows **102 → 101** on the 874-file common basis,
and the single row is `tests/trait_test.bl:34`, `let s2 = Describe.describe(p)` (`tid=? flat=Str`) —
the corpus's *only* real unannotated qualified trait call, now `agree`. Family-A cells stay 11. Total
`sv_ty_or_flat_at` calls moved **+400** = 13 new declaration rows × 31 compiler roots − 3, the three
being `src/compiler.bl`, `src/lsp.bl` and `src/embedded_stdlib_registry.bl`, which compile one fewer of
the four modified modules (the fix adds 14 `let`s, 13 of which reach `emit_let_binding`). The only new
diverge **signature** is `var=qt_k tid=TyKind flat=Int` ×31 — the documented `TyKind`-local hazard
(`tk_to_ct` maps `TyKind.Enum => CT_ENUM`, so a `TyKind`-typed local is class B by construction), which
retires with Stage 3's `c_type_from_tid`.

**The blast radius was measured before the arm was written, and it is why this was safe.** `src/` and
`lib/` contain **zero** real qualified trait calls — the `Display.display` and `BlockHandler.exit`
grep hits are inside `diag_explain` documentation strings — so no amount of new strictness here can
break self-host through this surface. `tests/test_trait_qualified.bl` is entirely sealed-ops, which the
arm excludes by construction.

`task regen` + `task ci` green (653 test files, 0 failed; fmt 1526 passed). Test:
`tests/test_ta51an_qualified_trait_call_type.bl`, 15 rows, 6 passed / 9 failed before → 15/15 after,
with the corpus-direct rows written **directly** rather than through `compile_and_run` so the
instrument can see them (`feedback_corpus_sweep_is_not_coverage`), and 6 regression pins (unannotated
single-trait call, multi-argument call, trait-bound generic receiver, sealed ops, the still-ambiguous
*unqualified* call, and an unknown method on a trait name).

### wnbsen — the `if` tail the recovery forgot, and the gate one line above it (CLOSED, −1 row)

**The last unblocked family-A cause, and it was one missing arm.** `tc_scoped_value_memo`
(`typecheck.bl:10734`) is the `bfq7nf` recovery for *"a value that names a binding introduced by the
very construct being inferred"*: `tc_check_body`'s LetBinding arm infers the initializer **before**
walking it, so at that moment `nr` has no frame for the initializer block and its locals are unknown.
The recovery reads the tid the in-scope walk memoized one step later. It recurses `WithBlock`,
`AsyncScope`, `Block` and `MatchExpr` — and had **no `IfExpr` arm**, so

    let s = {
        let p = "v"
        if n == 0 { p.concat("-a") } else { p.concat("-b") }
    }

fell through to `tc_lookup_node_tid(ifexpr)` = `TYPE_UNKNOWN`. A `match` tail spelling the same
program was typed; the `if` tail was not. Two spellings, two answers.

**Why the mistake is invisible exactly where it is.** `infer_type`'s IfExpr arm (`:10498`) skips the
branch compare when either side is UNKNOWN and returns *the other branch*. In the speculative pass
`p` is unknown, so a `Str` branch built from `p` reads UNKNOWN and the arm answers with whatever the
other branch happens to be. That is why `{ let p = 5  if c { p + 1 } else { p + 2 } }` was never
affected — an `Int` from an unknown `p` still infers `Int` — and why the family is narrower than "a
block-`let` with an `if` tail": it needs a branch value whose type comes from the block-local
**itself**.

**Fail-open modes, each reproduced by running a program:**

| | shape | observed |
|---|---|---|
| 1 | `let bad: Int = { let p = "v"  if c { p.concat("-a") } else { .. } }` | **silent.** `blink check` clean, ran, printed `bad=v-a` — an `Int`-declared binding holding a `char*`, displayed from the flat codegen type rather than the declared one |
| 2 | the same value passed to an `Int` **parameter** | `cc` escape, no Blink span: *makes integer from pointer without a cast* |
| 3 | an else-if chain, `let bad: Int = ..` | **silent**, printed `bad=v-b` |

**The arm, and the one case it deliberately declines.** Both branch bodies are Blocks the walk did
memoize, so the answer is there to be read: recurse `node_then_body` / `node_else_body`, return the
other side when one is UNKNOWN, and `type_merge` when both are known. When the two are known and
**incompatible** it returns `-1` and declines, for two independent reasons. Merging would return the
then-branch (`type_merge` returns `a` when the kinds differ), which would make
`if c { p.concat("-a") } else { 7 }` — **rejected today** — compile. And reporting the mismatch here
would double-report every ordinary `if`, because `infer_type` reports as a side effect; reading memos
and never re-inferring is the whole design of this recovery.

`loop { break v }` needed no arm: `let s = loop { .. }` is `error[KeywordAsIdentifier]` — a `loop` is
not a value expression in Blink at all, so a `loop` block tail is `Void` and today's *"return value
type Void does not match Str"* is the right answer.

**The byproduct is the gate one line above the recovery, and it is a separate defect.** The recovery
runs only `if inferred_tid == TYPE_UNKNOWN` (`:11186`). A compound tail value whose **element** names
a block-local infers as `List[?]` — which is not `TYPE_UNKNOWN` — so the gate is false, the recovery
never runs, and the erased element stands. Filed as **`gmb211`**, with the contrast that isolates it:
`let xs = if n == 0 { ["a"] } else { ["b"] }` followed by `let bad: Int = xs.get(0).unwrap()` is
correctly **rejected**, while wrapping the same `if` in a block-`let` makes it compile and print
`bad=v-a`. It is not the missing arm — a plain block tail and a `match` tail erase `[p]` identically,
so the axis is the element, not the tail kind — and it wanted a `tc_tid_has_unknown` predicate on the
`tc_tid_has_bare_typevar` model plus a "take the memo only if strictly better" rule. The row was
pinned **live** in the test (`var=xs tid=List[?] flat=List[Str]`); it is now `agree` — **`gmb211` is
closed in the section below**, with the "strictly better" rule replaced by a position-wise fill after
the all-or-nothing form was measured against the ordinary inference path and found to over-decline.

**Attribution, exact.** Family-A rows **101 → 100**, cells 11, and the row that left is
`tests/test_p9ddps_block_let_str_tail.bl:4` — `var=s tid=? flat=Str`, the one the ranked table listed
as the last unblocked cause. The row-count multiset diff is a single line, nothing else moved. Total
`agree` moved **+94** = 3 new `let`s × 31 compiler roots + the one row that changed bucket. Family-A
cells stay 11 because the departing row shared its `(site, tid=?, flat=Str)` shape with `fs.*` rows.

`task regen` + `task ci` green. Test: `tests/test_wnbsen_block_let_if_tail.bl`, 13 rows, 9 passed /
4 failed before → 13/13 after, with the corpus-direct shapes written **directly** rather than through
`compile_and_run` so the instrument can see them, and pins for the two neighbours that already worked
(a `match` tail, `Int`-valued branches) plus the mismatch that must stay rejected.

### gmb211 — the gate one line above the recovery, which read a partial answer as an answer (CLOSED, class B)

**`wnbsen`'s byproduct, and a different defect at a different line.** `wnbsen` was a missing `IfExpr`
arm *inside* `tc_scoped_value_memo`; this is the **gate on the call to it** (`typecheck.bl:11186`):

    if inferred_tid == TYPE_UNKNOWN { .. tc_scoped_value_memo .. }

A compound tail value whose **element** names a block-local infers as `List[?]` — which is not
`TYPE_UNKNOWN` — so the gate is false, the memo the in-scope walk already wrote is never read, and the
erased element stands. **The tail kind is not the axis**: a plain block tail, a `match` tail and an
`if` tail erase `[p]` identically. The element is.

Every carrier erased, measured rather than assumed:

| tail | before | after |
|---|---|---|
| `{ let p = "v"  [p] }` | `tid=List[?]` | `List[Str]` — **agree** |
| `{ let p = "v"  Some(p) }` | `tid=Option[?]` | `Option[Str]` — **agree** |
| `{ let p = "v"  Ok(p) }` | `tid=Result[?, ?]` | `Result[Str, ?]` — parity with the ordinary path |
| `{ let p = "v"  (p, 1) }` | `tid=(?, Int)` | `(Str, Int)`, flat still `Tuple2_str_int` |
| `{ let p = "v"  [[p]] }` | `tid=List[List[?]]` | `List[List[Str]]`, flat still `List[List[Int]]` |

`Result[Str, ?]` is the **right** answer, not a residual: the ordinary path gives `let a = Ok("v")` the
same `Result[Str, ?]`, because nothing constrains the error side. Measuring the ordinary path first is
what stopped the fix from over-reaching here.

**Fail-open modes, each reproduced by running a program:** `let bad: Int = xs.get(0).unwrap()` **silent**,
ran and printed `bad=v-a`; the same through `Option` (`xs.unwrap()`) and `Tuple` (`t.0`) **silent**, same
output; and the element passed to an `Int` **parameter** escapes to `cc` with no Blink span —
*makes integer from pointer without a cast*.

**The contrast that isolates the gate rather than the walk.** The same `if` **not** wrapped in a
block-`let` is correctly rejected, because there is no block-local for the speculative pass to miss and
ordinary inference answers `List[Str]` on the first try:

    let xs = if n == 0 { ["a"] } else { ["b"] }
    let bad: Int = xs.get(0).unwrap()      // error[TypeError]: declared Int but got Str

**The fix is position-wise, and the first version of it was wrong.** An all-or-nothing "take the memo if
it has no hole" rule left `Ok(p)` at `Result[?, ?]` — the memo has a hole on the error side forever, so
the rule declined a strictly better answer. The shipped rule is `tc_tid_fill_unknowns(base, src)`: walk
the two tids together and substitute `src`'s child **only where `base` has a hole**. Three invariants,
each load-bearing:

- **A concrete position is never overwritten.** So the recovery can only add information.
- **An unbound metavar is never pinned.** `tc_tid_has_unknown` matches the shared `TYPE_UNKNOWN`
  singleton and *not* `tc_is_unbound_metavar`, so `List[α]` reports no hole and is left for unification.
  Pinning α from a memo is the lossy direction `sskpk8` refuses.
- **Differing kinds return `base` untouched**, so nothing is invented when the two disagree.

`tc_tid_has_unknown` is the third member of the predicate family beside `tc_tid_has_unbound_metavar` and
`tc_tid_has_bare_typevar`, recursing the same shape. Struct and enum instance params are deliberately
left alone — their tids belong to the `tc_*_instance_tid` machinery, not to this recovery.

**Attribution, exact, and this is a class-B fix so family A does not move.** Family-A rows hold at
**100**, cells at **11**; `diverge` 4252 → 4283 and `agree` +372 on the 874-file common basis. The
**only** signature that changed is `var=k tid=TyKind flat=TyKind` **+31** — one new declaration
(`let k = e.kind` in `tc_tid_has_unknown`) × the 31 roots that compile `typecheck.bl`, landing in the
documented `TyKind`-local hazard that `ta51an` recorded and Stage 3's `c_type_from_tid` retires. The
other 12 new declarations agree: `+372 = 12 × 31`. Nothing else in the corpus moved by one row.

**The four `tid=List[?]` rows that did *not* move are a different cause, now filed.** They are
`tests/test_spread_list.bl` `var=b/z/w/d`, and they are `[..a]` — a list literal whose **first** element
is a spread. `infer_type`'s ListLit arm takes the element type from element 0 only and has **no
`SpreadExpr` arm**, so `..a` reads `TYPE_UNKNOWN`. Filed as **`08a267`**, with the position axis pinned
(`["q", ..a]` is correct, `[..a, "q"]` is erased) and a **silent wrong value** as the MVCE:
`let a: List[Option[Str]] = [Some("x")]  let b = [..a]  let bad: Int = b.get(0).unwrap().unwrap()` runs
and prints `bad=94036413253206`. It is **not** a homogeneity gap — `let b = [1, "x"]` compiles today with
no spread anywhere. Like `gmb211` it is a Stage 3 **prerequisite** rather than a subsumed cell: the flat
side is *right* and the tid is *wrong*, so the authority flip converts it from a fail-open into a hard
miscompile. **Now CLOSED — see the section below**, where all four rows flipped and nothing else moved.

**The nested case reached the tid and stopped one level short of the value.** `[[p]]` now recovers
`List[List[Str]]`, and codegen still fabricates an `Int` element at depth 2 — reading the inner element
prints the pointer as a number and a `Str` method on it is `error[UnresolvedMethod]`. That is **`f9hgt9`**,
it reproduces on a plain `let ys = [["ab"]]` with no block-`let` anywhere, and it is a class-B cell Stage
3's lowering subsumes. The test row asserts the **outer** list only, so it stays a live pin for the tid
half.

`task regen` + `task ci` green; `task test --force` **676 test files, 676 passed, 0 failed, 0 build
errors**. Test: `tests/test_gmb211_partial_erasure_recovery.bl`, 15 rows, with the carrier shapes written
**directly** into the corpus rather than through `compile_and_run` so the instrument can see them
(`feedback_corpus_sweep_is_not_coverage`), three pins for what already worked (no block-local, a scalar
tail, a `match` tail) and a **monotonicity** pin — an `Int` element declared `Str` must still be rejected,
because the widened gate now runs the recovery over shapes that already had a complete answer.

### 08a267 — the element type an element *contributes*, which a spread does not have (CLOSED, −4 rows)

**`gmb211`'s four leftovers, and the narrowest fix in this document.** `infer_type`'s ListLit arm
(`typecheck.bl:10493`) took the literal's element type from element 0 with `infer_type(elem)`, and
`infer_type` has **no `SpreadExpr` arm** — so `[..a]` read `TYPE_UNKNOWN` and the literal came out
`List[?]`. **Position is the axis, not the presence of a spread**, which is what proves the arm and not
the spread machinery is at fault:

| literal | before | after |
|---|---|---|
| `[..a]` | `tid=List[?]` | `List[Str]` — **agree** |
| `[..a, "q"]` | `tid=List[?]` | `List[Str]` — **agree** |
| `[..a, ..c]` | `tid=List[?]` | `List[Str]` — **agree** |
| `[..x, 99, ..y]` | `tid=List[?]` | `List[Int]` — **agree** |
| `["q", ..a]` | `List[Str]` | `List[Str]` — already right, pinned |

**Fail-open modes, each reproduced by running a program:** `let bad: Int = b.get(0).unwrap()` **silent**,
ran and printed `bad=x` — an `Int`-declared binding holding a `char*`; through `Option`
(`let a: List[Option[Str]] = [Some("x")]`) **silent and the printed value is wrong**,
`bad=94036413253206`, the `Str` pointer as an integer; and the element passed to an `Int` **parameter**
escapes to `cc` with no Blink span — *makes integer from pointer without a cast*.

**Not a homogeneity gap, measured rather than assumed.** `let b = [1, "x"]` compiles today with no
spread anywhere. §2.16 says nothing about a heterogeneous plain literal, so the fix stops at the spread.

**The fix names the right concept, and that is why it is one function.** What an element needs to
answer is not "what is my type" but **what element type do I contribute**: a spread contributes its
operand's *element*, everything else contributes itself.

    fn tc_list_elem_contribution(elem: Int) -> Int {
        if node_kind(elem) != NodeKind.SpreadExpr { return infer_type(elem) }
        let src_t = tc_resolve(infer_type(node_value(elem)))
        if tc_tid_kind(src_t) == TyKind.List { .. tc_tid_child(src_t, 0) .. }
        TYPE_UNKNOWN
    }

Three details are load-bearing:

- **`tc_resolve` is required, not defensive.** `tc_tid_child` indexes `ty_pool` directly and answers
  `-1` for an unresolved metavar; a `-1` child folds back to `TYPE_UNKNOWN` so no caller ever sees a
  non-tid in a tid slot. This is the same Stage-1 contract `tc_tid_child`'s own header records.
- **A non-`List` operand contributes `TYPE_UNKNOWN` rather than a guess.** `[..7]` is a spec violation
  (§2.16), not a shape to invent an element for; reporting it belongs with the rest of the spread-source
  check (`q1pxhm`) where the diagnostic can name the real rule.
- **The helper is called for elements 1..N too**, inside the `tydqe6` visit loop. A spread operand had
  never been inferred **at all** — `infer_type` has no arm for the node — so `..some_call()` wrote no
  per-node tid memo. It does now, on every path.

**Attribution, exact, and this fix is surgical.** `diverge` **4283 → 4279**, cells **395 → 394**,
family A holds at **100** / 11 cells (these rows are `List[?]`, partially erased, so class B and family A
was never expected to move). The signature diff on the 874-file common basis is **four lines and nothing
else** — `site=emit_let_binding.decl var=b/d/w/z tid=List[?] flat=List[Int]`, all four in
`tests/test_spread_list.bl`, which now reports **zero** diverge rows. `agree` **+97 = 3 × 31 + 4**: three
new declarations × the 31 roots that compile `typecheck.bl`, plus the four flipped rows.

**The call-source shape is now a *pin* rather than a hole, and that is the measurement worth keeping.**
`let b = [..mk_strs()]` reads `tid=List[Str] flat=List[Int]` — tid right, flat wrong. `emit_list_lit`
(`codegen_expr.bl:5912`) recovers a leading spread's element with `get_list_elem_type(src_str)`, keyed on
the **emitted C expression string**: a variable name hits the flat table, a call temp misses and the
element defaults to `Int`. So `io.println("{b.get(0).unwrap()}")` prints `0=94540132406870`, and a
`Str`-declared read of the same element makes `.len()` an `error[UnresolvedMethod]` from
`codegen_methods.bl:5465` — the receiver's *name* is `Str` but its flat ctype is not `CT_STRING`. Filed as
**`ehn3s9`**. It is the `hgd2az` string-keyed hazard shape again, it is **not** a Stage-3 prerequisite —
the tid already holds the right answer, so the authority flip fixes it — and the test row keeps the shape
in the corpus so the counter names it. §2.16's "v1 does not support function call spread"
(`02_syntax.md:875`) is about `f(..args)`, not about spreading a call's result; the shape is legal.

`task regen` + `task ci` green. Test: `tests/test_08a267_spread_list_elem_type.bl`, 14 rows — six shapes
written **directly** into the corpus so the instrument can see them
(`feedback_corpus_sweep_is_not_coverage`), two pins for what already worked (`["q", ..a]` and a plain
literal), four `expect_compile_error` rows for the declared-type compare **including the call source**
(which passes today, because typecheck's half is complete independent of codegen), and a **monotonicity**
pin. That last row is also the one authoring slip worth recording: the shared
`spread_src(decl, tail, read)` helper hardcodes `let bad: Int = <read>`, so as first written the
`List[Int]`-source row asserted Int-declared-Int and could never fail. It is rewritten with an explicit
source declaring `Str`.

### q1pxhm — the spec's own sentence, enforced by neither half of it (CLOSED, divergence-neutral)

**§2.16 already said this, and nothing did it.** `sections/02_syntax.md:863`, panel vote 5-0:
*"The spread source must be a `List[T]` with the same element type as the list being constructed.
Type mismatches are compile errors."* **Both** halves were open — the element type was never compared,
and a source that is not a `List` at all reached `cc`. This was `08a267`'s byproduct and it depended on
it: a contribution cannot be compared until it can be computed.

**Fail-open modes, each re-measured by running a program *after* `08a267` and with true exit codes:**

| shape | before |
|---|---|
| `let a: List[Int] = [7]` `let b = ["q", ..a]`, read `b.get(1)` | **exit 139, SIGSEGV, no diagnostic** — the literal is `List[Str]`, the spliced value is the integer `7`, and interpolation dereferences `7` as a `char*` |
| `let a: List[Str] = ["x"]` `let b = [1, ..a]` | **silent**, ran and printed `b1=94419670083158` — the `Str` pointer as an `Int` |
| `[..a, ..c]`, two spreads of different types | **silent**, ran and printed `b0=x` |
| `let n = 7` `let b = [..n]` | **cc escape**, no Blink span: *expected `blink_list *` but argument is of type `int64_t`* |

All four now report with a span on the offending spread:

    error[TypeError]: list spread source has element type Int but the list is built from Str
      --> m1.bl:3:19
    3 |     let b = ["q", ..a]
      |                   ^

    error[TypeError]: cannot spread Int into a list literal: a spread source must be a List

**The check reads the memo; it does not re-infer.** `infer_type` has **no memo short-circuit** — it calls
`infer_type_uncached` unconditionally and writes the memo *after* — so a second call on the same node
re-walks the operand and **double-reports every diagnostic inside it**. `tc_list_elem_contribution`
(`08a267`) already inferred every operand exactly once, spread or not, so the check reads
`tc_lookup_node_tid(node_value(elem))` and resolves that. This is the one design decision in the fix, and
it is the reason the check is a separate pass over the elements rather than folded into the contribution
helper: the contribution of element 0 *is* the literal's element type, so there is nothing to compare it
against until the whole element list has been walked.

**Silence on `Unknown` and `Typevar` operands is load-bearing, not laxity.** An unbound metavar here is
what the region-boundary check reports as `E0301` (`gqg3rk`); reporting it a second time from the literal —
or pinning the metavar *from* the literal — is exactly the lossy direction `sskpk8` refuses.
`types_compatible` is already permissive the same way for the element compare, which is what keeps
`[..first_two([5, 6, 7])]` — a spread of a **generic** function's result — green.

**The scope line is the spec's, not a shortcut.** Only *spread* elements are checked. `[..a, 1]` where
the **plain** element is the odd one out satisfies §2.16 — source and literal agree there, and §2.16 says
nothing about plain elements — so `[1, "x"]` stays legal, as it is today with no spread anywhere.
General list homogeneity is a separate decision, and the compiler's own source may rely on today's
permissiveness. Both shapes are **documented, not frozen**: no row in the test pins either in place.

**Attribution, exact, and the +31 is my own code.** Cells **394 → 394**, family A **100 / 11 cells**
unchanged, `diverge` **4279 → 4310**, `agree` **+186**. The signature diff on the 874-file common basis is
**one line**:

    var=k tid=TyKind flat=Int    279 → 310    (+31)

That is one new declaration × the 31 roots that compile `typecheck.bl` — `let k = tc_tid_kind(src_t)`
landing in **family D**, the documented cell where an enum-typed local is stored as `CT_INT` because the
flat universe cannot spell an enum. `agree` **+186 = 6 × 31**: the fix's other six declarations. No new
cell, no new shape, and the binding stays because `k` is read three times and Stage 3's recursive lowering
retires the whole `tid=TyKind flat=Int` family by construction — writing worse code to hold a counter
down would be the wrong trade.

`task regen` + `task ci` green (657 test files, 1534 fmt). Test:
`tests/test_q1pxhm_spread_source_elem_check.bl`, 15 rows — six `expect_compile_error` rows (Int-into-Str,
Str-into-Int, two spreads of different types, a mismatch **one level down** in `List[List[T]]`, a non-`List`
source, and a `Str` source that is *not* iterated as characters), and **nine legal programs written
directly into the corpus** (`feedback_corpus_sweep_is_not_coverage`), because a check this shape is only as
good as the set of programs it leaves alone: a matching spread, a spread in the middle (`[1, ..a, 4]`), two
matching spreads, a nested match, an empty source, an `Option`-element carrier, a **struct** element (which
is nominal — the compare must accept the *same* struct, not merely the same `TyKind`), a call result, and
the generic-fn result above.

The carrier row is annotated `let b: List[Option[Str]] = ...` **deliberately, and not to make it pass**:
an *unannotated* `let b = [Some("cd"), Some("ef")]` — **no spread anywhere** — erases the carrier's inner
type in codegen and prints the `Str` pointer as an integer, while the annotated form is correct. The axis
is the **annotation**, not the spread, and that is `f9hgt9`'s depth-2 cell with a second carrier spelling;
noted there. When it closes, drop the annotation and assert the element again.

### ehn3s9 — the first Stage-3 authority flip, at one seam (CLOSED, −2 rows)

**This is the collapse's thesis reduced to five lines of code, and it landed the direction the plan
predicts.** `emit_list_lit` recovered a leading spread's element with

    first_elem_type   = get_list_elem_type(src_str)
    first_elem_struct = get_list_elem_struct(src_str)

a flat lookup **keyed on the emitted C expression string**. That string is a variable *name* for a
variable source — the flat table has an entry, so it worked — and a fresh **temp** for a call, which
misses, reads `-1`, and lets the element default to `Int`. The axis is **call-vs-variable in codegen**,
not the spread, and it is the `hgd2az` / `twq9kz` string-keyed hazard shape for the **third** time.

**Fail-open modes, each reproduced by running a program:**

| shape | before |
|---|---|
| `let a = [..mk_strs()]`, read `a.get(0).unwrap()` | **silent**, printed `a0=94902105437782` — the `Str` pointer as an integer |
| a struct element, `d.get(0).unwrap().v` | **silent**, printed `d0=<value>` — the field read lowered against an `Int`-erased element |
| a **builtin** method source, `[.."x,y".split(",")]` | **silent**, same pointer-as-integer |
| `let s: Str = a.get(0).unwrap()` then `s.len()` | `error[UnresolvedMethod]: unresolved method '.len' on type Str` — the codegen backstop firing on a *correctly typed* `Str`, because the receiver's name is `Str` and its flat ctype is not `CT_STRING` |
| an `Option`/nested-`List`/`Map` element | **`error[UnresolvedMethod]` on `.unwrap` / `.get`** — loud, because a `(ct, sname)` pair cannot carry a carrier's inner at all |

**An `Int` element is the one shape that accidentally worked**, because `Int` *is* the default the
erasure falls back to. It gets its own regression row so a future change cannot "fix" this family by
moving the default.

**The fix reuses `recover_list_elem_from_tid` rather than adding a fourth spelling of the same walk.**
That function (`codegen_expr.bl:552`, `jw1pmb`/`jcr0zz`/`nprhy8`) already resolves a `List`'s element
from a node's tid memo — through `tc_tid_subst_mono` for a mono body, through `deep_tp_from_tid` for
`CT_OPTION`/`CT_RESULT`/`CT_MAP`, straight off `tc_tid_set_elem_ct` for `CT_SET`, and it **declines with
no stamp** when a child cannot be spelled faithfully. So the seam becomes: stamp the element onto the
literal's own temp from the **operand node's** tid, read it back, and fall through to the string-keyed
lookup only when the tid declined:

    recover_list_elem_from_tid(node_value(elem_node), tmp)
    first_elem_type   = get_list_elem_type(tmp)
    first_elem_struct = get_list_elem_struct(tmp)
    if first_elem_type < 0 && first_elem_struct == "" { ...the old flat read... }

Two things about that shape are deliberate. It stamps **`tmp`, not `src_str`** — the literal and the
operand have the same element type, and stamping the literal is what carries the `set_list_elem_option_tp`
/ `_result_tp` / `set_list_nested_elem_*` deep-carrier writes to the consumer; stamping the *source* temp
would leave them on a value nothing reads. And the flat read stays as the **fallback**, not the
authority — this is Stage 3's flip at **one** seam, and the honest decline arms
(`CT_ITERATOR`/`CT_HANDLE`/`CT_CHANNEL`/`CT_BYTES` have no parity target) must keep falling through to
whatever works today rather than becoming a regression.

**Attribution, exact.** On the 874-file `common.lst` basis: cells **394 → 394**, family A **100 / 11
cells**, `diverge` **4310 → 4310**, `agree` unchanged — a **zero** signature diff. That is the right
answer and not a null result: the three test files added since the basis was fixed are not in it, and
**no `src/` or `lib/std/` file contains a leading-spread list literal at all** (every `[..` hit in
`rg src/*.bl lib/std/*.bl` is inside a comment), so the compiler's own emitted C cannot change. Over the
**full** corpus the diff is five rows and nothing else:

    − diverge  emit_let_binding.decl  var=b  tid=List[Str]  flat=List[Int]   tests/test_08a267_spread_list_elem_type.bl
    − diverge  emit_let_binding.decl  var=b  tid=List[Str]  flat=List[Int]   tests/test_q1pxhm_spread_source_elem_check.bl
    + diverge  emit_let_binding.decl  var=d  tid=List[Box]  flat=List[Void]  tests/test_ehn3s9_spread_call_elem_codegen.bl
    + missing  copy_list_compound_elem.src  var=_l77   tests/test_ehn3s9_spread_call_elem_codegen.bl
    + missing  copy_list_compound_elem.src  var=_l103  tests/test_ehn3s9_spread_call_elem_codegen.bl

The two removals are the ticket's shape flipping to `agree` in **both** files that carry it — the second
one is `q1pxhm`'s generic-fn-result row, which was the same defect and was never separately filed.

**The `+1 diverge` row is the House convention, not a new defect, and it is worth naming precisely.** A
struct element is stored as the pair `(CT_VOID, "Box")` — the List house convention that
`recover_list_elem_from_tid`'s own header documents and that the declared-`List[T]` path at
`codegen_stmt.bl:3312` uses identically. The instrument's flat side has no way to render that pair, so it
prints `flat=List[Void]` against `tid=List[Box]`. The element itself is **right**: the row's own test
asserts `d.get(0).unwrap().v == 5` and passes. It is a class-B *spelling* divergence that Stage 3 retires
by construction, because `c_type_from_tid` will spell `List[Box]` from the tid and the `(CT_VOID, sname)`
pair stops existing.

**The `+2 missing` rows are free evidence for a Stage-3 item.** The `Option`-carrier and `Map` rows now
reach `copy_list_compound_elem` with a **temp** source that carries no tid — `site=copy_list_compound_elem.src
var=_l77 tid=- flat=-`. `twq9kz` closed that site's *arm coverage* question; this is its **source** question,
which is exactly Stage 3's item 3 (*replace `copy_list_compound_elem` with a node-tid-sourced copy, not
`get_var_ty(src)` — that copies `-1`*). Those shapes pass today on the flat path, so this is a pinned
exercise of the tap rather than a bug: the site now has three exercised rows instead of one, and the
replacement has something to be verified against.

`task regen` + `task ci` green (**658** test files, 1536 fmt). Test:
`tests/test_ehn3s9_spread_call_elem_codegen.bl`, 14 rows, **RED as a whole file before the fix** — it did
not compile at all, 7 `UnresolvedMethod` backstop errors — and 14/14 green after. Five rows for the
silent-wrong-value modes (`Str` element, method **dispatch** on the recovered element rather than only
printing it, a struct element's field, a **builtin** method source, a **trait** method source), three for
the compound elements one level deeper (`Option` carrier, nested `List`, `Map`), and six regression pins:
the `Int` default, a variable source, a **field-access** source (which already worked — `h.xs` is not a
variable name either, but the field's type is known per-def and stamped onto the temp; a call has no such
per-def stamp, which is the whole difference), a non-leading call spread, two call spreads in a row, and
`for`-in over a call-spread literal.

Two authoring notes, both language facts rather than defects: Blink has **no inherent `impl Type { }`** —
only `impl Trait for Type` — so the method-source row declares a one-method trait, and `Map` insertion is
`.insert(k, v)`, not `.set`.

`tests/test_08a267_spread_list_elem_type.bl`'s call-source row is strengthened from a length-only assert
to the element assert the ticket reserved for this one.

### Remaining family-A causes, ranked (11 cells / ~~116~~ ~~107~~ ~~102~~ ~~101~~ 100 rows)

**The tail is now fully enumerated and it is four causes, not a list.** Re-resolved row by row against
the source line each row points at (`var=` first, then the line — the discipline three wrong
attributions in this map were bought with), the 100 remaining family-A rows are exactly:

| cause | rows | ticket | state |
|---|---:|---|---|
| `Iterator` adapters — `zip` / `chain` / `enumerate` / `flat_map` / `collect` / `count` / `fold`, and the `.get(i).unwrap()` reads downstream of them | **39** | `qzdz2e` | deferred, panel (user-visible) |
| channels — `Channel(n)` and `ch.recv()` | **38** | `w3v2e6` | blocked on `8vcj2c` (is the capacity argument's element type under-determined?) |
| `fs.*` — `fs.read` (3) and `fs.list_dir` (6), plus 9 downstream rows (`entries.get(i).unwrap()`, `entry.substring(..)`) | **18** | `jr4xf7` | `type:spec` — codegen's bare `const char*` vs the spec's `Result` |
| `p.deref()` / `p.addr()` | **5** | `mwsy85` | `type:spec` |
| ~~a block-`let` whose initializer is a block — `let s = { .. }`~~ | ~~1~~ **0** | `wnbsen` | **CLOSED** — the last unblocked one; `tc_scoped_value_memo` had no `IfExpr` arm |

Two consequences worth stating plainly. **All four that remain are held on a decision, not on work** —
three `type:spec`/panel and one blocked — so the family-A counter cannot reach 0 by fixing code alone,
and Stage 3's exit gate depends on those decisions landing. `wnbsen` was the fifth and the only
unblocked one, and it is closed. And **the `fs.*` figure in the older table
below (4) was wrong twice over**: it counted sites, not rows, and it omitted the 9 rows *downstream* of
the untyped `fs.list_dir` result, which are the same cause one hop out. The `Response`/`Request` row
below is **stale**: the corpus has **zero** family-A rows naming either type today.

Re-ranked from the post-`qjfwc6` sweep, by **rows on the 874-file common basis**, grouped by the
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

**`is_intrinsic_method` is the same defect in the namespace half, and `qjfwc6` closed it the way the
decoupling asks to be closed: with a table, not with arms.** Typecheck now registers one real
`FnSigEntry` per namespace intrinsic under `{namespace}.{method}` — return type *and* parameter types
— so the second list is no longer a suppression list with nothing behind it. Two of the three
questions the suppression list was hiding survive as their own tickets (`jr4xf7`, `n84s1p`), and both
are about the *list*, not about a missing return type. `is_builtin_method`'s 73 unanswered names are
the remaining half of the same defect and want the same treatment.

**The entries left are now one shape: a namespace or handle whose operations codegen dispatches and
typecheck has no signature table for — or, more often than not, a RECEIVER with no type at all.**
With the `Str`, `Bytes`, `Ptr`, `self`, effect-op **and namespace-intrinsic** causes closed, the
intrinsic-method list is spent as a leading mechanism: `qjfwc6` gave typecheck the table, and what it
left behind is not a missing arm but an open spec question (`jr4xf7`) and a list that disagrees with
its own arms (`n84s1p`). **The untyped-receiver family was the whole head of the list** — and
`w089a0` took the binder half of it, `nrrs28` took `Template[T]` and `ps5br9` took the ffi scope, so
**the family is now closed at six sightings and is no longer a mechanism in this ranking at all**. The
two causes that are neither (iterator adapters, `Channel(n)`) are both already deferred to a
user-visible decision, which leaves this tail with **no** entry whose fix is a receiver.

**Two shapes, and they take different fixes.** The untyped-receiver family has now split cleanly in
two: `jzvxav` and `w089a0` were **declaration sites that dropped a type they already had**, and both
were repaired by swapping in the typed spelling that already existed (`nr_define_typed`) — no new
inference, no new arm, ~10 lines each. `w13xgb`, `nrrs28` and `ps5br9` are **types the pool cannot
name**, and those need a `TyKind` variant plus a lowering plus a method block. Both halves are now
done — all six sightings closed, and each half closed by the same recipe every time, which is the
useful part: **the split predicted the size of the fix before the fix was written.**

**The old 72-row `db.*` bucket split four ways, and every one of the four is now closed or isolated —
this is the lesson the map keeps re-teaching: a shared bucket is not a shared cause.** `jzvxav` took
the 12 `at=std_db_row:35` rows (`row.get`, never a `db.*` signature problem at all — it is `self`
inside `impl RowOps for Row`), `h3q81d` took the ~42 genuine effect-op rows, `w089a0` took the 9
with-resource binder rows, and `nrrs28` took the last 9, the `at=std_db_sqlite:140` rows
(`tpl.type_tag` — `Template[T]`, not `db`). All four are now **closed**: `tests/test_db_stmt.bl`
carried exactly one family-A row after `w089a0`, that row was the `nrrs28` one, and it is gone.

| cause | rows | ticket | note |
|---|---:|---|---|
| ~~`net.*` / `io.*` — `net.connect` / `listen` / `accept` / `read_bytes` / `write_bytes`, `io.read_line`~~ | ~~49~~ | **`qjfwc6`** | **CLOSED** — −45 rows, section above. `std_net_tcp` 40 → 0. The declared-type half was a **silent miscompile**, not a `cc` escape, and arity was a **compiler panic**. Two attributions in the row this replaces were wrong: `at=lsp` was 6 rows but only 2 were `io.read_line` (the other 4 are `io.read_bytes` → `n84s1p`), and `at=std_http_server`'s 3 are `Channel(max)` at `:368`, not a `net.*` producer at all. What is left of the intrinsic list is `jr4xf7` (4 rows, spec) and `n84s1p` (~~9~~ **6** rows — see that row) |
| ~~`is_intrinsic_method` disagrees with its own arms — `io.read_bytes`, `env.var`, `io.debug`~~ | ~~9~~ ~~6~~ **0** | **`n84s1p`** | **CLOSED — −8 rows** (one *more* than the 6 this row predicted), section below. The list was short of the arms by **twelve** names, not three, and the repair is one-directional: **list ⊇ arms**, so `io.debug` **stays** listed. Two of its three named causes were mis-attributed: the `src/incremental.bl:44` rows were never `env.var` (they were `cttrag`'s — `env.var` does not appear in that file, `:44` is `let path = symbol_index.si_file_path.get(i).unwrap()`, and the row's own `var=path` said so), and `env.var` has **zero** rows anywhere in the corpus despite being the ticket's worst defect. **Read the row's `var=` before believing an attribution derived from the line number** |
| `fs.read` / `write` / `list_dir` / `remove` | ~~4~~ **18** (9 direct + 9 downstream) | `jr4xf7` (`type:spec`) | The `4` was sites, not rows, and it missed every row *downstream* of the untyped `fs.list_dir` result — see the corrected table above. Split out of `qjfwc6` and **held on purpose**: `sections/04_effects.md:73,1053` spells `fs.read(path)?` as a `Result` and `:157,215` names the lister `fs.list`, while codegen emits a bare `const char*` from `blink_read_file`. Signing it from codegen would write "an FS read cannot fail" into the type system |
| ~~`db.*` effect operations — `db.query` / `query_one` / `execute`, `stmt.step`~~ | ~~51~~ | **`h3q81d`** | **CLOSED** — −49 rows, section above. Typecheck held **no** operation signatures, only the handle name for warning suppression; codegen held the same signatures across eight flat return fields. 9 rows survive, all `with db.prepare(..) as stmt` → **`w089a0`** |
| ~~the with-resource `as` binder — `with db.prepare(..).unwrap() as stmt`~~ | ~~9~~ | **`w089a0`** | **CLOSED** — −13 rows, section above. The prediction held exactly: the tid *was* already in hand at the binding site, one line above the walk that computes it, and the fix was the `jzvxav` shape — bind the binder. Another **silent miscompile** (`let bad: Str = r.value()` ran and printed `7`). Attribution was three files, all with-resource; `test_db_stmt.bl` 10 → 1, and the survivor is `nrrs28` |
| ~~`Template[T]` introspection — `tpl.type_tag` / `count` / `get_int` / `get_float` / `get_str`~~ | ~~9~~ **0** | **`nrrs28`** | **CLOSED — −9 rows**, section above, and the prediction in this row held to the row and to the recipe: it *was* the untyped-receiver shape (`Template` was claimed by `is_primitive_type` and had no `resolve_type_parts` arm, so the receiver was `make_typevar("Template")`), and it *was* fixed the way `w13xgb` was — variant, lowering, method block. `std_db_sqlite` 9 → **0**, which puts **every** `lib/std` module at zero. What the row did not predict: making the receiver a real type is **stricter** than a typevar, so the literal-decomposition coercion had to be added in the same change or every legitimate `db.query("…")` in the corpus became an error — and the `Str`-variable rejection the spec writes out in full (E0310) moved from **codegen** to typecheck, which widened it from the effect-op path to every call shape |
| `Iterator` adapters — `.zip`, `.chain`, `.enumerate`, `.collect` | ~~34~~ **39** | `qzdz2e` | **deferred** (panel decision, user-visible). Was invisible in the previous ranking and is now #3: `tests/test_combining_iterators.bl` (16) and `tests/test_44xww4_enumerate_zip_compound.bl` (18), showing as `flat=List[Void]` and `flat=Tuple2_int_int` — the adapter loses the element type *and* the pair shape |
| `Channel(n)` / `ch.recv` | ~~24~~ **38** | `w3v2e6` | **likely genuinely under-determined** — the arg is a capacity, not an element type, so this may be `decisions/under-determined-types.md` / E0301, not a missing rule. `tests/test_channels.bl` (11), `tests/test_async_cancel.bl` (7), `src/cli.bl:2162` |
| ~~a cross-module `pub let` container element — `symbol_index.si_file_path.get(i)`~~ | ~~12~~ **0** | `cttrag` | **CLOSED, and two of this row's three axes were wrong** — not container-specific, not about `pub` or crossing a module boundary. It is any **module-qualified** top-level `let`. See the `cttrag` section |
| ~~`Response` / `Request` from the http surface~~ | ~~10~~ **0** | — | **STALE — no such rows exist.** Re-resolving the tail row by row finds **zero** family-A rows naming `Response` or `Request`; the 3 rows this line was reading at `at=std_http_server` are `let sem = Channel(max)` (`http_server.bl:368`), which belong to the channel cause. A third attribution taken from a file name instead of from the row's `var=`. Original note: `tests/test_net_integration.bl`, `test_middleware.bl`, `test_http_server.bl`, all `at=__main__`. **It did not close with `net.*`** — the earlier note guessed it would. `net.request` was the one intrinsic `qjfwc6` left out for a reason of its own (its `Result[Response, NetError]` needs two stdlib struct types a consuming module need not have imported), so these need their own probe |
| ~~calling a closure-typed **field** (`route.callback`, `logger.log_msg`)~~ | ~~~11~~ **0** | `cjtxxr` | **CLOSED** — this row was `cjtxxr`, closed above (−12 rows); the line was never struck through |
| ~~**`@derive`-synthesized methods have no signature in typecheck** — `to_json`, `from_json`, `clone`, and the str-backed-enum statics~~ | ~~**19**~~ | **`nxnnxe`** | **CLOSED** — −19 rows, section above. The prediction held to the row and all seven files went to zero. 14 of the 19 moved family A → **class B** (four *different* flat-universe limits: `Result`'s second child erased, an `Option`'s enum inner erased to `Int`, a bare enum erased to `Int`, and `tid=Shape flat=Shape` diverging on identical spelling); the other 5 now `agree`. `agree` +346, the largest of the campaign. **Two names held back on purpose** — `hash` is uncallable today (`pvhaew`) and a signature would claim otherwise, and `to_json`/`from_json` are signed `Str` because the spec's `JsonValue`/`JsonError` do not exist (`169kjt`). Original triage: **Triaged, and it grew.** The old 15-row line lumped two unrelated causes and got both counts wrong: 10 of those rows were the IIFE (**`x3x0qj`**, closed above) and the rest is bigger than it looked once the IIFE rows stopped hiding it. One mechanism, four synthesized shapes: `u.to_json()` → `flat=Str` (`test_derive_serialize.bl`, `test_derive_nested.bl`, `test_derive_deserialize.bl:13`, `test_derive_list_deser.bl:30`), `T.from_json(..)` → `flat=Result[Void, Str]` (`test_derive_deserialize.bl` ×2, `test_derive_enum_deser.bl` ×2, `test_derive_list_deser.bl`, `test_str_backed_enum.bl` ×2), `x.clone()` → `flat=Point`/`Int`/`Shape` (`test_derive_clone.bl` ×3), and the str-backed statics → `flat=Option[Int]` (`test_str_backed_enum.bl` ×4). Nothing declares these — `@derive` synthesizes them in codegen, so there is no `node_type_ann` to read and no fnsig to look up. **The `qjfwc6` shape: a table, not arms** — one `FnSigEntry` per derived method per deriving type, minted where the derive is registered. Now the largest actionable cause, and it subsumes the separate `Status.from_str` line below |
| ~~`List.join` on a `List[Str]`~~ | ~~4~~ **0** | **`jvy35h`** | **CLOSED — −6 rows**, section below, and the row's estimate was low for the usual reason: 3 sites × 2 roots. It was the last allow-list-vs-dispatch entry in the tail and it turned out to be the **worst-consequence** one so far — nothing checked the RECEIVER, so `[1, 2].join(",")` segfaulted inside `str_join` and `[["a"], ["b"]].join(",")` printed binary noise at exit 0. The spec pins both halves (`impl Joinable for List[Str]`, `fn join(self, separator: Str) -> Str`), so unlike `jr4xf7` there was no question to answer |
| ~~`bytes.to_str()` → `Result[Str, Str]`~~ | ~~3~~ **0** | **`n84s1p`** | **CLOSED as a mis-attribution, not as a cause.** All 3 rows were `src/lsp.bl:51`, and `Bytes.to_str` has had its signature since `typecheck.bl:9495` (`make_result_type(TYPE_STR, TYPE_STR)`) — the whole time this row claimed it did not. `:51` consumes `:50`'s `io.read_bytes`, so its receiver was untyped and the rows were purely **downstream**; they retired with `n84s1p` and no `Bytes` arm was touched. This is the third attribution in this ranking derived from a line number rather than from the row's `var=` field and wrong for it |
| ~~`Status.from_str` — the compiler-synthesized static on a str-backed enum, returning `Option[Enum]`~~ | ~~4~~ | **`nxnnxe`** | **Folded into the `@derive` row above** — same producer, same missing table, closed with it. It was listed separately only because the `flat=Option[Int]` spelling put it in a different part of the tail. The fold was correct: one `register_derive_method_sig` call closed all 4, and they were the four rows that moved to `tid=Option[Status]` |
| ~~an immediately-invoked closure, `fn(..) -> T { .. }()`~~ | ~~10~~ | **`x3x0qj`** | **CLOSED** — −10 rows, section above. Was hidden inside the `@derive`/`Result` line, which is how a `flat=`-organized tail hides a callee-shape cause. One missing `callee_kind` branch left the result type, the arity **and** the callee body unchecked; a **silent miscompile** and two `cc` escapes. First fix whose rows moved family A → class B rather than leaving `diverge` |
| ~~`Ptr[T]` intrinsics — `buf.offset(i)`, `p.is_null()`, `s.as_cstr()`~~ | ~~176~~ | **`w13xgb`** | **CLOSED** — −177 rows, section above. `Ptr[T]` had no `TyKind` at all. 5 rows remained, all `scope.cstr` / `scope.take` → **`ps5br9`**, now also closed |
| ~~the `ffi.scope()` receiver — `scope.cstr` / `take` / `alloc` / `alloc_n`~~ | ~~5~~ **0** | **`ps5br9`** | **CLOSED — −5 rows**, section above, and the family-A `tid=? flat=Ptr[Int]` **cell is gone**: every unannotated pointer binding in the corpus now has a tid. The receiver had no `TyKind` while codegen had carried `CT_FFI_SCOPE` and a four-method emitter since the FFI surface landed. **Ten** fail-open modes, of which the instructive one ran *correctly* (a `Ptr[U8]` into a `Str` parameter — same C type). This row's premise was wrong in the same way `hgd2az`'s was: `alloc`/`alloc_n` are **not** under-determined, the spec writes the pointee at the call site and `parser.bl:2887` discards it (**`9qmrma`**). What is left is a *pointee* cell, not a receiver one: **`0dtbe6`**, 238 class-B rows over 20 sites, the largest such population in the corpus |
| ~~`Str` intrinsic aliases — `s.substr(a,b)`, `s.charAt(i)`, `n.to_string()`~~ | ~~147~~ | **`rbd0a4`** | **CLOSED** — −157 rows. `charAt` was not a missing return type; the method does not exist |
| ~~`row.get(col)` inside `impl RowOps for Row`~~ | ~~12~~ | **`jzvxav`** | **CLOSED** — was filed under the `db.*` bucket and was not a `db.*` cause: `self` had no type in **any** impl method in **any** program. −17 rows visible, and an argument-check `cc` escape that produces no row at all |

Note what the `db.*` and iterator entries did **not** do: they did not get bigger. They rose to the
top because the causes above them were removed, and both were already in the map.

**The `@derive`/`Result` line is where the ranking method itself failed, and it is worth recording
because it will fail the same way again.** That line was entered as one un-triaged 15-row group
because its rows shared a `flat=` spelling. Probing it split it into **three** unrelated causes:
the IIFE (`x3x0qj`, 10 rows, now closed), the `@derive`-synthesized methods (19 rows once the IIFE
rows stopped masking them), and `bytes.to_str()` at `src/lsp.bl:51` (3 rows, one per root — a
`Bytes` intrinsic returning `Result[Str, Str]`, the `2r96m9`/`rbd0a4` shape again). **Grouping by
`flat=` spelling groups by symptom.** `flat=Result[Int, Void]` is what the flat universe prints for
*any* `Result` whose error type it cannot spell, so it collects every producer at once — the same
trap as ranking by cells instead of rows, one level down. Only the *producing expression* is a
cause, and reading it means opening the source line.

**Cross-check by source module** (` at=` on the post-`w089a0` sweep — note the leading space; without
it the pattern also matches inside `flat=`), because the flat spelling and the producing module answer
different questions and disagreeing on which is "the" count is how the Ptr entry once acquired two
figures:

| module | family-A rows | | after `9md3r1` | after `cjtxxr` | after `rb5wvb` | after `jvy35h` | after `n84s1p` | after `cttrag` | after `nxnnxe` | after `x3x0qj` | after `w089a0` | after `qjfwc6` | after `h3q81d` | after `jzvxav` | after `w13xgb` | after `rbd0a4` |
|---|---:|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| `__main__` (the root being compiled) | **88** | | **96** | **108** | **120** | 122 | 125 | 129 | 129 | 148 | 158 | 171 | 174 | 223 | 225 | 237 |
| `std_libc` | **0** | | **0** | **0** | **0** | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 165 |
| `std_net_tcp` | **0** | | **0** | **0** | **0** | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 40 | 40 | 40 | 40 |
| `std_db_row` | **0** | | **0** | **0** | **0** | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 12 | 12 |
| `cli` | **8** | | **8** | **8** | **8** | 8 | 11 | 11 | 11 | 11 | 11 | 11 | 11 | 11 | 11 | 11 |
| `std_db_sqlite` | **0** | | 9 | 9 | 9 | 9 | 9 | 9 | 9 | 9 | 9 | 9 | 9 | 9 | 9 | 9 |
| `incremental` / `file_watcher` | **0 each** | | **0 each** | **0 each** | **0 each** | 0 each | 0 each | 0 each | 6 each | 6 each | 6 each | 6 each | 6 each | 6 each | 6 each | 6 each |
| `lsp` | **0** | | **0** | **0** | **0** | 0 | 0 | 4 | 4 | 4 | 4 | 4 | 6 | 6 | 6 | 6 |
| `std_testing` | **0** | | **0** | **0** | **0** | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 3 | 3 |
| `std_http_server` / `build_stdlib` | 3 each | | 3 each | 3 each | 3 each | 3 each | 3 each | 3 each | 3 each | 3 each | 3 each | 3 each | 3 each | 3 each | 3 each | 3 each |
| `pkg_resolver` | **0** | | **0** | **0** | **0** | 3 | 3 | 3 | 3 | 3 | 3 | 3 | 3 | 3 | 3 | 3 |

**Ten of the last eleven fixes landed their whole delta in `__main__` and nowhere else** — `ta51an`'s
−1 (88 → 87), `ps5br9`'s −5 (93 → 88) and, before it, `nrrs28`'s −9, the one exception, which took the last `lib/std` rows in
the corpus (`std_db_sqlite` 9 → 0 and with it **every** stdlib module at zero) — plus
`w089a0`'s −13 (171 → 158), `x3x0qj`'s −10 (158 → 148), `nxnnxe`'s −19 (148 → 129), `jvy35h`'s −3
(125 → 122), `rb5wvb`'s −2 (122 → 120, its other 3 rows being `pkg_resolver`'s), `cjtxxr`'s −12
(120 → 108), `9md3r1`'s −12 (108 → 96) and `hgd2az`'s −3 (96 → 93). That is the expected shape for a fix to a **declaration site** or to a **syntactic
form**: a `with ... as` clause, an `fn(..) { .. }()` call, an `@derive`d type and a
`route.callback(req)` field invocation are all written in the root under compilation, so unlike the
stdlib causes there is no shared module for the rows to concentrate in. It is also why those
attributions are per-root-file (three, three, seven and three files) rather than per-module, and why
the `__main__` figure is the one to watch from here — **every** stdlib module is now at zero, and the
100 remaining family-A rows sit in `__main__` (86), `cli` (8), `std_http_server` (3) and
`build_stdlib` (3). **`cjtxxr` is the sharpest case of that shape yet and worth reading carefully,
because the CAUSE is in `lib/std/http_server.bl` — three closure fields on `Route`, `Hook` and
`ErrorHandler` — while every row sits in `__main__`.** The rows land where the field is *invoked*, not
where it is *declared*, so a stdlib cause can present as a pure-`__main__` signature. Do not read a
`__main__`-only delta as "the defect was in the corpus".

**`std_libc` went from a third of everything left to zero**, and it was one cause; `std_db_row` and
`std_testing` went to zero on `jzvxav`, and it was one cause covering both; **`std_net_tcp` went from
a flat 40 across five sweeps to zero on `qjfwc6`**, and it was one cause — five `let` bindings in
`lib/std/net_tcp.bl` that every net-using root re-derives. The `__main__` bucket is not a residual
cause of its own: `__main__` is whatever root is under compilation, so it is the *corpus*
redistributing the same handful of mechanisms across roots — which is why the ranking is organized by
producer and not by this table. `h3q81d` is the only cause so far to move `__main__` substantially
(223 → 174), precisely because effect ops are called from roots rather than from a stdlib module.

**Every `lib/std` module in this table is now at zero except `std_db_sqlite` (9, `nrrs28`)** — and
with `nrrs28` closed, *`std_db_sqlite` is at zero too, so the qualifier is spent: every `lib/std`
module reads zero, and the only stdlib rows left anywhere are `std_http_server`'s 3.* What
remains is `__main__` plus the compiler's own source (`cli`, 11 at the time this was written and 8
after `jvy35h`) — so from here the instrument is measuring the corpus and the compiler, not the
standard library. (`lib/pkg`'s `pkg_resolver` stayed at 3 for ten sweeps after this and went to zero on
`rb5wvb`.)

**`n84s1p` cleared `lsp` outright** (4 → 0), the third compiler module retired in two fixes, and it
splits the `__main__` bucket in a way worth noting: of its 8 rows, 6 are the *same two source lines*
(`src/lsp.bl:50,51`) counted once per root that pulls `lsp` in — 4 attributed to `lsp` and 2 to
`__main__` when `lsp` is itself the root. That is the `std_net_tcp` shape again at one quarter the
size: **a family-A row count is a count of (site × root), not of sites**, so two lines in a
widely-imported module outrank six lines that only one root compiles. The remaining 2 rows are
single-site: `tests/manual_stdio_stdin.bl:10` and `tests/test_env_effect.bl:12`.

**`cttrag` cleared `incremental` and `file_watcher` outright** (6 each → 0), the first fix to retire two
whole modules since `jzvxav` took `std_db_row` and `std_testing` together. It also **shrank this table
by two rows**, which is the useful reading of a per-module view: a module reaching zero means every
producer written in it is accounted for, and only three of the compiler's own files still appear
(`cli`, `lsp`, and `__main__` when the compiler compiles itself).

**`jvy35h` took `cli` from 11 to 8, and it is the first fix whose delta splits evenly between a named
module and `__main__` for a mechanical reason worth recording.** Its 6 rows are *three* source lines —
`src/cli.bl:935`, `:3561`, `:3563`, all `List[Str].join(sep)` — counted **twice each**, once with
`at=cli:` when a root imports `cli` and once with `at=__main__:` when `cli.bl` is itself the root under
compilation. Every earlier per-module attribution had the two buckets holding different lines; this one
has the same three lines in both. So a module's figure and the `__main__` figure are not disjoint
populations, and a fix to the compiler's own source will always appear in both columns. `cli` is now the
only compiler file left in this table, at 8 rows across 8 distinct sites — the flattest tail the
instrument has measured.

**`rb5wvb` cleared `pkg_resolver` (3 → 0) and took `__main__` from 122 to 120, and it is the first fix
to retire a `lib/pkg` module** — so this table's non-`__main__` tail is now `std_db_sqlite` (9,
`nrrs28`), `cli` (8), and `std_http_server` / `build_stdlib` (3 each) and nothing else. *(`nrrs28`
later cleared `std_db_sqlite`, leaving `cli` 8 and `std_http_server` / `build_stdlib` 3 each.)* Its 5 rows are
three source lines: `lib/pkg/resolver.bl:312` (`let generated = time.read().to_rfc3339()`, ×3 roots) and
`tests/test_time.bl:46,:64`. Note that `pkg_resolver` **had to be split out of the shared `3 each` row**
to record this, which is the cost of grouping equal-valued modules on one line — they were only equal by
coincidence, and one fix separated them. The `pkg_resolver:312` entry had been sitting in the ranking
below as *"not yet diagnosed"*: it was `to_rfc3339`, and the audit that found the cause never looked at
the row. Reading the line would have named it in one command, which is the same lesson the `var=`-field
paragraph draws two paragraphs down.

**`cjtxxr` then took `__main__` 120 → 108 without moving any other row in this table, and its cause is in
`lib/std/http_server.bl`.** That combination is the one to keep in mind when reading this column: the rows
land where a closure field is *invoked* — three test roots — not where it is *declared*, so a stdlib cause
can present as a pure-`__main__` delta. The non-`__main__` tail is unchanged: `std_db_sqlite` (9,
`nrrs28` — **cleared since**), `cli` (8), `std_http_server` / `build_stdlib` (3 each). And `std_http_server`'s own 3 rows are
**not** this cause — they are `var=sem tid=? flat=Channel[Int]` at `:368`, which belongs to the held
`Channel` group.

**With `nxnnxe` closed, the top of the ranking is no longer actionable by row count**, and that is
worth stating plainly because it changes how the remaining prerequisites should be picked. The two
largest causes left are both *held* rather than open: **iterator adapters** (34) is deferred to
`qzdz2e` by panel decision because it is user-visible, and **`Channel(n)` / `ch.recv`** (24) is
probably not a missing rule at all — the argument is a capacity, not an element type, so it likely
belongs to `decisions/under-determined-types.md` / E0301. Below them the tail is genuinely flat:
~~`pub let` container element (12)~~ (**closed — `cttrag`**), **`jr4xf7` (14 — re-measured from the 4
this list used to claim, and now the largest single remaining cause, blocked on a spec answer)**,
~~closure-typed fields (~11)~~ + ~~`Response`/`Request` (10)~~ (**one cause, not two — closed as
`cjtxxr`, −12**), ~~`nrrs28` (9)~~ (**closed — −9, and it took the last stdlib module to zero**),
~~`n84s1p` (9 → 6)~~ (**closed — −8**), `List.join` (6),
~~`bytes.to_str()` (3)~~ (**closed as a mis-attribution — it was `n84s1p` downstream**),
~~`pkg_resolver:312` (3, `var=generated`, not yet diagnosed)~~ (**closed — it was
`Instant.to_rfc3339`, `rb5wvb`, −5 with the two `tests/test_time.bl` rows**).

**Four of this ranking's entries have now been corrected by reading the row's own `var=` field, and
two of the four were corrected *downward to zero*** — `bytes.to_str()` and the `env.var` half of
`n84s1p` were not causes at all, while `jr4xf7` was undercounted by more than 3×. The ranking is
generated from line numbers; the `var=` field is generated from the binding. When they disagree the
`var=` field wins, and one `sed -n '<line>p'` settles it.

**`cjtxxr` is a new kind of ranking error and the one most likely to recur: two adjacent entries were
the same cause.** "closure-typed fields (~11)" was grouped by a guess at the *mechanism*;
"`Response`/`Request` (10)" was grouped by the `flat=` *spelling*; both name `route.callback(req)` /
`hook.process(req)` / `srv.error_handler.on_error(req, msg)`, and the `~11`/`10` were the same rows
counted twice under two labels. It also made the entry look like two ~10-row items rather than one
12-row item — below `jr4xf7` (14, spec-blocked) either way, so the double-count cost nothing here, but
it would have if the group had been larger. Mixing grouping keys in one ranking is what allows it:
group every entry by the **producing expression**, and an entry named after a type spelling
(`flat=QueryError`, `flat=PgError`, `flat=Event`) should be treated as un-triaged until its source line
has been read.

**That warning was cashed in immediately, and the multiplicity was 6×.** Those three spellings plus
`flat=DbError`, `flat=Msg` and `flat=Shape` — six separate entries in the flat tail, 12 rows between
them, spread over five test files — are **one** cause: qualified struct-style variant construction,
`Enum.Variant { field: v }`. Six `sed -n '<line>p'` calls, one per entry, settled it before any
probing began; every one of the 12 sites is a `let x = Enum.Variant { .. }`. `9md3r1` closed all
six at once. **A type spelling is not a cause, and neither is a count of type spellings** — the
ranking's cell count over-states the amount of work left whenever one producing expression can be
reached with several different result types, which is exactly what an enum constructor is. Treat the
remaining flat-tail singletons (`flat=Int` ~35, `flat=Str` ~14, `flat=List[Int]` 6) the same way:
read the producing line first, and expect fewer causes than entries.

**`cttrag` was picked from that flat tail on a different criterion, and it is the one to keep using:
the rows sat in the compiler's own source.** A cause inside `src/` can be reproduced, fixed and
verified without waiting on a spec answer or a panel, and `task regen` exercises it on every build
afterwards. It paid twice over — the fix was −12 rows, and *scoping* it corrected two wrong axes on its
own ranking row and three mis-attributed rows on `n84s1p`'s. **Ranking rows are hypotheses, not
findings.** Both errors came from generalizing a cause out of the *line numbers* its highest-count
sites happened to have; both were caught by reading the sweep row's own `var=` field and the source
line it names. Do that first for every remaining entry — the cost is one `sed -n` and it has now
changed the answer twice.

So the next two prerequisites were chosen on **evidence quality and blast radius**, not size — and
both were `nxnnxe`'s own byproducts, which is the pattern every closed cause in this document has
produced. **Both are now closed** (`bf0jnj`, `pvhaew`, sections above), separately tested, separately
regenerated, and separately swept. Neither is measured in rows — both were `cc`/E0505 escapes, which
produce no divergence row at all, the `ya8qyf` situation — and the sweeps confirm it: each reproduces
the `nxnnxe` column digit for digit.

**What closing them establishes, beyond the two bugs.** They are the fourth and fifth sightings of
the same defect shape, and they now bracket it from both sides. `nxnnxe`, `qjfwc6` and `n84s1p` had an
**allow-list affirming a name with no arm behind it**; `pvhaew` has the **allow-list right and the
dispatch table short**. The repair was identical in both directions — *a table, not arms* — which is
the same conclusion Q2 of `decisions/compiler-type-representation.md` reached about types, arrived at
from the method side. And `bf0jnj` is the `expr_result_*`-vs-`ScopeVar` split, i.e. *one type, two
places to write it down, and only one written*: Stage 4 deletes the side-channel outright, so that
whole class ends structurally rather than one arm at a time.

**A signature fix keeps uncovering the codegen bug the missing type was hiding** — three times now.
`bf0jnj` was unreachable until `nxnnxe` taught typecheck `from_str`'s signature, because typecheck
rejected the program first with `on type ?`. That is worth carrying into Stage 3: when a fix stops a
program being rejected early, expect the next layer's bug to surface immediately, and budget for it
rather than treating it as a regression.

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

## Stage 3a — `c_type_from_tid`, and the second counter

Date: 2026-08-12. `task regen` green ×3; the flat fields still govern every emit decision, so
no emitted C changes in this sub-step.

**Where the function had to live, and a correction to the plan.** The plan sub-divides Stage 3
"by file, one regen each: `codegen_types` → `codegen_stmt` → …". That first step is impossible
as literally written: `codegen_types.bl` does **not** import typecheck (typecheck imports
`codegen_types`), so a recursive speller over `TyKind` cannot be written there at all. It lives
in `src/typecheck.bl`, next to the Stage 1 accessors it is built from, and codegen imports it —
which is the correct direction anyway: the tid is typecheck's, and the point of the collapse is
that codegen *reads* types instead of deriving them.

### Why a second instrument, when Stage 2 already has one

`tydiv` compares two **representations** and asks whether they have the same shape.
`ctypediv` compares the two **C strings** an emit site could print. Those are different
questions and neither implies the other:

- A cell can agree structurally and disagree on spelling. `Result[TcpSocket, NetError]` has one
  shape, and the two spellers produced `blink_Result_std_net_tcp_TcpSocket_std_net_error_NetError`
  and `blink_Result_..._std_net_error_std_net_error_NetError`. tydiv calls that **agree**.
- A cell can diverge structurally and agree on spelling — every `Map[K, V]` whose flat side
  erased `V`, because a Map is `blink_map*` whatever it holds.

Only the string comparison answers the question a flip actually turns on: *if authority moved to
the tid at this site, would the emitted C change?* Stage 3's exit criterion is about emitted C,
so it needs the string counter.

**Implementation note (why the two counters share a table but not a gate).** `ctypediv` rows
land in the same `ty_div_rows` table under a `ctype.` site prefix, but the *bump* is gated on
`dbg_channel_on("ctypediv")` — unlike tydiv's unconditional bump. Without that asymmetry a
tydiv-only sweep would silently accumulate ctype rows into its own published summary lines and
every earlier tydiv total in this document would stop being reproducible. `ty_divergence_dump`
now fires when *either* channel is on and routes each row to the channel matching its site
prefix, because `dbg_trace` gates on its own channel argument.

### Totals

874-file corpus (`tests/` + `examples/` + `src/`), archive-linked, probing
`emit_let_binding`'s nine declaration branches after `tc_tid_subst_mono`:

```
site                     agree     diverge  decline
ctype.flat               350000    981      82
ctype.struct             19262     8        141
ctype.option             1652      0        0
ctype.result             291       0        4
ctype.enum               123       0        0
ctype.ptr_ffi            169       0        0
ctype.ptr_ann            78        0        0
ctype.enum_mono          0         0        16
ctype.handler            0         0        7
ctype.void_placeholder   0         6        0
TOTAL                    371575    995      250
```

**395,253 of 396,603 cells — 99.66% — agreed on the first draft**, and the entire remainder is
1245 rows in ten buckets. That number is the point of the sub-step: the flat representation is
not mostly wrong, it is *narrowly* wrong, and the narrow part is now a list.

### The 1245, classified five ways

The classification matters more than the count, because the five classes have five different
dispositions and lumping them would have produced a wrong plan for four of them.

| | class | rows | disposition |
|---|---|---:|---|
| i | **the tid is right and the flat is wrong** | 973 | fix by flipping — br `0rmamy` |
| ii | **my speller was wrong** | 40 | already fixed, below |
| iii | by-design declines (mono spelling is a separate seam) | 164 | keep declining |
| iv | family-A residue (`tid=?`) | 87 | blocked on the four held causes |
| v | known and documented | 21 | no action |

**(i) 973 rows where the tid is right.** 868 `TyKind` + 96 `TokenKind` + 1 `Color`: an
unannotated local holding a unit-only enum is declared `int64_t` when the enum has a real
typedef (`blink_typecheck_TyKind`). Plus 7 `Ptr` rows where the tid knows the pointee
(`uint8_t*`, `int64_t*`) and the flat path answers `void*`, and 1 `U64` declared `int64_t`.
These are *not* miscompiles today — C's integer conversions absorb an enum-as-int64 and a
`void*` round-trip — which is exactly why they survived: the flat path is wrong in the way
that stays quiet until something starts depending on the type. They are the natural first
authority flip, filed as br `0rmamy` with the enum bucket as its red/green witness.

**(ii) 40 rows where my speller was wrong — and this is the sub-step's real payoff.**

*37 doubly-module-prefixed carriers.* I first spelled a carrier `c_type_c_name(tag)`. That
routes the tag through `canonical_struct_tag`, which splits `Result_<ok>_<err>` by **scanning
backwards for an underscore** and re-applies `c_type_tag_for_struct` to each half. The grammar
is ambiguous the moment either half carries a module prefix — prefixes contain underscores — so
an already-prefixed half gets prefixed again:
`Result_std_net_tcp_TcpSocket_std_net_error_NetError` came back as
`..._std_net_error_std_net_error_NetError`. 37 rows across `std.net` / `std.db` / `std.errno`,
**every one of them a C type that was never typedef'd**. `tc_tid_inner_tag` already emits the
canonical, alias-hopped, module-qualified tag, so the fix is to prefix and nothing else:
`"blink_{tag}"`. Re-measured: `ctype.result` diverge **37 → 0**, agree 254 → 291.
The underlying `canonical_struct_tag` defect is real and still there — br `rb5hsv`, latent,
**worked around here, not fixed**.

*3 transparent-newtype rows.* `type Errno(Int)` lowers to a bare `int64_t` by panel decision
(br `ja9jev`, 6-0, "transparent / zero-cost"). `tc_alias_underlying` has no entry for it — it is
a real single-variant enum declaration, not an alias — so the alias hop cannot see it, and the
speller answered `blink_Errno`: the boxed tagged struct that decision exists to avoid. Fixed by
consulting codegen's own `is_transparent_newtype` gate rather than re-deriving the rule, so the
two cannot drift. Re-measured: those rows gone, `ctype.flat` agree +3.

**Had I flipped authority at this seam without measuring first, I would have emitted ~40
references to never-typedef'd C types across three stdlib modules.** Both mistakes were mine,
both were invisible to reasoning about the code, and both were caught by a counter that costs
nothing to run because it compares strings without printing them. That is the whole argument
for the measure-then-flip ordering, and it is now an observation rather than a claim.

**(iii) 164 by-design declines.** 141 generic struct instances (`Box[Int]` → the mono registry
owns `blink_Box_0Int`; the sweep prints the exact target spelling, which is what makes the next
seam cheap), 16 monomorphised generic enums, 7 effect handlers (`blink_io_vtable*`). A decline
is an *answer*: the caller keeps what it does today rather than trading one wrong C type for
another. The same contract, for the same reason, as `tc_channel_elem_ct`'s `-1`.

**(iv) 87 family-A rows** where the tid itself is `?` — 83 `flat` + 4 `result`. Not spelling
defects; they are the four remaining family-A causes, all held on decisions
(`qzdz2e` panel, `w3v2e6` blocked on `8vcj2c`, `jr4xf7` and `mwsy85` `type:spec`).

**(v) 21 known rows, no action.** 6 Void placeholders (a *storage*-position rule: a `Void` local
still needs a slot, so `int64_t` is right and `void` would not compile — br `hsgsbp`); 3 more
`Void`-vs-`int64_t` at `.pop()`/`.clear()`, where typecheck and codegen genuinely disagree about
the method's return type; 5 `ty=Int tidc=int64_t emitted=int` at `src/codegen.bl:452`, a
`Bool + Bool` sum typed `Int` by typecheck and emitted in an `int` slot; and 8 generic-fn tuple
returns, below.

### The eight tuple rows are a convention, not a collision

`(Map[Str, Int], Int)` spelled `blink_Tuple2_Map_str_int_int` from the tid and
`blink_Tuple2_map_int` from the flat path. I read that as a stem collision with miscompile
potential and it is not — corrected by *running* three MVCEs rather than by re-reading the code:

- Every corpus site is `wrap[T](x: T) -> (T, Int)`. A generic fn's tuple return monomorphises
  to the erased stem `Tuple2_map_int` for **every** Map key/value combination, and the tests
  pass, because a Map is one runtime type: all those instantiations want the same C struct.
- A **directly constructed** tuple emits the structural `blink_Tuple2_Map_str_int_int` instead.
- The read-back failure I initially took for the collision's symptom
  (`UnresolvedMethod … on type ?`) reproduces with a **single** tuple and no second
  instantiation anywhere, so it is a pre-existing loud gap, not a collision.

Two live conventions, both sound, and a Stage-3 flip must not quietly unify them: flipping the
generic-fn path onto the structural spelling would fragment one C struct into N identical ones.
Documented as a flip constraint; no ticket.

### A hole the sweep could not see, found by writing the test

A typevar inner is the one unspellable tag that is **not** an ICE sentinel: `tc_tid_tag_at`
answers a bare `"<tv>"` for a `Typevar` — an unsubstituted `T` inside a generic body is normal,
not an internal error — and the Option/Result/Tuple arms interpolate it. So
`c_type_from_tid(Option[T])` returned **`blink_Option_<tv>`**, which is not a C identifier at
all, and `diag_is_ice_seg` cannot catch it by construction.

The corpus never produced that row, because `emit_let_binding` substitutes mono tparams before
probing. Zero occurrences over 874 files, and the shape was still wrong — the textbook case of
`feedback_corpus_sweep_is_not_coverage`: **a zero-hit tap is an unexercised tap, not a safety
fact.** It was found by enumerating what the test file should assert, which is the argument for
writing the pin test even at a seam where authority has not moved yet. Guard added, red
demonstrated by removing it (`got 'blink_Option_<tv>', want ''`), green with it.

### What pins this

`tests/test_ctype_from_tid_spelling.bl` — 18 rows over the reachable spellings (scalars, sized
ints, containers, runtime-backed kinds, carriers, depth ≥ 2 nesting, Ptr recursion, Void, bare
struct/enum delegation) and the decline contract (metavar, generic instance, typevar, carrier
over a typevar, carrier over a metavar), plus two rows that exist because they are
counter-intuitive:

- **decline is not contagious.** `Map[Str, T]` still spells `blink_map*`. A container's C type
  does not depend on its element, so an unspellable element must not propagate a decline
  outward — getting that wrong would silently drop every `Map[Str, T]` in a generic body back
  to the flat path, and no assertion about declines could see it.
- **a container inside a carrier erases its element; a Map does not.** `Option[List[Str]]` and
  `Option[List[Int]]` deliberately share **one** typedef `blink_Option_list`, while
  `Option[Map[Str,Int]]` and `Option[Map[Int,Str]]` get two byte-identical-but-for-the-name
  typedefs. I expected the structural spelling for both; the test said otherwise and the
  *spelling* is right. Pinned rather than "corrected".

Three cells are not reachable from a `check_types`-only harness and say so in the file, with the
sweep named as their evidence instead of an assertion loosened into a tautology: the
module-prefixed spelling of a bare struct (`c_type_c_name` consults a registry populated during
emit — 19,262 agreeing `ctype.struct` rows), the transparent-newtype arm
(`is_transparent_newtype`'s shape gate reads codegen's `enum_variants`, empty there), and
`Ptr` against a real ffi pointee (`ctype.ptr_ann` 78, `ctype.ptr_ffi` 169).

### Tickets

- br `0rmamy` — filed. Unannotated unit-only-enum local declared `int64_t` instead of its
  typedef (965 rows), plus 7 `Ptr` rows losing a known pointee and 1 `U64`. The first authority
  flip's witness.
- br `rb5hsv` — filed. `canonical_struct_tag`'s underscore-split grammar double-prefixes a
  module-qualified carrier half. Latent (no caller reaches it with such a tag today);
  worked around in `c_type_from_tid`, not fixed.

## Stage 3b — the first authority flip: `Ptr` locals (br `q3ssqw`)

Date: 2026-08-12. `task regen` green; `task ci` green (660/660 tests, 1540 fmt rows).
**This is the first site in the collapse where the tid governs an emit decision** rather than
being measured beside one.

### Why this cell went first

Of the 973 class-(i) rows — the ones where the tid is right and the flat path is wrong — the
enum bucket is 966 and the `Ptr` bucket is 7. The small bucket went first, on purpose, because
it is the only one with an **observable failure**. An enum-as-`int64_t` is quiet: C converts
enum↔int implicitly, so flipping it can only be verified by diffing emitted C against a counter.
An erased pointee is not quiet:

```
let s = "hi"
let p = s.as_cstr()      //  void* p = ...;      <- pointee lost here
let v = p.deref()        //  const int64_t v = (*(p));
                         //  error: void value not ignored as it ought to be
```

Four lines, no `ffi` import, and the diagnostic is a **cc escape** — the worst class this
compiler can produce, because there is no Blink span to point at. A red/green test can therefore
prove the flip, which is the property that makes it the right first step.

Note the *second* erasure on that emitted line: `const int64_t v`, where the Blink type of
`p.deref()` is `U8`. Both halves come from the same missing channel, and fixing the
**declaration** fixed both — once `p` is `uint8_t*` the dereference has a real type and storing
it in an `int64_t` slot is an ordinary C widening. One branch, two erasures.

### The branch, and why it declines on `void*`

`emit_let_binding`'s declaration chain had a `ptr_ann` arm (pointee from the binding's own
annotation) and a `ptr_ffi` arm (pointee from `ffi_offset_pending_struct`) and nothing for a
`Ptr` whose pointee is known only to typecheck — so it fell to the final `else` and printed
`c_type_str(CT_PTR)` = `void*`. The new `ptr_tid` arm sits after those two and asks the tid.

The helper declines when `c_type_from_tid` answers `void*`, and that decline is what **bounds**
the flip: `void*` is precisely what the flat path already prints, so a tid that knows no more
than the flat fields must not take authority away from them. Only a tid carrying a real pointee
changes a declaration — so the emitted-C diff for this sub-step is exactly the rows the ctypediv
census named, and nothing else. That is a much stronger statement than "the tests still pass".

Folded in with it: `decl_tid` is now substituted through `tc_tid_subst_mono` **at the point of
capture** instead of at the probe call. The probe was already substituting; the governing branch
needs the same tid, and computing it in two places would have let the governing value and the
measured value drift — the exact failure mode this whole plan exists to remove.

### Measured result

Re-swept the 874-file basis with the identical script. `ty=Ptr[...]` diverge rows: **9 → 0**
(7 on the `common.lst` basis; the two extra live in `test_ps5br9_ffi_scope_receiver_type.bl`,
which the basis filter drops). `ctype.flat` diverge **981 → 974**; every other site unchanged to
the row. Residual **1245 → 1238**.

| | before | after |
|---|---:|---:|
| `ctype.flat` diverge | 981 | **974** |
| all other sites | 264 | 264 |
| total residual | 1245 | 1238 |

**All 9 changed declarations are in `tests/`; none in `src/` or `examples/`.** So the first
authority flip in the collapse changed nine lines of emitted C for corpus programs and *not one
line* of the compiler's own output — which is why the bootstrap fixed point held without a
byte-identity argument being needed.

### Two rows that could not be written, and why that is a finding

Both were established by *running* the shapes, not by reading the code, and both are recorded in
the test file so the next person does not re-derive them:

- **There is no user-fn producer of a `Ptr[T]`.** `error[PtrOutsideFFI]` (typecheck.bl:4253)
  restricts the type to `@ffi` fns and `@trusted` **blocks**; `@trusted(audit:ID)` on the fn does
  *not* satisfy it, and `@ffi` then demands declared effects. Every `Ptr` value in the language
  comes from a builtin, an intrinsic, or a scope method — so the three call paths the test uses
  (`Str.as_cstr`, `ffi scope.take`, `ffi scope.cstr`) are not a sample of the producers, they are
  the producers.
- **An erased pointee cannot silently miscompute a stride.** `Ptr.offset()` on a scalar pointee
  is gated by `error[FfiOffsetUnknownStride]` whether or not the binding is annotated, so a
  byte-walk row cannot be written at all. That path fails **closed**, which is the correct shape
  for a stride the compiler genuinely does not know — worth stating explicitly, because "the
  pointee is erased" invites assuming the arithmetic is wrong too, and it is not.

### The corpus had all 9 rows and never failed

Six files carried them, and every one calls only `.is_null()` or `.to_str()` on the erased local
— neither dereferences. The tap existed, was hit 9 times, and could not fire
(`feedback_corpus_sweep_is_not_coverage`). The four cc-escape rows in
`tests/test_q3ssqw_ptr_call_return_pointee.bl` are that tap being exercised for the first time;
the four regression pins are the annotated forms plus `is_null`/`to_str`/`addr`, i.e. exactly
what the corpus *was* covering.

## Stage 3c — the enum bucket, and the census collapses (br `0rmamy`)

Date: 2026-08-12. `task regen` green after the gen1 promotion; `task ci` green (661/661 tests,
1542 fmt rows). **`ctype.flat` diverge 974 → 9. Total diverge on the 874-file basis: 988 → 23.**

### The cause was `infer_enum_from_node`, and the axis is not the producer

`emit_let_binding` gets its enum name from `infer_enum_from_node(val_node)` — an inference over
the RHS **syntax**. It goes blank the moment the value arrives through a plain call or an
anonymous C temporary, and the declaration then falls through to `c_type_str(CT_ENUM)`, which is
`int64_t`.

Measured by emitting C for one probe per position rather than by reading the code. Six positions
lose the enum name and five keep it:

| lost | kept |
|---|---|
| a plain call return, `pick()` | variant construction, `Col.Green` |
| a `match` expression's value | a field read, `bx.k` |
| an `if` expression's value | a trait-method return |
| a `mut` local bound to a call | a generic fn's return, `idc(Col.Green)` |
| `list.get(0).unwrap()` | `.unwrap()` on an **annotated** `Option[Col]` local |
| `map.get(k) ?? Col.Green` | |

The axis is not *which producer* but **whether the value passes through an anonymous C temporary
(`_match_4`, `_if_11`, `_ounw_8`, `__opt10`) or a bare call** — the flat fields carry an enum's
name in `sname`, and nothing stamps `sname` on a temp. The right-hand column is exactly the set
of positions where some earlier ticket hand-wired the name through. That is the
(position × shape) cartesian product from the plan's root-cause section, visible in one probe.

This also **corrected an earlier note on the ticket**, which had recorded `Option.unwrap()` as a
wrong producer. `.unwrap()` on an annotated `Option[Col]` local is right; `.unwrap()` reached
through an anonymous Option temp is wrong. Same method, different position — which is the point
above, and the reason the earlier note read as "two wrong producers" instead of one rule.

### The arm's placement is the load-bearing decision

`enum_tid` sits **after** every branch that already spells an enum. The `enum`/`enum_mono` arm
keeps the bindings whose flat `enum_type` survived; the new arm only catches the ones where it
went blank. Placing it earlier would take bindings away from arms that already spell them
correctly — a regression that **no failing row would reveal**, since both arms print a
`blink_*` name. The five "was already right" rows in the test exist to hold that ordering, and
they are the reason the test has eleven positions rather than six.

Two declines in `enum_c_from_tid`, both deliberate: a **generic enum instance** has children so
`c_type_from_tid` returns `""` and the `enum_mono` arm keeps ownership of per-instantiation
spelling (br `jjhnf3`); a **transparent newtype** spells `int64_t` (br `ja9jev`), which is what
the flat path already prints, so declining on equality leaves that decision untouched. Same
decline-on-no-improvement contract as `ptr_c_from_tid` in Stage 3b.

### The bootstrap needed the two-regen promotion, and its diff is the verification

Unlike Stage 3b (whose nine rows were all in `tests/`), this flip changes the **compiler's own**
emitted C, so the first bootstrap fails `gen1.c != gen2.c` **by construction**: gen1.c is
produced by the old binary from new source, gen2.c by the new binary
(`project_codegen_emit_string_bootstrap`). `cp build/blinkc_gen1 build/blinkc`, re-run, fixed
point restored.

The failing diff is the best evidence this sub-step produced — **31 lines, and every one of them
this shape**:

```
-        const int64_t assert_kind = blink_parser_peek_kind();
+        const blink_tokens_TokenKind assert_kind = blink_parser_peek_kind();
```

28 `blink_typecheck_TyKind` + 3 `blink_tokens_TokenKind`, nothing else. A change to the
compiler's own output that can be read in full and matched line-for-line against the census is a
stronger statement than a green test suite, and it is only available because the bootstrap
diffs gen1 against gen2 instead of trusting either.

### Why the test asserts on emitted C

Every other cell closed in this project got a test that runs a program and reads a value back.
This one cannot, and the test file says so at length instead of pretending otherwise: C converts
enum↔int implicitly, so `int64_t c = blink_u_pick();` followed by
`blink_u_score(c)` — declared `int64_t blink_u_score(blink_Col c)` — is well-formed and computes
the right answer on every mainstream target. **The emitted C is the observable for this cell.**
A runtime test would have passed before the fix, which is precisely why 966 rows survived this
long: nothing observable depended on them.

What still matters is that a declaration reading `int64_t` has thrown away the fact that the
local holds a `Col`, so everything downstream — a debugger, a narrower target where the widths
differ, and above all the next codegen change that reads a declaration back — must re-derive it
from a side channel. That re-derivation is the bug family the collapse exists to end.

One harness fact worth reusing: `generate` opens with `debug_assert(cg_lines.len() == 0)` and
does not clear the buffer on exit, so **it may be called exactly once per process**. The test
caches its emitted C in a module global; without that, `task ci` (which runs tests in debug
mode) trips the assert on the second row — and `build/blink run` without `--debug` does not,
which is a good reason to run a new test both ways before believing it.

### Census after Stage 3c

| | before 3b | after 3c |
|---|---:|---:|
| `ctype.flat` diverge | 981 | **9** |
| `ctype.struct` diverge | 8 | 8 |
| `ctype.void_placeholder` diverge | 6 | 6 |
| declines (all sites) | 250 | 250 |
| **total residual** | **1245** | **273** |

The 23 remaining diverge rows are the documented class-(v) set plus one new ticket:

- 6 `Void` placeholders — a *storage*-position rule (br `hsgsbp`), not a spelling defect
- 5 `ty=Int tidc=int64_t emitted=int` at `src/codegen.bl:452` — a `Bool + Bool` sum in an `int` slot
- 3 `Void`-vs-`int64_t` at with-ptr bindings, where typecheck and codegen disagree about the type
- 8 generic-fn tuple returns erasing a Map — a deliberate mono convention; unifying it would
  fragment one C struct into N identical ones
- **1 `U64` row → br `tm1vbv`**, filed: a mono'd typevar local of an unsigned type declared
  `int64_t`. The last class-(i) row. Split out rather than folded in because signedness changes
  what `<`, `>>` and `/` **mean** for the same bits — the correct meaning for a `U64`, but a
  behaviour change rather than a representational one, so it needs a test that runs comparison
  and division above 2^63 and not just a declaration pin.

The 250 declines are unchanged and stay that way: 164 by design (mono spelling is a separate
seam) and 87 family-A rows whose tid is itself `?`, held on the four undecided causes
(`qzdz2e` panel, `w3v2e6` blocked on `8vcj2c`, `jr4xf7` and `mwsy85` `type:spec`).

**So Stage 3's exit criterion is now within reach of decisions rather than of work**: of 1245
residual rows, 273 remain, 250 of those are declines-by-contract or blocked on panel questions,
and the 23 diverge rows are five documented conventions and one filed ticket.

### The anonymous temporaries are still `int64_t`, and that is stated, not hidden

`_match_4`, `_if_11`, `_ounw_8` and `__opt10` keep their erased declarations after this fix.
They are a different emit seam (`codegen_expr`), they are **not** in the ctypediv census — which
probes `emit_let_binding`'s declaration chain and nothing else — and `int64_t` → enum assignment
is a legal implicit conversion, so the declarations this sub-step fixed are correct regardless.
A future sub-step that adds a ctypediv probe at the temp emit sites would enumerate them the
same way this one enumerated the locals. Naming the uncovered seam is the point: a census is
only trustworthy if its boundary is written down (`feedback_corpus_sweep_is_not_coverage`).

## Stage 3d — the uncensused seam, entered on purpose (br `9ce8nr`)

Stage 3c closed with a written-down boundary: the ctypediv census probes `emit_let_binding`'s
declaration chain **and nothing else**, so the anonymous temporaries `codegen_expr` and
`codegen_methods` emit were named as uncovered. This sub-step is the first walk into that seam,
and it starts with the temp the 3c probe kept running into: `_ounw_N`, the Option-unwrap
temporary.

It is not a census row. It is a compile failure.

```blink
let x: U64 = 7
let o: Option[U64] = Some(x)
let v = o.unwrap()
```

```
build/optu64.c:128:32: error: invalid initializer
  128 |     blink_Option_int _ounw_0 = o;
```

**The construct side was never wrong.** The same emitted file carries all fourteen carrier
typedefs it needs, `blink_Option_u64` and `blink_Option_bool` among them, so `Some(x)` had always
ensured and spelled the right carrier. Only the unwrap temp disagreed. The scalar tail of the
`unwrap` dispatch named `CT_FLOAT` and `CT_CHAR` explicitly and sent everything else to
`option_c_type(CT_INT)`:

```blink
} else if inner == CT_CHAR {
    ...
} else {
    let opt_c = option_c_type(CT_INT)   // every remaining inner type, right or wrong
```

so **eight** inner types escaped to cc: `U8`, `U16`, `U32`, `U64`, `I8`, `I16`, `I32` and `Bool`.
`Bool` was not in the original filing; measuring one type at a time rather than reading the
ladder is what added it.

The three-way ladder collapses to one arm that names the carrier from the operand's own inner CT.
The interesting part is what the arm refuses to do:

```blink
pub fn unwrap_scalar_ct(ct: Int) -> Int {
    if ct == CT_FLOAT || ct == CT_CHAR || ct == CT_BOOL { return ct }
    if is_sized_int_ct(ct) != 0 { return ct }
    CT_INT
}
```

An **allowlist, not a pass-through.** A `CT_ENUM` inner is `int64_t` by representation and has no
carrier of its own; `CT_VOID` and an unresolved `-1` have none either. Passing `inner` through
unguarded would spell `blink_Option_enum` — a name nothing emits — and trade eight escapes for a
ninth. This is the same shape as the `enum_c_from_tid` / `ptr_c_from_tid` decline-on-no-
improvement contract from 3b and 3c: the richer authority governs only where it is genuinely
richer.

One regen, fixed point first try — no two-regen promotion, because no compiler source unwraps an
Option over a sized integer. That is the same fact as *why the corpus never caught it*: an
unexercised tap (`feedback_corpus_sweep_is_not_coverage`), and one that fails **loudly** the
moment it is exercised. Unlike a census cell, this needed no divergence count to justify — a
red/green test pins it directly. RED was 9 cc errors; GREEN is 13/13; `task ci` 662/662.

### Probing the siblings, because a hardcoded carrier is a pattern

A defect that reads "this arm names one carrier for every type" is worth spending three MVCEs on
before believing it is confined to one method:

| sibling seam | verdict |
|---|---|
| `??` on `Option[U64]` | **correct** — prints `18446744073709551615` |
| `.unwrap_or` | **not a language feature.** `blink llms --topic option` lists `unwrap`/`is_some`/`is_none` and names `??` as the with-default idiom. My probe was wrong, not the compiler |
| `Result[U64, Str]` | **broken, and worse** → br `3xd320` |

The `Result` finding is a different and more serious defect than the one this sub-step fixed:

```
build/res_local.c:316:11: error: unknown type name 'blink_Result_u64_str';
                                did you mean 'blink_Result_int_str'?
```

No unwrap is involved — **declaring** the local is enough, and the compiler's own hint names the
carrier that *was* emitted. `ensure_result_type` keys its registry by the **decimal string** of
the two CT integers (`"{ok_t}_{err_t}"`) and `emit_all_option_result_types` decodes it back with
`ct_from_str`, a hand-written string→CT ladder that ends at `"20"` (`CT_SET`) and answers
`CT_INT` for anything past it. `CT_I8`..`CT_U64` are 25..31 and `CT_CHAR` is 32, so all eight
round-trip as `CT_INT`: the ensure registers the right pair, the emitter prints
`blink_Result_int_str`, and the name the declaration actually uses is never declared.

`Option` is immune for one reason worth recording: `emitted_option_types` is a `List[Int]` and
never stringifies. Only the `Result` registry round-trips a type through a string, and only it
loses types. That asymmetry — same defect class, one registry away — is the plan's thesis in
miniature: the loss is not in the type system, it is in a representation that cannot hold what
the type system already knew.

### And the fix for it is a deletion (br `3xd320`)

```blink
fn ct_from_str(s: Str) -> Int {
    s.to_int()
}
```

That is the whole repair. **The ladder was not extended**, deliberately: adding eight entries
turns the test green and leaves the trap one entry longer, so the next `CT_*` added to the file
reopens the defect silently, for whichever type it happens to be. The same key decode appears
**twice** in `codegen_types.bl` — the whole-program emit loop and the incremental per-module one —
and repairing the shared helper fixed both; extending a ladder in two places is the version of
this fix that rots.

An exact decode newly reaches the CTs past the old end (`CT_STRUCT` 23, `CT_ENUM` 24, and the
handful whose `c_type_tag` is `"void"`), so that end was checked before the change rather than
after:

- `emit_result_typedef` already dedups by the typedef **name** (`result_typedef_emitted`), so two
  keys that share a name emit once. No redefinition hazard — and `c_type_tag` answers `"void"` for
  eight different CTs, so the hazard was real enough to check.
- Where such a key exists, the exact decode makes the emitted name **agree** with what the
  declaration site spells through `result_c_type`. Strictly more consistent than printing
  `int_str` for it.

RED was 10 `unknown type name` errors: the 8 ok-side types, the **Err arm** of a sized-int
`Result` (a separate emit path, `emit_err_result`), and a sized int in the **Err position** (the
other half of the key, same ladder). GREEN is 15/15, `task ci` 663/663 with fmt 1546/1546. Every
row declares the `Result` — where the escape happened — and then unwraps it, so a typedef emitted
with the wrong member width still fails: the `U64` row round-trips a value above 2^63 and would
answer wrong through an `int64_t` member.

`CT_STRUCT` and `CT_ENUM` sit past the ladder's end too, but they route through the separate
struct-carrier registry, keyed by tag rather than by CT, so they were never affected. A struct row
in the test pins that separation, so a later change cannot quietly reroute them into the scalar
registry.

### What these two sub-steps say about the seam Stage 3c left uncovered

Both defects were found by *entering* the uncensused seam and probing it by hand, not by reading
a counter — and both were louder than anything the census contains: a census row is a spelling
that could be better, while these were programs that do not compile at all. The census measures
`emit_let_binding`; the carriers, temps and registries around it are measured by constructing the
shape and running it (`feedback_corpus_sweep_is_not_coverage`). Three MVCEs spent on sibling
seams turned one filed ticket into two fixed ones and one language fact (`.unwrap_or` does not
exist; `??` is the idiom), which is a better return than any of them would have had alone.

### The last class-(i) row, and why it is not shaped like 3b or 3c (br `tm1vbv`)

This is the one census row Stage 3c left open, and closing it empties class-(i) — the class where
the tid is right and the flat path is wrong. It is also the sub-step where the *kind* of fix
changed, which is the part worth writing down.

**The axis is the anonymous temporary, not monomorphisation.** The ticket was filed as "a mono'd
typevar local of an unsigned type declared `int64_t`", because the single census row sits inside a
mono'd generic fn. That was a coincidence of the corpus. Measured one shape per position, by
running programs:

| lost — the value arrives through an anonymous temp | kept |
|---|---|
| `l.get(0).unwrap()` → `_ounw_N` | an annotated binding |
| `m.get(k).unwrap()` → `_ounw_N` | a generic fn's return, `ident(big)` |
| `r.unwrap()` → `_runw_N` | a field read, `b.v` |
| | an `if` expression's value |
| | a `match` expression's value |
| | `o.unwrap()` on an `Option[U64]` local |

No generics are required anywhere — the same axis br `0rmamy`'s enum bucket had. The last "kept"
row was *lost* until br `9ce8nr` earlier in this stage: naming the Option-unwrap temp from the
operand's own inner type repaired this declaration downstream as a side effect, which is the shape
of the whole family — one seam repaired, several positions fixed.

**Spelling vs recorded CT — the distinction this sub-step establishes.** Stages 3b and 3c each
added a declaration-chain arm: those change the emitted C string and nothing else, so a
declaration pin is a sufficient test. A sized integer's type governs three further things, and all
three read the **recorded** `ScopeVar` CT rather than the emitted spelling:

1. whether `/`, `<` and `>` are the signed or the unsigned operator;
2. whether `+` emits the overflow **trap** the spec promises ("Arithmetic on sized ints
   (`+`, `-`, `*`, `/`, `%`, unary `-`) traps on overflow") or plain 64-bit arithmetic;
3. whether `.wrapping_add` and the other modular escape hatches resolve at all.

So the fix feeds the answer into `val_type` **upstream of `set_var`** — it is the tid twin of an
annotation rule that already sat two lines above it — instead of into the declaration chain below.
One change, all three symptoms. Had it gone into the declaration chain, a declaration pin would
have passed while the program still answered `0` for `18446744073709551615 / 2`.

That is not a hypothetical: the first note on this ticket called the row "representational", from
reading a declaration. Running it says otherwise, three ways — `/ 2` answers **0** and `> 5`
answers **false** with no diagnostic; an erased `U8` answers **256** for `255 + 1` where the
annotated form panics `U8 overflow in +`, so a spec safety guarantee is silently withdrawn; and
`.wrapping_add` fails to resolve with a message that names the correct type
(`unresolved method '.wrapping_add' on type U8`) while dispatching on the wrong recorded CT. The
compiler names the right type in the very sentence where it fails to find that type's method.

The read is substituted through the enclosing monomorphisation (`tc_tid_subst_mono`) like every
other tid consumer in codegen — not because mono is the cause, but because the census row does sit
inside a mono'd fn, and an unsubstituted read would see the typevar `K` and decline exactly there.

### Census after Stage 3d — class-(i) is empty *on the corpus*

On the 874-file common basis (`feedback_corpus_sweep_is_not_coverage`: intersect, do not exclude
new test roots):

| | after 3c | after 3d |
|---|---:|---:|
| `ctype.*` diverge | 23 | **22** |
| declines (all sites) | 250 | 250 |
| **total residual** | **273** | **272** |

The single cell removed is exactly `bucket=diverge site=ctype.flat ty=U64 tidc=uint64_t
emitted=int64_t`, and the whole-corpus `U64` diverge count is now 0. The 22 that remain are
6 + 5 + 3 + 8 — the six `Void` placeholders (br `hsgsbp`), the five `Bool + Bool` sums in an `int`
slot at `src/codegen.bl:452`, the three `Void`-vs-`int64_t` with-ptr bindings, and the eight
generic-fn tuple returns erasing a `Map` by deliberate mono convention. That is the five documented
conventions with **nothing left over**.

So the residual census is now decisions and one convention, not work: `hsgsbp`, `qzdz2e` (panel),
`w3v2e6` (blocked on `8vcj2c`), `jr4xf7` and `mwsy85` (`type:spec`). Three rows sit outside the
common basis, in test files added during this stage, and all three are pre-documented classes (one
`codegen:452` sum, two declines) — stated rather than quietly excluded.

Stage 3's remaining work is therefore not census-driven: collapse the five spellers into one, and
replace `copy_list_compound_elem` with a node-tid-sourced copy.

**The qualifier in that heading is load-bearing, and the very next sub-step proved it.** "Class-(i)
is empty" is a statement about the 874 files, not about the language. Walking into
`copy_list_compound_elem` immediately produced a hand-constructed class-(i) row the corpus does not
contain (br `85j3j8`, below) — tid `List[(Int, Int)]`, flat `List[]`. A census bounds what has been
*measured*; it never bounds what exists (`feedback_corpus_sweep_is_not_coverage`). An earlier
revision of this section wrote the heading without the qualifier, which is the exact
task-count-as-done failure mode 03p551 was opened over.

### The class-(i) row the corpus lacks, and the two rounds it took to see it (br `85j3j8`)

Measuring `copy_list_compound_elem` before touching it — the plan's one-line prescription for it is
`set_var_ty(dst, get_var_ty(src))` — produced three findings, and the third became a bug fix.

**(i) The plan's literal prescription cannot work.** The whole 874-file corpus reaches that function
**once**, from `test_yvq32w_compound_inner_in_mono_body.bl`, and its `src` there is the emitted C
expression `blink_build_1list_1of_1maps_0Str_0Int("x", 5)` — not a variable name — so
`get_var_ty(src)` returns `-1`. The copy must be sourced from the *node's* tid, not from a name
lookup on a C string.

**(ii) The "MISSING ARMS" are not the hole.** The `copy_list_compound_elem.no_arm` tap has **zero**
hits in every sweep, and the arm is unreachable from all three call sites: `codegen_stmt.bl` (both
copies) gates the call on `expr_list_elem_type == CT_OPTION || CT_RESULT || CT_MAP`, and
`codegen_methods.bl:4380` gates on a `carrier` whose recogniser (`compound_tag_ct`) only knows
`Option_` / `Result_` / `Map_`. The hardcoded triple in the *callers' guard* is the hole; the
function's missing `CT_SET`/`CT_LIST` arms are downstream of a door that never opens.

**(iii) The element kind that actually loses is the one no arm and no guard mentions — `Tuple`.**
Measured one shape at a time by running programs: `List[List[T]]`, `List[Set[T]]`, `List[Struct]`
and `List[Map[K, V]]` are all correct read at depth, while an unannotated `let` bound to a **call**
returning `List[(A, B)]` erases the element. Three symptoms, and the worst is the quiet one:

| | emitted | how it presents |
|---|---|---|
| `let x: Int = f.0` | `const void x = f._0;` | cc error, **no Blink span** |
| `f.0 + f.1` in `"{...}"` | the fmj80a placeholder | prints `<value>` where a number belongs |
| `for p in g`, `.filter().collect()` | `blink_Option_void` | cc error, no span — **and a different bug** |

`tid=List[(Int, Int)] flat=List[]`, `tid=(Int, Int) flat=Int`, `tidc=blink_Tuple2_int_int
emitted=int64_t`. Class-(i) — the tid is right, the flat path is wrong — and the plan's thesis in
one screen. Generics are not required; a non-generic fn return reproduces it, and annotating fixes
it. The axis is the missing annotation.

**Three coupled gaps, in the order they block each other.** `tk_to_ct(TyKind.Tuple)` is `CT_VOID` so
`tid_inner_ct` answers `-1` — correct, and it stays: a tuple has no CT. But it has a generated tag,
and codegen's List house convention already spells a tuple element the way it spells a struct
element, as the pair `(CT_VOID, sname)`. What was broken was that (1) `tid_inner_struct` answered
`""` for a Tuple, so the tid side could not name it; (2) `recover_list_elem_from_tid` bailed at
`if ect < 0 { return }` *before* consulting the struct slot, so even a nameable element died there —
its own header comment claimed a tuple element was "a safe no-op", which the measurement disproves,
and the comment is corrected in place; and (3) `emit_let_binding`'s `CT_LIST` ladder had no tid last
resort where the `CT_SET` branch twelve lines above has had one since `mv45y5`.

**The guard took two rounds, and that is the lesson worth keeping.** The first attempt gated the new
arm on *"no element recorded"* — and it never fired. A new `listelem` `letladder` tap showed why: the
RHS of `let g = build_int_pairs()` carries `expr_list_elem_type = CT_STRUCT` — a tuple *is* a struct
here — with **no sname**, and `val_str` is a C call expression, so neither
`get_list_elem_struct(val_str)` nor `expr_list_elem_struct` can supply one. The element was present
and nameless, not absent. So the predicate is `list_elem_unspellable`: absent, **or** a
`CT_STRUCT`/`CT_ENUM`/`CT_VOID` marker with an empty struct slot. The tap is kept permanently,
because from the outside the two failure modes are indistinguishable and only the second was real.

**Census, same intersected basis.** `ctype.*` unchanged at 22 diverge / 250 declines, cell map
byte-identical. The `tydiv` map holds at 394 cells (familyA 11 cells / 100 rows) with exactly two
changes, both improvements:

- **removed** `site=emit_let_binding.decl tid=List[Int] flat=List[]` — `let result = list_concat([1,
  2], [3, 4])` in `test_list_hof_stdlib.bl`. An `Int` element, no tuple in sight: the recovery is not
  tuple-specific.
- **corrected** `var=k tid=K flat=Int` → `flat=U64` — `let k = ks.get(i).unwrap()` in `count_inc[K]`,
  U64 instance. Same nine diverge rows for that file before and after; the flat answer went from
  *wrong* to *right*, and stays booked as diverge only because the tid side spells the abstract
  typevar `K` inside a generic body, which is the known class-(ii) convention. A latent U64-key
  erasure in a generic body, fixed as a side effect.

**Symptom 3 is a different bug, and splitting it was the point.** `for`-in and
`.filter().collect()` emit `blink_ListIterator_void` because the iterator emitters
(`list_iter_c_type` / `emit_list_iter_typedef`, `codegen_types.bl:7502`) take a bare `inner: Int` CT
and spell it with `c_type_tag(inner)` — so an element whose C name lives in the companion sname slot
loses the name *however the binding got it*. It reproduces with a plain `List[Pt]` and no tuple
anywhere, and reproduces identically with `85j3j8`'s source changes stashed: neither caused nor cured
by the binding fix. Filed as br `1n9fhg` with those two rows as its MVCE. One red test standing for
two causes would have hidden whichever was fixed second — and `1n9fhg` is itself a cell the collapse
removes structurally, since a tid-sourced element carries its own name and there is nothing to lose.

### The same shape one axis over, and the axis is not the tuple (br `6g6g7t`)

`85j3j8` fixed `List[(A, B)]` reached through a **binding** — `let g = make_tups()` then `g.get(0)`.
The chained form `make_tups().get(0)` still failed, and the reason is the plan's thesis stated as
plainly as it gets:

```
let g = make_tups()    ->  g is a ScopeVar; the element can be stored on it
make_tups().get(0)     ->  the receiver is the C string `blink_u_f_make_tups()`
```

Every reader in `emit_list_method` derives the element with `get_list_elem_type(obj_str)` /
`get_list_elem_struct(obj_str)`, which look `obj_str` up as a variable **name**. A call expression has
never had a `ScopeVar` under that name, so every reader gets the not-found sentinel and degrades to
boxed `int64`. Measured on the `copy_list_compound_elem` analogue of the identical hole:

```
bucket=missing site=copy_list_compound_elem.src var=blink_u_f_loptmap() tid=- flat=-
```

`flat=-` is the whole finding. **The flat universe is keyed by variable NAME; the tid is keyed by
NODE.** A list that never had a name is not merely mis-spelled in the flat universe, it is
*unrepresentable* in it — while the tid is present and exactly right at the same place. No amount of
per-cell repair reaches this class; only a node-sourced type does.

**Broader than the ticket title.** The rows written as *pins* — expected-passing siblings, there to
bound the tuple claim — failed too: a chained `List[List[Int]]`, `List[Map[Str, Int]]` and
`List[Option[Int]]` all lost their element identically. So the tuple is not the axis, the missing
`ScopeVar` is, and it loses **every** element kind. Those rows stayed in the test file as the record.

**The fix is one gate, because stamping serves every reader at once.** In `emit_builtin_trait_method`,
before the ListOps dispatch: when the receiver is a `CT_LIST` and nothing is recorded under
`obj_str`, stamp the element from the object node's tid. `set_list_elem_type` **pushes** a scope var
when the name is absent (`codegen_types.bl:2991`) — the same mechanism `fresh_temp` names already
rely on — so one write registers a synthetic entry that all ~20 readers below then find, instead of
each reader growing its own tid path.

**Getting there needed a move, and the module direction dictated where.** `codegen_expr` imports
`codegen_methods` (`codegen_expr.bl:87`), so `codegen_methods` can never import
`recover_list_elem_from_tid` back. Duplicating the rule is exactly what this plan exists to delete,
so `recover_list_elem_from_tid`'s body and `deep_tp_from_tid` moved down into `codegen_types` — which
both files already import — as `stamp_list_elem_from_tid(node, var_name) -> ListElemStamp{ct, sname}`,
effect-free, returning the pair instead of writing globals. The `codegen_expr` function is now a
four-line wrapper that mirrors the pair onto the `expr_list_elem_*` globals. One body, two entry
points. Done as its own regen: pure move, fixed point held, emitted C unchanged.

**The trap, found by a segfault: `(CT_VOID, "")` is a REAL spelling, not only an erasure.** The first
gate reused `list_elem_unspellable` — `85j3j8`'s predicate, which counts a nameless `CT_VOID` as lost.
But that pair is how a **by-value plain-enum** element is recorded, and the *declared* path stamps
exactly that for an annotated `let l: List[Col]`. Re-stamping it from the tid promoted the element to
the `(CT_VOID, sname)` struct-pointer convention, so `.get()` emitted
`(blink_Col*)blink_list_get(..)` and the reader dereferenced an integer:

```c
_lget_2.value = (blink_Col*)blink_list_get(l, _lgi_1);   /* after  — wrong */
blink_Col _ounv_4 = *_ounw_3.value;                      /* deref of a by-value enum */
```

`test_0rmamy` **segfaulted with all eleven of its printed rows still reading `ok`** — the crash was
in the twelfth row's probe program, not in an assertion, so `task test`'s summary line was the only
thing that reported it, and running the test binary alone showed `EXIT=139` with no `passed/failed`
line at all. `build/blinkc.bak` attributed it to the right regen in one compile: `task regen` copies
the previous compiler there before rebuilding, so diffing its emitted C against the new one localises
a regression with no stash-and-rebuild cycle.

The narrowed gate is `get_list_elem_type(obj_str) < 0 && get_list_elem_struct(obj_str) == ""` —
literally the measured `flat=-` condition, i.e. *no element recorded at all*. That also means it
cannot override any flat answer, right or wrong; Stage 3's authority flip is what reverses precedence,
and until then each cell stays one measurable shape. `list_elem_unspellable` moved to `codegen_types`
with a header comment recording that it is only valid at the unannotated let-ladder it was measured
against, and the call site carries the same warning.

**Census, on a 954-file intersected basis — and the interesting number is zero.** `tydiv` 4811
diverge rows and 409 cells before and after; `ctypediv` 23 diverge rows and 7 cells before and after.
Both cell maps diff empty. **The corpus census could not see this cell**, because the ~20 readers in
`emit_list_method` carry no `sv_ty_or_flat` tap — they call `get_list_elem_*` directly. A silent
counter here is `feedback_corpus_sweep_is_not_coverage` in its sharpest form: the instrument's
stability is evidence about the *instrument*, not about the code, and the only thing that found this
was writing the shape by hand and running it. Class-(i) being "empty on the corpus" after Stage 3d
holds only for the sites that are tapped.

The new test file adds 12 diverge rows of its own, all the known class-(ii) convention artifact
already described under Stage 3a — `tid=(Int, Str) flat=Tuple2_int_str` and `tid=List[(Int, Str)]
flat=List[Void]`, the printer dropping the companion sname — plus `tid=List[Pt] flat=List[Void]` for
the struct pin, which is the same printer, not a loss.

**Not fixed here, deliberately.** Map and Set receivers have the identical expression-vs-variable hole
on their own key/value channels (a chained `make_maps().get("k")` where the Map itself is the
expression); their metadata lives in different slots with no `stamp_*` twin yet. And the depth-3
family — `List[Option[Map[Str, Int]]]` read through unannotated intermediates — is br `f9hgt9`,
verified still failing identically after this fix, so the two are independent.

### `copy_list_compound_elem`, and the state the pool cannot represent (br `bef42x`)

The plan's one-line prescription for this function is `set_var_ty(dst, get_var_ty(src))`, and
Stage 3d's measurement already showed why that cannot work: `src` is an emitted C expression, not a
name. Building the shape by hand to fix it properly produced a second finding that is worth more than
the first.

**The cell.** An unannotated `let` bound to a **call** returning a List whose element is a compound:

```blink
fn loptmap() -> List[Option[Map[Str, Int]]] { .. }

loptmap().get(0).unwrap().unwrap().get("a")   // WORKS
let e = loptmap()                             // ...and now the same chain does not
e.get(0).unwrap().unwrap().get("a")
```

Adding the `let` is a **regression relative to not binding at all** — the inversion is the fingerprint.
The unbound form works because `6g6g7t`'s receiver stamp reads the object node's tid; the bound form
goes through `emit_let_binding`'s unannotated `CT_LIST` ladder, which stamps the shallow element CT
and then asks `copy_list_compound_elem(val_str, name)` to carry the inner across. `val_str` is
`blink_u_f_loptmap()`, no `ScopeVar` has ever had that name, so every arm sees `elem_ct = -1` and
writes nothing. `List[Result[Map, E]]` and `List[Option[List]]` fail identically; annotating fixes all
three; depth 2 (`List[Map[Str, Int]]`) was already right. So the axis is the compound element's
**inner**, reached through a let.

**And the obvious fix does not fire, which is the finding.** The first attempt gated the tid recovery
on a new `list_elem_compound_inner_missing(name)`. It answered false, and the `listelem` tap said why:

```
letladder var=e val_type=4 ann=-1 expr_elem=7 sv_elem=0
```

`set_list_elem_type` routes through `sv_tp`, and **`sv_tp` fabricates**: `sv_tp(CT_OPTION, -1, ..)`
returns `type_option(type_int())` (`codegen_types.bl:1564`), with the `Result` and `Map` arms
defaulting likewise. A lost inner and a genuine `List[Option[Int]]` are therefore the *same pool
state, bit for bit*. **"Outer recorded, inner missing" is not an observable state of codegen's type
representation** — so no predicate over the flat fields can separate the two, and the only authority
that can is the tid. This is the plan's confirmation #1 met head-on rather than quoted: the erasure
factory does not merely guess, it *destroys the evidence that it guessed*.

**So the tid leads at that branch.** The copy runs first, `stamp_list_elem_from_tid(val_node, name)`
runs second: the tid wins when it has an answer, the copy's answer survives when it does not. The
stamper declines by itself for anything it cannot spell faithfully (`deep_tp_from_tid`'s `-1`
sentinel contract; an abstract typevar in a generic body reads as unspellable), so an unrepresentable
inner stays honestly erased rather than being traded for a different fabrication. Both ladder sites —
`emit_let_binding` and `emit_top_level_let` — take it. **This is Stage 3's authority flip, scoped to
one branch**, and the first unit where the flip was not optional: the gated version was not a more
conservative variant of the fix, it was a no-op. The predicate that cannot exist is left as a comment
in `codegen_types` where it would have gone, so it does not get written again.

**Scope split, one row asserting less on purpose.** A `List[Map[Str, List[Int]]]` now recovers its Map
element (`m.len()`, `m.contains_key()` answer right), but reading the map **value** out still fails —
identically with the list annotated, identically with the chain unbroken, and for an `Option` value
too, while a **scalar** map value works. Different axis: the step that reads the element out into a
Map receiver gets the Map's flat key/value pair, and a flat value slot cannot hold the value's own
element (`project_list_of_map_value_type_threading`). Filed as br `m039bn` with those bounds; the test
row asserts what this fix delivers and points there. One red test standing for two causes would have
hidden whichever was fixed second.

**Census: unchanged, again, and again that is a statement about the instrument.** `tydiv` 4823 diverge
rows / 409 cells; `ctypediv` 23 / 7. Both maps diff empty on a 955-file intersected basis. The corpus
contains no unannotated let bound to a call returning a List of compounds, and this ladder branch
carries no `sv_ty_or_flat` tap, so the counter could not have moved in either direction. Two units in
a row have now been found by hand in places the census is blind to — which bounds what "divergence
counter == 0" can mean as a Stage 3 exit criterion: it is zero *over the tapped sites on the corpus we
have*, and the plan's own `feedback_corpus_sweep_is_not_coverage` warning is the reason that is not
the same as done.

### The speller collapse the plan still lists as pending was already delivered (br `qerbc7`)

Stage 3's third bullet reads *"collapse the 5 spellers (`tc_tid_to_c_tag`, `tc_seg_from_tid`,
`tc_tid_inner_tag`, `tc_tid_struct_mono_name`, `tc_tid_tuple_tag`) into one recursive speller. Closes
the open `qerbc7`/`3fc3pn` intent properly."` **Both tickets are `done`, and reading the five
functions confirms the collapse landed — the plan text is stale, not the code.** Recorded here rather
than acted on, because the only way to make the bullet literally true is to undo a distinction two
closed tickets made on purpose.

What the five are today:

| function | line | refs | what it is now |
|---|---:|---:|---|
| `tc_tid_tag_at(tid0, tagpos)` | `typecheck.bl:12501` | 30 | **the one recursive encoder**, `TAGPOS_TOP=0` / `TAGPOS_INNER=1` |
| `tc_tid_to_c_tag(tid)` | `:14182` | 73 | `tag_at(tid, TAGPOS_TOP)` — a positional wrapper |
| `tc_tid_inner_tag(tid)` | `:12701` | 68 | `tag_at(tid, TAGPOS_INNER)` — a positional wrapper |
| `tc_tid_tuple_tag(t)` | `:12705` | 9 | **private**, reached from inside `tag_at` — an arm, not a speller |
| `tc_seg_from_tid(tid)` | `:14565` | 39 | two lines: the `tc_tid_encodable` gate, then `tc_tid_to_c_tag`. Not a grammar — the gate-lift, with an `Option[Str]` contract the encoder cannot express |
| `tc_tid_struct_mono_name(tid)` | `:13819` | 75 | the one genuinely separate **grammar**, and its leaves already route through the encoder |

So three of the five are one function with a position parameter, and a fourth is a two-line
composition of that function with the surviving gate. **Every leaf tag in the compiler is produced by
exactly one place.** That was the whole point of the bullet.

**The fifth is separate on purpose, and the reason is recorded in two places.** `tc_tid_struct_mono_name`
escapes each segment through `escape_mono_seg` and joins with `_0`, not a bare `_` (br `cr4gqk`), and
it answers on **two channels** — `""` meaning *defer to the caller's other path*, and a bare
`BLINK_I0001_*` sentinel it must return **whole** rather than concatenate, because burying it
mid-identifier (`Box_int_BLINK_I0001_…`) puts it past where `diag_is_ice_seg`'s prefix test can see it
(br `vbcw1e`). A position parameter cannot express either. `qerbc7`'s own triage says so verbatim —
*"`tc_tid_struct_mono_name` stays separate (28 call sites, `''` + ICE-sentinel dual return channel a
position param can't express)"* — and br `bwyfy1` had already paid for the general lesson: one shared
**rule** across two positions broke 296 fixtures. One encoder, two positions; never one rule. Its
leaves are not duplicated either: `tc_tid_struct_slot_seg` (`:13867`) recurses for a nested instance
and otherwise calls `tc_tid_encodable` + `tc_tid_to_c_tag`, i.e. the same encoder every other caller
reaches.

**The duplication that does remain is not among the spellers, and it is Stage 4's, not Stage 3's.**
`tc_tid_struct_mono_name`'s own comment names itself *"a NINTH, independent producer of a struct/enum
mono instance's C name"* — the use side — against `mangle_generic_name(base: Str, args: Str)`
(`codegen_types.bl:4889`) on the def side, the two kept byte-matched by hand because a disagreement is
a hard `cc` failure the moment an input contains an underscore (the `bee854` class,
`codegen_types.bl:4668-4675`). They cannot be collapsed into each other while one of them takes its
arguments as a **comma-separated string**: that signature *is* Stage 4 deletion group 4 (`args: Str` /
`ta_str`, exit criterion `rg ta_str src/` reads 0). Collapsing the producers is therefore downstream
of that deletion, and attempting it here would mean writing a second tid-keyed name builder next to
the one that already exists.

Net: the plan's speller bullet is **done**, one item on it is **deliberately excluded** with the
excluding argument on the record, and the residue is re-scoped to Stage 4 group 4 where the blocking
representation actually lives.

### The Map value the trip through a List element could not carry (br `m039bn`)

The scope split that `bef42x` left as a pointer, taken next. Measuring it first changed the
ticket: **half of what the ticket claimed was a different cell**, and the half that was real is a
missing *channel*, not a missing authority.

**The axis is the route, and it is one route.** Each row run, not reasoned about:

```blink
Map[Str, List[Int]] as a plain local     m.get("c").unwrap().len()   WORKS
the same Map out of a List element       m.get("c").unwrap().len()   FAILS
a scalar value out of a List element     m.get("c").unwrap()         WORKS
```

Bound and chained fail identically (so not `6g6g7t`'s axis), annotated and unannotated fail
identically (so not `bef42x`'s), and the Map **element** itself is recovered either way — `m.len()`
and `m.contains_key("c")` answer right. Only the value's own element is gone.

**The ticket's other bound was wrong, and splitting it was the point.** m039bn claimed an
`Option`-valued Map *"FAILS the same way, so it is List and Option alike"*. It does fail — with **no
List anywhere**: a plain local `Map[Str, Option[Int]]` loses its value type, and so does
`Map[Str, Map[Str, Int]]`. A map `ScopeVar` spells its value across **exactly three** flat channels —
`tp_child2_kind` (a scalar value's CT), `sname2` (a struct value's name), `extra` (a **List** value's
element ct), read in that order by `get_map_value_type_raw` (`codegen_types.bl:3876`) — and there is
**no slot for an Option, Map or Result value at all**. That is a value-**kind** cell, not a route
cell, and it is now br `dcjy17`. Asserting it in this test would have tied one red test to two
causes and hidden whichever was fixed second — the same discipline `bef42x` applied when it filed
this ticket.

**Where the route loses it.** `emit_list_method`'s `.get` `CT_MAP` branch spells the Option carrier
`Map_{ktag}_{vtag}`, and `c_type_tag(CT_LIST)` is the element-agnostic `list`. Its `CT_LIST`,
`CT_SET` and `CT_OPTION` siblings each thread the nested element onward **past** that lossy tag
(`set_var_option_inner2`, or `set_var_option_inner_tp` for a deep one). The `CT_MAP` branch threads
the value's **struct** name only (br `mvfd3m`) and has no line for the value's element. The
downstream `.unwrap()` then reads `get_var_option_inner2` — precisely the channel nobody wrote —
and falls back.

**The erasure-factory argument, third sighting, now on the Map value channel.** The fallback is not
"unknown": `set_var(name, CT_MAP)` builds the tp through `sv_tp`, and
`sv_tp(CT_MAP, -1, -1, "")` returns `type_map(type_string(), type_int())`
(`codegen_types.bl:1573`). **A value that was never recorded and a genuine `Map[Str, Int]` are the
same pool state bit for bit** — so, exactly as in `bef42x`, no predicate over the flat fields can
gate a recovery on "the value is missing", and the tid is the only authority that can tell them
apart. Two units apart, on two different channels, the same structural fact.

**So the fix is an authority flip at one branch, plus one thing that is easy to miss.**
`stamp_map_from_tid(node, var_name)` (`codegen_types.bl`, next to its list sibling
`stamp_list_elem_from_tid`) reads the `.unwrap()` node's tid — which holds `Map[Str, List[Int]]`
whole — and writes key, value and, for a List value, the value's element. It is called **last** in
the unwrap `CT_MAP` branch, so the tid wins over all three name-keyed recoveries above it rather
than being clobbered by them.

The part that is load-bearing and not obvious: the four `expr_map_*` globals are **republished from
what the stamp actually wrote**. `emit_map_method`'s head (`codegen_methods.bl:1702`) computes
`let base_val_ct = if !is_named_map_var && fb_val_ct >= 0 { fb_val_ct } else { base_val_ct0 }` — a
**chained** receiver's caller-captured globals *override* the name-keyed lookup. Stamp the var and
leave the globals holding the older answer, and the bound and chained spellings of one shape
disagree. The first draft of this fix put the call at the **top** of the branch and skipped the
republish; both halves of that were wrong for the same reason, and the chained rows are what say so.

**It declines for an Option/Map/Result value, and that is not conservatism.** Those value kinds have
nowhere to be written — the three channels above are the whole vocabulary. Writing the value's CT
with no home for its inner would trade *"a value floored to `Int`"* for *"a value claimed to be an
`Option` of `Int`"*: a different wrong answer, and a louder one. The decline leaves the recoveries
above in charge of what the stamp will not claim, and br `dcjy17` owns the channel.

**Attributed, not assumed.** Each row was compiled with `build/blinkc.bak` — the pre-regen compiler
`task regen` leaves behind — as well as the new one. Non-`Str` keys (`Map[Int, List[Int]]`, which
would otherwise read its key back as `sv_tp`'s fabricated `Str`) and a `List[List[Int]]` value both
failed before and pass now; the **struct** value passed before, on the one channel the `CT_MAP`
branch did thread. That row stays as the bound saying the missing channel was the value's
**element** specifically, not the value. The `List`-of-`List` row also does not claim depth 3 is
solved — `.get(0).unwrap().len()` needs the value's element to be a List, not that element's own
element type; br `f9hgt9` owns the deeper cell.

**And this time the census earned its keep — by flagging a fix that made a second cell worse.**
On the intersected 956-file basis the first version of this fix read 4824 -> 4822 rows and 409 -> 409
cells, with the diff showing one cell **gone** and one cell **arrived**:

```
- site=emit_let_binding.decl  tid=Map[Str, List[Int]]  flat=Map[Str, Int]        (the fixed shape)
+ site=emit_let_binding.decl  tid=Map[Str, Str]        flat=Map[Str, List[Int]]  (new, and not mine to want)
```

The arrival is `let m = o.unwrap()` on an `Option[Map[Str, Str]]` in
`tests/test_option_map_list_ptr.bl` — a shape with **no `List` in it at all**. `task ci` was green and the emitted C for that
file was **byte-identical** between the two compilers, so nothing in the test suite could have
reported it; the counter was the only instrument that saw it.

**The cause is channel priority, and it makes the stamp's correct answer unreachable.**
`get_map_value_type_raw` reads `extra` **first** and answers `CT_LIST` for any non-empty string,
`sname2` second, and `tp_child2_kind` — the only channel that can spell a scalar value — **last**.
Ten lines above the stamp, the branch reads the option's `inner2` slot, gets a stray `0`, and files
it as *"the value is a List whose element is Int"* — `CT_INT` **is** `0`, and it is also that slot's
spelling for *"nothing recorded"* (`codegen_methods.bl:1302`), so the `map_nested >= 0` gate cannot
tell a recorded `Int` element from an absent one. Filed as br `199132`, since the bad write outlives
this fix wherever the stamp declines. The stamp then wrote `(Str, Str)` correctly into
`tp_child2_kind` — the `listelem` tap confirms `val_ct=3` — and `set_map_types` **preserves** `extra`
(37h7n3's re-registration guard, right for a re-registration and wrong for an authoritative
restatement), so every reader still got `CT_LIST` off the stale field. My republish of
`expr_map_val_type` then propagated that answer onto the bound name, which is why a latent wrong
field became a visible wrong shape.

**So an authoritative restatement has to clear what it is not going to write.** `clear_map_value_meta`
empties both side-channels before the stamp writes, because two of the three writes are
**conditional** — a struct name, a list element — and an unconditional write of only one field
cannot displace an earlier guess in the other. With the clear in place **both** rows in that file
disappear: the `Map[Str, List[Int]]` one this unit set out to fix, and the `Map[Str, Str]` one whose
flat state had been wrong since before it. Final census on the same intersected basis: **`tydiv`
4824 -> 4821 rows / 409 -> 408 cells, one cell removed and none added; `ctypediv` 23 rows / 7 cells
unchanged.** The first census movement of
Stage 3 that is not a rounding of the instrument.

Two things worth keeping from that detour. The narrow one: *a channel that is read first can only be
overruled by being cleared*, and the three-channel Map value carrier reads in the order `extra`,
`sname2`, `tp_child2_kind` — so any future tid-led write into that carrier has the same obligation.
The general one: the divergence counter is not only an inventory of work remaining, it is a
**regression detector for the authority flips themselves**, and the thing it caught here was
invisible to 668 passing tests and to a byte-identical diff.

12 rows, 12 green, `task regen` at fixed point, `task ci` 668/668 with 0 fmt failures.

### The Map value kind that had no flat slot at all (br `dcjy17`)

The cell `m039bn` split out, taken next. Measuring it first **widened** it by one value kind and
established that the axis is the value's **kind**, not any route:

| Map value | read back | before |
|---|---|---|
| `Int`, a struct, `List[Int]`, `(Int, Int)` | `.get(k).unwrap()…` | works |
| `Option[Int]` | `.get(k).unwrap().unwrap()` | **fails** |
| `Map[Str, Int]` | `.get(k).unwrap().get(a)` | **fails** |
| `Result[Int, Str]` | `.get(k).unwrap().unwrap()` | **fails** |
| `Set[Int]` | `.get(k).unwrap().contains(2)` | **fails** — not in the ticket, same cause |

A plain local and a call receiver fail identically, and annotated and unannotated fail identically,
which rules out all three neighbouring axes (`bef42x`'s annotation, `6g6g7t`'s expression receiver,
`m039bn`'s trip through a `List` element). The Map itself survives — `m.len()`, `m.contains_key(k)` —
and so does the **outer** `Option` from `.get`: `.is_some()` is right where `.unwrap()` is wrong. The
value is floored *whole*, not partially, which the tap states in one row:

```
site=emit_let_binding.decl var=v tid=Option[Int] flat=Int
```

**Where it went.** `emit_map_method`'s `.get` ladder has arms for struct / `Str` / `List` / `Map` /
`Float` and an else that answers `blink_Option_int`. A Map ScopeVar's flat value channel holds a
scalar (`tp_child2_kind`), a struct name (`sname2`) or a `List` element (`extra`) and has **no slot
for an Option, Result or Set**, so all three land in that else and read back as an integer. The bare
`CT_MAP` arm is the same hole in a second flavour: it emits `blink_Option_map`, whose inner carries
no carrier tag, so the downstream `.unwrap()` — which requires `inner == CT_MAP` **with** a name —
falls through to the same scalar tail.

The **write** side was already correct. `emit_boxed_container_store` boxes an Option value as
`blink_Option_<tag>*` and a Result as `blink_Result_<ok>_<err>*`, exactly as it does for a `List`
element. So the C the map holds was right all along and only the read spelled the wrong carrier —
which is the useful diagnostic shape to recognise: a wrong *reader* over a correct store, not a
wrong store.

**The fix adds no fourth flat channel, and the reason is a small piece of design worth stating
plainly: the value type never had to live on the Map at all.** It only has to reach the `Option`
that `.get` returns, and the tid at the call site holds it whole. `map_val_carrier_from_tid` answers
a carrier — `Option_<tag>` / `Result_<ok>_<err>` / `Map_<k>_<v>` spelled through `tp_carrier_tag`,
or the Set element — and the `.get` arm consumes it **ahead of** the ladder. Nothing downstream
changed: the existing `.unwrap()` arms already decode exactly these carrier tags, because a `List`
element has been carrying compound values this way since `gemr3z`. Four broken value kinds, one new
reader, zero new channels.

Two details in it are load-bearing:

- **The receiver's tid leads, not the call's.** A Map tid names its value *definitionally*;
  `.get`'s own tid says `Option[V]`, and reading `V` back out of it assumes the memo is the call's
  result rather than the value — which would silently strip one `Option` from an Option-valued Map.
  The call node stays as the fallback for a receiver with no memo.
- **Declining has to keep the ladder's answer.** A fabricated carrier tag names a C typedef the
  write side never boxed into, and cc reports that with no Blink span. So the decline contract from
  `deep_tp_from_tid` propagates unchanged: unfaithful tid → `ct = -1` → the flat ladder answers.

**The census did not move, and that is the honest reading rather than a measurement failure.** On
the 957-file intersected basis `tydiv` reads **4826 diverge rows / 411 cells before and after**, and
`ctypediv` **23 rows / 7 cells** before and after. The counter taps ScopeVar-vs-tid disagreement at
`sv_ty_or_flat_at` sites; this fix routes the tid to the **emitter** through a carrier instead of
recording it on a ScopeVar, so the Map var still reads `tid=Map[Str, Option[Int]] flat=Map[Str, Int]`
— ten such rows in the new test file itself. That residual divergence **is** the missing flat
channel, and Stage 4 deletes it when `ScopeVar` becomes `{name, ty, is_mut}`; inventing a channel now
so the counter could tick would be adding to what the plan is about to remove.

So Stage 3's exit accounting needs one qualification it did not have before: **a cell can be closed
without moving the counter when the repair path is a carrier rather than a stamp.** The counter
remains the inventory of flat-field lies; it is not the inventory of user-visible defects, and the
two only coincide where the repair happens to write a ScopeVar. Read together with `m039bn`'s
finding — the counter is also a regression detector for the flips themselves — the instrument is
sound in both directions, and neither direction makes it a completeness measure.

**Byproduct, filed with an MVCE:** br `9qz1k6` — `for pair in m` over an Option/Result-valued Map
declares the pair tuple's value field `void`, so **cc** fails with no Blink span. Same axis, different
position: the map-iteration pair tuple. Scalar, struct, `List`, nested-`Map` and `Set` values all
iterate correctly, and the same maps now read correctly through `.get`, through `m.keys()` + `.get`,
and through `m.values()` — so the gap is one position wide, and it is the position whose failure mode
is the loudest and least helpful of the three (wrong value < honest diagnostic < cc error).

*(Two claims in that paragraph did not survive being measured — the `Set`/`List` values iterate but
lose their element, and `m.values()` needs an annotated receiver. Both are retracted and filed in the
section below; the wording here is left as written so the retraction is visible.)*

18 rows, 18 green (RED first: 19 errors across 12 rows), `task regen` at fixed point, `task ci`
exit 0 with 669/669 test files and 1558 fmt checks passing.

### The same missing name, one position over: the map-iteration pair tuple (br `9qz1k6`)

`dcjy17`'s own byproduct, taken next, and measuring it corrected two claims in the paragraph above —
the paragraph is left as written because being able to see which claims a later measurement retracted
is part of what this map is for:

- a **`Set` value does not fully iterate**. Its pair field is spelled right and `p.1.len()` answers,
  but the element is gone: `p.1.contains(3)` emits `void _mkey9 = (void)(3);` and fails in cc. A
  `List` value has the same hole and it is quieter still — `p.1.get(0).unwrap()` compiles, runs and
  prints **nothing** for `List[Int]`, `<value>` for `List[Pt]`. Filed as br `w224zg`.
- **`m.values()` works only on an annotated or directly-called receiver.** On an unannotated
  `let m = mopt()` the same loop is an `UnresolvedMethod`, while `.get` and `.keys()` on that very
  same variable are correct. Filed as br `nbf7aw`.

**What the pair position actually loses.** The flat value channel records the value's **head** —
`tp_child2_kind` is a `CT_*` and holds `CT_OPTION` happily — but never a carrier **name**, and a
carrier's C type is only nameable *with* its inner (`blink_Option_int`). `c_type_str` therefore has
no arm for a bare `CT_OPTION` and falls through to `"void"`, so the pair tuple is emitted as

```c
typedef struct { const char* _0; void _1; } blink_Tuple2_str_option;
```

which cc rejects (`variable or field '_1' declared void`, then `invalid initializer` at
`blink_Option_int _o = pair._1;`) with no Blink span anywhere. This sharpens `dcjy17`'s statement
rather than repeating it: the nameless head is not "nothing recorded", it is *a kind with no
spelling*, and what each position does with it is what varies. `.get` read it back as an integer
(wrong value); the pair tuple cannot even declare the field (cc).

| Map value | `for p in m` reads | before |
|---|---|---|
| `Int`, a struct, `(Int, Int)` | `p.1`, `p.1.x`, `p.1.0` | works |
| `List[Int]`, `Set[Int]`, `Map[Str, Int]` | `p.1.len()` | works (element lost — br `w224zg`) |
| `Option[Int]`, `Result[Int, Str]` | `p.1.unwrap()` | **fails in cc** |

Both routes fail identically — `for pair in m` and `for (k, v) in m` — and the fix repairs both,
because both are built from the one Tuple2 registration.

**The fix is `dcjy17`'s carrier reader at a second site, and nothing else.**
`map_val_carrier_from_tid` split into a receiver-only entry point (`map_val_carrier_from_recv`) and
the `vtid` half they share; map iteration has no `.get` call node to fall back to, so it reads the
receiver's Map tid and takes the value whole. The carrier **tag** then goes into the pair tuple's
`elem_structs` slot, which is a mechanism that already existed and already worked: a tuple element
whose `elem_structs` slot holds a carrier tag is emitted BY VALUE as `blink_Option_int _1;`, its
typedef pulled in by `emit_carrier_typedef_for_tag`, and `map_pair_value_read_expr`'s struct arm
reads it back as `*(blink_Option_int*)values[i]` — which is exactly what
`emit_boxed_container_store` had been storing all along. `resolve_tuple_ann` has spelled annotated
tuples this way since `qm01e7`, which is why a plain `let t: (Int, Option[Int])` reads `t.1` back
correctly today while map iteration could not.

Three details are load-bearing:

- **Only `CT_OPTION` / `CT_RESULT` are routed through the carrier.** Every other value kind names
  its field correctly, and for a container that field is a *pointer* (`blink_list*`), not a
  by-value carrier — routing them here would replace a working spelling. Their element loss is a
  different repair in a different function (`w224zg`, in the registrar's field tps), and merging the
  two would make neither measurable.
- **The tag is canonicalized, because the other registrar canonicalizes.** An annotated
  `(Str, Option[Int])` anywhere in the program registers the *same* `Tuple2` c_name, and
  `ensure_tuple_type` keeps whichever registration arrives first. Two callers of one c_name that
  disagree on the tag or the type slot mean one shape silently shadows the other — so this path
  matches `resolve_tuple_ann` exactly, including putting the real `CT_OPTION` in the type slot
  rather than the struct convention's `CT_VOID`.
- **Declining keeps the flat spelling**, per `deep_tp_from_tid`'s -1 contract. What must never
  happen again is spelling an absence as `void`: that is the one outcome with no Blink span at all.

**Census, on the 958-file intersected basis:** `tydiv` **4836 diverge rows / 419 cells before and
after**, `ctypediv` **23 / 7** before and after — unmoved, for the reason recorded under `dcjy17`
and now confirmed twice: a carrier-based repair routes the tid to the *emitter* and never writes a
ScopeVar, so the tap at `sv_ty_or_flat_at` sees the same flat-field lie it saw before. (The basis
grew from 957 to 958 with `dcjy17`'s test file, and 4826 + 10 = 4836 / 411 + 8 = 419 reconciles the
two runs exactly — a useful check that the counter is stable and the basis arithmetic is honest.)
The new test file contributes 8 residual rows of its own, all `emit_let_binding.decl` on the Map
var, and one of them is worth reading:

```
site=emit_let_binding.decl var=m tid=Map[Str, Option[Qz16Pt]] flat=Map[Str, Option[Int]]
```

The flat spelling keeps the Option **and** fabricates its inner as `Int` — the head survives, the
inner is invented. That is the whole family in one row, and it is what Stage 4 removes when
`ScopeVar` becomes `{name, ty, is_mut}`.

**Byproducts, each filed with an MVCE:** br `w224zg` (pair-position `List`/`Set` element, silent
wrong value / cc), br `nbf7aw` (`m.values()` on an unannotated let-bound call), br `gkgk1a`
(`List[(Int, Option[Int])]` — every method on it is an `UnresolvedMethod`, while the same tuple as a
plain local works).

19 rows, 19 green (RED first: 3 codegen errors ahead of the cc failures, which never got a chance to
print), `task regen` at fixed point, `task ci` exit 0 with 670/670 test files and fmt 1560 passed /
0 failed.


### The pair's element, and the two levels the ticket was away from it (br `w224zg`)

`9qz1k6`'s byproduct, and the first cell in this project whose repair **writes ScopeVar channels**
rather than routing a tid to one emitter — which is why it was expected to be the first to move the
census, and why the census not moving turned out to say something about the instrument rather than
about the fix (below).

**The ticket named the tuple registrar, and the registrar is not the cause.** The indictment was
`ensure_tuple_type`'s field tps:

```blink
reg_sf_entry(c_name, fname, et, "", sv_tp(et, -1, -1, ""))     // codegen_types.bl
```

`sv_tp(CT_LIST, -1, -1, "")` does fabricate `List[Int]`, and that is a real lie. But it is a
*survivable* one, and one row proves it: an annotated

```blink
let t: (Str, List[W22Pt]) = ("a", [W22Pt { x: 7 }])
```

registers the **same** element-less `Tuple2_str_list` c_name — the tag names no element either — and
`t.1.get(0).unwrap().x` reads back correctly today. It works because `codegen_methods.bl`'s
list-method entry stamps a receiver with no recorded element straight from the tid at `t.1`; the
shared registry entry is never consulted for the element at all. So the registrar's lossiness is
already routed around, and the question is only ever *whether a tid is there to route to*.

**It was not, and the reason was in typecheck.** `typecheck.bl`'s `ForIn` arm gave the loop variable
an element type for a `List` or a `Set` iterable and `TYPE_UNKNOWN` for every other legal iterable —
including a `Map`. So `pair` was `?`, `pair.1` was `?`, `stamp_list_elem_from_tid` declined
(`arm=bail_unnameable`), and the element then came from whatever ambient `expr_list_elem_struct`
happened to hold, which during map iteration is the pair tuple's own tag: `pair.1.get(0)` read a
`blink_Tuple2_str_list*` out of a list of boxed ints.

The fix is one branch, and it says the thing once — a Map's iteration element **is** the interned
`(K, V)` tuple, per `sections/03c_protocols.md`'s `IntoIterator` table:

```blink
} else if iter_tk == TyKind.Map {
    let mt = ty_pool.get(iter_t).unwrap()
    elem_t = make_tuple_type([mt.inner1, mt.inner2])
}
```

**All three rungs of the loudness ladder on one axis.** This is why the cell is worth a row per rung
rather than one representative row — the same lost element, read three ways, produced the best and
the worst diagnostic the compiler has:

| written | before |
|---|---|
| `let l = pair.1; l.get(0)` | `error[UnresolvedMethod] '.get' on type ?` — honest, the best |
| `pair.1.get(0).unwrap()` | **segfault** for `List[Int]`/`List[Str]`, `<value>` for `List[Pt]` |
| `for x in pair.1` | cc: `blink_Option_void`, `void x = …` — **no Blink span**, the worst |

Re-measuring also retracted one of the ticket's two MVCEs: `Set[Int]`'s `contains(3)` does **not**
fail in cc, and neither does `Set[Str]`'s — both polarities discriminate correctly. The ticket's
`void _mkey9` was a different program. Its `List[Int]` MVCE was worse than recorded (segfault, not
"prints nothing"). Both re-measurements are recorded in the test file, because a ticket's stated
symptom is evidence about the past, not about the build in front of you.

**Three edits, and each one is a different kind of gap.**

1. **typecheck's `ForIn`** — above. A missing fact, stated once, and every route reads it.
2. **`codegen_expr.bl`'s tuple-positional read** needed the `CT_LIST` arm next to the `CT_SET` and
   `CT_MAP` arms `jkdywb` had already added. Unlike those two, `List` carries a **global** channel
   (`expr_list_elem_type` / `_struct`) that the let-ladder and the for-loop lowering read, so the
   recovery has to go through `recover_list_elem_from_tid` — the wrapper that writes the globals —
   and not the bare stamp. That is what turns `let l = pair.1` and `for x in pair.1` from the first
   and third rungs into reads.
3. **`emit_for_in`'s `CT_MAP` arm** needed the receiver's tid for two *differently gated* answers,
   which is the whole finding of this cell:

   - The **heads**, for a call receiver only. `for pair in mkm()` has no ScopeVar to key the flat
     channels on, so `get_map_key_type` / `get_map_value_type` answer their **fabricated** defaults
     (`CT_STRING` / `CT_INT` — `sv_tp`'s `CT_MAP` arm) instead of declining, and the pair for a
     `Map[Str, List[Int]]` was built as `Tuple2_str_int`. The gate is the one honest signal the flat
     pool has: `get_map_key_type_raw` / `get_map_value_type_raw` reading **-1**, i.e. no ScopeVar
     under this name at all, so there is no correct answer to override. Where the flat pool *does*
     answer it keeps its spelling — those spellings work, and this cell is not the place to
     re-decide them.
   - The **element**, on every receiver including a plain `Ident`, because the flat pool has no
     channel for it at all: `extra` holds one integer, so it can spell the element's ct and never
     its struct name. That asymmetry is why one answer is gated on the flat pool's silence and the
     other is not.

   This one also produced the cell's most instructive error message. `pair.1.get(0)` off a call
   receiver reported

   ```
   error[UnresolvedMethod]: unresolved method '.get' on type List[Int] in 'main'
   ```

   from codegen's backstop — which prints the **tid-derived** type name. The compiler named the
   right type in the diagnostic while emitting against the wrong one. A diagnostic that reads the
   tid and an emitter that reads the flat fields is the divergence this project exists to remove,
   and here it was visible in one line of output.

**And a fourth thing, found by tracing rather than reasoning.** The `for (k, v) in m` element carry
that both the ticket and the surrounding comment describe as the working hand-written patch has
never run:

```blink
let for_pat_sl = node_elements(node)          // NOT a sublist — it is the pattern NODE
if map_val_nested_ct >= 0 && sublist_length(for_pat_sl) > 1 {
```

`node_elements(<ForIn>)` answers the tuple-pattern node; `emit_tuple_destructure` re-derives the
element sublist from it, which is why passing the node *to it* is correct and why the name was a
lie. `sublist_length` / `sublist_get` were reading a node id as a sublist id, so the measured arity
of `for (k, v) in m` was **1** — and **0** for the next such loop in the same program — and the
`> 1` guard rejected every two-element pattern there is. It looked like it worked because the
element it failed to write was supplied downstream by the `CT_INT` default: right for `List[Int]`,
silently wrong for every other element type. `for (k, v) in (Map[Str, List[Str]])` read a pointer as
an integer and `Map[Str, List[W22Pt]]` rendered as `<value>`, both of which the ticket's own bounds
list recorded and neither of which its cause explained.

Two mutually reinforcing failures produced that: a name that misdescribed a value, and a guard whose
false branch was indistinguishable from success. The `> 1` guard silently skipping is the same
failure mode as `sv_tp` fabricating — a decline that reads as an answer — one level up, in control
flow instead of in data. Filed as br `tdb6en`: `node_elements()` answers a sublist id for some node
kinds and a child node id for others, and nothing in the `Int` return type separates them — the same
argument Stage 0 made for `TyKind`, one level down.

**Census, on the 958-file intersected basis:** `tydiv` **4836 diverge rows / 419 cells before and
after**, `ctypediv` **23 / 7** before and after — the same pair of figures `9qz1k6` published, to the
row.

The prediction at the top of this section — that a repair which *writes ScopeVar channels* would be
the first to move the counter — was wrong, and measuring why is worth more than the prediction was.
It is not the carrier-vs-stamp reason the previous two sections gave. **The counter has exactly one
tap.** Every diverge row in the sweep reports the same site:

```
$ grep -a bucket=diverge sweep.txt | sed 's|.*site=||;s| .*||' | sort | uniq -c
   4860 emit_let_binding.decl
```

`sv_ty_or_flat_at` is called from `src/codegen_stmt.bl:3888` and nowhere else in codegen. The only
other tap in the tree, `copy_list_compound_elem.src`, is reached by six corpus files and answers
`missing` on every one of its 24 occurrences — the source variable has no stamped tid at all — so it
has never been in a position to report a divergence either. A for-in loop
variable is never compared against its tid, so a cell whose whole repair lives in the for-in
lowering cannot move this number no matter how wrong it was — and `w224zg` was wrong in three
distinct ways, one of them a segfault.

Two things follow. The first is that the figure staying **exactly** equal is itself the regression
evidence this cell can offer: 4836/419 before and after means no let declaration's spelling changed,
which is what you want from a fix aimed at a different site. The second is that Stage 3's stated exit
criterion — *drive the divergence counter to 0* — currently reads as **"no let declaration disagrees
with its tid"**, which is a genuine subset of "the tid is authoritative" and not a synonym for it.
Filed as br `7xgbh6`: add a tap per ScopeVar-declaring site (for-in loop and destructured bindings,
fn parameters, match-arm patterns, `with`/`catch` bindings), each with its own site key, and expect
the row count to **rise** when they land. That is the instrument getting honest. Stage 3's exit
should then be stated as zero at every tapped site, with the sites named.

25 rows, 25 green (RED first, and each rung failed in its own way), `task regen` at fixed point,
`task ci` exit 0 with 671/671 test files and fmt 1562 passed / 0 failed.


### The instrument had one tap, and four more declaration sites (br `7xgbh6`)

`w224zg` ended by measuring the instrument instead of the fix, and what it measured is that Stage 3's
exit criterion was reading a single site. This section makes the counter see the other declarations.
It is measurement work, not a repair: no cell is closed here, and the expected direction of the row
count is **up**.

**What a "tap" has to be.** `sv_ty_or_flat_at(name, site, node)` (`typecheck.bl:13007`) compares the
ScopeVar's stamped tid against `sv_tp`'s reconstruction from the flat fields and buckets the answer as
agree / diverge / missing. A declaration that never calls it is invisible: not "agreeing", not
"missing" — absent. Before this sub-step the only codegen caller was `emit_let_binding.decl`
(`codegen_stmt.bl:3888`), so the census answered one question — *does a `let` disagree with its tid* —
and Stage 3's "counter at 0" inherited that scope silently.

Five sites landed, one regen each:

| site key | where | what it measures |
| --- | --- | --- |
| `emit_for_in.var` | `forin_measure_var`, before each of the 8 `emit_block(node_body(node))` in `emit_for_in` | the loop variable |
| `emit_fn_params.param` | `params_measure`, after each of the 4 param registration loops | every parameter of every emitted function |
| `with_resource.bind` | `emit_with_block_core`, after the `w089a0` stamp | the `with X as r` binder |
| `match_pattern.bind` | `pat_measure`, at `bind_pattern_vars`' generic `IdentPattern` arm + its 3 inline carrier fast paths | match-arm pattern binders |
| `tuple_destructure.elem` | `pat_measure_at`, at the end of `emit_tuple_destructure`'s loop | `let (a, b) = t` **and** `for (k, v) in <iterable>` leaves |

Four of the five needed more than a call inserted.

**A parameter carried no tid at all, and the reason names the memo's one writer.** The first probe
reported `summary emit_fn_params.param agree=0 diverge=0 missing=142` — 142 out of 142. `tc_node_tid`
has exactly one writer, `infer_type` (`typecheck.bl:8941`), and `infer_type` is only ever called on
**expressions**. A parameter is a declaration, so nothing ever published its resolved type, and a tap
on it could only ever say `missing`. Fixed on the typecheck side with a publish at the point where
typecheck already knows the answer:

```blink
pub fn tc_publish_node_tid(node: Int, tid: Int)      // typecheck.bl, beside tc_lookup_node_tid
```

called in `tc_check_fn`'s param loop immediately after `nr_define_typed(pname, 0, ptid_final)`. The
tap then read `agree=132 diverge=30 missing=0` — a real comparison at a new position, and the largest
declaring population in the tree, since every mono instance and poly impl re-registers its params.

**The measurement has to substitute through the instance's binds.** Inside a monomorphized body a
`List[T]` parameter or `for x in xs` publishes `T`, and comparing a typevar against a concrete flat
spelling reports a divergence that is only the tap failing to look up what `T` is bound to. Both new
taps therefore run `tc_tid_subst_mono(...)` — and the param tap must use the mono loops' **own local**
`tparams_sl`/`arg_tids`, not the `cg_fn_mono_*` globals (`codegen_types.bl:1428`), because those are
set at `codegen_stmt.bl:8410`/`8770`, *after* the param loops run.

**`with`/`catch` is one site, not two.** The ticket's wording implies a second binder. There is no
catch clause in Blink — `rg Catch src/ast.bl src/parser.bl src/codegen*.bl` finds nothing, because
effects and `Result` carry failure — so the resource binder is the whole family. `w089a0` had already
stamped its tid; stamping is not measuring, which is exactly the blind spot the for-in variable had.

**The pattern family has no binding primitive, but it does have a binding chokepoint.**
`bind_pattern_vars` (`codegen_stmt.bl:1850`) stamps through ~28 `set_var` calls spread over its arms,
which is what makes a tap-per-arm look unavoidable. It is not: every recursed sub-pattern **re-enters
the function** and lands in the generic `NodeKind.IdentPattern` arm, so that arm plus the three
carrier fast paths that handle an IdentPattern inline without recursing are the complete set of
places a binder's name is decided — four insertions, and the tuple/list/variant arms are covered by
the recursion rather than by copies. A tap per arm would measure the same set today and rot tomorrow,
since an arm added later would be silently unmeasured.

The tid again comes from typecheck rather than a second walk. `tc_check_pattern_types` already
decomposes the binding hint one level per arm — Option/Result unwrap, tuple element, list element,
variant field — and now publishes each leaf's answer on the leaf node. Codegen reads that instead of
re-deriving the decomposition, which is precisely the two-copies-of-one-answer mistake `w224zg` was
made of.

One binder family stays unmeasured, and it is unmeasurable rather than skipped: a struct-pattern
shorthand field (`match p { SPt { xs } => ... }`) has no IdentPattern node, and typecheck's
StructPattern arm binds it with a bare `nr_define` — no type at all, unlike every other arm. There is
nothing to compare against. Probing it turned up a live miscompile rather than just a gap:

```blink
type SPt { xs: List[Str] }
match p { SPt { xs } => io.println("{xs.len()} {xs.get(0).unwrap()}") }   // prints: 2 94088795907670
```

Filed as br `1zqq7g`, with both coupled causes named — typecheck binding the field untyped, and
codegen's StructPattern arm setting `ftype`/`fstype` but never the element channels, so `get()` falls
to the `CT_INT` floor.

**A destructured binder is a fifth site, and the ticket said so.** `7xgbh6`'s first bullet reads
"`emit_for_in` loop variable (**and the destructured `k`/`v` bindings**)", and the second half is not
covered by either of the taps that look like it would cover it. A `for (k, v)` head does not route
through `bind_pattern_vars` at all: both it and `let (a, b) = t` go to `emit_tuple_destructure`
(`codegen_stmt.bl:3072`), which is therefore one function holding an entire declaration family. Hence
`pat_measure` split into `pat_measure_at(bind_name, pat, site)` with the site as a parameter — the two
callers share a mechanism but are different declaration families, and collapsing them under one key
would lose the attribution the cell map is read through.

The two callers of that one function do **not** report the same thing, and the asymmetry is the
finding:

| head | leaves carry a tid | bucket |
| --- | --- | --- |
| `for (k, v) in m` | yes — typecheck's ForIn arm knows the element type | real comparison |
| `let (a, b) = t` | no — typecheck never decomposes a LetBinding tuple pattern (br `ksx1q7`) | `missing` |

The tap deliberately does not re-derive the element from the tuple's `struct_name` to close that gap.
A tap that manufactures the answer measures itself, and the `missing` rows are the evidence that
`ksx1q7` is a real hole rather than a cosmetic one.

> Since fixed — the LetBinding arm now decomposes the tuple tid, so the `let` row is a real comparison
> like the for-in one. See *A tuple-pattern binder could not hold a Map* below; the 87 `missing` rows
> this table predicted are 6, and those 6 have a different cause.

The for-in half needed a typecheck change to be measurable at all. The ForIn arm called
`tc_check_pattern_types(pat)` without setting a binding hint, so the walk ran with whatever
`tc_pattern_binding_type` happened to hold from the last pattern checked anywhere — in practice
nothing, so the TuplePattern arm took its `tup_start = -1` path and typed both leaves as untyped. The
arm now sets the hint to the element type around the call and restores it after:

```blink
let tc_saved_pat_hint = tc_pattern_binding_type
tc_pattern_binding_type = elem_t
tc_check_pattern_types(tc_for_pat_node)
tc_pattern_binding_type = tc_saved_pat_hint
```

That is not measurement-only: it gives previously-untyped `for (k, v)` binders a type, so the probe is
asserted by **running** it, and `task ci` is what clears the risk that a newly-typed binder turns a
fail-open into a hard `UnresolvedMethod` on some shape inside `ksx1q7`'s resolver gap.

**The `sv_tp` fabrication hides its own cell, and one element type reveals it.** The param test first
probed `deep(m: Map[Str, List[Int]])` and the row came back `agree`. `sv_tp`'s Map arm fabricates a
missing value element as `Int`, so `Map[Str, List[Int]]` makes the flat side accidentally **right**.
One element over:

```
bucket=diverge site=emit_fn_params.param var=m tid=Map[Str, List[Str]] flat=Map[Str, List[Int]]
```

This is the same coincidence that let `w224zg`'s pair element look like it worked, and it is a
standing hazard for every cell in this census: a fabricated default that happens to match is
indistinguishable from a correct answer. Any probe meant to expose the fabrication must avoid the
fabricated value. The tests carry the note so the next reader does not spend the round rediscovering
it.

**A diverge is not automatically a defect.** The two `emit_for_in.var` diverge rows were checked by
*running* the probe, and its output is correct: the tid names the shape, the flat pair is structurally
incapable of spelling it, and the emitters that matter read the tid. A row where the tid is right and
the flat side cannot represent the answer is **evidence for Stage 4's deletion**, not a cell to
repair. Stage 3's exit therefore has to be stated per site, and this is the restatement it needs:

> Stage 3 exits when the divergence counter reads zero at every tapped site — `emit_let_binding.decl`,
> `emit_for_in.var`, `emit_fn_params.param`, `with_resource.bind`, `match_pattern.bind`,
> `tuple_destructure.elem` — with each remaining diverge row either fixed or recorded as
> flat-side-unrepresentable and scheduled for Stage 4.

The one declaration family still outside that list is the struct-pattern shorthand field, and it is
excluded for a stated reason rather than an oversight: no phase has a type for it (br `1zqq7g`). When
that ticket lands it becomes the sixth site.

**Byproduct: the with-resource binder is stamped with the resource's tid** (br `2cp4qn`), the census
finding above, and the only place in this census where the tid — not the flat pair — is the wrong side.
Latent while the flat fields govern; a field read against the wrong layout the moment Stage 3 flips
authority. The whole site (26 rows / 8 cells) goes to 0 when the stamp reads the impl's `type Context`.

**Byproduct: the comparison calls an equally-unknown child a divergence** (br `dyd8fk`).
`ty_tp_same_shape` rejects on `ct == CT_VOID && k != TyKind.Void`, and `tk_to_ct(Unknown)` *is*
`CT_VOID`, so `tid=Set[?] flat=Set[?]` — both sides equally ignorant, no defect present — counts as a
divergence, 4595 rows of it at the param site alone. This matters to the plan's exit criterion, not
just to the number: **no site whose corpus shapes include an unresolved typevar can reach 0 until the
comparison can say "equally unknown"**, so Stage 3's "counter at 0" needs this fixed first or needs to
be stated as "0 excluding both-unknown". It is an instrument defect, filed rather than fixed here
because changing the comparison mid-census would invalidate every figure in this section.

**Byproduct: `build/blinkc` exits 0 after reporting errors** (br `83ywd6`). MVCE:
`fn main() { let x: Int = "s" }` prints `1 error(s) found` and exits **0**; `build/blink build` and
`build/blink check` both exit 1 on the same file. `src/cli.bl` gets it right, `src/blinkc_main.bl`
does not. It bit this work directly — the first draft of the param test passed `assert_eq(r.exit_code,
0)` on a probe that had a parse error and never reached codegen — so both tap tests now assert
`!out.contains("error[")` instead of trusting the status.

**Byproduct: a Map method does not resolve on a tuple-pattern binder** (br `ksx1q7`), found while
writing the tuple assertion. `match t { (a, b) => a.len() }` over `(Map[Str, Int], Int)` reports
`unresolved method '.len' on type Map[Str, Int]` — the diagnostic names the type correctly, so the
TuplePattern decomposition works and the *method resolver* is what declines; the same call on a plain
local or a `Some(m)` binder resolves. The ticket carries a second, sharper shape: a LetBinding
destructure (`let (a, b) = t`) reports `on type ?` — that path does not decompose the tuple at all.
Reproduced on `build/blinkc.bak`, the generation before the pattern publish, so the tap did not
introduce it.

> Since fixed, and the reading above is wrong on the attribution: the method resolver was never at
> fault. `receiver_type_name_for_diag` spells the receiver off `tc_lookup_node_tid`, which is why the
> diagnostic could name `Map[Str, Int]` while the `ScopeVar` behind it was registered as a struct named
> `Map_str_int`. Two defects in two phases, one symptom — see the ksx1q7 section below.

**Byproduct: `node_elements()` is two functions under one name** (br `tdb6en`), carried over from
`w224zg`: it answers a sublist id for some node kinds and a child node id for others, with nothing in
the `Int` return type to separate them.

**A methodology hazard, recorded because it produced a wrong reading before it was caught.** A corpus
sweep must not overlap a source edit. Compiler-linking test files compile `src/*.bl` from disk, so a
sweep that is running while `src/` changes hits `undefined function` on the files it reaches
afterwards — and because `build/blinkc` exits 0 on error (br `83ywd6`), the sweep records a
*truncated* row set with no failure signal anywhere in it. The intermediate sweep taken that way read
1066 fewer let-site rows and two fewer cells, which looked like a real improvement and was pure
artifact: the affected file's rows had been replaced by two `error[UndefinedFunction]` lines. Both of
this section's control facts — that `83ywd6` matters and that a zero-hit measurement is not evidence
— fired on the same mistake.

**Census, on a 960-file intersected basis** (the only files the two sweeps differ by are this
section's five new test files; `comm -12` on the ` file=` prefixes). The instrument went from one tap
to six, and the count went up by 6.9x:

| site | diverge rows | cells | missing |
| --- | --- | --- | --- |
| `emit_fn_params.param` | 27856 | 167 | 19 |
| `emit_let_binding.decl` | 4895 | 427 | 1 |
| `match_pattern.bind` | 488 | 68 | 20 |
| `emit_for_in.var` | 58 | 27 | 11 |
| `with_resource.bind` | 26 | 8 | 0 |
| `tuple_destructure.elem` | 5 | 4 | 87 |
| **total** | **33328** | **701** | **138** |

Before: 4860 rows / 427 cells, all at `emit_let_binding.decl`.

**The let site did not move, and the +35 rows are one line of my own.** Diffed row-by-row with `at=`
line numbers normalised (my edits shifted every `at=typecheck:NNNNN`, which naively reads as 1143 new
and 1108 gone), the let site gained exactly 35 rows and lost none — all of them
`var=tk tid=TyKind flat=Int` at `typecheck.bl:13565`, i.e. the `let tk = type_kind(iter_t)` in the new
`tc_tid_iter_elem`, once per compiler-linking corpus file. It lands in an existing cell, which is why
cells stayed at **427 exactly**. The contamination guard also passed: the sweep's `error[` population
is identical to the baseline's, 1158 lines with the same 15 kinds in the same counts, so no file was
compiled against a half-edited `src/`.

**The param site's 27856 rows are four classes, and only one of them is a repair list.** Publishing
the number without the split would misread the instrument, since two classes are not defects at all:

| class | rows | example | what it is |
| --- | --- | --- | --- |
| A — codegen special-cases a stdlib struct | 13785 | `tid=Duration flat=Duration` (9190), `tid=Instant flat=Instant` (4595) | `CT_DURATION`/`CT_INSTANT` are dedicated flat ctypes for what typecheck correctly models as an ordinary struct (`pub type Duration { nanos: Int }`). The spellings match; the *representations* do not. Dies with `CT_*` in Stage 4. |
| B — both sides equally unknown | 4595 | `tid=Set[?] flat=Set[?]` | The comparison cannot say "equally ignorant" — br `dyd8fk`. |
| C — fabricated default vs under-determined tid | 8390 | `tid=Map[?, ?] flat=Map[Str, Int]` (5514), `tid=List[?] flat=List[Int]` (2757), `tid=Handle[?] flat=Handle[Int]` (119) | `sv_tp` invents a concrete element the tid does not claim. Both sides wrong; ties to E0301 (`gqg3rk`). |
| D — genuine flat-side loss | ~1086 | enum→`Int` (`TyKind` 286, `TokenKind` 181, `TyDiv` 107, `NodeKind` 35, …), `List[Pollfd] flat=List[Void]` (62), `Map[Str, List[Str]] flat=Map[Str, List[Int]]` (36), `tid=Template[DB] flat=Unknown` (72), `Fn(Request) -> Response flat=Fn(blink_std_http_types_Response(*)(const blink_closure*, …))` | The tid is right and the flat pair cannot hold the answer. |

Class A is worth stating plainly because it is the plan's thesis in miniature: codegen holds a
hard-coded ctype for a stdlib struct, so the same type has two representations and the counter can
see it. Class B is the one that blocks the exit criterion arithmetically rather than by any codegen
defect, which is why it went to a ticket instead of into this list.

**`match_pattern.bind`'s 488 rows are dominated by the fail-open floor**, which is the same shape
`1zqq7g` names one arm over: `tid=Pollfd flat=Int` (124), `tid=AstNode flat=Int` (70),
`tid=Box[Int] flat=Int` (12), `tid=UserRow flat=Int` (8) — a variant-payload binder whose flat ctype
is `CT_INT` while the tid names the struct. Those are Stage 3 repair cells, and the tid is the correct
side of each. A smaller group is unsubstituted typevars (`tid=T flat=Int`, `tid=P flat=Int`,
`tid=L`/`tid=R`), which belong with class B.

**`with_resource.bind` turned out to be a bug, and the only one in this census where the TID is the
wrong side.** All 26 rows / 8 cells are one defect: `emit_with_block_core` stamps
`tc_lookup_node_tid(item)` — the *resource* expression — but a `BlockHandler`'s binder is what
`enter()` returns, i.e. the impl's `type Context`. Minimal repro:

```blink
type Conn { id: Int }
type Tx { tag: Str }
impl BlockHandler for Conn {
    type Context = Tx
    fn enter(self) -> Tx { Tx { tag: "t" } }
    fn exit(self, _ok: Bool) { }
}
fn main() { with Conn { id: 1 } as ctx { io.println(ctx.tag) } }   // prints `t`
```
```
bucket=diverge site=with_resource.bind var=ctx tid=Conn flat=Tx
```

The binder really is a `Tx` — it runs, and `ctx.tag` resolves — so the flat side is right and the tid
is wrong. Harmless while the flat fields govern; a miscompile the moment Stage 3 flips authority,
because a field read would be resolved against the resource's layout. Filed as br `2cp4qn`, and the
whole site goes to 0 when the stamp reads the Context. Finding this is the clearest argument for the
ticket: a tap that only counted rows would have reported 26 harmless divergences.

**`tuple_destructure.elem` reports 5 diverge and 87 missing**, and the ratio is the point rather than
a shortfall: the diverge rows are for-in leaves the tid can spell and the flat pair cannot
(`tid=List[Str] flat=List[Int]`, `tid=Set[Str] flat=Set[?]`, `tid=List[W22Pt] flat=List[Int]`,
`tid=(Int, Str) flat=Tuple2_int_str`), and the 87 missing rows are `let (a, b) = t` binders that carry
no tid because typecheck does not decompose a LetBinding tuple pattern at all (br `ksx1q7`). The
missing bucket is that ticket's corpus-wide size.

> That prediction held: closing `ksx1q7` took the site to 97 agree / 18 diverge / 6 missing, and the 6
> that remain are `.enumerate()` / `.zip()` heads with no return type at all, not `let` binders.

21 rows, 21 green across five test files, `task regen` at fixed point for each sub-step, `task ci`
exit 0 with 676/676 test files and fmt 1572 passed / 0 failed.


## The one cell where the tid was the wrong side (br `2cp4qn`)

Taken next because the census found it, which is the whole argument for having built the census: the
row was not remarkable — 26 of 33328 — and reading it was.

`with <resource> as name` does not always bind the resource. For a `Closeable` it does, which is why
this held for as long as it did. For a `BlockHandler` the block sees what `enter()` returns, whose type
the impl declares as `type Context`. Both phases bound the resource unconditionally:

| phase | site | what it bound |
| --- | --- | --- |
| typecheck | `tc_bind_with_resource` | `nr_define_typed(node_name(item), 0, res_tid)` |
| codegen | `emit_with_block_core` | `set_var_ty(binding, tc_lookup_node_tid(item))` |

**The severity in the ticket was wrong, and probing is what corrected it.** The ticket said harmless
today because the flat fields govern. The flat fields *are* right — `emit_bh_setup` registers the
binder with the Context type — so the emitted C is correct and nothing looked broken. But typecheck
resolves field reads against the type bound to the *name*, and that was the resource:

| probe | result | what it establishes |
| --- | --- | --- |
| `ctx.id` in an interpolation (resource-only field) | prints `<value>` | **not** decisive — `ctx.nope`, absent from *both* types, also prints `<value>`. That is the generic interpolation fail-open, not this defect. |
| `let bad: Int = ctx.id` | escapes to `cc`: `'blink_Tx' has no member named 'id'` | typecheck admitted a resource-only field |
| `let bad: Str = ctx.id` | `error[TypeError]: declared type Str but got Int` | **decisive** — not fail-open. Typecheck *positively believed* `ctx` was a `Conn` and resolved `Conn.id` to `Int`. |
| `Conn { tag: Int }` + `Tx { tag: Str }`, `let v: Int = ctx.tag` | prints `ctx` | **silent miscompile.** A variable annotated `Int` holds a `Str`. |

The last row is the ticket's real severity and it needed the field *name* to collide: distinct names
only ever produce a `cc` escape, a shared name at differing types produces a wrong **value**, with no
diagnostic and no `cc` error. So the fix belongs on the typecheck side — fixing only codegen's stamp
would have left every one of those four rows exactly as it was.

**The comment above the stamp was also wrong**, and it is worth recording because it is the kind of
error that hides a defect for a release. It read *"a no-op on the BlockHandler path, where `set_var_ty`
finds no scope var to stamp."* `emit_bh_setup` registers the binder fifteen lines earlier
(`codegen_stmt.bl:4856`, `set_var` + `set_var_struct` with the Context type), so the stamp landed and
overwrote the correct Context with the resource. A comment asserting a no-op is a claim, and this one
was never measured.

**The fix names one concept once.** `nr_bh_context` maps resource type name → Context type name, filled
in the same Phase-1 impl walk that already fills the method registry (that loop holds both the impl node
and its trait name). The Context is stored as a *name* and resolved to a tid on demand, because Phase 1
runs before a struct declared after the impl is interned. `tc_with_binder_tid(res_tid)` answers "what
does `with <resource> as name` bind", and is conservative by construction: a non-nominal resource, an
impl with no Context, or a Context naming a type that does not resolve all fall back to the resource
tid — exactly what every caller got before. `tc_bind_with_resource` then publishes the **binder's** tid
on the node rather than the resource's, and codegen needed no change at all beyond the corrected
comment, because its one consumer reads that node.

**The staleness guard caught the new registry, which is worth recording as a working net.**
`tests/test_reset_staleness.bl` asserts every mutable global in `typecheck.bl` is either reset in
`init_types()` or explicitly allowlisted, and `task ci` failed on exactly that — `1 variable(s) not in
init_types() or allowlist: nr_bh_context` — with 676/677 otherwise green. `nr_bh_context` belongs in the
allowlist beside `nr_impl_type_names` and `nr_impl_method_names` for the same reason they are there: all
three are filled by one Phase-1 impl walk and cleared together at the top of `resolve_names`, so they
are per-pass by construction. A cross-compilation leak here would have been a real defect (one file's
handler Contexts visible to the next), and the guard is what makes that a caught error rather than a
future ticket.

**`Context = Void` is a fall-back, not a carve-out.** Both stdlib `BlockHandler` impls declare it —
`db_sqlite`'s `Transaction` and `testing`'s `Cleanup` — because `enter()` returns nothing and the form
is `with sqlite_transaction(h) { … }` with no `as` clause at all. A `Void` Context rebinds nothing, so
`tc_with_binder_tid` returns the resource tid for it and every existing stdlib user is bit-identical.
That the *other* spelling is broken is a separate defect, filed rather than papered over: `with X as
name` on a `Void` Context emits `void name = enter(…)`, which is not valid C, and `emit_bh_setup`'s
guard admits it because it tests whether the assoc type is *named* and `"Void"` is a name (br `ybw41a`).

**Two witnesses were already in the tree and both passed for the wrong reason.**
`tests/test_block_handler.bl` runs `with make_timer(..) as elapsed { assert_eq(elapsed, 0) }` where
`Timer`'s Context is `Int`, and `with make_conn(2) as tx { tx.conn_id }` where `Connection`'s Context is
`Transaction`. Before the fix `elapsed` was typed `Timer`, so `assert_eq(elapsed, 0)` compared a struct
against `0` and passed anyway. Those tests pass either way, which is exactly why the defect survived —
a test that passes for the wrong reason is not coverage, and `feedback_self_host_doesnt_catch_user_
codegen_bugs` is the same lesson one level up.

Byproducts: `ybw41a` above, and `25e2wr` — a **false positive** found writing `ybw41a`'s MVCE: a bare
`fn enter(self)` is rejected against a trait method declared `-> Void`, because the contract check
compares return-type *spellings* and `''` is not `'Void'`. Asymmetric inside a single impl: `exit`'s
trait signature is bare, so only `enter` fails.

`tests/test_2cp4qn_with_resource_context_tid.bl`, 5 tests, RED first in three distinct ways — no
`TypeError`, the miscompiled `ctx` output, and the census row `var=ctx tid=Conn flat=Tx` — with two
controls green from the start: a Context-typed read already worked, and a `Closeable` binder already
agreed. The `Closeable` control is the one that bounds the change, asserting the type is swapped only
for handlers that actually rebind. `task regen` at fixed point, `task ci` exit 0.

**One guard is forward-looking and says so.** A generic handler's `type Context = T` resolves to a
typevar outside the binding instance, and swapping a concrete resource tid for an unbound one trades a
wrong answer for *no* answer, which is worse for every downstream consumer. `tc_with_binder_tid` therefore
falls back to the resource tid on `TyKind.Typevar` and `TyKind.Unknown`. No generic `BlockHandler` impl
exists in the tree, so this guards a shape rather than a live case — recorded here so it is not later
read as a fix for something that was measured.

### The site did not reach 0, and the survivor is the *other* side

On the 960-file intersected basis, `with_resource.bind` went **26 rows / 8 cells → 11 rows / 1 cell**,
with **zero new cells anywhere in the corpus**. The seven that closed are every cell where the tid was
wrong: `tid=Timer flat=Int`, `tid=Connection flat=Transaction`, `tid=ApTx`/`CtxTx`/`Inner`/`Outer`/`Probe`
`flat=Int`. The prediction that the site would reach 0 was wrong, and the survivor is worth more than the
seven:

    site=with_resource.bind  tid=Connection flat=Int   × 11

Here the **tid is right and the flat is wrong** — the inverse of the ticket. All 11 rows are the
`with <expr>? as name` form, and probing found the flat pair internally inconsistent: `ctype=CT_INT`
alongside `sname=Conn`. The struct *name* being right is why it hid — field reads, method calls, passing
the binder as an argument, a plain copy and the Display gate all behave, and the emitted declaration is
correct because `c_decl` comes from `c_type_c_name(res_struct)`. Only a consumer that dispatches on the
**ctype** breaks, and then it breaks hard:

    let l: List[Conn] = [c]
    →  error: aggregate value used where an integer was expected
           blink_list_push(_l1, (void*)(intptr_t)c);

**And it is not a `with` bug at all.** The same list literal fails identically after a plain
`let c = connect()?`, and passes with the `?` removed in both shapes. So the cause is whatever publishes
`expr_result_type` for the Try expression; the with-resource binder merely inherits it at
`set_var(binding, res_type, 0)`. The census names both binding sites with one signature, third row
included:

    site=emit_let_binding.decl  var=c  tid=Conn        flat=Int
    site=with_resource.bind     var=c  tid=Conn        flat=Int
    site=emit_let_binding.decl  var=l  tid=List[Conn]  flat=List[Void]   ← the erasure cascading

The third row *is* the `cc` error: the list erased its element because its source variable claimed to be
an `Int`. Filed as br `8nqdx4` with the plain-`let` MVCE, since that is the smaller reproduction and
fixing the publisher covers both sites. The three tests that carry those 11 rows
(`test_schfpd_with_qmark_binding.bl`, `test_fmt_iife_with_block.bl`,
`test_promote_fwd_decl_ordering.bl`) pass today only because none of them puts the binder in a container.

**The counter is not monotone under its own fixes.** Corpus diverge rows went 33328 → **33348**, up 20,
while the defect was being removed: −15 from the fix and **+35 from the fix's own source**. Every one of
those 35 is `var=ctx_kind tid=TyKind flat=Int at=typecheck:11314`, the new guard's own `let`, counted once
per compiler-linking file in the corpus, landing on the already-documented family-D enum-let cell — which
is why cells did not move. Stage 3's exit criterion is stated as "the counter at 0", and this is the
arithmetic that criterion has to survive: writing compiler source *adds rows*, so the honest reading of
progress is **cells**, per site, on a fixed basis. Rows measure how much of the corpus links the
compiler.

## The instrument could not say "clean" (br `dyd8fk`)

Every cell above is a codegen defect. This one is a defect in the *measuring device*, and it is the
reason to stop and fix it mid-stage: Stage 3's exit criterion is "the divergence counter at 0", and the
comparison the counter is read through could not return 0 for any site holding an under-determined type,
no matter how correct codegen became.

`ty_tp_same_shape` opened with

    let ct = tk_to_ct(k)
    if ct == CT_VOID && k != TyKind.Void { return 0 }

and `tk_to_ct` maps `TyKind.Unknown` onto `CT_VOID`. So a tid whose child is an unbound metavar answered
"different" — including when the flat child was *identically* unbound. Both sides render `?`. They agree,
and what they agree about is that the element is not yet known. There was nothing in either
representation to repair.

### The population is one cell, and it is one impl block

    site=emit_fn_params.param  var=self  tid=Set[?]  flat=Set[?]     4595 rows / 919 files

Every row is a `self` param of `impl SetPure for Set` and `impl Sized for Set` in `lib/std/set.bl:23-33`
— five methods, at `std_set:24,25,26,30,31`. Those impls are written on the un-parameterized `Set`, so
the element is genuinely unknown at emit time and the flat slot was never filled. The rows appear in any
program that links the stdlib, which is why the test's probe is `fn main() { io.println("x") }`: it
declares nothing at all and still produces them.

### "Both unknown means agree" is the wrong fix

Folding these into `agree` would answer the exit criterion by *hiding* the population, and the population
is the thing `gqg3rk`'s metavar work is measured by. It is a fourth bucket — `TyDiv.Unknown` — visible in
every `summary` line, conflated with nothing. The published Stage-2 basis format therefore now carries a
fourth field, appended last so older sweeps stay diffable:

    summary <site> agree=N diverge=N missing=N unknown=N

And the comparison itself became tri-state, because a bucket needs three answers to feed it:

    type TyShape { Same, Differ, Ignorance }

Ignorance propagates upward but **loses to `Differ`**: `Set[?]` against `Set[?]` is Ignorance, while
`Map[Str, ?]` against `Map[Int, ?]` is a divergence. A parent cannot be cleaner than its worst child, and
one honest unknown child does not excuse a sibling that disagrees.

### The guard keys on the kind, not on the ctype

The tempting one-line version — treat `CT_VOID` as a wildcard — would have buried two neighbouring
classes, and both are now pinned by controls in the tests:

* `tid=Set[Int] flat=Set[?]` — the tid knows the element and the flat slot erased it. The whole class is
  **14 rows across 9 cells** corpus-wide, and the exact shape the ticket names is a **single row**
  (`at=__main__:55`, one test). A wildcard would silently absorb precisely the findings this census exists
  to surface: `tid=Map[Str, Set[Int]] flat=Map[Str, Set[?]]` (4 rows) and
  `tid=Set[Int] flat=Set[Set[?]]` (1) are in that 14.
* `tid=Fn(Int) -> Int` — `TyKind.Fn`, `Closure`, `Tuple` and `Typevar` all collapse onto `CT_VOID` in
  `tk_to_ct` as well, but that is not ignorance: those types are fully determined and the flat universe
  simply cannot spell them. Still a divergence.

So the test is `k == TyKind.Unknown`, placed *before* the erased-slot guard, and never
`tk_to_ct(k) == CT_VOID`.

`tc_unknown_tid()` is exported for one reason: the unit tests have to be able to *construct* an
under-determined type to assert the bucket. The global stays private — a test that could assign it could
invalidate the pool.

### Measured result — the movement is 1:1, and the two sites that moved are named

On the 960-file common basis, exactly two sites changed and the arithmetic closes with no remainder:

    emit_fn_params.param   agree=229688  diverge=27856 -> 23261   unknown=0 -> 4595
    emit_let_binding.decl  agree=416298 -> 416300  diverge=4930 -> 5035

The first line is the fix: **−4595 diverge, +4595 unknown, agree untouched**. Not one row moved into or
out of `agree`, which is the property that makes the new bucket a reclassification rather than an
amnesty. Corpus-wide diverge goes 33348 → 28858 and cells stay at 694: one cell removed
(`tid=Set[?] flat=Set[?]`), one added.

The added cell is the fix's own source, again. `emit_let_binding.decl` gains 105 rows = **3 new
enum-typed `let`s × 35 compiler-linking files** — `worst` at `typecheck:13121`, `c` at `:13123`, `shape`
at `:13163` — all landing on the already-documented family-D `tid=<Enum> flat=Int` class, which is why
the cell count did not rise by more than the one new spelling `TyShape`. The `+2 agree` is the two new
`let`s in `tests/test_stage2_ty_divergence.bl`, which links the compiler and is in the basis. Every row
of the delta is accounted for by name.

That is the second consecutive measurement in this stage where fixing a cell *raised* the row count. It
is not noise and it does not need suppressing: rows measure how much of the corpus links the compiler,
cells measure the work.

### Why the test runs `blinkc` instead of asserting on emitted C

The rows are stdlib `self` params, so no emitted C changes at all — this fix moves an integer between two
counters and nothing else. The witness has to be the instrument's own output, so
`tests/test_dyd8fk_both_unknown_not_divergence.bl` runs `env BLINK_TRACE_CHANNELS=tydiv build/blinkc` over
three probe programs and reads the rows: the ticket's row absent from `bucket=diverge`, present under
`bucket=unknown` with `summary ... unknown=` a *number greater than zero* (a substring match would pass on
a bucket that exists and is never reached), and the two controls still diverging. The four unit tests in
`tests/test_stage2_ty_divergence.bl` cover the same four classes at the `sv_ty_or_flat` level, where the
types can be built by hand instead of coaxed out of the stdlib.

Stage 0's exhaustiveness net did its job here without being asked: adding the fourth `TyDiv` variant made
the compiler name the three-arm `match` in the test file. That is the whole reason the enum came first.

## A tuple-pattern binder could not hold a Map, or a container element (br `ksx1q7`, br `v71vxv`)

Taken next because it is the only remaining ticket that closes two census cell families with one
change, and because both families were the *large* remainder at their sites: 87 of 121 rows at
`tuple_destructure.elem` and 20 at `match_pattern.bind`. It also turned out to be two defects in two
phases wearing one symptom, which is why the ticket had sat as "the diagnostic names the type, so the
*method resolver* declines" — a reading that was wrong about which component was at fault.

### The symptom named the type it could not dispatch

```
error[UnresolvedMethod]: unresolved method '.len' on type Map[Str, Int] in 'main'    ← match / for-in
error[UnresolvedMethod]: unresolved method '.len' on type ?      in 'main'           ← let
```

Two different messages for what looks like one program shape, and the pair is the whole diagnosis.
The trailing `in '<fn>'` is the tell: there are two `UNRESOLVED_METHOD` emitters and only the
**codegen** one (`src/codegen_methods.bl:5590`) appends the enclosing function name; typecheck's
(`src/typecheck.bl:10199`) does not. So typecheck was content with both programs and codegen refused
both — and `receiver_type_name_for_diag` reads `tc_lookup_node_tid(obj_node)`, which is why the
message could spell `Map[Str, Int]` correctly *while dispatch failed*. The type was in hand at the
moment of the error. Nothing was missing except codegen's willingness to read it.

**`blink check` said `ok` for both MVCEs, exit 0.** That is not a mistake in the probe, it is the
localization: `cmd_check` (`src/cli.bl:2327`) runs `compile_to_program` + `check_types` +
`check_unused_imports` + `analyze_escapes` and never enters codegen, so every codegen-emitted
diagnostic is invisible to it. Filed as br `dcchwn` — a green `check` followed by a red `build` is
worse than no check, and this is the second time in this project that a status code meant something
other than what it looked like (br `83ywd6` is the first).

### Half one: typecheck defined every `let` tuple leaf as Unknown

`src/typecheck.bl`, the LetBinding arm of `tc_check_body`, three lines below where it computes and
publishes the tuple's own tid:

```blink
nr_define_typed(node_name(tsp), is_mut, TYPE_UNKNOWN)
```

Unconditional, for every leaf. So `let (m, n) = t` bound two variables of no type at all, and the
`on type ?` message is that line rendered. The for-in and match spellings of the same destructure go
through `tc_check_pattern_types`, whose `TuplePattern` arm **does** decompose the hint — so only
`let` was uncovered, and `tests/test_7xgbh6_tuple_destructure_divergence_tap.bl`'s asymmetry table
had already recorded exactly that without naming it a typecheck bug.

The fix decomposes `final_tid` in place, through the Stage-1 accessors:

```blink
let tc_let_tup = tc_tid_resolved(final_tid)
let mut tc_let_arity = -1
if tc_tid_kind(tc_let_tup) == TyKind.Tuple { tc_let_arity = tc_tid_child_count(tc_let_tup) }
```

then `tc_tid_child(tc_let_tup, tpi)` per leaf, with `nr_define_typed` **and**
`tc_publish_node_tid(tsp, …)` so codegen reads it from the same memo it reads inferred types from.

Two details are load-bearing:

* **Not delegated to `tc_check_pattern_types`.** Its `IdentPattern` arm hard-codes
  `nr_define_typed(name, 0, tc_pattern_binding_type)` — the `0` is `is_mut`. Reusing it would have
  taken `mut` away from every destructured binder, and `let mut (m, n) = t` followed by `m.insert(…)`
  works today. That row is in the test.
* **A leaf past the tuple's arity stays Unknown.** Not clamped to the last child, not borrowed from a
  neighbour. Wrong-arity destructuring is diagnosed elsewhere; shifting a type into it would convert
  that error into a miscompile — the same argument written on `tc_tid_child` for why it answers `-1`
  rather than a plausible default.

### Half two: codegen's binders decode two tags, and a Map is not one of them

The flat side cannot express this element *at all*, and the erasure is at
`src/codegen_types.bl:6425`, in the tuple typedef's field registration:

```blink
if es != "" {
    reg_sf_entry(c_name, fname, CT_VOID, es, sv_tp(CT_VOID, -1, -1, es))
} else {
    reg_sf_entry(c_name, fname, et, "", sv_tp(et, -1, -1, ""))
}
```

Any element with a compound tag has its real `CT_*` replaced by `CT_VOID` and its tag moved into the
**struct-name** slot. Both binder sites then sniff that slot for a prefix — `Option_`, `Result_`, and
nothing else (`bind_pattern_vars`' IdentPattern arm and `emit_tuple_destructure`, byte-identical
chains) — so a `Map_str_int` tag falls to the generic branch and the variable is registered as a
struct of that name. `lookup_impl_method("Map_str_int", "len")` then misses, because Map's impls
register under the bare head `Map`.

**The emitted C was already correct**, which is worth stating because it bounds the fix:

```c
blink_map* mp = _scrut_1._0;
int64_t     n = _scrut_1._1;
```

`c_type_c_name("Map_str_int")` is `blink_map*`. Only the `ScopeVar` registration was wrong. So the
change is `set_var` and the Map channels, and not one byte of emission.

`stamp_map_binder_from_tid` (`src/codegen_types.bl`) leads at both sites, ahead of the tag chain
rather than beside it:

```blink
if !stamp_map_binder_from_tid(pat, bind_name, 1) {
    …the existing Option_/Result_/struct chain, unchanged…
}
```

**No `Map_` arm was added, deliberately.** A third `starts_with` arm would have to parse a key and a
value back out of a string that does not carry them — `Map[Str, Map[Int, Bool]]` tags as
`Map_str_map` — and the chain is flat-universe machinery Stage 4 deletes. The tid holds the whole
shape at depth, so the tid is read.

### Where the new helper deliberately differs from `stamp_map_from_tid`

On one point: **an unholdable value does not abandon the key.**

`stamp_map_from_tid` answers a single yes/no — "are both channels mine?" — and declines wholesale
when the value is a kind the Map's three flat channels cannot hold (an Option, Result, Set or nested
Map value; br `dcjy17`). That contract is right for its one caller, which keeps its own recoveries
for the value. A binder has no recoveries, and declining there would have produced this:

```blink
let m: Map[Str, Option[Int]] = Map()      // compiles and runs today
let (m2, n) = (m, 2)                      // …would still error on m2.len()
```

The same map, held under a plain name and under a destructured one, with two different answers. That
is an inconsistency, not caution. So the binder stamps the key unconditionally — the key selects the
kops vtable, and an unstamped key is a `BLINK_COMPILER_BUG_kops_unsupported` at the first insert,
not a floor — and leaves the value at whatever the flat channels already held. Measured parity, both
spellings, including `.get`:

```
declared: len=1  has=true  get=some
bound:    len=1  has=true  get=some
```

The test asserts that as **equality between the two programs**, not as the literal expected output.
Asserting the bound program's output alone would freeze whatever `dcjy17` currently answers into a
second place; equality means a later fix to the value channel drags the binder along and cannot be
applied to one spelling only.

### Measured result — 89 rows cleared, 13 rows became *visible*, and the arithmetic closes

Monolithic sweep, 967-file common basis (`comm -12` of both sweeps' file sets):

| site | agree | diverge | missing |
| --- | --- | --- | --- |
| `tuple_destructure.elem` before | 29 | 5 | 87 |
| `tuple_destructure.elem` after | **97** | **18** | **6** |
| `match_pattern.bind` before | 9622 | 488 | 20 |
| `match_pattern.bind` after | **9630** | **488** | **12** |

−81 missing at `tuple_destructure.elem` = +68 agree +13 diverge, exactly. All **5** pre-existing
diverge rows survive unchanged (`comm -23` of the two row sets is empty), so nothing was masked to
buy the improvement. At `match_pattern.bind`, −8 missing / +8 agree with diverge untouched. Every
other site in the corpus is unchanged except two that gained `agree` rows only
(`emit_fn_params.param` +105, `emit_let_binding.decl` +210, no new diverge or missing anywhere).

**The +13 diverge rows are the instrument gaining sight, not the fix losing ground.** They were
`missing` because the leaf had no tid; there was nothing to compare. Now there is, and they
disagree — but codegen's treatment of those shapes did not change (the stamp fires only for
`CT_MAP`) and all of them run green in `task ci`. Their attribution:

* **12 rows, family E** — same spelling on both sides, differing `CT_*`: `tid=Option[Cmd]
  flat=Option[Cmd]`, `tid=Cmd flat=Cmd` (`test_tuple_bare_none.bl`,
  `test_tuple_option_user_enum.bl`, `test_8vnjrm_tuple_enum_element_carrier.bl`,
  `test_295z9x_generic_tuple_option_enum_return.bl`). A user enum registered through the
  struct-name slot, so the flat CT is struct-shaped where the tid says `Enum`. Family E's published
  disposition is *resolved by construction* — they clear when Stage 4 deletes the CT split.
* **1 row, family F** — `tid=Option[Cmd] flat=Option[test_295z9x_generic_tuple_option_body_helper_Cmd]`:
  the flat side carries the mono-mangled *physical* name where the tid carries the logical one. Same
  type, two namespaces (`feedback_module_vs_c_prefix`). Family F is per-cell triage in Stage 3.

### The residual is 18 rows, and none of them are this ticket

Attributed individually rather than left as a remainder:

* **6 rows, `tuple_destructure.elem`, all `test_44xww4_enumerate_zip_compound.bl`** — `for (i, x) in
  a.enumerate()` / `for (a, b) in x.zip(y)`. Typecheck has **no return type for either adapter**:
  `enumerate` and `zip` appear in `is_builtin_method`'s name list (`src/typecheck.bl:6507`) and
  nowhere else in the file, so `infer_type` answers Unknown, the ForIn hint is `-1`, and
  `tc_check_pattern_types`' TuplePattern arm takes its `tup_start = -1` path. Reproduced standalone:
  the loop *runs correctly* (the flat side handles it) while the loop variable itself reports
  `bucket=missing site=emit_for_in.var var=_tuple`. Same root as the 11 open `emit_for_in.var` rows,
  and it is upstream of any binder — br `44xww4` is closed and was about the codegen materializer,
  not about typing the pair.
* **8 rows, `match_pattern.bind`, `test_j0cdey_hof_list_compound.bl`** — `Some(v)` / `Err(_e)`
  payload binders inside a closure passed as a method argument (`c.map(fn(x: Option[Int]) -> Int {
  match x { … } })`). The closure body is never typecheck-walked in that position, so nothing inside
  it carries a tid: br `1hg8b6`, already open with this exact cause.
* **4 rows, `match_pattern.bind`, `test_yb3a4z_tuple_lit_option_element.bl`** — `var=e` only, never
  `var=v`, from `match (Ok(3), 9) { (a, n) => … match a { Ok(v) => v  Err(e) => 0 } }`. A bare
  `Ok(3)` leaves the error type under-determined, so the `Err` binder has genuinely nothing to be
  typed as. That is br `8vcj2c`/`gqg3rk`'s E0301 population, and the fact that `v` cleared while `e`
  did not is the confirmation.

### A second-order confirmation nobody asked for

The 8 rows that cleared at `match_pattern.bind` are not tuple leaves at all — they are `v`, `e`,
`_v`, `_e` in `tests/test_tuple_result_destructure.bl`: `let (a, b) = t` where `a` is a `Result`,
followed by `match a { Ok(v) => …  Err(e) => … }`. Typing the *leaf* gave the inner match a
scrutinee type, which gave its payload binders theirs. One typecheck line, two sites.

### The rest of this defect class — br `v71vxv`, and a retraction of what this section first said

The Map arm fixed one shape. Sibling shapes found by hand after the fix, all through the same
binders, in the let / match-arm / for-in forms alike:

```
List[Str]           -> 943501557530581   (correct: a1)   SILENT
List[(Int, Str)]    -> <value>1          (correct: a1)   SILENT
List[List[Int]]     -> error[UnresolvedMethod] .len/.get on type List[Int]
List[Map[Str,Int]]  -> error[UnresolvedMethod] .len/.get on type Map[Str, Int]
List[Option[Int]]   -> error[UnresolvedMethod] .unwrap on type Option[Int]
List[Set[Int]]      -> error[UnresolvedMethod] .len/.contains on type Set[Int]
```

The outer CT is right and no binder site called `stamp_list_elem_from_tid`, so the inner read
decoded against `sv_tp`'s fabrication. The two silent rows are the severe half: `List[Int]` passes
only because the fabrication happens to be right, and `List[Str]` is the same cell one element over,
where the emitted C reads a `const char*` slot as `int64_t`.

> **Retraction — this section originally claimed the instrument could not see any of it, and that
> claim was wrong twice over.**
>
> It cited a `StringBuilder` element losing `CT_STRINGBUILDER` while the tap read
> `summary tuple_destructure.elem agree=2 diverge=0 missing=0`, and concluded *"Stage 3's exit gate
> would not have scheduled any of them, so the ticket is the schedule."*
>
> The probe was invalid: it called `sb.append(...)` and `sb.build()`, and `StringBuilder` has
> neither — the API is `.write` / `.write_char` / `.write_int` / `.write_float` / `.write_bool` /
> `.to_str` / `.len` / `.capacity` / `.clear` / `.is_empty`. The compile error was `unknown method
> 'append'` on a *correctly bound* StringBuilder, and the `agree=2` was the tap telling the truth.
> Re-probed with the real API against the pre-fix compiler: the binder prints `x1`. There is no
> StringBuilder defect, so the fix has no arm for it.
>
> And every real row above **was** visible. Measured on the pre-fix compiler, each of the six
> shapes emitted a per-occurrence row:
>
> ```
> bucket=diverge site=tuple_destructure.elem var=b tid=List[Str] flat=List[Int] at=__main__:3
> summary tuple_destructure.elem agree=1 diverge=1 missing=0 unknown=0
> ```
>
> Stage 3's counter gate would have scheduled the whole class. The lesson the section was reaching
> for survives in a different form: the corpus contained exactly **two** rows of this six-shape
> class, both `List[Str]` in `tests/test_w224zg_map_forin_pair_container_element.bl`. A low row
> count is not a small defect — which is `feedback_corpus_sweep_is_not_coverage`, not a blind spot
> in the comparator.

Fixed by generalizing the arm: `stamp_map_binder_from_tid` becomes `stamp_binder_from_tid`
(`codegen_types.bl:3584`) with a `CT_LIST` arm beside the `CT_MAP` one, at all four binder positions.
Census on the 968-file common basis: `tuple_destructure.elem` agree 112 → 114, diverge 20 → 18,
missing 6 → 6; corpus diverge 29200 → 29198.

**The one residual row is not an erasure.** The third `w224zg` row moved from `flat=List[Int]` to
`flat=List[Void]` against `tid=List[W22Pt]` — still `diverge`, and correct anyway.
`set_list_elem_struct` (`codegen_types.bl:3980`) files the element's struct name in `sname2` and does
not recompute `tp_id`; `sv_tp` takes **one** `sname`, so the tp the tap compares has no slot for an
element struct name even though the `ScopeVar` does. This is the depth-≥2 unrepresentability the plan
names, and it clears with `sv_tp` in Stage 4 deletion group 1 — the same conclusion as the family-C
correction at the top of this document, arrived at from the opposite end.

**A tap test that asserts a divergence is a hostage of the defect.** Both `7xgbh6` tap tests named a
specific binder in the row stream, and per-occurrence rows are written for the diverge / missing /
unknown buckets **only** — so fixing this cell made a working tap fail its own tests. Rewritten to
count rather than to name: the tuple test asserts all four leaves are comparable
(`missing=0 unknown=0 agree+diverge=4`), the match test asserts a differential against a
wildcard-arm probe. That differential is **4, not 2**, and the factor is worth carrying: this site
counts *registrations*, not binders — every match arm is bound twice, once by the discarded pre-pass
at `codegen_stmt.bl:1073` that discovers the arm's value type and once by the real emit at
`codegen_stmt.bl:1238`. Read every `match_pattern.bind` figure in this document with that doubling in
mind. The one remaining named-row assertion (`var=m`, `tid=Map[Str, List[Str]]`) is labelled in place
with the count-based form to convert it to when `dcjy17` closes.

Tests: `tests/test_ksx1q7_tuple_binder_map_element.bl`, 9 rows — 8 red before (the file did not
compile, which is the honest red for this ticket), 9 green after. `task regen` at fixed point;
`task ci` exit 0, 679/679 test files, fmt 1578 passed / 0 failed.

For the `v71vxv` half: `tests/test_v71vxv_tuple_binder_element_kinds.bl`, 15 rows, every one
asserting a **value** — a compiles-only test passes the two silent rows while still printing an
integer for a `Str`. Red on the pre-fix compiler (9 compile errors, plus the two silent probes),
green after; `task ci` exit 0, 680 test files.

### Boxing is a property of the producer, not of the type — br `1n9fhg`

`blink_ListIterator_void` was the visible symptom. The cause is that codegen's flat element pair
records **one** fact — a CT and a companion name — for a slot whose meaning depends on **who filled
it**. Measured from emitted C, not inferred:

```
producer                      struct   tuple    data enum   PLAIN (payload-less) enum
push / literal list           pointer  pointer  pointer     VALUE  (intptr_t ordinal)
set element, map KEY          pointer  pointer  pointer     pointer (kops, inline_key = 0)
map VALUE                     pointer  pointer  pointer     VALUE  (intptr_t ordinal)
```

A plain enum is an ordinal in a push-built list — `blink_list_push(l, (void*)(intptr_t)blink_Col_Red)`
— and a **pointer** in a key list, because the emitted kops for a user enum is
`{ hash, eq, sizeof(blink_Col), 0 }`: `inline_key = 0`, so `blink_set_to_list` and `blink_map_keys`
push the slot as-is. `blink_map_keys` packs a value into the slot only under
`k->inline_key && k->key_size <= sizeof(void*)` (`bootstrap/runtime_core.h:856`, `:1192`), which is
Int / Char / Bool / the sized ints.

So the pair got a stated convention: **`(CT_VOID, name)` means "pointer-boxed — deref this"**, and a
nameless element means value-boxed. `set_list_elem_struct` (`codegen_types.bl:4069`) now *rejects* a
plain-enum name and records `CT_INT`, which defends the 45 push-built call sites in one place;
`set_list_elem_named_boxed` beside it is the deliberate escape hatch for a slot that genuinely holds
a pointer.

That leaves the enum's **identity** homeless, because an ordinal carries no name and `.to_str()` on a
str-backed variant dispatches off one. The split is the load-bearing part of this cell:

> **Storage comes from the flat pair. Identity comes from the tid.**

Identity is read at the for-in loop variable (`var_enums`) and at any nameless receiver
(`codegen_methods.bl:5443`, the derive-enum dispatch — `l.get(0).unwrap().to_str()` reaches a method
call on an `int64_t` temp with no name anywhere in the flat universe).

Three producers needed the tid, one after another:

1. **The push-built list** — storage from the pair, identity from the tid, as above.
2. **An iterable that is not a variable** — a struct FIELD (`for c in h.cols`), a call result, an
   index. Those have no `ScopeVar`, so the name probe has nothing to look up:
   `named_elem_of_elem_tid(tc_tid_iter_elem(...))` answers from the element's own tid. It takes the
   **element** tid, not the container's, because a Set normalizes into a temp list
   (`blink_set_to_list`) that has no tid of its own and whose element the pair erases the same way.
3. **The key lists, which box the other way.** `for c in s` over a `Set[Col]` compiled cleanly after
   step 2 and read the pointers as ordinals — `iter_reds = 0` instead of 1. Fixed with
   `set_list_elem_named_boxed` at the Set producer plus a node predicate, `map_keys_boxed_elem`
   (`codegen_stmt.bl:4210`), at the two node-visible `m.keys()` producers — the direct `for k in
   m.keys()` and the let-bound `let ks = m.keys()`. Its gate is the **receiver's tid saying `Map`**,
   which a user method named `keys` cannot forge.

Step 3 also repaired a defect that predates this cell: a **struct**-keyed `m.keys()` rendered the
`<value>` placeholder and reached cc as `void k`, because `emit_map_method`'s `keys` arm publishes
`expr_list_elem_type` and no name at all (`codegen_methods.bl:1714-1990`; `key_sname` is in scope
there and unused). And it caught a regression of my own making: normalizing the chokepoint in step 1
had turned a plain-enum `m.keys()` from a loud C error into a **silent wrong answer**, which is not a
trade this project makes.

> **The census does not move, and that is the correct outcome — not a measurement failure.**
>
> Off the unit's own test file the tydiv cell map is identical before and after: **29256 diverge
> rows, 717 cells** on a 969-file common basis, and ctypediv row-level diverge **23 → 23**. This unit
> routes *around* the flat pair instead of repairing its fidelity, so `tid=List[Lv1n] flat=List[Int]`
> stays a diverge cell while the emitted code becomes correct. Those cells clear with `sv_tp` in
> Stage 4 deletion group 1 — the same conclusion the `v71vxv` residual reached from the other end.
> The `+19` rows / `+18` cells in the raw before/after diff are entirely the new shapes the unit's own
> test rows exercise (`HCol1n` / `HLv1n` / `Lv1n`), which is why the comparison has to be read on a
> file basis that accounts for **content** growth and not only for new files.
>
> Both build modes were checked: the unit's rows are identical archive-linked and monolithic, and the
> only mode difference is the stdlib rows the monolith re-emits into every TU.

Three of the new rows are worth keeping in view because they look like a contradiction:

```
bucket=diverge site=emit_for_in.var       tid=HCol1n         flat=HCol1n
bucket=diverge site=emit_let_binding.decl tid=Set[HCol1n]    flat=Set[HCol1n]
bucket=diverge site=emit_let_binding.decl tid=Map[HLv1n,Int] flat=Map[HLv1n, Int]
```

The spellings agree and the bucket is still `diverge`. `ty_tp_same_shape` compares **kinds** before
names, and the flat side files a named enum under a struct-shaped `tp` — an accounting artifact of the
two representations, not a miscompile.

**What is left is not a missing arm; it is a type with two ABIs — br `k4thkq`.** A key list reached
through any *other* producer is still wrong, and two of the three forms are silent:

```
f(m.keys())                     -> total 0, want 7        SILENT
m.keys().get(0).unwrap()        -> "", want "low"         SILENT
m.keys().filter(...).len()      -> error[UnresolvedMethod] '.len' on type List[Lv]
```

A producer-blind consumer cannot be patched per producer, because for a payload-less enum `List[Col]`
genuinely has two physical representations. The fix is to remove the split: emit the kops for a
payload-less enum with `inline_key = 1` and `key_size = sizeof(blink_<Enum>)` so the runtime packs
the ordinal into the slot exactly as it does for an Int, which makes every producer agree and retires
both `map_keys_boxed_elem` and the plain-enum arm of `set_list_elem_named_boxed`. (Ordinal 0 is a
valid key, so the empty/tombstone marking has to be read first.) The alternative — threading a
per-list "pointer-boxed" bit through the 38 `expr_list_elem_struct` publication sites, which carry
mixed conventions today — was rejected: it is leaky *and* it keeps both ABIs. A **struct** key has no
split at all, since a push-built `List[Struct]` is pointer-boxed too.

Byproduct, unrelated cause, filed as br `bp9qp1`: an inferred `Map()` with an enum key emits a correct
key box for the first `insert` and `void _mkey` for every one after it, because the insert arm stores
the recovered key CT (`set_map_types`) and not the recovered key **name**, and the next call's
`base_key_sname0` gate reads a name only for `CT_VOID` / `CT_STRUCT`. Annotating the declaration hides
it. Loud, and it may be retired outright by `k4thkq`.

Tests: `tests/test_1n9fhg_list_named_elem_iterator.bl`, 14 rows, every one asserting a **value** —
a compiles-only test passes an ordinal read out of a pointer slot. `task regen` at fixed point after
each of the three sub-steps; `task ci` exit 0, 681 test files, fmt 1580 passed / 0 failed.

### One type, one ABI: a payload-less enum key is an inline key — br `k4thkq`

`1n9fhg` fixed the two producers a consumer can see. `k4thkq` removes the reason there were two.

A payload-less enum's kops now emits `inline_key = 1` with `key_size = sizeof(blink_<Enum>)`, so
`blink_map_keys` and `blink_set_to_list` pack the ordinal straight into the list slot — the same
layout `blink_list_push(l, (void*)(intptr_t)blink_Col_Red)` already produced. `List[Col]` has one
physical representation again, and a consumer that cannot see the producer no longer has to guess:

```
                              before                    after
f(m.keys())                   0     (want 7)  SILENT    7
m.keys().get(0).unwrap()      ""    (want "low") SILENT  "low"
for c in m.keys().filter(..)  identity lost            "low"
```

Four edits, one semantic change, one regen — the kops and its readers cannot land apart or the
emitted C claims two layouts at once:

| where | change |
| --- | --- |
| `codegen_types.bl` | `kops_is_inline_enum_key(sname)` — a registered kops key that is an enum and not a data enum |
| `codegen_derive.bl` | the kops table's fourth field is computed, not the literal `0` |
| `codegen_methods.bl` | `map_key_expr_inner` takes an inline enum FIRST: a stack temp, no `blink_alloc` — the runtime memcpy's `key_size` bytes out of the pointer it is handed |
| `codegen_stmt.bl` | the three read sites stop claiming pointer boxing: `map_keys_boxed_elem` declines a plain enum, and the Set for-in arm is one `set_list_elem_struct` call again |

A **data** enum is untouched and still pointer-boxed: its C struct carries a payload, which is also
how a push-built list holds it. Same rule, opposite answer. A **struct** key is untouched for the
same reason, and `set_list_elem_named_boxed` stays for it — `emit_map_method`'s `keys` arm publishes
the element's CT but never its name, so a struct key list's identity still has to be recovered at the
node.

Ordinal 0 is a real key, not an empty slot: the runtime tracks occupancy in a separate `states` array
(`0=empty, 1=occupied, 2=tombstone`), never by a zero sentinel in the slot. The test asserts this
directly rather than trusting the reading.

The **identity** half of the storage/identity split had one more hole, found by running the tests
rather than reading: a lazy adapter's loop variable (`for c in m.keys().filter(..)`) binds through
`emit_for_in`'s `CT_ITERATOR` arm, which had no plain-enum `var_enums` registration, so `.to_str()`
answered `""` even once the ordinal was correct. Fixed from the iterable's element tid, the same way
the direct list arm does it.

Census, on a **970-file common basis** in monolithic mode, the new test file excluded:

> `diverge` rows **29324 → 29324**, cells **735 → 734**, `agree` **671574 → 671742**, `ctypediv`
> **24 → 24**. One cell cleared. Three cells changed spelling, and all three got *more honest*:
> `emit_let_binding.decl tid=List[HLv1n]` moved from `flat=List[Void]` (the erasure spelling, and a
> lie about the boxing) to `flat=List[Int]`, and the two `emit_for_in.var` cells that read
> `tid=HCol1n flat=HCol1n` — the `ty_tp_same_shape` kind-before-name artifact — now read
> `flat=Int`, which is what the slot actually holds.

The unit's own file was attributed in **both** build modes: archive-linked (30 diverge rows) and
monolithic (54, the difference being stdlib the monolith compiles), with **identical** rows for every
`Lv` / `Col` / `Pt` shape. `tid=List[Lv] flat=List[Int]` and `tid=Lv flat=Int` are the new
storage-truthful spellings; `tid=List[Pt] flat=List[Void]` at a fn parameter is the struct key still
pointer-boxed, as intended.

Byproducts, both pre-existing, neither caused by this unit:

- br `r6r5v6` — a `.filter()` / `.map()` result rejects `.len()`
  (`error[UnresolvedMethod]: unresolved method '.len' on type List[Int]`) and escapes to `cc` in a
  `List[T]` argument position (`expected 'blink_list *' but argument is of type
  'blink_FilterIterator_int'`). The reference calls these adapters eager `List[T]` and the diagnostic
  agrees; codegen makes them lazy iterators. `List[Int]` reproduces both, so it is not about enums.
  The adapter rows here use `.count()` and a `for`-in as the workaround, marked in the test.
- br `bp9qp1` — **not** retired by this change, re-probed after it landed: an inferred `Map()` still
  emits `void _mkey` for every `insert` after the first, for an enum key *and* a struct key. Its
  cause is the insert arm storing the key CT without the key name, which is independent of boxing.

Tests: `tests/test_k4thkq_enum_key_one_abi.bl`, 10 rows, each asserting a **value** through a
producer-blind consumer — a fn parameter, an index, an adapter — plus controls for the struct key, the
scalar keys, the ordinal-zero key and the map *value* of enum type. `task regen` at fixed point;
`task ci` exit 0, 682 test files, 0 failed.

### A gate that named three kinds, when the stamp already spelled five — br `86kqrf`

The `bef42x` unit flipped authority to the tid inside `emit_let_binding`'s list ladder, but it did so
behind a gate that lists kinds by hand:

```blink
if expr_list_elem_type == CT_OPTION || expr_list_elem_type == CT_RESULT || expr_list_elem_type == CT_MAP {
    copy_list_compound_elem(val_str, name)
    stamp_list_elem_from_tid(val_node, name)
}
```

`stamp_list_elem_from_tid` (`codegen_types.bl:3443`) has **five** faithful arms — CT_OPTION,
CT_RESULT, CT_MAP, CT_SET (`mv45y5`'s) and CT_LIST (the tail). The gate named three. So an
unannotated `let` bound to a **call** returning `List[Set[T]]` or `List[List[T]]` never reached the
stamp, and `copy_list_compound_elem` cannot serve it either: it has no CT_SET or CT_LIST arm, and a
call RHS has no `ScopeVar` to copy from. The element kept its head and lost its inner:

```
bucket=diverge site=emit_let_binding.decl var=g tid=Set[Int] flat=Set[Set[?]]
bucket=diverge site=emit_let_binding.decl var=r tid=List[Set[Int]] flat=List[Set[?]]
```

A `Set[Int]` called a `Set[Set[?]]`. This is the same erasure family as every other cell in this
document, and again it is invisible to any predicate over the flat fields, because `sv_tp(CT_SET, -1,
..)` fabricates an inner rather than reporting that it has none.

**Both failure modes matter, and only one of them is loud.** For a `Set` element the ICE fires
(`internal compiler error[SetElementTypeUnknownAtCodegen]: for-in over Set variable 's' has no
element type recorded at codegen`) or `cc` refuses the binder (`assignment to 'int64_t' from
'blink_set *'`). For a `List[Str]` element **nothing** complains — the inner iterates as raw
pointers and prints as addresses. Every row of the test therefore asserts a **value**; the loud shape
would pass a compiles-only test the moment `cc` stopped caring.

The fix is the gate, not a new recovery path: capture the entry CT and stamp for CT_SET / CT_LIST at
the **end** of the branch, after the flat nested-element channels, so for exactly those two kinds the
tid is the last writer and the flat pair cannot overwrite a faithful inner with an erased one. The
Option/Result/Map precedence is unchanged: copy first, tid second.

The ladder exists **twice**, byte-identical, at `codegen_stmt.bl:3870` and `:9740`, so the fix had to
be written twice — the standing argument for the de-duplication that Stage 4 will make possible.

> **Census, monolithic, 971-file common basis (the new test file excluded):**
> `diverge` rows **29378 → 29375**, cells **745 → 743**, `agree` **671998 → 672067**, `missing`
> **73 → 73**, `ctypediv` **276 → 276 rows, identical line for line**. The two cells above cleared;
> none appeared. Their corpus sources were `tests/test_twq9kz_list_compound_elem_rebind.bl` and
> `tests/test_85j3j8_list_tuple_elem_through_call.bl` — files written for *other* cells, which is
> how this one stayed open: neither test asserted the inner container's contents.

The new file was attributed in **both** build modes, monolithic and archive-linked, with the same two
residual `emit_let_binding.decl` rows in each: `tid=List[Pt] flat=List[Void]` and
`tid=List[List[Pt]] flat=List[List[Void]]`. Those are the `(CT_VOID, name)` pointer-boxed struct
element — the name travels out of band and the flat *spelling* drops it — not a lost inner. The rows
that read them (`p.x` summed to 12, `.get(1).unwrap().y`) pass.

Tests: `tests/test_86kqrf_list_container_elem_call_rebind.bl`, 9 rows — a `Set[Int]`, a `Set[Str]`, a
`List[Str]`, a `List[Pt]` and a `Set` through `.filter().collect()`, plus four controls that already
worked and must not move: an annotated declaration, a local literal, a `List[List[Int]]` (an `Int`
inner *coincides* with the erased default, which is why the bug reads as intermittent), and a
`for`-in straight over the outer list. `task regen` at fixed point; `task ci` exit 0, 683 test files,
0 failed.

### A `for` binder over a list of containers, and the producer that has no `ScopeVar` — br `bgenc2`

`emit_for_in`'s binder arm builds the loop variable's type from the **iterable's** `ScopeVar`: it reads
the flat list-element channels of the variable being iterated and copies them onto the binder. A
`let`-bound or annotated iterable has those channels filled, so the binder is right. A **call**, a
**method result** or a **struct field** has no `ScopeVar` at all, every read answers `-1`, and `sv_tp`
supplies the house default:

```
bucket=diverge site=emit_for_in.var var=m tid=Map[Int, Str] flat=Map[Str, Int]
bucket=diverge site=emit_for_in.var var=m tid=Map[Str, Str] flat=Map[Str, Int]
```

`Map[Str, Int]` is not a reading of the program. It is `sv_tp(CT_MAP, -1, -1, "")`, the same
fabrication this document has named at every other erasure site in it. The tid beside it was already correct,
which is the whole argument of Stage 3: the answer was in hand at the site that guessed.

**Three element kinds, three different failure modes.** A `Map` element is **silent** — the value type
comes back `Int`, so `m.get(5)` on a `Map[Int, Str]` yields a pointer printed as `94115272205922`. A
`List` element is **silent** — the inner element is erased the same way, and in combination with a
struct inner it segfaults. A `Set` element is **loud**: `internal compiler
error[SetElementTypeUnknownAtCodegen]`. One cause, so one ticket and one test; but only the third
kind would ever have been reported by a user as a compiler bug.

The controls are the diagnosis, not decoration. The **index** path (`lm.get(0).unwrap()`), the
**fn-parameter** path, a binder **passed on** to a typed parameter, a **`let`-bound** iterable and an
**annotated** declaration were all already correct — each has a `ScopeVar` or a declaration to copy
from. And `Map[Str, Int]` "works" only because it *is* the fabrication.

#### The fix splits each stamp into a node front and a tid core

`stamp_list_elem_from_tid`, `stamp_map_from_tid` and `stamp_binder_from_tid` all begin by turning a
node into a tid (`tc_lookup_node_tid` + `tc_tid_subst_mono`) and then act on the tid. A `for` **binder
is not an expression**, so it has no memoized tid of its own to look up — the tid has to come from the
iterable's element. Each of the three therefore keeps its node-taking name as a one-line front over a
new tid-taking core (`stamp_list_elem_from_list_tid`, `stamp_map_from_map_tid`,
`stamp_binder_from_binder_tid`), and `emit_for_in` calls the core with the element tid it derives
itself:

```blink
let binder_tid = tc_tid_subst_mono(tc_tid_resolved(tc_tid_iter_elem(tc_tid_resolved(tc_lookup_node_tid(iter_node)))), cg_mono_tparams_sl, cg_mono_arg_tids)
if elem_type == CT_MAP || elem_type == CT_LIST || elem_type == CT_SET {
    stamp_binder_from_binder_tid(binder_tid, var_name, 0)
}
```

Two orderings are load-bearing and are the reason this change moves nothing that already worked. The
call runs **after** `set_var`, which rebuilds the variable's `tp` from scratch and would discard an
earlier write. And it runs **before** the flat nested-element copies, so a `ScopeVar` that *does* have
an answer still gets the last word — the tid fills a hole, it does not overrule a working channel.
That is the opposite precedence from `86kqrf`, where the flat side had no answer to defend and the tid
had to be the final writer.

`stamp_binder_from_binder_tid` also gains the **CT_SET arm** that the `v71vxv` retraction declined to
write for want of a measured shape. There is a measured shape now, and the arm keeps the same
fail-quiet contract as the others: if the tid carries neither a set-element ct nor a struct name it
returns `false` and leaves the flat channels their answer.

> **Census, monolithic, 972-file common basis (the new test file excluded):**
> `diverge` rows **29401 → 29398**, cells **744 → 742**, `missing` **73 → 73**, `unknown`
> **4655 → 4655**, `ctypediv` **276 → 276 rows, identical line for line**. The three rows that moved
> are all `tuple_destructure.elem`, and they moved to `agree` 1:1 — a **byproduct**, not this
> ticket's own cell: `tid=Set[Int] flat=Set[?]` and `tid=Set[Str] flat=Set[?]`, from
> `tests/test_v71vxv_tuple_binder_element_kinds.bl`, `tests/test_ksx1q7_tuple_binder_map_element.bl`
> and `tests/test_w224zg_map_forin_pair_container_element.bl`. The new CT_SET arm closes the hole
> those three tickets left open, because tuple binders route through the same core.

`emit_for_in.var` itself stays at 36 cells and 76 rows on that basis, and that is the expected
result: **the corpus contains no file with this shape**, which is exactly why the cell was never
published and the bug outlived every ticket this project has closed so far. It took a hand-built program to make the
tap fire. A zero-hit sweep is an unexercised tap, not coverage.

`agree` rose **672324 → 672576**, and the arithmetic closes exactly: 3 rows are the moved
`tuple_destructure` Set rows, and the other 249 are `emit_fn_params.param` rows in the 35 corpus files
that **import the compiler** — 32 files at +7, three at +6 — counting the parameters of the three new
tid-taking helpers, which are compiler source and therefore part of the corpus they measure.

The new file was attributed in **both** build modes, monolithic and archive-linked, and both leave the
same single residual row: `site=emit_for_in.var var=inner tid=List[Pt] flat=List[Void]`. That is the
`(CT_VOID, name)` pointer-boxed struct element — the name travels out of band and the flat *spelling*
drops it — not a lost inner. The rows that read it (`p.x` summed to 12, `.get(1).unwrap().y`) pass.

Tests: `tests/test_bgenc2_forin_binder_container_elem.bl`, 11 rows — a `Map` value, a `Map` key and
`.values()`, a `Map[Str, Str]`, a `List` element read two ways, a `List[Pt]`, a `Set[Str]` and a
`Set[Int]`, and a **struct field** as the iterable, plus four controls that must not move. Every row
asserts a value, because two of the three failure modes are silent. `task regen` at fixed point;
`task ci` exit 0; 684 test files, 684 passed, 0 failed.

### The two seams that read the RECEIVER's name — br `a1cx6d`, br `fyat2w`

`bgenc2` above fixed the `for` binder. Its cause — *flat metadata is copied from a producer that
has no `ScopeVar`* — has two more instances, and both are reached by a plain method call:

```
bucket=diverge site=match_pattern.bind var=st tid=Set[Int]  flat=Set[?]
bucket=diverge site=match_pattern.bind var=m  tid=Map[Str, Str]  flat=Map[Str, Int]
bucket=diverge site=match_pattern.bind var=l  tid=List[Str] flat=List[Int]
```

**`a1cx6d` — the match-arm binder.** `bind_pattern_vars`'s Option/Result carrier fast path fills a
container binder's element from two lossy sources: the transient `expr_option_*` / `expr_result_*`
globals, and the **scrutinee's own flat channels, looked up by the scrutinee's C name**. A
call-returned scrutinee is a temp (`_scrut_1`) with no `ScopeVar`, so both answer nothing and `sv_tp`
supplies the house default. The same three kinds fail the same three ways as in `bgenc2` — Set loud
(`SetElementTypeUnknownAtCodegen`), Map and List silent.

One thing is worse here than at the `for` binder: **no producer shape works.** A `let`-bound value
and an **annotated declaration** fail identically to a call, because the arm reads the scrutinee
*temp*, not the declaration the temp came from. There is no coincidence to hide behind and no
"it works if you annotate it" workaround.

**`fyat2w` — `Option[Set[T]].unwrap()`, and its `Option[List[T]]` sibling.** Same read, one seam
over: `get_var_option_inner2(obj_str)` with `obj_str` the receiver's C text. For `oset().unwrap()`
that is a call expression, so the unwrapped set is left with **no element at all** and a later
`for` falls through to the stale `expr_list_elem_*` globals — whatever the last emitted
list-producing function body left behind. The element therefore depends on a declaration the
program never calls:

```blink
fn oset() -> Option[Set[Int]] { let s: Set[Int] = Set(); s.insert(4); s.insert(5); Some(s) }
fn olist() -> Option[List[Str]] { Some(["a", "bb"]) }   // never called
fn main() {
    let st = oset().unwrap()
    let mut n = 0
    for x in st { n = n + x }                            // cc: int64_t = const char*
}
```

Delete the `olist` line and the same program prints `9`. Make it `Option[List[Pt]]` and the loop
decodes a struct. Remove every list producer and the element is unset and the for-in ICEs. That is
one declaration reaching into another's codegen through a global — the failure mode a flat side
channel has and a tid does not.

The `Option[List[T]]` arm of the same function was fabricating too, in the open:
`set_list_elem_type(val_tmp, CT_INT)` as an explicit floor. `Option[List[Pt]].unwrap()` then handed
`.get(0).unwrap().x` an integer and printed `<value>`.

#### Fill-only, because this stamp cannot run first

`bgenc2`'s stamp is a **writer**: it calls `set_var`, which rebuilds the var's `tp` from scratch, so
it has to run *before* the flat copies that follow it. A match-arm binder cannot be served that way.
`bind_pattern_vars` decides the head CT and emits the C declaration inside one of ~28 arms, each
doing its own element copy afterwards, and the single place that sees **every** binder
(`pat_measure_at`) runs last. Writing there would overrule arms that were already right.

So `stamp_binder_elems_from_tid_if_unset` asks before it writes. An unset channel reads `-1` / `""`,
and that is the only honest signal available — a *set* channel holding the erased default is
indistinguishable from a genuine `Map[Str, Int]`, so "already set" has to mean "leave it alone". The
head CT must agree first: a binder whose flat head says `List` while the tid says `Set` is a
contaminated head, not a missing element, and stamping through the disagreement would write one
container's element onto another's channel — a new silent-wrong, not a fix.

#### `get_list_elem_type_raw`, and why the fill-only guard needed it

The first cut of this fix silently did nothing for lists, and the reason is the thesis of this whole
document. `get_list_elem_type` reads `tp_child1_kind`, and `sv_tp(CT_LIST, -1, ..)` answers
`type_list(type_int())`. **A list whose element was lost and a genuine `List[Int]` are the same pool
entry, bit for bit**, so every question asked through the pool comes back `Int` and a fill-only stamp
declines forever. The raw flat `inner1` field, which every setter keeps alongside `tp_id`, still says
`-1` — so it is the only place the distinction survives. `get_list_elem_type_raw` reads it, mirroring
`get_map_key_type_raw` / `get_map_value_type_raw`, and falls back to the pool answer for a name that
is not a scope var (a closure capture has a `tp_id` and no flat fields): there a missing answer must
read as SET, because declining is a no-op while overwriting a capture's real element is a new bug.

`Set` needed no such reader — `mv45y5` had already made `sv_tp`'s `CT_SET` arm decline instead of
fabricate, which is exactly why that kind is the loud one.

At the `.unwrap()` seam the guard is not needed at all and is not used: that branch **is** the
position where nothing else answered, and what it replaces is the `CT_INT` floor. The tid runs
third, after both existing channels, and the floor still stands for a tid that declines.

> **Census, monolithic, 973-file common basis (the two new test files excluded):**
> `diverge` **29423 → 29423**, cells **743 → 743**, `missing` **74 → 74**, `unknown`
> **4660 → 4660**, `ctypediv` **276 → 276**. Nothing moved and nothing regressed, and that is the
> expected reading: **no pre-existing corpus file has either shape.** The published
> `match_pattern.bind` siblings do not move either, and by design — `tid=Map[Str, List[Int]]
> flat=Map[Str, Int]` (`tests/test_option_map_list_ptr.bl:103`) has its key already set from the
> carrier tag, and `tid=List[Str] flat=List[Int]` (`tests/test_generic_deep_nesting.bl:60`) is an arm
> that wrote `CT_INT` on purpose. Fill-only cannot correct a channel that already answered; those are
> authority flips, each needing its own measured shape. A zero-delta sweep is not a null result here,
> it is the statement that this shape was never in the corpus — the same finding as `bgenc2`.

Both files were attributed in **both** build modes, monolithic and archive-linked, with identical
rows. Three residuals, all in-file and all passing:

- `emit_let_binding.decl var=p tid=List[Pt] flat=List[Void]` — the `(CT_VOID, name)` pointer-boxed
  struct element, an accounting artifact already named in the `bgenc2` section.
- `emit_let_binding.decl var=os tid=Option[Set[Str]] flat=Option[Set[?]]` — a Set in **nested**
  position, the family this plan defers to Stage 4 because the flat CSV has nowhere to put it.
- `match_pattern.bind var=l tid=List[Pt] flat=List[]` — a **half-answer**: the arm recorded the
  element's CT as a struct and its name as `""`, so `tp_display` renders the empty `sname` as
  nothing. The fill-only stamp declines (the channel answered), and the row still passes — because
  `for p in l` is `emit_for_in`, which consults the tid since `bgenc2`. The two fixes compose: a
  binder the flat side half-lost is read correctly one level down. Worth keeping in view as its own
  cell, not folded into either ticket.

Tests: `tests/test_a1cx6d_match_binder_container_elem.bl`, 11 rows — a `Set[Int]`, a `Set[Str]`, a
`Result` `Ok(st)`, a `Map[Int, Str]` read three keys deep, a `Map[Str, Str]` with `.values()`, a
`List[Str]` read two ways, a `Result` `Ok(l)`, a `List[Pt]`, and the annotated and `let`-bound forms
that do **not** rescue the binder, plus the `Map[Str, Int]` coincidence control.
`tests/test_fyat2w_option_set_unwrap_elem.bl`, 4 rows — the bound and expression-position unwraps
for two element types, and a row proving the contaminant declarations still work themselves. Every
row asserts a value; two of the three failure modes are silent. `task regen` at fixed point; `task
ci` exit 0; 686 test files, 686 passed, 0 failed; fmt 1590 passed, 0 failed.

### The seam with no reader at all — br `qy9ssr`

The three seams above lose an answer. This one **inherits somebody else's**, and it is the first of
this family that fails loudly at `cc` rather than silently at runtime:

```
blink_Option_Option_int _scrut_1 = blink_first_1or_1none_0Str(_l0);
cc: error: invalid initializer
cc: error: initialization of 'blink_list *' from incompatible pointer type 'blink_Option_int *'
```

`blink_first_1or_1none_0Str` is declared correctly one screen up — `blink_Option_list
blink_first_1or_1none_0Str(blink_list* l)`. The carrier on the left belongs to a **different
function**, `c_oopt() -> Option[Option[Int]]`, which the program does call but never in this
statement. Reorder the declarations and the borrowed carrier changes with them; often the tag on the
left is not even typedef'd in that TU.

#### The cause is a missing `else`, and its sibling ten lines down has one

`emit_match_expr` spells the scrutinee's carrier temp from the pair `expr_option_inner` /
`expr_option_inner_struct` (`codegen_stmt.bl` ~:904, and ~:801 for a tuple element). Those are
transient globals with **84 assignment sites** across `src/*.bl`. `emit_generic_fn_call_tail`'s
`CT_OPTION` branch is one of them (`codegen_expr.bl` :3778):

```blink
expr_option_inner = inner_ct
if inner_ct == CT_VOID && (is_struct_or_enum_type(inner_name) != 0 || is_mono_struct_instance(inner_name) != 0) {
    ensure_struct_option_type(inner_name)
    expr_option_inner_struct = inner_name
}
// ← no else
```

The `CT_RESULT` branch immediately below it does have that `else`, and clears both of its own
channels. That asymmetry **is** the bug, and it is why every Result spelling of every row in the
regression test always worked while the Option spelling did not. On a non-struct inner the `if` does
not fire, and leaving the global alone does not mean "no answer" — it means the last compound-Option
producer's answer survives into a caller that has nothing to do with it.

So the honest shape of this defect is not "a container's element was erased". No container is
required: `opt_of(5)` reproduces it, because `CT_INT` is not a struct either. Within the regression
test the leak even crosses rows of the *same* file — row 7's `Option[Pt]` poisons rows 8 and 9:

```
blink_Option_Pt _scrut_66 = blink_first_1or_1none_0Str(empty);
blink_Option_Pt _tup_71  = blink_opt_1of_0Str("q");
```

#### Fixed at the producer, not at the reader

The plan's Stage 3 says make the tid authoritative, and the scrutinee site does have the node in
hand — `tc_lookup_node_tid(scrut)` would have answered `Option[List[Str]]` correctly. That fix was
**not** taken, for a reason worth recording: it would have made the reader immune while leaving the
leak in place for the other 83 assignment sites and every other consumer of the pair. Clearing at the
source fixes all of them at once, and it is the change that makes the two sibling branches say the
same thing.

Clearing cannot regress the shapes that look most at risk from it — a generic fn returning
`Option[Option[T]]` or `Option[Result[T, E]]`. Those were checked and are **already** broken
independently: the mono'd signature erases the inner's type args (`blink_Option_Option_void`,
`blink_Option_Result_void_str`) while the caller drops them entirely (`blink_Option_option`). Three
disagreeing spellings of one type in one TU, filed as br `705b70` with `Option[Map[K,V]]` as its
primary shape. They are deliberately absent from this ticket's test file: asserting them here would
attribute that defect to this one.

> **Census, monolithic, 973-file common basis:** `diverge` **29423 → 29423**, cells **743 → 743**,
> `missing` **74 → 74**, `agree` **673418 → 673418**, family-A cells **11 → 11**, `ctypediv` diverge
> **24 → 24**. Identical in every bucket.

That null result means something different here than it did for `bgenc2` / `a1cx6d`, and the
difference matters. There, zero delta meant *the shape was not in the corpus*. Here the shape's
**site is not measured at all**: the tydiv channel taps `emit_fn_params.param`,
`emit_let_binding.decl`, `match_pattern.bind`, `emit_for_in.var`, `tuple_destructure.elem`,
`with_resource.bind` and `copy_list_compound_elem.src` — and not the carrier temp `emit_match_expr`
materializes. A hard `cc` failure lived at that site and the census could not have seen it either
way. The 11-row test is the whole of the coverage. Filed as br `359pt5`: tap `match.scrut` and
`match.scrut_tuple_elem`, then re-sweep — and only then is there a measurement that could justify
the authority flip declined above.

Attributed in **both** build modes. All four user-file rows are identical; monolithic adds nine
stdlib rows (`Duration`, `Instant`, `self tid=Map[?, ?]`) that archive mode does not recompile, the
same mode difference the previous two sections recorded. Residuals, all in-file and all passing:

- `emit_fn_params.param var=v tid=List[Str] flat=List[Int]` — the mono'd `opt_of[T]`'s own parameter
  when `T` is bound to `List[Str]`. The row passes because `emit_for_in` reads the tid since
  `bgenc2`; the flat param spelling is still the erased default.
- `match_pattern.bind var=p tid=Pt flat=Int` — a pointer-boxed struct binder booked as `CT_INT`. The
  emitted C is right (`blink_Pt p = *_scrut_60.value;`); this is the same accounting artifact as
  `flat=List[Void]`, one position over.
- `emit_fn_params.param var=l tid=List[Pt] flat=List[Void]` and `match_pattern.bind var=l
  tid=List[Pt] flat=List[]` — both already named in the sections above.

Tests: `tests/test_qy9ssr_generic_option_carrier.bl`, 11 rows — a generic `Option[T]` at `Int`, at
`Str`, at a bare typevar bound to a `List` and to a struct; a generic `Option[List[T]]` at `Str`,
`Int` and `Pt`; the `None` arm; a tuple-position scrutinee (the second, separate reader at ~:801);
and two controls — the Result spelling that was never broken, and the three contaminant producers
proving they still work themselves. `task regen` at fixed point; `task ci` exit 0; 687 test files,
687 passed, 0 failed; fmt 1592 passed, 0 failed.

Two byproducts filed while probing this one, both loud, neither touched: br `705b70` above, and br
`ht0bxj` — a typevar does not bind from a bare `Set[T]` **parameter**, so *every* generic fn taking
one is uncallable (`I0001`, mono args `BLINK_I0001_erased_slot`). `zpspke` made the other compound
params bind; `Set` was missed. It is a missing arm rather than an erasure, and it reports rather than
guesses — the same asymmetry `mv45y5` created when it made `sv_tp`'s `CT_SET` arm decline, and the
reason `Set` keeps turning up as the kind that tells you it is broken.


## A type param two levels down bound nothing, in three places (br `ee99gs`)

Entered not from the census but from the Stage 3 unit above it. The plan's line *"Replace
`copy_list_compound_elem` with `set_var_ty(dst, get_var_ty(src))`"* has one position where the copy is
genuinely load-bearing — an **abstract generic body**, where `deep_tp_from_tid` declines by contract
because the element's inner is a typevar. Constructing that position to measure it is what turned up
this ticket: **every** signature that puts a type param two levels down was uncallable, so the
position could not be reached by any compiling program. The blocker had to go first.

### The ticket was Set-shaped. The defect was not.

`ee99gs` reads *"Generic fn param `List[Set[T]]` fails to solve T at call site"*, and both the title
and the MVCE point at Set. An isolation matrix says otherwise — every row is `fn f[T](p: <shape>)`
with a real call site, because an **uncalled** generic fn never monomorphizes and answers "ok" no
matter how broken its binder is:

| parameter shape | before | after |
|---|---|---|
| `List[T]`, `Map[K, V]`, `Option[T]` | binds | binds |
| `List[(Str, T)]` | binds (bespoke arm) | binds |
| `List[Set[T]]` | **`BLINK_I0001_erased_slot`** | binds |
| `List[Option[T]]` | **`BLINK_I0001_erased_slot`** | binds |
| `List[Result[T, Str]]` | **`BLINK_I0001_erased_slot`** | binds |
| `List[List[T]]` | **`BLINK_I0001_erased_slot`** | binds |
| `List[Map[K, V]]` | **`BLINK_I0001_erased_slot`** | binds |
| `Map[K, List[V]]` | **`BLINK_I0001_erased_slot`** | binds |
| `Option[List[T]]` | **`BLINK_I0001_erased_slot`** | binds |
| `List[List[Set[T]]]` (depth 3) | **`BLINK_I0001_erased_slot`** | binds |

Depth 1 binds. Depth 2 binds nothing, for every head, in every slot. Set is only the kind that ICEs a
*second* time on the way out, which is what made the ticket look kind-specific. A second parameter
mentioning the same param at depth 1 rescues the whole signature — which is the giveaway that this is
about how far the reader descends, not about what it finds there.

This is the plan's thesis on the **inference** side rather than in codegen: a fixed set of one-level
readers cannot express depth >= 2, and the cure is the same one — walk the structured tid instead of
hand-writing a cell per (head x slot).

### Half one: `tc_resolve_tparam_tid` is a cell per (head x slot), and every cell reads one level

`src/typecheck.bl:15325`. The body is an arm per annotation head crossed with the slot the param
occupies: `List[T]` off `inner1`; `Map[K, _]` / `Map[_, V]` off `inner1` / `inner2`; `Option[T]`;
`Result[T, _]` / `Result[_, E]`; a bespoke case for `List[(.., T, ..)]`; hard `-1` for struct, enum and
`Fn` heads. **Nothing recurses.** A param one level further in matched no arm, so the slot arrived at
monomorphization as `BLINK_I0001_erased_slot` and the mangled symbol carried the placeholder
verbatim: `blink_first_1set_BLINK_I0001_erased_slot(d)`.

The replacement is a lockstep walk of the annotation tree and the argument's tid:

```blink
fn tc_tparam_tid_from_ann(ann: Int, tid: Int, param_name: Str) -> Int {
    if ann == -1 || tid < 0 { return -1 }
    if node_name(ann) == param_name {
        if tc_struct_slot_encodable(tid) { return tid }
        return -1
    }
    let elems_sl = node_elements(ann)
    if elems_sl == -1 { return -1 }
    if tc_ann_head_matches_tid(ann, tid) == false { return -1 }
    ...
        if tc_ann_mentions_param(child_ann, param_name) {
            let r = tc_tparam_tid_from_ann(child_ann, tc_tid_child(tid, i), param_name)
            if r >= 0 { found = r }
        }
    ...
}
```

It is a dozen lines only because `tc_tid_child(tid, i)` indexes `inner1` / `inner2` / the params
slice **in the same order the parser puts an annotation's `elements` in**. That alignment is the whole
reason the ladder was never needed. `TyKind.Fn` is the one exception — an `Fn` annotation stores its
params in `elements` and its return in `type_ann` — so `tc_ann_head_matches_tid` answers `false` for
it and the existing arm keeps that shape. The match enumerates all 29 kinds rather than closing with a
wildcard, so a kind that later gains an annotation spelling has to be decided here.

Three guards, each load-bearing:

* **Descend only into a child that actually names the param** (`tc_ann_mentions_param`), so an
  unrelated sibling slot cannot supply a binding.
* **Descend only when the annotation's head agrees with the tid's kind.** Without it an
  `Option[T]` annotation against a `List[Int]` argument would bind `T` to the list's element — the
  positional walk has no other way to notice that the two trees have diverged.
* **Return only an encodable tid** (`tc_struct_slot_encodable`), which is what keeps a typevar or an
  unknown from being spelled into a mono name. The same gate the struct and tuple arms already use.

Wired as the **last** resort, after every arm has declined, so it only *adds* answers: no slot an arm
already resolved is re-decided, the struct/enum arms' deliberate hard `-1` still fires first, and the
`Fn` arm's own hard `-1` (br `3ejrqa`) is never reached from here. Last-match-wins for a param named in
several slots, matching `tc_struct_param_binds`.

That took the test from 13 ICEs to 3.

### Half two: the generic-fn return ladder had no `CT_SET` arm

The remaining 3 were one shape, and the ticket had predicted it: *"which then ICEs a second time at
the for-in (`SetElementTypeUnknownAtCodegen`)"*.

```
internal compiler error[SetElementTypeUnknownAtCodegen]: for-in over Set variable
  'blink_first_1set_0Int(d)' has no element type recorded at codegen
```

The mangled name in that message is itself the proof half one landed — `_0Int`, not
`_0BLINK_1I0001_1erased_1slot`. What remained was `emit_generic_fn_call_tail`
(`src/codegen_expr.bl:3630`), whose return ladder has an arm for `CT_OPTION`, `CT_RESULT`, `CT_LIST`,
`CT_MAP`, a rerouted `CT_STRUCT`, and `CT_VOID`-as-tuple-or-struct — and **none for `CT_SET`**. A
generic fn returning `-> Set[T]` published no element to its caller at all.

The arm reads the **call node's memoized tid**, not the return annotation the way its `CT_LIST` and
`CT_MAP` siblings read theirs, because the annotation names the type *param* (`Set[T]`) while
typecheck has already substituted `T` on the call node:

```blink
} else if ret_type == CT_SET {
    recover_set_elem_from_tid(node, "{c_fn_name(mangled)}({call_args})")
}
```

Keyed on the call string because that is what `expr_result_str` becomes a few lines below, and what the
for-in lowering looks the element up by. `recover_set_elem_from_tid` declines whole on a tid that
cannot name the element, so the arm only ever adds an answer, and it uses the `_resolved` accessors —
an unannotated `Set()` inside the callee has a metavar element bound in place by a later `.insert`
(br `mv45y5`).

Deliberately *not* widened: a **bare-typevar** return `-> T` bound to a Set does not reroute
(`rerouted` covers Option/Result/Map/struct only), so it is still unhandled. That is a different cell
and it is not this ticket's MVCE.

### Half three: what the ICEs were hiding

An ICE means `blinkc` exits 101 **without writing any C**. So the moment the two halves above stopped
firing, a third defect appeared that had been invisible the whole time — not a regression, an
uncovering:

```c
blink_Option_Option_void _lget_1;                       /* in blink_first_1opt_0Pt */
_lget_1.value = (blink_Option_void*)blink_list_get(xs, _lgi_0);
blink_Option_void _ounv_3 = *_ounw_2.value;             /* undefined type */
...
return _ounv_3;   /* returning blink_Result_void_str where blink_Result_int_str expected */
```

`emit_mono_fn_def` binds a `List` param's element from the **annotation** (`src/codegen_stmt.bl:8430`),
and only the element's *outer* name goes through `resolve_tparam_via_tid`. A compound element's inner
is read raw: `set_list_elem_compound_ann` calls `deep_tp_from_ann` on the `T` node, which knows nothing
about this instance's binder. So the mono instance of `xs: List[Option[T]]` bound its element as an
Option over nothing, and every read of it spelled the undefined `blink_Option_void`; `List[Result[T,
Str]]` spelled `blink_Result_void_str` and returned it where a `blink_Result_int_str` was expected.

The tid does carry `T` substituted, once rewritten through this instance's binder, and
`stamp_list_elem_from_list_tid` is the complete ladder — it spells every element kind faithfully or
declines whole. So it **leads** and the annotation's answer survives only where it declines, the same
ordering the let-binding ladders use (br `bef42x`):

```blink
let mut praw = tc_lookup_node_tid(p)
if praw < 0 { praw = tc_lookup_node_tid(ta) }
stamp_list_elem_from_list_tid(tc_tid_subst_mono(tc_tid_resolved(praw), tparams_sl, arg_tids), pname)
```

Two details cost a regen each to find:

* **`tparams_sl` / `arg_tids` are passed explicitly.** The `cg_mono_*` globals that
  `stamp_list_elem_from_tid` reads are not switched to this instance until `emit_fn_body`, ~150 lines
  further down. Using the node-taking wrapper here substitutes against the *enclosing* context.
* **The tid lives on the PARAM node, not on its annotation.** The annotation carries a tid only for
  the struct-instance shapes that walk it; the first attempt read `node_type_ann(p)` and every event
  traced `ect=-1 arm=bail_unnameable`. `params_measure` states the rule five thousand lines away and
  it is now stated here too.

### Measurement

The new mono-param stamp is an authority flip in miniature, so it is instrumented rather than asserted.
A `monoparam` channel records what the annotation had already written next to what the stamp decided,
which separates the three outcomes that matter: **DECLINED** (the annotation still governs), **AGREED**,
and **OVERRODE** — only the third is a behavior change.

Corpus (`tests/` + `examples/` + `src/` + `lib/std/` + `lib/pkg/`), **both build modes**, archive-linked
via `blink build --emit c` and monolithic via `blinkc`:

| verdict | archive-linked | monolithic |
|---|---|---|
| DECLINED (annotation still governs) | 0 | 0 |
| AGREED | 44 | 44 |
| **OVERRODE** | **6** | **6** |
| total events | 50 | 50 |

**The two modes agree row for row** — same 50 events, same verdicts, same types. Five of the six
overrides are the new test. The sixth is the interesting one, and it is **pre-existing**:

```
tests/test_1n9fhg_list_named_elem_iterator.bl  list_1fold_0List_0Int
    List[List[Int]]  ->  List[List[Str]]
```

`ll: List[List[Str]]` through the stdlib's `list_fold[T, A]`, T bound to a List. The annotation path
had the nested element as **`Int`** — not "unknown", `Int` — because `set_list_elem_compound_ann` never
reached it and `sv_tp(CT_LIST, -1, -1, "")` answers `type_list(type_int())`. That is confirmation #1 of
the plan (*"`sv_tp` fabricates types when a flat slot is `-1`"*) caught live, in a passing test, on a
shape nobody filed: the row asserts `a + v.len()`, and a list's `.len()` does not depend on its element
type, so the fabricated `Int` was never observed. It is corrected now, and it is the reason this stamp
is instrumented rather than asserted — a sweep that only counted "did it fire" would have called this
seam clean.

One measurement note worth keeping, because the first sweep got it wrong: comparing the
`ListElemStamp{ct, sname}` pair the stamp *returns* reports **all 50 events as AGREED**. A compound
element's inner lives in `tp_id`, so `List[Option[Void]]` and `List[Option[Str]]` are both
`ct=CT_OPTION, sname=""` — the pair cannot distinguish the defect from the fix. The tap has to render
the whole var type (`tp_display(get_var_tp(pname))`) or it measures nothing. Same failure mode as
`list_elem_unspellable`'s missing companion (br `bef42x`): a predicate written over the flat pool
answers identically for a lost inner and a real one.

`task ci` green unpiped, exit 0: **688 test files, 688 passed, 0 failed, 0 build errors**; fmt 1594
passed, 0 failed, 88 skipped; per-module gen1-vs-gen2 byte-equal.

`tests/test_ee99gs_nested_tparam_param_bind.bl` — 11 rows, written red first (13 ICEs), all green. It
asserts **runtime values**, not just that the program compiles, because `task regen` proves self-host
and not codegen (`feedback_self_host_doesnt_catch_user_codegen_bugs`) and two of the three halves here
were wrong C that `cc` would have accepted in a slightly different shape. Verified green in **both**
build modes: `build/blink` (archive-linked) and `build/blinkc` + `cc -Ibootstrap -lgc` (monolithic),
11/11 each.

One residual, and it is an existing cell rather than a new one. The depth-3 row stamps
`List[List[Set[?]]]` — the innermost element is still unnamed, which is br `f9hgt9` (*"this carries only
the KIND at 2 levels deep, not the inner container's OWN element at 3 levels deep"*, written on
`stamp_list_elem_from_list_tid`'s own tail arm). The test row passes because the for-in recovers its
element from the callee's **return** type, not from that channel. Not folded in.

### What this unblocks

The `copy_list_compound_elem` position the Stage 3 unit needs — an abstract generic body whose list
element is a compound over a typevar — is now **reachable by a compiling program**. That measurement
is the next section, and it did not find the position: inside a mono body every copy is superseded by
an identical tid stamp, and outside one the fn is never emitted.

## `copy_list_compound_elem`: the plan's archetype, measured (br `zaq1np`)

The plan names this function as confirmation #3 — *"26 lines of hand case analysis to copy a type from
one variable to another, with no `CT_SET`, `CT_LIST`, or `CT_TUPLE` arm — three of the open tickets,
verbatim. It should be `set_var_ty(dst, get_var_ty(src))`."* Measuring it changed two of those three
claims and produced a real bug that none of them named.

### The missing arms are unreachable

All three call sites gate on the element being a **compound tag**, and `is_compound_tag` is exactly
Option/Result/Map:

| call site | gate |
| --- | --- |
| `codegen_stmt.bl:3885` (`emit_let_binding`) | `expr_list_elem_type == CT_OPTION \|\| == CT_RESULT \|\| == CT_MAP` |
| `codegen_stmt.bl:9819` (the second let ladder) | same |
| `codegen_methods.bl:4525` (`collect`) | `obj_type == CT_LIST && is_compound_tag(carrier) != 0` |

So the `CT_SET \|\| CT_LIST \|\| CT_STRUCT` tail — the arm the plan reads as three open cells — is
**dead code at every caller**. Probed directly, `List[List[Int]]`, `List[Set[Int]]` and `List[Pt]`
through a `let` re-bind never reach the copy at all; they go straight to
`stamp_list_elem_from_list_tid`, which has an arm for each:

```
[dbg:listelem] letladder var=g  val_type=4 ann=-1 expr_elem=4  sv_elem=0
[dbg:listelem] stamp ect=4  var=g  arm=tail
[dbg:listelem] letladder var=g2 val_type=4 ann=-1 expr_elem=20 sv_elem=0
[dbg:listelem] stamp ect=20 var=g2 arm=set set_ct=0 set_struct=
[dbg:listelem] letladder var=g3 val_type=4 ann=-1 expr_elem=5  sv_elem=-1
```

Adding those arms would have fixed nothing. **Confirmation #3 does not hold as written**, and the
three tickets it points at are not this function's.

### The real defect was the missing *stamp*, not the missing arms

The copy reads its source by **variable NAME**. Two of the three sites run
`stamp_list_elem_from_tid` on the next line, so their answer is the tid's regardless. The `collect`
site was the one with no stamp after it — and there a source that is not a variable has no `ScopeVar`
under that spelling, so every arm reads a fabricated flat default. `sv_tp` turns a missing inner into
`type_int()` (the plan's confirmation #1, which **does** hold), and the collect temp is left holding
`Option[Int]`:

```blink
type Box7 { items: List[Option[Map[Str, Int]]] }
let b = Box7 { items: [Some(m), None] }
let got = b.items.collect().get(0).unwrap().unwrap().get("k").unwrap()
```

```
[dbg:listelem] copy var=__collect_5 arm=option elem_ct=7 deep_tp=0
error[UnresolvedMethod]: unresolved method '.get' on type Map[Str, Int] in 'main'
error[UnresolvedMethod]: unresolved method '.unwrap' on type Option[Int] in 'main'
```

`deep_tp=0` is the fabrication, and `Option[Int]` in the second message is it surfacing. An
intervening `let` **hides** the whole thing — that ladder re-stamps from the tid one statement later
— which is why a corpus that collects into a `let` everywhere never caught it. A field source, a call
source, and consumption in the same chain are all required at once.

The fix is one call: let the tid lead at the collect site the way the let-ladders already do
(`bef42x` ordering). `stamp_list_elem_from_tid` reads the source **node**, so it is indifferent to
whether the source is spelled as a variable, a field or a call.

### The load-bearing set is now empty

Joining every `copy var=V arm=A` against a following `stamp ... var=V`, over
`tests/ examples/ src/ lib/std/`, in **both** build modes:

| | monolithic | archive-linked |
| --- | --- | --- |
| copy events | 3 → 9 | 3 → 9 |
| covered by a following stamp | 2 → 9 | 2 → 9 |
| **LOADBEARING (no stamp after)** | **1 → 0** | **1 → 0** |

(The event count rises because the new test contributes six.) Every arm agrees with the stamp that
supersedes it, and the one pre-existing LOADBEARING row — `test_1n9fhg`'s `__collect_481`, copied with
`deep_tp=0`, i.e. already carrying the fabricated `Int` — is now stamped `option` from the tid. That
row was a latent erasure in a passing test, the same class as the `list_1fold_0List_0Int` finding
above.

### What the one-line cure actually needs

`set_var_ty(dst, get_var_ty(src))` still does not work today, for the reason the whole plan exists:
`set_var_ty` writes a channel nothing reads yet. What is now true is weaker and more useful — **the
tid leads at all three call sites, and the flat case analysis survives only as the decline fallback.**
Deleting the body is Stage 4 work, gated on `sv.ty` governing, because a shape whose inner the tid
cannot spell still declines and those arms are then the only answer. Zero corpus events is not the
same claim as zero possible events (`feedback_corpus_sweep_is_not_coverage`).

Byproduct, unrelated to types and filed separately: a **named** function passed to a HOF emits the
unmangled Blink identifier (`.fn = keep` against a definition emitted as `blink_u_keep`), so the C
compiler sees an undeclared identifier — br `zpth5r`. Hidden because the corpus passes closure
literals, never a named fn.

## The first flip: the `for` binder's C declaration (br `bn3e6j`)

`copy_list_compound_elem` was a fix at a site where the tid was *added*. This is the first place the
tid was made to **govern an emitted C declaration**, which is what Stage 3's "flip authority" line
actually asks for, and it is worth recording because the flip turned out to be a *normalization*
rather than a bug fix — a distinction the census could not make on its own.

### The census, and the fact that it is one cell

Both build modes, `tests/` + `examples/` + `src/`, 291 rows each and identical:

```
ctype.forin.binder           agree=110 diverge=14 missing=0 unknown=0
ctype.forin.adapter_binder   agree=4   diverge=1  missing=0 unknown=0
```

129 events, **zero declines**, and all 15 divergences are the same shape — a plain, payload-less
enum element:

```
bucket=diverge site=ctype.forin.binder var=c ty=Col1n tidc=blink_Col1n emitted=int64_t
```

`missing=0` is the load-bearing number here, not `diverge`. It says the flat spelling contributed
nothing at these two sites that the tid could not also spell, which is the precondition Stage 4 needs
before deleting the flat arm.

### Codegen was disagreeing with itself, and the binder was the outlier

The reflex reading of a diverge row is "the tid is wrong here." It is not, and the way to tell is to
ask what codegen emits for the *same type in a different position*. From `.tmp/enum1.bl`:

```
338:    const blink_Col c = blink_Col_Red;      <- a let of that enum
347:        int64_t x = __next_2.value;          <- the for binder over List of it
```

A closure parameter of the same type is also declared `blink_Col1n`, and `blink_Col1n` is a real
emitted typedef. So two of three positions already spelled the enum and only the binder spelled the
ordinal. The tid agreed with the majority; flipping the binder makes codegen speak one language for
one type.

### Why this needed a characterization test rather than a red one

A plain enum **is** its ordinal, so the C conversion is implicit and free, and `int64_t` was not
producing a wrong program — it was producing an inconsistent one. Every way of consuming such a
binder was verified to work *before* the flip: passing it to a fn that expects the enum, storing it
in a struct-literal field of that type, using it as a `Map` key (with `@derive(Hash, Eq)`), matching
a **bare** variant, pushing it onto a `List` of the enum and reading back, and comparing against a
variant. `tests/test_bn3e6j_forin_binder_ctype_from_tid.bl` is those seven rows, and it passes on
both sides of the change by design. Red/green does not apply to a normalization; the guard does.

The bare-variant row is the one that could have broken and did not. A plain-enum binder's *identity*
reaches the body through `var_enums`, not through its C type (br `1n9fhg` / `k4thkq`), so changing
the declaration cannot disturb it — but that is an argument, and the test is the evidence.

### Reading the census after a flip

The probe's `emitted` column is documented as "what the caller is about to print." Once the tid
governs, that is no longer true at a flipped site, and the counter's meaning shifts with it:

- `diverge` now counts **corrections the tid applied**, not defects. It does *not* go to zero. After
  the flip the corpus reads `binder agree=112 diverge=19`, `adapter_binder agree=4 diverge=2` —
  *higher*, because `test_bn3e6j` adds six more plain-enum loops of exactly the diverging shape.
- `missing` is the number that must reach zero before the flat arm can be deleted.

This matters for how the plan's Stage 3 exit line — *"Drive the Stage 2 divergence counter to 0"* —
is read. It cannot mean "every flipped site reports `diverge=0`", which is what a first pass at this
unit assumed. The counter measures two *derivations* agreeing; a flip decides which derivation
reaches the *output*. Where the flat derivation is simply wrong about a spelling, those two pull in
opposite directions, and the counter goes to zero only when the flat derivation is **deleted**
(Stage 4), not when it is overruled. At a flipped site, `diverge` becomes a record of overruling and
only `missing` still carries information.

### The storage-position guard

`c_type_from_tid` answers a genuine `TyKind.Void` with `void` deliberately, and leaves the
position rule to its caller — legal in a return position, illegal in a storage one. A binder is a
storage position, so `forin_binder_ctype` declines a `void` spelling back to the flat answer. The
corpus contains no such row (`missing=0`, and all 21 post-flip divergences are the enum cell), so
this is a guard against a shape the sweep did not contain, not an observed cell — the same reason
`copy_list_compound_elem`'s body survives with zero corpus events
(`feedback_corpus_sweep_is_not_coverage`).

One tap that *was* unexercised is now covered: `ctype.forin.adapter_binder` had a single corpus
event before this, so the test's `filter` row over a plain-enum list exists to prove the lazy-adapter
declaration is genuinely reached rather than assumed — it shows up as the second `adapter_binder`
diverge row (`ty=KCol`).

## The speller that declined every monomorphized instance (br `tk8s0y`)

`bn3e6j` established that **`missing` is the number Stage 4 needs at zero**, so the next unit was
chosen by decline count rather than by divergence count. The largest cell was also the simplest: a
generic-struct or generic-enum *instance* declined unconditionally.

### The census, and the one line behind it

Both build modes, `tests/` + `examples/` + `src/`, identical:

```
ctype.enum_mono   agree=0     diverge=0 missing=16   <- 100% decline
ctype.struct      agree=23058 diverge=9 missing=141
```

`c_type_from_tid`'s Struct/Enum arm opened with `if tc_tid_child_count(t) != 0 { return "" }`. Every
`Box[Int]` / `Tree[Int]` tid has children — that is what makes it an instance — so the arm declined
exactly the tids that carry the most information.

### The ticket's own reasoning was half wrong, in the useful direction

The ticket argued the tid would need "a second, drift-prone namer" for mono stems. It does not.
`tc_tid_struct_mono_name` (`typecheck.bl:14027`) already produces the stem, already joins with `_0`
after `escape_mono_seg`, and is already byte-matched to the def side's `mangle_generic_name`
(br `cr4gqk`); it already recurses through struct-instance slots so `Box[Box[Int]]` keeps its `Int`,
and already admits `TyKind.Enum` (br `jjhnf3` / `82ajft` / `dbzy4r`). The whole widening is: call it,
prepend `blink_`, and decline on `""` or on an ICE seg (br `vbcw1e` — collapse, never interpolate).

`tests/test_ctype_from_tid_spelling.bl` carried a pin asserting the old decline, so `task ci` caught
this half of the argument as a hard failure rather than a review comment. That test now pins the three
stems (`blink_Box_0Int`, `blink_Pair_0Int_0Str`, `blink_Box_0Box_10Int`) and a companion case pins the
declines that must survive — a typevar slot and a metavar slot.

The second wrong expectation was measured, not argued: the ticket predicted module-qualified instances
would **keep** declining, citing br `q4etvt`. They do not. That caution applies to a struct-instance
*slot*, which `tc_tid_to_c_tag` strips; the *head* goes through `c_type_tag_for_struct(t.name)`, which
keeps the qualifier. `tests/test_q4etvt_cross_module_instance.bl` moved `missing=4 → agree=4` and
`tests/multifile/src/main.bl` `missing=3 → agree=3`, with no diverge row appearing anywhere — so the
tid spells `blink_test_1cross_1module_1generic_1fn_1helper_1CmgBox_0Int` byte-for-byte.

### Two of four seams flipped; the other two have nothing to read

`c_type_from_tid` has three non-probe consumers, and this widening put the tid **first** at two more
declaration sites (`bn3e6j`'s binder was the first):

- the `let` declaration's enum arm (`codegen_stmt.bl` ~`:4091`), now labelled three ways
  (`enum_mono_tid` / `enum_mono` / `enum`) so the census still says which authority governed;
- the match scrutinee temp (`codegen_stmt.bl` ~`:882`). Both flat recoveries there read a *name*; the
  tid reads the *node* and is indifferent to how the scrutinee was spelled — br `bef42x`'s ordering.

The shared gate `enum_instance_c_from_tid` lives in `typecheck.bl`, not in codegen, because three
emitters need the same answer for one binding — the declaration, the variant construction's
compound-literal cast, and the scrutinee temp — and a per-file copy is how a cell grows a fourth
spelling that disagrees with the other three.

The remaining two emitters were **not** flipped. `let t: ITree[Int] = INone` still emits
`(blink_ITree){.tag = 0}` and `void _v = …`: a payload-less variant carries no argument to infer the
instance from, and typecheck does not memoize the annotation-fixed instance tid on the value node, so
`tc_lookup_node_tid` declines there. A speculative reader was written at `codegen_expr.bl:686`,
measured to decline, and **removed** — dead code at a flipped site reads as coverage the census cannot
contradict. Filed as br `acrtns` with its MVCE and the two candidate fixes; the test row was swapped
for a passing annotation-plus-payload twin rather than left failing (xfail is spec-only, br `1c2zr6`).

### Measured result

`task regen` green, `task ci` green unpiped (`EXIT=0`, 691/691 test files, fmt 1600 passed / 88
skipped). Sweeps re-run in **both** modes; 159 detail rows each, and the only difference between the
two is one generated temp's counter (`_destr40` vs `_destr38`) on the same row.

```
                     before (post-bn3e6j)              after
ctype.enum_mono      agree=0     missing=16      site gone
ctype.enum_mono_tid  —                           agree=18    missing=0
ctype.struct  (mono) agree=23058 missing=141     agree=23190 missing=19
ctype.struct  (arc)  agree=22827 missing=141     agree=22959 missing=19
TOTAL missing        252                         114
```

138 declines cleared, and `ctype.enum_mono` disappeared as a *label*: no enum `let` in the corpus
falls back to the flat mono name any more. All 18 flipped rows are `agree`, so no emitted C changed —
which is the point. The flip's value is not a diff; it is the proof that the flat arm contributed
nothing recoverable at these sites, which is the precondition Stage 4 needs. The corpus contains no
row of the `acrtns` shape (that is why `diverge=0` here), so its absence is a gap in the corpus, not
evidence of correctness.

### The residual 19, and the one that was not this ticket

`ctype.struct missing=19` is unchanged in composition from the baseline — 18 `ty=?` rows and 1
`ty=Self` row, neither touched by this fix:

- **18 rows, `ty=?`** — tuple-typed `let`s in `test_44xww4` / `test_combining_iterators` where the
  site has *no tid at all*. A Stage-2 stamping gap, not a speller gap.
- **1 row, `ty=Self`** — `let cfg_err = ConfigError.from(io_err)` in `tests/test_from_trait.bl`. The
  impl method's declared return type `Self` was interned as a `TyKind.Struct` named literally
  `"Self"`, so `c_type_from_tid` declines (correctly — `blink_Self` is emitted by nobody) and the flat
  pair recovers `ConfigError` from the receiver name. The program passes today and will become a hard
  `cc` failure the moment the tid governs a plain-struct declaration. Filed as br `wc5q4g`; the fix
  belongs at the `Self` → impl-target substitution, not at the reader.

### Why the test is mostly "does it compile"

A wrong stem is not a wrong value — it is a reference to a typedef that was never emitted, i.e. a
`cc` failure. So `tests/test_tk8s0y_instance_ctype_from_tid.bl`'s 11 rows assert modestly and exist
mainly to *be compiled*: instance local, two instances of one base, the nested
`IBox[IBox[Int]]` that a head-only namer collapses to `Box_Box`, a two-arg `IPair[Int, Str]`, a
compound slot `IBox[Option[Int]]`, a generic-enum instance, the annotation-fixed twin, two for-in rows
(the binder consumer), a generic fn whose mono body must agree with its caller on the stem, and an
unsubstituted-typevar row that must keep declining.

## A pointer's pointee reached codegen through the annotation only (br `0dtbe6`)

The ticket's title names one cell — `Ptr[Float].deref()` prints `1` — and the fix found three,
in two different channels. That is the same lesson as `bn3e6j`: the ticket is a sighting, and
reading the source before naming a cause is what turns a sighting into the population.

### The three cells

`Ptr.deref()` set `expr_result_type = CT_INT` unconditionally (`codegen_methods.bl:5005`), so
`*(p)` was an `int64_t` whatever `p` pointed at:

| pointee | emitted | what happened |
| --- | --- | --- |
| `Float` | `const int64_t f = (*(p));` over `double* p` | **silent.** `1.5` printed as `1`, exit 0, no diagnostic |
| an `@ffi.struct` | `const int64_t v = (*(s));` | `cc`: *incompatible types … using type `blink_Pollfd`*, no Blink span |
| `Bool` | `void* b` | `cc`: *invalid use of void expression* — on `b.write(true)`, before any deref |

The third one is a different channel and is why the fix is not one line. The declaration branch
read the pointee out of the binding's own annotation and mapped the name through
`ptr_inner_c_type`, a fixed name table whose fallback arm is `_ => "void"` — and it has no
`Bool` arm. So `let b: Ptr[Bool]` declared `void*` while the tid said `int*`.

Sized-int pointees looked correct before the fix and still are, for a reason worth writing
down rather than filing as luck: `*(int32_t*)` promotes to `int64_t` losslessly, so the VALUE
survived. What `CT_INT` lost for them was the width and the signedness, which govern `/ < >`,
the overflow trap the spec promises for sized ints, and whether `.wrapping_*` resolves at all —
the same three consumers that made `tm1vbv`'s helper answer a CT instead of a C string.

### One question about two children, answered once

`tc_channel_elem_ct` (br `hgd2az`) already answered *"can a bare CT describe this child
completely?"* for a Channel's element. A Ptr's pointee is the same question about a different
child, so the body became `tc_tid_byvalue_ct` and both seams are now thin wrappers over it
rather than two copies with a drift risk. The rule dividing its arms is one line:

> A bare CT is a complete answer exactly when the type's C spelling does not depend on
> children.

Everything with children declines, and `-1` means *keep whatever you do today* — the same
contract, for the same reason, as `c_type_from_tid`'s `""`. `TyKind.Ptr` is in the declining
list, which reads oddly for a fix about pointers and is deliberate: `Ptr[Ptr[Int]]` derefs to a
perfectly good pointer, but the pointee of THAT pointer has nowhere to travel, so the next
`.deref()` would be back to guessing. What a nested pointer's declared shape should be is br
`mwsy85`.

### The tid leads, and this time it reverses an existing branch

The `ptr_ann` branch now asks `ptr_c_from_tid(decl_tid)` FIRST and keeps the annotation as the
fallback (`bef42x`'s ordering doctrine, `ptr_c_from_tid`'s `void*` decline as the gate). That is
a reversal of the branch's original order, not an addition alongside it — justified because both
channels describe the same binding, so they agree wherever the annotation's own table has an
arm, and the table's `_ => "void"` fallback is exactly where it does not.

### Measured

```
                     before (post-tk8s0y)          after
ctype.ptr_ann        agree=96   missing=0          agree=1     missing=0
ctype.ptr_ann_tid    —                             agree=101   missing=0
ctype.flat  diverge  9                             9
TOTAL missing        114                           114
```

Identical in both build modes. The flip changed **no emitted C in the corpus**: all 96
pre-existing rows agreed already, and one row still falls through to the annotation and agrees
there. That is not a null result — an all-agree flip is the proof that the flat arm contributes
nothing recoverable at that site, which is precisely the precondition Stage 4 needs before
deleting it. The `Bool` pointee is not a corpus shape at all, so the census could never have
found it (`feedback_corpus_sweep_is_not_coverage`); the test constructs it by hand.

`TOTAL missing` does not move, and the reason is worth stating plainly: the census cell for
`let f = p.deref()` is a `ctype.flat` `ty=?` row, i.e. the local has **no tid**, because
typecheck signs `is_null`, `offset` and `to_str` on a Ptr and deliberately omits `deref` and
`addr` (`typecheck.bl:9986`, pending br `mwsy85`). Codegen now spells the pointee correctly at a
site typecheck still has no type for. Closing that row means signing the method, which is the
next paragraph.

### The byproduct the census caught in the same hour

With `deref` answering the pointee, four corpus rows started diverging:
`ty=Int tidc=int64_t emitted=uint8_t`. All four are `let n: Int = <Ptr[U8]>.deref()` — a U8
stored into an `Int` local, which is a hard `TypeError` when written explicitly:

```blink
let u: U8 = 200
let n: Int = u          // error[TypeError] — sized ints are nominally distinct from Int
```

It is accepted through `deref` only because the method is unsigned, so the declared type is
never compared against the RHS. Two consequences, kept separate on purpose:

- **The emitted C** is now put back in agreement with the tid: `emit_let_binding` carries the
  reverse direction of a rule it already had — the annotation governs an integer local's
  declaration — which had nothing to reach until `deref` started answering a sized CT. Without
  it the local's arithmetic silently becomes U8 arithmetic under an `Int` annotation.
- **The missing compare** is br `axpq22`. Signing `deref` as the pointee type is not a decision
  on `mwsy85` (it records what codegen emits and what `lib/std` already depends on), but it IS
  stdlib-visible: `lib/std/libc.bl` reads `Errno(c_errno_location().deref())` off a `Ptr[I32]` in
  five places and would need the explicit conversion, so it needs the two-regen dance.

Verified that path end to end rather than assuming it: `libc.read_bytes(9999, 8)` still returns
`Err(Errno(9))` — EBADF — with the pointee now typed `I32`.

### Half (b) was already fixed

The ticket's second MVCE — `let taken = scope.take(p)` then `taken.deref()`, a `cc` escape —
printed `v=3` on the build that opened the ticket. Br `q3ssqw`'s `ptr_tid` declaration branch had
already closed it, and `test_ps5br9_ffi_scope_receiver_type.bl`'s mode-10 row said otherwise in a
comment. That row is now upgraded from asserting `is_null` to asserting the value. Verifying a
ticket's own premise against the current build is the cheapest step in this whole loop and it has
now paid twice in a row (`tk8s0y`'s module-qualified prediction was the other).

## The callback whose result had no type (br `msezvm`)

Three of the residual diverge rows were filed as class-(v) — *"3 `Void`-vs-`int64_t` at with-ptr
bindings, where typecheck and codegen disagree about the type"* — and parked as a known
disagreement. They were not a disagreement. Codegen was right and the tid was wrong, which is the
rarer direction and the reason this is a **typecheck** fix in the middle of a codegen collapse.

### The cause is one channel, and it is the only channel

`infer_type`'s `with_ptr` arm read the closure's RETURN ANNOTATION and nothing else:

```blink
let ret_str = node_return_type(cls_node)
if ret_str == "" { return TYPE_VOID }
```

So `b.with_ptr(fn(p) -> Int { b.len() })` was typed and `b.with_ptr(fn(p) { b.len() })` was not —
even though the body is walked either way, and a type error inside it is reported either way. The
spec signs the method `-> R` where R is the closure's result
(`sections/07_trust_modules_metadata.md:566`) and its own worked example at `:554` does **not**
ascribe the closure, so the spelling the spec writes is the spelling that did not work.

`Void` is not inert. Reproduced by running programs, not by reading code:

| written | result |
| --- | --- |
| `io.println("{n}")` | `error[MissingDisplayImpl]` — `Void` has no `Display` |
| `let t = n + 1` | `error[TypeError]`: binary `+`: `Void` and `Int` |
| `let m: Int = n` | `error[TypeError]`: declared `Int`, got `Void` |
| `assert_eq(n, 3)` | **accepted** |

The last row is why this survived: `cmp_operands_ok` (`typecheck.bl:8781`) fails open on a `Void`
operand, and its comment names this exact call — *"an un-annotated closure return flowing through
Bytes.with_ptr types as Void"*. `tests/test_bytes_with_ptr.bl` rides entirely on that fail-open.
It is left in place: `with_ptr` is not the only `Void` producer, so narrowing it is its own change
with its own corpus.

### Why the obvious fix is a no-op, and the less obvious one double-reports

The first attempt — answer the arm from the closure body — changed nothing after a full regen, and
the reason is pass ORDER. `tc_check_body`'s `LetBinding` arm calls `infer_type(val)` and **then**
`tc_check_body(val)`. The body's tail is not walked, so not memoized, until one step after
`infer_type` had to answer.

The repair for that is not "infer the body here", and this is the fact that shaped the whole fix:

> `infer_type` is a **write-through memo, not a read-through cache**. `infer_type` calls
> `infer_type_uncached` unconditionally, and it **reports as a side effect**.

A speculative re-inference of the closure body would therefore report every diagnostic inside it a
second time. Br `bfq7nf` already built the mechanism for asking this class of question without
adding diagnostics — `tc_scoped_value_memo`, which reads what the in-scope walk recorded *one step
late*, and the `LetBinding` recovery that fires when the inferred tid is `TYPE_UNKNOWN`. So:

- the `with_ptr` arm **DECLINES** to `TYPE_UNKNOWN` for an unascribed closure, instead of
  answering `Void`;
- `tc_scoped_value_memo` gains a `MethodCall` arm that reads the closure body's tail, gated on the
  node having no answer of its own (so the ascribed spelling keeps its annotation verbatim) and on
  the receiver actually being `Bytes` (so a user method of the same name is untouched);
- the existing recovery fills it in once the walk has run.

Two shapes come along for free, because `tc_scoped_value_memo` already handles them structurally:
a body that is a bare `match` (br `3c4g71`'s arm) and one that is a bare `if` (br `wnbsen`'s).
`r` in `tests/test_9tmsmt_with_ptr_match_body.bl` is the corpus row for the first, and both are
pinned — a narrower recovery that only read a simple tail would still pass every other row.

### Measured

```
                     before (post-0dtbe6)         after
ctype.flat  agree    407754                       408050
ctype.flat  diverge  9                            6
ctype.flat  missing  84                           86
TOTAL diverge        45                           42
TOTAL missing        114                          116
```

Identical in both build modes, 158 rows each. The accounting is exact, row by row: the three
removed diverge rows are `n` and `addr` (`tests/test_bytes_with_ptr.bl:6`/`:13`) and `r`
(`tests/test_9tmsmt_with_ptr_match_body.bl:8`). `n` and `r` now **AGREE**. `addr` **DECLINES**,
which is the `+2 missing` — `p.addr()` is deliberately unsigned in typecheck's `Ptr` arm
(`typecheck.bl:9986`, pending br `mwsy85`/`axpq22`), so the body has no type to read and the
helper returns `-1` rather than guessing. A decline is the honest cell: codegen keeps what it does
today.

That empties class-(v)'s three-row with-ptr entry. **All 6 remaining `ctype.flat` diverge rows in
the corpus are now the one `Bool + Bool` sum** at `src/codegen.bl:452`
(`let __emit_modes = (a != 0) + (b != 0) + (c != 0)`), filed as br `4vrmqe` — and reading that row
by hand rather than trusting the census label was worth the ten minutes, because the census
understated it. `ty=Int tidc=int64_t emitted=int` reads like a width divergence. It is not:

```blink
let s = (a != 0) + (b != 0)
assert_eq(s, 2)             // PASSES
io.println("s={s}")         // prints "true"
```

The value is genuinely 2 and the emitted C is `const int s = ((a != 0) + (b != 0));`, but the
`Display` dispatch is chosen from codegen's **flat** type, which is `Bool` — so the same binding
compares equal to `2` and prints `true`, in the same program. Nonzero prints `true`, zero prints
`false`, so it is silent and value-dependent. That the census could only see the width is the
point: a diverge row is a *sighting*, and the two answers behind it have to be read.

The compiler's own use of the expression is `if __emit_modes > 1`, which sees the int and works, so
this is not a self-host miscompile — another instance of `feedback_self_host_doesnt_catch_user_codegen_bugs`.

### The byproduct

Writing the `Void`-body row of the test produced a `cc` escape that has nothing to do with
`with_ptr`: `let _ = <Void expression>` emits `const void _unusedN = 0;`. `let _ =
io.println("x")` reproduces it with no `Bytes` in the program at all — filed as br `2q76x9`, and
the test row is written in statement position with a comment saying why.

## The type that was not in the enum, and segfaulted (br `88sfaz`)

`ctype.handler` was picked next because it is the **only site in the whole census with `agree=0`** —
7 rows, every one a decline. A site the tid has never answered for is the shortest route to whatever
the tid cannot say. What it could not say turned out to be the type's own identity, and the cost was
a memory-safety hole reachable from ordinary safe Blink: no `@trusted`, no `@ffi`, no unsafe
construct, `blink check` reporting `ok`, and the binary dying with SIGSEGV.

```blink
effect Small { effect Only { fn one(a: Str) } }
effect Big   { effect Many { fn first(a: Str)  fn second(a: Str)
                             fn third(a: Str)  fn fourth(a: Str) } }

fn make_small() -> Handler[Small] { handler Small { fn one(a: Str) { io.println(a) } } }
fn take_big(b: Handler[Big]) { with b { big.fourth("hello") } }

fn main() {
    let s = make_small()
    let laundered: Int = s      // accepted
    take_big(laundered)         // exit 139
}
```

### The cause is not a missing arm — it is a missing member

Every earlier cell in this document was a channel that dropped information. This one had no channel
because it had no **type**. `Handler` was not a `TyKind`. `resolve_type_parts` (`typecheck.bl:2857`)
has arms for List / Option / Result / Map / Set / Handle / Channel / Template / Fn and then a tail:

```blink
make_typevar(name)
```

`Handler[E]` fell to that tail, and the `Fn` arm three screens up already names what that costs, in
one line of its own comment: **"a bare typevar unifies with anything."** That is the same sentence
that describes the unsoundness br `nz7drz` fixed for `Fn` (`let bad: fn(Int) -> Int = 5` typechecked
clean). So every handler type compared equal to every other type in the language.

`TyKind.Handle` is *not* this type. That is the async task `Handle[T]`. `handler[E]` is a parser
pseudo-type named `"Handler"` (`parser.bl:1478`) carrying the effect in `node_elements`, and
`infer_type_uncached` had no `HandlerExpr` arm either — so neither the **annotation** nor the
**value** had a type.

### Why the vag3wc audit could not have found it

The comment above `make_handle_type` is an explicit audit of `TyKind` members that are never
constructed: Closure (deleted), Iterator (deferred to `qzdz2e`), Ptr (`w13xgb`). It is a careful,
complete list — and it missed this, unavoidably, because **`Handler` was not a member to be found**.

That is the transferable lesson for the rest of Stage 3, and it is recorded in the audit comment and
in the header of `tests/test_vag3wc_channel_handle_iterator_tids.bl` so the next reader hits it:

> *"Which enum members are unconstructed" is a strictly weaker question than "which annotations
> reach the typevar tail."*

### Three fail-opens compose into the crash, and each is independently a bug

1. `let laundered: Int = <Handler[E]>` is **accepted** — the declared type is never compared against
   a handler-typed RHS. Codegen then emits `void* laundered = s;`, because the vtable side-channel is
   keyed by **variable name** (`get_var_handler_vtable_type`, `codegen_stmt.bl:4161`) and has no
   entry under the new name, so it takes its `void*` arm.
2. **`void*` converts implicitly to any object pointer in C**, which defeats the `cc` backstop that
   catches the same mistake without the `Int` hop.
3. The callee installs the pointer into **its own** effect slot from its own annotation, and effect
   dispatch is by **slot index** (`__ev->ue_big->fourth(...)`). A one-function vtable receiving a
   four-function dispatch reads a function pointer past the end of the struct and calls it.

Rung 2 is why this could not be left to the C compiler: it is exactly the `Int` hop that turns a
`cc` type error into a segfault.

Two quieter members of the same family, both reproduced by running them:

- **Same-size launder** — with the two vtables the same width it does not crash. It ran, exited 0,
  and printed `[H] boom`: `metrics.counter("boom", 12345)` dispatched through the IO handler's
  `print(const char*)`, discarding the `Int` argument.
- **A lying annotation** — `let bad: Handler[Metrics] = make_io_handler()` compiled, ran, exited 0
  and **did nothing**. Codegen ignored the annotation, followed the RHS effect, installed into
  `.io`, and `metrics.counter` inside the `with` went to the default metrics vtable. A program that
  silently does not do what it says.

### The effect travels in the *name* slot, and that is not a shortcut

```blink
pub fn make_handler_type(effect_name: Str) -> Int {
    ty_intern_simple(TyKind.Handler, effect_name, -1, -1)
}
```

This departs from `make_handle_type` / `make_channel_type`, where `name` is the type's **own** name
and the parameter is a child tid. Those two can do that because a Channel's element **is a type**. An
effect is not, so there is no tid for `inner1` and the effect has to travel in the only other slot
the entry has. It is what the intern key discriminates on — precisely the identity this fixes — and
`tc_tid_handler_effect` hands it back so `resolve_effect_vtable` stays on the codegen side where the
`ue_effects` registry lives.

The consequence is that `Handler` is the one kind whose parameter is deliberately **not** a tid, so
`tc_tid_child_count` answers `0` rather than "1 that is always -1". There is no type down there to
erase.

### Sub-effects are root-compared, and that is representationally exact

`types_compatible` compares `tc_handler_effect_root` and not the full name, so `Handler[IO.Print]`
and `Handler[IO]` are interchangeable. This is not a loosening chosen for convenience — it is the
equivalence the C representation **already** uses. `resolve_effect_vtable` (`codegen_types.bl:1455`)
maps `IO`, `IO.Print`, `IO.Log` and `IO.Eprint` all onto `blink_io_vtable`, and groups every user
effect by `ue.name` plus `starts_with("{ue.name}.")`. Which is why it cannot reject a program that
compiles today — `lib/std/testing.bl` returns `Handler[IO.Log]` / `[IO.Print]` / `[IO.Eprint]` into
`Handler[IO]` positions.

Measuring *why* it is exact was worth the five minutes, because it settles a question that would
otherwise read as unfinished. A sub-effect handler emits the **parent's full-size vtable**, copying
the default and overriding only its own slots:

```c
static blink_ue_metrics_vtable blink_ue_metrics_vtable_default = {
    ..., blink_ue_metrics_default_get_counter };
...
blink_ue_metrics_vtable __handler_vt_0 = *__handler_0_outer;   // copy, then override
```

So two handler types with the same root effect have literally the same C type, slot-index dispatch
cannot run off the end of one, and **this is why the crashing MVCE needed two different effects.**
Both variance directions run clean today (exit 0); a `Handler[Metrics.Emit]` in a `Handler[Metrics]`
position returns the default stub's `0` from `get_counter` with no diagnostic. That is a silent
wrong answer, not a safety hole, and it is an effect-semantics question rather than a type-identity
one — filed as br `eegt61` with the measurement.

### Stage 0's net earned its keep twice in one change

Adding the enum member failed the compile at **exactly six sites** in `typecheck.bl`, and every one
of those sites' own governing comment dictated its answer:

| site | arm | why |
| --- | --- | --- |
| `tk_to_ct` | `CT_HANDLER` | codegen has carried it since handlers landed; the arm makes the two universes agree rather than adding knowledge |
| `tc_tid_child_count` | `0` | the effect is a name, not a child |
| `tc_tid_child` | `-1` | unreachable given the count, enumerated so a kind that *gains* children cannot slip through |
| `tc_tid_byvalue_ct` | `-1` | "a bare CT is a complete answer exactly when the C spelling does not depend on children" — a handler's depends on the effect |
| `c_type_from_tid` | `""` | the vtable name needs codegen's `ue_effects`; see below |
| `tc_ann_head_matches_tid` | `false` | the identical reason `TyKind.Fn` is `false` — element-index-to-child-index alignment does not hold when the element is not a type |

It then failed **four test files** that carry their own independent `TyKind` enumeration
(`test_e0wmt6`, `test_nz7drz`, `test_tc_tid_structural_accessors`, `test_vag3wc`). That second net
exists precisely so a variant cannot appear or disappear without a deliberate edit, and it worked.

### The census did not move, on purpose — but the rows did

Measured over `tests` + `examples` + `src`, **identical in both build modes**. On the same basis
(excluding the new test root) the census is unchanged: `ctype.handler` agree=0 diverge=0 missing=7;
TOTAL diverge=42, missing=116. The `+5` handler rows are entirely the new test file.

That is the scope split stated up front, not a shortfall. `c_type_from_tid` still declines, because a
handler's C type is the **vtable struct of its effect** and the effect→vtable map reads codegen's
`ue_effects` registry — and `typecheck` imports `codegen_types`, not the reverse. Spelling it in
`typecheck` would mean duplicating the grouping rule, which is how a cell grows a second speller that
disagrees with the first.

> **Correction, added when br `t7xf9y` closed the cell.** The paragraph above is wrong, and it is left
> standing because it is the most instructive error in this document. "`typecheck` imports
> `codegen_types`, not the reverse" is the import direction that makes the call **legal** — it is the
> premise of the fix, read as if it were the obstacle. `c_type_from_tid` already reaches
> `c_type_c_name` and `is_transparent_newtype` across that same edge (`typecheck.bl:3`), so there was
> never a grouping rule to duplicate: `resolve_effect_vtable` gets **consulted**, exactly as the
> transparent-newtype arm consults its predicate. The forward pointer to br `22zk5f` below inherited
> the error and sent the flip to the wrong file. See *"The handler that came out of a list"*.

What *did* move is the evidence that the identity landed:

```
BEFORE: bucket=decline site=ctype.handler var=h  ty=Handler          emitted=blink_io_vtable*
AFTER:  bucket=decline site=ctype.handler var=h  ty=Handler[IO]      emitted=blink_io_vtable*
        bucket=decline site=ctype.handler var=h2 ty=Handler[Metrics] emitted=blink_ue_metrics_vtable*
```

All 12 rows: the tid's effect matches the emitted vtable **1:1**. The tid now carries exactly what
the speller needs; only the speller's *reach* is missing. `codegen_stmt.bl` imports both modules and
already owns the handler declaration branch, so `resolve_effect_vtable(tc_tid_handler_effect(tid))`
is spellable there — filed as br `22zk5f`. That flip also retires a name-keyed registry, which is the
same keying that produced rung 1 of this crash.

### What is deliberately not pinned

A `Handler[E]` through a generic fn (`fn ident[T](x: T) -> T`) trips the I0001 tripwire — *the
def-side slot resolved to `T` at codegen site `mono_fn_signature_ret`*. That is the fail-closed
backstop working, so a handler simply cannot travel through a generic yet. Pinning an ICE as an
expected outcome would make it load-bearing, so the corpus says so in a comment and the ticket
carries the detail.

## The handler that came out of a list (br `t7xf9y`)

A handler stored in a container and read back out could not be used:

```blink
let hs = [mk_io()]
let h = hs.get(0).unwrap()
with h { io.println("via list") }
```

```
error: assignment to 'blink_io_vtable *' from 'int64_t' makes pointer from integer without a cast
```

A C compiler error with no Blink span to report it against. The census had already flagged the cell —
`bucket=decline site=ctype.flat var=h ty=Handler[IO] tidc=- emitted=int64_t` — the tid knew
`Handler[IO]`, the emitted declaration said `int64_t`, and `tidc=-` said the speller had no answer.

### One erasure, three surfaces

The cause is a single fact: **a container element's `CT_*` is erased to `CT_INT`.** So `val_type` for
`h` is not `CT_HANDLER`, the declaration chain's `CT_HANDLER` arm is skipped, the `ScopeVar` handler
registration at `codegen_stmt.bl:3513` is skipped, and the binding falls all the way to the final
`flat` else, which prints `c_type_str(CT_INT)`.

The ticket named the declaration. Writing the corpus found that the declaration was **one of three**
surfaces on that fact, and that fixing only it produces programs which compile and are still wrong:

1. **The declaration** printed `int64_t` — the reported error.
2. **The `with` install slot** came from a stale global, and installed the *wrong vtable*.
3. **The effect** could not be recovered from either flat channel, so the second operand of a
   two-handler `with` was discarded as a bare statement.

### Surface 2 is br `88sfaz`'s crash shape with no annotation lie

`cg_handler_vtable_field` is written by `emit_expr` only for a handler **construction**
(`codegen_expr.bl:1618`) or a call whose return is registered (`codegen_expr.bl:5312`) — **never by a
bare `Ident`**. The with-operand loop read it *before* clearing it, and the `let` clears it only on
its `CT_HANDLER` path. Measured:

```blink
let ios = [mk_io()]       // emit_expr leaves field="io"
let ms  = [mk_metrics()]   // ...then field="metrics", is_ue=1 — and nothing clears it,
                           //    because both of these bindings are CT_LIST, not CT_HANDLER
let hi = ios.get(0).unwrap()
let hm = ms.get(0).unwrap()
with hi, hm { io.println("both"); metrics.counter("both", 1) }
```

The **IO** handler was installed into the `ue_metrics` slot, and `hm` was then emitted as a bare
`hm;` statement and dropped. `metrics.counter` dispatches by slot index through an IO vtable — which
is precisely the wrong-vtable-in-a-slot shape that made br `88sfaz` a P0, reached here with **no
`@trusted`, no `@ffi`, and no annotation lie anywhere in the program.** Two things stopped it being a
crash rather than a diagnostic: the `handler_type == CT_HANDLER` gate, and `-Wint-conversion` being
an error in the generated build. Neither is a Blink diagnostic, and neither would have held if the
two effects had happened to share a root.

The fix is to clear the globals **before** `emit_expr`, so the channel means "what *this* operand
set" rather than "the last thing that set it". Filed br `td3mrg` for the identical read on
`cg_handler_cleanup_var` / `cleanup_fn` rather than moving those speculatively — no MVCE for them
yet, and that ticket says so.

### Surface 3 is where `sv.ty` stops being a cross-check

Recovering the slot needs the *effect*, and neither flat channel can name it for an erased binding.
My first attempt asked the operand node for its tid and did not fire. The reason is measured, not a
preference: typecheck's `WithBlock` arm routes each operand through `tc_check_body`
(`typecheck.bl:11900`), and for a bare `Ident` that walker has nothing to do — it never calls
`infer_type`, so no tid is ever memoized against the node and `tc_lookup_node_tid(item)` answers
`-1`.

The tid stamped on the **binding** at its `let` — whose node *is* inferred — is the only channel that
has it:

```blink
let h_eff = tc_tid_handler_effect(tc_tid_resolved(tc_tid_subst_mono(get_var_ty(handler_str), ...)))
```

Every Stage-3 unit so far has used `sv.ty` as a *better* answer than the flat fields. This is the
first one where it is the **only** answer, and where the flat channel is not merely lossy but absent.

### The spelling belongs in typecheck, and the earlier note said otherwise

The new arm is in `c_type_from_tid`:

```blink
if k == TyKind.Handler {
    let vt = resolve_effect_vtable(tc_tid_handler_effect(t))
    if vt == "" { return "" }
    return "{vt}*"
}
```

This is the correction described in the box under *"The census did not move, on purpose"*. Both the
88sfaz note and br `22zk5f` argued this could not live in typecheck because `resolve_effect_vtable`
reads codegen's `ue_effects` registry and "typecheck imports codegen_types, not the reverse" — the
import direction that makes the call legal, mistaken for the one that forbids it. The registry
filling *during* codegen is not a hazard either, for the same reason it is not one for
`is_transparent_newtype`: every caller of `c_type_from_tid` is a codegen emit site or the `ctypediv`
probe that runs beside them, so no caller can observe the empty registry — and if one ever did, the
effect resolves to no vtable and the arm declines, which is the right answer for *"I cannot spell
this yet"* rather than a wrong C type. br `22zk5f` closed as subsumed.

The declaration branch is ordered **after** every arm the flat channel already governs, per br
`0rmamy` / br `q3ssqw`. `handler_c_from_tid` deliberately carries **no equality decline**, unlike
`ptr_c_from_tid`'s `void*` and `enum_c_from_tid`'s `int64_t`: those guard against a tid that knows no
more than the flat fields, but the flat path cannot spell a vtable type *at all* unless it already
took the `CT_HANDLER` arm — which is ordered first. So every non-`""` answer here is a binding that
would otherwise have been declared from an erased CT. The cast is load-bearing, not cosmetic: a
container round-trips the handler pointer through an `(int64_t)(intptr_t)` slot, so at the
declaration the initializer really is an integer expression.

### One row compiled, ran, exited 0, and was silently wrong

```blink
let h2 = h
with h2 { io.println("via copy") }
```

This built and ran clean, and printed `via copy` where a correct dispatch prints `[H] via copy` — the
handler was never installed and the call went to the ambient default stub, which returns without
doing anything. Same cause as surface 3: a bare `Ident` sets no global, so the copy's
`set_var_handler` recorded an empty field.

I nearly recorded this as a regression of my own change, because the *pre-fix* probe had printed
`via copy` and I read that as working. It was not. **A user effect's default stub returning silently
means `assert(true)`-style rows cannot tell a correct dispatch from no dispatch at all** — so every
row in the corpus that claims a handler ran asserts on its *output*, and the five "already right"
pins were each verified by running them pre-fix and reading the prefix, rather than assumed.

### What is deliberately not pinned

`for h in hs` and `Some(mk_io())` still fail, on a different cause: the Option carrier erases its
inner to `void`, emits an undeclared `blink_Option_void`, and disagrees with the `blink_Option_int`
unwrap temp, so the pointer is built with `blink_u_mk()` and discarded. That is br `rh7rhf`, one cell,
noted in the corpus rather than pinned.

### Measured

Over `tests` + `examples` + `src`, **identical in both build modes** (monolithic and
`--link-archive`):

```
ctype.handler      agree=0  diverge=0 missing=12   ->  agree=16 diverge=0 missing=0
ctype.handler_tid  (new cell: the declaration branch)  agree=6  diverge=0 missing=0
TOTAL              diverge=42 missing=116          ->  diverge=42 missing=109
```

**The first Stage-3 cell to close completely rather than shrink.** `diverge` is unchanged, as it
should be: nothing here touched a shape the flat channel was already spelling.

`tests/test_t7xf9y_handler_from_container.bl`, 14 rows: five for shapes that did not compile (List,
Map, user-effect List, two effects in one program, non-zero index), four run-mode rows asserting the
handler body actually ran, five regression pins. `task ci` green — 695 test files, 695 passed, 0
failed; `fmt` 1608 passed, 0 failed.

## The `with` operand that was never typed (br `resqj9`)

One commit after br `t7xf9y`, probing the *next* container shape turned up a worse row than the one
the ticket was about:

```blink
type Env { h: Handler[IO] }
let e = Env{h: mk()}
with e.h { io.println("via field") }
```

This compiled, ran, and exited 0, printing `via field` where a correct dispatch prints
`[H] via field`. **Nothing was installed.** The emitted C says so:

```c
blink_Env _s0 = { .h = blink_u_mk() };
const blink_Env e = _s0;
{
    e.h;                                 // the operand, emitted for effect and dropped
    __blink_ev.io->print("via field");   // ambient default, not the handler
}
```

A silent wrong answer, which is why this is P1 while `t7xf9y` — which failed loudly in the C
compiler — was P2. The field storage is fine: the field really is `blink_io_vtable* h` holding a real
GC-allocated vtable. Only the operand *form* was at fault, and one extra binding proved it —
`let hl = e.h; with hl { … }` was already correct.

### My first fix was wrong, and the probe said so in one line

`t7xf9y`'s comment blames the missing operand tid on `Ident` specifically, so a field access looked
like it should already work. I added the node-tid recovery in codegen, regenerated, and all four rows
still failed. A `dbg_trace` on the with-operand loop:

```
[dbg:withop] str=e.h ct=21 node_tid=-1
```

Two facts in that row. **`ct=21` IS `CT_HANDLER`** — the flat channel knew perfectly well it was
looking at a handler; what it could not do was *name the effect*, because the vtable field is keyed by
variable name and `e.h` is not one. And **`node_tid=-1`** — `tc_check_body` has no `Ident` arm *and no
`FieldAccess` arm*. It **walks** the operand and never **types** it, so every `with` operand in the
corpus landed on a silent fallthrough. The narrowing to `Ident` was wrong, and this ticket inherited
it from the previous one.

### The fix is one line, in typecheck

```blink
tc_check_body(wh_item2)
let _memoized = infer_type(wh_item2)
```

`tc_check_body` stays and runs first: for an inline handler operand it routes to the `HandlerExpr` arm
that walks the method bodies (br `pgc3d9`), which `infer_type` does not do. They are complements.

Reconstructing the field's type in codegen instead — walking to the base variable's struct tid and
looking the field up — would have been codegen inferring a type again, which is the thing this
collapse exists to stop. It also makes the spec's own rule (`sections/04_effects.md:1102`, *"the
compiler checks `Handler[E]` first, then `BlockHandler`"*) something a later change can enforce
against a **type** rather than against a C string.

### It retires a channel instead of adding one

With the operand typed, the **operand node's** tid subsumes the `get_var_ty(handler_str)` **binding**
tid that `t7xf9y` had added one commit earlier. Measured with a `withop` probe over
`tests` + `examples` + `src`, 27 operands reaching the recovery:

```
ZERO rows where the binding tid answers and the node tid does not
every row get_var_ty resolved, the node resolves to the SAME effect
+3 rows only the node can reach   (e.h, b.io, b.metrics)
```

So the binding recovery is **deleted**, and codegen asks one question in one place. Keeping it "just
in case" would leave a second authority for the same question with no row to justify it. `t7xf9y`'s 14
rows pass unchanged — what changed is which single channel answers them.

The three corpus operands that answer *neither* channel were checked rather than assumed:
`tests/test_with_parse.bl` declares `fn make_handler() -> Int`, so they are not handlers at all and
the discard arm is right for them. The `_s*` / `_sr*` temps are `BlockHandler` struct values, handled
by the arm below.

Deliberately **not** touched: the flat `handler_type == CT_HANDLER` → `get_var_handler_vtable_field`
recovery still runs first. The probe suggests the tid would answer for its rows too, but taking rows
away from an arm an earlier ticket wired correctly needs its own measurement and its own ticket, per
br `0rmamy`.

### Measured

`task ci` green — 696 test files, 696 passed, 0 failed; `fmt` 1610 passed, 0 failed.
`tests/test_resqj9_with_field_operand.bl`, 6 rows, red before / green after: four failing rows (field
operand, user-effect field operand, two field operands of *different* effects, a field two struct
levels deep) and two pins that passed both before and after. Every row asserts on **output**, since
compilation was never the problem.

The census does **not** move, in either build mode: `diverge=42 missing=109`, unchanged. That is the
honest reading of this unit — it was a **dispatch** fix, not a spelling one. The `ctypediv` probe
watches which channel spells a C *type*, and every row here already spelled `blink_io_vtable*`
correctly; what was wrong was the *slot* the handler got installed into, which no `ctype.*` cell
observes. Worth stating plainly, because a Stage-3 unit that closes a P1 while leaving the counter
untouched is otherwise easy to read as having done nothing.

### 3nf9fr — `Option[T].unwrap()` floors every pointer-shaped inner to `CT_INT`

**Found by splitting a bigger ticket, not by the census.** br rh7rhf claimed three defects; its third —
"the unwrap temp is `blink_Option_int`, which does not match the value's own declared type" — reproduces
with **no handler and no effect anywhere**, so it came out as its own unit and rh7rhf blocked on it.

`unwrap_scalar_ct` (`codegen_types.bl:6437`) passed through only Float/Char/Bool/sized-int and floored
everything else to `CT_INT`. The **construct** side was already correct — `Some(handle)` emits a
properly typedef'd `blink_Option_handle` — so only the unwrap disagreed with it:

```c
blink_Option_int _ounw_2 = o;              // wrong carrier: cc `invalid initializer`
const int64_t h2 = _ounw_2.value;          // wrong decl: int64_t, not blink_handle*
```

**This is the same defect the tail's own comment claims to have closed.** That comment describes
widening the arm from Float/Char to the sized ints "an escape with no Blink span, for eight inner
types" — the pointer-shaped kinds were never added. Worth naming, because the comment reads as if the
class were finished, and that is exactly why nobody looked again.

The fix is one line, and the shape of it is the point:

```blink
if c_type_tag(ct) != "void" { return ct }
CT_INT
```

**Derived, not enumerated.** The obvious repair was to add `CT_HANDLE`, `CT_STRINGBUILDER`,
`CT_CHANNEL`, `CT_ITERATOR`, `CT_PTR`, `CT_TEMPLATE` to the pass-through list — but an enumerated list
is precisely what went stale the first time. Asking `c_type_tag` instead makes the predicate agree with
`emit_option_typedef` **by construction**: an inner is passed through exactly when a carrier for it can
exist, because both sites now consult the same speller. It also subsumes the old list rather than
extending it.

The two test rows fail in **different layers**, which is the useful part of having both: `Option[Handle]`
fails in cc (a wrong C type against a right one), `Option[StringBuilder]` fails in *Blink* with
`unresolved method '.write' on type StringBuilder` — once the inner is erased to Int the unwrapped value
is not a StringBuilder at all. A fix that only silenced cc would leave the second row red.

**The floor has no working witness, and that is the finding.** I tried twice to pin the `CT_INT` floor
and was wrong twice. First with Duration/Instant, on the reasoning that their C representation is an
integer — but they are *nominal types with methods* (flooring loses `.to_ms()`), and their construct
side already emits the undeclared `blink_Option_void` before the unwrap is reached (→ br kxe0s2). Then
with `Option[Void]`, the one inner whose `"void"` tag comes from a real arm rather than a fall-through
— same failure, same line. So the floor is reached **only** by inners `c_type_tag` cannot name, and
every such inner already dies at construction. It cannot be pinned by any compiling program and cannot
be blamed for anything; passing those inners through would spell the same undeclared name in the temp.
The guard becomes load-bearing only once rh7rhf gives `c_type_tag` its missing arms. *"Its C
representation is an integer"* is not the same claim as *"it is an Int"*, and neither is the same claim
as *"the carrier exists."*

`task ci` green — 697 test files, 697 passed, 0 failed; `fmt` 1612 passed, 0 failed.
`tests/test_3nf9fr_option_unwrap_pointer_inner.bl`, 6 rows. Red was maximal: the in-corpus row made the
whole file fail to **build**.

The census does not move, in either build mode: `diverge=42 missing=109`, per-cell identical to the
resqj9 baseline. Correct by construction — **no `ctypediv` cell observes the unwrap temp's carrier.**
The probe watches which channel spells a type at a *declaration* site; this disagreement is between two
spellings of the *same variable's* carrier. Second unit in a row to close a real defect without moving
the counter, so it is worth saying once more: the counter is a coverage instrument, not a scoreboard.

**Two byproduct tickets, both with MVCEs.** br y50dak — `Handle[T].await()` loses `T`, emitting
`const void _unused = (int64_t)(intptr_t)__await_3();` for a *discarded* await, with no Option in the
reproduction; the Handle row omits `.await()` for that reason, so it does not go red for a defect this
unit does not own. br kxe0s2 — `Some(Duration)` / `Some(Instant)` emit the undeclared
`blink_Option_void`; same missing-arm mechanism as rh7rhf, no handler involved.

### rh7rhf — a `Handler[E]` in a carrier named a C type that did not exist

**Two arms, one on each side of the collapse.** The ticket read as three defects and the census read as
one; both were wrong, and the census was the one that settled it. From br 3nf9fr's sweep:

```
bucket=decline site=ctype.option var=o  ty=Option[Handler[IO]]      tidc=- emitted=blink_Option_void
bucket=decline site=ctype.option var=om ty=Option[Handler[Metrics]] tidc=- emitted=blink_Option_void
```

`tidc=-` is the part no amount of reading the ticket would have given me. **Both** spellers were
missing an arm: `c_type_tag` had no `CT_HANDLER` case and fell to its `else { "void" }` default, and
`tc_tid_tag_at` had no `TyKind.Handler` case and answered `ICE_SEG_UNHANDLED_KIND`. Fixing only the
flat side would have produced a compiling program with the tid channel still silent — i.e. a cell the
collapse could never take authority over, which is the actual Stage-3 deliverable.

The flat default is what turned one missing arm into an undeclared type: naming the carrier
`blink_Option_void` made `emit_option_typedef` return early on its `tag == "void"` test, so the name was
**referenced and never typedef'd**. That also explains the ticket's first two claims — the `Some(h)`
failure and the `blink_ListIterator_void_next` failure — as one line, because `tp_carrier_tag` funnels
into `c_type_tag` for every non-container kind.

**The asymmetry between the two spellers is the reusable finding.** `tc_tid_tag_at` fails **closed** on
an unhandled kind, deliberately, so that a missing arm cannot be mistaken for a genuine Void.
`c_type_tag` has no such split — its default *is* `"void"`. Same omission, one loud and one silent, and
the silent one is the one that shipped a broken program. Worth carrying into Stage 4: the flat speller's
default is not merely less precise than its tid twin, it is *differently failing*.

Tag: `handler`, **effect dropped**, on precedent rather than preference. Every parameterized non-struct
kind already drops its parameter (`Handle[T]`→`handle`, `Channel[T]`→`channel`, `Iterator[T]`→`iter`,
`Ptr[T]`→`ptr`, whose own comment says so). For Handler the drop is not even a choice: `TyKind.Handler`
carries the effect in the entry's **name** slot, not as a child tid (br 88sfaz), so `tc_tid_child_count`
is 0 and there is no inner tid to recurse into. Precision is recovered from the tid by
`c_type_from_tid`'s Handler arm (br t7xf9y), and `c_type_str(CT_HANDLER)` is already `"void*"`, so C's
implicit `void*`↔object-pointer conversions carry the vtable without a cast.

**Two of the ticket's own claims were false, and each pointed somewhere worse.** Claim: "the value is
built with `blink_u_mk()` (the unit maker), so the handler pointer is DISCARDED at construction — this
is not only a spelling problem." `blink_u_mk` **is** the user function `mk`; `blink_u_` is the
reserved-name escape (`codegen_types.bl:884`) and the forward declaration reads
`static blink_io_vtable* blink_u_mk(void);`. Nothing was discarded, which is why one arm closed it.
Claim: the unwrap-temp mismatch is part of this defect — it reproduces with no handler and no effect
anywhere, and came out as br 3nf9fr.

The ticket also asked whether a handler should be storable in a container at all, reasoning that "the
vtable pointer's lifetime is the enclosing `with`". **The spec answers both halves.**
`sections/04_effects.md:1306` "#### First-class values" — handlers "can be stored in variables, struct
fields, collections, closures, passed as arguments, and returned from functions", with
`let handlers: List[Handler[DB]] = [mock_db(d1), mock_db(d2)]` at :1319 — and :1288 says each
`Handler[E]` vtable is "managed by the GC", so there is no scope-bound allocation to dangle. A carrier
tag, not a diagnostic. *Verifying the premise against the spec first would have saved the analysis.*

`tests/test_rh7rhf_handler_option_carrier.bl`, 9 rows, 9/9 green. Red was the whole file failing to
build. `task ci` green — 698 test files, 698 passed, 0 failed; `fmt` 1614 passed, 0 failed.

**No fixture churn, which was not the expected outcome.** `c_type_tag` is not Option-local — its output
is a segment in Result, Map, Tuple and mono-instance names — and br bwyfy1's precedent is that
"collapsing it to one RULE broke 296 fixtures and was reverted". Nothing broke here. The distinction
worth keeping: bwyfy1 *changed* what existing kinds spell, this *adds* a kind that previously spelled
nothing valid. Adding an arm is safe in a way collapsing arms is not.

**Census, both modes — and the counter went UP, from 42 to 43.** Saying that first, because the target
was also met:

```
                            mono                        arc
ctype.option    agree=1910 diverge=0 missing=0   agree=1867 diverge=0 missing=0   ← was 2 declines
ctype.forin.binder  agree=112 diverge=20         agree=112 diverge=20             ← was 19
TOTAL           agree=436725 diverge=43 missing=109   agree=361184 diverge=43 missing=109
```

The two `ctype.option` declines are gone in both modes. The 43rd row is **one row from this ticket's own
new test file**, and it is attributable exactly: the pre-existing 19 `forin.binder` rows are unchanged
(9 in `test_1n9fhg`, 5 in `test_bn3e6j`, 5 in `test_k4thkq` — all br qzdz2e, spec-blocked), and the new
one is

```
bucket=diverge site=ctype.forin.binder var=h ty=Handler[IO] tidc=blink_io_vtable* emitted=void*
```

**This is newly-observed divergence, not new divergence.** The corpus contained no for-in over a
`List[Handler[E]]`, so the cell existed and had never fired — `feedback_corpus_sweep_is_not_coverage`
running in the positive direction for once: writing the shape by hand lit a tap the 698-file corpus does
not reach. It is also the *benign* direction, where the tid is MORE precise than the flat channel
(`blink_io_vtable*` vs `void*`), both spellings are valid C, and the program runs correctly — so Stage
3's authority flip resolves it by making the binder more precise, with no separate fix needed. A cell to
count, not a bug to file.

**Three byproduct tickets, and the test file is where two of them were found.** Writing the rows
honestly is what produced them — every one came from a row that went red for the wrong reason.

- **br f5k3jk (P0)** — the in-corpus row built `[mk_io(), mk_metrics()]` to show the carrier worked,
  and it **compiled**. List-literal elements are not type-checked at all: `let xs: List[Int] = [1, "a"]`
  runs, and an explicit `List[Handler[IO]]` annotation does not help. For handlers that is the 88sfaz
  cross-effect laundering reached by a new route — `io.println("loop")` dispatches by slot index through
  a Metrics vtable and calls `counter(Str, Int)` with one argument. `types_compatible` is intact (the
  direct `take(mk_m())` is correctly rejected) and `push` checks; the **literal** is the hole. Sibling
  br x231pe reports the same gap for struct literals.
- **br wxxg4f (P1)** — a for-in row used a captured `tag` to tell its two elements apart and hit
  `error: 'tag' undeclared`. A **builtin**-effect handler body cannot reference any enclosing binding;
  the identical shape through a **user** effect compiles and runs. A divergence between two emit paths,
  not a missing feature.
- **br 1mw2c3 (P2)** — `hs.get(0).unwrap()` and `m.get("k").unwrap()` still fail, and *not* for this
  ticket's reason: `List.get`'s element-CT arm chain re-derives the carrier from a flat element CT and
  its final `else` hardcodes `CT_INT`, so the site never consults a tag speller at all. Both shapes are
  **parked as a commented block** in the test file with that explanation, not deleted. The for-in row is
  the control that makes the distinction checkable — it also goes through a `List[Handler[IO]]`, and it
  passes.

## The literal that was not a type position (br `f5k3jk`)

**Not a census cell, and it is in this log for a reason.** Every other unit here was found by the
instrument. This one was found by *writing a test row honestly*: rh7rhf's in-corpus row built
`[mk_io(), mk_metrics()]` to show its new carrier tag worked, and the row **compiled**. The census could
never have found it, because the census measures how codegen spells types it was given — and here
typecheck handed codegen a `List[Handler[IO]]` that contained a `Handler[Metrics]`. Both spellers agreed
perfectly. They were spelling a lie.

**Three symptoms, one missing check.**

```blink
let xs = [1, "a"]           // xs.get(1) prints 94055069447766 — the Str pointer read as an Int
let xs = [2.5, 1]           // xs.get(0) SIGSEGVs
let hs = [mk_io(), mk_metrics()]
for h in hs { with h { io.println("loop") } }
                            // prints "[M] loop=1" — io.println dispatched by SLOT INDEX through the
                            // Metrics vtable, calling counter(Str, Int) with one argument
```

The third is the reason this is P0 and jumped the queue: it is br 88sfaz's cross-effect vtable
laundering, in safe Blink with no `@trusted` and no `@ffi`, reached through a list literal instead of a
typevar. 88sfaz's own fix is intact — `fn take(h: Handler[IO])` called with a `Handler[Metrics]` is
correctly rejected — and so is `push`. The **literal** was the one position with no check.

**The fix reuses `check_arg_value`'s rule and cannot reuse `check_arg_value`.** Element 0 governs
(`sections/03_types.md:311`, `[100, 95, 87] // List[Int]`) and every later element is checked against it
exactly as `push` checks its argument: the int-literal escape, then the metavar unify when either side
carries an unbound α, then `types_compatible`. But `check_arg_value` *infers* its value node, and
`infer_type` has no memo short-circuit — a second call re-walks the element and double-reports every
diagnostic inside it, the trap this file already documents at br q1pxhm. The contribution the caller's
loop already computed is passed in instead. `tc_check_list_elem_compat`, 12 lines, called from the loop
at `typecheck.bl:10755` that until now discarded its own result into `let _c`.

**A comment in this codebase called this a spec decision, and it was right to at the time.**
`tc_check_spread_sources` (br q1pxhm) enforced §2.16 for spread elements only, and recorded: *"§2.16 says
nothing about plain elements, so `[1, "x"]` stays legal. General list homogeneity is a separate
decision."* The deferral was correct at the time. What settles it now is that the question has exactly
one sound answer, because there is no implicit widening anywhere in the language to build an alternative
rule out of:

```blink
let f: Float = 1        // error, today
xs.push(1)              // error on a List[Float], today
```

So `[2.5, 1]` cannot mean "`List[Float]` with `1` promoted" in this language. It means the segfault above.
A heterogeneous list literal has no meaning to preserve, so enforcing homogeneity removes no expressible
program — which is what makes this a bug fix and not a `type:spec` question for the panel.

**Spread elements are skipped, deliberately.** q1pxhm's diagnostic cites the spec sentence it enforces
and must stay the one that fires; a second report would be one defect explained two different ways. The
test asserts the count, not just the presence.

**One row went the other way: a program that did not compile now does.** `[None, Some(4)]` was E0301
under-determined, because element 0 contributed `Option[α]` and the constraint in element 1 was computed
and thrown away. Checking the element *unifies*, so α is pinned from the constraining element. That is
inference, not the Void-defaulting br 8vcj2c ruled out — the literal determines the type, nothing was
ever reading it.

`tests/test_f5k3jk_list_literal_elem_types.bl`, 15 rows, 15/15. Red was 6 negative rows; **8 of the 15
are positive controls**, and that ratio is the point — a homogeneity check is exactly the kind of change
that over-fires. The controls that mattered: `[Ok(1), Err("e")]` (the two elements constrain *opposite*
sides of one Result and fail a plain structural compare), `[Color.Red, Color.Green]` (two variants are
one type), `pair[T](a, b) -> [a, b]` (an unbound Typevar is neither concrete nor a metavar, and silence
there is load-bearing), and `[a, 1]` with `a: I32` (the int-literal escape).

**`task regen` green on the first attempt, which was the real risk.** A homogeneity check that the
compiler's own 40k lines violated even once would have bricked the bootstrap. They do not — and neither
does the stdlib, nor `examples/`. One corpus file did:
`tests/test_t7xf9y_handler_from_container.bl:136` read `[mk_io(), mk_metrics()]` in a row titled *"a
handler at a non-zero List index can be used"*, whose stated purpose was to make index 1 a different
effect from index 0. **That row was itself the 88sfaz crash**, in a test file written to guard against
it. Made homogeneous, with the loss recorded in the comment: the stronger proof it was reaching for is
not available in the language, because it was never sound.

**Census, both modes: unchanged, and that is the expected result.** `diverge=43 missing=109` per-cell
identical to the rh7rhf baseline; only `agree` grew (mono 436725 → 436981, arc 361184 → 361359 — the new
test file's own compilations). No `ctypediv` cell can observe this fix: it changes which programs reach
codegen, not how codegen spells anything. **Third unit in a row to close a real defect without moving the
counter** — worth stating plainly, because a project whose exit criterion is a counter reaching 0 will
otherwise quietly stop valuing the fixes that do not move it.

`task ci` green — 699 test files, 699 passed, 0 failed; `fmt` 1616 passed, 0 failed.

**The class is now one route from closed, and the last route is a P0 nobody had priced as one.** Six ways
to get a `Handler[Metrics]` into a `Handler[IO]` slot, measured:

```
hs.push(mk_m())                              REJECTED   argument 1 of 'List.push'
m.insert("k", mk_m())                        REJECTED   argument 2 of 'Map.insert'
let o: Option[Handler[IO]] = Some(mk_m())    REJECTED   declared type … but got …
fn f() -> Handler[IO] { mk_m() }             REJECTED   return value type …
let t: (Handler[IO], Int) = (mk_m(), 1)      REJECTED   declared type … but got …
let hs = [mk_io(), mk_m()]                   REJECTED   ← this unit
let e = Env{h: mk_m()}                       ACCEPTED   ← br x231pe, prints "[M] structlit=140092283357272"
```

br x231pe was filed P2 as a general soundness gap ("`P { n: "not an int" }` typechecks clean"). It is the
same P0 memory-safety hole through the struct-literal field, and it is **raised to P0**. It stays blocked
on br 0khtje — a strict per-field check bricks self-hosting until `AstNode.kind`/`Token.kind` are real
enum types, since ~281 `kind: NodeKind.X` sites are enum-into-Int — so 0khtje is **raised to P1** as the
gate on a P0, with a note that a narrower carve-out (fire only when neither side is an Int/enum pair)
might close the exposure without waiting for the migration.

**Two byproducts, one family, and neither is this cell.** Both came from positive-control rows that would
not compile:

- **br 3x4q41 (P2)** — `let xs: List[I32] = [1, 2, 3]` is *rejected*: `declared type List[I32] but got
  List[Int]`. The int-literal escape reaches a scalar `let` (`let x: I32 = 1`, fine) and a builtin method
  argument (`push(1)` onto a `List[I32]`, fine) and not the literal-vs-annotation compare — by then the
  element nodes are gone and only two list tids are compared. The literal needs the declared element type
  as a construction hint, the way `check_arg_value` sets one before inferring an argument.
- the same ticket, second position: `fn i32v() -> I32 { 7 }` is rejected too. Four positions, two with
  the escape and two without, so the escape belongs in whatever compare they share rather than in
  `check_arg_value` alone.

## The gate that was really a missing struct member (br `wxxg4f`)

Also not a census cell, and for a different reason than br `f5k3jk` was not one. `f5k3jk` was a type
typecheck never checked; this one is a type nobody spelled wrong anywhere. A `handler IO { ... }` op
body that referenced any enclosing binding emitted a free reference to a C identifier that is not in
scope, and cc rejected the program:

```
build/cap1.c:124:48: error: 'tag' undeclared (first use in this function)
  124 |     printf("%s\n", blink_str_format("[%s] %s", tag, msg));
```

The same shape through a **user** effect compiled and ran. That asymmetry is what made it a ticket
rather than a feature request, and the ticket's own advice — *"start by diffing the two emit paths at
the `has_handler_caps` branch rather than adding a second capture mechanism"* — was right. The diff
was one condition, repeated three times: `&& is_user_effect != 0` on the capture analysis
(`codegen_expr.bl:1343`) and on both of its consumers, the read side that declares the capture inside
the static op fn (:1513) and the write side that stores it at construction (:1591).

**The gate was not an oversight.** Captures ride in the vtable's `__userdata` word, and only the
user-effect vtable had that word: codegen emits it (`codegen.bl:991`), while the eight builtin
vtables are hand-written in `bootstrap/runtime_core.h` and were function pointers and nothing else —
`blink_io_vtable` was five of them. So the gate was the honest consequence of a missing struct
member, and it is worth separating from the kind of gate this project usually finds. A conjunct that
narrows a check because the general case was never thought through is a defect. A conjunct that
narrows a mechanism because the other half of the representation does not exist is a *description* of
the representation. Deleting the first is a fix; deleting the second without adding the member would
just have moved the failure from cc to a wild pointer. The fix is therefore symmetric — `void*
__userdata;` last in all eight builtin structs (so the positional `_default` initializers stay
aligned and leave it NULL), the three conjuncts dropped, and the capture read choosing
`ev_field(f)` for a builtin against `ev_field("ue_{f}")` for a user effect.

**A module global is not a capture, and the stdlib is what said so.** Removing the gate broke two
rows of `tests/test_std_testing.bl`, because `analyze_captures` reports every free name that
`is_scope_var` accepts and module-level `let`s are scope vars. `lib/std/testing.bl`'s
`capture_log`/`capture_print` handlers reference file-scope `_capture_log_target` /
`_capture_print_target`, which had been left as free references — correctly, since a file-scope C
static is visible from a static function. With the gate gone they became captures, and capturing a
global is wrong twice: the capture is a snapshot taken at handler-construction time, and it consumes
the single `__userdata` word that nested handlers share. Hence a filter, `is_module_global(cname) ==
0`, backed by a `cg_module_global_set` that `emit_top_level_let` registers — globals are emitted at
`codegen.bl:1292`/`:1315`, function bodies at `:1934`, so the registry is always populated first.

The general shape is worth keeping: **a capture analysis that has only ever run on one path has never
been tested against the corpus.** Removing the gate did not just enable a feature, it turned an
analysis loose on every builtin handler in the stdlib, and the row that caught the over-capture was
the *composed* one. A single `capture_log` works fine — one handler's `__userdata` is nobody else's.

**Divergence-neutral, for the fourth unit in a row.** `diverge=43 missing=109`, per-cell identical,
in both build modes; `agree` rose 436981 → 437188 (mono) and 361359 → 361485 (arc), which is only the
new test file's sites. Capture plumbing spells no types, so it moves no cell — and saying so out loud
matters in a project whose exit criterion is a counter reaching zero.

**Two byproducts, both found by probing the fix rather than by the census, and both larger than it:**

- **br `saf1hh` (P0)** — nested handlers share ONE `__userdata` word, so an op **inherited** from an
  outer handler reads the **inner** handler's captures. With two capture types that disagree it is a
  SIGSEGV from safe Blink, confirmed at exit 139 on the user-effect path too, so it predates this fix
  rather than following from it. The cause is a straight identity error: the capture belongs to a
  *handler*, `__userdata` belongs to the *effect's vtable slot*, and delegation shares the slot. Any
  fix has to break that identification (per-op `{fn, userdata}` pairs, a chained userdata, or
  per-handler storage), so it needs a decision rather than a patch. The nesting row in the new test
  documents which direction works and why the other has no row: a failing row cannot be parked, and a
  row asserting today's output would pin the defect.
- **br `vapcpp` (P1)** — `fs.*` and `net.*` handler overrides are silently ignored. Those 16 ops are
  hardcoded codegen intrinsics (`blink_read_file(...)` at `codegen_methods.bl:3072` and friends) that
  never read `__blink_ev.fs`/`.net`; of the eight builtin effects only io, time and env dispatch
  through the evidence struct at all. The runtime vtables exist and the `with` emitter installs them
  — only the call sites never look. This is the fail-open direction: `sections/04_effects.md:14`
  sells handler attenuation as the sandbox ("*The runtime enforces it*") and `:284-295` gives
  `mock_net` as a worked example of the shape that does not work. `saf1hh` is marked as blocking it,
  because fixing dispatch widens the P0's reach rather than narrowing it.

That second one is the reason this test's "second builtin effect" row is `handler Env` and not
`handler FS`: FS was the first draft, and FS cannot carry the row.

## Fixing the type moved the binding to a worse authority (br `1mw2c3`)

`List[Handler[E]].get(i)` and `Map[K, Handler[E]].get(k)` spelled the retrieved Option as
`blink_Option_int` whatever the element was, so the `with` operand assigned an `int64_t` to a vtable
pointer and cc rejected the program. A missing arm, not a missing type: both `.get` emitters end
their element-CT ladder in an `else` that hardcodes CT_INT, and CT_HANDLER had no arm of its own. The
carrier it needed already existed and is already emitted for `Some(mk())` — `blink_Option_handler`,
member `void*`, which stores and yields a vtable pointer with no cast at either end and therefore
needs no per-effect variant.

**The premise held on the axis that mattered.** The elem/value CT reaching those ladders really is
CT_HANDLER in both receiver shapes — the `listelem` tap reads `expr_elem=21` for a named list and
`stamp ect=21 var=blink_u_mk_list() arm=tail` for a call receiver — so no tid-led branch was needed
here. The flat channel had the answer; only the arm was missing. That is worth recording because it
is the *opposite* of most cells in this document, where the flat channel is the thing that cannot
answer.

**Then the fix broke something else, and the census caught it rather than a test.** Two new rows:

```
bucket=diverge site=ctype.handler var=hi ty=Handler[IO] tidc=blink_io_vtable* emitted=blink_ue_metrics_vtable*
bucket=diverge site=ctype.handler var=hm ty=Handler[Metrics] tidc=blink_ue_metrics_vtable* emitted=void*
```

An honest carrier **moves a binding from one authority to another**, and the authority it moves to
can be the weaker one. `let hi = ios.get(0).unwrap()` used to arrive as CT_INT, skip
`emit_let_binding`'s `val_type == CT_HANDLER` block entirely, and be spelled by
`handler_c_from_tid` — the arm br `t7xf9y` added for exactly this erased case. With the carrier
fixed it arrives as CT_HANDLER and takes the block ordered *far above* that one, which reads the
`cg_handler_*` construction globals. Nothing cleared those before a let RHS, so `hi` inherited what
`[mk_metrics()]` on the previous line had left behind: declared `blink_ue_metrics_vtable*` and
installed into `ue_metrics`, so `io.println` in the body dispatched through the ambient vtable while
`metrics.counter` went through an IO vtable by slot index. The br `88sfaz` shape, from a program with
no annotation lie in it.

This is a general hazard of the collapse and not a quirk of handlers. Every arm ordered on `val_type`
was ordered against the CTs that *actually arrive there*, and several of the tid-led arms in this
document are explicitly placed last so they only catch what the flat path erased (br `0rmamy`'s
rule). Making an erased CT honest is therefore not a monotone improvement: it hands the binding back
to an earlier arm that was never exercised on that shape. **Re-measure the census after a carrier
change even when the change looks purely additive** — a new arm in one file can silently re-route a
decision in another.

So the fix is three parts:

1. the two CT_HANDLER carrier arms in `emit_list_method` / `emit_map_method`;
2. clearing `cg_handler_vtable_type` / `_field` / `_is_user_effect` **before** `emit_expr(val_node)`
   in `emit_let_binding` — the same clear `t7xf9y` made on the `with` operand, one statement kind
   later, so the channel means "what THIS RHS set";
3. a tid fill-in ordered **last** in that block (construction global → annotation →
   `tc_tid_handler_effect`), because after the clear a container read has no flat answer at all and
   would register an *empty* vtable field. That is not a spelling problem but a dispatch one:
   `get_var_handler_vtable_field` is the first thing the `with` operand asks.

**The existing test had the shape and could not fail.**
`tests/test_t7xf9y_handler_from_container.bl`'s "handlers of different effects come out of their own
containers" row is this exact program, and it ends in `assert(true)` — a handler installed into the
wrong slot still exits 0. It was left alone rather than rewritten, because asserting output in-process
would mean nesting an IO capture handler inside the row's own handler, which is br `saf1hh` territory.
The covering row lives in the new file and asserts both output lines. Same lesson as the
`wxxg4f` file's: on this shape, exit 0 is not evidence.

Divergence-neutral once part 3 landed: `diverge=43 decline=109` in both build modes, mono per-cell
identical to the pre-ticket baseline, the two `ctype.handler` rows gone, and `agree` up 313 (mono) /
232 (arc) — all of it the new test file's own sites.

## The two types that were both a struct and a scalar (br `kxe0s2`)

`Some(Duration.ms(50))` did not compile, and the error came out at the far end of the pipeline:

```
error[UnresolvedMethod]: unresolved method '.to_ms' on type Duration in 'main'
```

**That message is codegen, not typecheck.** It is `codegen_methods.bl:5737`, and the `in '<fn>'`
suffix is the tell — typecheck's diagnostics carry no such suffix. The ticket had it filed against
the typecheck gate, and the gate is incapable of producing it: `tc_method_resolvable_on_type`'s
clause (e) fails open on `is_builtin_method`, which lists `to_ms` along with `to_seconds`, `to_nanos`,
`sub`, `scale`, `is_zero`, `since`, `elapsed`, `to_rfc3339`, `to_unix_ms` and `to_unix_secs`
(`typecheck.bl:6728-6746`). No typecheck change was made. Reading the source before naming the layer
is the whole content of that paragraph.

With the method call removed so codegen got further, cc gave the other half:

```
error: unknown type name 'blink_Option_void'
  const blink_Option_void o = (blink_Option_void){.tag = 1, .value = d};
```

**One cause, two symptoms.** `Instant` and `Duration` are the only two types in the language that are
simultaneously a declared struct — `pub type Duration { nanos: Int }` (`lib/std/time.bl:21,:25`), with
methods as ordinary value-receiver free functions — and a flat CT, `CT_INSTANT`/`CT_DURATION`, which
exists so `time.read().to_unix_ms()` lowers to a direct call. Every carrier and container-element site
decides struct-vs-scalar by asking whether a struct **name** is present. These two never presented
one, so they took the scalar side, where the carrier is named from `c_type_tag` — which had no arm for
either and answered its `else { "void" }` default. `emit_option_typedef` returns early on exactly
`tag == "void"`, so `blink_Option_void` was referenced and never typedef'd. In containers they fell
through to `emit_boxed_container_store`'s final `else` and emitted `(void*)<struct value>`, which cc
rejects outright. And the retrieved value came back a bare `int64_t`, so the method blocks that spell
`Duration_to_ms` — gated on the flat CT — no longer matched. Hence the `UnresolvedMethod` at the end.

**The fix routes them to the struct carrier instead of adding `c_type_tag` arms.** The invariant is
*at every container-element and carrier boundary an Instant/Duration presents as
`(CT_STRUCT, "Instant"/"Duration")`*. Two helpers in `codegen_types.bl`
(`builtin_struct_name_for_ct`, and `builtin_struct_ct_for_name` for the reverse direction), then five
fill-ins: the `Some()` inner name, ordered **last** so a real struct or enum name still wins;
`emit_boxed_container_store`'s guard and box name, which is the documented single chokepoint for
`list.push` / `list.set` / `map.insert` / list-literal (br `4yzsfc`) and therefore covers four store
sites with one name; `map.insert`'s value CT, normalized before **both** the store and `set_map_types`
because insert passes `elem_container: ""` and records its value type separately; the list literal's
`i == 0` block, whose `first_elem_struct` is read from `resolve_push_struct` *before*
`emit_boxed_container_store` has recorded anything; and the receiver CT recovery at
`emit_method_call:3850`, which has to sit there and not lower because
`let mut struct_type = get_var_struct(obj_str)` at `:5639` is bound long after the Instant/Duration
method blocks.

Three reasons for the routing choice rather than a by-value carrier with a struct-derived tag, all
recorded in the comment on `c_type_tag`'s `CT_HANDLER` arm:

1. List-of-struct, Map-value-struct, Result-of-struct and tuple-of-struct machinery is fully built
   out, so **one** routing decision covers every container — instead of one hand-written arm per
   container, which is the shape br `1mw2c3`'s `CT_HANDLER` arm had to take one section above.
2. The tid twin `tc_tid_tag_at` (`typecheck.bl:12884`) already answers `c_type_tag_for_struct(t.name)`
   for a `TyKind.Struct` inner. Routing to the struct carrier makes the two spellers agree **by
   construction** rather than by a third hand-kept arm — br `bwyfy1`'s lesson, applied instead of
   re-learned.
3. A struct-derived tag on the scalar path would collide with `emit_struct_option_typedef`'s
   pointer-boxed member under the same typedef name and one shared `option_typedef_emitted` dedup
   guard — the exact hazard `ensure_carrier_from_tag`'s own comment warns about.

**`CT_VOID` is the other spelling of "by-value struct whose identity lives in the name slot."** The
Result unwrap tail (`codegen_methods.bl:673-677`) declares the real C struct, calls
`set_var_struct(...)`, and then publishes `expr_result_type = CT_VOID` — not `CT_STRUCT`.
`emit_boxed_container_store`'s struct branch already accepted both; my first pass accepted only
`CT_STRUCT` at the method gate, which is precisely why the `Result[Duration, Str]` row still failed
after the first regen. Worth carrying forward into Stage 4: any guard written as `== CT_STRUCT` is
half a guard.

**The `Type_method` free-function convention is not general** — falsified by probe before
generalizing anything: `type P { x: Int }` plus `pub fn P_double(p: P) -> Int` plus `p.double()` gives
`warning[UnknownMethod]` then `error[UnresolvedMethod]`. Duration and Instant dispatch is
special-cased on the flat CT (`obj_type == CT_INSTANT` at `codegen_methods.bl:4954`, `CT_DURATION` at
`:4994`), which is exactly why the receiver recovery is needed and why it cannot be replaced by a
naming convention.

**Why an entire carrier sat unexercised.** `rg '\[(Instant|Duration)\]' src/ lib/ tests/ examples/`
finds nothing — not one `Instant` or `Duration` appears as a type argument anywhere in the repo. A
zero-hit sweep is an unexercised tap, not coverage, so all 16 rows of the new test are constructed by
hand. The second half of the camouflage is that both types are `{ nanos: Int }` and `int64_t`-shaped
in C, so flooring one to `Int` *looks* like a legitimate scalar. It is wrong twice: once in the
carrier name, once in what the retrieved value can still do. And field access degraded silently
instead of failing — `d2.nanos` interpolated the literal string `"<value>"` — which is why every row
asserts on a value and none end in `assert(true)`.

**The bwyfy1 caution, discharged by measurement.** The ticket warned that `c_type_tag` is not
Option-local and that br `bwyfy1` records collapsing it to one rule breaking 296 fixtures. Census
re-run in both build modes over `tests` + `examples` + `src`: `diverge=43 decline=109` before,
`diverge=43 decline=109` after, and a per-cell diff of the normalized `(site, tid, flat)` triples is
**identical** in both modes. No churn, because no `c_type_tag` arm was added and every change is
gated — `builtin_struct_name_for_ct` returns `""` and `builtin_struct_ct_for_name` returns `-1` for
every other type. Better than neutral: the new test file's own rows read `ctype.flat agree=79`,
`ctype.option agree=9`, `ctype.struct agree=4`, `ctype.result agree=2`, all with `diverge=0
missing=0`. Reason 2 above, measured rather than asserted.

**`CT_CLOSURE` is now the only kind left in the `else { "void" }` hole** — br `597kj0`, filed with an
MVCE. `Some(fn(x: Int) -> Int { x * 2 })` produces the identical `blink_Option_void`. Same shape,
different cause: a closure has no struct name to recover, so it cannot take this fix and needs either
a real closure carrier or a fail-closed diagnostic. `List[closure]` already works, so the list element
path has a channel the Option carrier lacks — that contrast is where whoever takes it should start,
rather than inventing a third representation.

## The rule the spec states, the example it marks COMPILE ERROR, and nine methods that ignored both (br `ees4yr`)

`sections/03_types.md:302` states it plainly: "Mutating methods (`push`, `pop`, `insert`, `remove`,
`set`) require the binding to be `let mut`. Immutable bindings can only call non-mutating methods."
:316 gives the counter-example with the verdict written in: `names.push("Dave")  // COMPILE ERROR —
names is not mut`. That program compiled, ran, and printed the mutated length.

**The first deliverable was scope, and the answer is that the check did not exist.** Not one of the
nine implemented mutating methods enforced it — `List.push/pop/set/clear`, `Map.insert/remove/clear`,
`Set.insert/remove` all accepted a plain `let` receiver and mutated it. There was no correct site to
copy from. `List.insert` and `List.remove` are in the spec's table but are not implemented at all (br
`5ebq1h`); both are listed in the new method table so they arrive covered rather than needing a
second edit.

**The second deliverable was the ticket's own caution — do not assume the emitted C is
const-correct.** It is not, and that is why the severity really is "missing diagnostic" and not
"writing through a const object": collections are never const-qualified, so `let xs` and `let mut xs`
both emit `blink_list* xs = _l0;`. Scalars and structs *do* get `const` today. So the spec's second
rationale at :320 — that the C backend can emit `const` for immutable bindings — remains unrealised
for exactly the types this rule is about. Checked before deciding, as the ticket asked.

**The home is `tc_check_body`'s MethodCall arm, and `infer_type`'s arm is the wrong one.**
`infer_type` is a memo *wrapper*: it always calls `infer_type_uncached` and only records the result,
so it does not short-circuit and it runs several times per node — the nr pass, the inference pass,
and mono re-inference. A diagnostic emitted there reports two or three times for one call.
`tc_check_body` walks each node exactly once **with the nr scope frames live**, which is the pair of
properties this check needs and the only place both hold. It is reached in statement position via the
ExprStmt arm and in binding position via LetBinding.

**Keyed on the receiver's kind, never on the method name.** `insert`, `remove`, `set` and `clear` are
ordinary user method names; a name-only key rejects `my_widget.set(3)`.
`tc_is_mutating_collection_method(k: TyKind, method: Str)` takes the kind, and `type_kind` resolves
bound metavars internally while `resolve_alias_tid` handles `type Names = List[Str]`. Three candidate
authorities for the method set, and only one is real:

1. The per-type tables' `Mutates` column (`sections/03_types.md:369`, `:430`, `:485`) — **this one**.
2. The trait blocks' `// Mutation (requires let mut)` comments — wrong: the MapOps block files
   `contains_key` under that heading while its own table row says Mutates=no (br `psytmt`).
3. `pp_is_mutating_method` (`typecheck.bl:4719`) — wrong, and the tempting one, because it already
   exists and looks authoritative. It is the `@pure` walker's list and it includes `append`, which is
   Mutates=no.

**`nr_is_mut` cannot tell a parameter from a `let`** — both answer 0 — so `is_mut` alone cannot scope
the rule. Binder identity has to come from the declaring node: parameters bind through the node-less
`nr_define_typed` in `tc_check_fn`, lets through `nr_define_typed_at(..., node)`. Hence a new
accessor `nr_binding_node(name)` plus a `node_kind(decl) == NodeKind.LetBinding` guard, which leaves
parameters, match/for/with binders and closure params deliberately out. Parameters are the
interesting exclusion: `fn f(xs: List[Int]) { xs.push(9) }` mutates the *caller's* list and the
spec's sentence does not reach it — that is br `5ryk88`, spec-undecided, and not a question this
ticket gets to answer unilaterally. Module-level globals are unaffected too, verified by the
pre-existing `test_type_errors` row that still reports E0300 rather than E0610.

**New code E0610 / `MutationRequiresMut`.** E0602 is spec-reserved
(`sections/05_memory_compile_errors.md:346`) and unimplemented, so it was left alone rather than
claimed. The help carries the *declaring* line, because the span points at the call:
`declare it as 'let mut m' at line 3`. That is a usability decision that paid for itself immediately
— it is what made the corpus migration mechanically drivable, since the compiler named every site
together with the declaration to change.

**Two real aliasing bugs in the compiler's own source**, which is the class the spec's `grep "let
mut"` rationale exists to expose — a binding never reassigned whose aliased collection is mutated:

```
src/codegen_derive.bl:81  let eq_target = if is_generic { derive_eq_generic_bases } else { derive_eq_types }   ... eq_target.push(tname)
src/parser.bl:92          let items = sl_data.get(sl).unwrap()                                                 ... items.push(node_id)
```

A test row mirrors that shape so it stays covered.

**Blast radius, measured rather than estimated:** 10 sites in `src` + `lib` across 5 files, 278 in
`tests` + `examples` across 54 files. The heuristic candidate list said 391; the inflation was
StringBuilder and Bytes receivers, neither of which is in scope.

**Two traps worth carrying forward.** A probe `blinkc` built into a scratchpad directory resolves
stdlib modules from `argv[0]`, prints `ModuleNotFound` for all 11 prelude modules, degrades
typechecking, and produced a **false zero-violation sweep** over `lib/std`. It must live in `build/`.
And `bootstrap.sh` copies `lib/std/*.bl` into `build/lib/std` with the archive built from *those*, so
an edit to `lib/std` has no effect until a regen — which is what made the migration script report
repeated NOMATCH on `http_types.bl` / `http_client.bl` lines it had already fixed.

**Census after — divergence-neutral, and confirmed per cell.** Both build modes over `tests` +
`examples` + `src`: `diverge=43 missing=109` before and after, and a per-cell diff of the normalized
`(site, tid, flat)` triples on a **common-file basis** — the 991-file / 922-file intersections, 17
distinct cells in each mode — is identical. Excluding "the new test roots" is not a sound comparison
basis and published a wrong figure once; intersect the file sets instead. Diagnostics do not move
types, and this measurement says so rather than assuming it.

`tests/test_ees4yr_mut_binding_required.bl`, 21 rows: ten E0610 expectations (the spec's own
counter-example verbatim, then each of the nine implemented methods), the aliasing row, three
negative controls pinning what is deliberately out of scope (a parameter is not rejected, a user
method sharing a mutating name is untouched, StringBuilder and Bytes are untouched), a row asserting
the help names the declaring line, and six acceptance rows that *run* and assert values. One of those
pins `Map.remove` returning `Bool` rather than `Option[V]` (br `ddapre`).

## The last kind in the hole, and why it got one arm and not two (br `597kj0`)

`c_type_tag` (`src/codegen_types.bl:7002`) maps a `CT_*` to the lowercase segment that names an
`Option` / `Result` carrier, and it ends in `else { "void" }`. That default is the whole defect class
`rh7rhf` and `kxe0s2` came out of: a **missing arm silently becomes a genuine Void**, where the tid
twin `tc_tid_tag_at` fails *closed* on an unhandled kind (`ICE_SEG_UNHANDLED_KIND`). `CT_CLOSURE` was
the last kind left in it.

**It failed two ways, not one, and the second is the worse one.** The ticket described the Option
side: `Some(fn(x: Int) -> Int { x * 2 })` named `blink_Option_void`, and `emit_option_typedef`
(`:7945`) returns early on exactly `tag == "void" || tag == ""`, so the name was **referenced and
never typedef'd** — a `cc` error, loud. The Result side is not symmetric. `emit_result_typedef`
(`:7960`) *matches* the literal `"void"` tag to lower a `Void` leaf to an `int64_t` placeholder field
(br `hsgsbp`, load-bearing), so `blink_Result_void_str` really was **declared** and a
`blink_closure*` was stored into an `int64_t` member. Nothing but a promoted `-Wint-conversion`
stood between that and a silent miscompile on a compiler that does not warn.

**The fix is one arm, because the source already said which one.** `unwrap_scalar_ct`'s comment read:
*"CT_CLOSURE is floored too and that is a latent erasure of the same family, left alone deliberately —
no `blink_Option_closure` carrier exists to spell it against… **Widen `c_type_tag` first if a closure
inner ever needs it.**"* That instruction is exact, and it composes: `unwrap_scalar_ct` is *derived*
from `c_type_tag` (`if c_type_tag(ct) != "void" { return ct }`) rather than enumerated, so the arm
un-floored it with **no edit there at all** — which is the payoff of having derived it. And
`emit_option_typedef` spells the member from `c_type_str(CT_CLOSURE)` = `"blink_closure*"`
(`:6166`), a runtime type (`bootstrap/runtime_core.h:2308-2312`), so a single arm yields a *complete*
carrier: `typedef struct { int tag; blink_closure* value; } blink_Option_closure;`. The ticket's
suggested alternative — a bespoke "tag + function pointer + userdata" carrier — was unnecessary:
`blink_closure` already **is** that struct, and it is heap-allocated, so a pointer suffices.

**The `decide first` question was answered by citation, not by judgement.** The ticket asked whether
`Option[fn(..) -> ..]` should be a supported type at all or a diagnostic. `sections/04_effects.md:454`
declares `error_handler: Option[fn(Request, ServerError) -> Response] = None` inside the http_server
`Route` type, and `:407` uses `List[fn(fn(Request) -> Response) -> fn(Request) -> Response]`. The
spec's own design depends on the carrier existing, so it is a codegen gap and not a missing check.

**One arm, deliberately, and the asymmetry is the interesting part.** `tc_tid_tag_at` takes a position
(`TAGPOS_TOP` / `TAGPOS_INNER`). Grepping the callers separates them cleanly: `tc_tid_to_c_tag` (TOP)
is the **mono-args CSV / mono-instance mangling** speller; `tc_tid_inner_tag` (INNER) is the
**carrier** speller. `TyKind.Fn` had no arm at either. It now has one at INNER only.

Dropping a closure's signature at INNER is *exact*, not merely conventional: every closure of every
signature is one `blink_closure*`, so a per-signature carrier name would emit distinct typedefs with
byte-identical bodies. At TOP the same drop would make `identity[fn(Int) -> Int]` and
`identity[fn(Str) -> Str]` mangle to **one symbol and one body** — trading a loud floor measured at 0
for a silent instance collision. So TOP keeps failing closed.

That is a **knowing divergence from the Handle/Ptr/Handler precedent**, which took arms at both
positions and accepted the drop at TOP — `rh7rhf`'s own words: *"Both DROP the pointee, which is what
makes Ptr non-injective as a segment."* Non-injectivity is tolerable for a pointee the mono-args CSV
recovers elsewhere. A whole function signature is not. The reasoning is recorded at both arms, because
a future reader comparing the two kinds will otherwise read the asymmetry as an oversight.

**An existing test had to move, and it now pins the asymmetry instead of hiding it.**
`tests/test_vbcw1e_lowercase_void_twin.bl` R4 used `TK_FN` as its witness for "a kind with no arm
spells the unhandled-kind sentinel" — its comment said *"the only constructible one"*, because every
other armless kind lacks an exported `make_*` constructor. Arming Fn at INNER made that row red. The
row's **guarantee** survives untouched (an armless position must fail closed and must not spell
`"void"`); only its witness position moved, so the row now asserts both sides from the same
`make_fn_type` tid: `ICE_SEG_UNHANDLED_KIND` at TOP, `"closure"` at INNER, and `diag_is_ice_seg`
false for the latter. A red pre-existing test whose *witness* went stale is not a regression, and
rewriting it to assert the new fact in the same breath as the old one is what keeps it honest.

**One of my own new assertions was wrong, and the fix is worth recording.** The Result row first
asserted `!c.contains("blink_Result_void_str")`. That name is emitted by **every** program — the
prelude synthesizes `Result[Void, Str]`, and `fn main() { io.println("hi") }` contains it three times
— so its presence never discriminated anything. The bug was that the closure Result was *declared as*
it. The row now asserts the binding's own type (`blink_Result_closure_str r =`) and the member being a
pointer, which is what actually distinguishes fixed from broken.

**Two byproduct findings, both filed with MVCEs, both out of scope here.**

- br `0ya6sk` (`type:spec`) — **the spec's own `Route` example does not parse.** `handler` is
  `TokenKind.Handler` (`src/tokens.bl:72`), so `handler: fn(Request) -> Response` at
  `sections/04_effects.md:454-455` is `error[KeywordAsIdentifier]`, and `handler` is not listed as
  reserved anywhere in `sections/02_syntax*.md`. Two defensible resolutions (permit keywords in field
  position vs. correct the spec and publish the reserved word); the ticket states both rather than
  presuming one. The test row that reproduces the `Route` shape renames the field to `on_error` with
  an inline comment pointing at the ticket.
- br `ndgx84` (`type:bug`) — **a closure that came out of a container is not callable.**
  `let h = fs.get(0).unwrap(); h(41)` is `error[UndefinedFunction]: undefined function 'h'`, while the
  control `let g = f; g(41)` prints `42`. It reproduces from a **List**, whose element path never
  names a carrier, so it is not Option-specific and it survives this fix: every construction form
  compiles and runs now, and only *calling* the unwrapped value fails. The callee resolver keys on the
  initializer's *shape* (a closure literal, or another closure binding) instead of the binding's type.

**Verified in both build modes, by hand — the corpus does not contain this shape.** A sweep would read
zero hits here, which is an unexercised tap and not coverage (`feedback_corpus_sweep_is_not_coverage`),
so the shape was constructed directly: archive-linked (`build/blink`) and monolithic
(`build/blinkc` + `cc -Ibuild`) both emit `blink_Option_closure` / `blink_Result_closure_str` with a
`blink_closure*` member, and both binaries run and print. `task ci` exit 0 — 704/704 test files, fmt
1626 passed / 0 failed.

**Census after — divergence-neutral in both modes.** `diverge=43 missing=109` before and after, and a
per-cell diff of the normalized `(site, tid, flat)` triples on a common-file basis (992-file and
923-file intersections, 17 distinct cells in each mode) is identical. Widening a tag speller for a kind
the corpus never instantiates should move nothing, and this says so instead of assuming it.

`tests/test_597kj0_option_closure_carrier.bl`, 9 rows: the carrier declaration asserted on the
*member type* and not just the name; `Some(closure)`; an explicit `Option[fn(..) -> ..]` annotation;
`None` under that annotation (a separate emission path — `{.tag = 0}` with no value — that named the
same undeclared carrier and so failed independently); the spec's `Route` field shape; the Result twin
as C plus a run; and three controls — `List[closure]` and `Map[Str, closure]`, which already worked
because both pointer-box the element and never name a carrier, and a genuine `Result[Void, Str]`
proving `hsgsbp`'s load-bearing `"void"` match still lowers to the `int64_t` placeholder.

## The value that was indistinguishable from end-of-stream (br `w3v2e6`, the data-loss half)

`w3v2e6` is titled as a *tid publication* ticket — a bare `let ch = Channel(4)` publishes no element
type, so `infer_type` leaves it `Unknown` and all three channel seams fall back. Its own notes then
name a second, separable defect and hand it to this ticket: *"on a bare channel, `ch.send(0)` still
encodes as `(void*)(intptr_t)0`, which IS NULL, and NULL is `blink_channel_recv`'s end-of-stream
sentinel."*

**The measured loss is bigger than "a 0 goes missing."** The for-in drain is
`while (1) { void* r = blink_channel_recv(ch); if (r == NULL) break; ... }`, so a payload of NULL does
not drop one element — it ends the stream:

```
let ch = Channel(4); ch.send(5); ch.send(0); ch.send(7); ch.close()
for v in ch { io.println("v={v}") }      // printed v=5 only: 0 AND 7 vanished
```

Silently, exit 0. Only the for-in path is affected — `.recv()` has no NULL-as-terminator, so it reads
`0, 1` back correctly, which is why this survived every corpus run.

**br `hgd2az` half-fixed it and its comment overstated the result.** hgd2az routed the three seams
through the channel node's tid and boxes the element when `tc_channel_elem_ct` answers `>= 0`, and a
box address is never NULL — so an annotated `Channel[Int]` was already correct. But its comment on the
drain read *"the NULL test above is the end-of-stream signal and is only sound because `send` now
boxes"*, which was true of the boxed arm and false of the fallback sitting three lines below it. The
comment now says which arm hgd2az made true and which one this fix did.

**The fix is decision-independent, and that is the point.** `w3v2e6`'s publication half is
spec-blocked: bare `Channel(n)` appears in no spec section and no `blink llms` topic (the spec's
spelling is `channel.new[T](buffer: n)`, `sections/04_effects.md:1751`, which hgd2az already handles);
`make_channel_type(TYPE_UNKNOWN)` would launder an unknown into a structured type; and minting a
metavar is the right HM answer but nothing binds it, so every corpus `let ch = Channel(4)` would
become `error[CannotInferType]` E0301 under the gqg3rk boundary check (spec 8vcj2c). The ticket says
that decision is not its to make unilaterally, and it is right.

So the fallback now boxes **the same 8-byte payload it used to send inline**:

```
void** __chbox_0 = (void**)blink_alloc(sizeof(void*));
*__chbox_0 = (void*)(intptr_t)x;              /* the exact word the old `send` passed */
blink_channel_send(ch, (void*)__chbox_0);
```

The payload word is bit-for-bit unchanged, so every reinterpretation downstream is unchanged. What
changes is **only** that the address is never NULL. No element type is invented, no tid is published,
and 8vcj2c's answer is not needed.

**Two details that are the whole fix, not decoration.** The box is `void*` and **not** `int64_t`: a
bare `Float` element is a loud `cc` error today (*"cannot convert to a pointer type"*), and an
`int64_t` box would have accepted the double and silently truncated it — trading a loud failure for a
wrong value, the one way this change could have made things worse. And the `.recv()` twin gets a NULL
guard the drain does not need (`void* p = (r == NULL) ? NULL : *(void**)r;`), because `.recv()` on a
closed empty channel legitimately reaches the decode with NULL in hand and must keep answering the
element's zero value (what it *should* answer is br `yzan52`); the drain has already `break`-ed by
then, and that break is precisely the test this fix repaired.

**The compiler's own code is an instance of the fixed shape, and it worked by accident.**
`src/cli.bl:2169-2170` — `let dot_ch = Channel(1); dot_ch.send(0)` — is `blink test --parallel`'s
dot-column counter. It was correct only because **two bugs cancelled**: the payload 0 became NULL, and
`.recv()`'s NULL case answers the element's zero value. It is now correct by construction.
(`src/cli.bl:2162` and `lib/std/http_server.bl:368` are the other two bare channels; both send 1 and
never 0.)

**Measured.** `task regen` exit 0; `task ci` exit 0 — 705 test files 705 passed / 0 failed (that run
*is* the dot counter, through the rebuilt CLI), fmt 1628 passed / 0 failed.
`tests/test_w3v2e6_bare_channel_zero_truncation.bl` 9/9, red on exactly 3 rows before the fix.

The 9 rows: a leading zero drains; a **mid-stream** zero does not take the value behind it (the row
that distinguishes truncation from a bad rendering of one element); the C-level mechanism, asserting
the box is emitted and the inline `(void*)(intptr_t)` send is gone — a behavioural row alone would
also pass if the drain simply stopped treating NULL as end-of-stream, which would break a genuinely
closed channel instead. Then six controls: `.recv()` still reads `0, 1`; a closed empty channel still
ends the drain *and* still reads back zero (the row that proves the sentinel survived the move from
payload to box address); the compiler's own 1-slot zero-valued cell; an annotated `Channel[Int]`; and
two rows that **pin still-wrong answers on purpose** — a bare `Str` channel still prints a pointer
(`w3v2e6`'s inference half; asserted as the *absence* of `v=hello`, since the garbage value varies per
run) and a bare `Float` channel still fails loudly in `cc`. When the inference lands, those two go
red, which is the point: it must not slide in silently.

**Census after — divergence-neutral in both build modes.** `diverge=43 missing=109` in monolithic
(`lines=2015 agree=438334`) and archive-linked (`lines=1816 agree=362258`) alike, matching the baseline
exactly; and a per-cell diff of the normalized `(site, tid, flat)` triples on a common-file basis (993-
and 924-file intersections, 17 distinct cells in each mode) is identical. That is the expected reading:
this change alters *emitted C*, not what either authority claims a type is, so the instrument that
compares the two should not move. The 21 family-A `flat=Channel[Int]` rows are still there — they are
the publication half, and they stay until it is decided.

`w3v2e6` stays **open**. Its data-loss half is dead; its publication half is a spec question.

## The one string that made a typed variable "an undefined function" (br `ndgx84`)

    let f = fn(x: Int) -> Int { x + 1 }
    let o: Option[fn(Int) -> Int] = Some(f)
    let h = o.unwrap()
    h(41)                       // error[UndefinedFunction]: undefined function 'h' in 'main'

`h` is a fully typed local. The diagnostic calls it an **undefined function** because of one empty
string. A bare-Ident callee is emitted as a closure invocation only if `get_var_closure_sig(fn_name)`
is non-empty (`src/codegen_expr.bl:5119`); on empty it falls through to the `UndefinedFunction`
backstop at `:5225`. That sig is the C function-pointer cast the call is made *through* —
`((sig)cls->fn_ptr)(cls, args...)` — so an empty sig is **indistinguishable from "not a closure at
all."** That is the whole reason a variable got a diagnostic about functions.

**Both pre-existing sig builders read an AST annotation.** `build_closure_sig_from_type_ann(ta)`
(`codegen_types.bl:4957`) and `build_closure_sig_resolved_mono(ta, tparams_sl, arg_tids)`
(`codegen_stmt.bl:8337`) are handed a `fn(..) -> ..` type node. A binding whose initializer is a
*method call* has no such node anywhere in reach, so every non-literal arrival of a closure — out of
a `List`, `Option`, `Result`, `Map`, out of a function return, out of a match binder — came back `""`.

**The tid always knew.** `BLINK_TRACE_CHANNELS=tydiv` on the failing programs reads
`site=emit_let_binding.decl var=h tid=Fn(Int) -> Int flat=Int` (List, Map, Result) and the same tid
against `flat=Fn()` (Option, match binder). A textbook Stage-3 cell: the authority holds the answer
and the decision is taken from the flat channel that lost it.

**The defect has three structurally different halves, and only one of them was the sig.** Option and
fn-return already *declared* `blink_closure*` — br `597kj0` widened `c_type_tag` for exactly that —
and lacked only the signature. List and Map `.get` had **no `CT_CLOSURE` arm at all**, so they built
a `blink_Option_int` and declared `const int64_t h = _ounw_3.value;`, the closure pointer squeezed
through an integer. `Result` was a third shape: the *carrier* was right (`Ok(f)` really does build
`blink_Result_closure_str`) and only `emit_result_unwrap_inner`'s decode ladder had no `CT_CLOSURE`
arm, so the value fell to the trailing `else` that defaults to `CT_INT`.

**The fix is the `1mw2c3`/`t7xf9y` handler precedent, applied verbatim.** There, `.get` got a
`CT_HANDLER` carrier arm so the binding stops arriving as `CT_INT`, and the *effect* is deliberately
dropped at the carrier and recovered from the tid downstream, because a list's flat element channel
can only ever say `List[Handler]`. A closure is the same shape one level over: the carrier can only
say `List[Fn()]`, so the three container arms make the binding arrive as `CT_CLOSURE`, and the
**signature** — which no `CT_*` tag can hold — is spelled from the binding's own tid by a new
`closure_sig_from_tid` (`src/typecheck.bl`, next to `c_type_from_tid`). `TyKind.Fn` stores the return
in child 0 and the params after it, so the walk is direct; the leading `const blink_closure*` is
prepended as ABI (it is the closure's self pointer, not a Blink parameter) exactly as both older
builders do. It declines to `""` on any child `c_type_from_tid` cannot spell, and on a `void`
parameter — legal in the return position, never in a parameter position — because the string is a
cast, and a half-spelled cast is a miscompile rather than a diagnostic.

**Two rows in the test exist only to prove the cast is right and not merely present.** A `Str -> Str`
closure and a two-parameter `Int, Int -> Int` closure: a `Str` signature emitted as `int64_t` would
compile clean and lie. The ABI was additionally hand-checked past the test rows for a `Float`
parameter and return, a by-value struct parameter and return, a `void` return, and a `Bool` return.
Two green controls stay in the file — the direct rebind `let g = f` and the struct-field read
`let h = b.f` — because those are the two shapes that *did* reach a sig writer, so a fix that
replaced the annotation path instead of extending it would show up there.

**`tk_to_ct` forced one deliberate deviation from the `0rmamy` ordering rule.** The rule is that a
tid-led arm goes *after* the flat arms, so it only ever catches a binding the flat channel erased.
The match-binder arm in `stamp_binder_elems_from_tid_if_unset` is instead placed **above** that
function's head-CT agreement guard, and asks `tc_tid_kind(mtid) == TyKind.Fn` directly rather than
going through `tc_tid_ct`. The reason is a false comment: `tk_to_ct` (`typecheck.bl:13283`) maps
`TyKind.Fn => CT_VOID` under *"No CT exists for these"*, which is untrue — `CT_CLOSURE = 6` has
existed since closures landed and the flat side uses it. `tc_tid_ct` therefore answers `-1` for every
closure and the guard rejected the binder before the arm could see it. Filed as br `rndevw` rather
than fixed here, because it has its own blast radius **and its own consequence for this plan**: while
that arm stands, every closure binding is a permanent `diverge` row, so **Stage 3's `counter == 0`
exit cannot be reached** until it is corrected. The `tydiv` closure rows do not move on this
ticket for that reason.

> **Correction, made when `rndevw` landed.** Correcting the arm is necessary but **not sufficient**:
> the closure rows stay `diverge` afterwards, because `ty_tp_same_shape` rejects a closure a second
> time in its child loop, where the flat universe holds the whole signature as one C string with no
> `tp` children to compare. Stage 3's exit needs the flat field *gone*, not the translation layer
> repaired. The deviation described above was nevertheless real and is now undone.

**Census after — divergence-neutral in both build modes, and the delta is fully attributed.**
`diverge=43 missing=109` in monolithic (`lines=2015 agree=438685`) and archive-linked
(`lines=1816 agree=362609`) alike, against a `diverge=43 missing=109` baseline; the per-cell diff of
the normalized `(site, tid, flat)` triples on a common-file basis (994- and 925-file intersections,
17 distinct cells in each mode) is identical in both. `agree` rose by **exactly 351 in each mode**,
and all 351 are `ctype.flat` — every other site's `agree`/`diverge`/`missing` triple is unchanged to
the row. Per-file, the increase appears **only** in files that link the compiler (`src/*.bl` and the
compiler-importing tests), at `+10` or `+7` each: it is this fix's own new declarations being
measured while the compiler compiles itself, not a corpus behaviour change.

> **Correction, made when `rndevw` landed.** This paragraph originally closed by predicting that the
> 351 were closure cells the instrument "cannot yet see agree" because `tk_to_ct` answers `CT_VOID`
> for `TyKind.Fn`, and that they would move when `rndevw` landed. They did not move — `rndevw` is
> census-neutral to the row — and the prediction confused two different instruments. `ctype_probe_at`
> spells with `c_type_from_tid`, which has always spelled a `Fn` as `blink_closure*` and never
> consulted `tk_to_ct`, so closure declarations were **already agreeing** here. `tk_to_ct` feeds
> `ty_tp_same_shape`, i.e. the `tydiv` sites, which is where the closure rows actually live. The
> per-file attribution above was right on its own terms; only the explanation of *why* was wrong.
> See the `rndevw` section below.

**Three byproducts filed, none of them regressions.** `311nk2`: calling a call-expression result
inline (`mk()(41)`, `fs.get(0).unwrap()(41)`) emits no call at all and silently prints the literal
`"<value>"`, exit 0, no diagnostic — the callee *shape*, not the callee *resolution*, and silent
where `ndgx84` was loud. `rndevw`: the `tk_to_ct` arm above. `pdvrsj`: a closure whose return type is
a **container** types the call result `Void`, because the return is recovered by re-parsing the
emitted C signature string — `closure_ret_ct` (`codegen_types.bl:4652`) knows exactly four spellings
and `reseat_from_closure_ret_tag` rescues only the compounds whose C name happens to name their Blink
type. So `Int`/`Float`/`Str`/`Bool`/`void`/struct/`Option`/`Result` returns are right and the
containers are wrong, and `.len()` on the result draws codegen's `UnresolvedMethod` backstop while
that backstop's message prints `List[Int]` **from the tid**. Pre-existing — it reproduces from a
directly-annotated closure variable — but only reachable in its container-sourced spelling once this
fix made the call happen at all.

## The arm that was in the wrong group, and the cell it does not retire (br `rndevw`)

`tk_to_ct` ended in a five-arm group under one comment:

    // No CT exists for these. CT_VOID is the erasure, not a type.
    TyKind.Void => CT_VOID
    TyKind.Fn => CT_VOID
    TyKind.Tuple => CT_VOID
    TyKind.Typevar => CT_VOID
    TyKind.Unknown => CT_VOID

The comment is true for four of those five and **false for `Fn`**. `CT_CLOSURE = 6`
(`codegen_types.bl:36`) has existed since closures landed, the flat side stamps it on every closure
binding, and `c_type_from_tid` already spells a `Fn` as `blink_closure*`. So the arm is the same
shape as the `TyKind.Handler` and `TyKind.Template` arms in the *same* match, whose comments both
say they "make the two universes AGREE rather than adding knowledge" — and it is now the third.
`Tuple` and `Typevar` stay, correctly: there is no `CT_TUPLE` at all (codegen models a tuple as a
struct), and a typevar is not storage.

**The cost of the lie was measured, not guessed.** `tc_tid_ct` turns `CT_VOID` into `-1`, so it
answered `-1` for every closure and no helper asking it for a head CT could see one. Fixing
br `ndgx84` ran straight into it: `stamp_binder_elems_from_tid_if_unset` opens with a head-CT
agreement guard, which rejected every closure binder before any arm could run, and that fix had to
ask `tc_tid_kind` directly from **above** the guard — a deviation from br `0rmamy`'s ordering rule
that only existed to route around this arm. With the arm repaired the guard admits a closure like
any other head, and the second sub-step put that arm back where `0rmamy` says it belongs: last,
keyed on the CT, catching only what the flat answer left unset. `task ci` green across both
sub-steps (707/707, fmt 1632); the ndgx84 test stayed 10/10 through the move, which is the point of
having written it first.

**The half of the ticket that turned out to be wrong, and it is the more interesting half.** The
ticket also claimed the arm makes Stage 3's `counter == 0` exit unreachable, the implication being
that fixing the arm retires the closure `diverge` rows. It does not, and the test pins that rather
than leaving it to be re-litigated. `ty_tp_same_shape` rejects a closure **twice over**:

1. `if ct == CT_VOID && k != TyKind.Void { return TyShape.Differ }` — the root kind. This arm fixes
   that one, and only that one.
2. the **child loop**. `tc_tid_child_count` on a `Fn` is `1 + params` (return first), and the flat
   universe holds a closure's signature as a **C string**, not as `tp` children — `flat=Fn(int64_t
   (*)(const blink_closure*, int64_t))` is one `sname`, not a tree. So `tp_cmp_child` answers `-1`
   at every index, and "an absent flat slot against a tid that NAMED the type" is a cell by the
   instrument's own rule.

So the row stays `diverge`, one level deeper and honestly attributed. That is the correct score:
the flat universe genuinely cannot hold a closure's parameter and return types, which is exactly
the divergence the instrument exists to count. **Closure cells are not retired by any repair to the
translation layer** — they are retired by Stage 3 flipping authority onto the tid and Stage 4
deleting the flat fields. Calling them `Ignorance` instead would be worse than leaving them:
`Ignorance` is keyed on the *tid* being unknown, and a `Fn` tid knows exactly what it is, so
scoring it as ignorance would hide a real cell from the very counter Stage 3 exits on.

Two stale comments came off with it. `ty_tp_same_shape`'s own note listed "Tuple, Fn, Closure and
Typevar" as the kinds collapsing onto `CT_VOID` — after this change `Fn` is not one of them, and
`TyKind.Closure` **does not exist**: a closure *is* `TyKind.Fn`. And `tc_tid_ct`'s TRAP note (do not
key a struct-slot admission gate on a CT, because several kinds share `CT_VOID`) listed `Fn` among
them; the trap is real and still stands for `Void`/`Typevar`/`Unknown`, so the fix there is to drop
`Fn` from the list rather than to soften the warning.

### The census moved by zero, and the ndgx84 note said why wrongly

Both modes came back exactly on the baseline — mono `agree=438685 diverge=43 missing=109`
(`lines=2015`), archive-linked `agree=362609 diverge=43 missing=109` (`lines=1816`), on identical
exclusions. The ndgx84 note had predicted the opposite: that its own `+351 agree` was closure cells
the instrument "cannot see agree until rndevw lands". **That prediction was wrong, and the reason
matters more than the number: those are two different instruments.**

- `ctype_probe_at` (the `ctype.*` sites, and the published 43/109) spells with
  **`c_type_from_tid`** and compares against the string the emitter actually printed. It has never
  consulted `tk_to_ct`, and `c_type_from_tid` has always spelled a `Fn` as `blink_closure*`. So
  closure declarations were **already agreeing** on this instrument, before and after.
- `sv_ty_or_flat` (the `tydiv` sites, and Stage 2's 428-cell map) goes through
  **`ty_tp_same_shape`**, which is the only consumer `tk_to_ct` feeds. That is where the closure
  rows live, and where the two-level rejection above applies.

Verified rather than reasoned: a hand-built closure program contributes exactly one `ctype.flat`
**agree** row per closure binding (0 → 1 → 2 as bindings are added), and rows are only *printed*
for decline/diverge, which is why grepping the sweep for a closure row finds nothing and why the
tap looked unexercised at first. On the `tydiv` side the same program prints
`bucket=diverge site=emit_let_binding.decl var=f tid=Fn(Int) -> Int flat=Fn(int64_t(*)(const
blink_closure*, int64_t))` — the row the test pins, unchanged by this fix by construction.

So rndevw is census-neutral **by mechanism**, not coincidentally, and the `+351` from ndgx84 was
what the per-file attribution said it was all along: that fix's own new compiler declarations being
measured while the compiler compiles itself. Nothing there was a closure cell.

### Sizing the closure family, which is a Stage 3 input

There was no `tydiv` corpus script (only `ctypediv`), so one was written — and the two sweeps must
stay in separate files, because the instruments are not comparable. Monolithic, `tests` + `examples`
+ `src`, new test roots excluded: **196 closure diverge rows, 61 distinct `(site, tid, flat)`
cells**, at exactly two sites — 44 at `emit_fn_params.param` and 17 at `emit_let_binding.decl`.

Not one of the 61 has an empty flat signature. Every one carries the full spelling as an opaque
string, which is the cleanest statement of what this whole plan is about: the flat universe is not
*missing* the closure's type here, it is holding it in a form nothing can walk. Those 61 go to zero
when the flat field goes away in Stage 4, and not before.

**One of the 61 sub-families turned out to be a live bug, filed as br `kvjfqt`.** 28 cells read
`tid=Fn(K, V) -> Bool` against a fully concrete `flat=Fn(int(*)(const blink_closure*, int64_t,
int64_t))` — the tid is *less* concrete than the flat spelling, which for a post-mono site should be
impossible. `substitute_typevar_tid` ends with

    // TyKind.Fn and every scalar/nominal kind: no embedded typevar to rewrite.

and that is the same species of false comment as the one this ticket fixed: `Fn` embeds typevars in
precisely the way `List[T]` does, and `List`/`Option`/`Set`/`Result`/`Map`/`Tuple`/`Struct`/`Enum`
all have recursing arms directly above it. So `tc_tid_subst_mono` hands back `Fn(T) -> T`
unsubstituted inside a mono'd body, `closure_sig_from_tid` declines on the typevar child, the sig
stays empty — and the ndgx84 backstop fires one level up, on safe Blink:

    fn apply_first[T](fs: List[fn(T) -> T], x: T) -> T {
        let h = fs.get(0).unwrap()
        h(x)
    }
    // error[UndefinedFunction]: undefined function 'h' called in 'apply_1first_0Int'

The mangled name proves the mono itself worked with `T=Int`; only the `Fn` tid's children were left
as `T`. A directly annotated param (`fn apply_it[T](f: fn(T) -> T, ..)`) works, because that path
resolves typevars by name off the AST annotation and never asks the tid — so this is the tid path
specifically, which is the path Stage 3 is making authoritative.

## The kind that was treated as having no children, twice (br `kvjfqt`)

The `rndevw` census asked one question of its own data — *why is the tid ever **less** concrete than
the flat spelling at a post-mono site?* — and 28 of the 61 closure cells answered it:
`tid=Fn(K, V) -> Bool` measured against `flat=Fn(int(*)(const blink_closure*, int64_t, int64_t))`.
That ordering should be impossible. `substitute_typevar_tid` ended with

    // TyKind.Fn and every scalar/nominal kind: no embedded typevar to rewrite.
    t

which is the same species of false comment as the `tk_to_ct` arm one section up, and false in the
same way: a `Fn` holds its return in `inner1` and its params variadically, so `fn(T) -> T` embeds a
typevar exactly as `List[T]` does — and `List`, `Option`, `Set`, `Result`, `Map`, `Tuple`, `Struct`
and `Enum` all have recursing arms *directly above that line*.

**It was live, on safe Blink, and it was `ndgx84`'s error message one level up.**
`tc_tid_subst_mono` handed back `Fn(T) -> T` unsubstituted inside a mono'd body,
`closure_sig_from_tid` declined on the unspellable typevar child, the binding kept an empty closure
sig — and an empty sig is indistinguishable from "not a closure":

    fn apply_first[T](fs: List[fn(T) -> T], x: T) -> T {
        let h = fs.get(0).unwrap()
        h(x)
    }
    // error[UndefinedFunction]: undefined function 'h' called in 'apply_1first_0Int'

The mangled name is the proof that the mono machinery was innocent: the instance really was emitted
for `T=Int`. Only the `Fn` tid's children were left as `T`.

### The second arm, and why it is in the tree

The discovery twin `unify_typevar_binds` — which walks a param tid against an arg tid in lockstep to
*find* the binds that the function above then *applies* — had no `Fn` arm either. Added on symmetry,
it changed **no test outcome**: every row passed without it, because `gqg3rk`'s metavar inference
already covers the call-argument routes.

An unexercised arm in an inference path is exactly the "unexercised tap" this project has been
burned by, so it was **deleted, regenerated, and probed for a shape that needs it** rather than kept
on the strength of the symmetry argument. That shape is a closure-typed *field* of a generic struct,
whose typevar has no other route to a bind — `build_typevar_binds` is called from the struct-literal
path as well as the call path:

    type Holder[T] { f: fn(Int) -> T }
    let h = Holder { f: fn(n: Int) -> Str { "v{n}" } }
    let g = h.f
    g(7)                    // I0001 + UndefinedFunction without the arm; `v7` with it

The arm was then restored with that program as a test row. Its sibling
`Pair[T] { g: fn(T) -> T, seed: T }` is kept as the control that already worked, because `seed: T`
binds `T` without ever consulting the closure.

### A third hole, in a third function, deliberately left alone

If a typevar is reachable **only** through a closure nested inside a container param, it is not
inferred at the call site at all — neither arm helps, and the program still ICEs:

    fn make_it[T](fs: List[fn(Int) -> T], n: Int) -> T { fs.get(0).unwrap()(n) }
    make_it(fs, 7)          // I0001, mono args BLINK_I0001_erased_slot

That is `tc_resolve_tparam_tid`, the one walker of the three driven by the param annotation's **name**
rather than by the tid: its `"List"` branch knows the bare element and the `List[(.., T, ..)]` tuple
slot, its `"Fn"` branch only reads a closure *literal*'s own annotations, and a `List[fn(..) -> T]`
arg matches neither. The arg tid is fully concrete — `tid=List[Fn(Int) -> Str]` on the tydiv channel
— so the information is present and only the walker cannot reach it. Its own source comment already
documents the narrowness and names the ticket (`3ejrqa`), whose proposed fix — walk the arg's tid now
that a closure literal memoizes a real `TyKind.Fn` — covers this shape for free. So the MVCE went
there, and this ticket's return-position test row gives its typevar an independent binding route so
that it measures the new arm instead of that gap.

**Three functions, one root shape.** `Fn` treated as a leaf by every walker that had learned to
recurse into every other compound kind. That is the plan's thesis restated at a smaller scale: the
representation was never the problem, the hand-written per-kind case analysis was.

### Census

The tydiv instrument moved exactly where predicted and nowhere else. The 28 tid-less-concrete-than-
flat cells are **zero**; distinct closure cells go 61 → 55 as the `K, V` family folds into its
concrete instances. Rows stay at 196 — correctly, because every closure row still diverges on the
signature-as-C-string cause that only Stage 4 retires, which is what `rndevw`'s pin exists to say.

The ctype instrument is neutral in both build modes: `diverge=43 missing=109` unchanged, 17 distinct
cells identical on a common-file basis (996 mono / 927 archive-linked common files). `agree` rose by
`+324` in each mode, attributed to the row — 37 compiler-linking files at exactly `+9` each, less the
`9` from the excluded `test_rndevw` root. Nine is the number of new `let` bindings the two arms
introduce: this fix's own declarations, measured while the compiler compiles itself.

## The return type that was recovered by re-reading the C (br `pdvrsj`)

A closure whose return type is a container is callable, and the call RESULT is typed `Void`:

    let l = fn(n: Int) -> List[Int] { [n, n + 1] }
    let lv = l(4)
    lv.len()          // error[UnresolvedMethod]: unresolved method '.len' on type List[Int]
    for e in lv {}    // internal compiler error[UnhandledIterableAtCodegen]: for-in over 'Void'

The first message is the whole plan in one line. It PRINTS `List[Int]`, because that backstop's
receiver name is tid-derived while the decision that reached it is flat-derived: the two authorities
disagree inside a single diagnostic.

The result type was never read from the callee's type at all. It was recovered by RE-PARSING the
emitted C signature string. `closure_ret_ct` (`src/codegen_types.bl:4647`) recognizes exactly four
spellings — `int64_t`, `double`, `const char*`, `int` — and answers `CT_VOID` for everything else;
`reseat_from_closure_ret_tag` (`src/codegen_expr.bl:339`) rescues only the compounds whose C name
happens to NAME their Blink type (`Option_*`, `Result_*`, a `resolve_struct_from_c_name` hit).
Nothing recognizes `blink_list*`, `blink_map*`, `blink_set*` or `blink_bytes*` — those spellings are
shared by every instantiation, so they are unrecoverable from the string by construction. **The
correctness of a return type depended on a coincidence of C naming.**

Three emitters consume that answer, each with its own copy of the parse: a closure called by name
(`codegen_expr.bl:~5155`), a closure-valued EXPRESSION called (`codegen_expr.bl:~5396`), and a
closure-valued FIELD called in method position (`codegen_methods.bl:~5790`, `h.f(4)`). The second
one was wrong in the opposite direction — an unrecognized `blink_*` return fell to a blanket
`CT_STRUCT`, not to `CT_VOID` — so both arms of the same string chain were guessing. A fix at one
site leaves the other two, which is why all three shapes are pinned as rows.

`closure_ret_direct_ct` seats the head CT from the tid the type checker already memoized on the call
node. Seating the HEAD is the whole job, and that is measured rather than assumed: the let ladder in
`codegen_stmt` already carries tid last-resorts keyed on the RHS node (`stamp_list_elem_from_tid`,
`recover_list_elem_from_tid`, the `mv45y5` `CT_SET` branch, `apply_map_binding_meta`), every one of
them gated on the head `val_type` being right. Fixing the head let the existing machinery recover
the elements — including at depth 2, `List[List[Int]]`, which the flat pair cannot hold at all.

### Why the predicate is an exclusion and not a list

The first version keyed on `CT_LIST`/`CT_MAP`/`CT_SET`/`CT_BYTES` — the kinds the ticket named. It
passed every row written from the ticket. Probing the ADJACENT kinds is what found it too narrow:

    -> Char           const void c = ((int32_t(*)(const blink_closure*, int64_t))l->fn_ptr)(l, 4);
    -> StringBuilder  error[UnresolvedMethod]
    -> Channel[Int]   error[UnresolvedMethod]

The defect was never about containers. The parse spelled four C types and erased every other kind
alike, so `Char`, `I32`, `StringBuilder`, `Channel`, the four containers and the enums all failed
together — and a whitelist of the reported ones would have left the rest, which is how this survived
several closure fixes. The predicate is now the complement: the tid answers for every kind EXCEPT
`CT_OPTION`, `CT_RESULT` and `CT_STRUCT`, which need more than a CT (a per-instantiation carrier
typedef and a temp, or a NAME attached to a temp) and keep the string-driven reseat until Stage 4
retires it.

### The half that a CT cannot fix

An enum needed both halves, and the second one is not a type — it is a cast. With the result type
seated, an enum return DECLARED correctly and still failed to compile:

    const blink_E e = ((void(*)(const blink_closure*, int64_t))l->fn_ptr)(l, 4);
    //                  ^ gcc: void value not ignored as it ought to be

A closure call is emitted as `((sig)cls->fn_ptr)(cls, args..)`, so the cast has to name the same C
type the declaration does. `codegen_closures` builds that sig from the literal's own annotation
names, and its return spelling is a three-way string chain ending in
`c_type_str(type_from_name(name))` — which answers `void` for every kind `c_type_str` cannot spell,
not just for a genuine `Void`. `closure_lit_ret_c` spells it from the closure node's own `Fn` tid and
is ordered LAST, for `0rmamy`'s reason: the three string arms keep every return they can spell, the
tid fills in only where they said `void`, and a genuine `Void` return reaches it and gets `void`
again, so the override is a no-op there.

One arm was written, measured and REVERTED: the same tid lead on the enum branch of the closure
DEFINITION's return spelling (`codegen_closures.bl:1000`). Every probe was byte-identical without
it, because `resolve_ret_type_from_ann` already answers for the shape that arm would have corrected.
An unexercised arm is a liability in a file this size, so it is not in the tree.

### What is a control, and what is a separate ticket

The ticket listed `Tuple` among the broken kinds. It was already correct — a tuple's C spelling IS
its typedef name, so `resolve_struct_from_c_name` recognized it — measured both bare and with a
container inside (`(Int, List[Int])`), and pinned as a control rather than silently dropped.

Two shapes are still broken and are neither this cell's cause nor its fix:

- **br `wj9bvn`** — a closure returning a generic-enum INSTANCE (`-> Tree[Int]`) emits no typedef for
  it: `blink_Tree` (the def line and the variant literal, the bare base) and `blink_Tree_0Int` (the
  declaration and the cast, the instance) are both undeclared. Measured RED on the pre-`pdvrsj`
  compiler too, so it is pre-existing; the payload-less and payload-carrying non-generic enums both
  work and are pinned.
- **br `gp4s8a`** — `fn(n: Int) -> I32 { 7 }` draws `error[TypeError]: return value type Int does not
  match function 'closure' return type I32`. An int-literal coercion gap; `n.to_i32()` compiles, and
  that is the form the sized-int row uses.

### Red, green, and why the corpus said nothing

18 of the 24 rows are red on the pre-fix compiler (measured by stashing the change and rebuilding),
and the 6 that pass are exactly the controls. All 24 pass after. Every row runs its program in a
SUBPROCESS: the failures are compile errors, so an in-file row could not be red — the whole test
file would fail to compile.

The corpus never exercised the broken shape. `tests/test_fn_type_params.bl:12` has
`fn apply_list(f: fn(Int) -> List[Int], x: Int) -> List[Int] { f(x) }` and passes today, because
`f(x)` is in TAIL position and the caller's type comes from the enclosing fn's own return
annotation, not from the closure call's result. That is why no instrument moved, and why the
hand-built rows are the coverage rather than the sweep.

### Census

The ctype instrument is neutral in both build modes: `diverge=43 missing=109` unchanged, 17 distinct
cells identical on a common-file basis (957 mono / 878 archive-linked common files). `agree` rose by
`+108` in each mode, attributed to the row — 34 compiler-linking files at `+3` and 3 at `+2`, which
is `closure_lit_ret_c` reaching `c_type_from_tid` at the closure literals in the compiler's own
source. The tydiv instrument does not move at all (30223 diverge rows, 196 closure rows), correctly:
every closure row still diverges on the signature-as-C-string cause, and this cell removes the
string from the RESULT type, not from the signature. Stage 4 retires the rest.

## The two spellers that agreed everywhere the tid answered (br `hp1emh`)

A closure whose declared return is a generic-struct instance needs its mono typedef name in three
places at once — the definition line, the call-site fn-ptr cast and the `_sr` return temp — and
`codegen_closures.bl` built that name by WALKING THE ANNOTATION:

    mono_name_from_ann(strip_module_qualifier(ret_str), node_type_ann(node), -1, [])

The plain-fn seam already spells the same stem from the tid (`src/codegen.bl`). This cell routes the
closure seam through the tid too, via one helper in `codegen_types.bl`:

    pub fn closure_ret_mono_stem(node: Int) -> Str {
        tc_tid_struct_mono_name(tc_lookup_node_tid(node_type_ann(node)))
    }

The empty-stem fallback to `ret_str` is kept on both sides: a non-generic head (`-> Plain`) yields
`""` from BOTH spellers, so `blink_Plain` still comes out of `c_type_c_name(ret_str)`.

### Dual-read before flipping, and the zero-hit trap it walked into

Both spellers were run side by side under a trace channel before either was removed: **27 rows in
each build mode, 0 disagreements.** Getting those rows required abandoning the corpus. The first
sweep printed NOTHING, and reading that as "agreement" would have been wrong — the pinned fixture
`tests/test_vmf1k0_closure_generic_struct_ret.bl` is a SUBPROCESS harness. It writes source strings
to `.tmp/` and compiles them with `build/blink build` at test RUN time, so compiling the harness
never reaches a closure with a generic-struct return. The tap was forced unconditional to prove it
could fire at all, then the shapes were built by hand:

| shape | ann walker | tid speller |
| --- | --- | --- |
| `-> GKV[Int, Str]` | `GKV_0Int_0Str` | `GKV_0Int_0Str` |
| `-> Plain` (control) | `""` | `""` |
| cross-module `-> gmod.GKV[Int, Str]` | `GKV_0Int_0Str` | `GKV_0Int_0Str` |

The stem comes back UNQUALIFIED in the cross-module case and `c_type_c_name` reapplies the module
prefix through `mod_type_prefix`, giving `blink_gmod_1GKV_0Int_0Str` at the typedef, the definition
line, the cast and the `_cls_ret_0` temp alike. A multi-module fixture needs a real project root
(`blink.toml` + `src/<mod>.bl`) and `@module("gmod")` with a QUOTED name; `@module(gmod)` draws
`error[InvalidModuleAnnotation]`.

### The one disagreement is a third place, and pre-existing

A closure inside a GENERIC fn — `fn wrap[T](x: T) -> Box[T]` containing `fn() -> Box[T]` — is the
only shape where the two answers differ, and neither is right:

- typecheck memoizes NO tid on that annotation (`tc_lookup_node_tid(...) == -1`), so the tid
  declines and the fallback emits the bare `blink_Box`;
- the annotation walker passed the declared binder through as a mono segment: `blink_Box_0T`.

Both names are undeclared C types and both fail `cc` loudly, so this is not a silent miscompile in
either direction. It is filed as br `axvwed` and needs typecheck to memoize inside a mono body — the
mono-context twin of `n8mmry` — not a different speller. `tc_tid_subst_mono` cannot help while the
raw tid is `-1`, which is why the arm that would have called it was written, measured, and REMOVED
rather than left unexercised (the `pdvrsj` lesson).

### Census

The ctype instrument is neutral in both build modes: `diverge=43 missing=109` unchanged, 0 new cells
(2028 mono / 1829 archive-linked summary lines). The tydiv instrument does not move either — 30223
diverge rows, distributed `emit_fn_params` 29057, `emit_let_binding` 5346, `match_pattern` 524,
`emit_for_in` 94, `copy_list_compound_elem` 31, `tuple_destructure` 25, `with_resource` 11. Neither
instrument taps the closure signature speller, so neutrality is the expected reading, and the
coverage that matters is the four pinned fixtures: `test_vmf1k0` 8/8, `test_5htahp` 22/22,
`test_pdvrsj` 24/24, `test_kvjfqt` 12/12.

### The comment debt this cell also paid

The call site carried a ~25-line comment naming six br tickets and narrating the measurement. That
class of comment is now out of the source entirely: `br` is a local-only tracker, so an ID in a
comment is dead weight to every other reader, and this codebase is training data for the language.
`codegen_types.bl` went from 1953 comment lines to 1730 with no block over 22 lines. Its ticket
references were NOT driven to 0, contrary to what this section first claimed: the harvest regex
required a digit in the token, so every all-letters ID (`htxpmh`, `hsgsbp`, `yavhwc`, `pdvrsj`, …)
was invisible to it and 50 lines survived the sweep. Validate the candidate set against `br show`,
not against a pattern. Reasoning goes here and to `br note`; the
source keeps 1-4 lines naming the constraint. Every file touched from here gets the same treatment
in the same commit.

## The heap cell that was typed from the CT alone (br `0e7dek`)

A local that a closure mut-captures is moved to a heap cell, and the cell holds a COPY of the
variable — so the cell's C type is the variable's own declared C type, nothing else. Both seams that
declare it derived it from the CT alone:

    // codegen_stmt, enclosing scope
    let cell_type = c_field_type_str(val_type, ...)
    // codegen_closures, rehydration at the top of the closure body
    let mc_ts = c_type_str(tp_get_kind(mc_e.tp_id))

A CT cannot spell any kind whose C name needs a struct NAME or a carrier typedef. For a struct local
both seams therefore answered `void`:

    void* e_cell = (void*)blink_alloc(sizeof(void));   // sizeof(void)
    *e_cell = e;                                       // invalid use of void expression

### The predicate is wider than the report, and probing adjacent kinds is what found it

The ticket named structs. Option, Result and Tuple fail through the identical derivation: all four
need more than a CT to be spelled. An enum passes only because it is `int64_t`-backed, and the
containers pass because `blink_list*` / `blink_map*` / `blink_set*` ARE the CT's whole answer. A
whitelist of the reported shape would have left three live kinds behind — the same lesson as
`pdvrsj`, applied before the fix rather than after it.

One helper in `codegen_types.bl` now answers for both seams, so they cannot disagree:

    pub fn capture_cell_c_type(tp_id: Int, tname: Str) -> Str

Struct reads `tp_get_sname`; Option and Result go through `option_c_type_mixed` /
`result_c_type_mixed`; everything else falls through to `c_field_type_str`, which carries the
Void-position rule for the one caller that has the name. Tuples need no arm — a tuple is `CT_STRUCT`
with the tuple typedef already in `sname`.

### The third seam reads the cell by its emitted C string

Fixing the two declarations still left 7 of 10 defect rows failing, with `let v = e.n` drawing
`error: variable or field 'v' declared void`. The FieldAccess arm in `codegen_expr.bl` resolves its
receiver's struct with `get_var_struct(obj_str)` — and `obj_str` is `(*e_cell)`, which is no scope
var. Both ident rewrites now push the struct identity onto that exact string with
`set_var_struct(expr_result_str, ...)`, the established idiom for attaching identity to an emitted
expression.

### The failure has two faces, and the second one names the type it cannot spell

A direct field read fails at `cc`. A CONTAINER field instead fails earlier, as a spurious
`error[UnresolvedMethod]` at typecheck time — and the diagnostic names the receiver `Set[Int]`
correctly. The element type was known throughout; only the receiver spelling through the cell was
broken. Both faces are in the row set.

### Coverage

`tests/test_0e7dek_mut_captured_struct_cell.bl`, 23 rows, subprocess harness — the failures are
compile errors, so an in-file row could not be red without the whole test file failing to compile.
10 defect rows (struct scalar / read inside the body / field assign / container field / nested /
generic instance, tuple, Option, Option of struct, Result) and 13 controls (Int, Float, Str, U8,
Char, Bool, List, Map, Set, Bytes, StringBuilder, enum, and a struct reassigned with NO closure at
all, which pins that the `mut` reassignment was never the axis).

Red 13/10 → 16/7 after the two cell declarations → **23/0** after the receiver identity.

### Census

The ctype instrument is neutral in both build modes: `diverge=43 missing=109`, 0 new cells (2030
mono / 1831 archive-linked summary lines).

**The tydiv figure first recorded here (−291) is withdrawn.** That sweep was captured while
`src/codegen_stmt.bl` still called `capture_cell_c_type` without importing it, so every corpus file
that compiles the compiler's own sources stopped at `error[ImportNotSelected]` and emitted no trace
rows at all. Two files went dark that way — `tests/test_0rmamy_enum_local_decl_typedef.bl` and
`tests/test_1b7ggq_await_operand_resolved.bl` — and they carry 165 and 149 diverge rows when the
tree compiles. The 314 rows they did not emit are the whole of the apparent drop. Re-measured on a
compiling tree and on a like-for-like root basis, tydiv is neutral across this cell too.

**A sweep whose corpus does not compile reads as an improvement.** Every row the instrument emits
comes from a file that reached the phase being measured, so a file that fails earlier contributes
zero to `diverge` and looks identical to a file with nothing left to fix. Before comparing two
sweeps, count `ImportNotSelected` / `error[` rows in both and confirm the SAME set of files reached
the instrument; a mid-edit tree is not a baseline.

### The byproduct

A transitive mut-capture through a NESTED closure emits an undeclared name and a non-lvalue
assignment. It reproduces for `Int` and `Str` alike, so it is not on the struct axis and not this
cell; filed as br `063qcp` with both controls recorded (one nesting level, and read-only nesting).

## The cell that was closed by deleting the language feature under it (br `4vrmqe`)

`Bool + Bool` was accepted, and the sum then DISPLAYED as `true`/`false` while comparing equal to
its integer value. Typecheck did that on purpose:

    if lt == TYPE_BOOL && rt == TYPE_BOOL { return TYPE_INT }
    if lt == TYPE_BOOL && rt != TYPE_UNKNOWN { return rt }
    if rt == TYPE_BOOL && lt != TYPE_UNKNOWN { return lt }

so the arithmetic node was typed `Int` while codegen's flat side still read the operand's `Bool`.
That disagreement was the whole of the ctype `var=__emit_modes` divergence population — six rows,
one per corpus file that compiles `src/codegen.bl`.

### The cited rationale did not cover the behaviour

The comment above those lines justified them with a ticket ID. Reading that ticket: it is about
`time.read()` without an import. It covers the RELATIONAL side effect the lines also had (a `sum <= 1`
downstream of a Bool sum), not any decision that Bool is an arithmetic operand. So no prior ruling
protected the behaviour, and the spec is unambiguous against it: arithmetic traits are sealed to the
built-in numeric types (`sections/03_types.md:1936`), bitwise already excludes Bool (`:801`),
operands must be the same type (`:1970`), and there is no truthiness (`DECISIONS.md:106`, 5-0).

**Check what a comment's citation actually says before treating it as a decision.** An ID in a
comment is an assertion that a decision exists, not the decision. This one had been load-bearing for
a user-visible language rule that was never voted.

### The fix is a rejection, so it is user-visible and was the user's call

Rejecting is a breaking change for any user code doing `(a != 0) + (b != 0)`. The user ruled: reject.
That makes this the one cell in the collapse closed by removing the construct rather than by
teaching codegen to spell it — the divergence population disappears with the feature.

`reject_bool_arith_operand` is shared by two arms, not inlined in one:

    fn reject_bool_arith_operand(op: Str, tid: Int, node: Int) ! TypeCheck.Report, Diag.Report {
        if type_kind(resolve_alias_tid(tid)) == TyKind.Bool {
            tc_error_at("arithmetic '{op}' requires numeric operand, got {type_to_str(tid)}", node)
        }
    }

`resolve_alias_tid` so `type Flag = Bool` cannot walk past it, and `type_kind` rather than a
`== TYPE_BOOL` identity test so a metavar bound to Bool resolves first.

### The BinOp arm is not the only place an operator's operands are checked

`a += true` was still accepted after the BinOp arm rejected `a + true`. The `CompoundAssign` arm
checks only assignment compatibility between target and value, and Bool = Bool is compatible — it
never reaches the operator's operand rules at all. Rejecting only in BinOp would have left the ban
bypassable by spelling, so the compound arm calls the same helper on both sides (the parser stores
the bare operator, `+` not `+=`, so the message is identical).

Probing the same arm with a non-Bool operand found the general hole: `s += "b"` on a `Str` passes
typecheck and fails in the C compiler, where `let x = s + "b"` is a clean `E0521`. Filed as br
`5vy9v7` — the real fix routes `CompoundAssign` through the binary-operator operand checks so every
operator rule applies to both spellings from one place. Not done here: that is a wider change than
this cell, and the Bool face is closed either way.

### The one in-tree caller

`src/codegen.bl:452` summed three mode flags directly:

    let __emit_modes = (cg_archive_header_mode != 0) + (cg_archive_build_mode != 0) + (cg_user_tu_mode != 0)

rewritten to an explicit `(if flag != 0 { 1 } else { 0 })` sum. Nothing else in `src/`, `lib/` or
`tests/` used Bool arithmetic — 711 test files pass unchanged, which is the real measure of how much
this "feature" was used.

### Coverage

`tests/test_4vrmqe_bool_arith_rejected.bl`, 19 rows, subprocess harness (the rows are compile
errors). 13 rejection rows: `+ - * / %` on two Bools, a Bool literal, `(a != 0) + (b != 0)`, Bool/Int
on either side, and `+= -= *= /=`. 6 controls: `&&`/`||`/`!`, a comparison still yielding Bool, Int
arithmetic, Int compound assignment, Float arithmetic, and the explicit `if c { 1 } else { 0 }` sum
that is now the way to count. Red 13/6 → green 19/0.

Each rejection row asserts three things — nonzero exit, `E0300`, and that the message names both the
rule and `Bool`. Asserting only on the code would pass on any unrelated type error in the fixture.

### Two test-harness defects this row hit, both filed

- A field name that does not exist is accepted everywhere and interpolates as the literal
  `<value>`: `blink check` says `ok`, `blink run` prints `bogus=<value>`. Found because
  `tests/test_0e7dek_mut_captured_struct_cell.bl:41` read `r.err` on a `ProcessResult` whose field is
  `err_out`, so the diagnostic that row was built to print came out empty. Filed as br `d1md7y`;
  the `0e7dek` row is corrected here. A typo in a field name is a silent test weakener.
- Two test names that differ only in punctuation mangle to the same C symbol, and the file stops
  compiling with a `redefinition` error pointing at C rather than at the source. `test "Bool + Bool
  is rejected"` and `test "Bool - Bool is rejected"` collide. Filed as br `3nsztp`; the rows here
  spell the operators as words to get around it.

### Census

Taken at base `b0c9397`. Both sides of the table were swept at that base, so the delta is sound, but
the absolute numbers are not comparable to a sweep taken after the closure/`TyKind.Fn` batch landed —
re-baseline before quoting them against a later row.

Like-for-like (the four roots that are new or were dark in an earlier sweep excluded from both sides;
identical summary-line counts on both sides confirm the same corpus reached the instrument):

| instrument | before | after |
|---|---|---|
| ctype, monolithic | 42 diverge / 429666 agree / 109 missing, 2014 lines | **37** / 429671 / 109 |
| ctype, archive-linked | 42 / 353511 / 109, 1815 lines | **37** / 353516 / 109 |
| tydiv | 29908 diverge / 4775 unknown / 80 missing, 3056 lines | **29903** / 4775 / 80 |

−5 on every instrument in both build modes, and the `var=__emit_modes` population reads 0. The five
are one row per corpus file that compiles `src/codegen.bl`; the sixth raw row belongs to an excluded
root. The compound-assignment step is separately census-neutral (byte-identical sweep totals before
and after), as it adds a diagnostic and no type.

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
