[< All Decisions](../DECISIONS.md)

# Mocking Helpers Beyond IO Captures (`mock_clock`, `mock_env`) — Design Rationale

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated br task **j21b6c** ("Spec: mocking helpers beyond IO captures — `mock_clock`, `mock_env`, `record_calls`") through independent-proposal → debate → vote → focused-re-debate rounds. The deliberation was run unattended by the nightly cron procedure; this record reconstructs the verbatim positions captured in [PHASE_8_TALLY.md](../PHASE_8_TALLY.md) and the panel transcript before context compaction.

The gap: `std.testing` already ships handler factories for the stateless IO sinks (`capture_log`, `capture_print`, `capture_eprint`). Should it also ship `mock_clock` for the `Time` effect, `mock_env` for the `Env` effect, and a polymorphic `record_calls[E]` for arbitrary handler recording? And — if so — do they belong in central `std.testing` or in per-effect `*.testing` submodules?

#### Phase A — Independent proposals

- **Systems:** Per-effect `*.testing` submodules (`std.time.testing`, `std.env.testing`). Keep `std.testing` from importing every effect's stdlib module. Free-fn `frozen_clock(i: Instant) -> Handler[Time]` and `mock_env_from(initial: Map[Str, Str]) -> Handler[Env]` with module-level `mut` recording globals. Reject `record_calls[E]` — constraint #9 (no effect-kinded generics in v1) makes it literally inexpressible. Initial position: A1 (free-fn only) / B2 (per-effect modules) / C1 (free-fn frozen_clock) / D1 (free-fn mock_env) / E1 (reject record_calls).

- **Web/Scripting:** Central `std.testing` for all effect mocks. The 90% case is a test that wants `with mock_clock(start), mock_env(...) { ... }` and three import lines per test file is a papercut. mock_clock probably wants `.advance(d)` for testing timeouts; mock_env probably wants `.set(...)` for mid-test mutation. Reject `record_calls`. Conditional Q4 position: D1 if the panel forces a single shape, D2-hybrid if hybrid is permitted.

- **PLT:** Match the established shape — `capture_log` is a free-fn factory returning `Handler[IO.Log]`. `frozen_clock(i: Instant) -> Handler[Time]` and `mock_env_with(init: Map[Str, Str]) -> Handler[Env]` are the structurally identical extension. `record_calls[E]` is literally inexpressible under constraint #9 — handler-kinded generics are out. Initially A1/B1/C1/D1/E1.

- **DevOps/Tooling:** Same surface, same diagnostic story. Free-fn factories let the LSP suggest `mock_clock(now)` exactly the way it suggests `capture_log([])`, and let the compiler emit "needs `Handler[Time]` — try `std.testing.mock_clock(...)`." `MockClock` controller struct is *machinery* not a *helper* — the nyyt0s constraint #2 ("pure library helpers, no intrinsics") is satisfied either way, but the simpler shape composes better with capture_log precedent. Initially A3/B1/C1/D1/E1.

- **AI/ML:** Two-shape API is a learnability disaster *unless* documented explicitly: if `capture_log` is a free fn and `mock_clock` is a controller struct, an LLM will conflate them and emit `with mock_clock(now) { ... }` expecting handler semantics or `let c = capture_log(); c.advance(...)` expecting controller semantics. Whichever way Q3/Q4 resolves, the rule "free-fn for stateless sinks, controller for stateful mocks" must land in §6 prose. Initially A2/B1/C2/D2/E1.

- **Minimalism:** Reject everything beyond what users can already write inline. `record_calls[E]` is dead on arrival. `mock_clock`/`mock_env` are speculative — show the usage signal first. If shipped, every `mock_*` cements precedent for one-per-effect across §4; the stdlib surface is a finite budget. Concern: Q4's `MockEnv.writes()` re-litigates Q5's unanimous reject of `record_calls` for one specific effect. Initially A1/B1/C1/D1/E1.

#### Phase A.5 — Mechanical dedupe

Five questions extracted from the spread of proposals:

- **Q1 (scope):** A1 = ship neither mock_clock nor mock_env. A2 = ship mock_clock only. A3 = ship both mock_clock and mock_env. A4 = ship both plus `record_calls[E]`.
- **Q2 (placement):** B1 = central `std.testing` (matches capture_log). B2 = per-effect `*.testing` submodules.
- **Q3 (mock_clock shape):** C1 = free fn `frozen_clock(i: Instant) -> Handler[Time]` with module-level `mut` for `slept` recording. C2 = controller struct `MockClock` with `.handler()` + `.advance(d)` + `.elapsed()`.
- **Q4 (mock_env shape):** D1 = free fn `mock_env_with(init: Map[Str, Str]) -> Handler[Env]`. D2 = controller struct `MockEnv` with `.handler()` + `.set(name, value)` + `.writes()`. D3 = split `mock_env_read(init) -> Handler[Env.Read]` and `mock_env_write() -> Handler[Env.Write]` with `.writes()` on the writer.
- **Q5 (record_calls):** E1 = reject. E2 = ship per-effect surrogates (no generic).

Two cross-cutting variations flagged: V1 — `Env.exit -> Never` handler op behavior (panic with captured code vs auto-delegate to real `env.exit`). V2 — whether `mock_clock`'s `Time.Sleep` op records the duration or silently no-ops.

#### Phase B — Debate highlights

**PLT's nesting argument that swung Q3 and Q4:**

> *(plt)* "Module-level `mut` state breaks under nested `with` blocks. §4 line 1020 is leftmost-wins for the outer scope, but §4 line 1012 says inner `with` shadows for the body of the inner block. Concretely: `with frozen_clock(t1) { ... with frozen_clock(t2) { f() } ... }` — the inner `frozen_clock(t2)` overwrites `_clock_fixed`, the outer body resumes after the inner block exits, and the outer handler now reads `t2`, not `t1`. The C1 shape is *structurally broken under nesting*. Per-instance struct state (C2) closes over the value on `self`, isolates correctly, and the `Cleanup` precedent in `lib/std/testing.bl` proves controller-style is library-deliverable today."

**AI/ML's `Env.exit` footgun argument that forced internal consistency on Q1:**

> *(aiml)* "`Env.exit(code: Int) -> Never`. Auto-delegating to the real `env.exit` terminates the test process mid-run. The user writes `with mock_env([]) { run_cli() }` expecting the test to *observe* an exit, and instead the test runner dies with code 1. Every test author hits this once and writes a five-line shim — that shim should live in std.testing once, not per-user. The inline-handler pattern from §4.4.3 (the `let mut exit_code = -1; handler Env { ... fn exit(...) { exit_code = code; abort } }` example at line 740) requires per-user discipline that the language can paper over."

**Aiml's three-question concession after the nesting and exit-footgun arguments:**

> *(aiml)* "I conceded A2→A3, C1→C2, D1→D2 on the same argument. Once C2 wins on the nesting argument, the controller pattern is library-deliverable and the precedent locks. Once Q1 is forced toward 'stdlib papers over `Env.exit`,' that's only a real win if the mock_env shape can expose the captured exit semantics — which only D2 can. Internal consistency forced all three flips."

**Min's held positions (refused full concession):**

> *(min)* "A1→A2 yes, but I refuse to extend to A3. The `frozen_time` example at §4:1557 is *capability attenuation*, not testing — it's a sandbox showing that capabilities can be narrowed, not a precedent for shipping `mock_clock`. That doesn't pre-commit `mock_clock`. And on Q3: two simultaneously active mock clocks are forbidden by §4:1020 leftmost-wins. The nested case is fine because `mock_clock(now)` closes over `now` as a *value*, not via a module global — the majority is solving an imaginary problem and smuggling time-progression as a separate feature with no usage signal."

> *(min)* "On Q4 D1: D2's 'centralized exit/writes' is matched by a fully-specified D1 free fn that takes the initial map and returns a handler that records writes into a passed-in `List[(Str, Str)]` — the same shape as `capture_log(messages)`. A controller struct with stateful methods is *machinery* not *helper* per nyyt0s constraint #2; `MockEnv.writes()` re-litigates Q5's unanimous reject of `record_calls` for one specific effect."

**Sys's Q2 dissent (B2 stable position):**

> *(sys)* "B1 forces `std.testing` to import `std.time` + `std.env`, dragging Time/Env codegen into every test binary. That's a real binary-size cost — small per-test, but stdlib monomorphization decisions compound. B2 also pre-decides the convention before `std.fs.testing`, `std.net.testing` land, so we can correct course in those without having pre-claimed `std.testing.mock_fs`. The convention being set here ripples forward for every future effect mock."

**Web's procedural disambiguation on Q4:**

After Round 2, web's vote was conditional ("D1 if forced single shape, D2-hybrid if hybrid permitted"). The moderator sent a single-recipient DM asking for an unambiguous ballot. Web replied:

> *(web)* "Treat hybrid as an implementation refinement, not a vote question. D2. The free-fn `mock_env_with(init)` companion is a stdlib follow-up to consider when writing prose, not a panel question. Lock D2 as the canonical shape."

**Devops's stable D1 position (Phase D Round 2):**

> *(devops)* "§4:1339 `Handler[E]` → `Handler[E.Sub]` projection covers `Env.Read` for free — the free-fn `mock_env_with(init) -> Handler[Env]` projects implicitly when a test only needs `! Env.Read`. capture_log shape symmetry is preserved. D2 builds machinery where a free-fn suffices. The 'mid-test mutation' use case is one `.set` away from a controller, but it's also one re-call away from a free-fn, and the latter is one less concept."

Termination: 4 of 6 stable signals after Round 1 of Phase B; 5 of 6 after Round 2. Phase C silent vote opened with all six panelists.

#### Phase C — Final vote (Round 1)

**Q1 — scope: 4-1-1 R1 → A3 wins with one abstention and one minority position.**

- **Web:** A3 — *"Ship both. The 90% test that wants either also wants the other 60% of the time; splitting them by ticket invites a stretched-out rollout with conflicting conventions between the two."*
- **PLT:** A3 — *"Both effects have unanimous Env-handler precedent in §4:730 and Time-frozen precedent in §4:1557. The structural argument for one applies equally to the other; shipping only one is internally inconsistent."*
- **DevOps:** A3 — *"Diagnostic surface is identical for both. LSP and `--blink-trace` already see Time/Env effects equally; the helper-factory surface should match."*
- **AI/ML:** A3 (revised from A2) — *"Once Q3 forces controller-pattern, the nesting argument applies equally to Env, and shipping mock_clock alone leaves test authors to roll their own mock_env handler that hits the `Env.exit` footgun."*
- **Minimalism:** *(dissent)* A2 — *"Concede on `Env.exit -> Never` auto-delegation footgun (real 'stdlib resolves once' win the inline-handler pattern can't match); refuse to extend concession to A3 because §4:1557 `frozen_time` example is capability attenuation, not testing — that argument doesn't pre-commit `mock_clock`. Stdlib surface is a finite budget, every `mock_*` cements precedent for one-per-effect across §4."*
- **Systems:** A3 — *"Granted scope on both, the placement question (Q2) is where I dissent. Once placement is settled, A3 follows."*

(Round 1 tally as initially captured was 4-1-1; PHASE_8_TALLY.md records the Phase D R2 reconciled tally of 5-1.)

**Q2 — placement: 5-1 R1 → B1 wins.**

- **Web:** B1 — *"`capture_log` already lives in `std.testing` per the 4-1 capture_log decision; splitting Time/Env to per-effect submodules is incoherent and forces 3 import lines per test."*
- **PLT:** B1 — *"nyyt0s constraint #2 satisfied — pure library helpers, no intrinsics. The handler-factory pattern is general enough that the central module is the right home regardless of which effect it factories."*
- **DevOps:** B1 — *"Single import path lets the LSP and `blink doc` surface all test helpers under one namespace. Per-effect submodules fragment the discovery story."*
- **AI/ML:** B1 — *"One import line for `import std.testing.{capture_log, capture_print, mock_clock, mock_env}` is the lowest-token-cost shape; per-effect submodules multiply import lines by N effects."*
- **Minimalism:** B1 — *"Concede on the import-line argument. The constraint here is 'is `std.testing` a coherent module,' and the answer is yes — handler factories for tests are one concept."*
- **Systems:** *(dissent)* B2 — *"B1 forces `std.testing` to import `std.time` + `std.env`, dragging Time/Env codegen into every test binary. B2 also pre-decides the convention before `std.fs.testing`, `std.net.testing` land — corrected at this scale costs less than the binary-size compounding effect."*

**Q3 — mock_clock shape: 4-2 R1 → C2 wins (will become 5-1 in Phase D after aiml's concession).**

- **Web:** C2 — *"`.advance(d)` covers testing timeouts and retry loops, which is the single largest mock_clock use case in JS/Python test suites. Controller pattern owns time-progression cleanly."*
- **PLT:** C2 — *"Module-level `mut` state breaks under nested `with` blocks (§4:1012/1020); per-instance struct state isolates correctly. `Cleanup` precedent in `lib/std/testing.bl` proves controller pattern is library-deliverable."*
- **DevOps:** C2 — *"Controller pattern gives the LSP a single discoverable namespace: `mc.handler()`, `mc.advance(d)`, `mc.elapsed()`. Free-fn forces three separate symbols with no organizing principle."*
- **AI/ML:** C1 R1 *(will flip in Phase D)* — *"Free-fn matches capture_log precedent; controller pattern adds a divergence that costs learnability. The two-shape API is a learnability disaster unless documented explicitly."* Phase D concession: *"Conceded C1→C2 on the nesting argument; the same argument plus the `exit` footgun forced internal consistency on Q1 and Q4."*
- **Minimalism:** *(dissent)* C1 — *"Two simultaneously active mock clocks are forbidden by §4:1020 (leftmost wins); nested case is fine because `mock_clock(now)` closes over `now` as a value, not via module global. Majority is solving an imaginary problem and smuggling time-progression as a separate feature with no usage signal."*
- **Systems:** C2 — *"Controller pattern's per-instance state has the cleanest codegen story — no thread-local, no module-level globals to clear between tests."*

**Q4 — mock_env shape: 3-3 R1 tie → triggers Phase D.**

- **Web:** D2 *(conditional, resolved to D2 via DM)* — *"Mid-test `env.set(...)` between calls to CUT is a 50% case; the controller's `.set()` method exposes it without re-creating the handler."*
- **PLT:** D2 — *"Same nesting argument as Q3 plus `MockEnv.handler()` centralizes the correct `exit` op (panic with captured code) in one method. Mid-test mutation and `writes()` recording are features only a controller can expose without becoming D3-with-extra-steps."*
- **AI/ML:** D1 R1 *(will flip in Phase D)* — *"D2's `.writes()` re-litigates Q5's unanimous reject of `record_calls` for one specific effect; that's a bad precedent."* Phase D concession: *"D1→D2 — internal consistency demands it once C2 wins. The recording is per-instance state, not a polymorphic `record_calls`."*
- **DevOps:** *(dissent)* D1 — *"§4:1339 projection covers Read for free; capture_log shape symmetry; D2 builds machinery where a free fn suffices."*
- **Minimalism:** *(dissent)* D1 — *"D2's 'centralized exit/writes' matched by fully-specified D1 free fn; controller struct with stateful methods is *machinery* not *helper* per nyyt0s constraint #2; `MockEnv.writes()` re-litigates Q5 unanimous reject of `record_calls`."*
- **Systems:** D2 — *"Controller pattern's `.handler()` method centralizes the `Env.exit` panic-with-captured-code shim in one place. Free-fn with module-level `mut` for captured exit code is the C1-style nesting bug all over again."*

**Q5 — record_calls: 6-0 R1 unanimous → E1 wins.**

- **Systems:** E1 — *"Constraint #9 (no effect-kinded generics in v1) makes polymorphic `record_calls[E]` literally inexpressible. Not a design preference, a typing-rule fact."*
- **Web:** E1 — *"A per-effect surrogate (`record_log_calls`, `record_env_calls`, ...) fragments the API; the inline counting-handler pattern is shorter than a call site to a stdlib `record_calls` would be."*
- **PLT:** E1 — *"Constraint #9 closes this question. `Handler[E]`-polymorphic helpers are out until effect-kinded generics are spec'd."*
- **DevOps:** E1 — *"No diagnostic surface improves from this — the inline `handler E { fn op(...) { calls.push(...) } }` pattern at the use site is already what the LSP suggests when an effect is missing a handler."*
- **AI/ML:** E1 — *"Per-effect surrogates multiply decision points; the inline counting-handler is the lowest-token shape for the rare cases that need it."*
- **Minimalism:** E1 — *"Dead on arrival. Constraint #9 makes the generic version impossible, and the per-effect version trades one stdlib symbol for N stdlib symbols."*

#### Phase D — Round 2 (Q1, Q3, Q4 triggered by 4-2-or-closer results)

The Q4 3-3 tie triggered Phase D automatic re-debate. Q1 and Q3's 4-2 results also fell under the trigger.

**Aiml's three-question internal-consistency concession** (already quoted in Phase B above) carried Q1 to 5-1 (A3), Q3 to 5-1 (C2), and Q4 from 3-3 toward D2 majority.

**Web's procedural disambiguation** on Q4 (DM-confirmed D2 over conditional D1/D2-hybrid Round 1 ballot) is the fourth D2 vote.

**plt and devops did not file Phase D Round 2 ballots** despite multiple pings. Per ballot ultimatum, their stable Round 1 positions are recorded as votes. plt held A3/C2/D2; devops held A3/C2/D1.

**Min held all three minority positions** (A2, C1, D1) on the arguments quoted in Phase B above.

Final Round 2 tallies:

- **Q1: 5-1 R2 (A3 wins).** Majority: sys, web, plt, devops, aiml. Dissent: min (A2).
- **Q3: 5-1 R2 (C2 wins).** Majority: sys, web, plt, devops, aiml. Dissent: min (C1).
- **Q4: 4-2 R2 (D2 wins).** Majority: sys, web, plt, aiml. Dissent: devops (D1), min (D1).

#### Step 8.5 — AI-First Review

| Criterion | Pass/Fail | Notes |
|-----------|-----------|-------|
| Learnability | **PASS** | Two coherent shapes (free-fn for stateless sinks, controller for stateful mocks) — must be documented explicitly in §6 prose so AI doesn't conflate them. |
| Consistency | **CONCERN-PASS** | Diverges from `capture_log` free-fn shape, but the divergence is principled (stateful vs stateless effects). aiml's concern about explicit "controller for stateful, free-fn for sinks" rule must land in §6 prose. |
| Generability | **PASS** | `with mock_clock(t).handler() { body }` and `with mock_env(map).handler() { body }` are mechanically generable from one schema. |
| Debuggability | **CONCERN-PASS** | aiml flagged `mock.advance(d)` outside a `with` block as a likely AI mistake (expecting global mutation); diagnostic for "method called on inactive mock controller" should be planned. |
| Token Efficiency | **CONCERN-PASS** | Controller pattern adds ~5 tokens vs free fn for the simple stamp-a-timestamp case. web's suggested `frozen_clock(i: Instant) -> Handler[Time]` companion free fn covers the trivial path; tracked as a follow-up. |

Score: 5/5 pass with three concerns documented in prose. No 2+ failures → proceeded to spec writing.

### Final Spec

```blink
// std.testing module additions

pub type MockClock {
    mut now: Instant
    mut slept: List[Duration]
}

impl MockClock {
    pub fn handler(self) -> Handler[Time] {
        handler Time {
            fn read() -> Instant { self.now }
            fn sleep(d: Duration) { self.slept.push(d) }
        }
    }

    pub fn advance(self, d: Duration) {
        self.now = Instant_add(self.now, d)
    }

    pub fn elapsed(self) -> List[Duration] {
        self.slept
    }
}

pub fn mock_clock(start: Instant) -> MockClock {
    MockClock { now: start, slept: [] }
}

pub type MockEnv {
    mut vars: Map[Str, Str]
    mut writes: List[(Str, Str)]
}

impl MockEnv {
    pub fn handler(self) -> Handler[Env] {
        handler Env {
            fn args() -> List[Str] { [] }
            fn var(name: Str) -> Option[Str] { self.vars.get(name) }
            fn vars() -> Map[Str, Str] { self.vars }
            fn cwd() -> Str { "/" }
            fn set_var(name: Str, value: Str) {
                self.vars.set(name, value)
                self.writes.push((name, value))
            }
            fn remove_var(name: Str) {
                self.vars.remove(name)
                self.writes.push((name, ""))
            }
            fn exit(code: Int) -> Never {
                panic("mock_env: env.exit({code}) called under test")
            }
        }
    }

    pub fn set(self, name: Str, value: Str) {
        self.vars.set(name, value)
    }

    pub fn writes(self) -> List[(Str, Str)] {
        self.writes
    }
}

pub fn mock_env(initial: Map[Str, Str]) -> MockEnv {
    MockEnv { vars: initial, writes: [] }
}
```

Locked design points:

- **Ship `mock_clock` + `mock_env` in central `std.testing`.** Reject `record_calls[E]` outright.
- **Both are controller structs**, not free-fn factories — `MockClock`/`MockEnv` with an `.handler()` method. The handler closes over `self`, so nested `with mock_clock(t1).handler() { ... with mock_clock(t2).handler() { ... } ... }` isolates correctly (per-instance state, not module-level `mut`).
- **`MockEnv.handler().exit(code)` panics with the captured code** rather than auto-delegating to real `env.exit` — this is the load-bearing reason `mock_env` ships at all (the alternative is every test author hitting the test-runner-terminates footgun once and writing a five-line shim).
- **`MockClock.advance(d)` mutates `now`** for time-progression tests (timeouts, retries). `MockClock.elapsed()` returns the list of `time.sleep(d)` durations the code under test consumed.
- **`MockEnv.set(name, value)` mutates `vars`** for mid-test environment changes (no `writes` record). `MockEnv.writes()` returns the list of `(name, value)` tuples written by the CUT via `env.set_var` / `env.remove_var`.
- **`record_calls[E]` rejected.** Constraint #9 (no effect-kinded generics in v1) makes the polymorphic version inexpressible; per-effect surrogates fragment the API. The inline pattern is canonical: `let mut calls = []; with handler E { fn op(...) { calls.push(...) } } { ... }`.
- **Pattern rule for §6 prose:** **free-fn factory for stateless sinks** (`capture_log`, `capture_print`, `capture_eprint`), **controller struct for stateful mocks** (`mock_clock`, `mock_env`). This divergence is principled — sinks have no state to inspect beyond the captured list; mocks have time-progression / mid-test mutation that the controller pattern exposes via methods.
- **Future `MockFs`, `MockNet`, `MockRand` controllers** follow this same pattern when those effects ship. Tracked as follow-ups; explicitly coordinate with the random/seeded-RNG ticket (2jersy) so `MockRand` lands consistent.
- **Implementation deferred.** The spec lands now; a `type:feature` ticket carries the `lib/std/testing.bl` and runtime plumbing. `Handler[Time]` / `Handler[Env]` projection from non-IO effects is not yet exercised by stdlib; the implementation will need to land that path or document any gaps.

### Follow-ups Filed

1. `type:feature` — Implement `MockClock` / `MockEnv` in `lib/std/testing.bl` per this spec.
2. `type:spec` — Consider shipping `frozen_clock(i: Instant) -> Handler[Time]` companion free fn alongside `MockClock` for the trivial stamp-a-timestamp case (web's concession).
3. `type:spec` — Decide whether `MockEnv` exposes `.reads()` recording / scoped variants in addition to `.writes()` (min's "containment" condition).
4. `type:chore` — Coordinate with 2jersy (random/seeded RNG) so `MockRand` controller follows this pattern when it ships.
5. `type:spec` — Document the "free-fn for stateless sinks, controller for stateful mocks" rule in `sections/06_tooling.md` testing prose (already covered by §8.10.3 in this resolution; ticket exists as belt-and-braces in case prose drifts).
6. `type:spec` — Open tickets for `MockFs`, `MockNet` controllers when those effects ship.
