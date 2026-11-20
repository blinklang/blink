[< All Decisions](../DECISIONS.md)

# A Test Block Is a Root — Design Rationale

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in independent-proposal → debate → vote rounds. The question: must a built-in effect (`FS`, `IO`, `Env`, `Process`, `Async`) that reaches a test block have a `with`? The old text said a test has "no implicit effects", so an end-to-end test that wrote a file or ran a child process was an error with no fix: no spec text names a real handler that a test can put in a `with`. A prototype of the check over the test corpus gave about 12,800 test blocks and 82,361 hits. By effect: FS 27,782; Env 19,494; IO 18,359; Process 16,003; Async 386; Net 198; Time 111; Rand 19; DB 6. The check for user-declared effects had 2 hits.

Already decided and not reopened: a user-declared effect that reaches a test block with no `with` is E0539 (one code at both roots); a closure is charged at its call; `State` is held by every test block and has no handler.

#### Phase A — Independent proposals

All six seats rejected a nameable real handler (`with real_fs() { }`). Four proposed that the test root holds the built-in effects (option R). Two proposed a declared test row (option D) and named R as the fallback.

- **Systems:**
  > A test block holds every built-in effect that `main` holds a root handler for (§4.6), plus `State`. Same set, same rule, at both roots. No new handler values, no new names.
- **Web/Scripting:**
  > A Python, Go or Rust dev expects a test to touch the disk, run a child, read `HOME` and print.

  Proposal W1 (preferred): *a test declares its built-in effects with a row, the same as a function*. Fallback W2:
  > the test root holds every built-in effect, as `main` does
- **PLT:**
  > A real handler of a world effect cannot discharge that effect.

  > A root holds exactly the effects for which the runtime installs a handler at that root.

  PLT proposed P1 (a declared test row) as the preferred option, with R as the fallback.
- **DevOps:**
  > A rule that 2/3 of the corpus breaks on day one, and that has no fix for Process, FS, Net or Async (no handler exists to name), is not a rule users will follow.

  > The runner is already a root that holds handlers. Say so for every built-in.
- **AI/ML:**
  > A test block is a root with the same capabilities as `main`: a root handler for each built-in effect (FS, IO, Env, Process, Async, Net, Time, DB, Rand), plus `State`.
- **Minimalism:**
  > Drop "no implicit effects" for built-in effects.

#### Phase B — Debate highlights

Web and PLT moved from D to R. All six wrote STABLE.

- **Web/Scripting:** *(moved D → R)*
  > I proposed D for one reason: so a reader sees which tests touch the world.

  > Under D the user types what the compiler already knows, which is the ceremony §4.6 calls "a worse version of what the compiler already computes" for `main`.
- **PLT:** *(moved D → R)*
  > No one calls a test. Like `main`, a test is a root, and the §4.6 reason for an implicit row on `main` holds word for word
- **Minimalism:**
  > A test block has no caller. Its row binds nobody.
- **Systems:**
  > The C does not change between R and D.
- **DevOps:**
  > R has one rule: a test root holds what `main` holds.
- **AI/ML:**
  > R also keeps one rule a model learns once: "a root holds what the runtime has a handler for; a user effect needs `with`".

Variations that the panel settled in Phase B:

- A split that keeps `Net` or `DB` out of the test root (V5) was rejected by every seat. **Systems:** "The line is a policy line; the codegen has no such line." **PLT:** "The split has no rule behind it (agree with min and sys)."
- `DB` (V6): **Systems:** "I withdraw my DB carve-out." **PLT:** "The test root follows `main`, whatever `main` holds." Whether `main` has a `DB` or `Crypto` root handler is a separate §4.6 question.
- Per-test capture of output (V2), `env.exit` that fails the test (V3) and the inferred row in `--json` and the LSP (V4) went to separate runner and tooling tickets, except that V2 went to the Phase C vote.
- The §2.20 foreign-code subsection. **PLT:**
  > an `@ffi` row names world effects only (§4.3). So a user-declared effect can never come only from foreign code. Under R no built-in reaches a test unhandled. The §2.20 foreign-code subsection then has no case, and the writer cuts it.

  **Web/Scripting:** "A lint for "foreign Rand in a test bypasses the seed" can be a friction ticket if anyone hits it."

#### Phase C — Final vote

- **Q1: How does a test get a built-in effect? R (the test root holds every built-in effect that `main` holds) or D (a declared test row)** (6-0 for R)
  - **Systems:** R — R and D compile to the same C: the test root fills the same evidence slots with the same default vtables. *Concern:* a forgotten mock now silently reaches the real network or filesystem, so the inferred row must get to the user through tools (the V4 ticket), or nobody will see it.
  - **Web/Scripting:** R — A JS, Python or Go dev writes a test that opens a file or runs a child and expects it to run. R does what they expect, with no new syntax and no new names. *Concern:* a forgotten `with mock_net(...)` now hits the real network without a word, so the inferred-row tooling ticket and CI sandboxing must actually ship.
  - **PLT:** R — A real handler of a world effect charges the effect it discharges (clause row, §4.7.1). So the only sound source of a world effect is a root that holds it. *Concern:* a foreign `! Rand` call (or any foreign world effect) in a test skips the runner's seeded handler with no diagnostic, so a test can be nondeterministic with no sign in the source.
  - **DevOps:** R — the compiler already infers each test's row, so a typed row adds no fact for a tool, a CI policy script or a reviewer; the LSP and `--json` can show the inferred row. *Concern:* with no row in the source, tests that touch the real world stay invisible until the runner/LSP ticket (V4) ships the inferred row in the editor and in `--json`, so that ticket must not slip.
  - **AI/ML:** R — One rule for both roots ("a root holds what the runtime has a handler for; a user effect needs `with`") is the rule a model learns once and does not get wrong. *Concern:* a test can reach the real network or disk with no mark in its source, so a CI run can be flaky or slow, and nothing in the code tells the reader why.
  - **Minimalism:** R — R is the only option that removes a rule. *Concern:* a forgotten mock reaches the real network or disk in silence. If users hit this, a runner flag should fence it, not a language rule.
- **Q2: Does this spec say that the runner captures `IO.Print`/`IO.Eprint` per test (C-IN), or leave capture to a runner ticket (C-OUT)?** (6-0 for C-OUT)
  - **Systems:** C-OUT — capture does not change what compiles or which effects a root holds; it only changes which vtable the runner puts in the `io` slot, at the cost of one pointer. *Concern:* until the runner ticket lands, parallel tests that print can interleave on stdout, so that ticket must be filed now, not left as a "later".
  - **Web/Scripting:** C-OUT — Capture does not change what compiles or which effect a test holds. It is runner behavior and belongs in §8.10 with its own ticket.
  - **PLT:** C-OUT — Capture changes no typing rule and nothing about what compiles. The test root still holds `IO.Print`, and whichever handler the runner installs there serves the call. *Concern:* until the runner ticket lands, parallel tests can interleave stdout, and a reader may read "root IO handler (stdout)" as a fixed promise rather than a placeholder.
  - **DevOps:** C-OUT *(moved from C-IN)* — I proposed C-IN, but aiml is right that capture changes no compile result, and C-OUT still answers Q3 (the root IO handler serves `io.println`).
  - **AI/ML:** C-OUT — Capture does not change what compiles. It is runner behavior in §8, and it needs its own design: where output shows on pass and on failure, and how it reads with `--json` and parallel runs.
  - **Minimalism:** C-OUT — The spec needs only "the root IO handler serves `io.println`; `capture_print` overrides it".

No Phase D ran.

### Final Spec

```blink
test "child process runs" {
    let out = process.run("echo", ["ok"]).unwrap()
    assert_eq(out.out.trim(), "ok")
}

test "fetch with mock" {
    with mock_net(responses) {
        assert_eq(fetch_data("https://example.com").unwrap(), "ok")
    }
}

effect Store {
    fn get(key: Str) -> Int
}

test "load reads the count" {
    assert_eq(load(), 1)    // E0539: `Store` is a user-declared effect with no `with`
}
```

- A test block is a root. A root holds the effects that the runtime installs a handler for, plus `State`. A test holds every built-in effect that `main`'s root holds, plus `State`.
- The runner's seeded `Rand` handler (§8.10.4) is the root `Rand` handler of a test.
- A `with` in the test body overrides a root handler.
- A user-declared effect that reaches a test with no `with` is E0539.
- No nameable real handler and no effect row on `test`.
- `Async` and `io.print*` follow the same rule. The root IO handler serves `io.println`, and `capture_print` overrides it. The spec does not fix where the root IO handler writes.
- The §2.20 foreign-code subsection is cut, with the matching hint text in §4.6 and in the E0539 catalog row.
- Not decided here: whether `main` has a `DB` or `Crypto` root handler; per-test print capture; `env.exit` in a test; the inferred row in `--json` and the LSP; the order in which tests that write the environment run.
