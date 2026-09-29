[< All Decisions](../DECISIONS.md)

# Builtin Type Name Shadowing — Design Rationale

**Gap:** a user declaration that takes a builtin type name (`type Handle`, `type Handler`) was accepted at the declaration but could not be used: every annotation resolved to the builtin or to a type variable, and wrong arguments reached the C compiler with no Blink diagnostic. The spec had no rule for type names other than the prelude W1010 line.

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated
in independent-proposal → debate → vote rounds. Each panelist's text below is quoted in full, as written.

#### Phase A — Independent proposals

- **Systems:**

> ## Sys panelist: Phase A proposals
>
> ### Proposal 1 (preferred): split "language-owned" names from "prelude library" names
>
> **Tier R (reserved language-owned type names).** These are names whose meaning the compiler or runtime ABI fixes: a fixed C shape, intrinsic lowering, or a parser sentinel. Every declaration (`type`, type alias, `trait`, `effect`) that uses one of these names is an error, in every scope.
>
> - Scalars: `Int`, `Float`, `Bool`, `Str`, `Char`, `I8`..`I64`, `U8`..`U64`, `F32`, `F64`
> - Runtime handles: `Bytes`, `StringBuilder`, `Ptr`, `Handle`, `Channel`, `FfiScope`, `Raw`
> - Syntax and compiler types: `Fn`, `Tuple`, `Self`, `Template`, `Handler`, `Range`, `ConversionError`
>
> The spec lists these names in one table in §3.4. E0524 ReservedTypeName, which exists in the compiler today, becomes a spec diagnostic.
>
> ```blink
> type Handler {
>     n: Int
> }
> ```
> ```
> error[E0524]: `Handler` is a reserved type name
>  --> app.bl:1:6
>   |
> 1 | type Handler {
>   |      ^^^^^^^ the compiler owns this name (effect handler type, §4.7.1)
>   |
>   = help: rename the type, e.g. `AppHandler`
> ```
>
> **Tier P (prelude library types and traits):** `List`, `Map`, `Set`, `Option`, `Result`, `Ordering` and the non-sealed prelude traits. The §10.6 W1010 rule applies as written. A module-level declaration shadows the prelude name in that module and gets W1010. Every annotation, constructor and `impl` in that module resolves to the user declaration. One spec line must be added: **desugarings always target the builtin, never the name in scope.** This covers `T?`, the `?` operator, `for` iteration, `==`/`<` dispatch and `??`. Without that line, a shadowed `Option` silently changes what `x?` compiles to.
>
> ```blink
> type Option {
>     on: Bool
> }
> fn flag() -> Option { Option { on: true } }
> fn find(xs: List[Int]) -> Int? { xs.get(0) }
> ```
> ```
> warning[W1010]: name shadows prelude type
>  --> app.bl:1:6
>   |
> 1 | type Option {
>   |      ^^^^^^ shadows prelude type `Option`
>   |
>   = help: consider a different name to avoid confusion
> ```
> In this example, `Int?` still means the builtin `Option[Int]`.
>
> **Stdlib-declared names that are not prelude** (`Duration`, `Instant`) are ordinary members of `std.time`. The compiler drops them from its owned-name set, and normal import rules apply. A user `type Duration` in a module that does not import `std.time.Duration` is a plain local type and gets no diagnostic. If the module imports it too, the existing duplicate-name error applies.
>
> **Handler contradiction.** §10.6 says to import `Handler`, but §4.7.1 uses it with no import. Resolve this the same way as `ConversionError` in §10.7: `Handler[E]` is compiler-known, usable without an import, and optionally importable from `blink.core` as an inert marker. It is Tier R.
>
> **Tradeoffs (systems view)**
> - This costs nothing at run time. The whole question is whether codegen stays predictable. Tier R names are keyed by bare name at many codegen sites: intrinsic dispatch, layout, C spelling. pp04ey shows what happens when a user declaration reaches those sites: a typevar unifies with everything, and the error surfaces in `cc`. Making each of those sites scope-aware would add a latent-bug surface to the compiler and give users nothing in return. Reserving the names closes that surface at one check at the declaration.
> - Tier P types are generic containers that lower through mono like any user type. Once the desugar rule pins the builtin, shadowing them is cheap and correct.
> - The cost: the Tier R list is closed and ships with the language. Adding a new runtime type later (e.g. `Atomic`) is a breaking change for any user who already declared that name. Rust and Zig accept the same cost.
> - Migration touches two test files (`type Handle { raw: Ptr[U8] }`) and the `fmt` fixtures (`type Handler = fn(...)`), which need a rename. No file in `src/` or `lib/std` breaks: `Ordering` is Tier P, and `Duration`/`Instant` leave the owned-name set.
>
> ### Proposal 2 (fallback): reserve every compiler-known name
>
> Tier R ∪ Tier P are all errors (E0524), and W1010 is deleted for types. This is the simplest rule and the simplest implementation. However, it reverses a written spec rule, and the prelude-trait W1010 path is already implemented (a user `trait Eq` wins in its module). I rank it second. Its gain over Proposal 1 is small because the desugar rule already removes the one real hazard in Tier P.
>
> ### Rejected: "user declaration wins everywhere"
>
> Letting a user declaration win for `Ptr`, `Bytes` or `Handle` means the name `Ptr` in a module may not be the FFI pointer. Then every `ffi.*` call, `@ffi` signature check and C-layout decision needs scope-aware resolution. The cost is high, the bug class is exactly pp04ey, and no real program needs it.
>
> ### Cross-language note
>
> - **Zig** rejects declarations that shadow primitives (`i32`, `u8`) with a hard error. This is the Tier R model.
> - **Rust** allows a user type named like a primitive, e.g. `struct u8;` (it is legal but lint-flagged), and resolves primitives through a special fallback path. That path is a known source of confusing errors. Rust's prelude types (`Option`, `Vec`) shadow cleanly, and `?` desugars to `core::ops::Try` regardless of what is in scope. This is the Tier P desugar rule.
> - **Go** lets you shadow `int` and `error`, which gives confusing programs and no benefit.

- **Web/Scripting:**

> **Web/Scripting panelist: Phase A proposal**
>
> ### Proposal W1: "Your name wins." A user's type always shadows a builtin, and only `Self` is reserved
>
> Web and scripting developers name things `Handler`, `Handle`, `Channel`, `Duration`, `Request` and `Response` all day. `type Handler` is probably the most common type name in any HTTP codebase. A rule that rejects `type Handler` makes the user rename their core domain type for a feature they may never use: effects. That is exactly the kind of rule that ends up as a Stack Overflow question ("why can't I name my type Handler?").
>
> The rule has three tiers, keyed on what the user can see and not on the compiler's internal list:
>
> 1. **Prelude names** (the §10.6 tables: `List`, `Option`, `Result`, `Ordering`, ...). A user declaration is legal, and it wins everywhere in its module. The compiler emits the W1010 warning that §10.6 already specifies. The compiler must also implement W1010 for types (today it has zero hits for types).
> 2. **Compiler-known names outside the prelude** (`Handler`, `Handle`, `Channel`, `Bytes`, `StringBuilder`, `Ptr`, `Template`, `Raw`, `FfiScope`). A user declaration is legal, it wins in its module, and there is no warning. The user never asked for these names, so a warning would be noise. The builtin stays reachable through `blink.core`.
> 3. **Reserved: `Self` only.** It gets the E0524 diagnostic, written into §3.4. `Fn` and `Tuple` are parser tags that users never type as type names, because the surface syntax is `fn(A) -> B` and `(A, B)`. The parser must stop leaking those tags into the user namespace. The implementation's shortcut should not cost users two names.
>
> ```blink
> type Handler {
>     route: Str
>     status: Int
> }
>
> fn serve(h: Handler) -> Int {
>     h.status
> }
>
> fn main() {
>     io.println("{serve(Handler { route: "/", status: 200 })}")
> }
> ```
>
> This compiles clean, with no diagnostic. `serve(5)` now fails at the Blink level with a normal type error (E0308-style). It no longer slips through to cc.
>
> A module that needs both its own type and the effect handler type imports the builtin under another name:
>
> ```blink
> import blink.core.{Handler as EffectHandler}
>
> fn mock_db(rows: List[Str]) -> EffectHandler[DB] {
>     handler DB { ... }
> }
> ```
>
> Shadowing a prelude name gives the warning:
>
> ```
> warning[W1010]: type `Option` shadows prelude type `Option`
>   --> src/app.bl:1:6
>   |
> 1 | type Option { label: Str }
>   |      ^^^^^^
>   = note: in this module, `Option` means this type; the prelude `Option[T]` is unreachable by that name
>   = help: rename it, or import the prelude type under another name: `import blink.core.{Option as Maybe}`
> ```
>
> Reserving `Self` gives the error:
>
> ```
> error[E0524]: `Self` is reserved and cannot name a type
>   --> src/app.bl:1:6
>   |
> 1 | type Self { n: Int }
>   |      ^^^^
>   = help: choose another name
> ```
>
> **Spec clean-up that goes with W1:**
> - In §10.6, move `Handler[E]` into the "compiler-known, usable without import" group (the `blink.core` group in §10.7). This matches the §4 examples, which use `Handler[DB]` with no import.
> - `Duration` and `Instant` come from `std.time`, so they are ordinary module names. A user `type Duration` in a file that also imports `std.time.{Duration}` is a plain duplicate-name error, which is the rule that already exists.
> - **Hard requirement for every option:** a type name must never resolve to a type variable. If resolution cannot find a type, the compiler emits an error.
>
> **Tradeoffs from the DX side:**
> - (+) Zero friction in the 90% case. The user picks a normal name and it works.
> - (+) "Local declaration wins" is the rule JavaScript, Python, Kotlin and TypeScript users already know.
> - (+) The reserved list has one entry, `Self`, so there is nothing to memorize.
> - (−) When a user reads code that uses `Handler`, they must check the module to learn which `Handler` it is. The damage stays inside the module, and `blink query` or the LSP answers the question.
> - (−) If a module shadows `Handler` and then writes `handler DB { }`, the result type cannot be named without the aliased import. Mitigation: when the expected type is the user's `Handler` and the found type is the effect handler, the error's `help:` line suggests the `as` import.
>
> ### Proposal W2 (rejected alternative): forbid every compiler-known name
>
> This means an E0524-style error for all 35 names in `is_primitive_type`. It is simple to implement, but:
> - The list of forbidden names follows compiler internals (`Raw`, `FfiScope`, `Template`) that users cannot see or predict.
> - It breaks our own test fixtures (`type Handle`, `type Handler = fn(...)`).
> - Each new builtin becomes a breaking change for any user code that already uses that name.
>
> **Cross-language note:** In TypeScript, a user type can shadow a global type (a local `interface Response` is legal). Python lets you rebind `list`, and linters warn. Kotlin lets a local class shadow a `kotlin.*` name, and an explicit import disambiguates. Rust allows `struct Box` and `struct Option`. None of these languages reserves ordinary type names. W1 matches all four.

- **PLT:**

> # PLT panelist — Phase A submission (4k7y77)
>
> **The core defect is a scoping error, not a naming one.** A type name must resolve **once**, at name resolution, to **one** declaration identity. Typecheck must never resolve a name again by its string, and a name that fails to resolve must never become a type variable. Only an explicit `[T]` binder creates a type variable. The pp04ey behaviour, where `Handler` becomes `make_typevar`, is unsound: a variable that unifies with anything makes every check on that type vacuous. Any policy the panel picks has to fix this first.
>
> ## Proposal P1 (recommended): lexical shadowing, hygienic desugaring, one reserved name
>
> 1. **One table.** §10.6 lists every compiler-known type name once, each with a class:
>    - *syntactic*: `Self`
>    - *prelude*: the current tables
>    - *ambient*: known to the compiler and usable without an import, but not in the prelude. That is `Handler`, `Handle`, `Template`, `Range`, `ConversionError`, `Ptr`, `Channel`, and the others.
>
>    This also fixes a conflict in the text. §10.6 says "import Handler", but §4 uses `Handler[DB]` with no import. "Ambient" matches what §10.7 already says for `ConversionError`.
> 2. **Resolution order**, innermost first: type parameters, then module declarations and explicit imports, then prelude and ambient names. The user declaration wins in its module.
> 3. **W1010 covers every compiler-known type name**, prelude or ambient. Today it covers only prelude traits.
> 4. **Only `Self` is reserved.** It is a contextual binder, like a keyword, so shadowing it is an error (E0524, now written into the spec). `Fn` and `Tuple` are not in the surface language. The spec has only `fn(A) -> B` and `(A, B)`. Their collision comes from the parser using those names as internal tags, which is an implementation leak. The compiler must tag these with spellings no user can write, and the spec must not reserve them.
> 5. **Hygiene.** When the compiler inserts a type itself, it refers to the builtin by identity, not by name. This covers the result of `async.spawn`, the `Handler[E]` check in `with`, the automatic `Template[C]`, `..` producing `Range`, `?` producing `Result`, and `for` using `Iterator`. A user `type Handle` cannot capture any of these.
>
> ```blink
> type Handle {
>     raw: Ptr[U8]
> }
>
> fn open() -> Handle { Handle { raw: ffi.null_ptr() } }
>
> fn run() -> Int ! Async {
>     let t = async.spawn(fn() { 42 })
>     t.await
> }
> ```
>
> The inferred type of `t` is the builtin `Handle[Int]`, not the user's `Handle`. Output:
>
> ```
> warning[W1010]: name shadows compiler-known type
>  --> main.bl:1:6
>   |
> 1 | type Handle {
>   |      ^^^^^^ shadows compiler-known type `Handle`
>   = help: consider a different name; `async.spawn` still returns the builtin `Handle[T]`
> ```
>
> If the user writes an annotation that mixes the two, the error must name both sides with their origin:
>
> ```
> error[E0308]: type mismatch
>   expected `Handle` (main), found `Handle[Int]` (blink.core)
> ```
>
> The same holds for names that the stdlib declares in source, such as `Ordering`, `Duration` and `Instant`. They are ordinary nominal declarations. A user `type Duration` shadows the stdlib one inside its module, and the two stay distinct types.
>
> **Escape path.** A module that shadows `Handle` can still name the builtin with `import blink.core.{Handle as Task}`. `blink.core` imports are inert today; this proposal gives them this one job.
>
> **Tradeoffs**
> - *Compositional and monotone.* When a new compiler version adds a compiler-known name, code that already declares that name still compiles and gets a warning. A reserved list that grows makes every release a possible breaking change.
> - *One rule.* Types follow the same rule that §10.6 already applies to values and traits. The only exception, `Self`, is one that has a principled reason.
> - *Cost.* Error messages must qualify a type by its origin whenever two types with the same name meet. That is a real obligation on the diagnostics.
>
> ## Proposal P2 (alternative, not recommended): reserve all compiler-known type names
>
> Any `type X` where `X` is in the table is an error:
>
> ```blink
> type Handler { n: Int }
> // error[E0524]: `Handler` is a reserved type name
> //   = help: rename the type
> ```
>
> This is simpler to implement, and a reader never sees two meanings for one name. The costs:
> - The reserved set is not closed, so it breaks the monotonicity point above.
> - It contradicts the existing W1010 text (`type Ordering` is shown as legal).
> - It rejects code that is already in-repo: `type Handle` in `tests/test_cg_derive_*_bodies.bl`, and the `type Handler = fn(...)` alias in the formatter fixtures.
>
> ## Cross-language note
>
> OCaml lets `type option = ...` and `module List = ...` shadow the standard ones lexically, and `Stdlib.List` stays reachable. P1's `blink.core` escape path is the same idea. Haskell's `NoImplicitPrelude` and `import Prelude hiding (...)` show that hiding by scope composes. Rust makes `Self` a keyword but allows `struct Box` and `struct Option`, and its macros insert paths like `::core::option::Option`, which is P1's hygiene rule. Koka handles `handler` as syntax, not as a type name. Blink already has `handler` as a keyword, so `Handler` has no need to be reserved.
>
> **Vote: P1.** Its non-negotiable parts are the identity-based resolution with no typevar fallback, and the hygiene rule.

- **DevOps:**

> # DevOps/Tooling proposals: user types named like builtin types
>
> My test for any option is simple. Every type name must resolve to exactly one declaration, and the LSP's go-to-definition must land on that declaration. Today the compiler breaks this rule: it accepts the declaration, then quietly sends every use of the name somewhere else. If a program compiles cleanly in Blink and then fails in `cc`, the toolchain has a bug. The spec must forbid that outcome in plain words.
>
> ## Proposal A (preferred): a small reserved set, and everything else may be shadowed with W1010
>
> **A1. Add an invariant to §3.4.** If the compiler accepts a `type` declaration, code in the same module can name that type. Each implementation then has only two choices at the declaration site: resolve the name to the user's type, or reject the declaration.
>
> **A2. Name one closed reserved set, and make it an error to declare these names.** The set is `Fn`, `Tuple` and `Self`. These names carry syntax: the parser uses them to tag tuple, function and self-type annotations. Add E0524 to the spec:
>
> ```blink
> type Tuple[X] {
>     val: X
> }
> ```
> ```
> error[E0524]: `Tuple` is reserved and cannot name a user type
>  --> main.bl:1:6
>   |
> 1 | type Tuple[X] {
>   |      ^^^^^ reserved: the compiler uses this name for tuple types
>   = help: rename the type, e.g. `type Pair[X]`
> ```
>
> **A3. Every other compiler-known type name may be shadowed.** This covers the prelude tables, plus `Handle`, `Channel`, `Bytes`, `StringBuilder`, `Duration`, `Instant`, `Ptr`, `Handler` and `Template`. The user's declaration wins in its module, and the compiler reports W1010 once, at the declaration, never at each use. W1010 today covers only traits, so its text must widen from "prelude type" to "compiler-known type":
>
> ```blink
> type Handle {
>     raw: Ptr[U8]
> }
> fn close(h: Handle) -> Int { 1 }
> ```
> ```
> warning[W1010]: `Handle` shadows the compiler-known type `Handle[T]`
>  --> main.bl:1:6
>   |
> 1 | type Handle {
>   |      ^^^^^^ this module now uses this type for `Handle`
>   = note: `async.spawn` still returns the built-in `Handle[T]`
>   = help: rename it, or import the built-in under another name:
>           import blink.core.{Handle as TaskHandle}
> ```
>
> **A4. Give each shadowed builtin a way back in.** Every compiler-known type can be imported under an alias from its pseudo-module (`blink.core` or `blink.ffi`). Without this, a module that declares its own `Handle` has no way to spell the built-in `Handle[T]`. The alias form, as in `import auth.{Error as AuthError}`, is already in §10.6.
>
> **A5. Fix the `Handler` inconsistency.** `Handler[E]` is compiler-known and needs no import, as §10.7 already says for `ConversionError`. Remove the "Import when writing handler functions" line from §10.6 so it agrees with the examples in §4.
>
> **Tradeoffs:**
> - The main reason to prefer A is that adding a builtin name later stays a non-breaking change. If every compiler-known name were forbidden, each new stdlib type such as `Instant` would break every user program that already declared that name.
> - LSP: hover on the declaration shows the W1010 note, go-to-definition resolves to the user's type, and completion lists the local declaration first.
> - `blink fmt` does not change.
> - Cost: `Handle` can mean two things across modules, and readers who grep for it have to check which one they found.
>
> **Cross-language:** Go's predeclared identifiers (`int`, `error`) can be shadowed, and only keywords are reserved. Rust's prelude types can be shadowed, and you reach the originals through `std::`. rust-analyzer handles both cases well because every name resolves one way.
>
> ## Proposal B (fallback): forbid every compiler-known type name
>
> Widen E0524 to cover the whole list in §10.6 plus the §10.7 set:
>
> ```
> error[E0524]: `Handler` is a compiler-known type and cannot be redeclared
>   = help: rename the type
> ```
>
> **Tradeoffs:**
> - For: the simplest resolver and LSP of any option, since no name ever means two things.
> - Against: every new builtin is a breaking change, and the stdlib's own `pub type Duration` and `pub type Instant` need a carve-out.
> - Against: this contradicts §10.6, which already allows shadowing a prelude name with W1010, so we would reverse a decision the spec has already shipped.
> - I would vote for B only if the panel rejects the A4 way back in.
>
> ## Rejected: silent shadowing with no diagnostic
>
> This is what the ticket's literal reading of the spec says `Handler` should do today. From the tooling side it is the worst option. A user reads `Handle` in a code review and has no signal that it is not the built-in type. At a minimum the compiler must warn.
>
> **My vote: A.** It needs three gate tests: the pp04ey MVCE (an argument of the wrong type gets a Blink error, not a `cc` error), W1010 on `type Handle`, and E0524 on `type Tuple`.

- **AI/ML:**

> **AI/ML panelist, Phase A: user type names that match compiler-known type names**
>
> ## Proposal 1 (preferred): a closed list of reserved type names, with a hard error
>
> **Rule.** The spec gets one closed table: **Reserved type names**. It holds every type name the compiler knows, whether or not the name is in the prelude:
>
> - **Prelude types:** Int, I8–I64, U8–U64, Float, F32, F64, Str, Char, Bool, Void, List, Map, Set, Option, Result, Ordering
> - **Other compiler-known types:** Handler, Handle, Channel, Bytes, StringBuilder, Instant, Duration, Ptr, Raw, FfiScope, Template, Range, ConversionError, Fn, Tuple, Self
>
> If a `type`, `trait`, or type alias uses one of these names, the compiler reports an error. E0524 ReservedTypeName already exists; we widen it to cover the whole table and write it into the spec. The only code allowed to declare these names is the stdlib module that defines them, such as `lib/std/time.bl` for `Duration` and `lib/std/traits.bl` for `Ordering`. That module's declaration *is* the builtin, not a shadow of it.
>
> ```blink
> type Handler {
>     n: Int
> }
>
> fn use_it(h: Handler) -> Int {
>     h.n
> }
> ```
>
> ```
> error[E0524]: `Handler` is a reserved type name
>  --> app.bl:1:6
>   |
> 1 | type Handler {
>   |      ^^^^^^^ compiler-known type (effect handler, §4.7.1)
>   |
>   = help: rename it, e.g. `type EventHandler { ... }`
> ```
>
> The shadowing rule in §10.6 changes. W1010 applies to **value** names and **trait** names only. Type names on the reserved list cannot be shadowed, the same as keywords. We also fix the §10.6/§4.7.1 conflict: `Handler[E]` and `Range[T]` behave like `ConversionError` (§10.7). They are compiler-known, you can use them without an import, and `import blink.core.{Handler}` stays a no-op you can add as documentation.
>
> **Tradeoffs (learnability and generability)**
>
> - **One question to answer.** "Is this name on the table?" A model can learn a closed list from the spec alone. Today's rules have three levels: keywords can't be shadowed, prelude names can be shadowed with a warning, and non-prelude names can be shadowed with no warning. The spec also contradicts itself on Handler. No model gets that right from reading the spec.
> - **Reading a file.** When a model reads `Handler[DB]` or `Duration` in any Blink file, it can trust what the name means without scanning the module for a local declaration that replaces it. Token cost for that check drops to zero.
> - **Error messages.** Models generate names like `Handler`, `Handle`, `Channel`, and `Duration` very often, because web and scripting code uses them all the time. If shadowing is allowed, the failure appears far from the cause: a `with` clause breaks, or `.await` resolves to the wrong type. A hard error at the declaration, with a rename hint, is a one-step fix, and models apply rename hints reliably.
> - **Cost.** Some natural names are no longer available, and the reserved list will grow over time (a new stdlib type is a breaking change). One fixture must change: the formatter's `type Handler = fn(...)`.
>
> **Other languages.** Rust lets you shadow `Option` and `String`, and models do trip on it (`use std::result::Result` vs. `io::Result`). Go lets you shadow `error` and `string`, and linters flag it. Swift and Kotlin reject few names. Blink should take the stricter end, because its readers include machines.
>
> ## Proposal 2 (fallback): the user declaration wins, and every such name gets W1010
>
> A user declaration beats the builtin inside its module, for all names on the reserved list. W1010 fires every time. Fn, Tuple, and Self stay hard errors (E0524) because the parser uses them.
>
> ```
> warning[W1010]: type `Handle` shadows compiler-known type `Handle` (returned by async.spawn)
> ```
>
> **Tradeoff.** This is less strict, but it gives models two rules to learn (the error list and the warning list). The meaning of a name also depends on which module you are in, and `async.spawn` in that module becomes very confusing. Both proposals share one requirement: the current behavior, where a user type silently resolves to a type variable, must go away. Proposal 2 fixes that too, but it leaves more ways to get it wrong.
>
> ## Vote position
>
> Proposal 1. A closed table, one error code, a rename hint, and Handler usable with no import. This gives models the fewest choices to make, and it is the only option a model can learn fully from the spec.

- **Minimalism:**

> ## Minimalism (Min): Phase A proposal for spec gap 4k7y77
>
> ### Proposal M1 (preferred): One reserved set of type names, one error, no type shadowing
>
> **Rule.** §10.6 gets a single table, "Compiler-known type names". It holds every prelude type plus the compiler-known types outside the prelude (`Handler`, `Handle`, `Range`, `ConversionError`, `Channel`, `Bytes`, `StringBuilder`, `Ptr`, `Fn`, `Tuple`, `Self`, and so on). A module-level `type` declaration or type alias that uses one of these names is a compile error. There is no scoped "user decl wins" rule for types and no W1010 for types.
>
> ```blink
> type Handler {
>     n: Int
> }
>
> fn use_it(h: Handler) -> Int { h.n }
> ```
>
> ```
> error[E0524]: type name `Handler` is reserved
>  --> app.bl:1:6
>   |
> 1 | type Handler {
>   |      ^^^^^^^ `Handler` is a compiler-known type (§10.6)
>   |
>   = help: choose a different name, e.g. `ConnHandler`
> ```
>
> The same error covers `type List[T] { ... }`, `type Ordering { ... }` and `type Handler = fn(Str) -> Bool`.
>
> **Three subtractions come with it:**
>
> 1. **Delete the type example from §10.6 Shadowing Rules.** Today the spec says `type Ordering` is legal with W1010. W1010 was never implemented for types (0 hits), so we delete a promise nobody built instead of building it.
> 2. **Keep the compiler's list inside the spec's list.** The compiler's `is_primitive_type` list may not hold a name the spec's table leaves out. `Duration` and `Instant` are ordinary `pub type` declarations in `lib/std/time.bl`. Demote them to plain stdlib names that resolve through `import std.time` like any other module name. They leave the compiler-known list instead of growing the reserved set. Internal names such as `Template`, `FfiScope` and `Raw` must either be specified in the table or leave the user namespace.
> 3. **Drop "Import when writing handler functions" from §10.6.** Treat `Handler[E]` the way §10.7 treats `ConversionError`: compiler-known and usable with no import. §4 already writes `Handler[DB]` with no import, so this deletes a contradiction instead of adding an import rule.
>
> **E0524 already exists** in the compiler for `Tuple`/`Fn`/`Self`. We specify it and widen its list. We do not add a new code.
>
> **Tradeoffs (Minimalism lens):**
> - **Expressive loss is zero.** A user who wants their own `Handler` renames it, and that costs one identifier. Shadowing adds no power, only a second meaning for a name.
> - **Combinatorial cost is avoided.** "User decl wins in its scope" makes every compiler site that matches on the text `"Handle"` or `"List"` scope-aware: typecheck, mono, layout, cname and derive. It also leaves the shadowing module with no way to name the builtin, because Blink has no `blink.core.Handler` qualified path, so one more feature would follow. Each of those is a new place for exactly the silent mistyping pp04ey describes.
> - **It fits prior decisions.** Module-level `let` duplicates are an error (5-0). Effect-handle names are reserved (5-0). Sealed traits cannot be redefined (6-0). Blink already prefers "error at module level" to "shadow with a warning".
> - **The cost is breaking.** Two corpus tests declare `type Handle { raw: Ptr[U8] }` and the fmt fixtures alias `type Handler`. They need a rename, not a test deletion.
> - **Two things stay unchanged.** Type parameters named like builtins (§3.4) still work, and W1010 for traits (`trait Eq`) is not touched by this proposal. A later ticket can unify traits under the same rule.
>
> **Cross-language:** Go lets you write `type int string`, and the `predeclared` linter exists to flag it. Java's `class String` is a standard puzzler. Python's `list = ...` is a well-known beginner trap. Each language allowed this shadowing and then built tools to warn against it. Zig and C reserve their builtin type names outright, and nobody asks for them back.
>
> ### Proposal M2 (fallback, if the panel insists on shadowing): Prelude-only shadowing with W1010, everything else reserved
>
> - Prelude type names (`List`, `Option`, `Ordering`, ...): the user decl wins in its module, with W1010 as §10.6 says today.
> - Every other compiler-known name (`Handler`, `Handle`, `Fn`, `Tuple`, `Self`, `Ptr`, ...): E0524.
>
> This keeps the current text but still needs scope-aware resolution in every codegen stage for the prelude names. It also means `Option` in module A and module B can name different types, which hurts readers and any tool that resolves names by text. I vote against M2. It is listed only so the panel does not fall back to "user wins everywhere", which is the worst option: it needs the most machinery and still lets a wrong type reach the C compiler.
>
> ### Do nothing: reject
>
> Today the declaration is accepted and every use of the name silently resolves to the builtin or to a typevar. That is a soundness bug, not a policy we could keep.
>
> **Vote intent:** M1.

#### Phase A.5 — Mechanical dedupe (moderator)

> # Phase A.5 — mechanical dedupe (4k7y77)
>
> Full Phase A texts: scratchpad/phaseA_{sys,web,plt,devops,aiml,min}.md (read all six).
>
> ## Main question: which type names may a user declaration take, and what happens?
>
> **Option R — reserve every compiler-known type name (widen E0524).**
> Proposed as first choice by: AI/ML (Proposal 1), Min (M1).
> Listed as fallback/alternative by: Sys (Proposal 2), DevOps (Proposal B), PLT (P2, "not recommended"), Web (W2, "rejected alternative").
> Variations:
> - R-a: W1010 for prelude *traits* is untouched (Min); W1010 applies to value and trait names only (AI/ML).
> - R-b: stdlib modules that define a reserved name (e.g. lib/std/time.bl `Duration`) are the builtin, not a shadow (AI/ML) vs `Duration`/`Instant` leave the compiler-known list and become plain std.time names (Min).
>
> **Option T — two tiers: reserve language-owned names; prelude library types shadow with W1010.**
> Proposed as first choice by: Sys (Proposal 1).
> Listed as fallback by: Min (M2, "I vote against M2").
> Variations:
> - T-a: what is in the reserved tier. Sys: scalars (Int, Float, Bool, Str, Char, I8..I64, U8..U64, F32, F64), runtime handles (Bytes, StringBuilder, Ptr, Handle, Channel, FfiScope, Raw), and Fn, Tuple, Self, Template, Handler, Range, ConversionError; shadowable tier = List, Map, Set, Option, Result, Ordering + non-sealed prelude traits. Min M2: shadowable tier = all prelude type names; everything else reserved.
> - T-b: Sys adds "desugarings always target the builtin, never the name in scope" (`T?`, `?`, `for`, `==`/`<`, `??`).
> - T-c: Sys covers `type`, type alias, `trait`, `effect` declarations.
>
> **Option S — user declaration wins in its module for (almost) every name; W1010 on every compiler-known name; small reserved set.**
> Proposed as first choice by: DevOps (Proposal A), PLT (P1).
> Listed as fallback by: AI/ML (Proposal 2).
> Variations:
> - S-a: reserved set. DevOps and AI/ML P2: `Fn`, `Tuple`, `Self`. PLT: `Self` only — `Fn`/`Tuple` are an implementation leak; the compiler must tag with spellings users cannot write.
> - S-b: escape path to the builtin via `import blink.core.{Handle as TaskHandle}` / `blink.ffi` alias (DevOps A4, PLT).
> - S-c: hygiene — compiler-inserted types (async.spawn result, `with` Handler check, Template[C], `..` Range, `?` Result, `for` Iterator) refer to the builtin by identity (PLT; DevOps W1010 note "async.spawn still returns the built-in").
> - S-d: diagnostics qualify a type by origin when two same-name types meet (PLT).
> - S-e: invariant in §3.4 "if the compiler accepts a `type` declaration, code in the same module can name that type" (DevOps A1).
>
> **Option W — user declaration wins; W1010 only on prelude names; no diagnostic on non-prelude compiler-known names; reserve `Self` only.**
> Proposed as first choice by: Web (W1).
> Variations: escape via `import blink.core.{Handler as EffectHandler}`; `Fn`/`Tuple` not reserved (parser must stop leaking tags) — same as PLT S-a.
>
> **Rejected by at least one panelist, proposed by none:** do nothing (Min, DevOps); silent shadowing of every name with no diagnostic (DevOps; Sys rejects "user wins everywhere").
>
> ## Cross-cutting points (appear in several proposals; flagged so the panel can confirm or dispute)
>
> X1. No type name may resolve to a type variable; only an explicit `[T]` binder creates one. An unresolved name is an error. (PLT, Web, AI/ML, DevOps, Min, Sys all describe the pp04ey behaviour as a bug.)
> X2. `Handler[E]` becomes compiler-known and usable without import, like `ConversionError` in §10.7; drop "Import when writing handler functions" from §10.6. (All six.)
> X3. `Duration` / `Instant` (declared in lib/std/time.bl): plain std.time names outside the compiler-known set (Sys, Web, Min) vs reserved with the stdlib decl being the builtin (AI/ML) vs shadowable nominal decls with W1010 (PLT, DevOps).
> X4. `Fn` / `Tuple`: reserved (Sys, DevOps, AI/ML, Min) vs not reserved, fix the parser leak (PLT, Web).
> X5. `Template`, `FfiScope`, `Raw`: must be specified in the table or leave the user namespace (Min); listed as reserved (Sys, AI/ML) or shadowable (DevOps, Web).
> X6. Which declaration kinds the rule covers: `type` + alias (Min), + `trait` (AI/ML), + `trait` + `effect` (Sys).
> X7. Future compiler-known names: reserved list growth is a breaking change (raised by Sys, DevOps, PLT, Web, AI/ML).

#### Phase B — Debate (round 1)

Four of six panelists signalled "stable, ready to vote" after round 1. The Phase C ballot records where each panelist stood after round 1: Web moved from W to S-self, and Sys ranked T second behind S-lit.

- **Systems:**

> ## Sys, Phase B round 1
>
> **I am changing my position. I move from T toward S, with a narrower reserved set.**
>
> In Phase A, my main case against shadowing was cost: each codegen site that keys on the bare name `"Handle"` would need to become scope-aware. PLT's X1 removes that cost. If name resolution maps each type name once to a declaration identity, then typecheck, mono, layout and cname see a tid, never a string. After that, a user `Handle` and the builtin `Handle[T]` are two different tids, and codegen needs no scope logic. So the pp04ey bug class is "resolve by string", not "shadowing". R without X1 still leaves the string-keyed sites in place, and the next collision gets through them. **X1 is non-negotiable for every option.** I would add one spec line: an unresolved type name is an error, and only a `[T]` binder makes a type variable.
>
> **What I still reserve, and why: `Self` plus the literal/scalar types** (`Int`, `I8`..`I64`, `U8`..`U64`, `Float`, `F32`, `F64`, `Bool`, `Str`, `Char`, `Void`). These names are what literals produce, and they have fixed machine shapes. With hygiene, `type Int` would be sound, but every `1` in that module would then mismatch the user's `Int`. That is a trap with no use. Zig reserves exactly this set. The set can only grow with a new literal kind, which changes the language anyway, so X7's growth problem does not apply to it.
>
> **Everything else compiler-known may be shadowed (S):** `Handler`, `Handle`, `Channel`, `Bytes`, `StringBuilder`, `Ptr`, `Template`, `Range`, `ConversionError`, `FfiScope`, `Raw`, and the prelude types, including `Ordering`. The user declaration wins in its module, with W1010 at the declaration. Web is right that `Handler` and `Handle` are the most common domain names in HTTP and file code. Rejecting them costs users more than it saves us.
>
> **Conditions I attach to S (all from the dedupe):**
> - **S-c / T-b hygiene.** Desugars and compiler-inserted types (`async.spawn`, `with`, `T?`, `?`, `..`, `for`, `??`, `==`/`<`) refer to the builtin by identity. This was my T-b, and PLT's S-c says the same thing.
> - **S-b escape.** Every ambient name can be imported under an alias from `blink.core` or `blink.ffi`. This answers Min's point that "no qualified path exists", and the cost is small.
> - **S-d.** When two types with the same name meet in a diagnostic, it qualifies each by origin.
> - **X7 policy.** The ambient set is frozen. A new builtin type goes in a named std module (the way `Duration` is in `std.time`), not in the ambient namespace. This makes new builtins non-breaking under S, and keeps the reserved list closed under any option.
>
> **X4 (`Fn`/`Tuple`).** I agree with PLT and Web. The surface syntax is `fn(A) -> B` and `(A, B)`, so these names are parser tags leaking out. The parser must tag with spellings that users cannot write. The spec must not reserve implementation artifacts.
>
> **X3.** `Duration` and `Instant` are plain `std.time` names. They get no W1010, because they are not ambient, and the normal duplicate-import error covers a clash.
>
> **X6.** The rule covers `type`, type alias, `trait` and `effect`, because all four declare names in the type namespace.
>
> **To AI/ML and Min.** Your learnability point stands: under my rule, the reserved list is closed, has 17 entries, and follows one principle ("types a literal can have, plus `Self`"). Min's machinery argument depends on string-keyed resolution, and X1 removes that anyway. R also forces breaking reservations whenever the ambient set grows.
>
> **Vote order now: S (reserved = `Self` + scalars, with hygiene, escape, frozen ambient set) > T > R.**
>
> SIGNAL: stable, ready to vote

- **Web/Scripting:**

> **Web, Phase B round 1**
>
> **I am moving from W to S, in PLT's form (S-a with only `Self` reserved, plus S-c hygiene).** AI/ML is right that my W had three tiers: reserved, warn, and silent. S has two: `Self` is an error, and every other compiler-known name gets W1010. The warning appears once, at the declaration, and a web developer can live with that. I drop the silent tier.
>
> **Against R (AI/ML, Min).**
> - *X7 decides it for me.* Under R, adding any compiler-known name is a breaking change. `Duration`, `Instant`, `Channel` and `Handle` are exactly the names that real apps already use. Suppose we add `Request`/`Response` for a `std.http` later. Under R, every web app that already declares them breaks. Under S, those apps get a warning.
> - *"Models generate `Handler` often" argues against R.* It means R's error fires on the most common names in web code, over and over. For a model, a rename hint is one step. For a human it is friction that becomes a Stack Overflow question, and the human asks it 10 times a year.
> - *Min's "codegen must become scope-aware".* That cost already exists, whatever we choose. X1 requires every name to resolve once, to one identity. After that fix, a codegen site that still matches the text `"Handle"` is a bug under R as well, because R only hides it. R is not cheaper once X1 is done; it only removes a user freedom.
> - *Min's "no qualified path to the builtin".* The alias import form (`import auth.{Error as AuthError}`) is already in §10.6. S-b only needs `blink.core` to export the compiler-known names. That is a small addition to a module that §10.7 already defines, not a new feature.
>
> **On T (Sys).** I will meet Sys partway, but not on `Handler`, `Handle` or `Channel`. Those are core domain names in HTTP and messaging code, and reserving them is the single most hostile choice on the table for my users. What I can accept is a narrow T: reserve the **scalars** (`Int`, `Float`, `Bool`, `Str`, `Char`, `I8`..`U64`, `F32`, `F64`) plus `Self`. No real program names a type `Int`, and Zig and C reserve these too, so no user loses anything. Everything else follows S. Sys's desugar rule (T-b) is the same idea as PLT's S-c hygiene rule, and I support it in both forms.
>
> **Cross-cutting points:**
> - **X1:** yes, non-negotiable. This is the actual bug.
> - **X2:** yes.
> - **X3:** `Duration` and `Instant` are plain `std.time` names and leave the compiler's list, as Sys and Min say. A user `type Duration` in a file that does not import `std.time` is a normal type with no diagnostic. A file that declares it and also imports it gets the existing duplicate-name error.
> - **X4:** do not reserve `Fn`/`Tuple`. The spec has no surface syntax that spells them, so reserving them documents a parser leak. If the panel reserves them anyway, the cost to users is near zero. I would not block a vote on this point.
> - **X5:** `Template`, `FfiScope` and `Raw` must either get a spec entry or leave the user namespace (Min). If they get a spec entry, they are shadowable like the rest.
> - **X6:** the same rule applies to `type`, type alias, `trait` and `effect`. Different rules per declaration kind would be a fresh source of Stack Overflow questions.
> - **Also adopt:** DevOps A1 ("if the compiler accepts a declaration, the module can name it"), and PLT S-d (when two same-name types meet, the diagnostic qualifies each by origin).
>
> **My ranking:**
> 1. S (PLT form) + hygiene + A1 + S-d
> 2. S with scalars also reserved
> 3. T only if `Handler`, `Handle` and `Channel` move to the shadowable tier
> 4. R last
>
> SIGNAL: want another round

- **PLT:**

> # PLT — Phase B round 1
>
> **X1 goes into the spec whatever option wins.** A type name resolves once, to one declaration identity, and an unresolved name is an error. It never becomes a type variable. All six of us agree, so put it in §3.4 as a normative rule and not only as a bug fix.
>
> **The main cost claim for R is wrong.** Sys and Min argue that shadowing forces every codegen site that matches on the text `"Handle"` or `"List"` to become scope-aware. Under X1 it does not: codegen gets a type identity, not a string. A site that keys on the bare name is already unsound today, with no shadowing of builtins involved. Two modules that each declare `type Config` hit the same class of bug. Reserving names hides that defect for 35 strings and leaves it open for every other name. Also, the codegen rewrite already works from type identities, so this cost is paid.
>
> **R is not closed, and it is not one rule.**
> - The table grows with the language. `Duration` shows it already drifts: it was a name the compiler owned, although the stdlib declares it in source. Under R, every new compiler-known name breaks programs that already use it (X7). Under S, adding a name is not a breaking change.
> - AI/ML's R-b carve-out ("the stdlib module that declares the name *is* the builtin") is a second rule. It is not simpler than scoping.
> - Min says Blink has no path back to a shadowed builtin. It has one: `import blink.core.{Handle as TaskHandle}` uses the aliased-import syntax that §10.6 already has. Nothing new is needed.
>
> **Sys is right on one point, so I refine S toward T.** Some builtins are the types of *literal syntax* that appears in every module: `1`, `1.0`, `"s"`, `'c'`, `true`, `()`. Under the hygiene rule, `let x: Int = 1` in a module that shadows `Int` would be a type error, even though the program means the obvious thing. That is a trap and gives no power, so these names get the same treatment as keywords.
>
> **My refined position, "S/T":**
> 1. **Reserved (E0524, in the spec):** `Self`, and the scalar types of literals: `Int`, `I8`..`I64`, `U8`..`U64`, `Float`, `F32`, `F64`, `Str`, `Char`, `Bool`, `Void`. The rule for the list is "a type that literal syntax produces", not "a name the compiler happens to own", so the list only grows when the literal syntax grows.
> 2. **Every other compiler-known name** (`List`, `Option`, `Result`, `Ordering`, `Handler`, `Handle`, `Channel`, `Bytes`, `Ptr`, `Template`, `Range`, ...): the user declaration wins in its module, W1010 fires once at the declaration, and the builtin stays reachable through a `blink.core` / `blink.ffi` aliased import.
> 3. **Hygiene (Sys T-b = my S-c):** desugarings and compiler-inserted types always name the builtin by identity. T and S share this point, and it must pass under either one.
> 4. **Diagnostics qualify by origin** when two types with the same name meet (S-d).
>
> **On the cross-cutting points:**
> - **X2:** agree.
> - **X3:** I move to the Sys/Web/Min view. `Duration` and `Instant` leave the compiler-known set and are plain `std.time` names under normal import rules. This drops what I wrote in Phase A.
> - **X4:** `Fn` and `Tuple` are not surface names, so reserving them writes an implementation tag into the spec. I prefer to fix the parser. I will not block on this, because reserving two names that users cannot write in type syntax costs little.
> - **X5:** `Template`, `FfiScope` and `Raw` must be in the table (Min is right). They fall in class 2 unless they are literal types.
> - **X6:** all declaration forms that put a name in the type namespace: `type`, alias, `trait`, `effect`. One namespace needs one rule. W1010 for traits already works this way.
> - **Web W1** (no warning on non-prelude names): I prefer the warning. A reader who sees `Handler` next to `handler DB { }` needs the signal. This is a small difference.
>
> **Vote order:** S/T refined above, then T (Sys), then S, then W. R is last: it is not closed, and it treats a codegen defect as a naming policy.

- **DevOps:**

> # DevOps, Phase B round 1
>
> **I still hold S, and I take on changes from PLT, Sys and Min.**
>
> ## 1. X1 is the real fix, and it removes the main case for R
>
> Min and Sys say shadowing makes "every codegen site that matches on the text `Handle`" scope-aware. That is backwards. Those sites are the pp04ey bug. Under X1, name resolution binds each name once to a declaration identity, and typecheck, mono, layout and cname see that identity, never the string. After that, the scope check lives in one place: nameres.
>
> R does not remove bare-name keying. It hides the keying for the names on the list, and it stays latent for every name not on the list, such as a stdlib name added next year. X1 is required under every option, so R buys no safety that S lacks.
>
> ## 2. X7 decides it for tooling
>
> A reserved list that grows makes each release a possible breaking change, and the break appears in user code that did nothing wrong. Go, Rust, TypeScript and Kotlin all refuse that cost for ordinary type names. AI/ML says a closed list is easy for models to learn. But R's list holds `Raw`, `FfiScope` and `Template`, which no user can predict, and it changes between releases. A model cannot learn that list from the spec either.
>
> W1010 at the declaration, with a rename fix-it, is the same one-step repair as E0524. The difference is that it does not break the build when the language grows.
>
> ## 3. Refinements I now accept
>
> - **S-a: reserve `Self` only (PLT, Web).** `Fn` and `Tuple` are not surface syntax. Reserving them writes a parser shortcut into the spec forever. The compiler must tag these with spellings no user can write. I withdraw them from my A2.
> - **S-c: hygiene (PLT) is the same rule as the Sys desugar rule (T-b).** `T?`, `?`, `for`, `..`, `with`, `async.spawn` and `==` refer to the builtin by identity. This is required. Without it, shadowing `Option` changes what `x?` means, and that is the only real hazard Sys found in Tier P.
> - **S-d: qualify by origin (PLT).** I own this as the diagnostic contract: when two same-name types meet, the message prints `Handle (main)` against `Handle[Int] (blink.core)`. The LSP's hover uses the same text.
> - **X3: `Duration` and `Instant` leave the compiler-known set (Sys, Web, Min).** They become plain `std.time` names. With no import there is no diagnostic. With both an import and a local declaration, the existing duplicate-name error applies. This changes my Phase A position.
> - **X5 (Min):** every name the compiler owns is listed in the §10.6 table, or it leaves the user namespace. `Template`, `FfiScope` and `Raw` get a row or they go.
> - **X6:** one rule for `type`, type alias, `trait` and `effect`. Four rules for four kinds of declaration give four sets of diagnostics.
>
> ## 4. Against W's silent tier
>
> Web wants no warning for non-prelude names. But the module that shadows `Handle` and calls `async.spawn` now holds two `Handle`s. The first sign of that is a mismatch error far from the cause. One W1010 at the declaration costs one line and prevents that. Web's own `help:` hint for the `as` import belongs in W1010 at the declaration, not only in the later mismatch.
>
> ## 5. Against T's large reserved tier
>
> Sys reserves `Handle`, `Channel`, `Bytes` and `Ptr` because of the codegen keying. X1 plus hygiene removes that reason. What is left is the name tax that Web describes: `Handler` and `Channel` are core names in real code.
>
> ## My position
>
> **S = X1 + X2 + hygiene + origin-qualified diagnostics + W1010 on every compiler-known type name + `Self` reserved + escape through an `import blink.core.{X as Y}` alias.**
>
> The gate tests:
> - the pp04ey MVCE gives a Blink type error;
> - `type Handle` plus `async.spawn` in one module gives W1010 and a correct `Handle[Int]`;
> - `type Option` plus `x?` still uses the builtin;
> - `type Self` gives E0524.
>
> If the vote goes to R, I ask that R keep X1 and hygiene anyway.
>
> SIGNAL: stable, ready to vote

- **AI/ML:**

> **AI/ML, Phase B round 1**
>
> **I still support R, and I adopt Min's and Sys's answer to X3.** I withdraw R-b ("the stdlib declaration is the builtin"). That carve-out is one more rule a model must learn. `Duration` and `Instant` should become ordinary `std.time` names that resolve through imports. The reserved table then holds only names the language itself owns. A model can learn that table from §10.6, and it will rarely grow.
>
> **X7 (a reserved list grows, so each release can break code).** This is the best argument against R, and my refinement above answers most of it. New library types go into std modules, as ordinary names that follow import rules. Only new *language* types enter the table: syntax types, runtime handles, types that desugarings produce. Such types are rare, and the release notes can list them. PLT and DevOps want every release to stay compatible, and S achieves that by letting a name mean different things in different modules. For a model, a name that means one thing everywhere is worth more than being able to add names without breaking code.
>
> **Against S and W (web, PLT, devops).** Web says `Handler` is the most common type name in HTTP code. I agree, and that is why shadowing it is dangerous. The files that declare `type Handler` for HTTP are also the files whose tests write `Handler[DB]` mock effect handlers (§4 examples). Under S or W, a model writes the spec pattern `fn mock_db() -> Handler[DB]` in that module. The name now means the user's `Handler`, so the error says "type `Handler` takes 0 type arguments". Neither the model nor a human reader can work out the fix without knowing the shadowing rule plus the `blink.core ... as` escape. Under R the rename happens once, at the declaration, and the hint is clear. W is worst: it gives no diagnostic, so nothing tells the reader or the model that `Handler` has changed meaning.
>
> **Against T (sys).** T is a better design than S, but a model must learn two tiers plus the rule that desugarings always target the builtin. Sys admits that tier P's only real hazard is the desugaring, and the desugar rule removes it. So what does shadowing `Option` get us? No user needs a type named `Option`. If the panel picks T, I can accept it as my second choice.
>
> **Cross-cutting points**
> - **X1:** agreed, and non-negotiable. No name may fall back to a type variable.
> - **X2:** agreed.
> - **Hygiene (S-c / T-b):** write it into the spec whatever we pick. Under R it is almost never triggered, but it is the correct rule.
> - **X4, `Fn`/`Tuple`:** I agree with PLT and Web that the parser leak is a bug in the compiler. Under R, whether these names are in the table matters little, since no one names a type `Tuple`. I prefer to fix the leak and keep only `Self` from that group, so the table holds only real type names.
> - **X5:** agreed with Min. `Template`, `FfiScope` and `Raw` must either be specified in the table or leave the user namespace. A name the spec doesn't list must never be silently reserved.
> - **X6:** the table applies to every declaration that introduces a type-level name: `type`, type alias, `trait` and `effect`. One rule for every declaration kind means one fewer choice for a model to make. W1010 stays for prelude *trait* names only as long as the table does not include them.
>
> **My ranking:** R (with the X3 change) > T > S > W.

- **Minimalism:**

> ## Min, Phase B round 1
>
> **Ranking: R > T > S > W.** I refine R below and take up the two strongest points against it: X7 monotonicity (PLT, DevOps) and "`Handler` is a common domain name" (Web).
>
> **1. Count the mechanisms each option adds.** In the list below, **H** is hygiene: compiler-inserted types refer to the builtin by identity. S and W add:
> - H
> - an escape path through `blink.core` aliasing, which is a new job for imports that are inert today
> - origin-qualified diagnostics ("`Handle` (main) vs `Handle[Int]` (blink.core)")
> - W1010 for types
> - scope-aware resolution at every codegen site that keys on a bare name
>
> T adds H plus W1010 for six names. R adds none of these; it widens one existing check (E0524) at the declaration. H exists only because shadowing exists. Under R nothing can capture a builtin name, so H is not needed. PLT's P1 is the correct design *if* we want shadowing. My point is that every one of its parts pays for shadowing and for nothing else.
>
> **2. X7 monotonicity is real, but it argues for shrinking the set, not for shadowing.** The reserved set only grows if we keep making library types compiler-known. I add a rule to R: **new library types go in std modules and resolve through import, like `Duration`/`Instant` (X3). They never join the reserved table.** The reserved table then holds only language-owned names: scalars, `Handler`, `Handle`, `Range`, `Ptr`, `Self`, and the like. A new language-owned name is as rare, and as breaking, as a new keyword. Blink already accepts that cost for keywords and for effect-handle names (the 5-0 decision). Rust, Zig and C accept it too.
>
> **3. Web's `type Handler`.** I accept the ergonomic cost. But under S or W, a web module that declares `Handler` and then writes `fn mock_db() -> Handler[DB]` gets a confusing error far from the cause. AI/ML makes the same point. Renaming to `RouteHandler` is one edit, and the compiler asks for it at the declaration.
>
> **4. I shift on X4: `Fn` and `Tuple` are not reserved.** PLT and Web are right. The surface syntax is `fn(A) -> B` and `(A, B)`, so the names come from the parser leaking its internal tags. The fix is to remove the leak, not to reserve the names. That leaves the reserved table with one fewer class. `Self` stays reserved.
>
> **Cross-cutting points:**
> - **X1:** Agree, and it is non-negotiable for every option: an unresolved type name is an error, never a type variable.
> - **X2:** Agree.
> - **X3:** `Duration` and `Instant` become plain `std.time` names. I oppose AI/ML's carve-out ("the stdlib decl *is* the builtin"). A special case for which module may declare a reserved name is exactly the kind of rule that grows. `Ordering` is the one hard case: it is in the prelude, yet `lib/std/traits.bl` declares it. Specify it as the prelude's definition site, not as a user declaration.
> - **X5:** A name that the spec shows users writing (`Template[C]`, `Ptr[T]`) goes in the table. `FfiScope` and `Raw` go in the table only if users can write them. Otherwise the compiler must tag them with spellings users cannot write, like `Fn`/`Tuple`.
> - **X6:** The rule covers every declaration that puts a name in type position: `type`, type alias, `effect` (because of `Handler[E]`), and `trait`. The sealed traits already error, so `trait` adds little. W1010 stays for value names.
>
> **On T (Sys):** It is my second choice. Its reserved tier is almost the same as R. It differs only on `List`/`Map`/`Set`/`Option`/`Result`/`Ordering`, where shadowing gives no expressive gain and still needs Sys's desugar rule. If the panel wants to keep the §10.6 W1010 text, T is the cheapest way to keep it.
>
> SIGNAL: stable, ready to vote

#### Phase C — Final vote

Ballot:

> # Phase C ballot — 4k7y77 (silent vote)
>
> Phase B round 1 closed: 4 of 6 panelists signalled "stable, ready to vote". Before voting, read every round-1 reply: scratchpad/phaseB_r1_{sys,web,plt,devops,aiml,min}.md. Do NOT read any phaseC_*.md file other than this ballot.
>
> The options below are the positions panelists hold after round 1, labelled mechanically. Option W (Web's Phase A W1) is dropped: its proposer moved to S, and no panelist holds it now.
>
> ## Q1 — Which type names may a user declaration take?
>
> - **R** — Reserve every compiler-known type name (E0524 at the declaration). As refined in round 1 by Min/AI-ML: `Duration`/`Instant` leave the set (plain `std.time` names); `Fn`/`Tuple` are not reserved (parser leak fixed); `Self` reserved; no W1010 for types. (Min r1, AI/ML r1)
> - **T** — Reserve language-owned names (scalars, runtime handles `Bytes`/`StringBuilder`/`Ptr`/`Handle`/`Channel`/`FfiScope`/`Raw`, plus `Self`/`Template`/`Handler`/`Range`/`ConversionError`); prelude library types (`List`/`Map`/`Set`/`Option`/`Result`/`Ordering`) shadowable with W1010. (Sys Phase A; Sys r1 now ranks it second)
> - **S-lit** — Reserve `Self` + the types literal syntax produces (`Int`, `I8`..`I64`, `U8`..`U64`, `Float`, `F32`, `F64`, `Str`, `Char`, `Bool`, `Void`). Every other compiler-known name: user declaration wins in its module, W1010 once at the declaration, builtin reachable via `import blink.core.{X as Y}` / `blink.ffi` alias, diagnostics qualify same-name types by origin. (PLT r1 "S/T", Sys r1)
> - **S-self** — Same as S-lit, but only `Self` is reserved; scalars are shadowable with W1010 too. (DevOps r1, Web r1)
>
> ## Q2 — `Fn` / `Tuple`
>
> - **Q2-a** — Not reserved; the spec does not name them; the compiler must tag function/tuple annotations with spellings users cannot write.
> - **Q2-b** — Reserved (E0524).
>
> ## Q3 — Future compiler-known types
>
> - **Q3-a** — The set of names that are compiler-known and usable without import is frozen in the spec; a new builtin type goes in a named std module and resolves through import (as `Duration` does in `std.time`). (Sys r1, Min r1)
> - **Q3-b** — No such rule; new names may join the compiler-known set.
>
> ## Q4 — Bundle of cross-cutting points (vote "accept" or name the item(s) you reject)
>
> - X1: A type name resolves once, at name resolution, to one declaration identity. An unresolved type name is an error; only an explicit `[T]` binder creates a type variable. Normative text in §3.4.
> - Hygiene: desugarings and compiler-inserted types (`T?`, `?`, `??`, `for`, `..`, `==`/`<`, `with`, `async.spawn`, `Template[C]`) refer to the builtin by identity, never by the name in scope. (Under R this is still stated, as DevOps and AI/ML asked.)
> - X2: `Handler[E]` is compiler-known and usable without import, like `ConversionError` (§10.7); drop "Import when writing handler functions" from §10.6.
> - X3: `Duration` / `Instant` are plain `std.time` names, outside the compiler-known set.
> - X5: every compiler-known type name users can write (e.g. `Template`, `Ptr`, `Handle`, `Channel`, `Bytes`, `StringBuilder`, `Range`, `ConversionError`) is listed in one §10.6 table; names users cannot write (`FfiScope`, `Raw` if so) leave the user namespace.
> - X6: the rule covers every declaration that puts a name in the type namespace: `type`, type alias, `trait`, `effect`.
>
> ## Vote format (per question)
>
> 1. **Vote** — option label.
> 2. **Reasoning** — 2–4 sentences from your domain.
> 3. **Concern** — one sentence on what could go wrong with the winning option from your POV (if you expect to lose, name the risk you want the spec to guard).

Tally:

- **Q1:** S-lit 4-2 (Sys, Web, PLT, DevOps; AI/ML and Min voted R). Closer than 5-1, so Phase D ran.
- **Q2:** Q2-a 6-0.
- **Q3:** Q3-a 6-0.
- **Q4:** accept 6-0.

- **Systems:**

> ## Sys, Phase C vote
>
> ### Q1 (which type names a user declaration may take)
> 1. **Vote:** S-lit
> 2. **Reasoning:** Under X1, codegen sees a declaration identity (tid), never a name string. So shadowing costs nothing in lowering or at run time, and the scope logic lives only in nameres. The literal/scalar types are the one place where shadowing is sound but is still a trap: every `1`, `"s"` or `true` in that module would mismatch the user's type. These types also have fixed machine shapes, and Zig and C reserve them for the same reason. R reserves `Handler`/`Handle`/`Channel` in order to hide a codegen defect that X1 already fixes, and users pay a lasting name tax for it.
> 3. **Concern:** The option is safe only if X1 and hygiene land in the same change. If they do not, a shadowed `Handle` or `Option` meets bare-name codegen keying, and pp04ey comes back through a new path. The implementation ticket must gate on the four DevOps tests (pp04ey MVCE, `type Handle` + `async.spawn`, `type Option` + `x?`, `type Self`).
>
> ### Q2 (`Fn` / `Tuple`)
> 1. **Vote:** Q2-a
> 2. **Reasoning:** The surface syntax is `fn(A) -> B` and `(A, B)`. These names are parser tags, and a spec must not reserve an implementation's internal spelling. Tagging with spellings that users cannot write costs nothing in the generated code.
> 3. **Concern:** The parser fix must land before E0524 is narrowed. Otherwise `type Tuple` becomes legal while the parser still produces the tag `Tuple`, and that silently captures every tuple annotation.
>
> ### Q3 (future compiler-known types)
> 1. **Vote:** Q3-a
> 2. **Reasoning:** A frozen ambient set makes the reserved list and the W1010 list closed under every Q1 option. New builtins then go through normal import resolution, which is predictable. `Duration`/`Instant` in `std.time` already show that a runtime-backed type needs no ambient name.
> 3. **Concern:** A future type that desugaring must produce (as `Range` is for `..`) could not be an ordinary import. The spec should say that such a type joins the set only through a language change, like a new keyword.
>
> ### Q4 (bundle of cross-cutting points)
> 1. **Vote:** accept (X1, hygiene, X2, X3, X5, X6)
> 2. **Reasoning:** X1 and hygiene are the soundness fix whatever wins Q1. X2, X3 and X5 remove spec contradictions and names that the compiler reserves without a spec entry. X6 applies one rule to the whole type namespace.
> 3. **Concern:** Under X5, `FfiScope`/`Raw` may leave the user namespace. If they do, the compiler must tag them with spellings users cannot write, as with `Fn`/`Tuple`, or they leak again.

- **Web/Scripting:**

> **Web, Phase C vote**
>
> **Q1**
> 1. **Vote:** S-lit
> 2. **Reasoning:** PLT's round-1 point convinced me to move from S-self. If a module shadows `Int`, then `let x: Int = 1` fails, and a JS or Python developer would never work out why in 5 minutes. No real app names a type `Int` or `Str`, so reserving the literal types costs users nothing. Every name that matters in web code (`Handler`, `Handle`, `Channel`, `Request`) stays available with one warning, and the same rule is how TypeScript, Kotlin and Python behave.
> 3. **Concern:** In a module that declares `type Handler` and also uses `Handler[DB]` for an effect, the mismatch error must print both origins and the `import blink.core.{Handler as ...}` hint. Otherwise this case turns into a common Stack Overflow question.
>
> **Q2**
> 1. **Vote:** Q2-a
> 2. **Reasoning:** No user writes `Fn` or `Tuple` in type syntax, because the syntax is `fn(A) -> B` and `(A, B)`. Reserving them would put an implementation leak in the spec. A user who reads that list would reasonably ask what `Tuple` means in Blink, and the answer is nothing.
> 3. **Concern:** The compiler must change its internal tags before this lands, or `type Tuple` keeps failing in strange ways.
>
> **Q3**
> 1. **Vote:** Q3-a
> 2. **Reasoning:** The rule "new library types live in a named module and you import them" is the model Python developers already know (`from datetime import timedelta`). It also keeps the no-import namespace small enough to learn. Together with S-lit, it means no future release can break a user's type name.
> 3. **Concern:** The frozen set must be written as one table in §10.6, so that "which names need no import" has a single answer.
>
> **Q4**
> 1. **Vote:** Accept all (X1, hygiene, X2, X3, X5, X6).
> 2. **Reasoning:** X1 and hygiene fix the actual bug. X2 fixes a contradiction that sends users to an import that does not exist. X3, X5 and X6 each replace a special case with one rule a user can predict.
> 3. **Concern:** Under X5, the spec must list names like `Template` and `Ptr` or remove them from the user namespace. A name the spec does not list must never be silently reserved.

- **PLT:**

> # PLT — Phase C vote (4k7y77)
>
> ## Q1
> 1. **Vote:** S-lit
> 2. **Reasoning:** Once X1 holds, shadowing is ordinary lexical scoping over declaration identities. It is sound, it composes, and adding a name to the language breaks no program. The literal types are the one principled exception. Every literal in the module elaborates to them by identity, so a user `type Int` would make `let x: Int = 1` fail to typecheck. The reserved set follows one rule ("types that literal syntax produces, plus `Self`"), so it only grows when the literal syntax grows. R reserves by "what the compiler owns today", and that set has no fixed limit.
> 3. **Concern:** If hygiene is implemented partly, one desugaring that still looks up `Option` or `Handler` by name in scope brings back pp04ey through a user declaration. Each hygiene site needs a gate test that runs with the builtin name shadowed.
>
> ## Q2
> 1. **Vote:** Q2-a
> 2. **Reasoning:** `Fn` and `Tuple` are not names in the surface language. The spec's only syntax for these types is `fn(A) -> B` and `(A, B)`. Reserving them writes a parser detail into the spec forever, which is the kind of corner the spec must not paint itself into.
> 3. **Concern:** The compiler must actually stop using those spellings as internal tags before the spec drops E0524 for them. Otherwise `type Tuple[X]` mis-decodes tuple annotations again.
>
> ## Q3
> 1. **Vote:** Q3-a
> 2. **Reasoning:** Hygiene means a desugaring target never needs a name in the user's scope, because the compiler refers to it by identity. So a new builtin type can always live in a named std module. Freezing the ambient set keeps the §10.6 table closed and complete, and it makes the monotonicity property hold by construction under every Q1 option.
> 3. **Concern:** "Frozen" must mean the spec's table is the whole set. A compiler list such as `is_primitive_type` that holds a name the table leaves out is a spec violation, and the table must not be allowed to fall behind the compiler again.
>
> ## Q4
> 1. **Vote:** accept (all of X1, Hygiene, X2, X3, X5, X6)
> 2. **Reasoning:**
>    - X1 is the soundness fix itself. Every other item depends on it.
>    - Hygiene is what makes shadowing safe.
>    - X2, X3 and X5 make the spec's name table agree with itself and with §4.
>    - X6 gives one namespace one rule. Types, aliases, traits and effects share the type namespace, so different rules per declaration kind would let a name mean different things by the kind of its declaration.
> 3. **Concern:** X1 must be normative text in §3.4 with a named error for an unresolved type name. It must not live only as a compiler invariant, or a later fallback to a type variable will come back unnoticed.

- **DevOps:**

> # DevOps, Phase C vote
>
> ## Q1: S-lit
>
> **Vote:** S-lit.
>
> **Reasoning:** I move from S-self to S-lit. The literal-type point from Sys and PLT is a diagnostic problem, and that is my domain. In a module that declares `type Int`, every `1` fails with "expected `Int` (main), found `Int` (builtin)". The message is correct, but no one can act on it, and nothing gains from the shadow. The literal set grows only when the literal syntax grows, so reserving it does not reopen X7. Every other name stays shadowable with one W1010 at the declaration, so `Handler` and `Handle` cost web users nothing.
>
> **Concern:** Implementations may use the W1010 note and the origin-qualified mismatch text inconsistently. The spec should give one fixed format, `Name (module)`, and use it in both diagnostics and LSP hover.
>
> ## Q2: Q2-a
>
> **Vote:** Q2-a.
>
> **Reasoning:** Users cannot write `Fn` or `Tuple` as type syntax. A spec that reserves them makes a parser shortcut permanent, and someone has to explain that reservation in the docs. The compiler must tag these annotations with spellings users cannot write. Until the parser is fixed, E0524 on these names is only a guard inside the implementation, not a rule of the language.
>
> **Concern:** If the parser leak is not fixed, `type Tuple` keeps an E0524 that the spec does not mention. Open a ticket, and give that E0524's explain text a pointer to the ticket.
>
> ## Q3: Q3-a
>
> **Vote:** Q3-a.
>
> **Reasoning:** Freezing the ambient set makes every future builtin non-breaking under any Q1 option. New types then resolve through a normal import, so go-to-definition lands on a real source declaration. That is the best case for the LSP and for `blink doc`.
>
> **Concern:** "Frozen" can drift when someone adds an ambient name for convenience. `task ci` should compare the compiler's owned-name list against the §10.6 table.
>
> ## Q4: accept
>
> **Vote:** accept (all items).
>
> **Reasoning:** X1 is the actual fix for pp04ey, and the hygiene rule keeps shadowing from changing what `?` and `async.spawn` mean. Without X1 and the hygiene rule, no option on the ballot is sound. X2, X3, X5 and X6 each remove a contradiction or an unlisted name. All four make diagnostics and hover text predictable.
>
> **Concern:** X1 needs a gate test that proves there is no type-variable fallback: the pp04ey MVCE must give a Blink type error, not a `cc` error.

- **AI/ML:**

> **AI/ML, Phase C vote**
>
> ## Q1 — Vote: R
>
> **Reasoning.** Under R, a compiler-known type name means one thing in every Blink file, so a model can learn that meaning from the spec and trust it without scanning each module for a local declaration that replaces it. S-lit adds work to every read: the model must check for a shadowing declaration, know the `blink.core ... as` escape, and read origin-qualified error messages. The common failure case is a module that declares `type Handler` and whose tests use `Handler[DB]` as the spec shows. Under S that gives an arity error far from its cause. Under R it is one rename at the declaration. With Q3-a frozen, R's list stops growing, and the X7 argument against R no longer applies.
>
> **Concern.** If S-lit wins, the W1010 text and every mismatch error between same-name types must name the `import blink.core.{X as Y}` fix explicitly. If they do not, models will loop on "type `Handler` takes 0 type arguments" errors that they cannot fix from the message alone.
>
> ## Q2 — Vote: Q2-a
>
> **Reasoning.** No user can write `Fn` or `Tuple` in type syntax, because the surface forms are `fn(A) -> B` and `(A, B)`. If the spec reserves them, the table gets two names that a model has no reason to learn, and a parser shortcut becomes part of the spec. A smaller table that holds only real type names is easier to learn.
>
> **Concern.** The compiler must actually stop leaking the tags. If an internal spelling ever becomes reachable again, users get errors that name a type the spec never mentions.
>
> ## Q3 — Vote: Q3-a
>
> **Reasoning.** A frozen ambient set gives models a fixed list to learn. New types then follow the one rule a model already knows: import them from a named std module. Q3-a also keeps whichever Q1 option wins from being a moving target between releases.
>
> **Concern.** The spec must list the frozen set completely in one §10.6 table. If the compiler knows a name the table leaves out, models learn the wrong set.
>
> ## Q4 — Vote: accept (all items)
>
> **Reasoning.** X1 is the actual soundness fix, and a hygiene rule has to be written down whatever Q1 picks. X2 and X3 each remove a contradiction or a special case a model would otherwise have to learn. X5 and X6 give one table and one rule that covers every declaration kind, which leaves a model fewer choices to make.
>
> **Concern.** X5 must be enforced, not just written: a gate test should check that the compiler's own list of type names is a subset of the §10.6 table, so the two cannot drift apart.

- **Minimalism:**

> ## Min: Phase C vote (4k7y77)
>
> ### Q1: Which type names may a user declaration take?
> 1. **Vote:** R
> 2. **Reasoning:** PLT and DevOps are right that X1 removes the codegen cost of shadowing. What stays is the surface that only shadowing needs:
>    - W1010 for types
>    - a new export job for `blink.core`/`blink.ffi` aliases
>    - origin-qualified diagnostics for two same-name types
>    - a reader who must check each module to learn what `Handler` means
>
>    Q3-a freezes the compiler-known set, and that removes the X7 growth argument against R as well. After that, S pays these ongoing costs only for the right to name a type `Option` or `Handler`, and a one-word rename is enough to avoid that.
> 3. **Concern:** If S wins, the spec must require the W1010 `help:` line to name the `import blink.core.{X as Y}` escape. Otherwise the first `Handler[DB]` in a shadowing module produces an arity error that points far from its cause.
>
> ### Q2: `Fn` / `Tuple`
> 1. **Vote:** Q2-a
> 2. **Reasoning:** Users cannot write these names in surface syntax, so reserving them puts a parser shortcut into the spec forever. Removing the leak is subtraction; reserving the names is addition.
> 3. **Concern:** The compiler's new internal tag spellings must be ones the lexer can never produce. Otherwise the leak comes back under another name.
>
> ### Q3: Future compiler-known types
> 1. **Vote:** Q3-a
> 2. **Reasoning:** A frozen compiler-known set keeps the reserved or shadowed table closed under every Q1 option. New library types then follow the ordinary import rules. This is the single rule that most limits language-surface growth.
> 3. **Concern:** The freeze must bind the implementation too. `is_primitive_type` must never hold a name that the §10.6 table does not list. The drift of `Duration` into that list is how this bug started.
>
> ### Q4: Cross-cutting bundle
> 1. **Vote:** Accept all of X1, Hygiene, X2, X3, X5 and X6.
> 2. **Reasoning:**
>    - X1 is the soundness fix itself.
>    - Under R, hygiene is a free rule, because no builtin name can be captured, but it is correct to state.
>    - X2 and X3 delete a spec contradiction and a compiler-owned name.
>    - X5 and X6 give one table and one rule for the type namespace.
> 3. **Concern:** X5's "names users cannot write leave the user namespace" needs a gate test. Without one, the list can drift from the table again unnoticed.

#### Phase D — Round 2 (Q1 only)

> # Phase D — focused round on Q1 only (4k7y77)
>
> Phase C tally:
> - Q1: S-lit 4 (Sys, Web, PLT, DevOps), R 2 (AI/ML, Min). No votes for T or S-self.
> - Q2: Q2-a 6-0. Q3: Q3-a 6-0. Q4: accept 6-0.
>
> Q2, Q3 and Q4 are decided. The procedure requires one focused round on Q1 because 4-2 is closer than 5-1.
>
> Q1 options are now R and S-lit only (definitions in phaseC_ballot.md). Q3-a (frozen set), Q2-a and the whole Q4 bundle are fixed and apply under either option.
>
> You may now read the Q1 section of every Phase C vote: phaseC_{sys,web,plt,devops,aiml,min}.md.
>
> Write ONE reply to scratchpad/phaseD_debate_<yourname>.md (yourname = sys/web/plt/devops/aiml/min), then send a one-line message to team-lead saying it is written. The reply:
> - responds to the strongest argument on the other side of Q1,
> - says whether your Q1 position holds or changes,
> - at most 250 words.
>
> This is the only Phase D debate round. A silent Q1 re-vote follows.

##### Debate

- **Systems:**

> ## Sys, Phase D (Q1)
>
> **The strongest R argument (Min, AI/ML):** Q3-a freezes the compiler-known set, so X7 no longer counts against R. After that, S-lit pays ongoing costs only for the right to name a type `Handler` or `Option`. Those costs are W1010 for types, `blink.core` alias exports, origin-qualified diagnostics, and a reader who must check each module.
>
> **I concede X7.** With Q3-a, R's list is closed. That was my main case against R in round 1.
>
> **What stays:**
> 1. **Most of the cost list is not specific to S.** Q4 already makes hygiene normative under both options. Origin-qualified diagnostics are needed anyway: two user modules that each declare `type Config` can meet in one error today. W1010 for traits already exists. What S adds is one declaration check plus alias exports from a module that §10.7 already defines. At the machine level both options are equal after X1: same tids, same C, no run-time cost.
> 2. **The frozen set is exactly the names users want.** `Handler`, `Handle`, `Channel` and `Bytes` sit in it permanently under R. A frozen reservation of common domain nouns is a permanent tax. Freezing makes the tax stable, but it does not make it small.
> 3. **The `Handler[DB]` arity trap is a diagnostic defect, and it has a precise fix.** When a shadowing type is used with the builtin's arity, the error must name the builtin and give the `import blink.core.{Handler as EffectHandler}` fix. I accept Min's and AI/ML's concern as a normative requirement on W1010 and on that error.
>
> **Position holds: S-lit.** The condition is that the spec requires the `help:` line described in point 3.

- **Web/Scripting:**

> **Web, Phase D (Q1)**
>
> **The strongest argument for R:** Q3-a freezes the compiler-known set, so X7 no longer applies, and what remains is S's ongoing cost for the right to name a type `Handler`.
>
> I accept the first half. With Q3-a, R's list stops growing, and my main Phase B argument against R loses most of its force.
>
> But the frozen set is not empty. It includes `Handler`, `Handle`, `Channel`, `Bytes`, `Range` and `Template`. That makes the tax permanent instead of growing. Under R, every HTTP developer who types `type Handler` gets a hard error on day one, and the error is about effects, a feature they have not met yet. A new language's first-hour experience matters more than almost anything else, and R makes the most common web type name its first error. S costs a one-line warning in the rare module that uses both meanings.
>
> **The `Handler[DB]` arity trap** (AI/ML, Min) is real, and it happens only in modules that use both meanings. Under S it is a diagnostic problem, and a diagnostic can fix it. Rather than lock the language, I would make the fix normative. When a user type that shadows a compiler-known name gets type arguments it does not take, the error must say: "`Handler` here is your type (main:1); the effect handler type is `blink.core.Handler`; `import blink.core.{Handler as EffectHandler}`". W1010 at the declaration carries the same `help:` line. With both, the model or human fixes it in one step, the same one step as R's rename.
>
> **Position holds: S-lit, with the escape hint required in both W1010 and the mismatch/arity error.**

- **PLT:**

> # PLT — Phase D (Q1)
>
> **The strongest argument for R** (Min, AI/ML): Q3-a freezes the compiler-known set, so X7 no longer counts against R. What remains is that S pays ongoing costs only so users can name a type `Handler`. I concede the X7 part. With a frozen set, R stops being a source of future breaking changes.
>
> **The cost claim does not hold at the margin.** Q4 passed 6-0, so X1 and hygiene are required under R as well. What S adds on top:
> - *Origin-qualified diagnostics.* R needs these too. Two user modules that each declare `type Config`, and each meet the other in an error message, need the same qualification. The need comes from nominal typing, not from shadowing builtins.
> - *The `blink.core` alias.* It uses the aliased-import form that §10.6 already has, with no new syntax.
> - *W1010 for types.* §10.6 already specifies it, and the trait version already works. R *reverses* shipped spec text. It also needs its own special case for `Ordering`: the stdlib's declaration site is exempt from the reservation.
>
> So the real difference is one warning versus one error. R's frozen table still permanently removes `Handle`, `Channel`, `Bytes`, `Range` and `Template`, which are common domain names, in order to prevent a confusion that a diagnostic can fix.
>
> **The arity-error case is real, and the answer is to specify it, not to reserve the names.** I adopt Min's and AI/ML's concern as a requirement. The W1010 `help:` line, and every mismatch or arity error that involves a shadowed compiler-known name, must name the `import blink.core.{X as Y}` fix.
>
> **Position holds: S-lit, with that diagnostic requirement.**

- **DevOps:**

> # DevOps, Phase D (Q1)
>
> **The strongest case for R** comes from AI/ML and Min together. Q3-a freezes the set, so X7 no longer counts against R. After that, S-lit carries costs that never go away (W1010, the alias escape, origin-qualified messages) just to buy one right: naming a type `Handler`. On top of that, the `Handler[DB]` arity error lands far from its cause.
>
> **My answer.** Q3-a works on both sides. It stops R's list from growing, but it also fixes that list in place for good. About 20 real domain names stay banned in every Blink program forever: `Handler`, `Handle`, `Channel`, `Range`, `Template`, `Bytes`. Under S-lit, the only cost to a user who picks one of those names is a single warning.
>
> The far-from-cause error is a real problem, but it is a diagnostic problem, and a diagnostic rule fixes it. I propose this normative line for S-lit:
>
> > Any diagnostic that involves a name shadowing a compiler-known type adds a note pointing to the shadowing declaration, plus the `import blink.core.{X as Y}` fix.
>
> ```
> error[E0303]: type `Handler` takes 0 type arguments, found 1
>  --> app.bl:9:21
>   = note: `Handler` here is `type Handler` (app.bl:1), which shadows the built-in `Handler[E]`
>   = help: import blink.core.{Handler as EffectHandler}
> ```
>
> With that rule the error has one cause and one fix, and a model can act on it without knowing the shadowing rules. AI/ML and Min both raised this in their concern lines. I accept both concerns as spec requirements, not as reasons to switch.
>
> **Position holds: S-lit, with the note rule above added to it.**

- **AI/ML:**

> **AI/ML, Phase D (Q1)**
>
> **The strongest argument for S-lit** is Web's: TypeScript, Kotlin and Python let a local name win, so models trained on them will write `type Handler` in Blink too. Under R, that name fails.
>
> That is true, but a failure under R is loud, happens at the declaration, and the error says how to fix it: rename. A model repairs that in one step. S-lit swaps it for a quiet failure later. The declaration compiles with one warning, and models ignore warnings. Then the model writes `Handler[DB]`, the pattern §4 teaches. That goes wrong somewhere else in the module, and the fix only works if the model already knows a second rule: the `blink.core ... as` escape. "Other languages allow it" helps when the model writes a declaration. It does not help when the model has to work out which `Handler` a later use means.
>
> X1 made shadowing safe for codegen, and Q3-a removed the X7 growth argument against R. The only thing S-lit still offers is the right to spell `Handler` or `Handle` for your own type. What it costs is one more rule that every reader, human or model, needs in every module.
>
> **My position holds: R.**
>
> If S-lit wins, I ask the spec to require two things:
> 1. The W1010 `help:` line names the `import blink.core.{X as Y}` escape.
> 2. Any error that involves a shadowed compiler-known name (an arity error, or a mismatch) repeats the note "`Handler` here is the module's own type (line N); the builtin is `blink.core.Handler`". The model then gets the fix at the place where the error happens, not only at the declaration.

- **Minimalism:**

> ## Min, Phase D (Q1)
>
> **Strongest argument for S-lit (Sys, PLT):** with X1, codegen sees a declaration identity and never a name string, so shadowing adds no lowering logic. R then taxes `Handler`/`Handle`/`Channel` for good.
>
> I built my case for R by counting what only shadowing needs. I recount that after the decisions already taken on Q2, Q3 and Q4:
> - **Hygiene** is now required under both options (Q4).
> - **Escape path:** aliased import syntax already exists in §10.6, and §10.7 already defines `blink.core`. The only new work is that `blink.core` exports names it already owns.
> - **Origin-qualified diagnostics** are needed anyway. Two user modules that each declare `type Config` meet the same way.
> - **W1010 for prelude types** is already in the spec. S-lit implements a written rule, and R reverses it.
> - **Growth:** Q3-a closes the set under both options.
>
> What S-lit adds over R is therefore close to zero. R, by contrast, deletes a spec rule and reserves names users want. My subtraction lens no longer favors R. With the rest of the bundle fixed, S-lit is the smaller change to the spec.
>
> The cost that remains is the one AI/ML names: a `Handler[DB]` in a module that shadows `Handler` gives an error far from the cause. That is a diagnostics duty, not a reason to reserve the name.
>
> **Position changes: R → S-lit.** I attach one condition: the W1010 `help:`, and every mismatch between two types of the same name, must name the `import blink.core.{X as Y}` fix explicitly.

##### Re-vote — Q1: S-lit 6-0 (AI/ML and Min moved R → S-lit)

- **Systems:**

> ## Sys, Phase D Q1 re-vote
>
> 1. **Vote:** S-lit
> 2. **Reasoning:** Under X1, both options lower to the same tids and the same C, with no run-time cost. The only difference is at the front end: one warning (S-lit) versus one error (R). Q4 already requires hygiene and origin-qualified diagnostics under both options, and §10.6 already specifies W1010, so S-lit is the smaller spec change. R would permanently reserve `Handler`, `Handle`, `Channel`, `Bytes`, `Range` and `Template` to prevent a confusion that a diagnostic can fix.
> 3. **Concern:** If X1 is implemented partly, with some codegen or intrinsic site still keyed on the bare name, a shadowing user type reaches that site and the pp04ey bug class returns silently. So the implementation must gate on the pp04ey MVCE, `type Handle` + `async.spawn`, `type Option` + `x?`, and `type Self`.
> 4. **Conditions:**
>    - "W1010 at a type declaration that shadows a compiler-known name carries a `help:` line that names `import blink.core.{X as Y}` (or `blink.ffi` for FFI names)."
>    - "Any diagnostic that involves a name that shadows a compiler-known type (for example type mismatch or type-argument arity) adds a note that gives the shadowing declaration's location and names the builtin's origin, plus the same `help:` line."
>    - "No codegen stage may select behavior by a type's name string; the stage selects it by declaration identity only."

- **Web/Scripting:**

> **Web, Phase D Q1 vote**
>
> 1. **Vote:** S-lit
> 2. **Reasoning:** Under Q3-a, R's reserved list stops growing, but that also freezes `Handler`, `Handle`, `Channel`, `Bytes` and `Range` into it for good. Those are the type names web developers and models write first. S-lit keeps them usable with one warning, and it keeps the literal-type names (`Int`, `Str`, ...) reserved, which is the one place shadowing was a real trap. Once the diagnostic rule below is in place, the `Handler[DB]` arity case that worries AI/ML takes one step to fix, the same as a rename under R.
> 3. **Concern:** If the escape hint is optional or implemented late, the first `Handler[DB]` in a module that shadows `Handler` gives an arity error that no one can act on. It then becomes the most-asked question about Blink.
> 4. **Conditions:** "The W1010 `help:` line, and every error (arity, mismatch, or other) that involves a name shadowing a compiler-known type, MUST add a note naming the shadowing declaration's location and the builtin's origin, plus the fix `import blink.core.{X as Y}` (or `blink.ffi` where applicable)." Example:
>    ```
>    error[E0303]: type `Handler` takes 0 type arguments, found 1
>      = note: `Handler` here is `type Handler` (app.bl:1), which shadows the built-in `Handler[E]` (blink.core)
>      = help: import blink.core.{Handler as EffectHandler}
>    ```
>    A gate test must cover this exact case.

- **PLT:**

> # PLT — Phase D Q1 vote (4k7y77)
>
> 1. **Vote:** S-lit
>
> 2. **Reasoning:** Once X1 and hygiene hold, which Q4 makes normative under both options, a shadowing declaration is ordinary lexical scoping over declaration identities. It is sound, and it composes. Q3-a closes the set under both options, so the only real difference between R and S-lit is a warning versus an error on names like `Handler`, `Handle` and `Channel`. R costs more: it reverses the W1010 rule already in §10.6, and it needs a special case that exempts the stdlib's own `Ordering` declaration. Reserving `Self` and the literal types stays principled, because literal syntax binds to them in every module.
>
> 3. **Concern:** If hygiene or the diagnostic rules below are implemented only partly, a shadowed name reaches a desugaring or an error message with no pointer back to its declaration. That brings back the pp04ey confusion in a new form.
>
> 4. **Conditions:**
>    - "A type name resolves once, at name resolution, to one declaration identity; an unresolved type name is an error, and only an explicit `[T]` binder creates a type variable." (§3.4, normative)
>    - "When a declaration shadows a compiler-known type name, the W1010 `help:` line names the `import blink.core.{X as Y}` (or `blink.ffi`) escape."
>    - "Every diagnostic that involves a name shadowing a compiler-known type, including arity and mismatch errors, notes the shadowing declaration's location and names the same escape."
>    - "Each hygiene site (`T?`, `?`, `??`, `for`, `..`, `==`/`<`, `with`, `async.spawn`, `Template[C]`) has a conformance test that runs with the builtin name shadowed."

- **DevOps:**

> # DevOps, Phase D Q1 vote
>
> 1. **Vote:** S-lit.
>
> 2. **Reasoning:**
>    - Q3-a freezes the set, so X7 no longer tells R and S-lit apart. What is left is R's permanent ban on common domain nouns, weighed against a warning at the declaration plus a clear note wherever the shadowed name causes an error.
>    - AI/ML is right that the failure is quiet and lands far from its cause. That is a diagnostic defect, and my domain can fix it: the same fix appears at the declaration and at every error site.
>    - Once the fix is normative, the repair is one step, the same as R's rename.
>
> 3. **Concern:** Models and CI configs ignore warnings. If the note rule in item 4 is not tested, the quiet failure AI/ML describes becomes the normal case. Each note needs a golden-output test.
>
> 4. **Conditions:**
>    - (a) "W1010 on a type declaration carries a `help:` line naming `import blink.core.{X as Y}` (or `blink.ffi`) as the way to reach the built-in type."
>    - (b) "Any diagnostic whose subject is a name that shadows a compiler-known type adds a `note:` giving the shadowing declaration's location and the built-in's origin, and repeats the help line from (a). This covers arity (E0303) and type mismatch (E0308) errors."
>    - (c) "When two distinct types with the same name appear in one diagnostic, each is printed as `Name (module)`. The LSP hover uses the same form."

- **AI/ML:**

> **AI/ML, Phase D Q1 re-vote**
>
> 1. **Vote:** S-lit.
>
> 2. **Reasoning:** I held R because of one failure case. In a module that declares `type Handler`, a later `Handler[DB]` gave an error far from its cause, and the fix needed a second rule the model had to know already. All four S-lit panelists now accept, as a normative requirement, that this error carries the note and the `import blink.core.{X as Y}` fix at the use site. With that, a model can repair the error in one step from the message alone, which is the same cost as R's rename. Min and PLT also showed that R reverses shipped W1010 text and needs its own `Ordering` exception, and a model would have to learn that exception too. With the arity trap handled, R's advantage in learnability is too small to justify banning `Handler`/`Handle`/`Channel` for good.
>
> 3. **Concern:** Models often ignore warnings, so a shadowing module could compile clean and still confuse a model reading its own code. The use-site note, not W1010, is what protects that case, so the note must not be optional.
>
> 4. **Conditions:**
>    - "Any diagnostic that involves a name that shadows a compiler-known type (mismatch, arity, missing method, or other) must include a note naming the shadowing declaration with its location, and a `help:` line giving `import blink.core.{X as Y}` (or `blink.ffi`) as the way to reach the builtin."
>    - "W1010 at the declaration carries the same `help:` line."
>    - "Each of these diagnostic rules has a gate test with a shadowed `Handler` used as `Handler[DB]`."

- **Minimalism:**

> ## Min: Phase D Q1 vote (4k7y77)
>
> 1. **Vote:** S-lit
>
> 2. **Reasoning:**
>    - Q4 is decided, and that removes most of the cost I counted against S-lit. Hygiene and origin-qualified diagnostics are needed under both options.
>    - The alias escape uses syntax that already exists.
>    - W1010 for types is already in §10.6, so S-lit implements a rule the spec already has. R reverses that rule and needs its own exemption for `Ordering`.
>    - The marginal choice is one warning (S-lit) or a permanent ban on common names (R). S-lit is the smaller change to the spec.
>
> 3. **Concern:** Hygiene may be only partly implemented. If one desugaring still looks a builtin up by name in scope, pp04ey comes back through a user declaration, so each hygiene site needs a gate test that runs with the builtin name shadowed.
>
> 4. **Conditions:**
>    - "The W1010 `help:` line names the `import blink.core.{X as Y}` fix."
>    - "Every diagnostic that involves a user type shadowing a compiler-known name (mismatch, arity, or other) adds a note that points to the shadowing declaration and names the same fix."
>    - "The reserved set is exactly `Self` plus the types that literal syntax produces; it grows only when literal syntax grows."

### Final Spec

```blink
// warning[W1010]: shadows compiler-known type Handler
type Handler {
    n: Int
}

fn use_it(h: Handler) -> Int { h.n }

fn main() {
    io.println("{use_it(5)}")    // error[TypeError]: expected `Handler (main)`, found `Int`
}
```

```blink
import blink.core.{Handler as EffectHandler}

type Handler {
    n: Int
}

fn with_db(h: EffectHandler[DB]) -> Int { 1 }
```

- Reserved (E0524 ReservedTypeName): `Self`, `Int`, `I8`..`I64`, `U8`..`U64`, `Float`, `F32`, `F64`, `Str`, `Char`, `Bool`, `Void`. The set grows only when literal syntax grows.
- Every other compiler-known name: the user declaration wins in its module, with W1010 at the declaration. Its `help:` line names `import blink.core.{X as Y}` (or `blink.ffi`).
- Every diagnostic that involves a shadowing name adds a note with the declaration location and the builtin's home. Two same-name types print as `Name (module)`, also in LSP hover.
- A type name resolves once, to one declaration identity. An unresolved name is E0507 UnknownType. Only a `[T]` binder makes a type variable.
- Desugarings and compiler-inserted types (`T?`, `?`, `??`, `for`, `..`, `==`/`<`, `with`, `async.spawn`, `Template[C]`, literals) use the builtin by identity. No codegen stage selects behavior by a name string.
- `Fn` and `Tuple` are not names; `type Fn` is legal. The compiler must tag annotations with spellings users cannot write, and that fix lands before E0524 is narrowed.
- The compiler-known set is one closed §10.6 table. New builtins go in named std modules. `Handler[E]` needs no import; `Duration`/`Instant` are plain `std.time` names.
- The rule covers `type`, type alias, `trait` and `effect` declarations. Sealed method-surface traits stay not redefinable (§3.2.2).
- Spec: §3.4 *Type Name Resolution (normative)*; §10.6 *Compiler-Known Type Names (closed set)* and *Shadowing Rules*; §9.1.1 and §10.7 alias note.
