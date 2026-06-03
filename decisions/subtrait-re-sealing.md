[< All Decisions](../DECISIONS.md)

# Sub-trait Re-sealing (Strengthening) — Design Rationale

### Problem Statement

Decision [trait-sealed-default-methods](trait-sealed-default-methods.md) (344dnd) locked
sealing as **monotonic down the supertrait chain**: a supertrait's `final` default cannot be
un-sealed by a subtrait or its impls. The mirror direction — a subtrait *strengthening* an
**open** supertrait default to `final` — was explicitly deferred. PLT's deferral note:
"it requires re-stating the body and creates two methods with the same name visible to
impls; revisit when there's a concrete need."

The question (br 7my8aw), given:

```blink
trait Super { fn m(self) -> Int { default_body() } }   // open default
trait Sub : Super { final fn m(self) -> Int { ... } }   // can the subtrait seal it?
```

1. Is strengthening allowed at all?
2. If yes, does an impl of `Sub` see one method or two? Which dispatches for `x.m()`?
3. If yes, is the subtrait's restated body authoritative, or must the impl supply the
   supertrait's open default body somewhere?
4. If no, what diagnostic fires?

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated
in Phase A independent proposal → Phase A.5 mechanical dedupe → Phase C silent ballot.
Phase B was skipped: all six independently produced the same primary (reject + a new
`E0733`), with the "allow" shapes held only as conditional fallbacks — no live disagreement
on the primary to debate.

#### Phase A — Independent proposals

- **Systems:** drafted both an "allow" proposal (S1) and a "reject" proposal (S2), and
  recommended **reject (S2, E0733)**: "S1 is *cheap in codegen* — that's why I drafted it
  honestly — but the value it buys (let a subtrait seal a method the supertrait left open) is
  fully recoverable by sealing at the supertrait or renaming, while the cost it imposes (a
  type with two context-selected `hash()` bodies) is the exact failure mode `final` was
  invented to kill. For a feature whose entire purpose is 'make observable-property drift
  structurally impossible,' shipping a variant that re-admits drift fails its own charter.
  Reject, and point authors at the monotonic-down primitive they already have." On the codegen
  fact: "Q2 ('does an impl see one method or two?') is not a policy choice we get to make
  freely — *two* is unrepresentable in the codegen without inventing dispatch primitives that
  344dnd already rejected."

- **Web/Scripting:** primary **W1 (reject, E0733)**: "This is the answer that produces the
  fewest SO questions, because it's the *symmetric completion* of the rule devs just learned in
  Q4. The mental model becomes one sentence: **'`final` only lives where the method is first
  declared; subtraits inherit sealing, they never change it.'** Monotonic in BOTH directions —
  can't un-seal going down (Q4), can't seal going up (W1)." Cross-language: "in every reference
  language a dev knows, 'tighten an inherited interface default to final from a sub-interface'
  is simply **not a thing they've ever typed.** Rejecting it surprises nobody." On the allow
  fallback (W2) he flagged the hazard against his own proposal: "Same object, two answers,
  depending on the static bound at the call site. That is the #1 SO-question generator in this
  whole feature and it's intrinsic to allowing strengthening at all."

- **PLT:** primary **P1 (reject, E0733)**, framing the hazard as a coherence problem, not an
  ergonomics wart: "Now `m` is a name reachable through **two distinct (Trait, Type) facts**:
  `(Super, Widget)` yields `1`, `(Sub, Widget)` yields `2`. ... `via_super(w)` // 1 ;
  `via_sub(w)` // 2 — SAME value, SAME method name, two answers. This is **incoherent in the
  precise sense**: the meaning of `w.m()` depends on the static lens, and `Sub : Super` is
  supposed to mean every `Sub` *is a* `Super`. Liskov is broken silently." On the only sound
  allow-variant (P2, force the Super-view to agree): "It is *sound* (no two answers) but it is
  **not compositional** — adding `impl Sub for T` retroactively changes what `via_super(t)`
  returns, even in code that never mentions `Sub`. That violates the 'each impl block is
  self-contained' reading of coherence." Verified no stdlib need: "No stdlib trait
  (Eq/Ord/Hash/Sized/Display) needs strengthening — they all seal at source."

- **DevOps/tooling:** primary **reject, E0733 (RedeclaresSupertraitDefault)**: "Allowing it
  forces two same-named methods to coexist in one hierarchy, which is exactly the case my
  entire surface degrades on — hover shows '2 candidates,' autocomplete double-lists `m`, and
  go-to-definition has to pick a winner the user can't see. Reject collapses each method name
  to one resolvable target per hierarchy, so every tooling affordance stays deterministic and
  explainable." Authored the full `blink explain` long-form. On the allow fallback: "The
  killer: `x.m()` selecting different bodies based on the *static* type of `x` is a 'spooky
  action at a distance' ... which produces the exact bug reports ('I called m() and got the
  wrong one') that the rejection avoids."

- **AI/ML:** primary **A1 (reject, E0733)**: "If two `m` are visible to an `impl Sub`, an AI
  must answer at generation time: *which body is authoritative? do I implement Super.m, Sub.m,
  both, neither? which one does `x.m()` dispatch when `x: Sub`?* Every one of those is a
  decision point with a wrong answer, and none of it is forced by a real user need — it is
  induced entirely by allowing the construct. This is the same class of bug AIs make with C++
  virtual-vs-non-virtual shadowing and Python diamond MRO." Held a conditional fallback (A2,
  a bare `seal m` directive with no restated body) "only if the panel insists strengthening
  must be expressible," rating it strictly below A1: "It spends a keyword and a decision point
  to enable a pattern with no demonstrated demand. YAGNI applies."

- **Minimalism:** primary **P1 (reject + E0733, no third sealing rule)**: "I checked the
  codebase before drafting. `rg 'trait \w+ : \w+' lib/ src/` → **zero subtraits exist**.
  `rg 'final fn' lib/ src/` → **zero `final` default methods exist in actual code** (only in
  spec prose). ... **The condition that was supposed to reopen this has not fired.**" On the
  workaround: "A subtrait author who wants `m` sealed for everyone has a strictly simpler option
  that exists right now: **seal it at the supertrait.** ... Monotonic-down (Q4, 6-0) then
  propagates the seal to `TotalOrdered` and every impl for free — no restated body, no
  two-methods-one-name problem, no new rule." On the interaction cost: allowing it "is a *third*
  rule that interacts with: monomorphization ... effect rows ... and impl resolution. That's
  three settled decisions reopened to support zero use sites."

#### Phase A.5 — Mechanical dedupe

All six primaries collapsed to one option: **reject strengthening, with a new `E0733`
fired at the subtrait declaration site.** The "allow" shapes were distinct but each held only
as a conditional fallback ("only if the panel insists"): a body-restating form (sys S1, web W2,
devops fallback, min P2) that PLT and sys both showed re-admits Super-view/Sub-view drift; a
forced-agreement form (plt P2) that is sound but non-compositional; and a bare `seal` directive
(aiml A2) that preserves the single-method invariant at the cost of a new keyword. No panelist
held any "allow" form as primary. Phase A.5 produced one option with 6-way primary agreement
and no flagged variation creating live disagreement → Phase B skipped.

Two sub-questions went to the ballot: **Q1** the resolution direction, and **Q2** whether the
diagnostic is framed as a permanent rule or as "not yet supported / deferred" (web had raised
the deferral framing as W3 but did not recommend it).

#### Phase C — Final vote

- **Q1 — Resolution direction (6-0 for REJECT + E0733):**
  - **Systems:** A — "Sealing must stay monotonic down the chain because that's what makes it a
    *static* guarantee ... Allowing a subtrait to re-seal an open supertrait default reintroduces
    exactly the cost-hiding I objected to in Phase A ... and it defeats devirtualization since the
    compiler can no longer treat a sealed default as a single known target."
  - **Web/Scripting:** A — "Sealing that can flip per-subtrait means a reader staring at
    `final foo()` can no longer trust it — they'd have to walk the entire trait hierarchy to know
    whether some descendant re-sealed or unsealed it. ... Monotonic-down-only keeps `final` a
    local, readable promise: born at the method, never edited downstream. Reject, with conviction."
  - **PLT:** A — "Allowing strengthening is a real coherence break, not a missing convenience.
    Blink dispatches statically against the trait the bound names and has no MRO, so
    `via_super[T: Super](x)` and `via_sub[T: Sub](x)` would yield different results for the same
    object. ... this is the symmetric closure of 344dnd Q4 and keeps Sub<:Super subtyping honest
    with zero new dispatch machinery."
  - **DevOps:** A — "Allowing it forces two same-named methods to coexist in one hierarchy, which
    is exactly the case my entire surface degrades on ... Reject collapses each method name to one
    resolvable target per hierarchy, so every tooling affordance stays deterministic and
    explainable. There is no diagnostic story for (B) that doesn't ship the 'which one runs?'
    ambiguity to the user."
  - **AI/ML:** A — "A sub-trait that re-seals with a strengthened body produces two same-named
    methods both visible to an impl author — and to a code-generating model, that is an
    unresolvable authority question ... This is the exact failure mode AIs already botch in C++
    name-shadowing and Python diamond MRO. Rejecting deletes a decision point rather than adding
    one."
  - **Minimalism:** A — "Allowing sub-trait re-sealing would add a third sealing rule to serve
    zero use sites — I grepped lib/ and src/ and found no subtraits and no `final fn` defaults, so
    the ticket's own reopen trigger has not fired. The workaround (seal at the supertrait;
    monotonic-down propagates) is strictly simpler and ships today."

- **Q2 — Diagnostic framing (6-0 for PERMANENT RULE):**
  - **Systems:** A — "Framing it as 'deferred / not yet supported' is a forward-compatibility
    liability — it implies a future where two authoritative bodies coexist ... The rule is a real
    coherence/perf invariant, not a missing feature, so the diagnostic should say so and point
    users at the two correct paths."
  - **Web/Scripting:** A — "'Not yet supported' trains users to file feature requests and wait,
    then come back disappointed ... A permanent framing with two concrete escape hatches ... turns
    the error into a teaching moment that closes the loop in one read."
  - **PLT:** A — "Framing it as 'deferred / not yet supported' mis-signals that the language merely
    lacks an implementation, when in fact strengthening is unsound under static dispatch — there is
    nothing to ship later."
  - **DevOps:** A — "'Not yet supported / deferred' framing tells the user to wait for a feature
    that we have collectively decided is wrong ... Framing it as a permanent rule with two concrete
    fixes ... turns the error into an actionable redirect instead of a roadblock."
  - **AI/ML:** A — "'Not yet supported / deferred' framing trains a model to expect the rule will
    loosen and to generate hopeful-but-wrong code against a future that may never arrive; a
    permanent-rule frame with both legal moves spelled out is self-correcting in one shot."
  - **Minimalism:** A *(flipped from her Phase-A "not yet / YAGNI" lean)* — "I came in leaning 'not
    yet (YAGNI),' but PLT/Web are right that a permanent rule is the clean symmetric closure of
    monotonic-down — and crucially, a permanent rule is the more *minimal* outcome for users: it
    closes the question, removes the deferred-decision debt, and gives one stable mental model
    rather than a door we'd have to revisit. A 'deferred' framing keeps a third rule perpetually
    pending in everyone's head, which is the opposite of subtraction."

No question closer than 6-0; Phase D not triggered.

#### Phase C — Concerns recorded

- **DevOps / Minimalism / AI/ML:** `E0733` must fire at the **seal/declaration site**, not the
  call site, and must not catch a legitimate normal `impl`-block override of the open default.
- **Web:** the help text must name the **declaring** supertrait by name, not just "the
  supertrait," or the fix is still a hierarchy hunt.
- **Minimalism:** keep the rule **narrowly scoped** to sub-trait re-sealing of inherited
  defaults — do not foreclose a genuinely different future feature (e.g. effect-row sealing).
- **AI/ML:** ensure the error fires on *strengthening specifically*, so models do not learn to
  fear and pad around a harmless construct.

#### Phase 8.5 — AI-First Review

Scored the resolved decision against the five AI-first criteria — all pass:

- **Learnability.** One sentence, stated as the symmetric closure of the already-spec'd
  monotonic-down rule. Pass.
- **Consistency.** No new dispatch rule; reinforces the "no MRO" identity rather than carving an
  exception. Pass.
- **Generability.** Deletes the "should I re-seal here?" decision point; the construct is
  unrepresentable, so an AI cannot emit the two-methods-visible hazard. Pass.
- **Debuggability.** Typecheck-time at the declaration site; help text names both legal fixes.
  Pass.
- **Token efficiency.** Zero cost in the common case; one error code added. Pass.

### Final Spec

```blink
trait Greeter {
    fn greet(self) -> Str { "hello" }          // open default
}

trait LoudGreeter : Greeter {
    final fn greet(self) -> Str { "HELLO" }    // E0733 — rejected at this declaration
}
```

```
error[SubtraitMethodRedeclaration]: cannot seal inherited open default `greet`
  --> greet.bl:6:5
   |
6 |     final fn greet(self) -> Str { "HELLO" }
   |     ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ `Greeter.greet` is an open default; `LoudGreeter : Greeter` may not re-seal it
   |
   = note: sealing is monotonic — a subtrait cannot strengthen a supertrait's open
           default, because `x.greet()` would resolve differently through the
           `Greeter` view than the `LoudGreeter` view
   = help: to seal `greet` for every implementor, mark it `final` on `Greeter` itself
   = help: to specialize behavior for one type, override `greet` normally in its `impl`
```

Locked design points:

- **Reject strengthening.** A subtrait may not re-declare a method that a supertrait provides
  as an **open** default in order to seal it. Both `final fn m { body }` and any redeclaration
  of `m` in subtrait position are rejected.
- **Diagnostic: `E0733 SubtraitMethodRedeclaration`**, fired at the subtrait's redeclaration
  site (not at any call site). Sits next to `E0731 SealedMethodOverride` and `E0732
  FinalRequiresBody`.
- **One legal direction for sealing.** A method's sealed-ness is fixed at the trait that first
  declares its body. No subtrait may un-seal (E0731, monotonic-down) or strengthen (E0733,
  monotonic-up) it. This is the symmetric closure of 344dnd Q4.
- **Rationale is coherence.** With no MRO and static resolution against the trait the bound
  names, a re-sealed `m` would give `via_super[T: Super](x).m()` and `via_sub[T: Sub](x).m()`
  different answers for the same `x`. Reject keeps `Sub <: Super` honest with zero new dispatch
  machinery.
- **Permanent rule, not a deferral.** The diagnostic does not advertise a future "allow."
- **Workaround.** Seal at the supertrait (monotonic-down propagates the seal to every subtrait
  and impl for free), or override the open default normally in the impl (replace-only, no
  `final`). The help text names both.
- **Narrow scope.** The rule governs sub-trait re-sealing of inherited open defaults only; it
  does not bear on other potential sealing axes.

### Vote summary

Q1: 6-0 reject strengthening + `E0733`. Q2: 6-0 permanent-rule framing (Minimalism flipped
from a Phase-A "not yet / YAGNI" lean to permanent-rule on the symmetric-closure argument).
No dissent; Phase B and Phase D not triggered.
