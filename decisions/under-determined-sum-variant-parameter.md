[< All Decisions](../DECISIONS.md)

# Under-Determined Sum-Variant Type Parameter — Design Rationale

**Spec gap:** br `bc65cn` (`type:spec`, user-visible) — *an unconstrained sum-variant type
parameter (an Ok-only `Result` error type, a None-only `Option` inner) resolves
position-dependently.*

**Status: spec resolved; implementation tracked separately.** The normative spec lives at
`sections/03_types.md` **§3.4** *Under-Determined Types*, in the subsection beginning "The judgment
is a property of the type, not of the syntactic position." This rationale is the deliberation record.

## The gap

The compiler answered the *same* under-constrained `Result[Int, <unbound Err>]` differently by
syntactic position:

1. **Direct `let`** — `let r = Ok(3); match r { Ok(v) => v  Err(e) => 0 }` → **rejected** with
   `error[CannotInferType]` (E0301) at the binding. Correct per `8vcj2c`.
2. **Tuple element in a match scrutinee** — `match (Ok(3), 9) { (a, n) => { match a { Ok(v) => v
   Err(e) => 0 } } }` → **silently accepted**; codegen fabricated an arbitrary carrier
   `blink_Result_int_str` (`int64_t ok` / `const char* err`) whose `Err` type was never written — a
   latent miscompile, and an ODR hazard under `--link-archive`.

Two defects: (i) position-dependent inconsistency — one value, two answers; (ii) in the accept
branch, an invented `Err` type. The fabrication seam is verified at `src/codegen_types.bl` (the
literal `"Result_int_str"` / `"Option_int"` fallthroughs). This blocks `jctkac` (delete the flat
`ScopeVar` type fields): the flat path fabricates `blink_Result_int_str` precisely because the tid
under-resolves in these positions, and the flat field cannot be deleted while that fabrication is
the only thing keeping such programs compiling.

**Governing prior decision — `8vcj2c`** ([under-determined-types.md](under-determined-types.md),
6-0): an unbound type variable at a materialization boundary is `error[CannotInferType]` (E0301),
never defaulted, applied uniformly, strict (no unobserved-local carve-out), no surface `unknown`,
with the I0001 ICE backstop keyed on type-variable *kind*. The ticket's question: is an
unconstrained sum-variant type parameter an **instance** of that rule (→ E0301), or a
**distinguishable** case (→ resolves to some defined type, e.g. a bottom/`Never`)? Blink has no
`Never`/bottom type available to inference.

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in
independent-proposal → dedupe → silent-vote rounds. Phase B (open debate) was not needed — Phase A
converged. Phase D (focused re-debate) was skipped by soft consensus on Q3 (below).

#### Phase A — Independent proposals

Overwhelming convergence. Every panelist ruled the unconstrained sum-variant parameter
**under-determined → `error[CannotInferType]` (E0301), uniform across every syntactic position**;
the tuple/scrutinee accept path is a bug to delete along with its fabricated carrier; defaulting the
open error type to `Never`/⊥ is **rejected**. No panelist proposed "well-formed value / resolves to
a defined type."

- **PLT:** *"An unconstrained sum-variant type parameter (Ok-only `Err`, None-only `Option`) is the
  SAME free-metavariable-at-a-materialization-boundary case as 8vcj2c's `let x = []`. It is
  under-determined → error[CannotInferType] (E0301), uniformly, in every syntactic position."* On the
  bottom-type temptation: *"HM produces α, not Never. Nothing in the constraint set entails
  `α = Never`. There is no rule 'a variable appearing only in never-constructed positions solves to
  ⊥.' Adding one is a defaulting rule — precisely what 8vcj2c Q1 banned 6-0. `[Never/α]` is the
  identical unlicensed substitution PLT already vetoed as `[Void/α]`."* And: *"'Ok-only ⇒ Err
  uninhabited' is a whole-program reachability property, not a typing constraint … Making α=Never
  contingent on 'no Err reachable' reintroduces the carve-out under a new name."* On the mechanism:
  *"the tuple-literal match-scrutinee fast-path captures the carrier for codegen without first
  demanding the scrutinee's type be metavariable-free. So α slips through to codegen, where the
  'Void'/arbitrary fallthrough fabricates blink_Result_int_str with an invented const char* err."*

- **Web/Scripting:** *"An Ok-only Result (Err never pinned) and a None-only Option are
  under-determined and therefore error[CannotInferType] (E0301) — the exact same answer 8vcj2c
  already locked for `let n = None`, `let x = []`, `Map()`. There is no second answer to invent;
  there is only a position-dependent bug where one code shape skips the check. Fix the skip."* On the
  only principled alternative: *"There is exactly one principled way `Ok(3)` with an unconstrained
  Err could be a well-formed value: a bottom type, `Result[Int, Never]` … It is blocked, and not by
  preference. sections/03_types.md:3138 states as a language invariant: 'There is no null, nil,
  None-as-implicit-value, or bottom type that inhabits every type.'"* Cross-language anchor: *"Rust's
  `let r = Ok(3);` alone yields `Result<i32, _>` and rustc errors E0282: type annotations needed …
  the same error we're proposing."* Its live ask was Q3: *"a local repair for scrutinee position —
  settle the variant-constructor explicit-type-arg spelling (`Ok[Int, Str](3)` preferred). No
  expr-level ascription exists, so without this the only repair is a structural rewrite."* And the
  message: *"The message must name that the `Err(e)` arm discards its payload — else the dev reads
  the error as wrong."*

- **AI/ML:** *"E0301 uniform, all positions. An unbound Err on `Ok(x)` is the same defect as the
  already-settled bare `None` — a type parameter inference left open."* On why it is forced:
  *"`Some(5)` pins Option's only parameter → fully determined → legal. `None` leaves that one
  parameter open → E0301. `Ok(3)` pins one of Result's two parameters, leaves E open → E0301, by the
  same clause."* The domain argument: *"The accept branch fabricates blink_Result_int_str — an Err
  type the program never wrote — and the binary runs. That is the one failure mode I vetoed in
  8vcj2c, verbatim: 'Silent-wrong is the one failure mode an LLM author has zero recourse against.'"*
  On the Never option: *"it would make inference produce a type the program never wrote — exactly the
  property Q2 forbade (`unknown` 'is never produced by inference'). An inferred Never in an Err slot
  is the same category error as an inferred unknown."*

- **DevOps/Tooling:** *"under-constrained sum-variant param is under-determined →
  error[CannotInferType] (E0301), UNIFORM across every position. The tuple-element accept branch is
  the worst-ranked outcome my domain can produce."* On the mechanism, grounded in-tree: *"E0301
  today emits NO machine-applicable quick-fix. src/typecheck.bl:1327-1335 sets only `help` text …
  src/lsp.bl:1078 SKIPS any diag whose `fix_action == ""`."* The tooling veto on the accept branch:
  *"hover: would report `Result[Int, Str]` — a concrete type the program NEVER WROTE and inference
  NEVER JUSTIFIED … A confidently-wrong hover is worse than a red squiggle … This is the TypeScript
  implicit-`any` failure my Q2 vote already rejected, wearing a concrete type's clothes."* On Q3:
  *"the repair is the narrowest edit that reaches that param — the binding annotation when a binding
  dominates the value, else the explicit type-argument list on the constructor itself. Both are
  already legal Blink and already in §3.4."* And on the quick-fix honestly: *"Do NOT promise a
  one-click machine-applicable fix here … The LSP code-action must be a SNIPPET with a tabstop
  placeholder … `Ok[Int, ${1:ErrType}](3)` … the rust-analyzer 'insert type placeholder' pattern."*
  The secondary span: *"'the Err type of this Result is never constrained by an annotation, a `?`, an
  error-reading arm, or a return type' — it enumerates the four things that WOULD have pinned E."*

- **Minimalism:** *"This is NOT a vote-worthy new rule. It is an implementation-conformance bug
  against an already-decided rule (8vcj2c / §3.4). The fix is pure subtraction: delete the
  position-dependent accept-path and let the existing E0301 rule fire uniformly. No new spec
  MECHANISM."* On Never-defaulting: *"It is a defaulting rule wearing a bottom-type costume.
  `[Never/α]` for an α the program never constrained is exactly the unlicensed substitution 8vcj2c
  forbade — the same shape as `[Void/α]`, just a prettier target … The fabricated
  blink_Result_int_str becomes a fabricated blink_Result_int_never — still fabricated."* Min also
  surfaced the bottom-type spec self-contradiction: *"Blink already HAS a `Never`/bottom type today.
  `panic(msg: Str) -> Never` … (sections/02_syntax.md:1319, 1328)"* — while 03_types.md:3138 denies
  it — and held that Never-defaulting is rejected regardless. On the normative text: *"one clarifying
  'position-independent' sentence in §3.4 is all the normative text this fix needs … My vote does
  not hinge on the sentence."*

- **Systems:** (Phase A consonant with its Phase C ballot, quoted below.) The load-bearing systems
  point: *"Every mono symbol must provably correspond to a fully-resolved type; the fabrication seam
  violates that — Result_int_str collapses a genuine `Result[Int,Str]` and an under-determined
  `Ok(3)` onto one symbol (ODR hazard under `--link-archive`) and stuffs a garbage `const char* err`
  into the carrier, a wild-pointer read strictly worse than the `Void_Void` wrong-vtable case."*

#### Phase A.5 — Mechanical dedupe

| Question | Convergence |
|---|---|
| **Q1** — under-determined → E0301 uniform, or well-formed (resolves to a type)? | All 6 → **E0301 uniform**; no one proposed "well-formed" |
| **Q2 (mechanism)** — delete the `Result_int_str`/`Option_int` fabrication, I0001 backstop | All 6 unanimous → folded into Q1 for the vote |
| **Q4** — default the open error type to `Never`/⊥? | All 6 → **reject** (a defaulting rule 8vcj2c banned) |
| **Q3 (repair for non-`let` positions)** | **The one live variation** |

**Facts surfaced (moderator, not votes):**
1. `Ok[Int, Str](3)` (variant-constructor explicit type args) appears **zero** times in the codebase
   today — so Q3 option A needs impl/parse confirmation regardless of the vote.
2. A **separate spec self-contradiction** exists on whether a bottom type is present:
   `02_syntax.md:1328` calls `panic() -> Never` a "bottom type, which inhabits every type";
   `03_types.md:3138` says "There is no … bottom type that inhabits every type." Logged as its own
   ticket; it does not move this vote — every panelist rejects `Never`-defaulting regardless of
   whether `Never` is nameable. Web recorded the sturdier ground: *"even if it does [exist],
   silently substituting it is the banned `[Never/α]` default."*

#### Phase C — Silent vote

**Q1 — under-determined → E0301 uniform / delete fabrication / reject Never-default: A wins 6-0.**

- **PLT:** A — *"An Ok-only Err is a free metavariable α at a materialization boundary — the exact
  HM-family hard-error case, identical in kind to 8vcj2c's `let x = []`. Defaulting α to Never is the
  same unlicensed `[⊥/α]` substitution I vetoed as `[Void/α]` … 'Err is never constructed' is a
  whole-program reachability property, not a typing constraint."* Concern: *"A is only real if the
  E0301 check runs structurally at every materialization boundary (tuple elements, scrutinee
  sub-positions), not just the `let`; a missed boundary keeps the fabrication seam alive behind a
  now-deleted fallthrough, converting a silent miscompile into an I0001 ICE rather than a clean user
  error."*
- **Web:** A — *"even if [Never] does [exist], auto-resolving an open Err to `Result[Int, Never]` is
  a defaulting rule — inference picking a concrete type the program never wrote — which 8vcj2c banned
  6-0."* Note recorded: *"If a user writes `Result[Int, Never]` explicitly (not inferred), that's a
  legitimate well-formed type and must compile — the ban is on inference choosing it, not on the type
  existing."*
- **AI/ML:** A — *"This is the `GKV[K,V]` clause of 8vcj2c applied to Result's second parameter …
  The fabrication seam is the one failure mode an LLM author cannot self-correct: green compile,
  invented Err carrier, wrong runtime type, and under `--link-archive` an ODR miscompile with no
  diagnostic text to feed back."* Concern: *"Deleting the seam must not regress the fully-determined
  cases that legitimately mint `Option_int`/`Result_int_str` … the I0001 backstop must key on the
  unsolved kind, never on the resulting concrete tag, or it fires on valid programs."*
- **DevOps:** A — (Phase A summary vote) *"E0301, uniform across all six positions. Caret on the
  open constructor (or the dominating binding); repair = binding annotation when a binding dominates,
  else explicit type application `Ok[Int, ${1:_}](x)` on the constructor."*
- **Systems:** A — *"Every mono symbol must provably correspond to a fully-resolved type; the
  fabrication seam violates that … Deleting the seam and failing closed at I0001 keyed on the metavar
  kind means the incorrect program never becomes a binary. Never-default buys no zero-cost win
  without dead-arm elimination and drags a `⊥ <: T` subtyping lattice into a language that is HM by
  declaration."* Concern: *"The I0001 backstop must key strictly on the unbound-metavar kind, never
  on a resulting `\"Void\"`/`\"int\"`/`\"str\"` tag — a tag-keyed check would either mask a genuine
  `Result[Void, Str]` or let a real fabrication slip through."*
- **Minimalism:** A — *"This is the smallest possible outcome — it ADDS nothing and SUBTRACTS the
  fabrication seam plus one invented mono symbol … B would re-open a settled decision and
  re-institutionalize the accident (now spelling it `Result_int_never` instead of
  `Result_int_str`)."* Concern: *"The I0001 ICE backstop must key on the type-variable KIND, not a
  'Void'/'Never' tag, or a legitimate `Result[Int, Never]` a user writes explicitly could trip it."*

**Unanimous impl constraint (every ballot):** the I0001 backstop MUST key on the unbound-metavar
**kind**, never on the resulting concrete tag (`"Void"`/`"int"`/`"str"`/`"Never"`) — a tag-keyed
check would both mask a legitimate `Result[Void, Str]` / user-written `Result[Int, Never]` and let a
real fabrication slip through.

**Q3 — repair for non-`let` positions: A wins 4-2** (A: web, plt, devops, aiml · B: sys, min).

- **A** = in-place explicit type application `Ok[Int, Str](x)` is the normative repair, entailed by
  the existing *Explicit Type Application* decision (a constructor is a callee; `callee[T](args)`
  already exists).
- **B** = lift-to-annotated-`let` is the sole normative repair now; defer the variant-constructor
  type-arg spelling to its own `type:spec` ticket.

  - **PLT (A):** *"A constructor is a callee, and `callee[T](args)` is already Blink's decided
    disambiguator (json.decode[Forecast], alloc_ptr[U8], Pair[Str,Int]{}) — so `Ok[Int, Str](3)` is a
    mechanical extension of a settled rule, not a new concept."* Concern: *"`Ok[Int, Str](3)` has zero
    occurrences today, so if the impl ticket does not actually land parse support for type args on
    variant-constructor callees, A becomes a normative repair the compiler rejects — the spec would
    prescribe a spelling that does not parse."*
  - **AI/ML (A):** *"A is the tightest correction loop — one machine-applicable edit at the caret, no
    program restructuring."* Concern: *"if parse support for the constructor-callee form isn't
    actually landed, a suggested fix that fails to compile is the worst possible outcome for an AI
    author, so that parse support gating the diagnostic is non-negotiable."*
  - **Systems (B):** *"The correctness fix — deleting the fabrication seam — is what stops the
    miscompile, and it must not be gated on a syntax surface (`Ok[Int, Str](3)`) that appears zero
    times in the codebase today; 'entailed by Explicit Type Application' is not 'parses and
    codegens.' Lift-to-`let` works now, is `blink fix`-able."*
  - **Minimalism (B):** *"B is strictly smaller … A mandates `Ok[Int, Str](3)` as normative, a
    spelling with ZERO occurrences … i.e. it is a real surface addition dressed as 'already entailed.'
    YAGNI."* Concern: *"deferring the spelling leaves a brief window where the constructor-local repair
    is unspecified — acceptable, but the follow-up ticket should not be allowed to lapse."*

**Phase D skipped — soft consensus.** A 4-2 split normally triggers Phase D, but the A-majority's
Concern fields explicitly endorse the dissent's substance: PLT — *"if the impl ticket does not …
land parse support … the spec would prescribe a spelling that does not parse"*; AI/ML — *"parse
support gating the diagnostic is non-negotiable"*; DevOps grounded that E0301 emits no fix today, so
parse+fix support must be *added*. Systems/Minimalism (B) ask for exactly that gate. Both sides agree
(i) the correctness fix (delete the seam) ships regardless, and (ii) `Ok[Int, Str](x)` needs real
parse/codegen support. **Resolution: Q3 = A** (bless the constructor type-arg repair as normative),
**with a hard impl gate** — the diagnostic may emit `Ok[Int, Str](x)` as its machine-applicable fix
only once parse+codegen support lands; until then the emitted repair is lift-to-annotated-`let`. This
satisfies the dissent's precondition without re-debating.

### AI-First Review

| Criterion | Score | Notes |
|-----------|-------|-------|
| Learnability | PASS | Derives from 8vcj2c §3.4 (under-determined → E0301) + *Explicit Type Application* (constructor = callee). No new concept. |
| Consistency | PASS | One rule across all six positions; constructor-as-callee reuses settled `callee[T](args)`. No special case. |
| Generability | PASS | One repair spelling; the model emits `Ok[Int, Str](x)` (contingent on parse support — the impl gate). |
| Debuggability | PASS | E0301 dual-span: primary caret on the open constructor + secondary note enumerating the four things that pin the error type (annotation, `?`, error-reading arm, return type). |
| Token Efficiency | PASS | Compact in-place repair; a small annotation cost buys correctness. HM pins the error type from the first real use, so the tax lands only on a genuinely-dead error channel. |

**5/5 PASS.**

### Decision

- **Q1 (6-0):** An unconstrained sum-variant type parameter is **under-determined →
  `error[CannotInferType]` (E0301), uniform across let / tuple element / match scrutinee / field /
  argument / return.** Delete the `codegen_types.bl` fabrication fallthroughs (`Result_int_str`,
  `Option_int`). Reject Never/⊥ defaulting. The I0001 backstop keys on the metavar **kind**, never on
  a concrete tag.
- **Q3 (4-2 → soft consensus):** the normative repair at non-`let` positions is in-place explicit
  type application `Ok[Int, Str](3)`; reported per `8w0yj9` (the binding when one dominates, else the
  constructor's type-argument position). **Impl gate:** emit that spelling as the machine-applicable
  fix only once parse+codegen support for variant-constructor type arguments lands; until then emit
  lift-to-annotated-`let`.

Consequence: unblocks `jctkac` (delete the flat `ScopeVar` type fields).

### Related

- [Under-Determined Types Are a Hard Error](under-determined-types.md) — `8vcj2c`, the governing
  6-0 rule this decision instantiates for sum-variant parameters.
- [Explicit Type Application](explicit-type-application.md) — the `callee[T](args)` decision the Q3
  repair spelling extends to variant constructors.
