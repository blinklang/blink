# Pact Design Decisions

Reference material extracted from the spec process. Influences, rejected features, resolved questions, editor's notes, and design process history.

---

## Editor's Notes

Minor inconsistencies between sections written by different experts. These need resolution:

1. **Annotation syntax**: Section 8 (in 06_tooling.md) uses `/// @i("text")` inside doc comments, while sections 2, 3, 4, 5, 9, 10, 11 use standalone `@i("text")`. The standalone form should be canonical — annotations are first-class, not comments.

2. **Annotation ordering**: Section 2.9 puts `@capabilities` after `@perf`. Section 11.1 puts `@capabilities` before `@i`. Section 11.1's ordering is more complete and should be canonical: `@mod` > `@capabilities` > `@derive` > `@src` > `@i` > `@requires` > `@ensures` > `@where` > `@invariant` > `@perf` > `@ffi` > `@trusted` > `@effects` > `@alt` > `@verify` > `@deprecated`.

3. **Method call syntax**: ~~Some sections use `email.len > 0` (property-style), others use `email.len() > 0` (method-style). Needs a decision.~~ **Resolved:** Always `x.len()` method-call syntax everywhere, including contracts. Panel vote 5-0.

---

## Design Process

This spec was developed through a multi-expert panel process across two sessions:

**Session 1:** 5 domain experts (systems programming, web/scripting, PL theory, DevOps/tooling, AI/ML) independently brainstormed attributes, designed syntax, and voted on contested decisions.

**Session 2:** 7 experts (original 5 + 2 fresh perspectives) each independently wrote sections of this merged spec, incorporating the best ideas from both prior iterations. The user's directive: think long-term ideal design, not v1-constrained.

---

## Influences

| Language | What Pact Borrows |
|----------|------------------|
| **Go** | Single binary deployment, `gofmt` philosophy, compilation speed priority |
| **Rust** | `fn` keyword, `match` expressions, `Option`/`Result`, `?` operator, traits, expression-oriented |
| **Koka** | Algebraic effects as a core feature, effect tracking in signatures |
| **OCaml/Haskell** | Hindley-Milner type inference, ADTs, pattern matching, ML type system level |
| **TypeScript** | `: Type` annotation syntax, developer experience focus |
| **Scala/Python 3.9+** | Square brackets for generics |
| **Swift** | `??` nil-coalescing operator |
| **E Language** | Object-capability model (Mark Miller) — effects as capabilities |
| **Dafny/Liquid Haskell** | Refinement types, `@requires`/`@ensures` contracts, SMT verification |
| **Z3** | SMT solver integration for contract verification |

---

## What We Explicitly Rejected

| Feature | Why Rejected |
|---------|-------------|
| **Ownership/lifetimes** | AI struggles with borrow checker (30-40% failure rate). Interacts badly with algebraic effects. Cognitive overhead anti-locality. |
| **Gradual typing** | "If you build a trapdoor, AI will find it." Undermines every type system guarantee. |
| **Null** | Billion-dollar mistake. `Option[T]` makes absence explicit and compiler-enforced. |
| **Exceptions** | Invisible control flow. Violates locality. LLMs generate incorrect catch blocks. `Result[T, E]` is explicit. |
| **Inheritance** | Creates deep hierarchies that destroy locality. Fragile base class problem. Traits are strictly better. |
| **Implicit conversions** | Action-at-a-distance. The AI (and the human) should see exactly what types flow where. |
| **Arbitrary operator overloading** | Reduces readability. Trait-based operator impls for numeric types only. |
| **Arbitrary macros** | Create sublanguages the AI hasn't seen in training data. Derive macros for codegen are the exception. |
| **Significant whitespace** | LLMs mangle indentation. Copy-paste loses whitespace. Braces are unambiguous. |
| **Multiple string delimiters** | One string syntax. No `'single'` vs `"double"` vs `` `backtick` ``. |
| **Semicolons** | Redundant with canonical formatting. Pure noise tokens. |
| **Structural typing** | Nominal types are easier for LLMs — distinct identifiers to latch onto. |
| **Full dependent types** | Type inference becomes undecidable. LLMs cannot reliably generate proofs. Error messages become incomprehensible. Refinement types give 90% of the value at 10% cost. |
| **JIT compilation** | Two compilation pipelines = two sets of bugs. JIT warmup is nondeterministic. Single binary deployment wins. |
| **Coarse-grained effects** | `! IO` collapses to meaninglessness within 3 call levels. Fine-grained effects (FS.Read, DB.Write) are the security model. |
| **Sigils for declaration** (`~`/`+`) | `fn` is universal. Sigils conflate visibility with declaration. Rejected 5-0. |
| **`:=` for bindings** | `let`/`let mut` has explicit mutability semantics. `:=` is ambiguous. Rejected 5-0. |
| **`::` for return type** | `->` is standard. `::` conflicts with Haskell convention. Rejected 4-1. |
| **Angle bracket generics** `<>` | Genuine parsing ambiguity with comparison operators. Zero technical argument over `[]`. Rejected 5-0. |
| **Optional keyword args (caller's choice)** | Caller deciding whether to name args violates Principle 2 (one way). Creates style decision at every call site. AI must choose between two forms. |
| **Mixed positional + keyword at same call site** | `foo(1, y: 2)` is the Python/Swift/Kotlin path. Creates decision-point-per-call-site that Principle 2 exists to prevent. |
| **Function parameter defaults** | Interact with closures (does `fn(Int) -> Int` match a fn with defaulted 2nd param?), higher-order functions, partial application. Struct field defaults are the simpler, controlled version. |

---

## Resolved Questions

Decided by expert panel vote. See [OPEN_QUESTIONS.md](OPEN_QUESTIONS.md) for full deliberation.

| Decision | Result | Vote |
|----------|--------|------|
| Closure syntax | `fn(params) { body }` — one keyword, no `\|x\|` sigil form | 5-0 |
| Derive/codegen | `@derive(Eq, Hash)` annotation. Compiler-known traits only for v1 | 5-0 |
| Property access | Always `x.len()` method-call syntax, including in contracts | 5-0 |
| Concurrency model | Green threads, structured concurrency, `Async` as effect. `main` has implicit effects | 5-0 ratified |
| Await semantics | `handle.await` — method on `Handle[T]`, compiler-recognized suspension point. Composes with `?` | 5-0 |
| Iterator/loop syntax | `for x in collection { }`, `.method()` chaining, `\|>` pipes. No comprehensions v1 | 5-0 ratified |
| Standard library scope | 3-tier system: Core (compiler), Batteries (toolchain), Ecosystem (community). `math/str/fmt` confirmed Tier 1 | 5-0 ratified |
| Range syntax | `..` exclusive, `..=` inclusive, `Range[T: Ord]`, lazy | 5-0 ratified |
| Keyword arg separator | `--` separator divides positional from keyword params. Author decides, caller has no choice | 3-1-1 (`--` 3, `;` 1, `*` 1) |
| Keyword labels in type | Labels are call-site sugar only. Function type is `fn(Int, Account, Account)` regardless of `--` | 5-0 |
| Struct field defaults | Struct fields can declare compile-time constant defaults. Omitted fields use default at construction | 5-0 |
| Struct construction shorthand | `foo({ port: 3000 })` when param type is inferrable. Sugar only — function takes one struct arg | 5-0 |
| Function param defaults | Rejected for v1. Interact with closures, HOFs, partial application. Struct defaults cover the use case | 5-0 (reject) |

---

## Keyword Arguments & Defaults — Design Rationale

### Problem Statement

Positional-only parameters create two classes of problems:

1. **Same-typed parameter swap bugs.** `transfer(from, to, amount)` where `from` and `to` are both `Account` — positional-only means a swap is type-correct but semantically wrong. LLMs swap same-typed positional args at 3-8% per call site.

2. **API evolution brittleness.** Adding a parameter to a positional-only function breaks every caller. Without defaults, the most common API evolution (adding an optional parameter) is always breaking.

### Cross-Language Survey

- **Python**: Full keyword args + defaults. Hugely popular but creates positional-or-keyword ambiguity, mutable default gotcha, `*args/**kwargs` untypeable black holes.
- **Swift**: External/internal param names. Best-in-class readability but dual naming is complex.
- **Kotlin**: Named args + defaults. Clean but "two ways to call" violates Principle 2.
- **Rust**: No keyword args, no defaults. Builder pattern workaround. #1 requested feature in surveys.
- **Go**: No keyword args, no defaults. Functional options pattern. Widely considered an ergonomics failure.

### Decision: Declaration-Site `--` Separator

The function author decides which params are positional and which are keyword. The caller has no choice.

```pact
fn transfer(amount: Int, -- from: Account, to: Account) -> Result[Transaction, BankError]
transfer(300, from: alice, to: bob)
```

**`--` separator won 3-1-1** (3 for `--`, 1 for `;`, 1 for `*`). `--` is the most visually distinctive, hard to confuse with any Pact syntax. `;` triggers statement-terminator instinct in AI. `*` (Python precedent) was considered too subtle.

**Labels as call-site sugar won 5-0 (unanimous).** Function type is `fn(Int, Account, Account)` regardless of `--`. Keeps closures and HOFs simple. No label propagation tracking needed.

### Decision: Struct Field Defaults

Struct fields can declare compile-time constant defaults. Primary config and API evolution mechanism.

```pact
type ServerConfig {
    host: Str = "0.0.0.0"
    port: Port = 8080
    debug: Bool = false
}
ServerConfig { port: 3000 }  // host and debug use defaults
```

Adding a field with a default is always backwards-compatible.

### Decision: Reject Function Parameter Defaults

Function param defaults interact with closures, HOFs, and partial application. Struct field defaults cover the same use cases with less type system complexity.

---

## Open Questions

These design decisions remain unresolved:

1. **Information flow tracking** — Taint tracking via effect provenance (v2+ roadmap)
2. **Row polymorphism** — Needed for effect system internals? Not yet addressed in sections.
3. **Higher-kinded types** — Only if needed for effect abstractions. Deferred.
