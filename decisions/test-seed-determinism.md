[< All Decisions](../DECISIONS.md)

# Test Seed Determinism (`--seed`, `mock_rand`) — Design Rationale

Resolves br **2hpc98** — "Deterministic randomness in tests (`blink test --seed`, `mock_random`/`seeded_rng`)".

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated over Phase A (independent proposals) → Phase A.5 (mechanical dedupe) → Phase B (open debate) → Phase C (silent vote). No Phase D triggered: Q1 was lopsided 5-1 and Q2/Q3/Q4/Q1-sub were unanimous.

#### Phase A — Independent proposals (excerpted, with attribution)

- **Systems (sys):** Proposed `blink test --seed <u64>` as a thin runner flag that flows the value down to property-test elaboration as an explicit argument (no thread-local read). For the RNG mock: a `MockRand` controller struct mirroring `MockClock`/`MockEnv` per j21b6c, with a `.handler() -> Handler[Rand]` method, `.draws()` debug counter (debug-only — *"one draw per op call; not stable across compiler versions"*), and `.reseed()`. Backing PRNG: xoshiro256** (*"fast, well-distributed, small state — what you want for a deterministic test RNG"*).
- **Web/Scripting (web):** Strongly in favor of `--seed`. *"Without `--seed`-in-failure-output, 'my prop test fails in CI, how do I reproduce locally?' is a daily Stack Overflow question. With it, it's a copy-paste."* Wanted the rerun line printed in **every** failure output mode (human, `--json`, `--quiet`, color-stripped CI). Accept both `0xDEADBEEF` and decimal on input; print as `0x` + 16 hex digits zero-padded. On naming: family symmetry with `mock_clock`/`mock_env` — *"two names = Stack Overflow generator."*
- **PLT (plt):** Initially proposed option C (no `--seed` flag; require explicit `mock_rand(seed)` at the test site for determinism) on soundness grounds — worried `--seed` would read as a thread-local or ambient effect. Moved to A in Round 1 after sys/web clarified the seed flows from runner to property as an explicit value at argument-elaboration time, not via implicit handler installation. On Q2: *"the controller's `.handler()` method subsumes the free-fn factory (call it and discard the controller for the stateless case), so A dominates B and C."* Raised `.handler()` idempotency as a spec must-answer: *"is `MockRand.handler()` callable multiple times, and if so, do the resulting handlers share state or fork it?"*
- **DevOps/Tooling (devops):** Strong A on `--seed`. Pushed two adjacent asks: `--rerun-failed` flag (reads last NDJSON, replays failed tests at their recorded per-test seeds — distinct from `--seed`), and an `unseeded_rand_in_test` lint (warn when a test uses the real `rand` handler without seeding). Also requested `decisions/test-seed-derivation.md` so users can hand-compute per-test seeds for offline reproduction. Wanted `--rerun-failed` in 2hpc98 scope; panel declined to vote on it explicitly — filed separately.
- **AI/ML (aiml):** Voted A on Q1-sub (SplitMix64) on the basis of *"LLM/cross-language familiarity — proptest, JDK SplittableRandom, and the splittable-RNG papers all use it; an AI reading the spec immediately recognizes the construction."* Made A on Q2 conditional on `.draws()` being marked *"debug-only, not stable across compiler versions"* to prevent users coupling regression tests to PRNG internals. Insisted the seed banner survives `--quiet`/`--json`/color-stripped CI: *"the reproduction contract collapses otherwise."* Flagged that `hash(property_name)` must be pinned to a specific stable hash, since *"different compiler versions will derive different sub-seeds from the same suite seed otherwise."*
- **Minimalism (min):** Voted B on Q1 (reject `--seed`). Stance: *"pure-addition without removal, no usage signal, Hypothesis's `--hypothesis-seed` is a known CI footgun across versions, and Q5's rerun line + future regression-file ticket cover the actual reproducibility need without a global mutable knob."* Voted A on Q1-sub conditionally (*"only meaningful if Q1-A wins"*) and A on Q2/Q3/Q4 — full consensus on every other question. Strongly advocated filing the persisted-counterexamples (proptest-regressions style) follow-up immediately rather than deferring indefinitely.

#### Phase A.5 — Dedupe

After grouping:

- **Q1 (ship `--seed`?):** Two distinct options. A = ship the flag; B = reject (min). C from plt collapsed into A after Round 1 clarification.
- **Q1-sub (sub-seed derivation):** Two options. A1 = `SplitMix64(suite_seed, hash(property_name))`; A2 = SipHash-2-4-only. Variation flagged: which hash, whether the hash includes module prefix.
- **Q2 (RNG mock shape):** Three options pre-debate. A = `MockRand` controller; B = free-fn `mock_rand(seed) -> Handler[Rand]`; C = effect-handler factory only. B and C collapsed into A after plt's "controller subsumes factory" argument.
- **Q3 (naming):** Two options. A = `mock_rand` only; B = `seeded_rng` synonym.
- **Q4 (defer pending 2jersy?):** Two options. A = resolve now with stated assumption; B = block on 2jersy.
- **Q5 (rerun line format):** No distinct alternatives raised — converged in Phase B on `rerun: blink test --seed <0xHEX> --filter '<name>'` + NDJSON `seed`/`reproduce` fields.
- **Q6 (persist counterexamples now?):** Two options. A = defer to follow-up; B = ship in 2hpc98 scope. Panel converged on A with strong follow-up note from min.

#### Phase B — Debate highlights

- **plt's reversal on Q1 (C → A):** After sys's clarification that the seed value is threaded as an explicit argument through `prop_check` elaboration (*"the seed is part of the test's argument value, not a thread-local read at handler-install time"*), plt accepted that A doesn't introduce ambient effect-like behavior. *"If the typing rule treats the seed as a normal value parameter to the property's elaboration, my soundness objection dissolves — it's just a numeric input."*
- **plt on Q2 collapse (B/C → A):** *"The controller's `.handler()` method subsumes the free-fn factory: you can call `.handler()` and immediately discard the controller for the stateless case. So A dominates B and C — there's no scenario where B or C wins."*
- **sys vs aiml on Q1-sub (A1 vs A2):** sys argued *"SplitMix has the right algebraic property — independent, well-distributed substreams from one parent. Plain `hash(name)` collision concerns are overstated for the small per-binary name space; SplitMix64 mixing absorbs minor key-quality issues. A2's siphash adds ~20ns vs ~3ns for nothing."* aiml's response: *"siphash is the right choice for the **identity** layer — it's the keyed hash that resists collisions across compiler versions and stays stable under renames. Use both: siphash24 for `hash(name)`, splitmix64 for mixing with the suite seed."* The panel converged on the composite formula `splitmix64(suite_seed XOR siphash24(property_name))` — neither pure A1 nor pure A2, but the natural synthesis.
- **min's standing dissent on Q1:** held to the end. *"Pure-addition without removal. The actual reproducibility problem is solved by Q5's rerun line and the future regression-file ticket. `--seed` adds a global mutable knob and a CI footgun pattern other ecosystems have already lived through."* Acknowledged majority and agreed to vote A on every other question.
- **aiml's conditional on Q2:** *"I'll vote A if and only if `.draws()` is marked debug-only and not stable across compiler versions. Otherwise users will write regression tests against draw counts and we will be stuck with whatever PRNG we ship in v0.1 forever."* Sys accepted the condition; spec text reflects it.

#### Phase C — Final vote

- **Q1: Ship `blink test --seed <u64>`?** (**5-1**, min dissent)
  - **sys:** A — *"the failure-output rerun line is the load-bearing part of the proposal; the flag is the thing that line refers to. They ship together or not at all."*
  - **web:** A — *"copy-paste reproduction is the daily ergonomic win. Hypothesis's footgun history is a banner-presentation problem, not a flag problem."*
  - **plt:** A — *"argument-threading model passes the soundness bar."*
  - **devops:** A — *"and we get `--rerun-failed` for free as a follow-up that reads the seeds the NDJSON already records."*
  - **aiml:** A — *"conditional on the rerun line surviving every output mode."*
  - **min:** *(dissent)* B — *"pure-addition without removal, no usage signal, Hypothesis's `--hypothesis-seed` is a known CI footgun across versions. Q5's rerun line + future regression-file ticket cover the actual reproducibility need without a global mutable knob."*

- **Q1-sub: Sub-seed derivation?** (**6-0** for A1+A2 composite: `splitmix64(suite_seed XOR siphash24(property_name))`)
  - **sys:** *"SplitMix64 mixing of (suite_seed XOR siphash24(name)) — siphash for stable identity, splitmix for stream mixing."*
  - **web:** *"the bare property name (no module prefix) is right — survives module renames, which is what users actually do."*
  - **plt:** *"composite formula is the principled answer; needs `prop_check` site to error on duplicate property names within a module."*
  - **devops:** *"document the exact derivation in a separate decision file so users can hand-compute it."*
  - **aiml:** *"siphash-2-4 is the right keyed hash — stable, fast, well-known. SplitMix64 is the familiar mixer."*
  - **min:** A1 conditionally — *"only meaningful if Q1-A wins. Given that, this is the right formula."*

- **Q2: RNG mock shape?** (**6-0** for `MockRand` controller struct)
  - **sys:** A — *"j21b6c family rule: stateful mock → controller struct. Breaking the pattern for `Rand` alone introduces incoherence between `MockClock`/`MockFs`/`MockRand` for zero benefit."*
  - **web:** A — *"if I learn `mock_clock` I expect `mock_rand` to work the same way. Anything else is a Stack Overflow generator."*
  - **plt:** A — *"controller subsumes factory; A dominates B and C."*
  - **devops:** A — *"controller gives us a handle for `.draws()` debugging, which the free-fn form would force us to expose globally."*
  - **aiml:** A — conditional on `.draws()` debug-only marking.
  - **min:** A — *"family symmetry is genuinely foundational here, not ergonomic sugar. The controller pattern was already settled in j21b6c."*

- **Q3: Naming?** (**6-0** for `mock_rand` only; reject `seeded_rng`)
  - Unanimous on family-symmetry grounds. Verbatim from **web** carried the room: *"`mock_clock`, `mock_env`, `mock_rand` are one mental model; two names = Stack Overflow generator."*

- **Q4: Defer pending 2jersy?** (**6-0** to resolve now with stated assumption)
  - **sys:** A — *"`Rand` effect ops are already decided in §4.3 (`rand.int/float/bytes`); 2jersy concerns stdlib module shape (distributions, helpers), not the effect surface this proposal touches. `MockRand.handler() -> Handler[Rand]` is forward-compatible regardless of 2jersy resolution."*
  - **min:** A — *"the assumption is well-scoped; only the `MockRand` body changes if 2jersy adds `rand.reseed` or `rand.fork`."*

- **Q5: Rerun-line format on failure?** No formal objection — converged in Phase B.
- **Q6: Persist counterexamples now (proptest-regressions style)?** No formal objection — deferred to a follow-up ticket per Q4's resolve-now-but-narrowly principle. min's standing follow-up ask logged.

### AI-First Review (Step 8.5)

Scored 5/5:

1. **Learnability** — pass. Single controller struct mirroring `mock_clock`/`mock_env`; one CLI flag with documented format.
2. **Consistency** — pass. Follows j21b6c family pattern exactly.
3. **Generability** — pass. The factory-method-handler triad is the same shape an AI has seen for every other Blink testing mock.
4. **Debuggability** — pass. `seed:` banner + `rerun:` line in every failure output mode; duplicate property names rejected at runner-load time with a specific diagnostic.
5. **Token efficiency** — pass. No new keyword; `--seed` flag is short; controller exposes three methods and no more.

### Final Spec

```blink
// std.testing — MockRand controller (mirrors MockClock/MockEnv per j21b6c)

pub type MockRand { mut state: U64, mut draw_count: Int }

impl MockRand {
    pub fn handler(self) -> Handler[Rand]
    pub fn draws(self) -> Int       // debug-only; not stable across compiler versions
    pub fn reseed(self, seed: U64)
}

pub fn mock_rand(seed: U64) -> MockRand
```

```blink
test "shuffle preserves length" {
    let r = mock_rand(0x1234)
    with r.handler() {
        let xs = [1, 2, 3, 4, 5]
        let ys = shuffle(xs)
        assert_eq(ys.len(), xs.len())
    }
    assert_eq(r.draws(), 4)
}
```

```
# Runner
blink test --seed 0xDEADBEEFCAFE1234
blink test                              # entropy-seeded; seed printed on failure

# Failure output (every mode — human, --quiet, --json, color-stripped):
FAIL  tests/test_parser.bl::reverse_is_involutive
  seed: 0xDEADBEEFCAFE1234
  shrunk input: [1, 2, 2, -9]
  rerun: blink test --seed 0xDEADBEEFCAFE1234 --filter 'reverse_is_involutive'

# NDJSON (--json):
{"event":"test_fail","name":"reverse_is_involutive","seed":"0xDEADBEEFCAFE1234",
 "reproduce":"blink test --seed 0xDEADBEEFCAFE1234 --filter 'reverse_is_involutive'", ...}
```

**Sub-seed derivation:** per-property seed = `splitmix64(suite_seed XOR siphash24(property_name))`. The SipHash-2-4 input is the bare property name (no module prefix) — stable under module renames. The runner errors on duplicate property names within a module, since the derivation collides silently otherwise.

**Locked design points:**

- `blink test --seed <u64>` flag; accepts `0xHEX` or decimal; prints as `0x` + 16 zero-padded hex digits.
- Entropy-seeded default; seed banner + rerun line surfaces in every failure output mode.
- `MockRand` controller struct per j21b6c family rule (not free-fn returning `Handler[Rand]`).
- `mock_rand` naming only; `seeded_rng` rejected.
- `.draws()` is debug-only and explicitly **not** stable across compiler versions.
- `.handler()` idempotency: each call returns an independent handler bound to the same controller state (so `.draws()` counts across them).
- Resolves now under the stated 2jersy assumption: `Rand` is a leaf effect, `rand.int`/`rand.float`/`rand.bytes` are the ops, no user-visible `rand.seed(u64)` op. If 2jersy adds `rand.reseed`/`rand.fork` later, only the `MockRand` body changes.
- PRNG implementation-defined (xoshiro256** in v0.1) — spec text deliberately leaves the algorithm open.

### Out-of-scope follow-ups

Filed as separate `br` tickets:

- 2jersy alignment task (after 2jersy resolves)
- Persisted counterexamples (proptest-regressions style)
- `--rerun-failed` flag
- `unseeded_rand_in_test` lint
- `decisions/test-seed-derivation.md` — devops's specific ask for an exact-derivation reference (this file partially covers it; the dedicated file documents the formula for offline hand-computation)
