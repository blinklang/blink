# Map Runtime Architecture: Per-K kops vtable

**Status:** Decided (2026-05-19)
**Scope:** Internal compiler architecture. Not a spec change.
**Related tickets:** h0geg9 (this), tn17vz (seed/iteration), trvwpg (migrate workarounds)

## Decision

`Map[K, V]` is implemented as a single runtime hash-map parameterized at construction
time by a per-K **kops vtable** (Go `runtime.hmap` style):

```c
typedef struct {
    uint64_t (*hash)(const void* k);
    int      (*eq)  (const void* a, const void* b);
    size_t   key_size;
    int      inline_key;   /* 1 = bytes copied into slot; 0 = pointer slot */
} blink_kops;
```

Codegen emits one `static const blink_kops` per distinct K type used in the program
and passes its address into `blink_map_new(&kops_<K>)`.

## Rejected alternatives

- **Per-(K,V) monomorphization.** Cleanest API, but balloons C compile time
  (~20% measured against current self-host). Reserved as an opt-in optimization knob,
  not a default.
- **Stringification of non-Str keys.** The current workaround. Loses type safety,
  forces `Display` on all keys, and pollutes the GC with throwaway strings.
- **Universal `void*` keys + user-supplied callbacks at every call site.** Trait
  dispatch overhead per op; ergonomically wrong; doesn't generalize to tuple keys.

## Trade-offs accepted

- ~3-5% runtime overhead on hot map ops vs monomorphized code (one indirect call
  per hash/eq). Negligible against current workload profile.
- ~20% saved on `task ci` C-compile time vs per-(K,V) monomorph.
- One runtime, one set of bugs, one place to land hash-seed plumbing for tn17vz.

## Hash functions

- Str: FNV-1a (unchanged from current runtime).
- Integers (all signed/unsigned widths): splitmix64 finalizer
  `x ^= x >> 30; x *= 0xbf58476d1ce4e5b9; x ^= x >> 27; x *= 0x94d049bb133111eb; x ^= x >> 31`.
- Struct/tuple: structural field-by-field mix, or user `@derive(Hash)` impl.

## Float keys

Rejected at typecheck (`E1301 MapKeyNotHashable`). Float does not implement Hash.
Hint: "consider rounding to Int first."

## Hash seed

Phase 5 adds `blink_map_set_seed(uint64_t)` + `--deterministic` CLI flag.
Default seed is 0 until tn17vz /deliberate ratifies the seed contract.
