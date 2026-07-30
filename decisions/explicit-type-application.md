[< All Decisions](../DECISIONS.md)

# Explicit Type Application and the Undeterminable Type Parameter — Design Rationale

Resolves br `8w0yj9`. The ticket asked for a declaration-site `error` when a generic type
parameter cannot be determined from any parameter or the return type, on the premise that
"Blink has no turbofish." Triage found that premise to be one of four places where the spec
contradicts itself, so the deliberation started from the contradictions rather than the ask.

Governs: `sections/03_types.md` §3.1 *Diagnostic Discipline*, §3.4 *Explicit Type Application*,
§3.4 *Under-Determined Types*, §3.6 *Polymorphic Trait Implementations*; `ERROR_CATALOG.md`
(E0301, E0909, W0604).

Amends `decisions/under-determined-types.md` (8vcj2c) on the report site of E0301 — see V1-c.

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in
independent-proposal → debate → vote rounds. Phase B ran (three distinct options on V1 after
dedupe, plus eight flagged variations). Phase D ran on V3 only.

#### Phase A — Independent proposals

- **Systems:** *"The ticket treats 'T mentioned by nothing' as one property. From the codegen seat
  it is **three** distinct properties, and the ticket's two exhibits sit in different tiers"* —
  arg-determined (T in a parameter type), context-determined (T in the return type or a bound
  only), signature-absent (nowhere in params or return). *"All ~18 bracket uses the ticket cites
  are **tier B**, not tier C. … That is not 18 rogue examples against §3; it is §3 failing to
  write down a mechanism the rest of the spec uses consistently."* On the hazard: *"Tier C is not
  'harmless dead weight'"* —

  ```blink
  fn parse_or_zero[T: From[Str]]() -> Int {
      T.from("0").to_int()
  }
  ```

  *"`parse_or_zero[Int]()` and `parse_or_zero[Duration]()` have **identical** types — `() -> Int`"*
  — two bodies, one C symbol under separate compilation.

- **Web/Scripting:** *"Bracketed type application at a call site is part of Blink, and §3 must
  define it. Answer YES."* One production: `Path [ TypeArgs ] ( Args )`. *"It is the single most
  transferable shape in Blink's surface. `Deserialize<Forecast>` in C#, `decodeFromString<Forecast>`
  in Kotlin, `from_str::<Forecast>` in Rust, `parse<Forecast>(body)` in TS … A dev arriving from any
  of those reads `json.decode[Forecast](body)` in under five seconds with zero doc lookups."* And
  against annotation-only: *"The annotation-only alternative does not cover the 90% shape — it
  covers the 60% shape."*

  ```blink
  let city = json.decode[Forecast](body)?.city          // postfix — no annotation site
  let ids = bodies.map(fn(b) { json.decode[Row](b) })    // closure return — no annotation site
  ```

- **PLT:** *"A generic declaration introduces a type scheme σ = ∀T̄. τ. Two independent properties
  are in play: **(P1) Well-formedness of the scheme.** … Type-theoretically, a binder need not
  occur in the body. `∀a. Int` is well-formed and inhabited — `Λa. 3` is its witness. There is no
  soundness content in requiring an occurrence. **(P2) Solvability of an instantiation.** … A free
  α at the end of its inference region is E0301."* The headline criterion:

  > *"A declaration-site **error** is justified exactly when the binder admits no witness at any
  > conceivable use site. If some well-typed use exists, rejecting the declaration rejects a
  > program that has a witness, and that is the one thing a type system may not do for the sake of
  > tidiness."*

  Applied, this yields a trichotomy across `fn f[T]` (warning — `f[Int]()` is a witness),
  `type X[T]` (warning), and `impl[T]` (error — no supply site exists).

- **DevOps/Tooling:** T1, offered as a gate on every other proposal: *"whatever this panel decides
  must be decidable in the phases `blink check` runs. … **no rule adopted here may be enforced only
  in codegen.** … A rule that can only be enforced after monomorphization is a rule that does not
  exist as far as the editor is concerned: the user sees a green buffer, `blink check` prints `ok`,
  and the failure arrives as a `cc` error or an ICE from `blink build`."* On Q1: *"**Answer to Q1:
  YES.** §3 must define it. `03_types.md:1148`'s 'The single repair is a type annotation' is wrong
  and must be amended."*

- **AI/ML:** measurement first. *"The ticket says ~18 in §3.x and §7. It is worse than that: **eight
  files, seven top-level sections**"* — 21 hits in §7, 7 in §4, 5 each in §3b and §3, 4 each in §2
  and §3c, 2 each in §5 and §6 — *"and three families the ticket does not name — `channel.new[Int]
  (buffer: 10)` … `json.parse[Weather](response.body)` … `db.query[Str](…)`. Three of the hits are
  not example call sites at all: a declared signature, table rows, and — the one that decides this
  for me — a diagnostic's own repair text, `07_trust_modules_metadata.md:364`."* And: *"the
  LLM-facing corpus is not `sections/` — it is `blink llms --full`"*, which carries the form too,
  including a changelog entry describing it as *"a supported, fixed feature."* *"Against that: **one
  sentence**, `03_types.md:1148`."* `rg -i turbofish` over the spec: zero hits.

- **Minimalism:** *"The lead asked me to say precisely which option is the subtraction. Here is the
  accounting, because it inverts the ticket's implicit direction. **Three of the four things in
  dispute are already in the language.**"* Call-site brackets (never voted, but attested in a
  declared signature and normative FFI bodies); a type parameter named by no field
  (`type Template[C]`, 4-1); a type parameter named by no parameter (`fn foo[T: From[Str]](s: Str)
  -> T`, 5-0). *"**Q1 = YES** is a *ratification*: §3.4 gains two sentences, 18 spec sites become
  valid, zero sites are deleted, and the language gains no concept it did not already use. **Q1 =
  NO** is the large change … NO also strands §2.6: the 5-0 vote reserved `[]` for type-level
  meaning *and foreclosed an index operator to pay for it*. Declining Q1 leaves that reservation
  half-spent — we bought the syntactic slot and then declined to use it. That is worse minimalism
  than using it. **A new declaration-site error** is the only genuine addition on the table."*

#### Phase B — Debate highlights

**Systems retracts its own headline hazard as an argument.** *"I framed `parse_or_zero[T:
From[Str]]() -> Int` as an argument against erasure. web and min both exclude the body (and web
excludes bounds) from vacuity, so both already treat that function as non-vacuous and both already
require `parse_or_zero[Int]()`. The ODR collapse I described cannot arise under (c)-as-stated. **I
withdraw it as an argument against (c)** … it is not a stick to beat web and min with, and I should
not have swung it as one."*

**Systems supplies the split that dissolved the apparent V2/V3 disagreement.** *"The apparent
V2/V3 disagreements are an artifact of one word ('use') doing two jobs. There are **two predicates
over a declared tparam**, and every panelist's sentence is true of one and false of the other:
`supplies(T)` — can any call site determine T? True iff T occurs in a parameter type or the return
type. **Bounds: no. Body: no.** Signature-local; governs the ERROR."* The other, `inert(T)`,
governs the lint. Then: *"**On V1 itself: I concede (a) and move to (b), conditionally.**"*

**Web abandons its own (c).** *"I abandoned (c) in round 1 because it made bracket-necessity
unpredictable from the signature, and predictability is the thing my constituency actually pays
for."*

**DevOps withdraws R5 on a pre-committed fallback.** *"I arrived here by my own pre-committed
fallback after withdrawing R5, not by counting."*

**Minimalism withdraws its own R5-b variant**, leaving the bound-inclusive declaration-site error
with no author.

#### Phase C — Final vote

- **V1: how are a generic function's type parameters supplied?** (6-0 for (b) — brackets are
  ratified, no erasure, every binder stays in the monomorphization key, and brackets are mandatory
  at every call of a binder the signature does not supply)
  - **Systems:** (b) — *"Every binder stays in the mono key, so two instantiations are two symbols
    and the ODR collapse is unreachable by construction rather than by a predicate drawn correctly
    forever. It adds zero concepts and zero code slots, and the caller's obligation is derivable
    from the signature alone — no hover, `blink doc`, or cross-package call site ever needs the
    callee's body."*
    *Concern:* *"(b) makes `f()` an error where it silently compiled, and on a genuinely pointless
    binder it taxes every call site with a meaningless `[Int]` unless V1-b actually steers people to
    the declaration."*
  - **Web/Scripting:** (b) — *"One code for one user-facing concept: 'the compiler needs a type it
    cannot work out, tell it here.' A second slot buys message quality that (b) gets from
    mint-provenance templates, at the cost of a doc page and a question whose only honest answer is
    which phase noticed."*
    *Concern:* *"(b)'s default message family must not read 'inference might have succeeded with
    more context' on the shape where no context ever could, or users will hunt for an annotation
    that does not exist."*
  - **PLT:** (b) — the P1/P2 split with the witness criterion above; a `fn` binder always has a
    witness, so the declaration may not be rejected.
  - **DevOps:** (b) — *"(b) is the only option whose user-facing rule fits in one sentence with no
    new vocabulary, which is what determines whether hover, `blink doc` and `blink query --fn` can
    explain a call's obligation from the signature alone. Its one real defect was a contradictory
    repair pair, and that is a help-ordering bug fixed by V1-b rather than a reason to erase
    anything."*
    *Concern:* *"(b) makes E0301 the code users meet in two structurally different situations, so if
    the mint-provenance message selector is ever dropped as an implementation detail, the wrong
    template ('inference left this undetermined') ships as a lie on the `¬supplies` call."*
  - **AI/ML:** (b) — on the attestation asymmetry: eight files against one sentence, and the form
    already appears inside a diagnostic's own prescribed repair.
  - **Minimalism:** (b) — YES on Q1 is the ratification, not the addition.

- **V1-b: is the ordering of the two repairs normative rather than presentational?** (6-0 ADOPT)
  - **Systems:** ADOPT — *"Under (b) the lint and the error both fire on the ticket's exhibit, and
    only the deletion discharges both; ordering it first is what stops the path of least resistance
    from being 'type `[Int]` and leave the useless binder in a file you may not own.'"*
    *Concern:* *"'removable by the lint' is now load-bearing in an error's fix ordering, so a future
    widening of the lint's gate silently changes which repair tooling offers first."*
  - **Web/Scripting:** ADOPT — *"it is the difference between a language whose path of least
    resistance is `f[Int]()`-and-move-on and one that points at the actual defect."*
    *Concern:* *"'ordered first' is only as good as the tooling that honors it; if the LSP surfaces
    the bracket fix by proximity to the cursor, the rule is defeated silently."*
  - **DevOps:** ADOPT — *"in an editor this is not message advice, it is which `codeAction` a
    keystroke applies unread; an LSP that one-click-inserts `[Int]` at every call site of a mistyped
    signature launders the defect into working code."*

- **V1-c: E0301 is reported where its repair attaches, not always at a binding** (6-0 ADOPT — an
  explicit amendment to 8vcj2c)
  - **Systems:** ADOPT — *"My V1 concession was conditional on this. Without it a `¬supplies` call
    in statement position has no binding to report at and falls through to I0001 — an ICE where a
    plain user error belongs, which also violates T1."*
  - **Web/Scripting:** ADOPT — *"Defining the site by where the fix attaches is also the only
    phrasing that a quick-fix implementation and a caret can both key on."*
    *Concern:* *"none material; the risk is that it is treated as editorial and dropped from §3
    during the write-up."*
  - **DevOps:** ADOPT — *"without it, `tag()` in statement position has no binding to report at and
    falls through to I0001 — an ICE standing where a user error belongs, which is my T1 violated by
    the panel's own preferred outcome. Two panelists made their V1 concession conditional on it, so
    it is load-bearing, not hygiene."*
  - *All three filed the same concern:* a future diagnostic with two equally applicable repairs at
    two sites has no stated tie-break for the primary span.

- **R5-a: a declaration-site error for a bound-exclusive undeterminable binder** (does not land; 4
  NO, 2 conditional-YES whose antecedent — V1 option (c) / R4 — lost 6-0)

- **R5-b: the bound-inclusive variant** (6-0 NO; withdrawn by its own author)

- **V2: is a bound an occurrence?** (6-0 YES — no warning)
  - **PLT:** *"`σ̄ ⊨ bounds(T̄)` is a premise of the instantiation rule, so a bound partitions
    instantiations into well-typed and ill-typed. That makes a bounded binder observable from the
    signature alone, with no reference to the body and no dependence on whether we monomorphize.
    Deleting the bound changes which programs are well-typed, so the deletion the lint prescribes is
    not meaning-preserving."*
    *Concern:* *"a decorative unused bound now permanently escapes the lint, so `[T: Show]` becomes
    the cheap way to silence W0604."*

  **Recorded correction to this ballot's stated derivation.** The outcome stands 6-0, but the
  justification as filed is incomplete, and Phase D established why. Read strictly, deleting *any*
  binder changes which programs are well-typed, so "the deletion changes which programs are
  well-typed" cannot by itself separate the bound case from the naked one. The derivation that works
  is the erasure-modulo construction PLT supplied in Phase D: the comparison is a bijection on
  well-typed programs *modulo the mechanical erasure of type-argument lists at call sites*. Under
  that comparison `fn assert_serializable[T: Serialize]() {}` fails — the erased
  `assert_serializable()` accepts what `assert_serializable[NotSerializable]()` rejected — and
  `fn tag[T]() -> Int { 1 }` passes. The spec does not rely on this: the normative gate is V3's
  occurrence clause, which derives V2 syntactically with no construction at all. This paragraph
  exists so `decisions/` does not record a derivation that fails on its own terms.

- **V3: which sentence is the normative gate for W0604?** (Phase C 4-1-1 → Phase D 6-0: min's
  occurrence clause as the normative gate, web's fix-safety sentence as normative rationale beside
  it. See Phase D.)
  - **PLT** (Phase C, the sole first-round vote for min's enumeration): *"all three formulations are
    extensionally identical … min's is the only one that states a property rather than a procedure:
    web's is defined by simulating an edit, which is what produced the 'unchanged meaning' ambiguity
    I had to disambiguate, and mine enumerates positions, which needs maintaining as the language
    grows an effect row. 'Occurs nowhere in the declaration or its body' needs no list and no
    interpretation. I withdraw my own phrasing in its favor."*
    *Concern:* *"a purely syntactic occurrence test means a binder mentioned only in unreachable
    code suppresses the lint."*

- **V4: may a type-argument list appear on a struct-literal head?** (5-1, AI/ML dissent — YES)
  - **AI/ML:** *(dissent)* NO — *"A type's binder is always reachable from an annotation, so no
    repair is missing; permitting brackets as well puts two spellings at one site and creates the
    choose-a-form decision at every construction, which is the exact ground Principle 2 rejected
    optional keyword arguments on. Two forms in the corpus means a model picks by frequency rather
    than by rule."*
    *Concern:* *"the receiver-position gap is real and a model that meets it will emit `Registry
    [User] { … }.lookup(3)` and get a parse error."*

- **V5: does a redundant explicit type-argument list carry a diagnostic?** (6-0 — no diagnostic of
  any class)
  - **AI/ML:** *"plt's non-monotonicity argument is decisive and the redundant form is
    permitted-and-harmless exactly as `let x: Int = 1` is; a warning here would make a later
    annotation elsewhere retroactively noisy on unchanged code."*

- **V6: does a `where`-clause bound rescue an impl binder?** (6-0 — no; narrow, E0909 still fires)
  - **PLT:** *"Impl binders are solved only by matching the header against a resolution goal; a bound
    is a premise discharged after matching, so it constrains `T` without determining it, and
    widening would require picking an arbitrary instance."*
    *Concern:* *"a bound being the one position that does not rescue a binder reads as inconsistent
    with V2 unless the message states that impls have no supply site."* (The spec answers this
    concern in §3.6.)

- **V7: E0909's shipped text, name, and placement** ((i) 6-0 delete; (ii) 5-1 keep the name; (iii)
  6-0 unchanged)
  - **AI/ML:** (i) *"**YES** — delete the sentence at `src/diagnostics.bl:1067`. It is the false
    generalization this ticket was filed on, it is shipped user-visible text, and shipped diagnostic
    text is training data."* (ii) *(dissent)* *"**RENAME** → `ImplBinderUndeterminable`. The defect
    is not in the prose alone: a name containing 'unused' teaches the generalization the panel has
    now rejected 6/6, and names propagate further than the prose that qualifies them."* (iii)
    *"**Confirmed — E0909 does not move.** The number is the stable searchable identifier, which is
    precisely what makes the rename cheap."*

- **V8: which principle is normative?** (5-1 for DevOps's sentence — *"Never emit a diagnostic whose
  prescribed repair does not exist."*)
  - **Systems:** *(dissent on routing, not substance)* *"§3.4 normative: plt/min's 'reject at a
    declaration only when no use site could ever repair it.' §3.6 corollary: that sentence applied
    to impl binders, which is E0909's justification. `ERROR_CATALOG.md` preamble: devops's 'never
    emit a diagnostic whose prescribed repair does not exist' — a diagnostics-authoring standard,
    not a typing rule, binding the population that produced this ticket. … Four sentences, three
    documents, nothing dropped and nothing competing."*
    *Concern:* *"the mono-key invariant sitting only in `decisions/` is the one a future implementer
    tempted to widen erasure most needs to hit, and rationale files are read less often than spec
    sections."* (The write-up honors the routing dissent with a cross-reference in
    `ERROR_CATALOG.md`'s Conventions rather than a duplicate, and puts the mono-key invariant in
    §3.4 rather than only here.)

- **V9: T1, and confluence** ((i) 6-0 ADOPT T1; (ii) 6-0 ADOPT confluence with PLT's rider)
  - **Systems:** *"**(i) ADOPT T1.** It is precisely my position that I0001 is a fail-closed
    backstop and never a rule; a check that bites only at codegen is invisible to `blink check`, to
    the LSP, and to every agent loop that gates on `check`. **(ii) The confluence replacement, with
    plt's rider** that the converging repair must be the one the diagnostic names first."*
    *Concern:* *"confluence is a property of a diagnostic *set*, so it is only as good as whoever
    checks a new diagnostic against every existing one that can fire on the same line — nothing in
    the toolchain verifies it."*

- **V10: code allocation** (6-0 CONFIRM — E0301 reused, no new error code; `W0604
  UnusedTypeParamBinder` newly allocated; E0909 keeps its number)

#### Phase D — Round 2 (V3 only)

Triggered by V3's 4-1-1. **Result: 6-0 for min's occurrence clause as the normative gate, with
web's fix-safety sentence adopted as normative rationale beside it — PLT's assignment.** All four
fix-safety voters moved, and each moved off a reason it had itself authored.

**PLT supplies the two load-bearing facts, one against its own Phase C text.**

> *"**1. The 'list of positions to keep in sync' objection is aimed at the wrong sentence.** Four
> voters gave that as the reason to prefer fix-safety, and it is a correct objection to *my*
> phrasing … min's is not a list. It is one quantifier over the whole declaration: *T occurs nowhere
> in the declaration or its body.* A new syntactic position is covered the moment it exists, because
> 'anywhere' already ranges over it … My own Phase C concern about maintaining a list was mis-aimed
> at min's sentence for the same reason; I withdraw it.*
>
> ***2. Reading 2 does not survive contact, and reading 2 is mine.** I introduced it to rescue web's
> phrasing on the V2 case, and it fails in the other direction. Read strictly, deleting *any* binder
> changes which programs are well-typed: delete `[T]` from `fn f[T]() -> Int { 1 }` and `f[Int]()`
> becomes an arity error, so the set of well-typed programs changes and the gate never warns on
> anything. To get the intended answer you need the deletion to be a bijection on well-typed
> programs *modulo the mechanical erasure of type-argument lists at call sites* … That is the
> correct pinning, and stating it in normative prose is more machinery than the sentence it
> replaces."*

**DevOps loses its primary reason and states the generalization that decided the assignment.**

> *"plt's item 1 refutes the reason I gave. … Four of us gave that reason and it does not separate
> the finalists. It was my primary reason, so I lose it. … My own pin dodged the bijection by asking
> whether 'no two admissible instantiations are distinguishable' — but an implementation can only
> check that by scanning for occurrences, so my clause **reduces to min's clause** at the point of
> implementation. So does sys's (ii). Every correct pin lands on min's sentence; the pins differ
> only in how much prose they spend getting there."*

And on why the tie-break must favor the decidable sentence:

> *"the failure direction is not symmetric: if the gate is min's clause and the rationale is loosely
> worded, the lint is still correct; if the gate is the counterfactual and the pin is trimmed in
> editing, W0604 fires on `fn assert_serializable[T: Serialize]() {}` with a `help:` that compiles
> cleanly and deletes a working compile-time assertion, silently reversing a 6-0 V2. That is a
> well-formed diagnostic with an applicable fix, so no test catches it, and it is my now-normative
> V8 sentence violated by the write-up of the same decision that adopted it."*

**Systems moves to fix-safety and back, conceding that its own pin has the same hole.**

> *"My move to fix-safety rested on exactly one claim from my seat … plt's item 1 defeats that by
> pointing out I was pricing the wrong candidate. min's clause is not my clause. … Bare occurrence
> **cannot be drawn wrong**, because any mention is an occurrence; there is nothing to classify. …
> Check that against the pin I supplied and it fails there identically — my clause (ii), 'no type
> argument's well-typedness at a call changes,' is not even well-defined after the deletion, because
> the argument it quantifies over no longer occupies a slot. … When the precise form of a property is
> heavier than the property it was meant to replace, the heavier form is the rationale and the
> lighter one is the gate. That is plt's assignment, and my repaired pin is now evidence **for** it
> rather than for the thing I voted."*

> *Concern (filed and standing):* *"A bare-occurrence gate under-fires: a binder mentioned only in a
> dead branch, or in a body form the front end discards, suppresses W0604 forever. Under-firing is
> the safe direction … but V1(b) was voted on the premise that W0604 is what stops the corpus
> filling with meaningless `[Int]`, and a gate deliberately biased toward silence is a weaker
> guarantee than that premise assumed."*

**Web withdraws its own pinned sentence, on its own initiative, and confirms the citation against
itself.**

> *"plt's item 2 is correct and it breaks my pin, not just a reading of it. Under V1(b), deleting
> `[T]` from `fn f[T]() -> Int { 1 }` makes `f[Int]()` an arity error and `f()` well-typed where it
> previously was not — so the set of well-typed programs changes, and my sentence warns on
> *nothing*. That is the ticket's own exhibit failing the gate I wrote."*
>
> *"aiml's citation of my round-1 text is accurate: I did apply the gate to `fn assert_serializable
> [T: Serialize]() {}` and conclude it warns. That was reading 1, and it is exactly the wrong answer
> — I voted reading 2 in Phase C precisely because plt showed me that. It is also the cleanest
> evidence on the record that the unpinned phrase misleads its own author, which is a reason not to
> make it operative."*

**AI/ML corrects two of its own Phase C claims.**

> *"First, sys is right and I was wrong to call the two extensionally equivalent … the proof is in
> web's own round-1 text … That is the phrase's author reaching reading 1 on the one case V2 has now
> settled 6-0 the other way — the ambiguity demonstrated rather than hypothesized. Second, I voted
> fix-safety for generativity and described min's as 'a list to keep in sync'; that description is
> wrong. … it is one syntactic occurrence test over two regions, and it answers the `Ptr[T]` case I
> used as my generativity exhibit with no amendment, exactly as fix-safety does."*

**Minimalism withdraws its Phase C vote for the third time on a falsified premise, and records the
one case that goes against it.**

> *"**3. The advantage I cast my Phase C vote on has evaporated.** I voted for web's phrasing for
> one stated reason: my formulation was a list of syntactic positions that must be kept in sync as
> the language grows. plt's compression removes the list … My reason for preferring web's was true
> of my Phase A wording and false of the form actually on the ballot."*
>
> *"sys's hazard survives in one residual shape only: a body that **depends on `T` without naming
> it**. There, deletion does break compilation and fix-safety decides correctly while occurrence
> does not. I recorded that against myself before the digest and I hold it — it is the reason web's
> sentence belongs in the document at all, and the criterion a future author would use to amend the
> clause if such a position is ever added."*

> *"**2. That is why the label is not cosmetic.** … the equality is false as written — plt's arity
> case is a counterexample to it — so the two sentences can disagree, and we have two demonstrations
> that they do. Whichever sentence is labeled normative is the tie-break when they disagree."*

> *"Fix-safety is true as *purpose* and false as *predicate* — it is a theorem the gate satisfies,
> and rationale is the right home for a theorem, because nobody conforms to rationale and its
> imprecision therefore costs nothing."*

*Moderator note on the count:* four peers crossed on this line before the two remaining fix-safety
voters were asked to reconsider. Their specific rebuttals were relayed verbatim; the tally was
withheld, because telling two holdouts that four peers have just crossed the aisle is social
pressure, not information. Both restated on the arguments, and both stated independently that they
did not need the count.

### AI-First Review

5/5 pass.

1. **Learnability — pass.** The decision writes down a form the corpus was already teaching in eight
   spec files and in `blink llms --full`, including inside a diagnostic's own `help:` text. Before it,
   a model learning from the spec had ~50 attestations of a mechanism §3 explicitly denied; the
   ambiguity is what failed learnability, and ratification removes it.
2. **Consistency — pass.** Brackets already mean "type-level application" everywhere in the language
   (the 5-0 §2.6 vote reserved the slot and foreclosed an index operator to pay for it); this uses the
   slot rather than leaving it half-spent. `W0604` joins the existing unused-thing family
   (W0600–W0603) at the granularity where that family already sits. The one asymmetry — E0909 is an
   error where W0604 is a warning — is derived from a stated criterion (no supply site vs. a supply
   site) rather than asserted, and §3.6 states the derivation.
3. **Generability — pass.** *Supplied by the signature* is decidable from the signature alone. A model
   with the callee's signature — which is what `blink query --fn`, hover, and `blink doc` all return —
   can decide whether brackets are required without the body and without the call context. There is no
   case where it must guess.
4. **Debuggability — pass.** This is the criterion the decision spends the most on. E0301 now reports
   where its repair attaches, so the statement-position call gets a user error instead of an I0001 ICE;
   the two repairs have a normative order, so a one-click fixer cannot launder a bad signature into
   working code; and §3.1's three rules make "the prescribed repair must exist" and "co-firing
   diagnostics must converge" checkable properties of every future diagnostic rather than authoring
   taste.
5. **Token efficiency — pass.** Brackets are mandatory only where nothing else can supply the type, and
   redundant lists are permitted but never required, so the common inferable call keeps its current
   cost. `json.decode[Forecast](body)?.city` is strictly cheaper than the annotation-only repair, which
   forces a named temporary purely to have somewhere to write the type.

### Final Spec

```blink
// Explicit type application — ratified. Mandatory when the signature does not supply T.
fn tag[T]() -> Int { 1 }

let a = tag[Int]()          // ok — T supplied at the call
let b = tag()               // error[CannotInferType] E0301, reported at the type-argument position
tag[Int]()                  // ok in statement position too
tag()                       // E0301 here as well — not an ICE

// A type parameter supplied by the signature needs no brackets, but may carry them.
fn first[T](xs: List[T]) -> T? { xs.get(0) }
let x = first(nums)         // ok — T unified from the argument
let y = first[Int](nums)    // ok — redundant, and carries no diagnostic

// One discipline for every type-argument list, including a struct-literal head.
let r = Registry[User] { entries: [] }

// A bound is an occurrence — this is a compile-time assertion, not dead weight.
fn assert_serializable[T: Serialize]() {}          // no W0604

// The binder occurs nowhere in the declaration or its body.
fn tag2[T]() -> Int { 1 }                          // W0604 UnusedTypeParamBinder

// Impl binders have no supply site, so the declaration is rejected outright.
impl[T] Show for IntBox { }                        // E0909 ImplBinderUnused
impl[T] Show for IntBox where T: Display { }       // E0909 — a bound does not rescue an impl binder
```

Locked design points:

- **Bracketed type application at a call site is part of Blink** and is defined in §3.4 — a third
  supply mechanism alongside inference at a construction site and a type annotation on the binding.
- **No erasure.** Every type parameter a declaration binds belongs to that declaration's
  monomorphization key: never dropped, never defaulted, never collapsed onto another instantiation's
  symbol.
- **Brackets are mandatory** at every call of a type parameter the signature does not supply. A type
  parameter is *supplied by the signature* iff it occurs in a parameter type or in the return type —
  decidable from the signature alone, with no call site and no function body consulted.
- **E0301 is reported where its repair attaches.** For a binder the signature does not supply, that
  is the call's type-argument position, including when the call stands alone as a statement. This
  amends 8vcj2c's "the single repair is a type annotation."
- **Two repairs, in a fixed order, and the order is normative** — supply the type argument, or, when
  the binder is removable, delete the binder. The deletion is named first when it applies.
- **One discipline for all type-argument lists**: all-or-none, exact arity, bounds checked, permitted
  on a struct-literal head.
- **A redundant type-argument list carries no diagnostic of any class** — a warning here would be
  non-monotonic.
- **Phantom type parameters are legal in user code**, and instantiations at distinct type arguments
  are distinct types.
- **`W0604 UnusedTypeParamBinder`** fires iff the type parameter **occurs nowhere in the declaration
  or its body**. A bound is an occurrence. The fix-safety property — W0604 fires exactly when
  deleting the binder is a safe edit — ships as normative rationale, and is the criterion for
  amending the clause if a future type position ever lets a body depend on `T` without naming it.
- **An impl binder must occur in the impl header's type positions**; a `where`-clause bound does not
  rescue it. §3.6 states the reconciliation: a declaration is rejected outright only when no use
  site could ever repair it; where a use site can, the diagnostic goes to the use site and the
  declaration gets a lint.
- **Diagnostic Discipline (§3.1, normative)**: never emit a diagnostic whose prescribed repair does
  not exist; no rule is enforced only at codegen (I0001 exists to catch violations of that rule, not
  to serve as one); diagnostics that can fire on the same construct must be confluent, and the
  converging repair must be the one named first.
