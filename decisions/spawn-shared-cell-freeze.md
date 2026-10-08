[< All Decisions](../DECISIONS.md)

# Shared Cells in a Spawned Task — Design Rationale

The old §2.8 sentence "Immutable captures in `async.spawn` are safe — the value stays valid while the closure can run, and no mutation means no data race" was false. An immutable `let` can reach a List, Map or Set that a `let mut` alias or a `mut` parameter changes. `async.spawn` runs on real threads, and collections have no locks. A concurrent `push` can realloc the buffer under a reader. A probe program with this shape passed `blink check` with no diagnostic.

Governs: `sections/02_syntax.md` §2.8 *Closures and `async.spawn`*; `sections/03_types.md` §3.6 *Shared cells*; `sections/04_effects.md` §4.13 *Channel operations*, §4.15.4.

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in independent-proposal → dedupe → debate → vote rounds. Phase A gave independent proposals. Phase A.5 merged them into four Q1 options (F freeze, S snapshot, H honest spec, T static type rule), three Q2 options (E error, W warning, N none), a channel question (Q3) and a help-text question (Q4). Phase B ran one debate round. Phase C was a silent vote. Q1 ended 4-2 and Q2 ended 2-2-2, so Phase D reran those two questions with one more debate round and a final silent re-vote. Q3 and Q4 were not reopened. The user (BDFL) signed off on the tally.

#### Phase A — Independent proposals

- **Systems:** freeze every shared cell a spawned task reaches, release at join. *"A compile-time rule alone cannot make the §2.8 sentence true. I propose a runtime guarantee as the base and a compile-time check on top."* On the release point: *"the spawner's thread does the release, in program order. So a panic depends only on source order and never on scheduler timing."* On cost: *"On a mutating call: one load and one well-predicted branch. Capacity checks already cost about the same."* and *"Reads cost nothing."* Also proposed extending E0650 to direct aliases (S2), *"a lint over S1, not the guarantee"*.

  ```blink
  let rows = [1, 2, 3]
  let mut alias = rows
  async.scope {
      let h = async.spawn(fn() { rows.len() })
      alias.push(4)          // panic: shared cell changed while a spawned task holds it
      io.println("{h.await}")
  }
  alias.push(4)              // OK: freeze ended at await / scope exit
  ```

- **Web/Scripting:** a spawned task gets a snapshot (copy) of the shared cells it reaches. *"The fix has to be about what the task receives, not about which names it captures."* On familiarity: *"It is how `postMessage` to a Web Worker works (structured clone). It is also how Python `multiprocessing` works (pickle) and how Erlang sends messages."* Ranked the lint-plus-honest-spec fallback last: *"undefined behavior is not "just works"."* Also proposed that `channel.send` snapshots.

  ```blink
  let mut log = ["start"]
  let view = log
  async.scope {
      let h = async.spawn(fn() { view.len() })   // task sees ["start"]
      log.push("more")
      io.println("{h.await}")                    // prints 1, always
  }
  ```

- **PLT:** freeze at spawn, release at join. *"A List, Map or Set push can move the storage while another thread reads it. That makes this a memory-safety hole, not a logic bug. I reject any fix that only rewords "safe" as a duty for the programmer."* Probes showed the race enters through a `mut` parameter and through a channel, so *"a rule that only tracks aliases cannot be sound"*. Fallback was a static rule that rejects a `let` capture whose type reaches a shared cell. Flagged that handlers in force at a spawn site are the same race.

  ```blink
  let xs = [1, 2, 3]
  let mut ys = xs
  async.scope {
      let h = async.spawn(fn() { xs.len() })
      ys.push(4)              // panic: cell is shared with a running task
      io.println("{h.await}")
  }
  ys.push(4)                  // OK: the task was joined
  ```

- **DevOps/Tooling:** freeze at runtime plus a warning when the compiler sees the write. *"A fault shows up as a panic, not as silent corruption. Any message that names both sites beats a segfault in `realloc`."* Proposed a panic message that names both sites:

  ```
  panic: write to a list that a spawned task can read
   --> app.bl:6:9
    |
  6 |         ys.push(4)
    |         ^^^^^^^^^^ write to a read-only list
    = note: the task spawned at app.bl:5:17 captured `xs`, which shares this list
    = help: build a new list for the task, or send values over a channel
  ```

  Noted that *"The `MutAliasOfImmutable` warning in §3.2.2 is not built: there is no code for it in `src/`."*

- **AI/ML:** copy every shared cell at each task boundary (spawn, send, await result). *"Capture is one way across a task boundary. `ch.send(xs)` is another, and `h.await` returning a List is a third."* On the failure mode: *"Leaving a race on an unsynchronized List as undefined behavior. `push` can reallocate, so the race breaks memory safety. That is not acceptable for a language that AI generates code in."* Found that *"`xs.clone()` on a `List[Int]` fails"* in gen1, so today's E0650 help does not work for a List.

  ```blink
  let xs = [1, 2, 3]
  let mut ys = xs
  async.scope {
      let h = async.spawn(fn() { xs.len() })   // task gets its own copy of xs
      for i in 0..100000 { ys.push(i) }        // no race: the task's copy does not change
      io.println("{h.await}")                  // prints 3
  }
  ```

- **Minimalism:** delete the false sentence, state the race honestly, add no new error. *"The bug is not in closure capture. Shared cells cross task boundaries in other ways too."* Proposed spec text: *"If one task changes a shared cell while another task can read or change it, that is a data race, and the program has a bug. A racing read returns an unspecified value, or the program panics. It stays memory-safe."* Owned the cost: *"P1 is honest, but the compiler does not catch the race."*

  ```blink
  let snap = xs.slice(0, xs.len())   // new cell; clone() does NOT copy (§3.6.1)
  async.spawn(fn() { process(snap) })
  ```

#### Phase B — Debate highlights

**Honest spec (H) lost its memory-safety claim.** Systems, PLT, DevOps and AI/ML each said the runtime cannot keep "stays memory-safe" for free. PLT: *"A racing `push` can publish a new `len` before the new buffer. To stop a torn read, every write must publish its header atomically, in single-thread code too."* and *"Go is not memory-safe under races"*. Minimalism withdrew H:

> *"My H rests on one sentence: "it stays memory-safe". Sys, plt and aiml are right that a `push` can realloc under a reader. […] When the cheaper option is also the sounder one, minimalism picks it."*

**F-end moved to join.** DevOps first proposed "until the task ends". Systems, PLT, web and AI/ML all objected. DevOps changed:

> *"if the freeze ends when the task ends, the same test passes or panics depending on how fast the worker runs. A flaky panic is the worst diagnostic there is. It does not reproduce in CI, and an agent cannot fix what it cannot repeat. With release at `h.await` or scope exit, the panic depends only on source order."*

**Static rule (T) rejected by all.** PLT: it *"also rejects §2.8's own `process(data)` example when `data` is a List"* and *"Users have no escape: there is no deep clone"*.

**Snapshot vs freeze.** Web: *"Each one walks the reachable cells at spawn, marks them, and checks a flag on each write. On a marked cell, F panics and S copies the storage. […] So the only real question is what the user sees when they write: a panic or correct output."* Systems answered:

> *"S costs what F costs, and on a hit it adds an O(bytes) copy that the source does not show. Where F gives a deterministic panic at the bad write, S gives a silent latency spike."*

Minimalism, against S: *"S would make spawn the one place in the language where a value deep-copies, and do it implicitly. That is a second copy model."*

**AI/ML dropped copy at `await`.** *"When `h.await` returns, the task has ended, so nothing can race on the returned value. A copy at await is redundant."*

**Channels.** PLT first proposed that `ch.send` freezes for good, then withdrew:

> *"I admit that F at `send` is F's weak spot. A send has no join point, so the freeze would last for good, and the receiver could never change what it gets."*

Web showed the batching loop that freeze-for-good breaks:

```blink
let mut batch = List[Row].new()
for row in rows {
    batch.push(row)
    if batch.len() == 100 {
        ch.send(batch)
        batch.clear()   // under PLT's rule: panic, for the rest of the program
    }
}
```

PLT moved to *"freeze at spawn (the scope gives a join) and copy at send (there is no join)"*. DevOps and Systems also moved to copy at send. Minimalism wanted to defer.

**Q2 shifted.** Systems moved from E to W (*"a check which does not follow control flow gives false errors under F-end at join"*). DevOps then moved from W to E, narrowed to the spawn-to-join window: *"A sure panic should be a compile error"*. Web and AI/ML moved to W under F. Minimalism stayed at N: *"A partial compile-time check adds rule text and gives a false sense of coverage."*

#### Phase C — Final vote

**Q1 — rule for a shared cell a spawned task reaches.** F 4, S 2, H 0, T 0.

- Systems: **F** — *"F gives a panic tied to the source, released in program order at join. S instead does an O(bytes) copy the source does not show. S also needs a deep-copy primitive that exists nowhere else in v1."*
- PLT: **F** — *"F is sound with no new primitive. […] The rule also covers the cases no static rule can see: `mut` parameters, struct fields, and writes from inside the task."*
- DevOps: **F** — *"F gives the one failure that tools can work with: a panic at the bad write, in the same place on every run"*.
- Minimalism: **F** — *"F adds no syntax, no type, no trait and no copy primitive. It adds one runtime idea ("frozen") and one sentence in §3.6"*.
- Web: **S** *(dissent)* — *"They differ only in what a write does. F panics, and S gives correct output. A JS or Python developer expects a worker to get a copy"*. Concern: *"users will hit panics on writes far from any spawn. The panic message must name the spawn site and the captured name"*.
- AI/ML: **S** *(dissent)* — *"S gives a generated program the result most models already expect from JS Workers, Python multiprocessing and Erlang: the task sees the value as it was at spawn, and nothing panics."* Second choice F. Concern: *"models will generate parent-side writes before `await`, and those writes panic at run time."*

**Q2 — compile-time check for a direct `let mut` alias.** E 2, W 2, N 2.

- Systems: **E** (narrowed to a write through the direct alias after the spawn and before the join) — *"A sure panic the compiler can see should be an error, the same reasoning as Rust's deny-by-default `unconditional_panic`."*
- DevOps: **E** — *"A sure runtime panic that the compiler can see should be a compile error, so the editor shows it before CI does."*
- PLT: **W** — *"A partial check should not be an error, because an error reads as a judgment of the type system and implies it is complete. F is the guarantee."*
- AI/ML: **W** — *"An error (E) teaches models that the check is complete, and it misses `id(a)`, `W { xs: a }` and `mut` parameters."*
- Web: **N** — *"Under F, the runtime already catches the probe every time. A compile-time check also needs `MutAliasOfImmutable` tracking, which has no code yet"*.
- Minimalism: **N** — *"E or W means building alias tracking from zero for one diagnostic. […] Add it later as a lint if users ask. YAGNI."*

**Q3 — channel send of a value that reaches a shared cell.** Q3-copy 5, Q3-defer 1. Decided in Phase C. Not reopened.

- Systems: **Q3-copy** — *"A send has no join point, so freeze-for-good makes a received or reused buffer unwritable forever. […] A send is an explicit hand-off point that the reader sees, so one copy there is a cost the source shows."*
- Web: **Q3-copy** — *"The batching loop […] is common in pipeline code. Under freeze-for-good it panics. Today it silently clears the receiver's list."*
- PLT: **Q3-copy** — *"The one principle holds: freeze while a structured lifetime bounds the sharing, and copy when nothing bounds it."*
- DevOps: **Q3-copy** (shifted from freeze) — *"That is a diagnostic I cannot make friendly."*
- AI/ML: **Q3-copy** — *"Copy at send is coherent with S and with F (plt's shift), so it is the one channel rule that fits whichever Q1 option wins."*
- Minimalism: **Q3-defer** *(dissent)* — *"Both "decide here" options add real surface. Q3-copy brings in the deep copy primitive that I reject under S."* Concern: *"Deferring leaves `ch.send` as a known race and the obvious way around F"*.

**Q4 — E0650 note and help text.** Q4-a 5-1 under F (web and AI/ML picked Q4-b, but named Q4-a as their fallback if F wins; DevOps picked Q4-c). Phase C picks:

- Systems: **Q4-a** (fallback Q4-b if S) — *"The note "binding a List does not copy it" fixes the false part."*
- PLT: **Q4-a** (fallback Q4-b if S) — *"`let snapshot = count` stays correct for scalars. The note "binding a List does not copy it (§3.6)" fixes the false claim the current help makes."*
- Minimalism: **Q4-a** (fallback Q4-b if S) — *"Q4-c's "await the task before this write" belongs in F's runtime panic message, not in E0650."*
- Web: **Q4-b** (fallback Q4-a if F) — *"Under F, Q4-a is the most honest choice: it says that binding does not copy and gives a way out."*
- AI/ML: **Q4-b** (fallback Q4-a if F) — *"I rank Q4-c below Q4-a, because it puts `slice` before the channel advice, and that teaches a partial copy as the main fix."*
- DevOps: **Q4-c** *(dissent)* (fallback under S: Q4-b) — *"Under F the first fix for the panic is order ("await the task before this write"), not a copy."*

#### Phase D — Round 2 (Q1 and Q2)

Phase C left Q1 at 4-2 and Q2 at 2-2-2. The moderator reran both with one debate round and a silent re-vote.

**Debate highlights.**

Minimalism opened with a new point on Q1: Q3-copy had already put a deep copy in the language.

> *"My Phase C case against S was that it brings in a deep copy that Blink has nowhere else. […] Q3-copy passed 5-1, so that copy is now in the language at `send`. That argument against S is gone."*

> *"F + copy-at-send […] is one principle with two mechanisms. The minimal spec has one mechanism."*

PLT answered with the argument that held the F majority:

> *"Take a parent that writes to a cell it also gave to a task, for example a shared list of work, or a stop flag the parent sets later. That parent almost always wants the task to see the write. Under S, the task reads stale data and nothing reports it. Under F, the program panics at the exact line, on every run. A rule that turns a likely logic bug into silent divergence is the weaker rule."*

PLT on Q3-copy: *"At `send`, the copy shows in the source, there is no join that could bound a freeze, and the hand-off is explicit."* DevOps added: *"A model that sees "write to `log` while the task spawned at 12:5 reads it; await the task first" fixes the code in one step."*

Web set conditions for accepting F:

> *"I will move to F in the re-vote if the decision record binds these three points: 1. The panic names the write site, the spawn site and the captured binding. 2. §2.8 shows an "await, then write" example. 3. The handler seam (PLT) and the `List.clone()` gap are filed as tickets before the F text ships."*

AI/ML said it would not block F: *"F is sound and deterministic, and it was my second choice."*

On Q2, Systems and DevOps argued for E: *"The ballot limits E to a write that panics on every run that reaches it, so it never rejects a program that F accepts."* AI/ML refuted this:

> *"A write in an `if` arm or a loop body may not run, so it is only a possible panic. A check that sees only direct aliases gives an error for some writes and silence for `id(a)` or `W { xs: a }`. Models learn from that pattern that a clean compile means no race."*

PLT conceded (*"aiml's point is correct, and it refutes my Phase D claim"*). Web and Minimalism moved from N to W because §3.2.2 already specifies `warning[MutAliasOfImmutable]`. AI/ML: *"§3.2.2 already specifies `warning[MutAliasOfImmutable]`, so that tracking must exist anyway, and W reuses it."*

**Q1 re-vote.** F 4, S 2. No change from Phase C.

- Systems: **F** — *"plt's point decides it for me: under S, a parent's write that a task should see becomes stale data with no report. F turns it into one deterministic panic."* Concern: *"Each List/Map/Set mutation in every program pays one load and one branch. The decision record must measure that cost, not only assert it."*
- PLT: **F** — *"A copy at `send` happens at an explicit hand-off that the source shows. A copy at spawn happens because a closure names a variable, and the source shows nothing."*
- DevOps: **F** — *"S turns it into stale data that nothing reports."* Concern: *"If the panic text ships generic ("write to frozen cell"), users get web's "action at a distance" with no clue, and F loses its main tooling advantage over S."*
- Minimalism: **F** — *(changed back from a debate-time lean to S)* *"A language that puts correctness first should fail loudly, on the same line every time, rather than diverge in silence. F also keeps "a capture is a shared reference" as one meaning, and it keeps the deep copy at the one place the source shows it (`send`)."*
- Web: **S** *(dissent)* — *"Q3-copy passed 5-1, so a deep copy at a task boundary is already in the language. […] S + copy-at-send becomes one rule: "a shared cell that crosses a task boundary is copied." If F wins, I accept it on the conditions in my debate reply."* Web had said in debate it would move to F; the Minimalism point changed that.
- AI/ML: **S** *(dissent)* — *"S + copy-at-send then gives one rule a model can learn from one sentence: "a shared cell that crosses a task boundary is copied." F + copy-at-send gives two mechanisms for two boundaries, plus a new runtime panic, and that is more decision points for every generated program."* Accepts F with the same three conditions.

**Q2 re-vote.** W 4, E 2, N 0. Web and Minimalism moved from N to W. PLT moved from its Phase D lean toward E back to W (its Phase C vote). No panelist ranks N first.

- PLT: **W** — *"A warning gives the editor signal that sys and devops want, and it makes no claim to be complete or never wrong."*
- AI/ML: **W** — *"An error from a partial check teaches models that a clean compile proves no race, and a warning does not make that promise."*
- Web: **W** *(moved from N)* — *"A warning shows the probe shape, which users write most, in the editor before any test runs. It does not claim to be complete, as an error would."*
- Minimalism: **W** *(moved from N)* — *"W is the smaller rule: it rejects no program and promises nothing about completeness."*
- Systems: **E** *(dissent; fallback W)* — *"E fires only for a write through a direct alias that runs on every path from the spawn to the join, in straight-line code in the same block. Any other direct-alias write in the window gets the warning (W). […] If the panel will not take the narrowed E, count my vote as W over N."* Systems narrowed E after AI/ML's `if`-arm point.
- DevOps: **E** *(dissent; fallback W)* — *"A write in the spawn-to-join window panics every time it runs. The compiler can see it, so the editor should mark it as an error before a test runs."* *"If E does not win, count my preference as W over N."*

### Conditions recorded with the vote

1. The freeze panic message names the write site, the spawn site and the captured binding. A generic message ("write to frozen cell") does not meet this condition. The text ships with the rule.
2. §2.8 shows an "await, then write" example.
3. Tickets are filed before the text ships for two items. First, the handlers in force at a spawn site that captured a `let mut`. The panel did not decide the rule. PLT: *"A handler in force at the spawn site that captured a `let mut` is frozen under F. So every stateful handler used in a task would panic. The sibling ticket must settle this before F text ships."* The spec says the rule is not yet decided. Second, gen1 rejects `List.clone()` although §3.6.1 lists it.
4. The write check has a stated cost, and the implementation owes a measurement. Systems' claim: *"On a mutating call: one load and one well-predicted branch. Capacity checks already cost about the same."* and *"Reads cost nothing."* Minimalism: *"The decision record must show that this check costs about one branch, or F's case weakens."* PLT: *"If that check costs more than one branch, min's S case gets stronger."* The implementation must measure this cost on a program with no spawn.

Two further facts the record keeps:

- The Q2 warning depends on `MutAliasOfImmutable` alias tracking. That tracking has no code in `src/` yet. Until it ships, the spec names a warning that does not fire, and `blink check` stays silent on the probe. The spec must not describe the warning as shipped.
- Q3 relates to an open sibling question: whether a Channel or an effect handle is a shared cell. The Q3 copy rule needs Channel and effect handles to stay off the §3.6 list. If they join the list, a send would copy the channel itself and break every send/receive example. The sibling question stays open and this record does not decide it.

The Q2 check is not complete. It misses `id(a)`, `W { xs: a }` and `mut` parameters. §2.8 says so, and says that the freeze is the guarantee.

AI-first review: Learnability pass, Consistency FAIL, Generability pass, Debuggability pass, Token efficiency pass, 4/5. The Consistency failure is the two mechanisms: freeze at spawn and copy at send. The panel accepted this cost. Its reason is that spawn has a join point that bounds the sharing and a send has none.

### Final Spec

```blink
fn main() {
    let xs = [1, 2, 3]
    let mut ys = xs                // ys and xs share one list (§3.6)
    async.scope {
        let h = async.spawn(fn() { xs.len() })
        ys.push(4)                 // PANIC: the task can still read xs
        let n = h.await
        ys.push(n)                 // OK: the task is joined
    }
    let ch = channel.new[List[Int]](buffer: 1)
    let mut batch = [1, 2]
    ch.send(batch)
    batch.clear()                  // the receiver still gets [1, 2]
}
```

- A spawned task freezes every shared cell its captures reach, at any depth. The freeze starts at `async.spawn`.
- The freeze ends at join: `h.await` or exit of the enclosing `async.scope`. The spawner releases it in its own program order, so a panic never depends on thread timing.
- A write through any name to a frozen cell panics. Reads are unchanged.
- `warning[SpawnCaptureMutAlias]` fires on a write through a direct alias inside the spawn-to-join window. The check is not complete. The freeze is the guarantee.
- `ch.send` copies every shared cell the value reaches, at any depth. It is the only deep copy in the language. Its cost grows with the size of the value. The rule assumes Channel and effect handles stay off the §3.6 list; that question is open and is decided elsewhere.
- E0650 help follows Q4-a. It keeps `let snapshot = count` for scalars. It adds that binding a List does not copy it (§3.6). It tells the user to compute the value inside the task or send results through a channel. It shows `xs.slice(0, xs.len())` for a List, marked "one level only".
- The handler state at a spawn site is not yet decided.
