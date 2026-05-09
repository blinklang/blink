## 8. Tooling & AI Interaction

### 8.1 Philosophy: Tooling IS the Language

Most languages treat tooling as an afterthought — a separate ecosystem of linters, formatters, package managers, and IDE plugins built by third parties, often incompatible, always fragmented. Blink rejects this entirely.

In Blink, the tooling is not adjacent to the language. It is the language. The compiler, formatter, package manager, test runner, and LSP are a single unified system with one dependency graph, one data model, and one structured output format. Every tool speaks the same AST. Every tool is driven by the same daemon process.

This matters for AI-assisted development because:

1. **Zero configuration decisions.** An AI agent never asks "which formatter?", "which test framework?", "which package manager?" There is exactly one answer to every tooling question.

2. **Structured everything.** Every tool produces structured JSON. The AI never parses freeform error strings, never scrapes terminal output, never guesses at formats. Machine-readable in, machine-readable out.

3. **Semantic access.** The AI doesn't read files — it queries the compiler. "Show me everything that writes to the database" is a single command, not a grep across 200 files hoping the naming conventions are consistent.

4. **Sub-second feedback.** The compiler daemon maintains a live dependency graph. Incremental type-checking of a single changed function targets sub-200ms. The AI's generate-compile-fix loop runs at the speed of thought, not the speed of `make`.

The combined effect is transformative: Blink gives an AI agent roughly 8x the effective context capacity of Python with file-based reads. Not through syntax tricks — through architectural decisions about how code is stored, queried, and validated.

---

### 8.2 Compiler-as-Service Architecture

The Blink compiler is not a batch process. It is a persistent daemon that runs for the lifetime of a development session, maintaining a live, incremental model of the entire codebase.

```
┌─────────────────────────────────────────────────┐
│                 blink daemon                      │
│                                                  │
│  ┌──────────┐  ┌──────────┐  ┌──────────────┐   │
│  │ Parser   │  │ Type     │  │ Effect       │   │
│  │ (incr.)  │──│ Checker  │──│ Checker      │   │
│  └──────────┘  └──────────┘  └──────────────┘   │
│       │              │              │             │
│       ▼              ▼              ▼             │
│  ┌───────────────────────────────────────────┐   │
│  │         Symbol-Level Dependency Graph      │   │
│  └───────────────────────────────────────────┘   │
│       │         │         │         │             │
│       ▼         ▼         ▼         ▼             │
│     LSP     Diagnostics  Query    Codegen        │
│    Server    (JSON)      Engine   (on demand)    │
│                                                  │
└─────────────────────────────────────────────────┘
```

Key properties:

**Symbol-level granularity.** The dependency graph tracks individual functions, types, and traits — not files. When you change one function, the daemon re-checks only that function and its direct dependents. File-level granularity (Rust, Go) re-checks entire files; Blink re-checks the minimal subgraph.

**The compiler IS the LSP.** There is no separate LSP implementation that reimplements half the compiler and gets the other half wrong. Completions, hover info, go-to-definition, refactoring, and diagnostics all come from the same type-checking pass that produces compilation errors. They are always consistent.

**Structured JSON output.** Every compiler output — errors, warnings, query results, completions — is structured data with stable schemas. AI agents consume compiler output directly, not through regex parsing of terminal text.

**Sub-200ms incremental checking.** Target latency for re-checking a single changed function in a 100k-line codebase. This is what makes the AI's tight generate-compile-fix loop viable. The daemon achieves this by:
- Keeping the full symbol table in memory
- Tracking fine-grained dependencies (function A calls function B, not "file X imports file Y")
- Only re-running type inference / effect checking on the changed symbol and its reverse dependencies
- Deferring codegen until explicitly requested

```sh
# The daemon starts automatically on first blink command
blink check              # type-check, daemon stays alive
blink check src/auth.bl  # re-check one file (daemon uses cached graph)

# Explicit daemon management
blink daemon start       # start manually
blink daemon status      # show uptime, memory, graph size
blink daemon stop        # shut down
```

---

### 8.3 Layered Inspection Model

This is the single most imblinkful feature for AI context efficiency.

Current AI coding tools read entire files to understand a codebase. A 100-function project might require reading 20 files (~50,000 tokens) just to understand the architecture before making a single change. Most of those tokens are implementation details the AI doesn't need.

Blink's compiler-as-service exposes code at four granularity levels. The AI chooses the level of detail it needs:

```
Layer 0: Intent        ~20 tokens/function    @i annotations only
Layer 1: Signatures    ~40 tokens/function    names + types + effects
Layer 2: Contracts     ~60 tokens/function    + @requires/@ensures
Layer 3: Full          ~200 tokens/function   complete implementation
```

For a 100-function project:

| Layer | Tokens | What you get |
|-------|--------|-------------|
| Intent | ~2,000 | Natural-language map of the entire codebase |
| Signatures | ~4,000 | Full API surface with types and effects |
| Contracts | ~6,000 | Behavioral guarantees on every function |
| Full | ~20,000 | Complete implementation |

Compare to file-based reading: ~50,000 tokens for the same project (imports, boilerplate, formatting, comments, irrelevant functions in the same file).

**Example: AI exploring an unfamiliar codebase**

Step 1 — Get the intent map (~2,000 tokens):

```sh
blink query --layer intent --module auth
```

```json
{
  "module": "auth",
  "functions": [
    {"name": "login", "visibility": "pub", "intent": "Main auth flow: rate check, verify credentials, issue token"},
    {"name": "check_rate", "intent": "Check login attempts, reject if over threshold"},
    {"name": "verify_creds", "intent": "Validate credentials against stored hash"},
    {"name": "issue_token", "intent": "Issue JWT with standard claims"},
    {"name": "refresh_token", "intent": "Reissue token if current one is near expiry"},
    {"name": "revoke_session", "intent": "Invalidate all tokens for a user"}
  ]
}
```

Step 2 — Drill into signatures for the relevant functions (~120 tokens):

```sh
blink query --layer signature --fn auth.login,auth.verify_creds
```

```json
[
  {
    "name": "login",
    "signature": "fn login(email: Str, pwd: Str, ip: Str) -> AuthResult ! IO, DB, Cache",
    "visibility": "pub"
  },
  {
    "name": "verify_creds",
    "signature": "fn verify_creds(email: Str, pwd: Str) -> Result[User, AuthError] ! DB",
    "visibility": "internal"
  }
]
```

Step 3 — Read full implementation only for the function being modified (~200 tokens):

```sh
blink query --layer full --fn auth.verify_creds
```

Total tokens consumed: ~2,320 instead of ~50,000. That is a **20x reduction** for a targeted modification — and the AI had full architectural context the entire time.

---

### 8.4 Intent Declarations (`///`)

The first line of a `///` doc comment serves as the intent declaration — it captures *what* a function does and *why* it exists, in natural language:

```blink
/// Validate user credentials against stored hash, returning the user on success
fn verify_creds(email: Str, pwd: Str) -> Result[User, AuthError] ! DB {
    let user = db.query_one("SELECT * FROM users WHERE email = {email}")
        ?? return Err(NotFound)
    if user.locked {
        return Err(Locked)
    }
    if !crypto.verify(pwd, user.hash) {
        return Err(BadCreds)
    }
    Ok(user)
}
```

Intent declarations are the first line of `///` doc comments. They are:

**Compiler-tracked.** The compiler stores intents in the symbol table alongside types and effects. They participate in the query system and are included in structured compiler output.

**Queryable.** `blink query --intent "authentication"` finds every function whose intent mentions authentication. This is semantic search over the codebase, not string matching — the query engine understands synonyms and related concepts.

**Versioned.** When a `///` first line changes, it shows up in diffs. When an implementation changes but its intent doesn't, the toolchain can flag the drift for review (future: automated drift detection).

**Compressed representation.** The intent layer is the most token-efficient representation of a codebase. An AI can understand the architecture of a 500-function project from ~10,000 tokens of intent declarations — less than a single large source file in most languages.

```blink
/// Main auth flow: rate check, verify credentials, issue token
@requires(email.len() > 0)
@ensures(result.is_ok() => result.unwrap().token.expiry > now())
pub fn login(email: Str, pwd: Str, ip: Str) -> AuthResult ! IO, DB, Cache {
    check_rate(ip)?
    let user = verify_creds(email, pwd)?
    let token = issue_token(user)
    io.log("auth.success", user: user.id, ip: ip)
    Ok(AuthSuccess { user, token })
}
```

The first `///` line answers: "If I had 10 words to describe this function, what would they be?" Every function in a Blink codebase should have one. The AI uses them as a table of contents for the codebase.

---

### 8.5 Semantic Query System

The query system lets AI agents (and humans) search the codebase by meaning, not by text patterns. Queries run against the compiler's live symbol table — they are fast, precise, and always up-to-date.

**Query by effect — find everything that writes to the database:**

```sh
blink query --effect "DB.Write"
```

```json
{
  "matches": [
    {
      "function": "auth.login",
      "effects": ["IO", "DB.Read", "DB.Write", "Cache"],
      "file": "src/auth.bl",
      "line": 42
    },
    {
      "function": "users.update_profile",
      "effects": ["DB.Write", "IO"],
      "file": "src/users.bl",
      "line": 18
    }
  ]
}
```

**Query by type signature — find all functions returning a specific error type:**

```sh
blink query --type "* -> Result[*, AuthError]"
```

```json
{
  "matches": [
    {"function": "auth.login", "signature": "fn(Str, Str, Str) -> AuthResult ! IO, DB, Cache"},
    {"function": "auth.verify_creds", "signature": "fn(Str, Str) -> Result[User, AuthError] ! DB"},
    {"function": "auth.check_rate", "signature": "fn(Str) -> Result[Int, AuthError] ! Cache"}
  ]
}
```

**Query by intent — find functions related to rate limiting:**

```sh
blink query --intent "rate limit"
```

```json
{
  "matches": [
    {
      "function": "auth.check_rate",
      "intent": "Check login attempts, reject if over threshold",
      "relevance": 0.95
    },
    {
      "function": "api.throttle",
      "intent": "Enforce per-endpoint request limits",
      "relevance": 0.82
    }
  ]
}
```

**Query by contract — find functions with specific guarantees:**

```sh
blink query --ensures "*.is_sorted"
```

**Query combinations — find pure functions that take a list and return a list:**

```sh
blink query --type "List[*] -> List[*]" --pure
```

The query system replaces the manual "grep, open file, read surrounding context, figure out what it does" loop that dominates current AI coding workflows. One structured query replaces dozens of file reads.

---

### 8.6 Structured Diagnostics with Machine-Applicable Fixes

Every compiler diagnostic is structured JSON with a stable schema. Errors include machine-applicable fix suggestions that an AI agent can apply directly — no parsing of freeform error messages, no heuristic extraction of fix hints.

```json
{
  "severity": "error",
  "name": "NonExhaustiveMatch",
  "code": "E0004",
  "message": "non-exhaustive match",
  "span": {
    "file": "src/auth.bl",
    "line": 24,
    "col": 5,
    "end_line": 28,
    "end_col": 6
  },
  "labels": [
    {"span": {"line": 24, "col": 11}, "message": "missing variant `Locked`"}
  ],
  "help": "add arm for `Locked` variant",
  "fix": {
    "description": "Add missing match arm",
    "edits": [
      {
        "span": {"file": "src/auth.bl", "line": 27, "col": 0},
        "insert": "        Locked => Err(AccountLocked)\n"
      }
    ]
  },
  "related": [
    {
      "message": "`AuthError` variant `Locked` defined here",
      "span": {"file": "src/auth.bl", "line": 5, "col": 5}
    }
  ]
}
```

What this gives the AI:

- **Error name** (`NonExhaustiveMatch`) — stable identifier, can be mapped to fix strategies. See [ERROR_CATALOG.md](../ERROR_CATALOG.md)
- **Error code** (`E0004`) — secondary comblink alias
- **Exact span** — the AI knows precisely which code to modify
- **Machine-applicable edits** — the `fix.edits` array contains insert/replace/delete operations the AI can apply verbatim
- **Related locations** — where the type/trait/variant was defined, for context
- **No guesswork** — the AI doesn't interpret an English sentence and hope it understands what the compiler meant

The effect on the generate-compile-fix loop is dramatic. In Python, an AI reads a traceback, infers what went wrong, generates a fix hypothesis, applies it, and hopes. In Blink, the compiler tells the AI exactly what's wrong, exactly where, and often exactly how to fix it. The fix loop becomes mechanical rather than inferential.

---

### 8.7 Alternatives System (`@alt`)

AI agents frequently generate multiple valid solutions to a problem. In current workflows, only one survives — the others are discarded, lost to the chat history. Blink's alternatives system preserves all valid implementations as first-class entities in the codebase.

```blink
/// Validate user credentials against stored hash
fn verify_creds(email: Str, pwd: Str) -> Result[User, AuthError] ! DB {
    let user = db.query_one("SELECT * FROM users WHERE email = {email}")
        ?? return Err(NotFound)
    if !crypto.verify(pwd, user.hash) {
        return Err(BadCreds)
    }
    Ok(user)
}

@alt("CRED-ALT-001", "Cache-backed credential verification")
/// Verify credentials with cache layer to reduce DB load
fn verify_creds(email: Str, pwd: Str) -> Result[User, AuthError] ! DB, Cache {
    let cached = cache.get("user:{email}")
    let user = match cached {
        Some(u) => u
        None => {
            let u = db.query_one("SELECT * FROM users WHERE email = {email}")
                ?? return Err(NotFound)
            cache.set("user:{email}", u, ttl: 300)
            u
        }
    }
    if !crypto.verify(pwd, user.hash) {
        return Err(BadCreds)
    }
    Ok(user)
}
```

Both implementations are type-checked by the compiler. Both are stored in the codebase. The active implementation is selected through configuration, not by deleting code:

```sh
# List alternatives for a function
blink alt list auth.verify_creds
```

```
  primary   verify_creds    "Validate user credentials against stored hash"
  CRED-ALT-001  verify_creds    "Cache-backed credential verification"
    + adds effect: Cache
    + adds dependency: cache module
    tradeoff: lower DB load, stale data risk (300s TTL)
```

```sh
# Select an alternative as the active implementation
blink alt select CRED-ALT-001

# Compare two implementations side-by-side
blink alt compare auth.verify_creds
```

```
  Effect diff:  primary: ! DB
                CRED-ALT-001: ! DB, Cache (+Cache)

  Contract diff:
    Both satisfy @ensures(result.is_ok => crypto.verify(pwd, result.unwrap().hash))
    CRED-ALT-001 does NOT satisfy: "always uses latest DB data" (stale cache)
```

Alternatives are selected per-environment via `blink.toml`:

```toml
[alternatives]
"CRED-ALT-001" = { environments = ["production"], enabled = true }
```

This means different alternatives can be active in staging vs production. The selection is a configuration concern, not a source code change — no feature flag `if` statements polluting the implementation.

---

### 8.8 Built-in Formatter

```sh
blink fmt                # format everything
blink fmt src/auth.bl  # format one file
```

There are zero configuration options. The canonical style IS the grammar — there is exactly one valid way to format any Blink program. The formatter is not a tool you run; it is a property of the language.

What this means in practice:

- **AI-generated code is indistinguishable from human code.** No style drift, no "this looks AI-generated" formatting quirks.
- **Diffs are always semantic.** Every line in a diff represents a behavioral change, never a formatting change. No "reformatted the whole file" noise commits.
- **No bikeshedding.** Tabs vs spaces, brace placement, line length — none of these are decisions. They are answered by the grammar itself.
- **Deterministic output.** Given any syntactically valid Blink program, `blink fmt` produces exactly one output. Two developers formatting the same code always get identical results.

The formatter runs in the compiler daemon, so it shares the parser. Formatting is near-instantaneous — it is a render pass over the AST, not a separate parse-transform-emit pipeline.

---

### 8.9 Built-in Package Manager

```sh
blink add std/serde       # add a dependency
blink remove std/serde    # remove a dependency
blink update              # update all deps within constraints
blink update std/serde    # update one dependency
```

One package manager. Mandatory lockfile. Content-addressed storage. Deterministic resolution.

There is no `blink.lock` vs `package-lock.json` vs `yarn.lock` decision. There is no pip vs pipenv vs poetry vs uv decision. There is no npm vs yarn vs pnpm decision. There is `blink add`.

The lockfile (`blink.lock`) is always committed to version control. Builds without a lockfile are an error — not a warning, an error. Reproducible builds are not optional.

The package manager is integrated with the compiler daemon. When you run `blink add`, the daemon immediately re-checks the dependency graph and reports any type conflicts with the new dependency. You find out about incompatibilities at add time, not at build time.

#### 8.9.1 Registry Model

Blink uses a **hybrid registry model**: a central registry for short-name resolution with git URL fallback for unregistered packages.

- **Central registry** — the default source. `blink add std/http` resolves to the registry.
- **Git URL fallback** — for unregistered or private packages. `blink add git:https://github.com/org/pkg.git`.
- **Path dependencies** — for local development. `path = "../my-lib"` in `blink.toml`.

**Identity invariant:** A registered package has exactly one identity regardless of how it is accessed. If `std/http` is registered, `git:https://github.com/blink-lang/http.git` resolves to the same package. The registry is the canonical source of truth; git URLs are aliases, not separate packages.

#### 8.9.2 Package Naming

Packages use **namespaced `org/name` format**:

- `std/http` — standard library HTTP package
- `acme/web-framework` — organization-scoped package
- Names are lowercase, alphanumeric plus hyphens. Org names follow the same rules.

Namespacing maps directly to trust boundaries. A package's org determines its capability audit scope — `std/` packages are trusted differently than `acme/` packages. This enables per-org capability policies in CI (§4.9).

#### 8.9.3 `blink.toml` Full Schema

```toml
[package]
name = "acme/myapp"          # org/name format (required)
version = "0.1.0"            # semver (required)
edition = "2026"             # language edition (optional, default: latest)
description = "My app"       # human-readable (optional)
license = "MIT"              # SPDX identifier (optional)
repository = "https://..."   # source URL (optional)

[dependencies]
std/http = "1.2"                                        # registry, caret constraint
std/json = "~1.0"                                       # registry, tilde constraint
acme/auth = { version = "0.5", features = ["oauth"] }   # registry with features
internal/lib = { git = "https://github.com/org/lib.git", tag = "v1.0" }  # git dep
local/utils = { path = "../utils" }                      # path dep

[dev-dependencies]
std/bench = "0.3"

[capabilities]
required = ["Net.Connect", "Net.DNS"]         # always needed
optional = ["IO.Log"]                         # only if caller provides handler

[native-dependencies]                         # §9.1.2 native C library resolution
libsodium = { type = "system" }               # dynamic link, must be on target
mylib = { type = "vendored", path = "vendor/mylib.c" }  # compiled from source

[alternatives]                                # §4.10 alt-effect registrations
Net.Connect = "mock-http"                     # test alternative
```

**Dependency source table:** Each dependency specifies exactly one source — `version` (registry), `git`, or `path`. Combining sources is an error.

#### 8.9.4 Version Constraints

| Syntax | Meaning | Example |
|--------|---------|---------|
| `"1.2"` | Caret (default): `>=1.2.0, <2.0.0` | Compatible updates within major |
| `"~1.2"` | Tilde: `>=1.2.0, <1.3.0` | Patch-level updates only |
| `"=1.2.3"` | Exact: only `1.2.3` | Pinned version |
| `">=1.0, <2.0"` | Explicit range | Manual bounds |

**Caret is the default** because it expresses the semver contract directly: "any compatible version." Most dependencies should use bare `"1.2"`.

**Pre-1.0 rule:** For versions `0.x.y`, the minor version is treated as breaking. `"0.2"` means `>=0.2.0, <0.3.0`. This matches the convention that pre-1.0 packages break APIs on minor bumps.

#### 8.9.5 Resolution Algorithm

Blink uses **Minimal Version Selection (MVS)**:

- Given a set of version constraints, MVS selects the **oldest version** that satisfies all constraints.
- Resolution is **deterministic without a lockfile**. The same `blink.toml` always resolves to the same versions, regardless of what versions exist on the registry at resolution time.
- There is **no SAT solver**. MVS resolution is a simple graph walk — O(n) in the dependency graph size. It cannot fail due to solver timeouts or heuristic differences.

**Why oldest, not newest:** Newest-version resolution is non-deterministic — it depends on what versions are published at resolution time. Two developers resolving on different days get different versions. MVS eliminates this: the resolved version depends only on what the dependency *declared*, not on what exists.

`blink update` explicitly upgrades dependencies to the newest version satisfying constraints. This is the only operation that changes resolved versions — it is intentional, not incidental.

`blink update std/http` upgrades one dependency. `blink update` upgrades all. Both update the lockfile.

#### 8.9.6 `blink.lock` Schema

```toml
[metadata]
lockfile-version = 1
blink-version = "0.1.0"
generated = "2026-01-15T10:30:00Z"

[[package]]
name = "std/http"
version = "1.2.0"
source = "registry"
hash = "sha256:abc123..."
capabilities = ["Net.Connect", "Net.DNS"]

[[package]]
name = "std/json"
version = "1.0.3"
source = "registry"
hash = "sha256:def456..."
capabilities = []

[[package]]
name = "internal/lib"
version = "1.0.0"
source = "git:https://github.com/org/lib.git#a1b2c3d"
hash = "sha256:789ghi..."
capabilities = ["FS.Read"]
```

Git dependencies are **pinned to commit hash** in the lockfile, ensuring reproducibility even if tags or branches move.

The `hash` field is the content hash of the package source. The package manager verifies hashes on every build — a tampered dependency is a build error.

Capability declarations in the lockfile enable `blink audit` to detect capability escalation without fetching package source (§4.9).

#### 8.9.7 MVP Scope

v1 ships with **path and git dependencies only**. No registry infrastructure is required for the initial release.

```toml
# v1 blink.toml — no registry deps
[package]
name = "myapp"
version = "0.1.0"

[dependencies]
my-lib = { path = "../my-lib" }
external = { git = "https://github.com/org/pkg.git", tag = "v0.1" }
```

The `blink.toml` schema is **forward-compatible**: adding `version = "1.0"` registry deps in v2 requires no schema changes. The registry is an additional source, not a replacement.

Import paths follow the `org/name` structure: `import std.http` maps to the `std/http` package. Local modules shadow dependencies with the same path, with compiler warning W1000 (§10.5).

---

### 8.10 Built-in Test Runner

Tests in Blink are not a library. They are first-class syntax — `test` blocks are part of the grammar, understood by the parser, type-checked by the compiler, and run by the built-in test runner.

```blink
fn add(a: Int, b: Int) -> Int {
    a + b
}

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

**Why first-class syntax, not a library:**

- The compiler knows about tests. It can type-check test bodies against the function under test, catch type mismatches in assertions at compile time, and provide structured test output in the same JSON format as diagnostics.
- `prop_check` for property-based testing is built-in. The AI doesn't need to pick a property testing library, learn its API, or manage its dependency.
- Doc-tests in `///` comments are compiled and run:

```blink
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

**Test output is structured JSON:**

```sh
blink test --json
```

```json
{
  "suite": "auth",
  "results": [
    {
      "name": "login succeeds with valid credentials",
      "status": "pass",
      "duration_ms": 12
    },
    {
      "name": "login rejects after rate limit",
      "status": "fail",
      "assertion": "assert_eq(result, Err(RateLimit))",
      "expected": "Err(RateLimit)",
      "actual": "Ok(AuthSuccess { ... })",
      "span": {"file": "src/auth.bl", "line": 58, "col": 5}
    }
  ],
  "summary": {"total": 14, "pass": 13, "fail": 1, "duration_ms": 340}
}
```

The AI reads structured test failures the same way it reads structured compiler errors — exact location, expected vs actual values, no string parsing.

```sh
blink test                       # run all tests
blink test --filter "auth"       # run tests matching pattern
blink test --prop                # run only property tests
blink test --doc                 # run only doc-tests
blink test --coverage            # with coverage report (JSON)
```

#### 8.10.1 Test Effect Handlers: `capture_log`

Tests are pure by default (see §4.7). Code that uses effects like `IO.Log` requires explicit handlers in test blocks. The `std.testing` module provides `capture_log` — a handler factory that intercepts `io.log()` calls and collects messages into a list for assertion.

```blink
import std.testing.{capture_log}

fn process_order(id: Int) -> Result[Receipt, OrderError] ! DB.Read, DB.Write, IO.Log {
    io.log("Processing order {id}")
    let order = db.read("SELECT * FROM orders WHERE id = {id}")?
    let receipt = Receipt { order_id: id, total: order.total }
    db.write("INSERT INTO receipts ...", receipt)?
    Ok(receipt)
}

test "process_order logs the order ID" {
    let log_messages: List[Str] = []
    let fake_orders = [Order { id: 42, total: 99.99 }]

    with mock_db(fake_orders), capture_log(log_messages) {
        let result = process_order(42)
        assert(result.is_ok())
    }

    assert_eq(log_messages.len(), 1)
    assert(log_messages[0].contains("Processing order 42"))
}
```

**Signature:**

```blink
pub fn capture_log(messages: List[Str]) -> Handler[IO.Log]
```

`capture_log` returns a `Handler[IO.Log]` that appends each `io.log(msg)` call's message to the provided list. The handler does not forward to the outer handler — log calls are silently captured.

**Usage patterns:**

```blink
// Capture and ignore logs (satisfy the effect requirement without asserting)
with capture_log([]) {
    do_work()
}

// Capture logs for assertion
let msgs: List[Str] = []
with capture_log(msgs) {
    do_work()
}
assert_eq(msgs.len(), 2)
assert(msgs[0].contains("started"))

// Compose with other handlers
with mock_db(data), capture_log(msgs) {
    do_work()
}
```

**No special assertion helpers.** Use the existing `assert`, `assert_eq`, and `assert_ne` built-ins with standard `List[Str]` methods:

```blink
assert_eq(msgs.len(), 3)                          // exact count
assert(msgs[0].contains("order 42"))              // substring match
assert_eq(msgs, ["started", "processing", "done"]) // exact match
assert(msgs.any(fn(m) { m.contains("error") }))  // any-match
```

**`capture_log` handles only `IO.Log`.** If the code under test also uses `IO.Print`, provide a separate handler for that effect. The effect system's handler composition makes this natural:

```blink
let logs: List[Str] = []
let prints: List[Str] = []
with capture_log(logs), capture_print(prints) {
    do_work()  // uses both io.log() and io.println()
}
```

`capture_print` follows the same pattern and is also provided by `std.testing`. Users can write custom capture handlers for any effect using the standard handler syntax (see §4.7).

#### 8.10.2 std.testing — Library API

Beyond the four built-in assertions (§2.20) and the effect-capture handlers (§8.10.1), `std.testing` ships a small set of library helpers for common test-authoring patterns. Everything in this section is plain Blink — no new compiler intrinsics, no new keywords. Each helper is a thin wrapper around the existing built-in assertions so power-assert introspection (§2.20 Assertion Failure Output) renders the failure.

```blink
import std.testing.{assert_close, assert_close_rel, for_each}
```

##### Float comparison: `assert_close` / `assert_close_rel`

Float equality via `assert_eq` is a correctness trap on every platform with an FPU. `0.1 + 0.2 != 0.3` is bit-for-bit true; a test that asserts otherwise is asserting against IEEE-754, not against the code under test. `std.testing` ships two float comparison helpers:

```blink
pub fn assert_close(actual: Float, expected: Float, tol: Float)
pub fn assert_close_rel(actual: Float, expected: Float, rel_tol: Float)
```

`assert_close` is **absolute tolerance** — fails unless `(actual - expected).abs() <= tol`.
`assert_close_rel` is **relative tolerance** — fails unless `(actual - expected).abs() <= rel_tol * actual.abs().max(expected.abs())`.

Both helpers are library functions whose body delegates to the existing `assert(...)` built-in, so failure rendering reuses the same expression-introspection machinery as `assert_eq`:

```blink
test "newton's method converges" {
    let result = newton_sqrt(2.0)
    assert_close(result, 1.41421356, 1e-7)
}

test "scaled measurement matches expected ratio" {
    let measured = simulate_signal(samples)
    assert_close_rel(measured, 1.0e9, 1e-6)
}
```

**Required tolerance.** Neither helper has a default `tol` / `rel_tol`. A default would silently encode an absolute scale that is wrong for values near `1e-12` (looser than `==`) and wrong for values near `1e9` (tighter than the FPU can represent). Tolerance is domain-specific; the caller picks it.

**NaN policy.** Either argument being NaN fails the assertion. This is the IEEE-754 invariant — `NaN <= NaN` is `false`, so `assert_close(NaN, NaN, _)` cannot pass. Use `assert(x.is_nan())` if you specifically want to assert that a value is NaN.

**Inf policy.** `+Inf` and `-Inf` are accepted only when `actual` and `expected` are both the same infinity; mixing finite values with infinities fails the assertion. Use `assert_eq(x, Float.INF)` for explicit infinity checks.

**Why a function pair, not a method.** `assert(x.close_to(y, eps))` would print only `false` on failure — power-assert decomposes call-site operands, not the bodies of called methods. A dedicated `assert_close(actual, expected, tol)` matcher owns its diagnostic and renders `actual`, `expected`, and `tol` at the assertion site. The underlying `Float.close_to` / `Float.close_to_rel` predicate methods are also available on `Float` for non-test use (clamping, convergence loops); see §3.X (Float type).

**Why no other matchers.** Power-assert renders both sides of an `assert(...)` call at the call site. `assert(list.contains(x))`, `assert(s.starts_with("/api"))`, and `assert(a < b)` already produce structured failure output naming both operands. A parallel `assert_contains` / `assert_lt` matcher namespace would duplicate that machinery without adding diagnostic value, and would force the test author to recall which matcher name corresponds to which predicate. Float comparison is the one correctness trap that cannot be expressed via the existing built-ins, so it earns its own helper.

**No `assert_panics` yet.** Capturing a `panic` from within a test requires deciding whether Blink supports recoverable panics at all (intrinsic, algebraic effect, or `Result[T, PanicInfo]`) — a language design decision, not a matcher. Tracked separately under `type:spec`. For now, tests that need to verify panics should isolate the panicking call into a subprocess via `process_run` (the same approach used by `tests/compile_test_helpers.bl`).

##### Table-driven tests: `for_each`

Many tests have the shape "run the same assertions against many inputs." Looping inside a single `test` block collapses N independent failures into one — the runner sees one failed test instead of three, and the first failure short-circuits the rest. `std.testing.for_each` is a thin helper that runs a block per case and reports each failure independently:

```blink
pub fn for_each[T](cases: List[(Str, T)], body: fn(T) -> Unit)
```

Each case is a `(label, value)` pair. The label is included in the failure message so the runner output identifies which case failed. The body is called for every case — failures do not short-circuit:

```blink
test "add handles signs" {
    testing.for_each([
        ("zero",     (0, 0, 0)),
        ("positive", (1, 2, 3)),
        ("negative", (-1, -2, -3)),
        ("mixed",    (5, -3, 2)),
    ], fn(case) {
        let (a, b, expected) = case
        assert_eq(add(a, b), expected)
    })
}
```

**Label uniqueness.** Duplicate labels within the same `for_each` call panic at the start of the offending iteration with `for_each: duplicate case label "<label>" at indices <j> and <i>`. Uniqueness is checked at runtime — labels are arbitrary `Str` values and may be computed, so static checking would be over-constrained. Empty-string labels are allowed but two empty strings still collide.

**Failure attribution.** Failures inside the body unwind through the test runner's per-test catch boundary (§2.20) and mark the parent `test` as failed. The current runner does not yet emit per-iteration `case` records in NDJSON output, so a failure shows the parent test's name without naming the failing case. Until the runner change lands (tracked separately as a `type:bug` against `lib/std/testing.bl` and the runner reporter), tests that need per-case attribution should include the label in the assertion message:

```blink
testing.for_each(cases, fn(case) {
    let (label, expected) = case
    assert_eq(compute(case), expected, "case {label}")
})
```

**Why explicit labels, not auto-generated names.** Two cases that stringify the same way (`(1.0, 1.0)` and `(1.0, 1.0)` from different file lines) would collide if names were auto-generated from `Display`. Forcing a label makes the case identifier deterministic and meaningful in CI logs. The two-token cost (`"label",`) is the price of unambiguous failure attribution.

**Relationship to `prop_check`.** `for_each` is for **deterministic** parameterization — a fixed list of explicit cases, every one run on every test invocation. `prop_check` (§2.20) is for **random** parameterization — the runner generates inputs from the closure's parameter types and runs the body many times. Use `for_each` when the cases are known and small; use `prop_check` when the property should hold for arbitrary inputs.

**Why no `subtest` primitive.** A `testing.subtest(label, fn)` HOF and a compiler-recognized `subtest "label" { }` block were both deliberated and rejected. `for_each` + multiple flat `test` blocks + helper `fn`s cover the parameterized-test design space (see §2.20 *Sub-tests and Parameterized Tests*). See [decisions/sub-tests.md](../decisions/sub-tests.md).

##### Snapshot testing — not in stdlib

`std.testing` does not ship snapshot testing (capture-and-diff a value against a stored golden). Snapshot semantics are policy-heavy: file storage layout, diff algorithm, update workflow, ANSI/whitespace handling, redaction of nondeterministic fields, merge-conflict behavior in `__snapshots__/`. Locking those choices into stdlib at this stage would commit the toolchain to a maintenance burden disproportionate to the value, and would foreclose ecosystem experimentation.

For now, the recommended pattern is `assert_eq` against a `pub const` golden value when the expected output is small, and an ecosystem package (`blink-snapshot` etc.) when the expected output is large or structured. A future `type:spec` deliberation may elevate the eventual community winner into stdlib.

##### Setup, teardown, and fixtures — not in stdlib (yet)

`std.testing` does not ship `setup`/`teardown`/`Fixture[T]` machinery. The current canonical pattern is to factor setup into a helper `fn` called at the top of each test, and to scope effectful resources via `with` handlers (§4.7), which run on pass, fail, *and* skip:

```blink
fn fresh_account() -> Account {
    Account.new("test-user", 100)
}

test "deposit increases balance" {
    let acct = fresh_account()
    let result = deposit(acct, 50)
    assert_eq(result.unwrap().balance, 150)
}

test "withdraw with mocked db" {
    let acct = fresh_account()
    with mock_db(fixtures) {
        let result = withdraw(acct, 25)
        assert(result.is_ok())
    }
}
```

A `defer` keyword for in-test (and general) teardown is being deliberated separately — it covers the gap of "run this on the way out even on panic" that `with` handlers alone do not address for non-effectful cleanup. See the `defer` spec ticket.

**Panel vote: 5-0** for `assert_close` library pair (Round 2; Round 1 was 3-2 with all five voters flagging the float gap). **5-0** for `for_each` library helper. **5-0** rejecting stdlib snapshot testing. **5-0** deferring `assert_panics` to a separate spec deliberation. AI/ML dissented on Q1 form (preferred a method-on-`Float` predicate over the matcher pair) before converging on the library-fn-with-inner-`assert` shape that gives both. PLT dissented on the hypothetical `defer` mechanism (separate ticket). See [DECISIONS.md](../DECISIONS.md) and [decisions/std-testing-user-api.md](../decisions/std-testing-user-api.md).

---

### 8.11 Token Efficiency Analysis

Blink's AI-efficiency gains come from three compounding layers. Each layer delivers real savings; together they are transformative.

#### Layer 1: Syntax (15-25% savings)

Blink's syntax is denser than Python or TypeScript without sacrificing clarity. Token savings from:

| Source | Saving |
|--------|--------|
| No semicolons | ~1 token/statement |
| `fn` vs `function`/`def` | 1 token per declaration |
| `Str` vs `String`, `Int` vs `Integer` | 1 token per type reference |
| No `import` boilerplate (effects provide handles) | 3-10 tokens per file |
| Universal string interpolation (no `f"..."` prefix) | 1 token per interpolated string |
| `T?` vs `Option[T]` in type position | 1-2 tokens per optional |
| `??` vs if-else/ternary for defaults | 2-4 tokens per default |

Cumulative: a typical 50-line function is 15-25% fewer tokens in Blink than the equivalent Python.

#### Layer 2: Structure (25-40% savings)

Blink's design eliminates entire categories of boilerplate:

| Traditional pattern | Blink equivalent | Token savings |
|----|----|----|
| Import statements (5-15 per file) | Effect handles + module system | 80-95% of import tokens |
| Dependency injection setup | Effect handlers | Constructor + binding boilerplate eliminated |
| Class hierarchies for polymorphism | ADTs + traits | No `class`, `extends`, `implements` ceremony |
| Exception handling (try/catch/finally) | `Result[T, E]` + `?` | 60-80% fewer error handling tokens |
| Null checking (`if x is not None`) | `??` and exhaustive matching | 50-70% fewer null-handling tokens |
| Test framework boilerplate | First-class `test` blocks | No `import unittest`, `class TestX`, `def setUp` |

Cumulative: a typical module is 25-40% fewer tokens than equivalent Python including imports, class definitions, and error handling.

#### Layer 3: Access (50-90% savings) — The Transformative Win

This is where Blink pulls away from every other language. The savings come not from syntax but from how the AI accesses code:

| Operation | Traditional (Python + file reads) | Blink (semantic queries) |
|----|----|----|
| Understand project architecture | Read 10-20 files (~50k tokens) | `blink query --layer intent` (~2k tokens) |
| Find all DB-writing functions | grep + manual reading (~5k tokens) | `blink query --effect DB.Write` (~500 tokens) |
| Check a function's contract | Read function + all callers (~3k tokens) | `blink query --layer contract --fn X` (~60 tokens) |
| Understand API surface | Read all public functions (~15k tokens) | `blink query --layer signature --pub` (~4k tokens) |
| Find functions by purpose | grep + reading context (~8k tokens) | `blink query --intent "rate limit"` (~200 tokens) |

The access layer savings compound with the syntax and structure savings. An AI working with Blink uses:
- 15-25% fewer tokens to represent the same code (syntax)
- 25-40% fewer tokens per module due to eliminated boilerplate (structure)
- 50-90% fewer tokens to navigate and understand the codebase (access)

**Combined effect: ~8x effective context capacity vs Python + file-based reads.**

For a 128k-token context window, this means:
- Python + file reads: effectively ~16k tokens of useful code context (rest is boilerplate, imports, irrelevant functions)
- Blink + semantic queries: effectively ~128k tokens of useful code context

The AI can hold an entire medium-sized project in its working memory. It can make cross-cutting changes that require understanding dozens of functions. It can refactor with full architectural context. This is the difference between an AI that edits one function at a time and an AI that understands the system.

---

### 8.12 Semantic Diffs

Standard `git diff` shows textual changes — lines added, lines removed. Blink's `blink diff` understands what changed semantically:

```sh
blink diff HEAD~1
```

```json
{
  "module": "auth",
  "changes": [
    {
      "function": "verify_creds",
      "kind": "implementation_changed",
      "summary": "Added cache lookup before database query",
      "effects_added": ["Cache"],
      "effects_removed": [],
      "contracts": {
        "status": "all_satisfied",
        "reverified": true
      },
      "intent_changed": false
    },
    {
      "function": "revoke_session",
      "kind": "new_function",
      "intent": "Invalidate all tokens for a user",
      "effects": ["DB.Write", "Cache"]
    }
  ]
}
```

Semantic diffs answer the questions humans and AI actually care about:
- Did this change add new effects? (security review concern)
- Are all contracts still satisfied? (correctness concern)
- Did the intent change, or just the implementation? (scope concern)
- What new API surface was added? (review concern)

---

### 8.13 `blink eval` — Fast Interactive Execution

For rapid AI iteration, `blink eval` interprets code directly from the AST with full type checking and effect tracking — no compilation step:

```sh
blink eval "auth.login(\"test@example.com\", \"pass123\", \"127.0.0.1\")"
```

```json
{
  "result": "Ok(AuthSuccess { user: User { id: 7 }, token: Token { exp: \"2026-02-06T12:00:00Z\" } })",
  "type": "AuthResult",
  "effects_observed": ["IO", "DB.Read", "Cache"],
  "contracts": {"satisfied": 4, "total": 4},
  "duration_ms": 183
}
```

The AI gets structured feedback — result value, type, effects actually performed, contract satisfaction — in a single JSON response. This replaces the "run it, read stdout, hope the output makes sense" pattern.

`blink eval` is for development and testing. Production always uses the AOT-compiled binary.

---

### 8.14 Complete CLI Reference

| Command | Description |
|---------|-------------|
| **Build & Run** | |
| `blink build` | Compile to native binary |
| `blink build --target wasm` | Compile to WebAssembly |
| `blink run` | Compile and execute in one step |
| `blink run --trace` | Run with full execution tracing (NDJSON to stderr) |
| `blink run --trace=<filter>` | Run with filtered tracing (see §8.15) |
| `blink check` | Type-check without codegen (fast) |
| `blink eval <expr>` | Interpret an expression with full checking |
| **Query & Inspect** | |
| `blink query --layer intent` | Get doc comment summaries for all functions |
| `blink query --layer signature` | Get function signatures with types and effects |
| `blink query --layer contract` | Get signatures + @requires/@ensures |
| `blink query --layer full --fn <name>` | Get complete implementation of a function |
| `blink query --effect <Effect>` | Find functions by effect |
| `blink query --type "<pattern>"` | Find functions by type signature pattern |
| `blink query --intent "<text>"` | Find functions by intent (semantic search) |
| `blink query --ensures "<predicate>"` | Find functions by contract |
| `blink query --pub` | Filter to public API only |
| `blink query --pure` | Filter to pure functions only |
| `blink query --module <name>` | Scope query to a module |
| **Testing** | |
| `blink test` | Run all tests |
| `blink test --filter "<pattern>"` | Run tests matching pattern |
| `blink test --prop` | Run property tests only |
| `blink test --doc` | Run doc-tests only |
| `blink test --coverage` | Run with coverage reporting |
| `blink test --json` | Output results as structured JSON |
| **Formatting & Style** | |
| `blink fmt` | Format all files (canonical style) |
| `blink fmt <file>` | Format one file |
| **Dependencies** | |
| `blink add <pkg>` | Add a dependency |
| `blink remove <pkg>` | Remove a dependency |
| `blink update` | Update all dependencies within constraints |
| `blink update <pkg>` | Update one dependency |
| **Alternatives** | |
| `blink alt list` | List all alternatives in the project |
| `blink alt list <fn>` | List alternatives for a specific function |
| `blink alt select <alt-id>` | Activate an alternative implementation |
| `blink alt compare <fn>` | Compare alternatives side-by-side |
| **Diagnostics & Analysis** | |
| `blink diff [ref]` | Semantic diff against a git ref |
| `blink trace <requirement>` | Show all code linked to a requirement ID |
| `blink ast <file>` | Dump AST as JSON |
| **Daemon** | |
| `blink daemon start` | Start compiler daemon explicitly |
| `blink daemon status` | Show daemon status and graph stats |
| `blink daemon stop` | Stop compiler daemon |
| **Evolution** | |
| `blink migrate` | Apply deprecation fixes, update edition in blink.toml |
| `blink migrate --dry-run` | Show what `migrate` would change without applying |
| `blink editions` | List all editions with changes and deprecations |
| `blink editions --breaking` | Show only breaking/removal changes per edition |
| `blink editions --json` | Machine-readable edition changelog |

All commands that produce output accept `--json` for structured JSON output. All commands that operate on code use the compiler daemon for incremental performance.

---

### 8.15 Runtime Execution Tracing

The `--trace` flag enables structured runtime tracing of compiled Blink programs. Output is NDJSON (one JSON object per line) to stderr, enabling observation of function calls, state mutations, and effect invocations without modifying source code.

#### 8.15.1 Usage

```sh
blink run app.bl --trace                              # trace everything
blink run app.bl --trace=fn:skip_newlines             # single function
blink run app.bl --trace=module:parser,depth:3        # AND composition
blink run app.bl --trace=fn:skip_newlines+parse_block # OR within key
blink run app.bl --trace=effect:FS.Write              # specific effect type
blink run app.bl --trace=event:state                  # only state events
```

Trace output goes to stderr. Program stdout is unaffected. Pipe through `jq` for filtering:

```sh
blink run app.bl --trace 2>trace.ndjson
cat trace.ndjson | jq 'select(.event == "state" and .var == "pending_comments")'
```

#### 8.15.2 Event Types

Four event types form a complete and orthogonal basis for execution observation:

| Event | Observes | Description |
|-------|----------|-------------|
| `enter` | Function application | Function call with arguments and source location |
| `exit` | Function return | Return value and wall-time duration |
| `state` | Store transitions | Mutation of `let mut` bindings |
| `effect` | Effect operations | Algebraic effect invocations (IO, FS, DB, etc.) |

Program termination events (`panic`, assertion failures) are not trace events — they produce structured diagnostics through the existing error reporting pipeline (§8.6).

#### 8.15.3 Schema

All events share common fields:

| Field | Type | Present | Description |
|-------|------|---------|-------------|
| `ts_us` | Int | all | Monotonic microseconds since trace start |
| `event` | Str | all | `"enter"` \| `"exit"` \| `"state"` \| `"effect"` |
| `fn` | Str | all | Fully-qualified function name (`module.function`) |
| `module` | Str | all | Module name |
| `depth` | Int | all | Call stack depth (0 = top-level) |

Per-event fields:

| Field | Type | Event | Description |
|-------|------|-------|-------------|
| `span` | `{file, line, col}` | `enter` | Source location (same shape as diagnostic spans, §8.6) |
| `args` | `{name: str}` | `enter` | Function arguments as Display strings. Omitted if no args |
| `duration_us` | Int | `exit` | Wall time in function (microseconds) |
| `return` | Str | `exit` | Return value as Display string |
| `var` | Str | `state` | Variable name |
| `op` | Str | `state` | `"assign"` \| `"push"` \| `"pop"` \| `"insert"` \| `"remove"` |
| `value` | Str | `state` | New value as Display string (post-mutation) |
| `effect` | Str | `effect` | Effect type (e.g. `"IO.Print"`, `"FS.Write"`) |
| `op` | Str | `effect` | Operation name (e.g. `"io.println"`) |
| `args` | `{name: str}` | `effect` | Operation arguments as Display strings |

Design notes:
- **`span` appears only on `enter`** — source location is static per function, saving ~40 bytes on other events.
- **`module` is a separate field** despite being derivable from `fn` — enables O(1) module-level filtering without string splitting.
- **`duration_us` on `exit`** — computed by the emitter rather than requiring consumers to maintain an enter-timestamp stack.
- **All values are Display strings** — bounded serialization cost; values longer than 200 characters are truncated with a `"truncated":true` field appended.

#### 8.15.4 Example

A function that enters, mutates state, performs an effect, and exits:

```json
{"ts_us":18042,"event":"enter","fn":"parser.write_output","module":"parser","depth":3,"span":{"file":"src/parser.bl","line":142,"col":1},"args":{"path":"out.c"}}
{"ts_us":18044,"event":"state","fn":"parser.write_output","module":"parser","depth":3,"var":"files_written","op":"assign","value":"1"}
{"ts_us":18045,"event":"effect","fn":"parser.write_output","module":"parser","depth":3,"effect":"FS.Write","op":"fs.write_file","args":{"path":"out.c"}}
{"ts_us":18048,"event":"exit","fn":"parser.write_output","module":"parser","depth":3,"duration_us":6,"return":"()"}
```

#### 8.15.5 Filter Syntax

Filters use colon-syntax: `--trace=key:value`. Multiple filters compose with AND (comma-separated). Multiple values for the same key compose with OR (`+` separator).

| Filter | Meaning |
|--------|---------|
| `fn:<name>` | Match function name (short or fully-qualified) |
| `module:<name>` | Match module name |
| `depth:<n>` | Events at call depth <= N |
| `event:<type>` | Only emit specified event types |
| `effect:<name>` | Match effect type (e.g. `FS.Write`) |
| `state:<var>` | Match state variable name |

Examples:

```sh
blink run app.bl --trace=module:parser,depth:2          # parser module, depth <= 2
blink run app.bl --trace=fn:skip_newlines+parse_block   # two functions (OR)
blink run app.bl --trace=event:state,module:parser      # state events in parser only
```

Bare `--trace` with no value traces all events. The `BLINK_TRACE` environment variable accepts the same filter syntax.

#### 8.15.6 Timestamp Semantics

`ts_us` is a monotonic microsecond counter relative to trace start (not wall-clock time). The clock source is `clock_gettime(CLOCK_MONOTONIC)` on Linux, `mach_absolute_time()` on macOS. Microsecond resolution matches the instrumentation overhead — sub-microsecond precision would measure the tracer, not the program.

---

### 8.16 Language Evolution

Blink evolves without breaking existing programs. The mechanism is **editions** — a per-package declaration that opts into a set of stdlib changes, keyword reservations, and lint severity upgrades. Combined with a rich `@deprecated` annotation and automated migration tooling, editions let the language improve continuously while maintaining infinite backward compatibility.

#### 8.16.1 Editions

An edition is a named yearly snapshot of language-surface defaults. Each package declares its edition in `blink.toml`:

```toml
[package]
name = "acme/myapp"
version = "1.0.0"
edition = "2026"
```

**Semantics:**

- **Per-package.** Each package in a dependency graph can use a different edition. A 2026-edition library compiles alongside a 2028-edition application with no friction — the compiler carries code for all editions simultaneously.
- **Scope.** Editions gate three things:
  1. **Stdlib API** — deprecated functions become errors, new defaults take effect
  2. **Keywords** — a new edition can reserve identifiers (e.g., promoting a soft keyword to a hard keyword)
  3. **Lint severity** — warnings in edition N can become errors in edition N+1
- **NOT core syntax.** Editions never change the grammar of `fn`, `match`, `let`, `if`, braces, or any core construct. An edition cannot make previously-valid syntax invalid (except for newly reserved keywords). The AST structure is eternal.
- **Infinite compatibility.** Every edition is supported forever. The compiler never drops support for an older edition. A `edition = "2026"` package compiles with the 2035 compiler. There is no "upgrade or die" — upgrading editions is always voluntary.
- **Default.** When `edition` is omitted from `blink.toml`, the compiler uses the latest stable edition at the time the compiler was built. For new projects, `blink init` writes the current edition explicitly.

**How editions interact with dependencies:** The compiler resolves each package's edition independently. If package A (edition 2028) depends on package B (edition 2026), the compiler checks A against 2028 rules and B against 2026 rules. No edition leaks across package boundaries. This is why editions can only gate per-package concerns (stdlib, keywords, lint) — they cannot change type system semantics or effect resolution, which are cross-package.

#### 8.16.2 `@deprecated` Semantics

The `@deprecated` annotation marks functions, types, and methods for eventual removal. It carries structured metadata enabling automated migration:

```blink
@deprecated(
    since: "2026",
    removal: "2028",
    replacement: "login_v2",
    fix: "replace"
)
pub fn login(email: Str, pwd: Str) -> Result[Session, AuthError] ! DB, Crypto {
    login_v2(email, pwd)
}
```

**Fields:**

| Field | Type | Required | Meaning |
|-------|------|----------|---------|
| `since` | `Str` (edition) | Yes | Edition in which the deprecation was introduced |
| `removal` | `Str` (edition) | No | Edition in which usage becomes a compile error |
| `replacement` | `Str` | No | Qualified name of the replacement API |
| `fix` | `Str` | No | Machine-applicable fix strategy: `"replace"`, `"inline"`, or `"manual"` |

**Warning/error behavior:**

- **Current edition < `removal`:** Usage emits warning W2000 (DeprecatedUsage). The program compiles successfully.
- **Current edition >= `removal`:** Usage emits error E2001 (RemovedAPI). The program does not compile.
- **No `removal` field:** The item is deprecated indefinitely — always W2000, never E2001.

```json
{
  "severity": "warning",
  "name": "DeprecatedUsage",
  "code": "W2000",
  "message": "use of deprecated function `login`",
  "span": {"file": "src/auth.bl", "line": 42, "col": 5},
  "labels": [
    {"span": {"line": 42, "col": 5}, "message": "deprecated since edition 2026, removal in edition 2028"}
  ],
  "help": "use `login_v2` instead",
  "fix": {
    "description": "Replace `login` with `login_v2`",
    "edits": [
      {
        "span": {"file": "src/auth.bl", "line": 42, "col": 5, "end_col": 10},
        "replace": "login_v2"
      }
    ]
  }
}
```

When `fix` is `"replace"` and `replacement` is provided, the compiler emits a machine-applicable fix in structured diagnostics (§8.6). When `fix` is `"manual"`, the diagnostic includes `help` text but no automatic edit. When `fix` is `"inline"`, the compiler suggests inlining the replacement expression.

The `@deprecated` annotation is the canonical mechanism for all API lifecycle communication — stdlib changes, user library evolution, and cross-package migration all use the same annotation with the same structured diagnostic output. See §11.1 for annotation catalog placement.

#### 8.16.3 `blink migrate`

The `blink migrate` command applies all machine-applicable deprecation fixes and advances the package's edition:

```sh
blink migrate
```

**What it does:**

1. Compiles the package at the current edition, collecting all W2000 warnings with `fix` fields
2. Applies all machine-applicable fixes (those with `fix: "replace"` or `fix: "inline"`)
3. Updates `edition` in `blink.toml` to the next edition
4. Re-compiles to verify the migration succeeded
5. Reports any remaining manual migrations

**Structured output:**

```json
{
  "command": "migrate",
  "from_edition": "2026",
  "to_edition": "2027",
  "fixes_applied": 12,
  "fixes_manual": 2,
  "files_modified": ["src/auth.bl", "src/users.bl"],
  "manual_actions": [
    {
      "code": "W2000",
      "function": "db.raw_query",
      "message": "Replace with db.query() using Template[C] parameterization",
      "span": {"file": "src/db.bl", "line": 18, "col": 5}
    }
  ],
  "success": true
}
```

**Flags:**

- `--dry-run` — show what would change without modifying files
- `--edition <year>` — migrate to a specific edition (skipping intermediate editions is allowed; all fixes from intermediate editions are applied cumulatively)
- `--json` — structured JSON output (default when piped)

The `blink migrate` command is idempotent. Running it on a package that is already at the target edition produces no changes.

#### 8.16.4 `blink editions`

The `blink editions` command displays a built-in changelog of all editions, compiled directly into the `blink` binary. No network access required — the changelog is always available offline.

```sh
blink editions
```

```
Edition 2027 (released 2027-01-15)
  Deprecated:
    - List.get() now returns Option[T] (was raw T) [since 2026, removal 2028]
    - Str.find() renamed to Str.index_of() [since 2027, removal 2029]
  New:
    - std.bytes module (Tier 1)
    - Pattern matching: nested OR-patterns

Edition 2026 (released 2026-06-01)
  Initial edition. No deprecations.
```

**Flags:**

- `--breaking` — show only items with a `removal` edition (items that will become compile errors)
- `--json` — structured JSON output for tooling and AI consumption
- `--edition <year>` — show changes for a specific edition only

The changelog is also exposed in the `llms.txt` header (§8.3) as an edition-specific API change summary, giving AI agents immediate awareness of what has changed between the edition a project uses and the current edition.

#### 8.16.5 Edition Cadence

- **At most one edition per year.** Editions are not releases — they are compatibility snapshots. Most years will have zero or one edition.
- **2+ year deprecation window.** Any item deprecated in edition N cannot have `removal` earlier than edition N+2. This gives downstream consumers at minimum two years to migrate.
- **Infinite backward compatibility.** The compiler never drops edition support. Edition 2026 code compiles with the 2040 compiler. The cost of carrying old editions is near-zero — edition logic is a small set of conditionals in stdlib resolution and lint severity tables.
- **Enforced semver (v2).** In v2, the package manager enforces that `removal` editions align with major version bumps of the package. A library cannot remove a deprecated API within the same major version. This is not enforced in v1 (path + git deps only, no registry infrastructure).
- **No flag days.** Because editions are per-package and compatibility is infinite, there is never a moment where the ecosystem must upgrade in lockstep. Each package migrates on its own schedule.

---

### 8.17 Summary

The tooling story is not a feature list — it is the thesis of the language:

1. **The compiler is a service,** not a batch job. It runs continuously, maintains a live model, and responds in milliseconds.
2. **Code is queryable,** not just readable. Semantic access to the codebase by effect, type, intent, and contract.
3. **Inspection is layered.** The AI chooses the granularity it needs — from 20-token intent summaries to full implementations.
4. **Diagnostics are structured.** Errors include machine-applicable fixes. The AI's fix loop is mechanical, not inferential.
5. **Alternatives are preserved.** Multiple valid implementations coexist, type-checked, selectable by configuration.
6. **There is one tool for each job.** One formatter, one package manager, one test runner, one way to do everything.

The result: an AI agent working with Blink has roughly 8x the effective context capacity, sub-second feedback loops, and structured machine-readable access to every aspect of the codebase. This is the difference between AI as a code completion engine and AI as a software engineering partner.
