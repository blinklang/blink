[< All Decisions](../DECISIONS.md)

# Module Prelude — Design Rationale

### Panel Deliberation

Five panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML) voted independently on 3 questions. Each expert ran as a separate agent and returned votes without seeing other experts' reasoning.

**Q1: Which types belong in the prelude (3-1-1 for types + ADTs + traits)**

- **Systems:** Full set including ConversionError, Range, Handler (Option D). Every type in A through D is already compiler-intrinsic. The compiler must know their layout, vtable shape, and monomorphization behavior. Forcing imports for items the compiler already knows about adds zero information and wastes tokens. *(dissent — wanted D)*
- **Web/Scripting:** Types + ADTs only, no traits (Option B). Every mainstream language makes primitives and core collections available without imports. But traits in the prelude go too far — they're an intermediate concept newcomers shouldn't need to encounter in the prelude. *(dissent — wanted B)*
- **PLT:** Types + ADTs + traits (Option C). `==` desugars to `Eq.eq`, `<` to `Ord.cmp`, `for` through `IntoIterator`/`Iterator`, interpolation through `Display`, `@derive` references traits by name. If these traits aren't in scope, every file needs boilerplate imports for basic language features. Stops at C because `ConversionError`, `Range`, `Handler` are used by specific subsystems, not core typing rules.
- **DevOps:** Types + ADTs + traits (Option C). LSP autocomplete for `x.` needs all compiler-known traits in scope to show methods. Error messages referencing `Eq` or `Ord` should never say "did you forget to import Eq?" — that's a broken diagnostic experience. `ConversionError`/`Range`/`Handler` are importable without degrading day-to-day tooling.
- **AI/ML:** Types + ADTs + traits (Option C). Every import is a failure point for LLMs. Primitive types + core traits have near-100% usage in training data without imports. Forcing imports for `Int` or `Eq` would create a pattern with zero training data. ConversionError/Range/Handler are niche enough to import.

**Q2: `true`/`false` — keywords or prelude values (5-0 for keywords)**

- **Systems:** Keywords. The compiler emits direct boolean instructions — no vtable, no trait resolution, no name lookup. Making them keywords reflects what the hardware sees.
- **Web/Scripting:** Keywords. In every language web devs know, boolean literals are keywords. `let true = 5` should give "cannot use keyword as identifier," not a confusing shadowing error.
- **PLT:** Keywords. `true` and `false` are introduction forms for `Bool`, like `42` for `Int`. They participate in exhaustiveness analysis. The lowercase spelling already signals "keyword, not constructor" — Pact constructors are PascalCase.
- **DevOps:** Keywords. Keywords get syntax highlighting for free. No "unknown identifier" errors. No import needed. Clean diagnostic story.
- **AI/ML:** Keywords. `true`/`false` are keywords in 95%+ of training data. Zero ambiguity, zero decision points.

**Q3: Test builtins — auto-available or require import (5-0 for auto-available)**

- **Systems:** Auto-available. Test builtins are compiler intrinsics — `assert_eq` needs source locations and display values at compile time. They're not library functions. Test code is dead-code-eliminated in release builds regardless.
- **Web/Scripting:** Auto-available. Jest, pytest, Go testing — all have built-in assertions. Requiring imports adds ceremony to the simplest tests. Cap auto-available set at these four; richer testing utilities require imports.
- **PLT:** Auto-available. `test` blocks are a special syntactic form with their own scoping rules. `assert`/`assert_eq`/`assert_ne` are observation forms of the testing judgment — they need no import, same as `match` needs no import for pattern elimination.
- **DevOps:** Auto-available. The compiler already knows about test blocks. Built-in assertions should produce compile errors when used outside test blocks — this requires compiler awareness, not library code. LSP can show "only available in test blocks" hints.
- **AI/ML:** Auto-available. In training data, test assertions are never imported. LLMs would forget the import at high rates. Zero-friction test authoring is critical for adoption.

