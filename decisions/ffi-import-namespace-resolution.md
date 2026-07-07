[< All Decisions](../DECISIONS.md)

# FFI Import Namespace Resolution — Design Rationale

Spec anchors: [`sections/07_trust_modules_metadata.md`](../sections/07_trust_modules_metadata.md) §9.1.1 (*FFI Type Specification* and the new *FFI import resolution and the real gates* subsection), §07:196 (Pointer Operations prose), §07:1659 (the `blink.*` reservation in §10.7), §07:1601 (§10.6 *What Is NOT in the Prelude* — the `ConversionError`/`blink.core` bullet). Ticket: br `q0brkj`.

### Problem Statement

The gap: `import blink.ffi` and `import blink.core` wrongly threw `ModuleNotFound`. §07:1659 reserves the `blink.*` namespace for compiler-internal pseudo-modules (`blink.core`, `blink.ffi`) that are "part of the language definition, not distributable packages" — but the resolver was never taught that reservation, so it fell through to the "no match → compile error" arm of §10.7's resolution order. Meanwhile §9.1.1 showed `import blink.ffi.{Ptr, Void, alloc_ptr, null_ptr}` as the opening example of every FFI binding, and §07:196 read "available only in modules that `import blink.ffi`" — prose that reads as a *requirement*.

That left an unanswered design question the panel had to settle before the resolver was patched: **is `import blink.ffi` a capability gate, or a documentation marker?** If a gate, it would be the language's *first* live per-file import gate, and the resolver bug is really a missing feature. If a marker, the resolver bug is simply that the §07:1659 reservation was never implemented, and the fix is to resolve `blink.*` imports as inert no-ops.

**Codebase facts surfaced to the panel:**
- **F1** No `import` anywhere in Blink is a capability gate today — imports control *name visibility* (§10.6 selective-import), never *permission*. The `io`/`net`/`time` namespaces are usable with no import at all (no-import intrinsics).
- **F2** `Ptr[T]`, `Void`, `alloc_ptr`, `null_ptr`, and the pointer operations are compiler-known intrinsics, resolved without reference to any imported module — so a selective `import blink.ffi.{...}` adds zero binding information.
- **F3** The unsafe FFI surface is *already* gated twice: `PtrOutsideFFI` (E0811) requires a `Ptr[T]` to appear inside an `@ffi`/`@trusted` context per-function; and `#275` makes an `@ffi` declaration without a `[native-dependencies]` manifest entry a compile error.
- **F4** All of lib/std and every FFI fixture in the tree use the `ffi` namespace and `Ptr[T]` *without* a mandatory `import blink.ffi` gate; making the import required would break them all and demand a migration.

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in independent-proposal → debate → vote rounds.

#### Phase A — Independent proposals

- **Systems:** No gate. `Ptr[T]` lowers to `T*`; the `ffi` namespace is intrinsic the way `io`/`net`/`time` are. A per-file import boundary buys nothing the codegen or the type system needs — the compiler already knows every FFI symbol without an import. Resolve `blink.*` imports as inert so the reservation in §07:1659 is honoured, and lean on `PtrOutsideFFI` + `#275` as the real, structural gates.
- **Web/Scripting:** No gate. Every scripting dev expects `import` to mean "bring these names into scope," not "unlock a permission." An import that is *required before you may call a function you can already name* is action-at-a-distance. Accept `import blink.ffi` as an optional convenience so copy-pasted examples don't error, but never require it.
- **PLT:** No gate. Capability in Blink is carried by *effects* and by the `@ffi`/`@trusted` context, not by module membership. Folding a capability check into name resolution conflates two independent judgments (visibility vs. permission) that the language deliberately keeps separate. `import blink.ffi` should resolve as a no-op that satisfies the `blink.*` reservation; the well-formedness rule that matters is `PtrOutsideFFI`.
- **DevOps/Tooling:** No gate — but initially wanted a soft nudge (see Phase B, W-withdrawal). Auditing FFI must key on something a tool can grep and CI can enforce: `rg '@ffi'` plus the `#275` manifest plus the `blink audit` Raw/audit surface. A per-file `import blink.ffi` marker is *weaker* than `rg '@ffi'` (a file can import and never use it, or use `@ffi` without importing), so it can't be the audit primitive. Resolve as no-op; keep the manifest gate.
- **AI/ML:** No gate. Every required import is a failure point for machine-authored code; a *conditionally*-required import (needed iff the file touches FFI) is worse — it's hidden per-file state the model must infer. FFI usage is already fully discoverable from `@ffi` at the declaration site. Resolve `blink.ffi`/`blink.core` as satisfiable no-ops so a model that writes the import (habit from other examples) and a model that omits it both compile.
- **Minimalism:** No new mechanism — but initially questioned whether the examples should exist at all (see Phase B, D-withdrawal). The smallest possible change is: implement the reservation that §07:1659 already promises, and add zero gates, zero errors, zero warnings. A live import gate would be a new capability axis the language does not otherwise have; that is the opposite of minimal.

#### Phase B — Debate highlights

**D-withdrawal by Min.** Minimalism opened by floating position **D — "delete the FFI import examples entirely"**: if `import blink.ffi` is a no-op, showing it in §9.1.1 is misleading clutter, so the truly minimal move is to strike the fenced `import blink.ffi.{...}` examples and never mention the import. Min **withdrew D** after Web and AI/ML pushed back: the examples are the single most-copied FFI snippet, and deleting them wouldn't stop people writing the import (it appears across every FFI ecosystem's mental model) — it would only make the resolver's tolerance *undocumented*. Min conceded: "keeping the example plus a one-line 'this is optional' note is smaller in practice than deleting it and fielding the resulting confusion — minimal means fewest surprises, not fewest characters." The examples stay, annotated as optional markers.

**W-withdrawal by DevOps.** DevOps opened by floating a **W-level warning: "`@ffi` used without `import blink.ffi`"** — a lint that would nudge authors toward a consistent file-level FFI marker for auditability. DevOps **withdrew W** once F3/F4 were on the table: the warning would fire across all of lib/std and every existing fixture (none of which import `blink.ffi`), so shipping it means either a mass migration or a warning that's off by default and therefore ignored. More decisively, DevOps agreed with its own Phase-A point that the marker is *weaker* than `rg '@ffi'` and the `#275` manifest — so the warning would add noise without adding a real audit guarantee. "A warning that pushes a per-file marker weaker than the grep I already run is negative-value; the manifest gate is the audit primitive, and it already exists." Withdrawn.

With both live-gate-adjacent positions withdrawn, the room converged: the resolver bug is a missing implementation of the §07:1659 reservation, not a missing feature. `import blink.ffi`/`import blink.core` resolve as recognized inert no-ops; the two real gates (`PtrOutsideFFI`, `#275`) are the whole capability story.

#### Phase C — Final vote

**Q: FFI import — gate or inert no-op? → NO GATE; resolve as inert optional no-op** — vote **6-0**.

- **Systems:** No gate. The compiler knows every FFI symbol without an import; a per-file gate is redundant with the intrinsic-namespace model and adds a lowering-irrelevant check.
- **Web/Scripting:** No gate. `import` means visibility, not permission, everywhere else in the language; an FFI-only exception would be the surprising special case.
- **PLT:** No gate. Capability is an effect/context judgment (`@ffi`/`@trusted`, `PtrOutsideFFI`), orthogonal to name resolution; keep the two judgments separate.
- **DevOps/Tooling:** No gate. `rg '@ffi'` + `#275` manifest + `blink audit` are the auditable primitives; a per-file import marker is strictly weaker and would only add noise.
- **AI/ML:** No gate. A conditionally-required import is hidden per-file state that harms first-try generation; resolving the import as a satisfiable no-op makes both "wrote it" and "omitted it" compile.
- **Minimalism:** No gate. Implementing the §07:1659 reservation as an inert no-op is the smallest change that fixes `ModuleNotFound`; a live import gate would introduce a capability axis the language does not otherwise have.

No Phase D triggered.

#### AI-First Review Pass — 5/5 pass

The winning decision was evaluated against the five AI-first criteria (see [ai-first-review-pass.md](ai-first-review-pass.md)):

1. **Learnability — pass.** The rule is one sentence ("the import is optional; FFI works without it"), learnable from the §9.1.1 note alone; no cross-language borrowing required.
2. **Consistency — pass.** `ffi` joins `io`/`net`/`time` as a no-import intrinsic namespace — the *existing* pattern, not a special case. `import` keeps its single meaning (visibility) everywhere.
3. **Generability — pass.** Both machine-authored variants compile: writing `import blink.ffi.{...}` (habit from examples) and omitting it. There is no import a model can *forget* and break the build.
4. **Debuggability — pass.** The removed failure mode (`ModuleNotFound` on a language-defined pseudo-module) was a dead end with no self-correcting fix. The real gates that remain (`PtrOutsideFFI` E0811, `#275` manifest) point at the actual problem (a `Ptr[T]` outside an `@ffi` context; a missing manifest entry) with a caret and an actionable help line.
5. **Token Efficiency — pass.** No mandatory boilerplate import per FFI file. FFI usage stays discoverable via `rg '@ffi'` — no hidden per-file state to scan for.

### Final Spec

1. **`ffi` is a no-import intrinsic namespace.** Its pointer types (`Ptr[T]`, `Void`) and operations are compiler-known and usable with **no import**, exactly like `io`/`net`/`time`.
2. **`import blink.ffi` / `import blink.core` resolve as inert optional no-ops** — recognized, accepted, never required, and **never `ModuleNotFound`**. This implements the `blink.*` reservation in §07:1659 (§10.7).
3. **Selective names are satisfiable no-ops.** `import blink.ffi.{Ptr, Void, alloc_ptr, null_ptr}` (and `import blink.core.{ConversionError}`) accept and bind names that are compiler-known regardless; the import is a **documentation marker**, not a binding source.
4. **No import gate.** The unsafe FFI surface is gated only by the two existing gates: **`PtrOutsideFFI` (E0811)** — a `Ptr[T]` must appear inside an `@ffi`/`@trusted` context — and **`#275`** — an `@ffi` declaration requires a matching `[native-dependencies]` manifest entry. There is no E- or W-level gate keyed on the import.
5. **Non-breaking.** No lib/std change and no test migration: existing FFI code that never imports `blink.ffi` keeps compiling, and code that does import it stops erroring.
