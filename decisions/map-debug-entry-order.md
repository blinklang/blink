[< All Decisions](../DECISIONS.md)

# Map Debug Entry Order — Design Rationale

## Gap

Follow-up of the assert_eq Debug-bound deliberation ([assert-eq-debug-bound.md](assert-eq-debug-bound.md), Q4 6-0). `Set` Debug prints elements sorted by their debug strings, so `a == b` gives `a.debug() == b.debug()` under any hash seed. `Map` Debug printed entries in iteration order, which changes per process (random seed) and with insert and delete history.

```blink
let mut a: Map[Int, Str] = Map()
a.insert(1, "x")
a.insert(2, "y")
let mut b: Map[Int, Str] = Map()
b.insert(2, "y")
b.insert(1, "x")
// a == b is true, but a.debug() and b.debug() could differ between runs
```

## Result

| Question | Result | Vote |
|---|---|---|
| Q1 Map entry order | Sort entries by `key.debug()` text (UTF-8 bytes); on equal key text, by `value.debug()` text. No `Ord` bound | 6-0 |
| Q2 Debug/Eq law | Unchecked contract like `Hash`/`Eq`: `a == b` must give `a.debug() == b.debug()`; derived `Debug` obeys it when `Eq` is also derived; a hand `impl` of either must keep them in agreement | 6-0 |
| Q3 Float zero sign | Named as the one built-in exception: `-0.0 == 0.0` but they may render differently. Float output does not change | 6-0 |
| Q4 Iteration | `keys()`, `values()` and `for` keep iteration order; only `debug()` sorts | 6-0 |
| Q5 Example | `Map[Int, Str]` example `{1: "a", 10: "c", 2: "b"}` beside Set `{1, 10, 2}` | 6-0 |
| Q6 Layout | One shared *Set and Map order* paragraph that points back to the law | 6-0 |

No Phase D (every question 6-0). AI-first review: 5/5 pass.

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in independent-proposal → debate → vote rounds.

#### Phase A — Independent proposals

All six proposed the same rule (O1). All who addressed them rejected sorting whole `"k: v"` entry strings and ordering by `Ord` on `K`. Full proposals, verbatim:

**Systems:**

> Debug is not a hot path, but it still needs predictable cost and a rule with no gaps. The one gap is two distinct keys whose debug texts match, which a hand-written `impl Debug` can produce. So I propose a two-level sort key.
>
> ## Proposal S1 (recommended): sort by key text, then by value text
>
> Spec text: "`Map[K, V].debug()` renders each entry's key text (`key.debug()`) and value text (`value.debug()`). It sorts the entries by key text, comparing UTF-8 bytes. When two key texts are equal, it sorts those entries by value text. It then joins them. It does not use iteration order."
>
> ```blink
> let a = {1: "x", 2: "y", 10: "z"}
> let b = {10: "z", 2: "y", 1: "x"}
> assert_eq(a.debug(), b.debug())   // both: {1: "x", 10: "z", 2: "y"}
>
> let s = {1, 2, 10}
> // s.debug() == "{1, 10, 2}"  -- same text order as the Map keys above
> ```
>
> The tie-break case:
>
> ```blink
> type Tag { id: Int }
> impl Debug for Tag { fn debug(self) -> Str { "Tag" } }   // not injective
> let m = {Tag { id: 1 }: "b", Tag { id: 2 }: "a"}
> // m.debug() == "{Tag: \"a\", Tag: \"b\"}" under every seed
> ```
>
> If both the key text and the value text tie, the two entries print the same, so their order cannot change the output. The output is fully fixed under every seed and every insert/delete history. That holds whether or not the user's Debug gives each key distinct text.
>
> What it compiles to:
> 1. Render n `(key_str, val_str)` pairs once. The join needs these strings anyway, so this adds no allocations beyond what the current code makes.
> 2. Sort an index array: O(n log n) memcmp calls on the key text, and on the value text only when key texts tie.
> 3. Join into one buffer, sized ahead because the lengths are already known.
>
> Fast path: when n ≤ 1, skip the sort. The extra cost over today is one index array and the comparisons. Debug runs in failure paths, power-assert, and NDJSON introspection, so this cost does not matter.
>
> There is no `Ord` bound and no new trait. The rule is the same one Set uses.
>
> ## Rejected S2: sort whole entry strings (`"k: v"`)
>
> This is simpler, because Map would reuse Set's "sort rendered strings" helper as-is. But `':'` (0x3A) sorts above `'0'` (0x30), so `{1: x, 10: y}` renders as `{10: y, 1: x}`, while the Set `{1, 10}` renders as `{1, 10}`. Set and Map would then disagree on key order, which is exactly what this ticket exists to stop. Not worth saving a few lines of helper code.
>
> ## Rejected S3: sort by key value (`K: Ord`)
>
> This gives a nicer order for Int keys, but it adds a bound that Debug does not have, and it breaks the decided Set rule. Rust's `HashMap` Debug has the same seed problem, and Rust tells users to switch to `BTreeMap`. Blink has no ordered map, and assert_eq needs determinism now.
>
> ## Implementation note (not spec text)
>
> Set (svsm5t, still open) and Map should share one runtime helper: "sort an array of rendered string tuples, comparing elements left to right". Set calls it with 1-tuples and Map with 2-tuples. That gives one code path and one set of tests, so the two rules cannot drift apart. Nested containers (a Map whose values are Sets or Maps) are already fixed, because each inner render is sorted by its own rule first.
>
> Cross-language: Python `dict` repr uses insertion order, which Blink cannot use because it is a history. Go's `fmt` sorts map keys by value for printing, the same idea with a value order in place of a text order.

**Web/Scripting:**

> Web/Scripting proposal (rjcx1g, Map Debug entry order): sort entries by key debug text, the same rule as Set, with one tie-break.
>
> **Proposal W1 (my vote): sort by key debug text, then by value debug text (UTF-8 bytes)**
>
> ```
> let a = {1: "x", 2: "y", 10: "z"}
> let b = {10: "z", 2: "y", 1: "x"}
> assert_eq(a, b)          // passes
> a.debug()                // {1: "x", 10: "z", 2: "y"}  every run, every seed
> b.debug()                // same text
> ```
>
> Rule: render each entry as `key.debug() + ": " + value.debug()`. Sort by the key text (bytes). If two keys give the same text, sort by the value text. Then join with ", ".
>
> Why the tie-break: keys are unique by Eq, but a hand-written `impl Debug` can give two different keys the same text (say a User whose Debug prints only the name). Without a tie-break, the order of those two entries falls back to iteration order, and two equal maps can print differently again. That is a rare case, but it is exactly the flaky-CI bug that turns into a Stack Overflow question nobody can reproduce. With the tie-break, two equal maps always print the same text. Two entries can tie on both key and value text only when they print the same, so their order cannot show.
>
> Why not sort the whole entry string: the ": " separator gets mixed into the compare. Key "a" sorts before key "a b", but entry "a: 1" sorts after "a b: 2" (':' is 0x3A, ' ' is 0x20). Users read the output as "sorted by key", so the rule must actually be "sorted by key".
>
> **DX cost, stated plainly:** `{1: .., 10: .., 2: ..}` will surprise people. Python 3.7+ and JS `Map` keep insertion order, and Python devs expect it. But Blink already said no to that (hash-seed decision), and Set already prints `{1, 10, 2}`. One rule for both containers is easier to learn than two. Tell users in one sentence what Debug order is for: a stable test diff, not a display. For display, use `m.keys().sort()` and format it yourself.
>
> **Spec text to add** (next to the Set paragraph): "`Map[K, V].debug()` sorts entries by the UTF-8 bytes of `key.debug()`, and by `value.debug()` when two keys render the same. It does not use iteration order, for the same reason as Set. `Map.keys()`, `.values()` and `for` loops still use iteration order." The last sentence stops people from thinking Debug order leaks into iteration.
>
> **Proposal W2 (rejected by me, listed for the record): numeric order for scalar keys.** It is friendlier for Int keys, but it needs an Ord path that Set already turned down, and then Set and Map follow different rules. No.
>
> **Process:** this is a direct follow-up of a 6-0 vote. Do not reopen Set's rule here. Land Map together with svsm5t so the two rules ship in one release and nobody sees a version where Set is sorted and Map is not.
>
> Cross-language: Rust's `HashMap` Debug uses iteration order (flaky across runs); Python's `pprint` sorts dict keys by default, which is the same idea as this proposal.

**PLT:**

> PLT proposal (Map Debug order): sort entries by the (key text, value text) pair, and state the Debug/Eq rule that this sort depends on.
>
> P1 (main): sort by the pair (key.debug(), value.debug()), comparing UTF-8 bytes, key text first.
>
>     let m = {10: "a", 2: "b", 1: "c"}
>     // renders {1: "c", 10: "a", 2: "b"}
>
> Typing rule: render(m) = "{" + join(", ", sort_lex(map(m.entries, (k,v) => (dbg k, dbg v))) as "k: v") + "}". No Ord bound. Needs only K: Debug and V: Debug, the bound we already have.
>
> Why the pair and not the key text alone: a hand-written Debug does not have to be injective. If two distinct keys render the same text, a sort on key text alone leaves the tie to iteration order, and the result changes with the seed. That is exactly the bug we are closing.
>
>     struct Id { n: Int }
>     impl Debug for Id { fn debug(self) -> Str { "Id" } }
>     let a = {Id { n: 1 }: "x", Id { n: 2 }: "y"}
>     // key text ties, value text breaks the tie: {Id: "x", Id: "y"}
>
> With the pair order, entries tie only when their rendered text is the same, so their order cannot change the output. The output is then a function of the multiset of rendered entries. Proof: equal maps give equal multisets, so they give equal strings.
>
> Composition: a Set[T] is the same as a Map[T, ()]. On the key part, the pair order agrees with the Set rule, so the two containers follow one rule. The order composes inductively: if each K and V debug is canonical (same value, same text), the container debug is too, which covers nested values such as Map[Str, Set[Int]].
>
> Rejected: sorting the whole "k: v" string. It also gives a deterministic order, but a key whose text contains ": " can put an entry between the entries of another key. The pair order keeps entries with the same key text together and reads better. Also rejected: an Ord bound on K. It contradicts the Set rule and the Debug-only bound that the panel already decided.
>
> P2 (needed for P1 to be sound): state a coherence law in §3.6.1. For a type that is both Eq and Debug, a == b must give a.debug() == b.debug(). Derived Debug obeys it. A hand impl must obey it, but the compiler cannot check that, so it is a contract, the same kind as Hash agreeing with Eq. Without the law, sorting does not give the guarantee: if k1 == k2 but their texts differ, two equal maps that hold different representatives render differently under any order. The same gap is open for Set today, so add one sentence that covers both, and say that a Debug that breaks the law voids the "a == b gives same debug" promise for Map and Set.
>
> Cross-language: Haskell's Show for Data.Map renders in key order because Map is an ordered tree, which needs Ord. OCaml offers no polymorphic printer for Hashtbl, for the same reason. Python's dict repr uses insertion order, which Blink rejected (hash-seed decision). Sorting by text gets the canonical output without Ord, and that fits Blink's bounds.
>
> Vote intent: P1 + P2 together. P1 alone is incomplete because the tie-break is required for soundness.

**DevOps:**

> **DevOps/Tooling: Map Debug entry order**
>
> I judge this by its output in CI logs, `assert_eq` failures and golden files. Right now `Map.debug()` follows hash order, so the same test can print different text on two runs. A test that fails with different text each time makes people stop trusting the test.
>
> **Proposal D1: sort by key debug text, break ties on value debug text (recommended)**
>
> `Map[K,V].debug()` renders each key and each value with `.debug()`. It then sorts the entries by the key string's UTF-8 bytes. When two key strings are equal, it sorts by the value string's bytes. Then it joins the entries.
>
> ```blink
> let a = {10: "x", 2: "y", 1: "z"}
> let b = {1: "z", 2: "y", 10: "x"}
> assert_eq(a.debug(), b.debug())
> // both => "{1: \"z\", 10: \"x\", 2: \"y\"}"
> ```
>
> Why I want the tiebreak: distinct keys can still print the same text. A user can write `impl Debug` by hand and leave out a field, for example a `User` key whose Debug prints only `name`. If we sort by key text alone, entries with equal key text keep their hash order, and the bug comes back for exactly the types where it is hardest to see. With the value as tiebreak, two entries can only tie if they print the same full text, and then their order cannot change the output. The rule then holds for every Map: `a == b` gives `a.debug() == b.debug()`, with nothing left to chance.
>
> Tooling benefits:
> - **assert_eq diffs line up.** If two maps differ in one value, the output differs at one place, not all through the text. If you sort by the whole entry string instead, a changed value can move its entry somewhere else in the order.
> - **Golden files stay stable** across seeds, compiler versions and `BLINK_MAP_SEED`. People stop adding `--deterministic` to tests just to work around Debug.
> - **Same rule as Set** (sort by text), so people only need to learn one rule. Set does not need a tiebreak, because two elements with the same text print the same.
> - **Order is by text, not by value.** `{1, 10, 2}` reads oddly, but Set already has it. Document it with the same `1, 10, 2` example.
>
> **Rejected: D2, sort by the full `key: value` text.** It is simpler to state, but `"a"` and `"a b"` sort in a different order than they do by key alone, because `" "` sorts before `":"`. A value change can also move an entry in the order, so diffs get noisy. A small saving in the spec text is not worth worse diffs.
>
> **Rejected: D3, sort by `K: Ord` when the key has it.** That gives two rules that depend on the type, adds a hidden bound, and output would change when someone adds `Ord` to a key type. Diagnostics should not change because of an unrelated impl.
>
> **Spec text, next to "Set element order":** "`Map[K,V].debug()` sorts entries by the UTF-8 bytes of the key's debug string, then by the value's debug string. It does not use iteration order (same reason as Set)." Also add a one-line note that `keys()`, `values()` and `for` loops still use iteration order. Debug sorts its output only; the Map itself has no sort order.
>
> **Other languages:** Python dicts print in insertion order, and Go's `fmt` has printed maps sorted by key since 1.12 to make test output stable. Go's change is the closest precedent and it was popular. Rust's `HashMap` Debug follows hash order, and people often complain about it in snapshot tests (insta users switch to `BTreeMap`).
>
> **Cost and follow-up:** Sorting is O(n log n) and only runs when Debug runs. The Debug output is diagnostic text, so speed matters little here. Land this with svsm5t (Set) so both change in one release, and add a corpus test that builds the same map in two insert orders under two seeds and compares the debug text.

**AI/ML:**

> # AI/ML panelist: Map Debug entry order
>
> ## Proposal A (recommended): sort by key debug text, break ties on value debug text
>
> Rule: `Map[K, V].debug()` renders each entry as `key.debug() + ": " + value.debug()`. It sorts the entries by the key's debug string, comparing UTF-8 bytes. If two keys render the same text, it sorts those entries by the value's debug string. Then it joins them. It does not use iteration order.
>
> ```blink
> let a = {1: "x", 2: "y", 10: "z"}
> let b = {10: "z", 2: "y", 1: "x"}
> assert_eq(a, b)
> // both render: {1: "x", 10: "z", 2: "y"}
>
> let s = {1, 2, 10}
> // renders: {1, 10, 2}   (same rule as Set)
> ```
>
> Why the tie-break: a hand-written `impl Debug` can give two different keys the same text. Without a second key in the sort, two equal maps could still render differently. With key text first and value text second, the output depends only on the set of (key text, value text) pairs. That gives `a == b` implies `a.debug() == b.debug()` in every case, with no hidden exception.
>
> Nesting works. A `Map[Str, Set[Int]]` or a `Map[Str, Map[...]]` has inner values whose text is already fixed. So the outer sort is fixed too.
>
> **AI/ML tradeoffs:**
> - **No new decision points.** Set and Map follow one rule: "containers with no order sort by text." A model learns it once and uses it for both. Two rules (sorted Set, unsorted Map) would be a trap that models hit in golden-output tests.
> - **Output a model can predict.** Today a model cannot write the expected `debug()` string of a Map for a snapshot test, because the order is random. After this change it can.
> - **Known trap: text order is not number order.** Models will guess `{1, 2, 10}`. Fix this in the spec text: put the `{1: "x", 10: "z", 2: "y"}` example next to the Set example, not in a separate section. One example costs about 20 tokens and stops the most common wrong guess.
> - **Token cost:** none at use sites. There is no new syntax or bound.
>
> ## Rejected alternative B: sort the full entry string
>
> This rule is shorter to state, but `"10: z"` sorts before `"1: x"`, because `0` (0x30) comes before `:` (0x3A). The output would be `{10: "z", 1: "x", 2: "y"}`. That order matches neither Set nor intuition. A model would get it wrong almost every time. Reject.
>
> ## Rejected alternative C: use `Ord` on the key when it exists, text otherwise
>
> This adds a branch: the model must know whether K implements `Ord` before it can predict output. Set already declined an `Ord` bound (Q4). Two ordering modes means twice the cases for a model to learn, and they disagree for `Int` keys. Reject.
>
> ## Cross-language notes
>
> - Python `pprint` sorts dict keys by default (`sort_dicts=True`), so sorted Debug is familiar.
> - Go's `fmt` sorts map keys when it prints them, which is the same reason: stable output for tests.
> - Rust `HashMap` Debug uses iteration order. Rust users and models learn to use `BTreeMap` for tests to work around it. Blink should not copy that trap.
>
> ## Spec wording for the moderator
>
> "`Map[K, V].debug()` sorts entries by the key's rendered string, then by the value's rendered string, comparing UTF-8 bytes. It does not use iteration order. A `Map[Int, Str]` with keys 1, 2 and 10 renders `{1: ..., 10: ..., 2: ...}`."
>
> **Vote intent:** A.

**Minimalism:**

> **Minimalism — Phase A: Map Debug entry order**
>
> "Do nothing" is not on the table. Q4 already chose canonical order, and each of us named Set/Map drift as the risk. The only real question is what to sort by, and the smallest rule that is fully correct.
>
> **Proposal M1 (preferred): sort by key debug text, then by value debug text. Both use UTF-8 bytes.**
>
> ```blink
> let a = {1: "x", 2: "y", 10: "z"}
> let b = {10: "z", 2: "y", 1: "x"}
> assert_eq(a.debug(), b.debug())   // both: {1: "x", 10: "z", 2: "y"}
> ```
>
> Spec text, one sentence beside the Set paragraph: "`Map[K, V].debug()` sorts its entries by the key's debug string, then by the value's debug string, both by UTF-8 bytes. It does not use iteration order, for the same reason as Set."
>
> Why add the value tiebreak? It closes a hole that key-only sorting leaves open:
> - Keys are unique by `Eq`, but their debug text does not have to be. A hand-written `impl Debug for UserId` can leave out a field, so two distinct keys can print the same text.
> - With key-only sorting, the order of those two entries falls back to iteration order, and `a == b ⇒ a.debug() == b.debug()` fails again in exactly the case that is hardest to debug.
> - Two equal maps hold the same (key, value) pairs, so sorting the (key text, value text) pairs always gives the same output. If both texts tie, the two entries print the same, so their order cannot be seen.
> - The cost is one more compare on the cold path. It needs no Ord bound and no new concept.
>
> **Rejected variant M2: sort the whole rendered entry string (`key + ": " + value`).**
> This looks like "literally the Set rule", but the `": "` separator corrupts the order. `"1: x"` vs `"10: z"` compares `:` (0x3A) with `0` (0x30), so 10 comes before 1: `{10: "z", 1: "x", 2: "y"}`. That breaks the match with Set, where `{1, 10, 2}` puts 1 first. Users would see two order rules for one idea. M1 avoids that, because the key text alone sorts exactly the way Set elements do.
>
> **Rejected variant M3: order by `Ord` on K when K has it.**
> This adds a conditional path, so output would depend on which traits a type has. Q4 already rejected that idea for Set.
>
> **Scope discipline:**
> - Debug only. `keys()`, `values()`, iteration and `for` keep hash order, as the hash-seed decision says. No "sorted map", no change to iteration, no Display for Map.
> - Text order, not value order, same as Set. The spec should show an `Int`-key example so nobody "fixes" it to numeric order.
> - Ship it in the same change as the Set sort (svsm5t is still open). One helper, "render the parts, sort by bytes, join", serves both, so the two rules cannot drift apart.
>
> **Cross-language note:** Python dicts print in insertion order. That would break Blink's rule that equal maps print the same. Go's `fmt` sorts map keys when it prints them, so a sorted print is a proven, cheap choice. Blink's version is smaller because it sorts on text and needs no ordering trait.
>
> **Vote intent:** M1.

#### Phase B — Debate (round 1)

The moderator broadcast O1 plus three variations: V1 (PLT: a Debug/Eq coherence law in §3.6.1), V2 (an iteration-order clause), V3 (an Int-key example). Key shifts: PLT amended its own V1 wording ("derived Debug obeys it" holds only when `Eq` is also derived) and raised the `Float` `-0.0` case; AI/ML raised the one-shared-paragraph layout. All six signalled "stable, ready to vote" after round 1. Replies, verbatim:

**Systems:**

> **O1: adopt.** This is my S1. Cost stays as I gave it in Phase A: n string pairs that the join needs anyway, one index array, O(n log n) memcmp calls, and a fast path that skips the sort when n ≤ 1. There is no new bound and no new trait.
>
> **V1: adopt.** PLT found a hole in my Phase A claim. I said the output is fixed whether or not each key gets distinct text. That covers distinct keys whose texts are equal. It does not cover equal keys whose texts differ. Take a struct whose `Eq` ignores a field that its `Debug` prints. Two equal maps can then hold different representatives of the same key and render differently under any order. No sort can fix that, only a contract can. The law costs nothing at runtime: no checks, and no change to the code we generate. Rust handles Hash against Eq the same way, as a documented, unchecked contract. Amend: have the spec sentence also say that derived Debug always obeys the law, so users know the risk exists only in a hand impl.
>
> **V2: adopt.** Iteration order has to stay unsorted. Sorting `keys()`, `values()` or `for` loops would put a hidden O(n log n) and an allocation on hot paths that never asked for them. Debug may pay that cost because it runs on failure and introspection paths. Iteration may not. One sentence prevents a later "make keys() match debug()" request.
>
> **V3: adopt.** Putting the Int-key example next to the Set `{1, 10, 2}` example costs nothing and blocks a likely wrong bug report ("debug sorts wrong"). It also shows that Set and Map follow one rule.
>
> **New point (implementation, not spec):** Set (svsm5t) and Map should share one runtime helper that sorts tuples of rendered strings element by element, 1-tuples for Set and 2-tuples for Map. Then the two rules cannot drift apart. The svsm5t ticket should note this so Map does not get a second copy of the code.
>
> stable, ready to vote

**Web/Scripting:**

> Web/Scripting, Phase B round 1: adopt O1, adopt V1 with a wording amendment, adopt V2, adopt V3. Stable, ready to vote.
>
> **O1: adopt.** It is my W1 unchanged. One rule for Set and Map, no Ord bound, and the same text every run.
>
> **V1 (coherence law): adopt, with an amendment.** PLT is right that sorting alone does not close the gap. Take a key type whose Eq ignores case but whose Debug keeps it: two equal maps can hold "Bob" and "bob" and print differently under any sort. Most users derive Debug and will never hit this, so the cost is near zero. The ones who write Debug by hand already accept the same kind of contract for Hash and Eq. Amendment: keep the wording to one plain sentence plus one example, not a law in formal language. A JS or Python dev should be able to read it in 10 seconds. Suggested text: "If you write Debug by hand for a type that also has Eq, equal values must print the same text. Derived Debug always does. If your Debug breaks this, equal maps and sets can print differently."
>
> **V2 (iteration order unchanged): adopt.** Without this sentence someone will see sorted debug output, assume `for k in m` is sorted too, and ship a bug. One sentence prevents a whole class of Stack Overflow questions.
>
> **V3 (Int-key example): adopt.** `{1: "x", 10: "z", 2: "y"}` next to Set's `{1, 10, 2}` shows the rule faster than prose does. It also stops a well-meaning contributor from "fixing" it to numeric order later.
>
> No new points.
>
> Stable, ready to vote.

**PLT:**

> PLT round 1: adopt O1, adopt V1 with two amendments, adopt V2, adopt V3.
>
> O1: adopt. The value-text tie-break keeps it sound when a hand Debug gives two keys the same text, and it agrees with the Set rule when we read Set[T] as Map[T, ()].
>
> V1: adopt, with two amendments to my own wording.
> (a) "Derived Debug obeys it" is too strong. It holds only when Eq is also derived. A hand Eq with a derived Debug breaks the law: for example, an Eq that ignores case, where "A" == "a" but the debug texts differ. Proposed text: "derived Debug obeys the law when the type's Eq is also derived".
> (b) Built-in exception: Float. Map equality compares V with ==. If 0.0 == -0.0 and Float's debug renders the sign, then {1: 0.0} == {1: -0.0} but the two debug texts differ under any order. NaN is fine, because the law only runs one way. The spec must either name this case ("Float values that compare equal can render differently, so the promise holds only up to this case") or confirm that Float debug renders -0.0 as "0.0". I prefer naming the case. We should not change Float output to make a Map promise hold. Without the law plus this note, O1 claims a property it cannot deliver.
>
> V2: adopt. It separates the debug rendering from the iteration semantics and fits the hash-seed decision. It costs one sentence.
>
> V3: adopt. A counterexample next to the rule stops readers from assuming numeric order.
>
> New point: none beyond V1(b).
>
> stable, ready to vote

**DevOps:**

> **DevOps/Tooling, Phase B round 1**
>
> **O1: adopt.** Sorting by key text and then by value text gives one fixed output order. A changed value then shows up in only one spot in an `assert_eq` diff, and golden files stay the same whatever the seed.
>
> **V1: adopt, with an amendment.** We need the law, or a hand-written Debug can quietly break the Map and Set guarantee. But Blink's own Float breaks it as written. §3.x says `-0.0 == 0.0` is true and that NaN equals NaN. Map *values* can be Float (only keys are rejected, by E1400). So `{1: 0.0} == {1: -0.0}` is true, but the debug text differs if Float Debug prints the sign. I want Debug to keep printing `-0.0`: when a test fails, that sign is often the bug, and hiding it would make the failure output wrong. So my amendment is to state the law, then name Float as the one built-in exception: "`-0.0` and `0.0` are `==` but render as `-0.0` and `0.0`. A value that holds a Float can break `a == b ⇒ same debug` for this reason only." That puts the gap in the spec, where people can see it. Without it, a user who notices this will report it as a bug. Separately, the spec does not say how Float Debug renders `-0.0` or NaN. That is a small gap and it needs its own friction ticket.
>
> **V2: adopt.** One sentence stops people from treating `keys()` order as sorted because the debug output looks sorted.
>
> **V3: adopt.** An example with Int keys (`{1: "a", 10: "b", 2: "c"}`) shows that the order is by text. Without it, someone will report the order as a bug, or "fix" it to numeric order.
>
> **New point, adopt with no extra vote:** the corpus test must build two equal maps with different insert and delete histories, and run them under two values of `BLINK_MAP_SEED`. Two seeds alone would miss a bug that only shows up after deletes.
>
> stable, ready to vote

**AI/ML:**

> **AI/ML panelist, Phase B round 1**
>
> **O1: adopt.** It gives one rule for Set and Map, so a model learns it once. It also adds no bound and no syntax.
>
> **V1: adopt, with one amendment.** PLT found a real gap in my Phase A claim of "no hidden exception." If `k1 == k2` but their texts differ, no sort order can save the guarantee. The fix costs one sentence, and it uses the Hash/Eq contract that models already know from Rust (`Hash`/`Eq`), Java (`hashCode`/`equals`) and Python (`__hash__`/`__eq__`).
>
> The amendment: "derived Debug obeys it" is only true when Eq is also derived. Suppose a user writes a case-insensitive `impl Eq` by hand and derives Debug. Then `"Bob"` and `"bob"` are equal but render differently. So the law should bind the Eq and Debug pair: "if either impl is hand-written, the author must keep them in agreement." Models write exactly this pattern (custom Eq, derived Debug) often, so the spec should name it.
>
> **V2: adopt.** Without it, models will over-generalize from "Map Debug is sorted" to "Map is sorted." They will then write `for k in m` and expect sorted keys. One sentence stops a likely wrong guess. Keep the existing `scores.keys().sort()` example next to it to show the correct idiom.
>
> **V3: adopt.** It is the cheapest fix for the most likely wrong guess (`{1, 2, 10}`). Put both examples, Set and Map, in the same paragraph so a model that reads one reads the other.
>
> **New point (low cost):** have the Set and Map rules share one paragraph, along the lines of "Containers with no defined order sort by rendered text." Then add the Map tie-break as a clause. Two separate paragraphs invite the two to drift apart in later edits.
>
> stable, ready to vote

**Minimalism:**

> **Minimalism — Phase B round 1**
>
> **O1: ADOPT.** It is the smallest rule that is correct. It needs no new trait bound and no conditional path, and the same "render, sort by bytes, join" helper serves both Map and Set.
>
> **V1 (coherence law): ADOPT, amended to one sentence.** PLT is right, and my M1 tiebreak does not cover this case. A map keeps whichever key it was given at insert time. If k1 == k2 but the two keys print different text, two equal maps print differently under any sort. That is a real hole, and it is open for Set today. The fix adds no mechanism: one contract sentence of the same kind as "Hash must agree with Eq", which the spec already has as precedent. Amendment: keep it one sentence in §3.6.1, add no lint or check, and do not repeat it in the Map and Set paragraphs. Those can point back to it in a few words ("given the Debug/Eq law").
>
> **V2 (iteration order unchanged): ADOPT, as one clause, not a paragraph.** It follows from the hash-seed decision, but readers will ask "does sorting Debug mean keys() is sorted?". A clause costs less than the questions.
>
> **V3 (Int-key example): ADOPT.** Merge it into the existing Set example line rather than adding a new block, e.g. `{1, 10, 2}` and `{1: "a", 10: "c", 2: "b"}`. One example blocks the "fix it to numeric order" mistake for both types.
>
> **New point:** none of this may grow into a sorted-iteration API or a `--sorted` flag later. Debug is the only place that needs canonical order.
>
> stable, ready to vote

#### Phase C — Final vote

Every question passed 6-0 for option A. In Q2, Systems and Web/Scripting withdrew their round 1 "derived Debug always obeys" wording (option B). Ballots, verbatim:

**Systems:**

> Q1: A
> Reasoning: Rendering the n string pairs, sorting an index array with memcmp, and joining has a cost we can predict. Almost all of it is allocation the join makes anyway, and when n ≤ 1 the sort is skipped. Debug runs on failure and introspection paths, so the O(n log n) cost does not matter there. It adds no bound, no trait and no new code shape.
> Concern: if the Set implementation (svsm5t) and the Map implementation are written separately, they can drift apart unless both share one sort helper.
>
> Q2: A
> Reasoning: My own round 1 wording ("derived Debug always obeys") is wrong. A hand-written case-insensitive Eq with a derived Debug breaks the law, so the text must say derived Debug obeys it only when Eq is also derived. The contract costs nothing at runtime and changes no generated code. It is the same kind of contract as Hash agreeing with Eq.
> Concern: we cannot check the contract, so a user's bad Eq/Debug pair will show up as a flaky-looking assert_eq message, not as a diagnostic.
>
> Q3: A
> Reasoning: -0.0 and 0.0 are different bit patterns, and they act differently (1.0 / -0.0 gives -inf). Debug output that hides the sign would hide a real bug cause when a test fails. Name the one exception, and do not change Float output to keep a container promise.
> Concern: readers may skim past the exception and still report `{1: 0.0}` against `{1: -0.0}` as a bug, so the note should carry a tiny example.
>
> Q4: A
> Reasoning: Iteration must stay at hash order with no sort, so `for`, `keys()` and `values()` pay no hidden O(n log n) and no allocation. One clause stops a future request to make them match debug().
> Concern: a clause that is too long would repeat the hash-seed decision rather than point to it.
>
> Q5: A
> Reasoning: The example costs nothing and blocks a wrong "fix" to numeric order. A numeric order would need an Ord bound and a second code path.
> Concern: none of substance.
>
> Q6: A
> Reasoning: In the runtime, one paragraph matches one helper (sort tuples of rendered strings element by element: 1-tuples for Set, 2-tuples for Map). Two paragraphs invite two code paths and later drift.
> Concern: the shared paragraph must still state the Map tie-break clearly, or someone will build Map on a key-only sort.

**Web/Scripting:**

> Web/Scripting ballot, Phase C (Map Debug order). Votes: Q1 A, Q2 A, Q3 A, Q4 A, Q5 A, Q6 A.
>
> Q1: A
> Reasoning: One rule for Set and Map is the easiest thing for a JS or Python dev to learn, and test output becomes the same every run. Equal maps print the same text, so assert_eq failures stop being flaky.
> Concern: people coming from Python dicts expect insertion order, so `{1: .., 10: .., 2: ..}` will still produce some "is this a bug?" questions.
>
> Q2: A
> Reasoning: I withdraw my own "derived Debug always obeys it" wording. PLT and AI/ML are right that a hand-written case-insensitive Eq with a derived Debug breaks the law, and that is a pattern web devs write often. Telling them "derived is always safe" would be a false promise, and it would bite exactly the people least likely to read the fine print.
> Concern: if the wording grows into formal-law prose, readers will skip it. Keep it to one plain sentence plus the case-insensitive example.
>
> Q3: A
> Reasoning: JS devs already know that -0 === 0, so naming this as a quirk will not confuse them. Hiding the sign in debug output would make failure messages lie at the moment the sign is the bug. Naming the exception in the spec is better than one more silent special case.
> Concern: the spec does not yet say how -0.0 and NaN render, so this note could point at undefined behaviour until the Float display ticket lands.
>
> Q4: A
> Reasoning: Without this clause, users will assume `for k in m` is sorted because debug output looks sorted, and they will ship that bug. One clause prevents a whole class of questions.
> Concern: none worth naming.
>
> Q5: A
> Reasoning: An example teaches faster than prose, and it stops anyone from "fixing" the order to numeric later.
> Concern: if the Map example sits too far from the Set example, readers will miss that they show one rule.
>
> Q6: A
> Reasoning: One shared paragraph means one place to read and one place to edit. Two paragraphs will drift apart over later edits.
> Concern: the shared paragraph must still make the Map tie-break easy to find, not hide it as a sub-clause.

**PLT:**

> PLT ballot (Map Debug order): Q1 A, Q2 A, Q3 A, Q4 A, Q5 A, Q6 A.
>
> Q1: A
> Reasoning: The pair order (key text, then value text) is a total order on rendered entries. Entries tie only when they render the same text, so the output depends only on which entries the map holds, and so on equality, given the Q2 law. It needs no Ord bound, and it gives the Set rule if we read Set[T] as Map[T, ()].
> Concern: An implementation might sort on key text alone with a stable sort, and that brings back seed-dependent order when two keys render the same text. The corpus test must cover a pair of keys that render the same text.
>
> Q2: A
> Reasoning: Option B states something false. A derived Debug with a hand-written Eq (an Eq that ignores case, or one that skips a field) breaks the law, and the panel itself gave three such counterexamples. A law the spec states falsely is worse than no law, because users and models will trust it. Tying the contract to the Eq/Debug pair gives the correct rule.
> Concern: A writer might trim the wording back to "derived Debug always obeys it" in a later edit, so the text should say why the pair matters.
>
> Q3: A
> Reasoning: Per §3 lines 2927–2930, no Float equality tells -0.0 from 0.0, so under any order the law fails for every value that holds a Float. Option C would leave a built-in type that breaks a spec promise without a word. Option B would change Float output to rescue a Map property and hide a sign that is often the bug. Naming the exception is the honest, minimal fix. How Float renders -0.0 stays with the open Float display ticket.
> Concern: If the Float display ticket later renders -0.0 as "0.0", this exception text goes stale and must be removed.
>
> Q4: A
> Reasoning: Sorting is a property of the debug rendering, not of the Map value or its iteration. Saying so keeps the hash-seed decision intact.
> Concern: None material.
>
> Q5: A
> Reasoning: A counterexample beside the rule pins text order against the numeric-order reading.
> Concern: None material.
>
> Q6: A
> Reasoning: One paragraph states one rule for both types, with the Map tie-break as a clause and a pointer to the §3.6.1 law. Two paragraphs would let the rules drift apart and obscure that Set is the special case of Map.
> Concern: The shared paragraph must still give the Map tie-break plainly and not leave it implied.

**DevOps:**

> Q1: A
> Reasoning: Sorting by key text and then by value text gives Map Debug one fixed output. It holds for every hash seed and every insert and delete history. `assert_eq` failures and golden files then stay the same from run to run, and a changed value shows up at only one spot in the diff. It uses the same text-sort rule as Set, so there is only one rule to learn and one to support in tools.
> Concern: Users will see `{1: .., 10: .., 2: ..}` and report it as a bug unless the example (Q5) sits next to the rule.
>
> Q2: A
> Reasoning: B is wrong for a hand-written Eq with derived Debug. A case-insensitive Eq gives `"Bob" == "bob"`, but the two print different text. If the spec says "derived always obeys", we will get bug reports that the spec text itself causes. A states the condition correctly, and it is the same kind of contract users already know from Hash agreeing with Eq.
> Concern: Nothing checks the law, so a broken hand impl will show up only as a test that fails at random, with no diagnostic. We should log a friction ticket for a lint later, but not in this vote.
>
> Q3: A
> Reasoning: Printing `-0.0` is useful when a test fails, because the sign is often the bug. If B hid it, the failure output would lie about the value. When the spec names the exception, a user who sees `{1: 0.0}` and `{1: -0.0}` compare equal but print differently finds the answer in the spec and does not file a bug.
> Concern: The spec does not yet say how Float renders `-0.0` or NaN. The wording must say "may render differently", and stay that way until wqv5yd settles the Float form.
>
> Q4: A
> Reasoning: One clause stops people from thinking that sorted debug output means `keys()` or `for` loops are sorted. That mistake would cause bugs that only show up under some seeds.
> Concern: None worth stating.
>
> Q5: A
> Reasoning: An example shows the text-order rule faster than prose does, and it stops contributors from "fixing" it to numeric order.
> Concern: None worth stating.
>
> Q6: A
> Reasoning: One shared paragraph means doc lookup (`blink llms --topic`) and readers find both rules together. It also stops the Set and Map rules from drifting apart in later edits. It fits a shared runtime helper too.
> Concern: The paragraph must still say plainly that the tie-break on value text applies only to Map, or readers will look for a "value" in Set.

**AI/ML:**

> **AI/ML ballot, Phase C (Map Debug order)**
>
> **Q1: A**
> Reasoning: One "render, sort by text, join" rule covers both Set and Map, so a model learns it once and can predict the exact `debug()` string for snapshot and `assert_eq` tests. It adds no bound and no syntax, so no new decision point at use sites. All six panelists rejected the other options (sorting whole entry strings, ordering by Ord), and I agree.
> Concern: Models will still guess numeric order (`{1: .., 2: .., 10: ..}`) unless the example sits right next to the rule.
>
> **Q2: A**
> Reasoning: Models often write a hand Eq (for example one that ignores case) and derive Debug. Option B's "derived Debug always obeys it" is wrong for that case, so a model would trust it and write broken code. Option A's wording matches what actually happens.
> Concern: If the sentence is too long or too formal, models skip it. It must stay one plain sentence plus a short example.
>
> **Q3: A**
> Reasoning: If the spec names Float as the one built-in exception, a model can find the answer in the spec instead of guessing. Option B would hide the `-0.0` sign in failure output, and that sign is often the bug. Changing Float output to rescue a container promise is the wrong trade.
> Concern: A model may over-apply the exception and treat all Float output as unstable. The text must say clearly that `-0.0` against `0.0` is the only case.
>
> **Q4: A**
> Reasoning: Without this clause, models will reason "Map Debug is sorted, so Map is sorted" and write `for k in m` expecting sorted keys. One clause blocks that. Keep the `scores.keys().sort()` idiom close by.
> Concern: A minor one: readers may not notice the clause if it is buried in the middle of the paragraph.
>
> **Q5: A**
> Reasoning: An example next to the rule is the cheapest fix for the most likely wrong guess. It costs about 20 tokens.
> Concern: If the example ends up in a separate block from the Set example, a reader who reads only one of them misses the shared rule.
>
> **Q6: A**
> Reasoning: One paragraph means one rule to retrieve and learn, and the Set and Map text cannot drift apart in later edits. A model reading about either container sees both.
> Concern: The shared paragraph may grow too dense, with the Set rule, the Map tie-break, the pointer to the law and two examples all together, so keep each part to one sentence.

**Minimalism:**

> **Minimalism — Phase C ballot**
>
> Q1: A
> Reasoning: Sorting by key text and then value text is the smallest rule that makes debug() depend only on the value. It needs no Ord bound and no conditional path, and one helper serves both Set and Map.
> Concern: Map could ship apart from the Set sort, leaving two copies of the helper that drift apart.
>
> Q2: A
> Reasoning: The law costs one sentence and no mechanism, the same kind of contract as Hash agreeing with Eq. B's wording ("derived Debug always obeys it") is false: a hand-written case-insensitive Eq with a derived Debug breaks it. A spec sentence that is false costs more than the three words needed to make it true.
> Concern: the sentence could grow into a lint or a list of examples. It must stay one sentence that the Map and Set text points back to.
>
> Q3: A
> Reasoning: Naming the case costs one clause and changes no behavior. B changes Float output to protect a Map promise, which is more surface and hides the sign, often the bug itself. C leaves the law claiming something Blink's own Float breaks, which would draw "bug" reports and a second deliberation later.
> Concern: the exception could become a catch-all ("built-in types may break the law"). It must name only -0.0 versus 0.0.
>
> Q4: A
> Reasoning: One clause stops readers from inferring that keys() is sorted. It also blocks a later request to make iteration match debug(), which would add hidden cost to hot paths.
> Concern: it may get written as a paragraph instead of a clause.
>
> Q5: A
> Reasoning: One example on the existing Set line blocks the "fix it to numeric order" mistake for both types at almost no cost.
> Concern: none worth noting.
>
> Q6: A
> Reasoning: One paragraph is less text and gives the rule one home, so Set and Map cannot drift apart in later edits. This is the same thinking as the shared runtime helper.
> Concern: the shared paragraph could get vague. It must still state the Map tie-break clause plainly.

### Final Spec

```blink
let mut m: Map[Int, Str] = Map()
m.insert(2, "b")
m.insert(10, "c")
m.insert(1, "a")
m.debug()   // => "{1: \"a\", 10: \"c\", 2: \"b\"}"

let mut s: Set[Int] = Set()
s.insert(2)
s.insert(10)
s.insert(1)
s.debug()   // => "{1, 10, 2}"
```

- `Map[K,V].debug()` sorts entries by the UTF-8 bytes of `key.debug()`; on equal key text, by the UTF-8 bytes of `value.debug()`. `Set[T].debug()` keeps its rule (sort element text). One shared paragraph, §3.6.1 *Container Debug Rendering*.
- Order is by text, not by value. No `Ord` bound.
- `keys()`, `values()` and `for` keep iteration order; only `debug()` sorts.
- New §3.6.1 law *Debug agrees with Eq*: for a type that is `Eq` and `Debug`, `a == b` must give `a.debug() == b.debug()`. Unchecked contract; derived `Debug` obeys it when `Eq` is also derived; a hand `impl` of either must keep them in agreement.
- `Float` is the one built-in exception: `-0.0 == 0.0` but they may render differently. Float output does not change. If the Float display form later renders `-0.0` as `0.0`, remove the exception.
- Panel concerns for the implementation: Set and Map share one sort helper (1-tuples for Set, 2-tuples for Map) and ship together; never sort on key text alone with a stable sort; a corpus test covers two keys that render the same text, and equal maps built by different insert and remove histories under two `BLINK_MAP_SEED` values. No sorted-iteration API. A lint for the law is a possible later friction item, not part of this decision.
