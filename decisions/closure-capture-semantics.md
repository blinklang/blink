[< All Decisions](../DECISIONS.md)

# Closure Capture Semantics — Design Rationale

### Panel Deliberation

Five panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML) voted independently on 3 questions.

**Q1: Capture mode — shared reference vs by-value vs inferred (3-2 for shared reference)**

- **Systems:** By-value (Option A). In a GC'd language, "by value" for heap objects means copying a pointer — 8 bytes, one register copy. Closure struct with flat fields, populated by copying locals. No indirection cells, no boxing. `let mut` snapshotted at closure creation. *(dissent)*
- **Web/Scripting:** By-value (Option A). Snapshotting mutable bindings is far more predictable than sharing them. Python's late-binding closure semantics are the single most common closure footgun. *(dissent)*
- **PLT:** Shared reference (Option B). In a GC'd language with no reference types, all bindings are GC-managed handles. Snapshotting `let mut` is a semantic trap — `count += 1` inside a closure silently mutates a copy, producing wrong results with no compiler error. Every GC'd language (OCaml, Koka, JS, Python, C#) uses shared-reference captures. For immutable bindings, shared-ref is observationally equivalent to by-value copy. The capture mode is not part of the function type.
- **DevOps:** Inferred (Option C). Immutable by-value, mutable by-ref. But acknowledged that C and B produce identical observable behavior for all cases. Critical requirement: LSP must show capture modes on hover.
- **AI/ML:** Shared reference (Option B). ~70% of closure training data (JS + Python + Go) uses shared-reference semantics. By-value silently breaks the `count += 1` mutation pattern — a silent logic bug is the worst outcome for LLM-generated code. Inferred (Option C) has zero training data for the specific inference rules; Rust's inferred capture is the #1 source of LLM errors in Rust closures.

**Q2: Explicit capture syntax (4-1 for no explicit syntax)**

- **Systems:** No syntax. If everything is always by-value, nothing to disambiguate. YAGNI. *(Note: voted for by-value in Q1, but no-syntax still applies under shared-ref — one mode = nothing to annotate.)*
- **Web/Scripting:** No syntax. Principle 2 — one way to do everything. GC'd languages don't need capture annotations.
- **PLT:** No syntax. GC eliminates the primary reason for explicit captures (Rust's `move` exists for ownership transfer; Pact has no ownership). The snapshot-via-`let` idiom covers edge cases. `move` can be added backward-compatibly in v2 if needed.
- **DevOps:** `move` keyword (Option B). Users need an escape hatch when inference is wrong. `move fn(params) { body }` forces all captures to by-value. One keyword, one behavior. `pact fmt` just puts `move` before `fn`. *(dissent)*
- **AI/ML:** No syntax. Explicit capture has ~40% LLM error rate in Rust/C++. One mode = nothing to annotate. Zero additional decision points.

**Q3: `async.spawn` mutable captures (3-2 for compile error)**

- **Systems:** Auto-copy (Option B). Falls naturally from by-value capture. `async.spawn` copies GC pointer into closure. Both tasks hold GC roots. Zero additional overhead. *(dissent)*
- **Web/Scripting:** Auto-copy (Option B). Spawned task gets own copies. No shared mutable state between tasks. Like `structuredClone` for web workers. *(dissent)*
- **PLT:** Compile error (Option A). `async.spawn` with shared mutable captures creates data races. Pact has no `Mutex`, no `Atomic`, no memory model for concurrent mutation of shared cells. Allowing this would be unsound. Immutable captures are fine — no data race potential.
- **DevOps:** Compile error (Option A). Silent correctness bugs are worst for tooling. Compile error E0650 with machine-applicable fix (snapshot via `let`, use channel, or use `Atomic[T]`). Error message should include quick-fix.
- **AI/ML:** Compile error (Option A). Data races are the #1 concurrency bug in LLM code. The compile error pushes LLMs toward the fork-join pattern (more training data, more correct). Immutable captures in spawn should be fine.

