[< All Decisions](../DECISIONS.md)

# A Code for a File That Is There but Cannot Be Read — Design Rationale

### Panel Deliberation

The ticket (verbatim):

> **Title:** Diagnostic code for a source file the loader cannot read (load_module / entry file I/O error)
>
> ERROR_CATALOG has no code for "an imported or entry .bl file exists but cannot be read" (EACCES, EISDIR, EIO). E1108 FileNotFound is #embed only; no ModuleNotFound row either.
> Example: `import m` where src/m.bl is mode 000.
> Today: read_file returned "" and the module parsed as empty (silent). After the fs migration, interim pick (team-lead): plain "error: read src/m.bl: Permission denied" + exit 1, no code, same as the entry-file check in cli.
> Question for the panel: a new catalog code (worker proposal: E1202 SourceReadFailed under Modules, span on the import, message "read <path>: <os text>", in the diagnostic stream / --json), or no code? Same code for the entry file? Does a missing imported module get its own code?
>
> Note 1: Correction: E1200 ModuleNotFound exists (I missed it). Interim pick changed (LSP has no channel for a plain error line, and must not exit): an imported module that exists but cannot be read emits E1200 at the import node, message 'read <path>: <os text>'. Entry file keeps the plain 'error: read <path>: ...' + exit 1. Panel question narrows to: does a read failure get its own code, or does E1200's row widen to cover it?
>
> Note 2: Interim also covers the entry file when compiled in-process (lsp/daemon): compile_entry_to_program never exits; it returns the read failure to its caller. CLI/blinkc print plain 'error: read <path>: <os>' + exit 1; lsp/daemon publish it as E1200 (no loc). Panel: same code question for the entry file.
>
> Note 3: Interim widened: blink.toml / blink.lock that manifest_load / lockfile_load cannot read (rc != 0) takes the same route as the unreadable entry: CLI plain error + exit 1; lsp/daemon E1200 no loc. Panel: should a build-input read failure (manifest, lock) share the code with source files?

The loader had no code for an imported `.bl` file that is there but cannot be read, and E1108 (`FileNotFound`) covers `#embed` only. The compiler's interim answer used E1200 (`ModuleNotFound`) with the message `read <path>: <os text>` for an import, and a plain line with no code for the entry file, `blink.toml` and `blink.lock`. The panel was asked whether a read failure gets its own code, and where the line falls between it and E1200. The panel named the other build inputs as well (`audits.toml`, an `#embed` file) because the same fault reaches them.

Questions:

- Q1: the name. **N-F:** `FileReadFailed`. **N-U:** `FileUnreadable`. (Phase A also proposed `SourceReadFailed` and `InputReadFailed`; the proposers dropped them in Phase B because `blink.toml` is not source and "input" is vaguer than "file".) The code number, E1025 or E1202, was also open in Phase A; all six chose E1025 in Phase B, because the *Category Ranges* table has an E10xx row and no E12xx row.
- Q2: the help line. **H-E:** a help for EACCES and EISDIR, none for any other error. **H-D:** a help for EISDIR only.
- Q3: where the line falls between E1200 and E1025. **R-E:** the errno of one `open` decides: ENOENT or ENOTDIR means "not here" and the search goes on; any other errno stops the search with E1025. **R-N:** no rule is stated.

Shared by all six seats, and so not put to a vote: one new code for every file that is there but cannot be read (an imported `.bl`, the entry file in the command line tools, the language server and the daemon, `blink.toml`, `blink.lock`, `audits.toml`, an `#embed` file); E1200 and E1108 do not change; the span is the import path or the `#embed` argument, and none for the other files; the code is in the `--json` stream every time; the exit code is 1; a missing entry file is a usage error (exit code 2, text only, no code); the message head is `read <path>: <os text>`; a failed import (E1025 or E1200) binds a poison module, so W0602 and every use of `m.*` give no diagnostic.

Quotes below are verbatim copies of each seat's reply, whole except its title line.

#### Phase A — Independent proposals

All six seats proposed one new code for every file that is there but cannot be read, and rejected a widened E1200 and a code per kind of file. They differed on the name (`FileReadFailed`: web, aiml; `FileUnreadable`: devops, min; `SourceReadFailed`: sys; `InputReadFailed`: plt), on the number (E1025: sys, aiml, plt; E1202: web, devops; min left it to the writer) and on the help line.

- **Systems:**

  > ## Position
  >
  > "Not found" and "found but read failed" are two different facts. The first is a resolution
  > result (the search found no candidate). The second is an OS result (open/read gave an errno).
  > A tool or an agent acts on them in different ways: the first means fix the import or `blink add`,
  > the second means fix the disk (chmod, a directory where a file should be, EIO). One code that
  > holds both makes the `code` field useless for routing, and the message text turns into the API.
  > So I do not widen E1200.
  >
  > ## Proposal A (my pick): one new code for every read failure
  >
  > `SourceReadFailed`, **E1025** (E10xx, next to E1024 TomlSyntax, the same "a toolchain input file"
  > family). One code for every file the toolchain opens and then fails to read: an imported `.bl`,
  > the entry file, `blink.toml`, `blink.lock`, `audits.toml`, an `#embed` target. Key the code on the
  > mechanism (open/read gave an errno), not on the kind of file. That is what the hardware and the
  > kernel see, and it is one code path in the loader: one read helper, one diagnostic constructor.
  >
  > Message head: `read <path>: <OS text>` (strerror, as Go's `os.PathError` and rustc's
  > `couldn't read`). Help: none for EIO; for EACCES "check the file mode"; for EISDIR "`<path>` is a
  > directory; a module is a `.bl` file". Never print a raw errno number.
  >
  > Spans:
  > - imported `.bl`: span on the import path; `#embed`: span on the string argument.
  > - entry file, manifest, lock, audits: no span (no source text to point at). `path` is in the
  >   message and in a `--json` `"file"` field.
  >
  > Example, `src/main.bl`:
  >
  > ```
  > import m
  >
  > fn main() {
  >     print("hi")
  > }
  > ```
  >
  > `src/m.bl` mode 000, `blink check src/main.bl`:
  >
  > ```
  > error[SourceReadFailed]: read src/m.bl: Permission denied
  >   --> src/main.bl:1:9
  >   |
  > 1 | import m
  >   |         ^
  >   = help: check the file mode
  > ```
  >
  > exit 1. `--json`:
  > `{"severity":"error","name":"SourceReadFailed","code":"E1025","message":"read src/m.bl: Permission denied","span":{...}}`
  >
  > W0602 UnusedImport must **not** fire. The module has no known contents, so "not used" is a guess;
  > the same holds for every downstream error that hangs off `m`. Mark the module as poisoned, the
  > way E1200 should already do.
  >
  > Entry file mode 000: `error[SourceReadFailed]: read src/main.bl: Permission denied`, exit 1, in
  > the `--json` stream. The CLI and the LSP/daemon give the same code; only the sink differs. Today
  > the CLI prints a plain line and the LSP prints E1200: two answers for one fact. That split is the
  > bug.
  >
  > Missing entry file: that is a usage error (the user typed a bad path), same as §6 for
  > `blink test`: plain stderr text, exit 2, not in the `--json` stream. No code. In LSP the client
  > opened the file, so this case does not occur there; if it does, E1025 with "No such file".
  >
  > `#embed` file that is missing stays E1108; unreadable gets E1025.
  >
  > ## Proposal B (fallback): split source vs build input
  >
  > E1025 `SourceReadFailed` for `.bl` and `#embed`; E1026 `ManifestReadFailed` for TOML files.
  > I reject it: two codes, one mechanism, one fix. TomlSyntax already proves one code can serve
  > every TOML file; one more step serves every input file.
  >
  > ## Tradeoffs (sys)
  >
  > - Cost: zero at runtime; the check is the errno the read already returns. Today a failed read
  >   gives `""` and parses as an empty module, which is a silent miscompile. Any fix must make the
  >   read result a `Result`, so the code falls out at no added cost.
  > - Predictable: one helper, one code, one message shape. No per-file-kind branches to drift.
  > - Do not catch the error in the parser; the loader owns I/O.
  >
  > ## Cross-language
  >
  > - Go: `open m.go: permission denied`, the same PathError for every file kind.
  > - rustc: `error: couldn't read src/m.rs: Permission denied (os error 13)`, distinct from E0583
  >   "file not found for module".
  > - tsc: TS6053 "File not found" vs TS5033 "Could not write file"; read and resolve differ.
  > - Python: `PermissionError` is not `ModuleNotFoundError`.
  >
  > All four keep "cannot read" apart from "not found". Blink should too.

- **Web/Scripting:**

  > ## Position
  >
  > "Not found" and "found but cannot read" are different problems with different fixes. The first
  > means you fix the import or the path. The second means you run `chmod` or fix the disk. A user who
  > sees `ModuleNotFound` for a file that is right there in `ls` will search for "ModuleNotFound", find
  > answers about import paths, and lose an hour. Python, Node and Go all keep these errors apart. So
  > do I.
  >
  > ## Proposal 1 (my pick): new code E1202 `FileReadFailed`, for every file the toolchain reads
  >
  > One code, one rule: "a file is there but the OS refused to read it". It does not matter which
  > kind of file. A developer learns it once.
  >
  > | Case | Code | Span | In `--json` | Exit |
  > |---|---|---|---|---|
  > | imported `.bl` cannot be read | E1202 | the import path | yes | 1 |
  > | entry file cannot be read (CLI) | E1202 | none, `file` = the path | yes | 1 |
  > | entry file cannot be read (LSP/daemon) | E1202 | none, published on the file | yes | n/a |
  > | `blink.toml` / `blink.lock` / `audits.toml` cannot be read | E1202 | none, `file` = the path | yes | 1 |
  > | `#embed` file cannot be read | E1202 | the `#embed` argument | yes | 1 |
  > | entry file missing (CLI) | none: usage error, plain stderr | none | no (as `blink test`, §6 :2135) | 2 |
  > | imported module missing | E1200 as today | — | yes | 1 |
  > | `#embed` file missing | E1108 as today | — | yes | 1 |
  >
  > Message head: `read <path>: <os text>`. Help: `check that the file is readable (permissions) and is a regular file, not a directory`.
  >
  > W0602 must NOT fire on an import that failed to load (with E1200 or E1202). "Unused import" next
  > to "cannot read" is noise. It tells the user to delete a line they need.
  >
  > Example, `src/main.bl`:
  >
  > ```blink
  > import m
  >
  > fn main() {
  >     m.greet("hi")
  > }
  > ```
  >
  > with `src/m.bl` at mode 000:
  >
  > ```
  > error[FileReadFailed]: read src/m.bl: Permission denied
  >   --> src/main.bl:1:9
  >   |
  > 1 | import m
  >   |         ^
  >   = help: check that the file is readable (permissions) and is a regular file, not a directory
  > ```
  >
  > `--json`:
  >
  > ```json
  > {"severity":"error","name":"FileReadFailed","code":"E1202","message":"read src/m.bl: Permission denied","span":{"file":"src/main.bl","line":1,"col":9}}
  > ```
  >
  > `chmod 000 blink.toml && blink check src/main.bl`:
  >
  > ```
  > error[FileReadFailed]: read blink.toml: Permission denied
  >   = help: check that the file is readable (permissions) and is a regular file, not a directory
  > ```
  >
  > Tradeoffs:
  > - + The name says what went wrong. A search for it finds the right fix.
  > - + One code means CI scripts and editors handle all of these cases the same way. Today the entry
  >   file and `blink.toml` cases have no `--json` record, so a tool that reads the stream sees exit 1
  >   and nothing to show.
  > - + The LSP already needs a code here. Make it an honest one.
  > - − E12xx is "Modules", and `blink.toml` is not a module. I accept that: a user never reads the
  >   range, only the name. Put it in the catalog where it reads best.
  > - − A missing entry file stays a usage error, not a code. That is right: you typed a bad path on
  >   the command line, like `python nope.py`.
  >
  > ## Proposal 2 (reject): widen E1200 to cover read failures
  >
  > Zero new codes, but the name lies. `ModuleNotFound: Permission denied` will be its own Stack
  > Overflow question. Codes are frozen, so this mistake stays forever.
  >
  > ## Proposal 3 (reject): one code per file kind (SourceReadFailed, ManifestReadFailed, ...)
  >
  > More precise but nobody needs it. The message already names the file. Four names for one fix is
  > four things to learn.
  >
  > ## Cross-language
  >
  > - Python: `ModuleNotFoundError` vs `PermissionError: [Errno 13] Permission denied: 'm.py'`. Two kinds.
  > - Node: `MODULE_NOT_FOUND` vs `EACCES: permission denied, open 'm.js'`. Two codes.
  > - rustc: E0583 for a missing module file; an unreadable one is "couldn't read src/m.rs: Permission denied (os error 13)". Two errors.
  > - Go: `open m.go: permission denied`, the same form as E1202's message.
  > - Nobody reports a permission error as "not found". We should not be first.

- **PLT:**

  > ## Principle
  >
  > E1200 states a fact about the program: no module answers this name. A read failure states a fact about the host: the name resolved to a file, and the OS refused the bytes. The second fact changes with `chmod`, while the source stays the same. One name for two facts breaks the frozen meaning of `ModuleNotFound`. A tool that matches on the name would act on a false premise: E1200's own help says "run `blink add`", which is wrong for a mode-000 file. Resolution and loading are separate steps, so each gets its own code.
  >
  > ## Proposal P1 (preferred): one new code for every failed read
  >
  > `InputReadFailed`, E1025 (Manifest/Modules, E10xx; free, never used). It follows the model of `TomlSyntax`: one code, every file the toolchain reads, the message names the file.
  >
  > | Case | Code | Span | Exit |
  > |---|---|---|---|
  > | imported `.bl` exists, read fails | E1025 | the import path | 1 |
  > | entry file exists, read fails (CLI, LSP, daemon) | E1025 | none | 1 |
  > | `blink.toml` / `blink.lock` / `audits.toml` read fails | E1025 | none | 1 |
  > | `#embed` file exists, read fails | E1025 | the `#embed` argument | 1 |
  > | import with no file | E1200 (no change) | — | 1 |
  > | `#embed` file missing | E1108 (no change) | — | 1 |
  > | entry path missing | usage error, plain stderr, not in `--json` | — | 2 |
  >
  > - Message head: `cannot read <path>: <os text>`.
  > - Help: only when a true repair exists. EISDIR: "`<path>` is a directory; a module is one file (§10.1)". For EACCES or EIO, no help. §3.1 forbids a help that prescribes a repair that does not exist.
  > - E1025 is in the `--json` stream in each case, with `"span": null` when no site exists. The CLI and the LSP then give the same verdict for the same input.
  > - A TOML file that cannot be read has the same downstream effect as E1024: it gives no data, the build fails, and the `.bl` files are still checked.
  > - A missing entry path is an argument the user typed, not a fact about the program. This matches §6 `blink test` (exit 2, text even with `--json`). An LSP-opened buffer has no missing-path case.
  >
  > ### Example
  >
  > ```blink
  > import m
  >
  > fn main() {
  >     print(m.greet())
  > }
  > ```
  >
  > `src/m.bl` mode 000:
  >
  > ```
  > error[InputReadFailed]: cannot read src/m.bl: Permission denied
  >   --> src/main.bl:1:8
  >   |
  > 1 | import m
  >   |        ^
  > ```
  >
  > ```json
  > {"severity":"error","name":"InputReadFailed","code":"E1025","message":"cannot read src/m.bl: Permission denied","span":{"file":"src/main.bl","line":1,"col":8}}
  > ```
  >
  > Exit 1. No W0602, and no error on `m.greet()`.
  >
  > ### W0602 and cascades
  >
  > "Unused" is a judgment about a module interface that does not exist. The failed import binds `m` to an error module. Every use of `m.*` takes the error type and adds no diagnostic, which is ordinary error-type absorption. W0602 does not fire. The same rule applies to an E1200 import, which W0602 reaches today.
  >
  > ## Proposal P2 (rejected): widen E1200
  >
  > This adds less to the catalog. But E1200 becomes "resolution or I/O failed", which is a disjunction that clients must parse from the message. E1200 already fires with no span for a missing name, so a second case adds one more irregular shape. The name also misleads for `blink.toml`, which is not a module. I vote against it.
  >
  > ## Tradeoffs
  >
  > - P1 costs one row. It keeps each name a single judgment, so tools can rely on `name` alone.
  > - `<os text>` is not stable across platforms. Tests should assert the name and code, not the OS text.
  >
  > ## Cross-language
  >
  > - tsc separates TS6053 "File not found" from TS5012 "Cannot read file '{0}': {1}". That is the same split as P1.
  > - Python raises `ModuleNotFoundError` for a missing module and `PermissionError` (an `OSError`) for a module it cannot read.
  > - Go reports `open x: permission denied` as a load error, apart from "package not found".
  > - rustc prints a separate uncoded `couldn't read` error next to E0583. Blink should give it a code, because the LSP needs a code on every error it reports.

- **DevOps:**

  > ## Proposal 1 (my pick): one new code, `FileUnreadable` E1202, for every toolchain input
  >
  > A file that is there but cannot be read is a different problem from a file that is not there, and needs a different fix. "Not found" means: fix the import path or run `blink add`. "Unreadable" means: fix the permissions, or replace the directory with a file. If both share E1200, the help line and the language server quick-fix (offer `blink add`, offer to create `src/m.bl`) are wrong for one of them. The code is the key that tools match on, so it must name one fix.
  >
  > E1202 is the next free code (E1200 and E1201 are already used). Name: `FileUnreadable`, which pairs with `FileNotFound`.
  >
  > | Case | Code | Span | Exit |
  > |---|---|---|---|
  > | imported `.bl` cannot be read | E1202 | the module path in the `import` | 1 |
  > | `#embed` file cannot be read | E1202 | the `#embed` argument | 1 |
  > | entry file cannot be read (CLI) | E1202 | none | 1 |
  > | entry file cannot be read (LSP/daemon) | E1202 | none, shown on the file at 0:0 | none, keeps running |
  > | `blink.toml` / `blink.lock` / `audits.toml` cannot be read | E1202 | none, shown on that file at 0:0 in the LSP | 1 |
  > | imported module missing | E1200 (no change; add the import span) | `import` path | 1 |
  > | entry file missing | no code; usage error, plain stderr | none | 2 |
  >
  > Every E1202 goes in the normal diagnostic stream, so `--json` emits it too. Today an unreadable entry file gives exit 1 with **zero** JSON records. To a CI wrapper or an agent, that looks like a crash. That is the worst gap in the current behavior.
  >
  > The missing entry file follows the `blink test` rule (§6: a path that does not exist is a usage error, exit 2, plain text even with `--json`). The user typed a bad argument; nothing was compiled.
  >
  > W0602 must not fire on a failed import. A lint that sits on top of an error is noise. The import should bind a poisoned module, so uses such as `m.f()` give no follow-on errors either. rustc and tsc both stop cascades from an unresolved item.
  >
  > Example, `src/main.bl`:
  > ```blink
  > import m
  >
  > fn main() {
  >     m.greet("hi")
  > }
  > ```
  > with `src/m.bl` mode 000:
  > ```
  > error[FileUnreadable]: cannot read `src/m.bl`: Permission denied
  >   --> src/main.bl:1:8
  >   |
  > 1 | import m
  >   |        ^
  >   = help: check the permissions on `src/m.bl`
  > ```
  > ```json
  > {"severity":"error","name":"FileUnreadable","code":"E1202","message":"cannot read `src/m.bl`: Permission denied","span":{"file":"src/main.bl","line":1,"col":8,...}}
  > ```
  > When `src/m.bl` is a directory: same head with "Is a directory", and the help changes to: "a module is a file; `src/m.bl` is a directory". For other OS errors (EIO and so on) there is no help line. Unreadable `blink.toml`: `error[FileUnreadable]: cannot read `blink.toml`: Permission denied`, no span.
  >
  > Side note: today's caret sits at col 9, one past `m`. Check this when the span is set.
  >
  > Tradeoffs:
  > - One more catalog row. But one code covers six inputs, which follows the E1024 TomlSyntax rule: one code for every TOML file, and the message names the file.
  > - The OS text varies by platform and locale. Tools must match on the code, never on the message.
  > - Exit 2 for a missing entry file changes today's exit 1. Scripts that test `$? -eq 1` break, but the change brings the CLI in line with the rule `blink test` already follows.
  >
  > Cross-language: tsc has separate codes for this (TS6053 "File not found" and TS5012 "Cannot read file '…': …"), which is the model for this proposal. rustc and Go print plain "couldn't read"/"open …: permission denied" lines with no code, and that is why their JSON consumers cannot tell the two cases apart. rust-analyzer shows Cargo.toml errors on the manifest at 0:0, the same as the LSP rows above.
  >
  > ## Proposal 2 (reject): widen E1200's row to cover read failures
  >
  > Cheaper by one row, but a `blink.toml` read failure would report as `ModuleNotFound`, which is false. The `blink add` help and quick-fix would also then be wrong. I would vote against this.

- **AI/ML:**

  > ## Proposal 1 (preferred): one new code for every file that is there but cannot be read
  >
  > New row `FileReadFailed`, **E1025** (next free code in the E10xx range, which already holds the
  > manifest codes E1020–E1024). One rule: **the file exists, the OS read fails → E1025, whatever
  > the file kind.** E1200 keeps its meaning: "no file at the module path".
  >
  > | Case | Code | Span | In `--json` | Exit |
  > |---|---|---|---|---|
  > | imported `.bl` unreadable | E1025 | the module path `m` (today's col 9 is one past `m`; looks off by one) | yes | 1 |
  > | `#embed` file unreadable | E1025 | the `#embed` string literal | yes | 1 |
  > | entry file unreadable, CLI | E1025 | none | yes | 1 |
  > | entry file unreadable, LSP/daemon | E1025 | none (published on the entry URI) | n/a | no exit |
  > | `blink.toml` / `blink.lock` / `audits.toml` unreadable | E1025 | none | yes | 1 |
  > | entry file missing | no code, usage error | — | no (text on stderr) | 2 |
  >
  > Message head: `read <path>: <os text>` (unchanged from today). Help, per errno:
  > EACCES → "check the file's permissions"; EISDIR → "`<path>` is a directory; a module is a `.bl` file";
  > other → no help. **W0602 does not fire** on an import that got E1025 (same rule as E1023: the
  > entry binds no item, so "unused" is noise).
  >
  > ```blink
  > import m
  >
  > fn main() {
  >     m.hello()
  > }
  > ```
  >
  > With `src/m.bl` mode 000:
  >
  > ```
  > error[FileReadFailed]: read src/m.bl: Permission denied
  >   --> src/main.bl:1:8
  >   |
  > 1 | import m
  >   |        ^
  >   = help: check the file's permissions
  > ```
  >
  > ```json
  > {"severity":"error","name":"FileReadFailed","code":"E1025","message":"read src/m.bl: Permission denied","span":{"file":"src/main.bl","line":1,"col":8,...},"help":"check the file's permissions"}
  > ```
  >
  > Unreadable `blink.toml`:
  >
  > ```
  > error[FileReadFailed]: read blink.toml: Permission denied
  >   = help: check the file's permissions
  > ```
  >
  > Missing entry: `error: file not found: src/nope.bl`, exit 2 — the same class as §6
  > `blink test` "a path that does not exist" (usage error, exit 2, text even with `--json`). The
  > user typed a bad argument; no program was read.
  >
  > **Tradeoffs (my seat):**
  > - *Fix-from-name.* An agent that sees `ModuleNotFound` creates or renames a file. That is the
  >   wrong fix for EACCES/EISDIR and it loops. `FileReadFailed` names the real fix (permissions,
  >   path is a dir). Agents act on the name and code far more than on the message.
  > - *Decision points: one.* A per-kind split (SourceReadFailed, ManifestReadFailed, EmbedReadFailed)
  >   adds three rows that an agent must pick among, with the same fix for all. The file kind is in
  >   the path already.
  > - *One channel.* Today the CLI prints a plain line with no code and no `--json` record, but the LSP
  >   prints E1200. An agent driving `blink check --json` sees nothing to parse. Proposal 1 gives the
  >   CLI and LSP the same record.
  > - *Token cost:* one catalog row, one sentence in §10.1 / §8.9.8 / §2.20 pointing at it.
  >
  > **Cross-language:** Go: `open x.go: permission denied` (os error, separate from "package not
  > found"). rustc: `error: couldn't read src/m.rs: Permission denied (os error 13)`, distinct from
  > E0583 "file not found for module". Python: `PermissionError` vs `ModuleNotFoundError`. All three
  > keep "missing" and "unreadable" apart; Blink should too.
  >
  > ## Proposal 2 (fallback): widen E1200 for source files only
  >
  > E1200's row gains "or the file exists but cannot be read"; manifest/lock/audits/embed keep the plain
  > CLI line. Cheaper (no new row), but the name lies in exactly the case it covers, and the
  > build-input cases stay outside `--json`. I vote against it.
  >
  > ## Rejected: no code at all
  >
  > LSP cannot show a codeless line and must not exit; an interim already proves a code is needed.

- **Minimalism:**

  > ## Position
  >
  > "What if we just don't?" fails here on one fact: the language server and the daemon must
  > publish this failure, and a published diagnostic needs a code. Today they borrow E1200 for an
  > entry file, `blink.toml` and `blink.lock`. "ModuleNotFound" on a manifest is a lie, and a
  > frozen name cannot widen to mean the opposite of what it says ("found, but unreadable"). So the
  > choice is not "code or no code". It is "one honest code, or many borrowed ones". I vote one.
  >
  > ## Proposal M1 (recommended): one code, `FileUnreadable`, for every file the toolchain reads
  >
  > One new error. A writer picks the number in the E10xx range (next to E1024 TomlSyntax, which is
  > the same idea: one code for one failure, on every file).
  >
  > | Case | Code | Span | Message head |
  > |---|---|---|---|
  > | imported `.bl` that is there but the read fails | FileUnreadable | the import path | `read src/m.bl: Permission denied` |
  > | entry `.bl`, CLI and LSP/daemon | FileUnreadable | none | `read src/main.bl: Permission denied` |
  > | `blink.toml`, `blink.lock`, `audits.toml` | FileUnreadable | none | `read blink.toml: Permission denied` |
  > | `#embed("x")` file there but unreadable | FileUnreadable | the `#embed` argument | `read assets/x.bin: Is a directory` |
  > | imported module missing | E1200 (no change) | | |
  > | `#embed` file missing | E1108 (no change) | | |
  > | entry file missing | usage error, no code | | `error: file not found: src/nope.bl` |
  >
  > - The message is `read <path>: <OS text>`. The path is relative to the package root, as the
  >   audit diagnostics already do. No help line: the OS text is the help, and no generic hint
  >   ("check permissions") fits EISDIR and EIO too.
  > - Always in the diagnostic stream and in `--json`. Exit 1. The CLI and the LSP take one route,
  >   not two. This removes the plain `error: read ...` line and the E1200 borrowing.
  > - A failed import does not fire W0602. The compiler does not know what the module exports, so
  >   "unused" is a guess. The same rule must hold for E1200.
  > - A missing entry file is a bad command argument, not a compile result. Treat it as `blink test`
  >   treats "a path that does not exist" (§ tooling): text on stderr, exit 2, not in `--json`.
  >
  > ```blink
  > import m
  >
  > fn main() {
  >     m.greet()
  > }
  > ```
  >
  > With `src/m.bl` mode 000:
  >
  > ```
  > error[FileUnreadable]: read src/m.bl: Permission denied
  >   --> src/main.bl:1:8
  >   |
  > 1 | import m
  >   |        ^
  > ```
  >
  > ```json
  > {"severity":"error","name":"FileUnreadable","code":"E10xx","message":"read src/m.bl: Permission denied","span":{"file":"src/main.bl","line":1,"col":8}}
  > ```
  >
  > (The span starts on `m`, column 8. Today's output says column 9, one past the path; that looks
  > like an off-by-one to check, not a design point.)
  >
  > `blink.toml` mode 000, `blink check --json src/main.bl`:
  >
  > ```json
  > {"severity":"error","name":"FileUnreadable","code":"E10xx","message":"read blink.toml: Permission denied"}
  > ```
  >
  > Tradeoffs: +1 name, −1 plain-text route, −1 misuse of E1200. Net surface goes down. One code,
  > six sites, zero new concepts: "a file I had to read, I could not read".
  >
  > ## Proposal M2 (fallback, if the panel refuses a new code): widen nothing, restrict E1200
  >
  > Imports keep E1200 with the read message. Entry, manifest, lock, audits and `#embed` read
  > failures stay plain text + exit 1 in the CLI. The LSP gets no code for them: it shows the plain
  > line as a code-less diagnostic. I list this only to reject it: it keeps two routes, keeps the
  > name lie for imports, and leaves the LSP without a stable key for tools and AI agents to match.
  >
  > ## Against splitting further
  >
  > No `SourceReadFailed` vs `ManifestReadFailed` vs `EmbedReadFailed`. The OS text and the path
  > already say which file and why. A per-file code adds names and buys no action the user would take
  > differently.
  >
  > ## Cross-language
  >
  > - tsc: TS5012 "Cannot read file '{0}': {1}." is one code for every input, `tsconfig.json`
  >   included. That is M1.
  > - rustc: `couldn't read src/m.rs: Permission denied`, no code, at the `mod` span. Works for a
  >   CLI; rust-analyzer then has no stable key.
  > - Go: `open m.go: permission denied`, plain. Go has few codes on purpose, but Blink already
  >   committed to coded diagnostics, so "plain" is the odd one out here.

#### Phase B — Debate highlights

One round. All six seats ended it ready to vote. They agreed on E1025 and on a poisoned module for a failed import. Sys added the rule for Q3 (the errno of one `open` decides). The name (Q1) and the help line (Q2) went to a vote. The message head was ruled wording only; five seats kept `read <path>: <os text>`.

- **Systems:**

  > I read all six replies. I accept every point in "Shared by all six".
  >
  > ## Q1. Name: I drop N-S and move to N-F `FileReadFailed`
  >
  > `Source` is wrong, because the code also covers TOML files. I prefer `FileReadFailed` to
  > `FileUnreadable`. The code reports what happened (the read returned an errno), not a fixed
  > property of the file. EIO and ENOMEM can be transient, so a retry can succeed on a file that
  > we called "unreadable". `InputReadFailed` is also accurate, but "input" is a word users do not
  > use. My second choice is N-U.
  >
  > ## Q2. Number: C-25 `E1025`
  >
  > The *Category Ranges* table defines E10xx and has no E12xx row. E1020-E1024 are already the
  > "toolchain input file" codes. Web's point that users read the name, not the range, is true, but
  > it is a reason to accept either number, not a reason to put the code in the wrong range.
  >
  > ## Q3. Help: I move from H-E to H-D (EISDIR only)
  >
  > This is a systems fact against my own Phase A. EACCES from `open` can come from a parent
  > directory that has no search (`x`) bit, so "check the file mode" can point at the wrong
  > object. Only EISDIR has one exact repair. I agree with plt's §3.1 rule.
  >
  > ## Q4. Wording only
  >
  > The writer can pick. My preference is `read <path>: <os text>`, because it is today's output and
  > the Go form.
  >
  > ## Q5. Yes: bind a poisoned module, with no follow-on errors
  >
  > ```blink
  > import m
  >
  > fn main() {
  >     print(m.greet())
  > }
  > ```
  >
  > `src/m.bl` mode 000 gives one E1025 at `m`, with no W0602 and no error on `m.greet()`. Exit 1.
  > The same rule applies to an E1200 import.
  >
  > ## New point: the split between E1200 and E1025 is set by the errno of one `open`, not by a check before it
  >
  > A stat-then-open is a TOCTOU race and costs a second syscall. The rule:
  > - For each candidate path, call `open` once. ENOENT or ENOTDIR on a candidate means "not here":
  >   try the next candidate. When no candidate is left, the result is E1200 (or E1108 for `#embed`).
  > - Any other errno from `open` or `read` (EACCES, EISDIR, EIO, ELOOP, ...) stops the search
  >   and gives E1025. Do not fall through to a dependency with the same name, because a mode-000 file
  >   must not cause a different module to be loaded without any message.
  > - EINTR is retried and a short read loops; neither is ever reported.
  >
  > This makes the boundary between the two codes exact and free of races. It also explains a
  > file that is deleted between resolution and read: that is E1200.
  >
  > ## Side finding: the column
  >
  > Column 8, on `m`, is correct. My Phase A copied today's column 9. That is an implementation bug to
  > file, not a design point.
  >
  > ## Writer notes
  >
  > - In `--json`, set the `file` field to the unreadable path for spanless cases.
  > - Tests assert the name and the code, never the OS text (strerror varies by libc and locale).
  >
  > STABLE: ready to vote

- **Web/Scripting:**

  > I agree with the shared block. I also accept the column-8 point: the caret goes on `m`, so my
  > Phase A example (col 9) copied the off-by-one.
  >
  > ## Q1. Name: I move to N-U `FileUnreadable`
  >
  > devops is right: `FileNotFound` / `FileUnreadable` is a pair a user learns at once. If you see
  > one, you can guess the other. `FileReadFailed` is fine, but it does not pair. I drop N-F.
  > Against N-S: `blink.toml` is not "source". Against N-I: "input" is compiler-speak; a Python dev
  > says "file".
  >
  > ## Q2. Code: I move to C-25 `E1025`
  >
  > The fact settles it. No E12xx range exists in the table, and E10xx already holds the manifest
  > codes E1020-E1024. My "users read the name, not the range" still holds, but then the range is a
  > free tie-break, and E1025 wins it. I drop C-02.
  >
  > ## Q3. Help: I move to H-E
  >
  > My fixed help was wrong for EIO: "check permissions" on a disk error sends the user the wrong
  > way. H-E keeps the help where it is true:
  >
  > - EACCES: `= help: check the permissions on src/m.bl`
  > - EISDIR: `= help: src/m.bl is a directory; a module is one .bl file`
  > - anything else: no help
  >
  > Against H-N: EACCES is the 90% case, and a newcomer from JS does not always map "Permission
  > denied" to `chmod`. One line of help is cheap. Against H-D: EACCES has a real repair, so §3.1
  > does not forbid it.
  >
  > ## Q4. Message head: wording only
  >
  > It does not change behavior. One writer note below.
  >
  > ## Q5. Poison the failed module: yes, and the same for E1200
  >
  > One root cause gives one error. A user who sees five errors on `m.greet()` under the read error
  > fixes the wrong lines first. tsc and rustc both stop this cascade.
  >
  > ```blink
  > import m
  >
  > fn main() {
  >     m.greet("hi")
  >     m.wave()
  > }
  > ```
  >
  > `src/m.bl` mode 000:
  >
  > ```
  > error[FileUnreadable]: read src/m.bl: Permission denied
  >   --> src/main.bl:1:8
  >   |
  > 1 | import m
  >   |        ^
  >   = help: check the permissions on src/m.bl
  > ```
  >
  > Exit 1. That is the only diagnostic: no W0602, and no error on `m.greet` or `m.wave`. With
  > `import zz` and no file, E1200 is the only diagnostic, the same rule.
  >
  > ## Writer notes
  >
  > - Q4: I prefer `cannot read <path>: <os text>`. A bare `read src/m.bl: ...` looks like a command
  >   to the user. Go and rustc users know both forms, so this is a minor point; the writer picks.
  > - Tests must check the name and code, not the OS text (locale and platform change it).
  >
  > STABLE: ready to vote

- **PLT:**

  > I agree with every shared point.
  >
  > ## Q1. Name: I concede N-I and pick N-F `FileReadFailed`
  >
  > `Input` is no more precise than `File`, and two seats already use `File`. N-S fails because `blink.toml` is not source. I prefer N-F to N-U for two reasons:
  > - `Unreadable` claims a lasting property of the file. EIO can be transient, and EACCES changes with `chmod`. What the toolchain observes is an event: this read failed. The name should state the observation.
  > - The pairing with `FileNotFound` (E1108) does not hold. E1108 covers `#embed` only, while the new code covers six inputs. A paired name suggests the two have the same scope, and they do not.
  >
  > ## Q2. Code: C-25 `E1025`
  >
  > The *Category Ranges* table has no E12xx row. E1201 is "Type checking", so E12xx is not a coherent range. E10xx is the documented module and import range, and E1020-E1024 already hold the manifest codes. E1025 sits next to E1024 TomlSyntax, which follows the same rule: one code for every file of a kind. Picking E1202 would build on an accident of numbering.
  >
  > ## Q3. Help: I move from H-D to H-E
  >
  > "Check the file's permissions" names a repair that exists (`chmod`), so §3.1 allows it. My objection was to a generic help on EIO, and H-E gives EIO no help either. H-G breaks §3.1: it tells an EIO user to check permissions. H-N leaves out a repair we know.
  >
  > ## Q4. Message head: wording only
  >
  > I drop `cannot read` and accept `read <path>: <os text>`. It matches today's output and Go's `PathError`.
  >
  > ## Q5. Uses of the failed module: this is behavior, not wording, and the decision must state it
  >
  > Rule: a failed import (E1025 or E1200) binds the name to an error module. Each `m.x` takes the error type. That type is compatible with every type and adds no diagnostic, so W0602 is one case of the rule, not a separate exception. Without the rule, each use of `m` gives an error with no repair: the user can make no change at the use site that fixes it. §3.1 says errors at one point must converge on the repair the first help names, and the cascade breaks that.
  >
  > ```blink
  > import m
  >
  > fn main() {
  >     let n: Int = m.count()
  >     print(n + 1)
  > }
  > ```
  >
  > `src/m.bl` mode 000:
  >
  > ```
  > error[FileReadFailed]: read src/m.bl: Permission denied
  >   --> src/main.bl:1:8
  >   |
  > 1 | import m
  >   |        ^
  >   = help: check the file's permissions
  > ```
  >
  > Exit 1, one record in `--json`. The output has no unknown-member error, no type mismatch and no W0602.
  >
  > ## Writer notes
  >
  > - The EISDIR help must fit the file kind. "a module is a `.bl` file" is wrong for `#embed` and the TOML files. For those, use only "`<path>` is a directory".
  > - The span starts on `m` at column 8. Today's column 9 is a separate off-by-one, and the decision should not encode it.
  >
  > STABLE: ready to vote

- **DevOps:**

  > I accept every shared point.
  >
  > ## Q1. Name: I move to N-F `FileReadFailed`
  >
  > "Unreadable" names a lasting state of the file. EIO and an NFS timeout are events: if you run the
  > build again, it can pass. "ReadFailed" names what happened, so it fits every errno. It also matches
  > the message head `read <path>: ...`. Two seats already hold N-F, so this moves us toward one name.
  > I reject N-S, because `blink.toml` is not source. N-I is an acceptable second choice.
  >
  > ## Q2. Code: I move to C-25 `E1025`
  >
  > The Category Ranges table lists E10xx as module resolution, and E1020-E1024 are the manifest
  > rows. E12xx has no row in that table, and E1201 is a type-checking code, so E12xx is not a real
  > range. I picked E1202 only because it is next to E1200. That is a weak reason. E1025 sits next to
  > E1024 TomlSyntax, which uses the same "one code, every file" rule.
  >
  > ## Q3. Help: I hold H-E (EACCES and EISDIR, none for the rest)
  >
  > plt cites §3.1, but I find no rule there that forbids a help with no edit. sections/06_tooling.md:316
  > says the opposite: "A repair that has no edit is not a fix. Its text stays in `help`." So a
  > `chmod` hint is a valid help. EACCES has a real repair (change the mode, or the owner of the
  > file or of a parent directory). EIO has none, so it gets no help. H-G puts an EISDIR hint on an
  > EACCES error, which is noise. H-N leaves the most common case (EACCES in a CI container, where
  > files belong to root) with nothing to act on.
  >
  > Example, `src/m.bl` is a directory:
  > ```blink
  > import m
  >
  > fn main() {
  >     m.greet()
  > }
  > ```
  > ```
  > error[FileReadFailed]: read src/m.bl: Is a directory
  >   --> src/main.bl:1:8
  >   |
  > 1 | import m
  >   |        ^
  >   = help: `src/m.bl` is a directory; a module is one `.bl` file
  > ```
  > I can accept H-D as a fallback. I will vote against H-G.
  >
  > ## Q4. Message head: wording only. I concede `read <path>: <os text>`
  >
  > This keeps today's text, which is also Go's form, and four seats hold it.
  >
  > ## Q5. Poisoned module: yes, and it is behavior, not wording
  >
  > After a failed import (E1025 or E1200), `m` binds to an error module. Every `m.*` use takes the
  > error type and gives no diagnostic. Without this rule, one chmod gives one real error plus N
  > errors about unknown members in `m`. In the LSP those errors fill the Problems panel, and an agent
  > tries to "fix" every one. For the plt example, the output is the E1025 diagnostic only, with
  > exit 1.
  >
  > ## Writer notes
  > - In the LSP, a diagnostic with no span goes on the file it names (the entry URI, or the
  >   `blink.toml` URI) at range 0:0.
  > - The span is on `m` (column 8). Today's column 9 is a separate off-by-one bug. File it on its own.
  >
  > STABLE: ready to vote

- **AI/ML:**

  > I accept the shared core as written (one new code for every file kind, the spans, always in
  > `--json`, exit 1, E1200/E1108 do not change, missing entry = usage error exit 2, no W0602).
  >
  > ## Q1. Name: I move from N-F to **N-U `FileUnreadable`**
  >
  > devops is right: it pairs with `FileNotFound` (E1108). An agent learns the pair as one rule:
  > "NotFound = no file, Unreadable = file is there, OS refused". The pair is easy to guess from the
  > spec alone. Both N-F and N-U name the fix; N-U also matches an existing name. N-S is wrong for
  > `blink.toml` (not a source). N-I "Input" is vaguer than "File" for no gain.
  >
  > ## Q2. Number: **C-25 `E1025`**
  >
  > The *Category Ranges* table has an E10xx row ("Module resolution / imports") and no E12xx row,
  > and E1020–E1024 already hold the manifest codes. A model that infers a category from a code
  > gets the right answer with E1025. E1202 would sit next to `InvalidStringBackedEnum` (Type
  > checking), which tells it nothing. web's point (users read the name) is true, but then the
  > range costs nothing either way, so take the one that agrees with the table.
  >
  > ## Q3. Help: I move from H-E to **H-D (EISDIR only)**
  >
  > `Permission denied` already says what "check the file's permissions" says. That help adds tokens
  > and no fact. The EISDIR help adds a fact the OS text does not give: a module is one `.bl` file,
  > not a directory (a model from Python or Go may expect a package directory). H-G puts a fixed
  > two-part guess on every case, which is noise for EIO. H-N loses the one useful line.
  >
  > ## Q4. Message head: wording, but I hold `read <path>: <os text>`
  >
  > It is the same as today, the same as Go's `os.PathError`, and one token shorter. Writer note below.
  >
  > ## Q5. Uses of the failed module: **yes, bind a poisoned module**, and the same for E1200
  >
  > Follow-on errors are the main cost for an agent: each one is a false lead it tries to fix. One
  > root error, zero follow-ons.
  >
  > ```blink
  > import m
  >
  > fn main() {
  >     print(m.greet())
  >     let x: Int = m.count
  >     print("{x}")
  > }
  > ```
  >
  > `src/m.bl` mode 000:
  >
  > ```
  > error[FileUnreadable]: read src/m.bl: Permission denied
  >   --> src/main.bl:1:8
  >   |
  > 1 | import m
  >   |        ^
  > ```
  >
  > Exit 1. One record in `--json`. No W0602, no error on `m.greet()` or `m.count`, and `x` gets the
  > error type with no added diagnostic. The same holds when `m` gets E1200.
  >
  > ## Writer notes
  >
  > - Q4: if the panel picks `cannot read`, no quotes around the path (plt), to match E1200's text.
  > - The span column is 8 (on `m`); today's 9 is a bug to fix with this change, not a design point.
  >
  > STABLE: ready to vote

- **Minimalism:**

  > I accept the shared block as written, with no objection.
  >
  > ## Q1. Name: N-U `FileUnreadable` (keep). Second choice: N-F
  >
  > `FileUnreadable` pairs with the existing `FileNotFound` (E1108), and the pair reads as one family:
  > the file is missing, or the file is there and cannot be read. It names the state of the file, not the step
  > that failed, so an open failure and a read failure both fit. Against N-S: a manifest is not
  > "source". Against N-I: "input" is vaguer than "file", and nothing gains from that. I can accept N-F.
  >
  > ## Q2. Number: C-25 `E1025`
  >
  > The *Category Ranges* table has an E10xx row ("Module resolution / imports") and no E12xx row.
  > E1202 then needs a new range row, or it sits in a range that no row describes. E1025 needs
  > neither, and it sits next to E1024 TomlSyntax, the closest model. Fewer catalog changes means
  > less to maintain.
  >
  > ## Q3. Help: I move from H-N to H-D (plt)
  >
  > I concede one case. For an import that resolves to a directory, the help tells the user
  > something the OS text does not: in Blink a directory is not a module, as it is in Go and
  > Python. That is a real repair. EACCES "check the file mode" only says "Permission denied"
  > again, so it adds a line and teaches nothing. I reject H-G: one fixed help names two causes,
  > so it is wrong in every case. H-E is acceptable but adds the EACCES line for no gain.
  >
  > Scope: the EISDIR help applies to an import only, where "a module is one `.bl` file" is
  > true. A `#embed` or TOML path that is a directory gets no help, because "a module" is the wrong
  > noun there.
  >
  > ## Q4. Wording only
  >
  > Q4 is wording, not an option. See Writer notes.
  >
  > ## Q5. No new rule. Use the rule that exists
  >
  > §5 (sections/05_memory_compile_errors.md:530) already says: "When a missing import causes
  > cascading errors ... downstream references to a poison symbol suppress their own diagnostics."
  > An unreadable import is the same kind of failed import. The spec text says it takes that route,
  > and nothing more. No second mechanism. W0602 is covered by the same sentence: a poison import is
  > neither used nor unused.
  >
  > ```blink
  > import m
  >
  > fn main() {
  >     print(m.greet())
  > }
  > ```
  >
  > ```
  > error[FileUnreadable]: read src/m.bl: Permission denied
  >   --> src/main.bl:1:8
  >   |
  > 1 | import m
  >   |        ^
  > ```
  >
  > Exit 1. One diagnostic only: no W0602 and no error at `m.greet()`. If E1200 does not do this
  > today, that is a compiler bug against §5, not a spec gap. File it as a bug.
  >
  > ## Writer notes
  >
  > - Message head: keep `read <path>: <os text>`. It is the current output and the Go `PathError`
  >   form. Do not use backticks around the path in the head, so that `--json` consumers do not
  >   have to strip them.
  > - Tests assert the name and code, never the OS text, because the text varies by platform and locale.
  > - The column-9 caret is a separate bug to file, not panel text.
  >
  > STABLE: ready to vote

#### Phase C — Silent vote

| Question | Result |
|---|---|
| Q1 the name | **N-F `FileReadFailed` 5-1** (AI/ML *(dissent)*: N-U `FileUnreadable`) |
| Q2 the help line | **3-3** (H-D: sys, aiml, min; H-E: web, plt, devops), sent to Phase D |
| Q3 where the line falls between E1200 and E1025 | **R-E 6-0** |

Each seat's vote, reasoning and concern:

- **Systems:**

  > ## Q1. Name
  > **Vote:** N-F `FileReadFailed`
  > **Reasoning:** The code reports an event: a syscall returned an errno. EIO, ENOMEM and an NFS
  > timeout are transient, so a retry can succeed on a file that we named "unreadable". The pairing
  > with `FileNotFound` reads well, but it is a small gain compared with a name that is false for
  > transient errors.
  > **Concern:** If N-U wins, users can think a retry has no chance on an EIO, and close a flaky disk
  > issue as a fixed file state.
  >
  > ## Q2. Help line
  > **Vote:** H-D (EISDIR only)
  > **Reasoning:** EACCES from `open` also comes from a parent directory that has no search (`x`) bit,
  > from an SELinux/AppArmor denial, or from a mount with `noexec`/ACL rules. So "check the file's
  > permissions" can send the user to the wrong object. Only EISDIR has one exact repair. The OS text
  > "Permission denied" already says what a generic hint would say.
  > **Concern:** If H-E wins, the help text must not say "file mode", because the cause is often a
  > directory or a security policy, not the file's mode bits.
  >
  > ## Q3. Boundary between E1200 and E1025
  > **Vote:** R-E
  > **Reasoning:** Without a stated rule, an implementation can stat-then-open (a TOCTOU race and a
  > second syscall), or treat any failed candidate as "not here" and fall through. That loads a
  > dependency named `m` with no message while `src/m.bl` exists. That is a silent wrong build, the
  > worst outcome for a compiler. One `open`, with ENOENT/ENOTDIR as the only "not here" errnos, gives
  > an exact, race-free boundary at zero added cost.
  > **Concern:** If R-E wins, the implementation must also apply the rule to the `#embed` and TOML
  > paths, and must test that EINTR and short reads loop and are never reported. A test that only
  > checks mode 000 will not prove that.

- **Web/Scripting:**

  > ## Q1. Name
  >
  > **Vote:** N-F `FileReadFailed`
  >
  > **Reasoning:** In round 1 I voted for N-U because it pairs with `FileNotFound`, but devops's point
  > changes my vote. An EIO error or an NFS timeout is an event, and the next run can pass.
  > `FileUnreadable` tells the user the file is broken, so they go and look at a file that is fine.
  > The name must stay true in every case, and a pair is a smaller gain than a name that is wrong for
  > some errors.
  >
  > **Concern:** If N-U wins, a user with a flaky network disk will look at the file mode and find
  > nothing wrong.
  >
  > ## Q2. Help line
  >
  > **Vote:** H-E
  >
  > **Reasoning:** EACCES is the 90% case, and many JS and Python devs do not link "Permission denied"
  > to `chmod` the first time they see it. One true help line costs little and prevents a search on
  > Stack Overflow. The fix for EACCES is real, so the help does not promise a repair that is not there.
  >
  > **Concern:** The writer could make the EACCES help too general, so that it also seems to cover
  > EPERM or SELinux denials, where `chmod` does not help.
  >
  > ## Q3. E1200 / E1025 boundary
  >
  > **Vote:** R-E
  >
  > **Reasoning:** If a mode-000 `src/m.bl` makes the compiler load a dependency named `m` with no
  > message, the user gets type errors from a module they did not write, and the cause is hidden. That
  > is the worst kind of bug to debug. Stop at the first file that is there and report it. Python's
  > "shadowed module" problems show the cost of a search that moves on to the next candidate with no
  > message.
  >
  > **Concern:** The rule list of errnos (ENOENT and ENOTDIR mean "not here") must stay the same on
  > macOS and Windows, or the search will act differently on each platform.

- **PLT:**

  > ## Q1. Name
  >
  > **Vote:** N-F `FileReadFailed`
  >
  > **Reasoning:** The diagnostic reports an event the toolchain saw: one read failed. A lasting property of the file is a claim the toolchain cannot check, because EIO can be transient and EACCES changes with `chmod`. The pairing with `FileNotFound` does not hold up. E1108 covers `#embed` only and this code covers six inputs, so a paired name would suggest the two have the same scope, which they do not.
  >
  > **Concern:** Users may read the different stems (`NotFound` against `ReadFailed`) as a split by file kind. The catalog row must say that the split is by errno.
  >
  > ## Q2. Help line
  >
  > **Vote:** H-E
  >
  > **Reasoning:** §3.1 forbids a help that names a repair that does not exist. For EACCES the repair exists (`chmod`), so the help passes that test. EIO and the other errors get no help, so the rule holds in each case, and leaving out a repair we know helps no one.
  >
  > **Concern:** The EISDIR help must fit the file kind. "a module is one `.bl` file" is wrong for `#embed` and the TOML files, which should get only "`<path>` is a directory".
  >
  > ## Q3. E1200 / E1025 boundary
  >
  > **Vote:** R-E
  >
  > **Reasoning:** Which module a name resolves to must depend only on the files that exist, never on whether the host lets us read them. Under R-N, a mode-000 `src/m.bl` can silently change `import m` to a dependency with the same name. The program's meaning then changes with file mode, and nothing reports it. R-E makes resolution a function of which paths exist: the loader resolves first, then reads, and a read failure stops the search and never falls through.
  >
  > **Concern:** A dangling symlink gives ENOENT on `open`, so R-E treats it as "not here", and it can still fall through to a dependency without any message. The writer should state what happens to a dangling symlink, or put it under E1025.

- **DevOps:**

  > ## Q1. The name
  > **Vote:** N-F `FileReadFailed`
  > **Reasoning:** The name names the event, so it fits every errno. That includes EIO and a network-filesystem timeout, which pass on a second run. "Unreadable" tells the user that the file is broken, but for a transient error the file is fine. A name that holds for every case is one that tools and agents can route on.
  > **Concern:** If N-U wins, a user who gets "FileUnreadable" for a transient EIO may chase file permissions that are not the problem.
  >
  > ## Q2. The help line
  > **Vote:** H-E
  > **Reasoning:** sections/06_tooling.md:316 lets a help hold a repair that has no edit, and `chmod`/`chown` is the real repair for EACCES. EACCES is the most common case, often in a CI container where root owns the files, so a help line there is useful. EIO has no repair, so it gets no help. That keeps the help honest.
  > **Concern:** The EACCES failure can be on a parent directory and not the file itself, so the help should say "permissions" in general and not name only the file's mode.
  >
  > ## Q3. Where the line falls between E1200 and E1025
  > **Vote:** R-E
  > **Reasoning:** If a mode-000 `src/m.bl` makes the compiler load a dependency named `m` with no message, the user gets errors about a module they did not mean to load, and no diagnostic points to the real cause. That is the worst result a diagnostic surface can give. Stopping on the first errno that is not "not here" puts the error at the real cause. The LSP and the CLI then give the same answer.
  > **Concern:** ENOTDIR as "not here" must apply only to a path part that is a file, so that one odd layout does not quietly fall through to the dependency again.

- **AI/ML:**

  > ## Q1. Name
  > **Vote:** N-U `FileUnreadable`
  > **Reasoning:** A model learns `FileNotFound` / `FileUnreadable` as one pair with one rule: no file, or a file the OS refused. A name that matches an existing one is easier to guess from the spec alone than a new shape. devops's EIO point is true but does not change the fix an agent takes; the message's OS text already says which event it was.
  > **Concern:** For a transient EIO or NFS timeout, "Unreadable" may lead an agent to change the file mode when a retry was the fix.
  >
  > ## Q2. Help line
  > **Vote:** H-D (EISDIR only)
  > **Reasoning:** "check the file's permissions" repeats "Permission denied" and adds tokens with no new fact. The EISDIR help adds a fact the OS text lacks: a module is one `.bl` file, not a package directory, which a model from Python or Go may expect. A help line that is there only when it says something new trains models to read it.
  > **Concern:** A new user may still not know that `chmod` is the fix for EACCES, so a short help may cost them one search.
  >
  > ## Q3. E1200 / E1025 line
  > **Vote:** R-E (the errno of one `open` decides)
  > **Reasoning:** One rule with no exceptions is what an agent can learn from the spec alone: ENOENT/ENOTDIR means "try the next path", any other errno stops with E1025. Without it, a mode-000 `src/m.bl` can silently load a dependency named `m`, and the agent then debugs wrong-module type errors far from the real cause. A stated rule also makes the behavior the same in the CLI, the language server and every later implementation.
  > **Concern:** A stray unreadable file (for example an editor lock or a broken symlink, ELOOP) under `src/` now blocks a build that would have resolved to a dependency, and the user may find that strict.

- **Minimalism:**

  > ## Q1. The name
  >
  > **Vote:** N-F `FileReadFailed`
  >
  > **Reasoning:** I change my vote. The devops point is right. EIO or an NFS timeout is an event,
  > and the next read may succeed, so "Unreadable" claims a lasting state that the compiler
  > cannot know. The pairing with `FileNotFound` was only nice to have; a name that is true in every
  > case it covers is worth more than a matched pair.
  >
  > **Concern:** a user may search `FileNotFound` and `FileReadFailed` as unrelated codes. The
  > catalog row should point from each one to the other.
  >
  > ## Q2. The help line
  >
  > **Vote:** H-D (help for EISDIR only)
  >
  > **Reasoning:** A help line must tell the user something that the head does not already say.
  > For EISDIR it does: in Blink a directory is not a module. For EACCES, "check the file's
  > permissions" only repeats "Permission denied", and that is one more line in every terminal and
  > `--json` record for no gain.
  >
  > **Concern:** a writer may extend the EISDIR help to `#embed` and TOML paths, where "a module is
  > one `.bl` file" is the wrong noun. Keep that help on an import only.
  >
  > ## Q3. Where the line falls between E1200 and E1025
  >
  > **Vote:** R-E (the errno of one `open` decides)
  >
  > **Reasoning:** This is not new surface. It defines where the code we just added starts and
  > stops. Without the rule, "file is there" stays undefined, and a mode-000 `src/m.bl` can let a
  > dependency named `m` load with no message. That is a silent wrong build, which is worse than any
  > cost in rule text. "ENOENT/ENOTDIR means try the next candidate; any other errno stops" is one
  > sentence and one branch in the loader.
  >
  > **Concern:** the errno list is POSIX. A later Windows port must map its own error codes onto
  > "not here" and "stop", or the two hosts will give different codes for the same tree.

#### Phase D

Triggered by the 3-3 tie on Q2. One round on Q2 only. Both sides agreed that EISDIR gets a help line and that EIO and the other errors get none; the split was the EACCES case. Each seat answered the other side once and voted again.

| Q2 | Result |
|---|---|
| H-D (a help for EISDIR only) | **4-2** (aiml, min, devops, plt) |
| H-E (a help for EACCES and EISDIR) | sys, web *(dissent)* |

Devops and plt moved from H-E to H-D. Sys moved from H-D to H-E. Web stayed with H-E.

- **Systems:**

  > ## Answer to H-E
  >
  > My objection was never that the help is useless. It was that "check the file's permissions"
  > points at the wrong object when the denial is on a parent directory. devops raised the same
  > concern, and it has a fix: a help that names the path and the directories above it is true for
  > every DAC EACCES, which covers almost every case a user sees (root-owned files in a CI container,
  > a home directory with mode 700). plt is right that §3.1 allows a help that names a repair that
  > exists, and `chmod`/`chown` is that repair.
  >
  > The aiml/min point that the help "repeats Permission denied" is half true. The head says *that*
  > access was denied. It does not say *where* to look, and the parent-directory case is exactly the
  > one a user misses: they run `ls -l src/m.bl`, see `rw-r--r--`, and get stuck.
  >
  > The cases left over (SELinux/AppArmor, EPERM) are rare on a dev machine, and a help about
  > permissions on the path does not mislead there. It only falls short.
  >
  > So I change my vote.
  >
  > ## Vote: H-E
  >
  > **Reasoning:** EACCES is the common case and has a real repair, so a help line passes §3.1 and
  > adds a fact the head lacks: the denial can be on any directory in the path, not only on the file.
  > This keeps H-D's precision point, because the help names the full path and not only the file's mode.
  >
  > **Concern:** If the writer words it "check the file's permissions" or "check the file mode", the
  > help sends users to the wrong object in the parent-directory case. The help must name the path
  > and the directories that contain it.

- **Web/Scripting:**

  > ## Answer to H-D
  >
  > min and aiml are right that "check the file's permissions" only repeats "Permission denied". If that is the text, I would vote H-D. sys gives the reason the help should exist: the cause is often not the file. A parent directory with no `x` bit is the classic Stack Overflow trap. A user runs `ls -l src/m.bl`, sees `rw-r--r--`, and is lost. "Permission denied" does not tell them to look higher up the path. So a help line for EACCES does add a new fact if it names the path and its parent directories. For example: "the current user cannot open `src/m.bl`; check the mode and owner of the file and of each directory above it". That is not a repeat of the head, and it is true for the common cases (the file mode, a parent dir, a root-owned CI checkout). It does not claim that `chmod` fixes SELinux. When it is SELinux, "check" points at the right place and promises nothing.
  >
  > ## Vote
  >
  > **Vote:** H-E
  >
  > **Reasoning:** The 90% user does not know that EACCES can come from a parent directory, and the head cannot tell them. One help line that names the parent directories saves the search that the bare OS text causes. If the writer cannot say more than the head does, the help line has no value, and H-D is the better outcome.
  >
  > **Concern:** The writer could shorten the help to "check the file's permissions". That only repeats the head and misses the parent-directory case, so it gives the H-D side's cost and none of the gain.

- **PLT:**

  > ## Answer to the other side
  >
  > sys's point refutes my Phase C argument, and I concede it. I said that the repair for EACCES exists, so the help passes §3.1. That test is not strong enough. A help is attached to a condition, which here is errno EACCES. It must be true for every case of that condition, not only for the common one. EACCES also comes from a parent directory with no search bit, from an SELinux or AppArmor denial, and from ACL rules. In those cases "check the file's permissions" names the wrong object, and `chmod` on the file repairs nothing, which is the failure §3.1 forbids. EISDIR has one repair in every case, so it keeps its help.
  >
  > devops's concern shows the same flaw: once the help says "permissions in general", it no longer names a repair, and it only repeats the OS text. web's 90% case is real, but "Permission denied" is the OS's own name for the fault, and that phrase finds the right answers in a search. A help that is right most of the time teaches users to doubt the help line in every case.
  >
  > ## Vote
  >
  > **Vote:** H-D (changed from H-E)
  >
  > **Reasoning:** A help line must be true for each case of the condition that triggers it. EISDIR passes that test, and EACCES fails it, because the denial can come from an object other than the file, or from a policy that `chmod` cannot change. This also gives a principle that composes: a help is attached only to an errno with one sure repair.
  >
  > **Concern:** A later change could add an EACCES help again "because it is common". The catalog row should state the rule, a help only for an errno with one sure repair, not just list EISDIR.

- **DevOps:**

  > ## Answer to H-D
  >
  > sys's list is the same as my own Phase C concern, but with more cases, and it changes my vote.
  > EACCES can come from the file's mode, a parent directory with no `x` bit, an ACL, or an
  > SELinux/AppArmor denial. A help that is true for all four must be general ("check access to the
  > file and the directories above it"). A general help adds little to "Permission denied". A
  > specific help ("check the file's permissions") can send the user to the wrong object. In an
  > SELinux denial, a user who runs `chmod 777` and still sees the error loses more time than a user
  > who saw no help line at all. A help line that can mislead is worse than no help line. web's
  > point is real (new users do not link the OS text to `chmod`), but the OS text is a searchable,
  > standard string, and every search for it gives the right answers. It also costs nothing to add
  > an EACCES help later if field reports ask for one. To take back a help line that misleads is a
  > visible change to output.
  >
  > ## Vote
  > **Vote:** H-D (I change from H-E)
  > **Reasoning:** The help for EISDIR names one exact repair. No EACCES help names one exact repair
  > and is also true for every cause of EACCES, so the head must carry that case alone. A help line
  > that is present only when it is exact is one users and agents learn to trust.
  > **Concern:** The writer must keep the EISDIR help on EISDIR only, and must not stretch it to
  > ENOTDIR or ELOOP, where "a module is one `.bl` file" is not the repair.

- **AI/ML:**

  > ## Answer to H-E
  >
  > web: "Permission denied" is the most common Unix error text there is. Models and most humans
  > already map it to `chmod`/`chown`. A search costs less than what the help line costs over time:
  > one more line in every terminal and `--json` record, read by every agent.
  >
  > plt: §3.1 says a help must not name a repair that does not exist. That is a floor, not a reason
  > to add a help. And for EACCES there is no single repair. sys lists the parent directory's `x`
  > bit, SELinux/AppArmor and ACLs. A help that names "the file's permissions" points an agent at the
  > wrong object in those cases. It runs `chmod` on `src/m.bl`, the error stays, and it loops.
  >
  > devops: in the CI case where root owns the files, the fix is `chown`, or to run as a different
  > user, or to fix the volume mount. A one-line help cannot pick among them. If we make the help
  > general enough to be true ("check permissions"), it says nothing that "Permission denied" does not.
  >
  > The EISDIR help is different: it has one exact repair and states a Blink rule (a module is one
  > file) that the OS text does not.
  >
  > ## Vote
  > **Vote:** H-D
  > **Reasoning:** A help line must add a fact the head does not give. For EACCES the only true
  > generic help repeats "Permission denied", and a more specific one is wrong for the parent-dir and
  > MAC cases, which sends an agent to fix the wrong object. Keeping help only where it adds a fact
  > keeps the help channel worth reading.
  > **Concern:** A new user in a root-owned CI container sees no hint, and may take one search longer
  > to find `chown`.

- **Minimalism:**

  > ## Answer to H-E
  >
  > The H-E side states its own problem in its concerns. devops says the help must say
  > "permissions" in general, because the denial can come from a parent directory. web says it
  > must not seem to cover SELinux or EPERM. Put those together and the only safe text is
  > "something about permissions denied the read", which is what the head already says. The useful
  > text, "chmod this file", is wrong for every parent-directory, ACL and SELinux case (sys).
  >
  > plt's §3.1 test is necessary but not sufficient. A help line can name a true repair and still
  > add nothing. Users who do not know what "Permission denied" means will search the OS text, and
  > that search already works for every language. The help line saves them nothing.
  >
  > The EISDIR help is different. It states a Blink rule (a directory is not a module) that the
  > OS text cannot know. That is the test I would keep: a help line says what only Blink knows.
  >
  > ## Vote
  >
  > **Vote:** H-D
  >
  > **Reasoning:** EACCES has several causes and no one repair, so any true help for it restates
  > the head. A help line that is there only when it adds a Blink fact keeps the line worth reading,
  > for people and for agents.
  >
  > **Concern:** a user in a CI container with root-owned files sees no hint. I accept that, because
  > the OS text gives them a search term that works.

### Dissent

**AI/ML, Q1 (voted N-U `FileUnreadable`).** Quoted in full from its Phase C reply:

  > ## Q1. Name
  > **Vote:** N-U `FileUnreadable`
  > **Reasoning:** A model learns `FileNotFound` / `FileUnreadable` as one pair with one rule: no file, or a file the OS refused. A name that matches an existing one is easier to guess from the spec alone than a new shape. devops's EIO point is true but does not change the fix an agent takes; the message's OS text already says which event it was.
  > **Concern:** For a transient EIO or NFS timeout, "Unreadable" may lead an agent to change the file mode when a retry was the fix.

**Systems, Q2 (voted H-E).** Quoted in full from its Phase C reply (H-D) and its Phase D reply (H-E):

  > ## Q2. Help line
  > **Vote:** H-D (EISDIR only)
  > **Reasoning:** EACCES from `open` also comes from a parent directory that has no search (`x`) bit,
  > from an SELinux/AppArmor denial, or from a mount with `noexec`/ACL rules. So "check the file's
  > permissions" can send the user to the wrong object. Only EISDIR has one exact repair. The OS text
  > "Permission denied" already says what a generic hint would say.
  > **Concern:** If H-E wins, the help text must not say "file mode", because the cause is often a
  > directory or a security policy, not the file's mode bits.

  > ## Answer to H-E
  >
  > My objection was never that the help is useless. It was that "check the file's permissions"
  > points at the wrong object when the denial is on a parent directory. devops raised the same
  > concern, and it has a fix: a help that names the path and the directories above it is true for
  > every DAC EACCES, which covers almost every case a user sees (root-owned files in a CI container,
  > a home directory with mode 700). plt is right that §3.1 allows a help that names a repair that
  > exists, and `chmod`/`chown` is that repair.
  >
  > The aiml/min point that the help "repeats Permission denied" is half true. The head says *that*
  > access was denied. It does not say *where* to look, and the parent-directory case is exactly the
  > one a user misses: they run `ls -l src/m.bl`, see `rw-r--r--`, and get stuck.
  >
  > The cases left over (SELinux/AppArmor, EPERM) are rare on a dev machine, and a help about
  > permissions on the path does not mislead there. It only falls short.
  >
  > So I change my vote.
  >
  > ## Vote: H-E
  >
  > **Reasoning:** EACCES is the common case and has a real repair, so a help line passes §3.1 and
  > adds a fact the head lacks: the denial can be on any directory in the path, not only on the file.
  > This keeps H-D's precision point, because the help names the full path and not only the file's mode.
  >
  > **Concern:** If the writer words it "check the file's permissions" or "check the file mode", the
  > help sends users to the wrong object in the parent-directory case. The help must name the path
  > and the directories that contain it.

**Web/Scripting, Q2 (voted H-E).** Quoted in full from its Phase C reply and its Phase D reply:

  > ## Q2. Help line
  >
  > **Vote:** H-E
  >
  > **Reasoning:** EACCES is the 90% case, and many JS and Python devs do not link "Permission denied"
  > to `chmod` the first time they see it. One true help line costs little and prevents a search on
  > Stack Overflow. The fix for EACCES is real, so the help does not promise a repair that is not there.
  >
  > **Concern:** The writer could make the EACCES help too general, so that it also seems to cover
  > EPERM or SELinux denials, where `chmod` does not help.

  > ## Answer to H-D
  >
  > min and aiml are right that "check the file's permissions" only repeats "Permission denied". If that is the text, I would vote H-D. sys gives the reason the help should exist: the cause is often not the file. A parent directory with no `x` bit is the classic Stack Overflow trap. A user runs `ls -l src/m.bl`, sees `rw-r--r--`, and is lost. "Permission denied" does not tell them to look higher up the path. So a help line for EACCES does add a new fact if it names the path and its parent directories. For example: "the current user cannot open `src/m.bl`; check the mode and owner of the file and of each directory above it". That is not a repeat of the head, and it is true for the common cases (the file mode, a parent dir, a root-owned CI checkout). It does not claim that `chmod` fixes SELinux. When it is SELinux, "check" points at the right place and promises nothing.
  >
  > ## Vote
  >
  > **Vote:** H-E
  >
  > **Reasoning:** The 90% user does not know that EACCES can come from a parent directory, and the head cannot tell them. One help line that names the parent directories saves the search that the bare OS text causes. If the writer cannot say more than the head does, the help line has no value, and H-D is the better outcome.
  >
  > **Concern:** The writer could shorten the help to "check the file's permissions". That only repeats the head and misses the parent-directory case, so it gives the H-D side's cost and none of the gain.

### Final Spec

Locked points:

- The name is `FileReadFailed` and the code is E1025. One code covers every file that is there but cannot be read: an imported `.bl` file, the entry file, `blink.toml`, `blink.lock`, `audits.toml` and an `#embed` file. E1200 and E1108 do not change in meaning.
- The errno of one `open` of the path decides. ENOENT or ENOTDIR (a part of the path before the last is a file) is "not here": the search goes on to the next candidate, and ends in E1200 (E1108 for `#embed`). Any other errno from the open or the read (EACCES, EISDIR, EIO, ELOOP) stops the search with E1025. A dependency of the same name is not tried. EINTR is retried and a short read goes on; neither is reported. A dangling link gives ENOENT. A port to another host maps its errors onto the same not-here and stop rule.
- The span is the module path of the import (the column of `m` in `import m`) or the `#embed` argument. The other files have no span, and the diagnostic names the unreadable file. The code is always in the `--json` stream, and the exit code is 1.
- A missing entry file is a usage error: exit code 2, text only, no code.
- The message head is `read <path>: <os text>`, with no backticks around the path.
- The help line is given only for an errno with one sure repair. Today that is EISDIR on an import: "a module is one `.bl` file, not a directory". EACCES, EIO and the rest get the head line only. An `#embed` file and the TOML files get no help. The EISDIR help is not stretched to ENOTDIR or ELOOP.
- A failed import (E1025 or E1200) binds a poison module (§6.3.5): no W0602 on the import, and no diagnostic on a use of `m.*`.
- The ERROR_CATALOG rows for E1200 and E1108 point to E1025, and the E1025 row states that the split is by errno.

The ticket case:

```blink
import m          // src/m.bl is mode 000

fn main() {
    m.greet()
}
```

```
error[FileReadFailed]: read src/m.bl: Permission denied
  --> src/main.bl:1:8
  |
1 | import m
  |        ^
```

The exit code is 1. This is the only diagnostic: no W0602, and nothing at `m.greet()`.

Spec text: §10.5 *Files That Exist but Cannot Be Read* (the rule, the span table, the help rule, the entry file, the poison rule, and one example for each decided case), §2.4.1 (`#embed`), §8.9.8 (the TOML files), §6.3.5 (the poison rule for a failed import). ERROR_CATALOG.md: E1025 in the code table and in the implementation table (not implemented); cross-references in the E1200 and E1108 rows; the W0602 row.

### Amendments

None.

### Implementation notes

These are not spec text.

- In `--json` the `file` field of a spanless E1025 is the unreadable path. The language server puts a spanless E1025 on the unreadable file (the entry URI, or the `blink.toml` URI) at range 0:0 (sys, devops).
- Tests assert the name and the code, never the OS text, because the text changes with the libc and the locale (sys, min, plt). Tests must also cover an interrupted call (EINTR retried) and a short read (the read goes on), and must not stop at mode 000 (sys). The rule applies to the `#embed` and TOML paths as well as to imports (sys).
- A `src/d.bl` that is a directory made the compiler abort with "out of memory" before this decision. The read must give EISDIR instead, and E1025 follows.
- The language server and the daemon publish the entry-file E1025 and do not exit. The command line prints the plain line today and exits 1.

### Open cases and follow-ups

Raised in the panel. None of these is decided here.

- The E1200 caret is one column late today: for `import m` it sits at column 9, one past `m`. E1025 uses column 8. Every seat that showed a caret in Phase B called column 9 an off-by-one bug in the compiler, not a design point (devops, sys, min, plt, aiml, web).
- W0602 fires on a failed import today. The panel's rule (a poison module, no W0602) is not what the compiler does now, for E1200 as well as for the new code (min, devops, plt).
- The E1200 for an import with no file has no span today (devops). The panel decided the span of E1025 only. The span of the no-file E1200 is not decided.
- What a build does after an unreadable `blink.toml`, `blink.lock` or `audits.toml`. Plt proposed the effect of E1024 (no data, the build fails, the `.bl` files are still checked). The panel decided the code, the span and the exit code, not this.
- A missing entry file in the language server and the daemon. Plt: an opened buffer has no missing-path case. Sys: if it happens, E1025 with "No such file". Not decided.
- A stray unreadable file under `src/` (an editor lock, a link loop) now blocks a build that would have resolved to a dependency (aiml). The panel accepted this as the price of R-E.
- A dangling link gives ENOENT, so it is "not here" and the search can fall through to a dependency of the same name without a message (plt). The panel did not rule that this should be E1025.
- Exit code 2 for a missing entry file changes today's exit code 1. A script that tests for 1 breaks (devops).
