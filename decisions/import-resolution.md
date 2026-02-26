[< All Decisions](../DECISIONS.md)

# Import Resolution — Design Rationale

### Panel Deliberation

Five panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML) voted independently on 4 questions.

**Q1: Search path algorithm (5-0 for single `src/` root)**

- **Systems:** Deterministic resolution with zero env-dependent state. `import foo.bar` → `src/foo/bar.pact`, done. One stat call. Configurable source roots create shadowing bugs that only manifest in CI with different directory layouts.
- **Web/Scripting:** Go proved single-root works. Python's sys.path is a legendary footgun — "works on my machine" is 90% a path problem. One folder, one rule.
- **PLT:** Resolution must be a total function from module path to file. Single root gives `resolve(path) = src/ ++ path.replace(".", "/") ++ ".pact"`. Configurable roots make resolution partial — first-match is nondeterministic if two roots contain the same module name.
- **DevOps:** LSP go-to-definition must be instant and unambiguous. Single root = path rewrite. Multiple roots = scan and handle shadows. Workspaces can be layered later without breaking single-root.
- **AI/ML:** LLMs generate imports by pattern matching. `import auth.token` → `src/auth/token.pact` is a mechanical rewrite the model learns instantly. Configurable roots mean the model must read `pact.toml` to resolve — extra context dependency that increases error rates.

**Q2: Cycle handling (4-1 for intra-package OK, cross-package error)**

- **Systems:** Intra-package cycles are natural — `auth.login` needs `auth.types`, and `auth.types` may reference errors from `auth.login`. Forcing extraction into a third module is artificial ceremony. Cross-package cycles are genuinely pathological.
- **Web/Scripting:** Strict no-cycles is frustrating in practice — hit it in Go constantly. Two files in the same directory should reference each other without extract-to-avoid-cycle gymnastics. Cross-package cycles are a real design smell.
- **PLT:** Within a package, the compiler resolves all declarations before checking bodies — standard ML-module semantics. Cross-package cycles would require recursive module resolution which is complex and rarely needed.
- **DevOps:** Strict cycles everywhere. Cycles within a package still make the dependency graph messy for incremental compilation — daemon can't recheck one module without rechecking the other. Forces clean layering. *(dissent)*
- **AI/ML:** LLMs generating multi-file modules naturally create cross-references between files in the same package. Forcing strict no-cycles means the model must plan extraction ahead of time — a planning task that increases error rates.

**Q3: Diamond dependencies (4-1 for exactly one version per package)**

- **Systems:** One version per package. Multiple versions in one binary break global state, type identity across versions, and FFI symbols. Go's minimum version selection is the right model.
- **Web/Scripting:** The "one version" constraint is why Go has dependency hell at scale. SemVer-compatible dedup gives flexibility — `http 0.5.1` and `http 0.5.3` can coexist as `http 0.5.3`. *(dissent)*
- **PLT:** Type identity requires one version. If `auth` uses `http.Response` from http 0.6 and `myapp` expects `http.Response` from http 0.5, these are distinct types. The compiler must reject this or insert hidden conversions (which Pact already rejected).
- **DevOps:** `pact.lock` has one version per package. Resolution is deterministic. Multiple versions → "which version did this bug come from?" diagnostic nightmare.
- **AI/ML:** LLMs don't reason about semver. They import `http.Response` and assume one definition. Multiple versions mean generated code might reference the wrong version's API silently.

**Q4: Re-exports (5-0 for `pub import`)**

- **Systems:** `pub import` is clean, explicit, and compiles to nothing — it's a namespace alias. Without re-exports, every consumer must know internal module structure. Adding a file forces downstream import changes.
- **Web/Scripting:** Every modern JS package has an `index.js` barrel file. `pub import` is the typed, explicit version. Without it, refactoring (moving a type between internal modules) breaks every consumer's imports.
- **PLT:** Re-exports are module-level abstraction — the module signature is independent of internal layout. Standard in ML, OCaml, Haskell.
- **DevOps:** LSP resolves `pub import` by following one redirect. Go-to-definition lands on the original declaration. Package-level re-exports mean the public API is visible in one file.
- **AI/ML:** `pub import auth.token.{Token}` is explicit and greppable. LLMs generate it mechanically. No re-exports forces models to track internal module structure — more context needed per import.

