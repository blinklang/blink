[< All Decisions](../DECISIONS.md)

# Hash Seed Contract, Iteration Order & `--deterministic` — Design Rationale

Resolves br **tn17vz** — "Spec: Hash seed contract + iteration order + `--deterministic` CLI flag." Follow-up to the 42cvjx triage (which produced an informal 6-0 starting draft but ran no spec round) and to the `h0geg9` Map runtime work (per-K kops vtable, [decisions/map-runtime-architecture.md](map-runtime-architecture.md)).

### Grounding facts (verified in-tree before deliberation)

The runtime already ships the behavior under discussion; this deliberation ratifies and documents it, and closes the soundness gaps around it.

- **Default seed is already randomized.** `bootstrap/runtime_core.h` `blink_map_init_seed(deterministic)`: if `--deterministic`, seed `= 0`; else if env `BLINK_MAP_SEED` is set, `strtoull` base-10; else `time(NULL) ^ (getpid() << 16)`. The seed is mixed via `BLINK_HASH_INIT = blink_map_seed ^ 0xcbf29ce484222325` (FNV offset basis).
- `--deterministic` is wired for `build`/`run` (`src/cli.bl`, `src/codegen_types.bl:1693` `cg_deterministic`), **not** `blink test`.
- The Map method table already labels `keys()`/`values()` "(unspecified order)"; `trait Hash` had no contract comment.
- The Float-key diagnostic is **`E1400 MapKeyNotHashable`** (`src/diagnostics.bl:113`), and its message already states the NaN/bit-equality rationale and recurses into tuple element types. (The map-runtime doc's "default seed 0" and "E1301" were both stale.)

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in independent-proposal → mechanical-dedupe → open-debate → silent-vote rounds.

#### Phase A — Independent proposals (excerpted, with attribution)

- **Systems:** Entropy-seed by default; `--deterministic` pins seed 0 (compile-time, travels with the binary), `BLINK_MAP_SEED` is the runtime no-recompile pin. *"This is exactly Go's model: per-process random hash seed, iteration order deliberately randomized... Java is the cautionary tale — `HashMap` has no seed... CVE-2011-4858 hash-collision DoS."* On Float: explicit text grounded in IEEE-754 — *"say 'F32/F64 do not, because bitwise hashing violates the Eq/Hash contract under NaN and signed zero.'"*
- **Web/Scripting:** Keep randomized default; fight the Python prior loudly. *"A stable-but-unspecified order is the worst outcome... Randomizing per-run converts a latent time-bomb into an immediate, local, every-run failure."* Proposed `blink test` auto-pin so snapshots "just work" (later conceded). Float error must teach the NaN/precision reason + an alternative.
- **PLT:** Codify two laws. *"Law H1 (Coherence, seed-independent): a == b ⟹ a.hash() == b.hash(), at the trait level before any runtime mixing. Law H2 (Mixing is a bucketing-layer endofunction)... never observable through hash(), never stored, serialized, or compared."* Raised the load-bearing soundness point (Proposal 2a): *"'pure' first_key(m) can return different values in different runs... That is a soundness contradiction"* — iteration order must be removed from value-identity and order-dependent fns excluded from §4.16.3 memoization. Default randomized as the principled forcing function; `--deterministic` an explicit opt-in (CLI flag, not env var, on ocap grounds). Seed write-once pre-main, **not** an effect.
- **DevOps/Tooling:** Corrected the diagnostic code to **E1400** and confirmed env+flag both already ship. `BLINK_MAP_SEED` *"is the ONLY mechanism that crosses a `process_run`/exec boundary."* Proposed `W08xx`/`W1401 MapOrderAssumption` lint with machine-applicable `.sorted()` fix. Float exclusion needs explicit spec text: *"without spec text it's an implementation detail a future contributor could 'fix' by adding a Float Hash impl."*
- **AI/ML:** Ratify the randomized default already in the tree; spec must say **"randomized,"** not "unspecified" — *"'Unspecified' reads to a model as 'implementation-defined but probably insertion order like Python.'"* The Python-insertion-order training prior is the dominant AI-correctness risk; randomization makes order-dependence fail fast in the AI's own edit/test loop. `--deterministic` flag + `BLINK_MAP_SEED` env, no determinism env var.
- **Minimalism:** *"~90% a spec-text gap."* Everything ships already. Demote `--deterministic`/`BLINK_MAP_SEED` to tooling §8.10, not normative §3. Proposed deleting `BLINK_MAP_SEED` (M2, net −1 surface). Float already closed three times over — no new normative text. *"Go added zero knobs... and the ecosystem is healthier for it."*

#### Phase A.5 — Dedupe

Q1 default seed (settled 6-0 randomized); Q2 `--deterministic` surface (A both / B flag-only / C demote+delete-env); Q3 does `blink test` pin (A randomized / B auto-pin); Q3-coupling does `--seed` pin both (YES / NO / PARTIAL); Q4 iteration-order × purity (plt, uncontested); Q5 Float spec text (A explicit / B cross-ref); Q6 soundness laws (plt, uncontested); Q7 order-dependence lint.

#### Phase B — Debate highlights

- **Web concedes Q3 (auto-pin → randomized):** *"My W2 auto-pin had a fatal flaw I underweighted: if blink test pins but blink run randomizes, tests would pass on order-dependent code that then breaks in production — the exact silent-week-3 bug I argued against. Auto-pinning the test runner manufactures the false confidence I was trying to kill."* Held a hard requirement: a prominent reproduce line on failure.
- **PLT tightens Q4 to a syntactic conservative rule:** *"The compiler does not need to [know the return derives from unsorted order], and must not try... If a function's body contains an iteration over a Map/Set... that function is excluded from the truly-pure set. Full stop. No dataflow... It is one predicate in an existing pass."* Sys called this *"the sharpest systems consequence in the whole deliberation."*
- **Min drops C (delete env var):** *"sys answered my 'name the user story' question on the record... reproduce a field-crash ordering without recompiling... That's a genuine, distinct user need for a self-hosting compiler that ships binaries. I withdraw the deletion."* Banked the placement win (§8.10, not §3).
- **Q2 convergence:** all six land on A-substance with §8.10 placement — normative contract in §3.6, mechanisms documented under tooling §8.10. PLT drops flag-only B; Min drops delete-C.
- **Q3-coupling stays split.** DevOps: *"A reproduce hint that lies is worse than no hint."* AI/ML: *"Coupling re-introduces the Q3-B hazard through the back door... the name `--seed` is itself a naming hazard."* Web: *"Full coupling is one sentence; PARTIAL is a truth table."* DevOps later reframed his real need as a mandatory printed `BLINK_MAP_SEED=…` reproduce line, satisfiable without coupling.

#### Phase C — Final vote

- **Q1: Ratify randomized-per-process default?** (**6-0 RATIFY**)
  - **sys:** *"Predictable hash seeds are a HashDoS liability... Per-process entropy is the correct systems default."*
  - **web:** *"Randomization is the only default that makes 'don't rely on order' a lived experience rather than a doc footnote."*
  - **plt:** *"Map/Set are unordered abstractions; iteration order was never part of their denotation."*
  - **devops:** *"A fixed seed is a CI honeypot... the only default that keeps our own self-host CI honest."*
  - **aiml:** *"'Randomized' is an active signal that flips the [Python insertion-order] prior and makes the hazard learnable from one read."*
  - **min:** *"Already in tree, zero new surface, and it does the pedagogical work for free."*

- **Q2: `--deterministic` surface?** (**6-0 A** — keep flag + `BLINK_MAP_SEED`; contract §3.6, mechanisms §8.10)
  - **sys:** *"The env var is the load-bearing knob for CI... deleting it removes the one lever ops people actually reach for."*
  - **min:** *"I conceded the user story... deletion is a real subtraction with a real cost. I take the placement win instead."*
  - (web, plt, devops, aiml all A on the same grounds: env var is the no-recompile / cross-process reproduction path.)

- **Q3: Does `blink test` pin the seed?** (**6-0 A** — randomized by default, seed printed, `--deterministic` opt-in wired into test)
  - **devops:** *"Auto-pinning just relocates the Q1 honeypot into the test runner — golden tests would pass forever on a frozen order and rot."*
  - **aiml:** *"Auto-pin... is the exact environment where an AI self-corrects against green tests, so it learns 'Map order is stable' and ships order-dependent code."*

- **Q3-coupling: Does `--seed` pin BOTH RNG and hash?** (**3 NO / 2 BOTH / 1 PARTIAL → user broke tie for NO, cross-ref only**)
  - **sys:** NO (PARTIAL acceptable) — *"RNG seed and hash seed are different subsystems with different observability contracts."*
  - **aiml:** NO — *"Coupling re-introduces the auto-pin hazard through the back door, and the name `--seed` is itself a naming hazard."*
  - **min:** NO — *"Two orthogonal knobs with a cross-ref is smaller in concept-count than one overloaded knob with two meanings."*
  - **web:** BOTH — *"One `--seed` reproduces the whole run is one sentence a human can hold in their head; PARTIAL is a truth table nobody will remember at 2am."*
  - **devops:** BOTH (via derived hash sub-seed) — *"A reproduce hint that lies is worse than no hint."*
  - **plt:** *(PARTIAL, non-blocking)* — *"`--deterministic` is the umbrella... I will not break consensus over it."*
  - **User tiebreak:** NO, **cross-ref sentence only** (no mandatory reproduce-line print). `--seed` stays RNG-only; map order is governed solely by `--deterministic`/`BLINK_MAP_SEED`. Smallest surface.

- **Q4: Iteration-order × purity (§4.16.3)?** (**6-0 ADOPT**)
  - **plt:** *"A function whose result can vary with non-denotational iteration order is not referentially transparent... A syntactic over-approximation is the right call: purity must be conservative."*
  - **sys:** *"Memoizing it would cache a result keyed to one process's seed and serve it across runs that disagree."*

- **Q5: Float exclusion spec text?** (**4-2 A**, one normative sentence; aiml + min dissent, both accept as floor — soft consensus)
  - **sys/web/plt/devops:** A — *(devops)* *"trait Hash today has NO contract comment, so nothing stops a future contributor from adding a Float impl and silently breaking determinism."*
  - **aiml:** *(dissent)* B — *"E1400 already carries the normative weight... I'll accept ONE permanence clause if sys/plt insist."*
  - **min:** *(dissent)* B — *"A fourth normative sentence... implies the rule is a fresh, revisable policy rather than a settled consequence,"* but *"will NOT block."*

- **Q6: Soundness laws H1/H2 + seed lifecycle?** (**6-0 ADOPT** — laws in this rationale doc, one normative sentence in §3.6)
  - **plt:** *"Separating H1 (the equality-coherence law, seed-independent) from H2 (seed as non-semantic bucketing perturbation) guarantees the seed can never leak into observable value semantics."*
  - **aiml:** *"No seed-exposing API is especially important AI-first — if the seed were reachable, models would write code that branches on it."*
  - **min:** Endorsed substance; named laws stay in the rationale doc, **not** §3 (*"formalism inflation"*) — PLT agreed.

- **Q7: Ship `W1401 MapOrderAssumption` lint?** (**5-1 SHIP**; min dissent — soft consensus with follow-up)
  - **sys/web/plt/devops/aiml:** SHIP, scoped: warning never error, intraprocedural/direct-flow only, machine-applicable `.sort()`/`.sorted()` fix, default-on. The majority's concern fields all echo the false-positive risk and commit to demote-to-opt-in if it proves high.
  - **min:** *(dissent)* DEFER — *"a new maintained analysis surface with inherent false-positive risk, and the randomized default already teaches the lesson at runtime with zero maintenance. YAGNI — defer until a br:friction signal."*

### AI-First Review (Step 8.5) — 5/5 pass

1. **Learnability** — pass. One rule ("randomized per process, sort to stabilize"); the word "randomized" is chosen specifically to override the Python insertion-order prior.
2. **Consistency** — pass. `blink test` randomized + seed-printed mirrors the §8.10.4 `--seed` RNG story; `W1401` clusters with `E1400`.
3. **Generability** — pass. Randomized default fails order-dependent code in the AI's own loop; W1401 catches the positional `keys()[N]` pattern with a one-keystroke fix.
4. **Debuggability** — pass. Immediate local failure; `BLINK_MAP_SEED=N` reproduces a flake without recompiling; E1400 carries the rationale.
5. **Token efficiency** — pass. `.sort()` only when order matters; one flag + one env var; Float = one sentence.

### Final Spec

Normative, §3.6 (Hash Contract and Seeding):

```blink
trait Hash: Eq {
    fn hash(self) -> U64   // pre-seed; satisfies a == b ⟹ hash(a) == hash(b), seed-free
}

// Stable iteration requires an explicit sort — order is randomized per process.
let mut names = scores.keys()
names.sort()
for name in names { io.println("{name}: {scores.get(name).unwrap()}") }
```

Mechanisms, tooling §8.10.6:

```
blink run app.bl                       # entropy seed (time ^ pid); order varies per run
BLINK_MAP_SEED=42 blink run app.bl     # runtime pin, no recompile, crosses process boundaries
blink run --deterministic app.bl       # pin 0, baked into the binary; env ignored
blink test --deterministic             # golden / self-host opt-in (newly wired into test)
```

Precedence: `--deterministic` (0) > `BLINK_MAP_SEED` (N) > entropy.

**Locked design points:**

- Hash seed randomized per process by default (ratifies shipped behavior). Spec says **"randomized,"** not "unspecified."
- **H1 (coherence, seed-free):** `a == b ⟹ a.hash() == b.hash()` at the trait level, independent of any seed.
- **H2 (mix is bucketing-layer-only):** the seed perturbs only bucket placement; never observable through `hash()`, never stored/serialized/compared.
- Seed lifecycle: process-global, write-once, set pre-`main` from runtime init. **Not** an effect, **not** a capability; no Blink API reads or sets it (no `map.seed()`, no `Hash.SetSeed`).
- Iteration order ∉ `Map`/`Set` value-identity; equal-entry maps are `==`-equal regardless of order.
- Purity (§4 truly-pure analysis): any function that iterates a `Map`/`Set` is **conservatively** excluded from memoization/reordering — one syntactic predicate, no dataflow, `.sort()` does not rescue.
- `--deterministic` flag (pins 0; wired into `build`/`run`, **and now `test`**) + `BLINK_MAP_SEED` env (decimal, runtime, crosses process boundaries). Contract in §3.6; mechanisms in §8.10. Reproducibility mechanisms, **not** security controls.
- `--seed` (§8.10.4 test RNG) and the hash seed are **independent** — `--seed` does not pin map order. One cross-reference sentence; no flag coupling (user tiebreak).
- Float (and any type transitively containing one) rejected as a `Map`/`Set` key at type-check as `E1400 MapKeyNotHashable` — a permanent contract (one normative sentence) grounded in Eq/Hash coherence (`-0.0 == 0.0`, distinct bit patterns).
- `W1401 MapOrderAssumption` — default-on warning, intraprocedural/direct-flow only, machine-applicable `.sorted()` fix, never an error. Indirect sorting is not analyzed and will not warn (documented bound).

### Dissents recorded

- **Q5 (4-2):** AI/ML and Minimalism preferred a cross-reference over a new normative sentence; both explicitly accepted the one-sentence outcome as a floor.
- **Q7 (5-1):** Minimalism preferred deferring the lint until a friction signal, on YAGNI/maintenance-surface grounds; the majority ships it but shares the false-positive concern and commits to revisit (demote to opt-in) if the rate proves high.
- **Q3-coupling (3-2-1):** No panel majority; the user broke the tie for NO + cross-ref only.
