# Open Questions — Pact v0.3

> Expert panel review complete. All votes unanimous (5-0). Decisions recorded in SPEC.md and spec sections.

## Panel Results Summary

| Question | Result | Vote |
|----------|--------|------|
| 1.1 Closure syntax | **A: `fn(params) { body }`** | 5-0 |
| 1.2 Derive syntax | **A: `@derive(...)` annotation, compiler-known only v1** | 5-0 |
| 1.3 Property access | **A: Always `x.len()` everywhere** | 5-0 |
| 2.1 Concurrency | **Ratified** — `main` gets implicit effects | 5-0 |
| 2.2 Stdlib tiers | **Ratified** — `math/str/fmt` confirmed Tier 1 | 5-0 |
| 2.3 For-loop/chaining | **Ratified** | 5-0 |
| 2.4 Range syntax | **Ratified** — `Range[T: Ord]` | 5-0 |
| 2.5 Await semantics | **A: `handle.await`** — method on `Handle[T]` | 5-0 |

**All blocking questions resolved.** Remaining open items are v2+ deferrals (see SPEC.md).

---

## Part 1: VOTE NEEDED (RESOLVED)

These blocked v1. Each had a recommendation; all recommendations accepted.

---

### 1.1 Closure Syntax

**Context:** Closures appear in `.map()`, `async.spawn()`, pipe chains, and handler blocks. The syntax choice ripples through every example and tutorial.

**Option A: `fn(params) { body }` (recommended)**

```pact
let evens = numbers.filter(fn(x) { x % 2 == 0 })

let doubled = data
    |> transform()
    |> filter(fn(x) { x > 0 })
    |> collect()

async.spawn(fn() { fetch_user(user_id) })
```

- Consistent with named function syntax — one `fn` keyword everywhere
- No ambiguity with `|>` pipe operator (pipes use `|>`, closures don't use `|`)
- AI-friendly: single pattern to learn/generate

**Option B: `|params| body`**

```pact
let evens = numbers.filter(|x| x % 2 == 0)

let doubled = data
    |> transform()
    |> filter(|x| x > 0)
    |> collect()

async.spawn(|| fetch_user(user_id))
```

- Terser, familiar to Rust users
- Visual collision with `|>` pipe operator in chains — `|>` and `|x|` look similar at a glance
- Two syntactic forms for "function": `fn` for named, `|x|` for anonymous

**Option C: Both (fn for multi-line, |x| for single-expression)**

```pact
numbers.filter(|x| x % 2 == 0)              // short: pipe syntax
items.map(fn(item) { validate(item); item }) // long: fn syntax
```

- Maximum flexibility, but two ways to write the same thing
- Violates "one parse, one meaning"; complicates formatter/linter/tutorials

**Recommendation: A.** One keyword, one pattern, no ambiguity. Pact already rejected sigil-heavy syntax across the board. Consistency > terseness.

**Vote: A / B / C**

---

### 1.2 Derive/Codegen Syntax

**Context:** Auto-deriving `Eq`, `Hash`, `Debug`, `Clone` etc. is table-stakes for usability. Design question is syntax + scope.

**Option A: `@derive` annotation (recommended)**

```pact
@derive(Eq, Hash, Debug, Clone)
pub struct UserId {
    value: Str
}
```

- Fits the existing 14-annotation system — `@derive` becomes #15
- Stacks naturally with other annotations:

```pact
@derive(Eq, Hash)
@invariant(self.value.len() > 0)
pub struct Email {
    value: Str
}
```

- `pact fmt` ordering already defined for annotations

**Option B: Inline `derive` keyword**

```pact
pub struct UserId derive(Eq, Hash, Debug, Clone) {
    value: Str
}
```

- Compact, reads left-to-right
- No precedent in the annotation system — one-off syntax
- Where does it go when stacked with `@invariant`?

**Sub-question: Compiler-known only, or user-defined derives?**

- **v1: Compiler-known only.** `Eq`, `Ord`, `Hash`, `Debug`, `Clone`, `Display`. Finite list, compiler can verify correctness.
- **v2+: User-defined.** Opens codegen/macro territory. Defer until the trait system is battle-tested.

**Recommendation: A + compiler-known only for v1.** Annotations are the established mechanism for metadata. Don't invent a second system.

**Vote: A / B**
**Sub-vote: compiler-known only (v1) / user-defined from day one**

---

### 1.3 Property Access in Contracts

**Context:** The spec currently uses `x.len()` (method-call syntax) everywhere. But contract annotations like `@requires` read more naturally with `x.len` (property-style). This creates a tension.

**Option A: Always `x.len()` everywhere (recommended)**

```pact
@requires(index >= 0 && index < list.len())
@ensures(result.len() == old(list.len()) + 1)
fn push[T](list: List[T], item: T) -> List[T] { ... }

type NonEmptyStr = Str @where(self.len() > 0)
```

- One rule, no exceptions
- Method calls are already used in all current spec examples
- Contracts use the same syntax as code — no context-switching

**Option B: Always `x.len` everywhere**

```pact
@requires(index >= 0 && index < list.len)
@ensures(result.len == old(list.len) + 1)
fn push[T](list: List[T], item: T) -> List[T] { ... }

let n = items.len
```

- Cleaner in contracts
- Requires distinguishing "field access" from "zero-arg method call" at the type level
- Ambiguous: is `x.foo` a field or a method? Compiler knows, reader doesn't

**Option C: `x.len()` in code, `x.len` in contracts**

```pact
let n = items.len()                          // code: method call
@requires(index >= 0 && index < list.len)    // contract: property
```

- Best readability in each context
- Two syntax rules; formatter/linter must track context

**Recommendation: A.** One syntax rule. The `()` in contracts is a minor readability cost; context-dependent grammar is a major complexity cost. Every spec example already uses `x.len()`.

**Vote: A / B / C**

---

## Part 2: RATIFY CONSENSUS

These are de facto resolved through conversation and examples. Formalize with a quick ratification.

---

### 2.1 Concurrency: Green Threads + Structured Concurrency + Effects

**Consensus from design session:**

- Green threads (M:N scheduling), no OS thread exposure
- Structured concurrency: `async.scope { }`, no spawn without scope
- `Async` is an effect, not a keyword — no function coloring
- `handle.await` only for joining spawned tasks
- Channels: `channel.new[T](buffer: N)`, send/receive/close
- Runtime wired in main: `async.Runtime.new()` + `runtime.run(fn() { ... })`

```pact
fn load_dashboard(user_id: UserId) -> Dashboard ! Async, Http {
    async.scope {
        let user = async.spawn(fn() { fetch_user(user_id) })
        let posts = async.spawn(fn() { fetch_posts(user_id) })
        Dashboard {
            user: user.await
            posts: posts.await
        }
    }
}
```

**Open gap:** How exactly does `main` wire the runtime? Implicit `Async` in main, or explicit `runtime.run()`? Current examples show both patterns.

**Ratify? Y / N / Needs discussion**

---

### 2.2 Standard Library Tiers

**Consensus from design session:**

| Tier | Ships with | Versioning | Examples |
|------|-----------|------------|----------|
| 1 — Core | Compiler | Locked to compiler version | `pact.core`, `pact.collections`, `pact.result`, `pact.iter`, `pact.io`, `pact.async`, `pact.testing` |
| 2 — Batteries | Toolchain | Independent versions | `pact.http`, `pact.json`, `pact.fs`, `pact.time`, `pact.regex`, `pact.crypto`, `pact.log`, `pact.cli` |
| 3 — Ecosystem | Community | Package manager | `pact-sql`, `pact-toml`, `pact-tls`, `pact-template` |

Tier 2 versions independently: `pact.http = "2.3"` works with compiler 1.x.

**Open gap:** Exact boundary between Tier 1 and Tier 2 for `pact.math`, `pact.str`, `pact.fmt`. Currently listed as Tier 1 — should any move to Tier 2?

**Ratify? Y / N / Needs discussion**

---

### 2.3 For-Loop + Method Chaining Syntax

**Consensus from examples throughout spec:**

```pact
// For-in loop
for n in 1..101 {
    io.println(fizzbuzz(n))
}

// Method chaining
let result = users
    .filter(fn(u) { u.active })
    .map(fn(u) { u.name })
    .collect()

// Pipe operator
let result = data
    |> transform()
    |> filter(fn(x) { x > 0 })
    |> collect()
```

- `for x in iterable { }` — standard for-in, no parens
- `.method()` chaining with leading-dot continuation
- `|>` pipe operator for function composition
- No comprehensions in v1 (deferred)

**Ratify? Y / N / Needs discussion**

---

### 2.4 Range Syntax

**Consensus from examples (fizzbuzz, channels, spec):**

```pact
for i in 0..100 { }      // exclusive: 0 to 99
for n in 1..=100 { }     // inclusive: 1 to 100
let bad: U8 = 300        // COMPILE ERROR: 300 exceeds U8 range (0..255)
```

- `..` exclusive upper bound
- `..=` inclusive upper bound
- Ranges are lazy iterables of type `Range[T]`
- Used in for-loops, slice indexing, pattern matching

**Ratify? Y / N / Needs discussion**

---

## Part 3: DEFERRED

Not blocking v1. Revisit after core language is stable.

| Question | Why deferred | Revisit when |
|----------|-------------|--------------|
| Comprehensions | For-in + method chaining covers use cases | v1 usage data shows pain points |
| While loops | `loop { }` + `break` may suffice; need iterator design first | Iterator trait finalized |
| Information flow tracking | Taint tracking via effect provenance | v2 roadmap |
| Row polymorphism | May be needed for effect internals | Effect system battle-tested |
| Higher-kinded types | Only if needed for effect abstractions | v2 if at all |

---

## Appendix: Source References

| Question | Source | Location |
|----------|--------|----------|
| Closure syntax | SPEC.md | line 101 |
| Closure syntax | sections/02_syntax.md | 2.8 |
| Derive/codegen | sections/07_trust_modules_metadata.md | 11.1 |
| Property access | SPEC.md | line 103 |
| Property access | sections/03_types.md | lines 543-566 |
| Concurrency | sections/04_effects.md | 4.13 |
| Stdlib tiers | sections/06_tooling.md | stdlib tiers |
| For-loop/chaining | sections/02_syntax.md | 2.7-2.9 |
| Range syntax | sections/02_syntax.md | 2.9 |
| Await semantics | sections/04_effects.md | 4.13 |
