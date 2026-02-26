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

The compiler must support **recoverable, incremental parsing** -- it should parse and type-check partial or malformed programs and still produce useful diagnostics for the valid portions. LLMs frequently generate code with one error in the middle of an otherwise correct program. A compiler that gives up at the first error without checking the rest of the file is hostile to AI workflows. Maximizing useful feedback per round-trip is the core optimization target.

**Principle 2: One way to do everything.**

Canonical syntax. Canonical formatting. One package manager. One test runner. One way to declare a function, one way to handle errors, one way to format a string.

When an AI encounters a decision point -- "should I use single quotes or double quotes?", "which test framework?", "tabs or spaces?" -- that decision costs tokens, risks inconsistency, and produces code that looks different from the training data depending on which choice is made. Pact eliminates these decisions. There is one way. The AI never asks "which way?" It just writes the only way.

This extends beyond syntax. There is one error handling mechanism (`Result[T, E]` with `?`). One polymorphism mechanism (traits). One way to represent absence (`Option[T]`). One way to declare effects. Pact is deliberately not a multi-paradigm language. It is an opinionated language that made the choices so nobody else has to.

A corollary is **exemplar-friendliness**: every syntactic pattern should be visually distinct so that LLMs can learn from examples via structural pattern-matching. If two different concepts use similar syntax, the AI conflates them. When every construct has a unique visual shape, a single example teaches the pattern unambiguously.

**Principle 3: Locality of reasoning.**

A function's behavior must be determinable from its signature, its body, and its explicit imports. No action-at-a-distance. No implicit conversions. No inheritance hierarchies where understanding a method requires reading five parent classes. No global state that silently changes behavior.

This principle exists because context windows are finite. If understanding one function requires reading 15 files, the AI fails -- it either truncates context and misses something, or it spends its entire budget on comprehension rather than generation. Pact's design ensures that the unit of comprehension is the function, not the call graph.

Effects are the key mechanism: when a function declares `! IO, DB`, you know its complete interaction surface with the outside world from the signature alone. When it declares no effects, you know it is pure -- its output depends only on its inputs. No need to read the body to check.

**Principle 4: Make correctness cheap and incorrectness expensive.**

Strong types, exhaustive pattern matching, effect tracking, and contracts catch bugs at compile time. The AI gets precise, actionable error messages -- not stack traces from a running program. The cost of writing correct code should approach the cost of writing any code at all.

This principle has a corollary: **prove, don't test.** The type system and contract system are designed so that many correctness properties can be verified statically. Testing is a fallback for properties that resist static proof, not the primary correctness mechanism. AI excels at satisfying formal constraints but struggles with the open-ended creativity required to write good tests. A language that shifts correctness toward provable contracts plays to AI's strengths.

The progression is deliberate: types catch the most bugs for free (inference makes them cheap). Effects catch the next tier (impurity is visible). Contracts catch domain-specific invariants (the compiler proves what it can, runtime-checks the rest). Tests cover what remains. Each layer is cheaper to write and more reliable than the one below it.

**Principle 5: Effects are capabilities.**

Pact's effect system is not just a purity tracker -- it is a capability system. A function that declares `! DB` has the *capability* to access the database. A function that does not declare it *cannot* access the database, period. The compiler enforces this transitively.

This reframes effects as a security mechanism. In traditional languages, any function can do anything -- read files, make network calls, launch missiles -- and nothing in the language prevents it. In Pact, capabilities are explicit, visible in signatures, and enforced at compile time. A module that declares only `! IO.Read` cannot write. A sandboxed plugin that declares no effects cannot touch the outside world.

The implications extend beyond security: effects enable deterministic testing (swap real handlers for mocks at effect boundaries), enable fearless refactoring (changing an effect signature is a compile error everywhere it matters), and enable AI comprehension (the AI knows a function's complete side-effect surface from its type).

**Principle 6: Precise, not verbose.**

Every piece of information appears exactly once, in the place where it matters, and nowhere else.

At boundaries -- function signatures, module interfaces, effect declarations -- Pact is explicit. Effects are declared, not inferred. Types are present at function boundaries. Imports are explicit. Error paths are visible in return types. There is no magic.

Within boundaries, Pact is terse. Types are inferred inside function bodies. The `?` operator handles error propagation in one character. Canonical formatting handles all whitespace decisions. No semicolons (newlines are unambiguous). No `f"..."` prefix (all strings interpolate). Short type names (`Str`, `Int`, `Bool`). `fn` not `function`. `T?` not `Option[T]` in type position.

AI models consume and produce tokens. Every unnecessary token costs inference time, money, and context window space. But ambiguity is worse than verbosity -- an ambiguous token that causes a wrong generation wastes far more than the token it saved. Every abbreviation is chosen because it is unambiguous, not merely because it is short.

The test: if you can delete a token and the program's meaning doesn't change, that token shouldn't exist. If you can't determine a function's behavior without reading something outside the function, something is missing from the signature.

**Principle 7: Errors are the teaching signal.**

For an AI, the error message *is* the learning signal. The quality of diagnostics determines how many round-trips it takes to reach correct code. Pact diagnostics are not messages for humans to interpret -- they are structured correction instructions that an AI can apply mechanically.

Every diagnostic includes: the error category, the precise source location, a human-readable explanation, and -- critically -- a machine-applicable fix: the exact edit that resolves the problem. An error like `{kind: "missing_effect", fix: {line: 5, insert: " ! IO"}}` lets the AI self-correct in one round-trip instead of reasoning about what to change. When multiple fixes are possible, the diagnostic enumerates them with confidence scores.

This is not a tooling convenience layered on top -- it is a language design constraint. Syntax and semantics are chosen so that errors are *unambiguously correctable*. A grammar that produces parse errors with three possible resolutions is worse than one that produces errors with exactly one resolution, even if the grammar is slightly more verbose. Pact optimizes for diagnostic clarity the same way other languages optimize for runtime performance.

### 1.2.1 Design Aspiration: Intent as Code

In current languages, the "why" behind code lives in comments, commit messages, Jira tickets, and tribal knowledge -- all invisible to the compiler, all easily lost, all perpetually out of sync with the implementation. Pact aims to treat intent as a first-class, compiler-aware part of the program.

Intent declarations, contracts, performance targets, and provenance links are structured metadata that participates in type checking, verification, and tooling. They are versioned with the code. They are queryable by the compiler-as-service. When the intent says "sort in ascending order" and the implementation sorts descending, the contract system catches it.

This bridges the fundamental gap in AI-assisted development: the human defines *what* should happen and *why*; the AI defines *how*; the compiler proves the *how* satisfies the *what*. Each role has first-class support in the language.

This is aspirational -- it depends on the contract and verification systems being expressive enough to close the intent-implementation gap. The seven principles above are concrete design constraints the compiler enforces today; this aspiration describes the direction they point toward.

### 1.3 Non-Goals

Pact is opinionated about what it is *not*.

**Not a systems language.** Pact does not compete with Rust or C for kernel development, embedded systems, or bare-metal programming. There is no ownership model, no manual memory management, no `unsafe` escape hatch. If you need to control individual cache lines, use a different language and call it via FFI.

**Not academically novel.** Every idea in Pact is proven in at least one shipping language. Algebraic effects come from Koka. HM inference comes from ML/OCaml/Haskell. ADTs and pattern matching come from the entire ML family. Traits come from Rust/Haskell. The novelty is the composition and the AI-first design constraints, not the individual features.

**Not backwards compatible with anything.** Pact has no legacy to protect. It does not parse C headers, accept Python syntax, or maintain compatibility with any existing ecosystem. Clean-slate design is the entire point -- the goal is to make the *right* choices, not the *familiar* ones.

**Not maximally expressive.** Pact deliberately restricts expressiveness to keep the language small and predictable. No macros that create sublanguages. No operator overloading beyond numeric traits. No metaprogramming that the compiler cannot analyze. If a feature makes code harder for AI to read and reason about, it does not belong in Pact, regardless of how powerful it is.

**Not a human-only language.** Some design choices in Pact prioritize machine readability over human familiarity. This is acceptable because humans work through tooling (IDE rendering, inlay hints) while AI works on the raw source. Optimizing the source format for AI consumption is the right tradeoff when tooling can bridge the gap for humans.

**Not a committee language.** Pact makes choices. It does not offer configuration knobs, alternative syntaxes, or "choose your own style" options. Every design decision is a bet, and Pact makes its bets explicitly rather than deferring them to the user. Opinionated is a feature, not a limitation.
