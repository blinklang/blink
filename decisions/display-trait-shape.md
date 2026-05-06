[< All Decisions](../DECISIONS.md)

# Display Trait Shape — Design Rationale

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in independent-proposal → debate → vote rounds. Resolves br task `x03hn6` (dispatch mechanism for `sb.write` / `println` / format strings) which was blocking `kytpvj`.

The `Display` trait already existed (decided 5-0 to require strict impl for interpolation, see `display-format-protocol.md`), but its **shape** — single pull-style method `display() -> Str` — created two latent problems:

1. **Quadratic allocation under composition.** Recursive `display` impls (trees, ASTs, nested structs) allocate a fresh `Str` at every level, then concatenate and discard. O(n·depth) allocator pressure under Blink's manual-memory model.
2. **Hardcoded type dispatch in `sb.write`.** `src/codegen_methods.bl:754-798` switches on `CT_INT` / `CT_FLOAT` / `CT_BOOL` / `CT_STR` and falls back to `blink_sb_write` for everything else — meaning user types could never participate in the same surface. The spec gap explicitly cited this.

Four sub-questions resolved:

- **Q1:** Trait method name (`to_str` / `to_string` / `display`)
- **Q2:** Trait shape (single pull / push primary + pull derived / pull-only with codegen specialization)
- **Q3:** Whether to block on `wk9gab` (polymorphic-impl direction)
- **Q4:** Adapter location for the pull form (default method on trait / free function in stdlib)

#### Phase A — Independent proposals

- **Systems:** *"Push primary `fmt(self, sb: StringBuilder)`. Pull is a free helper `to_str(x) -> Str` in stdlib that allocates a builder, calls `fmt`, materializes. One impl point. Composition is O(n) with zero intermediate Str — that's the whole point. The pull form lives outside the trait so users can't override it into divergence with `fmt`."*
- **Web/Scripting:** *"`fmt(self, sb)` required, `to_str(self) -> Str` as a default method on the trait so `value.to_str()` works without import. Migrants from JS/Python/Kotlin reach for `.toString()` first; method-call beats free-function for discoverability. Default method, not free function."*
- **PLT:** *"Push primary preserves algebraic composition: `display` for a struct calls `display` on its fields *into the same buffer*. Pull-style forces every nested call to allocate a fresh Str, which is O(n·depth) with allocator pressure; push is O(n) in output size. The trait is `fn fmt(self, sb)`, with a derived `fn display(self) -> Str` as a default method. Naming: `display` matches the trait name and reads as 'render' rather than 'convert' — Rust's `ToString`-vs-`Display::fmt` confusion is exactly what we'd recreate with `to_str` or `to_string`."*
- **DevOps/Tooling:** *"Push-only, single method `fmt(self, sb)`. `to_string(x: T) -> Str` as a free function in stdlib — non-overridable, single source of truth. Trait surface is one method; LSP autocomplete on Display values isn't bifurcated. Migrants who reach for `.to_string()` get a method-not-found error; the diagnostic should suggest the free function."*
- **AI/ML:** *"One canonical method `fmt(self, sb)` with a free helper `display[T: Display](x: T) -> Str` in stdlib (Rust pattern). Pull-only (Q2-C) is the single biggest AI-codegen risk in the space — LLMs writing recursive `display` impls would systematically generate quadratic-allocation code, and the spec would give them no signal to write a StringBuilder loop instead. Push primary makes the linear path obvious."*
- **Minimalism:** *"Pull-only `display(self) -> Str` with codegen specialization for built-ins is sufficient. We can live with one allocation per leaf in the slow path; the hot path is built-in interpolation which doesn't go through the trait. Minimalism: don't add a second surface for an asymptotic concern that may not show up in real workloads. If users need push, they write a method on their type, not on the trait."*

#### Phase A.5 — Mechanical dedupe

- **Q2 trait shape:** A (push-only with external helper: sys, devops), B (push primary + pull derived as default method: web, plt; aiml proposed B with helper relocated, see Phase B), C (pull-only with codegen specialization: min)
- **Q3 wk9gab dependency:** A (independent: web, plt, devops, aiml, min), B (block on wk9gab: sys; conditional)
- **Q4 adapter location (only relevant if Q2-B wins):** i (default method on trait: web, plt, min), ii (free function in stdlib: sys, devops, aiml)
- **Q1 method name:** `to_str` (sys, web), `to_string` (devops), `display` (plt, aiml, min)

#### Phase B — Debate highlights

**On Q2 — sys moved A → B:**

> **plt to sys:** *"A and B are mechanically identical at codegen — the difference is whether the spec sentence reads 'Display guarantees `fmt`' or 'Display guarantees `fmt` and a derived `display`'. Putting the derived form in the trait gives spec locality without changing the impl surface."*
> **sys (Phase B reply):** *"Granted. Default method ≠ second surface as long as `fmt` is the only required impl. Moving to B."*

**On Q2 — min withdrew C:**

> **plt to all:** *"`display` for a struct `Outer { a: Inner1, b: Inner2 }` under pull-only forces something like `'{a.display()}{b.display()}'`. Each nested `.display()` allocates a transient `Str`. For depth D, that's roughly N·D throwaway allocations the parent immediately concatenates and drops. This is asymptotic, not micro."*
> **min (Phase B reply):** *"plt's composition argument is correct and I was wrong to dismiss it as premature optimization. C is wrong; I withdraw it. Moving to B with Q4-i (default method)."*

**On Q3 — sys's contingency dropped:**

> **sys's Phase A:** *"If wk9gab lands erased boxing, generic `[T: Display]` callers face vtable + heap-SB + heap-Str cost per call. Display might need monomorphization-aware codegen — block on wk9gab."*
> **plt to sys:** *"The trait surface is identical under both wk9gab directions. The hot interpolation path lowers via codegen-direct calls into `fmt` on a concrete T regardless. Only generic `fn show[T: Display](v)` callers face the dispatch question, and that's downstream — ship the surface now."*
> **sys (Phase B reply):** *"Surface stable under both directions. Moving to Q3-A. The wk9gab perf concern is recorded as a wk9gab deliberation input, not a Display gate."*

**On Q4 — devops and aiml flipped after sealing constraint surfaced:**

> **aiml's Phase B:** *"Q4-i is acceptable IF the default method is non-overridable (sealed). My objection is LLMs generating divergent custom `display` impls. If sealing closes that hole, sealed-i is strictly better than ii — ii would still allow user-shadowed free functions to drift."*
> **plt's Phase B:** *"Sealing is the right answer mechanically. `final fn display` with body fixed by the trait — there is no override surface. Drift is impossible by construction."*
> **devops (Phase D):** *"Sealed default fully addresses my override-drift concern. Switching to i. One diagnostic ask: missing-impl error must steer at the trait (`@derive(Display)` or `impl Display for X`), not show `display()` as a 'did you mean?' ghost-method."*
> **aiml (Phase D):** *"Flipping to i with sealing as the recorded constraint."*

**On Q1 — devops conceded `to_string`, sys/web held `to_str`:**

> **plt to all:** *"`to_X` is the conversion-cluster naming convention — `to_int`, `to_float`, `to_bytes` — implying a structural cast. Display is not a conversion; it's a rendering (potentially lossy, locale-aware). Calling it `to_str` conflates the two. Rust's `ToString`-vs-`Display::fmt` confusion is exactly this in the wild."*
> **devops (Phase D):** *"With Q2-B locked, the trait method and the convenience adapter share one name. Split naming between trait and adapter is the worse failure mode. Switching to `display`. Recording a follow-up: when `Debug` lands, parallel must be `debug(x)`, not `to_debug_string(x)`."*
> **sys (Phase D):** *"Holding `to_str`. The trait *is* `Display`; `Display.display(x)` is nominally redundant. `to_X` is a load-bearing converter pattern. Will not block consensus, but registering the dissent."*
> **web (Phase D):** *"Holding `to_str` for the same reason. The substantive Q2/Q4 calls matter more; if `display` ships, I won't relitigate."*

#### Phase C — First vote

- **Q1: Trait method name** (3-2-1 split, no majority)
  - **Systems:** `to_str` — *"Verb-prefix-target convention (`to_int`, `to_float`, `to_str`); `display` collides nominally with the trait name."*
  - **Web/Scripting:** `to_str` — *"Matches `Str` the type, matches `to_*` family, migrant intuition."*
  - **PLT:** `display` — *"Method name = trait name (verb-of-noun); reads as 'render', not 'convert'."*
  - **DevOps:** `to_string` — *"Mirrors Rust's `ToString::to_string`. `display` is overloaded in user vocabulary (terminals, GUIs, rendering)."*
  - **AI/ML:** `display` — *"Trait/method parity is the simplest spec sentence; `to_str` triggers Rust `&str` borrow-semantics pattern-match."*
  - **Minimalism:** `display` — *"`Str` not `String`, and trait/method symmetry."*
- **Q2: Trait shape** — **5-1 for B** (DevOps dissent A; soft consensus on non-overridable default)
  - **Systems:** B, **Web:** B, **PLT:** B, **DevOps:** A, **AI/ML:** B, **Minimalism:** B
  - *(dissent)* **DevOps:** A — *"Push-only matches existing codegen call shape, eliminates transient Str allocations, keeps trait surface to one method. The convenience adapter belongs outside the trait so it cannot be overridden into divergence with `fmt`."* — addressed by sealing the default in Phase D, which converted devops's concern into Q2-B support.
- **Q3: wk9gab dependency** — **6-0 for A** (independent)
- **Q4: Adapter location** — 4-2 for i (sealed default method)
  - **Systems:** i, **Web:** i, **PLT:** i, **DevOps:** ii, **AI/ML:** ii, **Minimalism:** i

#### Phase D — Round 2

Triggered by Q1 (3-2-1 split) and Q4 (4-2). Q2 (5-1) treated as soft consensus given devops's concern was explicitly addressed by the majority's "non-overridable default" framing. Q3 (6-0) locked.

- **Q1 (Phase D vote):** **4-2 for `display`**
  - **Systems:** `to_str` — *"Verb-prefix-target convention is load-bearing; breaking it for one trait creates long-lived inconsistency. Will not block, registering dissent."*
  - **Web/Scripting:** `to_str` — *"Migrant intuition is conversion-by-noun; `display` is the only verb-named string-returning method any major language ships. Will not block; substantive trait shape matters more."*
  - **PLT:** `display` — *"`to_X` is conversion-cluster; Display is rendering. Conflating recreates Rust's `ToString`-vs-`Display::fmt` long-tail confusion."*
  - **DevOps:** `display` — *"Conceded. Split naming between trait and adapter is the worse failure mode."*
  - **AI/ML:** `display` — *"Trait/method parity gives the simplest spec sentence with zero translation cost for AI or human readers."*
  - **Minimalism:** `display` — *"`Str` not `String`; trait/method symmetry."*

- **Q4 (Phase D vote):** **6-0 for i (sealed default method)**
  - All six: i, with sealing as a recorded constraint.
  - *(flipped from ii)* **DevOps:** *"Sealed default fully addresses override-drift concern."*
  - *(flipped from ii)* **AI/ML:** *"Sealing closes the LLM-divergence hole; sealed-i is strictly better than ii."*

### Final Spec

```blink
trait Display {
    fn fmt(self, sb: StringBuilder) ! StringBuilderPure
    final fn display(self) -> Str {
        let sb = StringBuilder.new()
        self.fmt(sb)
        sb.to_str()
    }
}
```

**Locked design points:**

1. **Push primary.** `fmt(self, sb: StringBuilder)` is the only user-implementable method. Recursive impls call `child.fmt(sb)` into the same builder; composition is O(n) in output size with zero intermediate `Str` allocations.
2. **Sealed pull adapter.** `display(self) -> Str` is a `final` default method — non-overridable by `impl` blocks. Its body is fixed by the trait: build a `StringBuilder`, call `self.fmt(sb)`, materialize. `value.display()` and any push-style consumption are guaranteed to produce identical output by construction.
3. **Three call shapes, one impl.** `"{x}"` interpolation, `x.display()`, and `sb.write(x)` all route through `fmt`. Drift is mechanically impossible.
4. **`StringBuilderPure` effect on `fmt`.** Implementations may write to the supplied builder but cannot read external state, perform IO, or mutate state outside the builder. This is what makes the sealed `display` derivation safe.
5. **Independent of `wk9gab`.** Surface is identical under monomorphization and erased-boxing. Generic `[T: Display]` callers' codegen cost is a downstream wk9gab concern, not a Display gate.
6. **Diagnostic constraint.** Missing-impl errors for `T: !Display` MUST suggest `impl Display for X` or `@derive(Display)` and MUST NOT show `display()` as a "did you mean?" ghost-method.
7. **Future Debug parallel.** When `Debug` is shaped, its pull adapter must be named `debug(x)`, not `to_debug_string(x)`, for consistency with the verb-form family chosen here.

### Dissent recorded

- **Q1 dissent (sys, web → `to_str`):** Both held that `to_X` is Blink's converter convention and `display` is redundant with the trait name. Both explicitly declined to block consensus. The `to_str` vs `display` question can be reopened if a future trait family makes the `to_X` inconsistency painful in practice — but only by a fresh deliberation; the panel does not consider this an open gap.
