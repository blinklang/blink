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
  written to `<output>.units/` next to the binary. A module of more than
  512 decls is cut into files of its own (see "Large units in chunks"
  below). The
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

Unit `m` includes `blink.types.h` and no module header. In place of
the module headers, the unit holds a copy of the declaration of each
symbol its C text names (`unit_declarations` in
`src/build_unit_headers.bl`): first the lines of `<m>.h` and
`<m>.priv.h`, then those of the other headers in module order, each
header in its own line order, each line once. The build reads the
declarations from each header it wrote, and scans each unit for their
names. The scan reads whole C identifiers in code: it skips strings,
character constants and comments, and `blink_lib_tally` does not match
inside `blink_lib_tally_all`. A use by address and a read of a global
count as a call does. A header that has a line the build cannot read
(any line other than its guard, its include of `blink.types.h` and
one-line declarations), or a name without `blink` in it, goes into every
unit as an include of the whole header. A unit with no include of its
own header gets no copy, and its key takes every header.
`BLINK_TRACE_CHANNELS=build.unit_headers` prints a line for each unit
that takes a whole header, with the reason. A cold build of `src/cli.bl`
prints none.

Why a copy and not an include: the object cache keys a unit on the
bytes cc compiles, the unit and each header it includes. A module
header holds each declaration of its module, so a new pub fn changed the
key of each unit that included the header, and each one recompiled. With
the copy, the key of a unit changes only when a declaration it uses
changes. The build still writes the module headers: the emit record
compares them to decide if it can keep the last build's units, and a
header that the scan cannot read is still included.

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
declaration agrees with its definition. A missing declaration is a cc
error: C rejects a read of an undeclared name, and each unit compiles
with `-Werror=implicit-function-declaration`, which the object key also
covers. gcc 14 and later, clang 16 and later and `zig cc` reject a call
to an undeclared function by default. gcc before 14 and clang before 16
only warn and then guess an `int` return, so without the flag such a
miss would link and run wrong.

What recompiles:

- A private-body edit changes one unit and no header.
- A new private or pub function or global adds a declaration that no
  other unit names yet, so it recompiles only the unit (or, in a cut
  module, the chunks) whose text changed.
- A pub signature edit changes one declaration, which recompiles `m`
  and each unit that names that function.
- A new type, a new generic struct instance, or a new carrier changes
  `blink.types.h`, which recompiles every unit.
- A new instance of a generic adds a line to the `<m>.priv.h` of the
  module that declares the generic, which recompiles the units that name
  the instance.

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
binary as typed, its compiler and its env but `PWD`) and front-end settings
(`--strict-struct-layout`, `BLINK_TRACE`, emit reuse) are its own (see
"Identity with no shell" below). The daemon serves only its own user (see
"Closed to other users" below).
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

Identity with no shell. The client named its compiler and env to the daemon
by a `sha256sum` in `sh` (about 7 ms a build or run), and each build child
hashed the compiler again in `sh` (about 5 ms). On Linux x86_64 and aarch64
the client now reads both from `/proc` and starts no process:

- The compiler is the device and inode that `/proc/self/maps` gives for the
  image mapped at offset 0 from its path, with the size and mtime of
  `/proc/self/exe`. The device and inode alone tell a changed compiler only
  because the kernel refuses a write to a file a process runs (`ETXTBSY`):
  the daemon runs its compiler as long as it lives, so a rebuild or a copy
  (`cp -p` too) reaches its path only as a new inode. The size and mtime are
  kept for a file system that does not refuse the write.
- The env goes whole, not hashed: each variable but `_`, `SHLVL`, `OLDPWD`
  and `PWD` as `<length>\n<variable>\n`, sorted. The length keeps a value
  that holds a newline from standing for two variables. The env goes only
  to a daemon of the client's own user (see below), and the daemon only
  compares it; it does not log, store or send it back.
- The daemon hashes its compiler once at start, so each build child, a fork
  of it, has the hash. The daemon builds only for a client whose compiler is
  its own, so it is the hash the child took before.

Elsewhere, or when `/proc` cannot say, the client hashes both in `sh` as
before. A strace of 3 client builds and 4 build turns of the small target
shows 9 `execve` per client before (the client; one `sh`, found on the 4th
`PATH` entry; two `sha256sum`, `env` and `sort`) and 1 after; the
daemon tree ran the compiler hash in `sh` 4 times (once per build) before
and once (at start) after.

`task bench-edit-loop` with `BENCH_DAEMON=1 BENCH_SETTLE=1`, 11 reps, under
`blink-gates.slice`, on the `dc552e4d` tree, alternating the gen1 `blink`
built from `dc552e4d` (before) and from `884ce827` (after): before, after,
before, after, per target. Median wall seconds [min-max] over the 22 builds
of both runs of a binary. `daemon_identity_in_process_<target>_run<n>_<sha>.tsv`
hold the rows. Load1 was at most 2.41.

| target | case | before | after | change |
|---|---|---|---|---|
| cli | nochange | 0.1860 [0.180-0.198] | 0.1740 [0.166-0.187] | -12.0 ms |
| cli | body-cname | 0.5480 [0.520-0.585] | 0.5415 [0.496-0.570] | -6.5 ms |
| cli | body-typecheck | 2.9140 [2.888-2.936] | 2.9175 [2.891-2.939] | +3.5 ms |
| cli | pubfn-cname | 1.7140 [1.676-1.733] | 1.6930 [1.660-1.732] | -21.0 ms |
| cli | run-body-cname | 0.5925 [0.577-0.974] | 0.5795 [0.546-1.001] | -13.0 ms |
| small | nochange | 0.0730 [0.070-0.075] | 0.0610 [0.059-0.062] | -12.0 ms |
| small | body-inventory | 0.1255 [0.122-0.129] | 0.1140 [0.112-0.117] | -11.5 ms |
| small | pubfn-model | 0.1265 [0.125-0.129] | 0.1140 [0.112-0.117] | -12.5 ms |
| small | run-body-inventory | 0.1260 [0.124-0.130] | 0.1140 [0.112-0.118] | -12.0 ms |

- Each small row is 11.5-12.5 ms faster, the 7 ms of the client's shell and
  the 5 ms of the child's; each run's small medians do not overlap the other
  binary's.
- No row is slower beyond its spread. body-typecheck is 3.5 ms slower at the
  median, inside a 48 ms range that both binaries share; the other cli rows
  move by less than their spread.

Closed to other users. A client sends the daemon its env, and the daemon
builds and runs what it is sent, so no other user may reach its socket. The
daemon makes `.blink/` and each worker directory `0700`, also one that
existed before with a looser mode, and each socket `0600`, and does not start
when it cannot. Only the daemon uses the project's `.blink/`, so a group that
shares a project loses nothing by it. On Linux x86_64 and aarch64, where the
`SOL_SOCKET` and `SO_PEERCRED` values were checked against the C headers, the
daemon also asks the kernel for the uid at the other end of each connection
it accepts and closes one of another user unread, and the client sends a
request (with its env) only to a socket whose peer is its own user. The FFI
cannot read a C macro, so on another arch the peer check is off, the client
sends hashes in place of its env, and the closed directory alone keeps others
out.

### Any entry of the project

Before this change, the daemon served only the entry it started on, as typed
from the directory it started in. A check of `./src/cli.bl`, of its absolute
path, or of `../src/cli.bl` from `tests/` ran cold, and so did a check or
build of a second entry such as `examples/calculator.bl`.

The daemon is now a router and a set of workers:

- The router runs no front end. It keys each check, build or run by the
  entry's real path (`realpath(3)` of the client's directory and the path as
  typed). A symbolic link to an entry, and a path through a linked
  directory, give the key of the target, so they go to the same worker. Two
  files never share a real path, so never a key. A path that `realpath`
  cannot resolve, such as a missing file, falls back to the absolute path
  with no `.`, `..` or empty parts.
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
  the nearest `blink.toml`) or below it. It compares the key above with the
  real path of the root, so a link in the project to a file outside it is
  outside. A file outside the root can be part of another project, so its
  check or build runs cold. The entry that the daemon started on is served
  wherever it is.
- Builds of two entries do not run at the same time, as with two builds of
  one entry. Each build uses all the cores it can get, and the daemon keeps
  its one rule for builds. The router holds one build turn for all workers:
  - Before the fork, the router connects to the new worker's socket. The
    worker's first accept is that connection, its channel to the router.
    The worker only writes on it (`{"type":"turn"}` to ask, then
    `{"type":"done","more":0|1}`), and the router only reads, so neither
    waits on the other. The router waits with `poll` on its socket and all
    channels.
  - A worker queues each build and asks for the turn. The router gives the
    turn to the oldest asker: it connects to the worker's socket and sends
    `{"type":"turn"}`. The worker runs its oldest build. When the build
    child ends, the worker sends `done`, with `more` 1 when it has more
    builds. Such a worker goes to the end of the queue, so a turn is one
    build, and two workers with many builds take turns.
  - `blink daemon status` gives `building` 1 for the build that holds the
    turn and `queued` for each build that waits, in any worker.
  - A stop waits for the build that holds the turn, as above. Each worker
    then sends its queued builds cold, replies to the stop and exits.
  - A worker that ends while it holds the turn frees it only once its build
    child, and each process that child started, is gone (see below).
- The router refuses a build from a client with another identity or other
  front-end settings before it routes the build. The client builds cold, and
  the router forks no worker for it. The worker does the same check again. A
  check request carries no identity, before and after this change.
- Each worker leads a process group of its own, which its build child and
  each cc and ld that child starts join. When a worker ends without a stop
  (killed or crashed), the router sees its channel close, kills the group
  with `SIGKILL`, and serves the next request for that entry from a new
  worker. The kill comes before the reap, so the worker's pid, which names
  the group, can name no other process. The router reaps the worker, and
  removes its directory, once no process of the group is left, and only then
  frees the turn if the worker held it. So no process of the dead worker
  writes beside the next build through the daemon. A process of the group
  that the router does not parent is reaped by init; if none reaps it, the
  group counts as gone 10 s after the kill, since a killed process writes
  nothing.
- A client whose request was in that worker gets no reply and runs cold. Its
  cold build does not take the turn, so it can write the same outputs as the
  killed build child until the kill lands, as when a daemon is killed
  mid-build (above).
- When the router itself is killed, no turn is granted again, so no build
  through that daemon starts. Each worker sees that its router is gone, ends
  after its build child, and holds its clients until then. A new daemon that
  starts in that time can build an entry beside a build child of an old
  worker.
- Since a worker leads its own group, a signal sent to the router's group
  (by `kill` to a negative pid, or a Ctrl-C at a terminal) does not reach the
  workers; each ends when it sees its router gone.
- `blink daemon status` gives `entries` (the workers that serve) after
  `stopping`. `builds` and `checks` are the sums over all workers, also the
  workers the router stopped.

A script runs each case 5 times, on the gen1 `blink` built from `27b9888e`
(before, sha256 `3338425dccf667b8`) and then from `a3f7dfe1` (after, sha256
`608aa9a78b7b7a2d`), back to back under `blink-gates.slice`, in a copy of the
`a3f7dfe1` tree. `calc` is `examples/calculator.bl`. "settle1" waits 1 s
between the edit and the command. Median wall seconds [min-max].
`bench/edit_loop/daemon_any_entry_turn_27b9888e.tsv` and
`bench/edit_loop/daemon_any_entry_turn_a3f7dfe1.tsv` hold the rows.

| case | before | after |
|---|---|---|
| cold check `src/cli.bl` | 0.387 [0.379-0.388] | 0.384 [0.375-0.388] |
| daemon check `src/cli.bl`, no change | 0.008 [0.007-0.010] | 0.008 [0.008-0.011] |
| daemon check `src/cli.bl`, edit, no settle | 0.407 [0.403-0.411] | 0.404 [0.403-0.411] |
| daemon check `src/cli.bl`, edit, settle1 | 0.008 [0.008-0.012] | 0.008 [0.008-0.013] |
| daemon build `src/cli.bl`, body edit, settle1 | 0.586 [0.559-0.604] | 0.585 [0.567-0.608] |
| daemon check `./src/cli.bl` | 0.387 [0.386-0.392] | 0.008 [0.008-0.427] |
| daemon check absolute `src/cli.bl` | 0.391 [0.386-0.392] | 0.008 [0.008-0.416] |
| daemon check `../src/cli.bl` from `tests/` | 0.383 [0.379-0.392] | 0.008 [0.008-0.422] |
| cold check calc | 0.010 [0.010-0.011] | 0.011 [0.010-0.011] |
| daemon check calc, no change | 0.011 [0.010-0.011] | 0.002 [0.002-0.002] |
| daemon check calc, edit, settle1 | 0.010 [0.010-0.011] | 0.003 [0.002-0.003] |
| cold build calc, body edit | 0.152 [0.151-0.154] | 0.152 [0.151-0.153] |
| daemon build calc, body edit, settle1 | 0.163 [0.160-0.164] | 0.161 [0.158-0.163] |

- Each other spelling of `src/cli.bl` now gets its answer from the daemon.
  The max of each of those rows is the first check of a new spelling, which
  checks again.
- A check of calc through the daemon takes 2-3 ms, against 10-11 ms cold.
- A build of calc through the daemon gains nothing, as with the small target
  below: its front end is a few ms.

`task bench-edit-loop` with `BENCH_DAEMON=1 BENCH_SETTLE=1`, 5 reps, 12 cores,
under `blink-gates.slice`, back to back on the `a3f7dfe1` tree, on the same two
binaries: before from `27b9888e`, after from `a3f7dfe1`. The daemon served 30
builds on cli and 25 on small for each. Median wall seconds [min-max].
`per_module_daemon_settle1_turn_27b9888e.tsv` and
`per_module_daemon_settle1_turn_a3f7dfe1.tsv` hold the rows.

| target | case | before | after |
|---|---|---|---|
| cli | nochange | 0.181 [0.179-0.184] | 0.190 [0.190-0.198] |
| cli | body-cname | 0.554 [0.519-0.569] | 0.547 [0.525-0.581] |
| cli | body-typecheck | 2.871 [2.865-2.897] | 2.921 [2.888-2.936] |
| cli | pubfn-cname | 1.675 [1.632-1.676] | 1.740 [1.711-1.774] |
| cli | run-body-cname | 0.579 [0.571-0.920] | 0.596 [0.576-0.997] |
| cli | test-body-cname | 0.478 [0.475-0.482] | 0.479 [0.475-0.486] |
| cli | cold-obj | 3.420 [3.411-3.559] | 3.402 [3.385-3.529] |
| cli | cold-all | 6.050 [6.039-6.065] | 6.044 [6.029-6.046] |
| small | nochange | 0.072 [0.070-0.074] | 0.073 [0.072-0.074] |
| small | body-inventory | 0.127 [0.124-0.129] | 0.132 [0.128-0.133] |
| small | pubfn-model | 0.129 [0.128-0.131] | 0.134 [0.132-0.136] |
| small | run-body-inventory | 0.129 [0.127-0.129] | 0.136 [0.133-0.137] |
| small | test-body-inventory | 0.139 [0.137-0.141] | 0.138 [0.137-0.142] |
| small | cold-obj | 0.130 [0.127-0.133] | 0.138 [0.137-0.140] |

- In this run, cli nochange and pubfn-cname after are out of the spread of
  their before rows. Four more cli runs, after, before, after, before, do not
  show it: nochange 0.186, 0.183, 0.188, 0.188; body-typecheck 2.900, 2.883,
  2.889, 2.900; pubfn-cname 1.670, 1.670, 1.682, 1.704
  (`per_module_daemon_settle1_cli_alt_run<n>_<sha>.tsv`). pubfn-cname alone
  gives 1.603, 1.596, 1.607 and 1.601 against before
  (`per_module_daemon_settle1_pubfn_vs_before_run<n>_<sha>.tsv`), and 1.614,
  1.605, 1.610 and 1.611 against the redirect `b9c2f852`, so the build turn
  adds no time to it (`per_module_daemon_settle1_pubfn_vs_redirect_run<n>_<sha>.tsv`).
  The rows of the redirect `b9c2f852` against `27b9888e` are in
  `per_module_daemon_settle1_{27b9888e,b9c2f852}.tsv` and
  `daemon_any_entry_{27b9888e,b9c2f852}.tsv`.
- The small rows after an edit are 4-12 ms slower, out of the spread of
  their before rows. Not all of it is noise. In 4 small runs of 11 reps,
  after, before, after, before, body-inventory is 0.133, 0.126, 0.133 and
  0.127, and cold-obj is 0.136, 0.126, 0.136 and 0.126; nochange and
  test-body-inventory do not change
  (`per_module_daemon_settle1_small_reps11_alt_run<n>_<sha>.tsv`). All of the
  gap is in `emit_s`, the time before cc starts.
- The gap comes from the split into a router and a worker, not from the
  redirect. In 8 runs, the gen1 `blink` built from `799b05b3` (a relay
  process), `bb914b25` (a relay process, identity check in the router) and
  `b9c2f852` (the redirect) all give body-inventory 0.131-0.133 and cold-obj
  0.132-0.133, against 0.128-0.129 and 0.127 before
  (`per_module_daemon_settle1_small_bisect_run<n>_<sha>.tsv`).
- With `GC_MARKERS=1` (no GC marker threads), the gap goes away:
  body-inventory is 0.130 and 0.129 after, 0.128 and 0.129 before, and
  cold-obj is 0.130 and 0.130 after, 0.129 and 0.130 before
  (`per_module_daemon_settle1_small_gcmarkers1_run<n>_<sha>.tsv`). The cause
  in the GC is not found. The router and the worker do no GC collection in
  these runs, and a start of the marker threads in the build child made the
  rows slower.
- Without the GC marker threads in the worker (the gen1 `blink` built from
  `75c8dc00`), the small rows were 4-8 ms slower than before after edits.
  In 4 small runs of 11 reps, after, before, after, before, cold-obj was
  0.137, 0.130, 0.138 and 0.129. With the marker threads (`799b05b3`), it is
  0.135, 0.129, 0.129 and 0.126
  (`per_module_daemon_settle1_small_reps11_run<n>_<sha>.tsv`). The marker
  threads make the gap smaller, but the bisect above shows that `799b05b3`
  is still slower than before.

The cause is in when the GC collects. Each check leaves its whole working
set as garbage, and every build child is a fork of the worker heap, so the
child pays for the garbage it carries (page tables, and a bigger heap for
its own GC). Before the split, the second check of the worker collected
twice and the heap stayed at 7.7 MB. After the split, the allocations before
the first check differ a little, and the GC grew the heap in the second check
in place of a collection, so each fork carried about 7 MB more: forks at
14.4, 22.8, 31.2 and 39.6 MB, against 7.7, 15.6, 24.0 and 32.4 before. The
build child's RSS was 56 MB against 39, with no more page faults and no lost
huge pages. A build child forked straight from the router, without the
worker fork or the turn, was as slow as the split, and a worker without the
marker restart was too, so the depth of the fork and the markers are not the
cause.

The worker now calls `GC_gcollect` at the end of each check, so each fork
carries the live check and no garbage. On the small target the collection
takes under 1 ms, and the check 13-15 ms as before. A worker that starts by
exec of the same binary, with a fresh heap, would not help: it does the same
checks and leaves the same garbage.

Five runs back to back, 11 reps, under `blink-gates.slice`: base is the gen1
`blink` built from `27b9888e` (sha256 `3338425dccf667b8`), split from
`2ff0322f` (`608aa9a78b7b7a2d`), and fix from `29bc8bd0`
(`99a0e35b4ba94c2e`), in the order base, split, fix, base, fix. Median wall
seconds. `bench/edit_loop/daemon_worker_gc_after_check_run<n>_<sha>.tsv`
holds the rows.

| target | case | base | base | split | fix | fix |
|---|---|---|---|---|---|---|
| cli | nochange | 0.190 | 0.184 | 0.183 | 0.187 | 0.192 |
| cli | body-cname | 0.561 | 0.570 | 0.566 | 0.557 | 0.562 |
| cli | body-typecheck | 2.914 | 2.943 | 2.924 | 2.931 | 2.934 |
| cli | pubfn-cname | 1.705 | 1.769 | 1.687 | 1.713 | 1.694 |
| cli | run-body-cname | 0.591 | 0.608 | 0.665 | 0.593 | 0.592 |
| cli | test-body-cname | 0.486 | 0.484 | 0.480 | 0.486 | 0.480 |
| cli | cold-obj | 3.565 | 3.433 | 3.501 | 3.426 | 3.427 |
| cli | cold-all | 6.066 | 6.070 | 6.072 | 6.096 | 6.054 |
| small | nochange | 0.073 | 0.072 | 0.074 | 0.074 | 0.074 |
| small | body-inventory | 0.131 | 0.130 | 0.131 | 0.128 | 0.127 |
| small | pubfn-model | 0.132 | 0.132 | 0.137 | 0.127 | 0.127 |
| small | run-body-inventory | 0.131 | 0.132 | 0.137 | 0.127 | 0.127 |
| small | test-body-inventory | 0.138 | 0.138 | 0.139 | 0.138 | 0.139 |
| small | cold-obj | 0.130 | 0.131 | 0.137 | 0.126 | 0.127 |

- No fix row is slower than base beyond the spread of base. The small rows
  after an edit are 3-5 ms faster than base, except test-body-inventory,
  which does not change.
- In the first fix run, one rep of small nochange took 1.012 s. The second
  fix run did not repeat it (max 0.075).

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

### Large units in chunks

A body edit compiles one unit, and the time follows the size of that
unit. On cli, `typecheck.c` is 2.2 MB and takes cc about 2.4 s, so a
body edit there took 2.9 s through the daemon where one in `cname.bl`
took 0.54 s. Now the build cuts the unit of a large module into files
that cc compiles and caches one at a time (`generate_module_chunks_with`
in `src/cg.bl`):

- **The cut.** `BLINK_UNIT_CHUNK_DECLS` (default 32, written T here) is
  the target size of a chunk, in decls (functions and methods). A module
  of no more than 16·T decls (512) is not cut: cc cannot inline across a
  cut, and only a module past that size costs seconds of cc on each edit.
  In a cut module, a chunk ends before a decl whose name hashes (32-bit
  FNV-1a) to 0 modulo T once the chunk holds T/2 decls (16), and before
  any decl once it holds 4·T (128). The cut depends on the names near it,
  not on a count from the start, so a decl added or removed changes its
  own chunk and seldom the next. `0` cuts nothing. A release build cuts
  nothing, so cc sees each module whole. The value is an input of the
  emit record (`unit_chunk_decls`), and each chunk is an obj-cache entry
  whose key covers its own text. It is for tests and measurement; no CLI
  flag sets it.
- **The files.** The head, `<module>.c`, holds the globals, the init
  function and the first chunk of decls; each other chunk is
  `<module>.p<hex8>.c`, named by the hash of its first decl. Each chunk
  is emitted from a clean state, so its text depends only on its own
  decls. Each file has its own copy of the file-local helpers its bodies
  need. On cli only `typecheck` is over the bar: a head (47 KB), 16 chunks
  (15 KB to 333 KB) and `typecheck.pos.c`. `__main__.c` (2.6 MB, 0.70 s
  of cc) is one file: the cut is by decl count, and `__main__` is under
  the bar.
- **Lines.** A panic, an assert or a trace event names a line. In a cut
  unit each file reads its lines from a table of its own,
  `__blink_pos_<module>_<suffix>`, which `<module>.pos.c` defines. A line
  added above a function moves the numbers in the table, not the text of
  the chunk, so the edit compiles the edited chunk and `pos.c`, which
  holds only numbers. A column does not need a table: a line added above
  does not move it. A send on a closed channel formats its message at run
  time, only when it panics (`blink_channel_send_value_at`). The build
  writes no `#line`, so `--debug` adds no other line to the text.

What the cut costs and saves:

- A body edit in `typecheck.bl` compiles one chunk (0.06 s of cc, the
  largest chunk 0.38 s) in place of the whole unit (2.4 s).
- A decl added to the module changed the private header
  `typecheck.priv.h`, which every file of the unit and `__main__.c`
  included, so all 18 recompiled. Now each chunk holds only the
  declarations it names (see "Unit headers"), so only the chunks whose
  text changed recompile (see the bench below). The text of the other chunks does not
  change: a private fn added in the middle of `typecheck.bl` changed the
  text of its own chunk, `typecheck.pos.c` and `typecheck.priv.h`. Its
  name hashed to a cut, so the chunk before it lost a few decls too.
- Run time: the compiler (`check src/cli.bl`, 7 interleaved reps,
  `setarch -R`), unsplit against split at the default T, median 419.02 ms
  against 421.14 ms (+0.5%; instructions +0.1%). A user module of 600
  one-line fns whose hot loop calls 9 fns that sit in other chunks is the
  worst case: 659.24 ms against 768.92 ms (+16.6%; instructions 9.10 G
  against 9.50 G), since cc can no longer inline those calls. A
  `--release` build does not cut.

`task bench-edit-loop` on the gen1 `blink` of `c58722c2` (before) and of
`803d7eac` (after), 11 reps, 12 cores, under `blink-gates.slice`,
alternating before, after, before, after on the `10a3db88` tree. The
`pubfn-typecheck` and `privfn-typecheck` cases are new: a pub fn, or a
private fn, appended to `src/typecheck.bl`. The `unit_chunk_*` files in
`bench/edit_loop/` hold the rows. Median wall seconds of the two runs of
each binary, with the number of cc calls:

| target | case | before | after | daemon before | daemon after | cc before | cc after |
|---|---|---|---|---|---|---|---|
| cli | nochange | | | 0.176 / 0.174 | 0.182 / 0.179 | 0 | 0 |
| cli | body-cname | | | 0.536 / 0.554 | 0.539 / 0.540 | 1 | 1 |
| cli | body-typecheck | 3.108 / 3.103 | 0.784 / 0.781 | 2.913 / 2.920 | 0.590 / 0.577 | 1 | 1 |
| cli | pubfn-cname | | | 1.747 / 1.732 | 1.734 / 1.772 | 14 | 14 |
| cli | pubfn-typecheck | 3.611 / 3.624 | 2.213 / 2.206 | 3.541 / 3.527 | 2.132 / 2.147 | 21 | 37 |
| cli | privfn-typecheck | 3.342 / 3.327 | 1.771 / 1.773 | 3.244 / 3.249 | 1.679 / 1.674 | 2 | 18 |
| cli | run-body-cname | | | 0.579 / 0.591 | 0.597 / 0.579 | 1 | 1 |
| cli | cold-obj | 3.680 / 3.687 | 2.558 / 2.559 | | | 50 | 67 |
| cli | cold-all | 6.058 / 6.079 | 4.941 / 4.932 | | | 51 | 68 |
| small | nochange | | | 0.060 / 0.060 | 0.060 / 0.060 | 0 | 0 |
| small | body-inventory | | | 0.113 / 0.114 | 0.113 / 0.114 | 1 | 1 |
| small | pubfn-model | | | 0.114 / 0.113 | 0.113 / 0.114 | 3 | 3 |
| small | run-body-inventory | | | 0.115 / 0.114 | 0.114 / 0.114 | 1 | 1 |
| small | cold-obj | 0.121 / 0.121 | 0.122 / 0.121 | | | 5 | 5 |

- A body edit in `typecheck.bl` builds in 0.59 s through the daemon, 2.3
  s under the before row, and as fast as one in `cname.bl`.
- A decl added to `typecheck.bl` recompiles the 18 files that include its
  private header, and still builds 1.4 to 1.6 s faster than before, since
  the 18 compile at once. Through the daemon it costs 1.09 s more than a
  body edit.
- `cold-obj` and `cold-all` gain 1.1 s: the largest unit no longer holds
  the build up.
- No other row is slower than before outside its spread.

### Declarations in the unit

Each unit holds the declarations it names in place of the module headers
(see "Unit headers"). `task bench-edit-loop` on the gen1 `blink` of
`4e9da0b8` (before, sha256 `e1f24e5e510510b6`) and of `6735be43` (after,
sha256 `97ea08fea26351de`), 11 reps, 12 cores, under
`blink-gates.slice`, before then after for each target and mode, on the
`6735be43` tree. The `inline_decls_*` files in `bench/edit_loop/` hold
the rows. Median wall seconds, with the number of cc calls:

| target | case | before | after | daemon before | daemon after | cc before | cc after |
|---|---|---|---|---|---|---|---|
| cli | nochange | 0.533 | 0.531 | 0.170 | 0.180 | 0 | 0 |
| cli | body-cname | 0.802 | 0.798 | 0.549 | 0.536 | 1 | 1 |
| cli | body-typecheck | 0.786 | 0.786 | 0.585 | 0.575 | 1 | 1 |
| cli | pubfn-cname | 1.874 | 1.107 | 1.754 | 0.985 | 14 | 1 |
| cli | privfn-cname | 1.631 | 1.109 | 1.490 | 0.974 | 2 | 1 |
| cli | pubfn-typecheck | 2.213 | 0.996 | 2.161 | 0.880 | 37 | 1 |
| cli | privfn-typecheck | 1.771 | 1.000 | 1.720 | 0.884 | 18 | 1 |
| cli | run-body-cname | 0.806 | 0.803 | 0.588 | 0.577 | 1 | 1 |
| cli | test-body-cname | 0.487 | 0.483 | 0.488 | 0.485 | 1 | 1 |
| cli | cold-obj | 2.552 | 2.560 | 2.304 | 2.308 | 67 | 67 |
| cli | cold-all | 4.943 | 4.940 | 4.955 | 4.960 | 68 | 68 |
| small | nochange | 0.070 | 0.071 | 0.060 | 0.060 | 0 | 0 |
| small | body-inventory | 0.119 | 0.119 | 0.112 | 0.114 | 1 | 1 |
| small | pubfn-model | 0.121 | 0.111 | 0.111 | 0.103 | 3 | 1 |
| small | privfn-model | 0.112 | 0.110 | 0.103 | 0.104 | 1 | 1 |
| small | run-body-inventory | 0.120 | 0.121 | 0.112 | 0.113 | 1 | 1 |
| small | test-body-inventory | 0.133 | 0.133 | 0.136 | 0.135 | 1 | 1 |
| small | cold-obj | 0.121 | 0.121 | 0.110 | 0.111 | 5 | 5 |

- A new fn, pub or private, compiles one file: the unit, or in a cut
  module the chunk, whose text changed.
- Through the daemon a new fn still costs about 0.45 s (cname) and 0.3 s
  (typecheck) more than a body edit. All of it is emit (`emit_s` 0.79 s
  against 0.34 s and 0.47 s): a changed module header stops the build
  from keeping the last build's units, so it emits each unit again. The
  cc time is the same as a body edit's.
- No other row is slower than before outside its spread.

The scan that reads whole identifiers outside strings and comments, and the
`-Werror=implicit-function-declaration` flag, came after. The gen1 `blink`
of `d4dd6cb4` (sha256 `8c19d135eb12dd4d`), same reps and slice, on the
`d4dd6cb4` tree, in its own run after the one above; the `run3_d4dd6cb4`
files hold the rows. Median wall seconds against `6735be43`:

| target | case | 6735be43 | d4dd6cb4 | daemon 6735be43 | daemon d4dd6cb4 | cc |
|---|---|---|---|---|---|---|
| cli | nochange | 0.531 | 0.530 | 0.180 | 0.175 | 0 |
| cli | body-cname | 0.798 | 0.801 | 0.536 | 0.559 | 1 |
| cli | body-typecheck | 0.786 | 0.795 | 0.575 | 0.591 | 1 |
| cli | pubfn-cname | 1.107 | 1.120 | 0.985 | 0.990 | 1 |
| cli | privfn-cname | 1.109 | 1.125 | 0.974 | 1.006 | 1 |
| cli | pubfn-typecheck | 0.996 | 1.026 | 0.880 | 0.908 | 1 |
| cli | privfn-typecheck | 1.000 | 1.029 | 0.884 | 0.914 | 1 |
| cli | run-body-cname | 0.803 | 0.807 | 0.577 | 0.584 | 1 |
| cli | test-body-cname | 0.483 | 0.485 | 0.485 | 0.487 | 1 |
| cli | cold-obj | 2.560 | 2.558 | 2.308 | 2.313 | 67 |
| cli | cold-all | 4.940 | 4.950 | 4.960 | 4.959 | 68 |
| small | nochange | 0.071 | 0.072 | 0.060 | 0.061 | 0 |
| small | body-inventory | 0.119 | 0.119 | 0.114 | 0.113 | 1 |
| small | pubfn-model | 0.111 | 0.111 | 0.103 | 0.105 | 1 |
| small | privfn-model | 0.110 | 0.112 | 0.104 | 0.105 | 1 |
| small | run-body-inventory | 0.121 | 0.120 | 0.113 | 0.113 | 1 |
| small | test-body-inventory | 0.133 | 0.135 | 0.135 | 0.134 | 1 |
| small | cold-obj | 0.121 | 0.120 | 0.111 | 0.110 | 5 |

The cc calls did not change. A new fn costs about 0.03 s more, all of it
in `emit_s`: the scan reads each unit one byte at a time. The `cold-obj`
and `cold-all` rows did not change, so the flag costs cc nothing.

A build with no shell. A daemon build child of the small target started 44
programs past the C toolchain for one body edit (strace): 18 `sh`, 5 `rm`,
4 `sha256sum`, 3 `mkdir`, 3 `xargs`, 2 `mv`, and `awk`, `cat`, `cut`,
`date`, `du`, `head`, `mktemp`, `nproc` and `touch` once each. It now
hashes its units and keys in process (`src/sha256.bl`), makes, removes and renames its directories and
touches its cache entries in process (`src/build_fs.bl`), and starts `cc` and
the link with no `sh` when the command holds no byte `sh` would read as more
than a word break. It sums the cache's size in process too, from the
apparent bytes of its files, where `du` gave the blocks they take (see
`per-module-o-cache.md`). A file over 1 MiB is
hashed by `sha256sum`, run with no shell. The keys are the same bytes
`sha256sum` gave, so a cache on disk still hits. The cache GC, past its cap,
still lists by age in `sh`. The `82c21d3a` binary below linked the units it
took from a record with one `ln`; the build now makes each link with
`link(2)`. The table below was measured before the `du` went; that change
took one more exec off the child.

`task bench-edit-loop` with `BENCH_DAEMON=1 BENCH_SETTLE=1`, 11 reps, under
`blink-gates.slice`, on the `82c21d3a` tree, alternating the gen1 `blink`
built from `90a4d660` (before, sha256 `8c19d135eb12dd4d`) and from
`82c21d3a` (after, sha256 `d980d20f054d2320`): before, after, before, after,
per target. Median wall seconds [min-max] over the 22 builds of both runs
of a binary; `emit` is the change in the median `emit_s`.
`no_shell_daemon_settle1_<target>_run<n>_<sha>.tsv` hold the rows. Load1 was
at most 3.05.

| target | case | before | after | change | emit |
|---|---|---|---|---|---|
| cli | nochange | 0.1780 [0.171-0.190] | 0.1440 [0.137-0.154] | -34.0 ms | -33.0 ms |
| cli | body-cname | 0.5460 [0.521-0.591] | 0.4985 [0.461-0.528] | -47.5 ms | -46.0 ms |
| cli | body-typecheck | 0.6050 [0.578-0.626] | 0.5340 [0.513-0.551] | -71.0 ms | -72.0 ms |
| cli | pubfn-cname | 1.0090 [0.987-1.043] | 0.9275 [0.900-0.954] | -81.5 ms | -81.5 ms |
| cli | privfn-cname | 1.0110 [0.992-1.043] | 0.9270 [0.913-0.951] | -84.0 ms | -86.0 ms |
| cli | pubfn-typecheck | 0.9080 [0.886-0.936] | 0.8210 [0.797-0.856] | -87.0 ms | -89.0 ms |
| cli | privfn-typecheck | 0.9375 [0.896-0.962] | 0.8365 [0.810-0.857] | -101.0 ms | -100.0 ms |
| cli | run-body-cname | 0.6030 [0.587-1.060] | 0.5215 [0.503-0.946] | -81.5 ms | -80.0 ms |
| cli | test-body-cname | 0.4860 [0.480-0.493] | 0.4570 [0.450-0.464] | -29.0 ms | -30.0 ms |
| cli | cold-obj | 2.3705 [2.351-2.554] | 2.2475 [2.229-2.452] | -123.0 ms | -117.0 ms |
| cli | cold-all | 4.9980 [4.975-5.027] | 4.9055 [4.876-4.923] | -92.5 ms | -83.5 ms |
| small | nochange | 0.0600 [0.058-0.062] | 0.0440 [0.041-0.048] | -16.0 ms | -16.5 ms |
| small | body-inventory | 0.1130 [0.110-0.115] | 0.0900 [0.087-0.093] | -23.0 ms | -23.0 ms |
| small | pubfn-model | 0.1040 [0.102-0.107] | 0.0810 [0.078-0.085] | -23.0 ms | -24.0 ms |
| small | privfn-model | 0.1045 [0.100-0.107] | 0.0810 [0.078-0.084] | -23.5 ms | -24.0 ms |
| small | run-body-inventory | 0.1130 [0.111-0.117] | 0.0910 [0.087-0.094] | -22.0 ms | -22.0 ms |
| small | test-body-inventory | 0.1350 [0.132-0.138] | 0.1170 [0.114-0.119] | -18.0 ms | -19.0 ms |
| small | cold-obj | 0.1110 [0.109-0.117] | 0.0860 [0.082-0.094] | -25.0 ms | -24.5 ms |

- Each row is faster, and the time comes out of `emit_s`; the `cc_s` and
  `link_s` medians and the cc calls did not change. No small row's range
  overlaps the other binary's.
- A small body edit drops 22-23 ms, about 40% of its `emit_s`. The cli rows
  drop 29-123 ms.
- The C of each build matches the warm C in every row (`c_check`).

### Units and headers kept across a fn edit

Before this change, a changed module header stopped the build from taking
any unit of the last build, and every header was written again. A new
fn on cli emitted all 52 units (0.45 s of emit) and wrote 0.05 s of
headers that had the same text as before. Now a build takes each unit
that the edit cannot reach and keeps each header whose inputs did not
change.

The delta (`src/emit_record.bl`):

- Each top-level item in a source's interface text starts with a mark of
  its kind: `fn <name>`, `import` or `other`. The build compares the old
  and new items of each source as a multiset, with comments dropped.
- A changed plain fn adds its name to the edited names. A changed
  `import` adds nothing. A change to any other item, or to a field of the
  inputs that is not the sources' own, makes the build take nothing.
- The hit sources are those whose old or new text names an edited fn as
  a whole word.
- The types header must have the same text, and the module headers must
  come in the same order. Each changed module header gives the names it
  declares that were added or removed. Past 64 such names the build takes
  nothing.
- A unit is taken only when the texts of the sources it reads are the
  same, none of them is a hit, its own headers have the same text, it
  includes no changed header whole, and its C names none of the changed
  names. Its files are then linked in and their sha256 checked against the
  record.
- A module's headers are kept when the key of its inputs is the same and
  none of its sources changed or is a hit. The key is the sha256 of the
  types header and the C names of the instances the module homes, in
  order. A header with the same text as the last one is linked, not
  written, so its inode and mtime do not change.

#### Program-wide numbering

A unit's C reads tables and counters that the whole program shares. A
new fn can move an entry in such a table. Each one is in one of these
groups:

(a) Reset for each unit. `begin_unit` calls `reset_unit_state`, and
`cg_reg_build` makes the registry again:

- `c_mint_seq`, the counter in each closure and fn-value symbol;
- the emit temp counter and the print state (`materialized`,
  `guard_support_done`);
- the effect thunks, the derive and tuple-method marks, the promote
  state, the typedef and vtable state, the foreign declarations and the
  layout state.

(b) Named from content, so a fn-only delta cannot move a name:

- the instance and type names (`c_mono_fn_name`, `c_poly_method_name`,
  `c_mono_type_c_name`, `c_typedef_name`, `c_values_eq_name`, the closure
  walker names) come from the spelling of the types;
- an effect's field is `ue_<root>` and its default op is named from the
  root and the op;
- a key table has the name `layout` gives the key type (`kops_table`).
  Only `__main__` defines the tables, and other units declare them by that
  name;
- string literals are written in the unit that uses them;
- no tid or node id reaches the C text, and private copies are sorted by
  C name;
- the order of `reg_fns` and `mono_table` moves when a fn is added in
  another module, but the order of the entries of one module does not.

(c) A shift changes a text the build compares:

- the order of the instance table reaches the module's headers and its
  unit. The header key holds the instance names in order, and a unit is
  taken only when its own headers have the same text;
- the carrier typedefs, the effect-vector typedef, the derive
  declarations and the tuple types are in the types header, which the
  build compares byte for byte. A new tuple type therefore makes the
  build take nothing;
- the preamble marks come from the same walk as the types header;
- `program_spawns`, the test table and every key table reach only
  `__main__`, which the build emits each time.

An entry that is in none of these groups makes the build take nothing.

A source that declares an effect is read by every unit, so an edit there
emits every unit again. This was so before this change.

## Blockers before the default flipped

None from the edit-loop bench: `nochange` on cli is faster than the
monolith, and no per-module case is slower than before outside its spread.
