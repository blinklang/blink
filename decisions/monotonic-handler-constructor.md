[< All Decisions](../DECISIONS.md)

# How a Time Handler Builds a Monotonic Reading — Design Rationale

### Panel Deliberation

The ticket (verbatim, br id q8d9jz):

> Title: Spec: how a mock Time handler makes a Monotonic value
>
> From the effect-tracked builtins panel: §3.2.3 makes Monotonic opaque, built only by time.monotonic(). §8.10.3 mock_clock (06_tooling.md) has no monotonic op and passes it to the real clock, so a test cannot fake elapsed time. Decide how a handler builds a Monotonic (for example a constructor visible only to handlers, or Monotonic.from_nanos in std.testing).
>
> Blocks: 9nyp84 (type:feature) "Builtin Time effect lacks the time.monotonic() -> Monotonic op the spec lists … How a mock handler builds a Monotonic is open in q8d9jz."

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated. Phase A had independent proposals. Phase B had one round. Phase C was a ballot on Q1 to Q8. Phase D re-voted Q7 only, because Q7 passed 4-2. Quoted text is each panelist's own words, taken from the panel record. "…" marks a cut.

Questions:

- Q1: how a `Time` handler builds the `Monotonic` it returns. **C:** a public pure type-scoped constructor on `Monotonic` in `std.time`, no getter. **W:** the handler op returns a `Duration` and the `time.monotonic()` wrapper builds the value. **A:** `Monotonic.add` on a real base reading, no constructor.
- Q2: the name and argument of the constructor. **O:** `Monotonic.from_offset(d: Duration)`. **N:** `Monotonic.from_nanos(n: Int)`.
- Q3: the constructor panics on a negative argument.
- Q4a: `mock_clock.advance(d)` panics on a negative `d`, with the value in the message.
- Q4b: mock state. **D:** the monotonic reading derives from the wall cell. **S:** a separate monotonic cell.
- Q5: `since`. **E:** the exact signed difference, a total rule. **U:** unspecified when `earlier` is the later reading.
- Q6a: one short "Why the constructor is public" paragraph in §3.2.3.
- Q6b: replace "no epoch" with "the origin of the built-in clock is unspecified and can change from one run to the next. Code must not depend on its value."
- Q7: the W0545 help when a `Time` handler omits `monotonic`. **H1:** a `Time`-specific help. **H2:** one generic note for every `@handle_all` effect. **H2+T:** H2 plus a line that names the constructor.
- Q8: a sentence in §8.10.3: every `std.testing` mock of a `@handle_all` effect implements every primitive op.

#### Phase A — Independent proposals

New fact from the first proposal: the old spec text did not only lose determinism. It panicked in a test. Four seats proposed a public constructor (C). One proposed W. Three seats proposed A, as first or second choice.

- **Systems** proposed W (sys-1):

  > **New fact first: the current spec does not merely lose determinism, it panics.** §8.10.3 `mock_clock` has no `monotonic` op, so under `@handle_all` the omitted op forwards as `default.monotonic()` (sections/04_effects.md:2148). A test block is pure by default and holds no `Time` handler (sections/02_syntax.md:1859). So inside `with mc.as_handler() { ... }` in a test, `time.monotonic()` forwards to *no* handler, and "an operation that finds no handler at run time panics" (sections/04_effects.md:2922). It typechecks (the `with` discharges `Time`) and then dies at run time.

  > - Effect operation (what a `handler Time { ... }` implements, and what `default.monotonic()` calls): `fn monotonic() -> Duration`. The result is the time since an origin that the handler picks. The origin has no meaning outside that handler.
  > - Wrapper (what user code calls): `time.monotonic() -> Monotonic`. It calls the op once and wraps the `Duration` in a `Monotonic`. Only `std.time` builds the value, so §3.2.3 "Code builds a `Monotonic` only through `time.monotonic()`" stays true word for word. No new public constructor, no friend visibility, no epoch exposed to user code.

- **Web/Scripting** proposed C with `from_nanos`:

  > So the binding requirement is: **`.advance(d)` moves both readings by `d`**. How the handler makes the value is plumbing; pick the least surprising plumbing.

  > Fact that frames the choice: §2.12.2 has no friend or package visibility, and `std.testing` is a different module from `std.time`. A "constructor only `std.testing` can see" does not exist unless we add a visibility tier. I do not want a new visibility tier for one function.

- **PLT** proposed C with `from_offset(d: Duration)`, and Option A as second choice:

  > The model that makes this exact: **`Monotonic` is an affine space (a torsor) over `Duration`.** A reading is a point; only the difference of two points has meaning. The real clock picks an origin that the program cannot see. As long as the API has no observer of the absolute position (no `to_nanos`, no `Display`, no `Ord` against a constant), any choice of origin is unobservable, and a mock may pick its own.

  > The effect `Time.Read` tracks *observing* the clock. A value built from a `Duration` observes nothing, so a pure constructor does not weaken effect tracking. `Instant.from_epoch_secs` is pure for the same reason.

- **DevOps/Tooling** proposed A (devops-1), and C as second choice:

  > Add one method to `Monotonic` in §3.2.3. Add no constructor. A handler makes a fake reading by moving a real reading forward. `mock_clock` reads the outer clock one time, through `default.monotonic()`, and from then on answers `base.add(offset)`, where `offset` is the total of every `.advance(d)`.

- **AI/ML** proposed C with `from_nanos(n: Int)`:

  > So the rule must let *any* handler build a `Monotonic` from its own state. A rule that only `std.testing` can use (friend visibility, a testing-only constructor) leaves user handlers with one path: the W0545 fix, which is wrong. An LLM that writes a handler will take the machine fix every time. The spec must make the correct handler the short one.

- **Minimalism** proposed C with `from_nanos`:

  > The minimal answer: the door Blink already has. §2.12.2-3 gives an opaque type exactly one public way in: a `pub` type-scoped function in the declaring module. `Instant` uses it (`Instant.from_epoch_secs`). `Monotonic` needs one such function and nothing else. No new visibility tier, no handler-only scope, no compiler magic, no new diagnostic.

No seat proposed a constructor visible only inside a handler body, or in `std.testing` only. PLT gave the reason: "There is no typing judgement for 'inside a `handler Time { ... }` body'" and "`std.testing` cannot see the body of `std.time.Monotonic` (§2.12.2), so this needs friend visibility too."

#### Phase B — Round 1

Option A fell. devops, plt and web withdrew it on the same fact, because a test has no outer `Time` handler:

- **DevOps/Tooling:**

  > sys is right, and I was wrong on a fact. My Phase A said "A test always runs under the real `Time`, so this is safe in a test." The spec says the opposite: "Test blocks have **no implicit effects**" (sections/02_syntax.md:1859), and "an operation that finds no handler at run time panics" (sections/04_effects.md:2922). … Option A is dead for `mock_clock`. I still think `Monotonic.add` has a use for deadlines, but that is its own ticket, not this one.

- **PLT:**

  > Read lazily through `default.monotonic()` (devops-1, web-2), the program typechecks and then panics on the first `time.monotonic()` in a test. devops-1 said "A test always runs under the real `Time`"; the spec says the opposite. A design whose main use case panics at run time is out. I withdraw plt-2.

- **Web/Scripting:**

  > So the option meant to fix the mock breaks the mock in a test, the one place it runs.

PLT also corrected its own Phase A claim, and added the Q3 panic:

> I wrote: "No function reads the offset back, so … the origin of the built-in clock is never visible." That is false, and aiml saw why: `time.monotonic().since(Monotonic.from_offset(Duration.nanos(0)))` gives the raw clock count. So under Option C the origin of the real clock *is* observable.

> So the honest spec text for either option is not "the origin is hidden". It is: **the origin of the built-in clock is unspecified and can change from one run to the next. Code must not depend on its value.**

> **c. Negative offset.** New for C: `Monotonic.from_offset(d)` / `from_nanos(n)` panics on a negative argument, with the message shape of sys-1's wrapper check. A reading before the origin has no meaning on a monotonic clock, and the check is one compare (sys's cost argument).

Systems kept W as first choice by a small margin. Its argument, and the reply that moved it:

- **Systems:**

  > **W** keeps "Code builds a `Monotonic` only through `time.monotonic()`" true. It also gives the wrapper one place to check every reading a handler gives (the sign check, as the `Rand` wrapper does).

- **PLT** (reply, §2 and §3):

  > Under sys-1 any handler body can call `default.monotonic()`, which has type `Duration`: the raw count, in the hands of user code. A user wraps that in a three-line handler and gets the same number. So W and C give user code the same power over the origin. W only makes the path longer.

  > It does, in the letter. But in substance any pure code can write `with handler Time { fn monotonic() -> Duration { Duration.nanos(0) } ... } { time.monotonic() }` and forge a reading.

- **Minimalism** (same point):

  > Under W, `default.monotonic()` returns a `Duration`. Any handler, in any user module, gets the raw count of the real clock as a plain `Duration`, with no `since` in between. Under C, to see the origin you must write `time.monotonic().since(Monotonic.from_offset(Duration.nanos(0)))`, which takes some intent.

#### Phase C — Ballot

Results: Q1 C 6-0, Q2 O 6-0, Q3 Yes 5-1, Q4a Yes 6-0, Q4b D 5-1, Q5 E 6-0, Q6a Yes 5-1, Q6b Yes 6-0, Q7 H2 4-2, Q8 Yes 6-0.

**Q1: C (6-0).** sys and devops moved from W.

- **Systems:** C. "I proposed W, and I now vote against it. plt B1 §2 and min B1 are right: under W, `default.monotonic()` hands any handler body the raw count of the real clock as a plain `Duration`. … So W hides nothing that C exposes; it only keeps one sentence true in letter, and it costs a second signature for one name." *Concern:* "A public `from_offset` will show up in production code as a fake "start time", and `since` against a real reading will then return a number with no meaning and give no error."
- **DevOps/Tooling:** C. "min and plt showed me that this error exists only because W makes two signatures for one name. Under C, the signature a person copies from §4.4 (`time.monotonic() -> Monotonic`) is right the first time." *Concern:* "A public constructor has no diagnostic for its misuse in production code (a forged reading, or `since` across two clocks), so the only guard is the spec sentence and review."
- **Web/Scripting:** C. "A person who writes a `handler Time` copies what they see at the call site: `time.monotonic() -> Monotonic` (§4.4:292). Under C that signature is right on the first try; under W it is a compile error on every first handler."
- **PLT:** C. "Both C and W are sound and keep `Time.Read` the only effect that observes the clock. But the two give user code the same power: under W any handler can forge a reading (return any `Duration`) and see the raw origin."
- **AI/ML:** C. "Under C the handler op has the same signature that §4.4 lists for the call, `monotonic() -> Monotonic`, so the handler a model writes on its first try compiles."
- **Minimalism:** C. "C adds one row to one table and uses the only door §2.12.3 gives an opaque type, the same door `Instant.from_epoch_secs` uses." *Concern:* "Users will now ask for `to_offset`, `add` or `Ord` "because the constructor exists". The spec must keep `since` as the only observer until a ticket shows a need."

**Q2: O, `Monotonic.from_offset(d: Duration)` (6-0).**

- **Systems:** O. "The unit is in the type, as it is for every other `std.time` value, so `from_nanos(ms)` cannot happen. The cost is the same as an `Int`." *Concern:* "People who expect the `Duration.nanos(Int)` / `Instant.from_epoch_secs(Int)` shape will reach for a `from_nanos` that does not exist, and they get only an unresolved-name error."
- **Web/Scripting:** O. "A raw `Int` invites `from_nanos(ms)`, a silent bug by a factor of 10^6."
- **PLT:** O. "The argument is a vector in the torsor (`Duration`), so the unit is in its type and `from_nanos(ms)` cannot typecheck by accident."
- **AI/ML:** O. "A `Duration` argument puts the unit at the call site, which is the reason `Duration` has named constructors."
- **DevOps/Tooling:** O. "With a `Duration` argument, the wrong-unit bug (`from_nanos(ms)`) becomes a type mismatch."
- **Minimalism:** O. "The mock body becomes `Monotonic.from_offset(now.since(start))`, with no `to_nanos` round trip." *Concern:* "A model may still guess `from_nanos` by analogy with `Duration.nanos`. The E-code help for an unknown function on `Monotonic` should point at `from_offset`."

**Q3: Yes (5-1).**

- **Systems:** Yes. "A reading before the origin has no meaning on a monotonic clock, and the check is one compare-and-branch that the predictor learns at once." *Concern:* "A user handler that computes an offset by subtraction, and goes negative through its own off-by-one, panics in a hot timing loop where a clamp would have been less surprising."
- **Web/Scripting:** Yes. "Failing at the call that is wrong beats a negative `Duration` three calls later in an assertion the user did not write."
- **PLT:** Yes. "It makes the domain of `Monotonic` exact: a reading is a non-negative offset from its clock's origin, as the real `CLOCK_MONOTONIC` gives."
- **AI/ML:** Yes. "It turns a silent bad reading into a loud failure at the line that built it, which is the line a model must fix."
- **DevOps/Tooling:** Yes. "It fails at the call that is wrong, not later in a `since` far away, and the check is one compare."
- **Minimalism** *(dissent)*: No. "The origin is arbitrary, so a reading "before the origin" is still a valid point: only differences mean anything (plt's own torsor model). Monotonicity is a property of a sequence of readings from a handler, not of one value's sign, so the check guards the wrong thing." *Concern:* "If it wins, the panic text must say it is the argument that is negative, not the clock that went back. Otherwise a handler author will look for the wrong bug."

**Q4a: Yes (6-0).**

- **Systems:** "Moving the clock back breaks the one guarantee that `since` users rely on, and in a test helper the check costs nothing."
- **Web/Scripting:** "A clear panic with the value (`mock_clock.advance: duration must not be negative, got -1s`) is the "just works" answer."
- **PLT:** "Without it the stdlib mock breaks the monotone obligation that every `Time` handler has, by its own hand."
- **AI/ML:** "A message with the value tells a model what to change."
- **DevOps/Tooling:** "The panic fires at the test line that holds the bug, and the message shows the value."
- **Minimalism:** "Without it, the stdlib's own mock makes the monotonic clock go back, and `since` gives a result the real clock never gives. Fail at the call that is wrong." *Concern:* "A test that relied on a negative advance to rewind the wall clock now panics, and nothing in the mock lets it rewind only the wall clock."

**Q4b: D (5-1).**

- **Systems** *(dissent)*: S. "The two clocks are two models in §3.2.3, and two cells mirror that. If the mock ever gets a wall-clock jump (an NTP step is a real event worth testing), D breaks silently, because `now.since(start)` goes back." *Concern:* "If D wins, the first person to add `set_wall` to `MockClock` makes `time.monotonic()` go backward, and nothing in the code warns them."
- **Web/Scripting:** D. "One cell means the wall clock and the monotonic clock in a mock cannot drift, and the example users copy into their own handlers has one less `let mut`."
- **PLT:** D. "With Q4a, one cell gives both clocks and makes drift between `read` and `monotonic` impossible, which is the invariant `@handle_all` asks for."
- **AI/ML:** D. "With Q4a in place the derived reading is never negative and never goes back."
- **DevOps/Tooling:** D. "One cell means the two clocks cannot drift, and the stdlib example that users copy is shorter."
- **Minimalism:** D. "sys's wall-clock-jump case is YAGNI: the ticket that adds a jump adds the second cell." *Concern:* "A later mock op that moves `now` alone (a jump) would move the monotonic reading silently, unless that ticket's author knows about this coupling."

**Q5: E (6-0).**

- **Systems:** "The exact signed difference is one subtraction, which panics only on `Int` overflow and adds no branch. I prefer naming the cross-clock result as "a `Duration` with no meaning, and no error" over "unspecified"." *Concern:* "'Never panics except on overflow' freezes out a later debug-mode check (such as tagging readings by handler in `--debug`) unless that check is written as a lint rather than a panic."
- **PLT:** "A total function with a stated value is the stronger specification … "Unspecified" leaves room for an implementation to clamp or panic, and that changes program meaning between implementations."
- **Web/Scripting:** "It matches `Instant.since` and `Duration`, which already allow negatives."
- **AI/ML:** "A model writes better code from a total, stated rule … than from "unspecified"."
- **DevOps/Tooling:** "I proposed U, but E is the better contract for tools and tests."
- **Minimalism:** "One total rule with no branch: the exact signed difference." *Concern:* "Someone may pin a cross-clock result in a golden test because the law names it. The "no meaning" sentence must stay next to the law."

**Q6a: Yes (5-1).**

- **Systems** *(dissent)*: No. "The rationale belongs in decisions/ with this vote. §3.2.3 should state the rule and the laws, and the table row speaks for itself." *Concern:* "If it is left out, a reviewer's first question ("why can production code build one?") goes unanswered in the spec, and the answer is only one link away."
- **Minimalism:** Yes. "It answers the first question a reader asks, "why can production code build one?", in one paragraph where they will look. Each other choice in §3.2.3 has one." *Concern:* "It grows into a theory section. Keep it to one paragraph and put the torsor text in decisions/."
- **PLT:** Yes. "A handler can live in any module, so a handler-only door would be public in all but name."
- **Web/Scripting, AI/ML, DevOps/Tooling:** Yes. "'Why can production code build one?' is the first question a reviewer or an LLM asks."

**Q6b: Yes (6-0).**

- **PLT:** "Under both C and W the origin is observable, so the spec must state the obligation on the program in place of the false claim that the origin is hidden."
- **Systems:** "This is true of `CLOCK_MONOTONIC` (on Linux it counts from boot, and other OSes use other points)." *Concern:* "Nothing enforces it: `time.monotonic().since(Monotonic.from_offset(Duration.nanos(0)))` still returns uptime to anyone who writes it."
- **Minimalism:** "It overlaps "no epoch". The writer should merge the two so the paragraph does not say the same thing twice."
- **Web/Scripting:** "Telling users "do not depend on it" is how Python and JS document `time.monotonic()` and `performance.now()`."

**Q7: H2 (4-2).** sys, plt, devops, min voted H2. web and aiml voted H1. Phase D follows.

- **Web/Scripting:** H1. "H2's generic 'answer from the same state' tells them what to do but not how to build a `Monotonic`, so they still go searching."
- **AI/ML:** H1. "The machine fix `default.monotonic()` panics in any test (no outer `Time`) and mixes two clocks elsewhere, and a model takes the machine fix every time."
- **PLT:** H2. "I prefer one rule over a special case." *Concern:* "The generic note cannot name `Monotonic.from_offset`, so a handler author still has to find the constructor from §3.2.3."

**Q8: Yes (6-0).**

- **Systems:** "It records the fact that put this ticket on the agenda, where the next mock author will read it: a test has no outer handler, so a forwarded op panics at run time, not at compile time."
- **Minimalism:** "It is a rule for stdlib authors and adds nothing to the language."
- **Web/Scripting:** "One sentence prevents the same run-time panic in the next stdlib mock."
- **PLT, DevOps/Tooling, AI/ML:** Yes. Same reason: the fact that killed Option A, written where the next mock author reads.

#### Phase D — Q7 only

Q7 passed 4-2, closer than 5-1, so it got one focused round. The options were H1, H2 and H2+T. Every seat noticed the same gap in H2 (its supporters named it in their own concerns). The objection to a `Time` line was a table that someone must keep in sync. Four seats made H2+T a rule from the type of the omitted op, not a table. All six voted H2+T.

- **Systems** (from H2): H2+T. "When the omitted op returns an opaque type that has `pub` type-scoped constructors, the note names them … The compiler already has this lookup, because E1003's help names "the public way in, such as a constant or a type-scoped function"." *Concern:* "if the `T` line is written as a literal string, not derived from the return type's constructors, it goes stale the first time someone renames or adds a constructor."
- **PLT** (from H2): H2+T. "I voted H2 because I want one rule, not a table per effect. … The compiler can derive the line from the type of the omitted op, with no table." *Concern:* "if the `Time` line is written by hand and not derived from the op's return type, it is the per-effect table min warned of, and it will go stale when the next `@handle_all` effect lands."
- **DevOps/Tooling** (from H2): H2+T. "The `Time` line needs no table if the compiler works it out the same way it works out the rest of the H2 note: W0545 knows the omitted op and its return type … When that return type is an opaque type (§2.12.2) with `pub` type-scoped functions that return it, the note adds one line that names them. Otherwise the note adds nothing." devops checked the rule against the three marked effects: `Time` gets the line, and `Rand` and `IO.Read` do not, because their return types are not opaque. *Concern:* "if the `Time` line becomes hand-written text in the checker rather than derived from the opaque return type, it is the per-effect table we all wanted to avoid, and it will rot when the constructor is renamed."
- **Minimalism** (from H2): H2+T. "My own vote for H2 was against a per-effect *table*, not against naming the constructor." "Of the three marked effects, only `Time` has an op that returns an opaque type, and the type is what the help must name." *Concern:* "if the T line is a hard-coded `Time` string, not taken from the omitted op's return type, it becomes the per-effect table we meant to avoid."
- **Web/Scripting** (from H1): H2+T. "After sys's fact, the forward fix `default.monotonic()` panics in every test, and a test is where most custom `Time` handlers live. For `Rand`, forwarding gives a different stream. For `Time`, it gives a run-time panic. That is the reason to spend one line on it." *Concern:* "the `Time` line and the E1003 help on `Monotonic` will drift apart unless the checker builds both from one string."
- **AI/ML** (from H1): H2+T. "A model that gets W0545 reads the diagnostic text and applies the machine fix. It does not hover and it does not run `blink doc` unless the text tells it to. … One line that names `Monotonic.from_offset` turns that into a correct handler on the first try." *Concern:* "the `Time` line must change if a later panel renames `from_offset` or adds a second way to build a `Monotonic`, and nothing checks that."

Result: 6-0 H2+T. Round 2 settles on a rule from the return type, not a `Time`-only line.

### Final Spec

```blink
// std.time: Monotonic is an opaque type (§2.12.2); the one way in is a pub type-scoped function.
pub opaque type Monotonic

// A reading `d` after the origin of its clock. Pure. Panics when `d` is negative:
// "Monotonic.from_offset: negative offset -5ns; a monotonic reading is never before its origin"
fn Monotonic.from_offset(d: Duration) -> Monotonic

// The only observer. The exact signed difference; negative when `earlier` is the later
// reading; panics only on Int overflow. Readings from two clocks give a Duration with
// no meaning, and no error.
fn Monotonic.since(self, earlier: Monotonic) -> Duration

// A Time handler builds its reading with from_offset.
fn stepping(step: Duration) -> Handler[Time] {
    let mut elapsed = Duration.nanos(0)
    handler Time {
        fn read() -> Instant { Instant.from_epoch_secs(0) }
        fn monotonic() -> Monotonic {
            elapsed = elapsed.add(step)
            Monotonic.from_offset(elapsed)
        }
        fn sleep(d: Duration) { }
    }
}

// std.testing mock_clock: the monotonic reading derives from the wall cell.
// handler Time {
//     fn read() -> Instant { now }
//     fn monotonic() -> Monotonic { Monotonic.from_offset(now.since(start)) }
//     fn sleep(d: Duration) { slept.push(d) }
// }
// .advance(d) panics when d is negative:
// "mock_clock.advance: duration must not be negative, got -1s"
```

Locked points:

- `Monotonic` has one constructor, `from_offset`, and one observer, `since`. There is no `to_offset`, `add`, comparison or `Display`. Where code has "no reading yet", it uses `Monotonic?`, not a zero-offset sentinel.
- The handler op stays `fn monotonic() -> Monotonic`. The signature at the call site is the signature in the handler.
- `mock_clock` answers `read`, `monotonic` and `sleep` itself. A later op that moves the mock wall clock backward or jumps it must keep a separate monotonic reading.
- Every `std.testing` mock of a `@handle_all` effect implements every primitive op, because a test has no outer handler to forward to.
- W0545 keeps its machine fix `default.op(args)`. Its help gains the generic note for every `@handle_all` effect. When the omitted op returns an opaque type, the help also names that type's `pub` type-scoped functions that build it.

### Implementation notes (not spec)

- The builtin `Time` op table gains `monotonic`. Only `read` and `sleep` exist today. The `Monotonic` opaque type and its `since` and `from_offset` do not exist in `lib/std` yet.
- The W0545 constructor line derives from the omitted op's return type: the opaque type's `pub` type-scoped functions that return it. This is the same lookup that E1003 (`PrivateItemAccess`) help uses for "the public way in", so the two help texts come from one source and do not drift (web, Phase D).
- E1003 help and the LSP point a `from_nanos` guess on `Monotonic` to `from_offset` (sys, devops and min concerns on Q2).
- Panic messages carry the value: `Monotonic.from_offset: negative offset -5ns; a monotonic reading is never before its origin`, and `mock_clock.advance: duration must not be negative, got -1s`. The messages in the spec are examples.
- Tests: one per panic message; the derived help for a `Time` handler that omits `monotonic` (and no extra line for `Rand` and `IO.Read`); a `mock_clock` elapsed-time test through `time.monotonic().since(start)` after `.advance(d)`; `since` with a later `earlier` (negative result).
- The feature ticket that adds the builtin `Time.monotonic` op blocks on this decision.

### Open cases and follow-ups

- Mock `time.sleep(d)` does not move the clock. A loop that waits on `time.monotonic().since(start)` hangs under `mock_clock`. This changes a decided mock behaviour, so it is a friction ticket, not part of this vote (web wanted a spec ticket; aiml, devops and min wanted friction).
- `Monotonic.add(d)` for deadlines is a future spec question if a need shows up. It leads to `Ord` on `Monotonic`, which the effect-tracked builtins panel held back.
- A wall-clock jump op on `mock_clock` (sys, Q4b dissent) needs a second monotonic cell when someone adds it.
- Debug-mode tagging of readings by handler (sys, Q5 concern) would have to be a lint, not a panic.
