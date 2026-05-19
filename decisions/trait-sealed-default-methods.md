[< All Decisions](../DECISIONS.md)

# Trait Sealed-Default Method Semantics — Design Rationale

### Problem Statement

The Blink spec uses keyword `final` on exactly one trait default method —
`Display.display` (`sections/03_types.md`) — and defines `SealedMethodOverride`
as a Display-specific diagnostic. The keyword was never formalized as a
general language feature.

The spec was silent on:

- Whether any trait author can write `final fn` on their own trait.
- Whether trait default methods are by-default overridable or sealed.
- Override semantics when overrides are allowed (replace, shadow, super-call).
- Classification of existing stdlib derived-view defaults (`Eq.ne` and
  `Sized.is_empty` were spec'd with default bodies but no override-control
  policy).
- How sealing behaves when traits extend other traits.
- Effect-row interaction for overrides.
- Migration story when an open default is later sealed.

This deliberation formalizes `final` as a general trait-default modifier,
classifies the existing stdlib derived-view defaults, and adds the
inheritance / effect / migration rules needed for the design to remain sound
as the spec grows.

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML,
minimalism) deliberated in Phase A independent proposal → Phase A.5
mechanical dedupe → Phase B round-1 debate → Phase C silent ballot.

#### Phase A — Independent proposals

- **Systems (sys):** "Open by default, opt-in `final`. Sealing every default
  pessimizes hot paths: an iterator adapter that ships as a default body
  *must* be overridable so a concrete impl can supply a tighter
  specialization (e.g., `.count()` on a `Vec` reading `.len()` directly
  instead of walking). But a derived-view default whose correctness
  *depends* on agreement with required methods — `Display.display` over
  `fmt`, `Eq.ne` over `eq`, `Sized.is_empty` over `len` — must be sealed,
  because override creates two values for the same observable property. So:
  generalize `final`, default open, seal the derived-view defaults in
  stdlib." (Option O)

- **Web/Scripting (web):** "Open by default is what every mainstream
  language with default methods does — Java, Rust, Swift, Kotlin. Devs
  arrive with that prior. `final` as opt-in matches Java's keyword for the
  same purpose, which is the corpus signal. Allow super-call (`Trait.method(self)`)
  inside an override — users will reach for it and the absence will be a
  papercut." (Option O, with super-call)

- **PLT:** "Override semantics under monomorphization is the load-bearing
  question. There is no inheritance chain, no MRO, no vtable to walk —
  every call is statically resolved against the impl. *Replace* is the only
  semantics that has a meaning in this model. A 'super-call' from inside an
  override would have to mean 'compile this body with the trait default's
  body substituted for the surrounding method', which is a textual
  transformation, not a dispatch primitive. Reject super-call. Also:
  sealing must be monotonic down the supertrait chain — if a supertrait
  says a method is `final`, no subtrait or `impl SubTrait` may un-seal it,
  or the property the seal protects evaporates. Strengthening (re-sealing
  an open supertrait default in a subtrait) is murkier; I'd defer that
  question — it requires re-stating the body and invites confusion."
  (Option O, reject super-call, monotonic sealing, defer strengthening)

- **DevOps/tooling (devops):** "The migration story matters more than the
  keyword. Today `Eq.ne` is open in the spec. If we land 'now sealed', every
  downstream that overrode it breaks at the same release boundary. We need
  a deprecate-then-seal hop: mark the default `@deprecate_override` in
  release N (existing overrides keep compiling with a warning), flip to
  `final` in release N+1 (warnings become errors). Same pattern as
  `@deprecated` on functions — reuse the attribute mechanism we already
  have. Otherwise: agreed, generalize `final`, default open." (Option O,
  plus migration attribute)

- **AI/ML (aiml):** "Models trained on Rust will recognize the keyword
  immediately — Rust uses `final`-ish semantics via 'sealed traits' but
  doesn't seal individual default methods, so the closest analogue is
  Java/Kotlin/Swift's per-method `final`. The diagnostic surface is what I
  care about: a sealed override must produce a self-correcting error — name
  the trait, name the method, name the required method whose body the seal
  derives from, suggest implementing that instead. Originally I proposed
  sealed-by-default with `open` opt-in (Option S) on the AI-first
  consistency argument — fewer accidental footguns from accidentally
  overriding a derivation. But Sys+PLT's point that iterator adapters
  *need* override for perf flipped me: open-by-default with aggressive
  sealing of derived views in stdlib is the right shape. I fold S into O."
  (Option O after Phase B flip)

- **Minimalism (min):** "I will not vote for Option O under any variation.
  The whole keyword is one trait deep — `Display.display`. Generalizing a
  keyword to its one current use site is YAGNI. Two principled minimal
  outcomes exist: (R1) reject `final` entirely, lower `Display.display` to
  a free function `fn display[T: Display](x: T) -> Str`; or (R2) keep
  `final` Display-specific, don't generalize it. R2 is my preferred fall-back.
  Failing that, S (sealed-by-default) is closer to my values than O — at
  least sealed-by-default means *adding* a keyword to open up a default is
  a deliberate act. O means every default method declaration is a
  deliberation about whether to seal it, which is decision-fatigue across
  the trait surface. Principled dissent; will not block."
  (Option R2, fall-back S, dissent on O)

#### Phase A.5 — Mechanical dedupe

The option-space collapses to:

- **Option O** — overridable-by-default, `final` opt-in to seal (sys, web,
  plt, devops; aiml after Phase B flip).
- **Option S** — sealed-by-default, `open` opt-in (aiml original; min
  fall-back).
- **Option R1** — reject `final`, make Display a free function (min
  primary minimal answer).
- **Option R2** — keep `final` Display-specific, don't generalize (min
  preferred fallback).
- **Option I** — inferred sealing from body shape, no keyword (raised and
  dropped in A — too magical; no panelist held it through B).

Q2 (classification of `Eq.ne` and `Sized.is_empty`) and Q3-Q6 (override
semantics, inheritance, effects, migration) became separate questions for
Phase B once Q1 main-direction stabilized on Option O.

#### Phase B Round 1 — Debate highlights

**Q1 (main direction).** Five panelists ready to vote on Option O with
aggressive stdlib sealing of derived-view defaults. aiml explicitly folded
S into O after Sys/PLT's iterator-adapter-perf argument. min held R2 as
primary, S as second choice, "will not vote O under any variation"
(dissent).

**Q2 — stdlib classification of `Eq.ne` and `Sized.is_empty`.** sys: "Both
are pure derivations of required methods (`eq`, `len`). Drift risk is the
exact same as `Display.display` over `fmt`. Seal them." plt agreed: "If
`x.ne(y)` can disagree with `!x.eq(y)`, the trait's algebra is wrong; the
type-checker should make that disagreement structurally impossible."
devops, aiml, min agreed. web (dissent): "Power users sometimes want to
optimize `ne` with a SIMD path that doesn't go through `eq`. Closing that
door has a cost." After plt's reply ("the SIMD optimization belongs on
`eq`; the trait's contract is that `ne == !eq`, not that `ne` is a free
slot"), web conceded: "Fine, I'll concede on the substance — but record
this is the one place I'd reopen if a real perf case lands."

**Q3 — override semantics for open defaults.** plt: "Replace-only. Under
monomorphization there is no super-chain; a super-call would have to be a
textual transformation, not a dispatch primitive. Users who want the
default's body can factor it into a free helper." sys, devops, aiml, min
agreed. web (dissent): "Super-call is ergonomic; users will reach for it."
plt responded: "What semantics do you propose? Re-instantiating the trait
default with the impl's `Self` is the only interpretation, and that's a
new kind of dispatch primitive — once we add it, we own its corner cases
forever. Show me a use case that the free-helper pattern doesn't cover."
web (concession): "I cannot. Concede."

**Q4 — sealing inheritance under trait extension.** plt original; sys, web,
devops, aiml, min all agreed: monotonic, sealed-stays-sealed down the
chain. Re-sealing an open supertrait default in a subtrait was raised by
plt as a sub-question and explicitly deferred: "It requires re-stating the
body and creates two methods with the same name visible to impls. Park it,
revisit when there's a concrete need."

**Q5 — effect-row interaction for open overrides.** plt original: "Open
override row `R_o` must satisfy `R_o ⊆ R_d` against the default's row
`R_d`. Override may narrow, may not widen — narrowing preserves the
trait's stated upper bound on `m`'s effects across all `T`, which callers
parameterized over `T: Trait` rely on." sys, web, aiml agreed. devops and
min deferred ("don't object, but haven't thought through enough corner
cases to vote"). Expected tally: 4-0 with 2 abstain.

**Q6 — migration story.** devops original: "`@deprecate_override`
attribute on the open default, `W0731 OverrideOfDeprecatedDefault` at
override sites, then flip to `final` in the next release where the warning
becomes `E0731`." sys, web, aiml agreed. plt deferred ("plumbing detail").
min (dissent): "YAGNI — defer the whole migration apparatus until we
actually flip a stdlib default the first time. The hop costs an extra
attribute and a release of warnings; the alternative is one breaking
release. We don't have the data to know which is worse."

#### Phase C — Silent ballot

Phase C ballots returned after Phase B closed. Per-question results:

| Question | Result | Tally | Dissent |
|----------|--------|-------|---------|
| Q1 — Generalize `final` (Option O) | Pass | 5-1 | min → R2 |
| Q2 — Seal `Eq.ne` and `Sized.is_empty` | Pass | 5-1 | web (recorded reopen-if-perf condition) |
| Q3 — Replace-only override (no super-call) | Pass | 5-1 | web (conceded in B; ballot logged dissent for record) |
| Q4 — Monotonic sealing under trait extension | Pass | 6-0 | — |
| Q5 — Effect-row subtype required for open overrides | Pass | 6-0 | — (devops/min Phase-B defers flipped to yes on ballot) |
| Q6 — `@deprecate_override` + W0731 migration hop | Pass | 5-1 | min → defer migration apparatus |

No question closer than 5-1; Phase D not triggered. Sub-trait re-sealing
(strengthening) explicitly deferred to a follow-up `type:spec` ticket.

#### Phase 8.5 — AI-First Review

Scored the resolved decision against the five AI-first criteria:

- **Learnability.** `final` is short, the keyword matches Java/Kotlin/Swift,
  and "open by default, `final` opts in to seal" is one sentence. Pass.
- **Consistency.** Override semantics is *replace*, single rule, no super-call
  corner case. Inheritance rule is monotonic with one direction. Effect-row
  rule is the same subtyping users already learned in §4.5. Pass.
- **Generability.** The diagnostic is self-correcting: every sealed
  override produces `E0731` naming the trait, the method, and the required
  method to implement instead. AI/ML's Phase-A criterion. Pass.
- **Debuggability.** No runtime indirection — sealing is enforced at
  typecheck. A `final` violation surfaces immediately at the `impl` block.
  Pass.
- **Token efficiency.** One modifier keyword, three rules (replace,
  monotonic, effect-subtype), one migration attribute. Total surface: ~5
  spec paragraphs. Pass.

### Final Spec

1. **`final` is a method-level modifier on trait default methods only.** It
   appears nowhere else in the language.
2. **Trait default methods are overridable by default.** Trait author opts
   into sealing per-method with `final fn name(...) { body }`. `final` on a
   body-less method is a parse error (E0732 FinalRequiresBody).
3. **Override semantics: replace-only.** An impl's body fully replaces the
   default at every call site for that implementing type. No super-call to
   reach the default's body from inside an override. To reuse the default's
   body, factor it into a free helper.
4. **Monotonic sealing under trait extension.** If `SubTrait : SuperTrait`
   and `SuperTrait` seals `m`, then no `SubTrait` declaration and no
   `impl SubTrait` may override `m`. Strengthening (re-sealing an open
   supertrait default in a subtrait) is deferred to a follow-up ticket.
5. **Effect-row subtype required for open overrides.** When an open default
   declares effect row `R_d` and an `impl` provides an override with row
   `R_o`, the typechecker requires `R_o ⊆ R_d` under the §4.5 lattice. An
   override may narrow but may not widen. `final` defaults are
   effect-monomorphic at declaration.
6. **Stdlib classification.** `Eq.ne` and `Sized.is_empty` are sealed
   (`final`) — both are definitional derived views of required methods
   (`eq`, `len`). Iterator adapter defaults remain open (per §3c.1 — the
   performance-overridable adapter case).
7. **Migration: `@deprecate_override` warning hop.** Flipping a stdlib
   default from open to sealed is a two-step process: mark with
   `@deprecate_override` first (existing overrides compile with `W0731
   OverrideOfDeprecatedDefault`), then in the next release remove
   `@deprecate_override` and add `final` (override sites that ignored the
   warning hit `E0731 SealedMethodOverride`). Sealed→open is non-breaking.

### Deferred Follow-ups

- **Sub-trait re-sealing (strengthening).** Whether a subtrait may declare
  `final fn m` over an open supertrait default `m`. Filed as a separate
  `type:spec` ticket per Phase B PLT note.
- **`@deprecate_override` attribute infrastructure.** Reuses the existing
  attribute mechanism (`@allow(...)` is already parsed); ride on the same
  rails. Bundled into the implementation ticket for 344dnd.
- **Web's `Eq.ne` SIMD reopen condition.** Recorded: if a real perf case
  for non-`eq`-routed `ne` materializes post-v1, this decision is the
  reopen point.

### Vote summary

Q1: 5-1 generalize `final` (min → R2). Q2: 5-1 seal `Eq.ne` and
`Sized.is_empty` (web dissent, conceded). Q3: 5-1 replace-only (web
dissent, conceded). Q4: 6-0 monotonic. Q5: 6-0 effect-row subtype. Q6: 5-1
deprecate-override migration (min → defer).
