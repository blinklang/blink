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
copies const values into other units. A build after a reuse check runs cold (section 3), so
this does not affect slice 1.

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
  marks the sources untracked when they do not. A build after a reuse check runs cold in
  slice 1, so no build sees an appended range.
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

**Builds.** A build after a check that kept a source checks again with none kept, so a
build always compiles the program a cold load gives (`src/daemon.bl`, the build turn).
The idle poll (`daemon_recheck_if_changed`) keeps no source. No client waits on it, and a
build after it then uses its check as it is. A poll that kept sources made each build
through the daemon after an edit pay one more cold check, about 0.45 s on `src/cli.bl`. A
check request keeps sources, so a check followed at once by a build pays a warm check and
then a cold one. Slice 3 (build equality) removes that second check.

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
  settle hook counts checks. A build after the poll checked an edit checks no more; a build
  after a check request that kept a source checks once more.

The two warm-against-cold tests ask the warm tree last in each step, so the next edit comes
within the poll's 500 ms wait and the check request, not the poll, checks it.

Mutations that make the first test fail: skip the desugar undo; keep the edited source's old
`file_ranges` entry; merge in arena order; skip the keyword-default undo.

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
row of slice 1 has its fastest run slower than the slowest run of base. Builds through the
daemon do not gain, since a build checks with no source kept.
