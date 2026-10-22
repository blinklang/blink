## 8. Tooling & AI Interaction

### 8.1 Philosophy: Tooling IS the Language

Most languages treat tooling as an afterthought — a separate ecosystem of linters, formatters, package managers, and IDE plugins built by third parties, often incompatible, always fragmented. Blink rejects this entirely.

In Blink, the tooling is not adjacent to the language. It is the language. The compiler, formatter, package manager, test runner, and LSP are a single unified system with one dependency graph, one data model, and one structured output format. Every tool is driven by the same daemon process.

This matters for AI-assisted development because:

1. **Zero configuration decisions.** An AI agent never asks "which formatter?", "which test framework?", "which package manager?" There is exactly one answer to every tooling question.

2. **Structured everything.** Every tool produces structured JSON. The AI never parses freeform error strings, never scrapes terminal output, never guesses at formats. Machine-readable in, machine-readable out.

3. **Semantic access.** The AI doesn't read files — it queries the compiler. "Show me everything that writes to the database" is a single command, not a grep across 200 files hoping the naming conventions are consistent.

4. **Sub-second feedback.** The compiler daemon maintains a live dependency graph. Incremental type-checking of a single changed function targets sub-200ms. The AI's generate-compile-fix loop runs at the speed of thought, not the speed of `make`.

The combined effect is transformative: Blink gives an AI agent roughly 8x the effective context capacity of Python with file-based reads. Not through syntax tricks — through architectural decisions about how code is stored, queried, and validated.

---

### 8.2 Compiler as a Service

The Blink compiler is not a batch process. It runs as a persistent daemon for the length of a development session. The daemon keeps a live model of the codebase between commands.

Key properties:

**Fine-grained re-checking.** When you change one function, the daemon re-checks that function and the code that depends on it. It does not re-check the whole file.

**The compiler IS the LSP.** There is no separate LSP implementation that reimplements half the compiler and gets the other half wrong. Completions, hover info, go-to-definition, refactoring, and diagnostics all come from the same checks that produce compilation errors. The CLI and the LSP always give the same diagnostics. Hover, go-to-definition and `blink query` report the entity that a bare name denotes at a site, by the rules of §3.4 *Values come first*: the same entity that the program uses when it runs.

**Structured JSON output.** Every compiler output — errors, warnings, query results, completions — is structured data with stable schemas. AI agents consume compiler output directly, not through regex parsing of terminal text.

**Sub-200ms incremental checking.** The goal is a latency under 200ms for re-checking a single changed function in a 100k-line codebase. This is what makes the AI's tight generate-compile-fix loop viable. The daemon generates code only when you ask for it.

```sh
# The daemon starts automatically on first blink command
blink check              # type-check, daemon stays alive
blink check src/auth.bl  # re-check one file (daemon uses cached results)

# Explicit daemon management
blink daemon start       # start manually
blink daemon status      # show uptime and memory use
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
    let user = db.query_one(t"SELECT * FROM users WHERE email = {email}")
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

**Applying fixes.** `blink fix` applies the machine-applicable fixes in a set of diagnostics. When two fixes contain the same edit (same span, same text), it applies that edit once. Two different edits whose spans overlap are a conflict: `blink fix` applies neither and reports both diagnostics.

The effect on the generate-compile-fix loop is dramatic. In Python, an AI reads a traceback, infers what went wrong, generates a fix hypothesis, applies it, and hopes. In Blink, the compiler tells the AI exactly what's wrong, exactly where, and often exactly how to fix it. The fix loop becomes mechanical rather than inferential.

---

### 8.7 Alternatives System (`@alt`)

AI agents frequently generate multiple valid solutions to a problem. In current workflows, only one survives — the others are discarded, lost to the chat history. Blink's alternatives system preserves all valid implementations as first-class entities in the codebase.

```blink
/// Validate user credentials against stored hash
fn verify_creds(email: Str, pwd: Str) -> Result[User, AuthError] ! DB {
    let user = db.query_one(t"SELECT * FROM users WHERE email = {email}")
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
            let u = db.query_one(t"SELECT * FROM users WHERE email = {email}")
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
- **Variant order is meaning.** `blink fmt` never reorders the variants of an enum, and no auto-fix or refactor tool does so without a request from the user. Variant order sets `to_int()`, the comparison with `Int` and the enum's `Ord` (§3.4 *Tag Operations*, §3.6 *Enum Ord*).

The formatter runs in the compiler daemon.

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
sodium = { type = "system" }                  # links -lsodium, must be on target
mylib = { type = "vendored", path = "vendor/mylib.c" }  # compiled from source

[alternatives]                                # §4.10 alt-effect registrations
Net.Connect = "mock-http"                     # test alternative
```

**Dependency source table:** Each dependency specifies exactly one source — `version` (registry), `git`, or `path`. Combining sources is an error. An entry with no source is an error too (`MissingDependencySource`, §8.9.8).

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

The `blink.toml` schema is **forward-compatible**: adding `version = "1.0"` registry deps in v2 requires no schema changes. The registry is an additional source, not a replacement. The schema reserves `version` now; §8.9.8 sets what a toolchain does with a key that this specification does not define.

Import paths follow the `org/name` structure: `import std.http` maps to the `std/http` package. Local modules shadow dependencies with the same path, with compiler warning W1000 (§10.5).

#### 8.9.8 Manifest Diagnostics

**Positions.** Each diagnostic about `blink.toml` gives a line and a column in `blink.toml`. The span depends on what is wrong:

| Fault | Span |
|-------|------|
| A bad value | the value token, quotes included |
| A bad key | the key |
| A bad section | the `[header]` |
| A missing key | the `[header]` of the section that lacks it |
| A missing section (no `[package]`) | line 1, column 1, zero width |
| A dependency with no source | the token that names the dependency: the key for the inline form, the whole `[header]` for the table form (`[dependencies."local/utils"]`, quoted dotted segments included) |

There is no fallback position: every manifest diagnostic points at the token at fault, or, when the fault is an absent token, at the position that this table gives.

**Unknown sections.** A top-level section that this specification does not define is the warning `UnknownManifestSection` (W1001). §8.9.3 defines most sections, and §4.16.8 defines `[lints]`. The span is the `[header]`. When a defined section name is close to the unknown one, the help line offers it:

```toml
[dependecies]                # warning[UnknownManifestSection]: help: did you mean `[dependencies]`?
local/utils = { path = "../utils" }
```

W1001 is a warning, so a manifest written for a newer toolchain still builds (§8.9.7). `--strict` and a `[lints]` entry can make it an error, as for any warning.

A misspelled section often causes a second error later: the compiler does not see the dependencies in it. When W1001 fired in the same build, `ModuleNotFound` (E1200) and `PackageNotDeclared` (E1052) each add a `note:` that points at the unknown section.

**Unknown keys.** Some tables have keys that this specification fixes. These tables are *closed*: `[package]`, `[capabilities]`, each dependency entry (the inline table of a key in `[dependencies]` or `[dev-dependencies]`) and each native-dependency entry (§9.1.2). Their keys are the keys that §8.9.3 and §9.1.2 list. The keys of `[dependencies]`, `[dev-dependencies]`, `[native-dependencies]`, `[alternatives]` and `[lints]` are names, and the checks for those names apply (for `[lints]`, §4.16.8 and E0842); the rules below do not apply to them.

A field that picks a build input is an error. Other unknown keys are warnings:

- An unknown key in `[package]` or `[capabilities]` is the warning `UnknownManifestKey` (W1002). The toolchain reads the section without the key. `--strict` and a `[lints]` entry can make W1002 an error, as for W1001.
- An unknown field in a dependency entry or a native-dependency entry is the error `UnknownDependencyField` (E1014). No `[lints]` entry changes it. These fields choose what the toolchain fetches, compiles or links, so a field that the toolchain ignores builds a different program. For example, if `tga` stands for `tag`, the toolchain fetches the default branch and `blink.lock` pins it. The message has one `note:` line that gives this reason.

Both diagnostics span the key. The help line offers the nearest key of the same table (ERROR_CATALOG.md, *Conventions*). A key of another table is never a candidate.

```toml
[package]
name = "x"
version = "0.1.0"
nmae = "y"
```

```
warning[UnknownManifestKey]: `[package]` has no key `nmae`
 --> blink.toml:4:1
  |
4 | nmae = "y"
  | ^^^^
  = help: did you mean `name`?
```

```toml
[dependencies]
internal/lib = { git = "https://github.com/org/lib.git", tga = "v1.0" }
```

```
error[UnknownDependencyField]: dependency entry has no field `tga`
 --> blink.toml:2:58
  |
2 | internal/lib = { git = "https://github.com/org/lib.git", tga = "v1.0" }
  |                                                          ^^^
  = help: did you mean `tag`?
  = note: an unknown field changes what is built, so it is never ignored
```

W1002 keeps a manifest that a newer toolchain wrote building on an older toolchain, when the new key is metadata (§8.9.7). A new entry field is added to this specification before any toolchain reads it, as `version` was (§8.9.7). An older toolchain stops on a field that it cannot honour.

Each unknown key gets its own diagnostic, in source order. The toolchain checks the whole manifest before the load fails on E1014. The section check comes first: a section that W1001 reports gets no key diagnostic, also when a dotted key at the top level opens that section.

**Edition value.** The `edition` value must name an edition that this toolchain knows (§8.16.1). There is no fallback edition: the toolchain never checks a package under an edition that its manifest does not name. A manifest with no `edition` keeps the default (§8.16.1). The check runs for each package in the dependency graph. The span is the value token. Two errors cover the faults:

| Value | Error | Help |
|-------|-------|------|
| A string of four digits that is a year after the newest edition this toolchain knows (`"2099"`) | `UnsupportedEdition` (E1017) | install a newer `blink`; `blink editions` lists the editions this one knows |
| Any other value: a string that is not a year, a year before the first edition, a year at or below the newest known edition that names no edition, or a value that is not a string | `InvalidEdition` (E1018) | the nearest known edition (ERROR_CATALOG.md, *Conventions*; the candidates are the known editions); `blink editions` lists them |

`UnsupportedEdition` means that the file may be correct and this toolchain is too old. The message names the version of this toolchain and the newest edition that it knows. The help never offers a lower edition, and the error has no machine-applicable fix: a lower edition checks the package under rules that its author did not choose.

`InvalidEdition` means that the file is wrong for every toolchain. A TOML integer that names a known edition (`edition = 2026`) has a machine-applicable fix that quotes it. No other case has a machine-applicable fix.

```toml
[package]
name = "x"
version = "0.1.0"
edition = "2099"
```

```
error[UnsupportedEdition]: this blink does not know edition "2099"
 --> blink.toml:4:11
  |
4 | edition = "2099"
  |           ^^^^^^ blink 0.57.0 knows editions up to 2026
  |
  = help: install a newer `blink`; `blink editions` lists the editions this one knows
```

```toml
[package]
name = "x"
version = "0.1.0"
edition = 2026
```

```
error[InvalidEdition]: `edition` must be a string
 --> blink.toml:4:11
  |
4 | edition = 2026
  |           ^^^^
  |
  = help: write the edition as a string: `"2026"`
```

Neither error is a warning. No `@allow` and no `[lints]` entry lowers it; such an entry is `NotAWarningName` (E0847), as for any error.

When the manifest at fault belongs to a dependency, the error gets the `note:` and the chain of *Dependency manifests* below. The help also offers to pin a release of the dependency that uses an edition this toolchain knows.

```
error[UnsupportedEdition]: this blink does not know edition "2099"
 --> ../vendor/crypto/blink.toml:4:11
  |
4 | edition = "2099"
  |           ^^^^^^ blink 0.57.0 knows editions up to 2026
  |
  = note: `acme/crypto` is a dependency of `acme/auth` (../vendor/auth/blink.toml:9:1); chain: acme/app -> acme/auth -> acme/crypto
  = help: install a newer `blink`, or pin a release of `acme/crypto` that uses an edition this blink knows
```

W1001 and unknown-key diagnostics in the same manifest are still reported. For `UnsupportedEdition` only, each such warning adds a `note:` at the `edition` value. The note states a fact and nothing more: `this manifest names edition 2099, which this blink does not know`. For `InvalidEdition`, the warning has no note.

`blink fmt` still formats a package with an edition error. The language server reports the error and does not type-check that package. `blink migrate --edition <year>` and `blink editions --edition <year>` give the same two errors for a year that names no known edition; the span is the argument (§8.16.3, §8.16.4).

**Reporting.** The toolchain checks the whole manifest and reports every manifest error before the load fails. After a manifest error the toolchain prints no further line about the failed load. The toolchain may print one line that gives the count of errors. That line is not a diagnostic: it does not start with `error:` and it names no fault.

**Dependency manifests.** This rule is for every manifest error. When the manifest at fault is a dependency's, the error adds a `note:` with a span on the dependency's entry in the dependent manifest. When the dependency is not direct, the note also gives the chain from the root on one line, for example `myapp -> auth -> crypto`. The chain is the shortest path. Among paths of equal length, it is the first in declaration order.

**Package keys.** `MissingManifestKey` and `InvalidPackageVersion` are errors of category Manifest. No `@allow` entry and no `[lints]` entry lowers them (`NotAWarningName`, E0847, as for any error).

- `MissingManifestKey` (E1019): the manifest has no `[package]` section, or `[package]` lacks `name` or `version`. With no `[package]` section, the toolchain reports one diagnostic, at line 1, column 1. When `[package]` lacks both keys, it reports one diagnostic for each key, each at the `[package]` header. This code covers only these absent keys. An empty value is not this code.
- An empty `name`, or a `name` that is not a string, is `InvalidPackageName` (E1011, §10.1). The span is the value. The message for the empty case says that the package name is empty.
- `InvalidPackageVersion` (E1020): `version` is empty, is not a string, or is not a SemVer 2.0.0 version. The span is the value. The help says that `"1.2"` is a dependency constraint (§8.9.4) and not a package version. For `"1"` and `"1.2"`, the help gives the padded version (`"1.0.0"`, `"1.2.0"`). That edit is not machine-applicable, because the author can mean another version.
- When an unknown-key diagnostic fired in `[package]`, and that unknown key is the nearest-name match (ERROR_CATALOG.md, *Conventions*) for the missing key, `MissingManifestKey` adds a `note:` at the unknown key. Its help then says to rename the key (``rename `nmae` to `name` ``). An unknown key that is not the nearest-name match, such as `homepage`, gets no note. If the renamed key has a bad value, the next run reports `InvalidPackageName` or `InvalidPackageVersion`.

```toml
[package]
version = "0.1.0"
```

```
error[MissingManifestKey]: `[package]` has no `name`
 --> blink.toml:1:1
  |
1 | [package]
  | ^^^^^^^^^ `name` is required
  = help: add `name = "myapp"` under `[package]`
```

```toml
[package]
name = "myapp"
version = "1.2"
```

```
error[InvalidPackageVersion]: `"1.2"` is not a SemVer 2.0.0 version
 --> blink.toml:3:11
  |
3 | version = "1.2"
  |           ^^^^^ expected MAJOR.MINOR.PATCH
  = help: `"1.2"` is a dependency constraint (§8.9.4), not a package version; write `"1.2.0"`
```

**Dependency sources.** An entry takes exactly one source (§8.9.3). Both codes below are errors of category Manifest, and no `@allow` or `[lints]` entry lowers them. A later source kind uses these two codes. There is no third code for a wrong source.

- `MissingDependencySource` (E1021): the entry has no source. The message says that the dependency "has no source". The help lists the sources that this toolchain supports; a v1 toolchain lists `path` and `git` (§8.9.7). Some keys belong to some sources only. Today the only such key is `tag`, and only `git` takes it. When the entry holds such a key, the help names every source that takes the key (today `git` alone). The toolchain checks the whole entry before it reports this error. When an unknown-field diagnostic fired in the same entry, and that field is the nearest-name match for a source key, this error adds a `note:` at that field. The candidates are source keys only. The two errors have one repair: rename the field. The help says so.
- `ConflictingDependencySources` (E1022): the entry has two or more sources. The primary span is the second source key in source order. Each other source key has a label in the same snippet, and the number of labels has no limit. The help says that an entry takes exactly one source and asks the user to keep one. It never picks which source to keep, and the error has no machine-applicable fix.

```toml
[dependencies]
"local/utils" = { path = "../utils", git = "https://example.com/utils.git" }
```

```
error[ConflictingDependencySources]: dependency `local/utils` has two sources
 --> blink.toml:2:38
  |
2 | "local/utils" = { path = "../utils", git = "https://example.com/utils.git" }
  |                   ----               ^^^ second source
  |                   |
  |                   first source
  = help: a dependency takes exactly one source; keep one of `path` and `git`
```

```toml
[dependencies]
"local/utils" = { pth = "../utils" }
```

```
error[MissingDependencySource]: dependency `local/utils` has no source
 --> blink.toml:2:1
  |
2 | "local/utils" = { pth = "../utils" }
  | ^^^^^^^^^^^^^ needs one source
  = note: blink.toml:2:19: the unknown field `pth` may be the misspelled `path`
  = help: rename `pth` to `path`
```

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

The output is NDJSON: one complete JSON object per line. Each line has a `record` key that names its kind:

| `record` | Written | Carries |
|----------|---------|---------|
| `"test"` | when a test ends | `file`, and the test record described below |
| `"file"` | when a test file ends, or when it does not build | `file`, `outcome`, `summary`, and the fields of its outcome (§8.10.5) |
| `"run"` | last, once | `summary` for all tests, and `files` (§8.10.5) |

```json
{"record": "test", "file": "tests/test_auth.bl", "name": "login succeeds with valid credentials", "status": "passed", "duration_ms": 12}
{"record": "test", "file": "tests/test_db.bl", "name": "connect and query", "status": "failed", "cause": "propagated_error", "error": {"message": "connection refused: 127.0.0.1:5432", "error_type": "pg.ConnectError"}, "span": {"file": "tests/test_db.bl", "line": 12, "col": 21}}
{"record": "test", "file": "tests/test_auth.bl", "name": "login rejects after rate limit", "status": "failed", "cause": "assertion", "assertion": "assert_eq(result, Err(RateLimit))", "expected": "Err(RateLimit)", "actual": "Ok(AuthSuccess { ... })", "introspection": [], "omitted": [], "span": {"file": "src/auth.bl", "line": 58, "col": 5}}
{"record": "test", "file": "tests/test_auth.bl", "name": "session token decodes", "status": "panicked", "message": "unwrap called on None", "span": {"file": "src/auth.bl", "line": 91, "col": 17}}
{"record": "file", "file": "tests/test_db.bl", "outcome": "ran", "summary": {"total": 1, "passed": 0, "failed": 1, "panicked": 0, "skipped": 0, "duration_ms": 31}}
{"record": "file", "file": "tests/test_auth.bl", "outcome": "ran", "summary": {"total": 3, "passed": 1, "failed": 1, "panicked": 1, "skipped": 0, "duration_ms": 340}}
{"record": "run", "summary": {"total": 4, "passed": 1, "failed": 2, "panicked": 1, "skipped": 0, "duration_ms": 352}, "files": {"total": 2, "ran": 2, "build_failed": 0, "aborted": 0}}
```

The AI reads structured test failures the same way it reads structured compiler errors — exact location, expected vs actual values, no string parsing.

**Stream rules.**

- A `test` line is final when it is written. No later line changes or removes it.
- Test files run in parallel, so lines from different files interleave. The lines of one file keep their order, and that file's `file` line comes after all of its `test` lines. A consumer groups `test` lines by `file`, not by position.
- A consumer ignores a line whose `record` value it does not know. This rule applies to `record` only. `status`, `cause` and `outcome` are closed enums.
- `blink test` on one file writes the same lines as on a directory.

**Failure `cause` discriminator.** Records with `"status": "failed"` carry a `cause` field whose value is one of a closed enum:

| `cause` value | Meaning |
|--------------|---------|
| `"assertion"` | An `assert*` built-in failed. The record carries `assertion`, `expected`/`actual`, `introspection` and `omitted` fields (§2.20 Assertion Failure Output, *Sub-expression Values*). On the record for a failed `assert*` call, `introspection` and `omitted` are always present, `[]` when empty. |
| `"propagated_error"` | The test body — **or a `prop_check` property closure** (§2.20 Error Propagation, Property-Based Testing) — returned `Err(TestError { ... })` via `?` propagation. The record carries an `error` object with `message` (the `Display`-rendered error string) and `error_type` (the static name of the source error type at the `?` site). When the failure comes from a property closure, the record *additionally* carries the property failure fields (`seed`, `shrunk_input`, `reproduce`); the `cause` axis (assertion vs propagated error) is orthogonal to whether the test is a property, so no new `cause` value is added. |

`"status": "panicked"` and `"status": "skipped"` records have no `cause` field — the status itself identifies the path. The four top-level statuses (`passed | failed | panicked | skipped`) remain unchanged.

**Panicked records.** A panic that escapes a test body — one that no `assert_panics` catches (§2.20) — gives the test `"status": "panicked"`. The runner records the panic and continues with the next test. `"failed"` means the test found a bug; `"panicked"` means the test itself is broken (§2.20). A `panicked` record carries:

| Field | Meaning |
|-------|---------|
| `message` | The panic message, unchanged. |
| `span` | Where the panic fired, in the same shape as the `span` of a `failed` record. Present only when the runtime knows the location. |

A `panicked` record has no `cause`, no `error` object and no `assertion` fields. It never carries a placeholder location such as `line: 0`: when the location is not known, `span` is absent.

`message` and `span` have one meaning on every status that carries them: `message` is the text of the outcome, and `span` is where the outcome fired.

**Summary and exit code.** The `summary` object on every `file` line and on the `run` line always carries all six keys — `total`, `passed`, `failed`, `panicked`, `skipped`, `duration_ms` — even when a count is `0`. The counts partition the `test` lines it covers:

```
total = passed + failed + panicked + skipped
```

A test counts once, under the status of its record. A `file` summary covers the `test` lines of that file; the `run` summary covers all `test` lines. The test binary exits non-zero when `failed + panicked > 0`. An unexpected pass counts as `failed` (§8.10.6). A panic has no exit code of its own. `blink test` exits `1` when `failed + panicked + files.build_failed + files.aborted > 0`, and `0` otherwise (§8.10.5).

**Human-readable output.** The per-test line for a panicked test uses the word `PANIC`, and the panic message follows it:

```
test session token decodes ... PANIC
  unwrap called on None
  at src/auth.bl:91:17
```

The summary line always shows `passed` and `failed`. It shows `panicked` and `skipped` only when their count is above `0`:

```
11 passed, 2 failed, 1 panicked (of 14)
```

**Cleanup warnings.** A record of any status can carry a `cleanup_warnings` array. Each entry is `{"code": "E0824", "message": <cleanup panic message>}`. When a cleanup (`exit(false)` or `close()`) panics during a catchable unwind, the runner adds an entry and does not change the status (§4.7.2, E0824; cleanup in §5.5). The test keeps one record. This includes a panic in cleanup while an armed `assert_panics` unwinds: the expected panic sets the status (`passed`, or `failed` under E0832), and the cleanup panic is an E0824 entry on that record, not a separate `panicked` record:

```json
{"name": "rejects bad header", "status": "passed", "duration_ms": 2,
 "cleanup_warnings": [{"code": "E0824", "message": "close on released handle"}]}
```

The human output prints one line per entry under the test's result line, for every status, passing tests included:

```
test rejects bad header ... ok
  warning: E0824 cleanup panicked during unwind: close on released handle
```

A signal crash (for example `SIGSEGV`) is not a Blink panic and gives no `test` line. It ends the test binary, and the `file` line reports it with `outcome: "aborted"` (§8.10.5).

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
    let order = db.read(t"SELECT * FROM orders WHERE id = {id}")?
    let receipt = Receipt { order_id: id, total: order.total }
    db.write(t"INSERT INTO receipts ...", receipt)?
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
    assert(log_messages.get(0).unwrap().contains("Processing order 42"))
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
assert(msgs.get(0).unwrap().contains("started"))

// Compose with other handlers
with mock_db(data), capture_log(msgs) {
    do_work()
}
```

**No special assertion helpers.** Use the existing `assert`, `assert_eq`, and `assert_ne` built-ins with standard `List[Str]` methods:

```blink
assert_eq(msgs.len(), 3)                          // exact count
assert(msgs.get(0).unwrap().contains("order 42"))              // substring match
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

**Standard input: `stdin_from`.** `std.testing` also gives a handler that supplies standard input:

```blink
pub fn stdin_from(text: Str) -> Handler[IO.Read]
```

The handler reads the UTF-8 bytes of `text` as the input stream, from the start, and then gives end of input. It keeps the `IO.Read` handler contract (§4.4.9): `read_bytes(n)` returns exactly `n` bytes until fewer are left, and `read_line` and `read_all` give the same results as their derived bodies over those bytes. Each call to `stdin_from` makes a new stream.

```blink
import std.testing.{stdin_from}

fn sum_lines() -> Int ! IO.Read {
    let mut sum = 0
    loop {
        match io.read_line() {
            Some(line) => sum = sum + (line.parse_int().ok() ?? 0)
            None => break
        }
    }
    sum
}

test "sum_lines adds each line" {
    with stdin_from("1\n2\n\n3") {
        assert_eq(sum_lines(), 6)
    }
}
```

**Standard input of a test.** `blink test` gives each test process the null device as its standard input. A test that reads with no `IO.Read` handler sees end of input at the first read: `io.read_line()` gives `None`, `io.read_all()` gives `""` and `io.read_bytes(n)` gives empty `Bytes`. A test never waits for input from the terminal that started the runner.

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

**`assert_panics` — asserting expected panics.** Capturing a `panic` from within a test *is* supported, as a compiler-recognized block (§2.20), not as a general recoverable-panic primitive:

```blink
test "unwrap on empty list panics" {
    assert_panics(matching: "unwrap called on None") {
        let xs: List[Int] = []
        let _ = xs.get(0).unwrap()
    }
}
```

The body is a `{ ... }` block (not a closure), the optional `matching:` argument is a literal **substring** test on the panic message, and the construct is test-only and valueless. On failure the runner renders structured output: a body that returns without panicking is **E0831** (`expected the block to panic, but it returned normally`); a panic whose message lacks the `matching:` substring is **E0832**, which prints the expected substring, the **full actual panic message**, and the source location where the panic fired. A passing `assert_panics` consumes the panic — the test status is `"passed"`, not `"panicked"`. In-scope `with`/`Closeable` resources opened inside the block are released on the expected panic (§4.7.2, *armed* catchable unwind). See §2.20 for the full semantics, the test-only (E0833) and no-nesting (E0834) rules, and the R3-fence amendment.

For testing that a *separate binary* exits via panic, continue to isolate the call in a subprocess via `process_run` and inspect `exit_code`/`err_out`; `assert_panics` is for in-process expressions within the test itself.

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

**Failure attribution.** The test record carries a `cases` array with one entry for each case that ran. An entry holds the case `label` and its `status`, a value from the closed status enum (`passed | failed | panicked | skipped`). A `panicked` entry also carries `message` and, when known, `span` (§8.10, *Panicked records*).

A case that fails or panics does not stop the loop. The runner records the case and runs the next one, so every case runs on every invocation.

The parent test's status is the most severe status among its cases, in the order `panicked > failed > passed`. The parent is `skipped` only when every case is skipped. A duplicate-label panic is a panic: that case records `panicked`.

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

#### 8.10.3 Effect mocks: `mock_clock` and `mock_env`

Beyond the stateless IO capture handlers (§8.10.1), `std.testing` ships controller-style mocks for the two effects whose default-handler behavior is hostile to tests: `Time` (the real clock is nondeterministic) and `Env` (the real `env.exit` terminates the test runner).

```blink
import std.testing.{mock_clock, mock_env}
```

`mock_clock` and `mock_env` return **controller structs**, not bare handlers. Each controller gives `.as_handler()` (to plug into `with`) and methods that read or change the mock's state. This shape is deliberately different from `capture_log` — see the *Two shapes, one rule* note below.

Import only the factory. The controller's methods come from a trait impl in the controller type's own package, so they go with the value (§3.6 *Impl visibility*). An import of `MockClock` or `MockEnv` adds nothing, and W0602 flags it (§10.5 *Unused Imports*).

##### `mock_clock` — deterministic `Time` handler

```blink
pub type MockClock {
    time_handler: Handler[Time]
    advance_fn: fn(Duration) -> Void
    elapsed_fn: fn() -> List[Duration]
}

pub trait MockClockOps {
    fn as_handler(self) -> Handler[Time]
    fn advance(self, d: Duration)
    fn elapsed(self) -> List[Duration]
}

impl MockClockOps for MockClock {
    fn as_handler(self) -> Handler[Time] { self.time_handler }
    fn advance(self, d: Duration) { (self.advance_fn)(d) }
    fn elapsed(self) -> List[Duration] { (self.elapsed_fn)() }
}

pub fn mock_clock(start: Instant) -> MockClock {
    let mut now = start
    let mut slept: List[Duration] = []
    MockClock {
        time_handler: handler Time {
            fn read() -> Instant { now }
            fn monotonic() -> Monotonic { Monotonic.from_offset(now.since(start)) }
            fn sleep(d: Duration) { slept.push(d) }
        },
        advance_fn: fn(d: Duration) {
            if d.to_nanos() < 0 {
                panic("mock_clock.advance: duration must not be negative, got {d}")
            }
            now = now.add(d)
        },
        elapsed_fn: fn() -> List[Duration] { [..slept] },
    }
}
```

The mock's state lives in the factory's `let mut` bindings `now` and `slept`. The monotonic reading comes from `now`, so the two clocks cannot drift apart. The handler and the two closures capture the same bindings, so they share one cell each (§2.8, §4.7). The struct fields are never assigned. A copy of a `MockClock` holds the same handler and closures, so it drives the same clock (§3.6). This is the pattern for every stateful mock in `std.testing`: state in captured `let mut` bindings, methods through a single-type `*Ops` trait.

Construct the controller with a starting instant, plug `.as_handler()` into a `with` block, and (optionally) `.advance(d)` the clock between calls to the code under test to drive time-based control flow:

```blink
import std.testing.{mock_clock}

test "retry backoff sleeps with increasing delay" {
    let mc = mock_clock(Instant.from_epoch_secs(0))
    with mc.as_handler() {
        retry_with_backoff(fn() { Err("transient") })
    }
    assert_eq(mc.elapsed().len(), 3)
    assert_eq(mc.elapsed().get(0).unwrap(), Duration.ms(100))
    assert_eq(mc.elapsed().get(1).unwrap(), Duration.ms(200))
    assert_eq(mc.elapsed().get(2).unwrap(), Duration.ms(400))
}

test "timeout fires after configured interval" {
    let mc = mock_clock(Instant.from_epoch_secs(0))
    with mc.as_handler() {
        let token = start_token(Duration.seconds(30))
        mc.advance(Duration.seconds(29))
        assert(!token.expired())
        mc.advance(Duration.seconds(2))
        assert(token.expired())
    }
}
```

**`time.read()`** returns the current mock instant. **`time.monotonic()`** returns the mock reading: the offset of the mock instant from `start`, so it is zero at `start`. **`time.sleep(d)`** records `d` and does not block. **`.advance(d)`** moves the mock instant and the mock monotonic reading forward by `d` — used by tests that need to drive a timeout, retry loop, or rate-limiter past a threshold without consuming wall-clock time. It panics when `d` is negative, and the message contains the value: `mock_clock.advance: duration must not be negative, got -1s`. **`.elapsed()`** returns the recorded `List[Duration]` of `time.sleep` calls; tests assert on the sequence of sleeps the code under test issued. `.elapsed()` returns a copy: later handler activity does not change it. Call it again to see later sleeps, and call it once after the run, not in a loop, because each call copies the list.

Every `std.testing` mock of a `@handle_all` effect implements every primitive operation of the effect, because a test has no outer handler to forward to. An operation that finds no handler panics at run time (§2.20 *Test blocks*, §4.7.1). A later operation that moves the mock wall clock backward, or jumps it, must keep a separate monotonic reading, because `monotonic` here comes from `now`.

##### `mock_env` — capturing `Env` handler that does not terminate the runner

```blink
pub type MockEnv {
    env_handler: Handler[Env]
    set_fn: fn(Str, Str) -> Void
    writes_fn: fn() -> List[(Str, Str)]
}

pub trait MockEnvOps {
    fn as_handler(self) -> Handler[Env]
    fn set(self, name: Str, value: Str)
    fn writes(self) -> List[(Str, Str)]
}

impl MockEnvOps for MockEnv {
    fn as_handler(self) -> Handler[Env] { self.env_handler }
    fn set(self, name: Str, value: Str) { (self.set_fn)(name, value) }
    fn writes(self) -> List[(Str, Str)] { (self.writes_fn)() }
}

pub fn mock_env(initial: Map[Str, Str]) -> MockEnv
```

`mock_env` follows the `mock_clock` pattern: the environment lives in a `let mut vars` binding and the recorded writes in a `let mut writes` binding, both captured by the handler and the closures.

Construct with the initial environment, plug `.as_handler()` into a `with` block, optionally call `.set(name, value)` to mutate the environment between CUT calls, and inspect `.writes()` afterward to see what the CUT wrote:

```blink
import std.testing.{mock_env}

test "loader reads DATABASE_URL with fallback" {
    let me = mock_env(Map.from([("DATABASE_URL", "postgres://test")]))
    with me.as_handler() {
        let cfg = load_config()
        assert_eq(cfg.db_url, "postgres://test")
    }
}

test "CLI exits 1 on missing argument" {
    let me = mock_env(Map.new())
    assert_panics(matching: "env.exit(1)") {
        with me.as_handler() {
            run_cli([])
        }
    }
}

test "setup writes log path before reload" {
    let me = mock_env(Map.from([("LOG_PATH", "/var/log/old")]))
    with me.as_handler() {
        configure()
        me.set("LOG_PATH", "/var/log/new")
        reload()
    }
    assert_eq(me.writes().len(), 0)  // no env.set_var by CUT itself
}
```

**Important: `mock_env`'s `Env.exit(code)` op panics with the captured code rather than terminating the process.** The real `env.exit` is non-resumable (returns `Never`) — if a test's CUT calls `env.exit(1)` and the handler auto-delegates, the test runner dies. `mock_env` papers over this in one place so every test author does not write the same five-line `let mut exit_code = -1; handler Env { ... fn exit(...) { exit_code = code; panic(...) } }` shim (§4.4.3). The panic message contains `env.exit(`, then the code in decimal with no padding, then `)`: `env.exit(1)` for code `1`, `env.exit(-2)` for code `-2`. This text is stable; the rest of the message is not specified. Because the text includes the closing `)`, `matching: "env.exit(1)"` does not match code `10`. Tests that want to *observe* an exit run the CUT inside `assert_panics(matching: "env.exit(<code>)") { with me.as_handler() { ... } }` (§2.20).

**`env.var(name)`** reads from `vars`. **`env.vars()`** returns a copy of `vars`. **`env.set_var(name, value)`** updates `vars` *and* appends `(name, value)` to `writes` — this lets tests distinguish setup-driven environment state from environment writes performed by the CUT. `.set(name, value)` is the test-author-facing mutation that does **not** record into `.writes`; it is for staging environment changes between calls to the CUT. `.writes()` returns a copy: later handler activity does not change it.

**`mock_env` changes what Blink code reads through `Env`.** A real child that `process.run` starts still inherits the real environment. To control the environment of a child in a test, pass `env:` to the op (§4.4.8) or mock `Process`.

**`mock_env` does not currently mock `env.args()` or `env.cwd()`.** Tests that need `args` or `cwd` should either pass them in as function arguments to the CUT (preferred) or fork the controller after `mock_env`'s implementation lands — a `mock_env(initial, args: List[Str], cwd: Str)` overload is a likely follow-up if the usage signal emerges.

##### Why controller structs, not free-fn factories — two shapes, one rule

`capture_log` is a free-fn factory: `fn capture_log(messages: List[Str]) -> Handler[IO.Log]`. `mock_clock` and `mock_env` are controller structs returned by `mock_clock(start)` / `mock_env(initial)`. **The shapes diverge deliberately:**

- **Free-fn factory for stateless sinks.** `IO.Log`, `IO.Print`, `IO.Eprint` are write-only — the test passes in a `List[Str]`, the handler appends, the test asserts on the list. There is no state to inspect beyond the captured list. The free-fn factory shape is the minimum surface that does the job.
- **Controller struct for stateful mocks.** `Time` and `Env` have mock state that the test wants to read *and* manipulate: `mock_clock` needs `.advance(d)` to drive timeouts past thresholds; `mock_env` needs `.set(name, value)` for mid-test mutation and `.writes()` for CUT-write observation. A free-fn factory such as `frozen_clock(i: Instant) -> Handler[Time]` cannot hold this state safely: nested `with` blocks would share it, and the inner mock would change the time the outer mock reports. Each factory call makes new `let mut` bindings, and the controller's handler and closures capture them (§2.8, §4.7), so nested mocks stay isolated. The state does not live in the controller's fields: `self` is a by-value copy, and a write through it does not reach the caller (§3.6).

**Rule for AI generation and for adding future mocks:**

> Use a free-fn factory when the mocked effect's user-facing state is exactly the captured list. Use a controller struct when the test needs to *manipulate* mock state (advance the clock, set a variable mid-test) or *observe* mock-driven state (read recorded writes) beyond the simple captured-list shape.

This rule applies forward to `MockFs`, `MockNet`, `MockRand` and any future effect mocks: controllers when the test interacts with the mock during the `with` block; free-fn factories when the test only assembles the list afterward. A controller keeps its state in `let mut` bindings its factory's handler and closures capture, and attaches its methods through a single-type `*Ops` trait, as `MockClock` does.

##### Composing with `capture_log`

The mocks compose with each other and with the IO capture handlers via the standard `with a, b, c` handler chain:

```blink
import std.testing.{mock_clock, mock_env, capture_log}

test "scheduled job logs progress with mocked clock and env" {
    let mc = mock_clock(Instant.from_epoch_secs(1735689600))
    let me = mock_env(Map.from([("BATCH_SIZE", "100")]))
    let logs: List[Str] = []
    with mc.as_handler(), me.as_handler(), capture_log(logs) {
        run_scheduled_job()
        mc.advance(Duration.hours(1))
        run_scheduled_job()
    }
    assert_eq(logs.len(), 2)
    assert(logs.get(0).unwrap().contains("batch_size=100"))
}
```

Each handler intercepts only its own effect; auto-delegation forwards the rest. The handler ordering follows the nesting rule from §4.7: items nest from left to right, so the rightmost item is the innermost, and it takes precedence for any effect operation either could service.

##### `record_calls[E]` — rejected outright

A polymorphic `record_calls[E]() -> (Handler[E], List[OpCall[E]])` was considered and rejected unanimously (6-0). Constraint #9 in `DECISIONS.md` (no effect-kinded generics in v1) makes the polymorphic version literally inexpressible — `Handler[E]` is not a value-kinded generic parameter. Per-effect surrogates (`record_log_calls`, `record_env_calls`, ...) would fragment the API and the inline pattern is shorter than the stdlib call site would be:

```blink
test "logger calls audit hook on warn-or-higher" {
    let mut calls: List[Str] = []
    with handler IO.Log {
        fn log(msg: Str) { calls.push(msg) }
    } {
        warn_about(thing)
    }
    assert_eq(calls.len(), 1)
}
```

Use the inline `handler E { fn op(...) { calls.push(...) } }` pattern at the test site when you need ad-hoc op recording for an effect the stdlib does not (yet) ship a mock for. The pattern is shorter than the corresponding `record_calls` import-and-destructure would be.

**Panel vote: 5-1** for shipping both `mock_clock` and `mock_env` (Round 2; Round 1 was 4-1-1 — minimalism conceded A2→A3 with the `Env.exit` footgun argument). **5-1** for central `std.testing` placement (sys dissent on binary-size compounding). **5-1 R2** for controller-struct shape on `mock_clock` (Round 2 after aiml's nesting concession; min dissent). **4-2 R2** for controller-struct shape on `mock_env` (Round 2 after web's procedural D2 disambiguation and aiml's internal-consistency concession; devops and min held D1). **6-0** rejecting `record_calls[E]`. See [DECISIONS.md](../DECISIONS.md) and [decisions/mocking-helpers-beyond-io.md](../decisions/mocking-helpers-beyond-io.md). A later panel made the controllers expressible: state in captured `let mut` bindings, methods through `*Ops` traits, `.handler()` renamed `.as_handler()` (**6-0**), accessors return a copy (**5-1**). See [decisions/mock-controller-expressibility.md](../decisions/mock-controller-expressibility.md).

#### 8.10.4 Deterministic randomness: `--seed` and `mock_rand`

Tests that call `rand.int`/`rand.float`/`rand.bytes` (the `Rand` effect, §4.4.7), and `prop_check` blocks that generate random inputs, are nondeterministic by default. A failure in CI cannot be reproduced locally without the inputs that triggered it. `std.testing` and the test runner together close this gap with two coupled mechanisms: a runner-level `--seed` flag for reproducing whole runs, and an in-test `mock_rand` controller for asserting on deterministic streams.

##### Runner flag: `blink test --seed <u64>`

```sh
blink test --seed 0xDEADBEEFCAFE1234   # fixed seed
blink test                              # entropy-seeded; seed printed on failure
```

The `--seed` flag accepts either a `0x`-prefixed hex literal or a decimal integer. Without `--seed`, the runner picks a fresh seed from OS entropy at the start of each invocation. In both cases the seed is the **suite seed** — it is the root from which every property test's input stream and every effect-handler installation derives a deterministic sub-seed.

**Per-property sub-seed derivation.** Inside a test that uses `prop_check`, the runner does not pass the suite seed directly to the property's RNG. Instead it derives a stable per-property sub-seed. The sub-seed is a deterministic function of the suite seed and the bare property name. The name has no module prefix, so that moving a test between modules does not invalidate a reproducer. Within a binary, two `prop_check` blocks with the same `test "<name>"` are rejected by the runner — the runner emits a diagnostic listing both locations and exits with non-zero status, because this derivation would otherwise have them silently share a stream.

**Runner `Rand` handler.** The runner installs a seeded `Rand` handler around the body of each `test` block. This handler is the outermost one, so every `with` in the test body nests inside it. Its seed is a deterministic function of the suite seed and the bare test name, derived the same way as a property sub-seed. A `rand.*` call in a test therefore never reaches the OS random source. When no handler of the test answers the call, the runner's stream answers it, and `--seed <suite> --filter '<name>'` replays that stream. A `prop_check` block keeps its own per-property stream for its inputs.

Reordering tests, filtering with `--filter`, or running shards in parallel does **not** perturb any test's sub-seed — every test is reproducible in isolation given `--seed <suite> --filter '<name>'`.

##### Failure output (the reproduce line)

Every test failure includes the suite seed and a copy-pasteable rerun command, in both human-readable and JSON output. This is the load-bearing UX property of the design: a flaky CI failure becomes a one-line local reproducer.

Human-readable form:

```
FAIL  tests/test_parser.bl::"reverse is involutive"
  seed: 0xDEADBEEFCAFE1234
  shrunk input: [1, 2, 2, -9]
  rerun: blink test --seed 0xDEADBEEFCAFE1234 --filter 'reverse is involutive'
```

NDJSON form (`blink test --json`):

```json
{"record": "test",
 "file": "tests/test_parser.bl",
 "name": "reverse is involutive",
 "status": "failed",
 "cause": "assertion",
 "seed": "0xDEADBEEFCAFE1234",
 "shrunk_input": "[1, 2, 2, -9]",
 "reproduce": "blink test --seed 0xDEADBEEFCAFE1234 --filter 'reverse is involutive'",
 "introspection": [],
 "omitted": [],
 "span": {"file": "tests/test_parser.bl", "line": 42, "col": 3}}
```

When a property fails because a `?` inside the property closure propagated an `Err` (rather than an assertion failing), the `test` line carries `cause: "propagated_error"` and the `error` object — the property fields and the propagated-error fields co-exist in one record:

```json
{"record": "test",
 "file": "tests/test_net.bl",
 "name": "port strings round-trip",
 "status": "failed",
 "cause": "propagated_error",
 "error": {"message": "invalid port: 70000", "error_type": "net.ParseError"},
 "seed": "0xDEADBEEFCAFE1234",
 "shrunk_input": "70000",
 "reproduce": "blink test --seed 0xDEADBEEFCAFE1234 --filter 'port strings round-trip'",
 "span": {"file": "tests/test_net.bl", "line": 18, "col": 21}}
```

The human-readable form mirrors an assertion failure, with the rendered error directly beneath the shrunk input:

```
FAIL  tests/test_net.bl::"port strings round-trip"
  seed: 0xDEADBEEFCAFE1234
  shrunk input: 70000
  propagated error: invalid port: 70000
    error type: net.ParseError
  rerun: blink test --seed 0xDEADBEEFCAFE1234 --filter 'port strings round-trip'
```

The seed surfaces in **every** failure output mode — `--quiet`, `--json`, and color-stripped CI logs all include it. The reproduce line uses the suite seed as printed: `0x` + 16 hex digits, zero-padded.

**A panic inside a property.** When a property closure panics, the test record has `"status": "panicked"` (§8.10, *Panicked records*). In this version the runner does not shrink the input after a panic. The record carries `seed`, `reproduce` and `input` — the input the trial ran with, not shrunk — in place of `shrunk_input`. The record never carries `shrunk_input` for a panic, because nothing was shrunk.

```
PANIC  tests/test_parser.bl::"parse never panics"
  seed: 0xDEADBEEFCAFE1234
  input: "{["
  panic: index out of bounds: 3 >= 2
  rerun: blink test --seed 0xDEADBEEFCAFE1234 --filter 'parse never panics'
```

##### In-test seeded RNG: `MockRand` controller

For tests that want to install a deterministic `Rand` handler in a `with` block (independent of the runner's suite seed), `std.testing` exposes a controller struct following the `mock_clock` / `mock_env` shape (§8.10.3):

```blink
pub type MockRand {
    rand_handler: Handler[Rand]
    draws_fn: fn() -> Int
    reseed_fn: fn(U64) -> Void
}

pub trait MockRandOps {
    fn as_handler(self) -> Handler[Rand]
    fn draws(self) -> Int
    fn reseed(self, seed: U64)
}

impl MockRandOps for MockRand {
    fn as_handler(self) -> Handler[Rand] { self.rand_handler }
    fn draws(self) -> Int { (self.draws_fn)() }
    fn reseed(self, seed: U64) { (self.reseed_fn)(seed) }
}

pub fn mock_rand(seed: U64) -> MockRand
```

The PRNG state lives in a `let mut state` binding and the draw counter in a `let mut draw_count` binding inside `mock_rand`, both captured by the handler and the closures.

Usage:

```blink
import std.testing.{mock_rand, MockRand}
import std.random.{shuffle}

test "shuffle preserves length" {
    let r = mock_rand(0x1234)
    with r.as_handler() {
        let ys = shuffle([1, 2, 3, 4, 5])
        assert_eq(ys.len(), 5)
    }
    assert_eq(r.draws(), 4)
}
```

**`.as_handler()` semantics.** `.as_handler()` returns the `Handler[Rand]` that `mock_rand` built. Each `rand.int`/`rand.float`/`rand.bytes` call through it advances the captured `state`. The method is **idempotent**: calling `r.as_handler()` twice on the same `MockRand`, or on a copy of it, returns the same handler value over the same captured state, not two independent streams. A second `with r.as_handler() { ... }` block continues the stream where the first one left off. For an independent stream from the same seed, construct a second `MockRand`.

**`.draws()` semantics.** Returns the number of `rand.*` operations that have been served by this handler since construction or the last `reseed`. **One op call = one draw**, regardless of how many bytes or how many random values the op produces internally (`rand.bytes(64)` counts as one draw). Each `rand.*` wrapper makes exactly one op call (§4.4.7), so `shuffle` on five elements is four draws. The `.draws()` counter is intended as a coarse audit hook — "did this code path reach the RNG?" — and is explicitly **not stable across compiler versions**: a future PRNG-algorithm change or runtime optimization may change how individual ops decompose. Do not commit regression tests that assert exact draw counts as part of the property under test; use it for shape-of-behavior checks only.

**`.reseed(seed)`.** Resets `state` to the given seed and zeroes `draw_count`. Useful for sub-loops in a single test that want fresh streams without constructing a new `MockRand`.

**Why a controller struct, not a free-fn handler factory.** Stateful mocks ship as controller structs in `std.testing` (the mocking-helpers rule, see [decisions/mocking-helpers-beyond-io.md](../decisions/mocking-helpers-beyond-io.md)) — uniform shape across `mock_clock`, `mock_env`, `mock_rand`. A free-fn `mock_rand(seed) -> Handler[Rand]` would lose the `.draws()` audit hook and break the family pattern for one effect. Authors who only want determinism and do not need draw-count introspection write `with mock_rand(seed).as_handler() { ... }` as a single line and discard the controller.

**Why not `seeded_rng`.** The name `mock_rand` parallels `mock_clock` and `mock_env`; a parallel `seeded_rng` free-fn would split the surface across two names for one primitive without removing anything. The mocking-helpers rule already established "one controller per mocked effect" as the consistency invariant — `seeded_rng` is rejected on those grounds.

##### PRNG algorithm

`MockRand` and the runner's per-property RNG are **implementation-defined, deterministic given seed**. The spec names no algorithm. The `Rand` resolution (§4.4.7) names none for the default handler either, and the stdlib has no production seeded handler. If one is added later, it must name its algorithm and keep its stream stable across versions; this testing surface does not change. The reproduce-by-seed contract holds for any single compiler version; the spec does not guarantee bit-identical reproduction across major versions.

##### The `Rand` effect surface

The `Rand` resolution (§4.4.7, [decisions/random-stdlib-module.md](../decisions/random-stdlib-module.md)) confirms the assumption this design rests on. `Rand` has exactly the ops `int` / `float` / `bytes` and no seed, reseed or fork op. Seeding is a handler-installation concern: `mock_rand(seed).as_handler()` and `--seed`-derived runner handlers both install a deterministic interpretation. A `MockRand` handler implements the three ops and nothing else. A handler for `Rand` that omits an op gets the warning `PartialHandler` (§4.7.1): the omitted op reads the runner's stream, not the mock's seed.

##### Out of scope

The following are intentionally out of scope for this subsection and are tracked separately:

- **Persisted counterexamples** (proptest-regressions-style files). A complementary mechanism to `--seed` for shrinking-stable failure replay across compiler versions.
- **`--rerun-failed`**. Re-reads the previous run's NDJSON and replays only the failing tests at their recorded sub-seeds. Distinct from `--seed`.

**Panel vote: 6-0** for the `MockRand` controller struct shape, `mock_rand` naming, resolving now (not deferring on `Rand` effect finalization), and the per-property sub-seed derivation. **5-1** for shipping `--seed` (Minimalism dissent: pure-addition without removal, prefers persisted counterexamples as the reproducibility primitive). See [DECISIONS.md](../DECISIONS.md) and [decisions/test-seed-determinism.md](../decisions/test-seed-determinism.md).

---

#### 8.10.5 File outcomes: files that do not build or do not finish

A test file that does not build is not a test. `blink test` reports it as a build failure for that file and runs the other files. A file that does not build never stops the run: each such file gets its own diagnostics.

The runner has no store, flag or event class for files that do not build.

Every test file gives exactly one `file` line (§8.10). Its `outcome` is one value of a closed enum:

| `outcome` | Meaning | Fields for this outcome |
|-----------|---------|-------------------------|
| `"ran"` | The test binary reported the end of its run and was not ended by a signal. | — |
| `"build_failed"` | The file did not build. None of its tests ran. | `diagnostics` |
| `"aborted"` | The test binary was ended by a signal, or it exited before it reported the end of its run. An exit with code `0` before that point is `aborted` too. | `signal` or `exit_code`; `running` when known |

Every `file` line carries the six-key `summary`. For `build_failed`, every count is `0`: the file added no tests. For `aborted`, the counts cover the `test` lines that the file wrote before it ended. Those lines stay in the stream and count in the `run` summary.

```json
{"record": "file", "file": "tests/test_codec.bl", "outcome": "ran", "summary": {"total": 0, "passed": 0, "failed": 0, "panicked": 0, "skipped": 0, "duration_ms": 1}}
{"record": "file", "file": "tests/test_parse.bl", "outcome": "build_failed", "summary": {"total": 0, "passed": 0, "failed": 0, "panicked": 0, "skipped": 0, "duration_ms": 0},
 "diagnostics": [{"severity": "error", "name": "TypeError", "code": "E0300", "message": "expected Int, found Str", "span": {"file": "tests/test_parse.bl", "line": 14, "col": 22}}]}
{"record": "file", "file": "tests/test_ffi.bl", "outcome": "aborted", "signal": "SIGSEGV", "running": "reads mapped page", "summary": {"total": 2, "passed": 2, "failed": 0, "panicked": 0, "skipped": 0, "duration_ms": 9}}
{"record": "run", "summary": {"total": 2, "passed": 2, "failed": 0, "panicked": 0, "skipped": 0, "duration_ms": 10}, "files": {"total": 3, "ran": 1, "build_failed": 1, "aborted": 1}}
```

The first line is a file that built and holds no tests. Compare it with the second: the counts are the same, and `outcome` tells the two apart.

**`build_failed` fields.**

- `diagnostics` is a list of diagnostic objects in the shape of §8.6. It is never empty.
- A diagnostic with no source location has no `span`. It never carries a placeholder location such as `line: 0`.
- When the front end accepts the file and a later build step fails, `diagnostics` holds one diagnostic for that step:
  - The generated C does not compile: `severity: "ice"` (internal compiler error). This is a compiler bug, not an error in the test file.
  - The link step or a native-dependency step fails: `severity: "error"`. The cause is the project's setup, for example a missing native library.
  - `message` names the failed step and gives the tool's first error line. `notes` is a list of strings that holds the tool's full output, one line per entry. `blink test` may cut `notes` short; when it does, the last entry says that the output was cut.

**`aborted` fields.**

- Exactly one of `signal` and `exit_code` is present. A process that a signal ended has no exit code.
- `signal` is the signal name as a string, for example `"SIGSEGV"`. When the platform has no name for the signal, the value is `"SIG<n>"`, for example `"SIG34"`. A signal number is not portable (`SIGBUS` is 7 on Linux and 10 on macOS), so the record never carries a bare number.
- `exit_code` is the code of a process that exited before it reported the end of its run.
- `running` is the name of the test that was running when the binary ended. It is present only when `blink test` knows it, and it is never a guess or a placeholder. When the binary ended outside any test, `running` is absent.

*Informative.* `blink test` can learn `running` because the test lines are written as each test ends: the running test is the first test, in the file's run order under the same filter, that has no `test` line.

**Run counts and exit code.** The `run` line carries `files`:

```
files.total = files.ran + files.build_failed + files.aborted
```

When `files.aborted > 0`, the test counts are a lower bound: tests of an aborted file that wrote no `test` line are in no count.

`blink test` exits `1` when `failed + panicked + files.build_failed + files.aborted > 0`, and `0` otherwise. It has no other non-zero exit code.

**Human-readable output.** A file that does not build prints `BUILD FAILED` and its diagnostics. A file that aborted prints `ABORTED` and how it ended, with the test name when it is known:

```
BUILD FAILED tests/test_parse.bl
  error[E0300]: expected Int, found Str
  at tests/test_parse.bl:14:22

ABORTED tests/test_ffi.bl
  signal SIGSEGV in test "reads mapped page"
```

The summary line adds a file clause for each of these counts only when it is above `0`:

```
2 passed, 0 failed (of 2); 1 file did not build, 1 file aborted
```

*Informative.* To test that a compiler rejects a program, or does not yet accept it, write a test that builds: it passes the program's source as a string to a compile step and asserts the result. The project supplies that compile step; the standard library does not.

**Panel vote: 6-0** to remove the `.tmp/<ticket>/` parking workflow, the `--parked` flag, the `parked_file` NDJSON event and the `.tmp/` lint. **5-1** for the behavioral sentence above and **5-1** for the informative note; Minimalism dissented on both (the build-failure behavior belongs with the separate ticket that specifies its record shape, and the note serves only projects whose tests drive a compiler). This supersedes the 5-1 parking vote of the expected-failure decision. See [DECISIONS.md](../DECISIONS.md) and [decisions/parking-removal-and-xfail-ticket.md](../decisions/parking-removal-and-xfail-ticket.md).

**Panel vote** (file outcomes and the line stream): **6-0** for one `file` line per file with the closed `outcome` enum, the `files` counts, the exit code, the lower-bound rule, and `aborted` on an early exit with no end-of-run report; **6-0** for one line per test (after 3-3 in the first vote) and for ignoring an unknown `record` value; **6-0** for the signal name (after 3-3), with flat keys by user (BDFL) tiebreak after 3-3; **4-2** for the severity split by build step (Systems and DevOps dissented: generated C can fail on a user's header, so they wanted `error` for every step), with the tool output in `notes` by user decision; **5-1** for an all-zero `summary` on `build_failed` (Minimalism dissented); **5-1** for `running` with the method left informative (Minimalism dissented); **5-1** for the word `ABORTED` (Web/Scripting dissented for `CRASHED`/`EXITED`). See [DECISIONS.md](../DECISIONS.md) and [decisions/test-file-outcomes.md](../decisions/test-file-outcomes.md).

---

#### 8.10.6 Expected-failure tests (`test.failing`)

A test that **builds and runs** but is *expected* to be red — because the feature it exercises is deliberately not yet implemented — is registered with `test.failing` instead of `test`:

```blink
test.failing(
  "trait impl resolves through alias chain",
  reason: "Phase 3 trait elaboration not yet implemented",
) {
  // ... test body, expected to fail today
}
```

`reason: Str` is **mandatory** and must be non-empty. It tells *why* the test is expected to fail. A missing or empty `reason:` is error E0835. `test.failing` takes no other arguments. To point at tracked work, write the reference in `reason:`.

##### Encoding in the NDJSON record

`test.failing` does **not** add a new top-level status and does **not** add a new `cause` value. The four statuses (`passed | failed | panicked | skipped`) and the two `cause` values (`assertion | propagated_error`, §8.10) remain closed enums. Instead, each test record gains two optional fields:

| Field | Type | Meaning |
|-------|------|---------|
| `expected_fail` | `Bool` | `true` iff the test was registered with `test.failing` |
| `xfail_reason` | `Str` | The `reason` from the registration, unchanged. It appears exactly when `expected_fail` appears |

The **expected** (red) case emits `status: "passed"`:

```json
{ "name": "trait impl resolves through alias chain",
  "status": "passed",
  "expected_fail": true,
  "xfail_reason": "Phase 3 trait elaboration not yet implemented" }
```

The test ran, failed as expected, and the runner counts that as a success — `status: "passed"` reflects the *suite-level* outcome.

A panic is also an expected red. Every expected-red record carries one more field, which names the status the test had before `test.failing` inverted it. An expected-red panic also keeps the panic's `message` and, when known, `span`:

| Field | Type | Meaning |
|-------|------|---------|
| `xfail_observed` | `"failed" \| "panicked"` | The status the test would have had without `test.failing` |

```json
{ "name": "trait impl resolves through alias chain",
  "status": "passed",
  "expected_fail": true,
  "xfail_reason": "Phase 3 trait elaboration not yet implemented",
  "xfail_observed": "panicked",
  "message": "unwrap called on None",
  "span": {"file": "tests/test_traits.bl", "line": 40, "col": 9} }
```

Rules for `xfail_observed`:

- It appears only when `expected_fail` is `true` and `status` is `"passed"`. It never appears on any other record.
- Its value is the status the test would have had without `test.failing`. The values are two members of the status enum, `failed` and `panicked`, and never any other string. It is not a separate enum.
- It agrees with the rest of the record: a record with `xfail_observed: "panicked"` carries the panic's `message`, and `span` when known.

A consumer reads `xfail_observed` to find which kind of red a known failure had. It never needs to search `message` text for this.

An **unexpected pass** (the test was expected to fail but actually passed) becomes a suite failure with `status: "failed"`:

```json
{ "name": "trait impl resolves through alias chain",
  "status": "failed",
  "cause": "assertion",
  "assertion": "expected failure, got pass",
  "expected_fail": true,
  "xfail_reason": "Phase 3 trait elaboration not yet implemented" }
```

The suite-failure rule is mechanical. It reads only `status`:

- `status == "failed"` — the suite fails. When `expected_fail` is absent or `false`, this is an ordinary test failure. When `expected_fail` is `true`, this is an unexpected pass, with `cause: "assertion"` and `assertion: "expected failure, got pass"`.
- `status == "panicked"` — the suite fails.
- `status == "passed"` — the suite does not fail. When `expected_fail` is `true`, this is an expected red (see `xfail_observed`).
- `status == "skipped"` — the suite does not fail.

An unexpected pass is the only record with `expected_fail: true` and `status: "failed"`. A consumer tests the pair, not the `assertion` text. `expected_fail` is never true on a `panicked` record.

A skipped `test.failing` test keeps `expected_fail: true` and `xfail_reason`. It has no `xfail_observed`. The run gave no result: the record is neither an expected red nor an unexpected pass.

```json
{ "name": "trait impl resolves through alias chain",
  "status": "skipped",
  "reason": "env gate",
  "expected_fail": true,
  "xfail_reason": "Phase 3 trait elaboration not yet implemented" }
```

For a `test.failing` test that uses `for_each` (§8.10.2): `cases` entries never carry `expected_fail` or `xfail_reason`. The parent record carries them whatever its status.

*Informative:* the human-readable output may mark a skipped `test.failing` test on its skip line, so the text log shows the same facts as the record. This section does not specify the marker, and its text is not stable. Tools read the NDJSON record, not the human output.

There is **no** soft / "warn-only" mode for unexpected passes. The intent of `test.failing` is to record a known red state; the moment it goes green, the test must be moved back to `test(...)` in the same commit that removes the `test.failing` registration.

##### When to use which mechanism

A four-case decision rule, mechanical enough for AI code generators to apply without judgment:

| Situation | Mechanism |
|-----------|-----------|
| The fixture file **does not build** (uses syntax / feature the compiler does not yet accept) | Not a test (§8.10.5); keep it out of the test tree until it builds |
| The fixture builds, runs red, and the feature it exercises is **deliberately not yet implemented** | `test.failing(..., reason:)` |
| The fixture builds, runs red, and the code under test has a **bug** | Ordinary `test(...)` — the failure is the regression signal |
| The fixture builds but should not run yet (environmental gate, slow, etc.) | `skip(reason:)` |

`test.failing` is reserved for the second row only. It is **not** a debugging tool, not a "mark this red for now" convenience, and not a substitute for fixing a bug.

**Panel vote.** Q1 (`.tmp/<ticket>/` parking workflow with runner integration): **5-1**, PLT dissent. Q2 (ship runtime xfail now, not later): **3-3 → user (BDFL) tiebreak in favor of shipping** — Blink users are actively requesting it. Q3 (encoding under closed-status / closed-cause enums): **4-2** for the boolean `expected_fail` field with paired `xfail_reason` (rejected alternatives: new top-level `xfailed` status, new `cause` value). Mandatory non-empty `reason:` and strict-by-default unexpected-pass semantics are non-negotiable mitigations bundled with shipping. See [DECISIONS.md](../DECISIONS.md) and [decisions/xfail-and-parking.md](../decisions/xfail-and-parking.md).

**Superseded in part.** A later decision removed the parking workflow (Q1 above, §8.10.5) and the `br` coupling: the panel voted to remove parking and the closed-ticket lint (**6-0** each), and the user (BDFL) overruled the panel's optional `ticket:` to remove the argument from the language, so `xfail_reason` holds the reason only. See [decisions/parking-removal-and-xfail-ticket.md](../decisions/parking-removal-and-xfail-ticket.md).

**Rule text fixed.** A later panel fixed the suite-failure rule above to match the unexpected-pass example and the runtime. Rule keyed by `status` alone, over all four statuses: **5-1** (Minimalism dissent, for rules keyed by `status` and `expected_fail` together). The "only record" sentence with "a consumer tests the pair": **5-1** after a second round (Systems dissent, for the first sentence only). "`expected_fail` is never true on a `panicked` record", with no sentence on `xfail_observed`: **3-3 → user (BDFL) tiebreak**. No sentence that `expected_fail` is a property of the test: **3-3 → user tiebreak**. The added sentence in §8.10: **5-1** (Minimalism dissent: two copies can drift). See [decisions/xfail-unexpected-pass-rule.md](../decisions/xfail-unexpected-pass-rule.md).

**Skipped records.** A later panel ruled on a skipped `test.failing` test. Both fields on every record of a `test.failing` test, `skipped` included, with the runtime fixed to match: **6-0**. The `xfail_reason` presence rule in its table row: **5-1** (Systems dissent, for one sentence after the table). The `expected_fail` row unchanged: **5-1** (AI/ML dissent, for a row that also says "absent on all other records"). The sentence on a skipped record: **4-2** in the first round, then **6-0** for a reworded sentence, with the wording chosen by plurality and ranked preference (3 first choices of 6). The informative note on human output: **5-1** (Minimalism dissent). The `cases` line: **5-1** (Minimalism dissent, for one clause). See [decisions/xfail-skipped-record.md](../decisions/xfail-skipped-record.md).

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

For rapid AI iteration, `blink eval` interprets code with full type checking and effect tracking — no compilation step:

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
| `blink fix <file>` | Apply the machine-applicable fixes of a file's diagnostics (§8.6) |
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
| `blink test --seed <u64>` | Fix the suite seed (hex `0x...` or decimal) for reproducible random tests (§8.10.4) |
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
| **Language Reference** | |
| `blink llms` | Print the index of the language reference (§8.17) |
| `blink llms --full` | Print the core: the language rules, at most 46,000 bytes |
| `blink llms --topic <name>` | Print one topic, at most 12 KiB |
| `blink llms --list` | List topic names with their sizes in bytes |
| `blink llms --all` | Print the core and every topic |
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
- **`span` appears only on `enter`** — source location is static per function.
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

`ts_us` is a monotonic microsecond counter relative to trace start (not wall-clock time). Microsecond resolution matches the instrumentation overhead — sub-microsecond precision would measure the tracer, not the program.

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

- **Per-package.** Each package in a dependency graph can use a different edition. A 2026-edition library compiles alongside a 2028-edition application with no friction.
- **Scope.** Editions gate three things:
  1. **Stdlib API** — deprecated functions become errors, new defaults take effect
  2. **Keywords** — a new edition can reserve identifiers (e.g., promoting a soft keyword to a keyword; §2.23 *Soft Keywords*)
  3. **Lint severity** — warnings in edition N can become errors in edition N+1

  The manifest schema does not depend on the edition: the toolchain alone decides which sections and keys it knows. This rule is for spec authors. A section or key that changes what a package builds to — which code it compiles, which code it resolves, or which rules check it — enters the schema only together with a new edition. The change that adds the first such section also adds the error for a package whose edition is too old to use it. A section or key that does not change what the program does when it runs (metadata, tool hints, a setting that changes only speed or size) can enter in any `blink` release. This is why it is safe for an older toolchain to skip an unknown section with W1001 (§8.9.8).
- **NOT core syntax.** Editions never change the grammar of `fn`, `match`, `let`, `if`, braces, or any core construct. An edition cannot make previously-valid syntax invalid (except for newly reserved keywords). The AST structure is eternal.
- **Infinite compatibility.** Every edition is supported forever. The compiler never drops support for an older edition. A `edition = "2026"` package compiles with the 2035 compiler. There is no "upgrade or die" — upgrading editions is always voluntary.
- **Default.** When `edition` is omitted from `blink.toml`, the compiler uses the latest stable edition at the time the compiler was built. For new projects, `blink init` writes the current edition explicitly. An `edition` that the toolchain does not know is an error (§8.9.8).

**How editions interact with dependencies:** The compiler resolves each package's edition independently. If package A (edition 2028) depends on package B (edition 2026), the compiler checks A against 2028 rules and B against 2026 rules. No edition leaks across package boundaries. This is why editions can only gate per-package concerns (stdlib, keywords, lint) — they cannot change type system semantics or effect resolution, which are cross-package.

**Editions vs. the language version.** The cross-package type-system constants that editions cannot reach are fixed by the **language version** — the compiler/spec revision reported by `blink --version` (§9.1.3, line `blink 0.3.0 (stdlib 0.3.0)`), not the per-package `edition` and not package semver. The bridge alphabet (§9.1.3.2) is the first such constant: the set of element types `T` that flow through the byte-bridge primitives is identical for every package in a build regardless of any package's edition. Your edition does not and cannot change it — there is no per-package opt-in. The language version is not a third versioning *knob*: it is simply which `blink` binary you are running, the way `node`/`python` version is fixed by the interpreter you invoke, never declared in a manifest.

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
- `--edition <year>` — migrate to a specific edition (skipping intermediate editions is allowed; all fixes from intermediate editions are applied cumulatively). A year that names no known edition is `UnsupportedEdition` or `InvalidEdition` (§8.9.8), with the span on the argument
- `--json` — structured JSON output (default when piped)

The `blink migrate` command is idempotent. Running it on a package that is already at the target edition produces no changes.

#### 8.16.4 `blink editions`

The `blink editions` command displays a changelog of all editions. No network access required — the changelog is always available offline.

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
- `--edition <year>` — show changes for a specific edition only. A year that names no known edition is `UnsupportedEdition` or `InvalidEdition` (§8.9.8), with the span on the argument

The changelog is also exposed in the `llms.txt` header (§8.3) as an edition-specific API change summary, giving AI agents immediate awareness of what has changed between the edition a project uses and the current edition.

#### 8.16.5 Edition Cadence

- **At most one edition per year.** Editions are not releases — they are compatibility snapshots. Most years will have zero or one edition.
- **Names increase.** Each new edition is named for a year after the newest existing edition.
- **2+ year deprecation window.** Any item deprecated in edition N cannot have `removal` earlier than edition N+2. This gives downstream consumers at minimum two years to migrate.
- **Infinite backward compatibility.** The compiler never drops edition support. Edition 2026 code compiles with the 2040 compiler.
- **Enforced semver (v2).** In v2, the package manager enforces that `removal` editions align with major version bumps of the package. A library cannot remove a deprecated API within the same major version. This is not enforced in v1 (path + git deps only, no registry infrastructure).
- **No flag days.** Because editions are per-package and compatibility is infinite, there is never a moment where the ecosystem must upgrade in lockstep. Each package migrates on its own schedule.

---

### 8.17 In-Context Language Reference

An agent writes correct Blink only when the rules it must obey are in its context. The full specification is about 245k tokens, and no agent can hold that. So Blink defines a **core**: a subset of this specification that fits one context budget and is enough to write correct programs. `blink llms --full` prints it.

**Panel vote: 6-0** on every point in this section except the topic cap (5-1, §8.17.2). See [decisions/reference-context-budget.md](../decisions/reference-context-budget.md).

#### 8.17.1 The Core

**One source.** The core is made of marked blocks inside this specification. It is not a second text. This specification is the only normative source. The generator builds the core text and the `blink llms` output from it, and nobody edits that output by hand. If the committed core text is not equal to what the generator prints for the current specification, the build fails.

**Reference files in the repository.** `llms.md` and `llms-full.md` are reference files. They state no more and no less than this specification. The `Option` and `Result` method names in their tables, and in the compiler help text, match the tables in §7.6. A `blink` code block in a reference file, and each program in `examples/`, must pass `blink check`. A known failure goes on a list that has an entry for each failure, with the change that clears it. The list can only get shorter.

**Core blocks.** A core block is a marked span of a section:

```
<!-- core:types.match.exhaustive -->
Rule text, with its examples as fenced `blink` code.
<!-- /core -->
```

- Each block has a **semantic ID**: lowercase words joined by dots. The ID stays the same when sections are renumbered. Each ID is unique in the specification.
- A block must be correct when it is the only text the reader has. It names what it uses and does not depend on prose outside the block.
- Examples go inside the block as fenced `blink` code. A block can also hold a derivation line (`e? ≡ match e { ... }`) beside its example.
- A block states rules. Rationale stays outside core blocks.

**Byte cap.** The generated core is at most **46,000 bytes**. At the measured 2.3 bytes per token, that is about 20k tokens. The cap is in bytes so that the check is the same on each machine and needs no tokenizer. A core over the cap fails the build, and there is no allowlist. Only a panel vote can raise the cap. Each release reports the measured bytes per token. That figure is information, not a check.

**What the core holds.**

- The language: the rules a program must obey, in specification order.
- The names of the prelude types and traits, and one line for each prelude trait.
- One pointer line for each topic that holds content outside the core, for example:

  ```
  FFI: `blink llms --topic ffi`
  ```

**What the core does not hold.** Method tables, install steps, CLI and build flags, emit modes, the daemon, FFI detail and arena detail. These are topics (§8.17.2).

**Head and tail lists.** The core starts with a **divergence list**: the facts where Blink differs from what a capable model assumes. The core ends with a **common-errors list**. These lists are core blocks too. Each bullet in them cites the ID of the core block that states the rule.

**API-shape divergences.** Sometimes a model guesses the shape of a standard-library method wrong, for example its return type or how to call it. That fact goes in the divergence list as a core block. lib/std gets no marker for it. The block's examples must pin the shape so that a change in lib/std makes them fail: an annotated binding for the type, and an error example for the form that does not compile.

```blink
fn main() ! IO {
    let mut m = Map.new[Str, Int]()
    m.insert("k", 1)
    let v: Option[Int] = m.remove("k")    // remove returns the old value, not Bool
    io.println("{v ?? 0}")
}
```

```blink
fn main() {
    let mut m = Map.new[Str, Int]()
    m["k"] = 1                            // error[NoIndexOperator] -- intentional-error example
}
```

**Closure.** The core is closed under its own references. Each ID or `§` reference in the generated core names a core block, or is written as an explicit `--topic` pointer. Prelude names and keywords count as defined. Words in the prose are not checked.

#### 8.17.2 Topics

All content outside the core is served as topics. `blink llms --topic <name>` prints one topic.

- Each topic is at most **12 KiB** (12,288 bytes), so one topic is one small fetch. (Panel vote: 5-1. Minimalism dissented: add a topic cap only when a topic grows too large.)
- The index that `blink llms` prints with no flag is at most **6 KiB** (6,144 bytes).
- Standard-library API topics are generated from the lib/std declarations, the same data that `blink doc` reads. Nobody writes a method table by hand.
- CLI and build-flag topics are generated from the CLI's command and flag registrations.

A topic name is what an agent would guess: `ffi`, `build`, `cli`, or a type or module name.

#### 8.17.3 `blink llms`

| Command | Prints | Size limit |
|---------|--------|------------|
| `blink llms` | The index: what Blink is, the commands below, and the topic names | 6 KiB |
| `blink llms --full` | The core | 46,000 bytes |
| `blink llms --topic <name>` | One topic | 12 KiB |
| `blink llms --list` | Each topic name with its size in bytes | — |
| `blink llms --all` | The core and every topic | None |

`--full` is the core with a size limit. `blink init` writes `blink llms --full` into a project's agent instructions, so the meaning of `--full` does not change. `--all` makes no size promise. With the sizes from `--list`, an agent can choose what to fetch.

#### 8.17.4 Checks

The build fails unless each of these is true:

1. The core is at most 46,000 bytes, each topic is at most 12 KiB, and the index is at most 6 KiB.
2. Each `blink` fence in the core and in the topics compiles. An intentional-error example fails with exactly the code that it names.
3. The committed generated reference is equal to the generator output.
4. Each ID is unique, and each ID reference resolves.
5. The core is closed (§8.17.1 *Closure*).
6. Each diagnostic code in the core is in the diagnostic catalog.

Two properties have no check: that a block is correct alone, and that a rule earns its place in the core. Review enforces them.

#### 8.17.5 Authoring Rules

- **What goes in the core.** Put a rule in the core when a capable model with no Blink knowledge would probably get it wrong. Leave out what such a model gets right, and what it can fetch when a compile error tells it to look.
- **A closure failure.** The usual fix is a `--topic` pointer, not a larger core. Move a block into the core only when the rule above puts it there.
- **Rationale labels.** A paragraph either states a rule or explains one. A paragraph that explains a rule has the label `*Rationale.*` and never a label that calls it normative.

---

### 8.18 Summary

The tooling story is not a feature list — it is the thesis of the language:

1. **The compiler is a service,** not a batch job. It runs continuously, maintains a live model, and responds in milliseconds.
2. **Code is queryable,** not just readable. Semantic access to the codebase by effect, type, intent, and contract.
3. **Inspection is layered.** The AI chooses the granularity it needs — from 20-token intent summaries to full implementations.
4. **Diagnostics are structured.** Errors include machine-applicable fixes. The AI's fix loop is mechanical, not inferential.
5. **Alternatives are preserved.** Multiple valid implementations coexist, type-checked, selectable by configuration.
6. **There is one tool for each job.** One formatter, one package manager, one test runner, one way to do everything.

The result: an AI agent working with Blink has roughly 8x the effective context capacity, sub-second feedback loops, and structured machine-readable access to every aspect of the codebase. This is the difference between AI as a code completion engine and AI as a software engineering partner.
