[< All Decisions](../DECISIONS.md)

# Unknown Diagnostic Names in @allow and [lints] — Design Rationale

`@allow(...)` on a function and the `[lints]` table in `blink.toml` both take diagnostic names. The
spec did not say what happens when a name is not live. Today the compiler accepts it and does
nothing. Three cases show the gap:

- A retired name, such as `@allow(CallSiteTypeArgs)`. The diagnostic can never fire again, so the
  `@allow` suppresses nothing.
- An unknown name, such as a typo (`@allow(UnrestoredMutaton)`) or a mistyped `[lints]` key. The
  `@allow` suppresses nothing. A mistyped key that sets `"error"` removes a gate the author
  thinks is in place.
- A code, such as `@allow(W0816)`. Conventions say `@allow` takes names, but sections/07 shows
  `@allow(W0816)` twice, and the compiler matches `@allow` by name only.

Only audit-gated names were refused (E0837). §9.1 gives the reason: a suppression that silently
fails to apply and one that silently succeeds are equally bad, because the author cannot tell
which happened.

The panel answered six questions:

- **Q0.** Is there one general diagnostic for an `@allow` argument or a `[lints]` key that is not
  a live name, with `@allow` taking names only?
- **Q1.** What is its severity?
- **Q2.** What does the `help:` line say for a retired name?
- **Q3.** What is its name?
- **Q4.** What do `blink explain` and its exit code do for a retired or unknown string?
- **Q5.** What does the spec say about typo matching (the did-you-mean)? Q5 split in Phase D into
  Q5a (a distance bound in the spec), Q5b (a tie between two live names) and Q5c (which
  characters the match ignores).

The question of whether `[lints]` keys may be names or codes was not on the panel. A separate
spec ticket holds it.

**A note on quotation.** Panelist text below is verbatim. The single exception is `br` ticket
identifiers: `br` is local-only, so per the repo rule that keeps local IDs out of spec, decisions,
and source, each is replaced by a bracketed description of the ticket. No other substitution was
made, and no panelist text was reworded or shortened without an ellipsis.

---

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in
independent-proposal, debate and vote rounds. Phase A produced six proposals. Phase B ran one
round, after which all six marked "Stable, ready to vote". Phase C was a silent vote. Q0 to Q4
passed 6-0. Q5 tied 3-3, so Phase D ran one debate round on Q5. A final revote split Q5 into Q5a,
Q5b and Q5c. The user signed off on the result.

#### Phase A — Independent proposals

- **Systems:** "**Rule.** Each `@allow` argument and each `[lints]` key must name a diagnostic that
  is live in this compiler's catalog. If it does not, the compiler reports one new error. Working
  name: **UnknownSuppressionKey**, E08xx (the moderator assigns the number). The same code covers
  three cases, and only the `help:` line differs". On severity: "**Why an error, not a warning
  (systems view).** The dangerous case is the one nobody notices. A typo in `[lints]` such as
  `W0551 = "error"` with a wrong key quietly removes a gate the author believes is in place. A
  warning about that scrolls past in CI." On forwarding a retired name: "**Not auto-forwarded.**
  Retiring a diagnostic is not renaming it. … Blink must not do that: E0307 split into three
  diagnostics with different meanings. Forwarding `@allow(CallSiteTypeArgs)` to all three would
  quietly suppress more than the author wrote." On codes: "**P2: `@allow` takes names only** …
  Codes are numbers for humans to look up. Names are the stable API (Conventions). Allowing two
  spellings for one key doubles the surface the V3 catalog check must compare." On explain: "A
  retired name or code: print the retired text and the replacements, exit 0." And: "An unknown
  string: print "no diagnostic is named X", with the closest-match help, and exit non-zero." Its
  fallback: "If the panel wants rust's behavior, the fallback is: retired → warning, unknown →
  error. I would still vote for error on both."
- **Web/Scripting:** "**Rule.** When `@allow(X)` or a `[lints]` key names something that is not a
  live diagnostic name, emit a new warning `UnknownSuppression` (next free W code in the lint
  block)." On severity: "Severity is warning, not error. A user can raise it with
  `UnknownSuppression = "error"` in `[lints]`, or turn it off for a codebase that builds under
  several compiler versions." On help: "X is a retired name (Retired Codes table): help says it is
  retired and lists the "Replaced by" names with codes." and "X is within edit distance 2 of a
  live name: help says `did you mean \`Y\``." Reason for a warning: "Retirement happens for good
  reasons; E0307 went away because §3.4 made the code legal. A dead suppression changes no program
  behaviour; it is clutter. Breaking a dependency's build because the compiler dropped a check is
  the npm upgrade pain people hate." On silence: "Today `@allow(W0816)` in sections/07 silently
  does nothing, and nobody noticed, the spec authors included. That is the proof that silent
  acceptance fails." On codes: "`@allow(W0816)` is not a valid suppression, because names are the
  stable API."
- **PLT:** "**Principle.** An `@allow` argument is a *name*; it must denote a live catalog entry
  reachable by that channel. A non-denoting argument is a well-formedness error, exactly like an
  unbound identifier. A suppression that suppresses nothing is a false claim in the source." Rule:
  "an `@allow` argument that is not the name of a live catalog entry is an **error**,
  `UnknownDiagnosticName` … One diagnostic, three help shapes". On severity: "**Severity error,
  not warning.** A warning about a suppression is itself suppressible / `[lints]="off"`-able — a
  regress; the guarantee becomes "unless configured"." On retired help: "retired name → help says
  retired, lists the "Replaced by" cell; fix = delete the argument (NOT insert the replacement —
  §3.1 rule 1: never prescribe a repair that may not exist)." Its variation: "If a replacement is
  audit-gated, the retired-name help must not suggest `@allow(<replacement>)` (that only yields
  E0837); it points at `@trusted(audit: …)`." On codes: "A live code maps to exactly one live
  name (codes never reused), so the help can carry a machine-applicable rewrite with no
  ambiguity". On typos: "unknown name → nearest live name by edit distance, else no help."
- **DevOps:** "**Rule …:** A name in `@allow(...)`, or a key under `[lints]`, that names no live
  diagnostic is a **warning** `UnknownDiagnosticName`." Reason: "**Why a warning, not an error:**
  cross-version builds. Library v1 writes `@allow(SomeNewLint)`; it must still build on an older
  compiler, and survive the day we retire a name. rustc learned this: `unknown_lints` and
  `renamed_and_removed_lints` are warn-by-default. Escalation exists: `[lints]
  UnknownDiagnosticName = "error"` for CI. Audit-gated names keep **E0837** (error)". Help rule:
  "offer a machine-applicable rename only when the Replaced-by cell is exactly one diagnostic that
  covers the old one's scope; otherwise "remove". Never tell the user to suppress the successors
  (§3.1 — E0303/E0313/E0314 are errors with their own contract, not the same thing renamed)." On
  explain: "Exit 0 (it is a known entry). Unknown: `error: no diagnostic named \`UnusedVarable\`;
  did you mean \`UnusedVariable\`?`, exit 1." Tradeoff: "The meta-lint is itself suppressible —
  intended, so multi-version libraries can set it `"off"` once in `[lints]`."
- **AI/ML:** "**P1. One error for every key the catalog cannot resolve** (primary) … An `@allow`
  argument or a `[lints]` key that is not a live catalog name is an error. The new entry is
  `UnknownDiagnosticName` (next free E08xx; the moderator assigns it)." On no suppression: "**No
  `@allow` or `[lints]` can silence this error.** A silenced error here would be the silent
  failure that §9.1 forbids. This matches E0837." On severity: "Agents often skip warnings in a
  long build log, but they cannot skip a failing build." On typos: "Match on case and underscores
  first (`unused_variable` → `UnusedVariable`), then on edit distance to the nearest catalog
  name." On codes: "With one accepted spelling, a model has one form to learn, and the training
  corpus agrees with itself." On explain: "Have `blink explain <retired name>` print the same
  replacement list that P1 prints, from the same Retired Codes row, so the two outputs cannot
  disagree." Its fallback: "the smallest fallback is: retired names give a warning, unknown names
  give an error. Even then, keep one code and one name."
- **Minimalism:** "**Position:** one general diagnostic, no "retired" diagnostic, no "renamed"
  warning, no new severity tier. The retired case is a help line on the general "unknown name"
  error, the exact pattern the panel chose 6-0 twice". Rule: "each argument of `@allow(...)` must
  be the name of a diagnostic this compiler can emit. Anything else — misspelling, retired name, a
  code — is error `UnknownDiagnosticName` (E0xxx, next free code in the annotation range). It is
  reported on the annotation and no `@allow`/`[lints]` entry suppresses it." On severity: "**Why
  error, not warning:** the fix is always "delete or fix one word" — cheap and side-effect free. A
  warning invites a rule for `@allow(UnknownDiagnosticName)`, the recursion rustc lives with". On
  explain: "**P4 — `blink explain`: no change.** The Retired Codes preamble already decides it."
  On what it did not propose: "no "renamed" auto-mapping (names are frozen and never renamed, so
  the case does not exist); no "unused @allow" lint (YAGNI — a valid name that did nothing this
  time is not an error)." Lesson: "tools that warn grew meta-lints; tools that error stayed small.
  Choose the error."

All six agreed on a core: one general diagnostic for any `@allow` argument or `[lints]` key that
is not a live name, no code that serves only retired names, `@allow` takes names only, the stale
"(future — not yet implemented)" note comes out of Conventions, and audit-gated names keep E0837.

**Moderator facts.** The moderator checked these in the repo and gave them to the panel:

- W0816 has no name anywhere: no ERROR_CATALOG.md row, no constant or explain text in src/, no emit site in src/. An earlier draft name `BufNonBridgeElement` does not exist in the repo.
- `UnknownDerive` E1112 exists in src/diagnostics.bl (constant, explain text "reported rather than ignored") and src/typecheck.bl, but ERROR_CATALOG.md has no E1112 row.
- §9.1.3.2 G1 says the bridge alphabet `BridgeAlpha` is a function of the language version alone. It does not say anything about the diagnostic catalog.
- ERROR_CATALOG.md row for W0610 ScopedValueWithoutWith says "Suppress with `@trusted(audit: K)`"; W0610 is not on the §9.1 audit-gated list (that list is UnauditedFfi, RawBypassesParam).
- `CloseableWithoutScope` (Retired, Code "—") was never emitted by any compiler.

#### Phase B — Debate highlights

Round 1 grouped the proposals into three severity options (error that nothing suppresses, a split
by case, a warning), three retired-name help forms (remove, rename when there is one successor,
"name one of those"), three names, and two sets of explain and typo rules. Four of the six
proposals already chose an unsuppressible error. The two that chose a warning moved.

**Web moved from a warning to an unsuppressible error:** "**Severity: I move to SEV-E** (details
in (2)). The meta-lint must not be suppressible, as in E0837." Its reasons: "Min and PLT: a
suppressible meta-lint repeats rustc's recursion, where `allow(unknown_lints)` hides the bug." and
"PLT: the catalog is closed and tied to the language version. My ESLint pain came from an open
plugin ecosystem, which Blink lacks." and "Min: both coded retired entries were errors, so those
`@allow`s already did nothing. The break shows a silent no-op; it breaks no working code."

**DevOps moved the same way:** "**Severity: I move from SEV-W to SEV-E, and reject SEV-split.**"
Its reason: "Min shows that the warning undoes itself. Once `UnknownDiagnosticName = "off"` exists,
the guarantee becomes "unless configured". rustc needed two meta-lints for this reason, and
`#![allow(unknown_lints)]` is common boilerplate in Rust." And: "Sys gives the CI case. A typo in
a `[lints]` key set to `"error"` quietly removes a gate, and a warning about that scrolls past in
CI logs. That is my own domain's failure mode, and it outweighs mine."

**DevOps withdrew the one-for-one rename.** "Plt found the defect in my proposal. My one example
was `CloseableWithoutScope → ScopedValueWithoutWith`, and the catalog says W0610 is suppressed
with `@trusted(audit: K)`. So my "machine-applicable rename" gives
`@allow(ScopedValueWithoutWith)`, a suppression that either fails or gets refused. That breaks
§3.1 rule 1. The fix is always removal." Sys named a second defect: "No compiler ever emitted
`CloseableWithoutScope`, so `@allow(CloseableWithoutScope)` never suppressed anything. Rewriting
it to `@allow(ScopedValueWithoutWith)` would *add* a suppression the author never had, and the
author would not see it happen. That is the "silently succeeds" case. … Remove changes no
behaviour, because the key suppressed nothing. Rename does change behaviour." PLT added that the
rename "*widens* scope, because W0610 also covers BlockHandler".

**Web dropped name-or-delete:** "**Help text: I withdraw "name one of those".** It told the author
to suppress TypeArgArity and the other replacements, which are errors with their own contract.
That breaks §3.1 rule 1, as sys, plt and devops said."

**Sys dropped `UnknownSuppressionKey`:** "**Name:** I drop `UnknownSuppressionKey` and take
`UnknownDiagnosticName`. Four panelists chose it, and it reads correctly in both channels." Web
also withdrew `UnknownSuppression`. DevOps gave the reason: "`[lints] X = "error"`, which raises
severity and does not suppress anything. One name must cover both channels and both directions."

**Sys also dropped the numeric distance from the spec:** "**Typo matching:** I drop "edit distance
≤ 2". The spec should say only "the nearest live name, if one is close". The matching algorithm is
an implementation detail, and aiml's case-and-underscore step first (`unused_variable` →
`UnusedVariable`) is a good one."

**PLT conceded the G1 point.** "**Concede the G1 point.** The moderator is right: §9.1.3.2 G1
binds BridgeAlpha, not the catalog. My forward-compatibility argument therefore rests on the point
above (the spec has no multi-version concept), not on G1." PLT also withdrew its audit-gated
variation: "It is moot under H-remove, because we never suggest a successor." Its fallback order
was "SEV-E, then SEV-split, then SEV-W last."

**Explain details merged.** Sys, DevOps, Web and PLT all took one rule. In Web's words: "A
retired name or code prints the retired text and replacements and exits 0. An unknown string
prints "no diagnostic named X" plus a did-you-mean and exits non-zero. The retired text and the
compile-time note come from the same Retired Codes row, so they cannot drift." Minimalism changed
from "no change": "I take sys/devops's split. … It is one sentence and adds no new surface, so my
"no change" was too terse."

**AI/ML withdrew its severity split:** "I withdraw my SEV-split fallback. It adds a second
decision point ("is it retired or unknown?") for one severity bit, and the arguments above apply
to both cases." On suppressing the meta-diagnostic: "Agents do exactly that when told to "make the
warnings go away", and after it every later typo is silent for the whole project again. That is
today's bug, restored by one line."

#### Phase C — Final vote

##### Q0: shared core (**6-0 YES**)

Option: one general diagnostic for an `@allow` argument or `[lints]` key that is not a live
diagnostic name (typo, retired name, code-in-`@allow`); no retired-only code; `@allow` takes names
only; `[lints]` key form stays with a separate spec ticket; remove the stale "(future — not yet
implemented)" line; audit-gated names keep E0837.

- **Systems:** YES — "Each suppression key is one lookup in a fixed table at compile time. It costs
  nothing at runtime and needs no new pass. In exchange, no suppression can fail without the author
  seeing it. One code with help lines that vary by case follows the 6-0 precedent and adds the
  smallest possible surface." *Concern:* "Until W0816 has a catalog name, sections/07 still shows
  `@allow(W0816)`, and the spec will contradict itself until that chore lands."
- **Web/Scripting:** YES — "One diagnostic and one spelling (names) means a JS or Python dev learns
  one rule: "the argument must be a real diagnostic name". Today `@allow(W0816)` silently does
  nothing, and the spec itself shows it. The core closes the silent no-op without adding a new
  concept." *Concern:* "the W0816 example in sections/07 stays wrong until W0816 gets a catalog
  name, so the spec breaks its own rule until that chore lands."
- **PLT:** YES — "every argument to `@allow` and every `[lints]` key must name a live catalog entry,
  and an argument that names nothing is reported, the same as an unbound identifier. One general
  diagnostic with a help line chosen by case follows the 6-0 precedent and the E1112 pattern. With
  one spelling for each argument, every tool and grep has one form to handle." *Concern:* "none of
  this can ship until the W0816 catalog chore is done; otherwise sections/07 will show a spelling
  the rule rejects."
- **DevOps:** YES — "One diagnostic over both channels gives the LSP and `blink fix` one code to
  key quick fixes on. Names-only in `@allow` gives completion one list to offer and the formatter
  one form. E0837 stays as the specific refusal for a known name in the wrong channel."
  *Concern:* "The W0816 catalog chore must land first, or sections/07 shows code that this rule
  rejects with a help line that cannot name a target."
- **AI/ML:** YES — "Today, a model that writes a wrong key gets no signal, and the wrong form goes
  back into the corpus. One general diagnostic with names only gives a model one form to learn and
  one place to look. No code exists only for retired names, which keeps the catalog small enough to
  fit in a prompt." *Concern:* "The two `@allow(W0816)` lines in sections/07 teach the rejected form
  until W0816 gets a catalog name. Until then the spec gives training data that disagrees with the
  rule."
- **Minimalism:** YES — "The core adds exactly one diagnostic and one catalog row. It replaces the
  silent no-op with the rule §9.1 already states, and it adds no code that serves one retired
  spelling. Names-only `@allow` keeps one spelling for each key, which is the smallest surface."
  *Concern:* "The two `@allow(W0816)` lines in sections/07 cannot be fixed until W0816 has a catalog
  name, so the spec contradicts the new rule until that chore lands."

##### Q1: severity (**6-0 SEV-E**)

Options: SEV-E, an error that no `@allow` or `[lints]` entry suppresses. SEV-split, one code with a
warning for a retired name and an error for an unknown name. SEV-W, a warning configurable through
`[lints]`.

- **Systems:** SEV-E — "The silent cases (a mistyped `[lints]` key set to "error", and every
  retired name) are exactly the ones a warning misses, because nothing else fires to show them. If
  config can switch a check off, the check is only as safe as that config. Blink has one closed
  catalog per language version, so rustc's reason for warning across toolchains is weak here. The
  fix is always one line, and a tool can apply it." *Concern:* "A dependency that carries a stale
  `@allow` stops building on a compiler upgrade. If retirements become frequent, the panel may have
  to add a dependency-cap channel like rustc's `--cap-lints`."
- **Web/Scripting:** SEV-E — "The fix is always to delete or correct one word, and `blink fix` can
  do it, so an error costs a dev seconds. A suppressible meta-lint repeats rustc's
  `allow(unknown_lints)` flaw. Blink has one closed catalog tied to the language version, unlike the
  plugin ecosystem that makes ESLint's error painful. One severity is simpler to explain than a
  split." *Concern:* "a dependency with a stale `@allow` stops building after a compiler upgrade,
  and the user cannot edit it; we should check that `blink fix` and the error message make that
  quick to clear."
- **PLT:** SEV-E — "a meta-diagnostic that users can suppress can hide its own error
  (`@allow(UnknownDiagnosticName, Typo)`), and SEV-E with no suppression closes that loop, as E0837
  does. A misspelled `[lints]` "error" key silently removes a gate, and a warning does not restore
  it. The multi-version use case has no spec concept behind it today." *Concern:* "a compiler
  upgrade that retires a name breaks the build of every dependency that names it, and Blink has no
  `--cap-lints` style escape for dependencies."
- **DevOps:** SEV-E — "A suppressible meta-diagnostic undoes itself: once someone writes `= "off"`,
  the CI gate quietly stops working, which is the failure this ticket exists to remove. Both
  retired codes were errors, so the break only exposes `@allow` text that already does nothing. The
  fix is one machine-applicable edit." *Concern:* "An implementation that aborts on the first bad
  key, or before typecheck reports, would turn an upgrade into many build cycles. The implementation
  ticket must report every bad key in the same pass as all other diagnostics."
- **AI/ML:** SEV-E — "Agents skip warnings, but they cannot skip a failed build, so only an error
  closes the self-correction loop every time. If the diagnostic could be suppressed, one `[lints]`
  line that an agent adds to quiet a log would make every later typo silent again. Making it
  unsuppressible removes that path, and the fix is always to delete or correct one word."
  *Concern:* "A dependency with a stale `@allow` stops building after a compiler upgrade, and the
  user cannot edit that dependency. A later cap on dependency lints must deal with this case."
- **Minimalism:** SEV-E — "Blink has one closed catalog per language version, so the rustc case for
  compatibility across compiler versions does not apply. If the diagnostic can be switched off,
  silence returns in exactly the codebases that switch it off. SEV-split adds a new concept,
  severity per help variant, and `[lints]` would then need a rule for it." *Concern:* "A dependency
  that carries a stale `@allow` stops building after an upgrade. The help line must make the
  one-line delete obvious, and ideally machine-applicable."

##### Q2: help line for a retired name (**6-0 H-remove**)

Options: H-remove, the help says remove the argument or key, a note lists the Replaced-by cell, and
the help never suggests suppressing a successor. H-rename-one, a machine-applicable rename when the
Replaced-by cell names exactly one diagnostic that covers the old scope. H-name-or-delete, the help
lists the replacements and says "name one of those, or delete this entry".

- **Systems:** H-remove — "Removing the key changes no behaviour, because the key suppressed
  nothing. A rename or a "name one of those" help can add a suppression the author never had, or
  tell them to suppress errors. CloseableWithoutScope was never emitted, so a rename for it would
  create a new suppression, not keep an old one." *Concern:* "Authors may still read the
  Replaced-by note as an invitation to suppress the successors, so the note's wording must state
  facts and not suggest an action."
- **Web/Scripting:** H-remove — "Remove is always correct and is machine-applicable. The note still
  tells the dev where the rule went. Suggesting a successor in `@allow` either suppresses errors
  with their own contract or picks the wrong channel (W0610 goes through `@trusted`)."
  *Concern:* "devs may read the note as a hint to add `@allow(<replacement>)`, so the note's
  wording should not show the name in an `@allow` form."
- **PLT:** H-remove — "retirement is not renaming. The one row with a single replacement
  (CloseableWithoutScope → W0610) widens scope and was never emitted, so a machine-applicable
  rename would turn a no-op into a live suppression, and a fix must not change what a program
  means. Suggesting `@allow` of the successors would also suggest suppressing errors, which is
  still open (S6), and that conflicts with §3.1 rule 1." *Concern:* "authors may read the
  Replaced-by note as an invitation to suppress the successors by hand. The note's wording must
  state facts and not suggest an action."
- **DevOps:** H-remove — "Removal is the only repair that is always correct (§3.1 rule 1). My own
  rename example would have produced `@allow(ScopedValueWithoutWith)`, a channel that W0610 does
  not use. The note that lists the Replaced-by cell still gives the reader the forward pointer."
  *Concern:* "If a note names a successor, it must name that successor's own channel
  (`@trusted(audit: …)` for W0610), or the note itself becomes a wrong repair."
- **AI/ML:** H-remove — "A help line that says `@allow(<successor>)` teaches models that
  error-severity diagnostics can be suppressed, and this repo is training data. A machine rename
  gives the wrong channel for the only single-successor row: W0610 is suppressed with
  `@trusted(audit: K)`. "Remove it" is always correct, always changes nothing about what the
  program does, and can be applied mechanically." *Concern:* "An author who wanted to keep
  suppressing the successor's cases must find the successor's own channel from the note. The note
  must name the replacements clearly enough for that."
- **Minimalism:** H-remove — "Deleting the argument cannot change what the program does, so it is
  the only repair that is always correct. Rename and "name one of those" both need new catalog
  facts or point to suppressing errors. That breaks §3.1 rule 1, and it hits the out-of-scope hole
  where `@allow` reaches errors." *Concern:* "The note that lists replacements may still read as
  an invitation to suppress them. Its wording must say "for information", not imply a repair."

##### Q3: name (**6-0 UnknownDiagnosticName**)

Options: `UnknownDiagnosticName`, `UnknownSuppression`, `UnknownSuppressionKey`.

- **Systems:** UnknownDiagnosticName — "It reads correctly in `@allow`, in `[lints]` and in `blink
  explain`. It describes what went wrong (the name does not resolve), not which channel the name
  was in." *Concern:* ""Unknown" is not quite true for a retired name, so the message text must say
  "retired" for that case."
- **Web/Scripting:** UnknownDiagnosticName — "It says what is wrong in words any dev reads at once.
  It also fits the `blink explain` "no diagnostic named X" case, so the same words appear in both
  places." *Concern:* "none of weight; for a code in `@allow` the code is a real diagnostic, so the
  message must say "takes a name, not a code" instead of claiming it is unknown."
- **PLT:** UnknownDiagnosticName — "what fails to resolve is the name, and the same error covers
  `[lints] X = "error"`, which is an escalation, not a suppression. The name describes the failure,
  not the channel." *Concern:* "names are frozen once published, so if a later ticket adds the "not
  suppressible: error-severity" case under this code, the name must still fit. It does, because the
  name is "unknown" only in the sense that it is not a valid name for this channel. The catalog row
  text must say this."
- **DevOps:** UnknownDiagnosticName — "The same key in `[lints]` can raise severity (`= "error"`),
  so "Suppression" in the name is false for half the uses. The name describes the actual fault, a
  string that names no live diagnostic, in both channels." *Concern:* "None material; it is a
  frozen name once published, so check the spelling before the catalog row lands."
- **AI/ML:** UnknownDiagnosticName — "`[lints]` keys also raise severity, so "Suppression" in the
  name is wrong for half the channel. This name says exactly what failed, and it matches `blink
  explain`'s "no diagnostic named X", so a model learns one phrase for both outputs."
  *Concern:* "None of substance."
- **Minimalism:** UnknownDiagnosticName — "It describes the fault (the string names no diagnostic),
  not the channel. That keeps it accurate for `@allow`, `[lints]` and `blink explain`."
  *Concern:* "None of substance."

##### Q4: `blink explain` (**6-0 X-cli**)

Options: X-cli, a retired name or code prints the retired text and replacements from the same
Retired Codes row the error help reads and exits 0, and an unknown string prints "no diagnostic
named X" plus a did-you-mean if one is close and exits non-zero. X-none, no spec change beyond the
existing Retired preamble.

- **Systems:** X-cli — "The retired output and the error help come from one Retired Codes row, so
  they cannot disagree. A non-zero exit for an unknown string lets scripts and agents detect the
  miss." *Concern:* "Exit 0 for a retired name can make a script treat it as live, so the output
  must put "retired" on its first line."
- **Web/Scripting:** X-cli — "Scripts, the LSP and agents need an exit code to tell "retired" from
  "never existed". One data source (the Retired Codes row) for both the error help and explain
  means the two cannot drift." *Concern:* "an exit of 0 for a retired name could let a script treat
  it as live; the output must say "retired" on the first line."
- **PLT:** X-cli — "one source (the Retired Codes row) for both the help line and the explain text
  makes it impossible for them to disagree. Exit codes separate a known entry from an unknown one,
  so scripts and agents can tell the two cases apart." *Concern:* "the exit-0 behaviour for retired
  entries must be stated once, so that tools do not treat "retired" as a lookup failure."
- **DevOps:** X-cli — "Exit codes are the CLI contract that scripts and editor integrations test
  on. Reading from the same Retired Codes row as the error help means the two outputs cannot drift.
  Exit 0 for a retired entry is correct because the lookup found a known entry." *Concern:*
  "Explain text for retired rows must come from the catalog data, not a hand-written copy in
  src/diagnostics.bl, or the outputs will drift anyway."
- **AI/ML:** X-cli — "The help line and `blink explain` both read the same Retired Codes row, so
  they cannot disagree. An agent that runs `blink explain` to recover sees the same replacements as
  in the error. Defined exit codes let tools and agents tell a known (retired) entry from an unknown
  string without parsing text." *Concern:* "Exit 0 for a retired name could make a script think the
  name is still usable. The text must say "retired" on its first line."
- **Minimalism:** X-cli — "Both outputs read one source, the Retired Codes row, so they cannot
  drift, and a CLI exit code costs nothing new. I withdrew X-none because it was too terse to be
  testable." *Concern:* "The CLI behavior may get written into ERROR_CATALOG.md Conventions instead
  of the CLI section, and so spread over two places."

##### Q5: what the spec says about typo matching (**3-3, went to Phase D**)

Options: T-rule, the spec says only that the help names the nearest live name after normalizing
case and `_`, if one is close, and otherwise gives no help line, with the distance bound left to
the implementation. T-bound, the spec also fixes the bound: case and `_` normalization, then edit
distance ≤ 2 against live names only, and at most one suggestion.

T-rule: Systems, Web/Scripting, Minimalism. T-bound: PLT, DevOps, AI/ML.

- **Systems:** T-rule — "The distance bound is a tuning detail of the implementation. Putting it in
  the spec freezes a heuristic that no user relies on for correctness. The spec only has to promise
  that a suggestion, when given, is a live name." *Concern:* "Two implementations (compiler and LSP)
  could suggest different names. A shared catalog helper in src/ avoids that, and it does not need
  spec text."
- **Web/Scripting:** T-rule — "The behavior a dev sees is set by "normalize case and `_`, suggest
  the nearest live name if close, else nothing". Normalizing is the part that matters for Python,
  Rust and Go habits (`unused_variable`). The exact distance is tuning, and pinning it in the spec
  stops later changes without a panel vote for no user gain." *Concern:* "two tools (compiler vs
  LSP) could pick different bounds and suggest different names; both should share one
  implementation."
- **Minimalism:** T-rule — "The spec should state behavior, not the algorithm. A fixed edit-distance
  bound is an implementation detail that the spec would then have to freeze. Case/`_` normalization
  is user-visible enough to state, and the bound is not." *Concern:* "Without a bound, two
  implementations may differ on whether a help line appears. That is acceptable while Blink ships
  one compiler."
- **PLT:** T-bound (changed from T-rule in round 1) — ""if one is close" in normative text is
  unspecified behaviour. Two conforming compilers could give different help for the same input, and
  no golden test could pin the result. A fixed bound (case/`_` normalization, edit distance ≤ 2
  against live names only, at most one suggestion) is checkable, deterministic, and suggests nothing
  for retired names. At most one suggestion also keeps §3.1 rule 3: the first help line is the
  repair." *Concern:* "if two live names are equally near, the tie-break must be deterministic (for
  example, catalog order); otherwise "at most one" still varies between implementations."
- **DevOps:** T-bound — "The compiler, the LSP and `blink explain` must give the same did-you-mean
  for the same input; a fixed rule makes that testable and lets the V3 check pin it. "Live names
  only" and "at most one suggestion" carry correctness weight (never suggest a retired name, never
  suggest something ambiguous), so they belong in the text, not left to an implementation."
  *Concern:* "If T-rule wins, the spec must still say "live names only", or a near-miss could
  suggest a retired name, which would trigger the same error again."
- **AI/ML:** T-bound — "The normalization step is what makes Rust-style keys (`unused_variables`)
  get any help at all. That is the most common wrong key from a model, so the spec must require it,
  not leave it to the implementation. Fixing the bound and "at most one suggestion" makes the help
  text the same across compiler builds. Golden tests and training examples then stay stable, and a
  model sees one correct suggestion, not a list it must pick from." *Concern:* "A fixed bound of 2
  could miss a long name with three typos, or suggest a wrong near-name between two similar names.
  Limiting matches to live names and to one suggestion keeps the second risk small."

#### Phase D — Round 2 (Q5)

Each Phase D reply was written alone, then the six replies were read together. The sides agreed
more than the 3-3 split showed. Everyone wanted normalization, live names only, one suggestion and
stable output. Only the number 2 was in dispute.

**Systems conceded the main point to PLT, then raised the tie.** "**I concede the main point to
plt.** "If one is close" lets two conforming tools print different help for the same input, and a
golden test cannot pin that. … A spec rule binds every implementation. On a predictability axis the
fixed bound wins". And: "**One gap remains in T-bound: ties.** Plt's tie-break, catalog order, is
deterministic but arbitrary. Between two equally near live names, it would print one confident
suggestion that may well be wrong. That conflicts with devops' "never suggest something ambiguous"
and with §3.1 rule 3 (the first help line must be the repair). The correct answer to a tie is no
suggestion." Its refinement:

> **T-bound-strict (full text):** The did-you-mean help is computed against live names only (never
> retired names, never codes). Both strings are first normalized: case-folded, with every `_`
> removed. If exactly one live name is at the smallest edit distance from the argument, and that
> distance is ≤ 2, the help names it. Otherwise, whether no name is within 2 or two or more tie,
> there is no did-you-mean line. There is at most one suggestion.

**Web proposed T-core.** "Most of what the T-bound side argues for does not need the number. Devops
wants live names only and at most one suggestion. Aiml wants normalization to be required. Plt
wants a fixed tie-break. I agree with all of these, and none of them is the "≤ 2"."

> **T-core (normative):** The help names at most one suggestion, chosen from live names only. A
> retired name, a code or an audit-gated name is never suggested.
> - If the argument matches a live name after case and `_` are ignored, the help MUST name that live name.
> - Otherwise the help MAY name the nearest live name by edit distance, if the compiler judges it close. If none is close, there is no help line.
> - If two live names tie, the first in catalog order wins.
> - The compiler, the LSP and `blink explain` give the same suggestion for the same input.
> - The distance threshold is set by the implementation and is not part of the spec.

**PLT conceded part of its position and named a T-core of its own.** "**I concede part of this to
sys, web and min.** The edit-distance number is a tuning value, and freezing it in the spec would
mean a panel vote for every change to it. My real objection was not that the number is missing. It
was that "if one is close" lets the *set of possible outputs* go unconstrained". Its text:

> The help for an unknown name names at most one suggestion. The candidates are live catalog names
> only. Matching ignores case and `_`. The compiler picks the match by a deterministic rule that
> the same compiler version applies in `@allow`, `[lints]`, the LSP and `blink explain`. If no live
> name is near enough, the help line is omitted. How near is "near enough" is implementation-defined.

**DevOps conceded the number and named T-invariants.** "I concede the number to the T-rule side. A
distance bound is tuning: it could rightly change to a length-scaled bound when longer names
arrive, and that should not need a panel vote. … What I will not concede is leaving the safety
properties to the implementation."

> When an `@allow` argument or `[lints]` key is not a live diagnostic name, the compiler compares
> it with live names after removing case and `_` differences. If one live name is close, the help
> names it. The help never names a retired name and never names more than one. For the same
> compiler version and input, the suggestion is the same, and ties resolve in a fixed order. How
> close counts as close is not specified.

**AI/ML proposed T-rule+.** "For models, the parts that matter are normalization (it is what lets
`unused_variables` get help at all), one suggestion (a model takes the first help line, so a list
invites a wrong pick) and stable output (golden tests and training examples stay the same)."

> When the argument or key is not a live name and not a retired name or code, the help line
> suggests at most one name. The candidate set is the live names only; retired names are never
> suggested. Comparison ignores case, `_` and `-`. The suggestion is a function of the argument and
> the language version only: the same input gives the same help line in the compiler, the LSP and
> `blink explain`. Ties break in catalog order. If no live name is close, there is no help line.
> The closeness threshold is an implementation detail.

**Minimalism also proposed a T-rule+.** "The tie goes away if we split the guarantees that carry
correctness from the one tuning number." On the number: ""≤ 2" is a tuning number, not a
guarantee. No user relies on it for correctness. Freezing it means a panel vote to change it from 2
to 3 for long names, which is exactly the language-surface growth minimalism exists to prevent."

> When an argument is not a live diagnostic name and is not a retired name or a code, the help
> names at most one suggestion. The suggestion is a live name, never a retired name. The compiler
> finds it by comparing case-folded names with `_` removed, so `unused_variables` matches
> `UnusedVariable`. When two live names are equally near, catalog order breaks the tie. When no live
> name is near enough, there is no help line. How near is "near enough" is an implementation
> choice, and the compiler, the LSP and `blink explain` share one implementation of it.

The moderator reduced the refinements to three sub-questions.

##### Q5a: distance bound in the spec? (**6-0 NO-BOUND**)

Options: NO-BOUND, the spec states normalization, live names only, at most one suggestion and the
same output per compiler version across compiler, LSP and `blink explain`, and the closeness
threshold is implementation-defined. BOUND-2, the same plus "edit distance ≤ 2 after
normalization" as normative.

- **Systems:** NO-BOUND — "I asked for the bound only to get deterministic output, and the shared
  refinement now requires it ("same output for each compiler version across compiler / LSP / `blink
  explain`"). That gives golden tests and tools what they need without freezing a tuning number.
  The properties that carry correctness weight (live names only, at most one suggestion) are
  normative under this option, and the number is not one of them." *Concern:* "The bound can still
  change between compiler versions without notice, so a threshold change must go in the release
  notes."
- **Web/Scripting:** NO-BOUND — "Five of six refinements already agree on this. The guarantees a
  dev or a tool relies on are normalization, live names only, at most one suggestion, and the same
  output per version in every tool. The number is tuning, and changing it should not need a panel
  vote." *Concern:* "help text in golden tests can change between compiler versions, so release
  notes must say when the threshold changes."
- **PLT:** NO-BOUND — "The guarantees that carry correctness are now all normative: live names
  only, at most one suggestion, required normalization, and the same output per compiler version
  across the compiler, the LSP and `blink explain`. Those make the output a function of the input
  and the version, which was my whole objection to "if one is close". The number adds no guarantee
  that a program or a tool depends on, so freezing it is surface without meaning." *Concern:* "The
  determinism clause must say "per compiler version" in the normative text, or
  "implementation-defined" turns back into "unspecified"."
- **DevOps:** NO-BOUND — "Every property a tool depends on is normative under NO-BOUND: live names
  only, at most one suggestion, and the same output per compiler version across the compiler, the
  LSP and `blink explain`. The threshold is tuning that we should be free to improve without a
  panel vote. Golden tests pin the output for each version, and that is all CI needs." *Concern:*
  "A threshold change shifts golden help text between releases, so the release notes must call it
  out."
- **AI/ML:** NO-BOUND — "Every property that model self-correction depends on is normative under
  NO-BOUND: normalization, live names only, at most one suggestion, and the same output from the
  compiler, the LSP and `blink explain` for one compiler version. The number 2 changes none of
  these, and it is the value most likely to need tuning once real typos are logged. Golden tests
  pin the output for each compiler version, which is all that training examples and agents need."
  *Concern:* "A threshold change between releases changes help text in golden tests and in older
  training examples, so the release notes must say so."
- **Minimalism:** NO-BOUND — "Five of six refinements already agree that the number is tuning, and
  no program's meaning depends on it. The invariants that carry correctness weight are normative
  under NO-BOUND: live names only, at most one suggestion, and the same output per compiler version
  in every tool. Freezing "≤ 2" would mean a panel vote to change a heuristic, which is surface
  with no user benefit." *Concern:* "If the threshold changes, golden help text changes between
  releases, so release notes must say so."

##### Q5b: two live names equally near (**6-0 TIE-NONE**)

Options: TIE-CATALOG, catalog order breaks the tie. TIE-FIXED, a fixed order the spec does not
name. TIE-NONE, no did-you-mean line on a tie.

Web, AI/ML and Minimalism changed from TIE-CATALOG after they read Systems.

- **Systems:** TIE-NONE — "Two names equally near is the one case where the compiler has no
  evidence for either. Picking by catalog order prints a confident repair that is wrong about half
  the time. That conflicts with §3.1 rule 3 (the first help line is the repair) and with devops'
  "never suggest something ambiguous". Catalog order also moves when rows are added, so a new
  diagnostic can silently change an old suggestion. No suggestion is deterministic, needs no
  ordering rule, and invents no repair." *Concern:* "If TIE-CATALOG wins, "catalog order" must be
  pinned to a stable key (for example code order, not row position), or edits to the catalog will
  change help text."
- **Web/Scripting:** TIE-NONE (switched from TIE-CATALOG after reading sys) — "We voted the fixes
  machine-applicable, so a suggestion is not only a hint: `blink fix` or an LSP quick fix may apply
  it. On a tie, catalog order picks one name at random from the dev's point of view, and an
  auto-applied fix could then suppress a diagnostic the dev never meant to touch. Omitting the help
  line on a tie is deterministic and never wrong. The dev still sees "no diagnostic named X" and
  can run `blink explain`." *Concern:* "a dev with a typo that sits between two names gets no hint,
  which is a small loss in an uncommon case."
- **PLT:** TIE-NONE — "Two equally near live names is an ambiguity, and the principled answer to an
  ambiguity is no answer, the same as ambiguous name resolution, which reports and does not pick.
  Catalog order is deterministic but means nothing: it gives one confident suggestion that may be
  wrong, and a mechanical fixer will apply it. That conflicts with §3.1 rules 1 and 3. TIE-NONE is
  still deterministic, so it meets my Phase C concern at no extra cost." *Concern:* "Adding a new
  catalog row can turn a single nearest match into a tie, so a help line may vanish between
  versions. That is acceptable under the per-version determinism clause."
- **DevOps:** TIE-NONE — "The LSP and `blink fix` will offer the did-you-mean as a
  machine-applicable quick fix. With catalog order, a tie becomes a confident one-click rename to a
  name that is wrong half the time, and that rename can silently suppress the wrong diagnostic.
  That is the "silently succeeds" failure §9.1 forbids. No help line on a tie is deterministic,
  checkable, and never prescribes a guessed repair (§3.1 rule 1). It is the honest form of my own
  "never suggest something ambiguous"." *Concern:* "Users get no help in the rare tie case. That is
  acceptable, because the error still names the bad key exactly and `blink explain` is one command
  away."
- **AI/ML:** TIE-NONE (changed from TIE-CATALOG; sys's argument) — "Models apply the first help
  line mechanically. On a tie, catalog order prints one confident suggestion that is wrong about
  half the time. Unlike every other wrong fix here, that one does not fail: `@allow(<wrong live
  name>)` is valid, so it silently suppresses a different diagnostic and leaves the intended one
  firing. That is the "silently succeeds" case §9.1 forbids. With no line on a tie, the model must
  look, for example with `blink explain`, and the fix it then makes is the correct one."
  *Concern:* "A tie at distance 0 after normalization would mean two live names that differ only in
  case or `_`, so the catalog must never publish such a pair. The V3 check should enforce that."
- **Minimalism:** TIE-NONE (changed from TIE-CATALOG) — "Sys is right. On a tie, catalog order
  prints one confident suggestion that is wrong as often as it is right. That works against §3.1
  rule 3, where the first help line is the repair. TIE-CATALOG also makes the row order of
  ERROR_CATALOG.md load-bearing for compiler output, which is a hidden coupling. TIE-NONE needs no
  ordering concept at all: it is the smallest rule, and it is fully deterministic." *Concern:* "A
  typo that sits exactly between two names gets no help. That is acceptable, because `blink
  explain` and LSP completion still list the live names."

##### Q5c: normalization (**5-1 NORM-DASH**)

Options: NORM-UNDERSCORE, the match ignores case and `_`. NORM-DASH, the match ignores case, `_`
and `-`.

- **Systems:** NORM-DASH — "Live names are PascalCase and contain neither `_` nor `-`, so removing
  `-` cannot create a false match. It costs one more character class in the same pass. It catches
  eslint- and clippy-style kebab keys (`unused-variable`), which are valid bare TOML keys under
  `[lints]` and a likely wrong form from both humans and models." *Concern:* "None in correctness
  terms. The only cost is one more clause of normative text."
- **Web/Scripting:** NORM-DASH — "The JS devs this panel seat speaks for write lint names in
  kebab-case from ESLint habit (`no-unused-vars`). TOML bare keys accept `-`, so `unused-variable =
  "off"` under `[lints]` is a real input. Ignoring `-` as well as `_` costs nothing and gives that
  dev the right name at once." *Concern:* "in `@allow(unused-variable)` the parser may reject the
  argument as an expression before this help can run, so the dash case helps mostly in `[lints]`."
- **PLT:** NORM-DASH — "Normalization defines which foreign naming conventions map to a Blink name.
  Kebab case (eslint `no-unused-vars`, clippy CLI flags, TOML-style keys) is as common a source of
  wrong keys as snake case, above all in `[lints]`, where TOML allows `-` in bare keys. No live
  name contains `-`, so removing it can never create a false match. It only widens which inputs get
  help." *Concern:* "In `@allow(...)` a `-` may not lex as part of a name, so that case fails in
  the parser before this rule runs. The added coverage is mainly for `[lints]` keys, which is where
  it matters most."
- **DevOps:** NORM-DASH — "`[lints]` keys are TOML, where `unused-variable` is a legal bare key,
  and that is the eslint and kebab-case habit many users and models bring. Ignoring `-` costs one
  character in the rule and gives that key a correct suggestion instead of none. In `@allow` a `-`
  cannot reach this diagnostic, because it is not an identifier there, so the change only helps."
  *Concern:* "If NORM-UNDERSCORE wins, kebab-case `[lints]` keys still get the error but often no
  did-you-mean. That is a small gap, but it is the most common wrong form from eslint users."
- **AI/ML:** NORM-DASH — "Kebab-case names are common in model memory from eslint
  (`no-unused-vars`) and clippy's command-line form (`-W unused-variables`). A Blink name can never
  contain `-`, so removing it cannot create a false match. It costs one character in the
  normalization set and does not depend on the threshold. Without it, `unused-variables` reaches
  `UnusedVariable` only if the implementation's bound happens to allow for the extra edits."
  *Concern:* "Little. If the panel prefers NORM-UNDERSCORE for a shorter rule, the loss is only
  kebab keys that fall outside the bound."
- **Minimalism (dissent):** NORM-UNDERSCORE — "A `-` cannot appear in an `@allow` argument, since
  it is not an identifier, so a dash rule could only help `[lints]` keys. For those, the
  implementation's edit-distance step already covers one or two dashes. Every normalization clause
  is spec text that must be tested forever, and `_` is the one with proven demand (Rust-style
  `unused_variables`)." *Concern:* "An eslint-style key such as `no-unused-vars` gets no help, but
  no normalization would rescue that spelling anyway."

---

### Final Spec

An `@allow` argument or a `[lints]` key that is not a live diagnostic name is the error
`UnknownDiagnosticName` (E0842). The rule lives in ERROR_CATALOG.md *Conventions*. Section 4.16.8
has the short form and one example.

```blink
@allow(UnrestoredMutaton)   // error[UnknownDiagnosticName]: help: did you mean `UnrestoredMutation`?
fn parse_fast() -> Node {
    parse_simple()
}

@allow(CallSiteTypeArgs)    // error[UnknownDiagnosticName]: CallSiteTypeArgs is retired
fn main() {                 //   help: remove `CallSiteTypeArgs`
}                           //   note: replaced by TypeArgArity (E0303), NoIndexOperator (E0313), TypeArgsWithoutCall (E0314)
```

Locked points:

- The new error is `UnknownDiagnosticName`, code E0842, in the Linting category.
- No `@allow` or `[lints]` entry suppresses it, and it cannot change its severity.
- `@allow` takes names only. A code in `@allow` is E0842, and the `help:` line names the live
  diagnostic that has that code.
- The compiler reports every bad argument and key, not only the first.
- An audit-gated name (`UnauditedFfi`, `RawBypassesParam`) keeps `AuditGatedSuppression` (E0837).
  It is not E0842.
- A retired name or code: the `help:` line says to remove the argument or key. A `note:` lists the
  *Replaced by* cell of its *Retired Codes* row, as information only. The help never proposes a
  replacement as an `@allow` argument.
- Did-you-mean is computed against live names only. It never suggests a retired name or a code.
- The match ignores case, `_` and `-`.
- The help names at most one name. If two or more live names are equally near, or no live name is
  near enough, there is no suggestion.
- The implementation sets the closeness threshold. For one compiler version, the same input gives
  the same suggestion in the compiler, the language server and `blink explain`.
- `blink explain <name-or-code>` prints a detailed explanation of a live diagnostic and exits 0.
  For a retired name or code, the first line says it is retired, the output shows the same
  *Replaced by* list as the E0842 note, and the exit status is 0. For any other string, it prints
  `no diagnostic named <string>`, a suggestion by the rule above if there is one, and exits with a
  non-zero status.
- No two live names are equal when case, `_` and `-` are ignored.
- The stale "(future — not yet implemented)" note is gone from the `blink explain` line in
  Conventions.

### Out of scope / follow-ups

- **`[lints]` key form.** Whether a `[lints]` key may be a name, a code or both stays with a
  separate spec ticket. E0842 applies to whatever key form is legal.
- **Error-severity diagnostics.** `@allow` and `[lints]` reach error-severity diagnostics today.
  The Conventions example `@allow(NonExhaustiveMatch)` silences an error, and §4.16.8 says
  "warning". A new spec ticket decides whether they may.
- **W0816 needs a catalog name.** W0816 has no row in ERROR_CATALOG.md. The two `@allow(W0816)`
  examples in sections/07 are not valid under this rule until W0816 has a name. This is a chore,
  and it comes before the implementation.
- **Missing E1112 row.** `UnknownDerive` (E1112) has a constant, explain text and an emit site, but
  no row in ERROR_CATALOG.md. This is a separate chore.
