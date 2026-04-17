# Blink Design Decisions

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

| Language | What Blink Borrows |
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
| IR layer & multi-backend | Defer IR to post-v1. When added: incremental migration (trivial IR → enrich). First non-C backend: WASM | 4-1 (PLT dissented) |
| Interpolation injection safety | `Template[C]` structural+phantom type. Compiler decomposes InterpString into `parts`/`values`; handler reassembles with dialect-specific syntax. `Raw(expr)` per-interpolation escape hatch. Taint tracking deferred to v2 | 3-0 (original), refined 3-1-1 / 3-2 / 4-1 |
| Query escape hatch | `Raw(expr)` marker type. Per-interpolation bypass inside `Template[C]` strings. No format specs v1 | 2-1 (D 2, A 1) |
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
| Import search paths | Single `src/` root + deps from `blink.lock`. No env vars, no configurable roots | 5-0 |
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
| Test scope | Top-level only. Tests in a file see all items (pub and private) in that file's module. *(Updated: `mod { }` scoping removed per inline-module-blocks decision 4-1)* | 4-1 (AI/ML: top-level only) |
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
| Display and Template[C] interaction | Display is Str-context only. `Template[C]` interpolation passes raw typed values as decomposed parts/values, not Display-stringified strings. Compiler-known param type set | 5-0 |
| FFI pointer type model | `Ptr[T]` non-null default, `Ptr[T]?` for nullable via `Option`. `Void` opaque type for `Ptr[Void]`. No const/mut distinction | 4-1 (Sys/Web/PLT/DevOps for B; AI for A) |
| FFI pointer operations | Minimal + deref/write/null: `alloc_ptr`, `as_cstr`, `addr`, `deref() -> Option[T]`, `write(T)`, `is_null()`, `null_ptr[T]()`, `to_str()` | 5-0 |
| FFI pointer lifetime | Scoped `ffi.scope()` via Closeable integration. `scope.take()` for ownership transfer. Standalone `alloc_ptr` with GC finalizer as fallback | 3-2 (PLT/DevOps/AI for scope; Sys/Web for hybrid) |
| Error identification scheme | Names primary (PascalCase, frozen), codes secondary comblink alias. `error[NonExhaustiveMatch]` in terminal, both in JSON | 3-2 (PLT/DevOps/AI for names; Sys/Web for hybrid) |
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
| C symbol naming | Module-qualified for ALL items: `blink_module_name_fn` format. No flat names | 5-0 |
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
| Web-service stdlib: SQL/DB | Tier 2 — blessed separate package. Database drivers are backend-specific; `Template[C]` and `db.*` effect handles are already compiler-known | 5-0 |
| Web-service stdlib: Logging | Tier 2 — blessed separate package. `io.log()` effect handle is the T1 primitive; structured logging is policy above capability | 4-1 (DevOps dissented: default IO.Log handler should be T1) |
| Web-service stdlib: Config | Tier 2 — blessed separate package. `std.toml` + `env.var()` cover basics; config merging/validation is opinionated | 5-0 |
| Module-level `let mut` mutation | Compiler write-set inference (not an effect). Tracks which `let mut` bindings each function writes, fully automatic. Cross-module statefulness via user-defined effects (§4.12) | Round 1: 5-0. Round 2 (PLT/Systems/AI): 3-0 |
| Collection mutation via params | No effect required for v1. GC aliasing is real but tracking it approaches borrow-checker territory. Defer to v2 | 5-0 |
| Closure capture mutation | No effect required. Lexically scoped, visible in enclosing function body | 5-0 |
| `@i` annotation | Merged into `///`. First line of doc comment is queryable intent. `@i` removed from annotation system | 5-0 |
| Compile-time file inclusion | `#embed("path")` with `#` sigil for compile-time intrinsic category. Evaluated at compile time, produces `Str`. No new string syntax | 5-0 (inclusion); 5-0 (`#` sigil over `$` and unsigiled) |
| Language evolution: core mechanism | Edition-gated evolution + rich `@deprecated` + `blink migrate` | 5-0 |
| Language evolution: edition scope | Stdlib + limited behavior (keywords, lint severity). NOT core syntax | 3-1-1 (PLT/DevOps/AI for stdlib+keywords+lint; Systems for syntax too; Web for stdlib-only) |
| Language evolution: enforced semver | v2, not v1. Package manager enforces removal alignment with major versions | 4-1 (AI dissented: enforce from v1) |
| Language evolution: compatibility window | Infinite — all editions supported forever. Compiler never drops edition support | 4-1 (Systems dissented: wanted 5-year sunset) |
| Language evolution: llms.txt headers | Yes. Edition-specific API change summary in llms.txt | 5-0 |
| Language evolution: built-in changelog | Yes. `blink editions` command compiled into binary, offline-available | 3-2 (PLT/DevOps/AI for built-in; Systems/Web for external file) |
| Char → Int conversion | `Char.to_int()` named method + `From[Char] for Int`. Infallible widening | 4-1 (PLT dissented: `code_point()` only, Char is not numeric) |
| Int → Char conversion | `TryFrom[Int] for Char` + `Char.from_code_point(n) -> Result[Char, ConversionError]` | 4-1 (Web dissented: `Int.to_char()` for symmetry) |
| Char → Str conversion | `From[Char] for Str` + `Char.to_str()` named method. Infallible | 5-0 |
| List pattern matching | `[pattern, ...]` in match, wildcard-only rest (no binding), length-based exhaustiveness with mandatory catch-all | 5-0 patterns, 4-1 wildcard rest |
| Extended delimiter strings | `#"..."#` with `#{expr}` interpolation. `"` and `\` literal inside. Adjustable `#` depth (max 3). Same `Str` type. Parametric extension, not second syntax | 5-0 |
| Inline module blocks | No `mod name { }`. File = Module is absolute (§10.1.1). `mod` keyword reserved but unused. Separate files for sub-modules | 4-1 (Web: file-scoped namespaces) |
| Native dep manifest declaration | `[native-dependencies]` section in `blink.toml` for user `@ffi` C libraries. `@ffi` without manifest entry is compile error | 5-0 |
| Cross-compilation linking | Static by default for cross-targets (vendored source), dynamic for host. `link = "dynamic"` override available | 5-0 |
| Compiler-managed vs user-managed native deps | Compiler manages deps for language-defined effects (`db.*`, `net.*`). User manages raw `@ffi` via `[native-dependencies]` | 3-2 (PLT/DevOps/AI for B; Sys/Web for C) |
| Dead `-lcurl` flag | Remove immediately. HTTP uses raw POSIX sockets, not libcurl | 5-0 |
| Mutation analysis: suppression mechanism | Both `@allow(WarningName)` per-function + `blink.toml` `[lints]` project-wide. Function-level overrides project-level | 5-0 |
| Mutation analysis: W0551 heuristic | Context-aware: W0551 only fires inside functions with existing save/restore patterns (speculative work). Normal functions never trigger | 5-0 |
| Mutation analysis: threshold | Remove write-set size threshold entirely. Context-aware heuristic is the sole gating condition | 5-0 |
| Compiler type representation: pool style | Parallel arrays now, migrate to enum when struct-in-list lands | 4-1 (Sys for parallel-only) |
| Compiler type representation: unify TC/CG | Single type pool shared by typecheck + codegen, phase-specific side tables | 5-0 |
| Compiler type representation: interning | Full interning via Map — type equality is integer comparison | 5-0 |
| StringBuilder API | `StringBuilder` struct with `with_capacity`, Tier 1 (`std.str`), import required. Interpolation optimization in `write()` | 3-1-1 (PLT: Writable trait; AI: no capacity) |
| Stdlib API surface | Methods only; free functions are internal FFI bridges, not public API. Constructors use `Type.method()` static syntax | 4-1 (Web: D, methods + constructors — functionally identical) |
| `--trace` event types | 4 types: `enter`, `exit`, `state`, `effect`. Panics/assertions are diagnostics, not trace events | 4-1 (DevOps: 6 types including `assert_fail`/`panic`) |
| `--trace` schema shape | Semi-nested: flat top-level + `span` object matching diagnostic format | 5-0 |
| `--trace` value serialization | String/Display representation only. Bounded cost, forward-compatible | 4-1 (PLT: tagged `{"type":"Int","value":42}`) |
| `--trace` filter syntax | Colon-syntax `--trace=fn:name,module:mod,depth:3`. AND across keys, OR within key via `+` | 4-1 (PLT: separate flags) |
| `--trace` timestamp format | Microseconds monotonic (`ts_us`). Right precision for function-level tracing | 5-0 |
| Set[T] implementation | Implement now as full builtin type. Spec'd-but-unimplemented = hallucination trap + DX trap. ~300 LOC following Map pattern | 4-1 (Sys/Web/DevOps/AI for implement; PLT for defer) |
| Memory management GC | Boehm-Demers-Weiser conservative tracing GC. Replace `malloc` with `GC_MALLOC` in `blink_alloc`, link `-lgc`. ~15 lines. Custom precise GC deferred to Phase 3 if needed | 5-0 |
| Qualified access semantics | Selective restricts unqualified only; covers fn+type+const; leaf module name; resolves E1005 ambiguity | 3-2, 5-0, 5-0, 5-0 |
| Pub re-export semantics | Re-exported items = first-class pub. Both selective + qualified access. Name collision = compile error. No W0602. Any module can re-export | 5-0, 5-0, 5-0, 5-0 |
| Logo direction | Hybrid syntax+focus metaphor (chevrons evoking blinkers). Blue+gold palette. Full design system (icon+wordmark+combo). Pick one metaphor, commit | 2-2 (Q1, hybrid resolution), 4-0, 4-0, 4-0 |
| `capture_log` test instrumentation | Stdlib `std.testing.capture_log(List[Str]) -> Handler[IO.Log]`. Captures `io.log()` only. No new assertion helpers — use existing `assert`/`assert_eq` on `List[Str]` | 4-1 (Q1, Sys dissent), 5-0, 5-0 |
| Sized integer role | First-class nominal types, not refinement types or FFI-only. Different representation (8/16/32/64 bits), not value constraints on Int | 3-1-1 (Sys/PLT/DevOps for A; Web for C; AI/ML for B) |
| Sized integer overflow | Checked by default (panic on overflow). Explicit wrapping via `.wrapping_add()` etc. Compile-time range checking for literals | 3-2 (Sys/PLT/DevOps for checked; Web/AI for panic-always) |
| Bitwise operations | Operator syntax (`&`, `\|`, `^`, `<<`, `>>`, `~`) with sealed traits. Integer types only | 4-1 (AI/ML dissented: named methods only) |
| Sized numeric method surface | Standard: `.abs()`, `.min()`, `.max()`, `.pow()`, `.clamp()` plus wrapping arithmetic methods | 5-0 |
| Sized numeric literal syntax | Type inference only. `let x: U8 = 42` — literal range-checked against context type. No suffix syntax, no constructor syntax | 4-1 (Sys dissented: constructor syntax) |
| Transaction block syntax | `db.transaction { }` as parser special form (like `async.scope { }`). Block semantics (not closure) — `?` propagates to enclosing function. Manual API (`db.begin/commit/rollback`) remains for advanced use | 3-1 (PLT/DevOps/AI for A; Web for B trailing blocks; Sys abstained) |
| Scoped block mechanism | `BlockHandler` trait with `enter()/exit()` + `with`/`as` syntax. General mechanism for scoped blocks (transactions, timers, locks). Replaces need for parser special forms. `async.scope` migration deferred to v2 | 5-0 (runoff F vs C) |
| Tier-2 pre-registry behavior | Collapse tier-2 into tier-1 until registry exists. All `std.*` modules implicit, no `blink.toml` required | 4-1 (DevOps dissented: keep manifest gate for auditability) |
| Long-term stdlib tier architecture | Batteries included — all `std.*` is tier-1 forever. No tier-2 concept. Stdlib version-locks to compiler. If it doesn't belong in stdlib, it's an ecosystem package without `std.*` prefix | 3-2 (Web/PLT dissented: semi-stdlib with independent versioning) |
| Env var exposure mechanism | Pure codegen builtin with vtable dispatch (same as IO/FS/Time). Remove `get_env()` immediately (soundness hole). Vtable swap for handler mockability | 4-1 (PLT dissented: stdlib module), 4-1 (Web dissented: deprecate get_env), 4-1 (PLT dissented: evidence passing) |
| Spread/rest operator (`..`) | `..` is a general spread/rest concept. v1: struct/list pattern rest, struct literal copy-update, list literal spread. Future contexts (tuple spread, etc.) require separate deliberation | 5-0 (generic framing) |
| Rest sigil unification | Unified `..` for struct and list rest patterns. Drop `...` from list patterns. One sigil, context disambiguates | 4-1 (PLT dissented for `*` Kleene star) |
| Struct copy-update | `Type { field: val, ..source }` — spread suffix in struct literals. Same `..` sigil as pattern rest. Zero new keywords | 4-1 (AI/ML dissented for `copy` keyword) |
| List literal spread | `[..list1, extra, ..list2]` — spread elements into list literals. Multiple sources, any position. Eager copy. Completes pattern/construction duality | 5-0 |
| Arena promotion semantics | Per-type compiler-generated `blink_promote_<Type>` walkers. Deep structurally, `GC_MALLOC_ATOMIC` copy for strings, cyclic types rejected as E0701. Walker takes target allocator parameter | 4-1 (DevOps dissented for outermost-only) |
| Arena escape rules | Sound-conservative + return-path exception. Return expression is promoted, all other flows produce E0700. Arena-local params inferred from `! Arena` signatures | 5-0 |
| Arena handler plumbing | Hybrid: thread-local `__blink_current_arena` for `blink_alloc` fast path; `BlockHandler` trait for `with arena { }` lifecycle (enter sets TLS, exit restores + destroys). `! Arena` is a marker effect for escape analysis, not evidence-passing dispatch | 5-0 runoff (round 1: A=1 / C=2 / D=2) |
| Arena nesting | Independent arenas per nested `with arena`. Inner block allocations freed on inner exit; values promoted into nearest enclosing arena (or GC heap if none) | 5-0 |

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
| Language Evolution | [decisions/language-evolution.md](decisions/language-evolution.md) |
| Char Conversions | [decisions/char-conversions.md](decisions/char-conversions.md) |
| List Pattern Matching | [decisions/list-pattern-matching.md](decisions/list-pattern-matching.md) |
| Inline String Escape (Extended Delimiters) | [decisions/inline-string-escape.md](decisions/inline-string-escape.md) |
| Inline Module Blocks | [decisions/inline-module-blocks.md](decisions/inline-module-blocks.md) |
| Native C Dependency Resolution | [decisions/native-c-dependency-resolution.md](decisions/native-c-dependency-resolution.md) |
| Mutation Analysis Suppression | [decisions/mutation-analysis-suppression.md](decisions/mutation-analysis-suppression.md) |
| Logo Direction | [decisions/logo-direction.md](decisions/logo-direction.md) |
| Compiler Internal Type Representation | [decisions/compiler-type-representation.md](decisions/compiler-type-representation.md) |
| StringBuilder | [decisions/string-builder.md](decisions/string-builder.md) |
| Transaction Block Syntax | [decisions/transaction-block-syntax.md](decisions/transaction-block-syntax.md) |
| Scoped Block Mechanism | [decisions/scoped-block-mechanism.md](decisions/scoped-block-mechanism.md) |
| Stdlib API Surface | [decisions/stdlib-api-surface.md](decisions/stdlib-api-surface.md) |
| `--trace` NDJSON Format | [decisions/trace-ndjson-format.md](decisions/trace-ndjson-format.md) |
| Set[T] Builtin Type | [decisions/set-type-implementation.md](decisions/set-type-implementation.md) |
| Memory Management GC | [decisions/memory-management-gc.md](decisions/memory-management-gc.md) |
| Qualified Access Semantics | [decisions/qualified-access-semantics.md](decisions/qualified-access-semantics.md) |
| Pub Re-export Semantics | [decisions/pub-re-export-semantics.md](decisions/pub-re-export-semantics.md) |
| `capture_log` Test Instrumentation | [decisions/capture-log-test-instrumentation.md](decisions/capture-log-test-instrumentation.md) |
| Sized Numeric Types | [decisions/sized-numeric-types.md](decisions/sized-numeric-types.md) |
| IR Layer & Multi-Backend Codegen | [decisions/ir-multi-backend.md](decisions/ir-multi-backend.md) |
| DB Module Design | [decisions/db-module-design.md](decisions/db-module-design.md) |
| Template Type Design | [decisions/template-type-design.md](decisions/template-type-design.md) |
| Tier-2 Pre-Registry Behavior | [decisions/tier2-pre-registry-behavior.md](decisions/tier2-pre-registry-behavior.md) |
| Long-Term Stdlib Tier Architecture | [decisions/stdlib-tier-architecture.md](decisions/stdlib-tier-architecture.md) |
| Env Var Exposure Mechanism | [decisions/env-var-exposure-mechanism.md](decisions/env-var-exposure-mechanism.md) |
| Rest Sigil Unification | [decisions/rest-sigil-unification.md](decisions/rest-sigil-unification.md) |
| Struct Copy-Update | [decisions/struct-copy-update.md](decisions/struct-copy-update.md) |
| List Literal Spread | [decisions/list-literal-spread.md](decisions/list-literal-spread.md) |
| Arena Allocation Semantics | [decisions/arena-allocation-semantics.md](decisions/arena-allocation-semantics.md) |

---

## Open Questions

These design decisions remain unresolved:

1. **Information flow tracking** — Taint tracking via effect provenance (v2+ roadmap). `Template[C]` covers injection cases for v1
2. ~~**Row polymorphism**~~ — **Partially resolved.** Wildcard `! _` forwarding covers 95% case in v1. Named effect variables (full row polymorphism) deferred to v2. See [Effect Polymorphism rationale](decisions/effect-polymorphism.md).
3. **Higher-kinded types** — Only if needed for effect abstractions. Deferred.
4. ~~**Codegen backend**~~ — **Resolved.** Emit C → cc. See [Codegen Backend & Bootstrap rationale](decisions/codegen-backend-bootstrap.md).
