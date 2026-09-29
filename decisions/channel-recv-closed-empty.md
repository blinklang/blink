[< All Decisions](../DECISIONS.md)

# Channel `recv()` on a Closed, Empty Channel — Design Rationale

The ticket asked what `ch.recv()` returns on a closed, empty channel. The code returned whatever NULL casts to: `0` for an `Int` channel and a null pointer for a `Str` channel, with no diagnostic. The rewrite codegen instead panics with `recv on a closed, empty channel`. §4.13 said nothing about `recv` after close, and `Channel` was absent from the §3c `IntoIterator` table, so `for value in ch`, the only drain form §4.13 shows, had no stated desugaring.

Governs: `sections/04_effects.md` §4.13 *Channel operations*; `sections/03c_protocols.md` §3c.1 *`for` Loop Desugaring and `IntoIterator`*.

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in independent-proposal → debate → vote rounds. Phase B ran one round (three distinct Q1 options after dedupe, plus flagged variations); all six signalled ready to vote after round 1. Phase D did not run: every question was 6-0.

#### Phase A — Independent proposals

- **Systems:** `recv() -> Option[T]`. *"closed-ness has to come back atomically from the same locked recv. An `is_closed()` check followed by `recv()` is a TOCTOU race, because a producer can close between the two calls."* On the runtime: *"The ABI changes to `bool blink_channel_recv(blink_channel*, void* out)`, with elem_size stored at `new` and elements kept inline in the ring (memcpy of sizeof(T)). The status is the return value and the payload goes through `out`."* On the panicking alternative: *"A panic-only (b) is not enough under §4.6.3. Panics cannot be caught, so a consumer that races a close has no way to recover without an Option form."*

  ```blink
  for v in ch {          // == iter.from_fn(fn() { ch.recv() })
      process(v)
  }
  ```

- **Web/Scripting:** preferred `recv() -> T` that panics, plus `recv_or_none() -> Option[T]`. *"Guiding fact: §2 has no `while let` and no `if let`. So an Option-returning recv makes the consumer loop `loop { match ch.recv() { Some(v) => ..., None => break } }`. That is 4 lines and a match for something JS/Python devs write as `for await (const v of ch)` or `for v in queue`."* Rejecting the zero value and `is_closed()`: *"The zero value is JS's `undefined` problem with a type attached: a sent 0 cannot be told apart from end of stream."*

  ```blink
  // Expect exactly one value
  let reply = reply_ch.recv()            // panics: "recv on a closed, empty channel"

  // Closing is a normal outcome here
  let job = jobs.recv_or_none() ?? default_job
  ```

- **PLT:** `recv() -> Option[T]`. *"`recv : Channel[T] -> T` is a partial function. Nothing in the type rules out the closed-and-empty state, and the running program reaches that state as a matter of course."* Against the zero value: *"Its codomain is really `T ∪ {EOS}` squeezed into `T`"*. Against a panic: *"So under (b), a correct multi-consumer program can abort nondeterministically. That makes the partiality **effectful**, not a static contract. It is the `head []` / `fromJust` mistake that Haskell has spent twenty years deprecating."* Companion rulings: *"`send` on a closed channel panics."* and *"`close()` is idempotent."*

  ```blink
  // normative desugaring of `for v in ch`
  iter.from_fn(fn() { ch.recv() })
  ```

- **DevOps/Tooling:** `recv() -> Option[T]`, with the closed state held outside the value slot. *"My test for each option is where the user first learns that the channel is closed and empty: at compile time with a caret and a fix, at runtime with a stack trace, or never. Option (c) is "never"."* On naming: *"I oppose the name `try_recv` in any variant. Rust, crossbeam, tokio and Go-style libraries use `try_recv` for NON-BLOCKING receive"*.

  ```
  error[E0200]: expected Int, found Option[Int]
    --> main.bl:4:18
     |
   4 |     let n: Int = ch.recv()
     |                  ^^^^^^^^^ recv() returns None once the channel is closed and empty
     = help: supply a default:     ch.recv() ?? 0
     = help: or handle the end:    match ch.recv() { Some(v) => ..., None => ... }
     = help: to drain every value: for v in ch { ... }
  ```

- **AI/ML:** `recv() -> Option[T]`, with `for` defined in terms of it. *"One rule for every "maybe no value" case. `list.get`, `map.get`, JSON navigation and now `recv` all return `Option`. A model that has learned `.get()` from the spec also knows `.recv()`, so this adds no new decision point."* Against `is_closed()`: *"Models write check-then-act code by reflex, and with channels that is a race"*. Fallback: *"`recv() -> T` panics, and nothing else changes"* with `for` on *"an internal non-panicking primitive that user code cannot call"*.

  ```blink
  fn worker(lock: Channel[Int]) ! Async {
      let col = lock.recv().unwrap()    // a channel used as a mutex is never closed
      lock.send(col + 1)
  }
  ```

- **Minimalism:** preferred `recv() -> T` that panics, `for` as the only drain form, no Option-returning receive yet. *"One fact from the call-site audit drives my position. None of the real `.recv()` call sites ever closes its channel."* *"Zero new names, zero signature changes, no bootstrap dance."* On the alternative: *"Every current call site gains `.unwrap()` for a case that cannot occur there. That is ceremony with no information: a semaphore acquire now reads as a fallible lookup."* Spec text proposed: *"Every value sent is received. A sent `0` (or any other value) is never read as end of stream."*

  ```blink
  fn acquire(sem: Channel[Int]) {
      sem.recv()
  }
  ```

Rejected by all six in Phase A: the zero value, an `is_closed()` pre-check, and the name `try_recv` for a blocking receive.

#### Phase B — Debate highlights

**Web moves from B to A.** The move rests on PLT's point that a panic is uncatchable under §4.6.3. Web quotes PLT: *"§4.6.3 says a panic is uncatchable outside tests. So under (b), a correct multi-consumer program can abort nondeterministically."* Web's own words:

> *"A Kotlin or Python developer who hits a closed-channel error wraps the call in try/catch and moves on. A Blink developer cannot, so a panicking `recv()` is not the familiar thing I claimed. It is the familiar name with a harsher outcome. Every worker-pool tutorial (N consumers, one producer that closes) would then have to say "don't call recv, call recv_or_none". Once the default name is the one you must not use, you get a steady flow of Stack Overflow questions."*

And on why to pay the cost now: *"We can never make `recv()` total again without a breaking change after release. Pre-release is the only time the good default is free."*

**Minimalism moves from C to A.** *"I preferred C (panicking `recv`, no Option form). Two Phase A arguments showed that C is not the smallest design. It only looks smallest."* Its reasons:

> *"1. **C hides a second primitive.** aiml: "`for` stays the only way to drain, and it uses an internal non-panicking primitive that user code cannot call." sys: "for-in needs an Option-shaped primitive to desugar to anyway." Both are right. Under C the language has two receive operations, and the spec can name only one of them. Under A it has one operation, and `for v in ch` is plain composition, `iter.from_fn(fn() { ch.recv() })`."*

> *"2. **C's growth path ends at B.** I said "C can be undone, since M2 is additive". That is true, but the thing it adds is a second public receive forever, which makes B, the largest surface on the table. A never needs a second blocking receive. I withdraw the reversibility argument."*

> *"3. **The caller cannot check the precondition.** plt: "'Not closed and not empty' is not decidable by the caller ... a correct multi-consumer program can abort nondeterministically." A panic is correct for a precondition the caller controls, such as `list[i]`. Here the scheduler controls it, and §4.6.3 gives no recovery."*

PLT put the same point to web as a rebuttal of the `list[i]` versus `list.get(i)` analogy: *"An index precondition can be decided locally: `i < xs.len()` holds or fails, with no race, because the caller owns `xs`. "Not closed and not empty" cannot be decided by the caller, since another task changes that state between any check and the recv."*

**Systems changes Q4 to decide-now.** Systems had asked for a separate ticket in Phase A. In round 1: *"I change my Phase A position. Rule it here: `send` on a closed channel panics. The closer owns the channel's lifecycle, and `async.scope` makes that owner lexically clear, so the caller can decide it."* Systems corrects PLT's precedent claim and keeps the ruling: *"The conclusion is right, but the premise is wrong for Rust. `Sender::send` returns `Err(SendError(t))` and hands the value back, and Rust has no explicit close. Only Go panics. I support the panic on the ownership argument, not on precedent."*

**Systems withdraws its ABI item (3b).** *"I accept min's and plt's framing. The spec states the guarantee ("every value sent is received; closed is a state of the channel, never a value in the element domain") and pins it with plt's property test over `0`, `""`, `false`, `None`. My inline-element, bool-return ABI is how the runtime meets that guarantee. It is not spec text. I withdraw it as a spec item."*

**Devops, aiml and systems move Q7 to PLT's `.unwrap()`.** PLT's case: *"When a semaphore acquire drops a `None` and carries on, two tasks can be inside the critical section at once. That is a silent break of mutual exclusion, and §3.4 forbids exactly that kind of silent answer. `.unwrap()` turns the invariant back into a loud failure."*

- **Devops:** *"I change my position to plt's: write `sem.recv().unwrap()` at the two in-tree semaphore sites. In Phase A I said the bare statement "still works". It does, but under A a bare `sem.recv()` on a closed semaphore drops `None` and the acquire goes ahead silently. That is the same class of silent failure I rejected in (c)."*
- **AI/ML:** *"**Q7: changed.** I now agree with plt that the in-tree semaphore sites should say `sem.recv().unwrap()`. Under A, a bare discard on a closed semaphore lets the acquire proceed silently. That is the (c) failure mode again, only moved."*
- **Systems:** *"write `sem.recv().unwrap()` (plt). A discarded `None` lets an acquire go ahead on a closed semaphore without any sign. That is the same silent failure this ticket exists to remove."* Systems also filed a side point against the tree's design: *"The right fix is a real sync primitive (friction ticket), not a panicking `recv` signature chosen so misuse reads cleanly."*

**Devops and web move Q6 to a separate ticket, with a rider.**

- **Web:** *"Moved: I accept min's view that it is a separate ticket. It does not change the recv answer. Condition: that ticket must land before the §4.13 examples are rewritten, so we do not publish new examples in the spelling we are about to drop."*
- **Devops:** *"separate ticket, but it blocks the §4.13 text edit. I move toward min on scope. But every example this ruling publishes must compile. If §4.13 shows `channel.new[T](buffer: N)` and the compiler only takes `Channel(n)`, `blink llms` teaches code that fails."*
- **Minimalism**, who first raised the split: *"OPEN_QUESTIONS §2.1 already decided `channel.new[T](buffer: N)` (5-0), and it is on the already-decided list. The code that spells `Channel(n)` is out of step with the spec."*

**Two more points that shaped the record.**

- On the panic message quality under A, devops conceded part of web's objection and named the fix: *"the unwrap panic must carry the source span of the call (`main.bl:12:15`). With the span, the message points at the `recv()` call, and the Option-typed call site already explains why."*
- On the `for` row, devops wanted one line of real Blink for tooling: *"`blink doc`, hover on `for`, and go-to-definition can show a line of real Blink. … Under C (aiml P2, min M1), the row points at a primitive user code cannot name, so hover has nothing to show and `blink llms` must describe magic."* Web asked to lead the row with a plain sentence: *"lead the row with min's plain sentence, "receives until the channel is closed and empty, then stops", so the reader learns what it does before how it is defined."*

**Unanimous rejections.** The zero value: *"Specifying the zero value turns a known bug into a promise."* (minimalism); *"It is the same codegen as today and keeps the defect: a sent 0 is indistinguishable from end-of-stream."* (systems). An `is_closed()` pre-check, as a TOCTOU race: *"Neither should enter the spec."* (web, on the zero value and `is_closed()`); *"A panic is the right tool for a precondition the caller can discharge. It is the wrong tool for a result that depends on the interleaving."* (PLT). The name `try_recv` for a blocking receive: *"Using `try_recv` for a blocking Option-returning recv would mislead every systems programmer who reads it."* (systems); *"No change on naming: no `try_recv` for a blocking receive. All six agree."* (devops).

#### Phase C — Final vote

- **Q1: What does `recv()` do on a closed, empty channel?** (6-0 for A: `recv() -> Option[T]`, the one blocking receive; `None` only when closed and drained)
  - **Systems:** A — *"Closed-ness must come back atomically from the same locked receive, so the one primitive has to carry both the status and the value. For a scalar T, `Option[T]` is {tag, payload} and returns in two registers with no allocation."* Concern: *"If the implementation meets `Option[T]` by boxing elements, or by keeping the `void*` slot and a NULL test, then A ships with a GC allocation per send or with the send(0) data loss still in place. The Option signature alone does not fix the runtime."*
  - **Web/Scripting:** A — *"One method that works like `list.get` / `map.get` passes the 5-minute test, and the drain stays `for v in ch`, so the common case does not change."* Concern: *"The E0200 message must suggest `?? default`, `match` and `for` before `.unwrap()`, and an unwrap panic must name the `recv()` call's source location, or the error text gets worse than today's "recv on a closed, empty channel"."*
  - **PLT:** A — *"`Option[T]` makes the function total and composes with `?`, `??`, `match` and `iter.from_fn` without special cases."* Concern: *"The `unwrap on None` message says less than "recv on a closed, empty channel". If the unwrap panic does not carry the call-site span, people will find expect-a-value failures harder to diagnose."*
  - **DevOps/Tooling:** A — *"A gives the only compile-time signal. An old call site gets an ordinary E0200 "expected Int, found Option[Int]" with fixes the tool can apply (`?? default`, `match`, `for`)."* Concern: *"An `unwrap on None` panic says less than `recv on a closed, empty channel`; if the unwrap panic does not carry the source span of the call, the runtime message at the `.recv().unwrap()` sites gets worse than today's."*
  - **AI/ML:** A — *"Under A the type checker forces the `None` case at compile time, where C gives a process abort at run time with no recovery (§4.6.3)."* Concern: *"Models will write `.recv().unwrap()` by reflex at fan-in and first-N sites where `None` is the normal outcome, so the spec examples must show `match` / `??` / `?` for those shapes, not only `.unwrap()`."*
  - **Minimalism:** A — *"I count concepts, not tokens. C names one receive but needs a hidden non-panicking one under `for`, and when that hidden receive is exposed later, C turns into B, the largest surface on the table."* Concern: *"A tired author may reach for `.unwrap()` by habit, which gives back C's abort with a worse message. The unwrap panic must carry the call site's span, or A buys little in practice over C."*

- **Q2: How does the spec state `for v in ch`?** (6-0 for 2a: `Channel[T]` joins the §3c sealed `IntoIterator` table with the normative desugaring `for v in ch` ≡ `for v in iter.from_fn(fn() { ch.recv() })`, led by a plain sentence)
  - **Systems:** 2a — *"`iter.from_fn` over a closure that calls `recv()` monomorphizes to a loop around the receive call. It costs nothing, and the loop and `recv` share one code path, so they cannot disagree."* Concern: *"Codegen must actually inline the `from_fn` closure. If the rewrite codegen emits a real closure allocation and an indirect call per element, the "normative" desugaring becomes the slow path in hot drain loops."*
  - **Web/Scripting:** 2a — *"Start the row with the plain sentence ("receives until the channel is closed and empty, then stops") so a reader learns what it does before reading the formal definition."* Concern: *"If the plain sentence is left out, the first thing a newcomer reads is a closure passed to `iter.from_fn`. That is correct, but hard to follow for the one loop they will write most."*
  - **PLT:** 2a — *"Two things the spec already defines (the `recv` rule and `iter.from_fn`) then define `for v in ch`, so the loop and `recv` cannot disagree. Today they can, because each has its own NULL test."* Concern: *"The desugaring has to stay observationally exact: a `break` leaves the remaining elements in the channel, and each iteration makes exactly one `recv`. An implementation that prefetches or buffers would break the equivalence without anyone seeing it."*
  - **DevOps/Tooling:** 2a — *"`blink doc`, hover on `for`, and `blink llms` can show one line of real Blink that the user can also write. The loop and `recv` cannot drift apart, because one is defined by the other."* Concern: *"If codegen special-cases the channel `for` loop for speed rather than going through `from_fn`, it can drift from the stated desugaring; a test must pin that both forms give the same sequence, including a sent `0`."*
  - **AI/ML:** 2a — *"Put the plain sentence first: a model copies the first line it reads."* Concern: *"If the `iter.from_fn` row is the only text, models may copy the desugared form into user code in place of `for v in ch`. The §4.13 example must keep `for v in ch` as the form that is shown."*
  - **Minimalism:** 2a — *"The row defines itself from parts the spec already has (`iter.from_fn`, `recv`). It adds no new concept, only a table row, so the loop and `recv` cannot drift apart."* Concern: *"If the lead sentence and the desugaring ever disagree in wording, readers will quote the sentence. The desugaring must stay the rule, with the sentence only a plain-English gloss."*

- **Q3: How does the spec state the out-of-band closed rule?** (6-0 for 3a: the spec states the guarantee and the invariant, pinned by a property test over `0`, `""`, `false`, `None`; the runtime ABI is implementation, not spec)
  - **Systems:** 3a — *"I withdrew 3b. The spec should state the guarantee and the invariant; the inline-element, bool-return ABI is one way to meet them, and the runtime should stay free to change it (for example to lock-free rings)."* Concern: *"Without the ABI in the spec, an implementation can pass the property test by boxing every element. That is correct but costs one heap allocation per send. The runtime ticket must reject that path on cost."*
  - **Web/Scripting:** 3a — *"For users this is the most important line in the ruling: a sent `0` ending a loop early is a bug nobody would guess, and it would bring a steady flow of "my loop exits early" questions."* Concern: *"If the property test only covers `Int` and `Str`, a `Channel[Option[T]]` or `Channel[Bool]` that goes through a different codegen path can bring the silent loss back unseen."*
  - **PLT:** 3a — *"The guarantee is a statement about meaning: closed is a channel state and never a value of `T`, and every sent value is received in order. That is the part users and later implementations must keep."* Concern: *"If the property test covers only scalar types, a boxed or struct element type that encodes as NULL could bring back the hgd2az data loss without anyone noticing. The test should include one heap-typed and one struct-typed element."*
  - **DevOps/Tooling:** 3a — *"A spec that fixes a C ABI binds the runtime and every future backend to one layout for no user gain."* Concern: *""Implementation, not spec" can become "not done": if the runtime keeps a NULL-slot test for some element types, the property test must cover each element layout (scalar, Str, struct, Option), or the hgd2az data loss survives in the untested one."*
  - **AI/ML:** 3a — *"The guarantee "every sent value is received, in order" is the rule a model needs, and it fits in one sentence."* Concern: *"If the property test is thin (for example, no nested `Option[Option[T]]` element, or no case with several consumers), the old NULL-as-end defect could come back in a shape the test does not cover."*
  - **Minimalism:** 3a — *"The spec should say what users can count on, not how the runtime stores bytes. The guarantee plus the invariant close the `send(0)` data-loss hole in one sentence and leave the runtime free to change."* Concern: *"A guarantee with no test is only words. If the property test over `0`, `""`, `false`, `None` does not land with the ruling, the NULL-sentinel bug can come back quietly."*

- **Q4: What does `send` on a closed channel do?** (6-0 for 4a: panics, decided in this ruling)
  - **Systems:** 4a — *"The runtime already tests `closed` under the lock and returns -1, and codegen drops that result, so a send after close is lost without a sign. Turning that into a panic costs one cold branch."* Concern: *"A producer that is not joined before the close (a detached or long-lived task outside the scope) can race the close and abort. The spec should say that the close belongs after every producer has joined."*
  - **Web/Scripting:** 4a — *"The task that closes the channel owns it, so a send after close is a programmer error the caller can prevent, which is different from reaching the end of a stream."* Concern: *"Users who come from Rust expect `send` to return a Result and may not expect an abort they cannot catch. The §4.13 text must say plainly that close belongs to the producer, and why."*
  - **PLT:** 4a — *"Under `async.scope`, the owner closes the channel after every producer has joined, so "not closed" holds by construction, and a panic is the right tool for a programmer error that correct programs can avoid."* Concern: *"A channel with several producers where one producer closes it (not the scope owner) will panic in a way that depends on the schedule. The spec text should say who closes, so users do not take "the caller can check it" to cover that pattern too."*
  - **DevOps/Tooling:** 4a — *"Today the runtime returns -1 and codegen drops it, so a send after close is lost without a sign. That is the mirror of this ticket's bug."* Concern: *"In multi-producer code where one producer closes, a correct-looking program can abort on a late send; the explain text must say "only the sole owner closes", or users hit this as often as Go users hit double close."*
  - **AI/ML:** 4a — *"If we leave the send side open, the gap comes back on the other side and models will guess from Go (panic), Rust (`Err`) or Kotlin (throw)."* Concern: *"Models trained on Rust will expect `send` to return a `Result` and may write `ch.send(v)?`, so the panic must be stated next to the signature, not only in text about the channel."*
  - **Minimalism:** 4a — *"Deciding it here adds no name and closes the mirror gap, since today's runtime drops a closed send silently."* Concern: *"Several producers that share one channel and close it in a race will abort on a timing fluke, and someone will then ask for a `Result`-returning send. Hold the line until a real program needs it."*

- **Q5: What does a second `close()` do?** (6-0 for 5a: idempotent no-op)
  - **Systems:** 5a — *"A second close is a flag store under a lock the runtime already takes, so it has zero cost. Go's panic on double close is a known footgun in cleanup and defer paths."* Concern: *"Idempotence can hide a real ownership bug, where two tasks each believe they own the close. Without a panic, that bug shows up only as early end-of-stream for consumers."*
  - **Web/Scripting:** 5a — *"Go's double-close panic is one of the most-asked channel questions. A no-op works well with cleanup code and `with` blocks that may close twice, and it costs nothing."* Concern: *"Idempotent close can hide a real bug where two producers each think they own the channel. It is a small risk and worth taking, but the docs should still name one owner."*
  - **PLT:** 5a — *"An idempotent `close` means repeated closes act like a single close, so it composes with cleanup paths and `with` blocks and adds no new failure mode or name."* Concern: *"A no-op second close can hide a real protocol bug, where two parties each believe they own the channel. The spec should still say that the owner is the one who closes."*
  - **DevOps/Tooling:** 5a — *"Cleanup in `with` blocks and on error paths closes twice, and a diagnostic there has no fix the user can apply."* Concern: *"A no-op hides a real ownership bug (two tasks that each think they own the channel); if that becomes common, a debug-build warning is the tool, not a panic."*
  - **AI/ML:** 5a — *"An idempotent close removes a question a model cannot answer from local code ("did another task already close this?")."* Concern: *"Models from Go (where a double close panics) may add guard flags that are not needed, which adds tokens; that noise is harmless."*
  - **Minimalism:** 5a — *"An idempotent close removes a failure mode and adds no API. Cleanup paths do close twice, and Go's double-close panic is a known footgun that buys nothing. 5c leaves an under-determined behavior, which §3.4 forbids."* Concern: *"A no-op second close can hide a real ownership bug, where two tasks each think they own the channel. That bug then shows up as a send-after-close panic far from its cause."*

- **Q6: Constructor spelling (spec `channel.new[T](buffer: N)` vs code `Channel(n)`)** (6-0 for 6b: not part of this ruling; separate ticket to bring code in line with §2.1; rider: that ticket lands before the §4.13 examples are rewritten)
  - **Systems:** 6b — *"OPEN_QUESTIONS §2.1 already decided `channel.new[T](buffer: N)`, so there is nothing to re-rule. The code/spec mismatch is a codegen and stdlib task."* Concern: *"If the rider is not tracked as a hard dependency, §4.13 publishes examples that the compiler rejects, and `blink llms` teaches code that fails to build."*
  - **Web/Scripting:** 6b — *"My concern is examples that don't compile: if the new §4.13 and `blink llms` show a spelling the compiler rejects, a user's first copy-paste fails."* Concern: *"If the rider is not recorded as a real `br` dependency, the §4.13 rewrite can ship first, and for a while users will see spec examples that do not compile."*
  - **PLT:** 6b — *"The constructor spelling has no effect on the typing rule or the closed-state semantics, and OPEN_QUESTIONS §2.1 already decided it. Folding it into this ruling widens the change for no soundness gain."* Concern: *"If the rider is not written as a hard `br` dependency, the §4.13 rewrite can land first and teach a spelling the compiler rejects."*
  - **DevOps/Tooling:** 6b — *"§2.1 already decided `channel.new[T](buffer: N)`, so this is a code bug, not a panel question. My rider stays: every example this ruling publishes must compile."* Concern: *"The dependency gets lost, and the spec edit ships with examples in a spelling the compiler rejects, so the docs and the tool disagree for a release."*
  - **AI/ML:** 6b — *"What matters for models is that each example `blink llms` shows compiles. The web/devops rider (code migration lands before the §4.13 examples are rewritten) gives exactly that. 6a would let the spec show a form that the compiler rejects until the migration lands."* Concern: *"If the rider is written only as a note and not as a `br` dependency, the §4.13 rewrite can land first, and for some time the spec and the compiler will teach two different spellings."*
  - **Minimalism:** 6b — *"The code is behind the spec, which makes it a bug ticket, not a panel question. I accept the web/devops rider: the code fix lands before the §4.13 examples are rewritten, so no published example fails to compile."* Concern: *"The rider can stall the §4.13 rewrite behind a codegen migration during the rewrite, so the spec gap this ticket exists to close stays open longer than it has to."*

- **Q7: Semaphore sites that discard the result (`sem.recv()`), under Q1=A** (6-0 for 7a: bare `sem.recv()` stays legal, no lint; the in-tree semaphore sites write `sem.recv().unwrap()`)
  - **Systems:** 7a — *"A discarded `None` lets an acquire go ahead on a closed semaphore, so two tasks can enter the critical section. That is the same silent-failure class this ticket removes."* Concern: *"Using a channel as a semaphore is a heap ring, a mutex and two condvars that carry a dummy value, where a real semaphore is one atomic counter and a futex. `.unwrap()` makes the misuse safe but can make it look endorsed. A friction ticket for a real sync primitive should follow."*
  - **Web/Scripting:** 7a — *"A discarded Option is not a warning in the language today, so bare `sem.recv()` stays legal for users. This tree is training data, though, and a silent acquire on a closed semaphore breaks mutual exclusion without any sign."* Concern: *"With no lint, user code written in the old style keeps the silent-acquire bug. If it shows up in the wild, reconsider a must-use warning on `recv()`."*
  - **PLT:** 7a — *"`.unwrap()` at the site that knows the protocol puts the panic where the invariant lives. A lint on discarded `Option`s is a separate, language-wide question and should not go into this ruling."* Concern: *"User code still can write a bare `sem.recv()` legally, and it will fail silently in the same way. The same silent-discard problem will come back unless a must-use rule for `Option` results is considered later."*
  - **DevOps/Tooling:** 7a — *"`.unwrap()` states "this channel never closes" at the one place a reviewer or agent reads. This tree is training data, so it should show the explicit form. A must-use lint is out of scope now."* Concern: *"Users copy the bare `sem.recv()` idiom from older examples and get the silent acquire; if that shows up in friction logs, a discarded-Option lint with `recv` in its scope is the next step."*
  - **AI/ML:** 7a — *"Models copy in-tree code, so in-tree `.unwrap()` teaches the correct form without a lint."* Concern: *"With no lint, user and model-written semaphore code will still discard the `Option` in silence. If field data shows this pattern, a must-use warning on `recv()` may be needed later."*
  - **Minimalism:** 7a — *"No lint, because a must-use lint is new surface with one caller today. Two `.unwrap()`s at in-tree sites state the "never closed" invariant and turn a silent broken mutex into a loud abort."* Concern: *"User code will copy the bare `sem.recv()` form from older examples, and a closed semaphore will silently let two tasks into the critical section. The only guard is that we never show the bare form in docs."*

Results: Q1 A, Q2 2a, Q3 3a, Q4 4a, Q5 5a, Q6 6b (with rider: the constructor ticket must land before the §4.13 examples publish; the project owner made it a hard dependency of the implementation ticket), Q7 7a.

### AI-First Review

5/5 pass.

1. **Learnability — pass.** One receive, `Option` like every other absent-value lookup.
2. **Consistency — pass.** Matches the `Option`-returning lookups (`list.get`, `map.get`) and the `iter.from_fn` protocol.
3. **Generability — pass.** One method; `for` is the common drain.
4. **Debuggability — pass.** E0200 type mismatch when a caller uses the `Option` as `T`; the unwrap panic names the `recv` site.
5. **Token Efficiency — pass.** `for v in ch` is the common form; `?? d` and `.unwrap()` are short.

### Final Spec

```blink
// Channel[T] operations (§4.13)
ch.send(value)      // blocks while the buffer is full; panics if ch is closed
ch.recv()           // -> Option[T]; blocks; None only when ch is closed and drained
ch.close()          // buffered values stay receivable; a second close is a no-op

// for over a channel (§3c.1)
for v in ch { ... }
// is exactly
for v in iter.from_fn(fn() { ch.recv() }) { ... }
```

- `recv()` is the one blocking receive. It returns `None` only when the channel is closed and every buffered value is received. No `try_recv`, no `is_closed()`.
- A drain receives every sent value, in order; a sent value is never end of stream. Closed is a state of the channel, never a value of `T` — `0`, `""`, `false` and `None` (on `Channel[Option[T]]`) all arrive as `Some(...)`.
- `send` on a closed channel panics. One owner closes the channel, after every producer has joined.
- A second `close()` is a no-op.
- `Channel[T]` joins the sealed `IntoIterator` table; a `for` loop drains the channel once.
- Discarding a `recv()` result is legal. Code that must not go on past a closed channel writes `ch.recv().unwrap()`.
- Constructor spelling is not part of this ruling: `channel.new[T](buffer: N)` stands (OPEN_QUESTIONS §2.1). Bringing the code (`Channel(n)`) in line is separate work that must land before the §4.13 examples publish.
