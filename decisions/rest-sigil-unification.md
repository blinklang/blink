[< All Decisions](../DECISIONS.md)

# Rest Sigil Unification — Design Rationale

### Problem Statement

Blink used two different sigils for the same concept ("ignore/match remaining elements"):
- `..` in struct patterns: `User { name, .. }`
- `...` in list patterns: `[first, ...]`

This inconsistency is a learning-curve friction point and complicates the grammar. With struct copy-update syntax (`..source`) being added, having a unified rest sigil makes the overall `..` story coherent.

### Cross-Language Survey

- **Rust**: `..` for struct rest, `..` for slice rest — unified
- **JavaScript**: `...` for both spread and rest — unified (three dots)
- **Python**: `*rest` for sequence unpacking (binding required)
- **Scala**: `_*` for sequence wildcard
- **Haskell/OCaml**: no rest sigil, exhaustive patterns only

### Panel Deliberation

Five panelists independently proposed options, then voted.

**Options:**
- **A**: Unified `..` — drop `...`, use `..` for both struct and list rest
- **B**: Status quo — keep `..` for structs, `...` for lists
- **C**: Novel `_..` — composite sigil, frees bare `..` for ranges/copy-update only
- **D**: `*` — Kleene star, frees `..` entirely (added mid-deliberation by user)

| Expert | Vote | Reasoning |
|--------|------|-----------|
| Systems | A | Fewer sigils with context-driven disambiguation is cleaner. Parser already handles `..` in multiple contexts. `..` vs `...` carries no semantic weight. |
| Web/Scripting | A | One sigil for one concept. `..` vs `...` trips up beginners. `..` as "and the rest" reads intuitively. |
| PLT | D *(dissent)* | `*` has Kleene star semantics (zero-or-more) which is precisely what rest means. Achieves clean separation: `..` for ranges/copy-update, `*` for rest. No mainstream precedent for bare `*` without binding is the weakness. |
| DevOps | A | Single sigil = single code path in formatter/LSP. Eliminates "which one do I use here?" doc lookups. |
| AI/ML | A | Single sigil eliminates the `..` vs `...` off-by-one error class in LLM generation. Rust precedent is heavily represented in training data. |

**Result: A — 4-1 (PLT dissented for `*`)**

### `..` Disambiguation

After this decision plus struct copy-update, `..` has three context-dependent meanings:

| Context | Syntax | Meaning | Disambiguation |
|---------|--------|---------|----------------|
| Range | `0..100` | Exclusive range | Infix between two expressions |
| Pattern rest | `User { name, .. }`, `[first, ..]` | Ignore remaining | Trailing in pattern, no operand |
| Copy-update | `User { name: "new", ..source }` | Copy remaining from source | Trailing in literal, with operand |

These are syntactically distinct positions — the parser has no ambiguity. Human readability is addressed by context (patterns vs literals vs expressions) and syntax highlighting.

### AI-First Review

| Criterion | Pass/Fail | Notes |
|-----------|-----------|-------|
| Learnability | Pass | One sigil, one concept. Context distinguishes |
| Consistency | Pass | Unifies struct and list rest under single `..` |
| Generability | Pass | Rust precedent. Eliminates `..` vs `...` error class |
| Debuggability | Pass | Error messages specify which `..` context applies |
| Token efficiency | Pass | `..` is 2 chars vs `...` at 3 (minor) |

0 criteria fail.
