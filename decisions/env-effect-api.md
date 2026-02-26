[< All Decisions](../DECISIONS.md)

# Env Effect API — Design Rationale

### Panel Deliberation

Five panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML) voted independently on 5 questions about the Env effect API surface. High consensus: four questions unanimous, one 4-1.

**Q1: Env.Read operations (5-0 for B: Standard)**

- **Systems:** `vars()` and `cwd()` are syscall primitives (`environ`, `getcwd`) — not convenience helpers. Every systems program that spawns child processes needs the env map. `cwd()` is needed for relative path resolution. `home()` and `exe_path()` are derivable from `env.var("HOME")` and `/proc/self/exe` — stdlib, not effect surface.
- **Web/Scripting:** Config loading iterates env vars constantly. `env.vars()` to build a config map is bread-and-butter. `env.cwd()` needed for file resolution. Without them, people loop over hardcoded var name lists — ugly and fragile. `home()` and `exe_path()` are niche, defer to v2.
- **PLT:** Four operations form a clean closed set: scalar query (`var`), bulk query (`vars`), positional args (`args`), working directory (`cwd`). `home()` and `exe_path()` are derivable from `var("HOME")` — they add surface without adding capability.
- **DevOps:** `vars()` and `cwd()` essential for build scripts, CI runners, CLIs. Omitting them forces shell-outs. `home()` and `exe_path()` niche — defer them.
- **AI/ML:** These four are universal across all languages — LLMs will hallucinate `env.vars()` and `env.cwd()` even if not provided. Including them prevents hallucination errors. `home()` and `exe_path()` are niche — LLMs won't expect them on the env handle.

**Q2: Env.Write operations (4-1 for B: Standard)**

- **Systems:** `set_var` and `remove_var` are the two operations on the process environment table (`setenv`/`unsetenv`). Symmetric with read side. `set_cwd()` is process-global `chdir()` — breaks concurrent code, violates structured concurrency. If needed, should be a scoped handler.
- **Web/Scripting:** `remove_var()` needed for test setup/teardown. Setting var to empty string is semantically different from removing it. `set_cwd()` is dangerous in concurrent contexts.
- **PLT:** `remove_var` is the capability-attenuation primitive — clearing sensitive vars before delegating to untrusted code. Without it, only `set_var(name, "")` which is semantically different. `set_cwd` would require both Env.Write and FS capabilities — overly complex.
- **DevOps:** `remove_var()` is the natural complement to `set_var()`. Asymmetry confuses users. `remove_var()` on non-existent key should silently succeed (POSIX semantics).
- **AI/ML:** *(dissent)* Only `set_var()`. `remove_var` is rare in training data — fewer write ops means fewer ways LLMs generate destructive code. Can be added later without breakage.

**Q3: env.exit() placement (5-0 for A: Under Env)**

- **Systems:** `exit()` is in the same domain as process environment. Consistency with existing examples matters. Moving to `Process` means CLI programs need two effects (`Env.Read` + `Process`) — needlessly verbose. Standalone `exit()` breaks the ocap model entirely — can't be intercepted by handlers, can't be mocked in tests.
- **Web/Scripting:** `env.exit()` is the most intuitive. `Process` is about spawning/signaling child processes — different domain. Free function `exit()` would be the only side-effectful free function, contradicting Pact's core thesis.
- **PLT:** `exit` is intentional control flow with observable results (exit code), unlike `panic` which represents program errors. Making it an effect operation means handlers can intercept it for testing. The `-> Never` return type on handler operations is sound — handlers abort the computation rather than resuming past exit.
- **DevOps:** Already in examples. Keeps handle count low. Introducing Process just for `exit()` is terrible ergonomics — whole new effect for one operation. Diagnostic: `error[E0412]: missing required effect 'Env'` with actionable fix suggestion.
- **AI/ML:** Despite `process.exit(1)` having massive Node.js training weight, Pact has no `process` handle for this. Creating Process just to match Node idiom adds confusion. LLMs that generate `process.exit(1)` get a clear error and self-correct.

**Q4: Env sub-effect granularity (5-0 for A: Keep Read + Write)**

- **Systems:** Read/Write matches every other effect. Meaningful attenuation: compromised dependency with `Env.Read` can observe but not mutate. `Env.Args` distinction doesn't prevent real attacks — args often contain secrets too. Flattening loses useful information.
- **Web/Scripting:** Config-loading code declares `! Env.Read`, test setup declares `! Env.Write`. Matches mental model. `Env.Args` is over-engineering — args and env vars co-occur in practice.
- **PLT:** `Env.Args` without `Env.Read` prevents what attack? Attacker reads `argv` but not `$SECRET_KEY`? Not a meaningful capability boundary. Read/Write captures the real distinction: observation vs mutation.
- **DevOps:** Read/Write is the natural permission split. `Env.Args` adds granularity nobody asked for. Flattening loses useful permission info for LSP and audit tools.
- **AI/ML:** Two sub-effects is the sweet spot. Read/Write is universal pattern. Adding third = 50% more decision points for minimal benefit.

**Q5: Return types (5-0 for A: Simple Option[Str])**

- **Systems:** GC language, no ownership system. `Option[Bytes]` is a Rust/systems concern. 99.9% of env vars are valid UTF-8. `Result[Str, EnvError]` conflates "not set" (normal) with "invalid bytes" (nearly impossible). Non-UTF-8 is a v2 cross-platform concern.
- **Web/Scripting:** `Option[Str]` + `??` is beautiful: `let port = env.var("PORT") ?? "8080"`. Already in examples. Non-UTF-8 is not a web concern. Runtime should lossy-convert and document the behavior.
- **PLT:** `Option[Str]` is a partial function from names to UTF-8 strings. Partiality is honest (var may not exist). Value domain totality (always UTF-8 when present) is a deliberate modeling choice, same as `Int` being always 64-bit signed.
- **DevOps:** `Option[Str]` is the right default. `Result` or dual API pollutes LSP autocomplete. Non-UTF-8 is a platform edge case for 99% of programs.
- **AI/ML:** `Option[Str]` maps directly to `??` pattern. `Result` forces LLMs to choose between `?` and `??`. Dual API doubles surface. Non-UTF-8 too rare to justify.

