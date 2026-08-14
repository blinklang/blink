[< All Decisions](../DECISIONS.md)

# Iterator Protocol — Design Rationale

### Panel Deliberation

Five panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML) voted independently on 5 questions.

**Q1: Single-method vs multi-method Iterator (3-2 for single)**

- **Systems:** Multi-method (next + size_hint). `size_hint()` enables pre-allocation in `collect()` and `Vec::extend`. Critical for performance-predictable iteration. *(dissent)*
- **Web/Scripting:** Single. JS `[Symbol.iterator].next()` returning `{value, done}` maps to `Option[T]`. `has_next()` creates awkward double-call state. Training data strongly favors single-method.
- **PLT:** Multi-method (next + size_hint). Pragmatic extension that enables fusion without breaking the semantic model. *(dissent)*
- **DevOps:** Single. One required method means simpler derive macros, cleaner LSP completions, better error messages. Size hints can be added later as optional overrides.
- **AI/ML:** Single. Dominant pattern across Rust/Python/JS training data. Split methods require LLMs to coordinate two calls, increasing error rates.

**Q2: IntoIterator separation (5-0 for separate)**

- **Systems:** Separate. Collections shouldn't be consumed by iteration. Fresh cursor each time.
- **Web/Scripting:** Separate. JS distinguishes iterables (`[Symbol.iterator]()`) from iterators (`.next()`). Two loops over same list must both work.
- **PLT:** Separate. Conflating collection with traversal state is a category error. Semantically crucial.
- **DevOps:** Separate. Better error messages: "Vec does not implement Iterator, did you mean `for x in vec`?"
- **AI/ML:** Separate. Clear conceptual boundary LLMs can learn. Matches Rust's ubiquitous pattern.

**Q3: Lazy by default (5-0 for lazy)**

- **Systems:** Lazy. Only model compatible with zero-cost abstractions. `.map().filter().take(10)` on a million elements must not allocate intermediates.
- **Web/Scripting:** Lazy. Modern JS/Kotlin lazy chains are the right default. Token-efficient for AI generation.
- **PLT:** Lazy. Composes with fusion optimizations. Explicit `collect()` gives control.
- **DevOps:** Lazy. Prevents accidental quadratic behavior. Makes pending transformations visible in type signatures.
- **AI/ML:** Lazy. Produces token-efficient pipelines. LLMs excel at fluent chain generation.

**Q4: Adapter method placement (5-0 for default methods)**

- **Systems:** Default methods. Implement `next()`, get combinators free. Performance overrides still possible.
- **Web/Scripting:** Default methods. Web devs expect `.map()` to "just work". Minimum friction.
- **PLT:** Default methods. Natural home for combinators. Mirrors Haskell typeclasses.
- **DevOps:** Default methods. Derive macros trivial (generate `next()` only). One canonical documentation location.
- **AI/ML:** Default methods. Minimizes what LLMs must generate. Heavily represented in training data.

**Q5: Effectful iteration (3-2 for defer to v2)**

- **Systems:** Effects in v1. Effectful iteration is fundamental (file lines, DB cursors). Deferring creates compatibility chasm. *(dissent)*
- **Web/Scripting:** Defer. Async iteration in JS is a separate protocol because mixing has nasty edge cases. Get the simple case right first.
- **PLT:** Effects in v1. Evidence-passing means effectful iterators are just monomorphizations. No runtime burden. *(dissent)*
- **DevOps:** Defer. Effects on lazy iterators add compiler complexity (when does `! IO` fire?). Avoid half-solutions.
- **AI/ML:** Defer. Effectful iterators have virtually no training data. LLMs would hallucinate syntax. Ship pure, add effects when usage patterns emerge.

---

## Second Deliberation — `qzdz2e`: sealed carrier + eager collections

The first deliberation left a contradiction the compiler could not honor: §3c.1 defined `trait Iterator[T] { fn next(self) -> Option[T] }` **and** used `Iterator[T]` as a concrete return type, under a monomorphization-only model (no dyn/existential) where a bare trait-typed return has no representation. A six-panelist re-deliberation (systems, web/scripting, PLT, DevOps/tooling, AI/ML, **minimalism**) resolved it. This section **supersedes** the Q1 (single-method `next`) and Q4 (adapter placement as trait defaults) results above; it refines Q2/Q3/Q5.

### Facts that framed the debate

- **F1 (verified, sys+plt):** `fn next(self) -> Option[T]` is unimplementable. `self` is by-value copy-semantics (§3.6, no `&mut self`); a write to `self.field` to advance a cursor is silently discarded. The old `Fibonacci` example was denotationally empty — a latent soundness hole.
- **F2 (verified):** Blink already ships the runtime existential — the `MapIterator` fat-pointer carrier (`src/codegen_types.bl:8636`, constructed stack-local at `codegen_methods.bl:4311`). "No dyn" is a *type-system* rule, not runtime poverty; a closure is already an existential.
- **F5 (plt+min):** Under copy semantics with no linearity checker, a lazy *mutable-cursor* carrier aliases (`let b = a` shares position) and can return an interior pointer into a dead frame. The carrier must be a **persistent, restartable recipe** — `Iterator[T] ≅ Unit -> Option[(T, Iterator[T])]` (OCaml `Seq.t`, the final coalgebra) — which also dissolves F1.

### Deduped option-space

- **D1** — What is `Iterator[T]`? A concrete sealed opaque carrier (A) vs a trait that is static-opaque in type position (B).
- **D2** — List's own adapters: eager → `List` (A) vs uniform lazy → `Iterator` (B). *(BDFL ruled the earlier 5-0 lazy vote's scope OPEN for this question.)*
- **D3** — User-defined iterators in v1: `from_fn` + open `IntoIterator` now (A); functional cursor `next(self) -> Option[(T, Self)]` (B); seal v1, `from_fn`/`unfold` free-fn only, unseal `IntoIterator` in v2 (C).
- **D4** — Implicit `IntoIterator`→`Iterator` coercion: no coercion, explicit `.iter()` (A) vs checking-mode coercion (B).
- **D5** — `zip`/`enumerate` return tuples.
- **D6** — Reserve an effect-row slot for a v2 effectful iterator.

### Phase B — Debate highlights (verbatim / attributed excerpt)

**D1 — sys conceded B→A:** "static opacity = impl Trait in let-position (Rust deliberately lacks it), no answer for two match arms returning different chains or storing an iterator in a struct field (both need boxing, F4 bans). Too large a permanent type tax. CONCEDE D1→A with a condition on record as spec text: carrier is SEALED and layout UNSPECIFIED, stack-allocated no per-adapter heap, T never boxed."

**D1 — aiml:** "`let it: Iterator[Int] = ...` is THE shape models emit for long chains; B makes it unnameable. CONCESSION wanted in ruling: D1-A safe only if carrier is SEALED and sealing diagnosed BY NAME — models will try `impl Iterator[Int] for Fibonacci`; error must say 'Iterator is a sealed builtin; construct with from_fn or implement IntoIterator.' An error that names the replacement > the trait."

**D1 — plt (attributed excerpt):** the carrier must be a persistent/restartable recipe, `Iterator[T] ≅ Unit → Option[(T, Iterator[T])]` (OCaml `Seq.t` final coalgebra) — "each node re-entered not advanced; copy free, re-traversal recomputes. This DISSOLVES F1." Price: `xs.iter().map(expensive)` twice runs `expensive` twice (predictable).

**D2 — web, D2-A HARD:** "Industry after 15 yrs: Kotlin `list.map`→List (lazy=`.asSequence()`); Java no map on Collection (`.stream()` first); Python list-comp eager … 4/5 converged eager-on-collection, lazy-opt-in-on-carrier. D2-B isn't one rule — it's one rule + a mandatory `.collect()` ritual + a new silent failure. Side-effect version `users.map(fn(u){io.println(u.name); u})` → prints NOTHING, no error — imports Python's #1 lazy question into a language whose F4 stance is 'under-determined = HARD error.'"

**D2 — aiml:** "Under B the failure is `list.map(f)` — highest-freq generated line — stops returning List … repair (`.collect()`) not derivable from local context. Benign-and-frequent beats fatal-and-frequent."

**D2 — min (dissent, attributed excerpt):** uniform-lazy is one rule not two; codegen *already* routes all adapters through one lazy branch (`codegen_methods.bl:4230`), so D2-A is the *addition* (a per-method materialize rule the compiler lacks), not the subtraction. Concedes eager familiarity is real; owes a lazy-carrier `Debug`-print answer.

**D3 — devops, D3-C as the staging of D3-A:** "moved off 'sealed forever' and off my Phase A open-`next` trait entirely — D3-A is the correct destination, I'll vote it in v2 without a fight. v1 ships sealed carrier + `from_fn` (D3-A's producer half), Stage 2 = purely 'unseal `IntoIterator`,' additive, breaks nothing, lets us rewrite E0302 once deliberately alongside the completion work." Grounded in T1 (E0302's explain body is a hardcoded closed type list, `diagnostics.bl:770`) and T2 (no type-directed dot completion in `lsp.bl`).

**D3 — web, D3-A:** "F1 settles it: `next(self)->Option[T]` can't work under copy semantics. State must live where user can mutate = a closure; `from_fn` is the closest thing to a generator, and reads like one." Naming: concede `Iterable`→`IntoIterator`, but the method should be `iter()` not `into_iter()` — "`into_` is Rust ownership vocab, signals nothing in a GC lang."

**D3 — sys, held D3-B then fell back to C:** "COMPROMISE: adopt D3-B as the open extension point, ship `from_fn` as SUGAR over it … Fallback C (sealed v1) acceptable; cannot support A-as-only-mechanism."

**D4 — aiml folded to A (found the fact that folds it):** "`tests/test_vag3wc_channel_handle_iterator_tids.bl:241` asserts `Iterator[Int]` resolves to kind `Typevar` (comment at :236 records it as known divergence). D1-A invalidates that assertion regardless of D4; that file is edited EITHER WAY. So D4-B does NOT keep the test green. Fold now, not at 5-1."

**D6 — sys, split it:** "Type-level slot is FREE (`Iterator[T] ≡ Iterator[T] ! {}`, reserve syntactic position now) — RESERVE. Runtime plumbing … do NOT build now." web: "accept IF INVISIBLE … If it leaks into `fn iter(self) -> Iterator[T]` spelling, I'm against."

### Phase C — Silent vote

- **D1 — Concrete sealed opaque carrier: 6-0.** All six. Trait-opaque holdouts (sys, aiml) conceded on F2.
- **D2 — Eager collection adapters → `List`; lazy `Iterator` adapters; `.iter()`/`.collect()` are the doors: 5-1.** *(dissent)* **Minimalism** — uniform lazy is the one rule; eager is the addition the codegen doesn't yet implement.
- **D3 — 3-3** (open-now: web, plt, aiml — A; staged: sys, devops, min — C) → **Phase D**.
- **D4 — No coercion, explicit `.iter()`: 6-0.**
- **D5 — `zip`/`enumerate` return tuples `(T,U)`/`(Int,T)`: 6-0.**
- **D6 — Reserve invisibly** (pure v1, `Iterator[T]` stays one user-visible parameter forever, row confined to the internal mono key): consensus; PLT wanted a live effect-row variable threaded through the v1 checker immediately, the panel reserved the design without building the plumbing.

### Phase D — D3 re-debate and revote

Four of six panelists changed position — **web A→C, plt A→C, aiml A→C, devops C→A, min C→A** — landing **4-2 for staging (D3-C)**.

- **D3 — Seal `Iterator` and `IntoIterator` in v1; `iter.from_fn`/`iter.unfold` are the sole v1 producers; unseal `IntoIterator` in v2: 4-2.**
  - **Systems, Web, PLT, AI/ML — C:** unsealing later is a monotone, non-breaking change; shipping an open protocol whose central invariant (carrier persistence, F5) cannot yet be stated in the type system is not reversible. v1's real `from_fn` usage becomes the evidence that shapes v2's open-world diagnostics and completion.
  - *(dissent)* **DevOps, Minimalism — A:** open `IntoIterator` in v1 now; `from_fn` without an open `IntoIterator` is a half-feature (you can make iterators but cannot make your own type work in `for x in my_tree`).

### Final Spec

```blink
// Iterator[T] is a SEALED, OPAQUE, built-in carrier — not a user trait.
// A restartable recipe (Unit -> Option[(T, Iterator[T])]), not a mutable cursor.

// Collections are EAGER — a collection method answers a collection:
let shouted: List[Str] = names.map(fn(n) { n.to_upper() })

// .into_iter() crosses into the LAZY world; .collect() crosses back:
let first_two: List[Str] = names
    .into_iter()
    .filter(fn(n) { n.len() > 3 })
    .take(2)
    .collect()

// Custom iteration in v1: iter.from_fn (a free function, the sole producer).
// The Iterator trait is sealed and unimplementable.
fn fibonacci() -> Iterator[Int] {
    let mut a = 0
    let mut b = 1
    iter.from_fn(fn() {
        let v = a
        a = b
        b = v + b
        Some(v)
    })
}

// zip/enumerate answer TUPLES:
fn zip[U](self, other: Iterator[U]) -> Iterator[(T, U)]
fn enumerate(self) -> Iterator[(Int, T)]
```

Locked design points:

- `Iterator[T]` is a sealed, opaque, built-in carrier; layout unspecified; prints as `Iterator[T]`; its adapter surface (`IteratorOps`) is sealed and not user-overridable.
- The carrier is a **restartable recipe**, not a mutable cursor. `.into_iter()`-derived iterators restart; `from_fn` iterators are one-shot (re-traversal unspecified).
- **Collection adapters are eager** and answer a collection; **`Iterator` adapters are lazy** and answer an iterator. `.into_iter()` in, `.collect()` out. No implicit conversion either way.
- The crossing method is named **`into_iter`** — the incumbent spec name (prelude table, `for` desugaring, ~25 existing sites). Web/Scripting argued for the shorter `iter()` on the ground that Rust's `iter`/`into_iter` borrow-vs-consume split is meaningless under Blink's GC value semantics, so one short name would do; **noted but not adopted** — Blink has zero precedent for `.iter()` and the incumbent name ships unchanged.
- Custom iteration in v1 = `iter.from_fn`/`iter.unfold` free functions only. `Iterator` and `IntoIterator` are **sealed in v1**; user `IntoIterator` is deferred to v2 (monotone, non-breaking). `Iterator` itself — the carrier and its adapter surface — stays **sealed permanently**; only `IntoIterator` is the extension point that opens in v2.
- `zip`/`enumerate` return tuples, never nested lists.
- v1 `Iterator` is **pure**; the effect row is reserved in the internal carrier representation only, invisible on every v1 surface. Effectful iteration is a conservative v2 extension.

