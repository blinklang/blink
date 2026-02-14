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
| Assertion messages | Optional trailing `Str` message on all assertions. Interpolation via standard string syntax | 3-2 (Sys/PLT/AI for B; Web/DevOps for C) |
| `panic()` function | `panic(msg: Str) -> Never` available everywhere. Untracked divergence, not an effect. Test runner catches; production terminates | 5-0 |
| `assert_matches` | Fourth compiler intrinsic. Second arg is a pattern, not an expression. No binding support v1 | 4-1 (AI/ML: thin training data, pattern-as-arg confuses LLMs) |
| Assertion output format | Expression introspection (Power Assert). Sub-expression values on failure. Left/right for `assert_eq`. One-level bounded depth | 4-1 (PLT: left/right is structurally honest, introspection is ad-hoc) |
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
| Test assertions (original) | Three built-ins: `assert`, `assert_eq`, `assert_ne` | 4-1 (PLT: minimal only) |
| Test filtering | Name + path + `@tags(...)` annotation for structured filtering | 4-1 (AI/ML: name-only) |
| Test scope | Top-level and inside `mod { }`. Module tests see private items | 4-1 (AI/ML: top-level only) |
| Test skip mechanism | Both `@skip` annotation (compile-time) and `skip()` built-in (runtime conditional) | 3-2 (PLT/AI: `@skip` only) |
| Tuple max arity | Cap at 6. Beyond 6 → compile error, use named struct | 5-0 |
| Tuple 1-tuples | No 1-tuple. `(T)` is always parenthesization | 5-0 |
| Tuple auto traits | Full structural: Eq, Ord, Hash, Display, Clone when elements satisfy | 5-0 |
| OR-patterns | `\|` separator. All alternatives bind same vars with same types | 5-0 |
| Range patterns | `..`/`..=` in patterns. Int/sized ints/Char only, compile-time constant bounds | 5-0 |
| Pattern binding | `as` keyword (`name as pattern`). Not `@` (conflicts with annotations) | 4-1 (AI/ML: defer) |
| Struct patterns in match | Full: field punning, `..` rest, literal field values. Nominal (type name required) | 5-0 |
| Refutable vs irrefutable | Strict compile error on refutable `let`. `let`/`for` = irrefutable, `match` = refutable | 5-0 |
| `Self` type scope | Valid in trait declarations + impl blocks only. Compile error elsewhere | 5-0 |
| `self` keyword sugar | `self` desugars to `self: Self`. `.method()` requires literal `self` first param | 5-0 |
| `Self` as constructor | Type-position alias only, not a constructor. Use concrete type name | 4-1 (Web wanted construction) |
| `self` passing semantics | Always by-value (GC, no references). No `&self`/`&mut self` | 5-0 |
| Closure capture mode | Shared reference (GC pointer). Mutations to `let mut` visible across closure boundary | 3-2 (PLT/AI/DevOps for shared; Sys/Web for by-value) |
| Explicit capture syntax | No explicit syntax (no `move`, no capture lists). Snapshot via `let` binding | 4-1 (DevOps: `move` keyword) |
| Spawn mutable captures | Compile error E0650 on `let mut` captures in `async.spawn`. Immutable captures OK | 3-2 (PLT/DevOps/AI for error; Sys/Web for auto-copy) |
| Module prelude scope | All built-in types + Option/Result + Ordering + all compiler-known traits. Not: ConversionError, Range, Handler | 3-1-1 (PLT/DevOps/AI for C; Web for B; Sys for D) |
| `true`/`false` status | Language keywords, not prelude values. Recognized by parser, not name resolution | 5-0 |
| Test builtins availability | `assert`, `assert_eq`, `assert_ne`, `prop_check` auto-available in test blocks. No import needed | 5-0 |
| Trait coherence: orphan rule | Strict: impl must be in package that defines the trait or the type. No third-party orphan impls | 5-0 |
| Trait coherence: impl overlap | No overlap, no specialization. Overlapping impls are a compile error | 5-0 |
| Trait coherence: impl placement | Any module within the owning package. Impls auto-visible when trait or type is imported | 5-0 |
| Effects on function types | Explicit: `fn(T) -> U ! IO.Log` as type expression. Same `!` syntax as declarations | 5-0 |
| Effect polymorphism form | Wildcard forwarding: `fn map(f: fn(T) -> U ! _) -> Iterator[U] ! _`. Named effect variables deferred to v2 | 3-2 (Web/DevOps/AI for wildcard; Sys/PLT for row polymorphism) |
| Effect polymorphism timeline | Fn-type effects in v1, wildcard polymorphism v2. Foundation now, generality later | 4-1 (Web/PLT/DevOps/AI for B; Sys for full v1) |
| Handler type identity | `Handler[E]` is a single generic type constructor parameterized by effect | 5-0 |
| Handler effect projection | Implicit projection: `Handler[DB]` usable where `Handler[DB.Read]` expected, compiler extracts vtable slots | 3-2 (Sys/PLT/DevOps for projection; Web/AI for covariant subtyping) |
| Handler generic parameters | No effect-kinded generics in v1. Handlers always concrete. Deferred to v2 with named effect variables | 4-1 (PLT dissented: wanted effect-kinded generics now) |
| Handler storage | Full first-class values: struct fields, lists, maps, closures, arguments, return values | 4-1 (Sys dissented: wanted restricted storage) |
| Handler completeness | Partial handlers with auto-delegation. Omitted ops forward via `default.op(args)` | 5-0 |
| Clone semantics | Logical copy (one-level deep). GC pointers copied, not recursively cloned. Deep clone deferred to v1+ | 3-2 (Sys/Web/PLT for logical; DevOps/AI for deep) |
| Debug trait | Separate `Debug` trait, no supertrait relationship with `Display`. Structural repr for developers | 5-0 |
| Derive codegen algorithm | Inferred bounds on generics + auto supertrait derivation. Field-by-field for structs, variant-match for enums | 5-0 |
| Derive error reporting | Report all non-derivable fields in one diagnostic pass. Field-level error pointing | 5-0 |
| Collection trait organization | `Contains[T]` shared trait + per-type `ListOps[T]`, `MapOps[K,V]`, `SetOps[T]` | 5-0 |
| List[T] method surface | Expanded: 12 methods (push, pop, get, set, append, contains, reverse, sort, insert, remove, index_of, last) | 3-2 (Web/DevOps/AI for expanded; Sys/PLT for 8) |
| Map[K,V] method surface | Expanded: 8 methods (get, insert, remove, contains_key, keys, values, entries, get_or_default) | 3-2 (Web/DevOps/AI for expanded; Sys/PLT for 6) |
| Set[T] method surface | Core: 4 methods (insert, remove, contains, union). Full set algebra deferred | 3-2 (Sys/Web/AI for core; PLT/DevOps for full algebra) |
| Collection construction | `Type.new()` + `let mut` required for mutation. No split types, no literal-only | 5-0 |
| Display interpolation requirement | Strict: `{expr}` requires `T: Display` at compile time. No fallback, no auto-synthesis. Built-ins have compiler-provided impls | 5-0 |
| Display desugaring mechanism | Two-phase: type checker verifies `T: Display`, codegen optimizes built-ins to format specifiers, emits `Display.display()` for user types | 5-0 |
| Display and Query[C] interaction | Display is Str-context only. `Query[C]` interpolation passes raw typed values as parameters, not Display-stringified strings. Compiler-known param type set | 5-0 |
| FFI pointer type model | `Ptr[T]` non-null default, `Ptr[T]?` for nullable via `Option`. `Void` opaque type for `Ptr[Void]`. No const/mut distinction | 4-1 (Sys/Web/PLT/DevOps for B; AI for A) |
| FFI pointer operations | Minimal + deref/write/null: `alloc_ptr`, `as_cstr`, `addr`, `deref() -> Option[T]`, `write(T)`, `is_null()`, `null_ptr[T]()`, `to_str()` | 5-0 |
| FFI pointer lifetime | Scoped `ffi.scope()` via Closeable integration. `scope.take()` for ownership transfer. Standalone `alloc_ptr` with GC finalizer as fallback | 3-2 (PLT/DevOps/AI for scope; Sys/Web for hybrid) |
| Error identification scheme | Names primary (PascalCase, frozen), codes secondary compact alias. `error[NonExhaustiveMatch]` in terminal, both in JSON | 3-2 (PLT/DevOps/AI for names; Sys/Web for hybrid) |
| Error code organization | Category-based numeric ranges (E00xx pattern matching, E01xx traits, E03xx types, E05xx effects, etc.) | 4-1 (Web/PLT/DevOps/AI; Sys for clean-up-current) |
| Error code collisions | Reassign unique IDs to all colliding codes. 8 reassignments across 4 spec sections | 5-0 |
| Error catalog format | Table with name, code, one-line, category, spec ref. Deferred `--explain` for detailed explanations | 4-1 (Sys/PLT/DevOps/AI; Web for full Rust-style explain now) |
| Error catalog location | Standalone `ERROR_CATALOG.md` at repo root | 5-0 |
| Machine output format | JSON stays. Panel voted 3-1-1 for JSON+TOON flag, but deferred — JSON is required regardless, TOON ecosystem too immature. Revisit when token-optimized formats have tooling parity | Deferred (3-1-1 panel vote recorded) |
| Package registry model | Hybrid: central registry + git URL fallback. Identity invariant: registered package has one identity regardless of access path | 5-0 |
| Package naming | Namespaced `org/name` format. Maps to trust boundaries for capability auditing | 4-1 (AI: flat names for LLM accuracy) |
| Version resolution algorithm | Minimal Version Selection. Oldest satisfying version. Deterministic without lockfile. No SAT solver | 4-1 (Web: maximal/latest for dev expectations) |
| Version constraint syntax | Caret default (`"1.2"` = `>=1.2, <2.0`). Tilde/exact available. Pre-1.0: minor is breaking | 4-1 (Sys: tilde default for tighter control) |
| MVP dependency sources | Path + git deps for v1. No registry infrastructure required. Schema forward-compatible for v2 registry | 5-0 |
| Stdlib resolution mechanism | Implicit dependency model. `std.*` prefix. Stdlib bundled with compiler, injected as virtual deps. No new resolution step | 4-1 virtual dep, 3-2 `std` prefix, 3-2 stdlib-as-dep |

---

## Trait Coherence — Design Rationale

### Panel Deliberation

Five panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML) voted independently on 3 questions. All votes unanimous.

**Q1: Orphan rules (5-0 for strict)**

- **Systems:** Strict. Evidence-passing requires exactly one vtable per (Trait, Type). Orphan ambiguity would require runtime dispatch or link-time deduplication. Newtype workaround covers the practical cases.
- **Web/Scripting:** Strict. Haskell's orphan instances are a well-known disaster. Two packages defining `impl Display for HttpResponse` and any program importing both breaks silently. The newtype pattern is a small price for deterministic behavior.
- **PLT:** Strict. Global coherence is a syntactic property under the orphan rule (package ownership), not a whole-program semantic analysis. This keeps compilation fast and decidable. Relaxing later is backwards-compatible; tightening is not.
- **DevOps:** Strict. LSP go-to-definition on a trait method needs exactly one impl target. Orphan impls mean the impl could be anywhere in the dependency graph. Strict rule bounds the search to two packages.
- **AI/ML:** Strict. LLMs generating `impl Trait for Type` need one clear rule: "is this my trait or my type?" Binary check, zero ambiguity. Orphan impls would require the model to reason about which package owns what across the entire dependency graph.

**Q2: Impl overlap (5-0 for no overlap, no specialization)**

- **Systems:** No overlap. Specialization sounds useful but Rust has kept it unstable for over a decade with multiple soundness holes. Each (Trait, Type) pair maps to one vtable entry. Zero runtime ambiguity.
- **Web/Scripting:** No overlap. "Most specific wins" rules are never intuitive. Adding an impl to a library silently changing behavior in downstream code is the opposite of locality of reasoning.
- **PLT:** No overlap. Specialization requires a partial ordering on impls that interacts with type inference in subtle ways. Without specialization, adding a new impl can only cause overlap errors (loud), never silent behavior changes. The helper-trait and newtype workarounds are compositional.
- **DevOps:** No overlap. Overlap errors at the impl site are actionable ("these two impls conflict, choose one"). Specialization errors are baffling ("this impl was silently superseded by a more specific one three dependencies deep").
- **AI/ML:** No overlap. One impl per (Trait, Type) is the only pattern with significant training data (Rust stable). Specialization has near-zero training data (Rust nightly only). LLMs would generate overlapping impls and be confused by the resolution rules.

**Q3: Impl placement and visibility (5-0 for package-scoped, auto-visible)**

- **Systems:** Package-scoped. The impl must live in the trait's package or the type's package — follows directly from the orphan rule. Within a package, any module is fine. Intra-package cycles are already allowed (§10.5).
- **Web/Scripting:** Package-scoped with auto-visibility. Requiring explicit impl imports would be boilerplate torture. Importing `User` should give you all of `User`'s behavior. This matches how JS/TS modules work — import a class, get all its methods.
- **PLT:** Package-scoped. Auto-visibility is the only principled choice: an impl is a fact about a (Trait, Type) pair, not an independent entity to be imported. The compiler discovers impls by following the import graph — importing either the trait or the type is sufficient.
- **DevOps:** Package-scoped. For LSP, "find all impls of Trait for Type" has a bounded search: check the trait's package and the type's package. Auto-visibility means go-to-definition never fails because of a missing impl import.
- **AI/ML:** Package-scoped with auto-visibility. Zero-boilerplate discovery. An AI importing a type should immediately be able to call all its trait methods without hunting for impl import paths. One import, complete behavior.

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

### Bootstrap Path (COMPLETE)

All three stages verified. Fixed-point proven across 6 generations.

```
Stage 0: Python compiler (legacy/py_bootstrap/pact/) ✓ [DEPRECATED]
         → compiles src/pactc.pact (Pact compiler written in Pact)
         → emits C → cc → gen1 native binary

Stage 1: gen1 (compiled by Stage 0, checked in at bootstrap/pactc_bootstrap.c) ✓
         → compiles src/pactc.pact → C → gen2 native binary

Stage 2: gen1 C output == gen2 C output → fixed point ✓
         → verified identical through gen6
         → bootstrap complete, Python interpreter no longer required
```

Self-hosting compiler: `src/pactc.pact` (amalgamated lexer + parser + codegen + driver). Uses parallel arrays instead of structs-in-lists (C backend limitation). Compiles hello, fizzbuzz, and itself.

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

## Pattern Matching Grammar — Design Rationale

### Panel Deliberation

Five panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML) voted independently on 5 questions. Each expert ran as a separate agent and returned votes without seeing other experts' reasoning.

**Q1: OR-patterns (5-0 for `|` separator)**

- **Systems:** OR-patterns compile to merged branches/jump tables — zero runtime cost. Duplicate arms make the optimizer deduplicate what the programmer already expressed. `|` is universally understood, trivially parseable.
- **Web/Scripting:** Every JS/Python dev who has touched Python 3.10 `match` knows `|` as "or" in type contexts. Comma-separated (C) would be a trap — Pact already uses commas inside tuples. `|` is unambiguous and Pact doesn't use it as a bitwise operator.
- **PLT:** OR-patterns mirror the algebraic sum type structure. The typing rule is well-studied: all alternatives must bind the same variables at the same types. This is a standard judgment in ML-family pattern calculi.
- **DevOps:** Universal syntax, LSP can offer "merge duplicate arms" quick-fixes, formatter has clear precedent from every language that supports it.
- **AI/ML:** Overwhelming training data signal from Rust, OCaml, Scala, Python 3.10, C#. LLMs will generate `|` in match arms regardless — better to accept it than produce confusing errors.

**Q2: Range patterns (5-0 for `..`/`..=`)**

- **Systems:** Range patterns = two comparisons, predictable branch. Without them, guards are opaque to exhaustiveness checker — compiler can't verify completeness or optimize dispatch. For integer-heavy matching (protocol codes, byte ranges), this matters.
- **Web/Scripting:** Guards are where developer productivity goes to die. `n if n >= 1 && n <= 5` is 21 tokens for something that should be `1..=5`. HTTP status code matching is a bread-and-butter web dev task.
- **PLT:** Exhaustiveness over discrete types with range patterns is decidable via interval arithmetic. Guards defeat the purpose of exhaustiveness checking — the compiler cannot reason about their truth. Range patterns preserve the safety guarantee.
- **DevOps:** Diagnostic goldmine. When a range match misses `256..=511`, the compiler can say exactly which interval is uncovered. Guards produce only "non-exhaustive, add wildcard" — useless.
- **AI/ML:** Fewer decision points than guards, reduces off-by-one bugs in generation. LLMs handle Rust range patterns reasonably well — decent training signal.

**Q3: Pattern binding (4-1 for `as` keyword)**

- **Systems:** `@` conflicts with annotation prefix — parsing ambiguity. `as` is already a Pact keyword, no new token. Binding+destructure is just aliasing a pointer/value — zero cost either way.
- **Web/Scripting:** Pact already uses `as` in `with...as`. It reads naturally: "match this config AS a ServerConfig with these fields." Python devs know `as` from `import x as y`. Meanwhile `@` is the annotation prefix — LLMs would hallucinate annotations inside match arms.
- **PLT:** `@` conflicts with the annotation sigil. The typing rule for `as` binding is trivial: bound name gets the scrutinee type. No interaction with the type system beyond standard variable introduction.
- **DevOps:** Context-dependent `@` is a diagnostic nightmare. Is `@foo` an annotation or a pattern binding? LSP go-to-definition, syntax highlighting, and error recovery all suffer. `as` has clear precedent.
- **AI/ML:** Pattern binding is rare — thin training data even in Rust. Fewer features = fewer decision points for LLM generation. Defer to v2. *(dissent)*

**Q4: Struct patterns in match (5-0 for full)**

- **Systems:** Gives the compiler complete visibility — direct field-offset comparisons vs opaque guard calls. Already have struct destructuring in `let`; refusing it in `match` is artificial and costs optimization opportunity.
- **Web/Scripting:** If I can destructure an enum, I should be able to destructure a struct. Field punning (`User { name, .. }`) is exactly how JS destructuring works and every web dev already knows it.
- **PLT:** Restricting struct patterns to `let` breaks compositional nested matching. `Ok(User { name, .. })` is a nested pattern — disallowing the struct layer while permitting the enum layer is unprincipled.
- **DevOps:** Inconsistency between `let` and `match` is a diagnostics anti-pattern. LSP can autocomplete field names in struct patterns, and error messages can point to specific non-matching fields.
- **AI/ML:** Rust has strong training data for struct patterns in match. LLMs handle `Struct { field, .. }` well from Rust exposure. Restricting to `let`-only contradicts what models have learned.

**Q5: Refutable vs irrefutable (5-0 for strict compile error)**

- **Systems:** `let` that can fail = hidden panic = unpredictable codegen. Strict separation means `let` always succeeds (no hidden branches, no dead panic code), `match` handles all refutable logic. Clean CFG.
- **Web/Scripting:** JS devs have been burned by "undefined is not a function" for decades. `let Some(x) = val` panicking at runtime is exactly the "works in dev, crashes in prod" bug Pact's type system prevents. The language already rejected `if let` — allowing refutable `let` would be backdooring it as a runtime panic.
- **PLT:** Refutable `let` is type-theoretically unsound — it introduces a partial function into a total context. Non-negotiable. Pattern is irrefutable iff it covers all values of the scrutinee type; single-variant enums are naturally irrefutable by this definition.
- **DevOps:** Compile error + actionable fix is the gold standard. `"refutable pattern in let, use match or ?? instead"` with a code suggestion. Warnings get ignored — developers tune them out.
- **AI/ML:** Binary rules (error vs not-error) are easiest for LLMs. Warnings are invisible during generation — the model doesn't see them in compile output. Errors feed back into iterative fix cycles.

---

## `Self` Type — Design Rationale

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

---

## Closure Capture Semantics — Design Rationale

### Panel Deliberation

Five panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML) voted independently on 3 questions.

**Q1: Capture mode — shared reference vs by-value vs inferred (3-2 for shared reference)**

- **Systems:** By-value (Option A). In a GC'd language, "by value" for heap objects means copying a pointer — 8 bytes, one register copy. Closure struct with flat fields, populated by copying locals. No indirection cells, no boxing. `let mut` snapshotted at closure creation. *(dissent)*
- **Web/Scripting:** By-value (Option A). Snapshotting mutable bindings is far more predictable than sharing them. Python's late-binding closure semantics are the single most common closure footgun. *(dissent)*
- **PLT:** Shared reference (Option B). In a GC'd language with no reference types, all bindings are GC-managed handles. Snapshotting `let mut` is a semantic trap — `count += 1` inside a closure silently mutates a copy, producing wrong results with no compiler error. Every GC'd language (OCaml, Koka, JS, Python, C#) uses shared-reference captures. For immutable bindings, shared-ref is observationally equivalent to by-value copy. The capture mode is not part of the function type.
- **DevOps:** Inferred (Option C). Immutable by-value, mutable by-ref. But acknowledged that C and B produce identical observable behavior for all cases. Critical requirement: LSP must show capture modes on hover.
- **AI/ML:** Shared reference (Option B). ~70% of closure training data (JS + Python + Go) uses shared-reference semantics. By-value silently breaks the `count += 1` mutation pattern — a silent logic bug is the worst outcome for LLM-generated code. Inferred (Option C) has zero training data for the specific inference rules; Rust's inferred capture is the #1 source of LLM errors in Rust closures.

**Q2: Explicit capture syntax (4-1 for no explicit syntax)**

- **Systems:** No syntax. If everything is always by-value, nothing to disambiguate. YAGNI. *(Note: voted for by-value in Q1, but no-syntax still applies under shared-ref — one mode = nothing to annotate.)*
- **Web/Scripting:** No syntax. Principle 2 — one way to do everything. GC'd languages don't need capture annotations.
- **PLT:** No syntax. GC eliminates the primary reason for explicit captures (Rust's `move` exists for ownership transfer; Pact has no ownership). The snapshot-via-`let` idiom covers edge cases. `move` can be added backward-compatibly in v2 if needed.
- **DevOps:** `move` keyword (Option B). Users need an escape hatch when inference is wrong. `move fn(params) { body }` forces all captures to by-value. One keyword, one behavior. `pact fmt` just puts `move` before `fn`. *(dissent)*
- **AI/ML:** No syntax. Explicit capture has ~40% LLM error rate in Rust/C++. One mode = nothing to annotate. Zero additional decision points.

**Q3: `async.spawn` mutable captures (3-2 for compile error)**

- **Systems:** Auto-copy (Option B). Falls naturally from by-value capture. `async.spawn` copies GC pointer into closure. Both tasks hold GC roots. Zero additional overhead. *(dissent)*
- **Web/Scripting:** Auto-copy (Option B). Spawned task gets own copies. No shared mutable state between tasks. Like `structuredClone` for web workers. *(dissent)*
- **PLT:** Compile error (Option A). `async.spawn` with shared mutable captures creates data races. Pact has no `Mutex`, no `Atomic`, no memory model for concurrent mutation of shared cells. Allowing this would be unsound. Immutable captures are fine — no data race potential.
- **DevOps:** Compile error (Option A). Silent correctness bugs are worst for tooling. Compile error E0650 with machine-applicable fix (snapshot via `let`, use channel, or use `Atomic[T]`). Error message should include quick-fix.
- **AI/ML:** Compile error (Option A). Data races are the #1 concurrency bug in LLM code. The compile error pushes LLMs toward the fork-join pattern (more training data, more correct). Immutable captures in spawn should be fine.

---

## Module Prelude — Design Rationale

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

---

## Effect Polymorphism — Design Rationale

### Panel Deliberation

Five panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML) voted independently on 3 questions.

**Q1: Should function types carry effects? (5-0 for explicit effects)**

- **Systems:** The evidence vector is already threaded through every call. If a callback performs effects, that must be in the type so the compiler knows which vtable slots to pass. Hiding it makes C codegen unpredictable. Pure-only means you can't even log inside a map callback — non-starter.
- **Web/Scripting:** Web devs live and breathe HOFs — map, filter, forEach, middleware. If callbacks can't carry effects, the most natural JS/TS patterns become second-class citizens. TypeScript proved function types need full expressiveness. The `!` syntax is consistent with declarations — no new concept.
- **PLT:** A function type that cannot express its effects is unsound by construction. In Koka, Frank, and every serious effect calculus, the arrow type carries an effect row because `fn(T) -> U` and `fn(T) -> U ! IO` have fundamentally different denotations. Omitting effects from function types means the type system cannot express the contract of any HOF accepting effectful callbacks — a compositionality failure.
- **DevOps:** Explicit `! IO.Log` on function types is a massive win for LSP hover and diagnostic quality. When a user hovers over a callback parameter, the tooltip should show exactly what effects it can perform. Invisible semantics would make hover info misleading. Explicit syntax gives the formatter a clear layout rule.
- **AI/ML:** LLMs generate more correct code when syntax is uniform and local. If `fn foo() -> Int ! IO` works at declaration sites but `fn(Int) -> Int` silently drops effects at type sites, that's two rules where there should be one. Every special case increases error rates.

**Q2: Form of effect polymorphism (3-2 for wildcard forwarding)**

- **Systems:** Row-polymorphic effect variables. For C codegen, `e` compiles to "pass through whatever evidence sub-vector the caller provided." Monomorphizer specializes at call sites. Wildcard loses composability — can't distinguish effect sets from two different callback parameters. *(dissent)*
- **Web/Scripting:** Wildcard `_`. Row polymorphism is theoretically correct but `fn map[T, U, e](f: fn(T) -> U ! e) -> Iterator[U] ! e` will make web developers close the tab. The `_` is familiar from TypeScript's `any` and Rust's `_` patterns. Covers the 95% case without requiring developers to understand effect variables.
- **PLT:** Row polymorphism. The only approach that preserves principal types and decidable inference. Wildcard `_` cannot unify two wildcards from different parameters, which breaks `zip_with(f, g)` where both callbacks must share the same effect set. Give the variable a name; it costs one generic parameter and buys full expressiveness. *(dissent)*
- **DevOps:** Wildcard `_`. Row polymorphism produces horrific error messages — effect variable unification errors are nearly impossible for users to parse. `_` covers the 95% case and produces actionable diagnostics. Incremental compilation benefits since `_` is a local marker rather than a constraint variable propagating through the call graph.
- **AI/ML:** Wildcard `_`. Koka-style effect variables have vanishingly small training data. Models will hallucinate variable names, forget to thread `e` through return types, or invent nonsensical combinations. `_` is a single token learnable from one example, doesn't introduce naming decisions (Principle 2), and doesn't require reasoning about effect unification.

**Q3: Timeline (4-1 for fn-type effects v1, polymorphism v2)**

- **Systems:** Full in v1. If function types ship without effect information, every HOF signature becomes a lie you have to break later. Retrofitting changes calling conventions and ABI. The compilation strategy is known. Deferring borrows complexity at loan-shark interest rates. *(dissent)*
- **Web/Scripting:** Fn-type effects v1, polymorphism v2. Ship the `fn(T) -> U ! IO` syntax now so the type system is complete. Don't block v1 on getting polymorphism perfect — iterate after real users hit real friction.
- **PLT:** Fn-type effects v1, polymorphism v2. Pragmatic concession. Shipping `fn(T) -> U ! E1, E2` means library authors can write monomorphic effectful callbacks today. The type system remains sound; you just lose generality. The critical invariant: do not ship v1 with pure-only function types, because retrofitting `!` onto arrow types is breaking, while adding effect variables is additive.
- **DevOps:** Fn-type effects v1, polymorphism v2. Gives LSP and diagnostics a solid foundation. Trying to ship both at once means half-baked tooling for effect variables at launch. Better to have solid tooling for a smaller feature set.
- **AI/ML:** Fn-type effects v1, polymorphism v2. The foundation (`fn(T) -> U ! IO.Log`) is simple enough to ship now and unblocks real patterns. Deferring everything means v1 ships with a known hole that forces workarounds which become the patterns LLMs learn and then have to unlearn.

---

## Handler Type System — Design Rationale

### Panel Deliberation

Five panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML) voted independently on 5 questions.

**Q1: Handler[E] type identity (5-0 for generic type)**

- **Systems:** `Handler[E]` compiles to one vtable struct per effect. The type parameter is erased at codegen — at C level, `Handler[DB]` and `Handler[IO]` are different structs with different function pointer layouts. The generic type constructor is a source-level abstraction over effect-specific vtables. Correct and zero-cost.
- **Web/Scripting:** A single `Handler[E]` type makes the mental model simple — handlers are values, parameterized by which effect they handle. No need for separate `DBHandler`, `IOHandler` types. Matches how TypeScript generics work.
- **PLT:** `Handler[E]` is a type constructor indexed by effect declarations, analogous to `List[T]` indexed by types. The kinding rule is `Handler : Effect -> Type`. Standard parametric polymorphism over the effect namespace.
- **DevOps:** One type constructor means one autocomplete pattern, one hover format, one diagnostic template. LSP shows `Handler[DB]` uniformly regardless of which effect.
- **AI/ML:** `Handler[E]` is the pattern in every code example. LLMs already generate it correctly from existing spec examples. Formalizing what's already in practice.

**Q2: Effect subtyping on handlers (3-2 for implicit projection)**

- **Systems:** Implicit projection. `Handler[DB]` used where `Handler[DB.Read]` expected → compiler extracts `read` slot from the DB vtable and builds a projected handler. Not subtyping — a mechanical extraction. No runtime dispatch, no vtable indirection. Clean codegen.
- **Web/Scripting:** Covariant subtyping. If `DB > DB.Read` in the effect hierarchy, then `Handler[DB]` should be a subtype of `Handler[DB.Read]` — standard variance. Projection is an implementation detail that shouldn't leak into the mental model. *(dissent)*
- **PLT:** Implicit projection. True subtyping on handlers would require the type system to track variance of the handler type constructor with respect to effects — complexity that buys nothing over mechanical slot extraction. Projection is semantically transparent and verifiable.
- **DevOps:** Implicit projection. The compiler generates the projected vtable — users see a clean "OK" at the call site. Error messages for the reverse direction ("Handler[DB.Read] cannot satisfy Handler[DB]") are precise and actionable.
- **AI/ML:** Covariant subtyping. "DB is bigger than DB.Read, so Handler[DB] works where Handler[DB.Read] is needed" is the simplest mental model. LLMs reason about subtyping better than projection mechanics. *(dissent)*

**Q3: Generic handler parameters (4-1 for no generics v1)**

- **Systems:** No generics v1. Effect-kinded generics require a kinding system (`E: Effect`), monomorphization over effects, and interaction with evidence-passing. Doable but adds compiler complexity. Ship concrete handlers, add generics with named effect variables in v2.
- **Web/Scripting:** No generics v1. `Handler[DB]` and `Handler[IO]` are what people write. Generic-over-effect functions are a library-author concern, not a day-one need.
- **PLT:** Effect-kinded generics now. `fn apply_handler[E: Effect](h: Handler[E], f: fn() ! E)` is the principled way to write handler combinators. Without it, every handler combinator must be written per-effect, defeating the purpose of first-class handlers. *(dissent)*
- **DevOps:** No generics v1. Simpler LSP, simpler diagnostics. Concrete handler types are easier to display and reason about in tooling. Generics can be added without breaking changes.
- **AI/ML:** No generics v1. Effect-kinded generics have zero training data. LLMs would hallucinate syntax. Concrete handlers cover all practical v1 use cases (testing, DI, sandboxing).

**Q4: Handler storage (4-1 for full first-class)**

- **Systems:** Restricted. Handlers stored in long-lived data structures (struct fields, collections) risk holding stale vtable references if the handler's captured state is invalidated. Limit to local variables, function parameters, and `with` blocks. Storing in structs requires `'static`-like lifetime guarantee. *(dissent)*
- **Web/Scripting:** Full first-class. Handlers are GC-managed values — no dangling references by construction. Storing a handler in a struct field is identical to storing any other GC-managed value. Restricting storage would make the `TestEnv` pattern impossible.
- **PLT:** Full first-class. In a GC'd language, all values have the same storage semantics. Artificially restricting handler storage introduces a second class of values — exactly the complexity Pact rejected by choosing GC over ownership. Handlers are values; values can be stored anywhere.
- **DevOps:** Full first-class. The `TestEnv { db: Handler[DB], io: Handler[IO] }` pattern is the natural way to build test fixtures. Restricting it forces workarounds (factory functions, closures) that are strictly worse.
- **AI/ML:** Full first-class. Every GC'd language allows storing any value anywhere. Restrictions would be a novel pattern with zero training data, guaranteed to confuse LLMs.

**Q5: Handler completeness (5-0 for partial with auto-delegation)**

- **Systems:** Partial + auto-delegation. Most handler use cases override 1-2 operations (logging wrapper, restricted sandbox). Requiring all operations makes simple wrappers verbose. Auto-delegation to `default.op(args)` is the evidence-passing equivalent of prototype chain delegation — the enclosing handler's vtable slot is called.
- **Web/Scripting:** Partial + auto-delegation. Middleware pattern: override what you care about, pass through everything else. Express/Koa devs write `next()` constantly — `default.op(args)` is the same concept. Full completeness would make every handler as verbose as the full effect definition.
- **PLT:** Partial + auto-delegation. The handler algebra requires a default case for compositional reasoning — a handler that only overrides `read` should compose with any handler that provides `write` and `admin`. Auto-delegation provides this. Explicit `default.op(args)` remains available for custom forwarding logic.
- **DevOps:** Partial + auto-delegation. Compiler generates the forwarding code, zero boilerplate. Diagnostics can still warn when a handler overrides nothing (likely a mistake). LSP can show which operations are auto-delegated on hover.
- **AI/ML:** Partial + auto-delegation. LLMs generating test handlers will typically only mock the operations under test. Requiring completeness means the model must generate stubs for every operation — more tokens, more error surface, more maintenance burden when operations are added to an effect.

---

## Derive Mechanics + Clone Trait — Design Rationale

### Panel Deliberation

Five panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML) voted independently on 4 questions. Resolves two Tier 2 gaps: "Derive mechanics" and "Clone trait".

**Q1: Clone semantics in GC context (3-2 for logical copy)**

- **Systems:** Logical copy (Option C). In a GC'd runtime, "clone" means allocate a new struct shell, copy field values (GC pointers). Deep copy is an O(n×m) allocation storm for nested collections with cycle risk. The C backend emits a single `malloc` + `memcpy` for struct fields — clean, predictable, zero recursion. If users need deep independence, a separate `DeepClone` trait with explicit recursion is the right tool.
- **Web/Scripting:** Logical copy (Option C). This is exactly JS's `{...obj}` spread or Python's `copy.copy()`. Web developers already understand one-level semantics — the clone shares nested references. This is the dominant pattern in GC'd languages and matches the largest body of LLM training data.
- **PLT:** Logical copy (Option C). In ML/OCaml tradition, record copy is structural — `{r with field = new_value}` copies the record, shares nested references. Deep copy is a separate concern requiring recursion schemes. The distinction is principled and well-understood in PL literature.
- **DevOps:** Deep copy (Option B). A `clone()` that doesn't give you an independent value is semantically vacuous — it's just aliasing with extra allocation. When you clone a config struct, you expect modifying the clone doesn't affect the original. Shallow clone violates the principle of least surprise. *(dissent)*
- **AI/ML:** Deep copy (Option B). Training data overwhelmingly associates "clone" with "independent copy." When an LLM generates `let backup = config.clone()` and then mutates `backup`, it expects isolation. Shallow clone causes aliasing bugs that are invisible at the call site. *(dissent)*

**Q2: Debug trait design (5-0 for separate trait)**

- **Systems:** Separate `Debug` trait with `fn debug(self) -> Str`. No supertrait relationship with `Display`. Debug emits structural representation (`TypeName { field: value }`), Display emits user-facing strings. At C level, separate vtable slots — no coupling. The compiler can optimize away unused Debug impls in release builds.
- **Web/Scripting:** Separate `Debug`. Maps to `console.log()` vs `.toString()` distinction in JavaScript. Developers expect one format for logging/debugging and a different one for user-facing output. No supertrait means implementing Display doesn't require Debug and vice versa.
- **PLT:** Separate `Debug`. Haskell's `Show` conflates both roles and regrets it. Rust's `Debug` vs `Display` split is one of its best ergonomic decisions. The structural representation is mechanical and derivable; the user-facing string requires human judgment.
- **DevOps:** Separate `Debug`. Structured logging needs consistent machine-parseable output. `Debug` gives `"User { name: \"Alice\", age: 30 }"` which tools can parse. `Display` gives `"Alice (alice@example.com)"` for humans. Different audiences, different traits.
- **AI/ML:** Separate `Debug`. LLMs generating debug output and user-facing output are clearly different tasks. Having them in separate traits means the model picks the right one from context. No ambiguity about which to call.

**Q3: Derive codegen algorithm (5-0 for inferred bounds + auto supertrait)**

- **Systems:** Inferred bounds. The compiler scans field types, collects trait requirements, emits `where` clauses. For `@derive(Eq)` on `Pair[A, B]`, field `first: A` needs `A.eq()` → emit `where A: Eq`. Supertrait auto-derivation: `@derive(Ord)` checks for existing `Eq` impl, derives one if missing. Mechanical, deterministic, zero user annotation.
- **Web/Scripting:** Inferred bounds. "It just works" — the developer writes `@derive(Eq)` and the compiler figures out the bounds. No manual `where` clauses on derived impls. This is TypeScript-level ergonomics applied to trait derivation.
- **PLT:** Inferred bounds with auto supertrait. This follows the standard derivation algorithm from Haskell/Rust: derive obligations propagate through field types and supertrait relationships. Sound and complete for the derivable trait set.
- **DevOps:** Inferred bounds. LSP can show the inferred bounds on hover. Error messages point to the specific field that can't satisfy the bound. Clean diagnostic story.
- **AI/ML:** Inferred bounds. LLMs write `@derive(Eq)` and move on. No need to think about generic constraints — the compiler handles it. Reduces token count and error surface.

**Q4: Error reporting for non-derivable fields (5-0 for field-level errors)**

- **Systems:** Report all failing fields in one pass. The compiler walks every field, collects failures, emits a single diagnostic with all of them. No "fix one, compile, find the next" loop. Batch error reporting matches the existing diagnostic strategy.
- **Web/Scripting:** All fields at once. TypeScript shows all type errors in one pass. Developers expect to see the full picture, not a drip feed.
- **PLT:** All fields. Standard practice — GHC, rustc, and OCaml all report multiple derivation failures in a single compilation unit.
- **DevOps:** All fields. CI pipelines get a complete error list in one build. No wasted cycles on iterative fix-compile cycles.
- **AI/ML:** All fields. An AI agent in a generate-compile-fix loop needs all errors at once to fix them in a single pass. Reporting one at a time forces O(n) compilation rounds for n failing fields.

---

## String Methods — Design Rationale

### Panel Deliberation

Five panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML) voted independently on 5 questions. Resolves Tier 2 gap: "String methods".

**Q1: Trait organization (5-0 for generic Sized + StrOps)**

- **Systems:** Generic `Sized` trait. `.len()` and `.is_empty()` compile to one vtable slot per collection type. Sharing the trait across `Str`, `List`, `Map`, `Set` means one evidence-passing path for size checks in generic code. The `StrOps` catch-all avoids vtable fragmentation — one struct with all string function pointers, cache-friendly.
- **Web/Scripting:** Generic `Sized` + `StrOps`. Every web developer expects `.len()` to work the same way on strings and arrays. A shared `Sized` trait makes this intuition correct. `StrOps` as a single trait mirrors how Iterator works — one import, all methods available via LSP autocomplete.
- **PLT:** `Sized` as a generic trait is well-founded — it provides a uniform interface for the cardinality observation on finite containers. Separating it from `StrOps` respects the trait coherence model: `Sized` is implementable by any container, while `StrOps` is string-specific. This is the standard algebraic factoring.
- **DevOps:** `Sized` + `StrOps`. LSP autocomplete on `s.` shows `len()` and `is_empty()` from `Sized`, plus all string methods from `StrOps`. Two traits, clean categorization. Resolving the Collection methods gap simultaneously is a tooling win — `.len()` hover shows `Sized.len` for all types.
- **AI/ML:** Shared `Sized` trait matches training data where `.len()` works uniformly across collection types. One `StrOps` trait minimizes import decisions — LLMs don't need to choose which string trait to import. Follows the Iterator precedent that models already understand.

**Q2: v1 method surface area (5-0 for 15 existing methods)**

- **Systems:** Codify what exists. The self-hosting compiler already uses these 15 methods; each maps to a C runtime function. No speculative surface area — every method has a known caller. Adding methods later is additive; removing is breaking.
- **Web/Scripting:** The 15 existing methods cover the JS/Python string API core that web developers reach for daily. `trim_start`/`trim_end` and `pad_left`/`pad_right` are nice-to-have but not blocking — they can be added in a point release. Ship what's tested.
- **PLT:** Minimal committed API surface. Each method in the trait is a coherence obligation — every implementor must provide it. Starting with 15 well-understood methods minimizes the proof burden. Default methods can extend the surface later without breaking existing impls.
- **DevOps:** 15 methods = manageable autocomplete list. Expanded 22 would add noise. Every method in the spec needs LSP descriptions, error messages, and documentation. Ship the known set, extend based on friction logs.
- **AI/ML:** 15 methods match the common string operations in training data. Expanding to 22 adds methods with lower frequency in training data (`pad_left`, `repeat`) increasing hallucination risk for parameter order. The Iterator pattern proved that starting minimal and extending works.

**Q3: Unicode semantics (3-2 for codepoint-default dual API)**

- **Systems:** Byte-oriented defaults with honest names (Option D). `.len()` = `strlen()` is O(1) and maps to a single C call. Codepoint-length is O(n) — hiding that behind `.len()` violates the principle that simple syntax implies simple cost. Name the operations honestly: `.byte_len()`, `.byte_at()`, `.codepoint_at()`. *(dissent)*
- **Web/Scripting:** Dual API with codepoint default (Option C). Web developers think in characters, not bytes. Python, JavaScript (mostly), and Ruby all have codepoint-oriented `.length`. `.len()` returning bytes would surprise 90% of users — "hello" should have length 5, and "café" should have length 4, not 5. Byte access via `byte_` prefix for the rare cases that need it.
- **PLT:** Byte-oriented defaults with honest names (Option D). The type system should not lie about complexity. If `.len()` is O(n), that's a hidden cost the type signature doesn't reveal. Naming matters: `.byte_len()` is honest about what it counts, `.codepoint_count()` is honest about its cost. Option D preserves the correspondence between names and semantics. *(dissent)*
- **DevOps:** Dual API with codepoint default (Option C). Codepoint `.len()` matches what developers expect in diagnostics and error messages — "string has length 4" should mean 4 characters. The `byte_` prefix is clear and discoverable via LSP autocomplete. Performance-sensitive code can opt into byte methods explicitly.
- **AI/ML:** Dual API with codepoint default (Option C). Training data overwhelmingly associates `.len()` with character count. LLMs generating `if name.len() > 50` mean "50 characters" not "50 bytes." Byte-oriented default would cause systematic off-by-one bugs in every non-ASCII context. The `byte_` prefix is unambiguous and won't be hallucinated by models trained on Python/JS patterns.

**Q4: Parsing methods (4-1 for named methods on Str)**

- **Systems:** Named methods. `.parse_int()` compiles to a direct C function call — no vtable dispatch, no generic monomorphization overhead. The method name in the binary's symbol table is greppable. Delegating to `TryFrom` under the hood keeps the trait system consistent while giving call sites zero-cost direct dispatch.
- **Web/Scripting:** Named methods. `str.parse_int()` is exactly what Python's `int(str)` and JS's `parseInt(str)` developers expect, just in method-call form. LSP autocomplete on `s.parse_` shows available parse targets. Far more discoverable than `Int.try_from(s)` which requires knowing the target type has a `TryFrom` impl.
- **PLT:** TryFrom only (Option A). Named methods on `Str` create ad-hoc coupling — `Str` must know about `Int` and `Float` at definition time. `TryFrom` is parametric: the conversion knowledge lives with the target type, not the source. Adding `parse_int()` to `Str` violates the open-world assumption of trait-based dispatch. *(dissent)*
- **DevOps:** Named methods. `s.parse_` in autocomplete immediately shows `parse_int`, `parse_float` — zero lookup cost. `Int.try_from(s)` requires the developer to know both the target type and that `TryFrom` exists. Named methods are the discoverability sweet spot for tooling.
- **AI/ML:** Named methods. `s.parse_int()` is a single-token decision that models get right from Python/JS training data. `Int.try_from(s)` requires generating the correct target type first, then knowing the trait — two decision points. Generic `.parse[T]()` requires type inference context that models frequently get wrong.

**Q5: String building (5-0 for join now, StrBuf deferred)**

- **Systems:** `List[Str].join()` is O(n) with a single allocation — measure total length, allocate, copy. No intermediate allocations, no amortized realloc. `StrBuf` adds a mutable type to the language surface that requires growth-factor decisions and realloc strategy — defer until profiling data from real Pact programs shows it's needed.
- **Web/Scripting:** `.join()` is the pattern every web developer knows from `Array.join()`. It covers the 95% case (building strings from parts). `StrBuf` is a premature optimization for v1 — most programs build strings with interpolation and occasionally join a list. YAGNI, ship `join()`, add `StrBuf` when someone needs it.
- **PLT:** `List[Str].join()` is a fold with a separator — algebraically clean. It doesn't require new types or mutable state. `StrBuf` would be the first mutable non-collection type in the language, requiring design decisions about growth semantics and trait implementations. Defer to v1.1 when the design space is better understood.
- **DevOps:** `join()` now. One method, one signature, one autocomplete entry. `StrBuf` is an entire type with its own methods, its own documentation, its own error messages. Ship the simple thing, add complexity when the friction log demands it.
- **AI/ML:** `join()` has massive training data from every language. LLMs generate `parts.join(", ")` correctly at near-100% rates. `StrBuf` would be a novel type with zero training data — guaranteed hallucination target. Defer until there's enough Pact-specific training data to teach models the builder pattern.

---

## Collection Methods — Design Rationale

### Panel Deliberation

Five panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML) voted independently on 5 questions. Each expert ran as a separate agent and returned votes without seeing other experts' reasoning.

**Q1: Trait organization — per-type vs generic shared vs hybrid (5-0 for hybrid: shared Contains + per-type)**

- **Systems:** Hybrid. `Contains[T]` is justified — containment has identical semantics across collections. But `Indexable[K,V]` or `Growable[T]` are false unifications: `List.get(Int)` and `Map.get(K)` have fundamentally different memory access patterns (contiguous vs hash lookup). Per-type traits let the C backend emit type-specific code without trait dispatch indirection for hot-path operations.
- **Web/Scripting:** Hybrid. Web devs expect `contains`/`includes` to work uniformly across collections — Python's `in`, JS's `.includes()/.has()`. Per-type for the rest because List, Map, and Set have genuinely different semantics (push vs insert-with-key); forcing them into shared abstractions creates leaky APIs.
- **PLT:** Hybrid. A pure per-type approach misses shared algebraic structure (the point of traits). Full generic conflates fundamentally different structures. `Contains[T]` is a legitimate shared predicate (membership testing is universal set-theoretic), while per-type traits handle operations with genuinely different signatures.
- **DevOps:** Hybrid. Shared `Contains[T]` is gold for tooling — LSP resolves `.contains(` once for all collections. Per-type traits keep autocomplete focused. Generic traits like `Indexable` produce confusing diagnostics: "type X doesn't implement Indexable" is harder to act on than "type X doesn't implement MapOps."
- **AI/ML:** Hybrid. Shared `Contains[T]` minimizes generation errors (most common LLM pattern: "is X in collection"). Per-type traits keep method discovery unambiguous — models don't confuse List methods with Map methods.

**Q2: List[T] method surface (3-2 for expanded: 12 methods)**

- **Systems:** 8 methods (Option A). `insert`/`remove` at arbitrary indices are O(n) on contiguous arrays — including them signals they're cheap when they're not. `index_of` and `last` are expressible via iterator methods already in the spec. Keep the core API tight. *(dissent)*
- **Web/Scripting:** 12 methods (Option B). `indexOf`, `splice`/`insert`, `remove`, and `last` are bread-and-butter operations in web code. Leaving them out means everyone writes the same helpers on day one.
- **PLT:** 8 methods (Option A). The 8-method surface covers core algebraic operations on sequences. `insert`/`remove` are O(n) and advertising them as first-class methods violates least-surprise regarding performance. *(dissent)*
- **DevOps:** 12 methods (Option B). `insert`, `remove`, `index_of`, and `last` are methods people reach for constantly. 12 methods is table stakes for a list type. Every time someone hand-rolls these, that's friction and a potential bug.
- **AI/ML:** 12 methods (Option B). LLMs trained on Python/Rust/JS constantly generate `insert`, `remove`, `index_of`, `last`. Omitting them causes hallucinated methods or verbose workarounds.

**Q3: Map[K,V] method surface (3-2 for expanded: 8 methods)**

- **Systems:** 6 methods (Option A). `entries` is sugar for what `IntoIterator` already gives (Map yields `(K, V)` tuples). `get_or_default` is one line with `??`. Six methods keep the vtable small and C codegen simple. *(dissent)*
- **Web/Scripting:** 8 methods (Option B). `entries` is used constantly when iterating maps, and `get_or_default` eliminates the most common Map boilerplate pattern (Python's `dict.get(k, default)`).
- **PLT:** 6 methods (Option A). Maps are finite functions K→V; 6 methods precisely capture CRUD plus canonical projections. `get_or_default` conflates two concerns better expressed as `map.get(k) ?? default`. *(dissent)*
- **DevOps:** 8 methods (Option B). `entries` is critical for iteration and debugging. `get_or_default` eliminates a massive class of "key not found" runtime errors.
- **AI/ML:** 8 methods (Option B). `entries` and `get_or_default` are extremely high-frequency LLM patterns. `get_or_default` eliminates the "check then get" anti-pattern models frequently generate incorrectly.

**Q4: Set[T] method surface (3-2 for core: 4 methods)**

- **Systems:** Core 4 (Option A). `union` is worth including because it's non-trivial to implement correctly in userspace. `intersection`/`difference` are expressible as iterator filter chains. Most code only uses `contains` and `insert`.
- **Web/Scripting:** Core 4 (Option A). Web developers rarely do set algebra beyond union. The 95% case is covered. Set algebra can be added later without breaking anything — YAGNI.
- **PLT:** Full algebra (Option B). Sets form a Boolean algebra under union, intersection, difference, and symmetric difference. Omitting these is like defining a numeric type without subtraction. *(dissent)*
- **DevOps:** Full algebra (Option B). If you're going to have a Set type at all, you need intersection and difference. Without them, developers will roll their own buggy versions. *(dissent)*
- **AI/ML:** Core 4 (Option A). Full set algebra appears rarely in generated code. Small surface means models are less likely to confuse method names and signatures.

**Q5: Construction and mutability (5-0 for `Type.new()` + `let mut`)**

- **Systems:** `Type.new()` + `let mut`. Mutability at the binding, not the type. C backend can emit `const` qualifiers for immutable bindings. Split types double the surface for no gain with GC. Literal-only makes empty construction awkward.
- **Web/Scripting:** `Type.new()` + `let mut`. Most familiar for devs from Rust/Swift/Kotlin, straightforward for JS/Python devs. Split types create confusion and double the API surface. Literal-only breaks the `Type.new()` pattern already in the compiler.
- **PLT:** `Type.new()` + `let mut`. Mutability is a property of the binding, not the type — same insight as ML's `ref`. Split types double the type surface and create trait coherence nightmares (do both implement `Sized`?). `Type.new()` has clear formal semantics.
- **DevOps:** `Type.new()` + `let mut`. LSP flags mutation on non-mut bindings at edit time. `let mut` is greppable, lintable. Split types double surface for autocomplete, docs, and errors. `Type.new()` is unambiguous for tooling.
- **AI/ML:** `Type.new()` + `let mut`. Most consistent with Rust-influenced training data. LLMs handle "declare mutable, then mutate" well. Split types doubles type vocabulary and confuses models.

---

## Display Format Protocol — Design Rationale

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

---

## FFI Type Mapping — Design Rationale

### Panel Deliberation

Five panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML) voted independently on 3 questions. Resolves Tier 3 gap: "FFI type mapping."

**Q1: Pointer type model (4-1 for non-null `Ptr[T]`, `Ptr[T]?` nullable)**

- **Systems:** Non-null default (Option B). Maps cleanly to `T*` in C. Null-checks at FFI boundaries are zero-cost for the non-null path. Separating const/mut adds type system complexity with no codegen benefit — C enforces const on its side, not Pact.
- **Web/Scripting:** Non-null default (Option B). Reuses the nullable pattern every TS/Kotlin/Swift dev already knows. `T` vs `T?` is universal. Option A (everything nullable) is C's footgun. Option C (const/mut) adds a concept nobody writing a wrapper cares about.
- **PLT:** Non-null default (Option B). Preserves the Curry-Howard correspondence Pact exploits via `Option[T]`. Nullability IS the partiality monad — encoding it in `Option` means existing elimination forms (`match`, `??`) compose with pointer types with zero ad-hoc rules.
- **DevOps:** Non-null default (Option B). Reuses existing `Option`/`?` diagnostic infrastructure. LSP hover can distinguish "guaranteed non-null" vs "may be null." Autocomplete surface stays small.
- **AI/ML:** Single nullable `Ptr[T]` (Option A). Zero decision points. LLMs generating FFI code already struggle with C pointer semantics; adding a nullability decision increases error rates. *(dissent)*

**Q2: Pointer operations (5-0 for minimal + deref/write/null)**

- **Systems:** Option B. Option A is too minimal — you'd need C shims for every pointer read/write. `deref()` and `write(T)` map to single load/store instructions in C. Option C's `cast[U]()` and `offset(Int)` are pointer arithmetic footguns in a GC'd language.
- **Web/Scripting:** Option B. Option A has no deref — can't read what a pointer points to. Option B has exactly the four things a wrapper author needs: read, write, null-check, null construction. Option C (`cast`, `offset`, `free`) are expert footguns.
- **PLT:** Option B. `deref` is correctly typed as partial — return MUST be `Option[T]`. Option A is practically unsound (can't inspect values without FFI round-trips). Option C's `cast[U]()` destroys parametricity — it's `unsafeCoerce` and cannot be given a sound typing rule.
- **DevOps:** Option B. Gives the compiler enough info to emit structured null-safety warnings. Option A has zero diagnostic story for null derefs. Option C's `cast`/`offset` create pointer arithmetic errors nearly impossible to diagnose well.
- **AI/ML:** Option B. Covers exactly the patterns LLMs reach for. Option A's 3-op minimum causes hallucination: the LLM "knows" deref should exist and will generate it anyway. Option C's full surface creates decision paralysis.

**Q3: Lifetime and cleanup (3-2 for scoped `ffi.scope()` via Closeable)**

- **Systems:** Hybrid (Option D). Two real FFI patterns: short-lived marshaling (scope/arena) and long-lived opaque handles (GC finalizer). Neither alone suffices. *(dissent)*
- **Web/Scripting:** Hybrid (Option D). "Don't think about it" (GC) for the common case, deterministic cleanup (`with` block) when C requires explicit free. Matches Python `with` and JS explicit resource management. *(dissent)*
- **PLT:** Scoped (Option C). Only choice giving lexically scoped lifetime — minimal structure for soundness without linear types. Composes with existing `Closeable`. `scope.take(ptr)` is the affine typing escape hatch. GC finalizers are unsound for ordered resources.
- **DevOps:** Scoped (Option C). Direct analog to existing `with-resource`/Closeable pattern. Reuses E0601 scope-escape diagnostics. Only option where the compiler can actually help catch leaks.
- **AI/ML:** Scoped (Option C). Maps to Python's `with`, Kotlin's `use`, C#'s `using`. LLMs generate correct scoped cleanup ~85% of the time vs ~70% for manual free. One pattern, high accuracy, zero decision points.

**Resolution:** Scoped `ffi.scope()` is the primary mechanism, with standalone `alloc_ptr` as a GC-registered fallback for trivial cases. This satisfies the Sys/Web concern (both patterns available) while maintaining the PLT/DevOps/AI preference for scope-first design.

---

## Error Catalog — Design Rationale

### Panel Deliberation

Five panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML) voted independently on 5 questions. Resolves Tier 3 gap: "error codes referenced but no complete catalog."

**Q0: Identification scheme — names vs codes vs hybrid (3-2 for names primary)**

- **Systems:** Hybrid — both visible in terminal. Codes are searchable, greppable, copy-pastable. Names add value but shouldn't replace codes. *(dissent)*
- **Web/Scripting:** Hybrid — TS-familiar DX with both in output. *(dissent)*
- **PLT:** Names primary. Self-documenting, collision-proof by construction (namespace is unbounded). Work as suppression IDs (`@allow(NonExhaustiveMatch)`). Codes stay in JSON as compact alias.
- **DevOps:** Names primary. LSP hover shows the name, not a number. Names are stable API — frozen once published. CLI `pact explain NonExhaustiveMatch` is discoverable.
- **AI/ML:** Names primary. Python exception names are the most represented error pattern in LLM training data. `NonExhaustiveMatch` is self-explanatory; `E0004` requires a lookup table. Names survive context window compression better than codes.

**Q1: Organization — category ranges vs prefixes vs flat (4-1 for category ranges)**

- **Systems:** Clean-up-current — fix collisions, no new scheme. Adding ranges is over-engineering for 30 codes. *(dissent)*
- **Web/Scripting:** Category ranges. E00xx-E10xx gives room for growth. Browsing a range tells you the domain.
- **PLT:** Category ranges. Mirrors Rust's proven organization. Numeric ranges partition the code space cleanly.
- **DevOps:** Category ranges. CI rules like "fail on any E05xx" (effect errors) become trivial. Range-based filtering is a real operational tool.
- **AI/ML:** Category ranges. Training data from Rust/C# uses ranged codes. LLMs can infer category from code prefix.

**Q2: Collision handling — reassign vs reserve (5-0 for reassign)**

All panelists agreed: reassign unique IDs to every collision. Reserving ranges for "same code, different meaning" defeats the purpose of having codes at all. Eight reassignments were identified and applied.

**Q3: Documentation format — table vs detailed explain (4-1 for table + deferred explain)**

- **Systems:** Table. One-line descriptions suffice for a reference. Detailed `--explain` is a future tooling concern, not a spec concern.
- **Web/Scripting:** Full Rust-style explain now. Every error should have a prose explanation with examples from day one. *(dissent)*
- **PLT:** Table. The spec examples already serve as the "explain" for each error. A separate prose catalog duplicates them.
- **DevOps:** Table. Ship the catalog now, add `pact explain` tooling later. Perfect is the enemy of done.
- **AI/ML:** Table. LLMs parse tables efficiently. Prose explanations add tokens without proportional value when the spec sections already contain examples.

**Q4: Location — standalone file vs embedded in spec (5-0 for standalone)**

All panelists agreed: standalone `ERROR_CATALOG.md` at repo root. Embedding in a spec section makes the catalog hard to find and forces readers to navigate through prose. Standalone file is directly linkable, greppable, and serves as a single source of truth.

---

## Testing Framework — Design Rationale

### Panel Deliberation

Five panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML) voted independently on 4 questions. Resolves Tier 3 gap: "assert(), assert_eq(), panic() used in test blocks but assertion API not defined."

**Q1: Custom assertion messages (3-2 for optional trailing message)**

- **Systems:** Option B. Optional `Str` is zero-cost when omitted — compiler emits two different call sites, no runtime branch. Expression text alone isn't sufficient context for multi-layer test scenarios. Interpolation (C) adds compilation complexity for marginal gain — Pact's universal string interpolation already works in the message argument.
- **Web/Scripting:** Option C. String interpolation in assertion messages is table stakes for DX. Every modern language lets you embed values in error messages. Option A's auto-generated messages can't infer domain context. *(dissent)*
- **PLT:** Option B. Clean typing rule: `assert(cond: Bool, msg: Str = "")`. The message is a plain `Str` — Pact's regular string interpolation handles `"balance was {balance}"` before it reaches `assert`. Option C is unnecessary since interpolation is a property of the string literal, not the intrinsic.
- **DevOps:** Option C. CI/CD triage at 2am needs context like `"withdrawal of {amount} from account {acct_id}"` without reading source. JSON output should have a separate `message` field. *(dissent)*
- **AI/ML:** Option B. Dominant pattern across Python, Rust, Go, JS training data. Interpolation (C) adds format-string decision points. A useless message is cheaper than a compile error from trying to pass one when not allowed.

**Resolution note:** B and C are functionally equivalent in Pact — since all strings support `{expr}` interpolation, `assert(cond, "value was {x}")` works under Option B. The vote is really about whether the *intrinsic* needs special interpolation support (no — the *string literal* handles it).

**Q2: `panic()` function (5-0 for available everywhere)**

- **Systems:** `panic` is `__builtin_unreachable()` with a message. Every real program has invariants that can't be expressed in the type system. `Never` return type lets the optimizer eliminate dead code. Overuse mitigated via lint, not hard ban.
- **Web/Scripting:** Non-negotiable for DX. Every mainstream language has an escape hatch for "this should never happen." Forcing `Result` for truly impossible states creates boilerplate.
- **PLT:** `panic(msg: Str) -> Never`. `Never` (bottom) inhabits every type, standard in type theory. Panic is divergence, not a handleable algebraic effect — tracking it as an effect would poison every function signature. Koka separates `div` from algebraic effects for exactly this reason.
- **DevOps:** Production code needs unrecoverable error paths. Critical requirement: JSON output must distinguish `"status": "failed"` (assertion) from `"status": "panicked"` (unexpected panic) for CI categorization.
- **AI/ML:** `panic!()`/`raise` are deeply embedded in training data. Test-only panic means LLMs generate code that compiles in one context but not another.

**Q3: Pattern assertion — `assert_matches` (4-1 for fourth built-in)**

- **Systems:** Option A. The `match + assert(false)` pattern produces "assertion failed: false at line 43" — zero information about the actual variant. `assert_matches` captures the actual discriminant and Display representation. Binding extraction (C) is over-engineered for v1.
- **Web/Scripting:** Option A. The match-assert pattern is an embarrassing DX failure. `assert_matches` is standard in Rust, Jest, pytest. Keep it simple — no binding support.
- **PLT:** Option A. Principled sugar for `match e { p => (), _ => panic(...) }`. Well-typed when `e: T` and `p` is a refutable pattern over `T`. Must be a syntactic form (second arg is a pattern, not an expression). Binding support (C) deferred to a future `let_assert`.
- **DevOps:** Option A. Compiler has pattern structure at compile time for better failure messages. JSON can include `"expected_pattern"` and `"actual"` as structured fields.
- **AI/ML:** Option B. Training data is thin (Rust nightly-only). Second argument being a *pattern* not an *expression* is exactly the kind of distinction LLMs get wrong. `match` + `panic()` is reliably generated from existing training data. *(dissent)*

**Q4: Assertion failure output format (4-1 for expression introspection)**

- **Systems:** Option C. Compiler already has the full AST. Decomposing `assert(a > b)` into sub-expression values costs nothing at compile time, only emits extra code on the cold failure path. Option B's "expected/actual" labels are misleading — which argument is "expected"? Introspection bounded to one level of sub-expressions. For `assert_eq`, preserve left/right format.
- **Web/Scripting:** Option C. Power Assert is the single biggest testing DX win a language can ship. Groovy and Elixir adopted it. Since assertions are compiler intrinsics, the compiler *has* the AST and *can* decompose sub-expressions. Start with single-level decomposition.
- **PLT:** Option A. "Expected/actual" (B) imposes argument-order convention. Left/right is structurally honest — reports what the arguments are without semantic interpretation. Power assert (C) requires ad-hoc compiler decomposition with evaluation-order concerns. Can be added later as optional enhancement. *(dissent)*
- **DevOps:** Option C. Power assert produces the most actionable diagnostics. CI engineers diagnose from JSON: `"introspection": {"account.balance": 450, "minimum": 500}`. "Expected/actual" is misleading because users put expected on either side. For `assert_eq`, keep left/right labels; introspection applies to `assert()` booleans.
- **AI/ML:** Option C. Sub-expression values let the LLM map values back to variable names instantly in the fix loop. "Expected/actual" has a well-known argument-order swap problem (~30-40% of the time). Power Assert eliminates ordering conventions entirely.

---

## Machine Output Format — Design Rationale

### Panel Deliberation

Five panelists voted on whether Pact's machine-readable output format (§8.1) should remain JSON-only or adopt token-optimized alternatives like TOON.

**Context:** TOON (Token-Oriented Object Notation, v1.4, 2025) offers 30-60% token reduction vs JSON for LLM consumption, with 73.9% LLM parsing accuracy vs JSON's 69.7%. However, JSON has universal CI/IDE/tooling support while TOON has zero ecosystem tooling (no `jq` equivalent, no SARIF, no GitHub Actions parser).

**Q1: Primary output format (3-1-1 for JSON default + TOON flag)**

- **Systems:** Option C. JSON parsing overhead is negligible (SIMD parsers); token savings are the AI consumer's concern. `--format toon` flag is a cheap runtime branch.
- **Web/Scripting:** Option A. JSON universal, zero learning curve. Adding TOON means two paths to document/test/maintain. YAGNI. *(dissent)*
- **PLT:** Option D. Schema and encoding are separate concerns. Spec should define abstract schemas, not bind to a wire format. *(dissent)*
- **DevOps:** Option C. JSON is the only format CI/IDE actually consumes. TOON as opt-in for AI agents.
- **AI/ML:** Option C. 35-40% token savings on diagnostics. LLMs parse TOON more accurately despite less training data.

**Q2: Diagnostic-specific optimization (3-1-1 for uniform format)**

- **Systems:** Option C. Streaming (NDJSON) matches incremental compilation. *(dissent)*
- **Web/Scripting:** Option A. One format, one parser. Principle 2.
- **PLT:** Option A. Uniform treatment. Special-casing breaks compositionality.
- **DevOps:** Option A. One parser, one test suite, one integration.
- **AI/ML:** Option B. Diagnostics are the hot path; tabular TOON has highest ROI here. *(dissent)*

**Q3: Spec language (3-2 for "structured output with canonical JSON schema")**

- **Systems:** Option C. Schema is the contract, wire format is transport.
- **Web/Scripting:** Option A. Just say "JSON." Abstract language invites bikeshedding. *(dissent)*
- **PLT:** Option C. Separates type (schema) from representation (encoding).
- **DevOps:** Option A. CI authors need certainty, not abstract promises. *(dissent)*
- **AI/ML:** Option C. Schema is training signal; encoding is transport. Future-proof.

**Final decision: Deferred.** Panel voted for JSON+TOON, but the pragmatic conclusion was that JSON is required regardless for ecosystem compatibility. TOON (v1.4) is too immature — no `jq`, no SARIF, no CI tooling. The `--format` extensibility point can be added when token-optimized formats achieve tooling parity. No spec changes for v0.3.

---

## Test Skip Mechanism — Design Rationale

### Panel Deliberation

Five panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML) voted independently on whether and how to support skipping tests. Not a pre-existing GAPS.md item — arose from implementing recursive test discovery.

**Q1: Skip mechanism form (3-2 for both `@skip` annotation + `skip()` runtime built-in)**

- **Systems:** Option C. `@skip` is the zero-cost path — compiler elides the test body entirely. But runtime `skip()` is genuinely necessary for platform/environment-dependent tests. Two mechanisms is fine when they map to two fundamentally different evaluation times. Zig's `return error.SkipZigTest` proves runtime skip works cleanly.
- **Web/Scripting:** Option C. Every major framework (pytest, Jest, JUnit) ships both because they solve different problems. `@skip` is the TODO marker, `skip()` handles "this only works on Linux." Forcing conditional skips into tag filtering is clunky and unfamiliar.
- **PLT:** Option A. `@skip` operates at the declaration level as compile-time metadata — principled, composes orthogonally. Runtime `skip()` conflates a meta-level concern (whether to run) with object-level computation (the test body). This is a level confusion. *(dissent)*
- **DevOps:** Option C. `@skip` gives LSP/linter/formatter a static signal: dimmed rendering, CI warnings, reason-less skip linting. But `skip()` solves what `@skip` cannot: conditional skipping produces proper `"skipped"` status instead of misleading `"pass"`.
- **AI/ML:** Option A. `@skip` is highest-signal for LLM generation — annotation-before-test is massively represented in training data. `skip()` adds a runtime decision point that increases LLM error surface. LLMs will hallucinate `@skip` anyway; better to make the hallucination correct. *(dissent)*

**Key argument:** Compile-time and runtime skips are fundamentally different evaluation times. `@skip` cannot express "skip if no GPU" and `skip()` cannot avoid compiling/loading a test with missing dependencies. Conflating them into one mechanism forces losing either zero-cost static skipping or runtime conditional capability.

**Dissent summary:** PLT argued that skip is a meta-level judgment about the test, not part of the test's computation — `skip()` inside the body is a category error. AI/ML argued that two mechanisms doubles the decision surface for LLMs and `@skip` alone covers 90% of use cases with zero ambiguity.

---

## Package Distribution & Resolution — Design Rationale

### Panel Deliberation

Five panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML) voted independently on 5 questions covering the package manager design gap identified in GAPS.md.

**Q1: Registry model (5-0 for hybrid)**

- **Systems:** Hybrid. Central registry provides content-addressed integrity verification. Git fallback handles private/corporate repos without requiring a private registry instance. Identity invariant prevents the "same package, two names" dependency duplication bug.
- **Web/Scripting:** Hybrid. npm taught us that a central registry with URL fallback covers 99% of cases. Corporate proxies and private repos need git URLs. The identity invariant is critical — npm has the `npm:` alias mess because they lack this.
- **PLT:** Hybrid. Go's proxy model proves this works at scale. The identity invariant is a theorem about package identity that prevents diamond-dependency confusion. Registry is the canonical source; git is a transport mechanism.
- **DevOps:** Hybrid. CI/CD pipelines need deterministic dependency resolution from a single source of truth. Git fallback handles air-gapped environments and internal packages. The lockfile pins both registry and git deps uniformly.
- **AI/ML:** Hybrid. LLMs need one canonical name per package for reliable code generation. If `http-client` and `git:...http-client.git` were different identities, models would hallucinate the wrong one. Single identity = single training signal.

**Q2: Package naming (4-1 for namespaced org/name)**

- **Systems:** Namespaced. `org/name` provides collision-free naming and maps directly to capability trust boundaries. `std/http` and `acme/http` are unambiguous. Slash separator is universal (GitHub, Docker, Go modules).
- **Web/Scripting:** Namespaced. npm's `@scope/name` proves namespacing works at massive scale. Flat naming caused the `left-pad` land-grab problem. Organizations need ownership boundaries.
- **PLT:** Namespaced. Module path mapping (`import std.http` → package `std/http`) is clean and deterministic. Namespaces provide a natural hierarchical organization that matches how developers think about code provenance.
- **DevOps:** Namespaced. Org-scoped names enable per-org security policies in CI: `std/*` packages can be auto-approved while `unknown-org/*` requires review. Trust boundaries need machine-readable organization signals.
- **AI/ML:** Flat names. LLMs trained on npm/PyPI primarily see flat names (`requests`, `express`, `flask`). Namespaced names double the token count per dependency reference and increase hallucination surface — models must get both org AND name correct. Flat names with a prefix convention (`pact-http`) would leverage existing training data better. *(dissent)*

**Q3: Version resolution algorithm (4-1 for MVS)**

- **Systems:** MVS. Deterministic without lockfile is the key property — reproducible builds are guaranteed by the algorithm, not by an artifact. No SAT solver means no exponential worst-case. Resolution is a simple graph walk.
- **Web/Scripting:** Maximal/latest. Every JS/Python/Ruby developer expects `pact add foo` to get the newest version. MVS getting the *oldest* satisfying version will confuse developers and generate support tickets. The lockfile already ensures reproducibility — MVS's determinism-without-lockfile is solving a problem we don't have since lockfiles are mandatory. *(dissent)*
- **PLT:** MVS. Russ Cox's formal proof that MVS is the only algorithm where adding a dependency cannot change existing resolved versions is compelling. Monotonicity is a strong theoretical property that prevents "dependency hell" by construction.
- **DevOps:** MVS. `pact update` is an explicit operation that upgrades. Implicit latest-version resolution means CI builds change based on when they run. MVS + mandatory lockfile = maximum reproducibility.
- **AI/ML:** MVS. Deterministic resolution means LLMs can predict resolved versions from `pact.toml` alone. Non-deterministic resolution (latest at time of resolve) means the model cannot know what versions will be selected, making version-specific API advice unreliable.

**Q4: Version constraint syntax (4-1 for caret default)**

- **Systems:** Tilde. Caret is too permissive — `"1.2"` accepting `1.9.0` trusts the entire ecosystem to never break semver within a major. Tilde (`~1.2` = `>=1.2, <1.3`) limits blast radius to patch versions, which are far less likely to break. *(dissent)*
- **Web/Scripting:** Caret. npm's `^` default has proven itself at massive scale. Developers expect `"1.2"` to mean "compatible with 1.2." Tilde is too conservative — it prevents adopting minor-version features without manual update.
- **PLT:** Caret. The semver contract explicitly states that minor versions add functionality without breaking compatibility. Caret directly encodes this contract. Tilde underutilizes semver by treating minor versions as potentially breaking.
- **DevOps:** Caret. Combined with MVS, caret is conservative in practice — MVS selects the *oldest* 1.x that satisfies constraints, not the newest. Caret + MVS = you get 1.2.0 until something explicitly requires 1.3+.
- **AI/ML:** Caret. Simpler mental model for LLMs: `"1.2"` means "1.x compatible." Models generating `pact.toml` files will use the default constraint most often — caret is the most forgiving default for AI-generated version strings.

**Q5: MVP dependency sources (5-0 for path + git only)**

- **Systems:** Path + git. Registry infrastructure is a massive engineering effort (storage, CDN, authentication, moderation). Path and git deps cover all development scenarios. Ship the language, not the ecosystem infrastructure.
- **Web/Scripting:** Path + git. npm didn't launch with a registry either — the tool came first. Developers need local and git deps for real work. Registry can follow when there's a community to serve.
- **PLT:** Path + git. The `pact.toml` schema should be forward-compatible so adding `version = "1.0"` registry deps later requires zero breaking changes. Design the schema now, ship the registry later.
- **DevOps:** Path + git. Git deps with commit-hash pinning in the lockfile provide reproducibility. Path deps enable monorepo workflows. These two cover corporate development patterns completely.
- **AI/ML:** Path + git. LLMs generating `pact.toml` for new projects will use path deps for workspace packages and git deps for external code. Registry deps need a live package index — AI can't verify package existence without it. Ship what works offline first.

**Key argument:** MVS + caret + mandatory lockfile creates a uniquely conservative system: caret constraints allow compatible updates, but MVS selects the oldest satisfying version rather than the newest. `pact update` is the only operation that moves versions forward, making dependency upgrades always intentional. This eliminates the "it worked yesterday but today it resolves differently" class of bugs.

**Dissent summary:** Web/Scripting argued that MVS's "oldest version" behavior contradicts developer expectations from every major package manager (npm, pip, cargo all select newest). AI/ML argued that flat package names would better leverage existing LLM training data from npm/PyPI ecosystems. Systems argued that tilde constraints provide tighter blast radius than caret.

---

## Stdlib Distribution & Import Resolution — Design Rationale

### Panel Deliberation

The import resolution algorithm (§10.5) specified local `src/` resolution and `pact.lock` dependency resolution but had no mechanism for standard library modules. This gap blocked stdlib modules (`std.toml`, `std.semver`) from being importable outside of the compiler's own `src/` directory.

**Q1: Where does the stdlib physically live? (4-1 for D: virtual/implicit dependency)**

- **Sys (A):** Alongside compiler binary in `<pactc_dir>/stdlib/`. Hermetic, relocatable, matches Go/Zig.
- **Web (D):** Virtual dependency. Zero new concepts — stdlib is just deps you didn't have to declare. Go's approach.
- **PLT (D):** Uniform module semantics. No special resolution step. Effect system needs zero special cases.
- **DevOps (D):** Virtual dep backed by `<pactc_dir>/lib/std/`. LSP and compiler share same path. CI needs zero config.
- **AI (D):** Virtual dep. Implementation detail hidden from import syntax. Eliminates "where is my stdlib?" debugging.

*(dissent: Sys — preferred explicit filesystem colocating over virtual abstraction, citing Go's `GOROOT/src/` simplicity)*

**Q2: What is the import syntax for stdlib? (3-2 for A: `std` prefix)**

- **Sys (A):** `std.` prefix eliminates ambiguity. `pact.` prefix collides with language name. Matches Rust `std::`.
- **Web (C):** `pact.` prefix — spec already shows `import pact.http` in §10.5 examples. No new naming convention. *(dissent)*
- **PLT (A):** `std.` prefix avoids open namespace problems. OCaml retrofitted `Stdlib.List` for exactly this reason.
- **DevOps (A):** `std.` prefix — matches `std/` org on registry (§8.9.2). `import std.http` → `std/http` package.
- **AI (C):** `pact.` prefix — existing spec examples are the training data. Changing creates contradiction. *(dissent)*

*Clarifying note: §8.9.7 explicitly states "import paths follow the `org/name` structure: `import std.http` maps to the `std/http` package." The `pact.*` namespace in §10.6 (`pact.core`, `pact.ffi`) is reserved for compiler-internal pseudo-modules, not distributable packages. The existing spec is consistent with the `std` prefix.*

**Q3: What is the resolution order? (3-2 for C: stdlib is a dep, no new step)**

- **Sys (A):** Local → stdlib → deps → error. Stdlib is trusted toolchain code, should shadow deps for security.
- **Web (C):** Local → deps (stdlib included) → error. No new resolution step, uniform mental model.
- **PLT (C):** Stdlib-as-dep. Scales to Tier 2/3 without semantic boundary changes.
- **DevOps (A):** Local → stdlib → deps → error. With escape hatch: explicit `pact.toml` pinning overrides bundled version. *(dissent)*
- **AI (C):** Stdlib-as-dep. One resolution algorithm, zero special cases.

*(dissent: Sys — wanted explicit stdlib priority for supply-chain security. DevOps — wanted stdlib step for clearer error messages on corrupted installs)*

### Resolution

Stdlib modules are distributed alongside the compiler binary in `<pactc_dir>/lib/std/`. The compiler treats them as implicit dependencies injected into the dependency graph before resolution. Import syntax uses the `std` prefix: `import std.toml`, `import std.semver`. The resolution algorithm remains unchanged — local `src/` first, then all dependencies (including implicit stdlib entries), then error. See §10.7 for the full specification.

---

## Open Questions

These design decisions remain unresolved:

1. **Information flow tracking** — Taint tracking via effect provenance (v2+ roadmap). `Query[C]` covers injection cases for v1
2. ~~**Row polymorphism**~~ — **Partially resolved.** Wildcard `! _` forwarding covers 95% case in v1. Named effect variables (full row polymorphism) deferred to v2. See Effect Polymorphism rationale above.
3. **Higher-kinded types** — Only if needed for effect abstractions. Deferred.
4. ~~**Codegen backend**~~ — **Resolved.** Emit C → cc. See Codegen Backend & Bootstrap rationale above.
