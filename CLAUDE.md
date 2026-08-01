# Blink

Self-hosting compiler (src/compiler.bl → C → native).

Run `blink llms --full` for complete language reference (syntax, types, methods, stdlib, patterns).
Run `blink llms --topic <name>` for specific topics. Run `blink llms --list` to see topics.
Run `blink query <file> --fn <name>` to look up function signatures without reading whole files.
Always retrieve Blink docs before writing Blink code. Prefer retrieval-led reasoning over pre-training.

## Correctness

IMPORTANT: This is a programming language! If there are latent bugs, they WILL be found by users. 
Our codebase will be used as training data for future use of
this same langauge. We do not half-ass anything. We build it right. We build it correct. 
Ignore short-term gain, and always think about what is most correct according to:
1. The spec, and what the language is supposed to do
2. Long term health
3. Correctness

## Architecture

Pipeline: lexer → parser → typecheck → codegen → C output.
Entry points: src/compiler.bl (compiler), src/cli.bl (CLI tool), src/blinkc_main.bl (compiler binary).
Stdlib: lib/std/. Tests: tests/. Spec: sections/. Decisions: decisions/.
Build output: build/ (gitignored). Temp files: .tmp/ (gitignored, use instead of /tmp).

## Build & Verify

Bootstrap: `task bootstrap` — builds blinkc at `build/blinkc`. Requires `blink` on PATH or existing build/blinkc + build/blink (gen0 needs both: blinkc to emit gen1.c, blink to build the stdlib archive).
Regen: `task regen` — rebuild compiler from source + verify (Gen1 vs Gen2 fixed-point).
Adding a lib/std or lib/pkg module: just run `task regen` — the embedded registry refresh is automatic (no manual edit to src/embedded_stdlib_registry.bl).
CLI: `build/blink build <file.bl>` | `build/blink run <file.bl>` | `build/blink check <file.bl>` | `build/blink doc <module>`
Build CLI: `task build-cli` — produces `build/blink`
Test: `task test` — compile+run all test_*.bl in tests/
Test formatter: `task test-fmt` — golden outputs + idempotency + semantic checks
Single test: `task compile-test -- test_name`
Verify: `task ci` — regen + test + test-fmt. Always run after compiler changes.
Quick run: `build/blink run <file.bl>` — compiles and runs in one step. Prefer this over manual blinkc+cc.
Low-level (dev): `build/blinkc <file.bl> <output.c>` then `cc -o <binary> <output.c> -lm`
Archive-linked (dev): `build/blinkc --link-archive build/libblink_std.h <file.bl> <out.c>` then `cc -o <bin> <out.c> -Ibuild build/libblink_std.a -lm -lgc -pthread -Wl,--gc-sections`
After modifying compiler sources: `task regen` then `task ci` to verify.

## Debugging

Inspect generated C: `build/blink build --emit c <file.bl>` — output goes to `build/<name>.c`.
Trace compiler phases: `build/blink run --blink-trace codegen <file.bl>` (also: lex, parse, typecheck, all).
Fine-grained internal trace: `BLINK_TRACE_CHANNELS=<ch>[,<ch>...|all] build/blink build --emit c <file.bl>` — env-gated `dbg_trace(channel, msg)` taps (defined in ast.bl, the DAG root, so any module can emit). Emits `[dbg:<channel>] ...` to stderr; zero cost when unset. Prefer adding a permanent tap over a throwaway printf+recompile. Current channels: `monotid` (the tid twin's per-slot arg_tid at resolution); `kopsctor` (the
Set()/Map() ctor's element resolution — raw annotation name, name resolved through the mono
context, its tid, and the tid's tuple tag; this is where a wrong kops table gets baked);
`retmono` (the tid-native struct-mono tier's verdict at every struct literal. Since br qnpb2d that
tier is the PRIMARY producer at this seam, so a decline is consequential — it hands the site back to
the string-CSV tier rather than merely losing a tie. Admission is now ONE predicate per slot:
`admit=slot_encodable` carries the CSV the tier answered with, `decline=slot_unencodable` the
offending slot/idx/ct. The latter is a genuinely unspellable slot (typevar, unknown, List, fn), NOT a
policy veto — a slot appearing there is a `tc_struct_slot_encodable` gap to close in the PRODUCER,
never a reason to re-prefer the string. The three structural declines stay distinct because they mean
different things: `decline=bare_base` is a memo holding only the bare base (a typecheck memo bug),
`decline=no_inst_tid` is no per-node instance tid at all, and `decline=nesting_level_mismatch` is the
guard stopping an inner literal from adopting an outer annotation's slot. It is UNCONDITIONAL and, since
br htxpmh, reads **0** on the pinned corpus (4 rows over 3 fixtures before): emit_struct_lit's field loop,
defaults loop and enum-variant ctor
loop now retarget both `cg_let_target_ann` and `cg_expect_arg_ann` to the field's own annotation
(descending through the instantiation when the field is declared as a bare binder), so a nested literal
is handed the annotation describing itself and cannot adopt its parent's.
That 0 is an UNEXERCISED TAP, NOT COVERAGE, and br jefm9w established the difference by trying to delete
the guard on the strength of it — which is how the FIELD-ACCESS RECEIVER gap below was found. The
retarget covers struct-field values, defaults and enum-variant ctor args; it never touched a literal in
receiver position, where the enclosing `let`/arg annotation describes the RESULT of the access and not
the receiver: in `let n: Box[Set[Int]] = Box { value: Box { value: Set() } }.value` the outer literal is
really `Box[Box[Set[Int]]]`, but `cg_let_target_ann` names `Box[Set[Int]]` and the bare-name match
adopted `Set` one level too high. That was br qah9tx (CLOSED). The `Set`/`List` carriers stayed green
only because the jefm9w veto downstream declined the bad adoption; the shapes it does not catch —
`let n: Box[Str] = Box { value: Box { value: "z" } }.value` and the three-level
`Box { value: Box { value: Box { value: 3 } } }.value.value` — were hard cc errors at HEAD
(`incompatible types when initializing`), pinned red in `tests/test_qah9tx_fieldaccess_receiver.bl`
before the fix. Fixed with a scoped context flag, `cg_fa_receiver_ctx` (`codegen_types.bl`): the
FieldAccess handler in `emit_expr` sets it true only around the receiver's own `emit_expr(fa_obj)` call;
`tid_native_struct_inst_tid` skips its ann-based bare-name-match branch entirely while the flag is true,
falling through to the literal's own memoized tid instead. Clearing the ann channels outright (tried
first) was too blunt and REGRESSED kops resolution — `field_ann_at_instance`'s descent, used by the
htxpmh retarget, reads those same two channels to resolve a NESTED field's bare-binder type argument, and
the "leaked" receiver-result annotation is exactly the correct descent target one level down for whatever
is nested inside the receiver (a `Set()`/`Map()` ctor, an `Option` carrier). So `emit_struct_lit`
explicitly suspends `cg_fa_receiver_ctx` back to false around all four of its nested recursive emissions
(enum-variant ctor field, spread, field value, defaults) — the flag narrows ONLY the receiver literal's
own top-level identity resolution, never anything nested inside it. All four shapes (the two hard
cc-errors plus the two previously-masked `Set`/`List` rows) go green together under this fix, confirmed
via `tests/test_qah9tx_fieldaccess_receiver.bl`, `tests/test_jefm9w_parity_veto_live.bl` rows B/B2, and
`tests/test_htxpmh_field_loop_value_ctx.bl`, all green on a fully regenerated tree.
A `decline=nesting_level_mismatch` row now means one of two things: a nested-emission site the
retarget does not reach, or an ALIASED slot, because the guard cannot tell a wrong nesting level from a
second spelling of one type — `type Alias = Int` mints its own tid, so
`let p: P[Alias, I64] = P { a: 1, b: 2 }` reads as a contradiction, loses the literal to the string tier
and ICEs (I0001, measured at 1a0f961). That false positive is real and belongs to the
alias-canonicalization family (br q38hbk); it is a reason to fix the speller, not to drop the guard.
Above all do not read a decline as a reason to prefer the string tier in general (see below).
Measure any claim here against a FULLY REGENERATED tree: a partially-rebuilt one reports stale C and
produced two false liveness readings on jefm9w's first attempt.
The retarget is gated on `value_ctx_ann_spellable`, applied to
`field_ann_at_instance`'s DESCENT RESULT so it covers BOTH channels: an annotation that still spells a
type-param binder leaves them alone rather than overwriting them. Two independent reasons, and both were
measured, so do not narrow the gate to one channel. (1) The consumers of `cg_let_target_ann`
(`resolve_ctor_kops_elem`, `resolve_ptr_inner_c`) read a binder as no-information and fall back to a
default — an int-keyed Set dropping to `blink_kops_str`, a `Ptr[T]` field allocating `sizeof(void)`.
(2) The VOCABULARY BOUNDARY, which is why gating only that channel was itself a regression: the descent
result is spelled in the ENCLOSING scope's type-param vocabulary, but both channels are then read while
`cg_mono_tparams_sl` holds THIS struct's tparams, so a surviving binder is resolved BY NAME against the
wrong list. The tempting argument that a binder is inert in `cg_expect_arg_ann` because it cannot match a
head-name gate holds only for a BARE binder; `Set[K]` has a concrete head that matches and a foreign
binder inside. Measured on `type P[K, V] { m: V, spare: K }` + `fn mk[K](_k: K) -> P[Int, Set[K]]`: an
ungated `cg_expect_arg_ann` gave a `Set[Str]` the `blink_kops_i64` vtable and `contains("prefixedBBBB")`
returned **true** (keys compared as the first 8 bytes of char data — silent, clean cc), and renaming the
fn's type param `U`→`T` flipped a correct `blink_kops_str` into an undeclared
`BLINK_COMPILER_BUG_kops_unsupported_K_ct20_Set`, a cc-time break on a legal program keyed on a cosmetic
identifier. The tuple-wrapped shape of the same underlying mechanism is br 3aa3je. `retry=mono_subst` means substituting the enclosing mono context is what let the tier
answer. The pre-qnpb2d spellings `decline=slot_unclassifiable`, `decline=ret_target_mismatch`,
`decline=no_admission_reason` and the `admit=string_target_tid`/`admit=has_ret_target` split are GONE
— they named the four-lens triad the single predicate replaced); `retann` (the def-side return-annotation tier —
which gate declined a struct literal in a monomorphized generic fn's tail, or the CSV it resolved
to; the tier is last-resort, so silence here means an earlier producer answered); `retpin` (every
`tc_pin_tail_ret_generic` that made it past all four gates, with the declared and inferred types
it unified). Every pin mutates `ty_pool` IN PLACE, so adding a pin caller can change emitted C for
programs unrelated to the new seam — `retpin` is how you audit that blast radius without a
printf+recompile; silence on a program means no pin fired for it. `monodedup` (every
`merge_arg_tids` join on a mono-registry `(base, args)` dedup hit — `upgrade` when a degraded
stored `arg_tids` gained a slot, `slot-conflict` when two DIFFERENT concrete tids were offered
for one slot, `arity-conflict` on a length disagreement. `upgrade` is the blast-radius audit
for br p7014w: zero upgrade lines on a program guarantees its emitted C is unchanged by the
join a priori, which is a cheaper and stronger argument than a byte-diff. `slot-conflict` is
NOT a bug in the join — it means the `(base, args)` key collapsed two tids onto one slot, and
the join has no way to tell WHY. `slot-conflict-class` is the row that can: emitted once per
recorded conflict by `tc_classify_mono_conflicts` at the end of `generate()`, with
`verdict=same-type` or `verdict=DIFF-TYPE` and both tids rendered via `tc_type_str`.
NEVER discriminate on the tid NUMBERS: `new_type` (`src/typecheck.bl:566`) appends
unconditionally and `ty_pool` does not intern compound types, so two tids for one type is the
NORMAL state — the comparison must be structural (`tc_tid_same_type`).
`verdict=same-type` is that interning artefact and is harmless under br qnpb2d (either tid
lowers identically). `verdict=DIFF-TYPE` means one key genuinely holds two different types;
that is CORRECT when the segment is representation-keyed (`Set[Int]` and `Set[Str]` are both
`blink_set*`, share one C symbol, so they MUST share one registry entry) and the predicate for
"may this slot be read as per-instantiation identity" is `tc_tid_seg_injective`, not the `args`
spelling. Measured on the 700-fixture corpus: 43 raw `slot-conflict` rows over 13 fixtures →
25 same-type and 18 DIFF-TYPE, `arity-conflict` 0. 19 of the same-type rows are spread over 12
fixtures (`Box_Int`, `Result_Box_Int_str`, `LocBox_Int`, `Option_Box_Int`, `Option_int`,
`Option_Cmd`, `Tuple2_Option_int_int`, `Tuple2_Result_str_int_int`); the other 24 rows (6
same-type + ALL 18 DIFF-TYPE) are in `tests/test_jkdywb_tuple_inline_container.bl` alone, and
every DIFF-TYPE one is container-class (`Set[Int]` vs `Set[Str]`/`Set[Point]`, `Map[Int,Str]`
vs `Map[Int,NineBox]`/`Map[Point,Int]`). A DIFF-TYPE row
whose segment DOES name its own type arguments would be a real bug (the q4etvt class) — and
note rows come in pairs at the generic-fn seam, since `register_mono_fn` and
`register_mono_instance` both join the same key.); `monofield` (the
def-side mono SLOT resolvers — `bail=no_ann`/`bail=empty_arg_tids`/`bail=arity` are the recovery
net `mono_arg_tids_with_ann` giving up, and `binder-survived` is a slot that reached emission still
spelled as its own type-param binder, i.e. an erasure to `void v;` or `blink_Option_void v;`.
`binder-survived` now also raises I0001 (which carries the same owner in its message and site in its
help), so on a normal build that arm is already fatal and loud — the channel's real value is the
three BAILS, which are otherwise completely silent. Two
things it CANNOT see: a slot whose unresolvable answer is a TUPLE STEM rather than a binder, and
any erasure outside these four resolvers. The 3aa3je citation for the first of those is now
HISTORY, not a live example — re-measured at br htxpmh, `let b: Box[(Box[Int], Int)] = Box { v:
(Box { v: 7 }, 5) }` emits the correct `blink_Tuple2_Box_Int_int v;`, byte-identically before and
after the retarget; what remains of 3aa3je is a tuple ACCESS defect (`b.v.0.v` for `b.v._0.v`).
The blind spot itself is structural and unchanged — a tuple-stem slot would still be silent here
— but there is currently no fixture exhibiting it, so treat it as an UNEXERCISED gap rather than
a known-reachable one. Measured floor is 0 — `binder-survived` and every `bail=*` —
across the same 728 codegen-reaching files described under `ctagvoid` below, in the same sweep. A
nonzero reading is a regression, not noise.) `ctagvoid` (the four
things `tc_tid_to_c_tag` used to spell with the ONE string `"Void"`, now separated — br hsgsbp.
`producer=genuine_void` is a real `TK_VOID` type argument, which is LEGAL and expected: Void is "an
ordinary INHABITED, encodable type" (`decisions/under-determined-types.md:38-42`, 6-0), so this
bucket is informational and never an error. `producer=unhandled_kind` (with `k=`/`name=`) is a kind
with no arm — `TK_FN`, `TK_CLOSURE`, anything added later; `producer=out_of_range` is a negative or
out-of-pool tid. Those two are ARMED to `BLINK_I0001_*` sentinels, so a nonzero reading is a real
bug in the CALLER, and the arming premise is exactly "both read 0" — re-measure before adding a
`tc_tid_to_c_tag` caller that does not gate `tid < 0`. `probe=encodable_void` is a permanent
COUNTERFACTUAL tap in `tc_tid_encodable`: every row is a site where rejecting `TK_VOID` — what br
hsgsbp originally asked for, and what `DECISIONS.md:342` forbids — would have flipped the answer and
routed a genuine Void onto the string path. It also shows the propagation: the `TK_RESULT` arm means
rejecting the kind would make `Result[Void, Str]` unencodable, a type `lib/std/` depends on and one
the compiler synthesizes for every `?`-bearing `test` block. Measured (2026-07-30) over the 743-file
corpus `tests/*.bl` + `examples/*.bl` + `examples/with_deps/{app,mathlib}/src/*.bl` + `src/cli.bl` +
`src/blinkc_main.bl`, of which **730 actually reach codegen** — 15 die in an earlier phase and so
cannot reach any of these taps (`tests/xtest_question_mark_errors.bl` by design, plus 13 stale
`examples/*.bl` and `with_deps`' app compiled standalone without its package context; note
`task ci` does not compile `examples/` at all, so those are unguarded). Do NOT write the sweep as
`examples/with_deps/app/*.bl` — that glob matches nothing, and a sweep using it silently reports the
package as covered while contributing zero files. On that corpus the two ARMED buckets read
**0** — that is the arming premise, re-measure before trusting it — while `genuine_void` reads **22**
and `probe=encodable_void` **20**, all 42 in `tests/test_hsgsbp_box_void.bl`, the only fixture that
instantiates anything at Void. (`probe=encodable_void` was 18 until the string-CSV producer was
retired; the tid seams that replaced it call `tc_tid_encodable` twice more on genuinely-Void tids.
The fixture's emitted C is byte-identical across that change, so the +2 is extra TAP TRAFFIC, not a
behavior change — do not read a moved count here as a regression without diffing the C.)
Those two counts are the live-tap proof: before that fixture existed
all four buckets read 0 and it was an UNEXERCISED TAP, not coverage, provable only by hand-built
shapes. If `genuine_void` ever drops back to 0, the fixture stopped reaching the tap — check that
before concluding anything from the armed buckets' 0.
NOTE the lowercase twin `tc_tid_scalar_tag`/`tc_tid_inner_tag` still carries all three meanings in
`"void"` and is deliberately NOT armed — its fall-through is load-bearing for `Result_void_str`. See
the comment on `tc_tid_scalar_tag` before "finishing the job" there.) (`csvresolve` is
retired — the legacy string-CSV type-param resolver it tapped no longer exists.)
NOTE: `build/blinkc` IGNORES `BLINK_TRACE_CHANNELS` — `dbg_channels` is assigned only in
`src/cli.bl`, so a probe binary for tracing must be built from `src/cli.bl`, not
`src/blinkc_main.bl`, and (because the stdlib registry root is argv[0]-derived) must live in
`build/` (br m5ztt6).
Runtime trace: `build/blink run --trace all <file.bl>` (NDJSON to stderr, filter: `fn:name`, `module:mod`, `depth:N`).
Debug build: `build/blink run --debug <file.bl>` — enables debug_assert, compiles with `-g -O0`.
When debugging codegen bugs, inspect the emitted C first (`--emit c`), then use `--blink-trace codegen`.

Measuring type-erasure in emitted C: grep the emitted C for `_Void`, and filter out `blink_test_*`
symbols (a test whose NAME contains "Void" mangles into one) — and note that a test asserting
ABOUT erasure can carry the pattern in a plain string literal, so read the matched lines before
calling one a hit. A `_Void` in a monomorphized name (`blink_GKV_Void_Void`) means a type param was
erased — and because the erased name is a valid C identifier under an `#ifndef BLINK_TD_` typedef
guard, it compiles and links silently while collapsing distinct instantiations onto one C type.
This grep is a LOWER BOUND, not a sound metric, and never an exit criterion on its own. It finds
only the STRING producers' erasure spelling. The tid producers erase differently: a slot they
cannot name passes the binder through unchanged, so the symbol is `blink_Box_T` — no `_Void`
anywhere. Worse, a def-side field can erase while the mono NAME stays correct
(`blink_QBox_Int { blink_Option_void v; }`), which the grep cannot see at all. Both shapes are
real and both were found with the grep reading 0 (br pt4hsy, br w4c0py).
Check for BOTH spellings, and treat a clean C compile as necessary, not sufficient — a `void`
field errors loudly but an erased carrier field does not.
That `void <name>;` loudness is a LOAD-BEARING tripwire, and `c_field_type_str`
(`src/codegen_types.bl`) is built to preserve it: it lowers a Void field to an `int64_t`
placeholder only when the resolved type NAME is literally `"Void"`, never on `CT_VOID` alone —
`type_from_name` collapses `""` and every unknown name onto `CT_VOID` too, so a CT-keyed predicate
would silently swallow an erased slot into a well-typed field. Do not "simplify" it to one argument.
The retired `csvresolve` channel was a lower bound for the same reason:
`blink_GSet_Void`/`blink_GBoxSet_Void` were emitted with zero hits on it, because a producer's
`"Void"` initializer never routed through the tapped return.

## Self-Hosting Bootstrap Protocol

The compiler compiles itself. `task regen` verifies by compiling the compiler twice (Gen1 + Gen2)
and diffing the output — they must match.

Adding a new feature (2-step):
1. Add the feature to the compiler (parser/codegen/etc) → `task regen`
2. Now use the feature in compiler source code → `task regen`

Refactoring/breaking existing behavior (3-step):
1. Add new syntax/behavior alongside the old → `task regen`
2. Migrate compiler source to use the new way → `task regen`
3. Remove the old way → `task regen`

NEVER skip steps or combine them. Each regen locks in the previous change so the
compiler can still compile itself.

## Design Panel

Feature discussions require the 5-expert panel (systems, web/scripting, PLT, DevOps/tooling, AI/ML).
Majority vote required. Record in DECISIONS.md. See OPEN_QUESTIONS.md for archive.

## Task Tags

All tasks use `repo:blink` + one type tag:
- `type:bug` - write failing test → fix → regen → ci.
- `type:feature` - plan → confirm → implement.
- `type:project` - break down into subtasks.
- `type:friction` - triage → create bug/spec/feature tasks.
- `type:spec` - panel deliberation via `/deliberate`. This task type is specically for deliberating on programming language changes. Things that change the spec of the language itself. Things that effect blink users, not just this codebase. Not feature work. Spec "discussion".
- `type:chore` - carry out task

## Friction Log

When working on the compiler, log a br task whenever you hit:
- Spec ambiguity (unclear what correct behavior should be)
- Surprising behavior (spec says X but intuition expects Y)
- Missing features (spec doesn't address something the compiler needs)

Log with: `br add "<description>" -t repo:blink -t type:friction`
For blocking issues, use `type:bug` or `type:spec` directly instead of friction.

## Logging bugs
You can log bugs you find using `br add "<description>" -t repo:blink -t type:bug`.
Make sure you always provide a MVCE in the description for reproduction steps.
If you "work-around" the bug, you also need to add a task to `br` for cleaning up the workaround
once the bug is fixed, by making it depending on the bug ticket. 
