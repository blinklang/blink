[< All Decisions](../DECISIONS.md)

# Ord, Clone and JSON for Option and Result — Design Rationale

**Gap:** `Option` and `Result` had `Eq` but no `Ord` and no `Clone`, and the spec did not say how they encode in JSON. A sort over `List[Option[Int]]` and `.clone()` on a `Result` did not compile. `Option[T]` had a `Serialize` row but no decode rule, and `Result` had no row at all.

**Result:**

- **Q1 (6-0, O1):** `Option[T]` is `Ord` when `T: Ord`. `Result[T, E]` is `Ord` when `T: Ord` and `E: Ord`. Compare the variant first, then the payload. `None < Some(_)` and `Ok(_) < Err(_)`.
- **Q2 (5-1, D1):** reorder the `Option` declaration to `None` then `Some(T)`, and state both orders in words in §3.6. Minimalism dissents for D2 (reorder only, with one example line).
- **Q3 (6-0, C1):** `Option[T]` is `Clone` when `T: Clone`. `Result[T, E]` is `Clone` when `T: Clone` and `E: Clone`. The payload's own `clone` runs, so `x.clone()` gives the same value as `let y = x`, and a shared cell inside stays shared.
- **Q4 (6-0, P4):** one rule sentence: `Option` and `Result` have the instances `@derive` gives a user sum type with the same variants, for `Eq`, `Ord`, `Clone` and `Debug`, with inferred bounds. The per-trait text names them too. JSON has its own rows.
- **Q5 (6-0, J1):** `Option[T]` is `Deserialize` when `T` is. `null` decodes as `None`. Any other value decodes as `T` wrapped in `Some`.
- **Q6 (6-0, N2e):** the instance stays parametric. The round-trip law has an exception for `Some(v)` where `v.to_json()` is `null`. `@derive(Serialize)` or `@derive(Deserialize)` on a field with declared type `Option[Option[T]]` (after alias expansion, before generic substitution) is E1401. Phase C was 4-1-1 (Systems N2w, Minimalism N2). Both moved to N2e in Phase D.
- **Q7 (4-2, R1):** `Result` has no JSON form in v1. A `Result` field under `@derive(Serialize)` or `@derive(Deserialize)` is E1401, and the `help:` writes the full enum. Phase C was 3-3. Phase D moved Systems and PLT from R2 to R1 and AI/ML from R1 to R2s. Web and AI/ML dissent for R2s.

**AI-first review:** 5/5 pass, 0 fails. Learnability: one rule, "as `@derive` gives a user sum type". Consistency: the same order and bounds as `@derive` on a user sum type. Generability: a model can write `xs.sort()` and `r.clone()` and expects them to compile. Debuggability: the E1401 `help:` writes the enum to use. Token efficiency: no new syntax and no new trait.

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in independent-proposal, debate, vote and re-vote rounds. Each panelist's text below is a verbatim excerpt of the panelist's own reply. A line that ends with `[...]` shows where the excerpt stops.

#### Phase A — Independent proposals

- **Systems:**

> # sys — Phase A
>
> Frame: Option and Result are compiler-known carriers. layout.bl lowers each to a by-value C struct (a tag plus the payload; a large Option payload by pointer). Every impl below is monomorphized per instantiation. None of them adds an allocation, a vtable or a runtime type test. So the question is not about cost. It is about which order and which wire shape we lock in.
>
> ## sys-1 — Conditional Ord, fixed variant order: `None < Some(_)`, `Ok(_) < Err(_)`
>
> - `Option[T]: Ord` when `T: Ord`. `None` is less than every `Some(v)`. Two `Some` values compare by `T.cmp` on the payloads.
> - `Result[T, E]: Ord` when `T: Ord` and `E: Ord`. Every `Ok(v)` is less than every `Err(e)`. Two `Ok` values compare by `T.cmp`, two `Err` values by `E.cmp`.
> - This is the derived sum-type rule (F6: variant index first, then payload), with the variant index set by the spec, not by a declaration.
>
> ```blink
> fn pick(a: Option[Int], b: Option[Int]) -> Option[Int] {
>     if a < b { b } else { a }
> }
>
> fn main() {
>     let xs = [Some(3), None, Some(1)].sort()
>     io.println("{xs.debug()}")          // [None, Some(1), Some(3)]
>     let rs: List[Result[Int, Str]] = [Err("b"), Ok(2), Err("a"), Ok(1)]
>     io.println("{rs.sort().debug()}")   // [Ok(1), Ok(2), Err("a"), Err("b")]
> }
> ```
>
> What it compiles to, for `Option[Int]`:
>
> ```c
> static int64_t cmp_opt_int(blink_Option_int a, blink_Option_int b) {
>     if (a.tag != b.tag) return a.tag == TAG_NONE ? -1 : 1;
>     if (a.tag == TAG_NONE) return 0;
>     return (a.val > b.val) - (a.val < b.val);
> }
> ```
>
> One tag compare, then the payload compare. gcc -O2 makes this branch-free for scalar payloads.
>
> **The trap.** §7.3 (05_memory_compile_errors.md:727) lists `Option` as `Some(T)` then `None`. If we said "Option is Ord by declaration order", we would get `Some(_) < None`. That is the opposite of Rust (`None < Some`), Haskell (`Nothing < Just`) and OCaml's `compare` (a constant constructor sorts before a block). Code ported from those languages, and every LLM trained on them, expects `None` first. So the spec must **state** the order in the container paragraph. It must not inherit it from F6. I also propose to reorder the §7.3 listing to `None`, then `Some(T)`, so that the listing and the order never disagree. Variant listing order has no other meaning for a compiler-known type (the C tag value is an implementation detail and stays out of the spec).
>
> [...]

- **Web/Scripting:**

>
> My test for each question: a JS, TS, Python or Kotlin developer writes the obvious code. Does it compile, and does it do what they expect without a trip to the docs? Today the answer is "no" three times (F13): `a < b`, `.clone()` and `@derive(Serialize)` on a struct with an `Option` field all fail. The last one contradicts our own table. That is the first thing a web developer hits, because every API payload has optional fields.
>
> ---
>
> ## web-1 — Conditional Ord and Clone for Option and Result, with each order stated outright
>
> **Rule.**
> - `Option[T]` is `Ord` when `T: Ord`. `None` is less than every `Some(v)`. Two `Some` values compare by their payloads.
> - `Result[T, E]` is `Ord` when `T: Ord` and `E: Ord`. Every `Ok(v)` is less than every `Err(e)`. Two `Ok` values compare by `T`; two `Err` values compare by `E`.
> - `Option[T]` is `Clone` when `T: Clone`; `Result[T, E]` when `T: Clone` and `E: Clone`. The clone has the same variant and a clone of the payload, the same as tuple element-wise clone (F5). A shared-cell payload (`List`, `Map`, `Set`) shares its cell, as F8 already says.
> - Add these rows next to the F1 Container Equality list, so a reader finds Eq, Ord and Clone for each container in one place.
>
> ```blink
> fn f(a: Result[Int, Str], b: Result[Int, Str]) -> Bool {
>     let c = a.clone()
>     a < b
> }
>
> fn latest(xs: List[Option[Int]]) -> List[Option[Int]] {
>     let mut ys = xs.clone()
>     ys.sort()
>     ys
> }
>
> test "None sorts first" {
>     assert(None < Some(0))
>     assert(Some(1) < Some(2))
>     assert(Ok(9) < Err("x"))
> }
> ```
>
> **Why `None < Some`, stated outright and not "by declaration order".** §7.2 declares `Some(T)` first and `None` second. If we let F6 (declaration order) decide, `Some(5) < None`. No developer I know expects that:
> - Rust: `None < Some(_)`. Haskell: `Nothing < Just _`. Kotlin `compareValues` and `nullsFirst()`: null is less. Python 2 put `None` below every value, and that is still what people mean when they say "sort with missing values first".
> - Spreadsheets, `Array.prototype.sort` with a typical comparator, and most ORMs put missing values at one end. "Absent is smallest" is the rule people can say back in one sentence.
>
> So the spec must name the order in a sentence. It must not fall out of the order of a declaration that a reader never sees (F11: Option is compiler-known, not a user enum). Either reorder the §7.2 listing to `None` first, or add one sentence: "This order does not follow the listing in §7.2." I prefer reordering the listing; one fewer exception to explain.
>
> [...]

- **PLT:**

> # plt — Phase A
>
> ## Framing: one rule, not three lists
>
> The spec already gives Option and Result conditional `Eq` and `Debug` (F1, F2), and tuples get the full structural set (F5). The sound, compositional fix is to state one principle and derive every answer from it, not to add rows one trait at a time:
>
> > **P.** `Option[T]` and `Result[T, E]` have the instances that `@derive` would give a user sum type with the same variants, with the bounds that *Generic Type Bound Inference* would infer, for `Eq`, `Ord`, `Clone`, `Debug`, `Serialize` and `Deserialize`. `Hash` stays excluded (F7). Where this spec states a different behavior for one of these types (the `Option` JSON mapping), that statement wins, and it is the only exception.
>
> Typing rules this gives (instance heads; `C` ranges over Eq, Ord, Clone, Debug, Serialize, Deserialize):
>
> ```
> T : C            ⊢  Option[T]    : C
> T : C,  E : C    ⊢  Result[T, E] : C
> ```
>
> These are the same shape as the tuple rule (`T1 : C … Tn : C ⊢ (T1, …, Tn) : C`). Instance resolution stays syntax-directed and parametric: no instance looks at what `T` is, only at whether `T : C` holds. This matters for JSON below.
>
> ---
>
> ## plt-1 — `Ord` for Option and Result: lexicographic by variant, `None` first
>
> `Option[T]: Ord` when `T: Ord`. `Result[T, E]: Ord` when `T: Ord` and `E: Ord`. The order is the derived sum-type order (F6): variant index first, then the payload.
>
> - `Result`: `Ok(_) < Err(_)`; `Ok(a).cmp(Ok(b)) == a.cmp(b)`; `Err(a).cmp(Err(b)) == a.cmp(b)`.
> - `Option`: **`None < Some(_)`**; `Some(a).cmp(Some(b)) == a.cmp(b)`.
>
> ```blink
> fn pick(a: Result[Int, Str], b: Result[Int, Str]) -> Bool {
>     let c = a.clone()
>     a < b
> }
>
> fn main() {
>     let xs = [Some(2), None, Some(1)].sort()        // [None, Some(1), Some(2)]
>     let best = if Some(3) > None { "value wins" } else { "absence wins" }   // "value wins"
>     let lt = Ok(9) < Err("x")                       // true: Ok before Err
>     let t = (Some(1), 0) < (Some(1), 5)             // true: tuple of Ord is Ord
> }
> ```
>
> **The `None` order needs one edit.** The §5 declaration lists `Some(T)` then `None` (05:727). Under F6 that gives `Some(_) < None`. I propose the opposite, and to keep P a single rule I propose that the §5 declaration be reordered to `None` then `Some(T)`, so the declaration-order rule *gives* `None < Some`. No other behavior depends on that order: `Option` has a payload, so it has no `to_int()`, and the tag layout is codegen, not spec.
>
> Why `None` first:
>
> [...]

- **DevOps/Tooling:**

> # devops — Phase A
>
> My lens: each answer must give one rule a user can predict, and one diagnostic that names the real cause. Today a user who writes `a < b` on two `Result` values gets "does not implement Ord" with no reason, and `.clone()` gets UnresolvedMethod, which reads as "this method does not exist anywhere". Both are bad error surfaces. The spec fix must also give the checker one way to peel a container, the same way E0520 already does for Debug.
>
> ## devops-1 — Conditional Ord for Option and Result, order stated, not inferred
>
> - `Option[T]` is `Ord` when `T: Ord`. **`None` is less than every `Some(_)`.** Two `Some` compare by payload.
> - `Result[T, E]` is `Ord` when `T: Ord` and `E: Ord`. **Every `Ok(_)` is less than every `Err(_)`.** Two `Ok` compare by the `T` payload, two `Err` by the `E` payload.
> - The spec states both orders in words. It does not say "derived order", for this reason: §7.3 declares `Option` as `Some(T)` then `None`. Under the F6 rule (variant index first), declaration order gives `Some(_) < None`. That is the opposite of Rust, Haskell (`Nothing < Just`), OCaml `compare` and SQL `NULLS FIRST`. If the spec only says "Option orders like a derived enum", a reader who checks §7.3 gets the wrong answer, and an LSP hover that prints the declaration teaches it. So the spec sentence must fix `None < Some` directly, and note that it is not the declaration order. `Result`'s declaration order (`Ok` then `Err`) agrees with the rule, and with Rust.
> - Consequence: a tuple or a `@derive(Ord)` struct that holds an `Int?` field becomes `Ord`, and `List.sort` works on `List[Int?]`.
>
> ```blink
> @derive(Eq, Ord)
> type Row {
>     id: Int
>     score: Int?
> }
>
> fn rank(rows: List[Row]) -> List[Row] {
>     rows.sort()
> }
>
> fn worse(a: Result[Int, Str], b: Result[Int, Str]) -> Bool {
>     a < b
> }
> ```
>
> **Diagnostic surface.** When the bound fails, the error peels the container and names the type argument that lacks `Ord`, as E0520 does for Debug:
>
> ```
> error[E0306]: binary `<` needs Ord, and Result[Int, Blob] does not implement Ord
>   --> app.bl:4:5
>    |
>  4 |     a < b
>    |     ^^^^^
>    = note: Result[T, E] is Ord only when T: Ord and E: Ord; Blob is not Ord
>    = help: add `@derive(Ord)` to `type Blob` (app.bl:1)
> ```
>
> The same peeling applies to `@derive(Ord)` (E1401 NonDerivableTrait): a struct field of type `Blob?` names `Blob`, not `Option`. LSP hover on `<` lists the impl as `impl[T: Ord] Ord for Option[T]`. The checker needs no new code path: the Eq peeling (F1) already walks the same type arguments.
>
> [...]

- **AI/ML:**

>
> My lens: the fewest new facts a model must learn from the spec. Today the spec makes a model learn
> "Option and Result have Eq and Debug, but not Ord, Clone or Serialize" — a hole that no other
> language has. Every model trained on Rust, Haskell, OCaml or Swift writes `a < b` on two Options and
> `.clone()` on a Result without thinking. Each of those lines fails today (F13). The cheapest rule to
> learn is one sentence: **"Option and Result behave as if declared with `@derive(Eq, Ord, Clone,
> Debug, Serialize, Deserialize)`, with the bounds that derive infers."** Then every trait follows from
> rules the model already learned for user enums (F6, F8, F9). Only exceptions need extra text, and I
> keep those to two.
>
> ---
>
> ## aiml-1 — Conditional Ord: "as derived", with a fixed variant order
>
> Rule: `Option[T]` is `Ord` when `T: Ord`. `Result[T, E]` is `Ord` when `T: Ord` and `E: Ord`. The
> order is the derived sum-type order (F6): variant index first, then the payload. The spec states the
> variant order in words, so it does not hang on a declaration that the reader never sees:
>
> - `None < Some(_)` for every payload. Two `Some` compare by payload.
> - `Ok(_) < Err(_)` for every payload. Two `Ok` (or two `Err`) compare by payload.
>
> ```blink
> fn first_missing(xs: List[Int?]) -> List[Int?] {
>     xs.sort()                       // [None, None, Some(1), Some(4)]
> }
>
> fn worse(a: Result[Int, Str], b: Result[Int, Str]) -> Result[Int, Str] {
>     if a < b { b } else { a }       // any Err is greater than any Ok
> }
>
> test "option order" {
>     let none: Int? = None
>     assert(none < Some(0))
>     assert(Some(1) < Some(2))
> }
> ```
>
> Consequence that must be in the text: §7.2 declares `type Option[T] { Some(T) None }`, with `Some`
> first (05_memory_compile_errors.md:727). Read with the derived rule, that gives `Some(_) < None`, the
> reverse of Rust (`None < Some`), Haskell (`Nothing < Just`) and OCaml. Fix the illustrative
> declaration to put `None` first, and state the order in §3.6 next to Container Equality. A model
> that sorts `List[Int?]` will expect `None` first; it must not be wrong in one language only.
> `Result` already declares `Ok` first, which matches Rust (`Ok < Err`).
>
> Tradeoffs (aiml):
> - (+) Zero new rule: the derived-Ord rule, which a model already must learn, covers it.
> - (+) Fixes a tuple holding an Option, and `@derive(Ord)` on a struct with an Option field (F13), at
>   no extra text cost.
> - (+) Matches the order in every training-data language that orders these types.
>
> [...]

- **Minimalism:**

> # min — Phase A
>
> My lens: add no new rule where an existing one already gives the answer. `Option` and `Result` have a written declaration in the spec (05_memory_compile_errors.md:651 and :727):
>
> ```blink
> type Result[T, E] {
>     Ok(T)
>     Err(E)
> }
>
> type Option[T] {
>     Some(T)
>     None
> }
> ```
>
> The spec already has a full rule for derived instances on a two-variant sum type (03:5437, variant index first, then fields; 03:4906-4913 for Clone). Today `Option` and `Result` sit outside that rule only because they are compiler-known (F11). The smallest fix is one sentence that puts them back inside it, not a new table row per trait.
>
> ---
>
> ## min-1 — "Option and Result derive as declared" (Ord + Clone)
>
> Add one sentence to §3.6, next to *Container Equality*:
>
> > `Option[T]` and `Result[T, E]` implement `Ord` and `Clone` as if their declarations (§7.2, §7.3) carried `@derive(Ord, Clone)`, with the inferred bounds: `Option[T]` when `T` does, `Result[T, E]` when `T` and `E` do.
>
> What follows, with no further text:
>
> ```blink
> fn f(a: Result[Int, Str], b: Result[Int, Str]) -> Bool {
>     let c = a.clone()           // ok: Int: Clone, Str: Clone
>     a < b                       // ok: Ok(_) < Err(_); Ok(1) < Ok(2); Err("a") < Err("b")
> }
>
> fn g() -> List[Int?] {
>     let xs = [None, Some(2), Some(1)]
>     xs.sort()                   // [Some(1), Some(2), None]
> }
>
> @derive(Ord, Clone)
> type Row {
>     id: Int
>     score: Int?                 // now legal: Option[Int]: Ord
> }
> ```
>
> - Clone: same as `let y = x` for the payload, as for every other value (F8). No new semantics.
> - Ord: variant index first, then payload (F6). The tuple-holding-an-Option case (F13) fixes itself through the tuple rule (F5).
>
> **The one real decision point: `Some < None`.** Declaration order puts `Some` first, so ascending sort puts `None` last. Rust (`None < Some`), Haskell (`Nothing < Just`) and OCaml `compare` go the other way. I still prefer declaration order:
>
> - It needs zero new text. "None sorts first" would be a special case that a reader must learn on top of the fieldless-enum rule (03:4356), and the only one of its kind.
> - "Missing values last" is the PostgreSQL `ASC NULLS LAST` default, so the choice has precedent that users see often.
> - If the panel wants `None < Some`, the honest fix is to swap the declaration order in §7.3 (`None` then `Some`), not to add an exception. Then the rule stays "derive as declared". Either order is fine with me; an exception is not.
>
> [...]

#### Phase B highlights

The first debate round found no shared answer on `Option[Option[T]]` and on `Result` JSON. Web closed its reply with `STATUS: not ready`. Key shifts, quoted from the replies:

- **Web/Scripting:**

> **`Option[Option[T]]`: I move from N1 to "N2 plus a derive error".** PLT is right, and I checked the evidence: the template-hole rule (03:5256) is a check over a *closed, concrete list* of hole types, not an instance. It is not a precedent for a negative bound. With N1 as written, this does not compile:
>
> STATUS: not ready — Result JSON (R1 vs R2) is a real split; `Option[Option[T]]` needs plt and devops to answer on "parametric instance + derive-time error" before a vote.

- **Systems:**

> - **N1 vs N2: I change from N1 to N2.** plt's argument is decisive from my seat, for a reason plt did not state: N1 is an instance condition that only a monomorphized type can check. `fn f[T: Serialize](x: Option[T]) -> JsonValue { x.to_json() }` typechecks, and then `f[Option[Int]]` must fail. Where? Either at mono time (a post-typecheck error in a generic body, the C++ template failure mode, which I want Blink never to have), or by a negative bound users cannot write. Both are worse than the loss they prevent.

- **DevOps/Tooling:**

> **`Option[Option[T]]`: I change my position, from N1 to a combination of N2 and a derive-site check.** plt has two points I cannot answer under N1:

- **AI/ML:**

> ## Option JSON — I move from N1 to N2 plus a derive-site check
>
> ## Result JSON — I move from R3 to R1

- **Minimalism:**

> ## Option JSON — I change my vote on `Option[Option[T]]`: N2, not N1

#### Phase C — Silent vote

Each seat voted alone on seven questions. Tallies:

- **Q1: Ord** — Systems O1, Web/Scripting O1, PLT O1, DevOps/Tooling O1, AI/ML O1, Minimalism O1.
- **Q2: How the Option order is fixed** — Systems D1, Web/Scripting D1, PLT D1, DevOps/Tooling D1, AI/ML D1, Minimalism D2.
- **Q3: Clone** — Systems C1, Web/Scripting C1, PLT C1, DevOps/Tooling C1, AI/ML C1, Minimalism C1.
- **Q4: Framing** — Systems P4, Web/Scripting P4, PLT P4, DevOps/Tooling P4, AI/ML P4, Minimalism P4.
- **Q5: Option decode** — Systems J1, Web/Scripting J1, PLT J1, DevOps/Tooling J1, AI/ML J1, Minimalism J1.
- **Q6: `Option[Option[T]]` in JSON** — Systems N2w, Web/Scripting N2e, PLT N2e, DevOps/Tooling N2e, AI/ML N2e, Minimalism N2.
- **Q7: Result JSON** — Systems R2, Web/Scripting R2, PLT R2, DevOps/Tooling R1, AI/ML R1, Minimalism R1.

Phase C results: Q1 O1 6-0. Q2 D1 5-1 (Minimalism dissent: D2). Q3 C1 6-0. Q4 P4 6-0. Q5 J1 6-0. Q6 N2e 4, N2w 1, N2 1 (4-1-1). Q7 R1 3, R2 3 (3-3). Q6 and Q7 went to Phase D.

##### Q1: Ord

<details>
<summary>Systems — O1</summary>

> **Vote:** O1
> **Reasoning:** Each instance monomorphizes to one tag compare, then the payload's `cmp`: no allocation, no dispatch, branch-free for scalar payloads at -O2. Dropping Ord from Result (O2) saves nothing at runtime and breaks tuple Ord and `@derive(Ord)` on any struct with a Result field. `None` first is the lifted order and matches Rust, Haskell and OCaml.
> **Concern:** The bound on both parameters means `Result[T, E]` with an unordered `E` cannot sort even when every value is `Ok`, and users will file that as a bug.

</details>

<details>
<summary>Web/Scripting — O1</summary>

> **Vote:** O1
> **Reasoning:** Sorting a list of optional dates or scores, and `@derive(Ord)` on a struct with an optional or `Result` field, are everyday code. A hole for `Result` alone would make a struct underivable for no reason a user can guess. `None < Some` makes `max` return a value when one exists, which is what every JS/Python/Kotlin developer expects.
> **Concern:** A user who wants "nulls last" may not know to reach for `sort_by`, so the docs need one example of it.

</details>

<details>
<summary>PLT — O1</summary>

> **Q1. Ord — Vote: O1**
> Reasoning: The lexicographic sum order over total orders that agree with `Eq` is itself total and agrees with the F1 `Eq`, so the §3.6 Ord laws hold with no extra condition. O2 removes a lawful instance for no type-theoretic reason, and it makes `@derive(Ord)` and the tuple rule fail on one type. `None < Some` is the lifted order `T⊥`, so `None` is the bottom.
> Concern: `Result[T, E]: Ord` needs `E: Ord` even when a program compares only `Ok` values; a user may read that as too strict, but any weaker bound would make the instance depend on values, not on types.

</details>

<details>
<summary>DevOps/Tooling — O1</summary>

> **Vote:** O1
> **Reasoning:** With O1, a struct or tuple that holds a `Result` derives `Ord` and sorts. O2 adds a hole that the user meets only as an E1401 deep inside a derive, with no clear reason. `None < Some` keeps `max` from returning `None`, which is a wrong answer that no diagnostic can catch. Every reference language uses these two orders.
> **Concern:** The bound error for `Result[T, E]` must peel the type and name which argument lacks `Ord` (as E0520 does for Debug); if it only says "Result does not implement Ord", users will read it as "Result is never Ord".

</details>

<details>
<summary>AI/ML — O1</summary>

> **Vote:** O1
> **Reasoning:** Every training-data language that orders these types (Rust, Haskell, OCaml) gives conditional Ord with `None` first, so a model writes `a < b` and `xs.sort()` on them without checking. O2 would add a "Result is the exception" fact and block `@derive(Ord)` on any struct with a Result field. O1 adds no fact beyond the derived sum-type rule.
> **Concern:** `Ok < Err` means "errors sort last", and a model trained on Haskell's `Either` (`Left` first) could guess the reverse in a hand-written comparator.

</details>

<details>
<summary>Minimalism — O1</summary>

> **Vote:** O1
> **Reasoning:** Option and Result are two-variant sum types, and the spec already has a full rule for ordering those. O2 would be an exception to that rule, and a struct with a `Result` field could then not `@derive(Ord)`. Subtraction that adds exceptions is not subtraction.
> **Concern:** `Ok(_) < Err(_)` is arbitrary, and a user who sorts results may expect errors first; the example line must show it.

</details>

##### Q2: How the Option order is fixed

<details>
<summary>Systems — D1</summary>

> **Vote:** D1
> **Reasoning:** The order must be findable where a reader looks for it, the §3.6 container paragraph, not only as a side effect of a listing in §5. Stated in both places, the two agree by construction. A later edit to the §5 listing can then not change the order without a visible conflict.
> **Concern:** Two statements of one rule can drift if a later amendment edits one and not the other.

</details>

<details>
<summary>Web/Scripting — D1</summary>

> **Vote:** D1
> **Reasoning:** People look up "how do Options sort" in §3.6, not in §7.2. A one-line statement saves them from applying the derive rule in their head. Once the declaration is reordered, that sentence restates a fact; it adds no exception.
> **Concern:** The sentence and the declaration can drift apart in a later edit unless a test pins both.

</details>

<details>
<summary>PLT — D1</summary>

> **Q2. How the Option order is fixed — Vote: D1**
> Reasoning: The reorder keeps one rule (the derived order from the declaration), so the words in §3.6 restate that rule and add no exception. The words are needed because Option is compiler-known (F11), and a reader or an LSP hover may never see the §7.3 listing. D2 leaves the order implicit in an example, and a spec must state a law, not imply it.
> Concern: A later edit to one of the two places (listing or §3.6 words) without the other would bring back the conflict; the per-module invariant check or a review rule should tie them together.

</details>

<details>
<summary>DevOps/Tooling — D1</summary>

> **Vote:** D1
> **Reasoning:** The reorder makes the rule "derive as declared" exact, with no exception. The sentence in words is for lookup: docs, `blink llms --topic` and search results must give the order directly, and a reader should not need to apply the variant-index rule to a declaration in §7.3. The sentence restates the rule; it does not add one.
> **Concern:** The sentence and the declaration can drift apart later; a spec lint or a corpus test that sorts `[Some(1), None]` should pin the order.

</details>

<details>
<summary>AI/ML — D1</summary>

> **Vote:** D1
> **Reasoning:** Models read Blink docs by topic retrieval, so the answer to "how does Option order?" must sit in one chunk in §3.6, not depend on joining it with a declaration in §7.2. An example line alone teaches by inference, and a model can misread one example. The reordered declaration keeps the two texts from disagreeing.
> **Concern:** Two statements of one fact can drift apart in a later edit; the spec owner must keep them in sync.

</details>

<details>
<summary>Minimalism — D2 (dissent)</summary>

> **Vote:** D2
> **Reasoning:** With `None` declared first, the existing declaration-order and derived-sum rules give the order with no new text. A separate statement in §3.6 makes two normative sources for one fact, and the next edit to §7.3 for teaching order will make them disagree. One example line shows the result without becoming a second rule.
> **Concern:** If D1 wins, the §3.6 sentence and the §7.3 declaration can drift apart, so the spec must say which one governs.

</details>

##### Q3: Clone

<details>
<summary>Systems — C1</summary>

> **Vote:** C1
> **Reasoning:** The payload's own `clone` runs, so a hand-written `impl Clone` is honoured, and for every built-in payload the call inlines to a struct copy. The conditional bound keeps `T: Clone` meaningful under substitution, the same as tuples.
> **Concern:** A reader may take "the payload's `clone` runs" to mean a deep copy, unless the text says at once that a shared cell stays shared.

</details>

<details>
<summary>Web/Scripting — C1</summary>

> **Vote:** C1
> **Reasoning:** `.clone()` that fails only on Option and Result is a "the compiler is broken" moment. Same value as `let y = x` adds no new meaning to learn. The conditional bound keeps `T: Clone` honest for handle types.
> **Concern:** Users from JS may read `clone()` as a deep copy and be surprised that a `List` inside stays shared; the F8 text must stay easy to find.

</details>

<details>
<summary>PLT — C1</summary>

> **Q3. Clone — Vote: C1**
> Reasoning: The conditional bound keeps `T: Clone` meaningful under substitution: an unconditional instance would let `Some(h)` be copied when `h`'s type has no `Clone`. Running the payload's own `clone` respects a hand-written impl, and it is exactly the tuple rule (F5).
> Concern: Users may expect a deep copy of a `List` inside a `Some`; the Clone Semantics text must name Option and Result next to the shared-cell sentence.

</details>

<details>
<summary>DevOps/Tooling — C1</summary>

> **Vote:** C1
> **Reasoning:** It replaces today's UnresolvedMethod, which wrongly tells the user that the method does not exist, with a bound error that names the cause and the fix. The conditional form keeps `T: Clone` meaning the same thing under substitution.
> **Concern:** The impl gap on `List` and tuples (F13) will make users think C1 is broken too unless both bugs land together.

</details>

<details>
<summary>AI/ML — C1</summary>

> **Vote:** C1
> **Reasoning:** A model types `.clone()` on any value; today it fails only on Option and Result, so C1 removes a branch from the model's head. It is the tuple rule (element-wise, payload's own `clone` runs), so it adds no new meaning.
> **Concern:** A model may still read `clone` as a deep copy and expect a `List` payload to be copied; the "shared cell stays shared" sentence must sit next to the Option/Result rule, not only in F8.

</details>

<details>
<summary>Minimalism — C1</summary>

> **Vote:** C1
> **Reasoning:** It adds no new semantics: Clone is already "same as `let y = x`" for every value (F8), and C1 only says Option and Result are not an exception. It has the same shape as the tuple rule.
> **Concern:** None from my seat; the risk is only the open impl gap (`.clone()` on List and tuples), which is a bug ticket.

</details>

##### Q4: Framing

<details>
<summary>Systems — P4</summary>

> **Vote:** P4
> **Reasoning:** The rule sentence should be true with no exceptions. Under P6 the sentence grants derived Serialize and both JSON rows then override it, so for JSON the sentence says nothing that holds. P4 keeps the sentence exact for Eq, Ord, Clone and Debug and puts JSON in the rows, where a reader looks for wire shapes.
> **Concern:** A reader who reads only the rule sentence may conclude that Option and Result have no Serialize, so the sentence needs a pointer to the JSON rows.

</details>

<details>
<summary>Web/Scripting — P4</summary>

> **Vote:** P4
> **Reasoning:** The JSON shapes are not the derived-enum shape (the Option row already differs, and Result may differ too). Putting Serialize/Deserialize under "as derived" and then listing exceptions makes the reader check two places for one answer. Keep JSON in the JSON table, where people look for it.
> **Concern:** A reader may assume "as derived" covers JSON too unless the sentence says plainly that JSON is in its own rows.

</details>

<details>
<summary>PLT — P4</summary>

> **Q4. Framing — Vote: P4**
> Reasoning: Option's JSON is not the derived-enum shape (F9 is a decided exception), and Q7 may give Result no JSON instance or a shape of its own, so a sentence that covers Serialize and Deserialize would need exceptions whatever Q7 decides. P4 states the "as derived" rule only where it is true without an exception. That is the stronger and more honest statement, and it does not depend on Q7.
> Concern: A reader may still infer from the "as derived" sentence that JSON follows the enum row; the JSON rows must say plainly that they do not.

</details>

<details>
<summary>DevOps/Tooling — P4</summary>

> **Vote:** P4
> **Reasoning:** "As derived" is a good rule only when it has no exceptions. P6 would tell a user that `Some(5).to_json()` behaves like a derived enum and then overrule that with a table row; docs, hover text and error notes would have to carry the exception. P4 keeps JSON in its own rows, where people look for it.
> **Concern:** The derived `Debug` text for a user sum type must match the stated Option/Result `Debug` rendering exactly, or P4 states a contradiction for Debug.

</details>

<details>
<summary>AI/ML — P4</summary>

> **Vote:** P4
> **Reasoning:** The one rule sentence a model learns should have no exceptions. P6 brings JSON into the sentence and then carves out the Option row (and, under R1, Result), so a model must learn the rule and its exceptions together. P4 keeps the "as derived" sentence clean for Eq, Ord, Clone and Debug, and JSON rows stand alone in the table where a model already looks for wire shapes.
> **Concern:** A reader may assume that "as derived" extends to Serialize too and guess the tagged shape for Option; the JSON table must say plainly that its rows are the whole story.

</details>

<details>
<summary>Minimalism — P4</summary>

> **Vote:** P4
> **Reasoning:** The JSON rows for Option (`None` → `null`) are not the derived tagged shape, so a rule that puts Serialize under "as derived" starts with an exception for its most visible case. P4 keeps the sentence true with no exceptions and leaves JSON in the table where readers look for it. P6 would also pull Result into Serialize through the framing, which prejudges Q7.
> **Concern:** The per-trait lists repeat what P4 says, and someone may later edit one without the other.

</details>

##### Q5: Option decode

<details>
<summary>Systems — J1</summary>

> **Vote:** J1
> **Reasoning:** It is the inverse of the decided Serialize row and costs one tag check on `Null` before the payload decode. 03:5725 becomes one instance of the general rule.
> **Concern:** The rule is silent on a missing key, and users will assume it decodes as `None` until the out-of-scope ticket settles it.

</details>

<details>
<summary>Web/Scripting — J1</summary>

> **Vote:** J1
> **Reasoning:** It is the only rule any developer would guess, and it makes 03:5725 one case of a general rule.
> **Concern:** Without the missing-key rule (out of scope here), users will still hit decode errors on absent optional fields on day one; that ticket must follow fast.

</details>

<details>
<summary>PLT — J1</summary>

> **Q5. Option decode — Vote: J1**
> Reasoning: This is the inverse of the decided Serialize row, and the instance rule `T: Deserialize ⊢ Option[T]: Deserialize` is parametric. Without it, the round-trip law has no decode side for Option at all.
> Concern: With J1 and no rule for a missing key, users will read "missing" as "null"; the out-of-scope ticket for a missing key must not wait long.

</details>

<details>
<summary>DevOps/Tooling — J1</summary>

> **Vote:** J1
> **Reasoning:** The decode direction must be written down; 03:5725 covers only one case. The rule also fixes the error path: an inner decode error keeps its `path`, so `at $.owner.age` still works through an `Option` field.
> **Concern:** None for the rule; users will still ask what a *missing* key does, so the separate ticket must not wait long.

</details>

<details>
<summary>AI/ML — J1</summary>

> **Vote:** J1 (yes)
> **Reasoning:** It is the obvious reverse of the decided Serialize row and what every JSON library a model knows does. Without it, a model has only 03:5725 to infer from.
> **Concern:** Models will assume a missing key also decodes as `None`; until the separate ticket rules on it, that guess may be wrong at run time.

</details>

<details>
<summary>Minimalism — J1</summary>

> **Vote:** J1
> **Reasoning:** The spec states the encode row and only hints at decode (03:5725); one sentence closes a real hole and matches the decided `None` → `null` rule (DECISIONS.md:154).
> **Concern:** The missing-key case will be read into J1 by users until its separate ticket lands.

</details>

##### Q6: `Option[Option[T]]` in JSON

<details>
<summary>Systems — N2w</summary>

> **Vote:** N2w
> **Reasoning:** The instance must stay parametric. A rejection that only a monomorphized type can check is the C++ template failure mode. The amended law covers every collapse, including `Option[JsonValue]` and user types whose `to_json` returns `null`, which a field check cannot see. A warning at a written `T??` field catches the common mistake where the type is known, and `@allow` lets a deliberate "absent or null, same thing" field through.
> **Concern:** A warning is easy to ignore, so a `T??` PATCH-style field can still lose the `Some(None)` case in production.

</details>

<details>
<summary>Web/Scripting — N2e</summary>

> **Vote:** N2e
> **Reasoning:** The real source of `T??` in JSON is a PATCH body that wants "absent" vs "set to null". A silent collapse there passes tests and drops a user's intent in production; a compile error with a help line naming a `Keep` / `Clear` / `Set(T)` enum sends them to the right design at once. Keeping the instance parametric means a generic `fn send[T: Serialize](x: Option[T])` still compiles. A warning is too easy to ignore for a bug that loses data.
> **Concern:** A `T??` reached through a type alias or a generic struct field (`Wrapper[Str?]` with field `Option[T]`) escapes a check on the written type, so the spec must say whether the check sees through aliases.

</details>

<details>
<summary>PLT — N2e</summary>

> **Q6. `Option[Option[T]]` in JSON — Vote: N2e**
> Reasoning: The instance stays parametric, so generic code such as `fn send[T: Serialize](x: Option[T])` and `type Wrap[T] { v: Option[T] }` type-checks with no negative bound, and no rule is left to codegen (§3.1 rule 2). The amended law is true for every type, including `Option[JsonValue]`, which no field check can catch. The E1401 error is a front-end check on a written type, like the template-hole rule. Its repair exists (a named enum), so it meets §3.1 rule 1 and catches the PATCH-body case people write.
> Concern: Users may think the field check guarantees no collapse, while `Wrap[Option[Int]]` and `Option[JsonValue]` still collapse; the error's `note:` and the law text must say that the check covers only the written `T??` form.

</details>

<details>
<summary>DevOps/Tooling — N2e</summary>

> **Vote:** N2e
> **Reasoning:** The instance stays parametric, so a generic `fn f[T: Serialize](x: T?)` type-checks and gives no error that the user cannot fix. The concrete `T??` field in a derived JSON type has only one purpose (absent vs null), and the derive cannot keep it; an error with a help line that writes the `Keep / Clear / Set(T)` enum stops silent data loss. A warning lets that loss through again.
> **Concern:** The check covers only the written field type, so a generic struct `type Box[T] { v: T? }` used as `Box[Int?]` still collapses silently; the amended law is the only guard there.

</details>

<details>
<summary>AI/ML — N2e</summary>

> **Vote:** N2e
> **Reasoning:** The amended law tells the truth for every case, including `Some(JsonValue.Null)`, and keeps `fn send[T: Serialize](x: T?)` compiling, which a model writes often. The field check turns the common real case (a PATCH body with `T??`) into a compile-time error with a repair in the help line, instead of silent data loss that no test of a model's code is likely to catch. It is the same site check that the template hole uses, so it adds one rule that a model has already seen.
> **Concern:** A model may move the `T??` into a generic struct (`type W[T] { x: T? }` at `T = Int?`) to get past the error, and then lose data silently under the amended law.

</details>

<details>
<summary>Minimalism — N2</summary>

> **Vote:** N2
> **Reasoning:** The law amendment is the whole fix, and it covers every case, including `Option[JsonValue]` and user `impl Serialize` blocks that return `null`. A field check catches only one spelling (`T??`) of a general problem, and it adds a diagnostic code or a lint that must be specified, documented and kept up to date. If real users get hurt, a lint is a tooling change that needs no spec vote.
> **Concern:** If N2e wins, the spec has a compile error for one spelling while the same loss through a type alias or a generic field passes, which reads as a rule with holes.

</details>

##### Q7: Result JSON

<details>
<summary>Systems — R2</summary>

> **Vote:** R2
> **Reasoning:** A one-entry object is the same cost as a one-field struct, and decode is one key check and a dispatch. The shape is injective for every `T` and `E`, so the round-trip law gains no exception, and `Result[T, Never]` serializes with no special case. Rejecting it does not avoid a wire format; each team writes its own, and Blink services disagree on the wire.
> **Concern:** "An object with key `ok` or `err`" must say what `{"ok": 1, "err": 2}` and an object with extra keys decode to; I want both to be a JsonError, or two decoders will disagree.

</details>

<details>
<summary>Web/Scripting — R2</summary>

> **Vote:** R2
> **Reasoning:** Batch endpoints, job queues and caches carry per-item outcomes, and a struct with a `Result` field should derive Serialize. With no built-in shape, each team picks its own and two Blink services disagree on the wire. `{"ok": v}` / `{"err": e}` is the shape a JS consumer reads without a schema (`"ok" in r`), it is serde's shape lowercased, and it round-trips for every `T` and `E`.
> **Concern:** If R1 wins, the help line must give the enum to write in full, and the spec must say "not in v1" so that a later R2 reads as planned, not as a reversal.

</details>

<details>
<summary>PLT — R2</summary>

> **Q7. Result JSON — Vote: R2**
> Reasoning: The one-key shape is injective for every `T` and `E`, including `Result[T, T]`, so it adds no exception to the round-trip law. It also gives `Never: Serialize` its stated use (`Result[User, Never]`). `Never` has no `Deserialize`, so the instance rule correctly gives `Result[T, Never]` no decode, with no special case. R1 is sound and could be reversed later; R3 makes this vote also fix the positional-payload key for every user enum, which is a separate gap.
> Concern: If R2 wins, its lower-case keys differ from serde's `{"Ok": v}`, and Rust-interop users will meet a decode error that the message must name clearly.

</details>

<details>
<summary>DevOps/Tooling — R1</summary>

> **Vote:** R1
> **Reasoning:** A wire shape is a contract that non-Blink programs and schema generators read, and we cannot change it after 1.0 without breaking stored data. R1 can become R2 later with no break; R2 cannot be taken back. The cost of R1 is one E1401 with a help line that writes the enum for the user.
> **Concern:** If R2 wins, the decode must reject an object with both `"ok"` and `"err"` or with any extra key; under the first-entry rule alone, `{"ok": 1, "err": "x"}` would decode as `Ok(1)` with no error.

</details>

<details>
<summary>AI/ML — R1</summary>

> **Vote:** R1
> **Reasoning:** A wrong wire shape fails at run time; a missing impl fails at compile time with a help line that the model can act on in one step. Under R2, the training-data guess is serde's capitalized `{"Ok": v}`, which compiles and then fails to decode, the worst kind of decision point for code generation. R1 is reversible; R2 and R3 fix a wire format for good.
> **Concern:** Models will often write `@derive(Serialize)` on a response struct with a `Result` field and hit the error; if the help line does not show the exact enum to write, each one costs a round trip.

</details>

<details>
<summary>Minimalism — R1</summary>

> **Vote:** R1
> **Reasoning:** Nobody showed a program that serializes a Result; the ticket's MVCE needs only `<` and `.clone()`. R2 makes Result the only sum type with its own JSON shape, which is a second encoding rule to learn. Adding R2 later is a compatible change and removing it is not, so v1 should take the side we can undo.
> **Concern:** If R2 wins, the lower-case `"ok"`/`"err"` keys differ from serde's `"Ok"`/`"Err"`, and interop users will meet that mismatch.

</details>

#### Phase D — Debate and re-vote (Q6, Q7)

The moderator relayed the Phase C text of all six seats (`D/relay.md`). Each seat then answered the debate, and then voted again alone.

<details>
<summary>Systems — Phase D debate</summary>

>
> ## Q6: I move from N2w to N2e
>
> My Phase C objection was to a check that only a monomorphized type can make. N2e is not that. plt and devops state it as a front-end check on the **written** field type, the same kind of site check as the template-hole rule, and the instance stays parametric. `fn send[T: Serialize](x: T?)` and `type Box[T] { v: T? }` still typecheck, and no error appears after mono. That removes my reason to prefer a warning. web's point then decides it: a warning lets the PATCH-body loss through, and the repair (a `Keep` / `Clear` / `Set(T)` enum) always exists.
>
> Text that I want in the N2e wording, taken from the concerns of web, plt, devops and aiml:
>
> 1. **The check sees through type aliases.** It looks at the field type after alias resolution and before any type argument is substituted. So `type MaybeName = Str??` as a field type is an error. `Box[Str?]` with a field `v: T?` is not, because the field is written `T?`.
> 2. **The error's `note:` says what the check does not cover**: a generic field at `T = U?`, `Option[JsonValue]`, and a user `to_json` that returns `null`. For those the amended round-trip law is the only rule. That answers min's "a rule with holes" concern: the spec states the holes and the law covers them.
>
> With both lines, I vote N2e.
>
> ## Q7: I move from R2 to R1, with a refined wording
>
> The arguments that move me:
>
> - **Reversibility** (devops, min, aiml). R1 → R2 later is a compatible change. R2 → anything else breaks stored data. A wire shape is the one kind of decision where "wait" is cheaper than "pick". I said this myself in Phase A, and the Phase B counter-arguments did not answer it.
> - **aiml's failure-mode point is new and from my side of the table too.** Under R2 the likely wrong guess (`{"Ok": v}`, serde's casing) compiles and fails at run time. Under R1 the same mistake is a compile error with a repair. A compile-time failure is the cheaper failure.
> - **My own divergence argument is weaker than I claimed.** If the E1401 help line writes one exact enum, every team that follows it gets the same shape. So R1 with a fixed help line also gives one shape, without a language-level promise.
>
> What I give up: `Result[T, Never]` stays with no JSON use. That is a cost of zero programs today (min, F12), and the Never ruling says this gap does not narrow it.
>
> **Refined R1 (R1'):**
>
> > `Result` has no `Serialize` and no `Deserialize` impl in v1. `@derive(Serialize)` or `@derive(Deserialize)` on a type with a field of a `Result` type is E1401 `NonDerivableTrait`. The help line gives a complete enum to use in its place.
>
> with the help text fixed in the spec, for example:
>
> ```blink
> @derive(Serialize, Deserialize)
> type Outcome[T, E] {
>     Ok(value: T)
>     Err(error: E)
> }
> ```
>
> The words "in v1" are there for web's concern: a later R2 then reads as planned, not as a reversal. If the panel later takes R2, the decode must reject an object with both keys or with any extra key (devops's concern and mine), and not fall back on the first-entry rule. I ask the moderator to note that in the record for the follow-up.
>
> If R2 wins anyway, I want that strict-decode sentence in it, and I will not oppose the result.
>
> STATUS: ready to vote (Q6 N2e with the alias and `note:` lines; Q7 R1 as worded above)

</details>

<details>
<summary>Web/Scripting — Phase D debate</summary>

>
> ## Q6 — keep N2e, and adopt plt's and devops' text points
>
> N2e has a majority, so I speak only to the text.
>
> - **Accept plt's concern as text.** The E1401 `note:` and the amended law must both say the check covers only a field whose type is written `T??`. Suggested note: "`Option[Option[T]]` cannot round-trip: `None` and `Some(None)` both encode as `null`. This check covers a field written as `T??`; a generic field such as `Box[Int?]` still collapses (see the round-trip law)."
> - **Answer to my own alias concern, and to min's.** A type alias names the same type it expands to, so the check should see through an alias: `type MaybeName = Str??` on a field is the same written type as `Str??`. Generic substitution (`Box[Int?]`) stays outside the check, because seeing it would make the instance non-parametric, which every N2e voter rejected. One sentence states both: "after alias expansion, before generic substitution".
> - **To sys (N2w):** I agree a warning has an escape hatch, but the hatch is the bug. The PATCH case is the only common source of `T??` in a JSON type, and the user who writes it means "absent vs null". `@allow` on that field silences exactly the loss we want to stop. A user who truly means "absent or null, same thing" can write `T?` — that is the honest type.
> - **To min (N2):** "a rule with holes" is fair, and the note above says where the hole is. A check that catches the one spelling users write, with a repair in the help line, is worth one diagnostic.
>
> ## Q7 — I propose R2s: R2 with serde's exact keys and a strict decode
>
> The R1 voters gave three reasons. Two of them are about R2's *details*, not about a shape existing. I propose a refined option that answers both.
>
> **R2s.** `Result[T, E]: Serialize` when `T` and `E` are; `Deserialize` likewise.
> - `Ok(v)` → `{"Ok": v.to_json()}`; `Err(e)` → `{"Err": e.to_json()}` — the same keys as Rust serde's default.
> - Decode needs an object with **exactly one entry**, whose key is `"Ok"` or `"Err"` (case matters). Both keys, an extra key, no key, or a non-object is a JsonError that names both keys and the path: `expected an object with exactly one key, "Ok" or "Err", at $.outcome`. Here the first-entry rule never applies, because a second entry is already an error.
>
> ```blink
> @derive(Serialize, Deserialize)
> type Job {
>     id: Int
>     outcome: Result[Int, Str]
> }
>
> fn batch(jobs: List[Job]) -> Str {
>     json.stringify(jobs.to_json())
> }
> // [{"id":1,"outcome":{"Ok":42}},{"id":2,"outcome":{"Err":"timeout"}}]
> ```
>
> How R2s answers each R1 point:
> - **aiml: "the training-data guess is serde's `{"Ok": v}`, which compiles and then fails to decode."** Under R2s the guess is right. A model or a Rust service that writes `{"Ok": 42}` decodes. That removes the worst-case decision point aiml named. It also removes the interop concern that plt and min raised against lower-case keys. I drop my lower-case preference: "matches JSON style" is weaker than "matches the one shape that already exists in the wild".
> - **devops / sys: `{"ok": 1, "err": 2}` and extra keys must be an error.** R2s says so in the rule, not only in the decoder.
> - **min: "nobody showed a program that serializes a Result."** `batch` above is that program: a batch endpoint, a job queue result, a cached per-item outcome. These are common in web back ends. Under R1 each team writes the five-line enum, and each picks a different shape (`{"status": "ok", ...}`, `{"success": true, ...}`, `{"Ok": ...}`). Two Blink services then disagree on the wire, and that is not reversible either — it is stored data in fifty shapes instead of one.
> - **devops / min: "R1 is reversible, R2 is not."** True, and I concede it is the strongest point on the R1 side. My answer: the shape we would add later is the serde shape anyway; no seat has proposed a different one-key shape that it would prefer in v2. If the panel would pick `{"Ok": v}` later, picking it now costs nothing and removes the fifty-shapes drift.
> - **min: "Result would be the only sum type with its own JSON shape."** Option already has its own row (`null`), for the same reason: built-in types get the shape people expect. Result's row is the second built-in row, not a new kind of rule.
>
> **If R1 wins anyway,** my Phase C conditions stand: the E1401 help line writes the enum in full (devops-4a text), and the spec says "`Result` has no JSON form in v1", so a later R2s reads as planned.
>
> **Text change that would move me:** none needed to keep R2/R2s. I would vote R1 only if an R1 voter shows a real API whose wire shape for a per-item outcome is not a one-key `Ok`/`Err` object *and* would be blocked or harmed by Blink having R2s as the default (a user can still write their own enum under R2s).
>
> STATUS: ready to vote — Q6 N2e with the alias/generic sentence; Q7 R2s offered as the refined R2 (serde keys, exactly-one-key decode).

</details>

<details>
<summary>PLT — Phase D debate</summary>

>
> ## Q6 — I keep N2e, and I propose one sentence that answers web, devops, aiml and min
>
> All six seats agree on the part that carries the soundness: the instance stays parametric and the law is amended. The only question is the extra field check. min says it is "a rule with holes", and web asks whether it sees through aliases. Both are right that the check needs a stated boundary. A check with a stated boundary is not a rule with holes: the **law** is the rule and covers every case, and the check is a diagnostic over the part of that case the front end can see at the declaration.
>
> **Refined N2e wording (the boundary):**
>
> > `@derive(Serialize)` or `@derive(Deserialize)` is E1401 when a field's declared type, after type aliases are expanded, is `Option[Option[U]]` for some `U`. The check reads the declaration as written. It does not substitute type arguments, so `type Box[T] { v: T? }` derives, and `Box[Int?]` is covered only by the round-trip law. The error's `note:` says so.
>
> Why this boundary is the principled one:
> - **Aliases are expanded** because an alias is the same type (it is not a new nominal type), so a check that an alias defeats would depend on spelling, not on type identity. That would break the §3.4 rule "identity, not spelling, selects behavior". This answers web's question with "yes".
> - **Type arguments are not substituted** because a check after substitution is a check on a monomorphized type, which is a codegen-time rule (§3.1 rule 2) and the C++ template failure that sys names. So `Box[Int?]` (devops's and aiml's concern) is out of reach *by design*, and the `note:` tells the user. The law tells the truth about it.
>
> To sys (N2w): I agree that a warning would be enough as a matter of soundness. I keep the error because the written `T??` field has no meaning the derive can keep: if "absent" and "null" mean the same thing to the program, `T?` already says that, so no deliberate use is lost. A field that needs the two cases needs the enum.
>
> To min (N2): the cost is one row on an existing code (E1401), not a new code. The repair exists, so it meets §3.1 rule 1. I would rather spend that row than leave the one case that people write on purpose (PATCH bodies) silent.
>
> ## Q7 — I move to R1, on two conditions; and a stricter R2 text for the record
>
> The vote is 3-3, and both options are sound: an absent instance cannot break a law, and R2 is injective. When two options are equally sound, the tie-break from a type-theory view is the smaller commitment. A missing instance can gain an impl later with no program changing meaning (adding an instance is monotone, because no program that compiles today can observe it). A fixed wire shape cannot be withdrawn. devops, aiml and min have made that argument, and I said in B1 that I would move if the vote split. I move.
>
> **My R1 vote holds on two conditions, which web and aiml asked for:**
> 1. The spec says "**not in v1**": `Result[T, E]` implements neither `Serialize` nor `Deserialize` in v1. A later R2 then reads as a planned addition, not a reversal.
> 2. The E1401 help line writes the enum out in full, with the payload types from the field: for `Result[Int, Str]`, `type Outcome { Done(value: Int)  Failed(reason: Str) }` and `@derive(Serialize)`. aiml's one-round-trip cost depends on this.
>
> What I give up: `Never: Serialize` loses `Result[User, Never]` as its stated use. It still has `Option[Never]` and `List[Never]`, and the Never ruling gave it a closed list, not a promise of a use. That does not make R1 unsound.
>
> **For the record, if the vote stays tied:** R2 must not be written as "an object with key `ok` or `err`". devops is right that the first-entry rule alone decodes `{"ok": 1, "err": "x"}` as `Ok(1)`. That breaks injectivity on the decode side: two documents that mean different things give one value with no error. Stricter R2 wording:
>
> > Decode accepts an object whose entries all have the same key, `"ok"` or `"err"` (case matters). A repeated key follows the first-entry rule. An object that has both keys, any other key, or no entry, and every value that is not an object, is a `JsonError` that names both keys and the path.
>
> With that text I would still accept R2. But my vote is R1.
>
> STATUS: ready to vote (Q6: N2e with the alias/no-substitution boundary; Q7: R1 with "not in v1" and a full-enum help line)

</details>

<details>
<summary>DevOps/Tooling — Phase D debate</summary>

>
> ## Q6 — I keep N2e, with a refined wording that answers web, plt and min
>
> The concerns from four seats come down to one question: what does the check see? I propose the spec answers it in the rule itself:
>
> > **N2e (refined).** `@derive(Serialize)` or `@derive(Deserialize)` is E1401 `NonDerivableTrait` on a field whose declared type, after type aliases are expanded, is `Option[Option[T]]` for any `T`. The check looks at the field's type as declared. It does not look at type arguments that a use of the type supplies later, so `type Box[T] { v: T? }` derives, and `Box[Int?]` collapses as the round-trip law states. The error has a `note:` that says `None` and `Some(None)` both encode as `null`, and a `help:` that writes a user enum, e.g. `type Field[T] { Keep, Clear, Set(T) }`.
>
> - **web (aliases):** yes, see through aliases. An alias is the same type, and a check that an alias can hide is a check users learn to dodge. Alias expansion is resolved in the front end, so the check stays a front-end check, the same kind as E0534.
> - **plt (users think the check is complete):** the `note:` and the law text say what the check covers. I agree the law is the guarantee and the check is a guard on the common case.
> - **aiml (a model moves `T??` into a generic struct to dodge it):** possible, but that takes a deliberate extra type. The PATCH body that people actually write is a concrete struct with a `T??` field, and that is the case where a silent loss reaches production.
> - **sys (N2w):** a warning that `@allow` can suppress is the same as a field nobody reads in CI output. The derive cannot keep `Some(None)` on any input, so there is no false positive to suppress: every program the error rejects would lose data. A lint is right when some hits are fine; here none are.
> - **min (N2, "a rule with holes"):** with the refined text the boundary is stated, not a hole: declared types, aliases expanded, no instantiation. min says a lint needs no spec vote, but a lint the spec does not name is one that users and the LSP cannot rely on. The cost is one sentence plus one existing error code (E1401), no new code.
>
> ## Q7 — I keep R1, and I state the condition that would move me
>
> Both sides have one strong argument:
> - R2 (sys, web, plt): with no built-in shape, teams invent their own, and Blink services disagree on the wire.
> - R1 (aiml, min, me): R1 can become R2 later; R2 cannot be taken back. aiml adds the decisive point for me: the training-data guess for this shape is serde's `{"Ok": v}`. Under R2 it compiles and fails only at decode time, at run time, in another service. Under R1 the same mistake is a compile error with a repair.
>
> I answer the R2 argument with a refined R1, which also meets web's concern:
>
> > **R1 (refined).** In v1, `Result[T, E]` implements neither `Serialize` nor `Deserialize`. `@derive(Serialize)` or `@derive(Deserialize)` on a type with a `Result` field is E1401, with a `help:` that gives the full enum to write, using the field's own `T` and `E`: `type JobResult { Ok(value: Int), Err(error: Str) }`. The type mapping table gets a row `Result[T, E]` | none in v1.
>
> Why this answers "teams disagree on the wire": the help line writes the same enum for every user, so every team that follows it gets the same derived tagged shape. That is one shape, the existing one, not a second sum-type rule. If real programs then show that a one-key `{"ok": v}` shape is wanted, adding it is a compatible change.
>
> What would move me to R2: a decode rule strict enough that a serde-style or malformed document is a clear error, not a quiet wrong value. Concretely, the R2 text must say: the object has **exactly one** entry; its key is `"ok"` or `"err"`, case matters; any other object, including `{"ok": 1, "err": 2}` and `{"Ok": 1}`, is a `JsonError` whose message names both keys and gives the path, e.g. `expected an object with exactly one key, "ok" or "err", got "Ok" at $.outcome`. sys asked for the same rule. Without that text I vote R1. With it, I still prefer R1, but I will not block R2 if the user breaks the tie toward it.
>
> STATUS: ready to vote

</details>

<details>
<summary>AI/ML — Phase D debate</summary>

>
> ## Q6 — I keep N2e, with two wording refinements
>
> N2e already has 4 of 6. sys and min both say the field check covers one spelling of a wider loss.
> That is true, and plt's and devops's concerns say the same. I do not think it argues for dropping the
> check. It argues for text that says what the check covers, so that no reader (and no model) takes it as a
> guarantee. Two refinements:
>
> 1. **The check sees through aliases, not through type parameters.** web asks this. The check reads
>    the field's declared type after alias expansion: `type MaybeName = Str??` used as a field type is
>    the same error. A field `x: T?` in a generic `type W[T]` is not checked at `W[Int?]`; there the
>    amended law governs. The rule is "the written type, with aliases expanded", which a front end can
>    check at the declaration, and a model can predict from one sentence.
> 2. **The `note:` says the limit.** For example:
>    `note: None and Some(None) both encode as null; this check covers a field written as T??, and any other Some(v) whose JSON is null also decodes as None (§3.6.2 round-trip law)`.
>    That answers plt's concern ("users may think the check guarantees no collapse") in the place where the
>    user reads it.
>
> To sys: a warning that `@allow` can suppress is a fair choice for a deliberate "absent or null, same
> thing" field. But that field has a correct spelling, `T?`, which says the same thing without the
> nesting. A user who writes `T??` and means `T?` has a typo, and an error is the right response.
> I see no `T??` field that needs to compile under a derive, so a warning gives nothing back for the
> loss it lets through.
>
> To min: the diagnostic code is E1401 NonDerivableTrait (moderator's fact check). The check adds a
> reason to an existing code, not a new code. The spec cost is one sentence plus the note.
>
> ## Q7 — I stay R1; here is what R2 needs to be acceptable if it wins the tiebreak
>
> I do not move. My Phase C reason stands: R2 is a wire shape that fails at run time when it is guessed
> wrong, and the training-data guess (serde `{"Ok": v}`) is wrong under R2. R1 fails at compile time,
> with a help line. R1 can become R2 later with no break, and R2 cannot become R1.
>
> To sys and web ("each team invents its own shape"): under R1 the help line tells every user the same
> thing: write a user enum and derive Serialize on it. That gives one Blink shape (the F9 tagged
> object), not fifty. So the divergence is smaller than claimed. It is not zero, I concede: variant
> names will differ between teams.
>
> To plt (`Never: Serialize` has no use): true, and I concede R2 is the more compositional option.
> But a use for one prelude impl does not need a wire format we can never change.
>
> **Concessions and conditions.** If the tiebreak goes to R2, I want these in the row text. sys and
> devops raised the first two; I support them:
>
> - **Strict decode.** The object must have exactly one entry. Its key is exactly `"ok"` or `"err"`.
>   `{"ok": 1, "err": "x"}`, any extra key, and `{}` are JsonError. State that this overrides the
>   first-entry duplicate-key rule (03:5653) for Result, because under that rule alone
>   `{"ok": 1, "err": "x"}` decodes as `Ok(1)` and drops data with no error.
> - **A message a model can repair from.** The decode error's `message` contains both keys and says
>   that case matters, and for a key `"Ok"` or `"Err"` it names the lower-case key to use:
>   `expected an object with one key, "ok" or "err", at $.outcome; found "Ok" (keys are lower case)`.
>   This makes the serde guess repairable in one step instead of a dead end.
> - **Spec example.** The row has a two-line example (`Ok(42)` → `{"ok":42}`, `Err("timeout")` →
>   `{"err":"timeout"}`) so that a retrieved chunk teaches the exact spelling.
>
> If R1 wins, I support web's condition: the help line writes the full enum
> (`type Outcome { Done(value: Int), Failed(reason: Str) }`), and the spec says "Result has no JSON form
> in v1", so a later R2 reads as an addition, not a reversal.
>
> STATUS: ready to vote (Q6 N2e with the alias and note refinements; Q7 R1, with R2 acceptable only under the three conditions above)

</details>

<details>
<summary>Minimalism — Phase D debate</summary>

>
> ## Q6. `Option[Option[T]]` in JSON — I move to N2e, with two text conditions
>
> The 4 votes for N2e answer my Phase C objection better than I expected. Every seat that voted for it kept the instance parametric, so my main worry (a negative bound, a rule that only mono can check) is gone. What is left is my "one spelling of a general problem" point. web's PATCH-body case answers it: `T??` in a derived JSON type is the one spelling people write *on purpose*, and the purpose (absent vs null) is the exact thing the derive cannot keep. A check that catches the case people write, with a help line that writes the fix, costs one diagnostic row. It reuses the template-hole site rule, so it is not a new concept. I concede.
>
> Two text changes I ask for, both drawn from the Phase C concerns (web, plt, devops, aiml all raised the same hole):
>
> 1. **Aliases: the check sees through them.** Type aliases in Blink are transparent, so `type MaybeName = Str?` then `name: MaybeName?` is the same written type as `Str??`. Say so in one clause. Without it, the check has a hole that is a pure spelling choice, which is the worst kind.
> 2. **Generic fields: say plainly the check does not see them, and point to the law.** Wording, for the E1401 note and the §3.6.2 text:
>
>    > The check looks at the field's written type, after alias expansion. A field whose type is a type parameter, such as `v: T?` in `type Box[T]`, is not checked at `Box[Int?]`; the round-trip law (03:5588) states what happens there.
>
> With those two clauses, the rule says what it covers and what it does not, and my "rule with holes" concern becomes "rule with a stated edge". N2w (sys) is a fair middle, but a warning for a bug that drops data in production is the weaker trade, and a lint is still surface to specify. If I am going to accept a check, I would rather it be one that holds.
>
> ## Q7. Result JSON — I hold R1
>
> I read the three R2 texts closely. None of them changes the two facts my vote rests on:
>
> - **No program in this ticket needs it.** sys and web name real domains (batch endpoints, job queues). I agree those exist. But in each of them the team owns the wire contract, and the R1 help line gives them a two-variant enum in one step. "Each team picks its own shape" (sys, web) is true today for every sum type that is not Result; R2 makes Result the one exception, not the rule.
> - **R1 can become R2 later; R2 cannot become R1.** devops makes the stronger version of this: a wire shape is read by non-Blink programs and schema tools, and stored data outlives the compiler. After 1.0, R2's key case is fixed for good.
>
> On plt's `Never` point (`Result[User, Never]` gives `Never: Serialize` a use): that is real, but `Never: Serialize` already has uses through any user generic type with a `T` field (`Wrap[Never]`). It does not depend on Result. F12 records that it "makes no program compile today" for a separate reason (the Option derive bug), which is a bug ticket, not a reason for R2.
>
> aiml's point decides it for me: the training-data guess is serde's `{"Ok": v}`, which under R2 compiles and fails at run time. Under R1, the same guess fails at compile time with a fix in the help line. For a language that is also training data, a compile error beats a silent wire mismatch.
>
> **Refined R1 wording**, to answer web's concern that a later R2 must read as planned, not as a reversal:
>
> > `Result[T, E]` implements neither `Serialize` nor `Deserialize` in v1. A JSON mapping for `Result` is reserved for a later version. `@derive(Serialize)` on a type with a `Result` field is E1401 `NonDerivableTrait`; its help line writes the enum to use:
> >
> > ```blink
> > @derive(Serialize, Deserialize)
> > type Outcome {
> >     Done(value: Int)
> >     Failed(reason: Str)
> > }
> > ```
>
> **If R2 wins anyway** (the user breaks the tie), I support sys's and devops's decode text as a condition: an object with exactly one entry; `{"ok": 1, "err": "x"}`, an object with any extra key, and an empty object are each a JsonError that names both keys. The first-entry rule (03:5653) must not apply here, because it would turn `{"ok": 1, "err": "x"}` into `Ok(1)` with no error. That is a silent choice inside a shape that exists to be exact. The error message for `{"Ok": 1}` should also say "keys are lower case", per plt's concern.
>
> ## Summary
>
> | Question | Position |
> |---|---|
> | Q6 | N2e (moved from N2), with: check sees through aliases; note states generic fields are not checked and points to the law |
> | Q7 | R1 (hold), with "reserved for a later version" text and a help line that writes the enum; if R2, exact one-key decode, no first-entry rule, lower-case hint |
>
> STATUS: ready to vote

</details>

**Re-vote:**

- **Q6: `Option[Option[T]]` in JSON** — Systems N2e, Web/Scripting N2e, PLT N2e, DevOps/Tooling N2e, AI/ML N2e, Minimalism N2e (6-0 N2e).
- **Q7: Result JSON** — Systems R1, Web/Scripting R2s, PLT R1, DevOps/Tooling R1, AI/ML R2s, Minimalism R1 (R1 4, R2s 2: 4-2).

##### Q6: `Option[Option[T]]` in JSON

<details>
<summary>Systems — N2e</summary>

> **Vote:** N2e
> **Reasoning:** The check runs in the front end on the declared field type, after alias expansion and before generic substitution, so no error appears after monomorphization and generic code stays parametric. It stops the one common case (a PATCH body with `T??`) that loses data at run time, and its repair always exists. The amended law covers every case the check cannot see.
> **Concern:** A user can move the `T??` into a generic field (`Box[Int?]`) to silence the error and lose `Some(None)` with no signal at all.

</details>

<details>
<summary>Web/Scripting — N2e</summary>

> **Vote:** N2e
> **Reasoning:** The PATCH body ("absent" vs "set to null") is where web developers write `T??`, and a silent collapse there passes tests and drops intent in production. A compile error with a help line that writes the `Keep` / `Clear` / `Set(T)` enum sends them to the right design at once. The instance stays parametric, so generic helpers still compile, and the note tells the user where the check stops.
> **Concern:** Users may read a clean derive as "no collapse anywhere", so the note must name the `Box[Int?]` case in words, not only point to the law.

</details>

<details>
<summary>PLT — N2e</summary>

> **Q6. `Option[Option[T]]` in JSON — Vote: N2e**
> Reasoning: The parametric instance and the amended law carry the soundness, and they are true for every type, including `Option[JsonValue]` and `Box[Int?]`. The field check has a stated, decidable boundary: alias expansion follows type identity (§3.4), and no generic substitution keeps it a front-end rule (§3.1 rule 2). Its repair, a named enum, exists (§3.1 rule 1), and no deliberate use of a written `T??` field is lost, because `T?` already says "absent and null are the same".
> Concern: Users may read the error as a full guarantee and then lose `Some(None)` through a generic field such as `Box[Int?]`; the `note:` must say plainly that only the round-trip law covers that case.

</details>

<details>
<summary>DevOps/Tooling — N2e</summary>

> **Vote:** N2e
> **Reasoning:** The instance stays parametric, so generic code gets no error the user cannot fix. Every field the check catches would lose `Some(None)` on some input, so an error has no false positives and a warning would only let the loss through. The refined text states the boundary: declared type, aliases expanded, no generic substitution. With that, the LSP, the docs and the error `note:` can all say exactly what is checked.
> **Concern:** The `help:` enum must be written with the field's real `T` and must itself derive cleanly, or the repair the error suggests fails to compile.

</details>

<details>
<summary>AI/ML — N2e</summary>

> **Vote:** N2e
> **Reasoning:** The refined text is a rule a model can predict from one sentence: the declared field type after alias expansion, before generic substitution. It turns the common real case (a PATCH body written as `T??`) into a compile-time error with a repair in `help:`, and the `note:` tells the reader the limit, so nobody takes the check as a full guarantee. The instance stays parametric, so generic `fn send[T: Serialize](x: T?)` still compiles.
> **Concern:** A model that hits the error may route around it through a generic wrapper (`Box[Int?]`) and lose data silently under the amended law; the `help:` must lead with the enum, not leave the wrapper as the easy way out.

</details>

<details>
<summary>Minimalism — N2e</summary>

> **Vote:** N2e
> **Reasoning:** The instance stays parametric, so no negative bound and no check that only mono can do. The error covers the one spelling people write on purpose (a PATCH field), reuses the template-hole site rule instead of a new concept, and its `note:` states its own edge (generic substitution) and points to the law. That is a rule with a stated limit, not a rule with holes.
> **Concern:** Users may read the error as a full guarantee and still lose `Some(None)` through `Box[Int?]`, so the law text and the note must say the same thing.

</details>

##### Q7: Result JSON

<details>
<summary>Systems — R1</summary>

> **Vote:** R1
> **Reasoning:** A wire shape is the one decision where waiting costs less than choosing: R1 can become R2 later with no break, and R2 can never be taken back without breaking stored data. Under R1 a wrong guess is a compile error with a repair; under R2 or R2s a wrong-case guess compiles and fails at decode. A help line that writes one exact enum gives teams a common shape without a language promise.
> **Concern:** If the help-line enum is not fixed word for word in the spec, tools and versions will suggest different shapes, and Blink services will disagree on the wire anyway.

</details>

<details>
<summary>Web/Scripting — R2s (dissent)</summary>

> **Vote:** R2s
> **Reasoning:** A struct with a per-item outcome (batch endpoint, job queue, cache) should derive Serialize, and one built-in shape stops each team from inventing its own. serde's `{"Ok": v}` is the only one-key shape that already exists in the wild, so a Rust service or a model that guesses it decodes correctly, which removes the interop and wrong-guess concerns raised against lower-case R2. The exactly-one-entry decode makes `{"Ok": 1, "Err": 2}` an error, so no two decoders can disagree.
> **Concern:** JS/Python consumers expect lower-case keys and may write `r.ok`, so the docs need one example that shows `r.Ok` / `"Ok" in r`.

</details>

<details>
<summary>PLT — R1</summary>

> **Q7. Result JSON — Vote: R1**
> Reasoning: R1 and R2 are both sound, so the tie-break is the smaller commitment: adding an instance later changes the meaning of no program that compiles today, but a wire shape cannot be withdrawn. "Not in v1" and a help line that writes out the enum with the field's own payload types make the absence a stated, reversible decision with a one-step repair. R2s fixes the same permanent shape with only a different key case, so the same argument applies to it.
> Concern: `Never: Serialize` loses its stated use (`Result[User, Never]`) in v1, and teams that need Result on the wire will each write a different enum until a later vote picks one shape.

</details>

<details>
<summary>DevOps/Tooling — R1</summary>

> **Vote:** R1
> **Reasoning:** A wire shape is a contract that schema generators and non-Blink services read, and we cannot change it after 1.0; R1 can become R2 later with no break. The help line writes the same enum for every user, so teams get one shape, the existing tagged one, not fifty. The serde-guess risk (`{"Ok": v}` vs `{"ok": v}`) turns into a run-time decode error under R2, and R2s only moves the mismatch to JS consumers. "Not in v1" makes a later mapping read as planned.
> **Concern:** If R1 wins and the help line does not use the field's own payload types and names, users will copy a generic `Ok(value: T)` stub that does not compile, and that diagnostic will feel worse than no mapping at all.

</details>

<details>
<summary>AI/ML — R2s (dissent)</summary>

> **Vote:** R2s
> **Reasoning:** I change my vote. My one argument from my seat against a mapping was that the training-data guess (serde's `{"Ok": v}`) would be wrong under lower-case R2 and fail at run time. R2s removes that decision point: the key is the variant name exactly as Blink spells it, which is also serde's shape, so the model's guess is correct and a derived struct with a `Result` field just works. Strict decode, with an error that names both keys and the path, covers the rest. The irreversibility argument is real, but it belongs to the devops and min seats; from my lens R2s has fewer decision points and fewer failed generations than R1's compile error round trip.
> **Concern:** A JSON consumer used to lower-case keys may write `{"ok": ...}` by hand, so the decode error must say that case matters and name `"Ok"` and `"Err"` exactly.

</details>

<details>
<summary>Minimalism — R1</summary>

> **Vote:** R1
> **Reasoning:** No program in this ticket needs a Result wire shape, and R1 can become R2 later with no break, while R2 or R2s fixes a wire contract that stored data and non-Blink readers depend on. The lower-case vs serde-case split that showed up in Phase D (R2 vs R2s) shows that the shape is still a preference, not a forced answer. Under R1 a wrong guess is a compile error with a written fix; under R2 it compiles and fails at decode.
> **Concern:** If R2 or R2s wins, the strict decode text (exactly one entry, no first-entry rule) must reach the implementation intact, or `{"ok": 1, "err": "x"}` decodes as `Ok(1)` with no error.

</details>

**Strict-decode conditions, stated by the panel for a later `Result` mapping.** If a later panel adopts a `Result` JSON form (R2 with lower-case keys, or R2s with the keys `"Ok"` and `"Err"`), the decode is strict:

- The value is an object with exactly one entry.
- The key is `"Ok"` or `"Err"` for R2s (or `"ok"` or `"err"` for R2). Case matters.
- Two keys, an extra key, `{}` and a non-object are each a `JsonError` that names both keys and the path.
- The first-entry rule for a duplicate key (§3.6.2) never applies.

The text of the options is in the R2 and R2s bullets of `D/ballot.md`, quoted here:


> - **R2:** `{"ok": v}` / `{"err": e}` (lower case), Serialize and Deserialize when `T` and `E` are. Decode needs an object with exactly one entry, key `"ok"` or `"err"` (case matters); two keys, an extra key, no entry or a non-object is a JsonError that names both keys and the path. The first-entry rule does not apply.
> - **R2s (web, Phase D):** as R2 but with serde's keys `{"Ok": v}` / `{"Err": e}`, the same strict decode.

### Final Spec

```blink
let xs = [Some(3), None, Some(1)].sort()   // [None, Some(1), Some(3)]
let a = Ok(9) < Err("x")                   // true
let c = r.clone()                          // same value as `let c = r`

@derive(Serialize, Deserialize)
type Patch[T] {
    Keep
    Clear
    Replace(value: T)
}

@derive(Serialize)
type UserUpdate {
    name: Str??   // E1401: use `Patch[Str]`
}
```

Locked points:

- `Option[T]: Ord` when `T: Ord`. `Result[T, E]: Ord` when `T: Ord` and `E: Ord`. Variant first, then payload. `None < Some(_)`. `Ok(_) < Err(_)`.
- The `Option` declaration lists `None` before `Some(T)`. §3.6 states both orders in words.
- `Option[T]: Clone` when `T: Clone`. `Result[T, E]: Clone` when `T: Clone` and `E: Clone`. `x.clone()` gives the same value as `let y = x` when the payload's own `clone` does.
- One rule sentence covers `Eq`, `Ord`, `Clone` and `Debug`. JSON has its own rows.
- `Option[T]: Serialize` when `T: Serialize`, and `Deserialize` when `T: Deserialize`. `null` is `None`. Any other value is `Some` of the decoded `T`.
- The instance for `Option[Option[T]]` stays parametric. The round-trip law does not hold for `Some(v)` where `v.to_json()` is `null`. A derive on a field declared `T??` is E1401. The check reads the type after alias expansion and before generic substitution. The `note:` names the `Box[Int?]` case in words.
- `Result` has no JSON form in v1. A derive on a type with a `Result` field is E1401. The `help:` writes the full enum with the payload types of the field.
- Out of scope: a missing key that decodes as `None`, `List[T]: Ord`, a JSON row for tuples, positional payload keys, and `Hash`.

### Concerns

- Moderator edit to the `help:` names: the panel's examples used `Set(value: T)`, `Ok(value: T)` and `Err(error: E)`. `Set` is a prelude type and `Ok`/`Err` are prelude variants (§10.6), so a bare `Ok(x)` near the suggested enum would have two meanings. The spec writes `Replace(value: T)` and `Success(value: T)` / `Failure(error: E)`. The panel fixed the shape (full enum, field's own payload types, payload names `value` and `error`), not these names; the owner may change them.
- A user can reach the loss through `Box[Int?]`, `Option[JsonValue]` or a written `to_json`. The `note:` and the round-trip law must say the same thing.
- The `help:` text for a `Result` field must write the payload types of the field. It must not leave `T` and `E` as placeholders.
- Strict decode, if a `Result` form is adopted later, must reach the implementation as stated above.
