[< All Decisions](../DECISIONS.md)

# BlockHandler State Between `enter` and `exit` — Design Rationale

`BlockHandler.enter(self)` takes `self` by value, and assignment to a parameter or its field is a
compile error (§3.6). So `enter()` cannot pass state to `exit()`. The §4.6.3 Timer example wrote
`self.start = time.now()` in `enter` anyway, with a "do not copy" note next to it, and a note next to
wrong code is still wrong code in the training data. A scoped effect handler (Context =
`Handler[E]`) must hold its resource from construction, so entering one value twice runs `exit()`
twice, for example `sqlite3_close` on a freed handle. The scoped effect handler panel deferred two
fixes: `exit(self, ctx, ok)` and a lazy descriptor that opens in `enter`.

Panelists quote the old example's `time.now()` below. The old example also declared the record
with `struct`. Neither is Blink: a record is declared with `type`, and the clock is `time.read()`
with `Instant.elapsed()` (§3). The final spec uses those forms.

The panel answered six questions:

- Q1: the trait shape now.
- Q2: a lint for double entry.
- Q3: runtime behaviour of a second `exit`.
- Q4: what this record fixes for the future trait change.
- Q5: the Timer `enter` body.
- Q6: repair text on the parameter-assignment error.

Phase D added Q1-arena: the wording of the arena sentence in §5.5.

**A note on quotation.** Panelist text below is verbatim, with headings shown in bold. The one
exception is `br` ticket identifiers: `br` is local-only, so each is replaced by a bracketed
description of the ticket. No other substitution was made.

---

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in
independent-proposal → debate → vote rounds. Phase A produced six proposal sets. Phase B ran one
round. Phase C was a silent vote; Q1, Q2 and Q4 were closer than 5-1, so Phase D ran one focused
debate round on them and a final silent re-vote.

Option labels used in the votes, from the deduped Phase A option-space:

- **A**: no trait change. A scoped value gets all its state when it is built, by a factory call in
  the `with` item.
- **B**: `exit(self, ctx: Self.Context, ok: Bool)`. State passes through `Context`.
- **C**: a second associated type `State`, seen only by `exit`; `enter` returns
  `(Self.Context, Self.State)`.
- **L.3**: a new code, W0611 `ScopedValueEnteredTwice`, for a value that reaches more than one
  `with`, with a loop trigger. **L.1**: the same check folded into W0610. **L.State**: the check
  keyed on `State == ()`.
- **R.2-stdlib + R.3**: the stdlib's native handles make a second close defined; user impls get
  "should" guidance. **R.2-normative**: a "must" rule on every `exit`. **R.1**: no rule.
- **Q4-i**: the record names the `State` shape, to land as one trait change with the fallible-enter
  ticket. **Q4-ii**: the record names the need only.
- **Q5-a**: Timer `enter` is `{}`, with a lint chore so that UnusedVariable skips a `self` the
  trait requires. **Q5-b**: `let _ = self`.


#### Phase A — Independent proposals

Each panelist's stated preference, verbatim (the full proposal texts are longer; this is the closing preference section of each).

- **Systems:**

> **P1 + P3.**
>
> - P1 costs nothing at runtime and gives the trait the state channel that arena already uses internally. It fixes the Timer example properly, so the "do not copy" note and the wrong code both go away.
> - It makes double entry correct for every acquire-in-enter type.
> - P3 changes a silent UAF into a defined panic for the one class P1 cannot reach (eager, fallible-open resources), at a cost hidden behind a syscall.
> - Neither needs [the fallible-enter ticket]. Both stay correct if [the fallible-enter ticket] lands later.
> - I reject P2 as YAGNI until a fallible `enter` exists and someone shows a lazy resource that cannot be eager.
>
> **Open point for the panel:** the no-`as` relaxation for a concrete non-unit `Context` is the one part of P1 that changes the §4.7 table. The fallback is to make Timer users write `with timer("x") as _ { }`. That is worse ergonomics for the same codegen.

- **Web/Scripting:**

> It matches what JS, Python, Kotlin and C# developers already expect: you hold the thing, and the block closes it. It fixes the Timer with a shorter call site and turns the sqlite use-after-free into a clear runtime error. It costs no breaking change. P1 does not deliver lazy open for Connection without a second associated type and [the fallible-enter ticket], and it makes the common `with timer(..) { }` an E0839 error.
>
> If [the fallible-enter ticket] later adds a fallible `enter`, a lazy-open variant can come as an additive trait or associated type without breaking P2 code. Until a user asks for a reusable recipe value, YAGNI applies.
>
> **Requests to the moderator:**
>
> 1. Put the "exit must be idempotent" sentence in §4.6.3 and §5.5 together, so Closeable and BlockHandler share one rule.
> 2. Use `timer(label)` as the canonical §4.6.3 example, replacing the struct literal with `start: time.now()`.

- **PLT:**

> It is the only option that composes with all three things already decided:
> - the §4.7 table, because the dispatch on `Context` does not change;
> - scoped effect handlers, because `State` is separate from the opaque `Handler[E]`;
> - the arena semantics, which are already an instance of it.
>
> It fixes Timer correctly, including nesting. It makes double entry sound for every enter-acquired resource without an affine check, which the scoped effect handler panel rejected because it does not survive aliasing. And it leaves a fallible `enter` ([the fallible-enter ticket]) as a separate question. P2 is the precondition that makes a lazy open worth adding, and this panel should say so on [the fallible-enter ticket].

- **DevOps:**

> P1's main use case is the ticket's headline bug, and it cannot fix that. Every case it does fix (Timer, an env-var snapshot and restore) works just as well when the value is built in the `with` item. With P0's lint, a value built early or entered twice gets a warning with a fix that points at the exact line.
>
> If lazy open is ever wanted, the right change is [the fallible-enter ticket]'s fallible `enter` together with a State slot. That should be one trait change, so the 28 tests and the 3-step bootstrap are paid for once, not twice. Record P1 as deferred to that combined change. Fix the Timer example now, so no wrong code stays in the spec.

- **AI/ML:**

> - A makes the correct Timer the obvious one-step code, gives the §3.6 assignment error a clear repair text, and removes the wrong example from the corpus.
> - D closes the use-after-free the ticket names, with one rule models already follow.
> - Together: no new syntax, no new type, one table row; stateless impls gain only `_ctx`.
>
> **Concern.** Under A, `with Timer {..} as t` binds `t` to an `Instant` — odd to read but harmless. The §4.7 row text must say "context goes only to `exit`" so implementations do not differ on that row.

- **Minimalism:**

> - M1 is the only proposal that removes the wrong code from the training data today with zero new surface.
> - The double-entry hazard it leaves is the same one Blink already accepts for `Closeable`. It is guarded by the same single lint trigger the last panel voted for.
> - M2 is a breaking change that, on inspection, fixes neither motivating case, because `Context` already has a job: it is the user-visible binding or the installed handler. Overloading it as hidden state collides with E0839.
> - M3 is the correct shape if state passing ever becomes necessary. It is gated on [the fallible-enter ticket] and on a demonstrated need (YAGNI), so the panel should file it as a dependent follow-up, not adopt it now.
>
> I have one condition on M1: the shared-cell paragraph must show a concrete `let mut`-capture example. Otherwise authors will try `self.x = ...` again and get E0610-class errors with no path forward.

#### Phase B — Debate highlights

One round ran; all six ended it with "STATUS: stable, ready to vote". Each panelist's own "change of position" section, verbatim:

- **Systems:**

> Q1: from B to C, for PLT's composition argument plus the arena case. Q2: from R.1 to R.2 (scoped), and L.1 keyed on `State == ()`.
>
> STATUS: stable, ready to vote

- **Web/Scripting:**

> - I drop my proposal that native wrappers *must* use a closed flag. R now states the outcome, not the mechanism, so it covers Sys's claim-panic too.
> - I adopt DevOps's loop trigger and diagnostic for the lint.
> - I add two requests: the help text on the self-field assignment error, and a lint chore for the warning on an unused `self`.
>
> STATUS: stable, ready to vote

- **PLT:**

> - **Tuple order:** I concede `(Context, State)`, which four panelists wrote.
> - **Timing:** I move from "C only" to "C now, or A plus C deferred and bundled with [the fallible-enter ticket]".
> - **Unchanged:** B stays last.
>
> STATUS: stable, ready to vote

- **DevOps:**

> - Q2: I adopt Web's closed-state tracking for stdlib native wrappers. It is a stronger backstop than my "should be idempotent" sentence.
> - Q2: I adopt AI/ML's "exactly one `with`" as the rule wording, under my separate code W0611.
> - New ask: the ParamAssign help text above, as part of this ticket's fix.
>
> STATUS: stable, ready to vote

- **AI/ML:**

> **B to A.** In Phase A my case for B was "one-step repair text" for the Python habit of `self.start = now()`. Under A the repair is just as short: "set it when the value is built: `Timer { label: label, start: time.now() }` in a factory." I need one condition: the §3.6 assignment error, when it fires inside a BlockHandler `enter`, carries that help text. With that in place, A gets the AI/ML benefit at zero signature churn, with no `_ctx: ()` noise across about 31 impls, and with E0839's catch intact.
>
> STATUS: stable, ready to vote

- **Minimalism:**

> I withdraw the A.1 shared-cell example, for PLT's reason. Per-value cells are wrong under re-entry, and the spec must not teach them.
>
> I switch L.1 to L.3, for DevOps's reasons: a distinct code can be suppressed, and the loop trigger catches a real case that L.1 misses.
>
> STATUS: stable, ready to vote

#### Phase C — Silent vote

- **Q1: trait shape now**: A 4-2 (Web, DevOps, AI/ML, Min for A; Sys, PLT for C). Went to Phase D.
- **Q2: double-entry lint**: L.3 4-1-1 (Sys for L.State, with a fallback to L.1 under A; PLT for
  L.1). Went to Phase D.
- **Q3: runtime**: R.2-stdlib + R.3, 6-0.
- **Q4: future record**: Q4-i 4-2 (Web, Min for Q4-ii). Went to Phase D.
- **Q5: Timer example**: Q5-a, 6-0.
- **Q6: repair text**: Yes, 6-0.


Full Phase C ballots, verbatim:

- **Systems:**

> **Q1: Trait shape now**
> **Vote:** C
>
> **Reasoning:** The spec says `with arena { }` behaves as a BlockHandler. But `arena` is one value that is entered many times and nests, and its per-entry state (the new arena plus the previous TLS pointer) cannot live in the value. Under A, that claim is false, and `wrap_arena` stays a codegen special case that the trait cannot describe. C costs nothing at runtime: one more stack local, mono-resolved direct calls, and a unit `State` lowers to nothing. It also leaves the §4.7 table and E0839 as they are, which B does not.
>
> **Concern:** If A wins, every save/restore handler (env override, log-level push, signal masks) is written with a snapshot at build time. That gives stale restores on reuse and on nesting, which the lint only warns about.
>
> **Q2: Double-entry lint**
> **Vote:** L.State
>
> **Reasoning:** Under C, a value whose `State` is non-unit is a descriptor: each entry gets its own state, so a second entry is correct and must not warn. `State == ()` is the type-level sign that all state was fixed at build time, so a second `exit` repeats the release. That is exactly the hazard. If Q1 is A, my vote falls back to L.1, because the existing code and the existing flow analysis are enough.
>
> **Concern:** L.3's "exactly one `with`" wording will warn on correct reuse of descriptor values if the trait ever gets a `State` slot, and it would then need rewording.
>
> **Q3: Runtime behaviour of a second `exit`/`close`**
> **Vote:** R.2-stdlib + R.3
>
> **Reasoning:** A closed flag behind the native handle costs one word and one branch per call, which no one can measure next to `sqlite3_open`. It turns a use-after-free into a defined `Err`. It cannot be a normative rule for every `exit`: `Cleanup` runs a user closure and cannot be idempotent.
>
> **Concern:** The closed flag has to live in memory that outlives the native handle (a shim wrapper). If the shim frees the wrapper together with the handle, the check reads freed memory, and the guarantee is lost.
>
> **Q4: What the decision records for the future**
> **Vote:** Q4-i
>
> **Reasoning:** If Q1 is not C, the shape should still be fixed now. Then [the fallible-enter ticket] lands as one trait change, and the 28 test files and the 3-step bootstrap are paid for once. Codegen for that shape is already known: the arena restore struct.
>
> **Concern:** "One trait change" ties a useful `State` slot to an open ticket that has no date. Meanwhile, save/restore handlers keep shipping with build-time snapshots.
>
> **Q5: §4.6.3 Timer example**
> **Vote:** Q5-a
>
> **Reasoning:** An unused `self` in a trait impl method is a false positive in the lint, not something the example should work around. If the spec example uses `let _ = self`, every model copies that noise. Fix the lint, not the example.
>
> **Concern:** If the lint chore slips, the spec example warns when you compile it. That is worse than the noise, so the chore must block the spec edit.
>
> **Q6: Repair text on the parameter-assignment error**
> **Vote:** Yes
>
> **Reasoning:** A one-step, local repair costs nothing and stops the Python habit at the error. The help text must follow Q1. Under C, it says "return it as `State` from `enter`; `exit` receives it". Under A, it uses the ballot's build-time wording.
>
> **Concern:** If Q1 later moves to C, help text written for A will teach the wrong repair unless someone updates it in the same change.

- **Web/Scripting:**

> **Q1: A**
> **Reasoning:** "You hold the thing, and the block closes it" is how Python `open()`, JS `using`, Kotlin `use` and C# `using` all work. A JS or Python developer predicts it with no docs. With the factory in the `with` item, each entry gets a fresh value, so Timer and nesting are correct with no trait break. B binds an `Instant` through `as` and adds a dead `_ctx: ()` everywhere. C pays for a future that does not exist yet.
> **Concern:** some authors will still build the value early and store it. The lint and the repair text (Q6) must be good enough that they find the factory pattern on the first try.
>
> **Q2: L.3**
> **Reasoning:** a separate code with a plain name, `ScopedValueEnteredTwice`, tells the user what went wrong. A second meaning folded into ScopedValueWithoutWith would mislead: the value *did* go into a `with`. The loop trigger catches the most common real mistake: connect outside the loop, `with conn` inside it. A fix the tool can apply makes the warning cheap to act on.
> **Concern:** the lint loses track of a value once it crosses a function boundary. The docs must say so, or users will read silence as a guarantee.
>
> **Q3: R.2-stdlib + R.3 (changed from my round-1 position)**
> **Reasoning:** on a second look, my normative "must fail deterministically or do nothing" rule makes the stdlib's own `Cleanup` non-conforming, because it runs its action twice. A user-facing "must" that the compiler cannot check, and that the stdlib breaks, makes a bad spec rule. Defined behavior in the stdlib native wrappers fixes the real use-after-free. Guidance covers user code.
> **Concern:** "should be idempotent" guidance is easy to skip. A user's own FFI wrapper can still double-free, and only the lint stands in front of it.
>
> **Q4: Q4-ii**
> **Reasoning:** record the need (a fallible `enter` plus a state slot separate from `Context`), not the exact shape. The shape should come from [the fallible-enter ticket]'s panel once a real consumer exists. Fixing tuple order and naming now is design work with no user. I still want the note to say both pieces should land in one trait change, so the 28 tests and the bootstrap are paid for once.
> **Concern:** without a named shape, a later panel may reopen P1 (`exit(self, ctx, ok)`), which this panel found does not fix Connection.
>
> **Q5: Q5-a**
> **Reasoning:** the spec example is what models and people copy. `let _ = self` is noise that would spread into every `Context = ()` impl. Python, JS and Rust never warn on an unused `self`, so the lint is the bug, not the example.
> **Concern:** if the lint chore slips, the canonical example warns on first compile, and copying the spec gives a warning on day one.
>
> **Q6: Yes**
> **Reasoning:** a Python developer *will* write `self.start = time.now()` in `enter`. An error that says only "cannot assign to a parameter" leaves them stuck. Help text that names the fix ("set it when the value is built; build the value in the `with` item, §4.6.3") turns the most likely mistake into a one-step repair.
> **Concern:** the help must fire only inside a BlockHandler `enter`. A generic version on every self-field assignment would point users at the wrong pattern.

- **PLT:**

> **Q1 — C**
> **Reasoning.** C is the only shape that keeps one meaning per associated type. `Context` is what the body sees, and `State` is what only `exit` sees, so the §4.7 table and E0839 do not change. The body cannot name `State`, so it cannot copy or release the witness. That needs no ownership rule. It is the `bracket` shape, and it fixes Timer and makes nested or repeated entry correct by construction.
> **Concern.** If A wins, a later panel may land B as a "smaller" step, which would cost two trait breaks. Q4-i must prevent that.
>
> **Q2 — L.1**
> **Reasoning.** "Reaches exactly one `with`" is the same flow fact as ScopedValueWithoutWith, so one analysis and one code keep the rule set small and compositional. A second code for the same fact splits the explanation without adding precision.
> **Concern.** Either code stops at function boundaries, and the spec text must say so, so that no one reads the lint as a type guarantee.
>
> **Q3 — R.2-stdlib + R.3**
> **Reasoning.** A normative "must" on user `exit` is a proof obligation the language cannot check, so the spec would promise what it cannot keep. The stdlib can keep that promise for its own native handles, and that turns the use-after-free into defined behaviour.
> **Concern.** User-written native wrappers keep the hazard, and only guidance covers them.
>
> **Q4 — Q4-i**
> **Reasoning.** Fix the shape now so the future change is one break, not two. Naming `(Self.Context, Self.State)` also rules out B as a step on the way.
> **Concern.** None from my domain.
>
> **Q5 — Q5-a**
> **Reasoning.** An unused `self` should not warn. `let _ = self` in the canonical example would teach a workaround for a lint bug, and that becomes training data.
> **Concern.** The lint chore must land before the example ships, or the spec example warns.
>
> **Q6 — Yes**
> **Reasoning.** An error with no repair path invites another wrong workaround. The help text must follow Q1: under C it says "return it as `State`; `exit` receives it", and under A it says "build it in the `with` item".
> **Concern.** If the help text is written for A and C wins, the hint points users the wrong way.

- **DevOps:**

> **Q1 — A**
> **Reasoning.** A fixes the Timer example now with no trait break. The tools do the rest: the ParamAssign repair text (Q6) and W0611 (Q2). B breaks Connection and E0839's second job, and it makes hover show `t: Instant` for a timer. C is the right shape, but it puts `type State = ()` and a tuple return in every impl's signature help, for no case on this ticket.
> **Concern.** A stored value built early and entered once later still measures or acts from build time. No lint catches that, and the docs must say so.
>
> **Q2 — L.3**
> **Reasoning.** A separate code lets a team set `W0611 = "error"` and keep W0610 as a warning. W0610 has real false positives in pool or framework code. A second entry is almost never intended. One flow analysis can serve both codes. The quick-fix is machine-applicable when the item is a call, so the LSP can apply it in one click.
> **Concern.** The lint does not cross function boundaries. Users may read "no W0611" as "cannot double-enter", so the explain text must name that blind spot.
>
> **Q3 — R.2-stdlib + R.3**
> **Reasoning.** The stdlib can enforce a runtime guarantee, and the `Err(ConnectionError("connection is closed"))` it gives flows through `?` to a readable message. A normative "must" on every user `exit` cannot be checked by any tool, and `Cleanup` breaks it on purpose. A rule that no tool enforces is noise in the training data.
> **Concern.** Third-party native wrappers will skip closed-state tracking unless the FFI docs show the pattern next to the `@ffi` examples.
>
> **Q4 — Q4-i**
> **Reasoning.** If we record the shape now, the next panel does not reopen it, and the 28 tests and the 3-step bootstrap are paid for once, in the same change as [the fallible-enter ticket]. Leaving the shape open invites a second breaking change later.
> **Concern.** The `(Context, State)` tuple order fixed here may not suit whatever fallible-`enter` signature [the fallible-enter ticket] picks. The note should say the order may be revised in that one change.
>
> **Q5 — Q5-a**
> **Reasoning.** An unused-variable warning on a `self` that the trait requires is a lint bug, not a style the spec should teach. `let _ = self` is a workaround, and it would spread to every user's no-op `enter`. Land the example with `{}` and file the lint chore so that `UnusedVariable` skips trait-mandated `self`.
> **Concern.** Until the chore lands, the spec example warns when users copy it, so the chore needs priority and a test.
>
> **Q6 — Yes**
> **Reasoning.** This is the diagnostic every Python-trained author will hit first. A help line that names the exact one-step repair turns a dead end into a local edit, and an LSP quick-fix can follow it.
> **Concern.** The help needs to tell the BlockHandler `enter` case apart from a plain method assignment. If it fires the BlockHandler text on every `self.x = ...`, it misleads.

- **AI/ML:**

> **Q1 — Trait shape now**
> 1. **Vote:** A
> 2. **Reasoning:** Each trait-signature revision leaves a generation of old-shape code in the corpus, and models then mix the shapes. A changes no signature, adds no `_ctx: ()` noise to about 31 impls, and keeps E0839 as a loud, repairable error. A model can read the factory form (`with timer("x") { }`) straight from the spec, and it matches the eager `open()` habit models already have from Python, Go and C#.
> 3. **Concern:** Python-trained models will still write `self.start = time.now()` in `enter`, so A is only as good as the Q6 repair text and the Q2 lint that catch the stored-and-re-entered case.
>
> **Q2 — Double-entry lint**
> 1. **Vote:** L.3
> 2. **Reasoning:** A separate code with its own name gives `blink explain` and the diagnostic one exact cause to state ("goes into two `with` items"), and that is what a generated-code repair loop needs. Folding it into ScopedValueWithoutWith would give one code two opposite causes (zero `with` vs two). The loop trigger catches the form models produce most often: a value built once above a `for` and entered in each pass.
> 3. **Concern:** a value that passes through a helper function and is entered there is not tracked, so the lint is silent in a way a model cannot predict. The explain text must state this limit.
>
> **Q3 — Runtime behaviour of a second exit/close**
> 1. **Vote:** R.2-stdlib + R.3
> 2. **Reasoning:** The stdlib is the code models copy and call most, so a defined `Err("connection is closed")` there turns the worst case into an error message a model can act on. A normative rule on all user code cannot be checked, and a rule nobody can check teaches nothing. Guidance is enough for user impls.
> 3. **Concern:** "should be idempotent" may read as optional, so user `Cleanup`-style impls will keep running side effects twice. The doc must name `Cleanup` as the example.
>
> **Q4 — What the decision records for the future**
> 1. **Vote:** Q4-i
> 2. **Reasoning:** The clause that matters most to me is "both land in ONE trait change". It caps the signatures in the corpus at two. Naming the shape now also stops a future panel from adding the state channel to `Context` (the B shape), which this panel found breaks E0839.
> 3. **Concern:** naming a shape that is not adopted may let it leak into docs or examples before it exists. It must appear only in the decision record, not in sections/.
>
> **Q5 — Timer example**
> 1. **Vote:** Q5-a
> 2. **Reasoning:** A spec example is the most-copied text in the corpus. `let _ = self` would teach a noise idiom that models then add to every trait method. A warning on a trait-mandated `self` is a lint bug, and the example should show the long-term form.
> 3. **Concern:** if the lint chore lands after the example, the canonical example warns. The chore must land in the same change, or before it.
>
> **Q6 — Repair text on the parameter-assignment error**
> 1. **Vote:** Yes
> 2. **Reasoning:** This is the single most likely error a Python-trained model will hit with BlockHandler. A help line that names the fix and the section makes the repair one step, and that one step makes A as cheap to learn as B would have been.
> 3. **Concern:** the help must fire only inside a BlockHandler `enter`, not on every field write to `self`, or it sends models toward a factory in places where a `let mut` copy is the right fix.

- **Minimalism:**

> **Q1 — A**
> **Reasoning:** A closes [the Timer example ticket] by deleting wrong code. It adds no trait surface, needs no bootstrap and changes none of the 28 test files. B fixes only Timer, which a factory already fixes, and it cannot fix Connection. B and C are rival futures, so taking either now risks a second break when [the fallible-enter ticket] lands. Per-entry state has no use case today that eager construction cannot serve.
> **Concern:** Authors will store a scoped value and enter it twice. The fix for that rests on a lint, not on a guarantee.
>
> **Q2 — L.3**
> **Reasoning:** It adds no new analysis: it reuses the W0610 flow check with one more trigger, the loop case. A separate code can be suppressed on its own (`Cleanup` entered twice is legal) and gives tooling a clear target for the quick-fix. The rule wording "reaches exactly one `with`" is simpler than the current "at least one".
> **Concern:** A value that is passed to a helper and entered there is not tracked. Users may read silence as safety, so the spec must state this limit.
>
> **Q3 — R.2-stdlib + R.3**
> **Reasoning:** The stdlib owns the native handles, so it can make a second close defined at no cost to the language surface. A normative "must" on user `exit` cannot be checked and would conflict with `Cleanup`, which runs its action twice by design. "Should" guidance is honest about what the compiler checks.
> **Concern:** Third-party native wrappers will skip the closed flag. The stdlib docs must show the pattern so authors copy it.
>
> **Q4 — Q4-ii**
> **Reasoning:** Record the dependency (fallible `enter` plus a state slot separate from `Context`) so the next panel does not rediscover it. Do not fix a shape this panel did not adopt. Naming the tuple order and the trait text now pre-decides a design that [the fallible-enter ticket]'s panel should own, with its own evidence. Q4-i's "one trait change" bundling is good advice, and I would accept it as a non-binding note.
> **Concern:** The [the fallible-enter ticket] panel may add a fallible `enter` alone and leave the state slot for later, which breaks the trait twice.
>
> **Q5 — Q5-a**
> **Reasoning:** The spec should show the plainest correct code, and `{}` is that code. `let _ = self` is a workaround for a lint false positive and would spread through the training data as an idiom. Fix the lint instead: an unused `self` in a required trait method is not a defect.
> **Concern:** If the lint chore stalls, the canonical example warns when compiled. That chore must block publishing the example, not follow it.
>
> **Q6 — Yes**
> **Reasoning:** It is help text on an error that already fires, so it adds no language surface. It gives a one-step local repair and closes the gap that a trait change would otherwise claim to fill. Help text is also where models learn the idiom fastest.
> **Concern:** The help must fire only in the BlockHandler `enter` context. If it fires on every parameter assignment, the advice becomes noise.

#### Phase D — Round 2 (Q1, Q2, Q4)

The ballot for the re-vote added two choices from the Phase D replies. Q1-arena: the wording of
the §5.5 sentence "`with arena { }` behaves as a BlockHandler" if A wins. X (Sys, PLT) says arena
is compiler-defined, with per-entry state a user BlockHandler cannot express. Y (DevOps, AI/ML, Min)
says it behaves as if the compiler builds a fresh scope value at each entry. For Q2 the ballot
offered PLT's wording, "a value whose state is fixed at build time reaches exactly one `with`",
beside the plain wording. For Q4 it offered DevOps's amendment.

Final result:

- **Q1: trait shape now**: **A, 4-2** (Sys, PLT dissent for C). Phase D cap reached; the majority
  ships with the dissent recorded.
- **Q1-arena**: **Y, 6-0** (Sys and PLT moved from X).
- **Q2: double-entry lint**: **L.3, 6-0**. Wording: **plain "reaches exactly one `with`", 4-2**
  (Sys, PLT for PLT's wording).
- **Q4: future record**: **Q4-i plus DevOps's amendment, 6-0** (Web and Min moved from Q4-ii).


Phase D debate replies, verbatim:

- **Systems:**

> **Q1: I stay on C. If A wins, I have one condition.**
>
> None of the four A ballots answers the arena case.
>
> Web says "with the factory in the `with` item, each entry gets a fresh value, so Timer and nesting are correct". That is true only when the item is a call. `with arena { }` is not a call. `arena` is one value that is entered many times, and it nests. Its per-entry state (the new arena plus the previous TLS pointer) cannot be fixed at build time. §5.5 line 110 says it "behaves as a BlockHandler (§4.6.3)". Under A, that sentence is false: no BlockHandler impl can do what it describes.
>
> Min says "per-entry state has no use case today". Arena is a use case today. The compiler meets it with a special case (`wrap_arena`) that the trait cannot express.
>
> The cost argument from AI/ML and DevOps is real: ~31 impls, `type State = ()` noise, and a second shape in the corpus. I accept that it is the majority view.
>
> **Condition if A wins:** the decision must amend §5.5 line 110. The new text should say that `with arena` uses compiler-held per-entry state that a user BlockHandler cannot express, and it should name Q4's State slot as the path to remove that special case. Otherwise the spec makes a false claim about its own construct, and that is the kind of wrong text this ticket exists to remove.
>
> **Q2: I change to L.3.**
>
> Under A, my L.State has nothing to key on, so the choice is between L.1 and L.3. Two arguments move me:
>
> - **DevOps:** a separate code lets a team set W0611 as an error and keep W0610 as a warning. That is a real deployment control.
> - **AI/ML:** one code with two opposite causes (zero `with` vs two) gives a worse repair message.
>
> Both lints use one flow analysis, so the cost is the same. **Concern:** if a State slot lands later, the rule "reaches exactly one `with`" warns on descriptor values that are correct to re-enter. The W0611 text should say that a future State-carrying type may exempt itself.
>
> **Q4: I stay on Q4-i, with DevOps's amendment.**
>
> To Web and Min: naming the shape is not design work with no user. It excludes B, which this panel found breaks E0839 and the §4.7 table. If we record only "a slot separate from `Context`", B-shaped variants stay open, and the next panel has to work that out again. I accept DevOps's wording: the tuple order may be revised in the one combined change with [the fallible-enter ticket]. I also accept AI/ML's limit: the shape goes in the decision record only, not in sections/.
>
> Min's concern is that [the fallible-enter ticket] adds a fallible `enter` alone and breaks the trait twice. That is exactly what Q4-i's "one trait change" clause prevents, so it is an argument for Q4-i.

- **Web/Scripting:**

> **Q1: A (holds)**
>
> **Sys, on save/restore handlers giving stale restores:** that happens only when the value is stored. With the factory in the item, `with env_override("X", "1") { with env_override("X", "2") { } }` takes each snapshot right before its own `enter`. Nesting is correct, as it is for Timer. Stored-and-re-entered values are the case W0611 exists for.
>
> **Sys, on arena:** "with arena behaves as a BlockHandler" describes how it behaves on unwind. It does not promise that a user can write arena. No user has asked to write one. Keeping `wrap_arena` as a codegen special case costs users nothing.
>
> **PLT, on C as the bracket shape:** I agree that C is the right shape *when* a consumer exists. Today, every impl would pay `type State = ()` plus a tuple return in signature help, and no case on this ticket needs it. AI/ML's corpus point decides it for me: each signature revision leaves a generation of old-shape code. Change the trait once, when [the fallible-enter ticket] gives a reason.
>
> **Q2: L.3 (holds)**
>
> **PLT, on one fact needing one code:** to the user these are opposite facts, "your value never reached a `with`" against "it reached two". A JS developer reads the code name and the first line. One code with two causes means a longer `explain` and a vaguer quick-fix. DevOps's point also stands: teams want W0611 as an error while W0610 stays a warning.
>
> **Sys, on L.3 warning on correct descriptor reuse if `State` lands:** true. Reword the lint in that same trait change. That costs one sentence, in a change that already rewrites 28 tests.
>
> **Q4: moves to Q4-i**
>
> I voted Q4-ii so as not to pre-decide [the fallible-enter ticket]'s design. Two ballots changed my mind:
>
> - **AI/ML and PLT:** naming the shape rules out B. B is the option that would make hover show `t: Instant` for a timer, the worst DX result this panel looked at.
> - **Min's own concern:** under Q4-ii, [the fallible-enter ticket] could ship a fallible `enter` alone and break the trait twice. Q4-i's "one trait change" prevents that.
>
> I take Q4-i with two caveats:
>
> 1. DevOps's caveat: the tuple order may be revised in that one change.
> 2. AI/ML's caveat: the shape is recorded only in `decisions/`, never in `sections/`, so no example teaches a trait that does not exist.

- **PLT:**

> **Q1: I hold C**
>
> Sys's arena point is the strongest argument made in this panel, and no ballot for A answers it. §4.6.3 says `with arena { }` "behaves as a BlockHandler". Arena is one value that is entered many times and nests, and its per-entry state cannot live in the value. Under A, that sentence is false. The spec would describe a construct through a trait that cannot express it, and the codegen special case becomes a permanent exception.
>
> Web and Min say A makes nesting correct. That holds only when the item is a fresh factory call. "Correct if you build it in the item" is a usage convention that a lint enforces, not a property of the trait.
>
> If A wins anyway, the decision record must amend the arena sentence. It should say arena is compiler-defined and is not expressible as a user BlockHandler. Otherwise the spec states something false.
>
> **Q2: I change to L.3, with one condition**
>
> AI/ML and Web are right on the theory. "Reaches zero `with`" and "reaches two `with`" are different predicates. One code that covers both gives `blink explain` a disjunction, not a cause. DevOps's severity split, an error for W0611 and a warning for W0610, is a second, independent reason.
>
> My condition comes from Sys's concern. The rule text must say "a value whose state is fixed at build time reaches exactly one `with`". It must not say "every scoped value". Then a future `State` slot narrows the trigger (Sys's L.State) without rewording the rule, and correct reuse of a descriptor value never warns.
>
> **Q4: I hold Q4-i, and accept DevOps's amendment**
>
> Min's own concern is the case for Q4-i. If the record names only "a state slot", the [the fallible-enter ticket] panel can land a fallible `enter` alone and leave the slot for later, which is two breaks. Web's concern says the same thing from the other side: without a named shape, a later panel can reopen B, which this panel showed fixes neither Connection nor E0839.
>
> Naming the shape is not design work with no user. It records the one shape this panel found sound: the body sees `Context`, and only `exit` sees `State`. I accept DevOps's wording that the tuple order may be revised in that one change. I also accept AI/ML's condition that the shape appears only in the decision record, not in sections/.
>
> **Summary**
> - **Q1:** C (holds). If A wins, the record must fix the arena sentence.
> - **Q2:** L.3 (changed from L.1), with the trigger worded for build-time state.
> - **Q4:** Q4-i (holds), with "the order may be revised in the same change".

- **DevOps:**

> **Q1 — A holds**
>
> **Sys (arena).** This is the strongest argument for C. But the claim only fails because `arena` is spelled as a *value* that is entered many times. Under A, the restore snapshot is taken when the item is evaluated, and that is step 1, right before `enter`. Nested `with arena { with arena { } }` evaluates the item twice and gets two snapshots, so nesting is correct. What A cannot express is a single *stored* value reused as a descriptor. W0611 flags that case in user code. `with arena` is compiler-built, so it never hits it. I ask that the decision say so in one line, to keep §4.6.3's "behaves as a BlockHandler" honest. I do not ask for a trait change.
>
> **Sys (stale save/restore).** Under A, an env-override built in the item takes its snapshot at entry. It goes stale only when stored, and W0611 reports that with a fix that points at the line. That is a warning with a repair, not a silent bug, and it is the tooling bar this ticket needs.
>
> **PLT (C is principled).** Agreed. C costs `type State = ()` plus a tuple in about 31 signatures and hover cards, and no case on this ticket needs it. Q4-i keeps that shape on record, so A now does not block C later.
>
> **Q2 — L.3 holds**
>
> **PLT (one fact, one code).** These are not one fact. W0610 says "never reached a `with`". W0611 says "reached two". AI/ML and Web are right that one code would carry two opposite causes, and `blink explain` would need a branch to say which one fired. Severity is the practical point. W0610 is often `@trusted` in pool code. W0611 is almost never intended, and teams will want it as an error alone. One analysis can serve both codes, so there is no extra compiler cost.
>
> **Sys (L.State).** That is a fair point about the future. I fold it into Q4: if `State` lands, the same change narrows W0611 to `State == ()`. Then "exactly one `with`" is never reworded twice.
>
> **Q4 — Q4-i holds, with one change**
>
> **Web/Min (do not pre-decide).** Your own concern is my reason. Without a named shape, the next panel can reopen B, which this panel showed fails Connection and E0839. I accept Min's point that [the fallible-enter ticket] owns the details. So the record should fix:
> 1. a state slot separate from `Context`, seen only by `exit`, and **not** `exit(self, ctx, ok)`;
> 2. one trait change with the fallible `enter`;
> 3. in that change, W0611 narrows to `State == ()`.
>
> It should name the `(Self.Context, Self.State)` tuple as the recommended shape and say the order may be revised. This is Q4-i with the tuple order left open. If the ballot lacks that line, I still vote Q4-i.

- **AI/ML:**

> **Q1 — holds at A**
>
> **Sys (stale save/restore handlers).** This is the strongest case for C, so I checked it against the code models will actually write. The common generated form is `with env_override("X", "1") { }`. The factory runs in the item, so the snapshot is taken at entry. Nesting distinct values is correct: each item builds its own snapshot, and teardown is LIFO. The stale restore needs one value that is stored and entered twice, and L.3 flags exactly that shape. The hazard is real, but it is narrow, and a lint covers it.
>
> **Sys (the arena claim).** Agreed that under A, "`with arena` behaves as a BlockHandler" is not literally true for one reused value. The fix is one sentence of spec text, not a trait break. Say that each `with arena` builds a fresh scope value, or drop the claim. A false claim in the spec is wrong training data, so the decision should order that edit whichever way Q1 goes.
>
> **PLT (one meaning per associated type).** I agree C is the clean shape. My objection is cost, not soundness: `type State = ()` plus a tuple return on about 31 impls, for no case on this ticket. That adds a slot-choice decision to every impl a model writes.
>
> **Q2 — holds at L.3**
>
> **PLT (one fact, one code).** The flow fact is shared, but the repair differs. For zero `with`, the fix is "put it in a `with`". For two, it is "build a new value in each". A diagnostic code that maps to one repair is what a generated-code fix loop keys on. DevOps's separate severity point (W0610 has false positives, a second entry almost never does) adds a reason I had not weighed.
>
> **Sys (L.3 needs rewording if State lands).** True, and acceptable. Under Q4-i, that one future trait change narrows the trigger to `State == ()` (L.State) in the same edit, so the corpus never sees two versions of the lint.
>
> **Q4 — holds at Q4-i, with DevOps's amendment**
>
> **Min, Web (do not pre-decide the shape).** Min's own concern answers this: if [the fallible-enter ticket] lands a fallible `enter` alone, the trait breaks twice. Naming the shape is what makes the bundling enforceable, and it rules out B as a "small step" (PLT's concern). Three signatures in the corpus is the outcome I most want to prevent.
>
> I accept DevOps's wording: the record names `(Self.Context, Self.State)` as the shape and says that the tuple order may be revised inside that one change. That leaves the details to the [the fallible-enter ticket] panel but fixes the two facts that matter: a slot separate from `Context`, and one break.

- **Minimalism:**

> **Q1 — I hold A**
>
> **Sys (save/restore handlers).** The concern is that A gives "stale restores on reuse and on nesting". That holds only for a *stored* value. When the factory runs in the `with` item, build and `enter()` are the same point (Order, step 1).
>
> ```blink
> with env_override("X", "1") {
>     with env_override("X", "2") { }
> }
> ```
>
> Each item snapshots the previous value just before its own `enter`. The inner `exit` restores "1" and the outer `exit` restores the original. Nesting is correct under A. Stored reuse is the case W0611 flags.
>
> **Sys (arena).** `with arena { }` is a compiler form, not a user value. The spec claim "behaves as a BlockHandler" can say "as if the compiler builds a fresh value at each entry", which is what `wrap_arena` does. That is one sentence of spec, and it is not a reason to put a second associated type, a tuple return and a `type State = ()` line in every user impl.
>
> **PLT (C now).** I agree C is the right shape if a state slot is ever needed. Still, no case on this ticket needs it under A. The case that does, a lazy Connection, cannot exist before [the fallible-enter ticket]. Paying the break now buys a capability nobody can use yet.
>
> **Q2 — I hold L.3**
>
> **PLT** says it is one flow fact, so it should be one code. One analysis can still emit two codes; the analysis is what costs. AI/ML and Web give the deciding reason: "never reached a `with`" and "reached two" are opposite causes with opposite fixes. One code would give one explain text two meanings.
>
> **Sys's L.State** concern does not apply under A, because no State exists. If State lands later, that one trait change rewords the lint ("exactly one `with` when `State == ()`"). The decision should say so in one line.
>
> **Q4 — I change to Q4-i, with DevOps's amendment**
>
> Two arguments moved me:
> - **AI/ML:** "both in ONE trait change" caps the number of trait signatures in the corpus at two.
> - **PLT and Web:** naming the shape rules out B, the state channel in `Context`. This panel showed with evidence that B breaks E0839 and cannot fix Connection. That finding is a real result. It is not speculative design, and it should not be lost.
>
> My Phase C objection was to fixing details with no user. DevOps's amendment answers it: the tuple order and exact signature may be revised in that one change. The record then binds three facts:
> 1. A state slot separate from `Context`.
> 2. It lands together with a fallible `enter`.
> 3. Not B.
>
> That is the minimum record that prevents two breaks.
>
> **Position:** Q1 A, Q2 L.3, Q4 Q4-i plus the amendment "the tuple order and exact signature may be revised in the one combined change".

Phase D final ballots, verbatim:

- **Systems:** *(dissent on Q1)*

> **Q1: Trait shape now**
> **Vote:** C
>
> **Reasoning:** Codegen costs the same under A and C. C is the shape where the trait describes each entry's lifetime, instead of depending on a convention at the call site that only a lint enforces. The A side showed that a factory call in the item nests correctly. I accept that, and it narrows my concern to a stored value that is reused, but it does not remove the concern.
>
> **Concern:** under A, a stored save/restore value that someone enters twice restores stale state, and a missed W0611 (for example, across a function boundary) makes that a silent bug.
>
> **Q1-arena: if A wins**
> **Vote:** Y
>
> **Reasoning:** DevOps and Min are right, and I change my position. "As if the compiler builds a fresh scope value at each entry" is an accurate description of what `wrap_arena` does. That form *is* a user BlockHandler under A, spelled as a factory call in the item, because the snapshot is taken at Order step 1, right before `enter`. So Y makes the §5.5 claim true with no special-case wording. X would describe a gap that Y shows does not exist.
>
> **Concern:** the sentence must say "at each entry", or readers will think `arena` is one stored value. W0611 would then flag that pattern in user code.
>
> **Q2: Double-entry lint**
> **Vote:** L.3, with the rule worded per PLT: "a value whose state is fixed at build time reaches exactly one `with`"
>
> **Reasoning:** Two codes for opposite causes, and DevOps's severity split, decided this for me. PLT's wording costs nothing under A, because every value has its state fixed at build time. It also lets a future `State` slot narrow the trigger to `State == ()` without rewording the rule.
>
> **Concern:** the explain text must state the function-boundary blind spot, or users will read silence as a guarantee.
>
> **Q4: Future record**
> **Vote:** Q4-i plus DevOps's amendment
>
> **Reasoning:** It binds the three facts that matter:
> - a state slot separate from `Context`, seen only by `exit`;
> - one trait change together with the fallible `enter`;
> - not B.
>
> It also leaves the tuple order to the [the fallible-enter ticket] panel, and narrowing W0611 to `State == ()` in that change keeps the lint and the trait in step. The rule that the shape goes in decisions/ only, never sections/, keeps a trait that does not exist out of the training data.
>
> **Concern:** a record in decisions/ has no gate behind it, so the [the fallible-enter ticket] panel must be pointed at it explicitly, or the bundling clause will be missed.

- **Web/Scripting:**

> **Q1: A**
> **Reasoning:** with the factory in the item, building and `enter()` are the same step. Min's `env_override` example shows that nesting and save/restore are correct with no trait change. A JS or Python developer already writes this eager shape. C puts `type State = ()` and a tuple return into every impl, and no case on this ticket uses them.
> **Concern:** the factory convention is enforced only by W0611 and the Q6 help text. If either ships late, the stored-value mistake has no guard.
>
> **Q1-arena: Y**
> **Reasoning:** "Behaves as if the compiler builds a fresh scope value at each entry" is true, and a user can picture it in one read, because it is the same factory pattern §4.6.3 now teaches. X would put a future trait shape into sections/. This panel just agreed that shape lives only in decisions/. X would also tell users about a slot that does not exist.
> **Concern:** a reader may still try to write their own arena-like handler as one stored value. The arena sentence should point to the factory pattern in §4.6.3.
>
> **Q2: L.3, worded "reaches exactly one `with`"**
> **Reasoning:** the plain wording is what a user can check against their own code. "A value whose state is fixed at build time" makes the reader ask what that means, and under A every value is like that, so the extra phrase adds nothing today. The future narrowing to `State == ()` is already recorded in Q4's amendment and lands in that one change.
> **Concern:** the explain text must state the function-boundary blind spot, or users will read silence as safety.
>
> **Q4: Q4-i plus DevOps's amendment**
> **Reasoning:** it rules out B, which is the `t: Instant` hover result I most want to avoid. It ties the state slot to [the fallible-enter ticket] as one trait change. It leaves the tuple order and the exact signature to that panel. Keeping the shape in decisions/ only means no spec example teaches a trait that does not exist.
> **Concern:** the [the fallible-enter ticket] panel may not read this record. The [the fallible-enter ticket] ticket should get a `br note` that points to it.

- **PLT:** *(dissent on Q1)*

> **Q1 — C**
> **Reasoning.** C gives each associated type one meaning, and it puts per-entry state in the frame, where `bracket` puts it. Under A, re-entry is correct only by a usage convention: build the value in the item. A lint enforces that convention, so it is not a property of the trait. A and C are both sound, but only C makes re-entry correct by construction.
> **Concern.** If A wins and Q4 is weakened later, the slot this panel found sound may come back as B.
>
> **Q1-arena — Y (changed from X)**
> **Reasoning.** Min's and DevOps's reading gives a precise "as if" semantics. `with arena { }` is the item `arena()`, evaluated at step 1, and the snapshot is taken at build time, right before `enter`. That desugaring is a correct user BlockHandler under A, so X's claim that no user impl can express arena is too strong. Y is the more exact text. My Phase D sentence that arena cannot be expressed under A was wrong.
> **Concern.** The sentence must say "a fresh value at each entry", explicitly, so no reader takes `arena` to be one stored value.
>
> **Q2 — L.3, worded per PLT ("a value whose state is fixed at build time reaches exactly one `with`")**
> **Reasoning.** Opposite causes need separate codes, and I accept the severity split. The narrower wording states the real predicate. Under A it is equivalent to "exactly one `with`", and under a future `State` slot it stays true without a rewrite.
> **Concern.** "Fixed at build time" has to be decidable from the type. Under A every scoped value meets it, and the text must say so, or implementations will differ.
>
> **Q4 — Q4-i plus DevOps's amendment**
> **Reasoning.** The record binds three facts this panel established: a slot separate from `Context`, seen only by `exit`, and not B; one combined change with [the fallible-enter ticket]; and W0611 narrowing to `State == ()` in that change. Leaving the tuple order revisable leaves the details to [the fallible-enter ticket]'s panel without reopening the soundness result. Recording it in decisions/ only keeps sections/ free of a trait that does not exist.
> **Concern.** [the fallible-enter ticket]'s panel may treat a recommendation in decisions/ as advisory and land a fallible `enter` alone.

- **DevOps:**

> **Q1 — A**
> **Reasoning.** No reply showed a case on this ticket that A plus W0611 fails. Under A, nested save/restore and arena are correct when the item is evaluated at entry. Only stored-and-re-entered values break, and W0611 reports those with a fix at the exact line. C's cost lands in about 31 signature-help and hover cards for a capability nobody can use before [the fallible-enter ticket].
> **Concern.** A user-written value that is meant as a reusable descriptor has no correct form until the state slot lands, so W0611 and its explain text must state that limit plainly.
>
> **Q1-arena — Y**
> **Reasoning.** "As if the compiler builds a fresh scope value at each entry" is true under A, matches what `wrap_arena` does, and tells the reader the same rule that the factory pattern teaches: one value per entry. X is also true, but in sections/ it points at a trait slot that does not exist, which goes against the "decisions/ only" rule we just agreed for Q4. X's pointer to the state slot belongs in the decision record, and I support putting it there.
> **Concern.** If a user hovers `arena` and sees "BlockHandler", the LSP must not offer "go to impl", because there is none. The hover text should say "compiler-defined".
>
> **Q2 — L.3, rule worded "reaches exactly one `with`"**
> **Reasoning.** The diagnostic and `blink explain` must state a predicate the user can check by reading their code. "Whose state is fixed at build time" is true of every value under A, so today it adds words that select nothing, and readers will ask which values it excludes. The Q4 amendment already narrows W0611 to `State == ()` in the one future change, which meets PLT's and Sys's concern without wording for a type that does not exist.
> **Concern.** If the narrowing clause is left out of the decision record, a future State-carrying descriptor gets a false W0611 on correct reuse.
>
> **Q4 — Q4-i plus DevOps's amendment**
> **Reasoning.** Q4-i binds the facts that prevent a second break and a return to B: a slot separate from `Context`, one combined change with [the fallible-enter ticket], not B, and W0611 narrowed in that change. The amendment leaves the tuple order and exact signature to the [the fallible-enter ticket] panel and keeps the shape out of sections/, so no example teaches a trait that does not exist.
> **Concern.** [the fallible-enter ticket]'s panel may not read this record, so the [the fallible-enter ticket] ticket needs a `br note` that points at it.

- **AI/ML:**

> **Q1 — Trait shape now**
> 1. **Vote:** A
> 2. **Reasoning:** Under A, nesting and repeated entry are correct whenever the item is a factory call, and that is the shape models already produce. Per Min's `env_override` trace, each snapshot is taken at its own entry. C would put `type State = ()` and a tuple return into about 31 impls, for no case a user can write before [the fallible-enter ticket]. It would also add a Context-or-State choice to every impl a model generates. Under Q4-i, the corpus sees at most two trait signatures, not three.
> 3. **Concern:** "correct if built in the item" is a convention that a lint enforces, not a property of the trait (PLT). A model that stores the value relies entirely on W0611 and the Q6 help text.
>
> **Q1-arena — the arena sentence, if A wins**
> 1. **Vote:** Y
> 2. **Reasoning:** "As if the compiler builds a fresh scope value at each entry" is true of what `wrap_arena` does. It keeps one rule for models: every `with` item behaves as a BlockHandler, and a fresh value per entry is the correct pattern. X teaches an exception ("a construct a user cannot express") and puts the not-yet-adopted State slot into sections/ text, which I asked to keep out.
> 3. **Concern:** a model may read Y as permission to store `arena` in a variable and re-enter it. The sentence must make clear that `arena` is a keyword form, not a value.
>
> **Q2 — Double-entry lint**
> 1. **Vote:** L.3, rule worded "reaches exactly one `with`"
> 2. **Reasoning:** Under A, every scoped value has its state fixed at build time, so PLT's qualifier excludes nothing today. It does add a predicate that neither a model nor the `explain` text can check against the code in front of it. The plain wording maps to one cause and one repair. The narrowing to `State == ()` belongs in the future trait change, as the Q4 amendment records.
> 3. **Concern:** if the Q4 amendment is lost, a later State slot would make this rule warn on correct descriptor reuse.
>
> **Q4 — Future record**
> 1. **Vote:** Q4-i plus DevOps's amendment
> 2. **Reasoning:** The record binds the three facts that cap corpus churn: a slot separate from `Context`, one trait change together with a fallible `enter`, and not B. It leaves the tuple order to the [the fallible-enter ticket] panel. Keeping the shape in decisions/ only means no spec example teaches a trait that does not exist.
> 3. **Concern:** the [the fallible-enter ticket] panel must find this record. The [the fallible-enter ticket] ticket should get a note that points to it.

- **Minimalism:**

> **Q1 — A**
> **Reasoning:** In Phase D, all six replies agree that nesting is correct when the factory runs in the `with` item. The stale-restore hazard needs a stored value that is entered twice, which W0611 flags. C would add `type State = ()` and a tuple return to about 31 impls, and no case on this ticket needs them. Q4 keeps C on record, so A does not block it.
> **Concern:** If the [the fallible-enter ticket] panel delays, save/restore handlers that need a reusable descriptor value have no clean form, and authors may reach for per-value shared cells.
>
> **Q1-arena — Y**
> **Reasoning:** `with arena { }` evaluates its item at each entry, so a fresh snapshot per entry is the true description, and nesting stays correct (DevOps). A user can write the same thing today as a factory that snapshots at build time. So X's claim that "a user BlockHandler cannot express it" is stronger than the facts. Y is one sentence that is true now. It does not tie the spec text to a future trait change.
> **Concern:** The sentence must not suggest that a stored `arena` value can be re-entered, so it should say "each `with arena`", not "the arena value".
>
> **Q2 — L.3, rule worded "reaches exactly one `with`"**
> **Reasoning:** Under A, every scoped value has its state fixed at build time. So PLT's qualifier is a no-op today, and it describes a property that the compiler cannot name yet. The Q4 amendment already narrows W0611 to `State == ()` in the one future change, so the plain wording is never reworded twice. Plain text is the smaller rule and gives the clearer `explain`.
> **Concern:** If the narrowing clause is dropped from the Q4 record, the plain wording will warn on correct descriptor reuse once State exists.
>
> **Q4 — Q4-i plus DevOps's amendment**
> **Reasoning:** The record binds only what the panel showed with evidence:
> - a state slot separate from `Context`, seen only by `exit`;
> - not B;
> - one combined trait change with [the fallible-enter ticket], including the W0611 narrowing.
>
> The tuple order stays revisable, and the shape stays in decisions/ only. This prevents two breaks without pre-deciding [the fallible-enter ticket]'s details.
> **Concern:** "Recommended shape" in a decision record may still be read as binding by a later panel. The text should say the [the fallible-enter ticket] panel owns the final signature.

### Final Spec

```blink
trait BlockHandler {
    type Context

    fn enter(self) -> Self.Context
    fn exit(self, ok: Bool)
}

pub type Timer {
    label: Str
    start: Instant
}

pub fn timer(label: Str) -> Timer ! Time.Read {
    Timer { label: label, start: time.read() }
}

impl BlockHandler for Timer {
    type Context = ()

    fn enter(self) -> () {}

    fn exit(self, ok: Bool) ! Time.Read, IO.Log {
        let elapsed = self.start.elapsed()
        io.log("{self.label}: {elapsed} (ok={ok})")
    }
}

with timer("db_query") {
    db.query("SELECT * FROM large_table")?
}
```

- **No trait change (Q1).** A `BlockHandler` gets all its state when it is built. The factory call
  goes in the `with` item, so each `with` gets a new value right before `enter()`, and nested items
  are correct. §4.6.3.
- **Arena (Q1-arena).** `with arena { }` behaves as a `BlockHandler` as if the compiler builds a new
  scope value at each `with arena`. `arena` is a keyword form, not a value to store. §5.5.
- **W0611 `ScopedValueEnteredTwice` (Q2).** A scoped value must reach exactly one `with`. The lint
  fires on two or more, including a `with` in a loop on a value built outside it. It shares the
  W0610 flow analysis and has its own code, so a team can make it an error alone. It does not
  follow a value into a function call, and the spec says so. §5.5, ERROR_CATALOG.md.
- **Second `exit` (Q3).** The stdlib's native handles track a closed state, so a call after close
  returns a defined error, not a use-after-free. User `exit` impls get "should do nothing or fail
  with a defined error" guidance, not a checked rule. `Cleanup` runs its action on each `exit`.
  §4.6.3.
- **Timer (Q5).** `enter` is `{}`. UnusedVariable must not fire on a `self` that a trait method
  requires. That lint fix lands before or with the spec example.
- **Repair text (Q6).** In `BlockHandler.enter()`, a write to a field of `self` gets ParamAssign
  help that names the factory pattern. Everywhere else the help stays `let mut`. §3.6.

**Record for the future trait change (Q4).** This shape is recorded here only. It is not in
`sections/`, and no example uses it.

- If the trait gets a state slot, it is a slot separate from `Context`, seen only by `exit`. It is
  not B: state does not pass through `Context`. This panel found that B breaks the second job of
  E0839 and does not fix `Connection`.
- The recommended shape is `type State` with `fn enter(self) -> (Self.Context, Self.State)` and
  `fn exit(self, state: Self.State, ok: Bool)`. The tuple order and the exact signature may change.
  The panel for the fallible-enter ticket owns the final signature.
- The state slot and a fallible `enter` land as **one** trait change, so the trait breaks once.
- In that change, W0611 narrows to values whose `State` is `()`. A value with a non-unit `State` is
  a descriptor, and entering it more than once is correct.
