[< All Decisions](../DECISIONS.md)

# A Map Key or Set Element in a Written Type — Design Rationale

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated
in independent-proposal → debate → vote rounds. Ticket IDs in the quoted text are replaced with `[ticket]`.

#### Phase A — Independent proposals

- **Systems:** (excerpt, section `G1 ([ticket]): unbounded parameter as a key in a written type`)

>
> **Facts today (gen1).**
> - A concrete non-hashable key in ANY written type is E1400 at the type: `fn f(m: Map[Float, Int])` (g1a), `type B { s: Set[Float] }` (g1b), `let m: Map[Float, Int]` (g1e). `Bag[Float]` with `type Bag[T] { s: Set[T] }` is E1400 at the use `let b: Bag[Float]` (g1f): the implied bound.
> - An unbounded parameter in a written type is accepted everywhere: signature, field, return type, alias `type M[K] = Map[K, Int]`, enum payload `A(Set[T])`, fn-type parameter `fn(Set[T]) -> Int` (g1c, g1d, g1g).
> - `fn f[U](s: S[U])` with `type S[T: Tr]` is also accepted today (r.bl), although §3.6 No implied bounds says E0306. So the compiler lags the spec in the same way for both.
>
> ### G1-P1 (preferred): `Map[K, _]` and `Set[K]` are well-formed only when `K: Hash` is known; checked at every written type
>
> One rule: `Map` and `Set` carry a `K: Hash` bound on the type, as `Range` carries `T: Ord` and `S[T: Tr]` carries `T: Tr`. Every written type is checked against the bounds in scope at the place it is written. A type parameter is `Hash` only when its binder says so. The code is E1400 (same code as the concrete case), at the type argument, in check, help "add `K: Hash`" on the binder that is in scope (fn, impl, type, alias, trait method).
>
> ```blink
> fn len_ok[K: Hash, V](m: Map[K, V]) -> Int { m.len() }      // OK
> fn len_bad[K, V](m: Map[K, V]) -> Int { m.len() }           // error[E1400] at `K`: add `K: Hash`
> fn mk[K]() -> Map[K, Int] { Map.new() }                      // error[E1400] at `K` (return type)
> fn h[T](f: fn(Set[T]) -> Int) -> Int { 0 }                   // error[E1400] at `T` (fn type)
> type Bag[T] { s: Set[T] }                                    // error[E1400] at `T` in the field
> type Bag2[T: Hash] { s: Set[T] }                             // OK
> type M[K] = Map[K, Int]                                      // error[E1400] at `K` in the alias
> type E[T] {
>     A(Set[T])                                                // error[E1400] at `T` (payload)
>     B
> }
> fn loc[T](x: T) -> Int {
>     let s: Set[T] = Set.new()                                // error[E1400] at `T` (local type)
>     s.len()
> }
> fn use_bag(b: Bag2[Float]) -> Int { 0 }                      // error[E0306]: `Float` has no `Hash`
> ```
>
> The `Bag[Float]` refusal moves from an inferred key role (tc_hash_oblig) to a written bound: E0306 at `Bag2[Float]`, the normal unmet-bound error.
>
> Tradeoffs (systems):
> - A `Map[K, V]` value with a non-hashable K cannot exist: no `Map.new()` can build one, and the concrete type `Map[Float, Int]` is already an error. A generic signature that may name a type the concrete program may not name is a hole between check and build. Mono instantiates one C body per K. With the rule, every emitted `Map[K, V]` instance has a hash fn for K by construction, so codegen needs no "is this K hashable" fallback or ICE path.
> - One rule for all type positions; the checker reads one binder, never a body or a field. Cheaper than the field-role inference, which must walk type definitions.
> - Cost: `map_len`, `set_len` and the other 13 std fns gain `K: Hash`. Implementation work only. The E0303 explain row `fn f[K, V](m: Map[K, V]) {}` changes to an error example.
>
> Cross-language: Swift rejects `func f<T>(_ s: Set<T>)` ("T does not conform to Hashable"): the bound is on the type. Rust puts no bound on `struct HashMap<K, V>` and checks only at `impl` methods; Haskell removed datatype contexts. Those keep the hole Blink's Promise forbids.
>
> ### G1-P2: body-only rule, as adopted; signatures and fields stay open, the field inference stays
>
> Keep today's behavior. Rejected by me: it keeps an implied bound (Bag's T) that §3.6 forbids, and a signature-only type with unbounded K stays legal while its concrete form is not.

- **Web/Scripting:** (excerpt, section `G1 — unbounded parameter as a key in a written type`)

>
> **Facts today (gen1).** A concrete non-hashable key in a written type is already E1400 at the type:
> `fn f(m: Map[Float, Int])` gives E1400 at `Float` in the signature, `type B { s: Set[Float] }` gives
> E1400 at the field, and `let s: Set[Box[Float]]` gives E1400 at the annotation. `type Bag[T] { s: Set[T] }`
> is accepted, and `let b: Bag[Float]` is E1400 at the annotation (the inferred bound). `fn g[K](m: Map[K, Int])`,
> `type M[K] = Map[K, Int]`, `fn r[T]() -> Set[T]` and `fn h[T](f: fn(Set[T]) -> Int)` are all accepted.
>
> ### G1-P1 (preferred): one rule — a key position in any written type needs a key type known to be `Hash`
>
> Wherever a programmer writes `Map[K, _]` or `Set[K]`, K must be hashable: a concrete hashable
> type, or a parameter whose binder carries `Hash`. Else E1400 MapKeyNotHashable at the key in the
> written type, in `blink check`, help/fix `K: Hash` on the binder. Same for every position: parameter,
> return type, local annotation, field, enum payload, alias, fn-type parameter, type argument.
>
> ```blink
> fn size[K, V](m: Map[K, V]) -> Int { m.len() }        // error[E1400] at `K`: add `K: Hash`
> fn size_ok[K: Hash, V](m: Map[K, V]) -> Int { m.len() } // OK
>
> type Bag[T] { s: Set[T] }                              // error[E1400] at `T` in the field
> type Bag2[T: Hash] { s: Set[T] }                       // OK; `Bag2[Float]` is E0306 at the use
>
> type M[K] = Map[K, Int]                                // error[E1400]: write `type M[K: Hash]`
> enum Ev[T] { Seen(Set[T]), None }                      // error[E1400] at `T` in the payload
> fn h[T](f: fn(Set[T]) -> Int) -> Int { 0 }             // error[E1400] at `T`
> fn r[T: Hash]() -> Set[T] { Set.new() }                // OK
> ```
>
> Tradeoffs. For: one sentence ("a Map key or Set element you write must be hashable") covers the
> concrete case that already errors, the generic case, and the body rule decided last batch. Q2 has
> no other coherent answer: without implied bounds, an unbounded `Bag[T]` lets `Bag[Float]` name the
> type `Set[Float]`, which the concrete rule rejects. The fix is mechanical and the help names it, so
> AI and human authors get it right on the first edit. Against: `size[K, V]` above never hashes, and a
> Python/TS dev will see the bound as ceremony. 13 lib/std fns gain `K: Hash`; that is migration work, not
> a cost to users, who rarely write pass-through map helpers with a bare K.
>
> Cross-language: Rust puts no bound on `HashMap<K, V>` itself and checks only at `insert`; Kotlin
> and TS have no bound at all. Haskell's `Data.Map` also keeps the bound on the operations. Blink
> already went the other way for concrete keys, so P1 is the consistent version of that choice.
>
> ### G1-P2: signatures exempt, declarations not
>
> Parameter and return types of a fn may hold an unbounded K (Rust style, today's `map_len` stays);
> fields, payloads and aliases need `K: Hash` (E1400 at the declaration). Smaller migration, but two
> rules where P1 has one, and a reader must learn why `Map[K, V]` is fine in one spot and not in the
> next. Not preferred.

- **PLT:** (excerpt, section `G1: unbounded type parameter as a key in a written type`)

>
> The core question: is `Map[K, V]` well-formed for every `K`, or only for `K: Hash`? The spec already says "Set requires T: Hash" (03_types.md:6709), and a concrete `Map[Float, Int]` in a signature is E1400 today. So `Map` and `Set` act as if they were declared `type Map[K: Hash, V]` and `type Set[T: Hash]`. Then §3.6 *Bounds on a Type Declaration* and *No implied bounds* already give the answer. G1 does not need a new rule. It needs one sentence that says Map and Set are bounded type declarations, and E1400 is the code for their bound.
>
> ### G1-P1 (preferred): Map/Set carry a declared `Hash` bound; every written type is checked against it
>
> - A written type (parameter, return type, field, enum payload, alias target, local annotation, `fn(...)` type, impl header, trait method signature, a type argument nested at any depth) that has `Map[X, _]` or `Set[X]` where `X` is, or holds, a type parameter with no `Hash` bound in scope: E1400 at `X`, in check. The help and the machine-applicable fix add `: Hash` to that parameter's binder. That binder is the fn, the impl, the trait method, or the type declaration.
> - A concrete non-hashable key in a written type (`Map[Float, Int]`, `Set[List[Int]]`): E1400 at the type, the same as today.
> - A user type that holds the parameter as a key must write the bound: `type Bag[T: Hash] { s: Set[T] }`. After that, `Bag[Float]` is E0306 at the use, because the bound is now a user-written bound (the same split as at a call today: E1400 where the Map/Set is written, E0306 where a user binder rejects).
> - An alias is not a macro: `type M[K] = Map[K, Int]` is E1400 at `K` in the target, and the fix is `type M[K: Hash] = ...`.
> - A body use stays as decided last batch (E1400 at the use).
>
> ```blink
> fn size[K, V](m: Map[K, V]) -> Int { m.len() }          // error[E1400] at `K`: add `K: Hash`
> fn size_ok[K: Hash, V](m: Map[K, V]) -> Int { m.len() } // OK
> fn mk[T]() -> Set[T] { Set.new() }                     // error[E1400] at `T` in the return type
> fn app[T](f: fn(Set[T]) -> Int) -> Int { 0 }           // error[E1400] at `T` in the fn type
> type Bag[T] { s: Set[T] }                              // error[E1400] at `T`: write `type Bag[T: Hash]`
> type Bag2[T: Hash] { s: Set[T] }                       // OK
> type Tagged[T] {
>     One(Set[T])                                        // error[E1400] at `T` in the payload
>     Two
> }
> type M[K] = Map[K, Int]                                // error[E1400] at `K`
> fn g(m: Map[Float, Int]) -> Int { m.len() }            // error[E1400] at `Float` (today)
> fn use_bag(b: Bag2[Float]) -> Int { 0 }                // error[E0306] at `Float`: `Bag2` declares `T: Hash`
> ```
>
> Tradeoffs. Well-formedness becomes one judgment: "every written type is well-formed under the bounds in scope". There is no special case for the std containers, and E1400 at a concrete `Float` and at an unbounded `K` are the same check. It also closes the implied bound on `Bag[T]`, which is the pattern G5-Q1 rejected. Cost: `map_len`, `set_len` and similar std fns write `K: Hash`. The ERROR_CATALOG E0303 example `fn f[K, V](m: Map[K, V]) {}` changes. That is migration only.
>
> ### G1-P2: the bound is on the operations, not on the type
>
> `Map[K, V]` is well-formed for every `K`. E1400 fires only where a key is hashed (insert, get, contains, a literal, a body key use). To be coherent, `fn g(m: Map[Float, Int])` and `type B { s: Set[Float] }` must then become legal, which reverses today's behavior. The Float contract would move from "the type is rejected" to "no operation accepts it". It is sound, but it lets an empty, useless `Map[Float, Int]` exist, and it moves the error away from the declaration, where the fix goes.
>
> Cross-language: Rust and Haskell use P2 (`HashMap<K, V>` and `Data.Map k v` have no bound on the type; the bounds are on `impl`/functions). Rust WF checking (RFC 2089 rejected implied bounds for structs) is the model for P1 on user types. Blink already chose P1 for user types (§3.6) and for concrete Float keys. P2 would make std containers the one exception.
>
> ---

- **DevOps:** (excerpt, section `G1: unbounded type parameter as a key in a written type`)

>
> **Today (probed):**
> - Concrete non-hashable key in a written type is ALREADY E1400 at the type, in check:
>   `fn f(m: Map[Float, Int])` (E1400 at `Float`, 1:18), `type B { s: Set[Float] }` (2:22),
>   `type M = Map[Float, Int]` (1:19).
> - Local written type `let s: Set[T] = Set.new()` with unbounded T: E1400 (body rule).
> - `fn g[K, V](m: Map[K, V])`, `fn r[T]() -> Set[T]`, `fn c[T](f: fn(Set[T]) -> Int)`,
>   `type M[K] = Map[K, Int]`, payload `A(s: Set[T])`, field `type Bag[T] { s: Set[T] }`: all OK.
> - `fn h[T](b: Bag[T]) -> Int` is OK; `let b: Bag[Float] = ...` is E1400 at `Float` in the
>   annotation. So `Bag` has an implied `T: Hash` that the user never wrote and the LSP cannot hover.
>
> ### G1-P1 (preferred): one rule for every written type, checked at the type
>
> `Map[K, _]` and `Set[K]` require `K: Hash` wherever the type is WRITTEN: param, return, field,
> enum payload, alias right side, fn-type param/return, local annotation, type argument. A
> concrete type with no `Hash` is E1400 at the key (today). A type parameter with no written
> `Hash` bound is E1400 at the key, in check, with a machine-applicable fix that adds `: Hash` to
> the binder (fn, type, alias, impl; trait method per the settled body rule). A type that holds
> a keyed parameter (`Bag[T]` once `Bag` writes `T: Hash`) needs the bound at each use: E0306 by the
> settled "no implied bounds" rule.
>
> ```blink
> type Bag[T: Hash] { s: Set[T] }              // OK
> type Bad[T] { s: Set[T] }                    // error[E1400] at `T` in `Set[T]`; fix: `T: Hash`
> type M[K: Hash] = Map[K, Int]                // OK
> fn size[K: Hash, V](m: Map[K, V]) -> Int { m.len() }   // OK
> fn size2[K, V](m: Map[K, V]) -> Int { m.len() }        // error[E1400] at `K`; fix: `K: Hash`
> fn h[T](b: Bag[T]) -> Int { 0 }              // error[E0306]: `Bag` needs `T: Hash`
> fn h2[T: Hash](b: Bag[T]) -> Int { b.s.len() }          // OK
> ```
>
> Diagnostic shape: one E1400 per binder per declaration, primary span at the first key
> occurrence, a secondary label at each other occurrence of that binder as a key in the same
> declaration. A user who writes `fn f[K](a: Map[K, Int], b: Set[K]) -> Map[K, Int]` gets one
> error and one fix, not three.
>
> Tradeoffs: the rule is one sentence, and its site never moves. The concrete case and the
> parameter case give one code at one kind of site. Hover on `Bag` shows the full contract. The
> error lands in the declaring file, not in a caller in another package (today's `Bag[Float]` error
> lands at the user, far from the cause). The cost is writing `K: Hash` on `map_len` and similar
> (13 lib/std fns); that is migration, and it documents a fact that is true anyway: no
> `Map[Float, _]` can exist, so the bound loses no caller.
>
> Cross-language: Go is P1: `func f[K any, V any](m map[K]V)` is "invalid map key type K (missing
> comparable constraint)". Rust (`HashMap<K, V>` has no bound on the struct) and Swift (implied
> `Hashable` from the signature) are the two models we already rejected (no implied bounds).
>
> ### G1-P2: signatures and aliases exempt, fields and bodies checked
>
> Map/Set in a fn signature with unbounded K is OK (as Rust); E1400 only in a field, a payload or
> a body. Tradeoff: the rule needs a list of positions, and a reader cannot tell why
> `fn f[K](m: Map[K, Int])` is OK but `type W[K] { m: Map[K, Int] }` is not. Rejected by me.

- **AI/ML:** (excerpt, section `G1 — unbounded parameter as a key in a written type`)

>
> **Facts today (gen1):**
> - `fn f[K, V](m: Map[K, V]) -> Int { m.len() }` — clean.
> - `type Bag[T] { s: Set[T] }`, `type M[K] = Map[K, Int]`, `fn h[T](x: T) -> Set[T]`, `fn k[T](g: fn(Set[T]) -> Int)` — all clean.
> - `fn mk() -> Bag[Float]` — E1400 at the `Float` in the return type (the key role leaks from Bag's field onto Bag's `T`: an implied bound).
> - Concrete key in a written type: `fn g(m: Map[Float, Int])` and `type B { s: Set[Float] }` are **already E1400 at the type**, in check.
>
> So today a written `Map[Float, Int]` is checked at the type, but a written `Map[K, Int]` is not, and a user type that holds `Set[T]` gets a bound nobody wrote.
>
> ### G1-P1 (PREFERRED): one rule for every written type — the key must be known hashable where it is written
>
> `Map[A, V]` and `Set[A]` in any written type (parameter, return, local annotation, field, alias
> body, enum payload, fn/closure type, type argument) need `A` to be hashable from the bounds in
> scope. Concrete non-hashable `A`: E1400 at `A` (today's behavior). `A` holds an unbounded
> parameter: E1400 at `A`, help/fix adds `T: Hash` to the binder that declares it (fn, impl,
> type, alias, trait method). A user type that holds a key then writes the bound itself, and a use
> of it with a non-hashable argument is E0306 at the use (settled "no implied bounds" rule).
>
> ```blink
> fn size[K: Hash, V](m: Map[K, V]) -> Int { m.len() }   // OK
> fn size_bad[K, V](m: Map[K, V]) -> Int { m.len() }     // error[E1400] at `K`: add `K: Hash`
>
> type Bag[T: Hash] { s: Set[T] }                        // OK
> type BagBad[T] { s: Set[T] }                           // error[E1400] at `T` in `Set[T]`
> type Counts[K: Hash] = Map[K, Int]                     // OK
> enum Ev[T] { Seen(Set[T]) }                            // error[E1400]: add `T: Hash`
>
> fn mk() -> Bag[Float] { Bag { s: Set.new() } }         // error[E0306] at `Bag[Float]`: Float has no Hash
> fn g(m: Map[Float, Int]) -> Int { m.len() }            // error[E1400] (unchanged)
> ```
>
> Tradeoffs (AI seat): one rule, zero exceptions: "Map key / Set element is `Hash` wherever you
> write it". A model does not need to track whether the body happens to insert. It matches the
> concrete case the compiler already enforces, and it is the same shape as `S[T: Tr]` → E0306.
> Cost: `: Hash` is 2 tokens per binder, and the fix is machine-applicable, so a model that
> forgets it gets a one-edit repair. It also removes a non-local failure: today `Bag[Float]`
> fails at a use far from the field that caused it, which is the worst case for a model to fix.
>
> Cross-language: Go requires `func f[K comparable, V any](m map[K]V)`; Swift requires
> `Key: Hashable` on any `Dictionary<Key, V>` in a generic signature. Both are heavily represented
> in training data. Rust (`HashMap<K, V>` with no bound on the struct) is the counter-example.
>
> ### G1-P2: signatures exempt, fields and aliases checked
>
> Keep `fn f[K, V](m: Map[K, V])` legal (a function that only reads `len()` cannot hash), but
> require the bound on type/alias/enum declarations (Q2), E1400 at the field.
>
> Tradeoffs: saves 2 tokens in 13 std fns. Adds a decision point ("is this a signature or a
> declaration?") and makes `Map[K, V]` in a param legal while the same text in a field is not.
> A model copying a signature into a struct field gets an error it cannot predict. Rejected by
> this seat, but coherent.
>
> ### G1-P3: status quo (no rule at the type, implied key role on user types)
>
> Not coherent with *No implied bounds*; listed for completeness only.
>
> ---

- **Minimalism:** (excerpt, section `G1 — unbounded parameter as a key in a written type`)

>
> Facts today (gen1):
> - Concrete: `fn f(m: Map[Float, Int])` and `type B { s: Set[Float] }` are already E1400 at the type, in check.
> - Unbounded parameter: `fn g[K](m: Map[K, Int])`, `fn h[T]() -> Set[T]`, `type Bag[T] { s: Set[T] }`, `type M[K] = Map[K, Int]`, `type E[T] { A(Set[T]), B }`, `fn k[T](f: fn(Set[T]) -> Int)` all check clean.
> - `Bag[Float]` is refused at the use, and `let s: Set[List[Int]] = h()` gets a second E1400 that says "`h` uses its type parameter T as a Set element". Both are implied bounds: the compiler reads a declaration's insides to find a bound that nobody wrote.
>
> ### G1-P1 (PREFERRED): `Map` and `Set` act as if declared `type Map[K: Hash, V]` and `type Set[T: Hash]`
>
> No new rule. §3.6 *Bounds on a Type Declaration* already says where a bound on a type is checked: at each place a program writes or infers the type — signature, return type, field, enum payload, alias, fn type, local annotation, impl header, trait signature. Apply that rule to the two built-in types, with code E1400 (the code the concrete case uses today). A call that passes a non-`Hash` type to a `T: Hash` parameter stays E0306, as settled.
>
> ```blink
> fn len_bad[K, V](m: Map[K, V]) -> Int { m.len() }       // E1400 at `K` in `Map[K, V]`
> fn len_ok[K: Hash, V](m: Map[K, V]) -> Int { m.len() }  // OK
> type Bag[T] { s: Set[T] }                               // E1400 at `T`
> type Bag2[T: Hash] { s: Set[T] }                        // OK
> type M[K] = Map[K, Int]                                 // E1400 at `K`
> type M2[K: Hash] = Map[K, Int]                          // OK (alias bounds exist: §3.6 `type A2[X: Tr] = S[X]`)
> type E[T] { A(Set[T]), B }                              // E1400 at `T`
> fn k[T](f: fn(Set[T]) -> Int) -> Int { 0 }              // E1400 at `T`
> fn r[T]() -> Set[T] { Set.new() }                       // E1400 at `T` in the return type
> fn bad(m: Map[Float, Int]) -> Int { m.len() }           // E1400 at `Float` (as today)
>
> fn main() {
>     let b: Bag2[Float] = Bag2 { s: Set.new() }          // E0306 at `Float` (unmet bound of Bag2)
> }
> ```
>
> Tradeoffs (minimalism):
> - Subtraction. The last batch's body rule becomes one case of this rule (a body's local `Map[(K, Int), Int]` is a written type). The implied-bound inference (`tc_hash_oblig`, the "`h` uses its type parameter T" second report) goes away. One rule for every position, so the moderator's list of positions needs no per-position answer.
> - It closes the contradiction with *No implied bounds*: `Set[T]` with unbounded `T` is exactly `S[U]` with `type S[T: Tr]`.
> - Cost: `fn map_len[K, V]` style helpers write `K: Hash`. The bound is honest: you cannot put an entry into a `Map[K, V]` without hashing `K`, so a `Map` with a non-hashable key is a value that can only ever be empty. Nothing useful is lost.
> - ERROR_CATALOG E0303's "OK" example `fn f[K, V](m: Map[K, V]) {}` must change.
>
> Cross-language: Go rejects `func f[K any](m map[K]int)` ("invalid map key type K (missing comparable constraint)") — this proposal. Rust and Haskell put the bound on operations, not the type, which needs the implied-bound reasoning Blink has rejected.
>
> ### G1-P2: body-only (status quo of the spec), minus the implied bound
>
> Signature and field positions accept an unbounded key; only a body use is E1400; `Bag[Float]` is then accepted, and a later `impl[T] Bag[T]` method that inserts gets E1400 in its body. Fewer edits to lib/std, but two rules (written type vs body) where one does the job, and a `Bag[Float]` that check accepts but no code can fill. Not preferred.

#### Phase B — Debate highlights

- **Systems:** (excerpt, section `G1`)

> No objection. Straight to the vote.

- **Web/Scripting:** (excerpt, section `G1`)

> No objection. Straight to the vote.

- **PLT:** (excerpt, section `G1`)

> No objection. Ready.

- **DevOps:** (excerpt, section `G1`)

> No objection. Ready to vote on the single option.

- **AI/ML:** (excerpt, section `G1`)

> No objection. Straight to the vote.

- **Minimalism:** (excerpt, section `G1`)

> No objection. Ready for the 6/6 vote.

#### Phase C — Final vote

- **G1-Q1: a `Hash` bound on a `Map` key or `Set` element in every written type (6-0, option A; the other option was to reject)**

- **Systems:**

> ## G1-Q1
> **Vote:** A
> **Reasoning:** A `Map[K, V]` with a K that cannot be hashed can never be built, and the concrete form `Map[Float, Int]` is already E1400 at the type. So a generic signature must not be able to name what the concrete program cannot. With the bound written on every binder, each mono instance of `Map`/`Set` has a hash fn for K by construction. Codegen needs no fallback path for this, and the checker reads binders, not field roles.
> **Concern:** The bound spreads up through every generic wrapper type and fn that holds a Map or Set, and without a machine-applicable `: Hash` fix at each binder that churn will annoy users.

- **Web/Scripting:**

> ## G1-Q1
> **Vote:** A
> **Reasoning:** One rule a JS/Python dev learns once: "a Map key or Set element you write must be hashable", whether the key is concrete (already E1400 today) or a type parameter. The fix is one mechanical edit, and the help names it. An unbounded `Bag[T]` with an inferred key role is a hidden rule that surfaces far from its cause.
> **Concern:** Pass-through helpers like `fn size[K, V](m: Map[K, V])` that never hash will feel like ceremony. If the E1400 help does not give the exact `K: Hash` edit at the binder, this becomes a recurring Stack Overflow question.

- **PLT:**

> ## G1-Q1
> **Vote:** A
> **Reasoning:** Map and Set behave as bounded type declarations (`Map[K: Hash, V]`, `Set[T: Hash]`). So a written type is well-formed only under the bounds in scope. That is the same judgment §3.6 *Bounds on a Type Declaration* already uses for user types and today's E1400 uses for a concrete `Float` key. It removes the inferred key role on `Bag[T]`, which was an implied bound and broke *No implied bounds*.
> **Concern:** The check has to reach every written-type position, including an alias target, a fn type, an impl header and a trait method signature. If it misses one, that position keeps an unbounded key with no error.

- **DevOps:**

> ## G1-Q1
> **Vote:** A
> **Reasoning:** One rule checked at the written type gives one E1400 site in the file that declares the type, with a fix on the binder that a tool can apply. A concrete `Map[Float, Int]` in a written type is already E1400 at the type, so the parameter case now gives the same code at the same kind of site. Hover on `Bag` shows the whole contract, because no bound is added silently.
> **Concern:** A signature with several keyed uses of one binder could print several E1400s for one missing bound, unless the implementation reports one per binder per declaration and labels the other uses.

- **AI/ML:**

> ## G1-Q1
> **Vote:** A
> **Reasoning:** One rule with no exceptions: a Map key or Set element is `Hash` wherever it is written. A model does not need to know whether the body hashes. It matches the E1400 that a concrete `Map[Float, Int]` already gets at the type. The fix adds 2 tokens and is machine-applicable. It also removes today's non-local failure, where `Bag[Float]` fails far from the field that caused it.
> **Concern:** If the E1400 help does not name the exact binder to edit (fn, type, alias or trait method), a model will put `: Hash` on the wrong binder and loop.

- **Minimalism:**

> ## G1-Q1
> **Vote:** A
> **Reasoning:** It is the existing §3.6 *Bounds on a Type Declaration* rule applied to `Map` and `Set`, so it adds no new concept. The last batch's body rule becomes one case of it, and the inferred key role (an implied bound) goes away. That is a net subtraction.
> **Concern:** Users who write pass-through helpers (`fn size[K, V](m: Map[K, V])`) will see `K: Hash` as noise, and the E0303 catalog example must change, or the spec contradicts itself.

### Final Spec

```blink
type Bag[T: Hash] { s: Set[T] }                           // OK
type Bad[T] { s: Set[T] }                                 // error[MapKeyNotHashable] (E1400) at `T`
fn size[K, V](m: Map[K, V]) -> Int { m.len() }            // E1400 at `K`; help: add `K: Hash`
fn size_ok[K: Hash, V](m: Map[K, V]) -> Int { m.len() }   // OK
fn flt(m: Map[Float, Int]) -> Int { 0 }                   // E1400 at `Float`
fn use_bag(b: Bag[Float]) -> Int { 0 }                    // error[TraitBoundNotSatisfied] (E0306) at `Float`
fn pass[U](b: Bag[U]) -> Int { 0 }                        // E0306 at `U`
```

- `Map` and `Set` act as `Map[K: Hash, V]` and `Set[T: Hash]`. A written type is under that bound (§3.6 *Bounds on a Type Declaration*, *No implied bounds*).
- An unbounded type parameter, or a key that holds one, in a parameter, return, field, enum payload, alias target, `fn` type, local annotation, `impl` header or trait method signature is E1400 at the key, in `blink check`.
- A concrete key with no `Hash` impl in a written type is E1400 at the key (the same as before).
- The fix adds `: Hash` to the exact binder. One declaration gives one E1400 for each binder; each other keyed use is a label.
- A type that holds a key writes `: Hash` itself. `Bag[Float]` and an unbounded use of `Bag[U]` are E0306. The compiler gives a type parameter no inferred key role.
- Spec text: §3.6 *A type parameter as a key or element in a written type*, *Bounds on a Type Declaration*, *No implied bounds*; E1400 in ERROR_CATALOG.md.
