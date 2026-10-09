# Per-module emit as the default build path

## Context

Blink's compiler can emit a program in two shapes:

1. **Monolith** — one fat `.c` for the whole program (entry + every
   reachable module), compiled and linked in a single `cc` invocation.
   This is what `blink build` / `blink run` have always done, and what
   `--emit c` writes to disk.
2. **Per-module** — one `.c` per program module, a types header
   (`blink.types.h`), and two headers per module (`<m>.h` and
   `<m>.priv.h`). Each TU includes the headers of the symbols it names, so
   cross-module calls and typedefs resolve (see "Unit headers" below). Each module `.c` is compiled
   to its own `.o` and linked. See `generic-mono-ownership-per-module.md`
   and `per-module-o-cache.md` for the front-end split and the `.o`
   cache that elides unchanged recompiles.

The per-module machinery is mature: the four invariants in
`task ci-per-module-checks` (monolith-vs-per-module byte-equality,
cli.bl self-host, determinism, gen1/gen2 byte-equality) have held green
through the `tc83pp` project. Until now it was only reachable through the
**hidden** `__emit-per-module` subcommand — undocumented, unstable, and
not surfaced in `blink build --help` or `blink llms`.

This decision (br `fc9nrd`) promotes per-module emit to a documented flag
and charts the path to making it the default build path.

This is a build-orchestrator decision — **BDFL, no `/deliberate` panel**
(it changes how we build, not the Blink language surface).

## Decision

### 1. Documented flag

Per-module emit is now reachable as:

```
blink build --emit per-module-dir <file.bl> <outdir>
# or, output dir via -o:
blink build --emit per-module-dir <file.bl> -o <outdir>
```

It writes the per-module `.c`/`.h` set into `<outdir>`. The output target is a **directory**, not the single-file
path that `--emit c` and the default binary build assume — this is the
one structural difference in the `cmd_build` flow.

### 2. One-release deprecation alias

The hidden `__emit-per-module <file.bl> <outdir>` subcommand stays wired
as an **alias** for one release so existing callers (Taskfile,
out-of-tree scripts) keep working. It dispatches to the same
`cmd_emit_per_module`. It will be removed a release after the flag ships.

### 3. Monolith stays reachable for bisecting

`--emit c` continues to emit the single monolith `.c`. This is the
fallback for bisecting a codegen regression: if per-module output
misbehaves, compare against the monolith `.c` for the same program. The
**stdlib archive** (`libblink_std.a` / `monolith.o`) also stays a
monolith — the archive is a separate, pre-built artifact and is not
affected by the per-module *program* emit path.

### 4. CI gate restructure

- `task ci-release` (named `task ci` until the codegen rewrite) is the
  canonical release gate. It runs **`ci-monolith`** (full
  monolith verification: regen bootstrap + all tests + fmt + installed
  smoke + cross-compile smoke) **and** **`ci-per-module-checks`** (the
  four per-module invariants). So `task ci-release` covers all four
  invariants by construction.
- `task ci-monolith` is the legacy monolith-only verification, kept green
  as a standalone fallback so a codegen regression can be bisected
  against single-TU output.
- `task ci-per-module-checks` holds the four per-module invariants
  (renamed from the old `ci-per-module`). `ci-profile` times this phase.

## Path to default (done)

The per-module path is the default for `blink build`, `blink run` and
`blink test`. `--no-per-module` or `BLINK_PER_MODULE=0` builds the
monolith, so a per-module bug can be bisected against it. The wins:

- **cc warm-cache.** Per-module `.o` caching (`per-module-o-cache.md`)
  means an incremental build recompiles only the changed module's `.c`
  and re-links. The monolith path recompiles the whole program every
  time.
- **link-only fast path.** When nothing changed, the build is a pure
  link of cached `.o` files — no `cc -c` at all.
- **archive monolith stays for stdlib.** The stdlib is already a
  pre-built archive; per-module program emit composes with it unchanged.

## The per-module path for `blink build`, `blink run` and `blink test`

The default build drives the per-module path end to end: emit, compile,
cache and link. `--per-module` asks for it by name, and `--no-per-module`
asks for the one-unit build.

- **Units.** One `.c` per program module, plus the headers below,
  written to `<output>.units/` next to the binary. The
  std modules the archive holds get no unit: the units link
  `libblink_std.a` the same as the monolith user TU does, and the archive
  defines the runtime storage and every non-generic std body. A std module
  gets a unit only for the bodies the archive cannot hold (the functions
  that take the evidence vector). The archive leaves out the modules of
  a native dep (`std/db_sqlite` and the `std/db*` modules that name its
  types), so a program that reaches them gets one unit for each.
- **Native shims.** No archive holds the C shims of a native dep
  (`runtime_sqlite.h`), so the program defines them: the entry unit
  writes their bodies, and each other unit writes
  `#define BLINK_NATIVE_SHIMS_DECLS_ONLY 1` and reads only their
  prototypes. Each unit gets the same gates, so the entry unit defines
  every shim that any other unit can call. This also holds when a user
  module binds a shim with `@ffi` and does not import its std module.
  The one-unit build is that entry unit, so its C does not change.
- **Std generic instances.** A unit writes a std generic instance only as
  a `static` private copy, and only the instances its own calls name.
  User generic instances stay in the unit of the module that declares the
  generic, so a new instantiation recompiles that unit too. On
  `src/cli.bl` this writes one std instance, in one unit, so the copies
  cost no code there. The per-module binary has 36.5 KB (0.8%) more text
  than the monolith (4,673,490 against 4,636,962 bytes), which probably comes from
  the split itself, such as calls cc can no longer inline across units.
  A program that calls one std generic from many modules pays one copy
  per unit.
- **Jobs.** `--jobs N` or `BLINK_JOBS=N` sets how many units compile at
  once; the default is the CPU count, read only when a unit compiles. A
  value that is not a positive integer is an error. The largest unit
  starts first. The build starts and reaps the cc children from its own
  thread. Before, each compile waited in an async task, and the async
  pool has four threads (`blink_threadpool_init(4)`), so at most four cc
  ran at once whatever `--jobs` said. The build reaps children in start
  order, not whichever ends first, so a child that ends early holds its
  slot until those started before it end. A child that writes more than
  a pipe buffer of output before its turn waits for its turn: no
  deadlock, but its slot stays idle.
- **Object cache.** One entry per unit. The key covers the unit `.c`,
  every header it includes (the unit headers it names, `runtime.h`,
  `libblink_std.h`, its `.gch`, vendored headers), the compiler, the cc
  id, the flags and the target. A header the unit does not include is
  not in its key. The units are written to a private
  directory, so the bytes the key hashes are the bytes cc compiles. An
  unreadable input turns the cache off for that unit, or for all units
  when the input is shared. `--no-cache` turns it off. The inputs all
  units share go into one digest that each unit's key names, and the
  hashes run in batches that fit one exec argument (Linux caps one at
  128 KiB). With the full header list in each unit's manifest, the 48
  units of `src/cli.bl` passed that cap, and every unit missed. A miss
  compiles to a temp object, and one exec per batch moves each new object
  into the cache. The build links the cached object for each move that
  worked, and the temp object for each move that failed.
- **Emit reuse.** The front end always runs, so each build loads its files
  and reports their errors. Then the build writes its emit inputs as one
  text: the compiler sha, `argv[0]`, the cwd, the entry path, the codegen
  config, `--strict`, the skipped modules, the lint levels, the env vars
  that change the compile (`BLINK_ROOT`, `HOME`, `BLINK_SKIP_MODULES`,
  `BLINK_ONLY_MODULE`, `BLINK_COMPILER_ARCHIVE`, `BLINK_PER_MODULE`,
  `BLINK_PARSER_PANIC_DUMP`), each loaded file with the bytes the lexer
  read, each manifest and lockfile read, how each import resolved, and each
  `#embed` file with its bytes. Keys and lines from a `Map` are sorted, so
  the text does not change between builds. `<output>.units/` keeps this
  text in `.emit-inputs`, and `.emit-record` lists its length, the units
  and the sha of each `.h` and `.c` and of the text, in name order (a
  `Map` gives its keys in an order each process seeds at random, so two
  cold builds once wrote the lines in two orders). When the record's
  length matches and the text is the same byte for byte, the build
  hard-links the files and the text into its private directory, hashes
  them again against the record, and skips the emit. If any file differs,
  the text too, it emits. Content decides, not mtime.
  A new file that changes where an import resolves changes the import
  map and the loaded files, so it changes the text. The build writes the
  record last, only after the link succeeds, and only when the emit
  reported no diagnostic. A build that stops early leaves the last
  directory and its record. A reused build prints the warnings of the
  front end again. These turn reuse off: `--no-cache`, an empty
  `BLINK_CACHE_DIR`, `--blink-trace`, `--trace`, `BLINK_TRACE` on
  `blink run`, and a `BLINK_TRACE_CHANNELS` channel outside `build.*`.
  On `src/cli.bl` the text is 6.2 MB.
- **Unit reuse.** Beside each loaded source's bytes, the inputs text holds
  its interface text: its tokens with no positions and with no fn body
  inside. A source that comes with the compiler (`<embedded:...>`) has no
  interface text, because the compiler sha names it. When the inputs text
  differs only in the bytes of loaded sources, the build writes the
  headers, then takes each unit of the last build whose sources are all
  unchanged. Each other field of the text must be byte-equal, each
  interface too, and so must each header. The record lists, for each unit,
  the sources it read (`uses`):
  - its own module's;
  - each source whose nodes its IR spans, such as a field default or a
    keyword-parameter default of another module (the IR arena notes the
    source of each node it records);
  - each source whose fn body the emit lowers or reads, or whose node
    position it writes into the C. The emit marks the source once at each
    point where it crosses into such a node: `lower_fn` in
    `src/cg_stmt.bl` (each fn, method, test and generic instance body,
    and each private copy of a std generic), `cc_forwarded_binding` in
    `src/cg_call.bl` (a call site that calls a Str or List impl method
    straight through the foreign binding its body forwards to reads that
    body and lowers none of it), `unit_uses_async_scope` in `src/cg.bl`,
    and `ir_line` / `ir_col` in `src/ir.bl`, which the emit reads each
    line and column through. The node getters do not track reads.

  Only a build that may take units tracks these and has the parser keep
  the fn body token ranges for the interface text. A build with reuse off,
  a one-unit build, `blink check`, the LSP and the daemon's checks pay for
  neither.

  Signatures, effects and types are declared, so the front end's facts
  about a module's nodes come from its own text and the interfaces of the
  rest. A new instance of a generic changes the header of the module that
  declares it, so no unit is taken. A unit writes its private copies of
  std generics by C name, not in the order the program first named them,
  which an edit to another module can change. The build reads the last inputs text
  in its own process and writes a copy into its private directory, so the
  text it compared is the text it hashes. The exec that hashes the units
  first hard-links each taken unit from the last directory, so a taken
  unit costs no extra process, and a unit the build emits is never linked
  to the last build's file. Each taken unit, and the copied text, is
  hashed against the record. When one differs, the build emits every
  taken unit again. The `__main__` unit and the other units are emitted.
  The trace prints `reuse unit <module>` for each unit taken.
- **Reuse verify.** `BLINK_EMIT_REUSE_VERIFY=1` makes each per-module
  build, also one that takes nothing from the last build, emit the whole
  program again into a directory of its own, with each module header
  written after a typedef walk of its own (see "Unit headers from one
  walk"). It fails, naming the file, unless every unit, `__main__` and
  every header is byte-equal to the file the build left. Every file, not
  only the taken units: a unit's lowering can set state that `__main__`, a
  header or a unit lowered after it reads. The tests of the reuse key and
  of the module headers run under it.
- **Errors.** A cc failure prints the cc output, then
  `error: C compilation failed in unit <module>`, and exits 1, the same
  code as the monolith.
- **Selection.** A flag on the command beats `BLINK_PER_MODULE`, which
  beats the default. `--per-module` or `--no-per-module` decides for that
  command; passing both is an error. Without a flag, `BLINK_PER_MODULE=0`
  builds one unit and `1` or unset takes this path, for the command and for
  every `blink` that the program starts. Any other value is an error, even
  under a flag.
- **Fallback.** `--emit c`, `--format blink`, `BLINK_SKIP_MODULES`,
  `BLINK_ONLY_MODULE` and `BLINK_COMPILER_ARCHIVE` build one C unit. When
  `--per-module` asked for the path, the build prints
  `note: --per-module ignored: <reason>`. When the default or
  `BLINK_PER_MODULE` chose the path, it prints nothing. `--target` uses the per-module path.
- **Corpus.** `task corpus` builds one unit per file (`BLINK_PER_MODULE=0`
  and the compiler archive). `task corpus-per-module` builds every
  `tests/test_*.bl` on this path with no compiler archive, and
  `task ci-release` runs it. See the
  per-module corpus in `docs/codegen-rewrite/harness.md`.
- **Trace.** `BLINK_TRACE_CHANNELS=build.units` prints `reuse emit` or
  `emit` once per build, then `hit <module>` or `compile <module>` for each
  unit.
- **Tests.** `blink test <file>` builds the program under test
  on this path, at the debug flags `blink test` always uses. The test bodies,
  the runner and `main` are in the `__main__` unit; each imported module is a
  unit of its own. The runner state is one set per binary and per thread
  (`BLINK_TEST_STORAGE` in `runtime_test.h`), so an assert that fails in
  another unit reports a test failure and the next test runs. For a
  directory, `blink test` passes the path flag it was given and
  `--jobs` to the build of each test file, and each build runs up to `--jobs` compiles of its own.
  An entry file of only imports and tests declares nothing that names its
  module, but it still gets the `__main__` unit, since that unit holds `main`.

### Unit headers

The build writes three kinds of header:

- `blink.types.h`: the prologue (`libblink_std.h` or `runtime.h`, the
  native gates, the foreign includes), every typedef in the program, the
  evidence vector and its vtables, and the declaration of every derived
  method. Every other header includes it.
- `<m>.h`: what other modules can name in module `m`: its pub functions
  and globals, and the methods of its trait impls.
- `<m>.priv.h`: the rest of `m`: its private functions and globals, its
  init function, and the signatures of the generic instances its unit
  defines.

Unit `m` includes `<m>.h`, `<m>.priv.h`, and the header of each symbol
its C text names. The build reads the declared names from each header it
wrote, and scans each unit for them. A header that has a line the build
cannot read, or a name without `blink` in it, goes into every unit.

Why every type is in one header: a unit can hold a type by value that it
got through a module it does not import (`pc` holds `pb.Seg`, which holds
`pa.Point`). C needs the layout of `Point` to compile `pc`, so a header
per module of types would need the import graph of each type. One types
header gives every unit every layout.

Why the scan and not the imports: a unit names symbols of modules it
does not import (the init function of every module from `__main__`, a
method of a type it got through another module, a generic instance that
another module defines). It also imports modules for a type only, and
needs no header for that.

Why no unit can get a wrong or missing declaration: every header comes
from the same front end and registries that emit the unit, so a
declaration agrees with its definition. A missing header is a cc error:
C rejects a call to an undeclared function and a read of an undeclared
name. The scan can only include too much: a word that looks like a
symbol costs one header more.

What recompiles:

- A private-body edit changes one unit and no header.
- A new private function or global changes `<m>.priv.h`, which only
  units that name a private symbol of `m` include (usually `m` alone).
- A pub signature edit or a new pub function changes `<m>.h`, which
  recompiles `m` and the units that name a symbol of `m`.
- A new type, a new generic struct instance, or a new carrier changes
  `blink.types.h`, which recompiles every unit.
- A new instance of a generic changes the `<m>.priv.h` of the module
  that declares the generic.

`src/cli.bl` has 49 units and 131 headers (0.45 MB of headers, from 7.3 MB
when every unit included every header).

Edit-loop bench on cli, `--per-module`, 5 reps, median wall seconds (units
compiled), the gen1 of `5626a2b6` against the gen1 of `a026a18c` (since amended):

| case | every header | headers it names |
|---|---|---|
| nochange | 1.565 (0) | 1.510 (0) |
| body-cname | 1.783 (1) | 1.692 (1) |
| body-typecheck | 4.043 (1) | 3.927 (1) |
| pubfn-cname | 5.798 (48) | 2.753 (14) |
| cold-obj | 5.861 (48) | 5.280 (49) |
| cold-all | 8.164 (49) | 7.138 (50) |

The serial cc CPU of a cold build of the units, without sqlite3.c, went
from 13.79 s to 10.95 s. `a026a18c` has one more module.

## Edit-loop bench

`task bench-edit-loop` on the gen1 `blink` built from `80ee3a3e`, 5 reps, 12
cores, under `blink-gates.slice`. Median wall seconds;
`bench/edit_loop/monolith_80ee3a3e.tsv` and
`bench/edit_loop/per_module_80ee3a3e.tsv` hold the full rows. The "before"
column is the gen1 of `b59311e8` under the same conditions.

| target | case | monolith | `--per-module` before | `--per-module` | units compiled |
|---|---|---|---|---|---|
| cli | nochange | 0.763 | 1.518 | 0.948 | 0 |
| cli | body-cname | 10.424 | 1.684 | 1.118 | 1 |
| cli | body-typecheck | 10.424 | 3.929 | 3.367 | 1 |
| cli | pubfn-cname | 10.429 | 2.778 | 1.792 | 14 |
| cli | run-body-cname | 10.431 | 1.691 | 1.104 | 1 |
| cli | test-body-cname | 2.119 | 2.126 | 2.117 | 1 |
| cli | cold-obj | 10.447 | 5.039 | 4.026 | 49 |
| cli | cold-all | 12.807 | 7.414 | 6.394 | 50 |
| small | nochange | 0.073 | 0.135 | 0.072 | 0 |
| small | body-inventory | 0.138 | 0.179 | 0.119 | 1 |
| small | pubfn-model | 0.137 | 0.184 | 0.122 | 3 |
| small | run-body-inventory | 0.139 | 0.181 | 0.121 | 1 |
| small | test-body-inventory | 0.141 | 0.140 | 0.139 | 1 |
| small | cold-obj | 0.138 | 0.214 | 0.123 | 5 |

When this table was measured, `blink test` did not take the flag, so the
`test-*` rows ran the same path in both columns. Since `5ac58904` it does,
and `BENCH_FLAGS` reaches the `test-*` cases. The `test-*` rows from the
gen1 `blink` of `a2bb3b1a` (before) and of `5ac58904` (after), under the same
conditions; `bench/edit_loop/monolith_5ac58904.tsv` and
`bench/edit_loop/per_module_5ac58904.tsv` hold the full rows:

| target | case | monolith before | monolith after | `--per-module` before | `--per-module` after | units compiled |
|---|---|---|---|---|---|---|
| cli | test-body-cname | 2.123 | 2.121 | 2.116 | 0.602 | 1 |
| small | test-body-inventory | 0.143 | 0.139 | 0.140 | 0.134 | 1 |

In the before column the flag did not reach `blink test`. The other rows of
both runs are within 0.05 s of each other. What the numbers show:

- A small program is now as fast as the monolith or faster on every case.
  No few-modules threshold sends it to the one-unit path.
- A body edit on a large program gains the most: the build compiles one
  unit, and the time follows the size of that unit (`cname.c` 0.15 s,
  `typecheck.c` 2.4 s).
- `cold-obj` and `pubfn-cname` gain from more than four compiles at once.
- `nochange` on cli was then 0.19 s slower than the monolith. All of it
  was emit (`emit_s` 0.905 against 0.725): the build emitted 131 headers
  and 49 units each time, then hashed them to find that nothing changed.
  Emit reuse (below) removes that cost.

What made the emit cheaper, from 1.48 s to 0.91 s on cli `nochange`:

- The cache keys hash all units in one batched exec, not one exec per
  unit, and one exec answers the cache lookup for every key.
- The emit scans the program once for the key-table nodes and the
  carriers it spells, not once per unit, and builds the function index
  on its first lookup.
- One exec per batch installs the new objects (above).
- The CPU count is read only when a unit compiles, and the native-dep
  scan reads the units and the headers they include in process, not
  through `cat`. The gates and markers live in the unit `.c` files, and
  no header that no unit includes holds one (checked on cli and small), so
  the scan finds the same deps.

### Emit reuse

`task bench-edit-loop` on the gen1 `blink` built from `7f4d7dbb`, 5 reps, 12
cores, under `blink-gates.slice`. Median wall seconds, with min and max where
the ranges of two columns are near.
`bench/edit_loop/monolith_7f4d7dbb.tsv` and
`bench/edit_loop/per_module_7f4d7dbb.tsv` hold the rows on the `7f4d7dbb`
tree. The bench builds the tree it is in, and `7f4d7dbb` adds a unit to
cli, so the like-for-like columns build the `d1cf8f55` tree with the gen1
of `d1cf8f55` (before) and of `7f4d7dbb` (after), in two runs on one machine on the same day:
`bench/edit_loop/per_module_d1cf8f55.tsv` and
`bench/edit_loop/per_module_7f4d7dbb_on_d1cf8f55.tsv`.

| target | case | monolith | `--per-module` before | `--per-module` after | `--per-module` on `7f4d7dbb` |
|---|---|---|---|---|---|
| cli | nochange | 0.752 | 0.954 | 0.497 | 0.499 |
| cli | body-cname | 10.518 | 1.109 [1.095-1.134] | 1.124 [1.101-1.140] | 1.124 |
| cli | body-typecheck | 10.519 | 3.370 [3.339-3.375] | 3.376 [3.355-3.390] | 3.395 |
| cli | pubfn-cname | 10.509 | 1.808 | 1.798 | 1.812 |
| cli | run-body-cname | 10.515 | 1.124 | 1.131 | 1.130 |
| cli | test-body-cname | 2.119 | 0.601 [0.599-0.607] | 0.608 [0.596-0.611] | 0.607 |
| cli | cold-obj | 10.509 | 4.029 | 3.561 | 3.575 |
| cli | cold-all | 12.871 | 6.407 | 5.918 | 5.940 |
| small | nochange | 0.073 | 0.073 | 0.071 | 0.071 |
| small | body-inventory | 0.139 | 0.120 [0.117-0.122] | 0.121 [0.120-0.123] | 0.121 |
| small | pubfn-model | 0.138 | 0.121 | 0.121 | 0.122 |
| small | run-body-inventory | 0.139 | 0.123 | 0.121 | 0.121 |
| small | test-body-inventory | 0.141 | 0.136 | 0.135 | 0.136 |
| small | cold-obj | 0.137 | 0.123 | 0.122 | 0.123 |

- cli `nochange` is now 0.25 s faster than the monolith. The build runs
  the front end, finds its inputs the same as the last build's, and takes
  that build's units: `emit_s` 0.455 against 0.911.
- `cold-obj` and `cold-all` remove the objects but keep the units, so they
  also take the units and gain about 0.47 s.
- An edit costs the build the inputs text (6.2 MB on cli) and its write.
  In the like-for-like columns each edit case's range overlaps its before
  range; the largest change in a median is +0.015 s, on cli `body-cname`.

### After the flip

`task bench-edit-loop` on the gen1 `blink` built from `6ee0ea14`, 5 reps, 12
cores, under `blink-gates.slice`, with no flags (the per-module default) and
with `BENCH_FLAGS=--no-per-module` (one unit).
`bench/edit_loop/per_module_6ee0ea14.tsv` and
`bench/edit_loop/monolith_6ee0ea14.tsv` hold the rows. Median wall seconds,
then the default's split.

| target | case | `--no-per-module` | default | emit_s | cc_s | link_s |
|---|---|---|---|---|---|---|
| cli | nochange | 0.770 | 0.496 | 0.452 | 0.000 | 0.043 |
| cli | body-cname | 10.504 | 1.142 | 0.947 | 0.152 | 0.043 |
| cli | body-typecheck | 10.515 | 3.403 | 0.944 | 2.412 | 0.043 |
| cli | pubfn-cname | 10.508 | 1.826 | 0.948 | 0.839 | 0.043 |
| cli | run-body-cname | 10.558 | 1.124 | 0.932 | 0.151 | 0.042 |
| cli | test-body-cname | 2.123 | 0.603 | 0.465 | 0.102 | 0.035 |
| cli | cold-obj | 10.530 | 3.580 | 0.505 | 3.034 | 0.043 |
| cli | cold-all | 12.918 | 5.942 | 0.590 | 5.302 | 0.043 |
| small | nochange | 0.073 | 0.071 | 0.052 | 0.000 | 0.019 |
| small | body-inventory | 0.139 | 0.121 | 0.065 | 0.036 | 0.019 |
| small | pubfn-model | 0.139 | 0.121 | 0.066 | 0.036 | 0.019 |
| small | run-body-inventory | 0.137 | 0.121 | 0.065 | 0.037 | 0.019 |
| small | test-body-inventory | 0.141 | 0.135 | 0.062 | 0.053 | 0.020 |
| small | cold-obj | 0.137 | 0.120 | 0.064 | 0.037 | 0.019 |

The default rows match the `--per-module` rows on `7f4d7dbb` within their
spread: the flip changes which path runs, not the path. A body edit on cli
spends 0.95 s of its 1.14 s in emit (front end, codegen, cache hashing), so
the 1.0 s goal for it needs a faster emit, not a faster cc.

### Unit reuse

`task bench-edit-loop` on the gen1 `blink` built from `a2e9dc72` (before) and
from `b9aaeade` (after), 5 reps, 12 cores, under `blink-gates.slice`, back to
back on one machine, both on the `b9aaeade` tree. Median wall seconds, with
min and max on the rows the goal names. `bench/edit_loop/per_module_a2e9dc72.tsv`,
`bench/edit_loop/per_module_b9aaeade.tsv` and the two `monolith_*.tsv` files
of those shas hold the rows.

| target | case | `--no-per-module` after | before | after | after emit_s | after cc_s |
|---|---|---|---|---|---|---|
| cli | nochange | 0.779 | 0.508 | 0.524 | 0.482 | 0.000 |
| cli | body-cname | 10.635 | 1.153 [1.142-1.162] | 0.890 [0.875-0.906] | 0.697 | 0.150 |
| cli | body-typecheck | 10.603 | 3.389 | 3.204 | 0.765 | 2.396 |
| cli | pubfn-cname | 10.610 | 1.845 | 1.862 | 0.971 | 0.845 |
| cli | run-body-cname | 10.604 | 1.146 | 0.903 | 0.709 | 0.152 |
| cli | test-body-cname | 2.128 | 0.612 | 0.501 | 0.360 | 0.105 |
| cli | cold-obj | 10.600 | 3.592 | 3.611 | 0.540 | 3.033 |
| cli | cold-all | 12.997 | 5.969 | 5.993 | 0.622 | 5.329 |
| small | nochange | 0.075 | 0.072 [0.071-0.076] | 0.074 [0.072-0.074] | 0.054 | 0.000 |
| small | body-inventory | 0.140 | 0.122 | 0.125 | 0.066 | 0.038 |
| small | pubfn-model | 0.139 | 0.122 | 0.123 | 0.068 | 0.036 |
| small | run-body-inventory | 0.141 | 0.124 | 0.125 | 0.067 | 0.038 |
| small | test-body-inventory | 0.142 | 0.134 | 0.137 | 0.064 | 0.053 |
| small | cold-obj | 0.139 | 0.122 | 0.123 | 0.066 | 0.038 |

- A body edit on cli takes 47 of its units and emits two, the edited module
  and `__main__`: `body-cname` falls by 0.26 s, to 0.89 s, under the 1.0 s
  goal.
- Each build that may take units parses for the interface texts and keeps
  the longer inputs text: `nochange`, `pubfn-cname`, `cold-obj` and
  `cold-all` on cli pay 0.02 s for it. The interface texts are 3.75% of the
  instructions of a cli `nochange` build (callgrind).
- Each small row is within the spread of its before row.
- Each `--no-per-module` row is within the spread of its `a2e9dc72` row: a
  monolith build does not track the sources it reads or parse for the
  interface texts.

### Build through the daemon

`blink build` and `blink run` ask the project's daemon to build. The daemon
serves any entry file of the project, from any directory of it (see "Any
entry of the project" below). It builds only when the client's identity (its
binary as typed, the compiler's sha256 and its env but `PWD`) and front-end
settings (`--strict-struct-layout`, `BLINK_TRACE`, emit reuse) are its own.
The worker of the entry rechecks if an input changed, then forks a child
that builds from the program it checked: the child skips the front end and
runs mono, the analyses, emit, unit reuse, cc and link. The worker sends the
client the child's stdout, stderr and exit code. For `run`, the client runs the program itself, so the program's stdin,
args, env, cwd and exit code are the client's. A client the daemon does not
serve, or a child that declines (deps to resolve, a stale dev archive, a path
that needs a second front end), builds cold.

While a worker waits for a client, it polls each 0.5 s. A poll reads the
mtime (in ms) and the size of each file the last check read, and whether each
path the loader probed finds a file. Only when one of these moved does it
compare the files byte for byte with what the check read, and recheck if they
differ. The runtime gives mtime only in ms and no inode; a new runtime call
needs a gen0 re-pin, and a `struct stat` binding is laid out per platform, so
the size comes from `lseek(fd, 0, SEEK_END)`. A same-size edit inside one ms,
or one whose mtime was set back, moves no stat. The poll misses it, and the
build catches it: before each build the daemon compares the bytes of every
input and rechecks if one differs. Just after each check the daemon takes the
stats and compares bytes once, so an edit between the loader's read and the
stat forces a recheck at the next poll. Idle on `src/cli.bl` for 60 s, the
daemon used 0.767% and 0.750% of a core (two runs) when each poll compared
bytes, and 0.133% and 0.133% with the stat trigger. Interface text (kept for
emit reuse) costs nothing that a 10 ms tick shows on a cli recheck: an edit
then a `blink check` through the daemon takes 0.397 s median wall and 42 ticks
of daemon CPU with it on, and 0.394 s and 43 ticks with it off (an empty
`BLINK_CACHE_DIR`), 6 edits each.

While a build child runs, the daemon serves on: a status, check or query gets
its answer at once, and the daemon does not poll for edits. Each turn it reaps
the child if it ended (`waitpid` with `WNOHANG`), then waits on its socket for
1 ms at most. A build client so waits at most 1 ms past the child's exit, plus
the one request the daemon serves then. The runtime has no wait on both the
socket and the child: `SIGCHLD` is off, and a pipe from the child needs
`Ptr.offset` on the `int[2]` that `pipe()` fills, which it rejects. A first
try woke on a unix socket pair through a private listener file. It cost a
listener, a connect and an accept per build, and the first `std.libc` import
in src, to save under 1 ms, so the daemon ticks. Waking on the child's exit
is a follow-up.

Two builds of one entry write the same units dir and program, so a build that
comes while a child runs waits in a queue, oldest first, and runs when the
child ends. A stop that comes then lets the child end, since a killed build
would leave its cc and ld writing the files the client's cold build writes
next. The daemon then sends each queued build to build cold ("the daemon is
stopping"), replies to the stop and exits. `blink daemon status` gives
`building` (0 or 1), `queued` and `stopping` before `builds` and `checks`.

What a user sees while a build runs through the daemon:

- `blink check`, `blink daemon status` and editor queries reply at once, from
  the files as they are. A check may recheck; the child builds from the
  program it had at the fork, and the next build compares bytes again first.
- A second `blink build` or `blink run` waits for the running build, then
  runs. Its output is the same as a cold build's.
- `blink daemon stop` waits for the running build to end, then stops. Builds
  that were queued build cold.
- A client that quits mid-build leaves the daemon serving. The daemon reaps
  the child and removes its `.blink/w<pid>-<k>/build-<n>.*` files.
- A daemon killed mid-build (`kill -9`, a crash) can leave
  `.blink/w<pid>-<k>/build-<n>.*` files. The next daemon does not sweep them
  at start: it cannot tell them from the files of another daemon that serves
  the same dir, and they are small, so a sweep adds risk for no gain.
- Two cold builds of one output at once, outside the daemon, can still race
  on the swap of the units dir. That is a separate bug.

`task bench-edit-loop` on the gen1 `blink` built from `a6b467cb` (before) and
from `b809e4a1` (after), 5 reps, 12 cores, under `blink-gates.slice`, back to
back on one machine, all on the `eea901c6` tree. The daemon column is
`BENCH_DAEMON=1 BENCH_SETTLE=1` on the `b809e4a1` binary: the daemon starts
after the warm build, and the bench waits 1 s between the edit and the timed
build. It served 15 builds on each target. Median wall seconds, with min and
max on the rows the goal names. `bench/edit_loop/per_module_a6b467cb.tsv`,
`bench/edit_loop/per_module_b809e4a1.tsv`,
`bench/edit_loop/per_module_daemon_b809e4a1.tsv` and the two `monolith_*.tsv`
files of those shas hold the rows.

| target | case | `--no-per-module` after | before | after | daemon | daemon emit_s | daemon cc_s |
|---|---|---|---|---|---|---|---|
| cli | nochange | 0.785 | 0.525 | 0.519 | | | |
| cli | body-cname | 10.681 | 0.902 [0.887-0.911] | 0.894 [0.880-0.909] | 0.670 [0.650-0.706] | 0.476 | 0.152 |
| cli | body-typecheck | 10.667 | 3.207 | 3.202 | | | |
| cli | pubfn-cname | 10.658 | 1.900 [1.879-1.922] | 1.911 [1.879-1.918] | 1.734 [1.715-1.759] | 0.818 | 0.874 |
| cli | run-body-cname | 10.660 | 0.909 | 0.904 | 0.713 [0.700-1.060] | 0.518 | 0.151 |
| cli | test-body-cname | 2.127 | 0.499 | 0.497 | | | |
| cli | cold-obj | 10.657 | 3.612 | 3.602 | | | |
| cli | cold-all | 13.039 | 5.980 | 5.987 | | | |
| small | nochange | 0.074 | 0.072 | 0.072 | | | |
| small | body-inventory | 0.139 | 0.123 | 0.121 | 0.128 [0.124-0.131] | 0.072 | 0.037 |
| small | pubfn-model | 0.138 | 0.125 | 0.122 | 0.131 [0.129-0.133] | 0.074 | 0.038 |
| small | run-body-inventory | 0.140 | 0.123 | 0.123 | 0.129 [0.128-0.132] | 0.074 | 0.037 |
| small | test-body-inventory | 0.143 | 0.135 | 0.138 | | | |
| small | cold-obj | 0.140 | 0.122 | 0.122 | | | |

- Through the daemon, a body edit on cli builds in 0.670 s, 0.22 s under the
  cold build. The child's emit_s falls from 0.698 to 0.476: the front end is
  gone, and mono, the analyses, the unit headers and the reuse hashes stay.
- The front end of a cold cli build is about 0.39 s, so 0.50-0.53 s was the
  estimate for this design. A strace of the daemon and a client shows where
  some of the rest goes: the client hashes the compiler and its env for the
  identity (about 15 ms), the child hashes the compiler again for the dev
  archive check (about 11 ms), and the child's exit takes about 12 ms. The
  child's emit, with no subprocess, takes about 0.29 s, near the cold emit
  stages that remain.
- A small program gains nothing: its front end is a few ms, and the daemon
  round trip and fork cost more. Each small daemon row is 0.005-0.009 s over
  the cold row.
- Without a daemon, each row is within the spread of its before row, or
  0.003 s from it.
- The daemon runs one build at a time; a build sent during a build waits for
  it. Other requests do not wait (see below).
- With no wait between the edit and the build (`BENCH_SETTLE=0`, tree
  `a0d2bbb0`), the body-cname build through the daemon takes 1.083 s
  [1.061-1.116], 0.19 s over the cold row above (an earlier run on the
  `eea901c6` tree, not measured beside it): the build finds the check stale,
  rechecks (about 0.4 s), then builds. With a 1 s wait on the same binary it
  takes 0.680 s [0.641-0.718]. `per_module_daemon_settle0_a0d2bbb0.tsv` and
  `per_module_daemon_settle1_a0d2bbb0.tsv` hold the rows.

Serve during a build. A `blink daemon status` sent 0.1 s into a build through
the daemon on `src/cli.bl` (tree `2037f4d5`, 5 builds) took 566-621 ms on the
gen1 `blink` built from `2037f4d5`: the daemon waited in `waitpid` until the
build ended. On the gen1 `blink` built from `35662915` it takes 2-3 ms, the
same as with no build. The builds take 670-724 ms before and 662-724 ms after.

`task bench-edit-loop` with `BENCH_DAEMON=1 BENCH_SETTLE=1`, 5 reps, 12 cores,
under `blink-gates.slice`, back to back on the `35662915` tree, on the gen1
`blink` built from `2037f4d5` (before) and then from `35662915` (after). Median
wall seconds [min-max]. `per_module_daemon_settle1_2037f4d5.tsv` and
`per_module_daemon_settle1_35662915.tsv` hold the rows.

| target | case | before | after |
|---|---|---|---|
| cli | nochange | 0.182 [0.180-0.189] | 0.187 [0.181-0.190] |
| cli | body-cname | 0.535 [0.511-0.547] | 0.538 [0.532-0.546] |
| cli | body-typecheck | 2.881 [2.857-2.906] | 2.876 [2.867-2.915] |
| cli | pubfn-cname | 1.637 [1.606-1.672] | 1.628 [1.606-1.655] |
| cli | run-body-cname | 0.591 [0.575-0.878] | 0.567 [0.561-0.869] |
| cli | test-body-cname | 0.483 [0.480-0.485] | 0.481 [0.477-0.485] |
| cli | cold-obj | 3.426 [3.419-3.549] | 3.431 [3.414-3.597] |
| cli | cold-all | 6.037 [6.025-6.064] | 6.053 [6.036-6.068] |
| small | nochange | 0.072 [0.070-0.073] | 0.073 [0.072-0.074] |
| small | body-inventory | 0.126 [0.123-0.129] | 0.129 [0.124-0.130] |
| small | pubfn-model | 0.130 [0.127-0.131] | 0.130 [0.128-0.132] |
| small | run-body-inventory | 0.131 [0.128-0.133] | 0.133 [0.129-0.134] |
| small | test-body-inventory | 0.137 [0.136-0.138] | 0.137 [0.135-0.140] |
| small | cold-obj | 0.129 [0.128-0.132] | 0.128 [0.126-0.133] |

- Each row is within the spread of its before row. The tick adds about 0.5 ms
  on average past the child's exit, under the noise.
- Four cli runs of 11 reps each, before, after, before, after
  (`per_module_daemon_settle1_cli_reps11_run<n>_<sha>.tsv`), over 22 builds
  each: body-cname 0.5605 [0.531-0.598] before and 0.5540 [0.538-0.578]
  after, pubfn-cname 1.7215 [1.629-1.779] and 1.6775 [1.621-1.757], and
  run-body-cname 0.6130 [0.600-0.995] and 0.6200 [0.576-0.988].
- The daemon spends no more CPU in a build: over 5 builds of `src/cli.bl` its
  own CPU time is 221 and 220 ticks (of 10 ms) before, and 220 and 221 after.

### Any entry of the project

Before this change, the daemon served only the entry it started on, as typed
from the directory it started in. A check of `./src/cli.bl`, of its absolute
path, or of `../src/cli.bl` from `tests/` ran cold, and so did a check or
build of a second entry such as `examples/calculator.bl`.

The daemon is now a router and a set of workers:

- The router runs no front end. It keys each check, build or run by the
  entry's absolute path, with no `.`, `..` or empty parts. A symbolic link
  and its target are two keys.
- For a new key, the router forks a worker. The worker checks that entry and
  serves it as the daemon served its one entry before. Its socket and files
  are in `.blink/w<router pid>-<k>/`.
- The router does not wait on a check, a build or a query. It replies with
  the name of the worker that serves the request:
  `{"ok":false,"served":0,"worker":"w<router pid>-<k>"}`. The client sends
  the same request to `.blink/w<router pid>-<k>/daemon.sock` and uses the
  reply of the worker. `daemon_send` in `src/daemon.bl` does this for
  `blink check`, `build`, `run` and `query`, the only clients of the
  socket. It follows one redirect only. A second redirect, or a worker that
  is gone, gives no reply, and the client runs cold.
- A client from before this change does not follow the redirect. For a
  check, build or run it reads `"served":0` as a request the daemon did not
  serve, and runs cold, so its output stays correct. For a query it prints
  the redirect as its answer. Run `blink daemon stop` and start the daemon
  again after an upgrade.
- A worker checks in the client's directory, with the entry as the client
  typed it, since a diagnostic spells its file relative to both. A new
  spelling of the same entry makes the worker check again (about 0.4 s on
  `src/cli.bl`).
- The worker of the entry that the daemon started on (the home worker) also
  answers editor queries, and the router does not stop it. The router keeps
  at most `--max-entries` workers (default 8). For one more, it stops the
  worker that a client used longest ago, but not one that builds or holds
  builds.
- `PWD` is not part of the identity, since each directory of a project has
  its own. The request carries it, and the build child sets it. `argv[0]`
  stays in the identity as typed: a build finds its `lib/` and archive from
  it, so the daemon builds only for a client that typed it the same. A client
  that typed it another way builds cold.
- A worker ends when its router is gone. It sees this at its next accept tick
  (0.5 s when idle, 1 ms while a build runs). It then removes its directory.
  The directory name holds the router's pid, so a worker of a daemon that was
  killed does not remove the directory of a new daemon.
- The GC stops its marker threads in a forked child. A worker lives as long
  as the daemon and checks again at each edit, so it starts the marker
  threads again after the fork.
- The router serves only an entry in the project root (the directory of
  the nearest `blink.toml`) or below it, by the key above. A file outside
  it can be part of another project, so its check or build runs cold. The
  entry that the daemon started on is served wherever it is.
- The router refuses a build from a client with another identity or other
  front-end settings before it routes the build. The client builds cold, and
  the router forks no worker for it. The worker does the same check again. A
  check request carries no identity, before and after this change.
- When a worker ends without a stop (killed or crashed), the router reaps it
  at its next accept tick and removes its directory. The next request for
  that entry gets a new worker. A client whose request was in that worker
  gets no reply and runs cold. A build child of that worker ends when its
  build ends. Until then, it and the client's cold build can write the same
  outputs, as when a daemon is killed mid-build (above).
- `blink daemon status` gives `entries` (the workers that serve) after
  `stopping`. `builds` and `checks` are the sums over all workers, also the
  workers the router stopped.

A script runs each case 5 times, on the gen1 `blink` built from `27b9888e`
(before) and then from `799b05b3` (after), back to back under
`blink-gates.slice`, in a copy of the `799b05b3` tree. `calc` is
`examples/calculator.bl`. "settle1" waits 1 s between the edit and the
command. Median wall seconds [min-max].
`bench/edit_loop/daemon_any_entry_27b9888e.tsv` and
`bench/edit_loop/daemon_any_entry_799b05b3.tsv` hold the rows.

| case | before | after |
|---|---|---|
| cold check `src/cli.bl` | 0.380 [0.376-0.392] | 0.390 [0.378-0.392] |
| daemon check `src/cli.bl`, no change | 0.008 [0.007-0.010] | 0.009 [0.008-0.011] |
| daemon check `src/cli.bl`, edit, settle1 | 0.008 [0.008-0.008] | 0.009 [0.009-0.009] |
| daemon build `src/cli.bl`, body edit, settle1 | 0.582 [0.559-0.589] | 0.596 [0.567-0.597] |
| daemon check `./src/cli.bl` | 0.386 [0.380-0.392] | 0.009 [0.009-0.422] |
| daemon check absolute `src/cli.bl` | 0.388 [0.383-0.393] | 0.009 [0.009-0.415] |
| daemon check `../src/cli.bl` from `tests/` | 0.383 [0.378-0.389] | 0.009 [0.009-0.408] |
| cold check calc | 0.011 [0.010-0.011] | 0.011 [0.010-0.011] |
| daemon check calc, no change | 0.011 [0.010-0.011] | 0.003 [0.002-0.003] |
| daemon check calc, edit, settle1 | 0.011 [0.010-0.012] | 0.003 [0.003-0.003] |
| cold build calc, body edit | 0.152 [0.151-0.154] | 0.152 [0.151-0.154] |
| daemon build calc, body edit, settle1 | 0.160 [0.158-0.161] | 0.162 [0.160-0.164] |

- Each other spelling of `src/cli.bl` now gets its answer from the daemon.
  The max of each of those rows is the first check of a new spelling, which
  checks again.
- A check of calc through the daemon takes 3 ms, against 11 ms cold.
- A build of calc through the daemon gains nothing, as with the small target
  below: its front end is a few ms.

`task bench-edit-loop` with `BENCH_DAEMON=1 BENCH_SETTLE=1`, 5 reps, 12 cores,
under `blink-gates.slice`, back to back on the `799b05b3` tree, on the gen1
`blink` built from `27b9888e` (before) and then from `799b05b3` (after). The
daemon served 30 builds on cli and 25 on small for each. Median wall seconds
[min-max]. `per_module_daemon_settle1_27b9888e.tsv` and
`per_module_daemon_settle1_799b05b3.tsv` hold the rows.

| target | case | before | after |
|---|---|---|---|
| cli | nochange | 0.182 [0.178-0.184] | 0.189 [0.188-0.198] |
| cli | body-cname | 0.559 [0.541-0.565] | 0.556 [0.525-0.595] |
| cli | body-typecheck | 2.890 [2.879-2.940] | 2.921 [2.903-2.937] |
| cli | pubfn-cname | 1.675 [1.667-1.741] | 1.648 [1.637-1.653] |
| cli | run-body-cname | 0.604 [0.596-0.985] | 0.614 [0.589-0.903] |
| cli | test-body-cname | 0.481 [0.477-0.493] | 0.482 [0.476-0.482] |
| cli | cold-obj | 3.449 [3.433-3.581] | 3.436 [3.424-3.599] |
| cli | cold-all | 6.071 [6.048-6.079] | 6.058 [6.047-6.066] |
| small | nochange | 0.072 [0.072-0.074] | 0.073 [0.070-0.074] |
| small | body-inventory | 0.126 [0.123-0.131] | 0.129 [0.125-0.130] |
| small | pubfn-model | 0.133 [0.131-0.135] | 0.132 [0.128-0.135] |
| small | run-body-inventory | 0.134 [0.131-0.134] | 0.134 [0.132-0.136] |
| small | test-body-inventory | 0.137 [0.135-0.140] | 0.136 [0.134-0.139] |
| small | cold-obj | 0.130 [0.129-0.133] | 0.130 [0.128-0.133] |

- cli nochange is the one row out of the spread of its before row, by 4 ms.
  In 4 more cli runs of 11 reps, after, before, after, before, it is 0.190,
  0.185, 0.189 and 0.182. In a script that starts each daemon in turn and
  times 21 no-change builds, before is 0.184 and 0.192, and after is 0.191
  and 0.190. The relay adds a fork and a connect to each request; a check
  with no change shows it at about 1 ms.
- Without the GC marker threads in the worker (the gen1 `blink` built from
  `75c8dc00`), the small rows were 4-8 ms slower than before after edits.
  In 4 small runs of 11 reps, after, before, after, before, cold-obj was
  0.137, 0.130, 0.138 and 0.129. With the marker threads (`799b05b3`), it is
  0.135, 0.129, 0.129 and 0.126
  (`per_module_daemon_settle1_small_reps11_run<n>_<sha>.tsv`).

### Unit headers from one walk

Before each module header pair, the build wrote every typedef of the
program and threw the text away, so a signature that spells a typedef does
not write it again. That walk is the same for every module, and on cli it
ran 65 times: about 100 ms of the 139-145 ms the unit headers took on a
body edit. Now the build walks once (`header_preamble` in `src/cg.bl`),
keeps what the walk marked written (the typedef guards and buffer in
`layout`, the typedef and vtable marks in `cg_decl`), and starts each
module header from those marks. Each header reads them as a base under its
own marks, so no header copies them. The cold walk and the preamble call
one function, `mark_typedefs_written`, and the capture and the install sit
next to each other: any state the walk comes to write must go into both.

A mark-only pass, one that walks but prints nothing, would not do: a perf
profile of the walk puts 14% of it in printing. The rest (GC, variant
discriminants, member types, layout, typedef names) a mark-only pass pays
too, once per module.

The header still comes from the program, never from the last build, so
nothing in it can be stale: content decides, as for every other file. The
per-module tests run under `BLINK_EMIT_REUSE_VERIFY=1`, and verify writes
each header after a walk of its own and compares bytes. A header pass
skips lowering `#embed` initializers when it asks whether a module needs
an init function: such an initializer lowers to one string constant, and
spelling a large file as a C literal cost more than the rest of the
header. The skip is a parameter of that call, and verify writes the
headers without it.

Phase split of a cli body edit (`src/cname.bl`), 5 reps, in ms. The unit
headers are the program facts, the types header and the module headers:

| | facts | types header | module headers | wall |
|---|---|---|---|---|
| before | 5-6 | 6-7 | 127-132 | 890-1000 |
| after | 5-6 | 6-7 | 24-28 | 788-805 |

The 36-41 ms left are the 65 module header pairs themselves (19-22 ms to
write the text: each lowers its module's global initializers and prints
its signatures), the types header and the program facts.

`task bench-edit-loop` on the gen1 `blink` built from `b65ed27c` (before)
and from `02d27d7e` (after; since amended to `96ed6b3c`, which adds a test
and no src change), 5 reps, 12 cores, under `blink-gates.slice`, back to
back on one machine, all on the `02d27d7e` tree. The daemon
columns are `BENCH_DAEMON=1 BENCH_SETTLE=1`; the daemon served 30 cli
builds in each run. Median wall seconds, with min and max on the rows the
goal names. The `per_module_*`, `monolith_*` and
`per_module_daemon_settle1_*` files of those two shas in `bench/edit_loop/`
hold the rows.

| target | case | `--no-per-module` before | after | before | after | daemon before | daemon after |
|---|---|---|---|---|---|---|---|
| cli | nochange | 0.777 | 0.773 | 0.522 | 0.526 | 0.183 | 0.185 |
| cli | body-cname | 10.739 | 10.717 | 0.901 [0.887-0.914] | 0.796 [0.790-0.799] | 0.676 [0.649-0.719] | 0.533 [0.524-0.537] |
| cli | body-typecheck | 10.696 | 10.680 | 3.219 | 3.099 | 3.003 | 2.890 |
| cli | pubfn-cname | 10.682 | 10.683 | 1.902 [1.886-1.928] | 1.796 [1.792-1.821] | 1.743 | 1.679 |
| cli | run-body-cname | 10.691 | 10.702 | 0.902 | 0.797 | 0.705 | 0.573 |
| cli | test-body-cname | 2.117 | 2.126 | 0.495 | 0.480 | 0.498 | 0.476 |
| cli | cold-obj | 10.697 | 10.689 | 3.622 | 3.616 | 3.446 | 3.398 |
| cli | cold-all | 13.089 | 13.090 | 6.002 | 5.995 | 6.039 | 6.031 |
| small | nochange | 0.075 | 0.073 | 0.073 | 0.072 | 0.071 | 0.072 |
| small | body-inventory | 0.141 | 0.140 | 0.122 | 0.122 | 0.127 | 0.128 |
| small | pubfn-model | 0.142 | 0.140 | 0.126 | 0.121 | 0.130 | 0.130 |
| small | run-body-inventory | 0.139 | 0.139 | 0.124 | 0.122 | 0.131 | 0.131 |
| small | test-body-inventory | 0.143 | 0.144 | 0.135 | 0.134 | 0.139 | 0.139 |
| small | cold-obj | 0.139 | 0.139 | 0.124 | 0.123 | 0.127 | 0.128 |

- A cli body edit builds in 0.796 s, 0.105 s under the before row, and in
  0.533 s through the daemon, 0.143 s under. Each cli row that writes the
  module headers gains about 0.1 s (`emit_s` of body-cname goes from 0.700
  to 0.603, and through the daemon from 0.480 to 0.338).
- `nochange` takes the whole emit from the last build and writes no
  header, so it does not change. Nor do the monolith rows, which write no
  module header, or the small rows, whose headers cost a few ms.

## Blockers before the default flipped

None from the edit-loop bench: `nochange` on cli is faster than the
monolith, and no per-module case is slower than before outside its spread.
