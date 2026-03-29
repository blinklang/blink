[< All Decisions](../DECISIONS.md)

# Sized Numeric Types — Design Rationale

### Panel Deliberation

Five panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML) voted independently on 5 questions.

**Q1: Role of sized integers in user-facing code (3-1-1 for first-class nominal)**

- **Systems:** First-class. U8 array is 8x denser than i64 array. FFI collapses without first-class sizing. If the language compiles to C, sized types ARE the C types.
- **Web/Scripting:** Refinement types. Python/JS devs never think about U8 vs I32. Refinement syntax is self-documenting. *(Dissent)*
- **PLT:** First-class. U8 is not "a small Int" — it has different representation (8 bits vs 64 bits). Refinement types constrain values, not representation. Conflating the two is unsound.
- **DevOps:** First-class. Nominal types give precise error messages: "expected U8, got I32". Refinement types muddy the diagnostic surface.
- **AI/ML:** FFI-only. Eight numeric types is a combinatorial disaster for generation accuracy. Fewer choices = fewer hallucinations. *(Dissent)*

**Q2: Overflow behavior (3-2 for checked default + explicit wrapping)**

- **Systems:** Checked. Wrap-always is a footgun. Panic-always rules out legitimate wrapping. `.wrapping_add()` makes intent explicit in code review. Generated C is a comparison and branch — near-zero cost.
- **Web/Scripting:** Panic always. Web devs have never seen silent overflow. Wrapping is a footgun C devs get wrong. *(Dissent — wants no escape hatch)*
- **PLT:** Checked. Overflow breaks equational reasoning. But wrapping IS correct for Z/2^n ring operations (checksums, hashing). Default-panic + opt-in-wrap is principled. Matches Rust's empirical validation.
- **DevOps:** Compile-time + panic runtime. Static detection is free DX. Runtime panic includes operand values in error message. Aligns with C's default behavior.
- **AI/ML:** Panic always. One behavior, zero decision points. `.wrapping_add()` creates a choice LLMs will get wrong. *(Dissent — wants no escape hatch)*

**Q3: Bitwise operations (4-1 for operator syntax)**

- **Systems:** Operators. `.bit_or(READ_MASK).bit_and(WRITE_MASK.bit_not())` is hostile. 50 years of established precedence rules.
- **Web/Scripting:** Operators. `&`, `|`, `^`, `<<`, `>>` are universal across Python, JS, Kotlin. Hiding them behind methods would make Blink look amateur.
- **PLT:** Operators. Bitwise ops have algebraic laws (De Morgan's, associativity). Sealed trait model already handles this. Consistent with arithmetic operators.
- **DevOps:** Operators. LSP handles type errors fine. Named methods create discoverability problems (`.bit_and()` vs `.band()` vs `.bitwise_and()`?).
- **AI/ML:** Named methods. Operator `&` creates confusion with boolean AND across languages. `.bit_and()` is unambiguous. *(Dissent)*

**Q4: Sized numeric method surface (5-0 for Standard)**

- **Systems:** Standard. .abs()/.min()/.max()/.clamp() used in every numeric algorithm. Rich set belongs in a later extension.
- **Web/Scripting:** Standard. These methods show up in every JS/Python tutorial. Expected.
- **PLT:** Standard. Clean algebraic meaning: .abs() is identity for non-negative, .min()/.max() are meet/join in total order. Don't conflate numeric math with bit intrinsics.
- **DevOps:** Standard. Right autocomplete list size. Too minimal = missing functionality. Too rich = noise.
- **AI/ML:** Standard. .abs()/.max() are in essentially every language's training data. Rich methods are niche, high hallucination risk.

**Q5: Sized numeric literal syntax (4-1 for type inference only)**

- **Systems:** Constructor syntax. Type inference fails when passing literals to functions. `U8(42)` is greppable and optimizes away. *(Dissent)*
- **Web/Scripting:** Inference. `let x: U8 = 42` is most readable for TS/Kotlin devs. Suffixed literals confuse JS/Python devs.
- **PLT:** Inference. Bidirectional type checking (Pierce & Turner) is principled. Literal stays polymorphic until context demands specialization. Suffixes create dual-typing ambiguity.
- **DevOps:** Inference. Cleanest error surface. Type declaration is single source of truth. LSP quick-fix "add `: U8`" covers edge cases.
- **AI/ML:** Inference. One syntax, zero suffix rules. No new syntax to learn.
