# Per-module emit as the default build path

## Context

Blink's compiler can emit a program in two shapes:

1. **Monolith** — one fat `.c` for the whole program (entry + every
   reachable module), compiled and linked in a single `cc` invocation.
   This is what `blink build` / `blink run` have always done, and what
   `--emit c` writes to disk.
2. **Per-module** — one `.c` and one `.h` per program module, plus an
   aggregator header (`_blink_all.h`) that every TU includes so
   cross-module calls and typedefs resolve. Each module `.c` is compiled
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

It writes the per-module `.c`/`.h` set (plus `_blink_all.h`) into
`<outdir>`. The output target is a **directory**, not the single-file
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

## `blink build --per-module` and `blink run --per-module`

The opt-in flag drives the per-module path end to end: emit, compile,
cache and link. The default build does not change.

- **Units.** One `.c` per program module, plus one `.h` per module and
  `_blink_all.h`, written to `<output>.units/` next to the binary. The
  std modules the archive holds get no unit: the units link
  `libblink_std.a` the same as the monolith user TU does, and the archive
  defines the runtime storage and every non-generic std body. A std module
  gets a unit only for the bodies the archive cannot hold (the functions
  that take the evidence vector).
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
  once; the default is the CPU count. A value that is not a positive
  integer is an error. The largest unit starts first.
- **Object cache.** One entry per unit. The key covers the unit `.c`,
  every header it includes (the module headers, `runtime.h`,
  `libblink_std.h`, its `.gch`, vendored headers), the compiler, the cc
  id, the flags and the target. The units are written to a private
  directory, so the bytes the key hashes are the bytes cc compiles. An
  unreadable input turns the cache off for that unit, or for all units
  when the input is shared. `--no-cache` turns it off. The inputs all
  units share go into one digest that each unit's key names, and the
  hashes run in batches that fit one exec argument (Linux caps one at
  128 KiB). With the full header list in each unit's manifest, the 48
  units of `src/cli.bl` passed that cap, and every unit missed.
- **Errors.** A cc failure prints the cc output, then
  `error: C compilation failed in unit <module>`, and exits 1, the same
  code as the monolith.
- **Fallback.** `--emit c`, `--format blink`, `BLINK_SKIP_MODULES`,
  `BLINK_ONLY_MODULE` and `BLINK_COMPILER_ARCHIVE` build one C unit and
  print `note: --per-module ignored: <reason>`. `--target` uses the
  per-module path.
- **Trace.** `BLINK_TRACE_CHANNELS=build.units` prints `hit <module>` or
  `compile <module>` for each unit.

### The `_blink_all.h` cap

Every unit includes `_blink_all.h`, so every unit parses every module
header, and a change to any header recompiles every unit. A private-body
edit leaves the headers as they were and recompiles one unit. A pub
signature edit, or a new pub function, changes a header and recompiles
all units. A smaller include set per unit (only the headers of the
modules it imports) would remove this cap.

For `src/cli.bl` the cap costs most of the gain on a pub edit: 48 units
and 65 headers (7.3 MB of headers, parsed by every unit). `pubfn-cname`
recompiles all 48 units in 5.6 s, against 1.8 s for a private-body edit
to the same module.

## Edit-loop bench

`task bench-edit-loop` on the gen1 `blink` built from `67339785`, 5 reps, 12
cores, under `blink-gates.slice`. Median wall seconds;
`bench/edit_loop/monolith_67339785.tsv` and
`bench/edit_loop/per_module_67339785.tsv` hold the full rows.

| target | case | monolith | `--per-module` | per-module units compiled |
|---|---|---|---|---|
| cli | nochange | 0.752 | 1.554 | 0 |
| cli | body-cname | 10.374 | 1.780 | 1 |
| cli | body-typecheck | 10.387 | 4.050 | 1 |
| cli | pubfn-cname | 10.370 | 5.569 | 48 |
| cli | run-body-cname | 10.381 | 1.790 | 1 |
| cli | cold-obj | 10.380 | 5.874 | 48 |
| cli | cold-all | 12.780 | 8.041 | 49 |
| small | nochange | 0.074 | 0.116 | 0 |
| small | body-inventory | 0.138 | 0.161 | 1 |
| small | pubfn-model | 0.141 | 0.205 | 5 |
| small | cold-obj | 0.140 | 0.201 | 5 |

The `test-*` cases do not take the flag and stay within 0.03 s of the
monolith. What the numbers show:

- A body edit on a large program gains the most: the build compiles one
  unit, and the time follows the size of that unit (`cname.c` 0.2 s,
  `typecheck.c` 2.5 s).
- The front end and emit cost more per build (`emit_s` 0.74 s to 1.53 s
  for cli): the build writes and hashes every unit and header each time,
  so `nochange` is 0.8 s slower.
- A small program is slower on every case, by 0.02 to 0.07 s.

## Blockers before the default flips

Tracked separately: remove the `_blink_all.h` cap above, cut the per-build
emit and hash cost (`nochange` must not be slower than the monolith), and
keep a small program as fast as the monolith.
