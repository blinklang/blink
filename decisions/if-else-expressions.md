[< All Decisions](../DECISIONS.md)

# If/Else as Expressions — Design Rationale

### Panel Deliberation

Five panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML) voted independently on 4 questions. All votes unanimous.

**Q1: Expression-based if/else (5-0 for "always expression")**

- **Systems:** Maps to SSA phi nodes cleanly. Eliminates uninitialized-variable bugs from declare-then-assign. One construct, one lowering strategy.
- **Web/Scripting:** Eliminates need for a separate ternary operator (Principle 2). TS devs already fake this with ternaries — expression if/else is cleaner.
- **PLT:** Only clean option type-theoretically. Dual-mode would require defining `if` twice in typing rules. All ML-family languages get this right.
- **DevOps:** One rule for formatter/linter/LSP. Dual mode means context-dependent formatting and ambiguous diagnostics.
- **AI/ML:** Universal rule = more reliable LLM generation. Dual system forces model to track whether if/else appears in value-consuming position — subtle contextual reasoning that causes generation errors.

**Q2: Else mandatory when value used (5-0)**

- **Systems:** Type unification is compile-time only, zero runtime cost. Option wrapping creates implicit type complexity and hidden allocations.
- **Web/Scripting:** Forgetting else is a constant JS/TS bug source (implicit `undefined`). Compiler-enforced completeness when value matters.
- **PLT:** Conditional without else is a partial function. Implicit `Option[T]` wrapping adds monadic lifting into core syntax unnecessarily.
- **DevOps:** Trivial linter rule: value-producing if must have else. Catches real bugs mechanically. Auto-Option wrapping creates diagnostic ambiguity.
- **AI/ML:** When LLM produces `let x = if cond { 5 }`, it almost certainly forgot else — that's a bug, not intentional Option wrapping.

**Q3: No `if let` for v1 (5-0 reject)**

- **Systems:** Sugar over two-arm match — backend doesn't care. Smaller surface area = better for compiler simplicity.
- **Web/Scripting:** Two ways to pattern match = inconsistency in large codebases. If single-arm match feels verbose, that's tooling, not language.
- **PLT:** Pattern matching should live in one syntactic construct for exhaustiveness checking and type narrowing.
- **DevOps:** Every new syntax form multiplies formatter edge cases, LSP completions, and linter patterns.
- **AI/ML:** `if let` is a constant source of LLM syntax errors in Rust (forgetting `=`, wrong destructuring). One mechanism = more training signal per pattern.

**Q4: Parentheses forbidden, not optional (5-0)**

- **Systems:** Fewer grammar productions = simpler parsing, fewer ambiguities, faster parse times.
- **Web/Scripting:** Forbidding (not optional) prevents formatting inconsistency — optional means half the team uses them.
- **PLT:** Condition unambiguously delimited by `if` and `{`. Optional parens = two parse trees for same program.
- **DevOps:** Optional parens directly undermines `pact fmt` canonical formatting — formatter must either normalize (diff churn) or preserve (inconsistency).
- **AI/ML:** Models trained on mixed corpora randomly include/omit optional parens. Forbidding eliminates a decision point = one fewer error.

