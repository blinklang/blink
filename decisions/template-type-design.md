[< All Decisions](../DECISIONS.md)

# Template Type Design — Design Rationale

### Problem Statement

The spec (§3b.5) defines `Query[C]` as a phantom-typed parameterized query type where the compiler auto-extracts `{expr}` interpolations as bound parameters. During implementation, a fundamental design flaw was discovered: the compiler generates `$1, $2` placeholders (PostgreSQL syntax), baking SQL dialect knowledge into a language primitive. User-authored effect handlers cannot participate in parameterization because they receive an opaque `const char*` at the C level with no access to the decomposed parts.

Cross-language research confirmed a universal pattern: Python 3.14 `Template` (PEP 750), C# `FormattableString`, and JS tagged templates all have the *language* decompose the interpolated string into literal parts + values, and the *library/handler* reassemble with its own dialect-specific syntax. This deliberation refines the existing `Query[C]` decision to follow this pattern.

### Panel Deliberation

Five panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML) voted independently on 3 questions. Refines prior decisions: [OPEN_QUESTIONS.md 3.1](../OPEN_QUESTIONS.md) (Query[C] 3-0) and [OPEN_QUESTIONS.md 3.2](../OPEN_QUESTIONS.md) (Raw(expr) 2-1).

---

**Q1: Naming — `Query[C]` vs `Template` vs `Interpolation` vs other? (3-1-1 for Template)**

- **Systems:** `Template`. `Query[C]` encodes a domain assumption into a language primitive — a layering violation. The name should reflect the structure, not the use case. Python 3.14, C#, and JS all converged on this after similar debates.
- **Web:** `Template`. Every JS developer knows tagged templates. Every Python developer will recognize `Template` from PEP 750. `Query[C]` will confuse the first developer who uses it for HTML or logging.
- **PLT:** *(dissent)* `Interpolation`. Names the compiler's introduction form, not the use-site context. `Template` drags in template-engine mental models. Will accept `Template` if overruled.
- **DevOps:** `Template`. `error[E0310]: expected Template[DB], found Str` is immediately legible. `Query[Shell]` is not self-documenting in error messages.
- **AI/ML:** *(dissent)* Keep `Query[C]`. "Query" carries parameterization semantics in virtually every major framework in training data. `Template` has near-zero training corpus coverage for this usage.

---

**Q2: Internal structure — compiler rewrites to `$1/$2` vs decomposed `{ parts, values }` vs hybrid? (3-2 for decomposed)**

- **Systems:** Decomposed. The only option that produces predictable, dialect-free C output. Option A is a layering violation. Option C still ships dialect logic in disguise via helper methods.
- **Web:** *(dissent)* Hybrid. Decomposed is correct but brutal for the 90% case. A `to_parameterized(style)` helper covers the happy path without forcing every handler author to manually zip parts and values.
- **PLT:** Decomposed. The compiler's job is to preserve structure; the handler's job is to interpret it. This is how Koka-style effect handlers should work — the handler owns the semantics, the language owns the decomposition.
- **DevOps:** *(dissent)* Hybrid. Decomposed `parts`/`values` is what makes static analysis tractable, but without a helper, every handler author reinvents the wheel.
- **AI/ML:** Decomposed. Matches JS tagged template literals (`strings[]`, `values[]`), which have massive training data coverage. Handler authors can emit any format (`?`, `:name`, `%s`).

---

**Q3: Type identity — phantom-only vs single structural vs structural+phantom? (4-1 for structural+phantom)**

- **Systems:** Structural+phantom (`Template[C]`). The phantom is load-bearing for safety: without it, a `Template` built for Shell is silently passable to a SQL handler. Phantom is erased at codegen — zero runtime overhead.
- **Web:** Structural+phantom. Phantom-only means handlers can't introspect parts. Pure structural means no cross-context protection. Need both. This is exactly the TypeScript branded types model.
- **PLT:** Structural+phantom. The coercion rule `InterpString → Template[C]` is sound because the compiler synthesizes the phantom at the interpolation site from the surrounding effect context. Variance must be invariant in `C`.
- **DevOps:** Structural+phantom. The phantom parameter is load-bearing for diagnostics: `expected Template[DB], found Template[Shell]` is a clear, actionable error.
- **AI/ML:** *(dissent)* Single structural type. Phantom types are an invisible abstraction LLMs frequently mishandle. Prefers enforcement via trait bounds or effect constraints. Acknowledges this trades static safety for learnability.

---

### Key Design Points

> **Amended by [Template Surface](template-surface.md).** The panel quotes above are unchanged. The points below state the current design: `Template[C]` is opaque, a handler reads it through `parts()` and `values()`, the values are the closed enum `TemplateValue`, and `C` comes from the expected parameter type.

**Representation (opaque):** `Template[C]` has no fields and no constructor. Only the literal coercion and `Raw` folding build one. It is immutable, and each observer returns a fresh list:
```blink
// t.parts()  -> List[Str]            literal segments
// t.values() -> List[TemplateValue]  interpolated values
// t.parts().len() == t.values().len() + 1
enum TemplateValue { Int(Int), Float(Float), Bool(Bool), Str(Str), Null }
```

**Compiler coercion:** When an interpolated string literal appears where `Template[C]` is expected, the compiler decomposes it into parts and values instead of concatenating. The phantom `C` comes from the expected parameter type (e.g., `db.query()` expects `Template[DB]`), never from the effects of the enclosing signature.

**Handler reassembly:** Each handler decides its own parameterization syntax:
```blink
// PostgreSQL handler uses $1, $2
// MySQL handler uses ?
// Shell handler uses quoting
// HTML handler uses entity escaping
```

**Unchanged developer syntax:** `db.query("SELECT * FROM t WHERE id = {id}")` — identical to before. The magic is in the type of `db.query`'s parameter.

**`Raw(expr)` unchanged:** Wrapping an interpolation in `Raw()` folds the value into the literal parts (concatenated, not parameterized). Emits W0310 warning. This is unchanged from the prior decision.

**Open items for implementation:**
- Value representation: typed union vs `void*`+tag vs trait-bound dispatch
- `parts.len() == values.len() + 1` invariant must be explicit in spec
- Phantom inference at ambiguous sites needs fallback error
