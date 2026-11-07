[< All Decisions](../DECISIONS.md)

# `return` in a Test Body — Design Rationale

§2.20 *Error Propagation: `?` in Test Bodies* gives a test body the return type `()` or, when `?` appears, the elaborated `Result[(), TestError]`. The elaborated type is hidden from user code (*Hygiene*). §3.3 *`return` with a value* checks `return e` against the return type of the nearest function or closure, `()` included. Neither text said which return type a test body has for `return`. Two programs showed the gap. `test "t" { return 5 }` passed `blink check`, and `blink test` then stopped with an internal error. A bare `return` after `let x = f()?` was an error whose text named the hidden function and the type `Result[(), ?]`.

The panel settled it in one vote.

## Summary

| Q | Question | Result | Vote |
|---|---|---|---|
| Q1 | The return type of a test body for `return` | `()` for user code, with `?` and without `?`. `return` and `return ()` compile, and the test passes at that line. `return 5`, `return Ok(())` and `return Err("x")` are E0300. `return panic("x")` compiles (`Never`), and the test fails by panic. A `return` in a closure is checked against the type of that closure | 6-0 |

Wording that the vote carried, with no separate ballot:

- The E0300 text for a test body says "test body" and `()`. It never shows the elaborated type or an internal name.
- The E0300 help in a test does not offer "add `-> T`", because a test has no signature. It says to drop the value, and to use `assert` or `panic` to make the test fail.
- `blink check` reports `return 5` in a test body.
- The runner shows an early `return` as a plain pass, with no "returned early" state.

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated. All six proposed the same behavior in Phase A, so the fast path ran: Phase B (debate) and Phase D did not run. Quotes are verbatim; "…" marks a cut.

#### Phase A — Independent proposals

All six seats gave the same table, for a body with `?` and a body without `?`:

| Form | Result |
|---|---|
| `return` | compiles; the test passes at that line |
| `return ()` | compiles; the test passes |
| `return 5` | E0300 |
| `return Ok(())` | E0300 |
| `return Err("x")` | E0300 |
| `return panic("x")` | compiles (`Never`); the test fails by panic |

Excerpts follow, each with its seat.

- **Systems:** "Rule: for user code, every test body has return type R = (), with or without `?`. Elaboration to Result[(), TestError] is a lowering detail that user code never sees." "Letting `return Err(e)` in would force user code to build or see TestError (opaque by spec) and would change the C return shape depending on `?` use. That makes cost depend on a hidden type. I reject it." …
- **Web/Scripting:** "(c) No. `return e` is checked against (), so `Result[(), E]` is never legal. Users never see the Result." "One rule works for all tests. Adding or removing a `?` does not change what `return` means." …
- **PLT:** "LAW: Surface typing of a test body is invariant under elaboration. A test body has surface return type () whether or not it contains `?`." "Anything else makes the type of `return` depend on a distant `?`. That breaks compositionality: adding a `?` three lines later would change the meaning of a `return` above it." …
- **DevOps/Tooling:** "The E0300 message for a test must say "test body" and "()". It must never print `__test_t` or `Result[(), ?]`." "In a test, E0300 help should say only: "a test body returns (); drop the value, or use `assert` to fail the test"." "A runner log line for an early `return` should read as a plain pass. It must not show a special "returned early" state." …
- **AI/ML:** "For `return`, a test body acts as `fn() -> ()`. The §3.3 rule applies unchanged: `return e` is checked against ()." "An LLM often writes `return Ok(())` at the end of a test from Rust habit. This proposal rejects it with an error that says "remove the value", so one retry fixes it." …
- **Minimalism:** "Rule (one sentence): in a test body, `return e` is checked against (), with or without `?`. Bare `return` ends the test as a pass." "A test has only two outcomes, pass and fail. Fail already has two spellings: panic and `?`. A third spelling, `return Err("x")`, is redundant." …

All six seats answered the three questions of the gap the same way: (a) a test body is `()` for `return e`, so `return 5` is E0300; (b) a bare `return` is a pass; (c) `return e` with `e: Result[(), E]` is E0300, because the Result is never visible.

#### Phase B — Debate

Did not run. No seat proposed a different behavior.

#### Phase C — Silent vote

Option A: a test body has return type `()` for user code, with or without `?`; the table above is the same in both bodies. It was the only option on the ballot. **6-0 for A.** Votes are verbatim from each seat's ballot.

  - **Systems:** A — "One rule (R = () for user code) lets the typechecker check `return` before elaboration, so it needs no knowledge of the hidden type. This closes the MVCE 1 hole, where `return 5` reached C as a void function. A bare `return` lowers to a constant `Ok(())`. That is the same code the fall-off-the-end path already emits, so the cost is zero and does not depend on whether `?` appears. User code never builds or sees TestError." Concern: "The lowering of `return` in an elaborated body must be applied only to returns that belong to the test body. If it also rewrites returns inside closures, a closure's own return value would be wrong. The corpus needs a test with a closure `return` inside a test that uses `?`."
  - **Web/Scripting:** A — "This matches what a JS or Python dev expects. A test body returns nothing, and a bare `return` stops it early with a pass. One rule holds whether or not the body uses `?`, so adding a `?` never changes what `return` means. A user who wants a failure already has `assert` and `panic`, so they don't need `return Err`. The hidden Result stays hidden." Concern: "A dev coming from Rust may write `return Ok(())` and get E0300, so the help text must say plainly "drop the value" for them."
  - **PLT:** A — "The surface type of a test body stays the same whether or not `?` appears. So `return` is checked locally against (), and the hidden Result[(), TestError] stays a lowering detail, as Hygiene requires. Bare `return` lowers to Ok(()), which keeps `return` as the unit of the surface type. `?` and panic remain the only ways to fail a test. The writer notes (no `__test_t` or Result in the text, no "add -> T" help) follow from the same rule." Concern: "The lowering must rewrite every bare `return` and `return ()` in the elaborated body, including nested blocks and match arms but excluding closures. A missed one would bring back the C-level "function returning Result" miscompile."
  - **DevOps/Tooling:** A — "The rule is the same in every test body, so what a `return` means does not depend on whether a `?` appears elsewhere. The E0300 text names "test body" and "()" and never prints `__test_t` or `Result[(), ?]`. A bare `return` shows in the runner as a plain pass. Catching MVCE 1 in `blink check` removes the ICE that CI users see today." Concern: "Test-specific E0300 help must be implemented. If it is skipped, the generic "add -> T" help would appear in a test body, which has no signature."
  - **AI/ML:** A — "One rule covers every test body: `return` follows `fn() -> ()`, and `?` changes nothing the user can see. An LLM can learn that from the spec alone and has no hidden type to guess. A Rust-style `return Ok(())` gets E0300 with a repair that is easy to follow: drop the value, and use assert or panic to fail. That is one retry. The wording note that keeps `__test_t` and `Result[(), ?]` out of the message matters for debuggability, because a leaked internal name invites the model to write it." Concern: "Writers who expect `return Err(..)` to fail a test, as in Rust, will hit E0300, so the E0300 help text has to name assert and panic."
  - **Minimalism:** A — "Option A adds no new rule. It names the missing fact, that a test body is R = (), and lets the existing 3.3 return check do the rest. The user-visible rules stay the same whether or not a `?` appears in the body, and the hidden Result stays hidden (Hygiene in 2.20). A test has only pass and fail. Panic and `?` already express fail, so `return Err(..)` and `return Ok(())` would be redundant spellings." Concern: "A user may expect `return Err("x")` to fail a test, as in Rust Result-returning tests. They get E0300 and must be told by the help text to use assert or panic."

#### Phase D

Did not run.

## Result

Q1 is A (6-0). The spec text is the paragraph *`return` in a test body* in §2.20 *Error Propagation: `?` in Test Bodies*, a paragraph after *`return` with a value* in §3.3, and the E0300 row of the error catalog.
