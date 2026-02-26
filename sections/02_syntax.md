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
| If/else | Expression, no parens | Always an expression. No parentheses around condition. Else mandatory when value is used. No `if let`. See [2.9](#29-ifelse-expressions). |
| While/loop | `while` and `loop` | `while cond { }` for conditional, `loop { }` for unconditional. Plain `break`/`continue`. No labels, no `while let`. See [2.11](#211-whileloop). |
| Visibility | `pub` keyword | Public items use `pub`. Everything else is module-private. See [2.12](#212-visibility). |
| Scoped resources | `with expr as name { }` | Deterministic resource cleanup. `Closeable` trait + LIFO close order. Reuses `with` from effect handlers; `as` disambiguates. 3-0 over `defer`. |
| Constants | `const NAME = expr` | Compile-time constants. Distinct from `let` (runtime). Literals + arithmetic + boolean ops + references to other consts. See [2.20](#220-const-declarations). |
| Tests | `test "name" { }` | First-class syntax. Pure by default (no implicit effects). Four built-in assertions. `panic()` for unreachable states. Module-scoped tests access private items. `@tags(...)` for filtering. See [2.19](#219-test-blocks). |

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

**Escape sequences.** Strings support the following backslash escapes:

| Escape | Produces |
|--------|----------|
| `\n` | newline |
| `\r` | carriage return |
| `\t` | tab |
| `\\` | literal `\` |
| `\"` | literal `"` |
| `\{` | literal `{` (suppresses interpolation) |
| `\}` | literal `}` |

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

#### Capture Semantics

Closures capture variables from enclosing scope by **shared reference**. All captures — immutable (`let`) and mutable (`let mut`) — share the original binding. In a GC'd language, "shared reference" means the closure holds a GC pointer to the same value as the enclosing scope. No explicit capture syntax is needed. No `move` keyword, no capture lists.

```pact
let threshold = 10
let above = items.filter(fn(x) { x > threshold })  // captures threshold

let mut count = 0
items.for_each(fn(x) {
    if x > threshold { count += 1 }
})
io.println("Found {count}")  // prints the actual count, not 0
```

**Immutable captures.** For `let` bindings, shared reference is observationally equivalent to by-value copy — the value never changes, so there is no difference. The optimizer may inline or copy the value freely.

**Mutable captures.** For `let mut` bindings, mutations through the closure are visible in the enclosing scope and vice versa. The compiler heap-allocates (boxes) the mutable binding into a shared cell so closure and outer scope share it. Escape analysis eliminates this boxing when the closure does not outlive the enclosing scope.

```pact
let mut total = 0
let mut errors = 0
results.for_each(fn(r) {
    match r {
        Ok(v) => total += v
        Err(_) => errors += 1
    }
})
io.println("Total: {total}, Errors: {errors}")  // both reflect actual values
```

**Snapshot idiom.** When you want a copy independent of future mutations, bind to a new `let`:

```pact
let mut count = 0
let snapshot = count  // explicit copy
let f = fn() { snapshot }  // captures immutable snapshot
count = 42
// f() == 0, count == 42
```

**Capture does not affect the function type.** A closure `fn(Int) -> Bool` that captures mutable variables has the same type as one that captures nothing. Captures are part of the closure's *value*, not its *type*. Higher-order functions, trait implementations, and type inference are unaffected by captures.

#### Closures and `async.spawn`

Closures passed to `async.spawn` **cannot capture `let mut` bindings**. Mutable captures would create data races between the spawned task and the enclosing scope. This is a compile error:

```pact
let mut count = 0
async.spawn(fn() { count += 1 })  // COMPILE ERROR E0650
```

```
error[MutableCaptureInSpawn]: mutable binding captured in spawned task
 --> app.pact:3:18
  |
1 | let mut count = 0
  |         ----- mutable binding declared here
3 | async.spawn(fn() { count += 1 })
  |             ^^^    ^^^^^ mutable capture not permitted in spawn
  |
  = note: spawned tasks cannot share mutable state — data race risk
  = help: copy the value before spawning, or use a channel:
  |
  | let snapshot = count
  | async.spawn(fn() { use(snapshot) })
```

Immutable captures in `async.spawn` are safe — the GC keeps the value alive, and no mutation means no data race:

```pact
let data = prepare_data()
async.spawn(fn() {
    process(data)  // OK: data is immutable, shared GC pointer
})
```

For inter-task communication with mutable state, use channels:

```pact
let ch = channel.new[Int](buffer: 10)
async.spawn(fn() {
    ch.send(compute_result())  // explicit communication, no shared mutation
})
```

#### Closures and Scoped Resources

Closure captures compose with `Closeable` and arena escape rules. A closure that captures a `Closeable` binding cannot escape the `with...as` scope — this is already enforced by E0601:

```pact
with fs.open("data.txt")? as file {
    // OK: closure used synchronously, does not escape scope
    let lines = items.map(fn(item) { format_with(item, file) })

    // ERROR E0601: closure escapes, taking `file` with it
    return fn() { fs.read(file) }
}
```

Same logic applies to arena-allocated values — closures capturing arena bindings cannot escape the arena scope (E0700).

#### Capture Rules Summary

- All captures are **shared reference** (GC pointer to same binding)
- `let` captures: immutable, observationally equivalent to copy
- `let mut` captures: mutations visible across closure boundary
- No explicit capture syntax (no `move`, no capture lists)
- `async.spawn` closures: immutable captures only. `let mut` captures are compile error E0650
- `Closeable`/arena captures: existing escape rules (E0601/E0700) apply transitively through closures
- Capture mode is not part of the function type

**Panel vote:** Shared reference 3-2 (PLT/AI/DevOps for shared; Sys/Web for by-value). No explicit syntax 4-1 (DevOps dissented for `move`). Spawn restriction 3-2 (PLT/DevOps/AI for compile error; Sys/Web for auto-copy). See [DECISIONS.md](../DECISIONS.md).

### 2.9 If/Else Expressions

`if`/`else` is an expression — it evaluates to a value, like `match` and `with...as`. No parentheses around the condition (consistent with `for` loops). Braces required.

```pact
// Expression — both branches must return the same type
let status = if user.active { "online" } else { "offline" }

// Statement — value discarded, type is (), else optional
if amount <= 0 {
    return Err(AccountError.InvalidAmount)
}

// Else-if chains
let tier = if score >= 90 { "gold" }
    else if score >= 70 { "silver" }
    else { "bronze" }

// As the last expression in a function (implicit return)
fn abs(n: Int) -> Int {
    if n < 0 { -n } else { n }
}

// Inside match arms
match expr {
    Div(l, r) => {
        let divisor = eval(r)?
        if divisor == 0.0 {
            Err(CalcError.DivisionByZero)
        } else {
            Ok(eval(l)? / divisor)
        }
    }
}
```

#### Rules

- **Expression context** (let binding, return, argument): `else` is required. Both branches must unify to the same type. Missing `else` is a compile error.
- **Statement context** (value discarded): `else` is optional. The expression type is `()`. If `else` is present, both branches must be `()`.
- **No parentheses** around the condition. The condition is delimited by `if` and `{`. Sub-expression grouping with `()` inside the condition is normal expression syntax, not part of `if`.
- **No truthiness.** The condition must be `Bool`. `if 0 { }` and `if items { }` are compile errors. See [2.18](#218-operator-precedence--semantics).
- **No `if let`** for v1. Use `match` for pattern-based control flow, `??` for Option defaulting. Revisitable in v2 if `match` with single-arm + wildcard proves painful in practice.

**Panel vote: 5-0 unanimous** on all four sub-questions — if/else as expression, else required in expression context, no if-let for v1, parentheses forbidden. See [DECISIONS.md](../DECISIONS.md) for full deliberation.

### 2.10 For-Loops

```pact
for x in collection {
    process(x)
}
```

Iterates over any type implementing `IntoIterator` (§3c.1). No parentheses around the header. Braces required.

The compiler desugars `for x in expr { body }` to:

```pact
let mut __iter = expr.into_iter()
loop {
    match __iter.next() {
        Some(x) => { body }
        None => break
    }
}
```

`break` exits the loop. `continue` skips to the next `__iter.next()` call.

**Ranges:**

```pact
for i in 0..100 { }      // exclusive: 0 to 99
for n in 1..=100 { }     // inclusive: 1 to 100
```

`..` is exclusive upper bound, `..=` is inclusive. Ranges are lazy iterables of type `Range[T: Ord]` which implements `IntoIterator`.

No comprehensions in v1 — `for` loops and method chaining (`.map()`, `.filter()`, `.collect()`) cover the same use cases. See §3c.1 for the full iterator protocol.

**Panel vote: 5-0 ratified.** See [OPEN_QUESTIONS.md](../OPEN_QUESTIONS.md) 2.3, 2.4.

### 2.11 While/Loop

Two loop constructs for two distinct intents. `while` for conditional looping — keep going until the condition is false. `loop` for unconditional looping — run forever unless explicitly broken out of. No parentheses around the condition (consistent with `if` and `for`). Braces required.

```pact
// Conditional loop — checks before each iteration
while queue.has_next() {
    let item = queue.pop()?
    process(item)
}

// Retry with backoff
let mut attempts = 0
while attempts < max_retries {
    match try_connect(host) {
        Ok(conn) => return Ok(conn)
        Err(_) => {
            attempts += 1
            async.sleep(backoff(attempts))
        }
    }
}

// Infinite loop — event loop, server accept, REPL
loop {
    let event = events.next()
    match event {
        Event.Shutdown => break
        Event.Request(req) => handle(req)
    }
}

// Polling until a condition
let mut result = None
loop {
    let status = check_status()?
    if status.is_ready() {
        result = Some(status)
        break
    }
    async.sleep(poll_interval)
}
```

#### `break` and `continue`

`break` exits the innermost loop. `continue` skips to the next iteration. Both are statements — no break-with-value for v1.

```pact
for item in items {
    if item.is_skip() {
        continue
    }
    if item.is_done() {
        break
    }
    process(item)
}
```

`break` and `continue` work identically in `for`, `while`, and `loop`.

#### Rules

- **No parentheses** around the `while` condition. Delimited by `while` and `{`.
- **No truthiness.** The condition must be `Bool`. `while 1 { }` is a compile error.
- **Statement semantics.** Both `while` and `loop` evaluate to `()`. They are not expressions — you cannot `let x = while ... { }` or `let x = loop { }`. This is consistent with `for` loops.
- **No break-with-value** for v1. Use `let mut` + assign + `break` pattern. Revisitable in v2 if expression-oriented loops prove necessary.
- **No labeled breaks.** Nested loop exit uses extracted functions with early `return`. Labels are a backward-compatible addition if demand materializes.
- **No `while let`.** Consistent with `if let` rejection (5-0). Use `loop { match ... { P => body, _ => break } }` for pattern-based looping.
- **Linter recommendation:** `while true { }` should be written as `loop { }`. The linter warns and auto-fixes.

**Panel vote:** Both constructs 3-2. Plain break/continue 3-2. No labels 4-1. No while-let 5-0. See [DECISIONS.md](../DECISIONS.md).

### 2.12 Visibility

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

### 2.12.1 Module-Level Bindings

Module-level `let` and `let mut` declare module-scoped bindings. These follow different rules from function-local bindings:

**Duplicate names are a compile error.** A module may not declare two `let` bindings with the same name. Module scope is a flat namespace — there is no inner scope for shadowing to inhabit, so "redeclaration" has no well-defined semantics. The compiler reports `DuplicateModuleBinding` (E1004).

```pact
// Valid — each name is unique
let max_retries = 3
let mut request_count = 0

// INVALID — compile error E1004
let x = 1
let x = 2  // error[DuplicateModuleBinding]: duplicate module-level binding `x`
```

**`pub let` exports immutable bindings.** A module-level `let` (without `mut`) can be marked `pub` to make it importable by other modules. For compile-time constants, prefer `const` (see [2.20](#220-const-declarations)) — `let` at module level is for runtime-initialized values.

**`pub let mut` is forbidden.** Mutable module-level state must not be directly exposed to other modules. The compiler tracks which functions write to module-level `let mut` bindings via mutation analysis (see §4.16). The compiler reports `PubLetMutForbidden` (E1006).

```pact
// Compile-time constants — prefer const (§2.20)
pub const api_version = "2.0"
pub const default_timeout = 30

// Runtime module state — use let
let mut connection_count = 0

// INVALID — compile error E1006
pub let mut shared_counter = 0  // error[PubLetMutForbidden]: `pub let mut` is forbidden
                                // help: expose mutable state through functions with effect tracking
```

**Function-local shadowing is unaffected.** Within function bodies, `let` shadowing remains allowed (§2.2). This distinction reflects different scoping models: function bodies use sequential lexical scoping (each `let` opens a new scope), while modules use a flat namespace (all bindings coexist).

```pact
let x = 1  // module-level

fn transform(x: Int) -> Int {
    let x = x * 2    // OK — function-local shadowing
    let x = x + 1    // OK — sequential lexical scope
    x
}
```

### 2.13 Declaration-Site Keyword Arguments

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
- Default values must be const expressions (see [2.20](#220-const-declarations))
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

### 2.14 Struct Field Defaults

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

- Default values must be const expressions (see [2.20](#220-const-declarations))
- Fields without defaults are always required at construction
- The compiler inserts default values at construction sites — no runtime lookup
- Struct field defaults do not interact with the type system: `ServerConfig` is the same type regardless of which fields were explicitly provided

#### Why Struct Defaults, Not Function Param Defaults

Function parameter defaults interact with closures (does `fn(Int) -> Int` match a function with a defaulted second param?), higher-order functions, and partial application. Struct field defaults are simpler — a struct is always fully constructed before a function sees it. The complexity stays at the construction site, not in the type system.

Struct defaults also serve as the primary **API evolution mechanism**: adding a new field with a default is always backwards-compatible. Existing construction sites continue to compile unchanged.

### 2.15 Struct Construction Shorthand

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

### 2.16 Annotations

Annotations use the `@` prefix and are **compiler-checked** — they are not comments, not decorators, not optional metadata. They participate in type checking, verification, and optimization.

| Annotation | Purpose | Checked |
|------------|---------|---------|
| `@requires(expr)` | Precondition. Must hold when function is called. | Compile-time (SMT) or runtime assertion |
| `@ensures(expr)` | Postcondition. Must hold when function returns. | Compile-time (SMT) or runtime assertion |
| `@where(expr)` | Type-level constraint on generics or refinements. | Compile-time |
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
@requires(email.len() > 0)
@ensures(result.is_ok() => result.unwrap().token.is_valid())
@perf(p99 < 200ms)
pub fn login(email: Str, pwd: Str) -> Result[Session, AuthError] ! DB, Crypto {
    // ...
}
```

The canonical ordering enforced by `pact fmt` is: `@capabilities` first (permissions), then `@requires`/`@ensures` (contracts), then `@where` (type constraints), then `@perf` (performance). See section 11.1 for the complete ordering across all 13 annotation types.

### 2.17 Scoped Resources (`with...as`)

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

---

### 2.18 Operator Precedence & Semantics

#### Precedence Table

From lowest to highest binding:

| Precedence | Operators | Associativity | Category |
|:----------:|-----------|:-------------:|----------|
| 1 (lowest) | `\|>` | left | pipe |
| 2 | `??` | right | coalesce |
| 3 | `\|\|` | left | logical or (short-circuit) |
| 4 | `&&` | left | logical and (short-circuit) |
| 5 | `==` `!=` | left | equality |
| 6 | `<` `>` `<=` `>=` | left | comparison |
| 7 | `+` `-` | left | additive |
| 8 | `*` `/` `%` | left | multiplicative |
| 9 | `-` `!` | right | unary prefix |
| 10 | `?` | left | postfix unwrap |
| 11 (highest) | `.` `()` | left | member access, call |

**Non-chaining comparisons.** `a < b < c` is a compile error. The compiler suggests `a < b && b < c`. Chained comparisons introduce context-sensitive operator semantics that contradict Pact's unambiguous-parsing priority. (Vote: 4-1)

#### Operator Desugaring

All operators either desugar to trait method calls or are language primitives.

**Arithmetic** — `+`, `-`, `*`, `/`, `%`, and unary `-` desugar to trait methods (Add, Sub, Mul, Div, Rem, Neg). Arithmetic traits are sealed — only built-in numeric types implement them. Full trait definitions in §3.6.

```pact
// x + y  desugars to  Add.add(x, y)
// x - y  desugars to  Sub.sub(x, y)
// x * y  desugars to  Mul.mul(x, y)
// x / y  desugars to  Div.div(x, y)
// x % y  desugars to  Rem.rem(x, y)
// -x     desugars to  Neg.neg(x)
```

Operands must be the same type. Mixed-type arithmetic (`Int + Float`) is a compile error — use explicit conversion: `x.to_float() + y`. (Vote: 5-0)

**Equality** — `==` and `!=` desugar to `Eq.eq` and `Eq.ne`. Any type can implement `Eq`. See §3.6.

**Comparison** — `<`, `>`, `<=`, `>=` desugar via `Ord.cmp` returning `Ordering`. Any type can implement `Ord`. See §3.6.

**Boolean operators** — `&&`, `||`, `!` are language primitives, not trait-dispatched. They require `Bool` operands. Short-circuit: the right operand of `&&` is only evaluated when the left is `true`; the right operand of `||` is only evaluated when the left is `false`. (Vote: 5-0)

```pact
if user.is_admin() || expensive_check(user) {
    grant_access()
}
```

**`?` and `??`** are language primitives for `Result`/`Option`. Already specified in §3.5.

**`|>`** is the pipe operator. Already specified in §2.10.

#### No Truthiness

Only `true` and `false` are `Bool` values. There is no implicit conversion to `Bool`.

```pact
if 0 { }           // compile error: expected Bool, got Int
if items { }       // compile error: expected Bool, got List[T]

if items.len() > 0 { }    // correct: explicit Bool expression
if name.is_empty() { }    // correct: method returns Bool
```

Every language defines truthiness differently — Python, JS, and Ruby all disagree on what's falsy. LLMs cross-contaminate these rules at high rates. Requiring explicit `Bool` eliminates the bug class. (Vote: 5-0)

#### Assignment Operators

`+=`, `-=`, `*=`, `/=`, `%=` are syntactic sugar for reassignment with the corresponding operator:

```pact
let mut count = 0
count += 1       // desugars to: count = count + 1
count *= 2       // desugars to: count = count * 2
```

Only valid on `let mut` bindings. Desugaring is purely syntactic — `x += rhs` becomes `x = x + rhs` before type checking. (Vote: 5-0)

#### String Concatenation

`+` does **not** work on `Str`. Use interpolation or `.concat()`.

```pact
let full = first + " " + last   // compile error: Str does not implement Add

let full = "{first} {last}"              // interpolation (preferred)
let full = first.concat(" ").concat(last) // .concat() for dynamic cases
```

String `+` encourages O(n²) loops, creates ambiguity with numeric `+`, and violates Principle 2 when interpolation already exists. (Vote: 5-0)

### 2.19 Test Blocks

Tests are first-class syntax — `test` blocks are part of the grammar, understood by the parser, type-checked by the compiler, and run by the built-in test runner. No test framework to import.

```pact
test "add returns sum" {
    assert_eq(add(1, 2), 3)
    assert_eq(add(-1, 1), 0)
    assert_eq(add(0, 0), 0)
}

test "add is commutative" {
    prop_check(fn(a: Int, b: Int) {
        assert_eq(add(a, b), add(b, a))
    })
}
```

#### Syntax

```
test "description string" { body }
```

- `test` is a keyword. The description is a `Str` literal (no interpolation — must be a static string for test discovery).
- The body is a block expression evaluated by the test runner.
- `test` blocks are top-level declarations (peers of `fn`, `type`, etc.) or may appear inside `mod { }` blocks.
- Test names must be unique within their module scope. Duplicate names are a compile error.
- Tests are stripped from release builds. They exist only when compiled with `pact test`.

#### Effect Model: Pure by Default

Test blocks have **no implicit effects**. A test that calls an effectful function without a handler is a compile error — the same rule as any other function with an empty effect row. Effect handlers within the body introduce effects locally.

```pact
// Pure test — no effects needed
test "deposit increases balance" {
    let acct = open_account(1, "Test")
    let result = deposit(acct, 500)
    assert(result.is_ok())
    assert_eq(result.unwrap().balance, 500)
}

// Effectful test — handlers provide effects explicitly
test "fetch with mock" {
    with mock_net(responses) {
        let result = fetch_data("https://example.com")
        assert_eq(result.unwrap(), "ok")
    }
}

// Multiple effect handlers compose via with
test "integration test with shared environment" {
    with mock_db(fixtures), capture_log([]) {
        run_migration()
        assert_eq(get_user(1).unwrap().name, "Alice")
    }
}
```

This is consistent with Pact's effect system design — effects are explicit, never hidden. The compiler produces actionable errors when a test calls effectful code without a handler:

```
error[UnhandledEffectInTest]: unhandled effect `Net` in test "fetch data"
  --> src/api.pact:45:9
   |
45 |     let result = fetch_data(url)
   |                  ^^^^^^^^^^ `fetch_data` requires `! Net`
   |
   = hint: wrap in `with mock_net(...) { ... }` to provide a handler
```

Pure-by-default enables the compiler to safely parallelize test execution — tests with no effect handlers are guaranteed side-effect-free.

**Panel vote: 5-0 unanimous** for pure by default. See [DECISIONS.md](../DECISIONS.md).

#### Built-in Assertions

Four assertion functions are compiler built-ins, available in any test block without import:

| Function | Signature | On failure |
|----------|-----------|------------|
| `assert(expr)` | `fn assert(cond: Bool, msg: Str = "")` | Panics with source location and sub-expression values |
| `assert_eq(a, b)` | `fn assert_eq[T: Eq + Display](left: T, right: T, msg: Str = "")` | Panics with both values displayed |
| `assert_ne(a, b)` | `fn assert_ne[T: Eq + Display](left: T, right: T, msg: Str = "")` | Panics with the duplicated value displayed |
| `assert_matches(expr, pat)` | `fn assert_matches[T](expr: T, pattern)` | Panics with actual value and expected pattern |

All assertions accept an optional trailing message for additional context. The message is a regular `Str` — Pact's universal string interpolation applies:

```pact
test "assertions demo" {
    assert(user.is_active())
    assert_eq(account.balance, 500, "after depositing {amount}")
    assert_ne(token_a, token_b)
    assert_matches(withdraw(acct, 9999), Err(BankError.InsufficientFunds))
}
```

**Note:** `assert_matches` is a compiler intrinsic whose second argument is a **pattern** (same syntax as `match` arms), not an expression. It cannot be passed as a higher-order function.

Assertion failure panics — unwinding to the test runner, which marks the test as failed and continues running other tests. This is the one context where Pact uses panic semantics, since tests are controlled environments where unwinding is safe.

**Panel vote: 4-1** for three built-ins (original §2.19 vote). PLT dissented (assert_ne is `assert(a != b)` — Principle 2 violation). See [DECISIONS.md](../DECISIONS.md). Testing framework deliberation added `assert_matches` (4-1, AI/ML dissented) and optional messages (3-2). See [DECISIONS.md](../DECISIONS.md).

#### `panic()` Function

`panic(msg: Str) -> Never` is a built-in available in all code — not just tests. It triggers an unwind with the given message. In test blocks, the test runner catches the unwind and marks the test as failed. In production code, panic terminates the process with a stack trace.

```pact
fn divide(a: Int, b: Int) -> Int {
    if b == 0 { panic("division by zero") }
    a / b
}
```

`panic` returns `Never` (bottom type), which inhabits every type — allowing it in any expression position. Panic is *not* an algebraic effect — it is untracked divergence, like integer division by zero or array bounds violations. It cannot be caught or handled in normal code (only the test runner catches it).

**Use `Result[T, E]` for recoverable errors.** `panic` is reserved for programmer errors, violated invariants, and genuinely unreachable states. A lint warns when `panic()` appears in library code.

**Panel vote: 5-0 unanimous.** See [DECISIONS.md](../DECISIONS.md).

#### Assertion Failure Output

Assertion failures use **expression introspection** (Power Assert style). The compiler captures the source text, file/line/col, and decomposes sub-expressions to show their values:

```
assertion failed: assert(account.balance > minimum)
  account.balance = 450
  minimum = 500
  --> src/bank.pact:43:5
```

For `assert_eq` and `assert_ne`, the output uses left/right labels since both arguments are already fully displayed:

```
assertion failed: assert_eq(result, Ok(500))
  left:  Err(InsufficientFunds { deficit: 499 })
  right: Ok(500)
  --> src/bank.pact:44:5
```

For `assert_matches`, the output shows the actual value and expected pattern:

```
assertion failed: assert_matches(result, Err(BankError.InsufficientFunds))
  value:   Ok(500)
  pattern: Err(BankError.InsufficientFunds)
  --> src/bank.pact:45:5
```

When a custom message is provided, it appears as additional context:

```
assertion failed: assert_eq(result, Ok(500))
  message: after depositing 1000 into account A-42
  left:  Err(InsufficientFunds { deficit: 499 })
  right: Ok(500)
  --> src/bank.pact:44:5
```

Expression introspection is bounded to one level of sub-expressions (direct operands and field accesses, not recursive descent into nested calls). The message expression is evaluated only on failure. In JSON output (`pact test --json`), introspection values appear in an `introspection` field alongside `assertion`, `expected`/`actual`, and `span`.

The test runner distinguishes assertion failures (`"status": "failed"`) from unexpected panics (`"status": "panicked"`) in structured output, enabling CI to categorize "test found a bug" vs "test itself is broken."

**Panel vote: 4-1** for expression introspection. PLT dissented (left/right is structurally honest; introspection is ad-hoc compiler analysis). Majority: compiler already has the AST, introspection is zero-cost on the hot path (failure code is cold), and sub-expression values dramatically improve debugging. See [DECISIONS.md](../DECISIONS.md).

#### Property-Based Testing

`prop_check` is a built-in for property-based testing. It generates random inputs based on the closure's parameter types and runs the body repeatedly.

```pact
test "sort is idempotent" {
    prop_check(fn(list: List[Int]) {
        assert_eq(sort(sort(list)), sort(list))
    })
}
```

`prop_check` is available in test blocks without import. The compiler infers generator strategies from parameter types. Run property tests specifically with `pact test --prop`.

#### Test Scope

Test blocks can appear at the top level of a file or inside `mod { }` blocks. Tests inside a module see that module's private items — enabling verification of internal invariants without exposing implementation details.

```pact
mod auth {
    fn hash_password(pwd: Str) -> Str {
        // private implementation detail
    }

    pub fn verify(pwd: Str, hash: Str) -> Bool {
        hash_password(pwd) == hash
    }

    test "hash_password produces consistent output" {
        let h1 = hash_password("secret")
        let h2 = hash_password("secret")
        assert_eq(h1, h2)
    }
}

// Top-level test — can only access pub items
test "verify rejects wrong password" {
    assert(!auth.verify("wrong", "expected_hash"))
}
```

The scoping rule is uniform: a `test` block inside `mod M` sees `M`'s private namespace, same as any `fn` inside `M`. No special visibility modifiers needed.

**Panel vote: 4-1** for module-scoped tests. AI/ML dissented (flat is more reliable for LLM generation; nested placement adds decision point). Majority: testing private invariants is critical and the alternative — making internals `pub` or adding `pub(test)` — is worse. See [DECISIONS.md](../DECISIONS.md).

#### Discovery & Filtering

Tests are discovered at compile time — the compiler knows every `test` block's name, module path, file location, and tags.

```pact
@tags("slow", "integration")
test "full order flow" {
    with mock_db(fixtures), mock_payment() {
        let result = place_order(sample_order())
        assert(result.is_ok())
    }
}
```

The `@tags(...)` annotation attaches string tags to a test block for structured filtering. Tags are compile-time metadata — zero runtime cost, stripped with test bodies in release builds.

**CLI filtering:**

```sh
pact test                           # run all tests
pact test --filter "deposit"        # name substring match
pact test auth/                     # run tests in auth/ module path
pact test --tag unit                # run tests tagged "unit"
pact test --tag slow --exclude      # run all tests EXCEPT tagged "slow"
pact test --prop                    # run property tests only
pact test --json                    # structured JSON output
```

**Panel vote: 4-1** for annotation tags. AI/ML dissented (tags are metadata LLMs forget; name conventions suffice). Majority: structured tag filtering is day-one CI infrastructure; without it, teams hack naming conventions. See [DECISIONS.md](../DECISIONS.md).

#### Skipping Tests

Pact provides two skip mechanisms for two fundamentally different use cases: compile-time unconditional skip via annotation, and runtime conditional skip via built-in function.

**`@skip` annotation — unconditional, compile-time:**

```pact
@skip
test "not implemented yet" {
    assert_eq(unimplemented_feature(), 42)
}

@skip("waiting on async support")
test "async test" {
    // ...
}
```

`@skip` takes an optional reason string. The compiler still type-checks the test body (catching errors in skipped tests during refactors), but the test runner does not execute it. Skipped tests appear in output with status `"skipped"`.

When both `@tags` and `@skip` are present, `@tags` comes first:

```pact
@tags("integration")
@skip("DB migration pending")
test "full order flow" {
    // ...
}
```

**`skip()` function — conditional, runtime:**

```pact
test "platform specific" {
    if !is_linux() {
        skip("only runs on Linux")
    }
    assert(check_platform_feature())
}
```

`skip(reason: Str) -> Never` is a built-in available in test blocks. It unwinds to the test runner (same machinery as assertion failure panics) and marks the test as `"skipped"` with the given reason. Use `skip()` for decisions that depend on runtime state: platform detection, environment variables, feature flags.

**When to use which:**

| Situation | Mechanism |
|-----------|-----------|
| WIP / not yet implemented | `@skip("reason")` |
| Broken, will fix later | `@skip("reason")` |
| Platform-specific | `skip()` with condition |
| Requires specific environment | `skip()` with condition |

**JSON output for skipped tests:**

```json
{"name": "async test", "status": "skipped", "reason": "waiting on async support"}
```

Both `@skip` and `skip()` produce the same `"skipped"` status in JSON output. The `"skipped"` count in the summary reflects both.

**Panel vote: 3-2** for both mechanisms. PLT and AI/ML dissented (wanted `@skip` only — Principle 2 concern). Majority: compile-time and runtime skips are fundamentally different evaluation times; conflating them forces either losing zero-cost static skipping or losing runtime conditional skipping. See [DECISIONS.md](../DECISIONS.md).

#### Doc-Tests

Code examples in `///` doc comments are compiled and run as tests:

```pact
/// Parses a string to an integer.
///
/// ```
/// assert_eq(parse_int("42"), Ok(42))
/// assert_eq(parse_int("nope"), Err(ParseError))
/// ```
fn parse_int(s: Str) -> Result[Int, ParseError] {
    // ...
}
```

Doc-tests verify that documentation stays in sync with implementation. They are run by `pact test` alongside regular test blocks.

#### Rules Summary

- `test` is a keyword — first-class syntax, not a macro or library
- Test names are static `Str` literals (no interpolation)
- Pure by default — no implicit effects. Use `with` handlers for effectful tests
- Four built-in assertions: `assert`, `assert_eq`, `assert_ne`, `assert_matches`
- All assertions accept an optional trailing `Str` message for context
- `assert_matches` takes a pattern (not an expression) as its second argument
- Assertion failure panics (unwind to test runner, expression introspection on failure)
- `panic(msg: Str) -> Never` available everywhere — untracked divergence, not an effect
- Test runner distinguishes assertion failures from unexpected panics in JSON output
- `prop_check` built-in for property-based testing
- Tests can appear top-level or inside `mod { }` (private access)
- `@tags(...)` annotation for structured filtering
- `@skip` annotation for unconditional compile-time skip (body still type-checked)
- `skip(reason: Str) -> Never` built-in for conditional runtime skip
- Stripped from release builds
- JSON structured output via `pact test --json`

### 2.20 Const Declarations

The `const` keyword declares compile-time constants. Unlike `let` (runtime-initialized, immutable), `const` bindings are evaluated by the compiler during compilation and their values are substituted at every use site. The right-hand side must be a **const expression**.

```pact
const MAX_RETRIES = 5
const TIMEOUT_MS = 30 * 1000
const API_VERSION = "2.1.0"
const DEFAULT_HOST = "0.0.0.0"
const MAX_PAYLOAD = 1024 * 1024 * 10
const DEBUG = false
```

#### Const Expressions

A **const expression** is built from a closed set of operations that the compiler can evaluate without executing the program:

| Category | What's Allowed | Examples |
|----------|---------------|----------|
| Scalar literals | `Int`, `Float`, `Str`, `Bool`, `Char`, `None` | `42`, `3.14`, `"hello"`, `true`, `'x'`, `None` |
| Arithmetic | `+`, `-`, `*`, `/`, `%`, unary `-` | `1024 * 64`, `TIMEOUT / 3` |
| Boolean | `&&`, `\|\|`, `!` | `true && !DEBUG` |
| Comparison | `==`, `!=`, `<`, `>`, `<=`, `>=` | `MAX > 0` |
| Const references | Other `const` bindings by name | `MAX_PAYLOAD * 2` |
| Struct literals | Struct construction with all-const fields | `ServerConfig { port: 8080 }` |
| Enum variants | Variant construction with const payloads | `LogLevel.Info`, `Some(42)` |

What is **not** a const expression:

- Function calls: `some_fn()` — even pure functions
- Method calls: `"hello".len()` — methods are function calls
- `let` bindings: referencing a `let` variable is not const
- Collection constructors: `List.new()`, `Map.new()` — these allocate
- Mutable state: anything involving `let mut`

```pact
// Valid const expressions
const BUFFER_SIZE = 1024 * 64
const ENABLED = true && !DEBUG
const HALF_TIMEOUT = TIMEOUT_MS / 2

// NOT valid — compile errors
// const BAD1 = "hello".len()       // error[NonConstExpr]: method calls not allowed
// const BAD2 = compute_max()       // error[NonConstExpr]: function calls not allowed
// const BAD3 = some_let_binding    // error[NonConstExpr]: `let` bindings are not const
```

**Purity does not imply constness.** A pure function (no `!` annotation) is effect-free at runtime, but is not const-evaluable. Const evaluation is a separate, narrower concept — it means "the compiler can compute this during compilation using a fixed set of total operations." Extending to `const fn` is a potential v2 feature; v1 keeps the boundary syntactically obvious.

#### Struct and Enum Constants

Struct literal syntax and enum variant construction are const-eligible when all field values are themselves const expressions. Struct field defaults from the type definition are used for omitted fields (those defaults are already required to be const).

```pact
type LogLevel {
    Debug
    Info
    Warn
    Error
}

const DEFAULT_LOG_LEVEL = LogLevel.Info

type ServerConfig {
    host: Str = "0.0.0.0"
    port: Int = 8080
    max_retries: Int = MAX_RETRIES
    debug: Bool = false
}

// All fields are const — valid
const DEFAULT_CONFIG = ServerConfig {
    host: "localhost"
    port: 3000
    debug: true
}

// Omitted fields use their (const) defaults — also valid
const PROD_CONFIG = ServerConfig {
    host: "0.0.0.0"
    port: 443
}
```

Only struct **literal** syntax (`Type { field: value }`) is const. Constructor functions like `Type.new()` are function calls and are not const, even if they return the same value.

#### Where Const Expressions Are Required

Const expressions are required in four contexts:

1. **`const` declarations** — the RHS must be a const expression
2. **Struct field defaults** — `type Foo { x: Int = <const> }`
3. **Keyword argument defaults** — `fn f(-- x: Int = <const>)`
4. **Range pattern bounds** — `match n { 1..=MAX => ... }`

```pact
// Struct field defaults — const expressions
type RetryConfig {
    max_retries: Int = MAX_RETRIES
    backoff_ms: Int = TIMEOUT_MS / MAX_RETRIES
    timeout_ms: Int = 60 * 1000
}

// Keyword arg defaults — const expressions
fn connect(url: Str, -- timeout: Int = TIMEOUT_MS, retries: Int = MAX_RETRIES) ! Net.Connect {
    // ...
}

// Range pattern bounds — const expressions
fn classify(code: Int) -> Str {
    match code {
        0 => "zero"
        1..=MAX_RETRIES => "retry range"
        200..=299 => "success"
        _ => "other"
    }
}
```

#### Visibility

`const` declarations support `pub` for export, same as `let`:

```pact
pub const API_VERSION = "2.0"
pub const DEFAULT_PORT = 8080

const INTERNAL_LIMIT = 1000  // private to module
```

There is no `const mut` — constants are inherently immutable. `const mut` is a compile error (E1102).

#### Module-Level `let` vs `const`

`const` and `let` at module level serve different purposes:

| | `const` | `let` |
|-|---------|-------|
| Evaluation | Compile time | Program initialization |
| RHS | Must be const expression | Any expression (runtime) |
| Substitution | Inlined at use sites | Read from memory |
| Mutability | Never | `let mut` allowed |
| `pub` export | Yes | Yes (immutable only) |

Module-level `let` remains valid for runtime-initialized module state:

```pact
// Compile-time: evaluated by the compiler, inlined everywhere
const MAX_RETRIES = 5

// Runtime: initialized when the module loads
let mut request_count = 0
```

#### C Codegen

The compiler evaluates all const expressions during compilation and emits the resulting values as C literals. Arithmetic like `1024 * 64` is folded to `65536` by the Pact compiler, not the C compiler. Struct consts are emitted as C designated initializers with all fields resolved.

```c
// Pact: const BUFFER_SIZE = 1024 * 64
static const int64_t BUFFER_SIZE = 65536;

// Pact: const DEFAULT_CONFIG = ServerConfig { host: "localhost", port: 3000 }
static const ServerConfig DEFAULT_CONFIG = { .host = "localhost", .port = 3000, .debug = 0 };
```

This keeps the C output maximally simple and portable — no macros, no platform-dependent initializer rules.

#### Error Codes

| Name | Code | Description |
|------|------|-------------|
| `NonConstExpr` | E1101 | Expression is not a compile-time constant |
| `ConstMutForbidden` | E1102 | `const` binding cannot be `mut` |
| `NonConstStructDefault` | E1103 | Struct field default is not a const expression |
| `NonConstKeywordDefault` | E1104 | Keyword argument default is not a const expression |
| `NonConstRangeBound` | E1105 | Range pattern bound is not a const expression |

```
error[NonConstExpr]: expression is not a compile-time constant
  --> server.pact:5:15
   |
 5 | const BAD = compute_max()
   |             ^^^^^^^^^^^^^ function calls are not allowed in const expressions
   |
   = help: const expressions allow: literals, arithmetic, boolean ops, comparisons,
           references to other `const` bindings, struct literals, and enum variants
```

**Panel vote:** Const expression scope (literals + arithmetic) 5-0 unanimous. `const` keyword required 3-2 (PLT/DevOps/AI for `const`; Sys/Web for inferred `let`). Struct literals with const fields 3-1-1 (PLT/DevOps/AI for struct literals; Web for nested structs; Sys for scalars-only). Compiler-evaluated emit literals 5-0 unanimous. See [DECISIONS.md](../DECISIONS.md).
