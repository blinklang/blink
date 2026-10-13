# Daemon recheck: reuse the work of modules an edit did not touch

Status: design, not built. The user approves it before any slice starts.

## Why

A daemon check after an edit takes as long as a cold check, because the worker runs the
whole front end again. A wrong check is worse than a slow one. This note gives the rule,
the proof sketch and the tests before any code.

## Numbers (step 1)

Binary: `build/gen1/bin/blink` of tree 5bbecc46. Entry: `src/cli.bl`. The edits are made in
`src/cname.bl`. Each case ran 5 times under `setarch -R`, with load 0.36 to 0.93. Script:
`m1.sh`. The logs are kept beside the ticket's other logs (w151).

| case | cold median (range), s | warm median (range), s |
|---|---|---|
| (i) private body edit (`strip_blink` gets one more local) | 0.405 (0.402-0.414) | 0.407 (0.402-0.412) |
| (ii) pub signature edit (rename a param of `c_variant_member_name`) | 0.403 (0.402-0.412) | 0.407 (0.402-0.415) |
| (iii) no change | 0.410 (0.400-0.412) | 0.009 (0.009-0.009) |

The output is 475 KB and holds 382 warnings. Warm output and cold output are byte-equal in
14 of the 15 pairs. In the remaining pair, the first cold run also prints
`resolving dependencies...`, once.

Phase split: `perf record -F 1999 --call-graph dwarf` on the daemon worker. `classify.py`
sorts each sample of the worker main thread into one phase by its stack. The numbers are
CPU ms on that thread for each check, not wall time.

| phase | (i) body | (ii) pub |
|---|---|---|
| lex | 25.4 | 28.1 |
| parse | 53.4 | 58.9 |
| comment attach | 14.5 | 15.8 |
| load, other | 3.9 | 4.5 |
| typecheck: resolve_names | 58.3 | 63.6 |
| typecheck: fn bodies (tc_check_fn) | 57.6 | 63.9 |
| typecheck: stamp | 32.8 | 35.8 |
| typecheck: registration and other | 14.6 | 14.5 |
| typecheck: effect rows | 8.1 | 9.7 |
| escape | 34.6 | 40.1 |
| mono | 16.8 | 18.6 |
| mutations (write sets) | 14.1 | 15.1 |
| save/restore | 9.9 | 10.9 |
| analyses, inlined/other | 10.4 | 14.2 |
| index of the entry | 7.5 | 8.6 |
| render | 5.5 | 4.2 |
| **reply path** | **367.4** | **406.6** |
| settle, after the reply (11.8 of it is `interface_text_of`) | 21.0 | 22.1 |

The wall median is 0.407 s and the sampled reply path is 0.367 s. The 40 ms difference was
not sampled: it is the client process, the socket, and the time the worker spent off the
CPU (for example, waits for the GC marker threads). The GC marker threads used 166 ms of
CPU for each check, in parallel. In case (iii), the worker compares the input bytes and
replies from its last result, so there is nothing for this design to save.

Per-module share of typecheck time was not timed. As a proxy, `--blink-trace parse` gives
the token count of each source: 71 parsed sources, 62 module names, 675871 tokens and
4423 fns. `cname.bl` has 1.15% of the tokens and 2.71% of the fns, and it is source 27 of 71
in load order. `typecheck.bl` alone has 23.4% of the tokens. The reverse import closure of
`cname` (`cname` and each module that imports it, directly or not) has 21 modules and
44.5% of the tokens.

## 1. State each phase builds

The daemon calls `reset_compiler_state` (`src/compiler.bl:1298`) and `parser_reset` for
each check. Then `check_source_reporting` (`src/check_pipeline.bl:69`) builds all of the
state below again, starting from node 0.

- **Lex and parse.** All modules share one node arena: `columns` (`src/parser.bl:140`),
  `node_count` (`:1211`), and one sublist pool `sublists` (`:156`). `source_module_for_node`
  (`:205`) maps a node to its module. Node ids are given in load order (`load_module`,
  `src/compiler.bl:1373`; `collect_imports`, `:1461`). An edit to a module that loads early
  therefore moves the ids of every module that loads after it.
- **Per-module records.** `record_source_nodes` (`src/compiler.bl:1335`) keeps the node range
  of each module and its interface text (`parsed_interface_text`, `src/parser.bl:1243`;
  `interface_text_of`, `:1288`). This is the only per-module structure today.
- **Merge.** `merge_programs` (`src/compiler.bl:878`) puts all modules into one program node.
  Its sublists hold all types, fns, impls, traits, lets, tests and effects. Each later pass
  walks these global lists.
- **Typecheck.** `check_types` (`src/typecheck.bl:11322`) uses 184 module-level `let mut`
  globals. All are global; none is per module:
  - types are interned in check order: `ty_pool` (`:150`), `ty_intern` (`:1525`);
  - per-node results: `tc_node_tid` (`:156`), `tc_call_decl` (`:12449`);
  - signatures: `fnsig_map` (`:270`), `fnsig_pool` (`:352`), `fnsig_effect_names` (`:396`);
  - traits and impls (`:398`-`:444`, `nr_impl_*` `:14153`-`:14158`);
  - bare-name maps: `tc_symbol_module` (`:1374`), `nr_decls_by_name` (`:12407`),
    `tc_fn_node_by_name` (`:9851`);
  - under-determined checks waiting for the end of the program (`:2476`-`:2489`).

  `init_types` (`:11163`) resets `ty_pool` and `tc_node_tid`.

  The passes run in this order: register types, fn signatures, traits and impl signatures,
  then `resolve_names` (`:14470`), then `tc_infer_program` (`:23578`). `tc_infer_program`
  checks module lets, global initializers, each fn, impl methods, trait default bodies,
  tests, effect rows (`:25283`), and last the under-determined flush (`:2590`, `:2687`).
  Then the stamp pass runs.

  Typecheck writes to nodes: it stamps each node's module (`:12951`), sets names and puts
  them back (`:11659`, `:23710`), and `desugar_sealed_ops_calls` (`:17381`) rewrites call
  nodes in place. A second run of that rewrite on the same program is an ICE (`:17383`).
  `typecheck.bl` does not call `new_node`.

  An incremental filter exists (`tc_inc_enabled`, `:1460`; `tc_set_incremental_filter`,
  `:6445`), but no code calls it.
- **Analyses.** `run_build_analyses` (`src/check_pipeline.bl:19`) runs the sealed-ops
  desugar, then the mutation analysis, the save/restore check, escape analysis and mono:
  - `analyze_mutations` (`src/mutation_analysis.bl:406`) keys fns and globals by bare name
    over the whole program (`:25`-`:82`) and closes write sets over call edges
    (`propagate_writes`, `:356`).
  - `analyze_save_restore` (`:881`) warns at each call, using the callee's closed write set
    (`sr_check_call`, `:683`).
  - `analyze_escapes` (`src/escape.bl:2293`) runs once for each top-level fn and reads
    callee facts from the typecheck tables. It keeps `ea_promote_nodes` for codegen.
  - `run_mono` (`src/mono.bl:192`) finds generic instances from all roots, transitively.

  When the front end reports errors, only escape analysis runs.
- **Diagnostics.** The sink `diag_entries` (`src/diagnostics.bl:442`) is in emission order.
  `diag_filter.seen` (`:445`) drops repeats across the whole program. `diag_render_from`
  (`:984`) prints the entries in order, then the counts.
- **Daemon.** `daemon_run_check` (`src/daemon.bl:168`) checks, then renders one format.
  `daemon_settle_check` (`:200`) fills the interface texts and renders the other format.
  A build child forks from the checked program, so after each check every table that
  codegen reads must be as a cold check leaves it.

## 2. What crosses modules

M is the edited module. N imports M. P does not import M.

| what | how it crosses | an edit in M can change N | can change P |
|---|---|---|---|
| impls and traits | program-wide tables; method calls resolve against every impl in the program | yes | yes. Test: module `a` calls `p.size()` on its own type, and module `b` (which `a` does not import) has `impl Sizer for Pt`. The check is clean with `b` loaded and `UnresolvedMethod` without it. |
| effects | declared only. `tc_er_fn_row` (`src/typecheck.bl:25180`) reads the declared effects; a body adds none. | only through an edit to a signature | only through an edit to an impl or trait signature |
| inference (metavars) | made for each binding inside a body. A fn with no return annotation returns Void (`register_fn_sig`, `:9176`), so no type that other modules see is inferred | no, for a body edit | no |
| type ids | `ty_pool` interns types in check order. A body edit in M can intern a new type and move the tid numbers of every type interned after it | tid numbers only, not types | tid numbers only |
| generic instances | mono walks from all roots. An instance of a generic in M is made for a call in N | yes: the instances and their mono diagnostics (for example `InvalidPtrType`, `src/mono.bl:1000`) | through any chain of generic calls |
| constants and module lets | the initializer is outside fn bodies, so it is in the interface text. Bare-name maps (`tc_symbol_module`) mix same-named private lets of two modules | yes, for a let edit | yes: the bare-name collision |
| mutation write sets | taken from bodies, closed over all fns by bare name | yes: a private body edit in M changes the write set of M's fns, and so the warnings at calls in N. The interface text does not show this. | yes: a same-named private fn in P gets M's write set, a bug |
| escape | per fn. It reads callee signature facts (`tc_call_decl_node`, `tc_fn_has_effect`) | only through a signature | only through a bare-name collision |
| repeat filter | `diag_filter.seen` is program-wide | yes: removing a diagnostic in M can let an equal one print in N | yes |

## 3. The reuse rule

**Key.** A check may reuse results when it matches the last check in all of these:
- the compiler, the entry, the flags and the loader's probes (the fields of
  `CheckedInputs`, `src/check_pipeline.bl`);
- the set of loaded sources and their load order;
- the interface text of every source.

Only the bytes of a set E of sources may differ. The key is program-wide, not the import
closure of a module, because impls, traits and the bare-name maps cross to modules that do
not import M (section 2). If any interface text differs, the check runs cold. A private
signature edit and a pub edit (case ii) therefore get no gain.

**Keep, for each module not in E:**
- its nodes, at the same ids;
- its per-node typecheck results;
- its per-fn results of `resolve_names`, `tc_check_fn`, stamp and escape;
- its diagnostics from those passes.

**Redo:**
- lex, parse and comment attach of E;
- all of registration, so the name tables point to E's new declaration nodes;
- resolve, check, stamp and escape of E's items;
- effect rows and the under-determined flush;
- unused imports for E;
- for the whole program, each time: the mutation analysis, save/restore and mono;
- render.

Redoing these three for the whole program removes the need for a write-set summary in the
key. Their cost is 40.8 ms. A later slice can put the closed write set of each fn in the
key and redo save/restore only for the callers it affects.

**A body edit that changes a type or effect that other modules see.** This cannot happen:
- Return types are declared, or Void (`:9176`).
- Effects are declared (`:25180`).
- Module-let initializers, impl headers, trait items and every signature are in the
  interface text. A change to any of them fails the key.

Three things leave a body by another path:
- generic instances, which mono covers;
- write sets, which the mutation analysis and save/restore cover;
- tid numbers, which change only numbering.

The first two are redone each time. For tid numbers, the rule requires that no
output depends on a tid number. The differential test checks this.

**Stable node ids.** Put E's new nodes at the end of the arena, after the old nodes. E's old
range is then dead. Make the merged program lists again from each module's own lists, in
the cold load order, so every walk visits the modules in cold order. Before the next check,
undo the `desugar_sealed_ops_calls` rewrite on kept nodes, or the reused nodes are not the
parsed nodes. When dead nodes outnumber live nodes, run cold and start the arena again.

**Builds.** Until the build test in section 5 passes for a slice, a build after a reuse
check runs a cold check first. This is the cost a build has today.

## 4. The diagnostics rule

A check with reuse must print the same bytes as a cold check, in the same order, in both
formats. The counts and the `FrontEndReport` fields must also be equal.

- **Buckets.** Store each module's entries by bucket: (pass, item index in the merged
  list). The passes are in cold order: registration, `resolve_names`, the
  `tc_infer_program` sub-passes (module lets, global initializers, fns, impl methods, trait
  defaults, tests), stamp, unused imports, then the analyses. A per-module key is not
  enough: M's impl methods are checked after the fns of all modules.
- **What to store.** Store the entry after `@allow` is applied but before the repeat
  filter. Store it as rendered fields (file, line, column, text, notes), never as node ids.
- **Replay.** Walk the passes in cold order. For a kept item, push its stored entries
  through the sink's entry point, so `diag_filter.seen` drops repeats as it does in a cold
  check. For an item in E, run the pass. The whole-program passes (effect rows, the
  under-determined flush, mutations, save/restore, mono) run again, so their order is cold
  order without replay.
- **Counts.** Count `diag_count`, `diag_warn_count`, the ICE count and
  `FrontEndReport.entries` from the replayed sink. Render the front report after the front
  passes replay.
- **Branch.** If the replayed counts show errors, run escape only, as a cold check does.
- **Lex or parse errors.** If E has a lex or parse error, run cold.

## 5. Proof sketch and tests

**Sketch.** Take one kept item i of module N, in one pass. A cold check computes i's results
from these inputs:
- N's tokens, which are equal because N's bytes are equal;
- the registration tables, which come from interface tokens only and so are equal when all
  interface texts are equal;
- the impl and trait tables, which come from the same tokens;
- global state that earlier items left behind.

The first three are equal by the key. If the fourth reaches no output, i's diagnostics and
per-node results are equal to cold, and replay in cold pass order with the same filter
gives the same sink, so the same bytes. The whole-program passes are recomputed from equal
or recomputed inputs.

The weak step is the fourth input. The 184 typecheck globals and the tid numbering can leak
from one item to the next. The proof does not close this step; the differential test below
must catch any leak.

**Differential test** (a harness under `tests/`, added in slice 1):
- For each edit, a daemon check with reuse must print the same stdout, stderr and exit code
  as a cold `blink check` (no daemon) of the same tree. Compare byte for byte, in human and
  in `--format json`.
- The edits, for each module: a whitespace or comment edit; a new local in a private fn; a
  changed literal; a call added to, or removed from, a fn that writes a global (this changes
  a write set); a new warning; a new error, then its fix; a new instance of a generic; an
  edit inside an impl method body, a test block and a trait default body; edits to two
  modules at once; a parse error, then its fix; a private signature edit and a pub edit
  (both must run cold); an impl added in a module that the caller does not import; going
  back to the first bytes.
- Run the edits on `src/cli.bl` with `src/cname.bl`, and on each `tests/test_*.bl` that has
  imports. For the corpus, use a seeded generator of body edits at 3 positions in each file.
- **Build equality.** After a reuse check, `blink build --emit c` through the daemon must
  give the same C as a cold build. Until this passes, builds take the cold path of
  section 3.
- **Reuse counter.** `blink daemon status` counts the modules reused. Each test asserts
  that the counter is not zero, so the fast path cannot fall back to cold without notice.

**Mutations.** Each change below must make the differential test fail, with the edit that
catches it:

| mutation | edit that catches it |
|---|---|
| skip mono | a new generic instance |
| keep the old write sets | a call added to a fn that writes a global |
| leave impl headers out of the key | an impl in a module that does not import the caller |
| replay without the repeat filter | a removed diagnostic that hid a repeat |
| replay by module, not by pass | any module with an impl method warning |
| keep E's old `tc_node_tid` | a new local in a private fn |
| leave replayed entries out of the counts | a new error |
| skip the desugar undo | any edit to a module that calls a sealed ops method |

## 6. Expected gain

These figures come from case (i) above, in ms on the worker main thread.

The work that is always redone:

| work | ms |
|---|---|
| registration | 14.6 |
| effect rows | 8.1 |
| mutations | 14.1 |
| save/restore | 9.9 |
| mono | 16.8 |
| analyses, inlined/other | 10.4 |
| index of the entry | 7.5 |
| render | 5.5 |
| **total** | **86.9** |

`cname`'s own share of the per-item passes:
- resolve, check, stamp and escape: (58.3 + 57.6 + 32.8 + 34.6) x 2.71% of fns = 5.0
- lex, parse and attach: 97.2 x 1.15% of tokens = 1.1

The worker floor is therefore about 93 ms. Add the 40 ms that was not sampled: the floor
for a body edit is about **0.133 s, against 0.407 s, a gain of about 67%**. This is a
proxy: it assumes each module's share of a pass follows its share of fns or tokens, and
that kept state costs nothing to keep. It is over the 25% bar, so the idea stays open.

| case | under this rule | later, with an import-closure key |
|---|---|---|
| (ii) pub edit | runs cold, 0.407 s, no gain | about 0.251 s, a gain of about 38%: 44.5% of the per-module work (280.5 ms), plus 86.9 ms, plus 40 ms. This key needs the program-wide crossings in section 2 removed first. |
| (iii) no change | 0.009 s today | 0.009 s |

Slice 1 alone keeps only the load work of unchanged modules: 97.2 - 1.1 = 96 ms, about
24% of the check. That is just under the bar, but slice 1 is what makes the node ids stable,
and every later slice needs that.

## 7. Slices

Each slice comes with its own test and must pass `task ci`.

1. **Keep the parsed modules.**
   - The daemon keeps the nodes of each unchanged module, and lexes and parses only E. It
     puts E's nodes at the end of the arena and makes the merged lists again in cold order.
   - It undoes the in-place desugar rewrite.
   - It runs typecheck and the analyses on the whole program, as today.
   - It runs cold when E has a parse error, or when dead nodes outnumber live nodes.
   - Test: the differential harness and the edit set above, all edits, plus the reuse
     counter.
   - Expected gain: about 96 ms.
2. **Keep per-item typecheck results.**
   - Split `init_types` so that the signature tables are made again while `ty_pool`,
     `ty_intern` and per-node results stay.
   - Store diagnostics in buckets and replay them (section 4). Redo E's items only.
   - Test: the mutation table in section 5.
   - Expected gain: the floor in section 6.
3. **Keep escape results for each fn.** This also needs the build equality test.
4. **Write-set key.** Put each fn's closed write set in the key, and redo save/restore only
   for the callers it affects. Before this slice, the mutation analysis must key fns and
   globals by declaration, not by bare name (this bug is filed).
5. **Import-closure key.** Only after impls, traits and the bare-name maps stop crossing
   to modules that do not import M.
