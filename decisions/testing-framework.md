[< All Decisions](../DECISIONS.md)

# Testing Framework — Design Rationale

### Panel Deliberation

Five panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML) voted independently on 4 questions. Resolves Tier 3 gap: "assert(), assert_eq(), panic() used in test blocks but assertion API not defined."

**Q1: Custom assertion messages (3-2 for optional trailing message)**

- **Systems:** Option B. Optional `Str` is zero-cost when omitted — compiler emits two different call sites, no runtime branch. Expression text alone isn't sufficient context for multi-layer test scenarios. Interpolation (C) adds compilation complexity for marginal gain — Pact's universal string interpolation already works in the message argument.
- **Web/Scripting:** Option C. String interpolation in assertion messages is table stakes for DX. Every modern language lets you embed values in error messages. Option A's auto-generated messages can't infer domain context. *(dissent)*
- **PLT:** Option B. Clean typing rule: `assert(cond: Bool, msg: Str = "")`. The message is a plain `Str` — Pact's regular string interpolation handles `"balance was {balance}"` before it reaches `assert`. Option C is unnecessary since interpolation is a property of the string literal, not the intrinsic.
- **DevOps:** Option C. CI/CD triage at 2am needs context like `"withdrawal of {amount} from account {acct_id}"` without reading source. JSON output should have a separate `message` field. *(dissent)*
- **AI/ML:** Option B. Dominant pattern across Python, Rust, Go, JS training data. Interpolation (C) adds format-string decision points. A useless message is cheaper than a compile error from trying to pass one when not allowed.

**Resolution note:** B and C are functionally equivalent in Pact — since all strings support `{expr}` interpolation, `assert(cond, "value was {x}")` works under Option B. The vote is really about whether the *intrinsic* needs special interpolation support (no — the *string literal* handles it).

**Q2: `panic()` function (5-0 for available everywhere)**

- **Systems:** `panic` is `__builtin_unreachable()` with a message. Every real program has invariants that can't be expressed in the type system. `Never` return type lets the optimizer eliminate dead code. Overuse mitigated via lint, not hard ban.
- **Web/Scripting:** Non-negotiable for DX. Every mainstream language has an escape hatch for "this should never happen." Forcing `Result` for truly impossible states creates boilerplate.
- **PLT:** `panic(msg: Str) -> Never`. `Never` (bottom) inhabits every type, standard in type theory. Panic is divergence, not a handleable algebraic effect — tracking it as an effect would poison every function signature. Koka separates `div` from algebraic effects for exactly this reason.
- **DevOps:** Production code needs unrecoverable error paths. Critical requirement: JSON output must distinguish `"status": "failed"` (assertion) from `"status": "panicked"` (unexpected panic) for CI categorization.
- **AI/ML:** `panic!()`/`raise` are deeply embedded in training data. Test-only panic means LLMs generate code that compiles in one context but not another.

**Q3: Pattern assertion — `assert_matches` (4-1 for fourth built-in)**

- **Systems:** Option A. The `match + assert(false)` pattern produces "assertion failed: false at line 43" — zero information about the actual variant. `assert_matches` captures the actual discriminant and Display representation. Binding extraction (C) is over-engineered for v1.
- **Web/Scripting:** Option A. The match-assert pattern is an embarrassing DX failure. `assert_matches` is standard in Rust, Jest, pytest. Keep it simple — no binding support.
- **PLT:** Option A. Principled sugar for `match e { p => (), _ => panic(...) }`. Well-typed when `e: T` and `p` is a refutable pattern over `T`. Must be a syntactic form (second arg is a pattern, not an expression). Binding support (C) deferred to a future `let_assert`.
- **DevOps:** Option A. Compiler has pattern structure at compile time for better failure messages. JSON can include `"expected_pattern"` and `"actual"` as structured fields.
- **AI/ML:** Option B. Training data is thin (Rust nightly-only). Second argument being a *pattern* not an *expression* is exactly the kind of distinction LLMs get wrong. `match` + `panic()` is reliably generated from existing training data. *(dissent)*

**Q4: Assertion failure output format (4-1 for expression introspection)**

- **Systems:** Option C. Compiler already has the full AST. Decomposing `assert(a > b)` into sub-expression values costs nothing at compile time, only emits extra code on the cold failure path. Option B's "expected/actual" labels are misleading — which argument is "expected"? Introspection bounded to one level of sub-expressions. For `assert_eq`, preserve left/right format.
- **Web/Scripting:** Option C. Power Assert is the single biggest testing DX win a language can ship. Groovy and Elixir adopted it. Since assertions are compiler intrinsics, the compiler *has* the AST and *can* decompose sub-expressions. Start with single-level decomposition.
- **PLT:** Option A. "Expected/actual" (B) imposes argument-order convention. Left/right is structurally honest — reports what the arguments are without semantic interpretation. Power assert (C) requires ad-hoc compiler decomposition with evaluation-order concerns. Can be added later as optional enhancement. *(dissent)*
- **DevOps:** Option C. Power assert produces the most actionable diagnostics. CI engineers diagnose from JSON: `"introspection": {"account.balance": 450, "minimum": 500}`. "Expected/actual" is misleading because users put expected on either side. For `assert_eq`, keep left/right labels; introspection applies to `assert()` booleans.
- **AI/ML:** Option C. Sub-expression values let the LLM map values back to variable names instantly in the fix loop. "Expected/actual" has a well-known argument-order swap problem (~30-40% of the time). Power Assert eliminates ordering conventions entirely.

