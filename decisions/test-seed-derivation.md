# Test Seed Derivation — Reference

> `br h0ha00`

**Status:** Reference for *locked-but-pending* behavior. The derivation formula is
locked by panel decision (see [`test-seed-determinism.md`](test-seed-determinism.md),
committed `19962b5`), but the implementation is **not yet shipped**: SipHash-2-4,
`MockRand`, `prop_check`, and `blink test --seed` are tracked by br `cvghhp` and remain
pending. The codebase currently uses FNV-1a for map hashing; nothing in this document
describes shipped behavior. Treat numeric outputs below as **illustrative** until the
implementation lands and golden values can be pinned.

- **Rationale / panel decision:** [`test-seed-determinism.md`](test-seed-determinism.md)
- **Implementation tracking:** br `cvghhp`

This is a technical reference for hand-computing a per-property seed offline so a failure
can be reproduced without rerunning the runner. It is intentionally flat (formula + worked
example); it is **not** a decision record.

## The formula

```
per_property_seed = splitmix64(suite_seed XOR siphash24(property_name))
```

- The SipHash-2-4 input is the **bare property name** — no module prefix. This keeps the
  derived seed stable under module renames.
- Duplicate property names within a module are a **runner error**: the derivation would
  collide silently otherwise.

(Locked at [`test-seed-determinism.md`](test-seed-determinism.md), "Sub-seed derivation".)

## `suite_seed`

The suite seed is supplied by `blink test --seed <u64>`:

- Accepts either `0xHEX` or decimal input.
- Printed back as `0x` followed by 16 zero-padded hex digits (e.g. `0x000000000000002a`).
- When `--seed` is omitted, the runner picks an entropy-seeded default. The chosen seed is
  surfaced in the seed banner and the rerun line of **every** failure-output mode, so any
  failure is reproducible by copying the printed seed back into `--seed`.

## `splitmix64`

The seed-derivation mixer is the splitmix64 finalizer. It already exists in the runtime as
`blink_kops_mix_u64` ([`../bootstrap/runtime_core.h:732-742`](../bootstrap/runtime_core.h)).
The constants and shift amounts below are reproduced **verbatim** from that function and are
the contract for hand-computation:

```
splitmix64(x):              # x is a u64; all ops are mod 2^64
    x = x XOR (x >> 30)
    x = x * 0xbf58476d1ce4e5b9
    x = x XOR (x >> 27)
    x = x * 0x94d049bb133111eb
    x = x XOR (x >> 31)
    return x
```

Shifts: 30, 27, 31. Multipliers: `0xbf58476d1ce4e5b9`, `0x94d049bb133111eb`. Multiplication
wraps at 64 bits (unsigned overflow). This is the *seed-derivation mixer only* — it is not
the per-test random stream (see [Out of scope](#out-of-scope)).

## `siphash24`

SipHash-2-4 provides a stable identity for the property name. It is **not yet implemented**;
the construction is pinned here because br `cvghhp` flags that `siphash24` must be stable
across compiler versions or the sub-seed reproducer breaks. The future implementation must
honor this contract:

- **Algorithm:** SipHash-2-4 — the canonical construction by Aumasson & Bernstein
  (2 compression rounds per message block, 4 finalization rounds). Canonical spec:
  <https://www.aumasson.jp/siphash/siphash.pdf>.
- **Input message:** the UTF-8 bytes of the bare property name.
- **Key:** a fixed 128-bit key compiled into the runner. Because the derived seed must be
  reproducible across compiler versions, this key is a **frozen constant**, not
  per-build/per-run entropy. (The exact key bytes are pinned when the implementation lands;
  this doc is updated with the value at that time.)
- **Output:** the 64-bit SipHash-2-4 tag, used directly as the `siphash24(property_name)`
  term in the formula.

Stability requirement: a given `(property_name)` must map to the same 64-bit tag forever.
Any change to the algorithm, key, or input encoding breaks every persisted sub-seed
reproducer and is a breaking change.

## Worked example

The values below are **illustrative** — they show the procedure, not pinned golden output
(the `siphash24` term cannot be pinned until the implementation and its frozen key land).

Given:

```
suite_seed     = 0x000000000000002a        # i.e. --seed 42
property_name  = "reverse_is_involutive"
```

Steps:

1. `h = siphash24("reverse_is_involutive")`
   → a 64-bit tag from the frozen-key SipHash-2-4. Call it `<siphash_tag>`
   (the concrete value is pinned only once the implementation and its key land).
2. `mixed_in = suite_seed XOR h`
   → `0x000000000000002a XOR <siphash_tag>`.
3. `per_property_seed = splitmix64(mixed_in)`
   → apply the five splitmix64 steps above to `mixed_in`.

The result is the u64 fed to the per-property random stream for that property. To reproduce
a single property's failure offline, compute this value and seed the stream PRNG with it.

## Out of scope

This document covers only the **seed derivation** (`splitmix64` + `siphash24`). The following
are deliberately excluded:

- **Stream PRNG** — the per-test random number stream is `xoshiro256**` in v0.1, but the
  algorithm is **implementation-defined** and not part of this contract
  ([`test-seed-determinism.md:141`](test-seed-determinism.md)). Do not rely on it for offline
  reproduction beyond "seed it with `per_property_seed`".
- **`MockRand` controller mechanics** — handler binding, `.draws()`, op semantics. See br
  `cvghhp` and [`test-seed-determinism.md`](test-seed-determinism.md).
