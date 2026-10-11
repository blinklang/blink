[< All Decisions](../DECISIONS.md)

# Effect-Tracked Builtins — Design Rationale

The gap: the compiler had free functions with side effects and an empty effect row (`read_file`, `write_file`, `shell_exec`, `exit`, `time_ms`, `process_run`, the `unix_socket_*` family and others). A function with no `!` could call them, so the §4.1 claim "a function with no `!` cannot perform side effects; the compiler proves it" was false. The spec text never defined these functions; they lived only in the compiler and in the generated `llms-full.md`.

Facts the moderator gave the panel during the debate, labelled F9 and F10 in the messages below: (F9) `time_ms` reads the monotonic clock, while `time.read()` and `Instant` read the wall clock; (F10) the runtime listen call for Unix-domain sockets removed an existing file at the path before it bound the socket.

The panel quotes below use `ghmenw`, a local tracker ID. It names the compiler bug "E0500 UndeclaredEffect has no emit site; effect propagation is unenforced": the check that a caller declares each effect of its callees. Q10 decides whether that check must work before the migration.

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in independent-proposal → debate (two rounds) → vote rounds.

#### Phase A — Independent proposals

- **Systems:**

> My position: every builtin in F4 that does a syscall becomes a handle op, and the free-function form goes away. The question I care about is what this compiles to. If the root handler lowers to the same C runtime call we emit now, the effect system costs nothing at runtime. In exchange, every syscall becomes visible in a signature. That is exactly what effects are for.

- **Web/Scripting:**

> My view: the free builtins are the API a Python or JS developer finds first. That makes them a trap. Someone writes `read_file(p)` in a pure helper, it compiles, and they conclude that Blink's effect rows are decoration. That costs us more Stack Overflow questions than any migration will. Principle 5 says "Period", and §4.4 says "no free functions for IO". The spec is right and the builtins are wrong. Remove them all, and give each one a single obvious replacement on a handle.

- **PLT:**

> The ticket lists symptoms. The real problem is that the §4.1 theorem ("a fn with no `!` cannot perform side effects; the compiler proves it") is false today. The proof is by induction over call trees. F3 shows the inductive step already works: fn-to-fn propagation is enforced. The base case is broken, because some leaves (compiler-known names) carry an empty row and still have effects. So the fix belongs at the leaves, as a rule.

- **DevOps/Tooling:**

> I judge each option by what the user sees: the error message, the fix-it, what the LSP can complete, and whether `blink migrate` can do the work. Here F3 is the real problem. A program with a hidden effect compiles clean, so it produces no diagnostic at all. A spec that tools cannot check does not hold.

- **AI/ML:**

> Problems for a model come from one thing above all: **two ways to do the same job**. Today `read_file(p)` and `fs.read(p)?` both exist. The free form is shorter, needs no signature change, and has the most training data. The corpus has `write_file` ×1410 and `shell_exec` ×1922 in tests/, plus 127 / 45 in src/. Our repo is future training data (CLAUDE.md), so every free-form call teaches the next model to bypass §4.4. A deprecation period makes this worse, because it doubles the corpus surface. Any fix must end with **zero free forms in src/, lib/std, tests/ and llms-full.md**.

- **Minimalism:**

> My view: this ticket asks to remove things, and removing is rare enough that we should take it. Today Blink has two ways to do IO: the handle ops in the spec, and free functions that exist only in the compiler and in llms-full.md (F1). The spec already says the handle is "the only way" (F2). So I count no new feature here. We delete a second surface the spec never approved, and add as little as possible in its place.

#### Phase B — Debate highlights

Each panelist's own summary of their position at the end of each round, verbatim:

**Round 1**

- **Systems:** sys msg (B1): V3 -> V3d (wait + signal both handle ops); V8 -> V8c on condition the spec names the clock. New fact for V5: runtime unix listen calls unlink(path) before bind, so today it deletes a file at any path the caller passes, with no FS.Delete. Position: listen must not unlink; row is Net.Listen, FS.Write. STABLE, ready to vote
- **Web/Scripting:** web msg (B1): withdraw V1b, take V1c with std wrapper -> Result[Bool, FsError]. V2c (§2.13 keyword defaults exist). Withdraw V3b, take V3d, type named Child. C7: accept to_unix_ms. Hold V4a, V5a (Net.Listen alone), V6a (soft). V7: V7a rule + V7b sentence, drop two-tier criterion. V8c. V9: ghmenw blocks removal step 3 only. STABLE, ready to vote
- **PLT:** plt msg (B1): V8: time_ms is CLOCK_MONOTONIC (bootstrap/runtime_core.h:4191) but Instant is wall-clock, so C7 1:1 swap changes semantics; propose time.monotonic() -> Monotonic (distinct type). V3: switch to V3d (handler coherence + §4.1 rule out effect-free child.wait()). V5: reject V5a for same coherence reason. Side finding: UDP recv_from in §4.4.6 has no row. NOT STABLE: V3, V8
- **DevOps/Tooling:** devops msg (B1): now back V2c (keyword `-- stdin: Option[Str] = None`) and V3d (wait/signal as handle ops; a mock handler must own spawn, wait and signal). Withdraw free-forms-get-rows intermediate step. STABLE, ready to vote
- **AI/ML:** aiml msg (B1): V2->V2c (§4.4.6 + §9.1 already use keyword defaults), V3->V3d (mocked spawn needs wait as op), V5->V5b (UDP precedent). Withdraw V8b, back V8a (changes C7). NOT STABLE: V8 (Instant clock decides C7 mapping).
- **Minimalism:** min msg (B1): moved to V1a, V2c, V3c, V6b, V7a. V4c (V4a ok), V5c (V5b ok), V8c clocks follow-up, ghmenw before removal step. NOT STABLE: V3. wait must carry a row (V3c); V3a capability-by-possession lets a pure fn block on and reap children, reopening the §4.1 hole.

**Round 2**

- **Systems:** sys msg (B2): V8 to plt's V8d (time.monotonic() -> Monotonic, distinct type; time.read() stays wall clock; C7 splits by use), because F9 shows time_ms is monotonic. V3 merge: wait and signal are ops in effect Process, callable as child.wait() as well as process.wait(child), following the serve precedent at §4.4.2 lines 461/488/704. Should meet min's and plt's requirements. V5 to V5b, hard condition listen never unlinks; row then Net.Listen alone. V9: ghmenw before step 2. STABLE, ready to vote
- **Web/Scripting:** web msg (B2): V1: move to V1a; condition: §4.4.5 shows the not_found() match on fs.stat as the existence check. V2: V2c typed `-- stdin: Option[Str] = None`. V3: propose V3e, merge of V3c and V3d: wait/signal declared as Process handle ops, callable as child.wait(); §4.4.2 already does this with `fn serve(server: Server)` called as server.serve(). Fallback V3d. Put V3e on the ballot. V4: V4a. V5: move to V5b (V5a second). Listen must not unlink (F10): returns Err, caller uses fs.delete. Row Net.Listen alone. V6: move to V6b with devops's conditions. V7: PLT's three rules. V8: V8d in scope; F9 shows time_ms monotonic, 1:1 swap is a regression. V9: ghmenw blocks step 2. STABLE, ready to vote
- **PLT:** plt msg (B2): V8: F9 makes V8c premise false ("time_ms is wall today"), hold V8d: time.monotonic() -> Monotonic. List V8d on the ballot. V3: V3d normative; method sugar (child.wait() as process.wait(child)) is a separate ticket, offered to min as a merge. V5: after F10, no unlink, row Net.Listen, FS.Write. V2: Option[Str] = None. STABLE, ready to vote
- **DevOps/Tooling:** devops msg (B2): corrects B1 claim: F9 shows C7 swap not 1:1. V8 to plt's V8d (time.monotonic() -> Monotonic; time.read stays wall clock). V5 to V5b, no unlink on listen, row Net.Listen, FS.Write held lightly. V6 to V6b with structured fix.edits. V3: merge V3c and V3d: wait/signal are Process ops that carry rows and dispatch through the handler, callable as child.wait() only as far as the §4.4.2 server.serve() precedent allows. V9: ghmenw before step 2. STABLE, ready to vote
- **AI/ML:** aiml msg (B2): V8 -> plt's V8d: time.monotonic() -> Monotonic for elapsed time, time.read() stays wall clock. F9 shows time_ms is monotonic today, so the C7 swap min and devops back changes semantics. V3: V3d, process.wait(child) as the one call spelling. V5: V5b, Net.Listen alone, listen must not unlink (F10). V2: `-- stdin: Option[Str] = None`. V6: V6b with devops's two conditions. V7: plt's three-rule text. STABLE, ready to vote.
- **Minimalism:** min msg (B2): V3 back to V3d (handler coherence; Child). V2c typed `-- stdin: Option[Str] = None`. V4 conceded to V4a. V5: V5c, then V5b, reject V5a; listen must not unlink; row Net.Listen alone. V6b with permanent fix-it table and fix.edits. V7: plt's three rules plus §4.10 sentence. V8: corrects round-1 claim (F9: time_ms is monotonic), moves to plt's V8d (time.monotonic() -> Monotonic). V9: ghmenw blocks step 2. STABLE, ready to vote

Key position shifts, verbatim:

- **PLT:**

> The argument I use most often below is **handler coherence**. When an op consumes a value that a handle op made, the same handler must answer that op. If it does not, a mock handler returns a value that the real runtime then gets. One handler gives you "fake" and a different one gives you "real", and the composition is ill-typed in the semantic sense.

- **PLT:**

> **Against my own V3c (methods with rows).** The row would be sound, but it breaks handler coherence. Under `with mock_process`, `process.spawn` returns a fake `Child`, and then `child.wait()` goes to the real runtime with a slot that the runtime never allocated. `wait` and `signal` must dispatch through the handler that made the `Child`. Only handle ops do that.

- **Systems:**

> A new fact made me change. C3 makes `FileInfo.mtime` an `Instant`, and `std.time.Instant` is epoch-based. So `Instant` must be the wall clock, or `mtime` cannot be one. My S2 ("make `time.read()` monotonic") would break C3. I withdraw it.

- **PLT:**

> `blink_time_ms` uses **CLOCK_MONOTONIC** (bootstrap/runtime_core.h:4191), and the src call sites measure elapsed phases (src/blinkc_main.bl:101+). `Instant` is a wall-clock type in the spec: it has `from_epoch_secs` and RFC 9557 UTC `Display` (§3.2.3). So `time.read().to_unix_ms()` changes the semantics. Sys is right that this cannot be a 1:1 swap.

- **PLT:**

> But I reject V8a. Making `time.read()` monotonic while `Instant` keeps an epoch and a UTC `Display` makes the type lie, and it breaks `mock_clock(Instant.from_epoch_secs(...))` in §6 and §4.10.

- **Minimalism:**

> V5b (the UDP precedent) is coherent under plt's rule 3, because a std fn made the value, not a handle op. It is honestly second-tier: a sandbox can deny it but cannot mock it. I accept it if the panel wants user surface now.

- **Minimalism:**

> Rule 3 is the minimal statement of what decided V3, and it decides V5 the same way, so it earns its place. Web wants no two-tier text. But §4.4.6 *is* a second tier today, and a spec that does not say so is false on the day it ships. One sentence in §4.10 ("second-tier functions are gated by capability, not virtualized by handlers") is cheaper than a reader finding that out alone. Also file plt's finding: §4.4.6 `recv_from`/`close`/`set_timeout` have no row, which breaks rule 2. That is a separate ticket.

- **DevOps/Tooling:**

> Row: I move to `Net.Listen, FS.Write` for `unix_listen`, and `Net.Connect` alone for `unix_connect`. bind creates a node in the filesystem, and a sandbox that denies `FS.Write` should not see new files appear. The tooling cost is zero: the row fix-it inserts both effects in one edit. I hold this lightly and will accept `Net.Listen` alone if the vote goes that way.

- **AI/ML:**

> I accept V3c only if it is pure call sugar for the same handler-dispatched op, as `server.serve()` is in §4.4.2. Under that reading V3c and V3d have the same semantics, and the vote is only about spelling. Two spellings for one op are a decision point, so I vote V3d.

#### Phase C — Final vote

The ballot. Every option came from a panelist's Phase A or Phase B text; the labels (V1a, V3d, ...) are the ones in the messages above.

##### Q1. Core change
- A: Remove the effectful free builtins outright via the 3-step bootstrap, no alias (C1), and map them as C2-C6 (fs.* ops, fs.stat, env.exit/env.args/env.pid, process.run("sh", ["-c", cmd]), §4.4.x Process ops with ProcessError {op, cmd, code: Errno}, non-zero exit is data). The time_ms mapping is decided in Q9, not by C7.
- B: Reject; keep the free builtins.

##### Q2. "Does it exist?" (V1)
- V1a: fs.stat only; existence is a not_found() match / is_ok() on fs.stat, shown in §4.4.5.
- V1b: fs.stat plus a handle op fs.exists(path) -> Result[Bool, FsError].
- V1c: fs.stat plus a std wrapper (not a handle op) that calls fs.stat; web's form returns Result[Bool, FsError].

##### Q3. stdin to a child (V2)
- V2a: a second op (run_with_stdin / run_input).
- V2b: one op with a positional Option[Str].
- V2c-Str: one op, keyword `-- stdin: Str = ""`.
- V2c-Opt: one op, keyword `-- stdin: Option[Str] = None`.

##### Q4. wait and signal (V3)
Q4a. Shape:
- V3a: wait is a method needing no effect; signal is a handle op.
- V3c: methods that carry rows, not handle ops.
- V3d: handle ops `process.wait(child) ! Process.Spawn`, `process.signal(child, sig) ! Process.Signal`. The spec writes only the process.wait(child) form; whether method-call sugar (child.wait()) applies to ops in general is a separate ticket.
- V3e: the same handle ops as V3d, and the spec also lets callers write child.wait() / child.signal(sig) for the same op, citing §4.4.2 serve (server.serve() and net.serve(server)).
Q4b. Name of the value type: `Child` or `Pid`.

##### Q5. process_exec (V4)
- V4a: `process.exec(cmd, args) -> Result[Never, ProcessError] ! Process.Spawn, Env.Exit`.
- V4b: `process.exec(cmd, args) -> ProcessError ! Process.Spawn`.
- V4c: not spec surface; compiler-private @ffi decl with an audited row.

##### Q6. Unix-domain sockets (V5)
Q6a. Surface:
- V5a: net handle ops (unix_listen / unix_connect); PLT's condition for accepting it: the stream read/write/close are also net handle ops.
- V5b: std functions and methods with rows, following §4.4.6 UDP.
- V5c: not spec surface; compiler-private @ffi decls with audited rows.
Q6b. Listen row: `Net.Listen` alone, or `Net.Listen, FS.Write`.
Q6c. Listen must not unlink an existing path; it returns Err and the caller uses fs.delete under FS.Delete: Yes / No.

##### Q7. A call to a removed name (V6)
- V6a: a new dedicated, permanent RemovedBuiltin error code.
- V6b: the existing unknown-function error, plus a fix-it from a permanent table of removed names with machine-applicable fix.edits; it fires only when lookup fails, so a user's own `fn read_file` still compiles.
- V6c: a help line on the existing unknown-name error (wording not normative).

##### Q8. Normative rule text (V7)
- V7a: PLT Phase A: the sound-upper-bound rule, plus the two-tier criterion, plus a §4.10 sentence.
- V7b: Min Phase A: "No compiler-known free function may perform a side effect. Every side effect is a handle op on an effect from §4.3. The spec adds no new effect."
- V7m: V7a's sound-upper-bound rule plus V7b's first sentence; no two-tier criterion.
- V7r: PLT B1 three rules: (1) no compiler-known free function performs a side effect; (2) every stdlib function and method's declared row is a sound upper bound on its observable effects; an empty row means pure or divergent with result type Never; (3) an operation that consumes a value made by a handle op is a handle op of the same effect.
- V7r+: V7r plus a §4.10 sentence that second-tier (UDP-style) functions are gated by capability and can be denied by a sandbox, but are not virtualized by handlers.

##### Q9. Clocks (V8; fact F9: time_ms is CLOCK_MONOTONIC, time.read()/Instant is CLOCK_REALTIME)
- V8a: time.read() becomes monotonic; add time.wall() for wall-clock.
- V8c: out of scope; time_ms -> time.read().to_unix_ms() now; a monotonic op later.
- V8d: add `time.monotonic() -> Monotonic ! Time.Read` now (Monotonic opaque, only `.since(earlier) -> Duration`); the spec states time.read() is the wall clock; elapsed-time time_ms sites go to time.monotonic(), timestamp sites to time.read().to_unix_ms().

##### Q10. Ordering with ghmenw (V9; implementation ticket ordering)
- G2: ghmenw must land before step 2 (migration).
- G3: ghmenw must land before step 3 (removal) only.
- G0: ghmenw does not block any step.

**Tally**

| Q | sys | web | plt | devops | aiml | min | Result |
|---|---|---|---|---|---|---|---|
| Q1 core | A | A | A | A | A | A | A 6-0 |
| Q2 exists | V1a | V1a | V1a | V1a | V1a | V1a | V1a 6-0 |
| Q3 stdin | V2c-Opt x6 | | | | | | V2c-Opt 6-0 |
| Q4a wait/signal | V3e | V3e | V3d | V3d | V3d | V3d | V3d 4-2 |
| Q4b type | Child x6 | | | | | | Child 6-0 |
| Q5 exec | V4a x6 | | | | | | V4a 6-0 |
| Q6a unix surface | V5b | V5b | V5b | V5b | V5b | V5c | V5b 5-1 |
| Q6b listen row | NL | NL | NL+FW | NL+FW | NL | NL | Net.Listen alone 4-2 |
| Q6c no unlink | Yes x6 | | | | | | Yes 6-0 |
| Q7 removed names | V6b x6 | | | | | | V6b 6-0 |
| Q8 rule text | V7r+ x6 | | | | | | V7r+ 6-0 |
| Q9 clocks | V8d x6 | | | | | | V8d 6-0 |
| Q10 ghmenw | G2 x6 | | | | | | G2 6-0 |

The user approved the tally and read the two 4-2 results (Q4a, Q6b) as soft consensus, with no Phase D round: the majority Concern fields take up the dissent as follow-up work.

Each panelist's ballot, verbatim:

##### Systems

> ## Q1. Core change — A
> Under the default handler, each handle op lowers to the same runtime call as today's builtin, so the effect system costs nothing at runtime and every syscall shows in a signature. Keeping the free forms keeps a base-case hole in §4.1 and a second surface that handlers cannot intercept.
> Concern: helper fns across src and tests gain rows in large numbers, and the 3-step bootstrap is long enough for someone to stop at step 2 "for now".
>
> ## Q2. Exists — V1a
> One `stat(2)`, one op, one answer. A second op puts a consistency law on every mock that the type system cannot check, and it invites the TOCTOU pattern `if exists { read }`.
> Concern: people write `fs.stat(p).is_ok()`, which treats EACCES as "absent". §4.4.5 should show the `not_found()` match as the correct form.
>
> ## Q3. stdin — V2c-Opt
> One op and no noise at call sites. `None` means the null device and no pipe; `Some(s)` means a pipe and a writer. `""` makes every call pay for a pipe and gives a sentinel. The spec must say that `None` is the null device, never a closed fd 0.
> Concern: if V2c-Str wins, the runtime will likely special-case `""` to skip the pipe, and that makes a deliberate empty input impossible to express.
>
> ## Q4a. wait/signal — V3e
> The semantics are V3d: both are ops in `effect Process`, so the handler that made the `Child` answers them and a fn with no `!` cannot block, reap or signal. Method syntax adds nothing new, because §4.4.2 already calls the `serve` op both ways. Writing only the `process.wait(child)` form would make the spec less consistent with its own `serve` example.
> Concern: if the method form is allowed here but the general rule for method sugar on ops stays unwritten, implementers will guess. Someone should file the general rule as its own ticket either way.
>
> ## Q4b. Type name — Child
> The value is a runtime slot, not an OS pid. `env.pid()` returns a real pid as `Int`, and naming both "pid" invites passing one where the other is wanted.
> Concern: none worth a line. std.process renames `Pid`; pre-1.0 (D9).
>
> ## Q5. exec — V4a
> Replacing the process image ends the program, so the op needs `Env.Exit`. `Result[Never, E]` composes with `?`, and the checker sees the code after it as unreachable. A user-facing CLI wrapper needs exec, and an audited `@ffi` for it pushes people into the trust escape hatch for an ordinary task.
> Concern: on platforms with no exec (Windows), the spec must say that the op returns `Err`. It must not emulate exec with spawn+wait+exit, because that changes the pid and signal behaviour.
>
> ## Q6a. Unix sockets — V5b
> This follows the UDP precedent in §4.4.6: tracked by rows, with no handler-coherence gap, because there is no handle op that makes a stream the methods cannot serve. V5a is sound only with a full stream-op design, and nobody asked for that.
> Concern: sandboxes can deny these functions but cannot virtualize them, so testing the daemon client needs a real socket path.
>
> ## Q6b. Listen row — Net.Listen alone
> Once listen cannot unlink (Q6c), what remains is the creation of a new node, which fails if the path exists. That is part of binding a socket, so it belongs to the Net authority domain.
> Concern: a plugin with only `Net.Listen` can still create socket nodes in any directory it can write to. That is small, but a sandbox author should know it.
>
> ## Q6c. No unlink — Yes
> F10: today, "listen" deletes any file at the given path under a row that does not include FS.Delete. That violates the sound-upper-bound rule. A stale socket is removed with an explicit `fs.delete`, so the authority shows at the call site.
> Concern: the compiler daemon must handle EADDRINUSE on restart with an explicit stale-socket check, or it fails to start after a crash.
>
> ## Q7. Removed names — V6b
> Unknown-name error, plus a machine-applicable fix-it from a closed table. It reserves no names (a user's `fn read_file` still compiles), and it costs nothing at runtime or in the catalog.
> Concern: the fix-it table must stay in sync with the replacement signatures. If an op signature changes later, a stale table edit produces code that does not compile.
>
> ## Q8. Rule text — V7r+
> Rule 2 is the base case that makes §4.1 a theorem. Rule 3 (coherence) is what V3 and V5 rest on. Since Q6 puts Unix sockets in the second tier, the spec must say honestly in §4.10 that the second tier can be denied but not virtualized.
> Concern: rule 2 also condemns the rows missing from UDP `recv_from`/`local_addr`/`set_timeout`/`close` (§4.4.6). That needs its own ticket, or the spec contradicts itself on the day it ships.
>
> ## Q9. Clocks — V8d
> F9 shows `time_ms` is monotonic, so the C7 swap would move every elapsed-time site to a wall clock that NTP can step backwards. A distinct opaque `Monotonic` type makes it a type error to mix the two clocks, and `Instant` stays wall clock for `mtime` and the epoch APIs. It is one extra op under `Time.Read` and no new effect.
> Concern: a migration that classifies a site wrongly (timestamp vs elapsed) compiles fine. Each of the ~45 `time_ms` sites needs a manual check, not a sed.
>
> ## Q10. ghmenw — G2
> The migration finds missing rows only through checker errors. Without enforcement, step 2 writes wrong rows silently, and the corpus learns them.
> Concern: ghmenw may be larger than it looks and stall this ticket. That is still better than migrating twice.

##### Web/Scripting

> ## Q1. Core change: **A**
> A Python or JS developer finds the free builtins first, and they teach that effect rows are decoration. Removing them leaves one way to do each thing, and typing `fs.` lists the whole surface. D9 means we owe no compatibility, and the targeted fix-it covers the migration.
> Concern: the migration is large (about 4,000 test sites), and a sloppy codemod could leave tests that compile but test less than before.
>
> ## Q2. Exists: **V1a**
> One op means mocks cannot disagree with themselves, and `fs.stat` costs one syscall. My DX worry was the existence check, and a named §4.4.5 example of the `not_found()` match covers it.
> Concern: if §4.4.5 shows `fs.stat(p).is_ok()` rather than the `not_found()` match, people copy it and EACCES reads as "absent".
>
> ## Q3. stdin: **V2c-Opt**
> The common call is `process.run(cmd, args)` with no noise, which matches Python's `subprocess.run(args, input=...)`. `None` means the child gets no pipe, as today, so `""` never acts as a sentinel.
> Concern: whether the `None` default counts as a legal const default on an effect-op parameter must be stated in the same spec edit, or the first implementer will trip on it.
>
> ## Q4a. wait/signal: **V3e**
> These are handle ops, so the handler that made the `Child` answers them and mocks stay coherent. They carry rows, so the §4.1 hole stays closed. `child.wait()` is what every Rust, Node and Python developer writes, and the spec already teaches the same pattern with `server.serve()`.
> Concern: if method-call sugar on ops is not stated as a general rule, `child.wait()` becomes a one-off that users try on other ops and find does not work.
>
> ## Q4b. Type name: **Child**
> `Pid` reads as an OS integer, and `env.pid() -> Int` sits right next to it. `Child` matches Rust, Node (`ChildProcess`) and Python's mental model.
> Concern: none of substance. Rename `std.process.Pid` in the migration and leave no alias.
>
> ## Q5. exec: **V4a**
> `process.exec(cmd, args)?` composes and has type `Never`. CLI shims and launchers need exec, so a private `@ffi` would only push users to write their own. It needs `Env.Exit` because exec ends the program.
> Concern: users may not expect a call that can end the program to need `Env.Exit` as well as `Process.Spawn`, so the diagnostic must name both effects.
>
> ## Q6a. Unix sockets: **V5b**
> It uses the same pattern as UDP (§4.4.6), so users learn one socket pattern. It is coherent because no handler fakes the value. Docker, systemd and LSP clients are real user needs, so V5c (compiler-private) is wrong.
> Concern: a sandbox can deny Unix sockets but cannot mock them, and users who write tests for daemon clients will ask why `net.*` mocks do not cover them.
>
> ## Q6b. Listen row: **Net.Listen alone**
> Users think "I'm opening a socket". The socket inode holds no user data, and with the unlink gone (Q6c) no hidden file deletion remains.
> Concern: a sandbox that grants `Net.Listen` but denies `FS.Write` still lets code create socket files in any writable directory.
>
> ## Q6c. No unlink: **Yes**
> Node and Python already fail with EADDRINUSE on a stale socket, and "delete it first" is the known fix. With an explicit `fs.delete` under `FS.Delete`, the deletion shows in the row.
> Concern: daemons that restart after a crash will hit EADDRINUSE until their authors add the `fs.delete` step. Put that pattern in the spec example.
>
> ## Q7. Removed names: **V6b**
> The fix-it text is what users and models need, not a code number. It fires only when lookup fails, so a user's own `fn read_file` still works and D5 stays closed. The machine-applicable edits let `blink migrate` and the LSP do the work.
> Concern: if the removed-name table is ever pruned as "dead code", old snippets drop to a bare unknown-function error, so the table must be marked permanent.
>
> ## Q8. Rule text: **V7r+**
> Rules 1 and 2 make §4.1 a theorem. Rule 3 is the coherence rule that Q4 depends on. With V5b we use the UDP-style second tier ourselves, so the spec must state honestly that handlers do not virtualize it.
> Concern: the two tiers are one more thing to teach. The spec needs a short table showing which surface is which, so users do not have to guess.
>
> ## Q9. Clocks: **V8d**
> F9 shows `time_ms` is monotonic today, so moving it to `time.read()` would quietly regress every elapsed-time site to a wall clock. `time.monotonic()` is the same name Python uses, and it needs no teaching. `Instant` keeps its wall-clock meaning.
> Concern: models and users will still write `time.read()` for elapsed timing out of habit. A lint for subtracting `Instant`s to measure elapsed time would help.
>
> ## Q10. ghmenw ordering: **G2**
> The migration relies on the checker to find which helpers need rows. With handle ops unenforced, step 2 writes signatures with missing rows and nothing reports them.
> Concern: ghmenw may slip and stall this ticket, which tempts someone to start the migration anyway. Block it with a `br` dependency.

##### PLT

> ## Q1. Core change — **A**
> Reasoning: the §4.1 theorem is proved by induction over call trees. Fn-to-fn propagation already holds (F3), so the only broken part is the base case: compiler-known leaves with an empty row that still have effects. Removing those leaves restores the theorem. Keeping them with rows would close the row hole but bypass handlers, so handler substitution (§4.7) would still fail.
> Concern: the migration may type helpers with rows that are too wide (`! FS` where `! FS.Read` would do), or with `! _`. The program is then sound but loses precision, so the review must check that rows are minimal.
>
> ## Q2. Exists — **V1a**
> Reasoning: one op means handler authors carry no law. With `fs.exists` and `fs.stat` both as ops, every mock must keep them consistent, and the type system cannot check that.
> Concern: users write `fs.stat(p).is_ok()`, which treats EACCES as "absent". So §4.4.5 must show the `not_found()` match as the official idiom.
>
> ## Q3. stdin — **V2c-Opt**
> Reasoning: an empty pipe and a closed fd 0 are observably different to the child (`fstat`, `isatty`, fd reuse). `Option[Str]` is the exact type, and `Str` collapses two values into one. The default `None` keeps every migrated call a pure rename.
> Concern: the spec must state that keyword defaults are legal on effect-op parameters, and how a handler implements an op whose call site has defaults. The default belongs to the call surface, and the handler sees the full arity.
>
> ## Q4a. wait/signal — **V3d**
> Reasoning: an op that consumes a value made by a handle op must dispatch to the same handler. If it does not, a mock-spawned `Child` goes to the real runtime. A `wait` with no row also falsifies §4.1. Method sugar is a general question, not one to answer only for `process`.
> Concern: the §4.4.2 `server.serve()` / `net.serve(server)` inconsistency stays unresolved until the sugar ticket lands, and examples may copy whichever form they see first.
>
> ## Q4b. Type name — **Child**
> Reasoning: `env.pid()` returns an OS pid as an `Int`. A type also named `Pid`, which is an opaque runtime slot, invites confusing the two kinds of value.
> Concern: none of substance. The `std.process.Pid` rename must happen in the same bootstrap step.
>
> ## Q5. exec — **V4a**
> Reasoning: `Result[Never, E]` is isomorphic to `E` but composes with `?`, so the checker sees the code after the call as dead. Exec ends the program image, so the row must contain `Env.Exit`, or the Env.Exit gate can be bypassed.
> Concern: mock handlers must give an `exec` that never returns `Ok`. The type guarantees this, but a handler author may not see why their mock cannot "succeed".
>
> ## Q6a. Unix sockets — **V5b**
> Reasoning: this follows the existing §4.4.6 UDP precedent, and it is sound under rule 2 as long as every stream method carries a row. V5a is equally sound only if the stream read/write/close are also `net` handle ops. That is a larger design than this ticket needs.
> Concern: the stream methods may copy UDP's gap and ship with no row on read or close. Every method must carry its row.
>
> ## Q6b. Listen row — **Net.Listen, FS.Write**
> Reasoning: binding creates a filesystem node that `fs.list_dir` can see, and it can squat a path that another service expects. Under rule 2, the row must name that effect, and a sandbox that denies FS.Write expects no new entries.
> Concern: other seats will read this as noise in diagnostics. But the alternative quietly weakens attenuation.
>
> ## Q6c. No unlink — **Yes**
> Reasoning: an unchecked `unlink` inside listen is a hidden FS.Delete, which is exactly the bug class this ticket removes (F10).
> Concern: existing callers that relied on clearing a stale socket must add `fs.delete` and `FS.Delete` explicitly. That is correct, but it adds migration work.
>
> ## Q7. Removed names — **V6b**
> Reasoning: it reserves no names, so a user's own `fn read_file` still compiles, which respects D5's closed name set. The fix-it carries all the information a dedicated code would.
> Concern: the permanent table could drift into acting as a second resolver. It must fire only after name lookup has failed.
>
> ## Q8. Rule text — **V7r+**
> Reasoning: rule 2 is the base case the §4.1 theorem needs. Rule 3 states the coherence argument that four seats reached on their own in V3. The §4.10 sentence states honestly what the UDP tier already gives: a sandbox can deny it but cannot virtualize it.
> Concern: rule 3 needs a precise test for "a value made by a handle op". The spec text should name it as "a value whose type a handle op returns and whose meaning depends on the handler that made it".
>
> ## Q9. Clocks — **V8d**
> Reasoning: F9 shows `time_ms` is monotonic. So the V8c swap changes what elapsed-time sites mean, and an NTP step can make a duration negative. V8a would make `Instant` lie: it has an epoch, a UTC `Display`, and `FileInfo.mtime` is an `Instant`. A distinct `Monotonic` type keeps the two clocks apart in the types.
> Concern: if V8c wins, the record must state that the elapsed-time sites regress to the wall clock until a follow-up lands.
>
> ## Q10. ghmenw — **G2**
> Reasoning: the migration is driven by the checker, which finds the helpers that need rows. With handle ops unenforced, step 2 writes handle calls under rows that are wrong or missing, and the corpus teaches those signatures.
> Concern: if ghmenw slips, this ticket stalls behind it. G3 is the acceptable fallback.

##### DevOps/Tooling

> ## Q1. Core change
> Vote: **A**
> Reasoning: Today a hidden effect compiles clean, so tools have nothing to report. Removing the free forms makes E0500 and its row fix-it the single path, which the LSP and `blink migrate` can drive to a fixpoint. Completion on `fs.`, `process.` and `env.` then shows the capability model directly.
> Concern: about 4,000 test sites and about 600 src sites will be migrated by a codemod, and any codemod bug will reach many files at once. Run it per directory, with a gate after each.
>
> ## Q2. Exists
> Vote: **V1a**
> Reasoning: Each extra op is one more method that every mock `fs` handler must implement, and `fs.exists` invites check-then-act. `fs.stat` plus `e.not_found()` is one call and easy to suggest in a fix-it.
> Concern: users will ask for `exists` within a week. The §4.4.5 example must show the idiom prominently, or agents will invent a wrapper.
>
> ## Q3. stdin
> Vote: **V2c-Opt**
> Reasoning: about 750 `process_run` sites migrate as a pure rename, which is a machine-applicable fix with no inserted `None`. `Option[Str]` keeps "inherit stdin" apart from "empty stdin", and a `""` default would merge them.
> Concern: the spec must state that effect-op params may take `--` keyword defaults. If it does not, the op signature is valid in no section.
>
> ## Q4a. wait / signal
> Vote: **V3d**
> Reasoning: one handler must own spawn, wait and signal, or a mock's fake child reaches the real runtime. That is the coherence rule. One canonical spelling, `process.wait(child)`, keeps the diagnostic, the docs and completion uniform. Whether method sugar on ops is general is a separate question, and it should not be decided as a side effect here.
> Concern: if the sugar ticket is never filed, §4.4.2 `server.serve()` remains an unexplained special case. File it.
>
> ## Q4b. Type name
> Vote: **Child**
> Reasoning: `env.pid()` returns a real OS pid as an `Int`. A type named `Pid` beside it invites passing one where the other is wanted, and hover text cannot fix that confusion.
>
> ## Q5. exec
> Vote: **V4a**
> Reasoning: `Result[Never, ProcessError]` works with `?`, and the checker then marks the code after it as dead with no special case. Under V4c every launcher or build tool written in Blink writes its own `@ffi` decl, each with a W0800 audit.
> Concern: the row `Process.Spawn, Env.Exit` must be explained in the E0500 help. Otherwise users will not see why exec needs `Env.Exit`.
>
> ## Q6a. Unix sockets surface
> Vote: **V5b**
> Reasoning: under the coherence rule, V5a is only correct if every stream op is also a `net` op, which nobody has designed. V5b follows the UDP precedent: always real, tracked by rows, found under `std.net`. V5c pushes users to write their own `@ffi`.
> Concern: V5b sockets can be denied by a sandbox but not mocked, so tests of daemons need a real socket path in a temp dir.
>
> ## Q6b. Listen row
> Vote: **Net.Listen, FS.Write**
> Reasoning: bind creates a filesystem node, and a sandbox that denies `FS.Write` should not see new files. The row fix-it inserts both effects in one edit, so this costs users nothing.
>
> ## Q6c. No unlink on listen
> Vote: **Yes**
> Reasoning: a hidden delete inside a network op is the exact class of bug this ticket removes. With EADDRINUSE as an `Err`, the user has a clear message and an explicit `fs.delete` under `FS.Delete`.
>
> ## Q7. Removed name
> Vote: **V6b**
> Reasoning: the structured `fix.edits` is the requirement; a separate code number is not. Firing only when lookup fails avoids reserving names (D5). A help line alone (V6c) cannot be applied by an agent or by `blink migrate`.
> Concern: the table must really be permanent. If someone removes it as cleanup in a year, agents trained on the old names lose their fix-it.
>
> ## Q8. Rule text
> Vote: **V7r+**
> Reasoning: rule 2 is checkable by an audit table over the closed builtin set, so this class of bug turns into an ICE in CI, not a user report. Rule 3 is the reason a mock handler that compiles is also correct. The §4.10 sentence tells sandbox authors what a second-tier function does not give them.
> Concern: rule 3 also convicts §4.4.6 UDP methods (recv_from has no row). A follow-up ticket must exist, or the spec contradicts itself on day one.
>
> ## Q9. Clocks
> Vote: **V8d**
> Reasoning: F9 shows that V8c moves monotonic measurements to the wall clock. That gives wrong numbers with no diagnostic, which is the worst outcome for tooling. With a distinct `Monotonic` type, mixing the clocks is a type error at the call site, and `time.read()` stays the wall clock that `FileInfo.mtime` and `Display` need.
> Concern: `time_ms() - t0` becomes `.since(t0)`, a shape change, so the migration fix is a suggestion, not machine-applicable. Expect manual work on about 45 sites.
>
> ## Q10. ghmenw ordering
> Vote: **G2**
> Reasoning: the migration is driven by the checker. The row fix-it loop runs on E0500 from handle ops, and without enforcement it stops at once and leaves helper fns without rows. G3 catches that only after the corpus is already migrated wrongly.
> Concern: G2 delays the migration behind an implementation bug of unknown size. Scope ghmenw before you schedule step 2.

##### AI/ML

> ## Q1. Core change
> 1. Vote: **A**
> 2. Reasoning: two surfaces for one job is the largest source of model errors, and the free forms dominate the corpus (write_file ×1410, shell_exec ×1922 in tests). Our repo is future training data. Only a full removal stops it from teaching models to bypass §4.4.
> 3. Concern: the migration of about 3600 sites may get done by a mechanical rename that adds over-wide rows (`! FS`, `! Process`) to every helper, and the corpus would then teach coarse rows.
>
> ## Q2. Exists
> 1. Vote: **V1a**
> 2. Reasoning: one op means a model makes no choice. The `e.not_found()` idiom is the one §4.4.5 already teaches for `fs.read`, so the spec gives one pattern for both. A wrapper next to a handle op brings back the free-function-beside-handle shape this ticket removes.
> 3. Concern: unless §4.4.5 shows the `not_found()` existence check as a worked example, models will write `fs.stat(p).is_ok()`, which is wrong on EACCES.
>
> ## Q3. stdin
> 1. Vote: **V2c-Opt**
> 2. Reasoning: there is one name, and the common call `process.run(cmd, args)` carries no noise. Keyword defaults are already normative, so a model learns nothing new. `Option[Str]` keeps "no pipe" and "empty pipe" apart at the cost of one `Some(...)` on the rare call.
> 3. Concern: the spec does not yet say whether effect-op params may have defaults (§4.4.6 has one on a method only). If the spec does not say so, the handler signature and the call signature may drift.
>
> ## Q4. wait and signal
> Q4a.
> 1. Vote: **V3d**
> 2. Reasoning: with the handle at the call site, a model can check rows locally, which is the §4.4 rationale. A second spelling (`child.wait()`) would add a decision point and hide the need for an effect. Handle ops also keep mocks coherent: a mock spawn is followed by a mock wait.
> 3. Concern: models trained on Rust/Node will write `child.wait()` first, so the unknown-method error needs a fix-it to `process.wait(child)`.
>
> Q4b. **Child**. `Pid` reads as an OS integer and clashes with `env.pid() -> Int`. Rust and Node both name the value for the child.
>
> ## Q5. exec
> 1. Vote: **V4a**
> 2. Reasoning: `Result[Never, E]` composes with `?` and needs no special case, which matches every other op's shape. A spec op stops compiler src (training data) from teaching that a private `@ffi` is the way around handles. The `Env.Exit` row is correct because exec ends the program.
> 3. Concern: a model will forget the `Env.Exit` row, because it reads "exec" as process work only, so the missing-effect diagnostic must name both effects.
>
> ## Q6. Unix sockets
> Q6a.
> 1. Vote: **V5b**
> 2. Reasoning: it is one socket pattern, the same as §4.4.6 UDP, so a model learns sockets once. V5a without stream ops as handle ops breaks handler coherence, and V5c puts bypass examples in the corpus.
> 3. Concern: the second tier cannot be mocked, so a test of a Unix-socket client must use a real socket. Users may find this surprising unless the spec says it (see Q8).
>
> Q6b. **Net.Listen alone.** The authority domain is "socket". A second row entry for an inode with no data is a decision point no model gets right from the name.
>
> Q6c. **Yes.** A hidden unlink is hidden FS.Delete authority, and the row must tell the truth.
>
> ## Q7. Removed names
> 1. Vote: **V6b**
> 2. Reasoning: a model fixes itself from the fix-it text and edits, not from a code number. A permanent table matters because these names will be in model output for years. Firing only when lookup fails keeps user names free (D5).
> 3. Concern: the table may be dropped later as "dead code", although it is the part that serves models trained before the cutoff the longest.
>
> ## Q8. Rule text
> 1. Vote: **V7r+**
> 2. Reasoning: rules 1-3 are the base case for §4.1 and decide V3/V5 with no special cases. Since V5b creates a second tier, the spec must say in plain text that those functions can be denied but not mocked. A model or user reading §4.10 should not have to find that out by experiment.
> 3. Concern: "second tier" is a new concept for readers, so the §4.10 sentence must give a concrete example (UDP), or it will read as abstract.
>
> ## Q9. Clocks
> 1. Vote: **V8d**
> 2. Reasoning: F9 shows that `time_ms` is monotonic, so V8c silently changes about 45 sites to wall-clock elapsed time, and the corpus would teach that bug. V8d is the Rust `Instant`/`SystemTime` split that models already know, and the types stop the two clocks from mixing.
> 3. Concern: the migration must sort each `time_ms` site into elapsed time or timestamp by hand. A careless pass that sends all sites to one target brings the bug back.
>
> ## Q10. ghmenw ordering
> 1. Vote: **G2**
> 2. Reasoning: the migration is driven by the checker. Without handle-op enforcement, migrated helpers get no rows or wrong rows, and the corpus records those wrong signatures until a second pass.
> 3. Concern: if G3 wins, step 2 must still re-run the migration check after ghmenw lands. Otherwise unenforced rows ship.

##### Minimalism

> ## Q1. Core change: **A**
> Reasoning: This change removes far more than it adds: about 22 compiler-known names go, and a few handle ops replace them. It deletes a second IO surface that the spec never defined (F1), and it makes §4.1 true. Keeping the builtins (B) keeps two ways to do one thing, and one of them is unsound.
> Concern: The ~2,700 mechanical call-site rewrites will tempt someone to add "temporary" helper wrappers in src/ or tests/, and those wrappers become a third surface.
>
> ## Q2. Exists: **V1a**
> Reasoning: One op for one syscall. Every handler must implement every op, so a second op that answers the same question costs every mock and adds a law (exists vs stat) that the type system cannot check. The `not_found()` idiom is already in §4.4.5, so we only need to show it there.
> Concern: Users will write `fs.stat(p).is_ok()` as an existence test, which says "absent" on EACCES. The §4.4.5 example must show the `not_found()` match, not `is_ok()`.
>
> ## Q3. stdin: **V2c-Opt**
> Reasoning: It uses a feature that already exists (keyword defaults), gives one op for one concept, and its type is exact. No pipe and an empty pipe differ at the syscall level, so `Str = ""` merges two states. Two ops (V2a) double the handler cost, and a positional `None` (V2b) adds noise at every call site.
> Concern: Plt asked whether effect-op params may take keyword defaults at all. If the spec does not say so, this vote quietly creates that rule, so the §4.4.x text must state it.
>
> ## Q4a. wait/signal: **V3d**
> Reasoning: Rule 3 (handler coherence) decides this. `spawn`, `wait` and `signal` are one protocol, and the handler that made the `Child` must answer all three. V3e adds method-call sugar for ops in this ticket. That is a general language rule, it is a separate question, and it should not ride in here.
> Concern: §4.4.2 already writes `server.serve()`, so the spec has the sugar in one place and not in the other. That inconsistency needs its own ticket, or readers will guess.
>
> ## Q4b. Type name: **Child**
> Reasoning: The value is an opaque runtime slot, not an OS pid. `env.pid() -> Int` returns a real pid, and a `Pid` type next to it invites mixing the two. Renaming before 1.0 costs nothing (D9).
> Concern: none of substance; std.process must rename in the migration step, not later.
>
> ## Q5. exec: **V4a**
> Reasoning: `Result[Never, ProcessError]` uses existing types to say "returns only on failure", with no special case, and `?` works on it. `Env.Exit` in the row is required, because exec ends this program. I gave up V4c: a private `@ffi` pushes each user toward their own audited escape, and that adds surface.
> Concern: The handler for exec has to make a `Never` on success, so mock-handler docs must say that a mock exec can only return `Err` or diverge.
>
> ## Q6a. Unix sockets: **V5c**
> Reasoning: Today the only user is the compiler daemon (0 call sites in lib/std). A spec'd socket API is a permanent promise, and it would arrive before the stream and file-handle design that §4.4.5 defers to post-v1. An audited `@ffi` with rows keeps every call site tracked under D8 and promises nothing.
> Concern: If V5a wins without PLT's condition (stream ops also as net handle ops), it ships the same coherence bug that V3 just rejected.
>
> ## Q6b. Listen row: **Net.Listen alone**
> Reasoning: Classify by the authority domain. The node that bind makes is the socket itself. Adding `FS.Write` puts two effects in every diagnostic for one action, and it starts the slope of one row entry per syscall side effect.
> Concern: A sandbox that denies FS.Write but allows Net.Listen still lets a process create a socket node in a writable directory. That is acceptable, but the spec must state it, not leave it implicit.
>
> ## Q6c. No unlink: **Yes**
> Reasoning: A silent `unlink(path)` is FS.Delete authority hidden in a net op (F10). Taking it out removes a hidden behaviour and keeps the row honest. A caller that wants to clear a stale socket says so with `fs.delete`.
> Concern: Existing daemon code that relies on the unlink will fail with EADDRINUSE after a crash until the migration adds the explicit `fs.delete`.
>
> ## Q7. Removed names: **V6b**
> Reasoning: The fix-it carries all the useful information: the op, the effect, and a machine-applicable edit. It adds no permanent catalog code, and it reserves no names, because it fires only when lookup fails. V6a adds a permanent code for names the spec never had.
> Concern: The "permanent table" will grow with every future removal. It needs an owner and a rule for when an entry may finally go.
>
> ## Q8. Rule text: **V7r+**
> Reasoning: Rules 1-3 are the smallest text that makes §4.1 a theorem (rule 2), closes this ticket (rule 1) and decides V3 and V5 (rule 3). My own V7b is false against §4.4.6, so I withdrew it. The §4.10 sentence describes the spec as it is. It adds no mechanism, and leaving it out makes §4.10 overclaim.
> Concern: Rule 2 makes the row-less §4.4.6 UDP methods (`recv_from`, `close`, `set_timeout`) a spec violation on the day this ships. The follow-up ticket must be filed at once.
>
> ## Q9. Clocks: **V8d**
> Reasoning: F9 shows `time_ms` is monotonic, so it is a real orphan, and V8c would silently regress about 45 elapsed-time sites. V8d is the smallest fix: one op and one opaque type with one method, no new effect, and no change to `Instant`. V8a changes an existing type and breaks `FileInfo.mtime`, `from_epoch_secs` and `mock_clock`.
> Concern: Users will ask for `Display` or arithmetic on `Monotonic`. We should hold the line at `.since()` until a concrete need shows up.
>
> ## Q10. ghmenw: **G2**
> Reasoning: The migration is checker-driven. Without handle-op enforcement, migrated helpers compile with no rows, and step 3 only renames the hole. Enforcement must be on when we migrate.
> Concern: ghmenw becomes the critical path for this ticket. If it stalls, someone will want to migrate anyway, and they should not.

### Final Spec

```blink
// §4.4 — three rules
// 1. No compiler-known free function performs a side effect.
// 2. Every stdlib function and method's row is a sound upper bound on its effects.
//    An empty row means pure, or divergent with result type Never.
// 3. An operation that consumes a value that a handle op made is a handle op of the same effect.

// §4.4.5
fs.stat(path: Str) -> Result[FileInfo, FsError]                       // ! FS.Read
pub type FileInfo {                                                   // FsOp gains Stat
    kind: FileKind
    size: Int
    mtime: Instant
}

// §4.4.3
env.pid() -> Int                                                      // ! Env.Read

// §3.2.3
time.monotonic() -> Monotonic                                         // ! Time.Read
// Monotonic: opaque, only .since(earlier: Monotonic) -> Duration; time.read() is the wall clock

// §4.4.8
process.run(cmd: Str, args: List[Str], -- stdin: Option[Str] = None) -> Result[ProcessResult, ProcessError]  // ! Process.Spawn
process.spawn(cmd: Str, args: List[Str]) -> Result[Child, ProcessError]                                    // ! Process.Spawn
process.wait(child: Child) -> Result[ProcessResult, ProcessError]                                          // ! Process.Spawn
process.exec(cmd: Str, args: List[Str]) -> Result[Never, ProcessError]                                     // ! Process.Spawn, Env.Exit
process.signal(child: Child, sig: Int) -> Result[(), ProcessError]                                         // ! Process.Signal
pub type ProcessError {
    op: ProcessOp
    cmd: Str
    code: Errno
}

// §4.4.6 (std.net, second tier)
pub fn unix_listen(path: Str) -> Result[UnixListener, NetError]       // ! Net.Listen
pub fn unix_connect(path: Str) -> Result[UnixStream, NetError]        // ! Net.Connect
```

- The effectful free builtins go away with no alias (3-step bootstrap). A call to a removed name is the existing undefined-function error with a fix from a permanent table; the table is used only when lookup fails.
- Existence is a `not_found()` match on `fs.stat`. There is no `fs.exists`.
- A non-zero exit is data in `ProcessResult.exit_code`; `Err` means the operation failed. `stdin: None` is the null device, never a closed standard input.
- `process.wait(child)` is the only spelling. Method-call sugar on handle ops is a separate question, which also covers `server.serve()` and `net.serve(server)` in §4.4.2.
- `unix_listen` needs `Net.Listen` only, never removes an existing file, and returns `Err` when the path exists. The spec states that a sandbox that denies `FS.Write` still lets code create socket nodes.
- Second-tier functions (UDP, Unix sockets) are gated by their effect but no handler can intercept them (§4.10).
- Implementation order: handle-op enforcement lands before the migration step.

**Details the moderator filled in while writing the spec text** (the ballot did not decide them; a later panel may change them): `FileKind` has the variants `File`, `Dir`, `Other`, and `fs.stat` follows symbolic links; `ProcessOp` has the variants `Run`, `Spawn`, `Wait`, `Exec`, `Signal`; `process.spawn` takes no `stdin`; `Child` has no methods; the method sets of `UnixListener` and `UnixStream`.
