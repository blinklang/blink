# Generic monomorphization ownership under per-module .o

## Context

The per-module `.o` migration (project `tc83pp`) splits the program into
one `.o` per module instead of one fat `.c`. Generic monomorphizations
(`List[Int]`, `Map[K, V]`, user `box_make[T]`, etc.) live in a
program-global `mono_fns` / `mono_instances` table populated as the
type checker resolves call sites. Under per-module emit, every module's
`.c` walks that global table and re-emits the monos it instantiates,
which without further care produces duplicate non-`static` C symbols
across `.o` files and breaks the link.

This decision picks the ownership policy. Three options were on the
table — recorded here so future contributors don't re-litigate.

This is a codegen-internal mechanism decision — no `/deliberate` panel
needed. It documents the policy the existing codegen already implements
(commit `1da102b` for fns; `BLINK_TD_*` typedef guards predate that for
struct typedefs) and the test surface that protects it.

## Decision: hybrid (stdlib in archive, user monos `static inline`)

Two disjoint mono populations, two different storage strategies.

### Stdlib monos → archive monolith

Generic instantiations whose generic definition lives in `lib/std/`
(`List[Int]`, `Option[Result[Json, JsonError]]`, etc.) emit **exactly
once**, into the archive's `monolith.o`. Peeled archive `.o` files and
all user `.o` files emit **zero** stdlib instantiations and link against
the monolith's symbols as `extern`.

This rule predates the per-module project and is documented in
`stdlib-archive-symbol-policy.md` § "Generic monomorphizations are owned
by the monolith `.o`". Per-module emission inherits it unchanged.

### User monos → emitted per-module as `static inline` / TD-guarded typedef

Generic instantiations of user-defined generics emit into **every**
user `.o` that instantiates them, with internal linkage so the linker
quietly merges duplicates:

- **Generic fn definitions** prepend `static inline ` whenever
  `in_per_module_object()` is true. The forward-decl carries the same
  storage class. Implemented in `mono_storage_class` at
  `src/codegen_stmt.bl:3683`. Whole-program (single TU), archive
  monolith, and shared-header passes all keep the extern default.
- **Generic struct typedefs** wrap output in a `BLINK_TD_<mangled>`
  `#ifndef`/`#define` guard via `emit_td_guard_open` at
  `src/codegen_types.bl:4503`. Typedefs aren't link symbols, so
  duplication across `.o` is harmless; the guard only protects the
  same TU from emitting the typedef twice when multiple call sites
  pull it in.
- **Mono fn declarations are NOT emitted into shared headers** (archive
  header or per-module header). Only generic fn *defs* flow through
  `flush_mono_fns_with_typedefs` at `src/codegen.bl:1324`, gated by
  `is_generic_fn(fn_name) == 0`. So per-module `.c` files'
  `static inline` definitions never clash with an `extern` proto in an
  included aggregator header.

### Why hybrid and not the alternatives

**Why not (A) pure per-module duplication with module-keyed mangling**:
the mangler would have to consult the *instantiator's* module name. But
the same `Box[Int]` requested from two user modules must still merge —
they're the same type. Source-module-keyed mangling would *prevent*
merge and force every user TU to carry its own copy of `List[Int]`
even though they're bit-identical. That defeats the point.

**Why not (B) central `monos.o` for user code as well**: requires either
a 2-pass build (collect needs, then emit) or a manifest exchanged
between modules. Friction with incremental rebuilds and with the
"stdlib monolith owns its monos" rule already in place — there's no
clean equivalent of `monolith.o` for user code (no fixed home TU).
Hybrid keeps stdlib monolith ownership and avoids inventing a second
central TU.

### Trade-off accepted

Each user `.o` carries text-section bytes for every mono it
instantiates. If two modules instantiate `List[CustomType]`, both
`.o` files contain the function body, and the linker merges to one
copy in the final binary (internal linkage + identical bodies). Final
binaries are unchanged in size; intermediate `.o` files are larger.
`-ffunction-sections -fdata-sections` plus `-Wl,--gc-sections` strips
unused `static inline` copies the linker decided not to call.

## Verification surface

`task ci-per-module` exercises the policy end-to-end:

1. **Cross-module mono link**: `tests/multifile/src/main.bl` instantiates
   user generic fn `id[T]` (in `math.bl`) and user generic struct
   `Box[T]` from both `greet.bl` and `main.bl` with overlapping
   (`Box[Int]`) and disjoint (`Box[Str]`) type args. The per-module
   build links with no `cc` symbol-collision errors and produces output
   byte-equal to the monolith run.
2. **Self-host**: `src/cli.bl` per-module-built compiler typechecks
   the same fixture — exercises the policy on real-world generic use.
3. **Emit determinism**: re-emitting per-module from the same compiler
   produces byte-equal `.c`/`.h`.
4. **Gen1 vs Gen2 byte equality**: per-module emit from `bin/blink` and
   from the per-module-built compiler are byte-equal — bootstrap
   fixed-point preserved.

A regression in any of the four legs trips this target, which is part
of `task ci`.

## Out of scope

- Trait/impl method monos. Methods route through the same
  `c_fn_name` / mono-table machinery and inherit the same storage class
  rules; no separate carve-out needed.
- Generic enum typedefs. Enums use the same `emit_td_guard_open` path
  as structs; the same `BLINK_TD_*` guard protects them.
- Eliminating runtime-helper duplication across user `.o`. Tracked
  separately under the post-stdlib-archive runtime extraction work.
- Cross-module dead-mono pruning. Linker `--gc-sections` is sufficient;
  no compiler-side pruning planned.
