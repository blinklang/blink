[< All Decisions](../DECISIONS.md)

# Scoped Value Lint Code — Design Rationale

The diagnostic catalog gave W0600 to `UnusedVariable`, and the compiler emits it under that name.
§5.5 had used W0600 for the lint once named `CloseableWithoutScope`. The scoped effect handler
decision renamed that lint `ScopedValueWithoutWith` (6-0) and left its code open until this clash
was settled. The catalog *Conventions* say a name is stable API and is frozen once published, and a
code is secondary and never reused after retirement. `[lints]` in `blink.toml` keys on codes and
`@allow` keys on names, so a code is user configuration as well as a log token.

The panel answered two questions: the code for `ScopedValueWithoutWith` (Q1, with Q1b on a second
range row) and what happens to the old name `CloseableWithoutScope` (Q2). It also settled five
variations: a pointer line in `blink explain W0600` (V1), when the constant and explain entry land
in the compiler (V2), a `task ci` consistency check (V3), the stale "§6" spec-ref on W0600–W0602
(V4), and the `@allow(W0600)` example in llms-full.md (V5). All six panelists agreed from Phase A
that `UnusedVariable` keeps W0600.

**A note on quotation.** Panelist text below is verbatim. The single exception is `br` ticket
identifiers: `br` is local-only, so per the repo rule that keeps local IDs out of spec, decisions,
and source, each is replaced by a bracketed description of the ticket. No other substitution was
made, and no panelist text was reworded or shortened without an ellipsis.

---

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in
independent-proposal → debate → vote rounds. Phase A produced six proposal sets. Phase B ran one
round, after which all six marked "STABLE — ready to vote". Phase C was a silent vote. Q1b, V1 and
V2 went to a Phase D round. After that round the user asked for a re-debate of V3, which had
passed 4-2 in Phase C, and a second Phase D round ran on V3 alone.

#### Phase A — Independent proposals

- **Systems:** "Evidence for leaving W0600 alone: the compiler has emitted `UnusedVariable` as W0600
  since 2026-02-13 … If we renumber the live rule, a user's existing config starts to mean something
  else without any notice. A suppression of unused-variable noise would become a suppression of a
  resource leak. That is the worst outcome possible here: same input, different binary behaviour,
  no diagnostic." On the old name: "The code column must not list W0600 as retired, because W0600 is
  live and the Conventions forbid reuse of a retired code. That is why the row names the old code in
  prose and does not claim it." On the number: "**Why W0610 and not W0605:** W0605 would put a
  resource-safety lint inside the hygiene block (unused, shadowed). Teams turn that block off in
  bulk." And: "**Proposal S2 (required in any option): a CI check that stops this from happening
  again.** This clash survived seven months because the catalog, the spec and `diagnostics.bl` are
  three separate sources."
- **Web/Scripting:** "**Proposal W1 (my pick): `UnusedVariable` keeps W0600.
  `ScopedValueWithoutWith` gets W0605. The catalog marks the old spec name as retired.**" Its
  reasoning: "**Real users hit only one of the two rules.** UnusedVariable is the warning every Python
  or JS developer sees in their first ten minutes. … Nobody can have W0600 in a config that means
  "closeable". Moving UnusedVariable breaks real configs. Moving the other rule breaks nothing." And:
  "Why W0605: it is the next free W06xx slot. … It costs no new range." Its alternative W2: "Add two
  Category Ranges rows: `W060x | Linting (unused / shadowing)` and `W061x | Resource scope`. … YAGNI
  says W1."
- **PLT:** "Conventions say a published name is "never renamed, never reassigned". The
  scoped-effect-handler decision (705b9dcd, 6-0) renamed `CloseableWithoutScope` to
  `ScopedValueWithoutWith`. That rename only agrees with Conventions if `CloseableWithoutScope` was
  never *published*. … So the rule set is consistent only under one reading: **a diagnostic identity
  (name or code) is published when a compiler emits it.**" Its P1: W0610, Category Ranges rows
  `W060x | Linting (unused / shadowed bindings)` and `W061x | Resource scope lints`, and
  "`CloseableWithoutScope` gets **no** Retired Codes row." Its soundness guard: "Writing "one code
  per rule" in prose did not stop this clash, and it will not stop the next one. A check will."
- **DevOps:** "`[lints]` keys on codes, so if we move W0600, every existing `W0600 = "off"` silently
  turns into "turn off the resource-safety lint". That is a silent change to the meaning of user
  config, the worst kind of break a toolchain can ship." Its D1: W0610 with a `W061x | Resource scope
  lints` row, and a Retired row for `CloseableWithoutScope` whose "Code cell is "—" on purpose. W0600
  is live, so a table that lists it as retired contradicts "codes are never reused"." It added:
  "`blink explain W0600` keeps its UnusedVariable text and adds one line: "An early draft of §5.5
  used W0600 for the lint now named ScopedValueWithoutWith; that is W0610."" And: "llms-full's
  `@allow(W0600)` example changed to `@allow(UnusedVariable)`. `@allow` keys on names, so the
  current example teaches the wrong channel."
- **AI/ML:** "`ScopedValueWithoutWith` gets **W0610**. … Use W0610, not W0605: W0605 makes the lint
  look like the next linting rule after the W0600–W0604 group. W0610 starts a resource sub-band that
  lines up with E0601/E0602, which are the other two rules in the §5.5 "closed net"." Its tombstone
  row put "(W0600, spec-only, never emitted)" in the Code cell. Its reason: "A model trained on that
  history will write that line and silently turn every unused variable into an error. The fix is to
  give the old association an explicit, searchable answer." And: "`blink explain W0600` gets a "Not
  to be confused with" line: "Older docs used W0600 for the closeable lint; see W0610.""
- **Minimalism:** "My recommendation is M1: UnusedVariable keeps W0600, ScopedValueWithoutWith
  takes W0605, and nothing else changes." On timing: "add `pub const SCOPED_VALUE_WITHOUT_WITH =
  "W0605"` and explain text with the [the ScopedValueWithoutWith emitter ticket] emit site, in the
  same commit as the emit site. Do not add them before it. A constant with no emit site is dead
  code, and an explain entry for a lint that never fires describes a rule that does not exist (§3.1
  rule 1 in spirit)." On the old name: "No Retired Codes row for CloseableWithoutScope. W0600 is not retired, so
  a row "CloseableWithoutScope | W0600" claims a live code is retired, and `blink explain W0600`
  would then have two answers again." Its fallback M2 was a name-only Retired row: "This needs a "—"
  code cell, a shape the table does not have yet. I vote against it."

All six rejected moving `UnusedVariable` off W0600.

#### Phase B — Debate highlights

Round 1 grouped the proposals into two Q1 options (W0610 with a `W061x` row; W0605 with no row),
four Q2 options ((a) a name-only Retired row with Code "—"; (b) aiml's row with W0600 in the Code
cell; (c) plt's Conventions sentence and no row; (d) no row and no change), and the variations
V1–V5. Several panelists changed position.

**Web moved to W0610:** "**Q1: I switch to W0610 + a `W061x | Resource scope lints` row.** Four of
six panelists back it. The range row also gives users a rule they can remember ("W061x =
resources"), which W0605 does not." It also moved on Q2: "**Q2: I move from (a) to (c), plt's
Conventions sentence.** … Under (a), we write a Retired row for a name that no user ever saw: it was
never emitted and is not in CHANGELOG. That row is archaeology, not help."

**Minimalism did not block W0610, and moved from (d) to (c):** "**Q1 — I still prefer W0605, but I
do not block W0610 + `W061x` range.** … If the panel takes W0610, I ask for one change: name the row
`W061x | Resource scope lints`, to match E06xx, and do not add plt's extra `W060x` row." And: "(c)
gives the same outcome as (d), with no row for CloseableWithoutScope, but it states the rule, so the
next spec-only name does not need a panel. I am against (a): a "—" code cell is a new table shape
that exists only to honour a name no compiler ever emitted."

**PLT conceded its own (c) and dropped its `W060x` row:** "**Q2: I concede (c) and take (a)**
(sys/web/devops). On reflection, a Retired row with "Replaced by" is the catalog's own way to record
a rename." And: "I drop my extra `W060x` row. It is cosmetic, and the next lint can add it."

**AI/ML conceded (b) for (a), on a condition:** "**Q2: I concede to (a), a name-only row with Code
"—".** My option (b) existed to record the link between W0600 and the old lint. V1 records that link
in a better place: the explain output for the code itself, which is where a model or user looks." Its
argument against (c): "`CloseableWithoutScope` was in the published catalog from February to May
2026, so it is already in training data. Under (c), `blink explain CloseableWithoutScope` returns
nothing."

**Systems made the case against (c):** "The rule "spec text that names an unimplemented diagnostic
reserves nothing" also applies to `ScopedValueWithoutWith` today, because it has no emit site until
[the ScopedValueWithoutWith emitter ticket]. The panel decided that name 6-0, and (c) would leave it
unreserved." This point moved web, PLT and minimalism to (a) in the vote.

**DevOps conceded V2 to minimalism:** "**V2: I concede to min.** The catalog row reserves W0610 now.
The constant and the explain entry land in the [the ScopedValueWithoutWith emitter ticket] commit
with the emitter. A constant with no emitter is dead code, and an explain entry for a lint that
never fires tells a user something false." On V3: "**yes, in this change, at minimum the two checks
that would have caught this bug:** each code maps to one live name, and no code is both live and
retired. … "Spec codes match catalog names" means parsing prose and gives fuzzy hits, so that part
should be a follow-up ticket."

**Systems offered a middle form for V2:** "**V2: land it now, with no emitter.** … I accept min's
position if the explain text gets a "not yet emitted" line that [the ScopedValueWithoutWith emitter
ticket] removes."

**V4 moved to a separate ticket.** Web: "**V4: concede, separate ticket.** Four to two. Keeping the
change small makes it easier to review." PLT: "**V4: I concede a separate ticket.** It is the same
kind of bug, but it is a different fix (where UnusedVariable gets specified), and scope discipline
wins."

#### Phase C — Final vote

##### Q1: the code for `ScopedValueWithoutWith` (**5-1, (A) W0610 + `W061x | Resource scope lints`**)

- **Systems:** A — "`[lints]` keys on codes, so the code's decade is the unit a team uses for policy.
  A resource-leak lint must not sit in the hygiene decade, which teams turn off as one group."
  *Concern:* "with no rule that defines what a W range means, the next lint author can still put a
  resource lint somewhere else."
- **Web/Scripting:** A — "Users can learn a range ("W061x = resources"). They cannot learn the next
  free slot. It also groups the warning by number with E0601 and E0602, its partners in the "closed
  net"." *Concern:* "one lint now holds a whole range, and the next resource lint may not fit the
  label."
- **PLT:** A — "The code lands in the same 06 block as E0601/E0602, the other two parts of the §5.5
  "closed net". The Linting block stays for binding lints only." *Concern:* "W06xx would then hold
  two categories, split at the tens digit, and a later lint could take a W061x code for a
  non-resource rule unless reviewers check the range table."
- **DevOps:** A — "a `[lints]` block shows only codes, so a range is the only grouping a user who
  reads config ever gets. With a resource range, `W0610 = "error"` in a CI policy file is easy to
  understand without docs." *Concern:* "the W061x range must stay limited to resource-scope lints,
  or it loses its purpose as a grouping."
- **AI/ML:** A — ""06 = resource scope" then holds for both E and W codes, so a model learns one rule
  instead of a rule plus an exception." *Concern:* "the next resource lint may still take a W060x code
  by habit unless the Category Ranges table is the first thing a contributor reads."
- **Minimalism:** B (dissent) — "Codes are secondary tokens, and a band with one member is a guess
  about lints nobody has proposed. W0605 is the next free number and needs no new table row. I do not
  block (A)." *Concern:* "Under (A), the `W061x` band asks future authors to sort lints by category,
  so we will start arguing about which band a lint goes in."

##### Q1b: also add a `W060x` row (**4-2 YES; went to Phase D**)

- **Systems:** YES — "W061x as an explicit range, next to W060x as an unlabelled one, leaves the
  boundary implicit." *Concern:* "the label "unused / shadowed bindings" is too narrow for W0604
  UnusedTypeParamBinder. The wording must cover it."
- **Web/Scripting:** YES — "Today the ranges table has no layout for W codes, and that gap helped
  cause this clash."
- **PLT:** NO (dissent) — "It is cosmetic, and a range row with no use behind it adds nothing a reader
  needs. The next binding lint can add it when it lands." *Concern:* "Without the row, W0600–W0604
  have no range entry, so someone could treat W06xx as all resource scope and put a resource lint at
  W0605."
- **DevOps:** YES — "W0600–W0604 already work as one family, and today the Category Ranges table does
  not list any W06xx row. Adding the row makes the table describe what exists."
- **AI/ML:** YES — "Without it, the range has no name, so a model guesses what the 06 prefix means."
- **Minimalism:** NO (dissent) — "The `W060x` row only describes codes that already exist, and it is
  cosmetic. plt, who proposed it, dropped it. W0604 (a type-parameter lint) already makes the label
  "unused / shadowed bindings" inaccurate."

##### Q2: the old name `CloseableWithoutScope` (**6-0, (a) Retired row, name only, Code "—"**)

- **Systems:** (a) — "(c) unreserves every spec-decided name that has no emitter yet, and that
  includes `ScopedValueWithoutWith` until [the ScopedValueWithoutWith emitter ticket] lands. A Retired
  row is the catalog's existing way to record a rename." *Concern:* "a "—" Code cell is a new table
  shape, and a mechanical check must parse it as "no code" and not as a malformed row."
- **Web/Scripting:** (a) — "I change from (c). aiml's fact settles it for me: the name was in the
  published catalog from February to May, so readers and training data have it." *Concern:* "a "—"
  code cell is a new shape in the table, and readers may ask what it means unless the preamble says so
  in one clause."
- **PLT:** (a) — "sys's point decides it for me: the rule in (c) would leave `ScopedValueWithoutWith`
  itself unreserved until [the ScopedValueWithoutWith emitter ticket] emits it, which conflicts with
  the panel's 6-0 decision. That also rules out (a+c). Code "—" is accurate, because the name never
  held a live code." *Concern:* "Readers may take "—" to mean "code unknown" rather than "never had
  one", so the Retired preamble needs one clause that says so."
- **DevOps:** (a) — "the Retired preamble promises that `blink explain CloseableWithoutScope` names
  the replacement. With no row, that command prints "unknown code" to a reader who learned the name
  from the Feb–May catalog." *Concern:* "the Code cell "—" is a new shape for the table, so any tool
  that parses the table must accept a row with no code."
- **AI/ML:** (a) — "`blink explain CloseableWithoutScope` must then say "retired, see
  ScopedValueWithoutWith (W0610)" instead of "unknown"." *Concern:* ""—" is a new cell shape, so the
  Retired preamble needs one clause that says a row can retire a name with no code."
- **Minimalism:** (a) — "I change my vote. sys showed that the (c) sentence as worded leaves the
  6-0-decided `ScopedValueWithoutWith` unreserved until [the ScopedValueWithoutWith emitter ticket]
  emits it. … One table row costs less than a Conventions rule with a hole in it." *Concern:* "The "—"
  code cell is a new table shape, and a later author can copy it to tombstone names that never reached
  a catalog."

Four panelists asked for one preamble clause on "—". The catalog change adds it.

##### V1: a pointer line in `blink explain W0600` (**3-3; went to Phase D**)

- **Systems:** YES — "the old §5.5 told users to write `W0600 = "error"` to catch leaks. One explain
  line tells them that key never meant that. It is the only signal they get, because the config
  itself raises no error."
- **Web/Scripting:** NO — "`blink explain W0600` should tell a developer how to fix an unused
  variable, not tell the history of a spec draft. The Retired row from (a) already catches anyone who
  looks up the old name."
- **PLT:** NO — "A live code's explain entry should describe one rule. Adding history there is a
  second meaning, the same kind of overlap this ticket removes."
- **DevOps:** YES — "W0600 is the code users actually type into config and search for. One pointer
  line there sends the reader of the old §5.5 draft to W0610, so explain no longer answers one
  question and ignores the other."
- **AI/ML:** YES — "a model that copies them makes every unused variable an error. The explain output
  for that code is the one place a reader looks, so the correction must be there."
- **Minimalism:** NO — "A pointer in `blink explain W0600` puts a draft that never shipped next to a
  live rule, which is a soft form of the "two answers" bug. That history belongs in the Retired row
  and in git."

##### V2: when the constant and explain entry land (**4-2 emit; went to Phase D**)

- **Systems:** now+note (dissent) — "if the constant lands now, the V3 check has a real row to
  verify, and `W0610 = "error"` is a known key from day one. The "not yet emitted" line stops explain
  from describing a rule that does not fire as if it did."
- **Web/Scripting:** emit — "an explain entry for a warning the compiler cannot print misleads users."
- **PLT:** emit — "A constant with no emitter is a declared rule that has no meaning yet in the
  compiler. If they land together, every constant has an emitter and the V3 check stays exact."
- **DevOps:** emit — "an explain entry for a lint that never fires tells a user something false. The
  catalog row already reserves the code, so landing the constant early gains nothing."
- **AI/ML:** now+note (dissent) — "when the spec names W0610, `blink explain W0610` should not return
  "unknown"."
- **Minimalism:** emit — "An explain entry, even one with a "not yet emitted" note, describes a rule
  the compiler does not enforce."

##### V3: a `task ci` consistency check (**4-2 narrow**)

- **Systems:** full (dissent) — "this clash was spec prose vs catalog name. Narrow checks only
  constants against the catalog, so it would not have caught the bug we are fixing." *Concern:*
  "matching prose is brittle (code and name in the same sentence or heading), so it can give false
  positives that people learn to ignore."
- **Web/Scripting:** narrow — "I change from (follow-up). The narrow checks are cheap and would have
  caught both this ticket and [the W0603 code-clash ticket], and a fix with no guard tends to come
  back."
- **PLT:** full (dissent) — "A check that leaves out the failure we just had is not a guard against
  it. Code references in sections/ use a fixed format (`W0600`, `` `Name` ``), so the matching does
  not need a full prose parser." *Concern:* "The spec-text matcher may give false positives on
  historical or example text and need an allowlist, which could grow until the check means little."
- **DevOps:** narrow — "these checks would have caught this exact bug, and they are cheap and give no
  false hits."
- **AI/ML:** narrow — "one name per code and no code in both tables is exactly the invariant this
  ticket broke, and the check is cheap."
- **Minimalism:** narrow — "Spec-prose matching needs a second tool that parses the spec text, so it
  belongs in its own ticket."

The moderator first read this result as settled. The user asked for a re-debate, which ran as the
second Phase D round below.

##### V4: the stale "§6" spec-ref on W0600–W0602 (**6-0, separate ticket**)

- **Systems:** "a dead spec-ref is a different defect from a code clash. A focused diff is easier to
  review and to revert."
- **Web/Scripting:** "The "§6" fix needs its own answer for where those rules are specified."
- **PLT:** "It is the same class of bug but a different fix, because UnusedVariable needs a real home
  in the spec."
- **DevOps:** "before anyone can fix "§6", someone must decide which section specifies these lints.
  That is a spec decision, not a cross-reference fix."
- **AI/ML:** "no spec section defines these rules, so a correct fix means writing new spec text."
- **Minimalism:** "The "§6" link that points at no section is a real gap but unrelated to this one."

##### V5: llms-full.md `@allow(W0600)` → `@allow(UnusedVariable)` (**6-0, YES**)

- **Systems:** "names are the stable API and `@allow` keys on names, so docs that LLMs learn from must
  show the stable form. CHANGELOG is history and stays as it is."
- **Web/Scripting:** "A wrong example there spreads the exact confusion this ticket is about."
- **PLT:** "`@allow` keys on names by Conventions, so `@allow(W0600)` teaches a form the spec does not
  define, in the file LLMs read."
- **DevOps:** "`@allow` takes names, and llms-full is the source that AI users copy from, so the wrong
  example spreads."
- **AI/ML:** "llms-full.md is the surface models read most, so this one-line edit has a large effect."
- **Minimalism:** "It is a one-line change. The Conventions say suppression uses names, and this
  example is a W0600 reference."

#### Phase D — Round 2

##### Q1b, V1 and V2

Each panelist saw the others' Phase C text on these three items and gave one reply.

**Q1b moved to 6-0 YES.** PLT and minimalism changed their votes. Every panelist agreed that the
label "unused / shadowed bindings" did not fit W0604, and four labels were proposed.

- **PLT:** "sys and web are right that W061x as a labelled range next to an unlabelled W060x leaves
  the boundary implicit. That is the same failure I gave as my own concern in Phase C, so my NO did
  not hold up against my own argument." Vote: "YES, with the label `W060x | Linting` (not "unused /
  shadowed bindings")."
- **Minimalism:** "plt's concern changes my vote. … My NO was about the label, not the row. … Make the
  label match the catalog's own Category column: `W060x | Linting`."
- **Systems:** "Label the row `W060x | Linting (unused / shadowed binders)`. A type parameter is a
  binder, so W0604 fits without strain."
- **Web/Scripting:** "Name the row so it covers all five codes: `W060x | Linting (unused or shadowed
  declarations)`."
- **AI/ML:** "Use `W060x | Unused or shadowed names` or `W060x | Unused or shadowed declarations`,
  both of which cover W0604 UnusedTypeParamBinder."
- **DevOps:** "Label it `W060x | Linting`, which is the word the catalog's Category column already
  uses for W0600–W0604."

The user chose `W060x | Linting`. No reasoning was stated.

**V1 stayed 3-3** (YES: systems, AI/ML, DevOps; NO: web, PLT, minimalism).

- **Systems:** YES — "plt and min call the pointer a "second meaning". It is not one, because it does
  not change what W0600 means. It warns that a config key meant something else in a draft. … Keep it
  to one "See also" line, not prose about the history."
- **AI/ML:** YES — "It does the opposite: the line says W0600 has one meaning and never had the other.
  That is a disambiguation, not a second rule." Proposed text: "Not to be confused with
  ScopedValueWithoutWith (W0610), which a draft of §5.5 numbered W0600."
- **DevOps:** YES — "Sys has the decisive point: a stale `W0600 = "error"` produces no config error,
  so explain is the only place the user gets the correction." Proposed text: "W0600 has never meant
  ScopedValueWithoutWith; that lint is W0610."
- **Web/Scripting:** NO — "I searched the worktree, and the old §5.5 line `W0600 = "error"` is no
  longer in the repo. … So the stale meaning lives only in git history and in pre-May training data,
  and the (a) Retired row already catches anyone who looks up the old name."
- **PLT:** NO — "an explain pointer does not stop that copy. Config and model output are written
  without running `blink explain`, so the pointer reaches only the readers who are already checking."
- **Minimalism:** NO — "sys and aiml say a stale `W0600 = "error"` gives no signal. That is not true.
  Every unused variable becomes a hard error at once, and the diagnostic header says
  `UnusedVariable`, so the user sees the mismatch on the first build."

The user broke the tie for YES. No reasoning was stated.

**V2 moved to 5-1 emit.** Systems and AI/ML moved to emit; DevOps moved from emit to now+note.

- **Systems:** "I concede to emit. My reason for "now" was that V3 needs a constant to verify. But V3
  checks constant → catalog row, and the catalog row and §5.5 reserve W0610 either way, so landing the
  constant early adds nothing to check."
- **AI/ML:** "web, plt, devops and min convince me that a constant with no emitter, even with a note,
  is a declared rule the compiler does not enforce. … I concede."
- **DevOps** (dissent): "I am changing my vote. My reason for emit was "explain says something
  false", and sys's note removes that falsehood. Plt's own concern shows what emit costs: `blink
  explain W0610` prints "unknown" while the spec and the catalog name the code."
- **PLT:** "Adding a check to make up for a state we chose to create is the wrong way round."
- **Minimalism:** "(emit) needs only one line in [the ScopedValueWithoutWith emitter ticket]'s
  done-criteria: "adds the constant, the explain entry, and an emit site together.""
- **Web/Scripting:** "A "not yet emitted" note is text that someone has to remember to delete."

##### V3, re-debated

Before this round the moderator checked git history and gave the panel these facts:

- 2026-02-13 (7cfb7857): the catalog gets the row `CloseableWithoutScope | W0600`.
- 2026-03-06 (d22ce739): the compiler starts to emit W0600 for unused local variables.
- 2026-05-03 (8eb7be9c): the catalog row becomes `UnusedVariable | W0600`.
- 2026-05-03 to 2026-09-29 (705b9dcd): §5.5 still uses W0600 for the Closeable lint. Its code block
  header was `warning[CloseableWithoutScope]`, and its note said `[lints] W0600 = "error"`.

These dates correct the Phase A brief, which gave 7cfb7857 as the commit where the compiler first
emitted W0600. The Systems Phase A text quoted above repeats that earlier date.

The facts showed two windows. A (name, code) check of compiler constants against the catalog would
have failed on 2026-03-06. Only a check that reads the spec would have caught May to September. Five
panelists changed their votes.

- **Systems:** full → narrow — "The moderator's timeline shows I was wrong to say narrow "would not
  have caught the bug we are fixing". On 2026-03-06 the compiler started to emit `UNUSED_VARIABLE =
  "W0600"` while the catalog row still read `CloseableWithoutScope | W0600`. A constant↔catalog name
  check fails on that commit, and that commit is where the clash began." *Concern:* "the narrow check
  must compare name and code together for each row. A check that only tests that a code exists in the
  catalog would have passed on 2026-03-06, because W0600 did exist in the catalog, under the wrong
  name."
- **PLT:** full → narrow — "The moderator's timeline corrects my Phase C premise. … What narrow misses
  is the later residue: §5.5 prose kept W0600 from May to September after the catalog was fixed. That
  is a real gap but a smaller one, and aiml's and min's point that it needs a prose parser makes it a
  separate piece of work." Vote: "narrow, with the (name, code) pair compared and the spec-prose leg
  filed as its own follow-up ticket."
- **Web/Scripting:** narrow → full — "The moderator's timeline shows my Phase C claim was wrong. … From
  May to September, the compiler and the catalog both said UnusedVariable. Only §5.5 prose disagreed,
  and narrow checks never read sections/. That is the five-month stretch in which the bug actually got
  published." *Concern:* "if the matcher is not kept to those fixed shapes, it gives false positives,
  people start adding entries to an allowlist, and the spec leg slowly stops checking anything."
- **AI/ML:** narrow → full — "the dates show that sys and plt are right and that my Phase C reasoning
  was wrong. … Narrow passes the bug we are fixing." Its scope: "Diagnostic headers in code blocks
  (`warning[Name]`, `error[Name]`, plus a code if one is given): the pair must match the catalog. …
  `[lints]` keys in toml blocks: each must be a live code. … `@allow(...)` arguments: each must be a
  live name." Vote: "full, with the spec leg limited to structured forms." AI/ML later noted that
  these forms catch the llms-full `@allow(W0600)` example "only if the check also reads llms-full.md,
  because the scope in the brief is `sections/` only."
- **DevOps:** narrow → full — "Narrow would have caught Mar–May … It would have missed May–Sep, when
  the only disagreement was between §5.5 prose and the catalog, and that window is the one that
  produced this ticket." Its scope: "a code together with a backticked name on the same line, and a
  `warning[Name]`/`error[Name]` header. Each match must resolve to the same pair in the live or Retired
  table. There should be no allowlist." *Concern:* "the check's error message must name both the
  catalog row and the spec line it disagrees with."
- **Minimalism:** held narrow — "But (full) as worded, "the name the prose uses", would also have
  missed it. The old §5.5 heading said "W0600: `Closeable` value used outside `with...as`" and named no
  diagnostic. A matcher on code and name has nothing to compare there, unless it guesses from
  description text …" *Concern:* "the follow-up ticket must state the rule "a code in sections/ always
  appears with its name", not only "match whatever name is there"."

V3 stood 3-3 (narrow: systems, PLT, minimalism; full: web, AI/ML, DevOps). The user broke the tie for
"full, limited to structured forms". No reasoning was stated.

#### AI-first review

5/5 pass.

---

### Final Spec

```text
ERROR_CATALOG.md, Category Ranges:
| W060x | Linting |
| W061x | Resource scope lints |

ERROR_CATALOG.md, live table:
| UnusedVariable         | W0600 | Variable declared but never read | Linting   | §6   |
| ScopedValueWithoutWith | W0610 | A `Closeable` or `BlockHandler` value reaches anything
                                   other than a `with` item (flow-based) ... | Resources | §5.5 |

ERROR_CATALOG.md, Retired Codes:
| CloseableWithoutScope | — | The lint it named now covers every `Closeable` and
                              `BlockHandler` value, under a new name. Its old code,
                              W0600, belongs to `UnusedVariable` | ScopedValueWithoutWith (W0610) |

§5.5:
warning[ScopedValueWithoutWith]: `Closeable` value used without `with...as`
  ...
  = note: upgrade to error in blink.toml: [lints] W0610 = "error"
```

- **Q1.** `UnusedVariable` keeps W0600. `ScopedValueWithoutWith` is W0610. Category Ranges gains
  `W061x | Resource scope lints`.
- **Q1b.** Category Ranges also gains `W060x | Linting`, the word the catalog's Category column uses
  for W0600–W0604.
- **Q2.** `CloseableWithoutScope` gets a Retired Codes row with Code "—" and Replaced by
  `ScopedValueWithoutWith (W0610)`. The Retired preamble gains one clause: a Code cell of "—" means the
  catalog published the name, but no compiler ever emitted it under a code. No Conventions sentence
  is added.
- **§5.5** names the code in its heading, says W0600 is `UnusedVariable` and never refers to this
  lint, and shows `[lints] W0610 = "error"` in the note.
- **V5.** llms-full.md shows `@allow(UnusedVariable)`. CHANGELOG.md stays as written.
- **V4.** The "§6" spec-ref on W0600–W0602 goes to a separate ticket.

Implementation items not in this branch:

- **V1.** `blink explain W0600` gains one line saying W0600 never meant `ScopedValueWithoutWith`, and
  that lint is W0610. It stays one line.
- **V2.** The `ScopedValueWithoutWith` constant, its `blink explain` entry and its emit site land
  together, in the work of [the ScopedValueWithoutWith emitter ticket]. That ticket's done-criteria
  list all three. Until then the catalog row and §5.5 reserve W0610.
- **V3.** A `task ci` check, scoped as follows:
  - Each emitted constant's (name, code) pair matches its catalog row. A row that only has the code
    does not pass.
  - Each code maps to one name, and each name to one code.
  - No code is in both the live and the Retired tables.
  - Structured forms only, in sections/ and llms-full.md: `warning[Name]`/`error[Name]` headers, a
    code with a backticked name on the same line, `[lints]` keys, and `@allow` arguments. Each must
    agree with the live or Retired table. Free prose is not matched.
  - No allowlist. A false hit is fixed by rewording the spec line.
  - The error names the catalog row and the spec line that disagree.
  - Nothing parses ERROR_CATALOG.md today, so the check needs a new reader for it.

Out of scope here: whether `ScopedValueWithoutWith` keeps the `@trusted(audit: K)` suppression
channel ([the @trusted-channel ticket]); the W0603 clash ([the W0603 code-clash ticket]); what `@allow`
does with a retired name ([the @allow-with-retired-name ticket]).

Spec text: ERROR_CATALOG.md (*Category Ranges*, W0610 row, *Retired Codes*), §5.5 *Compiler
diagnostics*, llms-full.md.
