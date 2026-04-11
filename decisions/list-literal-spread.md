[< All Decisions](../DECISIONS.md)

# List Literal Spread — Design Rationale

### Problem Statement

Blink has no `.clone()` on `List[T]` and no ergonomic way to copy or concatenate lists. The workaround is `list.slice(0, list.len())` for copying and `.concat()` for two-list joining — but neither supports interleaving elements: `[..a, middle, ..b]` has no equivalent.

With `..` already established as the general spread/rest operator (5-0 vote) and list pattern rest (`[first, ..]`) already in v1, the construction dual is the obvious missing piece.

### Panel Deliberation

**Q1: Include list literal spread in v1? (5-0 for Yes)**

| Expert | Vote | Reasoning |
|--------|------|-----------|
| Systems | A | No `.clone()`, no interleave primitive. O(n) cost is obvious and expected. Pattern/construction duality is sound. |
| Web/Scripting | A | `slice(0, len())` workaround is embarrassing for a modern language. Symmetry with pattern rest is the decisive DX argument. |
| PLT | A | Multi-source any-position is principled for lists — no key conflicts (unlike struct fields). Deferring creates a half-finished feature asymmetry. |
| DevOps | A | Essential for day-to-day scripting/tooling code. Type errors on spread source should point to the specific `..expr` site. |
| AI/ML | A | JS `[...arr1, ...arr2]` is deeply embedded in LLM training data. LLMs will generate this regardless — better to support it than produce confusing errors. |

**Result: 5-0 unanimous**

### Semantics

- `..expr` inside `[]` expands all elements from `expr` into the list being constructed
- Source must be `List[T]` with same element type (compile-time type check)
- Multiple `..source` spreads allowed per literal (unlike struct: one source only)
- Any position allowed (unlike struct: last only) — lists have no key conflicts
- Left-to-right evaluation, eager copy (new allocation, not a lazy view)
- Runtime cost: O(n) per spread source

### Key Difference from Struct Spread

| Property | Struct spread | List spread |
|----------|--------------|-------------|
| Sources per literal | One | Multiple |
| Position | Last only | Any |
| Runtime cost | Zero (compile-time desugar) | O(n) copy |
| Reason for difference | Key conflicts (field shadowing) | No keys, ordered sequence |
