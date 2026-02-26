# Pact Design Decisions

Reference material extracted from the spec process. Influences, rejected features, resolved questions, editor's notes, and design process history.

---

## Editor's Notes

Minor inconsistencies between sections written by different experts. These need resolution:

1. ~~**Annotation syntax**: Section 8 (in 06_tooling.md) uses `/// @i("text")` inside doc comments, while sections 2, 3, 4, 5, 9, 10, 11 use standalone `@i("text")`.~~ **Resolved:** `@i` removed entirely (panel vote 5-0). Intent is now the first line of `///` doc comments. See `@i` Annotation deliberation.

2. ~~**Annotation ordering**: Section 2.9 puts `@capabilities` after `@perf`. Section 11.1 puts `@capabilities` before `@i`.~~ **Resolved:** `@i` removed. Canonical ordering is now: `@mod` > `@capabilities` > `@derive` > `@src` > `@requires` > `@ensures` > `@where` > `@invariant` > `@perf` > `@ffi` > `@trusted` > `@effects` > `@alt` > `@verify` > `@deprecated`.

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
| Serialization mechanism | `@derive(Serialize, Deserialize)` generating trait impls. Extends existing `@derive` | 5-0 |
| Serialization field renaming | No `@json("name")` field renaming in v1. Field names must match JSON keys | 3-2 (Sys/PLT/AI for no rename; Web/DevOps for `@json`) |
| Serialization codec dispatch | JSON-specific `Serialize` trait returning `JsonValue`. Add separate traits for other codecs later | 5-0 |
| Serialization tier | Tier 1 — `Serialize`/`Deserialize` are compiler-known traits, `@derive` works out of the box | 5-0 |
| Option JSON encoding | `Option[T]` `None` → JSON `null`. Consistent with majority of JSON libraries | 5-0 |
| Serialization error type | Single `JsonError` type covering both serialization and deserialization | 4-1 (PLT: separate types) |
| Serialization purity | Pure — `to_json()` returns `JsonValue`, IO effects only at call site | 5-0 |
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
| Module-level let duplicates | Compile error. No shadowing, no silent dedup | 5-0 |
| Module-level pub let | `pub let` (immutable) allowed. `pub let mut` forbidden | 5-0 |
| Shadowing scope rules | Function-local allows shadowing, module-level does not | 5-0 |
| Import compilation model | Emit-all: importing any item includes all module definitions in C output. Separate compilation deferred to v2 | 5-0 |
| Pub enforcement | Enforced at compile time. Using non-pub item from outside module is a compile error | 5-0 |
| C symbol naming | Module-qualified for ALL items: `pact_module_name_fn` format. No flat names | 5-0 |
| Name resolution: symbol table | Annotated AST — typecheck decorates nodes with resolution results, codegen reads decorations | 5-0 |
| Name resolution: method timing | Two-phase — name binding first, then type-aware method resolution. Methods are type-directed, not name-directed | 5-0 |
| Name resolution: error recovery | Accumulate all name errors, halt before codegen. Codegen never sees unresolved names | 4-1 (DevOps: continue through all phases with poison) |
| Name resolution: module scoping | Module-scoped symbol table. Each declaration tagged with source module. pub enforcement structural | 4-1 (Sys: flat scope with pub checking) |
| `?` operator: validation phase | Type checking phase. Codegen never sees invalid `?` usage. Phase gate architecture | 5-0 |
| `?` operator: operand types | Both `Result[T, E]` and `Option[T]`. No cross-type mixing | 5-0 |
| `?` operator: error type match | Exact structural match (`E1 == E2`). Consistent with no-auto-into vote. Use `.map_err()` | 5-0 |
| `?` operator: error codes | Separate codes: E0502 (invalid operand), E0508 (Result in non-Result fn), E0509 (Option in non-Option fn), E0512 (error type mismatch) | 5-0 |
| JSON codec: dynamic vs typed | Both `json.parse()` (dynamic) and `json.decode[T]()` (typed) as equal peer entry points | 4-1 (PLT: dynamic primary) |
| JSON codec: API surface | Medium 5 functions: parse, stringify, pretty, decode[T], encode[T] | 4-1 (PLT: minimal 3) |
| JSON codec: navigation returns | Option-returning methods on JsonValue (`.get() -> Option[JsonValue]`, `.as_str() -> Option[Str]`, etc.) | 5-0 |
| JSON codec: deserialization path | Two-step canonical: parse → JsonValue → T.from_json(). `json.decode[T]` is sugar composing the two | 5-0 |
| Net.Connect: method surface | Single `request(req)` core operation + HTTP verb default methods (`get`, `post`, etc.) | 4-1 (AI/ML: verbs only) |
| Net.Connect: request config | `Request` builder struct with `.with_header()`, `.with_timeout()` method chaining | 4-1 (Web: options struct) |
| Net.Connect: Response type | Transparent struct `{ status: Int, body: Str, headers: Map[Str, Str] }` with trait methods | 5-0 |
| Net.Connect: WebSocket | Deferred to v2. HTTP request/response only in v1 | 4-1 (Web: separate sub-effect) |
| Net.Listen: server API | Minimal value-server: `net.listen()` → `Server`, `.route()`/`.get()`/`.post()`, `server.serve()`. Go/Flask-style | 3-2 (Sys/Web/AI for A; PLT/DevOps for C: route table) |
| Net.Listen: middleware | Functional wrapping: `fn(handler) -> handler`. Compose by nesting. `.use()` for global middleware | 4-1 (Sys/Web/DevOps/AI for A; PLT for B: effect stacking) |
| Net.Listen: error recovery | Typed error handler: `ServerError { HandlerPanic, Timeout, Internal }` + configurable `error_handler` on Server and per-route | 3-2 (Sys/PLT/DevOps for C; Web/AI for B: effect-based) |
| Net.Listen: @requires auto-400 | Validation effect: compiler generates `validation.contract_violation()`. Default handler returns 400 JSON. Swappable via `with` | 4-1 (Sys/Web/PLT/DevOps for B; AI for A: implicit route marker) |
| Time value type (Instant) | Stdlib opaque `Instant` struct in `std.time` Tier 2. Nanosecond precision. Methods not operators | 5-0 |
| Duration type | Stdlib `Duration` struct in `std.time` Tier 2. Named constructors (`Duration.seconds(5)`). Methods not operators | 5-0 |
| Bytes type | Stdlib `Bytes` in `std.bytes` Tier 1. Contiguous buffer, not `List[U8]` | 5-0 |
| Numeric extensions | F32 built-in (sized numeric family), Decimal in `std.decimal` Tier 2, BigInt in `std.math` Tier 2. Sealed arithmetic not extended | 5-0 |
| UUID type | Stdlib `UUID` in `std.uuid` Tier 2. 128-bit nominal type, not Str. `UUID.random() ! Rand` | 5-0 |
| Env.Read operations | Standard: `args()`, `var()`, `vars()`, `cwd()`. No `home()`/`exe_path()` v1 | 5-0 |
| Env.Write operations | Standard: `set_var()`, `remove_var()`. No `set_cwd()` (process-global footgun) | 4-1 (AI: minimal set_var only) |
| env.exit() placement | Under Env as `env.exit(code) -> Never`. Requires `! Env` (parent). Effect-tracked, handler-interceptable | 5-0 |
| Env sub-effect granularity | Keep Env.Read + Env.Write. No separate Env.Args, no flattening | 5-0 |
| Env return types | Simple: `env.var() -> Option[Str]`, `env.args() -> List[Str]`. Non-UTF-8 lossy-converted. No dual API | 5-0 |
| Const expression scope | Literals + arithmetic + boolean + comparison ops. No function calls, no method calls. Purity does not imply constness | 5-0 |
| `const` keyword | Required. `const NAME = expr` distinct from `let`. Explicit phase annotation. `let` at module level is runtime-initialized | 3-2 (PLT/DevOps/AI for `const`; Sys/Web for inferred `let`) |
| Const struct/enum literals | Struct literal syntax and enum variant construction are const when all fields are const. `Type.new()` is NOT const | 3-1-1 (PLT/DevOps/AI for B; Web for C nested; Sys for A scalars) |
| Const codegen strategy | Compiler evaluates const expressions during compilation, emits result as C literals. No `#define`, no compound literals | 5-0 |
| Web-service stdlib: JSON codec | Tier 1 — ships with compiler. `JsonValue`/`Serialize`/`Deserialize` already compiler-known; codec completes the semantic loop | 5-0 |
| Web-service stdlib: HTTP client | Tier 2 — blessed separate package. Effect types (Request/Response) are compiler-known; convenience layer (retry, redirects, pooling) versions independently | 3-2 (Sys/DevOps/AI for T2; PLT/Web for T1) |
| Web-service stdlib: HTTP server | Tier 2 — blessed separate package. Server frameworks are opinionated and evolve faster than compilers | 5-0 |
| Web-service stdlib: SQL/DB | Tier 2 — blessed separate package. Database drivers are backend-specific; `Query[C]` and `db.*` effect handles are already compiler-known | 5-0 |
| Web-service stdlib: Logging | Tier 2 — blessed separate package. `io.log()` effect handle is the T1 primitive; structured logging is policy above capability | 4-1 (DevOps dissented: default IO.Log handler should be T1) |
| Web-service stdlib: Config | Tier 2 — blessed separate package. `std.toml` + `env.var()` cover basics; config merging/validation is opinionated | 5-0 |
| Module-level `let mut` mutation | Compiler write-set inference (not an effect). Tracks which `let mut` bindings each function writes, fully automatic. Cross-module statefulness via user-defined effects (§4.12) | Round 1: 5-0. Round 2 (PLT/Systems/AI): 3-0 |
| Collection mutation via params | No effect required for v1. GC aliasing is real but tracking it approaches borrow-checker territory. Defer to v2 | 5-0 |
| Closure capture mutation | No effect required. Lexically scoped, visible in enclosing function body | 5-0 |
| `@i` annotation | Merged into `///`. First line of doc comment is queryable intent. `@i` removed from annotation system | 5-0 |
| Compile-time file inclusion | `#embed("path")` with `#` sigil for compile-time intrinsic category. Evaluated at compile time, produces `Str`. No new string syntax | 5-0 (inclusion); 5-0 (`#` sigil over `$` and unsigiled) |

---

## Design Rationales

Full deliberation records for each decision. Each file contains expert votes, reasoning, and dissent.

| Topic | File |
|-------|------|
| Trait Coherence | [decisions/trait-coherence.md](decisions/trait-coherence.md) |
| While/Loop | [decisions/while-loop.md](decisions/while-loop.md) |
| If/Else as Expressions | [decisions/if-else-expressions.md](decisions/if-else-expressions.md) |
| Keyword Arguments & Defaults | [decisions/keyword-arguments-defaults.md](decisions/keyword-arguments-defaults.md) |
| Resource Cleanup | [decisions/resource-cleanup.md](decisions/resource-cleanup.md) |
| Codegen Backend & Bootstrap | [decisions/codegen-backend-bootstrap.md](decisions/codegen-backend-bootstrap.md) |
| Iterator Protocol | [decisions/iterator-protocol.md](decisions/iterator-protocol.md) |
| Type Conversions (From/Into/TryFrom) | [decisions/type-conversions.md](decisions/type-conversions.md) |
| Import Resolution | [decisions/import-resolution.md](decisions/import-resolution.md) |
| Method Resolution | [decisions/method-resolution.md](decisions/method-resolution.md) |
| Test Syntax | [decisions/test-syntax.md](decisions/test-syntax.md) |
| Tuple Types | [decisions/tuple-types.md](decisions/tuple-types.md) |
| Pattern Matching Grammar | [decisions/pattern-matching-grammar.md](decisions/pattern-matching-grammar.md) |
| `Self` Type | [decisions/self-type.md](decisions/self-type.md) |
| Closure Capture Semantics | [decisions/closure-capture-semantics.md](decisions/closure-capture-semantics.md) |
| Module Prelude | [decisions/module-prelude.md](decisions/module-prelude.md) |
| Effect Polymorphism | [decisions/effect-polymorphism.md](decisions/effect-polymorphism.md) |
| Handler Type System | [decisions/handler-type-system.md](decisions/handler-type-system.md) |
| Derive Mechanics + Clone Trait | [decisions/derive-mechanics-clone-trait.md](decisions/derive-mechanics-clone-trait.md) |
| String Methods | [decisions/string-methods.md](decisions/string-methods.md) |
| Collection Methods | [decisions/collection-methods.md](decisions/collection-methods.md) |
| Display Format Protocol | [decisions/display-format-protocol.md](decisions/display-format-protocol.md) |
| FFI Type Mapping | [decisions/ffi-type-mapping.md](decisions/ffi-type-mapping.md) |
| Error Catalog | [decisions/error-catalog.md](decisions/error-catalog.md) |
| Testing Framework | [decisions/testing-framework.md](decisions/testing-framework.md) |
| Machine Output Format | [decisions/machine-output-format.md](decisions/machine-output-format.md) |
| Test Skip Mechanism | [decisions/test-skip-mechanism.md](decisions/test-skip-mechanism.md) |
| Package Distribution & Resolution | [decisions/package-distribution-resolution.md](decisions/package-distribution-resolution.md) |
| Stdlib Distribution & Import Resolution | [decisions/stdlib-distribution-import-resolution.md](decisions/stdlib-distribution-import-resolution.md) |
| Module-Level Let Semantics | [decisions/module-level-let-semantics.md](decisions/module-level-let-semantics.md) |
| Serialization / Deserialization | [decisions/serialization-deserialization.md](decisions/serialization-deserialization.md) |
| Import Compilation Model | [decisions/import-compilation-model.md](decisions/import-compilation-model.md) |
| Name Resolution Pass | [decisions/name-resolution-pass.md](decisions/name-resolution-pass.md) |
| `?` Operator Type Validation | [decisions/question-operator-type-validation.md](decisions/question-operator-type-validation.md) |
| JSON Codec Design | [decisions/json-codec-design.md](decisions/json-codec-design.md) |
| HTTP Client Effect Mapping | [decisions/http-client-effect-mapping.md](decisions/http-client-effect-mapping.md) |
| HTTP Server Routing Model | [decisions/http-server-routing-model.md](decisions/http-server-routing-model.md) |
| Additional Built-in Types | [decisions/additional-built-in-types.md](decisions/additional-built-in-types.md) |
| Env Effect API | [decisions/env-effect-api.md](decisions/env-effect-api.md) |
| Const Evaluation | [decisions/const-evaluation.md](decisions/const-evaluation.md) |
| Web-Service Stdlib Tier | [decisions/web-service-stdlib-tier.md](decisions/web-service-stdlib-tier.md) |
| Non-Local Mutable State | [decisions/non-local-mutable-state.md](decisions/non-local-mutable-state.md) |
| AI-First Review Pass | [decisions/ai-first-review-pass.md](decisions/ai-first-review-pass.md) |
| `@i` Annotation | [decisions/i-annotation.md](decisions/i-annotation.md) |
| Compile-Time Intrinsics (`#` sigil) | [decisions/compile-time-intrinsics.md](decisions/compile-time-intrinsics.md) |

---

## Open Questions

These design decisions remain unresolved:

1. **Information flow tracking** — Taint tracking via effect provenance (v2+ roadmap). `Query[C]` covers injection cases for v1
2. ~~**Row polymorphism**~~ — **Partially resolved.** Wildcard `! _` forwarding covers 95% case in v1. Named effect variables (full row polymorphism) deferred to v2. See [Effect Polymorphism rationale](decisions/effect-polymorphism.md).
3. **Higher-kinded types** — Only if needed for effect abstractions. Deferred.
4. ~~**Codegen backend**~~ — **Resolved.** Emit C → cc. See [Codegen Backend & Bootstrap rationale](decisions/codegen-backend-bootstrap.md).
