## 2. Syntax

Pact's syntax optimizes for three things in priority order: unambiguous parsing, token efficiency, and human readability. Every syntactic choice was resolved by independent expert vote (5 panelists: systems, web, PLT, DevOps, AI/ML). Contested decisions are explained in subsections below.

### 2.1 Hello World

```pact
fn main() {
    io.println("Hello, world!")
}
```

Three lines. No imports. No effect annotation on `main` (it's implicit). No ceremony.

With CLI arguments:

```pact
fn greet(name: Str) ! IO {
    io.println("Hello, {name}!")
}

fn main() {
    let name = env.args().get(1) ?? "world"
    greet(name)
}
```

`env.args()` returns the argument list. `.get(1)` returns `Str?` (i.e. `Option[Str]`). The `??` operator supplies a default when `None`. The `greet` function declares `! IO` because it prints; `main` doesn't need to because its effects are implicit.

### 2.2 Locked Syntax Decisions

All decided through independent design and cross-team voting. None are revisitable.

| Element | Choice | Rationale |
|---------|--------|-----------|
| Function keyword | `fn` | 2 chars, 1 token. Unambiguous start-of-declaration. Rust/Zig normalized it. Sigils (`~`/`+`) were rejected 5-0 — they conflate visibility with declaration and are unfamiliar to both humans and LLM training data. |
| Entry point | `fn main()` | Convention-based. Compiler looks for `main`. No decorator, no annotation, no magic. |
| Blocks | `{ }` braces | Unambiguous nesting. LLMs produce brace errors far less often than indentation errors. Enables incremental parsing of broken code. See [2.3](#23-contested-braces-vs-indentation). |
| Statement terminator | Newline | No semicolons. Canonical formatting makes them redundant. Saves 1 token per line across every file. See [2.5](#25-contested-no-semicolons). |
| String delimiter | `"double quotes"` only | One string syntax. No single quotes, no backticks, no raw strings. Zero style debates. |
| String interpolation | `"Hello, {name}!"` | Universal — every string supports `{expr}`. No `f"..."` prefix needed. Literal brace via `\{`. See [2.4](#24-contested-universal-interpolation). |
| Bindings | `let` / `let mut` | Immutable by default. `let mut` is a deliberate speed bump that says "this will change." `:=` was rejected 5-0 — it's ambiguous about mutability. |
| Pattern matching | `match val { P => e }` | Expression-based. `=>` for arms (not `->`, which means return type). |
| Match arm separator | Newline | No commas between arms. Consistent with the newline-terminated philosophy. |
| Generic syntax | `List[Str]` | Square brackets. Zero parsing ambiguity with comparison operators. See [2.6](#26-contested-square-bracket-generics). |
| Type annotations | `name: Type` | Colon after identifier. Same syntax everywhere: params, let bindings, struct fields. |
| Return type | `-> Type` | Arrow after param list. Visually distinct from `:`. `::` was rejected 4-1 — conflicts with Haskell's type-of convention. Omit when returning `()`. |
| Effect annotation | `! Effect` | Bang after return type. Single character. Universal "danger/impurity" signal. |
| Comments | `//` line, `///` doc | No block comments. `///` produces structured data the compiler can query. |
| Expression-oriented | Last expr is return value | No `return` needed for the final expression. `return` exists only for early exit. |
| Keyword args | `fn f(a: T, -- b: U)` | Declaration-site `--` separator. Positional before, keyword after. Author decides — caller has no choice. Principle 2 preserved. |
| Option sugar | `T?` for `Option[T]` | `Str?` means `Option[Str]`. Short in type position, universally understood. |
| Option defaulting | `??` | `val ?? default` desugars to match on `Some`/`None`. Borrowed from Swift's nil-coalescing. |
| Type names | `Str`, `Int`, `Bool`, `Float` | Short PascalCase. One casing rule for builtins and user types. Token-efficient — `Str` saves 3 chars over `String`, thousands of times per codebase. |
| Visibility | `pub` keyword | Public items use `pub`. Everything else is module-private. See [2.10](#210-visibility). |
| Scoped resources | `with expr as name { }` | Deterministic resource cleanup. `Closeable` trait + LIFO close order. Reuses `with` from effect handlers; `as` disambiguates. 3-0 over `defer`. |

### 2.3 Contested: Braces vs Indentation

**Winner: braces (5-0)**

The claim that "indentation is trivial for AI" is empirically false. LLMs produce indentation errors 3-5x more often than brace errors, and the gap widens at 3+ nesting levels. Consequences:

- **Brace errors** are rare and produce clear, localized compiler diagnostics. A missing `}` points to exactly one block.
- **Indentation errors** can be silent. A mis-indented line may still parse — as part of the wrong block. The resulting program is syntactically valid but semantically wrong. This is the worst kind of bug.
- **Copy-paste** across chat, docs, web, and AI output frequently mangles whitespace. Tabs-vs-spaces is a solved non-problem with braces.
- **Incremental parsing** benefits directly. The compiler can identify block boundaries in broken code by scanning for `{}`  — critical for IDE features and the compiler-as-service architecture.

Spec 2 argued that "AI operates on the AST, not text." This is circular: if perfect AST tooling existed, surface syntax wouldn't matter. It doesn't exist yet. The syntax must be robust to text-level manipulation.

### 2.4 Contested: Universal Interpolation

**Winner: universal (voted as locked decision)**

Two string types (`"plain"` vs `f"interpolated"`) create problems:

1. The AI picks the wrong one — generating `"Hello, {name}"` without the `f` prefix, producing a literal `{name}` string. This is Python's most common string-related bug.
2. The formatter must handle two syntaxes for the same concept.
3. Developers forget the prefix, get no error, and ship broken output.

With universal interpolation, `"Hello, {name}!"` just works. When no `{expr}` is present, the compiler treats it as a plain string literal — zero cost. Literal braces use `\{`, which is rare enough (JSON templates, regex) to be acceptable. The trade is a one-character escape in edge cases vs eliminating an entire class of bugs in the common case.

**Context-sensitive interpolation.** When an interpolated string literal appears where `Query[C]` is expected (e.g., `db.query_one("SELECT * FROM users WHERE id = {id}")`), the compiler extracts `{expr}` as bound parameters instead of concatenating. The *receiving type* determines behavior: `{id}` in a `Str` context is concatenation, `{id}` in a `Query[DB]` context is parameterization. No new string syntax is needed — the same `"..."` literal does the right thing based on where it appears. See section 3.12 for details.

### 2.5 Contested: No Semicolons

**Winner: newlines (voted as locked decision)**

If there is exactly one way to format code (canonical formatting enforced by `pact fmt`), newlines are unambiguous statement separators. Semicolons carry zero additional information — they are noise tokens. Over a codebase, removing them saves thousands of tokens from AI context windows.

Multi-line expression continuation is handled by deterministic rules (see [2.7](#27-multi-line-continuation)).

### 2.6 Contested: Square Bracket Generics

**Winner: square brackets (5-0)**

Angle brackets `<>` create genuine parsing ambiguity with comparison operators:

```
// Is this a generic call or two comparisons?
f(a<b, c>d)
```

C++, Java, and TypeScript all have heuristics and special cases to disambiguate. These heuristics make parsers slower, error messages worse, and incremental compilation harder. Square brackets have zero ambiguity:

```pact
let users: List[User] = fetch_users()
let map: Map[Str, List[Int]] = build_index()
fn first[T](items: List[T]) -> T? { items.get(0) }
```

`List[Str]` can never be confused with indexing (Pact uses `.get()` for element access) or comparison. This directly serves the compiler-as-service goal: a simpler parser means faster incremental compilation, better error recovery, and easier tooling.

### 2.7 Multi-line Continuation

Pact uses deterministic continuation rules. A statement continues to the next line when the current line ends with:

- An **infix operator**: `+`, `-`, `*`, `/`, `|>`, `&&`, `||`, `==`, `!=`, `?`, etc.
- An **opening delimiter**: `(`, `{`, `[`
- A **comma** (inside argument lists, collection literals, etc.)
- The `=>` of a match arm (body continues on next line)

A statement also continues when the next line starts with:

- A **dot**: `.method()` chaining
- A **closing delimiter**: `)`, `}`, `]`
- An **infix operator** (alternative to trailing operator style)

```pact
// Trailing operator — line ends with |>, continues
let result = data
    |> transform()
    |> filter(fn(x) { x > 0 })
    |> collect()

// Method chaining — next line starts with dot
let name = user
    .get_profile()
    .display_name()
    .to_uppercase()

// Open delimiter — continues until matching close
let config = Config(
    host: "localhost"
    port: 8080
    debug: true
)

// Match arm body
match status {
    Ok(value) =>
        process(value)
    Err(e) =>
        log_error(e)
}
```

These rules are **deterministic and context-free** — no lookahead heuristics, no ambiguity. The formatter enforces canonical indentation for continued lines (one level deeper than the starting line).

### 2.8 Closures (Anonymous Functions)

Closures use the `fn` keyword — the same keyword as named functions. There is no alternate short form.

```pact
let evens = numbers.filter(fn(x) { x % 2 == 0 })

let doubled = data
    |> transform()
    |> filter(fn(x) { x > 0 })
    |> collect()

async.spawn(fn() { fetch_user(user_id) })

let add = fn(a: Int, b: Int) -> Int { a + b }
```

**Why no `|x|` syntax:** Pact has a pipe operator `|>`. Having `|x|` closures and `|>` pipes in the same expression creates visual ambiguity. More fundamentally, Principle 2 (one way to do everything) means one syntax for function abstraction: `fn`. The AI never has to choose between two closure forms. The formatter has one rule. Tutorials teach one pattern.

**Panel vote: 5-0** for `fn(params) { body }`. See [OPEN_QUESTIONS.md](../OPEN_QUESTIONS.md) 1.1.

Closures capture variables from enclosing scope by reference (for reads) or by move (when the closure outlives the scope). The compiler infers capture mode.

```pact
let threshold = 10
let above = items.filter(fn(x) { x > threshold })  // captures threshold

async.spawn(fn() {
    process(data)  // moves data into the spawned task
})
```

### 2.9 For-Loops

```pact
for x in collection {
    process(x)
}
```

Standard for-in over any iterable. No parentheses around the header. Braces required.

**Ranges:**

```pact
for i in 0..100 { }      // exclusive: 0 to 99
for n in 1..=100 { }     // inclusive: 1 to 100
```

`..` is exclusive upper bound, `..=` is inclusive. Ranges are lazy iterables of type `Range[T: Ord]`.

No comprehensions in v1 — `for` loops and method chaining (`.map()`, `.filter()`, `.collect()`) cover the same use cases.

**Panel vote: 5-0 ratified.** See [OPEN_QUESTIONS.md](../OPEN_QUESTIONS.md) 2.3, 2.4.

### 2.10 Visibility

All items (functions, types, constants, modules) are **private by default**. The `pub` keyword makes an item visible outside its module.

```pact
// Private — only accessible within this module
fn hash_password(pwd: Str) -> Str ! Crypto {
    crypto.hash(pwd)
}

// Public — part of the module's API
pub fn login(email: Str, pwd: Str) -> Result[User, AuthError] ! DB, Crypto {
    let user = find_user(email)?
    let hashed = hash_password(pwd)
    verify(user, hashed)
}

// Public type
pub type AuthError {
    BadCredentials
    AccountLocked
    RateLimited
}

// Private type — implementation detail
type HashedPassword {
    value: Str
    algorithm: Str
}
```

**Why default private:** Locality of reasoning. A private function can be changed without considering external callers. The public surface of a module is explicitly opted-into, making API boundaries clear to both humans and AI agents. An AI scanning a module's API only needs to read `pub` items — everything else is implementation detail it can skip, saving context window space.

### 2.11 Declaration-Site Keyword Arguments

Functions use a `--` separator to divide positional parameters from keyword parameters. Positional params come before `--`, keyword params come after. The function author decides which params are keyword — the caller has no choice. Principle 2 preserved.

#### Syntax

```pact
// Positional only (simple fns, 1-2 params) — no change
fn add(a: Int, b: Int) -> Int { a + b }
add(1, 2)

// Mixed: positional before --, keyword after --
fn transfer(amount: Int, -- from: Account, to: Account) -> Result[Transaction, BankError] {
    // ...
}
transfer(300, from: alice, to: bob)

// All keyword (config-heavy)
fn start_server(-- host: Str = "0.0.0.0", port: Port = 8080, debug: Bool = false) ! Net {
    // ...
}
start_server(port: 3000)

// Keyword args are order-independent at call site
transfer(300, to: bob, from: alice)  // valid, same as above
```

#### Rules

- Params before `--` are **positional**: order matters, no labels at call site
- Params after `--` are **keyword-required**: labels required, order-independent at call site
- Default values only allowed on keyword params (after `--`)
- Default values must be compile-time constants (no mutable default gotcha)
- Labels are **call-site sugar** — the function type is `fn(Int, Account, Account)` regardless of `--`. Closures, trait impls, and higher-order functions are unaffected. See [3.3](#33-type-inference).
- The formatter enforces declaration order at call sites for consistency

**Panel vote: `--` separator won 3-1-1** (3 for `--`, 1 for `;`, 1 for `*`). Labels as call-site sugar (not part of type signature): **5-0 unanimous**. See [DECISIONS.md](../DECISIONS.md).

#### Why `--`

The separator marks a safety boundary between positional and named parameters. It should be visually loud and unmissable. `--` is the most distinctive option — hard to confuse with any other Pact syntax. `;` was rejected because Pact already rejected semicolons as statement terminators; reusing `;` as a param separator would confuse AI models into generating statement-terminator patterns. `*` (Python precedent) was considered too subtle.

#### Why Declaration-Site Control

If the *caller* decides whether to use labels (Python/Kotlin-style optional naming), every call site becomes a style decision: name or don't? This violates Principle 2. With declaration-site control, the function signature determines everything. The AI never chooses between two forms — it reads the signature and generates the one correct form.

#### The Problem This Solves

Positional-only args are safe for 1-2 parameters. At 3+ parameters of the same type, they become error-prone:

```pact
// Without keyword args — which is from, which is to?
transfer(300, alice, bob)   // correct
transfer(300, bob, alice)   // compiles, wrong, silent bug

// With keyword args — swap is impossible
transfer(300, from: alice, to: bob)   // correct
transfer(300, from: bob, to: alice)   // still explicit, reviewer sees intent
```

LLMs swap same-typed positional args at measurable rates (3-8% per call site with 3+ same-typed params). Keyword labels eliminate this class of bug structurally.

### 2.12 Struct Field Defaults

Struct fields can declare default values. When constructing a struct, fields with defaults may be omitted — the default is used.

```pact
type ServerConfig {
    host: Str = "0.0.0.0"
    port: Port = 8080
    debug: Bool = false
    max_connections: Int = 100
}

// Only specify what differs from defaults
let config = ServerConfig { port: 3000, debug: true }
// host defaults to "0.0.0.0", max_connections defaults to 100
```

#### Rules

- Default values must be compile-time constants
- Fields without defaults are always required at construction
- The compiler inserts default values at construction sites — no runtime lookup
- Struct field defaults do not interact with the type system: `ServerConfig` is the same type regardless of which fields were explicitly provided

#### Why Struct Defaults, Not Function Param Defaults

Function parameter defaults interact with closures (does `fn(Int) -> Int` match a function with a defaulted second param?), higher-order functions, and partial application. Struct field defaults are simpler — a struct is always fully constructed before a function sees it. The complexity stays at the construction site, not in the type system.

Struct defaults also serve as the primary **API evolution mechanism**: adding a new field with a default is always backwards-compatible. Existing construction sites continue to compile unchanged.

### 2.13 Struct Construction Shorthand

When a function takes a single struct argument, the type name can be omitted at the call site. The compiler infers it from the parameter type.

```pact
fn start_server(config: ServerConfig) ! Net {
    // ...
}

// Full form (always valid)
start_server(ServerConfig { port: 3000 })

// Shorthand — compiler infers ServerConfig from parameter type
start_server({ port: 3000 })
```

This reduces boilerplate for config-struct patterns without introducing a new calling convention. The function still takes exactly one positional argument — a struct. The shorthand is purely syntactic sugar at the call site.

The shorthand applies only when:
- The function has exactly one parameter at the relevant position
- That parameter's type is a struct (product type)
- The call site uses `{ field: value }` syntax without a type name

When the type is ambiguous (e.g., the parameter is a trait object or generic), the full form is required.

### 2.14 Annotations

Annotations use the `@` prefix and are **compiler-checked** — they are not comments, not decorators, not optional metadata. They participate in type checking, verification, and optimization.

| Annotation | Purpose | Checked |
|------------|---------|---------|
| `@requires(expr)` | Precondition. Must hold when function is called. | Compile-time (SMT) or runtime assertion |
| `@ensures(expr)` | Postcondition. Must hold when function returns. | Compile-time (SMT) or runtime assertion |
| `@where(expr)` | Type-level constraint on generics or refinements. | Compile-time |
| `@i("text")` | Intent declaration. Natural-language description of purpose. | Tracked, versioned, queryable by tooling |
| `@perf(constraint)` | Performance contract. Checked by `pact bench`. | Benchmark runner in CI |
| `@capabilities(list)` | Required runtime capabilities (permissions). | Compile-time capability checking |

#### `@requires` and `@ensures` — Contracts

Preconditions and postconditions form verifiable contracts on function behavior. The compiler attempts static proof via SMT solver. Three outcomes: proven (zero-cost), disproven (compile error with counterexample), or unknown (runtime assertion inserted, warning emitted).

```pact
@requires(list.len() > 0)
@ensures(result <= list.len() - 1)
fn binary_search[T: Ord](list: List[T], target: T) -> Int? {
    // ...
}
```

The `@ensures` clause can reference `result` (the return value) and any parameter. Contract violations produce structured diagnostics the AI can act on directly.

#### `@where` — Type Constraints

Constrains generic parameters or refines types beyond what trait bounds express.

```pact
@where(N > 0)
fn chunks[T](list: List[T], n: Int) -> List[List[T]] {
    // compiler knows n > 0 — no division-by-zero possible
}
```

#### `@i` — Intent

Bridges human intent and machine implementation. Structured, versioned, and queryable through the compiler-as-service API.

```pact
@i("Fetch active users who logged in within the last 30 days, sorted by recency")
pub fn recent_active_users() -> List[User] ! DB {
    // ...
}
```

Intent declarations are not prose comments — they occupy a fixed position, are tracked through version control, and can be queried semantically (`ast.query(intent_contains: "active users")`). If the intent changes but the implementation doesn't (or vice versa), tooling flags it for review.

#### `@perf` — Performance Contracts

Declares performance expectations checked by the benchmark runner.

```pact
@perf(p99 < 200ms)
@perf(memory < 50mb)
pub fn process_batch(items: List[Item]) -> Summary ! DB, IO {
    // ...
}
```

`pact bench --check-contracts` runs benchmarks and fails if any `@perf` constraint is violated. This integrates into CI — performance regressions are caught the same way type errors are.

#### `@capabilities` — Runtime Permissions

Declares what system capabilities a function (or module) requires. The compiler verifies that callers have the necessary capabilities.

```pact
@capabilities(net, fs.read)
pub fn download_file(url: Str, dest: Str) -> Result[(), IOError] ! IO, Net {
    // ...
}
```

This enables sandboxing and least-privilege enforcement at the language level. A module declared with `@capabilities(net)` cannot perform filesystem operations, even if it has `! IO` in scope.

#### Annotation Placement

Annotations attach to the item immediately following them. Multiple annotations stack.

```pact
@capabilities(db, crypto)
@i("Main authentication flow")
@requires(email.len() > 0)
@ensures(result.is_ok() => result.unwrap().token.is_valid())
@perf(p99 < 200ms)
pub fn login(email: Str, pwd: Str) -> Result[Session, AuthError] ! DB, Crypto {
    // ...
}
```

The canonical ordering enforced by `pact fmt` is: `@capabilities` first (permissions), then `@i` (intent), then `@requires`/`@ensures` (contracts), then `@where` (type constraints), then `@perf` (performance). See section 11.1 for the complete ordering across all 14 annotation types.

### 2.15 Scoped Resources (`with...as`)

The `with...as` construct binds a `Closeable` value to a name and guarantees cleanup when the block exits — whether by normal completion, `?` early return, or any other exit path.

```pact
// Single resource
with fs.open("data.txt")? as file {
    let data = fs.read(file)?
    transform(data)
}

// Multiple resources — LIFO cleanup order
with fs.open("in.txt")? as src, fs.create("out.txt")? as dst {
    let data = fs.read(src)?
    fs.write(dst, data)?
}
```

`with...as` is an expression. The block's value is its last expression, same as any other block.

```pact
let data = with fs.open("cache.dat")? as f {
    fs.read(f)?
}
```

#### Disambiguation with effect handlers

The `with` keyword serves two roles. The compiler distinguishes them by the presence of `as`:

| Form | Meaning |
|------|---------|
| `with handler_expr { }` | Effect handler — no `as`, expression type is `Handler[E]` |
| `with expr as name { }` | Scoped resource — has `as`, expression type implements `Closeable` |

Both forms compose in the same `with` statement via comma:

```pact
with mock_db(fixtures), fs.open("data.txt")? as f {
    let data = fs.read(f)?
    process(data)
}
```

Here `mock_db(fixtures)` is an effect handler (no `as`) and `f` is a scoped `Closeable` resource.

#### Rules

- The `?` in `with expr? as name` propagates BEFORE the scope — if acquisition fails, no cleanup needed
- `Closeable` bindings cannot escape the `with` block (compile error E0601)
- `Closeable` bindings cannot be stored in fields or collections within the block (compile error E0602)
- Multiple resources clean up in LIFO order (reverse declaration order)
- Partial acquisition: if `expr2` fails via `?`, only resources from earlier bindings are cleaned up
