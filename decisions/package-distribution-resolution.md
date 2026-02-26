[< All Decisions](../DECISIONS.md)

# Package Distribution & Resolution — Design Rationale

### Panel Deliberation

Five panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML) voted independently on 5 questions covering the package manager design gap identified in GAPS.md.

**Q1: Registry model (5-0 for hybrid)**

- **Systems:** Hybrid. Central registry provides content-addressed integrity verification. Git fallback handles private/corporate repos without requiring a private registry instance. Identity invariant prevents the "same package, two names" dependency duplication bug.
- **Web/Scripting:** Hybrid. npm taught us that a central registry with URL fallback covers 99% of cases. Corporate proxies and private repos need git URLs. The identity invariant is critical — npm has the `npm:` alias mess because they lack this.
- **PLT:** Hybrid. Go's proxy model proves this works at scale. The identity invariant is a theorem about package identity that prevents diamond-dependency confusion. Registry is the canonical source; git is a transport mechanism.
- **DevOps:** Hybrid. CI/CD pipelines need deterministic dependency resolution from a single source of truth. Git fallback handles air-gapped environments and internal packages. The lockfile pins both registry and git deps uniformly.
- **AI/ML:** Hybrid. LLMs need one canonical name per package for reliable code generation. If `http-client` and `git:...http-client.git` were different identities, models would hallucinate the wrong one. Single identity = single training signal.

**Q2: Package naming (4-1 for namespaced org/name)**

- **Systems:** Namespaced. `org/name` provides collision-free naming and maps directly to capability trust boundaries. `std/http` and `acme/http` are unambiguous. Slash separator is universal (GitHub, Docker, Go modules).
- **Web/Scripting:** Namespaced. npm's `@scope/name` proves namespacing works at massive scale. Flat naming caused the `left-pad` land-grab problem. Organizations need ownership boundaries.
- **PLT:** Namespaced. Module path mapping (`import std.http` → package `std/http`) is clean and deterministic. Namespaces provide a natural hierarchical organization that matches how developers think about code provenance.
- **DevOps:** Namespaced. Org-scoped names enable per-org security policies in CI: `std/*` packages can be auto-approved while `unknown-org/*` requires review. Trust boundaries need machine-readable organization signals.
- **AI/ML:** Flat names. LLMs trained on npm/PyPI primarily see flat names (`requests`, `express`, `flask`). Namespaced names double the token count per dependency reference and increase hallucination surface — models must get both org AND name correct. Flat names with a prefix convention (`pact-http`) would leverage existing training data better. *(dissent)*

**Q3: Version resolution algorithm (4-1 for MVS)**

- **Systems:** MVS. Deterministic without lockfile is the key property — reproducible builds are guaranteed by the algorithm, not by an artifact. No SAT solver means no exponential worst-case. Resolution is a simple graph walk.
- **Web/Scripting:** Maximal/latest. Every JS/Python/Ruby developer expects `pact add foo` to get the newest version. MVS getting the *oldest* satisfying version will confuse developers and generate support tickets. The lockfile already ensures reproducibility — MVS's determinism-without-lockfile is solving a problem we don't have since lockfiles are mandatory. *(dissent)*
- **PLT:** MVS. Russ Cox's formal proof that MVS is the only algorithm where adding a dependency cannot change existing resolved versions is compelling. Monotonicity is a strong theoretical property that prevents "dependency hell" by construction.
- **DevOps:** MVS. `pact update` is an explicit operation that upgrades. Implicit latest-version resolution means CI builds change based on when they run. MVS + mandatory lockfile = maximum reproducibility.
- **AI/ML:** MVS. Deterministic resolution means LLMs can predict resolved versions from `pact.toml` alone. Non-deterministic resolution (latest at time of resolve) means the model cannot know what versions will be selected, making version-specific API advice unreliable.

**Q4: Version constraint syntax (4-1 for caret default)**

- **Systems:** Tilde. Caret is too permissive — `"1.2"` accepting `1.9.0` trusts the entire ecosystem to never break semver within a major. Tilde (`~1.2` = `>=1.2, <1.3`) limits blast radius to patch versions, which are far less likely to break. *(dissent)*
- **Web/Scripting:** Caret. npm's `^` default has proven itself at massive scale. Developers expect `"1.2"` to mean "compatible with 1.2." Tilde is too conservative — it prevents adopting minor-version features without manual update.
- **PLT:** Caret. The semver contract explicitly states that minor versions add functionality without breaking compatibility. Caret directly encodes this contract. Tilde underutilizes semver by treating minor versions as potentially breaking.
- **DevOps:** Caret. Combined with MVS, caret is conservative in practice — MVS selects the *oldest* 1.x that satisfies constraints, not the newest. Caret + MVS = you get 1.2.0 until something explicitly requires 1.3+.
- **AI/ML:** Caret. Simpler mental model for LLMs: `"1.2"` means "1.x compatible." Models generating `pact.toml` files will use the default constraint most often — caret is the most forgiving default for AI-generated version strings.

**Q5: MVP dependency sources (5-0 for path + git only)**

- **Systems:** Path + git. Registry infrastructure is a massive engineering effort (storage, CDN, authentication, moderation). Path and git deps cover all development scenarios. Ship the language, not the ecosystem infrastructure.
- **Web/Scripting:** Path + git. npm didn't launch with a registry either — the tool came first. Developers need local and git deps for real work. Registry can follow when there's a community to serve.
- **PLT:** Path + git. The `pact.toml` schema should be forward-compatible so adding `version = "1.0"` registry deps later requires zero breaking changes. Design the schema now, ship the registry later.
- **DevOps:** Path + git. Git deps with commit-hash pinning in the lockfile provide reproducibility. Path deps enable monorepo workflows. These two cover corporate development patterns completely.
- **AI/ML:** Path + git. LLMs generating `pact.toml` for new projects will use path deps for workspace packages and git deps for external code. Registry deps need a live package index — AI can't verify package existence without it. Ship what works offline first.

**Key argument:** MVS + caret + mandatory lockfile creates a uniquely conservative system: caret constraints allow compatible updates, but MVS selects the oldest satisfying version rather than the newest. `pact update` is the only operation that moves versions forward, making dependency upgrades always intentional. This eliminates the "it worked yesterday but today it resolves differently" class of bugs.

**Dissent summary:** Web/Scripting argued that MVS's "oldest version" behavior contradicts developer expectations from every major package manager (npm, pip, cargo all select newest). AI/ML argued that flat package names would better leverage existing LLM training data from npm/PyPI ecosystems. Systems argued that tilde constraints provide tighter blast radius than caret.

