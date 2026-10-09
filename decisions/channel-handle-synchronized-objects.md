[< All Decisions](../DECISIONS.md)

# Channel, Handle[T] and Handlers in a Spawned Task — Design Rationale

Two gaps stayed open after the spawn freeze vote. The first: "Spec: is a Channel or an effect handle a shared cell after a copy? (§3.6 Shared cells list does not cover them)". The second: "Spec: does async.spawn freeze the state of a handler in force at the spawn site that captured a let mut?". Two copies of one channel share one queue, so the old law sentence "Only a shared cell can change through a second name" was false. A freeze of a handler in force would make every stateful handler panic in a task. No freeze would let the task race on the handler state. The two gaps needed one answer, because both ask what a task may share.

Governs: `sections/03_types.md` §3.6 *Shared cells* / *Synchronized objects*, §3.6.1 *Clone Semantics*; `sections/02_syntax.md` §2.8 *Handlers in a spawned task*; `sections/04_effects.md` §4.13 *Handle[T]* / *Channel operations*, §4.15.4.

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in these phases. Phase A gave independent proposals. Phase A.5 merged them into option labels. Phase B ran one debate round. Phase C was a silent vote, and every question passed 6-0. Phase C left two sub-points of Q3 open in the Concerns, so a focused round (C2) ran on them. Phase D reran those two sub-points: point 1 (a same-handler cycle) split 3-3, and point 2 (blocking I/O) passed 6-0. The user (BDFL) broke the 3-3 tie: "spec requires panic it is".

#### Phase A — Independent proposals

- **Systems:** a second category in §3.6, not a shared cell. *"Rule: add a second category to §3.6, "synchronized objects". Do not add them to the shared-cell list."* On Handle[T]: *"A task is joined once. A second .await on a handle, or on a copy of it, panics."* On handlers: *"Proposal S-lock: the handler serializes its ops."* Vote: *"My vote: S-lock + R-publish. It is memory-safe, adds no cost to single-threaded code, and keeps stateful handlers usable in tasks."*

  ```blink
  let ch = channel.new[Int](buffer: 1)
  let c2 = ch
  c2.send(1)
  assert_eq(ch.recv(), Some(1))   // one queue, two names
  ```

- **Web/Scripting:** *"W1. Add a second, short list: "shared handles". Do not put them on the shared-cell list."* On Handle[T]: *"A second `.await` returns the same result again."* and *"To keep structured concurrency simple in v1, a `Handle[T]` cannot be sent on a channel or captured by `async.spawn`."* On handlers: *"W2. A handler in force at a spawn site is shared with the task, not frozen. Its ops run one at a time."*

- **PLT:** one list with two kinds. *"My fix: one list with two kinds."* On Handle[T]: *"A later `.await`, on the same handle or on a copy, returns the same result and does not block."* and *"A `Handle[T]` stays in its spawning task."* On handlers: *"That makes a handler an object with a home."*

  ```blink
  test "tasks log through the test's handler" {
      let msgs: List[Str] = []
      with capture_log(msgs) {
          async.scope {
              let h = async.spawn(fn() { io.log("from task") })
              let n = msgs.len()   // stable: ops run only at our suspension points
              h.await              // runs the task's pending log op here
          }
      }
      assert_eq(msgs.len(), 1)
  }
  ```

- **DevOps/Tooling:** *"F6 shows the problem. Two copies of a channel share one queue, but §3.6 says "Only a shared cell can change through a second name." That sentence is false today."* On Handle[T]: *"A type check catches this at compile time, and the LSP can underline the exact channel.new[...] or capture. That is better than a runtime panic."* On handlers: *"I prefer serialization. My one firm line is that the race option is not acceptable, because no tool can explain a data race."*

- **AI/ML:** *"Every rule below must be one sentence it can apply without running code, and code that works without tasks must keep working inside a task."* On Channel: *"But F4 shows Channel cannot join the shared-cell list: send would copy it, spawn would freeze it. So the spec needs a second, named category."* On Handle[T]: *"I flag (not decide) whether a `Handle[T]` may cross a channel; my lean is a compile error in v1, since a task outside its scope breaks the structured-concurrency guarantees."* On handlers: *"Proposal 2 (Gap 2): stateful handlers stay live; their ops run one at a time"*.

- **Minimalism:** *"`Channel[T]`: keep it off the list."* On Handle[T]: *"Leave the double-`.await` question for a separate ticket. It is a real gap, but a different one, and putting it in here invites scope creep."* On handlers: *"The handlers in force at the `async.spawn` site for each effect in the closure's row count as captures of the closure. The freeze covers each shared cell they reach."*

#### Phase A.5 — Dedupe

The moderator grouped the proposals mechanically. "F1" to "F8" in the quotes below name the numbered spec facts in the Phase A brief. Option lines, copied from the dedupe file:

- **Q1-A. A second, separate category beside shared cells.** "Shared handles" (aiml, web, devops) / "Synchronized objects" (sys). Law becomes "Only a shared cell or a shared handle [synchronized object] can change through a second name."
- **Q1-B. One list, two kinds of shared cell.** "Plain cells" (List, Map, Set, StringBuilder, closure/handler whose captures reach a plain cell or a `let mut`) and "synchronized cells" (Channel, Handle). Spawn freezes and send copies plain cells only. (plt)
- **Q1-C. No new category; a Channel carve-out in the law sentence.** "Only a shared cell or a `Channel` can change through a second name ..." plus "a copy of a `Handle[T]` names the same task". (min)
- **Q2-scope.** Decide Handle[T] here (sys, web, plt, devops, aiml) vs. give only "a copy names the same task" and split double-`.await` / sending a Handle into a new ticket (min; aiml offered the split as a smaller fallback).
- **Q2-await.** A second `.await` returns the same result again, no second join (web, plt, devops, aiml); or panics: "a task is joined once" (sys).
- **Q2-cross.** Compile error (sys, web, devops; aiml leans this way); compile error where the type shows it, panic otherwise (plt); treated like Channel: allowed, same task (min's minimal rule).
- **Q3-F. Freeze:** handlers in force for effects in the closure's row count as captures; the freeze covers the cells they reach. (min)
- **Q3-L. Lock:** the handler stays live; its ops run one at a time across tasks; writes outside its ops panic (freeze-style). Variations: outside reads panic (aiml "guarded", devops), or a read sees some state an op produced, never a torn one (sys R-publish).
- **Q3-H. Home:** the handler's ops run on the task that ran its `with`; a task's op waits until the home task runs it at its own suspension points. No lock, no read check. (plt)
- **Q3-P. Panic early** (named as fallbacks): at the `async.spawn` site when a handler in force reaches a shared cell; or when a non-home task performs an op (P2); or freeze with its own panic text (devops).

Six points were common to all panelists: the reserved names `io`, `db` are not values; `Handler[E]` is already on the §3.6 list; Channel does not join the shared-cell policy.

#### Phase B — Debate highlights

**Systems withdrew R-publish and panic-on-second-await, and moved to H.**

> *"Summary: I move on Q2-await and Q3. Q3-H (PLT's homed handlers) is now my first choice, and I drop R-publish."*

> *"Q2-await: I drop "panic" and move to "returns the same result"."*

> *"I withdraw R-publish. PLT and Min are right that a lock without a read rule is not sound. My R-publish claim was also too cheap: a Map rehash changes several words, and making an unlocked reader safe against it is a new memory model, not a store order."*

**Minimalism dropped Q1-C, the split, "treat like Channel" and F.**

> *"Min, Phase B round 1: I drop my own Q1-C and Q2 split, and on Q3 I move from F to H."*

> *"Q2-cross: I drop "treat like Channel" and back PLT: a compile error where the type shows the handle, a panic otherwise."*

> *"I proposed F, and I now rank it below H."*

**PLT dropped Q1-B.**

> *"PLT, Phase B round 1: I drop Q1-B for Q1-A ("synchronized object"), hold Q2, and keep Q3-H with Sys's and Web's blocking-point condition."*

PLT also widened the servicing list: *"I extend the rule to "every point where the home task blocks in the runtime", not just my four."*

**AI/ML stayed on L in Phase B, with one condition, and moved to H in Phase C.**

> *"STABLE, ready to vote. The only thing that could move me is a Sys reply that R-publish cannot be done for Map rehash or StringBuilder. In that case H moves to first."*

In Phase C AI/ML wrote: *"In round 1 I said I would move H to first if R-publish could not cover Map rehash. Sys has now withdrawn R-publish for exactly that reason."*

**DevOps moved from L to H; web moved from L to H.**

> *"Q3: I withdraw my lock + read check (Q3-L "guarded") and move to Q3-H (PLT's homing) as first choice."*

> *"Web, Phase B round 1. I move on Q3 from L to H; my other positions hold."*

**The name "shared handle" lost.** Web in Phase B: *"I am withdrawing my own name, and the reason is developer experience."* In Phase C, DevOps: *"I drop my own "shared handle"."* AI/ML: *"I move from my own "shared handle"."*

**Q2-cross moved to PLT's form.** Sys: *"I move to PLT's hybrid: a compile error where the type shows the Handle, and a panic otherwise."* The reason came from DevOps: *"A closure's type does not show what it captured."*

#### Phase C — Final vote

Tally: Q1 Q1-A 6-0. Q1-name "synchronized object" 6-0. Q2-scope decide Handle[T] here 6-0. Q2-await returns the same result 6-0. Q2-cross compile error where the type shows it, panic otherwise 6-0. Q3 Q3-H 6-0.

Q3 rankings: sys/web/plt/devops/aiml H > P2 > P > L(read panic) > F; min H > P2 > P > F > L.

**Q1 — Q1-A, a separate category (6-0)**

- **Systems:** Q1-A. *"A leaves every existing use of "shared cell" in §2.8, §4.13 and the freeze record unchanged, so the edit is smaller and the term keeps its meaning."* Concern: *"a future synchronized type (a mutex or an atomic, say) could be added to the category without the "buffer unaliased" argument holding for it. The category needs a stated entry condition, not only a list."*
- **Web:** Q1-A. *"A named category is what a developer can search for, and what hover text can show."* Concern: *"Two "can change through a second name" concepts is one more thing to learn. The §3.6 text must keep them side by side with one sentence each, or beginners will mix them up."*
- **PLT:** Q1-A. *"A keeps that meaning fixed and adds a second predicate beside it."* Concern: *"The text might lose the soundness reason. The text must say that each buffered value was copied at send, so no other name reaches it. That is why spawn and send may stop at a synchronized object."*
- **DevOps:** Q1-A. *"A category with a name gives the LSP one hover line and the docs one search term, e.g. "Channel[Int]: synchronized object. Spawn does not freeze it, send does not copy it.""* Concern: *"if the soundness sentence (a buffered value was copied at send, so no other name reaches it) is left out, readers will see the traversal stop at a Channel as an arbitrary exception."*
- **AI/ML:** Q1-A. *"The second concept already exists (F6). Naming it gives a model one term to look up."* Concern: *"Some sections will still say "shared cell" where they mean "anything that changes through a second name", and a model will apply the freeze/copy rule to a Channel. Every "only a shared cell" sentence must be updated."*
- **Minimalism:** Q1-A. *"A adds one category and changes one sentence."* Concern: *"the category text could drop PLT's soundness sentence (buffered values were copied at send, so nothing else reaches them). Without it, a later reader cannot see why spawn and send may stop at a Channel, and the next change may break that."*

**Q1-name — "synchronized object" (6-0)**

- **Systems:** *""Handle" already has two meanings in the spec (§3c.4 effect handles, Handle[T])."* Concern: *""synchronized" may suggest that the contents are locked. The text must say that values cross by copy at send and that only the queue and join state are synchronized."*
- **Web:** *"A third "handle" would bring the same Stack Overflow question back."* Concern: *""Object" is a slightly foreign word in a language with no classes. If the panel wants to say "value" instead, I would not object."*
- **PLT:** *""Synchronized" states the property a reader needs: the object is safe from any task."* Concern: *""Object" may suggest identity semantics that some reader thinks applies to other values too. The law sentence ("only a shared cell or a synchronized object can change through a second name") prevents that."*
- **DevOps:** *"I drop my own "shared handle"."* Concern: *"users may read "object" as an OOP class concept. The §3.6 text should define the term in its first sentence."*
- **AI/ML:** *"I move from my own "shared handle"."* Concern: *""Object" is not a Blink term anywhere else, so the text must define it in one sentence, keep PLT's soundness sentence, and not suggest classes."*
- **Minimalism:** *"A third use of the word adds to the problem."* Concern: *"object" is a word Blink uses nowhere else. Keep the term to §3.6 and do not let it grow into a general object vocabulary."*

**Q2-scope — decide Handle[T] here (6-0)**

- **Systems:** *"the runtime already has a behavior for a second await and for a sent handle, so leaving it unspecified leaves the behavior unspecified, not undecided."* Concern: *"none of substance."*
- **Web:** *"The freeze's end rule ("the spawner joins") is undefined until we say who can join."* Concern: *"none of substance. The text is short."*
- **PLT:** *"The freeze ends when the spawner joins. That end rule is defined only once the spec says who may join, so the Handle rule is part of the freeze contract."* Concern: *"None of substance. All six panelists agree."*
- **DevOps:** *"the freeze ends when "the spawner joins", so who can join is part of the freeze contract."* Concern: *"none of note."*
- **AI/ML:** *"The rule is short and all six agree on it. A split would leave a prelude type undefined."* Concern: *"None of substance. Wording must make clear that the "same result" shares cells as a bind does."*
- **Minimalism:** *"I withdraw my split. Sys showed that the runtime already does something on a second await, so the spec must say what."* Concern: *"keeping it in scope can pull in more questions (cancel, `select`, a handle in a struct field). Hold the text to the await rule and the cross rule."*

**Q2-await — returns the same result (6-0)**

- **Systems:** *"blink_handle_await already reads the stored h->result after DONE, and the scope drain re-awaits harmlessly. Zero added cost."* Concern: *"the result stays reachable from the handle for the handle's lifetime, so a large T is kept alive longer than a consuming join would keep it. This is a GC retention cost, not a correctness problem."*
- **Web:** *"A panic would turn a harmless habit into a run-time trap with no gain in safety."* Concern: *"Cells in the result are shared between the two awaits, as with a bind. The spec must say so in one clause, or someone will expect two fresh copies."*
- **PLT:** *"A second await is therefore sound, and panicking on it adds a failure mode with no safety gain."* Concern: *"If Q2-cross were weakened later, a returned value could alias across tasks. The rules must stay coupled."*
- **DevOps:** *"no program is wrong because it awaits twice, so a panic would be a diagnostic with no bug behind it."* Concern: *"the result's cells are shared between the two awaits, and a user who expects a fresh value could be surprised. The spec sentence "shared, as with a bind" must stay."*
- **AI/ML:** *"A panic would add a failure mode with no safety gain."* Concern: *"A model trained on Rust may still write code that treats the first await as a move. That is harmless here."*
- **Minimalism:** *"The runtime already keeps the result in the handle (Sys: blink_handle_await, scope drain), so this costs nothing and adds no failure mode."* Concern: *"if Q2-cross is ever relaxed, two tasks could get the same result cells without a freeze. Any later relaxation must revisit this rule."*

**Q2-cross — compile error where the type shows it, panic otherwise (6-0)**

- **Systems:** *"a closure type hides its captures, so a type-only check is incomplete."* Concern: *"the runtime walk must actually visit closure captures, or the panic arm is vacuous. The implementation needs a test that sends `fn() { h.await }` and expects the panic."*
- **Web:** *"A closure's type hides its captures, so `fn() { h.await }` gets past a type-only rule. My Phase A rule had that hole."* Concern: *"The panic arm fires at run time for a shape the user cannot see in the types. The message must name the closure and the captured handle, or it will look like magic."*
- **PLT:** *"That arm is what makes the rule sound. The compile arm gives early diagnostics in the common case."* Concern: *"Users may read the compile error as a full guarantee and not expect the panic. The spec must state that the compile check is not complete, as §2.8 does for the freeze warning."*
- **DevOps:** *"the compile error lets the LSP underline the common case, e.g. channel.new[Handle[Int]]."* Concern: *"the post-mono form of the compile error (a generic T instantiated with a Handle) can point at a call site far from the cause. Its message must show the instantiation chain."*
- **AI/ML:** *"A closure's type hides its captures, so a compile-error-only rule cannot be complete."* Concern: *"The panic arm is hard for a model to predict from the type alone. The diagnostic must name the closure capture that reached the Handle."*
- **Minimalism:** *"I withdraw "treat like Channel"."* Concern: *"users may read the compile error as the full rule. The spec text must say plainly that a Handle hidden inside a closure panics at run time."*

**Q3 — Q3-H, homed handlers (6-0)**

- **Systems:** Q3-H. *"H puts the cost only where the state lives."* Concern: *""blocking I/O services waiting ops" is the expensive clause. A home task in a plain blocking read(2) cannot service anything."*
- **Web:** Q3-H. *"H is the JS event-loop model, so web developers already know it. One task owns the state, and other tasks' ops run when it blocks."* Concern: *"A stateful handler in force over a production server loop stalls its tasks while the home task is in a blocking `@ffi` call or a long compute."*
- **PLT:** Q3-H. *"H is the faithful operational meaning of handlers: an op clause runs in the dynamic context of the `with` that installed it."* Concern: *"If the home task blocks in a foreign call or computes for a long time, task ops stall. The deadlock case (a foreign call that waits on the task) must be named in the spec, and the trace must show "op queued for home" so the stall can be diagnosed."*
- **DevOps:** Q3-H. *"H has no new panic, no read tax on all code, and reads in the home task are stable."* Concern: *"a user whose task stalls behind a busy home task sees a slow test, not an error. The implementation ticket must include the trace events ("op queued for home task", "op run at home", naming the `with` site and the spawn site), and an LSP hint on a `with` that contains an async.spawn, or the stall cannot be diagnosed."*
- **AI/ML:** Q3-H. *"The rule is then one sentence a model already knows from effects and from the JS event loop: "an op runs where its handler was installed.""* Concern: *"A home task that blocks in a foreign call or computes for a long time stalls workers with no visible cause. The spec must name this case, and the trace events DevOps asked for must ship with it."*
- **Minimalism:** Q3-H. *"H adds no new concept a user must learn."* Concern: *"the home task now runs waiting ops at every point where it blocks. If that includes a block inside an op of the same homed handler (an op body that calls `send`, `recv` or `sleep`), a second op runs in the middle of the first and sees its state half changed."*

#### Focused round C2 — two Q3 sub-points

The two Concerns above (Minimalism on re-entrancy, Systems on blocking I/O) named choices that the Q3-H text must make.

**Point 1, re-entrancy: 6-0.** Queued ops of the same homed handler do not run while one of its ops runs on the home. Ops of other homed handlers may run.

- **Systems:** *"While an op of homed handler X runs on the home, the home's blocking points run queued ops of other handlers but never of X. This makes each op atomic, which is what "ops run one at a time" promises."*
- **Web:** *"Developers read an op as one call that runs to completion, as a JS callback does."*
- **PLT:** *"Each op is then atomic with respect to its own state, which is the guarantee every panelist assumed in Phase B."*
- **DevOps:** *"The runtime can detect it exactly, so it should panic and name the `with` site, the op, and the task the op is waiting on, not hang."*
- **AI/ML:** *"A model reads an op body as one step on the handler's state, like a method under a monitor."*
- **Minimalism:** *"Without this rule, an op body that blocks would let a second op see the first one's state half changed, and per-op atomicity is the one thing H promises."*

**Point 2, blocking I/O in the servicing list.** Systems, Web and PLT keep it. Minimalism and DevOps narrow it. AI/ML keeps it as the target.

- **Systems (keep):** *"A user cannot tell a stdlib read from a runtime wait, so the servicing list must cover both."*
- **Web (keep):** *"The spec is the blueprint, so we should promise the right behavior."*
- **PLT (keep):** *"Leaving I/O out is not only a stall: if the home reads a pipe that the task writes, and the task is waiting on a log op, the two deadlock."*
- **Minimalism (narrow):** *"Blocking I/O: narrow the clause. List only the waits the runtime owns: `.await`, `recv`, `send`, scope exit and `time.sleep`."*
- **DevOps (narrow):** *"Point 2 (Sys, blocking I/O): narrow the clause for v1."*
- **AI/ML (keep as target):** *"Keep std I/O, net and sleep on the list as the target, and have the implementation ticket do poll plus an eventfd."*

#### Phase D — Round 2

**Point 2, blocking I/O: KEEP 6-0.** Minimalism and DevOps switched from narrow.

- **Systems:** *"PLT's pipe example shows that narrowing the list makes a deadlock, not just a stall, in code with no @ffi in sight."* Concern: *"not every runtime wait is an fd. A process wait needs pidfd, or a SIGCHLD self-pipe, or kqueue, so the implementation ticket must list each blocking runtime call and how it wakes."*
- **Web:** *"A user cannot tell a stdlib read from a runtime wait, so a list that leaves out I/O produces unexplained hangs."* Concern: *"If v1 ships H before the I/O layer is done, the spec and runtime will disagree. The implementation ticket must block the H release, not follow it."*
- **PLT:** *"With that, the "cannot deliver" objection falls away."* Concern: *"If the I/O layer ships without the poll path, the spec and the runtime will differ in a way that hangs. The implementation ticket must block the release of H, or ship P2 until then."*
- **DevOps:** *"Point 2: "keep". I change my vote."* Concern: *"if v1 ships before the I/O servicing does, the gap must have its own tracked ticket and show in `--trace` as "op queued for home task", or users will hit an unexplained hang."*
- **AI/ML:** *"A user cannot tell a stdlib read from a runtime wait, so the list must cover both, and `@ffi` stays the one named stall."* Concern: *"An I/O call that goes around the poll path would make the spec false, and a model would never see it. The implementation needs one test per blocking std call (read, accept, sleep) under a homed handler."*
- **Minimalism:** *"Point 2: keep. I change my C2 vote."* Reasoning: *""Every blocking operation the runtime provides, except `@ffi`" is also one rule with one exception, which is smaller than a list plus two kinds of stall."* Concern: *"the spec will lead the runtime here. The I/O servicing needs an implementation ticket with PLT's pipe case as its test, or the promise becomes silent drift."*

**Point 1, a same-handler cycle: 3-3.** The runtime detects the await-shape cycle and panics (channel-routed cycles stay a stated deadlock): Systems, Web, DevOps. The spec states a deadlock, and a panic in the await case is allowed as a diagnostic but not promised: PLT, Minimalism, AI/ML.

- **Systems:** panic. *"A fixed-line panic beats a hang under every rule this panel has applied, and this check costs nothing on the fast path."* And: *"The limit, which the spec text must say: a cycle routed through a channel (the op body blocks in recv, waiting on a sender that is waiting on X) has no single waited-on task. That case stays a stated deadlock."*
- **Web:** panic. *"For a developer, a hang is the worst failure, because nothing points at the cause."* Concern: *"The detection is exact only for a direct `.await` chain. A cycle that passes through a channel (T blocks in `send` on a full channel the op would drain) names no task. So the spec must also state that the remaining case deadlocks, and must not promise to catch every cycle."*
- **DevOps:** panic. *"A hang is the worst diagnostic a language can give, and this one we can turn into an error at a fixed line."*
- **PLT (dissent):** stated deadlock. *"If the op body waits on `recv`, whether the cycle is real depends on whether some other task will send. That is not decidable at the wait, so "the runtime detects the cycle and panics" promises more than it can deliver."* And: *"The rule should be the deadlock."*
- **Minimalism (dissent):** stated deadlock. *"A spec panic would then hold for only part of the cycles, and that makes a second rule that users must learn."*
- **AI/ML (dissent):** stated deadlock. *"A model applies a rule as written, so a rule that only holds some of the time is worse than one honest sentence."*

At the user's request, the moderator recommended that the spec require the panic, because "may panic" leaves the behavior to the implementation.

**User tiebreak:** spec requires panic — "spec requires panic it is". Point 1 became: the runtime detects the await-shape cycle and panics. A cycle through a channel stays a stated deadlock.

AI-first review: Learnability pass, Consistency pass, Generability pass, Debuggability pass, Token efficiency pass, 5/5. Debuggability note: a home task stalled in a blocking @ffi call delays waiting ops with no error; the implementation's trace events make it visible.

### Final Spec

- **Synchronized objects** are a second category in §3.6, beside shared cells. `Channel[T]` and `Handle[T]` are synchronized objects. A copy refers to the same state. `async.spawn` does not freeze one and `ch.send` does not copy one.
- **Entry condition.** A type joins the category only if each operation on it is safe from any task, and a value it hands from one task to another stays reachable from one task only.
- **Soundness.** A value in a channel's buffer was copied when it was sent, and no other name reaches it. So spawn and send need not look inside a synchronized object. Only the queue of a `Channel` and the join state of a `Handle` are synchronized.
- **Law.** "Only a shared cell or a synchronized object can change through a second name."
- **Effect handle names** (`io`, `db`) are reserved names, not values. They are on neither list.
- **Second `.await`.** A second `.await`, on the same handle or on a copy, returns the same result and does not run the task again. The result's shared cells are shared between the two results, as with a bind.
- **Handle cross rule.** A `Handle[T]` stays in the task that spawned its task. Where the type shows the handle, a `ch.send` value or an `async.spawn` capture that reaches it is a compile error. For a generic type, the message shows the instantiation chain. Where the type does not show it (a closure that captured the handle), the send or spawn panics. The compile check is not complete; the panic is the guarantee.
- **Homed handlers.** The trigger is that the handler's captures reach a shared cell. Its ops run on the task that ran its `with`. The home task runs waiting ops whenever it blocks in a runtime blocking operation: `.await`, `recv`, `send`, scope exit, `time.sleep`, and blocking I/O. A foreign call (`@ffi`) does not run them. Ops of the same handler never overlap on the home (per-handler atomicity); ops of other homed handlers may run.
- **Cycles.** If an op body waits with `.await` on a task, or exits a scope that joins it, and that task (directly or through the tasks it awaits) has an op of the same handler waiting, the runtime panics. The message names the `with` site, the op and the `async.spawn` site. A cycle through a channel is a stated deadlock, and the runtime does not detect every such cycle.

```blink
import std.testing.{capture_log}

fn main() {
    let msgs: List[Str] = []
    with capture_log(msgs) {       // capture_log reaches msgs, so it is homed on main's task
        async.scope {
            let h = async.spawn(fn() {
                io.log("task started")
                21 * 2
            })
            let n = h.await        // main's task runs the waiting log op here
            io.log("got {n}")
        }
    }
    io.println("{msgs.len()}")     // 2, on every run
}
```
