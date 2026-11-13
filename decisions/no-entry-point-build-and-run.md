[< All Decisions](../DECISIONS.md)

# A Program With No `fn main` — Design Rationale

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated
in independent-proposal → debate → vote rounds. Ticket IDs in the quoted text are replaced with `[ticket]`.

#### Phase A — Independent proposals

- **Systems:** (excerpt, section `G2 ([ticket]) A program with no `fn main``)

> Facts: `fn f() -> Int { 1 }` alone: check ok, build ok, binary does nothing. Empty file: check ok,
> build LinkFailed (undefined `main`), which breaks §6.7.1 because LinkFailed in §6.7.3 means a
> missing native library, not missing Blink source. 2093 of 3033 tests/test_*.bl files have no
> `fn main`, so a check-time "no main" error would hit most test files.
>
> **G2-P1 (preferred): no `main` is a library unit, Go model.**
> - `blink check`: no new error, for a file, an empty file, a non-entry module, a tests-only file
>   and a library package.
> - `blink build`: compiles every item through the C compiler to an object (this proves the code
>   builds), writes no executable, prints `note: no fn main; built no binary`, exit 0. Same for an
>   empty file (fixes today's LinkFailed). A library package builds every module the same way.
> - `blink run`: a usage error before any compile, exit 2: "`f.bl` has no `fn main`; nothing to run"
>   with help naming `blink test` and `blink build`. This is the same class as `blink test` on a
>   directory with no test file (exit 2, §8.10.5). It is not a stop of `blink build`, so §6.7.1 holds.
> - `blink test`: unchanged; the runner gives the entry point.
>
> ```blink
> // lib.bl: check exit 0, build exit 0 with the note, run exit 2, test runs the tests
> fn add(a: Int, b: Int) -> Int { a + b }
>
> test "add works" {
>     assert(add(1, 2) == 3)
> }
> ```
>
> Tradeoff: never emit a no-op binary (an exit 0 program that does nothing is a lie the user finds
> late). The object compile keeps the promise real for libraries: CI can run `blink build` on a
> library and get the C compiler's verdict, which `check` cannot give. Cost: a script that does
> `blink build x.bl && ./x` fails at `./x`; the note says why.
>
> **G2-P2: Rust model, new check error MissingMain for a file outside a package with no `fn main`
> and no test block.** Build/run then never meet the case. Weaker: the "no test block" carve-out is
> a heuristic, and a helper module checked on its own gets a false error.
>
> **G2-P3: build is an error (exit 1) with no main.** Breaks §6.7.1 unless check also errors, which
> is P2.
>
> Cross-language: Go `go build` of a non-main package compiles and discards, exit 0; Rust `rustc`
> on a bin with no main is E0601 at check. Blink has no `package main` marker, so Go's model fits.
>
> ---

- **Web/Scripting:** (excerpt, section `G2 ([ticket]): a program with no `fn main``)

> Facts that shape this: 1213 of the repo's `tests/test_*.bl` files have no `fn main`, and
> editors run `blink check` on every module. So "no main" cannot be an error in `blink check`.
> The promise (6.7.1) then forces `blink build` to succeed on it too.
>
> ### G2-P1 (PREFERRED): no `main` means "library": check and build succeed and say so; `run` refuses
>
> | Command | File/package with no `fn main` (empty file included) |
> |---|---|
> | `blink check` | Clean, exit 0. No note (editors check modules all day). |
> | `blink build` | Compiles every function (so check's promise is tested), writes no executable, prints `note: no fn main: built as a library, no binary written`, exit 0. With a near name (`mian`, `Main`, `main` in another module) the note adds ``did you mean `main`?`` |
> | `blink run` | Usage error, exit 2, before the build: `error: no fn main to run in <file>`, same did-you-mean help. |
> | `blink test` | Unchanged: runs the file's tests; main is not needed. |
>
> ```blink
> fn helper() -> Int { 1 }
> fn mian() { io.println("{helper()}") }
> // blink check: ok
> // blink build: note: no fn main: built as a library, no binary written
> //              help: did you mean `main`? (`mian` at line 2)
> // blink run:   error: no fn main to run; help: did you mean `main`? -- exit 2
> ```
>
> Tradeoffs: today's silent no-op binary that exits 0 is the worst outcome, a classic Python
> footgun (`python helpers.py` prints nothing). P1 makes it loud where it matters (`run`, the
> command a scripter types) and quiet where it is normal (check, test, library packages). The
> empty file stops being a LinkFailed and becomes the same library case. `run` is a usage error,
> not a compile error, so 6.7.1 stays true.
>
> Cross-language: `cargo run` on a lib-only crate: "a bin target must be available"; `go run` on a
> non-main package: "package is not a main package". Both are command errors, not compile errors.
>
> ### G2-P2: `blink build` errors on no main (new code, NoEntryPoint), and 6.7.1 lists it as a stop outside the promise
>
> Simpler output, but it punches a hole in the promise, and `blink build` of a library package
> then has no clean result. I reject it.
>
> ---

- **PLT:** (excerpt, section `G2. A program with no fn main`)

> Semantics first: a program means its `main`. A file with no `main` has no meaning as a
> program, so a binary that does nothing and exits 0 is a false meaning, not a default. But
> `blink check` judges a module, and a module with no `main` is a well-typed module: 2093 of the
> tests/test_*.bl files have no `main` and run under `blink test`. So the error can not be a type
> error of the text. It is an error of the command applied to the text.
>
> ### G2-P1 (preferred): no entry point is a command error of build and run
>
> - `blink check <file>` / `<package>`: no change. A file or package with no `main` checks clean
>   (an empty file too).
> - `blink test`: no change. A test build supplies its own entry (§2.20).
> - `blink build` / `blink run` on a file outside a package with no `fn main` (empty file
>   included): a usage error before any compile, exit 2, no binary. Message: "`x.bl` has no
>   `fn main`; `blink build` makes a program. Use `blink check` or `blink test`." Same class as
>   `blink test` on a path with no test file (06 section, :996, exit 2).
> - `blink build` on a library package (02_syntax.md:2734: entry module has no `main`): compiles
>   every module through codegen, writes no executable, exits 0, prints one line "library
>   `stats`: no binary". This keeps the promise in its useful form: a clean check of a library
>   still promises that its code generates.
> - `blink run` on a library package: usage error, exit 2, as for the file.
>
> ```blink
> // lib_only.bl
> fn f() -> Int { 1 }
> // blink check lib_only.bl  -> ok
> // blink build lib_only.bl  -> error: `lib_only.bl` has no `fn main` (exit 2)
>
> // app.bl
> fn f() -> Int { 1 }
> fn main() { io.println("{f()}") }
> // blink build app.bl       -> binary; prints 1
> ```
>
> Why this keeps §6.7.1: the promise is about what the text means. A usage error says the
> command does not apply to the input (the same as a path that does not exist); it is decided
> from the presence of one name, before any compile, and the compile of the text never fails.
>
> Tradeoffs: no new E-code, no change to check, test-only files keep working. The cost: the
> "no main" fact shows only at build. A user who wants it in check can run build.
>
> ### G2-P2: a check error MissingMain for a file outside a package
>
> A file outside a package is never library code (02_syntax.md:2734), so check could report E-new
> `MissingMain` there. Rejected: it breaks `blink check` on every test-only file, unless check
> learns which command will follow, which makes check's verdict depend on the caller. A judgment
> that depends on context outside the text is not compositional.
>
> ### G2-P3: keep the no-op binary
>
> Rejected: it gives a meaning to a program that has none, and the empty-file LinkFailed shows the
> current state is not even consistent.
>
> Cross-language: Rust `cargo build` on a bin crate with no `main` is error E0601 (a compile error,
> but Rust has an explicit bin/lib target split). Go: `go build` of a non-main package compiles
> and writes nothing (P1's library rule). C: link error.
>
> ---

- **DevOps:** (excerpt, section `G2 ([ticket]) a program with no `fn main``)

> A file with no `main` is a normal, legal thing to `check` and to `test`: 940 corpus files are
> test-only. So "no `main`" cannot be a check error on the file. It is an error of the *command*:
> `build` and `run` ask for an executable, and there is no entry point.
>
> **G2-P1 (preferred): `blink check` and `blink test` accept it; `blink build` and `blink run`
> reject it before any compile, with a new code `NoEntryPoint` (next free E0xxx in the module
> range).**
>
> ```blink
> // util.bl
> fn f() -> Int { 1 }
> test "f is one" { assert_eq(f(), 1) }
> ```
>
> ```
> $ blink check util.bl        ok: util.bl
> $ blink test util.bl         1 passed
> $ blink build util.bl
> error[E0xxx]: `util.bl` has no `fn main`, so there is nothing to build
>   --> util.bl:1:1
>   = help: add `fn main() { ... }`, or run its tests with `blink test util.bl`
> $ echo $?                    1
> ```
>
> An empty file: same error. A library package (`src/stats.bl` has no `main`): `blink build` gives
> the same code with the note already in 02_syntax.md:2754 ("package `stats` is a library");
> `check` and `test` are clean. No binary is written in any error case; no no-op binary ever.
>
> The promise (6.7.1): this is not a check-accepts/build-fails split, because check never claims a
> program is an executable. The writer should say so in 6.7.1: the promise covers a build of a
> unit that has an entry point; a command whose target has none fails before the compile.
> The LSP never shows it (it is not a property of the text); `blink build --json` gives it the
> normal diagnostic shape so CI tooling parses it.
>
> **G2-P2: check reports W-new `NoEntryPoint` when a file outside a package has neither `main`
> nor a `test` block.** Catches the "I forgot main" case in the editor. I would add it only after
> P1, and only if users ask; it is noise for scratch files.
>
> **G2-P3 (today): no-op binary, exit 0.** Silent success is the worst result a build tool can
> give. Against.
>
> Cross-language: `go build` of a non-main package compiles and writes nothing; `go run` of one is
> `package x is not a main package`. Cargo: `cargo run` on a lib crate is "a bin target must be
> available". P1 matches both.
>
> ---

- **AI/ML:** (excerpt, section `G2: a program with no fn main`)

> ### G2-P1 (PREFERRED): no main means "library build"; only `run` needs main
>
> - `blink check` (file or package, with or without main, empty file too): no error from the
>   missing main.
> - `blink build` with no `fn main`: type-checks and compiles every module to C and objects, writes
>   no executable, prints `note: no fn main: compiled as a library, no binary written`, exit 0.
>   The empty file gets the same (today's LinkFailed is a bug). The promise holds: check clean,
>   build clean.
> - `blink run` with no `fn main`: new code `MissingMain`, exit 1, nothing runs. Help: `add fn
>   main() { }`; when a fn named `Main`, `main_`, `start` or a `pub fn main` in another module
>   exists, a `did you mean` note. `run` is not under the promise; it is build plus an entry point.
> - `blink test`: unchanged; test blocks need no main.
> - The silent no-op binary (exit 0, no output) goes away.
>
> ```blink
> // lib.bl
> fn add(a: Int, b: Int) -> Int { a + b }
> test "add" { assert(add(1, 2) == 3) }
> // blink check lib.bl  -> ok
> // blink test lib.bl   -> 1 passed
> // blink build lib.bl  -> note: no fn main: compiled as a library, no binary written; exit 0
> // blink run lib.bl    -> error[MissingMain]: `lib.bl` has no `fn main`; exit 1
> ```
>
> Tradeoffs (AI): the no-op binary is the worst case for an agent: it forgets `main` (or writes
> `fn Main`), runs, sees exit 0 and no output, and reports success. P1 makes the `run` loop loud,
> and an agent that runs `./lib` after a library build gets "not found", also loud. Check stays
> quiet on helper modules and test-only scratch files, which agents write all the time; no new
> decision about whether a file "is an app". One rule to learn: `main` makes an executable.
>
> Cross-language: Go does exactly this: `go build` of a non-main package compiles and discards;
> `go run` says "package is not a main package".
>
> ### G2-P2: Rust style: MissingMain at check for any target that is not a library package
>
> A lone file or an application package with no main is an error in check and build; a library
> package (02_syntax.md:2734) is exempt. Cost: `blink check helper.bl` and test-only files fail,
> unless test blocks exempt them, which is one more decision point. Rust's E0601 works because
> Cargo states the crate kind in the manifest; a lone Blink file states nothing.
>
> ---

- **Minimalism:** (excerpt, section `G2 ([ticket]) No fn main`)

> Constraint I weigh most: `blink check` runs on every helper file (editor, LSP, `blink check
> src/util.bl`). A helper file has no main and is not wrong. So check cannot make "no main" an
> error, and by the Promise build then may not fail for it either.
>
> ### G2-P1 (PREFERRED): no main means "library": build compiles it and writes no binary
>
> - `blink check` on a file or package with no `fn main`: judges it as library code; clean if
>   the code is clean. An empty file is clean.
> - `blink build` on it: does the whole compile (through the C compile, so a build-only fault
>   still shows), writes no binary, prints `note: no fn main; compiled as a library, no binary
>   written`, exits 0. No more no-op binaries, no more LinkFailed on an empty file.
> - `blink run` on it: a command error before any compile, exit 2: `error: no fn main to run`.
>   If a top-level fn is one edit from `main` (`mian`, `Main`), a help names it. This is a usage
>   error of the command, not a source diagnostic, so the Promise (which speaks of build) holds.
> - `blink test`: runs the test blocks; main is not needed (as today).
>
> ```blink
> // util.bl
> fn double(x: Int) -> Int { x * 2 }
> // blink check util.bl  -> ok
> // blink build util.bl  -> note: no fn main; compiled as a library, no binary written (exit 0)
> // blink run util.bl    -> error: no `fn main` to run (exit 2)
>
> fn mian() { io.println("hi") }
> // blink run -> error: no `fn main` to run
> //              help: did you mean to name `mian` as `main`?
> ```
>
> Tradeoffs: no new diagnostic code, one consistent meaning ("no main = library", which
> 02_syntax.md:2734 already uses for packages); a lone file follows the same rule. Cost: a typo
> in `main` is found at `run`, not at `build`; the note at build still shows it.
>
> Cross-language: Go `go build` on a non-main package compiles and discards, exit 0; `go run`
> refuses. Rust needs a `[lib]` vs `[[bin]]` target; Blink has no targets, so infer from main.
>
> ### G2-P2 (rejected): new error MissingMain at check for a file outside a package
>
> Breaks check on helper files and in the LSP, or needs a "this file is a root" flag that check
> does not have today.
>
> ---

#### Phase B — Debate highlights

- **Systems:** (excerpt)

> ## G2: keep G2-L, variation L1 (run = usage error, exit 2). No change.
>
> Against G2-E and G2-P on `blink build`: whether a file has `fn main` is a fact of the source, and
> `blink check` saw that source. A build that stops on it, with exit 1 (E) or exit 2 (P), is a stop
> of `blink build` after a clean check for a cause inside the Blink source. §6.7.3's list of causes
> is closed and does not hold it, so §6.7.1 breaks. To keep the promise, E and P would need check to
> report it too, and check cannot: 2093 of 3033 tests/test_*.bl have no main. L is the only option
> where build never stops on a clean check. `blink run` is not covered by the promise, so refusing
> there is free.
>
> Against P's file/package split: a file and a library package with the same items get two
> different results from one command. One rule: no main, no binary.
>
> Systems point for L: build compiles the C to an object, so CI gets the C compiler's verdict on a
> library. E and P give no way to prove a library builds short of a fake `main`.
>
> L1 vs L2: weak preference for exit 2 (same class as `blink test` on a directory with no test
> file). The did-you-mean help (`mian`, `Main`) is good in either; writer note.

- **Web/Scripting:** (excerpt)

> ## G2: I move from L1 to G2-P (plt). L1 is my second choice. I oppose G2-E.
>
> - Position: a file outside a package with no `fn main` (an empty file too): `check` is clean, `test` runs as now, and `build`/`run` give a usage error with exit 2 and no binary. A library package: `build` compiles every module, writes no binary, prints one line and exits 0. `run` gives a usage error with exit 2. Add a did-you-mean help (`mian`, `Main`) to every one of these errors.
> - Why I changed: a loose file is "never library code" (02_syntax.md:2734). The only intent behind `blink build x.bl` on such a file is "make me a program". Under L, a `mian` typo gives exit 0 at build, and a CI script fails later at `./x` with "no such file". That is a worse place for the error. P fails at the command the user typed and keeps exit 0 for real libraries.
> - Against E: a library package build becomes an exit-1 error, so CI has no clean way to compile a library. E also needs the 6.7.1 promise text amended. A usage error (exit 2, before any compile) has the same class as `blink test` on a path with no test file, and it leaves the promise as it is.
> - On (b), exit 2 or a code: I prefer exit 2. aiml's point about JSON is fair, so the usage error should still have a stable machine-readable shape with `--json`. That is a writer note.

- **PLT:** (excerpt)

> ## G2: change to G2-L1 (from G2-P)
>
> Position: no main gives a library build. check is clean. build compiles every module through
> codegen, writes no binary, prints a note, and exits 0. This applies to a file and to a package
> alike. run is a usage error with exit 2, and its help suggests the nearest name (`mian`, `Main`).
>
> Why I changed: my file/package split depended on "a file outside a package is never library
> code" (02_syntax.md:2734). That sentence sets the W0705 scope. It does not define what build
> does. One rule for files and packages is simpler, and it keeps §6.7.1 in its strong form,
> because every check-clean input builds.
>
> - Against G2-E: build fails on an input that check passed, for a fact that check could have
>   read. A new code for that makes the promise hold only by a technicality. Also, `blink build`
>   on a test-only file is a sensible way to show that its code generates.
> - Against L2 (run gets a diagnostic code, exit 1): `blink run` with no entry is a misuse of
>   the command, not a fault in the text. `blink test` on a path with no test file already uses
>   exit 2 for this (06 section :996). I can accept L2, but L1 is more consistent.

- **DevOps:** (excerpt)

> ## G2: change. I move from E to P (plt).
> - A file outside a package with no `fn main` (an empty file too): `build` and `run` stop before the
>   compile, exit 2, no binary. A library package: `build` compiles every module, writes no binary,
>   prints one line, exit 0. `run` of a library package: exit 2. check and test: no change.
> - Why I moved: 02_syntax.md:2734 already says "a file outside a package is never library code". So
>   L ("no main = library", for a file) contradicts the spec's own definition. A library package is a
>   real library, and building it with no binary is the Go and Cargo model. P matches both facts.
>   I drop my new code: a usage error (exit 2, as for `blink test` with no test file) is enough, since
>   it is decided from the command and one name, not from the text.
> - Against L for a file: `blink build x.bl && ./x` exits 0 and then fails with "no such file". In CI
>   the step that went wrong is green, and the red step is the next one. An exit 0 that wrote no
>   artifact is the bug class we are trying to remove (today's no-op binary).
> - Writer notes: the usage error has a `--json` form (CI parses it), and it has the did-you-mean help
>   from web/aiml (`mian`, `Main`).

- **AI/ML:** (excerpt)

> ## G2: G2-L (no change). Variation: L2 lean, L1 acceptable
>
> - Position: no main = library. check clean; build compiles all, writes no binary, prints a note,
>   exit 0; run refuses with a did-you-mean (`Main`, `mian`, `main_`); test unchanged.
> - L1 vs L2: I lean to a diagnostic code (L2) because an agent reads `--json` output and keys on
>   a code; a usage error is free text. If usage errors also come out in `--json` with a stable
>   kind, L1 is fine and I will vote for it. Not a hill.
> - Against G2-E: check is clean and build fails. That is the exact pattern §6.7.1 forbids, and
>   for an agent it is the worst order: it trusts check and then hits a build error it cannot
>   see from the editor. It also makes `blink build` useless as "does my library compile to C".
> - Against G2-P: a file and a library package with the same content get different results from
>   one command. That is a decision point a model must learn (file or package?) for no gain, and
>   build-of-a-file still fails after a clean check, the same objection as E.

- **Minimalism:** (excerpt)

> ## G2: CHANGED from L to E behavior, with the usage-error class (plt's file rule, applied to packages too)
>
> Position: `check` and `test` accept a file or package with no `fn main`. `build` and `run` refuse
> it before any compile: a usage error, exit 2, no binary, with a did-you-mean help for `mian`,
> `Main`. One rule for a file, an empty file and a library package. No new E-code.
>
> ```blink
> // util.bl
> fn f() -> Int { 1 }
> test "f" { assert_eq(f(), 1) }
> // blink check util.bl  -> ok
> // blink test util.bl   -> 1 passed
> // blink build util.bl  -> error: `util.bl` has no `fn main`; nothing to build (exit 2)
> // blink run util.bl    -> same
> ```
>
> Why I left L: the "library build" in L buys almost nothing. Mono builds only what is reached,
> so a library's generic fns get no instances without a caller; `blink test` already builds what
> the tests reach. So L adds a second build mode (compile, no artifact, exit 0) for close to no
> check value, and its exit 0 hides a typo'd `main` in CI (`blink build x.bl && ./x`). YAGNI.
>
> Against P (plt): the file vs package split is a second rule for one fact. A library package is
> not more buildable than a file with no main. If a library build mode is ever needed, add it
> then, with a flag.
>
> Against a new code (devops E, aiml L2): no-main is a fact about the command, not the text, the
> same class as `blink test` on a path with no test file (exit 2). A catalog row for it adds
> surface that the LSP never shows. I do not object if the panel wants the JSON shape; then reuse
> it as a usage-error JSON, not a new E-code. Exit 2 vs a code is a weak preference.

#### Phase C — Final vote

- **G2-Q1: what `blink build` does with no `fn main`** (5-1, option L; DevOps dissented for P. The other option was U, a usage error for every input)
- **G2-Q2: what `blink run` does with no `fn main`** (6-0, option X2, a usage error with exit 2; the other option was a new code `MissingMain`)

- **Systems:**

> ## G2-Q1: L
> Reasoning: L is the only option where `blink build` never stops on an input that `blink check` passed, so §6.7.1 holds with no reading of "usage error" as outside the source. It also gives one rule for a file and a package, and lets CI get the C compiler's verdict on the code that is reached. Min is right that mono compiles only reached generics, so that verdict is partial; it is still more than check gives.
> Concern: `blink build x.bl && ./x` is green at build and red at `./x` when `main` is misspelled; the note and its did-you-mean help must be on stderr and in `--json`.

> ## G2-Q2: X2
> Reasoning: no entry point is a misuse of the command, the same class as `blink test` on a path with no test file (exit 2). It needs no catalog row.
> Concern: agents key on codes; the usage error needs a stable `--json` kind.

- **Web/Scripting:**

> ## G2-Q1: L (changed from my round-1 P)
> Reasoning: sys's round-1 point decides it for me. Whether a file has `fn main` is a fact of the source that check saw. A build that then stops on it, with exit 1 or exit 2, breaks the settled 6.7.1 promise, and §6.7.3's list of allowed causes does not hold it. L was my Phase A position. It gives one rule for a file and a package, which is easier to teach than P's split. The note plus did-you-mean at build makes a `mian` typo visible in the build log.
> Concern: `blink build x.bl && ./x` in CI shows a green build step and a red run step; the note must be loud (stderr, and in `--json`) so the cause is one line above the failure.

> ## G2-Q2: X2
> Reasoning: running with no entry point is a misuse of the command, the same class as `blink test` on a path with no test file (exit 2). cargo and go treat it the same way. The did-you-mean help does the real work.
> Concern: agents parse `--json`, so a usage error needs a stable kind field there, not only free text.

- **PLT:**

> ## G2-Q1: L
> Reasoning: whether `main` exists is a fact of the source, and check saw that source. A build that stops on it, after a clean check, breaks §6.7.1 unless §6.7.3's closed list of stop causes grows. Check cannot report it either, because 2093 test files have no `main`. Under L every check-clean input builds. One rule covers a file, an empty file and a package, so the same items get the same result.
> Concern: a `mian` typo gives exit 0 and no binary, and CI fails one step later. The note with its did-you-mean must be prominent, and it must appear in `--json`.

> ## G2-Q2: X2
> Reasoning: `blink run` with no entry misuses the command; the text has no fault. `blink test` on a path with no test file already uses exit 2. The promise does not cover `run`, so refusing there costs nothing.
> Concern: agents key on codes. The usage error needs a stable `--json` kind, or aiml's point stands.

- **DevOps:**

> ## G2-Q1: P
> Reasoning: under L, a typo'd `main` gives `blink build x.bl` exit 0 and no artifact, so CI goes green on the wrong step and fails at `./x`. That is the bug class we are removing. A loose file is "never library code" (02_syntax.md:2734), so the only intent of `build x.bl` is a program, and a usage error before any compile is the honest answer. A library package is a real library, and the Go/Cargo model (compile all, no binary, exit 0) gives CI a "does my library build" step.
> Concern: sys's point that §6.7.3's list of build stops is closed: the writer must name "no entry point" there as a usage error before the compile, or the promise text reads as broken.

> ## G2-Q2: X2
> Reasoning: no main is a fact about the command, not the text; the LSP never shows it, so a catalog code adds a row with no editor surface. Exit 2 matches `blink test` on a path with no test file. A stable `--json` shape gives agents and CI the same key a code would.
> Concern: if the usage-error JSON shape is not specified, tools will grep free text; the writer note must make that shape binding.

- **AI/ML:**

> ## G2-Q1: L
> Reasoning: whether a file has `fn main` is a fact of the source that check saw, and check cannot report it (2093 of 3033 test files have no main), so P and U make build stop after a clean check, which §6.7.1 forbids. L is one rule for a file, an empty file and a package, with no file-vs-package decision for a model to learn. It also gives agents a way to ask "does this compile to C" without a fake `main`.
> Concern: `blink build x.bl && ./x` with a typo'd `mian` fails one step late in CI, so the note must be on stderr, name the did-you-mean, and appear in `--json`.

> ## G2-Q2: X2
> Reasoning: I withdraw MC: the same class as `blink test` on a path with no test file (exit 2), and the writer note gives the usage error a stable `--json` shape, which was my only reason for a code. The did-you-mean help (`mian`, `Main`) carries the fix.
> Concern: if the usage error lacks a `--json` form in practice, agents get free text only; the writer note must be binding.

- **Minimalism:**

> ## G2-Q1: L (changed from U in round 1)
> Reasoning: sys is right on the text: §6.7.1 says build stops only for a cause outside the Blink source, and "has no main" is a fact of the source that check saw. U and P can keep the promise only by amending §6.7.3 or by calling a usage error "not a stop", which is a second rule to save the first. L is one rule for file, empty file and package, needs no new code and no promise amendment, and still gives CI a C-compiler verdict on non-generic library code. My round-1 objection (exit 0 with no artifact hides a typo'd `main`) is real but smaller: the note prints, `./x` then fails loudly, and `run` refuses with a did-you-mean.
> Concern: in CI a `mian` typo makes the build step green and the next step red; the note must be on stderr and name the near name.

> ## G2-Q2: X2
> Reasoning: no entry point is a misuse of the command, the same class as `blink test` on a path with no test file (exit 2). A catalog code for it adds surface the LSP never shows. The `--json` shape writer note covers aiml's need.
> Concern: if usage errors have no stable `--json` kind today, agents get free text; the writer must give it one.

### Final Spec

```blink
// stats.bl
fn mean(xs: [Int]) -> Int { xs.len() }
// blink check stats.bl:  exit 0
// blink test stats.bl:   unchanged
// blink build stats.bl:  exit 0, no binary
//   note: no fn main; compiled as a library, no binary written
// blink run stats.bl:    exit 2, nothing compiled
//   error: no fn main in stats.bl; nothing to run

// typo.bl
fn mian() { io.println("hi") }
// blink build typo.bl:   exit 0, no binary, the note and the did-you-mean help
// blink run typo.bl:     exit 2, the error and the did-you-mean help

// empty.bl has no text
// blink build empty.bl:  exit 0, no binary, the note
// blink run empty.bl:    exit 2
```

- `blink check` and `blink test` do not change.
- `blink build` with no `fn main` compiles every module, writes no binary, prints `note: no fn main; compiled as a library, no binary written` on standard error, and exits `0`. The rule is the same for a file, an empty file and a package. A top-level fn one edit from `main` (`mian`, `Main`) adds a did-you-mean help.
- `blink run` with no `fn main` is a usage error before any compile: exit `2`, the same help, no code and no catalog row. It is in the same class as `blink test` on a path with no test file.
- The note and the usage error have a stable `--json` shape with `kind: "no_entry_point"`.
- A build with no `fn main` is not a stop, so the promise of §6.7.1 holds and the closed list of §6.7.3 stays closed.
- Dissent (Q1, 5-1): DevOps voted for P, a usage error for a file and a note for a package.
- Spec text: §6.7.7 *A Program With No `fn main`*, §6.7.3, §6.6, §8.14, §2.2 and §2.20 (`PanicInLibrary`).
