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
  ran at once whatever `--jobs` said. The build reaps whichever child
  ends first and starts the next unit in its slot. Each child writes its
  output to files in the obj dir, so no child waits on a full pipe. The
  build prints the output and the error lines in unit order, not in the
  order the children end. "Units that end out of order" below gives the
  design.
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
  compiles to an object in the build's own dir, the build links that
  object, and the cache gets a hard link (or a copy) of it. A hit is
  hard-linked into the build's hold dir, and the build links that name.
  So the GC of another build cannot remove an object this build is about
  to link (section 5 of `per-module-o-cache.md`).
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
  taken unit again. Each unit the build does not take is emitted.
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
shares a project loses nothing by it. The daemon also asks the kernel for the
uid at the other end of each connection it accepts and closes one of another
user unread, and the client sends a request (with its env) only to a socket,
router or worker, whose peer is its own user. The runtime helper
`blink_unix_socket_peer_uid` asks with `SO_PEERCRED` on Linux, any arch, and
with `getpeereid` on macOS, FreeBSD, OpenBSD, NetBSD and DragonFly; the C
compiler picks the call from the target's platform macros. When the call
fails, the daemon and the client refuse that peer. On any other platform the
helper says the check is not supported: the daemon then serves each
connection and the client sends to each socket, so the closed directory alone
keeps others out there. The client sends its env, not hashes, only where the
check is supported and /proc names its compiler and env, so on Linux.

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
  its kind: `fn <name>`, `let <name>`, `const <name>`, `test`, `import`
  or `other`. The build compares the old and new items of each source as
  a multiset, with comments dropped.
- A changed plain fn, global or const adds its name to the edited names.
  A changed `import` or `test` adds nothing. A change to any other item,
  or to a field of the inputs that is not the sources' own, makes the
  build take nothing.
- The hit sources are those whose old or new text names an edited name
  as a whole word.
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
- A kept header is linked in without a hash. The build checks it against
  the record when it hashes the units directory, as it does for the files
  of a taken unit, so no header is hashed twice. When a kept header does
  not match, every unit may declare what it held, so the build writes the
  headers and every unit again, as a build with no last build does.

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
- `program_spawns`, the test table, every key table and the init calls
  reach only `__main__`. The build takes `__main__` only when its entry
  key is the last build's (see "The entry unit across an edit").

An entry that is in none of these groups makes the build take nothing.

A source that declares an effect with an operation was read by every
unit, so an edit there emitted every unit again. "Units kept across a
body edit beside an effect" removes that.

#### What `__main__` reads

`emit_module_head` writes `__main__` from the parts below, sorted into
the same groups.

(a) Reset for each unit:

- `__main__` starts from `begin_unit`, as every unit does;
- `program_facts` finds the init names before the build emits a unit. It
  lowers the globals of every module, throws the lowering away, and calls
  `begin_unit` again. The `__main__` emit therefore lowers no code of
  another module, and no closure, walker or typedef of that lowering can
  reach its text.

(b) Named from content:

- the key tables (`kops_table`, from the key type);
- the effect fields `ue_<root>` and the default ops;
- the init calls, `__blink_init_globals_<module>`;
- the C symbol of each test.

(c) Compared or keyed:

- the evidence storage: the vtable typedef, the default and the `ue_`
  field of each effect. A new or changed effect is an item other than a
  fn or an import, so the build takes nothing. The vtable typedef is in
  the types header, and the default bodies mark no source;
- its own globals and their init fn, from its own source;
- the init calls. A global of another module that changes between a
  constant and a run-time initializer adds or removes a call. The `init`
  lines of the entry key hold the names, so the build emits `__main__`
  again;
- `main`, spawns, tests and key table names: the entry key;
- a new key type: the types header;
- the eq and hash of each key table, lowered with the span of the node
  the table is written from: the unit marks that node's source, and the
  entry key holds it (`table_source`);
- the generic private copies it prints: their nodes mark their sources;
- `cfg`: the inputs text.

A test in an imported module does not reach `__main__`: `blink test`
builds each file with its own tests as the entry. The build takes
`__main__` and each unit the test does not reach.

One edit emits `__main__` again with the same text. A second Map with a
key type that a Map in an earlier source already has moves the node the
table is written from. This costs one emit of `__main__`, and the build
is byte-equal to a cold build.

#### Bench

Through the daemon, settle 1 s, 11 reps, median seconds (min-max). Base
and the change ran in turn: base, change, base, change. Base is gen1 of
`03b99f0f` (sha256 `72ed7e2f…`), the change is gen1 of `0af15486`
(sha256 `4d9d9460…`). `bench/edit_loop/unit_reuse_daemon_settle1_*.tsv`
hold the full rows.

| target | case | base run 1 | change run 2 | base run 3 | change run 4 |
|---|---|---|---|---|---|
| cli | nochange | 0.139 (0.135-0.145) | 0.138 (0.134-0.156) | 0.139 (0.132-0.148) | 0.140 (0.134-0.152) |
| cli | body-cname | 0.487 (0.452-0.497) | 0.466 (0.444-0.475) | 0.490 (0.457-0.500) | 0.455 (0.447-0.470) |
| cli | body-typecheck | 0.523 (0.505-0.533) | 0.503 (0.493-0.512) | 0.512 (0.502-0.516) | 0.493 (0.485-0.499) |
| cli | pubfn-cname | 0.934 (0.926-0.942) | 0.496 (0.492-0.610) | 0.906 (0.891-0.932) | 0.491 (0.481-0.585) |
| cli | privfn-cname | 0.938 (0.925-0.944) | 0.496 (0.487-0.502) | 0.928 (0.905-0.940) | 0.495 (0.484-0.503) |
| cli | pubfn-typecheck | 0.828 (0.814-0.841) | 0.513 (0.503-0.525) | 0.829 (0.810-0.840) | 0.512 (0.497-0.525) |
| cli | privfn-typecheck | 0.827 (0.821-0.842) | 0.520 (0.505-0.528) | 0.823 (0.813-0.830) | 0.515 (0.506-0.529) |
| cli | run-body-cname | 0.511 (0.506-0.925) | 0.487 (0.480-0.618) | 0.509 (0.494-0.921) | 0.486 (0.467-0.598) |
| cli | test-body-cname | 0.452 (0.448-0.455) | 0.449 (0.440-0.456) | 0.452 (0.447-0.461) | 0.448 (0.442-0.456) |
| cli | cold-obj | 2.246 (2.227-2.416) | 2.253 (2.243-2.400) | 2.241 (2.227-2.433) | 2.247 (2.227-2.397) |
| cli | cold-all | 4.932 (4.898-4.954) | 4.928 (4.906-4.963) | 4.929 (4.909-4.946) | 4.937 (4.927-4.966) |
| small | nochange | 0.042 (0.039-0.043) | 0.042 (0.040-0.044) | 0.044 (0.042-0.046) | 0.044 (0.042-0.045) |
| small | body-inventory | 0.087 (0.086-0.092) | 0.086 (0.083-0.090) | 0.088 (0.085-0.091) | 0.086 (0.085-0.087) |
| small | pubfn-model | 0.079 (0.077-0.084) | 0.078 (0.076-0.081) | 0.081 (0.077-0.083) | 0.078 (0.076-0.081) |
| small | privfn-model | 0.079 (0.077-0.081) | 0.079 (0.076-0.082) | 0.080 (0.076-0.082) | 0.078 (0.076-0.081) |
| small | run-body-inventory | 0.088 (0.086-0.091) | 0.087 (0.084-0.088) | 0.089 (0.085-0.092) | 0.088 (0.086-0.091) |
| small | test-body-inventory | 0.114 (0.112-0.115) | 0.114 (0.112-0.117) | 0.115 (0.113-0.118) | 0.113 (0.110-0.118) |
| small | cold-obj | 0.084 (0.080-0.087) | 0.083 (0.080-0.087) | 0.081 (0.079-0.088) | 0.082 (0.080-0.088) |

A new fn now costs about what a body edit costs: on cli the four fn rows
drop from 0.82-0.94 s to 0.49-0.52 s. The body rows drop by 19-35 ms,
about the time the headers took: 47-51 ms before, 21-28 ms now. No row is
slower outside its spread.

### The entry unit across an edit

Before this change, the build emitted `__main__` each time. On cli that
cost 63-69 ms of each body edit through the daemon: 53-59 ms to generate,
9 ms to splice, 1 ms to write a 2.66 MB file.

`__main__` could not be taken because its uses list held every source.
`module_init_fn_names` lowers the globals of every module to find the
modules with a global set at run time, and throws the lowering away.
That lowering ran in the `__main__` emit and marked each source as read
by the unit. It now runs in `program_facts`, before any unit, and also
stops the marks while it runs (`ir_sources_pause` and
`ir_sources_resume` in `src/ir.bl`). On cli the uses list of `__main__`
drops to `src/cli.bl` and `lib/std/list.bl`.

`__main__` also reads facts of the whole program that no source span
carries. The record keeps their sha256 in a line `entry <sha>` (schema
`emit-record-8`). The key is made of these lines, in order:

- `main <bool>` and `spawns <bool>` (`program_spawns`);
- `test <C symbol> <length> <name>` for each test;
- `table <name>` for each key table;
- `init <name>` for each init call of the shim;
- `table_source <path>` for the source of the node each key table is
  written from.

`take_units` checks `__main__` as it checks any unit. When it takes
`__main__`, the build makes the key again and drops the unit unless the
key is the record's. The trace then prints `skip unit __main__: the facts
of the whole program it reads differ`. A record with no entry line keeps
`__main__` from being taken.

Other checks also catch a change to the `test` and `table` lines. Only
the entry module's tests reach the program, so a new test changes the
entry source, which `__main__` reads. A new key type changes the types
header, so the build takes nothing.

`program_facts` finds the init names once, about 7 ms on cli. The
`__main__` emit calls them and the key holds them from that one list, so
the two cannot differ by how they were found.

Under `BLINK_EMIT_REUSE_VERIFY=1`, a unit that is not byte-equal to its
cold emit fails the build with the reason: each source the cold emit
read that the unit did not mark or, for `__main__` with no such source,
that the entry key leaves out a fact of the whole program. The error
also gives the first line that differs.

`hash_place` (27-32 ms) and the types header (about 10 ms) are not cut:
`hash_place` hashes `runtime.h`, `libblink_std.h` and each unit file the
link needs, and a taken file is checked against the record.

#### Bench

Through the daemon, settle 1 s, 11 reps, median seconds (min-max). Base
and the change ran in turn: base, change, base, change. Base is gen1 of
`5ec0de2e` (sha256 `4d9d9460…`), the change is gen1 of `ab1aed21`
(sha256 `e851cf84…`). `bench/edit_loop/unit_entry_daemon_settle1_*.tsv`
hold the full rows. Every C hash check reads 11/11.

| target | case | base run 1 | change run 2 | base run 3 | change run 4 |
|---|---|---|---|---|---|
| cli | nochange | 0.142 (0.136-0.155) | 0.140 (0.136-0.149) | 0.139 (0.135-0.154) | 0.143 (0.138-0.154) |
| cli | body-cname | 0.459 (0.447-0.474) | 0.418 (0.400-0.434) | 0.458 (0.431-0.483) | 0.414 (0.397-0.425) |
| cli | body-typecheck | 0.494 (0.473-0.503) | 0.453 (0.447-0.464) | 0.494 (0.480-0.505) | 0.452 (0.436-0.459) |
| cli | pubfn-cname | 0.496 (0.482-0.602) | 0.446 (0.429-0.565) | 0.481 (0.473-0.599) | 0.439 (0.429-0.561) |
| cli | privfn-cname | 0.492 (0.483-0.502) | 0.440 (0.427-0.451) | 0.485 (0.465-0.503) | 0.445 (0.431-0.462) |
| cli | pubfn-typecheck | 0.520 (0.510-0.533) | 0.469 (0.460-0.482) | 0.508 (0.501-0.529) | 0.470 (0.451-0.485) |
| cli | privfn-typecheck | 0.520 (0.499-0.529) | 0.471 (0.457-0.484) | 0.509 (0.502-0.519) | 0.469 (0.459-0.484) |
| cli | run-body-cname | 0.481 (0.471-0.626) | 0.446 (0.422-0.578) | 0.478 (0.464-0.624) | 0.426 (0.416-0.583) |
| cli | test-body-cname | 0.449 (0.442-0.454) | 0.452 (0.442-0.455) | 0.448 (0.445-0.458) | 0.448 (0.443-0.463) |
| cli | cold-obj | 2.265 (2.247-2.416) | 2.275 (2.253-2.375) | 2.245 (2.236-2.407) | 2.259 (2.228-2.334) |
| cli | cold-all | 4.948 (4.932-4.960) | 4.940 (4.918-4.952) | 4.921 (4.914-4.954) | 4.950 (4.931-4.989) |
| small | nochange | 0.044 (0.043-0.046) | 0.045 (0.042-0.046) | 0.044 (0.042-0.046) | 0.043 (0.041-0.045) |
| small | body-inventory | 0.086 (0.085-0.089) | 0.087 (0.084-0.090) | 0.085 (0.084-0.087) | 0.086 (0.084-0.088) |
| small | pubfn-model | 0.077 (0.075-0.081) | 0.077 (0.076-0.079) | 0.079 (0.076-0.082) | 0.080 (0.077-0.081) |
| small | privfn-model | 0.078 (0.076-0.080) | 0.078 (0.076-0.081) | 0.078 (0.076-0.080) | 0.078 (0.077-0.080) |
| small | run-body-inventory | 0.088 (0.086-0.090) | 0.087 (0.085-0.090) | 0.086 (0.084-0.089) | 0.088 (0.084-0.091) |
| small | test-body-inventory | 0.114 (0.112-0.119) | 0.113 (0.110-0.117) | 0.114 (0.112-0.116) | 0.114 (0.111-0.117) |
| small | cold-obj | 0.083 (0.080-0.086) | 0.084 (0.081-0.087) | 0.084 (0.079-0.089) | 0.082 (0.079-0.083) |

On cli the body and fn rows drop by 35-52 ms, which is most of the
63-69 ms `__main__` emit but not all. One part left is the init names,
which each build finds, about 7 ms on cli. small does not change: its
`__main__` costs 0-1 ms. `test-body-cname` does not change; this bench
does not split its emit. No row is slower outside its spread. An edit to
the entry file still emits `__main__`.

Finding the init names in `program_facts` instead of in the `__main__`
emit and the take path does not change an edit build. The same bench ran
`ab1aed21` (sha256 `e851cf84…`) and `a0b43999` (sha256 `3831bb98…`) in
turn, four runs. On the body, fn and nochange rows the medians differ by
22 ms at most, and not in one direction.
`cold-all` on cli reads 4.995 and 4.992 s for `ab1aed21`, 5.063 and
5.022 s for `a0b43999`: 30-70 ms slower, outside the spread in one of
the two runs. small does not change.
`bench/edit_loop/entry_facts_daemon_settle1_*.tsv` hold the full rows.

### Units kept across a global, const or test edit

Before this change, an edit in a module other than the entry that added,
removed or changed a global, a const or a test block made the build take
no unit: each was an item of kind `other`. On cli the build then emitted
all 69 units for a test block whose C reaches no unit.

Each kind, added once to `src/cname.bl` on cli under
`BLINK_EMIT_REUSE_VERIFY=1`: the units whose C changed against the last
build, and the median of 5 edits through the daemon, settle 1 s, with
the gen1 from before this change.

| kind | units changed | headers changed | median s |
|---|---|---|---|
| nochange | - | - | 0.139 |
| test block | 0 | 0 | 0.718 |
| constant global | 1 (`cname`) | `cname.priv.h` | 0.913 |
| run-time global | 1 (`cname`) | `cname.priv.h` | 0.942 |
| pub constant global | 1 (`cname`) | `cname.h` | 0.936 |
| global value changed | 1 (`cname`) | 0 | 0.774 |
| global made run-time | 1 (`cname`) | 0 | 0.785 |
| const | 1 (`cname`) | `cname.priv.h` | 0.975 |
| type | 14 | `blink.types.h` | 2.961 |
| alias | 14 | 0 | 0.808 |
| effect | 68 | `blink.types.h` | 3.091 |
| trait | 0 | 0 | 0.831 |
| impl | 15 | `blink.types.h`, `cname.h` | 3.050 |
| annotated fn | 1 (`cname`) | `cname.priv.h` | 1.009 |
| new private fn | 1 (`cname`) | `cname.priv.h` | 0.459 |

The alias changes 14 units only by the order of their extern lines.

A global or const reaches the C of other units by its name alone:

- `cg_decl_emit_globals` prints a constant initializer on the line that
  defines the global, in the unit of its module. Any other initializer
  goes into `__blink_init_globals_<module>`, in the same unit.
- Another unit refers to the global by its C name (`ir_global_ref`), and
  its declaration line is in the module's header.
- A const is a C global of its module's unit too (`int64_t blink_base_K
  = 3;`). No reader unit prints its value; each prints its C name. The
  name check still marks a const, so a fold added later, as spec 2.21
  allows in a range pattern bound or a default, keeps its readers.
- The entry unit calls each init fn. Its key holds the `init` lines, so
  a global made run-time or constant again emits `__main__` again.
- The init calls run in module order. Only an import changes that order,
  and a new import changes the inputs of import resolution, so the build
  takes no unit.

A reader can name a global or const in a way other than the bare word of
its declaration. Each shape that builds today, and why its unit is kept:

| shape | why the reader is emitted again |
|---|---|
| qualified (`base.G`) | its source names `G` |
| selective import from a `pub import` facade | its source names `G` |
| string interpolation (`"{G}"`) | the word check reads the whole text |
| another const (`pub const KC = K + 1`) | its source names `K`; `KC`'s readers read `KC`'s C global |
| a generic body that reads `G` | the instance is base's: base's unit writes its body |
| keyword default, struct field default | the caller's C holds the folded literal; the caller reads `base.bl`, which changed |

A renamed selective import of a global, a qualified read through a
facade, a default that names a const from another module, and a range
pattern bound that names a const each fail to compile today. Each has a
bug, and a chore adds the shape to
`test_unit_reuse_emits_again_the_units_that_read_an_edited_global_or_const_by_any_name.bl`
once it builds. `import m as x` is in the spec, but the parser does not
take it yet.

A global whose initializer makes a new instance of a generic of another
module (`pub let GI = count([1.5])` in `gen`) lands the instance in the
generic's module: `base.priv.h` declares it and `base.c` writes its body.
The build sees the header change and emits `base` again.

A test block of a module other than the entry is not in the program the
build makes, so it adds no name and changes no unit. `src/compiler.bl`
merges only the entry's test captures into the program; `mono` and
`cg_reg` read tests only from the program's captures. So a non-entry test
cannot add an instance, lower a private fn it alone calls, or move a
counter: `c_mint_seq`, which numbers closures and fn values, restarts for
each unit (`src/cname.bl`), and a string literal is written in the unit
that uses it. A test does move the lines below it, and panic text names
a source line, so the unit of the module that holds the test is always
emitted again.

Two mutants of `src/emit_record.bl` check the tests:

- A let or const edit adds no name. The any-name test and the readers
  test fail on their took lists. `BLINK_EMIT_REUSE_VERIFY` stays green,
  since no reader prints a value; the name check guards a future fold.
- A test-only edit takes every unit, its own too. Verify fails: the
  unit of `leaf` is not the cold one, at the panic line a test above its
  code moves.

The parser marks a plain global or const with its keyword and name. A
global with an annotation, or one that destructures or binds `_`, stays
`other`. Types, aliases, effects and impls stay `other`, so the build
takes nothing after an edit to one. A type or an effect changes the
types header; an impl changes the module header; an alias changes no
header, but no rule yet shows which units it reaches. Traits and
annotated fns take units since a later change ("Units kept across a
trait or annotated fn edit").

#### Bench

Through the daemon, settle 1 s, 11 reps, median seconds (min-max). Base
and the change ran in turn: base, change, base, change. Base is gen1 of
`3f228972` (sha256 `ee3770a4…`), the change is gen1 of `dfddc799`
(sha256 `f9944d7d…`), each built by `task gen1` with the same `-flto`.
`bench/edit_loop/global_test_items_daemon_settle1_*.tsv` hold the full
rows. Every C hash check reads 11/11.

`testblock-<module>` adds a test block to the end of the module, so its C
is the warm C. `global-cname` gives `c_mint_seq` a new Int literal on each
run.

| target | case | base run 1 | change run 2 | base run 3 | change run 4 |
|---|---|---|---|---|---|
| cli | nochange | 0.145 (0.138-0.150) | 0.143 (0.138-0.147) | 0.141 (0.135-0.150) | 0.137 (0.134-0.150) |
| cli | body-cname | 0.415 (0.392-0.420) | 0.411 (0.398-0.419) | 0.414 (0.391-0.427) | 0.412 (0.392-0.423) |
| cli | body-typecheck | 0.447 (0.436-0.463) | 0.445 (0.426-0.449) | 0.445 (0.430-0.461) | 0.445 (0.431-0.461) |
| cli | pubfn-cname | 0.441 (0.438-0.557) | 0.441 (0.433-0.542) | 0.439 (0.432-0.572) | 0.442 (0.430-0.550) |
| cli | privfn-cname | 0.446 (0.432-0.458) | 0.442 (0.436-0.450) | 0.450 (0.443-0.460) | 0.443 (0.427-0.459) |
| cli | pubfn-typecheck | 0.464 (0.453-0.471) | 0.467 (0.457-0.483) | 0.469 (0.462-0.476) | 0.464 (0.450-0.485) |
| cli | privfn-typecheck | 0.466 (0.457-0.475) | 0.468 (0.462-0.480) | 0.471 (0.460-0.475) | 0.468 (0.451-0.477) |
| cli | testblock-cname | 0.792 (0.774-0.801) | 0.277 (0.266-0.417) | 0.798 (0.788-0.814) | 0.264 (0.254-0.394) |
| cli | global-cname | 0.952 (0.939-0.962) | 0.436 (0.423-0.455) | 0.973 (0.946-1.001) | 0.436 (0.427-0.442) |
| cli | run-body-cname | 0.439 (0.427-0.948) | 0.433 (0.426-0.444) | 0.445 (0.434-0.990) | 0.428 (0.419-0.433) |
| cli | test-body-cname | 0.454 (0.443-0.472) | 0.466 (0.461-0.472) | 0.461 (0.454-0.480) | 0.474 (0.456-0.483) |
| cli | cold-obj | 2.279 (2.267-2.386) | 2.298 (2.294-2.414) | 2.310 (2.298-2.383) | 2.290 (2.275-2.395) |
| cli | cold-all | 5.054 (5.029-5.083) | 5.112 (5.091-5.122) | 5.073 (5.058-5.096) | 5.102 (5.069-5.134) |
| small | nochange | 0.044 (0.043-0.045) | 0.044 (0.042-0.046) | 0.043 (0.041-0.044) | 0.043 (0.042-0.045) |
| small | body-inventory | 0.087 (0.084-0.089) | 0.087 (0.085-0.088) | 0.086 (0.082-0.087) | 0.086 (0.084-0.087) |
| small | pubfn-model | 0.078 (0.076-0.082) | 0.079 (0.075-0.081) | 0.078 (0.077-0.080) | 0.078 (0.077-0.081) |
| small | privfn-model | 0.077 (0.076-0.080) | 0.079 (0.075-0.081) | 0.079 (0.076-0.080) | 0.078 (0.076-0.081) |
| small | testblock-model | 0.048 (0.047-0.050) | 0.046 (0.044-0.048) | 0.048 (0.046-0.049) | 0.047 (0.045-0.050) |
| small | run-body-inventory | 0.085 (0.084-0.091) | 0.086 (0.084-0.089) | 0.088 (0.085-0.090) | 0.087 (0.085-0.089) |
| small | test-body-inventory | 0.113 (0.111-0.116) | 0.114 (0.110-0.117) | 0.113 (0.110-0.118) | 0.113 (0.110-0.120) |
| small | cold-obj | 0.083 (0.079-0.087) | 0.083 (0.081-0.088) | 0.083 (0.081-0.088) | 0.082 (0.080-0.087) |

On cli a test block now costs less than a body edit, since no unit
changes: 0.79-0.80 s drops to 0.26-0.28 s. A new global value costs
what a body edit costs: 0.95-0.97 s drops to 0.44 s. On small the test
block row does not change outside its spread: 0.046-0.048 s, near the
0.043-0.044 s of a build with no edit.

In these four runs `cold-all` on cli reads 30-58 ms slower with the
change, outside the spread in run 2, and `test-body-cname` 5-20 ms
slower. The two rows ran again in turn, four runs
(`bench/edit_loop/global_test_items_recheck_daemon_settle1_*.tsv`):
`cold-all` reads 4.990 and 5.004 s for base, 5.014 and 4.995 s for the
change; `test-body-cname` 0.450 and 0.448 s for base, 0.452 and 0.452 s
for the change. Each pair is inside the other's spread, so neither row
is slower.

### Units kept across a body edit beside an effect

Before this change, a body edit in a source that declares an effect with
an operation made the build take no unit. Each unit calls
`emit_module_head`, which prints the default body of each operation
(`default_op_body`). That lowering used the span of the operation, so it
marked the declaring source as read by every unit, although the C it
prints holds no position.

`emit_effect_vtable` now stops the marks while it prints the default
bodies (`ir_sources_pause` and `ir_sources_resume`). Their C comes from
the names and types of the operations. Two checks still key them:

- the vtable typedef holds each operation's name, return and parameters,
  and it is in the types header, which must be byte-equal for any take;
- an effect is an item of kind `other`, so an edit that adds, removes or
  changes an effect or an operation takes no unit.

A handler is code in a fn body, so its unit marks its own source as for
any other body.

Measured before this change:

- cli as checked in has no effect with an operation, so a body edit
  takes the units it does not reach.
- cli with `effect Probe { effect Ping { fn ping() -> Int } }` added to
  `src/cname.bl`: a body edit in `cname.bl` takes no unit. Through the
  daemon it costs 0.906 s (0.850-0.955), against 0.444 s (0.431-0.847)
  with no such effect.
- small with `audit.bl` (below): a body edit in `audit.bl` takes no unit;
  with this change it takes 5 of 6, all but `audit`.

A sweep on cli through the daemon under `BLINK_EMIT_REUSE_VERIFY=1` ran
16 edits, each served by the daemon and each byte-equal to a cold emit:
an effect with an operation added to `src/diagnostics.bl`; a body edit
and its undo in `diagnostics.bl`, `lexer.bl`, `cg_decl.bl` and
`typecheck.bl`; an operation added, its signature changed and undone; a
handler added in a body of `diagnostics.bl`, its body changed, and
removed; the operation and the effect removed. Each step that touches
the effect or an operation took no unit (1.9-4.2 s). Each body edit and
each handler step took 51 units (1.42-1.65 s).

Three mutants check the tests:

- The item-kind rule lets `other` through. Every test stays green: the
  types header differs, so the build takes nothing.
- The same, and the types header compare always matches. The
  emits-again test and the entry-unit test fail on their took lists
  (`effect added: took __main__,eff,user`). The build still writes the
  cold output: the check after the take finds the headers changed and
  emits each unit again. `BLINK_EMIT_REUSE_VERIFY` stays green.
- The build takes every unit. Verify fails: unit `eff` is not the one a
  cold emit writes.

The binary from before this change is the mutant that takes too little.
Verify stays green, and the took list of the new tests fails.

`bench/edit_loop/src/audit.bl` gives the small target an effect with an
operation and a private fn beside it; `body-audit` edits that fn.
`src/main.bl` handles the effect with a handler that drops each note, so
the output does not change. Every small row now builds one more unit.

#### Bench

Through the daemon, settle 1 s, 11 reps, median seconds (min-max). Base
and the change ran in turn: base, change, base, change. Base is gen1 of
`d82b0e5f` (sha256 `f9944d7d…`), the change is gen1 of `c374ccb2`
(sha256 `7256272c…`). Both ran on tree `4f30afea`.
`bench/edit_loop/effect_evidence_daemon_settle1_*.tsv` hold the full
rows. Every C hash check reads 11/11.

| target | case | base run 1 | change run 2 | base run 3 | change run 4 |
|---|---|---|---|---|---|
| cli | nochange | 0.142 (0.137-0.151) | 0.141 (0.137-0.149) | 0.142 (0.133-0.154) | 0.142 (0.137-0.151) |
| cli | body-cname | 0.410 (0.396-0.428) | 0.410 (0.394-0.426) | 0.411 (0.396-0.424) | 0.411 (0.397-0.439) |
| cli | body-typecheck | 0.450 (0.433-0.458) | 0.453 (0.438-0.459) | 0.445 (0.434-0.459) | 0.443 (0.432-0.452) |
| cli | pubfn-cname | 0.438 (0.430-0.563) | 0.435 (0.430-0.571) | 0.448 (0.437-0.558) | 0.444 (0.440-0.560) |
| cli | privfn-cname | 0.442 (0.432-0.445) | 0.441 (0.435-0.455) | 0.448 (0.442-0.459) | 0.447 (0.438-0.451) |
| cli | pubfn-typecheck | 0.462 (0.444-0.471) | 0.470 (0.453-0.483) | 0.474 (0.461-0.479) | 0.467 (0.461-0.474) |
| cli | privfn-typecheck | 0.468 (0.450-0.479) | 0.477 (0.469-0.486) | 0.480 (0.453-0.498) | 0.465 (0.445-0.475) |
| cli | testblock-cname | 0.273 (0.261-0.405) | 0.277 (0.267-0.426) | 0.273 (0.265-0.420) | 0.266 (0.251-0.403) |
| cli | global-cname | 0.433 (0.422-0.450) | 0.441 (0.421-0.447) | 0.448 (0.427-0.462) | 0.426 (0.419-0.445) |
| cli | run-body-cname | 0.438 (0.416-0.444) | 0.433 (0.425-0.438) | 0.444 (0.431-0.461) | 0.431 (0.419-0.442) |
| cli | test-body-cname | 0.454 (0.449-0.463) | 0.451 (0.447-0.460) | 0.453 (0.448-0.461) | 0.453 (0.447-0.458) |
| cli | cold-obj | 2.259 (2.237-2.375) | 2.278 (2.264-2.369) | 2.283 (2.268-2.382) | 2.271 (2.256-2.379) |
| cli | cold-all | 4.958 (4.931-4.981) | 5.006 (4.916-6.298) | 4.969 (4.948-5.031) | 4.976 (4.951-5.012) |
| small | nochange | 0.045 (0.044-0.047) | 0.048 (0.046-0.050) | 0.046 (0.045-0.047) | 0.042 (0.041-0.045) |
| small | body-inventory | 0.093 (0.090-0.095) | 0.094 (0.092-0.097) | 0.093 (0.091-0.098) | 0.087 (0.085-0.090) |
| small | body-audit | 0.084 (0.081-0.085) | 0.082 (0.081-0.086) | 0.085 (0.083-0.086) | 0.077 (0.074-0.080) |
| small | pubfn-model | 0.087 (0.085-0.088) | 0.086 (0.084-0.087) | 0.088 (0.082-0.096) | 0.080 (0.079-0.084) |
| small | privfn-model | 0.086 (0.084-0.087) | 0.086 (0.083-0.089) | 0.086 (0.081-0.091) | 0.081 (0.080-0.082) |
| small | testblock-model | 0.050 (0.049-0.051) | 0.050 (0.049-0.053) | 0.052 (0.049-0.053) | 0.047 (0.045-0.051) |
| small | run-body-inventory | 0.094 (0.092-0.095) | 0.094 (0.093-0.096) | 0.095 (0.093-0.098) | 0.087 (0.086-0.089) |
| small | test-body-inventory | 0.122 (0.119-0.125) | 0.122 (0.120-0.124) | 0.121 (0.119-0.123) | 0.114 (0.113-0.118) |
| small | cold-obj | 0.090 (0.089-0.093) | 0.089 (0.088-0.098) | 0.090 (0.088-0.094) | 0.085 (0.083-0.089) |

cli has no effect with an operation, so no cli row changes, and none is
slower outside its spread. On small, `body-audit` saves the emit of five
units, about 2 ms, which is inside the spread in run 2. Run 4 reads 5-8%
faster on every small row, `nochange` too, so the machine, not the
change, moved that run. `nochange` in run 2 reads 2-3 ms slower than
both base runs, outside the spread; it takes no effect path, and run 4
reads faster than both.

On small the obj cache already skips the C compile of each unit whose C
did not change, so the take saves only emit time there. The saving shows
on cli with an effect that has an operation: `Probe` (above) added to
`src/cname.bl`, a body edit of `strip_blink` through the daemon, settle
1 s, 11 reps, the same two binaries in turn:

| case | base run 1 | change run 2 | base run 3 | change run 4 |
|---|---|---|---|---|
| body-cname with `Probe` | 0.867 (0.812-0.896) | 0.417 (0.398-0.435) | 0.879 (0.819-0.898) | 0.415 (0.398-0.429) |

The change brings this edit to what `body-cname` costs with no effect,
0.410-0.411 s.

### A PCH of the archive header

Each unit includes `libblink_std.h`, the stdlib archive header, which
includes `runtime.h`. Measured before this change with gcc 16 at `-O1`,
one compile at a time: a cli unit that holds only its prologue compiles
in 22.6 ms, and 10.7 ms with a PCH of the header. The `cname` unit
compiles in 148.6 ms, and 137.4 ms with the PCH. So each compile spends
about 12 ms in the header, the same on small. Each object built with the
PCH is byte-equal to the one built without it, at `-O1` and with
`--debug`. The PCH builds in about 50 ms and is 7.2 MB.

The build now keeps a PCH of the archive header in the obj cache:
`<key>.pch/` holds copies of `libblink_std.h` and `runtime.h` and the
`libblink_std.h.gch` built from them. The build holds links (or copies)
of the three files in `<hold>/pch/`, in its hold dir under the cache's
`tmp/`: the GC of another build can remove `<key>.pch/` while the units
compile. A unit that it serves compiles with `-I<hold>/pch` before
`-I<arc_dir>`, so gcc finds the `.gch` beside the copy, and with
`-ffile-prefix-map=<hold>/pch=<arc_dir>`, so the debug info names the
archive dir as a compile without the PCH does.

- gcc takes a `.gch` only when the unit defines, before the include, the
  macros the PCH was built with. The prologue of a unit is a `#define`
  line for each native-dep gate it reads, then
  `BLINK_USE_EXTERN_RUNTIME_STORAGE` and the include. The build reads
  that prologue from each unit to compile and builds one PCH for the set
  of macros most of those units define. The rest read the header. On cli
  68 of 69 units read the PCH; `typecheck.pos` includes no archive
  header. In a program with a sqlite store, the units that read the gate
  get a PCH under that gate, and `__main__`, which defines other macros,
  reads the header.
- The key holds the header and `runtime.h` shas, the cc id, the archive
  dir, every flag, those macros, each include flag, and the sha of each
  header in each include dir (`build_objcache.pch_key`). The build hashes
  those headers once, for the obj keys and the PCH key both.
- On a miss the build stages the copies in a private dir, builds the
  `.gch` there in a slot of its own while the units compile, holds its
  files, and renames the dir into place. A unit that starts after that
  reads the held files.
  When every unit starts before it ends, no unit of this build reads it,
  so the build waits for it after the link.
- gcc reads the header beside a `.gch` it cannot take, so a stale or
  wrong PCH costs only time. A `.gch` cut short stops gcc instead, so a
  unit that fails with the PCH compiles once more without it, and the
  build drops the PCH when that compile passes.
- No PCH for a cross build or under ccache. No gcc PCH when a
  `libblink_std.h.gch` sits beside the archive header already. clang
  gets a PCH of its own (see "clang and zig cc" below).
- A program's first build makes no PCH. A one-off build (a test, a CI
  job) would pay for a PCH that no later build reads. The build makes one
  only when `<out_dir>/<name>.units/` is there: each build that reaches
  the link leaves it, so it shows that this program was built before.
  The first edit after a cold build makes the PCH, and the edits after it
  read it.
- The obj key of a unit does not change, since its object does not.
- GC and `blink cache clean` treat a `.pch` dir as one entry, with its
  `.meta`. Its bytes count toward the cap.
- Dev knob: `BLINK_ARCHIVE_PCH=0` turns the PCH off. The byte-equal tests
  use it to build objects with no PCH in the cache at all.

As with the obj key, system headers (`gc.h`, libc) are not in the key;
gcc checks the `.gch` against the compiler that reads it.

cli finds `BLINK_USE_SQLITE` in its own C (a string literal in
`stdlib_native_deps.bl` holds it), so it builds with
`-I lib/native/sqlite3` although no unit defines the gate. A first cut
gave no PCH to a build with an include dir, so cli got none. The key now
holds the include dirs and their headers in its place.

#### Bench

Through the daemon, settle 1 s, 11 reps, median seconds (min-max). Base
and the change ran in turn: base, change, base, change. Base is gen1 of
main `34dd97f4` (sha256 `7256272c…`), the change is gen1 of `100ca7fd`
(sha256 `8c36b275…`). Both ran on tree `e2af9223`.
`bench/edit_loop/archive_pch_daemon_settle1_*.tsv` hold the full rows.
Every C hash check reads 11/11. The bench counts the PCH build as a cc
call, so `cold-obj` reads one call more for the change.

| target | case | base run 1 | change run 2 | base run 3 | change run 4 |
|---|---|---|---|---|---|
| cli | nochange | 0.143 (0.136-0.147) | 0.142 (0.134-0.150) | 0.143 (0.139-0.152) | 0.141 (0.136-0.154) |
| cli | body-cname | 0.419 (0.393-0.431) | 0.401 (0.382-0.407) | 0.412 (0.396-0.425) | 0.397 (0.383-0.416) |
| cli | body-typecheck | 0.446 (0.441-0.454) | 0.427 (0.413-0.441) | 0.440 (0.438-0.451) | 0.433 (0.424-0.440) |
| cli | pubfn-cname | 0.451 (0.440-0.563) | 0.435 (0.414-0.537) | 0.444 (0.436-0.550) | 0.429 (0.414-0.555) |
| cli | privfn-cname | 0.441 (0.429-0.455) | 0.426 (0.412-0.445) | 0.450 (0.440-0.463) | 0.423 (0.406-0.441) |
| cli | pubfn-typecheck | 0.462 (0.445-0.475) | 0.445 (0.435-0.452) | 0.477 (0.463-0.481) | 0.444 (0.434-0.456) |
| cli | privfn-typecheck | 0.461 (0.447-0.475) | 0.445 (0.433-0.460) | 0.472 (0.463-0.489) | 0.452 (0.441-0.468) |
| cli | testblock-cname | 0.264 (0.261-0.421) | 0.262 (0.251-0.403) | 0.277 (0.267-0.420) | 0.277 (0.267-0.413) |
| cli | global-cname | 0.438 (0.428-0.444) | 0.414 (0.409-0.418) | 0.448 (0.437-0.455) | 0.424 (0.413-0.441) |
| cli | run-body-cname | 0.439 (0.433-0.444) | 0.406 (0.393-0.412) | 0.442 (0.425-0.446) | 0.414 (0.407-0.423) |
| cli | test-body-cname | 0.451 (0.443-0.456) | 0.440 (0.436-0.450) | 0.449 (0.443-0.456) | 0.438 (0.434-0.445) |
| cli | cold-obj | 2.260 (2.241-2.370) | 2.212 (2.200-2.320) | 2.293 (2.271-2.364) | 2.204 (2.190-2.296) |
| cli | cold-all | 4.947 (4.930-4.964) | 4.884 (4.864-4.913) | 4.953 (4.931-4.971) | 4.895 (4.863-4.907) |
| small | nochange | 0.044 (0.042-0.047) | 0.045 (0.041-0.046) | 0.044 (0.042-0.046) | 0.044 (0.042-0.047) |
| small | body-inventory | 0.087 (0.085-0.088) | 0.075 (0.073-0.077) | 0.087 (0.086-0.090) | 0.075 (0.073-0.077) |
| small | body-audit | 0.076 (0.074-0.079) | 0.064 (0.062-0.066) | 0.075 (0.074-0.079) | 0.063 (0.062-0.065) |
| small | pubfn-model | 0.080 (0.077-0.081) | 0.069 (0.067-0.071) | 0.080 (0.076-0.081) | 0.068 (0.066-0.068) |
| small | privfn-model | 0.079 (0.077-0.082) | 0.068 (0.067-0.070) | 0.081 (0.079-0.082) | 0.068 (0.066-0.069) |
| small | testblock-model | 0.048 (0.046-0.048) | 0.048 (0.047-0.050) | 0.047 (0.046-0.049) | 0.048 (0.045-0.048) |
| small | run-body-inventory | 0.088 (0.086-0.090) | 0.076 (0.074-0.079) | 0.089 (0.086-0.090) | 0.076 (0.074-0.077) |
| small | test-body-inventory | 0.113 (0.111-0.118) | 0.102 (0.098-0.104) | 0.114 (0.110-0.116) | 0.102 (0.098-0.105) |
| small | cold-obj | 0.084 (0.082-0.088) | 0.090 (0.087-0.096) | 0.085 (0.083-0.092) | 0.088 (0.087-0.094) |

Each row with a unit to compile is faster on both targets, and each row
without one is the same. A cli unit compile (`cc_s`) drops from 0.150 s
to 0.140 s, and by 11 ms on the typecheck rows (0.046 s to 0.035 s): the
header share. `cold-obj` on cli drops 50-90 ms. A small edit drops about
12 ms of 75-114 ms.

`cold-obj` on small reads 3-6 ms slower: it builds the PCH, which takes
about as long as its six units and the link together. Each base run has
a max of 0.088 or 0.092 s and each change run a min of 0.087 s, so the
spreads overlap. The first edit after it saves 12 ms.

#### Bench of the lazy PCH

The same bench with the first-build rule in place. Base is gen1 of main
`34dd97f4` (sha256 `7256272c…`), the change is gen1 of `95fff446`
(sha256 `8b2d8683…`). Both ran on tree `95fff446`. Every C hash check
reads 11/11.

| target | case | base run 1 | change run 2 | base run 3 | change run 4 |
|---|---|---|---|---|---|
| small | nochange | 0.044 (0.042-0.045) | 0.045 (0.043-0.046) | 0.045 (0.043-0.046) | 0.044 (0.043-0.045) |
| small | body-inventory | 0.087 (0.085-0.089) | 0.075 (0.073-0.093) | 0.087 (0.086-0.090) | 0.075 (0.074-0.091) |
| small | body-audit | 0.075 (0.074-0.077) | 0.064 (0.061-0.065) | 0.075 (0.072-0.076) | 0.064 (0.063-0.066) |
| small | pubfn-model | 0.079 (0.077-0.080) | 0.067 (0.066-0.070) | 0.079 (0.077-0.080) | 0.067 (0.065-0.069) |
| small | privfn-model | 0.081 (0.076-0.083) | 0.066 (0.065-0.069) | 0.081 (0.077-0.082) | 0.066 (0.064-0.068) |
| small | testblock-model | 0.047 (0.044-0.049) | 0.047 (0.045-0.048) | 0.047 (0.045-0.048) | 0.046 (0.044-0.049) |
| small | run-body-inventory | 0.087 (0.086-0.092) | 0.076 (0.074-0.078) | 0.086 (0.084-0.089) | 0.076 (0.073-0.078) |
| small | test-body-inventory | 0.115 (0.112-0.117) | 0.102 (0.100-0.114) | 0.113 (0.111-0.117) | 0.102 (0.100-0.120) |
| small | cold-obj | 0.085 (0.082-0.088) | 0.090 (0.087-0.092) | 0.083 (0.081-0.088) | 0.087 (0.085-0.091) |
| cli | body-cname | 0.445 (0.425-0.457) | 0.439 (0.424-0.448) | 0.448 (0.429-0.458) | 0.432 (0.423-0.444) |
| cli | cold-obj | 2.394 (2.381-2.754) | 2.345 (2.312-2.425) | 2.396 (2.361-2.491) | 2.370 (2.336-2.433) |
| cli | cold-all | 5.202 (5.182-5.246) | 5.146 (5.106-5.166) | 5.196 (5.181-5.220) | 5.146 (5.126-5.162) |

The other cli rows read the same or 1-4% faster.

The warm build of the bench is the program's first build, so it makes
no PCH. The first timed edit makes it, and each edit after that reads it.
`body-inventory` on small, each rep in turn:

- change run 2: 0.093, then 0.073-0.078 (median of reps 2-11 0.074)
- change run 4: 0.091, then 0.074-0.077 (median 0.075)
- base runs 1 and 3: 0.085-0.090 on every rep (median 0.087)

So the first edit pays about 5 ms once, and each later edit saves about
12 ms.

`cold-obj` on small reads about 4 ms slower in each change run, with the
eager PCH and the lazy one alike. The case clears the obj cache, which
holds the PCH, but not `<name>.units/`, so the build takes the program
as built before and makes the PCH again in each rep. Each rep of change
run 2 reads 0.087-0.092 and of base run 3 0.081-0.088; the spreads
overlap. A real cleared cache costs this once.

#### Cost in `task ci`

Measured in a scratch clone where `main..HEAD` is empty on both sides:
base is `34dd97f4`, the change is a `--no-ff` merge of `95fff446` into
it. Four `task ci` walls each, in turn, all exit 0:

- base: 118.02, 117.74, 117.63, 117.79 s
- change: 121.75, 121.81, 121.97, 122.08 s

The change is 4.1 s slower, past a spread of about 0.4 s. Each step up
to the corpus takes the same time on both sides (ratchet 0.56 s,
lint_codegen 8.0-8.1 s, corpus start at 14.0 s). The whole 4.1 s is in
the corpus phase: 103-104 s against 107-108 s.

Split of the corpus and per-module slice reports of one base run and one
change run:

- New tests: the change adds 10 PCH test files (2142 to 2152 corpus
  files, 190 to 200 slice rows). They sum to 14.3 s in the corpus and
  17.5 s in the slice, about 32 s, which is about 2.7 s of wall on 12
  workers. The longest are the gated byte-equal test (3.1 s corpus,
  5.0 s slice) and the plain one (2.3 s).
- The product: no step outside the corpus is slower, and a test build is
  the program's first build, so it makes no PCH.
- Drift on the common files, UNPROVEN: the files on both sides sum to
  865.0 s against 877.1 s in the corpus and 238.3 s against 244.8 s in
  the slice, about 1.3% more. That covers the rest of the 4.1 s. It was
  not measured with the PCH off, nor against a second base run, so it
  can be noise or a cost of the change. A test that builds a program
  twice makes a PCH on the second build, so a cost there is possible.

The 10 tests are kept: each covers a case the PCH can get wrong (race,
bad `.gch`, byte-equal objects at `-O1` and `-g`, one error per unit,
GC, the key), and each goes red on its own mutant. The race test came
after these walls and adds about 0.3 s of CPU.

#### clang and zig cc

clang reads a PCH only through `-include-pch`, never from a `.gch` or
`.pch` beside a header it includes. Measured with clang 23.1.1 at `-O1`,
one compile at a time, 5 runs, median ms (min-max):

| unit | plain | with PCH |
|---|---|---|
| `cname` | 190.0 (188.3-195.2) | 175.0 (173.5-176.1) |
| `comment_attach` | 130.9 (130.1-131.4) | 116.0 (115.9-117.4) |
| `std_cache_key` | 46.5 (45.7-47.5) | 30.7 (30.0-30.9) |

So each clang compile spends about 15 ms in the header. The PCH builds
in about 40 ms and is 1.3 MB.

clang records the absolute path of each header it read in the PCH, and
reads them there again when a unit loads it. A PCH built from copies in
one dir and moved fails with "could not find file", even with
`-fno-validate-pch`. So the clang PCH is built from
`<arc_dir>/libblink_std.h` itself, with no copies and no prefix map:

- `<key>.pch/` holds only `libblink_std.h.pch`. The build links it at
  `<hold>/pch/libblink_std.h.pch`, and a unit it serves compiles with
  `-include-pch <hold>/pch/libblink_std.h.pch`. A moved or linked `.pch`
  loads, since clang checks the headers and not the PCH path. The debug
  info names the archive dir, as a unit compiled without it does.
- The key is the gcc key. Its cc id (`cc --version`, first line) tells
  gcc and clang apart, so a `.gch` and a `.pch` never share a dir.
- The build passes `-Xclang -fno-pch-timestamp`: a reinstall of the same
  header bytes gives it a new mtime, which would stop clang otherwise.
- clang takes a header whose bytes changed and size did not. The key
  holds the header shas, and the build hashes both headers again after
  the PCH build; it stores the PCH only when they match the key.
- clang stops with an error on a PCH it cannot take: cut short, not a
  PCH, another `-O` level, a header of another size or gone, or a macro
  the unit defines to another value. The retry above covers each: the
  unit compiles once more without it, and the build drops the PCH.
- clang loads the PCH before the first line of the unit, and takes it
  when a unit defines fewer macros than the PCH was built with. The
  prologue rule that picks the units a PCH serves keeps that from
  happening.
- Each object is byte-equal with and without the PCH at `-O1`, `-O2`
  and `-g -O0 -DBLINK_DEBUG`.

zig cc 0.16 also takes `-include-pch` with a PCH it built for the same
target (tried with `aarch64-linux-gnu`, `x86_64-linux-musl` and
`aarch64-macos`). Objects are byte-equal and a unit saves 11-21 ms. A
cross build still makes no PCH: no cross build links today, since the
link reads the host `libblink_std.a`. Turning it on needs the target in
the key and a cross build that links to test it.

##### Bench

Through the daemon, settle 1 s, 11 reps, median seconds (min-max). Base
and the change ran in turn: base, change, base, change. Base is gen1 of
main `4cae55ba` (sha256 `7698111126de03a9…`), the change is gen1 of
`36a780d3` (sha256 `4cc24c5f432231df…`). Both ran on tree `36a780d3`.
Every C hash check reads 11/11.

With clang 23.1.1 as `cc` (`cc_s` is the median unit compile time):

| target | case | base run 1 | change run 2 | base run 3 | change run 4 |
|---|---|---|---|---|---|
| cli | nochange | 0.164 (0.156-0.170) | 0.165 (0.157-0.168) | 0.166 (0.163-0.172) | 0.165 (0.158-0.170) |
| cli | body-cname | 0.505 (0.483-0.518) | 0.493 (0.467-0.515) | 0.501 (0.486-0.514) | 0.486 (0.470-0.491) |
| cli | body-cname `cc_s` | 0.212 | 0.200 | 0.212 | 0.198 |
| small | nochange | 0.061 (0.059-0.066) | 0.061 (0.056-0.064) | 0.061 (0.059-0.063) | 0.060 (0.055-0.063) |
| small | body-inventory | 0.109 (0.105-0.115) | 0.094 (0.091-0.112) | 0.110 (0.107-0.112) | 0.094 (0.092-0.110) |
| small | body-inventory `cc_s` | 0.040 | 0.024 | 0.039 | 0.025 |

The `cname` compile drops 12-14 ms of the 15 ms the header takes, and a
small edit 15 ms of 110 ms.

The full bench with gcc 16.2.1 as `cc`, the same binaries, runs and
order, is no slower on any row: no median of a change run is above the max of
a base run. Its rows are in `bench/edit_loop/clang_archive_pch_gcc_*.tsv`,
and the clang rows in `bench/edit_loop/clang_archive_pch_daemon_*.tsv`.

### Paths a debug object records

An object is correct in the cache only when its bytes follow from its
key. A unit compiled with `--debug` (`-g -O0 -DBLINK_DEBUG`) records
paths in its debug info. Two trees whose headers are byte-equal gave
equal keys, so tree B took tree A's objects, and a debugger in B opened
A's files. Found with `readelf --debug-dump=info,line` (gcc compresses
its debug sections, so `grep -a` finds nothing), gcc 16.2.1 and clang
23.1.1, per-module and one-unit, `-o` relative and absolute:

| path | from | `--debug` | default, `--release` |
|---|---|---|---|
| compile dir (`DW_AT_comp_dir`) | the cwd of cc | yes | no |
| unit name and a line-table dir | `-ffile-prefix-map=<work>=<units_dir>` (one unit: the dir of the C path) | yes | no |
| archive dir | `-I<arc_dir>` (clang names it from the compile dir when it is under it) | yes | no |
| vendored include dirs | `-I` | yes | no |
| `/usr/include` | the system headers | yes | no |
| `app/src/main.bl` | panic and assert text in the C | yes | yes |

The work and hold dirs are mapped away. Panic text and `__FILE__` in
the C are in the source sha. The vendored include dirs were already in
the key as `<dir>=<sha>` lines, and `cc --version` covers `/usr/include`.

So at `--debug` the key also holds the compile dir, the dir the C is
named under and the archive dir (`recorded_paths` in `cli.bl`). They
are not mapped away: a debugger in the tree needs them to find the
source. At the other levels an object records none of them and its key
does not change, so worktrees and CI trees with equal headers still
share objects. The test of two trees shows it: tree B compiles no unit
at the default level.

gcc and clang both take the compile dir from `$PWD` when it is absolute
and names the cwd (they compare inodes), else from `getcwd`. A cwd
reached through a link is then a dir of its own. cc inherits the `PWD`
of blink, and an `sh` between them keeps a `PWD` that names the cwd and
replaces one that does not. `build_objcache.compile_dir` reads the dir
the same way, so the key holds the dir each cc records. Blink sets no
`PWD`. Under the daemon, the child that runs a build takes the cwd and
`PWD` of the client first, so the key and the objects name the dir of
the client, not of the daemon. `compile_dir` compares by realpath, not
by inode: a stale `PWD` that names the cwd through another mount of it
is recorded by cc while the key holds the cwd. Both name the same dir.

The PCH key holds the archive dir and no compile dir. A PCH built in
one compile dir and read from another, with the same archive dir, gives
objects byte-equal to those built without it, with gcc and clang. The
unit key holds the compile dir, so the object of each tree is its own.

### Holds against a concurrent GC

Two builds that share an obj cache can race: the GC of one can remove an
entry the other found or stored and has not linked yet, and that link
fails. Two loops of 100 builds, one cache, a cap of 0 MB: 24 of 200
builds failed with `ld: cannot find <cache>/<key>.o`. A build now links
only names in a private dir of its own, and its units read the archive
header PCH from there too. Section 5 of `per-module-o-cache.md` gives the
design. After the change the same loops, 150 builds each, ran with no
failure, and each build printed the right output.

A first cut tried a hard link for each unit and then a `cp` when the link
failed. A miss has no object to link, so each missed unit ran a `cp` that
failed: 69 processes and 0.85 s more on a cold build of cli. The hold now
copies with `read(2)` and `write(2)` in its own process, and a miss ends
at the failed `open(2)` of the object it does not have.

#### Bench

Through the daemon, settle 1 s, then without the daemon for the cold
cases; 11 reps, median seconds (min-max). Base and the change ran in
turn: base, change, base, change. Base is gen1 of `d8eb38b8` (sha256
`8b2d8683…`), the change is gen1 of `bc65dc05` (sha256 `d379e7f8…`), both
from `task gen1`. Both ran on tree `bc65dc05`.
`bench/edit_loop/objcache_hold_*.tsv` hold the full rows. Every C hash
check reads 11/11.

| target | case | base run 1 | change run 2 | base run 3 | change run 4 |
|---|---|---|---|---|---|
| cli | nochange | 0.163 (0.157-0.175) | 0.168 (0.161-0.177) | 0.167 (0.160-0.175) | 0.170 (0.163-0.183) |
| cli | body-cname | 0.433 (0.421-0.440) | 0.433 (0.423-0.444) | 0.431 (0.419-0.444) | 0.426 (0.409-0.440) |
| cli | body-typecheck | 0.458 (0.449-0.469) | 0.462 (0.439-0.467) | 0.458 (0.445-0.470) | 0.460 (0.443-0.471) |
| cli | pubfn-cname | 0.469 (0.462-0.578) | 0.466 (0.462-0.587) | 0.462 (0.454-0.570) | 0.471 (0.460-0.587) |
| cli | privfn-cname | 0.473 (0.461-0.482) | 0.468 (0.462-0.488) | 0.457 (0.450-0.485) | 0.469 (0.461-0.479) |
| cli | pubfn-typecheck | 0.486 (0.476-0.500) | 0.484 (0.480-0.497) | 0.471 (0.456-0.492) | 0.483 (0.473-0.491) |
| cli | privfn-typecheck | 0.485 (0.470-0.495) | 0.490 (0.469-0.509) | 0.484 (0.473-0.498) | 0.483 (0.469-0.494) |
| cli | testblock-cname | 0.305 (0.294-0.439) | 0.305 (0.289-0.444) | 0.298 (0.282-0.423) | 0.302 (0.294-0.433) |
| cli | global-cname | 0.462 (0.450-0.476) | 0.466 (0.454-0.473) | 0.452 (0.434-0.464) | 0.458 (0.449-0.466) |
| cli | run-body-cname | 0.467 (0.454-0.479) | 0.460 (0.442-0.471) | 0.456 (0.446-0.469) | 0.465 (0.454-0.477) |
| cli | test-body-cname | 0.481 (0.468-0.500) | 0.478 (0.473-0.503) | 0.477 (0.471-0.500) | 0.480 (0.473-0.487) |
| cli | cold-obj | 2.375 (2.346-2.455) | 2.361 (2.340-2.419) | 2.362 (2.338-2.465) | 2.355 (2.327-2.420) |
| cli | cold-all | 5.150 (5.124-5.174) | 5.160 (5.136-5.177) | 5.152 (5.137-5.173) | 5.155 (5.137-5.174) |
| small | nochange | 0.044 (0.042-0.046) | 0.042 (0.041-0.046) | 0.043 (0.043-0.046) | 0.043 (0.042-0.044) |
| small | body-inventory | 0.075 (0.071-0.088) | 0.074 (0.073-0.091) | 0.075 (0.072-0.093) | 0.075 (0.073-0.092) |
| small | body-audit | 0.063 (0.061-0.066) | 0.065 (0.063-0.067) | 0.065 (0.062-0.067) | 0.064 (0.063-0.066) |
| small | pubfn-model | 0.068 (0.066-0.070) | 0.068 (0.067-0.071) | 0.067 (0.065-0.070) | 0.067 (0.066-0.068) |
| small | privfn-model | 0.067 (0.066-0.069) | 0.067 (0.065-0.069) | 0.067 (0.066-0.068) | 0.067 (0.065-0.069) |
| small | testblock-model | 0.047 (0.046-0.049) | 0.047 (0.046-0.048) | 0.047 (0.046-0.048) | 0.047 (0.046-0.048) |
| small | run-body-inventory | 0.076 (0.073-0.077) | 0.076 (0.075-0.077) | 0.076 (0.074-0.079) | 0.077 (0.075-0.078) |
| small | test-body-inventory | 0.103 (0.100-0.117) | 0.102 (0.100-0.119) | 0.102 (0.101-0.115) | 0.103 (0.101-0.117) |
| small | cold-obj | 0.090 (0.086-0.093) | 0.087 (0.086-0.090) | 0.089 (0.087-0.093) | 0.090 (0.087-0.095) |

Without the daemon:

| target | case | base run 1 | change run 2 | base run 3 | change run 4 |
|---|---|---|---|---|---|
| cli | cold-obj | 2.611 (2.594-2.626) | 2.618 (2.600-2.634) | 2.613 (2.595-2.626) | 2.614 (2.580-2.633) |
| cli | cold-all | 5.025 (4.998-5.055) | 5.017 (5.006-5.064) | 5.013 (4.996-5.039) | 5.018 (4.999-5.043) |
| small | cold-obj | 0.102 (0.100-0.106) | 0.102 (0.097-0.105) | 0.103 (0.100-0.106) | 0.103 (0.100-0.105) |

Each change row is inside the spread of the base rows beside it. The
holds cost no time a run can show: a hard link per object, and one dir
to remove after the link.

### Units that end out of order

The build reaped unit compiles in start order. The largest unit starts
first, but its compile does not always end last: on a cold build of
`src/cli.bl`, 69 units in 12 slots, a trace showed 9.3-9.8 slot-seconds
of idle slots. A slot was idle when its child had ended and an older
child had not. The cc wall was 2.02-2.05 s, and a replay of the trace
that reaps whichever child ends first gave 1.21-1.24 s, the time of
`parser.c`, the second unit to start. A program of 6 units, such as the
small bench target, had no idle slot.

Now each unit child, and the PCH compile:

- writes its stdout and stderr to `<place>.cc-out` and `<place>.cc-err`
  in the obj dir. The build reads and removes them when it reaps the
  child, whether cc passed, failed or died of a signal;
- holds the write end of a pipe of its own, and no other descriptor of
  the build but its stdin. The build sets `FD_CLOEXEC` on each read end
  it keeps, so a unit started later does not inherit the pipe of a unit
  or of the PCH compile that runs beside it.

The build polls the read ends of its units with a timeout of 50 ms.
After each wake it checks each unit it has not reaped with
`waitpid(pid, WNOHANG)`, and reaps each one that has ended. A read end
that reports `POLLHUP` or input is closed at once, and while a unit's
read end is closed but the unit has not been seen to end, the timeout is
1 ms: the kernel closes a process's descriptors a little before its
parent can reap it. A process that cc leaves running, and that holds the
write end, does not hold up the build: the unit ends, and the next sweep
finds it within 50 ms. The sweep costs at most 20 wakeups a second, each
one `poll` and one `waitpid` per running unit. The build waits on no pid
but those of its own units, so it reaps no other child of the process.
If `poll(2)` fails for a reason other than `EINTR`, the build waits on
the oldest unit it has not reaped. Output and error lines print in unit
order, as before.

No step reads a unit's object before the build has reaped that unit.
The link, the object cache store and the cache holds run after the last
unit is reaped. The PCH compile writes to a staged dir, and the build
holds and stores the `.gch` only after it has reaped the PCH compile; a
unit uses the PCH only when it starts after that.

Each build compiles in a dir of its own, `.units.<random>` in the out dir,
and renames it to `<stem>.units` at the end. If blink is killed while cc
runs, the cc children run to their end, but they write only into the
dir of the killed build, which no later build reads. The next build in
that out dir removes it (see per-module-o-cache.md, section 5).

Changes a user can see:

- The unit children are not in the runtime's table of children, so a
  `SIGTERM` sent to the blink pid alone does not reach cc. `^C`, a kill
  of the process group (which the daemon uses) and `timeout` still
  reach them.
- If `exec` fails, the unit's error output holds an `execvp:` line.

The runtime has no call that spawns a child with its output in a file,
so `src/build_fs.bl` forks and execs through libc.

#### Bench

Through the daemon, settle 1 s, then without the daemon for the cold
cases; 11 reps, median seconds (min-max). Base and the change ran in
turn: base, change, base, change. Base is gen1 of `86b69192` (sha256
`01f96a4e…`), the change is gen1 of `10097874` (sha256 `9295bba6…`), both
from `task gen1`. Both ran on tree `10097874`; the one file not yet
committed was this doc. `bench/edit_loop/unit_wait_any_*.tsv` hold the
full rows. Every C hash check reads 11/11.

| target | case | base run 1 | change run 2 | base run 3 | change run 4 |
|---|---|---|---|---|---|
| cli | nochange | 0.163 (0.153-0.172) | 0.163 (0.154-0.173) | 0.162 (0.153-0.174) | 0.163 (0.160-0.170) |
| cli | body-cname | 0.440 (0.412-0.446) | 0.428 (0.423-0.440) | 0.436 (0.420-0.454) | 0.426 (0.415-0.441) |
| cli | body-typecheck | 0.463 (0.454-0.472) | 0.468 (0.459-0.485) | 0.467 (0.456-0.478) | 0.456 (0.441-0.471) |
| cli | pubfn-cname | 0.466 (0.455-0.568) | 0.466 (0.457-0.575) | 0.476 (0.469-0.580) | 0.457 (0.446-0.578) |
| cli | privfn-cname | 0.470 (0.456-0.483) | 0.474 (0.466-0.491) | 0.478 (0.467-0.490) | 0.462 (0.452-0.471) |
| cli | pubfn-typecheck | 0.487 (0.477-0.496) | 0.496 (0.489-0.511) | 0.498 (0.480-0.507) | 0.483 (0.466-0.496) |
| cli | privfn-typecheck | 0.488 (0.474-0.502) | 0.492 (0.479-0.501) | 0.488 (0.476-0.508) | 0.489 (0.478-0.503) |
| cli | testblock-cname | 0.307 (0.297-0.438) | 0.306 (0.299-0.440) | 0.306 (0.298-0.451) | 0.304 (0.297-0.441) |
| cli | global-cname | 0.466 (0.458-0.476) | 0.465 (0.454-0.474) | 0.470 (0.459-0.475) | 0.466 (0.445-0.475) |
| cli | run-body-cname | 0.458 (0.444-0.467) | 0.456 (0.447-0.470) | 0.465 (0.458-0.473) | 0.463 (0.441-0.473) |
| cli | test-body-cname | 0.483 (0.470-0.495) | 0.483 (0.475-0.499) | 0.480 (0.471-0.494) | 0.477 (0.472-0.496) |
| cli | cold-obj | 2.361 (2.338-2.462) | 1.628 (1.620-1.714) | 2.358 (2.328-2.437) | 1.633 (1.618-1.731) |
| cli | cold-all | 5.145 (5.117-5.176) | 4.487 (4.465-4.522) | 5.140 (5.130-5.158) | 4.463 (4.448-4.504) |
| small | nochange | 0.044 (0.042-0.047) | 0.045 (0.043-0.046) | 0.045 (0.043-0.047) | 0.044 (0.043-0.047) |
| small | body-inventory | 0.076 (0.074-0.090) | 0.075 (0.073-0.092) | 0.076 (0.074-0.091) | 0.076 (0.074-0.089) |
| small | body-audit | 0.064 (0.063-0.066) | 0.065 (0.063-0.068) | 0.064 (0.062-0.065) | 0.066 (0.064-0.067) |
| small | pubfn-model | 0.067 (0.065-0.068) | 0.068 (0.066-0.070) | 0.068 (0.065-0.070) | 0.068 (0.065-0.070) |
| small | privfn-model | 0.067 (0.065-0.070) | 0.068 (0.067-0.069) | 0.068 (0.066-0.070) | 0.068 (0.066-0.071) |
| small | testblock-model | 0.048 (0.045-0.050) | 0.048 (0.046-0.049) | 0.048 (0.046-0.049) | 0.047 (0.045-0.048) |
| small | run-body-inventory | 0.077 (0.075-0.078) | 0.077 (0.076-0.079) | 0.075 (0.074-0.077) | 0.076 (0.074-0.079) |
| small | test-body-inventory | 0.102 (0.099-0.114) | 0.104 (0.102-0.119) | 0.103 (0.100-0.115) | 0.103 (0.100-0.118) |
| small | cold-obj | 0.089 (0.087-0.091) | 0.090 (0.087-0.093) | 0.087 (0.084-0.091) | 0.089 (0.087-0.091) |

Without the daemon:

| target | case | base run 1 | change run 2 | base run 3 | change run 4 |
|---|---|---|---|---|---|
| cli | cold-obj | 2.584 (2.559-2.606) | 1.932 (1.902-1.939) | 2.580 (2.557-2.621) | 1.927 (1.918-1.955) |
| cli | cold-all | 4.964 (4.931-5.002) | 4.308 (4.298-4.345) | 4.988 (4.954-4.998) | 4.331 (4.313-4.350) |
| small | cold-obj | 0.102 (0.100-0.105) | 0.103 (0.101-0.108) | 0.101 (0.101-0.104) | 0.102 (0.101-0.105) |

On cli the cold rows drop by 0.65-0.73 s, and the cc time drops by
about the same: cold-obj through the daemon 2.10-2.11 s to 1.39-1.40 s,
without it 2.01-2.02 s to 1.36-1.37 s (the `cc_s` column). Each other
change row is inside the spread of the base rows beside it.

The cc time does not reach the 1.21-1.24 s of the replay. A trace of 5
cold-obj builds of cli per binary, each `cc` timed with its CPU, shows
why. With the change, the cc time is the time of `parser.c` alone, to
within 8 ms: 1.36-1.40 s. With base, `parser.c` took 1.21-1.23 s. Each
slot now stays busy while `parser.c` compiles, and the CPU of all 69
units rises from 14.1 s to 14.8-15.0 s, so each compile runs a little
slower. No order of the units can end the build before its longest
unit ends.

### Runtime bodies out of each debug unit

At `-O0` gcc emits each plain `static` function that a unit sees, used
or not. `runtime.h` defined the assert and test-runner functions of
`runtime_test.h` and the helpers of `runtime_process.h` as
`BLINK_UNUSED static`, so each unit of a `--debug` build, and of each
`blink test` build, compiled its own copy. A replay of the cc commands
of a cold `--debug` build, with and without those bodies, one compile at
a time: on cli the 69 units took 7.68 s of compile time, and 6.16 s
without them, 20-30 ms and about 45 KB of object less per unit; on small
the 6 units took 0.31 s, and 0.17 s without them.

Now the twelve entry points of `runtime_test.h` are `BLINK_RT_FN`, with
a prototype before the `BLINK_RUNTIME_DECLS_ONLY` guard, and every body
of `runtime_test.h` and each static helper of `runtime_process.h` is
inside the guard. `BLINK_RT_FN` is empty when the unit reads the runtime
storage as extern, else `BLINK_UNUSED static`. So a unit compiles only
the declarations, and the unit that defines the runtime storage holds
the bodies: `monolith.o` of the archive, or `__main__` when the build
links no archive. A build that does not split into units sees the
bodies as before.

Two changes a user can see:

- A user C function, in an `@ffi` header or a vendored source, with the
  name of one of these twelve functions was an error at compile time.
  Now it is an error at link time, as it was already for the other
  `BLINK_RT_FN` names, such as `blink_alloc_atomic`.
- The archive is always built at `-O2`, also for `--debug`. A debugger
  now steps into the assert and test-runner code of `monolith.o`, which
  is optimized. Before, each unit held an `-O0` copy. This is a known
  trade.

#### The archive and its runtime.h

A dev `build/` must link an archive built against the same `runtime.h`,
because a unit now calls the runtime functions that the archive
defines. The archive stamp already held the sha of `runtime.h`, but
`ensure_dev_archive` did not read it, so after a runtime header edit
the build linked the old archive and failed on an undefined symbol.
Now, when the stamp names this compiler, the archive is current only
when its `runtime.h` is the one the build reads:

- When `libblink_std.a` resolves into a `std-cache/<key>/` dir that
  holds a copy of `runtime.h`, the build compares the bytes of that copy
  with the live `runtime.h` (0.1 ms).
- Else it compares the stamp's sha with a sha of the live `runtime.h`.
  A sha of the 284 KB file costs about 2 ms, which the first form of
  this change paid on each build, twice through the daemon.

`build_fs.real_path` replaces the realpath call of the daemon, so both
the daemon and the archive check use it.

#### Bench

Through the daemon, settle 1 s, then without the daemon for the cold
cases, then with `--debug` and without the daemon; 11 reps, median
seconds (min-max), and the `cc_s` medians of each run. Base and the
change ran in turn: base, change, base, change. Base is gen1 of
`e194f4aa` (sha256 `9295bba6…`), run on tree `e194f4aa`; the change is
gen1 of `ea6f6079` (sha256 `26eca40a…`), run on tree `ea6f6079`. Each
tree compiles its own `src/cli.bl`. `bench/edit_loop/unit_rt_statics_*.tsv`
hold the full rows. Every C hash check reads 11/11.

`blink test` always builds at `-O0` and takes no `--debug` flag, so the
`test-body` rows of the daemon table are debug builds, and the
`--debug` table has no `test-body` rows.

| target | case | base run 1 | change run 2 | base run 3 | change run 4 | cc_s 1/2/3/4 |
|---|---|---|---|---|---|---|
| cli | nochange | 0.166 (0.155-0.177) | 0.174 (0.165-0.180) | 0.171 (0.161-0.184) | 0.173 (0.162-0.184) | 0.000/0.000/0.000/0.000 |
| cli | body-cname | 0.433 (0.421-0.442) | 0.445 (0.432-0.456) | 0.428 (0.419-0.445) | 0.440 (0.429-0.459) | 0.144/0.145/0.143/0.145 |
| cli | body-typecheck | 0.452 (0.444-0.468) | 0.484 (0.462-0.490) | 0.461 (0.456-0.474) | 0.473 (0.454-0.482) | 0.050/0.050/0.051/0.049 |
| cli | pubfn-cname | 0.469 (0.458-0.573) | 0.486 (0.464-0.593) | 0.470 (0.450-0.592) | 0.479 (0.473-0.591) | 0.144/0.145/0.143/0.145 |
| cli | privfn-cname | 0.465 (0.451-0.479) | 0.483 (0.466-0.498) | 0.480 (0.467-0.484) | 0.473 (0.469-0.490) | 0.144/0.145/0.143/0.144 |
| cli | pubfn-typecheck | 0.481 (0.474-0.492) | 0.496 (0.486-0.509) | 0.486 (0.475-0.504) | 0.493 (0.480-0.503) | 0.035/0.035/0.036/0.036 |
| cli | privfn-typecheck | 0.488 (0.481-0.496) | 0.492 (0.483-0.498) | 0.492 (0.481-0.500) | 0.497 (0.478-0.508) | 0.036/0.036/0.036/0.036 |
| cli | testblock-cname | 0.313 (0.297-0.444) | 0.307 (0.292-0.446) | 0.310 (0.302-0.439) | 0.303 (0.285-0.437) | 0.000/0.000/0.000/0.000 |
| cli | global-cname | 0.470 (0.450-0.478) | 0.479 (0.460-0.492) | 0.474 (0.463-0.481) | 0.468 (0.462-0.482) | 0.144/0.143/0.144/0.144 |
| cli | run-body-cname | 0.464 (0.452-0.473) | 0.472 (0.457-0.480) | 0.464 (0.449-0.471) | 0.460 (0.444-0.471) | 0.144/0.143/0.143/0.143 |
| cli | test-body-cname | 0.481 (0.476-0.498) | 0.458 (0.447-0.470) | 0.479 (0.475-0.500) | 0.456 (0.450-0.469) | 0.095/0.075/0.095/0.073 |
| cli | cold-obj | 1.644 (1.621-1.728) | 1.644 (1.623-1.710) | 1.618 (1.598-1.732) | 1.656 (1.628-1.765) | 1.396/1.392/1.390/1.413 |
| cli | cold-all | 4.479 (4.455-4.517) | 4.564 (4.553-4.589) | 4.488 (4.450-4.519) | 4.543 (4.532-4.579) | 3.751/3.825/3.760/3.813 |
| small | nochange | 0.045 (0.041-0.045) | 0.046 (0.042-0.048) | 0.042 (0.041-0.045) | 0.044 (0.042-0.047) | 0.000/0.000/0.000/0.000 |
| small | body-inventory | 0.075 (0.074-0.089) | 0.078 (0.076-0.088) | 0.075 (0.073-0.090) | 0.078 (0.075-0.093) | 0.026/0.026/0.026/0.026 |
| small | body-audit | 0.064 (0.063-0.068) | 0.067 (0.064-0.068) | 0.065 (0.062-0.070) | 0.065 (0.063-0.069) | 0.015/0.015/0.015/0.015 |
| small | pubfn-model | 0.068 (0.066-0.070) | 0.070 (0.067-0.071) | 0.067 (0.066-0.070) | 0.069 (0.067-0.071) | 0.018/0.018/0.017/0.018 |
| small | privfn-model | 0.068 (0.066-0.071) | 0.069 (0.066-0.070) | 0.068 (0.067-0.072) | 0.069 (0.067-0.071) | 0.018/0.018/0.018/0.018 |
| small | testblock-model | 0.047 (0.046-0.049) | 0.049 (0.046-0.051) | 0.048 (0.047-0.049) | 0.048 (0.047-0.049) | 0.000/0.000/0.000/0.000 |
| small | run-body-inventory | 0.077 (0.075-0.079) | 0.079 (0.077-0.080) | 0.077 (0.074-0.078) | 0.079 (0.077-0.080) | 0.026/0.026/0.026/0.026 |
| small | test-body-inventory | 0.104 (0.099-0.122) | 0.080 (0.078-0.098) | 0.102 (0.100-0.121) | 0.081 (0.078-0.095) | 0.042/0.021/0.042/0.021 |
| small | cold-obj | 0.089 (0.086-0.093) | 0.090 (0.089-0.092) | 0.090 (0.085-0.093) | 0.091 (0.088-0.093) | 0.060/0.055/0.057/0.056 |

Without the daemon:

| target | case | base run 1 | change run 2 | base run 3 | change run 4 | cc_s 1/2/3/4 |
|---|---|---|---|---|---|---|
| cli | cold-obj | 1.940 (1.923-1.969) | 1.953 (1.925-1.966) | 1.954 (1.917-2.005) | 1.945 (1.921-1.986) | 1.365/1.373/1.382/1.371 |
| cli | cold-all | 4.337 (4.298-4.377) | 4.417 (4.387-4.447) | 4.367 (4.302-4.411) | 4.418 (4.389-4.459) | 3.678/3.759/3.705/3.764 |
| small | cold-obj | 0.103 (0.100-0.108) | 0.101 (0.098-0.103) | 0.103 (0.102-0.106) | 0.100 (0.096-0.104) | 0.058/0.055/0.060/0.054 |

With `--debug`, without the daemon:

| target | case | base run 1 | change run 2 | base run 3 | change run 4 | cc_s 1/2/3/4 |
|---|---|---|---|---|---|---|
| cli | nochange | 0.591 (0.577-0.628) | 0.586 (0.574-0.598) | 0.589 (0.583-0.605) | 0.586 (0.576-0.600) | 0.000/0.000/0.000/0.000 |
| cli | body-cname | 0.772 (0.766-0.795) | 0.740 (0.723-0.747) | 0.770 (0.755-0.802) | 0.737 (0.726-0.760) | 0.098/0.076/0.097/0.076 |
| cli | body-typecheck | 0.810 (0.791-0.831) | 0.779 (0.766-0.798) | 0.825 (0.808-0.855) | 0.784 (0.767-0.800) | 0.058/0.037/0.058/0.037 |
| cli | pubfn-cname | 0.776 (0.771-0.855) | 0.751 (0.730-0.826) | 0.783 (0.765-0.858) | 0.750 (0.734-0.838) | 0.098/0.076/0.098/0.076 |
| cli | privfn-cname | 0.777 (0.773-0.794) | 0.756 (0.737-0.770) | 0.774 (0.763-0.798) | 0.748 (0.725-0.756) | 0.099/0.076/0.097/0.077 |
| cli | pubfn-typecheck | 0.831 (0.817-0.849) | 0.795 (0.779-0.811) | 0.833 (0.810-0.849) | 0.803 (0.781-0.812) | 0.050/0.029/0.050/0.029 |
| cli | privfn-typecheck | 0.829 (0.816-0.845) | 0.792 (0.782-0.805) | 0.827 (0.813-0.844) | 0.797 (0.779-0.823) | 0.051/0.028/0.051/0.028 |
| cli | testblock-cname | 0.663 (0.653-0.755) | 0.655 (0.644-0.748) | 0.667 (0.653-0.775) | 0.652 (0.642-0.752) | 0.000/0.000/0.000/0.000 |
| cli | global-cname | 0.770 (0.761-0.782) | 0.749 (0.731-0.772) | 0.773 (0.765-0.791) | 0.741 (0.721-0.767) | 0.097/0.075/0.098/0.076 |
| cli | run-body-cname | 0.780 (0.766-0.816) | 0.747 (0.733-0.767) | 0.768 (0.742-0.782) | 0.739 (0.724-0.757) | 0.097/0.076/0.098/0.076 |
| cli | cold-obj | 1.526 (1.509-1.583) | 1.343 (1.319-1.412) | 1.526 (1.510-1.570) | 1.342 (1.328-1.413) | 0.905/0.727/0.910/0.730 |
| cli | cold-all | 3.936 (3.901-3.957) | 3.814 (3.790-3.837) | 3.930 (3.900-3.966) | 3.813 (3.779-3.837) | 3.229/3.124/3.228/3.130 |
| small | nochange | 0.057 (0.054-0.059) | 0.055 (0.053-0.058) | 0.058 (0.056-0.060) | 0.054 (0.053-0.057) | 0.000/0.000/0.000/0.000 |
| small | body-inventory | 0.105 (0.101-0.118) | 0.088 (0.080-0.102) | 0.106 (0.102-0.117) | 0.081 (0.079-0.100) | 0.042/0.021/0.043/0.020 |
| small | body-audit | 0.100 (0.097-0.103) | 0.077 (0.076-0.080) | 0.100 (0.096-0.103) | 0.078 (0.074-0.079) | 0.038/0.016/0.039/0.017 |
| small | pubfn-model | 0.105 (0.099-0.107) | 0.078 (0.077-0.079) | 0.105 (0.101-0.110) | 0.079 (0.078-0.084) | 0.040/0.018/0.040/0.018 |
| small | privfn-model | 0.102 (0.099-0.108) | 0.079 (0.077-0.081) | 0.102 (0.100-0.104) | 0.080 (0.077-0.086) | 0.039/0.017/0.040/0.018 |
| small | testblock-model | 0.059 (0.057-0.061) | 0.058 (0.057-0.060) | 0.058 (0.056-0.062) | 0.058 (0.054-0.064) | 0.000/0.000/0.000/0.000 |
| small | run-body-inventory | 0.106 (0.104-0.108) | 0.083 (0.081-0.089) | 0.106 (0.103-0.108) | 0.083 (0.081-0.085) | 0.042/0.021/0.043/0.021 |
| small | cold-obj | 0.125 (0.122-0.128) | 0.101 (0.096-0.117) | 0.125 (0.123-0.131) | 0.102 (0.098-0.105) | 0.067/0.060/0.066/0.061 |

Each debug edit row that compiles a unit drops by 21-22 ms of cc time,
which is the share the replay measured; cli `--debug` edit rows drop by
21-41 ms, small ones by 17-27 ms. The `--debug` cli cold-obj drops by
0.18 s, as its cc time does, and small cold-obj by 24 ms. Each
`test-body` row through the daemon drops by 21-24 ms. Rows that compile
no unit do not move.

Two sets of rows are slower beyond their spread:

- cli cold-all, 50-85 ms, with and without the daemon. Each cold-all
  builds the archive. `monolith.o` now holds the twelve bodies as
  extern functions, where before they were unused statics that gcc
  dropped. The same `monolith.c` at `-O2`, 7 compiles with each header
  in turn: 2.31-2.34 s with the base `runtime.h`, 2.38-2.40 s with the
  new one, and 27 KB more object. A dev or installed archive is built
  once per compiler and runtime, so an edit loop does not pay this.
- cli edit rows through the daemon, 5-32 ms. Two more runs swap binary
  and tree. The base binary on tree `ea6f6079` gave body-cname 0.445
  (0.416-0.451) and body-typecheck 0.474 (0.464-0.488); the change
  binary on tree `e194f4aa` gave 0.439 (0.429-0.448) and 0.470
  (0.461-0.481). Each lands between base and change, so the swap does
  not show whether the binary or the larger tree costs the time, and
  the other cli edit rows of the two runs move up to 18 ms either way.
  The small rows, whose tree is the same, do not move beyond their
  spread. Cold-all follows the tree: 4.560
  (4.546-4.583) for the base binary on the new tree, 4.473
  (4.451-4.504) for the change binary on the base tree.
  `bench/edit_loop/unit_rt_statics_cross_*.tsv` hold these two runs.

### Units kept across a trait or annotated fn edit

Before this change, an edit in a module other than the entry that added,
removed or changed a trait, or a fn with an annotation, made the build
take no unit: each was an item of kind `other`. Each kind, added once to
`src/cname.bl` on cli under `BLINK_EMIT_REUSE_VERIFY=1`, with the gen1
from before this change (sha256 `cb965d31…`): every one took 0 of 69
units, and the median of 5 edits through the daemon, settle 1 s, was
0.82-0.97 s. A private body edit took 51 units and cost 0.438 s.

| kind | units changed | headers changed | median s |
|---|---|---|---|
| nochange | - | - | 0.149 |
| fn under `@allow`, `@deprecated`, `@trusted` or `@pure` | 1 (`cname`) | `cname.priv.h` | 0.890-0.919 |
| fn under `@requires`, `@ensures` or `@verify` | 1 (`cname`) | `cname.priv.h` | 0.943-0.953 |
| fn under `@src`, `@modifies`, `@tags` or `@inline` | 1 (`cname`) | `cname.priv.h` | 0.957-0.966 |
| fn under `@ffi` | 1 (`cname`) | `cname.priv.h` | 0.963 |
| pub fn under `@allow` | 1 (`cname`) | `cname.h` | 0.963 |
| annotation added to a fn that exists | 1 (`cname`) | 0 | 0.827-0.830 |
| trait, any shape below | 0 | 0 | 0.821-0.851 |
| body edit | 1 (`cname`) | `cname.priv.h` | 0.438 |

An `@ffi` binding over a symbol a native dependency gates changes 68
units and `blink.types.h`, since the gates reach every unit. `@where` on
a fn does not parse today.

#### Annotated fns

The parser marks a fn with its name and the name of each annotation over
it (`fn <name> @<a>...`), and marks each annotation's own item
`ann <a> fn <name>`. So an edit to an annotation's arguments alone is an
edit of the fn's name, as is an annotation added or removed. The build
then emits again each unit whose sources name the fn, as for a fn with no
annotation, but only when each annotation over the fn is one that acts
inside the fn or at the calls that name it (`annotation_is_local` in
`src/emit_record.bl`). Any other takes no unit.

| annotation | takes units | why |
|---|---|---|
| `@allow` | yes | changes which warnings show; prints no C |
| `@deprecated` | yes | a warning at each call, which names the fn; prints no C |
| `@trusted` | yes | an audit check; prints no C |
| `@pure` | yes | a check of the fn's body; prints no C |
| `@modifies` | yes | reserved for a solver; read by no stage today |
| `@requires`, `@ensures` | yes | the checks print in the fn's own body (below) |
| `@verify` | yes | only `contract_runtime` reads it, for the fn's own body |
| `@src` | yes | read by no stage after the parser |
| `@ffi` | yes | changes the fn's own wrapper and each call that names the fn; a gated symbol changes `blink.types.h`, and that takes no unit |
| `@tags` | no | `src/cg.bl` writes the test table of the entry unit from it |
| `@expect_panic` | no | the parser rewrites the body of the test that holds it |
| `@where` | no | does not parse on a fn today |
| `@invariant` | no | no rule yet shows where its checks print |
| `@derive`, `@ffi.opaque`, `@ffi.struct` | no | type annotations; their items are types, which stay `other` |
| any other | no | a new reader could reach any unit |

`@requires` and `@ensures` print no C outside the fn they are on, in
any mode:

- `src/cg_stmt.bl` alone lowers them. `contract_entry` runs from the
  lowering of the fn's own body and prints the `@requires` checks and
  the `old(e)` snapshots. `cs_exit_ensures` holds the `@ensures`
  predicates, and the exit checks print at that body's returns.
- `contract_runtime` decides whether the checks print. It reads only
  `@verify(fallback: ...)` of the same fn.
- `CgConfig` has no contract flag. `--debug` sets `-g -O0` and the
  `debug_assert` bodies; `--release` sets `-O2`. No flag changes where a
  contract prints, and any flag change already takes no unit.
- `mono` walks the predicates (`src/mono.bl`) inside the fn's own
  instance. An instance of a generic of another module that a predicate
  makes lands in that generic's unit and adds a line to its header; the
  build sees the header change and emits that unit again.
- No caller reads them. Codegen reads by name only `@ffi`,
  `@ffi.opaque`, `@ffi.struct` and `@verify`
  (`rg 'get_annotation\(' src/cg*.bl src/mono.bl src/layout.bl
  src/cname.bl src/ir.bl`). `cc_forwarded_binding` declines when an
  impl method has an annotation, and an impl is an item of kind `other`.

`@ffi` reaches callers by name. `c_fn_decl_name` gives an `@ffi` fn the C
name `blink_<name>`, and `c_ffi_symbol` reads the symbol for the fn's own
wrapper. A call names the fn's Blink name, so a unit with such a call
names the fn in its source and is emitted again.

Warnings and errors on the take path match a cold build. Typecheck runs
on the whole program on every build, and a taken unit repeats the
warnings of its last emit. The annotated fn test checks the warnings of
each warm build against a cold build: `@deprecated` added in one module
with its warning at a call in another, `@trusted` removed from a pub
`@ffi` fn (refused: `PubFFI`), a private `@ffi` fn with no `@trusted`
(`UnauditedFFI`), and a `@pure` fn that calls a fn of another module
that is not pure (refused: `ImpureBodyForPureAnnotation`).

#### Traits

The parser marks a trait with no annotation over it, and none on a
method, with its name, its methods' names and its associated types'
names. A trait prints no C. It reaches a unit through an impl of it, a
bound that names it, and a call of one of its methods, and a source that
does one of these writes one of the names. So an edit to such a trait is
an edit of each of those names. A trait with an annotation stays
`other`, since an annotation can change what the trait lowers to.

A trait the compiler reads by name takes no unit. A unit can dispatch
through such a trait from a source that never writes its name: `==`
reads `Eq`, interpolation reads `Display`, `+` reads `Add`, `with` reads
`Closeable`. `tc_builtin_trait_names` in typecheck gives the names:
every trait of a prelude module, and a list for the std traits it reads
by name outside the prelude (`From`, `TryFrom`, `Into`, `IntoIterator`,
`Add`, `Sub`, `Mul`, `Div`, `Rem`, `Neg`, `Serialize`, `Iterator`). A
user trait with one of these names takes no unit either.

`test_a_trait_name_the_compiler_reads_is_on_the_list_whose_edit_takes_no_unit.bl`
reads the compiler's sources and fails when a source reads a trait by a
name on neither list: a string literal equal to a std trait, a literal
compared with a binding whose name holds `trait`, or a name pushed onto
`tc_trait_names`. A name built at run time is not seen, so the check is a
lower bound. Four mutants turn it red: `Add` or `Serialize` dropped from
the list, a std trait literal (`FloatPure`) added to `src/cg_call.bl`,
and `trait_name == "Default"` added there.

An edit to the body of a default method changes no interface text, so
the build treats it as a body edit. No impl falls back to a default body
today.

#### Sweep

Through the daemon on cli under `BLINK_EMIT_REUSE_VERIFY=1`, each kind
was added at the end of `src/cname.bl`, `src/ir.bl` and
`src/diagnostics.bl`, then changed, then undone, and each build checked
against a cold emit. Of 239 builds, each served by the daemon, 238 were
byte-equal to a cold emit. The one that failed was a default method added
to a trait that an impl implements: typecheck refuses it, since no impl
falls back to a default method yet. The first pass added the annotation
to an existing fn only in `cname.bl`; a second pass added it in `ir.bl`
and `diagnostics.bl`.

| kind | change | units taken |
|---|---|---|
| fn under `@allow`, `@deprecated`, `@trusted`, `@pure`, `@requires`, `@ensures`, `@verify(fallback: "trust")`, `@src`, `@modifies`, `@ffi` (one with a header of its own too) | an argument | 51 |
| pub fn under `@allow` | an argument | 51 |
| `@allow` or `@deprecated` added to the first pub fn | an argument | 49 (`cname`), 50 (`ir`), 42 (`diagnostics`) |
| trait, pub trait, trait with a supertrait, trait and a generic fn bound by it | a method parameter; the supertrait | 42-43 |
| trait with a default method | the default body | 34; 51 for the body edit |
| generic trait, trait with an associated type | a method parameter; the type's name | 6 |
| fn under `@tags` or `@inline` | an argument | 0 |
| trait under `@deprecated`, trait named `Debug` | a method parameter | 0 |

A trait method named `get` takes 6 units: most sources write `get`. A
trait that another module implements and a third calls through a bound
(`ProbeImpl` in `diagnostics.bl`, an impl in `cname.bl`, a generic call
in `emit_record.bl`) took 41 units after a method parameter rename and
after a supertrait added, and emitted the three units again each time.

Four mutants of the change check the tests. `BLINK_EMIT_REUSE_VERIFY`
stays green under each, and a took list fails:

- every annotation counted local: the annotated fn test fails;
- the builtin trait list empty: the trait test fails;
- a trait edit adds no name: the trait test fails;
- an annotated fn adds no name: the annotated fn test fails.

#### Bench

Through the daemon, settle 1 s, 11 reps, median seconds (min-max). Base
and the change ran in turn: base, change, base, change. Base is gen1 of
`edcc77ef` (sha256 `cb965d31…`), the change is gen1 of `b9c0c51b`
(sha256 `187d257a…`), each built by `task gen1`.
`bench/edit_loop/trait_annotated_fn_daemon_settle1_*.tsv` hold the full
rows. Every C hash check reads 11/11.

`trait-<module>` adds a trait with one method to the end of the module,
so its C is the warm C. `annfn-<module>` adds a private fn under
`@deprecated` to the end of the module.

| target | case | base run 1 | change run 2 | base run 3 | change run 4 |
|---|---|---|---|---|---|
| cli | nochange | 0.144 (0.139-0.161) | 0.149 (0.145-0.160) | 0.145 (0.139-0.156) | 0.149 (0.141-0.158) |
| cli | body-cname | 0.412 (0.400-0.424) | 0.410 (0.397-0.416) | 0.412 (0.389-0.425) | 0.406 (0.395-0.417) |
| cli | body-typecheck | 0.446 (0.430-0.468) | 0.434 (0.420-0.463) | 0.444 (0.436-0.465) | 0.443 (0.428-0.451) |
| cli | pubfn-cname | 0.444 (0.433-0.547) | 0.446 (0.438-0.557) | 0.444 (0.437-0.561) | 0.437 (0.433-0.554) |
| cli | privfn-cname | 0.453 (0.442-0.474) | 0.448 (0.438-0.454) | 0.451 (0.443-0.456) | 0.442 (0.433-0.452) |
| cli | pubfn-typecheck | 0.471 (0.452-0.483) | 0.464 (0.442-0.478) | 0.467 (0.456-0.478) | 0.450 (0.441-0.470) |
| cli | privfn-typecheck | 0.472 (0.457-0.481) | 0.465 (0.458-0.474) | 0.471 (0.459-0.481) | 0.458 (0.450-0.475) |
| cli | testblock-cname | 0.291 (0.274-0.432) | 0.279 (0.274-0.421) | 0.287 (0.277-0.417) | 0.298 (0.278-0.432) |
| cli | trait-cname | 0.832 (0.817-0.841) | 0.275 (0.266-0.282) | 0.821 (0.813-0.835) | 0.296 (0.290-0.303) |
| cli | annfn-cname | 0.998 (0.986-1.015) | 0.432 (0.424-0.442) | 0.988 (0.979-1.024) | 0.464 (0.457-0.468) |
| cli | global-cname | 0.455 (0.441-1.004) | 0.441 (0.433-0.456) | 0.455 (0.437-0.998) | 0.456 (0.446-0.466) |
| cli | run-body-cname | 0.446 (0.434-0.456) | 0.445 (0.438-0.457) | 0.433 (0.428-0.452) | 0.450 (0.432-0.457) |
| cli | test-body-cname | 0.450 (0.437-0.470) | 0.452 (0.446-0.470) | 0.452 (0.443-0.475) | 0.457 (0.445-0.468) |
| cli | cold-obj | 1.614 (1.577-1.719) | 1.613 (1.589-1.698) | 1.604 (1.569-1.686) | 1.616 (1.592-1.702) |
| cli | cold-all | 4.548 (4.520-4.584) | 4.553 (4.529-4.578) | 4.561 (4.535-4.594) | 4.579 (4.560-4.606) |
| small | nochange | 0.046 (0.043-0.047) | 0.043 (0.042-0.045) | 0.044 (0.042-0.045) | 0.044 (0.042-0.047) |
| small | body-inventory | 0.078 (0.075-0.091) | 0.077 (0.075-0.092) | 0.078 (0.074-0.093) | 0.079 (0.076-0.091) |
| small | body-audit | 0.066 (0.064-0.070) | 0.066 (0.063-0.069) | 0.065 (0.064-0.068) | 0.067 (0.064-0.068) |
| small | pubfn-model | 0.070 (0.068-0.072) | 0.069 (0.067-0.073) | 0.069 (0.068-0.072) | 0.069 (0.068-0.072) |
| small | privfn-model | 0.069 (0.067-0.074) | 0.069 (0.067-0.071) | 0.070 (0.067-0.072) | 0.068 (0.066-0.074) |
| small | testblock-model | 0.048 (0.045-0.050) | 0.049 (0.047-0.050) | 0.048 (0.047-0.050) | 0.049 (0.047-0.051) |
| small | trait-model | 0.053 (0.051-0.055) | 0.049 (0.047-0.051) | 0.053 (0.050-0.054) | 0.048 (0.046-0.051) |
| small | annfn-model | 0.074 (0.070-0.078) | 0.070 (0.068-0.073) | 0.073 (0.071-0.076) | 0.069 (0.067-0.072) |
| small | run-body-inventory | 0.080 (0.077-0.082) | 0.079 (0.076-0.082) | 0.079 (0.077-0.083) | 0.078 (0.075-0.080) |
| small | test-body-inventory | 0.081 (0.077-0.097) | 0.080 (0.078-0.100) | 0.080 (0.078-0.101) | 0.081 (0.079-0.099) |
| small | cold-obj | 0.089 (0.086-0.094) | 0.091 (0.089-0.096) | 0.091 (0.090-0.094) | 0.091 (0.090-0.093) |

On cli a new trait now costs less than a body edit, since no unit
changes: 0.82-0.83 s drops to 0.28-0.30 s. A new annotated fn costs what
a new private fn costs: 0.99-1.00 s drops to 0.43-0.46 s. On small the
trait row drops from 0.053 s to 0.048-0.049 s, below the base spread in
both pairs. The annotated fn row drops by 4 ms, below the base spread in
run 4 only.

No row reads slower than the base run before it, outside its spread. In
run 4, `privfn-cname`, `pubfn-typecheck` and `privfn-typecheck` on cli
read 8-17 ms faster than base run 3, below its spread. Run 2 does not
show this, so the change does not explain it.

## Blockers before the default flipped

None from the edit-loop bench: `nochange` on cli is faster than the
monolith, and no per-module case is slower than before outside its spread.

## Exit criteria on main 85653d77

Measured 2026-10-12 on main 85653d77 (gen0 selfhost-15) with the gen1
blink of that tree (sha256 c7c8201a687cb03d...), gcc 16.2.1, all runs in
blink-gates.slice (12 CPUs) after the load fell below 3. Each bench row is a
median of 5. (1)-(5) come from `scripts/bench_edit_loop.sh build/gen1/bin/blink`,
once with no daemon and once with `BENCH_DAEMON=1 BENCH_SETTLE=1`.

(6) is the output-speed job: each build of src/cli.bl runs
`setarch -R <bin> build --emit c src/blinkc_main.bl`, under `perf stat -e
cycles:u,instructions:u` and `/usr/bin/time -f %M`, with the 4 binaries
alternating 5 times per set and 3 sets. The default -O1 build made 69 units: 52
modules plus 17 typecheck split units (typecheck.p<hex8>.c and
typecheck.pos.c). `--release` splits nothing and made 52. The emitted C was
byte-equal in each run. The main-thread set uses `perf stat -i` and no time
wrapper, so its maxrss_kb column reads 0 and is not a measurement.

| criterion | bar | value | result | file |
|---|---|---|---|---|
| (1) cli private-body edit | <= 1.0 s | 0.733 s, daemon 0.412 s | pass | exit_criteria_85653d77.tsv, exit_criteria_daemon_settle1_85653d77.tsv |
| (2) cli new pub fn | <= 2.0 s | 0.739 s, daemon 0.440 s | pass | same |
| (3) small body / pub fn edit | <= 0.3 s | 0.088 / 0.079 s, daemon 0.082 / 0.072 s | pass | same |
| (4) cli `blink test` after a body edit | order of (1) | 0.416 s, daemon 0.457 s | pass | same |
| (5) cli cold build | <= 6.0 s | cold-all 4.380 s, daemon 4.570 s | pass | same |
| (5) cli no-change build | <= 0.8 s | 0.516 s, daemon 0.149 s | pass | same |
| (6) output speed -O1, cycles:u | <= +3% | +0.65, +0.66, +2.25% per set; +1.26% pooled; main thread +1.98% | pass | exit_criteria_output_speed_run{1,2,3}_85653d77.tsv, exit_criteria_output_speed_main_thread_85653d77.tsv |
| (6) output speed -O2, cycles:u | <= +3% | +2.54, +3.87, +1.33% per set; +2.54% pooled (paired +2.59%); main thread +1.74% | open: per set of 5, 2 pass and 1 misses; pooled and main thread pass | same |
| (6) instructions:u, -O1 / -O2 | - | +0.40 / +1.45% pooled | - | same |
| (6) maxRSS, -O1 / -O2 | - | -0.04 / -0.25% pooled | - | same |
| (7) `task ci` wall, median of 3 on 85653d77 | <= 117.6 s | 117.69 s (117.69, 117.56, 117.91); be33d1c9 (docs only) 118.18 s | miss by 0.09 s | gate logs |
| (7) per-module invariants | green | `task ci-per-module-checks` exit 0 | pass | gate log |
| (8) open P1/P2 obj-cache or daemon correctness bug | none | no open bug gives wrong C from the daemon or the obj cache; two make a daemon check print less than a cold check | open | br sweep |

The spread of cycles:u within one set is 2-4%, so one set can read over the
bar when the pooled median does not. Instructions:u match the last
measurement on 318110b0 (+0.43 / +1.42%).

The (7) miss comes from the corpus, not from load: the slowest run started at
a 1-minute load of 0.38. Since ee06e160 (113.65 s) the corpus grew from 2136
to 2195 files and the per-module slice from 184 to 224 rows. The corpus sweep
takes 103-104 s of the wall.

For (8), two open P2 bugs make a daemon check print less than a cold check: a
W1000 printed to stdout, and an unknown-escape warning from the lexer. Neither
goes through the diagnostics. The 9 corpus tests that compare a daemon build
or check with a cold one passed in each gate. Two open P2 cache bugs give no
wrong output: `blink test --no-cache` still uses the obj cache in its parallel
workers, and a vendored native-dep object is reused across build modes.
