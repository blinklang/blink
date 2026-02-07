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
| 3.1 Injection safety | **A: `Query[C]` parameterized queries** — auto-parameterize in Query context | 3-0 |
| 3.2 Query escape hatch | **D: `Raw(expr)` marker type** — replaces `Query.raw()` with per-interpolation type wrapper | 2-1 |

**All blocking questions resolved.** 3.2 is non-blocking (refines 3.1's escape hatch). Remaining open items are v2+ deferrals (see SPEC.md).

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

### 3.1 Interpolation Injection Safety

**Context:** Pact's universal string interpolation passes interpolated strings directly to `db.query_one()`, `db.execute()`, etc. — textbook SQL injection. The effect system tracks *who* can touch the database but not *what data* flows into it.

**Option A: `Query[C]` phantom-typed parameterized queries (recommended)**

DB handle methods accept `Query[DB]` not `Str`. When an interpolated string literal is passed where `Query[DB]` is expected, the compiler auto-constructs a parameterized query. `Query.raw()` is the escape hatch for dynamic SQL.

```pact
// Developer writes (unchanged syntax):
db.query_one("SELECT * FROM users WHERE id = {id}")
// Compiler sees: Query.param("SELECT * FROM users WHERE id = $1", [id])

// Str → Query is a compile error:
let q: Str = "SELECT * FROM users WHERE id = {id}"
db.query_one(q)  // ERROR: expected Query[DB], got Str
```

**Option B: Taint tracking (deferred to v2)**
Full information flow tracking via effect provenance. More powerful but significantly more complex.

**Option C: Lint-only (rejected)**
Warn on interpolation in DB calls. No type safety. Violates "if it compiles, it's safe."

**Vote: A — 3-0 unanimous. B deferred to v2. C rejected.**

---

### 3.2 Query Escape Hatch Mechanism (RESOLVED)

**Context:** Section 3.1 established `Query[C]` with `Query.raw()` as the escape hatch for dynamic SQL. But `Query.raw()` is all-or-nothing — it disables parameterization for the *entire* string. Mixed cases (dynamic table name + safe value) force the whole query unsafe.

**Problem:**

```pact
// Current: Query.raw() makes EVERYTHING unsafe
db.query_one(Query.raw("SELECT * FROM {table} WHERE id = {id}"))
// Both {table} and {id} are concatenated. {id} is unnecessarily unsafe.
```

**Option A: Per-interpolation `:raw` modifier (recommended)**

Add a format-spec-style `:raw` modifier. In `Query[C]` context, `{expr}` is parameterized by default; `{expr:raw}` is concatenated. Replaces `Query.raw()` entirely — one mechanism, not two.

```pact
// Only table is concatenated; id is still a bound parameter
db.query_one("SELECT * FROM {table:raw} WHERE id = {id}")
// Compiler: Query.param("SELECT * FROM users WHERE id = $1", [id])
//           with "users" concatenated from table

// Fully dynamic (all raw) — still works, just verbose
db.query_one("{whole_query:raw}")
```

- Granular: unsafe only where you need it
- Visible at exact point of danger inside the string
- Auditable: `pact audit` can flag individual `{expr:raw}` sites
- Kills `Query.raw()` — one escape mechanism, not two
- Generalizes: `:raw` in `Query[HTML]` = "don't escape", `Query[Shell]` = "don't quote"
- Risk: 4 characters is easy to type — less of a speed bump than `Query.raw()`

**Option B: Keep `Query.raw()`, no format spec**

Current design. `Query.raw()` wraps the entire string. For mixed cases, construct the query in parts:

```pact
// Workaround for mixed safe/unsafe:
let table_part = Query.raw("SELECT * FROM {table}")
let where_part = "WHERE id = {id}"  // parameterized
db.query_one(Query.join(table_part, where_part))
```

- Simpler string grammar — no `:` modifier syntax inside interpolation
- `Query.raw()` is intentionally ugly/verbose (speed bump)
- Mixed cases are awkward but rare
- No format spec means no temptation to add `:.2f` etc. later

**Option C: Both `Query.raw()` and `:raw` modifier**

Keep `Query.raw()` for fully-dynamic queries, add `:raw` for mixed cases.

```pact
// Fully dynamic — Query.raw() (existing)
db.query_one(Query.raw("{dynamic_sql:raw}"))

// Mixed — :raw modifier (new)
db.query_one("SELECT * FROM {table:raw} WHERE id = {id}")
```

- Two mechanisms for the same concept (violates Principle 2?)
- But each covers its natural use case well
- `Query.raw()` for "I know what I'm doing, the whole thing is dynamic"
- `:raw` for "one piece is dynamic, the rest is safe"

**Option D: Marker type `Raw(expr)` instead of format spec**

Use the type system instead of string syntax. A `Raw[T]` wrapper tells the compiler "concatenate, don't parameterize":

```pact
db.query_one("SELECT * FROM {Raw(table)} WHERE id = {id}")
// Raw-wrapped → concatenated, unwrapped → parameterized
```

- No new string grammar — uses existing expression syntax
- Type-system native — consistent with Pact's "types are the mechanism" philosophy
- Greppable: `Raw(` is as easy to audit as `:raw`
- Slightly more verbose than `:raw` (good speed bump? or annoying noise?)
- `Raw` needs to be a compiler-known type

**Sub-question: General format specs (`:>20`, `:.2f`) for v1?**

All options above only address the `:raw` modifier in `Query[C]` context. Should Pact support Python-style format specs for display formatting in `Str` context?

- **No (recommended for v1):** Format specs are a mini-language. `{price.format(2)}` works today via method calls. YAGNI.
- **Yes:** Convenient for formatted output. But adds parser complexity, another thing LLMs must learn.

**Recommendation: A.** One escape mechanism, granular, visible at the danger point. No general format specs for v1.

**Vote: A / B / C / D**
**Sub-vote: format specs — No (v1) / Yes**

**Vote: D — 2-1. PLT and Security voted D; AI/DX voted A. No format specs — 3-0 unanimous.**

**Key arguments for D over A:**
- No string grammar extension — `Raw(expr)` is just an expression inside `{...}`, zero new parser productions
- No format spec slippery slope — `:raw` creates `{expr:modifier}` grammar that invites `:.2f`, `:>20` etc.
- Type-system native — consistent with Pact's "types are the mechanism" philosophy; `Raw[T]` is a compiler-known type like `Option[T]`
- Proven industry pattern — Django's `mark_safe()`, Rails' `raw()`, Jinja2's `Markup()` all mark the VALUE, not the template slot
- Long-term safety signal — `Raw()` stays visually distinctive even if format specs are added later

**AI/DX dissent (A):** Cold-start LLM accuracy — `{x:raw}` maps to existing Python format spec training data; `Raw(expr)` is novel. Counter: `Raw(x)` inside `{...}` is just a function call inside interpolation, which LLMs handle reliably (cf. Python's `f"{str(x)}"`).


---

## Part 3: DEFERRED

Not blocking v1. Revisit after core language is stable.

| Question | Why deferred | Revisit when |
|----------|-------------|--------------|
| Comprehensions | For-in + method chaining covers use cases | v1 usage data shows pain points |
| While loops | `loop { }` + `break` may suffice; need iterator design first | Iterator trait finalized |
| Information flow tracking | Taint tracking via effect provenance. `Query[C]` covers injection for v1 | v2 roadmap |
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
| Injection safety | sections/03_types.md | 3.12 |
| Query escape hatch | OPEN_QUESTIONS.md | 3.2 |
