# Spec Gaps — Pact v0.3

Unspecified or under-specified areas that need design work before a compiler can be built.

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
- [ ] **Pattern matching grammar** — spec says exhaustive matching is required (§3.5) but no algorithm or pattern language spec (nested, guards, OR-patterns, ranges)
- [ ] **Destructuring** — `let (a, b) = ...` and `let Foo { x, .. } = ...` shown (§3.5) but not formally specified. Nested? Irrefutable only?
- [ ] **`Self` type** — used in trait declarations (`self`, `Self`, `other: Self`) but never formally defined. §3.6
- [ ] **Closure capture semantics** — by-reference vs by-move inferred (§2.8) but no rules for when each applies
- [ ] **Module prelude** — `Option`, `Result`, `Ok`, `Err`, `Some`, `None` auto-imported (§10.1); complete list? `Bool`, `Int`, `Str`?

## Tier 2: Blocks Compiler Completion

- [ ] **Trait resolution & coherence** — orphan rules, impl overlap, where trait impls can live. §3.6
- [ ] **Effect polymorphism** — can a generic fn be polymorphic over effects? `fn map[T,U](f: fn(T) -> U ! ???)` §4
- [x] **Error type conversions** — `?` requires exact error type match. Explicit `.map_err(fn(e) { Target.from(e) })?` for conversion. §3c.2 *(Resolved: panel vote 4-1 no auto-conversion; DevOps dissented)*
- [ ] **Handler type system** — `Handler[E]` is used (§4.7) but how it interacts with effect subtyping, generics, storage is unspecified
- [ ] **Derive mechanics** — `@derive(Eq, Hash)` specified (§11.1) but what code is generated? How does it recurse through fields? §3.6
- [ ] **`Clone` trait** — listed as derivable (§11.1) but semantics (deep copy? GC implications?) not defined
- [ ] **String methods** — `.len()`, `.contains()`, `.to_upper()` etc. used across examples but no stdlib string API specified
- [ ] **Collection methods** — `.map()`, `.filter()`, `.collect()`, `.get()`, `.push()`, etc. used everywhere; no stdlib collection API
- [x] **`Ordering` type** — `cmp` returns `Ordering` (§3.6) but the type (`Less`, `Equal`, `Greater`?) is never defined *(Resolved: §3.6)*
- [ ] **`Display` trait format protocol** — `Display.display()` returns `Str` (§3.6); how does `"{value}"` invoke it? Compiler magic?

## Tier 3: Can Punt to Later

- [ ] **FFI type mapping** — `Ptr[T]`, `Ptr[Void]`, `.as_cstr()`, `alloc_ptr` used (§9.1) but pointer types/ops not specified
- [ ] **Error catalog** — error codes referenced (E0004, E0310, E0500, E0501, E0601, etc.) but no complete catalog
- [ ] **`@perf` constraint grammar** — constraint syntax (`p99 < 200ms`, `memory < 50mb`) used (§11.2) but no formal grammar
- [ ] **Testing framework** — `assert()`, `assert_eq()`, `panic()` used in test blocks but assertion API not defined
- [ ] **Concurrency edge cases** — cancellation semantics, task panic propagation details, channel close behavior mentioned but not fully specified. §4.13
- [ ] **Arena escape analysis** — rules stated (§5.2) but interaction with closures, effect handlers, and return-value promotion needs detail
- [ ] **`@alt` annotation** — listed in §11.1 but usage/semantics barely described
- [ ] **Stdlib tier boundaries** — `math`, `str`, `fmt` tier placement flagged as open in OPEN_QUESTIONS.md §2.2
- [ ] **`env.exit()` / `env.args()`** — used in examples but `Env` effect operations not enumerated
- [ ] **Package manifest format** — `pact.toml` shown partially (§4.9) but full schema not specified
- [ ] **Const evaluation** — struct defaults and keyword-arg defaults must be "compile-time constants" (§2.12, §2.13) but no const-eval rules
