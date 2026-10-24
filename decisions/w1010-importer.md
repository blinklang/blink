[< All Decisions](../DECISIONS.md)

# W1010 at a Module That Imports a Shadowing Declaration — Design Rationale

The spec said two things about the warning `W1010 ShadowedPreludeName`. §10.6 *Shadowing Rules* said the compiler
emits "one warning at the declaration", and so did DECISIONS.md (*Builtin type name shadowing*) and the catalog. A
later sentence in §10.6, written for the imported-declared-name collision change, said the rule "also covers such a
name that another module declares and this module imports (`import geo.{Handler}`)". The sentence read as: the
importing module warns too. The compiler warned once, at the declaration, and nowhere else. A package shows the case:

```blink
// src/geo/sim.bl
pub type Handler { n: Int }

// src/main.bl
import geo.sim.{Handler}
fn main() { io.println("x") }
```

The question was: one W1010 at the declaration, or also one per importing module, where the bare name stops meaning
the builtin?

## Summary

| Q | Question | Result | Vote |
|---|---|---|---|
| Q1 | A plain selective import of a shadowing declaration (`import geo.sim.{Handler}`, used or unused) | A: no W1010 at the import; one W1010 at the declaration; the use-site note of *Diagnostics that involve a shadowing name* reaches the importer | 6-0 |
| Q2 | Warnings in a dependency package's files | A: no spec text in this decision; a separate ticket covers which dependency-file diagnostics print, for every warning | 5-1 (PLT dissent: B) |
| Q3 | The words that replace the "also covers such a name" sentence | B: "An import is not a declaration. A module that imports such a name gets no W1010; its uses get the note below. An import alias that is a compiler-known name gets W1010 at the alias (§10.5)." | 6-0 in Phase D (Phase C was A 3, B 2, C 1) |
| Q4 | The help line of the alias W1010 | A: one help, "choose another alias: import geo.sim.{Error as SimError}" | 6-0 |

AI-First review: 5/5 pass.

Points all six seats stated, not balloted:

- An import alias that is a compiler-known name (`import geo.sim.{Error as Option}`) gets W1010 once, at the alias, in
  the importing module. §10.5 *Import Aliases* stays. The compiler gives no W1010 there today: a compiler gap.
- A qualified-only import (`import geo.sim`, then `sim.Handler`) binds no bare name and gets no W1010.
- The "also covers such a name" sentence is replaced. The catalog row for W1010 gains the alias form.
- DECISIONS.md *Selective import and module-level declaration of one name* is not edited. This entry states that its
  parenthetical, "reached by an explicit import" now means a name another module declares, is superseded: the phrase
  now means a name that an import alias binds.
- "Warn at the first bare use in an importer" (aiml, Phase A) had no supporter.

The owner approved this tally.

### Compiler behavior before the decision

The moderator ran six probes with the gen1 compiler and gave the results to the panel:

- p1: `import geo.sim.{Handler}`, name unused. One W1010 at the declaration (`src/geo/sim.bl:1`), with the note "`with`
  in this module still uses `Handler` (blink.core)". Nothing at `src/main.bl` except `UnusedImport`.
- p2: the same import, `Handler { n: 1 }` used in `main`. The same single warning at the declaration; nothing at the
  import.
- p3: `import geo.sim.{Error as Option}`. No W1010 anywhere. §10.5 says this case gets W1010.
- p4: `import geo.sim`, then `sim.Handler { n: 1 }`. The warning at the declaration only.
- p5: `type Handler` declared in `main.bl` itself. W1010 at the declaration.
- p6: a path-dependency package `geolib` declares `pub type Handler`; the `app` package imports `geolib.{Handler}`.
  `blink check` in `app` prints the W1010 at `../geolib/src/geolib.bl:1:5`, a file of the dependency, with the help
  "to use the compiler-known type in this module, import it under another name". Nothing at `app`'s import line.

### Reading gaps in the panel record

- Phase B: aiml did not open the devops and web files (it used the digest). devops read the min and aiml files only to
  about 2500 characters. min first skipped the sys and web files, then read them in full when asked (no change to its
  position).
- Phase C: min read the brief and the Phase B digest through a truncated preview. The other seats read every file in
  full.
- Phase D ran on Q3 only. Moderator fact given in Phase D: both A and B contain "its uses get the note below" (devops,
  in Phase C, had said A lacks it). aiml read web's Phase D reply only to its first lines (its first lines state that
  web holds B); aiml's vote of B had no effect on the result.

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in
independent-proposal, debate, vote rounds. Phase A is excerpted from each panelist's own text; an omission is marked
`[...]`. Phases B, C and D are quoted in full from each panelist's file, without its heading line and its line that
lists the files read.

#### Phase A — Independent proposals

Five seats proposed no W1010 at a plain import. PLT proposed W1010 at each binding. Each seat asked for W1010 at an
alias that is a compiler-known name.

- **Systems:**

> **Rule.** W1010 fires where a module *chooses* a compiler-known name for a binding it owns. Two places:
> 1. A declaration (`type`, alias, `trait`, `effect`): once, at the declaration (07:2833, DECISIONS:369, unchanged).
> 2. An import entry whose *alias* is a compiler-known name: once, at the alias (07:2690, import-alias-collision V5).
>
> An importer of a declared name that shadows a builtin gets no W1010. It did not choose the shadow. The author of the declaration did, and that author already got the warning.
>
> [...]
>
> - p6 (dependency): the W1010 belongs to the package that owns the file. A dependent build cannot edit `../geolib/src/geolib.bl`, so a warning there has no repair (§3.1 Diagnostic Discipline: every diagnostic names a repair that exists). Spec: warnings in a dependency's files are reported when that package is built, not when a dependent builds.
>
> [...]
>
> **Why not one warning per importing module.** N importers give N warnings for one cause, with one repair (rename at the declaration). It breaks the 6-0 "once" (DECISIONS:369). E1012 (DECISIONS:396) is about two colliding bindings; a lone import collides with nothing. DECISIONS:413 describes lookup, not a warning site. The importer may not know bare `Handler` is not the builtin; the use-site note (07:2925) covers that when it matters.
>
> **Spec and catalog edits.**
> - 07:2846: replace "It also covers such a name that another module declares and this module imports (`import geo.{Handler}`)." with "A module that imports such a name gets no W1010: the warning is at the declaration only. An import entry whose alias is a compiler-known name gets W1010 at the alias (§10.5 *Import Aliases*)."

- **Web/Scripting:**

> Rule: W1010 fires where someone *writes a new type-namespace name that is also compiler-known*. A `type`, alias, `trait` or `effect` declaration writes one. An alias `as Option` writes one. A plain `import geo.sim.{Handler}` writes none: it names a declaration that already exists. The importer chose the name by writing it.
>
> [...]
>
> - **Dependency (p6):** the declaration warning is the dependency author's to fix. `blink check` in `app` should not print warnings for files of other packages (Cargo's cap-lints idea). They show when the dependency itself is checked. If the compiler cannot do this yet, file a tooling chore. Do not make the spec depend on it. When the dependency's warning is shown, its help ("import it under another name") is wrong for the reader in `app`; it must not tell them to edit a file they do not own.
>
> [...]
>
> - 07:2846: delete "It also covers such a name that another module declares and this module imports (`import geo.{Handler}`)". Replace: "An import alias that is a compiler-known name is covered too (§10.5). A plain import of a declaration is not: the warning is at the declaration."

- **PLT:**

> W1010 marks the place where a module's bare type-name changes meaning. Resolution is per module (§3.4), so the typing rule is: *one warning per binding that puts a compiler-known name into a module's type namespace*. A declaration is such a binding. A selective import is such a binding. A qualified path (`sim.Handler`) binds no bare name and shadows nothing.
>
> [...]
>
> Use is irrelevant. The binding changes the meaning of the bare name whether or not code uses it. An unused import then gets two diagnostics. Rule 3 of *Diagnostic Discipline* holds: removing the import discharges both, and the `help:` order must put "remove the unused import" first.
>
> Dependency case (p6). Today the app author sees a warning at `../geolib/src/geolib.bl:1:5` and the help tells them to edit a file they do not own. Rule 1 says a prescribed repair must exist, and here it does not. So: the declaration warning fires only when the declaring package is the check root. The importer's warning is the one the app author can fix (alias at the import).
>
> [...]
>
> Tradeoff: N+1 warnings for N importers. Each has a local repair, and it matches DECISIONS.md:413 ("modules that import the declaration").
>
> ## plt-2: declaration only
> Delete the 07:2846 sentence; keep `import auth.{Error as Option}` under W1010 as 07:2690 says (that is a binding, not an import of a shadowing declaration). The importer gets no signal, and p6 still violates rule 1.
>
> [...]
>
> I vote plt-1 over plt-2.

- **DevOps:**

> Rule: W1010 fires at the site that picks the shadowing name. That is a declaration (`type`, alias, `trait`, `effect`) or an import alias that is a compiler-known name. A plain selective or qualified import picks nothing. It gets no W1010.
>
> [...]
>
> Why not warn at the import (devops-2, rejected): a second W1010 at `import geo.sim.{Handler}` repeats the declaration's warning with no new fact. Its only repair is "remove the import", which deletes what the user needed. That fails rule 1. It also fails rule 3: the declaration's help (`import blink.core.{Handler as X}`) is a different edit. Another module cannot silence a declaration warning, so the count is not tied to an edit the importer can make. The use-site note (07:2925) already tells the importer that `Handler` is the shadow and not the builtin, at the point of confusion and only when the name is used.
>
> Spec and catalog edits:
> - 07:2846 replace "It also covers such a name that another module declares and this module imports (`import geo.{Handler}`)" with: "An import is not a declaration. A module that imports such a name gets no W1010; its uses carry the shadow note below. An import alias that is a compiler-known name is a declaration of that name and gets W1010 at the alias (§10.5)."
> - 07:2539/DECISIONS.md:369 stay. The DECISIONS.md:396 amendment parenthetical ("explicit import now means a name another module declares") is superseded. Note this in the new entry.

- **AI/ML:**

> ## aiml-1 (recommended): W1010 fires at a declaration and at an alias the importer writes. A plain import never warns.
>
> [...]
>
> - An LLM can state one rule from the spec: "W1010 sits where an author wrote the binder." A declaration and an alias are binders. A selective import binds a name another author chose.
> - A warning per importer repeats in every file. An agent in a fix loop would alias the name in N files to silence it. That burns tokens and carries no new signal.
> - Diagnostic Discipline Rule 3: `import geo.sim.{Handler}` can already carry UnusedImport. A third warning adds a point where repairs must converge, for no gain.
>
> ## aiml-2 (alternative): also warn at the first bare use in an importer
>
> One extra decision point for every user. The repair (alias) renames every use. I oppose it: the use-site note already says the same.

- **Minimalism:**

> Rule: W1010 fires where a module *chooses* a name that shadows a compiler-known name. Choosing means a declaration (`type`, alias, `trait`, `effect`) or an import alias. A plain selective import chooses nothing; the declarer chose. One choice, one warning.
>
> [...]
>
> ## Spec and catalog edits (all subtraction)
> - 07:2846: delete the sentence "It also covers such a name that another module declares and this module imports (`import geo.{Handler}`)". Replace with: "An import alias that takes such a name is covered too (§10.5 *Import Aliases*)."
>
> [...]
>
> ## min-2 (rejected, for the record): also warn per importing module
> Cost: a second emit site, a "bare name in importer" analysis, a new note text, a dedup rule across N modules, and a gate rule for dependencies. Benefit: none the use-site note lacks. Reject.

#### Phase B — Debate, round 1

Each seat read the other Phase A files and gave a position on five options: O1 (a plain selective import), O2 (a
dependency package), O3 (the DECISIONS.md parenthetical), O4 (the words), O5 (the alias help). PLT moved from
"each binding" to "declaration only" on one condition. sys moved from "spec says it" to "ticket" on O2. All six ended
with `STATUS: ready to vote`.

- **Systems:**

> **O1: no W1010 at a plain selective import. I oppose plt-1.** Four reasons, none about runtime cost (resolution is compile-time, so there is none):
> - plt-1 gives N+1 warnings for one cause. The cause is the declaration, and its rename repairs all N importers at once. The importer's alias repair only hides the symptom in one module.
> - An unused import then gets two diagnostics (plt-1 admits it). Rule 3 (diagnostics at one point converge) is met only by a help-order patch. With no import warning, no patch is needed.
> - plt-1 breaks the 6-0 "once at the declaration" (DECISIONS:369) to add a lint. The 07:2848 collision rules already say what a lone import is: not a collision.
> - The importer wrote the name. The use-site note (07:2925) tells them when the shadow matters.
> I concede one point to plt-1: the unwarned importer is silent until first use. That is a cost. I judge it smaller than N warnings. aiml-2 (warn at first bare use) adds a second warning site for the same cause; I oppose it.
>
> **O2: I change my Phase A position.** I proposed one spec sentence on dependency warnings. Facts show no text in sections/ covers dependency-file warnings at all, and the rule is not specific to W1010. A W1010-only sentence would be an odd special case. Spec text stays "one warning at the declaration". File one ticket for the general rule (diagnostics in dependency files, all warnings). I now side with devops-1, web-1 and aiml-1. I oppose plt-1's "importer warns, declaration silent in dependencies": it ties the plt-1 rule to a rule that does not exist.
>
> **O3:** The DECISIONS:396 parenthetical is superseded. The new entry says so: "reached by an explicit import" means only an alias that binds a compiler-known name. I accept min-1/aiml-1 wording.
>
> **O4:** Use devops-1 wording ("An import is not a declaration..."). It is short and it says why. My Phase A wording is acceptable second choice.
>
> **O5:** Use "choose another alias: import geo.sim.{Error as SimError}" (devops-1, aiml-1). I withdraw my `blink.core.{Option as CoreOption}` option. It reaches the builtin, but the alias is the shadow, and the repair for the alias is a new alias.
>
> **Ballot:** O1 two options (declaration only; plt-1 each binding). O2 two options (spec states dependency rule; no spec text, ticket). O3, O4, O5: one wording each, as above.

- **Web/Scripting:**

> ## O1. No W1010 at a plain import. Oppose plt-1 and aiml-2.
> plt-1 is the only real rival. Its principle is sound, but it warns on code the importer wrote on purpose and can fix only by renaming a type they did not make. Every consumer of a package with `type Error` gets a warning. Rule 3 of *Diagnostic Discipline* is also strained: an unused import gets two diagnostics (UnusedImport and W1010) at one point. I concede plt's point that the bare name changes meaning in the importer. The 07:2925 use-site note and the 07:2992 note already tell the importer at the place where it matters. aiml-2 adds a third site and a decision point; I oppose it too.
>
> ## O2. Spec stays silent on dependency warnings; separate ticket. Open question answer: every warning, not W1010 only.
> No sections/ text covers dependency warnings (B1 facts). A W1010-only rule is a special case a user must learn. The real rule is "warnings in another package's files are not shown", which is a tooling policy for all lints (Cargo cap-lints). It deserves its own ticket and its own vote. I concede plt's and devops' point that p6 breaks rule 1 today: the help tells the app author to edit a file they do not own. This is a bug in the p6 output, so it supports the ticket, not a W1010 spec sentence. If the panel wants one spec sentence, I accept a general one, not one in §10.6.
>
> ## O3. Correction note on DECISIONS.md:396 that points to the new entry. Not an edit of the 369 text. Any wording works; this is the lowest-stakes option.
>
> ## O4. Words for 07:2846. Prefer devops-1 or aiml-1 over mine.
> Mine says "the warning is at the declaration" but does not say "a module that imports gets no W1010" or point to the use-site note. aiml-1 is shortest and complete. I withdraw my wording. Not on the ballot as a wording vote; the editor picks.
>
> ## O5. Alias help line: "choose another alias: import geo.sim.{Error as SimError}" (devops-1/aiml-1). It is concrete and its repair exists. I withdraw "import it under another name": the compiler-known name is the problem the alias made.
>
> Ballot: O1 (plt-1 vs no-import-warning) and O2 (spec sentence vs separate ticket, with the scope question). O3, O4, O5 are drafting choices.

- **PLT:**

> **O1.** I concede ground. sys-1's point holds: the importer did not choose the shadow, the declaration author did, and DECISIONS:369 says "once" (6-0). My plt-1 "use is irrelevant" also doubles the diagnostics on an unused import. Warnings do not affect soundness, and 07:2929 keeps desugaring by identity, so the importer's program stays sound without a warning. I still hold that a selective import is a binding (DECISIONS:396 treats it as one). So I accept declaration-only on one condition: the use-site note (07:2925) is guaranteed wherever a diagnostic involves the name. Put both on the ballot: plt-1 (each binding) and declaration-only. I vote declaration-only unless someone shows the note misses a case. I oppose aiml-2 (warn at first bare use): the warning would depend on use order and would move when code moves.
>
> **O2.** Put it in the spec. A rule that "a dependency's own-file warnings are reported when that package is built" is compositional. A W1010-only rule is not: W1000 and every later warning would need its own sentence. The open question has an answer in Diagnostic Discipline rule 1: a warning whose repair is in a file the user cannot edit has no repair. So scope the sentence to warnings (not errors; an error in a dependency must still fail the dependent build). If the panel will not decide the general rule, ballot the W1010-only sentence and file a ticket to widen it. devops-1/web-1/aiml-1 ("spec stays, ticket") leaves p6 against rule 1 in the spec text, so I oppose it.
>
> **O3.** The DECISIONS:396 parenthetical is superseded. The new entry records that "reached by an explicit import" now means an alias that binds a compiler-known name. If plt-1 wins, DECISIONS:369 is amended instead.
>
> **O4.** Use min/aiml wording. I reject devops-1's "an alias is a declaration of that name": an alias is a binding, not a declaration, and 07:2848 already speaks of "declarations or imports".
>
> **O5.** First help: "choose another alias" (the repair that removes the warning). Second: `import blink.core.{Option as CoreOption}`. Rule 3 asks for the converging repair first.

- **DevOps:**

> ## Position
>
> **O1. Declaration only (five of six, including my own).** I concede one point to plt-1: its importer help (`{Handler as SimHandler}`) is a real repair, so Rule 1 is not broken. The plt-1 case still fails on three other counts.
> - Rule 3: an unused `import geo.sim.{Handler}` would carry W1010 and UnusedImport. Their repairs differ, so the user needs the right one named first. Today there is one warning and one repair.
> - The warning fires in every importer and adds no fact the use-site note (07:2925) does not give when the name matters. An agent in a fix loop aliases the name in N files to silence it.
> - plt-1 amends DECISIONS.md:369, a 6-0 vote ("once at the declaration"). The alias-only rule keeps that vote intact.
>
> aiml-2 (warn at the first bare use) is worse. The warning would move with an edit to the body and not to the import.
>
> **O2. Keep out of the W1010 spec.** No text in sections/ covers dependency warnings at all. A W1010-only carve-out is the wrong place to set that policy. It would leave E-codes, W1000 and every other warning in a dependency file unspecified. I would not vote for a one-sentence W1010 rule. I ask for a toolchain ticket: "which diagnostics from a dependency's files print when a dependent is checked". If the panel insists on text, make the rule cover all warnings from a dependency, and put it in the toolchain section (§10.x). Either way the p6 help line ("import it under another name") misleads the app user today. The ticket should note that.
>
> **O3.** The new decision entry states that the DECISIONS.md:396 parenthetical ("a name another module declares") is superseded and now means "a name an import alias binds". Do not edit history.
>
> **O4.** Use the aiml wording, with "import is not a declaration" added as the reason:
> "An import is not a declaration. A module that imports such a name gets no W1010; its uses get the note below. An import alias that is a compiler-known name gets W1010 at the alias (§10.5)."
>
> **O5.** `choose another alias: import geo.sim.{Error as SimError}`. A help with a concrete edit can be followed by a human and by `blink fix`. A bare "choose another alias" cannot.
>
> ## Ballot
> O1 (declaration plus alias, importer silent, against plt-1). O2 as a separate ticket, not in this decision. O3, O4 and O5 as above.

- **AI/ML:**

> **O1. Support: no W1010 at a plain selective import.** I oppose plt-1. Its principle, "a bare name changes meaning", is true, but the 07:2925 use-site note already tells the importer at the point where the change matters. plt-1 warns on an unused import too, which makes two diagnostics for one line; removing the import is the repair that clears both, but an agent following the first help (`as SimHandler`) renames an import it should delete. That is a Rule 3 hazard plt-1 itself admits, and it needs an ordering rule that an LLM must learn. N importers give N warnings and N alias edits. The binder rule "the author who wrote the binder is warned" fits in one sentence. Concession to plt: if a plain import must warn, warn only on use, not on an unused import. I still vote against it.
>
> **O2. Keep the spec at "one warning at the declaration". File a tooling ticket.** plt, min and sys are right that the help line gives the app author no repair (Rule 1). But no text in sections/ says what a dependency's warnings do. Does the rule cover all warnings or only W1010? A W1010-only rule is a special case that an AI cannot infer from other warnings. The rule belongs in a general section on dependency diagnostics, decided on its own. Do not ballot it in this ticket. Put one line in the ticket text: the cap applies to every lint.
>
> **O3. Correct the DECISIONS.md:396 parenthetical.** Use my wording: "reached by an explicit import" now means "a name an import alias binds". Add a dated amendment line in the new entry.
>
> **O4. Use the aiml-1 / sys-1 wording.** Reject devops-1's "An import alias ... is a declaration of that name". It conflicts with 07:2848 and the duplicate rules: an alias is a binding, not a declaration. Do not add a new category.
>
> **O5. Help text: "choose another alias: import geo.sim.{Error as SimError}".** A concrete line can be copied. Do not add a second help for blink.core: the alias does not hide the builtin the way a declaration does, so that help names no repair.
>
> **Ballot:** O1 (two options: declaration only, or each binding); O3 and O4 as wording items; O2 as a ticket, not a vote.

- **Minimalism:**

> **O1. Support: declaration only; no W1010 at a plain import.** Five of six seats agree. I oppose plt-1. Its "use is irrelevant" rule makes `import geo.sim.{Handler}` a second warning for a fact the importer did not choose. Its first help line, `Handler as SimHandler`, is a repair that exists. But it renames the import in every importer, so N files give N warnings for one declaration. It also adds a second emit site, a new message, and a new 07:2992 interaction, and it reverses a 6-0 vote (DECISIONS.md:369, "once at the declaration"). The use-site note (07:2925) already tells the importer at the point of confusion. aiml-2 (warn at first bare use) is the same cost again: reject. plt-1 goes on the ballot as the opposing option; aiml-2 does not.
>
> **O2. Concession: the spec stays "one warning at the declaration"; the dependency rule goes in a separate ticket.** I dropped it from min-1's catalog edit. The spec is silent on warnings in dependency files, and the real question (W1010 only, or every warning?) is wider than this ticket. A W1010-only carve-out adds a special case. Only the general rule is subtraction, and it belongs to the tooling seat. plt-1's version ("warn at the importer instead of the declaration") is a new emit site again. Ballot: "spec silent, tooling ticket" versus "spec says it".
>
> **O3. Support devops-1:** one new DECISIONS.md entry that states the :396 parenthetical is superseded ("a name an import alias binds"). I will not edit :396 itself.
>
> **O4. Support min-1's short wording**, with devops' first sentence added: "An import is not a declaration." The extra text in sys and devops is fine only if it stays at two sentences.
>
> **O5. Support devops/aiml:** "choose another alias: import geo.sim.{Error as SimError}". An example in help costs nothing and helps a model in a fix loop. sys's second option (`CoreOption`) is a different repair, so it breaks Rule 3. Leave it out.
>
> **Ballot:** O1 (declaration-only vs plt-1), O2 (spec says vs separate ticket), O3 and O4 as single wording picks. O5 can be settled by the writer.

#### Phase C — Silent ballot

Each seat voted alone on four questions. The option text is as follows.

- **Q1.** A plain selective import of a shadowing declaration (`import geo.sim.{Handler}`, used or unused).
  - A: No W1010 at the import. One W1010 at the declaration only; the use-site note reaches the importer.
  - B: W1010 at each binding: the declaration and each selective import or alias that binds the name; first importer help `import geo.sim.{Handler as SimHandler}`; amends the 6-0 "once at the declaration" row.
- **Q2.** Warnings in a dependency package's files.
  - A: No spec text in this decision. The spec stays "one warning at the declaration". A separate ticket covers which diagnostics from a dependency's files print when a dependent is checked, for every warning, not W1010 only.
  - B: The spec states a general rule now: a dependency's own-file warnings (not errors) are reported only when that package is built.
  - C: A W1010-only sentence now, plus a ticket to widen it.
- **Q3.** The words that replace the sentence "It also covers such a name that another module declares and this module imports (`import geo.{Handler}`)."
  - A: "A module that imports such a name gets no W1010; its uses get the note below. An alias that is a compiler-known name gets W1010 at the alias (§10.5)."
  - B: "An import is not a declaration. A module that imports such a name gets no W1010; its uses get the note below. An import alias that is a compiler-known name gets W1010 at the alias (§10.5)."
  - C: "An import is not a declaration. An import alias that takes such a name is covered too (§10.5 *Import Aliases*)."
  - D: "An import is not a declaration. A module that imports such a name gets no W1010; its uses carry the shadow note below. An import alias that is a compiler-known name is a declaration of that name and gets W1010 at the alias (§10.5)."
- **Q4.** The help line of the alias W1010.
  - A: One help: "choose another alias: import geo.sim.{Error as SimError}".
  - B: Two helps: first "choose another alias", second `import blink.core.{Option as CoreOption}`.

Results: Q1 A 6-0. Q2 A 5-1 (plt voted B). Q3 A 3 (aiml, plt, web), B 2 (sys, devops), C 1 (min). Q4 A 6-0.

##### Q1 — votes

- **Systems: A.**
  - Reasoning: Name resolution is compile-time and desugarings use the builtin by identity (07:2929), so a shadow has no runtime or codegen effect. The importer did not choose the shadow; one rename at the declaration fixes every importer, while a per-importer alias edit only hides the symptom in one module. A is also the only option that keeps the 6-0 "once at the declaration" vote (DECISIONS.md:369) intact.
  - Concern: An importer stays silent until a diagnostic at a use shows the 07:2925 note, so a quiet change in what a bare name means is possible if that note misses a case.
- **Web/Scripting: A.**
  - Reasoning: A JS or Python dev who writes `import geo.sim.{Handler}` typed the name on purpose. A warning on that line asks them to rename a type they did not write, and every consumer of a package with `type Error` would get it. The use-site note (07:2903 point 2) already says "Handler here is type Handler (...), which shadows ..." with the aliased-import help, at the place where a wrong guess about the name shows up. Python linters (`redefined-builtin`) flag the binder in the file that wrote it, not importers, and this matches.
  - Concern: An importer stays silent until the first diagnostic that involves the name, and plt's guarantee holds only if every diagnostic path really carries the note.
- **PLT: A.**
  - Reasoning: The importer's program stays sound without a warning: desugarings use the compiler-known type by identity (07:2929), and resolution is per module (§3.4). 07:2903 point 2 guarantees the shadow note on every diagnostic whose subject is the shadowing name (E0303, E0300, missing method, any other), so the importer learns of the shadow where it matters. That meets my condition from B1. An unused plain import under B would carry two diagnostics with different repairs, which strains Rule 3 of Diagnostic Discipline.
  - Concern: A silent selective import changes what a bare name means in the importer. A program that never hits a diagnostic never gets told, because 07:2903 fires only when a diagnostic arises.
- **DevOps: A.**
  - Reasoning: W1010 belongs at the site that chose the name. A plain import chooses nothing. A second warning on an unused import puts W1010 and UnusedImport at one point with different repairs, which strains Diagnostic Discipline rule 3. The use-site note (07:2903, point 2) reaches the importer where the shadow matters, and it covers every diagnostic whose subject is the shadowing name. A also keeps the 6-0 "once at the declaration" in DECISIONS.md:369.
  - Concern: The importer stays silent until a diagnostic involves the name, so a clean use that silently means the user type, not the builtin, gets no signal.
- **AI/ML: A.**
  - Reasoning: A model can learn one rule from the spec: W1010 fires where an author wrote the binder, which is a declaration or an alias. A plain import binds a name another author chose, so it carries no warning. Warning per importer gives N files the same fact and N alias edits in a fix loop. 07:2903 point 2 guarantees the use-site note on every diagnostic that involves the name, so plt's condition holds, and the importer learns where it matters.
  - Concern: An importer stays silent until a diagnostic involves the name, and an agent may read bare `Handler` as the builtin in code that raises no diagnostic.
- **Minimalism: A.**
  - Reasoning: A plain import chooses no name; the declaration author chose it and is warned once. B adds a second emit site, a new message, and N warnings for one cause, and it reverses a 6-0 vote (DECISIONS.md:369). plt's own B1 accepts A unless the 07:2903 note misses a case, and that note covers every diagnostic whose subject is the shadowing name.
  - Concern: The importer stays silent until a diagnostic involves the name; if a case exists where the 07:2903 note is not emitted, the importer gets no signal at all.

##### Q2 — votes

- **Systems: A.**
  - Reasoning: I withdrew my Phase A sentence. No text in sections/ covers dependency-file warnings, and a W1010-only sentence is a special case that W1000 and later warnings would each need to copy. The general rule (which dependency-file diagnostics print) is a toolchain policy that needs its own decision.
  - Concern: Until the ticket lands, p6 still prints a warning whose help tells the app author to edit a file they do not own, which breaks Diagnostic Discipline rule 1.
- **Web/Scripting: A.**
  - Reasoning: No text in sections/ covers warnings in dependency files. A W1010-only sentence is a special case a user must learn and then unlearn. The real rule (cap lints in dependencies, as Cargo does) is a tooling policy for every warning and deserves its own ticket and vote. The p6 help text that tells the app author to edit a file they do not own is a bug that supports that ticket.
  - Concern: Until the ticket lands, `blink check` in an app keeps printing a warning with a repair the app author cannot make.
- **PLT: B.**
  - Reasoning: A dependency-file warning whose repair lies in a file the user cannot edit has no repair (Rule 1). A general rule scoped to warnings composes: W1000 and later warnings need no sentence of their own. Errors in a dependency must still fail the dependent build, so the rule must say "warnings, not errors". A W1010-only sentence (C) is a special case that the next warning must copy.
  - Concern: With A, the spec text leaves p6 against Rule 1 until the ticket lands, and the app author sees a help line that tells them to edit a file they do not own.
- **DevOps: A.**
  - Reasoning: No text in sections/ covers warnings in a dependency's files. A W1010-only sentence is a special case, and a general rule needs its own deliberation and the toolchain seat's input (which diagnostics print, and what happens to errors). The p6 help line misleads the app user today; the ticket must record that.
  - Concern: Until the ticket lands, p6 prints a warning whose help tells the user to edit a file they do not own (rule 1).
- **AI/ML: A.**
  - Reasoning: No sections/ text covers warnings in dependency files. A W1010-only sentence is a special case a model cannot infer from other warnings, and it would need widening later. The rule belongs to one decision on all dependency diagnostics, with errors still failing the dependent build.
  - Concern: Until the ticket lands, p6 prints a W1010 with a help line that tells the app author to edit a file they do not own.
- **Minimalism: A.**
  - Reasoning: No section covers warnings in dependency files. A W1010-only sentence (C) is a special case that the general rule would later delete. A general rule (B) is a tooling policy decided without tooling-side analysis, in a decision about one warning. The ticket decides it once, for every warning.
  - Concern: Until the ticket lands, p6 still prints a W1010 whose help tells the app author to edit a file they do not own.

##### Q3 — votes

- **Systems: B.**
  - Reasoning: B gives the reason ("An import is not a declaration"), states the no-W1010 rule for importers, and points to the use-site note, so a reader needs no other text. I move off D (my B1 pick): "is a declaration of that name" conflicts with 07:2848, which speaks of "declarations or imports", and aiml and plt are right that an alias is a binding. B is D without that phrase.
  - Concern: A is shorter, and C drops the statement that a plain importer gets no W1010, so the final text must keep that sentence or readers will guess.
- **Web/Scripting: A.**
  - Reasoning: It is the shortest wording and it is complete. It states the rule (importer gets no W1010), points to the note, and states the alias case with a section link. A reader does not need a new category. "Is a declaration of that name" (D) conflicts with 07:2848, where an alias is a binding.
  - Concern: Without "An import is not a declaration" a reader may not see why the rule is what it is; the section text near it must carry that reason.
- **PLT: A.**
  - Reasoning: An alias is a binding, not a declaration (07:2848 says "declarations or imports"). D puts a wrong category in the spec, and C omits the stated rule for plain imports. A is the shortest text that states both the no-W1010 rule and the alias case.
  - Concern: A omits the reason ("an import is not a declaration"). A reader may take the no-warning rule as an oversight and not a design choice.
- **DevOps: B.**
  - Reasoning: "An import is not a declaration" gives the reason in six words and keeps the importer rule and the alias rule in one place. I drop "is a declaration of that name" from my own D: aiml and plt are right that an alias is a binding, and 07:2848 already speaks of "declarations or imports". B keeps the use-site pointer that A lacks.
  - Concern: "its uses get the note below" ties the sentence to 07:2903 point 2, so any use-site diagnostic that omits the note makes the spec text false.
- **AI/ML: A.**
  - Reasoning: It is the shortest wording that states the whole rule: no W1010 for the importer, uses get the note, an alias gets W1010 at the alias. It does not call an alias a declaration, which conflicts with 07:2848 ("declarations or imports"). A new category costs a model one more term to learn.
  - Concern: Without the sentence "An import is not a declaration", a reader may not see why the import is exempt.
- **Minimalism: C.**
  - Reasoning: The sentence replaces a longer one, so shorter is subtraction. "An import is not a declaration" gives the reason and implies the importer gets no W1010; the alias clause points to §10.5, which already states the rule. A and B repeat what §10.5 and the note below already say.
  - Concern: C does not say outright that the importer's uses get the note, so a reader must find 07:2903 on their own.

##### Q4 — votes

- **Systems: A.**
  - Reasoning: The alias is the shadow, so the repair that clears the warning is a new alias; a concrete one-line edit is what a human or `blink fix` can apply. A second help that reaches the builtin is a different repair and breaks Rule 3 (one converging repair, named first), and it names no repair for the problem the alias made.
  - Concern: A user who wants the builtin under its own name gets no pointer to `import blink.core.{Option as CoreOption}` from this warning.
- **Web/Scripting: A.**
  - Reasoning: One concrete help line (`import geo.sim.{Error as SimError}`) can be copied by a human or by `blink fix`. The alias is the shadow, so the repair for it is a new alias. A second help for `blink.core.{Option as CoreOption}` adds a decision point and a second repair at one point, which strains Rule 3.
  - Concern: A user who wants the builtin `Option` and the aliased `Error` in one module sees no help line that says how to reach the builtin.
- **PLT: A.**
  - Reasoning: I concede my B1 position. The second help (`import blink.core.{Option as CoreOption}`) reaches the builtin but does not discharge the alias warning. It is not a repair of this diagnostic, so Rule 3 does not ask for it. The first help is the converging repair and it carries a concrete edit.
  - Concern: A reader who wants the builtin and the imported type in one module gets no pointer to the builtin's escape hatch.
- **DevOps: A.**
  - Reasoning: The alias is the shadow, so the repair is a new alias. One help with a concrete edit can be copied by a human or `blink fix`. A second help that reaches the builtin names a different edit at the same point, which breaks rule 3.
  - Concern: A user who wants both the user type and the builtin gets no pointer to `blink.core.{Option as CoreOption}` from this warning.
- **AI/ML: A.**
  - Reasoning: One help with a concrete line, `import geo.sim.{Error as SimError}`, is copyable by a human and by an agent. A second help (`blink.core.{Option as CoreOption}`) is a different edit at the same point and does not repair the alias. That adds a decision point and breaks the convergence of Rule 3.
  - Concern: One help line gives no route to the builtin for a user who also wants `Option` from blink.core under another name.
- **Minimalism: A.**
  - Reasoning: One help line with a concrete, copyable edit gives one repair. B's second help (`blink.core.{Option as CoreOption}`) is a different repair for the same warning, which breaks Rule 3, and it names no repair for the alias because the alias is the shadow. sys withdrew that option in B1.
  - Concern: The help line hard-codes an example alias name (`SimError`), which a user may take as a required naming convention.

#### Phase D — Focused round on Q3

Q1, Q2 and Q4 were decided in Phase C. Q3 was closer than 5-1, so it got one focused round. The moderator gave each
seat the Phase C Q3 text and this fact: "A and B both contain 'its uses get the note below'. The words in B and not in A
are 'An import is not a declaration.' and 'import' in 'An import alias'." Option D had no vote and no Phase D support.

##### Phase D1 — Replies

- **Systems: holds B.**

> The C concerns of aiml, plt and web all name the same gap in A: it omits why the importer is exempt. Their Concern lines say a reader may take the no-warning rule as an oversight. B closes that gap with six words, "An import is not a declaration." Those words also settle the 07:2848 reading: that sentence already puts "declarations or imports" in separate classes, so B adds no new category.
>
> C does not state the importer rule outright, so I keep it below B. min is right that §10.5 holds the alias rule, but 07:2846 is the sentence a reader finds first when the question is "does the importer warn?". It should answer that question in the text.
>
> The only extra word in B is "import" in "An import alias". It matches the term in §10.5 *Import Aliases*, so it costs a model no new term.
>
> No change to the B wording. If A wins, I accept it with no objection: the rule is the same and only the reason sentence is missing.

- **Web/Scripting: moves from A to B.**

> Three A voters (aiml, plt, me) name the same concern: A gives no reason for the importer rule. A reader who finds "gets no W1010" with no cause may think the spec forgot the case. That is the Stack Overflow question: "why does the importer not get a warning?" B answers it in six words, "An import is not a declaration." It costs one short sentence.
>
> B has the same rule as A. B does not call an alias a declaration, so the 07:2848 conflict that aiml and plt raised against D does not apply. Five seats now hold a vote or a concern that B settles. C drops the plain-importer sentence, and sys and devops are right that readers would guess.
>
> Devops' concern stands: every use-site diagnostic must carry the 07:2903 note, or the sentence is false.

- **PLT: moves from A to B.**

> My A vote rested on the rule that an alias is a binding, not a declaration. B keeps that rule: it says "An import is not a declaration" and it never calls an alias a declaration. The category objection applied to D, and D is gone.
>
> The concern I wrote against A was that a reader takes the no-warning rule for an oversight. Three seats (aiml, plt, web) wrote the same concern against A. B answers it in six words. The cost is that B is longer, and the reason is a true statement that 07:2848 already supports ("declarations or imports").
>
> I reject C. It omits the statement that a plain importer gets no W1010. Without that sentence the replaced 07:2846 text leaves the importer case to guesswork, and that was the gap in the ticket.
>
> Concern: "its uses get the note below" is true only while 07:2903 point 2 holds for every diagnostic path.

- **DevOps: holds B.**

> Three of the four A-side and C-side Concerns name the same gap: without "An import is not a declaration" the reader cannot tell a design choice from an oversight. aiml's, plt's and web's Concerns on A say it in these words. web's fix is to move the reason into "the section text near it". That puts the reason in a second place and leaves the sentence alone when it is quoted, as in the decision file and `blink explain`. B costs six words and keeps the reason with the rule.
>
> I do not move to C. min's own Concern holds: C drops the statement that a plain importer gets no W1010, and sys says the same. A reader would have to infer the rule. The cost of that is higher than the cost of one sentence.
>
> I accept A as second choice if B loses, on one condition: the spec must keep "An import is not a declaration" in the §10.6 text near the sentence, as web's Concern asks.

- **AI/ML: moves from A to B.**

> My own concern in Phase C named the gap in A: it gives the rule but not the reason. plt and web wrote the same concern. The only way to close it in the sentence itself is "An import is not a declaration." That is six words. It costs little, and it gives a model one rule it can reuse: a declaration is a binder an author writes, and an import is not one. Without it, a model may treat the missing importer warning as an oversight and add it back.
>
> B also keeps the statement that a plain importer gets no W1010 and the pointer to the use-site note. C drops both, so I do not move to C.
>
> I accept A as second choice. I do not accept C.

- **Minimalism: moves from C to B.**

> C fails on its own test. The old 07:2846 sentence said the importer is covered. A replacement that only implies the opposite ("An import is not a declaration") leaves the rule for a plain importer to inference. sys, plt and aiml each name this gap: C drops the statement that a plain importer gets no W1010. A drops the reason, and three seats name that gap too (aiml, plt, web). B is the only option that has both, and it costs one sentence more than A.
>
> I do not move to A. A spec that states a rule without its reason invites the next editor to "fix" the omission by adding the warning back; the six-word reason prevents that. This is subtraction of a future change, not an addition of surface.

##### Phase D2 — Silent vote on Q3

All six seats voted B. The reasoning and the concern of each seat follow.

- **Systems: B.**
  - Reasoning: Name resolution is compile-time and a shadow has no codegen effect, so the only question is what the text tells a reader. B states the importer rule, the reason ("An import is not a declaration"), the pointer to the use-site note, and the alias case in one place. The extra words cost nothing at runtime and nothing in the term count: "import alias" is the §10.5 term. A states the same rule without the reason; its own voters named that gap.
  - Concern: "its uses get the note below" is true only while 07:2903 point 2 holds on every diagnostic path, so a use-site diagnostic that omits the note makes the spec text false.
- **Web/Scripting: B.**
  - Reasoning: A reader who finds "gets no W1010" with no cause asks on Stack Overflow why the importer is not warned, or adds the warning back as a "fix". "An import is not a declaration." answers that in six words, inside the sentence itself, where `blink explain` and the decision file quote it. B keeps the plain-importer rule and the use-site pointer that C drops, and it does not call an alias a declaration, so it does not conflict with 07:2848. All six D1 replies hold or accept B's wording unchanged.
  - Concern: "its uses get the note below" is true only while every use-site diagnostic carries the 07:2903 point 2 note; if one path omits it, the sentence is false and the importer gets no signal.
- **PLT: B.**
  - Reasoning: B states the rule and its reason, and it keeps the alias a binding, not a declaration ("An import is not a declaration" matches 07:2848, "declarations or imports"). The reason makes the importer's silence a stated design choice, which closes the gap in A that I named in Phase C. C leaves the plain-importer case to inference. The rule and the sentence do not change soundness; resolution stays per module, so this is a question of what the spec text makes clear.
  - Concern: "its uses get the note below" is true only while 07:2903 point 2 holds on every diagnostic path; a path that omits the note makes the spec sentence false.
- **DevOps: B.**
  - Reasoning: The 07:2846 sentence is the text a user finds when they ask "does the importer get a warning?", and `blink explain` quotes it alone. B answers that question and gives the reason ("An import is not a declaration") in the same place, so the reader cannot take the silence for an oversight. B names the alias rule with the same noun as §10.5 *Import Aliases*, so the diagnostic text and the spec text use one term. Six seats now hold or accept B, and A leaves the reason in a second place.
  - Concern: "its uses get the note below" is false for any use-site diagnostic that omits the 07:2903 point 2 note, so the compiler must emit the note on every diagnostic path, with a test for each, or the sentence misleads.
- **AI/ML: B.**
  - Reasoning: B states the rule (no W1010 for a plain importer), the reason ("An import is not a declaration"), the use-site pointer, and the alias case. A model that reads only the spec learns one reusable rule: a declaration is a binder an author writes, and an import is not one. Without the reason, a model may read the missing importer warning as an oversight and add it back. B does not call an alias a declaration, so it does not conflict with 07:2848.
  - Concern: "its uses get the note below" is true only while 07:2903 point 2 holds for every diagnostic path, and a model will trust the sentence without checking.
- **Minimalism: B.**
  - Reasoning: The sentence replaces a longer one that said the importer is covered. The replacement must answer "does the importer warn?" in the sentence itself, and it must give the reason, so the next editor does not add the warning back. B does both and adds no new category, because it says an import is not a declaration and never calls an alias a declaration. C leaves the plain-importer rule to inference; A drops the reason. B costs one short sentence and prevents a later change, which is the cheaper side.
  - Concern: "its uses get the note below" is true only while 07:2903 point 2 holds on every diagnostic path, so a use-site diagnostic that omits the note makes the sentence false.

Result: B 6-0.

### AI-First Review

| Criterion | Result |
|---|---|
| Learnability: one rule a model can reuse | Pass. A declaration is a binder an author writes; an import is not one. |
| Consistency with §10.5, §10.6 and the duplicate rules | Pass. No new category; an alias stays a binding. |
| Generability: the alias help is copyable | Pass. One concrete line, `import geo.sim.{Error as SimError}`. |
| Predictability of diagnostics | Pass. One W1010 per cause: the declaration, or the alias. |
| Debuggability | Pass, with a note. The importer is silent until a diagnostic involves the name. The use-site note then tells it. |

AI-First review: 5/5 pass.

Debuggability note: the sentence "its uses get the note below" is true only while the use-site note holds on every
diagnostic path. The help line of a warning in a dependency file stays wrong for the app author until the
dependency-warning ticket lands.

### Final Spec

§10.6 *Shadowing Rules*:

> The rule covers every declaration that puts a name in the type namespace: `type` (struct or enum), type alias, `trait`, and `effect`. An import is not a declaration. A module that imports such a name gets no W1010; its uses get the note below. An import alias that is a compiler-known name gets W1010 at the alias (§10.5). Local bindings (`let`) live in the value namespace and are not type declarations.

Example:

```blink
// geo/sim.bl
pub type Handler {               // warning[W1010]: the declaration
    n: Int
}

pub type Error {
    code: Int
}

// main.bl
import geo.sim.{Handler, Error as Option}   // warning[W1010] at `Option` only

fn main() {
    let h = Handler { n: 1 }
    io.println("{h.n}")
}
```

```
warning[W1010]: name shadows compiler-known type
 --> main.bl:1:35
  |
1 | import geo.sim.{Handler, Error as Option}
  |                                   ^^^^^^ this alias shadows compiler-known type `Option[T]` (blink.core)
  |
  = help: choose another alias: import geo.sim.{Error as SimError}
```

Other edits: §10.5 *Import Aliases* names the alias W1010; the diagnostics list point 1 names the alias help; the
catalog row for W1010 gains the alias form; `llms-full.md` gains one sentence. DECISIONS.md gets a new row; its row
*Selective import and module-level declaration of one name* is not edited, and its parenthetical is superseded.

### Open Points

- Gen1 gives no W1010 at an import alias (p3). The spec leads the compiler. A compiler change is needed.
- Gen1 prints a W1010 from a dependency's file, with a help line that tells the app author to edit a file they do not
  own (p6). A separate ticket covers which diagnostics from a dependency's files print, for every warning (Q2).
- The use-site note rule says the note "repeats the `help:` line from (1)". For a shadow that an alias binds, the help
  line to repeat is not stated. The panel did not ballot this point.
- "its uses get the note below" is true only while the use-site note is emitted on every diagnostic path. Each path
  needs a test.
- The alias help hard-codes the example alias `SimError`. A user may read it as a naming rule (min, Phase C, Q4).
- Under Q4 A, a user who wants the builtin under its own name gets no pointer to `import blink.core.{Option as
  CoreOption}` from the alias warning.
