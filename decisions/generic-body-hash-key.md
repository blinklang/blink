[< All Decisions](../DECISIONS.md)

# A Type Parameter as a Map Key or Set Element — Design Rationale

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated
in independent-proposal → debate → vote rounds. Ticket IDs in the quoted text are replaced with `[ticket]`.

#### Phase A — Independent proposals

- **Systems:** (excerpt, section `G5 ([ticket]) Where a Map/Set key role of a type parameter is judged`)

> Fact: `fn uniq[T](xs: List[T]) -> Int { let mut s = Set.new() ... s.insert(x) }` with no bound
> compiles and runs today (prints 2 for `[1, 2, 2]`). That is template behavior: the body is
> judged per instance.
>
> What the hardware sees: a hash container needs a `hash` and an `eq` for its key. A monomorphizer
> can always find them per instance, but only a written bound lets the checker prove the body once
> and lets a call through `X: Tr` (where the instance is chosen by an impl the caller never sees) be
> safe without whole-program impl search. The ticket's case (trait method hides the key role) is a
> check-clean build ICE today, exactly what "judge per call" cannot see.
>
> **G5-P1 (preferred): option A, judge at the declaration.** The key parameter of `Map` and the
> element parameter of `Set` are bound `Hash` (which implies `Eq`, `trait Hash: Eq`). A generic body
> that makes `T` a key, written (`Set[T]`) or inferred (`Set.new()` then `s.insert(x)` with
> `x: T`), with no written `T: Hash` is E1400 MapKeyNotHashable at that site in the body, in
> `blink check`, whether or not anything calls it. Help: machine-applicable `: Hash` on the binder.
> This is the existing *Bounds on a Type Declaration* rule (03_types.md:7260) and *No implied
> bounds* applied to `Map`/`Set`; it keeps E1400 as the code because the message is about keys.
>
> ```blink
> fn uniq[T](xs: List[T]) -> Int {
>     let mut s = Set.new()
>     for x in xs { s.insert(x) }                // error[MapKeyNotHashable] (E1400) at `x`: add `T: Hash`
>     s.len()
> }
>
> fn uniq2[T: Hash](xs: List[T]) -> Int {        // OK
>     let mut s = Set.new()
>     for x in xs { s.insert(x) }
>     s.len()
> }
>
> trait Tr { fn m[U](self, u: U) -> Int }
> type Foo { a: Int }
> impl Tr for Foo {
>     fn m[U](self, u: U) -> Int {
>         let mut s = Set.new()
>         s.insert(u)                            // E1400 at `u`; the fix is `fn m[U: Hash]` in the trait and impl
>         s.len()
>     }
> }
> ```
>
> The hidden-role case then cannot exist: the impl body fails on its own, and the bound must appear
> in the trait signature, which every caller through `X: Tr` sees. Calls with a non-Hash argument
> get E0306/E1400 at the call, as for any bound.
>
> Tradeoff: breaking for code that compiles today (pre-1.0, settled). It is the same direction as
> the open P0 bounds-are-proofs work; P2 would add a second whole-program pass that the P0 work is
> removing.
>
> **G5-P2: option B, judge per call and chase impls through bounds.** Rejected: whole-program,
> non-local errors (an error at `outer(Foo)` caused by an impl body two files away), and it keeps
> template behavior that the P0 work is deleting.
>
> **G5-P3: option C.** Half of P1: fixes impls, leaves fns per-call. Two rules for one fact.
>
> Cross-language: Rust `HashSet<T>::insert` needs `T: Hash + Eq` on the fn; C++ templates judge per
> instance and give the error far from the cause. We chose Rust's side with *No implied bounds*.
>
> ---

- **Web/Scripting:** (excerpt, section `G5 ([ticket]): where a Map/Set key role of an unbounded type parameter is judged`)

> ### G5-P1 (PREFERRED, option A): judge at the declaration; `U: Hash` must be written
>
> - A generic body (fn, impl method, trait default) that uses a type parameter with no `Hash`
>   bound as a `Map` key or `Set` element is E1400 at that use in the body, in `blink check`,
>   whether or not any call exists. Help (machine-applicable): add `: Hash` to the binder.
> - An impl method whose own type parameter needs `Hash` cannot add it alone (that demands more
>   than the trait); the help says to add it to the trait method.
>
> ```blink
> fn uniq[T](xs: List[T]) -> Int {
>     let mut s = Set()
>     for x in xs { s.insert(x) }        // error[E1400]: `T` has no `Hash` bound; help: write `T: Hash`
>     s.len()
> }
>
> fn uniq2[T: Hash](xs: List[T]) -> Int {   // OK
>     let mut s = Set()
>     for x in xs { s.insert(x) }
>     s.len()
> }
>
> trait Tr { fn m[U: Hash](self, u: U) -> Int }
> impl Tr for Foo {
>     fn m[U: Hash](self, u: U) -> Int {
>         let mut s = Set()
>         s.insert(u)
>         s.len()
>     }
> }
> fn outer[X: Tr](x: X) -> Int { x.m(Pt { x: 1 }) }   // error[E1400] at `Pt { x: 1 }`: `Pt` has no `Hash`
> ```
>
> Tradeoffs: this is how TypeScript, Kotlin, Java, Rust and Go generics behave: the generic body
> says what it needs, and the error names the line the author wrote. Option B is C++ template
> errors: the user calls `outer(Foo { a: 1 })` and gets an error about a Set in an impl they may
> never have read. That is the most-asked category of C++ question. A also matches the repo's P0
> direction ("a generic body may use T only through its written bounds") and No implied bounds.
> Cost: breaks code that compiles today; one `: Hash` fixes it, and the help writes it.
>
> ### G5-P2 (option C): call-site for fns, E0912-style error at an impl that exceeds its trait
>
> Half the rule at one site, half at another; a user has to learn both. Rejected.
>
> ### G5-P3 (option B): carry the role across trait-bound calls
>
> Keeps today's code compiling but builds an instance-time error system that the P0 work is
> removing. Rejected.
>
> ---

- **PLT:** (excerpt, section `G5. Where a Map/Set key role of an unbounded type parameter is judged`)

> This is the parametricity rule (03_types.md, *Parametricity (normative)* and *No implied bounds*):
> "the only legal way for a polymorphic body to vary behavior based on T is a trait bound". Hashing
> a T is behavior that varies with T. `Set[T]` requires `T: Hash` (03_types.md:6643). So a body
> that makes an unbounded T a key uses a capability it was not given. Judged per call, it is
> template semantics: the type of `outer` then depends on the bodies of every impl that `X: Tr` can
> pick, which no caller can see. That is non-modular, and with any future dynamic dispatch it can
> not be judged at all.
>
> ### G5-P1 (preferred): option A, judge at the declaration
>
> - A generic body (fn, impl method, trait default body) in which a Map key type or a Set element
>   type is, or contains, a type parameter with no `Hash` bound: E1400 MapKeyNotHashable at the
>   body, at the expression that fixes the key type to that parameter. Command: check.
> - The same for a written type in a signature (`fn f[K](m: Map[K, Int])`), which is the
>   bound-on-a-type rule (E0306 shape) with the E1400 code.
> - The help is the binder edit: insert `: Hash` (machine-applicable; `Hash: Eq`, so one bound
>   suffices).
> - A call is then judged only against written bounds (E0306 at the call when `Pt` is not `Hash`).
>
> ```blink
> fn count[T](xs: List[T]) -> Int {
>     let mut s = Set()
>     for x in xs { s.insert(x) }              // error[E1400]: `T` has no `Hash` bound; write `T: Hash`
>     s.len()
> }
>
> fn count2[T: Hash](xs: List[T]) -> Int {    // OK
>     let mut s = Set()
>     for x in xs { s.insert(x) }
>     s.len()
> }
>
> trait Tr { fn m[U](self, u: U) -> Int }
> type Foo { a: Int }
> impl Tr for Foo {
>     fn m[U](self, u: U) -> Int {
>         let mut s = Set()
>         s.insert(u)                          // error[E1400] at the impl: `U` has no `Hash` bound
>         s.len()
>     }
> }
> // the fix is in the trait: `trait Tr { fn m[U: Hash](self, u: U) -> Int }`;
> // then `x.m(Pt { x: 1 })` with no Hash on Pt is E0306 at the call in `outer`.
> ```
>
> Tradeoffs: the judgment uses the declaration and its written bounds only; a check of a module
> never depends on a body in another module. It is the same direction as the open P0 generics work.
> The cost: code that compiles today breaks (a CHANGELOG line). That code had an unstated contract.
>
> ### G5-P2: option B, judge per call and follow trait-bound calls
>
> Rejected: to judge `outer(Foo)` the checker must find the impl that X picks and judge its body.
> The type of a call then depends on code that is not in any signature. It makes the
> "impl may not demand more than its trait" rule (E0912) false for hashing while true for
> contracts. It is the template behavior the P0 work removes.
>
> ### G5-P3: option C, per call for fns, error at the impl when it exceeds its trait
>
> Rejected: two rules for one property. A fn and an impl method differ only in how they are
> reached, and both are generic bodies under one parametricity rule. C also leaves `count[T]`
> unsound to call from another generic fn with an unbounded parameter.
>
> Cross-language: Rust, Haskell, OCaml functors: `HashSet<T>::insert` needs `T: Hash + Eq` written at
> the generic fn. C++ templates are option B, and their error messages are the known cost.
>
> ---

- **DevOps:** (excerpt, section `G5 ([ticket]) where a key role of an unbounded type parameter is judged`)

> **G5-P1 (preferred): option A, judge at the declaration. A generic body that uses `T` as a Map
> key or Set element needs `T: Hash` written on its binder; else E1400 in the body.**
>
> ```blink
> fn uniq[T](xs: List[T]) -> Int {
>     let mut s = Set()
>     for x in xs { s.insert(x) }        // error[E1400] at `x`: `T` has no `Hash` bound
>     s.len()
> }
> fn uniq_ok[T: Hash](xs: List[T]) -> Int { ... }    // OK
>
> trait Tr { fn m[U: Hash](self, u: U) -> Int }       // the key role is in the signature
> impl Tr for Foo {
>     fn m[U: Hash](self, u: U) -> Int {
>         let mut s = Set()
>         s.insert(u)
>         s.len()
>     }
> }
> fn outer[X: Tr](x: X) -> Int { x.m(Pt { x: 1 }) }   // error[E1400] at `Pt { x: 1 }`: Pt has no Hash
> ```
> ```
> error[E1400]: `T` is used as a `Set` element, and `T` has no `Hash` bound
>   --> uniq.bl:3:30
>   = help: add the bound: `fn uniq[T: Hash]`        (machine-applicable)
> ```
> In the impl with the trait's `fn m[U]`: E1400 at the body; adding `U: Hash` on the impl alone
> is then a signature mismatch with the trait, and the help says to put `: Hash` on the trait
> method.
>
> Tradeoffs (tooling): this is the only option where the error is next to the code that caused
> it, at edit time, with a one-token fix. B puts the error at a call, possibly in another package,
> on a type the caller did not choose, and needs the checker to walk impl choice through bounds
> (the same instance walk the P0 generic work is removing). C fixes the impl hole but keeps fns
> on per-call judging, so the LSP still reports at callers. A matches "no implied bounds" and
> the parametricity rule (03_types.md:7660): `Hash` is a trait; using it needs the bound.
> Breaking: yes; the fix-it makes the migration mechanical (`blink fix` adds the bounds).
>
> **G5-P2 (C).** A fallback if A is voted down: impl-site error for the trait-hidden case; still
> call-site for fns.
>
> Cross-language: Rust and Swift both require `T: Hash`/`T: Hashable` at the declaration. C++
> templates judge per instance and are known for errors far from the cause.
>
> ---

- **AI/ML:** (excerpt, section `G5: key role of an unbounded type parameter`)

> ### G5-P1 (PREFERRED): option A, judge at the declaration
>
> A body that makes an unbounded type parameter a `Map` key or a `Set` element, written or
> inferred, is an error at that site in the body, in check, with no call needed. Code: E1400
> MapKeyNotHashable with the type parameter named, and a machine-applicable help that inserts
> `: Hash` on the binder. This is already what 03_types.md:7233 says for a bound written on a type
> declaration ("checked at each place a program writes or infers the type"), and it is what
> parametricity (:7641, "the only legal way to vary behavior based on T is a bound") requires.
>
> ```blink
> fn uniq[T](xs: List[T]) -> Int {                // error[E1400] at `Set()`: `T` is a Set element with no `Hash` bound
>     let mut s = Set()
>     for x in xs { s.insert(x) }
>     s.len()
> }
> fn uniq2[T: Hash](xs: List[T]) -> Int { ... }   // OK
>
> trait Tr { fn m[U](self, u: U) -> Int }
> impl Tr for Foo {
>     fn m[U](self, u: U) -> Int {                // error[E1400] at the Set: `U` has no `Hash` bound
>         let mut s = Set()
>         s.insert(u)
>         s.len()
>     }
> }
> // Adding `U: Hash` here is more than the trait states (E0912 rule), so the fix goes in the trait:
> trait Tr2 { fn m[U: Hash](self, u: U) -> Int }
> fn outer[X: Tr2](x: X) -> Int { x.m(Pt { x: 1 }) }   // error[E1400] at the call: `Pt` has no Hash
> ```
>
> Tradeoffs (AI): the signature tells the whole contract. A model that writes a call reads only
> the signature, never the body; options B and C make the body part of the API, and a model cannot
> learn that from the spec or from a `blink query` signature. A is also the direction of the open
> P0 work, so the panel avoids a rule that will be undone. Token cost: `: Hash` once per binder.
> Errors land in the generic code, where the model is writing, not at a distant call.
>
> Breaking: code that keys an unbounded T compiles today. Pre-1.0; CHANGELOG line.
>
> Cross-language: Rust (`HashSet<T>` needs `T: Hash + Eq` in the fn bounds), Swift (`Hashable`),
> Haskell (`Ord k =>`) all judge at the declaration. C++ templates judge per call, and their error
> messages are the standard example of what not to do.
>
> ### G5-P2: option C (calls for fns, E0912 for impls)
>
> Two rules, by item kind. Fixes the trait case, but a free fn's body still leaks into its API.
>
> ---

- **Minimalism:** (excerpt, section `G5 ([ticket]) Where a Map/Set key role of a type parameter is judged`)

> ### G5-P1 (PREFERRED): option A, judge at the declaration
>
> A generic body that uses a type parameter as a `Map` key or `Set` element must write a `Hash`
> bound on it (`Hash: Eq`, so one bound). E1400 MapKeyNotHashable at the key site in the body,
> in check, once per declaration. Help: add `T: Hash` (machine-applicable). Calls are then judged
> only by the written bounds (E0306 at a call whose argument has no `Hash`).
>
> ```blink
> fn uniq[T](xs: List[T]) -> Int {
>     let mut s = Set()
>     for x in xs { s.insert(x) }    // error[MapKeyNotHashable] (E1400) at `x`: `T` has no `Hash` bound
>     s.len()
> }
> fn uniq2[T: Hash](xs: List[T]) -> Int {
>     let mut s = Set()
>     for x in xs { s.insert(x) }    // OK
>     s.len()
> }
>
> trait Tr { fn m[U: Hash](self, u: U) -> Int }    // the key role is now in the signature
> fn outer[X: Tr](x: X) -> Int { x.m(Pt { x: 1 }) } // E0306 at the call: `Pt` has no `Hash`
> ```
>
> Tradeoffs: this is not a new rule. It is "No implied bounds" and parametricity
> (03_types.md:7641, :7650) applied to `Hash`, and it is where the open P0 generics work
> ([ticket], [ticket], [ticket]) already goes. It deletes the per-call judgment and the open case
> both: the trait signature must state the key role, so a call through `X: Tr` sees it. B needs
> the compiler to find the impl through a bound at each call, which is template behavior; C adds
> a second E0912-like rule. Cost: breaks code that compiles today; pre-1.0.
>
> Cross-language: Rust (`K: Hash + Eq` on the fn), Haskell (`Ord k =>`), Go (`comparable`) all
> judge at the declaration. C++ templates judge per instance; that is the model we are leaving.
>
> ---

#### Phase B — Debate highlights

- **Systems:** (excerpt)

> G1, G5, G6: no objection.

- **Web/Scripting:** (excerpt)

> G1, G5, G6: no objection. I accept devops' note at the param's `mut` for G1.

- **PLT:** (excerpt)

> G1, G5, G6: no objection.

- **DevOps:** (excerpt)

> G1, G5, G6: no objection. Writer note for G1: error at the capture, note at the `mut` of the param.

- **AI/ML:** (excerpt)

> G1, G5, G6: no objection.

- **Minimalism:** (excerpt)

> G1, G5, G6: no objection.

#### Phase C — Final vote

- **G5-Q1: E1400 at the generic body** (6-0, option A; the other option was to reject)

- **Systems:**

> ## G5-Q1: A
> Reasoning: a hash container needs `hash` and `eq` for its key; only a written bound lets the checker prove the body once and makes a call through `X: Tr` safe without a whole-program impl search. It matches No implied bounds and the P0 bounds-are-proofs work.
> Concern: code that compiles today breaks; the machine-applicable `T: Hash` fix must also reach the trait method when the role is in an impl.

- **Web/Scripting:**

> ## G5-Q1: A
> Reasoning: this is how TS, Kotlin, Java, Rust and Go generics behave: the error is at the line the author wrote, not deep inside an instance. The fix is machine-applicable.
> Concern: breaks code that compiles today; the CHANGELOG line should show the one-token fix.

- **PLT:**

> ## G5-Q1: A
> Reasoning: parametricity says a generic body varies by T only through its written bounds, and hashing T is behavior that varies with T. Judging per call is template semantics: the type of a call would depend on impl bodies that no signature shows. It also cannot extend to dynamic dispatch, and it contradicts the E0912 rule ("an impl may not demand more than its trait").
> Concern: the break hits code that checks clean today. The CHANGELOG line and the machine-applicable `T: Hash` fix must ship together.

- **DevOps:**

> ## G5-Q1: A
> Reasoning: the error sits next to the code that caused it, at edit time, with a one-token machine-applicable fix. A call-site error reports far from the cause, maybe in another package. It also matches "no implied bounds" and the move off template behavior.
> Concern: a breaking change for generic code that compiles today; `blink fix` must apply the `: Hash` fix in bulk, including the move of the bound to the trait method.

- **AI/ML:**

> ## G5-Q1: A
> Reasoning: the signature states the whole contract, which is what a model reads (`blink query`) when it writes a call; a body that leaks into the API cannot be learned from the spec. It matches parametricity and the open P0 direction.
> Concern: breaking existing generic code; the machine-applicable `: Hash` fix must be right in the trait case (bound on the trait method, not the impl).

- **Minimalism:**

> ## G5-Q1: A
> Reasoning: this is "No implied bounds" and parametricity applied to `Hash`, not a new rule; it removes per-call judgment and the trait-crossing case together.
> Concern: breaks generic code that compiles today; the machine fix `T: Hash` must be reliable so the migration is cheap.

### Final Spec

```blink
fn count[T](xs: List[T]) -> Int {
    let mut s = Set.new()
    for x in xs { s.insert(x) }        // error[MapKeyNotHashable] (E1400) at `x`; help: add `T: Hash`
    s.len()
}

fn count_ok[T: Hash](xs: List[T]) -> Int {
    let mut s = Set.new()
    for x in xs { s.insert(x) }        // OK
    s.len()
}

trait Tr { fn m[U: Hash](self, u: U) -> Int }   // in a trait, the bound goes on the trait method
```

- A generic body that uses an unbounded type parameter as a `Map` key or `Set` element is E1400 `MapKeyNotHashable` at that site, in `blink check`.
- The help and the fix add `T: Hash`. The compiler adds no bound itself (No implied bounds).
- In a trait method the bound goes on the trait method, and the impl repeats it.
- A call with a type that has no `Hash` impl for a `T: Hash` parameter is the unmet-bound error (E0306).
- Spec text: §3.6 *A type parameter as a key or element*, E1400 in ERROR_CATALOG.md.
