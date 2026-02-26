[< All Decisions](../DECISIONS.md)

# Tuple Types — Design Rationale

### Panel Deliberation

Five panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML) voted independently on 3 questions. All votes unanimous.

**Q1: Maximum arity (5-0 for cap at 6)**

- **Systems:** Cap at 6. Every tuple arity is a distinct struct in emitted C. Bounding at 6 keeps monomorphized trait impls small and fixed. Tuples beyond 3-4 smell like a struct that deserves a name.
- **Web/Scripting:** Cap at 6, already generous. Nobody asks "why can't I have a 13-tuple" — they DO ask "how do I remember what element 9 means."
- **PLT:** Tuples are an exception to Pact's nominal typing — anonymous structural products in a nominal world. The exception should be narrow. Cap pushes users toward better-designed named types.
- **DevOps:** Hover info stays readable, error messages stay clean. When someone hits the cap, the compiler emits "consider using a named struct" — a genuinely helpful diagnostic.
- **AI/ML:** Training data clusters at 2-3 elements. Cap forces structs for complex data, which LLMs handle better due to named fields carrying semantic info.

**Q2: 1-tuples (5-0 for no 1-tuple)**

- **Systems:** No 1-tuple. `(T)` is always parenthesized expression. A 1-tuple is isomorphic to its element — zero performance benefit, adds parser complexity.
- **Web/Scripting:** Every JS/Python dev has been burned by Python's `(x,)` vs `(x)` confusion. Don't make parentheses context-dependent.
- **PLT:** The 1-ary product is isomorphic to T in standard type theory. Trailing-comma syntax is a parsing hack with zero gain in expressiveness or soundness.
- **DevOps:** Eliminates an entire class of confusing diagnostics. Parser never has to guess intent when user types `(SomeType)`.
- **AI/ML:** LLMs get trailing comma `(T,)` wrong at measurably higher rates than almost any other syntax detail. Eliminating 1-tuples removes ambiguity entirely.

**Q3: Auto-derived traits (5-0 for full structural)**

- **Systems:** Full structural derivation. Tuples are anonymous product types — their value proposition is convenience. Lexicographic Ord matches every language with tuple ordering. Trait impls are trivially generated, zero cost beyond hand-written equivalent.
- **Web/Scripting:** "I returned `(status, count)`, why can't I sort a list of them?" is a question nobody should have to ask. Lexicographic ordering is what people expect.
- **PLT:** All five traits have canonical compositional interpretations on product types. Lexicographic Ord is the unique order compatible with product structure — mathematically canonical, not a design choice.
- **DevOps:** When a trait is NOT available, the compiler points at the specific element: "`Canvas` does not implement `Ord` (element .1 of tuple)." Omitting Ord artificially produces worse diagnostics.
- **AI/ML:** Matches Rust behavior, the largest source of typed-tuple training data. Missing traits create compile errors LLMs have no mental model for.

