[< All Decisions](../DECISIONS.md)

# Unknown Keys in blink.toml Sections — Design Rationale

### Panel Deliberation

The ticket (verbatim):

> Title: Spec: diagnostic for an unknown key inside a defined blink.toml section (e.g. [package] nmae = ...)
>
> §8.9.8 says unknown keys inside a defined section are not yet specified. Decide: warning or error, code, did-you-mean, and how it interacts with §8.9.7 forward compatibility. Unknown top-level sections are W1001 UnknownManifestSection (warning, promotable). MVCE: blink.toml with [package] name = "x" version = "0.1.0" nmae = "y"; today the key is ignored with no diagnostic.

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in four phases, with one round in Phase B. Phase D took three questions (Q1, Q2 and Q6). Quoted text is each panelist's own words. Each quote is a whole paragraph or list item of the panel record, or a line range of one.

All seats agreed from Phase A on which tables the check covers. The closed tables are `[package]`, `[capabilities]`, a dependency entry (the inline table of a key in `[dependencies]` or `[dev-dependencies]`) and a native-dependency entry. The keys of `[dependencies]`, `[dev-dependencies]`, `[native-dependencies]`, `[alternatives]` and `[lints]` are names and keep their own checks. The span is the key. The help line offers the nearest key of the same table (ERROR_CATALOG.md, *Conventions*).

Questions:

- Q1: severity. **W:** warning `UnknownManifestKey` (W1002) in every closed table, promotable. **S:** W1002 in `[package]` and `[capabilities]`; error `UnknownDependencyField` (E1014) in dependency and native-dependency entries, not suppressible by `[lints]`. **E:** error in every closed table.
- Q2: a clause that a command which writes `blink.lock` does not write it while W1002 fired in a dependency entry. It has effect only if W wins Q1.
- Q3: a later error that the unknown key causes adds a `note:` that points at the key, as E1200 and E1052 do after W1001.
- Q4: no key diagnostic inside a section that W1001 reports.
- Q5: every unknown key is reported, in source order.
- Q6: a `note:` that names the toolchain version and says a newer Blink may define the key, when the nearest-name rule gives no suggestion.

#### Phase A — Independent proposals

Four seats proposed W (Web/Scripting, DevOps/Tooling, AI/ML, Minimalism). Systems proposed E and PLT proposed S. The seats named the same tables. They differed on whether an ignored key in a dependency entry is a fault that must stop the build.

- **Web/Scripting (web-1):**

  > **Rule.** A key that §8.9.3 (or the `[native-dependencies]` field table) does not define, in a table whose keys
  > are a fixed set of field names, is the warning `UnknownManifestKey` (W1002). The span is the key. The help line
  > offers the nearest defined key of that same table, by the *Conventions* nearest-name rule. `--strict` and a
  > `[lints]` entry can make it an error, as for any warning.
  >
  > - *Consistency is the 5-minute test.* A JS/Python dev who already met W1001 will expect "misspelled section"
  >   and "misspelled key" to behave the same. One rule, "unknown manifest things warn, `--strict` makes them errors",
  >   fits in one sentence. A split rule (sections warn, keys error) makes a Stack Overflow question: "why does
  >   `[dependecies]` build but `nmae` fail?"
  >
  > - *§8.9.7 forward compatibility applies more to keys than to sections.* New schema growth is far more likely
  >   to be a new key (`rust-version`-style `blink-version`, `homepage`, `keywords`, `readme`) than a new section. An
  >   error would make every new optional key a hard break for anyone on an older toolchain, which is the exact case
  >   W1001 was a warning to avoid.

- **Systems (sys-1, first choice):**

  > A key that §8.9.3 (or the native-dependency field table) does not define, inside a closed table, is the error
  > `UnknownManifestKey` (E1014; E1014 is free in the E10xx block). Not suppressible by `[lints]`, like E0842 and E0830.
  > The span is the key (§8.9.8 span rule). The label names the allowed keys. The help line offers the nearest allowed
  > key under the *Conventions* rule; the candidates are the keys of that one table.

- **Systems (sys-2, fallback):**

  > - `UnknownManifestKey` (W1002), warning, promotable by `--strict` and `[lints]`: unknown keys in `[package]` and
  >   `[capabilities]`.
  > - `UnknownDependencyField` (E1014), error: unknown keys in a dependency inline table or a native-dependency inline
  >   table.
  >
  > I rank sys-2 below sys-1. `edition` lives in `[package]`, and a dropped `edition` changes lint severities and stdlib
  > defaults, so `[package]` is not only metadata. sys-2 also makes the reader learn which table gets which severity.

- **PLT (records and maps):**

  > "Unknown key inside a defined section" has no meaning until we say which tables are **records**
  > (a closed set of field names, given by the spec) and which are **maps** (the keys are data: package
  > names, library keys, effect names, diagnostic names). The schema in §8.9.3 mixes both:
  >
  > 2. **Candidates are the fields of the enclosing record only.** `[package] verison` suggests
  >    `version`. A field name from a different record is never a candidate (`[package] path = ...`
  >    gets no "did you mean" pointing into a dependency entry). The nearest-name rule in
  >    ERROR_CATALOG *Conventions* applies as written.

- **PLT (plt-1):**

  > - An unknown key in `[package]` or `[capabilities]` is the warning `UnknownManifestKey`
  >   (next free W10xx, W1002). Promotable by `--strict` and `[lints]`, like W1001.
  > - An unknown key in a dependency entry or a native-dependency entry is the error
  >   `UnknownDependencyField` (next free E10xx code). Not suppressible: no `[lints]` entry reaches it.
  >
  > **Tradeoffs.** Two codes, one more decision point than a single rule. In exchange, the one case that
  > builds wrong code silently becomes a hard stop. Cost of the error: an entry written for a newer
  > toolchain fails on an older one with a clear message; that is the correct result, since the old
  > toolchain cannot honour the field.

- **DevOps/Tooling (devops-1):**

  > A key that §8.9.3 (or §9.1.2 for native-dependency fields) does not define, inside a table whose key set the spec fixes, is the warning `UnknownManifestKey` (W1002).
  >
  > - **Forward compatibility holds.** A newer toolchain that adds a key (for example `rev` or `branch` for git deps, or `[package].authors`) does not break an older toolchain; it warns. This is the §8.9.7 promise and the reason W1001 is a warning.
  > - **The silent-success risk is small and covered.** plt's worry from the W1001 vote (a typo drops `"error"` overrides) does not apply here: `[lints]` keys are already E0842. The dangerous typos in closed tables either cause a later error (missing `name`, no source) that now carries a note at the real cause, or drop an optional value (`edtion`, `feature`) where a visible warning is the right weight. Teams that want hard failure use `--strict` in CI, as for every other warning.

- **AI/ML (aiml-1):**

  > **Rule.** In a table whose keys this specification fixes, a key that the specification does not
  > define is the warning `UnknownManifestKey` (W1002). The span is the key. When exactly one defined
  > key of that table is near enough (ERROR_CATALOG *Conventions*), the help line names it.
  > `--strict` and a `[lints]` entry can make it an error, as for W1001.
  >
  > - + One rule for sections and keys. An AI that learned W1001 predicts W1002 with no new reading.
  > - + The `help:` line turns most typos into a one-edit fix. Cargo-isms get a clear "not a key"
  >   instead of silent acceptance, so a model stops copying them.
  > - + Keeps §8.9.7: a manifest that a newer toolchain writes (a new `[package]` key) still builds.

- **Minimalism (min-1):**

  > Same reason as W1001, and the reason is stronger here. §8.9.7 says the schema is forward-compatible, and new keys are the most likely way the schema grows (a `branch` or `rev` field on git deps, a `readme` in `[package]`). If a key error broke an older toolchain on a newer manifest, every additive schema change would become a breaking change. A warning keeps the promise; `--strict` gives CI the hard gate.
  >
  > The silent-success risk that plt raised for `[lint]` is smaller here: most key typos remove a required key (`nmae`, `pth`, `tpye`), and the missing-key error fires anyway. The one silent case is an optional key with a default, such as `edtion = "2024"`, which falls back to the latest edition. The warning covers that, and the user who needs a hard stop has `--strict`.

#### Phase B — Debate highlights

One round. All six seats ended it ready to vote. The round turned on the entry-field risk that PLT and Systems named. `tga` for `tag` fetches the default branch, `lnik` and `heders` change linking and skip the header check, and in each case nothing later fails.

- **Systems (round 1), withdrawing E after plt-3:**

  > **I concede E for `[package]` and `[capabilities]`.** plt-3: "a newer toolchain that adds `[package] homepage` would
  > make every older toolchain refuse the manifest." That is right. `homepage`, `readme` and `description`-style keys do
  > not change the binary, so an error on them buys nothing from my seat and breaks §8.9.7. I drop sys-1.

- **DevOps/Tooling (round 1):**

  > - My reason (3), "the harmful typos there (`pth`, `gti`) already end in a "no source" error", covers only typos of a
  >   source key. It does not cover `tga` (plt), `lnik` or `heders` (sys), or `featurs`. Those typos leave a valid entry
  >   that builds a different program, and nothing later fails. I named the wrong examples.

- **PLT (round 1), moving to W with the lockfile clause on sys-2's `edition` point:**

  > - **sys-2 on `[package]`:** "`edition` lives in `[package]`, and a dropped `edition` changes lint
  >   severities and stdlib defaults, so `[package]` is not only metadata." Correct. My Phase A split
  >   claimed `[package]` fields "carry metadata or fail closed". `edition` does neither. So S does not
  >   follow its own principle cleanly: the line it draws (entry tables vs. the rest) is not the line
  >   between "safe to ignore" and "not safe to ignore". A split that does not match its own reason is
  >   not worth the second code.

- **Minimalism (round 1), conceding the entry-field risk:**

  > That is true, and it is the strongest case on the ballot. `tga = "v1.0"` fetches the default branch and pins it. My Phase A text said the dangerous typos "remove a required key, and the missing-key error fires anyway". That holds for `pth` and `nmae`. It does not hold for `tga`, `featurs`, `lnik` or `heders`, where the dropped key is optional. I withdraw that claim for entry fields.

After round 1: Systems and DevOps ranked S first, PLT ranked W with the lockfile clause first, and Web/Scripting, AI/ML and Minimalism ranked W first.

#### Phase C — Silent vote

| Question | Result |
|---|---|
| Q1 severity | **3-3**: S (sys, plt, devops), W (web, aiml, min); no seat voted E |
| Q2 lockfile clause | **No 4-2** (Yes: sys, web) |
| Q3 note on a later error | **Yes 6-0** |
| Q4 no key diagnostic inside a W1001 section | **Yes 6-0** |
| Q5 every unknown key, in source order | **Yes 6-0** |
| Q6 version note | **V1 4-2** (V0: aiml, min); the V1 seats differed on scope |

Each seat's vote, reasoning and concern:

- **Systems:**

  - Q1 severity — **S**

    > **Reasoning:** My test is whether a dropped key changes what gets built. In `[package]` and `[capabilities]` it
    > mostly does not; in dependency and native-dependency entries it always does (`tag`, `features`, `link`, `libs`,
    > `headers`). A typo of `headers` turns off the `@ffi.struct` layout check, so a layout fault reaches run time as
    > memory corruption. A build input must take effect or stop the build. Forward compatibility for inputs comes from
    > reserving fields in the spec, not from ignoring them.
    > **Concern:** W is likely to win, and under W a `heders` or `lnik` typo in a native-dependency entry stays a warning
    > in a CI log, with no lockfile clause to catch it, because native entries are not in `blink.lock`.

  - Q2 lockfile clause — **Yes**

    > **Reasoning:** Under W this clause is the only guard that keeps a dropped `tag` or `branch` from freezing the wrong
    > commit into `blink.lock`, which every machine then reproduces. Reproducible and wrong is worse than not
    > reproducible. The cost is zero for a manifest with no typo, and the build that reads an existing lockfile is not
    > affected.
    > **Concern:** If it fails, a W1002 inside a git entry pins the wrong tree on the first `blink update`, and nothing
    > later shows the fault.

  - Q3 note on a later error — **Yes**

    > **Reasoning:** The note points from the effect back to the cause at no run-time cost. It matches what E1200 and
    > E1052 already do after W1001, so it is one pattern, not a new one. Under S I accept devops' narrowing to the missing
    > `[package]` key.
    > **Concern:** If the note fires on a later error that the unknown key did not cause, it sends the reader to the wrong
    > line; the rule must stay "same table, required key missing or no source".

  - Q4 no key diagnostic inside a section that W1001 reports — **Yes**

    > **Reasoning:** One cause, one diagnostic. The toolchain has no schema for an unknown section, so it has nothing to
    > check keys against.
    > **Concern:** None from my seat.

  - Q5 every unknown key is reported, in source order — **Yes**

    > **Reasoning:** The manifest walk already visits every key; stopping at the first one saves nothing and makes the
    > user rebuild once per typo. Source order gives stable, diffable output.
    > **Concern:** None from my seat.

  - Q6 toolchain-version note — **V1, on both `UnknownManifestKey` and `UnknownDependencyField` (under W, on W1002), only when the
nearest-name rule gives no suggestion.**

    > **Reasoning:** When there is no near key, the likely cause is a manifest from a newer Blink, and the fix is an
    > upgrade; the note says so in one line. When a near key exists, the typo is the likely cause and the note is noise,
    > so the condition keeps it out.
    > **Concern:** A new key that is close to an old one (`lib` beside `libs`) gets a did-you-mean and no version note,
    > so the user "fixes" a correct newer manifest down to the old key.

- **Web/Scripting:**

  - Q1 severity — **W**

    > **Reasoning:** One rule covers sections and keys: an unknown manifest name warns, and `--strict` or `[lints]`
    > makes it an error. A user who met W1001 already knows it, and cargo users carry it over unchanged. S makes the
    > severity depend on which table holds the key, which a newcomer cannot work out from the message. S also puts the
    > error exactly where v2 will most likely add fields. The real harm sys and plt name (`tga` pinning the wrong commit)
    > is better closed at the lockfile write (Q2) than by a second severity.
    > **Concern:** If Q2 fails, `heders`, `lnik` and `tga` typos stay warnings that a CI with no `--strict` lets
    > through, so the spec should tell CI users to pass `--strict`.

  - Q2 lockfile clause — **Yes**

    > **Reasoning:** I change my B1 position. My objection was that a fresh clone's first build would fail on a
    > warning. plt's refined text removes that: a build that reads an existing `blink.lock` is not affected, and a
    > committed lock is the normal state (§8.9, :425). Only `blink add`, `blink update` and a first resolve stop, and the
    > extra `error:` line says why in plain words, so it does not read as a hidden severity. It closes the one case where
    > a typo becomes a committed, reproduced wrong build, and it still keeps one code and one catalog severity.
    > **Concern:** Users will ask why `blink add other/pkg` fails over a typo in an unrelated entry, so the `error:` line
    > must name the entry and point at the W1002 above it.

  - Q3 note on a later error — **Yes**

    > **Reasoning:** "Missing `name`" points at `[package]` or line 1, and "no source" points at the dependency key. The
    > typo sits somewhere else. Without the note the reader matches two messages by hand, and may follow the error's own
    > help and end up with both `pth` and `path`. It is the same shape as E1200/E1052 after W1001, so there is nothing
    > new to learn.
    > **Concern:** The missing-key and no-source errors have no code or catalog row yet, so the note rule names them by
    > fault until a chore gives them codes.

  - Q4 no key diagnostic inside a W1001 section — **Yes**

    > **Reasoning:** One cause, one diagnostic. Five lines under a misspelled `[pakage]` bury the single line that
    > names the fix. The candidate set for an unknown section is also undefined, so a key check there has nothing to
    > compare against.
    > **Concern:** None from my seat; the fix to the section header then shows the key warnings on the next build, which
    > is the correct order.

  - Q5 every unknown key reported, in source order — **Yes**

    > **Reasoning:** "Fix one, rebuild, see the next" is the worst edit loop for a user. tsc, eslint and E0842 all
    > report every fault in one run. Source order keeps the output the same from run to run, which the LSP and snapshot
    > tests need.
    > **Concern:** None worth stating.

  - Q6 toolchain-version note — **V1, on W1002 only, and only when the nearest-name rule gives no suggestion.**

    > **Reasoning:** When a key is near a defined one, the user made a typo and gets "did you mean". When no key is near
    > (`homepage`, `rev`), the most likely cause is a manifest from a newer Blink, and naming the toolchain version
    > answers "why does my teammate's build not warn?" in one line. The two never print together, so a typo never sends
    > the user to upgrade, which answers plt's §3.1 point. It is a `note:` (information), not a `help:` (repair).
    > **Concern:** V0 likely wins, and then a user on an older toolchain sees "no key `rev`" with no hint that an
    > upgrade is the fix.

- **PLT:**

  - Q1 severity — **S**

    > **Reasoning:** In B1 I ranked W with the lockfile rule first. web, devops, aiml and min showed that the rule is a severity that does not show its name: "it acts as an error in a fresh checkout and as a warning when an old `blink.lock` exists, so the same manifest behaves differently by repo state" (min). A rule whose result depends on what is in the repo, and not on the manifest, does not compose, so I withdraw it. S says the same thing openly. A dependency or native-dependency entry field selects an input of the build, so an unknown field is an error at the key. That also covers `link` and `headers`, which the lockfile rule did not reach. The `edition` hole in `[package]` that sys found remains a warning that `--strict` can make an error. I accept that.
    > **Concern:** If S loses, W lets `tga` pin the wrong commit into `blink.lock`, so the same wrong tree builds on every machine with only a warning that CI output hides.

  - Q2 lockfile clause — **No**

    > **Reasoning:** I proposed it and I now vote against it. Lockfiles are required (06_tooling.md:425). So the clause makes the result of a warning depend on repo state, and the error the user then sees ("no lockfile") does not name the key at fault. That breaks the §3.1 rule that diagnostics must converge on the repair the first `help:` names. If the panel wants a hard stop, S is the sound form of it.
    > **Concern:** If W wins with no clause, nothing stops a typo in an entry from freezing the wrong input.

  - Q3 note on a later error — **Yes**

    > **Reasoning:** A "missing `name`" error spans the `[package]` header, and its help says to add `name`. When the cause is `nmae` lower in the table, that help leads to a manifest with both keys. The note sends the repair back to the cause, as E1200 and E1052 do after W1001. Under S, the note is needed only for the missing `[package]` key (devops's narrowing). Under W, the no-source case needs it too.
    > **Concern:** The missing-key and no-source errors have no code or catalog row yet, so the note rule names a fault with no row behind it until a chore adds the row.

  - Q4 no key diagnostic inside a W1001 section — **Yes**

    > **Reasoning:** One cause, one diagnostic. An unknown section has no defined key set, so a key check inside it has no candidate set and no meaning.
    > **Concern:** None from my seat. The section check must run before the key check, and the spec text should say so.

  - Q5 every unknown key reported, in source order — **Yes**

    > **Reasoning:** This is the E0842 rule ("reports each such argument and key, not only the first"). A fixed order is what makes "same input, same output" hold across the compiler, the LSP and `blink explain`.
    > **Concern:** Under S, an implementation could abort the manifest load at the first error. The text must say the walk finishes the manifest before the load fails.

  - Q6 toolchain-version note — **V1, on `UnknownDependencyField` only, and only when the nearest-name rule gives no suggestion.**

    > **Reasoning:** With a near candidate, the key is almost always a typo, and an upgrade hint would point to a repair that does not exist. With no near candidate (`rev`, `branch`), "a newer Blink may define this key" is true information, and it explains why the build stopped. On W1002 the build goes on, so the note has nothing to explain there.
    > **Concern:** A key with no near candidate can still be a plain mistake, so the note must be worded as "may", never as the repair in `help:`.

- **DevOps/Tooling:**

  - Q1 severity — **S**

    > **Reasoning:** The best diagnostic stops at the cause. Under S, `tga`, `featurs`, `lnik` and `heders` give one error with the span on the key and a did-you-mean, and the user fixes it in one edit. Under W the build passes, and the fault surfaces later as a behaviour bug far from `blink.toml`, or as a wrong commit in `blink.lock`. The split follows the table kind, which the LSP already knows for its candidate list, and two codes keep `--strict` and `[lints]` behaviour plain.
    > **Concern:** I expect W to win, and then a team without `--strict` in CI pins a wrong git commit from a `tga` typo, with only a warning line in a log nobody reads as the trace.

  - Q2 lockfile clause — **No**

    > **Reasoning:** Because a build without `blink.lock` is an error (§8.9, :425), the clause makes the same manifest fail on a fresh clone and pass with an old lock. That is a third severity hidden under the label `warning`, and the failing line ("`blink.lock` was not written") is a separate message from the W1002 that caused it. If the panel wants a hard stop in entries, S says so in the catalog row; this clause does not.
    > **Concern:** If it passes, users will file "a warning broke my build" bugs, and each lockfile-writing command (`blink add`, `blink update`, first resolve) must carry the rule the same way, which is a test-matrix cost.

  - Q3 note on a later error — **Yes**

    > **Reasoning:** The missing-`name` error spans the `[package]` header while `nmae` sits lines below, so a note links symptom to cause, as §8.9.8 already does for E1200/E1052 after W1001. Under S it reduces to the missing `[package]` key case; under W it also covers no-source. One line, no new concept.
    > **Concern:** The missing-key and no-source errors have no code or catalog row yet, so the note rule will name them by fault until a chore gives them codes.

  - Q4 no key diagnostic inside a W1001 section — **Yes**

    > **Reasoning:** One cause, one diagnostic. An unknown section has no key set, so key warnings under `[pakage]` would be noise that buries the one useful line and invites an agent to "fix" the keys.
    > **Concern:** None from my seat; the implementation must skip the key walk for a section that W1001 reports, including a section first opened by a dotted top-level key.

  - Q5 every unknown key reported, in source order — **Yes**

    > **Reasoning:** Fix-one-rebuild-see-next is the worst edit loop; tsc, rustc and E0842 all report every fault in one run. Source order gives stable output for tests and diff-based tools.
    > **Concern:** None; the implementation must not bail out of the manifest walk on the first fault, which matters most if any part is an error.

  - Q6 toolchain-version note — **V1, on `UnknownDependencyField` (E1014) only, and only when the nearest-name rule gives no suggestion.**

    > **Reasoning:** A key with a near candidate is a typo, and an upgrade hint beside `did you mean` sends the user the wrong way; a key with none (`rev`, `branch`) is the forward-compatibility case, where "this toolchain is 0.57.0; a newer Blink may define `rev`" names the real repair. On a warning the build continues, so the hint adds little; if W wins I would not put it on W1002.
    > **Concern:** If S loses, V1 has no error to attach to, and a note on a warning risks being one more line that users learn to skip.

- **AI/ML:**

  - Q1 severity — **W**

    > **Reasoning:** W is the same rule as W1001 one level down: unknown schema name → warning, span on the name, nearest-name help, promotable. An AI that read the section rule predicts the key rule with no new reading, and generates correct manifests from §8.9.8 alone. S makes severity depend on table kind, and the panel itself moved the line during B1 (`edition` in `[package]`), so a model cannot predict it from the file. `--strict` gives agent harnesses and CI the hard stop with one flag that already covers every other warning.
    > **Concern:** LLM agents tend to stop reading output once a build passes, so a `tga` or `heders` warning may be seen by no one unless agent harnesses run with `--strict`.

  - Q2 lockfile clause — **No**

    > **Reasoning:** The refined text is better than the first one, because builds that read a lockfile are not affected. But it still gives one code two behaviours: a warning on a build, a refused write on `blink add` / `blink update` / first resolve. An agent sees `warning`, then an error about `blink.lock` that has no code of its own, and must connect the two. That is a weaker repair loop than an honest error (S) or an honest warning (W).
    > **Concern:** If it passes, the "lockfile not written" line needs a code and a catalog row, or it is a diagnostic an AI cannot look up.

  - Q3 note on a later error — **Yes**

    > **Reasoning:** The note points from the effect to the cause, so an agent edits the typo instead of adding a second key (`pth` and `path` both). It reuses the W1001 → E1200/E1052 pattern, so it adds no new idea. The missing-key and no-source errors need codes and catalog rows in a separate chore; the note should not wait on that.
    > **Concern:** Until those two errors have codes, the spec names the note's host error by its fault only, which is easy to implement on one path and miss on the other.

  - Q4 no key diagnostic inside a W1001 section — **Yes**

    > **Reasoning:** One cause, one diagnostic. Seven warnings for one misspelled `[pakage]` header costs tokens and invites an agent to "fix" the keys instead of the header.
    > **Concern:** None from my seat; the risk is only that an implementation forgets the clause, which a test row covers.

  - Q5 every unknown key reported, in source order — **Yes**

    > **Reasoning:** An agent fixes every key in one edit instead of one build per key, and a fixed order keeps output stable for golden tests and diff-based tools. E0842 already sets the same rule for `[lints]`.
    > **Concern:** None from my seat.

  - Q6 toolchain-version note — **V0**

    > **Reasoning:** The keys with no near candidate are mostly not keys from a newer Blink; they are keys copied from Cargo, npm and pyproject (`authors`, `keywords`, `default-features`, `optional`), which is the most common AI error in a manifest. V1 would tell a model "a newer Blink may define `authors`", which steers it to upgrade or keep the key instead of removing it. The forward-compat case belongs to the `edition`-newer-than-toolchain follow-up, where a version gate can say it with facts, not a guess.
    > **Concern:** If V1 wins, its text must not suggest that the key is valid; "this toolchain does not define `authors`" is safe, "a newer Blink may define it" is not.

- **Minimalism:**

  - Q1 severity — **W**

    > **Reasoning:** W adds one row and no new concept: it is W1001 one level down, with the same severity, span, help and promotion. S needs two codes and a split by table that plt itself says "does not match its own reason" once `edition` is counted. E contradicts the decided reasoning for W1001 and makes every new metadata key a breaking change. Teams that want the hard stop get it from `--strict` or one `[lints]` line, and teams that rely on §8.9.7 keep it.
    > **Concern:** A typo in an optional entry field (`tga`, `heders`) stays a warning that a CI log without `--strict` scrolls past, so a wrong pinned commit or a skipped layout check can still ship.

  - Q2 lockfile clause — **No**

    > **Reasoning:** It attaches a side effect to a warning, so the catalog row says "warning" while a fresh clone fails, because a build without a lockfile is an error (06_tooling.md:425). The same manifest then acts differently by repo state, which is harder to learn, test and explain than either W or S. If the panel thinks entry typos must stop the build, S says that openly; this clause hides it.
    > **Concern:** With the clause rejected, the `tga` case plt named writes the wrong commit to `blink.lock`, where it is reproduced on every machine until someone reads the warning.

  - Q3 note on a later error — **Yes**

    > **Reasoning:** I gave way on this in B1: a missing `name` spans the `[package]` header while `nmae` sits lines below, so the reader cannot always match the two by eye. It reuses the W1001 → E1200/E1052 pattern, so it adds no new rule. The note names the errors by fault; giving the missing-key and no-source errors codes is a separate chore and must not block this.
    > **Concern:** The later errors have no code or catalog row, so the spec text can name them only by fault until that chore lands.

  - Q4 no key diagnostic inside a W1001 section — **Yes**

    > **Reasoning:** It already follows from the rule: an unknown section has no fixed key set, so none of its keys can be "unknown". One clause in the spec makes that explicit and stops a cascade of warnings under one misspelled header.
    > **Concern:** None of substance; the risk is only an implementation that checks keys before it checks the header.

  - Q5 every unknown key reported, in source order — **Yes**

    > **Reasoning:** E0842 already says each bad key is reported, not only the first, so this is the same rule and no addition. Source order keeps the "same input, same output" promise in *Conventions*.
    > **Concern:** None; the walk must just not return early after the first key.

  - Q6 toolchain-version note — **V0**

    > **Reasoning:** Under W the build continues, so an upgrade hint has nothing to work around. The toolchain cannot tell a typo from a future key, so "a newer Blink may define this" can prescribe a repair that does not exist (§3.1, as plt says). It is the one variation that adds new diagnostic text with no evidence that users need it; YAGNI until the `edition`-newer-than-toolchain follow-up sets how the toolchain talks about newer schemas.
    > **Concern:** A user on an old toolchain who meets a real new key (`rev`) with no near candidate sees only "not a key", with no hint that an upgrade fixes it.

Result after Phase C: Q3, Q4 and Q5 passed 6-0 and stay decided. Q1 (3-3), Q2 (4-2) and Q6 (4-2) went to Phase D.

#### Phase D — Q1, Q2 and Q6

One focused round on the three open questions. Web/Scripting, AI/ML and Minimalism moved from W to S on Q1. Web/Scripting's Q1 vote depended on Q2, and Q2 had failed. AI/ML's own Phase C concern said that agents stop reading output once a build passes. Minimalism found that its W1001 analogy fails: a lost section is loud later, and a lost entry field is silent. On Q6, Systems, Web/Scripting, PLT and DevOps/Tooling moved from V1 to V0 on AI/ML's point that keys with no near candidate are mostly copied from Cargo, npm and pyproject (`default-features`, `optional`, `authors`).

| Question | Result |
|---|---|
| Q1 severity | **S 6-0** after 3-3 |
| Q2 lockfile clause | **No 4-2** (Systems *(dissent)*, Web/Scripting *(dissent)*); moot under S |
| Q6 version note | **V0 6-0** after 4-2 |

Each seat's vote line and first paragraph of reasoning for each question:

- **Systems:**

  - Q1 — I stay on S

    > web: "S makes the severity depend on which table holds the key, which a newcomer cannot work out from the message."
    > The newcomer does not need to work it out: the message says `error`, names the entry and gives a did-you-mean. The
    > severity is visible in the first word. What the newcomer cannot work out under W is that the build that just passed
    > links dynamically, or skipped the layout check.

    > D VOTE Q1: S — concern: if W wins, `heders`, `lnik` and `tga` typos ship as warnings by default, so the spec must at

  - Q2 — Yes (no change)

    > devops: "the clause makes the same manifest fail on a fresh clone and pass with an old lock". With an old lock, the
    > build is correct: it uses the pinned commit, so nothing is wrong to report. With no lock, the clause stops a wrong
    > commit from being pinned. That difference is the point, not a hidden severity. I accept that the error must name the
    > entry and the W1002 above it (web's concern). It has effect only if W wins, and then it is the only guard left for
    > `tag` and `branch`.

    > D VOTE Q2: Yes — concern: if it passes, the lockfile error must name the entry and the W1002, or the user sees "no

  - Q6 — I move to V0

    > aiml: "The keys with no near candidate are mostly not keys from a newer Blink; they are keys copied from Cargo, npm
    > and pyproject (`authors`, `keywords`, `default-features`, `optional`)". That is correct, and it is worst on the error
    > I want. Under S, `default-features = false` in a dependency entry gets E1014. A note that says "a newer Blink may
    > define this key" tells the user to upgrade, when the fix is to delete the key. V1-E puts the note exactly there. min is
    > also right that the `edition`-newer-than-toolchain follow-up is the correct place to decide how the toolchain talks
    > about newer schemas. V0 now; that follow-up can add a version note with a real signal (an `edition` the toolchain
    > does not know), not a guess from "no near key".

    > D VOTE Q6: V0 — concern: a user on an old toolchain with a newer manifest gets an unknown-key diagnostic with no hint

- **Web/Scripting:**

  - Q1: I move from W to S

    > My Phase C vote for W depended on Q2. My own reasoning said the `tga` harm "is better closed at the lockfile write
    > (Q2) than by a second severity", and my concern said: "If Q2 fails, `heders`, `lnik` and `tga` typos stay warnings
    > that a CI with no `--strict` lets through." Q2 is now No 4-2, and plt, devops, aiml and min give sound reasons
    > against it. That leaves W with no guard on the one case where a typo builds a different program and passes.

    > D VOTE Q1: S — concern: the spec must state the split in one sentence ("fields that pick a build input are errors; other unknown keys warn") or users will read it as arbitrary.

  - Q2: Yes (only has effect under W)

    > If S wins this is moot. If W wins, I still want a guard on the lockfile write rather than none. I accept the
    > objections about the hidden severity; I weigh them below a committed wrong commit.

    > D VOTE Q2: Yes — concern: under W, the `error:` line must name the entry and point at the W1002, or users read "no lockfile" with no cause.

  - Q6: I move from V1-W to V0

    > aiml's point decides it for me, and it is a web-seat point: "The keys with no near candidate are mostly not keys
    > from a newer Blink; they are keys copied from Cargo, npm and pyproject (`authors`, `keywords`, `default-features`,
    > `optional`)." Copying from a known manifest is the 90% case for a JS or Rust dev writing their first `blink.toml`.
    > "A newer Blink may define `keywords`" tells that user to upgrade, or to keep a key that will never work. That is
    > the wrong repair for most readers. Under S the note would sit on an error and send people to upgrade a toolchain
    > for `default-features`. Leave the message as "no key `X`" plus the list of allowed keys, and let the `edition`
    > follow-up decide how the toolchain talks about newer schemas.

    > D VOTE Q6: V0 — concern: a user on an older toolchain who meets a real new key gets no upgrade hint, so the release notes for each new key must say which version added it.

- **PLT:**

  - Q1 — I stay on S

    > aiml: "the panel itself moved the line during B1 (`edition` in `[package]`), so a model cannot predict it from the
    > file." The line did not move. What moved was my reason for one table. The S line is visible in the file: a key
    > inside a dependency or native-dependency **entry** (an inline table under `[dependencies]`, `[dev-dependencies]`
    > or `[native-dependencies]`) is an error. A key in a top-level section (`[package]`, `[capabilities]`) is a warning.
    > A reader or a model needs one fact to apply that rule, and the fact is the shape of the line: `name = { ... }`.
    > `edition` is a hole on the warning side, and I accepted it. A hole on one side does not make the rule
    > unpredictable.

    > D VOTE Q1: S — concern: `edition` in `[package]` stays a promotable warning, so a typo there changes the edition rules with no hard stop.

  - Q2 — No

    > Same reason as in Phase C: the result depends on repo state, and the error at the end names the lockfile, not
    > the key at fault. sys and web vote Yes as a fallback under W. If W wins, I prefer an honest warning to a hidden
    > error.

    > D VOTE Q2: No — concern: if W wins, a `tga` typo can pin the wrong commit into `blink.lock` behind only a warning.

  - Q6 — I move from V1-E to V0

    > aiml: "The keys with no near candidate are mostly not keys from a newer Blink; they are keys copied from Cargo,
    > npm and pyproject (`authors`, `keywords`, `default-features`, `optional`)". This is a counterexample to my own
    > condition. I assumed "no near candidate" meant "future key". `optional = true` in a dependency entry (Cargo) has
    > no near candidate in the entry record. Under V1-E, the note on it would suggest an upgrade, and the right repair
    > is to remove the key. A note that is wrong in the most common case breaks §3.1, even if it says "may". The
    > compiler cannot tell the two cases apart, so the note must not guess. min's point also stands: how the
    > toolchain talks about a newer schema belongs to the `edition`-newer-than-toolchain follow-up.

    > D VOTE Q6: V0 — concern: a user who does have a manifest from a newer Blink gets only "no key `rev`", with no hint, until the edition follow-up adds one.

- **DevOps/Tooling:**

  - Q1 — I hold S

    > web: "S makes the severity depend on which table holds the key, which a newcomer cannot work out from the message."
    > The message can say it. Under S the error text names the table kind and the reason in one line, as plt-1 drafted:
    > "`= note: an unknown field changes which source is fetched, so it is never ignored`". A newcomer reads why in the
    > diagnostic, not in the spec. Severity that the message explains is not a hidden rule.

    > D VOTE Q1: S — concern: the error text must state why an entry field is never ignored, or web's "newcomer cannot work out the severity" point holds.

  - Q2 — I hold No

    > Same reason as Phase C: the clause is a third severity under the label `warning`, and its failing line has no code
    > and is a separate message from the W1002 that caused it (plt and aiml say the same). If the panel wants entries to
    > stop the build, Q1 = S is the place to say it.

    > D VOTE Q2: No — concern: if W wins Q1, the spec has no guard on a wrong pinned commit except `--strict`, so §8.9.8 should say CI runs with it.

  - Q6 — I move to V0

    > aiml: "The keys with no near candidate are mostly not keys from a newer Blink; they are keys copied from Cargo, npm and
    > pyproject (`authors`, `keywords`, `default-features`, `optional`)". I accept this. My B1 case was `rev` and `branch`,
    > but `default-features` and `optional` in a dependency entry are the more likely no-candidate keys, and "a newer Blink
    > may define `default-features`" sends the user to upgrade instead of deleting the key. That is a wrong repair hint,
    > which is worse than no hint. min is right that the upgrade message belongs to the `edition`-newer-than-toolchain
    > follow-up, where the toolchain can know the schema is newer instead of guessing.

    > D VOTE Q6: V0 — concern: a user who meets a real key from a newer Blink gets only "unknown key" until the edition follow-up gives an upgrade message.

- **AI/ML:**

  - Q1: I move from W to S

    > My own Phase C concern is the best argument against my vote: "LLM agents tend to stop reading output once a build
    > passes, so a `tga` or `heders` warning may be seen by no one unless agent harnesses run with `--strict`." I cannot
    > make every agent harness pass `--strict`. A spec rule that is safe only when the harness sets a flag is not safe for
    > the largest class of manifest authors my seat speaks for.

    > D VOTE Q1: S — concern: the `edition` hole in `[package]` stays a warning, so a dropped `edtion` still changes defaults with only a printed line.

  - Q2: No

    > Under S it has no effect. If W wins, I still oppose it for the B1/C reason: a warning that refuses a lockfile write
    > is an error under a warning's name, and the "lockfile not written" line has no code an agent can look up.

    > D VOTE Q2: No — concern: if W wins without it, a dropped `tag` can freeze the wrong commit into `blink.lock`.

  - Q6: V0

    > Every V1 form prints only when there is no near key. Under S that is exactly the copied-Cargo case in dependency
    > entries: `default-features`, `optional`, `package` have no near Blink key. V1-E would print "a newer Blink may define
    > `default-features`" on the most common AI error in that table, and steer the model to upgrade or keep the key instead
    > of removing it. Reply to plt: "the note must be worded as "may", never as the repair in `help:`." The word "may" is
    > the problem: to a model it reads as "this key is plausibly valid". If the panel later wants a version line, the
    > `edition`-newer-than-toolchain follow-up can add one that states facts ("this toolchain is 0.57.0 and does not
    > define `rev`"), not a guess.

    > D VOTE Q6: V0 — concern: a real forward-compat key (`rev` on an old toolchain) gets an error with no hint that an upgrade is the fix.

- **Minimalism:**

  - Q1: I move from W to S

    > I voted W in Phase C. I change it, and I state why, because the reason is a flaw in my own argument, not pressure from the count.

    > D VOTE Q1: S — concern: the `[package]` `edition` key stays a warning under S, so `edtion = "2024"` still builds under the latest edition unless `--strict` is on.

  - Q2: No

    > Under S it has no effect. Under W I still oppose it for the reasons in C: a warning with a side effect that fails a fresh clone and passes with an old lock.

    > D VOTE Q2: No — concern: if W wins after all, nothing stops a `tga` typo from pinning the wrong commit in `blink.lock`.

  - Q6: V0

    > aiml's point decides it for me: "The keys with no near candidate are mostly not keys from a newer Blink; they are keys copied from Cargo, npm and pyproject (`authors`, `keywords`, `default-features`, `optional`)". Under S, V1-E would put "a newer Blink may define `default-features`" on an error, which sends the user to upgrade instead of removing the key. The toolchain cannot tell a borrowed key from a future one, so the note guesses, and a diagnostic that guesses a repair breaks §3.1. Leave it to the edition-newer-than-toolchain follow-up.

    > D VOTE Q6: V0 — concern: a user on an old toolchain who writes a real new entry field (`rev`) gets an error with no hint that an upgrade would fix it.

The Q2 dissent (Systems, Web/Scripting) is moot under S.

### Final Spec

```toml
[package]
name = "x"
version = "0.1.0"
nmae = "y"                    # warning[UnknownManifestKey]

[dependencies]
internal/lib = { git = "https://github.com/org/lib.git", tga = "v1.0" }   # error[UnknownDependencyField]
```

```
warning[UnknownManifestKey]: `[package]` has no key `nmae`
 --> blink.toml:4:1
  |
4 | nmae = "y"
  | ^^^^
  = help: did you mean `name`?

error[UnknownDependencyField]: dependency entry has no field `tga`
 --> blink.toml:7:58
  |
7 | internal/lib = { git = "https://github.com/org/lib.git", tga = "v1.0" }
  |                                                          ^^^
  = help: did you mean `tag`?
  = note: an unknown field changes what is built, so it is never ignored
```

Locked points:

- The closed tables are `[package]`, `[capabilities]`, each dependency entry and each native-dependency entry. Their keys are the keys that §8.9.3 and §9.1.2 list. The keys of `[dependencies]`, `[dev-dependencies]`, `[native-dependencies]`, `[alternatives]` and `[lints]` are names; their own checks apply and this rule does not.
- A field that picks a build input is an error. Other unknown keys are warnings (Web/Scripting's concern: say the split in one sentence).
- An unknown key in `[package]` or `[capabilities]` is the warning `UnknownManifestKey` (W1002). It is promotable by `--strict` and `[lints]`, as W1001 is.
- An unknown field in a dependency entry or a native-dependency entry is the error `UnknownDependencyField` (E1014). No `[lints]` entry changes it. The message carries one `note:` that says why an unknown field is never ignored (DevOps/Tooling's concern).
- Both diagnostics span the key. The help line offers the nearest key of the same table; a key of another table is never a candidate.
- A new entry field is added to the specification before any toolchain reads it, as `version` was. An older toolchain stops on a field it cannot honour (PLT's text, §8.9.7).
- `edition` in `[package]` stays a promotable warning (PLT, AI/ML and Minimalism's concern). There is no third rule for one key.
- When `[package]` lacks a required key and W1002 fired in `[package]`, the missing-key error adds a `note:` that points at the unknown key (Q3). The error has no code yet, so the text names it by its fault.
- A section that W1001 reports gets no key diagnostic. The section check comes first. This holds also for a section that a dotted top-level key opens (Q4).
- Each unknown key gets its own diagnostic, in source order. The toolchain checks the whole manifest before the load fails on E1014 (Q5).
- No toolchain-version note (Q6). The lockfile clause (Q2) is not in the specification.

### Implementation notes

These are not spec text.

- The manifest key walk visits each closed table once: `[package]`, `[capabilities]`, each dependency entry and each native-dependency entry. The candidate list of a table is the field list of that table only. The walk for W1001 in `lib/pkg/manifest.bl` is the place to extend.
- Add constants and catalog rows for W1002 and E1014. E1014 is not suppressible by `[lints]`, as for E0842.
- Skip the key walk for a section that W1001 reports, including a section that a dotted top-level key opens. Run the section check first (PLT, DevOps/Tooling).
- Collect all keys, in source order, and then fail the load on E1014. Do not return at the first bad key (PLT, DevOps/Tooling, Minimalism).
- The missing-required-key error adds the `note:` at the unknown key when W1002 fired in `[package]`. Today that error is a bare message with no code (`lib/pkg/manifest.bl`).
- Tests, one for each case: an unknown key in `[package]`; in `[capabilities]`; in a dependency entry; in a native-dependency entry; each code; no cascade under a W1001 section; several unknown keys in source order; the missing-key `note:`; `--strict` promotes W1002; a `[lints]` entry promotes W1002; a `[lints]` entry cannot lower E1014; a key of another table is not a candidate.

### Known gaps and follow-ups

- `edtion` is a typo in `[package]` and stays a warning. A dropped `edition` changes the edition rules with no hard stop unless `--strict` is on. PLT, AI/ML and Minimalism named this in Phase D. It goes with the existing edition follow-up in decisions/lexer-and-manifest-diagnostic-codes.md.
- Codes and catalog rows for three errors: a missing required `[package]` key, "Combining sources is an error" (§8.9.3), and a dependency with no source. The specification does not say that a dependency with no source is an error.
- How a toolchain reports a key or an `edition` from a newer Blink goes with the existing follow-up on an `edition` newer than the toolchain. Q6 left it there: a note cannot tell a key from a newer Blink from a key copied from Cargo.
- A reserved `[tool.<name>]` table that never warns stays open (decisions/lexer-and-manifest-diagnostic-codes.md).
