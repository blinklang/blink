[< All Decisions](../DECISIONS.md)

# Map/Set Insertion Order Re-audit — Design Rationale

A batch of re-audits reopened earlier votes under one principle: "match LLM priors unless the deviation prevents a bug class." This one asked about the iteration order of `Map` and `Set`. The earlier panel ([Hash Seed & Iteration Order](hash-seed-iteration-order.md), 6-0) made the order random per process, so that code which depends on order fails early. It added `--deterministic`, `BLINK_MAP_SEED` and the `W1401 MapOrderAssumption` lint to pin or catch order. Python, JavaScript, Ruby and PHP all iterate a map in insertion order, so an LLM writes code that expects it.

This decision supersedes that file in part: iteration order, `--deterministic`, `BLINK_MAP_SEED`, W1401 and the purity exclusion. The seed stays random per process, and the hash contract (H1/H2) stays.

Facts before the vote:

- `blink_map` iterates its slot array (`bootstrap/runtime_core.h`), so today the seed decides the order.
- `SetOps` declares only `union`. No `intersection` or `difference` exists (§3.2.2, `lib/std/traits.bl`).
- §3.6.3: JSON `Object` keeps entries in input order and keeps duplicate keys; a lookup (`JsonValue.get`, derived `from_json`) takes the **first** entry with a key.
- No std serializer encodes a `Map` or `Set` yet: the §3.6.2 Type Mapping table has no `Map` row, and the derive work for it is an open ticket.

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in independent-proposal → debate → vote rounds. Quoted text is each panelist's own, verbatim. Local ticket IDs are replaced with a short name in square brackets.

All six seats proposed insertion order as their first choice in Phase A. The dedupe listed one option (INS) and six variations: V1 (`--deterministic` and `BLINK_MAP_SEED`), V2 (the purity exclusion), V3 (order of derived maps and sets), V4 (a sentence that `==` maps can give different results), V5 (serializer order) and V6 (the cost of the layout for `Set`).

#### Phase A — Independent proposals

- **Systems:**

> **I reopen Q1's *observable-order* half, not its HashDoS half.** Q1 conflated two things that the hardware keeps separate: the *hash seed* (which bucket a key lands in) and the *iteration order* (what the iteration loop walks). Today they are coupled only because `blink_map` iterates its slot array (bootstrap/runtime_core.h ~1412). That is a layout accident, not a security property.
>
> ## Proposal S1 — Insertion order by default, via the compact-dict layout (CPython 3.6+)
>
> Replace the slot-walk layout with two arrays:
> - **`index`**: sparse, `cap` entries of int8/16/32/64 (width picked by `cap`), each empty / tombstone / position in `entries`. Open-addressing probe runs here, bucketed by the **randomized seed**.
> - **`entries`**: dense `{hash: U64, key, value}` in insertion order. Iteration walks `entries[0..n]`.
>
> ```blink
> fn main() {
>     let mut ports: Map[Str, Int] = Map()
>     ports.insert("http", 80)
>     ports.insert("ssh", 22)
>     ports.insert("dns", 53)
>     ports.insert("http", 8080)          // update in place: keeps slot 0
>     io.println("{ports.keys()}")        // ["http", "ssh", "dns"] — every run, every seed
>     ports.remove("ssh")
>     ports.insert("ssh", 2222)           // re-insert goes to the end
>     io.println("{ports.keys()}")        // ["http", "dns", "ssh"]
> }
> ```
>
> **What it compiles to / costs:**
> - **Lookup:** one extra dependent load per probe (index → entry). Offset: the stored hash lets us compare `entry.hash == h` before the `kops->eq` **indirect call** — for `Str` keys that skips most memcmp calls through a function pointer. CPython measured net neutral-to-faster.
> - **Memory:** today `cap × (stride + 8 + 1)` ≈ 17 B/slot, ~30 B per live entry at our load factor. Compact: `cap × 1–4 B` index + `24 B × entries` with entries sized at ~⅔ cap. Equal or smaller, and the iteration-hot data is one dense block.
> - **Iteration:** faster — walks `n` dense entries, not `cap` slots, no per-slot `states[i]` branch.
> - **Rebuild:** cheaper — stored hash means no rehash / no `kops->hash` call per entry.
> - **Remove:** tombstone the entry (hole in `entries`), compact on rebuild. Amortized O(1), order preserved. I reject `swap_remove` semantics (Rust `IndexMap`): O(1) but it reorders, and a remove that moves other keys is a bug magnet.
> - **Arena:** unchanged — same `owner` arena holds both arrays.
>
> `Set` gets the same structure (it is a parallel struct today; one more port, no new design).
>
> ## Consequences for prior rulings
>
> - **Q1 seed:** stays randomized — for HashDoS only. The seed becomes **wholly unobservable** (H2 in its strongest form).
> - **Q2 `--deterministic` / `BLINK_MAP_SEED`:** no longer change program output. Keep as perf-reproduction knobs (reproduce a collision-heavy timing trace); move from the §3.6 contract to §8.10 as non-semantic.
> - **Q4 purity:** narrow, do not drop. `==` still ignores order (Container Equality), so two `==` maps can iterate differently; a memo keyed on `==` identity would serve the wrong result. Iterating fns are pure only if the memo key includes order. PLT should word this.
> - **Q7 `W1401`:** retire it. Never implemented, so zero cost; its premise is gone.
> - **Debug:** keep the 6-0 sorted `debug()` — the law `a == b ⟹ a.debug() == b.debug()` still needs it.
> - **JSON:** objects serialize in insertion order (matches JS/Python; round-trips stay stable).
>
> **Cost I accept:** spec "insertion order" binds the runtime forever; we can never switch to a faster unordered layout once users rely on it. Python and JS locked in and do not regret it. Go and Rust stay unordered and both carry a flaky-test history.
>
> ## Proposal S2 (fallback) — keep `Map` randomized, add `OrderedMap[K, V]` to std
>
> ```blink
> let mut m: OrderedMap[Str, Int] = OrderedMap()
> m.insert("a", 1)
> ```
>
> Systems-worse: two runtime structures, two kops paths, twice the mono instances, twice the bugs. And the default shape (`Map`) still defeats the LLM prior — every model writes a map and expects Python order. More surface for no runtime gain, since S1 is not slower. Fallback only.
>
> ## Cross-language
>
> - CPython 3.6 adopted the compact dict for **memory**; order came free, spec'd in 3.7.
> - V8 `Map` is spec-ordered (Tyler Close's deterministic hash table — same idea).
> - Rust `IndexMap` is the ecosystem's most-used ordered map; its iteration beats `HashMap`.
> - Go's randomization is a teaching device that cost every Go user a `sort.Strings(keys)` line.
>
> **Bottom line:** the layout that gives insertion order costs the same or less, keeps HashDoS resistance (seed stays random), and removes the flaky-test bug class instead of flagging it. Systems votes **S1**.

- **Web/Scripting:**

> I am reopening my own Q1 vote from [the hash-seed deliberation].
>
> # Web/Scripting — Phase A proposal ([this ticket])
>
> ## Position: reopen Q1. Make Map/Set iteration follow insertion order, and keep the hash seed randomized.
>
> In [the hash-seed deliberation] I voted for randomized order to fight the Python prior. I now think that was the wrong fix. The new re-audit principle is "match LLM priors unless the deviation prevents a bug class." Randomization does not prevent a bug class. It only makes the bug show up faster. Insertion order removes the bug class, because code that depends on order becomes correct code. Every JS or Python dev already believes "a map keeps the order I put things in." Python 3.7+ dict, JS `Map`/`Set`/object string keys, Ruby `Hash` and PHP arrays all work this way. So does Kotlin `mutableMapOf` (a LinkedHashMap). Go and Rust are the outliers, and both generate a steady stream of "why is my map order random" Stack Overflow questions.
>
> There is evidence in our own tree. `lib/std/http_types.bl:12` keeps headers in `Map[Str, Str]`, so we send response headers in a random order on each run. Nobody would write that bug on purpose.
>
> ### P1 — Insertion order is the contract (Map and Set)
>
> ```blink
> let mut scores: Map[Str, Int] = Map()
> scores.insert("carol", 7)
> scores.insert("alice", 9)
> scores.insert("bob", 3)
> scores.insert("alice", 10)      // update: alice keeps her position
> scores.remove("carol")
> scores.insert("carol", 1)       // re-insert after remove: goes to the end
>
> for (name, score) in scores.entries() {
>     io.println("{name}: {score}")   // alice, bob, carol — every run, every build
> }
> let names = scores.keys()           // ["alice", "bob", "carol"]
> ```
>
> Rules, copied from Python and JS so no one has to learn new ones:
> - `insert` on a new key appends it at the end.
> - `insert` on an existing key changes the value and keeps the position.
> - `remove` deletes the key. The other keys keep their relative order.
> - A re-insert after a remove goes to the end.
> - `Set` follows the same rules. This is stronger than Python's `set`, but it is what JS `Set` does, and it gives one rule for both types.
>
> ### P2 — Keep the randomized seed for bucketing only (Q1 seed, Q6 H2 stay)
>
> HashDoS protection comes from the seed, not from the order, so the seed stays randomized. The runtime moves to the CPython 3.6 "compact dict" layout: a seeded index table points into a dense entries array that iteration walks. With this change, H2 ("the seed is never observable") becomes true in practice, not only on paper. Systems will price the memory and tombstone cost. CPython found the compact layout smaller and faster to iterate than its old one.
>
> ### P3 — What changes downstream
>
> | Item | Change |
> |---|---|
> | §3.6 text "varies run to run … must not depend" | Replace with the insertion-order rules from P1 |
> | §3c Iterator table "unspecified order" | Change to "insertion order" |
> | `W1401 MapOrderAssumption` (not implemented) | Delete it. There is nothing left to warn about. |
> | `BLINK_MAP_SEED` | Delete it. Its user story was "reproduce a flaky order," which no longer exists. |
> | `--deterministic` | Keep it as the flag that pins the seed to 0, for anyone who wants bit-identical bucketing. Remove its order wording. |
> | `==` | No change: compares membership and ignores order, as Python `dict ==` does |
> | `debug()` sorted | No change. The law `a == b ⇒ a.debug() == b.debug()` needs it. |
> | Q4 purity exclusion | No change. Two `==` maps can still iterate in different orders, so a memo keyed on `==` would still be unsound. Users never see this rule. |
> | Sorted map type | Not needed (YAGNI). `scores.keys().sort()` still covers that case. |
>
> The `debug()` point needs one honest note. A Python dev will be surprised once that `debug()` prints sorted keys while `for` gives insertion order. That is a single, stable, documented surprise, and I would rather have it than give up the equality law.
>
> ### P4 (fallback, if the panel keeps a randomized default)
>
> If the panel keeps a randomized default, ship `OrderedMap[K, V]` and `OrderedSet[T]` in `lib/std`, and convert http headers to them. I rank this well below P1. Most users will reach for `Map` first, hit random order, and then ask on Stack Overflow why there are two map types.
>
> ## Tradeoffs from my domain
>
> - **Learning curve:** P1 has nothing to learn. The current spec needs a footnote, a lint, a flag, an environment variable and a sort at every snapshot site.
> - **Flaky tests:** P1 makes them go away completely. Today's design only makes them fail sooner.
> - **AI correctness:** the training prior becomes correct. [the hash-seed deliberation] spent its effort trying to "flip" the prior, and every model that read only Python remains a risk. Matching the prior is cheaper than fighting it.
> - **Cost:** some memory per entry, and `remove` leaves holes that a resize compacts. This is a runtime change, not a language change, and the compiler's own `--deterministic` fixed-point check keeps working.
> - **Lock-in:** once insertion order is the contract, we can never take it back. Python made the same promise in 3.7 and has not regretted it.
>
> ## Questions for the panel
>
> 1. Systems: is the dense-entries layout acceptable for `Set` too, or does Set need a cheaper variant? I would still require one order rule for both types.
> 2. PLT: does any reason remain to keep the Q4 exclusion broader than "the result depends on order and the memo is keyed on `==`"?

- **PLT:**

> **Position: reopen Q1 (observable-order clause only), Q4, Q7. Keep Q1 seed randomization, Q6, Q2 flag.**
>
> ## The soundness problem in the current ruling
>
> Q6 adopted H2: the seed is "bucketing-only, never observable." But the runtime iterates in slot order, so iteration order *is* a function of the seed — `for (k, v) in m` observes it. H2 is violated by construction. Q4 then had to excise iteration order from value identity, which means a function with an empty effect row (`fn first_key(m: Map[Str, Int]) -> Str`) returns different results for the same argument value across runs. §4.16.3 says a pure function's "result depends only on its arguments" — that sentence is false today. The 6-0 vote fenced the wart (no memoization, a lint); it did not remove it. A typed pure fragment with run-to-run nondeterminism is a soundness defect.
>
> Insertion order removes it at the root: iteration becomes a deterministic function of operation history, and the seed becomes genuinely unobservable (H2 holds as written). HashDoS resistance (Q1's real reason) is retained — Python's compact dict (dense entry array + seeded index table) does exactly this.
>
> ## P1 (recommend): insertion order, specified by laws
>
> Denotation of `Map[K, V]`: a duplicate-free association list. Laws:
>
> - **O1 insert-new:** `insert(k, v)` with `k` absent appends at the end.
> - **O2 insert-existing:** `insert(k, v)` with `k` present replaces the value in place; position unchanged (Python, JS).
> - **O3 remove:** deletes the entry; relative order of the rest is preserved. A later re-insert appends (O1).
> - **O4 derived:** `clone` preserves order; `keys()`, `values()`, `entries()`, `for` share one order. `Set` obeys the same laws.
> - **O5 set algebra:** `a.union(b)` = `a`'s order, then `b`'s new elements in `b`'s order; `intersection`/`difference` follow the left operand. Left-biased, deterministic, not commutative in order (fine: `==` ignores order).
>
> ```blink
> let mut m: Map[Str, Int] = Map.new()
> m.insert("b", 1)
> m.insert("a", 2)
> m.insert("b", 3)          // O2: "b" stays first
> m.remove("b")
> m.insert("b", 4)          // O3 + O1: "b" now last
> assert(m.keys() == ["a", "b"])
> ```
>
> **Equality is a setoid, not a congruence — and that is fine.** `==` on Map/Set stays order-insensitive (Container Equality ruling unchanged; Python agrees). So `a == b` does not imply `f(a) == f(b)` for every pure `f` (`a.keys()` may differ). This is the standard situation for a quotient-like type with an observable representation; the spec must say so in one sentence. Consequences:
>
> 1. **Debug stays sorted.** The law `a == b ⟹ a.debug() == b.debug()` demands it. Debug ≠ iteration order; that is a learnability cost, but the law wins.
> 2. **Purity (reopen Q4).** A fn iterating a Map/Set is now a function of its argument's *representation*, so it may re-enter the pure set — provided any memoization/CSE keys on representation equality (entry sequence), never on `==`. If the compiler cannot promise that, keep the Q4 exclusion as-is; it stays sound either way. I prefer lifting it with the keying rule stated.
>
> **Consequences:**
> - **W1401 (Q7):** withdraw. Its premise is gone, and it was never implemented — zero migration.
> - **`--deterministic` / `BLINK_MAP_SEED`:** no semantic effect any more; they only pin table layout (perf profiling). Neutral on deletion; defer to Minimalism.
> - **§3.6:** replace "varies from run to run" with O1–O5; §3c iterator table "unspecified order" → "insertion order".
> - **Self-host:** Gen1/Gen2 fixed-point no longer needs the seed pin for stability.
>
> **Cost (for Systems to weigh):** one extra indirection per lookup and 8–16 bytes per entry for the dense array; `remove` leaves holes compacted on resize. CPython measured the dense layout as *smaller* than sparse slots at typical load factors.
>
> ## P2 (rejected alternative): sorted order by default
>
> Sorted order is the cleanest denotation — iteration is a function of the finite map itself, so `==` becomes a congruence and every issue above vanishes (Haskell `Data.Map`, OCaml `Map`, Rust `BTreeMap`). But it needs a `K: Ord` bound; the bound today is `Hash + Eq`, so this breaks existing code and conflicts with "Map never implements `Ord`" style rulings, and costs O(log n). Not as the default. A `SortedMap[K: Ord, V]` in lib/std is a separate ticket — YAGNI until asked.
>
> ## P3 (fallback): keep randomized, add `OrderedMap` to std
>
> Sound, but leaves the H2 leak and the purity fence, and fights the strongest LLM prior with no bug class prevented: insertion order is deterministic, so the "fail early vs rot silently" argument for randomization no longer applies — there is no hidden nondeterminism to rot. The only remaining thing randomization catches is code assuming *sorted* order, which Q1's argument never covered and the sorted Debug output already surfaces.
>
> **Cross-language:** Python 3.7+ and JS `Map` guarantee insertion order; Java offers `LinkedHashMap`; Go randomizes; Rust `HashMap` random with `IndexMap` as a crate; Koka/OCaml use sorted `Map`.
>
> **Vote intent:** P1 with O1–O5, order-insensitive `==`, sorted Debug, memoization keyed on representation; W1401 withdrawn.

- **DevOps:**

> **DevOps/Tooling: Phase A proposal ([this ticket])**
>
> I am explicitly asking to reopen part of the earlier vote: the order half of Q1, the Map role of Q2, and all of Q7. The seed half of Q1 (HashDoS) and Q6 (H1/H2) stay as they are.
>
> ### Proposal D1: `Map` and `Set` iterate in insertion order. The seed stays random for bucketing only.
>
> Use the CPython 3.6+ / JS layout: a dense entries array plus a separate index table. The seed still perturbs the index table, so HashDoS protection is unchanged. Iteration walks the dense array, so the seed can no longer be seen. That is H2 made stronger: the seed is now unobservable by construction instead of "observable but forbidden".
>
> ```blink
> fn test_config_render() {
>     let mut m: Map[Str, Int] = Map()
>     m.insert("host", 1)
>     m.insert("port", 2)
>     m.insert("user", 3)
>     m.insert("host", 9)              // update keeps its slot
>     assert_eq(m.keys(), ["host", "port", "user"])
>     m.remove("port")
>     m.insert("port", 4)              // re-insert goes to the end
>     assert_eq(m.keys(), ["host", "user", "port"])
> }
> ```
>
> Normative rules:
> - **Update** keeps the key's position. **Re-insert after `remove`** appends. Python and JS both do this.
> - **`remove` keeps the order of the other entries** (shift semantics). Implement it with a tombstone in the entries array and compact on growth, so it stays O(1) amortized. We must not ship Rust `IndexMap`'s `swap_remove` trap, where a remove silently reorders a survivor.
> - `Set` follows the same rules (as JS `Set` does). One rule for both types costs fewer tokens than two.
>
> **Why this is a tooling issue first.** The compiler itself uses Map heavily. Today every compiler output that iterates a Map is only reproducible if someone passed `--deterministic` or remembered a `.sort()`. That covers diagnostics lists, LSP completion and symbol lists, `blink doc` output, and emitted C order. With D1, all of that output is byte-stable for free:
> - Golden tests of diagnostics stop flaking.
> - LSP results stop reshuffling between keystrokes.
> - Reproducible builds do not depend on a flag.
>
> We run the Gen1/Gen2 diff with `--deterministic` precisely because random order is a CI honeypot for our own tools. D1 removes the honeypot instead of guarding it.
>
> **Serialization round-trips.** `lib/std/json.bl` already keeps source key order (parallel arrays). A user who decodes into a `Map` and encodes again today gets their keys shuffled, which gives noisy config diffs in PRs. D1 makes JSON/TOML → Map → JSON/TOML preserve order, which is what every user expects from Python and JS.
>
> **Re-audit principle.** Q1's AI/ML argument was "'unspecified' reads as insertion order to a model". That argument made random order a defence against a prior. D1 makes the prior *true*, so the bug class is gone, not caught. The random default catches order bugs only at runtime and only some of the time. Insertion order removes them with no lint at all.
>
> ### Effect on the diagnostic surface
>
> | Item | Today | Under D1 |
> |---|---|---|
> | `W1401 MapOrderAssumption` | spec text, **not implemented** (no hits in src/) | **Delete the spec text.** It costs nothing to remove, and we avoid ever maintaining a dataflow lint with false-positive risk. Minimalism's Q7 dissent wins on the merits. |
> | `--deterministic` | pins the map seed | Has no Map effect left. Keep the flag one release as an accepted no-op that prints `note: map order is insertion order; --deterministic has no effect`. Then remove it from §8.10.7, or keep it as the umbrella for future reproducibility knobs (separate question). |
> | `BLINK_MAP_SEED` | runtime pin | Keep it only as an internal runtime knob for fuzzing the bucket layout. Remove it from the user-facing spec. |
> | §3.6 "randomized" text, §3c "unspecified order" rows, MapOps table notes | | Rewrite to "insertion order" with the update, remove and re-insert rules. |
> | `Map.debug()` sorted (6-0) | | **Keep.** The law `a == b ⇒ a.debug() == b.debug()` needs it while `==` ignores order. Add one sentence to the spec: debug output sorts; `for`/`keys()` follow insertion order. |
> | `==` by membership | | **Keep.** It matches Python `dict` and the LLM prior. |
> | Q4 purity exclusion | | Leave this to PLT. Two maps can be `==` and still iterate differently, so the memo-key hazard survives unless the memo key includes order. My default is to keep Q4 unchanged. |
>
> The formatter and the LSP are not affected: D1 adds no syntax.
>
> **Migration.** D1 is a runtime chore in `bootstrap/runtime_core.h` (`blink_map`/`blink_set` layout). It needs no syntax change and no two-step bootstrap. Expect one Gen1/Gen2 output shift, which a regen absorbs. Programs that sorted explicitly keep working.
>
> **Cost (systems should check).** Iteration gets faster because the entries are dense. The extra cost is one index table (smaller than the entries) and one indirection on lookup. CPython measured the compact dict as a net memory *win*.
>
> ### Proposal D2 (fallback only): keep random order, add `OrderedMap[K, V]` to lib/std
>
> I would vote against D2:
> - It adds a second type with the same 9 methods, so the docs and LSP hover need "which one?" guidance.
> - LLMs write `Map` anyway, so the snapshot flake stays the default experience.
> - W1401 must still ship.
>
> Go is the cautionary tale here: random order plus no ordered map in std led to a dozen third-party ordered-map packages.
>
> ### Cross-language note
>
> Python 3.7+ `dict` guarantees insertion order. JS `Map`/`Set` iterate in insertion order. Rust `HashMap` is random (the `indexmap` crate is the de facto fix). Go is random by design. Of these, the two languages whose behaviour the LLM prior comes from both give insertion order.
>
> **Vote intent:** D1, with W1401 deleted, `--deterministic` turned into a no-op with a note, sorted Debug and membership `==` kept, and Q4 left to PLT.

- **AI/ML:**

> **I am reopening my own earlier argument, on the record.** In [the hash-seed deliberation] I said that a "randomized" order flips the Python prior and gives fast failures. That reasoning held only against the options we compared then: "unspecified" or "randomized". I did not weigh a third option. A stated, deterministic order removes the bug class, so we need not teach models to avoid it. Under the re-audit principle ("match LLM priors unless the deviation prevents a bug class"), randomized order prevents nothing that insertion order leaves open. Code that depends on insertion order is correct under insertion order.
>
> ## P1: Insertion order is normative for Map and Set (my first choice)
>
> ```blink
> let mut scores = Map.new()
> scores.insert("bob", 3)
> scores.insert("amy", 5)
> scores.insert("bob", 4)      // update: "bob" keeps its first position
> scores.remove("amy")
> scores.insert("amy", 6)      // re-insert after remove: goes to the end
> for (name, s) in scores {
>     io.println("{name}: {s}") // always "bob: 4", then "amy: 6"
> }
> ```
>
> The rules are the same as Python's `dict` and JS `Map`/`Set`:
> - `insert` on a key that is already in the map keeps that key's position.
> - `remove` followed by `insert` puts the key at the end.
> - `keys()`, `values()`, `entries()` and `for` all follow the same order.
>
> Set gets the same rule. With one rule for both containers, the model has nothing to decide.
>
> **Separate the hash seed from the iteration order.** Q1's per-process random seed stays for HashDoS protection. This is Python's design since 3.6: `PYTHONHASHSEED` is randomized and iteration follows insertion order. The runtime moves to a compact layout: a dense entries array, plus a sparse index table that the seed perturbs. That is the systems seat's call, but the design is well known, and it often uses less memory than the current single slot array.
>
> This change also fixes a soundness gap in the earlier vote. Q6/H2 says the seed is "never observable", but today iteration order shows it. Under P1, H2 becomes true.
>
> ## Effects on earlier votes
>
> | Item | Change |
> |---|---|
> | Q1 | Keep the randomized seed. Rewrite §3.6 to say "iteration order is insertion order; the seed affects bucketing only". |
> | Q2 | Keep `--deterministic` and `BLINK_MAP_SEED`. Restate them as perf and collision reproduction only, with no effect on output. They are no longer needed for the self-host diff. |
> | Q3 | Moot: `blink test` output is deterministic. |
> | Q4 | **Keep the purity exclusion**, for a new reason. `==` ignores order, so two `==` maps can iterate in different orders. A memo keyed on `==` would then return the wrong result. |
> | Q7 W1401 | **Remove it.** It was never built, and the bug class it targets no longer exists. Net surface is -1 lint. |
> | Debug sort | Keep it. The law `a == b ⟹ a.debug() == b.debug()` requires it. This is the one place that differs from Python's repr, and it is one sentence to learn ("debug() sorts; iteration does not"). |
> | `==` | Unchanged (membership only, as in Python `dict`). No `OrderedMap` is needed, because the default is ordered. |
> | JSON | Encoding emits keys in insertion order, so a round trip keeps the key order (same as JS/Python). |
>
> ## Why this is best from the AI/ML seat
>
> - **Prior match.** Python dicts, JS Maps/Sets and objects, Ruby Hash and PHP arrays all keep insertion order. Models write `for (k, v) in m` and then snapshot or print the result in nearly every program. Go's random order and Rust's unspecified order are the minority priors, and models write order-dependent code even in those languages.
> - **Generability in the model's own loop.** The randomized default fails *sometimes*. A model that runs its test once sees green and ships flaky code. The [the hash-seed deliberation] argument assumed failures would be fast and local. In practice a map of 2–3 keys often passes by chance. Insertion order makes the model's first green run reliable.
> - **Token cost.** We drop the `.keys().sort()` / look-up-again pattern from every printed map and every golden test. A print loop goes from about 2 lines to 1.
> - **Decision points.** Removed: "do I need to sort here?", "do I need `--deterministic`?", "will W1401 fire?". Added: none. There is only the remove-then-insert rule, and models already know it from Python and JS.
> - **Debuggability.** Output is the same on every run, so no flake needs a seed to reproduce.
>
> ## P2 (fallback, weaker): keep randomized order, add `std.collections.OrderedMap`
>
> This costs a second type, an import, and a choice at every call site. Models will still write `Map` and expect order, so the flaky failures stay. I rank P2 well below P1. I list it only so the panel can see the cost.
>
> ## P3 (reject): sorted-by-key default
>
> A BTreeMap default would be deterministic, but it would need `Ord` on keys, which conflicts with E1400 and with Hash-only keys. No mainstream prior uses it.
>
> **Cross-language note.** Python moved to ordered dicts in 3.6/3.7 for these same reasons: ecosystem code already depended on order, and the compact layout cost no performance. Go's randomized order is the counterexample, and it works only because Go users learned it over ten years. Blink has no such user base, and a spec read alone will not override the strongest prior in the training data.

- **Minimalism:**

> Minimalism: Phase A proposal ([this ticket])
>
> **I reopen Q1, Q2, Q3 and Q7 of hash-seed-iteration-order, and I reverse my own Q1 vote.** In that vote I compared random order against an order that was stable but not specified. Random won that comparison. A specified insertion order was not one of the options. The re-audit rule is "match LLM priors unless the deviation prevents a bug class". Random order prevents one bug class: code that depends on an order the spec does not promise. If the spec promises the order, that bug class goes away, and random order then prevents nothing.
>
> So I measure the options by what they delete, and insertion order deletes more than it adds.
>
> ### M1 (my first choice): insertion order for Map and Set, and delete the seed surface
>
> **Rule (one sentence in §3.6).** "`Map` and `Set` iterate in insertion order. `insert` on a key that is already present changes the value and keeps the key's position. `remove` followed by `insert` puts the key at the end."
>
> ```blink
> fn main() {
>     let mut ports: Map[Str, Int] = Map()
>     ports.insert("web", 80)
>     ports.insert("db", 5432)
>     ports.insert("cache", 6379)
>     ports.insert("db", 5433)        // db keeps its place
>     ports.remove("web")
>     ports.insert("web", 8080)       // web goes to the end
>     for name in ports.keys() {      // db, cache, web: in every run and every build
>         io.println("{name}: {ports.get(name).unwrap()}")
>     }
> }
> ```
>
> **What M1 deletes:**
> - All of §8.10.7. The hash seed stays random per process, so HashDoS protection stays. But the seed then has no visible effect, which makes law H2 true by construction. `--deterministic` has no remaining job: the only thing it does in src/ is call `blink_map_init_seed`. So `--deterministic` and `BLINK_MAP_SEED` both go, and so do the precedence rule and the "relation to `--seed`" paragraph.
> - `W1401 MapOrderAssumption`. It is spec-only and has no code in src/, so we delete it before anyone pays to build it. I voted against it at 5-1, and this removes it for everyone.
> - The "randomized" paragraph, and the `.sort()` steps that only exist to make tests stable.
> - The self-host diff no longer needs a pinned seed to be stable.
>
> **What M1 adds:** one sentence of spec, and a change to the runtime layout. CPython's compact dict uses a small index table plus a dense array of entries. In Python 3.6 that layout used less memory than the old one, and iteration got faster because it walks a dense array. `remove` leaves a hole in the array, and the next resize closes the holes. The change touches the runtime only: `blink_map` and its twin `blink_set` in runtime_core.h. The language surface does not change.
>
> **What stays as it is:**
> - Q4 (purity). `==` still ignores order, so two maps `a == b` can still iterate in different orders. A memo cache keyed by `==` would then return the wrong result, so the rule that functions which iterate a Map or Set are not memoized stays. No text change.
> - Q6 H1. Unchanged.
> - The rule that `Map.debug()` sorts. It is needed for the law that `a == b` gives `a.debug() == b.debug()`. No change.
> - E1400. Unchanged.
>
> **Set as well as Map.** One rule for both containers costs less to learn than two rules. The JS prior expects Set to keep order. The Python prior expects Set to have no order, so Python-trained code will not depend on Set order and loses nothing.
>
> **Cross-language note.** Python went this way in 3.7. Its separate `OrderedDict` type then had almost no use. JS `Map` and `Set` keep insertion order. Go is the counterexample, and its randomized order is an exam that Go programmers study for. Blink's re-audit rule says not to set that exam without a bug class to justify it.
>
> ### M2 (fallback): do nothing
>
> `--deterministic` exists, and `debug()` already sorts. This option costs nothing to build. But it keeps the flaky-test class that the ticket reports, and it keeps W1401 waiting to be implemented. I prefer M2 to any option that adds a type.
>
> ### Rejected: a second map type (`OrderedMap` or `SortedMap`) in stdlib
>
> Two map types make every author choose between them, and AI-written code will often choose the wrong one. Python's history shows the ordered variant becomes vestigial once the default map keeps order. If a need for key-sorted iteration appears in friction tickets, `keys().sort()` already handles it. YAGNI.
>
> ### Tradeoffs from my seat
>
> - **Cost:** about one runtime change, which touches two parallel structures. It adds no new syntax, no new type and no new diagnostic, and the spec gets smaller.
> - **Risk:** programs written for the old behaviour gain an order guarantee. They do not lose anything, so the migration is free.
> - **Things I could not find a way around:** a Map grows a little when a program does many removes without a resize. Rehash timing changes. Neither one changes what a program can observe.
>
> **Vote intent:** M1, with M2 as my fallback. I will vote against any proposal that keeps random order and also adds a new type.

#### Phase B — Debate (round 1)

- **Systems:**

> **INS: no change. I hold it as first choice.** I drop S2 (`OrderedMap`) for the reasons min gave: two map types cost every author a choice.
>
> **V1 (`--deterministic`, `BLINK_MAP_SEED`): I move to devops's position.** My "perf-reproduction knob" case is weak once order is fixed. The seed then changes only probe lengths, which means timing noise. That matters to a benchmark harness, not to the spec. So:
> - `--deterministic`: keep it for one release as an accepted no-op that prints a note, then remove it from §8.10.7. Build scripts (ours included: the Gen1/Gen2 diff passes it) must not break on the day this lands.
> - `BLINK_MAP_SEED`: take it out of the user-facing spec. Keep it as an internal runtime knob, documented in docs/build/, for fuzzing bucket layout and pinning benchmark noise. It costs one `getenv` at init.
> - The precedence rule and the "relation to `--seed`" paragraph go.
>
> **V2 (purity): I accept plt's wording.** What the hardware sees: CSE of `f(m)` twice on the same binding with no mutation between compares identical representations by construction, so it is safe. Any cache keyed on `==` is not safe. Rule: "iterating fns may be truly pure; memo/CSE keys on the entry sequence, never on `==`." If the compiler does not implement representation-keyed memo today, the Q4 exclusion stays in force until it does. That is the same predicate, not a new analysis. Both readings are sound, so I will not block either.
>
> **V3 (Set algebra order): I accept left-bias, with one cost on record.** `union` = copy `a`, then append `b`'s new elements: that is the natural code, so it costs nothing. `intersection` under left-bias must walk `a` and probe `b`. That is O(|a|), so we give up the "walk the smaller side" optimization (O(min)). The cost is real but small, and a deterministic order is worth it. `clone` copies the dense array (memcpy plus index copy), which is cheaper than today's rehash walk.
>
> **V4 (setoid sentence): accept.** It is one sentence, and it is true.
>
> **V5 (JSON):** encode in insertion order. Decode inserts in document order. A duplicate key in the input follows O2: the last value wins and the key keeps its first position. That matches JS `JSON.parse` and Python `json.loads`. Spec it in one line so the encoder and decoder do not diverge.
>
> **V6 (web's question, Set cost): one layout, no cheaper variant.** Numbers for an 8-byte key:
> - Today: `cap × (8 key + 1 state)` ≈ 13–18 B per live element.
> - Compact, hash stored: 16 B entry + `cap × 1–4 B` index ≈ 18–22 B per element. About 20% bigger.
> - Compact, hash not stored, for keys with a cheap hash (Int and the other scalars; kops already knows which): 8 B entry + index ≈ 10–14 B per element. That is smaller than today.
>
> So the policy is to store the hash for indirect keys (`Str`, structs), where it saves the `kops->eq` indirect call, and to skip it for scalar keys, where rehash on rebuild is a few ALU ops. That is a per-kops layout bit, and it is invisible to the spec. Iteration over a Set gets faster in both cases. Set does not need its own design.
>
> **One addition for the impl ticket:** `entries` must be allocated in the map's `owner` arena (as `keys` is today), and the index width (int8/16/32/64) must be picked at rebuild time. A spec-only landing that leaves slot-walk iteration in place would be a lie. The spec change and the runtime change land together, with a corpus test that runs the same program under two `BLINK_MAP_SEED` values and diffs the output.
>
> STABLE, ready to vote.

- **Web/Scripting:**

> **INS:** no change. All six seats picked it first, and I am not going to argue against a 6-0 that I am part of.
>
> **V1 — `--deterministic` / `BLINK_MAP_SEED`: I change my Phase A position.** I now support devops' plan, and min's end state after one release:
> - `--deterministic` stays for one release as an accepted no-op that prints the devops note (`map order is insertion order; --deterministic has no effect`). After that it is removed from §8.10.7.
> - `BLINK_MAP_SEED` comes out of the user-facing spec now. It may stay as an undocumented runtime knob for fuzzing.
>
> Why I changed: a flag named `--deterministic` that changes nothing a user can see will cause Stack Overflow questions. "I passed `--deterministic` and my output still differs" (because of time, rand or a parallel build). A reassuring name on a knob with no effect misleads people. Sys and aiml want to keep both for reproducing collision timing. That user is a runtime developer, and an undocumented environment variable serves them. A documented CLI flag is too much for that job. The one-release no-op keeps existing CI scripts from breaking, and our own Gen1/Gen2 recipe is one of them.
>
> **V2 — Q4 purity (my question to plt is answered).** I accept plt's conditional as the rule:
> - The exclusion stays unless the compiler promises that memo and CSE keys use representation (the entry sequence), never `==`.
> - If plt writes that keying rule into §4.16.3 in one sentence, lifting the exclusion is fine with me.
>
> Users never see either version, so I do not hold this up. Plt words it.
>
> **V3 — Set algebra order: support plt O4/O5, with one fact check.**
> - `clone` keeps order.
> - `union` uses the left operand's order, then the right operand's new elements.
>
> Fact check: `SetOps` (sections/03_types.md ~line 788) has only `union`. `intersection` and `difference` do not exist. The spec should not mention them now (YAGNI). Record "left operand's order" in the rationale as the rule any future set operation must follow.
>
> Cross-language note: ES2025 `Set.prototype.union` does the same as our `union`. ES2025 `intersection` picks its order by which set is *smaller*, a detail almost nobody knows. That is why the left-operand rule should be written down before anyone adds `intersection`.
>
> ```blink
> let mut a = Set.new()
> a.insert("x")
> a.insert("y")
> let mut b = Set.new()
> b.insert("z")
> b.insert("x")
> for s in a.union(b) {
>     io.println(s)        // x, y, z — every run
> }
> ```
>
> **V4 — setoid sentence: support,** in plain words. Suggested text: "Two maps can be `==` and still iterate in different orders, because `==` ignores order." It should sit next to the `debug()`-sorts sentence. Users will hit both facts together.
>
> **V5 — JSON/serialization: support.** Encoding emits keys in insertion order. Decoding into a `Map` inserts keys in document order, so a JSON round trip keeps the key order. `lib/std/json.bl` already keeps document order in its node arrays, so only the Map boundary needs the rule. Any other std serializer (TOML) follows the same rule. Python `json` and JS `JSON.stringify` work this way, and config diffs in PRs stop being noise.
>
> **V6 — Set cost: answered by sys.** Set gets the same compact layout, and its entries carry no value field. One order rule for both types, with no cheaper unordered Set variant. Settled for me.
>
> STABLE, ready to vote.

- **PLT:**

> **INS:** unchanged, first choice.
>
> **V2 — answer to web's question: no. No reason remains to keep the exclusion broader, and the hazard is not specific to Map or Set.** Facts: §4.16.3 has no memoization rule today, and src/ memoizes no user function. The only text is the §3.6 sentence "a function whose result depends on unsorted Map/Set iteration order is **not** referentially transparent". Under INS that sentence is false: such a function returns the same result for the same representation on every run. The real hazard is any cache keyed on `==` where `==` is not a congruence. That also covers any user `impl Eq` that ignores a field. Map/Set is one case of a general rule. Sound wording, replacing the §3.6 sentence:
>
> > "A compiler may reuse the result of a pure call only for arguments that are identical in representation. `==` does not license reuse: two `==` values can give different results (two equal maps can iterate in different orders)."
>
> This is sound, needs no syntactic predicate, and costs nothing because nothing memoizes today. Sys asked me to word it; this is the wording. If the panel would rather keep the old Q4 predicate unchanged, it is still sound (it over-approximates), and I will not block. But its stated reason ("not referentially transparent") must change, because the spec should not justify a rule with a claim that is false.
>
> **V4 — setoid sentence:** the sentence above covers it. One sentence total, not two.
>
> **V3 — derived operations.** Checked: SetOps has only `union` (plus insert/remove/contains). So the rules are:
> - `a.union(b)`: `a`'s order, then each element of `b` that is not in `a`, in `b`'s order.
> - `collect()` into a Map/Set: iterator order. A duplicate key keeps its first position and takes the last value (follows from O2).
> - `clone`: keeps the order.
> - `Map` literal `{"a": 1, "b": 2}`: source order.
>
> Without these rules, "insertion order" leaves derived maps unspecified, and an unspecified order is the hole the ticket wants closed. They also follow from O1/O2 if each operation is defined as a sequence of inserts, so the spec can state that one sentence instead of listing every case: "every derived Map/Set is built by inserts in the order above."
>
> **V1 — `--deterministic` / `BLINK_MAP_SEED`:** under INS no program output depends on them. That is a semantic fact, so they cannot stay in §3.6. I lean to min's position: delete both from the spec. If they survive, they belong in §8.10 as runtime-layout knobs only. DevOps' one-release no-op note is a reasonable migration step. Not blocking.
>
> **V5 — JSON:** agree. Encoding emits entries in iteration order. This is not a new rule, because iteration order is now specified.
>
> **V6 — Set layout:** for sys. My only requirement is the same order laws for Map and Set. One rule matters more to me than the layout.
>
> **Debug:** keep sorted. Agreed by all six.
>
> STABLE, ready to vote.

- **DevOps:**

> **DevOps/Tooling: Phase B round 1**
>
> **INS: no change. I hold it.** One correction to our own wording: "compact-dict layout (dense entries + seeded index)" must not go into sections/. The spec states the order rules and the HashDoS requirement; the layout is a runtime chore (docs/build/). If the layout text goes into the spec, a later runtime that keeps the order by other means becomes "non-conforming".
>
> **V1: I move to sys/aiml. Keep both knobs, state that they do not change program output, and move them to §8.10.** I withdraw my "no-op with a note" plan. It made sense only if the flag lost all meaning, and sys gives it one: bucket placement still changes probe lengths, so a timing trace or a collision-heavy perf regression reproduces only under a pinned seed. `BLINK_MAP_SEED` is still the only knob that crosses an exec boundary, which matters when a perf bug shows up in a child process under CI. Both knobs are already shipped and cost nothing to keep. Deleting them (min) removes a working perf-reproduction tool to save two paragraphs.
>
> Spec edits:
> - §8.10.7 says "pins bucket placement; program output is identical with or without it".
> - Remove the "Relation to `--seed`" paragraph. The two knobs no longer interact in any way a user can see, so the paragraph only adds confusion.
> - Keep the precedence rule, as one line.
>
> To web: pinning to 0 "for bit-identical bucketing" is the same purpose, so we agree in substance.
>
> **V2: keep the Q4 exclusion as it is.** I checked: src/ has no program-level memoization or CSE over pure calls. The only "memoize" hits are typecheck node caches and cli hash caches. Lifting the exclusion with a keying rule would promise behaviour from a pass that does not exist. Nobody can test the promise, and the first person to write the memoizer must re-derive it. Keep the conservative predicate. When a memoizer ships, PLT's keying rule can lift it in the same change, with tests. To web's question: no reason in principle, but there is no consumer today. YAGNI.
>
> **V3: adopt plt's rules.** `clone` keeps order; `union` = left operand's order, then the right operand's new elements in its order; `intersection`/`difference` follow the left operand. Golden tests that print the result of a set operation need this. Without it, "insertion order" is defined for `insert` only, and every derived Set has an unspecified order again, which is the same flake through a side door.
>
> **V4: adopt the setoid sentence.** It also explains why `debug()` sorts, which a user will otherwise file as a bug ("`for` prints host, port, but `debug()` prints port, host"). Put the sentence next to the Debug ruling.
>
> **V5: make it normative.** Map/Set encode in iteration order. A decode into Map followed by an encode keeps the source key order. Config files in PRs get a clean diff, and snapshot tests of emitted JSON/TOML stay stable.
>
> **V6: defer to sys on cost.** The order rule must be the same for Set and Map whatever layout sys picks. Two order rules would bring back the "which one?" doc and hover burden I argued against in D2.
>
> STABLE, ready to vote

- **AI/ML:**

> **INS:** I keep INS as stated.
>
> **V1: I change my Phase A position and move to devops plus min.**
> A flag that has no effect on output is a trap for models. Our own corpus, CI scripts and the old §8.10.7 text all show `--deterministic` next to test commands. A model that learns from them will keep adding the flag "for safety". It will also believe the flag still controls order, which is the old Python-prior error with the sign flipped. Every knob is one more decision point. Proposal:
> - Remove `--deterministic` and `BLINK_MAP_SEED` from the user-facing spec, together with the precedence rule and the "relation to `--seed`" paragraph.
> - `--deterministic` stays as an accepted no-op for one release. It prints `note: map order is insertion order; --deterministic has no effect`, then it goes. A hard error at once would break scripts for no gain. The note teaches the new rule at the exact point where the old belief shows up.
> - `BLINK_MAP_SEED` stays only as an internal runtime knob for fuzzing and perf reproduction, as devops proposes. It is not documented in sections/.
>
> If sys needs a documented knob to reproduce perf issues, I accept it in §8.10, provided the text says "no effect on program output".
>
> **V2: keep the Q4 exclusion unchanged.**
> PLT's lift is sound only if the compiler keys memos on the entry sequence. That is a promise about the implementation, and users cannot check it. Keeping the rule costs nothing a user can see. Lifting it adds a rule a model must hold ("pure, but memo keyed on representation") and gains nothing a model writes. If PLT words a narrow form that sys accepts, I will not block it, but my vote is unchanged.
>
> **V3: adopt PLT's O5 (left-biased).**
> JS's `Set.prototype.union` (ES2025) has the same order: the receiver's elements, then the argument's new ones. That makes O5 a prior match. One more case needs a rule: building a Map from a list with duplicate keys (`entries`, collect, JSON decode). The key keeps the position of its first occurrence and takes the value of its last. This follows from O1 and O2, and Python's `dict([("a", 1), ("a", 2)])` gives the same result. Please state it in one line, so models do not have to work it out:
>
> ```blink
> let m = Map.from([("a", 1), ("b", 2), ("a", 3)])
> assert(m.keys() == ["a", "b"])
> assert(m.get("a") == Some(3))
> ```
>
> (The constructor name is illustrative only.)
>
> **V4: adopt the setoid sentence.**
> It is the sentence a model needs in order to not use `==` as "same iteration". Suggested wording: "`==` ignores order: two equal maps may return `keys()` in different orders."
>
> **V5: insertion order for JSON and serialization.**
> Encoding emits entries in insertion order, and decoding inserts them in document order, so `decode(encode(m))` keeps the key order. This matches JS `JSON.parse`/`stringify` and Python `json`, and it is the main way snapshot tests depend on order.
>
> **V6: I defer to sys on the layout.**
> Whatever the layout, Set must obey the same order laws. Having two rules is the cost I will not accept.
>
> STABLE, ready to vote.

- **Minimalism:**

> Minimalism: Phase B, round 1
>
> **INS:** I keep it as my first choice. All six seats proposed it, so I drop M2 (do nothing).
>
> **V1. Delete both from the spec.** A knob that changes no output belongs in the implementation and needs no spec text.
> - To sys and aiml, on keeping them for perf reproduction: H2 says no API reads the seed, and Q3-coupling put no "reproduce" line in the output. So a user cannot learn which seed a slow run used, and cannot replay it with `BLINK_MAP_SEED`. Without a way to capture the seed, the perf-reproduction use has no user. Whoever needs to fuzz the bucket layout can keep an env var in the runtime. That fits devops's point, but the spec says nothing about it.
> - `--deterministic`: I accept devops's plan for migration only. The flag stays for one release as a no-op that prints a note, and then it goes. Our own Taskfile passes the flag today, so removing it at once breaks scripts for no gain. §8.10.7 goes away completely.
> - I do not accept "keep it as the umbrella for future reproducibility knobs". That is YAGNI. When a knob of that kind exists, we can add the flag with it.
>
> **V2. Keep Q4 unchanged.** PLT's version (lift the exclusion, and key the memo on the entry sequence) adds a second equality idea to the spec only to allow more memoization. No user has asked for that memoization. Q4 is a syntactic predicate on purpose, and the earlier panel rejected dataflow there. To web's question: a narrower rule would need the compiler to know whether a result depends on order, and that is the same dataflow. The broad rule is sound and costs no text. If memoization of these fns ever matters, we can narrow the rule then.
>
> **V3. Yes, but only for methods that exist.** The `Set` surface has `union` and no `intersection` or `difference`; that was the 3-2 YAGNI vote at §3.6 ~line 822. One clause is enough: "`clone` keeps order; `a.union(b)` gives `a`'s order, then `b`'s new elements in `b`'s order." Do not write order rules for methods the spec does not have. If those methods come back, their order rule comes back with them.
>
> **V4. Yes, as a rewording of the existing sentence, not a new one.** §3.6 already says "Iteration order is not part of a Map/Set value's identity." Add one clause to that sentence: "so `a == b` does not give `a.keys() == b.keys()`." That clause is the reason Q4 stays, so it pays for itself.
>
> **V5. No new text.** The JSON `Object` is already a list that keeps input order (§3.6.3 ~line 5126). A derived encoder that walks a Map uses iteration order, so INS already makes the encoding insertion-ordered. A separate rule would state the same thing twice, and the two copies could drift.
>
> **V6. One layout for both.** I defer to sys on cost. A second, cheaper Set layout would mean two runtime structures and an order guarantee that applies to one type only. The compact layout does not cost more than the linear probing we have now, so I see no reason to make Set a special case.
>
> **Net change to the spec:**
> - Removed: the "randomized" paragraph, §8.10.7, W1401, and the two "unspecified order" cells in the tables.
> - Added: the INS sentence, one clause for V3, and one clause for V4.
>
> STABLE, ready to vote

#### Phase C — Final vote

The ballot asked seven questions. Q1: insertion order (YES/NO). Q2: W1401 (WITHDRAW/KEEP). Q3: the flag and the variable (A: remove from the user-facing spec, flag is a one-release no-op; B: keep both as non-semantic knobs in §8.10). Q4: purity (A: keep the exclusion with its reason fixed; B: plt's reuse sentence). Q5: derived order (A: every derived form built by inserts; B: one clause for `clone` and `union`). Q6: where the spec says that `==` maps can iterate in different orders (A: a clause on the identity sentence; B: a separate sentence next to the `debug()` text). Q7: JSON (A: encode in iteration order, decode in document order; B: no new text).

Q7-A on this ballot said "a duplicate key: last value, first position". That contradicts §3.6.3, where the first entry wins. The moderator wrote the option wrongly; Minimalism found the conflict, and Phase D re-ran Q7.

Tally: Q1 YES 6-0. Q2 WITHDRAW 6-0. Q3 A 6-0. Q4 B 5-1 (DevOps dissent). Q5 A 6-0. Q6 B 4-2 (PLT and Minimalism for A). Q7 A 5-1 (Minimalism for B).

- **Systems:**

> Q1: YES
> Reasoning: A dense-entries plus seeded-index layout gives insertion order at equal or lower memory, faster iteration and cheaper rebuild, and the random seed still blocks HashDoS. The seed then changes only bucket placement, so no output depends on it, and that makes H2 true by construction. I agree with devops that the layout belongs in docs/build/, not sections/. The spec states the rules and the HashDoS requirement; the runtime chooses how to meet them.
> Concern: someone could land the spec change before the runtime change, so the spec would promise an order the slot-walk runtime does not give. They must land together, with a corpus test that diffs output under two BLINK_MAP_SEED values.
>
> Q2: WITHDRAW
> Reasoning: W1401's premise is gone, and src/ has no code for it, so withdrawing costs zero. A lint that flags well-defined code is noise the user pays for on every build.
> Concern: none of note. Stale mentions of W1401 in docs or the diag table could survive the edit, so grep for them.
>
> Q3: A
> Reasoning: Min is right that the perf-reproduction case has no user: no API exposes the seed, so nobody can capture the seed from a slow run and replay it. An env var in the runtime, documented in docs/build/, covers fuzzing and benchmark-noise pinning for runtime developers at the cost of one getenv. The one-release no-op keeps our Taskfile and Gen1/Gen2 recipe from breaking.
> Concern: the no-op flag could outlive its one release, so put its removal on a ticket.
>
> Q4: B
> Reasoning: Under INS the old sentence ("not referentially transparent") is false, and a spec should not justify a rule with a false claim. PLT's sentence states the real hazard, "== is not a congruence", which also covers any user `impl Eq` that ignores a field. It needs no analysis pass and costs zero today because nothing memoizes. Every memo or CSE the hardware would actually do (same binding, no mutation between) compares identical representations by construction.
> Concern: if A wins, its reworded reason must still name `==` and not order "nondeterminism", or the old false claim survives in new words.
>
> Q5: A
> Reasoning: "Every derived Map/Set is built by inserts in this order" is one sentence, and it is exactly what the runtime does: clone is a memcpy of the dense array, union appends, and collect inserts. Without the collect/duplicate-key rule (first position, last value), the commonest way to build a Map from data has an unspecified order again. That is the flake coming back through a side door. Left-bias for a future intersection belongs in the rationale only, per the YAGNI fact.
> Concern: a later perf patch could build `union` by walking the smaller operand first and silently break the rule, so a test must pin union order.
>
> Q6: B
> Reasoning: Users will run into the two facts together: `for` prints one order, `debug()` prints another, and two `==` maps differ. A plain sentence next to the debug-sorts text answers the bug report before anyone files it. If Q4-B wins, this sentence and PLT's can share wording, but the user-facing explanation belongs where Debug is defined.
> Concern: we could end up with two near-duplicate sentences (Q4-B plus this one) that drift apart, so the editor should cross-reference rather than restate.
>
> Q7: A
> Reasoning: Snapshot tests and config diffs depend most on order through serialization. The duplicate-key rule (last value, first position) is the one edge where an encoder and decoder written separately would diverge. It matches JS `JSON.parse` and Python `json`. One normative line costs less than the bug reports.
> Concern: the rule could apply only to json.bl while other std serializers (TOML) are left out, so the wording should say "std serializers", not "JSON".

- **Web/Scripting:**

> Q1: YES
> Reasoning: Python 3.7+ dict, JS Map/Set, Ruby Hash and PHP arrays all iterate in insertion order, so every JS or Python dev already holds this rule. Making the prior true removes the flaky-snapshot bug class. Randomized order only made that bug fail sooner, and with 2–3 keys it often passed by chance anyway. The seed stays for HashDoS, and users never have to think about it.
> Concern: the spec change might land before the runtime layout change, and then the spec promises an order that the runtime does not give. Sys's two-seed corpus diff test must ship with the spec change.
>
> Q2: WITHDRAW
> Reasoning: the lint guards against a bug class that no longer exists, and nobody ever built it, so deleting it costs nothing. A warning about an order that is guaranteed would confuse every dev who reads it.
> Concern: none worth a line. It was never implemented, so no user code or docs depend on it.
>
> Q3: A
> Reasoning: a flag named `--deterministic` that changes nothing visible will cause "I passed --deterministic and my output still differs" questions, and models will keep adding it out of habit. The one-release no-op note teaches the new rule at the exact place where the old belief shows up, and it does not break our own Taskfile or anyone else's CI script. A runtime developer who needs to pin bucket layout has an undocumented env var, which is the right size of tool for that audience.
> Concern: someone may forget the removal step after the no-op release, which would leave a dead flag in the CLI help forever. The impl ticket needs a follow-up ticket that depends on it.
>
> Q4: B
> Reasoning: users never see either rule, so I vote for the one that is true. Under Q1 the old reason ("not referentially transparent") is false. Plt's sentence states the real hazard, a reuse keyed on `==`. That hazard also covers a user `impl Eq` that ignores a field, which a narrow rule about Map/Set would miss. It costs nothing, because nothing memoizes today.
> Concern: a future memoizer author may skim past "identical in representation" and key on `==` anyway. The memoizer ticket must cite this sentence and include a test with two equal maps.
>
> Q5: A
> Reasoning: snapshot tests print maps built by `collect()`, by literals and by `union`, not only by `insert`. If those orders stay unspecified, the flake comes back through a side door. "Last value, first position" on duplicate keys is exactly Python's `dict([("a", 1), ("a", 2)])`, so it matches the prior. Stating it once as "every derived Map/Set is built by inserts" is one rule, not a list.
> Concern: the spec might mention `intersection`/`difference` by accident. Keep their rule in the rationale only, as the option says.
>
> Q6: B
> Reasoning: users meet this fact when `for` prints `host, port` and `debug()` prints `port, host`, and they file it as a bug. The sentence that explains it belongs right there, next to the `debug()`-sorts text, in plain words: "Two maps can be `==` and still iterate in different orders, because `==` ignores order; that is why `debug()` sorts."
> Concern: if Q4-B also wins, the spec may say the same fact twice. Have the editor keep the Q4 sentence about reuse and this sentence about `debug()`, each with its own job.
>
> Q7: A
> Reasoning: decode then encode keeping key order is what Python `json` and JS `JSON.parse`/`stringify` do. It is the main reason config diffs in PRs stay clean. One normative line stops the encoder and decoder from drifting apart, and it pins the duplicate-key case, which INS alone leaves for the reader to work out.
> Concern: TOML and any later serializer might not follow the same line. Word it as "every std serializer" rather than only JSON.

- **PLT:**

> Q1: YES
> Reasoning: With insertion order, iteration is a deterministic function of the operation history. That makes H2 ("the seed is never observable") true by construction, where today the rule only forbids depending on it. It also removes the case where a function with an empty effect row returns different results between runs. The order laws (O1–O3) define the denotation fully, and putting the layout in docs/build/ correctly keeps the spec independent of the representation.
> Concern: The spec may state the update/remove/re-insert laws loosely, and leave a derived operation without an order. That would bring back an unspecified order.
>
> Q2: WITHDRAW
> Reasoning: The lint's premise was that the order a program sees has no defined value. That premise is gone, and the lint was never implemented, so withdrawing it costs nothing.
> Concern: None of substance. A reader of the old rationale doc may still look for W1401, so the new rationale must say that it supersedes the old one.
>
> Q3: A
> Reasoning: A knob that does not change what a program can observe is not part of the language's semantics, so it has no place in sections/. An internal runtime env var and a one-release no-op note give the migration path without spec surface.
> Concern: The no-op note can outlive its one release unless someone files a ticket to remove it.
>
> Q4: B
> Reasoning: The hazard is not specific to Map or Set. It is any cache keyed on an `==` that is not a congruence, and a user `impl Eq` that ignores a field has the same problem. A Map/Set-only syntactic exclusion is sound for Map/Set but says nothing about that general case. One sentence states the actual law for all types, and it costs no analysis. Option A is sound as a conservative rule, but it fences off one example of the problem and leaves the problem itself unstated.
> Concern: If A wins, the spec keeps a Map-specific predicate for a general law, and the first memoizer may key on `==` for user types and be unsound.
>
> Q5: A
> Reasoning: "Every derived Map/Set is built by inserts" reduces all derived orders to O1/O2, so it is one rule and not a list of cases. The `collect`/decode rule for duplicate keys (first position, last value) is the case most likely to be guessed wrong. Clause B leaves `collect` and literals with no stated order, which is the hole that Q1 closes.
> Concern: A future set operation such as `intersection` may be added without the left-operand rule being read from the rationale.
>
> Q6: A
> Reasoning: The fact that two `==` maps can iterate differently is a statement about the denotation. It belongs on the sentence about value identity, which states that `==` is a setoid and not a congruence. The Debug text can point to it.
> Concern: Users read the Debug text and not the identity section, so they may still be surprised that `debug()` sorts.
>
> Q7: A
> Reasoning: Decode is where the duplicate-key rule has a visible effect: a document with a repeated key must give a defined result. Encode follows Q1 anyway, but a decode → encode round trip is a law worth stating once, so that the encoder and decoder cannot drift apart.
> Concern: A non-JSON serializer such as TOML may not follow the same rule unless the text says "any std serializer".

- **DevOps:**

> Q1: YES
> Reasoning: Every tool that iterates a Map becomes byte-stable with no flag: diagnostics lists, LSP results, `blink doc`, emitted C, and user snapshot tests. That removes the CI trap where order changes between runs, instead of guarding against it with a lint and a flag. Keeping the layout out of sections/ leaves the runtime free to change how it keeps the order.
> Concern: the spec could land before the runtime does. Then the spec would promise insertion order while the runtime still walks slots in hash order. The spec change and the runtime change must land in one commit, with a corpus test that diffs the output under two `BLINK_MAP_SEED` values.
>
> Q2: WITHDRAW
> Reasoning: The lint guards against a bug class that INS removes. src/ has no implementation of it, so withdrawing it costs nothing. We also avoid ever maintaining a dataflow lint with a false-positive risk.
> Concern: none of substance. The withdrawn W1401 code must not be reused for a different lint, or old docs and model priors will point at the wrong meaning.
>
> Q3: A
> Reasoning: I move from B to A. Min is right that no API exposes the seed and no reproduce line exists, so a user cannot capture a seed to replay, and the perf-reproduction case has no user. A documented `--deterministic` that changes nothing a user can see becomes a cargo-cult flag in CI scripts and in model output. The one-release no-op with a note keeps our Taskfile and user scripts working, and the note teaches the new rule where the old belief shows up.
> Concern: the no-op may never get removed. The release that adds the note must also file the removal chore, and the Gen1/Gen2 recipe must drop the flag in the same change.
>
> Q4: A
> Reasoning: src/ has no program-level memoizer, so lifting the exclusion would promise behaviour from a pass that does not exist and that no test can check. Option A keeps a sound syntactic predicate and fixes the stated reason, which PLT correctly showed is false under INS.
> Concern: when someone writes a memoizer, they may key it on `==` for user types with a lossy `impl Eq`. PLT's general rule should be recorded in the rationale so that this author finds it.
>
> Q5: A
> Reasoning: For golden tests, the derived cases matter as much as `insert`. A Map built from a list with duplicate keys, a literal, a clone and a union all appear in snapshot output. The one sentence "every derived Map/Set is built by inserts" gives one rule that a doc tool and a model can apply to any operation added later.
> Concern: a future bulk constructor could take a shortcut (for example, build the index first) and break the insert-sequence rule. The impl ticket needs a corpus test for each derived form.
>
> Q6: B
> Reasoning: Users meet the "`for` prints in one order, `debug()` prints in another" surprise together with the sort rule, so the explanation belongs next to the `debug()`-sorts text. Without it, someone will file the sort as a bug. A separate plain sentence is easier to find in docs and in LSP hover than a clause inside an identity sentence.
> Concern: the two sentences (identity in §3.6 and the debug note) can drift. The debug note should state the fact and link to the identity sentence, not restate the rule.
>
> Q7: A
> Reasoning: Config files that pass through decode→Map→encode in PRs give clean diffs only if both directions are pinned, and the duplicate-key rule (last value, first position) is exactly where an encoder and a decoder could disagree. One normative line costs less than the snapshot-flake reports we would get without it. It matches Python `json` and JS `JSON.parse`/`stringify`.
> Concern: TOML and any later std serializer must follow the same rule. The rule should read "std serializers" and not only "JSON".

- **AI/ML:**

> Q1: YES
> Reasoning: Python dict, JS Map/Set, Ruby and PHP all keep insertion order. Models print maps and snapshot them in nearly every program, so insertion order makes the model's first green run a reliable green run. Random order prevents no bug class once the order is specified. It only makes small maps pass by chance and fail later. The rule set is one paragraph, and models already know it from Python and JS.
> Concern: The sorted `debug()` output differs from iteration order. Models may expect `io.println("{m.debug()}")` to show insertion order, as Python's repr does.
>
> Q2: WITHDRAW
> Reasoning: Its target bug class no longer exists. It has no code in src/, so withdrawing it costs nothing to migrate, and the spec loses one diagnostic a model would have to learn.
> Concern: None that matters. A few docs or examples that still name W1401 must go in the same change.
>
> Q3: A
> Reasoning: A flag that does not change output is a trap. Our Taskfile and the old spec text pair `--deterministic` with test commands, so models will keep adding it and will believe it still controls order. The no-op note fixes that belief at the exact point where it shows up. The internal env var keeps layout fuzzing possible without a user-facing decision point.
> Concern: Someone may forget to remove the no-op after one release, so it should have a tracked removal ticket.
>
> Q4: B
> Reasoning: I move to PLT's sentence. The old reason ("not referentially transparent") is false under Q1, and a spec that justifies a rule with a false claim teaches models the wrong model. "`==` does not license reuse" is one general rule. It also covers a user `impl Eq` that ignores a field, so a model applies one idea everywhere, not a Map-specific predicate. Nothing memoizes today, so it costs nothing.
> Concern: Some readers may take "identical in representation" to mean pointer identity. The rationale should give the map example in one line.
>
> Q5: A
> Reasoning: Map literals and `collect()` are the most common ways code builds a map. A literal in source order is the strongest prior of all (JS object literals, Python dict displays). Leaving those cases unspecified would rebuild the hole that this ticket closes. "Every derived Map/Set is built by inserts in the order above" is one sentence that covers every case.
> Concern: A future derived operation may break the "built by inserts" rule without anyone seeing it, so new SetOps/MapOps methods need a review check.
>
> Q6: B
> Reasoning: (This applies if Q4-A wins. Under Q4-B the Q4 sentence covers it.) The surprise a model meets is "why does `debug()` not match my `for` loop?". A plain sentence next to the debug-sorts text answers that question where the model looks. A clause buried in the identity sentence does not.
> Concern: The statement may then appear twice, if the Q4-B sentence and this sentence both survive the edit.
>
> Q7: A
> Reasoning: Decode behaviour does not follow from Q1 alone. The order of keys on decode, and what a duplicate key does, are exactly the cases where a model guesses. Python's `json` and JS `JSON.parse` both use last value and document order, so the normative text matches the prior. JSON round trips are the main way snapshot tests depend on order.
> Concern: The duplicate-key rule must match the JSON `Object` decode path in lib/std, or the spec and the code will drift.

- **Minimalism:**

> Q1: YES
> Reasoning: With a stated order, the bug class that random order guarded against does not exist, so random order now costs every user something and prevents nothing. The spec gets shorter: the "randomized" paragraph, the two "unspecified order" table cells and all of §8.10.7 go. The spec gains only the order rules. It is right to keep the layout out of sections/: a later runtime that keeps the same order by other means must still conform.
> Concern: if the spec lands before the runtime, the spec promises an order the runtime does not give. The two must land in the same change, with a test that runs the same program under two seeds and diffs the output (sys B1).
>
> Q2: WITHDRAW
> Reasoning: Its premise is gone, it has no code in src/, and deleting it costs nothing. This is the deferral I asked for in the earlier vote, now made permanent.
> Concern: none worth stating. Maybe one stale mention of W1401 in a doc or DECISIONS entry that the cleanup misses.
>
> Q3: A
> Reasoning: Once a knob has no effect on output, it no longer belongs in the spec. No API exposes the seed and nothing prints it, so a user cannot capture the seed a slow run used, and the perf-reproduction case has no user. A runtime developer can use an env var documented in docs/build/. A flag named `--deterministic` that changes nothing misleads people (web) and teaches models a false belief (aiml). The one-release no-op is migration only.
> Concern: the no-op could outlive its one release. The cleanup needs its own ticket, made to depend on this one.
>
> Q4: B
> Reasoning: I change my B1 vote. PLT showed that the old sentence ("not referentially transparent") is false under Q1, and that nothing in src/ memoizes today. Q4-A keeps a Map-specific predicate and gives it a new reason. Q4-B replaces that predicate with one general sentence. That sentence also covers a user `impl Eq` that ignores a field, a latent bug the Map-only rule misses. One general rule in place of a special case is a subtraction. B only limits what a future memoizer may do, so it promises no feature that does not exist. If Q4-B passes, the syntactic predicate from the earlier Q4 vote should be deleted, not kept beside it.
> Concern: whoever writes the first memoizer could key it on `==` without reading §3.6. The memoizer ticket should cite the sentence.
>
> Q5: A
> Reasoning: I change from B1. PLT's form is one sentence ("every derived Map/Set is built by inserts in the order above"), and it covers `collect`, literals, `clone` and `union` without a separate rule for each. My clause covered two cases and left `collect` and the literal open, and an open order is the hole this ticket wants closed. The duplicate-key rule (first position, last value) follows from the insert rule, so it costs no extra text. Keep the rule for a future `intersection`/`difference` in the rationale only.
> Concern: the list of examples could grow into a list of cases. The spec should keep the one general sentence normative, and give the cases as examples only.
>
> Q6: A
> Reasoning: Q4-B already covers this. If Q4-A wins, one clause in the existing sentence says it without adding a sentence. Two copies of one fact in two places can drift.
> Concern: users may not find the reason `debug()` sorts unless the Debug text cross-refers to this clause. A three-word "see Container Equality" would fix that.
>
> Q7: B
> Reasoning: the encoder walks the Map in iteration order, so Q1 already fixes the encode order, and a new rule would only repeat Q1. Option A is also wrong. Its "duplicate key: last value" contradicts §3.6.3 (sections/03_types.md ~line 5126): "Where a key occurs more than once, a lookup takes the **first** entry with that key. This holds for `JsonValue.get` ... and for derived `from_json`." Under A, a decode into a Map would take the last value while `from_json` takes the first, so the same document would give two answers. If the panel wants a decode rule, the rule must match the existing first-entry rule or reopen it explicitly. It must not pass as a side effect of this ticket.
> Concern: if A wins as worded, the spec has two rules for duplicate keys that conflict, and a user hits them as a bug.

#### Phase D — Round 2 (Q6 and Q7)

Q6 was 4-2, so it went to Phase D. Q7 went to Phase D because its option text was wrong. The digest put the §3.6.3 text in front of every seat.

##### Debate

- **Systems:**

> **Q6: I move to A, with min's pointer made mandatory.**
> My Phase C concern was drift between two copies of one fact. A removes the second copy at the root, and B (as devops and I both qualified it) only works if the debug note does not restate the fact. That is A with a link. So: the fact lives once, on the value-identity sentence. The Debug text carries a plain "why" pointer with no restated rule:
>
> > "`debug()` sorts so that `==` maps print the same text; their iteration order can differ (see Container Equality)."
>
> That pointer answers web's user, who opens the Debug text, at the point where the bug report starts. If the panel keeps B, I accept it only in that same form: fact in one place, link in the other.
>
> **Q7: I vote A, corrected to the existing first-entry rule.** Min's catch is right. Q7-A as worded on the ballot contradicts §3.6.3, and one document must not decode to two answers depending on the target type. The cost is the same in the runtime either way: "insert if absent" is the same probe as "insert or replace". Exact wording:
>
> > "A std serializer encodes a `Map` or `Set` in iteration order. A std deserializer that builds a `Map` or `Set` inserts entries in document order. Where a key occurs more than once, the first entry wins, for both position and value, as for `JsonValue.get` and derived `from_json`. A round trip of a document with no duplicate keys keeps the key order."
>
> The decoder must skip a duplicate key, not call `insert` on it, so this does not follow from O2. The spec must state it, which is why I keep A over B.
>
> On record, not part of this vote: `collect()` into a Map takes the **last** value (Q5-A, O2), while decode takes the **first**. JS and Python take last for both. I am not reopening §3.6.3 here; it may be first-wins on purpose (parser-differential safety). A friction ticket should ask whether the two rules should agree.
>
> STABLE, ready to vote.

- **Web/Scripting:**

> **Q6: I move to A, on the condition that min's cross-reference ships.** My real need was that a dev who sees `for` print `host, port` and `debug()` print `port, host` finds the reason on the spot. Min's own fix does that without a second copy of the fact. So:
> - The fact is stated once, on the value-identity sentence (plt/min A).
> - The Debug text gets one short pointer that gives the reason without restating the rule: "`debug()` sorts because `==` ignores order (see *Container Equality*)."
>
> That is what devops and sys asked for in their B concerns ("link, don't restate"), so I think B's voters lose nothing. If the pointer is dropped, I go back to B.
>
> **Q7: A, with the duplicate-key rule changed to match the existing first-entry rule.** Min is right. Two answers for one document inside one std is worse than not matching the prior. Parser differentials on duplicate keys are a known security bug class, and we should not build one between `JsonValue.get` and Map decode. Python and JS take the last value, but RFC 8259 leaves duplicates unpredictable, and real documents almost never contain them. So I give up the prior here, keep Blink's rule as the only one, and do not reopen §3.6.3.
>
> Exact wording:
>
> > A std serializer encodes a `Map` or `Set` in iteration order. Decoding into a `Map` or `Set` adds entries in document order. Where a key occurs more than once, the first entry wins: it sets both the value and the position, and later entries with that key are ignored. This matches the first-entry lookup rule for `Object` (§3.6.3). So decoding then encoding keeps the order of the first occurrence of each key.
>
> ```blink
> let m: Map[Str, Int] = json.parse_as("{\"a\": 1, \"b\": 2, \"a\": 3}")?
> assert(m.keys() == ["a", "b"])
> assert(m.get("a") == Some(1))   // first entry wins, as JsonValue.get does
> ```
>
> (`parse_as` is illustrative only.)
>
> Note for the record: this decode rule is not "a sequence of `insert`s" (Q5), because a repeated `insert` would take the last value. The spec text must say "ignored" so nobody derives last-wins from Q5.
>
> STABLE, ready to vote.

- **PLT:**

> **Q6: I move to B, with the cross-reference that devops and sys asked for.** Q4-B already states the law in §3.6. The Debug text must not repeat that law. It should state the fact that users run into, then link to the law:
>
> > "`debug()` sorts because two maps can be `==` and still iterate in different orders (see *Hash Contract and Seeding*)."
>
> This gives one statement of the law and one pointer to it, so the two cannot drift. My objection to B was that the fact would be stated twice. A pointer is not a second statement, so the objection no longer holds.
>
> **Q7: I vote A, amended so the duplicate-key rule matches the existing first-entry rule.** Min is right. The ballot wording ("last value, first position") breaks a coherence law the spec already has. For a document `o` decoded into a Map `m`, `m.get(k)` must equal `o.get(k)` for every key `k`. Without this, one document gives two answers depending on how you read it. §3.6.3 fixes "first entry wins" for `JsonValue.get` and derived `from_json`. So the decode rule must be insert-if-absent, not insert. That differs from Python and JS, which keep the last value, but Blink's prior ruling outranks a foreign default. Changing it would mean reopening §3.6.3, which this ticket does not cover. Exact wording:
>
> > "A std serializer encodes a `Map` or `Set` in iteration order. Decoding into a `Map` or `Set` adds keys in document order. Where a key occurs more than once, the first entry wins, as for `JsonValue.get` and derived `from_json` (§3.6.3), and later entries with that key are dropped. So a decode followed by an encode keeps the key order of the document, except for the dropped duplicates."
>
> The last clause is honest about what the round trip loses. A `Map` cannot hold duplicate keys, so the round trip is lossless only on documents without duplicates. `JsonValue.Object` stays the lossless path.
>
> ```blink
> let m: Map[Str, Int] = json.decode("\{\"a\": 1, \"b\": 2, \"a\": 3\}")?
> assert(m.keys() == ["a", "b"])
> assert(m.get("a") == Some(1))
> ```
>
> (The decode entry-point name is illustrative only.)
>
> STABLE, ready to vote.

- **DevOps:**

> **DevOps/Tooling: Phase D round 1 (Q6, Q7)**
>
> **Q6: I move to A, with a required cross-reference.** Q4-B passed, so §3.6 now states the fact in full ("two equal maps can iterate in different orders"). A separate B sentence next to the Debug text would be a third copy of the fact. My own C concern was drift, and B causes it. Web's need is findability, and one pointer meets it. Exact Debug-text addition:
>
> > "`debug()` sorts because `==` ignores order (see §3.6, Container Equality)."
>
> The pointer states the reason in six words and does not restate the rule. LSP hover on `debug` shows this line, which is where the "is this a bug?" question comes up.
>
> **Q7: A, with the duplicate rule changed to match the existing spec.** Min is right: under "last value" the same document gives two answers, one through `JsonValue.get`/`from_json` and another through a decode into a Map. A spec where those disagree is a bug report waiting to happen. Reopening first-entry is outside this ticket's scope, so the Map rule follows it. Exact wording:
>
> > "A std serializer encodes a `Map` or `Set` in iteration order. A std deserializer that builds a `Map` or `Set` adds entries in document order. Where a key occurs more than once, the **first** entry gives both the value and the position, as for `JsonValue.get` and derived `from_json`. A round trip therefore keeps key order."
>
> This is an exception to Q5's "built by inserts" sentence (collect from a list: last value, first position), and the spec must say so in one clause. Otherwise a model applies Q5 to decode. Suggested clause on the Q5 sentence: "except a std deserializer, which keeps the first entry for a duplicate key (§3.6.3)."
>
> Cross-language: Python and JS take the last value. Blink takes the first, by an existing ruling. RFC 8259 leaves duplicate keys undefined, so neither choice breaks the standard. Q7 changes nothing here; it only keeps Map in line.
>
> STABLE, ready to vote

- **AI/ML:**

> ## Q6: one home for the fact, plus a plain-words pointer at Debug
>
> I accept the drift concern. Write the fact once, in the identity sentence, which the Q4-B sentence already covers. The Debug text gets one sentence that gives the reason and links to it, without stating the rule again:
>
> > "`debug()` sorts so that equal maps print the same text (see Container Equality)."
>
> That gives the model its answer at the point where it hits the surprise, and the rule exists in one place only. Call it B-with-link or A-with-pointer; I vote for whichever label carries this wording. I lean B, because the Debug text must exist.
>
> ## Q7: I correct my ballot. Use A, with the first-entry rule
>
> I was wrong in C. Python `json` and JS `JSON.parse` keep the last value, but Blink already ruled that a lookup takes the first entry (§3.6.3). One document must give one answer, whether it is read through `JsonValue.get`, through `from_json` into a struct, or decoded into a Map. Consistency within the language matters more than the prior here. A model that learns "first entry wins" once can apply it everywhere. Two rules is the worst result. Reopening first-wins is a separate ticket, not this one.
>
> Exact wording:
>
> > "A std serializer encodes a `Map` or `Set` in its iteration order. Decoding into a `Map` or `Set` keeps document order. Where a key occurs more than once, the first entry gives both its position and its value, and later entries are skipped. This matches the lookup rule for `Object` (§3.6.3)."
>
> Note for the editor: decoding must not be defined as "insert each entry" (O1/O2), because O2 would make the last value win. Say "skips later duplicates". This differs from the Q5-A collect rule (last value), and that difference is correct. `collect()` is a sequence of inserts, but a decode reads a document whose rule already exists. The rationale doc should state this in one line, so nobody "fixes" one rule to match the other.
>
> STABLE, ready to vote.

- **Minimalism:**

> Minimalism: Phase D, round 1
>
> **Q6: I move to B, on one condition: the Debug note points to the rule and does not restate it.** Web is right about where users meet this fact. My objection was only that two copies can drift, and devops and sys raised the same point. A pointer fixes that. Wording:
>
> > "Two `==` maps can iterate in different orders (§3.6, *Container Equality*), so `debug()` sorts."
>
> That is one clause, with the rule kept in a single place: the Q4-B sentence. I vote against a B that restates the reason in full.
>
> **Q7: I move to a corrected A (A').** Making it normative is cheap, and the round-trip promise has a real use, so I drop B. But the duplicate-key rule must match §3.6.3, which says the first entry wins. Changing that is a separate spec question, and it is not in this ticket.
>
> The Python and JS habit is that the last value wins. I note that habit, but I do not reopen the rule here. If someone wants it reopened, that is a ticket for the queue.
>
> Exact wording:
>
> > "A std serializer writes a `Map` or `Set` in iteration order. A std decoder inserts keys in document order. Where a key occurs more than once, the first entry wins, as for `JsonValue.get` and `from_json` (§3.6.3), so the decoded `Map` holds the value a lookup on the document returns. Without duplicate keys, a decode followed by an encode keeps the key order."
>
> Notes:
> - "std serializers" covers JSON and TOML. TOML forbids duplicate keys, so in practice the duplicate clause applies only to JSON.
> - "First entry wins" means the first value and the first position. It needs no new insert rule: the decoder skips any key it has already seen.
>
> ```blink
> let m: Map[Str, Int] = json.decode("\{\"a\": 1, \"b\": 2, \"a\": 3\}")?
> assert(m.keys() == ["a", "b"])
> assert(m.get("a") == Some(1))
> ```
>
> (The decode call is only to show the rule; the panel did not vote on that name.)
>
> STABLE, ready to vote

##### Re-vote

The A/B labels on Q6 no longer matched what the seats meant, so the re-vote ballot restated them. **P** (pointer form): the fact is stated once, in §3.6, and the `debug()` text gets one sentence that points there. **R** (restate form): the `debug()` text states the fact and its reason again. On Q7, **A'** (first entry): a std serializer encodes in iteration order; a std deserializer adds entries in document order; the first entry of a duplicate key gives position and value, and later entries are ignored; a round trip without duplicate keys keeps key order. **B**: no new text.

Tally: Q6 P 6-0. Q7 A' 6-0.

- **Systems:**

> Q6: P
> Reasoning: The fact lives in one place, so it cannot drift. The pointer still answers a user who opens the Debug text after seeing `for` and `debug()` disagree. Any of the listed pointer sentences works, as long as it does not restate the rule.
> Concern: the editor could grow the pointer into a restatement over time, and we would be back at two copies.
>
> Q7: A'
> Reasoning: One document must decode to one answer whatever the target type, so the Map/Set decode follows the existing §3.6.3 first-entry rule. The decoder skips later duplicates, so this does not follow from insert semantics, and devops's exception clause on the Q5 sentence is required. "Insert if absent" costs the same probe as "insert or replace", so the runtime pays nothing.
> Concern: the `collect()` last-wins rule and the decode first-wins rule now differ, and the follow-up ticket must not get lost.

- **Web/Scripting:**

> Q6: P
> Reasoning: The dev who sees `for` and `debug()` print keys in different orders finds the reason at the exact place where the surprise happens. The fact itself lives in one place, so it cannot drift. Of the pointer sentences, I prefer sys's: it gives both the purpose (equal maps print the same text) and the fact (iteration order can differ) in one line.
> Concern: an editor could pick the aiml wording, which drops the "iteration order can differ" part, and then a reader learns why `debug()` sorts but not why `for` disagrees with it.
>
> Q7: A'
> Reasoning: One answer for one document across `JsonValue.get`, `from_json` and Map decode beats matching the Python/JS last-wins prior, because duplicate keys are rare and a disagreement between parsers is a known security bug class. Devops's exception clause on the Q5 sentence stops anyone deriving last-wins from "built by inserts".
> Concern: Python/JS-trained devs and models will expect last-wins on a duplicate key. The spec example should show a duplicate key and the first value winning, so that the rule is learned from one read.

- **PLT:**

> Q6: P
> Reasoning: The law appears in one place, §3.6. The `debug()` text gives one sentence that states the fact and points to that law, so the two cannot drift. Any of the proposed pointer sentences will do, provided it names both `==` and iteration order.
> Concern: A pointer that says only "`==` ignores order" leaves the reader to work out the step to iteration order, so the editor should prefer the sys or plt wording.
>
> Q7: A'
> Reasoning: With first-entry wins, `m.get(k) == o.get(k)` holds for every document `o` decoded to `m`, so one document gives one answer whichever way it is read. Devops's exception clause keeps the Q5 rule "built by inserts" true for every other derived Map. The round-trip claim is correctly limited to documents that have no duplicate keys.
> Concern: `collect()` keeps the last value and decode keeps the first entry, so the two disagree on duplicate keys until the follow-up ticket resolves that.

- **DevOps:**

> Q6: P
> Reasoning: The fact is stated once in §3.6, and the Debug text points to it, so the two cannot drift. LSP hover on `debug` still shows the reason at the point where users ask "is this a bug?". Of the proposed wordings I prefer sys's, because it names both the purpose (equal maps print the same text) and the fact.
> Concern: if the editor moves or renames the §3.6 section, the pointer goes stale, so the pointer should use the section name, which `blink doc` can resolve.
>
> Q7: A'
> Reasoning: One document gives one answer whether it goes through `JsonValue.get`, `from_json` or a decode into a Map, and a round trip without duplicate keys keeps key order, so config diffs and snapshot tests stay stable. Without the clause on the Q5 sentence, a model or a later encoder author would define decode as insert-each and get last-wins.
> Concern: users who come from Python or JS expect the last value to win on a duplicate key. A decode that silently skips later entries may surprise them, so a later ticket should consider a diagnostic or a strict-decode option for duplicate keys.

- **AI/ML:**

> Q6: P
> Reasoning: The fact lives in one place, so a model reads one rule and the copies cannot drift. The pointer at `debug()` answers the "why does debug not match my loop?" question at the point where a model hits it. I prefer sys's pointer, because it names both halves (same text, different iteration) in one short sentence.
> Concern: An editor may let the pointer grow into a second statement of the rule, which brings back the drift risk.
>
> Q7: A'
> Reasoning: One document must give one answer, whether code reads it through `JsonValue.get`, `from_json` or a Map decode. A model learns "first entry wins" once and applies it everywhere. The round-trip clause covers the snapshot-test case that matters, and devops's exception clause stops anyone from defining decode as insert-each.
> Concern: Models carry the Python/JS last-wins prior, so the follow-up ticket on collect versus decode should also weigh whether first-wins is worth that cost.

- **Minimalism:**

> Q6: P
> Reasoning: the fact is stated once, in §3.6, and the Debug text points to it, so the two texts cannot drift. Either plt's pointer or devops/web's is fine: one clause, plus a link.
> Concern: an editor could expand the pointer into a second statement of the rule over time, so the rationale record should say "pointer only".
>
> Q7: A'
> Reasoning: a decoder that keeps the first entry for a duplicate key agrees with §3.6.3, so one document gives one answer through every path. Devops's exception clause on the Q5 sentence is needed: without it, "built by inserts" would make a decode take the last value, against §3.6.3.
> Concern: `collect()` (last value wins) and decode (first entry wins) still differ, and models trained on Python and JS will expect the last value. The follow-up ticket must not be lost.

### Final Spec

```blink
let mut scores: Map[Str, Int] = Map()
scores.insert("carol", 3)
scores.insert("alice", 1)
scores.insert("carol", 4)
for (name, score) in scores {
    io.println("{name}: {score}")
}
// carol: 4
// alice: 1
```

- `Map` and `Set` iterate in insertion order. `insert` on a present key replaces the value and keeps the position. `remove` keeps the relative order of the rest. A re-insert after `remove` goes at the end. `keys()`, `values()`, `entries()` and `for` share one order.
- The hash seed is random per process and protects against hash flooding. It controls only bucketing and has no effect on any output. The layout that gives both (dense entries plus a seeded index) is a runtime choice and goes in `docs/build/`.
- `W1401 MapOrderAssumption` is withdrawn. The code is not reused for another lint.
- `--deterministic` and `BLINK_MAP_SEED` leave the spec. `--deterministic` stays one release as an accepted no-op that prints a note, then goes. `BLINK_MAP_SEED` stays as an internal knob, documented in `docs/build/` only.
- A compiler may reuse the result of a pure call only for arguments that are identical in representation. `==` does not license reuse. The Map-specific purity exclusion is gone.
- Every derived `Map`/`Set` is built by inserts: `clone()` keeps order; `a.union(b)` gives `a`'s order, then `b`'s new elements in `b`'s order; `collect()` and any build from a list keep the first position of a duplicate key and take the last value.
- `debug()` still sorts. The fact that two `==` maps can iterate in different orders is stated once, in §3.6 *Hash Contract and Seeding*; the `debug()` text points to it and does not restate it.
- A std serializer encodes a `Map`/`Set` in iteration order. A std deserializer adds entries in document order; for a duplicate key, the first entry gives position and value, and it ignores later entries.

Rules recorded here and not in the spec, because the feature does not exist yet:

- A future `intersection` or `difference` follows the order of the left operand (PLT, Phase A).
- A future `Map` literal keeps source order (Q5).

Why decode and `collect()` differ for a duplicate key: decode follows the §3.6.3 first-entry rule, so that a `Map` and `JsonValue.get` read the same value from one document. `collect()` follows `insert`, where a later insert replaces the value. Systems and Minimalism asked for a separate ticket on whether the two should agree. DevOps asked for a strict-decode option or a diagnostic for duplicate keys.

### Spec changes

- §3.6 *Hash Contract and Seeding*: the order rules, the derived-order rules, the hash seed paragraph, and the reuse sentence replace the random-order text and its sort example.
- §3.2.2 `MapOps` and `SetOps` tables and example comments: "unspecified order" becomes iteration order; the `union` row states its order.
- §3.6 *Container Debug Rendering*: one pointer sentence replaces the reason text.
- §3.6.2: new *Map and Set Order* subsection.
- §3c iterator table: `Set` and `Map` yield in insertion order.
- §8.10.7 (the seed flag, the variable and W1401) is deleted.
