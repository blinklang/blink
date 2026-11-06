[< All Decisions](../DECISIONS.md)

# Methods That Declare Their Own Type Parameters — Design Rationale

**Spec gap:** *Spec silent on a method declaring its own type parameters.*

Normative text: `sections/03_types.md` §3.6 *Method Type Parameters*, and §3.4 *Explicit Type Application* (the W0604 lint). Error codes: `ERROR_CATALOG.md`, E0906 (turned on), E0326 (new), W0604 (extended).

## The gap

`sections/` never showed a user trait or impl method that declares its own type parameters (`fn m[U](self, ...)`). The only generic-method signatures in the spec were the sealed built-in `Iterator` adapters (`fn map[U](self, f: fn(T) -> U) -> Iterator[U]`), and `Iterator` is not user-implementable. The general rule (*no erasure*, §3.4) covers a method by implication, because a method is a declaration. E0909 governs the binders of an impl and says nothing about the binders of a method inside it.

The ticket asked three questions:

1. May a method inside a polymorphic impl (`impl[T] Trait for List[T]`) declare its own binders, and are the impl binder and the method binders one monomorphization key or two?
2. May a trait default method declare its own binders, and does each impl get its own instances of that default?
3. Does explicit type application reach a method's own binders: `c.combine[Int](2, 3)`?

The ticket also blocked two check-clean rows: `impl Eq for P { fn eq[U](self, o: P) }`, reached by `a == a`, and `fn enter[U](self)`, reached by `with`. `U` is in no parameter and the trait method has no `[U]`: refuse the impl signature at check, or report `U` as under-determined?

The panel worked from four programs, measured on the compiler of the day:

- **m1.** `trait Comb { fn combine[U](self, a: U, b: U) -> U }` with `impl Comb for C`, called as `c.combine(2, 3)` and `c.combine[Int](4, 5)`. It compiled and printed `2` and `4`.
- **m2.** `impl Eq for P { fn eq[U](self, o: P) -> Bool { ... } }` and `a == a`. Check passed, and the build failed with an internal error.
- **m3.** `impl[T] Wrap for List[T] { fn wrap[U](self, u: U) -> (Int, U) { ... } }`. Check passed, and the build failed with an internal error.
- **m4.** A trait default `fn sh[U](self, u: U) -> Int { 7 }` that two impls (one polymorphic) omit. Both impls got E0900, a separate defect.

The facts the panel took from the spec, and did not vote on:

- No erasure: every binder a declaration introduces is in its monomorphization key.
- Brackets are the explicit form, and a binder the signature does not supply needs them at the call.
- W0604 "fires exactly when deleting the binder is a safe edit" (§3.4 *Explicit Type Application*).
- E0909: an impl binder that occurs in neither the trait nor the receiver is an error, because "impl selection admits no type-argument list, so no use site could ever repair the declaration".

## Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in independent-proposal, debate and vote rounds. Phase A produced six proposals. A mechanical dedupe found five points where all six agreed (C1 to C5) and four points where they differed (V1 to V4). Phase B ran one round, and all six panelists marked their position stable. Phase C was a silent vote on three questions. **Phase D did not run**: no question had a vote closer than 5-1 (Q1 6-0, Q2 5-1, Q3 6-0), so no tie needed a debate.

**A note on quotation.** Panelist text below is verbatim. Where a quote has an ellipsis ("…"), the panelist's words are cut there. No panelist text is reworded. Ticket identifiers and the paths of working files are not quoted.

### Phase A — Independent proposals

All six seats agreed on the behavior of the first five cases. In the dedupe, that became C1 to C5.

- **Systems** on who may declare binders and on the key:
  > "A trait method, an impl method and a trait default method may all declare binders. A method is a declaration, so its binders join its monomorphization key ("no erasure", decided)."

  > "The instance key is one flat tuple: (impl binders, method binders)."

  On the operator and `with` rows:
  > "Operators, `with`, string interpolation and `for` call only language traits (Eq, Ord, Hash, Add, Display, Closeable, Iterator). None of those methods declares a binder, so an impl that adds one is E0906 at the impl."

  On W0604:
  > "W0604 goes on the trait method declaration, because that is where the binder is removable."
- **Web/Scripting**:
  > "Trait method, impl method, and trait default method may all write `fn m[U](...)`. No new syntax, no new concept."

  > "`fn tag[U](self) -> Int` (U occurs nowhere) gets W0604 at the trait method, as a free function would."
- **PLT**, on why an impl must match the trait method:
  > "Under no erasure, using a `∀` needs a witness at each use. So an impl method must bind **exactly** the trait method's binders: the same count, matched **by position**, with the same bounds after renaming."

  On a name that repeats an enclosing binder:
  > "A method binder may not reuse the name of an impl binder or a trait binder (`impl[T] .. { fn wrap[T] .. }`). That is an error at the method binder, because in the body one name would denote two variables."

  On W0604, the only seat that disagreed with the other five:
  > "W0604 does not fire on a trait method's binder. That binder is interface: an impl body can depend on it, so it is never safe to delete, and W0604 exists only to mark a safe delete."
- **DevOps/Tooling**:
  > "Rule: the impl method's binder list must match the trait method's by count, by position and by bound. Names may differ (alpha-renaming is accepted)."

  On the help of E0301 for a method call:
  > "The help drops the receiver; it must print `c.mk[U]()`."
- **AI/ML**:
  > "A method's `[U]` is the method's own. It works like a generic fn's `[U]`. An impl copies the trait header, binders included."

  > "`trait T { fn tag[U](self) -> Int }` gets W0604 at the trait (U occurs nowhere)"
- **Minimalism**, on exact bounds:
  > "The bounds must be the *same*, not "weaker allowed". That choice is the easy one to relax later and the hard one to take back."

  On W0604:
  > "If `U` occurs nowhere, W0604 fires at the declaration."

So on V1 (does W0604 fire on a trait method's binder that occurs nowhere), five seats (systems, web, AI/ML, minimalism, DevOps) said yes at the trait method, and PLT said no.

### Phase B — Debate (round 1)

The dedupe listed C1 to C5 as agreed and V1 to V4 as open. All six seats agreed to C1 to C5 as written. On V2 all six agreed that a binder that repeats an enclosing binder name is an error. On V3 all six agreed that the help of E0301 prints the receiver. On V4 (how tools print the name of an instance) all six said it is out of scope for the spec.

The panel moved on V1. Four seats left their Phase A position and moved toward PLT's:

- **Systems:**
  > "I change my position and agree with plt, with one exception for `final`"
- **DevOps:**
  > "W0604's own rationale is "fires exactly when deleting the binder is a safe edit". Deleting a trait method's `[U]` is never safe: every impl must then drop its `[U]` (E0906 by C4), an impl body may use `U`, and every call that writes `[X]` turns into E0303."
- **AI/ML:**
  > "plt is right, and the W0604 rationale itself decides it: "W0604 fires exactly when deleting the binder is a safe edit"."
- **Minimalism:**
  > "The W0604 gate is "deleting the binder is a safe edit". For a trait method that edit is never safe by looking at one declaration: E0906 makes each impl repeat the binder, and an impl body may depend on it."

Systems and PLT then proposed the `final` exception:

- **PLT:**
  > "W0604 fires on a trait method's binder only when no impl can override the method, that is, on a `final` default. In that case the declaration plus its body is the whole method, and the single-declaration test holds."

  > "A lint whose fix breaks other code is a false positive, so the five-seat reading weakens the gate the spec states."
- **Systems:**
  > "Exception: a `final` default method has no override site, so its body is the only body that can ever exist. W0604 fires there by the normal rule:"
- **Web** kept its position in this round:
  > "plt is right that the edit is not "delete one binder and done": E0906 then makes each impl drop its copy. But the cost of NOT linting falls on every caller, forever:"

On V2, Minimalism asked for one general rule:
> "So the real gap is "a binder repeats a binder already in scope", and the method case is one instance of it."

On V3, DevOps gave the reason for the receiver:
> "`mk[U]()` with the receiver dropped does not compile (no free fn `mk`)."

On V4, Minimalism:
> "How ICE text, `--trace` names, hover and `blink query` print an instance is tool output, not language behavior."

### Phase C — Final vote

Three questions went to a silent vote.

#### Q1: the consensus package, C1 to C5, plus the receiver in the E0301 help (**6-0 A**)

The package, as put to the vote:

- **C1.** A trait method, an impl method and a trait default method may each declare their own binders.
- **C2.** One instance for each pair (impl binders, method binders). A default method is keyed for each impl too.
- **C3.** Brackets after a method name fill only the method's own binders, in order, on the receiver form, the trait-qualified form and through a bound. `Comb.combine[Int](c, 4, 5)` prints `4`. A wrong count is E0303.
- **C4.** An impl method's binder list matches the trait method's: the same count, matched by position, the same bounds. Names may differ. A mismatch is E0906 at the impl's binder list, one per method, and it suppresses the E0902 and E0903 cascade. Removing `[U]` is machine-applicable only when `U` occurs nowhere else in the impl method; otherwise it is a help only.
- **C5.** Operators, `with`, `for` and interpolation dispatch only to compiler-known trait methods with no binders, so the two blocked rows become E0906 at the impl. For a user trait method whose binder no argument fixes, a bare call is E0301 at the call, and brackets are the repair.
- **V3.** The E0301 help for a method call prints the receiver: `c.mk[U]()`.

All six voted A. Reasons, from the ballots:

- **PLT:** "C2 and C3 supply each type parameter at the place that declares it, so the rule composes: a call through a bound and a direct call build the same instance."
- **Systems:** "E0906 at the impl removes both ICE shapes (MonoInstanceNotRegistered and UnspellableCallType) at their source, so they do not move to the call site."
- **Web:** ""A generic method works like a generic function" is the whole lesson, and this package says exactly that."
- **DevOps:** "A help that prints the receiver is a repair that compiles, which §3.4 already demands."
- **Minimalism:** "The receiver in the E0301 help fixes a help text that cannot be pasted as it is."
- **AI/ML:** "The package adds no new syntax and no new code."

Concerns recorded: PLT and Minimalism said that exact-bounds matching may refuse an impl that would be sound with a weaker bound. PLT: "Relaxing it later breaks no program." Systems and Web said that the bounded-call and qualified-call defects in the compiler must be fixed before the spec text is true of the build.

#### Q2: W0604 on a trait method's binder that occurs nowhere (**5-1 C**; Web dissented)

The options: **A** (Web): W0604 at every trait method whose binder occurs nowhere. **B**: W0604 never fires on a method binder of a trait. **C** (Systems, PLT): W0604 fires only on a `final` default method; a required method or an open default gets none; an impl method gets none.

Votes: A: Web. B: none. C: Systems, PLT, AI/ML, DevOps, Minimalism.

Three seats moved from B in Phase B to C in Phase C:

- **AI/ML:**
  > "I revise my B1 position. A `final` default has no override site, so the W0604 test ("deleting the binder is a safe edit") applies to it exactly as it does to a free fn."
- **DevOps:**
  > "I voted B in Phase B because deleting an overridable binder is never a safe edit. A `final` default has no override site, so it is a free function in all but name"
- **Minimalism:**
  > "I change from B to C. C is not a new rule. It is the W0604 gate ("deleting the binder is a safe edit") applied as it stands."

The two seats that proposed C:

- **PLT:**
  > "A `final` default has no override site. Its declaration plus its body is the whole method, so the single-declaration test holds there and the lint is correct."
- **Systems:**
  > "That holds for a `final` default, because its body is the only body that can ever exist."

**Web's dissent**, from the ballot:
> "C4 makes the impl copy the trait's bounds exactly, so an unbounded `U` that occurs nowhere in the trait method cannot affect any impl's result (parametricity) — deleting it is meaning-preserving even though the impls must change too."

> "C fixes only the rarest shape (`final`); B fixes none."

Web's concern, on its own option:
> "The fix spans the trait and every impl, so it cannot be machine-applied, and an author of a published trait may have to live with the warning (or `@allow`) to keep impls in other packages compiling."

Concerns on C: AI/ML said a learner may not see why `Odd` gets no warning and `Odd2` does; the spec shows the cases side by side with the reason. DevOps and Minimalism said that a user who removes `final` sees the warning vanish, so the help must say that no impl can override the method. PLT said the rule should name `final` as the reason.

#### Q3: a binder that repeats a binder name already in scope (**6-0 B**)

The options: **A**: the rule covers a method binder that reuses an impl or trait binder name, and `fn f[T, T]` is a separate ticket. **B**: one rule, no two binders in scope share a name; it covers the method case and `fn f[T, T]`. Measured fact (Minimalism): `fn f[T, T](a: T) -> Int { 1 }` passed check at the time of the vote.

All six voted B. Reasons:

- **AI/ML:**
  > ""No two type parameters in scope share a name" is one rule with no exceptions, and it is easier to learn than one rule for the method case plus a separate ticket for `fn f[T, T]`."
- **PLT:**
  > "It also leaves `fn f[T, T](a: T)` in the language today, and that function has no clear meaning: which `T` is `a`'s type, and what does `f[Int, Str]` fill?"
- **Systems:**
  > "Whatever the nesting, it is one fault: one name with two slots in a mono key and two meanings in a body."
- **DevOps:**
  > "One rule, one code, one message: "`T` is already a binder here", with a note at the first one."

Concerns recorded, and how the spec text answers each:

- **DevOps:** "A shared rule could fire in the wrong place for a nested generic fn or closure if "in scope" is not tied to the declaration chain (fn, impl, trait)." The spec defines "in scope" as the binder lists of the declaration and of its enclosing impl or trait, and claims nothing about any other place.
- **Minimalism:** "If a later feature gives a nested generic scope, such as a generic closure, then "in scope" must state whether it shadows or errors. This rule picks error." The spec text does not make this claim for a later scope.
- **PLT:** "Code that compiles today with a duplicate type parameter in one list will break. It should follow the §8.16.1 rollout of a new error, not be a hard cut." The decision does not set a rollout (see below).
- **Systems:** "Widening the rule to all binder lists can catch an existing stdlib or test declaration. The implementation must sweep the corpus before it turns the error on."

### Phase D

Phase D did not run. No question had a vote closer than 5-1.

## Final Spec

The spec text is in `sections/03_types.md`. The rules, in order of the questions:

**Q1, the package.**

- **Who may declare binders (C1).** A trait method, an impl method and a trait default method may each declare their own binders.
- **Key (C2).** One instance for each pair (impl binders, method binders). A default method is keyed for each impl that inherits it. The body of a default is checked once.
- **Brackets (C3).** A list after a method name fills only the method's own binders, in order. This holds on a receiver, in the trait-qualified form and through a bound. A wrong count is E0303, and the impl binders are not in the count.
- **Impl method (C4).** An impl method repeats the binder list of its trait method: the same count, by position, with the same bounds. Names may differ. A mismatch is E0906 at the impl method's binder list, one error for each method, and E0902 and E0903 are not reported for the same fault. A fix that deletes `[U]` is machine-applicable only when `U` occurs nowhere else in the impl method.
- **Operators and the unfixed binder (C5).** An operator, a `with` block, a `for` loop and an interpolation call only compiler-known trait methods that declare no binder. The two blocked rows are E0906 at the impl. For a user trait method whose binder no argument fixes, a bare call is E0301 at the call, and the help prints the receiver (`c.mk[U]()`, and `Mk.mk[U](c)` for a qualified call).

**Q2, W0604.** W0604 fires on a trait method's binder only on a `final` default method, because the declaration and its body are the whole method and no impl can override it. A required method and an open default get none. An impl method of a trait gets none. This is the existing gate, "deleting the binder is a safe edit", applied to the one body there is.

**Q3, a unique name.** No two binders in scope share a name. The binders in scope are those of the declaration's own list and those of the impl or trait that encloses it. The error is `DuplicateTypeParam` (E0326) at the second binder, with a note at the first and the help "rename it". The writer chose a new code: no existing code covers a type parameter named twice (E0316 is for fields).

## Not decided here

- **Rollout of E0326.** `fn f[T, T]` compiles before this decision, so E0326 breaks code. The decision does not say whether the error starts at once or first as a warning. §8.16.1 *Rollout of a new error* governs that, and the test of §8.16.1 is the subject of a separate panel.
- **How tools print an instance** (V4). All six seats said that the text of an internal error, the names in `--trace` and the output of `blink query` are tool output and not language behavior. It goes to the implementation work as a note. One form that the panel liked keeps the two lists apart, impl first, so that a flat `wrap[Int, Str]` does not suggest two method binders.
- **Weaker bounds.** The rule demands the same bounds. A later decision may relax it, and that change breaks no program that compiles under this rule.
