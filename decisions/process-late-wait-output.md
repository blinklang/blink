[< All Decisions](../DECISIONS.md)

# Late Wait on a Limited Child — Design Rationale

**Question.** §4.4.8 says that a deadline holds whether or not anyone waits. It says nothing about the output that a limited child writes before a late `process.wait`. The runtime reads the pipes of a child only inside `wait` and `run`. So a limited child that writes more than its pipe holds blocks in `write` until its deadline ends it, and a late `wait` gives `Limit(Timeout)` with only the first pipe-full of output. The same program gives `Exited(0)` with all the output when the pipe is larger. What must a late `wait` keep?

```blink
let lim = ChildLimits { timeout: Some(Duration.ms(1200)), grace: Duration.nanos(0) }
let c = process.spawn("sh", ["-c", "head -c 50000 /dev/zero | tr '\\0' x"], limits: lim)?
let _ = process.run("sleep", ["1.5"])?
let r = process.wait(c)?
// pipe of 8 KiB: Limit(Timeout) and 8192 bytes; pipe of 64 KiB: Exited(0) and 50000 bytes
```

**Answer.** From spawn on, the watcher also reads both pipes of a limited child into a buffer of that child. It stops where `run` stops. `wait` takes the buffer. A late `wait`, an early `wait` and `run` give the same `end` and `out` on every host, and there is no byte bound. The example gives `Exited(0)` and 50000 bytes on a pipe of any size. A child with no limit is not read before `wait`: it can block in `write` on a full pipe until `wait` reads it, and its `end` and `out` do not change. `timeout + grace + δ` holds while a child writes without end. See *Final Spec*.

### Panel Deliberation

Six seats voted: Systems, Web/Scripting, PLT, DevOps/Tooling, AI/ML and Minimalism. Phase A gave two options for Q1 (D by five seats, F by Systems), so no Phase B ran. Phase C was a silent vote and all votes were the same, so no Phase D ran. The quotes come from the seats' own text. The seats all rejected "do nothing" (the host pipe is the bound), so that question was not on the ballot.

#### Phase A — Independent proposals

Each seat proposed alone. The quotes are excerpts from the seats' own proposals.

- **Systems:** "The bug is not "output is lost". It is that **the kernel's pipe size, a value that depends on host state, decides `end`**." Its pick was "Proposal S1 (my pick): a fixed floor buffer, read by the watcher" (option F below).
- **Web/Scripting:** "Today a late wait changes the end from `Exited(0)` to `Limit(Timeout)`. That is the observer dependence that two panels voted down 6-0 and 5-1."
- **PLT:** "wait(spawn(c)) at any time t  ==  run(c)        (same `end`, same `out`, same `err_out`)"
- **DevOps/Tooling:** "This is the worst kind of failure for an operator: green on the laptop, red in CI, and the result names the wrong cause (`Limit(Timeout)` for a child that would have finished in 5 ms)."
- **AI/ML:** "So the test I use is: can a reader predict `end` and `out.len()` from the program text alone?"
- **Minimalism:** "Add no surface. No new field, no new type, no new limit."

The ballot had two questions.

- **Q1.** What does the runtime read for a limited spawned child before `wait`? **D**, drain with no bound (Minimalism M1, PLT A, Web W1, DevOps A, AI/ML P1): the watcher reads both pipes of a limited child into a buffer of that child, until the point where `run` stops. **F**, a fixed floor (Systems S1): the watcher reads each stream up to 64 KiB, then stops reading, and the child may block on the kernel pipe.
- **Q2.** Does a child with no limit get the same early read? **U0**, no. **U1**, yes (AI/ML P2, its second choice).

#### Phase C — Final vote

Phase C was a silent vote. Each seat gave a vote, its reasoning and one concern. The text is whole, from the seat's ballot. Systems changed its vote on Q1 from F to D, and said why in its own words: "I change from my own F." and "devops is right about F: what F keeps is N plus the kernel pipe, so the amount stays host-dependent, and past N the end still flips to `Limit(Timeout)`. F only moves the cliff."

- **Q1: What does the runtime read for a limited spawned child before `wait`?** (D, 6-0)
  - **Systems:** Vote: D (drain, no bound). I change from my own F.
    - Reasoning: "devops is right about F: what F keeps is N plus the kernel pipe, so the amount stays host-dependent, and past N the end still flips to `Limit(Timeout)`. F only moves the cliff. My core value is behavior that is the same on every host, and only D gives that in full. My memory objection is weaker than I said in Phase A. A limited child can write only until `timeout + grace + δ` or its leader's exit, so the buffer has a bound in time. It is the same memory that `run` and an early `wait` already hold, and the existing rule that reaps an unreachable `Child` frees it."
    - Concern: "the drain must not delay a deadline signal. A watcher thread that also pumps a fast 1 GiB writer can be late with SIGTERM or SIGKILL for every other limited child. So the runtime must read in bounded chunks for each poll round, or on a thread apart from the signal path, and the `timeout + grace + δ` bound must stay true under load. I also support devops's follow-up for an output target or byte cap on every path, because D gives no way to cap memory for a child the program does not wait on."
  - **Web/Scripting:** Vote: D (drain, no bound)
    - Reasoning: "The 90% case is "spawn, do other work, wait". Under D, the answer is the same as `run` on every host, and a test author can trust it. F moves the cliff from the host pipe size to a fixed 64 KiB, and the default Linux pipe is also 64 KiB. So on a normal host F fixes almost none of the cases we measured: a 70000-byte child still flips to `Limit(Timeout)`, and its `out` length still depends on the host pipe. sys's memory point is real only while the program still holds the `Child`, and a held `Child` is one the program means to `wait` on. Once nothing can reach the `Child`, the existing reap rule frees the buffer."
    - Concern: "A long-lived program that keeps many `Child` values it never waits on, from big-output limited children, holds all of that output, and nothing in the result warns it."
  - **PLT:** Vote: D (drain, no bound)
    - Reasoning: "D is the only option under which, for every limited child, a `wait` at any time gives the same `end`, `out` and `err_out` as `run` gives for that child. So the child alone decides its end, on every path and every host. F only moves the size cliff from the pipe to N. Past N the end again depends on when the wait comes, and the amount kept is N plus the host pipe, so the host is back in the result (devops's point holds). Under D the bound on memory is the bound §4.4.8 already sets on time. A program that keeps a `Child` it never waits asked for that output, as `run` does."
    - Concern: "If the watcher reads and signals in one loop, a child that writes fast could delay a deadline signal past δ. The implementation must send signals before it reads, and a test must prove that a deadline fires on time while a child writes without end."
  - **DevOps/Tooling:** Vote: D
    - Reasoning: "An operator must be able to trust `end`. Under F a limited child that writes 70 KiB still gets `Limit(Timeout)` on a late wait, because nobody read the pipe. So F moves the flake from 64 KiB to 64 KiB plus the kernel pipe, and the bytes kept still depend on the host. D is the only option where `end` and `out` for a late wait are the same as for an early wait on every host. That way a test author can write a 1 MiB row and know it means the same thing in CI as on a laptop. The memory D holds is the memory `run` already holds, and the program asked for it when it piped the output."
    - Concern: "A long-lived service that spawns many chatty limited children and never waits keeps all their output until reap or exit, and an operator sees that only as RSS growth. The spec and the CHANGELOG line should say plainly that unwaited output is held, and the output-target/byte-cap feature ticket should be filed in the same change."
  - **AI/ML:** Vote: D (drain, no bound)
    - Reasoning: "With D, a reader of the program text can predict `end` and `out.len()` with no knowledge of the host, which is the test I set in Phase A. F moves the cliff from 64 KiB to 64 KiB + pipe size, but a cliff stays, and its edge is still host-dependent (devops's point). A model must then learn a number, and a test that writes 200 KiB still flips between hosts. D gives one rule on three paths, and `out` keeps its doc line, "everything the child wrote"."
    - Concern: "A long-running program that spawns many limited, loud children and keeps their `Child` values with no `wait` holds that output until exit. The spec must state this in one plain sentence, next to the advice to wait on every `Child`, so the cost is visible."
  - **Minimalism:** Vote: D (drain, no bound)
    - Reasoning: "D adds no surface and gives one result on every host, which follows from the rules we already voted: observer independence, and `out` holds everything the child wrote. F adds a number to the spec and still lets the end flip once output passes N plus the pipe size, which is host-dependent. So F keeps a smaller copy of the bug and adds a rule people must learn. The memory that D holds is memory the program asked for: `run` holds the same 1 GiB, and `> /dev/null` or `| head -c N` solves it by convention."
    - Concern: "a long-lived program that spawns many limited children which write a lot and are never waited can hold a lot of memory until reap or exit. If real code hits this, the devops output-target follow-up is the fix, not a cap in this rule."

- **Q2: Does a child with no limit get the same early read?** (U0, 6-0)
  - **Systems:** Vote: U0 (no early read for a child with no limit).
    - Reasoning: "a child with no limit has no deadline. A full pipe changes only when it ends, never its `end` or its `out`, so the ticket's harm does not occur. U1 would give every spawned child a reader and a buffer with no bound, and a child that writes forever with no `wait` would grow memory without end. It also breaks the decided rule that a program which starts no limited child starts no watcher and pays nothing."
    - Concern: "a user can read "limited children never block on their pipe" and expect the same of an unlimited child that is never waited. The spec must say plainly that such a child can block in write until `wait`."
  - **Web/Scripting:** Vote: U0 (no)
    - Reasoning: "With no deadline, a blocked write changes only the time, not `end` or `out`, so the ticket's harm does not happen. A program that sets no limit must keep paying nothing; that was the deal that got the watcher passed 6-0. Draining every child (Go-style) is a broader change and needs its own ticket."
    - Concern: "A user may see a limited child and an unlimited child act differently when nobody waits on them (one drained, one blocked), and may read that as a bug if the spec does not say why in one line."
  - **PLT:** Vote: U0 (no)
    - Reasoning: "With no limit there is no deadline and no leader-exit rule, so a block in write changes only the time, never `end` or `out`. The rule that every path gives the same result already holds there. U1 adds a buffer that can grow with no bound in time (nothing ends an unlimited child), and it adds a cost to programs that set no limit, for no change a program can see."
    - Concern: "A reader may take "limited children never block on a pipe" to mean all children, so the spec must state in one line that an unlimited child may block until `wait`."
  - **DevOps/Tooling:** Vote: U0
    - Reasoning: "With no deadline, a full pipe changes only the time, not `end` or `out`, so the ticket's harm does not occur. U1 adds a thread and an unbounded buffer to every program that spawns, including one that sets no limit, and this panel decided the watcher is pay-only-if-limited. U1 also gives a child that writes forever with no wait unbounded memory, where today it only blocks."
    - Concern: "A user who sees limited children drained may expect the same for unlimited ones and build a deadlock (spawn unlimited, never wait). The spec should say in one line that only a limited child is read before `wait`."
  - **AI/ML:** Vote: U0 (no early read for a child with no limit)
    - Reasoning: "The ticket's harm is a changed `end`, and with no deadline the `end` and `out` of a child do not change: only the timing does. U1 would put a reader in every program that spawns, and memory with no bound for a child that writes without end. I withdraw my P2 as second choice."
    - Concern: "A model may expect an unlimited spawned child to progress with no `wait` (for example a server that logs a lot before it writes a file the test reads), so the spec needs an example that shows the child pause on a full pipe until `wait`."
  - **Minimalism:** Vote: U0 (no early read for a child with no limit)
    - Reasoning: "with no deadline, a full pipe changes only the time, never `end` or `out`. So U0 has no harm to fix, and U1 would put a reader and an unbounded buffer on every program that sets no limit. This matches the lazy-watcher rule: you pay only when you ask for a limit."
    - Concern: "a reader may expect a late `wait` to work the same for limited and unlimited children. The spec must say in one line that the unlimited child waits on its pipe and loses nothing."

AI/ML's second choice on Q2 was U1 in Phase A. It wrote in Phase C: "I withdraw my P2 as second choice."

### Final Spec

```blink
let lim = ChildLimits { timeout: Some(Duration.ms(1200)), grace: Duration.nanos(0) }

let c = process.spawn("sh", ["-c", "head -c 200000 /dev/zero | tr '\\0' x"], limits: lim)?
let _ = process.run("sleep", ["1.5"])?
let r = process.wait(c)?
// limited, late wait: r.end == Exited(0), r.out.len() == 200000, on every host

let u = process.spawn("sh", ["-c", "head -c 200000 /dev/zero | tr '\\0' x"])?
let _ = process.run("sleep", ["1.5"])?
let v = process.wait(u)?
// no limit: u blocks in write until wait; v.end == Exited(0), v.out.len() == 200000
```

- From spawn on, the watcher reads both pipes of each limited child into a buffer of that child. It stops where `run` stops: the leader exit then the read to end of file, or `timeout + grace + δ`.
- `wait` takes the buffer. A late `wait`, an early `wait` and `run` give the same `end`, `out` and `err_out` on every host. The pipe size never decides the end.
- There is no byte bound. The program holds the output until `wait`, until the runtime reaps an unreachable `Child`, or until the program ends. The spec says so next to the advice to wait on every `Child`.
- The watcher still never reaps a child.
- `timeout + grace + δ` holds while a child writes without end. The mechanism is not in the spec.
- A child with no limit gets no early read, no watcher and no buffer. It can block in `write` until `wait` reads both pipes; its `end` and `out` do not change.
- `ProcessResult.out` stays "everything the child wrote". No new field.
- Follow-up from DevOps/Tooling, backed by Systems and Minimalism: a feature for an output target (inherit, discard or file) or a byte cap, on every path including `run`.
