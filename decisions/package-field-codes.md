[< All Decisions](../DECISIONS.md)

# blink.toml Package Fields and Dependency Sources — Design Rationale

### Panel Deliberation

The ticket (verbatim):

> Title: Spec: register codes for blink.toml [package] field errors (missing or empty name/version) and a bad dependency source
>
> Desc: lib/pkg/manifest.bl prints 'error: [package] section missing required field name', '... version', 'package name must not be empty', 'package version must not be empty' via io.eprintln with no code. §8.9.3 makes name and version required and says combining dependency sources is an error, but neither has a registered code. Once coded, they follow the §8.9.8 span rule (key fault = key; missing key = [package] header). MVCE: blink.toml with only [package] version = "0.1.0" and a fn main; blink check prints the uncoded line.

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in three phases, with one round in Phase B. Quoted text is each panelist's own words. Each quote is a whole sentence, a whole list item, or a run of whole sentences from the panel record.

Before Phase B, a digest of the six Phase A proposals gave one fact that all seats then used: a TOML 1.0 bare key cannot contain `/`, so a key such as `local/utils` must be quoted. Every example below quotes it.

Questions:

- Q1: dependency source codes. **TWO:** `MissingDependencySource` (no source) and `ConflictingDependencySources` (two or more). **ONE:** `InvalidDependencySource` for both, with two messages.
- Q2: name of the missing-key code. **MMK:** `MissingManifestKey`. **MPF:** `MissingPackageField`. **MPK:** `MissingPackageKey`.
- Q3: the pending unknown-key note on the missing-key error. **COND:** the note fires only when the unknown key is the nearest-name match for the missing key. **ASIS:** keep the pending text with no condition.
- Q4: when the Q3 note fires, the help says "rename `nmae` to `name`".
- Q5: the same note, with the same nearest-name condition, on the no-source error, at an unknown field in the entry (`pth` for `path`).
- Q6: a git-only key (`tag`) in the entry makes the no-source help name `git` alone.
- Q7: a count line after manifest errors. **ALLOW:** the spec allows one count line. **SILENT:** the spec defines no summary line here.
- Q8: the no-source span for the table form `[dependencies.foo]`. **HEADER:** the `[header]`. **KEY:** the key.
- Q9: marks on the other source keys when an entry has two or more sources. **LABEL:** a label in the same snippet. **NOTE:** a `note:` at each key.

#### Phase A — Independent proposals

All six seats proposed the same `[package]` core: a missing-key code, `InvalidPackageVersion` for the version, and the existing E1011 for an empty name. They differed on the name of the missing-key code, on whether the dependency source needs one code or two (Systems, PLT, DevOps/Tooling and AI/ML proposed two; Web/Scripting and Minimalism proposed one), and on a few details of span and help.

- **Systems:** Four codes. Missing key (`MissingPackageField`), `InvalidPackageVersion`, `MissingDependencySource`, `ConflictingDependencySources`. Empty `name` is E1011.

  > Splitting codes by repair (sys-1) gives machine-readable fixes; merging (sys-2) gives fewer catalog rows. I prefer the split.

  > **Empty `name` is E1011, not a new code.** `""` does not match the §10.1 grammar, so it is already an `InvalidPackageName`.

- **Web/Scripting:** Three codes (`MissingPackageField`, `InvalidPackageVersion`, `InvalidDependencySource`); empty `name` is E1011; no `[package]` at line 1, column 1.

  > Rules I apply: one fault = one code; a code covers a *fault*, not one *spelling* of it ("empty" and "not semver" are one fault); reuse a code when an existing row already covers the fault.

- **PLT:** Four codes (`MissingManifestKey`, `InvalidPackageVersion`, `MissingDependencySource`, `ConflictingDependencySources`); empty values fold into membership codes; an absent key points at the anchor of the table that must hold it.

  > "Empty" is not a kind of fault. `""` is a value that is not in `PackageName` and not in `SemVer`.

- **DevOps/Tooling:** Four new codes (`MissingPackageKey`, `InvalidPackageVersion`, `MissingDependencySource`, `ConflictingDependencySources`) and E1011 for an empty name; no uncoded follow-on lines.

  > Only the first line is about the fault. The other two are noise, and the LSP has nowhere to put a squiggle. Any proposal must fix all three problems: a code, a position, and no uncoded follow-on lines.

- **AI/ML:** One code per fault kind for `[package]` (`MissingPackageField`, E1011, `InvalidPackageVersion`, which checks SemVer, not only emptiness), and two codes for the dependency source (`MissingDependencySource`, `ConflictingDependencySources`).

  > Rule: a `[package]` fault is one of two kinds, and the kind decides the code, not the key's value.

- **Minimalism:** Three codes for six messages (`MissingPackageField`, `InvalidPackageVersion`, `InvalidDependencySource`); empty `name` is E1011.

  > The ticket lists six uncoded messages (missing name, missing version, empty name, empty version, no source, many sources). Six faults do not need six codes.

#### Phase B — Debate highlights

One round. All six seats ended it ready to vote. The round settled the `[package]` block and the span for an absent section, and it narrowed the open points to the nine questions above. Web/Scripting moved to TWO on Q1. AI/ML, DevOps/Tooling and Minimalism moved to `MissingManifestKey`. Systems gave up its first-section-header span for an absent `[package]`, and its no-source help that offers `version`. Minimalism gave up its position that the follow-on lines are an implementation chore, and moved to a version-neutral no-source help.

- **Web/Scripting (round 1):**

  > I concede. My case for ONE was "one sentence in §8.9.3, so one code". But from my seat the name is what the user reads first, and `InvalidDependencySource` says "something is wrong" without saying what.

- **Systems (round 1):**

  > **No `[package]` span.** I concede **1:1, zero width**. web-1 is right: the fix is "add `[package]` at the top", so the top is the token at fault.

  > **v1 help.** I concede to devops: "A help that offers `version` in a toolchain with no registry prescribes a repair that does not exist, which §3.1 *Diagnostic Discipline* forbids."

- **Minimalism (round 1):**

  > **Follow-on lines.** I concede. sys, web, plt, devops and aiml want spec text, and devops's one sentence is cheap:

  > **No-source help in v1.** I change my position to devops's side, in a version-neutral form: "the help names the sources this toolchain accepts."

  > **Name.** I now support plt's `MissingManifestKey`. It names the rule ("a required key is absent"), not one section.

- **AI/ML (round 1):**

  > **Name.** I move to plt's `MissingManifestKey`. Reason: the pending W1002 is `UnknownManifestKey`, and §8.9.8 says "key".

- **DevOps/Tooling (round 1):**

  > **Name.** I move off `MissingPackageKey` to plt's `MissingManifestKey`. "Key" matches the §8.9.8 span table and the pending `UnknownManifestKey` (W1002); E1014 uses "Field" only for dependency entries.

Minimalism kept ONE on Q1 and said in round 1 that it accepts TWO if TWO wins.

#### Phase C — Silent vote

| Question | Result |
|---|---|
| Q1 dependency source codes | **TWO 5-1** (ONE: min) |
| Q2 missing-key code name | **MMK 6-0** |
| Q3 note on the missing-key error | **COND 6-0** |
| Q4 help follows the note | **Yes 6-0** |
| Q5 note on the no-source error | **Yes 6-0** |
| Q6 git-only key narrows the help | **Yes 5-1** (No: min) |
| Q7 count line | **ALLOW 5-1** (SILENT: min) |
| Q8 no-source span, table form | **HEADER 6-0** |
| Q9 marks on other source keys | **LABEL 6-0** |

Each seat's vote, reasoning and concern:

- **Systems:**

  - Q1 dependency source codes — **TWO**

    > **Reasoning:** The two faults have opposite repairs: one adds a key, the other removes keys. With one code, every consumer that reads the code (CI annotations, LSP code actions, fix loops) must parse the message to know which way to go, and that is a hidden string contract. The catalog already splits codes by repair (E1005 / E1012).
    > **Concern:** If ONE wins, tools will match on message text, and a later change to the wording breaks them.

  - Q2 name of the missing-key code — **MMK**

    > **Reasoning:** I change from MPF. The code also covers an absent `[package]` section, which is a missing key of the root table, not a "package field"; `MissingManifestKey` names both cases correctly. A name is frozen once published, so the wider correct name is the safer choice.
    > **Concern:** A later required key in another section could reuse MMK with a span rule that differs from the `[package]` one, so the row must state the span per case.

  - Q3 unknown-key note on the missing-key error — **COND**

    > **Reasoning:** A note on `homepage` for a missing `name` points the user at the wrong token. The nearest-name rule already exists and is deterministic, so the condition costs nothing and the note then always marks the real cause.
    > **Concern:** The two branches can merge with different note text, so the merge note must make the pending branch take the condition.

  - Q4 help follows that note — **Yes**

    > **Reasoning:** When the condition holds, the repair is known and unique: rename the key. Under COND the help is never a guess, so it follows §3.1.
    > **Concern:** If ASIS wins Q3, this help would also fire for unrelated keys and suggest a wrong rename.

  - Q5 unknown-field note on the no-source error — **Yes**

    > **Reasoning:** `pth = "../u"` gives both E1014 and no source; the note ties the two diagnostics to the one fault, as the third §3.1 rule asks (diagnostics at one point converge on one repair). Same nearest-name condition, same cost.
    > **Concern:** E1014 is pending on another branch, so this text can land before its dependency does.

  - Q6 a git-only key makes the no-source help name `git` — **Yes**

    > **Reasoning:** `tag` exists only for git sources, so the repair is fixed data, not a heuristic. It stays version- neutral and offers no source that the toolchain does not support.
    > **Concern:** When `branch`/`rev` arrive, the list of git-only keys must be kept in one place, or the help drifts.

  - Q7 count line after manifest errors — **ALLOW**

    > **Reasoning:** One count line in the same form as any failed build is predictable output and reports no new fault. Saying nothing would let an implementation keep an uncoded `error:` line and call it a summary.
    > **Concern:** The summary line must not take the `error:` prefix of a diagnostic, or tools will count it as one.

  - Q8 no-source span for the table form — **HEADER**

    > **Reasoning:** In the table form, the dependency key is inside the header, and the header is the token that opens the entry with no source. This is the §8.9.8 "bad section → the `[header]`" rule, so no new rule is needed.
    > **Concern:** A header with a quoted dotted key (`[dependencies."local/utils"]`) needs the whole header as the span, not only the last segment.

  - Q9 marks on the other source keys — **LABEL**

    > **Reasoning:** All source keys sit in one entry, usually on one line, so one snippet with labels shows the whole fault at once. Separate notes repeat the same line once per source.
    > **Concern:** In a multi-line table form the labels span several lines, and the renderer must keep them in one snippet.

- **Web/Scripting:**

  - Q1 dependency source codes — **TWO**

    > **Reasoning:** The name is the first thing a user reads. `MissingDependencySource` and `ConflictingDependencySources` each say the fault and the fix direction (add a key, or remove keys) before the user reads the message. Each gets a `blink explain` page with one repair. `InvalidDependencySource` says only that something is wrong.
    > **Concern:** A user who writes `{ path = "../u", version = "1.0" }` because Cargo allows it gets `ConflictingDependencySources` and may read it as a bug; the help must say in plain words that Blink takes exactly one source.

  - Q2 name of the missing-key code — **MMK**

    > **Reasoning:** I move from `MissingPackageField`. aiml's argument settles it for me: `UnknownManifestKey` and `MissingManifestKey` are one pattern, and a user who has seen one can guess the other. It also fits the no-section case, which is not a "field", and plt's point that a later required key (`type` in a native dependency) can reuse it with no new frozen name.
    > **Concern:** A general name can become a bucket; the catalog row must list each required key it covers, so `blink explain MissingManifestKey` stays one short page.

  - Q3 unknown-key note on the missing-key error — **COND**

    > **Reasoning:** A note from a missing `name` to `homepage = "..."` sends the user to the wrong line, and that costs more time than no note. With the nearest-name condition, the note fires on `nmae`, which is the real common case. The condition is one clause and uses a rule the catalog already has.
    > **Concern:** The two branches can land in the wrong order and lose the condition; the merge note must carry it.

  - Q4 help follows that note — **Yes**

    > **Reasoning:** When the note fires, the real fix is "rename `nmae` to `name`", not "add `name`". A help that says "add `name`" leaves the typo in place, and the user then gets W1002 forever. §3.1 says the first help names the repair; with COND, this is that repair.
    > **Concern:** If Q3 goes ASIS, this help would say "rename `homepage` to `name`", which is wrong; Yes only makes sense with COND.

  - Q5 unknown-field note on the no-source error — **Yes**

    > **Reasoning:** `{ pth = "../u" }` gives E1014 on `pth` and a no-source error on the key. Without the note the user sees two errors and must work out that they are one typo. The note joins them, under the same nearest-name condition as Q3, so one rule covers both.
    > **Concern:** The E1014 branch is not on main, so this text can be dropped at merge time if the merge note does not carry it.

  - Q6 a git-only key makes the no-source help name `git` — **Yes**

    > **Reasoning:** `{ tag = "v1" }` with no `git` means the user forgot the URL. A help that lists all sources makes them guess what the toolchain already knows. Naming `git` alone is the 90% fix.
    > **Concern:** The list of git-only keys must be written in the spec (today `tag`), or the help drifts as keys are added.

  - Q7 count line after manifest errors — **ALLOW**

    > **Reasoning:** Users of every build tool expect one count line at the end, and scripts and CI logs search for it. It must be the same form as any failed build, so it adds no new format to learn and reports no new fault.
    > **Concern:** An implementation can keep `failed to load root manifest` and call it a "summary"; the spec must say the line is the count form and nothing else.

  - Q8 no-source span for the table form — **HEADER**

    > **Reasoning:** In the table form the dependency name sits inside the header, so the header is the token the user looks at, and that matches the §8.9.8 rule "a bad section → the `[header]`". It is the same idea as the key for the inline form, not a second rule to learn.
    > **Concern:** The spec text must say this in the span table row, or an implementer will point at the first key inside the table.

  - Q9 marks on the other source keys — **LABEL**

    > **Reasoning:** Labels show every source on the one line the user is editing, so the choice is in front of them. A `note:` with a line and column makes the user find the other key by number. For an inline entry, all sources are on one line, which is where labels read best.
    > **Concern:** In the table form the sources sit on separate lines, so the snippet grows; that is still clearer than a list of notes.

- **PLT:**

  - Q1 dependency source codes — **TWO**

    > **Reasoning:** "Exactly one source" is the conjunction of two judgments, "at least one" and "at most one", and each fails with an opposite repair (add a key, remove keys). A code names one judgment, so `blink explain`, the LSP and an LLM map code to repair with no case split on message text. Both codes are mutually exclusive by count, so the split adds no ordering rule.
    > **Concern:** A later source kind (a registry alias, say) must fit both rows, and an implementer may add a third "wrong source" code instead of reusing them.

  - Q2 name of the missing-key code — **MMK**

    > **Reasoning:** Names are frozen, and §8.9.3 already has a required key outside `[package]` (`type` in a native-dependency entry). `MissingManifestKey` covers that, and a missing `[package]` section (a key of the root table in TOML's model), with no new name. It also pairs with the pending `UnknownManifestKey` (W1002).
    > **Concern:** The catalog row must state the scope it covers today (`[package]` and its two keys) so that nobody reads it as a license to report any absent optional key.

  - Q3 unknown-key note on the missing-key error — **COND**

    > **Reasoning:** A note asserts a relation between two tokens. With no condition, `homepage = "..."` gets a note on a missing `name`, which names the wrong cause. The nearest-name rule is the existing, deterministic test for that relation, so the condition adds no machinery.
    > **Concern:** The unknown-key branch must merge this condition in its own text, or main ends up with two sentences that disagree.

  - Q4 help follows that note — **Yes**

    > **Reasoning:** Under COND the note proves that the unknown key is the nearest match, so "rename `nmae` to `name`" is a repair that exists, and the W1002 help and the missing-key help converge on it (§3.1). Without it, the help says "add `name`", and the author ends up with both `nmae` and `name`.
    > **Concern:** If Q3 goes ASIS, this help would rename an unrelated key, so the decision file must tie Q4 to COND.

  - Q5 unknown-field note on the no-source error — **Yes**

    > **Reasoning:** It is the same judgment as Q3 one level down: an absent key whose cause is a misspelled key in the same table. With the same nearest-name condition (`pth` to `path`), the rule composes: one sentence in §8.9.8 for any absent required key and any unknown key in the same table.
    > **Concern:** E1014 is on a pending branch, so the merge note must carry this sentence, or it is lost.

  - Q6 a git-only key makes the no-source help name `git` — **Yes**

    > **Reasoning:** In the sum-type model `tag` is a field of the `Git` constructor only, so its presence fixes the constructor and `git` is the one repair. The rule is fixed data (field → constructor), not a heuristic.
    > **Concern:** If a later source kind also takes `tag`, the rule must say "names every source that takes the key", or the help goes wrong.

  - Q7 count line after manifest errors — **ALLOW**

    > **Reasoning:** A count reports no new fault, so it does not break the rule that each error is the sole report of its fault. Saying "the same form as any failed build" adds no new format; it binds the manifest path to the one that exists.
    > **Concern:** min is right that no section defines that common form, so implementers may each write their own until one section does.

  - Q8 no-source span for the table form — **HEADER**

    > **Reasoning:** An absent key anchors at its table's anchor. For an inline entry that is the key; for the table form it is the `[header]`, which holds the key. One rule, two shapes, and it matches the missing-`name` case (anchor at `[package]`).
    > **Concern:** For `[dependencies.foo]` the header and the key overlap, so a tool that prints only the key range may look like it does not conform when it does.

  - Q9 marks on the other source keys — **LABEL**

    > **Reasoning:** I concede to devops: the other source keys are part of one fault, not separate facts. Labels in one snippet say that, and the LSP maps them to related information on one diagnostic. A `note:` reads as a second remark and breaks up the snippet.
    > **Concern:** With three sources on several lines, a multi-line inline table may give a long snippet; the spec should not limit the label count.

- **DevOps/Tooling:**

  - Q1 dependency source codes — **TWO**

    > **Reasoning:** The two faults have opposite repairs: add a key, or remove keys. With two codes, the LSP chooses its code actions and `blink explain` chooses its page from the code alone. With one code, every client must parse the message text, and that coupling lasts as long as the frozen name.
    > **Concern:** An implementation may check "zero sources" before it scans the whole entry, so a typo like `pth` gives E1021 alone and the user does not see E1014 until the next run.

  - Q2 name of the missing-key code — **MMK**

    > **Reasoning:** "Key" matches the §8.9.8 span table and `UnknownManifestKey` (W1002), so a user who searches the catalog finds the missing-key and unknown-key rows next to each other. The broader scope also covers the no-section case without a special word.
    > **Concern:** A later required key in another table will join this code, and its help text must still name the right table.

  - Q3 unknown-key note on the missing-key error — **COND**

    > **Reasoning:** A note from `homepage` to a missing `name` sends the user to the wrong line. The nearest-name rule is already deterministic across the compiler, the LSP and `blink explain`, so the condition adds no new behaviour to test. Only the merge order makes the text land on the other branch; the decision belongs here.
    > **Concern:** The merge note may not carry the condition onto the unknown-key branch, which leaves two texts that disagree.

  - Q4 help follows that note — **Yes**

    > **Reasoning:** Without this rule, the help says "add `name`" and the note points at `nmae`. Two repairs then compete, which §3.1 forbids. "rename `nmae` to `name`" is a one-token edit that an editor can show at the right place.
    > **Concern:** If the unknown key's value is not a string (`nmae = 5`), the rename gives E1011 next, so the help must still be honest about the value.

  - Q5 unknown-field note on the no-source error — **Yes**

    > **Reasoning:** `{ pth = "../u" }` gives two errors on one entry. The note links them, so both point at one repair, as the W1001 → E1200 note already does. With the nearest-name condition, an unrelated unknown field gets no note.
    > **Concern:** The condition must use E1014's candidate set (source keys only), or `fetaures` → `features` would add a misleading note.

  - Q6 a git-only key makes the no-source help name `git` — **Yes**

    > **Reasoning:** `tag` without `git` shows that the author wants a git dependency. A help that lists `path` too adds a choice the author does not need. This is a concrete, one-key help.
    > **Concern:** The spec must list the git-only keys (`tag`, and later `branch`/`rev`), or implementations will disagree on which keys trigger the narrowed help.

  - Q7 count line after manifest errors — **ALLOW**

    > **Reasoning:** Each failed build ends with one count line, so scripts and CI logs can look for it. A manifest failure that ends in a different way breaks that, and SILENT lets each tool add its own summary text. The rule allows only a count; it allows no new fault and no uncoded line.
    > **Concern:** An implementation could keep `dependency resolution failed` and call it a summary; the text must say the line gives a count and nothing else.

  - Q8 no-source span for the table form — **HEADER**

    > **Reasoning:** In the table form, the entry is a section, and §8.9.8 points a bad section at its `[header]`. The LSP then marks the whole line, which is where the user adds `path = ...` below.
    > **Concern:** A rendered snippet with a span on the full header looks the same as W1001's, so the message text must say "has no source" clearly.

  - Q9 marks on the other source keys — **LABEL**

    > **Reasoning:** In an inline entry, all the source keys are on one line. Labels show them in one snippet, and the LSP maps them to the related information of one diagnostic. A `note:` for each key repeats the same line two or three times.
    > **Concern:** In the table form the source keys are on separate lines, so the snippet becomes taller; it is still one diagnostic.

- **AI/ML:**

  - Q1 dependency source codes — **TWO**

    > **Reasoning:** An agent picks its repair from the code. With TWO, the name says "add a key" or "remove keys", so the agent does not have to parse the message. The cost is one more catalog row and no more spec text.
    > **Concern:** An agent that writes `{ path = ..., version = ... }` from Cargo habits may "fix" `ConflictingDependencySources` by deleting `path` and keeping a `version` that v1 cannot resolve.

  - Q2 name of the missing-key code — **MMK**

    > **Reasoning:** `MissingManifestKey` pairs with the pending `UnknownManifestKey` (W1002), and §8.9.8 says "key". A model learns the pair as one pattern, and the name also fits the no-`[package]` case (an absent table is an absent key in TOML).
    > **Concern:** "Manifest" is wider than `[package]`, so a later rule for another required key could reuse this code without a vote.

  - Q3 unknown-key note on the missing-key error — **COND**

    > **Reasoning:** Without the condition, an unrelated key (`homepage = ...`) next to "missing `name`" invites an agent to rename it, which loses data. The nearest-name rule already exists in *Conventions*, so the condition adds no new mechanism.
    > **Concern:** The condition must land on the unknown-key branch as well, or the two texts disagree after the merge.

  - Q4 help follows that note — **Yes**

    > **Reasoning:** Agents apply the `help:` line, not the `note:`. When the cause is a typo, "rename `nmae` to `name`" is the correct one-token edit, and "add `name`" leaves a W1002 behind.
    > **Concern:** If the condition in Q3 loses, this help would propose renames to keys that are not typos.

  - Q5 unknown-field note on the no-source error — **Yes**

    > **Reasoning:** `pth = "../u"` is the most likely cause of "no source", and the same note-plus-nearest-name pattern as Q3 means the model learns one rule for both.
    > **Concern:** E1014 and the no-source error both fire for one typo, so the output has two errors for one fault; the note must make clear they have one repair.

  - Q6 a git-only key makes the no-source help name `git` — **Yes**

    > **Reasoning:** `{ tag = "v1" }` has only one valid repair, so a help that lists every source wastes a turn. Naming `git` alone gives the exact repair without inventing a URL.
    > **Concern:** The set of "git-only keys" must be stated (today only `tag`), or the help's behaviour drifts as git keys are added.

  - Q7 count line after manifest errors — **ALLOW**

    > **Reasoning:** A count line in the standard form tells an agent how many faults remain, at no cost in learnability, since every failed build ends the same way. It reports no new fault, so it cannot point the agent at the wrong section.
    > **Concern:** An implementer could take ALLOW as licence to keep `failed to load root manifest` reworded as a "summary".

  - Q8 no-source span for the table form — **HEADER**

    > **Reasoning:** In the table form the dependency's key is in the header, so the header is the key's token. It is also the line where the agent inserts the missing `path =` or `git =`.
    > **Concern:** Readers could read HEADER and KEY as different rules when the real rule is "the token that names the dependency"; the spec text should say it that way.

  - Q9 marks on the other source keys — **LABEL**

    > **Reasoning:** I move from NOTE. The sources nearly always sit on one line of an inline table, so labels in one snippet show the whole conflict for fewer tokens than a separate `note:` block for each key.
    > **Concern:** In the table form the sources are on separate lines, so the snippet grows; that is fine, but the LSP must still show each label as a related location.

- **Minimalism:**

  - Q1 dependency source codes — **ONE** *(dissent)*

    > **Reasoning:** "Exactly one source" is one rule, and the panel's own test elsewhere is one rule, one code. E1011 and `InvalidPackageVersion` each already carry repairs that go in opposite directions (add text vs change text), with no seat asking to split them. The LSP keys its actions on which source keys are present, not on the code. TWO adds a frozen name and a `blink explain` page for no extra rule.
    > **Concern:** If TWO wins, the next "zero or many" rule in the manifest will cite this as precedent for a pair of codes, and the catalog grows two rows per rule.

  - Q2 name of the missing-key code — **MMK**

    > **Reasoning:** It names the rule, a required key is absent, not one section. A later required key in any section reuses it with no new frozen name. "Key" is the TOML word and the §8.9.8 word.
    > **Concern:** A general name invites stretching it to faults that are not "absent key", such as an empty value; the row must keep empty values out.

  - Q3 unknown-key note on the missing-key error — **COND**

    > **Reasoning:** I move. plt is right that a note from `homepage` to a missing `name` points at a token that is not the cause, which §3.1 forbids. The nearest-name rule already exists in *Conventions*, so the condition adds no new machinery. My earlier point was only where the text goes; the moderator's merge note handles that.
    > **Concern:** The condition lands on a branch that is not merged yet; if the two branches merge in the wrong order, the unconditional text ships.

  - Q4 help follows that note — **Yes**

    > **Reasoning:** *Conventions* already says that a nearest-name match puts the name in the `help:` line. With COND, this is that rule applied, not a new one.
    > **Concern:** If Q3 is ASIS, this help would propose renaming an unrelated key; Yes must depend on COND.

  - Q5 unknown-field note on the no-source error — **Yes**

    > **Reasoning:** A misspelled source key (`pth`) is the most likely cause of "no source", and the note uses the same nearest-name condition as Q3. One rule, used twice, is cheaper than two answers to the same shape.
    > **Concern:** It couples two codes across two branches; the merge note must carry it.

  - Q6 a git-only key makes the no-source help name `git` — **No** *(dissent)*

    > **Reasoning:** A special case to save one word of help. The version-neutral help already lists `git`. `tag` with a non-git source is a follow-up ticket, and this hint would pre-empt it.
    > **Concern:** None if No wins; if Yes wins, each new git-only key needs the rule updated.

  - Q7 count line after manifest errors — **SILENT** *(dissent)*

    > **Reasoning:** The spec defines no summary line for any other failed build, so "the same form as any failed build" points at text that does not exist. Silence already allows an implementation to print a count. A sentence that allows what nothing forbids adds surface and no rule.
    > **Concern:** With ALLOW, the next ticket must define the form the sentence refers to, and that becomes a spec rule by accident.

  - Q8 no-source span for the table form — **HEADER**

    > **Reasoning:** I move. In the table form the dependency key is inside the header, and §8.9.8 already says a section fault points at the `[header]`. The two answers mark nearly the same token; HEADER uses the rule the table has.
    > **Concern:** A tool might mark only `foo` inside the header; the row should say "the whole `[header]`".

  - Q9 marks on the other source keys — **LABEL**

    > **Reasoning:** One snippet with labels shows both keys in one place, in fewer lines than a `note:` per key. The keys are on one line in the common inline form.
    > **Concern:** In the table form the source keys sit on separate lines, so the snippet gets long; that is acceptable.

#### Phase D

There was no Phase D. No result was closer than 5-1, and each dissent came from one seat (Minimalism, on Q1, Q6 and Q7). Minimalism had said in Phase B that it accepts TWO if TWO wins.

### Final Spec

The text below is the text of §8.9.8 after this decision (the new rows of the span table, then the new paragraphs). §8.9.3 gains one sentence after "Combining sources is an error.": an entry with no source is an error too (`MissingDependencySource`, §8.9.8). §10.1 says that an empty or non-string `name` is also E1011, with the span from §8.9.8. ERROR_CATALOG.md gains four rows (E1019 to E1022, category Manifest) and the E1011 row cites §8.9.8.

New rows of the span table:

| A missing key | the `[header]` of the section that lacks it |
| A missing section (no `[package]`) | line 1, column 1, zero width |
| A dependency with no source | the token that names the dependency: the key for the inline form, the whole `[header]` for the table form (`[dependencies."local/utils"]`, quoted dotted segments included) |

**Reporting.** The toolchain checks the whole manifest and reports every manifest error before the load fails. After a manifest error the toolchain prints no further line about the failed load. The toolchain may print one line that gives the count of errors. That line is not a diagnostic: it does not start with `error:` and it names no fault.

**Dependency manifests.** This rule is for every manifest error. When the manifest at fault is a dependency's, the error adds a `note:` with a span on the dependency's entry in the dependent manifest. When the dependency is not direct, the note also gives the chain from the root on one line, for example `myapp -> auth -> crypto`. The chain is the shortest path. Among paths of equal length, it is the first in declaration order.

**Package keys.** All four codes in this subsection are errors of category Manifest. No `@allow` entry and no `[lints]` entry lowers them (`NotAWarningName`, E0847, as for any error).

- `MissingManifestKey` (E1019): the manifest has no `[package]` section, or `[package]` lacks `name` or `version`. With no `[package]` section, the toolchain reports one diagnostic, at line 1, column 1. When `[package]` lacks both keys, it reports one diagnostic for each key, each at the `[package]` header. This code covers only these absent keys. An empty value is not this code.
- An empty `name`, or a `name` that is not a string, is `InvalidPackageName` (E1011, §10.1). The span is the value. The message for the empty case says that the package name is empty.
- `InvalidPackageVersion` (E1020): `version` is empty, is not a string, or is not a SemVer 2.0.0 version. The span is the value. The help says that `"1.2"` is a dependency constraint (§8.9.4) and not a package version. For `"1"` and `"1.2"`, the help gives the padded version (`"1.0.0"`, `"1.2.0"`). That edit is not machine-applicable, because the author can mean another version.
- When an unknown-key diagnostic fired in `[package]`, and that unknown key is the nearest-name match (ERROR_CATALOG.md, *Conventions*) for the missing key, `MissingManifestKey` adds a `note:` at the unknown key. Its help then says to rename the key (``rename `nmae` to `name` ``). An unknown key that is not the nearest-name match, such as `homepage`, gets no note. If the renamed key has a bad value, the next run reports `InvalidPackageName` or `InvalidPackageVersion`.

```toml
[package]
version = "0.1.0"
```

```
error[MissingManifestKey]: `[package]` has no `name`
 --> blink.toml:1:1
  |
1 | [package]
  | ^^^^^^^^^ `name` is required
  = help: add `name = "myapp"` under `[package]`
```

```toml
[package]
name = "myapp"
version = "1.2"
```

```
error[InvalidPackageVersion]: `"1.2"` is not a SemVer 2.0.0 version
 --> blink.toml:3:11
  |
3 | version = "1.2"
  |           ^^^^^ expected MAJOR.MINOR.PATCH
  = help: `"1.2"` is a dependency constraint (§8.9.4), not a package version; write `"1.2.0"`
```

**Dependency sources.** An entry takes exactly one source (§8.9.3). Both codes below are errors of category Manifest, and no `@allow` or `[lints]` entry lowers them. A later source kind uses these two codes. There is no third code for a wrong source.

- `MissingDependencySource` (E1021): the entry has no source. The message says that the dependency "has no source". The help lists the sources that this toolchain supports; a v1 toolchain lists `path` and `git` (§8.9.7). Some keys belong to some sources only. Today the only such key is `tag`, and only `git` takes it. When the entry holds such a key, the help names every source that takes the key (today `git` alone). The toolchain checks the whole entry before it reports this error. When an unknown-field diagnostic fired in the same entry, and that field is the nearest-name match for a source key, this error adds a `note:` at that field. The candidates are source keys only. The two errors have one repair: rename the field. The help says so.
- `ConflictingDependencySources` (E1022): the entry has two or more sources. The primary span is the second source key in source order. Each other source key has a label in the same snippet, and the number of labels has no limit. The help says that an entry takes exactly one source and asks the user to keep one. It never picks which source to keep, and the error has no machine-applicable fix.

```toml
[dependencies]
"local/utils" = { path = "../utils", git = "https://example.com/utils.git" }
```

```
error[ConflictingDependencySources]: dependency `local/utils` has two sources
 --> blink.toml:2:38
  |
2 | "local/utils" = { path = "../utils", git = "https://example.com/utils.git" }
  |                   ----               ^^^ second source
  |                   |
  |                   first source
  = help: a dependency takes exactly one source; keep one of `path` and `git`
```

```toml
[dependencies]
"local/utils" = { pth = "../utils" }
```

```
error[MissingDependencySource]: dependency `local/utils` has no source
 --> blink.toml:2:1
  |
2 | "local/utils" = { pth = "../utils" }
  | ^^^^^^^^^^^^^ needs one source
  = note: blink.toml:2:19: the unknown field `pth` may be the misspelled `path`
  = help: rename `pth` to `path`
```

#### Locked points

- E1019 `MissingManifestKey`, E1020 `InvalidPackageVersion`, E1021 `MissingDependencySource` and E1022 `ConflictingDependencySources` are errors of category Manifest. No `@allow` or `[lints]` entry lowers them.
- E1011 keeps its name and its category (Modules). It covers an empty or non-string `name`; its row cites §8.9.8 for the span and gives the empty case its own message.
- An absent `[package]` section is one E1019 at line 1, column 1, zero width. A `[package]` without both keys is two E1019 diagnostics at the `[package]` header.
- E1019 covers only absent keys, and today only `[package]`, `name` and `version`. An empty value is not E1019. A later required key needs its own vote.
- The toolchain checks the whole manifest and reports every manifest error before the load fails. After a manifest error it prints no further line about the failed load. One count line is allowed; it is not a diagnostic.
- The dependency-entry `note:` and the chain from the root are stated once, for every manifest error.
- The no-source help is version-neutral: it lists the sources that the toolchain supports. When the entry holds a key that only some sources take, the help names every source that takes it. The spec states the list of such keys once (today `tag`).
- The conflict help says that an entry takes exactly one source. It never picks one, and it has no machine-applicable fix. A later source kind reuses E1021 and E1022.
- Q3 to Q5 apply only when an unknown-key or unknown-field diagnostic fired, and only when the unknown name is the nearest-name match. Candidates for Q5 are source keys only.

#### Moderator reading

This is the moderator's reading of the record, not a panelist's words.

- Q3 to Q5 refer to diagnostics that exist only on the pending unknown-key branch. This branch therefore says "an unknown-key diagnostic" and "an unknown-field diagnostic", and it names no code for them.
- At merge, the pending branch's uncoded sentence about a missing key gives way to the conditional text on this branch.
- Q7 allows a count line only. It does not define the form of a summary line. Minimalism and PLT both noted that no section defines a common form; that is a follow-up.

#### Merge note

The unknown-key branch (`spec/unknown-manifest-key`) has a sentence that says: when `[package]` lacks a required key (`name` or `version`) and the unknown-key warning fired in `[package]`, the error for the missing key adds a `note:` that points at the unknown key. That sentence has no code and no condition. At merge, it gives way to the text of this branch: the error is `MissingManifestKey` (E1019), the note fires only when the unknown key is the nearest-name match for the missing key, and the help says to rename the key. In the same way, `UnknownDependencyField` (E1014) must add the Q5 note on `MissingDependencySource` under the same condition.

In this branch, "an unknown-key diagnostic" means W1002 `UnknownManifestKey`, and "an unknown-field diagnostic" means E1014 `UnknownDependencyField`. Both codes are on the pending branch and not on main.

### Implementation notes

These notes are not spec.

- The six uncoded `eprintln` sites in `lib/pkg/manifest.bl` (:204, :208, :216, :220, :352, :356) get codes and spans.
- The separate empty-name check moves under E1011. The empty-version check moves under E1020, which also checks SemVer 2.0.0.
- Drop the two follow-on lines (`failed to load root manifest` and `dependency resolution failed`) after a manifest error.
- Collect all manifest errors before the load fails. Check the whole dependency entry (unknown fields) before the zero-source check, so both errors come in one run.
- Tests, one per case: no `[package]` section; both keys missing; `name` missing only; `version = "1.2"` with the padded help; empty and non-string `name` and `version`; no source in the inline form; no source in the table form (span on the whole header, quoted dotted segments included); `tag` without `git` (help names `git`); a misspelled source key (note at the field); a misspelled `[package]` key that is the nearest match, and one that is not (`homepage`); three sources (primary span on the second, a label on each other); an error in a dependency's own manifest (note and chain); a `[lints]` entry cannot lower any of the four codes.

### Known gaps and follow-ups

- The name grammar in §8.9.2 and §8.9.3 (`org/name`, hyphens) disagrees with §10.1 (`[a-z][a-z0-9_]*`).
- The §8.9.3 example uses `acme/myapp` and keys with `/` that are not quoted. This is a stale-example chore.
- Codes for "manifest file not found" and for a TOML parse error.
- `tag` with a source that is not `git`.
- A `version` source in v1. Today the registry is not shipped (§8.9.7). A user who removes `path` and keeps `version` after E1022 gets a source that v1 cannot resolve.
- A bad source value (`path = 3`).
- One summary-line form for every failed build (Minimalism and PLT, on Q7).
- Merge: the pending unknown-key branch takes the Q3 and Q5 condition.
