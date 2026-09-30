[< All Decisions](../DECISIONS.md)

# Mock Controller Expressibility (`mock_clock`, `mock_env`, `mock_rand`) — Design Rationale

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in independent-proposal → debate → vote rounds.

The gap: §8.10.3 (`mock_clock`, `mock_env`) and §8.10.4 (`MockRand`) showed syntax the language rejects: `mut` struct fields, an inherent `impl`, and a method named `handler`, which is a keyword. The text also said the controller "closes over `self`", which a by-value `self` (§3.6) cannot do. Inherent methods were rejected 4-1 and by-value `self` passed 5-0 in earlier rulings. The controller-struct shape itself ([mocking-helpers-beyond-io.md](mocking-helpers-beyond-io.md), [test-seed-determinism.md](test-seed-determinism.md)) was not re-opened.

Panelist text below is quoted verbatim, except that local tracker IDs are replaced by a bracketed name: [this ticket] is this mock-controller ruling, [parameter-mutation ticket] is the open question of whether a write to a parameter field is an error, and [BlockHandler state ticket] is the open question of how state passes from `enter` to `exit`.

#### Phase A — Independent proposals

All six proposed the same primary design: state in the factory's `let mut` locals, captured by both the handler and closure fields; methods through a single-type trait; `.handler()` renamed `.as_handler()`. Representative code, Systems S1, as sent (two errors in it were later caught by a gen1 probe: `slept` must be `let mut`, and `Instant` has no `+`, so the spec uses `now.add(d)`):

```blink
pub type MockClock {
    time_handler: Handler[Time]
    advance_fn: fn(Duration) -> Void
    elapsed_fn: fn() -> List[Duration]
}

pub trait MockClockOps {
    fn as_handler(self) -> Handler[Time]
    fn advance(self, d: Duration)
    fn elapsed(self) -> List[Duration]
}

impl MockClockOps for MockClock {
    fn as_handler(self) -> Handler[Time] { self.time_handler }
    fn advance(self, d: Duration) { (self.advance_fn)(d) }
    fn elapsed(self) -> List[Duration] { (self.elapsed_fn)() }
}

pub fn mock_clock(start: Instant) -> MockClock {
    let mut now = start
    let slept: List[Duration] = []
    MockClock {
        time_handler: handler Time {
            fn read() -> Instant { now }
            fn sleep(d: Duration) { slept.push(d) }
        },
        advance_fn: fn(d: Duration) { now = now + d },
        elapsed_fn: fn() -> List[Duration] { slept },
    }
}
```

- **Systems:** (excerpts; each block is a separate excerpt)
  > ## Ruling on self-field mutation (sub-question b, semantics)
  >
  > It does not persist, and `self.f = x` should be a compile error. §2.22 says a place is rooted in a `let mut` binding, and `self` is a parameter. If we let it compile and silently drop the write, a copy gets mutated and the change is lost. If we make it persist, pass-by-value quietly becomes pass-by-reference: the ABI changes depending on what the body does, and codegen stops being predictable. Both are worse than a clear error.
  >
  > State persists across calls only through a heap cell. Blink already has exactly one: a `let mut` binding captured by a closure or handler, which §2.8 boxes into a shared cell. A `List` also works. In C this is one boxed allocation per field and one pointer dereference per access. That cost is visible and fixed, and nothing hides a by-reference path. The same fix applies to the §4.6.3 Timer example ([BlockHandler state ticket]) and the parameter half of [parameter-mutation ticket].

  > ## Proposal S2 (alternative): an explicit `Cell[T]`
  >
  > `std.testing` gets a private `Cell[T]`: a boxed value with `get` and `set`. The controller becomes `MockClock { now: Cell[Instant], slept: List[Duration] }`, and `impl MockClockOps` does `self.now.set(...)`. Copying `self` copies the pointer, so a mutation reaches the shared heap cell.
  >
  > This is more explicit. There is one named allocation, and the struct layout reads like the data. The price is a new primitive, kept private for now. If it ever becomes public it grows into a general interior-mutability type, and that is a spec-level feature. I prefer S1 because it uses only mechanisms we already ship.

  > ## How it carries over
  >
  > - `MockEnv` gets `MockEnvOps` with `as_handler`, `set` and `writes`. Its `vars` is a captured `let mut Map`, and `writes` is a `List`.
  > - `MockRand` gets `MockRandOps` with `as_handler`, `draws` and `reseed`. `state: U64` and `draw_count: Int` become captured `let mut` cells.
  > - The §8.10.3 forward rule should say it outright: "controller state lives in captured cells; controller methods attach through a single-type `*Ops` trait."
  >
  > **Cross-language:** Go closures over captured variables produce this same heap-escape codegen. Zig would pass a `*State` explicitly. S1 is the Go shape, S2 the Rust `Rc<Cell>` shape.

- **Web/Scripting:** (excerpts; each block is a separate excerpt)
  > ## W1 (recommended): the factory owns the state, the struct holds closures, a trait attaches the methods
  >
  > The state lives in `let mut` locals inside the factory. The handler and closures capture those locals as shared cells (§2.8). The struct only holds the handler and closures, so passing `self` by value costs nothing: every copy points at the same cells. This uses only rules that already exist.

  > ## Ruling on self-field mutation
  >
  > Rule explicitly: **`self.f = x` never persists to the caller.** `self` is passed by value, and §2.22 says a place is rooted in a `let mut` binding. Persistent controller state lives in shared cells: captured `let mut` locals, or `List`/`Map` contents.
  >
  > Add a one-paragraph callout to §8.10.3. Python and JS devs will write `self.now = ...` and expect it to stick, so the spec must say why it does not and what to do instead. Better still, make `self.f = ...` a compile error (a `self` parameter is not a place), so nothing fails silently. That overlaps [parameter-mutation ticket], so hand that part to it.
  >
  > The §4.6.3 Timer example has the same bug. Point [BlockHandler state ticket] at this ruling.

  > ## One import gotcha to fix
  >
  > §3.6:2714 makes an impl reachable only when the trait or the type is in scope. The example imports only `{mock_clock}`. Then either `mc.advance()` fails to resolve, or the spec must state that a type reached through an imported fn's return value counts as in scope. I vote to state it: `import std.testing.{mock_clock, MockClock}` is exactly the ceremony that becomes a Stack Overflow question.
  >
  > **Vote: W1**, with the `as_handler` rename, the explicit ruling that `self` mutation does not persist, and the same fix applied to MockEnv and MockRand.

- **PLT:** (excerpts; each block is a separate excerpt)
  > ## Diagnosis (the typing question underneath)
  >
  > The stale example assumes `self.f = e` persists across calls. That judgment has no derivation in Blink today.
  >
  > - §2.22 says a place is a `let mut` binding, or a field path rooted in one. `self` is a parameter, so `self.now = ...` is not a place.
  > - Even if [parameter-mutation ticket] lets parameters mutate, `self` is by value (§3.6). A write to a by-value copy is invisible to the caller, unless structs have reference identity. §3.6 says "no by-reference vs by-move distinction" but never states aliasing semantics for struct values. That is its own soundness hole, and **our controller design must not depend on it**.
  >
  > The spec has exactly one well-defined shared mutable channel: **the closure capture cell** (§2.8, "shared cell", visible both ways). A sound controller has to route its state through that channel, and only that one.
  >
  > ## Proposal P1 (primary): closure-cell controller with a single-type ops trait
  >
  > State lives in `let mut` locals of the factory. The handler and the controller's closure fields capture the same cells. The methods attach through `impl MockClockOps for MockClock`, the same single-type trait pattern as `PidOps` and `TcpSocketOps`, so the 4-1 inherent-method ruling stands. The ruling on `self` fields is simple: no field of the controller is ever assigned.

  > ## Proposal P2 (the rulings, needed whichever shape wins)
  >
  > 1. **`self.f = e` is rejected.** Close [parameter-mutation ticket] in the direction that parameters, `self` included, are not places, so §2.22 already covers them. The alternative, silent non-persistence, is the worst option: it type-checks and then drops the write. The §4.6.3 Timer example (`self.start = time.now()`) falls under the same ruling, and its fix belongs to [BlockHandler state ticket] (for example, a `BlockHandler.enter` that returns the state for `exit`).
  > 2. **§3.6 must state struct aliasing.** Whichever way it goes, P1 stays correct, but the spec cannot leave the question implicit.

  > **Vote intent:** P1 plus P2.1 plus P2.2.

- **DevOps:** (excerpts; each block is a separate excerpt)
  > ### Proposal A (recommended): state in captured `let mut`, methods on a single-type trait
  >
  > The factory owns the state as local `let mut` bindings. The handler and the controller's closures both capture them. Under §2.8 these captures share one boxed cell, so state persists without changing the language. The methods attach through a trait with one impl, `impl MockClockOps for MockClock`. That is the same pattern as `TcpSocketOps` and `PidOps`.

  > ### Ruling on assigning to `self` fields (ask b)
  >
  > Assigning to `self.f` must be a compile error, not a write that silently vanishes. `self` is passed by value (5-0), and §2.22 defines a place as rooted in a `let mut`. `self` is neither. Letting it compile and then drop the write is the worst possible tool outcome: the test passes against stale state and no diagnostic fires. Proposed error:
  >
  > ```
  > error[E0xxx]: cannot assign to 'self.now': 'self' is a by-value parameter, not a 'let mut' binding
  >   --> clock.bl:14:9
  >    |
  > 14 |         self.now = self.now + d
  >    |         ^^^^^^^^ this write would be lost when the method returns
  >    = help: keep mutable state in a 'let mut' captured by a closure, or in a List/Map field
  > ```
  >
  > Two open tickets depend on this ruling:
  > - [parameter-mutation ticket] (can parameters mutate?) resolves toward "no" for fields reached through a parameter.
  > - [BlockHandler state ticket], and the spec's own §4.6.3 Timer example (`self.start = time.now()` in `enter`), would turn into this error. That is correct, but §4.6.3 must be rewritten in the same change, or the spec contradicts itself.

  > ### Follow-up to file (outside this ruling)
  >
  > `capture_log` and its two siblings store their target in a module-level global (lib/std/testing.bl:3-38). That is the nesting bug §8.10.3 itself names as the reason for controllers: an inner `capture_log(b)` makes the outer handler push into `b`. Proposal A's per-call `let mut` capture fixes it the same way. It should be its own bug ticket.
  >
  > ### Vote
  >
  > Proposal A (factory-local `let mut` shared by the handler and closures, plus a single-type trait such as `impl MockClockOps for MockClock`), plus a hard compile error for assigning to `self` fields, plus renaming `.handler()` to `.as_handler()` with an E1103 fix-it: "help: 'handler' is a keyword; the mock method is 'as_handler()'". The same shape applies to MockEnv and MockRand (MockRand uses `draws_fn` and `reseed_fn` closures because Int is not a cell).
  >
  > Open risk to check: under enforced selective imports, `import std.testing.{mock_clock}` may not bring `MockClockOps` into scope, so `mc.advance()` would fail with "no method". The spec should either say that a type's trait methods resolve wherever the type is visible, or the error must print "help: import std.testing.{MockClockOps}".

- **AI/ML:** (excerpts; each block is a separate excerpt)
  > ## Proposal A (preferred): the state lives in captured cells, and a sibling `*Ops` trait supplies the methods
  >
  > **The ruling on self-field mutation:** it does not persist, and the spec says so outright. `self` is passed by value (5-0), and a place is a `let mut` root (6-0). If `self.f = x` persisted from a method, the result would depend on how `f` happens to be stored, and an LLM cannot predict that. The only mechanism with shared visibility is the one §2.8 already specifies: `let mut` captures become shared boxed cells. The factory owns the state and the struct carries closures over it. Because the struct is a bundle of handles, copying it by value is harmless.

  > ## Proposal B (fallback): expose the closure fields and drop the trait
  >
  > ```blink
  > (mc.advance)(Duration.seconds(29))
  > ```
  >
  > I reject this. LLMs will write `mc.advance(...)` without the parentheses nine times in ten, which is a guaranteed first-pass compile error on the most common line in the feature. The trait layer exists to remove exactly that decision point.

  > ## One open risk the panel must close
  >
  > §3 (`sections/03_types.md:2714`) says an impl is reachable only if "either the trait or the type is in scope." With `import std.testing.{mock_clock}`, neither `MockClock` nor `MockClockOps` is imported, so `mc.advance(...)` may fail to resolve. That would be a silent trap, like Rust's "you forgot `use std::io::Write`", and it is the worst kind for AI generation: code that looks right and fails with a far-off error.
  >
  > I propose that the ruling pick one of these:
  > 1. **(My preference.)** State in §3 that a type named in the signature of an imported fn counts as "in scope" for method resolution. This is a general rule, not a special case for mocks.
  > 2. Every example imports the type explicitly: `import std.testing.{mock_clock, MockClock}`.
  >
  > ## Vote intent
  >
  > - **(a) Cosmetic:** remove `mut` from every field, and rename `.handler()` to `.as_handler()` in §8.10.3 and §8.10.4.
  > - **(b) Structural:** Proposal A.
  >   - Each mock gets a sibling `MockClockOps`, `MockEnvOps` or `MockRandOps` trait, following the `TcpSocketOps` precedent.
  >   - The state lives in the factory's `let mut` cells, shared through §2.8 capture.
  >   - The struct holds only the handler and closures, so copying it by value is harmless.
  > - **Self-field mutation:** it does not persist. State this in §3.6 and add a cross-reference from the §4.6.3 Timer example ([BlockHandler state ticket]) so the spec stops teaching the wrong model.
  > - **Method resolution:** risk resolution 1 above.

- **Minimalism:** (excerpts; each block is a separate excerpt)
  > ### M1 (preferred): no language change. State lives in captured cells, methods come from a single-type trait
  >
  > The controller is a plain struct built by the factory. The factory's `let mut` locals hold the mutable state. Closures and the handler capture those locals as shared cells (§2.8), so no one ever writes `self.field = ...`. The methods attach through one trait per controller, following the `TcpSocketOps for TcpSocket` precedent.

  > **Rulings this implies:**
  > - **(a) Example syntax:** remove `mut` from the fields. Rename `.handler()` to `.as_handler()`, because `as_` already means "view as another type".
  > - **(b1) How methods attach:** through the trait. No inherent impl, so the 4-1 vote stands.
  > - **(b2) Self-field mutation:** it does **not** persist. `self` is passed by value and is not a place under §2.22. The spec must state this outright and stop implying the opposite anywhere.
  > - **Nesting:** each `mock_clock(...)` call makes new cells, so the nesting isolation that §8.10.3 promises still holds.
  > - **Idempotent handler:** the factory builds the handler once and `as_handler()` returns that same value. §8.10.4's "two handles, same state" promise holds with no special work.
  > - **Cascade:** `MockEnv` gets an `EnvControl` trait (`as_handler`, `set`, `writes`). `MockRand` gets a `RandControl` trait (`as_handler`, `draws`, `reseed`). Rewrite §8.10.3:1017 to say "closes over cells captured at construction" in place of "closes over `self`".
  >
  > **Tradeoffs from the minimalism view:**
  > - It adds zero syntax and zero new semantics. It only uses features the language already has: closure capture, single-type traits and handler values.
  > - It adds three traits whose only job is to carry methods. That is the known cost of the 4-1 inherent-methods decision, and we accepted it then. Systems' old dissent comes back, and it is weaker when the traits are stdlib-internal.
  > - **Open risk: import friction.** A user may need `import std.testing.{mock_clock, ClockControl}` before `mc.advance(...)` resolves. Someone must check whether trait-method resolution needs the trait in scope. If it does, the spec example must show the import, or the prelude must auto-import these traits. I reject the prelude option because it widens the prelude for test-only code.
  > - Stateless mocks gain nothing. `capture_log` and the rest stay unchanged.

  > ### What I reject, and why
  >
  > - **An inherent-impl form or `mut self`.** Both re-open settled decisions (4-1 against inherent methods, 5-0 for by-value `self`) to serve three test mocks. Test helpers must never drive core language surface. That is the C++ committee failure mode.
  > - **Making self-field mutation persist.** It breaks by-value `self` for every type in the language to fix one spec example.
  > - **Handling this in [this ticket].** The §4.6.3 Timer example (`self.start = ...`) is the same bug. Fix it under [BlockHandler state ticket] with the same rule, and do not widen this ticket. Also add one line to §3.6: "assigning to a field of `self` changes the callee's copy only."
  >
  > **Vote intent:** M1. I will accept M2 if M1's trait-import question cannot be solved without widening the prelude.

#### Phase B — Debate (round 1)

Round 1 ended with all six panelists marked stable and ready to vote. Key shifts: Minimalism dropped `ClockControl` for `MockClockOps`; Systems moved from a live list to a copy; DevOps narrowed from "compile error now" to "state it here, error vs. silent in the parameter-mutation ticket"; AI/ML moved the other way, from "state it" to "error now"; Web switched to rewriting the Timer example now. Each panelist's full round-1 reply:

- **Systems:**
  > Systems Phase B round 1 (full resend).
  >
  > V1: MockClockOps. Stdlib already uses *Ops for single-type traits (TcpSocketOps, PidOps, RowOps). Two suffixes in one stdlib buys nothing.
  >
  > V2: I move to plt. elapsed() and writes() return a clone() snapshot. My live-alias argument was zero-cost thinking, the wrong trade in test-only code. A List is a shared cell, so an alias lets the test push into handler state. That is a correctness hole, and the copy costs a few Durations. It also matches env.vars(), which the spec already calls a snapshot. The spec must state: "returns a copy; later handler activity does not change it." No .snapshot() method.
  >
  > V3: This ticket says "does not persist" in normative text (self is a by-value copy); that answers ask (b). Error vs silent covers all params, so it goes to [parameter-mutation ticket]. Note that sys (with devops, plt) recommends a compile error there. Silently changing a copy is a latent bug, and devops' diagnostic sketch is right.
  >
  > V4: Import the type explicitly in the examples. No new rule here. §3.6:2705 says impls come into scope when the type or trait is imported, so import std.testing.{mock_clock, MockClock} works under the current spec. The "type reached through an imported fn's return is in scope" rule changes name resolution for every API, so it needs its own spec ticket. No runtime cost either way; I prefer no new rule.
  >
  > V5: Hand the Timer example to [BlockHandler state ticket], but add a visible marker now. A rewrite means ruling on BlockHandler enter-to-exit state (Context threading), which is out of scope. Once this ruling says self.f = does not persist, the spec contradicts itself. Add one line at §4.6.3: "This example relies on self mutation persisting, which §3.6 rules out; see the open BlockHandler state ticket."
  >
  > V6: Yes, one sentence in §3.6: "Copying a struct copies its fields. A field whose value is a cell (List, Map, Set, or a closure or handler that captures a let mut) still refers to the same cell after the copy." That is the real memory model, and the controller design depends on it.
  >
  > MISSING ITEM, part of this change: §4.7 must say a handler E { ... } expression captures let mut locals with the same shared-cell rule as closures (§2.8). All six primaries depend on it, and the moderator confirmed the spec does not say it. One sentence; no separate ticket.
  >
  > Stable, ready to vote.

- **Web/Scripting:**
  > Web/Scripting Phase B round 1 positions (full resend). Stable, ready to vote.
  >
  > V1, trait name: MockClockOps / MockEnvOps / MockRandOps. It matches the XOps suffix the stdlib already uses (TcpSocketOps, PidOps). The only place a user sees the trait is a help line, and a name that matches the type is the easiest to find there.
  >
  > V2, return value: a clone() snapshot (as plt proposes), plus one sentence: "returns a copy; call again to see later sleeps." A live alias changes under `let s = mc.elapsed()`, the same class of bug as Python's mutable default. The copy costs nothing in a test. No separate .snapshot() method.
  >
  > V3, self.f = e: this ticket rules "does not persist" and states it normatively in §3.6. Error vs. silent goes to [parameter-mutation ticket], with the panel recommending error (devops's diagnostic text is good). Make [parameter-mutation ticket] block calling the mock examples final. If the panel wants to decide it here, I vote error and will not block.
  >
  > V4, visibility: fix the rule. A type named in the signature of an imported item counts as in scope for method resolution (aiml option 1). A user who follows the docs and still gets "no method advance" is the worst error there is. TS, Kotlin and Python all allow method calls on a value whose type was not imported. Reject explicit type imports in the examples (ceremony) and prelude auto-import. This fixes every stdlib factory fn, not only mocks.
  >
  > V5, Timer example: rewrite it in this change. I am switching to devops's side. Once §3.6 says self.f = e does not persist, the §4.6.3 Timer example contradicts the spec, and spec examples are training data. Rewrite it with a captured let mut or closure fields. [BlockHandler state ticket] keeps the deeper question of BlockHandler enter-to-exit state.
  >
  > V6, aliasing statement: yes, two lines in §3.6: "Structs copy on pass. List, Map, Set and closures share their contents across copies." Put it next to the V3 sentence. Reference-minded JS/Python devs must find it easily.
  >
  > Added gap (sys raised it): §2.8 states shared-cell capture for closures only. W1 depends on `handler E { ... }` expressions capturing let mut locals the same way, so §4.7 must say so in one sentence with a cross-reference to §2.8. The "no capture" line at §4:1368 is about BlockHandler block bodies, not handler expressions, but it reads as a contradiction. The new sentence should separate the two.

- **PLT:**
  > ## PLT positions, Phase B round 1
  >
  > **V1 (trait name): `MockClockOps` / `MockEnvOps` / `MockRandOps`.** It follows the `TcpSocketOps`/`PidOps` precedent, so it is one naming rule with no special case. `ClockControl` is a fine name, but a second convention for the same construct is a cost with no gain.
  >
  > **V2 (return of `.elapsed()` / `.writes()`): snapshot (`clone()`). I hold this.** A live view breaks equational reasoning at the test site:
  >
  > ```blink
  > let before = mc.elapsed()
  > with mc.as_handler() { retry_with_backoff(op) }
  > assert_eq(before.len(), 0)   // fails under a live view
  > ```
  >
  > `before` changes value with no assignment to it, and nothing in its type tells the reader. A live view also lets the test push into the handler's internal log, which corrupts the mock's invariant. Cost is not an argument in a test API. If the panel picks the live view anyway, the spec must say "live view" in words (sys's condition). What I reject is the silent version: web, min and aiml return `slept` with no statement, and that is the one choice that stays unsound by omission.
  >
  > **V3 (`self.f = e`): this ticket must rule "does not persist". Error vs silent goes to [parameter-mutation ticket], with the panel's recorded intent that it be an error.** I object to min's sentence as worded. "Changes the callee's copy only" makes silent mutation of a copy a documented feature, and that decides [parameter-mutation ticket] by the back door. Replacement wording for §3.6: "A method cannot change its caller's value through `self`. State that must persist across calls lives in a `let mut` binding captured by a closure or handler (§2.8)." That sentence is true under both outcomes of [parameter-mutation ticket].
  >
  > **V4 (trait-method visibility): the examples import explicitly now, and the type-directed rule goes to a separate `type:spec` ticket.** aiml's option 1 ("a type in an imported fn's signature counts as in scope") is a change to the §3.6 reachability rule for the whole language, not a mock fix. It is plausibly sound (coherence holds because the impl lives in the type's defining module), but it needs its own deliberation. For now, since §3.6:2705 says the type *or* the trait is enough, the examples write `import std.testing.{mock_clock, MockClock}`. Importing the type is the smallest legal form. I would also accept devops's `help: import std.testing.{MockClockOps}` diagnostic as a tooling follow-up, because it adds no new rule.
  >
  > **V5 (Timer §4.6.3): hand it to [BlockHandler state ticket], plus a cross-reference now.** Its real problem is enter-to-exit state flow in `BlockHandler`, which is a separate typing question. To keep the spec from contradicting itself in the meantime, add one line at the Timer example that says it depends on [BlockHandler state ticket] and that `self.start = ...` does not persist per §3.6.
  >
  > **V6 (struct aliasing in §3.6): yes, this change must include it.** Proposed text: "Struct values have value semantics. `let mut b = a` then `b.x = 1` leaves `a` unchanged." Without this, V3's "does not persist" has no semantic ground. Before the spec asserts this, someone should check that the compiler really copies on bind or assign (a GC pointer shared by both would be a bug). That check needs a probe, not a vote.
  >
  > **Addition (sys's fact):** §4.7 must state that a `handler E { ... }` expression captures from its scope under the same shared-cell rule as a closure (§2.8). All six proposals rest on that, and today the spec only implies it. Also, my sketch named the op wrongly: it is `fn read() -> Instant`, not `fn now()`.
  >
  > Stable, ready to vote.

- **DevOps:**
  > DevOps Phase B round 1: my position on V1-V6, plus one addition. Stable, ready to vote.
  >
  > V1 trait name: MockClockOps / MockEnvOps / MockRandOps. The *Ops suffix matches TcpSocketOps and PidOps, so a user who knows one knows the rest. It is also what `blink doc` and LSP hover will show as the owner of `.advance()`. ClockControl reads well, but it breaks the pattern for no gain. This is a weak preference and I will not block on it.
  >
  > V2 elapsed()/writes(): return a clone() snapshot (plt), and the spec must say so. If the list is a live alias, the value a test reads inside the `with` block can change before the assert runs, and a failure message then shows a list the test never saw. That makes failures hard to debug. A copy costs nothing in a test. Whichever way the panel votes, the spec must name the semantics. It must not leave them for the reader to guess.
  >
  > V3 self.f = e: I narrow my position. This ticket states the fact: "assigning to a field of self changes the callee's copy only; it does not persist." Whether that is an error or a silent write belongs to [parameter-mutation ticket], because it covers every parameter, not just self. In [parameter-mutation ticket] I will vote for a compile error with the diagnostic I sketched. A silent lost write is the worst case for tooling. The fixing change must note the dependency on [parameter-mutation ticket].
  >
  > V4 visibility: under current spec, §3.6:2705 already brings impls into scope when the TYPE is imported. So the smallest legal fix is to have the examples import it: `import std.testing.{mock_clock, MockClock}`. That works today with no rule change. aiml's option 1 (a type named in an imported fn's signature counts as in scope for method resolution) is the better long-term rule, and it matches how the LSP already resolves the receiver type. But it changes method resolution for the whole language, so it needs its own spec ticket. It must not ride on this one. Whatever the rule, "no method" on a trait method must print "help: import std.testing.{MockClock}". I am dropping my own phrasing ("resolves wherever the type is visible") in favour of this.
  >
  > V5 §4.6.3 Timer: hand the fix to [BlockHandler state ticket], on one condition. Once V3 says writes to self do not persist, §4.6.3 contradicts the spec on the same day. This change must add at least a note or cross-reference at §4.6.3 saying the example is known wrong and pointing to [BlockHandler state ticket]. aiml's cross-reference satisfies this.
  >
  > V6 §3.6 sentence: yes. Combine min's and plt's text: "self and every parameter are copies. A struct copy is shallow: List, Map, Set and closure fields still refer to the same cell." That second sentence is what makes the controller design work. It also appears in hover docs and `blink llms`, so users and AI agents learn it from one place.
  >
  > Addition (sys's point): §4.7 must state that a `handler E { ... }` expression captures outer `let mut` bindings by shared cell, the same as a closure (§2.8). Without that, the whole design rests on behaviour the spec does not state.

- **AI/ML:**
  > My positions on the Phase B items:
  >
  > **V1. Trait name: `MockClockOps`, `MockEnvOps`, `MockRandOps`.**
  > The stdlib already uses the `*Ops` suffix (`TcpSocketOps`, `PidOps`, `RowOps`). A model that has seen one of those predicts the name correctly. `*Control` would bring in a second convention for the same kind of thing, which is one more decision point with no gain.
  >
  > **V2. Return value: a snapshot (plt), and the spec must say so.**
  > - Every accessor on a mock controller returns a copy that the later handler ops do not change.
  > - With a live alias, `let s = mc.elapsed()` followed by more sleeps would change `s` from a distance, and a `.push` by the test would corrupt the mock.
  > - The copy matches the model that by-value `self` already teaches: what you get back is a value, not a window into internal state.
  > - Test lists are small, so the copy costs almost nothing.
  > - `capture_log` is not a counter-example. There the caller passes in its own list, so aliasing is the whole point and it is visible at the call site.
  > - Whichever way the panel votes, the spec text must say "snapshot" or "live view" in one sentence. If the spec says nothing, generated code will be wrong about half the time.
  >
  > **V3. `self.f = e`: a compile error, ruled in this ticket and limited to `self`.**
  > A silent no-op is the worst outcome for AI generation. The code compiles, the test runs, and the state change is lost without any signal. That is the pattern models copy from Python and JS training data (`self.x = ...`), so it will be generated often.
  > - `self` is a special receiver and already has its own 5-0 by-value rule, so ruling on it here does not decide [parameter-mutation ticket]'s question about other parameters.
  > - Use devops's diagnostic text, including the help line that points to a captured `let mut`.
  > - If the panel wants to keep this ticket's scope narrow, my fallback is: rule "does not persist", and require that no spec example shows `self.f = e` while [parameter-mutation ticket] is open. I change my Phase A position from "state it does not persist" to "error".
  >
  > **V4. Method visibility: my option 1 (the same as web's), plus devops's help line.**
  > - The rule: a type reached through the signature of an imported fn counts as in scope for impl lookup. The examples then need no extra import, which saves tokens on every mock test.
  > - The diagnostic: when a method is not found but an impl exists in a dependency, the error prints `help: import std.testing.{MockClockOps}`.
  > - The two parts do not conflict. The rule removes the trap, and the help line catches cases the rule does not cover.
  > - I reject a prelude auto-import, which agrees with min.
  >
  > **V5. Timer example: rewrite it in this change.**
  > I change my Phase A position here. If V3 makes `self.f = e` an error, a spec example that does it contradicts the spec, and models learn from examples before rules.
  > - The smallest legal rewrite: `enter` returns the start `Instant` as its `Context`, and `exit` uses it, if `exit` can receive the Context.
  > - If [BlockHandler state ticket] confirms that `exit` cannot see Context today, remove the illegal line and put a [BlockHandler state ticket] marker in its place. Do not leave the illegal line in the spec.
  >
  > **V6. Add the §3.6 sentence, and one more line that sys found.**
  > 1. §3.6: "Assigning to a field of `self` is an error; a struct value passed as `self` is a copy of its fields." Reword this to match whatever V3 decides.
  > 2. §4.7: a `handler E { ... }` expression captures enclosing bindings the same way a closure does (§2.8), and `let mut` captures become shared cells. The whole Proposal A design depends on this, and the spec does not say it today. A model that reads only the spec cannot derive that the design works without it. I consider this line mandatory, not optional.
  >
  > Stable, ready to vote.

- **Minimalism:**
  > **Minimalism, Phase B round 1**
  >
  > **V1 (trait name): I switch to `MockClockOps` / `MockEnvOps` / `MockRandOps`.** It matches the stdlib precedent (`TcpSocketOps`, `PidOps`), and five of six already chose it. My name adds nothing, so I drop it.
  >
  > **V2 (what `.elapsed()` / `.writes()` return): the live list, with no copy and no `.snapshot()` method.**
  > - `capture_log` already works this way: the test holds a live list that the handler writes into. A snapshot rule for the controllers would give the family two aliasing rules.
  > - A test that wants a copy calls `.clone()`. We do not need a named method for that.
  > - The spec adds one sentence: "returns the live recorded list; call `.clone()` for a copy."
  > - plt's worry is that the test could push into mock state. A test can only harm itself that way, and a copy on every call does not pay for preventing it.
  >
  > **V3 (`self.f = e`): this ticket states only "does not persist", and [parameter-mutation ticket] decides error vs silent.**
  > - The mock design no longer depends on self-field mutation, so this ticket does not need the ruling.
  > - Pulling in the whole "are parameters places" question widens scope, and that is how panels ship half-thought rules.
  > - For the record, when [parameter-mutation ticket] comes up I lean toward a compile error. A silent no-op write is a footgun, and the error fits §2.22 as written. But we should decide it there, with every parameter case in view, not only `self`.
  >
  > **V4 (trait-method visibility): make no rule change here. The examples import the type, and a separate spec ticket handles the general rule.**
  > - The moderator's fact settles it. §3.6:2705 says impls come into scope when the **type or** the trait is imported. So `import std.testing.{mock_clock, MockClock}` works under today's rules, with no spec change.
  > - aiml's option 1 and devops's "resolves wherever the type is visible" both change method resolution for every program to spare one name in a test import. That may be the right rule, but it is a language change that needs its own deliberation, not a rider on a mock ticket. I would open it as a `type:spec` ticket.
  > - I still reject auto-importing through the prelude.
  >
  > **V5 (the §4.6.3 Timer example): hand it to [BlockHandler state ticket] and add a cross-reference now.**
  > - The contradiction exists today whatever we do here.
  > - The real fix needs [BlockHandler state ticket]'s enter-to-exit state design, which this ticket does not own.
  > - A one-line note in §4.6.3 ("the `self.start = ...` line does not persist; see [BlockHandler state ticket]") stops the spec from misleading readers in the meantime. That answers devops's concern at no design cost.
  >
  > **V6 (§3.6 statement): yes, one sentence.** "Assigning to a field of `self` or of any by-value parameter changes the callee's copy only."
  >
  > **One required addition:** a sentence in §4.7 saying that a `handler E { ... }` expression captures outer bindings exactly as a closure does (§2.8, where a `let mut` capture is a shared cell).
  > - The whole design rests on this. sys is right that the spec does not say it today.
  > - This is not new semantics: `capture_log` and the inline `record_calls` replacement in §8.10.3 already depend on it. We are writing down what exists, which is the kind of addition I support.
  >
  > Stable, ready to vote.

A gen1 probe run between Phase B and Phase C confirmed: struct bind/pass copies fields while a `List` field stays shared; a `handler Time { ... }` stored in a struct field shares the factory's `let mut` bindings with closure fields.

#### Phase C — Final vote

Six fresh voters, each seeing only the ballot.

- **Q1: Core design: state in factory `let mut` locals shared by the handler value and closure fields; methods through a single-type trait; `.handler()` → `.as_handler()`; same shape for MockEnv, MockRand** (6-0)
  - **Systems:** A — Every state cell is a `let mut` binding captured by closures and a handler. That is the capture model §2.8 already defines, so we add no new runtime machinery. A probe shows the design compiles and runs today. Each fallback is worse: `Cell[T]` adds a stdlib type that repeats what capture already does, and single-element List cells hide their cost and their intent. *Concern:* Each controller now carries one heap closure environment per field, and the spec must not hide that allocation.
  - **Web/Scripting:** A — A JS dev reads `mock_clock(start)`, calls `mc.advance(d)`, and hands over `mc.as_handler()`. That is the whole API, and it works today. Each fallback moves the ugliness to the call site: `(mc.advance)(d)` looks like a typo, and a `Cell[T]` is one more concept to learn. *Concern:* Closures that capture `let mut` stay hidden in the stdlib, so users will copy the pattern without knowing why `slept` has to be `let mut`.
  - **PLT:** A — The shared design needs no new typing rule. State lives in `let mut` bindings captured as shared cells (§2.8), and methods reach it only through trait impls, so it fits every rule already decided. Each fallback adds a new surface: `Cell[T]` adds a type, a bare closure field forces the `(mc.f)(d)` call form, and a `List` used as a cell is a type-level lie. *Concern:* The design rests on handler expressions capturing like closures, which the spec does not state yet. Q8 must pass, or the design is sound only because the compiler happens to allow it.
  - **DevOps:** A — The shared design compiles and runs today, so the compiler already backs every example in the spec, and every diagnostic points at real code. Each fallback has a worse error surface. `(mc.advance)(d)` gives a confusing "not callable" error when someone writes `mc.advance(d)`, and a List cell gives index errors that have nothing to do with a clock. *Concern:* A user who writes `let slept = []` without `mut` gets MutationRequiresMut inside the stdlib pattern they copied, so the spec example must show `let mut`.
  - **AI/ML:** A — One shape across MockClock, MockEnv and MockRand gives a model one pattern to learn. Probes show it compiles and runs today. `(mc.advance)(d)` and one-element List cells both need extra syntax and pull toward idioms from other languages, so models would generate them wrongly more often. *Concern:* Sketches wrote plain `let slept` and `now + d`, so the spec example must use `let mut` and `.add(d)`, or models will copy the error.
  - **Minimalism:** A — The shared design uses only features the language already has: traits, closures that capture `let mut` bindings, and handler expressions. The moderator's probe shows it compiles and runs today. Each fallback adds a new concept (`Cell[T]`) or makes the call site worse (`(mc.advance)(d)`, one-element lists). *Concern:* `slept` must be `let mut`, and some drafts used plain `let`. If the spec examples repeat that mistake, readers will copy code that does not compile.

- **Q2: Trait names `MockClockOps` / `MockEnvOps` / `MockRandOps` (A) vs `ClockControl` / `EnvControl` / `RandControl` (B)** (6-0)
  - **Systems:** A — `*Ops` is the naming the compiler already uses for its trait surfaces (StrOps, BytesOps). One convention costs less to learn and to grep than two. `*Control` reads a little better but adds a second naming scheme. *Concern:* Users can mistake `MockClockOps` for the `Time` effect ops, so the doc line must say it controls the mock.
  - **Web/Scripting:** A — Users type `MockClock`, not the trait name. The trait shows up in imports and error messages, and `MockClockOps` points straight at the type it serves. `ClockControl` sends a reader looking for a type called `Clock`. *Concern:* "Ops" tells a newcomer nothing, so the doc comment on each trait has to do the explaining.
  - **PLT:** A — `*Ops` matches the existing trait convention (StrOps, BytesOps). A trait name should say that it is the method surface of one type, and `Ops` does that without claiming a wider abstraction. *Concern:* Users may read `ClockControl` as a general interface and expect other clocks to implement it.
  - **DevOps:** A — A trait named `MockClockOps` shows up right next to `MockClock` in LSP completion and hover, so the user can see the link. `ClockControl` sorts away from the type and reads like a production API. Grep and "go to definition" also work better when the two names share a prefix. *Concern:* Users will guess `Ops` traits exist for other types when they do not.
  - **AI/ML:** A — `<Type>Ops` follows from the type name, so a model can guess the trait from `MockClock` alone. `ClockControl` is one more name to recall and could be confused with the `Time` effect or a real clock API. *Concern:* Users will seldom write the `Ops` name, and some may read it as an operator-trait family.
  - **Minimalism:** A — `MockClockOps` ties the trait to the type it serves, so a reader gets one name to learn, not two. `ClockControl` reads like a separate, general concept that could have other implementations, and nothing here needs that. *Concern:* If the "Ops" suffix spreads, it becomes a naming habit nobody chose on purpose.

- **Q3: `.elapsed()` / `.writes()` return a copy (A) vs the live list (B)** (5-1, Minimalism dissent)
  - **Systems:** A — A List is a shared cell. If we return the live list, the test and the handler share mutable state, and a push through that alias changes what the handler recorded. A copy costs O(n) once per call, only in test code, and the reader sees that cost. A live alias costs nothing at the call but causes spooky action later. *Concern:* A test that calls `.elapsed()` in a hot loop copies the list each time, so the docs must say "call once, after the run".
  - **Web/Scripting:** A — Python and JS devs expect a getter to give back a value they can hold. If a list changes after it has already been read, a failing assert prints something the test never checked. "Returns a copy; call again to see later sleeps" takes one line to learn. *Concern:* Someone will call `elapsed()` inside a hot loop and pay for a copy every time.
  - **PLT:** A — A copy keeps equational reasoning at the test site. `let e = mc.elapsed()` then means one fixed value, and a later assert cannot see a different list. A live view makes an aliased shared cell visible to the user, and a test could then push into handler state. *Concern:* An implementation that forgets `.clone()` returns the live list with no error, so the stdlib needs a test that proves it returns a copy.
  - **DevOps:** A — A failed assertion must print the value the test actually checked. With a live list, the failure message can show entries pushed after the check. A copy keeps the test output tied to what the test saw. *Concern:* A test that keeps an old copy and asserts on it after more sleeps will fail, and nothing in the error will say it was a copy.
  - **AI/ML:** A — A copy means the value at the assert is the value the test got, which is simpler to reason about and to debug. A live list whose contents change after the call is a subtle bug that models make and seldom detect. *Concern:* `capture_log` returns a live list, so the stdlib has two conventions; one must change or the spec must say why they differ.
  - **Minimalism:** *(dissent)* B — The closure already returns the list it captured, so a live list needs no extra copy step. `capture_log` already works this way, so returning a copy here gives the testing surface two rules. A user who wants a snapshot writes `.clone()`, which states the intent at the call site. *Concern:* If A wins, `capture_log` and the mock accessors will behave differently until someone brings them into line. Record that follow-up.

- **Q4: `self.f = e`: §3.6 states the write does not reach the caller, error vs. silent goes to the parameter-mutation ticket with a recorded recommendation of error (A) vs compile error on `self` now (B)** (5-1, AI/ML dissent)
  - **Systems:** A — The normative fact is that `self` is a by-value copy (5-0), so a write through it never reaches the caller. Whether that write is an error or silent affects every by-value parameter. It belongs to [parameter-mutation ticket] as one rule, not a special case for `self`. The recorded recommendation for error keeps the pressure on. *Concern:* If [parameter-mutation ticket] stalls, users write `self.f = e` and get silent no-ops meanwhile.
  - **Web/Scripting:** A — I want the error, but [parameter-mutation ticket] owns the question for all parameters. A rule that covers only `self` gives two behaviours to learn. This ticket should state the fact and put the recommendation for an error on record. *Concern:* Until [parameter-mutation ticket] lands, `self.x = 1` does nothing and says nothing. That trap catches every dev coming from JS or Python.
  - **PLT:** A — `self` is an ordinary by-value parameter (§3.6). A rule that makes writes an error only for `self` treats one parameter differently from all others, and [parameter-mutation ticket] must decide all parameters together. The normative text must not describe the silent write as a feature, so I hold my wording: "A method cannot change its caller's value through `self`." *Concern:* Until [parameter-mutation ticket] lands, the silent no-op stays a trap for users and for AI-generated code.
  - **DevOps:** A — One ruling on error vs. silent for every parameter gives one diagnostic code and one explain page. If we rule on `self` now and leave other parameters to [parameter-mutation ticket], we get two behaviors and two messages for the same mistake. The normative sentence plus the recorded recommendation to make it an error is enough to keep spec examples honest. *Concern:* If [parameter-mutation ticket] stalls, a silent no-op ships as the de facto behavior, and that is the worst possible diagnostic outcome.
  - **AI/ML:** *(dissent)* B — A write that silently does nothing is the worst result for generated code. Models trained on Rust, Python or JS will write `self.count += 1` and expect it to persist, and nothing tells them it did not. A compile error on `self` fixes this now at low cost. *Concern:* If A wins, the spec example set must hold no `self.f = e` until [parameter-mutation ticket] rules, or it teaches the silent case.
  - **Minimalism:** A — The spec should state the fact, "does not persist", and nothing more. Error vs. silent covers every parameter, and [parameter-mutation ticket] already owns that question. A special error for `self` alone adds a rule that [parameter-mutation ticket] may make redundant or contradict. *Concern:* Until [parameter-mutation ticket] closes, users still get a silent write that goes nowhere. This option is only safe if no spec example shows `self.f = e` in the meantime.

- **Q5: Visibility: no rule change, examples import the type (A) vs a type named in an imported signature counts as in scope (B)** (4-2, Web and AI/ML dissent)
  - **Systems:** A — §3.6:2705 already makes this work when the examples import the type. A type-directed rule changes how method resolution finds impls, and that needs its own analysis. Deciding it inside a mock-controller ticket is the wrong place. *Concern:* Until the help diagnostic ships, "no method advance" will trip users who import only `mock_clock`.
  - **Web/Scripting:** *(dissent)* B — Someone follows the docs, writes `let mc = mock_clock(t)`, then gets "no method advance". That is the worst error a language can give. If an import function returns a type, method calls on that value should resolve. Examples that tell you to import the type as well only document the trap. *Concern:* The rule is wider than one ticket, and without a careful statement it could pull impls from other modules into scope in ways nobody expects.
  - **PLT:** A — A rule that makes types named in a signature count as in scope affects impl coherence and name resolution across modules. That needs its own analysis, not a line added inside a mock ticket. The explicit import already works under §3.6:2705. *Concern:* Users who follow a signature and not the docs will still get "no method" until the help diagnostic ships.
  - **DevOps:** A — An explicit import works under §3.6:2705 today, and the smallest legal fix is to use it. The wider type-directed rule changes how method resolution works across the whole language, so it needs its own ticket. The `help: import std.testing.{MockClock}` line on a "no method" error fixes most of the confusion by itself. *Concern:* If the help diagnostic slips down the backlog, a user who copies an older example still gets a bare "no method advance".
  - **AI/ML:** *(dissent)* B — A model that imports only `mock_clock` and then calls `.advance()` gets "no method" and cannot tell why. That is one extra import decision per use. A type named in an imported signature is the rule users expect. *Concern:* The type-directed rule could bring impls into scope that the user did not expect, and method-name clashes would then give ambiguity errors.
  - **Minimalism:** A — §3.6:2705 already makes the explicit import work, so the examples need no new rule. A type-directed scope rule is a real language change and should go through its own `type:spec` ticket. A mock-clock fix is the wrong place to widen name resolution. *Concern:* Users who follow older docs will still hit "no method advance" until the help diagnostic ships.

- **Q6: §4.6.3 Timer: visible note, fix stays with the BlockHandler state ticket (A) vs rewrite/remove the line now (B)** (4-2, Web and AI/ML dissent)
  - **Systems:** A — How state flows from `enter` to `exit` is [BlockHandler state ticket]'s question, and a rewrite now could contradict what that ticket decides. A visible note stops readers, and models trained on the spec, from copying the line as correct. *Concern:* The note can outlive [BlockHandler state ticket] if nobody removes it when that ticket closes.
  - **Web/Scripting:** *(dissent)* B — Spec examples are training data and copy-paste material. A note next to an illegal line still teaches the illegal line. Remove or rewrite it now, and [BlockHandler state ticket] keeps the deeper question of how state moves from `enter` to `exit`. *Concern:* A quick rewrite could lock in a pattern that [BlockHandler state ticket] later wants to change.
  - **PLT:** A — Any rewrite that keeps the enter-to-exit state decides [BlockHandler state ticket]'s question early. A visible note stops the example from teaching the wrong thing now. *Concern:* The note may stay in place for a long time, and a spec example that the spec itself marks wrong is poor training data.
  - **DevOps:** A — A visible note plus a cross-reference stops readers and models from copying the bad line now. The real fix depends on the state question [BlockHandler state ticket] owns. A rewrite here could give a second wrong answer. *Concern:* A note next to wrong code is still wrong code in the training data, so [BlockHandler state ticket] must not sit idle.
  - **AI/ML:** *(dissent)* B — Spec examples are training data. A note next to an illegal line still leaves the illegal line in the corpus, and models copy code, not notes. Remove or rewrite it now, and put a [BlockHandler state ticket] marker where the state question stays open. *Concern:* A rewrite made before [BlockHandler state ticket] rules could show a pattern that [BlockHandler state ticket] later changes.
  - **Minimalism:** A — [BlockHandler state ticket] owns the question of how state passes from `enter` to `exit`. Rewriting the example now would pre-decide that answer. A visible note stops readers from copying the illegal line. *Concern:* A spec example marked "does not work" is poor training data if [BlockHandler state ticket] stays open a long time.

- **Q7: §3.6 value-semantics sentence** (6-0)
  - **Systems:** A — This is the sentence that tells a reader what the hardware does. The copy is shallow, and a field that holds a cell still points to the same heap object. The probe shows exactly this split (`b.x` is independent, `b.xs.push` is shared), so the spec must state it. *Concern:* "Cell" needs one exact definition in §2.8, or the sentence adds a vague term.
  - **Web/Scripting:** A — "`let mut b = a` copies, but `b.xs.push` shows through `a.xs`" is exactly the JS object-vs-primitive confusion. One sentence heads it off, and it explains why the mock design works. *Concern:* If the sentence names the cell types in a list, it goes stale when a new cell type is added.
  - **PLT:** A — The copy-on-assign probe shows a copy that is shallow per field, and the spec must state that. Without the sentence, value semantics and shared-cell fields contradict each other with nothing to settle it. *Concern:* Readers may read "value semantics" as a deep copy and miss the rule that fields holding a cell still share it.
  - **DevOps:** A — The probe shows that `let mut b = a; b.x = 2` does not change `a`, but `b.xs.push` does. Without this sentence, users will file that as a bug. The sentence also gives the LSP hover text and a diagnostic note something to cite. *Concern:* "Shallow copy" may read as a promise about how the struct is stored in memory, so write it in terms of what the program can observe.
  - **AI/ML:** A — A shallow copy that shares cell fields is the least obvious fact in this design. Without the sentence, models will think the struct copy isolates the List. Explicit text is how a model learns this from the spec alone. *Concern:* The sentence must list every kind of cell (List, Map, Set, closure, handler), or models will generalise from an incomplete list.
  - **Minimalism:** A — This sentence writes down behavior that already exists (see the moderator's probe) and adds nothing new to the language. Without it, readers cannot predict how a copied struct behaves when a field holds a shared cell. *Concern:* If the wording lists cell types one by one ("List, Map, Set…"), it will go stale when a new cell-like type appears. Define the rule once, not as a list.

- **Q8: §4.7 handler-expression capture sentence** (6-0)
  - **Systems:** A — The whole Q1 design depends on handler expressions capturing `let mut` as shared cells, and no spec text says they do. Behavior with no spec text is a latent bug. The sentence also separates this case from BlockHandler bodies (§4:1368), which work differently. *Concern:* The handler's capture lifetime must match the closure rules exactly, or escape analysis will diverge between the two.
  - **Web/Scripting:** A — The mock design depends on a handler expression sharing `now` with a closure. Right now the spec says this only for closures, and its nearest sentence says "no capture". Without this line, users are guessing about how it works. *Concern:* Readers may still mix up handler expressions and BlockHandler bodies unless the sentence contrasts them in plain words.
  - **PLT:** A — This sentence is mandatory. Q1 is sound only if a handler expression captures exactly as a closure does. It must also say this is different from BlockHandler bodies (§4:1368). *Concern:* The capture rules for handlers and closures could drift apart later unless the spec defines one rule by pointing to the other.
  - **DevOps:** A — The whole mock design depends on handler expressions capturing `let mut` as shared cells, and no spec text says so today. Tooling (escape analysis, capture warnings) needs a written rule to point to. The sentence must separate this from BlockHandler bodies, or §4:1368 will confuse readers. *Concern:* If the compiler's handler capture ever differs from closure capture in some edge case, this sentence makes that a spec bug that needs a probe.
  - **AI/ML:** A — The whole design depends on handler expressions capturing `let mut` as shared cells, and no text says so today. §4:1368's "no capture" wording about block handlers will mislead readers unless the two cases are separated in writing. *Concern:* If the implementation ever differs from closure capture, the spec will then state something false.
  - **Minimalism:** A — The whole design depends on handler expressions capturing `let mut` bindings as shared cells, and today no text says they do. Without this sentence the stdlib depends on behavior the spec does not promise. It also removes confusion with the BlockHandler "no capture" text at §4:1368. *Concern:* If the sentence does not clearly separate `handler E { ... }` expressions from BlockHandler bodies, it will make that confusion worse.

#### Phase D — not run

Q5 and Q6 closed 4-2, which calls for a focused round. The moderator proposed closing both as soft consensus, and the user approved: on each question the majority's own concerns endorse the dissent's point as a follow-up.

- **Q5:** Minimalism, Systems, PLT and DevOps each name "no method advance" until a help diagnostic ships as the risk, and each says the type-directed rule needs its own ticket. Follow-ups: a spec ticket for the type-directed method-scope rule, and a tooling ticket for a "no method" help line that names the import.
- **Q6:** DevOps: "A note next to wrong code is still wrong code in the training data, so [BlockHandler state ticket] must not sit idle." PLT and Minimalism say the same. Follow-up: raise the BlockHandler state ticket's priority.

### Final Spec

```blink
pub type MockClock {
    time_handler: Handler[Time]
    advance_fn: fn(Duration) -> Void
    elapsed_fn: fn() -> List[Duration]
}

pub trait MockClockOps {
    fn as_handler(self) -> Handler[Time]
    fn advance(self, d: Duration)
    fn elapsed(self) -> List[Duration]
}

impl MockClockOps for MockClock {
    fn as_handler(self) -> Handler[Time] { self.time_handler }
    fn advance(self, d: Duration) { (self.advance_fn)(d) }
    fn elapsed(self) -> List[Duration] { (self.elapsed_fn)() }
}

pub fn mock_clock(start: Instant) -> MockClock {
    let mut now = start
    let mut slept: List[Duration] = []
    MockClock {
        time_handler: handler Time {
            fn read() -> Instant { now }
            fn sleep(d: Duration) { slept.push(d) }
        },
        advance_fn: fn(d: Duration) { now = now.add(d) },
        elapsed_fn: fn() -> List[Duration] { [..slept] },
    }
}
```

- State lives in the factory's `let mut` bindings. The stored `Handler[E]` and the closure fields capture them as shared cells (§2.8, §4.7). The struct fields are never assigned.
- Methods come from single-type traits `MockClockOps`, `MockEnvOps`, `MockRandOps`. No inherent `impl`, no `mut` fields.
- `.handler()` is renamed `.as_handler()`. It returns the same handler value on every call, so MockRand's idempotence rule holds by construction.
- `.elapsed()` and `.writes()` return a copy (`[..slept]`; lists have no `.clone()`).
- Examples import the controller type with its factory: `import std.testing.{mock_clock, MockClock}` (§3.6 impl scope).
- §3.6: a method cannot change its caller's value through `self`; a struct copy shares cell-valued fields. Error vs. silent for parameter-field writes stays open, with a recorded recommendation of error.
- §4.7: a `handler E { ... }` expression captures exactly as a closure does, unlike `BlockHandler` block bodies.
- §4.6.3: the Timer example carries a note; its fix stays with the BlockHandler state question.
