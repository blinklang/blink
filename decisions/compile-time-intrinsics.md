[< All Decisions](../DECISIONS.md)

# Compile-Time Intrinsics (`#` sigil) — Design Rationale

### Panel Deliberation

Five panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML) voted across three rounds on questions arising from the GAPS.md "raw/uninterpolated string syntax" entry. The friction log (2026-02-25, blocking) reported that embedding LLM reference text in cli.pact was impossible without escaping every `{`, `}`, and `"`. The panel reframed the problem: the issue isn't "strings need escaping" — it's "large external text blobs need inclusion." These are different problems with different solutions.

**Round 1 (5-0): Compile-time file inclusion, not new string syntax**

All 5 experts independently proposed compile-time file inclusion instead of raw strings, triple-quotes, or `{{ }}` escaping. Nobody voted to override the locked "one string syntax" decision. Key insight (Systems): "The friction log's real problem is not 'strings need escaping' — it's 'I need to embed a large external text blob.'" The `\{`/`\}` escaping is adequate for inline strings (especially with LLM authors). Large blobs belong in files, not string literals.

**Round 2: Visual signal for compile-time intrinsics**

The critical follow-up: every language that does compile-time evaluation marks it visually — Rust's `!` macro sigil, Zig's `@` prefix, Go's `//go:` directives. Pact's compile-time intrinsics must be visually distinguishable from runtime function calls, or LLMs will confuse compile-time and runtime, try passing variables instead of literals, etc. Furthermore, a forward-compatible signal is needed: `#embed` today, but `#env`, `#version`, `#target`, `#file`, `#line` in the future. Shipping an unsigiled builtin in v1 and retrofitting a sigil in v2 would be a breaking change.

Three options considered:
- **A: Unsigiled builtin** — `const X = embed_file("path")` with `const` as the visual signal
- **B: `$` prefix** — `$embed("path")` with `$` as compile-time intrinsic category
- **C: `#` prefix** — `#embed("path")` with `#` as compile-time intrinsic category

Initial proposals split A=2, B=2 (naming variant), C=1. After collapsing the A/B naming difference and reframing as "const-context-only vs sigil category," tiebreaker was 4-1 for const-only (YAGNI — only one intrinsic in v1). However, the user identified the fundamental flaw: if v2 adds `#env`, `#version`, etc., retrofitting a sigil onto `embed_file()` is a breaking change. The sigil decision is load-bearing for forward compatibility.

**Round 3: `$` vs `#` (5-0 for `#`)**

With the sigil category accepted as necessary, the panel voted on which sigil:

- **Systems:** Vote `#`. Swift's direct precedent (`#file`, `#line`, `#embed`) is the deciding factor. The lexer advantage (tokenizing `#ident(` as a distinct token class without context) is a real codegen win.
- **Web/Scripting:** Vote `#`. A developer who has touched any Swift or modern C will read `#embed("path")` and immediately understand "the compiler resolves this." `$` has too much dynamic/interpolation baggage from scripting languages.
- **PLT:** Vote `#`. Swift's `#file`, `#line`, `#embed` gives LLMs unambiguous phase-correct training signal. `$` carries dominant "dynamic variable" semantics from shell/scripting that actively misleads about compile-time evaluation.
- **DevOps/Tooling:** Vote `#`. Swift's direct precedent means LLMs and tooling already have strong training signal. LSP token classification, syntax highlighting, and error messages are unambiguous at the lexer level.
- **AI/ML:** Vote `#`. *(Switched from `$`.)* Swift's `#file`, `#line`, `#embed` is direct precedent in a compiled language LLMs have trained on extensively. The failure mode of `$` (LLMs treating it as dynamic interpolation) is worse than the failure mode of `#` (LLMs expecting preprocessor power).

**AI-First Review: 5/5 PASS**

1. **Learnability** — PASS. Swift `#file`/`#line`/`#embed` is direct precedent in LLM training data
2. **Consistency** — PASS. `#` is a new, clean syntactic category — no collision with `@` annotations or `!` effects
3. **Generability** — PASS. `#name("arg")` is one pattern for all compile-time intrinsics
4. **Debuggability** — PASS. E1108 file not found, E1109 non-literal arg — both point at `#embed(...)` expression
5. **Token Efficiency** — PASS. One character prefix, single line

**Resolution:** `#embed("path")` with `#` as the compile-time intrinsic sigil category. `#embed` is the only v1 intrinsic; `#env`, `#version`, `#target`, `#file`, `#line` are reserved for future versions. No new string syntax. Locked "one string syntax" decision preserved. Spec: §2.4.1.

