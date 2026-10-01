[< All Decisions](../DECISIONS.md)

# Assertion Bound: `Eq + Debug` — Design Rationale

**Gap:** §2.20 declared `assert_eq[T: Eq + Display]`, but only the scalar types have Display. Containers, Option and Result have Debug only, or no rendering at all. So the bound rejected the spec's own example `assert_eq(p.parse(""), Ok([]))`. The spec also named two codes for one failure: E0523 (03_types) and E0306 (02_syntax).

**Result:** 6-0 on all five questions. No Phase D (all votes were unanimous). AI-first review: 5/5 pass.

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in independent-proposal → debate → vote rounds.

#### Phase A — Independent proposals

All six put the same option first: a `Eq + Debug` bound, rendering with `debug()`, and conditional Debug for Result and tuples. Excerpts follow, verbatim.

- **Systems:**
  > What the hardware sees: `assert_eq` is one `==` call and a branch. Rendering runs only on the failure path. The renderer should be a cold, non-inlined function, monomorphized per `T`, that runs once before the panic. On the success path it costs nothing in either proposal below. So the question is which trait gives correct, deterministic output with no placeholders. Performance does not decide it.
  >
  > 1. The bounds become `assert_eq[T: Eq + Debug]` and `assert_ne[T: Eq + Debug]`. `assert_matches` gets the bound `T: Debug`.

- **Web/Scripting:**
  > The most common test any web dev writes is `assert_eq(result, Ok(...))`. If that line fails to compile, the test framework is broken for them. Python's `assert a == b` (pytest), Jest's `toEqual`, Kotlin's `assertEquals` and Rust's `assert_eq!` all print the structure of any value you can compare. Nobody expects to write a `toString` before they can write a test. The failure output also has to tell `"1"` from `1` and `"a "` from `"a"`, and that means quoted strings. Display can't do that; Debug can.

- **PLT:**
  > **Diagnosis.** The spec gives `assert_eq` a type with a Display bound, but the spec's own examples cannot satisfy that bound. This is a broken typing rule, not just loose wording. The bound has to say exactly what the failure path needs. The current compiler sidesteps the problem with `<TypeName>` stand-ins and `Some(..)`, which is the silent fallback the panel already banned. Whatever we pick, the bound must be checked and the output must never use a placeholder.
  >
  > **Consequence, stated openly so I do not hide it:** the spec's own example (`left: Err(InsufficientFunds {...})`) only type-checks if `Result[T,E]` is Debug. So P1 **revisits the 6-0 / 5-1 decision that "Set and Result are not Debug."** I add these conditional instances:

- **DevOps:**
  > One fact decides this for me. The spec's own sample output, `left:  Err(InsufficientFunds { deficit: 499 })`, is already in **Debug** form, the `@derive(Debug)` struct format. With a Display bound the left/right lines would show whatever a user's `fmt` prints. That is wrong for a failure log in two ways:
  >
  > This relitigates part of the 6-0/5-1 Container Debug vote. That vote's own text says the Set/Result/container-key exclusion comes from the renderer's key-ops storage layer, which is an implementation limit and not a design principle. Today a value can be Eq but have no Debug, so "Eq ⇒ you can see why it is not equal" fails. Assertions are where that hurts most.

- **AI/ML:**
  > 1. `assert_eq[T: Eq + Debug]` and `assert_ne[T: Eq + Debug]`. The failure output renders each side with `.debug()`. `assert_matches[T: Debug]` renders `value:` the same way. Power-assert sub-expression values use `debug()` too, so all assertion output uses one rendering.
  >
  > `Set[T]` becomes conditionally Debug. It renders as `{a, b}`. If `T: Ord`, elements print in sorted order. If not, they print in iteration order. Two equal sets then print the same text, and a diff is easy to read.

- **Minimalism:**
  > Diagnosis: the Display bound was a typo-level mistake. Display is the user-facing format. A test failure is a developer-facing dump, and Debug exists for that job. We should not grow Display to cover a job that Debug already does.
  >
  > 2. Diagnostics: a missing Eq gives E0306 (already decided: "same check as =="). A missing Debug gives E0520, the code that every other Debug sink uses, and it names the innermost type that has no Debug. Fix 03_types.md:2854 and 02_syntax.md:1430 so that each one names one code per trait. Do not add a new code for assertions.

Phase A.5 found three options (X, Y, Z) and five variations: the diagnostic code (V1), Set Debug and its order (V2), container map keys (V3), power-assert sub-expression rendering (V4), and the `.unwrap()` payload (V5). V4 and V5 were not voted. They go to separate tickets.

#### Phase B — Debate highlights

Round 1. Sys and PLT each proposed sorting Set elements by their debug strings (V2-s). The other four held iteration order plus a follow-up ticket.

- **Systems:**
  > New sub-option, V2-s: Set.debug() sorts the elements by their rendered debug strings and joins them. This needs no Ord bound, is deterministic under any seed, and costs O(n log n) string compares in debug(), which allocates anyway and is never a hot path.
- **PLT:**
  > Debug must respect Eq: a == b ⇒ debug(a) == debug(b). Otherwise assert_ne on two equal sets can print two different lines. It also breaks golden output, because the hash seed varies between runs. Iteration order violates this. aiml's "sorted if T: Ord, else iteration order" fixes it by the same specialization I reject in Z. NEW AMENDMENT: render Set elements sorted by their debug strings. This needs only the Debug bound the instance already has, is deterministic under any seed, respects Eq, and costs O(n log n) only on the cold path. Map has the same flaw today (entries in iteration order); I flag it as a follow-up ticket rather than reopen it here.
- **Web/Scripting:**
  > the per-process random seed means iteration order changes between CI runs. That is noise, not a wrong verdict, because equal sets never fail assert_eq. "Sorted iff T: Ord" fixes it, but it makes the format depend on which traits are present. It also leaves Map, which has the same problem today, unsorted, so Set and Map would disagree. My vote: iteration order, the same as Map, and file a separate ticket to sort Map and Set debug output together (or have blink test pin the seed). Don't fix half of it here.
- **AI/ML:**
  > V2 (Set): Set is conditionally Debug, as `{a, b}`. I withdraw "sorted if T: Ord". It is specialization on an optional trait, the same thing I reject in Z. Seed randomization makes iteration order differ between runs, but Map already has this, `--deterministic` pins it, and equal sets never fail assert_eq. File a follow-up for Map and Set together; do not fix it here.

Round 2 was on Set order only. Web, DevOps, AI/ML and Minimalism changed to V2-s. Sys changed its fallback.

- **Web/Scripting:**
  > Set order: V2-s, elements sorted by their debug strings. Plt's property settles it for me: if a == b, then debug(a) must equal debug(b). Without that, assert_ne on equal sets can print two different-looking lines, and that is a sure Stack Overflow question.
- **Minimalism:**
  > I switch to V2-s: sort the elements by their debug strings. My round 1 point that iteration order is the "honest" order was wrong. With a random seed per process, debug() would stop being a function of the value, and plt's rule (a == b ⇒ debug(a) == debug(b)) is the smallest correct rule.
- **DevOps:**
  > DevOps round 2 (Set order): I switch to V2-s, Set elements sorted by their debug strings. Stable, ready to vote.
- **AI/ML:**
  > I change to V2-s: Set.debug() sorts the elements by their debug strings. It solves the problem I tried to solve with "sort if T: Ord", but needs no extra bound and does not specialize on that bound. For my domain the deciding point is reproducibility. An AI that runs a failing test twice, or compares a CI log with a local run, must see the same text. Otherwise it chases a difference that does not exist. PLT's rule, a == b ⇒ debug(a) == debug(b), is the correct invariant, and it is easy to state in the spec.
- **Systems:**
  > I am changing my fallback. If V2-s loses, I accept iteration order plus one follow-up ticket for Map and Set together. I no longer ask to keep Set out.
- **PLT:**
  > Pinning the seed in `blink test` (devops) is a good runner fix, but it does not give a == b ⇒ debug(a) == debug(b). Two equal sets with different insertion or deletion histories can iterate in different orders under the same seed (collision chains, tombstones, resize timing). Only a canonical order gives that property. Sorting by the debug string needs no extra bound, so it is not the specialization we all rejected.

#### Phase C — Final vote

- **Q1: Bound and rendering for assert_eq / assert_ne / assert_matches.** (6-0 for X)
  - *Option* X: assert_eq[T: Eq + Debug], assert_ne[T: Eq + Debug]; failure output renders with debug(). assert_matches[T: Debug]. No placeholder. Result[T, E] gets conditional Debug (Ok(..)/Err(..)); tuples get auto-derived conditional Debug, format (a, b).
  - *Option* Y: X's bounds, but Result (and Set) stay non-Debug; spec examples rewritten.
  - *Option* Z: bound T: Eq only; render with debug() when T is Debug, else an explicit "values not shown" line.
  - **Systems:** X. — A passing assert costs one == and a branch. Rendering lives in a cold, per-T monomorphized walker that the descriptor emitter already builds. Result is a tag switch and a tuple is a fixed field walk, so neither needs new runtime machinery. Z puts a trait-presence branch inside a built-in, a specialization users cannot write, and turns a compile-time error into a gap that shows only in CI logs. *Concern:* the Result and tuple walkers must go into the shared descriptor emitter that struct fields and enum-variant fields already use. If they are written as an assertion-only renderer instead, the two renderings can drift apart.
  - **Web/Scripting:** X. — assert_eq(f(), Ok(x)) is the most common test line in any language with Result. X lets it compile as the spec writes it and prints values with quoted strings, the way pytest, Jest and Rust users expect. The fix for a type that fails is one word, @derive(Debug), and the error names where it goes. *Concern:* users with Eq-only types will hit E0306 on their first test, so the help text and LSP quick fix must be in place on day one, or the bound will feel like friction rather than help.
  - **PLT:** X. — The bound must state exactly what the body uses. The failure path renders values, so the bound must require Debug. Display is the wrong trait because it does not separate unequal values: unquoted strings can print the same for different values. Result and tuple Debug make the Debug instances inductive over the core algebraic types, matching the Eq instances, so a type that can be compared can also be shown. Z is a type-case on an optional trait, which breaks parametricity. *Concern:* The spec edit must record this as an explicit extension of the Container Debug decision, or the two sections will contradict each other again.
  - **DevOps:** X — the spec's own failure output (`Err(InsufficientFunds { deficit: 499 })`) is already in Debug form, and Debug quotes strings, so a CI log shows `"a "` vs `"a"` and `"1"` vs `1`. The error comes at compile time on the call span, with a fix-it the user can apply, and not as a run-time log with no values (Z). Under Y, `assert_eq(f(), Ok(x))` is an error the user cannot fix with a derive. *Concern:* users with Eq-only types will hit a new compile error across existing tests, so the fix-it text and its span must point at the type's declaration, or the migration will be noisy.
  - **AI/ML:** X. — The spec's own examples (`Ok([])`, `Err(InsufficientFunds { deficit: 499 })`) then compile as written, so a model that learns from the spec alone writes legal tests. The rule is "a type you assert on derives Eq, Debug". That is one decision point, and it matches Rust's `assert_eq!`, which is common in training data. Debug quotes Str, so failure output shows the differences an AI needs to correct itself. *Concern:* Users who meet only Eq types in examples may forget Debug, so the E0306 fix-it text must be exact.
  - **Minimalism:** X — The fix is a one-word change to the bound. It removes an exception (Result/tuple not Debug) that had no stated reason, and it adds no new traits, formats or rules. Then the Eq set and the Debug set cover the same core types, so the spec's own examples compile as written. Y keeps a gap for no reason, and Z adds a dispatch rule that only assertions use. *Concern:* users with Eq-only types must add @derive(Debug), and some will read this as friction until the fix-it makes it one edit.

- **Q2: Code for a missing Debug at an assert call.** (6-0 for A)
  - *Option* A: E0306 TraitBoundNotSatisfied. One diagnostic lists both traits when Eq and Debug are both missing, and names the innermost type without Debug. E0523 is scoped to Display bounds and sinks (fix 02_syntax.md:1430 and 03_types.md:2854 together).
  - *Option* B: E0520.
  - **Systems:** A. — At an assert call, a missing Debug fails the same generic bound check as a missing Eq, so both should get one code. E0520 reports a failed derive at a field, which is a different check in a different place. Reuse E0520's peel logic to find the innermost type, not its code. *Concern:* if the 02_syntax.md:1430 and 03_types.md:2854 edits do not land in the same commit, the spec will name two codes for one failure again.
  - **Web/Scripting:** A. — a user who never wrote a derive should not get a "DeriveDebugFieldNoDebug" code at an assert call. Searching for that error leads them the wrong way. One code for "this call's bound failed", whichever half fails, is the rule a user can learn in one line. *Concern:* if the 02_syntax and 03_types edits do not land together, docs and compiler will disagree on the code again, which is how this ticket started.
  - **PLT:** A. — A diagnostic code should name the judgment that failed. A bound check at a call site is E0306's judgment, and E0520 belongs to the derive judgment. Listing every missing trait in one diagnostic, and naming the innermost type without Debug, gives a complete account of the failed constraint. *Concern:* If the innermost-type note reuses the E0520 peel logic by copying it, the two paths can drift; it should be one shared function.
  - **DevOps:** A — E0306 classifies the event that fails, a call-site bound check, and that is the same code the Eq half already uses, so one assert call gets one code. E0520's title and `blink explain` page describe a derive site, and at an assert call there is no derive. Listing both traits in one diagnostic keeps CI logs and LSP problem panels from stacking two errors on one span. *Concern:* the "innermost type" peel must reuse E0520's walker exactly. A second copy will drift, and the two codes will then name different types for the same shape.
  - **AI/ML:** A. — One call gets one code, whichever half of the bound fails. E0306 already means "this call's type parameter does not meet its bound", so an AI reads the correct cause. E0520 names a derive-site judgment and would send the reader to look at fields. Naming the innermost type without Debug makes the fix one mechanical edit. *Concern:* If the "innermost type" peel is wrong for nested containers, the fix-it points at the wrong type and the AI loops.
  - **Minimalism:** A — One call-site bound check gets one code, whichever trait fails. That is fewer codes than splitting Eq and Debug across E0306/E0520. E0520 stays a derive-site code, and E0523 stays at Display sinks, so each code means one judgment. *Concern:* if the two spec files are not fixed in the same commit, the E0523/E0306 conflict comes back.

- **Q3: Set and Debug.** (6-0 for A)
  - *Option* A: Set[T] gets conditional Debug, format {a, b}, empty {}.
  - *Option* B: Set[T] gets conditional Debug, format Set{a, b}.
  - *Option* C: Set stays non-Debug.
  - **Systems:** A. — Set already reuses the Map key-ops walker, so this is a small amount of code. Neither the record nor the spec gives a reason for leaving it out. The type is static at every assert and derive site, so an empty {} that looks like an empty Map cannot mislead anyone. *Concern:* in an ad-hoc log line that mixes types, {} could be read as either an empty Map or an empty Set.
  - **Web/Scripting:** A. — {a, b} is set syntax every Python and JS dev already reads. The clash with an empty Map {} cannot mislead in an assert, because both sides share one static type. *Concern:* in a @derive(Debug) struct with both a Set and a Map field that are empty, a reader of the raw text sees {} twice and must check the type to know which is which.
  - **PLT:** A. — Set is Eq, so leaving it non-Debug keeps a gap between the Eq and Debug instance sets with no type-level reason. `{a, b}` follows Map's braces and adds no one-off type prefix. The empty `{}` is the same as an empty Map, which is harmless because Debug output is not a parse form and both sides of an assert share one T. *Concern:* Readers of a nested derive dump may confuse an empty Set field with an empty Map field. The field's static type settles it, but only if they look it up.
  - **DevOps:** A — Set is Eq, so excluding it breaks `assert_eq(set_a, set_b)` with no fix the user can make. `{a, b}` reads with no learning, and both sides of an assert share one T, so the empty `{}` collision with Map causes no confusion in assert output. *Concern:* in a struct's derived Debug, an empty Set field and an empty Map field both print `{}`, which can mislead a reader of a log line.
  - **AI/ML:** A. — Set is Eq, so it must be Debug, or Option X leaves the same gap open for Set. `{a, b}` matches the Map and List style and costs no extra tokens. The type is the same on both sides of an assert, so an empty `{}` is never ambiguous there. *Concern:* In mixed logs out of context, an empty Set and an empty Map print the same text.
  - **Minimalism:** A — Set is Eq, so leaving it out makes an Eq type that cannot be asserted for no reason. `{a, b}` reuses Map's braces and adds no token. A `Set{` prefix on one container alone is a one-off. The empty `{}` matches empty Map, which is harmless because both sides of an assert share one T. *Concern:* a reader who sees `{}` in a log with no type context cannot tell an empty Set from an empty Map.

- **Q4: Element order in Set's Debug output (applies if Set gets Debug).** (6-0 for A (V2-s))
  - *Option* A (V2-s): elements sorted by their debug strings; follow-up ticket gives Map entries the same rule (sort by key debug text).
  - *Option* B: iteration order; follow-up ticket for Map and Set order (canonical sort or test-runner seed pin).
  - **Systems:** A. — Each process gets a random hash seed, and two equal sets can hold their elements in different orders after different insert, delete and resize steps. So iteration order breaks the rule a == b ⇒ debug(a) == debug(b), even inside one process. Sorting by the debug strings needs no Ord bound, gives the same text under any seed, and costs O(n log n) string compares only on the cold path. *Concern:* if B wins and the follow-up ticket stalls, golden-output and NDJSON rerun comparisons stay flaky for Set and Map.
  - **Web/Scripting:** A. — equal values must print the same text, or assert_ne on equal sets and golden-output tests give confusing, flaky output. Sorting by debug string gives that with no extra trait bound, so the output does not depend on which traits a type has. Numbers sorting as text ({1, 10, 2}) looks odd but never misleads. *Concern:* the Map follow-up may stall, which would leave Set sorted and Map in random order, an inconsistency users will notice and ask about.
  - **PLT:** A (V2-s). — Debug should respect Eq: a == b ⇒ debug(a) == debug(b). Iteration order breaks that rule. Two equal sets can iterate in different orders even under the same seed, because of insertion and deletion history. Sorting by the debug string gives a canonical form with no extra bound, so it is not specialization. The cost is O(n log n), only on the cold failure path. *Concern:* If B wins, the follow-up ticket must aim for a canonical order, not only a pinned seed in the test runner, or the Eq property stays broken.
  - **DevOps:** A — sorting by debug text makes failure output the same under any hash seed, so golden tests, NDJSON `expected`/`actual` and `--rerun-failed` comparisons stay stable. It needs no Ord bound, so the rule is one line in hover docs and does not depend on which traits a type has. *Concern:* until the Map follow-up lands, Set is canonical and Map is not, so Map output in CI logs stays unstable and users will ask why the two disagree.
  - **AI/ML:** A (V2-s). — Output must be the same on every run. An AI that compares a CI log with a local run must not chase a hash-seed difference. Sorting by debug string needs no extra bound and keeps a == b ⇒ debug(a) == debug(b), which is easy to state in the spec. *Concern:* Sorting by string puts 10 before 9, which can look odd, and the spec must state it so nobody "fixes" it to numeric order.
  - **Minimalism:** A — Sorting by the debug text makes debug() a function of the value (a == b ⇒ same text) under any seed. It needs no Ord bound and no conditional path, and the spec needs one sentence for it. Iteration order makes failure text and goldens flaky, which costs more over time than the sort costs once. *Concern:* until the Map follow-up lands, Set and Map use different order rules, and that drift must not become permanent.

- **Q5: Map keys that are containers.** (6-0 for A)
  - *Option* A: the ban stays (lifting it is separate work).
  - *Option* B: lift the ban; container-keyed Map gets conditional Debug.
  - **Systems:** A. — Lifting the ban needs a new key-ops descriptor in the storage layer, which is real codegen work for a shape that is rare in tests. E0306 names the key type, so nothing is hidden from the user. *Concern:* a user with a container-keyed Map who wants to assert on it gets an error that Map does not explain, and must change the key to a struct that derives Debug.
  - **Web/Scripting:** A. — container map keys are rare in test code, and the ban has a real storage reason. E0306 will name the key type clearly. Lifting it belongs on its own ticket. *Concern:* a user who does hit it gets a "not Debug" error for a Map whose key and value types are each Debug on their own, which will read as a compiler bug unless the note explains the key rule.
  - **PLT:** A. — The ban has a stated storage reason, and assert_eq does not need it lifted. The E0306 diagnostic names the key type, so the gap stays visible and does not hide behind a fallback. *Concern:* A Map that is Eq but cannot be shown stays a hole in the "comparable ⇒ showable" property until someone builds the key-ops descriptor.
  - **DevOps:** A — the ban has a real storage reason, the shape is rare in test code, and E0306 names the key type, so nothing hides from the user. Lifting it is codegen work that this gap does not need. *Concern:* a container-keyed Map is Eq but not Debug, so assert_eq on it is the one remaining "you can compare it but not assert it" case, and the diagnostic must say why and not just "add @derive(Debug)".
  - **AI/ML:** A. — The ban has a stated storage reason, and assert_eq does not need it lifted. Container map keys are rare in tests, and E0306 names the type, so the error lets an AI correct itself. *Concern:* An assert on a container-keyed Map fails to compile, and users may read that as a defect in assert_eq, not as a Map Debug limit.
  - **Minimalism:** A — YAGNI. Container-keyed maps are rare, and the ban has a real storage-layer reason. E0306 names the key type honestly, so nothing hides. Lift it when a user asks. *Concern:* a user who meets this ban in a test will find the gap between Eq and Debug for Map surprising.

#### Phase D

Not triggered. Every question passed 6-0.

### Final Spec

```blink
fn assert_eq[T: Eq + Debug](left: T, right: T, msg: Str = "")
fn assert_ne[T: Eq + Debug](left: T, right: T, msg: Str = "")
fn assert_matches[T: Debug](expr: T, pattern)   // signature shorthand, as in §2.20

@derive(Eq, Debug)
type InsufficientFunds { deficit: Int }

test "withdraw" {
    let result = account.withdraw(999)
    assert_eq(result, Ok(500))
    // assertion failed: assert_eq(result, Ok(500))
    //   left:  Err(InsufficientFunds { deficit: 499 })
    //   right: Ok(500)
}
```

- The failure output renders each value with `debug()`. There is no placeholder. A `T` with no Debug does not compile.
- A missing Debug at an assert call is `E0306 TraitBoundNotSatisfied`, the same code as a missing Eq. If both are missing, one diagnostic names both traits. A note names the innermost type with no Debug, found by the same peel logic as E0520. `E0523` stays for Display sinks and Display bounds only.
- This extends the Container Debug decision. `Result[T, E]` is Debug when `T` and `E` are (`Ok(..)` / `Err(..)`). Tuples are Debug when every element is (`(a, b)`). `Set[T]` is Debug when `T` is (`{a, b}`; empty `{}`).
- Set elements print sorted by the UTF-8 bytes of their debug strings, not in iteration order. (Moderator clarification: the vote said "sorted by their debug strings"; "UTF-8 bytes" fixes the compare.) So `a == b` implies `a.debug() == b.debug()` under any hash seed. No Ord bound is needed. `{1, 10, 2}` is the intended output.
- The ban on container map keys stays (no key-ops descriptor). Container set elements stay out for the same reason. (Moderator extension of Q5; not voted.)
- Follow-up tickets: Map entries sorted by key debug text; power-assert sub-expression rendering; `.unwrap()` payload rendering follows Debug.
- Spec: §2.20 *Built-in Assertions* (02_syntax.md), §3.6.1 *Debug vs Display* and *Container Debug Rendering* (03_types.md), §3.8 tuple auto-derived traits, §10.6 *Test Builtins* (07_trust_modules_metadata.md).
