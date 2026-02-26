[< All Decisions](../DECISIONS.md)

# Non-Local Mutable State — Design Rationale

### Round 1: Panel Deliberation (5 experts)

Five panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML) voted independently on 3 questions. The question arose from a real bug: the Pact compiler's `skip_newlines()` mutates module-level `pos` and `pending_comments` without declaring any effect — it looks pure but isn't. Speculative lookahead called it, collected comments as a side effect, then backtracked `pos` without undoing the comment collection. This caused three separate bugs. The broader question: should mutation of state outside the scope where it was created require tracking?

**Four options considered:**
- **A: Track module-level `let mut` mutation** — targeted, zero runtime cost
- **B: Track ALL non-local mutation** — sound but approaches borrow-checker territory
- **C: Compiler warning** — lint, not enforced
- **D: No change** — rely on convention

**Q1: Should module-level `let mut` mutation be tracked? (5-0 for Yes)**

- **Systems:** Zero runtime cost. Module globals are just C globals; tracking changes nothing in codegen. Functions that don't touch globals can be freely reordered and memoized by the compiler.
- **Web/Scripting:** Yes, reluctantly. It's one more thing to learn, but JS/Python devs understand the concept of global vs local. The 90% case is functions that DON'T touch globals, so most functions are unaffected.
- **PLT:** This is not optional — the purity guarantee is currently **unsound**. A function with no `!` can observe different results depending on call order — the textbook definition of an effectful function. Tracking restores referential transparency for non-mutating functions.
- **DevOps:** Diagnostics are the win: "skip_newlines writes {pos, pending_comments}" tells you exactly what a function touches. LSP can show this on hover. The diagnostic surface is excellent.
- **AI/ML:** This is the highest-value change for AI. An LLM reading a function can now know which globals it touches. The compiler catching AI mistakes at this level is exactly what an AI-first language should do.

**Q2: Should mutation of GC-aliased collections (List/Map/Set) received as arguments be tracked? (5-0 for No — defer to v2)**

- **Systems:** This is Rust's borrow checker repackaged. Tracking `.push()` on a received List means tracking every method call on every GC'd object. Pact deliberately chose GC to avoid this complexity.
- **Web/Scripting:** Hard no. If `.push()` on a list requires annotation, every web dev's first Pact program will be 50% annotations. Collections should just work.
- **PLT:** In principle, mutating a GC-aliased collection violates referential transparency. In practice, Pact chose GC over ownership (§5.1). Defer to v2 where escape analysis could make this targeted.
- **DevOps:** Overwhelming noise. Signal-to-noise ratio collapses. Keep tracking meaningful — globals are a clear boundary, parameter mutation is not.
- **AI/ML:** Collection mutation is too granular for LLMs. Module globals are a crisp, binary check the LLM can learn from one example.

**Q3: Should closure mutation of captured `let mut` be tracked? (5-0 for No)**

- **Systems:** Closures are syntactic sugar for a struct with captured fields. The mutation is contained within the enclosing function's stack frame. No action-at-a-distance.
- **Web/Scripting:** Closures mutating captures is the single most natural pattern in JS/TS/Python. The mutation is visible in the same function body.
- **PLT:** Closures are lexically scoped. The mutation is syntactically visible within the enclosing function. No additional tracking needed for soundness.
- **DevOps:** No diagnostic benefit. Closures are tooling-transparent — the LSP shows them inline with the enclosing scope.
- **AI/ML:** Closures with captured mutable state are a high-frequency pattern in training data. LLMs understand this pattern.

### Round 2: Refinement (PLT, Systems, AI/ML — 3-0)

Round 1 established that module-level mutation must be tracked, but left open the mechanism. The initial proposal was a built-in `! State` effect. Round 2 considered two approaches:

- **A: `! State` effect** — boolean annotation, must propagate through callers, sealed (no handlers)
- **B: Compiler write-set inference** — automatic analysis, binding-parameterized (knows WHICH bindings), no signature annotations

**Decision: Compiler write-set inference (3-0 for B)**

- **PLT:** `! State` is a boolean — it tells you a function touches globals but not WHICH ones. The three parser bugs were caused by incomplete save/restore of specific bindings. Write-set inference tracks `{pos, pending_comments}` per function, which is the actual information needed for diagnostics. Additionally, making this a compiler analysis rather than an effect keeps the effect system clean — effects are for cross-module capabilities, not intra-module implementation details.
- **Systems:** Write-set inference is zero-annotation. The parser has ~80 functions touching module globals. Adding `! State` to 80 functions plus propagating through all callers adds ceremony without additional information — you already know it's a parser, of course it touches parser state. The write set (`{pos, pending_comments, ...}`) is the useful information, and it's inferred automatically.
- **AI/ML:** Against all 5 AI-first criteria: (1) **Learnability** — `! State` is novel; no mainstream language has it. Write-set inference is invisible, nothing to learn. (2) **Consistency** — `! State` would be the only effect that's sealed, has no handler, and tracks reads. Special cases hurt generability. (3) **Generability** — LLMs would over-annotate (adding `! State` where not needed) or under-annotate (missing it in callers). Inference eliminates this failure mode. (4) **Debuggability** — Write sets in diagnostics (`writes {pos, pending_comments}`) are more actionable than boolean `! State`. (5) **Token efficiency** — zero tokens vs `! State` on every mutating function.

**Key design decisions from Round 2:**

| Decision | Outcome | Vote |
|----------|---------|------|
| Writes only (reads are free) | Yes — reading mutable state doesn't corrupt it | 3-0 |
| Transitive within module | Yes — if `a()` calls `b()` which writes `pos`, `a`'s set includes `pos` | 3-0 |
| Cross-module: opaque | Yes — imported function calls are opaque, no cross-module propagation | 3-0 |
| Cross-module statefulness | Use user-defined effects (§4.12) if module wants to expose state changes | 3-0 |
| Not an effect | Yes — compiler analysis like type inference, not a declared effect | 3-0 |
| Remove `effect State` from hierarchy | Yes — no longer a built-in effect | 3-0 |

