[< All Decisions](../DECISIONS.md)

# Type Parameters on Effect Operations — Design Rationale

**Gap:** "Spec: may an effect operation declare its own type parameters (`fn put[T](x: T) -> T` inside an effect)? The parser refuses `fn put[T](x: T) -> T` inside an effect declaration (UnexpectedToken: expected (, got [). sections/04_effects.md defers effect-kinded generics to v2 but says nothing about an operation with its own type parameters, primitive or derived. Every spec example uses concrete types. Derived operations over instantiated types (List[Str], Option[Str]) work and are tested."

**Result:**

- **Q1 (6-0, A):** in v1 an effect operation, primitive or derived, takes no type parameters, and an effect takes no type parameters (`effect Store[T]`). The parser accepts `[...]` after an operation name or an effect name and reports the named error, not `expected (, got [`.
- **Q2 (5-1, A; Minimalism dissent):** the golden diagnostic has one "why" note, in language terms.
- **Q3 (4-2, A, in Phase D; PLT and DevOps dissent for B'):** the note text is exactly `a handler provides each operation of an effect with one fixed signature`.
- **Q4 (5-1, A; DevOps dissent):** one help with both parts: declare the operation with concrete types, and write a generic wrapper function that calls it. The help example shows an instantiated type such as `List[Str]` as concrete.
- **Q5 (4-2, A, in Phase D after 3-3 in Phase C; Systems and Minimalism dissent):** sections/ adds exactly one sentence: "A later version may allow type parameters on an operation."

**Points all six seats agreed (not balloted):**

- One code for both shapes, `EffectOpTypeParams`, E0558. The framing is "not allowed in v1". PLT dropped the name `EffectTypeParamsDeferred` in Phase B.
- No lowering words (vtable, slot, boxing, dictionary, ABI, erased, specialized, monomorph) in sections/, the golden diagnostic block included. The lowering reasons and the design constraints live in this file. The ERROR_CATALOG row may carry the reason.
- The wrapper example uses `T: Display` and `x.display()`, as sections/04_effects.md:274 does for `io.println`.
- This is its own deferral, independent of the `Handler[E]` deferral in DECISIONS.md ("Handler generic parameters"). AI/ML and Web withdrew the tie in Phase B. A cross-reference is allowed.
- A later version can relax the rule without breaking a program, because every such program is an error today. When a later version allows the syntax, the code is retired and not reused.
- A derived body may still call generic free functions and use instantiated types.

**Lowering reason (for this file and the catalog row, not for sections/).** A handler is a runtime value. `Handler[E]` can be stored, passed and installed by `with`, and the compiler lowers it to a vtable of its root effect with one slot per operation. A slot holds one function pointer. An operation with its own type parameter has one instance per type, so a later version needs a defined lowering first: erase the type (box the values and pass a type descriptor), or specialize the handler per type. A derived operation does not escape this, because a handler may override any derived operation, and an override is a slot. Systems also noted that a bound (`T: Display`) needs a dictionary passed through the slot. DevOps added a design hint for a later version: generic operations might be limited to those with a static dispatch path. Neither is a rule; the lowering and the hint are open.

**Phase B shifts.** In Phase A, PLT proposed the name `EffectTypeParamsDeferred`, and Systems, DevOps and Minimalism put "vtable" or "slot" in the diagnostic note. After the repo fact that sections/ holds no implementation detail, all four moved: PLT dropped `Deferred`, and the three rewrote the note in language terms. AI/ML and Web withdrew the tie to the `Handler[E]` deferral. PLT dropped the `Encode`-bounds sentence and the claim about row typing of an effect-level `[T]`.

**AI-first review:** 5/5 pass. The rule is one sentence ("an effect and an operation take no type parameters"), it adds no grammar and no decision point, and the repair is the pattern that sections/04_effects.md:274 already teaches. The new code lets `blink explain` teach the fix.

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in independent-proposal → debate → vote rounds. The texts below are the panelists' own, verbatim. The panel ran Phase A (independent), Phase B (one round), Phase C (silent ballot on five questions) and Phase D (a focused round and a silent re-vote on Q3 and Q5).

#### Phase A — Independent proposals

##### Systems

> ## sys-1: reject in v1 (primitive, derived, and effect-level). Generic surface stays in free functions.
>
> **Rule.** An operation in an effect declaration takes no type parameters. An effect takes no type parameters. Both stay in v1 as a named compile error, not a raw parse error. Later versions may relax the rule without breaking any program.
>
> **Why, from the hardware.** A handler is a runtime value. `Handler[E]` can be stored, passed, and installed by `with`. The compiler lowers it to a vtable with one slot per operation (src/cg_reg.bl:238, src/cg_eff.bl:967). A slot holds one function pointer. `put[T]` has one instance per `T`, so a slot cannot hold it. There are only two ways to build it:
>
> 1. Erase `T`. Box every argument and result, and pass a type descriptor. Every `store.put(3)` then allocates or copies, and `T: Display` or `T: Eq` bounds need a dictionary pass. The cost hides behind a call that reads like a plain call.
> 2. Make the handler generic over `T` and instantiate each handler for each `T` used. The set of `T` is not known where `with` installs the handler, because handlers cross function and module boundaries. That is whole-program monomorphization of runtime values. The spec has no trait objects for the same reason.
>
> Neither gives predictable codegen. This is the same limit as Rust object safety: a generic method cannot go in a vtable.
>
> **Derived operations do not escape this.** A derived body runs at the call site, so a derived `fn map[T]` alone could be monomorphized. But a handler may override any derived operation (`logging_get` above). An override is a vtable slot, so the override clause would need to be generic. To allow generic derived operations, the rule would need "this operation cannot be overridden". That is a second kind of operation. I do not want it for a case that a free function covers.
>
> ```blink
> effect Store {
>     effect Put {
>         fn put(key: Str, value: Str)
>     }
> }
>
> // the generic surface is a wrapper, as for io.println (04_effects.md:274)
> fn put_val[T: Display](key: Str, x: T) ! Store.Put {
>     store.put(key, x.display())
> }
> ```
>
> This is the established pattern. `store.put(key, x.display())` costs one monomorphized wrapper per `T` and one vtable call. No hidden cost.
>
> **Diagnostic.**
>
> ```
> error[E0xxx]: effect operation `put` cannot take type parameters
>  --> store.bl:3:15
>   |
> 3 |         fn put[T](x: T) -> T
>   |               ^^^ type parameters are not allowed on effect operations
>   |
>   = note: a handler is a runtime value. Its operations are fixed entries, so each one has one type.
>   = help: keep the operation concrete and put the generic part in a function:
>           fn put_val[T: Display](x: T) ! Store.Put { store.put(x.display()) }
> ```
>
> For `effect Store[T]`, the same code with "effects cannot take type parameters". The parser accepts `[` after the name or operation name so that it can report this. The number comes from ERROR_CATALOG.md.
>
> **Relation to the v2 deferral.** DECISIONS.md:182 defers `Handler[E: Effect]`, which is effect-kinded. This question concerns value type parameters, and it is a different axis. I do not tie them together. I record it as its own deferral: "operation type parameters are rejected in v1. A later version may add them, together with a defined lowering (erased or specialized)."
>
> **Relaxable later?** Yes. Any program that compiles under the rule contains no `[` in an operation signature. Accepting that syntax later changes no existing meaning. The reverse (allow now, restrict later) breaks programs. So reject now.
>
> **Cross-language.** Rust: a generic method makes a trait non-object-safe, or needs `where Self: Sized`. Koka: `effect state<s>` parameterizes the effect, not the operation. OCaml 5: `'a Effect.t` is a GADT, so the result type varies per constructor, but the handler pays by matching on the constructor at run time. Haskell mtl: polymorphic methods work because a dictionary is passed at run time. Go: interface methods cannot take type parameters. Zig: `anytype` only works with comptime-known callees. The runtime-value languages that allow it pay with dictionaries or boxing. Blink promises neither.

##### Web/Scripting

> ## web-1: Reject in v1. Operations and effects take no type parameters. Add a named diagnostic and a help. Write generics in a stdlib wrapper.
>
> **Rule.** An `op_sig` has no `[...]`. An `effect` has no type parameters. This holds for primitive and derived operations. The §4.12 grammar already says this, so the change adds a diagnostic and one spec sentence. It does not change the grammar.
>
> **Why.** A handler is a runtime value (`Handler[E]`: stored, passed, installed by `with`) and lowers to a vtable with one slot per operation. A generic slot cannot be monomorphized per call. It needs boxing or a dictionary parameter, and a handler clause would have to be generic too. Trait methods are different: they resolve statically. §4.5 already says the generic surface is "a stdlib wrapper, not a generic effect operation" (04_effects.md:274). `io.println(x)` shows the pattern: generic outside, `Str` inside. This rule extends that sentence to all effects.
>
> **What users write.**
> ```blink
> effect Store {
>     effect Put {
>         fn put(key: Str, value: Str)
>     }
> }
>
> fn store_json[T: Serialize](key: Str, x: T) with Store.Put {
>     store.put(key, x.to_json())
> }
> ```
> Generic code lives in a free function. The operation takes a concrete type (`Str`, `Bytes`, `Json`). A JS/Python dev sees the same shape as an interface with a serialize step. For a typed key-value store, the user writes one effect per concrete type, or a stdlib wrapper.
>
> **Diagnostic (today a raw parse error).**
> ```
> error[E????]: effect operation `put` cannot take type parameters
>  --> store.bl:3:15
>   |
> 3 |         fn put[T](x: T) -> T
>   |               ^^^ type parameters are not allowed on an operation
>   |
>   = help: use a concrete type in the operation and put the generic part in a free function: `fn put_value[T: Serialize](x: T) with Store.Put`
> ```
> The same code, with a matching message, covers `effect Store[T]` (`type parameters are not allowed on an effect`). The parser accepts `[`, records the error, and recovers. The code number is assigned at implementation. The parser must not stop at `expected (`, because that text sends users to a wrong fix.
>
> **Derived ops.** Same rule. A derived body may call a generic free function (probe d.bl) and use instantiated types (probe c.bl). Only the operation's own signature is closed.
>
> **Relation to the v2 deferral.** §4.7.1 defers `[E: Effect]` over effects. This rule is a separate axis (value parameters). Reject now, and record both under one v2 heading: "generic effect operations and effect-kinded generics". Rejecting a form that is a parse error today breaks no program. A later version can allow `fn put[T](x: T) -> T` with the trait-method rule (§3.4 explicit type application, bounds as on methods) and no old program changes meaning. The reverse (allow now, restrict later) would break code.
>
> **Tradeoffs.**
> - Win: a rule that fits in one sentence; no new handler syntax; no "why does my handler need `[T]` too" Stack Overflow question. One error with a fix.
> - Cost: no typed generic store or state effect (Koka `state<s>`, Haskell `MonadState s`). Users who want `State[T]` must write one effect per type, or use a mutable cell from stdlib. This is the 10% case. Mutable state in Blink is an ordinary `mut` or a stdlib cell, so the loss is small.
>
> **Cross-language.** Koka puts the type parameter on the effect (`effect state<s>`) and on the operation (`fun get() : s`); the cost is in row types, which Blink defers. OCaml 5 `Effect.t` is a GADT: `type _ Effect.t += Put : 'a -> 'a Effect.t` is generic, but handlers are untyped at the effect level, so it is unsound-prone and has no static effect row. Rust rejects generic methods in trait objects (object safety); Blink handlers are the same case: runtime vtables. Go interfaces cannot have generic methods either, and Go users cope with free generic functions. mtl and polysemy have polymorphic methods because dictionaries are cheap there; Blink has no dictionary-passing runtime.
>
> **Fallback if the panel wants it.** web-2: allow on operations only (no effect parameters), require an explicit bound-free `[T]`, and make the handler clause generic. I oppose it for v1: the vtable cost and the generic handler clause are the biggest part of the spec change for the smallest user gain.

##### PLT

> ## plt-1 (preferred): defer in v1, one named diagnostic, grammar slot reserved
>
> **Rule.** An `op_sig` in v1 has no type parameters, primitive or derived. An effect has no type parameters (`effect Store[T]` is also refused). Both are one family: *an effect interface that quantifies over types*. The parser accepts `[...]` after an operation name and after an effect name, then reports a new error, `EffectTypeParamsDeferred`, instead of `UnexpectedToken`. The error replaces today's raw parse error; no valid program changes meaning.
>
> ```blink
> effect Store {
>     effect Put {
>         fn put[T](x: T) -> T      // error[EffectTypeParamsDeferred]
>     }
> }
> ```
> ```
> error[EffectTypeParamsDeferred]: operation `put` declares type parameter `T`
>   help: an effect operation has concrete types in v1. Use a concrete type,
>         or put the generic surface in a stdlib wrapper:
>         fn put_any[T: Encode](s: Store, x: T) -> Str { s.put(x.encode()) }
> ```
>
> **Why sound to defer, not forbidden.** The typing rule is easy: `op : forall T. (T) -> T ! E`; a call `store.put(3)` instantiates `T := Int` by the §3.4 rules, as for any generic fn. A handler clause must then be checked at `forall T`, so an unbounded clause is parametric and cannot inspect `T`. That part is clean, and Koka allows it. The cost is in the handler. A handler is a runtime value with a vtable slot per operation (src/cg_eff.bl:967). Blink monomorphizes, and a slot cannot hold one body per `T`. A bound (`T: Encode`) needs a dictionary passed through the slot. Both need a uniform representation or a dictionary ABI that Blink does not have. Allowing `[T]` now would fix that ABI by accident, before the v2 design of named effect variables (§4.15, DECISIONS.md:182) has chosen it.
>
> **Wrapper pattern.** The generic surface is a stdlib or user free fn over a concrete operation. This is already the rule at 04_effects.md:274 (`io.println` renders with `display()`, then calls the `Str` operation). A derived operation over `List[Str]` stays legal.
>
> **Relaxing later.** Safe. Today every spelling is an error, so no program depends on it. v2 can turn the error into: unbounded `[T]` allowed on primitive and derived ops, handler clauses written `fn put[T](x: T) -> T`, with `Encode`-style bounds only after the dictionary ABI exists. I also propose the v2 text says an effect-level `[T]` follows the same row-typing as `Handler[E]`.
>
> **Tradeoffs.** Users lose a typed `Store.put[T]`, and must box via `Str`/`Bytes`. The gain: one rule, one diagnostic, no half-generic handler.
>
> ## plt-2 (fallback): allow unbounded `[T]` on operations only
>
> Operations may declare unbounded type parameters. Bounds are `GenericOpBound` (deferred). Effects stay non-generic. A handler clause repeats `[T]` and is checked parametrically. Call-site typing is §3.4. The cost: handler slots need a uniform value representation (boxing) for `T`, or per-instantiation handler specialization, which breaks the "handler is a runtime value" rule. I vote against this for v1 unless sys shows a zero-cost lowering. Derived ops would also need `T` in the body's leaf-sub-effect check.
>
> ## Cross-language
> Koka: `effect state<s> { ctl get: () -> s }` and polymorphic ops (`ctl pick: forall a. ...`) exist because Koka has evidence passing with uniform boxed values. OCaml 5: `type _ Effect.t += Put : 'a -> 'a Effect.t` is a GADT constructor, which is polymorphic by design, at the cost of an uncontrolled handler (`match` returns `'a`). Haskell mtl: methods may be polymorphic since dictionaries are boxed. Rust: a generic method makes a trait not object-safe, the exact situation of a vtable handler. That is the reason to defer.

##### DevOps

> ## devops-1: Reject in v1 (primitive, derived, and effect-level), with a dedicated diagnostic
>
> **Rule.** In v1 an effect operation takes no type parameters of its own, and an effect takes none either. An operation signature is `fn IDENT ( params? ) ( -> type )?`, as §4.12 already says. The compiler keeps that grammar but parses an optional `[...]` after the op name, so it can report a real diagnostic. It does not stop with a raw `UnexpectedToken`. The same applies to `effect Store[T]`.
>
> ```blink
> effect Store {
>     effect Put {
>         fn put[T](x: T) -> T      // error
>     }
> }
> ```
>
> ```
> error[E0xxx]: effect operation `put` cannot declare type parameters
>   --> store.bl:3:15
>    |
>  3 |         fn put[T](x: T) -> T
>    |               ^^^ type parameter on an effect operation
>    |
>    = note: a handler is a runtime value with one vtable slot per operation; an operation with type parameters has no single slot
>    = help: declare the operation with concrete types: `fn put(x: Int) -> Int`
>    = help: for a generic surface, write a free function that calls concrete operations: `fn put_any[T: Display](x: T) \{ store.put(x.display()) }`
> ```
>
> (`E0xxx` means the next free code in ERROR_CATALOG.md. The catalog row lists the same three parts: the parse position, the two helps, and the §4.15 link.) The effect-level case uses the same code with the text "effect `Store` cannot declare type parameters" and a help that points to the concrete-effect rule in §4.7.
>
> **Why from the tooling side.**
> - Handler clauses stay one-to-one with operations. `blink fmt`, the LSP "implement missing operations" stub, hover and signature help all print the op signature as written. A generic op forces a generic clause `fn put[T](x: T) -> T` in every handler and in every `Handler[E]` value. The LSP must then infer the clause's bounds from the op, and error messages for a clause mismatch must now explain type-parameter mismatch as well as parameter mismatch.
> - `Handler[E]` is a runtime value stored in a vtable. A generic slot needs either per-type slots (the vtable size depends on call sites, so separate compilation and the archive cache break) or boxing and a dictionary. Neither fits the "predictable, one slot per op" model that tests and traces rely on (`--trace` prints one NDJSON event per op call; a generic op needs a type argument in the event).
> - Traits are different. They are static and monomorphized, so §3c.4 can allow method type parameters at no tooling cost. An effect op is dynamic dispatch. Rust makes the same split: a generic method is not object-safe, and a trait object cannot call it.
> - §4.2 line 274 already sets the pattern: a generic surface is a stdlib wrapper over a concrete operation. The v1 rule extends that pattern; it adds no new concept.
>
> **Derived operations.** Same ban. A derived op is also a vtable slot, because a handler may override it. Its body may call generic free functions (probe d.bl works), which covers the real need.
>
> **Relation to the v2 deferral.** This rule is about an op's value parameters. DECISIONS.md:182 and §4.12 *Generic handler parameters* are about effect-kinded parameters. The two are independent. Reject now, and v2 can add either with no breakage: today no program contains `[` after an op name, so every such program is already an error. A later rule can accept the syntax and give it meaning. If v2 adds effect type parameters, the grammar change is additive too. The one design constraint for v2: generic ops must then be restricted to ones with a static dispatch path (for example, only when the handler is known at the `with` site), or every handler value pays for them.
>
> **What users write instead.**
>
> ```blink
> effect Store {
>     effect Put {
>         fn put_str(key: Str, value: Str)
>     }
> }
>
> fn put[T: Display](key: Str, x: T) with Store.Put {
>     store.put_str(key, x.display())
> }
> ```
>
> For typed storage use one op per concrete type the effect needs, or encode through `Str`/`Bytes` in the wrapper.
>
> **Tradeoffs.** Cost: a user who wants a typed `Store` effect writes a wrapper and loses type safety across the handler boundary (values pass as `Str`). Gain: the diagnostic surface stays small, the handler-clause surface stays small, and we can still add generic ops later.
>
> **Cross-language.** Koka `effect state<s>` puts the parameter on the effect, not the op, and its ops are monomorphic in that parameter; effect-level parameters are what v2 should study. Koka ops with their own `forall` exist but rely on evidence passing. OCaml 5 effects are a GADT `'a Effect.t` with one constructor per effect, and the handler matches by constructor, so a typed result needs a GADT index. Rust trait objects reject generic methods (object safety). Haskell polysemy and mtl allow polymorphic actions because dispatch is by dictionary at compile time. Go has no analog; its interfaces have no generic methods either.

##### AI/ML

> # aiml-1: reject in v1 (primitive and derived ops, and effects themselves)
>
> **Rule.** An effect operation has no type parameters. An effect has no type parameters. Both stay concrete in v1. A handler clause has the same signature as the operation, so a handler clause needs no generic form.
>
> ```blink
> effect Store {
>     effect Put {
>         fn put(x: Str) -> Str
>     }
> }
>
> // Generic surface = stdlib wrapper, same pattern as io.println (04_effects.md:274)
> fn store_put[T: Display](x: T) -> Str with Store.Put {
>     store.put(x.display())
> }
> ```
>
> **Diagnostic.** Replace the raw parse error with a dedicated error at the `[`:
>
> ```
> error[E0xxx]: effect operation `put` cannot declare type parameters
>  --> store.bl:3:15
>   |
> 3 |         fn put[T](x: T) -> T
>   |               ^^^ type parameters are not allowed on an effect operation
>   |
>   = help: declare the operation with concrete types, then add a generic wrapper:
>           `fn put_any[T: Display](x: T) with Store.Put { store.put(x.display()) }`
> ```
>
> The same shape for `effect Store[T]`: "an effect cannot take type parameters". The parser should accept `[...]` after the op name and after the effect name, then report the diagnostic. This gives one clear error and one recovery path, not a cascade of `UnexpectedToken`.
>
> **Why, from the AI/ML seat.**
> - Learnability. The grammar (§4.12) has no `[` in `op_sig`. An LLM that reads the spec writes what the grammar says. Every spec example uses concrete types, so no model has seen a generic op that works. The ticket itself shows the failure: a model that knows trait methods (03c:752) will write `fn put[T]` in an effect, because the two look alike.
> - Decision points. Allowing `[T]` adds three: where T is bound (op, effect, handler), whether the handler clause repeats `[T]`, and how a handler for `Handler[Store.Put]` is stored. Each is a place where a model guesses wrong. A reject rule adds zero.
> - Token cost. A wrapper costs one extra line in the stdlib, paid once. It is not paid at each call site.
> - Wrong-code feedback. A clear error with a `help` that shows the wrapper teaches the fix in one round trip. This matters more than permissiveness, because models repair from diagnostics.
>
> **Cost of the generic option (why I do not propose it).** A handler is a runtime value with a vtable slot per operation (src/cg_reg.bl:238). A generic slot needs either monomorphization per call (impossible for a stored `Handler[E]`, since Blink has no trait objects) or boxing/type-erasure. Either one is a new mechanism. It is also the same machinery that v2 effect-kinded generics will need. Deciding it now binds v2.
>
> **Relation to the v2 deferral.** Parameter-ranges-over-effects (`Handler[E]`, DECISIONS.md:182) and operation-own-type-parameters are two different features, but they share one implementation problem: generic vtable slots. Reject both in v1, and the v2 panel decides both together with full information.
>
> **Can a later change relax it?** Yes. Today these programs do not parse, so no program depends on them. Accepting `fn put[T]` later only turns an error into a valid program. Nothing breaks. The diagnostic code should be reserved and retired when the feature lands.
>
> **Derived ops.** Reject also. A derived op body runs at the call site, so it could be monomorphized. That is true, but it creates a rule where primitive ops cannot be generic and derived ops can. A handler that overrides the derived op then needs a generic clause. Two rules cost more than one. A derived op that wants generics should be a free function.
>
> **Cross-language.** Koka has `effect state<s>` and generic ops, with row-typed effects as the base, so the type system is built for it. OCaml 5 effects are `'a Effect.t` GADT values: the generic part is in the type of the effect constructor, not in a handler vtable. Rust: generic methods make a trait not object-safe; Blink handlers are runtime values like trait objects, so the same wall applies. Go interfaces cannot have generic methods, and Go teams use wrapper functions, as here. Haskell mtl and polysemy allow polymorphic ops because dictionaries are passed at runtime; Blink has no such dictionary for handlers.
>
> ## Fallback (aiml-2), only if the panel allows generics
>
> Primitive and derived ops may declare `[T]`; no effect type parameters; no bounds except existing trait bounds; the handler clause must repeat the same `[T]` list; a stored `Handler[E]` is rejected for an effect with a generic op unless the effect is closed over concrete instantiations. I rate this worse on every axis in my seat.

##### Minimalism

> ## min-1: Reject. No type parameters on an effect or on any operation (primitive or derived). Add one dedicated diagnostic.
>
> **Rule.** An `op_sig` has no `[...]`, as §4.12 already says. An effect declaration has none either. The spec gains one sentence in §4.12: "An effect operation has concrete parameter and return types. Neither an effect nor an operation takes type parameters." Primitive and derived operations follow the same rule. Today's grammar already encodes it; the gap is only the missing sentence and the raw parse error.
>
> **Diagnostic (new, replaces the raw `expected (, got [`).**
>
> ```
> error[EffectOpTypeParams]: an effect operation cannot take type parameters
>   --> store.bl:3:15
>    |
>  3 |         fn put[T](x: T) -> T
>    |               ^^^ `Store.Put.put` declares `[T]`
>    |
>    = help: a handler is a runtime value with one fixed slot per operation.
>            Declare the operation on a concrete type, or write a generic
>            function that calls it:  fn put_any[T: Display](x: T) = put(x.display())
> ```
>
> The same code covers `effect Store[T]`. The parser accepts `[` after the name and the checker rejects it, so one message covers both shapes.
>
> **What users write instead.** This is the existing pattern at 04_effects.md:274: the operation takes `Str` (or `Bytes`, or a concrete enum), and a generic stdlib wrapper converts first.
>
> ```blink
> effect Store {
>     effect Put {
>         fn put(key: Str, value: Str)
>     }
> }
>
> fn put_any[T: Display](key: Str, value: T) with Store.Put {
>     Store.put(key, value.display())
> }
> ```
>
> A generic caller keeps its own `[T]`. Only the effect boundary stays concrete. Where a program needs a typed store, it declares one effect per type (`IntStore`, `StrStore`) or serializes at the boundary.
>
> **Why reject (domain: surface conservation).**
> - A handler is a runtime value in a vtable with one slot per operation. A generic slot cannot be monomorphized, because the handler is chosen at runtime. It would need dictionary passing or boxing. Trait methods avoid this since Blink has no trait objects. The trait precedent (03c:752) does not transfer.
> - It forces three more rules: a generic handler clause (`fn put[T](x: T) -> T` in every handler), bounds on an op (`T: Display`, then every handler receives a dictionary), and call-site inference through `with`. Each interacts with the pending derived-body rule and with row typing. None has a user asking for it. Every spec example uses concrete types.
> - The effect-kinded deferral (DECISIONS.md:182) already says handlers stay concrete in v1. Allowing generic ops would reopen the same machinery one door later.
> - Rule 04_effects.md:274 already commits the stdlib to the wrapper pattern. The pattern works today and costs nothing.
>
> **Relation to v2 and relaxing later.** Rejecting is a strict subset: no valid program uses the syntax, so a later panel can accept `fn put[T]` (with generic handler clauses) and break nothing. The new error code becomes dead then and is removed. I would not bind it to the v2 effect-variable work: the two are independent, and the later change can land first or never.
>
> **Cost.** One diagnostic, one grammar sentence, one corpus test per shape (op generic, effect generic). No runtime or codegen change.
>
> **Cross-language.** Go interfaces have no generic methods, and the Go team has refused them for the same dispatch-cost reason. Rust forbids generic methods on trait objects (object safety) for the same reason: a vtable slot has one type. Koka's `effect state<s>` parameterizes the whole effect, never one operation, and Koka resolves it at the handler install site. OCaml 5 effects are typed `'a Effect.t` per constructor, so an operation is an instance, not a generic method. Haskell mtl and polysemy do allow polymorphic methods, but only because a dictionary is passed at runtime; Blink does not take that cost for a feature with no demand.
>
> **Fallback if the panel wants something.** The smallest step up is min-2: allow type parameters on an effect (`effect Store[T]`, as Koka), never on an operation, deferred to v2 with effect-kinded generics. I do not propose it.

#### Phase B — Debate highlights (one round)

The panel got the six Phase A texts, deduplicated into two options. **Option 1:** in v1 neither an effect operation (primitive or derived) nor an effect takes type parameters; a named diagnostic replaces the raw parse error; the generic surface is a free wrapper function over a concrete operation (first choice of all six seats). **Option 2** (fallbacks; no seat proposed them first): **2a**, allow unbounded `[T]` on operations only, with the handler clause repeating `[T]`; **2b**, allow type parameters on an effect only, deferred to v2. Four variations went to debate: V1 the name and framing of the diagnostic, V2 the text of the diagnostic, V3 the relation to the `Handler[E]` deferral, V4 what the spec records about a later version. Each seat's reply is below, verbatim.

##### Systems

> ## sys, Phase B round 1
>
> **Option 1.** I support it. All six seats agree on it as first choice. I oppose 2a and 2b for v1.
>
> 2a (unbounded `[T]` on operations, clause repeats `[T]`) has no zero-cost lowering. I cannot show one, and plt and web asked for one. A vtable slot holds one function pointer. So 2a means boxing with a type descriptor, or per-`T` handler instances that the compiler cannot enumerate at `with`. Unbounded `[T]` is also nearly useless: an operation that cannot call `T`'s methods can only move the value, so the real use cases need bounds, which need dictionaries. 2b (`effect Store[T]`) is a different cost, because one `T` per handler type is monomorphizable. But it is effect-kinded in effect and ties to `Handler[E]` row typing. I agree with min: defer it, do not design it now.
>
> **V1 (name).** The catalog requires a PascalCase name and an E-number. I take one code for both shapes. The name should say "rejected": `EffectOpTypeParams` (min-1), not `...Deferred`. A "deferred" name promises a feature. The panel has not promised it.
>
> **V2 (text).** Change from Phase A: the spec's golden diagnostic block must hold no lowering detail (project rule). My `note:` said "runtime value ... fixed entries". Rewrite it in language terms: "a handler provides each operation of an effect with one fixed signature". Keep the why in the decision file and the ERROR_CATALOG row, where lowering text is allowed. Keep one help line with the concrete-op plus wrapper fix. I accept `x.display()` for the example, because it matches 04_effects.md:274.
>
> **V3.** Independent. Tying the two lets the effect-variable design set the operation rule by accident. plt's concern (an ABI fixed by accident) is a reason to reject now, and it applies equally with or without a tie.
>
> **V4.** The spec text says only "not allowed in v1". It records no lowering plan. The decision file may note that a later version needs a defined lowering (erased or specialized) first. I accept devops's "static dispatch path" as a design note in the decision file only. The relaxation property holds: every such program is an error today.
>
> STATUS: ready to vote

##### Web/Scripting

> # web — Phase B round 1
>
> **Option 1.** I support it. All six seats choose it first, and I see no case for 2a or 2b. 2a puts the biggest spec and handler cost behind the smallest user gain. 2b has no user and no one proposed it.
>
> **V1 (name).** Use the "not allowed" framing, one code for both shapes: `EffectOpTypeParams`. A name with "Deferred" makes users think the feature is coming and wait for it. A user who sees the error wants to know what to do, not the roadmap. The v2 plan belongs in the decision file, not in the error name.
>
> **V2 (text).** Two parts: the message states the rule, the help gives the fix with a wrapper example. I concede the "why" line has value for a user who asks "why not?". But the project rule keeps lowering detail out of sections/ and out of golden diagnostic blocks. So: no "vtable" or "slot" in the diagnostic. If a note exists, it uses user terms: `note: an operation has one fixed type`. The vtable reason goes in the decision file and the ERROR_CATALOG row. For the wrapper bound I do not care: `Display` is the best choice, since `io.println` already uses `x.display()`. This also shows users the one pattern they already know. My `to_json` example was only an example; I withdraw it in favor of `Display`.
>
> **V3 (tie to v2).** I change my Phase A position. I wrote "record both under one v2 heading". Six seats read it as a coupling, and sys, devops and min are right: the two are different axes (value parameters vs effect-kinded parameters). Tying them means a v2 decision on `Handler[E: Effect]` blocks a decision on `fn put[T]`, or the reverse. Record this as its own deferral in DECISIONS.md, with a cross-reference to line 182 and no dependency.
>
> **V4 (later version).** The spec text says one sentence: "A later version may allow type parameters on an operation." It names no lowering (erased, specialized, dictionary). The design constraints (static dispatch path, dictionary ABI) are implementation facts and belong in the decision file only. When the feature lands, the error code is retired, not reused.
>
> **Change from Phase A:** V3 (decoupled), `to_json` to `display`, and no lowering words in the diagnostic.
>
> STATUS: ready to vote

##### PLT

> # plt, Phase B round 1
>
> **Options.** I support Option 1. I oppose 2a for v1. I oppose 2b as a v1 feature: an effect with a type parameter is a type constructor over rows, and §4.15 has not fixed how rows treat it. Option 1 loses nothing, since all six seats chose it.
>
> **V1 (name).** I concede. Use `EffectOpTypeParams` plus an effect-level sibling only if the catalog wants two rows; one code for both shapes is enough. My "Deferred" name made a promise in the code name. A name states what the compiler checks, not a schedule. Drop `Deferred`. The help may say "v1".
>
> **V2 (text).** Include the "why" note (sys, devops, min). A user who knows ML will otherwise read the rule as arbitrary, and will ask why Koka allows it. One line: a handler is a runtime value with one fixed signature per operation. That sentence states a typing fact (each operation has one type, not a scheme), so it needs no lowering detail and stays inside the "no implementation in sections/" rule. I would not write "vtable" or "slot" in the spec; the ERROR_CATALOG row may. For the wrapper, any bound that exists in the stdlib works. `Display` (sys, aiml, devops, min) is the one 04_effects.md:274 already uses, so take that and drop my `Encode`.
>
> **V3 (tie to v2).** I disagree with tying the two. Handler parameters ranging over effects (`E: Effect`) and operations ranging over types are different quantifiers: one is over rows, one is over value types. A v2 vote on one must not bind the other. Record it as its own deferral. Weak concession: the v2 section may cross-reference both.
>
> **V4 (later text).** Spec says only: "A later version may allow type parameters on operations." No ABI wording, since that is implementation. I withdraw the `Encode`-bounds sentence from plt-1; bounds need their own vote then.
>
> **Change from Phase A.** Drop the `Deferred` name, drop the effect-level row-typing claim (unargued), drop `Encode`.
>
> STATUS: ready to vote

##### DevOps

> # Phase B1 — devops
>
> **Options.** I support Option 1. All six seats start there, and I oppose 2a and 2b. 2a (op-level `[T]`) puts a generic clause in every handler, forces the LSP to infer clause bounds, and makes a clause-mismatch error explain type parameters as well as parameters. Nobody has shown a lowering that avoids this. 2b is out of scope for this question: effect-level parameters belong with the v2 effect work.
>
> **V1 (name).** I take the "rejected" framing and a PascalCase name with an E-number, as every catalog row has. I prefer `EffectOpTypeParams` (min-1) over `EffectTypeParamsDeferred` (plt-1). A name that says "deferred" in a code the user sees promises a feature. The spec has not promised one. The deferral text lives in the decision file. One code covers op and effect: the user's fix is the same, and the message names which one.
>
> **V2 (text).** I keep a "why" line, because a bare "not allowed" gives the user nothing to act on. I change my wording after the repo fact that sections/ holds no implementation detail. My Phase A note said "vtable slot". The note now reads: "a handler is a runtime value. Its operations are fixed entries, so each has one type" (sys-1's wording). I concede the vtable wording to the decision file only. I keep two helps: the concrete-type form, then the wrapper form. A user who reads only the first help gets a working program. For the wrapper I use `x.display()` with `T: Display`. It matches `04_effects.md:274`, so the diagnostic and the spec show one pattern.
>
> **V3.** Independent from the v2 effect-kinded deferral, as in sys-1 and min-1. DECISIONS.md:182 is about effect-kinded handler parameters, and this is about an op's value parameters. If the two share one heading, the v2 panel must take both, or neither. I would not bind it. Note the effect-level `[T]` case in v2 notes only.
>
> **V4.** The spec text says nothing about a later version, apart from the existing v2 deferral. I withdraw my "static dispatch path" constraint from the spec side. It was a design hint, and it belongs in the decision file. On removal: when a later version allows the feature, the catalog row is retired, not reused, so old tickets and docs keep a stable code.
>
> **Change from Phase A.** The vtable wording (above), the name (now `EffectOpTypeParams`), and the v2 constraint (moved out of the spec).
>
> STATUS: ready to vote

##### AI/ML

> # aiml, Phase B round 1
>
> **Options.** I hold Option 1. All six seats converge. I oppose 2a and 2b for v1. 2b adds a type-parameter list to the effect grammar, and no seat shows a need for it.
>
> **V1 (name).** I support a name without "Deferred", such as min-1's `EffectOpTypeParams`. A "Deferred" name promises a feature the spec does not promise. One code covers both shapes (op and effect). Every ERROR_CATALOG row needs a PascalCase name and an E-number, so my Phase A "E0xxx" with no name was incomplete. I accept min-1's name.
>
> **V2 (text).** I change my position. I support a "why" line, but a short one that states the rule, not the implementation: "an effect operation has concrete types". sys-1 and devops-1 put "vtable slot" in the note. The project rule says sections/ holds no implementation details, and golden diagnostic blocks are in sections/. A model that reads a vtable note learns nothing it can act on. The help line, which names the wrapper fix, does the teaching. One help with both parts (concrete operation, then wrapper) costs fewer tokens than two helps. For the bound in the example I prefer `Display`, because §4 line 274 already uses `x.display()`. A model then sees one pattern in two places.
>
> **V3 (tie to v2).** I concede in part. I wrote "the v2 panel decides both together". sys-1, devops-1 and min-1 are right that the two features are independent in the type rules. I withdraw the binding. The record should say only: both are deferred and share the generic-slot lowering question, and the v2 panel may take them in one session. The spec should not promise they ship together.
>
> **V4 (record).** Put no lowering text in sections/. A one-line "a later version may allow it" is enough. Put design constraints (erased or specialized, static dispatch only, dictionary ABI) in the decisions/ file, not the spec. I drop "reserved and retired" for the code. The catalog row is simply removed or reworded when the feature lands.
>
> **Unchanged.** Derived ops follow the same rule. The parser accepts `[...]` then reports the named error. A later release relaxes it without breaking programs.
>
> STATUS: ready to vote

##### Minimalism

> ## min, Phase B round 1
>
> **Options.** Option 1. All six seats converge on it, and it adds the least surface: one diagnostic, one grammar sentence. I oppose 2a and 2b. 2a needs generic handler clauses, bounds on operations and a lowering nobody has shown. 2b adds a feature with no user and reopens the v2 effect-variable design.
>
> **V1 (name).** `EffectOpTypeParams`, one code for both shapes. I oppose "Deferred" in the name (plt). A name that promises a later version is a commitment we have not voted. A diagnostic says what is wrong today. If v2 allows the syntax, we retire the code.
>
> **V2 (text).** Concession: my Phase A help line said "a handler is a runtime value with one fixed slot per operation". That is lowering detail. The repo rule keeps lowering out of sections/, and the spec holds golden diagnostic blocks. Change to the sys/devops style: the spec's golden block carries only the language-level reason and the fix. Proposed:
>
> - error: `an effect operation cannot take type parameters`
> - help: `declare the operation with concrete types, and write a generic function that calls it`
>
> The vtable explanation, if wanted, goes in the ERROR_CATALOG row or the `--explain` text, which the rule does not cover. I prefer the wrapper example in the explain text, using `x.display()` with `T: Display`, because 04_effects.md:274 already uses `display()`.
>
> **V3.** Independent of the v2 effect-kinded deferral. I oppose tying them (aiml, web). One v2 heading would make a later panel decide both together, and the two have different costs. This matches sys, devops and my Phase A. I do not accept plt's proposed v2 sentence in the spec: a sentence about the future row typing of an effect-level `[T]` is a promise, not a rule.
>
> **V4.** The spec records nothing about a later version. No "may add later", no "design constraint". DECISIONS.md records the deferral, as it does for the Handler row at :182. Retire the code when the feature lands (aiml, min).
>
> **Change from Phase A.** Only the help text (V2).
>
> STATUS: ready to vote

#### Phase C — Final vote

Silent ballot, five questions. Ballot options:

- **Q1 (the rule).** A: Option 1, no type parameters on an effect operation (primitive or derived) or on an effect in v1. B: 2a, unbounded `[T]` on operations only. C: 2b, type parameters on an effect only, deferred to v2.
- **Q2 (a "why" note in the golden diagnostic).** A: yes, one note line in language terms. B: no note; the reason goes in the ERROR_CATALOG row or `--explain` text.
- **Q3 (the note text, if Q2 A wins).** A: "a handler provides each operation of an effect with one fixed signature". B: "a handler is a runtime value with one fixed signature per operation". C: "a handler is a runtime value. Its operations are fixed entries, so each has one type". D: "an operation has one fixed type". E: "an effect operation has concrete types".
- **Q4 (the help lines).** A: one help with both parts. B: two helps, the concrete-type form first, then the wrapper form.
- **Q5 (what sections/ says about a later version).** A: one sentence, "A later version may allow type parameters on an operation." B: nothing beyond the v1 rule; DECISIONS.md records the deferral.

Note on reading: four voters in Phase C (DevOps, AI/ML, PLT, Web) said they read only the ballot, the brief and their own seat's Phase B file. The Phase D voters were told to read every seat's file.

- **Q1: the rule** (6-0, A)
  - **Systems:** A — "A handler is a runtime value lowered to a vtable with one slot per operation. A slot holds one function pointer, so a generic operation needs boxing or a per-`T` instance set the compiler cannot list at `with`. Unbounded `[T]` also gives little: without bounds an operation can only move the value. Option A costs nothing and any later relaxation breaks no program." Concern: "Users who want a generic store will write a wrapper over `Str` or `Bytes` and pay a conversion at each call, and they may blame the language for that cost."
  - **Web/Scripting:** A — "Every spec example uses concrete types, and the 90% case is `io.println(x)` through a stdlib wrapper. A JS/Python dev gets a clear rule and a known fix (write a generic wrapper) with no new handler syntax. Option A is also the only one a later version can relax without breaking a program." Concern: "A user who wants a generic `Store.put[T]` has to write one op per type or a wrapper, and may see this as a gap next to trait methods, which allow their own type parameters."
  - **PLT:** A — "A handler is a runtime value. Each operation in it has one monotype, not a type scheme. A `[T]` on an operation would need a polymorphic handler clause, and v1 has no typing rule for it (no bound environment, no instantiation at the handler). Allowing it on operations only (B) leaves effects non-generic but still forces that rule. Allowing it on effects only (C) makes an effect a type constructor, and the effect row rules in §4.15 do not say how rows treat it. A refuses both and costs no program, since no program uses either today." Concern: "If v2 allows `[T]` on operations, the typing rule of the handler clause must be defined then, and a refusal in v1 hides how many users need it."
  - **DevOps:** A — "One rule with no exceptions gives one diagnostic and one LSP behavior: no generic clause to infer in a handler, and no clause-mismatch error that must explain type parameters. The parser can accept `[...]` and report a named error at the right span instead of `expected (, got [`." Concern: "Users who write generic stores meet the error often, and the wrapper-function fix only works if the help shows it clearly."
  - **AI/ML:** A — "One rule with no exceptions is the cheapest for a model to learn from the spec alone. It adds no grammar and no decision point (no choice of where to write `[T]`, no repeat of `[T]` on the handler clause). The wrapper pattern is already in the spec (04_effects.md:274), so a model sees one pattern in two places." Concern: "A model trained on Koka or on Haskell polymorphic methods may still write `fn put[T]` on first try, so the error must be clear and its help must name the fix."
  - **Minimalism:** A — "Option 1 adds one diagnostic and one grammar sentence, and nothing else. Nobody has shown a user who needs a generic operation. 04_effects.md:274 already says the generic surface is a stdlib wrapper. 2a needs generic handler clauses, bounds and an unshown lowering. 2b adds a feature with no user and reopens the v2 effect-variable design." Concern: "Users who want a generic operation write a wrapper per type, and the demand may come later; but a later version can relax the rule without breaking a program."

- **Q2: a "why" note in the golden diagnostic** (5-1, A; Minimalism dissent)
  - **Systems:** A — "A user who hits a hard rule needs the reason at the error site. One line in language terms, with no lowering words, costs nothing in the spec." Concern: "If the note wording drifts from the real reason, it will teach users a wrong model of handlers."
  - **Web/Scripting:** A — "A user who hits the error asks "why not?" first. One short note in user terms answers that and saves a search. It must use no lowering words." Concern: "If the note text is vague, it reads as a bare "because we said so" and adds noise to every golden block."
  - **PLT:** A — "A user who knows ML or Koka reads the rule as arbitrary without a reason. One note line in language terms gives the typing fact and needs no lowering detail." Concern: "A note in the golden block fixes its wording in tests, so a later change to the rule forces a golden edit."
  - **DevOps:** A — "A bare "not allowed" gives the user nothing to act on. One note line in language terms costs one line in the golden block and answers the "why" at the point of the error. The ERROR_CATALOG row and `--explain` can carry the long reason." Concern: "A note that drifts from the real reason (lowering) misleads, and golden text is costly to change."
  - **AI/ML:** A — "A model that gets an error with no reason tends to retry with variations. One note line in user terms stops that. The golden block is the text a model copies, so it must hold no lowering words." Concern: "A note that is too long or too abstract adds tokens and teaches nothing."
  - **Minimalism:** B *(dissent)* — "The error line states the rule and the help gives the fix. The reason adds a second thing to keep in step with the compiler. It belongs in the ERROR_CATALOG row or the `--explain` text." Concern: "A user who sees no reason may think the rule is arbitrary and file a ticket."

- **Q3: the note text** (Phase C: A 1, B 1, C 1, D 2, E 1; no majority, so Phase D)
  - **Systems:** A — "\"a handler provides each operation of an effect with one fixed signature\" states the rule in language terms. It says nothing about vtables, slots or runtime layout, so it keeps the no-lowering rule. B and C name the runtime value, which leaks the implementation into sections/." Concern: "\"fixed signature\" may read as \"concrete types only\" to some users, and they may not see why a bounded `T` is also refused."
  - **Web/Scripting:** D — "\"an operation has one fixed type\" is the shortest and uses only words a user already knows. The other texts bring in \"handler\" and \"runtime value\", which a new user has to learn first. It states the rule without describing the implementation." Concern: "\"fixed type\" is short enough that a user may not link it to the handler, so the reason stays unclear to some."
  - **PLT:** B — "\"a handler is a runtime value with one fixed signature per operation\" states the typing fact: each operation has one type, not a scheme. It says why a handler cannot be polymorphic per operation. It uses no word about vtable, slot or boxing. A and D are close, but A hides \"runtime value\", the premise that gives the reason; D states the rule again and gives no reason." Concern: "\"runtime value\" may read as lowering detail to a reviewer who applies the no-implementation rule strictly."
  - **DevOps:** C — "\"a handler is a runtime value. Its operations are fixed entries, so each has one type\" names the cause (handler is a value) and the effect (one type per operation) in user terms, with no lowering words. It reads as two short sentences, which suits a note line. Options D and E state the rule again and do not say why." Concern: "\"fixed entries\" is close to an implementation word; if review finds it so, B is the fallback."
  - **AI/ML:** E — "\"an effect operation has concrete types\" is the shortest text and states the rule in language terms. It has no \"runtime value\" or \"slot\" idea that a model must interpret. D is close, but \"one fixed type\" can read as \"one type per program\"." Concern: "\"concrete\" is a word of art, and a user may not know that `List[Str]` counts as concrete."
  - **Minimalism:** D — "It is the shortest and uses user terms only. It has no lowering words and no claim about handlers as runtime values." Concern: "\"one fixed type\" can read as \"all operations share one type\"."

- **Q4: the help lines** (5-1, A; DevOps dissent)
  - **Systems:** A — "One help with both fixes uses fewer lines and keeps the golden block short. The concrete form comes first in the sentence, so a user who reads only that part still gets a working program." Concern: "A long single help line can be hard to read in a terminal, and users may miss the wrapper half."
  - **Web/Scripting:** A — "One help with both parts gives a single fix block to copy. Two helps make the user decide which to read and make the golden output longer. The concrete-type form and the wrapper form fit in one short example." Concern: "A user who reads only the first half of one long help line may miss the wrapper form."
  - **PLT:** A — "The two fixes are parts of one answer: concrete types in the operation, generic code in a wrapper that calls it. One help keeps the diagnostic short and keeps the pair together." Concern: "A user who reads only the first half of a long help line may miss the wrapper form."
  - **DevOps:** B *(dissent)* — "Two helps let a user who reads only the first get a working program (concrete types). The second help shows the wrapper for users who need genericity. Each help line is one action, which is how our other diagnostics work." Concern: "Two help lines make the golden block longer, and tools that show only the first help hide the wrapper."
  - **AI/ML:** A — "One help with both parts costs fewer tokens and shows the two-step fix in order. A model reads one block and copies it. Two helps add a point where a model may stop after the first." Concern: "A reader who stops at the first half gets a program that compiles but does not do what they meant."
  - **Minimalism:** A — "One help line costs the least surface and fewer golden lines to keep. Both parts fit in one sentence. The wrapper part is a hint, so one line is enough." Concern: "A user who reads only part of a long help line may miss the wrapper advice."

- **Q5: what sections/ says about a later version** (3-3, A against B; no majority, so Phase D)
  - **Systems:** B — "The spec text should say only \"not allowed in v1\". A promise in sections/ about a later version commits the panel to a lowering it has not designed. DECISIONS.md records the deferral and the design constraint (erased or specialized, static dispatch path)." Concern: "Without a sentence in sections/, readers may take the rule as permanent and build workarounds that a later version would make needless."
  - **Web/Scripting:** A — "One sentence tells users the limit is a v1 limit, not a design rule, so they do not build workarounds as permanent patterns. It names no lowering. It costs one line." Concern: "The sentence promises nothing firm, and a user may read \"may allow\" as \"will allow\" and wait for it."
  - **PLT:** A — "One sentence tells the user the rule is a v1 limit and not a soundness law, and it does not promise a schedule or a form. The spec says what a later version may do, as it does for other v1 limits." Concern: "The sentence is a promise readers can cite; if the panel later rejects the feature, the sentence must be removed."
  - **DevOps:** B — "The spec text should state the v1 rule only. A sentence about a later version promises a feature the panel has not agreed to, and the code name `EffectOpTypeParams` already avoids the promise. DECISIONS.md records the deferral." Concern: "Without a spec sentence, a reader may think the rule is permanent and file duplicate tickets."
  - **AI/ML:** A — "One sentence tells a model that the rule is a v1 limit and not a design principle, so it does not build habits on it. It costs few tokens. A relax-later change then does not contradict the text." Concern: "The sentence may read as a promise, and users may ask when it ships."
  - **Minimalism:** B — "A spec sentence about a later version is a promise, not a rule. DECISIONS.md already records deferrals, as at :182. The spec says what v1 does." Concern: "With no sentence in the spec, a reader may not learn that the rule is open to change."

#### Phase D — Round 2 (Q3 and Q5)

Q1 (6-0), Q2 (5-1) and Q4 (5-1) were decided in Phase C and not reopened. Q3 (1-1-1-2-1) and Q5 (3-3) had no majority and got one focused round (D1), then a silent re-vote (D2). The D1 digest gave the panel the Phase C votes verbatim and these repo facts:

- sections/04_effects.md:2084 "Handlers are first-class values. They can be stored in variables, passed as arguments, and returned from functions." and :2329 "Handlers are full first-class values." The words "runtime value" do not occur in sections/ for handlers.
- sections/ text that names a later version for a v1 limit: 02_syntax.md:708 ("No `if let` for v1 ... Revisitable in v2 if ..."), 02_syntax.md:825 (break-with-value, same form), 04_effects.md:3158 ("Rule 1 does not depend on depth, so it stays true if a later version lifts the limit."), 04_effects.md:2626 ("Effect-kinded generic parameters ... are deferred to v2, alongside named effect variables."), and §4.15.5 "What Is Deferred to v2".
- sections/ text that states a v1 limit with no later-version wording: 02_syntax.md:754 "No comprehensions in v1 — `for` loops and method chaining ... cover the same use cases."

Notes on reading. The Phase D voters were told to read every seat's file, in order: the brief, the Phase C ballot, all six Phase C files, the D1 digest, all six D1 files. The brief records that in Phase D2 the Minimalism seat did not open the Phase C files or the brief in full (the D1 digest quotes Phase C) and did not read the cited repo files. This stands next to the Phase C reading note above.

##### Phase D1 — Focused debate (Q3 and Q5)

###### Systems

> ## sys, Phase D round 1 (Q3 and Q5)
>
> **Q3. Vote stays A, with B as second choice.**
> The fact that sections/ never says "runtime value" for handlers, only "first-class values" (04_effects.md:2084, :2329), weakens my objection to B. "Runtime value" is not a lowering word: it says the handler exists at run time, and it says nothing about a vtable, a slot or a layout. I now accept B as a text that keeps the no-lowering rule. I still prefer A, because it needs no term the spec does not use, and it states the rule at the place it applies: the handler gives each operation one signature. I oppose C. "Fixed entries" is an implementation word, and devops names it as the risk. I oppose D and E. D can read as "all operations share one type" (min's own concern). E uses "concrete", which needs a definition. If A and B split the vote, I move to B.
>
> **Q5. Vote stays B.**
> Sections/ is mixed on this: 02_syntax.md:754 gives a v1 limit with no later-version wording, and 02_syntax.md:708 gives one with it. So no spec convention decides the question. The sentence "A later version may allow type parameters on an operation" says "may". It promises nothing, but readers cite it as a promise (web's and plt's own concerns say so). It also pre-commits the panel on a feature that has no lowering. The rule stays open to change with or without the sentence, because every such program is an error today. DECISIONS.md and the ERROR_CATALOG row can hold the deferral and carry the "v1" word. The error code name `EffectOpTypeParams` and the phrase "not allowed in v1" already tell the reader that the rule is a v1 limit. That answers plt's soundness-law concern and web's workaround concern at no cost to the spec.
>
> STATUS: ready to vote

###### Web/Scripting

> # web — Phase D1 (Q3, Q5)
>
> ## Q3. Change from C: D to A
> min and aiml both show that D is ambiguous. "One fixed type" can read as "all operations share one type" (min) or "one type per program" (aiml). That is a real reading error for a new user, and it defeats the note's job. I now rank A first.
>
> A says "a handler provides each operation of an effect with one fixed signature". "Handler" is a word the user already has: the spec calls handlers first-class values (04_effects.md:2084), and the user writes one to use an effect. A gives the reason without "runtime value" (plt B, devops C) and without "slot" or "vtable". It also fixes my own D concern: it links the rule to the handler. I reject B and C because "runtime value" does not occur for handlers in sections/, so it adds a new term. I reject E because "concrete" is a word of art (aiml's own concern). If A loses, I vote D over E, B and C.
>
> ## Q5. Keep A
> sys and min say a spec sentence is a promise. The repo shows the spec already does this for v1 limits: 02_syntax.md:708 ("Revisitable in v2"), 04_effects.md:2626 ("deferred to v2"), and §4.15.5. "May allow" is not a promise; it is weaker than those. Without it, a user takes the rule as permanent and builds permanent workarounds, which is the cost devops and sys name in their own Concerns. The wording gives no lowering and no schedule. If the panel later rejects the feature, we remove one line.
>
> STATUS: ready to vote

###### PLT

> # plt, Phase D1 (Q3 and Q5)
>
> **Q3.** I keep B in substance and offer one wording change that answers sys.
> sys says "runtime value" leaks the implementation. The repo fact in D1 shows the point has force: sections/ never says "runtime value" for handlers, but it says "first-class value" at 04_effects.md:2084 and :2329. First-class is a typing term, not a lowering term. It carries the premise I need: a value has one type, and a value's fields cannot each be a type scheme. So I move to B':
>
> "a handler is a first-class value with one fixed signature per operation"
>
> B' uses the spec's own words, names no vtable or slot, and gives the reason. If B' is not on the ballot, my second choice is A (sys), then C. I vote against D and E: they restate the rule and give no reason, which is what Q2 A voted to add. E also has the "concrete" problem aiml states.
>
> **Q5.** I keep A. sys and min say a sentence is a promise. The text says "may", and the repo already does this: 02_syntax.md:708, 02_syntax.md:825, 04_effects.md:2626, 04_effects.md:3158 and §4.15.5 all name a later version for a v1 limit. The one counter-example (02_syntax.md:754) states a limit that has a stated substitute and no known demand. Here the "why" note says the limit comes from handler values, so a reader may take it as a law of the language. One sentence says it is not. sys's worry about committing to a lowering does not apply: the sentence names no lowering. If the panel rejects the feature later, it removes the sentence, as it would amend any spec line.
>
> STATUS: ready to vote

###### DevOps

> # Phase D1 — devops
>
> **Q3. Change: C to B, with one word swapped.**
> I drop C. My own Concern named "fixed entries" as close to an implementation word, and sys is right that it leaks layout. The repo fact settles the other half: "runtime value" does not occur in sections/ for handlers, but "first-class value" does (04_effects.md:2084, :2329). A note should use the words the spec already teaches. I vote for plt's B with that swap: "a handler is a first-class value with one fixed signature per operation". It keeps the cause (handler is a value) that D and E lack, and it uses no lowering word. If the panel wants B verbatim, I accept B. I oppose D and E: they restate the rule and give no reason, which was the point of Q2 A. sys's A is my second choice; it gives a reason, but the premise "handler" is only implied.
>
> **Q5. Change: B to A.**
> The repo shows sections/ already states later-version limits in one sentence: 02_syntax.md:708, 04_effects.md:2626, 3158. A user who sees an error and finds no such sentence cannot tell a v1 limit from a design rule, and files a duplicate ticket. That was my own Concern on B. "A later version may allow ..." says "may", not "will", so it commits the panel to no lowering and no date. sys's worry is the design constraint (erased or specialized, static dispatch), and that stays in the decision file; the sentence names none. If the panel later rejects the feature, we edit one line. That cost is smaller than the cost of readers who build permanent workarounds.
>
> STATUS: ready to vote

###### AI/ML

> # aiml, Phase D1 (Q3 and Q5)
>
> **Q3. I hold E.** "an effect operation has concrete types" is the shortest text. A model can act on it: the fix is to write concrete types. I answer my own concern about "concrete": the help line shows `List[Str]` in the example, so a user sees that an instantiated type counts. I oppose B and C. The words "runtime value" do not occur for handlers in sections/ (the facts say so); sections/ says "first-class value". B and C add a term that a model must link to the lowering. "Fixed entries" in C is an implementation word, as devops admits. I oppose D: "one fixed type" can read as "one type per program". If E does not win, my second choice is A, because it has no lowering words and gives a reason ("each operation has one fixed signature"). My third choice is D.
>
> **Q5. I hold A.** sys says a sentence commits the panel. It does not. "May allow" promises no schedule and no form, and sections/ already uses this form for v1 limits (02_syntax.md:708, 04_effects.md:2626, §4.15.5). Q5 B is the odd form out, like 02_syntax.md:754. For a model, the sentence is the signal that the rule is a v1 limit. Without it a model may copy workarounds as a pattern, or tell users the limit is permanent. plt's concern (the panel later rejects the feature) is small: the decision file records the retirement rule, so removing one sentence is a known step.
>
> No change from Phase C.
>
> STATUS: ready to vote

###### Minimalism

> ## min, Phase D round 1 (Q3 and Q5)
>
> **Q3.** I keep D: "an operation has one fixed type". Q2 A won, so a note exists. The note should cost the least and carry no word a user must learn first. D is the shortest text that has no lowering word.
>
> I answer plt and devops. B and C say "runtime value". That phrase does not occur in sections/ for handlers (04_effects.md:2084 and :2329 say "first-class values"). A note that uses a term the spec never defines teaches a new term inside an error. C also has "fixed entries", which devops calls close to an implementation word.
>
> I accept aiml's point that E is weaker: "concrete" is a word of art. My concern on D (that it reads as "all operations share one type") is small, because the error line above it names the operation. If D loses, my second choice is A: it keeps "handler" and "signature", terms the spec defines, and has no lowering word.
>
> **Q5.** I keep B: the spec says only the v1 rule. The repo has no single practice. 02_syntax.md:754 states a v1 limit with no later-version text. The other cases (02_syntax.md:708, 04_effects.md:2626) name a later version, but each was a vote on that limit. Here the panel has not voted on a later version, and sys says a lowering is not designed.
>
> plt's concern shows the cost: if the panel later rejects the feature, we must remove the sentence. DECISIONS.md carries the deferral, and the help and ERROR_CATALOG row are where a user looks.
>
> No change from my Phase C vote.
>
> STATUS: ready to vote

##### Phase D2 — Silent re-vote (Q3 and Q5)

The Q3 ballot after D1: A "a handler provides each operation of an effect with one fixed signature"; B "a handler is a runtime value with one fixed signature per operation"; B' "a handler is a first-class value with one fixed signature per operation" (PLT and DevOps moved to it in D1); D "an operation has one fixed type"; E "an effect operation has concrete types". C was withdrawn. The Q5 ballot was unchanged: A the one sentence, B nothing beyond the v1 rule.

- **Q3: the note text** (4-2, A; PLT and DevOps dissent for B')
  - **Systems:** A — "\"a handler provides each operation of an effect with one fixed signature\" states the rule where it applies and uses only terms the spec already defines. It carries no lowering word. B' is acceptable, but A is the second choice of aiml, min and plt, so it is the text most seats can live with. D reads as \"all operations share one type\" and E needs a definition of \"concrete\"." Concern: "\"fixed signature\" may read as \"concrete types only\", so a user may not see why a bounded `T` is also refused."
  - **Web/Scripting:** A — "\"a handler provides each operation of an effect with one fixed signature\" uses only words the user already has: \"handler\" and \"signature\". It ties the rule to the handler, so the user sees why, which D and E do not. D can read as \"all operations share one type\" and E needs \"concrete\" explained. B and B' are sound, but they add a premise (\"runtime value\" or \"first-class value\") that a new user must read as a typing fact. A gives the same reason in fewer ideas." Concern: "\"fixed signature\" may read as \"concrete types only\", and a user with a bounded `T` may not see why it is refused too."
  - **PLT:** B' *(dissent)* — "\"a handler is a first-class value with one fixed signature per operation\" gives the typing reason: a value has one type, and its fields cannot each be a type scheme. \"First-class value\" is the spec's own term (04_effects.md:2084, :2329), and the text names no vtable, slot or layout, so it keeps the no-lowering rule. sys accepts the B form as compatible with that rule. If B' loses, A is my second choice." Concern: "If A wins, the premise that makes the rule necessary (the handler is a value) stays implied, and a reader may take the limit as arbitrary."
  - **DevOps:** B' *(dissent)* — "The note must answer \"why\" at the error site, and B' does: the handler is a first-class value, so each operation has one fixed signature. \"First-class value\" is the spec's own wording (04_effects.md:2084, :2329), so the error teaches no new term and has no lowering word. D and E restate the rule and give no cause. A is close and my second choice, but it leaves the premise (a handler is a value) implied." Concern: "If B' and A split the vote, either text is acceptable to me, but a note that drops the \"value\" premise may leave users unsure why a bounded `T` is also refused."
  - **AI/ML:** A — "I voted E in Phase C and D1. D1 showed that \"concrete\" is a word of art, and that D and E both state the rule again and give no reason. A has no lowering word, uses terms the spec defines (\"handler\", \"signature\"), and links the rule to the place where a user writes the fix. A model can act on it: give each operation one signature, then wrap it in a generic function. A has the most support as a second choice (sys, web, min, aiml), so I move to it." Concern: "\"fixed signature\" does not tell a model that `List[Str]` is allowed, so the help line must show an instantiated type in its example."
  - **Minimalism:** A — "D is short, but three seats showed it reads as \"all operations share one type\" or \"one type per program\". A note that a user can misread fails its one job. A uses only terms the spec already defines (\"handler\", \"operation\", \"signature\"), names the handler as the cause, and has no lowering word. B and B' add \"runtime value\" or \"first-class value\" for no gain in meaning, so A is the smaller text that still gives the reason." Concern: "If B' wins, \"first-class value\" invites a reader to ask why a first-class value cannot hold a polymorphic operation, and the note then raises a question it does not answer."

- **Q5: what sections/ says about a later version** (4-2, A; Systems and Minimalism dissent)
  - **Systems:** B *(dissent)* — "The sections/ precedent is mixed (02_syntax.md:754 has no later-version wording; :708 has it), so no convention decides this. A sentence that says \"may allow\" is read as a promise, and it pre-commits the panel to a feature that has no designed lowering. The name `EffectOpTypeParams` and the words \"not allowed in v1\" already mark the rule as a v1 limit, and DECISIONS.md records the deferral and its design constraint." Concern: "Without a sentence in sections/, a reader may take the rule as permanent and build workarounds that a later version would make needless."
  - **Web/Scripting:** A — "One sentence, \"A later version may allow type parameters on an operation.\", tells a JS or Python dev that the rule is a v1 limit and not a law of the language. sections/ already says this for other v1 limits (02_syntax.md:708, 04_effects.md:2626, §4.15.5). \"May\" promises no form and no date. Without the sentence, users build permanent workarounds and file duplicate tickets." Concern: "A user may read \"may allow\" as \"will allow\" and wait for it, and the sentence must go if the panel later rejects the feature."
  - **PLT:** A — "The \"why\" note ties the limit to handler values, so a reader may take it as a law of the language. One \"may allow\" sentence says it is a v1 limit. sections/ does this for other v1 limits (02_syntax.md:708, :825; 04_effects.md:2626, :3158), and \"may\" promises no lowering and no date." Concern: "If B wins, a reader who sees the note and no later-version sentence may think the rule is permanent and file duplicate tickets."
  - **DevOps:** A — "sections/ already states later-version limits in one sentence (02_syntax.md:708, 04_effects.md:2626, :3158). A user who hits the error and finds no such sentence cannot tell a v1 limit from a design rule, and files duplicate tickets or builds permanent workarounds. \"May allow\" promises no date, no form and no lowering. Removing one line is cheap if the panel later rejects the feature." Concern: "Readers may cite the sentence as a promise, and the golden docs and the sentence must be edited together when the rule changes."
  - **AI/ML:** A — "For a model, the sentence is the signal that the rule is a v1 limit and not a law of the language. Without it, a model may copy the wrapper workaround as a permanent pattern, or tell a user the limit is permanent. sections/ already uses this form for v1 limits (02_syntax.md:708, 04_effects.md:2626, 3158, section 4.15.5), and \"may\" promises no schedule and no lowering." Concern: "If the panel later rejects the feature, the sentence stays in the spec and misleads readers until someone removes it."
  - **Minimalism:** B *(dissent)* — "A sentence about a later version is a promise in the spec, and the panel has not voted on that feature or designed its lowering. The error code `EffectOpTypeParams`, the words \"not allowed in v1\" in the error line, DECISIONS.md and the ERROR_CATALOG row already tell a reader this is a v1 limit. Spec text should state rules, not forecasts." Concern: "Without the sentence, a reader may take the rule as permanent and file a duplicate ticket or build a workaround a later version would make needless."

### Final Spec

```blink
// error: an effect operation takes no type parameters (EffectOpTypeParams, E0558)
effect Store {
    effect Put {
        fn put[T](x: T) -> T
    }
}

// error: an effect takes no type parameters
effect Cell[T] {
    fn set(x: T)
}

// repair: a concrete operation and a generic function that calls it
effect Store {
    effect Put {
        fn put(x: Str) -> Str
    }
}

fn put_any[T: Display](x: T) -> Str ! Store.Put {
    store.put(x.display())
}
```

```
error[EffectOpTypeParams]: effect operation `Store.Put.put` declares type parameters
 --> store.bl:3:15
  |
3 |         fn put[T](x: T) -> T
  |               ^^^ type parameters are not allowed in v1
  |
  = note: a handler provides each operation of an effect with one fixed signature
  = help: declare the operation with concrete types (an instantiated type such as `List[Str]` is concrete), and write a generic function that calls it: `fn put_any[T: Display](x: T) -> Str ! Store.Put { store.put(x.display()) }`
```

Locked design points:

- An effect operation, primitive or derived, takes no type parameters. An effect takes no type parameters. One code, `EffectOpTypeParams` (E0558), covers both shapes. The parser reads the `[...]` and reports the code, not `expected (, got [`.
- The golden block has one `note:` with the exact Q3 text and one `help:` with both repairs (Q4). sections/ holds no lowering word.
- The help example and the spec example use `T: Display` and `x.display()`, as sections/04_effects.md:274 does for `io.println`. The help shows `List[Str]` as a concrete type.
- sections/ adds one sentence about a later version (Q5): "A later version may allow type parameters on an operation."
- The rule is its own deferral, independent of the `Handler[E]` deferral in DECISIONS.md ("Handler generic parameters"). The spec cross-references the two and ties neither to the other.
- A derived operation body may call a generic function, and an operation may use an instantiated type in its signature.
- A later version can relax the rule without breaking a program, because every such program is an error today. It needs a defined lowering first (erased or specialized); the lowering is open. Systems named static dispatch as a design constraint for that lowering. It is a design note and not a rule. When a later version allows the syntax, the code E0558 is retired and not reused.
