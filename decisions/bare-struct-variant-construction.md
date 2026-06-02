[< All Decisions](../DECISIONS.md)

# Bare Struct-Style Enum-Variant Construction

**Task:** `hrwn4h` (P1, `type:spec`). Triaged from friction `p5pk6k`.
**Resolution:** Support bare struct-style variant construction. Hint-first resolution.
Two distinct collision kinds with two distinct mechanisms. No silent winner.
**Vote:** Unanimous **6-0** on all three questions.

## The Gap

Today, bare struct-style enum-variant construction fails:

```blink
type QueryError {
    NotFound { msg: Str }
}

let e = NotFound { msg: "x" }   // error[UnknownType]: unknown type 'NotFound'
```

…even though three sibling forms already work:

- `QueryError.NotFound { msg: "x" }` — qualified struct-style construction.
- `Leaf(1)` — bare *tuple*-style construction (canonical in §3.4).
- `NotFound { msg }` in a **pattern** — bare struct-style pattern (fixed in `e4eymz`).

So construction vs pattern position was asymmetric for struct-style variants. The
construction path dies at `typecheck.bl:4752-4761` (`infer_type`, StructLit case),
which only calls `lookup_named_type(sname)`; variant names aren't in `named_type_map`,
so it falls through to `UnknownType`. The pattern path at `typecheck.bl:5288` already
has the fallback — binding hint, then `get_variant_enum_tid(short_name)`.

The moderator also confirmed today's collision behavior: with both a plain
`type NotFound { code: Int }` and an enum variant `NotFound`, `NotFound { code: 404 }`
**silently** resolves to the struct.

## Three Questions

- **Q1.** Support bare struct-style construction at all?
- **Q2.** What is the resolution rule for a bare construction site?
- **Q3.** What is the collision rule when a name is ambiguous?

---

## Phase A — Independent Proposals (6 panelists)

### Systems (sys)

> 1. Bare struct-style construction dies at typecheck.bl:4752-4761 (`infer_type`, StructLit case): it ONLY calls `lookup_named_type(sname)`. Variant names aren't in `named_type_map`, so it falls to TYPE_UNKNOWN → UnknownType. The pattern path (5287-5292) already has the exact fallback: try binding hint, then `get_variant_enum_tid(short_name)`.
> 2. QUALIFIED struct-style variant construction already works, which means the CODEGEN to emit the tagged-union initializer (tag field + struct payload) is already wired. Bare construction needs zero new codegen — it only needs the front-end to resolve (enum_tid, variant_idx) and route to the existing path. … **this is a pure resolution change, not a representation change. The C output for `NotFound { msg }` is byte-identical to `QueryError.NotFound { msg }`.**

> **PROPOSAL S1 (primary): Support bare struct-style construction; resolution = binding-hint first, then global variant lookup; struct-vs-variant collision = HARD ERROR** … Resolution order for `Name { ... }`: 1. Expected-type / binding hint … 2. `lookup_named_type(Name)` (struct) … 3. `get_variant_enum_tid(Name)` (bare variant) … 4. If BOTH (2) and (3) match and (1) didn't disambiguate → **hard error E_AMBIGUOUS_CONSTRUCT**, force qualification.

> ZERO runtime cost. Resolution is compile-time; emitted C is the existing qualified path. … The current SILENT struct-wins behavior … is a latent miscompile-class hazard … For a self-hosting compiler whose output is training data, silent rebinding is the worst outcome.

> **PROPOSAL S2 (alternative): Support bare, but collision … is rejected AT DECLARATION** … a program may not declare a struct named `X` if an enum variant `X` exists (and vice versa). This makes bare construction unconditionally unambiguous.

### Web/Scripting (web)

> My domain test for every option: "Would a JS/Python/TS dev predict this from what they already wrote, and how many SO questions does it spawn?"

> **PROPOSAL 1 (PRIMARY): Support bare struct-style construction — make construction symmetric with patterns** … A dev who writes a `match` arm `NotFound { msg }` and then can't write `NotFound { msg: "x" }` to build the value hits a wall that has no mental model behind it. … Symmetry is the whole game. Bare tuple-style construction (`Leaf(1)`) already works AND is the canonical form in §3.4. Bare struct-style construction is the *only* asymmetric hole left.

> **PROPOSAL 2 (THE AMBIGUITY RULE …): struct name wins, with a hard error on true ambiguity, NOT silent shadowing** … 1. If the name is in `named_type_map` … AND is NOT also a variant name → it's the struct. 2. If the name is a variant name AND NOT a struct → it's the variant. 3. If the name is BOTH … → **hard compile error** `error[AmbiguousType]`.

> **P3 (costed fallback):** If bare construction is rejected, at minimum upgrade the `UnknownType` error to name the enum and suggest the qualified form.

### PLT (plt)

Proposed support (P1) with **hint-directed resolution before global-unique** (R2 before R3),
and in Phase A argued the collision should be a **declaration-time** error.

### DevOps/Tooling (devops)

Proposed support (DV-1). For the collision rule offered **struct-wins + a warning** (DV-2b).
Independently flagged two orthogonal wins: a better unknown-name error suggesting
`EnumType.Variant` (DV-4), and that **`blink fmt` must NOT canonicalize bare↔qualified** (DV-3).

### AI/ML (aiml)

Proposed support (A1) leaning on **global uniqueness**, with A2 as a hint-directed fallback.
Scored expected-type-directed resolution a **C on learnability** because the model must
rebuild the expected type from return/carrier/call-arg context that may not be in view.

### Minimalism (min)

Lone dissent on Q1 (M1: keep `EnumType.Variant {}` canonical, reject the bare form), with
M2 as a fallback if outvoted: support it, but make collisions a **use-site** error. Core
instinct: fewer surface forms = simpler.

---

## Phase A.5 — Mechanical Dedupe

- **Support bare construction:** sys, web, plt, devops, aiml (5). Reject: min (1).
- **Resolution rule:** all supporters converge on reusing the pattern fallback chain (hint → global `get_variant_enum_tid`). plt most explicit: hint *before* global.
- **Collision rule (the fault line):** declaration-time error (plt, aiml, sys-S2) vs use-site error (sys-S1, web-P2, min-M2) vs struct-wins+warning (devops DV-2b). **All six reject today's silent struct-wins.**
- **Orthogonal wins flagged:** better unknown-name error (devops, web, sys); `blink fmt` no-canonicalize (devops).

≥3 distinct options on Q3 → **Phase B (open debate) triggered.**

---

## Phase B — Open Debate

The debate turned on a **codebase fact** that falsified plt's Phase A premise.

### Round 1 — plt argues use-site is the only complete rule

> A struct `Foo` in module A and a variant `Foo` in enum E in module B is NOT a conflict that module authors can see or prevent at declaration time — neither module knows about the other. A declaration-time error can therefore only fire for SAME-module collisions; it is structurally incapable of catching the cross-module case, which is exactly where the silent-struct-wins bug bites hardest. So declaration-time is necessary-but-insufficient.

### The pivot — the whole-program symbol table

The moderator verified in source that `named_type_map` and `evar_pool` are **single global
tables, populated from every module** at registration. That refutes plt's "declaration-time
can't catch cross-module" premise: registration-time detection sees collisions globally.
This reframed Q3 into **two distinct collision kinds**.

### sys — the narrow-scoping consistency check

> CRITICAL CONSISTENCY CHECK for the declaration-time rule: it must reject struct-name-vs-variant-name collision ONLY. It must NOT reject two enums sharing a variant name (e.g. `Pending` in both `JobState` and `NetState`) — that's a common legitimate pattern and precisely what the binding-hint (Q2) exists to resolve. So the declaration-time invariant is narrowly "a struct name may not equal an enum variant name (and vice versa)," not "all constructible names are globally unique."

### aiml — adopts the narrow rule, then flips to declaration-time

> sys's consistency check **corrects a real flaw in my original A1 and I adopt it wholesale.** My Phase A "uniqueness-enforced" framing was too broad — it would have rejected two enums sharing a variant name … That's exactly the case the binding-hint in Q2 is designed to resolve.

> Under declaration-time, the narrow invariant "a bare Name is NEVER both a struct and a variant" holds *globally and always*. … There is no expected-type to reconstruct, no hint to infer, no site-local arbitration. My own A2 scored expected-type-directed resolution a **C on learnability** … Declaration-time deletes that entire step.

### plt — converges back to declaration-time with the narrow carve-out

> sys just resolved the exact worry that drove me OFF declaration-time … The declaration-time invariant is ONLY: **a struct name may not equal an enum variant name (and vice versa).** It is NOT "all constructible names are globally unique." Two enums both declaring `Pending` (JobState, NetState) is LEGAL and stays legal — that collision is resolved by the binding hint (Q2), never by a declaration error. This is the load-bearing distinction.

> the two collision kinds are DIFFERENT and must be handled by DIFFERENT mechanisms.

### web — moves from use-site to declaration-time

> Declaration-time error is the most *teachable* possible moment: you get the error the instant you write the colliding name, at the definition, with both definitions in front of you, before any use exists. … devops's struct-wins+warning … is the one I'd push back on hardest: a warning that everyone learns to ignore is silent-struct-wins with extra steps; it doesn't prevent the wrong-type-value bug, just annotates it.

On Q2, web switched to hint-first on monotonicity:

> under uniqueness-only, a program compiles today, then a teammate adds a second unrelated enum with a same-named variant in a far-off module, and a working construction site elsewhere breaks with no edit to that site. … Hint-directed-first means the expected type at the use site pins the resolution locally, so a distant addition can't retroactively break you. Local predictability beats global simplicity.

### sys — rejects banning variant-vs-variant

> I REJECT min's uniqueness-only-because-he'd-ban-it: banning two enums from sharing a variant name is too aggressive — it breaks ergonomic, real-world enums (every state machine wants `Pending`/`Done`). The cost of keeping hint-directed resolution is zero (compile-time, and the hint plumbing already exists for patterns at typecheck.bl:5288).

**Outcome of Phase B:** the panel converged on a two-tier model — Kind A (struct vs variant)
= declaration-time `NameCollision`; Kind B (variant vs variant) = legal, hint-resolved, with a
use-site `AmbiguousConstruction` for the no-hint residual.

---

## Phase C — Silent Vote (UNANIMOUS 6-0 on all questions)

### Minimalism (verbatim)

> === Q1: Support bare struct-style variant construction? ===
> Vote: A (YES).
> Reasoning: Three of the four bare construction forms already exist; struct-style variant is the lone hold-out. The asymmetry is itself surface area — an arbitrary carve-out a user must memorize. Killing the exception is subtraction, not addition: we remove a rule, not add a feature. I held one condition and it is met by Q2/Q3: no path silently picks a winner.
> Concern: If resolution ever drifts toward silent disambiguation, this "subtraction" quietly becomes new hidden machinery and the win inverts.
>
> === Q2: Resolution rule? ===
> Vote: A (qualified → hint-directed first → global-unique lookup; no-hint-and-non-unique → use-site error).
> Reasoning: Hint-directed-first reuses inference the compiler already does for the other bare forms, so it adds no new user-facing concept. … The non-unique no-hint case MUST be a loud use-site error — that is the price of admission for keeping the feature honest.
> Concern: Two slightly different lookup phases (hint vs global) can confuse users about why one site compiles and a near-identical one errors; diagnostics must name the missing hint explicitly.
>
> === Q3: Collision rule? ===
> Vote: A (Package A).
> Reasoning: Kind A (struct name == variant name) is a real declaration-time ambiguity with no sane resolution, so a hard error there is justified surface. But extending the ban to variant-vs-variant (Package B) spends user-facing rule-surface to forbid a perfectly legal pattern, just to dodge internal machinery that already exists — wrong trade. … Struct-wins-plus-warning (C) is the silent-winner path and is my hard red line — rejected.
> Concern: A declaration-time error scoped to struct-vs-variant only must be precisely worded, or users will assume it implies the broader uniqueness rule we deliberately did NOT adopt.

### AI/ML (verbatim final vote)

> Revised final vote:
> - **Q1: YES**
> - **Q2: hint-directed FIRST, then global** (governs the two-enums-same-variant case only)
> - **Q3: DECLARATION-time hard error, narrowly scoped to struct-name == variant-name.**
> - Reject devops struct-wins+warning.

> Concern (on the record): declaration-time error must stay the NARROW invariant — struct-name == variant-name only. Two enums sharing a variant name … must remain legal; THAT case is the one where the hint legitimately does work.

### Systems (verbatim final position)

> declaration-time for struct-vs-variant (Q3), hint-directed + residual use-site error for variant-vs-variant (Q2). Cheapest, most monotonic, most ergonomic combination.

> Sub-point 1: CONFIRMED. Declaration-time bans struct-name == variant-name ONLY. It must NOT ban two enums sharing a variant name … Holding this firmly.

### Web/Scripting (verbatim final position)

> Net change from my Phase A: Q2 hint-first (was agnostic), Q3 declaration-time (was use-site).

> Concern: a warning that silently decides which type you ALLOCATE is a miscompile hazard in a hi-vis vest. Warnings get ignored; the codegen divergence is real.

### PLT (verbatim final position)

> Q1: YES. … Q2: hint-first then global-unique. … Q3: declaration-time hard error, NARROWLY scoped to struct-name == variant-name (sys's consistency check), with cross-module handled per (i) above [registration over the merged whole-program symbol table].

### DevOps (final position)

Conceded the warning approach (DV-2b) to declaration-time once the whole-program symbol-table
fact made the diagnostic decl-scoped and cheap. Carries forward the two orthogonal wins it
raised: the construction-aware unknown-name suggestion and the `blink fmt` no-canonicalize
guarantee.

### Phase D — NOT triggered (all questions 6-0).

---

## Final Spec

1. **Bare struct-style construction is supported.** `Variant { field: expr }` with no
   qualifier resolves to the enum variant, mirroring the existing pattern fallback
   (`get_variant_enum_tid`, `typecheck.bl:5288`). Emitted C is byte-identical to the
   qualified form.

2. **Resolution order** at a bare struct-style site `Name { ... }`:
   qualified (`E.V { .. }`) → **hint-directed** (expected type from binding annotation,
   return type, fn-arg param, or `Ok`/`Err`/`Some` carrier) → **global-unique**
   `get_variant_enum_tid` lookup. Hint is consulted FIRST among the unqualified rules —
   load-bearing for monotonicity, so a distant enum declaration never retroactively breaks
   a locally-determined site. Resolution is fully compile-time; no runtime dispatch.

3. **Two collision kinds, two mechanisms:**
   - **Kind A** — a struct name equals an enum variant name: **declaration-time hard error**
     `error[NameCollision]` (E0518), scoped to struct-vs-variant ONLY, detected over the
     whole-program global symbol table (catches cross-module), two-span message naming both
     declarations.
   - **Kind B** — the same variant name in two different enums: **LEGAL**, resolved by the
     hint. The residual case (bare construction, no hint, name non-unique across enums) is a
     use-site `error[AmbiguousConstruction]` (E0519). **No path ever silently picks a winner.**

4. **Orthogonal (6-0):**
   - Replace the misleading `UnknownType` on a bare construction of an unknown name with a
     construction-aware message suggesting `EnumType.Variant` (edit-distance over `evar_pool`,
     with a confidence threshold to avoid misleading typo suggestions).
   - `blink fmt` must NOT canonicalize bare↔qualified (a formatter must never change name
     resolution).

## Locked Design Points

- The declaration-time `NameCollision` rule is the **narrow** invariant (struct-name ==
  variant-name only). It does **not** require all constructible names to be globally unique;
  two enums sharing a variant name is explicitly legal. The error must be worded so it does
  not imply the broader (rejected) global-uniqueness rule.
- Resolution must stay fully compile-time (no runtime dispatch).
- Hint propagation must be reliable in return/arg/field/let positions, or bare construction
  spuriously errors.
- The `NameCollision` diagnostic is decl-scoped, two-span, and stable (emitted once at the
  declarations, not re-emitted per use site).
- The unknown-name suggester needs a confidence threshold.
- Silent struct-wins (today's behavior) is killed on every path.

**Implementation** is filed separately as a `type:project` ticket (see `hrwn4h`'s linked
impl ticket). It follows the 3-step refactor bootstrap protocol since it changes existing
silent behavior.
