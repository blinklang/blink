## 1. Philosophy

Pact is built on a single thesis: **the language should treat AI as a first-class consumer of its entire toolchain.** Not "a language with good AI tooling." A language where the compiler, formatter, package manager, test runner, and verification engine form a unified system designed to be driven by both humans and AI agents through structured, machine-readable interfaces.

The consequence: every design decision in Pact is filtered through the question *"does this make the human-AI-compiler collaboration loop faster, cheaper, and more correct?"* When the answer conflicts with tradition, convention, or familiarity, Pact chooses the collaboration loop.

### 1.1 Name

The language is called **Pact** because its central abstraction is the contract -- formal, verifiable agreements between components at every level of the system.

A function signature is a pact: it promises a return type, declares its effects, and guarantees its contracts. A module boundary is a pact: it exposes a public API and hides implementation. The effect system is a pact: a function that declares `! DB` can access the database; one that does not, cannot. The type system is a pact: if a value's type says `Int`, it is an integer everywhere and always.

Every annotation, type constraint, and effect declaration is a binding promise that the toolchain enforces mechanically. The name is the philosophy: make promises explicit, then make the machine hold everyone to them.

File extension: `.pact`
CLI tool: `pact`

### 1.2 Core Principles

**Principle 1: Optimize the generate-compile-check-fix loop.**

AI writes code in tight iterations. It generates a candidate, the compiler checks it, the AI reads the diagnostics, and it fixes the problems. This loop runs hundreds of times per task. Every millisecond of compiler latency, every ambiguous error message, every syntax choice that causes wasted generations -- these costs compound multiplicatively.

Pact is designed around this loop. The compiler runs as a persistent daemon with sub-200ms incremental checking. All diagnostics are structured data with machine-applicable fixes. The syntax is deterministic -- there is never a question of "which valid form should I generate?" because there is only one.

*This is the operational principle. Every other principle exists in service of making this loop faster and more reliable.*

**Principle 2: One way to do everything.**

Canonical syntax. Canonical formatting. One package manager. One test runner. One way to declare a function, one way to handle errors, one way to format a string.

When an AI encounters a decision point -- "should I use single quotes or double quotes?", "which test framework?", "tabs or spaces?" -- that decision costs tokens, risks inconsistency, and produces code that looks different from the training data depending on which choice is made. Pact eliminates these decisions. There is one way. The AI never asks "which way?" It just writes the only way.

This extends beyond syntax. There is one error handling mechanism (`Result[T, E]` with `?`). One polymorphism mechanism (traits). One way to represent absence (`Option[T]`). One way to declare effects. Pact is deliberately not a multi-paradigm language. It is an opinionated language that made the choices so nobody else has to.

**Principle 3: Locality of reasoning.**

A function's behavior must be determinable from its signature, its body, and its explicit imports. No action-at-a-distance. No implicit conversions. No inheritance hierarchies where understanding a method requires reading five parent classes. No global state that silently changes behavior.

This principle exists because context windows are finite. If understanding one function requires reading 15 files, the AI fails -- it either truncates context and misses something, or it spends its entire budget on comprehension rather than generation. Pact's design ensures that the unit of comprehension is the function, not the call graph.

Effects are the key mechanism: when a function declares `! IO, DB`, you know its complete interaction surface with the outside world from the signature alone. When it declares no effects, you know it is pure -- its output depends only on its inputs. No need to read the body to check.

**Principle 4: Intent is code.**

In current languages, the "why" behind code lives in comments, commit messages, Jira tickets, and tribal knowledge -- all invisible to the compiler, all easily lost, all perpetually out of sync with the implementation. Pact treats intent as a first-class, compiler-aware part of the program.

Intent declarations, contracts, performance targets, and provenance links are structured metadata that participates in type checking, verification, and tooling. They are versioned with the code. They are queryable by the compiler-as-service. When the intent says "sort in ascending order" and the implementation sorts descending, the contract system catches it.

This bridges the fundamental gap in AI-assisted development: the human defines *what* should happen and *why*; the AI defines *how*; the compiler proves the *how* satisfies the *what*. Each role has first-class support in the language.

**Principle 5: Make correctness cheap and incorrectness expensive.**

Strong types, exhaustive pattern matching, effect tracking, and contracts catch bugs at compile time. The AI gets precise, actionable error messages -- not stack traces from a running program. The cost of writing correct code should approach the cost of writing any code at all.

This principle has a corollary: **prove, don't test.** The type system and contract system are designed so that many correctness properties can be verified statically. Testing is a fallback for properties that resist static proof, not the primary correctness mechanism. AI excels at satisfying formal constraints but struggles with the open-ended creativity required to write good tests. A language that shifts correctness toward provable contracts plays to AI's strengths.

The progression is deliberate: types catch the most bugs for free (inference makes them cheap). Effects catch the next tier (impurity is visible). Contracts catch domain-specific invariants (the compiler proves what it can, runtime-checks the rest). Tests cover what remains. Each layer is cheaper to write and more reliable than the one below it.

**Principle 6: Effects are capabilities.**

Pact's effect system is not just a purity tracker -- it is a capability system. A function that declares `! DB` has the *capability* to access the database. A function that does not declare it *cannot* access the database, period. The compiler enforces this transitively.

This reframes effects as a security mechanism. In traditional languages, any function can do anything -- read files, make network calls, launch missiles -- and nothing in the language prevents it. In Pact, capabilities are explicit, visible in signatures, and enforced at compile time. A module that declares only `! IO.Read` cannot write. A sandboxed plugin that declares no effects cannot touch the outside world.

The implications extend beyond security: effects enable deterministic testing (swap real handlers for mocks at effect boundaries), enable fearless refactoring (changing an effect signature is a compile error everywhere it matters), and enable AI comprehension (the AI knows a function's complete side-effect surface from its type).

**Principle 7: Token efficiency without ambiguity.**

Every token in a Pact program should carry maximum semantic meaning. Redundant syntax, decorative keywords, and boilerplate are eliminated -- but never at the cost of introducing ambiguity. The language is dense but precise.

AI models consume and produce tokens. Every unnecessary token costs inference time, money, and context window space. A language that expresses the same program in 40% fewer tokens effectively gives the AI 40% more working memory. But ambiguity is worse than verbosity -- an ambiguous token that causes a wrong generation wastes far more than the token it saved.

The practical consequence: no semicolons (newlines are unambiguous with canonical formatting). No `f"..."` prefix (all strings interpolate). Short type names (`Str`, `Int`, `Bool`). `fn` not `function`. `let` not `const`. `T?` not `Option[T]` in type position. Every abbreviation is chosen because it is unambiguous, not merely because it is short.

**Principle 8: Explicit over implicit -- but not verbose.**

Effects are declared, not inferred. Types are present at function boundaries. Imports are explicit. Error paths are visible in return types. There is no magic.

But explicit does not mean ceremonious. Types are inferred within function bodies. `main` does not require effect annotations. The `?` operator handles error propagation in one character. Canonical formatting means the formatter handles all whitespace decisions. The goal is that every piece of information appears exactly once, in the place where it matters, and nowhere else.

The test: if you can delete a token and the program's meaning doesn't change, that token shouldn't exist. If you can't determine a function's behavior without reading something outside the function, something is missing from the signature.

**Principle 9: Dual representation.**

Humans and AI have fundamentally different cognitive strengths. Forcing them to share a single representation means compromising for both. Pact maintains a single source of truth (the AST, derived from the canonical wire format stored on disk) with multiple renderings: a token-efficient wire format for storage and AI consumption, a human-optimized display format rendered on demand by tooling, and structured JSON for programmatic access.

All representations are lossless projections of the same underlying structure. They cannot desynchronize because only one is stored -- the rest are derived. The wire format is text (compatible with git, grep, diff). The display format expands abbreviations, adds visual structure, and presents metadata in readable panels. The AI operates on whichever representation is most efficient; the human reviews in whichever is most readable.

This is a long-term architectural principle. The initial implementation stores canonical source and renders it conventionally. As tooling matures, the display format becomes richer and the wire format can become more compact, without breaking compatibility.

### 1.3 Non-Goals

Pact is opinionated about what it is *not*.

**Not a systems language.** Pact does not compete with Rust or C for kernel development, embedded systems, or bare-metal programming. There is no ownership model, no manual memory management, no `unsafe` escape hatch. If you need to control individual cache lines, use a different language and call it via FFI.

**Not academically novel.** Every idea in Pact is proven in at least one shipping language. Algebraic effects come from Koka. HM inference comes from ML/OCaml/Haskell. ADTs and pattern matching come from the entire ML family. Traits come from Rust/Haskell. The novelty is the composition and the AI-first design constraints, not the individual features.

**Not backwards compatible with anything.** Pact has no legacy to protect. It does not parse C headers, accept Python syntax, or maintain compatibility with any existing ecosystem. Clean-slate design is the entire point -- the goal is to make the *right* choices, not the *familiar* ones.

**Not maximally expressive.** Pact deliberately restricts expressiveness to keep the language small and predictable. No macros that create sublanguages. No operator overloading beyond numeric traits. No metaprogramming that the compiler cannot analyze. If a feature makes code harder for AI to read and reason about, it does not belong in Pact, regardless of how powerful it is.

**Not a human-only language.** Some design choices in Pact prioritize machine readability over human familiarity. This is acceptable because humans work through tooling (IDE rendering, display format, inlay hints) while AI works on the raw source. Optimizing the stored format for AI consumption is the right tradeoff when tooling can bridge the gap for humans.

**Not a committee language.** Pact makes choices. It does not offer configuration knobs, alternative syntaxes, or "choose your own style" options. Every design decision is a bet, and Pact makes its bets explicitly rather than deferring them to the user. Opinionated is a feature, not a limitation.
