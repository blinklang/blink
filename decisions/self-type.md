[< All Decisions](../DECISIONS.md)

# `Self` Type — Design Rationale

### Panel Deliberation

Five panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML) voted independently on 4 questions.

**Q1: Where is `Self` valid (5-0 for trait decls + impl blocks only)**

- **Systems:** `Self` is resolved at monomorphization — it's a placeholder the compiler substitutes. Only meaningful where there's a "current implementing type." Free functions have no implementing type.
- **Web/Scripting:** TS `this` type works exactly this way — valid in class/interface bodies, nowhere else. Familiar rule.
- **PLT:** `Self` is a type variable bound by the trait/impl quantifier. Outside that scope, it's unbound — standard scoping rules.
- **DevOps:** LSP go-to-definition on `Self` jumps to the impl header's type. If `Self` appeared in free functions, where does it point? Nowhere useful.
- **AI/ML:** Clear binary rule: inside trait/impl = valid, outside = error. LLMs handle binary rules well.

**Q2: `self` keyword sugar (5-0 for sugar, literal `self` required for methods)**

- **Systems:** `self: Self` is the mechanical truth. Sugar saves tokens. Requiring literal `self` for dot-call dispatch means the compiler checks one name, not arbitrary parameter names.
- **Web/Scripting:** Python's explicit `self` parameter is beloved for clarity. Sugar makes it concise without hiding it. `this: Self` not enabling `.method()` prevents confusion.
- **PLT:** Method dispatch keyed on a syntactic marker (`self`) rather than positional convention avoids the fragile "first parameter is special" rule that Python has.
- **DevOps:** Formatter and LSP can reliably identify methods (has `self`) vs associated functions (no `self`). No heuristics needed.
- **AI/ML:** `self` as first param = method is the dominant pattern in training data. Enforcing it eliminates a class of generation errors where models name it `this` or `s`.

**Q3: `Self` in construction position (4-1 for type-position only)**

- **Systems:** Type-position only. `Self { ... }` in a default method doesn't know field names — traits don't see struct internals. Would require trait-level field visibility, massive complexity.
- **Web/Scripting:** Allow `Self { ... }` construction. Factory methods (`fn default() -> Self { Self { x: 0 } }`) are common. Requiring the concrete name defeats the purpose of writing generic defaults. *(dissent)*
- **PLT:** Type-position only. `Self` as constructor in a trait default method would require the trait to know the representation of all implementing types — breaks parametricity.
- **DevOps:** Type-position only. Error message is clear and actionable: "use the concrete type name." LSP can auto-fix.
- **AI/ML:** Type-position only. `Self` as constructor is rare in training data (Rust allows it but it's uncommon in default methods). Simpler rule = fewer generation errors.

**Q4: `self` passing semantics (5-0 for always by-value)**

- **Systems:** GC handles memory. No ownership distinction means no `&self`/`&mut self`. One form, zero decisions. The runtime manages sharing.
- **Web/Scripting:** By-value is what every GC language does. JS, Python, Java, Go — `self` is a reference under the hood but passed "by value" at the language level. Natural.
- **PLT:** Pact has no reference types. The type system has no `&T` or `&mut T`. Introducing by-reference `self` would require adding reference types to the language — rejected design direction.
- **DevOps:** One calling convention. No "should this be `&self` or `&mut self`?" decisions at every method. Eliminates entire category of Rust-style borrow checker diagnostics.
- **AI/ML:** Rust's `&self`/`&mut self`/`self` triple is the #1 source of trait impl errors in LLM-generated code. Single form eliminates the decision entirely.

