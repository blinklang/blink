[< All Decisions](../DECISIONS.md)

# Panic Hook and Dev Trace, the Open Points — Design Rationale

**Question.** The first ruling on the panic hook and the dev trace ([panic-hook-and-dev-trace.md](panic-hook-and-dev-trace.md)) left five points open. What does a user name `trace` do to `trace.log`? How does the program read the items of `BLINK_TRACE_CHANNELS`? Does a panic report hold a stack trace? What is a failed `debug_assert`? What does `PanicInfo` hold for a fault that the runtime raises?

**Answer.** (1) A binding named `trace` hides the built-in `trace.log` by lexical scope. (2) The program splits the items of `BLINK_TRACE_CHANNELS` and of `BLINK_TRACE` on `,` (and `+`), trims ASCII space and tab from the two ends of each item, skips empty items, and matches by exact text. (3) The spec does not require a stack trace. The report holds the message, and `file:line` when the line is known. (4) With debug on, `debug_assert(c, m)` is `assert(c, m)` in every context. (5) A fault that user code can cause is a panic with the call site in `file` and `line`; a fault with no Blink site is a fatal runtime error and the hook does not run.

**Release note.** Three changes are visible to users. The text of a runtime fault loses its `blink: ` lead-in, so a `matching:` string that tests for `blink: ` must change. A failed `debug_assert` no longer prints the three lines of `DEBUG ASSERT FAILED` and exits with code 1: it gives the report of a failed `assert` and exits with code 101 (in a test, a `failed` record with `"cause": "assertion"`, and the next test runs). `BLINK_TRACE` trims the ends of each item and skips empty items; before, `fn:a, depth:2` dropped the second filter, and an empty item ended the parse of the rest of the value. `BLINK_TRACE_CHANNELS` has the same item rule, and its item `all` works inside a list.

**Spec.** §2.20 (*`panic()` Function*, *Panic Hook: `on_panic`*, `debug_assert`), §4.7.2, §8.10 (the `cause` table), §8.15.5, §8.15.7. No new error code. The row of `UnresolvedMethod` (E0505) in ERROR_CATALOG.md is not changed: the help line of Q1b is an example in §8.15.7 and not required wording.

### Decision

| Q | Result | Tally | Dissent |
|---|---|---|---|
| Q1a | A binding named `trace` hides the built-in by lexical scope, as for `io` and `env`. A module-level `trace` hides it only in its own module. `trace.log` on it is `UnresolvedMethod`. | 6-0 | none |
| Q1b | The spec shows the help line in the example output. It is not required wording. | 5-1 | DevOps/Tooling: the note is required |
| Q2a | `BLINK_TRACE_CHANNELS`: split on `,`, trim ASCII space and tab from the two ends of each item, skip empty items, match exactly (case counts), the item `all` anywhere turns on every channel. No warning. | 6-0 | none |
| Q2b | `BLINK_TRACE` (§8.15.5) uses the same item rule for its `,` and `+` lists. | 6-0 | none |
| Q2c | No warning for a literal channel that no value can select. A lint is a follow-up and is not in this ruling. | 5-1 | Minimalism: reject the lint |
| Q3a | Drop "with a stack trace". Exit code 101. No stack trace is required. A `--debug` backtrace stays a "may". | 6-0 | none |
| Q3b | With no hook, the default report holds the panic message, and `file:line` when the line is known. The form and layout are not normative. | 6-0 | none |
| Q4 | With debug on, `debug_assert(c, m)` is `assert(c, m)` in every context. In a test, a failure is `"status": "failed"`, `"cause": "assertion"`, with the operand lines. Inside `assert_panics` it gets what `assert` gets there. | 5-1 | DevOps/Tooling: a failed `debug_assert` is a panic |
| Q5a | `PanicInfo.message` for a runtime fault is the fault text with no `blink: ` lead-in, for example `"list set index out of bounds: 4"`. | 6-0 | none |
| Q5b | A fault that user code can cause (index, set, pop, `Str` index, overflow) carries its call site in `file` and `line`. A fault with no Blink site is a fatal runtime error (§4.7.2): the hook does not run, and the runtime writes its own report. `file` is never `""`. | 6-0 | none |

**Agreed by all six, not voted (Q4).** The failure message is `assertion failed: debug_assert(<cond>)`, and it holds the message of the user when one is given. The text `debug_assert(` is stable. When debug is off, `c` is still typechecked (types, names, effect rows) and not evaluated, and the call is `()`. Outside a test, a failed `debug_assert` ends with exit code 101, and `on_panic` gets it. The three-line `DEBUG ASSERT FAILED` text and its exit code 1 go.

**Phase C moves.** Minimalism moved from Q1b-none to Q1b-example, from Q2b-no to Q2b-yes, and from Q3b-free to Q3b-content. Systems moved from Q1b-none to Q1b-example. Web/Scripting moved from Q4-panic to Q4-assert.

**Dissent.** Each dissent below is the full text of the section of the ballot of the seat, copied without change.

*DevOps/Tooling on Q1b (the note that names the hiding binding is required).*

> **Vote:** Q1b-required
> **Reasoning:** For my seat, the note is the behavior: it is the one line that turns a confusing type error into a rename. If it lives in the catalog row, the diagnostics goldens can test it, and a later refactor of the method-error path cannot drop it unseen. An example the spec does not require is a note that no test protects.
> **Concern:** If Q1b-example wins, the note will be lost the first time someone rewrites the `UnresolvedMethod` path, and nothing will fail.

*DevOps/Tooling on Q4 (a failed `debug_assert` is a panic).*

> **Vote:** Q4-panic
> **Reasoning:** A `debug_assert` is a debug-only contract in the code under test, not the test's own check. A failed `@requires` and an `unwrap` on `None` in a library both give `panicked`, so a broken invariant should too, or CI triage lands on the wrong side. Q4-panic also gives one category in every context (in `main` it is already a panic with exit 101 and a hook run), and `t` passes by the existing `assert_panics` text, with no dependence on the open spec ticket.
> **Concern:** If Q4-assert wins, `assert_panics(matching: "debug_assert(")` fails today (a failed `assert` is not taken). That pattern was proposed in Phase A by sys, plt and me, and it will look broken to users until the separate `assert_panics` ruling lands.

*Minimalism on Q2c (reject a lint for a channel that no value can select).*

> **Vote:** Q2c-reject
> **Reasoning:** The user sees this typo the first time they run with the channel on. A dedicated warning is a new diagnostic to specify, implement and test, and nobody has asked for it. If real users hit it, a friction ticket can reopen it.
> **Concern:** If the user rarely turns that channel on, the typo can sit unseen for a long time.

**Follow-ups, open.** Two questions came out of the ballot. This ruling does not decide them.

1. What exit code does a fatal runtime error give? §4.7.2 names none. Out of memory calls `exit(1)` today, the same code as `env.exit(1)`. Five seats gave this as the concern of Q5b.
2. Should `assert_panics` take a failed `assert`? Today a failed `assert` in an `assert_panics` body is not taken, and the test is `failed`. The spec does not say. A failed `debug_assert` follows the answer, because it is `assert` with debug on.

A third item is a follow-up lint, not an open spec question: a warning for a literal `trace.log` channel that no value of `BLINK_TRACE_CHANNELS` can select (Q2c).

### Panel Deliberation

Six seats voted: Systems, Web/Scripting, PLT, DevOps/Tooling, AI/ML and Minimalism. Each quote below is the full text of the reply of the seat, copied without change. The only edits: a ticket ID in the heading of a reply is removed, and the directory in front of a scratch file name is removed. The text of the moderator rounds is not quoted.

#### Phase A — Independent proposals

Each seat proposed alone, from the brief of the five points.

**Systems**

> # Systems seat (sys): proposals
>
> Sys asks one question about each point: what does it compile to, and what does it cost at run time and at startup? My answer for every point is that the cheap choice is also the honest one. I give one exception on point 5.
>
> ## P1. A user binding named `trace`: pick (a), normal lexical lookup
>
> `trace` is a plain identifier. A module fn, an import alias, a param or a local named `trace` hides the built-in namespace, the same way a local named `io` hides `io` today. `trace` is not an effect handle, so E0710 has no analogue here. The compiler adds no new error code. The existing diagnostic gets one help line.
>
> ```blink
> fn trace(phase: Str, msg: Str) { }
>
> fn f() {
>     trace.log("c", "x")
> }
> ```
> ```
> error[UnresolvedMethod]: unresolved method `.log` on type Fn(Str, Str) -> ()
>   help: `trace` here is the fn at line 1, which hides the built-in `trace.log`; rename the fn to use it
> ```
>
> Tradeoffs:
> - Name lookup costs nothing at run time either way.
> - (b) puts two rules on one identifier: `trace.log` would be special while `trace(...)` stays ordinary. Every tool that resolves names would need the special case, so the cost lands in the front end and in the LSP.
> - (c) breaks working code for no runtime gain. The compiler's own `src/ast.bl:831` would need a rename before src could even compile.
> - (a) is the rule users already know from `io` and `env`.
>
> Rust and Go take the same approach: a local `log` shadows the `log` package or crate, and nothing is special-cased.
>
> ## P2. `BLINK_TRACE_CHANNELS` items: pick (b), trim ASCII space and tab, skip empty items, no warning
>
> - The runtime parses the var once at startup into a fixed table. Trimming costs a few bytes of work, once.
> - Names compare as exact bytes after the trim, and case counts.
> - `all` anywhere in the list means all channels.
>
> ```blink
> fn main() ! IO {
>     trace.log("walk", "w")
>     trace.log("mono", "m")
> }
> ```
> With `BLINK_TRACE_CHANNELS="mono, walk"` or `"mono,,walk,"`, stderr is `[trace:walk] w` then `[trace:mono] m`, and the exit code is 0.
>
> Against (c), the warning: under `--trace`, the spec says each stderr line is valid JSON (§8.15.7 *The form*). A plain-text startup warning would break that NDJSON stream before the first event. Making the warning a JSON event instead adds a new event type for one typo. And with (a), `" walk"` silently matches nothing, which is the hardest failure to debug.
>
> Cost note, not spec text: a call site with a literal channel can cache its on/off bit after the first check. A disabled call then costs one load and one branch.
>
> ## P3. "with a stack trace": pick (a), drop the phrase
>
> The default report is one line. Its form is not normative.
>
> ```blink
> fn main() { panic("boom") }
> ```
> stderr is `panic: boom at app.bl:1`, and the exit code is 101.
>
> Why not (b):
> - A required trace means an unwinder plus a symbolizer: libunwind or libbacktrace, DWARF kept in release binaries, a bigger binary and one more link dependency.
> - At `-O2`, C frames are inlined, so a symbolized C stack is often wrong about Blink frames.
> - True Blink frames need a shadow stack, which costs every call. That is the opposite of zero overhead.
>
> Why not (c): it is redundant. Since the form is not normative, an implementation may already print more under `--debug` (for example `-g -O0` plus a backtrace) without a spec sentence. Naming it in the spec turns a free choice into an obligation.
>
> Rust prints a backtrace only with `RUST_BACKTRACE=1`, so the cost is paid on request. Go always prints goroutine stacks, but it pays for that with a runtime that keeps a symbol table in every binary.
>
> ## P4. Failed `debug_assert`: pick (a), it is a panic
>
> A failed `debug_assert` routes through the dispatcher. Exit code 101, the hook gets it, and `assert_panics` and the test runner frame catch it.
>
> The message drops the three-line format and becomes one line in the form that `assert` uses, with the location passed apart through `__blink_panic_dispatch_at`. The fn name goes away; `file:line` is enough.
>
> ```blink
> fn main() {
>     debug_assert(1 == 2)
> }
> ```
> Under `--debug`, stderr is `panic: debug assertion failed: 1 == 2 at app.bl:2`, and the exit code is 101.
>
> ```blink
> test "debug_assert is catchable" {
>     assert_panics(matching: "debug assertion failed") {
>         debug_assert(1 == 2)
>     }
> }
> ```
> This test passes, and later tests still run.
>
> Tradeoffs:
> - With the assert off, it costs zero, as before.
> - With it on, the failure path becomes the same cold call that `assert` makes. That removes code: `__blink_debug_assert_fail` and its `exit(1)` go away (`bootstrap/runtime_core.h:4696`).
> - (b) keeps a second way to end the process. Exit code 1 is already the code for "tests failed" in `blink test` (§8.10.5), so a crash with that code reads as an ordinary failure.
> - (c) adds a report format that no test can match against reliably.
>
> Rust's `debug_assert!` is `assert!` behind `cfg(debug_assertions)`: same panic path, same code 101.
>
> ## P5. PanicInfo for a runtime fault
>
> **`message`: pick (b), drop the `blink: ` lead-in.** The message is the fault text only. The default report adds `panic: ` and the location in one place, the dispatcher, the same way `__blink_panic_dispatch_at` already does for faults the compiler raises. That gives one report format for every panic, and `matching:` patterns get simpler.
>
> **`file`: split by where the fault comes from (my one exception to "always cheapest").**
>
> - **Faults from a Blink expression in the program** (index out of bounds, `pop` on an empty list, a `Str` index, overflow): pick (b), the call site. `file` and `line` name that expression.
>   - Overflow already gets its location from the compiler (`cg_expr.bl:1483`); the other faults should match.
>   - Codegen passes `file` and `line` as constant args to the checking runtime entry. Those entries are `static inline` in the header, so after inlining the constants only reach the cold panic call. The hot path costs nothing.
>   - In the archive-linked build, each entry gets two extra register moves per call.
>   - Rust does exactly this: `panic_bounds_check` takes `&'static Location` through `#[track_caller]`.
> - **Faults inside the runtime with no Blink site** (internal `Str` errors, an FFI call that returns NULL): pick (a), `file` is `""` and `line` is `None`. The rule: `file` is `""` exactly when the runtime knows no location, and `line` is then `None`.
>   - (c) would change a type that a panel already set, to say something that `""` together with `line: None` already says.
>   - (c) also makes every hook match on two Options for a case that is rare.
>
> ```blink
> fn report(p: PanicInfo) -> Never ! IO.Eprint, Env.Exit {
>     io.eprintln("fatal: {p.message} [{p.file}]")
>     env.exit(70)
> }
>
> fn main() ! IO, Env {
>     with on_panic(report) {
>         let mut xs = [1]
>         let i = xs.len() + 3
>         xs.set(i, 2)
>     }
> }
> ```
> stderr is `fatal: list set index out of bounds: 4 [app.bl:10]`, and the exit code is 70. With no hook, stderr is `panic: list set index out of bounds: 4 at app.bl:10`, and the exit code is 101. A fault inside the runtime prints `panic: <text>` with no ` at` part.
>
> Cost of the split: an ABI change on about 28 runtime entries in `bootstrap/runtime_core.h`. Under the bootstrap protocol, the old one-arg entries stay until gen0 is re-pinned, which is the same pattern as the commit that added `__blink_panic_dispatch_at` (41222b65).
>
> ## Summary
>
> | Point | Sys pick |
> |---|---|
> | P1 | (a) lexical lookup, plus one help line |
> | P2 | (b) trim and skip, no warning |
> | P3 | (a) drop "with a stack trace" |
> | P4 | (a) a panic, exit 101, one-line report |
> | P5 message | (b) drop the `blink: ` lead-in |
> | P5 file | call site for faults from a Blink expression; `""` with `line: None` for internal runtime faults |

**Web/Scripting**

> ## Web seat: proposals
>
> My test for each point: a JS or Python developer hits it on their first day. What does the screen tell them, and what fixes it?
>
> ### P1. `trace` uses normal scoping (choice a), and the error gets a help line
>
> A binding named `trace` (module fn, import alias, local, param) hides the built-in namespace in its scope. This works as `let console = 5; console.log("x")` works in JS, and as a user name that hides `print` works in Python. Both of those languages also skip a reserved word for this case. `trace` is a common user name: the compiler has one, and so do profilers and HTTP tracers. A hard error (c) breaks that code to protect a dev tool. Choice (b) gives one name two meanings in one scope. Nobody will guess that, and it will make Stack Overflow questions.
>
> The fix for discoverability is the error text, not the rule:
>
> ```blink
> fn trace(phase: Str, msg: Str) { }
>
> fn f() {
>     trace.log("c", "x")
> }
> ```
> ```
> error[UnresolvedMethod]: unresolved method `.log` on type Fn(Str, Str) -> ()
>  --> a.bl:4:5
>   help: `trace` here is the fn at a.bl:1, which hides the built-in `trace.log`.
>         Rename the fn to use `trace.log`.
> ```
>
> If the user's own type has a `.log`, then `trace.log(...)` calls it with no warning. A JS dev expects that. No new code and no escape syntax (YAGNI).
>
> ### P2. Trim spaces, skip empty items (choice b)
>
> A channel that does not turn on and gives no error is the worst developer experience here. The dev thinks their code did not run, and they debug the wrong thing. People type `"mono, walk"` by hand, and shell scripts that build the list leave a trailing comma.
>
> - Trim spaces at the two ends of each item. Skip empty items. Keep case as typed: `Mono` is not `mono`.
> - An item that is `all` after the trim turns on all channels, as `all` alone does.
> - Use the same rule for the comma lists of `BLINK_TRACE` (§8.15.5), so the two vars read the same.
> - No startup warning (c). The runtime has no list of channel names, so it cannot warn on a misspelled name, and a warning only for a space is noise.
>
> ```
> BLINK_TRACE_CHANNELS="mono, walk,"  ->  channels {mono, walk}
> BLINK_TRACE_CHANNELS=" , "           ->  no channels
> ```
>
> Tradeoff: a channel name with a space at an end can never be turned on. That is fine. As an option, a `trace.log` with a literal channel that is empty or has a comma or an end space could get a warning, because no value of the var can select it.
>
> (The compiler's own `dbg_channel_on` matches items exactly. The tool's internals can follow this rule later.)
>
> ### P3. One line by default; a stack under `--debug` only (choice c, with the words dropped from the production sentence)
>
> Python devs expect a traceback. Rust devs expect one line plus `note: run with RUST_BACKTRACE=1`. Go prints all goroutine stacks. A production binary needs no unwinder or symbol tables to be useful. It needs a stable first line that tools can grep.
>
> - Production: one line, `panic: boom at app.bl:2`, exit 101. Remove "with a stack trace" from §2.20.
> - `--debug` and `blink test` builds may print Blink frames after the line. They use the V8 shape that every JS dev knows:
>
> ```
> panic: n out of range: 9 at app.bl:12
>     at deep (app.bl:12)
>     at main (app.bl:20)
> ```
>
> This stays non-normative ("may"), so the spec does not get ahead of a runtime that has no unwinder. Do not require it (b). That puts a large runtime job on the spec for a dev-only feature.
>
> ### P4. A failed `debug_assert` is a panic (choice a)
>
> In Python, a failed `assert` raises `AssertionError`, a normal exception. In Rust, `debug_assert!` is `assert!` behind a cfg flag. Nobody expects a failed check to skip the test runner and kill the whole suite. The behavior today, where one failed `debug_assert` stops all later tests, is the bug that people will report first.
>
> - It panics: exit 101. `on_panic` gets it, and `assert_panics` and the test runner frame catch it.
> - Its report has the same shape as `assert`. The runtime prints this today for `assert(1 == 2)`:
>   ```
>   assertion failed: assert(1 == 2)
>     1 = 1
>     2 = 2
>     --> a.bl:2:5
>   ```
>   With `--debug`, `debug_assert(1 == 2)` prints the same block, with `debug_assert(1 == 2)` on the first line. Exit 101.
> - `PanicInfo.message` is `"assertion failed: debug_assert(1 == 2)"`. `file` and `line` point at the call.
> - Drop the "DEBUG ASSERT FAILED" text. A check that is two words longer must not have a second failure language.
>
> ```blink
> test "debug_assert is catchable" {
>     assert_panics(matching: "debug_assert") {
>         debug_assert(1 == 2)
>     }
> }
> ```
>
> This passes, and later tests in the file still run. Choice (c) gives the same result, with its own report text. I accept (c) only if that text has the same shape as `assert`'s.
>
> ### P5. `file` is the nearest Blink call site (choice b); the message drops `blink: ` (choice b)
>
> **File.** The developer asks "which line of MY code?" Rust gives this answer with `#[track_caller]`: an index panic names the user line, not a line in the stdlib. A runtime fault that names no location sends the user to grep their code for `.set(`.
>
> - `file` and `line` are the Blink call that went into the runtime entry that faulted.
> - Only when no Blink frame exists (a fault before `main`) are `file` `""` and `line` `None`.
> - Keep `file: Str`. Choice (c), `Str?`, adds a second nested `match` to every hook, the spec's own example included, to serve a rare case.
>
> **Message.** Drop the `blink: ` lead-in. With a hook, `fatal: blink: list set...` has two prefixes. With no hook, every panic now has one shape:
>
> ```blink
> fn main() ! IO {
>     let mut xs = [1]
>     let i = xs.len() + 3
>     xs.set(i, 2)
> }
> ```
> ```
> panic: list set index out of bounds: 4 at app.bl:4
> ```
> Exit 101. `PanicInfo { message: "list set index out of bounds: 4", file: "app.bl", line: Some(4) }`.
>
> **Tradeoff:** codegen must pass a location into each runtime entry that can panic. That is real work, but it is a one-time compiler cost. The other choices cost every user who hits a fault.
>
> **Summary:** 1a + help line · 2b (the same rule for `BLINK_TRACE`) · 3c (the words dropped from the production sentence) · 4a, with `assert`'s report shape · 5b file / 5b message
>
> **Probes:** `probe/web/a.bl` gave the `assert` report above. `b.bl` in the same folder did not run: it used `xs[i]`, which Blink rejects with `error[NoIndexOperator]`, so I have no runtime output for an index fault with a location.

**PLT**

> # PLT seat: Phase A proposals
>
> All five rulings follow from three rules:
>
> - **R1. Names resolve one way.** A name resolves by the lexical order of §6.3.4. `x.m` resolves `x` first and then looks up `m`.
> - **R2. A type shows its own partial cases.** It does not use an in-band sentinel, such as `""`, to mean "unknown".
> - **R3. Normative text covers only what a program or test can observe.**
>
> ---
>
> ## P1. `trace` is a prelude-level name, and a user binding hides it (choice a)
>
> **Behavior.** `trace` resolves at priority 6 (the module prelude), the same as any built-in name. A local, a parameter, a module-level `fn`/`let` or an import alias named `trace` hides it in its own scope. The name `trace` is not reserved, and E0710 does not apply, because `trace` has no effect and no fn declares an effect that reserves it. A module-level `trace` in one module does not hide the built-in in other modules.
>
> ```blink
> fn trace(phase: Str, msg: Str) { }
>
> fn f() {
>     trace.log("c", "x")
> }
> ```
> ```
> error[UnresolvedMethod]: unresolved method `.log` on type Fn(Str, Str) -> ()
>  --> a.bl:4:11
>   = help: `fn trace` (a.bl:1) hides the built-in `trace.log`; rename it to use the tracer here
> ```
>
> The compiler gives this error today. The only new part is the `help` line. It shows when the receiver is a user binding named `trace` and the member is `log`.
>
> **Why not (b).** Under (b), `trace.log` would resolve differently from `trace`, so `trace` would be a name in a second namespace. That breaks R1 and the plain reading of `x.m`. It also makes `let t = trace` a hole: what does `t` denote? A model that reads `trace.log` must then know a special case. The rule for `io` and `env` (a local hides them when no fn declares the effect) is already (a). Choice (b) would make `trace` the only exception.
>
> **Why not (c).** It reserves a word without making it a keyword. It breaks `src/ast.bl` and any user code that already has a `trace` binding, and it only saves a rename.
>
> **Cross-language.** In Haskell, a local `trace` hides `Debug.Trace.trace` in the same way. Rust's `println!` is safe from this only because it is a macro, and Blink has no macro namespace.
>
> ---
>
> ## P2. `BLINK_TRACE_CHANNELS` is a total, normalising parse (choice b, plus `all` as an item)
>
> **Behavior.** Split the value on `,`. Trim ASCII spaces and tabs from each item, then drop the empty items. The result is a set of items. Channel `c` is on when the item `all` or the item `c` is in the set. The parse never fails, and the runtime prints no startup warning. An unset var and an empty var both give the empty set. Matching is exact and case-sensitive after the trim.
>
> | Value | On |
> |---|---|
> | `"mono, walk"` | `mono`, `walk` |
> | `"mono,,walk,"` | `mono`, `walk` |
> | `" , "` | nothing |
> | `"mono,all"` | every channel |
>
> **Why.** The meaning becomes a plain function from a string to a set of channels, so the order of items and repeated items have no effect. Under (a), `" walk"` names a channel that no literal call matches, so it fails silently. Under (c), the runtime writes to stderr by itself even when no channel is on, which goes against "writes nothing if unset". Handling `all` as an item, and not only as the whole value, keeps the rule a set union with no special form. A channel named `all` is still well defined: the item `all` turns it on.
>
> **Cross-language.** Rust's `RUST_LOG` and Go's `GODEBUG` both trim and skip empty items.
>
> ---
>
> ## P3. Drop "with a stack trace" (choice a)
>
> **Behavior.** §2.20 should say "terminates the process and writes a report to stderr, exit code 101". It should not promise a stack trace. An implementation may add a backtrace, for example under `--debug`, as part of the report, whose form is not normative.
>
> ```blink
> fn main() {
>     panic("boom")
> }
> ```
> stderr: `panic: boom at app.bl:2` (this form is not normative). Exit code: 101.
>
> **Why.** Under R3, no test can check that a stack trace exists, because the report is not normative. A clause that the reference runtime breaks today is a spec bug. Choice (b) would add an unwinder and a symbolizer to the runtime ABI for no gain in semantics. Choice (c) is covered by "not normative".
>
> **Cross-language.** Go always prints a trace. Rust prints one only with `RUST_BACKTRACE`. Neither puts it in the language spec.
>
> ---
>
> ## P4. A failed `debug_assert` is a panic (choice a, with stable message substrings)
>
> **Behavior.** Define `debug_assert` by desugaring.
> - **When on:** `debug_assert(c, m)` ≡ `if !c { panic(<msg>) }`.
> - **When off:** it is `()`. The compiler still typechecks `c`, but the program does not evaluate it.
>
> Because it is an ordinary panic:
> - With no hook, the default report goes to stderr and the exit code is 101.
> - `on_panic` gets it, and `PanicInfo.line` is the line of the call.
> - `assert_panics` catches it.
> - Under the runner, it gives `"status": "panicked"`, and later tests still run.
>
> The message contains the stable substring `debug assertion failed`. It also contains the condition's source text and `m` when one is given. This follows the precedent of `todo`, `not yet implemented` (§2.20 *Messages*).
>
> ```blink
> test "invariant holds" {
>     assert_panics(matching: "debug assertion failed") {
>         debug_assert(1 == 2)
>     }
> }
> ```
> Result: passed. Run with `blink run --debug` and no hook, `fn main() { debug_assert(1 == 2) }` writes `panic: debug assertion failed: 1 == 2 at q4.bl:2` (form not normative) and exits 101.
>
> **Why a panic and not an assertion failure.** `debug_assert` guards invariants in code under test. It is a debug-only contract, not a test check. A failed `@requires` check panics, so a failed `debug_assert` must panic too. A test-only "failed" status would make its meaning depend on where it is. Choice (b) gives a second termination path with its own exit code, past the hook and the catch frames. That breaks the claim that the hook gets every panic, and it is the bug the ticket note describes. Choice (c) is only (a) with the substring above.
>
> **Cross-language.** Rust's `debug_assert!` expands to `assert!`, which panics.
>
> ---
>
> ## P5. Every panic has a Blink source site, so `file: Str` stays (file choice b; message choice b)
>
> **File.** The panic's site is the Blink expression that raised it. For a fault inside runtime code, the site is the Blink call that entered the runtime: `xs.set(i, 2)` is at `app.bl:4`. Codegen passes the static location into each runtime entry point that can panic. A fault that has no Blink site, such as one at startup or in the runtime's own threads, is a *fatal runtime error* under the existing §4.7.2 rule. It is not a panic, and the hook does not run. With these rules `file` is always known, so `file: Str` is exact. `line` stays `Int?` for code the compiler generates with no line.
>
> **Message.** Drop the `blink: ` lead-in. `message` is the fault text, such as `list set index out of bounds: 4`. A lead-in belongs to the report, not to the data, and it would show up in `matching:` and in hook output.
>
> ```blink
> fn main() ! IO {
>     let mut xs = [1]
>     let i = xs.len() + 3
>     xs.set(i, 2)
> }
> ```
> With the `report` hook from §2.20, stderr is `fatal: list set index out of bounds: 4 at app.bl:4`. With no hook, it is `panic: list set index out of bounds: 4 at app.bl:4`, exit 101.
>
> **Why not file (a) or (c).**
> - (a) `""` is an in-band null, which breaks R2. Every hook would need to check for it, and the type does not show that.
> - (c) `Str?` lets the type hold a state that never happens: `file = None` with `line = Some(n)`. It also makes the common case harder to use.
> - (b) puts the cost in codegen (one static pointer per call that can fail). It gives a total, honest type and the same report form for user panics and runtime faults.
>
> **Cross-language.** Rust's `#[track_caller]` gives a `Vec` index panic the location of the user's call, not of the library code. Go also reports the user's frame for a runtime bounds error.
>
> That is the end of my Phase A proposals.

**DevOps/Tooling**

> I propose this behavior for each of the five points.
>
> # DevOps seat: Phase A proposals
>
> What I judge on: what a CI log shows, what a supervisor or a hook can count on, and whether the LSP resolves `trace` by the same rule as every other name.
>
> ## P1: `trace` follows normal scoping, and the error names what hides it (choice a, with a better diagnostic)
>
> **Behavior.** A local, parameter, module-level fn or `let`, or import alias named `trace` hides the built-in namespace, in the same way a local `io` hides `io` today in a fn that does not declare IO. Then `trace.log(...)` resolves against the user binding. It stays `UnresolvedMethod`, but the diagnostic gets a note and a help line:
>
> ```blink
> fn trace(phase: Str, msg: Str) { }
>
> fn f() {
>     trace.log("c", "x")
> }
> ```
> ```
> error[UnresolvedMethod]: unresolved method `.log` on type Fn(Str, Str) -> ()
>  --> app.bl:4:11
>   |
> 4 |     trace.log("c", "x")
>   |           ^^^ no method `log` on fn `trace`
> note: `trace` here is the fn at app.bl:1, which hides the built-in `trace.log`
> help: rename the fn `trace` to use the built-in tracer
> ```
>
> `trace(...)` used as a plain call compiles with no warning.
>
> **Tradeoffs.**
> - **(b)** makes name lookup depend on the next token. The LSP would have to special-case `trace` + `.log` for go-to-definition, hover and rename. Rename-symbol on the user's `trace` would then skip some uses and take others.
> - **(c)** turns a valid module fn into a hard error. That includes `src/ast.bl:831`, so the compiler needs a migration dance for no gain to the user.
> - **(a)** is the rule that rust-analyzer and the TS server already implement. The only risk is a confusing message, and the note fixes that.
>
> **Cross-language note.** Python has no reserved namespace at all: `import logging; logging = 3` simply hides the module. The Python error is bad because it never says what hid the name. Ours says.
>
> ## P2: `BLINK_TRACE_CHANNELS` trims spaces, skips empty items and never warns (choice b)
>
> **Behavior.**
> - The program splits the value on `,` and trims ASCII spaces and tabs from each item. It skips empty items.
> - Names match exactly, and case matters.
> - An item `all` turns on every channel, even inside a list.
> - An unknown name matches nothing, with no message.
>
> ```
> BLINK_TRACE_CHANNELS="mono, walk"    -> channels mono, walk
> BLINK_TRACE_CHANNELS="mono,,walk,"   -> channels mono, walk
> BLINK_TRACE_CHANNELS=" "             -> no channel (same as unset)
> ```
>
> **Tradeoffs.**
> - The worst failure is silent: the user set the var and nothing prints. Values come from YAML `env:` blocks, docker env files and shell string builders, and those routinely add spaces and trailing commas. (a) punishes all of these, with no sign of what went wrong.
> - (c) is worse for my seat. A startup warning writes to the program's own stderr. Under `--trace` it breaks the rule that each stderr line is valid JSON. It also adds noise to the stderr that a supervisor captures.
> - A channel name with a space inside it or at its ends cannot be turned on. That is an acceptable loss.
>
> **Cross-language note.** Rust's `RUST_LOG` (env_logger) ignores empty items in its comma list. Go's `GODEBUG` reads a comma list in the same way.
>
> ## P3: The report is one line by default; extra lines may follow but are not normative (a, with some of c)
>
> **Behavior.**
> - Drop "with a stack trace" from the spec.
> - With no hook, the first stderr line of a panic report carries the message and, when known, `file:line`. Today that line is `panic: boom at app.bl:2`.
> - An implementation may add more lines after it, such as a backtrace under `--debug`. Their form is not normative.
> - The exit code is 101.
>
> ```blink
> fn main() {
>     panic("boom")
> }
> ```
> ```
> panic: boom at app.bl:2        (stderr, exit 101)
> ```
>
> **Tradeoffs.**
> - (b) means an unwinder and a symbolizer for every target we cross-compile with zig cc, including static builds. That is a large runtime cost for a feature a hook cannot even see, because PanicInfo has no frames.
> - One line greps cleanly in CI and stays readable in a supervisor's log.
> - The rule "first line = message + location" gives tools a stable hook point while the lead-in stays free to change.
>
> **Cross-language note.** Rust prints one line plus a hint about `RUST_BACKTRACE`. Go always dumps every goroutine, and CI users then dig through it. I prefer the Rust default.
>
> ## P4: A failed `debug_assert` is a panic (choice a)
>
> **Behavior.**
> - A failed `debug_assert(cond)` (on under `--debug` and in test builds) is a panic at the call site.
> - The message is `debug assertion failed: <condition text>`. With a message argument, that text follows: `debug assertion failed: <msg>: <condition text>`.
> - file and line are those of the call.
> - It goes through the dispatcher:
>   - with no hook: the one-line report and exit 101;
>   - with a hook: the hook gets it;
>   - in a test: the runner records `panicked` and goes on to the next test;
>   - `assert_panics(matching: "debug assertion failed")` catches it.
>
> ```blink
> fn main() {
>     debug_assert(1 == 2)
> }
> ```
> ```
> panic: debug assertion failed: 1 == 2 at app.bl:2     (stderr, exit 101, with --debug)
> ```
>
> **Tradeoffs.**
> - Exit 1 collides with `env.exit(1)`, which is a reported failure. Code 101 exists so that a supervisor can tell a crash from a reported failure, and a failed debug assert is a crash.
> - (b) also keeps the bug in which one failed assert kills the whole test binary, so `blink test` reports `aborted` and you lose every later test result.
> - (c) gives two report formats, so CI log scrapers need two patterns. A distinct message prefix inside the one format is enough to tell them apart.
>
> **Cross-language note.** Rust's `debug_assert!` is an ordinary panic. The message `assertion failed: <expr>` is the model for this one.
>
> ## P5: Runtime faults carry the Blink call site; the message is the fault text only (file b, message b)
>
> **file.**
> - Codegen passes the file and line of the Blink expression into each runtime entry that can panic: index, set, slice, overflow, unwrap and so on.
> - `file` is never empty, and `line` is `None` only when the line is truly unknown.
> - PanicInfo stays as it is, and a bad `file` is a compiler bug, not a case a hook must handle.
>
> **message.**
> - Drop the `blink: ` lead-in. The default report adds its own lead-in, and with `blink: ` kept we print `panic: blink: list set index out of bounds: 4`.
> - The fault text should name both the index and the length. That wording is not normative.
>
> ```blink
> fn main() ! IO {
>     let mut xs = [1]
>     let i = xs.len() + 3
>     xs.set(i, 2)
> }
> ```
> ```
> panic: list set index out of bounds: index 4, length 1 at app.bl:4     (stderr, exit 101)
> ```
>
> The §2.20 example hook, given the same fault, prints `fatal: list set index out of bounds: index 4, length 1 at app.bl:4` and exits 70.
>
> **Tradeoffs.**
> - An index fault with no location is the least useful message a language can give: `index out of bounds: 4`, somewhere in 40k lines.
> - With (a), the spec's own example hook prints `fatal: ... at ` with a blank location.
> - (c) makes every hook match on `file`, for a case that exists only because the runtime did not get the site.
> - The cost is two more arguments on cold fault paths, or an inline check that calls the panic entry with the site. Codegen already passes the message, file and line apart for `panic()` (commit 41222b65).
> - I defer to Systems on how codegen does it, but I hold that the location is known.
> - Out of memory and stack overflow are not panics (§2.20), so no panic is left with "no Blink site".
>
> **Cross-language note.** Rust's `#[track_caller]` exists for exactly this: `Vec` index panics report the user's line, not a line in the standard library.
>
> ## Summary of my votes
>
> | Point | Pick |
> |---|---|
> | 1 | (a), plus a note that names the binding that hides `trace` |
> | 2 | (b): trim spaces, skip empty items, accept `all` as one item of a list, never warn |
> | 3 | (a): one line by default; more lines may follow, but their form is not normative |
> | 4 | (a): a panic with exit 101; the message is `debug assertion failed: <cond>` |
> | 5 | file (b): `file` is never empty; message (b): no `blink: ` lead-in |

**AI/ML**

> # AI/ML seat: proposals
>
> My yardstick: when an agent gets one of these wrong, does the output tell it what to fix? A silent miss is the worst result for me, because an agent cannot correct a mistake it cannot see.
>
> ## P1. A binding named `trace`: choice (a), with a help line that names the binding
>
> **Behavior.** A module fn, an import alias or a local named `trace` hides the built-in, as a local `io` does in a fn with no IO. `trace.log` on that binding is the usual `UnresolvedMethod` error. The error gets one extra note that names the hiding binding and the built-in.
>
> ```blink
> fn trace(phase: Str, msg: Str) { }
>
> fn f() {
>     trace.log("c", "x")
> }
> ```
>
> ```
> error[UnresolvedMethod]: unresolved method `.log` on type Fn(Str, Str) -> ()
>  --> app.bl:4:5
>   note: `trace` here is the fn at app.bl:1; it hides the built-in `trace.log`
>   help: rename the fn, or call it as `trace(...)`
> ```
>
> **Tradeoffs.**
> - **(b) is silent:** with `import mylib.trace`, `trace.log(...)` would quietly call the built-in and never reach `mylib.trace.log`. That bug gives no signal.
> - **(c) costs too much:** it reserves a common word (compilers, tracing libraries, `let trace = backtrace()`) and breaks src/ast.bl, all to prevent an error that (a) already reports clearly.
> - **(a) adds no new rule.** It is the scope rule that `io`/`env` already follow when the effect is not declared. The help line is what lets an agent fix the code in one step.
>
> Cross-language: Python `logging = 5` and Go `fmt := 1` hide the module in the same way.
>
> ## P2. `BLINK_TRACE_CHANNELS` items: choice (b), trim spaces and skip empty items
>
> **Behavior.** Split on `,`, trim ASCII spaces from each item, and skip empty items. Names match exactly and are case-sensitive. If any item is `all`, every channel is on. No warning.
>
> ```blink
> fn main() {
>     trace.log("walk", "x")
> }
> ```
>
> With `BLINK_TRACE_CHANNELS="mono, walk"` or `"mono,,walk,"`, stderr is `[trace:walk] x`.
>
> **Tradeoffs.**
> - **Why not (a):** agents often write `"mono, walk"` in shell commands and CI YAML. With exact items, `" walk"` matches nothing and the trace is silently empty. The agent then thinks the code path does not run, which is a wrong conclusion that leads to wrong edits.
> - **Why not (c):** a startup warning puts noise on stderr, and stderr is the stream an agent reads for the trace.
> - **Accepted cost:** with (b), a channel name cannot start or end with a space. I accept that.
>
> Cross-language: Rust's env_logger accepts `RUST_LOG="a, b"`.
>
> ## P3. "with a stack trace": choice (a), drop it, but make the report's content normative
>
> **Behavior.** With no hook, a panic writes a report to stderr and exits 101. Two parts of the report become normative: it holds the panic message, and it holds the `file:line` when the line is known. The form stays non-normative (the lead-in, the suffix, the line layout). Because the form is free, a later `--debug` backtrace needs no spec change.
>
> ```blink
> fn main() {
>     panic("boom")
> }
> ```
>
> stderr: `panic: boom at app.bl:2` (form not normative). Exit code 101.
>
> **Tradeoffs.**
> - An agent fixes a panic from two facts: the message and the location. Both are in the one line, and the line costs about 10 tokens.
> - An unsymbolized stack trace costs many tokens and gives an agent no added fix data.
> - Requiring a trace (b) makes every target ship an unwinder and a symbolizer, for little gain.
>
> Cross-language: Go always prints goroutine stacks, which is noisy. Rust prints one line plus a `RUST_BACKTRACE` hint. Blink is close to the Rust model, without the hint.
>
> ## P4. A failed `debug_assert`: choice (a), it is a panic
>
> **Behavior.** A failed `debug_assert` is a panic, with the same report shape as `assert`:
> - exit code 101;
> - the `on_panic` hook gets it;
> - the test runner frame takes it, and `assert_panics` catches it.
>
> Its message names `debug_assert`, so `matching:` can tell it apart from an `assert`.
>
> ```blink
> fn main() {
>     debug_assert(1 == 2)
> }
> ```
>
> Under `--debug`:
>
> ```
> assertion failed: debug_assert(1 == 2)
>   1 = 1
>   2 = 2
>   --> app.bl:2:5
> ```
>
> Exit code 101.
>
> **Tradeoffs.**
> - **One failure model.** An agent learns once that a failed check panics and exits 101, and that is true for every check. Today's exit 1 collides with `env.exit(1)`. §2.20 picked 101 so that a caller can tell a crash from a reported failure, and exit 1 breaks that rule exactly here.
> - **Tests stay whole.** Today one failed `debug_assert` kills the whole test binary. An agent that reads the result sees later tests missing, with no cause given.
> - **Why not (c):** a separate report text makes agents learn a second form for no gain.
>
> Cross-language: Rust's `debug_assert!` is `assert!` in debug builds, and it panics.
>
> ## P5. `PanicInfo` for runtime faults: file (b) is the goal, with (a) as the fallback; message (b)
>
> **Behavior: file.** Each panic that §2.20 lists (index out of bounds, overflow, failed contract, unwrap) carries the location of the Blink call site that made the fault happen: `file` and `line = Some(n)`. Only a panic with no Blink frame at all gets `file = ""` and `line = None`. The two always go together, so a hook that checks `line` is correct. `file` stays `Str`.
>
> **Behavior: message.** Drop the `blink: ` lead-in. `message` is the fault text only. The default report puts its own `panic: ` lead-in on every panic, the same for all kinds.
>
> ```blink
> fn main() ! IO {
>     let mut xs = [1]
>     let i = xs.len() + 3
>     xs.set(i, 2)
> }
> ```
>
> stderr: `panic: list set index out of bounds: 4 at app.bl:4`. Exit code 101. `assert_panics(matching: "list set index out of bounds")` matches it.
>
> **Tradeoffs.**
> - **The location matters most.** For an agent, it is the most useful token in a crash report. `list set index out of bounds: 4` with no location in a 10k-line program makes the agent search every `.set` call. The hook example in §2.20 prints `file:line`, and it prints nothing useful for exactly the faults that are most common.
> - **Why not (c):** `Str?` puts a nested match in every hook, and almost every hook gets a file.
> - **Why not a sentinel such as `"<runtime>"`:** it is one more fixed string for agents to learn and to hard-code.
> - **Why drop the lead-in:** if it stays, `message` has two forms, with a prefix for runtime faults and none for `panic()`. Agents will write `matching:` strings that hold `blink:` for one kind and miss it for the other.
> - **Cost:** (b) needs codegen to pass the location into each runtime entry that can panic. That is real work, but it is an implementation ticket and not a spec question.
>
> Cross-language: Rust's `#[track_caller]` exists for this reason. `Vec` index panics report the caller's line, not a line inside libstd.
>
> Probe file: probe/aiml/a.bl. It confirms that a failed `assert` today prints the three-line report above and exits 101, so P4 reuses a form that already exists.

**Minimalism**

> # Minimalism (Min) proposals:
>
> My rule for all five points: add no new mechanism. Each point should be settled either by a rule the spec already has, or by deleting a promise the runtime does not keep.
>
> ---
>
> ## Point 1: a user binding named `trace`. Vote (a), plain lexical scope.
>
> `trace` is not an effect handle. It has no row and no effect, so E0710 does not apply to it. That leaves the ordinary scoping rule that `io` and `env` already follow outside a fn that declares their effect: an inner binding hides an outer name. We need no new rule and no new code.
>
> ```blink
> fn trace(phase: Str, msg: Str) { }
>
> fn f() {
>     trace.log("c", "x")
> }
> ```
>
> ```
> error[UnresolvedMethod]: unresolved method `.log` on type Fn(Str, Str) -> ()
> ```
>
> The fix is to rename the fn or use an import alias. Without the binding, `trace.log` is the built-in.
>
> **Tradeoffs:**
> - (b) gives one name two meanings that depend on the call shape: `trace(...)` is the user fn, `trace.log(...)` is the built-in. Every reader, and every tool that resolves names, must learn that special case. It is the first resolution rule of its kind.
> - (c) reserves a common word, adds an error code, and breaks the compiler's own `src/ast.bl`. A dev tracer is not worth a keyword-like reservation.
> - The existing error is clear enough. The compiler may add a help line ("`trace` here is the fn at ast.bl:N; the built-in `trace.log` is hidden"). That is diagnostic quality and needs no spec text.
>
> **Cross-language:** in Python, a local named `print` hides the builtin with no special case. Go does the same for `len`.
>
> ---
>
> ## Point 2: `BLINK_TRACE_CHANNELS` format. Vote (a), exact items.
>
> Split the value on `,`. Each item is a channel name, matched by exact text. An empty item matches nothing, because no `trace.log` call can usefully gate on "". `all` keeps its meaning only as the whole value, as the spec says now.
>
> ```blink
> fn main() ! IO {
>     trace.log("walk", "w")
>     trace.log("mono", "m")
> }
> ```
>
> | `BLINK_TRACE_CHANNELS` | stderr |
> |---|---|
> | `"mono,walk"` | `[trace:walk] w`, then `[trace:mono] m` |
> | `"mono, walk"` | `[trace:mono] m` (the item is `" walk"`, and no call uses that channel) |
> | `"mono,,walk,"` | both lines; the empty items match nothing |
>
> Exit code is 0 in every row.
>
> **Tradeoffs:**
> - This option needs the fewest words. Trimming makes us define which whitespace counts (spaces, tabs, Unicode?).
> - A startup warning (c) puts output on stderr from a var meant to control stderr output. It also adds a code path to test.
> - The cost of (a) is that a user who types `"mono, walk"` sees no `walk` lines. It is a dev-only var with immediate feedback, so the user sees the problem and fixes it in seconds.
> - I accept (b) as a second choice if the panel wants it, provided the rule is "trim ASCII spaces only". I vote no on (c).
>
> **Cross-language:** Go's `GODEBUG` splits on `,` and does not trim.
>
> ---
>
> ## Point 3: "with a stack trace". Vote (a), delete the phrase.
>
> The spec already says the report's lead-in and suffix are not normative. "With a stack trace" is the one promise in that paragraph that the runtime does not keep. Requiring it (b) adds an unwinder and symbolizer to every target, which is a lot of runtime surface. Saying it is optional (c) is the same as saying nothing.
>
> ```blink
> fn main() {
>     panic("boom")
> }
> ```
>
> stderr is one line, `panic: boom at app.bl:2` (form not normative). Exit code is 101.
>
> **Tradeoffs:**
> - An implementation may still print a backtrace, for example under `--debug`. "Not normative" already allows that.
> - Users who want rich crash reports have `on_panic`, which is the reason the hook exists.
>
> **Cross-language:** Rust prints a backtrace only when `RUST_BACKTRACE` is set. The default is one line.
>
> ---
>
> ## Point 4: what a failed `debug_assert` is. Vote (a), it is a panic, the same as `assert`.
>
> Two ways to fail are worse than one. With (a), a failed `debug_assert` exits 101, `on_panic` gets it, and in a test the runner frame or `assert_panics` takes it.
>
> **Point 4, continued.**
>
> The spec has no text that says what `debug_assert` is. We should add one definition and nothing more: `debug_assert(c)` is `assert(c)` when debug is on, and nothing when debug is off. When debug is off, `c` is not evaluated. The Known-limit text in §8.15.7 already assumes this.
>
> ```blink
> fn main() {
>     debug_assert(1 == 2)
> }
> ```
>
> - **With `--debug`:** stderr is one line, for example `panic: debug assertion failed: 1 == 2 at q4.bl:2`. The text is not normative. The message has the same form as a failed `assert`. Exit code 101.
> - **Without `--debug`:** nothing prints. Exit code 0.
>
> ```blink
> test "debug_assert is a panic" {
>     assert_panics(fn() { debug_assert(false) })    // passes in a test build
> }
> ```
>
> **Tradeoffs:**
> - (c) adds a second report text that must be specified and tested, and gives no extra power. The three-line `DEBUG ASSERT FAILED` block can go.
> - (b) exits 1, which is the same code as ordinary program failure. The panel already moved panics off exit 1 (Q3, 6-0).
>
> **Cross-language:** Rust's `debug_assert!` is `assert!` when debug assertions are on. It is the same panic and goes to the same hook.
>
> ---
>
> ## Point 5: `PanicInfo` for a runtime fault with no location
>
> **`file`: I vote (a). It is `""` when the file is not known, and `line` is then `None`.**
> - We keep the type that just landed.
> - The spec does not forbid (b). An implementation that knows the nearest Blink call site may fill in `file` later as a quality improvement. That needs no ruling.
> - (c) `Str?` gives two ways to say "unknown" (`file: None` and `line: None`). It also makes every hook nest a match, and it changes a type that is days old.
>
> **`message`: I vote (b). Drop the `blink: ` lead-in.**
> - The message is the fault text only.
> - The hook then gets the same shape for `panic("...")` and for a runtime fault. The default report adds its own prefix.
>
> ```blink
> fn report(p: PanicInfo) -> Never ! IO.Eprint, Env.Exit {
>     io.eprintln("fatal: {p.message} file='{p.file}' line={p.line}")
>     env.exit(70)
> }
>
> fn main() ! IO, Env {
>     with on_panic(report) {
>         let mut xs = [1]
>         let i = xs.len() + 3
>         xs.set(i, 2)
>     }
> }
> ```
>
> - **With the hook:** stderr is `fatal: list set index out of bounds: 4 file='' line=None`. Exit code 70.
> - **With no hook:** the default report is one line, for example `panic: list set index out of bounds: 4` (form not normative). Exit code 101.
>
> **Tradeoffs:**
> - To require (b) for `file`, codegen must pass a location into every runtime entry that can panic. That is a large cost. The spec can permit it without requiring it.
> - The lead-in belongs to the report format, and the spec already says that format is not normative. If we keep the lead-in in the data, every hook must strip it.
>
> **Cross-language:** Go's `runtime.Caller` returns `""` and `0` when it does not know the location. It does not use optionals.
>
> ---
>
> ## Summary of Min votes
>
> | Point | Vote | Net spec change |
> |---|---|---|
> | 1 `trace` name | (a) lexical scope | none; the current scoping rule covers it |
> | 2 channel list | (a) exact items | one clause: items match by exact text, and an empty item matches nothing |
> | 3 stack trace | (a) delete the phrase | delete three words |
> | 4 `debug_assert` | (a) it is a panic | one definition sentence, and one failure path |
> | 5 `PanicInfo` | file (a) `""`, message (b) no lead-in | one clause each |
>
> These votes add no error codes, no types and no runtime machinery.

#### Phase B, round 1 — Replies to the moderator digest

The digest listed each option with its proposers. It is not quoted. Each seat replied to the options that it wanted to argue. All six ended with `STABLE` or `NOT STABLE`.

**Systems**

> Phase B round 1, Systems seat (sys).
>
> **P1-v1 (help line in spec or not):** I agree with min. The help line is about diagnostic quality, so it does not need to be normative. I also accept plt's addition, that a module-level `trace` hides the built-in only in its own module. That is plain lexical scope, so it adds no new rule.
>
> **P2-a vs P2-b:** I stay with P2-b. With P2-a, `"mono, walk"` turns on only `mono`, and nothing reports it. On startup cost the two are the same, because both parse once.
>
> **P2-v1 (`all` as one item):** yes, `all` anywhere in the list turns on all channels. That way the parser has one loop and no special case for the whole value.
>
> **P2-v2 (what is trimmed):** ASCII space and tab. Shells and YAML env blocks put tabs in values. A wider set, such as Unicode whitespace, costs code and helps no one.
>
> **P2-v3 (`BLINK_TRACE` too):** yes. One splitter for both vars means less runtime code and one rule for users.
>
> **P2-v4 (compile-time warning for a bad literal channel):** I support it. It costs nothing at run time, and it catches a channel that no value of the var can turn on. It belongs in a lint, not in the core rule.
>
> **P3-v1 (normative content of the report):** I accept the devops/aiml floor. The first stderr line holds the message, plus `file:line` when the line is known. That costs nothing, and the runtime already has both parts apart (`__blink_panic_dispatch_at`). The lead-in, and any lines after the first, stay non-normative. Writer note: a "may print frames under `--debug`" sentence requires nothing that a test could check, so I treat it as wording only.
>
> **P4-v1 (report shape):** I move to web/aiml. `debug_assert` uses the helper that `assert` uses. On my axis this is the better pick: it removes `__blink_debug_assert_fail` and leaves one assert failure path in the runtime, not two.
> ```blink
> fn main() {
>     debug_assert(1 == 2)
> }
> ```
> Under `--debug`, stderr is the `assert` block with `assertion failed: debug_assert(1 == 2)` on the first line, and the exit code is 101. `PanicInfo.message` is `"assertion failed: debug_assert(1 == 2)"`.
>
> **P4-v2 (message argument):** whatever `assert` does with its message arg, `debug_assert` does too. They share one helper, so they cannot differ.
>
> **P4-v3 (when off):** the compiler typechecks `c` but the program does not evaluate it. It emits no code, so the cost is zero. The §8.15.7 *Known limit* text already assumes this.
>
> **P5f:** I move from P5f-2 to **P5f-3**. P5f-3 and P5f-4 do differ, in exactly one class of fault: the runtime's own invariant checks. An example is the checks in `blink_str_len`, which `bootstrap/runtime_core.h:697` calls for every `Str` operation.
> ```blink
> @ffi fn bad_name() -> Str    // C side breaks the Str header contract
>
> fn main() ! IO {
>     let s = bad_name()
>     io.println("{s.len()}")
> }
> ```
> - **P5f-4:** this is a panic with a non-empty `file`. So the location has to reach `blink_str_len` and every other `Str`, `List` and `Map` entry that can hit an internal check. Those are hot paths, and in the archive-linked build they are not inlined. That cost goes on every string operation in every program, to report a runtime bug.
> - **P5f-3:** this is a fatal runtime error, in the same class as out of memory. The runtime writes its report and does not run the hook. Only the faults the user's own code can cause carry a site: index out of bounds, `pop` on an empty list, a `Str` index, overflow. Those sites cost a static location on the cold path.
> - With P5f-3, `file` is never `""`, so the type is honest. That fixes the in-band null I offered as P5f-2's fallback.
> - What the user loses with P5f-3 is a hook run for a runtime bug. A runtime bug says nothing about the user's program, so the hook would have nothing useful to report.
>
> **P5f-1:** against. A hook for an index fault that prints `fatal: ... file=''` is the least useful report, and the location costs nothing on the hot path.
>
> STABLE

**Web/Scripting**

> ## Web seat, Phase B round 1
>
> ### P1-v1: help line in the spec or not
> I have a mild view. Put the help line in the spec example, not in a rule. Spec examples already show diagnostics, and the example is what a reader copies. If the panel calls it diagnostic quality, I will not fight it. I agree with plt that a module-level `trace` hides the built-in only in its own module.
>
> ### P2-a vs P2-b
> I vote P2-b. Under P2-a, a value that people type all the time turns a channel off and says nothing:
> ```
> BLINK_TRACE_CHANNELS="mono, walk" blink run app.bl
> [trace:mono] m          // P2-a: walk is silently off
> [trace:mono] m          // P2-b: both print
> [trace:walk] w
> ```
> The developer then debugs code that is fine. P2-b breaks no program, because a channel name never needs a space at its ends.
>
> - **P2-v1:** Yes. `all` as one item means all channels, so `"mono,all"` turns on everything. There is no other useful reading of that value.
> - **P2-v2:** Trim spaces and tabs, so that text pasted from a shell or a YAML file works. I agree with sys, plt and devops.
> - **P2-v3:** I hold this, softly. `BLINK_TRACE` (`--trace=fn:a,depth:2`) is also a comma list. Two vars in the same section that parse commas in different ways will get a "why does this one work" question. If the panel wants this kept out of the ticket's scope, file it as friction rather than drop it.
> - **P2-v4:** I withdraw the compile-time warning. YAGNI.
>
> ### P3-v1: is the report's content normative?
> I support aiml and devops. The content is normative: the message, plus `file:line` when the line is known. The form is not. CI log scrapers and editors grep for the location, and a report that may leave it out is a report that tools cannot use. This costs nothing, because the runtime already prints both.
>
> On the `--debug` backtrace: I agree it is wording, since "may" gives no requirement anyone can observe. I drop it from the ballot.
>
> ### P4-v1: report shape and message
> I change my vote to the message `debug assertion failed: <cond>` (sys, plt, devops, min). It has a good property: `"assertion failed"` is a substring of it, so `matching: "assertion failed"` catches both `assert` and `debug_assert`, and `matching: "debug assertion"` catches only `debug_assert`.
>
> I still hold one point. The report should give the same help that `assert` gives. Today `assert` prints the value lines (`1 = 1`), and those lines are the most useful part of the report. The report form is not normative (P3-v1), so the value lines are an implementation choice and do not need a ballot question. My only request is that the writer not specify a report for `debug_assert` that is poorer than the one for `assert`.
>
> ### P4-v2: the message argument
> I support devops and plt: the user's text goes in the message.
> ```blink
> fn main() {
>     let n = 5
>     debug_assert(n < 3, "n too big")
> }
> ```
> `--debug` output: `panic: debug assertion failed: n too big: n < 3 at app.bl:3`, exit 101. Python and Rust both print the user's message. Leaving it out discards the one line that the author wrote for this failure.
>
> ### P4-v3: when it is off
> `c` is typechecked but not evaluated. Python `-O` and Rust release builds do the same. The §8.15.7 *Known limit* already assumes it.
>
> ### P5f
> My ranking: P5f-3 first, P5f-2 second, P5f-4 third, P5f-1 last.
>
> **Against P5f-1:** It makes the most common runtime fault, an out-of-range index, report `file=''`. "May fill in later" means every hook author writes code to handle `""` from now on. sys shows that the hot path costs nothing, because the entries are `static inline` and the constants only reach the cold call. So the "large cost" argument does not hold.
>
> **Against P5f-4:** It says the case cannot happen, and leaves undefined what the runtime does when it does happen.
>
> **P5f-3 vs P5f-2:**
> - When codegen passes the site into every entry that can panic, sys's no-site cases (internal `Str` errors, an FFI NULL) are all reached from a Blink call, so they get a site.
> - What is left is a fault on a runtime thread or before any Blink frame. A hook author already handles "the hook did not run" for out of memory and stack overflow. So P5f-3 adds no new case to handle, and it lets the hook use `p.file` with no check.
> - That is the 90% case: a simple hook that just works.
>
> **Do P5f-3 and P5f-4 differ?** I cannot write a Blink program where they do, because every panic a program can raise has a Blink call site. They differ only for a fault with no Blink site:
> - P5f-3 says it is a fatal runtime error: the hook does not run, and there is no `PanicInfo`.
> - P5f-4 says it cannot happen.
>
> P5f-3 is P5f-4 with a defined fallback, so I prefer P5f-3.
>
> STABLE

**PLT**

> PLT seat, Phase B round 1 reply.
>
> **P1-v1 (help line in the spec).** I want the help line in the spec, as an example and not as required wording. It shows the rule that matters: plain lexical hiding, with no second namespace for `trace`. The exact text stays diagnostic quality. I keep my addition: a module-level `trace` hides the built-in only in its own module.
>
> **P2-a vs P2-b.** P2-b. Under P2-a, `"mono, walk"` turns on `" walk"`, a channel that no literal call matches, and nothing tells the user. A total function from the string to a set of channels is the simplest correct meaning.
>
> **P2-v1 (`all` inside a list).** I want `all` as an item. The meaning then stays a set union: the item `all` stands for every channel. Min's "only as the whole value" adds a special form, and `"mono,all"` then silently turns on only `mono`.
>
> **P2-v2 (what is trimmed).** ASCII space and tab. A tab comes from the same YAML and shell sources as a space. I would not trim other whitespace, because Unicode trimming is a choice the spec does not need to make here.
>
> **P2-v3 (same rule for `BLINK_TRACE`).** Yes, if `BLINK_TRACE`'s `,` and `+` lists use the same item rule. Two env vars of one tracer that read lists differently is a needless difference. This is a small spec change outside the ticket, so the writer should mark it.
>
> **P2-v4 (compile-time warning).** No view. It is lint quality. If it is added, it applies only to literal channels.
>
> **P3-v1 (normative report content).** I support aiml's and devops's clause: with no hook, the report holds the message, and `file:line` when the line is known. Everything else is free. A tool can observe and test that, so it passes R3. A `--debug` backtrace under "may" puts no requirement on the runtime, so it is only wording.
>
> **P4-v1 (report shape).** I change my vote to web/aiml: `assertion failed: debug_assert(<cond>)`, rendered by the existing `assert` path. That is the stronger desugaring: when on, `debug_assert(c, m)` ≡ `assert(c, m)`, with the call named `debug_assert` in the message. It gives one renderer and one meaning. The stable substring for `matching:` is `debug_assert(`.
>
> ```blink
> test "invariant" {
>     assert_panics(matching: "debug_assert(") {
>         debug_assert(1 == 2)
>     }
> }
> ```
> Result: passed.
>
> **P4-v2 (message argument).** `m` appears in the message when given, as it does for `assert`. The position stays free.
>
> **P4-v3 (when off).** When off, it is `()`. The compiler still typechecks `c` (types, and the rules for names and rows), but the program does not evaluate it. The typecheck part must be in the ruling: without it, a debug-off build accepts code that a debug-on build rejects. That breaks the rule that a flag changes behavior and does not change which programs compile.
>
> **New item, P4-v5 (runner status).** A failed `debug_assert` is observable in the test JSON as either `"failed"` with `cause: "assertion"` or `"panicked"`. No seat ruled on this. The compositional answer is: the same status and the same `assert_panics` behavior as a failed `assert` at the same place. The writer must check that §2.20 and §8.10 already say `assert_panics` catches a failed `assert`. If they do not, then "`assert_panics` takes a `debug_assert`" (all six seats) needs its own clause. I want this named before the vote.
>
> **P5f-1 to P5f-4.** I merge P5f-3 into P5f-4. As far as I can find, the two give the same behavior: under both, every panic has a Blink site.
>
> - **Against P5f-1.** It makes `""` part of the contract, and every hook then needs a check that the type does not show.
> - **Against P5f-2.** Sys's examples of a fault with no Blink site do have Blink sites:
>   - An FFI call that returns NULL is a Blink call expression.
>   - An internal `Str` fault is reached from a Blink call.
>   - Codegen passes the site of the outermost Blink call into the runtime entry point, so the runtime knows it.
> - **A fault before `main`** (web's case): a module-level `let` initializer is Blink code with a site. A fault in runtime startup, before any Blink code runs, can only be fatal. No hook is installed at that time anyway (the hook lives in `main`), so the only thing that changes is the default report.
>
> ```blink
> fn main() ! IO {
>     let p = ffi_open("x")     // returns NULL, and the runtime faults on it
> }
> ```
> P5f-2 (sys): `file: ""`, `line: None`. P5f-4: `file: "app.bl"`, `line: Some(2)`.
>
> The one case where P5f-3 could differ: a runtime-internal fault with no site under `blink test`. P5f-3 makes it fatal, so the test binary aborts. P5f-4 calls it a compiler bug. I take P5f-4's wording, because an abort is the worse result to write into the spec for a case that should never happen.
>
> NOT STABLE (P4-v5 only; all else is ready to vote)

**DevOps/Tooling**

> # DevOps seat: Phase B round 1
>
> **P1-v1: put the help line in the catalog, not in §2.** I want the note, but the E0565 catalog row already shows where label text belongs: the catalog. Add one clause to the `UnresolvedMethod` row: "when the receiver is a user binding named `trace` and the member is `log`, a note names the binding and says it hides the built-in `trace.log`." That is testable through the diagnostics goldens, and the section text stays free of it. I agree with plt's clause that a module-level `trace` hides the built-in only in its own module. A model or a user reading another module must not have to check imports to know what `trace.log` means.
>
> **P2-a vs P2-b: P2-b.** Min says the user "sees the problem and fixes it in seconds". What the user actually sees is that the `walk` lines are missing, and that looks like "the code path did not run". That sends them off to debug their own code instead of the env var. In CI it is worse, because the var sits in a YAML file that nobody reads again.
>
> - **v1 (`all` as an item): yes.** A set union is a simpler rule than "`all` only as the whole value".
> - **v2 (what gets trimmed): ASCII space and tab, named exactly.** That answers Min's "which whitespace?" with two characters. Tabs show up from heredocs and from `.env` files.
> - **v3 (`BLINK_TRACE`): yes,** with the same trim and skip on its `,` and `+` items. `BLINK_TRACE="fn:a, depth:2"` should not fail silently on the second filter.
> - **v4 (literal-channel warning): not in this ruling.** A new warning code needs its own catalog row. I would file it as a follow-up `type:friction` and keep it out of this ruling.
>
> **P3-v1: I give up my "first line" wording and take aiml's.** Two reasons:
> - A message can hold a newline (`panic("a\nb")`), so a first-line rule promises something the runtime cannot keep.
> - The rule that matters to a CI log or a supervisor is aiml's: the report holds the message, and holds `file:line` when the line is known. The form stays non-normative.
>
> ```blink
> fn main() {
>     panic("bad\nstate")
> }
> ```
> The report contains `bad`, `state` and `app.bl:2`, the exit code is 101, and the layout is not normative.
>
> On the `--debug` backtrace "may": it adds no observable requirement, so it is a wording matter. I agree with that.
>
> **P4-v1: I move to web and aiml, and reuse `assert`'s report and message form.**
> - My Phase A goal was one failure form. `assert` already has a form, and it prints the operand values, which is more fix data than my one-liner. A second one-line form would be the very split I argued against.
> - The rule I propose: a failed `debug_assert` fails exactly as `assert` does, and its message names `debug_assert`.
>
> ```blink
> test "debug_assert is catchable" {
>     assert_panics(matching: "debug_assert(") {
>         debug_assert(1 == 2)
>     }
> }
> ```
> This test passes, and later tests run. Under `blink run --debug`, stderr is `assertion failed: debug_assert(1 == 2)` followed by the operand block, and the exit code is 101.
>
> **P4-v2 (the message argument): whatever `assert` does with its message, `debug_assert` does the same.** No rule of its own.
>
> **P4-v3 (when off): agree with plt.** The compiler still typechecks `c`, but the program does not evaluate it. For CI this matters: a release build and a `--debug` build must accept the same programs. Otherwise a type error shows up only in the test job.
>
> **P5f: P5f-3. I withdraw P5f-4 into it.**
> - P5f-4 states a fact ("no panic has no Blink site"). P5f-3 states the rule that makes the fact true: a fault with no Blink site is a fatal runtime error.
> - I find no Blink program where the two differ. Every fault a program can cause has a Blink expression as its site: a module-level `let`, a call into the runtime, a spawned task's body. The only leftover is a runtime-internal fault, and that is a runtime bug. A hook must not show a runtime bug as a user panic.
>
> Against P5f-1 and P5f-2: both put `""` into the hook's input. Then the §2.20 example hook prints `fatal: ... at ` with an empty location. Every tool author has to learn about that sentinel from the bug report, not from the type. "Permitted but not required" (Min) means hooks have to handle `""` forever, even after codegen always passes the site.
>
> **One new point for the writer, not a ballot item.** P5f-3 leans on "fatal runtime error", and no spec text gives that error an exit code (§4.7.2 at 04_effects.md:4363 names none). Today, out of memory prints `blink: out of memory` and calls `exit(1)`, which collides with `env.exit(1)`. That is the collision Q3 ended for panics. Please log it as a follow-up ticket, apart from this ruling.
>
> **No view:** none. I ruled on every flagged item.
>
> STABLE

**AI/ML**

> # AI/ML seat: Phase B round 1
>
> **P1-v1 (help line in the spec): keep it in the spec, as the example output.** The help line is the part an agent acts on. Without it, `.log on type Fn(Str, Str) -> ()` sends the agent looking for a `log` method on fns. I do not need a rule clause. One example output in §8.15.7 that shows the note is enough, and it is how the spec already shows diagnostics. I agree with plt that a module-level `trace` hides the built-in only in its own module.
>
> **P2-a vs P2-b: P2-b.** min's own example shows the cost:
>
> ```blink
> fn main() {
>     trace.log("mono", "m")
>     trace.log("walk", "w")
> }
> ```
>
> With `BLINK_TRACE_CHANNELS="mono, walk"`, P2-a prints only `[trace:mono] m`. Nothing says that `walk` was dropped, so the agent decides the `walk` path never ran. That is a silent wrong conclusion, the worst case for my seat.
>
> - **P2-v1 (`all` inside a list): yes, `all` anywhere means all.** If `"mono,all"` gives only `mono`, users get the same silent miss.
> - **P2-v2 (what to trim): spaces and tabs.** It costs nothing and it is one rule. I accept the majority wording.
> - **P2-v3 (same rule for `BLINK_TRACE`): yes.** Two env vars from one tool that split commas in different ways is a decision point an agent will get wrong. One rule for both is the smaller design.
> - **P2-v4 (compile-time warning): weak yes, but not in this ruling.** A literal channel like `"a,b"` or `" mono"` can never be turned on, so a lint that flags it removes a silent miss. It needs a new catalog code, so I would file it as a follow-up and not vote on it here.
>
> **P3-v1 (report content normative): yes, the content is normative and the form is not.** devops's "first line holds message + location" is the same as my text, and I accept their wording. The reason: agents and CI greps rely on the location being in the report. If the spec leaves it free, a later runtime change can drop ` at file:line` with no spec break, and every agent loses the fact it needs most to fix a panic. The `--debug` backtrace "may" adds no observable requirement. I agree with sys that it is wording, so leave it out.
>
> **P4-v1 (report shape and message text): mirror `assert`, whatever `assert` does.** My point is not the block layout. It is that one assertion form is fewer things to learn than two. Today `assert(1 == 2)` prints the block with operand values (`1 = 1`, `2 = 2`). Those values are what let an agent fix a failed check without re-running it, and a one-line `debug assertion failed: 1 == 2` drops them.
>
> The two picks match different `matching:` strings:
>
> ```blink
> test "invariant" {
>     assert_panics(matching: "debug_assert") {
>         debug_assert(1 == 2)
>     }
> }
> ```
>
> - With the message `assertion failed: debug_assert(1 == 2)`, both `matching: "assertion failed"` and `matching: "debug_assert"` pass.
> - With the message `debug assertion failed: 1 == 2`, `matching: "assertion failed"` passes too, but `matching: "debug_assert"` does not.
>
> So I propose this. The message has the stable substring `assertion failed`, holds the condition's source text, and names `debug_assert`. Under `--debug`, the report also lists the operand values, as `assert` does. If the majority wants a one-line message, I accept it on one condition: the operand values still appear in the report under `--debug`.
>
> **P4-v2 (the message argument): yes, the user's text goes in the message.** An agent that wrote `debug_assert(n > 0, "n must be positive")` expects to see its own text in the output and in `matching:`. Without it, the message argument has no visible use.
>
> **P4-v3 (when debug is off): typechecked, not evaluated, the value is `()`.** I agree with plt and min. A `cond` that does not compile with debug off is a bug an agent must see at once, not only in a `--debug` build.
>
> **P5f: P5f-2 is my first pick, P5f-3 my second; P5f-1 and P5f-4 are out.**
>
> - **P5f-1 is out.** It gives `file=''` for the most common fault, and that is the report of least use to an agent.
> - **P5f-4 is out.** It states something the runtime cannot guarantee.
>
> P5f-3 and P5f-4 differ for any fault that has no Blink frame. Example: the runtime fails to allocate a `Str` during the setup of the args list, before `main`, or a runtime-owned thread (a GC finalizer, the scheduler) hits an internal bounds check. The code below gives the hook no part in that case:
>
> ```blink
> fn main() ! IO, Env {
>     with on_panic(report) {
>         run()
>     }
> }
> ```
>
> - **P5f-3:** this is a fatal runtime error. `report` does not run, the stderr text is the runtime's own, and the exit code is whatever §4.7.2 gives a fatal error.
> - **P5f-4:** it must be a panic with a real `file`. No such file exists, so the implementation either makes one up or breaks the spec.
>
> So the two do differ. P5f-4 is not honest, and P5f-3 is honest. Under P5f-2 the hook runs with `file=""` and `line=None`, so the tool's JSON frame is still written. I prefer that because an editor tool sees every crash. I accept P5f-3 if the majority wants `file` always valid: it keeps hooks simpler, and the case is rare.
>
> **P5m (drop the `blink: ` lead-in): agree.** I agree with devops's writer note that the fault text names the index and the length.
>
> STABLE

**Minimalism**

> # Min, Phase B round 1
>
> I move from my Phase A position on P2, P4 and P5f. In each case the majority option costs less than I estimated, or it reuses an existing path, so it fits the minimalism rule.
>
> ## P1-v1: help line in the spec
> **No view on the outcome, provided the help line is not a requirement.** The writer can show it as example output. A required diagnostic wording becomes a test obligation, and it does not change behavior.
>
> plt's cross-module note follows from lexical scope. It can go in an example, but it needs no rule.
>
> ## P2-a vs P2-b: I move to P2-b
> Five seats want the trim, and sys made the case well: with exact items, `" walk"` matches nothing and gives no sign, which is the hardest failure to find. Trim ASCII space and tab, and skip empty items.
>
> - **P2-v1 (`all` as one item): yes.** If items are trimmed, "each item is a name, and the item `all` means every channel" is one rule. "`all` only as the whole value" is a second rule, so it is the bigger option.
> - **P2-v2 (what we trim): ASCII space and tab.** This is the majority text, and we need no Unicode rule.
> - **P2-v3 (`BLINK_TRACE` too): no, not in this ruling.** No seat showed a problem with that var's lists. If someone finds one, it needs its own ticket. YAGNI.
> - **P2-v4 (compile-time warning for a bad literal channel): no.** It is a new warning for a typo the user sees at once, and nobody has asked for it.
>
> ## P3-v1: is the report content normative?
> **No, keep the whole report non-normative.** Tools that need a stable shape have `on_panic`, which is why the hook exists, and `blink test --json` already gives them structured output. A rule like "the first line holds the message and file:line" freezes a format we decided to leave free.
>
> I accept aiml's softer form ("the report holds the message") if the panel wants it, but I see no need.
>
> I agree that a `--debug` backtrace "may" is only wording. It adds no requirement, so the writer can leave it out.
>
> ## P4-v1: report shape and message
> Reading the facts again, I side with **web and aiml**. My own rule says `debug_assert(c)` is `assert(c)` when debug is on, so a failed `debug_assert` should take `assert`'s report path. One failure path and one report format, with no `debug assertion failed` text of its own:
>
> ```blink
> fn main() {
>     debug_assert(1 == 2)
> }
> ```
> With `--debug`, stderr is:
> ```
> assertion failed: debug_assert(1 == 2)
>   1 = 1
>   2 = 2
>   --> q4.bl:2:5
> ```
> The exit code is 101.
>
> The spec should fix "it is a panic with `assert`'s report", not the exact text. `matching: "debug_assert"` works because the condition text names the call.
>
> ## P4-v2: the message argument
> **Same as `assert` with a message.** This needs no separate rule.
>
> ## P4-v3: when debug is off
> **Take plt's text.** `c` is still typechecked but not evaluated, and the call is `()`. The typecheck part matters: without it, code under `debug_assert` stops compiling unseen in release builds.
>
> ## P5f: the file of a runtime fault
> devops points out that codegen already passes the message, file and line apart for `panic()` (commit 41222b65), so the cost of the call site is small. **I drop P5f-1.** My order is now **P5f-2 > P5f-3 > P5f-4**.
>
> **P5f-3 and P5f-4 do differ.** They differ for a fault that runtime code raises with no Blink expression under it, such as sys's case of a runtime-internal `Str` error, or an FFI call that returns NULL inside the runtime:
>
> - **P5f-3:** this is a fatal runtime error. The hook does not run. The exit code is whatever a fatal error gives, and §2.20 does not state one. A hook-based JSON reporter goes silent for that crash.
> - **P5f-4:** this is a panic, and the hook runs. But `file` is then filled by "a compiler bug, not a case a hook must handle". The spec would promise a property that no check enforces.
>
> **Why I prefer P5f-2:**
> - The hook gets every panic, and `line: None` already says "location unknown", so `""` costs hooks nothing new.
> - It adds no new boundary between "panic" and "fatal error".
> - It does not make a promise that one runtime path can break. P5f-4 says `file` is never empty, but nothing checks that, so the first runtime fault with no Blink site breaks the spec.
> - plt's objection, that `""` is an in-band null, is fair. But the case is rare, and `line: None` already marks it in the data. A hook that already matches on `line` handles it with no new code.
>
> ```blink
> fn main() ! IO {
>     let mut xs = [1]
>     let i = xs.len() + 3
>     xs.set(i, 2)
> }
> ```
> With no hook, stderr is `panic: list set index out of bounds: 4 at app.bl:4`, and the exit code is 101. If a fault has no Blink site, P5f-2 gives `file` `""` and `line` `None`. The hook still runs, and with no hook stderr is `panic: <text>` with no ` at` part.
>
> If the panel picks P5f-3, I accept it with one condition: the spec states the exit code of a fatal runtime error. Today §2.20 does not, so a crash with no Blink site would have no defined exit code.
>
> ## P5 message
> I agree that the `blink: ` lead-in goes. devops's request to show both the index and the length is wording for the writer.
>
> STABLE

#### Phase B, round 2 — Replies on `debug_assert` in a test and on the file of a runtime fault

Round 1 showed two open points. The first was what a failed `debug_assert` is in a test, and so what `assert_panics` takes. The second was whether the options P5f-3 and P5f-4 give the same behavior. The moderator put both to the seats. All six ended round 2 with `STABLE`.

**Systems**

> Phase B round 2, Systems seat (sys).
>
> ## P4-v5 / P4-v1: probe first
>
> I ran today's `assert` under gen1 (probe/sys/tap_assert.bl):
>
> ```blink
> test "t" {
>     assert_panics(matching: "assert(") {
>         assert(1 == 2)
>     }
> }
>
> test "u" {
>     assert(1 == 2)
> }
> ```
> ```
> test t ... FAIL
> test u ... FAIL
>   assertion failed: assert(1 == 2)
>   1 = 1
>   2 = 2
>   --> tap_assert.bl:3:9
> ```
>
> So `assert_panics` does not take a failed `assert` today. The runtime longjmps straight to the test frame (`__blink_assert_fail`, bootstrap/runtime_test.h), and that matches §4.7.2: "An assertion failure ... [is a failure]". Outside a test, the same helper calls `__blink_panic_dispatch` (`__blink_assert_fail_uncaught`). That gives exit 101, and the hook gets it as an uncaught panic.
>
> My answers, with the rule that `debug_assert(c, m)`, when on, is `assert(c, m)` and its text names `debug_assert`:
> 1. **`u`:** `"status": "failed"`, `"cause": "assertion"`, `assertion: "debug_assert(1 == 2)"`, with the operand lines.
> 2. **`t`:** it fails. `assert_panics` does not take an assertion failure, the same as for `assert`. The record is `failed`/`assertion` at line 3. The later tests still run, which is the P1 bug's real fix.
> 3. **P4-v1:** I hold `assert`'s path. I withdraw the Phase A clause "assert_panics catches it", because it would make `debug_assert` the one assertion that `assert_panics` takes. That needs a third path in the runtime, which is the opposite of the reason I moved.
>
> | Context | `assert(1 == 2)` | `debug_assert(1 == 2)` under `--debug` |
> |---|---|---|
> | test | failed/assertion | failed/assertion |
> | inside `assert_panics` | not taken: test fails | not taken: test fails |
> | main, no hook | report, exit 101 | report, exit 101 |
> | main, hook | hook runs | hook runs |
>
> Cost: zero new runtime code. `__blink_debug_assert_fail` is deleted, and codegen calls `__blink_assert_fail_intro` for both. If the panel wants `assert_panics` to take assertion failures, that is a separate ruling for `assert` too, not a special case for `debug_assert`.
>
> ## P5f: I hold P5f-3
>
> plt says codegen "passes the site of the outermost Blink call into the runtime entry point". For internal checks that means a location argument on `blink_str_len` and every entry under it, on every `Str` operation, in every program. The archive build does not inline those, so the cost lands on hot paths and buys a report for a runtime bug. P5f-3 puts the site only where user code can fault (index, set, pop, `Str` index, overflow), as a constant that reaches only the cold call.
>
> P5f-3 and P5f-4 do differ. aiml's case shows it: a runtime-owned thread (the GC, the scheduler) faulting on an internal check. P5f-4 has no `file` to give, so it has to invent one or break its promise. P5f-3 calls it a fatal runtime error: no hook, and the runtime's own report.
>
> ```blink
> @ffi fn bad_name() -> Str     // C breaks the Str header contract
>
> fn main() ! IO, Env {
>     with on_panic(report) {
>         io.println("{bad_name().len()}")
>     }
> }
> ```
> - **P5f-3:** a fatal runtime error. `report` does not run. stderr is the runtime's report.
> - **P5f-2:** `report` runs with `file: ""` and `line: None`.
> - **P5f-4:** this needs a site on every internal check.
>
> I agree with min and devops that the spec must give a fatal runtime error an exit code. Today out of memory calls `exit(1)`, which collides with `env.exit(1)`. I support a follow-up ticket for it, outside this ruling.
>
> ## Rest
> No change.
>
> STABLE

**Web/Scripting**

> ## Web seat, Phase B round 2
>
> ### P4-v1 / P4-v5
>
> Two questions are mixed here, and I split them:
> - **What the report says:** text. It is non-normative (P3), so it is a writer matter once we fix the message substrings.
> - **What status a failed `debug_assert` gets:** behavior. It needs a vote.
>
> **(1) Status of `u`: `"panicked"`.** A `debug_assert` lives in program code, not in the test. When it fires, the code under test broke its own invariant. That is a crash, the same as a failed `@requires`, and not a check that the test author wrote. pytest draws the same line. It rewrites `assert` with introspection only in test modules, and an `assert` in library code is a plain `AssertionError` crash. Phase A had six seats on "it is a panic", and this keeps that.
>
> The user loses nothing. The `panicked` record still carries the message, and under `--debug` the default report still lists the operand values.
>
> **(2) `t` passes.** `assert_panics` takes panics, and a failed `debug_assert` is a panic.
>
> ```blink
> test "t" {
>     assert_panics(matching: "debug_assert(") {
>         debug_assert(1 == 2)
>     }
> }
> // passed
>
> test "u" {
>     debug_assert(1 == 2)
> }
> // "status": "panicked", message "assertion failed: debug_assert(1 == 2)"
> // later tests still run
> ```
>
> **(3) P4-v1 pick:** I keep the message `assertion failed: debug_assert(<cond>)` (plt, sys, devops, min and aiml now agree), so `matching: "assertion failed"` and `matching: "debug_assert("` both work. The report may reuse `assert`'s renderer, with operand values, and that is an implementation choice. What I vote against is "fails exactly as `assert` does" when it is read to mean `"failed"` + `cause: "assertion"`:
> - That gives `"failed"` for a fault in the code under test.
> - It makes `t` depend on a question the spec does not answer: whether `assert_panics` takes a failed `assert`.
>
> That question exists for `assert` without `debug_assert` and is out of scope here. File it as spec friction. I note the footgun for that ticket: `assert_panics { setup(); assert(x == 3) }` with no `matching:` would pass on a wrong `x`.
>
> ### P5f
>
> I keep **P5f-3 first, P5f-2 second.**
>
> - **P5f-3 and P5f-4 do differ.** Take sys's case: an FFI `Str` that breaks the header contract and trips the internal check in `blink_str_len`.
>   - Under P5f-4 that is a panic with a real `file`. So every hot `Str`, `List` and `Map` entry must carry a location, and in the archive-linked build that cost is not inlined away.
>   - Under P5f-3 it is a fatal runtime error. Only user-caused faults (index, `pop` on empty, `Str` index, overflow) carry a site, on the cold path.
>   - So P5f-4 is either dishonest (aiml) or costs something on every string operation (sys). P5f-3 is neither.
> - **plt's concern (an abort under `blink test`):** the only case that aborts is a runtime bug. It is the same class as out of memory, which already aborts the test binary today. Writing that into the spec is honest, and P5f-4's "cannot happen" is not.
> - **min and aiml's concern (the hook goes silent):** this is true only for runtime bugs, and the hook already goes silent for out of memory. A tool author handles "no hook ran" once, through the exit code. That gives the tool a reason to need a defined exit code for a fatal error, which supports devops's follow-up ticket. I support filing it.
>
> ### P3-v1
>
> No change. I keep "the report holds the message, and `file:line` when known" as normative content, with free form. min's answer that tools should use `on_panic` does not cover the 90% case: a CI log of a program with no hook, which someone reads or greps. aiml's softer form ("holds the message") is my fallback.
>
> ### Everything else
>
> No change.
>
> STABLE

**PLT**

> PLT seat, Phase B round 2 reply.
>
> ## P4-v1 / P4-v5
>
> I keep the rule from round 1: when on, `debug_assert(c, m)` ≡ `assert(c, m)`, and the message names `debug_assert`. It has no test-runner rule of its own. It takes the label of the `assert` family, not of `panic`. A construct whose status depends on the context it runs in does not compose. One label per construct does.
>
> For the two tests in the digest:
>
> 1. **`u`:** `"status": "failed"`, `"cause": "assertion"`, `"assertion": "debug_assert(1 == 2)"`, with the value lines that `assert` gives. The spec already defines this result for `assert`, so `debug_assert` inherits it.
> 2. **`t`:** the same result as `assert_panics(matching: "assert(") { assert(1 == 2) }`. The spec does not define that case today (the digest's grep finds no text). It is a gap about `assert`, not about `debug_assert`, so this ruling must not settle it for `debug_assert` alone. If it did, the two would differ in exactly the one place they should agree.
>    - My view on that gap (it should be a separate ticket): §4.7.2 says "an assertion failure is a failure" and "an expected panic that `assert_panics` catches is not a failure". If `assert_panics` caught an assertion failure, it would turn a failure into a pass. So the failure goes past the armed boundary, and `t` is `"failed"`, `cause: "assertion"`.
>    - Outside tests, nothing changes. With no hook, a failed `debug_assert` under `--debug` writes `assert`'s report to stderr and exits 101. With a hook, the hook gets it, with `message` `assertion failed: debug_assert(1 == 2)` and the line of the call.
> 3. **P4-v1 pick:** reuse `assert`'s path and form (web/aiml/devops/sys/min in round 1). I do not take web's round 2 change to `debug assertion failed: <cond>`. A second message form is a second meaning, unless it shares the same report path, and then its text is not normative anyway. The stable substring is `debug_assert(`.
>
> This takes back the Phase A claim, made by all six seats, that "`assert_panics` takes it" for `debug_assert`. It becomes "it does what `assert` does". The `assert` gap goes to its own ticket.
>
> ## P5f
>
> I move to **P5f-3**, with P5f-4 kept as a consequence of it and not as a separate rule. Sys's case (`@ffi fn bad_name() -> Str`, where the C side breaks the `Str` header contract) is the case my round 1 reply missed. Its site is a runtime invariant check deep in `blink_str_len`, not a Blink call. Passing a location into every such check would put a cost on hot paths that are not inlined. That would be paid on every string operation to report a fault in foreign code or in the runtime.
>
> - §4.7.2 already makes "foreign code that ends the process" a fatal runtime error. A breach of the FFI contract falls into the same class.
> - So, under P5f-3:
>   - A panic is a fault that Blink code raises or causes, and every panic has a site, so `file: Str` stays honest.
>   - A runtime-internal invariant check is a fatal error: no hook, and no `PanicInfo`.
> - Min and aiml prefer P5f-2 because the hook would see every crash. But it already does not see out of memory or stack overflow, so a hook author already handles "the hook did not run". P5f-2 adds `""` for the same rare case, and every hook pays for it through the type.
>
> I agree with min's condition and devops's note: a fatal runtime error needs a stated exit code that is not `1`. That is a follow-up ticket, apart from this ruling.
>
> ## Rest
>
> No change.
>
> STABLE

**DevOps/Tooling**

> # DevOps seat: Phase B round 2
>
> ## P4-v5 and P4-v1: a failed `debug_assert` is a panic; only its report text comes from `assert`
>
> (1) **`u` is `"panicked"`, with no `cause`.**
> (2) **`t` passes.**
> (3) **P4-v1:** I keep the move to `assert`'s report text and message form, but not to its status. The report text and the status are two separate things.
>
> ```blink
> test "t" {
>     assert_panics(matching: "debug_assert(") {
>         debug_assert(1 == 2)
>     }
> }
>
> test "u" {
>     debug_assert(1 == 2)
> }
> ```
> ```
> {"record":"test","name":"t","status":"passed",...}
> {"record":"test","name":"u","status":"panicked","message":"assertion failed: debug_assert(1 == 2)",...}
> ```
>
> Why `panicked` and not `failed`/`assertion`, from the CI side:
> - §8.10 splits the two statuses for a reason: `failed` means "the test's own check found a bug", `panicked` means "the code crashed". A `debug_assert` almost always sits in the code under test, not in the test body. It is a debug-only contract. A failed `@requires` is a panic, and an `unwrap` on `None` in a library gives `panicked`. A violated invariant in a library is the same kind of event. If a dashboard counted it as a test assertion, it would send the triage to the wrong place.
> - One category in every context. In `main` it is a panic: exit 101, and the hook gets it (all six seats in Phase A). In a test it should stay a panic. If it becomes a "failure" only under the runner, its meaning depends on where it runs, and it falls into the §4.7.2 rules for a failure in cleanup and for the first failure.
> - It does not depend on the open question. The spec does not say whether `assert_panics` catches a failed `assert` (digest fact). If `debug_assert` is defined as "≡ `assert`", the result of `t` depends on that gap. If it is defined as "a panic", `t` passes by the existing `assert_panics` text, with no new clause.
>
> So the ruling I want: a failed `debug_assert` is a panic at its call site. Its message has `assert`'s form and names `debug_assert` (`assertion failed: debug_assert(1 == 2)`, with the user's message when given). Under `--debug` with no hook, the stderr report may show the operand values, as `assert` does (web's and aiml's condition; the form stays non-normative). The `panicked` record keeps its own schema: there are no `introspection` fields, and the message carries the text.
>
> The gap plt found, whether `assert_panics` catches a failed `assert`, is real but is not this ticket's. Please log it as a `type:spec` follow-up.
>
> ## P5f: P5f-3. I was wrong that P5f-3 and P5f-4 give the same behavior
>
> sys's case shows the difference: a bad `Str` from FFI hits the runtime's own check inside `blink_str_len`. Under P5f-4, that check needs a site, so a location has to reach every hot `Str`/`List`/`Map` entry in the archive build. Under P5f-3, it is a fatal runtime error, and only the faults the user's code can cause carry a site, on the cold path. P5f-4 is out, and I stay on P5f-3.
>
> Against P5f-2 (min, aiml): a hook-based JSON reporter "sees every crash" only if it handles `""`. The §2.20 example hook does not handle it. And what reaches the hook is a runtime bug, not a fault in the user's program.
>
> **Min's condition, which I back as part of P5f-3:** state the exit code of a fatal runtime error. My proposal: it is not 0, 1 or 101, and nothing else about it is normative. A supervisor can then tell "crash in the program" (101) from "the runtime died". The implementation can use `abort()` (signal 6, shell code 134). Today the out-of-memory path calls `exit(1)`, which is wrong under this rule.
>
> ## Other items
>
> - **P3-v1:** no change. Min wants the whole report non-normative. A hook is opt-in and `--json` is for tests only, so a plain `blink run` in a CI log has only the default report. The message and the `file:line` must be in it.
> - **P1, P2:** no change.
>
> STABLE

**AI/ML**

> # AI/ML seat: Phase B round 2
>
> ## P4-v1 / P4-v5: `debug_assert` is `assert` when on, in every observable way
>
> My rule stays the one from round 1: one assertion form. With `debug_assert` on, `debug_assert(c, m)` behaves as `assert(c, m)`, and its message names `debug_assert`. plt's `debug_assert(` is a good stable substring. So P4-v5 is not a `debug_assert` question. It is the question of what a failed `assert` does, and `debug_assert` follows that answer.
>
> ```blink
> test "t" {
>     assert_panics(matching: "debug_assert(") {
>         debug_assert(1 == 2)
>     }
> }
>
> test "u" {
>     debug_assert(1 == 2)
> }
> ```
>
> 1. **`u`:** `"status": "failed"`, `"cause": "assertion"`, with the same `assertion` and `introspection` fields that `assert(1 == 2)` gets. It is not `"panicked"`. An agent reads `failed` as "the check found a bug". That is the truth here, and it is the same signal `assert` gives.
> 2. **`t`:** passes. `assert_panics` takes a failed `assert` or `debug_assert` that is raised anywhere in its body, callees included, as it takes any other panic. With `matching:`, a wrong message is E0832, as now.
> 3. **P4-v1:** `assert`'s report path and message form, `assertion failed: debug_assert(1 == 2)`, plus the operand values.
>
> **Why `t` must pass.** The main use of `debug_assert` is a guard in library code. The only way to test that a guard fires is test `t`, and agents will write exactly that test. If `assert_panics` does not take an assertion failure, a guard cannot be tested in-process. The agent then sees E0831 or a `failed` record and has no way to fix the test except to delete it. Rust's `#[should_panic]` catches `assert!` and `debug_assert!` for this reason.
>
> **The risk, and why I accept it.** A failed `assert` that sits in the body by mistake is caught too:
>
> ```blink
> test "v" {
>     assert_panics {
>         let r = parse("x")
>         assert(r == 3)
>     }
> }
> ```
>
> If `parse` returns 4, `v` passes and hides the bug. With `matching:` the test gets E0832 and the full message instead. So I ask the writer to show `matching:` in the §8.10.3 example for this case.
>
> This is a ruling on `assert` as well, so I agree with plt that it is named before the vote. My vote: `assert_panics` takes assertion failures. Outside `assert_panics`, an assertion failure stays `failed`/`assertion`.
>
> ## P5f: I move to P5f-3
>
> sys, web and devops changed my view. Under P5f-3, `file` is honest with no sentinel. A hook an agent writes from the §2.20 example (`None => p.file`) never prints an empty location. A runtime-internal fault is a runtime bug and not a panic of the user's program, so a hook that reports it as one misleads the agent that reads the report.
>
> P5f-3 and P5f-4 differ only in what the spec says happens in that case, as sys and min show. P5f-3 gives that case a defined result, so it is P5f-4 with a fallback, and I prefer it.
>
> I add one condition, the same one as min and devops. The spec, or a follow-up ticket filed with this ruling, gives a fatal runtime error:
> - an exit code other than 1 and other than 101;
> - a report that does not start with the panic lead-in.
>
> An agent must be able to tell "my code panicked" from "the runtime broke" in the output alone.
>
> My order is now **P5f-3 > P5f-2 > P5f-4 > P5f-1**.
>
> ## Everything else
>
> No change.
>
> STABLE

**Minimalism**

> # Min, Phase B round 2
>
> ## P4-v5 / P4-v1: a failed `debug_assert` in a test
>
> My rule stays the same: when debug is on, `debug_assert(c, m)` is `assert(c, m)`, and the message names `debug_assert`. It has no status of its own and no `assert_panics` rule of its own. It gets whatever `assert` gets at the same place.
>
> I checked what `assert` does today with gen1 (probe/min/test_min_ap.bl):
>
> ```blink
> test "t" {
>     assert_panics(matching: "assertion failed") {
>         assert(1 == 2)
>     }
> }
>
> test "u" {
>     assert(1 == 2)
> }
> ```
> ```
> {"name":"t","status":"failed","cause":"assertion","message":"assertion failed: assert(1 == 2)",...}
> {"name":"u","status":"failed","cause":"assertion","message":"assertion failed: assert(1 == 2)",...}
> ```
>
> Today a failed `assert` inside an `assert_panics` body is **not** caught. The test fails with `cause: "assertion"`. This matches §4.7.2: "An assertion failure ... [is a failure]. An expected panic that `assert_panics` catches ... [is] not [a failure]."
>
> So for the digest's `t` and `u`:
>
> 1. **`u`:** `"status": "failed"`, `cause: "assertion"`, `message` `"assertion failed: debug_assert(1 == 2)"`, with the `introspection` lines. Later tests run.
> 2. **`t`:** it does not pass. It fails with `cause: "assertion"`, as it does for `assert`.
> 3. **P4-v1:** `assert`'s path and message form, `assertion failed: debug_assert(<cond>)`.
>
> This means I withdraw a claim I made in Phase A. All six seats wrote that "`assert_panics` takes a failed `debug_assert`". That was wrong for `assert`, so it is wrong for `debug_assert` too. Making `debug_assert` catchable where `assert` is not would add a second rule and an odd split. Nobody needs to test that an invariant check fires, so this is YAGNI.
>
> The ticket's real defect still goes away, because the runner records the failure and later tests run. Outside a test, a failed `debug_assert` is a panic in the same way as a failed `assert`: exit 101, and `on_panic` gets it.
>
> Whether `assert_panics` should catch a failed `assert` is a question about `assert`. If the panel wants to settle that question, it should be its own ticket, not a piece of this ruling. Whatever it decides, `debug_assert` follows.
>
> ## P5f: I move to P5f-3, with P5f-2 second
>
> sys, web and devops convinced me:
> - Codegen can pass the site to the entries that user code can make fail (index, pop, overflow), and the cost stays on the cold path.
> - The case left over is a runtime-internal fault, which is a runtime bug. "Fatal runtime error" already exists in §4.7.2, so P5f-3 adds no new concept.
> - `file` is then never `""`, so hooks need no sentinel check.
>
> P5f-4 states that a fault cannot happen and gives no fallback when it does, as aiml's runtime-thread case shows. P5f-3 is the same rule with a defined fallback.
>
> My condition from round 1 stands, but as a follow-up ticket and not as part of this ruling (devops's note). The exit code of a fatal runtime error is unspecified, and out of memory exits 1 today.
>
> ## Everything else
> No change.
>
> STABLE

#### Phase C — Silent vote

Each seat voted alone on the ballot. No Phase D ran. The ballot did not put `assert_panics` and `assert` to a vote: a probe by Systems and Minimalism showed that a failed `assert` inside an `assert_panics` body is not taken today, and the panel left that question to its own ruling.

**Systems**

> # Phase C ballot, Systems seat (sys)
>
> ## Q1a
> **Vote:** Q1a-yes
> **Reasoning:** Plain lexical lookup costs nothing at compile time or run time, and every tool that resolves names uses the same rule for `trace`, `io` and `env`. A special case for `trace.log` would be a second namespace rule that each tool must copy.
> **Concern:** A module-level `fn trace` (such as src/ast.bl's) blocks `trace.log` in that whole module. Users can read that as a bug until the help line points to the cause.
>
> ## Q1b
> **Vote:** Q1b-example
> **Reasoning:** I can accept an example. It shows the behavior that lexical hiding causes, and it binds no implementation to exact text. A required clause would make diagnostic wording part of conformance, and that is a cost with no runtime effect. This is a step up from my Q1b-none, because the example costs nothing.
> **Concern:** Readers copy examples as if they were rules, so a compiler with a different help text can look non-conformant.
>
> ## Q2a
> **Vote:** Q2a-yes
> **Reasoning:** The runtime parses the var once at startup into a fixed table, so the trim and the skip cost a few bytes of work, once. It closes the silent `" walk"` miss, and it writes no warning that could break the NDJSON stream under `--trace`.
> **Concern:** A user who wants a channel name with an end space cannot turn it on. No real program needs one, but the rule makes it impossible.
>
> ## Q2b
> **Vote:** Q2b-yes
> **Reasoning:** One item splitter for both vars means less runtime code and one rule to learn. `BLINK_TRACE="fn:a, depth:2"` has the same silent miss today.
> **Concern:** It changes §8.15.5 outside this ticket's scope, so the writer must mark the change. A user who relies on today's exact parse sees different output.
>
> ## Q2c
> **Vote:** Q2c-followup
> **Reasoning:** The lint costs nothing at run time, and it catches a channel that no value of the var can turn on. But a new warning code needs its own catalog row and tests. Keeping it out of this ruling keeps the ruling small.
> **Concern:** A follow-up friction ticket can stay in the backlog for a long time, so the dead literal channel stays silent until someone picks it up.
>
> ## Q3a
> **Vote:** Q3a-yes
> **Reasoning:** A required stack trace means an unwinder plus a symbolizer, DWARF kept in release binaries, and more link dependencies. At `-O2` it would still give wrong Blink frames. A one-line report costs none of this.
> **Concern:** Users who come from Go or Java expect frames, and they can find one line too little for a deep fault. A `--debug` backtrace stays an unstated extra.
>
> ## Q3b
> **Vote:** Q3b-content
> **Reasoning:** The runtime already has the message, file and line apart (`__blink_panic_dispatch_at`), so the rule costs nothing. It gives CI greps and agents a contract that a later runtime change cannot break by accident.
> **Concern:** A message that holds the text of a file location can confuse a grep that looks for `file:line`. The rule says the report holds both parts, not where they stand.
>
> ## Q4
> **Vote:** Q4-assert
> **Reasoning:** With debug on, `debug_assert` lowers to the same `__blink_assert_fail_intro` call as `assert`. So there is one failure path, `__blink_debug_assert_fail` is deleted, and no new runtime code is added. With Q4-panic, `debug_assert` becomes the one assertion that `assert_panics` takes, and that needs a third path in the runtime.
> **Concern:** If the separate ruling keeps `assert_panics` from taking assertion failures, a user cannot test that an invariant fires with `assert_panics`. They will ask why `debug_assert` is not a panic.
>
> ## Q5a
> **Vote:** Q5a-yes
> **Reasoning:** The dispatcher adds the lead-in and the location in one place, so every panic has one report format. With `blink: ` kept, the report reads `panic: blink: ...`, and `matching:` patterns carry noise.
> **Concern:** Existing tests that use `matching: "blink: ..."` break when the lead-in goes, so the corpus needs one sweep.
>
> ## Q5b
> **Vote:** Q5b-3
> **Reasoning:** A fault that user code can cause gets its site as a constant that reaches only the cold call, so the hot path costs nothing. A runtime-internal invariant check, such as the one in `blink_str_len`, stays free of a location argument, and `file` is never `""`. Q5b-4 would put a site on every internal check, including on hot non-inlined archive entries. Q5b-2 puts an in-band null into the hook's data.
> **Concern:** Until the fatal-runtime-error exit code is specified, a runtime bug ends with an undefined code, and today that code is `exit(1)`, which collides with `env.exit(1)`.

**Web/Scripting**

> # Web seat ballot
>
> ## Q1a
> **Vote:** Q1a-yes
> **Reasoning:** This is how `console` and `print` behave when a user binding hides them in JS and Python. A developer can predict it with no new rule. A hard error would break a common name, which the compiler itself uses.
> **Concern:** A user who names a fn `trace` and later adds a `trace.log` call gets a type error that does not mention the built-in, unless the help line is there.
>
> ## Q1b
> **Vote:** Q1b-example
> **Reasoning:** The spec example is what readers and models copy, so the help line should appear in it. But a required wording in a row puts a test obligation on diagnostic text that will change over time. The example sets the quality bar without making it a rule.
> **Concern:** If the help line is only an example, an implementation may ship without it, and the confusing error is then the one users see.
>
> ## Q2a
> **Vote:** Q2a-yes
> **Reasoning:** `"mono, walk"` is what people type, and an exact-match rule turns `walk` off with no sign. The developer then debugs the wrong thing. The trim breaks no real channel name.
> **Concern:** "Case counts" means `Mono` turns nothing on with no warning, which is the same silent-off failure in a smaller form.
>
> ## Q2b
> **Vote:** Q2b-yes
> **Reasoning:** Two comma-list env vars in the same section that parse commas in different ways will create a "why does this one work" question. One rule for both is less to learn.
> **Concern:** A trim in the `+` lists of `BLINK_TRACE` must not change how an existing filter value parses. The writer should check the filter grammar for values that have spaces in them.
>
> ## Q2c
> **Vote:** Q2c-followup
> **Reasoning:** I withdrew this in round 1. It is a nice-to-have lint and should not block or grow this ruling.
> **Concern:** The friction ticket may never get done. A bad literal channel is rare, so the cost of that is small.
>
> ## Q3a
> **Vote:** Q3a-yes
> **Reasoning:** The spec should not promise a stack trace that the runtime does not print. A one-line report with a location is what Rust gives by default.
> **Concern:** Python developers expect a traceback, and with no `--debug` backtrace planned anywhere they may file this as a bug.
>
> ## Q3b
> **Vote:** Q3b-content
> **Reasoning:** In the 90% case, a program with no hook crashes in CI and someone reads or greps the log. If the message or the `file:line` can be missing, that log is no use. The runtime prints both today, so this costs nothing.
> **Concern:** A test of "contains `file:line`" can over-fit to today's layout unless the goldens check substrings only.
>
> ## Q4
> **Vote:** Q4-assert
> **Reasoning:** In round 2 I argued for panic. I change my vote, because the five-minute explanation wins: "`debug_assert` is `assert`, and it runs only in debug builds." Rust developers already know that model, and a JS or Python developer can learn it in one sentence. Both options fix the real bug, where one failed check aborted the whole test suite. Q4-assert also gives `u` the `failed` record with operand introspection, which is more help than a bare `panicked` message.
> **Concern:** Until the separate `assert_panics` ruling lands, a developer who wants to test that their invariant fires (test `t`) finds that `assert_panics` does not take it. That will make Stack Overflow questions, so the follow-up ticket should not wait long.
>
> ## Q5a
> **Vote:** Q5a-yes
> **Reasoning:** `fatal: blink: list set ...` has two lead-ins, and every hook would have to strip one. The message should be the fault text, so that panics the user raises and faults the runtime raises read the same.
> **Concern:** None from my seat. The writer should take devops's note that the text names both the index and the length.
>
> ## Q5b
> **Vote:** Q5b-3
> **Reasoning:** Every fault that user code can cause names the user's line, as Rust's `#[track_caller]` does. The hook can use `p.file` with no check for `""`. The only case with no site is a runtime bug, which belongs in the same class as out of memory, where hooks already do not run.
> **Concern:** A hook-based JSON reporter goes silent on a runtime bug, and the exit code of a fatal runtime error is not yet defined. So the follow-up spec ticket on that exit code needs to land soon.

**PLT**

> # Phase C ballot: PLT seat
>
> ## Q1a
> **Vote:** Q1a-yes
> **Reasoning:** Under this rule, `trace` follows the same lexical rule as every other name, and `x.m` keeps one reading: resolve `x`, then look up `m`. Any other choice puts a second namespace into name lookup for one identifier.
> **Concern:** When a user `trace` hides the built-in in a large module, the error appears far from the binding. That makes the note in Q1b matter in practice.
>
> ## Q1b
> **Vote:** Q1b-example
> **Reasoning:** The note is not a typing or name-resolution rule. It makes no difference to which programs compile or what they do. Showing it as an example records the intent and does not make diagnostic wording part of what the language means.
> **Concern:** An implementation can leave the note out and still conform, and the users who hit this case would then get no hint.
>
> ## Q2a
> **Vote:** Q2a-yes
> **Reasoning:** The value maps to a set of channels by a total function. The order of items and repeated items have no effect, and `all` stands for the full set. No input fails and none needs a warning.
> **Concern:** A channel whose name has an end space or a comma can never be turned on, and nothing reports it unless Q2c follows.
>
> ## Q2b
> **Vote:** Q2b-yes
> **Reasoning:** Two env vars of one tracer should read lists by one rule. Without it, the same text means different things in the two vars, which is needless non-uniformity.
> **Concern:** The change touches §8.15.5, which this ticket does not cover. The writer must keep that edit small and mark it.
>
> ## Q2c
> **Vote:** Q2c-followup
> **Reasoning:** The warning is a lint over literal arguments, and it does not change the meaning of the gate. It should get its own small ticket and not widen this ruling.
> **Concern:** The follow-up may never be done, and dead channels then stay silent.
>
> ## Q3a
> **Vote:** Q3a-yes
> **Reasoning:** Normative text must say only what a program or a test can observe. A stack trace in a report whose form is free is neither, and the reference runtime breaks the clause today.
> **Concern:** Users may read the dropped phrase as a ban on backtraces. The writer should keep the "may".
>
> ## Q3b
> **Vote:** Q3b-content
> **Reasoning:** "The report holds the message, and `file:line` when it is known" is a property that a test can check, and it says nothing about layout. It gives tools a fixed minimum at almost no cost to the runtime.
> **Concern:** Tools may start to parse the non-normative lead-in and suffix as well. A later change to the layout would then break them.
>
> ## Q4
> **Vote:** Q4-assert
> **Reasoning:** When on, `debug_assert(c, m)` desugars to `assert(c, m)` in every context, so it adds no rule of its own. A construct whose test status differs from the construct it desugars to does not compose. Under Q4-assert, the open `assert_panics` question gets one answer that covers both constructs.
> **Concern:** Until the separate `assert_panics` ruling lands, users cannot test that a `debug_assert` fires (`t` fails). They may write workarounds with `panic` in its place.
>
> ## Q5a
> **Vote:** Q5a-yes
> **Reasoning:** `message` is data, and a lead-in is formatting of the report. Putting it into the data leaks into `matching:` and into hook output.
> **Concern:** Today the runtime fault texts are not stable. Users may match on them with `matching:` anyway, and a wording change will then break those tests.
>
> ## Q5b
> **Vote:** Q5b-3
> **Reasoning:** A panic is a fault that Blink code raises or causes, so each panic has a site and `file: Str` stays honest, with no in-band `""`. A fault in runtime-internal or foreign code goes into the fatal-error class that §4.7.2 already defines. Hook authors already handle that class for out of memory and stack overflow.
> **Concern:** The line between "a fault that user code can cause" and "a runtime-internal check" is a runtime choice that users cannot see. If the runtime puts a fault on the wrong side, a user-caused fault can skip the hook.

**DevOps/Tooling**

> # DevOps ballot (Phase C)
>
> ## Q1a
> **Vote:** Q1a-yes
> **Reasoning:** One lookup rule for every name, so the LSP's go-to-definition, hover and rename all work with no special case for `trace`. It is also the rule `io` and `env` already follow outside a fn that declares their effect.
> **Concern:** A user who writes a module fn `trace` and later adds `trace.log` sees a method error on a fn type. Without the note, that error looks like a compiler bug.
>
> ## Q1b
> **Vote:** Q1b-required
> **Reasoning:** For my seat, the note is the behavior: it is the one line that turns a confusing type error into a rename. If it lives in the catalog row, the diagnostics goldens can test it, and a later refactor of the method-error path cannot drop it unseen. An example the spec does not require is a note that no test protects.
> **Concern:** If Q1b-example wins, the note will be lost the first time someone rewrites the `UnresolvedMethod` path, and nothing will fail.
>
> ## Q2a
> **Vote:** Q2a-yes
> **Reasoning:** Values come from YAML `env:` blocks, `.env` files and shell builders, which add spaces and trailing commas. A channel that is silently off is the worst failure, because the user debugs the wrong code. A startup warning would break the rule that every stderr line under `--trace` is valid JSON.
> **Concern:** A user can still misspell a channel name (`mnoo`), and nothing tells them. The trim does not cover that.
>
> ## Q2b
> **Vote:** Q2b-yes
> **Reasoning:** Two env vars from one tracer, in one section, should read their lists the same way. If they differ, `BLINK_TRACE="fn:a, depth:2"` silently drops a filter, and that is the same class of silent miss as Q2a.
> **Concern:** The change sits outside the ticket's stated scope, so the writer must mark it in the release note. Otherwise a reader of §8.15.5 misses it.
>
> ## Q2c
> **Vote:** Q2c-followup
> **Reasoning:** A literal channel that no value can select is a real silent miss, and a lint would catch it at compile time. But a new warning needs a code, a catalog row and a `--strict` story. That is its own ticket, and it should not ride along with this ruling.
> **Concern:** If it goes in now, the panel picks a code and its wording without the review a new diagnostic gets.
>
> ## Q3a
> **Vote:** Q3a-yes
> **Reasoning:** The runtime prints one line, and a required stack trace would mean an unwinder and a symbolizer on every zig-cc target. One line greps cleanly in CI and in a supervisor's log.
> **Concern:** Users who come from Python or Go will ask where the traceback is. The docs must point them to `on_panic` and to `--debug`.
>
> ## Q3b
> **Vote:** Q3b-content
> **Reasoning:** A hook is opt-in and `--json` is for tests only, so a plain `blink run` in a CI log has only the default report. The message and the `file:line` are the two facts a person or a tool needs to act. Making them normative costs nothing, because the runtime has both apart.
> **Concern:** A multi-line message (`panic("a\nb")`) can split the location from the start of the message, so a naive one-line grep can still miss the location.
>
> ## Q4
> **Vote:** Q4-panic
> **Reasoning:** A `debug_assert` is a debug-only contract in the code under test, not the test's own check. A failed `@requires` and an `unwrap` on `None` in a library both give `panicked`, so a broken invariant should too, or CI triage lands on the wrong side. Q4-panic also gives one category in every context (in `main` it is already a panic with exit 101 and a hook run), and `t` passes by the existing `assert_panics` text, with no dependence on the open spec ticket.
> **Concern:** If Q4-assert wins, `assert_panics(matching: "debug_assert(")` fails today (a failed `assert` is not taken). That pattern was proposed in Phase A by sys, plt and me, and it will look broken to users until the separate `assert_panics` ruling lands.
>
> ## Q5a
> **Vote:** Q5a-yes
> **Reasoning:** The default report and a hook each add their own prefix. If `blink: ` stays in the data, the report prints `panic: blink: ...`, and `matching:` strings differ between runtime faults and `panic()`.
> **Concern:** None from my seat, provided the fault text names both the index and the length.
>
> ## Q5b
> **Vote:** Q5b-3
> **Reasoning:** Every fault a user's code can cause names the user's line, which is the most useful fact in a crash report, and hooks can use `p.file` with no check for `""`. A runtime-internal fault is a runtime bug, and a hook must not present it as a panic in the user's program.
> **Concern:** Until the fatal-runtime-error exit code is specified (out of memory calls `exit(1)` today), a supervisor cannot tell "the runtime died" from "the program reported a failure". The follow-up ticket must not wait long.

**AI/ML**

> # Phase C ballot: AI/ML seat
>
> ## Q1a
> **Vote:** Q1a-yes
> **Reasoning:** This is the scope rule that `io` and `env` already follow when a fn does not declare their effect, so an agent learns no new rule. The error comes at the call site, which an agent can see and fix. Option (b) would turn `import mylib.trace` into a silent wrong call.
> **Concern:** Without a good note, `.log on type Fn(Str, Str) -> ()` sends an agent to look for a `log` method on fns instead of telling it to rename its binding.
>
> ## Q1b
> **Vote:** Q1b-example
> **Reasoning:** Agents learn diagnostics from the outputs that the spec shows, so the help line belongs in the spec as an example. The example tells the implementer that the note is expected. It does not freeze the wording for each change to the diagnostics.
> **Concern:** If the example is not normative, a later refactor of the diagnostics can drop the note and no gate fails, so a golden test should cover it anyway.
>
> ## Q2a
> **Vote:** Q2a-yes
> **Reasoning:** Agents often write `"mono, walk"` in shell commands and CI YAML. With exact items, that value gives a silently empty trace, and the agent then concludes the code path never ran. Trim-and-skip removes that wrong conclusion and adds no new output.
> **Concern:** A channel name that a user meant to hold an end space can never be selected. That case is rare, and Q2c is the place to catch it.
>
> ## Q2b
> **Vote:** Q2b-yes
> **Reasoning:** If two env vars from the same tool split commas by different rules, that is a decision point an agent will get wrong. With one item rule for both vars, the agent has one rule to learn.
> **Concern:** The trim must not change how a filter value with an inner space is read, so the writer should state that only the two ends of each item are trimmed.
>
> ## Q2c
> **Vote:** Q2c-followup
> **Reasoning:** A literal channel that no value can select is a silent miss, and a lint is the right fix for it. But a lint needs a catalog code and its own discussion, so it should not ride on this ruling.
> **Concern:** A follow-up ticket can wait in the backlog for a long time, and the silent miss stays until it lands.
>
> ## Q3a
> **Vote:** Q3a-yes
> **Reasoning:** One line with the message and the location is all the data an agent needs to fix a panic, and it costs about ten tokens. A stack trace with no symbols costs many tokens and gives an agent nothing more to act on.
> **Concern:** When a panic comes from a shared helper, users will want the chain of callers. The spec must not later read "not normative" as a ban on a `--debug` backtrace.
>
> ## Q3b
> **Vote:** Q3b-content
> **Reasoning:** Agents and CI greps rely on the location being in the report. If the content is free, a runtime change can drop ` at file:line` with no spec break, and the most useful fact for a fix is gone. Making the content normative while the form stays free keeps that fact for every agent.
> **Concern:** A test of "contains the message" can be hard to write when the message has newlines or control characters, so the gate needs care.
>
> ## Q4
> **Vote:** Q4-assert
> **Reasoning:** One assertion model is one thing to learn: with debug on, `debug_assert` is `assert` in every context, with the same record and the same operand lines. `u` as `failed`/`assertion` tells an agent the truth, which is that the check found a bug. Whether `assert_panics` takes an assertion failure is a single rule for both calls, and it belongs on its own ticket.
> **Concern:** Until that ticket rules that `assert_panics` takes assertion failures, test `t` fails. So a guard in library code that uses `debug_assert` cannot be tested in-process, and agents will write test `t` and see it fail.
>
> ## Q5a
> **Vote:** Q5a-yes
> **Reasoning:** If the lead-in stays, `message` has two forms, with a prefix for runtime faults and none for `panic()`. Agents would then write `matching:` strings that work for one kind and miss the other. A lead-in belongs to the report, not to the data.
> **Concern:** None from my seat, except that a test that matches on the old `blink: ` text breaks, and the release notes must say so.
>
> ## Q5b
> **Vote:** Q5b-3
> **Reasoning:** Under Q5b-3, `file` is honest with no sentinel, so a hook written from the §2.20 example never prints an empty location. A runtime-internal fault is a runtime bug, and a hook that reported it as a user panic would mislead the agent that reads the report.
> **Concern:** A fatal runtime error has no stated exit code and no stated report form. Until the follow-up ticket fixes that, an agent cannot tell "the runtime broke" from "my code panicked" or from `env.exit(1)`.

**Minimalism**

> # Phase C ballot: min
>
> ## Q1a
> **Vote:** Q1a-yes
> **Reasoning:** This uses the scoping rule that `io` and `env` already follow outside a fn that declares their effect. It needs no new rule, no reserved word and no new error code.
> **Concern:** A user who names a module fn `trace` sees the built-in vanish in that module, and if the help line is missing, the `Fn(...)` type in the error is the only clue.
>
> ## Q1b
> **Vote:** Q1b-example
> **Reasoning:** I move from Q1b-none to Q1b-example. Showing the help line as an example costs nothing and teaches the fix, and it puts no obligation on the compiler. A required wording would turn a diagnostic-quality choice into a conformance test.
> **Concern:** Readers can take an example for a requirement, and then golden tests freeze the wording anyway.
>
> ## Q2a
> **Vote:** Q2a-yes
> **Reasoning:** The rule is one sentence, and it has no warning path. Under the exact-items rule, `" walk"` matches nothing and gives no sign, and nobody is helped by that.
> **Concern:** A channel name that has an end space can never be selected. Q2c-reject accepts that, because nobody writes such a name on purpose.
>
> ## Q2b
> **Vote:** Q2b-yes
> **Reasoning:** I change my vote. Two env vars of the same tool with two item rules is a bigger surface than one shared rule. "Use the same rule" adds one clause and removes a difference users would have to learn.
> **Concern:** If `BLINK_TRACE` filter values can contain spaces now or later, the trim could change what they mean.
>
> ## Q2c
> **Vote:** Q2c-reject
> **Reasoning:** The user sees this typo the first time they run with the channel on. A dedicated warning is a new diagnostic to specify, implement and test, and nobody has asked for it. If real users hit it, a friction ticket can reopen it.
> **Concern:** If the user rarely turns that channel on, the typo can sit unseen for a long time.
>
> ## Q3a
> **Vote:** Q3a-yes
> **Reasoning:** This deletes a promise the runtime does not keep, and it needs no unwinder. Tools that want more use `on_panic`.
> **Concern:** Users moving from Go may expect a stack trace and find the one line too terse.
>
> ## Q3b
> **Vote:** Q3b-content
> **Reasoning:** I move to the majority. "The report holds the message, and `file:line` when known" is a small, testable floor that every implementation meets today. It also stops a report from dropping the message, and the form stays free.
> **Concern:** Tools may start to parse the default report anyway, and treat the free layout as fixed.
>
> ## Q4
> **Vote:** Q4-assert
> **Reasoning:** `debug_assert(c, m)` is `assert(c, m)` when on, in every context. That gives one failure path, one test status and one `assert_panics` behavior, with no rule of its own. Q4-panic makes the two checks report differently in a test, `failed` for one and `panicked` for the other, so users must learn a split. When the separate ticket rules on whether `assert_panics` catches a failed `assert`, `debug_assert` follows that ruling.
> **Concern:** Until that ticket lands, a user cannot use `assert_panics` to test that a `debug_assert` fires.
>
> ## Q5a
> **Vote:** Q5a-yes
> **Reasoning:** The lead-in belongs to the report, not to the data. The hook then sees one message shape for both user panics and runtime faults.
> **Concern:** Without the lead-in, the default report cannot tell a runtime fault from a `panic("...")` with the same text. The layout is free, so an implementation can add that back.
>
> ## Q5b
> **Vote:** Q5b-3
> **Reasoning:** "Fatal runtime error" already exists in §4.7.2, so this adds no concept. `file` is never `""`, so hooks need no sentinel check. The site cost stays on the cold paths of faults that user code can cause.
> **Concern:** The exit code of a fatal runtime error is unspecified, and today out of memory exits 1, the same as `env.exit(1)`. The follow-up spec ticket must land, or this case stays undefined.

