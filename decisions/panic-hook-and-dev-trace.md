[< All Decisions](../DECISIONS.md)

# Panic Hook, Dev Trace and Panic Exit Code — Design Rationale

**Question.** How can a Blink program end with its own report when it hits an internal error, how can it leave development notes without an effect row on each fn, and what exit code does an uncaught panic give?

**Answer.** Three linked rules. (1) `with on_panic(f)` installs a panic hook, a `fn(PanicInfo) -> Never`. It is allowed once, in the body of `main`. The hook runs at the panic point, nothing unwinds, and the row of the hook is charged to `main`. (2) `trace.log(channel, msg)` is a rowless built-in call. The env var `BLINK_TRACE_CHANNELS` turns channels on. `msg` is lazy and may only read state. A trace call does not keep code alive. Lines come in program order with the other stderr writes of the same thread. The default form is a text line, and under `--trace` it is a `note` event. (3) An uncaught panic with no hook exits with code 101.

**Release note.** The exit code of an uncaught panic changes from 1 to 101. A script that tests for exit code 1 after a crash must test for 101. The exit code of a failed `blink test` (1) does not change.

**Spec.** §2.20 (*Panic Hook: `on_panic`*), §4.4 (*Runtime writes are not operations*), §4.6, §4.7, §4.7.2, §8.15.2, §8.15.3, §8.15.5, §8.15.7. Error codes E0565 (`PanicHookPlacement`) and E0566 (`TraceMessageEffect`).

### Decision

| Q | Result | Tally | Dissent |
|---|---|---|---|
| Q1 | 1A: a panic hook | 5-1 | Minimalism: 1B, no hook |
| Q1b | 1b-M: the hook only in the body of `main`, once | 5-1 (after Phase D) | PLT: 1b-S, any `with`, innermost wins |
| Q2 | 2A: a rowless built-in tracer, `trace.log(ch, msg)` | 5-1 | Minimalism: 2B |
| Q2b | 2b-R: `msg` is lazy and may only read state | 5-1 | Minimalism: 2b-E |
| Q2c | 2c-D: a trace call does not keep code alive | 5-1 (after Phase D) | AI/ML: 2c-K, the call keeps code alive |
| Q2d | 2d-O: program order with the stderr writes of the same thread | 6-0 | none |
| Q2e | 2e-N: a text line by default, a `note` event under `--trace` | 5-1 | Minimalism: 2e-T, always a text line |
| Q3 | 3A: an uncaught panic with no hook exits 101 (was 1) | 6-0 | none |

**Phase D moves.** Web moved from 1b-S to 1b-M. Web and Minimalism moved from 2c-K to 2c-D. AI/ML moved from 2c-D to 2c-K. DevOps moved from 2d-U to 2d-O in Phase C.

**Follow-up.** A module `let mut` is one cell for all threads, and the language has no per-thread state. A hook in a threaded server that must name the current request can name the wrong one. PLT's dissent (1b-S) wanted a hook held in a closure with its own state. A later spec can add per-thread state for a hook.

### Panel Deliberation

Six seats voted: Systems, Web/Scripting, PLT, DevOps/Tooling, AI/ML and Minimalism. Each quote below is the full text of the reply of the seat, copied without change. The only edit: a ticket ID in the heading of one reply is removed. The text of the moderator rounds is not quoted.

#### Phase A — Independent proposals

Each seat proposed alone.

**Systems**

> # sys — Phase A
>
> Reject (b) and (c). (b) puts `! IO.Eprint, IO.Print, Env.Exit` on ~3000 node accessors. These
> are hot leaf fns. If a row lowers to passed evidence or a handler lookup, each one pays for a
> path that runs once per crash. (c) costs a fork and an IPC frame per LSP check to recover one
> error frame. An ICE is an invariant violation, so it is a panic (l.1106). The gap is the shape
> of the abort, not the row.
>
> ## S1 — Q1, Q3: a process-wide abort hook installed from a rowed root
>
> `panic.on_abort(h)` registers one hook, type `fn(PanicInfo) -> Never ! R`. The checker charges
> `R` to the caller of `on_abort` (E0500 if the caller lacks it), so the row is proven where the
> capability exists (`main`). Panic sites keep no row.
>
> On a panic outside a test:
> - with no hook: as today. Stderr `panic: <msg> at <file>:<line>`, exit 1.
> - with a hook: the runtime writes nothing. It runs the hook once. The hook's ops go to the root
>   handlers, never to a `with` around the panic site. The hook's `env.exit(n)` sets the code.
> - a panic inside the hook: the default report, exit 1. No recursion (Rust's double panic).
> - a second thread that panics while the hook runs: it parks. The first panic wins.
> - inside a test: the test runner's catch frame takes the panic and the hook does not run.
>
> The hook never returns into user code. It is not a catch boundary, so the closed catch set of
> §4 (l.3936) still holds. `exit()`/`close()` stay skipped, as for any panic.
>
> ```blink
> fn main() ! IO, Env {
>     panic.on_abort(fn(p: PanicInfo) -> Never ! IO.Print, IO.Eprint, Env.Exit {
>         io.eprint(ice_report(p.message, p.file, p.line))
>         io.print(ice_state.abort_stdout)
>         env.exit(101)
>     })
>     run()
> }
>
> fn deep() {
>     panic("ice")
> }
>
> fn f() -> Int {
>     deep()
>     1
> }
> ```
>
> `f` compiles with no row. Stderr: the ICE report. Stdout: the abort frames. Exit 101.
>
> The MVCE as written (`io.eprintln` + `env.exit` in `deep`) does not change: `f` gets E0500.
> This is correct. Those calls are ops.
>
> Capability: unrowed code can still only stop the process, as it can today. Only the code that
> holds `Env.Exit` picks the code and the output. Sandboxed code cannot install a hook.
>
> Cost: one global fn pointer, read only on the panic path. Zero on the hot path, no change to
> codegen of any panic site.
>
> Cross-language: Rust `std::panic::set_hook` (plus `process::exit` in the hook), Go has no hook
> and pays with wrappers in each goroutine.
>
> ## S2 — Q2: dev channel tracing is runtime trace output
>
> `dbg_trace` as written is an ordinary `IO.Eprint` op, and stays so. Add a builtin
> `trace.log(ch: Str, msg: Str)`. It belongs to the §8.15 class: the runtime writes it to stderr,
> it has no row, and no handler receives it. The runtime reads `BLINK_TRACE_CHANNELS` once at
> start. If `ch` is not on, the site costs one load and one branch, and `msg` is not evaluated
> (as with `debug_assert`). Effects inside `msg` are still charged to the caller.
>
> ```blink
> fn lower(n: Node) -> Ir {
>     trace.log("mono", "lower {n.kind}")
>     lower_inner(n)
> }
> ```
>
> `BLINK_TRACE_CHANNELS=mono`: stderr `[trace:mono] lower Call`, stdout unchanged, exit unchanged.
> Unset: no output.
>
> Tradeoff: a test cannot capture it. That is the point. It is diagnostics, not behavior, so a
> test that needs the text uses `io.eprintln` and its row.
>
> Cross-language: Rust `log!` checks the level before it formats, Go `GODEBUG` is read by the
> runtime, Zig `std.log` is rowless by design.

**Web/Scripting**

> # web seat — Phase A
>
> Trigger test: a Python dev adds one debug print 20 frames deep, and the compiler asks for `! IO.Eprint` on 40 functions. That is the top Stack Overflow question for this feature. A crash report that needs a row on every function is the second. Fix both with two small, familiar tools. Keep rows honest for real I/O.
>
> ## Proposal 1: `panic_hook` in `main` (Q1, Q3)
>
> A built-in `with` item, allowed only in the body of `main`. Its closure gets the panic and must diverge. It does not recover: the program cannot resume.
>
> ```blink
> fn deep() -> Never {
>     panic("parser limit: node kind 99")
> }
>
> fn f() -> Int {
>     deep()
>     1
> }
>
> fn main() ! IO, Env {
>     with panic_hook(fn(p: PanicInfo) -> Never {
>         io.eprintln("error: internal compiler error: {p.message}")
>         io.println("status: ice")
>         env.exit(101)
>     }) {
>         io.println("{f()}")
>     }
> }
> ```
>
> stdout: `status: ice`. stderr: `error: internal compiler error: parser limit: node kind 99`. Exit 101. The runtime's own `panic: ... at file:line` line does not print. The hook decides what to write.
>
> Rules:
> - The panic unwinds out of the `with` body first, so each `close` inside it runs, then the hook runs. Python's `finally` blocks run before `sys.excepthook` in the same order.
> - The hook's effects are checked against `main`'s row (E0500 if `main` lacks them). It must be `-> Never`. A closure that can return is E0311.
> - `panic_hook` outside `main`, or a second one, is a new error.
> - A panic inside the hook prints both messages through the runtime and exits 101.
> - Test blocks and `assert_panics` do not change. `main` does not run under `blink test`.
>
> Q3: an uncaught panic with no hook exits **101** (Rust's code), not 1. A CI script can then tell "the tool crashed" from "the tool said no". With a hook, the exit code is whatever the hook passes to `env.exit`.
>
> The MVCE as written still gets E0500 in `deep`, because it uses real ops with no row. That is correct. In the rewrite above, `deep` and `f` have no row. The compiler's `diag_ice_abort` becomes "record state, then `panic`", and `main` owns the stdout frames and the exit code.
>
> Tradeoffs: the hook is a second exit path that a reader must know about, but only `main` can have one, so a reader finds it in one place. The LSP server still ends on an ICE, as it does today. A server that must keep running uses a child process (option c). The catch-boundary set stays closed.
>
> Cross-language: Node `process.on("uncaughtException")` (must exit), Python `sys.excepthook`, Rust `std::panic::set_hook` + exit 101, Go's `recover` in `main` only.
>
> ## Proposal 2: built-in `dbg(channel, msg)` (Q2)
>
> A rowless built-in that joins the runtime-write list in 04_effects l.468, next to `--trace` output. It writes `[dbg:<channel>] <msg>` to stderr only when the channel is on at run time: `BLINK_DBG=parse,mono` or `BLINK_DBG=all`. The runtime reads the env var, so the call has no `Env.Var` op.
>
> ```blink
> fn lower(n: Int) -> Int {
>     dbg("mono", "lower {n}")
>     n * 2
> }
> ```
>
> `BLINK_DBG=mono ./app` writes `[dbg:mono] lower 3` to stderr. With the channel off it writes nothing. Exit codes do not change. No handler gets the text (`capture_eprint` does not see it). No API tells the program whether a channel is on, so the program cannot branch on it. Its only visible effect is diagnostic text, the same as `--trace`. `msg` is evaluated each time, so wrap a costly message in a helper only when you need to.
>
> Tradeoffs: someone will use `dbg` as a logger. Because it is env-gated, not capturable, and has a fixed prefix, it is a bad logger, and that is on purpose. Real logs stay `io.eprintln` with a row. The compiler's `dbg_trace` becomes `dbg`, and 38 sites lose their rows.
>
> Cross-language: Rust `dbg!`, Python `logging.debug` with an env level, Node's `DEBUG=ns` package (the same `DEBUG=a,b` pattern).
>
> ## Rejected
>
> (b) rows through ~3000 functions: right in theory, but they hide each real I/O row behind noise. Panic as-is (a): loses the LSP frames that editors need.

**PLT**

> # plt — Phase A
>
> Principle: a row is an upper bound on what a call can do that the program (or a handler) can observe. A rowless construct is sound only if it is bottom (divergence) to every Blink observer. `panic` qualifies. "Write stdout frames, then exit 101" does not, unless something holds the rows for those writes. So the rows must go to the scope that wants the report, not to the 3000 fns that can fail.
>
> ## P1 (main): panic + a scoped abort hook (Q1, Q3)
>
> New `with` item `on_abort(hook)`, where `hook: fn(Str) -> Never ! R`. The `with` site is charged `R`, checked there. In the dynamic extent of the body, an uncaught panic calls `hook(msg)` at the panic point. Its ops go to the handlers in scope at the `with` (captured, as in Koka), not to those at the panic site. The hook cannot return (`Never`), so this is not recovery. Nothing unwinds, and no `exit()`/`close()` runs. The §4.7.2 catch-boundary set and its fence do not change. A panic inside the hook gets the default runtime report and exit code.
>
> ```blink
> fn deep() -> Never { panic("ice: node limit") }
> fn f() -> Int { deep() }          // no row: compiles
>
> fn report(msg: Str) -> Never ! IO.Print, IO.Eprint, Env.Exit {
>     io.eprintln("error[ICE]: {msg}")
>     io.print(ice_frames(msg))     // LSP -32603 + publishDiagnostics
>     env.exit(101)
> }
>
> fn main() ! IO, Env {
>     with on_abort(report) {
>         io.println("{f()}")
>     }
> }
> ```
> stderr `error[ICE]: ice: node limit`, stdout the frames, exit 101. The default `panic: ...` line does not print. That is the hook's choice.
>
> MVCE: as written, `deep` performs `IO.Eprint` and `Env.Exit`, so `f` still needs the row (correct: that is an ordinary program). With `deep` rewritten to `panic`, `f` is pure and `main` pays for the report once.
>
> Q3: with a hook, the code is whatever the hook passes to `env.exit`. Without a hook, the spec must name one fixed code for an uncaught panic. I favor 101 (Rust), so a crash is never the same as `env.exit(1)`. Today the runtime exits 1, so this is a behavior change. The panel must vote it.
>
> Tradeoffs:
> - + Sound. No new rowless write. The capability for the report is visible at one site.
> - + Composes. Nested `on_abort`: innermost wins. It is lexically scoped, unlike Rust's global `set_hook`.
> - − The hook runs at the panic point, in a state that may be corrupt. It must not trust program data. Same as `Printexc.set_uncaught_exception_handler` (OCaml) and Rust panic hooks.
> - − Inside a test, the runner frame and the hook overlap. Rule: the nearest boundary wins, so a hook inside a test body runs, and its `env.exit` goes to the test's `Env` handler (a mock must panic, which ends at the runner). The writer must state this.
> - − LSP: one ICE ends the server (exit 101, as tests pin today). An LSP that must survive runs each check in a child process (ticket option c). In-process survival needs recovery, which I reject: it reopens §4.7.2.
>
> ## P2: dev-channel tracing (Q2)
>
> `dbg_trace` as written is an `IO.Eprint` op, not "trace output" in the l.468 sense. A `capture_eprint` handler can see it, and that must stay true for `io.eprintln`.
>
> Sanctioned route: a new runtime builtin, `trace(ch: Str, msg: Str)`, no row, joins the §8.15 trace output. It writes only when the runtime enables channel `ch` (`--trace`/`BLINK_TRACE`), and no handler receives it. The rule that keeps it sound: its output is not program behavior. The compiler may move, merge or drop a call, and order with stdout is not defined. This is Haskell's `Debug.Trace.trace`. The list stays closed with five entries.
>
> ```blink
> fn walk(n: Int) -> Int {
>     trace("walk", "n={n}")       // no row
>     n + 1
> }
> ```
> `BLINK_TRACE=walk` → stderr `[trace:walk] n=3`. Without it, nothing prints.
>
> Tradeoff: tests cannot assert on `trace` output, and that is by design. Code that must be checked uses `io.eprintln` and carries `IO.Eprint`.

**DevOps/Tooling**

> # devops seat: Phase A
>
> ## Proposal D1: an ICE is a panic; a panic exits 101; the process boundary writes the frames
>
> **Q1.** There is no rowless abort that writes stdout. An ICE is an invariant violation, which is what `panic` is for (04_effects l.1106). The spec fixes the panic exit code at **101**. This is a change: a panic exits 1 today, the same code as `env.exit(1)`, so CI cannot tell "the tool crashed" from "the tool found errors". After the change the codes are: 0 ok, 1 reported failure, 2 usage error, 101 crash.
>
> **Q3.** An ICE exits 101 because every panic does. The status line goes into the panic message.
>
> ```blink
> fn node_kind(id: Int) -> Int {
>     if id < 0 {
>         panic("internal compiler error: node_die [E9001]: bad node id {id}")
>     }
>     id % 7
> }
> ```
> stdout: nothing. stderr: `panic: internal compiler error: node_die [E9001]: bad node id -1 at ast.bl:3`. Exit 101. `node_kind` and its 3000 callers carry no row.
>
> **LSP / JSON frames.** The parent process writes them, not the process that crashed. The LSP server (or `blink build --json` driver) runs each check in a child (`process.run`), reads `r.end` = exit 101 plus `r.err_out`, and writes the `-32603` reply and an empty `publishDiagnostics` itself. Only the top of the server needs `! Process`. cargo does this for rustc ICEs, and VS Code restarts a crashed tsserver the same way.
>
> **MVCE.** `fn deep() { io.eprintln("ice"); env.exit(101) }` still needs `! IO.Eprint, Env.Exit`, and so does `f`. No change, and none is needed. The fix is `fn deep() -> Never { panic("ice") }`. Then `f` compiles with no row, stderr is `panic: ice at mvce.bl:1`, and the exit code is 101.
>
> Diagnostic surface: when the missing-row error on a call traces back to an `io.eprint*` call followed by `env.exit(n)` with n != 0, add a help line: `help: for an internal error, use panic(...) (exit 101, no row)`.
>
> Tradeoffs:
> - Some tests change: the 9 parser-limit tests keep exit 101 but match the panic line, not the ice JSON row. The LSP tests move their frame checks to the parent.
> - A child process per check costs a spawn (milliseconds). In return, an LSP that hits an invariant violation does not keep serving from corrupt state, which an in-process recover would allow.
> - This adds no new rowless route, so the closed list stays closed.
>
> Cross-language: Rust panics exit 101 and rustc ICEs are panics. Go panics exit 2. Python's uncaught exceptions exit 1, which is the collision D1 removes.
>
> ## Proposal D2: `debug_trace` joins trace output (§8.15)
>
> **Q2.** Today `dbg_trace` is an ordinary `IO.Eprint` op, and so is anything a user writes in Blink. D2 adds one built-in, `debug_trace(channel: Str, msg: Str)`, as part of the §8.15 trace output. It is rowless and no handler receives it. The runtime reads `BLINK_TRACE_CHANNELS` once at start-up, as the runtime does for `--trace`; this read is not an `Env.Read` op. The call does nothing unless the variable names the channel or `all`.
>
> ```blink
> fn lower(id: Int) -> Int {
>     debug_trace("mono", "lower {id}")
>     id + 1
> }
> ```
> `BLINK_TRACE_CHANNELS=mono`: stderr is `[trace:mono] lower 4`, stdout is unchanged, exit 0. With the variable unset, nothing is written. `lower` carries no row.
>
> Tradeoffs:
> - It adds no capability: `panic(msg)` already writes any text to stderr with no row. `debug_trace` only writes that text without ending the process. The output cannot reach stdout, a handler or a return value, so the row still tells the truth about what the program does.
> - A formatter or linter may want `W` "debug_trace left in a pub fn of a published package". That is a tooling choice, not a spec rule.
> - Rejected: a general rowless `@ffi` stderr write. It is an open-ended exemption with no fixed format.
>
> Cross-language: Haskell `Debug.Trace` (rowless on purpose), Rust `dbg!`, and Go's `GODEBUG` env-gated runtime output.
>
> ## Vote intent
> D1 + D2 together. If the panel rejects D2: `dbg_trace` stays an op with an `! IO.Eprint` row. I would not accept the ~3000-fn row (option b) for the ICE path.

**AI/ML**

> # aiml — Phase A
>
> My test for each option: what does a model have to decide at each call site? Option (b) puts a
> decision about the row in about 3000 deep fns. Option (c) puts a process design in every tool.
> I want deep code to need one rule: **an invariant break is `panic`**. The entry point alone
> decides how the abort looks.
>
> ## P1 (Q1): `with on_panic(f)`, a diverging abort hook with its row at the install site
>
> - New builtin with-item `on_panic(f)`, where `f: fn(PanicInfo) -> Never`. `PanicInfo` has
>   `message: Str`, `file: Str`, `line: Int`.
> - `f`'s row goes into the row of the fn that holds the `with`, the same way a handler clause's
>   row does. Code under the `with` keeps an empty row.
> - A panic in its dynamic scope calls `f` at the panic site. `f` cannot return (it is `-> Never`,
>   so a missing exit is a compile error, §3.3) and cannot resume. This is not a catch: the
>   process still ends. The innermost hook wins. A panic inside `f` gets the default report.
>
> ```blink
> fn deep() -> Int {
>     panic("node kind 99 out of range")
> }
>
> fn f() -> Int {
>     deep() + 1
> }
>
> fn main() ! IO, Env.Exit {
>     with on_panic(fn(p: PanicInfo) -> Never {
>         io.eprintln("error[ICE]: {p.message} at {p.file}:{p.line}")
>         io.println("{\"status\":\"ice\"}")
>         env.exit(101)
>     }) {
>         io.println("{f()}")
>     }
> }
> ```
>
> stderr: `error[ICE]: node kind 99 out of range at main.bl:2`. stdout: `{"status":"ice"}`.
> Exit code 101. `deep` and `f` carry no row.
>
> **MVCE:** it stays as it is. `io.eprintln` and `env.exit` are ordinary ops, so `f` needs
> `! IO.Eprint, Env.Exit` (the missing-row error as today). The fix is to call `panic("ice")` in
> `deep` and install the hook in `main`. In the compiler, `diag_ice_abort` moves into the hook
> body and the LSP loop installs a hook that writes the frames.
>
> Tradeoffs: one new name, one rule, and the `Never` typing models already know. An LLM can fail
> in one way here: it may write the hook as a catch that returns. The §3.3 body-completeness error for a
> `-> Never` body that falls through catches that, so no new code. Cross-language: Rust `panic::set_hook` + `process::exit`, Python
> `sys.excepthook`. Both are well known to models, but Blink scopes the hook and gives it a row.
>
> ## P2 (Q2): user notes go into the §8.15 trace stream, and `io.eprintln` stays an op
>
> - New rowless `trace.note(channel: Str, msg: Str)`. No handler receives it. It writes a fifth
>   event kind, `note`, into the §8.15 NDJSON stream, and only when tracing is on and the filter
>   matches (`--trace=note:mono`). When tracing is off, it writes nothing.
> - The closed list stays at four kinds, because this is "trace output (§8.15)".
> - An env-gated `io.eprintln` (today's `dbg_trace`) stays an ordinary `IO.Eprint` op.
>
> ```blink
> fn lower(n: Int) -> Int {
>     trace.note("mono", "lower {n}")
>     n * 2
> }
> ```
>
> With `--trace=note:mono`, stderr gets
> `{"ts_us":40,"event":"note","fn":"main.lower","module":"main","depth":1,"channel":"mono","msg":"lower 3"}`.
> Without the flag, it writes nothing. The fn has no row.
>
> Tradeoffs: models will reach for `trace.note` as free logging. The fixed NDJSON shape and the
> opt-in flag make it a poor log, so the misuse stays small. Cost: §8.15.2 calls its four events
> "complete", and that claim changes. Cross-language: Rust `tracing` events and Go `runtime/trace`
> user annotations.
>
> ## P3 (Q3): an unhooked panic exits 101
>
> With no hook, stderr gets `panic: <text> at <file>:<line>`, stdout gets nothing more, and the
> exit code is 101 (the value Rust uses). This lets a script tell a crash apart from
> `env.exit(1)`. One fixed, documented number costs a model nothing to learn. Under P1, the hook
> picks the code. The test runner rule ("a panic has no exit code of its own") stays.

**Minimalism**

> # Min (Phase A): keep the closed list closed; pin the panic exit code
>
> The spec works. The ~3000-fn cost exists because the compiler uses `exit` deep inside node accessors. That is a design choice in one program, not a gap in the language. Adding a rowless write means a fifth exemption, and l.468 closes the list on purpose. My proposal is one pin and no new surface.
>
> ## M1 (recommended)
>
> **Q1: no rowless abort-with-report.** Blink programs have two routes, and both exist today:
> - *Invariant violation* (a bad node index, an unknown kind in fmt): `panic`. No row. The runtime writes the message to stderr. Nothing goes to stdout.
> - *Reportable condition* (a parser limit that user input hits): return a value to a root that holds the rows. Only `main` (or the LSP loop) carries `! IO, Env.Exit`.
>
> ```blink
> type ParseStop { code: Str  message: Str }
>
> fn parse_expr(p: Parser) -> Result[Node, ParseStop] {
>     if p.depth > 512 {
>         return Err(ParseStop { code: "E9001", message: "nesting limit" })
>     }
>     ...
> }
>
> fn main() ! IO, Env.Exit {
>     match parse_file(src) {
>         Ok(ast) => run(ast)
>         Err(s) => {
>             io.eprintln("ice: {s.code} {s.message}")
>             io.print(abort_stdout)
>             env.exit(101)
>         }
>     }
> }
> ```
>
> `?` carries the stop up the parser. That is about 80 parse fns, not 3000 accessors, and the accessors stay pure. A tool that must write a frame after a *panic* runs the work in a child process. The parent holds the rows and reads `ChildEnd`:
>
> ```blink
> fn check_doc(uri: Str, id: Int) ! IO.Print, Process.Spawn {
>     match process.run("blinkc", ["--check", uri]) {
>         Ok(r) => match r.end {
>             ChildEnd.Exited(0) => io.print(r.out)
>             _ => io.print(lsp_error_frame(id, -32603, r.err_out))
>         }
>         Err(e) => io.print(lsp_error_frame(id, -32603, "{e}"))
>     }
> }
> ```
>
> **Q2: `dbg_trace` is an ordinary op.** It is Blink code that writes to stderr, so it is `IO.Eprint`. "Trace output (§8.15)" means only the runtime's `--trace` NDJSON. But §8.15 already does what `dbg_trace` does. Make the tracer a pure no-op and filter on it:
>
> ```blink
> fn dbg_trace(ch: Str, msg: Str) { }
> ```
> ```sh
> blink run src/cli.bl --trace=fn:dbg_trace 2>t.ndjson
> jq 'select(.args.ch == "mono")' t.ndjson
> # {"event":"enter","fn":"ast.dbg_trace","args":{"ch":"mono","msg":"..."},...}
> ```
>
> No row, no new feature. Callers pay for building `msg` even with tracing off, as they do today. Open point: §8.15 shows `--trace` only on `blink run`. A traced build of a tool binary needs the same flag on `blink build`. That is a CLI flag, not language surface.
>
> **Q3: pin the exit code of an uncaught panic at 101.** §2.20 says only "terminates the process with a stack trace". It gives no exit code, and today the runtime exits 1. That is a real gap: a script cannot tell "the tool said no" (1) from "the tool is broken". Rust uses 101 for this reason. With the pin, an ICE that goes through `panic` keeps exit 101 and a `panic: ...` line on stderr. It loses the stdout frames, and M1 says that is correct: a broken program does not report on stdout.
>
> **The MVCE under M1:** no change. `deep` and `f` fail with `UndeclaredEffect` (E0500) for `IO.Eprint` and `Env.Exit` until each one declares them. The fix is `fn deep() { panic("ice") }`: no row, stderr `panic: ice at m.bl:1`, exit 101. Or `deep` returns a `Result` to `main`.
>
> ## M2 (fallback)
>
> Same as M1, but keep a panic exit of 1 and pin that. This costs less runtime churn but leaves "user error" and "crash" with one code.
>
> ## Tradeoffs
>
> - Adds zero syntax, effects or exemptions. The l.468 list stays closed, and "no row means no side effect" stays true without exceptions, so an agent can still trust it.
> - The cost lands on the compiler: one Result refactor of the parser, a supervisor in the LSP, and ~14 ICE tests that move from the json row to the panic line.
> - Rejected: a rowless `@ffi` abort. It is an exemption with an audit key in name only, and every library would copy it.
> - Cross-language: Go's `os.Exit` and `panic` take this split (gopls uses `recover`, which Blink refuses by design, §4.7.2). Erlang's supervisor model is the same as the child-process route. Rust has the exit code of 101.

#### Phase B — Debate

Round 1.

**Systems, round 1**

> # sys — Phase B round 1
>
> ## Q1: 1A, and I move to plt's form
>
> **1A-i scope: concede to a `with` item, dynamic extent, innermost wins (plt/aiml).** My
> global `panic.on_abort` makes the LSP loop keep the uri and request id in global state. A
> per-request `with on_abort(...)` holds them in the closure. Cost: one thread-local pointer saved
> and restored at each `with`, which is less than any handler install. Against web's "only in
> `main`": the LSP loop is not `main`, and it is the motivating case.
>
> **1A-ii: nothing unwinds (plt).** Against web: to run each `close` before the hook, panic
> must unwind. Outside a test, today it does not, so each frame with a `with` would need cleanup
> records on the panic path, and `close` would run in state the panic just called broken.
>
> **1A-iii: concede to plt.** The hook's ops go to the handlers in scope at the `with`. At `main`,
> those are the root handlers, so my rule is a special case. The runtime records the handler-stack
> depth at install time and resets to it before it calls the hook.
>
> **1A-iv: `PanicInfo { message, file, line }`.** The runtime already has the location, so it
> costs nothing. An LSP frame wants it, and `Str` throws it away.
>
> **1A-v: concede to plt.** The nearest boundary wins: a hook, `assert_panics` or the runner frame.
> **1A-vi:** default report, exit 101.
>
> ```blink
> fn serve(uri: Str, id: Int) ! IO.Print, IO.Eprint, Env.Exit {
>     with on_abort(fn(p: PanicInfo) -> Never ! IO.Print, IO.Eprint, Env.Exit {
>         io.print(lsp_abort_frames(uri, id, p.message))
>         env.exit(101)
>     }) {
>         io.print(check(uri))
>     }
> }
> ```
> Stdout gets the -32603 frame and `publishDiagnostics`. Exit 101. `check` and all it calls have no row.
>
> **1B:** min's Result route puts a branch on each return in the parser's hot path to report a
> path that runs once per crash. The child-process route for a server that must survive is fine,
> and every seat accepts it, but it does not cover the CLI status line and JSON row. 1A costs
> nothing until a panic.
>
> ## Q3: concede to 3A, 101
>
> A crash code that differs from `env.exit(1)` costs nothing at run time. I drop 3B.
>
> ## Q2: 2A
>
> - **2A-iii: keep `msg` lazy.** It lowers to `if trace_on(ch) { trace_write(ch, msg) }`.
>   Interpolation allocates. Web's eager form charges an allocation at each of 38 sites in hot
>   compiler loops when every channel is off.
> - **2A-iv: accept plt.** A trace call does not keep code alive. The optimizer can still drop a
>   pure fn, so this is what makes a rowless write sound.
> - **2A-v: accept web.** No API can ask if a channel is on. If the program could branch on it,
>   2A-iv would be unsound.
> - **2A-i: a text line `[trace:<ch>] <msg>`.** When `--trace` is also on, the same call goes into
>   the NDJSON stream as an event so that stderr stays valid NDJSON. Two formats mixed on one
>   stream breaks `jq`.
> - **2B (min): reject.** `--trace=fn:dbg_trace` needs a build with enter/exit events on every
>   fn, which costs far more than one branch. A no-op `dbg_trace` also evaluates `msg` each time.
>
> ## Writer notes
> - Say the hook runs at the panic point, with the handler stack reset to its install depth.
> - Name the env var once (`BLINK_TRACE_CHANNELS`).
>
> NOT STABLE: 2A-i (a text line, plus an NDJSON event when `--trace` is on, against aiml's
> NDJSON only), and whether web and aiml accept plt's 1A-v nearest-wins rule inside tests.

**Web/Scripting, round 1**

> # web — Phase B round 1
>
> ## Q1: 1A over 1B
>
> 1B makes a CLI author learn process supervision before they can print a crash report. Python devs reach for `sys.excepthook` and Node devs for `uncaughtException`, so 1A passes the 5-minute test. I agree with min on one point: a limit that user input can hit is better as a `Result` to `main`. That is advice for the compiler, not a rule in the spec.
>
> **1A-i scope: I concede to plt/aiml.** A `with` item allowed anywhere, and the innermost one wins. I drop my main-only rule, because an LSP loop that is not `main` needs it too. I oppose sys's process-wide `panic.on_abort`: a library that installs a global hook takes it from the app, and Rust's `set_hook` has that problem.
>
> **1A-ii unwind: I concede.** The hook runs at the panic point, with no unwind and no `exit()`/`close()` call. That is what an uncaught panic does today, so the change adds no new cleanup semantics. The process ends anyway.
>
> **1A-iii: plt's rule.** The hook's ops go to the handlers in scope at its `with`. A reader can find each op where the `with` is written.
>
> **1A-iv: `PanicInfo { message, file, line }`.** Devs want the location. A bare `Str` makes them parse it out.
>
> **1A-v: plt's rule (nearest boundary wins).** It lets a test check a hook:
>
> ```blink
> test "hook writes the ICE frame" {
>     assert_panics(matching: "exit 101") {
>         with mock_env_exit() {        // its exit op panics "exit {code}"
>             with on_abort(report) {
>                 panic("ice")
>             }
>         }
>     }
> }
> ```
>
> The hook runs, `env.exit(101)` goes to the mock, the mock panics, and that panic goes to `assert_panics`. The test passes.
>
> **1A-vi:** a panic inside the hook gets the default report and the default exit code. I drop my "both messages" wording.
>
> ## Q2: 2A, not 2B
>
> 2B (an empty fn plus `--trace=fn:` plus `jq`) fails the 5-minute test.
>
> - **2A-i/ii:** a text line `[trace:<ch>] <msg>`, turned on by `BLINK_TRACE_CHANNELS`. I drop `dbg`/`BLINK_DBG`. aiml's NDJSON `note` is fine as an extra form under `--trace`, but a human reads the text line.
> - **2A-iii: I concede to sys.** When the channel is off, `msg` is not evaluated. "Why does my f-string run when logging is off?" is a classic Python question. Effects inside `msg` are still charged to the caller.
> - **2A-iv: I oppose plt's "move, merge or drop".** With the channel on, a dev who adds a trace and sees nothing, or sees lines out of order, stops trusting the tool. My rule: with the channel on, each call that runs writes its line once, in program order with the other stderr writes of its thread. Order against stdout is undefined (it is a different stream).
> - **2A-v:** no API to ask whether a channel is on. Otherwise a program could branch on it.
>
> ## Q3: 3A, 101
>
> I keep 101.
>
> ## Writer notes
>
> - Pick one name: `trace.log`, `trace`, `debug_trace` or `trace.note`. I lean to `trace.log(ch, msg)`, a namespace call like `io.eprintln`.
> - Hook name: `on_abort` or `on_panic`. `on_panic` says when it runs.
>
> NOT STABLE: 2A-iv (may the compiler drop or reorder an enabled trace call?) and 1A-i (a scoped `with` or a global hook).

**PLT, round 1**

> # plt — Phase B round 1
>
> ## Q1: I keep 1A, and I narrow it to web's scope
>
> **1A-i / 1A-iii (scope and handlers) are one question.** §4.5 says no Blink op skips a handler its row names. sys charges `R` to the caller of `on_abort` but sends the ops to the root handlers. If a test or wrapper puts a mock `Env` around that caller, the hook's `env.exit` skips the mock. That breaks the §4.5 rule. Two sound fixes exist: send the ops to the handlers in scope at the install site (my Phase A rule), or allow the hook only in `main`, where those handlers are the root ones. I concede to web's form: a `with` item, only in `main`'s body, one per program, and the ops go to the handlers in scope at that `with`. A hook in a library is a problem, because "innermost wins" lets any dependency take over the app's crash report. The process-wide call form (sys) makes the result depend on the order of calls (a panic before the call gets no hook), so I reject it.
>
> **1A-ii (unwind first): reject web's rule.** If `close()` runs on a panic path, the hook is a catch boundary in the §4.7.2 sense. The spec fences that boundary set and calls for a separate amendment before it changes. Rule: nothing unwinds, and the hook runs at the panic point. If the panel wants unwind-first, it must be a separate option, because it reopens §4.7.2.
>
> **1A-iv:** I concede `PanicInfo { message, file, line }`. It is plain data and does not affect soundness.
>
> **1A-v:** sys's rule. Under the test runner, the runner frame takes the panic and the hook does not run. This holds even when a test calls `main()`.
>
> **1A-vi:** a panic inside the hook gets the default report and the default exit code (101 under 3A), with no second call to the hook.
>
> **1B** is compatible with 1A, not a rival. A parser limit that user input can hit is better as a `Result` (min). An LSP that must keep running needs a child process under any option. I vote 1A because the language should give an invariant break one route that is free of rows, and that route is `panic`.
>
> ## Q2: 2A, plus one soundness rule
>
> **2A-iii is the soundness point.** If `msg` is skipped when the channel is off, and `msg` has effects, then program behavior depends on an env var with no `Env.Read` row:
>
> ```blink
> fn noisy() -> Str ! IO.Print {
>     io.println("side")
>     "m"
> }
>
> fn f() ! IO.Print {
>     trace.log("x", noisy())   // stdout gets "side" only if BLINK_TRACE_CHANNELS has x
> }
> ```
> Rule: `msg` must have the empty row. A row on `msg` is a compile error. With that rule, skipping `msg` is safe and cannot be seen. Without the rule, `msg` must be evaluated each time, as web says.
>
> **2A-v** (no API asks whether a channel is on) is required for the same reason. **2A-iv** (calls can be moved or dropped) is required, because without it the spec would promise an order relative to `IO` ops that no row backs. **2A-i/ii:** I have no PLT stake. aiml's NDJSON `note` fits "trace output (§8.15)" literally.
>
> 2B is sound and the smallest option. My second choice.
>
> ## Q3: 3A (101).
>
> NOT STABLE: 1A-ii (unwind before hook) must leave 1A or become its own option; 2A-iii needs the empty-row rule on `msg`, or `msg` must be evaluated each time.

**DevOps/Tooling, round 1**

> # devops: Phase B round 1
>
> ## Q1: I move from 1B to 1A, as a scoped `with`
>
> I give up D1's "the parent writes the frames". With a hook, the LSP still ends on an ICE, but it first writes the `-32603` reply and `publishDiagnostics`. That is the shape the 3 LSP tests and the daemon test pin today. The editor shows the error, then restarts the server. Under 1B every tool needs a supervisor process before it can report a crash. A child process stays the route for a server that must keep running.
>
> My picks on the variations:
> - **1A-i scope:** a `with` item, innermost wins (plt/aiml). The LSP needs a hook per request that captures `uri` and `id`. Today the compiler keeps these in the global `diag_ice_state.abort_lsp_uri`. A global hook (sys) or a `main`-only one (web) puts them back in a global.
> - **1A-ii:** no unwind. A `close` that does I/O would write text before or between the frames.
> - **1A-iii:** the hook's ops go to the handlers in scope at the `with` (plt). The row is checked at the `with`, so its ops must resolve there too.
> - **1A-iv:** `PanicInfo { message, file, line }`. A diagnostic needs the location. When the runtime has no location, follow §8.10's rule: no placeholder `line: 0`.
> - **1A-v:** the nearest boundary wins (plt). Then a test can check the hook's frames in-process:
>
> ```blink
> import std.testing.{mock_env, capture_print}
>
> test "ICE hook writes the error frame" {
>     let out: List[Str] = []
>     let me = mock_env()
>     assert_panics(matching: "env.exit(101)") {
>         with capture_print(out), me.as_handler(), on_abort(report) {
>             node_kind(-1)
>         }
>     }
>     assert(out[0].contains("-32603"))
> }
> ```
> - **1A-vi:** a panic inside the hook is an ordinary panic with no hook. It goes to the next boundary out: `assert_panics`, the test runner, or the default report. The default report prints both messages (web). The first message caused the crash and must not be lost.
>
> I keep the help line, reworded: `help: for an internal error, call panic(...) and install on_abort at the root`.
>
> ## Q2: 2A; I reject 2B
>
> `--trace=fn:dbg_trace` turns on the whole trace stream to read one channel, and §8.15 shows the flag only on `blink run`.
> - **2A-i/ii:** a text line `[trace:<ch>] <msg>` when `BLINK_TRACE_CHANNELS` names the channel. When `--trace` NDJSON is also on, the call writes aiml's `note` event in the stream, so `jq` still parses each line.
> - **2A-iii:** `msg` is not evaluated when the channel is off (sys). The compiler has trace calls on hot paths.
> - **2A-iv:** I reject "may drop". When the channel is on, each call writes a line, and the lines keep program order within a thread. Their order against stdout is not defined.
> - **2A-v:** no query API (web).
>
> ## Q3: 3A, 101. No change.
>
> ## Writer notes
> - Say that `PanicInfo.line` is absent, not 0, when the runtime does not know it.
>
> NOT STABLE: 1A-i (scoped vs global vs main-only), 1A-iii, 1A-v, 2A-i (text vs NDJSON), 2A-iv (may drop).

**AI/ML, round 1**

> # aiml — Phase B round 1
>
> ## Q1: 1A, narrowed to web's form
>
> I keep 1A over 1B. Min's case is that "no row means no side effect" lets an agent trust a row.
> 1A keeps that: a rowless fn can still only diverge, and the report's writes appear in `main`'s
> row. 1B instead asks a model to design a parser-wide `Result` or a supervisor process to get
> one crash frame. Few models find that from the spec alone.
>
> For the variations, I pick the form with the fewest rules a model must learn:
>
> - **1A-i: I concede to web.** One `with on_panic(...)` in `main`'s body only. A second one, or
>   one outside `main`, is an error. There is one place to look and no nesting rule. It also
>   settles 1A-iii (the hook's ops go to `main`'s handlers) and 1A-v (`blink test` does not run
>   `main`, so the hook never meets the runner).
> - **1A-ii: nothing unwinds.** The hook changes the report only, and the rest is the same as any
>   panic: `close`/`exit()` are skipped (plt, sys). If web's "unwind first" rule applies, a hook
>   changes cleanup order, and that is a second fact to learn.
> - **1A-iv: `PanicInfo { message, file, line }`.** A model should not have to parse
>   `"... at f:3"` out of a `Str`.
> - **1A-vi:** a panic inside the hook gets the default report and the default exit code (101).
> - **Name:** `on_panic`, because it names what the user writes (`panic`). With `on_abort`, a
>   model must also learn that "abort" here means panic.
>
> ```blink
> fn main() ! IO, Env {
>     with on_panic(fn(p: PanicInfo) -> Never {
>         io.eprintln("error[ICE]: {p.message}")
>         io.print(ice_frames(p.message))
>         env.exit(101)
>     }) {
>         run()
>     }
> }
>
> fn helper() {
>     with on_panic(fn(p: PanicInfo) -> Never { panic("x") }) { }   // error: on_panic outside main
> }
> ```
>
> ## Q2: 2A, with the output form changed
>
> - **2A-i: I concede.** Use a text line, `[trace:<ch>] <msg>`, and drop my NDJSON `note` event.
>   It matches `DEBUG=ns` and `dbg!`, which models know, and §8.15.2 keeps its four events.
> - **2A-ii:** `BLINK_TRACE_CHANNELS`, read once by the runtime.
> - **Name:** `trace.note`, or `trace.log` if the panel prefers it. `io.log`/`IO.Log` already
>   exist, so a model can mix up `io.log` and `trace.log`.
> - **2A-iii: new rule.** `msg` must have an empty row, so an effectful call in `msg` is an
>   error. Then whether the message is built when the channel is off is not observable, and an
>   env var cannot change what the program does.
>   ```blink
>   trace.note("mono", "n={next_id()}")   // error: next_id has State; a trace message must be pure
>   ```
> - **2A-iv:** reject "may drop or move". When a channel is on, its lines appear in program order
>   among this thread's stderr writes. Their order relative to stdout is not specified.
> - **2A-v:** agree, no "is this channel on" API.
> - **2B:** it adds no surface, but tracing the fn `dbg_trace` and filtering it with `jq` is a
>   trick a model will not find. It also needs `--trace` on built binaries.
>
> ## Q3: 3A, 101
>
> No change from Phase A.
>
> ## Writer notes
>
> - Put the new tracer in the l.468 list as a fifth item, or state that it belongs to "trace
>   output". Either way, the list must still read as closed.
>
> NOT STABLE: 1A-i scope (main-only vs process-wide vs nested), 1A-ii unwind order, the purity rule for 2A-iii

**Minimalism, round 1**

> # min — Phase B round 1
>
> ## Q3: 101. I drop M2.
>
> Five seats want 101. sys's 3B keeps 1 only because it is the code today, and that is not a reason. A crash and `env.exit(1)` must differ.
>
> ## Q1: I hold 1B, and I name the smallest 1A I can accept
>
> Six variations in 1A are the cost I warned of. Each one is a rule that a user must learn, and each one touches a part of the spec that is settled. Also, 1A does not save the LSP case that started the ticket: plt, web and devops all say that a server that must keep running still needs a child process. So 1A buys only one thing: a one-shot CLI that writes its stdout frames on a crash. 1B gets the same frames from a parent process, with no new surface.
>
> If the panel picks 1A, I vote for this form and no other:
>
> - **1A-i: web's form.** A `with` item allowed only in the body of `main`. A second one, or one outside `main`, is an error. This kills 1A-v for free, because `main` does not run under `blink test`. Nesting and "innermost wins" go away too.
> - **1A-ii: nothing unwinds** (plt, sys). web's "each `close` runs, then the hook" breaks §2.20 l.2729, where an unexpected panic bypasses cleanup. That would reopen §4.7.2. I reject it.
> - **1A-iii:** the hook's ops go to `main`'s handlers, and its row is checked against `main`'s row. With main-only, plt and sys say the same thing here.
> - **1A-iv:** `PanicInfo { message, file, line }`. The hook hides the default `at file:line`, so a bare `Str` loses data.
> - **1A-vi:** a panic inside the hook writes the default report and exits 101, the same as 3A. There is no new code.
>
> ```blink
> fn main() ! IO, Env {
>     with panic_hook(fn(p: PanicInfo) -> Never ! IO.Print, IO.Eprint, Env.Exit {
>         io.eprintln("error[ICE]: {p.message}")
>         io.print(ice_frames(p.message))
>         env.exit(101)
>     }) {
>         run()
>     }
> }
> ```
>
> ## Q2: I hold 2B. If 2A wins, take aiml's form
>
> devops makes a fair point: `panic` already writes text to stderr with no row, so a rowless tracer adds no capability. I accept that. But the smallest 2A is aiml's 2A-i/2A-ii: a `note` event in the §8.15 stream, turned on by `--trace=note:<ch>`. It needs no fifth entry in the l.468 list, no new env var and no new text format. Each of the other four forms adds all three.
>
> - **2A-iii:** `msg` is always evaluated. A lazy argument is a second evaluation rule for one builtin. `debug_assert` is a precedent, but it is not a reason to add more of them.
> - **2A-iv:** reject plt's "may move or drop". If `msg` runs, its effects must run in order.
> - **2A-v:** no query API. I agree with web.
>
> ## Writer notes
>
> - Under 1B, devops's help line on E0500 (`use panic(...)`) needs no vote. It is diagnostic text, and I support it in both 1A and 1B.
>
> NOT STABLE: before a vote, 1A must collapse to one form for 1A-i to 1A-iii, so the ballot is that 1A against 1B. Q2 must also pick one 2A form to put against 2B.

Round 2.

**Systems, round 2**

> # sys — Phase B round 2
>
> ## S1: concede to main-only
>
> plt's point holds: under "innermost wins", a dependency's `with` decides how a crash looks
> inside its code. Main-only is also cheaper. It needs one static slot, set once, with no save and
> restore at each `with` and no per-install handler depth, because `main`'s handlers are the root
> handlers. The LSP case loses only a closure capture. The request loop writes `uri` and `id` to
> one global slot that the hook reads, as `diag_ice_state` does today. In a test, the runner frame
> takes the panic (plt). A test checks the hook fn by calling it under mocks.
>
> ## S2: concede to lazy, with an empty-row `msg` (plt, aiml)
>
> plt's example is right. With lazy evaluation, an effect in `msg` lets an env var change program
> behavior with no row. Eager (min) makes each of 38 hot sites build a string when every channel
> is off. The empty-row rule keeps the lazy lowering and makes it impossible to see:
>
> ```blink
> fn lower(n: Node) -> Ir {
>     trace.log("mono", "lower {n.kind} {n.args.len()}")   // ok: no row
>     trace.log("mono", "id={next_id()}")                  // error: msg has State; a trace message must have no row
>     lower_inner(n)
> }
> ```
>
> ## S3: move to a middle rule
>
> Once `msg` has no row, the only open question is DCE. With the channel on, each trace call that
> runs writes its line once, in program order among this thread's stderr writes. Order against
> stdout is not defined. A trace call does not make its fn have an effect: the spec does not say
> whether a call to a fn with no row runs when its result is not used. So the compiler may drop
> the fn call and its trace lines together, but it may not reorder or merge lines. Today the C
> backend keeps every call, so this costs nothing. The rule keeps DCE of pure code legal later.
>
> ## S4: hold
>
> When `BLINK_TRACE_CHANNELS` and `--trace` are both on, a text line in the NDJSON stream breaks
> each consumer that parses the stream line by line. Text-only (aiml, web) leaves that case
> undefined. So: a text line by default, and a `note` event when `--trace` is on.
>
> NOT STABLE: S4 (what a trace call writes when `--trace` is on) and S3 (my DCE rule against
> plain "never drop").

**Web/Scripting, round 2**

> # web — Phase B round 2
>
> ## S1: hold a scoped `with`, innermost wins, nearest boundary wins in tests
>
> plt's takeover risk is real, the same way Node libraries that register `uncaughtException` take the app's crash report. In Blink the rows already show it. The hook's row is charged at its `with`, so a library fn that installs a hook which writes and exits must declare `! IO.Print, Env.Exit`. The app sees that in the signature it calls. Main-only moves the LSP's uri and request id back into a global, and the LSP is the motivating case (sys, devops). Tests: the nearest boundary wins, so a user can check a hook in-process (r1_web.md, r1_devops.md). If the panel picks main-only, I accept it as the second choice. That makes this a ballot choice, not a reason to block.
>
> ## S2: concede, lazy and pure
>
> plt's example convinced me. An env var must not change program behavior. When `msg` has an effect, the error message tells the dev what to do:
>
> ```blink
> fn f() ! IO.Print {
>     trace.log("x", "n={noisy()}")
> }
> ```
> ```
> error: a trace message must have no effects; `noisy` has IO.Print
>   help: compute the value into a `let` before the call
> ```
>
> One refinement for the panel: a *read* of a module `let mut` should be allowed, because skipping a read cannot be seen. Compiler trace sites interpolate global state. A write is an error.
>
> ## S3: hold no-drop
>
> With S2, a trace call has no effect the program can see, so sys's soundness worry is gone. The order rule only covers diagnostic text on stderr, as for the panic message. A dev who turns a channel on and gets no line, or gets lines out of order, stops using it. With the channel on, each call that runs writes one line, in program order with this thread's stderr writes. Order against stdout is not specified.
>
> ## S4: concede to sys/devops
>
> The default is a text line `[trace:<ch>] <msg>`. When `--trace` is also on, the same call writes a `note` event in the NDJSON stream instead, so `jq` still parses each line. Two formats on one stream is the bug sys names.
>
> STABLE: ready to vote (S1 scoped vs main-only is a ballot choice; the S2 State-read refinement needs one line from plt/aiml)

**PLT, round 2**

> # plt — Phase B round 2
>
> ## S1: I concede to any `with`, innermost wins
>
> My library-hijack point fails. A fn that installs a hook must hold the hook's row (`! IO.Print, Env.Exit`), so its signature shows the takeover. This is the same as a library that installs a handler for an effect. A hook with dynamic extent that captures `uri`/`id` composes better than a `main`-only hook that reads a global. Tests: the nearest boundary wins (hook, `assert_panics`, runner frame). This was my Phase A rule, and web's test shows that it works.
>
> ## S2: hold lazy + empty row; eager is my second choice
>
> "Lazy, any `msg`" contradicts 2A-v, which all six accept. If an effect in `msg` runs only when the channel is on, a program can test the channel:
>
> ```blink
> fn probe() -> Str ! IO.Print {
>     io.println("tracing on")
>     "x"
> }
>
> fn main() ! IO {
>     trace.log("mono", probe())
> }
> ```
> With `BLINK_TRACE_CHANNELS=mono`, stdout is `tracing on`. With it unset, stdout is empty. That is an `Env.Read` with no row. A charged row is an upper bound, so it does not fix this. Only two rules are sound. Either `msg` has the empty row (an error otherwise), and then laziness cannot be seen. Or `msg` is always evaluated (min).
>
> ## S3: concede in-order, with one limit
>
> I accept: with the channel on, each trace call that runs writes its line once, in program order with this thread's stderr writes. The limit (sys's words, which match Haskell's `Debug.Trace`): a trace call does not keep code alive. If the compiler removes or merges a pure computation, for example an unused result, its trace call does not run, so its line is missing. Without this limit, every pure fn that holds a trace call counts as effectful for the optimizer, and its empty row stops being true.
>
> ## S4: sys/devops form
>
> A text line, or a `note` event when `--trace` NDJSON is on, so stderr stays one format. I have no other stake.
>
> STABLE: ready to vote (S2 needs a ballot line: lazy + empty row vs eager; "lazy, any `msg`" is unsound by the example above).

**DevOps/Tooling, round 2**

> # devops: Phase B round 2
>
> ## S1: I concede to main-only
>
> My testability argument does not hold. The hook is a plain fn, so a test calls it directly and needs no in-process hook:
>
> ```blink
> test "ICE hook writes the error frame" {
>     let out: List[Str] = []
>     let me = mock_env()
>     assert_panics(matching: "env.exit(101)") {
>         with capture_print(out), me.as_handler() {
>             report(PanicInfo { message: "ice", file: "ast.bl", line: 3 })
>         }
>     }
>     assert(out[0].contains("-32603"))
> }
> ```
> The test passes. Under the runner, `main` does not run, so no hook meets the runner frame.
>
> plt's risk outweighs my per-request capture. If a dependency's hook replaces the app's crash report, the user sees the wrong diagnostic and cannot find out why. The cost to the LSP: its one hook reads the current uri and id from module state, which is what the compiler does today.
>
> ## S2: I concede to lazy with an empty-row `msg` (plt/aiml)
>
> plt shows that lazy evaluation plus effects lets an env var change behavior with no row. The error is easy to read:
>
> ```blink
> trace.log("mono", "n={next_id()}")
> ```
> ```
> error[E05xx]: a trace message must not perform effects
>   --> lower.bl:4:23
>    |  next_id() has ! State
> help: compute the value first: `let n = next_id()`, then `trace.log("mono", "n={n}")`
> ```
>
> ## S3: I hold "no drop", narrowed to meet sys/plt
>
> - When the channel is on, a trace call that runs writes its line exactly once.
> - The lines of one thread are in program order.
> - Their order against any `IO` op, `io.eprintln` included, is not specified (plt's point).
> - A trace call does not keep code alive. If the optimizer removes the code around it, the line goes too (sys's point).
>
> These rules are enough for soundness. A dev who adds a trace to code that runs still sees its line.
>
> ## S4: I hold: a text line, plus a `note` event when `--trace` is on
>
> Two formats mixed on one stderr stream break `jq`. That is a tooling failure, so I keep sys's merge.
>
> STABLE: ready to vote

**AI/ML, round 2**

> # aiml — Phase B round 2
>
> ## S1: hold main-only
>
> A model that writes a library will copy any crash-report pattern it has seen. If `on_panic`
> is legal anywhere, some generated libraries will install one, and the app loses its report
> (plt's point). A model learns "only in `main`" from one sentence and one error.
>
> The LSP case still works. The hook in `main` reads the request state that the loop keeps, and
> its row (`State` too) goes on `main`. A test of the hook tests a named fn, not an in-process
> crash:
>
> ```blink
> fn report(p: PanicInfo) -> Never ! IO.Print, Env.Exit {
>     io.print(lsp_abort_frames(cur_uri, cur_id, p.message))
>     env.exit(101)
> }
>
> fn main() ! IO, Env, State {
>     with on_panic(report) {
>         serve()
>     }
> }
>
> test "report writes the -32603 frame" {
>     let out: List[Str] = []
>     assert_panics(matching: "env.exit(101)") {
>         with capture_print(out), mock_env().as_handler() {
>             report(PanicInfo { message: "ice", file: "a.bl", line: 3 })
>         }
>     }
>     assert(out[0].contains("-32603"))
> }
> ```
>
> The test passes. It needs no nesting rule and no boundary-order rule.
>
> ## S2: hold lazy + empty row on `msg`
>
> This is the only form where both of these hold: the env var cannot change program behavior
> (plt), and a channel that is off costs no allocation (sys). The common case,
> `"lower {n.kind}"`, is already pure, so a model writes nothing new. The rare case gets a clear
> error:
>
> ```blink
> trace.note("x", noisy())   // error: a trace message must have an empty row; noisy has IO.Print
> ```
>
> ## S3: hold no-drop, plus one merge
>
> With the channel on, each call that runs writes its line, in program order among this
> thread's stderr writes. Merge for sys: when the compiler removes a pure computation whose
> result is unused, any trace calls inside it go too. That call never ran, so this matches what
> a model expects from `-O2`. A call that runs is not moved or merged.
>
> ## S4: concede to sys/devops
>
> Write a text line `[trace:<ch>] <msg>`. When `--trace` is also on, the same call writes a
> `note` event in the NDJSON stream instead. Mixed formats on one stream break `jq`, and a model
> asked to parse `--trace` output assumes every line is JSON.
>
> NOT STABLE: S1 (main-only vs scoped `with`) is 3-3, a tie for the owner unless a seat moves. The S3 merge needs plt/sys to accept it.

**Minimalism, round 2**

> # min — Phase B round 2
>
> ## S1: hold main-only
>
> Main-only is one rule: one hook, one place to look. Nesting needs three more: innermost wins, how a hook meets `assert_panics`, and how it meets the runner frame. It also lets a library take the app's crash report (plt). The per-request case does not need nesting. The LSP loop writes `uri` and `id` to a `let mut` before each check, and the hook in `main` reads them. `main` already pays `State` for that. Under the test runner the hook does not run, even when a test calls `main()` (plt). That gives no new test rule.
>
> ## S2: hold eager, accept lazy + empty row second, reject lazy with any `msg`
>
> plt shows that lazy with any `msg` is unsound: an env var with no row changes what the program writes to stdout. That rules it out. Eager adds no rule. Lazy + empty row adds a compile error, and the compiler's own sites hit it: a `msg` that reads a module `let mut` has `State`.
>
> ```blink
> let mut depth = 0
>
> fn walk() {
>     trace.log("walk", "depth={depth}")   // lazy+pure: error, msg has State; eager: compiles
> }
> ```
>
> The cost of eager is one string built at each site, which is what `dbg_trace` costs today.
>
> ## S3: hold "no drop"
>
> With the channel on, each call that runs writes one line, in program order among this thread's stderr writes. A trace that may vanish is a tool that no one can trust. With eager `msg`, "may drop" would also have to keep the effects of `msg`, which is a second rule.
>
> ## S4: concede to text line only. Reject the dual form.
>
> I drop the NDJSON-only form, because aiml, its proposer, dropped it. sys's `jq` argument for the dual form does not hold: under `--trace`, a program's own `io.eprintln` lines already mix into stderr, so stderr is never pure NDJSON. A second output form buys nothing and adds a rule.
>
> ```
> $ BLINK_TRACE_CHANNELS=walk ./app
> [trace:walk] depth=0
> ```
>
> STABLE: ready to vote

#### Phase C — Votes

Each seat voted alone on the ballot.

**Systems**

> # sys — Phase C vote
>
> ## Q1
> **Vote:** 1A
> **Reasoning:** A hook costs nothing until a panic: one static slot read on the panic path, and
> no change to the codegen of any panic site. 1B puts a branch on each parser return, or a process
> spawn on each check, to serve a path that runs once per crash. Rows stay proven at one site.
> **Concern:** The hook runs in state the panic just called broken, and a hook that walks large
> program data can crash again and lose the report.
>
> ## Q1b
> **Vote:** 1b-M
> **Reasoning:** One slot, set once, with no save and restore per `with` and no per-install handler
> depth, because `main`'s handlers are the root handlers. No dependency can take over the crash
> report. The LSP's per-request state goes in one global, as it does today.
> **Concern:** A long-lived server with many concurrent requests must keep the "current request"
> global right per thread, or a frame names the wrong request.
>
> ## Q2
> **Vote:** 2A
> **Reasoning:** A disabled channel costs one load and one branch. 2B needs a build that writes an
> enter/exit event for each fn, which costs far more, and its no-op call builds `msg` each time.
> **Concern:** People will use it as a free logger in hot loops with channels on, then blame the
> language for the stderr cost.
>
> ## Q2b
> **Vote:** 2b-R
> **Reasoning:** Skipping a read does nothing that any code can see, so laziness stays sound. Depth
> and counter globals are the most common thing a compiler trace prints, and 2b-P forbids them.
> Both forms lower to the same `if trace_on(ch) { ... }` branch.
> **Concern:** The checker must tell a State read from a State write inside `msg`. If it charges
> them as one State row today, this needs new checker work.
>
> ## Q2c
> **Vote:** 2c-D
> **Reasoning:** If a trace call keeps its code alive, every fn that traces is pinned against
> dead-code elimination of pure code, so an optimization depends on debug output. Today the C
> backend keeps every call, so 2c-D costs nothing now and keeps that freedom later.
> **Concern:** A user who traces a pure fn whose result is not used sees no line and files a bug.
> The spec must say this outright.
>
> ## Q2d
> **Vote:** 2d-O
> **Reasoning:** Both writes go to one fd from one thread. Program order is the free result of
> writing in sequence, so this costs no fence and no buffer.
> **Concern:** If the runtime buffers trace lines apart from `io.eprint`, it must flush in order,
> or 2d-O breaks under load.
>
> ## Q2e
> **Vote:** 2e-N
> **Reasoning:** With `--trace` on, stderr is a stream that is parsed one line at a time. One text
> line breaks each consumer. The runtime already owns that writer, so a `note` event costs one more
> event kind.
> **Concern:** §8.15.2 calls its four events complete, and the writer must change that claim with
> care.
>
> ## Q3
> **Vote:** 3A
> **Reasoning:** A crash code that differs from `env.exit(1)` costs nothing at run time and lets a
> script tell a crash from "no".
> **Concern:** Scripts that check for exit 1 on a panic today break silently.

**Web/Scripting**

> # web: Phase C vote
>
> ## Q1
> **Vote:** 1A
> **Reasoning:** A JS or Python dev expects a crash hook (`sys.excepthook`, `uncaughtException`). They do not expect to write a supervisor process before they can print one error frame. 1A keeps deep code simple, with one rule: an invariant break is `panic`. The report's row shows up at one site.
> **Concern:** Devs will read "hook" as "catch" and try to resume. Only the `-> Never` body-completeness error stops them, so its help text must say "a hook cannot return; end it with `env.exit`".
>
> ## Q1b
> **Vote:** 1b-S
> **Reasoning:** The motivating case is an LSP request loop, and a closure that captures `uri`/`id` is how every web dev writes this. Main-only pushes that state into a global. The takeover risk shows up in rows, because a library that installs a hook declares `! IO.Print, Env.Exit`. A test can check a hook in-process.
> **Concern:** "Innermost wins" across library boundaries may produce reports nobody expected, unless the docs show where a library installs one.
>
> ## Q2
> **Vote:** 2A
> **Reasoning:** Printf-debugging is the 90% case. 2B needs a full trace build, `jq`, and the knowledge that "trace an empty fn" is the trick, so it fails the 5-minute test. `DEBUG=ns`-style channels are familiar.
> **Concern:** People will use it as a free logger in library code. Its fixed prefix and env gate limit the damage but do not stop it.
>
> ## Q2b
> **Vote:** 2b-R
> **Reasoning:** Trace messages almost always interpolate the state being debugged, such as a depth counter or a module `let mut`. Under 2b-P, the obvious first use gets an error. A skipped read cannot be seen, so 2b-R is as sound as 2b-P. Never building the string when the channel is off answers the "why does my f-string run" question.
> **Concern:** The State-read vs State-write split must be explained in the error message, or it will read as an arbitrary rule.
>
> ## Q2c
> **Vote:** 2c-K
> **Reasoning:** A dev turns a channel on and the line is missing, because an optimizer removed a pure call. That is the debugging experience that makes people give up on a tool. A trace in code that runs must print. The perf cost only applies to code that has a trace call in it.
> **Concern:** If 2c-D wins, "my trace does not print in a release build" becomes a recurring question, and the docs must state the rule plainly.
>
> ## Q2d
> **Vote:** 2d-O
> **Reasoning:** Trace lines mixed with the program's own `io.eprintln` must appear in the order that the code ran, or the trace misleads. Every language's stderr gives this inside one thread.
> **Concern:** Buffering differences between the runtime trace writer and `io.eprint` could break this in the implementation, so a test must pin it.
>
> ## Q2e
> **Vote:** 2e-N
> **Reasoning:** Under `--trace`, stderr is a JSON stream and users pipe it to `jq`. One text line breaks the whole pipe. The text line stays the default for humans.
> **Concern:** Users may not find their trace lines under `--trace` until the docs say they appear as `note` events.
>
> ## Q3
> **Vote:** 3A
> **Reasoning:** A crash and "the tool said no" must have different exit codes for CI scripts. 101 has Rust as precedent.
> **Concern:** Scripts that check for exit 1 after a panic today change behavior, so the release notes must call it out.

**PLT**

> # plt — Phase C vote
>
> ## Q1
> **Vote:** 1A
> **Reasoning:** With 1A, an invariant break has one route that needs no row: `panic`, which is divergence (bottom). The writes in the report are charged to the scope that installs the hook, so every row stays an honest upper bound. No new write without a row enters l.468. Since the hook is `-> Never` and nothing unwinds, the §4.7.2 catch-boundary fence holds.
> **Concern:** the hook runs at the panic point, in a state the panic says is broken, and the spec must say that the hook cannot trust program data.
>
> ## Q1b
> **Vote:** 1b-S
> **Reasoning:** A hook with dynamic extent that captures its state in a closure composes like a handler. A `main`-only hook pushes per-request state into a module global, and that is a weaker design. The installer's signature shows the hook's row, so a library cannot take over the crash report without anyone seeing it. When the nearest boundary wins, a test can check a hook in-process.
> **Concern:** the rule for where an op inside the hook goes ("handlers in scope at the `with`") must be stated exactly, or an implementation will dispatch to the handlers at the panic site.
>
> ## Q2
> **Vote:** 2A
> **Reasoning:** 2A is sound once three rules hold: output that is not program behavior, no query API, and a pure `msg` (or one that only reads). Haskell's `Debug.Trace` works the same way. 2B is also sound, but it puts a full fn-level trace on every program just to get one channel.
> **Concern:** users will treat it as a logger, then ask for a level or a query API, and either would break the reasons it is sound.
>
> ## Q2b
> **Vote:** 2b-R (2b-P is an acceptable second)
> **Reasoning:** Skipping a read cannot be seen, so a lazy `msg` that only reads state is as sound as a pure one. It also allows the most common trace, `depth={depth}`. A write, or any other op, would let the env var change what the program does, so both are errors.
> **Concern:** a `msg` that panics (an index out of range) still makes the program panic only when the channel is on, and the spec should state this as a known limit, as with `debug_assert`.
>
> ## Q2c
> **Vote:** 2c-D
> **Reasoning:** A fn with no row must stay pure for the optimizer, or its empty row is false. Under 2c-K, a trace call is a hidden effect that stops dead-code removal. That is the soundness gap this design must not open.
> **Concern:** a developer sees a line go missing at `-O2` and files a bug, so the spec should give an example of the missing line.
>
> ## Q2d
> **Vote:** 2d-O
> **Reasoning:** For the trace's own stream, order among one thread's stderr writes is a runtime guarantee and adds no row. Together with 2c-D, it says that the lines which do appear come in source order.
> **Concern:** the optimizer must treat a trace call as ordered against `IO.Eprint` ops but not as an effect, and that rule is easy to get wrong.
>
> ## Q2e
> **Vote:** 2e-N
> **Reasoning:** When `--trace` is on, stderr is a typed stream, and a text line in it breaks every consumer. With 2e-N, the l.468 entry stays literally "trace output (§8.15)".
> **Concern:** §8.15.2 calls its event set complete, and the writer must change that claim.
>
> ## Q3
> **Vote:** 3A
> **Reasoning:** A crash and `env.exit(1)` are different outcomes, and a fixed exit code makes the difference visible to a caller. 101 has precedent in Rust.
> **Concern:** a script in use today that checks for exit 1 on a panic will break, and the release notes must say so.

**DevOps/Tooling**

> # devops: Phase C vote
>
> ## Q1
> **Vote:** 1A
> **Reasoning:** With a hook, the LSP and the CLI write their `-32603` frame, the `ice` status line and the JSON row before they end. That is what the editor and the CI scripts read, and what the tests pin today. 1B makes every tool add a supervisor process before it can report a crash.
> **Concern:** A hook runs in a state the panic says is broken, so a hook that walks program data can panic again and lose the report it was meant to write.
>
> ## Q1b
> **Vote:** 1b-M
> **Reasoning:** A crash report must come from the app, never from a dependency that a user's callback happened to run under. One hook, in `main`, gives one place to look. A test calls the hook fn directly, so testing the hook costs nothing.
> **Concern:** The LSP's per-request uri and id go back into module state, and a stale value there writes a frame for the wrong request.
>
> ## Q2
> **Vote:** 2A
> **Reasoning:** 2B turns on full enter/exit tracing and needs `jq` to read one channel, and `--trace` is not on `blink build`. 2A is a single line that a dev adds and then reads.
> **Concern:** Users will treat `trace.log` as a logger, and when output they need is gone in production they will file bugs.
>
> ## Q2b
> **Vote:** 2b-R
> **Reasoning:** Most of the compiler's traces print counters and depths kept in module state. Under 2b-P each of those traces needs a `let` first and loses its one-line form. A read that is skipped changes nothing anyone can see, so 2b-R is as sound as 2b-P.
> **Concern:** The writer must define a "read" precisely. A read that goes through a handler op runs user code, so 2b-R must allow only a direct read of a module `let`.
>
> ## Q2c
> **Vote:** 2c-D
> **Reasoning:** If a trace call keeps its code alive, a trace changes what the optimizer can do, and a traced build then times differently from an untraced one. A line that is missing because its code was never run is not a surprise for a dev.
> **Concern:** At -O2 a dev adds a trace to a pure helper, sees nothing because the call was removed, and decides the tool is broken.
>
> ## Q2d
> **Vote:** 2d-O. I change my vote from 2d-U.
> **Reasoning:** A dev who debugs reads trace lines and `io.eprintln` lines as one timeline on one terminal. An unspecified order makes that timeline lie. When a handler captures the `io.eprintln` text, the order does not apply to it.
> **Concern:** Buffered `io.eprint` text can show up after a later trace line, unless the runtime flushes stderr in a fixed order.
>
> ## Q2e
> **Vote:** 2e-N
> **Reasoning:** With `--trace` on, each stderr line must parse as JSON, or `jq` and the trace viewers break.
> **Concern:** A dev runs `--trace` to see their text lines and finds JSON instead, so the docs must say this in one place.
>
> ## Q3
> **Vote:** 3A (101)
> **Reasoning:** CI and editors need to tell a crash from a reported failure (1) and from a usage error (2). Rust uses 101 for this.
> **Concern:** Scripts written for today's exit 1 on a panic must change.

**AI/ML**

> # aiml — Phase C vote
>
> ## Q1
> **Vote:** 1A
> **Reasoning:** Under 1A, deep code needs one rule: an invariant break is `panic`. One hook at
> the root picks the report. 1B makes a model design a parser-wide `Result` or a supervisor
> process to get one crash frame, and a model will not find that from the spec alone. Models
> already know the pattern from Rust `set_hook` and Python `sys.excepthook`.
> **Concern:** a model may write the hook as a catch that returns, so the error for a `-> Never`
> body that falls through must be clear and must name the hook.
>
> ## Q1b
> **Vote:** 1b-M
> **Reasoning:** "Only in `main`" is one sentence and one error, and it needs no nesting rule and
> no rule for which boundary in a test comes first. Generated libraries copy patterns. With 1b-S,
> some will install a hook and take the app's crash report. A test of the hook calls the named fn
> directly, which is easier for a model to write than an in-process crash.
> **Concern:** if 1b-S wins, models will put `on_panic` in library code, because a `with` item
> looks local and safe.
>
> ## Q2
> **Vote:** 2A
> **Reasoning:** `trace.log(ch, msg)` is one call that a model learns from one example, and it
> matches `DEBUG=ns` and `dbg!`. 2B, an empty fn plus `--trace=fn:` plus `jq`, is a trick no model
> derives from the spec.
> **Concern:** models will use `trace.log` as free production logging. The env gate and the fixed
> text form must stay strict, or it will replace `io.eprintln`.
>
> ## Q2b
> **Vote:** 2b-R (I move from 2b-P)
> **Reasoning:** When the channel is off, a skipped read cannot be observed, so 2b-R is as sound
> as 2b-P. Traces such as `"depth={depth}"` are the most common shape a model will write, and
> 2b-P rejects them with an error that seems arbitrary. "A trace message may read but not change
> anything" is easy to state.
> **Concern:** the writer must define "read only" exactly, or a getter with a hidden write will
> slip through.
>
> ## Q2c
> **Vote:** 2c-D
> **Reasoning:** A model expects `-O2` to drop dead pure code, and a call that never ran writes
> nothing. If a trace keeps code alive, it changes codegen, and a user cannot see that from the
> source.
> **Concern:** a dev who traces inside a pure fn whose result is unused will see no line and think
> the trace is broken. The spec needs one example for this case.
>
> ## Q2d
> **Vote:** 2d-O
> **Reasoning:** A model that reads interleaved `io.eprintln` and trace lines assumes they are in
> source order, and so does a human. Order that is not specified makes debug output wrong in a way
> that users cannot predict.
> **Concern:** none of note. Buffered stderr must flush in one order for both paths.
>
> ## Q2e
> **Vote:** 2e-N
> **Reasoning:** A model asked to parse `--trace` output assumes every line is JSON. A text line
> mixed into that stream breaks `jq` and the parsers that models generate.
> **Concern:** two output forms for one call. The spec must show both, side by side.
>
> ## Q3
> **Vote:** 3A
> **Reasoning:** One fixed, documented code (101, as in Rust) separates a crash from `env.exit(1)`,
> and a model learns it at no cost.
> **Concern:** scripts that check for exit 1 on a panic today will break, so it goes in the
> breaking-changes list.

**Minimalism**

> # min — Phase C vote
>
> ## Q1: 1B
> **Reasoning:** 1A adds a new construct, a new type (`PanicInfo`) and rules on where it may go, how it meets tests, and what a panic inside it does. In exchange it does not save the motivating LSP case, since every seat agrees a server that must keep running needs a child process anyway. The rest is a one-shot CLI that writes a status line on a crash, and a parent process or a `Result` to `main` does that with no new surface.
> **Concern:** 1A will win, and the hook will turn into the default "error handling" users reach for, so `panic` will be used for user-facing errors that should be values.
>
> ## Q1b: 1b-M
> **Reasoning:** One hook in one place is one rule. Nesting adds innermost-wins, test-boundary interplay, and lets a library take over the app's crash report. Per-request state in a module `let mut` costs `main` a `State` row it already pays.
> **Concern:** under 1b-S, a dependency installs a hook, and the app's crash output changes with the order of `with` nesting that no one reads.
>
> ## Q2: 2B
> **Reasoning:** §8.15 already traces calls with their arguments, and that needs no fifth exemption on l.468. 2A adds a builtin, an env var and an output format, and the ballot shows four sub-questions it opens (Q2b–Q2e). That count is the cost.
> **Concern:** 2A will win, and `trace.log` will be used as rowless logging in published libraries, so "no row means no output" stops being something an agent can trust.
>
> ## Q2b: 2b-E
> **Reasoning:** Eager adds no evaluation rule and no new compile error. The cost is one string per site, the same as `dbg_trace` today. 2b-R adds a third row class ("State read only") that exists nowhere else in the spec.
> **Concern:** under 2b-P or 2b-R, users will hit an error at the many sites where `msg` reads a module `let mut` or calls a helper that has a row, and will route around it with globals.
>
> ## Q2c: 2c-K
> **Reasoning:** A trace that can vanish when the channel is on is a debugging tool that lies. "The compiler may drop it" also makes the output depend on the optimizer level, which is a new rule users cannot see.
> **Concern:** under 2c-D, a dev adds a trace to a pure helper, sees nothing at `-O2`, and files a bug that the spec calls correct behavior.
>
> ## Q2d: 2d-O
> **Reasoning:** A trace line between two `io.eprintln` lines must appear between them, or it cannot tell you where the program was. It is one stream with one order.
> **Concern:** none of weight. 2d-O is near unanimous.
>
> ## Q2e: 2e-T
> **Reasoning:** One output form is one rule. Under `--trace`, the program's own `io.eprintln` lines already mix into stderr, so stderr is never pure NDJSON, and 2e-N's `jq` argument does not hold. 2e-N also changes the §8.15.2 claim that four event kinds are complete.
> **Concern:** under 2e-N, a call writes two different formats depending on a flag, and tools that parse one will break on the other.
>
> ## Q3: 3A
> **Reasoning:** A crash must not share an exit code with `env.exit(1)`. Pinning one number is a fact, not surface, and 101 has precedent (Rust).
> **Concern:** scripts that check for exit 1 on a Blink panic today will change behavior, so the release notes must call it out.

#### Phase D — Focused round on Q1b and Q2c

Two questions were 4-2 in Phase C and got one more round.

**Systems**

> ## Q1b
> web and plt: "a library that installs a hook declares `! IO.Print, Env.Exit`, so a takeover
> shows in rows." It shows that the library can print and exit, which is common for any CLI
> helper. It does not show that the library replaces the app's crash report. You learn that only
> by reading the body. Under 1b-M, a reader finds every hook in one place. The closure point is
> real, but a request loop in Blink today runs one request at a time, so one module slot that the
> loop sets before each request costs one store. A server that runs requests on many threads
> needs a slot per thread, which the runtime can give with no new surface. I hold.
> **Final vote:** 1b-M
> **Concern:** If Blink adds a thread-per-request server pattern later, the spec needs a
> per-thread rule for the slot that the hook reads.
>
> ## Q2c
> web and min: "a trace that can vanish is a tool that lies." Under 2c-D, a missing line means
> the compiled program does not make that call. That is true of the binary you debug. Under 2c-K,
> the trace changes the binary: adding the line keeps code alive that the untraced build drops,
> so the tool shows a program you did not ship.
>
> ```blink
> fn cost(n: Int) -> Int {
>     trace.log("c", "n={n}")
>     n * 2
> }
>
> fn main() ! IO {
>     let _ = cost(3)
>     io.println("done")
> }
> ```
>
> `BLINK_TRACE_CHANNELS=c`: stdout `done`. Under 2c-D, stderr has `[trace:c] n=3` only if the
> compiler keeps the call (today's C backend always does). Under 2c-K, it always does, and the
> call is never removable. I hold.
> **Final vote:** 2c-D
> **Concern:** When a later optimizer removes pure calls, users will report missing lines as bugs
> unless the spec and `blink llms` say plainly that a trace line does not keep its call alive.

**Web/Scripting**

> ## Q1b
> The strongest point on the other side is that 1b-M can grow into 1b-S later, but 1b-S cannot shrink back. Widening "only in `main`" to "any `with`" breaks no program. Narrowing would break every library that installed a hook. For the 90% case, a CLI with one crash report, one hook in `main` is the familiar shape: Python's `sys.excepthook` and Node's `uncaughtException` are global too. Testing by calling the hook fn directly is easier than an in-process crash. My per-request-state argument still holds for the LSP. But a single-threaded request loop that sets a module `let mut` per request is a normal pattern, and it is not a trap. I change my vote.
>
> **Final vote:** 1b-M
> **Concern:** A threaded server that keeps the "current request" in module state will write a frame for the wrong request, so the docs example must show it per thread or call it out.
>
> ## Q2c
> devops's point holds: if the program does not use a pure call's result, the call does nothing the program can see, so a missing line there is not a lie about code that mattered. A dev who traces code whose result feeds the output always gets the line:
>
> ```blink
> fn lower(id: Int) -> Int {
>     trace.log("mono", "lower {id}")
>     id + 1
> }
>
> fn main() ! IO {
>     io.println("{lower(3)}")   // stderr [trace:mono] lower 3; stdout 4
>     lower(5)                   // result unused: the line may be missing
> }
> ```
>
> The second call is dead code. An unused-result lint already points at it. Also, 2c-K makes the empty row false for every fn that traces, and the language should not pay that. Haskell's `Debug.Trace` has the same rule, and its users live with it. I change my vote.
>
> **Final vote:** 2c-D
> **Concern:** Devs will hit the missing line in `let _ = f(x)` probes, so the docs must state the rule and show this example.

**PLT**

> ## Q1b
> The strongest point for 1b-M is devops's: a dependency's hook takes an app panic raised in a callback that runs under it. That is true, and the same is true for every handler in Blink, because a library's `with` handles the effects of the callbacks it runs. 1b-S keeps that rule, and the library's row shows it. 1b-M fails on sys's own concern. A server that handles requests on several threads keeps one module-global "current request" for every thread:
>
> ```blink
> fn serve(uri: Str, id: Int) ! IO.Print, Env.Exit {
>     with on_panic(fn(p: PanicInfo) -> Never ! IO.Print, Env.Exit {
>         io.print(lsp_abort_frames(uri, id, p.message))
>         env.exit(101)
>     }) {
>         io.print(check(uri))
>     }
> }
> ```
> Under 1b-S, a panic in request 7 writes a frame with `id` 7. Under 1b-M, the frame gets whichever `id` the last thread stored. 1b-S is correct by construction, and 1b-M is correct only by discipline. I hold.
> **Final vote:** 1b-S
> **Concern:** if 1b-M wins, the spec must say how a hook installed in `main` reads per-thread state, or every server writes the race above.
>
> ## Q2c
> min's point is that output then depends on the optimizer level. Under 2c-K, it is the meaning of the program that depends on a hidden bit. To keep a call alive, the compiler must know, for each fn and transitively, whether it traces. That bit is an effect row in all but name, with no syntax and no check, and it makes "empty row means pure" false. Under 2c-D, a line goes missing only for a call whose result nothing uses:
>
> ```blink
> fn cost(n: Int) -> Int {
>     trace.log("c", "cost {n}")
>     n * 2
> }
> fn main() ! IO {
>     let _ = cost(3)
>     io.println("done")
> }
> ```
> At `-O2`, stdout is `done` and the trace line may not appear. That is Haskell's `Debug.Trace` rule. I hold.
> **Final vote:** 2c-D
> **Concern:** the spec must show this example, or developers will file the missing line as a bug.

**DevOps/Tooling**

> ## Q1b
> web and plt say that rows show a takeover. They do not show it in a way a user can read. A CLI framework or an HTTP server library already declares `! IO, Env`, so a hook it installs adds nothing new to its signature:
>
> ```blink
> fn serve_cli(app: App) ! IO, Env {
>     with on_panic(lib_report) {   // under 1b-S: compiles, and no row changes
>         app.run()
>     }
> }
> ```
>
> A panic in the user's own `app.run` code then writes the library's report. The user's `main` hook never runs, and nothing in the source says why. The diagnostic is wrong and cannot be traced. Under 1b-M this is a compile error at `with on_panic`, and the message names the fix. The cost of 1b-M is one module-state slot for the current request. That is a known pattern and it fails loudly in a test.
> **Final vote:** 1b-M
> **Concern:** A threaded server must keep the current-request slot per thread, or a frame names the wrong request.
>
> ## Q2c
> web's strongest point: a dev turns a channel on and the line is missing. Under 2c-D a line goes missing only when the call it is in has no effect at all:
>
> ```blink
> fn weigh(n: Int) -> Int {
>     trace.log("w", "weigh {n}")
>     n * 2
> }
>
> fn main() ! IO {
>     weigh(3)            // result unused; -O2 may drop it with its line
>     io.println("{weigh(4)}")
> }
> ```
>
> `BLINK_TRACE_CHANNELS=w` at -O2 prints `[trace:w] weigh 4` and maybe `weigh 3`. With `--debug` (-O0) it prints both. The dev who chases a bug in output that they can see always gets the line. A dev who debugs at `-O0` gets every line.
> **Final vote:** 2c-D
> **Concern:** The docs must say in one sentence that a missing line at -O2 means the call had no effect, or users will file bugs about it.

**AI/ML**

> ## Q1b
> web and plt say the row shows a takeover. It does not. `! IO.Print, Env.Exit` on a library fn
> reads as "this helper prints and can exit", like any CLI helper. Nothing in the signature says
> "this replaces the app's crash report". A reviewer or a model that reads the row sees nothing
> strange:
>
> ```blink
> pub fn with_retry(f: fn() -> Int) -> Int ! IO.Print, Env.Exit {
>     with on_panic(log_and_quit) {   // under 1b-S: takes over every panic in f
>         f()
>     }
> }
> ```
>
> Under 1b-M, this is a compile error. Under 1b-S, it compiles, and the app's hook stops running
> inside `f`. Closure capture is a better design for a single LSP request, but that is one program.
> The hijack risk applies to every generated library.
> **Final vote:** 1b-M
> **Concern:** the per-request state in a module global can go stale, and the hook then writes a
> frame for the wrong request.
>
> ## Q2c
> I change my vote. min's point holds from my domain. In the training data, a debug print keeps
> its code alive: C `fprintf`, Rust `dbg!`, Python `print`, and Go `log`. The one common exception
> is Haskell `Debug.Trace`, where lines vanish because of laziness and the optimizer, and models and
> users find it hard to reason about. Under 2c-K the rule is "a call that the source reaches
> prints", and a model can check that by reading the source. Under 2c-D, a model must also know
> what the optimizer removes:
>
> ```blink
> fn cost(n: Int) -> Int {
>     trace.log("c", "cost {n}")
>     n * 2
> }
>
> fn main() ! IO {
>     let _ = cost(3)
>     io.println("done")
> }
> ```
>
> Under 2c-K, `BLINK_TRACE_CHANNELS=c` always prints `[trace:c] cost 3`. Under 2c-D, the line may
> be missing at `-O2`, and the dev asks why. Today the backend keeps every call, so 2c-K costs
> nothing now.
> **Final vote:** 2c-K
> **Concern:** fns that trace can no longer be removed as dead code, and a later optimizer must
> treat them as such.

**Minimalism**

> ## Q1b
> web and plt say the rows show a takeover, because a library that installs a hook declares `! IO.Print, Env.Exit`. That is true only for a library whose row is small. A server framework already declares those rows for its own I/O, so the hook adds nothing a reader can see:
>
> ```blink
> pub fn serve(app: fn(Req) -> Resp) ! IO, Env, Net {
>     with on_panic(lib_report) {     // row unchanged; the app's report is gone
>         loop_requests(app)
>     }
> }
> ```
>
> The row shows that the library *can* exit. It does not show that it took over the crash report. The closure-capture benefit is real, but it is ergonomics, and its cost is three rules (innermost wins, test interplay, library takeover). The module-state route already works.
> **Final vote:** 1b-M
> **Concern:** a server with concurrent requests keeps the "current request" global per thread, and gets it wrong.
>
> ## Q2c
> plt's point decides it for me. We passed 2A as rowless *because* trace output is not program behavior. Under 2c-K, a trace call becomes a thing that changes what the compiler may do. That is an effect in all but name, with no row to show it. 2c-K also needs a new rule for the optimizer. 2c-D adds no rule: a call the compiler is already free to remove takes its trace with it. Haskell's `Debug.Trace` behaves the same way, and users learn it in one sentence. I change my vote.
> **Final vote:** 2c-D
> **Concern:** a dev traces a pure helper whose result is unused, sees no line at `-O2`, and needs the writer's one-sentence note to know why.
