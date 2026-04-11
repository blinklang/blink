[< All Decisions](../DECISIONS.md)

# Struct Copy-Update Syntax — Design Rationale

### Problem Statement

Blink structs are intentionally immutable — no field mutation. To "update" a struct, you must reconstruct all fields manually:

```blink
let updated = Account { id: acct.id, owner: acct.owner, balance: acct.balance + amount }
```

This scales poorly. The self-hosting compiler's `Node` struct has 51 fields — updating one field requires spelling out all 51. This blocks the parser parallel-array migration (`0jbhdq`) and makes struct-heavy code fragile: adding a field to a type breaks every construction site.

### Cross-Language Survey

- **Rust**: `Struct { field: val, ..other }` — spread suffix, same type required, last position
- **OCaml**: `{ record with field = val }` — `with` keyword (taken in Blink for resource blocks)
- **Elm**: `{ record | field = val }` — pipe separator inside braces
- **JavaScript**: `{ ...obj, field: val }` — spread operator, any position, no type checking
- **Kotlin**: `data class` + `.copy(field = val)` — method-based, compiler-generated

### Panel Deliberation

Five panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML) independently proposed options, then voted.

**Q1: Struct copy-update syntax (4-1 for Option A)**

**Option A: `..source` suffix in struct literal**
```blink
let updated = Account { balance: acct.balance + amount, ..acct }
```

**Option B: `copy` keyword expression**
```blink
let updated = copy acct { balance: acct.balance + amount }
```

**Option C: `update...with` keyword expression**
```blink
let updated = update acct with { balance: acct.balance + amount }
```

| Expert | Vote | Reasoning |
|--------|------|-----------|
| Systems | A | Zero-cost desugaring to flat field list in C. No new keywords — keywords have grammar-wide blast radius (`copy` and `update` are common identifiers). `..` dual of pattern rest is structural symmetry, not coincidence. |
| Web/Scripting | A | Recognizable from Rust/JS. Symmetric with existing pattern `..` — same sigil, opposite direction. Zero new vocabulary. Teachable in one sentence. |
| PLT | A | Pattern/construction duality is principled: `..` means "fields I didn't name" in both directions. Sound typing rule — source must be same nominal type. Desugars before type inference. |
| DevOps | A | Single sigil means one formatter/LSP code path. Zero keyword-colorization edge cases. Error attribution is precise. Originally proposed Option C but switched — `with` reuse as contextual keyword creates diagnostic ambiguity. |
| AI/ML | B *(dissent)* | `copy` names the operation at first token — no sigil overloading. LLMs trained on Rust may place `..source` in wrong position or confuse with range `..`. Counter: `..source` in struct literal is a field expression LLMs handle reliably from Rust precedent. |

**Result: A — 4-1 (AI/ML dissented)**

### Rules

1. `source` must be the same nominal type as the struct being constructed
2. `..source` must appear last in the field list (hard parse rule, not style)
3. At most one `..source` per literal
4. Explicit fields shadow source fields
5. Desugars to field-by-field copy at typecheck — zero codegen impact
6. Source values win over field defaults for non-explicit fields

### AI-First Review

| Criterion | Pass/Fail | Notes |
|-----------|-----------|-------|
| Learnability | Pass | `..source` is dual of pattern `..`. One concept, two directions |
| Consistency | Pass | Reuses existing `..` sigil. No new keywords or grammar categories |
| Generability | Pass | Rust precedent in training data. Position error caught by parser |
| Debuggability | Pass | Type mismatch and position errors are clear and actionable |
| Token efficiency | Pass | 51-field Node update: ~15 tokens vs ~300 |

0 criteria fail — no reconsideration needed.
