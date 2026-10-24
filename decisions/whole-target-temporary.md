[< All Decisions](../DECISIONS.md)

# Whole Assignment Target That Is a Temporary — Design Rationale

**Question:** §2.22 case 2 gave help only for a field path from a temporary root ("bind it first: `let mut c = mk()`, then `c.x = 5`"). When the whole left side of `=` or `op=` is a temporary, there is no path to assign through once the value is bound, so that help does not fit. Measured with gen1 before this vote: `mk() = c`, `1 = 2`, `(a, b) = (b, a)` and `a + b = 3` gave E0611 "cannot assign to a temporary value" with the label "no name holds this value, so the store is lost" and no help; the caret for `a + b = 3` sat on the `+`, and the caret was one char wide even for `mk().x`. `mk() += 1` gave E0611 and then a `TypeError`. `(a) = 3` was accepted (a place). `(a, 2).0 = 5` was accepted by check, a bug. Blink has no destructuring assignment; `let (a, b) = ...` declares new names (§2.2). The question was what help each form gets, and whether a tuple target gets its own text.

**Decision:**

- Every whole left side of `=`/`op=` that is not a place stays E0611 NotAPlace. No new code, no fix for any whole-target form. The caret covers the whole left side. The label stays "no name holds this value, so the store is lost" for every form.
- The root rule: strip parentheses and field steps; if what is left is not a `let mut` name, it is a temporary (case 2). A `Ptr` step is still checked first. The spec states the rule and lists no form. So `(a, 2).0 = 5` and `C { x: 1 }.x = 5` are case 2 with the existing "bind it first" help; check accepted `(a, 2).0 = 5`, a bug fixed in the same change. `(a) = 3` and `(a).x = 1` stay places.
- A `note`, not a `help`, replaces the empty help: "a place is a `let mut` name, or a field path from one". "Bind it first" does not apply to a whole target.
- A tuple of two or more elements on the left adds the note "Blink has no destructuring assignment". The swap help (`let t = a`, then `a = b`, then `b = t`) shows only when every element is a place. It is text, never a fix.
- A place error stops the check of the left side: `mk() += 1` reports E0611 only.
- `blink llms` shows the swap and the contrast between `let (a, b) = ...` and assignment.

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in independent-proposal → debate → vote rounds. Phase B ran one round. Phase D ran two rounds, on Q2 and Q4.

#### Phase A — Independent proposals

The heading line of each seat's proposal, verbatim.

- **Systems:** "sys-1: one code (E0611), one message, whole-target help names what a place is; tuple gets one extra note; tuple/struct-literal roots are temporaries"
- **Web/Scripting:** "web-1: one code, one title, a label and help that fit the form"
- **PLT:** "plt-1 (recommended): one code, one rule note, help only where a fix exists"
- **DevOps:** "devops-1: one code, one message, a note for the whole-target case, a help only for tuples"
- **AI/ML:** "aiml-1: one code, one rule note on every whole-target form, one extra help for the tuple form"
- **Minimalism:** "min-1: one message, one help line, no per-form text"

Key passages, verbatim:

- **Systems:** "Systems view: a write needs storage. A call result, a literal, an operator result and a tuple expression are rvalues. The C backend puts them in a scratch temporary that dies at the end of the statement. The store goes there and is lost. So this is the same fact as case 2, not a new case." On the rule: "In case 2, the "root" of the left side is the leftmost expression after you strip field steps and parentheses. If that expression is not a `let mut` binding, it is a temporary." Systems proposed two labels: "literal, operator, tuple: `this expression is a value, not a place`". "I reject the idea of the help "bind it first" for a whole target: after binding, `let mut c = mk()` then `c = ...` does not change `mk()`; the advice would be wrong."
- **Web/Scripting:** "A new code adds nothing: a JS or Python dev searches the message text, and one title gives one search result. The label and help change with the form." On the tuple: "Show the swap help only when every element is a place. Otherwise show the note only. The help is text, not a fix: the right side may have side effects, and a rewrite into three lines changes the order." "I reject "empty help" (today): a bare error with no next step makes a Stack Overflow question."
- **PLT:** "Typing rule. `place ::= x | place.f | place.n | (place)`, where `x` is a `let mut` binding. Every other left side is an rvalue. An rvalue denotes a fresh value with no identity, so a store to it has no observer." "Why no help on `mk() = c`. The case 2 help ("bind it first, then assign through the name") makes sense only with a field path: `let mut c = mk()` gives `c.x = 5` something to write to. For `mk() = c`, binding gives `c = c`, which does nothing. A help that proposes a no-op is worse than no help."
- **DevOps:** "Emit a `note`, not a `help`. Spec: help is the last fix the line needs; no fix exists here." Own tuple message: "Message "tuple expression" instead of "temporary value": a user who writes a swap does not think of a tuple as a temporary."
- **AI/ML:** "A model that sees a new code for each shape of bad target must learn more codes. A model that sees one code and one stated rule learns once." "A second error that blames the wrong thing teaches a model to fix the wrong thing." "The help fires only when the left side is a tuple expression of two or more names. It is text only, not a fix."
- **Minimalism:** "the spec already has the rule. A place is a `let mut` binding or a field path from one. A whole target that is not a place breaks that rule in the same way for every form. So the compiler needs one diagnostic for all of them. It does not need a branch for each form." On the tuple: "Do not write text for a feature that is absent." "the guide (`blink llms`) can show `let t = a; a = b; b = t`. That is a convention in docs. It costs no compiler surface."

#### Phase B — Debate highlights

All six stated these points in Phase A and agreed on them by the end of Phase B: one code, the caret over the whole left side, no "bind it first" for a whole target, no fix for any whole-target form, `mk() += 1` reports E0611 only, a path from a tuple or struct literal is case 2, `(a) = 3` and `(a).x = 1` stay places, and no destructuring assignment.

**The rule line: `help` or `note` (V1).** Three seats moved from `help` to `note`.

- **DevOps:** "A `help` line is where an LSP and `--fix` tools look for an action to offer. Here no action exists, so a `help` promises a fix that is not there." "I move to aiml's shorter wording: "a place is a `let mut` name, or a field path from one". It uses the spec's own word, so a user can search for it."
- **Systems:** "**V1. I change: a `note`, not a `help`.** devops cites the spec: help is the last fix the line needs. No fix exists for a whole target, so a help line breaks that rule."
- **Minimalism:** "**V1 (rule line).** I change to devops's position: emit a `note`, not a `help`. §2.22 says "the help is always the last fix the line needs". No fix exists here, so a `help` line breaks that rule."
- **Web/Scripting:** "**V1: I change. Use a `note`, not a `help`.** devops is right: the spec says help is the last fix the line needs, and no fix exists."

**The label (V2).** Systems, and DevOps for a while, moved toward one label.

- **Systems:** "**V2. I change: one label for every form**, today's "no name holds this value, so the store is lost". My Phase A objection (it reads oddly for `1`) is small. It is still true for a literal: no name holds it."
- **DevOps:** "I change my position. The per-form labels (mine and web's) add 4 strings that must stay in step with the spec and the goldens." DevOps moved to a new one-label option: "a value, not a place".
- **Web/Scripting:** "**V2: I change toward sys.** Call keeps today's label ... Literal, operator, tuple and other forms use "this expression is a value, not a place". Two strings, not five." "I oppose one label for all (plt, aiml, min): "no name holds this value" on `1 = 2` makes a user ask which name."
- **PLT:** "I keep today's label for every form. It is true for all of them: the store is lost."

**The tuple target (V3).** The gate "show the swap help only when every element is a place" came from web and was adopted by sys, plt, aiml and devops.

- **PLT:** "**V3. Tuple: I change my position in part.** I concede to web: the swap snippet in the help must show only when every tuple element is a place. For `(a, 2) = ...` or `(mk(), b) = ...`, the snippet is wrong advice." "I reject devops's own message ("cannot assign to a tuple expression"): it adds a second message string for one failure, and the tuple is a temporary by the same rule."
- **DevOps:** "I hold my position: own message "cannot assign to a tuple expression", plus the note and the swap help." "If the panel prefers the same message as the other forms, I accept that: the code and the help matter more than the headline."
- **Systems:** "**V3. Same message, no own message (against devops).**" "I reject min's "no tuple text": the cost is one branch in the diagnostic, no run-time cost, and the tuple form is the one case where the user's intent is clear."
- **Minimalism (dissent):** "**V3 (tuple).** I hold: no tuple text, no own message. Five seats want a tuple line, so I state the cost for the vote. A tuple-gated line means a form test in the compiler, a catalog entry and a golden test. It says "no destructuring assignment", which a later vote may reverse. ... If the tuple line wins, it must be one `note` line with no swap code, and the swap example goes in `blink llms`."
- **Web/Scripting:** "The "feature may never exist" worry is answered by the note's wording: it states today's rule, not a promise."
- **AI/ML:** "Change from Phase A: add web's condition; add web's clause "`let (a, b) = ...` only declares new names" to the tuple help, since models also mix up the two."

**The root rule (V5).**

- **Minimalism:** "Adopt sys/plt's rule as the spec text: strip parentheses and field steps; if the leftmost expression is not a `let mut` name, it is a temporary. This one rule covers block, cast, unary, method call, closure, literals and `x?`. It removes the need to list forms. Spec should state the rule and list no forms."
- **PLT:** "I want the vote to include that rule as the spec text, not a list of forms." "**Extra for the vote:** the `op=` cascade rule (a place error stops the check of the left side) goes in the spec test list, with `mk() += 1` as the case."
- **AI/ML:** "Vote item I want: suppress the cascade (`mk() += 1` second error) as a stated rule in the spec, not only in the compiler."

All six ended Phase B with "STATUS: stable, ready to vote".

#### Phase C — Final vote

- **Q1: The text of the rule note** (6-0 for A: "a place is a `let mut` name, or a field path from one")
  - **Systems:** A — "Same cost as B and C: one fixed string in the emitter. A is the shortest and uses the spec's own word ("place"), so the user can search for it. The note states the rule once for every whole-target form, with no per-form branch." Concern: ""a place is" assumes the reader knows the word; a user new to Blink may not, and the spec definition is the only place it is explained."
  - **Web/Scripting:** A — "A JS or Python dev reads the note once and needs it to name the thing they got wrong. "A place is a `let mut` name, or a field path from one" uses the spec's own word, so a user can search for it, and it is the shortest of the three. B and C say the same thing in more words, and the extra words do not help anyone." Concern: "A user who never read the spec may not know what "a place" means, so the note may send them to search for the term."
  - **PLT:** A — "The note states the typing rule `place ::= x | place.f | place.n | (place)` in the spec's own term, "place", so a user can search for it. It is short and true for every whole-target form. Between A and B the difference is wording only, and A uses the spec's vocabulary." Concern: "If the note says "a place" and a user does not know the word, the line defines nothing for them; the spec and `blink llms` must define "place" in the same terms."
  - **DevOps:** A — "The text uses the spec's own word, "place", so a user can search for it and find section 2.22. It is the shortest of the three, so it fits one terminal line next to the caret. It is a `note`, so an LSP or `--fix` tool finds no action to offer." Concern: "If the rule changes later (for example, destructuring assignment), this fixed string goes stale unless the spec and the golden change with it."
  - **AI/ML:** A — "The note uses the spec's own word, "place", and states the rule in one short sentence. A model that reads the error alone can then repair the line without the spec. The same wording in the spec and in the error means one term to learn." Concern: "If the writer later rewords the note in the spec but not in the emitter, the two texts drift and a model sees two rules."
  - **Minimalism:** A — ""a place is a `let mut` name, or a field path from one" is the shortest of the three. It uses the spec's own word "place", so a user can search for it, and it states the rule once for every form. B and C say the same in more words." Concern: "A note that defines "place" only by the two allowed shapes may read as a puzzle to a user who has never met the word, but this is minor next to the cost of longer text."

- **Q2: The label under the caret** (Phase C 4-1-1: A four votes, web B, devops C; see Phase D for the re-vote)
  - **Systems:** A — "One check (is-place) gives one failure and one label. It is true for every form: the temporary lives in a scratch slot that dies at the end of the statement, so the store is lost. One string means one emitter path and one golden, with no form switch to keep in step with the spec." Concern: "On `1 = 2` the label "no name holds this value" makes a reader ask which name; that is a small readability loss, not a correctness one."
  - **Web/Scripting:** B — "A call keeps today's label, because binding the call result to a name is a real step the user can take. For `1 = 2` and `a + b = 3`, "no name holds this value" makes a user ask which name, and that starts a Stack Overflow question. Two strings is a small price for a label that is true and clear for the 90% case, a literal or an operator on the left. Option C would drop the call-specific label that fits `mk().x = 5` and `mk() = c`." Concern: "Two labels add one form test to the emitter, and a later edit may change one label and leave the other out of step with the goldens."
  - **PLT:** A — "One predicate (is-place) fails, and one fact holds for every form: the value has no identity, so the store has no observer and is lost. "No name holds this value" is true for `1`, for `a + b` and for `(a, b)`. Splitting the label by form encodes the syntax of the rvalue, which has no semantic difference, and adds strings and goldens." Concern: ""No name holds this value" reads oddly for a literal, so some users will ask which name; if goldens show this confuses users, one neutral label for all forms (option C) is the fix, not per-form labels."
  - **DevOps:** C — "One label means one string and one golden. It is true for a call, a literal, an operator result and a tuple. It also fits the path forms, so there is one label for the whole code. Today's label asks "which name?" on `1 = 2`." Concern: "Option A keeps today's label, which names a cause (lost store) that some forms, such as `1 = 2`, do not need, and users may keep asking which name should hold the value."
  - **AI/ML:** A — "One label for every form means one string for a model to learn and one golden test, and it also stays true for the path forms (`mk().x`), so the spec example does not change. A label per form adds choices that no user or model needs to act on. "Store is lost" names the consequence, which is the fact a model needs to fix the line." Concern: ""no name holds this value" on `1 = 2` makes a reader ask which name; the note on the next line has to carry that gap."
  - **Minimalism:** A — "One label is one string in the emitter and one golden. "No name holds this value, so the store is lost" is true for every form, including `1 = 2`: no name holds `1`. Two labels add a branch on the form for a small gain, and C changes text for the path forms the panel already decided (6-0)." Concern: "On `1 = 2` the label may make a user ask which name, so B or C would read better there; the cost is one extra branch that I judge not worth it."

- **Q3: The tuple target `(a, b) = (b, a)`** (5-1, Minimalism dissent: A five votes, min D)
  - **Systems:** A — "A tuple on the left is the one form where the user's intent (a swap) is clear and the fix is three plain lines with no run-time cost. Gating the swap help on "every element is a place" stops wrong advice for `(a, 2) = ...`. Same message and code keep one catalog row for E0611. The cost is one branch in the diagnostic code, which does not touch codegen." Concern: "If a later vote adds destructuring assignment, the tuple note and its golden become dead text that must be removed in step."
  - **Web/Scripting:** A — "The swap `(a, b) = (b, a)` is the most common wrong guess from Python, JS, Go and Rust users, and the error is the only place they will read. The same title keeps one search result for one failure. The swap help only shows when every element is a place, so `(a, 2) = ...` gets no wrong advice. B splits the title in two, and C and D leave the user with no example at the point of the error." Concern: "The tuple branch may grow into a table of per-shape text, so the panel should hold the line at this one form."
  - **PLT:** A — "The tuple is an rvalue by the same rule, so it keeps the same code and message. A swap is the one intent the error can name, and the user with Python or Rust habits reads only the error. The swap help is gated on every element being a place, because for `(a, 2) = ...` or `(mk(), b) = ...` the three-line rewrite is wrong advice." Concern: "The swap help is a text pattern; if the right side reads a name the swap order changes (`(a, b) = (b, a + 1)`), the three-line rewrite can mislead, so the help must stay text and never become a fix."
  - **DevOps:** A — "Same message and code, so the catalog row lists one text, tools group on one message, and one search finds every case. The swap help stays gated on "every element is a place", so it never gives wrong advice for `(a, 2) = ...`. The help is the only line a user can act on, so an LSP can show it as text." Concern: "The headline "cannot assign to a temporary value" is odd for a tuple, and a user who writes a swap may not read the caret and notes below it."
  - **AI/ML:** A — "The swap `(a, b) = (b, a)` is the form models write most by habit (Python, JS, Go, and Rust all accept it). An error with no next step makes the model guess, so it earns one extra line. Gating the swap help on "every element is a place" avoids wrong advice for `(a, 2) = ...`, and the same message keeps one text per code." Concern: "The tuple text can grow into a table of per-shape help, and it names a feature that a later vote may add."
  - **Minimalism:** *(dissent)* D — "Five seats want tuple text, so I take my second choice: the same message plus one `note` line, with no swap code in the diagnostic. This is one form test and one string. The swap example costs nothing in the compiler when it lives in `blink llms`, where it can change if a later vote adds destructuring assignment. A swap help (A) adds a second gate ("every element is a place"), a second branch, and code that shows in every swap error." Concern: "If A wins, the swap help is a form-specific rewrite hint that needs the "every element is a place" gate to stay correct, and that is the start of a per-shape table of help text."

- **Q4: The tuple note text** (Phase C 3-3: A sys, plt, min; B web, devops, aiml; see Phase D for the re-vote)
  - **Systems:** A — "The note states today's rule in one short line and promises nothing. The clause about `let (a, b)` is a language-teaching aside, not a fact about this error; it adds text to every tuple error and goes in the docs." Concern: "A user who confuses `let (a, b) = ...` with assignment gets no hint of the difference from the diagnostic alone."
  - **Web/Scripting:** B — "A model or a person who has just written `(a, b) = ...` also tends to mix up the assignment with `let (a, b) = ...`. The second clause says that `let (a, b) = ...` only declares new names, so the user does not try to fix the line by adding `let`. It costs one clause and removes a second wrong attempt." Concern: "If the panel later adds destructuring assignment, the note must change with it, and a long note is more likely to go stale than a short one."
  - **PLT:** A — "The note states today's rule only: there is no destructuring assignment. It makes no claim about `let (a, b) = ...`, which is a separate, valid form (§2.2), so no second rule can go stale. One fact per line keeps it exact." Concern: "A user who writes `(a, b) = ...` after a `let (a, b) = ...` habit may still not see the difference between declaring and assigning; the `blink llms` text must carry that contrast."
  - **DevOps:** B — "The clause "`let (a, b) = ...` only declares new names" answers the second question a user asks, since a destructuring `let` is what they just saw work. It adds one clause and no new string path. The note stays a statement of today's rule, not a promise." Concern: "The line is long for narrow terminals and wraps, and it will need an edit if destructuring assignment is added."
  - **AI/ML:** B — "Models mix up `let (a, b) = ...` (valid, declares new names) with `(a, b) = ...` (invalid). The clause names the valid form next to the invalid one, so a model can map the fix at once. It costs about 12 tokens on one rare error." Concern: "If destructuring assignment is added later, the clause "only declares new names" turns false and must change with the spec."
  - **Minimalism:** A — ""Blink has no destructuring assignment" is one short clause that states today's rule. The `let (a, b) = ...` clause in B teaches a second fact in an error about a different mistake, and it adds tokens to every tuple error." Concern: "If B wins, the clause will need an edit whenever `let` destructuring changes, so the note carries a second thing to keep in step with the spec."

#### Phase D — Round 2

Q2 ended Phase C at 4-1-1 and Q4 at 3-3. A focused debate ran on both, then a silent re-vote. Q1 and Q3 were not reopened.

**Debate highlights (D1).**

Q2, the label:

- **Web/Scripting** (moved from B to A): "Strongest argument against B: my reason for keeping the call label was that "binding the call result to a name is a real step the user can take". That is wrong for a whole target. min showed it in Phase A: after `let mut t = mk()`, `t = c` stores into `t`, not into the call result. So a call as a whole target has no more of a fix than `1 = 2`, and there is no basis to give it a label different from the other forms."
- **DevOps** (moved from C to A): "Strongest argument against C (min): C rewrites the label of the path forms (`mk().x = 5`) that the panel already decided 6-0, so the spec example, the catalog and the goldens all change for a gain that is only about wording. I agree this cost is real." "The weak point of A, "which name?" on `1 = 2`, is small: the rule note sits on the next line and says what a place is."
- **PLT** (kept A): "The label is not false for `1 = 2`. No name holds a literal, and the store is lost. The cost is style, not soundness." "If goldens or user reports show the confusion, the fix is C for all forms, as my Phase C concern said."
- **AI/ML** (kept A): "No vote shows a user failing on the label; this is a style worry. If a golden or a user report shows the confusion, plt's remedy (one neutral label for all forms) is cheap."

Q4, the tuple note text:

- **Web/Scripting** (held B): "the clause is not a second rule. It states today's grammar (§2.2), which is stable, and it answers the question this exact user asks next. They write `(a, b) = ...` because `let (a, b) = ...` worked for them, and the note "no destructuring assignment" does not tell them why the two differ. Without it, a user may add `let` and silently declare new shadowing names, which is a worse bug than the error."
- **Systems** (held A): "Still, adding `let` silently compiles and changes meaning (a shadow, not a swap). That is a sharper risk than I weighed in Phase C. I hold A because the swap help is shown right under the note when it applies, and it shows the working form. For `(a, 2) = ...` there is no help, and there B is stronger."
- **PLT** (held A): "The user who tries `let (a, b) = (b, a)` gets a valid program that shadows the names and swaps nothing; the compiler does not warn about it. That is a real trap, but the diagnostic for `(a, b) = ...` is the wrong place to teach it, and the note on that line would bind the error text to the shape of another form (§2.2). The `blink llms` docs carry the contrast." "I do not object if B wins; the clause states a fact that is true today."
- **Minimalism** (held A): "The contrast between `let (a, b)` and `(a, b) =` belongs in `blink llms`, which is where a user and a model look for the language rule, and plt's Concern names that. The error stays short and does not wrap on narrow terminals (devops's own concern)."
- **DevOps** (held B): "A diagnostic should answer the next question the user asks, and a search for "destructuring" does not help a user who does not know the term."
- **AI/ML** (held B): "the docs do not reach a model that reads only the error text, and a model that wrote `(a, b) = ...` has the `let` form in mind as the valid pattern."

**Re-vote (D2).**

- **Q2: The label under the caret** (6-0 for A: today's label for every form, "no name holds this value, so the store is lost")
  - **Systems:** A — "One is-place check gives one failure and one label, so the emitter has one string and one golden test and no switch on the form of the left side. The label is true for every form: the temporary has no name, and the store is lost. It also keeps the path-form text that the panel decided 6-0. web and devops moved to A in D1, so the old split on `1 = 2` is gone." Concern: "On `1 = 2` the label makes a reader ask which name; if goldens or user reports show this, one neutral label for all forms (C) is the fix."
  - **Web/Scripting:** A — "My Phase C case for B rested on "bind the call result to a name", and min showed that does not help a whole target: `t = c` stores into `t`, not into the call. So a call has no better fix than `1 = 2`, and a form switch has no basis. One string and one golden are easier for a dev to learn, and the rule note on the next line answers "which name?"." Concern: ""No name holds this value" on `1 = 2` still reads oddly, so a user may ask which name; if goldens or reports show that, one neutral label for all forms is the later fix."
  - **PLT:** A — "One predicate (is-place) fails, so one label. "No name holds this value, so the store is lost" is true of a call, a literal, an operator result and a tuple: the value has no identity, so the store has no observer. A split by form (B) encodes the syntax of the rvalue, which has no semantic difference, and web withdrew B in D1 after min showed that binding a call result gives a whole target no fix either. C rewrites the path-form text decided 6-0 and drops the consequence." Concern: "On `1 = 2` the label raises the question "which name?"; if goldens or user reports show this, one neutral label for all forms (C) is the fix."
  - **DevOps:** A — "One label is one string and one golden, with no form switch to keep in step. It is true for every form: no name holds a call result, a literal, an operator result or a tuple, so the store is lost. It also keeps the 6-0 spec example for `mk().x = 5` unchanged. The rule note on the next line answers "which name?" for `1 = 2`." Concern: "On `1 = 2` the label still makes some users ask which name; if goldens or user reports show it, one neutral label for all forms (C) is the later fix."
  - **AI/ML:** A — "One label means one string for a model to learn and one golden test. It stays true for the path forms the panel decided 6-0, so the spec example does not change. "The store is lost" names the consequence, and the rule note on the next line answers "which name?". Web and devops moved to A in D1, so no seat now argues for a form switch." Concern: ""No name holds this value" on `1 = 2` may still make a reader ask which name; if goldens or user reports show it, one neutral label for all forms is the later fix."
  - **Minimalism:** A — "One label is one string and one golden, with no branch on the form. The label is true for every form, and it keeps the text of the path forms that the panel decided 6-0. web moved from B to A and devops moved from C to A, because B encodes the syntax of the rvalue and C rewrites decided text. The rule note on the next line answers "which name?"." Concern: "On `1 = 2` the label still reads oddly; if goldens or user reports show confusion, one neutral label for all forms is the later fix."

- **Q4: The tuple note text** (3-3 → owner broke the tie for A: "= note: Blink has no destructuring assignment")
  - **Systems:** A — "The note states one fact about this error and promises nothing about `let`. The clause about `let (a, b)` is a rule about a different, valid form (§2.2), and it adds tokens to every tuple error and wraps on narrow terminals. The swap help, shown when every element is a place, already shows the working three lines. `blink llms` can carry the `let` contrast once." Concern: "A user who adds `let` gets a program that compiles and shadows `a` and `b` with no swap, and for `(a, 2) = ...` there is no swap help to show the right form."
  - **Web/Scripting:** B — "A dev who writes `(a, b) = (b, a)` has just seen `let (a, b) = ...` work. Without the clause, the likely next attempt is to add `let`, which compiles, shadows the names and swaps nothing. That silent wrong program is worse than the error. The clause is about 12 tokens on one rare error and states grammar from §2.2 that is stable." Concern: "If A wins, a user who adds `let` after the error gets a program that compiles and does not swap, with no hint in the diagnostic; only `blink llms` carries the contrast, and users read the error, not the guide."
  - **PLT:** A — "The note states today's rule only: assignment cannot destructure. It makes no claim about `let (a, b) = ...` (§2.2), so no second rule can go stale with it. B is true and I do not object if it wins, but it binds the E0611 text to the shape of another form. sys's point stands that adding `let` compiles and shadows without a swap; `blink llms` must carry that contrast, and the swap help shows the working form where it applies." Concern: "A user who writes `(a, 2) = ...` gets no swap help, may add `let`, and silently gets a shadowing program that swaps nothing."
  - **DevOps:** B — "A user who writes `(a, b) = ...` has just seen `let (a, b) = ...` work. Note A says "no" and gives no reason the two differ. Without the clause, the user may add `let`, which compiles, shadows `a` and `b`, and swaps nothing. That is a worse bug than the error. For `(a, 2) = ...` there is no swap help, so the clause is the only text that stops this. A diagnostic should answer the next question the user asks." Concern: "If A wins, the user who adds `let` gets a silent shadow with no warning, and the `blink llms` text is the only place that explains it."
  - **AI/ML:** B — "Models mix up `let (a, b) = ...` (valid, declares new names) with `(a, b) = ...` (invalid). A model that reads only the error has no other source for the contrast, and `blink llms` does not reach it there. Sys saw in D1 that adding `let` compiles and shadows the names, so the swap fails without any error; that is a worse result than the error, and the clause costs about 12 tokens on a rare error. For `(a, 2) = ...` there is no swap help, and there the clause is the only guide." Concern: "If destructuring assignment is added later, the clause "only declares new names" turns false and must change with the spec in the same commit."
  - **Minimalism:** A — ""Blink has no destructuring assignment" states today's rule in one line. The `let (a, b)` clause in B is a rule about a different, valid form (section 2.2), and it adds a second fact to keep in step with the spec and tokens to every tuple error. The `let` contrast belongs in `blink llms`, where plt and sys both agree it should go. The swap help, which the panel kept in Q3, already shows the working form under the note." Concern: "If B wins, the clause goes stale if `let` destructuring or destructuring assignment changes, and a user who adds `let` still gets a program that shadows and swaps nothing, so the `blink llms` contrast matters either way."
  - **Owner tiebreak:** A — the owner (BDFL) broke the 3-3 tie for A, with no reason given.

Dissents and concerns carried by the record:

- **Minimalism** dissented on Q3 (D, "A swap help (A) adds a second gate ("every element is a place"), a second branch, and code that shows in every swap error.").
- On Q2, all six name the same risk: on `1 = 2` the label makes a reader ask which name. If goldens or user reports show it, one neutral label for all forms (C) is the later fix.
- On Q4, all six name the same risk: adding `let` compiles, shadows `a` and `b`, and swaps nothing, with no warning. All six want `blink llms` to show the `let (a, b)` against assignment contrast. The spec and `blink llms` carry it (§2.22, and a bullet beside the `E0611` bullet in `llms-full.md`).
- Shared concern on Q1 (sys, web, plt, min): a reader new to the word "place" may not know it, so the spec and `blink llms` must define it in the same terms. The note uses §2.22's own definition.

**Reading gaps.** The ruling and the panel files agree. Two points the panel left open, and how the writer read them:

- The panel did not fix the order of the two notes for a tuple. The writer put the rule note first and the tuple note second, so the tuple lines follow the same text as every other whole target.
- The panel gave no text for a note when a tuple has no swap help. The writer reads Q3 A as: the same two notes, no `help` line.
- A tuple of fewer than two elements is not named. `(a)` is a name in parentheses (a place); the spec does not rule on `(a,)`.
- The panel named the swap help "`let t = a`, then `a = b`, then `b = t`". The wording "to swap, use a temporary:" comes from sys's and devops's Phase A text.
- Today's gen1 gives one-char carets, no rule note, and a `TypeError` after `mk() += 1`. It already gives "bind it first" for `(a, 2).0 = 5`. The spec leads the compiler here.

### Final Spec

```
error[NotAPlace]: cannot assign to a temporary value
 --> swap.bl:6:5
  |
6 |     (a, b) = (b, a)
  |     ^^^^^^ no name holds this value, so the store is lost
  |
  = note: a place is a `let mut` name, or a field path from one
  = note: Blink has no destructuring assignment
  = help: to swap, use a temporary: `let t = a`, then `a = b`, then `b = t`
```

- One code, E0611. No fix for any whole-target form. The caret covers the whole left side. The label does not change.
- Root rule: strip parentheses and field steps; a root that is not a `let mut` name is a temporary. A `Ptr` step is checked first.
- `(a, 2).0 = 5` and `C { x: 1 }.x = 5` get "bind it first". `(a) = 3` and `(a).x = 1` are places.
- A whole left side gets the rule note and no help. A tuple of two or more elements adds the tuple note, and the swap help only when every element is a place.
- `mk() += 1` is E0611 only.
- Tests: one row per shape (call, literal, operator, tuple of places, tuple with a non-place, block, cast, unary, method call, closure, `x?`), `(a) = 3` accepted, `mk() += 1` one error, `(a, 2).0 = 5` and `C { x: 1 }.x = 5` E0611 with "bind it first", and the caret width on `mk().x`.

