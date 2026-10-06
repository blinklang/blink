[< All Decisions](../DECISIONS.md)

# E0601 Field-Path Stores — Design Rationale

**Question:** The E0601 tag-mismatch store list (§9.1.1 *Scope tags*) is "closed and exhaustive", but its rule 1 named only `x = v` to a `let mut` binding. Two stores were in no row: (1) index assignment `xs[i] = v` into an outer `List`, and (2) field assignment `h.p = v` on a `let mut` struct. Measured with gen1 on 2026-10-06, a field store `v.iov_base = inner.alloc[U8]()` on an outer `let mut` `@ffi.struct` and a tuple store `t.0 = inner.alloc[U8]()` on an outer tuple both pass `blink check`, and both are use-after-free. Case 1 is no longer a store form: [`index-assignment-place`](index-assignment-place.md) made `xs[i] = v` E0313.

**Decision:** Rule 1 covers every assignment to a place. The cell of an assignment is the place's root `let mut` binding, so a store into `x.f.g` or `x.0` is a store into `x`. A §2.22 field-path step is a struct field or a tuple field. No step goes through a `Ptr`: `p.f = v` on a `Ptr[S]` is not a place, and the help names `p.f.write(v)`. The spec does not mark that help machine-applicable. The list keeps four rows.

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in independent-proposal → debate → vote rounds. Phase B ran one round. Phase D ran on Q3b only.

#### Phase A — Independent proposals

Every seat proposed widening rule 1 with no fifth row. Each excerpt below is the seat's own proposed rule-1 text.

- **Systems:**
  > 1. **Write.** `c.write(v)` or `c.field.write(v)` stores into the pointee of `c`. An assignment `place = v` or `place op= v` to any place (§2.22) stores into the place's **root binding**. A field path `x.f.g` or a tuple field `x.0` is part of its root's storage: the root's storage is one cell, so it has one tag.

- **Web/Scripting:**
  > 1. **Write.** `c.write(v)`, `c.field.write(v)`, or an assignment `place = v` or `place op= v` to any place (§2.22). The cell is the place's root `let mut` binding. A struct or tuple is one value held in its binding, so a store into `h.f.g` is a store into `h`.

- **PLT:**
  > 1. **Write.** `c.write(v)`, `c.field.write(v)`, or an assignment `place = v` or `place op= v` (§2.22). The cell of an assignment is the place's root `let mut` binding. A store into `x.f.g` is a store into `x`.

- **DevOps:**
  > 1. **Write.** `c.write(v)`, `c.field.write(v)`, or an assignment `place = v` or `place op= v` to a place (§2.22). The cell is the place's root `let mut` binding: `h.p = v` and `t.0 = v` store into `h` and `t`, with the tag of their declaration.

- **AI/ML:**
  > 1. **Write.** `c.write(v)` or `c.field.write(v)` stores into the pointee of `c`. Assignment to a place (§2.22), `place = v` or `place op= v`, stores into the cell of the place's root `let mut` binding. A field path `x.f.g` or a tuple field `x.0` has no cell of its own. Its cell is the cell of `x`.

- **Minimalism:**
  > 1. **Write.** `c.write(v)`, `c.field.write(v)`, or an assignment `place = v` or `place op= v` to a place (§2.22). The cell is the place's root `let mut` binding.

Further Phase A points, quoted:

- **Systems** (on `p.f = v` through a `Ptr`): "A field path follows only struct and tuple fields. It never passes through a `Ptr`. Write through a pointer with `p.f.write(v)` (§9.1.1)."
- **PLT:** "The current sentence "a field path holds only names" must change, because `.0` is a numeral. §3.4 already calls `pair.0` a "tuple field" (03_types.md:1775, 4433)."
- **DevOps:** "Also, `blink explain E0601` does not mention tag-mismatch. It covers only CloseableEscapesScope and PtrEscapesFfiScope. Today a user who reads the explain text after a tag-mismatch error gets the wrong rule."
- **Minimalism:** "**§2.22, one cross-reference added:** "A store to a place is rule 1 of E0601 (§9.1.1)." This joins the two halves of "a feature that adds places must keep that rule" to each other, so no future place can get past the tag check unseen."
- **Minimalism** *(position later withdrawn)*: "**Tuple elements.** We need no new text. §3 already calls `pair.0` a "tuple field", so `t.0` is a field path under §2.22 as written."

#### Phase B — Debate highlights

- **Minimalism** *(position change)*: "**V1 (tuple fields). I change my position to add text.** plt is right: §2.22 says "A field path holds only names", and `.0` is a numeral, so my claim that the spec already covers `t.0` was wrong."
- **AI/ML** *(position change)*: "**V1 (tuple fields): I change my position and support adding text.** plt is right: "a field path holds only names" is false for `.0`. A model reads "names" as identifiers and will decide that `t.0 = v` is not a place."
- **Systems:** "**V2 (path through a Ptr): it is not a place.** I accept plt's text: "No step goes through a `Ptr` ... `p.f = v` is not a place." web, devops and aiml: today this passes `check` and then the compiler crashes in codegen. That is a typecheck that is not sound."
- **PLT:** "Do not reuse E0313: that code is NoIndexOperator, and sys's "E0313-style" would blur it. The spec has no "not a place" diagnostic today (fact 2: assignment to an immutable `let` gets only a warning). So the decision says only that it "is not a place", with help `p.f.write(v)`. A separate ticket names the not-a-place diagnostic and covers immutable roots too."
- **Web/Scripting:** "The spec should require the help line "write through the pointer: `p.f.write(v)`" and mark it machine-applicable. The rewrite is mechanical, so here, unlike the "allocate from outer" repair, a fix-it is safe."
- **Minimalism** *(position change)*: "**V3 (index assignment).** I change my position to accept sys's one sentence: "An element write is a method call, so rule 4 covers it." A closed list makes readers ask what is missing."

#### Phase C — Final vote

- **Q1: Rule 1 wording** (5-1, Web/Scripting dissent (C))
  - **Systems:**
    > 1. **Vote:** A
    > 2. **Reasoning:** The C output stores into the root's storage (`w._0.iov_base = ...`) for struct fields and tuple fields alike. The tuple clause is cheap, and gen1 accepts `t.0` with no check today. Leaving the clause out invites the same narrow reading again.
    > 3. **Concern:** An implementer may resolve the root only for named-field paths and miss mixed paths such as `w.0.iov_base`.
  - **Web/Scripting:** *(dissent)*
    > **Q1. Vote: C.**
    > Reasoning: Readers copy examples and skip definitions. "`h.p = v` and `t.0 = v` store into `h` and `t`" shows both the struct case and the tuple case in one line, with no abstract `x.f.g` to decode. A says the same thing, so A is my second choice, but C is what a JS or Python developer gets in five seconds.
    > Concern: If A wins, a reader may treat the `x.0` clause as a special case rather than "the same thing again". Explain needs a tuple example to cover that.
  - **PLT:**
    > **Q1. A**
    > - Reasoning: the rule must cover every kind of place. A tuple field is a place, and B leaves it to inference. If A passes, the rule and the §2.22 definition list the same two step kinds, so a reader can check each against the other.
    > - Concern: someone may later add a third kind of step to §2.22 and forget the clause here. Q6 is what guards against that.
  - **DevOps:**
    > **Q1. Vote: A.**
    > Reasoning: The rule text must name the tuple field, because implementers read rule 1 literally and skipped every form it did not name (gen1 proves it). A short general clause is better than C's example clause. A diagnostic and an explain entry can quote it word for word.
    > Concern: the compiler fix could cover `x.f` and miss `x.0` or nested `x.0.f` unless the tests list each shape.
  - **AI/ML:**
    > **Q1. Vote: A.**
    > Reasoning: The clause shows both a struct field and a tuple field. A model generalizes from what the sentence shows, so B (no tuple clause) teaches that `t.0` might be different. A states a rule a model can apply to any path. C names two examples but states no rule, so a model has to infer the general case from them.
    > Concern: if a model sees `x.0` and nothing else, it may read it as a tuple-only form and miss `x.0.f` (a tuple field inside a struct). The §2.22 text in Q2 must cover mixed paths.
  - **Minimalism:**
    > **Q1. Vote: A.**
    > Reasoning: Q2 makes tuple fields explicit field steps. So rule 1 should name `x.0` too, and the two sections then say the same thing. Leaving it out, as in my B, would save four characters and bring back the gap we are closing. C repeats the same fact with example names, which adds words.
    > Concern: as places grow, the clause "x.f.g or x.0" could become a list of path shapes. The rule should rest on "root binding", not on that list.

- **Q2: §2.22 field-path steps are struct or tuple fields** (6-0)
  - **Systems:**
    > 1. **Vote:** Yes
    > 2. **Reasoning:** `0` is a numeral, not a name, so the current text does not admit `t.0`. Stating that steps have no effects and cannot fail keeps the store a single address computation with no hidden reads.
    > 3. **Concern:** None from the codegen side.
  - **Web/Scripting:**
    > **Q2. Vote: Yes.**
    > Reasoning: "A field path holds only names", read next to working `t.0 = v` code, is a ready-made Stack Overflow question. One clause ends it.
    > Concern: None, as long as "no step has an effect" stays in the text. That is the guarantee the evaluation-order rule depends on.
  - **PLT:**
    > **Q2. Yes**
    > - Reasoning: "holds only names" contradicts the line that says `.0` is a tuple field. Two normative sentences that disagree are an under-determined spec. The definition of a place must list all its step kinds, because the tag check is defined by recursion on it.
    > - Concern: none of note. The wording must keep "no step has an effect or can fail", because the evaluation-order rule depends on it.
  - **DevOps:**
    > **Q2. Vote: Yes.**
    > Reasoning: "Holds only names" excludes `0`, and the LSP, formatter and checker all key off the §2.22 grammar of a place. Text that names tuple fields gives each tool one definition to share.
    > Concern: "no step has an effect or can fail" must stay true if a future field step (for example, a computed property) is added.
  - **AI/ML:**
    > **Q2. Vote: Yes.**
    > Reasoning: "Holds only names" is false for `.0`, and a model reads "names" as identifiers. If the definition of a place disagrees with real code, models trained on it will give conflicting answers.
    > Concern: "no step has an effect or can fail" must still be true for tuple fields. It is, because positions are fixed at compile time. The text should not let a reader think `t.(i)` with a variable is allowed.
  - **Minimalism:**
    > **Q2. Vote: Yes.**
    > Reasoning: plt is right that "holds only names" is false for `.0`. Making one sentence accurate costs nothing, and it is the single place that defines field steps.
    > Concern: none worth stating; it is a correction.

- **Q3: A field path through a `Ptr` is not a place** (6-0)
  - **Systems:**
    > 1. **Vote:** Yes
    > 2. **Reasoning:** Today `p.f = v` through a Ptr passes check and then the compiler crashes in codegen, so typecheck accepts code the backend cannot lower. A store through a pointer must stay the explicit `.write` form, so that rule 1, rule 4 and `blink audit` see every write to memory the binding does not own.
    > 3. **Concern:** Until the "not a place" ticket lands, the compiler may still crash instead of giving a front-end error. The impl ticket must make this a front-end error at once.
  - **Web/Scripting:**
    > **Q3. Vote: Yes.**
    > Reasoning: Today `p.f = v` passes check and then ICEs in codegen, which is the worst DX there is. A front-end error with a clear help line turns the C habit `p->f = v` into a lesson about the explicit `.write()` form.
    > Concern: Leaving the error code to a separate ticket may mean users see the ICE for a long time. Give the bug a high priority.
  - **PLT:**
    > **Q3. Yes**
    > - Reasoning: today §2.22 admits `p.f = v`, gen1 accepts it, and nothing defines what it means. Calling it a place would make one assignment syntax store into either the binding or the pointee, depending on the type. Then the cell rule depends on the type and no longer on the syntax. Every store through a pointer stays `.write`, which rule 1 already handles.
    > - Concern: the separate ticket for the diagnostic may sit unfixed, and the ICE stays until it is done.
  - **DevOps:**
    > **Q3. Vote: Yes.**
    > Reasoning: Today `p.f = v` passes check and then crashes the compiler (ICE) in codegen. That is the worst diagnostic surface possible. A front-end error with a clear help line replaces a crash with a fix.
    > Concern: until the separate "not a place" ticket lands, the error may surface under an ad hoc code, which then has to be renamed.
  - **AI/ML:**
    > **Q3. Vote: Yes.**
    > Reasoning: Today the check passes and codegen ICEs. That gives an AI nothing to correct against, which is the worst result for learning. Making it one stated error with one named fix turns a crash into a lesson.
    > Concern: leaving the error code to a separate ticket risks a placeholder code staying in place for a long time. Models trained on that period will learn the placeholder.
  - **Minimalism:**
    > **Q3. Vote: Yes.**
    > Reasoning: today the compiler accepts code (`check` passes) that it then cannot build (ICE), so the spec must decide. "Not a place" keeps one way to store through a pointer (`.write`), and both the tag rules and `blink audit` already understand that way. Leaving the error code to gm879d's family avoids picking a code twice.
    > Concern: if gm879d stays open, `p.f = v` may sit in the spec as "not a place" with no diagnostic implemented for a long time.

- **Q3b: The spec marks the `p.f.write(v)` help machine-applicable** (4-2 Yes in Phase C; see Phase D)
  - **Systems:**
    > 1. **Vote:** Yes
    > 2. **Reasoning:** `.write` is the only store through a pointer the language has, so the rewrite has a single meaning and gives the same machine store. That makes it safe to apply automatically.
    > 3. **Concern:** `p.f op= v` needs `p.f.write(p.f.read() op v)`, which is a read-modify-write. The fix must emit both calls, not just rename `=`.
  - **Web/Scripting:**
    > **Q3b. Vote: Yes.**
    > Reasoning: The rewrite `p.f = v` → `p.f.write(v)` is purely mechanical, with one correct answer. A one-key fix-it in the editor removes the friction of a rule C developers will hit on day one.
    > Concern: Compound `p.f += v` has no one-call rewrite. The machine-applicable claim must cover plain `=` only.
  - **PLT:** *(dissent)*
    > **Q3b. No**
    > - Reasoning: the rewrite does not always keep the meaning. `place = rhs` evaluates `rhs` first, then reads the root. `p.f.write(v)` evaluates the receiver `p.f` first, then `v`. So when `rhs` writes `p` through a closure, the two forms store to different addresses. A fix that is machine-applicable must keep the meaning in every case. This one does so only when `rhs` cannot write the root, so the help should be a plain help.
    > - Concern: if Yes wins, the spec must at least limit the fix to an `rhs` that has no write effect on the root.
  - **DevOps:**
    > **Q3b. Vote: Yes.**
    > Reasoning: The rewrite is purely syntactic and always correct, so the LSP and `blink fix` can apply it with no user decision. A rule that has exactly one correct fix should ship as a quick fix. rust-analyzer and the TypeScript language server both do this for such cases.
    > Concern: if `v` is itself a compound expression, the fix must keep `rhs` evaluated before the store, which `.write(v)` does.
  - **AI/ML:**
    > **Q3b. Vote: Yes.**
    > Reasoning: There is exactly one correct rewrite, so an agent loop can apply it with no guessing. When a spec says a fix is machine-applicable, tools (LSP, `blink fix`) and models both treat it as the right answer.
    > Concern: a fix applied without thought could hide a design error (the user meant to store into a local copy). The help should be clear that the store goes into the pointee.
  - **Minimalism:** *(dissent)*
    > **Q3b. Vote: No.**
    > Reasoning: the fix is not uniform. `p.f += 1` must become `p.f.write(p.f.read() + 1)`, not just a `.write(...)` wrapper. Whether a fix is machine-applicable belongs to the diagnostic ticket that picks the code, not to this decision. We should not promise a fix before we know it is always correct.
    > Concern: if this wins, the impl ticket must cover `op=` paths, or the "machine-applicable" fix will produce code that does not compile.

- **Q4: One sentence on element writes (ticket case 1)** (6-0)
  - **Systems:**
    > 1. **Vote:** Yes
    > 2. **Reasoning:** One line closes case 1 and points readers to rule 4. That rule is unimplemented (vcf206 slice D), and the sentence makes the gap in the compiler visible, not hidden.
    > 3. **Concern:** Readers may take the sentence as "this is checked today" while `ps.push(inner...)` still passes.
  - **Web/Scripting:**
    > **Q4. Vote: Yes.**
    > Reasoning: The ticket asked this exact question, and a silent "moot" lets the next reader ask it again. One sentence that points to `xs.set` costs nothing and gives the form people must write anyway.
    > Concern: The sentence is true of the spec but not yet of the compiler (vcf206 slice D). Users who test it will see `ps.push(inner...)` pass. The decision should name that gap.
  - **PLT:**
    > **Q4. Yes**
    > - Reasoning: the list says it is closed and exhaustive, so leaving a form out has to be marked as on purpose. One sentence ties the list to the index-assignment-place decision, and with it the list is truly complete.
    > - Concern: rule 4 is not yet in the compiler (vcf206 slice D), so for now the spec sentence is true and the compiler is not.
  - **DevOps:**
    > **Q4. Vote: Yes.**
    > Reasoning: The ticket asks which row covers case 1, and the answer must be in the text a test can cite. It also gives `blink explain` a place to point the E0313 help.
    > Concern: users will read the sentence as "the compiler checks `ps.push` today", which is false until vcf206 slice D lands.
  - **AI/ML:**
    > **Q4. Vote: Yes.**
    > Reasoning: In a closed list, a form that is left out with no note makes a model look for the missing row, or guess a fifth one. One sentence settles it and gives the code to write.
    > Concern: until vcf206 slice D lands, the spec says rule 4 rejects `ps.push(inner...)` but gen1 accepts it. A model that tests against the compiler will learn the gap, not the rule.
  - **Minimalism:**
    > **Q4. Vote: Yes.**
    > Reasoning: a closed list makes readers ask what is missing. One sentence stops the next person from re-filing case 1.
    > Concern: the sentence names `m.insert`; if rule 4 (vcf206 slice D) ships late, the spec promises a check that does not exist yet.

- **Q5: Diagnostic text in sections/** (5-1, Minimalism dissent (A))
  - **Systems:**
    > 1. **Vote:** B
    > 2. **Reasoning:** The cell's tag comes from the root's declaration scope. A message that does not name that root and scope makes the user rebuild the outlives check by hand. Today `.write()` and `=` both print "write", but they are different store forms (pointee vs. binding storage), so they must have separate labels.
    > 3. **Concern:** Message conditions written too tightly in sections/ could fix the wording in place. Keep them as facts, not exact strings.
  - **Web/Scripting:**
    > **Q5. Vote: B.**
    > Reasoning: The "assignment" vs "write" label and naming the root's declaration scope are what make the error answer itself. That is the core of the DX. These are facts about the message, not layout, so they belong in message conditions. Spans stay out.
    > Concern: Message-condition lists tend to grow. Keep this one to facts the user needs to fix the code.
  - **PLT:**
    > **Q5. B**
    > - Reasoning: naming the root cell and its declaration scope is what makes the error useful. The outlives relation is between `v` and the root, not the field. A separate "assignment" label keeps each row of the list one-to-one with a label. Layout stays out of the spec.
    > - Concern: B adds a fifth label, "assignment", to the existing four-form list. The existing condition "names the store form (write, capture, effect argument, or call)" must be edited to match.
  - **DevOps:**
    > **Q5. Vote: B.**
    > Reasoning: The existing message conditions already list the store-form labels, so B only adds "assignment" beside "write". Today both forms print "write", so a user and a test cannot tell `x = v` from `.write(v)`. Span layout stays out of the spec.
    > Concern: adding a fifth label to a list that says "four store forms" can confuse readers unless the text says assignment and `.write()` are both rule 1.
  - **AI/ML:**
    > **Q5. Vote: B.**
    > Reasoning: An error that names the root cell and its scope is what lets a model choose the right fix: move the declaration, or allocate from the outer scope. Separate "assignment" and "write" labels let tests and models match on the form. Layout is not spec, and B keeps it out.
    > Concern: the message conditions could grow per store form. Keep them as one list of required facts, not one list per form.
  - **Minimalism:** *(dissent)*
    > **Q5. Vote: A.**
    > Reasoning: §9.1.1 already says the message names the store form and that explain gives one example per form, so most of B is already in the spec. Adding a label rule ("assignment" as distinct from "write") and a "required by the decision" explain section writes tooling detail into the language spec. The narrow condition plus a chore is enough.
    > Concern: if B wins, the label set becomes normative and freezes the wording of diagnostics, which should be free to change.

- **Q6: §2.22 cross-reference to E0601 rule 1** (6-0)
  - **Systems:**
    > 1. **Vote:** Yes
    > 2. **Reasoning:** It costs nothing, and it makes anyone who adds a new kind of place find rule 1.
    > 3. **Concern:** None.
  - **Web/Scripting:**
    > **Q6. Vote: Yes.**
    > Reasoning: It's a cheap link, and it stops the next feature that adds a place from skipping the tag check without anyone noticing.
    > Concern: None.
  - **PLT:**
    > **Q6. Yes**
    > - Reasoning: §2.22 already says a feature that adds places must keep the place rule. The cross-reference closes the other direction, so every place is checked by construction.
    > - Concern: none.
  - **DevOps:**
    > **Q6. Vote: Yes.**
    > Reasoning: The gap exists because §2.22 and §9.1.1 did not reference each other. A cross-reference is the cheapest guard so that the next new place is checked.
    > Concern: none of note.
  - **AI/ML:**
    > **Q6. Vote: Yes.**
    > Reasoning: Links in both directions mean a retrieval on either topic (`blink llms --topic`) reaches the tag rule. It also makes "a feature that adds places must keep that rule" something a reader can check.
    > Concern: none of note. Cross-references can go stale if sections are renumbered.
  - **Minimalism:**
    > **Q6. Vote: Yes.**
    > Reasoning: §2.22 says a feature that adds places must keep that rule, but it does not point to the tag rule that is also part of the contract. One sentence makes the link something a reader can follow.
    > Concern: none.

- **Q7: Where the conformance-test requirement goes** (5-1, Minimalism dissent (B))
  - **Systems:**
    > 1. **Vote:** A
    > 2. **Reasoning:** This is the second row implemented narrower than the spec (field paths here, rule 4 receivers in vcf206). A row with no failing test is a row the compiler does not check, so the decision must require the tests.
    > 3. **Concern:** The tests could check only that an error occurs, not the store-form label, and then miss a store that the wrong row catches.
  - **Web/Scripting:**
    > **Q7. Vote: A.**
    > Reasoning: The field-path hole exists because a row shipped with no failing test. Putting the per-row test requirement in the decision record makes it part of "done" and stops it being dropped as an optional chore.
    > Concern: A test for each row could be satisfied by trivial cases. The negative tests must include `t.0` and `p.f = v`, as listed.
  - **PLT:**
    > **Q7. A**
    > - Reasoning: closed list of store forms ↔ one test per form is the minimum evidence that the rule is enforced. The measured gaps (field, tuple, Ptr path, receiver) were all silent passes that a test per row would have caught.
    > - Concern: a test that only expects an error can pass for the wrong reason, so each negative test must assert the store-form label.
  - **DevOps:**
    > **Q7. Vote: A.**
    > Reasoning: The bug happened because a row had no failing test, so the tests are part of what the decision means, not optional follow-up. Listing them in the decision record makes the impl ticket's done condition explicit.
    > Concern: the `p.f = v` and `ps.push` tests depend on other tickets, so they may land as xfail rows first.
  - **AI/ML:**
    > **Q7. Vote: A.**
    > Reasoning: This row was implemented narrower than the spec twice because no test failed. If the decision record requires the tests, the next implementer (often an AI) reads that requirement with the decision itself.
    > Concern: a corpus test that asserts on message text can break when wording changes. Assert on the form label and code, not on the full message.
  - **Minimalism:** *(dissent)*
    > **Q7. Vote: B.**
    > Reasoning: every compiler change already needs tests (test-first is house rule). A decision record states language semantics, and a test plan does not belong there. A chore that depends on the decision gets the same tests without making the record longer.
    > Concern: if A wins, the decision record ties itself to a test layout that will change while the decision stays valid.

- **Q8: Fix `header =` to `header:`** (6-0)
  - **Systems:**
    > 1. **Vote:** Yes
    > 2. **Reasoning:** The edit is one token in the same paragraph, and it lets z5wh88 close. Spec examples get copied into FFI code, and the wrong form does not parse.
    > 3. **Concern:** z5wh88 must be closed with this edit, not left open as a duplicate.
  - **Web/Scripting:**
    > **Q8. Vote: Yes.**
    > Reasoning: People copy spec examples straight into code, and today the example does not parse. We are editing the same block anyway, so fix it here and close z5wh88 with it.
    > Concern: None.
  - **PLT:**
    > **Q8. Yes**
    > - Reasoning: it is a two-character change in the paragraph this edit already touches. Leaving a spec example that does not parse beside new normative text is a needless inconsistency. Close z5wh88 with it.
    > - Concern: none.
  - **DevOps:**
    > **Q8. Vote: Yes.**
    > Reasoning: Spec examples get copied into user code and LLM training data, and this one does not parse. It is a two-token fix to the same paragraph, so it should close z5wh88 in the same edit.
    > Concern: none. The doc tooling should check that each spec example compiles, so this class of bug cannot happen again.
  - **AI/ML:**
    > **Q8. Vote: Yes.**
    > Reasoning: Models copy spec examples word for word. A wrong example is wrong training data, and z5wh88 closes with no extra cost if we fix it in the same edit.
    > Concern: other spec examples may have the same `=` form. Grep all of sections/ for `@ffi.struct(header =` in the same edit.
  - **Minimalism:**
    > **Q8. Vote: Yes.**
    > Reasoning: it is in the same paragraph and the same edit, and fixing it here lets z5wh88 close at no extra cost.
    > Concern: none; note z5wh88 when it closes.

#### Phase D — Round 2 (Q3b only)

Q3b went 4-2 in Phase C, so the panel re-debated it alone. PLT's evaluation-order point moved all four Yes seats. Final: **No, 6-0**.

Phase D replies, excerpted:

- **PLT:** "§2.22 says `place = rhs` evaluates `rhs`, then reads the root. §2.13 (02_syntax.md:2131) says a call evaluates its receiver before its arguments. So `p.f.write(rhs)` reads `p` before `rhs` runs. Take `p.f = next()` where `next` is a closure that sets `p = q`. The original form stores into `q.f`. The naive rewrite stores into the old `p.f`."
- **PLT:** "**A correct fix exists.** For plain `=`, the fix is `let tmp = rhs` and then `p.f.write(tmp)`. Because assignment is a statement, the fix can always put the `let` before it. The fix may emit the short form `p.f.write(rhs)` only when `rhs` cannot write the root: a literal, a name, or an expression that calls nothing."
- **Systems** *(position change)*: "devops: `.write(v)` keeps `rhs` before the *store*, but not before the *address*. The address is the part that matters here."
- **DevOps** *(position change)*: "rust-analyzer and rustc mark such fixes `MaybeIncorrect` for exactly this reason."

Phase D votes:

- **Systems:**
    > 1. **Vote:** No
    > 2. **Reasoning:** `p.f.write(rhs)` computes the store address from `p` before `rhs` runs. `place = rhs` reads the root after `rhs` runs. So the naive rewrite can store to a different address, which could be freed memory: the use after free that E0601 exists to stop. When the fix is safe (`let tmp = rhs` first, or an `rhs` that cannot write the root) is a decision for the diagnostic ticket, not a spec-level promise.
    > 3. **Concern:** The diagnostic ticket may later mark the short form machine-applicable and skip the "cannot write the root" condition. Its tests must include a case where a closure in `rhs` reassigns `p`.
    >
    > **Help text:** Yes, the decision should name `p.f.write(v)` as the help text. It must not mark the help as machine-applicable.
- **Web/Scripting:**
    > **Vote: No.**
    >
    > **Reasoning:** Under §2.22, `p.f = rhs` evaluates `rhs` before it reads `p`. `p.f.write(rhs)` reads `p` first. So the rewrite can store to a different address, and that is a use-after-free that the tool puts in. A quick fix that users and agents apply in bulk has to be correct every time. A fix that is correct only some of the time does more harm to DX than plain help text. The diagnostic ticket can still mark a safe subset as machine-applicable, for example plain `=` with an `rhs` that cannot write the root, or the `let tmp = rhs` form.
    >
    > **Concern:** If the diagnostic ticket never marks even the safe subset as machine-applicable, C developers lose a one-key fix for an error they hit often. The ticket should say whether it does.
    >
    > **Help text:** Yes. The decision should require the help text to name `p.f.write(v)`, so the error teaches the right form even though the fix is not automatic.
- **PLT:**
    > **Vote:** No
    >
    > **Reasoning:** A fix the spec marks as machine-applicable must keep the meaning at every site. The plain rewrite does not. `place = rhs` evaluates `rhs`, then reads the root. A call evaluates its receiver first. A fix that keeps the meaning everywhere exists (`let tmp = rhs`, then `p.f.write(tmp)`), and so do safe subsets for the short form. Both are diagnostic design, and they belong in the ticket for the "not a place" diagnostic, not in the language decision. I drop my conditional Yes. Sys, devops and min are right that conditions of that kind are tool rules, not spec rules.
    >
    > **Concern:** the diagnostic ticket might mark the short form as applicable with no check on `rhs`. That ticket must state the evaluation-order condition and test it with a closure that reassigns the root in `rhs`.
    >
    > **Help text:** Yes, the decision should name `p.f.write(v)` as the help text, shown as a plain help that is not machine-applicable.
- **DevOps:**
    > **Q3b re-vote (DevOps)**
    >
    > 1. **Vote:** No.
    > 2. **Reasoning:** The rewrite `p.f.write(v)` reads `p` before `v` is evaluated, so it can change which address gets the store. That breaks the rule that a machine-applicable fix keeps the meaning in every case. Tools and agents apply such fixes in bulk without review, so a fix that is rarely wrong is worse than a plain help. The safe subset (plain `=`, and an `rhs` that cannot write the root, or a `let tmp` hoist) is a per-site tool decision for the diagnostic ticket, not a promise in the spec.
    > 3. **Concern:** the diagnostic ticket could drop the quick fix entirely. It should still ship the safe subset as machine-applicable and mark the rest as a plain help (MaybeIncorrect).
    >
    > **Help text:** yes. The decision should name `p.f.write(v)` as the help text, for `=` and for `op=` alike (`p.f.write(p.f.read() op v)`).
- **AI/ML:**
    > **AI/ML, Q3b re-vote**
    >
    > **Vote:** No.
    >
    > **Reasoning:** The naive rewrite can store to a different address when `rhs` writes the root, and `op=` has no rewrite that only wraps the value in `.write(...)`. So "machine-applicable" as a blanket spec promise would be wrong in rare, silent cases. Agent loops apply such fixes without checking them, so a fix that is sometimes wrong teaches a model the wrong form and gives it no error to learn from. A per-site rule (plt's `let tmp = rhs` form, or the short form when `rhs` cannot write the root) is diagnostic design for the "not a place" ticket.
    >
    > **Concern:** if the diagnostic ticket never sets that per-site rule, agents get only a plain help. They may then rewrite with the naive one-call form by hand, which is the same hazard with no tool to catch it.
    >
    > **Help text:** Yes, the decision should name the help text `p.f.write(v)`. Showing the one store form through a pointer is the signal a model needs to correct itself.
- **Minimalism:**
    > **Vote:** No.
    >
    > **Reasoning:** plt's evaluation-order case shows the rewrite can store to a different address. `place = rhs` evaluates `rhs` before it reads the root, while `p.f.write(rhs)` reads the receiver first. `op=` needs a read and then a write in the order §2.19 gives. A fix that is safe only under conditions (plain `=`, an `rhs` with no write effect on the root, or a `let tmp` hoist) is a tool rule for each site, so it belongs in the "not a place" diagnostic ticket, not in the spec. The spec should promise only what is true in every case.
    >
    > **Concern:** the diagnostic ticket may lose plt's conditions and later mark the short form machine-applicable everywhere. The decision record should point to plt's `let tmp = rhs` form so the ticket starts from the correct rewrite.
    >
    > **Help text:** yes, the decision should name `p.f.write(v)` as the help, as Q3 already states. It is a plain help and is not machine-applicable.

### Final Spec

```blink
@ffi.struct(header: "sys/uio.h", name: "iovec")
pub type IoVec {
    iov_base: Ptr[U8],
    iov_len: U64,
}

fn refill() {
    with ffi.scope() as outer {
        let mut v = IoVec { iov_base: outer.alloc[U8](), iov_len: 1 }
        let mut t = (outer.alloc[U8](), 1)
        let p = outer.alloc[IoVec]()
        with ffi.scope() as inner {
            v.iov_base = inner.alloc[U8]()   // error[E0601] tag-mismatch: assignment into `v` (scope: outer)
            t.0 = inner.alloc[U8]()          // error[E0601] tag-mismatch: assignment into `t` (scope: outer)
            v.iov_len += 1                   // OK: U64 carries no tag
            p.iov_base = v.iov_base          // error: not a place; help: `p.iov_base.write(v.iov_base)`
        }
    }
}
```

- **Rule 1 (§9.1.1):** `c.write(v)` or `c.field.write(v)` stores into the pointee. An assignment `place = v` or `place op= v` (§2.22) stores into the place's root `let mut` binding. A store into `x.f.g` or `x.0` is a store into `x`. The list keeps four rows.
- **§2.22:** each field-path step names a struct field or a tuple field. No step goes through a `Ptr`. A store to a place is rule 1 of E0601.
- **`p.f = v` through a `Ptr`:** not a place. The help names `p.f.write(v)`. The spec does not mark it machine-applicable. The "not a place" diagnostic and its code belong to a separate ticket that also covers assignment to an immutable binding. That ticket may mark the fix machine-applicable where it keeps the meaning: plain `=`, with `rhs` hoisted to `let tmp = rhs` or an `rhs` that cannot write the root. Its tests must include a closure in `rhs` that reassigns the root. `op=` stays a plain help (`p.f.write(p.f.read() op v)`).
- **Element writes (ticket case 1):** `xs.set(i, v)` and `m.insert(k, v)` are method calls, so rule 4 covers them. Blink has no index assignment.
- **Message conditions:** a tag-mismatch error labels `.write()` "write" and `=`/`op=` "assignment"; both are rule 1. An assignment error names the full place and its root binding with the scope around the root's declaration. `blink explain E0601` gives one example per store form; its tag-mismatch section is required compiler work.
- **Conformance tests (required):** one positive and one negative test per store row, including a struct field path, a tuple field `t.0`, a mixed path (`w.0.iov_base`), `op=`, and `p.f = v` through a `Ptr`. Negative tests assert the store-form label and the code, not the full message.
- **Known compiler gap:** rule 4 for a method receiver (`ps.push(inner.alloc[U8]())` into an outer list) is not yet implemented; the spec sentence for case 1 states the rule, not the current compiler.
- **Spec example fix:** `@ffi.struct(header = ...)` → `header: ...` in sections/ and in decision Final Spec blocks.
