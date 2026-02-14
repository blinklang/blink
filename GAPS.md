# Spec Gaps — Pact v0.3

Unspecified or under-specified areas needing design work. Note: a self-hosting compiler exists (`src/pactc.pact`) targeting a minimal Pact subset. These gaps apply to the full language spec.

## Tier 1: Blocks Real Programs

- [x] **Iterator trait & protocol** — `for x in collection` requires an `Iterator` trait; not defined. What methods? Lazy? §2.9, §3.6 *(Resolved: §3c.1, panel vote 3-2 single-method, 5-0 IntoIterator separate, 5-0 lazy, 5-0 default methods, 3-2 defer effectful iteration to v2)*
- [x] **While/loop construct** — only `for` loops specified; `loop { }` + `break`/`continue` mentioned but not defined. §2.9 deferred table *(Resolved: §2.11, panel vote 3-2 both constructs, 3-2 plain break, 4-1 no labels, 5-0 no while-let)*
- [x] **If/else syntax** — no section defines `if`/`else` expressions despite examples using `if`. §2 *(Resolved: §2.9, panel vote 5-0 on all 4 sub-questions)*
- [x] **Type coercions & `From`/`Into` traits** — `From[T]`, `Into[T]` (auto-derived), `TryFrom[T]` formally defined. `?` requires exact error match, no auto `.into()`. §3c.2 *(Resolved: panel vote 5-0 From, 4-1 Into auto-derive, 3-2 fixed ConversionError, 4-1 no auto-conversion on ?)*
- [x] **Import resolution semantics** — import syntax shown (§10.1) but no resolution algorithm: search paths, cycles, diamond deps, re-exports *(Resolved: §10.5, panel vote 5-0 single src/ root, 4-1 intra-package cycles OK, 4-1 one-version-per-package, 5-0 pub import re-exports)*
- [x] **Operator semantics** — `+`, `-`, `*`, `/`, `%`, `==`, `!=`, `<`, `>` etc. used freely; no trait-based dispatch rules (e.g., does `==` desugar to `Eq.eq`?) §3.6 *(Resolved: §2.18, §3.6)*
- [x] **Numeric conversions** — Widening via `From` + named methods, narrowing via `TryFrom` + checked methods. Full conversion table in §3c.3. *(Resolved: panel vote 4-1 both methods and traits, 5-0 widening/narrowing split)*
- [x] **Method resolution** — `x.foo()` could be a field method, a trait method, or an effect handle method. No resolution/priority rules. §3.6, §4.4 *(Resolved: §3c.4, panel vote 5-0 dot-means-method, 5-0 reserved handles, 5-0 call-site disambiguation, 4-1 no inherent methods)*
- [x] **Boolean operators** — `&&`, `||`, `!` used in examples but never formally specified. Short-circuit semantics? *(Resolved: §2.18)*
- [x] **Assignment operators** — `=` for reassignment of `let mut`, but no spec for `+=`, `-=`, etc. *(Resolved: §2.18)*
- [x] **Test syntax** — `test "name" { }` blocks appear in examples (§4.7) but syntax is never formally defined. Discovery, filtering, assertions *(Resolved: §2.19, panel vote 5-0 pure-by-default, 4-1 three assertions, 4-1 annotation tags, 4-1 module-scoped tests)*
- [x] **Tuple types** — `(T, U)` appears in examples (§3b.2 `pop` returns `(T, Stack[T])`) but tuples are never formally defined as a type *(Resolved: §3.8, panel vote 5-0 cap-at-6, 5-0 no 1-tuple, 5-0 full structural traits)*
- [x] **Pattern matching grammar** — spec says exhaustive matching is required (§3.5) but no algorithm or pattern language spec (nested, guards, OR-patterns, ranges) *(Resolved: §3.5, panel vote 5-0 OR-patterns via |, 5-0 range patterns, 4-1 as-binding, 5-0 struct patterns, 5-0 strict refutability)*
- [x] **Destructuring** — `let (a, b) = ...` and `let Foo { x, .. } = ...` shown (§3.5) but not formally specified. Nested? Irrefutable only? *(Resolved: §3.5, destructuring is the irrefutable subset of pattern grammar; let/for require irrefutable, match allows refutable)*
- [x] **`Self` type** — used in trait declarations (`self`, `Self`, `other: Self`) but never formally defined. §3.6 *(Resolved: §3.6 "The Self Type", panel vote 5-0 trait+impl only, 5-0 self sugar, 4-1 type-position only, 5-0 by-value)*
- [x] **Closure capture semantics** — by-reference vs by-move inferred (§2.8) but no rules for when each applies *(Resolved: §2.8, panel vote 3-2 shared-reference, 4-1 no explicit syntax, 3-2 compile error on mutable spawn captures)*
- [x] **Module prelude** — `Option`, `Result`, `Ok`, `Err`, `Some`, `None` auto-imported (§10.1); complete list? `Bool`, `Int`, `Str`? *(Resolved: §10.6, panel vote 5-0 keywords for true/false, 3-1-1 types+ADTs+traits in prelude, 5-0 test builtins auto-available)*

## Tier 2: Blocks Compiler Completion

- [x] **Trait resolution & coherence** — orphan rules, impl overlap, where trait impls can live. §3.6 *(Resolved: §3.6 "Trait Coherence", panel vote 5-0 strict orphan rule, 5-0 no overlap/no specialization, 5-0 package-scoped placement with auto-visibility)*
- [x] **Effect polymorphism** — can a generic fn be polymorphic over effects? `fn map[T,U](f: fn(T) -> U ! ???)` §4 *(Resolved: §4.15, panel vote 5-0 explicit effects on fn types, 3-2 wildcard forwarding `! _` over row polymorphism, 4-1 fn-type effects v1 / full polymorphism v2)*
- [x] **Error type conversions** — `?` requires exact error type match. Explicit `.map_err(fn(e) { Target.from(e) })?` for conversion. §3c.2 *(Resolved: panel vote 4-1 no auto-conversion; DevOps dissented)*
- [x] **Handler type system** — `Handler[E]` is used (§4.7) but how it interacts with effect subtyping, generics, storage is unspecified *(Resolved: §4.7.1, panel vote 5-0 generic type, 3-2 implicit projection, 4-1 no generics v1, 4-1 full first-class, 5-0 partial+auto-delegation)*
- [x] **Derive mechanics** — `@derive(Eq, Hash)` specified (§11.1) but what code is generated? How does it recurse through fields? §3.6 *(Resolved: §3.6 "Derive Mechanics", panel vote 5-0 inferred bounds + auto supertrait, 5-0 field-level error reporting)*
- [x] **`Clone` trait** — listed as derivable (§11.1) but semantics (deep copy? GC implications?) not defined *(Resolved: §3.6 "Clone" + "Debug", panel vote 3-2 logical copy over deep copy, 5-0 separate Debug trait)*
- [x] **String methods** — `.len()`, `.contains()`, `.to_upper()` etc. used across examples but no stdlib string API specified *(Resolved: §3.2.1, panel vote 5-0 generic Sized + StrOps traits, 5-0 codify 15 methods, 3-2 codepoint-default dual API, 4-1 named parse methods, 5-0 join now / StrBuf deferred)*
- [x] **Collection methods** — `.map()`, `.filter()`, `.collect()`, `.get()`, `.push()`, etc. used everywhere; no stdlib collection API *(Resolved: §3.2.2, panel vote 5-0 Contains shared trait + per-type traits, 3-2 expanded List 12 methods, 3-2 expanded Map 8 methods, 3-2 core Set 4+2 methods, 5-0 Type.new() + let mut)*
- [x] **`Ordering` type** — `cmp` returns `Ordering` (§3.6) but the type (`Less`, `Equal`, `Greater`?) is never defined *(Resolved: §3.6)*
- [x] **`Display` trait format protocol** — `Display.display()` returns `Str` (§3.6); how does `"{value}"` invoke it? Compiler magic? *(Resolved: §3.6 "Display Format Protocol", panel vote 5-0 strict Display bound, 5-0 two-phase desugaring, 5-0 Display is Str-context only)*

## Tier 3: Can Punt to Later

- [x] **FFI type mapping** — `Ptr[T]`, `Ptr[Void]`, `.as_cstr()`, `alloc_ptr` used (§9.1) but pointer types/ops not specified *(Resolved: §9.1.1, panel vote 4-1 non-null Ptr[T] with Option nullable, 5-0 minimal+deref ops, 3-2 scoped ffi.scope() cleanup)*
- [x] **Error catalog** — error codes referenced (E0004, E0310, E0500, E0501, E0601, etc.) but no complete catalog *(Resolved: ERROR_CATALOG.md, panel vote 3-2 names primary, 4-1 category ranges, 5-0 reassign collisions, 4-1 table format, 5-0 standalone file)*
- [ ] **`@perf` constraint grammar** — constraint syntax (`p99 < 200ms`, `memory < 50mb`) used (§11.2) but no formal grammar
- [x] **Testing framework** — `assert()`, `assert_eq()`, `panic()` used in test blocks but assertion API not defined *(Resolved: §2.19, panel vote 3-2 optional messages, 5-0 panic everywhere, 4-1 assert_matches, 4-1 expression introspection)*
- [ ] **Concurrency edge cases** — cancellation semantics, task panic propagation details, channel close behavior mentioned but not fully specified. §4.13
- [ ] **Arena escape analysis** — rules stated (§5.2) but interaction with closures, effect handlers, and return-value promotion needs detail
- [ ] **`@alt` annotation** — listed in §11.1 but usage/semantics barely described
- [x] **Stdlib distribution & import resolution** — stdlib modules ship with compiler but no resolution mechanism specified. How does `import std.toml` find files on disk? *(Resolved: §10.7, panel vote 4-1 implicit dependency model, 3-2 `std` prefix over `pact` prefix, 3-2 stdlib-as-dep resolution order)*
- [ ] **Stdlib tier boundaries** — `math`, `str`, `fmt` tier placement flagged as open in OPEN_QUESTIONS.md §2.2
- [ ] **`env.exit()` / `env.args()`** — used in examples but `Env` effect operations not enumerated
- [x] **Package manifest format** — `pact.toml` shown partially (§4.9) but full schema not specified *(Resolved: §8.9, panel vote 5-0 hybrid registry, 4-1 org/name namespacing, 4-1 MVS resolution, 4-1 caret constraints, 5-0 path+git MVP)*
- [ ] **Const evaluation** — struct defaults and keyword-arg defaults must be "compile-time constants" (§2.12, §2.13) but no const-eval rules
- [ ] **Serialization story** — every web service does JSON; no `@derive(Serialize)` or `@json("field")` equivalent. `@derive` exists, `@where` handles validation, but ser/de is unspecified. Language-level annotation vs stdlib trait vs library? "One way" principle argues for a blessed answer. Refinement types (`@where`) already cover validation; this is about codec dispatch and field mapping
- [ ] **Web-service stdlib tier** — HTTP client/server, JSON codec, SQL (type-safe via `Query[C]`?), logging, config — all heavily used by AI-generated code. Effect system provides primitives (`Net.*`, `IO.*`) but no blessed stdlib modules. Every third-party dep is a hallucination risk for AI. Question: stdlib tier 1 (ships with compiler) vs tier 2 (blessed but separate package)?
