[< All Decisions](../DECISIONS.md)

# The Root Package — Design Rationale

§2.14 and the Error Catalog rows for E0315 (`MissingField`) and E0525 (`NoSuchField`) offer a second repair that edits
the declaration ("or add the field to `T`", "or give `y` a default in `T`") only when `T` is declared in "the package
being compiled". The spec never defined that phrase. §10.5 *Project root discovery* defines a package root by the
nearest `blink.toml`, but nothing said whether a path dependency counts. The spec has no workspace concept, and §8.9.1
says a package has one identity however it is reached. The compiler already gave the help only for a type in the
package of the nearest `blink.toml`: with a path dependency `geo`, `Point { x: 1, z: 2 }` (a type in `geo`) got only
"did you mean `y`?", and `Local { a: 1, c: 2 }` (a type in the app) also got "or add the field to `Local`".

## Summary

- **Q1**: the root package only (6-0).
- **Q2**: the spec adds no line for a type outside the root package (5-1, DevOps dissent).
- **Q3**: replace "the package being compiled" with "root package", defined in §10.5 (6-0).
- **Q4**: no §3.1 pointer; the gate lives in §10.5 only (5-1, PLT dissent).

## Reading gaps

The moderator recorded these gaps in how the panel read the record:

- Phase A: only Minimalism ran the probe. Systems, PLT, Web/Scripting, AI/ML and DevOps relied on the probe text in the
  brief. Web/Scripting did not check the brief's facts against the repo. DevOps's Phase A file is about 600 words (the
  limit was 500).
- Phase B: DevOps read the first part of Minimalism's Phase A file only (it was cut off), and did not list the digest.
  Minimalism read the Systems, PLT, Web/Scripting and AI/ML Phase A files in part (the rule, path-dependency and
  non-root sections).
- Phase B, corrected from the agents' own reports: PLT read only its own Phase A file and the digest in full, and the
  openings of the DevOps and Minimalism files; it did not open the Systems, Web/Scripting or AI/ML files, so its header
  that lists all six is wrong. Systems read only its own file and the DevOps file in full, so its header that lists all
  six is wrong. DevOps's Phase B reply is about 410 words (the limit was 300).
- Phase C: all six seats report that they read every listed file.

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated
in independent-proposal → debate → vote rounds.

#### Phase A — Independent proposals

- **Systems (sys-1):** "**Rule.** "The package being compiled" is the package whose `blink.toml` is the nearest one above the file given to `blink check`, `build`, `test` or the LSP (07 *Project root discovery*). A module counts if it belongs to that package. This includes `tests/`, `examples/` and `bench/`, which are peers of `src/`. A path dependency, a git dependency and `std` do not count. This is what `tc_decl_in_root_package` does today, so the ticket becomes a spec text fix, not a code change."
  - "**Why path deps do not count.** §8.9.1 says a package has one identity however it is reached. A path dep is therefore the same kind of package as a git dep. Whether the user can edit it is a fact about the file system. The compiler cannot see it and must not guess. Rule 1 of §3.1 asks for a repair that exists for the person who reads the message. For a path dep we cannot know that. We know it for the root package, because the user ran the tool there. Silence is the safe default."
  - "**Workspaces.** The spec has no workspace. Each member has its own `blink.toml` and is its own root when the user runs the tool inside it. A member that another member reaches as a dependency is a dependency. So no new concept."
  - "**CLI and LSP.** The same rule. Both start from one root package, so the set of packages that count is identical. The LSP may add a code action "add field to `Point`" on a dependency type as a separate editor feature (03c:653 already lets a tool search more widely). This must not change the text of the diagnostic."
  - "**Other helps that say "package".** ... Any new help that edits a declaration uses the root-package definition. Add one line to §3.1: edit-help is root-package-gated."
  - "**Rejected alternative.** "Path deps count" needs a new fact (editable), splits §8.9.1 identity, and makes the same code print different help depending on how a dep was declared."

- **Web/Scripting (web-1):** "**Rule.** "The package being compiled" means the root package: the package whose `blink.toml` is the nearest one above the file that `blink check`, `build`, `test` or the LSP started from. A module counts if it shares that package root (this includes `tests/`, `examples/`, `bench/`, which §07 already makes peers of `src/`). Every dependency does not count: path, git, std. The spec does not add a workspace concept."
  - "A path dep must not count. `path = "../geo"` can point at a checkout the user does not own, or at a vendored copy. §8.9.1 says a package has one identity however it is reached, so the compiler cannot use "reached by path" as a signal to guess editability. Writing "edit the path dep" would also break when the same package is later switched to a git or registry dep, and the diagnostic would change without any code change. A help line must not depend on how a dependency is spelled in `blink.toml`."
  - "The `note:` is new and optional. It costs one line and answers "why is there no 'add the field' line?" before the user asks Stack Overflow. It states a fact (the declaring package), not a repair, so §3.1 rule 1 is not touched. I ask the panel to take it as a separate sub-vote. If it loses, web-1 stands without it."
  - "**Where it goes in the spec.** One sentence in §07 *Project root discovery*: "The *root package* is the package of the source file that a command or the language server starts from." Then 02_syntax.md:1462 and ERROR_CATALOG E0315/E0525 say "declared in the root package" and link there. Delete the unexplained phrase "the package being compiled"."

- **PLT (plt-1):** "**Rule.** Define one term in 07 *Project root discovery*: the **root package** is the package whose `blink.toml` is the nearest ancestor of the file given to the tool (`check`, `build`, `test`, LSP session). A type is *declared in the root package* when its declaration lies in a module whose package is the root package. "The package being compiled" in 02 §2.14, E0315 and E0525 becomes "the root package" with a pointer to that definition."
  - "**Why this is the sound reading.** The help claims "an edit to the declaration repairs this error" (§3.1 rule 1). That claim is a property of what the tool may rewrite, not of how the code reached the compiler. §8.9.1 says a package has one identity however it is accessed. So the answer cannot depend on `path =` versus `git =`. ... A path dependency is a separate package with its own manifest and its own API contract: adding a field to `geo.Point` changes every other consumer of `geo`, so "or add the field" is not a local repair even when the user can edit the file."
  - "**Non-root type.** Show only the repairs that live at the use site: `help: did you mean y?`. Do not add "the field is declared in `geo`" as a help; a plain `note: Point is declared in package geo` is allowed but optional (a note states a fact, it prescribes nothing)."
  - "**Tradeoffs.** A user who edits both packages loses the declaration help for the dependency. That is a missing help, not a wrong one, and silence is permitted by §3.1 rule 1. A later opt-in (a manifest flag naming editable packages) is additive and not needed now (YAGNI)."

- **DevOps (devops-1, recommended; devops-2, fallback):** "**Definition.** For declaration-editing help, T counts as declared in the package being compiled when T's package is the root package or a package reached through `path = "..."` dependencies (directly or transitively). Git dependencies, registry dependencies and `std` do not count. Their sources live in a fetch cache or in the toolchain, and an edit there is lost on the next fetch or upgrade."
  - "**Why path deps count.** §8.9.1 says path dependencies are "for local development". The user who writes `path = "../geo"` owns that directory, and editing `geo/src/lib.bl` is exactly the repair. Gating on the root package alone gives silence where the repair exists. That breaks rule 1 in the other direction: the help is missing and the user must search for it."
  - "`= help: or add the field to `Point` (geo/src/lib.bl:3)` — The second line names the declaration file, relative to the root. ... For a git/registry/std type, show only the first help."
  - "**Spec placement.** Define "local package" once in 07_trust_modules_metadata.md next to *Project root discovery* (:2316) ... Rename the phrase everywhere so that one word means one thing."
  - "**devops-2 (fallback): keep root-package-only. Never wrong, but it hides a correct repair for local multi-package layouts. I accept it only for zero new vocabulary.**"

- **AI/ML (aiml-1):** "**Rule.** The package being compiled is the package of the nearest `blink.toml` above the file that the command or the language server started from (§8.9 *Project root discovery*). Its `src/`, `tests/`, `examples/` and `bench/` all belong to it. Every other package is foreign: path dependency, git dependency, std. Foreign packages get no declaration-editing help."
  - "A help line that says "or add the field to `Point`" sends the agent into `../geo/src/geo.bl`. That is a second package, often with its own users and its own version. The agent does it without asking, and the edit is wrong more often than right."
  - "The spec states one rule that is easy to check: "same `blink.toml` as the root". A model can learn this from the spec alone. A path-dep rule needs a second test, "can the user edit this?". The compiler cannot answer that."
  - "Do not add a note such as "`Point` is declared in package `geo`". It is correct, but an agent reads it as a task. If devops wants the origin shown, it goes on the declaration span as a secondary label, not in a `help:` line."
  - "**Where the definition goes.** One sentence in §8.9 (07 *Project root discovery*): "The package being compiled is the package that the root `blink.toml` defines." Then 02_syntax.md:1462, ERROR_CATALOG E0315 and E0525 link to it, instead of each carrying its own words."

- **Minimalism (min-1, recommended; min-2, fallback):** "**Rule.** "The package being compiled" is the *root package*: the package whose `blink.toml` is the nearest ancestor of the file the tool started from (07 *Project root discovery*). A type counts if its declaration is in a module of that package. This includes `src/`, `tests/`, `examples/` and `bench/`, which 07 already makes peers."
  - "Path dependency: does not count. Git dependency: does not count. std: does not count. Workspace member: Blink has no workspaces, so there is nothing to decide. A sibling package is a path dependency of the root package, or it is not reachable."
  - "**Why no path-dep exception.** §3.1 rule 1: a help that cannot be followed is worse than silence. A path dep might be editable, but the compiler cannot know that. The path may point into a vendored directory, a read-only mount, or a checkout that belongs to another team. §8.9.1 says a package has one identity however it is reached. If a path dep counted, `geo` would get the help when `app` builds it, and not when `geo` is the root. That breaks the identity invariant."
  - "**Non-root type.** Show only the repairs the user can make at the use site, as now ... No second line and no note such as "declared in a dependency". A note is more surface for little gain."
  - "**Where it goes.** One sentence in 07 *Project root discovery*: "The *root package* is the package of the nearest `blink.toml`. A help that edits a declaration is offered only for a declaration in the root package." 02 §2.14, E0315 and E0525 keep their words and gain a link to that sentence."
  - "**min-2 (fallback, not preferred): path deps count.** Only if the panel wants it. Needs a "path dep" flag on package identity, breaks the identity invariant above, and gives the CLI help the LSP cannot always match. I oppose it."

#### Phase B — Debate highlights

The moderator's digest listed two options: Option 1, the root package only (primary for Systems, Web/Scripting, PLT,
AI/ML and Minimalism); Option 2, the root package plus path dependencies, direct and transitive (primary for DevOps).
It flagged five variations: V1 a line for a non-root type, V2 the term, V3 where the gate is stated, V4 other uses of
"package", V5 an LSP code action. One round ran.

- **Systems:** "**Option 1 (root only): support.** **Option 2 (root plus path deps): oppose, but keep it on the ballot.** It is a real alternative with a real precedent (cargo, Go `replace`, TS references all split by editability). It should lose on the merits, not be dropped."
  - "Devops concedes this ("a read-only vendored path dep still gets the help ... YAGNI"). That concession is the exact case rule 1 of §3.1 forbids: a `help:` that cannot be followed."
  - "**V1: no note, no path in the help.** I hold my A position. A related location on the declaration span is a tool choice. I do not oppose that, and it needs no spec text."
  - "**V2: keep the phrase and define it** (low stakes). "Root package" is also fine. I do not want "local package", which implies more than the rule tests."
  - "**V3: agree.** ... I withdraw my §3.1 line if min's sentence in 07 covers it."
  - "**V5: concede to min and aiml.** I withdraw my allowance for a code action wording. The spec should say nothing about it."
  - STATUS: ready to vote
- **Web/Scripting:** "**Option 1: support.** Five of six seats reach it from different seats. A JS/Python dev can say it in one sentence: "the package you ran the tool in"."
  - "**Option 2: oppose, but I do not ask to remove it.** devops-1 is right that the repair exists for a user who owns `../geo`. The rule cannot know that."
  - "**V1 (note for a non-root type): I concede.** Four seats oppose it. aiml's point that an agent reads a note as a task is fair. I withdraw my "separate sub-vote". The spec says nothing about a note."
  - "**V2 (term): "root package".** A defined term beats a phrase that sounds like it needs a definition. ... I oppose devops's "local package": it implies "editable", which we cannot test."
  - STATUS: ready to vote
- **PLT:** "**Why not Option 2.** The help asserts "an edit to this declaration repairs the error". For a path dependency the compiler cannot decide that. The path may be a vendored copy, a read-only mount or another team's checkout, and the manifest does not say. ... Option 2 cannot be narrowed later without breaking users; Option 1 can be widened."
  - "**V1 (line for a non-root type).** I concede my optional note. aiml's point holds: the spec should fix no extra line."
  - "**V3.** Definition in 07 next to *Project root discovery*. I would add the gating sentence there (min) and a one-line reference from §3.1 rule 1 (sys). One definition, two pointers."
  - STATUS: ready to vote
- **DevOps:** "**Options.** I keep Option 2 on the ballot, but I move toward Option 1 on one condition (V1). ... In a monorepo the user who works in `app/` and edits `geo/` loses a help they would use. That is a real cost, a missing help and not a wrong one, so §3.1 rule 1 allows it."
  - "**V1 (non-root line).** This decides my vote. Under Option 1 the user of a path dep sees one help where `Local` shows two, with no explanation. I support a `note:` that states the declaring package (web, plt). It states a fact and prescribes nothing. ... I accept aiml's secondary label on the declaration span as an equal alternative. I oppose "no origin at all" (min, sys). A silent gap is a bug report."
  - "**V3.** Agree: definition in 07 next to *Project root discovery*. I do not want a §3.1 line from sys; the rule belongs with the help, not the principle."
  - STATUS: ready to vote
- **AI/ML:** "**Option 1 (root package only): support.** Option 2 (add path deps): oppose. ... The test also gives a wrong answer in three cases: a vendored path dep, a read-only mount, and a dep that later moves from `path` to `git`. Then the same code gets different help after a manifest edit."
  - "**V1 (note for a non-root type): oppose.** ... every added line costs tokens in each agent loop, and the note invites an agent to "fix" the dependency. ... I would accept a secondary span on the declaration, which is a location, not text."
  - "**V2 (term): keep "the package being compiled", and define it.** I yield to "root package" if the panel prefers it."
  - STATUS: ready to vote
- **Minimalism:** "**Option 2 (path deps count): oppose, and I withdraw min-2.** devops has the strongest case: the help is missing where the repair exists. But the facts do not support it: ..."
  - "**V2 (term): I change my Phase A position.** Rename to "the root package" (web, plt). The old phrase caused this ticket. Defining a phrase that is wrong on its face is more words than replacing it."
  - "**V3 (placement): 07 next to *Project root discovery*.** I oppose sys's extra §3.1 line. §3.1 rule 1 already covers the principle, and a second statement can drift from the first."
  - "**V4: leave the other "package" uses alone.** I disagree with plt on forcing one meaning everywhere. The other uses compare two packages and already mean the `blink.toml` package."
  - "**V5: no widening, and no spec text about code actions.** An LSP code action on a dependency type is an editor feature outside this decision."
  - STATUS: ready to vote

All six sent "ready to vote".

#### Phase C — Final vote

- **Q1: Which packages count** (6-0 for A, the root package only; B was the root package plus path dependencies)
  - **Systems:** A — "The rule is one package-id compare on an error path. It does not depend on file permissions, git state or the editor, so a build gives the same help on every machine. Option 2 needs a graph walk with a path-only transitive rule, and it still prints a help the user cannot follow for a vendored or read-only path dep. A rule that says "root package" can widen later by manifest flag. A rule that says "path deps" cannot narrow without breaking users." Concern: "A user who edits a path dep from the app root loses one help line, and the spec gives no way to opt in until a later manifest flag exists."
  - **Web/Scripting:** A — "A JS/Python dev reads "the package being compiled" as "the thing I ran the command in", and Option 1 says exactly that in one sentence. Option 2 makes the help change when a dependency moves from `path =` to `git =` with no code change, and the compiler cannot know if a path dep is editable. A user who edits `geo/` can run the tool there and get the help." Concern: "A user who works on two path-linked packages from one editor window gets no edit help on the second one until they open it as root."
  - **PLT:** A — "The help claims that an edit to the declaration repairs the error (§3.1 rule 1). The compiler can know this only for the package the user ran the tool in. A path dependency says where the source is, not who may edit it, and §8.9.1 says that how a package is reached must not change what it is. Adding a field to `geo.Point` also changes the contract for every other consumer of `geo`, so the edit is not local even when the file is writable. Option A can be widened later by an opt-in manifest flag. Option B cannot be narrowed later without breaking users." Concern: "A user who edits a path dependency from the app root loses a help line that would have been correct for them."
  - **DevOps:** A — "The compiler cannot tell an editable path dependency from a vendored or read-only one. The manifest does not say. Web's point also holds: under Option 2 the same code would print different help after `path =` becomes `git =`. Option 1 can widen later with an opt-in manifest flag. Option 2 cannot narrow later without breaking users." Concern: "A user who edits `app/` and `geo/` together from `app/` loses the "add the field" help for `geo` types, with no sign of why."
  - **AI/ML:** A — "A model can learn "same `blink.toml` as the root" from the spec alone and apply it with one compare. Option 2 needs a second test, "reached by `path =`", that does not tell the model whether the user can edit the files. It also makes the help change when a dependency moves from `path` to `git`. The `geo/src/lib.bl:3` text in devops-1 would send an agent into a file outside its root." Concern: "A user who works in a monorepo and edits `geo` from `app/` gets no "add the field" help, and an agent may not look for that repair itself."
  - **Minimalism:** A — "Option 1 adds one sentence and matches `tc_decl_in_root_package`, so the compiler needs no change. Option 2 adds a path-graph walk and a rule about how to print a path outside the root. It also guesses editability, and a path dependency can be a vendored or read-only copy. A rule that is too narrow can be widened later, for example by a manifest flag; a rule that is too wide cannot be narrowed without breaking users." Concern: "A user who edits a path dependency from the app's root loses one help line and must run the tool in the dependency's directory to get it."

- **Q2: A line for a type outside the counted packages** (5-1, DevOps dissent; A: the spec adds no line, B: a fixed `= note:` that states the declaring package)
  - **Systems:** A — "A fixed `note:` adds bytes to every such diagnostic and costs tokens in each agent loop. The tool already prints the type name and the span. A related location on the declaration is a tool choice and needs no spec text, so the spec states only that the edit help is absent." Concern: "A user sees one help where a root-package type shows two, with no explanation, and may file it as a bug."
  - **Web/Scripting:** A — "I withdrew my own note in B1, because four seats oppose it and aiml is right that an agent reads a note as a task. The spec only needs to say the edit help is absent. A tool may show the declaration site as a secondary label without spec text." Concern: "A user sees one help where a local type shows two, with no explanation, and may file a bug about the missing line."
  - **PLT:** A — "The help is absent by rule. The spec need not prescribe an extra line, because a note states a fact the user can already read from the type name and the declaration span. A fixed note text is one more string for CLI and LSP to keep identical, and it adds nothing to soundness. I withdraw my "allowed but optional" note from Phase A. Tools may show the declaring package as a related location without spec text." Concern: "A user sees one help where a root type shows two and gets no stated reason for the difference."
  - **AI/ML:** A — "Each extra line costs tokens in every agent loop, and an agent can read a `note:` as a task to fix the dependency. A fixed note makes two diagnostic shapes for one error that a model must learn. A tool may still show the declaration as a secondary label, because a location is not text that prescribes a repair." Concern: "A user who sees one help where a local type shows two gets no reason in the output and may file a bug."
  - **Minimalism:** A — "The spec should state only that the edit help is absent. A fixed `note:` is a new line in a common diagnostic, and it adds surface that every tool and every agent loop must carry. A tool may show the declaration site as a related location without spec text, so no mandate is needed." Concern: "A user sees one help where a local type shows two, with no explanation, and may file a bug about the missing line."
  - **DevOps:** *(dissent)* B — "Under Option 1 a `Point` error shows one help where a `Local` error shows two, and nothing says why. A silent gap becomes a bug report. A fixed `= note:` that states the declaring package is a fact, not a repair, so §3.1 rule 1 does not apply to it. `= note:` already carries package facts in 06_tooling.md:693. It also gives the CLI and the LSP one fixed text to render and test. A secondary label on the declaration span would serve equally well, but option A leaves the gap with no spec text at all." Concern: "If A wins, each tool will choose its own origin hint, and the CLI and LSP output will drift apart."

- **Q3: The term in 02 §2.14, E0315 and E0525** (6-0 for A, replace with "root package", defined in 07; B was keep "the package being compiled" and define it)
  - **Systems:** A — "I said in B1 that this is low stakes, and it is. "The package being compiled" is wrong in a build sense: when `app` builds, the compiler also compiles `geo`. "Root package" names one thing, matches the 07 definition, and removes the phrase that caused this ticket. I keep my objection to "local package", which implies an editability test we do not run." Concern: "If the term "root package" later gets a second meaning (for example a workspace root), the 02 and catalog text will need a second edit."
  - **Web/Scripting:** A — "The undefined phrase caused this ticket. A reader of 02 or the error catalog should meet a term that is defined in one place, so replace it. "Root package" is short and says what the rule tests. Nobody on the panel wants "local package", which implies "editable"." Concern: ""Root package" may be read as the root of a workspace, and Blink has no workspace."
  - **PLT:** A — "An undefined phrase caused this ticket. A defined term that is used at each use site is better than keeping the phrase in 02 and defining it elsewhere. "Root package" is one name for one thing, defined once in 07 next to *Project root discovery*. Readers of 02 then reach a definition and not a guess." Concern: ""Root package" can be read as "root of a workspace", and Blink has no workspace, so 07 must state that it means the package of the nearest `blink.toml`."
  - **DevOps:** A — "An undefined phrase caused this ticket. A reader of 02 or the error catalog should meet a term that is defined, and "root package" links straight to the 07 definition. One word then means one thing in the diagnostic docs and in 07. I withdraw "local package", which implies the user can edit the package." Concern: "Messages and tests that quote "the package being compiled" must change in the same commit, or the catalog and the compiler will disagree."
  - **AI/ML:** A — "I said in B1 that either term is fine. One defined word at the place of use is easier for a model to match to the definition than a phrase that reads as plain English and is not. The phrase "the package being compiled" caused this ticket, and a reader of 02 who does not follow a link gets the wrong meaning." Concern: ""Root package" must be used the same way everywhere, and a later edit that goes back to the old phrase brings the gap back."
  - **Minimalism:** A — "The phrase "the package being compiled" caused this ticket. Replacing it with a defined term costs fewer words than keeping it and defining it elsewhere. "Root package" means exactly what the rule tests and does not imply editability." Concern: "The three edits must land together with the 07 definition, or a reader of 02 meets an undefined term."

- **Q4: A pointer from §3.1 rule 1** (5-1, PLT dissent; A: a one-line reference to the 07 definition, B: no §3.1 line, the gate lives in 07 only)
  - **Systems:** B — "I withdrew my §3.1 line in B1 on the condition that the gating sentence is in 07. Two statements of one rule can drift. §3.1 rule 1 already states the principle, and 07 states the gate beside the definition." Concern: "A reader of §3.1 alone has no link to the gate, so a future edit help may skip the root-package test."
  - **Web/Scripting:** B — "The gating sentence in 07 is enough, and a second statement in §3.1 can drift from the first. Rule 1 already states the principle. Readers who reach the help through E0315 or E0525 find the link there." Concern: "A reader of §3.1 alone does not learn that edit help is gated by root package, and a future help author may miss it."
  - **DevOps:** B — "The gating rule belongs with the help it gates, in 07 and the catalog entries. A second statement in §3.1 can drift from the first. §3.1 rule 1 already states the principle, and the 07 sentence is the one place that says what "root package" means for edit helps." Concern: "A future edit help may cite only §3.1 and miss the 07 definition, so it would gate on a different package notion."
  - **AI/ML:** B — "The gating sentence in 07 and the links from 02, E0315 and E0525 are enough. A second statement in §3.1 can drift from the first, and the model gets two places to check. §3.1 rule 1 already states the principle." Concern: "A reader of §3.1 alone does not learn which package the principle covers, so a future edit help may not cite the 07 definition."
  - **Minimalism:** B — "§3.1 rule 1 already states the principle. A second statement of the gate in §3.1 can drift from the first in 07. Three of the six seats call the pointer optional, and sys withdrew it if the 07 sentence covers it." Concern: "A future author of an edit help may read only §3.1 and miss the root-package gate in 07."
  - **PLT:** *(dissent)* A — "A pointer is a reference to the one definition, not a second statement of the rule, so it cannot drift from the first. §3.1 rule 1 is where a reader looks for the principle, and the principle needs the definition of "the package" to be checkable. The cost is one line. If the panel puts the gating sentence in 07 only, this vote does not block it." Concern: "If the pointer restates the rule and does not only link to 07, the two texts can drift."

#### Phase D — Round 2

Did not run. No question was closer than 5-1.

#### Owner approval

The owner approved the tally. No tiebreak was needed. The approval dashboard's ruling and the panel files agree on every question.

### Final Spec

```blink
// app/blink.toml: geo = { path = "../geo" }
import geo.{Point}

type Local { a: Int, b: Int }

fn main() {
    let p = Point { x: 1, z: 2 }     // NoSuchField: help "did you mean `y`?" only
    let q = Local { a: 1, c: 2 }     // NoSuchField: also "or add the field to `Local`"
}
```

- The root package is the package of the nearest `blink.toml` above the file the tool started from, with its `src/`, `tests/`, `examples/` and `bench/`. Path, git and std dependencies do not count (Q1).
- Blink has no workspace concept. A package that the user opens as the tool's start is its own root package; from another package it is a dependency.
- §10.5 *Project root discovery* defines the term and states the gate: a help that edits a declaration is offered only for a declaration in the root package (Q3, Q4).
- §2.14, E0315 and E0525 say "root package" in place of "the package being compiled" (Q3).
- For a type outside the root package, the spec adds no line. Only the use-site help shows. A tool may show the declaration site as a related location without spec text (Q2).
- The CLI and the LSP print the same diagnostic text. The spec says nothing about an LSP code action on a dependency type.
- E0505 reachability text is unchanged. The orphan rule, E0518 and E1016 keep their text: they already mean the `blink.toml` package.
- Any future help that edits a declaration uses the same definition. "Local package" is rejected: it implies an editability the compiler cannot test.

