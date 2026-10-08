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

## Path to default

The eventual flip makes the per-module path the default for
`blink build` / `blink run` (link-only fast path on warm `.o` cache),
with monolith reachable via an explicit flag. The wins:

- **cc warm-cache.** Per-module `.o` caching (`per-module-o-cache.md`)
  means an incremental build recompiles only the changed module's `.c`
  and re-links. The monolith path recompiles the whole program every
  time.
- **link-only fast path.** When nothing changed, the build is a pure
  link of cached `.o` files — no `cc -c` at all.
- **archive monolith stays for stdlib.** The stdlib is already a
  pre-built archive; per-module program emit composes with it unchanged.

## `--per-module` for `blink build`, `blink run` and `blink test`

The opt-in flag drives the per-module path end to end: emit, compile,
cache and link. The default build does not change.

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
- **Errors.** A cc failure prints the cc output, then
  `error: C compilation failed in unit <module>`, and exits 1, the same
  code as the monolith.
- **Env.** `BLINK_PER_MODULE=1` selects this path for a command that does
  not pass `--per-module`, and so does every `blink` that the program starts.
  `0` or unset keeps the default. Any other value is an error.
- **Fallback.** `--emit c`, `--format blink`, `BLINK_SKIP_MODULES`,
  `BLINK_ONLY_MODULE` and `BLINK_COMPILER_ARCHIVE` build one C unit. When
  `--per-module` asked for the path, the build prints
  `note: --per-module ignored: <reason>`. When only `BLINK_PER_MODULE`
  asked, it prints nothing. `--target` uses the per-module path.
- **Corpus.** `task corpus-per-module` builds every `tests/test_*.bl` on this
  path with no compiler archive, and `task ci-release` runs it. See the
  per-module corpus in `docs/codegen-rewrite/harness.md`.
- **Trace.** `BLINK_TRACE_CHANNELS=build.units` prints `hit <module>` or
  `compile <module>` for each unit.
- **Tests.** `blink test <file> --per-module` builds the program under test
  on this path, at the debug flags `blink test` always uses. The test bodies,
  the runner and `main` are in the `__main__` unit; each imported module is a
  unit of its own. The runner state is one set per binary and per thread
  (`BLINK_TEST_STORAGE` in `runtime_test.h`), so an assert that fails in
  another unit reports a test failure and the next test runs. For a
  directory, `blink test` passes `--per-module` and `--jobs` to the build of
  each test file, and each build runs up to `--jobs` compiles of its own.
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
- `nochange` on cli is still 0.19 s slower than the monolith. All of it
  is emit (`emit_s` 0.905 against 0.725): the build still emits 131
  headers and 49 units each time, then hashes them to find that nothing
  changed.

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

## Blockers before the default flips

Tracked separately: cut the per-build emit cost on a large program, so that
`nochange` is not slower than the monolith. The two ways out are a front-end
input fingerprint that skips the emit when no input changed, or a header
snapshot so that the emit does not write the typedefs again each time.

