[< All Decisions](../DECISIONS.md)

# `abort` in a Handler Body — Design Rationale

The §4.4.3 mock `Env` handler ended its `exit` op with `abort`, and the §8.10.3 `mock_env` prose
spoke of an "`abort` shim". No section defined `abort`: not its syntax, not its type, and not what
it does to the `with` block. The §4.4.3 example asserted on `exit_code` after the `with`, which
works only if `abort` leaves the `with` and execution goes on after it. The same §8.10.3 example
also used `try { }`, which §3 rules out ("There is no `throw`, no `try/catch`"). The `Never` ruling
([never-bottom-type.md](never-bottom-type.md)) said a handler `fn` for an op declared `-> Never`
must diverge, and left this gap for a follow-up.

The panel decided whether Blink gets an `abort` construct, or whether the examples are rewritten
with constructs the spec already defines.

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated
in independent-proposal → debate → vote rounds.

Facts surfaced to the panel by the moderator:

- Handlers have no `resume` keyword. A handler gives an op its result by returning from the op's
  `fn` (§4.7). No spec text gives a handler a way to stop the `with` body and return to the point
  after the `with`.
- `assert_panics` (§2.20) is the only catch boundary a user can arm. It is test-only (E0833) and
  not nestable (E0834). §4.6.3 says user code cannot extend the set of catch boundaries.
- A captured `let mut` is a shared cell, so a write in a handler op is visible after the `with`
  (§4.7).
- The test runner's per-test boundary and `assert_panics` use setjmp/longjmp. `?` and `return` in a
  `with` body run cleanup through ordinary return paths.

#### Phase A — Independent proposals

All six proposed, on their own, to add no construct: the mock op panics, and the test wraps the
`with` in `assert_panics`. All six rejected an `abort` keyword. Excerpts, each in the panelist's own
words:

- **Systems:** "S1 (preferred): no `abort`. The mock op panics; the test observes it
  with `assert_panics`." On cost: "Zero new runtime machinery. Handler op calls stay ordinary C calls.
  After mono, the compiler can inline them." On the keyword: "It breaks the invariant that each op
  is tail-resumptive, which is what makes "handler op = plain call, inlinable after mono" true
  today." And: "It is a user-level catch boundary in all but name."
- **Web/Scripting:** "Proposal A (preferred): remove `abort`, use `panic`, observe the exit
  with `assert_panics`" Also proposed `MockEnv.exit_code() -> Option[Int]`: "Matching on a substring of
  a message to get an integer is fragile." On the keyword: "It is a large feature disguised as a
  word."
- **PLT:** "A handler op returns to the caller in tail position (§4.7), and nothing in the spec
  gives a handler an escape continuation to the point after `with`." And: "Outside a test you still
  cannot intercept `exit` and continue. I count that as correct, because `-> Never` means "the
  continuation is dead". A handler that brings the continuation back would turn `Never` into an
  ordinary type."
- **DevOps:** "do not add `abort`. Rewrite both examples to use `panic` plus `assert_panics`, and
  add one diagnostic." On the diagnostic surface: "Zero new diagnostic surface. `assert_panics`
  already ships E0831/E0832, and E0832 prints the full actual message and the panic site." Proposed
  help text for a stray `abort`: "Blink has no `abort`. A handler fn for an op declared `-> Never`
  must diverge: end it with `panic(...)`. To observe it in a test, wrap the `with` in
  `assert_panics`."
- **AI/ML:** "Add no new construct. A mock handler for a `-> Never` op ends in `panic(...)`, which
  is already `Never` (§2.20)." On the keyword: "**The name means the opposite in training data.** C
  `abort()`, Rust `std::process::abort`, Python `os.abort` and Go's runtime abort all end the
  process at once, with no unwind and no cleanup."
- **Minimalism:** "`abort` is not a missing definition. It is a placeholder for a feature the
  language has deliberately not got: a handler that does not resume". And: "Two undefined
  constructs in examples do not show a gap in the language. They show two examples that need
  fixing." Offered a stdlib `pub fn abort() -> Never { panic("handler aborted") }` only to oppose
  it: "a second name for `panic` that reads like a control-flow keyword will make users expect it
  to resume after `with`." On the keyword: "This is the C++ committee pattern: a feature gets in
  through an example."

#### Phase B — Debate highlights

One round. All six signalled stable.

- **Panic text.** Web conceded its `env.exit called with code N`: "The closing paren also prevents
  a false match: `matching: "env.exit(1)"` cannot match exit code 10. My wording does not have this
  property." Minimalism conceded its `exit(<code>)`: "It names the op that really fired."
- **Keep the cell in §4.4.3.** AI/ML changed from dropping it: "The §4.4.3 example teaches that a
  captured `let mut` is shared, and an integer read after the block does not depend on how the
  message is formatted."
- **Rule sentence.** Systems corrected the first draft: "'or uses `?`' is wrong in an op body: `?`
  there returns from the op fn, which only gives the caller a value. It does not end the `with`."
  PLT supplied the wording "...declares an op whose result type carries the outcome (e.g.
  `Result[T, E]`)".
- **`exit_code()` accessor.** Minimalism opposed it here: "It changes a decided API (the
  DECISIONS.md *mock_env* and *Mock controller* rows), so it needs its own ticket." Web: "If the
  panel prefers, split it into a std.testing follow-up ticket rather than putting it in this spec
  text."
- **Minimalism withdrew the stdlib `abort()`**: "Nobody wants it, and it gives `panic` a second
  name."

#### Phase C — Final vote

- **Q1: Construct** (6-0, P: no new construct; panic + `assert_panics`; `try { }` goes too)
  - **Systems:** P — "Handler ops stay plain calls that the compiler can inline after mono, and no
    `with` needs a landing pad. The only catch point is the test-only setjmp boundary that exists
    today, so production code pays nothing."
  - **Web/Scripting:** P — "A Python or Rust developer already knows the pattern of panicking in a
    mock and catching it with assert_panics; it is pytest.raises(SystemExit) and should_panic."
  - **PLT:** P — "`panic : Never` already inhabits the op's result type, so the Never ruling holds
    with no new typing rule. K needs an escape continuation that is delimited by `with`."
  - **DevOps:** P — "K adds frame-targeting ambiguity under `with a, b`, a new type for `with`, and
    a production catch boundary, all to serve one test mock."
  - **AI/ML:** P — "A model learns one rule: a `-> Never` op body diverges with `panic`, and a test
    observes it with `assert_panics`."
  - **Minimalism:** P — "K adds a second unwind model and a new catch boundary that §4.6.3 forbids
    without an amendment, all to save one block."
- **Q2: `mock_env` panic text** (6-0, the message contains `env.exit(` + decimal code + `)`)
  - **Systems:** "With the closing paren, `matching: "env.exit(1)"` cannot match `env.exit(10)`,
    and the text names the op exactly." Concern: "the spec must state the format exactly (decimal,
    no padding, no sign other than "-")".
  - **PLT:** Concern: "the spec must say "contains" and not "equals", or later message text will
    break tests."
  - **DevOps:** "`env.` is the spelling a user searches for." Concern: "The docs example should
    show the full text."
  - **Web/Scripting, AI/ML, Minimalism:** 2a. Minimalism's concern: "once it is normative, the
    message text is frozen, and changing its wording later counts as a breaking change."
- **Q3: §4.4.3 example** (6-0, keep the cell, write it first, `assert_eq` after `assert_panics`)
  - **Systems:** "It shows that a captured `let mut` cell is on the heap and keeps its write across
    the unwind."
  - **DevOps:** "`assert_eq` prints both ints side by side on failure, which tells the user more
    than a failed text match." Concern: "Keep the write as the first line of the op."
  - **Web/Scripting, AI/ML, Minimalism:** concern that readers will think the cell stops the run.
    AI/ML: "the prose should say that `assert_panics` stops the run and the cell only observes it."
  - **PLT:** 3a.
- **Q4: §4.6.3 table row** (Phase C 4-1-1: 4b Systems, PLT, DevOps, Minimalism; 4a Web; 4c AI/ML;
  went to Phase D)
- **Q5: "No early exit" rule** (6-0, three-sentence form)
  - **PLT:** "it states the invariant that handler ops are tail-resumptive and that `with` has no
    abort path. Today that invariant is only implied." Concern: "A future non-resumptive-op
    deliberation must amend this sentence explicitly."
  - **Systems:** "The third sentence tells production code how to get early exit at zero cost: a
    typed result plus `?`, all through ordinary returns."
  - **AI/ML:** Concern: "keep it framed as "only when early exit is needed"."
  - **Web/Scripting, DevOps, Minimalism:** 5a.
- **Q6: `MockEnv.exit_code()`** (6-0, not here; separate std.testing ticket)
  - **PLT:** "a typed observer is the better design, but it changes a decided std.testing API row.
    A gap fix should not quietly amend another decision."
  - All six voted 6b.
- **Q7: help text for a stray `abort` / `resume`** (6-0, help line on the existing unresolved-name
  diagnostic; diag ticket; no reserved keywords; not spec text)
  - **Web/Scripting:** Concern: "it must trigger only when the name is unresolved."
  - **Minimalism:** Concern: "the help could go stale if handlers ever get a non-resumptive form, so
    the diag ticket should note that."

#### Phase D — Round 2 (Q4)

- **Q4: §4.6.3 table row** (5-1, 4b; Minimalism dissent for 4c)
  - **Systems:** 4b — "Naming C `abort()` ties the spec to libc. A freestanding or zig target could
    end the process through another path, and the row would become false." And: "other runtime
    fatal paths exist apart from OOM, for example a failed runtime invariant check. Removing the
    word makes the row incomplete, and the table claims to be exhaustive."
  - **Web/Scripting:** 4b (was 4a) — ""Process abort" plus one sentence that says what triggers it
    (OOM, a fatal runtime error) and what happens (the process ends, nothing unwinds, exit()/close()
    do not run) is a defined term, not a new undefined word. I'm attaching one condition: the
    trigger sentence must be in the text, not optional."
  - **PLT:** 4b — "Foreign code that calls abort, stack overflow, and runtime fatal errors also end
    the process without unwinding. The row claims to be exhaustive ("the set is closed"), so
    dropping the word removes a real path from a closed set."
  - **DevOps:** 4b — "The editor should spell the term "fatal runtime error", not "abort", so that
    "abort" no longer appears in the row."
  - **AI/ML:** 4b (was 4c) — "4c only drops the word and states nothing, so a reader learns less."
    Condition: "the row or the clause must name what triggers it (OOM or another fatal runtime
    error)".
  - **Minimalism:** *(dissent)* 4c (was 4b) — "The test runner already has an `"aborted"` status,
    and any "abort" left in this row collides with it." And: "Subtraction removes the undefined
    word, needs no new term or definition, and loses no semantics, because the row's own column
    already says nothing unwinds."
  - **User (wording):** took DevOps's request; the term is "fatal runtime error", with the 4b
    definition, so the word "abort" leaves the row.

AI-first review: 5/5 pass (Debuggability rests on the Q7 help line).

### Final Spec

```blink
test "CLI exits with 1 on missing args" {
    let mut exit_code = -1
    let mock = handler Env {
        // ...the other seven ops...
        fn exit(code: Int) -> Never {
            exit_code = code
            panic("env.exit({code})")
        }
    }
    assert_panics(matching: "env.exit(1)") {
        with mock, capture_log([]) {
            run_cli()
        }
    }
    assert_eq(exit_code, 1)
}
```

- Blink has no `abort` construct. A handler `fn` for an op declared `-> Never` diverges with
  `panic` (or another diverging construct).
- A handler cannot end the `with` body early. A test observes a diverging op with `assert_panics`.
  Production code that needs early exit uses an op whose result type carries the outcome, and `?`.
- `mock_env`'s `exit(code)` panic message contains `env.exit(`, the code in decimal with no padding,
  and `)`. That text is stable.
- §4.6.3: the row reads "Uncaught panic (...) outside a runtime catch frame, or a fatal runtime
  error". A fatal runtime error is a fault the runtime cannot recover from (OOM, stack overflow,
  foreign code that ends the process); the process ends at once, nothing unwinds, and no
  `exit()`/`close()` runs.
- Follow-ups: `MockEnv.exit_code() -> Option[Int]` (std.testing ticket); help line for an
  unresolved `abort`/`resume` in a handler op body (diagnostics ticket).
