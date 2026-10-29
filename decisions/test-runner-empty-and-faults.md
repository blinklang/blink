[< All Decisions](../DECISIONS.md)

# Test Runner: Empty Selections and Runner Faults — Design Rationale

**Question.** What does `blink test <path>` do when the path holds no test file, or does not exist? Which files does a directory walk pick? What outcome does a file get when the runner loses its result, or cannot start or wait for its test binary?

**Answer.** A directory with no test file, and a path that does not exist, are usage errors: exit 2, text on standard error, no `test`, `file` or `run` line. A file that you name is taken as given. A directory walk skips names that start with `.` and the `build/` directory at the project root. A runner fault on one file (E0856, I0016) is `aborted` with a fourth cause key, `diagnostics`, a list that holds exactly one diagnostic with no `span`.

### Panel Deliberation

Six seats voted: Systems, Web/Scripting, PLT, DevOps/Tooling, AI/ML and Minimalism. Where a quote has a "[...]", the quote skips text. Phase D ran for Q2 only.

#### Phase A — Independent proposals

Both gaps were open. Gap 1: the path with no test file. Gap 2: the runner fault on one file.

- **Systems.** Gap 1: "Rule: when the runner resolves its path arguments to an empty set of files, that is a usage error." Gap 2: "`build_failed` is a false statement about what happened."
- **Web/Scripting.** Gap 1: "The user named the file, so the runner did what it was told." Gap 2: "`build_failed` is a lie here. The file DID build."
- **PLT.** Gap 1: "The command's precondition is that the path names tests, and a broken precondition is a usage error, not a result." Gap 2: "Each constructor of a closed sum must state a true fact."
- **DevOps/Tooling.** Gap 1: "Exit 0 with files.total 0 is the worst choice from a tooling seat: a typo in a CI path turns green forever." Gap 2: "Why not build_failed (the interim pick): it lies. The file DID build."
- **AI/ML.** Gap 1: "Exit 0 for a wrong path is the worst result: the agent says \"all tests pass\" and moves on." Gap 2: "`aborted` already means \"the test binary did not report the end of its run\"."
- **Minimalism.** Gap 1: "I reject \"change nothing, exit 0 with files.total 0\". It reads cleanly off the formula, but a CI job with a typo in its path then goes green with no tests run." Gap 2: "The closed enum is an API that every consumer switches on, so a fourth value is a breaking change for each of them."

#### Phase B — Debate highlights

- **Several paths.** Systems, Web/Scripting and PLT proposed the rule that won. Web/Scripting: "a typo in one path of three is still a bad command". AI/ML took it: "An agent that writes `blink test src/ tset/` must not get exit 0."
- **The skip list split.** PLT: "Names that start with `.` and the project's own `build/` dir: spec them." Systems split it the same way and asked that `// xtest` get its own ticket. Minimalism took the subtraction side: "the spec states only the predicate plus \"names that start with `.` are skipped\"". AI/ML: "Leaving them unstated is the one result I reject."
- **`--filter` and `--tag` that match no test (V3).** Deferred. Web/Scripting: "defer to a separate ticket, as aiml says". DevOps/Tooling: "I withdraw it from this round." The seats agreed it is not a usage error.
- **A stderr note for a named file with no test block (V4).** Left to the CLI. DevOps/Tooling withdrew it: "withdrawn. The `file` line already shows total 0, and nobody else wants it." PLT: "not in the spec."
- **Web/Scripting moved from `error` to `diagnostics`.** "I move from `error` (one object) to `diagnostics` (an array holding one diagnostic), as aiml and devops D2-alt proposed. Reason: `build_failed` already uses `diagnostics`."
- **DevOps/Tooling withdrew Option B (a fourth outcome).** "I move from B (`runner_error` outcome) to A, my own fallback. plt's argument settled it: \"Two constructors with the same elimination rule are one constructor with a tag.\""
- **Minimalism withdrew Option C (split by whether the binary started).** "I drop C and vote A." And: "Blurring a meaning is a real cost even when the surface does not grow, so I was wrong to count it as free."

All six seats ended Phase B with "stable, ready to vote".

#### Phase C — Final vote

Each seat voted on four questions. Q1: an empty selection or a missing path is a usage error. Q2: the directory-walk skip list, with four options: (a) spec `.` and `build/`, the CLI drops `legacy`, `node_modules` and `// xtest`; (b) the same, but `// xtest` goes to its own ticket; (c) spec only `.`; (d) spec nothing about skips now. Q3: a runner fault is `aborted`. Q4: the name and shape of the fourth cause key, with three options: K1 `diagnostics` (a list), K2 `diagnostic` (one object), K3 `runner_error` (one object). The quotes are the seats' own vote replies.

##### Q1. An empty selection or a missing path is a usage error (Yes 6-0)

- **Systems: Yes.** "It keeps the exits to the closed set {0,1,2} and keeps \"a usage error stops before any file builds\" true."
- **Web/Scripting: Yes.** "A typo in a CI path must never go green, and with several paths that holds for each path, not only for the union."
- **PLT: Yes.** "Selecting the files is a static step that happens before any build, and the usage-error class is \"fails before any file builds\"."
- **DevOps/Tooling: Yes.** "Exit 2 with one line on stderr is the clearest signal for a CI job with a wrong path, and it keeps the closed exit set {0,1,2}."
- **AI/ML: Yes.** "The rule takes one sentence: a directory is searched for test files, and a file you name is taken as given."
- **Minimalism: Yes.** "It closes the CI hole and adds nothing."

##### Q2. The directory-walk skip list ((a) 3, (b) 2, (c) 1 in Phase C)

- **Systems: (b).** "Names that start with `.` and the `build/` output dir belong in the spec."
- **Web/Scripting: (a).** "`legacy`, `node_modules` and `// xtest` are repo policy."
- **PLT: (a).** "A skip rule is part of what `blink test dir/` means, so each one must be either spec text or gone."
- **DevOps/Tooling: (b).** "`.` and `build/` are safe to spec"
- **AI/ML: (a).** "The spec should hold every rule that changes which tests run."
- **Minimalism: (c).** "The spec then holds one skip rule, the hidden-name rule every tool already follows"

No option had a majority, so Phase D ran for Q2.

##### Q3. A runner fault is `aborted` (Yes 6-0)

- **Systems: Yes.** "In all three cases, what the runner saw fits the existing `aborted` row: the binary did not report the end of its run."
- **Web/Scripting: Yes.** "A user reads `aborted` as \"this file's run did not finish\", which is true in all three cases."
- **PLT: Yes.** "So it is the same constructor with one more cause tag, not a new outcome."
- **DevOps/Tooling: Yes.** "The file did build, so `build_failed` sends the user to look for a compile error that does not exist."
- **AI/ML: Yes.** "`build_failed` keeps one meaning an agent can act on: fix the build."
- **Minimalism: Yes.** "It keeps `build_failed` true to its name, which I underweighted in Phase A."

##### Q4. The fourth cause key (K1 5-1)

- **Systems: K1.** "With one key name and one element type for every diagnostic on a `file` line, a consumer decodes it with one path and no new struct."
- **Web/Scripting: K1.** "Use one key and one shape for the same kind of data in both outcomes."
- **PLT: K2 (dissent).** "K1's array admits 0 or 2 entries, states the rule must then forbid, while a singular object makes them impossible."
- **DevOps/Tooling: K1.** "The same key and element shape as `build_failed` lets a consumer, an LSP or a CI annotator show the diagnostic with the code it already has"
- **AI/ML: K1.** "With one key name for diagnostics in both outcomes, a model writes `file.diagnostics` once and it handles `build_failed` and `aborted` alike."
- **Minimalism: K1.** "It reuses a key and element shape that consumers already parse and render for `build_failed`, so it adds no new key name and no second diagnostic container."

#### Phase D — Round 2

Phase D ran for Q2 only. The seats saw two new facts. The CLI skips an entry named `build` at every depth of the walk. This repo's `build/` holds 1289 `.bl` files, and none has a top-level `test` block. The quotes are the seats' own replies.

- **Systems: (a), changed from (b).** "plt's point convinces me: \"(b)'s 'the CLI keeps it' leaves the very gap this round closes.\"" And: "the spec should name the project's output dir, `build/` at the project root, and not every dir named `build`."
- **Web/Scripting: (a), no change.** "The spec should skip only the project's own output dir: `build/` at the walk root (or the project root). It should not skip any dir named `build`."
- **PLT: (c), changed from (a) (dissent).** "Spec'd that way, the rule would silently hide a user's own source dir named `build/`, for example `src/build/`." And: "A rule that changes no meaning does not belong in the spec."
- **DevOps/Tooling: (a), changed from (b).** "plt's point is the one I cannot answer". Condition: "the chore migrates the 9 `// xtest` files (move, fix or delete with the owner's consent) BEFORE it drops the skip."
- **AI/ML: (a), no change.** "`build/` is the tool's own dir, and users expect a walk to skip it."
- **Minimalism: (a), changed from (c).** "Skipping your own output dir is not cruft: cargo skips `target/`, for example." And: "The spec text for (a) must name the project's own output dir, the `build/` at the project root, and not every entry named `build`."

Result: **(a) 5-1**, PLT **(dissent)** for (c). Every (a) voter set the same condition: `build/` means only the project-root output dir, and the chore migrates the 9 `// xtest` files before it drops that skip.

### Final Spec

```sh
blink test empty/               # exit 2; stdout empty, also with --json
blink test missing/             # exit 2
blink test a/ missing/          # exit 2, although a/ holds tests
blink test notests/lib.bl       # exit 0: "ran", total 0
blink test notests/             # exit 2
```

```
error: no test files in empty/ (a test file is a .bl file with a test block)
error: path not found: missing/
```

```json
{"record": "file", "file": "tests/test_net.bl", "outcome": "aborted", "diagnostics": [{"severity": "error", "name": "TestBinaryDidNotRun", "code": "E0856", "message": "could not start the test binary: EAGAIN"}], "summary": {"total": 0, "passed": 0, "failed": 0, "panicked": 0, "skipped": 0, "duration_ms": 1}}
```

- A directory with no test file, and a path that does not exist, are usage errors: exit 2, text on standard error, no `test`, `file` or `run` line.
- A directory is searched for test files. A named file is taken as given: with no `test` declaration it gives a `ran` line with total 0 and exit 0.
- With several paths, any missing path gives exit 2. An empty union gives exit 2. Otherwise the runner runs what it found. The message names every bad path.
- A test file is a `.bl` file with a top-level `test` declaration.
- A directory walk skips names that start with `.` and the `build/` directory at the project root (§10.5 *Project root discovery*). A `build` directory elsewhere is walked.
- A runner fault (E0856, I0016) is `aborted`. Exactly one of `signal`, `exit_code`, `limit` and `diagnostics` is present, and the set is closed.
- `diagnostics` on an `aborted` line holds exactly one diagnostic with no `span`. E0856 has severity `error`. I0016 has severity `ice`.
- The `test` lines written before the fault stay and count. The file counts in `files.aborted`, so the run exits 1.
- A consumer tells outcomes apart by `outcome`, not by whether `diagnostics` is present.

### Dissents

- **Q2, PLT (c).** Only names that start with `.` are in the spec.
- **Q4, PLT (K2).** A singular `diagnostic` object, so that 0 or 2 entries are impossible.

### Implementation notes

- The CLI walk today skips any dir named `build` at every depth, plus `legacy`, `node_modules` and `// xtest` files. A chore narrows `build` to the project root and drops the other three. It must first migrate the files that use `// xtest` (9 in this repo today) and check that no project-root `build/` probe holds a top-level `test` block (PLT).
- The CLI's test-file check should use the top-level `test` declaration, not a text scan (PLT).
- Today a missing path exits 1. It becomes 2.
- The I0016 and E0856 interim path writes `build_failed`. It becomes `aborted` with `diagnostics`.
- A stderr note for a named file with no test block, and `--filter` or `--tag` that match no test, are left to the CLI and to a separate ticket.
- Monorepo pressure for a `--pass-with-no-tests` flag: wait for a real request (Minimalism).
