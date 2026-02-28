[< All Decisions](../DECISIONS.md)

# List Pattern Matching

**Status:** Resolved
**Date:** 2026-02-28
**Triggered by:** GAPS.md — "Ergonomic dispatch on variable-length ordered data"

## Context

Pattern matching handles tuples (fixed-length), enums, structs — not lists (variable-length). Surfaced from CLI subcommand dispatch on `List[Str]` command paths, but applies broadly: JSON traversal, token parsing, protocol dispatch.

## Questions & Votes

### Q1: Add list patterns to match?

`[pattern, ...]` syntax in pattern position, matching list values by length and element values.

| Expert | Vote | Reasoning |
|--------|------|-----------|
| Systems | Yes | Natural extension of tuple patterns. Lists are the universal collection |
| Web/Scripting | Yes | JS/TS destructuring proves the pattern. Essential for ergonomic code |
| PLT | Yes | Well-understood in ML family. Square brackets unambiguous in pattern position |
| DevOps | Yes | CLI dispatch is the motivating case. if/else chains are error-prone |
| AI/ML | Yes | LLMs generate list matching confidently — familiar from Python/JS/Rust |

**Result: 5-0 Yes**

### Q2: Rest patterns — bind the tail or wildcard only?

Options: (A) `[first, ...rest]` binds rest as new list (requires O(n) copy or slice type), (B) `[first, ...]` wildcard only, no binding.

| Expert | Vote | Reasoning |
|--------|------|-----------|
| Systems | B | Copy is O(n), slice type adds complexity. Use `.slice()` explicitly |
| Web/Scripting | B | Wildcard covers 90% of cases. Binding can come later with slices |
| PLT | B | Rest binding needs a slice type to be zero-cost. Defer to v2 |
| DevOps | A | Full binding is more useful. Worth the copy for ergonomics |
| AI/ML | B | Simpler mental model for LLMs. One fewer concept to learn |

**Result: 4-1 wildcard only (DevOps dissented)**

### Q3: Exhaustiveness checking?

Lists are unbounded — finite length patterns can never be exhaustive. How to enforce coverage?

| Expert | Vote | Reasoning |
|--------|------|-----------|
| All | Length-based + mandatory wildcard | Track covered lengths; require `_` or `...` catch-all arm. `[]` + `[_, ...]` IS exhaustive (covers empty + non-empty) |

**Result: 5-0 consensus**

## AI-First Review

| Criterion | Pass/Fail | Notes |
|-----------|-----------|-------|
| Learnability | Pass | Familiar from JS/Python destructuring |
| Consistency | Pass | Mirrors tuple pattern syntax with `[]` instead of `()` |
| Generability | Pass | LLMs generate list patterns confidently |
| Debuggability | Pass | Length-based errors are clear and actionable |
| Token efficiency | Pass | More concise than equivalent if/else chains |

## Decision

Add list patterns with wildcard-only rest. Length-based exhaustiveness with mandatory catch-all for unbounded lists.
