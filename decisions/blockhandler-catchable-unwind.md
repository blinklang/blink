[< All Decisions](../DECISIONS.md)

# BlockHandler Catchable-Unwind — Design Rationale

This decision was originated mid-deliberation during the [Defer Keyword Rejection](defer-keyword-rejection.md) panel. The Sys panelist surfaced a spec inconsistency between §4.6.3 and §2.20: §4.6.3 said panics bypass `BlockHandler.exit()` entirely, but §2.20 specs assert-failure panics as catchable unwind to the test runner. The practical consequence: `with db.transaction() { assert_eq(...) }` silently leaked the transaction on assertion failure. This is a correctness bug independent of the defer question.

The panel voted 6-0 (Q2 of the defer panel) that the amendment must be recorded as its own decision regardless of how the defer question resolved. This file is that record.

### The Bug

Before the amendment:

- §4.6.3 (BlockHandler): "panics bypass `BlockHandler.exit()` entirely"
- §2.20 (test blocks, line 1198): assertion-failure panics are *catchable* by the test runner; the runner records the failure and continues to the next test
- Net effect: a transaction opened by `with db.transaction() { ... }` and unwound by an assertion failure inside the block ran neither `commit` nor `rollback` — the connection sat in an open transaction state until process exit.

The same bug applied to `Closeable.close()` via §5.5, since §5.5 mirrored §4.6.3's "all exit paths except panic" wording.

### The Amendment

`BlockHandler.exit(self, ok: Bool)` and `Closeable.close(self)` run on every **catchable unwind**:

| Exit path | `ok` flag (BlockHandler) |
|---|---|
| Normal completion | `true` |
| `?` propagation | `false` |
| `return` from inside the block | `false` |
| Assertion failure | `false` |
| `skip()` | `false` |
| Uncaught / process-terminating panic | (does not run — bypassed) |

The set of catch boundaries is **closed and runtime-defined**. User code cannot extend it — there is no `recover`/`catch_panic` primitive in v1, and introducing one would require a separate spec amendment that re-evaluates `exit()`/`close()` semantics under the new boundary set. PLT named this the "R3-forbidden fence."

### Why `panic: Never` is preserved

The amendment runs `exit(false)` and `close()` bodies as **runtime-driven finalization**. They cannot:

- Receive the panic value as an argument
- Inspect a panic-vs-normal-unwind discriminant other than the `ok: Bool` flag
- Suppress the unwind, transform it into a different control flow, or "rescue" the test

This means the typing claim `panic: Never` at any call site that doesn't observe a runtime catch boundary remains sound. Analogous to Rust `Drop` impls running on stack unwind without violating `!` (never-type) reasoning, or Java `finally` blocks running without making exceptions reifiable beyond `catch`.

PLT verified this reading and signed off on it during Phase B.

### Panel Deliberation

Same panel as the defer-keyword question (sys, web, plt, devops, aiml, min). The amendment was discovered during Phase B of that deliberation; Q2 of the Phase C vote made it a standalone decision.

> **Note on quotation:** As with the defer-keyword rationale, pre-compaction Phase A/B verbatim transcripts were not preserved. Excerpts below come from the Phase C tally (`.tmp/deliberate_panel_votes.md`) "Key argument" and "Concerns flagged" sections.

#### Phase B — Debate highlights

- **Sys (originator):** "§4.6.3 says 'panics bypass `exit()` entirely' but §2.20 line 1198 specifies that assert-failure panics are *catchable* unwind to the test runner. This means today, `with db.transaction() { assert_eq(...) }` silently leaks the transaction on failure — a real bug, not a hypothetical."
- **PLT (soundness verification):** "`exit(false)` runs as runtime-driven finalization, cannot inspect/transform the panic; analogous to Rust `Drop` on unwind. `panic: Never` axiom preserved as a typing claim about the call site. The closed-set fence on user-level recovery is what makes that claim hold — if we ever add `recover`, the `exit()`/`close()` semantics need a separate revisit."
- **Min:** "This is the load-bearing fix. Without it, `defer` would be sugar over a still-broken `with`. With it, `defer` is sugar over a now-correct `with` — and we don't ship sugar."
- **DevOps:** raised the migration concern: "existing user-authored `BlockHandler.exit` impls assumed 'panic bypasses'; the amendment runs them on more paths now. Need a one-release lint for impls that mutate without an `if !ok` guard, plus a 'BREAKING in spirit' changelog entry."

#### Phase C — Final votes (relevant to this decision)

- **Q1 (which option resolves the spec gap):** REJECT_WITH_AMENDMENT — 6-0. See [Defer Keyword Rejection](defer-keyword-rejection.md). The amendment is the load-bearing change.
- **Q2 (record amendment separately):** YES — 6-0. The amendment fixes a real spec bug independent of the defer question; coupling them would let a defer-question split block a correctness fix.
- **Q3 (what does "catchable unwind" enumerate):** A — closed set, R3-forbidden fence — 6-0. The set is exactly `{? propagation, return, assert failure, skip()}`. Runtime-defined and closed. Introducing user-level panic recovery requires a separate amendment.
- **Q5 (does `skip()` trigger cleanup):** YES — 6-0. Skip is controlled cooperative early-exit, structurally identical to `?` propagation at the runtime boundary. A test that creates a temp dir then `skip()`s on platform mismatch must remove the temp dir.

No Phase D (all 6-0).

### Concerns flagged for spec-text drafting

Recorded in `.tmp/deliberate_panel_votes.md`; carried forward as follow-up `br` tickets:

1. **Migration disclosure (devops, sys):** existing user-authored `BlockHandler.exit` impls assumed "panic bypasses". Add a one-release lint for impls that mutate without an `if !ok` guard. Spec changelog: "BREAKING in spirit — `exit()` now runs on catchable unwind."
2. **E0824 cleanup-panicked-during-unwind (devops, sys):** if `exit(false)` itself panics, the original panic is preserved and the secondary surfaces as a `warning` in the trace. Spec must define this behavior; it cannot be implementation-defined.
3. **Trace schema (devops):** `phase: "exit"` events get `ok: Bool` and `unwind_reason: ?propagate|return|assert_fail|skip|panic_uncatchable`. `--blink-trace exit` filter as first-class channel.
4. **Closed-set wording (plt, min):** spec text must say explicitly "the set of runtime catch boundaries is exhaustively defined by this spec and cannot be extended by user code; introducing user-level panic recovery would require a separate spec amendment that re-evaluates `exit()`/`close()` semantics."
5. **Skip cleanup ergonomics (web, plt):** test runner JSON output must distinguish "skipped after partial setup" from "skipped immediately" — otherwise developers see green-skip and miss that work was done before bailing.
6. **Test runner unwind-mechanism (min):** spec must require skip use Result-sentinel propagation, not panic unwind, or the implementation will silently diverge.

### Final Spec

Sections amended:

- **§4.6.3** (`sections/04_effects.md`) — `BlockHandler.exit()` constraints + new "Catchable unwind" subsection enumerating the closed set, with the R3-forbidden fence wording.
- **§5.5** (`sections/05_memory_compile_errors.md`) — `Closeable.close()` runs on every catchable unwind. Wording made uniform with `BlockHandler.exit()`.
- **§2.20** (`sections/02_syntax.md`) — assertion-failure paragraph + skip() paragraph cross-reference §4.6.3/§5.5 and clarify that the test runner's per-test frame is a runtime catch boundary; transactions roll back on assertion failure.

Stdlib addition:

- `lib/std/testing.bl` — `Cleanup` BlockHandler type + `cleanup(action: fn() -> Void) -> Cleanup` factory function. The HOF that lets `with cleanup(fn) { body }` register non-`Closeable` teardown.

```blink
// The locked semantics
with db.transaction() {
    assert_eq(rows.len(), 3)  // failure here triggers transaction.exit(ok=false) → rollback
}

with cleanup(fn() { remove_dir(temp) }) {
    return early_path()  // return triggers cleanup.exit(ok=false) → remove_dir runs
}

with reader = open(path) as r {
    skip_unless(r.is_utf8())  // skip() triggers reader.close() → file handle released
}
```
