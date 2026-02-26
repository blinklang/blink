[< All Decisions](../DECISIONS.md)

# Stdlib Distribution & Import Resolution — Design Rationale

### Panel Deliberation

The import resolution algorithm (§10.5) specified local `src/` resolution and `pact.lock` dependency resolution but had no mechanism for standard library modules. This gap blocked stdlib modules (`std.toml`, `std.semver`) from being importable outside of the compiler's own `src/` directory.

**Q1: Where does the stdlib physically live? (4-1 for D: virtual/implicit dependency)**

- **Sys (A):** Alongside compiler binary in `<pactc_dir>/stdlib/`. Hermetic, relocatable, matches Go/Zig.
- **Web (D):** Virtual dependency. Zero new concepts — stdlib is just deps you didn't have to declare. Go's approach.
- **PLT (D):** Uniform module semantics. No special resolution step. Effect system needs zero special cases.
- **DevOps (D):** Virtual dep backed by `<pactc_dir>/lib/std/`. LSP and compiler share same path. CI needs zero config.
- **AI (D):** Virtual dep. Implementation detail hidden from import syntax. Eliminates "where is my stdlib?" debugging.

*(dissent: Sys — preferred explicit filesystem colocating over virtual abstraction, citing Go's `GOROOT/src/` simplicity)*

**Q2: What is the import syntax for stdlib? (3-2 for A: `std` prefix)**

- **Sys (A):** `std.` prefix eliminates ambiguity. `pact.` prefix collides with language name. Matches Rust `std::`.
- **Web (C):** `pact.` prefix — spec already shows `import pact.http` in §10.5 examples. No new naming convention. *(dissent)*
- **PLT (A):** `std.` prefix avoids open namespace problems. OCaml retrofitted `Stdlib.List` for exactly this reason.
- **DevOps (A):** `std.` prefix — matches `std/` org on registry (§8.9.2). `import std.http` → `std/http` package.
- **AI (C):** `pact.` prefix — existing spec examples are the training data. Changing creates contradiction. *(dissent)*

*Clarifying note: §8.9.7 explicitly states "import paths follow the `org/name` structure: `import std.http` maps to the `std/http` package." The `pact.*` namespace in §10.6 (`pact.core`, `pact.ffi`) is reserved for compiler-internal pseudo-modules, not distributable packages. The existing spec is consistent with the `std` prefix.*

**Q3: What is the resolution order? (3-2 for C: stdlib is a dep, no new step)**

- **Sys (A):** Local → stdlib → deps → error. Stdlib is trusted toolchain code, should shadow deps for security.
- **Web (C):** Local → deps (stdlib included) → error. No new resolution step, uniform mental model.
- **PLT (C):** Stdlib-as-dep. Scales to Tier 2/3 without semantic boundary changes.
- **DevOps (A):** Local → stdlib → deps → error. With escape hatch: explicit `pact.toml` pinning overrides bundled version. *(dissent)*
- **AI (C):** Stdlib-as-dep. One resolution algorithm, zero special cases.

*(dissent: Sys — wanted explicit stdlib priority for supply-chain security. DevOps — wanted stdlib step for clearer error messages on corrupted installs)*

### Resolution

Stdlib modules are distributed alongside the compiler binary in `<pactc_dir>/lib/std/`. The compiler treats them as implicit dependencies injected into the dependency graph before resolution. Import syntax uses the `std` prefix: `import std.toml`, `import std.semver`. The resolution algorithm remains unchanged — local `src/` first, then all dependencies (including implicit stdlib entries), then error. See §10.7 for the full specification.

