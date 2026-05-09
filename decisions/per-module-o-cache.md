# Per-module `.o` cache

## Context

Per-module `.c`/`.h` emission already lands the *front-end* split (each
program module gets its own `.c` and `.h`, see
`generic-mono-ownership-per-module.md`). The dominant remaining cost in
`task ci` is the **back-end** step: `cc` compiling those `.c` files into
`.o` and linking them. A single test run pays for hundreds of identical
stdlib `.c` → `.o` compiles whose inputs haven't changed since the last
run.

This decision records the cache that elides that work. Closes
`br vwvvtg` and folds in `br daqhhj` (clean/info CLI surface).

This is a build-orchestrator decision — no `/deliberate` panel needed.

## Decision

Add a content-addressed `.o` cache keyed on every input that legitimately
affects the bytes of the produced `.o`. On a cache hit, skip `cc -c`
entirely and reuse the cached `.o` in the link step.

### 1. Cache key

A 16-hex SHA-256 over a deterministic manifest, mirroring
`build_stdlib.bl::compute_cache_key` (which is refactored to share a
`sha256_of_manifest(text)` helper):

```
schema:1
mod:<module_key>
src_sha:<sha256 of the module's .c source as emitted>
imports:<sorted "name=sha256-of-its-emitted-.h" lines>
runtime_sha:<sha256 of build/runtime.h>
blinkc_sha:<sha256 of the blinkc binary>
cc_id:<output of `cc --version | head -1`>
flags:<sorted, canonicalized cc flags affecting codegen: -O*, -g, -DBLINK_USE_SQLITE, etc.>
target:<--target value, or "" for native>
```

Notes:

- **`blinkc_sha` subsumes `blinkc_cli_version`.** The dev-mode literal
  `blink_cli_version = "dev"` doesn't move when codegen changes; hashing
  the binary does.
- **Transitive imports are *not* re-walked.** Each direct dep's `.h`
  already encodes its own pub surface; that surface changes iff the
  dep's `.h` content changes. Hashing direct deps' `.h` content is
  sufficient.
- **Sort import lines** before hashing so emission order can never
  affect the key.
- **`schema:1`** so a future key-format change invalidates everything.

### 2. Cache location — per-repo

Default: `build/obj-cache/`. Sibling of the existing `build/std-cache/`.
Override via `BLINK_CACHE_DIR` env var.

Layout:

```
build/obj-cache/
  <16-hex>.o
  <16-hex>.meta    # one-line: "<unix-mtime> <module_key> <src_sha>"
  tmp/             # atomic-write staging (rename into ../)
```

Per-repo, not XDG: `build/` is gitignored, easy to wipe, no shared-host
permission surprises. A fresh checkout starts cold, which keeps `task ci`
hermetic by default.

### 3. Invalidation

The key is the invalidator. There is no separate "invalidate this entry"
path — if inputs change, the key changes, and the old entry is unreferenced
and eventually GC'd.

| Change                                         | Key field                                     | Effect                            |
|------------------------------------------------|-----------------------------------------------|-----------------------------------|
| Edit `foo.bl`                                  | `src_sha` for `foo`                           | `foo.o` recompiles                |
| Edit `bar.bl`, `foo` imports `bar` (pub change) | `imports` for `foo` (via `bar.h` sha)         | `foo.o` recompiles                |
| Edit `bar.bl` private body only                | `bar.h` unchanged → `foo.o` unaffected        | minimal blast radius              |
| Rebuild compiler                               | `blinkc_sha`                                  | full rebuild                      |
| Edit `runtime.h`                               | `runtime_sha`                                 | full rebuild                      |
| Switch / upgrade cc                            | `cc_id`                                       | full rebuild                      |
| Toggle `-O2` ↔ `-O0 -g`                        | `flags`                                       | parallel cache lines coexist      |
| Cross-target build                             | `target`                                      | parallel cache lines coexist      |
| Schema bump                                    | `schema:N`                                    | full rebuild                      |

The "minimal blast radius" row is the entire reason for the per-module
`.o` switch. Without it a single private-body edit forces full rebuild.

### 4. GC — size cap, LRU by mtime

- Default cap: **2 GiB**, override via `BLINK_CACHE_SIZE_MB`.
- Trigger: opportunistic, end of run. Any `blink build`/`run`/`test`
  invocation that *added* an entry checks total size; if over cap,
  evict by oldest `.meta` mtime until under cap. No daemon, no cron.
- mtime is touched on cache *hit* (not just store) so hot stdlib `.o`s
  don't get evicted under churn from rare modules.
- Manual: `blink cache info`, `blink cache clean`,
  `blink cache clean --older-than DURATION`.

LRU-by-mtime is good enough — no need to track real access counts.

### 5. Atomic writes + concurrency

- Write `.o` to `tmp/<pid>.<rand>.o`, then `rename(2)` into `<hash>.o`.
  POSIX rename is atomic within a filesystem.
- Write `.meta` after the `.o`. A present `.o` with missing/older `.meta`
  is treated as a cache hit (still safe; just less precise GC). A
  `.meta` with no `.o` is a miss; the `.meta` is reaped opportunistically.
- Two parallel `blink test` runs that miss on the same key both compile
  and both rename — last write wins, content is byte-identical, no
  corruption. No file locks needed.

### 6. Bootstrap protocol impact

`task ci-per-module` invokes `bin/blink __emit-per-module` directly and
calls `cc` itself in the script. It does not call `do_build` and so does
not consult the cache by default. We additionally export
`BLINK_CACHE_DIR=` (empty) inside the `ci-per-module` script as
belt-and-suspenders against future drift. The cache helper short-circuits
to "always miss, never store" when the dir is empty.

We do **not** add `.o` byte-equality to the bootstrap invariant — `cc`
output isn't deterministic across `cc` versions, and we already cover
determinism at the `.c`/`.h` level which is what `blinkc` owns.

### 7. Why this works — cross-link to ownership policy

Cache hits are safe because each `.o` is self-contained at link time,
which is exactly what `decisions/generic-mono-ownership-per-module.md`
guarantees:

- Stdlib monos live in the archive `monolith.o` — never duplicated
  across user `.o`s.
- User monos emit per-module as `static inline` / `BLINK_TD_*`-guarded
  typedefs — duplication across user `.o`s is harmless because the
  linker merges identical-body internal-linkage symbols.

Without that policy, two cached `.o`s could carry conflicting external
copies of the same mono. With it, cached `.o`s compose under `cc`'s
linker exactly as freshly-built ones do.

## Out of scope

- Caching the blinkc front-end (lex/parse/typecheck). Front-end cost is
  ~10 % of warm `task ci` wall time; revisit only if a measurement says
  it matters.
- Replacing the stdlib archive with per-module stdlib `.o`s. The archive
  is its own well-trodden cache (`build/std-cache/`); the two cache
  systems coexist.
- Cross-machine cache distribution. Per-repo location intentionally
  rules out shared-host or remote caching for now.
- Eviction by access count rather than mtime. mtime-LRU is good enough
  until measurement says otherwise.
