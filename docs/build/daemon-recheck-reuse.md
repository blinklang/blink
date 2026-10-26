# Daemon recheck: reuse the work of modules an edit did not touch

Status: the user approved the design. Slice 1 is built (see "Slice 1 as built" at the end).
Slices 2-5 are not.

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
| generic instances | mono walks from all roots. An instance of a generic in M is made for a call in N | yes: the instances and their mono diagnostics (for example `InvalidPtrTypeParam`, `src/mono.bl:1145`) | through any chain of generic calls |
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
check runs a cold check first. Slice 1 now passes it; see "Slice 1 as built".

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

## 8. Review points

"In the text" means in the interface text: the tokens of a source with the bodies of its
top-level fns, impl methods and trait methods left out. The parser records a body only at
depth 0 (`src/parser.bl:3200`-`:3206`). Trait methods (`:3505`) and impl methods go through
`parse_fn_def` at depth 0, so their bodies are left out too. A lambda body is not recorded,
so it stays in the text.

**(a) Contracts.** `@requires` and `@ensures` are annotations before the `fn` keyword
(`src/parser.bl:2234`), so they are in the text. They are read only in the check of the fn
that carries them: `pv_validate_fn_contracts` (`src/typecheck.bl:9801`),
`tc_check_contract_verifiable` (`:10127`) and `tc_type_contract_predicates` (`:21455`,
called from `tc_check_fn` at `:21393`). No call site in N reads a callee's contract. A
predicate in N that calls a fn of M reads M's `@pure` flag (`tc_fn_is_pure`, `:9608`) and
M's declared effects (`lookup_fnsig`, `:9586`), by name. Both are in M's text. The key
catches all of it.

**(b) Consts.** A `const` or module `let` initializer is outside any fn body, so the value
is in the text, not only the type. The front end folds no values. N reads another const
only for its `is_const` flag (`tc_name_is_const_binding`, `:21118`) and for an `alloc`
initializer (`tc_ptr_reads_singleton_alloc`, `:9405`). A module let with no type annotation
gets its type from its initializer (`tc_infer_global_initializers`, `:23544`). The
initializer is in the text, so the key catches a change. I did not check whether codegen
copies const values into other units. A build after a reuse check compiles the program that
check made, so this is a question for the unit keys, which the build test compares with a
cold build.

**(c) Impls and coherence.** Only `parse_program` calls `parse_impl_block`
(`src/parser.bl:2366`), so an impl is always top level and never inside a body. Its header,
its where bounds and its method signatures are in the text. Only its method bodies are left
out, and a method body cannot change resolution, because return types and effects are
declared. An impl added to or removed from M therefore changes M's text, and the
program-wide key catches it. A key over N's import closure does not: in the test in
section 2, `impl Sizer for Pt` sits in a module the caller does not import, and the check
passes with that module and fails with `UnresolvedMethod` without it. That is why section 3
keys on the text of every source.

**(d) Bodies that other modules read.** The compiler has no `@inline`
(`rg "@inline" src lib` finds nothing). Typecheck reads a trait default body once, in the
trait's own module, with `Self` left abstract (`src/typecheck.bl:23726`). N's typecheck
never reads M's default body. Three passes read bodies across modules: mono (it makes
instances of generic and default bodies for N's types), the mutation analysis and
save/restore. A body edit does not change the text, so the key does not catch these.
Instead, the rule redoes all three for the whole program on each check (section 3). Escape
reads only callee signature facts. The mutations "skip mono" and "keep the old write sets"
in section 5 test that this redo is required.

**(e) The node arena.** Slice 1 adds stable ids. What it changes:
- E's new nodes and sublists go at the end of `columns` and `sublists`.
- `merge_programs` (`src/compiler.bl:878`) walks the list of per-module program nodes in
  load order, not in id order. E's new program node goes into E's old slot, so merge visits
  the modules in cold order.
- E's new range goes into `file_ranges` (`diag_register_file_range`,
  `src/diagnostics.bl:485`). The ranges do not overlap, and the lookup at `:742` does not
  need them sorted.
- E's entry in `loaded_inputs.source_first_nodes` and `source_end_nodes` is replaced.
  `unit_sources` (`src/cli.bl:2009`) expects these ranges to increase in load order, and
  takes the ranges sorted by node, as `ir_track_sources` needs, with the load index of
  each, so a build after a reuse check tracks the sources a unit reads as a cold build
  does.
- The `desugar_sealed_ops_calls` undo, and a cold start when dead nodes outnumber live
  nodes.

Slice 1 can avoid stable ids by prefix reuse: keep the arena up to the first node of the
earliest edited source in load order, cut it there, and run the loader again from that
source. That needs no id change, but it still needs the desugar undo on the kept part. The
loader parses each source before its imports (`load_module`, `src/compiler.bl:1394` and
`:1449`), so the entry is source 0. The gain depends on where E loads:
- an edit to `cname` (source 27 of 71) keeps 50.2% of the tokens: about 48 ms of the
  97.2 ms load, about 12% of the check;
- an edit to the entry (`src/cli.bl`, the case in the ticket) keeps nothing.

Slice 2 keeps per-node typecheck results by node id. Those results must stay valid for the
modules after E as well, so slice 2 needs stable ids in any case. Prefix reuse only moves
the id work to slice 2, and adds cut-and-reload code that slice 2 then removes.

Recommendation: keep stable ids in slice 1. The id work is the five items above, and the
slice gives about 96 ms for an edit to any source, the entry included.

## Slice 1 as built

**What a recheck keeps.** The daemon worker keeps the nodes of each source whose bytes did
not change. `reset_compiler_state` (`src/compiler.bl`) calls `parser_rewind`
(`src/parser.bl`) in place of `parser_reset`. The rewind undoes every write to a node or
sublist below the parsed end, newest first. It then cuts the pool back to the parsed end.
`parse_source` gives a kept source its old nodes, and lexes and parses each other source at
the end of the pool. Typecheck and the analyses run on the whole program, as a cold check
runs them.

**Key of a kept source.** Its path, its bytes, and the program annotations that the parses
before it handed on (a parse reads them). The interface-text flags of the parser must also
be the same as when the nodes were parsed. A source whose parse reported anything (an
entry, an ICE or a lex cutoff) is never kept.

**Pub edits.** A pub edit keeps the parse of every other source. Slice 1 keeps only parsed
nodes, and a parse reads only its own bytes and the annotations handed to it. A pub edit
cannot change what another source parses to. Typecheck runs on the whole program, so the
section 3 rule (a changed interface text runs cold) is not needed until slice 2 keeps
typecheck results.

**Merge order.** `merge_programs` takes the program nodes in load order, and the loader puts
an edited source's new program node in its old slot. `parser_set_load_order` gives every
walk over node ids the cold load order. `diag_register_file_range` registers each source's
new range, so a diagnostic in the edited source names its file.

**Runs cold when:**
- a parse of this load reported anything. The load after it is cold too;
- dead nodes outnumber the nodes the kept sources hold;
- the load read other sources than the last load, or the same ones in another order. The
  load then runs again with no source kept (`loader_must_redo`), and the daemon drops what
  the first load printed;
- a non-source input of the check changed (`checked_non_source_inputs_changed`,
  `src/check_pipeline.bl`): the entry, a probe answer, a config or an `#embed` file.

**Builds.** A build compiles the program of the last check when that load started from an
empty node pool (`loader_load_was_cold`, `src/compiler.bl`) or kept a source. A load that
kept sources undid the last load in place and parsed each edited source at the end of the
pool, so the program has the cold sources at other node ids, in another id order. The build
child calls `loader_keep_sources_for_build`: it keeps no source and records no write, but
keeps the load order, so `node_load_rank` and `parser_live_ranges` still give load order.
These places read node order in the build:
- `cg_decl_spelled_carrier_tids` and `cg_derive_key_table_nodes` walk the pool. They walk
  `parser_live_ranges()`, which skips the dead ranges and gives the live ones in load order;
- `unit_sources` (`src/cli.bl`) sorts the source ranges by node for `ir_track_sources`,
  whose lookup is a binary search, and maps each read source back to its load index for the
  unit's `uses`. Before, an edited source's range out of order marked every source
  untracked, so each unit had no `uses` and rebuilt more than a cold build would.
Rule (d) holds for the build as for a check: the check that the build compiles ran
`run_build_analyses` (`src/check_pipeline.bl`: the sealed-ops desugar, the mutation
analysis, save/restore, escape and mono) over the whole program, kept sources included,
since `check_source_once` runs it on each clean check. The build child runs none of them
again and writes no node.
A load that undid the last one in place but kept no source, as when the entry carries a
program annotation, is still not compiled: the build checks again from an empty pool
(`src/daemon.bl`, the build turn). The order is not the reason: that load parses every
source after the dead range, and `parser_set_load_order` records its ranges as for any load
that did not start at node 0. The reason is scope. This change compiles only what its
differential test proves equal, a check that kept a source, and keeps every other case as it
was. Such a load is rare (in the slice 1 corpus run, 2 of 1718 edited files), and the
test of that case asserts the cold reload.
A build that finds its inputs changed loads cold at once (`loader_load_cold_next`), so a
build right after an edit checks once. The idle poll (`daemon_recheck_if_changed`, on the
500 ms accept wait, and only when inputs changed) keeps no source. No client waits on it,
and that drops the dead ranges at no cost to a request. A build after a check request that
kept sources checks no more. `BLINK_DEV_DAEMON_KEEP_SOURCES=0` turns kept sources off, to
measure what they save.

**Reuse counter.** `blink daemon status` reports `reused`: the number of sources kept,
summed over the worker's checks.

**In-place writes below the parsed end.** Each one goes through a parser primitive that
records the old value (`node_replace`, `node_widen`, `node_write_int`, `node_write_str`, and
the closed-sublist branch of `sublist_add`), so `parser_rewind` undoes it. Line numbers are
at the slice 1 commit.

| write | where | undone how |
|---|---|---|
| keyword-default fill (`sublist_append` on a call's args) | `src/typecheck.bl:4911` | sublist record; the arena is cut back |
| sealed-ops desugar (`node_set_obj`, `node_set_args`) | `src/typecheck.bl:17439`-`17440` | int records |
| names set and put back (`node_set_name`) | `src/typecheck.bl:11661`/`11663`, `11906`/`11910`, `23727`/`23729` | str records |
| module stamp (`node_set_module`) | `src/typecheck.bl:12953`, `12965` | int records; an equal value writes no record |
| module stamp of top-level decls (`node_set_module`) | `src/compiler.bl:903`-`1034` | int records; an equal value writes no record |
| merged program node and its lists | `src/compiler.bl:1040`-`1104` | new nodes above the parsed end; the cut drops them |
| comment attachment | `src/comment_attach.bl:63`-`572` | runs in the parse, before the mark |
| `verify_comment_attachment` | `src/comment_attach.bl:573`-`637` | a debug path that puts back what it sets |

`node_overwrite` (`src/parser.bl:714`) writes columns directly, but only for a node that is
not kept. `node_pop` below the parsed end stops the parser (`parser_limit_stop`).

**Tests.**
- `tests/test_daemon_recheck_that_keeps_parsed_modules_prints_what_a_cold_check_prints.bl`:
  the edit set of section 5 on `src/cli.bl` with `src/cname.bl`, warm against cold, human
  and JSON. It asserts `reused > 0`.
- `tests/test_daemon_recheck_after_a_body_edit_of_a_corpus_file_prints_what_a_cold_check_prints.bl`:
  a body edit of six corpus files. `BODY_EDIT_ALL=1` runs every `tests/test_*.bl`.
  In the full run (2303 files, 1718 edited, 8042 checks), every check printed what a cold
  check printed. Two files kept no source: `test_capabilities.bl` and
  `test_scoped_budget.bl`. Their entry carries a program annotation, which is handed on to
  each later parse by node id, so an edit of the entry changes the key of every source.
- `tests/test_daemon_build_after_an_idle_recheck_of_an_edit_checks_no_second_time.bl`: a
  settle hook counts checks. A build after the poll checked an edit checks no more, and a
  build after a check request that kept a source checks no more.
- `tests/test_daemon_build_after_a_reused_check_checks_no_second_time_and_matches_a_cold_build.bl`:
  a body edit of a module that loads early, a pub edit of it, a body edit of the entry and
  of a module that loads late. After each, a check request keeps sources, then a per-module
  build at default and `--debug` checks no more, and every file in the output dir (C, unit
  keys, interface text, `.emit-record` but its `inputs` line) equals a cold build's. The
  record's `uses` lines are in that compare, so a unit that a warm build marks untracked
  fails it. A `--no-per-module` build at default and `--debug` runs in the client, since the
  daemon serves no build of one unit; it must match a cold one too, and the daemon's
  `builds` count must not grow for it.
- `tests/test_daemon_recheck_after_edits_to_a_module_that_loads_early_prints_what_a_cold_check_prints.bl`:
  edits to `src/lexer.bl`, the first module of `src/` to load, alone and with `src/cg.bl`.
  The new nodes of the early module come after those of every module that loads after it.
- `tests/test_daemon_build_after_a_check_that_kept_no_source_of_an_unemptied_pool_checks_again.bl`:
  an entry with `@capabilities`, so a check after its edit keeps no source but undoes in
  place. The build after it checks once more.
- `tests/test_daemon_recheck_drops_every_node_made_after_the_parses_before_it_loads.bl`:
  with the `journal` trace channel on, each undo leaves the pool at the parsed end.
- `tests/test_daemon_with_keep_sources_off_reuses_no_parsed_source.bl`: the dev knob
  `BLINK_DEV_DAEMON_KEEP_SOURCES=0` loads each check cold, so a bench can measure what the
  kept parses save.
- `tests/test_daemon_build_right_after_an_edit_checks_the_program_once.bl`: a build sent
  right after an edit, with no check request between, checks the program once.

A test that needs a check request, not the poll, to check an edit sets the dev knob
`BLINK_DEV_DAEMON_IDLE_HOLD=<path>`: while that file exists, the poll does nothing. Without
it, a request that comes more than 500 ms after the edit finds the poll's cold check done,
keeps no source, and has nothing to check. On a loaded machine that gap is common. The poll
test and the first half of the idle recheck test leave the file absent.

Mutations that make the first test fail: skip the desugar undo; keep the edited source's old
`file_ranges` entry; merge in arena order; skip the keyword-default undo. Merge in arena
order also makes the early-module test fail. Skip the cut to the parsed end after the undo
passes every differential test, since the stale nodes are dead and no output reads them; the
journal trace test fails on it (the pool holds 7137 nodes where the parsed end is 7126).

Mutations that make the reused-check build test fail, each alone:
- skip the journal undo: the checks keep no source (`reused 0 then 0`) and the builds check
  again;
- `cg_decl_spelled_carrier_tids` walks the pool in id order: `blink.types.h` and the
  `.emit-record` of each unit differ from a cold build's;
- `cg_derive_key_table_nodes` walks the pool in id order: `__main__.c`, `blink.types.h` and
  the `.emit-record` differ;
- keep the edited source's old range in `loaded_inputs`: C compilation fails in unit `early`;
- the build child drops the load order (`loader_keep_sources(false)` in place of
  `loader_keep_sources_for_build`): the C and records differ as with an id-order walk;
- `unit_sources` without the sort (it marks every source untracked): only the
  `.emit-record` files differ, since their `uses` lines are empty.

**Journal trace.** `BLINK_TRACE_CHANNELS=journal` prints, on each undo, the writes it undid,
the nodes it dropped and the pool it leaves. A daemon check undoes twice: the index of the
entry (`daemon_index_entry`) loads before the client's output is captured, so its undo
prints to the daemon's stderr; the check's own undo then has no writes and drops the nodes
of the index query. On `src/cli.bl` with 20 comment edits of `src/cname.bl`, each check
undid 28,933 writes (the journal at its peak) and dropped 25,030 nodes, and the pool grew by
4,119 nodes (one parse of `src/cname.bl`) per check, from 368,002 to 446,263.

**Parser state that crosses files.** A parse of E alone must give what a cold parse of E in
place gives. Each piece of parser and lexer state that outlives one file:

| state | where | why E's parse does not depend on it |
|---|---|---|
| node columns, shape ids | `src/parser.bl:140` | ids only; the order key (`node_load_rank`) maps them to cold ids |
| sublist pool | `src/parser.bl:156` | open lists cleared on undo (`:356`); closed ones are E's own |
| item annotations | `src/parser.bl:164` | reset at each item (`:2344`, `:2353`, `:2594`) |
| program annotations | `src/parser.bl:164` | handed to later parses; part of the key of a kept source |
| fn bodies | `src/parser.bl:190` | lists reset on undo (`:363`); the two flags are part of the key |
| `parse_desugar_enabled` | `src/parser.bl:198` | reset on undo (`:366`) |
| `source_module_for_node` | `src/parser.bl:205` | cleared on undo (`:364`) and made again by the merge |
| `pos` | `src/parser.bl:2236` | reset on undo (`:365`) and at each file (`src/compiler.bl:1480`) |
| lexer tokens | `src/lexer.bl:395` | made again for each file |
| comment attachment | `src/comment_attach.bl:24` | reset at each file (`:27`) |

No counter makes a name. The only made-up name, `_<n>` at `src/parser.bl:3069`, is the
index of a field in its own variant. The loader makes no node between two parses; the merge
makes its nodes after the last parse.

**Node ids in text and order.** Every place that walks node ids in id order, sorts or
compares them, or prints one:

| site | how a warm check keeps the cold order |
|---|---|
| `check_embed_targets` (`src/compiler.bl:235`) | walks `parser_live_ranges()`, which are in load order |
| `cg_decl_spelled_carrier_tids`, `cg_derive_key_table_nodes` (`src/cg_decl.bl`, `src/cg_derive.bl`) | walk `parser_live_ranges()`; the build child keeps the load order |
| `unit_sources` (`src/cli.bl`) | sorts the ranges by node for the lookup, and maps a read source back to its load index |
| `tc_conversion_impl_for` (`src/typecheck.bl:609`) | picks the lowest `node_load_rank` |
| `tc_unclaimed_call_nodes` (`src/typecheck.bl:14190`) | sorts by `node_load_rank` when the order moved |
| `desugar_sealed_ops_calls`, `require_sealed_ops_rewritten` (`src/typecheck.bl`) | walk `parser_live_ranges()`; the rewrite of one call does not depend on another, only the order of their internal errors did |
| internal errors that print a node id (`src/typecheck.bl:7299`, `:11063`, `src/mono.bl:173`) | not held: an internal error is a compiler bug, and its text names the id of that check |
| `dbg_trace` channels | not held: debug output |
| tables sized by the pool, filled by a walk from the program | read in walk order; the walk follows the merged lists, which are in load order |
| maps keyed by node id | lookup or membership only; no output iterates one |

The loader also makes a warm load read the same sources in the same order as a cold one, or
it runs again cold (`end_source_load`, `src/compiler.bl`).

**Walks over node ids on the build path.** Every loop whose bounds come from the pool
(`node_count()`, `parser_live_ranges()`, a source's node range) in mono, `src/cg*.bl`,
`src/ir.bl`, layout, cname, `src/build_objcache.bl`, `src/emit_record.bl`, the analyses of
`run_build_analyses`, the CLI build path and the typecheck the build runs. Found with `rg`
for `node_count()`, `parser_live_ranges()`, `node_load_rank(`, the source node lists,
`file_ranges` and `.sort` in those files. Line numbers are at this change. Three verdicts:
*live ranges* (it walks or ranks in load order), *order does not matter* (and why), *not on
the build path*.

| site | verdict |
|---|---|
| `src/cg_decl.bl:192` `cg_decl_spelled_carrier_tids` | live ranges |
| `src/cg_derive.bl:1391` `cg_derive_key_table_nodes` | live ranges |
| `src/cli.bl:2067` `unit_sources`, `:2114` `ir_track_sources`, `:2171` `unit_uses` | live ranges: sorted by node for the lookup, then mapped back to the load index |
| `src/compiler.bl:235` `check_embed_targets` | live ranges |
| `src/typecheck.bl:17413` `desugar_sealed_ops_calls` | live ranges |
| `src/typecheck.bl:609` `tc_conversion_impl_for` | live ranges: lowest `node_load_rank` |
| `src/typecheck.bl:14193` `tc_unclaimed_call_nodes` | live ranges: walks `tc_node_tid` in id order, then sorts by `node_load_rank` when the order moved; a dead node has no type, so it is never unclaimed |
| `src/typecheck.bl:4816`, `:11180`-`11188`, `:24689`, `:24739`-`24740`, `:24833`-`24834`, `:24907` | order does not matter: tables sized by the pool and indexed by id; each is filled and read by a walk from the program node, which follows the merged lists in load order |
| `src/diagnostics.bl:747` file lookup, `:852` `diag_span_readable` | order does not matter: a lookup by id and a bounds check |
| `src/ir.bl:1439` `verify_enum_new` | order does not matter: a bounds check |
| `src/compiler.bl:1481`, `:1484`, `:1579` | order does not matter: they mark where a parse starts and ends |
| `src/cg.bl:493`, `src/cg_eff.bl:1313`, `:1388`, `:1418`, `src/escape.bl:1199`, `:1238` | order does not matter: `while i < end` over the children that `node_push_value_child_ids` gave, so the order is the tree's |
| `src/emit_record.bl:168`, `:177`, `:264`, `:288` | order does not matter: they sort strings, not ids |
| `src/cli.bl:570` (`blink fmt`), `:5379`, `:5408` (`blink doc`), `:5662` (`--emit ast`), `src/blinkc_main.bl:120`, `src/comment_attach.bl:573` (`verify_comment_attachment`) | not on the build path: comment attachment for fmt, doc and AST output, and a debug check |
| `src/lsp.bl:1105`, `src/query.bl:341` | not on the build path |
| `src/cname_test_helpers.bl:28`, `:40`, `:75`, `src/lower_test_helpers.bl:68`, `:119`, `:134`, `:147` | not on the build path: unit-test helpers |

No other sort of node ids is in those files. The C names that a walk mints come from a
counter (`c_mint_seq`, `src/cname.bl:36`, cleared by `layout_reset`), not from node ids, so
they follow the walk order, which the table holds to load order. `Map` and `Set` iteration is no hidden order: the compiler's
`main` calls `blink_map_init_seed(0)`, which seeds each process from time and pid, and the
seed goes into every key hash (`bootstrap/runtime_core.h`). An output that read map order
would differ between two cold runs; the Gen1/Gen2 diff and `ci-per-module-checks` compile
`src/` twice and compare.

**Numbers.** m1 (`src/cli.bl`, edits in `src/cname.bl` and `src/cli.bl`), 5 runs each,
base and slice 1 alternating, gen1 of each, median in s:

| case | base | slice 1 |
|---|---|---|
| cold | 0.407 | 0.412 |
| warm, body edit of `cname` | 0.411 | 0.305 |
| warm, body edit of `cli` (the entry) | 0.405 | 0.308 |
| warm, pub edit of `cname` | 0.406 | 0.301 |
| warm, no change | 0.010 | 0.010 |

A warm edit gains about 100 ms. Section 6 expected 96 ms. The worker peak RSS after 20
rechecks is 389 MB, against 362 MB on base: the pool holds the dead ranges and the journal.
`task bench-edit-loop`, base and slice 1 alternating, plain and with `BENCH_DAEMON=1`: no
row of slice 1 has its fastest run slower than the slowest run of base. At the slice 1
commit, builds through the daemon did not gain, since a build checked with no source kept.

At the build-turn fix, gen1 of base and of slice 1, alternating, two rounds, median of 5 (s):

| row (`src/cli.bl`) | base | slice 1 | slice 1, keep off |
|---|---|---|---|
| daemon, body edit of `cname`, build | 1.037 / 0.915 | 1.037 / 0.877 | 1.033 / 0.868 |
| daemon, body edit, check, build at once | 1.066 / 0.955 | 1.476 / 1.220 | 1.048 / 0.924 |
| plain, body edit, check, build | 1.408 / 1.193 | 1.429 / 1.194 | |
| cold `blink check src/cli.bl` (mean of 12) | 0.420 | 0.426 | |
| cold `blink check src/compiler.bl` (mean of 12) | 0.165 | 0.167 | |

The check-then-build row was the cold check that the build ran after a reused check. The
worker peak RSS (VmHWM) after 21 checks of `src/cli.bl` was 384 MB on slice 1 and 441
MB on base in one run where the daemon served each check. Two runs where the client checked on its own, and the
worker checked only through the idle poll, gave 402 and 349 MB on slice 1 and 363 MB on
base. The runs overlap; the 389 / 362 MB pair above stays the reference.

When the build compiles the reused check, gen1 of base (`2da6acd0`) and of this change
(`4593ae64`), daemon, `src/cli.bl`, median of 5 [min-max] (s), two rounds alternating:

| row | base | base, keep off | this change |
|---|---|---|---|
| body edit of `cname`, build | 0.857 [0.845-0.863] / 0.867 [0.855-0.882] | 0.855 [0.851-0.866] / 0.990 [0.851-1.113] | 0.863 [0.856-0.880] / 0.853 [0.844-0.869] |
| body edit, check, build at once | 1.208 [1.183-1.234] / 1.225 [1.189-1.255] | 0.873 [0.856-0.884] / 0.866 [0.857-0.876] | 0.787 [0.767-0.799] / 0.770 [0.765-0.792] |

The check-then-build row is now faster than with kept sources off, since the check keeps
sources and the build checks no more. In a full `task bench-edit-loop`, base and this
change, daemon and plain, one round, two rows of this change had their fastest run slower
than the slowest run of base: the plain `privfn-cname` and `trait-cname` of `src/cli.bl`,
by 2 and 10 ms. Two more rounds of those rows, alternating, overlap. Over 20 cycles of an
edit to `src/cname.bl`, a check request and a build of `src/cli.bl` through the daemon, the
worker ran 41 checks on base and 21 on this change, and its peak RSS (VmHWM) was 463 / 472
MB on base and 327 / 320 MB on this change, in two runs each.

## Warm recheck profile

Typecheck reuse is parked, so this section measures the work that each warm recheck does
again, ranks it, and cuts the top row that keeps the output byte-equal.

### Numbers

Binary: gen1 of a027384e, built `-O1 -g`, run under `setarch -R`. Median of 5 (s):

| case | s |
|---|---|
| warm body edit, `src/cli.bl` entry, edit in `src/cli.bl` | 0.315 |
| warm body edit, `src/cli.bl` entry, edit in `src/cname.bl` | 0.307 |
| cold `blink check src/cli.bl` | 0.420 |
| warm, no change | 0.009 |

The 5% bar is about 15.7 ms. `perf record --call-graph dwarf` on the worker, over 20 warm
rechecks that alternate two bodies, lost 1.4% of the samples. The reply path on the worker
main thread is 317 ms of CPU for each check. The phases, in ms for each check:

| phase | ms |
|---|---|
| resolve | 65.2 |
| infer (fn bodies) | 62.3 |
| escape | 38.8 |
| stamp | 36.2 |
| typecheck, other | 26.9 |
| mono | 18.7 |
| load | 16.9 |
| mutations (15.3 in its own frame, 13.2 inlined into callers) | 28.5 |
| save/restore | 10.5 |
| index of the entry | 8.4 |
| render | 4.2 |
| settle, after the reply | 23.1 |

Function families, self time in ms for each check: AST getters 83, Str-keyed map hash and eq
about 50 to 56, GC on the main thread 35, other Str operations 29.

### Top 10

"w66" is the cold-compile profile from before; "named" means its cut table or report gave the
row.

| # | row | ms | why it costs | fix shape | risk | w66 |
|---|---|---|---|---|---|---|
| 1 | AST getters (`parser.node_*`, `sublist_get`) | 83 | every field read is a call into the dense pool | inline or batch reads; measure at `-O2` first | low; wide | named (15% self); the dense pool made it larger |
| 2 | Str-keyed map hash and eq (`map_find`, `kops_hash_str`) | ~50 | each lookup hashes the full name and compares the bytes | a hash cached in the Str header, interned keys, or a cheaper hash | medium; Map order is seeded per process, so no order a user sees depends on the hash | named (9%); no change |
| 3 | `analyze_mutations` (`src/mutation_analysis.bl:406`) | 26.7 | a dense fns x globals Int matrix (about 1.6M cells), full sweeps over each call edge until no change, then a scan of each fn x each global | bit sets, a worklist over reverse call edges | low | named (alloc 2.6%, GC trigger); **cut here** |
| 4 | `tc_tid_is_pointer_bearing` (`src/typecheck.bl:3490`, from `src/escape.bl:684`) | 12.0 | a new Map for each expression node | memo by tid for each check | low | named (alloc 1.3%) |
| 5 | stamp walk and assert (`tc_stamp_name_child` to `tc_name_is_item`, `src/typecheck.bl:24390`; `recover_node`) | 18.2 + 18.0 | name lookups by Str and many small calls | key by id; see row 2 | medium | `tc_stamp_walk` and `tc_name_is_item` named |
| 6 | `check_arg_shapes_with_binds` (`src/typecheck.bl:5015`) | 17.9 | a new Map for each call, each bind copied in | reuse a scratch map | low | named (alloc 2.1%) |
| 7 | `nr_check_selective_access_at` (`src/typecheck.bl:12343`) | 12.4 | Str lookups for each name use | see row 2 | low | not named |
| 8 | `check_spawn_mut_captures` (`src/escape.bl:1179`) | 10.4 | the `let mut` scan runs in each fn, also in fns with no `spawn` | skip fns with no `spawn` | low | not named |
| 9 | `nr_top_index` (`src/typecheck.bl:12999`) | 9.2 | Str lookups | see row 2 | low | not named |
| 10 | index of the entry (`daemon_index_entry`, `src/daemon.bl:265`) | 8.4 | a second lex and parse of the entry for the query index | share the check's parse | medium | not named; a cold compile does not do it |

Rows 1, 2, 5 and 6 are 5% or more and are not cut here; each one has a chore. Rows 4 and 8
are under 5% alone; row 6 shares a cause with row 4 (a new Map for each call).

### The cut: write sets as bits and a worklist

`analyze_mutations` now keeps one bit for each (fn, global) pair, 64 globals to a U64 word.
The word is unsigned because a shift of a signed 1 into bit 63 is undefined in C: GCC gives it
a meaning, clang does not. The closure takes each fn whose set is not empty, pushes its writes
to each caller, and puts a caller back in the queue only when its set grew. The least fixpoint
is unique, so the visit order does not change the result. The write lists come from a
word-by-word scan of the bits, which gives the globals in declared order, as the W0550/W0551
text needs. That text is the only output that reads the write sets.

Tests, each with 70 globals:

- `tests/test_mutation_write_set_reaches_every_caller_through_cycles_in_global_order.bl`:
  writes to globals 0, 64 and 69 through a cycle of three fns and a self call. It fails with
  a worklist that never puts a caller back, and with a bit index that always uses word 0.
- `tests/test_mutation_write_set_keeps_the_top_bit_of_a_word_and_the_next_word.bl`: writes to
  globals 62, 63 and 64 through a two-fn cycle, and a save of global 63 alone around the call.
  It fails with a list scan that stops at bit 62, and with a bit index of `gi % 63` (the
  closure then never ends).

Both pass on base.

Results, gen1 of a027384e (base) and of 0cf7df35 (tip), alternating, `setarch -R`, median of 5
[min-max] (s), load 0.54 to 1.04:

| case | base | tip |
|---|---|---|
| warm body edit, `src/cli.bl` | 0.313 [0.311-0.322] | 0.301 [0.297-0.304] |
| warm body edit, `src/cname.bl` | 0.307 [0.301-0.309] | 0.292 [0.288-0.296] |
| cold `blink check src/cli.bl` | 0.417 [0.412-0.423] | 0.400 [0.399-0.405] |
| warm, no change | 0.009 | 0.009 |

The output of each run is byte-equal between base and tip. `analyze_mutations` falls from
26.7 to 12.7 ms (the AST walk is 8.6 of that; the closure 2.2; the lists 0.3). That is about
14 ms of CPU, 4.4% of the reply path: a little under the bar, but the row itself was 8.4%.
Worker memory over 20 rechecks: VmHWM 416680 kB on base, 359820 kB on tip; VmRSS at the end
416680 kB on base, 292040 kB on tip.

`task bench-edit-loop`, base (`build/base_gen1/bin/blink`, sha256 c1101c11) and tip
(`build/gen1/bin/blink`, sha256 5124c406), two rounds, alternating, peak load 2.96: no row is
slower than base. In 11 of 28 rows, both tip medians are below every base run. In the row
`src/cli.bl`, private fn edit of `typecheck`, one tip round reads 0.782 against a base maximum
of 0.757. Two more rounds of that row read base 0.736 and 0.739, tip 0.725 and 0.729. Some rows:

| row | base, r1 / r2 | tip, r1 / r2 |
|---|---|---|
| `src/cli.bl`, daemon, body edit of `cname` | 0.755 / 0.750 | 0.736 / 0.742 |
| `src/cli.bl`, daemon, body edit of `typecheck` | 0.743 / 0.747 | 0.723 / 0.729 |
| `src/cli.bl`, daemon, body edit, check, build | 1.166 / 1.171 | 1.141 / 1.143 |
| `src/cli.bl`, cold, all | 4.428 / 4.416 | 4.440 / 4.412 |

Chores for the rows not cut: Str-keyed name lookups in resolve and stamp (rows 2, 5, 7, 9);
the stamp pass, which finds every name position before it knows any node is untyped (row 5);
the Str hash (row 2, 50 ms: a hash cached in the Str header, interned keys, or a cheaper hash;
Map order is seeded per process, so the hash value sets no order a user sees); a new Map or
List for each call, which drives the GC (rows 4, 6); the AST getters, measured at `-O2`
(row 1).

### The stamp row after the cut

`tc_stamp_assert` now finds the untyped nodes first and runs the name ladder only where a name
position holds one of them. A name position always holds a bare Ident, so with no untyped
Ident the ladder does not run. The walk order and the owner column get room for every node
before the walk starts. The report is the same: the first untyped node of each kind, in walk
order, with the same text, and an item name in a name position is still excused.

In `src/cli.bl` the walk reaches 343942 nodes. 33427 of them carry no type, and each one is an
item name in a name position. So the ladder still runs 33427 times, against 46622 before (one
for each name position). The ladder itself, keyed by Str, is the chore for the Str-keyed name
lookups.

Stamp phase (row 5), gen1 of 51306b80 (base) and of 29d8c697 (tip), as `task gen1` links them (`-O1`, no `-g`),
`perf record --call-graph dwarf` over 20 warm rechecks of `src/cli.bl`, ms for each check:

| part | base | tip |
|---|---|---|
| stamp phase | 37.2 | 32.5 |
| list growth in the walk (`list_push`) | 3.7 | 1.7 |
| stood lookup on an empty map (`map_has`) | 1.5 | 0.1 |
| `List.with_capacity` in the assert | 0.7 | 0.0 |
| name ladder (`is_import_module_name`, `is_trait_name`, `is_known_type`, `lookup_fnsig`) | 6.7 | 5.6 |

Wall time, alternating, `setarch -R`, median of 5 [min-max] (s), two runs, load 0.3 to 1.3:

| case | base | tip |
|---|---|---|
| warm body edit, `src/cli.bl` | 0.304 [0.296-0.305], 0.300 [0.298-0.307] | 0.299 [0.293-0.300], 0.298 [0.297-0.299] |
| warm body edit, `src/cname.bl` | 0.295 [0.290-0.298], 0.293 [0.289-0.297] | 0.287 [0.285-0.289], 0.289 [0.286-0.293] |
| cold `blink check src/cli.bl` | 0.400 [0.398-0.404], 0.407 [0.399-0.426] | 0.401 [0.395-0.402], 0.394 [0.393-0.408] |

The cut is about 5 ms of a 300 ms recheck, which is near the spread of 5 runs. Over 20 warm
rechecks with a real edit each, the median is 0.304 on base and 0.297 on tip in one run, and
0.307 and 0.303 in another. The output of each run is byte-equal between base and tip. In
`task bench-edit-loop`, no row is slower than base. Worker VmHWM over 20 rechecks: 363500 and
371236 kB on base, 371052 and 369292 kB on tip.

### The stamp row after the per-spelling memo

The 33427 ladder calls in `src/cli.bl` ask about only 4228 spellings. The assert now keeps
the ladder's answer for each spelling in a map that lives for one `tc_stamp_assert` call. The
key is the spelling alone. Every other input to the ladder is a table that nothing writes while
the assert runs, plus `nr_current_module`, which is one value for the whole call. Scope is not
in the key: the scope checks (`tc_old_calls`, `tc_name_position_is_value`) still run for each
position, because one spelling can be an item at one position and a shadowing local at
another. The assert also no longer clears the walk marks at its end, as nothing reads them
after the pass.

The ladder reads the module that is current when the assert runs, not the module of the node.
A fix that changes this must add the module to the memo key.

Stamp phase, the same perf method, tip 29d8c697 and memo 24564045 in one window each, ms for
each check:

| part | base | tip | memo |
|---|---|---|---|
| stamp phase | 37.2 | 32.7 | 27.8 |
| `tc_stamp_assert`, inclusive | | 15.4 | 10.8 |
| name ladder, inclusive (`is_import_module_name`, `is_known_type`, `lookup_fnsig`, `is_trait_name`) | 6.7 | 5.8 | 0.9 |
| reply path, total | | 302.9 | 295.2 |

Wall time, alternating base 51306b80, tip 29d8c697 and memo 24564045, `setarch -R`, median of 5
[min-max] (s), two runs:

| case | base | memo |
|---|---|---|
| warm body edit, `src/cli.bl` | 0.300 [0.294-0.314], 0.301 [0.298-0.303] | 0.294 [0.292-0.296], 0.296 [0.291-0.298] |
| warm body edit, `src/cname.bl` | 0.294 [0.289-0.296], 0.294 [0.290-0.297] | 0.282 [0.280-0.287], 0.287 [0.286-0.292] |
| cold `blink check src/cli.bl` | 0.398, 0.403 | 0.393, 0.393 |

The min-max ranges touch, so the 5-run spread alone does not separate them. The runs alternate,
so each memo run has a base run next to it. In those pairs the memo is faster in 9 of 10 for
`src/cli.bl` (median gain 5.5 ms) and in 10 of 10 for `src/cname.bl` (median gain 9 ms). That
is about 2 to 3% of the recheck.

`task bench-edit-loop`, base against the final branch build, two rounds, the order swapped in the
second: no row is slower than base. Worker VmHWM over 20 rechecks of `src/cli.bl`: 342904 and
348824 kB on base, 369816 and 363308 kB on the final build. Base read 363500 and 371236 kB in
the earlier runs, so this is within the spread of the GC heap high-water mark. The memo holds
a few thousand entries.

### The resolve row after the name lookup cut

Resolve asked the same Str-keyed questions of a spelling at every read of it. Three cuts, all
in `src/typecheck.bl`:

1. `nr_check_selective_access_at` rules out a local binding before it runs the builtin ladder
   (`is_builtin_name`), since most reads are of locals.
2. Each module record (`ModuleNames`) keeps, for each module it imports selectively, the set of
   spellings that import binds: each selected name and each alias. `is_selected_import` reads
   that set and no longer walks the import list. The set is built and dropped with the import
   index of the record, so an edit to an import list makes the next question build it again.
3. Each module record keeps the answer resolve gives each spelling the module reads that no
   local binding holds: the module it is not selected from (`nr_unselected_source`), whether
   it is private here (`nr_private_access_here`), and the declaration it names
   (`nr_find_bare_decl`). Every table behind an answer is filled before the walk: each
   module's declarations and privates, the import lists, the symbol modules, the re-exports,
   the namesake types, the type declarations of `Handler` and `Template` and the prelude
   modules. Nothing writes them again until the next check. `resolve_names` drops every
   answer when it starts to fill them. The module is in the key, as the record is the module's
   own. Scope is not in the key: no answer reads scope state, and the import answer is read
   only after the local check.

The three calls emit nothing and mark nothing. Each diagnostic, each used-import mark and each
note of the declaration a node names is made by the caller at each node, from the kept answer.
The only writes under the calls fill the import index and the selected spellings of a module
record, both built from that module's import list alone.

The state lives in the module record, not in new module globals.

Tests:

- `tests/test_typecheck_name_answers_follow_the_module_and_scope_of_each_use.bl`: one spelling
  selected in one module and not in another, private in one module and declared in another,
  and shadowed by a local in one function and not in the next. Each module pair loads in both
  orders. It fails when all modules read one answer record, and when a kept answer is read
  for a local binding.
- `tests/test_daemon_recheck_after_an_edit_to_an_import_or_a_top_level_name_prints_what_a_cold_check_prints.bl`:
  a warm daemon and a cold check after each edit to an import list, a top-level name and a
  private declaration. Both outputs must be equal, in human and JSON form. It runs once with
  the daemon keeping sources, and once with `BLINK_DEV_DAEMON_KEEP_SOURCES=0`. It fails when
  the answers are kept from the check before, and when the selected spellings are not built
  again after an import list changes.
- `tests/test_typecheck_a_spelling_read_twice_in_one_module_is_reported_and_marked_at_each_read.bl`:
  a name not selected and a private name, each read twice in one module, give two errors in
  source order; an import read twice is used and an unread one is reported; and a second check
  in one process after the import list stops selecting a name reports the read. It fails when
  a diagnostic comes only from the first read, when a call does not mark its import used, and
  when the selected spellings are not built again after an import list changes.

All three pass on base.

Resolve phase, `perf record --call-graph dwarf` over 20 warm rechecks of `src/cli.bl`, base
(gen1 of 3c41c677) and tip (gen1 of 60c890dc) in one window each, ms for each check:

| part | base | tip |
|---|---|---|
| resolve phase | 65.0 | 54.7 |
| Str-keyed work in resolve | 32.5 | 28.6 |
| `nr_check_selective_access_at` | 11.9 | 4.4 |
| `is_selected_import` | 4.6 | 0.7 |
| `is_builtin_name` | 4.5 | 0.6 |
| `nr_resolve_bare_decl` | 3.0 | 2.5 |
| `is_private_access` | 3.1 | 2.4 |
| `nr_top_index` (not cut) | 5.5 | 4.4 |

The memo of the private and declaration answers gains less than the other cuts: each read
still hashes the module name to find the record (`nr_module_names_of`, 2.2 ms).

Wall time, alternating, `setarch -R`, 10 pairs in each of two runs, the order swapped in the
second, median of the first 5 [min-max] (s):

| case | base | tip | pairs tip faster | median paired delta (ms) |
|---|---|---|---|---|
| warm body edit, `src/cli.bl` | 0.297 [0.293-0.299], 0.296 [0.292-0.296] | 0.284 [0.281-0.286], 0.285 [0.281-0.292] | 10/10, 10/10 | -12, -8 |
| warm body edit, `src/cname.bl` | 0.281 [0.281-0.290], 0.282 [0.281-0.287] | 0.277 [0.271-0.282], 0.279 [0.271-0.281] | 10/10, 10/10 | -7, -7 |
| cold `blink check src/cli.bl` | 0.393 [0.391-0.395], 0.400 [0.389-0.410] | 0.385 [0.382-0.394], 0.390 [0.385-0.397] | 9/10, 9/10 | -9, -11 |
| warm, no change | 0.009 | 0.009 | | 0 |

The output of each run is byte-equal between base and tip. The first cold check of a run
also prints `resolving dependencies...`, whichever binary runs first.

`task bench-edit-loop`, base and tip, two rounds, the order swapped in the second: no row is
slower than base. Worker VmHWM over 20 rechecks of `src/cli.bl`: 363852 and 373816 kB on base,
361656 and 362064 kB on tip.

### The allocation row after the per-call cut

Most allocation on the warm recheck path came from a few calls that built a new Map or List
each time, though the call needed none, or needed one map that could be kept. Each GC
allocation can start a collection, so a new map per call costs both the allocation and part of
a collection. Four cuts, all in `src/typecheck.bl` and `src/diagnostics.bl`:

1. `tc_tid_is_pointer_bearing` keeps its answer for each resolved tid in
   `tc_ptr_bearing_memo`, for one check. Escape asks for every expression, and each walk built a
   seen map and read the field pools. The walk reads only the pool entry of each tid it meets,
   the field declarations of a struct or enum (`tc_declared_field_tids`) and the instance each
   field maps to (`tc_member_tid_at_instance`). A tid names one instance, and these are fixed
   once interned, so only `init_types`, which clears `ty_pool`, clears the memo. The one entry
   that can change is a metavar that a later unify binds. A walk that meets an unbound metavar
   puts `PTR_BEARING_MET_METAVAR` in its seen map, and its answer is not kept. The memo writes
   only its own map.
2. `check_arg_shapes_with_binds` takes its `seen` map off a free list
   (`tc_arg_binds_free`), clears it, and gives it back when it returns. An argument can hold a
   call, which reads its own arguments before the outer call reads its next one. Each open call
   holds a map that no other open call holds, so a nested call cannot clear or fill the map of
   the call outside it. A check that panics out of a call leaves that map off the list, which
   costs one new map and nothing else. `init_types` empties the list, as it resets every
   typecheck global, so no map outlives its check.
3. `diag_clear_allows` clears the allow set in place and does not make a new one.
4. `check_ptr_bearing_struct_in_type_ann` searches for an `@ffi.struct` only when the
   annotation has type arguments or names an `@ffi.struct`. In all other cases the search
   answers -1 at once, so its seen map is not made.

The memo of cut 1 also removes most calls to `tc_evar_field_slots`, which made a new list for
each enum variant that the walk read (2.35 ms for each check on base).

The ratchet does not let a commit add a module `let mut`. Cuts 1 and 2 add two, so the three
lists of pending under-determined blames (`tc_ud_pending_names`, `_tids`, `_nodes`) become one
list of `TcUdPending` records. The count stays the same.

Tests:

- `tests/test_escape_pointer_bearing_answer_follows_the_instance_and_each_check.bl`: two
  `Box[Int]` and `Box[Ptr[U8]]` are asked in both orders, and a second check in one process changes a field to add or remove a `Ptr`. It
  fails when the memo is kept across checks, and when it is keyed by the declaration and not by
  the instance.
- `tests/test_typecheck_a_call_inside_an_argument_keeps_the_type_parameters_the_outer_call_fixed.bl`:
  generic calls whose arguments hold other generic calls, some well typed and some not, each
  error checked by message and line. It fails when all calls share one map, and when a map is
  not cleared before use.
- `tests/test_daemon_recheck_after_a_field_edit_that_adds_or_removes_a_ptr_prints_what_a_cold_check_prints.bl`:
  a warm daemon and a cold check after each field edit that adds or removes a `Ptr`, with and
  without `BLINK_DEV_DAEMON_KEEP_SOURCES=0`. It fails when the memo is kept across checks.

All three pass on base.

Allocator rows, `perf record --call-graph dwarf` over 20 warm rechecks of `src/cli.bl`, base
(gen1 of 903ffaa8) and tip (gen1 of 3734a0f8) in one window, ms for each check:

| part | base | tip |
|---|---|---|
| reply path | 287.4 | 268.2 |
| any GC frame on the reply path | 35.6 | 24.0 |
| `blink_map_new` | 8.20 | 0.90 |
| `tc_tid_is_pointer_bearing` map | 3.10 | 0.03 |
| `check_arg_shapes_with_binds` map | 2.58 | 0 |
| `diag_clear_allows` map | 0.93 | 0 |
| `check_ptr_bearing_struct_in_type_ann` map | 0.83 | 0 |
| `blink_list_new` | 5.23 | 4.55 |
| `blink_list_new_atomic` | 9.90 | 7.15 |
| escape phase | 37.8 | 27.2 |
| infer phase | 63.0 | 59.2 |

No row that is still allocated is worth 5% of a check (about 14 ms). The largest are
`sr_scan_for_patterns_block` (1.43), `substitute_typevar_tid` (1.40) and
`closeable_binders_reached` (0.98).

Wall time, alternating, `setarch -R`, 10 pairs in each of two runs, the order swapped in the
second, median of the first 5 [min-max] (s):

| case | base | tip | pairs tip faster | median paired delta (ms) |
|---|---|---|---|---|
| warm body edit, `src/cli.bl` | 0.285 [0.283-0.289], 0.286 [0.283-0.288] | 0.267 [0.265-0.271], 0.267 [0.263-0.267] | 10/10, 10/10 | -19, -19 |
| warm body edit, `src/cname.bl` | 0.278 [0.274-0.306], 0.276 [0.273-0.280] | 0.258 [0.253-0.264], 0.260 [0.253-0.269] | 10/10, 10/10 | -16, -18 |
| cold `blink check src/cli.bl` | 0.384 [0.384-0.406], 0.386 [0.384-0.392] | 0.370 [0.367-0.375], 0.365 [0.365-0.374] | 10/10, 10/10 | -19, -16 |
| warm, no change | 0.009 | 0.009 | | 0 |

The output of each run is byte-equal between base and tip. The first cold check of a run
also prints `resolving dependencies...`, whichever binary runs first. The C that base and tip
emit for `src/cli.bl` and `src/blinkc_main.bl` is byte-equal.

`task bench-edit-loop`, base and tip, two rounds, the order swapped in the second: no row is
slower than base. Worker VmHWM over 20 rechecks of `src/cli.bl`: 377700 kB on base and
358668 kB on tip with base first, and 381012 kB on tip and 359948 kB on base with tip first.
The binary that runs first peaks about 20 MB higher, so the memo shows no RSS cost.

### The Str hash row after the word-at-a-time cut

The runtime map hashed a Str key one byte at a time (FNV-1a), so each byte cost one multiply
that waited on the one before it. That hash was the top self row of a warm recheck of
`src/cli.bl`: 16.4 ms of 272.8 ms. During one cold check of `src/cli.bl` the compiler hashes
about 2.03 million Str keys. The median key is 9 bytes, 24% are 1 to 4 bytes, 24% are 5 to 8,
36% are 9 to 16, and 0.3% are longer than 32.

The cut, in `bootstrap/runtime_core.h` (`blink_map_hash_of`):

- The start value is the length times an odd constant, so keys that differ only in length
  start apart.
- A key longer than 8 bytes is read 8 bytes at a time. The last step reads the last 8 bytes of
  the key, which can overlap the step before it. A key of 4 to 8 bytes is one step on its first
  4 and its last 4 bytes. A key of 1 to 3 bytes is one step on its first, middle and last byte.
  Each byte of the key is in at least one step, and no load reads past the recorded length.
  The loads use `memcpy`, so an unaligned key is not undefined behavior.
- Each step is an exclusive-or, a multiply and a shift. The answer goes through
  `blink_kops_mix_u64`, the splitmix64 finish that every integer key already takes.
- The seed is mixed in as before: `blink_kops_hash_str` gives the hash exclusive-or the map
  seed. `blink_map_hash` (the hash that a derived `Hash` reads) takes no seed, as before.
- `blink_kops_hash_str` forces the hash inline. Without that, cc kept it as a call, and each
  probe made two calls.

The hash reads the key with native byte order, so a big-endian host gives other hash values.
The spec allows this: a hash value and the iteration order vary from build to build (section
3.6), and no test pins a value.

No hash value leaves the process. The std archive key, the object cache key and the package
content hashes are sha256 of the bytes. The daemon sends the environment whole, not hashed.

Tests:

- `tests/test_str_keyed_map_and_set_answer_for_every_key_length_up_to_40.bl`: `Map[Str, Int]`
  and `Set[Str]` with keys of 0 to 40 bytes in six byte classes (ASCII, the bytes 0x01 and 0x7f,
  and two-, three- and four-byte UTF-8), each with the variants that change one byte at each
  offset. Keys are made by concatenation, slice and interpolation, so equal keys are separate
  cells. Get, contains, insert over, remove and iteration are checked against a linear scan.
- `tests/test_derived_hash_of_a_str_field_sees_every_byte_at_every_length_up_to_40.bl`: the
  same keys through a derived `Hash` on a one-field struct. Every distinct key gets a distinct
  `hash()`, and equal keys made by other routes get the same one. The seed is one
  exclusive-or before a mix that loses no bits, so the result does not depend on the seed.
- `tests/test_str_keyed_map_order_follows_the_pinned_seed.bl`: with `BLINK_MAP_SEED` pinned,
  two processes iterate Str keys of every length in the same order, and another seed gives
  another order.

All three pass on base. Each mutation of the cut makes one of them fail: drop the tail (929
same hashes), hash only the first word (3168), read the tail one byte short (192) or one byte
long (24), leave out the length (2372), read the 4-to-8 tail at the wrong offset (24), read the
last word past the key (the Map and Set test fails) and leave out the seed (the order test fails).

Self rows, `perf record` over 20 warm rechecks of `src/cli.bl`, base (83d6902f) and tip in one
window, ms for each check:

| row | base | tip |
|---|---|---|
| reply path | 275.8 | 264.3 |
| `blink_kops_hash_str` (the hash inline in tip) | 16.76 | 12.88 |
| `blink_str_eq` | 10.16 | 8.65 |
| `memcmp` | 7.68 | 7.48 |
| `blink_kops_eq_str` | 6.63 | 5.88 |
| `blink_map_find` | 9.78 | 11.16 |

In a tip build without the forced inline, 29% of the hash samples are on the first read of
the key header (its length). That is a cache miss that a hash of any kind takes.

Probes, one cold check of `src/cli.bl` with a counting runtime, five pinned seeds (0 to 4),
range over the seeds:

| op | calls | base slots per call | tip slots per call | base key compares per call | tip key compares per call |
|---|---|---|---|---|---|
| find | 1373093 | 1.385-1.447 | 1.317-1.340 | 1.309-1.375 | 1.235-1.263 |
| has | 329088 | 1.497-1.573 | 1.431-1.523 | 1.496-1.572 | 1.426-1.516 |
| set | 144570 | 2.743-2.839 | 2.670-2.712 | 1.453-1.539 | 1.375-1.411 |

The fewer probes are why `blink_str_eq` and `memcmp` also fall.

Wall time, alternating, `setarch -R`, 10 pairs in two runs, the order swapped in the second,
median of 5 [min-max] for each run (s):

| case | base | tip | pairs tip faster | median paired delta (ms) |
|---|---|---|---|---|
| warm body edit, `src/cli.bl` | 0.270 [0.269-0.274], 0.273 [0.270-0.290] | 0.264 [0.261-0.267], 0.267 [0.263-0.274] | 9/10 | -7 |
| warm body edit, `src/cname.bl` | 0.263 [0.262-0.270], 0.273 [0.263-0.281] | 0.259 [0.252-0.270], 0.259 [0.257-0.263] | 9/10 | -7 |
| cold `blink check src/cli.bl` | 0.376 [0.367-0.378], 0.372 [0.369-0.392] | 0.365 [0.364-0.371], 0.361 [0.356-0.369] | 9/10 | -10 |
| warm, no change | 0.009 | 0.009 | | 0 |

The output of each run is the same for base and tip, except that the first cold check of a
run also prints `resolving dependencies...`.

`task bench-edit-loop`, base and tip, two rounds, the order swapped in the second: no row is
slower than base. `cli cold-obj` had one tip round above the base range while other work
loaded the machine; two more rounds of that row in a quiet window gave base 1.920 and 1.921 s
and tip 1.924 and 1.904 s.

A user program, `Map[Str, Int]` with 300000 keys, insert then 5 rounds of get, 15 runs each,
median ms:

| keys | base insert | tip insert | base get | tip get |
|---|---|---|---|---|
| `k{i}` (2 to 7 bytes), get in insert order | 14 | 14 | 22 | 25 |
| `name_{i}_x` (8 to 13 bytes), get in insert order | 21 | 19 | 26 | 25 |
| 41 to 46 bytes, get in insert order | 35 | 18 | 63 | 33 |
| `k{i}`, get in scattered order | 12 | 12 | 41 | 35 |
| `name_{i}_x`, get in scattered order | 22 | 19 | 43 | 33 |
| 41 to 46 bytes, get in scattered order | 34 | 17 | 133 | 67 |

Only one row is slower: short keys read back in the order they were put in. The probable
cause: FNV-1a puts keys that differ only in the last byte in nearby slots, so that read order
stays in cache. When the same keys are read in scattered order, tip is faster.
