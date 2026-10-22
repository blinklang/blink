[< All Decisions](../DECISIONS.md)

# Mutation Lints and the Dynamic-Binding Form — Design Rationale

**Resolution:** W0550 (`IncompleteStateRestore`) and W0551 (`UnrestoredMutation`) tell a binding pair from a speculative pair. A save is `let x = G` or `let x = G.clone()` of a module `let mut` `G`. A restore is `G = x`. A call is in a binding of `G` when an assignment to `G`, other than the restore, comes after the save and before that call. Neither lint checks a call for a pair that is in a binding at that call, and a binding pair does not make its function a speculative context. A warning that still fires has a `note:` that names the pair and its class, and one `help:` line that names the binding shape. Neither lint looks at exit paths; that gap is a follow-up.

**Vote:** N agreed 6-0 (no vote); Q1 A 5-1 (PLT dissent: S); Q2 H1 5-1 (Web dissent: H2); Q3 C2 + close gate 6-0 after 3-3 in Phase C.

## The Gap

§4.16.7 says W0550 and W0551 catch speculative lookahead (save, call, restore). It never defines "save", "restore" or "save/restore pattern". The same lints also fire on a second shape: save a global, assign it, call, restore it (the dynamic-binding form). There the other writes of the callee are the intended effect, yet both lints report them as unrestored. The only remedy was a function-wide `@allow`, which also silences real speculative bugs in the same function.

Measured on the compiler tree: 81 `@allow(UnrestoredMutation ...)` and `@allow(IncompleteStateRestore ...)` sites in `src/` and `lib/`. A script classified 51 as the binding form, 6 as save, call, restore with no assignment, and 24 as other. The counts are approximate.

Probe results (the checks the panel used):

| Probe | Program shape | Result before this change |
|---|---|---|
| p1 | save `g`, `g = 5`, call writes `{h, k}`, restore | W0551 on the call |
| p2 | same, callee writes only `g` | no warning |
| p3 | save `g`, call writes `{g, h}`, restore (no assignment) | W0550 |
| p4 | binding with `?` or early `return` between the assignment and the restore | no warning about the missing restore; W0551 for the callee write |
| p5 | a binder called from a function that saves `pos` | W0551 in both functions; write sets are gross |
| p6 | save `g`, `g = 5`, call writes `{g, h}`, restore | W0550 on the call |

The panel used these labels. **F19:** a restore missed on a `?` or early `return` exit. **F20:** write sets are gross, not net of restores. **F7:** the concern the 2026-03 panel accepted in the mutation-analysis decision ("A function that should have save/restore but doesn't yet won't trigger W0551").

### Panel Deliberation

The ticket, verbatim:

> **Spec: W0550/W0551 should tell a dynamic-binding scope from a speculative rollback**
>
> sections/04_effects.md §4.16.7. In the form: let s = G, then G = v, then f(), then G = s, the callee's other global writes are the intended effect, yet W0550/W0551 flag them as unrestored. The assignment between save and call marks the dynamic-binding form (save, assign, call, restore) apart from a speculative rollback (save, call, restore). Measured: in the compiler build, all 10 residual sites on the save/restore helper fns extracted for the warning-elimination audit are this form. Proposal for the panel: narrow the lint when the saved global is reassigned before the call.

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in independent-proposal, debate, vote rounds, with one extra round (Phase D) on the one question that Phase C left tied.

#### Phase A — Independent proposals (excerpts)

Each seat's first choice, with its test for the rule.

- **Systems** (sys-1: bound value vs cursor, by the callee's write set):

  > What really separates the two forms is what the callee does to G, not whether G got a new value.

  And on the ticket's rule:

  > The ticket's test (the saved global gets a new value before the call) also matches seek-and-try, the most common speculative shape in a parser

- **Web/Scripting** (web-1: tell the forms apart per save, by the assignment):

  > A call that comes after a save of `G` and before its restore is **in a binding scope of `G`** if a binding assignment of `G` comes between the save and the call. Otherwise the call is **speculative** for that save.

  > Cost: a speculative fn that by chance also assigns the saved global before the call (`let s = pos; pos = pos + 1; try_x(); pos = s`) now reads as a binding scope. I accept that. It is a lookahead that moves first, and its own author wrote a restore, so the lint adds little there. The decision record should say this out loud.

- **PLT** (plt-1: define the pattern, classify by an override):

  > *Override of G*: an assignment `G = e` in the region, before the first call, where `e` reads neither G nor a save of G.

  > The rule on `e` is important. A step such as `pos = pos + 1` reads G. It moves the state forward, so the pair stays speculative. The ticket's rule ("any assignment before the call") would make inline-advance lookahead a binding pair and silence the case that the lint exists to catch.

- **DevOps** (devops-1: judge each call by the pair around it):

  > A pair is a **binding pair** when the window assigns `G` a value other than `s` before the first call in the window. Else it is a **rollback pair**.

  > A fire must name the pair that put the call in scope, so the user can check the compiler's reading

- **AI/ML** (aiml-1: define the two forms; the binding form does not arm or fire either lint):

  > *Binding pair*: a save/restore pair with at least one other assignment to G between the save and the restore (conditional ones count). The span from that first assignment to the restore is the *binding span*.

  > One rule, one token test ("is G assigned between save and restore?"). A model can apply it from the spec text alone, with no training-data prior.

  AI/ML also proposed aiml-2: aiml-1 plus a new warning when a `?`, `return`, `break` or `continue` leaves a binding span before the restore.

- **Minimalism** (min-1: a binding is not a save; subtract it from the gate):

  > **Binding**: a save of `G` followed by any other assignment to `G` before its restore. The value `G` holds during the calls is the new value, not the saved one. The function says "run this code with `G = v`", not "try this and undo it".

  > It is a pure narrowing. The gate gets one more "not this" clause; the lint keeps its names, codes, suppression and `[lints]` keys (F5).

All six seats rejected a scoped-binding construct for this ticket (sys-2, plt-2, devops-2, web-2, aiml-3, min-2). DevOps, Web and Minimalism also rejected doing nothing (devops-3, web-3, min-3).

#### Phase A.5 and Phase B — Debate highlights

The moderator grouped the proposals. N: narrow both lints by the binding pair. N+X: N plus an exit-path warning in this change (aiml-2). Seven variations: V1 which assignment makes a binding; V2 where the assignment sits; V3 a function with both pair kinds; V4 a callee that also writes the bound `G` (p6); V5 an exit-path check now or later; V6 the text of a fire; V7 the follow-ups.

Key shifts:

- **AI/ML** dropped aiml-2:

  > I drop aiml-2 and support **N**. Five seats want the exit-path check designed on its own, and W0552 is taken. My condition: the F19 ticket is filed in the same change, and the decision record says in plain words that under N, p4 (`?` between the assignment and the restore) gives no warning at all.

- **Systems** withdrew its write-set condition and moved to the plain assignment test (V1):

  > I checked my condition against the tree, and F20 breaks it. `tc_infer_unhinted` binds `tc_construct_hint` and calls `infer_type`. `infer_type_uncached` binds `tc_construct_hint` itself (the D site at typecheck.bl:23707), so its gross write set contains `tc_construct_hint`. Under sys-1 that call reads as speculative and stays flagged.

- **PLT** and **DevOps** moved to the write-set condition in Phase B. PLT:

  > A dynamic binding is a reader effect: the callee *reads* G. If the callee *writes* G, the restore throws away a callee write. That is the rollback signature.

  DevOps:

  > sys's test is the only one that closes my own hole (`pos = pos + 1`, `try_x()`) and the seek-and-try hole together.

  DevOps asked for a count of the sites that stay flagged under the write-set rule: "If that number is large, the change does not reach its goal." Minimalism then named the poster child:

  > `tc_infer_unhinted` (src/typecheck.bl:4643) binds `tc_construct_hint` around `infer_type`. `infer_type` is recursive and reaches about ten other binders of the same global

  In Phase C Systems, Web and AI/ML cited this fact, and DevOps moved back to the plain assignment test (Q1 A).
- **V2 and V3 settled per call** (min conceded both):

  > I concede my "before its restore": a call before the assignment runs with the saved value, so for that call the pair is a rollback.

  > Checking each call against each speculative pair around it loses no real check.

- **V6 settled** on DevOps's note that names the pair and its class. Systems, PLT, DevOps, AI/ML and Minimalism opposed Web's help line with the exact `@allow(...)`; AI/ML: "It trains the habit this ticket removes: models copy the text of a help line."
- **Every seat** put the exit-path check (F19) in its own follow-up. Web on p4:

  > aiml's concern on p4 is fair, but note what p4 warns about today: the callee's write of `h`, not the leak of `g` (F19). The leak is silent today too. N removes an unrelated warning; it does not remove a leak check that exists.

Agreed by all six, with no vote (ballot "Agreed by all six"):

- **N**: narrow both lints by the binding pair; no exit-path warning in this change.
- The spec states the definitions of save, restore, save/restore pair and binding.
- Per call (V2): a call is in a binding of `G` when an assignment to `G` (not the restore) comes after the save and before that call. Calls before the assignment stay speculative.
- Per call (V3): in a function with both kinds of pair, each call is checked only against the speculative pairs around it. A binding pair does not arm the W0551 gate.
- A fire carries a note that names the pair and its class.
- The decision record states that under N, p4 (`?` between the assignment and the restore) gives no warning.

#### Phase C — Final vote

Each panelist voted alone on a written ballot. The common ground above was not on the ballot.

##### Q1 — Which assignment makes a binding — **A** (5-1; PLT: S)

Option A: any assignment to `G` other than the restore, between the save and the call. A callee that also writes `G` (p6) does not fire. Option S: as A, and `G` is not in the callee's write set.

- **Systems: A.**

  > S depends on write sets that count a global even when the callee restores it (F20), so it misreads the nested binders that make up most of the 51 sites. `tc_infer_unhinted` reaches other binders of `tc_construct_hint` through `infer_type`. A rule that keeps the bulk of the false positives does not fix the ticket. The case S protects (seek-and-try with a direct assignment to the cursor) does not occur in src/ or lib/. A is a local syntactic test with no extra pass cost. Once F20 gives net write sets, the F20 ticket can add the write-set condition as a precise refinement.

- **Web/Scripting: A.**

  > A reader checks A by eye: "did the code set G after the save, before this call?" S adds a condition on the callee's write set, which the reader cannot see at the call site. So the same five lines can warn or not, based on code in another file. min's fact makes S worse in practice. `tc_infer_unhinted` reaches other binders of the same global, so under S the most common binder in the compiler keeps its function-wide `@allow`, which is the problem we set out to fix. The holes A has (seek-and-try, step-then-try) have no sites today, and the spec states them.

- **PLT: S.**

  > A dynamic binding is a reader effect: the callee reads G and does not write it. A callee that writes G and then has that write thrown away by the restore is the definition of a rollback. S makes this one set lookup, with no guess about intent. A has false negatives on seek-and-try and step-then-try, the exact speculative bugs that W0550 exists to catch. S errs only toward false positives (nested binders of the same G), and the F20 fix removes those. When a lint must choose which way to be wrong, it must choose the false positive over a silent miss.

- **DevOps: A.**

  > In Phase B I moved to S, but only if the 51 binding sites mostly went quiet under it, and I asked for a count. min's fact answers that: `tc_infer_unhinted` (typecheck.bl:4643), the site the ticket names, reaches other binders of the same `tc_construct_hint`. So S keeps the main motivating site flagged until F20, and the `@allow` stays. web and sys also found no save of `pos` in src/ or lib/ that is followed by an assignment before a call, so the hole in A does not hit real code today. A is the rule a user can check from the source alone, and the pair note shows the class at every fire.

- **AI/ML: A.**

  > A model can apply A from the text of the function it writes: "is G assigned between the save and this call?" S makes the ruling depend on the write set of each callee, which the writer cannot see at the call site. Under S, nested binders of the same G read as speculative until F20 lands, and min names five such sites around `tc_infer_unhinted` alone. Those sites keep their `@allow`, and models keep copying it. A states its known hole in the spec, and no save of `pos` in src/ or lib/ falls into that hole today.

- **Minimalism: A.**

  > A is one visible test: "did the code set G after the save, before this call?" S adds a second condition that depends on a write set the reader cannot see. Because write sets are gross until F20, S keeps the false positives on the binders this ticket exists to fix: `tc_infer_unhinted` binds `tc_construct_hint` around a recursive `infer_type` that reaches other binders of the same global. A rule that removes less surface and is harder to predict loses on both counts.

##### Q2 — Help text on a fire — **H1** (5-1; Web: H2)

H0: the pair note only. H1: the pair note plus one help line that names the binding shape. H2: the pair note plus a help line with the exact `@allow(...)`.

- **Systems: H1.**

  > The pair note shows how the compiler read the code. One help line that names the binding shape tells the author how to write the code so that it compiles clean for a real reason. H2 prints a suppression as the fix, which is the habit that produced 81 function-wide `@allow` sites. Those sites mute real checks in the same function.

- **Web/Scripting: H2.**

  > When a warning fires, the user needs two exits: fix the save, or say "this write is intended". H2 gives the second exit as text they can paste, and the pair note already explains the class. H1 tells the user to add an assignment to change the class. That teaches people to add a fake assignment to quiet a lint, and `G = G` would do it.

- **PLT: H1.**

  > The pair note tells the reader how the compiler classed the pair. The help line tells them which shape the rule accepts as a binding. Together, a reader can predict the rule from the diagnostic alone. The help text must match the Q1 result. Under S, it must also say that a callee that writes the bound G is what makes the pair a rollback (sys's line). I oppose H2: a help line that offers `@allow` as the fix teaches people to suppress the lint, not to fix the code.

- **DevOps: H1.**

  > A user who meant a binding and gets a fire needs the one change that makes it clean: assign the global after the save. That is a fix with a reason, which a help line should give. H2 puts a suppression in every warning and teaches users to mute the lint; §4.16.8 already documents `@allow` for anyone who needs it. H0 is correct but leaves the user to find the rule in the spec.

- **AI/ML: H1.**

  > Models copy help lines nearly word for word, so the help line decides what code gets written next. H1 shows the shape that compiles clean for a real binding, so the model fixes the code instead of suppressing the lint. H2 puts `@allow(...)` in front of every reader, and that is the habit this ticket exists to remove. H0 leaves a model with no action to take for the non-speculative reading.

- **Minimalism: H1.**

  > One line that names the binding shape tells the user how the lint reads their code and what source change makes the warning go away for a real reason. H2 teaches the function-wide `@allow` habit that hid real checks on 51 sites. H0 is acceptable, but the pair note says what the compiler saw, not what the user can do.

##### Q3 — The scoped-binding construct — **3-3 in Phase C** (C1: Systems, PLT, AI/ML; C2: Web, DevOps, Minimalism)

C1: file it now as its own spec ticket, blocked by the F19 ticket. C2: no separate ticket; list it as a candidate answer inside the F19 ticket.

- **Systems: C1.**

  > A construct that restores G on every exit edge costs the same as the hand-written form on the normal path, plus one entry on the existing cleanup stack for panics. It closes F19 by construction and makes F20 exact, with no path analysis. If it is only a line inside the F19 ticket, the F19 design will default to "add a lint" before anyone weighs the construct. Its own ticket, blocked by F19, keeps both answers visible when that design happens.

- **Web/Scripting: C2.**

  > No user has asked for the construct, and the F19 ticket is where we find out whether bindings leak in real code. A spec ticket filed now only waits, and it suggests a decision about syntax before we have data. If F19 shows leaks, it can bring the construct forward as one of its answers.

- **PLT: C1.**

  > The construct is a language-spec question. It changes `with` or adds a form, and it gives a restore on every exit by construction. It belongs in its own spec ticket, not as one line in a lint ticket, where it would get no deliberation. Blocking it on F19 gives the timing I asked for: the panel decides it when the F19 design shows whether a path check alone is enough for binders.

- **DevOps: C2.**

  > The construct is one candidate answer to F19 among others, such as an exit-path warning. A spec ticket filed now, before the F19 design, asks the panel to compare syntax with nothing to compare it against. Putting it in the F19 ticket keeps one place where the options are weighed.

- **AI/ML: C1.**

  > A filed ticket is cheap and easy to find later. An idea listed inside the F19 ticket gets lost when the F19 ticket closes on a lint-only answer. Blocking it on F19 keeps the panel from deliberating it before there is data on real leaks. A construct is also the form a model learns most reliably, because it has one shape and restores on every exit, so the option should stay visible.

- **Minimalism: C2.**

  > A spec ticket for new syntax, opened before any data shows that F19 leaks happen in user code, is surface waiting for a reason. Listing it as a candidate answer in the F19 ticket keeps the idea in front of the people who design F19, on equal terms with a lint, at no extra cost. If F19 picks the construct, that ticket opens the spec work then.

#### Phase D — One focused round (Q3 only)

Every seat saw the same fear on both sides. The debate settled on a gate on the close of the F19 ticket.

- **Systems** opened with the shared concern:

  > Each C2 voter wrote down my concern as the risk of their own option. web: "the construct would then drop out of view with no ticket of its own". devops: "the construct can fade out without its own vote". min: "may pick a lint by default and never weigh the construct properly". All six seats fear the same failure, so the tie is about where the guard sits, not about the goal.

  And accepted either label with a gate:

  > **F19 ticket must hold:** "Candidate answers: (1) an exit-path warning on binding spans (aiml-2 text), (2) a scoped-binding construct that restores on every exit. This ticket does not close on a lint-only fix until the panel has voted (2) against (1) on the F19 data."

- **Web** proposed C2′:

  > the F19 ticket holds this text: "Candidate answers: (1) an exit-path warning on binding spans (aiml-2 text), (2) a scoped-binding construct (sys-2/plt-2 text). This ticket does not close until the panel votes on (2) by name. If (2) wins, file it as its own spec ticket at that time."

- **PLT** proposed C2+ and moved to it:

  > The F19 ticket cannot close until the panel records a vote between them, or a vote for both. A lint-only fix with no recorded comparison does not count as closure.

- **DevOps** moved to C1 with two pieces of text, then (in the vote) took AI/ML's gate. Its C1 text: "Close without deliberation if the F19 answer finds every missed restore of a binding on `?`, `return`, `break` and `continue` exits with no false positives. Otherwise deliberate."
- **AI/ML** proposed C2+, the gate text the panel adopted:

  > Candidate answers: (1) an exit-path warning on binding spans; (2) a scoped-binding construct that restores on every exit. Before this ticket closes, the decision record compares both on the F19 data (leak count in src/, lib/ and the corpus). If (1) wins, the record states why (2) is not needed. If (2) wins, open a type:spec ticket for it.

- **Minimalism** proposed C2′:

  > Before this ticket closes, its decision record compares a scoped-binding construct (sys-2/plt-2) with each lint answer. If the F19 data show binder leaks that a lint cannot cover with no false positives, file the construct as a `type:spec` ticket before closing.

##### Q3 — **C2 + close gate** (6-0)

All six voted C2 with the AI/ML gate (web's C2′, plt's C2+, min's C2′ name the same intent).

- **Systems: C2 + close gate, from plt (C2+). The F19 ticket names both candidate answers, the exit-path warning (aiml-2 text) and the scoped-binding construct (sys-2/plt-2 text). It cannot close until the panel records a vote between them. A lint-only fix with no recorded comparison does not count as closing it. If the construct wins, a `type:spec` ticket opens then. This matches my own Phase D text, and web, aiml and min proposed the same gate.**

  > My only reason for C1 was that the construct must not drop out by default. A required close gate on F19 guarantees that better than a blocked ticket, which can sit open while F19 closes on a lint. One ticket keeps the compare in one place, with the F19 leak data next to it. That data is what decides whether a restore on every exit, at almost no cost, is worth new syntax.

- **Web/Scripting: C2 + close gate (web C2′ = plt C2+ = aiml C2+ = min C2′; sys accepts C2 with this gate)**

  > Five seats now propose the same text in slightly different words: the F19 ticket names both answers (exit-path warning, scoped-binding construct), it cannot close until the panel records a vote between them on the F19 data, and if the construct wins a type:spec ticket opens then. That puts the comparison in one place and forces a vote, and it files no syntax ticket before there is data. For a developer reading `br` later, one ticket with one close rule is easier to follow than a blocked ticket and its parent.

- **PLT: C2 + close gate, from plt (C2+). This is the same gate as web's C2′ and aiml's C2+. The F19 ticket names both candidate answers in its body: an exit-path warning on binding spans, and a scoped-binding construct that restores on every exit. It cannot close until the decision record compares the two on the F19 data and records a vote between them. If the construct wins, a `type:spec` ticket opens then.**

  > The guarantee I want is that the construct gets a real vote. A gate on the F19 close gives that guarantee. A separate blocked ticket does not, because F19 can still close on a lint and leave the blocked ticket open forever. With the gate there is one record and one place where the options are weighed, and no spec ticket comes before there is data. The gate also makes my C1 closure condition unnecessary, because the comparison itself decides whether the construct is needed.

- **DevOps: C2 + the F19 close gate, from aiml (C2+), with the same intent as web's C2′, plt's C2+ and min's C2′.**

  > I moved to C1 only because a plain list line in the F19 ticket can be lost when the ticket closes. A close gate on the F19 ticket fixes that better than a second ticket does: F19 cannot close on a lint until the record compares both answers. A blocked ticket can still sit open after F19 ships a lint, as plt and min said. I take aiml's text because it names the data the comparison uses (the leak count in src/, lib/ and the corpus), so the vote rests on numbers, not taste.

- **AI/ML: C2 + close gate, from plt (C2+). This is the same gate as aiml's C2+, web's C2′ and min's C2′: the F19 ticket names both candidate answers in its body (the exit-path warning, aiml-2 text, and the scoped-binding construct, sys-2/plt-2 text). It cannot close until the panel records a vote between them. A lint-only fix with no recorded comparison does not count as a close. If the construct wins, a `type:spec` ticket opens then.**

  > Four seats now propose the same gate on the F19 close, and it answers the fear that all six seats named in Phase C. The gate forces the comparison at the point where data exists. A blocked ticket only waits, and it can still be passed over when F19 closes. One ticket with one close rule also gives a future reader (human or model) one record to find, not two that can drift apart.

- **Minimalism: C2 + close gate on the F19 ticket, from aiml (C2+; the same gate as web's C2′, plt's C2+ and my C2′). Text in the F19 ticket: "Candidate answers: (1) an exit-path warning on binding spans; (2) a scoped-binding construct that restores on every exit. Before this ticket closes, the decision record compares both on the F19 data (leak count in src/, lib/ and the corpus). If (1) wins, the record states why (2) is not needed. If (2) wins, open a type:spec ticket for it."**

  > One ticket holds one question, and the gate forces the comparison that all six seats feared would be skipped. aiml's wording ties the choice to a measured leak count, which is the evidence I asked for before any new syntax. It opens a construct ticket only if the construct wins, so no ticket waits as a promise of syntax.

#### AI-First Review

Learnability: one test per call ("is `G` assigned between the save and this call?") that a model applies from the text of the function, with no training-data prior. Consistency: W0550 and W0551 keep their names, codes, `@allow` names and `[lints]` keys. Generability: the common binder shape (save, assign, call, restore) compiles clean with no `@allow`. Debuggability: a fire names the pair and its class, so a user can check how the compiler read the code. Token efficiency: one note and one help line on a fire, no suppression text, no `@allow` on the 51 binder sites once the cleanup lands.

### Final Spec

```blink
let mut hint = -1
let mut depth = 0
let mut count = 0

fn infer() -> Int {
    count = count + 1
    hint + depth
}

fn infer_unhinted() -> Int {
    let saved = hint
    hint = -1              // an assignment after the save: a binding pair
    let t = infer()        // no warning: `infer` writes {count} on purpose
    hint = saved
    t
}

fn looks_ahead() -> Bool {
    let saved = depth      // no assignment after the save: a speculative pair
    let t = infer()        // W0551: `infer` writes {count}, and nothing saves it
    depth = saved
    t > 0
}
```

Locked points:

- A **save** of `G` is `let x = G` or `let x = G.clone()`, where `G` is a module-level `let mut`. A **restore** is `G = x`, where `x` holds a save of `G`. A **save/restore pair** is a save and a later restore of the same `G` in the same function.
- A pair is **in a binding** at a call when an assignment to `G` other than the restore comes after the save and before that call. A call before that assignment is not in the binding.
- A **binding pair** has at least one call between its save and restore and is in a binding at each. A **speculative pair** is every other pair.
- W0550 and W0551 check a call only against the pairs around it that are not in a binding at that call. A callee that also writes `G` (p6) does not fire. A binding pair does not arm the W0551 gate.
- A fire carries a `note:` that names the pair and its class, and one `help:` line that names the binding shape. No `@allow` help line (Q2).
- No change to W0550 or W0551 names, codes, `@allow` names, `[lints]` keys, or to write sets (§4.16.4).
- The spec text says nothing about a scoped-binding construct (Q3).

### Concerns

Panelists' own concerns on the winning options, quoted:

- **Systems** (Phase C, Q1): "A user parser that writes `pos = start` before a try-parse call loses W0550 without any sign. The spec must state that hole in plain words, next to the definition."
- **Web/Scripting** (Phase C, Q1): "A user writes a seek-and-try lookahead (`pos = start` then `parse_item()`), and A reads it as a binding and stays quiet about a stale global."
- **PLT** (Phase C, Q1): "Until F20 is fixed, many of the 51 sites stay flagged under S. min's `tc_infer_unhinted` chain is one example. So the `@allow` cleanup recovers less than the panel expects, and F20 must not be left to drift."
- **DevOps** (Phase C, Q1): "A seek-and-try rollback in user code (`pos = start` then `parse_item()`) gets no warning, and the spec text about this hole is the only thing that tells users."
- **AI/ML** (Phase C, Q1): "A seek-and-try function in user parser code (`pos = start` then `parse_item()`) will lose its W0550 for a stale side global, and nothing tells the user it did."
- **Minimalism** (Phase C, Q1): "A seek-and-try in user code (`pos = start`, then a call that moves `pos` and leaves other state stale) goes silent. The spec must state this hole plainly so nobody reads A as a soundness claim."

- **Systems** (Phase C, Q2): "Authors may add a dummy assignment to G only to make the warning go away, which turns a real rollback into a "binding" in name only."
- **Web/Scripting** (Phase C, Q2): "An easy `@allow` line could make people paste it without reading the pair note, so real rollback bugs get muted at the first fire."
- **PLT** (Phase C, Q2): "If the help text is worded for A and S wins, or the other way round, the diagnostic will contradict the rule in the spec."
- **DevOps** (Phase C, Q2): "The help line can push a user to add a dummy assignment just to silence a real rollback, so the wording must say "if the function sets a global for the call", not "to silence this"."
- **AI/ML** (Phase C, Q2): "A model that meant a rollback could read the H1 line as an invitation and add an assignment to G only to quiet the lint, which hides a real speculative bug."
- **Minimalism** (Phase C, Q2): "A user who meant a rollback may read the help as "add an assignment to make the warning go away", and so turn a real rollback bug into a silent binding."

- **Systems** (Phase C, Q3): "Under C2 the construct gets left out once a lint answer to F19 ships, and Blink keeps a heuristic where a guarantee costs almost nothing."
- **Web/Scripting** (Phase C, Q3): "The F19 ticket could close with a lint-only fix, and the construct would then drop out of view with no ticket of its own."
- **PLT** (Phase C, Q3): "If the F19 path check ships first and works, the construct ticket may sit open forever. Its closure condition must say "close if F19 covers binders with no false positives"."
- **DevOps** (Phase C, Q3): "If the F19 ticket picks a lint, the construct can fade out without its own vote, even if the F19 data show leaks in user code."
- **AI/ML** (Phase C, Q3): "The open spec ticket can read as a promise of new syntax and pull the F19 design toward the construct before the lint-only answer has had a fair test."
- **Minimalism** (Phase C, Q3): "The F19 ticket may pick a lint by default and never weigh the construct properly, which would leave the restore-on-every-exit problem only partly solved."

- **Systems** (Phase D, Q3): "If the compare is written as a single "considered and rejected" line in the decision record, the gate holds in name only. The record should measure (2) against (1) on the same leak count."
- **Web/Scripting** (Phase D, Q3): "The gate lives in ticket text, not in a tool, so someone can close F19 without the vote; whoever lands the F19 fix must check the record holds the comparison."
- **PLT** (Phase D, Q3): "The gate is only text in a ticket body. If the person who closes F19 does not read it, the construct still drops out. So the moderator must copy the gate text word for word into the F19 ticket when they file it."
- **DevOps** (Phase D, Q3): "The gate is only text in a `br` ticket, so a worker who closes F19 without reading the body can skip the comparison; the F19 ticket needs a checklist item that the closer must tick."
- **AI/ML** (Phase D, Q3): "`br` does not enforce a close condition written in a ticket body, so a later session could close F19 on a lint without the recorded vote. The moderator should copy the gate text into the F19 ticket word for word and add a `br note` that points to this decision."
- **Minimalism** (Phase D, Q3): "The gate binds only if whoever closes F19 reads it; a lint could still ship before the panel votes unless the F19 ticket is `type:spec` and goes through `/deliberate`."

### Known gaps and follow-ups

- **Seek-and-try and step-then-try read as bindings (Q1 A).** `pos = start` then `parse_item()`, and `pos = pos + 1` then `try_x()`, give no warning for stale globals that the callee writes. §4.16.7 states the hole. The moderator's facts from Phase B: "web and sys: no save of `pos` in src/ or lib/ is followed by an assignment to `pos` before a call."
- **No warning for a missing restore on `?` or an early `return` (p4).** Under this rule a `?` or `return` between the assignment and the restore gives no warning. That was already true before the change: neither lint looks at exit paths. §4.16.7 states the limit.
- **Write sets stay gross (F20).** A function that saves `pos` and calls a binder sees the binder's bound global in its write set (p5).

Follow-ups, in order:

1. **Implementation** of the narrowing in this decision.
2. **Exit-path check for binding spans** (F19). aiml-2 is the starting design: a warning when a `?`, `return`, `break` or `continue` leaves a binding span before the restore. The ticket body holds the close gate (Q3), word for word:

   > Candidate answers: (1) an exit-path warning on binding spans; (2) a scoped-binding construct that restores on every exit. Before this ticket closes, the decision record compares both on the F19 data (leak count in src/, lib/ and the corpus). If (1) wins, the record states why (2) is not needed. If (2) wins, open a type:spec ticket for it.

3. **Gross-vs-net write sets** (F20), after the exit-path check. Netting a restored global out of a binder's write set is sound only when the restore runs on every exit. Systems' refinement for that ticket:

   > Refinement for the F20 ticket: once a binder's net write set leaves out G, "the callee writes G, so the pair is speculative" becomes precise. That ticket should consider adding it then.
4. **Chore:** remove the `@allow(UnrestoredMutation ...)` and `@allow(IncompleteStateRestore ...)` sites that the narrowing makes stale.
