[< All Decisions](../DECISIONS.md)

# Polymorphic Trait Impls for Builtin Generic Types — Design Rationale

### Problem Statement

Blink needs a rule for how polymorphic trait impls for builtin generic types
(`impl[T] Display for List[T] where T: Display`, etc.) are compiled. Two
directions were on the table:

- **(a) Erased boxing.** One impl body per (Trait, BuiltinGeneric), values
  stored as `void*`, dispatched on `@intrinsic size_of[T]()` /
  `@intrinsic is_pointer_kind[T]()` at runtime. Smaller binaries, runtime
  cost on every operation, exposes type-shape inspection as a language
  primitive.
- **(b) Monomorphization.** Compiler stamps out a separate instantiation per
  concrete `T`. Each instantiation has type-appropriate storage and dispatch
  decided at codegen time. Bigger intermediate `.o` files, zero runtime cost,
  no type-introspection surface. Linker `--gc-sections` strips unused
  instantiations.

Implementation subtasks (project `b1bdnh`) were provisionally written
assuming direction (b). This deliberation formalizes the choice and the
follow-on constraints.

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML,
minimalism) deliberated in independent-proposal → debate → vote rounds.

#### Phase A — Independent proposals

All six panelists independently proposed **direction (b) monomorphization**.
The disagreements that surfaced were on two follow-on questions, not on the
core direction.

- **Systems:** "Mono gives predictable codegen — each instantiation is a
  straight-line C function the optimizer can inline. Erased-boxing turns
  every method call into a vtable + size-dispatch branch the hardware can't
  predict cleanly. The hybrid traps in `display-trait-shape.md` already
  showed erased-boxing pays vtable + heap-StringBuilder + heap-Str on every
  generic `[T: Display]` caller; we'd be re-introducing that cost across the
  whole trait surface."
- **Web/Scripting:** "Devs already understand mono from Rust and C++
  templates. `List[Int]` and `List[Str]` becoming separate compiled functions
  is intuitive. Erased-boxing with `size_of[T]` intrinsics would be a new
  vocabulary nobody asked for and Stack Overflow questions waiting to happen."
- **PLT:** "Monomorphization preserves parametricity at the source level —
  user impl bodies cannot dispatch on T because the type checker substitutes
  T away before the body is meaningful. Erased-boxing breaks Reynolds-style
  parametricity by exposing T's runtime shape; that's a load-bearing
  semantic property we don't want to give up. Wadler's 'theorems for free'
  reasoning depends on it."
- **DevOps:** "Mono produces normal C symbols with normal names. Erased-boxing
  would produce one symbol per (Trait, BuiltinGeneric) with branching
  inside — a debugger steps into the dispatch, not the implementation. LSP
  hover, error messages, profiler symbols all degrade. Mono keeps the
  toolchain trivially observable."
- **AI/ML:** "Models are trained extensively on Rust monomorphization. Models
  encountering `@intrinsic size_of[T]` will have no priors — they'll
  hallucinate or skip it. Mono is the well-trodden path and the diagnostic
  surface stays simple ('add a trait bound' is a universally trained
  correction)."
- **Minimalism:** "Mono is the *subtractive* answer here. It deletes the
  need for new intrinsics (`size_of[T]`, `is_pointer_kind[T]`,
  `TypeRepr[T]`), deletes the need for a runtime type-tag mechanism, and
  reuses the same monomorphization machinery the language already has for
  generic functions. Erased-boxing would *add* a whole sublanguage for
  type-shape inspection. Reject erased-boxing on YAGNI grounds; mono is the
  primitive we already have."

#### Phase A.5 — Mechanical dedupe

Phase A produced unanimity on direction. Two follow-on questions surfaced
where panelists disagreed:

- **Q2:** Should the `size_of[T]` / `is_pointer_kind[T]` / `TypeRepr[T]`
  intrinsics (originally proposed for direction (a)) still exist, gated as
  `@compiler_internal`? Or drop them entirely?
- **Q3:** Should the spec contain an explicit sentence stating the
  parametricity guarantee (user impl bodies cannot dispatch on T's runtime
  identity)? Or let it follow implicitly from monomorphization semantics?

Q4 (`dyn Trait` / runtime polymorphism) was unanimously deferred. Q5
(bootstrap strategy) is an implementation note, not a spec question.

#### Phase B — Debate highlights

**Q2 movement:**

- **Sys** initially preferred (A) but flipped to (B) after PLT framed it as
  "compiler-internal intrinsics keep user surface parametric without forcing
  FFI for trivial things."
- **PLT** initially preferred (B) but flipped to (A) after realizing
  `@compiler_internal` terms still appear in the AST and become targets for
  future macro elaboration: *"A `@compiler_internal` intrinsic is still a
  typed term in the AST and type-checker; once it exists as a language form
  it becomes a target for future derive macros, elaboration tricks, and
  'just expose this one' pressure."*
- **AI/ML** (Phase B): *"`lib/std/` is training corpus (per CLAUDE.md), so
  any `@compiler_internal` intrinsic appearing there will be pattern-matched,
  attempted, and have its gate-annotation stripped to bypass — same failure
  mode as Rust `#![feature(...)]` in LLM output. `@ffi` to a runtime C
  symbol is a stronger seam: one well-known concept (foreign call) instead
  of a new type-introspection sublanguage."*
- **Min** (Phase B): *"`@compiler_internal` is a fence around user surface
  today, not around the mechanism. Once those intrinsics exist: future
  contributors reach for them because they're there (C++-committee
  dynamic); the 'invisible to user surface' boundary erodes — they leak via
  error messages, `--blink-trace`, compiler source; they license adjacent
  additions later (`align_of[T]`, `is_zst[T]`, `layout_of[T]`)."*

**Q3 movement:** positions stayed mostly stable. Majority (sys, plt, aiml,
min) argued the spec sentence is a load-bearing future-proofing line —
"what the spec says is what LLMs train on" (aiml), "written-down rejections
stick" (min), "alternate backends silently dissolve the property unless
it's spec-level" (plt). Dissenters (web, devops) argued mono codegen
already mechanically prevents dispatching on T from source, so prose
duplicates a grammar invariant. Both dissenters' Phase C concerns
explicitly endorsed the underlying need (written rationale somewhere) and
disagreed only on **location** (spec prose vs. diagnostic text vs.
DECISIONS.md).

#### Phase C — Final vote

**Q1: Direction.** Monomorphization. **6-0.**

**Q2: Intrinsic surface.** Drop the `size_of[T]` / `is_pointer_kind[T]` /
`TypeRepr[T]` intrinsics entirely. Any genuine stdlib layout need routes
through `@ffi` to a runtime C helper. **5-1.**

- **Systems:** *(dissent)* B — *"Stdlib has to implement
  `List`/`Map`/`Set`/`Bytes` lowering somehow; the choice is between
  auditable `@compiler_internal` primitives and an opaque sprawl of
  `@ffi("blink_*_for_int")` stubs that encode the same shape information in
  C macros. From a codegen perspective B keeps the shape-aware logic where
  the compiler can reason about it."*
- **Web:** A — *"Mono removes the intrinsics' only job — each instantiation
  already knows T concretely, so `size_of[T]` and `is_pointer_kind[T]` have
  nothing to do. `@compiler_internal` is never actually invisible: stdlib
  source is read, grepped, and trained on, and a hidden generic intrinsic
  in `lib/std` becomes the next 'why can't I use this' Stack Overflow
  thread."*
- **PLT:** A — *"A `@compiler_internal` intrinsic is still a typed term in
  the AST and type-checker; once it exists as a language form it becomes a
  target for future derive macros, elaboration tricks, and 'just expose
  this one' pressure. Monomorphization removes the entire motivation for
  the intrinsic surface, and `@ffi` to a runtime C helper is the principled
  boundary."*
- **DevOps:** A — *"With mono picked, the compiler computes layout/
  pointer-kind decisions inside its own codegen — it doesn't need to expose
  them as Blink-level intrinsics at all, even gated. `@compiler_internal`
  intrinsics create a parallel surface that leaks into LSP completion
  lists, hover text, and error messages."*
- **AI/ML:** A — *"`lib/std/` is training corpus; any `@compiler_internal`
  intrinsic appearing there will be pattern-matched, attempted, and have
  its gate-annotation stripped to bypass — same failure mode as Rust
  `#![feature(...)]` in LLM output. `@ffi` is a stronger seam: one
  well-known concept (foreign call) instead of a new type-introspection
  sublanguage."*
- **Minimalism:** A — *"Under monomorphization the compiler emits
  `sizeof(int64_t)` directly into the C body — stdlib never needs
  `size_of[T]` / `is_pointer_kind[T]` to exist as language primitives.
  Every primitive in the language is forever, and these intrinsics license
  adjacent additions later (`align_of[T]`, `is_zst[T]`, `layout_of[T]`)."*

**Q3: Parametricity spec sentence.** Add an explicit spec rule that user
impl bodies must be parametric in T — no dispatching on T's identity, no
inspection of T's runtime shape/size/layout. Trait-bounded method calls
(`T: Display`) are explicitly carved out as allowed. **4-2.**

- **Systems:** A — *"Mono codegen is *how* we lower; parametricity is
  *what* user code is allowed to assume — they're separate guarantees and
  only the latter preserves our freedom to change builtin layouts
  (niche-filled `Option[Int]`, future tagged-union changes) without
  breaking shipped code. Without the spec sentence, the first `@trusted`
  PR that peeks at lowered representation has no principled rejection."*
- **Web:** *(dissent)* B — *"With no intrinsic surface and mono semantics,
  the grammar already forbids dispatching on T — a prose sentence
  restating that is scaffolding without load. Devs from TS/Python read
  examples and error messages, not spec sections; the right place to
  encode 'you can't inspect T' is the diagnostic at the attempt site."*
  Concern (acknowledges majority's underlying need): *"When `dyn Trait`
  or reflection eventually returns, the absence of a written parametricity
  invariant means the reviewer of that PR has to reconstruct the
  constraint from first principles instead of pointing at a spec line."*
- **PLT:** A — *"A guarantee that isn't in the spec isn't enforced — 'mono
  codegen is sufficient' conflates current implementation with language
  semantics, and any future backend (interpreter for `blink check`, JIT,
  alternate linkage) silently dissolves the property unless it's
  spec-level. The asymmetric cost matters: one declarative spec sentence
  vs. permanent ambiguity that LLM training data will fill with
  `Obj.magic` / `Typeable` patterns from other languages."*
- **DevOps:** *(dissent)* B — *"Mono codegen and the empty intrinsic
  surface mechanically prevent dispatching on T from source — there's no
  syntax to express it. Spelling parametricity out in spec prose creates
  an abstract invariant users will see cited in errors ('violates §X.Y')
  instead of the concrete diagnostic ('cannot determine layout of T
  here'), and concrete error messages outperform abstract ones every
  time."* Concern (acknowledges majority's underlying need): *"A future
  contributor adding a reflection-like feature might not realize
  parametricity was load-bearing without a written rule, so the decision
  record needs to capture the rationale even if the spec doesn't."*
- **AI/ML:** A — *"What the spec says is what LLMs train on; an unstated
  invariant gets filled in from priors like C++'s `if constexpr` or Rust's
  `TypeId`. A one-line parametricity sentence gives the model a teachable
  invariant and gives diagnostics a clause to cite ('forbidden by §X.Y'),
  enabling self-correction. Mechanism descriptions aren't normative;
  spec sentences are."*
- **Minimalism:** A — *"A one-paragraph spec sentence subtracts from
  future panel-time by collapsing every future 'should we add reflection /
  dispatch-on-T / specialization?' debate to 'the spec already says no.'
  Blink has strong precedent for written-down rejections (CLAUDE.md's
  `if let`/defaults/specialization list, `display-trait-shape.md`'s mono/
  erased equivalence note) precisely because written constraints stick."*

**Q4: `dyn Trait` / runtime polymorphism.** Deferred — out of scope for
this gap. **6-0 to defer.**

**Q5: Bootstrap strategy.** Implementation note: existing stdlib generic
machinery already monomorphizes; spec doesn't need to address bootstrap.

#### Soft consensus on Q3

Phase D was eligible on Q3 (4-2 trigger) but skipped under the soft-consensus
carve-out: both dissenters' Phase C concerns explicitly acknowledged the
underlying need (written rationale, somewhere) and disagreed only on
location. The synthesis below honors all six votes — spec sentence
(majority) + concrete diagnostic (DevOps) + this decision record
(both dissenters' fallback).

### Final Spec

**Direction.** Polymorphic trait impls for builtin generic types are
compiled by **monomorphization**: the compiler emits a separate instantiation
per concrete `T` referenced in the program. Each instantiation has
type-appropriate storage and dispatch decided at codegen time. Linker
`--gc-sections` strips unused instantiations. No runtime type-shape
intrinsics are exposed.

**Parametricity rule (normative).** User impl bodies must be **parametric in
their type parameters**. The source may not:

- dispatch on `T`'s identity (no `if T == Int { ... }`, no `match T { ... }`);
- inspect `T`'s runtime layout, size, alignment, or pointer-kind;
- call any function that exposes `T`'s runtime shape.

Trait-bounded method calls (`(x: T).display()` when `T: Display`) **are
permitted** — they are dispatched at monomorphization time, not at runtime.
The only legal way for an impl body to vary behavior based on `T` is to
introduce a trait bound and call a method on that bound.

```blink
// Allowed: parametric body, dispatches via trait bound
impl[T] Display for List[T] where T: Display {
    fn fmt(self, sb: StringBuilder) ! Fmt {
        sb.write("[")
        let mut first = true
        for item in self {
            if !first { sb.write(", ") }
            item.fmt(sb)
            first = false
        }
        sb.write("]")
    }
}

// Compile error: body inspects T's identity
impl[T] Display for List[T] where T: Display {
    fn fmt(self, sb: StringBuilder) ! Fmt {
        if T == Int { sb.write("(ints)") }  // ERROR: cannot dispatch on T
        // ...
    }
}
```

**Intrinsic surface.** No `size_of[T]`, `is_pointer_kind[T]`, or
`TypeRepr[T]` exist as Blink-level forms — neither user-visible nor
`@compiler_internal`. Stdlib needs that require layout queries route through
`@ffi` to a runtime C helper.

**Diagnostic requirement.** Compile errors for parametricity violations
**must** read as concrete, actionable text and cite the spec rule. Example:

```
error[E0701]: cannot inspect type parameter T
  --> mymod.bl:12:9
   |
12 |         if T == Int { ... }
   |         ^^^^^^^^^^^ T's identity is not available at runtime
   |
   = note: user impl bodies must be parametric in T (§3.6 Polymorphic Trait
     Implementations)
   = help: to vary behavior based on T's properties, add a trait bound:
     `where T: Eq` and call `(t: T).eq(other)` instead
```

The diagnostic must lead with the concrete impossibility ("T's identity is
not available at runtime"), follow with a `note:` citing the spec rule,
and end with a `help:` proposing a trait-bound alternative.

**Coherence interaction.** Polymorphic impls follow the existing coherence
rules (orphan rule, no overlap). `impl[T] Trait for BuiltinGeneric[T]
where T: Bound` and `impl Trait for BuiltinGeneric[Int]` overlap and the
program is rejected — same rule as today.

### Out of scope (recorded for future panels)

- **`dyn Trait` / boxed polymorphism.** Deferred. If revisited, the
  parametricity rule above scopes only to static-dispatch impl bodies; the
  `dyn` boundary is its own carve-out and a future panel must spell out
  what is allowed across it.
- **`align_of[T]`, `is_zst[T]`, `layout_of[T]`, `TypeId[T]`.** Rejected
  on the same grounds as `size_of[T]`. Adding any of these reopens this
  decision.
- **Specialization** (more-specific impl wins). Already rejected in
  `trait-coherence.md`. This decision strengthens that rejection — no
  source-level dispatch on T means no specialization-by-the-back-door
  either.
- **Const generics** (e.g., `Array[T, N]`). Not addressed here. A future
  panel can decide whether `N: const Int` is "inspecting T's runtime
  shape" (it isn't — it's a compile-time value) or otherwise.
