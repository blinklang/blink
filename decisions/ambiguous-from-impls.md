[< All Decisions](../DECISIONS.md)

# A Generic Qualifier That Matches Two Impls — Design Rationale

The spec let one generic receiver carry several `From` impls with binders. It gave no rule for a call such as
`Box.from([[1, 2], [3]])` that matches two of them. The two impls below do not overlap (`List[T]` and `List[List[T]]`
fail the occurs check at one `T`), but the bare qualifier call matches both:

```blink
type Box[T] { v: List[T] }

impl[T] From[List[T]] for Box[T] { ... }
impl[T] From[List[List[T]]] for Box[T] { ... }

let a = Box.from([[1, 2], [3]])   // Box[List[Int]] by the first impl, Box[Int] by the second
```

The question was whether refusal is the rule, or whether one impl wins (the most specific source, as in
specialization, which Blink otherwise rejects).

## Summary

| Q | Question | Result | Vote |
|---|---|---|---|
| Q1 | Refusal or a pick rule | A: refuse with E0301 at the call; no impl wins by specificity | 6-0 |
| Q2 | Does a later use pick the impl? | A: no. Selection is complete at the call; the spec states the contrast with the later use that fixes a binding (§3.4) | 5-1 (PLT dissent: B) |
| Q3 | What the spec states about the diagnostic | A: the content (each candidate with the type it gives, a note, the help; `x.into()` points at `.into()` and names the `From` impls), not the exact wording | 5-1 (Minimalism dissent: B) |
| Q4 | When the help names the impl-qualified head | B: only when the call has no binding to annotate | 5-1 (PLT dissent: A) |
| Q5 | Where the rule lives | A: §3c.2, with a pointer from §3.4 *Under-Determined Types* | 5-1 (PLT dissent: B) |
| Q6 | How the spec mentions the compiler-provided reflexive impl | No clause; two examples show it as a candidate (BDFL ruling) | Phase C clause 4-2; Phase D: A1 3, A2 2, B 1; A1 against A2 3-3 |

Points all six seats stated, not balloted: refuse; E0301 at the call; the rule covers every trait method called
through a generic type's qualifier, and `x.into()`; the expected type and the impl-qualified head pick an impl;
`Box.from[Int](...)` and `Box[Int].from(...)` stay errors, and "the explicit type list" is not in the rule;
the first sentence of the 03_types.md *Under-Determined Types* paragraph is not cited for the later-use case, because
the same section says a later use does fix a binding's type; the reflexive
`impl From[T] for T` joins the candidate set under the same rule and adds an ambiguity only when the argument type
unifies with the receiver, and the diagnostic prints it like any other candidate; the help that names the
impl-qualified head appears only once that head parses.

### Compiler behavior before the decision

The moderator ran these probes with the gen1 compiler. All declare the `Box` type and the two impls above.

- p1 `let a = Box.from([[1, 2], [3]])` gives `error[CannotInferType]` with the message "`Box.from` on List[List[Int]] matches more than one impl", which lists `impl From[List[T]] for Box[T]` and `impl From[List[List[T]]] for Box[T]`. The help reads "annotate the binding that receives the result with the type it should have".
- p2 `let a: Box[Int] = Box.from(...)` and `let b: Box[List[Int]] = Box.from(...)` both compile.
- p3 `Box.from([1, 2])` (one match) compiles.
- p6 `take(Box.from([[1, 2], [3]]))` with `take(b: Box[Int])` compiles: the parameter type picks.
- p8 `let a: Box[Int] = [[1, 2], [3]].into()` compiles.
- p9 `let a = Box.from(...)` then `let n: Int = a.v.get(0).unwrap()` gives the same E0301 at the `Box.from` call. A later use does not pick.
- p7 `Box.from[Int](...)` gives the same E0301. p10 `Box[Int].from(xs)` gives `CallSiteTypeArgs`.
- p4, p5: the impl-qualified head `(From[X] for Box[Int]).from(...)` does not parse yet ("expected ), got for"). 03c *Impl-Qualified Calls* specifies it; a separate ticket tracks it.

### Reading gaps

- The moderator brief quoted only the first sentence of the 03_types.md *Under-Determined Types* paragraph and left out "Later use still determines the type". Three seats cited that paragraph for the later-use case in Phase A. The Phase B digest corrected the brief, and all six seats withdrew the citation.
- Phase A files ran over the 500-word limit (579 to 693 words). No seat ran the probes in Phase A. sys read only the brief. min read only 03_types.md near line 2690 and 03c near line 274.
- plt's Phase B reading line lists the six Phase A files and no Phase B digest, but its reply answers the digest's correction.
- web (Phase C) says it only skimmed the other seats' Phase A and B1 files and did not re-check the later-use paragraph. Its reading line claims more than it read.
- Phase D ran on Q6 only.
- The writer found that the gen1 compiler does not treat the reflexive impl as a candidate of a generic qualifier call (`Box.from(other_box)` gives `NoConversionImpl`, and a user impl `From[Box[List[T]]] for Box[T]` is picked with no error), and that `let a = [[1, 2], [3]].into()` with no annotation checks. The ruling is unchanged; these are implementation gaps.

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated
in independent-proposal → debate → vote rounds.

#### Phase A — Independent proposals

Each seat's opening position and rule, excerpted with attribution. All six proposed refusal. The full files ran
579 to 693 words each.

- **Systems** (sys-1: "Refuse. The expected type at the call picks; nothing else does. (All trait methods, not From only.)"):
  > A call `T.m(args)` through a generic type's qualifier names a set of candidate impls: every impl of the trait whose head unifies with the argument types, with the receiver binders left free. If the set has one member, that impl runs. If it has more than one, the expected type of the call expression, known at the call site, must reduce the set to one. If it does not, the compiler reports E0301 at the call. No impl wins by specificity. This follows *No Impl Overlap* (03_types.md:4995): Blink has no "more specific wins", and the argument for it ("Each (Trait, Type) pair has exactly one impl") applies to a bare qualifier as well. The rule covers every trait method called through a qualifier, and `x.into()`, because `Into` is derived from `From`. It is not a `From` special case.

  > If a distant `let n: Int = a.v.get(0)` chooses which body runs, then editing line 40 changes the code generated at line 3 and its cost. Local selection keeps the monomorphized call target readable from the call site and its expected type.

- **Web/Scripting** (web-1: "Refuse. Ambiguity is E0301. Only fixed types pick. Applies to every trait method called through a generic qualifier."):
  > A call `Type.m(args)` resolves its impl from the types known at that call. If the receiver's binders are not fixed and more than one impl head matches, the call is under-determined: E0301 `CannotInferType`, at the call. No impl wins by specificity. This is the existing *No Impl Overlap* rule (03_types.md:4995) applied at one more place. It is not a new rule.

  > Listing the result type of each impl is what makes the error fixable in 5 seconds. The current message names the impls but not the types they give.

- **PLT** (plt-1: "Refusal is the rule. Ambiguity is E0301 at the call; the spelling that names the whole instance picks."):
  > **Typing rule.** For `T.m(args)` with `T` a generic head, collect the impls of the trait whose Self-head unifies with `T[?a..]` and whose trait arguments unify with the argument types. Zero candidates is "no impl". One candidate is selected, and its impl binders solve `?a..`. More than one is under-determined: `error[CannotInferType]` (E0301). The expected type, when known, filters the candidates before this count.

  > A "most specific wins" rule would be specialization by another name, and it is undefined here: neither source type is an instance of the other, so the order is arbitrary ("deepest nesting", "first declared"). Either choice lets a new library impl, for example `From[List[List[List[T]]]]`, change what existing code means. That is the exact hazard 03_types.md:5032 forbids.

  > The reflexive `impl From[T] for T` joins the candidate set under the same rule, so it can add an ambiguity, and it is subject to the same E0301.

- **DevOps** (devops-1: "Refusal is the rule, with a repair-first diagnostic (no new syntax)"):
  > Refuse. Do not add a "most specific impl wins" rule. 03_types.md:4995 and :5032 already decide this: no specialization, so a new impl cannot change which impl old code selects. A tie-break would only work for From, and would break that rule. Keep E0301 CannotInferType. The compiler already does this; the spec needs to state it.

  > The "-> Box[X]" column is the new part. It turns "ambiguous" into a choice the user can make from the message alone. It needs the typechecker to instantiate each candidate, which it already does to detect the match. For `x.into()` point at `.into()` and name the same candidates by the `From` impl, not by `Into`, since `Into` is auto-derived.

- **AI/ML** (aiml-1: "refuse; the expected type picks; no impl wins by rule (all generic-qualifier trait calls)"):
  > **Rule.** A call `T.m(x)` or `x.into()` through a generic type's qualifier must resolve to exactly one impl. The resolver gathers impls by trait and head. It then uses, in order, only *type information that already exists at the call*: the expected type (annotation, parameter type, return type, field type) and the explicit type list. If more than one impl still matches, the call is E0301. No impl wins because it is "more specific". This is the *No Impl Overlap* rule (03_types.md:4995) applied to calls. It is not limited to `From`. It covers every trait method called through a qualifier whose binders are open.

  > Decision points: refuse adds zero. One repair (annotation) is learnable from one example. "Most specific wins" adds a rule the model must predict. It must reason about specificity, and models get that wrong for generic heads. A wrong guess compiles and silently yields a different type. A refusal fails loudly and is fixed on the next turn.

- **Minimalism** (min-1: "Refuse. Add no rule, no syntax. State the existing rule once."):
  > Refusal is already the rule. 03_types.md:4995 says no "more specific impl wins" rule exists, and DECISIONS.md:175 records the vote. 03_types.md:2954 says Blink never defaults an unresolved type variable and that a later use does not fix it. The ticket asks us to carve an exception to both. We should not. The spec needs one sentence under *Under-Determined Types* that names this case. It needs no new feature.

  > Refusal turns that change into a compile error at the caller. That is the safe failure.

#### Phase B — Debate highlights

The Phase B digest corrected the moderator brief with the 03_types.md paragraph "Later use still determines the type —
there is no error when it does" (`let mut xs = []` then `xs.push(1)` is not an error). Each seat then replied on five
points: V1 why a later use does not pick, V2 the diagnostic text, V3 where the rule lives, V4 the explicit type list,
V5 the reflexive impl.

- **Systems, V1:**
  > I concede a point and keep the conclusion. Three seats (devops, aiml, min) cite 03_types.md:2954 as saying a later use does not pick. The digest correction shows the opposite: later use still determines a type, and `let mut xs = []` then `xs.push(1)` is fine. So p9 is not covered by 2954. The spec needs an explicit carve-out. Impl selection is not a binding's type variable. It picks a function body, and it is settled at the call.
- **AI/ML, V1:**
  > **Correction to my own Phase A.** I wrote that p9 "matches 03_types.md:2954". That is wrong. The same subsection (2979) says a later use does determine a binding's type (`let mut xs = []` then `xs.push(1)`). The min and devops citation of 2954 for p9 has the same flaw. I withdraw that argument.
- **DevOps, V1:**
  > p9 stays an error, for a different reason. The reason is sys-1 and plt-1: impl choice is made at the call, not by inference over the binding. But this is now a visible exception, and the user will see it: `xs.push(1)` rescues `let mut xs = []`, and `let n: Int = a.v.get(0).unwrap()` does not rescue `let a = Box.from(...)`. Tooling cost: users will file this as a bug unless the spec states it and the message says it. So the rule text must say "impl selection is complete at the call; a later use does not reopen it", and the E0301 text for this case must say "a later use does not choose". Without both, 2979 and this rule look contradictory.
- **Minimalism, V1:**
  > p9 still stays E0301, for the plt/sys reason. The impl is chosen at the call. Binder inference across statements is a separate thing: `xs` is one variable that a later `push` fixes. Here a later use would have to choose between two impl bodies, which turns impl selection into a deferred obligation. That needs new checker machinery to buy one spelling the annotation already gives. Subtraction says do not build it. If anyone proposes it, it is a separate feature with its own vote. It is not part of this ticket.
- **Web, V1:**
  > p9 stays an error. Reason: the choice of impl is made at the call, not at the binding. In `let mut xs = []` one unknown type has one future value. Here the call has two valid impls that give two different programs, and the later use would have to pick between them. That is a deferred obligation across statements (plt-1, sys-1). The spec must say this in one sentence under *Under-Determined Types*, so the contrast with `xs.push(1)` is stated and not left for users to find.
- **PLT, V1 (changes position; dissent in the later vote):**
  > My Phase A said impl choice would "cross statements" and that 2954 forbids a later use. The Facts correct that: 03_types.md:2979 says later use DOES fix an unbound variable (`let mut xs = []` then `xs.push(1)`). Here `Box.from(xs)` types as `Box[?T]` with a pending obligation `From[List[List[Int]]] for Box[?T]`. In p9, `a.v.get(0).unwrap(): Int` fixes `?T = Int`, and one impl then matches. That is sound: coherence gives one impl per ground instance.
  >
  > - **V1-b (defer to end of inference).** The call carries the obligation. E0301 fires, at the call, only if inference terminates with more than one candidate. One rule, no impl-specific exception. Cost: a pending-obligation set in the checker; HM metavars exist already.
  >
  > I vote V1-b, and I accept V1-a if the panel prefers locality. Both stay on the ballot.
- **Systems, V1 (on deferral):**
  > Deferral is feasible: `a.v.get(0).unwrap()` as `Int` would filter the candidates. I judge the cost of locality (one annotation) lower than the cost of deferral. Put "later use picks" on the ballot as a real option, not as a settled point.
- **V2, the diagnostic.** Web: "Listing the result type of each impl is what makes the error fixable in 5 seconds" (Phase A). Minimalism withdrew "keep the current text":
  > Accept listing each candidate with the type it gives. It adds no language surface, and it is the web/aiml/devops consensus. I withdraw "keep the current text". The impl-qualified head goes in `help:` only after 03c:760 parses. Until then it would suggest a form that fails. The spec should not fix the message text; it should fix only the code (E0301) and the position (the call).
- **V2, the head help.** AI/ML:
  > The second help naming the impl-qualified head: yes, but only once 03c:760 parses. Before that it would name a form that fails with "expected ), got for".

  DevOps:
  > Head-spelling help: add it only when no binding exists to annotate (plt, min), and only after the head parses (sys). Where a binding exists, the annotation is the shorter repair. One `help:` per situation, not two always.

  Web:
  > I now support adding the impl-qualified head as a `help:` when the call has no binding to annotate (bare statement, chained call such as `Box.from(xs).v.len()`). There the annotation does not exist as a repair, so the head is the only one.
- **V3, where the rule lives.** DevOps: "Rule text in 03c (trait method selection through a qualifier), plus one sentence and a cross-reference in *Under-Determined Types* (min's point)". Minimalism withdrew its placement under *Under-Determined Types*: "One place, 03c, as devops says: it is a rule about trait calls. Add a one-line pointer from *Under-Determined Types*. Do not state it twice." PLT (dissent):
  > One rule, stated once in *Under-Determined Types* (03_types.md:2954 block) with a pointer from 03c. The rule is about any trait method through a generic qualifier, so 03c is the wrong home.
- **V4, the explicit type list.** AI/ML withdrew it: "My Phase A rule text listed "the explicit type list" as a source. That is wrong, since p7 stays E0301. Delete it from the rule. The sources are: expected type, the impl-qualified head, nothing else." Sys: "Explicit type list stays E0301 (p7). `from` has no own binders. Do not put it on the ballot."
- **V5, the reflexive impl.** PLT:
  > `impl From[T] for T` is a candidate only when the argument type unifies with the receiver. `Box.from(b)` with `b: Box[Int]` has it and the user impls both reject `Box`, so no ambiguity arises there. Only an unsolved argument type, for example `Box.from(x)` with open `x`, can add it. The spec needs no special sentence.

  Sys: "The reflexive impl joins the candidate set (plt). It has no runtime cost: it is the identity. State it in the rule so that `Box.from(b)` with `b: Box[Int]` is not a surprise ambiguity."

#### Phase C — Silent ballot

Each seat voted alone on six questions, after it read the brief, the Phase B digest, and all Phase A and B replies. Each
quote below is the seat's own text.

| Question | Sys | Web | PLT | DevOps | AI/ML | Min | Result |
|----------|-----|-----|-----|--------|-------|-----|--------|
| Q1. Refusal or a pick rule | A | A | A | A | A | A | A, 6-0 |
| Q2. A later use (p9) | A | A | **B** | A | A | A | A, 5-1 (plt dissent) |
| Q3. Spec states the diagnostic content | A | A | A | A | A | **B** | A, 5-1 (min dissent) |
| Q4. When the help names the head | B | B | **A** | B | B | B | B, 5-1 (plt dissent) |
| Q5. Where the rule lives | A | A | **B** | A | A | A | A, 5-1 (plt dissent) |
| Q6. The reflexive impl in the text | A | A | B | B | A | A | A 4, B 2 (see Phase D) |

##### Q1. Refusal or a pick rule — A, 6-0

- **Systems:**
  > Specificity is specialization. 03_types.md:4995 and :5032 rule it out, and no seat proposes it. A pick rule would let a new library impl change which body an old call runs, with no error. Refusal turns that change into a compile error at the caller.

  Concern:
  > A user who adds a sibling impl to a library breaks callers that passed bare `Box.from(xs)`, but the break is loud and has a one-line repair.
- **Web:**
  > A JS or Python dev reads "which impl ran?" as a question with one answer. A silent pick by specificity makes a new library impl change old code, and 03_types.md:4995 already rejects that. Refusal with a one-line repair is the 90% path.

  Concern:
  > Users who expect Rust-style "just works" will still file this as a bug; the message must carry the fix.
- **PLT:**
  > Coherence gives one impl per ground instance, `Box[Int]` and `Box[List[Int]]` each have exactly one. The ambiguity is in the unsolved binder of `Box[?T]`, not in impl choice. A specificity order is undefined here, because neither source type instantiates the other, and it is specialization (03_types.md:4995, 5032).

  Concern:
  > None for A. A specificity order would let a new library impl change what existing code means.
- **DevOps:**
  > 03_types.md:4995 and :5032 already rule out a specificity pick. A pick rule would make a new library impl change old call sites with no diagnostic, and no lint, hover or diff would show it. A refusal fails at compile time, at the call, with a repair.

  Concern:
  > Users meet E0301 on a line that looks valid; the message must carry the repair or they will file it as a bug.
- **AI/ML:**
  > A refusal fails loudly at the call and a model fixes it on the next turn with one annotation. A specificity rule compiles and silently yields a different type, and models predict specificity badly for generic heads. It adds a decision point and repeats the specialization that 03_types.md:4995 already rejects.

  Concern:
  > LLM-written code will meet E0301 on a valid-looking line, so the diagnostic must carry the repair.
- **Minimalism:**
  > Refusal is the existing rule (03_types.md:4995, 5032). A pick rule is specialization under another name, needs a partial order on impl heads, and lets a new library impl silently change old call sites. The annotation costs one edit.

  Concern:
  > A user meets E0301 on a valid-looking line, but the repair is one annotation and the failure is local.

##### Q2. A later use (p9) — A (local), 5-1

- **Systems (A):**
  > The two impls have different bodies (wrap versus flatten), so they differ in cost. If a later statement picks the body, an edit far from the call changes the code generated at the call and its cost. Local selection gives codegen one resolved impl per call node before mono, with no pending-obligation set and no fixup pass. This differs from `xs.push(1)`, where one variable gets one future type; here the later use would choose between two function bodies. The spec must state this as an explicit carve-out from 03_types.md:2979, not cite 2954.

  Concern:
  > Users will expect `let a = Box.from(xs)` plus a typed later use to work, as `let mut xs = []` plus `xs.push(1)` does, so the carve-out sentence and the E0301 text must say that a later use does not choose.
- **Web (A):**
  > The error is local and the repair is one annotation, so the user never reads forward to learn which impl ran. The spec must state the contrast with `xs.push(1)` (03_types.md:2979) in one sentence, or users will report it as an inconsistency. Deferred selection needs new checker machinery to save one annotation.

  Concern:
  > Users will still find `let mut xs = []` plus `push` works and this does not, and file it as a bug.
- **PLT (B, dissent):**
  > `Box.from(xs)` types as `Box[?T]` with a pending obligation `From[List[List[Int]]] for Box[?T]`. A later use that fixes `?T` leaves one impl, and that is sound by coherence. This keeps one uniform rule with 03_types.md:2979: E0301 means inference ended with the variable unresolved, and `xs.push(1)` and p9 behave alike. HM metavars exist already, so the cost is a pending-obligation set. E0301 still fires at the call (2691, 2708), only at the end of inference.

  Concern:
  > If A wins, p9 errors while `let mut xs = []` plus `xs.push(1)` does not, so the spec needs an explicit carve-out, and users will report it as a bug.
- **DevOps (A):**
  > Impl selection is complete at the call. An error that points at the call and says "annotate here" is a local repair; a deferred obligation makes the error appear at the end of inference, away from the line that needs the edit. The LSP also needs one resolved impl per call node to give hover and go-to-definition without waiting for later statements. The spec must state the contrast with 03_types.md:2979, or users will read `xs.push(1)` rescuing `let mut xs = []` as a promise that p9 works.

  Concern:
  > p9 errors while `xs.push(1)` does not, so users will see an inconsistency unless both the spec sentence and the E0301 text for this case say "a later use does not choose".
- **AI/ML (A):**
  > With a local rule, the call and its expected type tell a model which impl ran, with no need to read forward. A later use that picks a body makes the meaning of one line depend on distant text. The spec must state the contrast with 03_types.md:2979 in one sentence, because a model that has learned `let mut xs = []` then `xs.push(1)` will otherwise expect p9 to work.

  Concern:
  > p9 is an error while `xs.push(1)` is not, and models will write p9 until the diagnostic says "a later use does not choose".
- **Minimalism (A):**
  > Deferral adds a pending-obligation set to the checker and makes impl selection depend on code far from the call, to buy a spelling the annotation already gives. Subtraction says do not build it. The one-sentence carve-out against 03_types.md:2979 costs little and stops users from guessing by analogy with `xs.push(1)`. If anyone wants deferral, it is a separate feature with its own vote.

  Concern:
  > p9 stays an error while `xs.push(1)` works, so the contrast must be stated in the spec or users will file it as a bug.

##### Q3. What the spec states about the diagnostic — A (content), 5-1

- **Systems (A):**
  > Listing each candidate with the type it gives makes the cost and the choice visible at the call, with no need to work out `Box[Int]` alone. For `x.into()`, naming the `From` impls shows which bodies compete, since `Into` has no body of its own. The spec should fix the content (candidates with result types, help lines), so that tooling and tests have one target.

  Concern:
  > Message content in the spec can drift from the compiler, so a conformance test must pin the candidate list and the help.
- **Web (A):**
  > The per-candidate result type is what makes the error fixable in five seconds; without it the user must work out `Box[Int]` alone. A spec that states the content gives tools and docs one shape to follow. I accept that it ties message text, so the spec should state content, not exact wording.

  Concern:
  > A fixed content list may freeze message shape too early.
- **PLT (A):**
  > The repair for E0301 is part of the rule's contract. Each candidate with its type is the only information that makes the error actionable, and 03_types.md fixes the repair site for E0301 at 2691 and 2708. The spec should fix the content, not the exact wording. Under B (Q2) the text must also say that no later use fixes it.

  Concern:
  > If B wins, an implementation can ship a bare "ambiguous" message and still claim conformance.
- **DevOps (A):**
  > The candidate list with the type each impl gives is what turns "ambiguous" into a repair the user can copy. LSP code actions and tests also depend on this content; if the spec fixes only the code and position, the next compiler change can drop it with no spec violation. The spec states the content (each candidate, its result type, the help), not the exact wording, so the text can still be polished.

  Concern:
  > If the spec text reads as exact message text, it will freeze wording; keep it at the level of content.
- **AI/ML (A):**
  > A model learns repairs from the spec and from the error text. A spec that states "each candidate with the type it gives" and the help line lets a model copy one line and finish. A spec that fixes only the code and position leaves the message free to drift back to "annotate the binding", which does not show the result types. For `x.into()` it must point at `.into()` and name the `From` impls, since `Into` is derived and the user never wrote it.

  Concern:
  > A message that the spec fixes is harder to change, so the wording must stay at the level of content and not exact characters.
- **Minimalism (B, dissent):**
  > The spec should fix the code (E0301) and the position (the call), the two parts that are language contract. Message text and the candidate list belong to the diagnostic catalog and can improve without a spec change. Putting message text in the spec freezes it and adds surface that conformance has to test.

  Concern:
  > Without a spec requirement, a later compiler could drop the candidate list and regress usability, with no spec text to point at.

##### Q4. When the help names the impl-qualified head — B (only with no binding to annotate), 5-1

- **Systems (B):**
  > Where a binding exists, the annotation is the shorter repair, and a second help adds noise. Where the call has no binding (bare statement, chained call), the impl-qualified head is the only repair, so the help must name it there. In both cases the head appears in a help only once it parses; the compiler must not print a repair that the parser rejects.

  Concern:
  > Two help shapes mean two code paths to keep correct in the diagnostic, and the "no binding to annotate" test needs a precise definition in the checker.
- **Web (B):**
  > Where a binding exists, the annotation is the shorter repair, and one `help:` per situation is easier to read than two. The head help earns its place only for a bare statement or a chained call, where an annotation does not exist. Two always-on helps add noise for the common case.

  Concern:
  > Users with a binding who prefer the head form get no hint of it.
- **PLT (A, dissent):**
  > The impl-qualified head is the one spelling that needs no expected type and no inference. It is a repair in every case, also where a binding exists. Two help lines cost little and state both repairs. I accept the shared caveat that the line appears only once the head parses.

  Concern:
  > If B wins, the help changes with the syntactic position of the call, and a user must learn that the repair set varies.
- **DevOps (B):**
  > One `help:` per situation. With a binding, the annotation is the shorter repair and a second help adds noise. The head `(From[X] for Box[Int]).from(...)` is the repair only when no binding exists (bare statement, chained call), and only after it parses.

  Concern:
  > The compiler must detect "no binding to annotate" correctly; a wrong guess prints an annotation help that has no target.
- **AI/ML (B, moved from its Phase B position):**
  > I move from my B1 position. The annotation costs about 4 tokens and models know it from other languages. The impl-qualified head is long and appears in no common training data, so a second help beside a working annotation gives a model a second choice and a likely copy of the longer, rarer form. One help per situation keeps the decision count at zero; the head help appears only where no binding exists (bare statement, chained call), and only once the head parses.

  Concern:
  > With B, the chained-call case relies on the head parsing, and until it does that case has no printed repair.
- **Minimalism (B):**
  > One `help:` per situation is fewer lines and no duplicate repair. The impl-qualified head is the only repair when there is no binding to annotate; with a binding, the annotation is the short repair. This holds only once the head parses.

  Concern:
  > The help depends on whether the call has a binding, so the compiler needs a small branch that the always-two-helps option avoids.

##### Q5. Where the rule lives — A (03c, pointer from Under-Determined Types), 5-1

- **Systems (A):**
  > The rule is about trait method selection through a qualifier, which is the topic of 03c. That is where a reader of the `From` section looks for the repair. *Under-Determined Types* gets a pointer plus the p9 carve-out, so the two rules do not seem to conflict.

  Concern:
  > Two places can drift, so the pointer must name the rule and not restate it.
- **Web (A):**
  > A dev who hits a trait call through a qualifier looks in the trait-method section, so the rule goes in 03c. A pointer from *Under-Determined Types* lets a search for E0301 find it from either place.

  Concern:
  > The rule sits in 03c while the E0301 family lives in 03_types.md, so a reader of one may miss the other if the pointer is weak.
- **PLT (B, dissent):**
  > The rule covers any trait method called through a generic qualifier, and `x.into()`. Its failure mode is an unresolved metavariable at the end of inference, which is the *Under-Determined Types* judgement. 03c holds trait declaration and impl form, so selection through a qualifier belongs with the typing rule that already defines E0301. 03c keeps a pointer.

  Concern:
  > If A wins, the rule sits apart from the E0301 text and the p9 contrast with 2979, so the two can drift.
- **DevOps (A):**
  > The rule is about trait method selection, and a user who reads the `From` section looks in 03c. One statement with a pointer from *Under-Determined Types* and a row in ERROR_CATALOG.md for E0301 means a user who looks up the error finds the rule from either side without two copies drifting.

  Concern:
  > The pointer in *Under-Determined Types* can go stale; it must carry the p9 carve-out so 2979 does not read as contradicting the rule.
- **AI/ML (A):**
  > A model that reads the `From` section and the trait method selection text finds the rule where it calls `Type.from`, and that is where it needs the repair. The rule covers every trait method through a qualifier, and 03c is where those calls are specified. A pointer from *Under-Determined Types* serves the reader who looks up E0301 first, and it also holds the p9 contrast with 2979.

  Concern:
  > The rule sits in one place and the pointer in another, so the two can drift unless the pointer is one sentence with no restated rule.
- **Minimalism (A):**
  > The rule is about trait method selection through a qualifier, and 03c owns that. State it once there and add a one-line pointer from *Under-Determined Types*, so a reader of E0301 finds it. Stating it in both places risks drift.

  Concern:
  > A reader who knows only 03_types.md:2954 may miss the pointer and think the rule is `From` only.

##### Q6. The reflexive impl in the spec text — A 4, B 2

- **Systems (A):**
  > The reflexive impl is the identity and has no runtime cost. One clause in the rule stops `Box.from(b)` with `b: Box[Int]` from reading as a surprise ambiguity. It costs one clause and removes a question the reader would otherwise ask.

  Concern:
  > The clause must say the reflexive impl can add an ambiguity only when the argument type unifies with the receiver, or readers will think it adds one at every call.
- **Web (A):**
  > One clause costs little and answers a question a careful reader will ask ("does the reflexive impl count?"). Leaving it out invites a Stack Overflow question. The rule is still the general one.

  Concern:
  > A named special case may read as a special rule when it is not.
- **PLT (B):**
  > The reflexive impl is an ordinary impl by 03c:278. The general rule counts every candidate whose head unifies, so a special sentence adds nothing and invites a second sentence for the next compiler-provided impl. A test covers it.

  Concern:
  > If A wins, a clause about one built-in impl suggests that it is a special case in the rule.
- **DevOps (B):**
  > The general rule already covers the reflexive impl. A special sentence adds a second place to maintain. The diagnostic lists every candidate, the reflexive one included, so it is not hidden from the user. A test covers the case.

  Concern:
  > A user who gets an ambiguity that lists `impl From[T] for T` may not know it exists; the diagnostic should print it as it prints any other impl.
- **AI/ML (A):**
  > One clause costs few tokens and removes a surprise: `Box.from(b)` with an open argument type can add the reflexive impl to the set. A model cannot derive this from the general rule when it does not know the reflexive impl exists as a candidate. 03c:278 states the impl, and the rule text should link to it.

  Concern:
  > The clause may suggest the reflexive impl is a special case, when the same rule treats it like any impl.
- **Minimalism (A):**
  > One clause costs a line and answers the question every reader will ask: does the reflexive impl add candidates? Leaving it to inference from the general rule invites a ticket. I accept it only as a single clause, not a section.

  Concern:
  > A special mention of one impl can read as a special case and grow into more text than the rule needs.

#### Phase D — Q6 only

Q1 to Q5 had a majority. Q6 split 4 to 2, so the panel ran a second round on Q6 alone. In round 1 each seat answered
the strongest point from the other side. Three seats moved.

- **PLT, B to A:**
  > My B reasoning assumed that the reader knows every impl in scope. That assumption fails for a compiler-provided impl, which no source file declares. [...] I change my vote to A, on one condition on the wording: the clause says that the candidate set includes the compiler-provided impls, with `impl From[T] for T` as the example, and that they follow the same rule. It must not give the reflexive impl its own step in the rule.
- **DevOps, B to A:**
  > I change to A. Conditions, so the clause does not read as a special rule: The clause links to 03c:278 and says the reflexive impl is a candidate "like any other impl". It says the impl adds an ambiguity only when the argument type unifies with the receiver (sys's concern). The diagnostic prints it like any other candidate. No clause for other compiler-provided impls; they follow the general rule.
- **Minimalism, A to B:**
  > I change my Q6 vote from A to B. This is a subtraction: no text, no special case, one test.
- **Systems, Web, AI/ML kept A.** Systems asked for "compiler-provided impls, such as the reflexive `impl From[T] for T`, count as candidates". Web asked for "`impl From[T] for T` is a candidate like any other impl." AI/ML wrote: "The clause states a consequence of the general rule and does not give a new rule".

The two wordings of A came from the panel, so the round 2 ballot had three options.

- **A1:** one clause that names the class of compiler-provided impls, with the reflexive impl as the example.
- **A2:** one clause that names the reflexive impl only, with a link to 03c.
- **B:** no sentence; the general rule and a test cover it.

| Seat | Vote | Reasoning (verbatim) |
|------|------|----------------------|
| Systems | A1 | "A2 names one impl only, so a second built-in impl would need a second clause. B leaves a model that learns from the spec alone with an ambiguity that appears from nowhere." |
| PLT | A1 | "A clause that names the class (\"compiler-provided impls, with `impl From[T] for T` as the example\") states the domain of the rule. A1 adds no typing rule: the reflexive impl gets no step of its own" |
| AI/ML | A1 | "`Into` is also compiler-derived (03c, *The `Into` Trait*), so `x.into()` has compiler-provided candidates too." |
| DevOps | A2 | "A2 names the one impl the compiler prints today. A1 names a class with one member, and its wording on \"compiler-provided impls\" would need upkeep for impls that do not exist (YAGNI)." |
| Web | A2 | "A1 adds a class (\"compiler-provided impls\") that has one member today; that is a rule for a case that does not exist yet (YAGNI), and a reader has to learn a new term to use it." |
| Minimalism | B | "Text about a class with one member is an addition with no second case to justify it. If A wins, A2 is the smaller text: A1 writes a rule for a class that has one member." |

Concerns on the winning side, verbatim. Systems (A1): "If the compiler prints the reflexive impl in the diagnostic differently from user impls, or the clause grows past one sentence, the text reads as a special case." DevOps (A2): "If a second compiler-provided impl appears, the spec text and the diagnostic can drift apart until someone adds a second clause." Minimalism (B): "If B wins, a reader who meets `impl From[T] for T` in a diagnostic and finds no mention in the rule text may file a ticket; the diagnostic must print it like any other candidate."

Result: A1 3, A2 2, B 1. No option has a majority.

##### BDFL tiebreak

The owner broke the tie: no clause about the reflexive impl in the rule text. Two examples show the case instead (`Wrap.from(w)` with `w: Wrap[Int]` is accepted, and `Wrap.from(ws)` with `ws: Wrap[List[Int]]` is E0301). The diagnostic prints the reflexive impl like any other candidate. This is the B outcome, reached by owner ruling and not by panel majority.

### AI-First Review

4/5 pass.

| Criterion | Result | Note |
|-----------|--------|------|
| Learnability | Pass | One rule: a call that two impls match is an error at the call. Two things pick: the expected type and the impl-qualified head. |
| Generability | Pass | The OK form is an annotation, which a model already writes. The error names each type the candidates give. |
| Consistency | Fail | A later use fixes `let mut xs = []` (03_types.md, *Under-Determined Types*) but does not pick an impl here. The spec states the contrast in 03c and in a pointer under *Under-Determined Types*, so the exception is explicit and not hidden. |
| Debuggability | Pass | E0301 at the call, one note per candidate, one note that a later use does not choose, one help. |
| Token efficiency | Pass | The repair is one annotation. |

### Final Spec

The rule is in `sections/03c_protocols.md`, under *A Generic Qualifier That Matches Two Impls*. A pointer is in `sections/03_types.md`, under *Under-Determined Types*.

```blink
type Box[T] { v: List[T] }

impl[T] From[List[T]] for Box[T] { /* wrap */ }
impl[T] From[List[List[T]]] for Box[T] { /* flatten */ }

fn main() {
    let one = Box.from([1, 2])                        // OK: only the first impl matches
    let a: Box[Int] = Box.from([[1, 2], [3]])         // OK: the annotation picks the second impl
    let f = Box.from([[1, 2], [3]])                   // COMPILE ERROR E0301: two impls match
    let n: Int = f.v.get(0).unwrap()                  // a later use does not pick
}
```

Locked points:

- A trait method called through a generic type's qualifier that matches more than one impl is E0301 at the call. No impl wins by specificity. The rule covers `x.into()`.
- The expected type (annotation, parameter, return, field) and the impl-qualified head pick an impl. `Box.from[Int](..)` and `Box[Int].from(..)` do not.
- A later use does not pick. The spec states this as a contrast with *Under-Determined Types*.
- The spec fixes the diagnostic content, not the wording: each candidate with the type it gives, a note that a later use does not choose, and one help. The help is an annotation when a `let` receives the result. Otherwise it is one impl-qualified head for each candidate. For `x.into()` it points at `.into()` and names the `From` impls.
- The rule lives in 03c. *Under-Determined Types* holds a pointer.
- The rule text has no clause about the reflexive impl. Two examples show it.
