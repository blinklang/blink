[< All Decisions](../DECISIONS.md)

# Contracts on Trait Methods — Design Rationale

`sections/03b_contracts.md` had a stopgap rule: "Contracts attach to functions and to methods in
`impl` blocks. A `@requires`, `@ensures` or `@verify` on a trait method declaration is a compile
error (E1110); contracts on trait methods are not yet specified." Contracts on impl methods already
worked as ordinary function contracts. That leaves a hole. A generic caller through `T: Trait`
sees only the trait, so an impl `@requires` it cannot see can fail after monomorphization.

The ticket for this gap listed five sub-questions:

- **(a)** May a trait method declaration carry `@requires` or `@ensures`?
- **(b)** Do impl methods inherit them?
- **(c)** May an impl add a `@requires` that a generic caller through `T: Trait` cannot see?
- **(d)** Where does `@verify` go: the trait declaration, the impl, or both?
- **(e)** If an impl renames a parameter, is an inherited predicate bound by position?

The panel grouped the work into four questions:

- **Q1.** Inheritance, and what an impl may add. This covers (a), (b) and (c).
- **Q2.** Where `@verify` goes. This is (d).
- **Q3.** Parameter binding when an impl renames a parameter. This is (e).
- **Q4.** Eight sub-questions the panel added:
  - **4-1.** Supertraits.
  - **4-2.** Default methods.
  - **4-3.** Calls through a bound.
  - **4-4.** Predicate scope and purity.
  - **4-5.** A predicate that calls its own function.
  - **4-6.** `@ffi`.
  - **4-7.** The formatter.
  - **4-8.** Migration.

**A note on quotation.** Panelist text is verbatim. Three exceptions:

1. `br` ticket identifiers are replaced by a bracketed description, for example "[the
   trait-annotation parser ticket]". `br` is local-only. No quoted passage below needed this.
2. The panel used working codes. Three were renumbered at spec time because they were taken or out
   of range. Quotes keep the panel's original code. The mapping is: E1111 -> E0912
   (`TraitImplAddsPrecondition`), E1112 -> E0913 (`TrustOnTraitMethod`), W0851 -> W0900
   (`RestatedInheritedEnsures`). W0850 was rejected, so it has no final code.
3. The AI/ML Phase A text was reconstructed by the moderator after a relay loss. It was not
   captured verbatim. The other five Phase A texts are verbatim.

Where a quote has an ellipsis ("…"), the panelist's words are cut there. No panelist text is
reworded.

---

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in
independent-proposal, debate and vote rounds. Phase A produced six proposals. A deduplication step
grouped them into options Q1-A to Q1-E, Q2-A to Q2-C, Q3-A and Q3-B, and Q4-1 to Q4-8. Phase B ran
one round, after which all six marked "Stable, ready to vote". Phase C was a silent vote. Q1, Q3
(except the W0850 lint) and Q4 passed. Q2 and the W0850 lint both tied 3-3, so Phase D ran one
debate round on those two items and a silent re-vote. Q2 passed 6-0 for a variant of Q2-B, and
W0850 was rejected 6-0. The user signed off on the result.

#### Phase A — Independent proposals

- **Systems** (favored S1, "the trait contract is the interface, and impls may only add
  guarantees"): "The decisive fact for me: we monomorphize, so a call through `T: Trait` always
  lands on one concrete impl function, and the contract check is ordinary code in that function's
  mono copy." On (c): "Forbidden. This is a new error, TraitContractPreconditionAdded, and it
  mirrors E0904. An impl may add `@ensures`, which makes the guarantee stronger." On (d), `@verify`
  "On both, and they cover different obligations", and "`fallback: "trust"` is forbidden on a trait
  declaration. A trait author must not vouch for impl bodies they have never seen." On (e):
  "Inherited predicates bind by position." and "Diagnostics must print both names". It rejected
  contracts on impls only: "You end up with the restrictions and none of the value." It deferred
  full Liskov, "S1 can grow into it without breaking anything."
- **Web/Scripting** (favored W1, "The trait owns the contract"): On (c): "An impl may not add a
  `@requires` at all. That is a new error, something like E1111 ImplAddsPrecondition." and "A
  stronger promise never hurts a caller." On (d): "On the trait declaration it is the default
  policy for every impl body. On an impl method it replaces that default for that one body." The
  reason: "if `@verify` lived only on impls, a trait with 20 impls would need the same line 20
  times or give 20 V0003 errors." On (e): "By position." and "Renaming `self` changes nothing,
  because the contract still binds to position 0." Mental model: "The trait says what every impl
  promises; impls can promise more, never demand more." It rejected W2, which made an impl restate
  the contract: "the "Java checked exceptions" experience: copy-paste walls".
- **PLT** (favored Proposal 1, "the trait contract is the interface, and impls refine it only
  covariantly"): "A trait method's contract is part of its interface type." On (c): "No. An impl
  method that implements a trait method may not have its own `@requires`; that is a new error,
  ImplStrengthensPrecondition. The impl may add `@ensures` clauses, which are conjoined with the
  trait's." On (d): "Only where a body exists. That means impl methods and trait default methods;
  on a trait declaration without a body it is an error." On (e): "Yes. A trait contract is a closed
  term `λ(x₁..xₙ). P`, and the impl instantiates it by capture-avoiding substitution
  `P[y₁/x₁ … yₙ/xₙ]`." It added a sub-question: "A predicate on method `m` may not call `m` itself
  (a new error), so that contract meaning stays well-founded."
- **DevOps** (favored Proposal A, "the trait owns the contract, impls inherit it, and impls may only
  add `@ensures`"): "My lens: every rule must give a diagnostic that points at the right line, a
  hover that shows the contract in force, and a `blink query --layer contract` row an agent can
  trust without reading other files." On (c): "An impl of a trait method may not add a `@requires`.
  Doing so is E1111." On (d): "On an impl it governs that impl's body obligations (inherited plus
  its own `@ensures`), and it overrides the trait's." and "`@verify(fallback: "trust")` on a trait
  declaration is E1112. A trait author cannot vouch for impls they never see, often in other
  packages. They may only write `"runtime"`." On (e): "Lint W0850 `contract-param-renamed` (warning,
  may be suppressed with `@allow`) fires when an impl renames a parameter that the trait contract
  names, because readers will grep for the trait's name." It also proposed: "An impl that restates
  the trait's predicate word for word gets lint W0851 `redundant-inherited-contract`. `blink fmt`
  never adds or removes contracts."
- **AI/ML** (reconstructed by the moderator, not verbatim; favored Proposal A, "Trait owns the
  contract; impls inherit, may only add `@ensures`"): On the status quo: "That breaks §3b.3 ("the
  contract is the interface") exactly the way E0904 exists to prevent for effects. Any ruling must
  close this." On (c): "An impl method of a trait may NOT declare `@requires` (new error,
  ImplAddsPrecondition)." On (d): "`@verify` goes on the impl method only; on a trait declaration
  it is an error." On (e): "Bind by name, enforced. If a trait method carries a contract, every
  impl must use the trait's parameter names, `self` included (new error, ImplParamNameMismatch,
  fix-it "rename `x` to `n`")." Rule in one line: "Preconditions live on the trait; impls may
  promise more, never demand more."
- **Minimalism** (favored M1, "The trait owns the contract and impls inherit it unchanged"): "Even
  "do nothing" must close this hole, so status quo is not a valid option." On (c): "A trait impl
  method may not write its own `@requires` or `@ensures` (new error, for example
  "TraitImplContract"). No weakening, no strengthening, no adding." On (d): "`@verify` goes where a
  body is: on the impl method, and on a trait default method." On (e): "Inherited predicates bind
  by position." Its accepted cost: "each impl must write its own `@verify` line. I accept this. It
  keeps every `trust` visible to grep for each impl". It rejected full Liskov (M2): "A rule the
  compiler can never enforce is surface area with no value."

All six agreed on a core: a trait method may carry `@requires` and `@ensures`, impls inherit them,
an impl may not add a `@requires`, and an impl `@requires` is checked as a new error that mirrors
the effect-row rule E0904. Five of the six also let an impl add `@ensures`. Minimalism did not.

#### Phase B — Debate highlights

The moderator grouped the Phase A texts into the options in the table below and sent them back for
one round of replies.

| Question | Options |
|---|---|
| Q1 | Q1-A: impl inherits, may not write `@requires`, may add `@ensures`. Q1-B: impl may write no contract. Q1-C: full Liskov. Q1-D: impl restates the contract. Q1-E: no contracts on trait declarations. |
| Q2 | Q2-A: body only. Q2-B: trait is the default, impl overrides. Q2-C: split by obligation. |
| Q3 | Q3-A: positional. Q3-B: name match enforced. |
| Q4 | 4-1 to 4-8, the sub-questions listed above. |

**A fact corrected three Phase A texts.** Minimalism's Q1-B sent a stronger guarantee to an
inherent method, and Blink rejects inherent methods (DECISIONS.md, 4-1). Several panelists said so:

- **Web:** "Blink has no inherent methods (rejected 4-1). Under Q1-B the only route left is a free
  fn wrapper".
- **Systems:** "I wrote "it can expose an inherent fn with its own contract". DECISIONS.md rejects
  inherent methods (4-1), so that route does not exist."
- **AI/ML:** "Correction to my own Phase A text: my migration note ("or make the method inherent")
  is void for the same reason."
- **Minimalism** moved from Q1-B to Q1-A: "Under Q1-B the only route left is a free wrapper fn,
  which adds one more name for each guarantee. Q1-A adds no new rule shape: "the impl may narrow,
  may not widen" is the E0904 effect-row rule applied to behavior."

PLT added why a concrete caller may see more than a generic one: "Q1-A stays sound because no
caller can obtain `Q_i` without statically naming the one impl that proves it."

**The restated-contract sub-point.** DevOps: "I keep W0851 (a lint, not an error)." and "it must be
E1111 with that note, not a third error code. One error per rule." Web dropped its own wording: "I
drop my "allowed, no effect" wording in favor of W0851." **(dissent)** Minimalism: "So I am against
devops's W0851 and aiml's separate "already inherited" error. Both add surface for a case the base
rule already covers."

**Q2 moved the most.** Systems and PLT corrected the claim that a caller's policy governs an
Unknown `@requires`:

- **PLT:** "I wrote "call-site discharge of `@requires` follows the caller's policy". That is wrong
  under §3b.4." Under the corrected rule, an impl method elaborates to a plain function: "the
  semantics *is* the elaboration to an existing construct."
- **DevOps** had argued the same from the other side: "The spec has no caller-side policy." DevOps
  first preferred Q2-C: "Q2-C (sys) is my first choice. I can accept my Q2-B variant as an
  add-on."
- **Systems** moved from Q2-C to body only: "I move from Q2-C to Q2-A, with one stated variant" and
  "Who pays at runtime must be visible in the body that pays."
- **Web** moved to the DevOps variant of Q2-B: "sys, aiml and min are right that a trait author
  must not vouch for bodies they never saw. I concede that point, and the devops variant fixes it."
- **AI/ML** moved the same way: "That is a token-cost argument and it is my domain, so I concede
  it."
- **Minimalism** held at Q2-A: "Devops's E1112 is only needed because Q2-B exists. Under Q2-A it
  disappears."

**Q3 converged on position.** AI/ML dropped name matching: "min asked for "a real readability
failure that the diagnostics cannot fix." I cannot show one." and "Name-match enforcement is
dropped." The other five gave an API-evolution reason:

- **Minimalism:** "Adding a contract to an existing trait method would break every downstream impl,
  in packages the trait author never sees, because of a parameter name alone."
- **PLT:** "It also creates an API-evolution hazard: today a trait author can rename a parameter
  without breaking anyone, but under Q3-B that rename breaks every downstream impl in every
  package."
- **DevOps:** "It turns a cosmetic edit into a breaking change for every impl downstream when a
  trait author adds a contract."

Rendering moved toward both names. DevOps: "For diagnostic rendering I take sys's "both names":
`trait param n (impl param count)`." PLT: "Diagnostic rendering: I adopt sys's "both names" form."
**(dissent)** Minimalism rejected the W0850 lint: "Against devops's W0850: a lint that fires on a
legal, common rename is noise, so I reject it."

**Q4.** All six accepted 4-1, 4-2, 4-3 and 4-6. Two items split:

- **4-5, a predicate that calls its own function.** Systems gave the reason for a rule: "Without
  the rule, a runtime check of `m`'s contract calls `m`, which checks the contract again, and
  recurses without end." **(dissent)** Minimalism: "If a predicate calling its own fn is a problem,
  it is one for every fn contract. Put it in the general contract rules, not as a trait-only
  error." PLT kept the trait rule: "I keep Q4-5 (no self-call in a method's own contract) so that
  contract meaning stays well-founded." DevOps asked for more: "yes, with a dedicated error. A
  cycle through two methods should get the same error, with the cycle printed."
- **4-7, the formatter.** **(dissent)** Minimalism: "no spec text. `blink fmt` already never
  changes semantics, so a rule for contracts alone is redundant."
- **4-8, migration.** The inherent-method fix applied here too. Minimalism: "a migration note, not
  a spec rule, with the wording fixed as above."

#### Phase C — Final vote

The moderator gave the panel two codebase facts. First, §3b.4 puts `@verify` on the function that
declares the contract, and says nothing about whose `@verify` covers an Unknown `@requires` at a
call site. Second, today a function's own `@verify(fallback: "runtime")` emits its `@requires`
checks at that function's entry, and callers emit no check.

##### Q1: inheritance and what an impl may add (**6-0 Q1-A**)

Q1-A: the trait method may carry `@requires` and `@ensures`. Every impl inherits them. An impl may
not write `@requires`. An impl may add `@ensures`, ANDed with the trait's. Generic callers assume
only the trait's `@ensures`. A caller that names the concrete type assumes both.

- **Systems:** Q1-A — "An impl `@ensures` is one more conjunct, checked in a body we already emit."
  *Concern:* "Users will expect a concrete call to see a stronger `@requires` too, and the error
  for that case must name only real fixes: move it to the trait, use a refinement type, or call a
  free fn."
- **Web/Scripting:** Q1-A — "The rule is one sentence: "impls may promise more, never demand
  more."" *Concern:* "users will expect a concrete-receiver call to also accept a looser input than
  the trait allows, and the E1111 help text must make clear why it doesn't."
- **PLT:** Q1-A — "Q1-A is behavioral subtyping with the same variance as the effect-row rule."
  *Concern:* "Users will want the escape hatch Q1-A forbids, a weaker `@requires`, and will reach
  for `trust` to fake it. That pressure should become a solver-era ticket for checked weakening,
  not a loosening of this rule."
- **DevOps:** Q1-A — "Q1-A keeps the stronger guarantee on the method itself." *Concern:*
  "Concrete-receiver callers and generic callers see different postconditions. If hover and query
  do not show which contract is in force at a call site, users will assume an `[own]` `@ensures`
  holds through `T: Trait`."
- **AI/ML:** Q1-A — "The rule fits in one sentence: "impls may promise more, never demand more"."
  *Concern:* "Models may read an impl's own `@ensures` as visible through `T: Trait` and write
  generic code that relies on it. The V0003/V0002 text must say "this guarantee is visible only to
  callers of the concrete type"."
- **Minimalism:** Q1-A — "Blink has no inherent methods, so Q1-B's only escape route is a second
  name for the same operation." *Concern:* "impl `@ensures` gives a concrete caller and a generic
  caller different facts about one call, and tooling must show which view is in force."

**Q1 sub-point: a restated contract (5-1).** Option (i) is lint W0851 for a restated `@ensures`,
plus an "already inherited from" note on the impl-`@requires` error. Option (ii) is no special
rule. Systems, web, PLT, DevOps and AI/ML voted (i). **(dissent)** Minimalism voted (ii).

- **Systems:** "under `fallback: "runtime"` a restated `@ensures` emits the same check twice in
  every mono copy, and the lint finds that duplicate."
- **AI/ML:** "A note that names where the contract came from turns that mistake into a fix in one
  step, at no extra spec cost."
- **PLT:** "The restated-contract sub-point is diagnostic quality, not semantics."
- **Minimalism (dissent):** "A restated `@ensures` is one more ANDed clause and does no harm. A
  restated `@requires` already gets the Q1-A error. A message note such as "already inherited from
  `Stack.pop`" is diagnostic wording, not a rule, and I do not object to it. W0851 is a lint for a
  case that hurts nobody."

##### Q2: where `@verify` goes (**3-3, went to Phase D**)

Q2-A: body only. Q2-B, DevOps variant: a trait may set only `"runtime"` as the default for impl
bodies, `"trust"` on a trait is E1112, and an impl `@verify` replaces the default. Q2-A: systems,
PLT, minimalism. Q2-B DevOps variant: web, DevOps, AI/ML.

- **Systems:** Q2-A — "Under Q2-A an impl method elaborates to exactly that construct, with one
  check per mono copy and no new codegen path." *Concern:* "Until a solver exists, every impl of a
  contracted stdlib trait needs a `@verify` line or gets V0003. So stdlib must not put contracts on
  core traits (`Ord`, `Eq`, and so on) until the solver ships, or every user who writes an impl
  hits that wall."
- **Web/Scripting:** Q2-B DevOps variant — "With no solver, Q2-A means every user who implements a
  contracted trait gets V0003 on a contract they didn't write until they add a line they don't
  understand." *Concern:* "if Q2-A wins, the V0003 help on an impl must say "add
  `@verify(fallback: ...)` to this impl method for the contract inherited from `Trait.m`". If it
  does not, users will be lost."
- **PLT:** Q2-A — "Each impl method elaborates to a plain fn with contract `P_t[σ] / Q_t[σ] ∧ Q_i`
  (σ is the positional renaming) and the impl's own `@verify`." *Concern:* "Until a solver ships,
  every impl of a contracted trait (the `Ord` case web raised) needs one `@verify` line or fails
  V0003. That friction may push users to `trust` by habit."
- **DevOps:** Q2-B DevOps variant — "The codebase fact settles my round 1 objection to Q2-A."
  *Concern:* "If Q2-A wins, the V0003 help text must name the impl method as the place for
  `@verify` and say that the contract comes from the trait. Without that, the error points at a
  trait line the user cannot edit."
- **AI/ML:** Q2-B DevOps variant — "With no solver, Q2-A means every generated impl of a contracted
  std trait (`Ord`, etc.) fails V0003 on a contract the user did not write until they add a
  boilerplate line." *Concern:* "The runtime cost of an inherited `"runtime"` default does not
  appear in the impl body (sys's point). Hover and `blink query` must show the inherited `@verify`
  row, or readers will miss it."
- **Minimalism:** Q2-A — "A trait-level default, even "runtime" only, is a permanent annotation
  site that fixes a gap lasting only until the solver exists." *Concern:* "if stdlib puts contracts
  on prelude traits like `Ord` before a solver exists, every user impl gets V0003. Stdlib must not
  contract prelude traits until the solver ships."

##### Q3: parameter binding (**6-0 Q3-A**; rendering **6-0 both names**; W0850 lint **3-3, went to Phase D**)

Q3-A: inherited predicates bind by position, `self` binds to position 0, and the compiler adds no
parameter-name check. Rendering option (iii) prints both names: "trait param `n` (impl param
`count`)". All six voted Q3-A and (iii). On W0850: web, DevOps and AI/ML voted yes. Systems, PLT
and minimalism voted no.

- **Systems:** Q3-A, (iii), W0850 no — "Position is the identity the function type already has." On
  the lint: "A warning on a legal, common rename is noise that people will learn to `@allow` away."
  *Concern:* "The diagnostics, `blink query` and hover must all use the same rendering, or the
  positional mapping really does become a source of misreads."
- **Web/Scripting:** Q3-A, (iii), W0850 yes — "Python, TS and Kotlin let an override rename params,
  and users expect the same." On the lint: "The lint gives a soft push with an LSP quick-fix and
  breaks no build." *Concern:* "W0850 can get noisy on `self` → `this` renames, which are legal and
  spec'd. It should not fire when only the receiver is renamed."
- **PLT:** Q3-A, (iii), W0850 no — "An inherited predicate is a closed term over formal positions,
  and renaming is alpha-equivalence." On the lint: "A warning on a legal, semantics-free rename
  tells users names matter, which contradicts the rule we just adopted." *Concern:* "Rendering may
  drift across diagnostics, `blink query` and hover unless the spec fixes a single rendering for
  all three."
- **DevOps:** Q3-A, (iii), W0850 yes — "Q3-A gives positional binding by capture-avoiding
  substitution." On the lint: "W0850 is a warning that `@allow` can suppress, and the LSP offers a
  "rename to trait name" quick-fix." *Concern:* "Every surface must render the same form, or the
  agents that read one surface and edit another will be wrong: diagnostics, hover, `blink query`,
  and V0002 counterexamples."
- **AI/ML:** Q3-A, (iii), W0850 yes — "Of the three renderings, the both-names form is the most
  robust for an agent: it can grep the impl or the trait for either name, and a few extra tokens
  buy that." On the lint: "W0850 is a nudge an agent can follow at no build cost." *Concern:* "If
  any one surface (diagnostic, query, hover) prints only the trait's names, agents will patch the
  wrong identifier in the impl body."
- **Minimalism:** Q3-A, (iii), W0850 no — "I move from (ii) to (iii) to converge. It costs nothing
  and lets a reader grep for either name." On the lint: "W0850 warns on a legal, common rename, and
  the both-names diagnostic already fixes the readability case, so the lint is surface with no
  gain." *Concern:* "both-names rendering must reach every surface (diagnostics, hover, `blink
  query`), or the misreading aiml fears comes back."

##### Q4: sub-questions (4-1, 4-2, 4-3, 4-4, 4-6 **6-0 yes**; 4-5 **6-0 general rule**; 4-7 **5-1 no spec text**; 4-8 **6-0 migration note only**)

The ballot for 4-5 offered three options: (i) a trait-specific error, (ii) a general rule for all
function contracts, (iii) no rule. All six voted (ii). On 4-7, five voted (ii), no spec text, and
**(dissent)** DevOps voted (i), spec text. On 4-8, all six voted (ii), a migration note only.

- **Systems:** "4-3 matters most for me. Mono must never bring an impl contract into a generic
  caller's proof, or the verification result would change with the instantiation." And on 4-5: "A
  predicate that calls its own fn recurses at runtime without end for any fn, not only trait
  methods, so the rule belongs in the general contract text." *Concern:* "If 4-5 is deferred to a
  general ticket and that ticket stalls, a runtime-checked contract that calls its own method
  recurses until the stack overflows, and nothing in the spec forbids it in the meantime."
- **Web/Scripting:** "A self-recursive contract is a problem for any fn, so one general rule is
  easier to learn than a trait-only one." *Concern:* "if 4-5 goes into the general contract rules,
  the work must actually happen (a friction ticket), or the trait case ships with no rule at all."
- **PLT:** "I accept min's correction on 4-5." And: "4-3 keeps verification results independent of
  instantiation." *Concern:* "If 4-5 goes to a separate general ticket, trait contracts ship before
  that rule exists. A self-calling trait contract would then recurse without end under `"runtime"`
  in the interim."
- **DevOps:** On 4-5: "A predicate that calls its own fn recurses without end at runtime, whether
  the fn is a trait method or not. One general error with the cycle printed is more correct than a
  trait-only rule." **(dissent)** On 4-7: "I want the formatter's contract behavior stated, because
  tools and agents read the spec to learn what `blink fmt` may touch." *Concern:* "4-5 as a general
  rule extends past this ticket. Make sure it gets its own spec text and error code, and does not
  stay implied by trait text."
- **AI/ML:** "Each yes follows directly from Q1-A, and an AI can derive it from the spec once it is
  stated." On 4-7: "fmt already never changes semantics, so the text would only repeat that."
  *Concern:* "Under 4-5 (ii), the general rule may never be written if the panel defers it to a
  separate ticket, which leaves trait contracts with an unbounded runtime-check recursion in the
  meantime."
- **Minimalism:** 4-4 — "yes, same purity rule as fn contracts". On 4-5: "sys's recursion argument
  for 4-5 is true of any fn whose contract calls itself, so a trait-only error would leave the same
  hole in plain fns. Fix it once, in the general contract rules." *Concern:* "if the panel puts 4-5
  as trait-only text, the same recursion in plain fn contracts stays unspecified. Log it as a
  friction item either way."

#### Phase D — Round 2 (Q2 and the W0850 lint)

Phase C left two items tied 3-3: Q2 and the W0850 lint. Phase D ran one debate round on those two
items and a silent re-vote. The brief said: "If the re-vote is still 3-3, the user casts the
deciding vote."

##### Q2: debate

Systems and minimalism held Q2-A in the debate. The other four held or moved to the DevOps variant.

- **Systems** (held Q2-A): "Consistency is the larger point. Today V0003 is the default for an
  Unknown contract on every fn. Q2-B makes trait-inherited contracts the one place in the language
  where Unknown silently turns into runtime checks." And on cost: "A runtime check is not free, and
  the trait methods most likely to carry contracts run in the hottest loops."
- **Minimalism** (held Q2-A): "Q2-A can be undone without breaking anyone. Q2-B cannot." and "YAGNI
  says ship the reversible rule and add the default when the need is proven."
- **AI/ML** (held Q2-B): "sys's "dead weight" argument has it backwards." and "A fallback applies
  only when the outcome is Unknown (§3b.4 table: "Unknown + `runtime`"). A Proven contract costs
  zero whatever `@verify` says." On the Q2-A side's own concern: "The fix this proposes is to not
  use the feature on the traits that matter most."
- **DevOps** (held Q2-B): "Unknown is a permanent outcome in §3b.4 (solver timeouts, undecidable
  theories), so a default for it is never dead text."
- **Web** (held Q2-B): "Q2-A makes `trust` the easy path." and "Under the variant, the user who
  does nothing gets the safe outcome. Making the safe path the default is the reason to have a
  default."
- **PLT** (moved to Q2-B DevOps variant): "What tips me: trait evolution. Under Q2-A, adding an
  `@ensures` to a published trait method breaks the build of every downstream impl with V0003 until
  each one adds a line. Under the variant, the trait author adds the contract with
  `@verify(fallback: "runtime")`, and every downstream impl stays well-typed: the new obligation
  becomes a fail-fast check." PLT set three conditions: "The default resolves during elaboration,
  before verification.", "It covers open-default override bodies too." and "An impl `@verify`
  replaces the trait's default as a whole; the two never merge."

##### Q2: re-vote (**6-0 Q2-B, DevOps variant**)

All six voted for the DevOps variant: a trait may set only `"runtime"` as the default for impl
bodies, `"trust"` on a trait is E1112, and an impl `@verify` replaces the default as a whole, with
PLT's three conditions. Systems and minimalism moved from Q2-A.

- **Systems:** "My "dead weight" argument was wrong. A fallback applies only to Unknown, and a
  Proven contract compiles to nothing whatever `@verify` says, so the trait default never costs
  anything for a proven contract." *Concern:* "An inherited `"runtime"` check on a hot trait method
  (`compare` inside `sort`) puts cost into release inner loops that no body shows. Inherited
  defaults must follow exactly the same debug/release policy as a plain fn's runtime fallback, and
  `blink query` must show the inherited row."
- **Web/Scripting:** "plt's trait-evolution point decides it for me: under Q2-A, a trait author who
  adds one `@ensures` breaks every downstream impl's build." *Concern:* "sys's hot-loop point is
  real. An inherited runtime check on a contracted `compare` runs on every call inside `sort`, and
  the impl body has no annotation that says so. Hover and `blink query` must show the inherited
  `@verify` row, and stdlib must weigh that cost before it adds a contract to a hot-path trait
  method."
- **PLT:** "In §3b.4, the `@verify` sits on the declaration that owns the contract. For a trait
  method, that owner is the trait." *Concern:* "Sys's hot-path case is real. A trait default can
  put a runtime check, and an `old()` copy, into an impl body that shows no annotation. The spec
  must therefore require that the inherited row appear on every surface: query, hover, and the
  generated-C trace."
- **DevOps:** "plt's trait-evolution point decides it for me as a tooling matter." *Concern:*
  "sys's hot-loop case. An inherited `"runtime"` check on a method like `compare` costs O(n log n)
  at runtime with no annotation in the body. Hover and query must tag the row, and the V0001/V0003
  report must list each inherited runtime check per impl, so that cost is easy to find."
- **AI/ML:** "The variant makes doing nothing the safe outcome." *Concern:* "sys's hot-loop case is
  real. A `"runtime"` default on a contract like `compare` adds a check, and possibly an `old()`
  copy, to every call inside `sort`. Stdlib trait authors must weigh that before they set the
  default on hot methods."
- **Minimalism:** "I move from Q2-A, because the round 1 replies disproved two of my three Phase D
  arguments." and "The trait-evolution case decides it (plt)." *Concern:* "sys's hot-loop point. A
  trait author's `"runtime"` default puts checks and `old()` snapshots into code like `compare` in
  `sort` without any visible line in that body. Hover, query and the docs must make the inherited
  cost obvious."

##### W0850 lint: debate

Three panelists voted yes in Phase C. All three moved to no in the debate.

- **PLT** (held no): "The both-names rendering (6-0) already deals with that cost on every surface
  the lint could reach. The lint adds no information the diagnostic does not already print."
- **Systems** (held no): "If the LSP wants a "rename to trait name" quick-fix, it can offer that as
  an assist with no diagnostic."
- **Minimalism** (held no): "**Alternative I accept:** a convention line in the style guide, not a
  lint: "keep the trait's parameter names in impls unless you have a reason."" and "I would accept a
  style-guide convention in place of W0850."
- **DevOps** (moved yes to no): "What I keep is outside the spec: the LSP may offer "rename
  parameter to trait name" as a code action on a renamed param. A code action is not a diagnostic,
  it gives no warning, and it needs no spec text. Spec result: no W0850."
- **AI/ML** (moved yes to no): "What W0850 adds after that is a mixed signal. The spec says names do
  not matter, and the tooling warns when they differ."
- **Web** (moved yes to no): "A warning on code that is correct, and that Python/TS/Kotlin devs
  write without thinking, produces a "how do I silence W0850" question and teaches users to add
  `@allow` reflexively."

##### W0850 lint: re-vote (**6-0 no**)

The panel rejected W0850 6-0. In its place: an LSP "rename to trait name" assist (not a
diagnostic, no spec text) and a style convention.

- **Systems:** "The both-names rendering, passed 6-0, already fixes the readability case on every
  surface, so the lint fires only on legal code that means the same thing." *Concern:* "If some
  surface (a V0002 counterexample, a hover) prints only one name, the misread returns, and with no
  lint nothing flags it."
- **Web/Scripting:** "A warning on a legal, common rename that means the same thing teaches users
  that names matter, which contradicts Q3-A." *Concern:* "if the both-names rendering slips on any
  one surface (hover, query, V0002 counterexample), the readability gap comes back with no lint to
  catch it."
- **PLT:** "Q3-A makes the binding positional, so names carry no meaning. Both-names rendering (6-0)
  already removes the readability cost on every surface." *Concern:* "Without the lint, readability
  depends on every surface using the both-names rendering. A single tool that prints only one name
  brings back the misread."
- **DevOps:** "Under warnings-as-errors CI it also brings back the breaking-change hazard that Q3-B
  was rejected for." *Concern:* "If a later tool or style guide adds the nudge again as a default-on
  warning, it will bring back the same mixed signal. Keep it as an assist only."
- **AI/ML:** "A warning on a legal rename teaches models a second, informal identity rule that Q3-A
  rejects." *Concern:* "Without any nudge, impls may drift from the trait's names. The style-guide
  convention min offers (or sys's LSP assist) should be recorded so the nudge is not lost entirely."
- **Minimalism:** "A warning on a legal rename with no semantic effect contradicts the Q3-A rule."
  *Concern:* "with no lint, nothing prompts authors to keep the trait's names, so the both-names
  rendering must be implemented on every surface, not only in diagnostics."

---

### Final Spec

This section is in `sections/03b_contracts.md`, subsections *Contracts on Trait Methods* and
*Contracts That Call Their Own Function* (4-5).

```blink
trait Stack {
    fn size(self) -> Int

    @requires(self.size() > 0)
    @ensures(result.size() == old(self.size()) - 1)
    fn drop_top(self) -> Self
}

impl Stack for IntStack {
    fn size(self) -> Int { self.items.len() }

    // Inherits `@requires(self.size() > 0)` and the trait's `@ensures`.
    @ensures(result.items.len() == self.items.len() - 1)    // OK: an impl may add @ensures
    @verify(fallback: "runtime")
    fn drop_top(self) -> IntStack {
        IntStack { items: self.items.drop_last() }
    }
}

trait Score {
    @ensures(result >= 0 && result <= 100)
    @verify(fallback: "runtime")              // default for every impl body
    fn score(self) -> Int
}

impl Score for Exam {
    // No @verify: the trait's "runtime" default applies to this body.
    fn score(self) -> Int {
        self.correct * 100 / self.total
    }
}

impl Score for Model {
    @verify(fallback: "trust")                // replaces the trait default for this body
    fn score(self) -> Int {
        self.eval_score()
    }
}

trait Shape {
    @ensures(result >= 0.0)
    @verify(fallback: "trust")                // E0913 -- "trust" on a trait method declaration
    fn area(self) -> Float
}
```

Locked points:

- A trait method declaration may carry `@requires`, `@ensures` and `@verify(fallback: "runtime")`.
  Every impl of the method inherits them. Rule in one line: an impl may promise more, never demand
  more. It has the same narrow-only shape as the effect-row rule E0904.
- The compiler elaborates each impl method to a plain function. Its `@requires` is the trait's. Its
  `@ensures` is the trait's ANDed with the impl's own. Its `@verify` is the effective policy. From
  there, verification and runtime checks follow the ordinary function path.
- An impl method may not write `@requires`, even when the predicate equals the trait's. This is
  `TraitImplAddsPrecondition`, E0912. The fixes are: move the predicate to the trait method, give
  the parameter a refinement type in the trait's signature, or use a free function. When the
  predicate is already inherited, a `note:` says so on the same error.
- An impl may add `@ensures`. An impl `@ensures` that restates an inherited predicate gets
  `RestatedInheritedEnsures`, W0900.
- A call through a bound checks the trait's `@requires` and assumes only the trait's `@ensures`.
  Monomorphization never brings an impl contract into a generic caller. A call that names the
  concrete type checks the same `@requires` and assumes the trait's and the impl's `@ensures`.
- Inherited predicates bind by position, by capture-avoiding substitution. `self` binds to position
  0 whatever the impl calls it. The compiler adds no parameter-name check, and no W0850 lint exists.
  Every surface that shows an inherited predicate prints both names, for example "trait param `n`
  (impl param `count`)". This includes diagnostics, hover, `blink query` and V0002 counterexamples.
- A trait `@verify` takes `fallback: "runtime"` only. It is the default for every impl body of that
  method with no `@verify` of its own. `"trust"` on a trait method declaration is
  `TrustOnTraitMethod`, E0913.
- An impl's own `@verify` (`"trust"` included) replaces the trait default as a whole. The two never
  merge. The default resolves at elaboration, before verification, and also covers an open default
  body and each override of it.
- A fallback applies only to an Unknown outcome. A Proven contract costs nothing. An inherited
  `"runtime"` check follows the same build-mode rule as any runtime fallback, and the verification
  report lists the inherited runtime checks for each impl.
- If no `@verify` applies and the outcome is Unknown, the error is V0003 at the impl method. The
  message says the contract comes from the trait and names the impl method as the place for
  `@verify`.
- A trait default body is verified once against the trait's contract, generically over `Self`. An
  override inherits the same contract and must discharge it in its own body. A `final` default
  fixes both its body and its contract.
- A predicate may use the method's parameters, `self`, `result`, `old(...)`, and methods of the
  trait, its supertraits and the bounds on its type parameters. The purity rules are those of
  function contracts (E1301, E1302).
- A subtrait may not redeclare a supertrait method to add or change its contract (E0733).
- A trait method that has a contract may not be implemented directly by an `@ffi` function. A safe
  wrapper implements it and carries the contract (E0803).
- A contract predicate of function `f` may not call `f`, directly or through a cycle. This is one
  general rule for all function contracts, not trait-only text. It is `RecursiveContractPredicate`,
  E1309, and the diagnostic prints the cycle. The rule applies to trait methods the same way.
- The spec has no formatter text for contracts: `blink fmt` already never changes semantics.
- Migration is a note, not a rule. An existing impl `@requires` is now E0912. Move the predicate to
  the trait method, give the parameter a refinement type in the trait's signature, or call a free
  function.
