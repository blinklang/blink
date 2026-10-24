[< All Decisions](../DECISIONS.md)

# Machine Fix for a Write to a Parameter (E0612) — Design Rationale

### Panel Deliberation

Six seats voted: systems (sys), web/scripting (web), PLT (plt), DevOps/tooling (devops), AI/ML (aiml)
and minimalism (min). Phase A gave independent proposals. Phase B was one debate round. Phase C was a
silent vote on four questions. Phase D re-voted Q2, Q3 and Q4 after each seat answered the strongest
argument against its vote. Q1 was voted in Phase C only. The owner made no tiebreak.

The question: what machine-applicable fix does `ParamAssign` (E0612) carry in the warning phase of §3.6
*Rollout*? Before the panel, the help line said `let mut x = c`, and the spec said the fix names a new
binding because `let mut a = a` triggers W0603.

#### Phase A — Independent proposals

Excerpts. Each is the seat's own text.

**sys** (shadow, own name): "`blink fix` inserts `let mut <p> = <p>` as the first statement of the function body, using the parameter's own name. One insertion per parameter, however many writes exist." For W0603: "Narrow and syntactic. Any other shadow still warns."

**plt** (shadow, own name): "The fix needs no renaming and no analysis of uses, so it cannot capture or miss a name." For W0603: "it does not fire for a `let` that is a top-level statement of a function body, binds a name that is a parameter of that function, and has the bare name as its initializer (`let [mut] p = p`)."

**aiml** (shadow, own name): "The fix text is fixed. A model reading the diagnostic copies `let mut a = a` with no naming decision. Copy plus rename adds a decision per site (`x`? `a2`? `a_`?) and an edit at every later use, so model output varies and breaks."

**min** (shadow, own name): "It adds no name, renames no use, and keeps every later use bound to the same identifier." On W0603, min proposed the wide form: "W0603 does not fire when a body-top-level `let` shadows a parameter of that function." Fallback: "ship no fix for ParamAssign".

**web** (copy and rename): "Insert `let mut <fresh> = <param>` as the first statement of the body. Rename every use of `<param>` in that body (reads, writes, nested blocks, closures, string interpolation)." Name: "`<param>_mut`. If a binding of that name is visible anywhere in the body, add `2`, `3`, and so on until free." Against the shadow: "Facts show it gives W0603 at the top of the body. The fix would trade one warning for another. A fix that creates a new warning is not a fix."

**devops** (copy and rename): "The shadow fix `let mut a = a` adds W0603 (verified on gen1), so it fails the second rule. I reject it." On two parameters: "Amend §8.6: zero-width insertions at the same offset do not conflict, and `blink fix` applies them in parameter order. Without this, `gcd` is unfixable."

The fixed form of `gcd` under the shadow fix (sys, plt, min):

```blink
fn gcd(a: Int, b: Int) -> Int {
    let mut a = a
    let mut b = b
    while b != 0 {
        let t = b
        b = a % b
        a = t
    }
    a
}
```

#### Phase B — Debate highlights

web and devops moved to the shadow fix. All six seats ended Phase B on it. Excerpts:

- **devops:** "**I change my position: O1 over O2.** ... Rename edits must resolve every use of a name (string interpolation, closures, patterns, shadowing in nested scopes). Each missed use is a wrong edit or a failed re-typecheck, and every `blink fix` user pays for it."
- **web:** "I change my position: I support O1 (shadow with the parameter's own name)." "My Phase A case against O1 was the W0603 warning. V1 removes that."
- **sys:** "O2 needs a rename pass over every use, plus a fresh-name search ... It also makes `a_mut` and `a` two live names for one value." On W0603: "min's wider rule (any body-top `let` that shadows a parameter) would silence real mistakes. I switch from my Phase A wording to plt's."
- **min:** "**V1: accept plt's narrower form.**" "One exemption, one shape." Also: "vote O1 and V1 as two separate questions."
- **aiml:** "**V1: I move to min's wider form.** ... `let a = a + 1` at the body top would warn while `let a = a` would not. That split is hard to explain."
- **plt:** "I oppose min's wider form (any top-level shadow of a parameter). It changes W0603 for `let a = a * 2` too, which is a separate question and not needed for the fix."
- **Verify-after-fix.** devops: "keep verify-after-fix." plt: "I support it in `blink fix` but not as spec text." min: "no re-typecheck guard."
- **Two parameters.** web, plt and devops wanted a §8.6 sentence. sys and min wanted one combined insertion per function. aiml: "I do not want both."

The moderator gave two facts after Phase B. `self` as a `let` binder gives `KeywordAsIdentifier`. Every closure in Blink has a block body (§2.8), so an expression-bodied closure has no case.

**Agreed by all six at the end of Phase B, not voted:**
- The fix keeps the parameter's name: `let mut p = p` as a top-level statement at the start of the body that owns the parameter. No rename. No new name.
- Rebind, field write, parameter-pattern binder, and a write in a nested block or closure that reaches an outer parameter get this fix. A write to a closure's own parameter gets it at the start of that closure's body.
- Help only, no fix: a write to `self` or a field of `self`, and any write in `Scoped.enter()`.
- The §3.6 Rollout sentence reads: "It carries a machine-applicable fix where one exists that keeps the program's meaning; otherwise it carries help only." The ERROR_CATALOG row names the help-only cases. Warn first (Q8) stands.
- The field-write diagnostic keeps a note that the write does not reach the caller: "to give the caller the new value, return it".
- Tests: after `blink fix`, `blink check` reports no ParamAssign and no W0603 on the fixed names. A nested `let a = a` still raises W0603.

#### Phase C — Final vote

Each seat voted alone, after it read all Phase A and Phase B files. Votes are verbatim.

**Q1. Scope of the W0603 exemption.** A: narrow, `let [mut] p = p` only. B: wide, any top-level `let` that shadows a parameter. **Result: A 5-1 (aiml dissents).**

- **sys — A.** The fix emits exactly `let [mut] p = p`, so the exemption needs to cover only that shape. It is a syntactic check the compiler makes in constant time. A wider rule would also silence `let a = compute()` at the body top, which is a real accidental shadow, and the exemption has no codegen benefit to justify that. *Concern:* The split between `let a = a` (silent) and `let a = a + 1` (warns) may confuse users, and a later request to widen it would reopen W0603.
- **web — A.** A JS or Python dev expects a lint to flag `let a = compute()` over a parameter, because that is an accidental shadow. The narrow form exempts exactly the idiom the fix writes, `let [mut] p = p`, and nothing else. aiml's "hard to explain" split is easy to explain: the copy-under-its-own-name line is the one idiom, and every other shadow still warns. *Concern:* The split between `let a = a` (silent) and `let a = a + 1` (warns) will draw a Stack Overflow question or two.
- **plt — A.** The exemption exists to make the fix's own output clean, and `let [mut] p = p` as a top-level statement is exactly that output. The narrow form is a syntactic predicate with one typing-free condition set. It leaves `let a = a + 1` and `let a = compute()` under W0603, where the shadow may be a mistake. The wide form changes lint semantics beyond what this ticket needs, and the "hard to explain" split is a real but smaller cost: the exempt form is the one that is provably an identity copy. *Concern:* If A wins, a reader sees `let a = a` pass and `let a = a + 1` warn and may read that as inconsistent, though the first is an identity rebind and the second changes the value.
- **devops — A.** The lint and the LSP can check the narrow form cheaply and syntactically: top-level statement, parameter name, bare-name initializer. The wide form also silences `let a = compute()`, which is a real accidental shadow that W0603 exists to catch. The split aiml names (`let a = a + 1` warns, `let a = a` does not) is easy to explain: the exemption covers exactly the form `blink fix` writes. *Concern:* Users who hand-write `let a = a * 2` at the top of a body will still see W0603 and may ask why the idiom next to it is exempt.
- **aiml — B.** A model learns one rule: "a `let` at the top of the body may reuse a parameter name." The narrow form adds a second condition (bare initializer), so `let a = a` is silent and `let a = a + 1` warns. Spec readers cannot predict that split from the spec alone. Same-block shadowing (`let x = n` then `let x = x * 2`) already gives no warning, so the wide form removes an inconsistency. *Concern:* The narrow form will win, and a model that writes `let a = a + 1` at the top of a body will get a W0603 it cannot derive from the "same-block shadowing is silent" rule.
- **min — A.** The fix emits exactly one shape, `let [mut] p = p` at the body top. The exemption should cover that shape and no more. A narrow rule removes the fix's own warning and subtracts nothing else from W0603, so `let a = compute()` and `let a = a + 1` keep their warning. I withdrew my wide form in Phase B for this reason. *Concern:* aiml is right that "`let a = a` is silent but `let a = a + 1` warns" is a split a reader must learn, so the narrow rule may draw questions and a later push to widen it.

**Q2. Two written parameters in one function.** A: amend §8.6 so zero-width insertions at one offset do not conflict and apply in parameter order. B: one combined insertion per function, no §8.6 change. **Phase C: A 3-3 (web, plt, devops for A; sys, aiml, min for B).** The Phase C text of each seat:

- **sys — B.** One combined insertion per function reuses the existing "same edit applies once" rule in §8.6. It needs no new same-offset ordering rule to specify and test. The extra copy of an unwritten-but-listed parameter does not occur, since only written parameters are inserted, and a copy of a by-value parameter is free at -O2. *Concern:* Every diagnostic in a function carries the other parameters' lines, so the edit depends on function context and the LSP code action for one parameter changes more than that parameter.
- **web — A.** Each diagnostic should show only the line for its own parameter. A user who reads the diagnostic on `a` and sees a `let mut b = b` line in the fix will be confused. A same-offset zero-width insertion rule in §8.6 is one sentence, and other fixes can reuse it. *Concern:* A second ordering rule in §8.6 needs its own tests, and a bug there would leave `gcd`-style functions unfixable.
- **plt — A.** Zero-width insertions at one offset commute when their order is fixed, so they are not a conflict in any sound edit model. Stating this in §8.6 is a general rule that other fixes need. B makes each diagnostic's edit depend on the function context and carry other parameters' text, which breaks the one-diagnostic-one-edit compositionality. *Concern:* If B wins, fixing the diagnostic on `a` also copies `b`, so the edit no longer matches its own diagnostic, and the next fix with two same-offset insertions needs its own special case.
- **devops — A.** Each diagnostic should carry only its own parameter's edit. An LSP code action on the `a` diagnostic should insert the `a` line and nothing else, and a diagnostic whose fix touches `b` is a surprise in the editor. The same-offset rule is one sentence in §8.6 and other fixes can use it. Option B makes the dedup depend on function context, which is harder to test. *Concern:* Parameter order becomes a second ordering rule in `blink fix`, and an implementation that orders by diagnostic position instead would give different output.
- **aiml — B.** Fewer rules in the tooling spec means fewer rules for a model to learn and for tests to cover. One edit text per function is deterministic: every diagnostic in the function carries the same line set in parameter order. I accept A if the combined edit proves hard to build. *Concern:* If A wins, the same-offset ordering rule becomes a second ordering rule that other fixes may depend on in ways nobody tested.
- **min — B.** One combined insertion per function is a fix built from rules the spec already has: same edit, same span, apply once. Option A adds a second ordering rule to §8.6 (same-offset insertions, parameter order) that needs its own text and tests, for a case one function-level edit already solves. Subtraction favors the option that adds no spec rule. *Concern:* web's point stands: the fix on the diagnostic for `a` also inserts the line for `b`, which surprises a user who reads one diagnostic alone.

**Q3. A verify-after-fix rule in the spec.** A: the spec says `blink fix` re-checks and drops any fix that leaves a new diagnostic. B: no spec text. **Phase C: B 4-2 (web, devops for A).**

- **sys — B.** O1 adds no new name, so it cannot create a capture or type error. The tests in the agreed list check this directly. A re-check pass in `blink fix` doubles the front-end cost per fix for a case that cannot occur. An implementation may add it without spec text. *Concern:* A future fix with a rename or an insertion at a different place would have no spec guard and could ship a fix that leaves a new diagnostic.
- **web — A.** `blink fix` rewrites user files, and users trust it only if it never leaves a file worse than it found it. A re-check that drops a bad fix costs little and covers cases nobody foresaw, such as a macro-like construct or a later change to W0603. A spec sentence makes every implementation, including the LSP code action, do the same. *Concern:* If the re-check is slow on large files, `blink fix` on a big project gets noticeably slower for a guard that rarely fires.
- **plt — B.** Under O1 the edit adds no new name and renames nothing, so by lexical scope it preserves meaning and cannot add a diagnostic. The tests cover that property. A re-check in `blink fix` is a fine implementation safety net, but it is not a language rule and should not be spec text. *Concern:* If B wins and an unforeseen interaction does produce a new diagnostic, nothing in the spec requires `blink fix` to catch it.
- **devops — A.** `blink fix` rewrites user files, and the user cannot see an unsafe edit before it lands. A re-check that drops a fix leaving a new diagnostic costs one extra typecheck and gives a guarantee that does not depend on each fix author getting the analysis right. The Rollout promise ("a fix, not a new warning") then holds for every future fix, not only O1. *Concern:* If spec text is not added, the guarantee lives only in tests for this one fix, and the next fix author can ship an edit that leaves a diagnostic behind.
- **aiml — B.** O1 adds no new name, so the re-check guards no case. Spec text should hold rules a reader must know to write code; a guard in `blink fix` is an implementation detail. The tests already require no ParamAssign and no W0603 after the fix. *Concern:* If a later fix adds a new name, nothing in the spec forces a re-check, and a fix could leave a new diagnostic unnoticed.
- **min — B.** O1 inserts one fixed line and adds no name, so it cannot create a capture error or a new diagnostic. The tests in the agreed list already check that `blink check` is clean on the fixed names. A spec rule that guards a risk O1 does not have is new machinery with no case. An implementation may still re-check; the spec does not need to require it. *Concern:* A future fix that does add a name would ship with no spec-level guard, and the gap would show only when a user hits a bad edit.

**Q4. Help line text.** A: "copy it under its own name: `let mut a = a`". B: "shadow it at the top of the body: `let mut a = a`". C: "rebind it: `let mut a = a`". **Phase C: A 2 (web, devops), B 2 (sys, aiml), C 2 (plt, min). No majority.**

- **sys — B.** "shadow it at the top of the body: `let mut a = a`" names the real parameter and says where the line goes, so the user does not guess the position. It states the mechanism (shadow) that explains why the later uses need no edit. A and C omit the position. *Concern:* "shadow" is a term of art, and a user new to the idiom may read it as a warning-class word because of W0603.
- **web — A.** "copy it under its own name: `let mut a = a`" says what the line does in plain words, and the code that follows is the exact edit. A JS or Python dev reads "copy" faster than "rebind" or "shadow". The note already says the write changes only this function's copy, so "copy" ties the two lines together. *Concern:* If C wins, "rebind it" reads as if the parameter itself changes, which is the wrong mental model for a by-value copy.
- **plt — C.** All three wordings show the real name and the exact edit text, which is the property that matters. "rebind it" is the shortest and names the operation as the type system sees it: a new binding of the same name. The body-top placement follows from the fix itself. *Concern:* "rebind it" does not say where the line goes, so a user fixing by hand may place it after the first write.
- **devops — A.** "copy it under its own name: `let mut a = a`" says what the edit does and the text after the colon is identical to the edit, so help and fix always agree. The help line is the string a user and an LLM read first, and it explains why the name does not change. "rebind" is short but also names the `a = b` operation the error forbids, which is confusing in this message. *Concern:* "Own name" may read as odd to users who expect a new name, since the old help said "new name".
- **aiml — B.** The line names the real parameter and says where the edit goes, so a model that reads only the diagnostic can apply it by hand with no guess. "Rebind it" does not say where; "copy it under its own name" does not say where either. Token cost is a few words more than C, and it removes one decision point. *Concern:* If C or A wins, the help text states what but not where, and a model may place the line mid-body, after the write, which does not fix the error.
- **min — C.** "rebind it: `let mut a = a`" is the shortest wording and shows the exact edit text, which is what the line must do. A, B and C all name the real parameter and satisfy the agreed rule, so the choice is length only. Shorter help costs fewer tokens in every diagnostic and in the spec sample. *Concern:* "rebind" is less plain than "copy" for a reader who has not met shadowing, and it does not say that the line goes at the top of the body.

#### Phase D — Round 2

Q1 had a majority and was not re-voted. Q2, Q3 and Q4 went to a second round. In D1 each seat read all six Phase C files and answered the strongest argument against its own vote. Moves in D1:

- **aiml, Q2, B to A:** "A model or user that reads the help line "shadow it: `let mut a = a`" then sees a fix that does something else. The help text and the edit no longer match." "The §8.6 sentence must say "parameter order", not "diagnostic order". I ask the writer to keep that wording and to test it with `gcd`."
- **web, Q3, A to B:** "My vote rested on trust in `blink fix`, and the tests already agreed for O1 (no ParamAssign, no W0603 after fix) give that trust. ... I move to B. If a later fix adds a name, that ticket can add the guard to the spec."
- **web, Q4, A to B:** "A JS or Python dev who has not met the idiom guesses the position, and a wrong guess leaves the error in place."
- **devops, Q4, A to B:** "this gap in the diagnostic surface outweighs my objection to "rebind" and the plain-word case for "copy"."
- **plt, Q4, C to B:** "The fix is sound only at the start of the body. A line placed after the first write leaves E0612 in place, so a help line that omits the position can send a user, or a model, to a wrong hand edit."
- **min, Q4, C to B:** "this is correct, and my Phase C reason ("length only") was weak."
- **Conditions on Q2 A.** sys: "If A wins, I ask that the rule name parameter order as the only order." devops: "two parameters give fixed output, and one parameter written twice gives one insertion."
- **Held.** sys, min and devops kept their Phase C votes on Q2 and Q3 (devops on Q3 accepted "wording that re-checks only the changed function"). sys and aiml kept Q4 B. min on Q2: "I still would not block A, because the cost is one sentence."

Reading gaps. The sys and aiml D1 replies were first filed on the digest excerpts, then amended after each read all six Phase C files ("my answers do not change"). Q1 was voted in Phase C only. The moderator note said "AI-first review: 5/5 pass", but the tally states no AI-First score, so this record has none.

Phase D2 votes, verbatim.

**Q2. Two written parameters in one function. Result: A 4-2 (sys, min dissent). Phase C was 3-3.**

- **sys — B.** One combined insertion per function reuses the "same edit applies once" rule that §8.6 already has. The result is one edit at one offset, so no second ordering rule exists to specify, implement or test. The extra lines are by-value copies of parameters the body also writes, and they cost nothing at -O2. I still do not block A. If A wins, the §8.6 sentence must say "parameter order" as the only order, and a `gcd` test must pin it. *Concern:* The code action on the diagnostic for `a` also inserts the line for `b`, so the edit does not match its own diagnostic.
- **web — A.** A user who reads the diagnostic on `a` should see a fix for `a` only. Under B the editor action on `a` also inserts `let mut b = b`, and that surprises the 90% case. The §8.6 rule is one sentence, and the conditions sys, aiml and devops asked for fit it: the text says "parameter order" as the only order, with a `gcd` test and a test that one parameter written twice gives one insertion. *Concern:* A bug in same-offset ordering would leave `gcd`-style functions with the wrong line order or unfixable.
- **plt — A.** Zero-width insertions at one offset commute once their order is fixed, so they are not a conflict in a sound edit model, and "parameter order" is the only order the source gives. A keeps one diagnostic tied to one edit that matches its own span and help line; B makes an edit depend on function context and carry another parameter's text. The rule costs one sentence in §8.6, and other fixes that insert at one offset can reuse it. I join sys's and aiml's condition: the sentence must say "parameter order" as the only order, and the test must cover `gcd`. *Concern:* If B wins, the fix on the diagnostic for `a` also inserts `let mut b = b`, so the edit no longer matches its own diagnostic, and the next fix with two same-offset insertions needs a special case.
- **devops — A.** Each diagnostic carries only its own parameter's line, so an LSP code action on `a` inserts the `a` line and nothing else. B moves the work into the edit builder, which must scan the function for every written parameter and copy the result into each diagnostic. The A rule is one sentence in §8.6 and its tests are small: two parameters give fixed output, and one parameter written twice gives one insertion. I ask that the sentence name parameter order as the only order, as sys and aiml asked. *Concern:* An implementation that orders same-offset insertions by diagnostic position instead of parameter order would give different output for `gcd`.
- **aiml — A.** One diagnostic carries one edit, and the help line matches the edit. A model that reads the diagnostic on `a` finds only the `a` line, so it has no hidden rule to learn. The cost is one sentence in §8.6. The sentence must say "parameter order", not "diagnostic order", so output is the same on every run. *Concern:* If an implementation orders by diagnostic position instead of parameter order, `gcd` gives `let mut b = b` before `let mut a = a`, and the spec test must catch it.
- **min — B.** One function-level insertion reuses the "same edit applies once" rule that §8.6 already has, so the tooling spec gains no text and no ordering rule. The extra line is a free copy of a parameter that the body also writes, so the user needs it anyway. The case for A ("later fixes need same-offset insertions") has no second fix today, and the panel can add the rule when one exists. I note that four seats now lean A and I would not block it, because the cost is one sentence. *Concern:* The fix on the diagnostic for `a` also inserts the line for `b`, so an LSP code action changes more than the span the diagnostic points at.

**Q3. A verify-after-fix rule in the spec. Result: B 5-1 (devops dissents). Phase C was 4-2.**

- **sys — B.** O1 adds no name and renames nothing, so it cannot create a capture or type error. The agreed tests check that directly. A spec rule that requires a re-check per fix fixes a method, adds a second front-end pass per fix, and guards a case that does not exist. An implementation may add the guard with no spec text. *Concern:* A later fix that adds a name or inserts at another place ships with no spec guard.
- **web — B.** O1 adds no new name, so the guard has no case to protect against, and the agreed tests check the fixed file directly. A spec rule with no case is dead text. An implementation may still add the re-check, and a later fix that adds a name can add the rule with its own case. *Concern:* A later fix that adds a name could ship with no spec-level guard and leave a new diagnostic in a user's file.
- **plt — B.** The Rollout sentence already states the property: a fix keeps the program's meaning. A re-check is one way to meet it, and a spec that fixes the method over-constrains tooling. Under O1 the edit adds no name and renames nothing, so lexical scope gives the property, and the agreed tests check it. A guard in `blink fix` is a fine implementation safety net without spec text. *Concern:* If an unforeseen interaction does produce a new diagnostic, nothing in the spec requires `blink fix` to catch it, and a later fix that adds a name needs its own ticket to add the rule.
- **devops — A.** `blink fix` rewrites user files, and the user cannot see an unsafe edit before it lands. A re-check that drops a fix leaving a new diagnostic gives the Rollout promise an owner for every future fix, not only O1. I accept wording that re-checks only the changed function, so the cost stays small for the editor and for large files. *Concern:* If B wins, the guarantee lives only in tests for this one fix, and the next fix that adds a name can ship an edit that leaves a diagnostic behind.
- **aiml — B.** The fix adds no new name, so a re-check guards no case. Spec text holds rules a reader needs to write code. A guard in `blink fix` is an implementation detail, and the agreed tests bind this fix. A general rule for all fixes needs its own ticket and its own case. *Concern:* A later fix that adds a name will have no spec-level guard, and a model that writes such a fix has no rule to follow.
- **min — B.** O1 adds no new name, so it cannot create a capture or a type error, and the agreed tests (no ParamAssign and no W0603 after the fix) check it directly. A spec sentence that requires a re-check per fix is new machinery for a risk this fix does not have. An implementation can add the guard with no spec text. web has moved to B, and plt and sys agree. *Concern:* A later fix that does add a name ships with no spec-level guard until its own ticket adds one.

**Q4. Help line text. Result: B 6-0. Phase C was 2-2-2.**

- **sys — B.** "shadow it at the top of the body: `let mut a = a`" gives the exact text and the position. The fix is correct only at the start of the body, so the position is part of the edit. A and C leave it out, and a line placed after the first write leaves E0612 in place. *Concern:* "shadow" is a term of art that a new user may read as a W0603-class word, though the Q1 exemption keeps the fixed file clean.
- **web — B.** The help line is the only text a JS or Python dev reads before they act. "Shadow it at the top of the body" gives the position, and a wrong position leaves E0612 in place. The exact code follows on the same line, and the Q1 exemption means the fixed file raises no W0603, so "shadow" does not mislead. *Concern:* "Shadow" is a term of art, and a new user may read it as a W0603-class word and distrust the fix.
- **plt — B.** The fix is sound only at the start of the body, and a line placed after the first write leaves E0612 in place. B is the one wording that states the position and the exact edit text, and the mechanism (shadow) explains why later uses need no rename. A has the extra defect that "rebind" in C names the forbidden `a = b` operation; B avoids both problems. The Q1 exemption makes the fixed form clean, so "shadow" does not meet a W0603 on the result. *Concern:* "Shadow" is a term of art and a new user may read it as a W0603-class word, even though the same line shows the code and the exemption keeps the fixed file clean.
- **devops — B.** The help line is the only text a user reads in the editor before they choose the action, and B is the only option that says where the line goes. Without the position, a user or model applying it by hand can put it after the first write, and the error stays. "Shadow" is a term of art, but the exact code is on the same line and the Q1 exemption means W0603 does not fire on the result. *Concern:* A user who reads "shadow" may link it to the W0603 name, and expect a warning on the fixed file that never comes.
- **aiml — B.** B names the real parameter and says where the line goes. A and C leave out the position, and a line placed after the write leaves the error in place. B removes one decision point at a cost of a few tokens. If A or C wins, I ask for "put it at the top of the body" in the note line. *Concern:* If A or C wins, a model that reads only the help line may put the `let mut` line after the first write, and the error stays.
- **min — B.** In Phase C I picked C for length only. D1 showed that the short forms leave out the one fact that makes the edit work: the line must go at the top of the body, or the error stays. B states the position and the exact code in one line, and it adds no new rule or word to the spec. Four seats now name B, and a few extra words cost less than a wrong hand edit. *Concern:* "Shadow" is a term of art that a new user may read as a W0603 word, although the same line shows the exact code and the Q1 exemption keeps the fixed file clean.

### Final Spec

- **Fix shape.** `blink fix` inserts `let mut p = p` as the first statement of the body that owns the parameter, one line per written parameter, in parameter order. No rename, no new name. Several writes to one parameter give one insertion.
- **W0603 exemption (Q1, A).** W0603 does not fire for `let [mut] p = p` when it is a top-level statement of the body and `p` is a parameter of that body. `let a = a + 1` and a nested `let a = a` still warn. §2.12.1.
- **Same-offset insertions (Q2, A).** Two zero-width insertions at one offset are not a conflict. `blink fix` applies both in parameter order, never in diagnostic order. §8.6.
- **No spec text for verify-after-fix (Q3, B).** A guard in `blink fix` stays an implementation choice.
- **Help line (Q4, B).** ``shadow it at the top of the body: `let mut a = a` ``. §3.6, ERROR_CATALOG.
- **Help only.** A write to `self` or a field of `self`, and any write in `Scoped.enter()`.
- **Rollout (§3.6).** "It carries a machine-applicable fix where one exists that keeps the program's meaning; otherwise it carries help only."

```blink
fn gcd(a: Int, b: Int) -> Int {
    let mut a = a
    let mut b = b
    while b != 0 {
        let t = b
        b = a % b
        a = t
    }
    a
}
```

Open point. gen1 still raises W0603 on the exempt form. The spec leads the compiler.

