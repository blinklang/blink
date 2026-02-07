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
| Iterator trait | Single `next(self) -> Option[T]` method. No `has_next()`, no `size_hint()` in v1 | 3-2 (Web/DevOps/AI for single; Sys/PLT for multi-method) |
| IntoIterator separation | Separate `IntoIterator` trait; collections produce iterators, aren't iterators | 5-0 |
| Lazy iteration | Adapters (`.map()`, `.filter()`) return lazy iterators. `.collect()` materializes | 5-0 |
| Iterator adapter placement | Default methods on `Iterator` trait. Implement `next()`, get adapters free | 5-0 |
| Effectful iteration | Deferred to v2. v1 Iterator is pure — `next()` cannot perform effects | 3-2 (Web/DevOps/AI for defer; Sys/PLT for v1 effects) |
| Standard library scope | 3-tier system: Core (compiler), Batteries (toolchain), Ecosystem (community). `math/str/fmt` confirmed Tier 1 | 5-0 ratified |
| Range syntax | `..` exclusive, `..=` inclusive, `Range[T: Ord]`, lazy | 5-0 ratified |
| Keyword arg separator | `--` separator divides positional from keyword params. Author decides, caller has no choice | 3-1-1 (`--` 3, `;` 1, `*` 1) |
| Keyword labels in type | Labels are call-site sugar only. Function type is `fn(Int, Account, Account)` regardless of `--` | 5-0 |
| Struct field defaults | Struct fields can declare compile-time constant defaults. Omitted fields use default at construction | 5-0 |
| Struct construction shorthand | `foo({ port: 3000 })` when param type is inferrable. Sugar only — function takes one struct arg | 5-0 |
| Function param defaults | Rejected for v1. Interact with closures, HOFs, partial application. Struct defaults cover the use case | 5-0 (reject) |
| Resource cleanup | `Closeable` trait + `with...as` scoped resource blocks. 3-0 over `defer` and lint-only approaches | 3-0 |
| Interpolation injection safety | `Query[C]` phantom-typed parameterized queries. Auto-parameterize `{expr}` in Query context. `Raw(expr)` per-interpolation escape hatch (replaces `Query.raw()`). Taint tracking deferred to v2 | 3-0 |
| Query escape hatch | `Raw(expr)` marker type. Per-interpolation bypass inside `Query[C]` strings. No format specs v1. No `Query.raw()` | 2-1 (D 2, A 1) |
| Codegen backend | Emit C source, shell out to cc/gcc/clang. Koka-style evidence-passing for effects. Optional LLVM via `clang -O2` for release builds | 4-1 (Sys/PLT/DevOps/AI for C; Web for Cranelift) |
| Operator desugaring | Trait-based: operators desugar to trait method calls (Add, Sub, Mul, Div, Rem, Neg, Eq, Ord) | 5-0 |
| Arithmetic trait restriction | Sealed: only compiler-provided impls for built-in numeric types | 4-1 |
| Boolean operator semantics | Language primitives requiring `Bool`. Short-circuit. No truthiness | 5-0 |
| Assignment operators | `+=` `-=` `*=` `/=` `%=` as syntactic sugar, `let mut` only | 5-0 |
| String concatenation via `+` | Rejected. Use interpolation or `.concat()` | 5-0 |
| Float equality | Total ordering: NaN == NaN, NaN sorts last | 5-0 |
| Ordering type | `type Ordering { Less, Equal, Greater }`, compiler-known, prelude | 5-0 |
| Comparison chaining | Rejected. `a < b < c` is compile error. Use `a < b && b < c` | 4-1 |
| `From[T]` trait | Single method `fn from(value: T) -> Self`. Compiler-known trait | 5-0 |
| `Into[T]` trait | Auto-derived by compiler from every `From` impl. Never user-implemented | 4-1 (AI/ML: no Into) |
| `TryFrom[T]` trait | Exists with fixed `ConversionError` error type (no associated types) | 5-0 exists; 3-2 fixed error (Sys/PLT: generic) |
| Numeric conversions | Both named methods (`.to_float()`) AND From/TryFrom impls | 4-1 (AI/ML: traits only) |
| `?` error conversion | No auto `.into()` on Err. Exact type match required. Use `.map_err()` | 4-1 (DevOps: auto-convert) |
| Generic From bounds | `fn foo[T: From[Str]](s: Str) -> T { T.from(s) }` is valid | 5-0 |
| If/else as expression | Always an expression. Value discarded → type `()`. Both branches type-unify when value is used | 5-0 |
| Else mandatory (expression context) | Required when value is used (let, return, arg). Optional when standalone (type `()`) | 5-0 |
| `if let` syntax | Rejected for v1. `match` + `??` cover use cases. Principle 2 | 5-0 |
| Parentheses around if condition | Forbidden (not optional). Consistent with `for`. One canonical form | 5-0 |
| `while` and `loop` constructs | Both: `while cond { }` for conditional, `loop { }` for unconditional. Different intent, different semantics | 3-2 (Sys/PLT/DevOps for both; Web/AI for while-only) |
| Break/continue semantics | Plain `break`/`continue` only. No break-with-value for v1 | 3-2 (Web/DevOps/AI for plain; Sys/PLT for break-expr) |
| Labeled breaks | Rejected for v1. Extract to function for nested loop exit | 4-1 (DevOps dissent) |
| `while let` syntax | Rejected for v1. Consistent with `if let` rejection. Use `loop { match ... }` | 5-0 |
| Import search paths | Single `src/` root + deps from `pact.lock`. No env vars, no configurable roots | 5-0 |
| Import cycle handling | Intra-package cycles OK (ML-style batch resolution), cross-package cycles are compile errors | 4-1 (DevOps: strict everywhere) |
| Diamond dependencies | Exactly one version per package. Conflict → compile error. Minimum version selection | 4-1 (Web: semver-compatible dedup) |
| Re-exports | `pub import` syntax. Decouples internal structure from public API | 5-0 |
| Import aliases | `import mod.{X as Y}` for local renaming. No wildcard imports | 5-0 |
| Method resolution: dot semantics | `x.foo()` is always trait method call, never field-call. `(x.field)(args)` for callable fields | 5-0 |
| Method resolution: effect handles | Effect handles are reserved names, cannot be shadowed by local variables | 5-0 |
| Method resolution: trait ambiguity | Multiple traits with same method → compile error at call site, use `Trait.method(x)` to disambiguate | 5-0 |
| Inherent methods | Rejected. All methods must belong to traits. No `impl Foo { fn bar(self) }` | 4-1 (Sys: wanted inherent) |
| Test effect model | Pure by default. No implicit effects in test blocks. Use `with` handlers | 5-0 |
| Test assertions | Three built-ins: `assert`, `assert_eq`, `assert_ne`. No `assert_match` v1 | 4-1 (PLT: minimal only) |
| Test filtering | Name + path + `@tags(...)` annotation for structured filtering | 4-1 (AI/ML: name-only) |
| Test scope | Top-level and inside `mod { }`. Module tests see private items | 4-1 (AI/ML: top-level only) |
| Tuple max arity | Cap at 6. Beyond 6 → compile error, use named struct | 5-0 |
| Tuple 1-tuples | No 1-tuple. `(T)` is always parenthesization | 5-0 |
| Tuple auto traits | Full structural: Eq, Ord, Hash, Display, Clone when elements satisfy | 5-0 |

---

## While/Loop — Design Rationale

### Panel Deliberation

Five panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML) voted independently on 4 questions.

**Q1: `while` vs `loop` vs both (3-2 for both)**

- **Systems:** Both share the same IR lowering. `while` and `loop` express different *intent* — conditional vs unconditional. `while true` adds a dead constant that communicates nothing. Event loops, server accept loops are conceptually infinite.
- **Web/Scripting:** `while` only. Every JS/TS/Python dev knows `while`. `while true` for infinite is immediately readable. `loop` as separate keyword violates Principle 2. *(dissent)*
- **PLT:** Both. `while` and `loop` have different typing — `while` may execute zero times (type `()`), `loop` without reachable `break` diverges (type `Never`). Collapsing them forces special-casing `while true` in the type checker.
- **DevOps:** Both. Linter can warn on `while true` → suggest `loop`. LSP can offer context-appropriate snippets. Two constructs, two distinct intents.
- **AI/ML:** `while` only. `while` is dominant in training data across Python/JS/Java/C/Go. `loop` is basically Rust-only. Models frequently fumble Rust's `loop`. *(dissent)*

**Q2: Break-with-value (3-2 for plain break)**

- **Systems:** Break-with-value. Polling/retry/search loops all produce a value. Without `break expr`, forced into `let mut` + assign — the declare-then-assign antipattern expression-oriented design exists to eliminate. *(dissent)*
- **Web/Scripting:** Plain break. Break-with-value is alien to web devs. `let mut` + assign + `break` is universal and obvious.
- **PLT:** Break-with-value. If `if/else` and `match` are expressions, `loop` should be too. Without it, unnecessary mutation to work around a missing semantic feature. *(dissent)*
- **DevOps:** Plain break. Break-with-value is a diagnostic nightmare — compiler must verify all break paths return compatible types. YAGNI for v1.
- **AI/ML:** Plain break. `break expr` is a Rust-ism LLMs get wrong constantly. Plain break matches Python/JS/Java/C/Go training data.

**Q3: Labeled breaks (4-1 no labels)**

- **Systems:** No. Rare need, extract-to-function handles it. Labels can be added in v2 without breaking changes.
- **Web/Scripting:** No. In 15+ years, can count on one hand. Nested loops needing coordinated exit is a code smell.
- **PLT:** No. Labels add continuation points that interact with algebraic effects — semantics get hairy. Extract a function.
- **DevOps:** Yes. Retry-with-timeout (outer=timeout, inner=retry), polling multiple endpoints. `@outer` reuses annotation sigil. *(dissent)*
- **AI/ML:** No. Rare in training data. Models routinely botch label placement. Extract-to-function is more common and correctly generated.

**Q4: `while let` (5-0 reject)**

- **Systems:** No. Same construct as rejected `if let`. Interacts awkwardly with potential future break-with-value.
- **Web/Scripting:** No. Consistent with `if let` rejection. `loop { match ... }` is explicit.
- **PLT:** No. Pattern matching should live in `match`. Adding `while let` after rejecting `if let` would be inconsistent.
- **DevOps:** No. One fewer special form for formatter, linter, and LSP. `loop + match` is more flexible.
- **AI/ML:** No. Rust/Swift-specific syntax with thin training signal. LLMs frequently generate wrong destructuring patterns.

---

## If/Else as Expressions — Design Rationale

### Panel Deliberation

Five panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML) voted independently on 4 questions. All votes unanimous.

**Q1: Expression-based if/else (5-0 for "always expression")**

- **Systems:** Maps to SSA phi nodes cleanly. Eliminates uninitialized-variable bugs from declare-then-assign. One construct, one lowering strategy.
- **Web/Scripting:** Eliminates need for a separate ternary operator (Principle 2). TS devs already fake this with ternaries — expression if/else is cleaner.
- **PLT:** Only clean option type-theoretically. Dual-mode would require defining `if` twice in typing rules. All ML-family languages get this right.
- **DevOps:** One rule for formatter/linter/LSP. Dual mode means context-dependent formatting and ambiguous diagnostics.
- **AI/ML:** Universal rule = more reliable LLM generation. Dual system forces model to track whether if/else appears in value-consuming position — subtle contextual reasoning that causes generation errors.

**Q2: Else mandatory when value used (5-0)**

- **Systems:** Type unification is compile-time only, zero runtime cost. Option wrapping creates implicit type complexity and hidden allocations.
- **Web/Scripting:** Forgetting else is a constant JS/TS bug source (implicit `undefined`). Compiler-enforced completeness when value matters.
- **PLT:** Conditional without else is a partial function. Implicit `Option[T]` wrapping adds monadic lifting into core syntax unnecessarily.
- **DevOps:** Trivial linter rule: value-producing if must have else. Catches real bugs mechanically. Auto-Option wrapping creates diagnostic ambiguity.
- **AI/ML:** When LLM produces `let x = if cond { 5 }`, it almost certainly forgot else — that's a bug, not intentional Option wrapping.

**Q3: No `if let` for v1 (5-0 reject)**

- **Systems:** Sugar over two-arm match — backend doesn't care. Smaller surface area = better for compiler simplicity.
- **Web/Scripting:** Two ways to pattern match = inconsistency in large codebases. If single-arm match feels verbose, that's tooling, not language.
- **PLT:** Pattern matching should live in one syntactic construct for exhaustiveness checking and type narrowing.
- **DevOps:** Every new syntax form multiplies formatter edge cases, LSP completions, and linter patterns.
- **AI/ML:** `if let` is a constant source of LLM syntax errors in Rust (forgetting `=`, wrong destructuring). One mechanism = more training signal per pattern.

**Q4: Parentheses forbidden, not optional (5-0)**

- **Systems:** Fewer grammar productions = simpler parsing, fewer ambiguities, faster parse times.
- **Web/Scripting:** Forbidding (not optional) prevents formatting inconsistency — optional means half the team uses them.
- **PLT:** Condition unambiguously delimited by `if` and `{`. Optional parens = two parse trees for same program.
- **DevOps:** Optional parens directly undermines `pact fmt` canonical formatting — formatter must either normalize (diff churn) or preserve (inconsistency).
- **AI/ML:** Models trained on mixed corpora randomly include/omit optional parens. Forbidding eliminates a decision point = one fewer error.

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

## Resource Cleanup — Design Rationale

### Problem Statement

Section 5.1 hand-waved "defer/drop semantics" without specifying them. Effect handlers manage DI'd resources (connection pools, FS capability) but not individual resources acquired within a function. The `?` operator causes early returns that skip cleanup code — the same problem that motivated Python's `with`, Go's `defer`, and Rust's `Drop`.

### Cross-Language Survey

| Language | Mechanism | Strengths | Weaknesses |
|----------|-----------|-----------|------------|
| Python | `with X as Y` + `__enter__`/`__exit__` | Scoped, familiar to LLMs | Two dunder methods, context manager protocol verbose |
| Go | `defer` | Simple, one keyword | Forgettable, no type signal, resource stays in scope after cleanup |
| Rust | `Drop` trait + RAII | Automatic, zero overhead | Tied to ownership system Pact doesn't have |
| Java | `try-with-resources` + `AutoCloseable` | Trait-based, scoped | Verbose syntax, bolted onto exception system |
| C# | `using` + `IDisposable` | Clean syntax | Requires explicit `IDisposable` cast in some cases |
| Swift | `defer` | Simple | Same problems as Go's defer |

### Proposals Considered

**Proposal A: `Closeable` trait + `with...as`** (selected)
- Single compiler-known trait signals resource-holding types
- `with...as` guarantees cleanup on all exit paths
- Reuses existing `with` keyword; `as` disambiguates from effect handlers
- Scopes the resource — cannot escape the block

**Proposal B: `defer` statements**
- `let f = fs.open(path)?` then `defer f.close()`
- Forgettable — no type signal, compiler can't warn when you forget
- Two steps to manage one resource
- Resource stays in scope after logical cleanup point

**Proposal C: Lint-only approach**
- Warn when `Closeable` values aren't closed
- No enforcement mechanism — easy to ignore
- No scoping guarantees

### Decision: Proposal A (3-0)

Why not `defer`:
1. **Forgettable** — no type signal, compiler can't warn when you forget
2. **Two steps** — acquire then defer, vs single `with...as` construct
3. **Principle 2** — adds a second resource management mechanism alongside `with`
4. **Training data** — `with X as Y` is Python (dominant in LLM training data); `defer` is Go/Zig (smaller representation)
5. **Scope leaking** — `defer` leaves the resource in scope after cleanup; `with...as` scopes it

---

## Codegen Backend & Bootstrap — Design Rationale

### Problem Statement

Pact compiles AOT to native binaries (§5.1, §6.1). The compiler will be self-hosted (written in Pact). Three questions:
1. What does the compiler emit to produce native code?
2. How does the self-hosted compiler bootstrap?
3. How are algebraic effects compiled?

### Options Considered

| Backend | Pros | Cons | Used by |
|---------|------|------|---------|
| **Emit C → cc** | Simplest, cross-compile for free, WASM via emscripten, every platform C supports | Two-phase compilation slower, no native stack maps | Nim, Chicken Scheme, Zig (stage1), Vala |
| **LLVM IR → llc** | Best optimization, wide targets | 500MB+ dep, SSA complex to emit, version churn, slow compilation | Rust, Swift, Julia, Crystal |
| **Cranelift (FFI)** | Fast compilation, self-contained | Fewer targets, no WASM output, FFI from Pact to Rust lib, less mature | Wasmtime, rustc (experimental) |

### Decision: Emit C (4-1)

**Phase 1 (v1.0):** Emit C, shell out to system cc/gcc/clang.
**Release builds:** `clang -O2` gives LLVM optimization without a separate backend.
**Phase 2 (optional, post-v1):** Evaluate Cranelift for self-contained builds if "needs cc installed" becomes a real user complaint.
**LLVM as standalone backend: rejected.** Massive dependency, version churn, no panel support.

### Algebraic Effects: Evidence-Passing Translation (Koka model)

Effects are compiled away *before* codegen via Koka-style evidence-passing (Leijen, ICFP 2021):
- Each effect type → slot in evidence vector (vtable of function pointers)
- Evidence vector threaded as hidden parameter
- **Tail-resumptive handlers** (common case in Pact) → direct function pointer call, zero overhead
- **Non-resumptive handlers** → return from handler function
- **One-shot resumptive handlers** → yield bubbling (heap-allocated continuation, rare)
- Backend never sees effects — just structs and function calls

Pact restricts to **one-shot continuations** (like OCaml 5). Multi-shot not required by spec.

### GC Integration: Shadow Stack (v1)

Generated C uses shadow stack for GC root tracking:
- Function prologue/epilogue registers/deregisters GC roots
- ~5-10% overhead on pointer-heavy code
- Escape analysis (§5.3) eliminates most roots (stack-allocated values skip shadow stack)
- Precedent: Go used shadow stack through v1.4 at production scale
- Upgrade path: LLVM backend could use statepoints for zero-overhead precise scanning

### Green Threads: Runtime Library (C)

M:N scheduling is a runtime concern, not codegen:
- C runtime library handles stack allocation/switching (ucontext/platform fibers)
- Compiler inserts cooperative preemption checks in function prologues
- Same model as Go

### Bootstrap Path

```
Stage 0: Python interpreter (exists, src/pact/)
         → runs Pact compiler source (written in Pact)
         → compiler emits C
         → cc compiles C → native binary

Stage 1: Native Pact compiler (compiled by Stage 0)
         → compiles itself (Pact source → C → native)

Stage 2: Verify Stage 1 output == Stage 2 output → bootstrap complete
         → Python interpreter never needed again
```

### Panel Votes

- **Systems:** C primary. Shadow stack for GC. CPS + stack switching for effects. Optional LLVM later. Cranelift rejected (FFI coupling, insufficient targets).
- **PLT:** C primary. Evidence-passing makes backend irrelevant for effects. Koka proves it at scale. One-shot continuations only.
- **Web/DX:** Cranelift primary *(dissent)*. Wants Go-like zero-dep toolchain. Concedes C for bootstrap. Compilation speed concerns.
- **DevOps:** C primary. Ubiquitous toolchain. LLVM hard no. Optional Cranelift v1.x for self-contained builds.
- **AI/ML:** C primary. AI can write/debug/maintain C codegen easiest. Most training data. `clang -O2` for release = free LLVM optimization.

### Cross-Compilation & WASM

C backend delegates entirely to C compiler ecosystem:
- `CC=aarch64-linux-gnu-gcc pact build` → ARM64
- `CC=emcc pact build --target wasm32` → WASM
- `CC=x86_64-w64-mingw32-gcc pact build` → Windows
- `CC=musl-gcc pact build` → static musl binary

### References

- Leijen, "Type Directed Compilation of Row-Typed Algebraic Effects" (ICFP 2021) — evidence-passing
- Koka language (github.com/koka-lang/koka) — production evidence-passing to C
- Chicken Scheme — continuations in C via "Cheney on the MTA"
- Nim — production self-hosted compiler emitting C

---

## Iterator Protocol — Design Rationale

### Panel Deliberation

Five panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML) voted independently on 5 questions.

**Q1: Single-method vs multi-method Iterator (3-2 for single)**

- **Systems:** Multi-method (next + size_hint). `size_hint()` enables pre-allocation in `collect()` and `Vec::extend`. Critical for performance-predictable iteration. *(dissent)*
- **Web/Scripting:** Single. JS `[Symbol.iterator].next()` returning `{value, done}` maps to `Option[T]`. `has_next()` creates awkward double-call state. Training data strongly favors single-method.
- **PLT:** Multi-method (next + size_hint). Pragmatic extension that enables fusion without breaking the semantic model. *(dissent)*
- **DevOps:** Single. One required method means simpler derive macros, cleaner LSP completions, better error messages. Size hints can be added later as optional overrides.
- **AI/ML:** Single. Dominant pattern across Rust/Python/JS training data. Split methods require LLMs to coordinate two calls, increasing error rates.

**Q2: IntoIterator separation (5-0 for separate)**

- **Systems:** Separate. Collections shouldn't be consumed by iteration. Fresh cursor each time.
- **Web/Scripting:** Separate. JS distinguishes iterables (`[Symbol.iterator]()`) from iterators (`.next()`). Two loops over same list must both work.
- **PLT:** Separate. Conflating collection with traversal state is a category error. Semantically crucial.
- **DevOps:** Separate. Better error messages: "Vec does not implement Iterator, did you mean `for x in vec`?"
- **AI/ML:** Separate. Clear conceptual boundary LLMs can learn. Matches Rust's ubiquitous pattern.

**Q3: Lazy by default (5-0 for lazy)**

- **Systems:** Lazy. Only model compatible with zero-cost abstractions. `.map().filter().take(10)` on a million elements must not allocate intermediates.
- **Web/Scripting:** Lazy. Modern JS/Kotlin lazy chains are the right default. Token-efficient for AI generation.
- **PLT:** Lazy. Composes with fusion optimizations. Explicit `collect()` gives control.
- **DevOps:** Lazy. Prevents accidental quadratic behavior. Makes pending transformations visible in type signatures.
- **AI/ML:** Lazy. Produces token-efficient pipelines. LLMs excel at fluent chain generation.

**Q4: Adapter method placement (5-0 for default methods)**

- **Systems:** Default methods. Implement `next()`, get combinators free. Performance overrides still possible.
- **Web/Scripting:** Default methods. Web devs expect `.map()` to "just work". Minimum friction.
- **PLT:** Default methods. Natural home for combinators. Mirrors Haskell typeclasses.
- **DevOps:** Default methods. Derive macros trivial (generate `next()` only). One canonical documentation location.
- **AI/ML:** Default methods. Minimizes what LLMs must generate. Heavily represented in training data.

**Q5: Effectful iteration (3-2 for defer to v2)**

- **Systems:** Effects in v1. Effectful iteration is fundamental (file lines, DB cursors). Deferring creates compatibility chasm. *(dissent)*
- **Web/Scripting:** Defer. Async iteration in JS is a separate protocol because mixing has nasty edge cases. Get the simple case right first.
- **PLT:** Effects in v1. Evidence-passing means effectful iterators are just monomorphizations. No runtime burden. *(dissent)*
- **DevOps:** Defer. Effects on lazy iterators add compiler complexity (when does `! IO` fire?). Avoid half-solutions.
- **AI/ML:** Defer. Effectful iterators have virtually no training data. LLMs would hallucinate syntax. Ship pure, add effects when usage patterns emerge.

---

## Type Conversions (From/Into/TryFrom) — Design Rationale

### Panel Deliberation

Five panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML) voted independently on 5 questions.

**Q1: From[T] trait shape (5-0 for single method)**

- **Systems:** Single method `fn from(value: T) -> Self` compiles to a single function pointer in evidence-passing, zero overhead. Into should be auto-derived, not user-implementable — two user-facing traits doubles vtable surface for no gain.
- **Web/Scripting:** Web devs are used to `String(x)`, `Number(x)` style conversion. One method, one direction, dead simple. Auto-derive Into for `.into()` ergonomics but never let users implement it directly.
- **PLT:** Single method is correct. Manual Into would allow incoherent pairs (A: Into[B] without B: From[A]), breaking the categorical dual.
- **DevOps:** Single method, clean. If Into exists as a writable trait, you get two places to look when debugging "why did this conversion happen." LSP should show "derived from From[X] for Y" on hover.
- **AI/ML:** Single method cleanest for LLM generation. Into creates "two ways to do the same thing" — models trained on Rust constantly confuse From vs Into. *(Dissent: wants no Into at all — but 4-1 for auto-derive.)*

**Q2: TryFrom existence and error type (5-0 exists; 3-2 for fixed ConversionError)**

- **Systems:** TryFrom should exist with generic error parameter `TryFrom[T, E]`. A single ConversionError is a runtime-typed escape hatch that undermines the type system. *(Dissent on error type.)*
- **Web/Scripting:** Yes to TryFrom. Concrete ConversionError is fine — don't over-engineer without associated types. A single error type carrying a message is plenty.
- **PLT:** TryFrom yes, but parameterize E on the trait itself: `TryFrom[T, E]`. A fixed ConversionError becomes a god-type that loses information. *(Dissent on error type.)*
- **DevOps:** TryFrom should exist with fixed ConversionError. Per-impl error types create boilerplate cascade — every TryFrom needs a custom error, every call site needs a From impl for that error.
- **AI/ML:** Fixed ConversionError is better than Rust's associated-type approach for LLMs — models frequently botch the error type. One concrete error type = one pattern to learn.

**Q3: Numeric conversion mechanism (4-1 for both methods and traits)**

- **Systems:** Both. Named methods for primitives — discoverable, compile to single instructions. Plus From/TryFrom impls for generic programming. Complementary, not redundant.
- **Web/Scripting:** Both. Named methods are autocomplete-friendly. But From impls needed for generic code.
- **PLT:** Both. Methods for readability, From/TryFrom for generic programming. Methods should be sugar over the trait machinery.
- **DevOps:** Both. LSP autocomplete on `my_int.to_` shows available conversions — that's the primary discovery mechanism. From/TryFrom enables generic conversion functions.
- **AI/ML:** Traits only, no named methods. Named methods create open-ended surface area LLMs hallucinate (`.to_float()` vs `.as_float()` vs `.to_f64()`). Having both violates "one way to do everything." *(Dissent.)*

**Q4: `?` auto-conversion on Err (4-1 for NO)**

- **Systems:** No. A language that rejected implicit conversions shouldn't have `?` silently calling `.into()`. Require exact match. `.map_err()` is explicit and greppable.
- **Web/Scripting:** No. Auto-conversion on `?` is one of Rust's most confusing features for newcomers. Explicit `.map_err()` is more verbose but readable and obvious. Start strict, loosen later.
- **PLT:** No. Makes inference harder — compiler must solve From constraints at every `?` site. Degrades error messages. Violates explicit-over-implicit philosophy.
- **DevOps:** Yes. The spec already showed this pattern. Invest in diagnostic quality — generate "implement From[X] for Y" suggestions and LSP quick-fix actions. *(Dissent.)*
- **AI/ML:** No. LLMs handling Rust's `?` with implicit `.into()` is a mess — models generate code that compiles only because of hidden From impls they didn't reason about.

**Q5: Generic From-bounded code (5-0 valid)**

- **Systems:** Basic bounded polymorphism. Evidence-passing handles it naturally. Standard orphan rules ensure at most one From[Str] impl per type.
- **Web/Scripting:** Standard generic programming, would be bizarre to disallow. Invest in good error messages when the bound isn't satisfied.
- **PLT:** Sound. T determined at call site, coherence maintained. Standard return-type polymorphism.
- **DevOps:** No tooling concerns. LSP can resolve T.from to the From trait and show all satisfying types on hover.
- **AI/ML:** Clean, well-constrained, LLMs generate reliably. Bound makes contract explicit.

---

## Import Resolution — Design Rationale

### Panel Deliberation

Five panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML) voted independently on 4 questions.

**Q1: Search path algorithm (5-0 for single `src/` root)**

- **Systems:** Deterministic resolution with zero env-dependent state. `import foo.bar` → `src/foo/bar.pact`, done. One stat call. Configurable source roots create shadowing bugs that only manifest in CI with different directory layouts.
- **Web/Scripting:** Go proved single-root works. Python's sys.path is a legendary footgun — "works on my machine" is 90% a path problem. One folder, one rule.
- **PLT:** Resolution must be a total function from module path to file. Single root gives `resolve(path) = src/ ++ path.replace(".", "/") ++ ".pact"`. Configurable roots make resolution partial — first-match is nondeterministic if two roots contain the same module name.
- **DevOps:** LSP go-to-definition must be instant and unambiguous. Single root = path rewrite. Multiple roots = scan and handle shadows. Workspaces can be layered later without breaking single-root.
- **AI/ML:** LLMs generate imports by pattern matching. `import auth.token` → `src/auth/token.pact` is a mechanical rewrite the model learns instantly. Configurable roots mean the model must read `pact.toml` to resolve — extra context dependency that increases error rates.

**Q2: Cycle handling (4-1 for intra-package OK, cross-package error)**

- **Systems:** Intra-package cycles are natural — `auth.login` needs `auth.types`, and `auth.types` may reference errors from `auth.login`. Forcing extraction into a third module is artificial ceremony. Cross-package cycles are genuinely pathological.
- **Web/Scripting:** Strict no-cycles is frustrating in practice — hit it in Go constantly. Two files in the same directory should reference each other without extract-to-avoid-cycle gymnastics. Cross-package cycles are a real design smell.
- **PLT:** Within a package, the compiler resolves all declarations before checking bodies — standard ML-module semantics. Cross-package cycles would require recursive module resolution which is complex and rarely needed.
- **DevOps:** Strict cycles everywhere. Cycles within a package still make the dependency graph messy for incremental compilation — daemon can't recheck one module without rechecking the other. Forces clean layering. *(dissent)*
- **AI/ML:** LLMs generating multi-file modules naturally create cross-references between files in the same package. Forcing strict no-cycles means the model must plan extraction ahead of time — a planning task that increases error rates.

**Q3: Diamond dependencies (4-1 for exactly one version per package)**

- **Systems:** One version per package. Multiple versions in one binary break global state, type identity across versions, and FFI symbols. Go's minimum version selection is the right model.
- **Web/Scripting:** The "one version" constraint is why Go has dependency hell at scale. SemVer-compatible dedup gives flexibility — `http 0.5.1` and `http 0.5.3` can coexist as `http 0.5.3`. *(dissent)*
- **PLT:** Type identity requires one version. If `auth` uses `http.Response` from http 0.6 and `myapp` expects `http.Response` from http 0.5, these are distinct types. The compiler must reject this or insert hidden conversions (which Pact already rejected).
- **DevOps:** `pact.lock` has one version per package. Resolution is deterministic. Multiple versions → "which version did this bug come from?" diagnostic nightmare.
- **AI/ML:** LLMs don't reason about semver. They import `http.Response` and assume one definition. Multiple versions mean generated code might reference the wrong version's API silently.

**Q4: Re-exports (5-0 for `pub import`)**

- **Systems:** `pub import` is clean, explicit, and compiles to nothing — it's a namespace alias. Without re-exports, every consumer must know internal module structure. Adding a file forces downstream import changes.
- **Web/Scripting:** Every modern JS package has an `index.js` barrel file. `pub import` is the typed, explicit version. Without it, refactoring (moving a type between internal modules) breaks every consumer's imports.
- **PLT:** Re-exports are module-level abstraction — the module signature is independent of internal layout. Standard in ML, OCaml, Haskell.
- **DevOps:** LSP resolves `pub import` by following one redirect. Go-to-definition lands on the original declaration. Package-level re-exports mean the public API is visible in one file.
- **AI/ML:** `pub import auth.token.{Token}` is explicit and greppable. LLMs generate it mechanically. No re-exports forces models to track internal module structure — more context needed per import.

---

## Method Resolution — Design Rationale

### Panel Deliberation

Five panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML) voted independently on 4 questions.

**Q1: Effect handle namespace — reserved vs shadowable (5-0 for reserved)**

- **Systems:** Reserved. Effect handles compile to evidence-vector slots — not variables, capability proofs. Shadowing would require checking handler-compatibility at every use site. Keep the invariant simple: handle name → evidence slot, always.
- **Web/Scripting:** Reserved. If a dev writes `let io = 5` inside a function with `! IO` and `io.println` silently breaks, the bug is incomprehensible. Effect handles must be sacred.
- **PLT:** Reserved. Handles are capability witnesses. The typing rule for `io.println(x)` checks that `IO.Print` is in the effect row — trivially correct when `io` is a fixed binding in a separate namespace. If shadowable, the type rule must verify the variable's type matches at every use.
- **DevOps:** Reserved. LSP go-to-definition on `io.println` should always jump to the effect operation signature, never to some local variable. If shadowable, go-to-definition becomes context-dependent.
- **AI/ML:** Reserved. LLMs would shadow effect handles by accident constantly — `io`, `db`, `fs` are common variable names in training data. Making them reserved eliminates an entire error class.

**Q2: Dot-call semantics — method-only or field-call too (5-0 for method-only)**

- **Systems:** Method-only. `x.foo()` should compile to a single vtable dispatch or direct call. If it can also mean "load field, then indirect call," the codegen has two paths. `(x.callback)(args)` is explicit and compiles to a load+call.
- **Web/Scripting:** Method-only. `obj.method()` means method call. `(obj.field)(args)` for callable fields is unusual but the case is rare. Parentheses make intent clear.
- **PLT:** Method-only. Separating field projection (`.foo`) from method dispatch (`.foo()`) in typing rules avoids needing a "field-or-method?" judgment form. `(x.foo)(args)` is explicit projection-then-application — two rules composed, not one ambiguous rule.
- **DevOps:** Method-only. LSP autocomplete for `x.` shows methods uniformly. If fields could be callable too, autocomplete must inspect field types to decide which get `()` appended.
- **AI/ML:** Method-only. In training data, `x.foo()` is overwhelmingly a method call. Same syntax for two semantics = generation errors. `(x.callback)(args)` has a distinct visual pattern.

**Q3: Multiple trait methods — error at impl site or call site (5-0 for call-site)**

- **Systems:** Call site. Two independent authors defining traits with the same method name is realistic. Preventing a type from implementing both kills composability. Qualified syntax `Trait.method(x)` at the ambiguous call site is the right fix.
- **Web/Scripting:** Call site. Blocking impls is too aggressive — you'd discover the problem when adding a dependency, not when writing code. Error at call site with "did you mean `TraitA.foo(x)` or `TraitB.foo(x)`?" is better DX.
- **PLT:** Call site. Forbidding at impl site violates the open-world assumption for traits. Types should be freely implementable for any trait whose contract they satisfy.
- **DevOps:** Call site. Error message can list both traits, show signatures, offer quick-fix to insert qualified form. Error at impl site gives "you can't implement this trait" with no actionable fix for third-party traits.
- **AI/ML:** Call site. Call-site errors happen where the AI is generating code and can immediately fix. Impl-site errors happen at definition time, far from where the AI is working.

**Q4: Inherent methods — yes or no (4-1 for no)**

- **Systems:** Yes. Inherent methods are essential for type-specific operations that don't belong to any trait. Forcing everything through traits creates artificial trait proliferation — one-method traits that exist only to give a type a method. *(dissent)*
- **Web/Scripting:** No. One way to define methods: in traits. No "should this be inherent or a trait?" decision. A one-method trait is fine — the overhead is one line.
- **PLT:** No. Inherent methods create silent priority over trait methods. Adding an inherent method to a type can change which code runs at existing call sites without any error. Without inherent methods, adding a trait impl can only cause ambiguity errors, never silent behavior change.
- **DevOps:** No. "Where is this method defined?" has one answer: in a trait impl block. LSP searches trait impls only. With inherent methods, LSP must also search `impl Foo { }` blocks.
- **AI/ML:** No. "All methods live in traits" is a single rule. One mechanism = one pattern = better generation accuracy. Consistent with Pact's rejection of alternatives everywhere.

---

## Test Syntax — Design Rationale

### Panel Deliberation

Five panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML) voted independently on 4 questions. Each expert ran as a separate agent and returned votes without seeing other experts' reasoning.

**Q1: Test effect model — pure by default vs implicit effects (5-0 for pure)**

- **Systems:** Pure-by-default means zero hidden runtime cost. Implicit effects require the test runner to silently inject handler implementations — hidden behavior that Pact's effect system exists to eliminate. Pure tests are trivially parallelizable since the compiler knows they're side-effect-free.
- **Web/Scripting:** JS/Python devs are used to explicit test setup. A test that silently hits a real database is a footgun. `with mock_net(...)` is self-documenting. Worth more than saving one line of boilerplate.
- **PLT:** Implicit effects destroy the information content of the effect row and require the compiler to silently insert evidence the programmer never requested. Pure-by-default preserves compositionality — the principled Koka approach.
- **DevOps:** Best diagnostics. Compiler emits actionable errors: `test "fetch data" calls fetch() which requires !Net, no handler provided. Hint: wrap in 'with mock_net(...) { }'`. LSP can offer quick-fix.
- **AI/ML:** "Pure by default, opt-in with `with`" is one rule everywhere. Two different implicit-effect contexts (main vs test) forces LLMs to track which context they're in — bad at context-dependent behavior shifts.

**Q2: Assertion built-ins (4-1 for three: assert + assert_eq + assert_ne)**

- **Systems:** Three intrinsics compile to comparison + branch + panic-with-diagnostics. `assert_match` implies compiler needs to lower arbitrary pattern syntax into assertion diagnostics — significant codegen complexity. Three is manageable; four starts to smell like a framework.
- **Web/Scripting:** `assert`, `assert_eq`, `assert_ne` — the holy trinity. Every developer from every language expects these three. `assert_match` can wait.
- **PLT:** `assert_ne(a, b)` is literally `assert(a != b)` — zero expressive power added, violates Principle 2. Keep the trusted kernel small. Two primitives form a complete basis. Compiler could special-case `assert(a != b)` for better messages via syntactic analysis. *(dissent)*
- **DevOps:** Three autocomplete entries in LSP, clean and fast. `assert_match` has ugly diagnostics — pattern failure diffs are walls of text. Defer until someone designs good pattern diff formatting.
- **AI/ML:** `assert`, `assert_eq`, `assert_ne` are near-universal across training data. Three built-ins = high coverage, low hallucination surface.

**Q3: Test discovery & filtering (4-1 for name + path + annotation tags)**

- **Systems:** Tags are compile-time metadata, zero runtime cost — stripped with test bodies. Without tags, you get name conventions encoding structured data in unstructured strings, making build systems fragile. The annotation system already exists; tags are a trivial extension.
- **Web/Scripting:** Every real-world project needs `--tag unit` vs `--tag integration`. JS-land abuses filename conventions because the framework didn't give them tags. `@tags(...)` is dead simple and immediately familiar.
- **PLT:** Annotations are already in the language — `@tags(...)` introduces no new typing concerns. Tags provide an orthogonal classification algebra without conflating naming conventions with test categorization.
- **DevOps:** Every real CI pipeline needs structured tag filtering. `@tags(...)` fits existing annotation system. Test runner output groups by tag naturally. `pact test --json` includes tags for CI parsing.
- **AI/ML:** Tags are metadata LLMs consistently forget to add. Name/path filtering requires zero additional annotation. Naming conventions are what LLMs are good at. *(dissent)*

**Q4: Test scope — top-level only vs inside modules too (4-1 for inside modules)**

- **Systems:** Tests inside `mod { }` can access private items — test internal invariants without making them `pub`. Internal data structure invariants need rigorous testing and must NOT be public API. Top-level-only forces either making internals `pub` or adding `pub(test)` visibility.
- **Web/Scripting:** This is the Rust model and it's genuinely good. Being able to write tests next to the code they test, with access to private items, is one of Rust's best features. Strictly more capable than top-level-only.
- **PLT:** Module-scoped tests seeing private items is the correct typing rule for verification. The scoping rule is uniform: `test` inside `mod M` sees `M`'s private scope, same as `fn` inside `M`. No special cases.
- **DevOps:** Tests next to code, access private items. LSP shows code lens "Run test" above each block. Filter uses path prefix: `auth::verify works`.
- **AI/ML:** Flat file structures are far more reliable for LLMs. Nested placement adds an ambiguous decision point. Rust's `mod tests { }` is the counterexample — LLMs frequently mess it up. *(dissent)*

---

## Tuple Types — Design Rationale

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

---

## Open Questions

These design decisions remain unresolved:

1. **Information flow tracking** — Taint tracking via effect provenance (v2+ roadmap). `Query[C]` covers injection cases for v1
2. **Row polymorphism** — Needed for effect system internals? Not yet addressed in sections.
3. **Higher-kinded types** — Only if needed for effect abstractions. Deferred.
4. ~~**Codegen backend**~~ — **Resolved.** Emit C → cc. See Codegen Backend & Bootstrap rationale above.
