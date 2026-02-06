## 8. Tooling & AI Interaction

### 8.1 Philosophy: Tooling IS the Language

Most languages treat tooling as an afterthought — a separate ecosystem of linters, formatters, package managers, and IDE plugins built by third parties, often incompatible, always fragmented. Pact rejects this entirely.

In Pact, the tooling is not adjacent to the language. It is the language. The compiler, formatter, package manager, test runner, and LSP are a single unified system with one dependency graph, one data model, and one structured output format. Every tool speaks the same AST. Every tool is driven by the same daemon process.

This matters for AI-assisted development because:

1. **Zero configuration decisions.** An AI agent never asks "which formatter?", "which test framework?", "which package manager?" There is exactly one answer to every tooling question.

2. **Structured everything.** Every tool produces structured JSON. The AI never parses freeform error strings, never scrapes terminal output, never guesses at formats. Machine-readable in, machine-readable out.

3. **Semantic access.** The AI doesn't read files — it queries the compiler. "Show me everything that writes to the database" is a single command, not a grep across 200 files hoping the naming conventions are consistent.

4. **Sub-second feedback.** The compiler daemon maintains a live dependency graph. Incremental type-checking of a single changed function targets sub-200ms. The AI's generate-compile-fix loop runs at the speed of thought, not the speed of `make`.

The combined effect is transformative: Pact gives an AI agent roughly 8x the effective context capacity of Python with file-based reads. Not through syntax tricks — through architectural decisions about how code is stored, queried, and validated.

---

### 8.2 Compiler-as-Service Architecture

The Pact compiler is not a batch process. It is a persistent daemon that runs for the lifetime of a development session, maintaining a live, incremental model of the entire codebase.

```
┌─────────────────────────────────────────────────┐
│                 pact daemon                      │
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

**Symbol-level granularity.** The dependency graph tracks individual functions, types, and traits — not files. When you change one function, the daemon re-checks only that function and its direct dependents. File-level granularity (Rust, Go) re-checks entire files; Pact re-checks the minimal subgraph.

**The compiler IS the LSP.** There is no separate LSP implementation that reimplements half the compiler and gets the other half wrong. Completions, hover info, go-to-definition, refactoring, and diagnostics all come from the same type-checking pass that produces compilation errors. They are always consistent.

**Structured JSON output.** Every compiler output — errors, warnings, query results, completions — is structured data with stable schemas. AI agents consume compiler output directly, not through regex parsing of terminal text.

**Sub-200ms incremental checking.** Target latency for re-checking a single changed function in a 100k-line codebase. This is what makes the AI's tight generate-compile-fix loop viable. The daemon achieves this by:
- Keeping the full symbol table in memory
- Tracking fine-grained dependencies (function A calls function B, not "file X imports file Y")
- Only re-running type inference / effect checking on the changed symbol and its reverse dependencies
- Deferring codegen until explicitly requested

```sh
# The daemon starts automatically on first pact command
pact check              # type-check, daemon stays alive
pact check src/auth.pact  # re-check one file (daemon uses cached graph)

# Explicit daemon management
pact daemon start       # start manually
pact daemon status      # show uptime, memory, graph size
pact daemon stop        # shut down
```

---

### 8.3 Layered Inspection Model

This is the single most impactful feature for AI context efficiency.

Current AI coding tools read entire files to understand a codebase. A 100-function project might require reading 20 files (~50,000 tokens) just to understand the architecture before making a single change. Most of those tokens are implementation details the AI doesn't need.

Pact's compiler-as-service exposes code at four granularity levels. The AI chooses the level of detail it needs:

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
pact query --layer intent --module auth
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
pact query --layer signature --fn auth.login,auth.verify_creds
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
pact query --layer full --fn auth.verify_creds
```

Total tokens consumed: ~2,320 instead of ~50,000. That is a **20x reduction** for a targeted modification — and the AI had full architectural context the entire time.

---

### 8.4 Intent Declarations (`@i`)

Intent declarations are structured, compiler-tracked annotations that capture *what* a function does and *why* it exists, in natural language:

```pact
@i("Validate user credentials against stored hash, returning the user on success")
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

Intent declarations are not comments. They are:

**Compiler-tracked.** The compiler stores intents in the symbol table alongside types and effects. They participate in the query system and are included in structured compiler output.

**Queryable.** `pact query --intent "authentication"` finds every function whose intent mentions authentication. This is semantic search over the codebase, not string matching — the query engine understands synonyms and related concepts.

**Versioned.** When an intent annotation changes, it shows up in diffs. When an implementation changes but its intent doesn't, the toolchain can flag the drift for review (future: automated drift detection).

**Compressed representation.** The intent layer is the most token-efficient representation of a codebase. An AI can understand the architecture of a 500-function project from ~10,000 tokens of intent annotations — less than a single large source file in most languages.

```pact
@i("Main auth flow: rate check, verify credentials, issue token")
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

The `@i` annotation answers: "If I had 10 words to describe this function, what would they be?" Every function in a Pact codebase should have one. The AI uses them as a table of contents for the codebase.

---

### 8.5 Semantic Query System

The query system lets AI agents (and humans) search the codebase by meaning, not by text patterns. Queries run against the compiler's live symbol table — they are fast, precise, and always up-to-date.

**Query by effect — find everything that writes to the database:**

```sh
pact query --effect "DB.Write"
```

```json
{
  "matches": [
    {
      "function": "auth.login",
      "effects": ["IO", "DB.Read", "DB.Write", "Cache"],
      "file": "src/auth.pact",
      "line": 42
    },
    {
      "function": "users.update_profile",
      "effects": ["DB.Write", "IO"],
      "file": "src/users.pact",
      "line": 18
    }
  ]
}
```

**Query by type signature — find all functions returning a specific error type:**

```sh
pact query --type "* -> Result[*, AuthError]"
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
pact query --intent "rate limit"
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
pact query --ensures "*.is_sorted"
```

**Query combinations — find pure functions that take a list and return a list:**

```sh
pact query --type "List[*] -> List[*]" --pure
```

The query system replaces the manual "grep, open file, read surrounding context, figure out what it does" loop that dominates current AI coding workflows. One structured query replaces dozens of file reads.

---

### 8.6 Structured Diagnostics with Machine-Applicable Fixes

Every compiler diagnostic is structured JSON with a stable schema. Errors include machine-applicable fix suggestions that an AI agent can apply directly — no parsing of freeform error messages, no heuristic extraction of fix hints.

```json
{
  "severity": "error",
  "code": "E0004",
  "message": "non-exhaustive match",
  "span": {
    "file": "src/auth.pact",
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
        "span": {"file": "src/auth.pact", "line": 27, "col": 0},
        "insert": "        Locked => Err(AccountLocked)\n"
      }
    ]
  },
  "related": [
    {
      "message": "`AuthError` variant `Locked` defined here",
      "span": {"file": "src/auth.pact", "line": 5, "col": 5}
    }
  ]
}
```

What this gives the AI:

- **Error code** (`E0004`) — stable identifier, can be mapped to fix strategies
- **Exact span** — the AI knows precisely which code to modify
- **Machine-applicable edits** — the `fix.edits` array contains insert/replace/delete operations the AI can apply verbatim
- **Related locations** — where the type/trait/variant was defined, for context
- **No guesswork** — the AI doesn't interpret an English sentence and hope it understands what the compiler meant

The effect on the generate-compile-fix loop is dramatic. In Python, an AI reads a traceback, infers what went wrong, generates a fix hypothesis, applies it, and hopes. In Pact, the compiler tells the AI exactly what's wrong, exactly where, and often exactly how to fix it. The fix loop becomes mechanical rather than inferential.

---

### 8.7 Alternatives System (`@alt`)

AI agents frequently generate multiple valid solutions to a problem. In current workflows, only one survives — the others are discarded, lost to the chat history. Pact's alternatives system preserves all valid implementations as first-class entities in the codebase.

```pact
@i("Validate user credentials against stored hash")
fn verify_creds(email: Str, pwd: Str) -> Result[User, AuthError] ! DB {
    let user = db.query_one("SELECT * FROM users WHERE email = {email}")
        ?? return Err(NotFound)
    if !crypto.verify(pwd, user.hash) {
        return Err(BadCreds)
    }
    Ok(user)
}

@alt("CRED-ALT-001", "Cache-backed credential verification")
@i("Verify credentials with cache layer to reduce DB load")
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
pact alt list auth.verify_creds
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
pact alt select CRED-ALT-001

# Compare two implementations side-by-side
pact alt compare auth.verify_creds
```

```
  Effect diff:  primary: ! DB
                CRED-ALT-001: ! DB, Cache (+Cache)

  Contract diff:
    Both satisfy @ensures(result.is_ok => crypto.verify(pwd, result.unwrap().hash))
    CRED-ALT-001 does NOT satisfy: "always uses latest DB data" (stale cache)
```

Alternatives are selected per-environment via `pact.toml`:

```toml
[alternatives]
"CRED-ALT-001" = { environments = ["production"], enabled = true }
```

This means different alternatives can be active in staging vs production. The selection is a configuration concern, not a source code change — no feature flag `if` statements polluting the implementation.

---

### 8.8 Built-in Formatter

```sh
pact fmt                # format everything
pact fmt src/auth.pact  # format one file
```

There are zero configuration options. The canonical style IS the grammar — there is exactly one valid way to format any Pact program. The formatter is not a tool you run; it is a property of the language.

What this means in practice:

- **AI-generated code is indistinguishable from human code.** No style drift, no "this looks AI-generated" formatting quirks.
- **Diffs are always semantic.** Every line in a diff represents a behavioral change, never a formatting change. No "reformatted the whole file" noise commits.
- **No bikeshedding.** Tabs vs spaces, brace placement, line length — none of these are decisions. They are answered by the grammar itself.
- **Deterministic output.** Given any syntactically valid Pact program, `pact fmt` produces exactly one output. Two developers formatting the same code always get identical results.

The formatter runs in the compiler daemon, so it shares the parser. Formatting is near-instantaneous — it is a render pass over the AST, not a separate parse-transform-emit pipeline.

---

### 8.9 Built-in Package Manager

```sh
pact add serde          # add a dependency
pact remove serde       # remove a dependency
pact update             # update all deps within constraints
pact update serde       # update one dependency
```

One package manager. Mandatory lockfile. Content-addressed storage. Deterministic resolution.

There is no `pact.lock` vs `package-lock.json` vs `yarn.lock` decision. There is no pip vs pipenv vs poetry vs uv decision. There is no npm vs yarn vs pnpm decision. There is `pact add`.

The lockfile (`pact.lock`) is always committed to version control. Builds without a lockfile are an error — not a warning, an error. Reproducible builds are not optional.

```toml
# pact.toml — project manifest
[package]
name = "myapp"
version = "0.1.0"

[dependencies]
serde = "1.2"
http = "0.5"

[dev-dependencies]
bench = "0.3"
```

The package manager is integrated with the compiler daemon. When you run `pact add`, the daemon immediately re-checks the dependency graph and reports any type conflicts with the new dependency. You find out about incompatibilities at add time, not at build time.

---

### 8.10 Built-in Test Runner

Tests in Pact are not a library. They are first-class syntax — `test` blocks are part of the grammar, understood by the parser, type-checked by the compiler, and run by the built-in test runner.

```pact
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

**Test output is structured JSON:**

```sh
pact test --json
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
      "span": {"file": "src/auth.pact", "line": 58, "col": 5}
    }
  ],
  "summary": {"total": 14, "pass": 13, "fail": 1, "duration_ms": 340}
}
```

The AI reads structured test failures the same way it reads structured compiler errors — exact location, expected vs actual values, no string parsing.

```sh
pact test                       # run all tests
pact test --filter "auth"       # run tests matching pattern
pact test --prop                # run only property tests
pact test --doc                 # run only doc-tests
pact test --coverage            # with coverage report (JSON)
```

---

### 8.11 Token Efficiency Analysis

Pact's AI-efficiency gains come from three compounding layers. Each layer delivers real savings; together they are transformative.

#### Layer 1: Syntax (15-25% savings)

Pact's syntax is denser than Python or TypeScript without sacrificing clarity. Token savings from:

| Source | Saving |
|--------|--------|
| No semicolons | ~1 token/statement |
| `fn` vs `function`/`def` | 1 token per declaration |
| `Str` vs `String`, `Int` vs `Integer` | 1 token per type reference |
| No `import` boilerplate (effects provide handles) | 3-10 tokens per file |
| Universal string interpolation (no `f"..."` prefix) | 1 token per interpolated string |
| `T?` vs `Option[T]` in type position | 1-2 tokens per optional |
| `??` vs if-else/ternary for defaults | 2-4 tokens per default |

Cumulative: a typical 50-line function is 15-25% fewer tokens in Pact than the equivalent Python.

#### Layer 2: Structure (25-40% savings)

Pact's design eliminates entire categories of boilerplate:

| Traditional pattern | Pact equivalent | Token savings |
|----|----|----|
| Import statements (5-15 per file) | Effect handles + module system | 80-95% of import tokens |
| Dependency injection setup | Effect handlers | Constructor + binding boilerplate eliminated |
| Class hierarchies for polymorphism | ADTs + traits | No `class`, `extends`, `implements` ceremony |
| Exception handling (try/catch/finally) | `Result[T, E]` + `?` | 60-80% fewer error handling tokens |
| Null checking (`if x is not None`) | `??` and exhaustive matching | 50-70% fewer null-handling tokens |
| Test framework boilerplate | First-class `test` blocks | No `import unittest`, `class TestX`, `def setUp` |

Cumulative: a typical module is 25-40% fewer tokens than equivalent Python including imports, class definitions, and error handling.

#### Layer 3: Access (50-90% savings) — The Transformative Win

This is where Pact pulls away from every other language. The savings come not from syntax but from how the AI accesses code:

| Operation | Traditional (Python + file reads) | Pact (semantic queries) |
|----|----|----|
| Understand project architecture | Read 10-20 files (~50k tokens) | `pact query --layer intent` (~2k tokens) |
| Find all DB-writing functions | grep + manual reading (~5k tokens) | `pact query --effect DB.Write` (~500 tokens) |
| Check a function's contract | Read function + all callers (~3k tokens) | `pact query --layer contract --fn X` (~60 tokens) |
| Understand API surface | Read all public functions (~15k tokens) | `pact query --layer signature --pub` (~4k tokens) |
| Find functions by purpose | grep + reading context (~8k tokens) | `pact query --intent "rate limit"` (~200 tokens) |

The access layer savings compound with the syntax and structure savings. An AI working with Pact uses:
- 15-25% fewer tokens to represent the same code (syntax)
- 25-40% fewer tokens per module due to eliminated boilerplate (structure)
- 50-90% fewer tokens to navigate and understand the codebase (access)

**Combined effect: ~8x effective context capacity vs Python + file-based reads.**

For a 128k-token context window, this means:
- Python + file reads: effectively ~16k tokens of useful code context (rest is boilerplate, imports, irrelevant functions)
- Pact + semantic queries: effectively ~128k tokens of useful code context

The AI can hold an entire medium-sized project in its working memory. It can make cross-cutting changes that require understanding dozens of functions. It can refactor with full architectural context. This is the difference between an AI that edits one function at a time and an AI that understands the system.

---

### 8.12 Semantic Diffs

Standard `git diff` shows textual changes — lines added, lines removed. Pact's `pact diff` understands what changed semantically:

```sh
pact diff HEAD~1
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

### 8.13 `pact eval` — Fast Interactive Execution

For rapid AI iteration, `pact eval` interprets code directly from the AST with full type checking and effect tracking — no compilation step:

```sh
pact eval "auth.login(\"test@example.com\", \"pass123\", \"127.0.0.1\")"
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

`pact eval` is for development and testing. Production always uses the AOT-compiled binary.

---

### 8.14 Complete CLI Reference

| Command | Description |
|---------|-------------|
| **Build & Run** | |
| `pact build` | Compile to native binary |
| `pact build --target wasm` | Compile to WebAssembly |
| `pact run` | Compile and execute in one step |
| `pact check` | Type-check without codegen (fast) |
| `pact eval <expr>` | Interpret an expression with full checking |
| **Query & Inspect** | |
| `pact query --layer intent` | Get intent annotations for all functions |
| `pact query --layer signature` | Get function signatures with types and effects |
| `pact query --layer contract` | Get signatures + @requires/@ensures |
| `pact query --layer full --fn <name>` | Get complete implementation of a function |
| `pact query --effect <Effect>` | Find functions by effect |
| `pact query --type "<pattern>"` | Find functions by type signature pattern |
| `pact query --intent "<text>"` | Find functions by intent (semantic search) |
| `pact query --ensures "<predicate>"` | Find functions by contract |
| `pact query --pub` | Filter to public API only |
| `pact query --pure` | Filter to pure functions only |
| `pact query --module <name>` | Scope query to a module |
| **Testing** | |
| `pact test` | Run all tests |
| `pact test --filter "<pattern>"` | Run tests matching pattern |
| `pact test --prop` | Run property tests only |
| `pact test --doc` | Run doc-tests only |
| `pact test --coverage` | Run with coverage reporting |
| `pact test --json` | Output results as structured JSON |
| **Formatting & Style** | |
| `pact fmt` | Format all files (canonical style) |
| `pact fmt <file>` | Format one file |
| **Dependencies** | |
| `pact add <pkg>` | Add a dependency |
| `pact remove <pkg>` | Remove a dependency |
| `pact update` | Update all dependencies within constraints |
| `pact update <pkg>` | Update one dependency |
| **Alternatives** | |
| `pact alt list` | List all alternatives in the project |
| `pact alt list <fn>` | List alternatives for a specific function |
| `pact alt select <alt-id>` | Activate an alternative implementation |
| `pact alt compare <fn>` | Compare alternatives side-by-side |
| **Diagnostics & Analysis** | |
| `pact diff [ref]` | Semantic diff against a git ref |
| `pact trace <requirement>` | Show all code linked to a requirement ID |
| `pact ast <file>` | Dump AST as JSON |
| **Daemon** | |
| `pact daemon start` | Start compiler daemon explicitly |
| `pact daemon status` | Show daemon status and graph stats |
| `pact daemon stop` | Stop compiler daemon |

All commands that produce output accept `--json` for structured JSON output. All commands that operate on code use the compiler daemon for incremental performance.

---

### 8.15 Summary

The tooling story is not a feature list — it is the thesis of the language:

1. **The compiler is a service,** not a batch job. It runs continuously, maintains a live model, and responds in milliseconds.
2. **Code is queryable,** not just readable. Semantic access to the codebase by effect, type, intent, and contract.
3. **Inspection is layered.** The AI chooses the granularity it needs — from 20-token intent summaries to full implementations.
4. **Diagnostics are structured.** Errors include machine-applicable fixes. The AI's fix loop is mechanical, not inferential.
5. **Alternatives are preserved.** Multiple valid implementations coexist, type-checked, selectable by configuration.
6. **There is one tool for each job.** One formatter, one package manager, one test runner, one way to do everything.

The result: an AI agent working with Pact has roughly 8x the effective context capacity, sub-second feedback loops, and structured machine-readable access to every aspect of the codebase. This is the difference between AI as a code completion engine and AI as a software engineering partner.
