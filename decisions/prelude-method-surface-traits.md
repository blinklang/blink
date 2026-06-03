[< All Decisions](../DECISIONS.md)

# Built-in Method-Surface Traits: Prelude Status & Sealing — Design Rationale

Resolves spec gap **nrbq84** ("clarify StrOps/BytesOps/StringBuildOps prelude status; fix §3.2.2 trait summary table"), sub-ticket of **fsmwz2**.

### Background

The §3.2.2 trait summary table was incomplete and partially contradicted the codegen: it omitted `StrOps` and `BytesOps`, said `StringBuildOps` was *not* in the prelude ("No (import `std.str`)"), and listed `Contains` as applying to "List, Map, Set". The codegen pre-registers all these as builtin trait impls (`src/codegen.bl:474-490`).

Three facts were verified against the running compiler during deliberation (framed to the panel as facts, not votes):

- **F1** — `StringBuilder` type, return-type annotation, `StringBuilder.new()`, and all its methods compile with **zero imports** (like `Str`/`List`/`Map`/`Set`). So §3.2.2:249 "requires explicit import" was false.
- **F2** — `Contains` is registered in codegen **only for `Str` and `Set`** (`codegen.bl:480,485`; intrinsics `blink_str_contains`/`blink_set_contains`). `[1,2,3].contains(2)` → `UnresolvedMethod`; `List`/`Map` have no `.contains()`. The table's "List, Map, Set" was wrong on all three.
- **F3** — **No seal existed.** `trait StrOps { fn bogus(self) -> Int }` (user redefinition) compiled cleanly; `impl StrOps for MyType` only failed with `TraitContract` "missing method", not a "reserved trait" error. Sealing is a real behavior change, not a doc fix.

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in independent-proposal → debate → vote rounds.

#### Phase A — Independent proposals

- **Systems:** "These traits ARE compiler-known prelude traits: their NAMES are prelude-visible (usable in generic bounds), AND their method dispatch on built-in receivers is codegen-intrinsic. These are not in tension — they are two facets of the SAME fact ('compiler-known'). … Model (b) ('name never user-visible') is factually FALSE against the running compiler. … Dispatch on a built-in receiver … NEVER touches the trait name at the call site. lookup_builtin_trait_impl … is a static, monomorphic, direct C-call lowering. … making these prelude-nameable costs NOTHING at runtime." Proposed adding a distinct "Built-in method-surface traits" sub-table to §10.6.

- **Web/Scripting:** "what does a JS/Python dev expect when they write `"x".len()` or `sb.write(...)`? They expect *nothing*. … The moment a learner has to type `import std.str` to call `.len()` … we have generated our first 10,000 Stack Overflow questions. … Model (b) … creates a phantom: a trait that's real enough to back `.len()` but invisible enough that you can't name it. That's *more* confusing than (a)." Favored adding rows under the existing rule, all "Yes".

- **PLT:** "The whole confusion is that 'in the prelude' has been used to mean two different things … 1. Name visibility … 2. Method-dispatch knownness." Proposed **P1** (two-category model, both nameable & prelude) and explicitly rejected **P2** (intrinsic-only, non-nameable) as contradicting rows 135/185: "If method dispatch is 'always a trait method call,' then the thing backing `"s".len()` must be a trait, and a trait that exists must be nameable in a bound (or we've invented a second-class trait with no typing rule — that's the unsound option)." Flagged the `Contains` table-vs-codegen contradiction as needing a real ruling; flagged `impl StrOps for Str` re-impl as the dangerous unsealed case.

- **DevOps:** "Model (b) … is a non-starter on diagnostic grounds. The compiler ALREADY needs the type→trait→method table … The LSP must answer 'what completes after `"x".`' … If the trait is 'never named,' you have a method list with no grouping, no doc anchor, no `T: StrOps` bound spellable in generics." Proposed §10.6 as single source of truth, a hard error for re-impl, and flagged that the `UnusedImport` warning on importing a prelude trait "punishes good behavior."

- **AI/ML:** "the single most important AI-first fact: today, zero imports + method syntax = `"x".len()` 'just works.' This is the lowest-decision-point model that exists. … ANY model that requires `import std.str.{StrOps}` before `"x".len()` would be a near-zero-training-data failure mode." Proposed §10.6 as single source of truth and silencing the redundant-import warning to avoid the "defensive-import" LLM trap.

- **Minimalism:** "REJECT all new spec vocabulary. This is a text-correction task, not a taxonomy-design task. The binding rule already decided (row 167) — 'all compiler-known traits are in the prelude' — fully covers [these] with ZERO new concepts. … One rule beats two buckets." Argued the `UnusedImport` warning is technically correct; that `[T: StrOps]` is a degenerate single-impl bound the spec needn't advertise; and that sealing should reuse existing re-seal machinery (commit `7c9cc7d` / row 138), not a new error class.

#### Phase A.5 — Mechanical dedupe

Convergence on the core model (a); all six rejected (b). Distinct open sub-questions surfaced for debate: Q2 (Contains row contents, given F2), Q3 (§10.6 structure: new category vs not), Q4 (redundant-import diagnostic), Q5 (sealing — error vs note vs nothing), Q6 (generic bounds).

#### Phase B — Debate highlights

- **Web** shifted toward Min on structure: "**Q3 … NO new category** … Splitting into 'operator traits' vs 'method-surface traits' sub-buckets invites the exact question 'wait, why are these two different, do they behave differently?' — and the answer is 'they don't,' so the distinction is pure cognitive overhead." Held that the `UnusedImport` warning should stay.

- **PLT** conceded F1 ("my §3.2.2:249 caveat about the type needing import is withdrawn") and offered a Q3 compromise: "ONE prelude rule, but present the traits in TWO labeled sub-tables … If Min reads 'category' as implying a new normative construct, I'll rename to 'groups'." On Q2 argued for ruling on *intent*: "a membership trait that excludes List is incoherent" — but gave fallback to "Str, Set" + bug ticket. On Q5: "**hard ERROR** for both `impl StrOps for MyType` (orphan) and `impl StrOps for Str` (overlapping intrinsic impl)."

- **DevOps** conceded Q2 to reality and softened Q3: "do NOT add a parallel method-surface table to §10.6. Instead … add ONE sentence + a cross-reference … One source of truth per concern, cross-linked — not two tables." Withdrew the `E0740` number from spec scope: "spec tickets shouldn't mint E-codes." Held firm on Q6: "a trait you can name but can't bound is a wart the LSP can't explain."

- **Min** held the Q3 line and offered the synthesis the panel converged on: "CONCESSION I will accept: a single NON-NORMATIVE annotation column … in the ONE existing prelude-trait table — NOT two separate tables, NOT a new defined term. … A column is data about traits; a category is a new noun in the language's vocabulary. I'll take the column; I reject the noun." On Q5: "hard ERROR via the EXISTING re-seal machinery … no new error class."

- **Systems** delivered **F3** (verified): "redefining `trait StrOps {...}` is silently accepted ('ok'); `impl StrOps for MyType` is NOT rejected as reserved … There is NO seal today." Accepted Min's column compromise on Q3: "That was my actual requirement — the split, not the table count. Min's column satisfies it. Converged." On Q5: "'via existing seal machinery' means we must actually wire these traits into that machinery — file the bug. Don't spec a seal the compiler doesn't enforce."

- **AI/ML** conceded Q3 to Min ("one flat COMPLETE table, no sub-categories") and reconciled its Proposal 3 against F1 ("StringBuilder is fully zero-import; §3.2.2:249 becomes 'in prelude, no import.' … the zero-decision-point model now has zero exceptions"). Held silent-no-op on Q4 and bless on Q6.

#### Phase C — Final vote

Each panelist voted independently in isolation. Format: vote — reasoning — concern.

- **Q1: Core model — (a) compiler-known ⇒ prelude (names visible + intrinsic dispatch). 6-0.**
  - **Systems:** (a) — "These traits are not library abstractions — they are names attached to codegen-intrinsic dispatch … so the call sites lower to direct C runtime calls with zero indirection." Concern: "Prelude-visible names that are intrinsic-only risk users assuming full trait machinery … exists when codegen only supports the builtin path."
  - **Web:** (a) — "A JS/Python dev's entire mental model is 'I made a string, I call `.contains()`, it works — no ceremony.' That already works (F1), so the spec must *say so*."
  - **PLT:** (a) — "A method that participates in normal dispatch must have a name in scope; 'intrinsic-only never-named' creates a dispatch path with no denotational referent, which is incoherent."
  - **DevOps:** (a) — "The LSP and error messages need a name to point at. If [these are] 'intrinsic-only never-named' (b), then 'UnresolvedMethod' can't suggest them, hover has nothing to render."
  - **AI/ML:** (a) — "the single most valuable property is that 'if it compiles, the name is in the spec.' An intrinsic-only/never-named model creates a class of constructs that work but cannot be discovered from the spec text."
  - **Minimalism:** (a) — "The prelude already IS the noun for 'compiler-known items in scope.' Option (b) invents a second concept … to describe the same machinery. One model, no new surface."

- **Q2: §3.2.2 `Contains` row — (i) match codegen ("Set"/element-membership) now + file List/Map bug. 6-0.**
  - **Systems:** (i) — "The spec table must describe what the hardware actually does today; writing 'List' when [1,2,3].contains(2) lowers to UnresolvedMethod is a lie in the normative text."
  - **Web:** (i) — "if I … get UnresolvedMethod, that's the single worst DX outcome — the docs lied." Concern: "§3_types.md … already promises List/Map membership … the bug ticket must cover reconciling both."
  - **PLT:** (i) — "claiming 'Str, List, Set' describes a compiler that rejects `[1,2,3].contains(2)` is publishing a false typing rule. My … point stands that a membership protocol excluding List is incoherent as a *design*, but coherence-of-intent is repaired by the List bug ticket, not by writing fiction into the normative table."
  - **DevOps:** (i) — "the diagnostics surface must not promise a method the compiler answers with UnresolvedMethod."
  - **AI/ML:** (i) — "documenting 'List' as supported would teach the model to emit code that fails to compile, the worst outcome for generability."
  - **Minimalism:** (i) — "The spec must describe what IS, not aspiration."

- **Q3: §10.6 structure — (A) no new category; flat presentation + cross-ref (optional non-normative column). 6-0.**
  - **Systems:** (A) — "all these traits collapse to the same mechanism: a known name → a fixed intrinsic. Inventing two normative sub-categories implies a machine-level distinction that does not exist in lowering." (Accepted Min's single-column compromise in debate.)
  - **Web:** (A) — "Two labeled sub-categories … is an internal compiler taxonomy that means nothing to a scripting user."
  - **PLT:** (A) — "Withdrawing my P1 — two labeled sub-categories implies a normative distinction (intrinsic vs trait) that Q1(a) just dissolved by making them all prelude traits." Concern: "Keep the cross-ref column explicitly non-normative."
  - **DevOps:** (A) — "Two labeled sub-categories double the surface the formatter/doc-gen and LSP completion must keep in sync for zero reader benefit."
  - **AI/ML:** (A) — "Fewer decision points and a single flat lookup minimizes token cost and ambiguity." Concern: "Flat table only wins if it is genuinely exhaustive."
  - **Minimalism:** (A) — "§10.6 already presents prelude items flat … That column is sufficient and non-normative. … Subtract, don't partition."

- **Q4: Redundant prelude-trait import — spec rule: importing a prelude name is permitted, no effect/no warning. 6-0** (the *implementation* of suppressing the current `UnusedImport` warning is a separate diagnostics ticket; this vote is on the spec rule only).
  - **Systems:** (silent rule) — "Redundant import of an already-visible name has zero codegen impact … so the spec rule should match the no-op reality." Concern: "the impl ticket must scope it tightly to prelude names."
  - **Web:** (silent rule) — "punishing that with a warning teaches 'imports are scary' exactly when we want imports to feel safe." Concern: "A genuinely unused import … should still warn — the rule must scope narrowly."
  - **PLT:** (silent rule) — "importing a name that's already bound to the same entity is idempotent; warning on it conflates 'unused' with 'already-available.'"
  - **DevOps:** (silent rule) — "the spec states only the rule 'legal, not an error'; whether to emit UnusedImport is a diagnostics-severity decision that belongs in a separate ticket."
  - **AI/ML:** (silent rule) — "a prelude name is provably never a dead dep. … Penalizing redundant-but-correct imports teaches the model to omit imports to avoid warnings, eroding robustness across files where the name is NOT prelude."
  - **Minimalism:** (silent rule) — "stating 'permitted, no warning' is the minimal rule with zero new machinery. … the suppression carve-out belongs in a SEPARATE tooling ticket."

- **Q5: User impl/redefine — hard error; these traits are sealed; spec states the seal + a latent-bug ticket is filed (unenforced today per F3). 6-0.**
  - **Systems:** (error) — "allowing a user impl would create two competing lowerings for one method name with no runtime dispatch to choose between them — an unsound, non-zero-cost situation." Concern: "the compiler does not enforce the seal today (F3)."
  - **Web:** (error) — "If a user can `impl StrOps for MyType` or redefine `trait StrOps`, then `.contains()` no longer has stable meaning and every 'it just works' guarantee evaporates." Concern: "The error message must name the alternative (define your own trait)."
  - **PLT:** (error) — "Coherence demands a single canonical impl for the intrinsic dispatch surface; allowing user re-impl/redefinition introduces overlapping instances. … This matches the precedent set by 7c9cc7d."
  - **DevOps:** (error) — "a clear 'this name is reserved by the prelude' error is far more actionable than silent acceptance that later collides with intrinsic dispatch." (E-code assigned by the impl PR, not the spec.)
  - **AI/ML:** (error) — "One name → one meaning is the highest-leverage rule for learnability; allowing users to redefine prelude trait names silently (F3) means the same token can dispatch differently per file, which is unlearnable from spec alone."
  - **Minimalism:** (error) — "reuse [the 7c9cc7d / row 138 machinery] — one sentence, NO new error class. This is subtraction-by-reuse, not invention. But because it's unenforced today, it needs a bug ticket."

- **Q6: Generic bounds `[T: StrOps]` — bless as legal, with a single-impl note. 4-2** (web, min dissent → "stay silent"). Soft consensus: treated as "legal + single-impl note."
  - **Systems:** bless — "a bound resolving to a single builtin impl monomorphizes to a direct intrinsic call — genuinely zero-cost, no vtable." Concern: "such bounds are effectively decorative until/unless more impls are ever allowed."
  - **PLT:** bless — "Once StrOps is a real prelude trait (Q1a), bounding a type parameter by it is the natural, compositional consequence — banning it would special-case prelude traits out of the bounds system for no soundness reason."
  - **DevOps:** bless — "banning them contradicts the trait's stated purpose, and silence leaves LSP completion/hover unsure whether to surface the bound."
  - **AI/ML:** bless — "a name usable in a bound but 'not really a bound' is incoherent for an AI; single-impl just makes the bound mean 'T is Str.' Zero cost, removes a special case."
  - **Web:** *(dissent → silent)* — "this is a power-user corner — 0% of the 5-minute-onboarding crowd writes `[T: StrOps]`. … a one-line non-normative 'single-impl, rarely useful' note would be acceptable as a fallback if the panel leans bless."
  - **Minimalism:** *(dissent → silent)* — "The existing generic trait-bound rule covers the degenerate case completely; adding a 'this is legal' blessing implies the general rule has a hole it doesn't have. … Max concession: one descriptive line 'legal but degenerate'."

  **Soft-consensus resolution:** No Phase D. The majority's Concern fields all insisted on the single-impl caveat, and web explicitly accepted "bless + single-impl note" as a fallback; min accepts a descriptive "legal but degenerate" line. The spec records the bound as legal, framed as the general bound rule applied to a degenerate case — not a new capability.

### Final Spec

Locked design points (see §3.2.2 *Trait Summary* and §10.6 *Module Prelude → Prelude Traits*):

- The built-in **method-surface traits** — `Sized`, `Contains`, `StrOps`, `BytesOps`, `ListOps`, `MapOps`, `SetOps`, `Joinable`, `StringBuildOps` — are compiler-known and therefore **in the prelude**. Trait names are in scope without import; method dispatch on a built-in receiver is resolved intrinsically by the compiler and never consults whether the trait name is imported.

```blink
fn shout(s: Str) -> Str {
    s.to_upper()                  // StrOps — no import, ever
}

fn build() -> Str {
    let mut sb = StringBuilder.new()   // StringBuildOps + the StringBuilder type: no import
    sb.write("hello ")
    sb.write("world")
    sb.to_str()
}

fn describe[T: Sized](x: T) -> Int {
    x.len()                       // sealed prelude trait, named in a bound: legal
}
```

- §3.2.2 trait summary table: added `StrOps`, `BytesOps`; all "In prelude" = `Yes`; `StringBuildOps` flipped to `Yes` (import parenthetical deleted); `Sized` "Applies to" gains `Bytes`. `Contains` element membership is implemented for `Set` only today (`List`/`Map` planned; `Str.contains` is substring search hosted by `StrOps`, not element membership).
- §3.2.2:249: "lives in `std.str` (Tier 1) and requires explicit import" struck — `StringBuilder` (type, constructors, methods) is a zero-import compiler-known built-in.
- §10.6: prose broadened so "compiler-known traits" covers *both* operator/protocol traits *and* built-in method-surface traits; the prelude-trait table lists the method-surface traits alongside the operator traits (single source of truth, cross-referenced to §3.2.2). Importing a prelude name is permitted and has no effect.
- These method-surface traits are **sealed**: user `impl` and user redefinition are compile errors. (The compiler does not yet enforce this — F3 — so a latent-bug ticket tracks enforcement.)
- A sealed trait may be named in a generic bound. `Sized` spans several built-in types so its bounds are polymorphic; a bound on a single-implementor trait (`StrOps`/`BytesOps`/`StringBuildOps`) is legal but degenerate.
