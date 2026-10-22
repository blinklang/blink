[< All Decisions](../DECISIONS.md)

# Defaults on Generic Parameters — Design Rationale

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated
in independent-proposal → debate → vote rounds.

**The question.** Spec §2.13 and §2.21 say a keyword default is a const expression. They did not say what type the default is checked against when the parameter type names a type parameter, as in `fn h[T](*, x: T = 3) -> T { x }`. Before the change that checks each default at its declaration, `h()` printed `3`: the default was inferred at each call, so `T` came from it. The compiler now checks the default once against the declared parameter type. The panel decided whether that is the rule.

#### Phase A — Independent proposals

**Systems:**

> ## Repo evidence (probe, gen1 with the old `--` marker)
>
> `fn k[T](-- xs: List[T] = []) -> Int { xs.len() }` called as `k[Int]()` lowers to
> `blink_k_0Int(blink_list_new_atomic())`. Two facts follow:
>
> 1. The caller fills the default after mono, at the instance type. No shared static, no boxing, no dispatch.
> 2. `[]` is a heap allocation at each call that omits the argument. It is not a compile-time value. §2.21 excludes `Map.new()` because "these allocate", so `[]` in a default is an unlisted exception today.
>
> ## sys-1 — check once with `T` rigid; the default never informs `T` (recommended)
>
> Rule for §2.13: the compiler checks a default once, at its declaration, against the declared parameter type with each type parameter held abstract. The default must have that type for every instance. An omitted argument adds no constraint to inference. Arguments, the expected type, or an explicit `[...]` must fix `T`. If none does, the call is E0301 at the call (§3.4), and the fix is `g[Int]()`.
>
> ```blink
> fn g[T](*, x: Option[T] = None) -> Option[T] { x }
> fn k[T](*, xs: List[T] = []) -> Int { xs.len() }
> fn h2[T](a: T, *, b: Option[T] = None) -> T { b.unwrap_or(a) }
>
> fn main() {
>     let a: Option[Int] = g()     // T = Int from the expected type
>     io.println("{k[Str]()}")     // T = Str from the explicit list
>     io.println("{h2(1)}")        // T = Int from `a`; `b` fills as None of Option[Int]
> }
> ```
>
> Per shape:
> - Bare `T`: no const value has type "every T". Every default is an error. Give it its own message, not "expects T, got Int": `error: a default on a parameter of type `T` must fit every `T`, and no constant does`, with two fixes: remove the default, or use `Option[T] = None`.
> - `Option[T]`: only `None`.
> - `List[T]`: only `[]` (see below).
> - `Box[T]`: a struct literal whose `T` fields take `None` or `[]`.
> - A fn type: none. §2.21 has no const fn values.
>
> Why this is the systems answer. The old behavior (`h()` printed 3) took `T` from the default. That is a type default, which §3 *No erasure* forbids ("never defaulted"). Checking per instance, as C++ does, moves type errors to instantiation time. Then a library compiles, and its user gets the error inside someone else's signature. Checking once keeps every instance's default well typed, and mono stays a pure substitution. Runtime cost is zero: each instance lowers the same literal at its own layout (`Option[Int]` and `Option[Str]` differ, and the caller has the concrete one).
>
> ## On `[]` — admit it, but only in defaults, and say what it costs
>
> Add one row to §2.21: "Empty list literal `[]`: allowed only as a keyword default or a struct field default. Each fill builds a new empty list." Do not admit it in `const` declarations. A `const` names one value, and a shared heap list would alias every mutation (the Python mutable-default trap). A default runs at each fill, so a new list each time is correct.
>
> The alternative, `Option[List[T]] = None`, costs a tag and a branch in every body that reads the list. One small allocation at the call is cheaper. Non-empty list literals stay out: they allocate and copy elements on each call, and the reader does not see that cost.
>
> ## sys-2 — forbid any default on a parameter whose type names a type parameter
>
> This is the zero-surprise fallback. It loses `Option[T] = None`, which works today and has a real use. I oppose it unless the panel rejects `[]`.
>
> ## Cross-language
>
> C++ default arguments are checked per instantiation, which gives late errors. Swift and Kotlin check against the generic type, as sys-1 does. Python evaluates once and shares the object (the trap that sys-1's "new per fill" avoids). Rust has no defaults.

**Web/Scripting:**

> ## web-1: a default must fit the declared type for every `T` (codify the conservative reading)
>
> Rule for §2.13: a keyword default is checked once, at its declaration, against the declared parameter type with each type parameter held abstract. It is accepted only if it has that type for every choice of `T`. An omitted argument adds nothing to inference: `T` comes from the written arguments, the expected type, or explicit `[...]`, as if the parameter were not there.
>
> ```blink
> fn h[T](*, x: T = 3) -> T { x }                 // error: default `3` is Int, `x` is any T
> fn g[T](*, x: Option[T] = None) -> Option[T] { x }   // ok: None fits Option[T] for every T
> fn k[T](*, xs: List[T] = []) -> Int { xs.len() }     // ok: [] fits List[T] for every T
> fn h2[T](a: T, *, b: Option[T] = None) -> T { b.unwrap_or(a) }
>
> fn main() {
>     io.println("{h2(1)}")          // T = Int from `a`; b = None
>     io.println("{k(xs: [1, 2])}")  // T = Int from xs
>     let n: Option[Int] = g()       // T = Int from the expected type
>     g()                            // error[CannotInferType]: T is under-determined (§3.4)
> }
> ```
>
> Per shape:
> - bare `T`: no const value fits every `T`, so no default. (A `T: Default` bound does not help: a trait call is not const.)
> - `Option[T]`: `None` only. `List[T]`: `[]` only.
> - struct `Box[T]`: a struct literal whose `T`-typed fields are themselves `None`/`[]`, e.g. `Box { item: None }` for `item: Option[T]`.
> - fn type: no fn value is a const expression, so no default. Same as a non-generic fn param today.
>
> Why this is the 90% answer. The JS/Python mental model is "the default is a value I can read off the signature". `x: T = 3` breaks that: the signature says "any T" and the default says "Int". The old behaviour (default picks `T` at each call) makes `h()` return Int and `h(x: "a")` return Str from one signature. That is two functions hiding in one, and the first Stack Overflow question writes itself: "why does `let s: Str = h()` fail?". No erasure and parametricity agree: the body must not see a concrete `T`, and a default that picks `T` is a hidden instantiation.
>
> Diagnostic (one error, at the default):
> ```
> error[TypeError]: default `3` has type Int, but `x` has type T, which the caller picks
>   help: make `x` required, or write `x: Option[T] = None` and unwrap in the body
>   help: if `x` is always Int, write `x: Int = 3`
> ```
> "expects T, got Int" with "argument 1 of `h`" (today's text) names a call that does not exist. That wording must change.
>
> ## web-2: `[]` is a const expression (change §2.21)
>
> The compiler accepts `[]` today and users will write `xs: List[T] = []` constantly; it is the most common generic default after `None`. Add `[]` to the const table ("empty list literal"). It is safe because §2.13 fills the default at each call: every call gets a fresh empty list. This is the one place Blink beats Python, whose `def f(xs=[])` shares one mutable list across calls (the most-asked default question in Python). Say so in one line in §2.13.
>
> I would not admit non-empty list literals (`[1, 2]`) in this ticket: no one asked, and min will rightly ask why.
>
> ## Cross-language
> - Python, Kotlin, Swift: a default is checked against the declared type. Swift rejects `func h<T>(x: T = 3)` with "cannot convert Int to T" — same rule as web-1. Kotlin likewise.
> - C++ `template<class T> void h(T x = 3)`: `h()` fails to deduce `T`; the default never drives deduction. Same outcome.
> - TypeScript allows `<T = number>` (a type default), which Blink's "never defaulted" rule forbids. Not proposed.
> - Rust: no defaults; people write `Option<T>` + `unwrap_or`. web-1 lands on that idiom with less ceremony.

**PLT:**

> ## plt-1 (recommended): a default is checked once, with every type parameter rigid
>
> **Typing rule.** For `fn f[T1..Tn](..., *, x: τ = e)`, check `e : τ` once, at the declaration, with `T1..Tn` held abstract (rigid, as in the body). The default is then a closed term of type `∀T1..Tn. τ`. A call instantiates it at the call's own solution for the `Ti`. The default never adds a constraint to that solution.
>
> This is the conservative reading the compiler already takes. I want it written down because it is the only reading that is sound and local.
>
> ```blink
> fn h[T](*, x: T = 3) -> T { x }                // error: `3` is Int, not every T
> fn g[T](*, x: Option[T] = None) -> Option[T] { x }   // ok: None : ∀a. Option[a]
> fn k[T](*, xs: List[T] = []) -> Int { xs.len() }     // ok: [] : ∀a. List[a]
> fn h2[T](a: T, *, b: Option[T] = None) -> T { b ?? a }
>
> fn main() {
>     io.println("{h2(1)}")       // T = Int from `a`; default instantiated at Int
>     let n: Option[Int] = g()    // T = Int from the expected type
>     io.println("{k[Str]()}")    // T written at the call
> }
> ```
>
> `g()` alone as a statement, with nothing else fixing `T`, is `error[CannotInferType]` (E0301) at the type-argument position. That is §3.4 unchanged: the default does not count as a source.
>
> Per shape:
> - bare `T`: no const fits, so no default. That is correct: a value of every type does not exist.
> - `Option[T]`, `List[T]`: `None` and `[]` fit.
> - `Box[T]`: fits only when every field that mentions `T` takes a value that fits all `T` (`Box { v: None }` for `v: Option[T]`).
> - fn type `fn(T) -> T`: no const fills it today (fn references are not const). If a later change makes a generic fn reference const, `identity` fits by this same rule with no new text.
>
> **Why sound.** Parametricity (§3) holds: the default cannot observe `T`, so the body still sees a parametric argument. No erasure holds: `T` comes only from the call, never from the default, so `T` is never defaulted. Instantiation is plain ∀-elimination, so `h2(1)` and `h2("s")` need no new check at the call.
>
> **Diagnostic.** Today's text, "argument 1 of `h` expects T, got Int", is wrong: there is no argument 1 at the default. Name the default and the type parameter, at the default:
>
> ```
> error[TypeError]: default of `x` must fit every `T`, but `3` is Int
>   help: make the parameter `Option[T]` and default to `None`
>   help: or remove the default
> ```
>
> **§2.21 change.** The const table does not list `[]`, yet keyword defaults accept it. Add the empty list literal `[]` to the table as a const of type `List[α]`, as `None` is `Option[α]`. Leave non-empty list literals out of scope for this ticket.
>
> **§2.13 text.** Replace the "not yet specified" sentence with: "A default is checked once against the declared parameter type, with the function's type parameters abstract. It must fit every instance, so it fixes no type parameter at a call."
>
> ## plt-2 (opposed): infer the default at each call
>
> The old behaviour. The default becomes a call-site constraint, so `h()` picks `T = Int`. That defaults a type parameter (breaks "no erasure"), moves the error for `h2("s")` into the caller at code the caller cannot see, and makes the fn value (full arity, §2.13) disagree with the direct call. Reject.
>
> ## plt-3 (opposed): forbid any default on a parameter whose type names a type parameter
>
> Sound but too strict. It rejects `Option[T] = None`, the common idiom, and gains nothing plt-1 does not already give.
>
> ## Cross-language
>
> Swift and Kotlin take plt-1: `func h<T>(x: T = 3)` is rejected at the declaration. mypy rejects `def h(x: T = 3)` the same way. C++ takes plt-2: a default argument in a template is instantiated on use, so it fails late and inside the caller. That is the failure mode we want to avoid. Rust has no defaults.

**DevOps:**

> ## devops-1 (recommended): check once, at the declaration, for every instance
>
> **Rule.** The compiler checks a default once, against the declared parameter type. Each type parameter of the function counts as a fixed, unknown type (rigid). A default is legal only if it fits that type for every type a caller can choose. The default plays no part in inference at a call.
>
> ```blink
> fn g[T](*, x: Option[T] = None) -> Option[T] { x }    // ok: None fits Option[T] for every T
> fn k[T](*, xs: List[T] = []) -> List[T] { xs }        // ok
> fn b[T](*, box: Box[T] = Box { items: [] }) -> Box[T] { box }  // ok if every field fits
> fn h[T](*, x: T = 3) -> T { x }                       // error: 3 fits only Int
> fn h2[T](a: T, *, b: T = 0) -> T { b }                // error at the default, even though h2(1) would fix T = Int
> ```
>
> A fn-typed parameter (`*, f: fn(T) -> T`) cannot take a default, because no const expression has a fn type. The spec needs no extra text for it.
>
> **Calls.** `h2(1, b: 2)`: `a` fixes T. `g()` alone: nothing fixes T, so it is `error[CannotInferType]` (E0301) at the call's type-argument position, as for any other under-determined call. `let y: Option[Int] = g()` and `g[Int]()` are ok. This is §3 *No erasure* applied directly: the default value never supplies T, so T is never defaulted.
>
> **Diagnostic.** Keep E0300 (no new code), but fix the text. Today it reads "argument 1 of `h` expects T, got Int". That is wrong: no argument exists, and the user wrote no call. Proposed:
>
> ```
> error[TypeError]: default of `x` does not fit type `T`
>  --> p.bl:1:22
>   |
> 1 | fn h[T](*, x: T = 3) -> T { x }
>   |               -   ^ this is `Int`
>   |               |
>   |               `T` is chosen by each caller
>   = note: a default must fit the parameter type for every `T`; `3` fits only `Int`
>   = help: declare `x: Int`, or declare `x: Option[T]` with default `None`, or remove the default
> ```
>
> Tooling reasons for this rule:
> 1. The author gets the error once, in their own file. Under per-call inference, each caller gets an error in the caller's file. When the generic fn lives in a package, that caller cannot fix it.
> 2. Hover and signature help show the declared type, and that is the true type. Under per-call inference, `x: T = 3` hides a rule that "T is Int when you omit x".
> 3. A fn value of `h` takes every argument (§2.13), so per-call inference would make `h()` and `let f = h` disagree about T. That is a bad thing to explain in an error.
>
> **§2.21.** Add the list literal to the const table: `[]`, and `[e, ...]` with const elements. The compiler accepts `[]` today, §2.14/§2.13 examples need it, and §2.13 already fills a default afresh at each call, so Python's shared-mutable-default bug cannot occur. Keep `Map.new()` out (it is a call).
>
> **§2.14.** Apply the same rule to a field default on a generic type (`type Box[T] { x: T = 3 }` is the same error). One rule, one diagnostic.
>
> **§2.13.** Replace "not yet specified" with the rule above and the `h`/`g` examples.
>
> ## devops-2 (oppose): infer T from the default at each call
>
> This is the old behavior. It moves the error to every call site, makes the signature on hover misleading, and is a defaulted type parameter, which §3 *No erasure* forbids. Reject.
>
> ## Cross-language
>
> - Swift: `func h<T>(x: T = 3)` is rejected: "default argument value of type 'Int' cannot be converted to type 'T'". Same as devops-1.
> - Kotlin: `fun <T> h(x: T = 3)` is a type mismatch at the default.
> - mypy: "Incompatible default for argument 'x' (default has type 'int', argument has type 'T')".
> - C++: template deduction never uses a default argument; `h()` fails to deduce T. Default template *arguments* (`template<class T = int>`) are the separate feature Blink does not have.
> - Rust: no defaults.

**AI/ML:**

> ## aiml-1 (preferred): check the default once, with each type parameter held abstract
>
> **Rule for §2.13.** A default is checked once, at its declaration, against the declared parameter type, with every type parameter of the function held abstract (rigid). The default must have that type for every instantiation. A default never takes part in inference at a call: an omitted argument gives no evidence about `T`.
>
> ```blink
> fn h[T](*, x: T = 3) -> T { x }                      // error: default must fit `T` for every T
> fn g[T](*, x: Option[T] = None) -> Option[T] { x }   // OK: `None` is `Option[T]` for every T
> fn k[T](*, xs: List[T] = []) -> Int { xs.len() }     // OK: `[]` is `List[T]` for every T
>
> type Box[T] {
>     v: Option[T]
> }
> fn b[T](*, bx: Box[T] = Box { v: None }) -> Box[T] { bx }   // OK
>
> fn h2[T](a: T, *, b: Option[T] = None) -> T { a }
> fn main() {
>     let n = h2(1)               // T = Int from `a`; `b` filled with None
>     let o: Option[Int] = g()    // T = Int from the expected type
>     g()                         // error[CannotInferType] at the call: write g[Int]()
> }
> ```
>
> A fn-typed parameter (`*, f: fn(T) -> T = ...`) cannot take a default today, since no fn value is a const expression. The rule needs no special case for it.
>
> **How it meets the other rules.** No erasure and §3.4 hold unchanged: `g()` with nothing fixing `T` is E0301 at the call's type-argument position, the same as `make()` for `fn make[T]() -> List[T]`. Parametricity holds because the only defaults that fit are values that do not depend on `T`.
>
> **Diagnostic** (at the default, not at a call):
> ```
> error[TypeError]: default for `x` must have type `T` for every `T`, got `Int`
>   help: change the parameter type to `Int`, or remove the default
> ```
>
> **§2.21 change.** Add `[]` (the empty list literal) to the const table. The compiler accepts it today, and §2.21 does not list it, so the spec and compiler disagree. Leave element-bearing list literals out of this ticket.
>
> **Why, from my seat.**
> - One rule with no call-site branch. A model reads the signature and knows if the default is legal. Under the old "infer at each call" behavior, the same declaration was legal or not depending on how a caller used it, so a model must look at every call to predict an error. That is the costly decision point.
> - Signatures stay honest for retrieval. `blink query --fn h` shows `x: T = 3`. A model that sees that line will assume `T` can be anything, and it cannot. Checking once removes signatures that lie.
> - Matches training data from most typed languages. TypeScript rejects `function f<T>(x: T = 3)` ("'T' could be instantiated with an arbitrary type"). Kotlin and Swift reject it the same way. C++ default template arguments and Python are the outliers: C++ checks the default lazily at each instantiation, Python does not check it. Rust has no defaults. A model trained on TS/Kotlin/Swift will expect this rule.
> - No token cost for the common case. The useful generic defaults (`None`, `[]`) still work.
>
> ## aiml-2 (fallback, oppose): forbid any default on a parameter whose type names a type parameter
>
> Simpler to state, but it rejects `*, x: Option[T] = None`, the one generic default people write often. A model then has to write a second function or force callers to pass `None`. More tokens, and no gain in soundness over aiml-1.
>
> ## aiml-3 (oppose): restore inference from the default at each call
>
> `h()` would return 3. This turns a default into a hidden type argument, which conflicts with "never defaulted" in §3 *No erasure*, and makes legality depend on the call. Worst for generation accuracy.

**Minimalism:**

> ## min-1 (preferred): no new rule. A default is an ordinary expression checked at its declaration, with each type parameter rigid.
>
> The compiler already does this. The spec needs one sentence in §2.13 to replace "is not yet specified":
>
> > A default is checked once, at the declaration, against the declared parameter type, with each type parameter of the function held abstract. A default fits only when it fits every instance. An omitted argument adds no constraint on any type parameter.
>
> ```blink
> fn h[T](*, x: T = 3) -> T { x }                 // error: default 3 is Int, x is T
> fn g[T](*, x: Option[T] = None) -> Option[T] { x } // ok: None fits Option[T] for every T
> fn b[T](*, v: Box[T] = Box { item: None }) -> Box[T] { v } // ok when Box[T] has field item: Option[T]
> fn m[T](*, f: fn(T) -> T = ...) { }             // no default possible: a fn literal is not const (§2.21)
>
> fn h2[T](a: T, *, b: Option[T] = None) -> T { a }
> h2(1)        // T = Int from `a`; the default adds nothing
> g()          // error[CannotInferType]: nothing fixes T (§3.4); repair: g[Int]()
> ```
>
> Why this is the minimal choice:
> - It is the rule every other expression already obeys. Parametricity (§3) already says a generic body cannot know `T`; a default sits in the signature of that body, so it inherits the same rule. Nothing to learn.
> - `h()` then falls under §3.4 with no special case: nothing fixes `T`, so E0301, repair `h[Int]()`. One rule, one diagnostic.
> - The old behaviour (infer `T` from the default at each call) is a *type default* in disguise. §3 *No erasure* says a type parameter is "never defaulted". Per-call inference would add a second inference source that exists only for omitted keyword args, and it changes the meaning of the same call when a caller passes the argument. Reject.
>
> Diagnostic: keep the existing type mismatch, at the default's span, with a note: "`T` is a type parameter; a default must fit every `T`". Help: "remove the default, or give `x` a concrete type". No new error code.
>
> ## On `[]`
>
> `[]` is not in the §2.21 table, yet the compiler accepts `xs: List[T] = []`. That is a spec/compiler split, but it is a §2.21 question (struct field defaults and non-generic `xs: List[Int] = []` hit it too), not a type-parameter question. Do not widen §2.21 inside this ticket. File it separately; the rule above is right whichever way that goes. If the panel insists on deciding now, the narrowest change is "an empty list literal `[]`" only, not list literals in general, since §2.21 rules out allocating constructors and only the empty one has a fixed, per-call value.
>
> ## min-2 (fallback): forbid any default on a parameter whose type names a type parameter
>
> Zero uses in lib/ or src/ today (rg for generic keyword defaults returns nothing). It is simple to state and to check. But it is a *new* rule that bans `Option[T] = None`, which already works and follows from min-1 at no cost. Addition, not subtraction. I rank it below min-1.
>
> ## Cross-language
> - Rust: no defaults at all; nobody misses generic ones.
> - Kotlin/Swift: a default on `x: T` must type as `T` for all `T`; `fun <T> h(x: T = 3)` is a compile error. Same as min-1.
> - C++: `template<class T> T h(T x = 3)` does not deduce `T` from the default, so `h()` fails. To make `h()` work you write `template<class T = int>`, a type default, which §3 *No erasure* forbids. The old Blink behaviour was that type default without the syntax.
> - Python: no static check; not a model.
>
> §2.21 needs no change for this ticket.

#### Phase B — Debate highlights

One round. The moderator set three options and three variations (V1 the empty list literal and §2.21; V2 generic struct field defaults; V3 the diagnostic) after removing duplicates. Each seat replied in full; all six replies end `STABLE: yes`. Position shifts: **minimalism** moved from V1 (d) to (a), then in Phase C to (b); **PLT** moved from V1 (a) to (b) in Phase B ("V1: I change from (a) to (b)."); **web** moved from (a) to (b) ("I move from (a) to (b), and (a) stays acceptable."); **DevOps** dropped its (c) and chose (a), with (b) accepted if a `const` names one shared list; **systems** ranked (b) first and (d) second; **AI/ML** held (a).

The moderator's option text for the round:

> ## Options after mechanical dedupe
>
> **Option 1: check the default once, at its declaration, with each type parameter rigid; the default never takes part in inference at a call.** First choice of all six (sys-1, web-1, plt-1, devops-1, aiml-1, min-1). `x: T = 3` is an error; `Option[T] = None` fits; a call with nothing that fixes `T` (`g()`) is E0301 at the call, repair `g[Int]()`.
>
> **Option 2: forbid any default on a parameter whose type names a type parameter.** Listed as fallback or opposed by sys-2, plt-3, aiml-2, min-2.
>
> **Option 3: infer `T` from the default at each call (the old behaviour).** Listed only as opposed (plt-2, devops-2, aiml-3).
>
> ## Variations (flagged for debate)
>
> **V1. `[]` and §2.21.**
> - (a) Add the empty list literal `[]` to the §2.21 const table; non-empty list literals out of scope (web-2, plt, aiml).
> - (b) Admit `[]` only as a keyword default or a struct field default, not in `const` declarations; "each fill builds a new empty list" (sys).
> - (c) Add list literals to the table: `[]` and `[e, ...]` with const elements (devops).
> - (d) Do not change §2.21 in this ticket; file it separately. If decided now, empty `[]` only (min).
>
> **V2. Generic struct field defaults (§2.14).** devops: apply the same rule to a field default on a generic type (`type Box[T] { x: T = 3 }` is the same error). Other seats do not cover it.
>
> **V3. Diagnostic.** All seats who cover it: an error at the default, not at a call; today's "argument 1 of `h` expects T, got Int" wording must change. devops and min: no new error code (keep `TypeError`). sys: a bare-`T` parameter gets its own message ("no constant fits every `T`"). Is any diagnostic text spec material, or is it all for the impl ticket?

**Systems:**

> **Option 1: support.** No change from Phase A. **Option 2: oppose**, because it loses `Option[T] = None` and gains nothing. **Option 3: oppose**, because it defaults `T`.
>
> **V1: (b) or (d). Oppose (a) and (c) as written.** New repo evidence, from gen1:
>
> ```blink
> const E: List[Int] = []
> fn main() {
>     let mut c = E
>     c.push(5)
>     io.println("{E.len()}")   // prints 1
> }
> ```
>
> The compiler lowers `E` to one global, `blink_u_E = blink_list_new_atomic()`, allocated once. A push through a copy changes the constant. The same probe shows `let mut b = a; b.push(2)` also changes `a`. That breaks §3c's "values are copied on bind", and [...] covers a similar case. So `[]` is not a compile-time value at the machine level. It is an allocation. (a) puts it in the general table, which makes `const E = []` legal and blesses the global that the probe can mutate. (c) adds `[1, 2]`, which allocates and copies its elements at every fill, and nobody asked for that. A default fills afresh at each call (my Phase A probe showed `k[Int]()` lowering to a new `blink_list_new_atomic()` in the caller), so `[]` is safe there and only there. If the panel wants the narrowest step, I accept (d): file `[]` separately, and note that the Option 1 rule does not depend on it. I rank (b) first and (d) second.
>
> **V2: support devops.** A generic struct field default fills at each construction, after mono, the same way a keyword default does. One rule, one check, one diagnostic.
>
> **V3:** Diagnostic text goes in the impl ticket. The spec says only that the error is at the default, not at a call. I drop my request for a separate bare-`T` message. The common text ("must fit every `T`") covers it, and I agree there is no new code.
>
> **For the moderator:** the probe also shows two codegen bugs, a list alias on bind and a mutable `const` list. These are outside this ticket. Someone outside the panel should file or link them (see [...]).
>
> STABLE: yes

**Web/Scripting:**

> **Option 1: support.** No change from Phase A. All six seats got there independently, and it is what Swift, Kotlin, TypeScript and mypy users already expect. Nobody coming from those languages needs a new idea.
>
> **Option 2: oppose.** It bans `x: Option[T] = None`, which is the generic default people actually write, and it gives nothing that Option 1 does not already give. The user would see a rule with no reason they can find.
>
> **Option 3: oppose.** One signature that returns Int for `h()` and Str for `h(x: "a")` is a type default hidden in a value. It would generate questions for years.
>
> **V1 (`[]`): I move from (a) to (b), and (a) stays acceptable.** sys convinced me. A keyword default and a field default run again at each fill, so a new empty list each time is correct, and it avoids Python's shared-mutable-default bug. A `const EMPTY = []` declaration names one value. That raises an aliasing question that nobody asked about and this ticket does not need to answer. (b) admits `[]` only where users write it. I oppose (c): `[1, 2]` as a default has no demand behind it, and it hides a copy at each call. I oppose (d): the compiler accepts `[]` today and the spec does not list it. Writing the generic rule while leaving that gap open means the example `xs: List[T] = []` in §2.13 is not backed by §2.21.
>
> **V2 (generic struct field defaults): support devops.** `type Box[T] { x: T = 3 }` is the same question. One rule in two places is easier to learn than one rule plus a gap. A one-line cross-reference from §2.14 to §2.13 is enough.
>
> **V3 (diagnostic): put the shape in the spec and the wording in the impl ticket.** The spec should say: the error is at the default (not at a call), it names the parameter and the type parameter, and it stays `TypeError` (no new code). The exact text, including sys's separate message for bare `T`, belongs to the impl ticket. What the spec must rule out is today's "argument 1 of `h`", because it names a call that does not exist.
>
> STABLE: yes

**PLT:**

> **Option 1: support.** All six seats agree. Typing rule: `e : τ` is checked once with the type parameters rigid, so the default is a closed term of type `∀T̄. τ`, and a call takes it with ∀-elimination at the call's own `T̄`. **Option 2: oppose.** It is sound but adds a ban that Option 1 makes unnecessary (min-2 says the same). **Option 3: oppose.** It is a type default, which "No erasure" forbids.
>
> **V1: I change from (a) to (b).** sys's aliasing point is a soundness point, not only a cost point. Lists alias (§3.2.2). `[]` is useful only if it is generalized to `∀a. List[a]`. A `const EMPTY = []` that names one shared list, used at two types, is the ML value-restriction hole: push an `Int` at one use, read a `Str` at another. `None` is safe to generalize because it is immutable. A default is not one value: the compiler builds it again at each fill, so it is generalized the way `fn[a]() -> List[a] { [] }` is. Therefore:
> - Admit `[]` as a keyword default and a struct field default only, not in a `const` declaration.
> - The spec must say "each fill builds a new value". §2.13 says the call "fills each omitted keyword parameter with its const default" but does not say it is fresh. Without that sentence, (b) is unsound.
> - (c): out of scope. A non-empty literal with const elements has the same typing, but it is a §2.21 feature, not this ticket.
> - (d): acceptable if the panel prefers it, but the `[]`-in-`const` hole then stays open with nothing in the spec to stop it.
>
> **V2: support devops.** A field default on `type Box[T]` is the same judgment with the type's parameters rigid. One rule in two places, §2.13 and §2.14. The construction site instantiates the default as a call site does.
>
> **V3.** Spec material: the error is reported **at the default**, never at a call, and it uses the existing `TypeError` code (no new code). That location is normative, as E0301's "where the repair attaches" is. The exact wording, and sys's own message for a bare `T`, belong in the impl ticket.
>
> STABLE: yes

**DevOps:**

> **Option 1: support.** All six seats chose it first. It puts one error at one place, in the author's file. **Option 2: oppose.** It bans `Option[T] = None`, which works today, and adds a rule plus a new diagnostic for no gain. **Option 3: oppose.** It moves errors into callers' files and makes hover show a signature that is not true.
>
> **V1 (`[]`): I change to (a).** I drop my (c). Web and min are right: nobody asked for `[1, 2]`, and sys is right that it hides a copy at each call. Of (a), (b) and (d), I pick (a), because a split of (b) costs the tool surface. "Const expression" and "default expression" become two categories, and the error for `const E = []` then has to explain why the same text is fine as a default. If sys shows that a `const` names one shared heap list (not a new value at each use), I accept (b), and the error for `const E = []` must say "allowed only as a default". I oppose (d). The spec and the compiler disagree today, and the gate checks them against each other. Deferring keeps an unlisted exception in place. The fix is one table row.
>
> **V2 (§2.14): keep, as one sentence.** `type Box[T] { v: T = 3 }` is the same check on the same code path with the same message. If §2.14 does not say so, a later implementer may check field defaults per instance, and we get the C++ late-error failure for structs only. Nobody argued against it. If the panel thinks it is out of scope, I accept it as a follow-up chore, not a vote item.
>
> **V3 (diagnostic): spec states the frame, not the words.** The spec does this elsewhere (§3 truthiness: code, caret, fixed note, help). For this ticket the spec should say: `error[TypeError]` (E0300), no new code. The caret goes under the default, not at any call. The message names the parameter and the type parameter. A help gives `Option[T] = None` or a concrete type. The exact text, and sys's separate wording for bare `T`, belong to the implementation ticket. They are wording inside the same code and span, so I do not oppose them.
>
> STABLE: yes

**AI/ML:**

> **Options.** Support Option 1, no change from Phase A. Oppose Option 2: it bans `Option[T] = None`, the one generic default people write, and adds a rule where Option 1 adds none. Oppose Option 3: legality then depends on the caller, and it is a type default, which §3 *No erasure* forbids.
>
> **V1 (`[]`).** Support (a), with sys's wording added to the row: "the empty list literal `[]`; each use builds a new empty list."
> - Against (d): the spec and the compiler already disagree on `[]`. A model that learns from the spec alone will think `xs: List[T] = []` is illegal and will write `Option[List[T]] = None` plus an unwrap in every body. That costs tokens and teaches the wrong idiom. The fix is one table row, so make it now.
> - Against (b): a row that holds in two of the four const sites and not in the other two adds a decision point a model will miss. sys's aliasing concern has a fix that needs no split: "each use builds a new list" covers a `const` too. Also, `const XS = []` is under-determined anyway (§3.4), so the case is rare.
> - Against (c): non-empty literals copy elements on each fill and widen the ticket. No current need. Leave them for a separate ticket.
>
> **V2 (generic struct field defaults).** Support devops. §2.21 gives keyword defaults and field defaults the same const rule. If the type rule differs between them, a model has to learn two rules for code that looks the same. One sentence in §2.14 that points to the §2.13 rule is enough.
>
> **V3 (diagnostic).** Normative: the error is reported at the default, not at a call, and keeps `TypeError` (no new code). The exact text goes in the impl ticket. The spec should show one example comment (`// error: default must fit every T`) so readers see where the error goes. sys's separate message for bare `T` is a good impl note, not spec text.
>
> **Change from Phase A:** I now accept sys's "new list per use" wording and devops's V2.
>
> STABLE: yes

**Minimalism:**

> **Option 1: support.** It adds no rule. It applies the typing every expression already gets, and it also covers the bare-`T`, `Box[T]` and fn-type shapes without a special case. Six of six agree.
>
> **Option 2: oppose.** It is a new ban on `Option[T] = None`, which works today and follows from Option 1 for free. It also gives no soundness gain (plt-3, aiml-2).
>
> **Option 3: oppose.** It is a type default, and §3 *No erasure* forbids that. It also makes the direct call and the fn value disagree (plt-2, devops-2).
>
> **V1 (`[]`): I change from (d) to (a).** Five seats want to decide it now, and the split between spec and compiler already exists. Deferring it leaves a known gap in the spec. So: add one row to the §2.21 table for the empty list literal `[]` only, with the sentence "each evaluation builds a new empty list". That sentence answers sys's concern about aliasing in a `const` too, so the table does not need a second rule that depends on context.
> - I oppose (b). "Allowed in defaults, not in `const`" makes one expression const in some places and not in others. That is two rules where one does the job. I change my view only if sys shows that `const E: List[Int] = []` would share one list across uses even with the "new each evaluation" sentence.
> - I oppose (c). Nobody asked for `[1, 2]` as a default, and it brings in per-call element copies that the reader does not see (sys). YAGNI.
>
> **V2 (generic struct field defaults): support, as one sentence.** This is not a new rule. §2.14 field defaults are already const (02_syntax.md:2801), and `type Box[T] { x: T = 3 }` has the same gap. One sentence that says "the same rule applies to a field default on a generic type" prevents a second ticket. It adds no mechanism.
>
> **V3 (diagnostic): impl material, not spec.** The spec says only that the error is at the default, not at a call, and that there is no new error code. The exact wording, including sys's separate message for bare `T`, goes on the impl ticket. All six seats agree today's "argument 1 of `h`" text is wrong. Put that fact on the impl ticket.
>
> STABLE: yes

#### Phase C — Final vote

**Moderator facts surfaced on the ballot (no position implied).**
- sys/B1 says `let mut b = a; b.push(2)` changing `a` "breaks §3c's 'values are copied on bind'". The spec, §3.6 *Shared cells* (sections/03_types.md:4083): "Passing or binding a struct copies its fields. A field whose value is a shared cell refers to the same cell after the copy. ... The shared cells are: `List`, `Map` and `Set`; `StringBuilder`; a closure or handler that captured a `let mut` binding." §3.2.2 (:692): "Collections are shared cells (§3.6 *Shared cells*), so an immutable name can observe a change made through a `mut` alias." So list aliasing on bind is the specified behaviour, not a bug.
- The §2.21 table today does not list `[]`, so by the current spec text `const E: List[Int] = []` is not a const expression. The compiler accepts it (sys/B1 probe: one global list, changed through an alias).

**sys withdraws its Phase B claim.** The opening line of sys's Phase C text, verbatim:

> Correction to my B1: list aliasing on bind is the specified behavior (§3.6 *Shared cells*), not a bug. I withdraw that claim. The correction makes my Q2 point stronger. `List` is a shared cell, so a `const` that holds one is a mutable global.

- **Q1: The rule for a default on a parameter whose type names a type parameter.** (6-0 for A)
  - A: Check the default once, at its declaration, against the declared parameter type, with each type parameter held abstract. It must fit every instance. An omitted argument adds no constraint to inference; a call with nothing that fixes `T` is E0301 at the call. (sys-1, web-1, plt-1, devops-1, aiml-1, min-1)
  - B: Forbid any default on a parameter whose type names a type parameter. (sys-2, plt-3, aiml-2, min-2; all fallback or opposed)
  - C: Infer `T` from the default at each call (the old behaviour). (plt-2, devops-2, aiml-3; all opposed)

  - **Systems:** vote A

  > **Q1. Vote: A**
  > **Reasoning:** Checking once with `T` abstract keeps mono a pure substitution. Each instance lowers the same literal at its own layout in the caller, with no dispatch, no boxing and no per-instance type check. The default never informs `T`, so codegen never sees a defaulted type parameter, and errors stay in the author's file rather than at instantiation, which is how C++ does it.
  > **Concern:** The implementation must lower the default after substitution at each call site. If it lowered once at the generic level, `None` of `Option[Int]` and `None` of `Option[Str]` would get the same layout, and they have different layouts.

  - **Web/Scripting:** vote A

  > **Vote:** A
  > **Reasoning:** It is the rule that Swift, Kotlin, TypeScript and mypy users already expect, so nobody has to learn a new idea. The signature reads true: `x: T` means any `T`, and the default cannot quietly turn it into Int. The one surprise left, `g()` alone failing, has a fix the user can see (`g[Int]()` or an annotation).
  > **Concern:** If the error for `g()` at the call does not mention that the omitted default gave no type, users will think the default should have filled `T` and file it as a bug.

  - **PLT:** vote A

  > **Q1. Vote: A**
  > **Reasoning:** With the type parameters held abstract, the default type-checks as a closed term of type `∀T̄. τ`, and each call takes it with plain ∀-elimination. That keeps parametricity: the default cannot observe `T`. It keeps "No erasure": the default never supplies `T`. It also keeps the fn value and the direct call in agreement. B is sound but bans `Option[T] = None` for no gain. C is a hidden type default.
  > **Concern:** The impl might check the default against the instantiated type at mono time and not against the rigid type, so a default that fits only some `T` would slip through as a late error.

  - **DevOps:** vote A

  > **Vote:** A
  > **Reasoning:** The author gets one error, at the default, in their own file. No caller in another package inherits an error it cannot fix. Hover and `blink query` show the declared signature, and under A that signature is true. A call with nothing that fixes `T` falls into the E0301 path that already exists, with its repair `g[Int]()`, so we add no new diagnostic.
  > **Concern:** The implementer may keep today's "argument 1 of `h` expects T, got Int" text, which names a call that does not exist, unless the impl ticket names the fix to the wording.

  - **AI/ML:** vote A

  > **Vote:** A
  > **Reasoning:** A model can tell whether a default is legal from the signature alone, with no need to look at any call. The rule matches what TypeScript, Kotlin, Swift and mypy do, so training data and the spec agree. `Option[T] = None` and `List[T] = []`, the useful generic defaults, still work. `g()` falls under the E0301 rule a model already knows, with no special case.
  > **Concern:** A model trained on Python or C++ may still write `x: T = 3`, so the error message must name the fix (a concrete type, or `Option[T] = None`), not only the mismatch.

  - **Minimalism:** vote A

  > **Q1. Vote: A**
  > **Reasoning:** A adds no mechanism. A default gets the same typing as any other expression, with the type parameters held abstract as they are in the body. Bare `T`, `Box[T]` and fn types then need no special case, and `g()` falls under §3.4 as it stands. B adds a ban on `Option[T] = None`, which works today, and C brings back a default type for `T`, which §3 *No erasure* forbids.
  > **Concern:** The §2.13 text could grow a separate list of cases (bare `T`, `Option[T]`, `Box[T]`, fn type). That would make A read as four rules when it is one sentence plus examples.

- **Q2: The empty list literal `[]` and §2.21.** (5-1 for B, AI/ML dissent)
  - A: Add the empty list literal `[]` to the §2.21 const table, with the text that each evaluation builds a new empty list. Non-empty list literals out of scope.
  - B: Admit `[]` only as a keyword default and a struct field default, not in a `const` declaration. The spec says each fill builds a new value.
  - C: Add list literals to the table: `[]` and `[e, ...]` with const elements.
  - D: No §2.21 change in this ticket; file `[]` separately.

  - **Systems:** vote B

  > **Q2. Vote: B**
  > **Reasoning:** `[]` compiles to a heap allocation (`blink_list_new_atomic()`), and a `List` is a shared cell (§3.6). In a default, each fill makes a new list, which is correct and cheap. In a `const`, the compiler today makes one global list, and any alias can change it, so a "constant" changes at run time. Option A's "each evaluation builds a new empty list" leaves open whether a reference to the `const` counts as an evaluation. B closes that gap.
  > **Concern:** If A wins, the spec must say a reference to a list `const` builds a new list at each use, or the compiler keeps one shared, mutable global behind a name that reads as constant.

  - **Web/Scripting:** vote B

  > **Vote:** B
  > **Reasoning:** Users write `[]` as a default; nobody asked for `const EMPTY = []`. The new fact backs B: lists are shared cells, so a `const` list raises the question "does each use get its own list, or does every use share one?". That question needs its own answer, and today the compiler shares one global list. A default is filled again at each call, so a fresh empty list there is plain and avoids Python's mutable-default bug.
  > **Concern:** If A wins, "each evaluation builds a new empty list" must say clearly that each use of a `const` gets its own list. Otherwise the compiler's current single shared global becomes a silent aliasing bug that users hit.

  - **PLT:** vote B

  > **Q2. Vote: B**
  > **Reasoning:** Lists are shared cells (§3.6), so `[]` is safe to generalize to `∀a. List[a]` only where the compiler builds it again at each use. A default fill does that, and so does a field default at each construction. A `const` names one value. The compiler today makes `const E = []` one global list. To keep A sound, a const reference would have to allocate a new list each time, which goes against what a `const` means. Under B, a one-value const never has a mutable, generalized type, the ML value-restriction hole.
  > **Concern:** If A wins, the impl must make each reference to a list `const` build a new list (today it is one shared global). Without that, a `[]` const used at two element types is unsound.

  - **DevOps:** vote B

  > **Vote:** B
  > **Reasoning:** In B1 I said I would accept B if a `const` names one shared heap list. The facts confirm it: lists are shared cells (§3.6), and the compiler makes one global list for `const E = []`, which changes through an alias. Under A, a `const` would then be a mutable global that `pub let mut` (E1013) forbids, and the error surface could not explain the difference. With B, a default fill builds a new list each time, and `const E = []` stays an error. That error must say "`[]` is allowed only as a keyword default or a field default".
  > **Concern:** If the error for `const E = []` is a plain "not a const expression", users will see `[]` accepted on one line and rejected on the next with no reason given. The message must name where `[]` is allowed.

  - **AI/ML:** *(dissent)* vote A

  > **Vote:** A
  > **Reasoning:** One table row that holds at all four const sites is one fact to learn. B splits `[]` by site, a decision point a model will get wrong from the spec alone. The post-B1 fact (lists are shared cells, and the compiler today builds one global list for `const E: List[Int] = []`) makes the "each evaluation builds a new empty list" text matter more. That text says a `const` reference builds a fresh list at each use, which removes the alias trap at its source. D leaves the spec teaching that `List[T] = []` is illegal, and a model will then write `Option[List[T]] = None` with an unwrap in every body.
  > **Concern:** "Each evaluation" must say plainly that each reference to a `const` counts as one evaluation. If it does not, readers and the compiler will keep today's single shared global, and a push through one alias will show at every use of the const.

  - **Minimalism:** vote B

  > **Q2. Vote: B**
  > **Reasoning:** In B1 I said I would move off A if sys showed that `const E: List[Int] = []` shares one list. The facts show it does. §3.6 makes `List` a shared cell, and the compiler emits one global that changes through an alias. A `const` that names a shared cell is a mutable module global in disguise. That goes around the `pub let mut` ban. "Each evaluation builds a new list" does not fix it unless the spec also says that each const reference re-evaluates, and that would add a second new rule. B admits `[]` only where the spec already fills it again at each use (a keyword default, a struct field default). It closes the split between spec and compiler and opens no global-state hole.
  > **Concern:** If A wins, its sentence must say that each *reference* to a const builds a new list. If it does not, a `const` list becomes shared mutable state that every module can reach.

- **Q3: Field defaults on a generic type (`type Box[T] { x: T = 3 }`).** (6-0 for A)
  - A: One sentence in §2.14 applies the same rule as Q1 (pointer to §2.13).
  - B: Leave it out of this ticket; a follow-up chore.

  - **Systems:** vote A

  > **Q3. Vote: A**
  > **Reasoning:** A field default fills at each construction after mono, the same mechanism as a keyword default. One rule gives one check and one codegen path.
  > **Concern:** The §2.14 sentence must also cover a struct literal that leaves out a field. That literal fills from a generic default at the instance type, and the generic default must not be lowered once.

  - **Web/Scripting:** vote A

  > **Vote:** A
  > **Reasoning:** `type Box[T] { x: T = 3 }` is the same question as `fn h[T](*, x: T = 3)`. One rule, written once, with a pointer from §2.14, is easier to learn and to teach than a rule plus a known gap.
  > **Concern:** The §2.14 sentence must cover a default whose type nests `T` (such as `Option[T]` or another generic struct), not only bare `T`, or the gap comes back.

  - **PLT:** vote A

  > **Q3. Vote: A**
  > **Reasoning:** A field default on `type Box[T]` is the same judgment with the type's parameters held abstract, and the construction site instantiates it as a call site does. One rule stated twice costs one sentence. Leaving it out keeps a hole that the next ticket would have to vote on again.
  > **Concern:** A field default may refer to a type-scoped const whose type mentions `T`. The §2.14 sentence must say the type's own parameters are held abstract, not only the function's.

  - **DevOps:** vote A

  > **Vote:** A
  > **Reasoning:** A field default goes through the same check, with the same span and the same message. One sentence keeps a later implementer from checking a field default once per instance, which would give late, C++-style errors for structs only. It costs one line.
  > **Concern:** The §2.14 pointer must also carry the Q2 outcome for `[]`, or field defaults and keyword defaults will drift apart.

  - **AI/ML:** vote A

  > **Vote:** A
  > **Reasoning:** Keyword defaults and field defaults already share the §2.21 const rule. A different type rule for field defaults would make code that looks the same follow two rules. One pointer sentence costs nothing and closes the gap now.
  > **Concern:** The impl ticket may cover only keyword defaults. The test list must include a generic struct field default, or §2.14 will state a rule that nothing checks.

  - **Minimalism:** vote A

  > **Q3. Vote: A**
  > **Reasoning:** This is the same gap under the same rule. §2.14 defaults are already const expressions. One sentence that points to §2.13 prevents a second ticket and adds no mechanism.
  > **Concern:** The sentence must point to §2.13 and must not repeat the rule, or the two copies will drift apart.

- **Q4: Diagnostic in the spec.** (6-0 for A)
  - A: The spec says the error is reported at the default (never at a call) and uses the existing `TypeError` code, no new code. The exact wording, including any separate bare-`T` message, goes to the impl ticket.

  - **Systems:** vote A

  > **Q4. Vote: A**
  > **Reasoning:** The location rule (at the default, never at a call) is the part that users can see and the part that matters. The message wording belongs in the impl ticket.
  > **Concern:** If the impl keeps "argument 1 of `h`", the user reads it as a call that does not exist, so the impl ticket must state that it rewrites the text.

  - **Web/Scripting:** vote A

  > **Vote:** A
  > **Reasoning:** The spec should fix the shape the user sees: the error is at the default, it names the parameter and the type parameter, and it never names a call that does not exist. Exact wording changes as the compiler improves and belongs to the impl ticket.
  > **Concern:** The impl ticket could keep the "argument 1 of `h`" phrasing because the spec text only says "at the default", so the ticket must name that text as the thing to remove.

  - **PLT:** vote A

  > **Q4. Vote: A**
  > **Reasoning:** Where the error is reported is part of the rule. The error belongs to the author of the declaration, and a caller must never see it. That is the same principle as E0301's "reported where the repair attaches". The wording is a tooling matter for the impl ticket.
  > **Concern:** If the message keeps "argument 1 of `h`", it names a call that does not exist and points the reader at the wrong code.

  - **DevOps:** vote A

  > **Vote:** A
  > **Reasoning:** The spec fixes the frame: code E0300, caret under the default, never at a call. That is what tests and the LSP key on. Wording changes more often than the frame does, so it belongs to the impl ticket, where the golden tests also live.
  > **Concern:** "Wording goes to the impl ticket" may become "wording never gets fixed". The impl ticket needs a golden test that fails on the current "argument 1 of `h`" text.

  - **AI/ML:** vote A

  > **Vote:** A
  > **Reasoning:** Where the error is reported is normative: it shows which file the fix goes in. The wording is not, and putting it in the spec freezes text that should improve. The existing `TypeError` code keeps the code table small.
  > **Concern:** Today's text ("argument 1 of `h` expects T, got Int") names an argument nobody wrote. If the impl ticket does not replace it, models will learn from a message that points at a nonexistent call.

  - **Minimalism:** vote A

  > **Q4. Vote: A**
  > **Reasoning:** The spec needs only where the error is reported and which code it uses. Message wording is tooling detail and belongs on the impl ticket, so the spec carries no text that the compiler can contradict later.
  > **Concern:** The impl ticket could lose the agreed fact that today's "argument 1 of `h`" wording is wrong. Write that fact into the ticket.

### Final Spec

```blink
fn h[T](*, x: T = 3) -> T { x }                       // error: `3` is Int, and `x` is `T` for every `T`
fn g[T](*, x: Option[T] = None) -> Option[T] { x }    // ok: `None` has type `Option[T]` for every `T`
fn k[T](*, xs: List[T] = []) -> Int { xs.len() }      // ok: `[]` has type `List[T]` for every `T`

type Box[T] { x: T = 3 }                              // error: the same rule, with `T` abstract
```

- A default is checked once, at its declaration, against the declared parameter type. Each type parameter stays abstract, so the default must fit every instance (Q1, §2.13).
- An omitted argument adds no constraint to inference. `T` comes from the written arguments, the expected type, or explicit `[...]`. A call with nothing that fixes `T` is E0301 at the call (Q1).
- A field default on a generic type follows the same rule, with the type's own parameters abstract, also when the default's type nests `T` (Q3, §2.14).
- `[]` is a const expression in a keyword default and in a struct field default only, not in a `const` declaration or a range bound. Each fill builds a new value (Q2, §2.13, §2.14, §2.21).
- The error is reported at the default, never at a call, with the existing `TypeError` code. The spec fixes no message text (Q4).
