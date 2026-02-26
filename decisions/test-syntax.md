[< All Decisions](../DECISIONS.md)

# Test Syntax — Design Rationale

### Panel Deliberation

Five panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML) voted independently on 4 questions. Each expert ran as a separate agent and returned votes without seeing other experts' reasoning.

**Q1: Test effect model — pure by default vs implicit effects (5-0 for pure)**

- **Systems:** Pure-by-default means zero hidden runtime cost. Implicit effects require the test runner to silently inject handler implementations — hidden behavior that Pact's effect system exists to eliminate. Pure tests are trivially parallelizable since the compiler knows they're side-effect-free.
- **Web/Scripting:** JS/Python devs are used to explicit test setup. A test that silently hits a real database is a footgun. `with mock_net(...)` is self-documenting. Worth more than saving one line of boilerplate.
- **PLT:** Implicit effects destroy the information content of the effect row and require the compiler to silently insert evidence the programmer never requested. Pure-by-default preserves compositionality — the principled Koka approach.
- **DevOps:** Best diagnostics. Compiler emits actionable errors: `test "fetch data" calls fetch() which requires !Net, no handler provided. Hint: wrap in 'with mock_net(...) { }'`. LSP can offer quick-fix.
- **AI/ML:** "Pure by default, opt-in with `with`" is one rule everywhere. Two different implicit-effect contexts (main vs test) forces LLMs to track which context they're in — bad at context-dependent behavior shifts.

**Q2: Assertion built-ins (4-1 for three: assert + assert_eq + assert_ne)**

- **Systems:** Three intrinsics compile to comparison + branch + panic-with-diagnostics. `assert_match` implies compiler needs to lower arbitrary pattern syntax into assertion diagnostics — significant codegen complexity. Three is manageable; four starts to smell like a framework.
- **Web/Scripting:** `assert`, `assert_eq`, `assert_ne` — the holy trinity. Every developer from every language expects these three. `assert_match` can wait.
- **PLT:** `assert_ne(a, b)` is literally `assert(a != b)` — zero expressive power added, violates Principle 2. Keep the trusted kernel small. Two primitives form a complete basis. Compiler could special-case `assert(a != b)` for better messages via syntactic analysis. *(dissent)*
- **DevOps:** Three autocomplete entries in LSP, clean and fast. `assert_match` has ugly diagnostics — pattern failure diffs are walls of text. Defer until someone designs good pattern diff formatting.
- **AI/ML:** `assert`, `assert_eq`, `assert_ne` are near-universal across training data. Three built-ins = high coverage, low hallucination surface.

**Q3: Test discovery & filtering (4-1 for name + path + annotation tags)**

- **Systems:** Tags are compile-time metadata, zero runtime cost — stripped with test bodies. Without tags, you get name conventions encoding structured data in unstructured strings, making build systems fragile. The annotation system already exists; tags are a trivial extension.
- **Web/Scripting:** Every real-world project needs `--tag unit` vs `--tag integration`. JS-land abuses filename conventions because the framework didn't give them tags. `@tags(...)` is dead simple and immediately familiar.
- **PLT:** Annotations are already in the language — `@tags(...)` introduces no new typing concerns. Tags provide an orthogonal classification algebra without conflating naming conventions with test categorization.
- **DevOps:** Every real CI pipeline needs structured tag filtering. `@tags(...)` fits existing annotation system. Test runner output groups by tag naturally. `pact test --json` includes tags for CI parsing.
- **AI/ML:** Tags are metadata LLMs consistently forget to add. Name/path filtering requires zero additional annotation. Naming conventions are what LLMs are good at. *(dissent)*

**Q4: Test scope — top-level only vs inside modules too (4-1 for inside modules)**

- **Systems:** Tests inside `mod { }` can access private items — test internal invariants without making them `pub`. Internal data structure invariants need rigorous testing and must NOT be public API. Top-level-only forces either making internals `pub` or adding `pub(test)` visibility.
- **Web/Scripting:** This is the Rust model and it's genuinely good. Being able to write tests next to the code they test, with access to private items, is one of Rust's best features. Strictly more capable than top-level-only.
- **PLT:** Module-scoped tests seeing private items is the correct typing rule for verification. The scoping rule is uniform: `test` inside `mod M` sees `M`'s private scope, same as `fn` inside `M`. No special cases.
- **DevOps:** Tests next to code, access private items. LSP shows code lens "Run test" above each block. Filter uses path prefix: `auth::verify works`.
- **AI/ML:** Flat file structures are far more reliable for LLMs. Nested placement adds an ambiguous decision point. Rust's `mod tests { }` is the counterexample — LLMs frequently mess it up. *(dissent)*

