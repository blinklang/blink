[< All Decisions](../DECISIONS.md)

# Machine Output Format — Design Rationale

### Panel Deliberation

Five panelists voted on whether Pact's machine-readable output format (§8.1) should remain JSON-only or adopt token-optimized alternatives like TOON.

**Context:** TOON (Token-Oriented Object Notation, v1.4, 2025) offers 30-60% token reduction vs JSON for LLM consumption, with 73.9% LLM parsing accuracy vs JSON's 69.7%. However, JSON has universal CI/IDE/tooling support while TOON has zero ecosystem tooling (no `jq` equivalent, no SARIF, no GitHub Actions parser).

**Q1: Primary output format (3-1-1 for JSON default + TOON flag)**

- **Systems:** Option C. JSON parsing overhead is negligible (SIMD parsers); token savings are the AI consumer's concern. `--format toon` flag is a cheap runtime branch.
- **Web/Scripting:** Option A. JSON universal, zero learning curve. Adding TOON means two paths to document/test/maintain. YAGNI. *(dissent)*
- **PLT:** Option D. Schema and encoding are separate concerns. Spec should define abstract schemas, not bind to a wire format. *(dissent)*
- **DevOps:** Option C. JSON is the only format CI/IDE actually consumes. TOON as opt-in for AI agents.
- **AI/ML:** Option C. 35-40% token savings on diagnostics. LLMs parse TOON more accurately despite less training data.

**Q2: Diagnostic-specific optimization (3-1-1 for uniform format)**

- **Systems:** Option C. Streaming (NDJSON) matches incremental compilation. *(dissent)*
- **Web/Scripting:** Option A. One format, one parser. Principle 2.
- **PLT:** Option A. Uniform treatment. Special-casing breaks compositionality.
- **DevOps:** Option A. One parser, one test suite, one integration.
- **AI/ML:** Option B. Diagnostics are the hot path; tabular TOON has highest ROI here. *(dissent)*

**Q3: Spec language (3-2 for "structured output with canonical JSON schema")**

- **Systems:** Option C. Schema is the contract, wire format is transport.
- **Web/Scripting:** Option A. Just say "JSON." Abstract language invites bikeshedding. *(dissent)*
- **PLT:** Option C. Separates type (schema) from representation (encoding).
- **DevOps:** Option A. CI authors need certainty, not abstract promises. *(dissent)*
- **AI/ML:** Option C. Schema is training signal; encoding is transport. Future-proof.

**Final decision: Deferred.** Panel voted for JSON+TOON, but the pragmatic conclusion was that JSON is required regardless for ecosystem compatibility. TOON (v1.4) is too immature — no `jq`, no SARIF, no CI tooling. The `--format` extensibility point can be added when token-optimized formats achieve tooling parity. No spec changes for v0.3.

