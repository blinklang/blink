[< All Decisions](../DECISIONS.md)

# `assert_panics` Closure Fence (Test-Only Helper Extraction) — Design Rationale

The ticket asked for `@test_only` with transitive propagation through the call graph, so
that a helper `fn` could arm an `assert_panics` catch frame. No panelist proposed it. The panel
kept the fence lexical, documented the closure shape that already works, deleted a false
rationale from §2.20, and recorded eleven defects it found in the surrounding surface.

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in
independent-proposal → debate → vote → focused re-debate → re-vote rounds.

#### Phase A — Independent proposals

- **Systems:** "**Reject transitive `@test_only` propagation of `assert_panics`.** The ticket
  asks to move the arming site into a user `fn`. That converts a statically decidable fence into
  an undecidable one, and converts E0834 from a compile error into undefined behavior. The
  friction is real but the ticket has the extraction axis backwards." … "I propose **SYS-E** …
  **SYS-A** … and **SYS-B** … I **withdraw SYS-C** and I **reject SYS-D**, which is what the
  ticket literally asks for."

- **Web/Scripting:** "**Do nothing structural. Reject `@test_only` in every form, declared or
  inferred.** Spend the effort on the diagnostic and on one spec pattern that already works and
  is not written down. Then clean up the undocumented and unimplemented annotation surface, which
  is the actual defect this ticket led me to." … "I hold this position even though I am the
  panelist who normally argues loudest for ergonomics. The reason is that the friction in the
  ticket is one line of duplication in a same-file context, and every fix costs a newcomer at
  least three new concepts plus a silently-forgettable annotation."

- **PLT:** "**Reject `@test_only` transitive propagation.** It is unsound as an annotation and
  non-modular as a reachability analysis. There is no third reading of \"transitive propagation\"
  that is both." … "But **\"do nothing\" is not the answer either**, because the tree currently
  ships five defects that this ticket sits on top of. Close the gap by making the fence's
  contextual nature *normative*, fixing two Diagnostic Discipline violations, spec'ing the
  undocumented annotation that already ships, correcting the error catalogue, and opening a
  separate ticket for a spec claim the compiler does not implement. Record the one sound
  extraction shape as gated future work."

- **DevOps:** "I reject the shape the ticket proposes. I do not reject the problem." …
  "`@test_only` with transitive propagation is a bad design for my domain. It moves the error away
  from the mistake. It needs new annotation surface that this toolchain cannot diagnose, cannot
  order in the formatter, and cannot repair in the LSP. It also needs a test build mode that does
  not exist." … "The extraction the ticket asks for already works today. I ran it. The user does
  not know it works, because the E0833 diagnostic does not tell them. That is a diagnostic defect,
  not a language gap. I propose we repair the diagnostic and document the shape." … "I also found
  a hole in the fence. `blink check` accepts a program that stores an armed `assert_panics` catch
  frame in a module-level variable and calls it from a regular `fn`. This is the exact leak that
  F2 says the block form prevents. It changes the risk calculation for every proposal on the
  table."

- **AI/ML:** "## 2. Proposal P1 (my primary) — keep the lexical fence, close Q1 negative, pay the
  budget into E0833" … "**Q1: no.** **Q2: `@test_only` does not become a feature.** **Q3: E0833 is
  rewritten.** The language surface does not change. No new annotation, no new visibility state,
  no new pass." … "**The fence has no support in training data, so no model will ever guess it.
  Only a diagnostic can teach it.**"

- **Minimalism:** "**What I propose.** The panel rejects `@test_only`, rejects transitive
  propagation through helper `fn`s, and rejects any call-graph-based fence. `assert_panics` stays
  lexically fenced exactly as shipped. [This ticket] closes as resolved by M2+M3+M4, with the M6
  reopen gate recorded." … "### Why: the true cost of `@test_only` is four new concepts, not one
  annotation" … "This is the core of my objection. The ticket title makes `@test_only` look like
  one annotation. It is not. Trace what it drags in."

Phase A.5 (mechanical dedupe) recorded the result on Q1 as: "Q1-B. `@test_only` with transitive
propagation through the call graph. This is what [the ticket] asks for literally. **PROPOSED BY
NOBODY.** Explicitly rejected by all six."

#### Phase B — Debate highlights

- **DevOps**, opening its Round 1 reply with three withdrawals of its own text: "**(a) I withdraw
  D2 (the §2.20 \"Pattern 4\" blessing the test-local closure helper).** … The moderator reports
  that Systems and Web both moved toward D2 with an escape caveat attached. They moved toward a
  position its proposer no longer holds. I ask that the ballot record this, so the panel does not
  carry D2 on my authority when I have abandoned it. **(b) I withdraw the closure-naming `help:`
  line from D1** … **(c) My D3 proposed code number E1111 is wrong.** It is taken."

- **Web**, on why withdrawing a help line cannot fix the teaching surface: "**§2.20 Pattern 3
  already blesses the shape AI/ML withdrew.** … So \"do not teach the leak\" cannot be satisfied
  by withdrawing one help line from E0833. The spec teaches it already, in a neighboring pattern,
  for an unrelated reason. Any seat voting on Q4 on the grounds that the compiler must not name
  the escape shape should know that the spec names it first."

- **Systems**, on the shape of the Q1 agreement: "Q1-B has six rejections on six independent
  grounds, and mine is the only one that is a **soundness** objection rather than a cost
  objection. … If the decision record compresses the six rejections into a single \"too expensive\"
  line, it will lose the one reason that would still hold even if the feature were free."

- **Systems**, on the distinction that decided its own Q4 vote: "**prose can carry a caveat, a
  help line cannot.** That is the whole of my Q4 position."

- **Systems**, withdrawing its own proposed clause after fact F24: "**Short answer: my Q3 position
  does not change, but my proposed clause does.** I withdraw it as worded … F24c shows the
  conclusion is **scoped to one of three exits**, and stating it bare would overstate the safety
  of an escaped value. That is my error, not the moderator's, and it is the kind of error the
  clause was supposed to prevent."

- **PLT**, retracting its central Phase A claim in Phase D: "I wrote, one message ago: \"This is
  not a rule the checker has not got around to. It is a rule the type system currently cannot
  state.\" I checked the premise I skipped and it is wrong. **BLINK HAS A WORKING SCOPE-ESCAPE
  ANALYSIS.** `src/escape.bl`, 1295 lines, `analyze_escapes`. … **WHAT THAT COSTS ME.** My
  objection to a prohibition wording falls. … A prohibition is legitimate when an enforcement path
  exists, and one does. … **WHAT IT BUYS THE PANEL, which is more than it costs me.** [the escape-analysis ticket]
  should be re-scoped from \"needs an escape discipline\" to \"extend `analyze_escapes` to the
  `test` scope.\""

#### Phase C — Final vote

- **Q1: Does a fence-crossing helper need new language surface? (Q1-A: no new surface)** — **6-0 A**
  - **Systems:** A — "The fence governs only where a `setjmp` may be written, not which code may
    panic … A second dynamically reachable arming site therefore longjmps into a frame that has
    returned, which is undefined behavior, not a failed test. New surface here buys nothing that
    dynamic catching does not already give, and costs the decidability of the fence."
  - **Web/Scripting:** A — "Zero seats proposed the thing the ticket asks for, and my own corpus
    sweep found no instance of the predicted friction across 131 `assert_panics` occurrences. A new
    marker costs a newcomer at least three concepts … to save three inlined lines."
  - **PLT:** A — "`@test_only` would put a propagating marker on a declaration without putting it
    in the declaration's type, which is unsound by eta-expansion, and the reachability reading is
    non-modular in the MLton sense."
  - **DevOps:** A — "The extraction path already works on this tree … A new annotation would ship
    with an error that points at a declaration far from the mistake, no quick fix, and a formatter
    that already silently misplaces the name."
  - **AI/ML:** A — "The `@test_only` name also carries the `#[cfg(test)]` / `testonly` meaning from
    the training corpus — \"removed from the release build\" — which is not what it would mean here,
    and F10 shows Blink does not have that build mode at all. A name that asserts a false fact
    about the language is worse than no name, because it is copied."
  - **Minimalism:** A — "`@test_only` is not one annotation: it is an annotation plus a
    whole-program call-graph analysis plus a third visibility state plus a build mode plus a
    conditional-compilation facility, on a surface where 7 of 16 spec'd annotations have no
    implementation."

- **Q2: What does §2.20 say about the closure shape? (B = anchoring only; C = disclosed
  prohibition)** — **3-3 TIE → Phase D**
  - **Systems:** C, in Minimalism's fact-stating variant — "I accept Q2-C only with the defect
    named as fact … because an unenforced prohibition whose violation is a longjmp into a returned
    frame must not be written as if the compiler checked it." *(conditional: "If the panel adopts
    Web's prohibition framing instead of Minimalism's, my vote falls back to Q2-B.")*
  - **Web/Scripting:** C — "The shape works today, three seats want it, and users will find it
    whether or not we bless it — unblessed-but-working is the worst DX outcome, because it produces
    the Stack Overflow answer with no spec citation behind it, and those get copied for years."
  - **PLT:** *(dissent)* B — "a closure literal in direct argument position is never bound to a
    name, so condition (b) of my corrected closure theorem … holds by construction rather than by
    promise. … a non-escape proviso the compiler cannot check is the \"works-in-practice\" trade I
    am on this panel to refuse."
  - **DevOps:** *(dissent)* B — "a closure literal in direct argument position is never bound to a
    name, so there is nothing to store and nothing to return — leak-resistance by construction."
  - **AI/ML:** *(dissent)* B — "The direct-argument anchoring is the only rule in the ladder a
    model can check against the code it is emitting … Q2-C's non-escape proviso is unenforced —
    `leak.bl` checks `ok` today — and an unenforced prohibition in a spec is a rule a model cannot
    verify and will therefore violate silently."
  - **Minimalism:** C — "Each rung of this ladder removes a falsehood or a silence rather than
    adding a concept, so the ladder is subtraction dressed as prose and I take all of it. … The
    non-escape sentence must read as a fact plus a named defect, because a spec rule saying \"must
    not be stored\" is a typing rule no checker can see, which §3.1 rule 2 forbids."

  *The mechanism three seats voted on — that a closure literal in argument position cannot escape —
  was refuted after the ballot by fact F34, which the moderator verified with two probes that both
  report `ok`. Four seats had rested Phase C reasoning on it.*

- **Q3: Is §2.20's "why a block, not a closure" rationale correct as shipped? (C = replace with
  M3's text, keep sentence one, enforced rule first)** — **4-1-1 C**
  - **Systems:** *(dissent)* D — "F24b shows the tree does not hold the property the replacement
    text would describe … The `AssertPanics` lowering is deleted from this tree and will be
    rebuilt, so the invariant can be stated as a requirement before the code that must satisfy it
    is written, which is the cheapest moment it will ever have."
  - **Web/Scripting:** *(dissent)* B — "sentence one is true in isolation, but it is one half of a
    two-sentence rationale whose other half taught the wrong inference, and leaving the surviving
    half next to Q2-C's newly blessed local closure invites the same reader to re-derive it."
  - **PLT:** D, resolving to C by its own stated conditional — "If the moderator reads Q3-D as
    replacing rather than including Q3-C, then D as tallied would delete a true sentence, and my
    vote in that reading falls back to C." *(The ballot drafted Q3-D on top of Q3-B, not Q3-C — a
    moderator drafting defect, recorded.)*
  - **DevOps:** C — "C then keeps a sentence PLT verified as TRUE, and I will not vote to delete
    true text when only the inference drawn from it was invalid. I reject D: per F24b we would be
    writing a normative requirement the binary does not meet, which is a knowingly-created
    spec-versus-implementation divergence in the very change that fixes one."
  - **AI/ML:** C — "Sentence one is worth keeping precisely because it names the mechanism of the
    leak: closures are first-class values, which is why a closure *operand* was rejected, and also
    why the block form does not by itself prevent escape when the closure *containing* the block is
    a value."
  - **Minimalism:** C — "D converts a description into a normative obligation the tree does not
    meet today (F24b), which manufactures a second F10 — a spec clause the compiler violates — and
    F10 is the exact debt this panel spent Phase A discovering."
  - *Soft consensus, Phase D skipped:* DevOps's Concern supplies the remedy the majority adopted —
    "the enforced-rule sentence must sit between it and the non-guarantees, not after them" — and
    both Minimalism and DevOps endorse Systems' dissent as a ticket against the rebuilt lowering.

- **Q4: Does E0833 get a repair that exists? (A = "extract the code under test" named at the error
  site)** — **3-2-1, no majority → Phase D**
  - **Systems:** A — "A help line cannot carry the non-escape caveat that makes a closure shape
    safe, so a help line must not name one; prose in §2.20 can."
  - **Web/Scripting:** *(dissent)* B — "a help line that compiles as written is three lines for one
    repair — and my own rule … is that the help names only what §2.20 blesses AND only what has
    been verified to compile as written."
  - **PLT:** *(dissent)* B — "`diag_explain` text is a string literal in `src/diagnostics.bl` that
    no gate compiles, so an inlined help line creates a second, unchecked copy of the very example
    class that produced five spec defects."
  - **DevOps:** A — "A … names the one repair that is true whichever way [the escape-analysis ticket] goes — extract the
    code under test — which is also the only shape in the whole option space that works ACROSS
    `test` blocks, the case the ticket actually names."
  - **AI/ML:** *(dissent)* C — "a model in a generate-check loop acts on the text in front of it and
    does not reliably follow a section pointer. … If the diagnostic points at a pattern without
    showing the one spelling that works, the panel will have answered the ticket with a repair the
    asker cannot execute."
  - **Minimalism:** A — "the diagnostic names the one repair that converges and the spec carries
    the full menu; Q4-A's first line converges in every case, including the cross-test case no
    closure shape can reach."

- **Q5: `@expect_panic` on a plain `fn` (A = reject at the annotation, at the parser, reusing
  E1110)** — **6-0 A**
  - **Systems:** A — "A `fn` body is never lexically inside a test, so the synthesized
    `AssertPanics` node always hits E0833 and names a construct the user did not write, which is a
    live D7.1 violation in shipped code. … This is also what rustc does with `#[should_panic]` on a
    non-test function."
  - **Web/Scripting:** A — "Today a `@expect_panic fn` desugars and then surfaces E0833 pointing at
    an `AssertPanics` node the user never typed, which is the worst class of error message — one
    about a construct absent from their source."
  - **PLT:** A — "I verified the layer — `src/parser.bl:1239` emits E1110 today — so \"reuse E1110\"
    and \"at the parser layer\" were never competing options, and my Phase A text spelling one
    concept two ways was incoherent."
  - **DevOps:** A — "E1110 is `UnexpectedAnnotation`, \"an annotation was used in a position where
    it is not supported\", and `@expect_panic` on a non-test `fn` is precisely that."
  - **AI/ML:** A — "the mistake is visible in the declaration the model just wrote, so the report
    lands on the token the model must change."
  - **Minimalism:** A — "E1110 already exists, already fires at the parser … a new code would be a
    second name for a diagnostic we ship."

- **Q6: Unknown-annotation diagnostic (C = out of scope, file separately)** — **4-2 C**
  - **Systems:** C — "F25 removed the number Q6-A was written around, so voting A here would decide
    a code we cannot name."
  - **Web/Scripting:** C — "a defect this size must not ride along inside a helper-ergonomics
    decision, because the design I want … is a design, not a number."
  - **PLT:** *(dissent)* A — "\"Unknown annotation NAME\" and \"known annotation in an unsupported
    POSITION\" are different judgements with different premises and different repairs … deciding the
    shape now and deferring only the number costs nothing and stops the question being reopened."
  - **DevOps:** *(dissent)* A — "only one is quick-fixable: \"wrong place\" is a scope move the LSP
    cannot express, while \"wrong spelling\" is a replacement over the diagnostic's own range and
    works today."
  - **AI/ML:** C — "a check shipped before that reconciliation rejects programs that follow the
    written spec."
  - **Minimalism:** C — "a panel that has just declined an addition should not ship an adjacent one
    on the way out."
  - *Soft consensus, Phase D skipped:* all four C Concerns say the follow-up ticket must be cut in
    this decision or it will be lost. Minimalism: "Filing it separately risks it never being filed
    at all, so the decision record must name the ticket rather than say \"out of scope\" and stop."

- **Q7: Sequencing and the reopen gate (option 3 = merge M6 with PLT item 9; keep Web's ledger out
  of the gate; Q7-D stands alone)** — **6-0 option 3**
  - **Systems:** 3 — "Binding them makes corrections wait on additions, which would block M2 and
    M3, whose whole content is making the spec true."
  - **Web/Scripting:** 3 — "I reverse my Round 1 merge of A+B+C and say so rather than defend it.
    Minimalism's objection is right and it lands on my own text."
  - **PLT:** 3 — "a correction restores agreement between spec and tree, an addition enlarges the
    surface both must satisfy, and they cannot carry the same burden of proof."
  - **DevOps:** 3 — "**MOVE from my Round 1 position, which was Q7-1** … a gate whose condition is
    an open-defect list never goes green … a ledger is a dashboard, a gate is a gate."
  - **AI/ML:** 3 — "blocking corrections behind a ledger is how 471 unchecked examples accumulated
    in the first place."
  - **Minimalism:** 3 — "Corrections do not carry the burden that additions carry; that asymmetry
    is the whole content of my seat, and inverting it here would make the panel's own output
    unshippable."

- **Sub-items** — **Q2-1 6-0 YES** (repair the unannotated closure parameter in §2.20's Pattern 1);
  **Q3-1 2-4 NO** (no thread-locality clause in §2.20); **Q3-2 6-0 YES** (the same correction lands
  in E0833's explainer); **Q3-3 6-0 YES** (record that §4.6.3's "exposes no user-nameable symbol"
  ground does not hold, amend nothing); **Q4-1 6-0 YES** (do not change E0827/`skip()`);
  **Q4-2 6-0 YES** (no LSP quick fix); **Q5-1 6-0 YES** (generalize E1110's message and explainer
  off type aliases); **Q5-2 6-0 YES** (`@expect_panic` must be spec'd, not deleted);
  **Q6-1 5-1 YES** (warning severity, DevOps dissenting); **Q6-2 6-0 YES** (do not reserve
  `@test_only` by name); **Q7-1a 6-0 YES** (the §2.20 release-build stripping claim is false and is
  filed separately); **Q7-1b 6-0 YES** (spec examples must compile as written); **Q7-1c 6-0 YES**
  (a ratchet, not a hard gate, over the 471 `blink` blocks in `sections/`).

#### Phase D — Round 2 (Q2 and Q4)

Phase D re-debated Q2 and Q4 only. It ran under one hard cap of one round, and it surfaced eleven
verified facts that landed after the Phase C ballot. Three of them moved votes: **F34** (the
direct-argument non-escape mechanism is false — both probes report `ok`), **F39** (Blink has a
wired 1295-line `analyze_escapes` that fires on closure capture, gated so it never runs for a test
block), and **F41** (of the three enumerated escape routes, "return it from a `fn`" is not
expressible).

**Q4 — closed 6-0 at Q4-A-devops+A4**, the corrected A-prime carrying AI/ML's lexical/not-call-graph
note, with Systems' three added items: the explainer's stated repair becomes callee extraction and
appears first, the `skip()` analogy is removed, and the checking rule extends to `diag_explain`
bodies.

**Q2 — rung closed 6-0 at C.** Three of the three seats that had voted B moved. PLT's own account
of the move is quoted under Phase B above. The rung then needed a text, so the moderator ran a
ranked re-vote over the live wordings.

- **Q2 base text: Q2-E-plt + A1 — 5-1** (Minimalism dissent)
  - **Systems:** first — "**Q2-E is the only live text that states the correction.** Its middle
    sentence — \"an argument is bound to the callee's parameter, and a parameter's type does not say
    whether the callee keeps the value\" — is a statement about calling convention and it is true.
    Nothing else on the ballot says it, and if the spec does not say it, readers re-derive the false
    property from the recommended shape, because the recommended shape looks like it is the reason."
  - **Web/Scripting:** first (after its own Q2-F-web drew no second seat) — "Q2-E's first paragraph
    is the highest-value sentence in the whole Q2 set for that reader: \"the compiler checks where
    the construct is written, not where it runs, and both forms are accepted deliberately\" closes
    the Stack Overflow question — why is this rejected in my helper and fine in my closure — before
    it is asked."
  - **PLT:** first — "Q2-E is also the only text that states the actual typing rule. The fence is
    SYNTACTIC: well-formedness of `assert_panics` is decided by the lexical context in which the
    term is written, not by the context in which it is evaluated. That single sentence is what makes
    the rest of the section compose."
  - **DevOps:** first — "**ONLY Q2-E IS A SECTION.** … A destination that is four sentences of
    don'ts, with no lexical statement and no shape, does not answer the question the note sent the
    user to ask." And: "**IT IS THE ONLY TEXT THAT SAYS THE WORD THE DIAGNOSTIC SAYS.**
    Q4-A-devops+A4's carried note is \"this fence is lexical, not call-graph.\" … Same word, same
    claim, in both artifacts, on the same decision."
  - **AI/ML:** first — "a locally checkable rule that does not imply the safety property is a rule a
    model will check, pass, and be wrong. That failure is silent, plausible and repeated at scale,
    which is the worst shape a generation hazard can have."
  - **Minimalism:** *(dissent)* ranked Q2-C-aiml+A1+A2 first — "Q2-E-plt is the largest surface for
    the least new content … I rank it below Q2-C-sys on the asymmetry that governs my seat: a
    missing clause is repaired by a later editorial pass, shipped surface is not."

- **Amendment A1 (strike "return it from a `fn`" from the enumeration) — 6-0.** Minimalism:
  "An enumeration that lists a route the compiler already refuses is false on the first thing a
  reader tries, and it discredits the two clauses that are true."

- **Consequence clause, A2 (unconditional) vs A3 (scoped to the failing assertion) — 3-3, then
  5-1 for A3** after fact **F46** established that the two halves of `assert_panics` longjmp to
  different buffers: the passing half lands in `__blink_panic_jmp`, a `__thread` pad the construct
  arms inline in its own frame, while both failure paths (E0831, E0832) route through
  `__blink_assert_fail_intro` into `__blink_test_jmp`, a bare `static` set only in the runner's
  per-test loop. The undefined half is the failing half.
  - **Minimalism:** A2 → **A3** — "So my ballot's \"what is missing outside a running test is the
    frame, not the outcome\" is wrong: two frames are in play, the armed one is present because the
    closure arms it, and only the failing half reaches for the runner frame that is gone. A2 is not
    merely broader than the record — it calls the defined half undefined, which is the same failure
    mode I ranked F41 on."
  - **PLT:** A2 → **A3**.
  - **DevOps:** A3 — "**A3 IS NOT OPTIONAL ON ANY TEXT.** … Q3 carried on deleting a false sentence
    from §2.20. Replacing it with a differently false one is a bad trade, and no gate can catch
    prose."
  - **AI/ML:** A3 — "A3's claim rests only on the failure-path chain … all of which is readable in
    the tree and needs no emit site. A2's EXTRA claim — that the passing call is also undefined — is
    the half that depends on where the construct's inline setjmp lands, which is exactly what F46
    could not execute."
  - **Web/Scripting:** A3 — "A2 asserts undefinedness over every call of an escaped closure, so a
    reader who tries the cheapest thing, watches a passing assertion behave normally, and concludes
    the sentence is alarmist is the F41 failure repeated one clause later."
  - **Systems:** *(dissent)* A2, correcting its own stated mechanism on the record — "CORRECTION TO
    MY OWN BALLOT, ON THE RECORD. The mechanism sentence in my REASONING section is backwards and
    F46 is right. … My \"indicts the case closest to inert\" was exactly inverted. MY PREFERENCE DOES
    NOT CHANGE: **A2**. The reason changes, and it is not the one I gave. 1. A3 promotes an
    implementation choice to a spec guarantee by negative implication. … A sentence that scopes
    undefinedness to the failing assertion tells a reader that an escaped closure is fine so long as
    its assertion passes. That is a guarantee the implementation would then owe them, bought with no
    deliberation, on a detail the rewrite is free to move. 2. A rule keyed on a run-time outcome is
    unactionable at the site where the reader acts."

**Limit on F46, recorded because two seats asked for it.** F46 was read from
`bootstrap/runtime_core.h` and `bootstrap/runtime_test.h` plus the normative decision record, and
**it could not be run**: this tree cannot emit C, and `rg __blink_panic_jmp src/` returns nothing
because the codegen rewrite removed the emit site. Web: "Its load-bearing inference is that the pad
lands in the CLOSURE'S frame. The emit site is gone, so that rests on prose … The inference is
sound and it is not run." PLT asks that A3's scoping be re-checked once the emitters land.

### Final Spec

The fence is unchanged. §2.20 gains one subsection describing the shape that already works:

```blink
import std.testing

fn nth(xs: List[Int], i: Int) -> Int {
    xs.get(i).unwrap()
}

test "nth rejects out-of-range indices" {
    let xs: List[Int] = [10, 20, 30]
    testing.for_each([
        ("negative", -1),
        ("past end",  3),
    ], fn(case: Int) {
        assert_panics {
            let _ = nth(xs, case)
        }
    })
}
```

Locked design points:

- **No new language surface.** No `@test_only`, no transitive propagation, no call-graph fence, no
  new visibility state, no new build mode. The ticket's literal request was proposed by nobody and
  rejected by all six seats.
- **The fence is lexical, and it is now stated as such.** The compiler checks where `assert_panics`
  is *written*, not where it runs. A closure written inside a `test` block may therefore contain
  `assert_panics`.
- **Both spellings are accepted deliberately** — the closure passed directly as an argument, and the
  closure bound with `let` first. Both were verified with `blink check`.
- **The direct-argument form carries no leak resistance.** An argument is bound to the callee's
  parameter, and a parameter's type does not say whether the callee keeps the value. Four seats had
  reasoned from the opposite; fact F34 refuted it with two probes.
- **The closure must not outlive its `test` block, and the compiler does not check this.** The
  prohibition ships with its own non-enforcement disclosed. If the assertion inside an escaped
  closure fails when it is called from outside a running test, the behaviour is undefined.
- **The false rationale at §2.20 is deleted.** "A recognized block is never a value, so the panic
  continuation is observable only by the test runner" does not hold: the counter-example is a program that
  stores an armed catch frame in module-level state and calls it from a plain `fn`. What the
  compiler enforces is where a catch frame is **created**.
- **§4.6.3 is not amended.** Its "exposes no user-nameable symbol" ground does not hold as shipped;
  that finding is recorded here and deferred to the escape-analysis follow-up (Q3-3, 6-0).
- **E0833's repair becomes one that exists.** "Extract the code under test" is named first, the
  `skip()` analogy goes, and the fence is described as lexical and not call-graph — in the
  diagnostic and in `blink explain` alike.
- **`@expect_panic` on a plain `fn` is rejected at the annotation**, at the parser, reusing E1110,
  whose message and explainer are generalized off type aliases. The annotation itself is spec'd,
  not deleted.
