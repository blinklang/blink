[< All Decisions](../DECISIONS.md)

# StringBuilder — Design Rationale

### Panel Deliberation

Five panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML) voted independently on 3 questions. Each expert ran as a separate agent and returned votes without seeing other experts' reasoning.

**Context:** The spec deferred `StrBuf` to v1.1, but the self-hosting compiler hits O(N²) string building in the lexer (char-by-char concat) and formatter (result string concat). Two bugs are blocked on this decision. The question: what should the efficient string building API look like?

**Q1: API design — simple struct (A), Writable trait + struct (B), optimize List[Str].join (C), or struct with capacity hints (D)? (3-1-1 for D)**

- **Systems:** D. `with_capacity` is the difference between O(1) and O(log N) allocations when size is bounded. The lexer knows approximate token lengths. Option C's `List[Str]` has pointer-per-entry overhead and GC pressure. Option B's `Writable` vtable dispatch on inner write loops is real cost with no concrete use case beyond StringBuilder yet (YAGNI).
- **Web/Scripting:** D. Graduated complexity: beginners use `new()`, experienced devs reach for `with_capacity()`. Option C is clever but invisible — developers can't reason about when optimization kicks in. Option B front-loads trait complexity that belongs in v1.1 when IO abstractions mature.
- **PLT:** B. `Writable` is the right abstraction — files, sockets, test spies, and `StringBuilder` all share "write strings into". A single-implementor trait is a design smell. Capacity hints are orthogonal and can go on the constructor regardless. *(dissent)*
- **DevOps:** D. Capacity hints are the difference between a professional API and a toy. The compiler knows approximate buffer sizes. Error diagnostics can suggest `StringBuilder` when detecting `concat` in a loop. Option C makes LSP unable to distinguish "building a string" from "building a list."
- **AI/ML:** A. Maps directly onto dominant training signal (Java, C#, Go `strings.Builder`). Option D's capacity hints add decision fatigue with near-zero benefit in a GC language — models will cargo-cult `with_capacity(256)`. Option B adds learnability tax for an abstraction with no immediate payoff. *(dissent)*

**Q2: Tier 1 or Tier 2? (5-0 for Tier 1)**

- **Systems:** Tier 1, NOT prelude. Ship with compiler since the compiler itself needs it. But don't pollute prelude — callers who need it import explicitly.
- **Web/Scripting:** Tier 1, NOT prelude. String building is day-one stuff, can't send devs to a package registry. But `import std.str.{StringBuilder}` is the right nudge to keep default namespace clean.
- **PLT:** Tier 1. The compiler hits O(N²) now — that's a self-hosting correctness hazard. Not hypothetical.
- **DevOps:** Tier 1, IN prelude. If `List` is in the prelude, this should be too. Half of devs won't know it exists behind an import and will write O(N²).
- **AI/ML:** Tier 1. The reference implementation (compiler) using bad patterns is a training data problem.

*Sub-question: prelude or import? 3-2 for import (Sys/Web/PLT for import; DevOps for prelude; AI unspecified).*

**Q3: Compiler optimization of `write()` with interpolated strings? (4-1 for yes)**

- **Systems:** No. Semantics of `write()` would depend on whether the argument is a literal interpolation or a variable — invisible to the reader. Unpredictable codegen. Add `write_many()` if you want multi-segment writes. *(dissent)*
- **Web/Scripting:** Yes, but limited to direct `sb.write(interpolated_string)` calls. This is the hot path in lexers and formatters. Document it explicitly.
- **PLT:** Yes, as a compiler lowering, not a trait method. Must NOT leak into the trait surface (no `write_interpolated`). Purely a codegen concern, transparent to the trait.
- **DevOps:** Yes. Without this, every `sb.write("{x}: {y}")` silently allocates a temporary Str, defeating the purpose. Keeps API surface clean — one `write()` method.
- **AI/ML:** Yes. Zero-cost abstraction that eliminates the most common footgun. Keeps API minimal.

### Notable Cross-Cutting Concerns

- **AI/ML naming concern:** `write` may confuse LLMs with IO `write` effects. `append` was suggested as alternative. Panel noted the concern but stayed with `write` — it's the dominant verb in Java/C#/Go StringBuilder APIs.
- **Systems aliasing concern:** `to_str()` must copy the buffer. If `to_str()` were zero-copy and `clear()` reused the backing allocation, prior `Str` values would be corrupted. Spec explicitly states `to_str()` always copies.
- **PLT trait concern:** Pact requires all methods on traits. `StringBuildOps` is a compiler-known trait (like `StrOps` for `Str`). `Writable` trait deferred to v1.1 when IO write abstractions mature.
