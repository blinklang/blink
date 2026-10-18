[< All Decisions](../DECISIONS.md)

# W0611 Default Severity — Design Rationale

**Gap:** W0611 `ScopedValueEnteredTwice` fires when one scoped value (`Closeable` or `BlockHandler`) reaches more than one `with` item (§5.5). It is a warning by default; `[lints]` can raise it, and `@allow(ScopedValueEnteredTwice)` suppresses it per function (decisions/scoped-value-trusted-channel.md). A second `exit()` on a wrapper over a foreign handle is a double free unless the wrapper guards it. The std.db handles now guard it: a second close is a no-op, and ops after close return `DBError.ConnectionError("connection is closed")`. `std.testing`'s `Cleanup` has a legal run-twice case. Should W0611 be an error by default?

**Facts given to the panel:** §4.16.8 lets `@allow` and `[lints]` reach only names under *Warning Names*; the catalog row decides, not the severity in effect. W0611 has no emit site in the compiler yet, so no one can measure its false-positive rate. A second close on `TcpSocket`/`TcpListener` still closes whatever fd the OS reused (open bug). W0812 is a warning name that `--strict-struct-layout` raises to an error. §8.16.1 says editions gate lint severity. A `[lints]` level that `@allow` cannot override ("deny") is a separate open spec question.

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated
in independent-proposal → debate → vote rounds. All text below is quoted from the panelists. Cuts are marked "…". Dissent is marked **(dissent)**. Text in [brackets] replaces a local tracker ID.

#### Phase A — Independent proposals

Four seats proposed a warning by default now; Web/Scripting and AI/ML proposed an error by default now, with the name kept under *Warning Names*. All six rejected a move to *Error Names*.

- **Systems:** "**Position:** Keep W0611 a warning by default for now. A double `exit()` on a foreign handle is a safety problem, and the wrapper is the place to close it. A lint that cannot see into calls cannot close it." … "Making W0611 an error does not make that rule hold. It only makes the cases the lint can see fail the build. When people see that error stop a build, they will think the compiler checks double entry, and it does not." Proposal S1 added: "Make [the TcpSocket second-close bug] a release blocker for the next stdlib release. It is the one stdlib wrapper left where W0611 is the only guard."
- **Web/Scripting:** "**Proposal A (my vote): the default level is "error", and the name stays under *Warning Names*.**" … "**The 90% case is a bug.** A JS or Python dev who writes `with conn` inside a loop believes they reuse one connection. They do not know that `exit()` runs on each pass." … "**Strict first, loosen later.** Changing error to warn later breaks no build. Changing warn to error later breaks builds, so it needs an edition (§8.16.1). Blink has few users today, so this is the cheapest moment to pick the strict default." Fallback: "**Proposal B (fallback): warning now, error in the next edition.**"
- **PLT:** "Keep W0611 a warning by default. Do not move it under *Error Names*. Write down the conditions that must hold before an edition may make it deny-by-default." … "§4.16.8 says an error means "the compiler cannot give the program a meaning". A program that enters one value twice has a meaning … W0611 reports a likely mistake." … "**Precision: the rule is not exact enough to be an error.** "Reaches two or more `with` items" does not say whether it counts per path or across all paths". PLT proposed the per-path sentence and: "W0611 is not a safety check. A type that wraps a foreign handle makes a second `exit()` safe (§4.7.2)."
- **DevOps:** "**Proposal D1 (primary): W0611 stays a warning by default now. Raising it to an error waits for measured data and an edition.**" … "**No one can measure it.** … If we make an unmeasured lint an error, every false positive breaks a build. That pushes users to add `@allow` without thinking, and the habit lasts after the bug is fixed." … "**Dependencies.** Blink has no `--cap-lints` … If a compiler upgrade adds a lint that is an error by default, every library that trips it breaks every downstream build." DevOps also flagged "a loop that `break`s after its first `with`" as a case the rule must not count twice.
- **AI/ML:** "**Proposal 1 (main): W0611 is an error by default. It stays a warning name.**" … "*The rule must be precise first.* An error that fires on correct code teaches agents to add `@allow` wherever it fires. So before W0611 can be an error, §5.5 must state the path rule: "W0611 fires when one execution path takes the value into two `with` items. Two `with` items on paths that exclude each other count as one.""
- **Minimalism:** "**Proposal M1 (primary): keep W0611 a warning by default. Change no spec text.**" … "**There is no data.** W0611 has no emit site yet … If we pick a default severity now, we guess." … "**The danger is in the handle, not the lint.**" … "**"Error by default" adds a concept.** Every warning name defaults to `"warn"` today."

#### Phase B — Debate highlights

The moderator grouped the proposals into O1 (warning now, with variants for where raise conditions are written), O2 (error by default now), O3 (decide now on an edition raise), O4 (error only when `exit()` reaches `@ffi`) and O5 (move to *Error Names*), plus sub-questions Q2–Q7. O4 and O5 had no support. All six ended round 1 "stable".

- **Web drops the fixed edition promise:** "I drop my Web B wording ("becomes an error in the next edition" as a fixed commitment)." Web held O2 with a gate: "Before merge, [the emit-site change] runs the corpus and lib/std under the per-path rule (Q2) … If any false positive shows up, W0611 ships at "warn"".
- **PLT on O2 as a raise without an edition:** "A library that enters `conn` in a loop builds today. When [the emit-site change] ships with a default of "error", that library stops building. §8.16.1 gates exactly that case". On copies: "It must fire. Copies share the box … The §5.5 per-path sentence should add: "A copy of a scoped value is the same value."" PLT also wrote the loop-exit clause: "A `with` in a loop body counts as two, unless every path through the body after that `with` leaves the loop." On [the "deny" question]: "I drop my request to decide the two together."
- **DevOps on precision fixes:** "under O2 the lint itself becomes a breaking surface. Every later change to how precise the flow analysis is … adds new errors to builds that passed before. Blink has no `--cap-lints`, so those new errors also fail builds of every downstream package". DevOps moved from O1c to O1d: "my O1c sentence … is a process promise. It is not a rule of the language".
- **AI/ML concedes on dependencies:** "In Phase A I wrote that an error now "breaks nothing" because no program has seen W0611. That was wrong. The *pattern* can exist in libraries today. Only the emit site is new."
- **Systems and PLT on keeping the name a warning name:** Systems: "A raise at an edition changes the default level of a warning name, so `@allow` keeps working for `Cleanup`. Moving the name breaks the legal case for good." PLT: "Any future promotion must keep the name under *Warning Names* with a default of "error" (O3). The decision should say so".
- **Systems on "should":** ""A type that wraps a foreign handle makes a second `exit()` safe" reads as a guarantee. For user types it is only guidance (blockhandler-enter-exit-state Q3, "should")."

#### Phase C — Final vote

- **Q1: default severity** (O1 4-2; Web/Scripting and AI/ML for O2; went to Phase D)
  - **Systems:** O1 — "an error by default stops one shape of the bug and gives a false sense that the compiler checks the rest. The rule is not exact yet either (Q2), and no hit count exists."
  - **Web/Scripting:** *(dissent)* O2 — "The users this lint protects are the ones who do not read warnings: JS and Python devs used to `with` that can be reused, and agent loops that check only the exit code." Concern: "Real user code may write per-path or copy shapes the corpus lacks, and then the first false positives reach users as failed builds and not as warnings."
  - **PLT:** O1 — "An error default would claim more than the analysis can prove, and a clean build would read as "no double entry", which is false. O2 also raises severity on programs that build today, and §8.16.1 says only an edition may do that."
  - **DevOps:** O1 — "An error-by-default lint makes each later precision fix (copies, loop exits, call-following) a breaking change." Concern: "agent loops that check only exit codes will ignore the warning until a harness or `blink init` template sets the lint level."
  - **AI/ML:** *(dissent)* O2 — "An agent loop reads the exit code, not the warning text." Concern: "If O1 wins, models will copy the double-`with` loop from code that compiles with exit 0".
  - **Minimalism:** O1 — "W0611 has no emit site, so no one can measure how often it fires on correct code. A severity choice now is a guess." Concern: "the decision must say that [the emit-site change's] data triggers that review."
- **Q1b: where the conditions for a later raise are written** (c 3, d 3; went to Phase D)
  - **c** (§5.5 and catalog sentence): PLT, Web/Scripting, AI/ML. **d** (decision file and a ticket note only): Systems, DevOps, Minimalism.
- **Q1c: any future raise keeps the name under *Warning Names*** (yes, 6-0)
  - **PLT:** "§4.16.8's test does not change with an edition, so the decision should say this now and not reopen it later."
- **Q2a: per-path rule** (yes, 6-0)
  - **Systems:** "Exclusive branches enter the value once at run time. Counting them twice is a precision bug at any severity."
- **Q2b: loop-exit clause** (clause 5-1, Minimalism dissent: explain-only)
  - **Systems:** "A `break` or `return` after the `with` on every path means one entry at run time. That is the same per-path rule".
  - **DevOps:** "I change from explain-only. An exact rule in the spec gives the implementer and the LSP one test to check".
  - **Minimalism:** *(dissent)* "the clause adds a second flow rule to the spec for one rare loop shape. Under O1 a known false positive in a warning costs little, and `blink explain` can name it."
- **Q2c: a copy is the same value** (yes, 6-0)
  - **PLT:** "Copies share the box …, so they are one scoped value. Without this sentence, an implementer can track names, not values".
- **Q3: "not a safety check" text** (b 4, c 1, d 1; went to Phase D)
- **Q4: severity note line in the W0611 sample** (yes, 6-0)
  - **DevOps:** "W0611 and W0610 then print the same note, and the note is how a team or an agent harness finds the opt-in."
- **Q5: default-level catalog column if a raise ever happens** (yes 5-0, Minimalism n/a; moot under O1)
  - **PLT:** "If any default other than "warn" exists, it is data that tools (explain, LSP, migrate) read, so it belongs in a column, not in prose."
- **Q6: precedence line; "deny" stays a separate question** (yes, 6-0)
  - **Systems:** "One stated precedence order keeps severity a single order of strength. "deny" needs its own decision about whether it beats `@allow`."
- **Q7: the `TcpSocket` double-close bug blocks the next stdlib release** (yes, 6-0)
  - **Web/Scripting:** "Closing an fd that the OS gave to other code is the worst bug in this area, and the fix belongs in the wrapper."
- **Q8: file a ticket for a dependency lint cap** (yes 5-1, Minimalism dissent)
  - **PLT:** "Severity per package with no cap makes any future default raise reach downstream builds. A ticket records that gap. It decides nothing."
  - **Minimalism:** *(dissent)* "under O1 no new error-by-default lint exists that could break a dependency. YAGNI until a lint does."

#### Phase D — Round 2 (Q1, Q1b, Q3)

The focused debate added three merges. O1+T is O1 plus a stated trigger for the review. Two of the Q1b options keep the conditions in the decision file and add a short §5.5 pointer. Three of the Q3 options fold the text into the existing "not a proof" sentence. Each voter gave a ranked vote; the moderator counted first choices and dropped the last option until one had four.

- **Web/Scripting (debate):** "**PLT: "O2 also raises severity on programs that build today, and §8.16.1 says only an edition may do that."** This is right, and it removes my main argument." … "So my O1 vote has one condition, which fits inside O1: the decision says that [the emit-site change's] corpus data **triggers** the edition review".
- **AI/ML (debate):** "**DevOps:** "An error-by-default lint makes each later precision fix (copies, loop exits, call-following) a breaking change." This argument is new to me, and it decides my vote." … "A review that only "may" happen does not happen."
- **PLT (debate, Q1b):** "A "may become an error in a later edition" sentence is not a rule. It states no behavior, and §8.16.1 already grants that power to every warning. Spec text should state rules."
- **Systems (debate, Q1b):** "Web: "A sentence that lives only in decisions/ or br is invisible to anyone who reads §5.5". AI/ML makes the same point." … "That gives the spec reader the one fact they need, keeps the process out of sections/, and leaves out the ambiguous "no false positives"."
- **Minimalism (debate, Q3):** "My objection was only that this adds a sentence. So I propose that the panel put b's content into the existing sentence".

- **Q1: default severity** (O1+T, 6-0 R2 after 4-2 R1)
  - **Systems:** O1+T > O1 > O3 — "The trigger makes [the emit-site change's] hit count force an actual review, so the move to "error" does not stall for no reason." Concern: "Until the edition review runs, agent loops that check only the exit code ship the double-`with` loop, so the `blink init` template should set `W0611 = "error"`."
  - **Web/Scripting:** O1+T > O3 > O1 — "PLT and DevOps convinced me that O2 is a severity raise without an edition, on an analysis that will grow new hits. The trigger keeps the "agents read exit codes" problem on a clock". Concern: "The trigger says a review happens, not when."
  - **PLT:** O1+T > O1 > O3 — "The trigger turns the review from "some day" into a step that follows [the emit-site change's] data, and it fixes no level in advance." Concern: "the trigger must name an owner and not stay a sentence."
  - **DevOps:** O1+T > O1 — "With the trigger, the review is no longer a promise that someone has to remember." Concern: "If no ticket is filed for the edition review when [the emit-site change] merges, O1+T turns back into plain O1."
  - **AI/ML:** O1+T > O1 > O3 > O2 — "At error level, a later widening (following a value into a call) fails builds that passed before, and dependencies cannot `@allow` the hit." Concern: "Nothing in the code holds the trigger, so it lives only in the decision file."
  - **Minimalism:** O1+T > O1 > O3 — "It adds no spec text and no catalog concept. It also makes sure the review runs once the data exists." Concern: "[the emit-site] ticket must say who runs the review."
- **Q1b: where the conditions for a later raise are written** (3-3 → user broke tie for d)
  - First choices: d 3 (PLT, AI/ML, Minimalism), cd-measured 2 (Systems, Web/Scripting), bd 1 (DevOps). bd dropped; DevOps's next choice was cd-measured, which gave d 3, cd-measured 3. Compared two at a time, d tied every sentence option 3-3.
  - **PLT:** d > bd > cd-measured — "Spec text should state behavior. A "may raise later" sentence states none". Concern: "If a sentence wins, the next warning name will be expected to carry the same "may raise" line, and that is spec noise."
  - **AI/ML:** d > cd-short > bd > cd-measured — "A model or user reading it needs what the lint does today, and a sentence about a possible raise changes no code."
  - **Minimalism:** d > cd-short > bd > cd-measured — "the decision file holds every condition in all of these options, so the spec text adds only a pointer to §8.16.1, which already exists."
  - **Systems:** *(dissent)* cd-measured > bd > cd-short > c > d — "A reader of §5.5 should learn that a raise is possible and that measured data gates it."
  - **Web/Scripting:** *(dissent)* cd-measured > cd-short > bd > d — "Users read §5.5, not decision files, so the spec should tell them that double-entry code may fail later."
  - **DevOps:** *(dissent)* bd > cd-measured > cd-short > c — "I leave out d, because the spec should not hide a planned change from the people who read it."
  - **User tiebreak:** d.
- **Q3: "not a safety check" text** (bd-1, 4-2; Web/Scripting and DevOps first chose b and ranked bd-1 second)
  - **Systems:** bd-1 > bd-3 > b > bd-2 — "bd-1 keeps one sentence, names the lint as "not a safety check", and gives the author of a foreign-handle wrapper the "should" duty."
  - **PLT:** bd-1 > bd-2 > b > bd-3 — "bd-1 places where the guarantee lives inside the existing sentence, with fewer words than my bd-2, so I move to it." Concern: "`blink explain W0611` must show that case."
  - **AI/ML:** bd-1 > b > bd-3 > bd-2 — "bd-1 puts the fact and the instruction next to the existing "not a proof" sentence, where a model reading the limit finds it". Concern: "`blink explain` should show one wrapper with no guard against a second `exit()` and one with it."
  - **Minimalism:** bd-1 > bd-3 > bd-2 > b — "bd-1 has b's content and adds no sentence."
  - **Web/Scripting:** *(dissent)* b > bd-1 > bd-3 > bd-2 — "Two short sentences are easier to read than one long one, and the blind spot and the wrapper duty are separate points."
  - **DevOps:** *(dissent)* b > bd-1 > bd-3 > bd-2 > c — "a separate short sentence works best when the text appears in an editor hover and in `blink explain`."

### Final Spec

§5.5, W0611:

> A scoped value must reach exactly one `with` item. W0611 counts the `with` items that one execution path takes the value into, and fires when the count is two or more. Items on paths that exclude each other (`if`/`else` branches, `match` arms) count once. A `with` in a loop body that enters a value built outside the loop counts as two, unless every path through the body after that `with` leaves the loop. A copy of a scoped value is the same value: `let copy = conn` followed by `with copy` enters `conn`. … No W0611 is not a proof that a value goes into one `with` only, and W0611 is not a safety check: a type that wraps a foreign handle should make a second `exit()` safe (§4.7.2).

The W0611 sample ends with `= note: upgrade to error in blink.toml: [lints] W0611 = "error"`, as W0610's does.

- **Severity (Q1):** W0611 stays a warning by default. `[lints] W0611 = "error"` raises it per project; `@allow(ScopedValueEnteredTwice)` suppresses it per function. The spec text about severity does not change.
- **Review trigger (Q1, Q1b):** the corpus data from the change that adds W0611's emit site starts an edition review of its default level (§8.16.1). No sections/ text records this. The review's conditions:
  1. W0611 has an emit site in the compiler.
  2. The emit site applies the per-path rule as voted here (exclusive paths count once, loop-exit clause, copies are the same value).
  3. A hit count on the test corpus and lib/std, where every hit is classed as a true double entry, a tagged `@allow` case, or a false positive. A false positive is a hit on a path that, at run time, enters the value into one `with` only.
  4. The `TcpSocket`/`TcpListener` second close is fixed, so that no stdlib wrapper relies on W0611.
- **Name stays a warning name (Q1c):** any later raise changes only the default level. The name stays under *Warning Names*, so `@allow` and `[lints]` still reach it and `Cleanup` keeps a legal form.
- **Default-level data (Q5):** if a raise happens, the default level is a column in ERROR_CATALOG.md, not prose.
- **Precedence (Q6):** `@allow` > `[lints]` > catalog default (§4.16.8). A `[lints]` level that `@allow` cannot override ("deny") stays a separate question.
- **Tracking (Q7, Q8):** the `TcpSocket` second-close bug blocks the next stdlib release. A ticket records the lack of a lint cap for dependencies.
