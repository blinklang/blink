[< All Decisions](../DECISIONS.md)

# Child Limits: The Edges — Design Rationale

**Question.** §4.4.8 leaves the edges of child limits open. What happens to the rest of a limited child's process group when the leader exits first? What does program exit do to limited children? What are the exit race, the deadline clock, the order of errors, and the result of `run` or `wait` when the runtime may not signal the child (`EPERM`)? Which cgroup cases does the spec state?

```blink
let r = process.run("sh", ["-c", "sleep 30 & exit 0"],
    limits: ChildLimits { timeout: Some(Duration.seconds(5)) })?
// returns at once, at 5 s, or at 7 s? Is r.end Exited(0)? Is the sleep still alive?
```

**Answer.** A limited child is a unit: its tree ends with its leader. When `run` or `wait` sees the leader exit, the runtime ends the rest of the leader's group (or cgroup) with SIGTERM and, after `grace`, SIGKILL. Then it reads the pipes to end of file and returns. The example returns at about 0 s with `Ok` and `Exited(0)`, and nothing stays alive. The same end holds for an unwaited `spawn`. At program exit each limited group is ended the same way. `Err(EPERM)` from `run` or `wait` means that the limit could not be enforced and the child may still be alive. See *Final Spec* for the list.

### Panel Deliberation

Six seats voted: Systems, Web/Scripting, PLT, DevOps/Tooling, AI/ML and Minimalism. The quotes below come from the seats' own replies. Where a quote has a "[...]", the quote skips text. Phase D ran for Q3 only.

#### Phase A — Independent proposals

Each seat proposed alone. The quotes are excerpts from the seats' own proposals.

- **Systems.** "a limited child is a unit. When its leader ends, the runtime ends what is left of its group (or cgroup) before run or wait returns."
- **Web/Scripting.** "a JS or Python dev reads `limits: ChildLimits { timeout: 5s }` as "this command and everything it started is gone by 5 s + grace"."
- **PLT.** "a limit is a property of the child's TREE, not of whoever observes it (the Q2 reasoning)."
- **DevOps/Tooling.** "The interim picks make the result depend on timing that the user cannot see."
- **AI/ML.** "R2. When `run` or `wait` returns for a limited child, no part of its group (or cgroup) is alive."
- **Minimalism.** "Invariant: *a limited child's tree does not outlive the call that collects it.*"

The seats differed on one point above all: whether a reap ends the leftovers (Option L) or the deadline does (Option T), and they differed on four smaller points that Phase B settled or put to the vote.

#### Phase B — Debate highlights

Phase B ran one round. Quotes are from the seats' own text.

**Option T (the deadline ends the tree) against Option L (the tree ends with the leader).**

- **DevOps/Tooling.** "Variant `sh -c "sleep 30 >/dev/null 2>&1 & exit 0"` → `run` returns at once with `Exited(0)`; the `sleep` ends at 5 s."
- **Systems.** "T has a cost that nobody priced: it keeps a zombie for each waited child until the deadline."
- **Web/Scripting.** "Under T, the ticket's example takes 5 s for a command that finished at 0 s."
- **PLT.** "T passes that test only by holding a zombie past `wait`, and the runtime must still reap it later."
- **DevOps/Tooling.** "The point of my T was to stop the leftovers from depending on when `wait` runs. L gets that too, and it gives a bound the user can see in their own code: when `run`/`wait` returns, the tree is gone."

DevOps/Tooling and PLT moved from T to L. Systems, Web/Scripting, Minimalism and AI/ML held L from Phase A.

**L-now (end the group when the leader exit is seen) against L-after-EOF (read the pipes first).**

- **AI/ML.** "Waiting for EOF keeps the output whole, as Go's `Wait` and Python's `communicate` do, and the bound keeps the documented return-time promise."
- **Systems.** "Under L-now the return time is the leader's exit plus at most `grace`, for every limited child."
- **AI/ML.** "L-after-EOF also has no bound for a child with no deadline: a leftover that holds the pipe holds `run` forever, which brings back the Python/Go hang."

AI/ML moved to L-now. No seat backed L-after-EOF in Phase C.

**L-unwaited (the leftovers of a `spawn` that nobody waits on).**

- **PLT.** "A late `wait` gives the leftovers a longer life. That is the Q2 observer dependence again."
- **Minimalism.** "L-unwaited: no spec rule. The deadline or program exit already bounds it, and a pidfd watcher is optional implementation work. YAGNI."

Systems, PLT and AI/ML made the rule required. PLT: "If the panel votes L without it, I vote T." The ballot (Q1) put it to the vote.

**I-L (`Limit(Processes)`) against I-E (`Exited(c)`) when the leader exits after a refused fork.**

- **AI/ML.** "Confirm by R1: the leader ended on its own before the runtime ended the tree, so `Exited(c)`."
- **DevOps/Tooling.** "The spec names the cause, not who moved last."
- **AI/ML.** "My R1 said `Limit(k)` means the runtime's signal reached the leader first. That wording is too narrow."
- **Systems.** "A refusal by a leftover after the leader ended does not count."

AI/ML moved from I-E to I-L. The vote was 6-0 for I-L, so it is settled and not on the ballot.

**The `EPERM` variations (V10).**

- V10-1, when the `Err` returns. **Minimalism.** "`Err(ProcessError { code: EPERM })` at about `timeout`, with no grace, because SIGKILL would fail too." **Systems.** "if SIGTERM to the leader gives EPERM, SIGKILL will too, so waiting `grace` gains nothing." **Web/Scripting.** "a group `kill` that reaches any member succeeds, so the runtime can only tell that enforcement failed once the leader is still alive at the end of the grace." **Minimalism.** "CHANGE OF MIND, I now back timeout + grace + δ" Systems and PLT moved toward the deadline; Web/Scripting, AI/ML and Minimalism moved to the end of the grace. After V10-4 was settled, the question went to the vote as Q2.
- V10-2, an error at start for a set-user-ID program. **DevOps/Tooling.** "if the program that the limited child execs directly is setuid or setgid (the runtime checks the mode bits of the resolved file), `run`/`spawn` give `Err` with `ENOTSUP` and no child starts." **DevOps/Tooling.** "A false ENOTSUP is worse than the rare late EPERM." DevOps/Tooling withdrew it. No seat kept it.
- V10-3, what the handle does after the `Err`. **AI/ML.** "`wait` on that handle later gives the same `Err`." **AI/ML.** "A later `wait` blocks with no limit and returns the child's real end." AI/ML moved.
- V10-4, what counts as a failed signal. **DevOps/Tooling.** "If the group signal reaches at least one member, there is no error: the normal `Limit(Timeout)` path." **PLT.** "The rule: `Err(EPERM)` if and only if the signal to the leader itself fails." **DevOps/Tooling.** "I adopt plt's test and drop mine."

**P1 to P4.**

- P1, a second signal. **Web/Scripting.** "a second SIGINT/SIGTERM that arrives while the program is in the exit grace sends SIGKILL to every limited group at once and ends the program."
- P2, SIGHUP. **Systems.** "because a closed terminal is the usual way a runner dies, and SIGHUP is fatal by default." **Web/Scripting.** "SIGHUP starts the exit path only when its action would end the program anyway (default disposition)." **DevOps/Tooling.** "if SIGHUP is ignored at program start (`nohup`), the runtime keeps it ignored. Same for INT/TERM."
- P3, a warning for a `grace`-only literal. **DevOps/Tooling.** "`blink check` should warn (W-code, "grace has no effect without a limit")." **Minimalism.** "A field that does nothing is harmless."
- P4, `grace` for the leftovers. **AI/ML.** "It keeps `grace` at one meaning: an end the runtime chooses (deadline, leftovers, exit) is SIGTERM then SIGKILL after `grace`."

P1, P2 and P4 passed 6-0 and are settled. P3 went to the vote (Q3). Five seats sent "stable, ready to vote". PLT sent "not stable", with one condition: L-unwaited. The ballot put that condition to the vote as Q1.

#### Phase C — Final vote

Phase C was a silent vote on three questions. The items that every seat stated in Phase B (the list in *Final Spec*) were not on the ballot. The text after each vote is the seat's own reasoning, whole, from its ballot.

##### Q1. A limited `spawn` whose leader exits when nobody calls `wait` — A (5-1)

A: the watcher ends the leftovers at the leader's exit, whoever waits. B: the leftovers end at the first of `wait`, the deadline or program exit. C: the deadline ends the tree (Option T).
- **Systems** — A. "Under B, an unwaited `spawn` with no `timeout` (only a memory or processes limit) keeps its leftovers alive until program exit, so nothing bounds the tree. B also makes the leftovers' life depend on when the caller calls `wait`, which is the observer dependence we rejected in Q2 of the first panel. The cost of A is small and known: one pidfd (Linux) or kqueue NOTE_EXIT (macOS) per live limited child in the watcher's poll set, and no reaping. The zombie pins the pgid until the per-child lock lets `wait` reap, so the group signal stays safe. C costs a zombie for each waited child until its deadline, and zombies count against `pids.max`."
- **Web/Scripting** — A. "For a scripter the rule is "a limited command's tree is gone when the command ends", and A is the only option where that holds for every call site: `run`, `spawn` with an early `wait`, with a late `wait`, and with no `wait`. I proposed B only as a fallback, in case nobody would commit to seeing the leader's exit without a reap. sys has now shown it is cheap (pidfd POLLIN on Linux, kqueue NOTE_EXIT on macOS), so B's "first of three points" just adds a rule users must learn and SO answers must explain. C would have the ticket's example take the full timeout for a command that finished at 0 s."
- **PLT** — A. "A makes how long the leftovers live a property of the child alone: they end at min(leader exit, deadline), plus grace. That is true for `run`, for an early `wait`, for a late `wait` and for no `wait`. Under B a late `wait` gives the leftovers a longer life, which is the observer dependence that Q2 of the original panel voted down 6-0, and "may add a fourth point" makes the result depend on the implementation. A rule that an implementation may or may not follow is not a rule. The cost (the watcher starts for any limited child) falls only on programs that set a limit."
- **DevOps/Tooling** — A. "under B, an unwaited `spawn` leaves its leftovers alive until the deadline. So "why did my background process die 30 s after its parent was gone" stays a support question, and the answer depends on whether someone called `wait`. Under A, the one rule a user, a doc and a trace line all state is "a limited child's tree ends at its leader's end plus `grace`, or at the deadline, whichever is first", for every caller. pidfd and kqueue `NOTE_EXIT` make it exact on both targets, with no polling."
- **AI/ML** — A. "The rule a model learns is "the tree ends with the leader or at the deadline, whichever is first". A holds that rule on every path. B adds "or when you `wait`", which ties how long the tree lives to whoever waits on it, and we rejected that in Q2 of the limits vote. Under B, `spawn` with no `wait` and `run` give different leftover lifetimes for the same command, and the code shows no sign of it. The cost is a lazy watcher for every limited child, and a program that sets no limit still pays nothing."
- **Minimalism** — B **(dissent)**. "B promises only what the runtime already does. Leftovers end at whichever comes first: `wait`, the deadline, or program exit. A adds a watcher for every limited child, including `memory`-only and `processes`-only children that have no clock today. It also needs a second exit-watch mechanism on each OS (pidfd, kqueue) and turns a free bound into spec text. Under B, a `memory`-only or `processes`-only child that nobody waits on is still capped by its cgroup, and the deadline still bounds every timed child. Nothing goes unbounded. An implementation can add the leader-exit point later without a spec change."

##### Q2. When `run` or `wait` return `Err(EPERM)` — E1 (5-1)

E1: as soon as the runtime knows it cannot signal the leader; `timeout + grace + δ` stays the upper bound. E2: at `timeout + grace + δ`.
- **Systems** — E1. "web's argument for E2 ("the runtime can only tell that enforcement failed once the leader is still alive at the end of the grace") no longer holds after V10-4: the runtime signals the leader by pid, and that `kill` returns EPERM at the deadline. SIGKILL needs the same permission as SIGTERM, so waiting `grace` cannot change the outcome. It only adds 2 s of dead wait. E1 is still inside the timeout + grace + δ bound, so the documented bound holds with no exception."
- **Web/Scripting** — E1. "My E2 argument rested on "a group `kill` that reaches any member succeeds". The settled V10-4 tests the signal to the leader itself, and that test fails at the deadline, so the runtime knows at about 1 s. Holding a known failure for another `grace` makes the user wait for nothing. Fast failure is what JS and Python devs expect. timeout + grace + δ stays the upper bound, so the documented promise is unchanged."
- **PLT** — E1. "Under V10-4 the runtime signals the leader by its own pid (pidfd_send_signal or kill(pid)), not only through the group, so EPERM is known at the deadline. web's "can only tell once the leader is still alive at the end of the grace" assumed the group call alone. E1 also decides at the moment of the event. Under E2 a leader that we could not signal and that then exits on its own during the grace leaves the end unclear: `Limit(Timeout)` by the grace rule would credit a limit that never reached it. E1 commits to `Err` when enforcement fails, and timeout + grace + δ still bounds every return."
- **DevOps/Tooling** — E1. "V10-4 settled that the runtime tests the leader itself, so at the deadline it already knows that enforcement failed. Waiting `grace` more only delays a known error. The sooner the `Err` arrives, the closer it is in time and in logs to its cause. timeout + grace + δ stays the documented upper bound, so no promise changes."
- **AI/ML** — E1. "I backed E2 only because a group `kill` that reaches any member hides a failure for the leader. V10-4 now tests the signal to the leader itself, so the runtime knows at the deadline, and waiting `grace` for a SIGKILL that will also fail gains nothing. The bound "by timeout + grace + δ" stays true as an upper bound, so there is no new rule to learn. Code also gets its notice 2 s sooner."
- **Minimalism** — E2 **(dissent)**. "under E2, every limited `run` or `wait` returns at timeout + grace + δ, with the runtime finished with the group. E1 returns while the runtime still owes the rest of the group a SIGKILL, which it must send in the background. That is new state for a path that cannot be tested without privilege. The 2 s gained only matters in the pkexec/doas case, which is rare."

##### Q3. A `blink check` warning for a `ChildLimits` literal that sets only `grace` — Yes (4-2 in Phase C, 6-0 after Phase D)

Not spec text. Yes files a tooling ticket. No drops it.
- **Systems** — No. "a `grace` with no limit costs nothing at runtime. (3) makes it the same as `ChildLimits {}`: no own group and no watcher. A warning code and its doc entry are upkeep for a case that cannot fail."
- **Web/Scripting** — Yes. "`ChildLimits { grace: Duration.seconds(10) }` reads as "give my child 10 s to clean up", and it silently does nothing. That is a classic "why is my setting ignored" SO question. A warning on a literal only (no `timeout`, `memory` or `processes` named) has no false positives, so it costs one doc entry."
- **PLT** — Yes. "A literal that names only `grace` is a field with no effect that the reader can see at the call site, and a lint scoped to the literal cannot give a false positive on the `run_capped` pattern. It costs nothing at run time and is not spec text."
- **DevOps/Tooling** — Yes. "a field that silently does nothing is the kind of mistake that only a tool can catch: the code reads as "give it 10 s to clean up" and the runtime ignores it. The rule is syntactic (no `timeout`, `memory` or `processes` field named in the literal), so it has no false positives on the `run_capped` pattern, and the LSP can show it inline with a fix: add `timeout`."
- **AI/ML** — Yes. "`ChildLimits { grace: Duration.seconds(10) }` with no limit is exactly the literal a model writes when it reads `grace` as "a soft timeout". A warning at check time is the cheapest feedback loop, and it corrects that reading where the code is written. It fires only on a literal, so it has no false positives at run time."
- **Minimalism** — No. "(3) already says a `grace`-only literal behaves like `ChildLimits {}`, so the warning catches no failure. It costs a diagnostic code, a doc entry and a lint rule to maintain. The lint would also miss computed limits, so it covers only part of the case."

#### Phase D — Round 2

Phase D took Q3 only, because Q1 and Q2 were decided. Each seat read the reasoning of both sides and voted again. Systems and Minimalism changed from No to Yes. The text is the seat's own reasoning, whole.
- **Systems** — Yes (changed from No). "My Phase C concern already named the failure: a user who sets only `grace` thinks the child has a bound, and it has none. aiml's point is right: `grace: 10s` reads as "a soft timeout". The cost of that mistake is a child with no deadline, not a no-op. My "cannot fail" was about the runtime. The program can still fail. The lint runs at check time only, so it adds no runtime cost and no codegen change, and that answers my upkeep objection from my own seat. min's point that the lint misses computed values is true, but the case it covers, a literal that names only `grace`, is the one people write by hand."
- **Web/Scripting** — Yes (kept). "sys says this "cannot fail", and min says it "catches no failure". Both are true of the runtime and miss the bug: the program fails, because the user meant to bound the child and did not. min's own concern says it well: the user "finds out only when a child they meant to bound runs on". That is a runaway job in CI found hours later, when one warning at the call site would have caught it. "It misses computed limits" is not a reason to drop the lint: it fires only where it can be certain, and that is the case a person or a model types by hand."
- **PLT** — Yes (kept). "The No side says the literal "catches no failure" because (3) makes it equal to `ChildLimits {}`. That equality is the problem. The program means something different from what it does, and a warning exists to show exactly that gap. A failure at run time is not the bar. min says the lint "would miss computed limits". That is true, and that is how it should be: a lint scoped to the syntax gives no false positives. A sound lint that covers part of the case is better than none, and a doc comment does not reach a reader who never hovers."
- **DevOps/Tooling** — Yes (kept). "sys and min say the warning "catches no failure". But their own concerns name the failure: "a child they meant to bound runs on". The failure is not at runtime; it is the gap between what the code says and what it does. That is exactly what a lint is for, and a doc comment the user never hovered does not close that gap. "It misses computed limits" is true of nearly every useful lint (unused-variable misses reflection too). The literal is the common form, and the one a model or a user writes from the docs. The upkeep is one syntactic rule on one type, with no type flow, so it is near the cheapest lint we could own."
- **AI/ML** — Yes (kept). "sys and min say "the case cannot fail". That is true of the runtime, but not of the program. The failure is that the child the user meant to bound runs on with no deadline, and min's own concern names it: the user "finds out only when a child they meant to bound runs on". A doc comment only helps a reader who hovers over `grace`. A model that writes the literal from a misread never sees the comment, but it does see a `blink check` warning in its edit loop. The upkeep is one code and one doc entry for a syntactic check on a literal. On min's "misses computed limits": partial coverage of the one shape a person or model actually writes is still worth having, and it gives no false positives."
- **Minimalism** — Yes (changed from No). "In Phase C my own concern was the Yes case: "a user who believes `grace` alone does something gets no signal". aiml showed that this misreading is the likely one: `grace` read as "a soft timeout". plt's scope answers my "misses computed limits" point. The lint fires only where the no-op shows in the literal, so it costs no false positives, and a check that covers part of the case is still worth having when that part is the common one. It is a tooling rule, not language surface, so my budget objection is weaker than I gave it credit for."

Result: 6-0 Yes.

#### Dissents

- **Q1 (Minimalism, B).** "B promises only what the runtime already does. [...] An implementation can add the leader-exit point later without a spec change." Concern: "a long-running program that spawns `memory`-only children and never waits on them keeps their leftovers alive until it exits, and users may read that as a leak."
- **Q2 (Minimalism, E2).** "under E2, every limited `run` or `wait` returns at timeout + grace + δ, with the runtime finished with the group. E1 returns while the runtime still owes the rest of the group a SIGKILL, which it must send in the background." Concern: "a reader may think the caller pays `grace` for nothing when SIGTERM to the leader already failed, and later ask for E1 as an "optimization" without moving the background-SIGKILL duty."

### Final Spec

The text is in §4.4.8. In short:

```blink
let r = process.run("sh", ["-c", "sleep 30 & exit 0"],
    limits: ChildLimits { timeout: Some(Duration.seconds(5)) })?
// returns at about 0 s; Ok; r.end == Exited(0); no `sleep 30` is alive
// with `trap '' TERM` in the leftover: returns at about 2 s (grace)

let c = process.spawn("sh", ["-c", "sleep 600 & exit 0"],
    limits: ChildLimits { memory: Some(256 * 1024 * 1024) })?
// nobody waits: the sleep still ends right after sh exits (plus grace)

let p = process.run("pkexec", ["sleep", "600"],
    limits: ChildLimits { timeout: Some(Duration.seconds(1)) })
// default grace 2 s: Err with code EPERM at about 1 s; the child may still be alive
```

- **Leader exits first.** When `run` or `wait` sees the leader exit, the runtime ends the rest of the group or cgroup: SIGTERM, then SIGKILL after `grace`. Then it reads the pipes to end of file and returns. Output that a leftover writes after the leader exits is lost. A process outside the group that holds a pipe (after `setsid`) does not hold `run` back: `run` closes the pipe at the bound.
- **`end` stays the leader's end.** A deadline that fires when the leader has exited but is not yet reaped signals the group, and `end` stays `Exited(c)`. Ending only leftovers never changes `end`.
- **`Limit(Processes)` after a refused fork.** `end` is `Limit(Processes)` when the limit refused a fork in the tree before the runtime first sees the leader exit, even if the leader then exits on its own. A refusal by a leftover after the leader ended does not count.
- **Q1: every path.** The tree of a limited `spawn` ends at the first of the leader's exit and the deadline, then SIGTERM, `grace`, SIGKILL, whoever waits (no `wait`, an early `wait`, a late `wait`), also for `memory`-only and `processes`-only children.
- **Q2: `EPERM`.** `Err` with code `EPERM` if and only if the signal to the leader itself fails. It returns as soon as the runtime knows, in practice at the deadline. `timeout + grace + δ` stays the one upper bound; the early return is a note. The rest of the group still gets SIGKILL after `grace`, in the background. A later `wait` blocks with no bound and returns the real end; for `run`, the runtime reaps the child in the background. No start-time `ENOTSUP` for a set-user-ID program. `EPERM` means that the limit could not be enforced and the child may still be alive.
- **Program exit.** At a return from `main`, `exit`, a panic, SIGINT, SIGTERM or SIGHUP, each limited group still alive gets SIGTERM, then SIGKILL after that child's `grace`. Every limited group or cgroup still populated is ended. A second SIGINT or SIGTERM sends SIGKILL to every limited group at once. SIGHUP starts the exit path only with its default disposition; a signal ignored at program start stays ignored. A limited `run` or `spawn` that races the exit blocks until the program ends. Other threads keep running user code during the exit grace. The exit loop treats `EPERM` and `EACCES` on a group as done.
- **`grace`-only.** A `ChildLimits` that sets only `grace` behaves exactly like `ChildLimits {}`: no own group, no watcher. The `grace` doc comment says it has no effect when no limit is set, and that it applies only to ends that the runtime starts.
- **Clock.** The deadline clock is monotonic. Suspend does not count. The `timeout` doc comment drops "Wall-clock".
- **Error order.** A call with both a bad value and an unsupported limit gives `EINVAL` first.
- **`ENOTSUP`.** `ENOTSUP` exactly when `process.can_limit` is `false` for a requested kind. When the host supports a limit and applying it fails, the call gives the real errno, and no child starts.
- **cgroup membership.** The runtime never moves a process that it did not start into a cgroup. The cgroup check is true only when every process in this program's cgroup is this program or one of its descendants. `systemd-run --scope sh -c prog` gives `ENOTSUP` for `memory` and `processes`; `systemd-run --scope sh -c 'exec ./prog'` works.
- **`processes` hit.** It ends the tree at once, with no grace.
- **SIGKILL to this program.** Nothing ends the descendants of a limited child, on any OS, with or without a cgroup. The old sentence "its descendants end only when they are in the cgroup of the child" is removed.

### Implementation notes

These items are not spec text. They go to the implementation ticket.

- Leader-exit watch without a reap: pidfd (Linux), kqueue `EVFILT_PROC NOTE_EXIT` (macOS). One fd per live limited child, counted in the fd budget, with a fallback to SIGCHLD + `waitid(WNOWAIT)`. Never fail the spawn for it (Systems). No quiet fallback to B on a target without it (PLT).
- A setuid exec during the grace that makes the final SIGKILL fail gives `Err(EPERM)` at `timeout + grace + δ`, not `Limit(Timeout)` (Systems).
- A corpus test of an unwaited `spawn` per OS (AI/ML). The runtime trace logs each leftover end (DevOps/Tooling).
- cgroup picks that the spec does not state: (b) only `memory` and `processes` get a cgroup; (d) kernels without `pids.events.local`; (e) a `memory` event wins when both events show at once; (g) `processes >= PIDS_MAX` writes `max`; (j) `memory.oom.group=1`. Where §4.4.8 already states one of these, it stays as it is.
- Tooling: the grace-only lint. Its scope is a bare `ChildLimits` literal with no spread that names `grace` and none of `timeout`, `memory`, `processes`. It never fires on `ChildLimits {}` or on values from variables.
