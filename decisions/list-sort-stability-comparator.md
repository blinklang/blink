[< All Decisions](../DECISIONS.md)

# List Sort Stability and Comparator — Design Rationale

The spec gap: the voted List surface (DECISIONS.md, 12 methods, 3-2) includes `sort`, and the spec declared `fn sort(self) -> List[T]` with the row "Sorted copy (requires `T: Ord`)". The spec did not say whether the sort is stable. It had no comparator form, so a `List` of structs could be sorted only one way per type, through its `Ord` impl. And the spec and two decision records called `.sorted()`, a method that is defined nowhere.

### Grounding facts (verified in-tree before deliberation)

- `ListOps[T]` is a sealed built-in surface (03c §740). Blink has no inherent methods, so users cannot add a sort method to `List`.
- `trait Ord: Eq { fn cmp(self, other: Self) -> Ordering }`; `Ordering` is `Less | Equal | Greater`. `Float` has a total order and `NaN` sorts last. No Ord-laws paragraph existed; the Eq-laws paragraph was the precedent.
- `Iterator[T]`'s sealed adapter list has no `sort`, so `pairs.into_iter().sort().collect()` (03_types.md) did not type-check.
- `.sorted()` appeared in the W1401 `MapOrderAssumption` fix text (06_tooling.md), DECISIONS.md and decisions/hash-seed-iteration-order.md. `Map.keys()` returns `List[K]`, so `.sort()` is type-correct at every site.
- 03_types.md and the hash-seed record wrote `names.sort()` as a statement on a `let mut names`. Since `sort` returns a copy, that line discarded the sorted list.
- W0603 has two names today: `UnusedResult` (DECISIONS.md, fs decision) and `ShadowedVariable` (03_types.md, src/diagnostics.bl).
- The compiler's generic "did you mean" hint (`tc_suggest_method`, src/typecheck.bl) does not reach `sorted` → `sort`: the threshold is `len / 3` = 2, and the distance 2 must be below it. A table of cross-language List spellings with a note on meaning (`tc_list_rename_help`) already exists, with rows for `concat` and `collect`.

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated
in independent-proposal → debate → vote rounds. Each section below quotes the panelist's own text in full. (The AI/ML Phase A file notes that the panelist lightly copyedited it before submission.)

#### Phase A — Independent proposals

##### Systems

> # Systems panelist: Phase A proposals (yv1sj1)
>
> ## Proposal S1: `sort` is stable, and the spec says so
>
> The spec should state: `sort` returns a stable sorted copy. Elements that compare `Equal` keep their input order. The receiver is not changed.
>
> ```blink
> type Rec { name: Str  dept: Int }
>
> let by_name = recs.sort_by(fn(a, b) { a.name.cmp(b.name) })
> let by_dept = by_name.sort_by(fn(a, b) { a.dept.cmp(b.dept) })
> // by_dept is grouped by dept, and each group stays sorted by name. This needs stability.
> ```
>
> **What it compiles to.** A merge sort, ideally a run-adaptive one (TimSort or driftsort), monomorphized for each `T`. The copy semantics already pay for one n-element allocation. A stable merge needs one more n-element scratch buffer. The sort can switch between the two buffers on each pass, return whichever one holds the result, and leave the other to the GC. So stability costs one extra n-sized allocation over an unstable pdqsort. The cost in comparisons is about the same: n log n worst case, and close to O(n) on input that is already sorted or nearly sorted. That is a small price next to the copy we already make. An unstable sort saves a little allocation but leaves a correctness hole that users will find.
>
> **Do not add `sort_unstable` now (YAGNI).** We can add it later to the sealed surface without breaking anything, which is the same reasoning as the set-algebra precedent. There is no measured need yet.
>
> **Ord-law rider (same change).** Add a paragraph shaped like the Eq-laws one: "If a user `Ord` impl or a comparator breaks the total-order laws, `sort` returns an unspecified permutation of the input. It stays memory-safe and does not panic." This has a real cost for the implementer, so the spec must state it. The guarded/unguarded insertion-sort bug class (out-of-bounds reads when the comparator lies) is exactly what this rules out. Rust 1.81 chose "may panic". I reject that, because a panic makes the sort's control flow depend on bugs in user code.
>
> Cross-language: Rust `sort` and Python `sorted` are stable. Java uses stable TimSort for objects. Go's `sort.Slice` is not stable and needs a separate `SliceStable`, which is a known footgun. C `qsort` makes no guarantee.
>
> ## Proposal S2: add exactly one comparator form, `sort_by`, returning `Ordering`
>
> ```blink
> fn sort_by(self, cmp: fn(T, T) -> Ordering ! _) -> List[T] ! _
>
> let newest = posts.sort_by(fn(a, b) { b.ts.cmp(a.ts) })     // descending
> let ranked = scores.sort_by(fn(a, b) { a.cmp(b) })           // same as .sort()
> ```
>
> - **Return `Ordering`, not `Int`.** An `Int` comparator invites C-style `a - b`, which overflows silently. `Ordering` is a three-variant enum that lowers to a small int, so it costs nothing extra and stays exhaustive.
> - **Codegen.** `sort()` with `T: Ord` monomorphizes to a direct comparison, which inlines for primitives. That is the fast path. `sort_by` costs one indirect call (fn pointer + env) per comparison, the same as `qsort`. When the closure is a literal at the call site, mono could specialize on it later. That is an optimization and needs no spec change. Users can see the cost from the signature.
> - **The `! _` effect row** matches `map`. Copy semantics make an effectful comparator safe: if a handler aborts partway through, the receiver is unchanged and the half-built buffer is garbage. In-place sorts cannot say that.
> - **No `sort_by_key` (defer).** It hides a cost choice: either recompute the key 2·n·log n times, or cache it, which means an allocation plus a decorate-sort-undecorate pass. `sort_by(fn(a, b) { a.age.cmp(b.age) })` covers it with the cost visible. We can add it later without breaking anything.
> - **Why not stay Ord-only?** A user who needs a second ordering must wrap the data in a newtype that carries its own `Ord` impl. That is more code, and it is not obviously free. Users cannot extend the sealed `ListOps`, so leaving the comparator out is not a minimal choice. It is a hole only the language can fill. I voted for 8 methods in the original vote, but this one earns its place.
>
> Cross-language: Rust `sort_by(|a, b| -> Ordering)`, Zig `std.sort.block(T, items, ctx, lessThan)` (stable), Go `slices.SortStableFunc(cmp func(a, b) int)`.
>
> ## Proposal S3: `.sorted()` is a misspelling. Fix the docs and add no alias
>
> `sort` already returns a copy. `.sorted()` would be a second name for the same thing on a sealed surface, so it would be pure surface area. Make these edits:
>
> - In DECISIONS.md:343, decisions/hash-seed-iteration-order.md, and 06_tooling.md:1434/1444, change `.sorted()` to `.sort()`. This includes the W1401 machine-applicable fix text: `assert_eq(m.keys().sort(), ["a", "b"])`.
> - In 03_types.md:4208, change `pairs.into_iter().sort().collect()` to `pairs.sort()`. `Iterator` has no `sort`, and a lazy sort has to buffer everything anyway, so it does not belong among the lazy adapters.
> - In 03_types.md:2207 and hash-seed:104-106, change the statement `names.sort()` to `let names = names.sort()` (or reassign it).
>
> **Rider:** a bare `names.sort()` statement throws away an n-element allocation and, for Python/Rust/JS habits, silently does nothing. Extend the `UnusedResult` lint family (the precedent is W0603) to discarded results of copy-returning `ListOps` transforms (`sort`, `sort_by`, `reverse`, `append`, `slice`). The opt-out is `let _ =`.
>
> ## Systems vote intent
>
> S1 (stable + Ord-law rider): yes. S2 (`sort_by` with `Ordering`, no `sort_by_key`): yes. S3 (doc fix, no alias, discard lint): yes.

##### Web/Scripting

> ## Web/Scripting proposals for yv1sj1 (`sort`)
>
> My test: a Python or JS dev types `xs.sort()` with no docs open. What happens? Today they get a sorted copy they never asked for, and the spec's own `names.sort()` example (03_types.md:2207) shows that exact bug. Fix the trap, keep the surface small, and make the common case work.
>
> ### Proposal W1: `sort` is stable, and the spec says so (Q1)
>
> Normative text: "`sort` is stable. Elements that compare `Equal` keep their input order." There is no `sort_unstable` in v1.
>
> ```blink
> let by_name = people.sort_by_key(fn(p) { p.name })
> let ranked = by_name.sort_by_key(fn(p) { p.dept })   // depts grouped, names still in order
> ```
>
> - **Tradeoff:** stable merge sort (Timsort-style) needs O(n) scratch space. But `sort` already returns a copy, so that buffer costs almost nothing extra. An unstable sort saves nothing worth having.
> - **Cross-language:** Python's `sorted` is stable. JS `Array.prototype.sort` became stable in ES2019 because unstable sorts produced real bugs. Java's object sort and Kotlin's `sortedBy` are stable. Go is the outlier, and it had to add `sort.SliceStable`. Scripting devs expect stable, and when it's missing their bugs show up only some of the time.
>
> ### Proposal W2: add `sort_by_key`, and `sort_by` with an `Ordering` comparator (Q2)
>
> ```blink
> trait ListOps[T] {
>     fn sort(self) -> List[T]                                      // T: Ord
>     fn sort_by_key[K](self, key: fn(T) -> K ! _) -> List[T] ! _   // K: Ord
>     fn sort_by(self, cmp: fn(T, T) -> Ordering ! _) -> List[T] ! _
> }
>
> let newest = posts.sort_by_key(fn(p) { p.created_at }).reverse()
> let custom = users.sort_by(fn(a, b) {
>     match a.role.cmp(b.role) {
>         Equal => a.name.cmp(b.name)
>         other => other
>     }
> })
> ```
>
> - **The comparator returns `Ordering`, not `Int`.** `fn(a, b) -> Int` brings the JS `a - b` habit with it: overflow on large Ints, and "is negative less?" confusion. `Ordering` matches `Ord.cmp`, and `match` checks it for exhaustiveness. It also teaches users one concept, not two.
> - **`sort_by_key` covers the common case.** Most real sorts are "sort records by one field." Python's `key=` and Kotlin's `sortedBy` show that people reach for the key form far more than for comparators. `sort_by` handles the rest: multi-key sorts, descending order, custom rules.
> - **Why not stay Ord-only:** Ord-only forces a newcomer to write an `Ord` impl on `User` just to sort a table by email. Then sorting by name somewhere else becomes impossible. That gap generates Stack Overflow questions. Users also cannot add these methods themselves, because ListOps is sealed (fact 9). So "add it later via an extension trait", which the set-algebra precedent relied on, does not work here. If we leave it out, it stays out until a spec change.
> - **Effects:** both use `! _`, same as `map`. Sorting with a comparator that logs just works.
> - **Ord laws:** add one sentence that copies the Eq precedent: "If an `Ord` impl or comparator is not a total order, `sort` returns an unspecified permutation of the input. It stays memory-safe and does not panic." That matches Rust and avoids JS's "implementation-defined" mess.
>
> ### Proposal W3: no `.sorted()`, and fix every doc site. Add a warning for a discarded copy (Q3)
>
> `.sorted()` is a misspelling of `.sort()`, so the fix is a doc edit. Do not add an alias: two names for one operation makes every newcomer ask "which one?" Fix all sites:
> - 06_tooling.md:1434 and 1444: `m.keys().sort()`. The W1401 fix text must name a method that exists.
> - DECISIONS.md:343 and decisions/hash-seed-iteration-order.md: same edit, with a note that it is an erratum.
> - 03_types.md:4208: `pairs.sort()`. `Iterator` has no `sort`, and the two-worlds rule puts it on the collection.
> - 03_types.md:2207: `let names = scores.keys().sort()`.
>
> **The real DX problem is the 2207 example.** Python's `list.sort()` mutates in place. JS's mutates and also returns the array. Blink's returns a copy. So `names.sort()` as a statement is a silent no-op for every Python and JS migrant, and our own spec author made that mistake. I propose a default-on warning, **W-DiscardedCopy**: the result of a non-mutating ListOps transformation (`sort`, `sort_by`, `sort_by_key`, `reverse`, `append`, `slice`) is discarded in statement position. It comes with a machine-applicable fix: `names = names.sort()`. It costs one lint and saves the most common migration bug.
>
> ```blink
> let mut names = scores.keys()
> names.sort()            // warning: `sort` returns a sorted copy; result discarded
> names = names.sort()    // ok
> ```
>
> ### Summary vote position
> - Q1 stable: **yes, required**
> - Q2: **`sort_by_key` + `sort_by` (→ `Ordering`)**, not an `Int` comparator, and not Ord-only
> - Q3: **`.sorted()` is a misspelling. Fix all six sites, add no alias, and add the discarded-copy warning**

##### PLT

> # PLT panelist: Phase A proposals for yv1sj1
>
> ## Proposal 1 (primary): stable `sort`, an `Ordering` comparator, Ord laws, doc fixes
>
> **1a. Stability is normative.** `sort` and `sort_by` are stable. When two elements compare `Equal`, the result keeps their input order.
>
> The PLT reason is purity, not convenience. Blink has no identity. But a user `Eq` can be coarser than structural equality: two records can be `==` under a key-only impl and still differ in other fields. An unstable sort then turns `xs.sort()` into a *relation*, where one input has many allowed outputs. That makes `sort` non-deterministic for the same value. The spec already makes purity analysis exclude Map iteration for the same reason (03_types.md, hash-seed section), and we should not add a second hole of that kind. A stable sort is the only *function* the spec can name: the unique stable permutation that orders the list by `cmp`. Stability also makes multi-key sorting compose: `xs.sort_by(k2).sort_by(k1)` is lexicographic `(k1, k2)`, which is an equational law users can rely on. YAGNI on `sort_unstable`. We can add it later by trait extension without a breaking change (the set-algebra precedent).
>
> **1b. Comparator form.** Add one method to `ListOps[T]`:
>
> ```blink
> fn sort_by(self, cmp: fn(T, T) -> Ordering ! _) -> List[T] ! _
> ```
>
> - It returns `Ordering`, **not `Int`**. An `Int` comparator is a three-valued type encoded in a 2^64-valued one, with a sign convention the type system cannot check. Blink already has a closed `Ordering` sum for exactly this job, so we should use it (Haskell `sortBy`, OCaml `List.sort` uses int and is the cautionary tale, Rust `sort_by`).
> - It is effect-polymorphic, so `! _` propagates the comparator's effects (04_effects.md:2269 pattern).
> - It needs no `T: Ord` bound. This is the real gap in the Ord-only design: `Ord` is coherent, so you get one order per type per program. A comparator is how a second order exists without newtype wrappers.
>
> ```blink
> type Emp { name: Str, dept: Str, age: Int }
>
> let by_age = staff.sort_by(fn(a, b) { a.age.cmp(b.age) })
> let by_dept_then_name = staff
>     .sort_by(fn(a, b) { a.name.cmp(b.name) })
>     .sort_by(fn(a, b) { a.dept.cmp(b.dept) })   // correct only because sort is stable
> let desc = staff.sort_by(fn(a, b) { b.age.cmp(a.age) })
> ```
>
> `sort` is then definitionally `sort_by(fn(a, b) { a.cmp(b) })`, so the spec gets one semantic definition instead of two.
>
> I do **not** propose `sort_by_key` now. It can be derived from `sort_by` in one line, and it is lossy for descending order without a `Reverse[K]` wrapper. It is not minimal.
>
> **1c. Ord laws paragraph**, mirroring the Eq-laws paragraph at 03_types.md:2730:
>
> - `cmp` must be a total order consistent with `Eq`: `a.cmp(b) == Equal` iff `a == b`.
> - Antisymmetric: `a.cmp(b)` is the reverse of `b.cmp(a)`.
> - Transitive.
> - A `sort_by` comparator must be a total *preorder* (consistency with `Eq` is not required there).
> - If a law is broken, the result is an **unspecified permutation of the input**: every element appears exactly once, the call terminates, and it stays memory-safe. This must be normative, because the C implementation must not index out of bounds on an inconsistent comparator (this is a real bug class in glibc `qsort`).
>
> **1d. Effect semantics of the comparator.** The *number and order* of comparator calls are unspecified. This matters only when the comparator has a non-empty effect row. Saying it is what keeps the implementation free to choose merge sort or Timsort. If the comparator raises or a handler aborts, the receiver is unchanged. This follows directly from copy semantics, so it costs nothing to state.
>
> **1e. Doc defects, as an edit with no vote** (`.sorted()` is not in the voted 12, and nothing supports a second spelling):
>
> - Replace every `.sorted()` with `.sort()`: 06_tooling.md:1434 and :1444 (the W1401 fix text), DECISIONS.md:343, and decisions/hash-seed-iteration-order.md. `m.keys().sort()` is type-correct as is.
> - 03_types.md:2207 and decisions/hash-seed:104: `let mut names = scores.keys(); names.sort()` discards its result. Rewrite it as `for name in scores.keys().sort() { ... }`. This is a latent spec bug, not a style issue.
> - 03_types.md:4208: `into_iter().sort().collect()` is ill-typed (no `Iterator.sort`, and sort is inherently non-lazy). Rewrite it as `pairs.sort()`.
>
> ## Proposal 2 (follow-up, separate ticket): warn on a discarded pure result
>
> The `names.sort()` defect shows the hazard: a `List[T]`-returning non-mutator whose result is discarded is almost surely a bug. This calls for a must-use lint on discarded results of the transformation methods (`sort`, `sort_by`, `reverse`, `append`, `slice`). It is a tooling question, so I name it here but do not bundle it into this vote.
>
> ## Tradeoffs and what I reject
>
> - **Ord-only (my side's 3-2 position)**: it is sound but incomplete. Without inherent methods or newtype-deriving ergonomics, a second ordering means a wrapper type per ordering. One method with a precise type closes that gap at almost no cost to surface size.
> - **Unspecified stability**: I reject it. It is unsound with respect to the purity classification, and Go's `sort.Slice` is the cautionary example.
> - **An `Int` comparator**: I reject it, as covered in 1b.
> - **`Ordering` combinators (`reverse`, `then`)**: I defer them. They are nice, but stability plus composition of `sort_by` already gives multi-key and descending order.
>
> **Vote intent:** 1a + 1b + 1c + 1d + 1e as one package. Proposal 2 goes to a separate ticket.

##### DevOps/Tooling

> # DevOps/Tooling — Phase A proposals (yv1sj1)
>
> ## Proposal 1: `sort` is stable and deterministic; specify what a bad `Ord` impl does
>
> Spec text (03_types.md): "`sort` is stable. Elements that compare `Equal` keep their input order. The result depends only on the input and the comparisons." Add an Ord-laws paragraph modelled on the Eq-laws text: "If an `Ord` impl or a comparator breaks a law (it is not total, transitive, or antisymmetric), `sort` returns some permutation of the input in an unspecified order. It terminates, does not panic, and stays memory-safe."
>
> ```blink
> let by_name = people.sort_by(fn(a, b) { a.name.cmp(b.name) })
> let by_dept = by_name.sort_by(fn(a, b) { a.dept.cmp(b.dept) })
> // within each dept, people stay in name order: correct only because sort is stable
> ```
>
> **Tooling reason:** an unstable sort produces flaky golden tests and snapshot diffs. Users file those as "`blink test` is nondeterministic", and we already pay that support cost for Map order (W1401, `--deterministic`). Do not add a second source of flaky output. The laws paragraph is also an implementation contract: it rules out the out-of-bounds read that a guard-free insertion sort performs when it gets an inconsistent comparator.
>
> **Cross-language:** JS left sort stability to each engine until ES2019, and code depended on V8's behaviour for years. Go has to keep `sort.Slice` and `sort.SliceStable` as separate functions. Rust made `sort` stable by default and named the fast one `sort_unstable`. Do what Rust did. Do not add `sort_unstable` now (YAGNI).
>
> ## Proposal 2: add one comparator form, `sort_by`, that returns `Ordering`
>
> ```blink
> fn sort_by(self, cmp: fn(T, T) -> Ordering ! _) -> List[T] ! _
> ```
>
> ```blink
> let newest = posts.sort_by(fn(a, b) { b.created.cmp(a.created) })        // descending
> let ranked = rows.sort_by(fn(a, b) { (a.team, a.score).cmp((b.team, b.score)) })  // multi-key via tuple Ord
> ```
>
> - **Return `Ordering`, not `Int`.** A closure written as `a - b` is then a type error with a clear message (expected `Ordering`, found `Int`), not the subtraction-overflow bug that C and Java have. `Ordering` and tuple `Ord` already exist, so this adds no new types and no `.then()`.
> - **Choose `sort_by` over `sort_by_key`.** A key form cannot express "descending on a `Str` field" unless we add a `Reverse[K]` wrapper. A trailing `.reverse()` is wrong because it also reverses the order of ties. `sort_by_key` can come later without breaking anything, the same way the Set-algebra precedent deferred set operations.
> - **Diagnostics:** the container-equality vote already promised that the error for a `T` without `Ord` would suggest `sort_by`. Today that hint points at a method that does not exist. With this proposal the `TraitBoundNotSatisfied` help text becomes `help: implement Ord for Canvas, or use .sort_by(fn(a, b) { a.key.cmp(b.key) })`.
> - **LSP:** completion shows `sort` and `sort_by` next to each other with their signatures. Users can find both.
>
> ## Proposal 3: `.sorted()` is a misspelling of `.sort()`; fix every site, and add a "did you mean" hint
>
> `.sorted()` was never voted on as a separate method, so treat it as a typo. Change it in all these places:
>
> - DECISIONS.md:343
> - decisions/hash-seed-iteration-order.md:25, 84, 132
> - 06_tooling.md:1434 and 1444
>
> The 1444 site matters most. It is W1401's **machine-applicable fix**. A fix that inserts a method that does not exist gives the user a new error, which is the worst thing a tool fix can do. The new text is `assert_eq(m.keys().sort(), ["a", "b"])`.
>
> Also fix the related sites:
>
> - 03_types.md:4208: `pairs.into_iter().sort().collect()` becomes `pairs.sort()`. Iterator has no `sort`, and making one an adapter would break the two-worlds rule.
> - 03_types.md:2207 and decisions/hash-seed-iteration-order.md:106: `names.sort()` as a statement becomes `let names = names.sort()`.
>
> Users coming from Swift or Python will type `.sorted()`. For that, add only a diagnostic, no new surface. On `UnresolvedMethod` for `sorted`, print `help: did you mean .sort()? Blink's sort returns a new list`.
>
> ## Proposal 4: lint when a copy-returning call discards its result
>
> Nothing in the spec catches `names.sort()` as a statement. The spec's own examples contain this bug, so users and models will write it too. Add a default-on warning with a machine-applicable fix (use the next free W code):
>
> ```
> warning[W0xxx]: result of `sort` is discarded
>  --> report.bl:12:5
>    |
> 12 |     names.sort()
>    |     ^^^^^^^^^^^^ `sort` returns a new sorted list; `names` is unchanged
>    = fix: names = names.sort()
> ```
>
> - **Scope:** statement-position calls to the ListOps methods that return a copy: `sort`, `sort_by`, `reverse`, `append`. It is a fixed list on a sealed surface, so false positives are near zero.
> - **Fix rule:** if the receiver is a `let mut` binding, the fix is `x = x.sort()`. If not, there is no fix and the warning says to bind the result.
> - **Not part of this proposal:** a general `#[must_use]` mechanism. That would be language surface and needs its own vote.
>
> ## Short form for the vote
>
> 1. Stable sort required by the spec, plus an Ord-laws paragraph.
> 2. Add `sort_by(fn(T, T) -> Ordering ! _)`; defer `sort_by_key`.
> 3. `.sorted()` is a typo, fixed in all places including W1401's fix text, plus a "did you mean" hint.
> 4. A narrow lint for discarded copy results.

##### AI/ML

> # AI/ML panelist — Phase A proposals (yv1sj1)
>
> ## Proposal 1 (PRIMARY): Stable `sort` + `sort_by_key` + `sort_by` returning `Ordering`
>
> ```blink
> type Person { name: Str, age: Int, last: Str, first: Str }
>
> let by_age = people.sort_by_key(fn(p) { p.age })
> let by_name = people.sort_by_key(fn(p) { (p.last, p.first) })   // multi-key via tuple Ord
> let oldest_first = people.sort_by(fn(a, b) { b.age.cmp(a.age) }) // descending: swap args
> let nums = [5, 1, 4].sort()                                      // T: Ord, unchanged
> ```
>
> Spec surface:
>
> ```blink
> fn sort(self) -> List[T]                                   // requires T: Ord
> fn sort_by_key[K: Ord](self, key: fn(T) -> K) -> List[T]
> fn sort_by(self, cmp: fn(T, T) -> Ordering) -> List[T]
> ```
>
> Decisions:
> 1. **All three are stable.** Equal elements keep input order. No `sort_unstable` in v1 (YAGNI, set-algebra precedent: addable later without breaking).
> 2. **Comparator returns `Ordering`, not `Int`.** The ticket's `fn(a, b) -> Int` is a trap: -1/0/1 vs any-sign vs `a - b` (overflows) is a guess for the LLM. `Ordering` is already in the prelude and `a.x.cmp(b.x)` produces it directly — zero new names. Multi-key = tuple Ord; descending = swap args. No `Ordering.reverse()`/`.then()` needed.
> 3. **Key/comparator fns are effect-free** (no `! _` row). This lets the spec leave the number and order of key/comparator calls unspecified without that being observable, and avoids choosing between Python-style decorate-sort-undecorate (one key call per element) and Rust-style re-evaluation. Widening to `! _` later is additive.
> 4. **Ord-laws paragraph mirroring Eq-laws:** if an `Ord` impl or comparator is not a total order, the result is an unspecified permutation of the input — never a panic, never lost/duplicated elements, memory-safe.
>
> Tradeoffs (AI/ML):
> - **Stability:** every major training-data language made its default sort stable: Python `sorted`, JS `Array.prototype.sort` (ES2019), Rust `sort`, Java (objects), Kotlin `sortedBy`. Models write chained-key sorts assuming stability; an unstable default makes that a silent wrong-answer bug that tests with distinct keys never catch. Worst class of bug for generated code.
> - **Why `sort_by_key` too:** "sort records by a field" is the dominant real-world need. `sort_by_key(fn(p) { p.age })` is ~8 tokens with no argument-order to get wrong. `sort_by` is the complete fallback (descending strings, custom orders). Names match Rust exactly, so the model's first reach resolves. Omitting them does not remove a decision — it converts it into an `UnresolvedMethod` error → retry → newtype-with-Ord-impl, which fixes one ordering per type program-wide (the ticket's stated defect).
> - **Decision points:** one rule — "Ord → `sort`, field → `sort_by_key`, anything else → `sort_by`." The three signatures differ in shape, so a wrong pick does not type-check.
>
> ## Proposal 2 (FALLBACK if panel caps new surface at one method): `sort_by(fn(T, T) -> Ordering)` only
>
> Complete (any key sort is `fn(a, b) { a.k.cmp(b.k) }`), ~6 extra tokens per call. Same decisions 1, 3, 4. I rank this below Proposal 1 but far above Ord-only: Ord-only makes "sort the same list two ways" inexpressible, which fails the "can an AI do the obvious task" bar.
>
> ## Proposal 3 (doc fix + rider): `.sorted()` is a typo; guard the discard trap
>
> - **`.sorted()` → `.sort()`** everywhere, not a distinct method: 06_tooling.md:1434, :1444 (W1401 fix text becomes `m.keys().sort()`), DECISIONS.md:343, decisions/hash-seed-iteration-order.md. Same change: 03_types.md:4208 `pairs.into_iter().sort().collect()` → `pairs.sort()` (Iterator has no `sort`; a lazy adapter cannot sort without buffering), and 03_types.md:2207 `names.sort()` statement → `let names = names.sort()`.
> - **Rider — discard warning:** In Rust, JS, and Python `list.sort()` mutates in place. The #1 predicted LLM error in Blink is `xs.sort()` as a statement, silently a no-op — the spec itself already does it (2207). Propose: discarding the result of a pure copy-returning `ListOps` transform (`sort`, `sort_by`, `sort_by_key`, `reverse`) is a default-on warning (extend W0603 `UnusedResult`), machine-applicable fix `let xs = xs.sort()`. If I must trade, this rider matters more than the naming.
> - **Cross-language note:** Python's `sorted`/`sort` encodes copy-vs-in-place in the name. Blink has only the copy form, so one name suffices; adding `sorted` as an alias would be a decision point that carries no meaning.
>
> **Summary vote position:** stable; `sort_by_key` + `sort_by(-> Ordering)`, effect-free fns; Ord-laws paragraph; `.sorted()` is a doc typo; discard lint rider.

##### Minimalism

> # Minimalism panelist: Phase A proposals (yv1sj1)
>
> **Summary:** each part comes down to one answer. Specify one sort, make it stable, add one comparator method, and fix the doc call sites.
>
> ## Proposal M1: `sort` is stable. No `sort_unstable`.
>
> Add to the `sort` row and to ListOps: **"Stable: elements that compare `Equal` keep their input order."**
>
> ```blink
> let rows = [Rec { dept: "b", name: "x" }, Rec { dept: "a", name: "y" }, Rec { dept: "b", name: "z" }]
> let by_dept = rows.sort_by(fn(a, b) { a.dept.cmp(b.dept) })
> // [y, x, z]  — x stays before z, guaranteed
> ```
>
> **Why stability costs almost nothing here:**
> - `sort` already returns a new list (Mutates = no), so we pay for an O(n) buffer anyway. A stable merge sort (or timsort) needs that same buffer, so stability adds no memory cost. The usual case for an unstable sort is "in place, no allocation", and that case does not exist in our API.
> - A stable sort gives exactly one correct output. An unstable sort leaves the output open, and "open" turns into "whatever the first implementation does". That adds one more unspecified behaviour to the spec. The hash-seed decision already shows what this costs: tests that depend on order by accident.
> - **No `sort_unstable`.** YAGNI. If profiling shows we need it, a trait extension can add it later without breaking anything (the same reasoning as the set-algebra decision at 03_types.md:518).
>
> **Ord laws paragraph.** Add this next to the Eq laws (03_types.md:2730): "`cmp` must be a total order. If a user impl or comparator breaks this, `sort` returns a permutation of its input in unspecified order. It does not panic and stays memory-safe." This copies the existing Eq-laws wording, so it adds no new idea.
>
> **Cross-language:** Rust has stable `sort` plus `sort_unstable`. Python and Java have only a stable sort, and that has worked fine for decades. Go needed both `sort.Slice` and `sort.SliceStable`, which is the C++-committee result we want to avoid.
>
> ## Proposal M2: one comparator method, `sort_by`. No `sort_by_key`.
>
> ```blink
> fn sort_by(self, cmp: fn(T, T) -> Ordering ! _) -> List[T]   // stable; no T: Ord bound
> ```
>
> I normally vote against additions. I vote for this one because **the language cannot express it today:**
> - Sorting one `List[Rec]` two ways means two `Ord` impls on one type, and Blink allows one.
> - The decorate-sort-undecorate workaround needs `Ord` on the whole tuple, which includes `Rec` itself (see the 03_types.md:4227 diagnostic).
> - Users cannot extend sealed ListOps (fact 9), so stdlib or user code cannot fill the gap.
>
> That makes it foundational, not a convenience.
>
> **Why `sort_by` and not `sort_by_key`:** the comparator form covers every case without extra helpers.
> - Descending order means you swap the arguments.
> - Multi-key and mixed-direction sorts use the tuple `Ord` the spec already has, so we need no `Ordering.then` / `.reverse()` combinators:
>
> ```blink
> let by_name = users.sort_by(fn(a, b) { (a.last, a.first).cmp((b.last, b.first)) })
> let newest  = posts.sort_by(fn(a, b) { b.created.cmp(a.created) })
> let mixed   = staff.sort_by(fn(a, b) { (a.dept, b.salary).cmp((b.dept, a.salary)) })  // dept asc, salary desc
> ```
>
> `sort_by_key(fn(T) -> K)` gives nothing that `sort_by` cannot do; it only saves typing. One method, one idea.
>
> **Details:**
> - **Return `Ordering`, not `Int`.** The ticket's `fn(a, b) -> Int` would bring back C's `strcmp` convention next to a type we already have. One way to say "less than".
> - **`! _` on the comparator**, the same as the `map` precedent (04_effects.md:2269). The spec does not define how many times or in what order `sort_by` calls `cmp`.
> - `sort()` becomes exactly `sort_by(fn(a, b) { a.cmp(b) })`. The spec states that identity, so the two methods share one semantics.
>
> **Tradeoff I accept:** this is a 13th ListOps method, so the count goes up. I would still take it over making users write a newtype wrapper with its own `Ord` impl for every sort order. That costs much more surface in user code.
>
> ## Proposal M3: `.sorted()` does not exist. Fix the docs.
>
> `.sorted()` would be a second name for a method that already returns a copy. Two names for one operation is the opposite of minimal. Edits:
> - 06_tooling.md:1444 and DECISIONS.md:343, plus decisions/hash-seed-iteration-order.md:25,84,132: change to `m.keys().sort()`. `keys()` returns `List[K]` (03_types.md:429), so this type-checks.
> - 06_tooling.md:1434: change "no intervening `sort()`/`sorted()`" to "`sort()`/`sort_by()`".
> - 03_types.md:4208: change to `pairs.sort()`. Iterator has no `sort`, and a lazy sort makes no sense.
> - 03_types.md:2207 and hash-seed decision lines 104-106: change to `let names = names.sort()`, or drop the `mut`. As written, that code throws away the sorted copy.
>
> A follow-up worth logging: a lint for a discarded `sort()`/`reverse()`/`append()` result (unused pure return value). That lint goes to the friction log, not into this vote.
>
> ## Vote position
>
> - I vote for M1 + M2 + M3 together.
> - I vote against `sort_unstable`, `sort_by_key`, `.sorted()`, `Int`-returning comparators, and `Ordering` combinators.
>
> The surface grows by exactly one method, and that method fills a real gap in what the language can express.

#### Phase B — Debate (one round; all six signalled stable)

##### Systems

> # Systems: Phase B round 1
>
> **Q2: I stay with Q2-A.** `sort_by_key` hides a cost choice. If it recomputes the key 2·n·log n times, an expensive key (such as `to_lower()` on a Str) allocates on every comparison. If it caches the keys, it needs an extra n-element buffer of `K` that the user cannot see. `sort_by(fn(a, b) { a.age.cmp(b.age) })` is one token-pair longer and shows the cost. We can add `sort_by_key` later without breaking anything, so the set-algebra precedent applies.
>
> **v1: I adopt PLT's law set.** `Ord` must be a total order consistent with `Eq`. A `sort_by` comparator only needs a total preorder. This is necessary, not pedantic: the standard use of `sort_by` is ordering by one field, and that is a preorder by definition. If the spec demanded a total order there, every normal use would break the law.
>
> **v2: yes to "terminates, and every input element appears exactly once."** A merge sort gives this for free. The only cost is that the implementation must not use unguarded insertion-sort loops. That is exactly the out-of-bounds bug class the paragraph rules out.
>
> **v3: `! _` on the parameter and on the return.** Min's signature, with `! _` on the parameter and none on the return, is unsound: the comparator's effects must show up at the call site. An effect-free version would forbid a comparator that logs or counts, and copy semantics already make an aborted sort safe. Mono specializes the effect row anyway, so it adds no runtime cost.
>
> **v4: yes.** The number and order of comparator calls are unspecified, and the receiver is unchanged on abort. Implementations need this freedom to choose a run-adaptive merge.
>
> **v5: yes, but as a semantic equivalence only.** The spec must not suggest that `sort()` routes through a closure. For primitives, codegen inlines the comparison.
>
> **v6: yes.** It is free, and it points users to the right tool.
>
> **v7: edit in place.** This fixes a misspelling, not a decision, and git keeps the history. An erratum note is harmless, so I will not fight it.
>
> **v8: no special case for one name.** A generic edit-distance "did you mean" hint covers `.sorted()` and every other typo. Special-casing one spelling is surface area with no gain.
>
> **v9: yes.**
>
> **Q4: I concede to Q4-B.** F1 settles it: W0603 already means two different things in the spec. Extending it here would add a third meaning. The lint also reaches past sorting (`reverse`, `append`, `slice`, and maybe more). File it as its own ticket, which must first resolve the W0603 naming conflict. The Q3 doc fixes stand on their own, because they rewrite the discarded `names.sort()` statement.
>
> **F2:** noted. It was a concern, not a vote, so it does not bind Q2.
>
> **F3:** `Map.keys()` returns `List[K]`, so `m.keys().sort()` is type-correct. This confirms Q3-A: `.sorted()` is a misspelling.
>
> STABLE, ready to vote

##### Web/Scripting

> ## Web/Scripting — Phase B round 1
>
> **Q2: I concede to Q2-A (`sort_by` only).** With an `Ordering` comparator, sorting by one field is one line: `users.sort_by(fn(a, b) { a.email.cmp(b.email) })`. A Python dev reads that in five minutes. `sort_by_key` saves about ten characters, and it costs a second generic method and a "which one?" question. Adding it later is an additive spec change, so YAGNI wins. My conditions: the spec's `sort_by` example must show the one-field case, and v6 must pass.
>
> **v1 Ord laws:** I back PLT's wording: `cmp` is a total order consistent with `Eq`, and a `sort_by` comparator only needs to be a total preorder. Most comparators sort by one field, and that is a preorder. Calling it a "total order" would declare most real code out of contract.
>
> **v2:** Use the strongest form: "terminates; returns a permutation of the input (every element exactly once); memory-safe; no panic." Users need to know a bad comparator cannot lose their data.
>
> **v3:** Use `! _` on both the param and the return, the same as `map`. Min's signature (`! _` on the param, none on the return) is a typo, and fixing it is not a choice. Effect-free with `! _` deferred (aiml) means a comparator that logs fails to compile, and the error names effect rows. That generates Stack Overflow questions.
>
> **v4:** Yes. Say that the number and order of comparator calls are unspecified. PLT's "if the comparator aborts, the receiver is unchanged" comes free with a copy, so state it.
>
> **v5:** Yes. Saying `sort()` ≡ `sort_by(fn(a, b) { a.cmp(b) })` costs one line and removes a question.
>
> **v6:** Yes, and Q2-A depends on it. Without `Ord` on `T`, the error must point to `sort_by`.
>
> **v7:** Edit in place. A one-line erratum note is enough, and I do not insist on it.
>
> **v8:** Yes. A "did you mean `.sort()`?" hint is cheap, and `.sorted()` is exactly what Python devs will type.
>
> **v9:** Yes.
>
> **Q4: I hold Q4-A.** The spec's own example (03_types.md:2207) has this bug, and two ratified decision files repeat it. If the spec authors made this mistake, every Python and JS migrant will too. Deferring the lint to a ticket ships the trap together with the method. Scope: every copy-returning ListOps transformation (`sort`, `sort_by`, `reverse`, `append`, `slice`).
>
> **F1 settles the code question:** W0603 already has two conflicting names. Do not make a third claim on it. Allocate a new W code now, and file the W0603 naming conflict as a separate bug.
>
> **F2:** Noted. A Concern field from a past panel does not create a `sort_by_key` commitment, which is consistent with my concession.
>
> **F3:** Confirms that `m.keys().sort()` type-checks, so the Q3 fixes are correct.
>
> STABLE, ready to vote

##### PLT

> # PLT — Phase B round 1
>
> **Q2: A, but B is acceptable.** `sort_by_key` is `sort_by(fn(a, b) { key(a).cmp(key(b)) })`, so it adds surface and no expressive power. I will not block B. If B wins, the spec must say the key fn is called an unspecified number of times, the same as v4.
>
> **v1 matters for soundness, not only wording.** A `sort_by` comparator must be a total **preorder**, not a total order. Requiring a total order would forbid the main use: `fn(a, b) { a.age.cmp(b.age) }` returns `Equal` for two different records, and that breaks antisymmetry as "total order" is defined. Under the bare "total order" wording, every key comparator breaks a law. Stability is defined on `Equal`, so a preorder is exactly what it needs. For `Ord.cmp` I keep "consistent with `Eq`" (`cmp == Equal` iff `==`). Without it, `sort` and `index_of`/`contains` disagree about which elements are the same. Rust and Haskell state this law too.
>
> **v2: include both additions.** The result terminates, and it is a permutation in which every element appears exactly once. "Permutation" already implies the second, but saying it outright tells the C implementer what they must guarantee.
>
> **v3: `! _` on both the param and the return.** Min's signature, with `! _` on the param but a pure return, is **unsound**: the comparator's effects would escape the row. Deferring to an effect-free comparator (aiml) is additive on paper, but it breaks consistency with `map`/`filter`, which already carry `! _`. A comparator that logs or reads config would have to fail now.
>
> **v4, v5: yes.** These are my own points. The definitional equation in v5 gives `sort` its meaning.
>
> **v6: yes.** It costs nothing. F2 confirms nothing binds the wording, so the help text can suggest `sort_by`.
>
> **v7: edit in place with a one-line erratum note.** A decision record is history, so a silent edit hides that the ratified text had a typo.
>
> **v8: yes,** as a non-normative tooling hint.
>
> **v9: yes.**
>
> **Q4: still B.** F1 shows W0603 has two names in the spec today. "Extend W0603" therefore picks a side in an unresolved naming conflict as a side effect of a sort ticket. Fix F1 first, then decide the lint (new code or extended) in its own ticket. I support the *principle* (a discarded copy should warn) as a recorded intent here.
>
> **F3:** `keys()` returns `List[K]`, so `m.keys().sort()` type-checks. That confirms Q3-A needs no alias.
>
> STABLE, ready to vote

##### DevOps/Tooling

> # DevOps/Tooling — Phase B round 1
>
> **Q2: I hold Q2-A (`sort_by` only).** The Q2-B case for `sort_by_key` is that it is familiar from Python's `key=` and short to write. I do not find that enough:
> - A key form cannot express "descending on a `Str` field" unless we add a `Reverse[K]` wrapper. Without one, users write `.sort_by_key(k).reverse()`, which also reverses the order of ties, and no warning catches it.
> - Multi-key sorting already works through tuple `Ord` in `sort_by`.
> - `sort_by_key` can be added later without breaking anything. For LSP, a single method means one completion entry to find and one help-text target.
>
> **Variations:**
> - **v1, accept plt's law set.** `cmp` is a total order consistent with `Eq`, and a comparator only needs to be a total preorder. The text is more exact, and the diagnostics do not change.
> - **v2, accept all clauses.** These are "terminates" and "every element appears exactly once". The implementer needs both as a contract.
> - **v3, use `! _` on the parameter and the return.** If the comparator is effect-free, a comparator that logs gets an effect-mismatch error on a closure the user thinks is pure. That is a bad first error. Min's signature leaves `! _` off the return. That is a defect: the effect would be dropped. The signature must be `-> List[T] ! _`.
> - **v4, accept.** The number and order of comparator calls are unspecified. "Receiver unchanged on abort" follows from the copy semantics, so stating it costs nothing.
> - **v5, accept.** `sort()` ≡ `sort_by(fn(a, b) { a.cmp(b) })` gives a one-line hover doc.
> - **v6, keep.** F2 is correct that the earlier mention was a Concern field, not a vote. I ask that this decision vote the help text, because `sort_by` now exists.
> - **v7, accept web's erratum note.** The edit changes nothing that was voted, but a one-line note keeps the record honest.
> - **v8, keep the "did you mean" hint.**
> - **v9, accept.** In addition, W1401's "intervening sort" check must count `sort_by` as a sort. Otherwise it gives a false positive on the method we just added.
>
> **Q4: I hold Q4-A, and I change one detail because of F1.** Do NOT extend W0603:
> - The code is already used for `ShadowedVariable` (src/diagnostics.bl:213, 03_types.md:2470).
> - The `UnusedResult` lint voted in the fs decision is about a dropped `Result[T, E]` error, which is a different diagnosis with a different fix text.
>
> So use a new code, `DiscardedCopy`, scoped to the copy-returning ListOps methods (`sort`, `sort_by`, `reverse`, `append`), with the fix `x = x.sort()`. The spec's own examples contain this bug three times. If we defer the lint, the sort implementation ships with a known silent mistake. I would accept Q4-B only if the lint ticket blocks the sort implementation ticket.
>
> **Separately:** F1 is a real code collision between the voted `W0603 UnusedResult` and the shipped `W0603 ShadowedVariable`. File a bug ticket for it whatever we decide here.
>
> **F3:** `keys()` returns `List[K]`, so `m.keys().sort()` type-checks. The W1401 fix text is valid after the Q3 edit.
>
> STABLE, ready to vote

##### AI/ML

> # AI/ML — Phase B round 1
>
> **Q2 (A vs B): I hold Q2-B, but will not block Q2-A.** `sort_by_key` is the shape models reach for first (Rust `sort_by_key`, Python `key=`, Kotlin `sortedBy`, lodash `sortBy`). Under Q2-A that first try is `UnresolvedMethod`, then a retry. F2 is a useful signal here: the container-equality panel wanted the error text to suggest "`sort_by` with a key". That is exactly the gap. If Q2-A wins, v6 becomes mandatory: the help text must show the full rewrite `xs.sort_by(fn(a, b) { a.k.cmp(b.k) })`, and an `UnresolvedMethod` on `sort_by_key` should suggest the same rewrite. That turns the retry into a single, fixed step.
>
> **v3: I concede `! _`.** Matching `map`/`filter` (`fn(T) -> U ! _`) is the stronger learnability argument, since one HOF rule beats a special case. With `! _`, v4 is required: the number and order of comparator calls is unspecified. I also support plt's "comparator aborts → receiver unchanged", which follows from copy semantics anyway. Fix min's signature: the return must carry `! _` too (`-> List[T] ! _`) to match 04_effects.md:2269.
>
> **v1: adopt plt's law set.** For `Ord`: a total order consistent with `Eq` (`cmp == Equal` iff `==`). For a `sort_by` comparator: a total preorder. The preorder wording is what makes "sort by age" legal, because unequal records compare `Equal`. Without it, every key comparator technically breaks the law.
> **v2: take the union.** Terminates, every element appears exactly once, unspecified order, memory-safe, no panic.
> **v5: yes.** The equivalence `sort() ≡ sort_by(fn(a, b) { a.cmp(b) })` makes stability and the laws one definition. It is cheap and closes edge cases.
> **v6: yes** (see Q2).
> **v7: edit in place with a one-line erratum note** in DECISIONS.md and the hash-seed decision file. Decision records are history, and a silent rewrite misleads anyone diffing what was voted. Spec sections get a plain edit.
> **v8: yes.** `.sorted()` is the Python spelling. A "did you mean `.sort()`" hint costs almost nothing and catches a predictable LLM error.
> **v9: yes.**
>
> **Q4: A, decide it now.** The spec already contains this bug (2207), so it is not hypothetical. Deferring it ships the trap together with the fix that exposes it.
> - **Code:** F1 shows W0603 is already `ShadowedVariable` in 03_types.md:2470, and DECISIONS.md:353 reuses the same number for `UnusedResult`. So I withdraw "extend W0603". Use a **new W code** for a discarded copy, and log the W0603 double-assignment as its own friction/bug.
> - **Scope:** every `Mutates = no` method that returns `List[T]`: `sort`, `sort_by`, [`sort_by_key`], `reverse`, `append`, `slice`. `append` matters most. Python's `list.append` mutates, so `xs.append(ys)` as a statement is the single most likely LLM no-op. The fix is `let xs = xs.append(ys)`.
>
> **F3:** since `Map.keys()` is `List[K]`, `m.keys().sort()` type-checks. That confirms Q3-A as a pure doc fix.
>
> STABLE, ready to vote

##### Minimalism

> # Minimalism: Phase B round 1
>
> ## Q2-A vs Q2-B: I hold Q2-A (`sort_by` only)
>
> Web's own example makes the case against Q2-B: `posts.sort_by_key(fn(p) { p.created_at }).reverse()`. `.reverse()` flips the order of tied elements, so a "stable newest-first" sort is not stable. The key form leads users to `.reverse()` for descending order, and that quietly breaks the Q1 guarantee we all just voted for. With `sort_by` you swap the arguments, `b.created_at.cmp(a.created_at)`, and ties keep their order.
>
> `sort_by_key` also brings a spec question that `sort_by` does not have: does `sort_by_key` call `key` n times (cached, as in Python) or n log n times (as in Rust's `sort_by_key` versus `sort_by_cached_key`)? With an effectful `! _` key, users can see the difference. That is one more thing to specify, for a method that only saves typing. The sealed-surface argument (fact 9) explains why the comparator form must exist now. It does not explain why sugar must exist now. A later additive vote can add `sort_by_key`.
>
> ## Variations
>
> - **v1: I concede to plt's law set.** `Ord.cmp` must be a total order consistent with `Eq`. A `sort_by` comparator need only be a total preorder. This is more correct and adds no surface.
> - **v2: I accept** "terminates, and every input element appears exactly once."
> - **v3: `! _` on both the parameter and the return** (`-> List[T] ! _`). My signature was missing the return row, and I concede that point. I reject aiml's effect-free version: it breaks the `map` precedent and adds a special case.
> - **v4: yes.** The "receiver unchanged on abort" rule follows automatically from returning a copy. State it anyway.
> - **v5: yes.**
> - **v6: yes.** It is diagnostic text, not language surface.
> - **v7: edit in place.** Git keeps the history. An erratum note is fine as long as it takes one line.
> - **v8: only if it comes from the generic "did you mean" edit-distance hint.** No special case for `.sorted()`.
> - **v9:** keep my wording.
>
> ## Q4: I hold Q4-B
>
> The fault is not specific to `sort`. Any pure call whose result is thrown away has it. A hand-picked list of six ListOps methods is the ad-hoc shape that grows a new entry every release. F1 shows that W0603 already has two names in the spec. Setting a lint code inside a sort ticket would mean fixing that collision as a side job here. File the general "discarded pure return value" lint as its own ticket. If Q4-A wins anyway, extend the general UnusedResult lint; do not mint a sort-specific code.
>
> ## Facts F1–F3
>
> All three are accepted. F2 means no prior vote binds us to a key form. F3 confirms that `m.keys().sort()` type-checks.
>
> STABLE, ready to vote

#### Phase C — Final vote

- **Q1: stable `sort` and `sort_by`, no `sort_unstable`** — 6-0 A
- **Q2: Ord laws (total order agreeing with `Eq`; comparator a total preorder; terminate + permutation on a breach)** — 6-0 A
- **Q3: `sort_by` only, no `sort_by_key`** — 6-0 A
- **Q4: `.sorted()` is a misspelling; fix every site** — 6-0 A
- **Q4.1: erratum note on the edited decision records** — 6-0 A
- **Q5.1: missing-`Ord` help suggests `sort_by`** — 6-0 Yes
- **Q5.2: `.sorted()` hint** — 3-3 (A: web, aiml, devops; B: sys, plt, min) → Phase D
- **Q6: discarded-copy lint** — 3-1-2 (A: web, aiml, devops; B: plt; C: sys, min) → Phase D

##### Systems

> # Systems: Phase C vote (yv1sj1)
>
> **Q1: A**
> - **Reasoning:** A stable merge sort costs one extra n-element scratch buffer on top of the copy we already allocate. The comparison count stays n log n, and close to O(n) on input that is already sorted. The copy semantics already pay most of the bill. Stability turns multi-pass sorting from a latent bug into correct code at a known, bounded cost.
> - **Concern:** An implementer may pick an in-place stable algorithm (block or rotation merge) to save the buffer, and its constant factors are much worse. The spec should leave the algorithm open, but the impl ticket should name a buffered run-adaptive merge.
>
> **Q2: A**
> - **Reasoning:** A key comparator such as `a.age.cmp(b.age)` returns `Equal` for different records, so under plain "total order" wording every normal `sort_by` call breaks a law. The preorder wording matches exactly what stability is defined over. "Terminates, permutation, memory-safe, no panic" is free with a guarded merge sort, and it rules out the out-of-bounds bug class of unguarded insertion sort.
> - **Concern:** "Consistent with `Eq`" can be broken by a derived `Eq` next to a hand-written `Ord`. That gives silently surprising results with no diagnostic, so a later lint may be needed.
>
> **Q3: A**
> - **Reasoning:** `sort_by_key` hides a cost choice the user cannot see: it either recomputes the key 2·n·log n times (an allocating key allocates on every comparison) or caches it in a hidden n-element `K` buffer. Min's and DevOps' point settles it: the key form pushes users toward `.reverse()` for descending order, which breaks the stability we voted in Q1. `sort_by` shows its cost, and we can add the key form later without breaking anything.
> - **Concern:** A model's first try will often be `sort_by_key` and fail. Q5.1 and a generic hint must make that retry one step.
>
> **Q4: A**
> - **Q4.1: A** (edit in place with a one-line erratum note).
> - **Reasoning:** `Map.keys()` returns `List[K]`, so `.sort()` is already type-correct. An alias would only add surface on a sealed trait. The erratum note costs one line and keeps the decision record honest about what was ratified.
> - **Concern:** One of the listed sites could be missed. The implementer should run `rg 'sorted\('` across the repo after the edit.
>
> **Q5**
> - **Q5.1: Yes.** It is diagnostic text with no runtime or surface cost, and it points users to the right tool.
> - **Q5.2: B.** A generic edit-distance hint covers `.sorted()` and every other typo. Special-casing one spelling is maintenance with no gain.
> - **Concern:** If the generic hint does not exist yet, B gives no hint at all for now.
>
> **Q6: C**
> - **Reasoning:** The fault is "a discarded pure return value", not something specific to sort. `reverse`, `append` and `slice` already ship with the same trap, so blocking `sort` on the lint protects nothing they don't already expose. The Q4 doc fixes remove the spec's own instances. The lint code also has to wait until the W0603 collision (F1) is resolved.
> - **Concern:** Without a blocker, the lint ticket could go stale while users hit `names.sort()` no-ops. It needs a priority, not just a filing.

##### Web/Scripting

> # Web/Scripting — Phase C vote
>
> **Q1 — Vote: A**
> - **Reasoning:** Python, Kotlin, and modern JS (ES2019) all sort stably. Scripting devs assume it, and chain sorts on that assumption. An unstable sort makes bugs that show up only on some inputs, and nobody can find those from a Stack Overflow answer.
> - **Concern:** someone may later "optimize" a primitive `List[Int]` sort to an unstable algorithm. The test suite must check stability on records, not on Ints.
>
> **Q2 — Vote: A**
> - **Reasoning:** the main real use is "sort by one field", which returns `Equal` for different records. Under the plain "total order" wording, the first example in every tutorial would break a law. The breach clauses tell a user, in plain terms, that a bad comparator cannot lose their data.
> - **Concern:** "total preorder" and "consistent with `Eq`" are jargon. The spec paragraph needs a plain example (sort by age, ties keep their order) right next to the law.
>
> **Q3 — Vote: A**
> - **Reasoning:** with an `Ordering` comparator, `xs.sort_by(fn(a, b) { a.name.cmp(b.name) })` is one line that a Python dev understands at once. Min's point decided it for me: `.sort_by_key(k).reverse()` for descending order quietly breaks stability, while swapping `a` and `b` does not. We can add `sort_by_key` later.
> - **Concern:** devs coming from Python, Rust, and lodash will type `sort_by_key` first. Without a Q5 help text that shows the `sort_by` rewrite, that first try is a dead end.
>
> **Q4 — Vote: A; Q4.1 — Vote: A**
> - **Reasoning:** `.sorted()` is a misspelling, and two names for one operation produce endless "which one?" questions. The erratum note costs one line, and it tells a reader who diffs the decision record why the ratified text changed.
> - **Concern:** the fix list may miss a site. After the edit, grep for `sorted(` and `.sort()` used as a statement across `sections/` and `decisions/`.
>
> **Q5.1 — Vote: Yes**
> - **Reasoning:** "implement `Ord`" is the wrong advice for a newcomer who only wants to sort a table by one column. The help text must show the one-line `sort_by` rewrite.
> - **Concern:** the help text may print a field name that does not exist on `T`. It should use a placeholder (`a.key`) or a real field name, never a guess that looks real.
>
> **Q5.2 — Vote: A**
> - **Reasoning:** `.sorted()` is the most predictable typo from Python devs and from LLMs. A generic edit-distance hint suggests `.sort()` but does not say why it is correct, namely that Blink's `sort` already returns a new list. That second sentence answers the follow-up question before anyone asks it.
> - **Concern:** special cases tend to multiply. Keep this to a short, deliberate table of known names from other languages, not one-off code paths.
>
> **Q6 — Vote: A**
> - **Reasoning:** our own spec author wrote `names.sort()` as a statement, and the same bug sits in two ratified decision records. Every Python and JS migrant will make it on day one. Python's `append` mutates, so `xs.append(ys)` is an even worse trap. If the lint ships later than `sort`, the trap ships with no guard. A new code avoids the W0603 conflict.
> - **Concern:** if a general "discarded pure value" lint arrives later, `DiscardedCopy` must become its subset under the same code, or users will see two warnings for one line.

##### PLT

> # PLT — Phase C vote (yv1sj1)
>
> **Q1 — Vote: A**
> Reasoning: Only a stable sort is a function of its input value. When `Eq` is coarser than structural equality, an unstable sort is a relation, and that breaks the purity analysis the spec already relies on. Stability also gives the composition law `xs.sort_by(k2).sort_by(k1)` = lexicographic `(k1, k2)`.
> Concern: Users may still reach for `.reverse()` to get descending order, which flips ties. The spec should show the swapped-argument comparator form.
>
> **Q2 — Vote: A**
> Reasoning: A key comparator such as `a.age.cmp(b.age)` is a preorder by definition, so "total order" wording for comparators puts every normal use out of contract. Consistency with `Eq` for `Ord.cmp` keeps `sort`, `contains` and `index_of` agreeing about which elements are the same. The breach clauses (terminates, exact permutation, memory-safe) are the contract the C implementation must meet.
> Concern: Implementers may treat the breach clause as a non-goal and ship an unguarded insertion pass. The sort ticket needs a test with an inconsistent comparator.
>
> **Q3 — Vote: A**
> Reasoning: `sort_by_key` adds no expressive power. With an effectful key, it adds a new open question: is the key called n times or n log n times? It also leads to `.reverse()` for descending order, which breaks the stability we just voted for. It can be added later without breaking anything.
> Concern: The first try for many users and models will be `sort_by_key`. Q5.1 and the generic "did you mean" hint must turn that into a one-step fix.
>
> **Q4 — Vote: A**
> Reasoning: `Map.keys()` returns `List[K]` (F3), so `.sort()` is type-correct at every site. An alias would be a second name for one function with no gain.
> **Q4.1 — Vote: A.** A decision record is history. A silent edit hides that the ratified text was wrong.
> Concern: Missing a site. Grep for `sorted(` across sections/, decisions/ and DECISIONS.md after the edit.
>
> **Q5.1 — Vote: Yes.**
> Reasoning: The help text is diagnostic only, not surface, and it points to the one form that needs no `Ord` impl.
> Concern: The example key in the help text must be a real field. If not, the machine-applicable fix will not type-check.
>
> **Q5.2 — Vote: B.**
> Reasoning: A generic edit-distance hint covers `.sorted()` and every other typo under one rule. A special case for one name is ad-hoc surface.
> Concern: If the generic hint's distance threshold misses `sorted` → `sort`, the case needs a test, not a special rule.
>
> **Q6 — Vote: B.**
> Reasoning: The principled lint is "discarded result of a pure, non-unit call". That is a general typing-level notion, not a list of ListOps methods, and the W0603 clash (F1) must be fixed first. But the spec's own examples hit this trap three times, so the sort implementation must not ship without the lint. Blocking gets both: the right scope and no shipped trap.
> Concern: The lint ticket may stall on the W0603 clash and hold up `sort` indefinitely. Order the F1 bug ticket first.

##### DevOps/Tooling

> # DevOps/Tooling — Phase C vote (yv1sj1)
>
> **Q1 — Vote: A**
> **Reasoning:** An unstable sort produces flaky golden files and snapshot tests. Users report these as tool bugs ("`blink test` is nondeterministic"), and we already pay that support cost for Map order. JS shows the cost of an unstated answer: engines diverged until ES2019. Stability must be part of the contract from the first implementation.
> **Concern:** A future performance push asks for `sort_unstable`, and nobody records that adding it is a separate vote.
>
> **Q2 — Vote: A**
> **Reasoning:** The preorder clause is what makes `sort_by(fn(a, b) { a.age.cmp(b.age) })` legal. Under plain "total order" wording, every one-field comparator breaks a law. That would make any future "comparator violates contract" lint fire on correct code. The breach clauses (terminates, every element exactly once) give the C implementer a contract to test against.
> **Concern:** Users will not read "consistent with `Eq`". A derived `Eq` paired with a hand-written `Ord` that disagree will give quiet `index_of`/`sort` mismatches, and no diagnostic flags them.
>
> **Q3 — Vote: A**
> **Reasoning:** With one method, LSP completion shows one entry and every help text points to one place. `sort_by_key(...).reverse()` silently breaks the stability we just voted for, and no lint can catch that. The aiml retry cost goes away if the `UnresolvedMethod` error on `sort_by_key` shows the exact `sort_by` rewrite.
> **Concern:** If the `sort_by_key` → `sort_by` rewrite hint is not implemented, every model makes its first try with `sort_by_key`, it fails, and that costs a round trip.
>
> **Q4 — Vote: A; Q4.1 — Vote: A**
> **Reasoning:** W1401's machine-applicable fix currently inserts a method that does not exist. A fix that creates a new error is the worst failure a tool can have, so every site must change, including the "`sort`/`sort_by` counts as a sort" check. A one-line erratum note in the decision records costs nothing and stops anyone who diffs the voted text from thinking the vote changed.
> **Concern:** Someone misses a `.sorted()` site, for example in llms docs or the lint's fix template in src. The spec stays clean, but the tool still emits `.sorted()`.
>
> **Q5.1 — Vote: Yes**
> **Reasoning:** If `sort` has no comparator escape, the user hits a dead end. The help text is how users discover `sort_by`. It costs one string.
> **Concern:** The suggested key in the help text is a placeholder (`a.key`). It must not be marked machine-applicable.
>
> **Q5.2 — Vote: A**
> **Reasoning:** A generic edit-distance hint says "did you mean `sort`", but it does not say why. "Returns a new list" teaches the copy semantics at the moment a Swift or Python user is most likely to drop the result. It is one table row in the "did you mean" engine.
> **Concern:** The special-case table becomes a junk drawer unless each entry needs a semantic note, which is the bar here.
>
> **Q6 — Vote: A**
> **Reasoning:** The spec's own examples contain this bug, so it is certain to occur. A fixed list of methods on a sealed surface gives near-zero false positives and a fix with a definite rewrite (`x = x.sort()`). A general "discarded pure value" lint needs purity inference and decisions about scope, so it slips. B is my acceptable fallback, because it still keeps the trap from shipping with sort. C ships the trap.
> **Concern:** The code set of a new `DiscardedCopy` code and a later general UnusedResult lint overlap. When the general lint lands, it must absorb `DiscardedCopy` (one diagnostic per site), not fire next to it.

##### AI/ML

> # AI/ML — Phase C vote (yv1sj1)
>
> **Q1 — Vote: A**
> - **Reasoning:** Every default sort in the training data is stable: Python, JS (ES2019), Rust, Java (objects), and Kotlin. Models write chained-key sorts that assume it. An unstable default would be a silent wrong-answer bug that tests with distinct keys never catch.
> - **Concern:** An implementer could pick an in-place quicksort for primitive `T` "because ties are indistinguishable". That is true for `Int`, but the shortcut could spread to struct `T` with a custom `Ord`.
>
> **Q2 — Vote: A**
> - **Reasoning:** The idiomatic use, `fn(a, b) { a.age.cmp(b.age) }`, is a preorder. Plain "total order" wording would put the code models write most often out of contract, so a spec-following model gets contradictory signals. "Consistent with `Eq`" keeps `sort` and `contains`/`index_of` agreeing on what counts as the same element.
> - **Concern:** "Total preorder" and "consistent with `Eq`" are jargon. The paragraph needs one worked example (sort by age, two records compare `Equal`) or learners will not see why it matters.
>
> **Q3 — Vote: A** (changed from my Phase A primary)
> - **Reasoning:** Min and DevOps showed that `sort_by_key(k).reverse()` is the natural descending idiom, and it reverses the order of ties. That breaks Q1 with no warning. It is exactly the pattern an LLM produces, because Python's `key=` with `reverse=True` keeps ties stable and Blink's would not. `sort_by` with swapped arguments has no such trap. The key-call-count question is also avoided. `sort_by_key` stays additive later.
> - **Concern:** The first reach of a model trained on Rust or Python will be `sort_by_key` and will fail. Q5.1, plus an `UnresolvedMethod` hint on `sort_by_key` that shows the `sort_by` rewrite, must carry that load.
>
> **Q4 — Vote: A; Q4.1: A**
> - **Reasoning:** `.sorted()` is the Python spelling, and `sort` returns a copy, so this is a doc typo, not a missing method. An alias would add a decision point that carries no meaning. A one-line erratum note keeps the ratified record honest for anyone who diffs it against the vote.
> - **Concern:** A site could be missed, for example a decision file not listed here. A grep for `sorted(` across sections/ and decisions/ should be part of the edit.
>
> **Q5.1 — Vote: Yes**
> - **Reasoning:** The error is the teaching moment. The full one-line `sort_by` rewrite in the help text turns a failed generation into a single, fixed repair step.
> - **Concern:** The help text could suggest `a.key` literally. It should name a real field of `T`, or use a clearly marked placeholder.
>
> **Q5.2 — Vote: A**
> - **Reasoning:** `.sorted()` is a high-frequency, predictable LLM and Python-migrant error. The specific hint also teaches the semantic point ("returns a new list"), which a generic edit-distance hint does not. The cost is one table entry.
> - **Concern:** It sets a precedent for adding special-case hints, so keep such hints to cross-language spellings with evidence.
>
> **Q6 — Vote: A** (B is my second choice)
> - **Reasoning:** The spec's own examples contain the discarded-copy bug three times. `xs.append(ys)` as a statement is the single most likely LLM no-op, because Python's `append` changes the list in place. Shipping `sort` without the lint ships a known trap.
> - **Concern:** A hand-picked method list grows over time. The `DiscardedCopy` code should be defined by the rule (any `Mutates = no` method returning the receiver's type), not by a list of names.

##### Minimalism

> # Minimalism: Phase C vote
>
> **Q1: A**
> - **Reasoning:** Stable is the only answer that fully specifies the result. `sort` already returns a copy, so the buffer that merge sort needs is already paid for. `sort_unstable` would be a second method that saves nothing in this API.
> - **Concern:** Later someone asks for `sort_unstable` "for speed". We should hold the line until a profile shows it is needed.
>
> **Q2: A**
> - **Reasoning:** Requiring a total preorder for comparators is what makes the usual one-field `sort_by` legal. Without it, every key comparator breaks the law. The extra wording costs no surface, and the breach clauses copy the existing Eq-laws precedent.
> - **Concern:** "consistent with `Eq`" binds every hand-written `Ord` impl, so `@derive` and hand-written impls must both obey it, and nothing checks that.
>
> **Q3: A**
> - **Reasoning:** `sort_by` is the foundational addition. Users cannot extend sealed ListOps, and one `Ord` impl per type cannot express two orders. `sort_by_key` adds no expressive power, and it invites `.reverse()` for descending order, which silently breaks the stability we just voted for. It also opens a question about how often the key is called. It can be added later without breaking anything.
> - **Concern:** Models and Python migrants will type `sort_by_key` first. The Q5.1 help text and a generic "did you mean" hint must catch it.
>
> **Q4: A**
> - **Reasoning:** `keys()` returns `List[K]`, so `.sort()` type-checks in that position. Two names for one operation is pure surface cost.
> - **Concern:** The sweep misses a site and the W1401 fix text keeps pointing at a method that does not exist.
>
> **Q4.1: A**
> - **Reasoning:** The erratum costs one line and keeps the ratified record honest about what changed. It changes no vote.
> - **Concern:** None of substance.
>
> **Q5.1: Yes**
> - **Reasoning:** This is diagnostic text, not surface. It is the cheapest way to make Q3-A discoverable.
> - **Concern:** The help text drifts from the real signature if `sort_by` changes later.
>
> **Q5.2: B**
> - **Reasoning:** Every typo should get a generic edit-distance hint. Special-casing one spelling is the kind of one-off rule that piles up.
> - **Concern:** The generic hint may fall below its distance threshold for `sorted` → `sort` and then say nothing.
>
> **Q6: C**
> - **Reasoning:** The fault is "a pure result was thrown away", not anything specific to `sort`. A hand-picked list of five ListOps methods will need a new entry in every release. F1 shows the W-code space needs fixing before anything else claims a number. A warning does not change what `sort` means, so the implementation has no reason to wait for it.
> - **Concern:** Without a blocker, the general lint gets deferred forever and the `names.sort()` trap ships to users.

#### Phase D — Round 2 (Q5.2 and Q6)

##### Focused debate

##### Systems

> # Systems: Phase D debate (Q5.2, Q6)
>
> ## Q5.2: I move from B to A
>
> I checked the code, and it defeats my own concern. In the current compiler, the generic hint does **not** reach `.sorted()`:
>
> - `tc_suggest_method` (src/typecheck.bl:13954) sets the threshold at `len / 3`, which is 2 for `sorted`. It then requires `best_dist < threshold` when the threshold is above 1. The distance from `sorted` to `sort` is 2, so 2 < 2 fails.
> - The fallback `tc_builtin_method_edit1` (:13905) only tries one deletion or one transposition. `sorted` needs two deletions.
>
> So with B, `.sorted()` gets no hint at all. That is the exact failure PLT and Min named as their concern. Widening the generic threshold to catch it would add false suggestions on every receiver, which is a worse trade.
>
> A also has a precedent. `tc_list_rename_help` (:12938) is already a deliberate table of cross-language List spellings, each with a note on meaning: `concat` gives "list concatenation is `.append(other)`", and `collect` gives an explanation of the two worlds. A `sorted` row ("`.sort()` already returns a new list") fits that pattern exactly. It is not a new one-off code path. Web and DevOps set the right bar, and I adopt it: an entry goes in the table only if it carries a note about meaning.
>
> ## Q6: I move from C to B
>
> I said C because `reverse`, `append` and `slice` already ship with the trap, so blocking `sort` would protect nothing new. That is true, but it misses frequency. Rust and Python teach `xs.sort()` as a statement, and our own spec author wrote it in three places. `sort` is where the trap gets hit most, so the sort implementation is the right place for the lint to land. Min's concern about my C vote also stands: a ticket that blocks nothing gets deferred forever.
>
> I do not go to A. F1 means no W code should be claimed in this deliberation, and PLT is right that the rule belongs in its own ticket.
>
> **Condition on B, aimed at PLT's stall concern.** The blocking ticket must be shippable without purity inference. The rule's first cut is "a discarded result of a `Mutates = no` method on a sealed collection surface that returns the receiver's type". That rule comes from the signature, not from a list of names, which answers Min's concern. Any general "pure non-unit call" extension is a follow-up that does not block `sort`. Fix the F1 bug first. If purity inference ends up in the blocking ticket, `sort` stalls on a type-system project. That is the failure PLT predicted, and I would rather prevent it than discover it.
>
> **Votes now: Q5.2 = A, Q6 = B.**

##### Web/Scripting

> # Web/Scripting — Phase D debate (Q5.2, Q6)
>
> ## Q5.2 — I hold A
>
> Sys, PLT, and Min all say "one generic rule covers every typo." I agree that the generic hint should exist. But two of their own concerns argue for A:
> - **Min and PLT** both worry that the distance threshold misses `sorted` → `sort`. That is a real risk: it is a two-character suffix, and many edit-distance cutoffs scale with name length.
> - **Sys** says the generic hint may not exist yet, in which case B means no hint at all.
>
> So B gives either nothing or "did you mean `sort`?" with no reason given. The Python dev then writes `names.sort()` as a statement, because that is how `sort` works in Python, and hits the Q6 trap.
>
> The specific hint exists to say "Blink's `sort` returns a new list". Edit distance cannot produce that sentence. The worry about piling up one-off rules is fair, and I accept DevOps's bar: an entry goes in the table only if it carries a semantic note about a cross-language difference. That keeps the table small. Today the only entry would be `sorted`.
>
> ## Q6 — I move from A to B
>
> PLT's reasoning answers the concerns from both sides better than A does:
> - **Sys, Min, PLT:** the lint should be defined by a rule ("discarded result of a pure, non-unit call"), not by a list of five names. AIML and DevOps raised the same point in their concerns. I wrote the same concern myself: a later general lint would have to absorb `DiscardedCopy`. If we build the general lint once, nothing needs absorbing.
> - **F1:** minting a new code while W0603 is double-assigned adds to a mess we have not cleaned up. Fixing the W0603 clash first is the right order.
> - **The trap must not ship with `sort`.** That was my whole case for A, and B keeps it. C does not. Sys and Min both list "the lint goes stale and users hit the trap" as their own concern for C, and the blocking dependency is what prevents it.
>
> Sys's point that `reverse`, `append`, and `slice` already ship with the trap is true. But it argues for fixing the trap sooner, not for shipping one more instance of it. `sort` is the method where Python and JS habit is strongest: both languages sort in place, so `xs.sort()` is a whole statement there. For migrants, `sort` is the worst place for this trap.
>
> **Condition on B:** order the F1 (W0603) bug ticket ahead of the lint ticket, and keep the lint's first version narrow enough to land. "Pure, non-unit call" over sealed builtin surfaces is enough for v1; full purity inference for user fns can follow. Otherwise B stalls `sort` indefinitely, which is PLT's own concern.
>
> **Final positions: Q5.2 A (holds), Q6 B (moved from A).**

##### PLT

> # PLT — Phase D debate (Q5.2, Q6)
>
> ## Q5.2 — my vote holds: B
>
> Web, aiml and devops all argue that a specific hint teaches "returns a new list". But look at when the hint fires. The hint fires on `UnresolvedMethod` for `.sorted()`. A user who writes `.sorted()` has almost always *used* the result (`let s = xs.sorted()`, `for k in m.keys().sorted()`), because `sorted` is the copy-returning name in Python and Swift. That user already holds the right mental model, and "returns a new list" tells them nothing new. The user who needs that sentence is the one who writes `names.sort()` as a statement. That user never sees an `UnresolvedMethod` hint. The Q6 lint is the right place for the sentence.
>
> To answer devops's "it doesn't say why": let the generic hint print the target's signature line (`did you mean .sort()? fn sort(self) -> List[T]`). The return type then carries the "returns a new list" point for every method, with no table. That is one rule, not a list of special cases. Min's and sys's concern (a threshold miss) is a test case on the generic hint, not a reason for a special case.
>
> ## Q6 — I move: A, with two conditions
>
> Sys's reasoning moved me off B. `reverse`, `append` and `slice` already ship with the same trap, so blocking `sort` alone protects nothing. A blocker that is arbitrary is not principled. C ships a known trap, which sys and min both name as their own concern. That leaves A.
>
> My objection to A was "a hand-picked list of names". Aiml's concern answers it. If the lint is defined by a *declared property*, not by names, it is a sound rule:
>
> 1. **Scope is a rule:** a call to a sealed built-in method whose spec row says `Mutates = no` and whose return type is the receiver's type, used as a statement. This needs no purity inference, because the property is already in the spec table (devops's slip risk goes away), and new methods are covered with no new entry (min's concern goes away).
> 2. **Subsumption:** if a general "discarded pure result" lint lands later, it absorbs `DiscardedCopy`, keeping the code or aliasing it, with one diagnostic per site (devops's and web's concern).
>
> A new W code also stays clear of the W0603 clash (F1), so A does not wait on that bug.
>
> If A does not pass, my fallback is B.
>
> **Final: Q5.2 = B (holds). Q6 = A (moved from B), with conditions 1 and 2.**

##### DevOps/Tooling

> # DevOps/Tooling — Phase D debate (Q5.2, Q6)
>
> ## Q5.2 — I hold A, and I add evidence from the code
>
> Two facts from src/typecheck.bl settle the concerns that sys, plt and min each raised against their own option.
>
> 1. **The generic hint does NOT fire for `.sorted()` today.**
>    - `tc_suggest_method` (typecheck.bl:13974) sets the threshold to `len / 3`. For `sorted` that is 2.
>    - `levenshtein("sorted", "sort")` is 2.
>    - The guard `threshold <= 1 || best_dist < threshold` gives `2 < 2`, which is false.
>    - The fallback `tc_builtin_method_edit1` only accepts distance 1.
>
>    So under B, `xs.sorted()` gets a bare `UnresolvedMethod` with no help line. Min's concern ("may fall below its distance threshold and then say nothing") and sys's concern ("B gives no hint at all") are not risks. They describe today's output. Making B work means loosening a shared threshold, which adds false suggestions for every receiver. That is the wrong trade.
>
> 2. **The special-case table already exists.**
>    - `tc_list_rename_help` (typecheck.bl:12938) is a List-only table of names users bring from other languages.
>    - It already has two rows: `concat` → "list concatenation is `.append(other)`", and `collect` with a note on the two worlds of collections and iterators.
>    - Q5.2-A adds a third row to that table. It adds no new code path and no new rule.
>
>    The "special cases pile up" objection applies to a mechanism that the codebase has already adopted, with the same bar: a name from another language plus a note on meaning.
>
> PLT's suggestion ("the case needs a test, not a special rule") fits A: the row gets a test either way.
>
> ## Q6 — I hold A; if A has no majority, my vote goes to B. I will never vote C.
>
> To **sys** ("`reverse`/`append`/`slice` already ship with the trap, so blocking sort protects nothing"):
> - That argues for covering all of them now, which A does. It does not argue for waiting.
> - aiml's point stands: `xs.append(ys)` is the most likely no-op, because Python's `append` changes the list in place.
>
> To **min** ("a hand-picked list grows every release"):
> - Option A's scope is already a rule: every `Mutates = no` ListOps method that returns `List[T]`.
> - ListOps is sealed (fact 9), so the set grows only by a panel vote, and the method's table row then puts it in scope. Nothing is picked by hand.
>
> To **plt and min** ("fix F1 / the W-code space first"):
> - A uses a NEW code and touches W0603 not at all. It is the only option with no dependency on F1.
> - plt's own concern for B ("may stall on the W0603 clash and hold up `sort` indefinitely") is the cost that A avoids.
>
> To **everyone** ("the general 'discarded pure result' lint is the principled shape"):
> - I agree, and A does not prevent it.
> - My recorded concern still holds, and web's matches it: when the general lint lands, `DiscardedCopy` becomes its subset under one diagnostic per site.
> - The general lint needs purity-from-effect-row rules and its own scope vote. Under C, the known trap ships while that work waits. sys and min name that exact outcome as their concern for C.
>
> C is the only option where every panelist's stated concern is the expected outcome. I vote A, with B as my fallback.

##### AI/ML

> # AI/ML — Phase D debate (Q5.2, Q6)
>
> ## Q5.2 — holds at A
>
> The B side's own concerns make the case for A:
> - Sys: "if the generic hint does not exist yet, B gives no hint at all."
> - Min and plt: the distance threshold may miss `sorted` → `sort`. That is distance 2 on a 4-letter target, a relative distance of 50%, which most thresholds reject (Rust's own `did you mean` stays silent at that ratio).
>
> So B can easily mean silence on the single most predictable cross-language spelling. A test that pins the generic hint (plt's answer) would force the threshold up for every name, and that brings noisy suggestions everywhere else.
>
> The "ad-hoc surface" objection is fair, and web and devops already answered it with a bar: an entry needs a known spelling from another language **and** a semantic note. `.sorted()` → "Blink's `sort` already returns a new list" meets both. The note is the part that matters for AI. A generic hint fixes the token, and the model then writes `xs.sort()` as a statement and loses the result. That is the Q6 trap in a different form. The note heads it off.
>
> Synthesis I would accept, and it is still A in substance: the generic edit-distance engine plus a small curated table of known names from other languages, each entry carrying a required semantic note.
>
> ## Q6 — moves from A to B
>
> I move to my stated second choice. Plt's B takes what is right from both sides:
> - **From C:** the lint is defined by a rule ("discarded result of a pure, non-unit call"), not a hand-picked list. That was my own Phase C concern. The F1 clash is also settled before anything claims a code.
> - **From A:** `sort` does not ship with the trap unguarded.
>
> Answering C (sys, min):
> - **"`reverse`/`append`/`slice` already ship the trap, so blocking `sort` protects nothing."** This is true, but `sort` is not just another member of that list. It is the one method whose name, in Python, JS, Rust, Ruby (`sort!`), Java and C#, means mutate in place. It is the method an LLM will most often write as a bare statement. The existing trap in `append` is a reason to fix it soon, not a reason to add the most likely instance of it.
> - **"A warning does not change what `sort` means."** Also true, but it changes whether the first program a user writes with it is silently wrong. Both C voters name the same failure as their own concern: "deferred forever" and "goes stale". Blocking is what prevents that.
>
> Answering plt's concern about stalling: order the F1 bug first, then the lint, then the sort implementation. The lint on a sealed surface is small. The Q4 doc fixes remove the spec's own instances meanwhile, so the block costs nothing in docs.
>
> On devops's concern about overlap: under B there is only one lint (general, rule-based), so no `DiscardedCopy` subset fires next to a general lint later.
>
> **Final: Q5.2 A (holds), Q6 B (moved from A).**

##### Minimalism

> # Minimalism: Phase D debate (Q5.2, Q6)
>
> ## Q5.2: I move from B to A
>
> I checked the code before arguing further, and it changes my vote.
> - `tc_unresolved_method_help` (src/typecheck.bl:14015) already consults a per-receiver rename table, `tc_list_rename_help` (src/typecheck.bl:12938). It runs before the generic `tc_suggest_method` edit-distance pass.
> - That table already holds `concat` → "list concatenation is `.append(other)`" and `collect` → a note on the two worlds. Both are cross-language spellings with a semantic note attached, which is exactly the bar web, devops and aiml set.
> - My B vote assumed A meant inventing a special-case mechanism. It does not: A adds one row to a table that already exists. B would only avoid a row that fits a pattern the compiler already follows.
> - The generic hint also cannot say "returns a new list", and that missing sentence is the reason for the hint.
>
> Condition: the row goes in `tc_list_rename_help`, not in a new code path, and each table entry carries a semantic note (devops's bar). Sys and plt, the "one-off rule" worry is already answered by the existing table.
>
> ## Q6: I hold C. My ranking is C > B > A
>
> **To web, aiml and devops on A:**
> - Your trap evidence is real. But sys's point stands: `reverse`, `append` and `slice` already ship with the same trap today. By aiml's own account, `append` is the worse one. "Don't ship sort without the lint" protects one method out of four, so the trap is already in the field. What it shows is that the lint needs priority, not that it must block sort.
> - A names a list of methods, and aiml's and web's own concerns ask for the opposite: define it by rule, and let it become the general lint's subset later. A rule needs no list. Blink has effect rows, so "a call with an empty effect row returning a non-`Void` value, used as a statement" is decidable today without a separate purity analysis. One code, one rule, no per-release entries.
> - Devops: that rule is not hard enough to slip. It is easier to write than the list.
>
> **To plt on B:** your scope is right. Blocking on it ties sort to the F1 collision, and that is a stall you named yourself. Since the trap already ships through `reverse`/`append`, the block buys nothing for its cost.
>
> **What would move me:** a runoff between A and B. There I vote B, because the rule-based scope matters more to me than the ticket ordering. I keep the C concern from Phase C: the non-blocking ticket needs a set priority (P1) and must be ordered right after the F1 bug, so it cannot go stale.
>
> Final positions: **Q5.2: A** (moved). **Q6: C** (held; B in any runoff against A).

##### Re-vote

- **Q5.2: specific `.sorted()` hint** — 6-0 A (3-3 in Phase C). Sys, plt and min moved after sys and devops showed that the generic hint stays silent for `sorted` and that the hint table already exists.
- **Q6: separate lint ticket that blocks the `sort` implementation** — 6-0 B (3-1-2 in Phase C). Rankings: B > A > C (sys, web, plt, devops, aiml); B > C > A (min).
- **Q6-scope: S1** — 6-0. Min withdrew S2: mutation through `let mut` is not in the effect row, so S2 would warn on `xs.pop()` and `xs.remove(i)`.

##### Systems

> # Systems: Phase D vote (yv1sj1)
>
> **Q5.2: A**
> - **Reasoning:** Under the current threshold rule, the generic hint stays silent on `sorted` → `sort` (distance 2 is not below 2, src/typecheck.bl:13954), so B means no hint. Loosening that shared threshold would add false suggestions on every receiver. A adds one row to the `tc_list_rename_help` table that already exists, with a note about meaning, so it costs no new code path.
> - **Concern:** The table may gain rows that have no note about meaning. The bar (a cross-language spelling plus a note) has to hold in review.
>
> **Q6: B** (ranking: B > A > C)
> - **Reasoning:** `sort` is the method that Python, JS, Rust and Java habit writes as a bare statement, so the lint has to land before it ships. A blocking ticket keeps the rule out of this deliberation, where we cannot settle the W-code space. PLT's point that A avoids the F1 dependency is fair, so A is my close second. C ships the trap, and every C voter has named that as their own concern.
> - **Concern:** The blocking ticket could grow into general purity inference and stall `sort`. Its first cut must be S1 only, and the F1 bug must be ordered ahead of it.
>
> **Q6-scope: S1**
> - **Reasoning:** In Blink, mutation through `let mut` is not part of the effect row. Under S2, `xs.pop()` and `xs.remove(i)` as statements (empty effect row, non-`Void` return, result discarded on purpose) would warn. Those are common and correct uses, so S2 has false positives on day one. S1 reads a property the spec table already declares, needs no inference, and gives zero false positives on the sealed surface.
> - **Concern:** S1 does not cover user-defined pure functions. That is a deliberate gap, and a general lint can close it later once it can tell mutating methods apart from pure ones.

##### Web/Scripting

> # Web/Scripting — Phase D vote
>
> **Q5.2 — Vote: A**
> - **Reasoning:** Sys and DevOps showed from the code that the generic hint is silent on `.sorted()` today (threshold 2, distance 2, `2 < 2` fails). `tc_list_rename_help` already holds rows for `concat` and `collect`, each with a note on meaning, so A adds one row to a table that already exists. The note "Blink's `sort` already returns a new list" is the reason for the hint.
> - **Concern:** the table may gain rows without notes. Every row needs a cross-language spelling, a note on meaning, and a test.
>
> **Q6 — Vote: B. Ranking: B > A > C**
> - **Reasoning:** B defines the lint by a rule in its own ticket, fixes the W0603 clash first, and still stops `sort` from shipping with the trap. In Python, JS, Rust, Ruby, and Java, the name `sort` means sort in place, so `sort` is the method where migrants and LLMs will hit the trap most. A is close behind, because it also guards `sort`. C ships the trap, and both C voters name that outcome as their own concern.
> - **Concern:** the blocking ticket may grow into a purity-inference project and stall `sort`. Keep it to the S1 rule: order F1 first, then the lint, then sort.
>
> **Q6-scope — Vote: S1**
> - **Reasoning:** S2 fires on legitimate code. `xs.pop()` and `xs.remove(i)` as statements mutate the list and are often written only to drop an element. They have empty effect rows, so S2 warns on correct code, and a Python dev learns to ignore the warning. S1 derives the rule from the spec table (`Mutates = no` and returns the receiver's type). That gives it near-zero false positives, and new methods are covered with no new entry.
> - **Concern:** S1 misses discarded results of user fns and other pure calls. Track that wider lint as a follow-up, and it must absorb S1 with one diagnostic per site.

##### PLT

> # PLT — Phase D vote (yv1sj1)
>
> **Q5.2 — Vote: A** (moved from B)
> - **Reasoning:** Sys, devops and min checked the code, and their evidence beats my argument. Under today's `tc_suggest_method` threshold, `levenshtein("sorted", "sort") = 2` fails `2 < 2`, so B means silence, not a generic hint. A is not a new mechanism either: it adds one row to the existing `tc_list_rename_help` table, whose rows already carry semantic notes. My principle (one rule, no ad-hoc paths) is met by the table's entry bar.
> - **Concern:** The table's bar (a spelling from another language plus a semantic note) must be enforced in review, or it becomes a dumping ground.
>
> **Q6 — Vote: B.** Ranking: **B > A > C**
> - **Reasoning:** B was my Phase C position. Web, aiml and sys have now converged on it, and it carries both properties I care about: the lint is defined by a rule and lands after the F1 W0603 clash is fixed, and `sort` does not ship with the trap unguarded. I rank A above C because shipping the trap is worse than claiming a code early.
> - **Concern:** The blocking ticket may grow into purity inference and stall `sort`. Its first cut must be S1 only, ordered F1 bug → lint → sort.
>
> **Q6-scope — Vote: S1**
> - **Reasoning:** S2 is unsound as a "dead result" predicate in Blink. List/Map/Set are shared cells, and mutation through `let mut` is **not** in the effect row. So `xs.pop()`, `xs.remove(i)` and `m.remove(k)` used as statements have an empty effect row and a non-`Void` result, but they are legitimate and do work. S2 would warn on them, a false positive on correct code by construction. A call that may panic as validation is the same case. S1 keys on the declared `Mutates = no` column plus a receiver-typed return, which is exactly "this call's only output is its result". That is true by the spec, with no inference.
> - **Concern:** A later extension toward S2's generality must first add a mutation-aware purity judgement. Effect-row emptiness alone will never be the right predicate.

##### DevOps/Tooling

> # DevOps/Tooling — Phase D re-vote (yv1sj1)
>
> **Q5.2 — Vote: A**
> **Reasoning:** In the current compiler, the generic hint gives `.sorted()` no help line (`tc_suggest_method` threshold: `2 < 2` fails). The row belongs in the existing `tc_list_rename_help` table next to `concat` and `collect`, so it adds no new code path. On plt's point: a user who writes `let s = xs.sorted()` does already have the right model. The note still pays off on the next line they write, when Python habit turns `xs.sort()` into a statement. plt's "print the signature" idea is a good generic improvement, and it can come in addition to A, not in place of it.
> **Concern:** Without a written bar, the rename table grows rows that have no semantic note. Record the bar (a cross-language spelling plus a note on meaning) next to the table.
>
> **Q6 — Vote: B. Ranking: B > A > C**
> **Reasoning:** I move to my stated second choice. With S1 as the rule, B and A differ only in ordering and in who assigns the code. B still keeps the trap from shipping with `sort`, which was my whole case. Fixing F1 first is a small rename, so plt's stall risk is low as long as that bug ticket is ordered first. C ships the trap, and its own voters say so in their concerns.
> **Concern:** The blocking ticket grows into a general purity lint and stalls `sort`. Hold its first version to S1 and make any extension a non-blocking follow-up.
>
> **Q6-scope — Vote: S1**
> **Reasoning:** S2 gives false positives on correct idioms. Mutation is not an effect in Blink's rows, so `xs.pop()`, `items.remove(i)`, `m.remove(k)` and `seen.insert(x)` (03_types.md:364-367, 436, 486-487) all have empty effect rows and non-`Void` returns. Each one is a normal statement that discards a value on purpose. A default-on lint that fires on `xs.pop()` gets disabled, and then it catches nothing. S1 reads the `Mutates = no` column of the spec table, so it needs no inference and has near-zero false positives. A later general lint can extend it.
> **Concern:** S1 skips user functions and copy-returning methods outside ListOps. Users may read "no warning" as "the result was used", so the explain text must state the scope.

##### AI/ML

> # AI/ML — Phase D vote (yv1sj1)
>
> **Q5.2 — Vote: A**
> - **Reasoning:** Sys and devops checked the code. `tc_suggest_method` rejects `sorted` → `sort` (2 < 2 fails), so under B a model that writes `.sorted()` gets a bare `UnresolvedMethod` and nothing to repair from. A adds one row to the existing `tc_list_rename_help` table, next to `concat` and `collect`. The row's note, "`sort` already returns a new list", also stops the next mistake, `xs.sort()` as a statement.
> - **Concern:** The table could take rows without a semantic note. Keep the bar: a spelling from another language plus a note on meaning, and each row gets a test.
>
> **Q6 — Vote: B. Ranking: B > A > C**
> - **Reasoning:** B makes sure `sort` does not ship with the trap, and it keeps the rule in its own ticket after the F1 clash is fixed. Every panelist except min ranks B first or second, so it is the option no one rejects. A with S1 scope would deliver the same result for AI users, so it is a close second. C is last because every C voter names "the ticket goes stale while the trap ships" as their own concern.
> - **Concern:** The blocking ticket could grow into purity inference and stall `sort`. Keep its first cut to S1 and order it directly after the F1 bug.
>
> **Q6-scope — Vote: S1**
> - **Reasoning:** S2 fires on legitimate discards. `xs.pop()`, `xs.remove(i)` and a value-returning `insert` all have an empty effect row and a non-`Void` return. Discarding their result as a statement is normal, so every such line would be a false positive. A lint that fires on correct code teaches models and users to ignore it or wrap it in `let _ =`, and that destroys the signal. S1 reads the `Mutates = no` column and the receiver-type return straight from the spec table: no purity inference and no name list, and any new sealed method is covered by its own table row.
> - **Concern:** S1 misses user-defined copy-returning methods. Record that as a known gap for the later general lint, which must absorb this code with one diagnostic per site.

##### Minimalism

> # Minimalism: Phase D vote
>
> ## Q5.2: A
> - **Reasoning:** Sys and devops showed that under B, `.sorted()` gets no hint at all today. `tc_suggest_method` sets the threshold at `len / 3`, and the guard `2 < 2` fails. The `edit1` fallback only accepts distance 1. A adds one row to the existing `tc_list_rename_help` table, so it needs no new mechanism. Widening the shared threshold would be the bigger change.
> - **Concern:** The table grows past the bar. Each row must be a name from another language with a semantic note and a test.
>
> ## Q6: B. Ranking: B > C > A
> - **Reasoning:** I move from C. My own Phase C concern for C was that the lint gets deferred forever, and web, aiml and sys now all agree. B is the only option that keeps a rule-defined, single lint and still keeps the trap from shipping with `sort`. A claims a code inside a sort ticket while the W-code space is broken (F1). Even when defined by a rule, it risks the `DiscardedCopy`-plus-general-lint overlap that devops and web both flagged.
> - **Concern:** The block stalls `sort`. Order the F1 bug first, and keep the blocking lint to the S1 rule so no purity work lands on the critical path.
>
> ## Q6-scope: S1
> - **Reasoning:** I withdraw S2. It is wrong:
>   - `xs.pop()` and `xs.remove(i)` have empty effect rows and non-`Void` results.
>   - Writing them as statements is a correct and common way to drop an element.
>   - So S2 would warn on correct code.
> - S1 keys off the spec's own `Mutates = no` column and the "returns the receiver's type" property. That is a declared fact from the signature, with no purity inference and no name list, and it covers future sealed methods with no new entry.
> - **Concern:** S1 covers only sealed built-ins. The general "discarded pure result" lint for user functions still needs its own later ticket, and it must absorb S1 so each site gets one diagnostic.

### Final Spec

```blink
trait ListOps[T] {
    // ...
    // Transformation (returns new list)
    fn append(self, other: List[T]) -> List[T]
    fn slice(self, start: Int, end: Int) -> List[T]
    fn reverse(self) -> List[T]
    fn sort(self) -> List[T]                                        // T: Ord
    fn sort_by(self, cmp: fn(T, T) -> Ordering ! _) -> List[T] ! _
}

let by_age = people.sort_by(fn(a, b) { a.age.cmp(b.age) })        // ties keep input order
let oldest_first = people.sort_by(fn(a, b) { b.age.cmp(a.age) })  // descending: swap arguments
let names = scores.keys().sort()                                  // a new list; not `.sorted()`
```

- `sort` and `sort_by` return a sorted copy and are **stable**. There is no unstable sort.
- `xs.sort()` gives the same result as `xs.sort_by(fn(a, b) { a.cmp(b) })`. `sort_by` needs no bound on `T`.
- The comparator returns `Ordering`, may have effects (`! _`), and is called an unspecified number of times in an unspecified order. If it does not return, the receiver is unchanged.
- **Ord laws** (03_types.md §3.6, beside the Eq laws): `Ord.cmp` is a total order that agrees with `Eq`. A `sort_by` comparator need only be a total preorder. If a law is broken, the sort terminates and returns a permutation of the input in an unspecified order. It stays memory-safe and does not panic.
- No `sort_by_key` in v1. It can be added later without a break.
- `.sorted()` does not exist. All spec and decision-record sites now read `.sort()`, and the edited records carry an erratum note. W1401 counts `sort_by` as a sort.
- Diagnostics: the missing-`Ord` help suggests `sort_by`. `.sorted()` gets a row in the List rename-help table that says `sort` already returns a new list. Each row in that table needs a cross-language spelling, a note on meaning, and a test.
- A discarded-copy lint lands before `sort` ships, in its own ticket. It fires on a call used as a statement to a sealed built-in method with `Mutates = no` that returns the receiver's type. The W0603 name clash is fixed first. A later general "discarded pure result" lint must absorb it, with one diagnostic per site.
