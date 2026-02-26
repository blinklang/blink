[< All Decisions](../DECISIONS.md)

# Display Format Protocol — Design Rationale

### Panel Deliberation

Five panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML) voted independently on 3 questions resolving the Display trait format protocol gap (GAPS.md Tier 2). All votes unanimous.

**Q1: Display requirement for interpolation (5-0 for strict compile error)**

- **Systems:** Strict. `{expr}` is a trait call site — if the type doesn't impl the trait, it's a type error. Period. Auto-synthesis would make Display meaningless as a trait; you'd never know if a type's string representation is intentional or compiler-generated garbage. Built-in types get compiler-provided impls, same as `Eq` for `Int`.
- **Web/Scripting:** Strict. JavaScript's `toString()` auto-synthesis is a notorious source of `"[object Object]"` bugs. Requiring explicit Display means every type that appears in a string was consciously designed for it. `@derive(Display)` is one line — the cost of explicitness is negligible.
- **PLT:** Strict. Display is a semantic contract: "this type has a meaningful user-facing string representation." Auto-synthesis violates the contract — a compiler-generated string for an arbitrary type has no semantic content. Debug exists for the "just show me something" use case. Separate traits, separate purposes.
- **DevOps:** Strict. The error message (`type X does not implement Display`) is immediately actionable. The fix is one annotation. Auto-synthesis would mean Display output is never trustworthy in logs or user-facing strings — you'd always wonder if it's intentional or default garbage.
- **AI/ML:** Strict. LLMs trained on Rust know: missing trait → add derive or impl. This is a well-learned pattern. Auto-synthesis removes a signal the model uses to decide whether a type is "displayable." Explicit is better for code generation reliability.

**Q2: Compiler desugaring mechanism (5-0 for two-phase check+optimize)**

- **Systems:** Two-phase. The type checker treats `{expr}` as requiring `T: Display` — standard trait bound checking. But codegen doesn't need to emit a function call for `{42}` — `%d` in snprintf is correct and faster. The semantic guarantee (Display exists) is orthogonal to the codegen strategy (inline vs call). Rust does this exact optimization for built-in Display impls.
- **Web/Scripting:** Two-phase. Developers don't care about the desugaring mechanism — they care that `{42}` works and `{MyType}` requires Display. Two-phase gives both: clean semantics for the programmer, fast codegen for the runtime. Full trait dispatch for `{42}` would be silly overhead that the programmer can't even observe.
- **PLT:** Two-phase. Formally, `"{expr}"` desugars to `Display.display(expr)` concatenated into a string. The optimizer is free to replace `Display.display(42: Int)` with its known definition `snprintf(buf, ..., "%d", 42)` — this is standard inlining of known implementations. No semantic difference. The two-phase framing is just saying "the compiler is allowed to optimize known impls."
- **DevOps:** Two-phase. The current compiler already does this — snprintf with format specifiers for built-ins. Formalizing it means the spec matches the implementation. Full trait dispatch would require changing the existing working codegen for no benefit. Two-phase also means the LSP can show "Display.display() called here" in hovers without the runtime paying for virtual dispatch.
- **AI/ML:** Two-phase. The semantic model is simple for LLMs: "interpolation calls Display." The optimization is invisible to the programmer. LLMs generating Pact don't need to know about the codegen phase — they just need to know Display is required. Clean separation of concerns.

**Q3: Query[C] context interaction (5-0 for Display is Str-context only)**

- **Systems:** Str-context only. Query[C] parameterization passes raw typed values to the database driver — `Int` stays `Int`, not `"42"`. Calling Display first would serialize to Str, then the DB driver would have to parse it back. That's a round-trip through string representation that loses type information and adds a potential injection vector if the Display impl produces unexpected characters.
- **Web/Scripting:** Str-context only. This was already decided when we voted 3-0 for Query[C] phantom types. The entire point is that `{id}` in `Query[DB]` becomes a typed parameter `$1` with value `42: Int`, not a string `"42"`. Display-then-parameterize defeats the purpose. The compiler knows the context (Str vs Query) from the type annotation.
- **PLT:** Str-context only. Display's return type is `Str`. Query parameterization requires typed values. These are fundamentally different operations — one is presentation (type → string), the other is data binding (type → parameter slot). Conflating them is a type error in the formal sense. The context type (Str vs Query[C]) selects the interpolation semantics.
- **DevOps:** Str-context only. Database parameterized queries expect typed parameters for good reason — the driver can validate types, use binary protocols, prevent injection. If we Display-ify everything first, we lose all of that. The compiler already knows whether it's building a Str or a Query[C] from the type context. Two codepaths, clearly motivated.
- **AI/ML:** Str-context only. LLMs need one clear rule: "in Str context, Display; in Query context, parameterize." Two distinct behaviors selected by type context. If Display were invoked in both, models would be confused about when injection safety applies. The type-based dispatch is the simplest mental model.

