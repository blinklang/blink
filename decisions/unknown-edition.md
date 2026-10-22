[< All Decisions](../DECISIONS.md)

# Unknown blink.toml Editions — Design Rationale

### Panel Deliberation

The ticket (verbatim):

> Title: Spec: blink.toml edition newer than the compiler knows, and schema gating by edition
>
> Raised by PLT on the lexer/manifest codes panel. W1001 UnknownManifestSection is a warning so a manifest for a newer
> toolchain still builds (§8.9.7). The spec does not say what happens when [package] edition names an edition the
> compiler does not know, or whether the set of defined sections (and so W1001) depends on the edition. MVCE:
> [package] name = "x" version = "0.1.0" edition = "2099".

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in four phases, with one round in Phase B. Phase D took one question (Q7). Quoted text is each panelist's own words. Each quote is a whole paragraph, a list item, or a line range of the panel record.

The moderator's ballot lists this common ground from the A and B1 files of all six seats: the span is the value token; the check runs for each package in the graph; an omitted `edition` keeps the decided default; a year after the newest known edition never gets lower-edition help and no machine-applicable fix; any other string gets the nearest known edition as help; a TOML integer that names a known edition gets a machine-applicable fix that quotes it, and no other case gets one; `blink fmt` still formats; the LSP reports the error and does not type-check that package; `blink migrate --edition <year>` and `blink editions --edition <year>` give the same code, with the span on the argument. Minimalism ruled out a new manifest field for a minimum toolchain version.

Questions:

- Q1: an `edition` value the toolchain does not know. **ERR:** an error, no fallback edition. **WARN:** a warning; compile under the newest known edition.
- Q2: does the manifest schema depend on the edition. **FIXED:** the section and key set depends on the toolchain only; W1001 stays a warning. **GATED:** `[package]` edition-free, every other section defined per edition; W1001 becomes an error.
- Q3: one code or two. **ONE:** `UnknownEdition`. **TWO:** `UnsupportedEdition` (a year after the newest known edition) and `InvalidEdition` (any other value, including a non-string).
- Q4: edition names strictly increase: "Each new edition is named for a year after the newest existing edition."
- Q5: W1001 and unknown-key diagnostics in a manifest whose edition check fails. **N:** keep them; add a `note:` at the `edition` value for a year after the newest known edition only. **K:** keep them, no note. **S:** suppress them.
- Q6: section admission rule (a section that changes what a package builds to enters the schema only with a new edition).
- Q7: toolchain version in the W1001 message. **V0:** W1001 text unchanged. **V1:** "not defined by blink <version>".
- Q8: the later-year error names this toolchain's version and its known editions.
- Q9: dependency note. **E:** a `note:` with a span on the dependency's entry in the dependent manifest. **EC:** E, plus the chain from the root when the dependency is not direct.
- Q10: the edition errors cannot be made a warning by `[lints]`, `--allow` or `@allow`.

#### Phase A — Independent proposals

All six seats proposed an error with no fallback edition (ERR) and a schema that does not depend on the edition (FIXED). They differed on the number of codes, on what happens to W1001 in the same manifest, and on a rule for future sections.

- **Systems (sys-1):**

  > A fallback to "latest known" gives a binary that compiles clean and acts differently from what the author tested. That is a silent miscompile. A build that stops costs the user one upgrade; a build that runs wrong costs a production incident.

- **Web/Scripting (web-1):**

  > An unknown section is different. It is data the old toolchain does not read, and skipping it is safe enough for a warning. An unknown edition is a statement about the meaning of every source file in the package. Skipping it is not safe.

- **PLT (plt-1):**

  > An error is the only answer that never produces a program whose meaning the author did not choose. It also costs nothing under the decided "infinite compatibility" rule: the fix is always "use a newer blink", never "change your code".

- **DevOps/Tooling (devops-1):**

  > Why two names and not one: §3.1 *Diagnostic Discipline* says diagnostics converge on the repair that the first
  > `help:` names. The repairs differ. `"2099"` is not a typo; the file is correct, the toolchain is old. Suggesting
  > `"2027"` there would prescribe a repair that changes the program's meaning.

- **AI/ML (aiml-1):**

  > A silent fallback is the worst result for an agent: the build is green,
  > and the agent has no signal that the package compiles under rules it did not ask for.

- **Minimalism (min-1):**

  > With min-1, `edition` does the gate job
  > for free: a package that needs edition 2028 features fails cleanly on a pre-2028 compiler, with a message that
  > says "upgrade blink". We do not add `blink-version` / `min-blink` to `[package]`.

Phase B settled four open points: one code or two; what happens to W1001 and unknown-key diagnostics in the same manifest; a rule for future sections; and the path text of the dependency note.

#### Phase B — Debate highlights

One round. Five of six seats ended it ready to vote. PLT's two open asks became Q4 and Q6.

- **DevOps/Tooling (devops-1), the point that moved the code count:**

  > devops-1: "`"2099"` is not a typo; the file is correct, the toolchain is old. Suggesting `"2027"` there would prescribe a repair that changes the program's meaning. ... One name with two help forms makes `blink explain`, the LSP code-action list and CI log greps branch on the message text."

- **AI/ML (round 1), withdrawing lower-edition help:**

  > I withdraw it. For a year after the newest known edition: no machine-applicable
  > fix, and the help never offers a lower edition.

- **Web/Scripting (round 1), withdrawing lower-edition help:**

  > **I withdraw that clause.** For
  > a year newer than the newest known edition, the help says only "install a newer blink". It never offers a lower
  > edition.

- **Minimalism (round 1), withdrawing lower-edition help:**

  > Correct. My A help for `"2099"` said "install a newer blink, or set the edition to one listed by `blink editions`".
  > The second half is a repair that silently changes the program, which §3.1 rule 1 forbids in spirit. I withdraw it.

- **PLT (round 1), the admission rule:**

  > FIXED + "W1001 is a warning" means: an old toolchain **skips** a section it does not know and builds the rest. Skipping is sound only if the skipped section cannot change what gets built. Nothing in the spec says that today.

- **PLT (round 1), reply to web-2 and sys-2:**

  > - web-2: "a change in meaning gets a new key name." A new key name is exactly what an old toolchain does not know. It skips it with W1001 and builds without it. A new name does not close the hole; it is the hole.
  > - sys-2: "a manifest key controls the build, not the meaning of source." The build is the meaning the user runs. `[dependencies]` already decides which code is compiled. A future `[patch]`, `[features]` or `[build]` section would do the same. An old blink that skips `[patch]` links the unpatched library, with one warning line. That is the same silent wrong build that all six seats reject for Q1.

- **PLT (round 1), the rule:**

  > A section or key that changes what a package builds to — which code it compiles, which code it resolves, or which rules check it — enters the schema only together with a new edition. A section or key that does not change that (metadata, tool hints) can enter in any `blink` release.

- **Systems (round 1), withdrawing suppression:**

  > I proposed suppression. I withdraw it. devops-1: "the build already fails, and a section that is a real typo is still worth a line." That is right, and it matches aiml-2's "fix them in one edit".

- **PLT (round 1), withdrawing plt-2:**

  > I withdraw plt-2. No seat supports it, and its cost (a yearly wait for every new section, a fourth edition scope) is real. W1001 stays a warning; no new severity vote.

- **PLT (round 1), moving to two codes:**

  > devops-1 is right, and the reason is formal, not only about help lines.

- **PLT (round 1), the sentence two codes need:**

  > The split is decidable only if a later toolchain can never add an edition at or below a known one. §8.16.5 says "at most one edition per year" but not that edition names strictly increase in release order. The spec needs that sentence: **"Each new edition is named for a year after the newest existing edition."** With it, any unknown year at or below the newest known is provably not an edition, and the split is exact.

After round 1: sys, web, aiml, devops and min were ready to vote; sys, aiml and plt had moved to two codes, and web and min stayed on one code until the Phase C vote.

#### Phase C — Silent vote

| Question | Result |
|---|---|
| Q1 unknown edition | **ERR 6-0** |
| Q2 schema and edition | **FIXED 6-0** |
| Q3 codes | **TWO 6-0** (web, min, devops moved from ONE) |
| Q4 edition names strictly increase | **Yes 6-0** |
| Q5 W1001 and unknown-key diagnostics when the edition check fails | **N 5-1** (K: min) |
| Q6 section admission rule | **Yes 6-0** |
| Q7 version in the W1001 message | **V0 6-0** after V0 4-2 in Phase C (V1: sys, web) |
| Q8 later-year error names version and known editions | **Yes 6-0** |
| Q9 dependency note | **EC 5-1** (E: min) |
| Q10 not demotable | **Yes 6-0** |

Each seat's vote, reasoning and concern:

- **Systems:**

  - Q1 unknown edition — **ERR**

    > **Reasoning:** An edition can change stdlib defaults, so the same source can do different things at run time under different editions. A toolchain that does not know the edition cannot apply its rules, and a fallback gives a green build that acts differently from what the author tested. The check is one table lookup per package, with no run-time or codegen cost.
    > **Concern:** A popular library that moves to a new edition in its first week breaks every user on an older `blink`, and users will ask for a fallback flag. The answer must stay no.

  - Q2 schema and edition — **FIXED**

    > **Reasoning:** The root's toolchain reads every manifest in the graph to resolve it, so one binary with one schema is the simple and predictable model. An edition-gated schema means N schemas in one binary and new sections held back for up to a year. With ERR and Q6, FIXED leaves no case where a skipped section changes the binary.
    > **Concern:** If Q6 fails, FIXED lets a meaning-changing section from a newer toolchain be skipped with only a warning, which is a silent miscompile.

  - Q3 one code or two — **TWO**

    > **Reasoning:** The two faults have different owners and different repairs: "the binary is too old" versus "the file is wrong". A CI job or a toolchain manager (the Go `toolchain` model) can match `UnsupportedEdition` alone and fetch a newer `blink`, with no text parsing. One code with fixed sub-messages makes each such tool parse English, which is a hidden cost.
    > **Concern:** If ONE wins, tools will match on message text, and any later change to that text breaks them without warning.

  - Q4 edition names strictly increase — **Yes**

    > **Reasoning:** TWO needs this sentence to be sound. Without it, a toolchain that knows 2026 and 2028 cannot say whether `"2027"` is a future edition or a value that never names one. With it, a year at or below the newest known edition that is not in the table is `InvalidEdition` forever, and only a later year can be `UnsupportedEdition`. It costs nothing, since §8.16.5 already allows at most one edition a year.
    > **Concern:** None from my seat; it only writes down what the cadence rule already implies.

  - Q5 W1001 when the edition check fails — **N**

    > **Reasoning:** I withdrew S in B1. The build already stops, so the extra lines cost nothing, and a real typo in a section must not be hidden. The note at the edition value is a fact tied to a span, and it reuses the E1200/E1052 note mechanism that §8.9.8 has, so it adds no new machinery.
    > **Concern:** The note text could drift into a guess ("this section may be from a newer blink"). It must only state that the manifest names an edition this toolchain does not know.

  - Q6 section admission rule — **Yes**

    > **Reasoning:** This is the Q1 miscompile argument applied to sections. A section that changes what the package builds to must not be skippable by an old toolchain under a known edition, and this rule makes the old toolchain stop on the edition line first. I read "what a package builds to" as the observable behaviour; an optimization-only setting that changes speed or size, not results, can enter in any release.
    > **Concern:** Only review enforces the rule, and someone can ship the first meaning-changing section without its "needs edition N or later" diagnostic. The spec text must tie the two together.

  - Q7 version in the W1001 message — **V1**

    > **Reasoning:** The binary knows its own version, and printing it costs nothing. "not defined by blink 0.57.0" lets a user compare with a teammate's toolchain at once, and it makes no guess about newer toolchains.
    > **Concern:** It changes the wording of a message an earlier panel set, and it can differ from the pending unknown-key diagnostics if that panel keeps them without a version.

  - Q8 later-year error names version and known editions — **Yes**

    > **Reasoning:** The repair for `UnsupportedEdition` is "install a newer toolchain", and the user needs to know which toolchain they have and what it covers to act on that. These are facts in the binary's table, as in Cargo's message.
    > **Concern:** The known-edition list grows over decades; the text should print a range ("2026 to 2035"), not every year.

  - Q9 dependency note — **EC**

    > **Reasoning:** The span on the direct dependent's entry is the right anchor for the LSP. For a transitive dependency, that entry is often in a manifest the user does not own (vendored or git). The chain from the root tells them which of their own entries to pin or replace. It is one line of text, and only for the non-direct case.
    > **Concern:** For deep graphs, the chain line can get long; cap it or shorten the middle if needed.

  - Q10 not demotable — **Yes**

    > **Reasoning:** The edition error is not a lint: it says the toolchain has no rules to build the package with. If `[lints]` or `--allow` could turn it into a warning, the fallback rejected in Q1 would come back through another route, with the same miscompile risk.
    > **Concern:** None from my seat; users will ask for an override, and the help line (upgrade `blink`) is the answer.

- **Web/Scripting:**

  - Q1 unknown edition — **ERR**

    > **Reasoning:** A warning plus a fallback is the npm `engines` story: "EBADENGINE" scrolls past, then a confusing failure or a quiet wrong build somewhere else. An error at the `edition` line with "install a newer blink" is the one message a JS or Python dev acts on at once. Cargo and Go 1.21 both landed here after trying the soft version.
    > **Concern:** A library author bumps the edition with no real need and locks out every user on an older blink. The help line must make the fix obvious, and for a dependency it must offer "pin an older release" too.

  - Q2 schema and edition — **FIXED**

    > **Reasoning:** One rule a dev learns in five seconds: the blink you run decides which sections it knows. No tool web devs use gates manifest keys by a value inside the manifest, and go.mod, the one that does, has the Stack Overflow pile to show for it. It also keeps one completion list in the LSP.
    > **Concern:** Someone later adds a section that changes meaning without an edition, and an old blink skips it with a warning. Q6 is the guard for that.

  - Q3 one code or two — **TWO**

    > **Reasoning:** I change my vote from B1. sys's case decides it for me: a CI job or a toolchain manager can match `UnsupportedEdition` and fetch a newer blink without parsing English. That is the "just works" path, the same as Go's toolchain download. Each name then has one fixed help line, and the names read plainly ("your blink is too old" vs "this value is wrong"). The cost is one more catalog row, which I accept.
    > **Concern:** A later-year typo (`"2062"`) reads as "upgrade blink" and sends a dev to install a toolchain that does not exist. The message must name the newest known edition so the typo is easy to spot.

  - Q4 edition names strictly increase — **Yes**

    > **Reasoning:** Every dev already assumes it: 2027 comes after 2026. TWO needs it to say "a year after the newest known edition is a future edition". Writing it down costs one sentence and removes a corner case nobody wants.
    > **Concern:** None from my seat. It only blocks a naming scheme nobody has proposed.

  - Q5 W1001 when the edition check fails — **N**

    > **Reasoning:** Report every fault in one pass. A dev fixes `blink.toml` once, and a real `[dependecies]` typo must not hide behind "upgrade blink" and come back as a second surprise. The note states a fact (this manifest names an edition this blink does not know), so the reader can tell "probably from a newer blink" from "probably a typo" without extra rules.
    > **Concern:** The note wording drifts into a guess ("this section is from a newer blink"). It must stay "may" and point at the `edition` value.

  - Q6 section admission rule — **Yes**

    > **Reasoning:** Users never see this rule, and it is what makes "W1001 is a warning" safe and not just convenient. Without it, a future section that changes what the code builds to would be skipped by an old blink with a warning. That is the same silent wrong build Q1 rejects. It costs spec authors a check at review and costs users nothing.
    > **Concern:** Review alone enforces it, so a rushed release could add a meaning-changing key as "just a tool hint". The rule's wording must make the test clear.

  - Q7 version in the W1001 message — **V1**

    > **Reasoning:** "Not defined by the spec" sends a dev to read a spec. "Not defined by blink 0.57.0" lets them compare with the blink their teammate or CI runs, which is the first thing they check. It is a fact, not a guess, and it costs a few tokens.
    > **Concern:** The version string makes golden test output churn on each release. The test harness needs to normalize it.

  - Q8 later-year error names version and known editions — **Yes**

    > **Reasoning:** This is the cargo message people praise: "only supports 2015, 2018, and 2021". It answers "how old is my blink, and what does it know?" without a second command. It also makes a later-year typo easy to see.
    > **Concern:** Once there are many editions, "2026 to 2040" is a range, and a reader may take it to mean every year. Q4 makes the range correct only if the spec says the list holds named editions, not every year.

  - Q9 dependency note — **EC**

    > **Reasoning:** The 90% case is a direct dependency, where the chain is one link and the note just points at the line to edit. For a transitive one, "myapp -> acme/auth -> acme/crypto" answers "where did this even come from?" without a `blink tree` command. That is the first question every npm user asks about a deep dependency error.
    > **Concern:** Deep graphs make the chain line long. Show the shortest path only.

  - Q10 not demotable — **Yes**

    > **Reasoning:** A demoted edition error is exactly the WARN fallback that Q1 rejects, coming back through `[lints]`. If `@allow` could silence it, someone would paste that from a Stack Overflow answer to "make the error go away" and ship a wrong build. The fix is always "upgrade blink", and that is cheap.
    > **Concern:** A dev on a locked CI image cannot upgrade and has no escape. The help must also offer the dependency pin, so the fix is something they can actually do.

- **PLT:**

  - Q1 unknown edition — **ERR**

    > **Reasoning:** A package means "this source under `rules(E)`", and a toolchain has `rules(E)` only for editions in its own table. Compiling under another edition substitutes rules the author did not pick, and stdlib defaults can make the binary act differently with a green build. An error is the only answer that never produces a program whose meaning nobody chose.
    > **Concern:** A library that moves to a new edition in its first week breaks every user on an older blink, and some will read that as the toolchain being fragile rather than correct.

  - Q2 schema and edition — **FIXED**

    > **Reasoning:** The edition lives inside the manifest, so at least `[package]` must be read under an edition-free schema, and `[dependencies]` feeds graph-wide resolution that §8.16.1 says editions cannot reach. With Q1 = ERR and Q6 = Yes, a fixed schema plus a W1001 warning is sound: every section an old toolchain can skip is meaning-neutral by construction. GATED would buy nothing more for soundness and costs a yearly wait for every new section.
    > **Concern:** FIXED is sound only together with Q6; if Q6 fails, "W1001 is a warning" goes back to being a hope, not a guarantee.

  - Q3 one code or two — **TWO**

    > **Reasoning:** The two faults are different kinds of judgment. `InvalidEdition` is absolute: the value is wrong for every toolchain, and the file is at fault. `UnsupportedEdition` is relative to this toolchain: the file may be right. One code mixes a property of the file with a property of the (file, toolchain) pair, and a CI policy such as "retry with the newest blink on UnsupportedEdition only" is sound only when the code separates them.
    > **Concern:** The split is exact only if Q4 passes; without it, a year at or below the newest known could in principle be a real edition, and `InvalidEdition` would be a false claim.

  - Q4 edition names strictly increase — **Yes**

    > **Reasoning:** This sentence makes "unknown year at or below the newest known edition" decidably not an edition, so the TWO split, and the nearest-name help in `InvalidEdition`, are exact rather than heuristic. It also matches §8.16.5's cadence and the meaning of an edition as a yearly snapshot, so it costs nothing. Without it, the edition set is not a total order by release, and "newer than this toolchain" has no precise definition.
    > **Concern:** A year with no edition (a skipped year) stays a permanent gap, and a user who types it gets "not an edition" where they might expect "not yet"; the help must list the known editions to make that clear.

  - Q5 W1001 when the edition check fails — **N**

    > **Reasoning:** When the manifest names a later year, the toolchain has evidence that sections it does not know may belong to that edition, so the note states a fact tied to a span, not a guess. In every other case the edition is a typo and says nothing about where a section comes from, so there is no note. Suppression (S) would hide a real typo for one build round.
    > **Concern:** Readers may take the note as a claim that the section IS from a newer blink; the text must say "this manifest names edition N, which this blink does not know", and nothing more.

  - Q6 section admission rule — **Yes**

    > **Reasoning:** Skipping an unknown section is sound only if that section cannot change what gets built; this rule is what makes it true for every future section, at zero toolchain cost today. I read "what a package builds to" as observable behaviour (sys B1 asked): a section that changes only speed or size and preserves the program's result is meaning-neutral and may enter in any release. I agree with min B1 that the first meaning-changing section brings its "needs edition N or later" check with it, in the same change, and that W1001's severity may be voted again then, not now.
    > **Concern:** Review alone enforces it, and "meaning-neutral" will be argued case by case; a borderline section (say, a feature flag that is "only" a default) could slip in as neutral and reopen the silent-wrong-build hole.

  - Q7 version in the W1001 message — **V0**

    > **Reasoning:** I supported V1 in B1, and I change my vote. The pending unknown-key result ruled out a toolchain-version note on its sibling codes, and two sibling manifest diagnostics with different text rules is an inconsistency for no gain in soundness. The W1001 text was settled by an earlier panel, and this ticket's question does not need it changed.
    > **Concern:** If V1 wins and the unknown-key result is approved as it stands, W1001 and its sibling warning will say different things about the same kind of fault, and someone must reconcile them in a chore.

  - Q8 later-year error names version and known editions — **Yes**

    > **Reasoning:** For `UnsupportedEdition` the toolchain's version and its known editions are the exact facts that define the fault (the error is relative to this toolchain), so stating them is stating the cause. It is a fact the binary knows, not a guess, and it lets the user compare with a teammate's blink at once.
    > **Concern:** Tests and golden outputs that capture this message will change with every release; the catalog should fix the message form, not the numbers.

  - Q9 dependency note — **EC**

    > **Reasoning:** The span on the direct dependent's entry is the token the user can edit, which §8.9.8's "every manifest diagnostic points at the token at fault" asks for. The chain in the text costs one line only in the transitive case and answers "why is this package in my build at all", which the single entry does not answer from the root's point of view.
    > **Concern:** A deep or diamond graph has more than one chain; the spec must say which one is shown (for example the first found in resolution order), or two toolchains print different notes for one graph.

  - Q10 not demotable — **Yes**

    > **Reasoning:** This error is not a lint: it says the package has no defined meaning under this toolchain. Allowing `[lints]`, `--allow` or `@allow` to make it a warning would bring back the WARN fallback that Q1 rejects, by a side door. It also keeps the code's meaning stable: an edition error always stops the build.
    > **Concern:** Users who want to "just try" an old toolchain on a new package have no escape hatch, and some will edit the edition down by hand, which is a silent change of meaning that no diagnostic can catch.

- **DevOps/Tooling:**

  - Q1 unknown edition — **ERR**

    > **Reasoning:** Under a fallback, a stdlib default from a newer edition changes and nothing reports it, and the
    > real cause is one warning line lost in the scroll above the type errors that follow. An error gives the one
    > diagnostic that names the true cause and its fix. CI gets a stable non-zero exit status in place of a green build
    > that runs wrong.
    > **Concern:** A team that leaves CI on an old blink image now fails on each dependency that moves to a new edition.
    > The message must name the editions this blink knows, so the fix is plain from the log alone.

  - Q2 schema and edition — **FIXED**

    > **Reasoning:** With one schema per toolchain, the LSP has one completion list and one hover text for `blink.toml`,
    > and it needs no edition context to read a half-typed manifest. Under gating, a correct section name gets a
    > "did you mean" help, and `blink migrate` must rewrite manifests too. FIXED keeps W1001 the same rule under every
    > edition.
    > **Concern:** If Q6 fails, an old toolchain can skip a section that changes the build, with only W1001 to show it.

  - Q3 one code or two — **TWO**

    > **Reasoning:** In B1 I accepted ONE, but plt B1 gives the deciding fact for a tool: `"abc"` is a fault in the file
    > for every toolchain, and `"2099"` is a fault only with this toolchain. A CI policy such as "fail on InvalidEdition,
    > retry on the latest blink on UnsupportedEdition", and the agent's choice of repair, then work from the JSON `code`
    > field with no parse of the message. `blink explain` gives one answer for each name. ONE with fixed messages for each
    > case works, but it makes each tool match on the message text.
    > **Concern:** If ONE wins, a tool will match on the message prose. The catalog row must fix the message for each case
    > and say that it is stable.

  - Q4 edition names strictly increase — **Yes**

    > **Reasoning:** The rule makes the "later year" test exact, so the diagnostic is decidable and never prescribes a
    > repair that is wrong. It is useful under ONE too: the help for each case depends on the same test.
    > **Concern:** None from my seat. It costs nothing until a skipped year comes up, and then it is the correct
    > constraint.

  - Q5 W1001 when the edition check fails — **N**

    > **Reasoning:** When the edition is a later year, the note copies the E1200/E1052 note rule in §8.9.8. It tells the
    > reader which warnings are probably from a newer toolchain and loses none of them. In the other cases the edition is a
    > typo, so a W1001 beside it is a second typo that the user fixes in the same edit, and it needs no note.
    > **Concern:** The note text must state the fact ("this manifest names edition 2099"), not guess that the section is
    > from a newer blink.

  - Q6 section admission rule — **Yes**

    > **Reasoning:** This rule is what makes W1001-as-warning safe: a section that changes the build arrives with an
    > edition, so an old toolchain stops with the edition error and does not build without that section. Every such
    > section then fails with a diagnostic, which is what my seat asks for. The rule also obliges the change that adds the
    > first such section to add its "needs edition N or later" diagnostic.
    > **Concern:** "Changes what a package builds to" is a judgment call for future spec authors, so a section that is not
    > neutral can be classed as metadata.

  - Q7 version in the W1001 message — **V0**

    > **Reasoning:** An earlier panel set the W1001 text, and the pending unknown-keys result ruled out a toolchain-version
    > note on its own codes. If V1 changes W1001 alone, the two manifest warnings are worded in different ways. If the
    > version line is wanted, put it in one rule for all manifest diagnostics in its own ticket.
    > **Concern:** If V1 wins, the unknown-key warning must use the same wording, or users and the LSP see two styles for
    > one kind of fault.

  - Q8 later-year error names version and known editions — **Yes**

    > **Reasoning:** This is the Cargo message that works. The reader sees what they have and what they need with no
    > second command, and a bug report pasted from a CI log is complete.
    > **Concern:** The known-editions list must come from the same built-in table that `blink editions` uses, so the two
    > never disagree.

  - Q9 dependency note — **EC**

    > **Reasoning:** The span on the immediate entry is the token the user can change and the LSP can navigate to. For an
    > indirect dependency, the chain in the note text answers "why is this package in my build at all" with no second tool.
    > It is text in the note that already exists, not one more note.
    > **Concern:** A deep graph gives a long chain. The text should give the shortest path from the root.

  - Q10 not demotable — **Yes**

    > **Reasoning:** If the error can be made a warning, `[lints]` brings back the fallback. It is not a lint: under this
    > toolchain the package has no defined meaning. It also follows the catalog's rule that only warnings can be suppressed,
    > so this states a fact the catalog already gives and adds no exception.
    > **Concern:** None from my seat. A user who tries to demote it gets E0847 `NotAWarningName`, which is the right error.

- **AI/ML:**

  - Q1 unknown edition — **ERR**

    > **Reasoning:** A fallback gives an agent a green build under rules it did not ask for, and it has no signal to act on. An error at the manifest value is the one diagnostic that names the cause, and the rule fits in one sentence of spec. It matches Cargo, the manifest models have seen most.
    > **Concern:** Models trained on Cargo will write `edition = "2021"` often, and the spec examples must show `"2026"` everywhere so the habit gets corrected at the source.

  - Q2 schema and edition — **FIXED**

    > **Reasoning:** GATED adds a fourth edition axis and a "which edition introduced `[x]`" question for every manifest an agent writes. FIXED keeps "the toolchain defines the sections" as the whole rule. With Q6, it is also safe.
    > **Concern:** An agent may read W1001 as noise and ignore it; spec examples should show the warning as worth a look.

  - Q3 one code or two — **TWO**

    > **Reasoning:** An agent reads a code, it does not choose one, so a second code adds no decision point for the writer. The two repairs never overlap ("upgrade blink or ask the human" versus "edit the value"), and a code that maps one-to-one to a repair works from the JSON `code` field with no parse of English. `blink explain <code>` then has one answer.
    > **Concern:** A later-year typo (`"2062"`) gets `UnsupportedEdition`, and an agent may try a toolchain install before it sees the typo.

  - Q4 edition names strictly increase — **Yes**

    > **Reasoning:** It makes the Q3 split exact and lets a model reason about editions as an ordered list from the spec alone. It costs one sentence and constrains nothing the cadence rule did not already imply in practice.
    > **Concern:** None from my seat beyond a future wish for an out-of-order edition, which this sentence correctly forbids.

  - Q5 W1001 when the edition check fails — **N**

    > **Reasoning:** Report every manifest diagnostic in one pass, so an agent that cannot upgrade does not need a second build to find a real typo. The note at the `edition` value states a fact, only in the case where it is true, so it adds context without a guess.
    > **Concern:** An agent may read the note as "every W1001 here is from a newer blink" and miss a real typo next to it.

  - Q6 section admission rule — **Yes**

    > **Reasoning:** A rule in the spec is learnable from the spec; a habit of the spec authors is not. It is what makes W1001-as-warning safe, and it costs users nothing today. Requiring the "needs edition N or later" diagnostic in the same change as the first such section keeps the gap closed.
    > **Concern:** "Changes what a package builds to" needs an example in the text (sys's `[profile]` speed-only case), or readers will disagree on the edge.

  - Q7 version in the W1001 message — **V0**

    > **Reasoning:** The pending unknown-key result ruled out a toolchain-version note on its own diagnostics. Two sibling manifest warnings with different wording rules is a pattern a model learns wrong. The W1001 text belongs to the earlier panel; if the version is wanted, change both siblings together in one later chore.
    > **Concern:** If V1 wins and the unknown-key result is approved as is, W1001 and W1002 differ in form, and that should be reconciled in the same change.

  - Q8 later-year error names version and known editions — **Yes**

    > **Reasoning:** "this blink (0.57.0) knows editions 2026 to 2027" lets an agent decide in one step whether an upgrade fixes it, with no extra `blink editions` call. It is a fact the binary knows, and Cargo prints the same list.
    > **Concern:** With one edition, "2026 to 2026" reads oddly; the text may want a one-edition form.

  - Q9 dependency note — **EC**

    > **Reasoning:** For a transitive dependency, the span lands in a manifest the user does not own; the chain from the root names the direct dependency the user can pin or drop. One line of text, and it shows only when the dependency is not direct, so the common case costs nothing.
    > **Concern:** A long chain makes a wide line; the format should stay one `->`-joined line, not one line per hop.

  - Q10 not demotable — **Yes**

    > **Reasoning:** A demotable edition error is the fallback by a side door, and agents add `@allow`/`[lints]` entries to clear red builds. It is not a lint, so the lint controls must not reach it.
    > **Concern:** The spec must say this in the catalog row, or a model that learned "every warning-class code can be allowed" will try it.

- **Minimalism:**

  - Q1 unknown edition — **ERR**

    > **Reasoning:** An edition is a rule set. A compiler that does not have the rule set can only stop or pretend, and
    > pretending is a silent change of meaning. ERR also makes `edition` the minimum-toolchain gate, so the manifest needs
    > no `blink-version` field. That is one field doing two jobs, which is the subtraction I want.
    > **Concern:** Each new edition locks out older compilers for packages that adopt it, even when they use none of its
    > changes; `blink init` and `blink migrate` write the newest edition, so this happens by default.

  - Q2 schema and edition — **FIXED**

    > **Reasoning:** The edition scope was fixed at three things. GATED adds a fourth, a schema table per edition, and a
    > W1001 re-vote, with no user need on the table. The manifest is tooling input and changes with the binary.
    > **Concern:** FIXED is sound only while no section changes what a package builds to; Q6 must pass, or the first
    > such section opens a silent wrong-build path.

  - Q3 one code or two — **TWO**

    > **Reasoning:** I change my B1 position. plt B1 showed the two faults are different in kind: "absolute" (the file is
    > wrong for every toolchain) against "relative" (the file may be right; this toolchain is old). A code should name a
    > fault, and these are two faults with repairs that never overlap. With one code, a CI job or agent that wants
    > "retry with a newer blink" must branch on message text, which is the more complex surface, not the less.
    > **Concern:** The year test puts a typo like `"2062"` under `UnsupportedEdition`, and a user is told to upgrade for
    > a typo; the note listing known editions (Q8) must make that visible.

  - Q4 edition names strictly increase — **Yes**

    > **Reasoning:** One sentence, and it states what §8.16.5's yearly cadence already implies. Without it, the
    > `UnsupportedEdition` / `InvalidEdition` split, and even the one-code help rule, is not decidable. It constrains the
    > future at no cost to any user.
    > **Concern:** None from my seat beyond the rule being forgotten when someone wants a "2026.1" style edition; the
    > sentence must be in §8.16.5, where edition cadence lives.

  - Q5 W1001 when the edition check fails — **K** *(dissent)*

    > **Reasoning:** Report everything in one pass, with no extra rule. The note in N repeats what the edition error's
    > help already says ("install a newer blink"), and it is still a guess about any single section. S hides real typos
    > until after an upgrade.
    > **Concern:** If N wins, the note becomes a pattern that later manifest codes copy, and "may come from a newer
    > blink" spreads to cases with no evidence.

  - Q6 section admission rule — **Yes**

    > **Reasoning:** It is the constraint that makes FIXED and W1001-as-warning sound, and it costs nothing today because
    > no such section exists. The mechanism and its "needs edition N or later" code arrive with the first real section,
    > not before. That is YAGNI done right: write the rule, defer the machinery.
    > **Concern:** The rule is enforced only by review; a section that looks meaning-neutral (an optimization profile,
    > a feature flag) may slip in without an edition, so the spec should keep sys B1's reading ("observable behaviour")
    > in the text.

  - Q7 version in the W1001 message — **V0**

    > **Reasoning:** The W1001 message was set by the lexer/manifest panel, and the pending unknown-keys result ruled out
    > a version note on its sibling codes. This ticket is about `edition`; changing another code's wording here makes
    > two manifest warnings read differently for no repair gain.
    > **Concern:** If V1 wins, W1001 and the unknown-key warning drift apart in wording, and the next panel must align
    > them.

  - Q8 later-year error names version and known editions — **Yes**

    > **Reasoning:** For this one error the version and the edition list are the evidence for the repair: they let the
    > user see whether "upgrade" is right or whether `"2062"` was a typo. They are facts the binary has, not guesses. My
    > own A draft already had this note.
    > **Concern:** The text grows as editions add up; "knows editions 2026 to 2041" must stay a range, not a list.

  - Q9 dependency note — **E** *(dissent)*

    > **Reasoning:** The note's span on the dependency entry is where the user edits. The chain from the root is more
    > text on every transitive case and gives no repair that the span does not. If the chain is wanted, a command that
    > prints the dependency graph is the place for it, not every manifest error.
    > **Concern:** With E, a deep transitive fault points at a manifest the user does not own, and they must trace by
    > hand which of their direct dependencies pulled it in.

  - Q10 not demotable — **Yes**

    > **Reasoning:** A demotable edition error is the fallback by another door, and the fallback had no supporters. It is
    > not a lint; there is nothing to demote it to.
    > **Concern:** None; if users ask for an override, the answer is to edit the manifest, and that edit shows in the
    > diff.

#### Phase D — Q7

One focused round on Q7, after the first Phase C count of V0 4, V1 2. Systems and Web/Scripting moved from V1 to V0. The four V0 seats had named the same risk: V1 changes W1001 alone while the pending unknown-key diagnostics keep their wording, and the golden outputs change at each release. All six seats asked for one version-wording rule for all manifest diagnostics, set in its own ticket (see *Known gaps and follow-ups*).

| Question | Result |
|---|---|
| Q7 version in W1001 text | **V0 6-0** after 4-2 (sys, web moved from V1) |

Each seat's Q7 vote, reasoning and concern:

- **Systems:**

  > **Vote:** V0
  > **Reasoning:** I change my vote from V1. Changing W1001's wording alone makes it differ from its pending sibling warning, and one rule for all manifest diagnostics belongs in its own ticket, as devops says. The version is already in the edition error (Q8), where it is part of the repair.
  > **Concern:** If nobody files the follow-up ticket for a version line across all manifest diagnostics, the idea is lost; the moderator should list it in the decision's follow-ups.

  Systems on the follow-up:

  > web: "The version string makes golden test output churn on each release."
  >
  > That is a second cost of V1 that I did not count. The single rule in its own ticket must also cover how the tests handle the version.

- **Web/Scripting:**

  > **Vote:** V0
  > **Reasoning:** I change from V1. The version helps the reader only if all manifest diagnostics show it the same way. Changing W1001 alone here, while its sibling stays without it, gives users and the LSP two styles for one kind of fault. The right place is one rule for all of them, in its own ticket.
  > **Concern:** The follow-up ticket gets lost, and devs keep reading "not defined by the spec" with no way to tell a typo from an older blink.

  Web/Scripting also asked for the follow-up:

  > I still want the version shown. I ask the moderator to file it as its own ticket: "manifest diagnostics name the
  > toolchain version", covering W1001, the unknown-key codes once they are approved, and the edition errors. Q8 already
  > puts the version in `UnsupportedEdition`, and that one is needed for the repair.

- **PLT:**

  > **Vote:** V0
  > **Reasoning:** No soundness question depends on Q7: V1 is a true statement, and V0 is not a false one. What decides it is consistency. W1001 and its pending sibling warning are one kind of fault, and changing one code's text here, while the other panel ruled the version out, splits the class. If the version line is wanted, it should be one rule for all manifest diagnostics, set in its own ticket.
  > **Concern:** If nobody files that follow-up ticket, web's real point (the "not defined by the spec" text points the user at the wrong place) stays unfixed.

- **DevOps/Tooling:**

  > **Vote:** V0
  > **Reasoning:** The repair is the same with or without the version, and adding it to the W1001 prose makes every golden
  > and snapshot change at each release. The pending unknown-key result ruled out a version note on its sibling codes, so
  > V1 would give two manifest warnings two forms. If the version is wanted, it goes in once: a per-run field in the JSON
  > output, or one rule for every manifest diagnostic, in its own ticket.
  > **Concern:** A user who sees W1001 for a section a teammate's newer blink accepts has no hint in the warning itself.
  > The `--version` check stays a manual step until a later ticket adds the per-run field.

- **AI/ML:**

  > **Vote:** V0
  > **Reasoning:** A model learns diagnostic wording as a pattern across sibling codes; W1001 and the unknown-key warning
  > worded under different rules teaches it the wrong pattern. The version line is worth having, but as one rule for all
  > manifest diagnostics, in its own ticket, with the golden-output normalization web names. This ticket is about
  > `edition`, and Q8 already puts the version where it repairs something: the later-year edition error.
  > **Concern:** The follow-up ticket for a shared version rule may never get filed, and "not defined by the spec" stays
  > as the wording a reader meets most often.

- **Minimalism:**

  > **Vote:** V0
  > **Reasoning:** This ticket is about `edition`. W1001's text belongs to an earlier panel, and the pending unknown-key
  > result ruled out a version note on its sibling. Changing one of two sibling warnings here gives two wording rules
  > for one kind of fault. If the version is wanted, a separate ticket can add it to every manifest diagnostic at once.
  > **Concern:** Nobody files that ticket, and web's real point (a user comparing toolchains) is answered only by Q8 and
  > the Q5 note, which cover the edition case but not a section from a newer blink under an old edition.

### Final Spec

```toml
[package]
name = "x"
version = "0.1.0"
edition = "2099"              # error[UnsupportedEdition]
```

```
error[UnsupportedEdition]: this blink does not know edition "2099"
 --> blink.toml:4:11
  |
4 | edition = "2099"
  |           ^^^^^^ blink 0.57.0 knows editions up to 2026
  |
  = help: install a newer `blink`; `blink editions` lists the editions this one knows
```

A TOML integer that names a known edition:

```toml
[package]
name = "x"
version = "0.1.0"
edition = 2026                # error[InvalidEdition]
```

```
error[InvalidEdition]: `edition` must be a string
 --> blink.toml:4:11
  |
4 | edition = 2026
  |           ^^^^
  |
  = help: write the edition as a string: `"2026"`
```

The fix for the integer case is machine-applicable: it replaces `2026` with `"2026"`. A dependency with the same fault adds a `note:` with a span on its entry in the dependent manifest and the chain from the root (`acme/app -> acme/auth -> acme/crypto`).

Locked points:

- An `edition` value that names no edition the toolchain knows is an error. There is no fallback edition: the toolchain never checks a package under an edition its manifest does not name. An omitted `edition` keeps the default. The check runs for each package in the graph. The span is the value token (Q1).
- The manifest schema does not depend on the edition. The toolchain alone decides which sections and keys it knows. W1001 stays a warning, and its severity is not put to a vote again here (Q2).
- Two codes. `UnsupportedEdition` (E1017): a string of four digits that is a year after the newest known edition; the file may be correct. `InvalidEdition` (E1018): any other value, including a non-string; the file is wrong for every toolchain (Q3).
- "Each new edition is named for a year after the newest existing edition." It is in §8.16.5. A year at or below the newest known edition that names no edition can never become one (Q4).
- W1001 and unknown-key diagnostics in the same manifest are still reported. Under `UnsupportedEdition` only, each adds a `note:` at the `edition` value that states a fact: "this manifest names edition 2099, which this blink does not know". The note does not guess that a section comes from a newer `blink`. Under `InvalidEdition` there is no note (Q5; Minimalism's concern is the fact-only wording).
- A section or key that changes what a package builds to — which code it compiles, which code it resolves, or which rules check it — enters the schema only together with a new edition. The change that adds the first such section also adds the error for a package whose edition is too old to use it. A section or key that does not change what the program does when it runs (metadata, tool hints, a setting that changes only speed or size) can enter in any `blink` release. The rule is in §8.16.1 *Scope* as a rule for spec authors (Q6).
- W1001 text is unchanged. It does not name the toolchain version (Q7).
- The `UnsupportedEdition` message names the version of this toolchain and the newest edition it knows; the help points to `blink editions` for the full list. This is the moderator's reading of the Q8 concerns. The known editions are named editions, not every year (Web/Scripting), and the list grows (Systems, Minimalism). A typo such as `"2062"` is easy to see because the newest known edition is in the message (Web/Scripting, AI/ML and Minimalism, on Q3). The list comes from the same built-in table as `blink editions` (DevOps/Tooling).
- The help for `UnsupportedEdition` never offers a lower edition and has no machine-applicable fix. For a dependency, it also offers pinning a release of the dependency that uses an edition this toolchain knows (Web/Scripting's concern).
- The help for `InvalidEdition` offers the nearest known edition by the catalog nearest-name rule and points to `blink editions`, so "not an edition" is clear for a skipped year (PLT's concern). Only a TOML integer that names a known edition gets a machine-applicable fix.
- Dependency case: the error adds a `note:` with a span on the dependency's entry in the dependent manifest. When the dependency is not direct, the text of the note also gives the chain from the root on one line, joined by `->`: the shortest path; among paths of equal length, the first in declaration order (Q9; PLT's tie rule).
- Neither error is a warning. No `@allow`, `--allow` or `[lints]` entry lowers it; such an entry is E0847 `NotAWarningName`, as for any error (Q10).
- `blink fmt` still formats the package. The LSP reports the error and does not type-check that package. `blink migrate --edition <year>` and `blink editions --edition <year>` give the same two errors, with the span on the argument.
- No manifest field names a minimum toolchain version. `edition` does that job (Minimalism).
- Every example edition value in the spec is `"2026"`, or a later year such as `"2099"` for the fault case (AI/ML's concern).

### Implementation notes

These are not spec text.

- Keep one table of known editions in the binary, and use it for both `blink editions` and the edition check. The "newest known edition" and the nearest-name candidates come from it (DevOps/Tooling).
- Add constants and catalog rows for E1017 and E1018. Both are free on main. Neither is suppressible by `[lints]`.
- The manifest reader checks `package.edition` once for each package in the graph, before it reads source. A string of four ASCII digits that is greater than the newest known year is E1017. Every other value that is not in the table is E1018.
- The dependency note needs the dependent manifest's entry span and a path search from the root: breadth-first, with declaration order as the tie rule.
- Under E1017, each W1001 and unknown-key warning of the same manifest adds the fact note at the `edition` value. Under E1018 it adds none.
- The LSP does not type-check a package that has an edition error. `blink fmt` does not read the edition.
- `blink migrate --edition` and `blink editions --edition` call the same check on their argument and use the argument as the span.
- Golden tests normalize the version string (Web/Scripting, PLT).
- Tests, one for each case: a later year (the ticket MVCE); a year before the first edition; a year at or below the newest known edition that names no edition; a string that is not a year; an integer that names a known edition and its fix; an integer that names no edition; a non-string, non-integer value; an omitted `edition`; a dependency one level down; a dependency two levels down with the chain; two chains of equal length; the pin help on a dependency; the fact note under E1017 and no note under E1018; a `[lints]` entry for either name is E0847; `migrate` and `editions` with an unknown year.

### Known gaps and follow-ups

- One rule for the toolchain version in the wording of all manifest diagnostics, W1001 and the unknown-key codes included, with the test-harness change that normalizes it. All six seats asked for it in Phase D. It is a chore or spec ticket to file when this decision lands.
- The first section that changes what a package builds to must bring its "needs edition N or later" error in the same change. This decision writes the rule and defers the mechanism and the code (PLT, DevOps/Tooling, Minimalism).
- The condition in the lexer/manifest decision for a new vote on W1001's severity ("only if ... edition gating of the schema") is met only when such a section arrives, and only for that section (Minimalism).
- A library that moves to a new edition locks out users of older toolchains, even if it uses no new feature. `blink init` and `blink migrate` write the newest edition, so this happens by default (Minimalism's concern on Q1). No fallback flag is specified (Systems' concern on Q1).
- A year with no edition stays a permanent gap. A user who types it gets `InvalidEdition`, and the help points to the known editions (PLT's concern on Q4).
