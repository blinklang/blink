[< All Decisions](../DECISIONS.md)

# Under-Determined Types Are a Hard Error — Design Rationale

**Spec gap:** br `8vcj2c` — *First-class "unknown" type: uniform treatment of under-determined types across all inference sites.*

**Status: implemented.** The 6-0 vote below stands and the normative spec (`sections/03_types.md`
§3.3) is unchanged. One detail of the *rationale* is now historical: the `blink_map_ensure_kops` /
`blink_set_ensure_kops` runtime patch described throughout as the "current accident" was retired
(br `59bnez`) once E0301 + the I0001 ICE backstop moved the vtable decision to construction time.
Every reference to it below describes the pre-metavar state of the compiler, not current behaviour.

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated
in independent-proposal → dedupe → focused-debate → vote rounds. The core question: does Blink
have a first-class notion of an under-determined / "unknown" type, and how is it treated uniformly
across all inference sites (empty `[]`, bare `None`, empty `Map()`/`Set()`, under-constrained
generic construction like `let b = GKV { m: Map() }`)?

The motivating exhibit: `type GKV[K,V] { m: Map[K,V] }` built as `let b = GKV { m: Map() }`
currently mints `blink_GKV_Void_Void`, defaults to the wrong `kops_str` vtable, and relies on a
runtime `blink_map_ensure_kops` patch at first insert. Latent, not a live miscompile — but
"unknown" and concrete `Void` collapse to the same mono symbol.

#### Phase A — Independent proposals

All six panelists independently converged on the same core answer: **ERROR, never default; no
surface `unknown` type.** No panelist proposed keeping silent Void-erasure, and no panelist
proposed a stated defaulting rule.

- **Systems:** *"Refuse to monomorphize an under-determined type parameter — emit
  `error[CannotInferType]` at the point the value's type must be pinned. NO silent `Void`, NO
  surface `unknown`/`?` type."* Traced the mechanism: *"`resolve_tparam` falls through with
  nothing to bind, `tc_tid_to_c_tag` (`typecheck.bl:9447`) has a literal `"Void"` fallthrough →
  mints `blink_GKV_Void_Void`. The `Map()` ctor with no key type defaults to `blink_kops_str` …
  then `b.m.insert(256, "x")` emits a runtime patch `blink_map_ensure_kops`."* Hard veto on symbol
  collision: *"`Void` is an ordinary INHABITED, encodable type … A genuine `GKV[Void, Void]` and an
  under-inferred `GKV { m: Map() }` mint the same symbol … Under `--link-archive` separate
  compilation this is a One-Definition-Rule violation and a real silent miscompile."*

- **Web/Scripting:** *"ERROR at the inference-region boundary, never eagerly at the `let`."*
  Probed the compiler first: *"Unconstrained `let x = []`, `let m = Map()`, `let n = None`, AND the
  full motivating exhibit … all pass inference today with ZERO 'cannot infer' diagnostics."*
  Reframed as two situations: *"'I'll fill it in a second' (`let x = []; x.push(42)`) … vs 'I
  genuinely never said what's in it' … A dev is annoyed by an error on #1 and grateful for an error
  on #2."* Rejected surface `unknown`: *"a solution to a problem Blink doesn't have … every case
  here has a type that IS knowable from context; it's just not yet stated."*

- **PLT:** Diagnosed the category error precisely: *"`TK_UNKNOWN` … is an unsolved unification
  metavariable (α). NOT resolved … `α` (metavariable) and `Void` (unit) — genuinely distinct in
  `ty_pool` — alias to the same mono symbol."* *"the codegen layer performs `[Void/α]` —
  substituting an inhabited unit type for a free variable the program never constrained. No typing
  rule licenses that substitution."* On the invariant: *"an unbound α is not a fully-resolved type,
  therefore it must never reach a mono symbol. Any α that reaches codegen is, by that constraint,
  already a bug."* Rejected a surface top type: *"a subtyping ⊤ in the same variable slot … is no
  longer the HM Blink declared."*

- **DevOps:** *"Camp A (ERROR / 'annotate it'), scoped by the diagnostic surface. No surface
  `unknown`/`?` type."* Rejected OCaml weak-var deferral on diagnostic grounds: *"The error fires
  far from the `let` … There is no single machine-applicable fix … LSP hover would show `'_weak1`
  … A scheme whose best possible error is 'somewhere downstream, a type you can't name failed to
  resolve, and I can't tell you what to type' is disqualified before we discuss its theory."*
  Proposed dual-span: *"Primary caret on the binding because that's where the fix applies;
  secondary underline explains the cause."*

- **AI/ML:** *"ERROR, uniformly. `error[CannotInferType]`. No surface `unknown` type."* The
  correction-loop argument: *"the AI emits `let b = GKV { m: Map() }`, later does
  `b.m.insert(256, "x")`, gets green compile, wrong vtable, latent runtime divergence. There is no
  diagnostic to feed back into the loop … This is strictly worse than a crash — a crash at least
  produces text. Silent-wrong is the one failure mode an LLM author has zero recourse against."*
  On learnability: *"A is literally the same principle as `AmbiguousConstruction`, generalized from
  variant-name ambiguity to type-parameter ambiguity. Zero new concepts."*

- **Minimalism:** *"REJECT a surface `unknown`/`any`/`?` type. ADOPT a single new error,
  `error[CannotInferType]`, and otherwise SUBTRACT — delete the silent Void-erasure defaulting
  path."* Surface-area accounting: *"Option C is unambiguously the smallest language. It adds one
  error — and an error is not a new concept a user must hold in their head the way a new type or a
  defaulting rule is."* On the top type: *"You'd be institutionalizing the accident."*

#### Phase A.5 — Mechanical dedupe

- **Q1 (general rule):** unanimous — `error[CannotInferType]`, never default. No competing option.
- **Q2 (surface `unknown`):** unanimous — reject, keep `TK_UNKNOWN` internal-only.
- **Q3 (the only live split):** the genuinely-unobservable local — does `let x = []; x.len()`
  (element-agnostic use, element type never observed) error, or is it accepted? Systems (Proposal 3)
  and PLT (Phase A) leaned toward a carve-out; DevOps argued strict-error. → Phase B, scoped to Q3.

#### Phase B — Debate highlights (Q3 only)

Both carve-out proponents withdrew during debate.

- **Systems (position change):** *"Q3b — I CONCEDE to strict-error. devops is right and it's a
  systems argument, not just a purity one … My carve-out's soundness rests on the compiler proving
  the element type is never observable — that's a whole-function escape analysis whose bugs produce
  silent miscompiles … a special silent-success path for unobservable unbound locals is a second
  rule. Strict-error is the single rule … So: error even on `let x = []; x.len()`. No carve-out.
  My Proposal 3 is withdrawn."*

- **PLT (position change):** *"STRICT-ERROR. I concur. No carve-out … HM/value-restriction PERMITS
  accepting the never-observed local — it does not MANDATE it … erroring at the earlier (introduction)
  boundary is strictly more conservative and therefore still sound … the carve-out's acceptance
  depends on a whole-function escape analysis, which breaks locality of reasoning and is
  refactor-fragile (adding `return x` later flips a legal program to erroring/miscompiled)."*

- **DevOps (empirical correction):** checked the emitted C and refined the argument. *"`List` and
  `Map` are type-erased runtime handles … `let x = []` → `blink_list* x = blink_list_new();` — no
  `_Void`, no mono symbol. My Phase A line — 'x would ship as `List[?]` collapsing to `List[Void]`'
  — is factually wrong for the bare-collection case."* But: *"`None` does NOT erase — it silently
  defaults to `Int` … `const blink_Option_int n = (blink_Option_int){.tag = 0};` … the carve-out
  isn't uniform, and Q1 was locked as the uniform rule."*

*(Moderator note: the `None → blink_Option_int` and `Map() → blink_map_new(&blink_kops_str)`
findings were independently verified at HEAD before being recorded as normative — the accident is
non-uniform, which strengthens the case for one uniform rule.)*

#### Phase C — Final vote

All five questions **6-0 unanimous**. No Phase D (nothing closer than 5-1). No ties.

- **Q1: General rule — `error[CannotInferType]`, never default** (6-0)
  - **Systems:** A — *"Only option where every mono symbol provably corresponds to a fully-resolved
    type; the incorrect program never becomes a binary. Kills the `blink_GKV_Void_Void` wrong-vtable
    accident and the ODR collision at the root."*
  - **Web:** A — *"Silent Void-erasure is the worst DX outcome — no error, wrong runtime behavior,
    bug invisible until it bites … Matches my reference cohort's expectation (TS `noImplicitAny`,
    OCaml value restriction)."*
  - **PLT:** A — *"A free metavariable at a generalization boundary is the HM-family's universal
    hard-error case … defaulting to Void is an unlicensed `[Void/α]` substitution that the 'don't
    intern inference variables' invariant already forbids."*
  - **DevOps:** A — *"An under-determined binding is an unfinished program, not a value to ship …
    Blink diagnostics carry machine-applicable fixes … so the 'error' is a one-click quick-fix, not
    a dead end."*
  - **AI/ML:** A — *"A silent default produces wrong behavior with no diagnostic — the one failure
    mode an AI author cannot self-correct … A hard error at the site is one deterministic rule …
    closes the fix loop in a single round-trip."*
  - **Minimalism:** A — *"Two-state inference (solved / reported) is the smallest possible model …
    the error reuses the existing `AmbiguousConstruction` machinery and adds no new concept a user
    must hold in their head."*

- **Q2: Surface `unknown` type — REJECT, keep `TK_UNKNOWN` internal-only** (6-0)
  - **Systems:** REJECT — *"A surface top type in a monomorphizing backend forces
    boxing/RTTI/vtable dispatch — the exact runtime cost Blink's whole model rejects."*
  - **Web:** REJECT — *"it earns its keep only at untyped boundaries (`JSON.parse`, `catch`) —
    Blink's gap has none of those … Adding surface `unknown` manufactures the exact
    annotate-`Map[Str,Int]`-vs-`Map[unknown,unknown]` decision point §1.2 forbids."*
  - **PLT:** REJECT — *"A top type doesn't solve the gap (TS `unknown` is never produced by
    inference, only opted into) … a subtyping ⊤ in the same slot as a Damas-Milner α is no longer HM."*
  - **DevOps:** REJECT — *"the TypeScript `any` footgun, not the `unknown` discipline … hover shows
    `unknown`, autocomplete offers nothing useful, and `fmt` gains a type to canonicalize — all to
    avoid emitting a fix."*
  - **AI/ML:** REJECT — *"adds a decision point … plus a whole narrowing sub-spec the AI must learn
    cold. Its own exemplar (TypeScript) insists `unknown` is opted-into and never inferred, so it
    wouldn't even fill this gap."*
  - **Minimalism:** REJECT — *"the single largest addition on the table … the C++-committee failure
    mode … It also solves the wrong problem … it would institutionalize the accident rather than fix
    it."*

- **Q3: Unobserved-local — STRICT, no carve-out** (6-0)
  - **Systems:** STRICT — *"The carve-out's soundness rests on a whole-function escape analysis
    whose bugs produce silent miscompiles; a guaranteed error beats a proof-obligation I must get
    right every time … no symbol is cleaner than a provably-harmless one a later `return x` silently
    turns harmful."*
  - **Web:** STRICT — *"The carve-out is a second rule … 'why does `.len()` compile but `.first()`
    doesn't?' is not [teachable]. The dead stub isn't a shipped pattern worth protecting."*
  - **PLT:** STRICT — *"I argued CARVE-OUT in Phase A … and I honestly changed position: HM permits
    accepting the never-observed local but does not mandate it … I do NOT consider STRICT a
    soundness error. It is fully sound (over-conservative, not unsound)."*
  - **DevOps:** STRICT — *"`None` defaults to a concrete `blink_Option_int` … so the carve-out is
    non-uniform and breaks the Q1 rule we just locked … 'provably never observed' is a non-local
    escape analysis … action-at-a-distance acceptance."*
  - **AI/ML:** STRICT — *"STRICT is one condition-free rule; the carve-out is a rule plus an 'is
    this use element-observing?' predicate that isn't spec-derivable, is learned only by training
    osmosis, and grows unstably as collection methods are added."*
  - **Minimalism:** STRICT — *"The carve-out is not one condition but a permanent per-method
    observability classification … exactly the combinatorial surface I rejected in Q2. The only
    thing the carve-out buys is letting dead locals slide, and those already trip `UnusedVariable`."*

- **Q4: Span/reporting — REPORT-AT-BINDING, dual-span** (6-0)
  - **Systems:** *"the machine-applicable fix attaches to the `let` target, so the primary span
    belongs there with a secondary blame note at the empty ctor."*
  - **Web:** *"Dual-span is precisely what makes Q1 non-confusing — the fix … belongs at the `let`
    … and the secondary blame at the empty ctor answers 'why?'"*
  - **PLT:** *"The `let` is the generalization boundary where the witness obligation fires and where
    the machine-applicable annotation fix attaches."*
  - **DevOps:** *"Fix location and blame location are different spans and good tooling shows both …
    The `notes` field in the diag struct (`src/diagnostics.bl:459`) already supports the secondary
    span; this beats Rust's single-span E0282."*
  - **AI/ML:** *"the fix is always 'annotate the binding,' so the primary span and the
    machine-applicable insertion must sit at the `let'."*
  - **Minimalism:** *"This is the same dual-span shape E0519 already uses, so it adds no new
    reporting concept."*

- **Q5: ICE tripwire — ADOPT** (6-0)
  - **Systems:** ADOPT — *"an unsolved typevar reaching the mangler is by construction a compiler
    bug … An ICE converts a future silent miscompile into a loud, located compiler failure."* Concern:
    *"it must fire ONLY for typevar/unknown, never for a legitimate `Void` type argument … the
    tripwire keys on TK_TYPEVAR/TK_UNKNOWN, not on the resulting 'Void' tag."*
  - **Web:** ADOPT — *"the belt-and-suspenders that makes Q1 enforceable."*
  - **PLT:** ADOPT — *"failing closed (ICE) turns the entire silent-`Void_Void` miscompile class
    into a loud compiler assertion and makes the 'don't intern inference variables' invariant
    enforced rather than hoped-for. It also retires the `blink_map_ensure_kops` runtime patch honestly."*
  - **DevOps:** ADOPT — *"`type_name_from_ct` (`src/codegen_types.bl:4337`) has `else { "Void" }`,
    and `ct_from_c_type` (`:4310`) funnels every unmapped ct to `CT_VOID`. So an unsolved typevar
    and a genuine `Void` are indistinguishable at this seam — that identity collapse is exactly how
    `blink_GKV_Void_Void` is minted."* Concern: *"it needs a distinct 'unsolved' sentinel upstream
    of this `else`, because today the two share the `CT_VOID`/`"Void"` path."*
  - **AI/ML:** ADOPT — *"this is the enforcement that makes Q1/Q3 real … it must be a true ICE
    (I-prefix, unsuppressable) with a stable code."*
  - **Minimalism:** ADOPT — *"It adds no user surface (users can never legitimately hit it) …
    it must be genuinely unreachable from user input before we ship."*

### AI-First Review

| Criterion | Score | Notes |
|-----------|-------|-------|
| Learnability | PASS | One sentence — "inference can't determine a type → `CannotInferType`; annotate" — generalizing the already-spec'd `AmbiguousConstruction`. No new type concept. |
| Consistency | PASS | Reuses existing diagnostic machinery (E0519 dual-span shape); annotation is Blink's canonical disambiguator (sized-int precedent). No observability sub-clause. |
| Generability | PASS | Correct program is deterministic: annotate every unconstrained empty. One shape, no stylistic fork. |
| Debuggability | PASS | Error fires at the binding (local), carries a machine-applicable fix, self-corrects in one round-trip. ICE backstop turns any bypass into loud text. |
| Token Efficiency | PASS | Cost is ~4–8 tokens on genuinely-unconstrained bindings only (HM pins most from use). Those tokens are enforced documentation and improve the training corpus. |

**5/5 PASS.**

### Final Spec

```blink
// Under-determined → hard error, uniformly:
let x = []          // error[CannotInferType] (E0301): element type undetermined
let n = None        // error[CannotInferType]: inner type undetermined
let m = Map()       // error[CannotInferType]: key/value types undetermined
let b = GKV { m: Map() }   // error[CannotInferType]: type params K, V of GKV undetermined

// Fix in every case is an annotation:
let x: List[Int] = []
let n: Int? = None
let m: Map[Str, Int] = Map()
let b: GKV[Int, Str] = GKV { m: Map() }

// Later use still determines the type — no error, no annotation:
let mut xs = List.new()
xs.push(1)          // xs : List[Int]

// Strict — an element-agnostic use does NOT rescue the binding:
let x = []
x.len()             // still error[CannotInferType]: len() observes the list, not the element
```

Locked design points:
- **Two-state inference:** every type variable is resolved to a concrete type, or the unresolved
  ones are **reported**. No third "default" state.
- **`error[CannotInferType]` (E0301)** for an unbound type variable at its binding — uniform across
  empty `[]`, bare `None`, empty `Map()`/`Set()`, under-constrained generic construction. Sole
  repair: a type annotation. Non-suppressible (no `@allow`).
- **No surface `unknown`/`any`/`?` type.** `TK_UNKNOWN` stays a transient internal inference state,
  never nameable, holdable, or produced-by-inference. Must never leak into user-facing diagnostic
  or hover text.
- **Strict:** no unobserved-local carve-out. Legality is judged at the binding, once — never
  contingent on a whole-function observability analysis.
- **Report-at-binding, dual-span:** primary caret + machine-applicable annotation fix at the `let`
  (ctor shape known → `: List[T]` / `: Map[K, V]` / `: T?`); secondary "blame" span at the empty
  constructor. Rejects OCaml weak-var deferred-to-boundary reporting.
- **ICE backstop `UnsolvedTypeVarAtCodegen` (I0001):** an unsolved `TK_TYPEVAR`/`TK_UNKNOWN`
  reaching `tc_tid_to_c_tag`/`type_name_from_ct` fails closed, never falls through to `"Void"`. Keys
  on the *kind*, not the resulting `"Void"` tag, so a genuine `GKV[Void, Void]` is unaffected.
- **Migration** (consequence, not an input to the vote): breaks today's permissive `let x = []` /
  `Map()` / `None` on genuinely-unconstrained bindings. Mechanical (`blink fix`-able); the
  compiler's own sources must be swept before the rule flips (self-host).
