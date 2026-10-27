[< All Decisions](../DECISIONS.md)

# Audit record resolution — Design Rationale

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) answered one question: which `audits.toml` does `@trusted(audit: K)` read, for a file in `src/`, in `tests/`, in a fixture, or in no package? Quotes are the panelists' own words. A mark `[...]` shows text left out: a source line number or a part that does not bear on the question. Words in other square brackets, such as `[the pin-key ruling]`, replace a ticket id.

#### Phase A — Independent proposals

All six proposals agreed on the base rule. A file's package root comes from its own path: the nearest `blink.toml` above it. `K` resolves only against the `audits.toml` beside that `blink.toml`. `src/`, `tests/`, `examples/` and `bench/` share that one file. There is no fixture rule. A file with no `blink.toml` above it has no records.

**Systems:**

> Make the file path absolute, then walk up from its directory and include every ancestor. The first directory with a blink.toml is the package root. The cwd is never checked on its own.

> A fixture with no blink.toml of its own, written at build/p.bl, walks up to the repo root and uses the repo audits.toml. That is correct, because the fixture really sits in that package. But the harness should not use this case for trust fixtures.

> Hermetic input set [...] audits.toml is a compile input of every file in its package [...] Under the cwd fallback, the input set depends on the process cwd. That poisons any obj-cache or check cache [...] makes the LSP [...] disagree with `blink check`.

> a script with no package fails closed (E0829), not open.

Systems rejected `tests/blink.toml` (it would break the 464 imports of compiler modules in `tests/`), a fixture rule ("users' tools would inherit a magic directory") and the cwd for `K` only.

**Web/scripting:**

> K resolves from WHERE THE FILE IS, never from where you ran the command, and one package has ONE audits.toml. No tests/audits.toml, no fixture rule in the spec. The fixture problem is a test-harness problem; solve it in the harness.

> by §10.5 `build/foo.bl` under the repo root IS in package "blink" [...] today it only fails to find it because the walk stops at a relative path's first segment. That is a second compiler bug: the walk must work on the absolute path.

> Node model (nearest package.json owns file) over Python sys.path cwd ("works from the repo root, breaks from tests/" papercut).

On the pin key of a file with no module name, Web proposed: "package-relative file path + ":" + fn name, e.g. "tests/test_db.bl:sqlite3_open"". Web gave a fallback (W2): a loose file reads an `audits.toml` in its own directory. It wrote: "I lean W1; I would vote W2 over any tests/audits.toml or cwd rule."

**PLT:**

> package = dir of nearest blink.toml above canonical absolute path; K only against audits.toml beside it

> A loose script simply cannot suppress W0800, the same way it cannot import an external package (E1010).

PLT said a fixture at `build/x.bl` that walks up to the repo `audits.toml` is the "correct answer under the rule, and the wrong thing for a hermetic probe". It rejected a sibling `audits.toml` because it "erodes no package = no package files, which E1010 already sets".

**DevOps:**

> Every audit diagnostic (E0829, E0830, the pin-lapse note) prints the audits.toml path it read, or says that no package was found.

Example note: "looked in /home/u/pkg/audits.toml (package `pkg`)". DevOps proposed the pin key `<path relative to package root>::<fn name>`, "Two fixtures that each declare fn main must not collide". It rejected `tests/blink.toml`, the cwd rule and a test-mode trust-all switch.

**AI/ML:**

> K resolves against <package root>/audits.toml, root = §10.5 nearest ancestor blink.toml of THE FILE, never cwd. tests/examples/bench use package root audits.toml; no tests/blink.toml. Loose script: no package, no records, @trusted(audit: K) -> E0829 with note "in no package"; removing @trusted leaves W0800 warning.

> Rejects tests/audits.toml and fixture rules (second lookup rule).

AI/ML wanted a paste-ready TOML stanza and the exact `blink audit pin K fn` command in the help.

**Minimalism:**

> no new language rule. §10.5 and §9.1 already answer every case. The cwd fallback is the only thing that makes this look open, and it is not in the spec.

> A fixture written to `build/<stem>.bl` is in no package once the fallback is gone, so its `@trusted` sites give E0829.

(Minimalism withdrew the second claim in Phase B; see below.) Minimalism rejected a sibling `audits.toml` beside a loose file: "saves the user one line of blink.toml. It does not pay for itself".

#### Phase B — Debate highlights

The moderator checked the fixture claim against the code and the spec. A walk up from `build/<stem>.bl` reaches `<repo>/blink.toml`.

**Minimalism:** "I concede. I was wrong. A walk up from build/<stem>.bl reaches <repo>/blink.toml". On a sibling `audits.toml`: "their own help text already says "or run blink init". That is the fix, and it needs no rule." On the pin key: "Deciding one key form here and the others there gives two rulings on one key grammar".

**Systems:** "The fallback removal and the absolute-path walk must land in the same change." On a sibling `audits.toml`: "One concept, one lookup, fail closed." On the import fallback: "D1, or D2 with sentence "a file has one package root, used for both imports and audit records" + bug fix before/with enforcement."

**AI/ML:** "blink check build/x.bl and blink check /abs/repo/build/x.bl can give different answers". On a scratch directory: "One audits.toml there would quietly apply to every unrelated script". On the pin key: the ruling should say a file outside `src/` is in a package, so it can have pins.

**DevOps:** withdrew its sibling-file proposal ("fn main collisions"). Asked that the ruling say a fixture under the package tree is in the package. Moved from audit-only to one rule for imports and audit records, and asked for a release note: breaking change for loose files run inside a package directory.

**PLT:** "A1 costs the script author one empty blink.toml, and E1010 already sets that price for imports." On the pin key: decide the principle here ("package-relative path + item name, never collides with module-path keys"), and leave the separator to a later ruling, because "test names can contain ':'". On the import fallback: "D1 is the ruling that guarantees they do".

**Web/scripting:** "I drop W2. All six picked A1 first, and a sibling file is a second lookup rule for a rare case. The fix for a script that wants an audit stays one command (`blink init`) and the E0829 note says so." On the pin key, Web switched to `::`: "this is pytest's node ID form (`tests/test_db.py::test_open`) [...] A single colon looks like `file:line` to editors, terminals and CI log linkers: `tests/test_db.bl:open` sits one step from `tests/test_db.bl:12`". "leaving it open blocks `blink audit pin` on every test site."

All six reported "stable, ready to vote".

#### Phase C — Final vote

**Q1. A loose file with an `audits.toml` in its own directory. A1 (no records) wins 6-0.**

- **Systems: A1.** "Packages are then the only unit that owns records, and there is one lookup, the nearest blink.toml walk. A2 adds a second unit (a bare directory) with its own discovery and pin-key rules, which doubles what the build cache and the LSP must model. The way out for a script costs one file, a blink.toml." Concern: "Script users may see E0829 as hostile and just strip @trusted. The help text must say plainly to add a blink.toml (or run `blink init`)."
- **Minimalism: A1.** "A sibling audits.toml would be a second way to find a package, and a one-line blink.toml does the same job. A2 also needs a key form based on the file name, which is one more concept. One rule (the nearest blink.toml) covers every file." Concern: "script users who add an audits.toml beside their script will get a confusing E0829, unless the note says plainly that no blink.toml was found."
- **DevOps: A1.** "with A1, one rule finds a root: walk up to blink.toml. The CLI, `blink audit check` and the LSP all use it with no special case. A2 makes a folder of scripts half a package, and two scripts in that folder that each declare `fn main` get the same pin key." Concern: "people who write scripts will see E0829 and may switch to `@allow`. That fails with E0837, so the E0829 note must say outright: "remove @trusted; W0800 stays a warning and the script runs.""
- **AI/ML: A1.** "agents write scratch scripts into shared dirs like /tmp. Under A2, one audits.toml left there would quietly suppress W0800 for every unrelated script in that dir. A1 keeps one rule, "records live beside blink.toml", and the E0829 note tells the agent what to do." Concern: "agents in a loose script will see E0829 and create a blink.toml in /tmp just to make it go away, which turns all of /tmp into a package. The help text should list "remove @trusted" as the first fix."
- **PLT: A1.** "The language should have one function from a file to its records. A2 adds a second rule that applies only when the first finds nothing, so a script's records move to another file when someone adds a blink.toml above it. Under A2 the sibling audits.toml also has no package that owns it or that pin keys are relative to. E1010 already sets "no package, no package-level files" for imports, and A1 keeps audits the same." Concern: "Script authors may find "add an empty blink.toml" an odd step, and work around it by deleting @trusted. That leaves W0800 firing as a plain warning, so the diagnostic text must make the one-file fix obvious."
- **Web/scripting: A1.** "One rule ("audits live next to blink.toml") is what a JS/Python dev can learn in five minutes; a second lookup rule for scripts adds a "which file?" question for a rare case. The repair is one command, `blink init`, and the E0829 note says so." Concern: "a scripter who drops an audits.toml beside a loose file and sees it ignored may be confused unless the note says plainly that a sibling audits.toml without a blink.toml does not count."

**Q2. Pin key for a fn or `test` block in a file with no module name. K-principle wins 5-1 (Web/scripting dissents for K-full).**

- **Systems: K-principle.** "This ruling decides which file K resolves against. It should fix only the constraint that comes from that: a package-relative path plus the item name, so the key does not change with the cwd or the checkout location, and never collides with module-path keys. The separator and the quoting of test-block names belong in one key grammar with impl methods and trait impls in [the pin-key ruling]. Fixing them piecemeal here risks a grammar that does not fit together." Concern: "[the pin-key ruling] may pick a form that fits methods but makes quoted test-block names awkward inside TOML keys, so it must test that case on purpose."
- **Minimalism: K-principle.** "In B1 I leaned toward K-defer, but F3 shows that [the pin-key ruling] does not name files outside src/. Under K-defer, tests and fixtures could end up with no way to be pinned at all. K-principle costs one sentence and leaves the whole key grammar to one ticket, which is what I wanted." Concern: "[the pin-key ruling] could pick a separator that is ugly in TOML quoting for test-block names. It must check that case, not only plain fns."
- **DevOps: K-principle.** "the key grammar gets parsed by `blink audit pin`, `blink audit check`, the LSP and any third-party CI tool, so it must be decided once and in one place, with impl methods, trait impls and inline mods. What this ruling must fix is that files outside src/ can be pinned at all, because [the pin-key ruling] does not name them today. K-principle fixes exactly that and no more." Concern: "[the pin-key ruling] might settle impl and trait keys and forget files outside src/. Its brief should list "fn and test block in a file with no module name" as an explicit case."
- **AI/ML: K-principle.** "this ruling has to say that a fn in tests/ or examples/ can be pinned, or test-site records can't exist. The key grammar belongs with impl methods, trait impls and inline mods in [the pin-key ruling]. A separator chosen here without those cases could be wrong. `blink audit pin` writes the keys, so agents rarely type them, and the cost of waiting is low." Concern: "if [the pin-key ruling] slips, the slices that record test-site pins stall on the key format, so [it] should be next in the queue."
- **PLT: K-principle.** "The test-site slice cannot pin a fn in tests/ without knowing that such a fn can be pinned, and by what identity. So K-defer leaves this ticket's purpose unmet. The separator and quoting must come from one key grammar that also covers impl methods, trait impls and inline mods. If we fix it here alone, two grammars can drift apart. The principle (package-relative path + item name, never colliding with a module-path key) is the part that determines meaning. The characters are surface syntax." Concern: "[the pin-key ruling] could pick a grammar for the path-plus-name keys that is ambiguous, because test names are free strings and Unix paths can contain ":". The non-collision clause must stay binding on that ruling."
- **Web/scripting: K-full (dissent).** "This ruling admits files with no module name and its enforcement slice needs a key now; leaving the separator open blocks `blink audit pin` on every test site until [the pin-key ruling] lands. The file-path half of the key does not depend on how impl methods are spelled, so [that ruling] can add member syntax on top of it." Concern: "if [the pin-key ruling] later picks a member syntax that reads badly after the separator chosen here, we get a key grammar that looks pieced together."

Q2b (the separator) counted only if K-full won. It did not. The votes are recorded for the later ruling: colon from Systems, Minimalism, DevOps, AI/ML and PLT; double colon from Web/scripting. This ruling fixes no separator.

**Q3. What audit diagnostics print about the file read. C1 (name the file, or say no package) wins 6-0.**

- **Systems: C1.** "The text is built only when a diagnostic fires, so it costs nothing at run time. The path that was read is the single most useful fact for a resolution bug. It makes path defects visible on sight, for example the `/src/` substring shortcut at [...], which would print the wrong audits.toml." Concern: "Absolute paths in diagnostics make golden test output depend on the machine, so tests need a path-normalizing convention (package-relative or a placeholder)."
- **Minimalism: C1.** "This ticket exists because of "which audits.toml did it read?". Naming the file is free, and it removes the question. It is diagnostic content, not a new language rule." Concern: "absolute paths in diagnostics make golden test output depend on the machine. Print the path relative to the cwd or the package."
- **DevOps: C1.** "the hard cases are the ones where a file was found but it was the wrong one: a nested examples/foo/blink.toml, a monorepo, or the wrong checkout. C2 prints nothing useful in any of them. Naming the path costs one note line and ends "it passes in CI but fails in my editor" reports. That is the same reason cargo names the manifest it used." Concern: "absolute paths in notes make expected-output test fixtures depend on the machine. Golden tests need a path-normalizing step, or the note should print the path relative to the cwd when it is under the cwd."
- **AI/ML: C1.** "the expensive agent failure is editing the wrong audits.toml: a copy in tests/, a worktree, or the cwd. Only a printed path catches that in one turn instead of a guess-and-rebuild loop. It costs one line per diagnostic." Concern: "absolute paths in diagnostics make golden-test output depend on the machine, so tests should normalize the path or the note should print it relative to the package root where possible."
- **PLT: C1.** "Which audits.toml a file reads is the observable result of the resolution rule. Printing it lets a user check the path-only rule directly, instead of guessing which package the compiler found. Confusion about that resolution is how this ticket started. The cost is one note line, and it adds no semantics." Concern: "Absolute paths in diagnostics make golden test output depend on the machine, so the note should print the path relative to the package root (or cwd) where it can."
- **Web/scripting: C1.** "When an audit error fires, the first question is "which file did you read?"; one note line answers it, the same way npm and tsc name the package.json or tsconfig they used. It costs nothing on the success path." Concern: "absolute paths in notes make golden-test output depend on the machine; print the path relative to the package root or cwd where possible."

**Q4. The cwd fallback for imports. D1 (one package root for imports and audit records; the cwd is never an input) wins 6-0.**

- **Systems: D1.** "One root per file, used for both imports and records, is the only coherent state. If K goes path-only while the import fallback stays, a /tmp file run from the repo root imports repo modules but has no records. Users can see that split, and it makes the cwd a hidden compile input for caches. The ordering clause stops enforcement from shipping into that split state." Concern: "Removing the fallback without first making the walk absolute (today it stops at ".", [...]) would silently drop every relative tests/ and build/ file out of the package, so both must land in one change."
- **Minimalism: D1.** "One package root for imports and for records is the fewest concepts. D2 lets audit enforcement ship while imports still read the cwd, so for a while a file could be in two packages at once. §10.5 already says this, so D1 adds an ordering constraint, not a new rule." Concern: "when the import fallback goes, the walk must also be fixed to check "." (F1). If it is not, fixtures under build/ lose the repo package and the corpus breaks."
- **DevOps: D1.** "D2 allows a window in which one file imports by the cwd and gets audit records by its own path. For example, `cd repo && blink run /tmp/x.bl` would get the repo's modules but none of the repo's records. That gives two answers from one tool to "which package is this file in". D1 makes one change with one release-note line." Concern: "removing the fallback breaks anyone who runs loose files from inside a package to pick up its imports, and probe tests that pass relative paths. The release notes must call this a breaking change, and the implementation must make paths absolute before the walk-up, or `tests/x.bl` stops finding `./blink.toml`."
- **AI/ML: D1.** "one package root for imports and audit records means no command can say "imports resolved" while E0829 says "no package". Agents would try to fix that split by moving audits.toml around. Stating the order removes the window D2 leaves open." Concern: "probe tests and scripts that rely on the cwd fallback today will break all at once when it goes, so the change needs a corpus sweep in the same slice."
- **PLT: D1.** "There must be one package-membership function, used by both imports and records. Otherwise one file can have in-package imports and an E0829 "no package" note at the same time. §10.5 already says the root comes from walking up from the file, so D1 adds no new rule. It removes a deviation and fixes the order, so the incoherent middle state never ships. D2 permits that middle state." Concern: "Removing the import fallback may break existing workflows or tests that compile a path outside the cwd tree and depend on the cwd's package, so the change needs a corpus sweep for files that reach their package only through the fallback."
- **Web/scripting: D1.** "A user sees one result either way, the same file compiles the same from any cwd, so one ruling with an order stated is simpler than a split rule that lingers. "Works from the repo root, breaks from tests/" is the Python sys.path trap; close it for imports and audits together." Concern: "removing the fallback before the absolute-path walk is fixed ([...] stops at the first segment of a relative path) breaks every `build/<stem>.bl` probe fixture at once."

The order of the compiler change is not part of the spec text. The votes above record it for the implementer.

### Final Spec

```blink
// pkg/tests/test_pid.bl, with pkg/blink.toml and pkg/audits.toml holding [TEST-PID]
@ffi("c", "getpid")
@trusted(audit: "TEST-PID")      // accepted: K resolves against pkg/audits.toml
fn getpid() -> Int ! IO

// /tmp/hello.bl, with /tmp/audits.toml and no blink.toml above it
@ffi("c", "puts")
@trusted(audit: "PUTS-1")        // error[E0829]: the file is in no package
fn puts(s: Ptr[U8]) -> Int ! IO
```

- A file's package root is the nearest ancestor directory with a `blink.toml`. The walk starts at the file's own path, made absolute first. The cwd is never an input.
- One package root serves imports and audit records. §10.5 states this once; §9.1 refers to it.
- `K` resolves only against the `audits.toml` beside that `blink.toml`. `src/`, `tests/`, `examples/` and `bench/` share it.
- There is no fixture rule. A file a test writes is in the package its path walks up to: `<repo>/build/x.bl` is in the repo package.
- A file with no `blink.toml` above it is in no package. Each `@trusted(audit: K)` in it is E0829. An `audits.toml` beside it does not count. Without `@trusted`, W0800 stays a warning and the script runs. `@allow` cannot replace `@trusted` (E0837).
- The E0829 help for a loose file lists "remove `@trusted`" first, then "add a blink.toml (`blink init`)".
- A fn or `test` block in a file with no module name can carry a pin. Its key is the package-relative file path plus the item name, with forward slashes and no absolute path, in a form that never equals a module-path key. The pin-key grammar sets the spelling.
- Every audit diagnostic (E0829, E0830, the note on a lapsed pin) names the `audits.toml` it read, or says the file is in no package. The path is relative to the package root.
- The help may show a record skeleton with a placeholder `claim` and the `blink audit pin K fn` command. It never fills in a claim.

| Question | Result | Dissent |
|----------|--------|---------|
| Q1 A loose file with a sibling `audits.toml` | 6-0 A1: it does not count | none |
| Q2 Pin key for a file with no module name | 5-1 K-principle | Web/scripting (K-full) |
| Q3 Audit diagnostics name the file read | 6-0 C1 | none |
| Q4 One package root for imports and records | 6-0 D1 | none |
