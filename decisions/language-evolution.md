[< All Decisions](../DECISIONS.md)

# Language Evolution — Design Rationale

### Panel Deliberation

Five panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML) voted across five questions on how Pact communicates breaking changes, deprecations, and new features to downstream consumers. The friction log (2026-02-26, annoying) reported that `List.get()` changed from returning raw `T` to `Option[T]` with no mechanism to inform projects or help them migrate.

**Core (5-0): Edition-gated evolution + rich `@deprecated` + `pact migrate`**

All 5 experts independently converged on the same three-part mechanism: (1) editions as per-package compatibility snapshots gating stdlib/keyword/lint changes, (2) a rich `@deprecated` annotation with structured fields enabling machine-applicable fixes, and (3) a `pact migrate` command that applies those fixes and bumps the edition. No expert proposed a mechanism that required manual migration without tooling support.

**Q1: Edition scope — what can editions change? (3-1-1)**

- **Systems:** *(dissent)* Vote **A: broad** — editions should be able to change core syntax (new expression forms, keyword semantics). Languages that limit editions to stdlib become trapped. "If you can't fix syntax mistakes, you carry them forever."
- **Web/Scripting:** *(dissent)* Vote **C: stdlib-only** — editions should only gate stdlib API changes. Keywords and lint severity are too surprising. "When my code stops compiling because a word I used as a variable is now a keyword, that's a breaking change regardless of what you call it."
- **PLT:** Vote **B: stdlib + limited behavior** — stdlib API changes, keyword reservations, and lint severity upgrades. NOT core syntax or type system semantics. "Editions that change grammar create dialects. Editions that change the surface API are just versioned defaults."
- **DevOps/Tooling:** Vote **B: stdlib + limited behavior** — keyword reservations are fine because `pact migrate` can mechanically rename variables. Lint severity upgrades catch real bugs. Core syntax changes break every tool in the ecosystem.
- **AI/ML:** Vote **B: stdlib + limited behavior** — LLMs need grammar stability across editions. If `fn` means something different in edition 2028, every code example in training data becomes edition-dependent. Stdlib changes are fine because the type checker catches misuse.

Result: **B (stdlib + keywords + lint severity)**, 3-1-1.

**Q2: Enforced semver — when does the package manager enforce removal alignment? (4-1)**

- **Systems:** Vote **A: v2** — v1 has path + git deps only, no registry. Enforcement requires registry metadata.
- **Web/Scripting:** Vote **A: v2** — premature enforcement on git deps is meaningless without version resolution.
- **PLT:** Vote **A: v2** — semver enforcement is a property of the package ecosystem, not the compiler. The compiler handles W2000/E2001; the registry handles version policy.
- **DevOps/Tooling:** Vote **A: v2** — enforcement without a registry is unenforceable. Defer to when the infrastructure exists.
- **AI/ML:** *(dissent)* Vote **B: v1** — "Even without a registry, the compiler can warn when a library's pact.toml removes a deprecated API within the same version field. It's a lint, not enforcement."

Result: **A (v2)**, 4-1.

**Q3: Compatibility window — how long are editions supported? (4-1)**

- **Systems:** *(dissent)* Vote **B: 5-year sunset** — carrying every edition forever accumulates technical debt. A 5-year window is generous and matches industry norms (Python 2→3 was 12 years). "Infinite support means infinite maintenance."
- **Web/Scripting:** Vote **A: infinite** — the cost of carrying old editions is near-zero (conditional branches in stdlib resolution). The cost of dropping an edition is ecosystem-splitting. JavaScript never breaks the web; Pact should never break the build.
- **PLT:** Vote **A: infinite** — edition logic is a small lookup table. The alternative (sunsetting) creates a coordination problem identical to Python 2→3. "If the cost is cheap, don't impose it."
- **DevOps/Tooling:** Vote **A: infinite** — CI pipelines break when compilers drop support. Infinite compat means no emergency upgrade sprints.
- **AI/ML:** Vote **A: infinite** — LLMs generate code against all editions. Dropping an edition means AI-generated code for that edition stops compiling. "The whole point of editions is to avoid breaking things."

Result: **A (infinite)**, 4-1.

**Q4: llms.txt headers — should llms.txt include edition-specific API change summaries? (5-0)**

- **Systems:** Vote **yes**. AI agents reading llms.txt should immediately know what changed between the project's edition and the current edition.
- **Web/Scripting:** Vote **yes**. This is the "AI-first migration assistant" use case. The AI reads the edition diff and generates migration patches.
- **PLT:** Vote **yes**. Structured edition diffs in llms.txt are the machine-readable equivalent of a changelog. Cross-references §8.3 layered inspection.
- **DevOps/Tooling:** Vote **yes**. CI bots and AI agents both benefit. One format serves both audiences.
- **AI/ML:** Vote **yes**. "This is literally what llms.txt was designed for — giving AI agents structured context about the project's state."

Result: **Yes**, 5-0.

**Q5: Built-in changelog — should `pact editions` exist as a built-in command? (3-2)**

- **Systems:** *(dissent)* Vote **no**. A CHANGELOG.md file or `--help` output is sufficient. Compiling a changelog into the binary is bloat.
- **Web/Scripting:** *(dissent)* Vote **no**. "Put it on a website. Binaries should be small."
- **PLT:** Vote **yes**. The changelog is small (kilobytes). Having it always available — offline, in CI, in air-gapped environments — is worth the negligible size cost. `pact editions --json` enables programmatic consumption.
- **DevOps/Tooling:** Vote **yes**. Offline availability matters in enterprise environments. `pact editions --breaking` is exactly what a CI pipeline needs before attempting a migration.
- **AI/ML:** Vote **yes**. "An AI agent running `pact editions --json` gets the full edition history in one command. No network, no file discovery, no parsing."

Result: **Yes**, 3-2.

**AI-First Review: 5/5 PASS**

1. **Learnability** — PASS. Rust editions are direct precedent in LLM training data. `@deprecated` fields are self-documenting.
2. **Consistency** — PASS. Reuses existing annotation syntax (§11.1), structured diagnostics (§8.6), and pact.toml schema (§8.9.3).
3. **Generability** — PASS. AI agents can generate `@deprecated` annotations with correct fields, and consume `pact migrate --json` output mechanically.
4. **Debuggability** — PASS. W2000/E2001 diagnostics include exact spans, replacement names, and machine-applicable fix edits.
5. **Token Efficiency** — PASS. `pact editions --json` replaces reading external changelogs. `pact migrate --dry-run --json` replaces manual deprecation auditing.

**Resolution:** Edition-gated evolution with rich `@deprecated` (since, removal, replacement, fix fields), `pact migrate` for automated migration, `pact editions` for built-in changelog. Editions scope: stdlib + keywords + lint severity, NOT core syntax. Infinite backward compatibility. Enforced semver deferred to v2. Spec: §8.16, §11.1.
