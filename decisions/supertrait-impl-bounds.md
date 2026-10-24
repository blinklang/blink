[< All Decisions](../DECISIONS.md)

# Supertrait Check Under the Impl's Own Bounds — Design Rationale

ERROR_CATALOG E0911 said "every impl must satisfy each supertrait of its trait", and §3.6 *Operations on `Self` in a
Default Body* used that rule to call the default-body check "complete at the definition". The spec did not say how a
polymorphic impl satisfies a supertrait. The compiler judged the supertrait at a generic impl header by type name, so
this program passed `check`:

```blink
type H[T] { v: T }
impl[T: Eq] Eq for H[T] { fn eq(self, o: H[T]) -> Bool { true } }
impl[T] Ord for H[T] { fn cmp(self, o: H[T]) -> Ordering { Ordering.Equal } }
```

The `Ord` impl holds for every `T`, but its supertrait `Eq` holds only where `T: Eq`. The question was whether the
`Ord` header is an error, or whether the obligation moves to each use site.

## Summary

| Q | Question | Result | Vote |
|---|---|---|---|
| Q1 | Rule | A: the impl header proves each supertrait under the impl's own bounds, closed over their supertraits; else E0911 `MissingSupertraitImpl` at the header. A concrete impl is the case with no binders | 6-0 |
| Q2 | Primary span when a missing bound is the cause | A: one clause in the E0911 catalog row: the binder parameter that lacks the bound; the headline names the failed impl and the supertrait; the trait reference when the obligation does not end at a binder; no label layout in the spec | 6-0 in Phase D after 4-1-1 in Phase C |
| Q3 | Rollout | A: hard error at once, no warning release | 6-0 |
| Q4 | The bound of the auto-derived `Eq` | A: *Supertrait Auto-Derivation* states that the `Eq` that `@derive(Ord)` or `@derive(Hash)` adds carries the bounds `@derive(Eq)` would carry | 6-0 |
| Q5 | What the spec says about the help | A: the machine-applicable help adds only the bounds the impl's bounds do not already entail, in the impl's existing form | 5-1 (Minimalism dissent: B) |

Points all six seats stated in Phase B, not balloted: with a derived supertrait impl, a label or note points at the
`@derive(...)` attribute, with the same code, message and help as a hand pair; no implied bounds (the compiler never
adds a bound the user did not write); with no impl of the supertrait at all, the primary span is the trait name and
the present help ("derive it ... or write `impl Eq for P`") stays.

### Compiler behavior before the decision

The moderator ran eight probes with the gen1 compiler and gave the results to the panel:

- a: the program above checks ok.
- b: the same with `impl[T: Eq] Ord for H[T]` checks ok.
- c: a's impls and `fn lt[T: Ord](a: T, b: T) -> Bool { a < b }` called on `H[F]` with `type F` (no `Eq`) gives
  `error[TraitBoundNotSatisfied]: `H[F]` does not satisfy the Eq bound on type parameter T`, note "`H[F]` is `Eq`
  only if `F` is `Eq`". The bound that `lt` writes is `Ord`.
- d: a concrete `impl Ord for P` with no `Eq` gives `error[MissingSupertraitImpl]: impl Ord for P requires P to also
  implement supertrait `Eq` (trait Ord: Eq)`, help "derive it: `@derive(Eq)` on `P`, or write `impl Eq for P`".
- e: `@derive(Ord) type H[T]`, then `<` on `H[F]` gives "`H[F]` does not implement `Ord`", note "`H[F]` is `Ord` only
  if `F` is `Ord`".
- f: `trait Loud: Named`, `impl[T: Named] Named for W[T]` and `impl[T] Loud for W[T]` check ok.
- g: a's impls and a direct `a < b` / `a.cmp(b)` on `H[F]`: `check` ok, although `H[F]` is not `Eq`; `run` reaches an
  unrelated codegen ICE.
- h: f's impls and `fn both[T: Loud](x: T) -> Str { "{x.shout()} {x.name()}" }` called on `W[N]` with `N` not
  `Named`: `check` ok, and the body calls `x.name()` on a `W[N]` that has no `Named` impl.

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in
independent-proposal, debate, vote rounds. Phase A is excerpted from each panelist's own text. Phases B, C and D
are quoted in full from each panelist's file, without its heading line.

#### Phase A — Independent proposals

All six seats proposed the same rule as their first choice. Each also wrote against the use-site obligation.

- **Systems** (`A/sys.md`):

> Rule for §3.6: an `impl[Ts: Bs] Tr for X[Ts]` is well-formed only if, for every supertrait `S` of `Tr` (transitive), `X[Ts]: S` follows from the bounds `Bs` (plus `where` clauses) alone. The check runs once, at the impl header, before any use. Probe a is an error.
>
> [...]
>
> Same code E0911 as probe d: one contract ("every impl satisfies each supertrait"), two shapes (no impl at all / impl under stronger bounds). Primary span on the binder `[T]` when a missing bound is the cause; on the trait name when no impl of `S` exists for `X` at all (probe d keeps its current span and help). The help is machine-applicable: it adds exactly the bounds of the supertrait impl the checker found.
>
> [...]
>
> Blink monomorphizes. A generic body `both[T: Loud]` calls `x.name()`; mono resolves that to `Named.name` at `W[N]`. Under the use-site rule there is no such instance, so the failure lands in mono or codegen. That is exactly what probe h does today with `run`: `check` says ok, the build ICEs at `self.v.name()`. Every stage after typecheck then has to carry a "this instance might not exist" path — in mono, in layout, in any future vtable for a trait object (a vtable for `Loud` must hold `Named`'s slots at the same instance). The header rule removes that path: once typecheck passes, every supertrait call in any mono instance resolves. Zero runtime cost, and less code in cg.

- **Web/Scripting** (`A/web.md`):

> **Rule.** An impl `impl[Ts: Bs] Sub for X[Ts]` must prove `X[Ts]: Super` for each supertrait `Super` of `Sub`, using only the bounds the impl itself declares (binder bounds, `where` clause, and the supertraits those bounds imply). If it cannot, the impl is E0911 `MissingSupertraitImpl`, the same code a concrete impl gets today (probe d). The obligation never moves to the use site.
>
> [...]
>
> **Why web picks this.** The error lands on the line the dev wrote wrong, with a one-edit fix. Today (probe c) a dev who wrote `fn lt[T: Ord]` gets "does not satisfy the **Eq** bound" at a call site far from the cause. That message makes a Stack Overflow question every time: "I asked for Ord, why is it talking about Eq?" A use-site rule makes this the normal experience, not a bug.
>
> [...]
>
> - Rollout: the generic case is new rejection, so warning first with the `blink fix` edit, error next release (same as the §3.6 rollout paragraph).

- **PLT** (`A/plt.md`):

> **Rule.** For `impl[Ts] Tr for X[Ts] where C`, and for each direct supertrait `S` of `Tr`, the context `C` must entail `X[Ts]: S`. `C` is the bounds written in the binder or `where`, closed over their supertraits (`T: Ord` gives `T: Eq`). The check uses the same instance resolution as a use site (`tc_instance_has_trait`), with each `T` as a rigid variable that has only the bounds in `C`. If the check fails, emit E0911 `MissingSupertraitImpl` at the impl declaration. A concrete impl is the case with an empty binder, so probe d is unchanged. There is one rule, not two.
>
> **Why this rule and not use-site.** Bound elaboration (`T: Loud` ⊢ `T: Named`) is what makes generic bodies and default bodies type-check. §3.6 *Operations on Self* already claims "every impl must satisfy the trait's supertraits ... the check is complete at the definition". The use-site option makes that claim false. Probe h is the counterexample: `both[T: Loud]` calls `x.name()` with the right to do so from `Loud: Named`. Then `both(W { v: N {...} })` checks, and the call goes to an impl that does not exist. That is unsound, not only "unusable".
>
> [...]
>
> **No implicit bound insertion.** The compiler must not quietly add `T: Eq` to the impl. That would put bounds in the impl that the code does not show. It would break the parametricity statement in *Polymorphic Trait Implementations* (behavior varies only through written bounds). It would also make a change to one impl's bound change the domain of the other impl, far from it.

- **DevOps/Tooling** (`A/devops.md`):

> **Rule.** An impl `impl[T: B..] Sub for X[T]` must show, for each supertrait `S` of `Sub` (transitively), that `X[T]` is `S` using only the bounds `B..` (plus the supertrait closure of those bounds, so `T: Ord` entails `T: Eq`). The check runs once, at the header. Use sites never re-check supertraits.
>
> [...]
>
> Primary span: `Ord for H[T]` (the claim that fails). Secondary labels: the binder (where the fix goes) and the bound on the supertrait impl (why). The help is a machine-applicable edit: insert `: Eq` after a bare `T`, append ` + Eq` to an existing bound list, or add to an existing `where` clause. `blink fix` applies it. When no `S for X[_]` impl exists at all, keep today's help (`@derive(Eq)` / `impl Eq for H[T]`).
>
> [...]
>
> **Derive and mix.** `@derive(Ord)` on `H[T]` emits `impl[T: Ord] Eq` (if absent) and `impl[T: Ord] Ord` — passes by entailment.
>
> [...]
>
> **Cost.** Code like probe a that checks today now fails. The fix is one token and mechanical, so per §3.6 *Rollout* it can ship as a warning with a `blink fix` edit for one release. I lean to a hard error at once: the accepted code is already unsound (h), so a warning period keeps a hole open.

- **AI/ML** (`A/aiml.md`):

> Rule for §3.6: an `impl[Ts] Sub for X[Ts] where B` is well-formed only when, for each supertrait `Sup` of `Sub`, `X[Ts]: Sup` follows from `B` (with the supertrait closure of each bound: `T: Ord` gives `T: Eq`). Otherwise E0911 `MissingSupertraitImpl` at the header. A concrete impl (probe d) is the case with no binders, so one rule covers both.
>
> [...]
>
> Primary span on the binder list (where the fix goes); secondary note points at the `impl[T: Eq] Eq` header that sets the condition. The help names the exact missing bounds: the supertrait impl's binder bounds, substituted, minus what the current bounds already entail. It is machine-applicable.
>
> [...]
>
> - **One rule, one site, one fix.** A model writes an impl, gets an error on the line it wrote, and the help is a literal edit. Use-site errors (probe c) name a bound the caller never wrote (`Eq` when `lt` asks `Ord`); a model then edits the caller, which is wrong.
> - **Matches the training prior.** Rust (E0277 at the impl: "the trait bound `T: Eq` is not satisfied", "required by a bound in `Ord`"), Haskell (GHC: "No instance for (Eq a) arising from the superclasses of an instance declaration"), and Swift (a conditional `Comparable` conformance must state the conditions its `Equatable` needs) all check at the header.

- **Minimalism** (`A/min.md`):

> The rule already exists. ERROR_CATALOG E0911 says "every impl must satisfy each supertrait of its trait", and §3.6 *Operations on `Self`* leans on that sentence to call the default-body check "complete at the definition". The compiler just checks it by type name. Fix the check, add one sentence to the spec, ship. Nothing new to learn.
>
> Rule: for `impl[Ts: Bs] Sub for X[Ts]`, with `trait Sub: Sup`, the checker must prove `X[Ts]: Sup` with only `Bs` (closed over their own supertraits: `T: Ord` gives `T: Eq`) as assumptions. If it cannot, E0911 at the impl header.
>
> [...]
>
> - Mix: `@derive(Eq)` on `H[T]` plus a hand `impl[T] Ord for H[T]` gives E0911, help `T: Eq`. Same rule, same message as a hand pair.
>
> [...]
>
> Rollout: no warning period. This is a bug in a rule the spec already has, and h is unsound.
>
> [...]
>
> ## Not proposed: implied bounds (Ord impl silently gets `T: Eq`)
>
> Hidden bounds the user did not write. Adds inference to fix a check. Reject.

##### Phase A options (after dedupe)

- **Option 1:** the impl header proves each supertrait under the impl's own bounds (closed over their supertraits);
  else E0911 at the header. First choice of all six.
- **Use-site obligation:** no seat's pick; all six gave reasons against it.

Variations flagged for Phase B: V1 primary span; V2 rollout; V3 a note for a derived supertrait impl; V4 implied
bounds; V5 the form of the help.

#### Phase B — Debate, round 1

The moderator gave the panel two facts from the repo, with no position implied:

- The *Rollout* paragraph web-1 cites is sections/03_types.md:4220: "Each new error in this subsection ships first
  as a warning ...". It is the last paragraph of *Mutable Parameters* (heading at :4104), not of the supertrait text.
- What a derived impl's bound is: sections/03_types.md:5947 "If a field has type `A`, and the derived trait requires
  calling `.eq()` on that field, then `A: Eq` is added as a bound." *Supertrait Auto-Derivation* (:5952) says
  `@derive(Ord)` "implicitly derives `Eq`" and does not state the bound of that `Eq` impl.

All six seats ended round 1 `STATUS: ready to vote`. Position changes: Web/Scripting withdrew the warning period;
DevOps moved the primary span to the binder and corrected its auto-derived `Eq` bound to `T: Eq`; PLT moved the
primary span to `Ord for H[T]`; Minimalism asked that the spec leave the span layout to tooling and that the
auto-derived `Eq` bound go to a separate chore.

- **Systems** (`B1/sys.md`):

> Option 1 stands, unchanged. Six of six agree; the rest is the shape of the diagnostic.
>
> **V1 span.** Primary on the binder `[T]` when a missing bound is the cause, on the trait name when no impl of `S` matches `X[_]` (plt-1 says the same). The primary span should sit where the edit goes, since that is where `blink fix` and the LSP quick-fix act. I concede the secondary labels: one on `Ord for H[T]` (devops' "the claim that fails") and one on the supertrait impl's bound ("why"). Labels cost nothing at runtime and help the reader.
>
> **V2 rollout.** Hard error at once, with the fix. The *Rollout* paragraph belongs to *Mutable Parameters* (fact at :4220), not to this rule. Probe h is not a style issue: it type-checks and then ICEs in mono on a call to an impl that does not exist. A warning period would keep code that does not build in a state where `check` says it is fine.
>
> **V3 derived mix.** Point the secondary label at the `@derive(Eq)` attribute. The user cannot see a derived bound in the source, so the note must show it.
>
> **V4 implied bounds.** Reject, with plt-1 and min-1. A hidden bound changes which instances exist, and mono must then derive bounds the source does not show.
>
> **V5 help.** Merge with `+`, add to an existing `where` clause if there is one, and add only the bounds that the current ones do not already imply (aiml-1). All three are the same edit at different positions.
>
> **Derive fact.** :5947 gives a field bound by what the derived body calls, so an auto-derived `Eq` is `impl[T: Eq] Eq`, not devops' `[T: Ord]`. Either one passes the check; the spec text should say `T: Eq`.
>
> STATUS: ready to vote

- **Web/Scripting** (`B1/web.md`):

> Option 1 stands. No change to the core rule.
>
> **V1 span.** Binder primary when a missing bound is the cause; trait name when no impl of the supertrait exists for `X` at all (sys-1/plt-1 split). Secondary label on the supertrait impl's header ("`Eq for H[T]` requires `T: Eq`"). devops-1's span on `Ord for H[T]` is fine too, but the eye should land where the edit goes. Weak preference; I will not block on it.
>
> **V2 rollout. I withdraw the warning period.** The moderator is right: the *Rollout* paragraph I cited belongs to *Mutable Parameters*, not to supertraits. And the accepted code is unsound (h compiles a call to a method that does not exist). A warning that lets unsound code run for a release is worse DX than a hard error with a one-edit `blink fix`. Hard error now, as devops-1 and min-1 say. The machine-applicable help makes the break cheap.
>
> **V3 derived note.** Keep the note at `@derive(Eq)`. A dev who never wrote an Eq impl will not know where `T: Eq` came from; "derived `Eq` requires `T: Eq`" answers that in one line. min-1's "same message" costs a confused minute for zero gain.
>
> **V4 implied bounds.** Reject. Hidden bounds read well until a call fails for a reason not on the screen.
>
> **V5 help.** Merge with `+` (plt-1), edit the existing `where` clause when there is one (devops-1), add only what the current bounds do not already entail (aiml-1). All three; they do not conflict.
>
> **Fact on the derived Eq bound.** §3.6:5947 adds `A: Eq` for a field needing `.eq()`, so auto-derived Eq is `impl[T: Eq] Eq`, not `[T: Ord]`. The spec should state it in *Supertrait Auto-Derivation*.
>
> STATUS: ready to vote

- **PLT** (`B1/plt.md`):

> I still support Option 1, the same rule as plt-1.
>
> **V1 (span).** I accept devops-1's layout. The primary span goes on `Ord for H[T]`, the claim that fails. Secondary labels go on the binder, where the fix goes, and on the supertrait impl's bound, which is the cause. In type-theory terms, the impl judgement is what fails, and a missing hypothesis in the binder is one possible cause. The help already points at the binder. The no-impl case (d) keeps the span it has now.
>
> **V2 (rollout).** Make it a hard error at once. The *Rollout* paragraph at :4220 is about *Mutable Parameters*, so it does not apply here. Code that passes today is unsound (h), so a warning period would mean shipping a known hole for one release. That also matches what §3.6 :4235 already promises.
>
> **V3 (derive note).** The note should point at `@derive(Eq)`. The label points to the impl that sets the condition, whether a user wrote it or derive made it. That keeps one rule, so I see no conflict with min-1.
>
> **V4.** Reject implied bounds. All six seats agree.
>
> **V5 (help).** Combine devops-1 and aiml-1. The help lists the missing bounds, which are the supertrait impl's bounds after substitution, minus what the current context already proves. It then inserts them in the form the user wrote: `: B`, `+ B`, or the `where` clause. With aiml-1's "minus what is already entailed", `impl[T: Ord] Ord` gets no help, because none is needed.
>
> **One correction for the spec text.** When `@derive(Ord)` auto-derives `Eq`, the bound must follow :5947 (one bound per field use), which gives `impl[T: Eq] Eq`. devops-1's `impl[T: Ord] Eq` is narrower than it needs to be: it would make `H[F]` not `Eq` when `F` is `Eq` but not `Ord`. Both forms pass entailment. *Supertrait Auto-Derivation* should state the bound so the result is known.
>
> STATUS: ready to vote

- **DevOps/Tooling** (`B1/devops.md`):

> I support Option 1. No seat backs the use-site rule. I now take the majority's primary span, which differs from my Phase A text.
>
> **V1 (span).** I concede. The primary span goes on the binder `[T]` when a missing bound causes the error, and on the trait name when no impl of `S` matches `X[_]` (as sys-1 and plt-1 say). The binder is where `blink fix` edits and where the LSP quick-fix lands, so the caret and the edit match. I still want a secondary label on the supertrait impl's header ("`H[T]` is `Eq` only where `T: Eq`"). Without it, a user with the Eq impl in another file cannot see why the bound is needed.
>
> **V2 (rollout).** Hard error at once, as min-1 says. The *Rollout* paragraph belongs to *Mutable Parameters* (:4220), not to supertraits, so it does not bind here. The accepted code is unsound (h) and ICEs at `run`. A warning would keep the hole open for a release and buy nothing, since the fix is one token that `blink fix` writes.
>
> **V3 (derived supertrait).** Point the secondary label at the `@derive(Eq)` attribute ("derived `Eq` requires `T: Eq`"). This agrees with min-1: the code, the message and the help stay the same, and only the label points somewhere else. It costs nothing and shows where the condition comes from.
>
> **V4 (implied bounds).** Reject. A hidden bound gives the LSP nothing to show on hover and nothing to jump to.
>
> **V5 (help).** The help adds only the bounds not yet proven (aiml-1's "minus what is entailed"). It edits the form the impl already uses: it inserts `: Eq` after a bare `T`, merges with `+` into an existing list, or appends to an existing `where` clause. It never changes the other impl.
>
> **Correction.** I wrote the auto-derived Eq as `impl[T: Ord] Eq`. Per :5947 it is `impl[T: Eq] Eq`. Both bounds pass. *Supertrait Auto-Derivation* (:5952) should state the bound, so the derive and this check agree in writing.
>
> STATUS: ready to vote

- **AI/ML** (`B1/aiml.md`):

> I support Option 1, as in Phase A. My position on each variation:
>
> **V1 span.** The primary span goes on the binder, because the fix goes there and a model edits the line under the caret. If no impl of the supertrait exists at all, the primary span is the trait name and d's help stays (sys-1/plt-1). Keep the secondary label on the supertrait impl's header. It answers "why `T: Eq`?" without a second lookup. devops-1 puts the primary span on `Ord for H[T]`. That is a fair reading of "the claim that fails", but it puts the caret one place away from the edit. This point is small and I will not block on it.
>
> **V2 rollout.** Make it a hard error at once (devops-1, min-1). The rollout paragraph web-1 cites is part of *Mutable Parameters* (03_types.md:4220), not the supertrait text. h is unsound today. A warning period would also teach models from code that compiles and then breaks.
>
> **V3 derived note.** Point at the `@derive(Eq)` attribute. If the note points at a hand impl that does not exist in the source, the model searches for one. The note costs nothing and costs no extra decisions.
>
> **V4 implied bounds.** Reject them. A hidden bound is one more rule that a model cannot see in the text.
>
> **V5 help form.** Add only the missing bounds, in the form the impl already uses: `: Eq` after a bare `T`, ` + Eq` on a list, or a new item in an existing `where`. Offer the weakest bound (`T: Eq`), not `T: Ord`.
>
> **Derive fact.** 03_types.md:5947 already fixes the bound of the auto-derived `Eq`: the `Eq` that `@derive(Ord)` adds needs `.eq()` on each field, so its bound is `T: Eq`, not `T: Ord` as devops-1 writes it. The vote does not depend on this, but the §3.6 example should write it as `T: Eq`.
>
> STATUS: ready to vote

- **Minimalism** (`B1/min.md`):

> No change from Phase A. Option 1.
>
> **V1 span.** The spec should fix the code (E0911) and the place (the subtrait impl header). It should leave the exact span layout to the tooling. My preference: primary on the binder when a bound is missing, and on the trait name when no impl of the supertrait exists at all (sys-1/plt-1). devops-1's secondary labels are fine as a diagnostic detail. They do not need spec text.
>
> **V2 rollout.** Make it a hard error now. The *Rollout* paragraph that web-1 cites is the last paragraph of *Mutable Parameters* (:4220), so it does not cover this. The rule is not new: the catalog already says "every impl must satisfy each supertrait". The compiler skipped the generic case, and h is unsound. A warning release leaves that hole open. devops-1 leans the same way.
>
> **V3 derive note.** I accept a note that points at `@derive(Eq)`. It is a label, not a new message form, so the rule stays the same for hand, derived and mixed impls.
>
> **V4 implied bounds.** Reject them. They add hidden inference to fix a check.
>
> **V5 help.** Merge into the existing bound list or `where` clause, and leave out bounds the current ones already entail. This belongs to `blink fix`, not the spec.
>
> **Separate gap, not ours to settle:** §3.6 *Supertrait Auto-Derivation* does not state the bound of the auto-derived `Eq`. devops writes `[T: Ord]`, the rest of us write `[T: Eq]`. Option 1 passes either way. File it as a spec chore. Do not fold it into this vote.
>
> STATUS: ready to vote

#### Phase C — Final vote

Ballot options:

- **Q1.** A: the impl header proves each supertrait under the impl's own bounds (closed over their supertraits);
  else E0911 at the header; a, f, g, h become errors. B: the obligation moves to each use site.
- **Q2.** A: the binder; secondary labels on `Ord for H[T]` and on the bound in the supertrait impl's header.
  B: `Ord for H[T]`; secondary labels on the binder and on the supertrait impl's bound. C: the spec fixes only the
  code (E0911) and the place (the subtrait impl header); span layout goes to the impl ticket.
- **Q3.** A: hard error at once, no warning period. B: warning first with the `blink fix` edit, error in the next
  release.
- **Q4.** A: this decision writes into *Supertrait Auto-Derivation* that the `Eq` that `@derive(Ord)` or
  `@derive(Hash)` adds has the bounds of `@derive(Eq)`. B: file a separate spec chore.
- **Q5.** A: the spec states that the machine-applicable help adds only the bounds the impl's bounds do not already
  entail, in the impl's existing form (`: Eq`, ` + Eq`, or the `where` clause). B: the spec states only that the help
  is machine-applicable and adds the missing bound; its form goes to `blink fix` and the impl ticket.

- **Q1: rule** (A, 6-0)
  - **Systems:** A — "Blink monomorphizes, so each supertrait call in a generic body must find a real impl at each instance. With A, typecheck guarantees this once, at the header. With B, the failure reaches mono, and probe h shows that path today: `check` says ok, then the build ICEs on a call to an impl that does not exist. A keeps codegen free of a \"this instance might be missing\" path, at no runtime cost." Concern: "the header check must use the same instance predicate as use sites (`tc_instance_has_trait`) with rigid binders; a second, weaker copy of the entailment logic would reopen the hole."
  - **Web/Scripting:** A — "The error shows up on the line the dev wrote wrong, and a one-edit fix comes with it. A use-site rule puts the error at a far-away call and names a trait the caller never wrote (probe c), so it produces a Stack Overflow question each time. Rust devs already expect this rule." Concern: "Devs who copy an `impl[T]` header from a trait with no supertraits will hit E0911 often, so the help must be exact or the error will feel like noise."
  - **PLT:** A — "Bound elaboration (`T: Loud` gives `T: Named`) is sound only if every impl of the subtrait proves its supertraits under the impl's own context. §3.6 :4235 already depends on that rule. B makes probe h type-check and then call an impl that does not exist, so B is unsound and not only harder to use. A is the same rule as Rust, Haskell and Swift, and probe d is the case with no binders." Concern: "The entailment check must use the same instance resolution as the use site, with each binder rigid. If it uses a separate name-based shortcut, the bug comes back in a new place."
  - **DevOps/Tooling:** A — "One check at one place gives one error and one fix, on the line the author wrote wrong. The use-site rule gives probe c's message: the user wrote `T: Ord`, gets an error about `Eq`, at a caller far from the cause. It also lets h pass `check` and then ICE at `run`, which is the worst diagnostic surface there is." Concern: "Existing generic impls that check today now fail with no warning, so the help must be right in every bound form, or users get stuck."
  - **AI/ML:** A — "There is one rule, it runs in one place, and the fix is one edit on the line the model just wrote. The same check at the header already exists in Rust, Haskell and Swift, so models write `impl<T: Ord> Ord` by habit. The use-site rule gives errors that name a bound the caller never wrote (probe c), and models then edit the wrong file." Concern: "Generated code that checks today (probe a's shape) stops compiling with no warning first, so the help must be exact enough for `blink fix` to repair it in one pass."
  - **Minimalism:** A — "The rule is already in the catalog (\"every impl must satisfy each supertrait\"). The fix makes the checker do what it says, so the language gains no new surface. A use-site obligation adds a state (\"the impl holds but no one can use it\") and one more check on every bound proof. It also makes §3.6's \"complete at the definition\" false." Concern: "The proof must close the binder bounds over their supertraits (`T: Ord` gives `T: Eq`). If it skips that, valid impls like `impl[T: Ord] Ord for H[T]` get rejected."

- **Q2: primary span when a missing bound is the cause** (A 4, B 1, C 1; went to Phase D)
  - **Systems:** A — "the primary span should sit where the edit goes, because `blink fix` and the LSP quick-fix act there. The secondary labels on the claim and on the supertrait bound give the reason without a second error." Concern: "if the spec fixes span layout too tightly, a later diagnostic change becomes a spec change; keep the text to \"primary span on the binder\"."
  - **Web/Scripting:** A — "The eye should land where the edit goes, and that is the binder. The secondary labels say what failed and why, so no context is lost." Concern: "In a long binder list or a `where` clause, a caret on the binder can be hard to match to the failing claim unless the label text names the supertrait."
  - **PLT:** B — "The judgement that fails is \"`H[T]: Ord` is a well-formed impl\". A missing hypothesis in the binder is one way to repair it. Another repair is to widen the supertrait impl, so the binder is not always where the fault is. The primary span should mark the claim, and the labels should mark the cause and the usual place for the fix." Concern: "If A wins, the message must still name the failed claim (`impl Ord for H[T]`) in its headline, so that the span on the binder does not read as an error in the binder's syntax."
  - **DevOps/Tooling:** A — "The caret goes where the edit goes. The `blink fix` edit and the LSP quick-fix both land on the binder, so the span and the fix agree. The secondary label on the supertrait impl's bound tells the user why the bound is needed, even when that impl is in another file." Concern: "With many binders (`impl[K, V] ...`), the span must point at the one parameter that lacks the bound, not the whole list."
  - **AI/ML:** A — "A model edits where the caret points. If the caret is on the binder, the obvious edit is the correct one, adding `T: Eq` there. The secondary labels still name the claim that fails and the cause, so no information is lost." Concern: "The impl may set a different layout than the spec example, and the spec text and the compiler output would then disagree in the examples models learn from."
  - **Minimalism:** C — "The spec should fix what users depend on: the code, and that the error lands on the subtrait impl header. Which token gets the caret is a diagnostic choice. Writing it into sections/ means a spec edit each time the tooling improves. I still prefer the binder in the implementation." Concern: "If A wins, the spec pins a span layout that later diagnostic work must amend in the spec text, not just in code."

- **Q3: rollout** (A, 6-0)
  - **Systems:** A — "the code this rejects is not a style issue. It passes `check` and then fails to build (h), so a warning period gives no working program to protect. The fix is one bound and machine-applicable." Concern: "library code in the wild that has probe a's shape breaks on upgrade with no warning; the release notes must name the change and `blink fix`."
  - **Web/Scripting:** A — "The code it rejects is unsound (h calls a method that does not exist), and the help is machine-applicable, so the break costs one `blink fix`. A warning release would let unsound programs keep running for no DX gain." Concern: "Some existing user code may break on upgrade with no warning, so the release notes must name E0911 and `blink fix`."
  - **PLT:** A — "Code that is accepted today is unsound (probe h), and the rule restores a guarantee the spec already makes. A warning period would mean shipping a known soundness hole on purpose. The :4220 rollout paragraph covers only *Mutable Parameters*." Concern: "Existing generic impl pairs in lib/std or in user packages break all at once, so the change should sweep lib/std before it lands."
  - **DevOps/Tooling:** A — "The accepted code is unsound (h) and ICEs at `run`, so a warning period keeps a hole open and buys nothing. The fix is one bound that `blink fix` writes. The *Rollout* paragraph belongs to *Mutable Parameters* and does not bind here." Concern: "A user of a third-party package that has such an impl gets a hard error they cannot fix in their own code."
  - **AI/ML:** A — "Probe h is unsound today. A warning period also puts code that compiles but will soon break into the corpus models learn from. One release of warnings buys nothing that the machine-applicable help does not already give." Concern: "Downstream packages with probe-a-shaped impls break on upgrade, and the release notes must point at `blink fix`."
  - **Minimalism:** A — "This fixes a bug in an existing rule, and probe h is unsound today. A warning release keeps the hole open and adds a transition state for no gain. The *Rollout* paragraph covers *Mutable Parameters*, not this rule." Concern: "Code like probe a in lib/std or tests breaks at once. The fix slice must sweep the corpus and apply the help before it lands."

- **Q4: the bound of the auto-derived `Eq`** (A, 6-0)
  - **Systems:** A — "the derived bound decides which instances exist, and so which mono instances codegen may emit. The spec should state it next to the rule that reads it, not leave it for a later chore while this decision cites it." Concern: "the text must say \"the bounds of `@derive(Eq)`\" and not repeat :5947's rule in other words, or the two texts can drift."
  - **Web/Scripting:** A — "A dev who reads `@derive(Ord)` needs to know which bounds the hidden `Eq` impl has, and today the spec leaves that to inference. One sentence here closes the gap while the context is fresh. A separate chore could sit open for a long time." Concern: "Writers might copy the sentence into the hand-impl section and blur the line between derived and hand bounds."
  - **PLT:** A — "The rule's outcome for e depends on which bound the auto-derived `Eq` has, so the decision is not complete until the spec states that bound. Per :5947, field-wise derivation gives `T: Eq`, which is the most general bound. `T: Ord` would remove `H[F]: Eq` for no reason." Concern: "The text must also cover `@derive(Hash)` and a mix of derives in more than one `@derive` attribute, so that \"the bounds of `@derive(Eq)`\" has one meaning."
  - **DevOps/Tooling:** A — "The derive and this check must agree in writing, and the error label for the mix case points at the `@derive` attribute and names its bound. If the spec does not state that bound, the diagnostic cites a rule the spec does not contain. It is one sentence, so this decision can carry it." Concern: "The derive code could emit a different bound from the one the text states, and only a test row will catch that."
  - **AI/ML:** A — "An implicit derive with an unstated bound is something a model must guess. The answer is already fixed by :5947, and writing it next to :5952 costs one sentence and removes the guess. A separate chore leaves the gap open in the text models read now." Concern: "The sentence could be read as a new rule and not as a restatement of :5947, so it should cite :5947."
  - **Minimalism:** A — "I change from B1. This decision now relies on that bound for the derive case. Stating it is one sentence that follows from :5947, adds no new rule, and closes a gap the decision already touches. A separate chore would cost more process than the sentence." Concern: "The sentence must say \"the bounds `@derive(Eq)` would carry\" and not hard-code `T: Eq`, or it will drift from :5947 on multi-parameter types."

- **Q5: what the spec says about the help** (A, 5-1, Minimalism dissent)
  - **Systems:** A — "\"add only what the current bounds do not entail\" is a rule about the result, not a tool detail. It stops the help from writing redundant bounds such as `T: Ord + Eq`, which also add needless entailment work at each instance." Concern: "the spec could grow formatter-level detail; keep it to one sentence on what the help adds and where."
  - **Web/Scripting:** A — "A help that writes `T: Eq + Eq`, or that adds a new bound when the impl already uses a `where` clause, makes the fix look broken and teaches bad style. If the spec states the form, LSP quick-fixes and `blink fix` give the same edit." Concern: "The spec text could grow into a formatter spec; keep it to one sentence."
  - **PLT:** A — "\"Add only the bounds the impl does not already entail\" is the precise statement of the repair, and it follows directly from the rule. It also makes sure `impl[T: Ord] Ord` gets no false help. Stating the insertion form keeps the fix stable across tools." Concern: "Computing \"the bounds not already entailed\" needs the supertrait closure. A careless implementation suggests `T: Ord + Eq`, which is redundant but still sound."
  - **DevOps/Tooling:** A — "Users see the help, and `blink fix` applies it with no review, so its result is a user-visible contract like the error code. \"Only the bounds not already entailed, in the impl's existing form\" keeps the fix stable: running `blink fix` twice gives the same file. A third-party LSP needs the same rule to give the same quick-fix." Concern: "The spec text can grow into a formatter specification. Keep it to one sentence, with no layout rules."
  - **AI/ML:** A — "When the help is fixed, every tool and every model gets the same fix. The spec also becomes the reference for the edit, so models learn the weakest bound (`T: Eq`) and not an arbitrary stronger one (`T: Ord`). The rule is one sentence long." Concern: "The rule may meet edge cases, such as several binders or a `where` clause that is already long, where \"the impl's existing form\" is not clear. The impl ticket then has to choose, and the spec may need a follow-up."
  - **Minimalism:** *(dissent)* B — "The spec should promise a machine-applicable help that adds the missing bound. How the edit merges with `: B`, ` + B` or `where` is `blink fix` behavior and can improve without a spec change. Spelling out every edit form in sections/ is the kind of build-up minimalism exists to resist." Concern: "If A wins, the help text in the spec and the help in `blink fix` can drift apart, and nothing tests the spec text."

**Phase C result:** Q1, Q3 and Q4 pass 6-0 with option A. Q5 passes 5-1 with option A (Minimalism dissents). Q2 comes
out 4-1-1 (A: Systems, Web/Scripting, DevOps/Tooling, AI/ML; B: PLT; C: Minimalism), so it goes to Phase D.

#### Phase D — Focused round on Q2

Moderator facts given to all seats (taken from the repo; no position implied):

- Spec and catalog rows that pin a span today: ERROR_CATALOG.md E1011 "Span on the value"; E0843 "Span on the value
  token"; sections/06_tooling.md E1022 "The primary span is the second source key in source order. Each other source
  key has a label in the same snippet"; dependency manifests "a `note:` with a span on the dependency's entry".
- The E0911 row names no span today.
- Systems' Phase C concern: "keep the text to \"primary span on the binder\"". PLT's Phase C concern: "the message must
  still name the failed claim (`impl Ord for H[T]`) in its headline".

Replies (excerpts):

- **Systems** (stays A): "plt is right that widening the supertrait impl is a second repair. But widening it means
  writing `Eq for H[T]` with no `T: Eq`, and that impl can then not compare `v`. That fix is rare, and often impossible
  for a correct `eq`. [...] I accept plt's concern as a rule: the headline names the failed claim (`impl Ord for H[T]
  ... supertrait Eq`), so a caret on the binder does not read as a syntax error there." Also: "Without a pinned span,
  two front ends (CLI and LSP) can disagree, and the quick-fix range then does not match the caret." Proposed text:
  "Primary span on the binder parameter that lacks the bound; the headline names the impl and the supertrait."
- **Web/Scripting** (stays A): "The binder covers the 90% case, and the secondary label on the supertrait impl still
  shows the other path. I accept your concern in full: the headline names the failed claim (`impl Ord for H[T]
  requires H[T] to implement supertrait Eq`)." And: "Put it in ERROR_CATALOG; §3.6 gives the example with no layout
  text. The cost of a later tooling change is then one catalog row."
- **PLT** (moves to A): "Q5 is now decided, so the help in the spec is the binder edit. A span that points somewhere
  other than the help's edit would contradict that help. Widening the supertrait impl is the rarer repair, and the
  secondary label on that impl's bound still shows it as an option." Conditions: "The headline names the failed impl"
  and "The primary span covers the one binder that lacks the bound, as devops asked. A also needs a fallback for when
  that obligation does not end at a binder. One example is a concrete argument such as `impl Ord for H[F]` with `F` not
  `Eq`. [...] In those cases the primary span is the trait reference, the same as the no-impl case."
- **DevOps/Tooling** (stays A): "The help we decided on (Q5) edits this impl's binder, so the caret goes where the
  offered edit goes. If the caret sits on the claim while the fix sits on the binder, the user must match them up
  [...]. I agree with min and sys that the label layout should not go into the spec." Proposed text: "The primary span
  is the binder parameter that lacks the bound. The headline names the impl and the supertrait."
- **AI/ML** (stays A): "The binder is the repair in the common case, and it is the edit that the help applies. I accept
  plt's concern in full [...]. For models, one fixed span means the spec example and the compiler output agree, so they
  teach the same shape." And: "The layout of the secondary labels stays with the impl ticket. That also covers min's
  concern about later tooling changes."
- **Minimalism** (moves to A in its minimal form): "The repo facts weaken my C. The catalog already pins spans in single
  phrases [...]. My worry was the spec freezing a whole layout, not one phrase." And: "I move to A in its minimal form,
  meaning one span phrase in the catalog row with labels left out of normative text. If A means writing the full label
  layout into sections/, I stay at C."

Position changes in Phase D: PLT moves from B to A, with the headline condition and the trait-reference fallback.
Minimalism moves from C to A, on the condition that only one span phrase goes into the catalog row.

Re-vote options: A — one clause in the E0911 catalog row: primary span on the binder parameter that lacks the bound
(not the whole binder list); the headline names the failed impl and the supertrait; when the obligation does not end
at a binder, the primary span is the trait reference, as probe d; label layout goes to the impl ticket, and §3.6 gives
the example with no layout rules. C — the spec fixes only the code (E0911) and the place (the subtrait impl header).
Phase C option B was not listed, because its only voter moved to A.

**Re-vote (Q2):** A, 6-0.

- **Systems:** A — "One clause in the catalog row puts the caret where the Q5 help edits, so the CLI, the LSP quick-fix and `blink fix` act on the same range. plt's fallback to the trait reference covers the cases with no binder to edit, such as a concrete argument like `impl Ord for H[F]`, so every E0911 has a defined span. Leaving the label layout to the impl ticket keeps later diagnostic work out of the spec, which was my Phase C concern." Concern: "The checker must report which binder parameter failed, not only that entailment failed. If it returns a bare yes or no, the impl will put the caret on the whole binder list or on the trait name, and the output will not match the catalog row."
- **Web/Scripting:** A — "The caret lands on the one parameter the help edits, and the headline names the impl and the supertrait that failed, so the user sees both the cause and the fix at once. plt's fallback to the trait reference covers the cases with no binder to edit (`impl Ord for H[F]`), so no case is left undefined. It is one clause in a catalog row, which follows E1011 and E0843 and keeps the label layout out of the spec." Concern: "The `where`-clause case (sys: caret on the `where` bound) is not in the clause, so the impl could put the caret on the binder while the help edits the `where` clause."
- **PLT:** A — "The caret marks the edit that the help offers (Q5), and the headline names the failed judgement, so no information about the cause is lost. The fallback to the trait reference closes the gap where no binder can carry the missing obligation, such as `impl Ord for H[F]`. With the fallback, the rule gives a span for every way E0911 can fail. One clause in the catalog row follows the precedent of E1011, E0843 and E1022, and leaves label layout free." Concern: "\"The binder parameter that lacks the bound\" assumes each missing obligation reduces to a single parameter. When one supertrait obligation needs bounds on two parameters (`impl[K, V]` needing `K: Eq` and `V: Eq`), the rule must still give exactly one primary span, for example the first such parameter in source order."
- **DevOps/Tooling:** A — "One clause in the catalog row puts the CLI caret, the LSP range and the `blink fix` edit on the same token, which is the binder parameter the Q5 help edits. The headline names the failed impl, so the caret cannot read as a syntax error. plt's fallback to the trait reference covers the cases where no binder exists, such as `impl Ord for H[F]` with a concrete argument. Without it, those cases would have no defined span. Leaving the label layout to the impl keeps later tooling work out of the spec." Concern: "When the impl states its bounds in a `where` clause, the \"binder parameter\" wording could leave unclear whether the caret marks `T` in `[T]` or the `where` clause, so the impl ticket and a test row must pick one."
- **AI/ML:** A — "The caret, the help's edit and the spec example then all point at the same token, so a model learns one fixed shape and edits the right place. plt's fallback (the trait reference when the obligation does not end at a binder, as with `impl Ord for H[F]`) closes the one case that A did not cover. One clause in the catalog row follows the E1011 and E0843 pattern and fixes no label layout, which meets min's terms." Concern: "Where the impl uses a `where` clause, \"the binder parameter\" can be read as either the binder or the `where` item, and the impl ticket should choose one so that the CLI and the LSP agree."
- **Minimalism:** A — "A as worded meets my condition. It is one clause in the catalog row, and the secondary label layout stays out of normative text, so §3.6 gains an example and no layout rules. This follows the existing span phrases in the catalog (E1011, E0843, E1022) and adds no new kind of spec text. plt's fallback to the trait reference also covers cases the binder phrase leaves undefined, so the clause is complete." Concern: "Later diagnostic work may add label rules to this row one at a time until it reads like the full layout I voted against. Each addition should have to justify itself."

Open points the re-vote leaves to the impl ticket: the caret position when the impl writes its bounds in a `where`
clause (Web/Scripting, DevOps/Tooling, AI/ML), and which parameter gets the primary span when one supertrait needs
bounds on two parameters (PLT: "for example the first such parameter in source order"). The spec text does not fix
either.

### AI-First Review

| Criterion | Result |
|---|---|
| Learnability | Pass: the rule is the one Rust, Haskell and Swift use; models already write `impl<T: Ord> Ord` |
| Consistency | Pass: the catalog's "every impl must satisfy each supertrait" now holds for a polymorphic impl, and the *Operations on `Self`* claim holds |
| Generability | Pass: one bound on the binder fixes each case; `T: Ord` also passes, so the natural form is accepted |
| Debuggability | Pass: one error at the impl header, the caret on the parameter to edit, and a machine-applicable help; no use-site error that names a bound the caller never wrote |
| Token Efficiency | Pass: no new syntax; at most one extra bound per impl |

### Final Spec

```blink
type H[T] { v: T }

impl[T: Eq] Eq for H[T] { fn eq(self, o: H[T]) -> Bool { self.v == o.v } }

impl[T] Ord for H[T] { ... }         // E0911 -- H[T] is Eq only where T: Eq
impl[T: Eq] Ord for H[T] { ... }     // OK
impl[T: Ord] Ord for H[T] { ... }    // OK -- T: Ord gives T: Eq
```

```
error[MissingSupertraitImpl]: impl Ord for H[T] requires H[T] to also implement supertrait `Eq` (trait Ord: Eq)
 --> h.bl:5:6
  |
5 | impl[T] Ord for H[T] { ... }
  |      ^ `H[T]` is `Eq` only where `T: Eq`
  |
  = help: add the bound: `impl[T: Eq] Ord for H[T]`
```

- **Rule (Q1).** An impl of a trait with supertraits proves each supertrait for its receiver type, using only the
  bounds it writes (binder or `where` clause) and the supertraits of those bounds. Else E0911 `MissingSupertraitImpl`
  at the impl header. A concrete impl is the case with no binder. No use site checks it again.
- **No implied bounds.** The compiler never adds a bound that the user did not write.
- **Derived supertrait impl.** Same rule, code, message and help as a hand-written pair; a label or note points at
  the `@derive(...)` attribute.
- **Span (Q2).** One clause in the E0911 catalog row: primary span on the binder parameter that lacks the bound; the
  headline names the failed impl and the supertrait; when the obligation does not end at a binder (a concrete argument,
  or no impl of the supertrait at all), the primary span is the trait reference. Label layout is not spec text.
- **Rollout (Q3).** Hard error at once. No warning release.
- **Auto-derived `Eq` (Q4).** The `Eq` that `@derive(Ord)` or `@derive(Hash)` adds carries the bounds that
  `@derive(Eq)` would carry.
- **Help (Q5).** The help is machine-applicable and adds only the bounds the impl's own bounds do not already give, in
  the form the impl already uses (`: Eq`, ` + Eq`, or a `where` item). Minimalism dissents: the form belongs to
  `blink fix`.
