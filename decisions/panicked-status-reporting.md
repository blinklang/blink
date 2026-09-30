[< All Decisions](../DECISIONS.md)

# Panicked Status Reporting — Design Rationale

## The gap

§8.10 closes the test status enum (`passed | failed | panicked | skipped`) and the `cause` enum (`assertion | propagated_error`). The runtime drifted from it. A bug fix that keeps the test binary alive after a panic chose, with no vote, to report a panic as `status:"failed"`, `cause:"panic"`, `line:0` and an `error` object. The runtime never emitted `panicked`. The spec did not say which fields a `panicked` record carries, how it counts in `summary`, the exit code, or the human output. It also did not say what a panic does inside `test.failing`, `prop_check`, `for_each`, or during an armed `assert_panics` unwind.

Decisions already in force: the testing framework vote (JSON must tell `failed` from `panicked`), the expected-failure vote (no new status and no new `cause`), the `prop_check` `?` vote, the `assert_panics` semantics vote, the `?`-in-tests vote, and E0824 (a cleanup panic during a catchable unwind is a secondary warning, §4.6.3).

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated
in independent-proposal → debate → vote rounds. Q3 tied 3-3 and went to Phase D. The user
reopened Q6 after the vote, because the moderator's fact sheet left out §4.6:1360, and the
panel re-debated and re-voted it.

#### Phase A — Independent proposals

Each panelist wrote alone. Text is verbatim.

##### Systems

> # Systems panelist: proposal for tfxxwc
>
> **Position.** The spec is right and the runtime is wrong. zs3w3y was a bug fix (keep the binary alive after a panic). It was never a vote on the record shape. `cause:"panic"` breaks a closed enum that two votes (Q3 4-2, `?` 6-0) closed on purpose. Fixing the runtime costs one flag store on a cold path. No hot path changes.
>
> ## P1: Record shape
> An unexpected panic that escapes a test body emits `status:"panicked"` with no `cause`. The fields are fixed: `name`, `duration_ms`, `message` (the panic text), an optional `span` (where the panic fired), and an optional `warning` (E0824 cleanup panic).
>
> ```json
> {"name": "parse header", "status": "panicked",
>  "message": "unwrap called on None",
>  "span": {"file": "src/hdr_test.bl", "line": 14, "col": 9},
>  "duration_ms": 3}
> ```
>
> `span` is optional because `__blink_panic_dispatch(const char*)` takes only a message today. Runtime panics such as list index out of bounds do not have a source location. When codegen knows the site (unwrap, `panic()`), it passes `__FILE__`/line/col as constants. That adds only argument setup on a path that never returns, so a passing test pays nothing. I reject `line:0`: a sentinel value in a typed field is worse than a missing field.
>
> ## P2: Summary
> `summary` always carries every key: `{"total", "passed", "failed", "panicked", "skipped", "duration_ms"}`. Always emitting the keys, even when a count is 0, gives consumers a fixed schema and means nobody has to branch on a missing key. Invariant: `total == passed + failed + panicked + skipped`. Update the §8.10 example to match.
>
> ## P3: Exit code
> The test binary exits 1 when `failed + panicked > 0`. There is one non-zero code. CI tells "found a bug" from "test is broken" by reading NDJSON, not the exit status. Separate exit codes would leak detail through an 8-bit channel that shells and task runners already mangle. The `blink test` driver stays as it is (it reads the exit code only).
>
> ## P4: Human output
> The per-test line is `test NAME ... PANIC`, then the message and span. The summary line is `N passed, M failed, P panicked[, K skipped] (of T)`. The `panicked` term shows only when P > 0, the same rule as `skipped`. Update the assertions in `tests/test_runner_panic_continues_zs3w3y.bl`; do not delete them.
>
> ## P5: test.failing
> A panic counts as red, which the runtime already does. The record stays `status:"passed"` with `expected_fail:true`, plus the panic `message` so drift stays visible. Why: the most common known bug is an unwrap on None. If a panic did not count as red, a user could not mark that bug. Cross-language: pytest's `xfail` counts any exception as expected unless you give `raises=`. Rust `#[should_panic]` is a different construct (Blink's is `assert_panics`). This does not conflict with Q3: no new status and no new cause.
>
> ## P6: prop_check
> A panic inside a property closure does **not** shrink. The record is `status:"panicked"` and also carries `seed`, the unshrunk `input`, and `reproduce`. Why: after a longjmp out of the closure, heap and global state are in an unknown state (skipped cleanups, half-done mutation). Running more shrink trials on top of that state gives answers you cannot trust. Arming a catch frame per trial is cheap (a setjmp per trial, next to nothing beside the generator), but cheap does not make it sound. This matches the premise of the prop_check `?` vote: panicked means no shrink UX. The spec should state it as a rule.
>
> ## P7: for_each
> A case that panics records `status:"panicked"` in `cases[]`. The loop stops, which is the existing `__blink_test_is_failed` poll behavior. The parent test is `panicked`. Precedence when cases differ: `panicked > failed > passed`.
>
> ## P8: Precedence with other paths
> - A panic raised by `exit(false)` during an armed `assert_panics` unwind makes the test `status:"panicked"`, per the DevOps refinement in prior vote 4.
> - E0824 stays as it is: when a cleanup panics after a failure, the first failure stays the status and the cleanup panic becomes `warning`.
> - The first escape wins. The runner never upgrades a failed test to panicked.
>
> ## Out of scope
> - **Signal crashes (SIGSEGV, abort).** The process dies, and so do Rust libtest and Go. Forking a process per test to catch signals costs about 100µs+ per test plus copy-on-write (COW) page faults. I reject that as a default. A crashed binary becomes a file-level record, which belongs with 57n5xh.
> - **File that does not build.** That is 57n5xh.
>
> ## Cross-language
> - JUnit XML separates `<error>` from `<failure>`. `panicked`/`failed` map one-to-one, so a JUnit exporter needs no guesswork.
> - Rust libtest treats both as panics and cannot make this split. Go's `panic` kills the whole test binary, which is what zs3w3y fixed.
>
> ## Conflicts with prior votes
> None. This proposal applies the votes (Q2 DevOps requirement, Q3 closed enums, prop_check premise, assert_panics refinement) to a runtime that drifted from them.
>
> **Runtime cost:** `__blink_test_panic_handler` stores `__blink_test_panicked = 1` in place of `cause = "panic"`, and emit branches on it. That is one global and one branch in the report code. The code under test does not change.

##### Web/Scripting

> # Web/Scripting panelist: Phase A proposal (tfxxwc)
>
> **Position:** The spec is right and the runtime is wrong. Three votes already assume that `panicked` exists. Keep the enums closed, emit `panicked`, and delete `cause:"panic"`. A JS or Python dev who reads §8.10 and then sees `cause:"panic"` in real output will file a bug or a Stack Overflow question. Today the docs and the output disagree, and fixing that matters more than anything else in this ticket.
>
> ## P1: Record shape (required)
> An unexpected panic that escapes a test body produces `status:"panicked"`. The record has no `cause` field, as §8.10 already says.
>
> ```json
> {"type":"test","name":"parse empty","status":"panicked","message":"unwrap called on None","span":{"file":"tests/test_p.bl","line":12,"col":9},"duration_ms":1}
> ```
>
> - `message` is required and holds the panic message.
> - `span` is present when the runtime knows where the panic happened, and absent otherwise. Never write `line:0`. A zero line is a wrong value, and editors will jump to it.
> - Remove the empty `error:{..."error_type":""}` object. An empty field teaches readers nothing.
>
> **Tradeoff:** Tools that read `cause:"panic"` today will break. That output was never in the spec, so this is a bug fix, not a breaking change.
>
> **Other languages:** JUnit XML has `<failure>` for assertions and `<error>` for unexpected exceptions. That is the same split, and CI dashboards already show it. Jest and pytest merge the two, and users often ask how to tell them apart. We already voted to keep them apart (Q2, 5-0), so do it properly.
>
> ## P2: Summary and human output
> - The JSON summary always has `passed`, `failed`, `panicked` and `skipped`, even when a value is 0. `total` is the sum of the four. A fixed set of keys means scripts never need `?.panicked ?? 0`.
> - Correct the §8.10 example so its summary shows all keys.
> - The human line is `test NAME ... PANIC`, and the panic message follows on stderr.
> - The human summary is `N passed, M failed[, P panicked][, K skipped] (of T)`. Show `panicked` only when it is not zero, the same rule as for `skipped`.
> - Update `tests/test_runner_panic_continues_zs3w3y.bl` so it expects `PANIC` and `1 panicked`. Change the assertions; do not delete them.
>
> **Tradeoff:** People who grep CI logs for `FAIL` will miss panics. I accept that: the word should match the status one to one. The other option, `FAIL (panic)`, prints one status as two words, which will confuse people later.
>
> ## P3: Exit code
> The exit code is 1 if any test is `failed` or `panicked`. Do not add a separate exit code. Pytest has six exit codes and nobody remembers them. CI tools that need the category read the NDJSON.
>
> ## P4: test.failing
> A panic counts as "expected red". The record is `status:"passed"`, `expected_fail:true`, which is what the runtime does today. Put this sentence in §8.10.6: "red means `failed` or `panicked`."
>
> **Reason:** A known bug most often shows up as `unwrap` on `None`. If a panic did not count, users could not mark the most common known bug as expected to fail. That is a trap, and people would file an issue about it every week. Pytest's `xfail` accepts any exception by default. This adds no status and no cause, so it is consistent with the Q3 vote.
>
> ## P5: for_each
> - A panic inside one case marks the parent test `panicked`. There are no per-case records yet (§8.10.2 says so).
> - The duplicate-label panic is also `panicked`. That is the right category, because the test itself is broken.
> - If one case fails and a different case panics, the parent is `panicked`. The rule is simple: "panicked outranks failed."
> - The per-case `cases[]` records stay with their own ticket. When they land, each case uses the same four-status enum.
>
> ## P6: prop_check (only the minimum here)
> - A panic in a property escapes as `panicked` without shrinking. That is the premise the 6-0 `?` vote relied on, so this contradicts no prior vote.
> - The record must still carry the suite `seed`, so `--seed` reproduces the panic. Without the seed, a panicking property cannot be debugged.
> - Out of scope: whether prop_check should catch panics and shrink them, as Hypothesis and fast-check do. My lean is yes, eventually, but it is a UX change that needs its own ticket.
>
> ## P7: Cleanup panics
> No change. E0824 still applies. A cleanup panic during a catchable unwind is a `warning` on the original record. A cleanup panic after a passing `assert_panics` is a separate `panicked` record, per the DevOps refinement.
>
> ## Out of scope
> - Signal crashes (SIGSEGV). Record this as a limit: a signal crash ends the binary and produces no `panicked` record. Handling it is a future ticket.
> - 57n5xh (a test file that does not build).
>
> ## Prior votes
> This proposal contradicts none. The only thing it overrides is zs3w3y's implementer choice, and that was a bug ticket, not a vote. The continue-on-panic behavior zs3w3y locked in stays as it is.

##### PLT

> # PLT proposal on tfxxwc: a panicked test gets `status: "panicked"`
>
> ## Core position
>
> The spec is sound as written. The runtime is what breaks the rule. §8.10 defines the test outcome as a closed sum `passed | failed | panicked | skipped`, and `cause` exists only on `failed`. zs3w3y emits `status:"failed", cause:"panic"`, which puts a value outside the closed `cause` enum and leaves the `panicked` constructor with no inhabitants. zs3w3y was a bug ticket and not a vote, so no prior decision protects its record shape. What it fixed stays in force: the runner survives a panic and goes on to the next test. The code should change to match the spec. The spec should not grow to match the code.
>
> The principle is that each constructor gets its own payload and no two constructors share one. `cause` refines `failed` only, so a panic must not appear as a `cause`.
>
> ## P1: The panicked record
>
> ```json
> { "name": "parses empty header",
>   "status": "panicked",
>   "panic": { "message": "unwrap called on None",
>              "span": {"file": "src/hdr.bl", "line": 41, "col": 17} },
>   "duration_ms": 3 }
> ```
>
> - No `cause`. §8.10 already says this.
> - No `error` object. `error` belongs to `propagated_error`, so reusing it for panics mixes two constructors.
> - `panic.span` is optional. It is present only when the runtime knows where the panic fired. When it does not, the record leaves `span` out. It must never emit `line:0`.
> - In human output, the status word is `PANIC`, not `FAIL`.
>
> ## P2: Summary counts and exit code
>
> - `summary` gets `panicked` and `skipped` keys. The invariant is `total = passed + failed + panicked + skipped`, and the spec should state it as normative.
> - A panicked test is a suite failure. The exit code is nonzero when `failed + panicked > 0`.
> - The human summary reads `N passed, M failed, P panicked[, K skipped] (of T)`.
> - Fix the §8.10 example to include every key.
>
> ## P3: `test.failing`
>
> "Red" means any outcome other than pass, so it covers `failed` and `panicked`. A panicking `test.failing` therefore gives `status:"passed"` and `expected_fail:true`, which matches the runtime today. This is the useful case in practice: a known bug often shows up as an unwrap-on-None panic.
>
> The fact must not be lost, though. Add an optional field `xfail_observed: "failed" | "panicked"`. It is a new field, not a new status or `cause`, so it stays inside the Q3 (4-2) vote.
>
> ## P4: `prop_check`
>
> A property closure is a function `Input -> Result[(), TestError]`, and a panic in it is a divergent (non-returning) result. Panics can be caught (§4.6.3), so a panic on one input is an observable falsification. The runner must catch it for each case, shrink on it, and report `status:"panicked"` with `seed`, `shrunk_input` and `reproduce`.
>
> This does not reverse vote 3. γ is still wrong: `.unwrap()` would label a falsified property as a broken test. Under this rule it keeps shrinking, but it keeps the wrong category. The vote holds, and its reason becomes more precise.
>
> ## P5: `for_each`
>
> - Each entry in `cases[]` uses the same four-status sum, so a case can be `panicked` with a `panic` object.
> - The runner continues to the next case after a panic.
> - The parent status is the join over the order `passed < skipped < failed < panicked`, where "broken" wins. This gives one algebraic rule, and the same join defines how a test aggregates its sub-outcomes anywhere else.
>
> ## P6: Secondary panics
>
> - E0824 stays as it is. A cleanup panic during a catchable unwind is a `warning` on the record and does not change the primary status.
> - Vote 4's "separate failure record" for an `exit(false)` panic during an `assert_panics` unwind breaks the one-record-per-test rule. The DevOps seat should confirm the shape. I propose that the test's single record becomes `status:"panicked"`, which keeps the intent (the test is broken) without a second record under the same name.
>
> ## Out of scope
>
> - A C-level signal (SIGSEGV) is not a Blink panic. The runner cannot write a record for it. The file driver reports the binary's death, which falls with 57n5xh.
> - There is a spec bug next to this gap. §8.10.6 lists `status == "passed" && expected_fail` as "unexpected pass", but the example beside it shows an unexpected pass as `status:"failed"`. It should read `status == "failed" && expected_fail`. File this as a separate ticket.
>
> ## Tradeoffs
>
> **For:**
> - The enums really are closed.
> - A consumer can match on `status` alone and cover every case. A reserved constructor with no inhabitants is a trap for consumers.
> - The DevOps requirement from Testing Q2 (5-0), which separates "found a bug" from "test broken", is met at last.
>
> **Against:**
> - The human output and summary change, so the assertions in `tests/test_runner_panic_continues_zs3w3y.bl` must be updated (updated, not deleted).
> - `blink test` only reads exit codes, so it needs no change. Any tool that parses the JSON and relied on `cause:"panic"` will break, but the spec never allowed that value.
>
> ## Cross-language note
>
> - Rust libtest folds panics into "failed". That is exactly the loss of information vote Q2 rejected.
> - pytest separates `failed` from `error` in the same way this proposal separates `failed` from `panicked`.
> - Hypothesis and QuickCheck treat an exception in a property as a falsification and shrink on it, which supports P4.
> - pytest's `xfail(raises=...)` records what kind of red it saw, which supports `xfail_observed` in P3.
>
> ## Votes touched
>
> - No prior vote is contradicted.
> - P3 adds a field inside Q3.
> - P4 makes the reason for vote 3 more precise without reversing it.
> - P6 asks the DevOps seat to confirm the shape of the vote-4 refinement.

##### DevOps

> **DevOps/Tooling panelist: Phase A proposal for tfxxwc**
>
> The spec already decides the main question. §8.10 says `panicked` is a live status with no `cause`, and the prior votes (Q2, Q3, prop_check γ, assert_panics) all assume it. The runtime's `status:"failed", cause:"panic"` is a bug in the implementation, not a design to reconcile: it puts a third value into a closed enum. Any consumer that validates the enums strictly (a generated TS union, a JSON Schema, a Rust `enum` with serde) rejects the record today. No proposal below contradicts a prior vote.
>
> **P1: shape of a `panicked` record.** An unexpected panic that leaves a test body gives `status:"panicked"` with no `cause`. The record carries a `panic` object with `message` and, when the runtime knows where the panic fired, a `span`. It never emits `line:0` as a placeholder: a missing span means "unknown", and a zero sends editors and GitHub annotations to a line that does not exist. E0824 cleanup warnings go in the same `warnings` array as they do for failed records.
> ```json
> {"name": "parse header", "status": "panicked", "duration_ms": 3,
>  "panic": {"message": "unwrap called on None",
>            "span": {"file": "src/hdr_test.bl", "line": 14, "col": 22}},
>  "warnings": []}
> ```
> Why this shape: CI can tell "test found a bug" from "test is broken" by one key, which is what Q2 required. Cost: every consumer handles four statuses, but the spec already promised four.
>
> **P2: summary counts.** `summary` always carries all four counters, zeros included, and `total = passed + failed + panicked + skipped` is a normative invariant:
> ```json
> "summary": {"total": 14, "passed": 11, "failed": 1, "panicked": 1, "skipped": 1, "duration_ms": 340}
> ```
> A key that is sometimes missing is the classic dashboard bug: someone writes `summary.panicked ?? 0` in one place and forgets it in another. The §8.10 example gets updated to match.
>
> **P3: exit code.** The test binary and `blink test` exit 1 when `failed + panicked > 0`, and 0 otherwise. I do not add a separate exit code for panics. The JSON carries the categorization, and shell consumers only need red or green (Go, pytest and cargo all work this way). A file that did not build stays with 57n5xh.
>
> **P4: human output.**
> ```
> test parse header ... PANIC
>   panicked at src/hdr_test.bl:14:22: unwrap called on None
> 3 passed, 1 failed, 1 panicked, 1 skipped (of 6)
> ```
> `PANIC` has the same width as `FAIL`/`PASS`/`SKIP`, and the summary line omits zero counts as it does today. tests/test_runner_panic_continues_zs3w3y.bl must have its assertions updated (not deleted) from `FAIL`/`1 failed` to `PANIC`/`1 panicked`. zs3w3y's real fix, continue-after-panic, stays as it is.
>
> **P5: test.failing.** A panic counts as "expected red", which is what the runtime does today: `status:"passed"`, `expected_fail:true`. The record still carries the `panic` object, so a dashboard can see how the test was red. This adds no status and no `cause`, so Q3 holds. pytest `xfail` works the same way: any exception is an expected failure unless the author narrows it with `raises=`. A narrowing option like that is out of scope here, for a later ticket.
>
> **P6: prop_check.** A panic inside a property closure gives `status:"panicked"`, and the runner does not shrink it. This is the normative form of the premise the γ vote relied on: shrinking runs only on assertion or `Err`. The record still carries `seed` and `reproduce`, with the unshrunk input as `input`, because a panic you cannot reproduce is the worst outcome CI can have. Tradeoff: Hypothesis and proptest shrink on panics too, so users coming from them lose some convenience. In exchange, the "use `?`, not `.unwrap()`" guidance the γ vote gave has a visible reason behind it.
>
> **P7: for_each.** A case that panics records `status:"panicked"` in `cases[]` with its own `panic` object, and the remaining cases still run (continue-after-panic, as in zs3w3y). The parent status is the worst case status, in the order `panicked > failed > passed`, and the parent's summary counts once, by that status. "Harness is broken" wins over "found a bug" because it makes the other results in that test less trustworthy.
>
> **P8: out of scope, but please file follow-up tickets.**
> (a) A signal crash (SIGSEGV) kills the binary, and today the test that was running produces no record. The `blink test` driver should write a `panicked` record for it, with `panic.message:"process terminated by signal 11"`. This belongs with 57n5xh or a new ticket.
> (b) Publish the §8.10 record shape as a JSON Schema and run a conformance test against the runner's output. The only reason `cause:"panic"` got into the runtime is that nothing checks the closed enums by machine.
>
> **Cross-language note.** JUnit XML already separates `<failure>` (an assertion) from `<error>` (an unexpected exception), and Jenkins, GitLab and CircleCI all show the two differently. Blink's `failed` maps to `<failure>` and `panicked` to `<error>`, so a JUnit exporter needs no guessing. Go's test2json and Rust's libtest merge the two into one status, and their CI users end up searching the output for `panicked at` to tell them apart. That is the result Q2 voted against.

##### AI/ML

> # AI/ML panelist: Phase A proposal (tfxxwc)
>
> **Summary position:** the spec stays as written. `panicked` is a live top-level status, and `cause:"panic"` is an off-enum runtime bug that must go. zs3w3y was a bug ticket, not a vote. The part it got right (a panic does not kill the binary) stays. The part it chose without a vote (the record shape) does not. This contradicts no prior vote. Votes 1, 3 and 4 already assume `panicked` is emitted.
>
> ## P1. Record shape of an unexpected panic
>
> **Rule:** a panic that leaves a test body gives `status:"panicked"` with no `cause` field (§8.10 already says this). The record carries:
> - `message`: the full panic text.
> - `span` / `line` / `col`: where the panic fired. The runtime knows this, because the panic text already contains it. The record must not use `line:0`.
> - No `error` object. That object belongs to `propagated_error`.
>
> ```json
> {"type":"test","name":"parse empty","status":"panicked","message":"unwrap called on None","file":"tests/test_p.bl","line":12,"col":9,"duration_ms":1}
> ```
>
> **Why (fix loop):** an agent branches on one field. Today it must read `status:"failed"`, then `cause`, then find `"panic"`, a value the spec says cannot exist. An agent trained on the spec will write `match cause { "assertion" -> ..., "propagated_error" -> ... }` and crash or fall through on the real output. A spec/runtime mismatch in a closed enum does the most harm to generability, because an LLM trusts closed enums completely. `line:0` also breaks the most common agent action: "open file at line". The location must be a real one.
>
> ## P2. Summary counts
>
> **Rule:** the JSON `summary` always has all four count keys, even at zero: `total, passed, failed, panicked, skipped, duration_ms`. The spec states this invariant: `total == passed + failed + panicked + skipped`. Fix the §8.10 example to match.
>
> **Why:** keys that are sometimes present add a decision point for the model. An invariant it can check lets an agent confirm that it parsed the output correctly.
>
> ## P3. Exit code
>
> **Rule:** the exit code is non-zero if `failed + panicked > 0`. Skipped tests do not change it. `blink test` keeps counting by exit code.
>
> **Why:** there is one rule to learn, and it matches cargo, pytest and go.
>
> ## P4. Human output
>
> **Rule:** the result word is `PANIC` (not `FAIL`), followed by the panic message and its location. The summary line is `N passed, M failed, P panicked[, K skipped] (of T)`. Show `panicked` only when P > 0, the same way `skipped` works today.
>
> Update the assertions in tests/test_runner_panic_continues_zs3w3y.bl to match. Do not delete them.
>
> **Why:** agents read human output as often as JSON. The word must match the status token exactly (`panicked` ↔ `PANIC`) so there is no second vocabulary to learn.
>
> ## P5. test.failing
>
> **Rule:** a panic counts as expected red, which keeps today's runtime behavior. The record stays `status:"passed"`, `expected_fail:true`, and also carries `message` with the panic text.
>
> **Why:** people mark known bugs with `test.failing`, and a known bug often shows up as an unwrap panic. If a panic did not count, it would be the most common reason an agent's "mark it failing" edit does not work. The message is kept so that an agent can see that the failure mode changed (for example, from an assert to a panic). No new status or cause is added, so this is consistent with vote 2 (4-2).
>
> ## P6. prop_check
>
> **Rule:** a panic inside the property ends the check at once. There is no shrinking. The record is `status:"panicked"` and carries the `seed` and the generated input that caused it, so the failure can be reproduced.
>
> **Why:** vote 3 already rests on "panic ⇒ panicked, no shrink UX". The spec should state it so the rejected γ premise is written down. Carrying the seed means a panic can still be reproduced, and that is the step an agent's fix loop needs most.
>
> **Cross-language:** proptest and Hypothesis do shrink on panics/exceptions. We do not, by design (`?` is the Blink path), and the spec should say so.
>
> ## P7. for_each
>
> **Rule:**
> - A case that panics records `status:"panicked"` in `cases[]` with the same fields as P1.
> - The remaining cases still run.
> - The parent test's status is the worst case status, in the order `panicked > failed > passed`. `skipped` applies only if every case is skipped.
>
> **Why:** a single worst-case ordering is one rule, used the same way everywhere.
>
> ## Out of scope
>
> - A C-level signal crash (SIGSEGV) is a runtime-integrity matter. It needs its own ticket (a synthetic record from the driver).
> - 57n5xh (a test file that does not build).
>
> ## Token/decision count
>
> This adds no status, no cause and no field names beyond those §8.10 already uses (`message`, `line`, `seed`). The net change for a learner is minus one: the undocumented `cause:"panic"` goes away.

##### Minimalism

> ## Minimalism panelist, Phase A proposal: tfxxwc (panicked status vs closed enums)
>
> **My view.** The spec is already right and the runtime is wrong. §8.10 closes `status` over four values and `cause` over two. Five prior votes (Q2, Q3, prop_check `?`, assert_panics, E0824) rely on `panicked` being a real status. zs3w3y was a bug fix, and its record shape was the implementer's choice with no vote behind it. That choice put a value outside the closed enum (`cause:"panic"`) and left a documented status that the runtime never emits. The fix that adds the least is to make the runtime emit the status the spec already defines. It needs no new status, no new cause and no new field names.
>
> ### Proposal M1 (primary): emit `panicked` as the spec says
>
> 1. A panic that escapes a test body gives `status:"panicked"` with no `cause` (§8.10 already says this). Fields: `name`, `status`, `duration_ms`, `message` (the full panic text), and `span` only when the runtime knows the panic site. The record does not carry `line:0` or an empty `error` object. A field with a fake value is worse than no field.
>    ```json
>    {"name":"parse empty","status":"panicked","duration_ms":1,
>     "message":"unwrap called on None at src/p.bl:12:9"}
>    ```
> 2. **Summary: one count per status.** `total` is the sum of `passed + failed + panicked + skipped`. Every key is always present, even at 0. This is one rule, not four. It also fixes the §8.10 example, which is missing `skipped` today.
>    ```json
>    "summary":{"total":14,"passed":11,"failed":1,"panicked":1,"skipped":1,"duration_ms":340}
>    ```
> 3. **Exit code:** non-zero if `failed + panicked > 0`. The code stays binary. A separate code for "panicked" would add surface that the records already cover.
> 4. **Human output:** the word shown for a test is its status: `PASS | FAIL | PANIC | SKIP`. The summary line lists only the non-zero counts: `11 passed, 1 failed, 1 panicked, 1 skipped (of 14)`. The test `tests/test_runner_panic_continues_zs3w3y.bl` gets its assertions updated, not deleted.
> 5. **test.failing:** a panic counts as red. The rule becomes "any outcome other than `passed` is inverted." The runtime already does this, and a known bug often shows up as an `unwrap` panic, so an exception here would be a trap. The record is `status:"passed"`, `expected_fail:true`, as §8.10.6 specifies.
> 6. **prop_check:** a panic inside the property is not a falsification. The runner does not shrink it, and the test reports `panicked`. The γ rejection in vote 3 already assumed this, and this rule makes it normative. Shrinking on a panic would need catch-and-retry machinery for a path the panel has already called "the test itself is broken."
>
> Tradeoffs: this changes one runtime record shape, one human word, and one summary key. It removes one illegal enum value. There is no language change. The cost is a small break for anyone parsing `cause:"panic"`, and that value never had a spec to rely on.
>
> ### Out of scope
>
> - **for_each per-case records.** §8.10.2 says the runner does not emit `cases[]` yet, and a separate bug tracks it. A case that panics is the same as a panic in the parent test: the parent is `panicked`. When case records land, they reuse the same four statuses, so this proposal adds nothing for them.
> - **Signal crashes (SIGSEGV).** They stay uncaught. Catching signals is a separate and much larger feature, and nobody has shown a need for it.
> - **Files that do not build.** Ticket 57n5xh covers this.
>
> ### Rejected alternative M0: remove `panicked` and bless `cause:"panic"`
>
> At first this looks like subtraction, since it drops one status. In practice it adds a third `cause` value and reverses the part of Q3 (4-2) that rejected new cause values. It also breaks the Q2 DevOps requirement (5-0) and the assert_panics and E0824 wording. That is four decisions reopened to save one enum member, so it removes one thing and costs more than it saves. I vote no.
>
> ### Cross-language note
>
> Go reports a panic as a FAIL but prints it differently. Rust's libtest does the same, with no separate state. pytest keeps "error" apart from "failure" for this reason. Blink has already chosen the pytest split, and the gap is only in the implementation. Once a closed enum has a value outside it, it is no longer closed, so I rank this a correctness bug before it is a design question.
>
> **My vote in advance:** M1 yes. M0 no. Scope cuts yes.

#### Phase B — Debate (round 1)

The moderator grouped the six proposals into shared points S1–S6 and variations V1–V7. Each panelist then replied once, verbatim below. All six signalled "stable, ready to vote" after this round.

##### Systems

> # Systems, Phase B round 1
>
> ## Positions
>
> **V1: I change to V1b (`panic: {message, span?}`).** PLT's rule convinced me: each constructor gets its own payload. `propagated_error` already uses an `error` object, so a `panic` object has the same shape. A consumer can then test for one key, and a top-level `message` cannot collide with a later field on another status. The runtime cost is the same, because the emit code writes the same bytes in a different order.
>
> **V2: V2b, carried as the `panic` object.** With V1b, when a `test.failing` record carries a `panic` object, it tells the reader that the test panicked. That makes V2c's `xfail_observed` a second copy of the same fact, and two copies can drift apart. I reject V2c. I reject V2a because it throws away the message, and the message is how a user sees that a known bug changed shape.
>
> **V3: I hold V3a (no shrink, carry `seed`, `input`, `reproduce`).** Here is what the machine does today. `__blink_test_panic_handler` longjmps to the per-test frame, so the property loop does not come back. To shrink, each trial must arm its own catch frame, and after the first panic every later trial runs on whatever the panic left behind: globals that were half changed and cleanups that did not run. An unarmed panic skips those cleanups. A shrink that runs on corrupt state can report a false minimum, and a false minimum is worse than a large honest input. I would not object to a separate ticket that asks for panic-shrink once a trial can run with its state isolated (web's deferral), but not in this ticket.
>
> **V4: I hold V4b (record the case, stop the loop).** The runtime stops `for_each` after an assertion failure today (the `__blink_test_is_failed` poll) because the state may be corrupt. A panic corrupts more than an assertion does, because it skips cleanups. V4a would continue after a panic but stop after an assertion failure, and that order is backwards. To continue after a panic, the runtime also needs a catch frame for each case. If the panel wants "run every case", the rule must cover assertion failures too, and it belongs in its own ticket.
>
> **Parent precedence:** `panicked > failed > passed`. The parent is `skipped` only when every case is skipped (AI/ML's refinement, which I adopt). I reject PLT's `skipped` above `passed`: one skipped case among passing cases would make the whole test read as skipped, and that hides real coverage.
>
> **V5: V5b (one record for each test, which becomes `panicked`).** Consumers key records by `name`. Two records with the same name give JUnit exporters and dashboards duplicate-key bugs. I say plainly that this reads the vote-4 DevOps refinement ("separate failure record") by its intent, which is to mark the test as broken, and not by its letter. The DevOps seat should confirm. The E0824 rule stays: a cleanup panic after a failure becomes a `warning`, and the first escape decides the status.
>
> **V6: `passed` and `failed` always show. `panicked` and `skipped` show only when above 0.** This is the rule the runtime already uses for `skipped`. Min's "non-zero only" rule is also acceptable. Either way, the JSON `summary` always carries every key (S2).
>
> ## Argument for the others
>
> For V3 and V4, the cheap-looking option has a cost you cannot see: when a trial or case resumes after a panic, it runs on state that nothing guarantees. The fact that setjmp is cheap does not make that state sound. Keep this ticket to reporting only. Put any change to how execution resumes after a panic in its own ticket, and make that change cover assertion failures the same way.
>
> ## Status
>
> Stable, ready to vote.

##### Web/Scripting

> # Web/Scripting, Phase B round 1 (tfxxwc)
>
> ## V1: payload location — V1a (top-level `message` + optional `span` object). No change.
> Argument: §8.10's existing `failed` records put `span` at top level (lines 647-662). A consumer's "jump to location" code is `rec.span` for every status today. V1b makes it `rec.span ?? rec.panic?.span` — one special case per consumer, forever, and exactly the kind of thing that generates Stack Overflow questions. The `error` object is nested only because it has two fields that belong to the error value; a panic has one (`message`). I also reject AI/ML's flat `file/line/col`: it is a second location spelling next to `span`.
>
> ## V2: test.failing payload — CHANGED to V2b (carry `message`).
> sys/aiml/devops convinced me: a dev who sees an xfail test "still passing" wants to know it is now red for a different reason. Cost is one field that already exists. Under V1a it is just top-level `message` on the passed record. I reject V2c (`xfail_observed`): a new field name for something `message` already tells the reader.
>
> ## V3: prop_check — V3a (no shrink; carry `seed`, unshrunk `input`, `reproduce`).
> I adopt sys's argument over my own "lean yes": after a longjmp, heap state is unknown, so shrink trials on top of it give answers you cannot trust. A wrong shrunk input is worse UX than no shrunk input. Carrying `input` + `reproduce` gives the 90% of what shrinking gives. Against V3b: it reopens the reasoning behind vote 3, and the panel did not ask for that.
>
> ## V4: for_each — CHANGED to V4a (case records `panicked`, remaining cases run).
> The moderator's facts change my view: `cases[]` exists in the runtime today, so "leave it to its own ticket" (my V4c) no longer applies. Against V4b (stop the loop): §8.10.2 line 835 says, normatively, "The body is called for every case — failures do not short-circuit." The poll that stops the loop breaks that sentence, and it is the whole reason `for_each` exists (line 829). A panic must follow the same rule. File the poll as a bug.
> Parent precedence: `panicked > failed > passed`; `skipped` only when every case is skipped (aiml). Against PLT's join: `passed < skipped` makes one skipped case turn a mostly-green test into `skipped`, which no JS/Python user expects (Jest and pytest both report the parent as passed).
>
> ## V5: exit(false) panic after a passing assert_panics — CHANGED to V5b (single record, `status:"panicked"`).
> This departs from the vote-4 DevOps refinement's wording ("a SEPARATE record"), and I say so explicitly. Reason: two records with the same `name` break every dashboard keyed by test name and break `total = passed + failed + panicked + skipped`. The intent of the refinement — the test is reported as broken — is kept. It also agrees with sys's "first escape wins": the expected panic was consumed, so the cleanup panic is the first escape. DevOps should confirm.
>
> ## V6: human summary — show `panicked` only when > 0 (the `skipped` rule). No change.
> Against min's "only non-zero": `passed` and `failed` always show today, and `0 failed` is the line people look for. Removing it changes output for every user to fix a line only panicking suites see.
>
> ## Stable, ready to vote.

##### PLT

> # PLT, Phase B round 1
>
> ## Positions
>
> **V1: V1a (changed from V1b).** Top-level `message` plus an optional `span`. The reason is that a `failed` record already carries a top-level `span`, and there it means "where the outcome fired". When each field has one meaning across every constructor, the sum stays clean without nesting. I hold one condition: `span` must mean the same thing on every status. I reject AI/ML's flat `file`/`line`/`col`. It gives a second encoding of the same location, when `span` already exists.
>
> **V2: V2c first, then V2a, then V2b.** Under V2b, a `passed`+`expected_fail` record carries `message`. But what does an xfail that went red through an assertion carry? It also has a message. So the presence of `message` cannot tell the two cases apart, and a consumer has to guess the discriminant from the shape of the payload. `xfail_observed: "failed" | "panicked"` is the discriminant itself. I can accept V2b only if it also includes that field. If the choice is V2b alone versus V2a, I take V2a: it is honest about what it leaves out.
>
> **V3: I accept V3a for now, with a change to the wording.** Sys's soundness argument (unknown state after a longjmp) holds in the same way for assertion failures. Those also longjmp to the per-test frame (runtime_test.h:135/179/204), and the spec already requires the runner to shrink on them. So "a panic leaves state we cannot trust" is not a principled line between the two. The actual reason is that the implementation does not do it yet. The spec should say "the runner does not shrink on a panic in this version", not declare that a panic is not a falsification. The second wording closes off Hypothesis-style shrinking for good, on a premise that is false. The record must carry `seed`, the unshrunk `input` and `reproduce` (sys, devops, aiml, and web on `seed`).
>
> **V4: V4a.** §8.10.2 gives `for_each` its reason to exist: it "reports each failure independently", and it names "the first failure short-circuits the rest" as the problem it solves. The runtime's `__blink_test_is_failed` poll that stops the loop conflicts with the spec, so V4b would bring that runtime drift into the spec. Continuing must apply to `failed` and `panicked` cases alike, because the loop should not treat two outcomes differently when neither one damages the next case. V4c defers what the runtime already emits (`cases[]` exists; see the moderator's fact notes).
>
> **Parent precedence: I concede to AI/ML.** My join `passed < skipped < ...` was wrong: one skipped case among passes would turn the parent into `skipped`. The correct rule is `panicked > failed > passed`, with `skipped` only when every case is skipped. It is still a single total order and the same rule everywhere.
>
> **V5: V5b.** The one-record-per-test rule is structural: the test name is the key. A second record under the same name breaks every consumer that indexes by name. I also adopt sys's "first escape wins" rule. It agrees with E0824, where the first outcome is the result and any later panic is a `warning`.
>
> **V6: Show `panicked` only when it is above 0**, the same rule as for `skipped`. One rule for every optional count.
>
> ## Arguments for the panel
>
> 1. On V3 in particular: do not write a false premise into the spec. "Panic is not falsification" is not true (Hypothesis, proptest and QuickCheck all treat it as one), and it does not follow from vote 3. Vote 3 rejected γ because it puts a falsification in the wrong category. That holds whether or not we shrink. Write the limit as a limit of the current version.
> 2. On V2: a bare optional `message` field on `passed` records makes the record shape depend on history (how the test went red) with no tag. Every closed-enum argument this panel accepted (Q3, the `?` vote) says to tag it.
> 3. I support devops's follow-up for a JSON Schema conformance test. `cause:"panic"` got into the runtime only because no one checked the enum by machine.
>
> ## Status
>
> Stable, ready to vote.

##### DevOps

> # DevOps/Tooling: Phase B round 1 (tfxxwc)
>
> S1–S6: agree.
>
> **V1: I change to V1a (top-level `message` + optional `span`).** The reason is a tooling one: every `failed` record already carries `span` at top level. With V1a, one path (`.span`) turns every red record into a GitHub or GitLab annotation, and nobody needs to branch on status to find the location. `status` already tells a consumer which payload it has, so the nested `panic` object only adds a second path. I reject AI/ML's flat `file`/`line`/`col`: it would be a second shape for location next to the `span` object that every other record uses.
>
> **V2: V2c plus V2b.** An inverted panic keeps `message`/`span` and adds `xfail_observed: "panicked"` (or `"failed"`). A dashboard wants the enum, not a text search: "this known bug used to fail an assert and now crashes" is a real drift signal. The field is optional and inside Q3: no new status, no new cause. If the panel wants only one of the two, I take V2c.
>
> **V3: V3a.** No shrink on a panic. The record carries `seed`, the unshrunk `input` and `reproduce`, and all three are normative, not optional. Systems' argument decides it for me: after a longjmp the program state is not known, so shrink trials run on top of it give answers you cannot trust. A panic you cannot reproduce is the worst outcome CI can have, which is why the seed is required. I do not object to web's follow-up ticket.
>
> **V4: I change to V4b (the loop stops).** The runner already stops `for_each` at the first failed case. If it continued after a panic but stopped after an assertion, the less trustworthy outcome would get the more generous treatment. That makes no sense. The panicking case gets a `panicked` entry in `cases[]` with `message`/`span`. Cases that did not run get no entry. Parent precedence: `panicked > failed > passed`, and `skipped` only when every case is skipped. PLT's join gives the same result, and I accept either wording. I reject V4c: the runtime already emits `cases[]`, so the §8.10.2 line 853 text is out of date and should be fixed in the same edit.
>
> **V5: V5b. As the DevOps seat, I withdraw the vote-4 "separate record" refinement.** One record per test is the invariant every consumer keys on. A JUnit `<testcase>` is unique by name, dashboards de-duplicate by name, and S2's `total` counts tests. A second record under the same name breaks all three. The test's single record becomes `status:"panicked"` with the cleanup panic's `message`/`span`. This does not violate systems' rule that "the first escape wins": the armed `assert_panics` had consumed its panic, so the test had not failed before the cleanup panic. If `assert_panics` had already failed (E0831/E0832), E0824 applies unchanged: the test stays `failed` and the cleanup panic is a `warning`. The spec should state both cases. This amends a DevOps refinement, not the core vote, and I say so explicitly.
>
> **V6: show `panicked` only when it is above 0, the same rule as `skipped`.** I reject min's "non-zero counts only" because it would also drop `0 failed`. Today's line always shows `passed` and `failed`, and CI log scrapers and humans look for that fixed shape. Changing it is churn with no benefit.
>
> **V7:** Please file the JSON Schema + conformance test ticket. Without a machine check of the closed enums, the next `cause:"panic"` will get in the same way. I also back PLT's §8.10.6 unexpected-pass text fix as a separate ticket.
>
> **Stable, ready to vote.**

##### AI/ML

> # AI/ML panelist: Phase B round 1 (tfxxwc)
>
> ## V1: payload location. **V1a (changed view).**
> I drop my flat `file`/`line`/`col` fields. The §8.10 `failed` records already put location in a top-level `span` object, so a panic should use it too. The rule an agent learns is then "location of any non-pass record = `span`", one path for every status. V1b moves `span` to `panic.span`, which gives location two paths that depend on status. That is an extra decision point in every fix loop, for no gain. If V1b wins, I ask for an amendment: `span` stays top-level and only `message` goes inside `panic`.
>
> ## V2: test.failing payload. **V2b** (the panic message). **V2c is my second choice.**
> V2a loses the data an agent needs to see that a known bug changed shape, for example from an assert to a panic. That drift is what makes an agent look again. V2c is a closed enum, which models match well, but it adds a field name that V2b does not need. I rank them V2b > V2c > V2a.
>
> ## V3: prop_check. **V3a**, with `seed`, unshrunk `input` and `reproduce`.
> Sys's argument settles it for me. After a longjmp, cleanups were skipped and state is unknown. Shrink trials that run on that state give a "minimal" input the agent cannot trust. An agent will act on a wrong shrunk input with full confidence, which is worse than having no shrunk input. PLT's point that Hypothesis shrinks exceptions is true, but Python unwinds cleanly and our unwind does not. Web's "later ticket" is fine with me.
>
> ## V4: for_each. **V4b (changed view).**
> I proposed "continue after a panic". The runtime stops the loop after the first `failed` case. If a panic continued and a failure stopped, the model would have two loop rules, one for each kind of red. For loop control a panic must act like a failure: the loop stops. Whether every kind of red should continue is a separate question. It changes `failed` too, and it needs its own ticket. For precedence, I accept either `panicked > failed > passed` or PLT's join. They agree on every case that can happen.
>
> ## V5: exit(false) panic during an armed assert_panics unwind. **V5b.**
> Keep one record per test. Agents and tools index results by test `name`, and two records with the same name break that silently: the last one wins in a dict. I also accept sys's "first escape wins, never upgrade failed → panicked". This refines the vote-4 DevOps wording ("separate record"), so the panel must say so explicitly, and devops should confirm it.
>
> ## V6: human summary. **Show `panicked` only when it is above 0**, the same rule as `skipped`.
> Min's "non-zero only" would also hide `0 failed`. That changes the line that tests/test_runner_panic_continues_zs3w3y.bl and users' log greps already match, and this ticket does not need that change.
>
> ## To the panel
> - S1–S6 are the substance, and all six of us agree on them. Please do not let V2–V6 hold up the vote on S1–S6. The runtime's off-enum `cause:"panic"` teaches every model that reads Blink output that closed enums are not closed.
> - I support devops's V7 follow-up: a JSON Schema plus a conformance test. Only a machine check stops this kind of drift. Models trust the spec, so the runtime must be checked against it.
>
> **Stable, ready to vote.**

##### Minimalism

> ## Minimalism, Phase B round 1 (tfxxwc)
>
> Test I use for every choice: **does the rule reuse a field name or behavior that already exists?** If it does, it costs nothing. If it adds a new name or new machinery, it has to earn its place.
>
> **V1: V1a (top-level `message`, optional `span` object).**
> §8.10 records already carry `span` as an object, so flat `file`/`line`/`col` (AI/ML) would give one location two spellings. A nested `panic: {}` object (V1b) adds a new field name to say what `status:"panicked"` already says. The status is the discriminator, so a wrapper repeats it. I vote against both.
>
> **V2: I change to V2b, the top-level `message` only.**
> In Phase A I said "nothing more". I change my view because `message` is not a new name: it is the field a panicked record already carries. Keeping it costs zero new surface and shows a change in failure mode, which is the AI/ML argument, and it convinced me. I vote against V2c: `xfail_observed` is a new field with a new two-value enum, when a panic message can already be read from `message`. If DevOps puts the message in a `panic` object, that falls with V1b.
>
> **V3: V3a, no shrinking, with `seed` and `reproduce` only.**
> Both field names already exist for property failures. The seed recreates the input deterministically, so an extra "unshrunk input" field is only a convenience, and a new name. I would accept one if the panel insists, but it must not be called `shrunk_input`, because nothing was shrunk. I vote against V3b. Catching panics for each case and retrying the shrink is new runtime machinery for a path the panel already calls "the test itself is broken". Vote 3's γ rejection assumed a panic does not shrink. I oppose even a deferred ticket unless a user asks for it.
>
> **V4: I change from V4c to V4b.**
> The moderator's facts show the runtime already emits `cases[]` and already stops the loop at the first failure. So V4b is what exists today, with only the status word corrected. V4a ("remaining cases still run") adds new behavior: it changes the existing `__blink_test_is_failed` poll for panics only, so a panic and an assert failure would behave differently in the same loop. That is an asymmetry with no user asking for it.
> Parent precedence: when the loop stops at the first escape, only one non-passing case can exist, so a precedence lattice is not needed. The rule is "the parent status is the status of the first escape". I agree with sys: the first escape wins, and the runner never upgrades a failed test to panicked. A panic from a duplicate label is a panic, so it records `panicked`. That needs no special rule.
> Separately, the stale text at §8.10.2 line 853 should be fixed in the same edit.
>
> **V5: V5b, one record per test.**
> This amends the DevOps refinement to vote 4, so I justify it. A second, top-level record for the same test breaks the S2 invariant that all six of us just agreed to: `total` must count tests, and a phantom record makes `total` wrong or needs a special case. It also breaks one test = one record, which every consumer relies on. V5b keeps DevOps's actual goal: the cleanup panic is not swallowed and it shows as `panicked`. It is consistent with E0824. There, a cleanup panic after a real failure is a warning. Here, the expected panic was consumed and nothing else failed, so the cleanup panic is the first escape.
>
> **V6: I concede to the majority: show `panicked` only when it is above 0, as `skipped` works today.**
> My "show only non-zero counts" would also hide `passed`/`failed`, which changes existing output for no gain. It is not worth a vote.
>
> **Argument for the panel:** every variant that adds a name (`panic` wrapper, `xfail_observed`, catch-and-shrink, continue-after-panic) buys a small convenience with permanent surface in a closed-enum record format. The minority positions on V1, V2c, V3b and V4a all add; the others reuse. Pick the ones that reuse.
>
> **Stable, ready to vote.**

#### Phase C — Final vote

The ballot put these questions to the panel:

- **Q1.** Shared points S1–S6 as one bundle: a panic gives `status:"panicked"` with no `cause`, carries the message and a location only when known, never `line:0`, no `error` object (S1); the summary always carries all six keys and `total = passed + failed + panicked + skipped` (S2); exit non-zero when `failed + panicked > 0` (S3); the human word is `PANIC` and the regression test's assertions are updated, not deleted (S4); a panic in `test.failing` is expected red (S5); signal crashes and 57n5xh are out of scope (S6).
- **Q2.** V1a top-level `message` + optional `span`, or V1b nested `panic: {message, span?}`.
- **Q3.** What a panicking `test.failing` record carries: V2a nothing, V2b the message, V2c `xfail_observed`, or V2b+V2c.
- **Q4.** `prop_check` panic: V3a no shrink or V3b shrink; carry the unshrunk input; wording W1 ("in this version") or W2 ("a panic is not a falsification").
- **Q5.** `for_each` panic: V4a record `panicked`, keep running, or V4b record `panicked`, stop.
- **Q6.** Cleanup panic during an armed `assert_panics` unwind: V5a separate `panicked` record, or V5b the one record becomes `panicked`.
- **Q7.** Human summary: show `panicked` only when above 0, or show only non-zero counts.
- **Q8.** Follow-ups F1–F6.

Tally:

| Q | Result | Tally |
|---|--------|-------|
| Q1 | S1–S6 adopted | 6-0 |
| Q2 | V1a | 5-1 (Systems for V1b) |
| Q3 | tie: V2b (sys, web, min) vs V2b+V2c (plt, devops, aiml) | 3-3 → Phase D |
| Q4 | V3a 6-0; carry unshrunk input 5-1 (Minimalism no); W1 6-0 | see ballots |
| Q5 | V4a | 5-1 (Minimalism for V4b) |
| Q6 | V5b | 6-0 — **voided**, see Phase D (Q6) |
| Q7 | show `panicked` only when above 0 | 6-0 |
| Q8 | F1 6-0; F2 5-1; F3 6-0; F4 4-2; F5 5-1; F6 6-0 | see ballots |

Each ballot, verbatim:

##### Systems

> # Systems ballot, Phase C (tfxxwc)
>
> ## Q1. S1–S6 bundle
> **Vote:** Yes
> **Reasoning:** The spec already defines `panicked`. Only the runtime drifted from it, and the fix is one flag and one branch in the report path. Keeping the summary keys fixed and using one non-zero exit code keeps the runtime cost at zero and gives consumers one schema to parse.
> **Concern:** Tools that already parse `cause:"panic"` break silently unless the change log names the change.
>
> ## Q2. V1
> **Vote:** V1b
> **Reasoning:** Each constructor gets its own payload object, the same as `error` for `propagated_error`. The emit code writes the same bytes in a different order. A consumer tests for one key.
> **Concern:** Consumers can confuse `panic.message` with the `message` on other record kinds unless the spec lists the fields for each status.
>
> ## Q3. V2
> **Vote:** V2b
> **Reasoning:** Under V1b, a `panic` object on the record already tells the reader that the test panicked, so the object is the tag. `xfail_observed` would be a second copy of that fact, and the two copies can drift apart. V2a throws away the message, and the message shows when a known bug changes shape.
> **Concern:** Readers can take the `panic` object on a `passed` record for a failure unless the spec states that `expected_fail:true` qualifies it.
>
> ## Q4. V3
> **Q4a:** V3a
> **Q4b:** Yes
> **Q4c:** W1
> **Reasoning:** Do not shrink in this version, because the runner has no per-trial catch frame. The record must carry `seed` and `reproduce`. It must also carry the unshrunk `input`, because printing the input is cheap and a seed reproduces the input only when the generator and the build are the same. PLT is correct that assertion failures also longjmp and the runner still shrinks on them. My "unknown state" argument is therefore a limit of the implementation, not a principle. For that reason I change to W1 and do not choose W2.
> **Concern:** W1 can stay "this version" forever unless F5 is filed.
>
> ## Q5. V4
> **Vote:** V4a (changed view)
> **Reasoning:** My core position on this ticket is that the spec wins over runtime drift. §8.10.2 says normatively that failures do not short-circuit, and the `__blink_test_is_failed` poll breaks that rule. V4b would write the drift into the spec, so V4a is the only vote consistent with that position. The cost is a setjmp for each case, a few nanoseconds against the case body. `failed` must continue the same way (F6), so the loop has one rule for both kinds of red. I accept the parent precedence: `panicked > failed > passed`, and `skipped` only when every case is skipped.
> **Concern:** If the per-case catch frame lands for panics before F6 lands for failures, the loop has two rules for a time. Land the two changes together.
>
> ## Q6. V5
> **Vote:** V5b
> **Reasoning:** Consumers key records by `name`. One record per test keeps the `total` invariant and keeps JUnit output valid. The DevOps seat has amended its own refinement. The first escape wins: if `assert_panics` already failed, E0824 applies unchanged.
> **Concern:** The spec text must state both cases (the panic was consumed, and `assert_panics` already failed), or implementers will guess.
>
> ## Q7. V6
> **Vote:** Show `panicked` only when above 0
> **Reasoning:** Log scrapers already rely on the fixed `N passed, M failed` prefix. This rule keeps that prefix and follows the existing `skipped` rule.
> **Concern:** A scraper that matches the whole line without anchors can miss the new term.
>
> ## Q8. Follow-ups
> - F1: File. Checking the enums by machine would have caught `cause:"panic"`.
> - F2: File. Today a test that crashes on a signal leaves no record, and CI needs one.
> - F3: File. The rule text contradicts its own example, which is a spec bug.
> - F4: File, low priority. It narrows expected red without a new status.
> - F5: File. It follows from the W1 wording, and it needs per-trial state isolation first.
> - F6: File. The spec requires the fix, and it must land with the Q5 change.

##### Web/Scripting

> # Web/Scripting ballot (tfxxwc)
>
> ## Q1. S1–S6 bundle
> **Vote:** Yes
> **Reasoning:** The spec already promises four statuses and two causes; the runtime's `cause:"panic"` makes the docs lie. A dev who reads §8.10 and then sees real output should find what the docs say. Every S point either removes a surprise or fixes a stale example.
> **Concern:** Tools that already match `cause:"panic"` break without warning; the changelog must name it.
>
> ## Q2. V1
> **Vote:** V1a
> **Reasoning:** `failed` records already put `span` at top level, so "jump to location" stays `rec.span` for every status. V1b adds `rec.panic?.span` as a second path that every consumer must learn. `status` already says which payload it is.
> **Concern:** A later status that needs a multi-field payload may push someone to nest it, and then top-level `message` looks like the odd one out.
>
> ## Q3. V2
> **Vote:** V2b
> **Reasoning:** A dev whose known-bug test is still "passing" wants to see if it is now red for a different reason; the message shows that at a glance. It reuses a field name, so there is nothing new to learn. `xfail_observed` says in a new field what the message text already shows.
> **Concern:** Dashboards that want to count "xfail via panic" must parse text, which PLT correctly flags as an untagged shape.
>
> ## Q4. V3
> **Q4a Vote:** V3a
> **Q4b Vote:** Yes (carry the unshrunk input)
> **Q4c Vote:** W1
> **Reasoning:** Sys's unknown-state argument is enough to not shrink today. But the input itself is the first thing a dev wants to see; "rerun with --seed to find out what broke" is one more step in every debug loop. W1 because Hypothesis and fast-check users expect a panic to be a falsification, and the spec should not rule that out forever on a premise vote 3 never needed.
> **Concern:** If W1 wins with no follow-up ticket, "in this version" stays in the spec forever and reads as a promise we never keep.
>
> ## Q5. V4
> **Vote:** V4a
> **Reasoning:** §8.10.2 says, as a rule, "failures do not short-circuit", and that is the whole reason `for_each` exists. V4b writes the runtime's drift into the spec. I agree with sys/aiml/min that panic and assertion must behave the same, so V4a must be paired with F6 (assertion failures also continue). No objection to the parent precedence.
> **Concern:** V4b will probably win, and then the spec says both "do not short-circuit" and "the loop stops"; that line 835 text must change in the same edit or users get two contradictory rules.
>
> ## Q6. V5
> **Vote:** V5b
> **Reasoning:** One record per test name is what every dashboard, JUnit exporter and `dict` keyed by name assumes. The devops seat withdrew its own refinement, so this is not a re-litigation. The spec should state both cases (assert_panics passed → panicked; assert_panics already failed → E0824 warning), as devops wrote.
> **Concern:** Someone reads the old vote-4 note later and implements two records; DECISIONS.md must record the amendment next to the original.
>
> ## Q7. V6
> **Vote:** Show `panicked` only when above 0 (the `skipped` rule)
> **Reasoning:** `0 failed` is the line people and log scrapers look for; keep `passed`/`failed` fixed. One rule for every optional count.
> **Concern:** Log greps for `failed` alone miss suites that only panic; the exit code covers that.
>
> ## Q8. Follow-up tickets
> - F1: File — only a machine check stops the next off-enum value.
> - F2: File — a test that crashes with no record at all is the worst DX; the driver knows the exit signal.
> - F3: File — a rule that contradicts its own example generates confused bug reports.
> - F4: File — low priority; pytest users will ask for `raises=` the first time a known bug changes shape.
> - F5: File — Hypothesis/fast-check users expect it; tie it to trial-state isolation, as sys said.
> - F6: File — the runtime conflicts with a normative sentence in §8.10.2; fix it for failed and panicked alike.

##### PLT

> # PLT ballot (tfxxwc)
>
> ## Q1. S1–S6 bundle
> **Vote:** Yes
> **Reasoning:** With this bundle the closed enums hold in the runtime. Every constructor of the status sum has records that use it, and `cause` refines only `failed`. The summary invariant `total = passed + failed + panicked + skipped` makes the counts a partition, and a consumer can check that.
> **Concern:** S5 without a tag (see Q3) lets a `passed` record hide how the test went red.
>
> ## Q2. V1
> **Vote:** V1a
> **Reasoning:** `failed` records already carry a top-level `span` that means "where the outcome fired". If `panicked` uses the same field with the same meaning, the record needs no nesting and the sum stays uniform. The condition is that `span` keeps that one meaning on every status.
> **Concern:** A later status could reuse `message` or `span` with a different meaning, and nothing would stop it unless the spec defines each field once for all statuses.
>
> ## Q3. V2
> **Vote:** V2b+V2c
> **Reasoning:** An xfail that goes red through an assertion also has a message. So a bare `message` field cannot tell that case from a panic, and consumers would have to guess the case from the payload. `xfail_observed` is the tag. The message is useful payload once the tag says which case the record is.
> **Concern:** If V2b wins without V2c, the record shape depends on how the test went red, with no field to name it.
>
> ## Q4. V3
> **Q4a vote:** V3a
> **Q4b vote:** Yes
> **Q4c vote:** W1
> **Reasoning:** Assertion failures also longjmp out of the property closure (runtime_test.h), so "state after the jump cannot be trusted" does not separate a panic from an assertion. The real reason is that the implementation does not do it yet. W2 would put a false claim in the spec (Hypothesis, proptest and QuickCheck all treat a panic as a falsification) and would close off F5 for good. The unshrunk input is what makes the record reproducible without re-running the generator.
> **Concern:** If W2 wins, the spec keeps a false premise that a later shrink feature must first reverse.
>
> ## Q5. V4
> **Vote:** V4a
> **Reasoning:** §8.10.2 exists to report "each failure independently". It names "the first failure short-circuits the rest" as the problem `for_each` solves. The loop should treat a failed case and a panicked case the same way: neither one damages the next case, so both continue. I accept the parent precedence (`panicked > failed > passed`, with `skipped` only when every case is skipped).
> **Concern:** The runtime stops today, so the spec and the runtime will disagree until F6 lands.
>
> ## Q6. V5
> **Vote:** V5b
> **Reasoning:** The test name is the record key. Two records under one name break every consumer that indexes by name. "First escape wins" matches E0824: the first outcome is the result, and any later panic becomes a `warning`. This narrows the shape in the vote-4 DevOps refinement but keeps its intent, "the test is broken".
> **Concern:** A reader may take V5b as a reversal of vote 4. The spec text should say it fixes the shape and keeps the intent.
>
> ## Q7. V6
> **Vote:** Show `panicked` only when it is above 0 (the `skipped` rule).
> **Reasoning:** The same rule already applies to `skipped`. `passed` and `failed` stay fixed so the line always has its anchors. This is the smaller change from the current format.
> **Concern:** Anyone who greps the summary line for `panicked` gets no match when the count is 0. The JSON summary covers that case.
>
> ## Q8. Follow-ups
> - **F1: File.** Nothing checked the closed enums by machine, and that is how `cause:"panic"` got in.
> - **F2: File.** The ticket should decide whether a crash is `panicked` or a file-level record. A signal is not a Blink panic, so the category is not obvious.
> - **F3: File.** The rule text contradicts the example next to it, and consumers will code against the wrong one.
> - **F4: File.** Narrowing makes the xfail predicate precise. Low priority.
> - **F5: File.** This follows from W1. Assertions and panics should shrink the same way once trial state can be isolated.
> - **F6: File.** The runtime conflicts with the §8.10.2 spec.

##### DevOps

> # DevOps/Tooling: Phase C ballot (tfxxwc)
>
> ## Q1. S1–S6 bundle
> **Vote:** Yes.
> **Reasoning:** The runtime drops a closed enum from the spec, and this bundle puts it back. It makes CI's "found a bug" vs "test is broken" split real (Q2 5-0), and it gives dashboards a summary schema with fixed keys and a stated invariant.
> **Concern:** Tools that already match on `cause:"panic"` break silently, so the change needs a changelog entry.
>
> ## Q2. V1
> **Vote:** V1a.
> **Reasoning:** Every red record already has its location at top-level `span`, so one path (`.span`) drives GitHub and GitLab annotations and editor jump-to for every status. V1b makes each consumer write `rec.span ?? rec.panic.span` from now on.
> **Concern:** A later status might want a top-level `message` that means something else. The spec must state that `message` and `span` each have one meaning on every status.
>
> ## Q3. V2
> **Vote:** V2b+V2c.
> **Reasoning:** PLT's point holds. An xfail that went red through an assertion can also carry a message, so the presence of `message` cannot tell a dashboard which kind of red it was. `xfail_observed` is the tag a dashboard filters on to catch drift (a known bug that now crashes), and `message` is what a person reads.
> **Concern:** If V2b wins alone, consumers will guess the kind of red from which fields the record has. That is the untagged shape the closed-enum votes rejected.
>
> ## Q4. V3
> **Q4a vote:** V3a.
> **Q4b vote:** Yes, carry the unshrunk input (named `input`, never `shrunk_input`).
> **Q4c vote:** W1.
> **Reasoning:** Shrinking on a panic is not safe in the runtime today, and CI needs the seed and input so a panic it cannot reproduce never happens. A CI log that shows the failing input directly saves a rerun, even though the seed can rebuild it. PLT is right that assertion failures longjmp too, so "a panic is not a falsification" (W2) would write a false premise into the spec permanently. W1 states the limit honestly.
> **Concern:** W1 can read as a promise. The spec text should say plainly that this version does not shrink on a panic, and nothing more.
>
> ## Q5. V4
> **Vote:** V4a. **I change from my round 1 position (V4b).**
> **Reasoning:** In round 1 I voted for V4b for consistency with the runtime's `__blink_test_is_failed` poll. §8.10.2 line 835 says, normatively, that "failures do not short-circuit", so that poll is runtime drift and not a rule to extend. A per-case report that stops at the first red case gives CI one row where the spec promises N, which is the problem `for_each` exists to solve. Assertion failures and panics must follow the same rule, so this goes with F6. I accept the stated parent precedence.
> **Concern:** Until F6 lands, assertion failures stop the loop but panics do not, so the runtime has an asymmetry for a time. Land F6 with this change or before it.
>
> ## Q6. V5
> **Vote:** V5b.
> **Reasoning:** Speaking as the DevOps seat, I confirm that V5b replaces the "separate record" wording of my vote-4 refinement and keeps its intent. A JUnit `<testcase>` is unique by name, dashboards key on name, and `total` counts tests, so a second record under the same name breaks all three. If `assert_panics` had already failed, E0824 applies unchanged.
> **Concern:** The spec must state both cases (a consumed expected panic becomes `panicked`, an earlier failure plus a cleanup panic stays `failed` + `warning`), or an implementer will get one of them backwards.
>
> ## Q7. V6
> **Vote:** Show `panicked` only when it is above 0.
> **Reasoning:** `passed` and `failed` always show today, and people and log scrapers look for `0 failed`. This follows the existing `skipped` rule, so it adds no new rule.
> **Concern:** None worth a vote. The JSON summary carries every key anyway (S2).
>
> ## Q8. Follow-up tickets
> - F1: File. Only a machine check of the closed enums stops the next `cause:"panic"`.
> - F2: File. Today a crashed binary leaves CI with no record for the test that was running, which is the worst diagnostic gap in the runner.
> - F3: File. A rule text that contradicts its own example will be implemented wrong.
> - F4: File (low priority). Narrowing which kind of red an xfail expects is the natural next step after `xfail_observed`.
> - F5: File (deferred). This is the ticket W1 points to; leave it until trial state can be isolated.
> - F6: File. The runtime poll breaks §8.10.2's normative "failures do not short-circuit", and V4a depends on fixing it.

##### AI/ML

> # AI/ML ballot: Phase C (tfxxwc)
>
> ## Q1. S1–S6 bundle
> 1. **Vote:** Yes
> 2. **Reasoning:** Models learn the output format from the spec, and a closed enum that holds a value outside it (`cause:"panic"`) teaches them that closed enums are not closed. S1–S6 make the runtime match the spec with no new status or cause. A fix loop then needs only one branch on `status`.
> 3. **Concern:** Tools that read the old `cause:"panic"` break without warning, so the change must go in the release notes.
>
> ## Q2. V1
> 1. **Vote:** V1a
> 2. **Reasoning:** Every non-pass record then has its location at one path, `span`, so "open the file at the failure" is the same code for every status. V1b gives location a second path that depends on status, which is one more decision point in every generated consumer.
> 3. **Concern:** A top-level `message` means different things on different statuses, so the spec must define it for each status where it can appear.
>
> ## Q3. V2
> 1. **Vote:** V2b+V2c
> 2. **Reasoning:** PLT is right. Under V2b alone, a model has to infer "it panicked" from whether `message` is present, and that is a guess from the record's shape. A closed two-value enum is the kind of discriminant models match with the fewest errors. The message stays because it is the drift signal an agent acts on. (I ranked V2b above V2c in round 1. The option that combines both answers PLT's ambiguity point, so I change my vote to it.)
> 3. **Concern:** `xfail_observed` and the payload can disagree if the runtime sets one without the other, so the F1 conformance test must check that they match.
>
> ## Q4. V3
> - **Q4a vote:** V3a
> - **Q4b vote:** Yes, carry the unshrunk input.
> - **Q4c vote:** W1
> 2. **Reasoning:** An agent in a fix loop needs the failing input right away. Making it re-derive the input from `seed` costs a whole extra run, so Q4b is yes. For wording, PLT showed that assertion failures also longjmp and the runner still shrinks them, so "a panic is not a falsification" is a false premise. Models would learn W2 as a permanent language rule, while W1 honestly states a limit of the current version.
> 3. **Concern:** W1 can read as a promise that shrinking will come, so F5 must exist to track that limit.
>
> ## Q5. V4
> 1. **Vote:** V4a (changed from V4b in round 1)
> 2. **Reasoning:** I voted V4b because the runtime stops the loop. But §8.10.2:835 says, normatively, "failures do not short-circuit". The runtime poll is the same kind of drift as `cause:"panic"`, and my whole position in this ticket is that the spec wins over drift. Every case running also gives an agent every broken case in one run, not one per run. It closes the fix loop faster.
> 3. **Concern:** Until F6 lands, the runtime continues after a panic but stops after an assertion, and that looks inconsistent. The spec edit must state that one rule covers both outcomes, and the runtime must fix both together.
>
> ## Q6. V5
> 1. **Vote:** V5b
> 2. **Reasoning:** Agents and tools index results by `name`, and a second record under the same name is silently lost. One record per test also keeps the S2 `total` invariant true. The DevOps seat withdrew the "separate record" refinement, so this reverses nothing without the owner's agreement.
> 3. **Concern:** The spec must write out both cases (the armed catch passed, then cleanup panics → `panicked`; assert_panics failed, then cleanup panics → `failed` plus a `warning`), or implementers will mix them up.
>
> ## Q7. V6
> 1. **Vote:** Show `panicked` only when it is above 0 (the `skipped` rule).
> 2. **Reasoning:** This is one rule already in use, and it keeps the line shape (`N passed, M failed`) that models and log scrapers already match.
> 3. **Concern:** None of substance.
>
> ## Q8. Follow-ups
> - **F1: File.** A machine check is the only thing that keeps runtime output matching the spec that models trust.
> - **F2: File.** A crash with no record is the worst case for an agent: silence, with nothing to act on.
> - **F3: File.** A rule and an example that contradict each other teach models the wrong one half the time.
> - **F4: Do not file.** No user has asked for it, and it adds a decision point to every `test.failing` an agent writes.
> - **F5: File.** W1 names a limit, and this ticket tracks it. Low priority.
> - **F6: File.** This is the spec/runtime drift that my Q5 vote depends on.

##### Minimalism

> # Phase C ballot: Minimalism (tfxxwc)
>
> ## Q1. S1–S6 bundle
> **Vote:** Yes
> **Reasoning:** The bundle adds no status and no cause. It removes the one value outside the enum (`cause:"panic"`), and the runtime then emits what the spec already defines. That is a net subtraction of surface.
> **Concern:** Some external tool may already parse `cause:"panic"`. The release notes must name the break.
>
> ## Q2. V1
> **Vote:** V1a
> **Reasoning:** `message` and `span` already exist at top level on `failed` records, so V1a adds no new name. A `panic` wrapper repeats what `status` already says and gives location a second path.
> **Concern:** A top-level `message` could later take on a different meaning on some new status, so the spec must fix its meaning as "the text of the outcome" on every status.
>
> ## Q3. V2
> **Vote:** V2b
> **Reasoning:** `message` is a field the record already has, so keeping it costs no new surface and still shows that a known bug changed shape. `xfail_observed` adds a new field and a new two-value enum for a fact a consumer can infer, so it has not earned its place.
> **Concern:** PLT is right that `message` alone does not tag which kind of red was inverted. If dashboards start grepping message text, pressure for V2c will come back.
>
> ## Q4. V3
> **Q4a vote:** V3a
> **Q4b vote:** No
> **Q4c vote:** W1
> **Reasoning:** No shrink means no per-trial catch frames and no new runtime machinery. The existing `seed` + `reproduce` already recreate the input deterministically, so a separate unshrunk-input field is a convenience with a new name. W1 records a limit and does not commit the spec to a premise PLT has shown to be doubtful. It is the smaller normative claim.
> **Concern:** If Q4b passes as Yes, the field must not be named `shrunk_input`, because nothing was shrunk.
>
> ## Q5. V4
> **Vote:** V4b
> **Reasoning:** It is what the runtime does today, with only the status word corrected. It keeps one loop rule for every kind of red. Whether every kind of red should continue is the separate F6 question and must cover `failed` too. Deciding it here for panics only would make an asymmetry. I accept the stated parent precedence.
> **Concern:** V4b leaves the spec sentence "failures do not short-circuit" in conflict with behavior until F6 resolves it. F6 must not be dropped.
>
> ## Q6. V5
> **Vote:** V5b
> **Reasoning:** One record per test keeps `total` honest and keeps `name` a unique key. A second record would need a special case in every consumer. The DevOps seat has withdrawn the refinement, so no prior vote is contradicted in substance.
> **Concern:** The spec must state both branches (assert_panics passed → `panicked`; assert_panics already failed → stays `failed`, E0824 `warning`), or implementers will guess.
>
> ## Q7. V6
> **Vote:** Show `panicked` only when it is above 0 (the `skipped` rule)
> **Reasoning:** I conceded this in round 1. It reuses the existing `skipped` rule and does not change the line for suites with no panics.
> **Concern:** None worth noting.
>
> ## Q8. Follow-up tickets
> - **F1: File.** A machine check is how the closed enums stay closed. It is tooling, not language surface.
> - **F2: Do not file.** Add it as a note on 57n5xh (the driver's non-test-record outcomes) rather than open a new ticket.
> - **F3: File.** It is a plain contradiction in the spec text, and it needs a fix, not a debate.
> - **F4: Do not file.** No user has asked for it (YAGNI). It adds surface to test.failing.
> - **F5: Do not file.** No user has asked for it, and it needs state isolation the runtime does not have. Open it when someone hits the need.
> - **F6: File.** The spec and runtime disagree today. It must decide the rule for `failed` and `panicked` together.

#### Phase D — Round 2 on Q3

Q3 tied 3-3. The panel debated Q3 alone and re-voted. Result: **V2b+V2c, 6-0**. Systems, Web/Scripting and Minimalism changed from V2b. Minimalism set three conditions, which the spec adopts: the field appears only on `expected_fail:true` / `status:"passed"` records; its values are the status before inversion (`failed | panicked`) and are never extended; the F1 conformance test checks that it agrees with the payload. Web/Scripting asked that the spec explain the field in plain words.

##### Arguments

##### Systems

> # Systems, Phase D on Q3
>
> I voted V2b because V1b's `panic` object would have been the tag. V1a won 5-1, so that premise is gone. A top-level `message` field says nothing about which kind of red the test went. An xfail that went red through an assertion or a propagated error can also carry text. With V1a, V2b alone leaves the record untagged, which is the case PLT describes. I now lean V2b+V2c.
>
> The runtime cost is close to zero. The runner already knows at emit time whether the test panicked: that is the same flag that picks `status:"panicked"` under S1. `xfail_observed` is one constant string, chosen from that flag, and written in the branch that turns the result into `passed`. The message and the tag come from one flag in one branch, so they cannot drift apart unless someone writes two sources of truth. AI/ML's concern still holds, and the F1 conformance test should check it.
>
> Min's point that a consumer can work out the kind of red is only half true. It works for an assertion red, when the assertion fields are present. It does not work for a propagated-error red or a panic red, when only message-like fields remain. When a consumer has to work out a closed enum from which fields are present, the record is untagged.
>
> One thing to say in the spec text: `xfail_observed` appears only when `expected_fail:true` and `status:"passed"`. It never appears on other records, so the record does not gain a field that is sometimes set when it should not be.

##### PLT

> # PLT, Phase D on Q3
>
> **1. Q2 removes sys's argument.** V1a won, so there is no `panic` object. Sys's reasoning ("the `panic` object is the tag") depended on V1b. Under V1a, a panic payload is a top-level `message` plus `span`. Those are the same field names an assertion or a `propagated_error` record uses for its own outcome. Nothing in the payload names the case any more.
>
> **2. Under V2b, the tag is the fact that a field is there.** "`message` present means it panicked" holds only while no other kind of red puts `message` on an xfail record. The first time someone adds the assertion text to an assertion-red xfail (a natural next step for the drift use case web describes), the inference fails without any error. A tag you infer from which fields are present is still a tag. It is just one that nobody wrote down and nothing checks.
>
> **3. Min's cost argument, answered.** `xfail_observed` adds no new vocabulary. Its values, `failed` and `panicked`, are a subset of the closed status enum the panel just affirmed 6-0. It records the status the test had before the xfail inversion. That makes the inversion lossless: the original status can be read back from the record. The new surface is one field name, and it takes nothing new to learn.
>
> **4. AI/ML's concern supports V2c.** A tag and its payload that can disagree is exactly what F1 (the conformance schema) checks. A schema can require `message` when `xfail_observed` is `panicked`. It cannot require anything of an inference no one declared.
>
> I stay at V2b+V2c.

##### DevOps

> # DevOps/Tooling: Phase D on Q3
>
> 1. **Sys's argument assumed V1b, and V1b lost 5-1.** Sys said "the `panic` object is the tag". Under V1a no `panic` object exists. An inverted panic and an inverted assertion failure both carry a top-level `message`, so V2b alone now has no tag at all. Sys's own concern (a reader will take the record for a failure) gets worse under V1a, not better.
>
> 2. **Searching the message text cannot recover the tag.** A panic message is whatever text the user passed to `panic()`, or a runtime string such as "unwrap called on None". No regex can reliably separate that from an assertion message. A dashboard query like "count known bugs that now crash" needs `xfail_observed == "panicked"`. Without it the query cannot be written. Web and min both said this in their concerns.
>
> 3. **The new surface is small.** The key is optional, it appears only on `expected_fail:true` records, and its values are two members of the existing status enum. There is no new vocabulary, no new status and no new `cause`, so Q3's 4-2 vote holds. A JUnit exporter that wants to put `type="panic"` on the xfail's `<skipped>` element also needs the field, and it should not have to guess.
>
> 4. **Aiml's concern belongs in F1.** The conformance test checks that `xfail_observed` is present exactly when `expected_fail` is, and that `span`/`message` agree with it. A machine check keeps the tag and the payload from drifting apart.
>
> Minimalism's test was "reuse a name that exists". The values are reused. The only new thing is one key that names a fact a consumer cannot otherwise get.

##### AI/ML

> # AI/ML, Phase D on Q3
>
> **1. Sys's premise was lost in Q2.** Sys voted V2b because "under V1b, a `panic` object ... is the tag." V1a won 5-1, so there is no `panic` object. What is left is a top-level `message`, and that name also appears on `failed` records. Sys's own objection to V2c was that "two copies can drift". That objection needs a tag to exist already, and under V1a none does.
>
> **2. V2b alone leaves a question the spec must still answer.** If an assertion that went red is inverted, does that record also carry `message`?
> - If **yes**, the record cannot tell a panic from an assertion (PLT's point).
> - If **no**, then "has `message`" becomes the tag without anyone saying so. That is a rule you learn by trial, and the spec does not state it.
>
> Either way, the spec has to write a sentence about which kind of red it was. V2c writes that sentence as one closed field, not as a rule about which fields are present.
>
> **3. The cost of V2c is one enum field. Models use such fields very reliably.** A model writing a consumer against V2c writes `if r.xfail_observed == "panicked"`. Against V2b it writes a text search on the message or a check for whether a field is present, and both are guesses that go wrong silently. Min's own concern predicts this: "if dashboards start grepping message text, pressure for V2c will come back." It is cheaper to add the field once now than to add it later, after consumers have been built on text searches.
>
> **4. Offer to the V2b voters.** If the "new name" cost is what decides your vote, I accept V2c in any spelling the panel prefers. What matters is the closed tag, not the name `xfail_observed`.

##### Minimalism

> # Minimalism, Phase D on Q3
>
> I am moving to V2b+V2c, and my own Phase C concern is the reason.
>
> My V2b argument rested on "a consumer can infer" the kind of red. That is false. An xfail that goes red on an assertion also carries a message, so the record shape does not tell a consumer what happened. When a fact cannot be inferred, the true alternatives are "tag it" or "grep the message text". Grepping message text is the worst surface a minimalist can accept: it makes the panic message wording (for example "unwrap called on None at ...") an unwritten API that nobody can change without breaking dashboards. One tagged field is less surface than a text format we freeze by accident.
>
> The cost of V2c is also smaller than I scored it. Its values are not a new vocabulary: `"failed" | "panicked"` are two members of the status enum the panel just closed 6-0. The spec should state this, so that it reads as "the status before inversion" and not as a new enum.
>
> Conditions for my move. I ask the panel to put all three in the spec text:
> 1. `xfail_observed` appears only when `expected_fail:true` and `status:"passed"`. It never appears on any other record.
> 2. Its value is always the status the test would have had without `test.failing`, restricted to `failed | panicked`. No new strings, ever.
> 3. The F1 conformance test checks that `xfail_observed` agrees with the payload (AI/ML's concern).
>
> To sys and web: V2b alone leaves a gap we already know about, and a later panel will close it with the same field. It is cheaper to add it once now than to reopen this later.

##### Web/Scripting

> # Web/Scripting, Phase D on Q3
>
> I lean toward changing to V2b+V2c, and my own Phase C concern is the reason.
>
> My V2b vote rested on "the message shows it at a glance". That is true for a person reading one record. It fails the test I apply to everything: how many Stack Overflow questions does it generate? The question "how do I list the test.failing tests that now panic instead of failing an assert?" has only one answer under V2b alone: regex the message text. With V1a decided, an inverted assertion failure and an inverted panic both carry a top-level `message`, so the record's shape does not help either. When the documented answer is "grep the prose", people write fragile scripts, and the prose then becomes an API we can never change.
>
> What I want to keep out of V2c is extra vocabulary. Its values are `"failed" | "panicked"`, both words from the status enum a user already knows. The only new thing is the field name. The field is present only when `expected_fail:true`, so nobody sees it unless they use `test.failing`.
>
> To sys and min: V1b lost, so no `panic` object is left to act as the tag, and sys's "second copy" argument no longer applies. Min's test ("reuse, don't add") is right in general. Here the reuse is really a hidden rule ("infer the kind of red from the text"), and a hidden rule costs a learner more than one field that names the kind outright.
>
> One request if V2c passes: the spec should say that the field reuses the status words, so nobody reads it as a third enum.

##### Re-vote ballots

##### Systems

> # Systems, Q3 re-vote
>
> 1. **Vote:** V2b+V2c (name: `xfail_observed`)
> 2. **Reasoning:** My V2b vote depended on V1b's `panic` object serving as the tag. V1a won, so that premise is gone and a top-level `message` does not say which kind of red occurred. The runner sets the tag from the same flag that picks `status:"panicked"`, in the same emit branch, so the runtime cost is one constant string, and the tag cannot drift from the payload unless someone adds a second source of truth. I adopt min's three conditions: the field appears only when `expected_fail:true` and `status:"passed"`, its value is the status before inversion, restricted to `failed | panicked`, and the F1 conformance test checks it against the payload.
> 3. **Concern:** If the runtime computes the tag somewhere other than the branch that inverts the status, the tag and `message` can disagree, and without F1 no check would catch it.

##### Web/Scripting

> # Web/Scripting, Q3 re-vote
>
> 1. **Vote:** V2b+V2c (message plus `xfail_observed: "failed" | "panicked"`)
> 2. **Reasoning:** With V1a decided, a top-level `message` does not tell a dev which kind of red a known bug went. Under V2b alone the only way to find out is to regex the message text, which is fragile and generates support questions. That also freezes the panic message wording into an API nobody meant to create. The tag reuses two status words users already know, it appears only on `test.failing` records, and one `==` check answers the question. I accept min's three conditions for the spec text: only on `expected_fail:true` + `status:"passed"`; the value is the pre-inversion status, `failed | panicked` only; F1 checks it against the payload.
> 3. **Concern:** The name `xfail_observed` is jargon to a JS dev who has never used pytest, so the spec text should explain it in one plain sentence ("the status this test had before `test.failing` inverted it").

##### PLT

> # PLT Q3 re-vote
>
> 1. **Vote:** V2b+V2c, using the name `xfail_observed`.
> 2. **Reasoning:** The xfail inversion should lose no information. The status the test would have had without `test.failing` must be readable from the record, and a closed tag is how a sum type says so. The values reuse two members of the status enum the panel closed 6-0, so this adds one field name and no new vocabulary. I endorse min's three conditions and sys's presence rule as normative text: the field appears only when `expected_fail:true` and `status:"passed"`, its value is the status before inversion (`failed | panicked`), and F1 checks that the tag agrees with the payload.
> 3. **Concern:** If the spec does not state that the values are "the status before inversion", a later change could add strings to this field that are not statuses, and it would become a separate enum.

##### DevOps

> # DevOps/Tooling: Q3 re-vote
>
> 1. **Vote:** V2b+V2c, with the name `xfail_observed`.
> 2. **Reasoning:** Under V1a an inverted panic and an inverted assertion both carry a top-level `message`, so a CI dashboard can only tell them apart by a closed tag. Without the tag, consumers search the message text, and that text becomes an API nobody wrote down. I adopt min's three conditions as spec text: the field appears only when `expected_fail:true` and `status:"passed"`; its value is the status the test would have had without `test.failing`, and only `failed | panicked`; and the F1 conformance test checks that the field agrees with the payload.
> 3. **Concern:** If the runtime sets `xfail_observed` somewhere other than the one branch that inverts the result, the tag and payload can drift, so F1 must land soon after this change.

##### AI/ML

> # AI/ML: Q3 re-vote
>
> 1. **Vote:** V2b+V2c, with the name `xfail_observed`.
> 2. **Reasoning:** With V1a decided, nothing in the record except a closed tag can tell a panic that was inverted from an assertion that was inverted. Without that tag, generated consumers fall back to searching the message text, and they fail silently. The values reuse the status words the panel closed 6-0, so a model learns one field name and no new vocabulary. I support min's three conditions and web's note that the field reuses the status words. All four should go into the spec text.
> 3. **Concern:** Until F1's conformance test exists, nothing stops the runtime from setting the tag without its payload or the payload without its tag.

##### Minimalism

> # Minimalism, Q3 re-vote
>
> 1. **Vote:** V2b+V2c (name `xfail_observed`)
> 2. **Reasoning:** Under V1a, nothing in the record says which kind of red was inverted. The only way to recover it would be to grep the message text, and that would freeze the panic message wording as an unwritten API. That is more surface than one field. The field's values come from the closed status enum (`failed | panicked`), so it adds one key and no vocabulary. I hold my three conditions: the field appears only on `expected_fail:true` / `status:"passed"` records, its values are the status before inversion and are never extended, and F1 checks that it agrees with the payload.
> 3. **Concern:** Someone may later add `"skipped"` or a new string to `xfail_observed`. The spec must say its values are a fixed subset of the status enum.

#### Phase D — Q6 reopened

After the votes were in, the moderator found that its fact sheet had left out §4.6:1360, normative text on this exact case: a cleanup panic during an armed `assert_panics` unwind leaves the expected panic as the test's result and adds an E0824 entry to `cleanup_warnings[]`, "not as a separate failing record". The Phase C vote on Q6 (6-0 V5b) was cast without this fact. The user (BDFL) voided that vote and reopened Q6 alone. The panel got the §4.6:1360 and §4.6.3 text verbatim, debated once, and re-voted.

Result: **§4.6:1360 as written (V5c), 6-0.** The expected panic sets the status (`passed`, or `failed` under E0832). The test keeps one record. The cleanup panic adds `{code:"E0824", message}` to `cleanup_warnings[]`. Conditions from the ballots: §8.10 names `cleanup_warnings[]` as valid on every status; the F1 schema lists it; the human output shows the E0824 warning on passing tests (Web/Scripting asked for the count on the result line itself, for example "PASS (1 cleanup warning)"); a follow-up ticket for an opt-in "fail on E0824 warnings" runner option (DevOps, Systems).

This amends the DevOps refinement quoted in decisions/assert-panics-semantics.md ("should surface as a SEPARATE failure record (top-level `panicked` ...)"). §4.6:1360 already overrode it; this vote confirms that.

##### Arguments

##### Systems

> # Systems, Q6 reopened
>
> **Position:** Follow §4.6:1360 as written. The test gets `status:"passed"`, and the record carries an E0824 entry in `cleanup_warnings[]`. There is no `panicked` status and no second record.
>
> **Argument:**
> 1. The spec already covers this case, and the systems seat co-authored E0824 (decisions/blockhandler-catchable-unwind.md point 2). I voted V5b without that text in front of me. The rule I argued for, "the first escape wins", gives the same answer as §4.6:1360: the first escape was the expected panic, `assert_panics` consumed it, and the cleanup panic came later during that unwind. So V5b as I stated it was wrong, and I change my vote.
> 2. With this rule the E0824 path is the same whether `assert_panics` passed or failed. In both cases the original outcome is the status, and the cleanup fault goes to `cleanup_warnings[]`. The runner needs one branch, not two.
> 3. The cost I accept: a cleanup that panics may have leaked a resource (an fd, a lock), and the test still reads green. The warning is on the record and in the human output, so the fault is visible, not hidden. A strict CI mode that treats warnings as errors is a separate ticket, if anyone asks for it.
>
> **Wording fix for the spec edit:** the field name is `cleanup_warnings[]` (§4.6), not the `warning`/`warnings` that our Phase A proposals used. Use the §4.6 name everywhere in §8.10.
>
> **Ready to vote.**

##### Web/Scripting

> # Web/Scripting, Phase D on Q6 (reopened)
>
> **Position:** Follow §4.6:1360 as written. The status is `passed`, and the record carries an E0824 entry in `cleanup_warnings[]`. There is no `panicked` status and no second record. I withdraw my V5b vote; I cast it without this text.
>
> **Argument:**
> 1. **One rule.** A dev learns "if a cleanup panics during an unwind, the first outcome stays and the cleanup panic becomes a warning". That rule already covers every catchable unwind (§4.6.3:1491, E0824, continue-drain 6-0). V5b adds a special case for one path, "unless the unwind was an armed `assert_panics`", and nobody would guess that exception. Exceptions to a rule are what generate Stack Overflow questions.
> 2. **It was already decided.** §4.6:1360 is normative text with two votes behind it. The "separate record" note in the assert_panics decision was a concern carried to implementation, and the spec text that came after it settled that concern. Overriding it here would re-litigate those votes by accident.
> 3. **The spec text is honest.** The test did what it claimed: the expected panic happened and matched. The cleanup bug is real but secondary, and a warning is the correct weight for it.
>
> **DX conditions (not a new option, only wording for the spec edit):**
> - §8.10 must list `cleanup_warnings[]` in the record shape for every status, so JSON consumers find it.
> - Human output must not hide it: print `PASS` followed by an indented `warning[E0824]: cleanup panicked: <message>` line. A green test with a buried cleanup bug is the real risk here.
>
> **Ready to vote.**

##### PLT

> # PLT, Phase D on reopened Q6
>
> **Position:** Follow §4.6:1360 as written. The test gets `status:"passed"` because the expected panic was consumed. The record carries an E0824 entry in `cleanup_warnings[]`. There is no `panicked` status and no second record.
>
> **Argument:**
>
> 1. **One rule, applied the same way everywhere.** §4.6:1360, §4.6.3:1491 and the continue-drain vote (6-0) give a single rule for every catchable unwind: the primary outcome decides the status, and a cleanup panic is a secondary E0824 warning. My V5b ballot used "first escape wins" to set the status when the test had already failed. A rule that holds only when the primary outcome is red, and is overridden when it is green, is two rules. The expected panic is the first escape here. `assert_panics` consumes it, so the result is `passed`.
>
> 2. **My Phase C vote rested on a misread.** I read V5b as "one record per test" versus V5a's second record. §4.6:1360 already rules out the second record. The part of V5b that set the status to `panicked` breaks the E0824 rule, and I did not see that when I voted. I withdraw that part.
>
> 3. **The cleanup bug stays visible.** It is tagged E0824 on the same trace frame, which is the "found without losing the primary cause" design the spec states.
>
> **Condition:** the tfxxwc spec text should use the field name `cleanup_warnings[]` from §4.6/§5.5. It must not add a second name such as `warnings`.
>
> **Concern:** A green test with a cleanup bug is easy to miss in human output. The human line should print E0824 warnings on passed tests too. That is a small follow-up, not a change to the status.
>
> **Ready to vote.**

##### DevOps

> # DevOps/Tooling: Q6 reopened
>
> **Position:** Follow §4.6:1360 as written. The test is `status:"passed"`, and the record carries an E0824 entry in `cleanup_warnings[]`. It has no `panicked` status and no second record. I withdraw my Phase C V5b vote.
>
> **Argument:**
> 1. **I cast V5b on a premise the dossier left out.** I was amending the vote-4 "separate record" wording, and I did not know that §4.6:1360 had already replaced it. The spec text now in force is the E0824 rule that devops and sys wrote. Reopening it would take a new reason, and I have none.
> 2. **One rule is better for CI than two.** Under V5b, a cleanup panic is a `warning` when a failure came first and a `panicked` status when an expected panic came first. A consumer would have to learn that split. Under §4.6:1360, a cleanup panic during a catchable unwind is always a warning, and the primary outcome always decides the status. That is also what sys's "first escape wins" rule says: the expected panic is the first escape.
> 3. **The warning is visible.** The runtime already emits `cleanup_warnings[]` in JSON (runtime_test.h:345) and a `warning: E0824` line in the human output (:365). A dashboard can count it with one path.
> 4. **Correction to my Phase A text:** the field is `cleanup_warnings[]`, not `warnings`. The spec edit should use that name everywhere.
>
> **Concern / follow-up:** A green test that hides a cleanup bug may be too lenient for strict CI. If anyone wants that changed, the fix is a runner option that fails a run on any E0824 warning, like `-Werror`, and not a status change. That would be a separate ticket.
>
> **Ready to vote.**

##### AI/ML

> # AI/ML, Phase D on reopened Q6
>
> **Position: V5c. Follow §4.6:1360 as written.** The test's status is whatever the expected panic gives (`passed`, or `failed` for E0832). The cleanup panic becomes an E0824 entry in `cleanup_warnings[]` on the same single record. There is no `panicked` status and no second record.
>
> **Argument.**
> 1. **My V5b vote rested on a wrong premise.** I voted to keep one record per test and to have the first escape win. §4.6:1360 keeps one record too, and under it the expected panic is the first escape. The cleanup panic comes second. So V5b's own logic ends at `passed`, not `panicked`. I withdraw V5b.
> 2. **One rule for models to learn.** §4.6.3:1491 and §4.6:1360 together say: "a cleanup panic during a catchable unwind never changes the status; it adds an E0824 warning." V5b adds an exception to that rule for one construct. Exceptions are what models get wrong.
> 3. **Prior votes decided this.** E0824 (blockhandler-catchable-unwind) and continue-drain (6-0) are in force. Overriding them here would need its own justification, and nobody has given one.
> 4. **Spell the field one way.** Our Phase C ballots said `warning`/`warnings`, but the spec says `cleanup_warnings[]`. Use that name everywhere, including under E0824 after a failure.
>
> **My concern, and a fix that stays in scope:** a fix loop that filters on `status` will miss a `passed` record that carries a cleanup bug. The human line should show it, for example `test NAME ... PASS (1 cleanup warning)`, and F1's schema should list `cleanup_warnings[]` as valid on every status.
>
> **Ready to vote.**

##### Minimalism

> # Minimalism, Phase D on Q6 (reopened)
>
> **Position:** I retract my V5b vote. The status is what §4.6:1360 already says: `status:"passed"`, one record, and an E0824 entry in `cleanup_warnings[]`. The test does not get `panicked`.
>
> **Argument.**
> 1. My V5b vote rested on the assumption that no rule existed, so we had to pick one. That assumption was false. A normative rule already exists, with its own vote history (E0824, and continue-drain 6-0). Keeping the spec is the zero-surface option. V5b would add a second rule for a case the spec already covers.
> 2. The spec today has one uniform rule: a cleanup panic during an unwind is a warning and never decides the status. §4.6:1360 (armed) and §4.6.3:1491 (catchable) agree. V5b would split that into "a warning, unless the unwind was an expected panic that matched". That is a special case, and special cases are where the combinatorial cost lives.
> 3. The reason we chose V5b still holds under the spec: one record per test, and `total` stays honest. The only thing that changes is the status word, and the spec fixes it.
> 4. Risk: a cleanup bug sits in a green test. It is visible in `cleanup_warnings[]`. If the panel thinks a cleanup panic must turn a test red, that change covers every unwind path (§4.6 and §4.6.3 together). It needs its own ticket, not a side effect of this one.
>
> **Spec edit needed:** §8.10 should name `cleanup_warnings[]` as a field of the test record, so the record shape in §8.10 matches §4.6.
>
> **Ready to vote.**

##### Re-vote ballots

##### Systems

> # Systems, Q6 re-vote
>
> **Vote:** §4.6:1360 as written (V5c)
>
> **Reasoning:** Under my own "first escape wins" rule, the expected panic is the first escape, so the status comes from it (`passed`). The cleanup panic becomes an E0824 entry in `cleanup_warnings[]`, and the test keeps one record. This follows the E0824 and continue-drain votes already in force. It also gives the runner one branch for every cleanup panic during an unwind, where V5b would add a special case for `assert_panics`. §8.10 should name `cleanup_warnings[]` so the record shape matches §4.6.
>
> **Concern:** A resource leaked by a panicking cleanup can sit inside a green test, so the human line must show the warning, and a warnings-as-errors runner option should get its own ticket.

##### Web/Scripting

> # Web/Scripting, Q6 re-vote
>
> **Vote:** §4.6:1360 as written (V5c): status from the expected panic (`passed`), one record, an E0824 entry in `cleanup_warnings[]`.
>
> **Reasoning:** A dev learns one rule: "a cleanup panic during an unwind never changes the status; it adds an E0824 warning." V5b adds an exception for armed `assert_panics` that nobody would guess. The spec already says this, with two prior votes behind it, and the runtime already emits `cleanup_warnings[]` and a human `warning: E0824` line (devops, runtime_test.h:345/365). The spec edit should name `cleanup_warnings[]` in the §8.10 record shape for every status.
>
> **Concern:** A green test with a cleanup bug is easy to miss when you skim, so the human line should flag it on the PASS line itself (for example `PASS (1 cleanup warning)`), not only on a separate line below.

##### PLT

> # PLT Q6 re-vote
>
> **Vote:** §4.6:1360 as written (V5c).
>
> **Reasoning:** Every catchable unwind follows one rule: the primary outcome decides the status, and a cleanup panic is a secondary E0824 entry in `cleanup_warnings[]`. The expected panic is the first escape, and `assert_panics` consumes it, so the status is `passed`, or `failed` under E0832. V5b makes an exception to that rule for one construct and overrides spec text that is already normative, with no new reason to do so.
>
> **Concern:** A `passed` record that carries a cleanup bug will be missed by consumers that filter on `status`. So §8.10 and the F1 schema must list `cleanup_warnings[]` as valid on every status, and the human line must print it.

##### DevOps

> # DevOps/Tooling: Q6 re-vote
>
> **Vote:** §4.6:1360 as written (V5c).
>
> **Reasoning:** §4.6:1360 already decides this case, and the E0824 rule has votes behind it. With that rule, a cleanup panic during a catchable unwind is always a warning, and the primary outcome always decides the status, so CI consumers learn one rule. There is still one record per test, so `total` stays honest. The runtime already emits `cleanup_warnings[]`, so a dashboard can count cleanup bugs with one path. I endorse the others' spec-edit conditions: §8.10 names `cleanup_warnings[]` as valid on every status, the F1 schema lists it, and the human line shows E0824 warnings on passed tests.
>
> **Concern:** A strict CI setup may treat a green test with a cleanup bug as a pass it should not accept, so file the opt-in "fail on E0824 warnings" runner option as a follow-up ticket.

##### AI/ML

> # AI/ML: Q6 re-vote
>
> **Vote:** §4.6:1360 as written (V5c).
>
> **Reasoning:** A single rule, "a cleanup panic during any catchable unwind never changes the status; it adds an E0824 entry to `cleanup_warnings[]`", is easier for a model to learn than that rule plus an exception for `assert_panics`. It keeps one record per test, it keeps the rule that the first escape wins, and it respects the E0824 and continue-drain votes. The runtime already emits `cleanup_warnings[]` and a human `warning: E0824` line. So the spec, the runtime and the model will all agree.
>
> **Concern:** A fix loop that filters only on `status` will pass over a green test that hides a cleanup bug. §8.10 must list `cleanup_warnings[]` in the record shape for every status, and the human output must print the warning on `PASS` lines too.

##### Minimalism

> # Minimalism, Q6 re-vote
>
> **Vote:** §4.6:1360 as written (V5c)
>
> **Reasoning:** The spec already has a rule for this case, backed by earlier votes: during any catchable unwind, a cleanup panic becomes an E0824 entry in `cleanup_warnings[]` and never decides the status. Keeping that rule adds no surface. V5b would add an exception for one construct and override two decided votes on a premise we now know was incomplete.
>
> **Concern:** A green test with a cleanup bug is easy to miss. The human line must print the E0824 warning on passed tests. Any "fail on warnings" option belongs in a separate ticket, not in a status change.

### Final Spec

Governing text: sections/06_tooling.md §8.10 (*Panicked records*, *Summary and exit code*, *Human-readable output*, *Cleanup warnings*), §8.10.2 (`for_each` failure attribution), §8.10.4 (*A panic inside a property*), §8.10.6 (`xfail_observed`).

```blink
test "session token decodes" {
    let tok = parse_token("").unwrap()   // panics on None
    assert_eq(tok.user, "ada")
}
```

```json
{"name": "session token decodes", "status": "panicked",
 "message": "unwrap called on None",
 "span": {"file": "src/auth.bl", "line": 91, "col": 17}}
{"summary": {"total": 14, "passed": 11, "failed": 2, "panicked": 1, "skipped": 0, "duration_ms": 340}}
```

```
test session token decodes ... PANIC
  unwrap called on None
  at src/auth.bl:91:17
11 passed, 2 failed, 1 panicked (of 14)
```

- A panic that escapes a test body gives `status:"panicked"`. It has no `cause`, no `error` object, no assertion fields and never `line: 0`. `cause:"panic"` is gone. Both closed enums stay closed.
- The payload is top-level `message` plus `span` when the location is known. `message` and `span` mean the same on every status.
- `summary` always carries `total, passed, failed, panicked, skipped, duration_ms`. `total = passed + failed + panicked + skipped`. Exit non-zero when `failed + panicked > 0`.
- Human output: `PANIC`; the summary line shows `panicked` and `skipped` only when above 0.
- `test.failing`: a panic is expected red → `status:"passed"`, `expected_fail:true`, plus the panic `message`/`span` and `xfail_observed:"panicked"`. `xfail_observed` appears only on expected-red records; its values are `failed | panicked` and are never extended.
- `prop_check`: in this version, no shrink after a panic. The record carries `seed`, `reproduce` and the unshrunk `input`, never `shrunk_input`.
- `for_each`: a panicking case records `panicked` in `cases[]`; failing and panicking cases do not stop the loop. The parent is the most severe case status (`panicked > failed > passed`), and `skipped` only when every case is skipped.
- A cleanup panic during a catchable unwind, `assert_panics` included, never changes the status and never adds a record. It adds an E0824 entry to `cleanup_warnings[]`, valid on every status, printed under the result line.
- Out of scope: signal crashes (`SIGSEGV`) and test files that do not build (§8.10.5).
- Follow-ups: JSON Schema + conformance test (F1); signal-crash record (F2); §8.10.6 unexpected-pass rule text vs example (F3); xfail `raises=` narrowing, low priority (F4); shrink after a panic once trial state is isolated (F5); `for_each` must not short-circuit, lands with the implementation (F6); opt-in "fail on E0824 warnings" runner option.
