[< All Decisions](../DECISIONS.md)

# Native C Dependency Resolution — Design Rationale

### Panel Deliberation

Five panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML) voted independently on 4 questions. Resolves gap: "Native C dependency resolution for cross-compilation."

**Q1: How should `pact.toml` declare native C dependencies? (5-0 for `[native-dependencies]` section)**

- **Systems:** (B) Auto-detection from `@ffi` is fragile heuristics. `@ffi` mixing build concerns into source is wrong — how you *obtain* a library is orthogonal to how you *call* it. Manifest section is the correct separation. This is what Rust learned with `build.rs` + `Cargo.toml` links.
- **Web/Scripting:** (B) Every JS/Python dev knows "works on my machine" pain with native deps. Explicit declaration is discoverable — open `pact.toml`, see what native stuff your project needs. Option A is too magical; option C scatters build config across every FFI call site (the `node-gyp` problem).
- **PLT:** (B) Dependencies are a property of the module/package, not individual binding sites. `@ffi` already serves a clear role: typing the foreign boundary. Overloading it with resolution strategy conflates interface and provision. Auto-detection is unsound in the general case.
- **DevOps:** (B) Auto-detection is a diagnostics nightmare — when cross-compile fails, no single place to see what native deps are needed. Explicit manifest is a source of truth that CI/CD can lint and pre-check before invoking the compiler.
- **AI/ML:** (B) LLMs generate TOML config extremely reliably — every language has a similar pattern. Single greppable location for an LLM to target, no ambiguity about whether to modify an annotation or manifest. Option C scatters resolution hints across N call sites.

**Q2: What linking strategy for cross-compilation? (5-0 for static-cross/dynamic-host)**

- **Systems:** (C) Dynamic linking against cross-target is fundamentally broken without a complete sysroot. Static for cross is the only reliable path. Host dynamic is correct: picks up security patches, respects distro packaging. This is what Zig does internally.
- **Web/Scripting:** (C) This is what makes `go build` feel magical. Python wheels went through years of `manylinux` pain before landing on "bundle everything for distribution." If cross-compiling requires installing cross-target system libraries, devs are already closing browser tabs in frustration.
- **PLT:** (C) Only option principled about what the compiler can guarantee. Host: can probe the system, run pkg-config. Cross: none of those probes are valid. Static linking is the only strategy where the compiler has full knowledge of what it's linking.
- **DevOps:** (C) Only option that doesn't break existing workflows while solving cross-compile. Dynamic for host = `pact build` keeps working. Static for cross = only reliable strategy in CI/CD where runners lack target sysroots.
- **AI/ML:** (C) Zero decisions from the user in the common case. Host just works. Cross just works. One branch, deterministic. Option A guarantees failures an LLM cannot diagnose.

**Q3: How should compiler-provided built-ins differ from user @ffi? (3-2 for compiler-managed)**

- **Systems:** (C) Bundling sqlite3 amalgamation (250KB C file) eliminates the entire cross-compilation problem for `db.*`. Zero-cost at runtime. Only bundle what the compiler itself depends on. *(dissent — voted implementation-level C over design-level B)*
- **Web/Scripting:** (C) Deno ships with everything built in. Python bundles sqlite3 in stdlib. Batteries included DX. Making users declare sqlite3 because they used `db.query()` is like Python requiring pip-install of sqlite3. *(dissent — voted implementation-level C over design-level B)*
- **PLT:** (B) Genuine type-theoretic distinction. `db.*` and `net.*` are language primitives with compiler-known effect semantics, not FFI. Treating them as user `@ffi` erases this distinction. Boundary principle: compiler manages deps for language-defined effect domains.
- **DevOps:** (B) Compiler already knows about sqlite3. Making users declare it for `db.query()` is hostile ergonomics. Go gets this right: `net/http` just works. Keep user `@ffi` as a separate path through the manifest.
- **AI/ML:** (B) User should never write `[native-dependencies] sqlite3 = { ... }` for `db.query()`. Mental model is clean: built-in modules just work; bring-your-own C goes through manifest. Two rules, zero overlap.

**Resolution:** (B) compiler-managed is the design-level answer. (C) bundling is the implementation strategy that serves (B). The Sys/Web votes for (C) agree with the design intent — they just named the mechanism rather than the principle. Effective consensus: compiler manages its own effect-domain deps; bundling is how it does so for cross-compilation.

**Q4: Should dead `-lcurl` flag be removed? (5-0 Yes)**

- **Systems:** Dead linker flags add spurious runtime dependencies on host and cause hard link failures on cross-targets. Zero risk to remove.
- **Web/Scripting:** Dead code in build tooling causes phantom failures impossible to debug. Some user will spend an hour installing libcurl-dev for a target only to discover it was never used.
- **PLT:** The compiler is asserting a dependency that doesn't exist — the link flags are lying about the dependency graph. Violated invariant.
- **DevOps:** Every unnecessary `-l` flag is a dependency your build environment must satisfy for no reason. Dead code in a build system is worse than dead code in application logic.
- **AI/ML:** Dead code in a compiler is an LLM adversarial trap — context retrieval will pull in `-lcurl` and the LLM will conclude libcurl is required, generating incorrect advice.
