[< All Decisions](../DECISIONS.md)

# Selective Import of an Undeclared Name — Design Rationale

A selective import, `import other.{nothere}`, checked clean when module `other` declared no `nothere`. The
*Import Errors* table (§10.5) had no row for it. This ruling adds one code, `UnknownImportName` (E1023), and fixes
when it fires, what it points at, what it suggests, and what it silences.

## Summary

| Q | Question | Result | Vote |
|---|---|---|---|
| Q1 | Which code a listed name that the module does not declare gets | A: a new code E1023; a name declared without `pub` stays E1003 | 6-0 |
| Q2 | Name of the new code | A: `UnknownImportName` | 6-0 |
| Q3 | The qualified miss `other.nothere()` | A: out of this decision; it keeps E0505, and its help uses the same candidates and the same nearest-name rule as E1023 | 6-0 |
| Q4 | Where the spec says that import checks run when the import is read | C: §10.5 *Imported Names* says it for every check on an import entry, and each import cause cell keeps a short clause | 6-0 in Phase D (4-2 in Phase C) |
| Q5 | `import other.{Hidden}` with a private `hidden` | A: E1023; `hidden` is not a candidate; a `note:` says that a private item `hidden` exists, with no fix, no edit, no code action, and never "make it `pub`" | 5-1 in Phase D, Minimalism dissent (4-2 in Phase C) |
| Q6 | Help when no candidate is near enough | A: follow E0547: the help lists the candidates; the terminal may shorten the list and count the rest; structured output lists every candidate | 5-1, Minimalism dissent |
| Q7 | What the machine-applicable fix changes | B: the listed name and every use that resolves to that import binding; with an alias, the listed name only; a suggestion only when the new name is already bound in the file or at any of those uses | 6-0 in Phase D (4-2 in Phase C) |

Agreed by all six seats, without a vote:

- The primary span is on the listed name, to the left of any `as`. The check runs when the import is read, used or not. `pub import` gets the same code.
- The entry binds a name that denotes no item. The entry gets no W0602. A use of the name gets no E0504, E0507 or E1006. The entry takes no part in E1005 or E1012.
- The candidates are the `pub` items of the module in both namespaces plus its `pub import` names, minus the names the list already holds. The nearest-name rule of the *Conventions* in ERROR_CATALOG.md applies, and the row names its candidates.
- With one suggestion, the fix is machine-applicable (Q7 sets its edit set).
- E1003's import form is checked when the import is read too. The compiler does not do this today (probe b below). That is a compiler bug, not a spec change.
- The table drift for E1014 is out of scope.

Follow-up, not part of this decision: moving the qualified miss `m.n` from E0505 to E1023 (Q3).

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in
independent-proposal, debate (one round), silent-vote rounds. The text below is quoted from each panelist's own text.
A quote is cut at a sentence end, and line breaks in the source files are joined. A cut inside a quote is marked
`[...]`. Three questions (Q4, Q5, Q7) came out 4-2 in Phase C and went to a focused round, Phase D.

#### Moderator facts and probes

The ticket, in its own words:

> The E1000-E1016 table in sections/07_trust_modules_metadata.md has no row for `import m.{nothere}` when module m declares no `nothere`. Today it checks clean (bug [...]). [...] Candidate rows: (a) widen E1003 Private item access to "not pub or not declared" (one code for "this module gives you no such name"; the help can say which); (b) reuse E0507 UnknownType / E0504-style unknown-name codes from typecheck (but these are not import codes and the name may be a fn or value, not a type); (c) a new E10xx "Selected name not declared" row next to E1006.

The moderator checked the compiler on a probe package (`other.bl` declares `pub fn x`, a private `fn hidden` and `pub type Pt`):

> - a `import other.{nothere}` (unused) → only `warning[UnusedImport]: module `other` is imported but not used`, then ok.
> - b `import other.{hidden}` (private fn, unused) → the same: UnusedImport warning, ok. No E1003.
> - c `import other` + `other.nothere()` → `error[UnresolvedMethod]: no member `nothere` on module `other``.
> - d `import std.io.{nothere}` → ok, no warning.
> - e `import other.{Nothere}` → UnusedImport warning, ok.
> - f `import other.{nothere}` + a call `nothere()` → `error[UndefinedFunction]: undefined function `nothere`` plus the UnusedImport warning.
> - g `import other.{x, nothre}` with `x` used → ok (the typo passes silently).
> - h `pub import other.{nothere}` → ok.

The moderator surfaced these facts before Phase B and Phase D:

> - Correction to the brief: E1014 is not unused. ERROR_CATALOG.md:237 gives E1014 to `UnknownDependencyField` (category Manifest, §8.9.8). E1017-E1022 are manifest codes. The first free E10xx is E1023. The *Import Errors* table (sections/07:2634-2652) lists none of the manifest codes.
> - ERROR_CATALOG.md:28 (*Conventions*, nearest-name rule): the comparison "ignores case, `_` and `-`". "If two or more candidates are equally near, or no candidate is near enough, there is no suggestion ... Each row that suggests a name says which names are its candidates."
> - Existing rows on the no-suggestion case: E0525 NoSuchField (ERROR_CATALOG.md:131) "with none, the help lists the declared fields"; E0547 NoSuchVariant (:151) "with none, the help lists the declared variants. The terminal text may shorten the list and count the rest; structured output lists every variant."
> - E1012 DuplicateSymbol (ERROR_CATALOG.md:236): "Replaces W0602 on that import entry".

> - devops's Q7 reasoning says a fix that leaves new errors is something "§8.6 forbids". §8.6 (sections/06_tooling.md:259-307) defines machine-applicable fixes as edits "the AI can apply verbatim" and says `blink fix` applies neither of two different edits whose spans overlap. It has no sentence about a fix that leaves other errors in the file.
> - A machine-applicable fix with more than one edit exists: sections/02_syntax.md:3083 binds `rhs` to a new name on the line before and writes the name; "The name is one that is not in scope at that line."
> - E0525 NoSuchField, for a punned pattern label (ERROR_CATALOG.md:131): "the fix writes `y: yy`: the binder and the arm body stay as they are, and no use is renamed."

#### Phase A — Independent proposals

Five seats proposed a new code, E1023. Minimalism proposed to widen E1003. No seat backed ticket option (b).

- **Systems** (`A/sys.md`):

> sys-1 (preferred): new code `ImportNameNotFound`, next free E10xx (E1023 today)

> Code number: E1014 is not free.

> 2. **Eager**: checked when the import is read, whether or not the file uses the name.

> 3. **Private name (b)**: stays E1003. The name exists, so the user needs a different fix (make it `pub`, or import from the public API). Two causes, two codes.

- **Web/Scripting** (`A/web.md`):

> web-1 (main): new code "Unknown import name", separate from E1003

> A JS/TS dev has seen this error a thousand times: TS2305 "Module './other' has no exported member 'nothre'. Did you mean 'x'?" It is the most common import error there is, and it is almost always a typo.

> A missing name means "fix your spelling". A private name means "this is not the API; find the public path or ask the owner to export it".

- **PLT** (`A/plt.md`):

> plt-1: new code E1023 `UnknownImportName`, checked at the entry, one judgment for entry and qualifier

> An entry `import m.{n}` is well formed only when `n ∈ dom(Sig(m))`.

> A code name is a claim; a false claim in a catalog that agents learn from is a bug.

- **DevOps/Tooling** (`A/devops.md`):

> devops-1: new code `ImportItemNotFound` (E1023, next free E10xx), checked at the import, with a nearest-name fix

> The LSP picks a code action from the code, so two mistakes with different fixes need two codes.

> Option (a), widening E1003, makes every `--json` reader parse the message to choose a fix.

- **AI/ML** (`A/aiml.md`):

> aiml-1 (recommended): new row E1023 `UnknownImportName`, checked eagerly

> An agent reads the code to pick a fix.

> the most common repair for E1003 — add `pub` to the declaration — is wrong for a typo and invites the agent to *create* a stub `pub fn nothre`.

- **Minimalism** (`A/min.md`):

> min-1: widen E1003 to "the module gives you no such name" (ticket option a). No new code.

> For the importer, `import other.{hidden}` and `import other.{nothere}` are one mistake with one fix: pick a name the module exports.

> Python raises one ImportError for a missing name. One code with a note is the smaller shape and loses no information.

#### Phase B — Debate, round 1

The moderator reduced the six texts to two options: Option 1, a new E10xx code for a listed name that the module does not declare, with a private name staying E1003; Option 2, widen E1003 to cover both. Six variations were flagged: V1 code name, V2 the qualified miss, V3 the private import, V4 what the entry's poison binding silences, V5 the help, V6 the E1014 table drift. Quotes from `B1/`:

- **Systems** moved on the code name and held Option 1: (`B1/sys.md`)

> **V1: change from Phase A.** I drop `ImportNameNotFound` and take `UnknownImportName`.

> Oppose plt-1's "private exact match after case folding is E1003". E1003 must name a name that exists. `import other.{Hidden}` where `hidden` is private gets E1023; at most a `note:` that a private item `hidden` exists.

- **Web/Scripting** moved on the message head and on the no-suggestion help: (`B1/web.md`)

> I drop "name" for "item": "module `other` has no item `nothre`".

> No suggestion: I concede to the E0525/E0547 pattern (list some, count the rest; `--json` lists all of them).

> `import other.{Hidden}` is not an import of `hidden`, so an E1003 that says "`Hidden` is private" is false.

- **PLT** retracted its case-folding rule: (`B1/plt.md`)

> I retract my case-folding rule: `Hidden` is not declared, so it is E1023 by the same judgment.

> I keep plt-1b as my preference: E0505 *UnresolvedMethod* is a false name for a module member miss. I accept it as a separate follow-up so that it does not block this vote.

- **DevOps/Tooling** moved on the code name, opposed case folding, and proposed the binding rename: (`B1/devops.md`)

> I drop `ImportItemNotFound` and take `UnknownImportName`.

> I oppose plt-1's case-fold rule. `import other.{Hidden}` names nothing, because names are case-sensitive.

> New point against min-1's "never machine-applicable": renaming only the entry leaves the uses (`nothre()`) broken. The uses resolve to the poison binding, so the fix knows them. The fix renames the entry and every use of that binding in the file. With an alias (`{nothre as n}`), it renames only the entry.

- **AI/ML** moved on the no-suggestion help: (`B1/aiml.md`)

> **Change from Phase A:** with no suggestion, I now accept devops-1: the help lists some `pub` names and counts the rest, `--json` lists all.

- **Minimalism** moved from Option 2 to Option 1: (`B1/min.md`)

> **Change from Phase A: I drop min-1 and back Option 1 (new E1023).**

> If one code covers both, an LSP quick-fix or an agent that keys on the code will offer "make it `pub`", and for a typo that means writing a stub `pub fn nothre`.

> One new row that stops a wrong fix is worth what it costs.

All six seats ended Phase B with `STATUS: ready to vote`. Minimalism's remaining position in Phase B: "No near match: no list. A module is not a closed set the way fields and variants are, so E0525/E0547 do not set the pattern here."

#### Phase C — Final vote

Silent ballot. Each seat gave a vote, reasoning and one concern for each question. Option letters are as on the ballot (`ballot.md`).

- **Q1: Which code a listed name that the module does not declare gets.** (6-0). Options: A: a new code E1023; a private name stays E1003. B: widen E1003 to cover both, renamed (`ItemNotVisible`).
  - **Systems:** A — One code for one cause. "Add `pub`" and "fix the spelling" are different fixes, and a tool that keys a quick-fix on the code must not have to parse the message to pick one. The cost of the check is the same either way (one lookup in the export table), so the split costs nothing.
    Concern: a later implementation could run E1003 and E1023 from two separate passes and report both on one entry; the two checks must share one lookup.
  - **Web/Scripting:** A — Every toolchain a JS/TS/Python/Rust dev knows keeps "no such export" apart from "exists but not exported". The two fixes differ: a typo needs a rename, a private name needs a different import path or a change by the owner. Two codes let the help and the LSP action be right without reading the note.
    Concern: People may still confuse E1023 with E1003 when a name is both misspelled and private, so the note in Q5 must actually ship.
  - **PLT:** A — The two errors are two judgments: the name is declared but not `pub`, or the module declares no such name. Each has its own fix. A code is a claim about which judgment failed, so one judgment per code is the clean split. Rust (E0432 and E0603) and TypeScript (TS2305 and TS2459) split it the same way.
    Concern: An implementation may test "is it `pub`" before "is it declared" and report a private name as E1023. The rule must test "declared" first.
  - **DevOps/Tooling:** A — Editors and `--json` readers choose a quick-fix by the code. A typo needs a rename, and a private name needs "make it `pub`" or another import path. One code would make every tool parse message text to choose between them. Rust, TypeScript and the rest of this catalog keep these apart.
    Concern: an implementation might give E1023 for a private name if it checks `pub` names before it checks declared names. The tests must cover probe b and probe a side by side.
  - **AI/ML:** A — An agent picks its fix from the code. "Respell" and "make it `pub`" are different fixes, and one code for both pushes a model to add a stub `pub fn` for a typo. Two codes match TS2305/TS2459 and Rust E0432/E0603, which models already know.
    Concern: The impl may fix E1023 and leave probe b (private import passes silently) open, so the split exists on paper only.
  - **Minimalism:** A — The two causes need different fixes, so one code would steer tools and agents to the wrong one ("make it `pub`" for a typo). Option B also renames E1003, so it is not the smaller change. One new row costs less than one wrong fix.
    Concern: Later rows may cite this vote as license to split every code by cause, and the table may grow without a check.

- **Q2: Name of the new code.** (6-0). Options: A: `UnknownImportName`. B: `ImportItemNotFound`.
  - **Systems:** A — `UnknownImportName` fits the `Unknown*` family (E0507, E0538, E1014), so a reader can guess the code's shape from its siblings. Most seats already use it.
    Concern: "name" vs the message's "item" is a small mismatch that a reader may notice.
  - **Web/Scripting:** A — `UnknownImportName` reads like the error users already know ("unknown import"), and most of the panel wants it. The message head still says "item", so the name and the text do not have to match word for word.
    Concern: The code name says "name" and the message says "item"; small, but someone will file it as an inconsistency.
  - **PLT:** A — `UnknownImportName` states the failed judgment: the name in the import resolves to nothing. It does not claim that the name is an item, which an undeclared name is not. The difference is small. Both names are sound.
    Concern: "Name" could read as covering the module path, which E1000 owns. The catalog row must say "a listed name".
  - **DevOps/Tooling:** A — `UnknownImportName` matches the `Unknown…` prefix the catalog already uses (`UnknownType`, `UnknownDependencyField`), so `blink explain` and LSP hover read consistently. "Name" is also accurate: the entry does not know whether the name is a fn, a type or a value.
    Concern: none of substance. The help text must still say "item" where that reads better.
  - **AI/ML:** A — `UnknownImportName` follows the `Unknown*` pattern (UnknownType, UnknownEffect, UnknownDependencyField), so a model that knows the catalog can guess the name. One naming pattern for "no such X" costs fewer decision points.
    Concern: The message says "item" and the code says "name"; a reader may think they are two concepts.
  - **Minimalism:** A — It matches `UnknownType` in the existing name set, and most seats already use it. It names what is wrong: the name in the import.
    Concern: "Name" vs "item" in message and code may drift; keep the message head as agreed.

- **Q3: The qualified miss `other.nothere()`.** (6-0). Options: A: out of this decision; it keeps E0505 for now, but its help uses the same candidates and the same nearest-name rule as E1023; moving `m.n` to E1023 is a follow-up. B: E1023 covers `m.n` where `m` is a module qualifier, in this decision.
  - **Systems:** A — The import check is a lookup at the import. `m.n` is resolved at an expression, in a different pass, with its own follow-on rules. Keep this decision small and move `m.n` in a follow-up, with the same candidates now so the help agrees.
    Concern: the follow-up may never get done, which leaves two codes for "this module gives you no such name".
  - **Web/Scripting:** A — `other.nothere()` already gets a clear error at the use, so nothing breaks while it waits. Shared candidates and one nearest-name rule give the user the same suggestion from both forms, and that is what they notice. Moving the code is a clean follow-up.
    Concern: The follow-up could slip, leaving one mistake with two codes for good.
  - **PLT:** A — The qualified miss is the same judgment, and E0505 *UnresolvedMethod* is a false name for it. A shared candidate set and a shared nearest-name rule keep the two sites consistent now. Moving the code is a separate change, and the first step does not depend on it.
    Concern: The follow-up may never land, and E0505 would keep its false name for module members.
  - **DevOps/Tooling:** A — Shared candidates and a shared nearest-name rule give the user the same suggestion at both sites now. Moving `m.n` off E0505 changes an existing code at use sites, and that needs its own corpus sweep and its own ticket.
    Concern: the follow-up ticket may never be done, which leaves "no such name in module" under two codes.
  - **AI/ML:** A — Shared candidates mean both forms suggest the same name now, which is what a model needs. Moving an expression diagnostic changes a different surface and wants its own ticket.
    Concern: The follow-up gets lost, and `other.nothere()` keeps a code named "method" for a long time.
  - **Minimalism:** A — Keep the decision to the gap the ticket names. Moving `m.n` touches expression resolution and E0505, which is its own change with its own tests.
    Concern: The follow-up may never land, and `other.nothere()` keeps a false "method" label for a long time.

- **Q4: Where the spec writes that import checks run when the import is read.** (4-2 → Phase D). Options: A: edit E1003's cause to say the import form is checked when the import is read; the E1023 row says the same. B: one sentence in §10.5 *Imported Names*: every check on an import entry runs when the import is read, not repeated in each cause cell.
  - **Systems:** A — A user, an LSP or an AI looks up one catalog row and must get the full rule from it. A sentence in a separate section is easy to miss. Repeating a short clause in two cells is a small price.
    Concern: a later import code may copy the table row and leave out the clause, so the rule drifts between rows.
  - **Web/Scripting:** A — Users come to a code from `blink explain E1003` or a link from the LSP, not by reading §10.5 from the top. Each row should say on its own when the check runs. One repeated clause is cheap.
    Concern: The rows and §10.5 could drift apart if a later import check adds the rule in one place only.
  - **PLT:** B — The time of the check is one property of every check on an import entry. One rule in §10.5 covers E1003, E1005, E1023 and any future import check. Copying the sentence into each cause cell lets a new row drop it, and the rows can drift apart.
    Concern: A reader who looks at only the E1003 or E1023 cell can miss the rule. The cells should point to §10.5 *Imported Names*.
  - **DevOps/Tooling:** A — `blink explain`, LSP hover and catalog lookups show one row at a time. Each cause cell must be complete when read alone, so the timing belongs in each row. A §10.5 sentence on its own is invisible from the diagnostic surface.
    Concern: the cells can drift apart if a later vote changes the timing for one code only.
  - **AI/ML:** A — Models retrieve one catalog row at a time; a rule that sits only in §10.5 prose is a rule the row's reader does not see. Saying it in each cause cell costs a few words and removes one lookup.
    Concern: The cells and §10.5 drift apart if one later changes and the other does not.
  - **Minimalism:** B — §10.5 already states the rule for E1005. Widening that one sentence covers every import check, and any later import code gets the rule free. Repeating it in each cause cell leaves room for one cell to omit it.
    Concern: If A wins, a future import code may leave the clause out of its cell and be read as lazy.

- **Q5: `import other.{Hidden}` with a private `hidden`.** (4-2 → Phase D). Options: A: E1023; `hidden` is not a candidate; a `note:` says a private item `hidden` exists. B: E1023; `hidden` is not a candidate; no note. C: E1003.
  - **Systems:** A — E1003 must name an item that exists, so E1023 is correct. The note costs one string on the error path and saves a round trip when the user meant the private item and must add `pub`.
    Concern: the note reveals a private name to the importer; that is acceptable inside one package, but check that it reads well across packages.
  - **Web/Scripting:** A — `Hidden` is not `hidden`, so E1003 would be false. But if we say nothing, the user goes looking for a name that exists and is private. One `note:` answers "why can't I find it?" before it turns into a forum question.
    Concern: The note must not read like a suggestion to import `hidden`.
  - **PLT:** A — `Hidden` and `hidden` are different names, so by the judgment the error is E1023, and a private item is never a candidate. A `note:` gives a true fact without suggesting a fix that only leads to E1003. That keeps the code sound and still helps the reader.
    Concern: The note reveals that a private name exists, and an agent may "fix" it by making `hidden` `pub`.
  - **DevOps/Tooling:** B — Names are case-sensitive, so `Hidden` is undeclared. A note about a private `hidden` points the user, or an agent, at a fix that still does not compile (make it `pub`, keep `Hidden`). It also brings back the private-name candidate that every seat agreed to exclude. The plain E1023 is correct and makes no suggestion that leads to a second error.
    Concern: if A wins, the note must never come with a machine-applicable action.
  - **AI/ML:** A — Blink names are case-sensitive, so `Hidden` is not declared and E1003's "`Hidden` is private" would be false. But the note matters for an agent: it says the intended item exists and is private, so the model looks for the public path instead of creating `pub fn Hidden`.
    Concern: The note may tempt an agent to make `hidden` `pub` in a module it does not own.
  - **Minimalism:** B — A note about a private near-match is a special rule for a rare case. It also points at a fix that only leads to E1003. The plain E1023 is true and enough.
    Concern: If A wins, the note becomes one more branch that the impl and tests must carry for little gain.

- **Q6: Help when no candidate is near enough.** (5-1, Minimalism dissent). Options: A: follow E0547: the help lists the candidates; the terminal may shorten the list and count the rest; structured output lists every candidate. B: no help line.
  - **Systems:** A — Same as E0547 and E0525, so all "no such X" rows act alike. The list is built only on the error path, and structured output with every candidate is what an LSP or an AI needs to pick a fix.
    Concern: a large stdlib module can make a long terminal list if the shortening rule is not applied.
  - **Web/Scripting:** A — When you do not know the right name, the list of real names is what you want next. E0525 and E0547 already do this, and one pattern across the catalog is easier to learn than a special case.
    Concern: A module with a large surface could flood the terminal if the shortening is not done well.
  - **PLT:** A — E0525 and E0547 already set this rule for the same kind of question. Matching those rows keeps the catalog compositional, with one rule for "the name is not in this set" instead of one rule per row. Structured output that lists every candidate is the complete answer for tools.
    Concern: A module with many `pub` names makes the terminal list long. The shortening rule must apply.
  - **DevOps/Tooling:** A — E0547 already sets this rule for the same kind of miss. A second rule for "no near candidate" would be one more thing for tools and the spec to carry. A list of what the module exports is the next thing a user would look up, and structured output lets the LSP offer each entry as a completion.
    Concern: a large module (`std.io`) makes the terminal list noisy unless the implementation keeps the shortening rule.
  - **AI/ML:** A — With no suggestion, a list of what the module exports is the one thing that lets an agent fix the import without a second lookup. It matches E0525 and E0547, so one rule covers every "no such X" row.
    Concern: A large module (std) makes the terminal list noisy if the shorten-and-count rule is weak.
  - **Minimalism:** *(dissent)* B — Fields and variants are small closed sets; a module's `pub` items can be hundreds, and the LSP's completion already lists them. The *Conventions* default is "no candidate near enough, no suggestion"; keeping it adds no rule.
    Concern: If A wins, the terminal output for a large std module turns into noise that hides the real error.

- **Q7: What the machine-applicable fix changes.** (4-2 → Phase D). Options: A: the listed name only. B: the listed name and every use of that binding in the file; with an alias (`{nothre as n}`), the listed name only.
  - **Systems:** A — A machine-applicable fix must be safe to apply with no review. Renaming every use in the file has to deal with locals and parameters that shadow the name, which is a rename refactor, not a one-token fix. The minimal edit is predictable; uses that still fail then get their own diagnostics.
    Concern: after the fix, uses of the misspelled name show up as new E0504 errors, which can look like the fix made things worse.
  - **Web/Scripting:** B — If I typed `nothre` in the import, I typed it at the uses too. A fix that renames only the list leaves the file broken, and the next build shows errors at every use. Renaming the binding across the file gives one keystroke and a file that builds, which is what "machine-applicable" should mean. Leaving uses alone under an alias is correct.
    Concern: A use that the user meant to point at a different local (shadowing) could be renamed by mistake if the fix follows text, not the binding.
  - **PLT:** B — A rename of a binder is alpha-conversion: the binder and every occurrence bound to it change together. A fix that changes only the binder leaves each use of `nothre` unbound, so the fix makes new errors. With an alias, the uses bind to the alias, so only the listed name changes.
    Concern: The rename can be captured. If any use site has a local binding of the new name in scope, the fix is not capture-avoiding, so it must not be machine-applicable there.
  - **DevOps/Tooling:** B — A fix that renames only the list leaves every `nothre()` use broken. A "machine-applicable" fix that gives the user a new error defeats the purpose of §8.6 ("an AI agent can apply directly"). A precedent exists: the E0844 fix "renames the key and every `@ffi` that names it, in one edit" (sections/07:1135). The uses already resolve to the poison binding, so the fix knows the exact edit set. With an alias, the uses name the alias and must stay as they are.
    Concern: if A wins, the fix is not truly machine-applicable whenever the file uses the name, and `blink fix` will turn one error into several.
  - **AI/ML:** B — The poison binding hides every use, so a fix that renames only the list makes the uses fail next (E0504), and the agent needs a second round. Renaming the binding and its uses gives a program that compiles in one apply. With an alias, the uses already name the alias, so the list name alone is right.
    Concern: A use of the typo that is not through this binding (a shadowing local) must not be renamed; the fix must follow the binding, not the text.
  - **Minimalism:** A — A fix that edits one span is easy to predict and to check. Uses that still fail after the fix get their own diagnostic with their own suggestion. Renaming every use in the file makes the fix touch code the user did not ask about.
    Concern: If B wins, the fix may rename a use the user spelled on purpose, which is a silent change of meaning.

#### Phase D — Round 2: Q4, Q5, Q7

Q1, Q2, Q3 (6-0) and Q6 (5-1, Minimalism dissent) were decided. Q4, Q5 and Q7 came out 4-2 in Phase C: Q4 A 4 (sys, web, devops, aiml), B 2 (plt, min); Q5 A 4 (sys, web, plt, aiml), B 2 (devops, min); Q7 B 4 (web, devops, plt, aiml), A 2 (sys, min). They got one focused debate round and one more silent vote. The moderator surfaced the three facts quoted under *Moderator facts and probes*.

##### Debate texts

- **Systems** (`D/sys.md`):

> **Q7: I change to B.** My objection was shadowing: a text rename can hit a local that shadows the name. aiml, web and plt answer that. The uses already resolve to the poison binding, so the compiler knows the exact edit set from name resolution, not from a text search. A local `nothre` that shadows the import does not resolve to it and is not touched. plt's capture case is the one real hazard: if the new name is already bound at any use site, the fix must drop to a suggestion. With that condition, B is a closed edit set, the same shape as E0844 (key plus every `@ffi` that names it) and the §2 fix at sections/02_syntax.md:3083. min's "silent change of meaning" cannot happen: each renamed use pointed at a binding that resolves to nothing, so no working code changes meaning. I want the capture rule written in the row.
>
> **Q4: I keep A**, and take plt's concern as an addition: each cell carries the clause, and §10.5 *Imported Names* widens its E1005 sentence to cover every import check. The table stays the lookup surface (devops: `blink explain`, hover); §10.5 holds the general rule for a future code. A and B are not exclusive. If the panel wants one, A, because the row is what tools show.
>
> **Q5: I keep A.** devops and min say the note leads to a fix that fails. It does not when the fix is `import other.{hidden}` plus `pub` in a module the user owns, which is the common case inside a package. I accept devops's condition: the note carries no machine-applicable action and does not appear in the candidate list.

- **Web/Scripting** (`D/web.md`):

> **Q4. My position stays A, but I would take a mix.** plt and min are right that one rule in §10.5 is the source of truth, and the row-copy drift risk is real. sys, devops and aiml are right that people read one row at a time. Both can hold: widen the §10.5 *Imported Names* sentence to cover every import-entry check, and give each cause cell a short clause pointing to it ("checked when the import is read, §10.5"). plt's own concern asks for this pointer. If the ballot keeps only A and B, I stay A.
>
> **Q5. Stays A.** devops says the note brings back a private candidate. It does not: a candidate is a suggested rename with a fix, and the note states a fact with no action. I accept devops's condition: the note never carries a machine-applicable fix, and it never says "make it `pub`". min is right that the case is rare, but the cost is one string, and without it the user greps the module and finds `hidden`, confused.
>
> **Q7. Stays B.** On sys's and min's shadowing worry: the fix follows the binding, not the text. The uses already resolve to the poison entry, so the compiler knows the exact set of occurrences to edit, and a shadowing local is not in it. On min's "a use spelled on purpose": a use bound to an entry that names nothing has no meaning to keep, so the rename cannot change what the program means. Capture is the one real hole (plt): if the new name is shadowed at any use, the fix is not machine-applicable there. Multi-edit fixes already have precedent (E0844 at sections/07:1135, the 02_syntax:3083 rewrite). The E0525 pun case keeps its uses only because its binder does not change.

- **PLT** (`D/plt.md`):

> **Q4. Position changes: I accept A, with one amendment.** sys, web, devops and aiml are right that people and tools read one row at a time, so each cell must state the rule. My concern was drift. The fix for drift is to have both. §10.5 *Imported Names* widens its sentence to "every check on an import entry runs when the import is read". Each import cell also keeps a short clause: "checked when the import is read (§10.5)". The section is the single source, and each row points to it. If the panel will not add the amendment, I still vote A.
>
> **Q5. No change: A.** devops says the note brings back the private candidate. It does not. A candidate drives the help and the fix, but the note only states a fact, and the code stays true: `Hidden` is not declared. I take devops's condition as part of A: the note has no action and no suggested edit. min calls it a special rule. Its cost is one lookup that the private check does anyway.
>
> **Q7. No change: B, with a capture guard.** sys and min fear renaming uses "by text". The fix does not follow text. It follows resolution. The edit set is exactly the uses that resolve to the poison binding, and no other meaning is possible for those uses, because the binding denotes nothing. So min's "a use the user spelled on purpose" cannot occur. The E0525 precedent does not apply. There `y: yy` keeps the program's meaning with one edit, but here no one-edit fix compiles. The multi-edit precedents are sections/02_syntax.md:3083 and E0844. Guard: if the new name is bound at any use site by a closer scope, or is already bound in the file, the fix is a suggestion only. This answers sys's shadowing concern.

- **DevOps/Tooling** (`D/devops.md`):

> **Retraction.** My Q7 text said "§8.6 forbids" a fix that leaves new errors. §8.6 has no such sentence. I withdraw the claim. The argument stands on the E0844 and sections/02:3083 precedents for multi-edit fixes.
>
> **Q4: still A, but I take plt's concern.** Each cell says "checked when the import is read (§10.5 *Imported Names*)". §10.5 may also widen its E1005 sentence to cover every import check. The pointer answers min's and plt's drift concern, and the cell stays complete for `blink explain` and hover. I would accept that merge under either label.
>
> **Q5: I move to A, on one condition.** web and aiml give a real use: without the note, the user looks for a name that exists. My concern was a fix that does not compile. A note gives a fact, not a fix. My condition: the note carries no edit in `--json` and no LSP code action, so `blink fix` can never act on it. sys's cross-package question is not a blocker. The private name is already visible to anyone who reads the dependency source.
>
> **Q7: still B, with plt's capture rule added.**
> - sys and min (shadowing): the fix follows name resolution, not text. It renames only the uses that resolve to the poison binding, so a shadowing local or parameter is never touched (aiml and web say the same).
> - min ("a use spelled on purpose"): a use that resolves to the poison binding is already an error. It means nothing else, so the rename cannot change working code.
> - sys ("not a one-token fix"): multi-edit machine-applicable fixes exist (E0844, sections/02:3083).
> - Capture (plt): if the new name is already bound at any of those uses, the fix is a suggestion only. That is the same carve-out as "already bound in the file".
> - E0525's punned case keeps the binder because it is a valid new local. Here the uses are unbound, so that precedent does not apply.

- **AI/ML** (`D/aiml.md`):

> **Q4.** plt and min are right about drift; sys, devops and web are right that a row read alone must be complete. Both can hold: §10.5 *Imported Names* states the rule once for every import check, and each cause cell says "checked when the import is read (§10.5)". That is A plus plt's own Concern fix. I stay A, and I would vote for that merged text if offered.
>
> **Q5.** devops has the strongest point: "make `hidden` `pub`" still leaves `Hidden` broken. But without the note, an agent sees "no item `Hidden`" and the cheapest edit that clears it is to declare `pub fn Hidden` — the stub problem we split E1003 to avoid. The note states a fact ("a private item `hidden` exists; names are case-sensitive") and the model then knows the item is real. I stay A, with devops's condition: the note carries no fix and no action, and `hidden` never shows as a candidate.
>
> **Q7.** sys and min fear a rename that touches code by text. B does not do that: it renames the uses bound to the poison binding, which are unbound today, so none of them can be "spelled on purpose" (min). A shadowing local is not bound to the import, so it is not touched (sys). E0525's punned-label rule does not cut the other way: there the binder is a name the user chose on purpose; here the binder is the typo. E0844 (sections/07:1135) already renames a key and its uses in one edit. I add plt's capture rule: if the new name is already bound at any use, the fix is not machine-applicable. I stay B with that clause.
>
> No position change.

- **Minimalism** (`D/min.md`):

> **Q4: change to A, on one condition.** devops and web are right that `blink explain` and LSP hover show one row at a time, so a rule that lives only in §10.5 does not reach that reader. A short clause in each cell costs little. My condition is the one from plt's concern: keep the §10.5 sentence general (it already covers E1005), so the section and the rows say the same thing, and a new import row has a rule to copy from.
>
> **Q5: hold B.** We agreed by 6-0 that a private name is never a candidate. A note on a case-folded private match brings that candidate back through a side door and adds one more branch for the impl and its tests. aiml says the note stops an agent from writing `pub fn Hidden`. plt's and aiml's own concerns say the same note invites "make `hidden` `pub`" in a module the agent may not own. One wrong fix replaces another. If A wins, the note must carry no action, as devops asks.
>
> **Q7: change to B.** My concern was a silent change of meaning. plt and devops answer it: the uses already resolve to the poison binding, so the fix follows the binding, not the text, and the edit set is exact. E0844 sets the precedent for a multi-edit rename. E0525 does not argue against it, because there the binder keeps its name. One condition, from plt and sys: if the new name is already bound at any use (capture), the fix is a suggestion only. With an alias, change the listed name only.
>
> Position now: Q4 A (§10.5 stays general), Q5 B, Q7 B (binding-following, capture-avoiding).

##### Phase D ballot

- **Q4.** A: edit E1003's cause to say the import form is checked when the import is read; the E1023 row says the same. B: one sentence in §10.5 *Imported Names* only, not repeated in each cause cell. C: both: §10.5 *Imported Names* widens its sentence to "every check on an import entry runs when the import is read", and each import cause cell keeps a short clause "checked when the import is read (§10.5)".
- **Q5.** A: E1023; `hidden` is not a candidate; a `note:` says a private item `hidden` exists; the note carries no fix, no edit in `--json`, no LSP code action, and never says "make it `pub`". B: E1023; `hidden` is not a candidate; no note.
- **Q7.** A: the listed name only. B: the listed name and every use that resolves to that binding (not a text search; a shadowing local is not touched); with an alias (`{nothre as n}`), the listed name only; if the new name is already bound in the file or at any of those uses (capture), the fix is a suggestion only.

- **Q4: Where the spec writes that import checks run when the import is read.** (6-0 for C)
  - **Systems:** C — The catalog row is what `blink explain`, hover and an AI lookup show, so it must carry the clause. §10.5 holds the general rule, so a future import code gets it even if its cell is written badly. The pointer "(§10.5)" ties the two, so drift has one place to check.
    Concern: a later vote that changes the timing for one code must edit both the cell and §10.5, and may edit only one.
  - **Web/Scripting:** C — Users and tools reach a code one row at a time (from `blink explain` or a language-server link), so each row must state the rule. One sentence in §10.5 keeps a single source of truth that a future import code gets for free. C gives both at the cost of a few words per cell.
    Concern: A later import row may still leave out the clause; the reviewer of that row has to check for it.
  - **PLT:** C — The time of the check is one property of every check on an import entry, so §10.5 states it once. Each cell carries a short clause that points to that section, so a reader who sees one row still gets the rule. Any later import code inherits the rule from the section, and the cell clause shows where it comes from.
    Concern: A later import row may leave out the cell clause. Review must check each new import row for it.
  - **DevOps/Tooling:** C — `blink explain` and LSP hover show one catalog row, so each cell must state the timing. The §10.5 sentence gives one rule that a future import code gets too, and the pointer in each cell links the two. This answers the drift concern from both sides.
    Concern: a later import row may copy the table shape and leave out the clause; a lint or review checklist on the import table should catch that.
  - **AI/ML:** C — A model retrieves one catalog row at a time, so each cell must state the timing; the §10.5 sentence makes one source that a new import code inherits. The pointer "(§10.5)" ties the two together, so a reader of either place finds the rule.
    Concern: A later import code may add its cell without the clause, and the catalog then reads as if that check were lazy.
  - **Minimalism:** C — The rule lives in one place, §10.5. Each cell carries a short clause that points to that place, so a reader who sees one row in `blink explain` or hover still gets the rule. That meets my condition from D, and a new import row has a clause to copy.
    Concern: A later edit may change the clause in one cell and not in §10.5, so the two disagree.

- **Q5: `import other.{Hidden}` with a private `hidden`.** (5-1 for A, Minimalism dissent)
  - **Systems:** A — E1023 stays true, and the note says a fact the user would otherwise search for. With no fix, no `--json` edit and no code action, the note cannot push an agent into an edit; it costs one string on the error path.
    Concern: across packages the note names a private item the user cannot reach, which helps less and may tempt an edit to a dependency.

**Q7. Vote: B**
Reasoning: The uses already resolve to the poison binding, so the edit set comes from name resolution, not text, and is closed and exact. A one-span fix that leaves every use failing is not a fix an agent can apply and trust. The capture guard removes the one case where the rename changes meaning.
Concern: the impl must record the use sites that resolved to the poison binding; if it drops them, the fix falls back to a text search and the guard means nothing.
  - **Web/Scripting:** A — Without the note, the user searches the module, finds `hidden`, and does not see why the import fails. The note answers that in one line. With no fix and no "make it `pub`", it cannot send anyone to a second error.
    Concern: An agent may still read the note as a hint to make `hidden` `pub` in a module it does not own.

**Q7. Vote: B**
Reasoning: The typo in the import is almost always the same typo at each use, so a fix that renames only the list leaves the file broken. Following the binding (not the text) touches only the uses that already point at the bad entry, and the capture guard covers the one unsafe case. One apply gives a file that builds.
Concern: The implementation must use the resolved binding set, not a text search, or a shadowing local gets renamed by mistake.
  - **PLT:** A — `Hidden` is not declared, so E1023 is the true code, and the private item stays out of the candidates and the fix. The note states a fact and offers no action, so it does not lead to a second error. It answers why the name the user expected is not there.
    Concern: Someone may later attach a code action to the note. The catalog row must keep the "no fix, no edit, no action" wording.

**Q7. Vote: B**
Reasoning: A rename of a binder is alpha-conversion. The fix changes the binder and the uses that resolve to it, chosen by resolution and not by text. A fix that changes only the listed name leaves those uses unbound, so it makes new errors. The capture guard turns the fix into a suggestion when a rename could change what a name refers to.
Concern: An implementation may compute the edit set from text and not from resolution. Tests must include a shadowing local and a capture case.
  - **DevOps/Tooling:** A — The note tells the user the name they want exists and is private, so they stop searching. My only objection was a fix that leads to E1003. This option bars any edit, code action or "make it `pub`" text, so no tool can act on the note.
    Concern: an implementation may attach the note's span as a structured suggestion anyway; the catalog row must say "no edit" in so many words, and a test must check the `--json` output.

**Q7. Vote: B**
Reasoning: A fix that renames only the list leaves every use broken, so `blink fix` turns one error into several. Following the binding, not the text, leaves shadowing locals alone. The capture guard drops the fix to a suggestion in the one case where a rename could change meaning.
Concern: the poison binding must record its uses in the resolver; if it does not, the fix falls back to a text search, which is wrong.
  - **AI/ML:** A — Without the note, the cheapest edit an agent sees for "no item `Hidden`" is to declare `pub fn Hidden`, a stub that compiles and is wrong. The note says the real item exists and is private, which steers the model toward the public API. The devops condition (no fix, no code action, no "make it `pub`") keeps it a fact, not a suggestion.
    Concern: An agent may still read the note as permission to make `hidden` `pub` in a module it does not own.

**Q7. Vote: B**
Reasoning: The poison binding hides every use, so a fix on the list alone makes the next build fail at each use, and the agent needs a second round. Renaming by binding gives a file that compiles in one apply and cannot touch a shadowing local. The capture guard drops it to a suggestion in the one case where the rename would change meaning.
Concern: The impl may rename by text instead of by binding, and then rename a local the user meant.
  - **Minimalism:** *(dissent)* B — With the devops condition the note can do no harm through tooling, but it is still a special branch for a rare case-folded match. It also brings back, as text, a private candidate that all six seats excluded. The plain E1023 is true and enough.
    Concern: If A wins, agents may still read the note as "make `hidden` `pub`", and no tooling rule stops a model from acting on prose.

**Q7. Vote: B** (rename the binding and its resolved uses, capture-guarded)
Reasoning: The uses already resolve to the poison binding, so the edit set is exact, and the result builds in one apply. The capture guard and the alias rule answer my concern about a silent change of meaning. E0844 already sets the precedent for a multi-edit rename.
Concern: The impl may fall back to a text match for uses, and then rename a shadowing local by mistake.

- **Q7: What the machine-applicable fix changes.** (6-0 for B)
  - **Systems:** B — The uses already resolve to the poison binding, so the edit set comes from name resolution, not text, and is closed and exact. A one-span fix that leaves every use failing is not a fix an agent can apply and trust. The capture guard removes the one case where the rename changes meaning.
    Concern: the impl must record the use sites that resolved to the poison binding; if it drops them, the fix falls back to a text search and the guard means nothing.
  - **Web/Scripting:** B — The typo in the import is almost always the same typo at each use, so a fix that renames only the list leaves the file broken. Following the binding (not the text) touches only the uses that already point at the bad entry, and the capture guard covers the one unsafe case. One apply gives a file that builds.
    Concern: The implementation must use the resolved binding set, not a text search, or a shadowing local gets renamed by mistake.
  - **PLT:** B — A rename of a binder is alpha-conversion. The fix changes the binder and the uses that resolve to it, chosen by resolution and not by text. A fix that changes only the listed name leaves those uses unbound, so it makes new errors. The capture guard turns the fix into a suggestion when a rename could change what a name refers to.
    Concern: An implementation may compute the edit set from text and not from resolution. Tests must include a shadowing local and a capture case.
  - **DevOps/Tooling:** B — A fix that renames only the list leaves every use broken, so `blink fix` turns one error into several. Following the binding, not the text, leaves shadowing locals alone. The capture guard drops the fix to a suggestion in the one case where a rename could change meaning.
    Concern: the poison binding must record its uses in the resolver; if it does not, the fix falls back to a text search, which is wrong.
  - **AI/ML:** B — The poison binding hides every use, so a fix on the list alone makes the next build fail at each use, and the agent needs a second round. Renaming by binding gives a file that compiles in one apply and cannot touch a shadowing local. The capture guard drops it to a suggestion in the one case where the rename would change meaning.
    Concern: The impl may rename by text instead of by binding, and then rename a local the user meant.
  - **Minimalism:** B — The uses already resolve to the poison binding, so the edit set is exact, and the result builds in one apply. The capture guard and the alias rule answer my concern about a silent change of meaning. E0844 already sets the precedent for a multi-edit rename.
    Concern: The impl may fall back to a text match for uses, and then rename a shadowing local by mistake.

web's vote file ends with this line: "Confirmed after reading every Phase D reply (sys, plt, devops, aiml, min): no change."

Retraction: devops withdrew a claim in Phase D: "**Retraction.** My Q7 text said "§8.6 forbids" a fix that leaves new errors. §8.6 has no such sentence. I withdraw the claim."

### Final Spec

```blink
// other.bl declares `pub fn x`, `pub fn nothere` and a private `fn hidden`
import other.{x, nothre}       // error[E1023]: module `other` has no item `nothre`
import other.{Hidden}          // error[E1023]: module `other` has no item `Hidden`
```

```
error[E1023]: module `other` has no item `nothre`
 --> src/main.bl:1:18
  |
1 | import other.{x, nothre}
  |                  ^^^^^^ not declared in `other`
  |
  = help: did you mean `nothere`?
```

- **E1023 `UnknownImportName`** (Modules, §10.5): a selective import, `import` or `pub import`, lists a name that the module does not declare in either namespace and does not re-export. A name declared without `pub` stays E1003. The message head is "module `other` has no item `nothre`".
- **Span and timing.** The primary span is on the listed name, to the left of any `as`. Every check on an import entry runs when the import is read, used or not. §10.5 *Imported Names* says it for every check; the E1003 import form, E1005 and E1023 cells keep the clause "checked when the import is read (§10.5)".
- **Candidates.** The `pub` items of the module in both namespaces and its `pub import` names, minus names the list already holds. The nearest-name rule of the *Conventions* applies. A private item is never a candidate.
- **No near candidate.** The help lists the candidates; the terminal text may shorten the list and count the rest; structured output lists every candidate.
- **Case.** Names are case-sensitive. `import other.{Hidden}` with a private `hidden` is E1023, with a `note:` that the private item exists. The note carries no fix, no edit in structured output, no editor code action, and never says to make the item `pub`.
- **Fix.** With one suggestion, machine-applicable: it renames the listed name and every use that resolves to the name this entry binds, found by name resolution and not by text. With an alias, only the listed name. A suggestion only when the new name is already bound in the file or at any of those uses.
- **Follow-on diagnostics.** The entry still binds its name, or its alias, to no item. No W0602 on the entry. No E0504, E0507 or E1006 at a use. No part in E1005 or E1012.
- **Qualified miss.** `other.nothere()` keeps E0505. Its help uses the same candidates and the same nearest-name rule. Moving `m.n` to E1023 is a follow-up.
- **Out of scope.** The E1014 drift in the *Import Errors* table.

