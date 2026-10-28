[< All Decisions](../DECISIONS.md)

# Process Child Handle — Design Rationale

### Panel Deliberation

The ticket (verbatim from the Phase A brief):

> Title: Spec: §4.4.8 gaps: a mock Child, signal on an ended child, wait results, the spawn cap
>
> Four gaps in §4.4.8. (1) §4.4 rule 3 says a mock `process.spawn` returns a mock `Child`, but `Child` is opaque with no constructor, so a handler clause cannot make one. (2) `process.signal(child, SIGTERM)` on a child that has already ended, waited or not: `Ok(())` or `Err` ESRCH? The runtime must never signal a recycled pid. (3) May the runtime drop the result of a child that was never waited? If it does, what does a later wait give? (4) What does `process.spawn` give when the runtime's child table is full?

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated. Phase A had independent proposals. Phase B had one round. Phase C was a silent ballot. Phase D re-voted D, D.v and E, because D and E passed 4-2 in Phase C. Quoted text is each panelist's own words, taken from the panel records. A bracketed ellipsis marks a ticket reference that was cut out.

Questions:

- P: the package. **Q1-A:** a type-scoped constructor plus `Eq` and `Hash` on `Child`, no getter, the key is an `Int`. **Q1.v4:** `Child` implements `Debug`. **Q1b:** a `Child` that the built-in handler did not make gives `Err` ECHILD from `wait` and `Err` ESRCH from `signal`, with no syscall and no panic. **Q1c:** no lint. **Q2:** `signal` on an ended child gives `Ok(())`. **Q3:** the runtime never drops a `Child` result. **Q3.v1:** a second wait after a failed first wait gives the same `Err`. **Q4:** `spawn` gives `Err` EAGAIN when the runtime cap is full. **Q4.v2:** an OS failure passes its errno through. **Q4.v3:** `process.run` takes no slot.
- N: the constructor name. **N-mock:** `Child.mock`. **N-from_id:** `Child.from_id`.
- D: the `Debug` text of a real `Child`. **D-pid:** `Child(pid 4211)`. **D-nopid:** `Child(spawned)`.
- D.v: the text after a wait reaped the child. **D.v-ended:** `Child(pid 4211, ended)`. **D.v-same:** `Child(pid 4211)`, with a spec sentence that the pid may name another process.
- E: the `cmd` field of the Q1b `Err`. **E-debug:** the `Debug` text of the `Child`. **E-empty:** `""`. **E-empty+display:** `""`, and `Display` names the cause.
- R: may the runtime reap a child once no copy of its `Child` is reachable. **R-allow:** yes, and code must not depend on it. **R-forbid:** no.
- F: a number for the runtime cap. **F-floor:** the spec promises "at least 4096". **F-none:** no number.

#### Phase A — Independent proposals

- **Systems** (sys):

> - `Child.mock(id: Int) -> Child` is a pub type-scoped fn in std.process, pure (no effect row), callable from any module. This is the same door as Monotonic.from_offset. Any Int is valid; it never panics.
>
> - A mock Child that reaches the REAL runtime (it leaked out of `with mock`, or a handler forwards it to `default`) makes no syscall. Real `process.wait` gives `Err(ProcessError { op: Wait, cmd: "", code: ECHILD })`, which is what waitpid(2) gives for a pid that is not your child. Real `process.signal` gives `Err ESRCH`. It never panics, and it can never touch a real pid.
>
> - After the first successful wait (from any copy of the Child, on any thread): `Err(ProcessError { op: Signal, cmd, code: ESRCH })`, with no syscall. After the wait, the runtime holds no claim on the pid, and the OS may have given it to another process. This is the "never signal a recycled pid" rule, and it is deterministic.

- **Web/Scripting** (web):

> === W1. A handler makes a Child with `Child.from_id`, and reads it back with `id()` ===
>
> - `Child.from_id(id: Int) -> Child`: a type-scoped fn, total, never panics, no effect row.
>
> === W2. Signal on a child that already ended: Ok(()), and no signal is sent after the reap ===

- **PLT** (plt):

> A `Child` is a name for one spawn. The only thing a handler must do with that name is recognize it. So the right observer is equality, not a getter. Same torsor-style reasoning as `Monotonic`: give one pure way in and the smallest observer that makes the mock work, and no more.
>
> - `std.process` adds a pub, pure, type-scoped function `Child.mock(id: Int) -> Child`. Any code can call it (the `from_offset` precedent; §2.12 has no friend tier, and a handler can live in any module). It has no effect row: it observes and starts nothing.
>
> - `Child` implements `Eq` and `Hash`. Two `Child` values are equal when one `process.spawn` made both (copies of one Child), or when both come from `Child.mock(n)` with the same `n`. A real child never equals a mock child. No other observer: no `id()`, no `pid()`, no `Display`. (I am fine with `Debug` printing `Child(mock 3)` / `Child(spawned)` with no pid, so `assert_eq` works; minor.)

- **DevOps/Tooling** (devops):

> NEW FACT FIRST (it changes Q3). I read bootstrap/runtime_process.h. In the Child design the runtime never drops the result of a Child that nobody has waited on yet:
>
>   - `Child.mock(key: Str) -> Child`: makes a Child that has no process behind it. Any code can call it.
>
> Behavior: `process.signal(child, sig)` on a child that has ended returns `Ok(())` and sends nothing, whether or not someone has waited on it. It never returns ESRCH for an ended child.

- **AI/ML** (aiml):

> Test I apply to each part: can a model write it right first time from the spec, and does a wrong program fail at a fixed place with an error that names the fix? A result that depends on reap timing or GC timing fails both: a model cannot test it and cannot learn it.
>
> - `std.process` adds a pub, pure, type-scoped fn `Child.fake(id: Int) -> Child`. Any code can call it (same door as `Monotonic.from_offset`; §2.12 has no friend tier, and a user handler lives in any module). It starts no process and reads nothing, so it has no row.
>
> Behavior: `process.signal(child, sig)` on a real Child that has ended, waited or not, reaped by the runtime or not, returns `Ok(())` and sends nothing. The runtime never calls `kill` on a pid once it has reaped it (so never a recycled pid). `Err` stays for real failures: `EINVAL` for a bad signal number, `EPERM`, `ESRCH` for a fake Child (AIML-1).

- **Minimalism** (min):

> Proposal min-1: `Child.from_id(id: Int) -> Child`, a pub pure type-scoped fn in std.process, plus `Eq` on Child. No getter, no Debug, no Display, no other methods.
>
> NEW FACT FIRST (it shrinks Q3). The ticket's premise for Q3 comes from the old Pid table. The current runtime (bootstrap/runtime_process.h, blink_child_spawn / blink_child_wait / blink_pid_table_alloc) never reaps a child before its first wait:


#### Phase B — Debate highlights

Five seats moved to Q1-A (a constructor, `Eq` and `Hash`, no getter): sys, web, devops, aiml and min. plt had proposed it. The Phase A getters (`id()`, `mock_id`, `mock_key`) all dropped out.

- **Systems** (sys):

> Q1: I MOVE to Q1-A (constructor + Eq + Hash, no getter). plt is right that a handler needs to recognize a Child, not read it. `child == Child.mock(1)` gives the same routing power as my `Child.mock_id`, and Eq on a real Child is useful on its own (a supervisor drops the ended child from a List[Child]). Cost: Eq on a real Child compares box identity, one pointer compare. Hash needs a stable key. The Boehm GC does not move objects, so the address works today, but the spec must not promise that, so the runtime gives each spawn a serial: one atomic add per spawn, nothing next to fork. I drop Child.mock_id.
>
> Q2: I MOVE to Q2-Ok. devops and plt changed my mind. Under my rule the answer for one ended child depends on whether some OTHER copy of the Child was waited first (another thread), so the reap, an implementation event, becomes observable. "Signal on an ended child is a no-op, Ok" is one law with no race in it. It costs the same as ESRCH: the same reaped check under the same table lock, then no kill(2). It keeps the safety property that matters to me, which is no syscall on a pid after the reap. Requirement to keep in the text: the reap and the signal check take one lock (or the equivalent), so a signal never reaches a recycled pid. That is what the runtime does now. Errs that stay: EINVAL (bad number), EPERM (from kill on a live child), ESRCH only for a Child this runtime did not make (Q1b).
>
> Q4.v1: No number. A floor of "at least 4096" means nothing on a default host, where pipe() gives EMFILE at about 510 live children (2 fds each, `ulimit -n` 1024). It would also freeze a table size into the spec. If the panel wants a floor, write it as "the runtime's own cap is never the first limit on a default host", not as a number.

- **Web/Scripting** (web):

> Q1: I move from Q1-B to Q1-A, with Eq + Hash and no getter. I proposed the getter so that a mock can tell two children apart. aiml shows a better way: `Map[Child, ProcessResult]`, or `if child == Child.mock(1)`, does the same job. A JS or Python dev already keys maps by object, so it is not a new idea. min is right that a getter must also give a value for a real child, which brings in the pid question that this ticket does not need. Eq on real children also gives a supervisor `children.remove(ended)` for free. A pid getter for logging can be its own feature ticket.
>
> Q2: Ok. My reply to sys and min: the rule "ESRCH after this program's own wait" is the same on every run only in a single-task program. When one task waits and another sends SIGTERM at shutdown (copies of one Child), the result depends on which task the scheduler runs first. So the race comes back, and every shutdown needs `Err(e) if e.code == ESRCH => {}`. That is exactly the Go `errors.Is(err, os.ErrProcessDone)` boilerplate. min wants one rule for "ended" and "never yours", but those mean different things. An ended child is a normal event. A Child the runtime never made is a bug, and it should stay an error.
>
> Q4.v1: no number. sys's fact changes my view: EMFILE comes at about 510 children on a default `ulimit -n`, so "at least 4096" would mislead users.

- **PLT** (plt):

> Q1: Q1-A (constructor + Eq, no getter). The new point against web's `child.id()`: it is not injective across where a Child came from. A real child with pid 41 and `Child.from_id(41)` give the same `id()` but are different children. A mock that routes on `id()` then answers a real child that was forwarded through it as if the mock had made it. That is a real soundness hole in the routing pattern web's own example teaches. Eq has no such hole, because a made Child never equals a real one. sys's `Child.mock_id(c) -> Int?` is sound (None for a real child), so it is my second choice. It is still more surface than Eq, and it gives two ways to do one thing. devops's Str key with no Eq: a mock can route, but `List[Child]` membership, `assert_eq` and a supervisor's "remove the child that ended" all need Eq anyway. Pid logging (web's real need) belongs in Debug, not in a getter that logic can branch on.

- **DevOps/Tooling** (devops):

> Q1: I move to Q1-A: a constructor + Eq + Hash, no getter. aiml's test (`Map[Child, ProcessResult]` keyed on the Child) is the shortest correct multi-child mock, and it is one way to do it, not two. Eq also has a real use outside mocks: a supervisor removes the Child that ended from a `List[Child]`. My `mock_key` getter gave the same power through an Option that each caller must unwrap. I withdraw it.
>
> Q1.v1 name: `from_id` first, `mock` second, `fake` third. My seat's reason is the log line. min and web are right that a sandbox or ssh handler makes Childs in production. If those Childs print as `Child.mock(3)` in a prod log, an operator asks "why does prod run a mock?" and loses an hour. The pid-confusion risk that plt and aiml raise is real, but Q1b closes it on the first run: `process.wait(Child.from_id(1234))` gives an Err that names the made Child, and no pid is touched. The Debug text must make the two kinds of Child look different (Q1.v4).
>
> Q4.v1: a floor, "at least 4096 children that are spawned and not yet waited". It is a floor, not the size, so it ties the runtime to nothing more than a promise that a program can rely on. sys's "grow the table so the OS limit always fires first" is fine as an implementation, and it meets the floor. If the majority wants no number, I accept that, provided the EMFILE writer note goes in.

- **AI/ML** (aiml):

> Q1: Q1-A (constructor + Eq, no getter). Against Q1-B:

- **Minimalism** (min):

> Q1: Q1-A (constructor + Eq, no getter). Eq is the smallest observer that lets rule 3 work. Against Q1-B: web's `child.id()` gives a real Child's OS pid. That is a new feature (logging the pid) that this ticket does not need, and it puts a runtime fact into program logic. If someone wants it, it gets its own ticket. sys's `mock_id -> Int?` and devops's `mock_key -> Str?` each add a second observer plus an Option to unwrap, and Eq already does the routing.
>
> Q2: I move to Q2-Ok (Ok(()) on any ended child, whether or not it was waited; nothing is sent after the reap; ESRCH only for a foreign Child). What changed my mind: devops's point about concurrent code. With ESRCH-after-wait, a thread that signals during shutdown gets Ok or ESRCH depending on whether another thread's wait on a copy of the Child ran first. That is a race the signalling code cannot see. My Phase A claim that the result "depends only on what this program did" holds only for one thread. The two rules are the same size, so the one with no race wins. Rust 1.72 changed to Ok for the same reason. The cost to the runtime is one line, and the reap and the signal still take one lock.
>
> Q1b: Err (wait gives ECHILD, signal gives ESRCH), with no syscall on any pid. Against Panic: the op already returns Result, a foreign value is an op failure, and a panic makes it impossible to write a test that checks the real runtime rejects a foreign Child (aiml's point). cmd variation: "" (empty). `cmd` holds a command. Putting Debug text there makes the field mean two things. The message `wait : No child processes` is weak, but the docs cover it.


Position shifts and dissents after Phase B:

- Q2: min and sys moved from ESRCH-after-wait to `Ok(())`. Nobody held ESRCH.
- Q1b: devops moved from a panic to an `Err`.
- N: devops kept `Child.from_id` as first choice **(dissent)**.
- F: devops kept a floor of 4096 **(dissent)**.
- Q1.v4: aiml and min wanted no pid in `Debug` text. This split goes to the vote as D.
- Q1b `cmd`: plt and min wanted `""`. This split goes to the vote as E.

#### Phase C — Final vote

Each seat's text below is its own ballot. A block holds the seat's vote, its reasoning and its concern for one question.


**P. The package.** Tally: YES 6-0.

- **Systems** (sys):

> P. Vote: YES.
> Reasoning: Every item keeps the property that matters at the OS level. No Blink value built from plain data carries a pid, and no syscall reaches a pid after its reap, so a recycled pid is never signaled. The runtime cost is one pointer compare for Eq, one atomic serial for Hash, and the reaped check that signal already does under the table lock. Passing the errno through (Q4.v2) keeps EMFILE visible, and EMFILE is the limit that users hit first (about 510 children at `ulimit -n` 1024). Q4.v3 matches the runtime today: run reaps inline and holds no slot after it returns.
> Concern: The "one lock for the reap and the signal check" requirement must survive a later move to pidfd or to a SIGCHLD reaper, or Q2's Ok turns into a kill on a recycled pid.

- **Web/Scripting** (web):

> P. Vote: YES
> Reasoning: Each item answers the question a JS or Python dev would ask first, with the behavior they would guess. Mocks key on the Child the way JS keys a Map by object, and a cleanup that runs `signal(child, SIGTERM)?` never fails because of timing. A Child is never "lost", and spawn errors carry the errno that people already search for. Nothing in the package needs a new concept: it uses one constructor, Eq and Hash, and Errnos people know.
> Concern: Users will expect `child.pid` from every other language, and when they don't find it, they will open tickets.

- **PLT** (plt):

> P. Vote: YES.
> Reasoning: Each part makes an op total and makes its result depend only on the Child, not on reaping state, timing or the activity of other children. Eq without a getter is the smallest observer, and it is injective across provenance, so a mock can never mistake a forwarded real child for its own. A sticky failed wait makes "the second wait returns the same result" a law for both outcomes. ECHILD and ESRCH for a foreign Child make the escape case of rule 3 total, with no pid touched.
> Concern: Rule 3's "the handler that made it answers" is still only dynamic, so a Child that escapes its `with` gets an Err far from the cause, and nothing in the type system warns about it.

- **DevOps/Tooling** (devops):

> P. Package
> Vote: YES
> Reasoning: Each item gives one fixed answer at the call that caused it. A wiring bug gives a named Err. An ended child gives Ok. A failed wait gives the same Err again. A full cap gives EAGAIN at spawn, and an OS limit passes its own errno through. So the error an operator reads always points to the right fix. Q4.v2 matters most to my seat: EMFILE and EAGAIN have different fixes, so they must not share one code.
> Concern: the race-free part of Q2 (one lock for the reap and the signal, and no syscall after the reap) is the part that an implementer can silently break, so it needs a corpus test that signals after a wait under load, not only prose.

- **AI/ML** (aiml):

> P. Vote: YES.
> Reasoning: Each item gives one obvious way to write the program, and the first try a model writes is correct: `==` and `Map[Child, V]` to route in a mock, `process.signal(c, SIGTERM)?` in cleanup, `?` on spawn. A stray mock Child gives an Err a test can match, not a crash, and the OS errno passes through, so the error points at the real fix (wait on your children, or raise `ulimit -n`).
> Concern: the llms docs may show only the one-child mock, so a model's first two-child mock routes by call order and does not key on the Child.

- **Minimalism** (min):

> P. Vote: YES.
> Reasoning: The package adds one pure fn and three trait impls on Child, and no new Errno, error variant, diagnostic or lint. Every rule in it makes an existing promise total ("a wait answers once", "Err means the op failed, with its errno") and adds no new idea. Q2 removes a race that the signalling thread cannot see, and Q1b removes the only path by which a made value could reach a real pid.
> Concern: Hash on a real Child needs an identity that stays stable for the life of the value (a box address under a non-moving GC today). If the GC ever starts to move objects, someone must remember that Hash depends on that address.


**N. The constructor name.** Tally: N-mock 5-1 (devops votes N-from_id).

- **Systems** (sys):

> N. Vote: N-mock.
> Reasoning: `from_id` reads like "make a Child from a pid", which invites `Child.from_id(4211)` and the belief that it controls pid 4211. `mock` says the value is inert test data, so a call in production code stands out in review.
> Concern: Some production code (a supervisor replay, a dry-run mode) will need a fake Child and will find the name "mock" odd, but the name still tells the truth.

- **Web/Scripting** (web):

> N. Vote: N-mock
> Reasoning: The 90% case is a test, and the spec already says "mock handler", so `Child.mock(1)` reads right the first time. A name that starts with `from_` makes people and models pass a real pid to it, which leads to the question "why does wait give ECHILD?". A sandbox or ssh handler is rare, and it usually calls `default.spawn`.
> Concern: A non-test handler that builds its own Childs has to call `Child.mock`, and that reads odd in production code.

- **PLT** (plt):

> N. Vote: N-mock.
> Reasoning: The name must say at the call site that no OS process stands behind the value, so that nobody passes a pid to it. `from_id` reads like a conversion from an existing identifier, and in a process API the existing identifier is a pid. That an ssh or sandbox handler also uses `mock` is a small misnomer, and its meaning stays exact: the built-in runtime did not make this child.
> Concern: Authors of non-test handlers (ssh, sandbox) may avoid `Child.mock` because of the name and ask for a second constructor that does the same thing.

- **DevOps/Tooling** (devops):

> N. Name
> Vote: N-from_id
> Reasoning: Handlers that are not tests (a sandbox, ssh, remote exec) make Childs in production. If those Childs print as `Child.mock(3)` in a prod log, an operator chases a mock that is not there. The pid-confusion risk is closed by Q1b: `Child.from_id(1234)` never touches pid 1234 and gives an Err that names it. It is not closed by the name.
> Concern: if N-mock wins, a non-test handler has to call `Child.mock` in production code, and its Debug and Err text then says "mock" in prod logs. The writer should at least say that `mock` means "made by a handler", not "test only".

- **AI/ML** (aiml):

> N. Vote: N-mock.
> Reasoning: The name is the only signal a model gets at the call site. `from_id` reads like "adopt this id", and a model will write `Child.from_id(pid)` to wait on a process it did not start. `mock` cannot be read that way, and it names the common use.
> Concern: a non-test handler (sandbox, ssh) that builds Childs reads a little wrong, and a model may think `Child.mock` is not allowed outside a test.

- **Minimalism** (min):

> N. Vote: N-mock.
> Reasoning: §4.4 rule 3 and *Mock handlers* already say "a mock Child", so `Child.mock` adds no new word. `from_id` reads like "adopt process N", and the person or model who writes `Child.from_id(pid)` then files a bug.
> Concern: a non-test handler (sandbox, remote exec) has to call a fn named `mock`, so a reader of that code can think it is test code.


**D. Pid in the Debug text of a real Child.** Tally: D-pid 4 (sys, web, devops, plt), D-nopid 2 (aiml, min). Phase D re-voted this question.

- **Systems** (sys):

> D. Vote: D-pid.
> Reasoning: An operator who matches a log line to `ps`, `/proc/<pid>` or a core dump needs the pid. Debug text is for people, and the pid there gives no typed handle that code can feed to `libc.kill`. A run-to-run change in Debug text is normal (addresses and times change too), and tests should use Eq on the Child, not compare Debug strings of real children.
> Concern: Someone will parse the pid out of the Debug text to signal by hand, and that brings back the recycled-pid bug outside the runtime's lock.

- **Web/Scripting** (web):

> D. Vote: D-pid
> Reasoning: When a dev logs a Child or reads a failed assert, the pid is what links it to `ps` and to the system logs. No Int leaks into logic, because Debug is only text. "Child(spawned)" says nothing at the moment you need the most help.
> Concern: A test that uses `assert_eq` on Debug text of a real Child gets a different pid each run, so the writer should say that a test must not depend on it.

- **PLT** (plt):

> D. Vote: D-pid.
> Reasoning: Debug text is not an observer that the semantics rests on. It has no spec'd format, and no rule may branch on it. So a pid in it adds no power to the language and helps an operator join a log line to `ps`. The run-to-run difference matters only to code that compares Debug text of real children, and such code is already wrong.
> Concern: A golden test of a panic message or an `assert_eq` failure that holds a real Child will differ on each run, and a user will take that as a flaky compiler.

- **DevOps/Tooling** (devops):

> D. Pid in Debug
> Vote: D-pid
> Reasoning: An operator matches a log line against `ps`, `journalctl`, a core dump or a cgroup event by pid. `Child(spawned)` gives nothing to match. Debug text is for people, and the spec makes no promise about its format to a program that parses it. A pid that changes from run to run is what makes the line useful.
> Concern: tests that `assert_eq` on Debug output of a real Child become flaky. The writer should say that the Debug text of a real Child is not stable from run to run.

- **AI/ML** (aiml):

> D. Vote: D-nopid.
> Reasoning: A pid changes on every run, so `assert_eq` failures, snapshot goldens and logs from Debug differ each time, and a model cannot fix a message that differs each run. Debug output often ends up in tests, and there the pid is noise. Logging a pid is a fair need, but it belongs to an explicit getter (a separate ticket), not to Debug text.
> Concern: if D-pid wins, the writer must keep golden tests and spec examples that print a real Child from showing pid text, or they will fail at random.

- **Minimalism** (min):

> D. Vote: D-nopid.
> Reasoning: Debug text goes into assert failures, snapshots and golden logs, and a pid makes that text different on every run. A pid in the text is also the first step toward web's pid getter, which is a separate feature with its own ticket. If operators need the pid, add it on purpose with its own observer.
> Concern: if D-pid wins, people will parse the pid out of the Debug text, because no getter exists, and the Debug format then becomes ABI by accident.


**E. The cmd field of the Q1b Err.** Tally: E-debug 4 (sys, web, devops, aiml), E-empty 2 (plt, min). Phase D re-voted this question.

- **Systems** (sys):

> E. Vote: E-debug.
> Reasoning: `wait : No child processes` points an operator at a reaper bug that does not exist. `wait Child.mock(1): No child processes` names the cause: a mock value reached the real runtime. It costs nothing, because the text is built only on this error path.
> Concern: `cmd` now holds two kinds of thing (a program name, or a Child's Debug text), and code that logs `e.cmd` as a program name will print `Child.mock(1)`.

- **Web/Scripting** (web):

> E. Vote: E-debug
> Reasoning: "wait : No child processes" reads like a bug in Blink. "wait Child.mock(1): No child processes" points straight at the mock that left the `with` block. It is the same Display shape, `op cmd: message`, and the error text tells the user the fix.
> Concern: Code that matches on `e.cmd` as a program name gets Debug text for this one case, which is a small exception to "cmd is the command".

- **PLT** (plt):

> E. Vote: E-empty.
> Reasoning: `cmd` is typed as the command that the op ran. A made Child has no command that the runtime knows, so putting Debug text there gives the field two meanings, and code that reads `e.cmd` (to retry, or to group errors) gets a value that is not a command. The clearer line belongs in Display, which the writer can word from the code and the op without changing the field.
> Concern: If E-empty wins and the writer does not add a Display rule, the message reads `wait : No child processes`, which names no cause.

- **DevOps/Tooling** (devops):

> E. cmd of the Q1b Err
> Vote: E-debug
> Reasoning: `wait : No child processes` tells the reader nothing and sends them to look for a reaper bug. `wait Child.mock(1): No child processes` names the cause and the fix (add a wait clause to the mock) in one line. Every other ProcessError puts the subject of the error in cmd, so this keeps the Display convention.
> Concern: a cmd field that sometimes holds a command and sometimes a Debug text can confuse code that reads `e.cmd` as a program name. The writer should say so in one clause.

- **AI/ML** (aiml):

> E. Vote: E-debug.
> Reasoning: `wait Child.mock(1): No child processes` tells the reader that a mock Child leaked to the real runtime, and the fix is to add a `wait` clause. `wait : No child processes` has no clue in it, and reads as an OS fault. That is the operator concern that made devops ask for a panic, and E-debug answers it with no panic.
> Concern: code that matches on `e.cmd` must then handle a non-command string; the writer should say that `cmd` holds Debug text for a made Child only.

- **Minimalism** (min):

> E. Vote: E-empty.
> Reasoning: `cmd` means "the command this op ran". Debug text there makes one field mean two things, and code that matches on `e.cmd` sees a value that is not a command. The weak message is a docs problem; the llms Gotchas entry covers it.
> Concern: if E-debug wins, the writer must say that `cmd` holds Debug text only for a made Child, or a reader will think a program named "Child.mock(1)" ran.


**R. Reaping when no copy is reachable.** Tally: R-allow 6-0.

- **Systems** (sys):

> R. Vote: R-allow.
> Reasoning: Code cannot observe the reap when no copy of the Child is left, except through zombie and slot counts. Allowing it lets a GC finalizer fix the zombie leak later with no spec change. R-forbid writes the leak into the spec, and Python found long ago that the leak needs this fix.
> Concern: A finalizer reap runs on a GC thread at a time nobody controls, and it must take the table lock in the same order as wait and signal, or it adds a deadlock to the runtime.

- **Web/Scripting** (web):

> R. Vote: R-allow
> Reasoning: No Blink code can see when the runtime frees a slot that no Child can reach, so the permission costs users nothing. It lets the GC fix for spawn-and-forget leaks land later with no spec change. If the spec forbids it, we write a leak into the spec as a promise.
> Concern: Someone uses FFI and depends on the zombie staying alive (for example, a raw pid in a log), and an early reap surprises them.

- **PLT** (plt):

> R. Vote: R-allow.
> Reasoning: Once no copy of a Child is reachable, no program can observe a reap, so forbidding it constrains only the implementation and protects no semantic property. A spec rule that forbids an optimization nobody can observe is over-specified. The program-visible behavior stays the same under both options.
> Concern: An implementation that reaps from a GC finalizer must take the table lock and must never race a signal on a copy that the GC thinks is dead but a register still holds; if it gets this wrong, a recycled pid gets signaled.

- **DevOps/Tooling** (devops):

> R. Reap when unreachable
> Vote: R-allow
> Reasoning: The reap cannot be observed, so the permission costs no correctness, and it lets the GC-reap ticket land later with no spec change. From my seat, the operator note still belongs next to it: an unwaited Child that stays reachable keeps its zombie and slot, so a leak shows as zombies and then EAGAIN at spawn.
> Concern: "may reap" can lead readers to drop Childs on purpose and expect the GC to clean up, so the text must say that only a wait is certain to reap a child.

- **AI/ML** (aiml):

> R. Vote: R-allow.
> Reasoning: In round 1 I accepted the forbid form to move the point to another ticket. On a fresh read, no program can observe this reap, because no copy is left to wait or signal. Its only visible effect is that spawn hits EAGAIN later, never sooner. Forbidding it ties the runtime to a leak and gives users nothing they can test.
> Concern: users may come to depend on GC reaping to free slots, so their spawn loop works on one runtime and gets EAGAIN on another; the spec text must say "do not depend on it" in plain words.

- **Minimalism** (min):

> R. Vote: R-allow.
> Reasoning: no program can observe a reap of a child that it can no longer reach, so a ban protects nothing, and it would block the GC-reap ticket. My first choice is that the spec says nothing about it. If the writer wants a sentence, it must be the permission, not the ban.
> Concern: a permission sentence for something no runtime does yet can lead readers to think it happens today, and so expect zombies to clean themselves up.


**F. A number for the cap.** Tally: F-none 5-1 (devops votes F-floor).

- **Systems** (sys):

> F. Vote: F-none.
> Reasoning: On a default host the fd limit stops a program at about 510 live children, so a promise of 4096 is false where users meet it. A number in the spec freezes a table size and a memory cost (the table is static today) for every target, small ones included.
> Concern: Without a number, a later runtime could choose a small cap, so EAGAIN from the runtime would come before the OS limit and confuse users; the writer note should say the runtime's own cap should not be the first wall.

- **Web/Scripting** (web):

> F. Vote: F-none
> Reasoning: A program usually hits EMFILE at about 510 children on a default `ulimit -n`, so "at least 4096" promises a number that users will not reach. A floor that real hosts cannot honor creates more questions than no number at all. The EAGAIN and EMFILE entries in the catalog tell the user what to do.
> Concern: Users have no number to plan by, so the docs must state the usual limit (ulimit -n) next to the error.

- **PLT** (plt):

> F. Vote: F-none.
> Reasoning: A floor binds every conforming runtime, but the default host already fails it: at `ulimit -n` 1024, pipes give EMFILE at about 510 live children. A guarantee that the default host breaks is not a guarantee. EAGAIN plus the pass-through errno gives a defined result at any count.
> Concern: With no number, a runtime may pick a very small cap, and portable code then cannot know how many children it can keep unwaited.

- **DevOps/Tooling** (devops):

> F. A number for the cap
> Vote: F-floor
> Reasoning: A floor is a promise that a program can rely on ("I can hold 4096 unwaited children"), and it ties the runtime to nothing more. sys's plan (grow the table so that the OS limit fires first) meets it. With no number, a pool size that works on one runtime can give EAGAIN on another, and nothing in the spec says which is wrong.
> Concern: if F-none wins, the EMFILE / `ulimit -n` writer note is the only guide that a user has to a real limit, so it must not be cut.

- **AI/ML** (aiml):

> F. Vote: F-none.
> Reasoning: sys showed that the fd limit (EMFILE at about 510 children) fires long before 4096. A floor is a promise users never reach, and it becomes ABI. A model learns more from "wait on every Child; EAGAIN or EMFILE means too many unwaited children" than from a number.
> Concern: with no number, a test that spawns many children has no portable bound, so a test author may hard-code a count that works on one host only.

- **Minimalism** (min):

> F. Vote: F-none.
> Reasoning: at the default `ulimit -n` of 1024, the host hits EMFILE at about 510 live children, so a floor of 4096 is a promise that the host breaks first. A number in sections/ is an implementation detail that becomes a promise forever.
> Concern: with no number, a user cannot tell how many unwaited children are safe. The Gotchas entry must point to "wait on every Child" and to `ulimit -n`.


#### Phase D — Round 2

Phase C split D and E 4-2. The seats replied to each other on D and E. The replies raised a new question, D.v: what the text of a real `Child` says after a wait reaped it. Each seat's reply and re-vote follow, in full.


##### Systems (sys)

Reply:

> sys Phase D ([...]), D and E.
>
> D: I keep D-pid, and I concede one point to aiml and min.
> - The concession: the Debug text of a real Child is different on every run, and the spec should say so. A test must not compare it. Their snapshot concern is real, but it is narrow. A test that prints a Child is almost always a mock test, and `Child.mock(3)` is stable. A real Child shows up in a golden only when the test starts a real program, and then the out and err_out text and the timing differ between runs anyway.
> - The rebuttal on "the first step toward a getter / Debug becomes ABI": nobody needs to parse Debug to get a pid. Any program can already read `/proc/self/task/*/children` or run `ps --ppid`, so D-nopid does not stop a pid from reaching code. It only stops the person who reads the log line from seeing it. The recycled-pid hazard comes from a typed pid that flows into `libc.kill`, and P already rules that out (no getter).
> - One new behavior fact for the writer, not a new option: after the wait, the pid in the text may name another process, because the OS can give it out again. The Debug of a waited Child should mark that it has ended (for example `Child(pid 4211, ended)`), so an operator does not go to `ps` and find the wrong process. The runtime knows this from the box, so it costs nothing.
>
> E: I keep E-debug. plt's alternative does not work as written.
> - plt says the clearer line "belongs in Display, which the writer can word from the code and the op without changing the field". But Display sees only `op`, `cmd` and `code`. With E-empty, a made Child gives `{ op: Wait, cmd: "", code: ECHILD }`. A real child that something outside Blink reaped (FFI waitpid(-1), SIGCHLD set to SIG_IGN) gives `{ op: Wait, cmd: "make", code: ECHILD }`, and the only fact that tells the two cases apart is the empty cmd. Display can then print only "an empty cmd means a made Child", which is E-debug with worse text, or it needs a new field, which P ruled out ("no new error variant").
> - On "cmd has two meanings": for wait and signal, cmd already is not "the command this op ran". Those ops run no command. cmd names the subject of the error, the program the Child came from. A made Child has no program, so its subject is the Child itself, and its Debug text names it. That is one meaning: the thing the op acted on. I accept min's and devops's writer note: one clause that cmd holds the Child's Debug text when the built-in handler did not make the Child.
> - Code that groups errors by `e.cmd` puts every leaked mock in one bucket per mock key. That is the right grouping for a wiring bug.
>
> Stable, ready to vote.

Re-vote:

> sys Phase D re-vote ([...]).
>
> D. Vote: D-pid.
> Reasoning: The pid is how an operator joins a log line to `ps`, `/proc`, journalctl or a cgroup event, and Debug is text for people, not a typed handle. Hiding it does not keep the pid from code (a program can read `/proc/self/task/*/children`). It only keeps it from the person who reads the log. A test of a mock Child stays stable, because `Child.mock(3)` has no pid in it.
> Concern: A golden or `assert_eq` that prints a real Child differs on every run, so the writer must state that the text of a real Child is not stable.
>
> D.v. Vote: D.v-ended.
> Reasoning: After the reap the kernel may give the pid to a new process at once (a busy host cycles pid_max within minutes). `Child(pid 4211)` then sends the operator to `ps` to find the wrong process, and a spec sentence does not reach the person who reads a log line at 3 a.m. The runtime already knows "waited" from the box, so the mark costs one branch on a path that only formats text.
> Concern: A Child that has exited but has not been waited still prints without "ended", so a reader may take its absence to mean "still running" when it only means "not yet reaped".
>
> E. Vote: E-debug.
> Reasoning: E-empty+display uses `cmd == ""` as a hidden tag. A mock can build its own `ProcessError { op: ProcessOp.Wait, cmd: "", code: ... }`, and then Display adds "this Child came from a handler" to an error that no leaked Child caused, which is a wrong message. E-debug infers nothing: the Child that the op acted on is named in the field that names the subject, so the line is right for every value that can reach Display. It costs nothing, because the text is built only on this error path.
> Concern: Code that treats `e.cmd` as a program name (to retry it, or to look it up on PATH) gets `Child.mock(1)` in this one case, so the writer must say so in one clause.


##### Web/Scripting (web)

Reply:

> web Phase D ([...]), on questions D and E only.
>
> D: I hold D-pid, and I give the nopid side one point.
>
> The golden-test point is real for the case it names. But in a test, the Child is almost always a mock, and `Child.mock(3)` prints the same text on every run. A golden that prints a real Child already depends on a real process, so its output (timing, the child's own text) varies anyway. The place where a real Child's Debug text shows up is a log line from production code, and there the pid is the whole value. Read "Child(spawned)" in a log at 3 a.m. and you have nothing to look up in `ps` or `journalctl`.
>
> To min's "the format becomes ABI": that happens only if parsing it is the only way to get the pid. The fix is the pid getter ticket we already put off. Hiding the pid does not fix it, because people would then shell out to `pgrep` instead, which is worse.
>
> To sys's own concern, parse the pid and then call `libc.kill`: that code needs FFI, and FFI is already outside the runtime's guarantees.
>
> What I give: the writer must say that the Debug text of a real Child changes from run to run and is not a format for a program to parse. Spec and llms examples must print only mock Childs. With that text in place, I see no observable cost left that outweighs the help to the operator.
>
> E: I hold E-debug. I would accept one stated form of E-empty, but not the bare one.
>
> plt and min are right that `cmd` then holds two kinds of value. But the user-facing failure with bare E-empty is the line "wait : No child processes". Every user who hits it files it as a Blink bug, and it is the most likely error a mock writer sees.
>
> plt says Display can give a clear line with cmd = "". That works only if Display has a rule for it. The value has no Child in it, so Display can name the cause but not the mock. For example: `wait: No child processes (this Child came from a handler, not from process.spawn)`, shown exactly when cmd is "". That is acceptable to me as a second choice, because a user then sees the cause and the fix. It is still weaker than E-debug, which also names which mock, and that matters when a test has two.
>
> So my order: E-debug first. Second, E-empty plus a Display rule for an empty cmd that names the cause. Bare E-empty with no Display rule is the option I reject. If E-empty wins, I ask the writer to take the Display rule as part of it, not as wording to decide later.
>
> Stable, ready to vote.

Re-vote:

> web Phase D re-vote ([...])
>
> D. Vote: D-pid
> Reasoning: A real Child shows up in a production log line, and there the pid is what a dev looks up in `ps` or `journalctl`. Test text stays stable, because tests print mock Childs. The writer must say that a real Child's text changes from run to run and is not a format to parse.
> Concern: Someone parses the pid out of the text before the pid getter ticket lands, and the format then becomes one that programs depend on.
>
> D.v. Vote: D.v-ended
> Reasoning: A dev who reads `Child(pid 4211)` in a log will run `kill 4211` or look the pid up, and after the reap that pid may belong to another process. `ended` answers the first question they will ask, "is this pid still mine?", right in the text, and no one has to have read a spec sentence. It costs one word, and only after the wait.
> Concern: The same Child prints different text before and after its wait, which can confuse someone who compares two log lines.
>
> E. Vote: E-debug
> Reasoning: `wait Child.mock(1): No child processes` names both the cause and the mock that leaked, and the second part matters when a test has two mocks. E-empty+display is my second choice: it names the cause but not the mock. Bare E-empty reads like a bug in Blink, and every user who hits it will file it as one.
> Concern: Code that logs or groups by `e.cmd` as a program name gets `Child.mock(1)` for this one error path.


##### PLT (plt)

Reply:

> PLT Phase D ([...]): I hold D-pid and change E to E-debug.
>
> D: I hold D-pid, and I accept a real cost that min and sys named.
> - To aiml and min (tests and goldens): a test that compares Debug text of a real Child is checking a child it did not mock. It should use Eq or match on `end`. Under P every observable fact about a child goes through Eq, `wait` and `signal`, so a test has a stable thing to assert on. Run-to-run noise in Debug text breaks only code that the spec already tells people not to write.
> - To min and sys (Hyrum's law: people will parse the pid out of Debug and signal it by hand): this is the strongest point against me, and it is real. But the only way to act on a parsed pid is `libc.kill` through FFI, and that path already has the recycled-pid hazard for any pid from any source. D-nopid does not close that hole; it only removes one way to find the number. An operator who joins a log line to `ps`, `/proc` or a core dump has no other way to get it. A missing getter does not make the format an ABI unless the spec says it is one, and the spec says it is not.
> - No change to observable semantics either way: no rule, op or type branches on the text.
>
> E: I change to E-debug. devops's framing answers my objection. In every ProcessError, `cmd` is the human-readable name of the thing the op acted on. For a real Child that name is its command. A made Child has no command, so its Debug text is its human name. Read that way, the field keeps one meaning ("what this op acted on, as text"), not two. My E-empty also needed a special Display rule keyed on an empty `cmd` to give a readable line, and that is worse: Display would branch on a sentinel value. E-debug gets the same readable line from the plain `op cmd: message` shape with no special case. I keep one requirement as a writer note: say that `cmd` holds the Child's Debug text only for a Child that the built-in handler did not make, so nobody reads it as a program name.
>
> Stable, ready to vote.

Re-vote:

> PLT Phase D re-vote ([...]): D-pid, D.v-ended, E-debug.
>
> D. Vote: D-pid.
> Reasoning: No rule, op or type branches on Debug text, so a pid in it adds no power to the language. It gives an operator the one key that joins a log line to `ps`, `/proc` or a core dump. Tests already have stable observers (Eq, `wait`, `end`), so run-to-run noise breaks only code that compares Debug text of a real child, which the spec already rules out.
> Concern: With no getter, people will parse the pid out of the text and feed it to `libc.kill`, outside the runtime's lock.
>
> D.v. Vote: D.v-ended.
> Reasoning: After the reap the runtime holds no claim on the pid. Text that shows only `pid 4211` then states something about the present that may be false. `ended` makes the text true at the moment it is printed, and it shows only a fact the program already knows: some copy of the Child was waited. It also takes away most of the reason to parse the pid, because a reader can see when the pid is stale. Eq and every op stay unchanged, so this changes no semantics.
> Concern: One Child value prints differently before and after a wait, and a reader may expect Debug text to be a fixed function of the value.
>
> E. Vote: E-debug.
> Reasoning: In every ProcessError, `cmd` is the readable name of what the op acted on. For a made Child that name is its Debug text, so the field keeps one meaning and Display keeps its plain `op cmd: message` shape. E-empty+display makes Display branch on a sentinel value (`cmd == ""`). Then an empty `cmd` that comes from somewhere else, such as a mock `ProcessError` a test builds, would print the "came from a handler" text and give a wrong diagnosis. E-empty alone names no cause.
> Concern: Code that groups or retries on `e.cmd` as a program name gets `Child.mock(1)` in this one case, unless the writer states the rule clearly.


##### DevOps/Tooling (devops)

Reply:

> devops Phase D ([...]), on D and E only.
>
> D: I hold D-pid.
> - To aiml and min ("goldens and assert text differ on each run"): a test that prints a real Child has spawned a real process, so it is not a golden-stable test to begin with. Its timing, its environment and its pid are all facts of the host. The fixed text that a test needs is the made Child, `Child.mock(3)`. Both options print that the same way, so every mock-based test and every spec example stays deterministic under D-pid. The cost falls only on tests that compare Debug strings of real children. sys and plt are right that such a test should use Eq.
> - To min and sys ("people will parse the pid out of the text, and it becomes ABI"): this is the strongest point against me, and I take it seriously. But the pid is the one fact an operator needs at 3 a.m., and D-nopid does not remove that need. It only moves it to `@ffi` getpid tricks or a log line that the user writes by hand, both of which are worse. The answer to "people will parse it" is to file the getter ticket (aiml and min already want a separate ticket), not to hide the fact from the people who read logs. Until then, the writer says that the Debug text is not a format, as for every other Debug impl.
> - Observable behavior I ask for under D-pid: the pid shows only while the runtime holds the child. After the reap, the text is still `Child(pid 4211)`, but the spec says this pid may now name another process. That is a fact for a reader of the log. Code gets no handle from it.
>
> E: I hold E-debug, and I name one form of E-empty that I can accept.
> - To plt and min ("cmd gets two meanings"): true. The two meanings are "the subject of this op". For a real Child that is its command, and for a made Child the runtime knows no command, so the Child is the only subject it has. Code that groups errors by `e.cmd` gets a group named `Child.mock(1)`. That is the right group: every such error is the same wiring bug.
> - plt's alternative (keep cmd "", and let Display word the cause) gives an operator the same line, and I would accept it IF the ballot made it binding: Display of a wait or signal Err on a made Child must name the cause, for example `wait: this Child was not made by the built-in handler (No child processes)`. Plain E-empty, as balloted, with no such rule, gives `wait : No child processes`. plt's own concern says that line "names no cause", and that is the line I reject.
> - So my vote stays E-debug on this ballot. If the panel wants a third option ("E-empty + a Display rule that names the cause"), I rank it second, above plain E-empty.
>
> Stable, ready to vote.

Re-vote:

> devops Phase D re-vote ([...])
>
> D. A real Child's Debug text
> Vote: D-pid
> Reasoning: The pid is how an operator joins a log line to `ps`, `/proc`, a journal or a core dump. A made Child prints the same fixed text under both options, so mock tests and spec examples stay deterministic. Only code that compares Debug strings of real children loses, and that code should use Eq.
> Concern: with no getter, someone will parse the pid out of the Debug text, so the getter ticket should be filed now and the writer must say that the Debug text is not a format.
>
> D.v. Debug text after the reap
> Vote: D.v-ended
> Reasoning: sys's form is better than mine. `Child(pid 4211, ended)` tells the operator in the log line itself that this pid is stale, and they do not need to know a spec sentence to read it. It also blocks the worst misuse of a parsed pid: anyone who reads "ended" knows not to signal it.
> Concern: "ended" must mean "the runtime has reaped it" (after a wait), not "the child exited". If the writer blurs the two, the text will appear to change at random while a zombie waits.
>
> E. The Err for a Child the built-in handler did not make
> Vote: E-empty+display
> Reasoning: I move from E-debug. This option gives the operator the line I asked for, one that names the cause and points to the fix, and it keeps `cmd` with one meaning, which answers plt's and min's objection in full. Both sides' concerns are met. Neither of the other options does that.
> Concern: the Display rule must key on "a wait or signal Err on a Child that the built-in handler did not make", not on any empty cmd, because `process.spawn("", [])` gives a real Err with cmd "" and must not print the handler hint.


##### AI/ML (aiml)

Reply:

> aiml Phase D ([...]): I concede D and move to D-pid. I hold E-debug.
>
> D: concede, D-pid.
> The other side is right on the fact I weighed too high. Code can only compare a real Child with Eq: it has no literal to assert against, so no correct test compares the Debug text of a real Child. My "a model cannot fix a message that differs each run" case only covers a test that already fails, and there the pid helps more than it hurts, because it links the failure to `ps` and to the logs. min and sys raise a real risk: with no getter, people (and models) will parse the pid out of the text. That is a reason for the writer to say plainly that the Debug format is not stable and is not a way to get the pid. It is not a reason to hide the pid. Writer note I ask for: spec examples and golden tests that print a real Child must not show a pid literal; use a mock Child or Eq.
>
> E: hold, E-debug.
> plt and min say `cmd` gets two meanings. In practice it already has one meaning: the subject of the failed op as the runtime knows it. For `wait`, that is the command stored on the Child, not a command the op ran. For a made Child, the only subject the runtime has is the Child itself, so its Debug text is the honest value. "" is not more correct: it is a third value that means "unknown", and code that groups or logs on `e.cmd` gets a blank key that hides the cause. Retry code that feeds `e.cmd` back to `run` gets ENOENT from `Child.mock(1)`, which is harmless and visible. plt's other path, a Display rule with cmd "", cannot name the Child: ProcessError holds no Child, so Display could at best print a generic "made Child" line. A model fixes the leak faster when the line names the exact mock (`Child.mock(1)`), because it can find it in the test. Writer note, as all four E-debug seats said: one clause that `cmd` holds the Debug text only for a Child the built-in handler did not make.
>
> Stable, ready to vote.

Re-vote:

> aiml Phase D re-vote ([...]): D-pid, D.v-ended, E-debug.
>
> D. Vote: D-pid.
> Reasoning: As I said in Phase D: no correct test compares the Debug text of a real Child, because Eq is the only way to compare children. So the pid harms only a test that already fails, and there it links the failure to `ps` and the logs. The parse risk belongs in the writer note, "the format is not stable and is not a way to get the pid". It does not justify hiding the pid.
> Concern: models parse the pid out of the text to call `libc.kill` because there is no getter, and that brings back the recycled-pid bug outside the runtime lock.
>
> D.v. Vote: D.v-ended.
> Reasoning: The text itself must carry the fact that the pid is stale, not a spec sentence that no model reading a log will see. `Child(pid 4211, ended)` tells the reader (and a model that debugs from the log) not to look for 4211 in `ps` and not to signal it. That cuts the parse-and-kill risk on the exact path where it does harm. D.v-same prints a pid that may now name another process with nothing to mark it, which is a wrong fact in a debug line.
> Concern: Debug text of one Child changes after its wait, so two log lines for the same child differ, and a reader may take them for two children.
>
> E. Vote: E-debug.
> Reasoning: E-empty+display is a good second and much better than E-empty, because it names the cause. But a test with two or three mocks needs to know which made Child leaked, and only E-debug says `Child.mock(1)`, which a model can find in the test with one search. As in Phase D, `cmd` already means "the subject of the op as the runtime knows it", and for a made Child the Child is the only subject. If E-debug loses, I want E-empty+display, not E-empty.
> Concern: code that logs or groups on `e.cmd` as a program name prints `Child.mock(1)` for this one case, so the writer must state that exception in one clause.


##### Minimalism (min)

Reply:

> min Phase D: I change both votes, to D-pid and E-debug.
>
> D: I concede to D-pid. plt's point decides it: the spec gives Debug text no format, and no rule may branch on it. So my argument about goldens applies only to tests that compare Debug text of a REAL Child, and those tests are already wrong. A test of process code runs under a mock, and a mock Child prints the same text on every run. My "ABI by accident" fear is real, but the pid is already in `ps` and /proc, so leaving it out of Debug does not stop anyone from parsing it. The way to answer that fear is to say the text is not stable, not to hide the pid. The operator value (joining a log line to `ps` or a core dump) is real and costs nothing. One condition for the writer, which all four D-pid seats also asked for: the spec says that the Debug text of a real Child changes from run to run, and that code must not parse it or compare it. No spec example and no golden test prints a real Child.
>
> E: I concede to E-debug. I weighed plt's middle path (keep `cmd` as "" and make Display special for a made Child). It adds a special case to Display, and that is a bigger special case than an odd value in one field on an error path that only bad wiring reaches. With E-debug, Display stays one rule, `op cmd: message`, and the line names the cause and the fix. The cost is that `cmd` has two meanings. That is small: no program retries or groups errors on this path, because the error itself is a bug. Condition for the writer: one clause saying that for a Child the built-in handler did not make, `cmd` holds the Child's Debug text.
>
> stable, ready to vote.

Re-vote:

> min Phase D re-vote.
>
> D. Vote: D-pid.
> Reasoning: I keep the position from my Phase D reply. The spec gives Debug text no format, so a pid in it adds no power to the language, and it lets an operator join a log line to `ps` or a core dump. The only tests that break are tests that compare Debug text of a real Child, and those are already wrong.
> Concern: people will copy the pid out of a log line into `kill`, after the runtime has reaped that pid and the OS has given it to another process.
>
> D.v. Vote: D.v-same.
> Reasoning: with `ended`, the Debug text depends on mutable state of the box, so printing a Child must read the waited flag under its lock. Two prints of one value can then differ inside one run, and that is a race in a text that is only for people. The note "after a wait, this pid may name another process" covers the operator's risk with one sentence and adds no new state to read.
> Concern: an operator who skips the note can match a stale pid in a log to the wrong process in `ps`.
>
> E. Vote: E-debug.
> Reasoning: E-empty+display adds a special case to Display ("when cmd is empty, print this other text"). Display is the one rule all ProcessErrors share, so that is a bigger special case than an odd value in one field on an error path that only bad wiring reaches. E-debug keeps one Display rule, `op cmd: message`, and the line still names the made Child, which is the cause. E-empty with no Display rule names no cause, so of the three options it is the worst.
> Concern: code that logs or groups errors by `e.cmd` will show `Child.mock(1)` as if it were a program, unless the writer's clause on this case is clear.


Phase D tally:

- D: D-pid 6-0. aiml and min conceded.
- D.v: D.v-ended 5-1. min votes D.v-same **(dissent)**.
- E: E-debug 5-1. plt, min and aiml hold or move to E-debug. devops votes E-empty+display **(dissent)**.

### Final Spec

```blink
let mock = handler Process {
    fn spawn(cmd: Str, args: List[Str], *, env: ChildEnv, cwd: Str?, limits: ChildLimits) -> Result[Child, ProcessError] {
        Ok(Child.mock(1))
    }
}
// Child.mock(1) == Child.mock(1)       true
// Child.mock(1) == Child.mock(2)       false
// Child.mock(3)                        the Debug text of a made Child
// Child(pid 4211)                      a real Child that no wait has reaped
// Child(pid 4211, ended)               the same Child after a wait reaped it
// process.wait(Child.mock(1))          under the built-in handler:
//     Err: wait Child.mock(1): No child processes
```

- `Child` is opaque and has no methods. It implements `Eq`, `Hash` and `Debug`. There is no getter, and no pid getter today.
- `Child.mock(id: Int) -> Child` is a pure type-scoped function of `std.process`. "mock" means "made by a handler", not "test only".
- Copies of one `Child` are equal. `Child.mock(n) == Child.mock(m)` exactly when `n == m`. A real `Child` never equals a made one. Two real spawns never give equal values.
- A `Child` that the built-in handler did not make: `process.wait` gives `Err` ECHILD and `process.signal` gives `Err` ESRCH. No syscall reaches any pid. No panic. No lint.
- In that `Err`, `cmd` holds the `Debug` text of the `Child`. It holds that text only in this case. `Display` keeps the shape `op cmd: message`.
- A real `Child` prints its pid. "ended" means that a wait reaped the child, not that the child exited. The text changes from run to run, is not a format, and code must not parse it or compare it. No spec example prints a real `Child`.
- A second `wait` gives the same result, `Ok` or `Err` (same op, cmd, code). This binds the built-in handler only. A user handler decides for itself.
- The runtime never drops a `Child` result. The 4096 / 1 MiB bound does not apply to a `Child`.
- `process.signal` on an ended child gives `Ok(())`, whether or not a wait reaped it. After the reap, no signal goes out. `EINVAL` and `EPERM` stay errors. `ESRCH` comes only for a `Child` that the built-in handler did not make.
- The runtime may reap a child once no copy of its `Child` is reachable. Code must not depend on when or whether this happens. Only `wait` is certain to reap.
- `process.spawn` gives `Err` EAGAIN when the runtime cap on children not yet waited is full. No child starts. No new error variant. The spec gives no number for the cap, and the cap is not the first limit a user meets.
- An OS failure passes through the errno of the step that failed: EAGAIN from the process limit, EMFILE or ENFILE from the pipes, ENOMEM.
- `process.run` takes no slot from the cap. Children that were spawned and not waited do not make `process.run` fail.
- llms Gotchas: EAGAIN means wait on every `Child` you spawn. EMFILE comes at about 510 children at `ulimit -n 1024`, so raise `ulimit -n`.

### Implementation notes

These notes are for the compiler, library and runtime work. They are not spec text.

From the panel:

- Q2 needs a corpus test that signals after a wait under load. The race-free rule is the part that an implementer can break without notice.
- The one-lock rule (the reap and the signal check take one lock) must survive a later move to `pidfd` or to a `SIGCHLD` reaper. If it does not, Q2's `Ok` turns into a `kill` on a recycled pid.
- A finalizer reap takes the lock in the same order as `wait` and `signal`. It must not race a copy that a register still holds.
- `Hash` on a real `Child` depends on a non-moving GC, or on a serial that each spawn gets. A moving GC must keep the hash stable.
- File a pid getter as a follow-up. It is a separate, later ruling.

For the work that follows:

- Typecheck: `Child.mock(id: Int) -> Child` is a pub pure type-scoped function with no effect row. `Child` gets `Eq`, `Hash` and `Debug` impls. The `Debug` text of a made `Child` is `Child.mock(n)`.
- Runtime, `Eq` and `Hash`: a real `Child` compares by the identity of the spawn. A made `Child` compares by its key. The two kinds never compare equal.
- Runtime, `Debug`: a real `Child` shows `Child(pid N)`, and `Child(pid N, ended)` once a wait reaped it. The `ended` mark reads the waited flag under the same lock as `wait` and `signal`.
- Runtime, Q1b: a `Child` that is not a spawn of the built-in handler makes no syscall. `wait` gives ECHILD and `signal` gives ESRCH, both with `cmd` set to the `Debug` text. The `Display` shape does not change.
- Runtime, Q2: `signal` checks the reaped flag under the lock before it calls `kill`. If the child has ended, the call gives `Ok(())` and sends nothing. A bad signal number gives EINVAL, and the OS gives EPERM.
- Runtime, Q3: the result lives with the `Child` after the first wait. A failed first wait stores its `Err`, and a second wait returns it. The old `Pid` ring keeps its bound, and no `Child` path reads it.
- Runtime, Q4: `spawn` gives EAGAIN when the table is full and starts no child. A failing step (`fork`, `pipe`) returns its own errno. `process.run` does not take a table slot.
- The size of the table is not in the spec. Make the OS limit on files fire first on a usual host.
- Tests: a corpus test for each example in §4.4.8 (made `Child` under the built-in handler, second wait, signal after exit, signal after wait, spawn at the cap) and for the two-child mock with `Map[Child, ProcessResult]`.
