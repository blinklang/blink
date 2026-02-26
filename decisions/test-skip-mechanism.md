[< All Decisions](../DECISIONS.md)

# Test Skip Mechanism — Design Rationale

### Panel Deliberation

Five panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML) voted independently on whether and how to support skipping tests. Not a pre-existing GAPS.md item — arose from implementing recursive test discovery.

**Q1: Skip mechanism form (3-2 for both `@skip` annotation + `skip()` runtime built-in)**

- **Systems:** Option C. `@skip` is the zero-cost path — compiler elides the test body entirely. But runtime `skip()` is genuinely necessary for platform/environment-dependent tests. Two mechanisms is fine when they map to two fundamentally different evaluation times. Zig's `return error.SkipZigTest` proves runtime skip works cleanly.
- **Web/Scripting:** Option C. Every major framework (pytest, Jest, JUnit) ships both because they solve different problems. `@skip` is the TODO marker, `skip()` handles "this only works on Linux." Forcing conditional skips into tag filtering is clunky and unfamiliar.
- **PLT:** Option A. `@skip` operates at the declaration level as compile-time metadata — principled, composes orthogonally. Runtime `skip()` conflates a meta-level concern (whether to run) with object-level computation (the test body). This is a level confusion. *(dissent)*
- **DevOps:** Option C. `@skip` gives LSP/linter/formatter a static signal: dimmed rendering, CI warnings, reason-less skip linting. But `skip()` solves what `@skip` cannot: conditional skipping produces proper `"skipped"` status instead of misleading `"pass"`.
- **AI/ML:** Option A. `@skip` is highest-signal for LLM generation — annotation-before-test is massively represented in training data. `skip()` adds a runtime decision point that increases LLM error surface. LLMs will hallucinate `@skip` anyway; better to make the hallucination correct. *(dissent)*

**Key argument:** Compile-time and runtime skips are fundamentally different evaluation times. `@skip` cannot express "skip if no GPU" and `skip()` cannot avoid compiling/loading a test with missing dependencies. Conflating them into one mechanism forces losing either zero-cost static skipping or runtime conditional capability.

**Dissent summary:** PLT argued that skip is a meta-level judgment about the test, not part of the test's computation — `skip()` inside the body is a category error. AI/ML argued that two mechanisms doubles the decision surface for LLMs and `@skip` alone covers 90% of use cases with zero ambiguity.

