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
| `08a267` | P2 | *(the four `tid=List[?]` rows `gmb211` did **not** move)* a list literal whose **first** element is a spread — `[..a]` — infers `List[?]`, because `infer_type`'s ListLit arm takes the element type from element 0 only and has **no `SpreadExpr` arm**. Position is the axis: `["q", ..a]` is correct. A **silent wrong value**, not just a laundered declaration. Flat is right and the tid is wrong, so the authority flip converts it into a hard miscompile |
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
miscompile.

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
