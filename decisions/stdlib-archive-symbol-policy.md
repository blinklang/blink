# stdlib archive: symbol policy

## Context

The stdlib factoring spike (br umbrella `eyr6wf`) compiles stdlib once
into `build/libblink_std.a` and links it into every test binary
instead of having each test re-emit and re-compile the same ~1850
lines of stdlib C. Sub-project #17 nails down the symbol/linkage
rules the archive build orchestrator (#16) must follow.

This is a codegen-internal mechanism decision — no `/deliberate`
panel needed. It documents what the existing codegen already does
and what the orchestrator must respect.

## Decisions

### 1. Symbol naming follows existing codegen rules unchanged

Stdlib functions emit with the same names today as they will inside
the archive. Two conventions coexist:

- **Default**: `pub fn parse(...)` in `std.json` emits as
  `blink_std_json_parse`. Module prefix is auto-applied via
  `c_fn_name` in `src/codegen_types.bl:744`.
- **`@module("")` opt-out**: e.g. `lib/std/str.bl` and
  `lib/std/list.bl` strip the prefix. `pub fn str_len(...)` emits as
  `blink_str_len`. Symbol is namespaced only by the `blink_*` family
  prefix.

Both emit with **external C linkage** (no `static`). Trait/impl
methods follow the same rules via `c_fn_name`. The archive does
nothing special — it simply collects the same symbols the
whole-program build would have produced.

**Implication**: collisions across `@module("")` modules would silently
clobber. Today no two `@module("")` stdlib modules share a function
name. The orchestrator runs `nm libblink_std.a | sort | uniq -c` and
fails the build if any symbol appears more than once. Cheap insurance
against future stdlib additions that violate the convention.

### 2. Generic monomorphizations are owned by the monolith `.o`

Every stdlib generic instantiation (`List[Int]`, `Option[Str]`,
`Result[Json, JsonError]`, etc.) emits exactly once into
`monolith.o`. Peeled-module `.o` files emit **zero**
instantiations even when their bodies use generics — they call
into the monolith's emitted symbols.

Why: the alternative (each peeled `.o` emits the generics it uses)
produces guaranteed duplicate-symbol link errors, since two peeled
modules would both emit `blink_list_get__int_t`. The "central
monomorphization" idea was raised in the original plan and rejected
because monolith ownership is simpler and collision-free.

**Implication**: when emitting the monolith, codegen must walk the
ASTs of *peeled* modules to discover their generic uses and emit
those instantiations into the monolith. Peeled-module emission must
suppress instantiation emission entirely. Both filters already
exist (`cg_emit_only_module`, `cg_skip_modules` from sub-project
#15) — sub-project #16 adds the AST walk for cross-module mono
discovery.

Test code that instantiates stdlib generics with **test-local**
types (e.g. `List[CustomTestStruct]`) still emits its own
instantiation in the test binary. The monolith has no visibility
into test types. This is intentional and forms the negative-test
verification case for #16.

### 3. Hidden runtime helpers stay duplicated for the spike

Every emitted `.c` today contains ~300 `BLINK_UNUSED static`
runtime helpers (`blink_arena_*`, `blink_list_*`, `blink_alloc`,
etc.). They are file-scoped, so each `.o` gets its own copy with
no cross-`.o` linkage problem. The duplication is acceptable bloat
for the spike.

Post-spike cleanup: extract `runtime.o` from `bootstrap/runtime_*.h`
and have peeled `.o` and the monolith link against it instead of
inlining. Out of scope here. Tracked as the documented next step
once the archive is shipping.

### 4. Type definitions live in the shared header

`build/libblink_std.h` (emitted by the new
`generate_archive_header()` codegen entry point) contains every
typedef, struct, enum, option/result/iter type, plus `extern`
declarations for every `pub fn` and impl method, plus forward decls
for every monolith-owned generic monomorphization.

Peeled `.o` and the monolith both `#include "libblink_std.h"`
instead of the inlined runtime header. The header itself starts by
`#include`-ing the same runtime bytes (`build/runtime.h`) the
inlined path uses today, preserving byte-equivalent runtime
semantics.

### 5. Visibility / dead-code stripping

Each archive `.o` is compiled with `-ffunction-sections
-fdata-sections`. Final binaries link with `-Wl,--gc-sections`. This
lets the linker drop archive-provided symbols the binary doesn't
reference. Without this, every test binary pulls in the full stdlib
even if it only uses 3 functions — the archive's only point of
existence is to compile stdlib once, not to inflate binary sizes.

### 6. Cache invalidation

The cache key in `build/std-cache/<hash>/` is SHA256 over:

- The compiler binary hash (`build/blinkc`).
- All `lib/std/*.bl` content.
- `build/runtime.h` content.
- The cc binary's version string (`cc --version | head -1`).
- The peeled-module list (sorted, comma-joined).

Any change to any of those invalidates the cache and triggers
rebuild. The orchestrator never reuses a stale archive.

## Out of scope

- Bootstrap. `bootstrap/bootstrap.sh` keeps emitting one fat `.c` —
  the gen1/gen2 byte-equality invariant requires deterministic
  per-module ordering, which is its own project. Archive flag is
  opt-in via `--use-stdlib-archive`; bootstrap path is unaffected.
- User-code per-module emission and caching. Spike covers stdlib
  only.
- Central monomorphization `.o`. Monolith ownership is the chosen
  simplification.
- Eliminating the `BLINK_UNUSED static` runtime-helper duplication.
  Post-spike cleanup.
