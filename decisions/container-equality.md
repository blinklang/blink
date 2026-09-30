[< All Decisions](../DECISIONS.md)

# Container Equality — Design Rationale

**Gap:** the ticket title was "Option[Set]==Option[Set] is silently pointer identity while bare Set==Set is a hard error". The spec never said whether `List`, `Map`, `Set`, `Option` or `Result` implement `Eq`. The Built-in Type Trait Implementations table had no container rows. §3.2 *The Contains Trait* said nested-collection equality "is not yet defined ... until value equality lands", while §3.6 *Hash Contract and Seeding* said "two maps with equal entry sets are `==`-equal". No vote had decided container `Eq`.

**Facts given to the panel (measured 2026-09-30 with gen1):**

- `Option[Set[Int]] == Option[Set[Int]]` and `Option[List[Int]] == Option[List[Int]]`: typecheck accepts; codegen stops with ICE `EqualityOperandNotDerived`. The ticket's "pointer identity" claim was stale.
- `Set == Set`, `List == List`, `(Int, Int) == (Int, Int)`, `Map == Map`, `Result == Result`: `error[TypeError] (E0300): binary ==: incompatible types List[Int] and List[Int]`.
- Typecheck accepts `Option == Option` with no check of the inner type, so `Option[T] == Option[T]` in a generic fn needs no `T: Eq`.
- Same-enum `==` is accepted with no `@derive(Eq)`, data enums included.
- `@derive(Eq)` rejects container and tuple fields with E1401; its explain text says container `==` "is pointer identity".
- `assert_eq`/`assert_ne` (`[T: Eq + Display]`) compare structurally in codegen with no `Eq` check.

**Already decided (given to the panel as constraints):** operators desugar to trait calls (5-0); `@derive` covers compiler-known traits with inferred per-field bounds; tuples get structural `Eq`/`Ord`/`Hash`/`Display`/`Clone` when elements do (5-0); `Float` total order with `NaN == NaN` (5-0); Hash coherence law H1, seed-free; `Map`/`Set` iteration order is not part of value identity; containers have no `Hash` (E1400); `Bool` and `Int` are distinct; `==` on a type parameter needs an `Eq`/`Ord` bound; monomorphization, no specialization; opaque FFI handles have no `==`.

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated
in independent-proposal → debate → vote rounds.

#### Phase A — Independent proposals

All six put the same core first: conditional structural `Eq` for the built-in containers (Option A below). Fallbacks differed: no container `Eq` at all (sys, web, aiml) or `Eq` for `Option`/`Result` only (plt, devops, min). min also listed and rejected "do nothing". Full texts, verbatim:

**Systems:**

> **Systems panelist: Phase A proposals**
>
> ###### Proposal S1 (recommended): conditional structural Eq for every built-in container, checked at typecheck, one monomorphized eq function per type
>
> **Rule.** The compiler supplies these impls, the same way it supplies Debug for List, Option and Map today:
>
> | Type | Eq when | Meaning of `==` |
> |---|---|---|
> | `Option[T]` | `T: Eq` | tags equal, then payloads `==` |
> | `Result[T, E]` | `T: Eq`, `E: Eq` | tags equal, then payloads `==` |
> | `List[T]` | `T: Eq` | lengths equal, then each element in order `==` |
> | `Set[T]` | always (`T: Hash`, so `T: Eq` already) | lengths equal, and each element of `a` is found in `b` |
> | `Map[K, V]` | `V: Eq` | lengths equal, and each key of `a` is in `b` with a `==` value |
> | tuples | already decided 5-0 | element by element |
>
> Typecheck does all the checking. `cmp_operands_ok` stops treating `Option == Option` as always valid. It asks the trait solver whether `Option[T]: Eq` holds. When it does not hold, it reports E0300 at typecheck, so no code reaches codegen and there is no ICE. Inside a generic fn, `Option[T] == Option[T]` then needs `T: Eq`, which matches the locked E0305 rule for a bare `T`. `@derive(Eq)` accepts a container field when the container is Eq (drop that part of E1401). `assert_eq` goes through the same Eq impl, so there is one equality path and not two.
>
> ```blink
> @derive(Eq)
> type Tag {
>     name: Str
>     ids: List[Int]
> }
>
> fn same_tags(a: Option[Set[Int]], b: Option[Set[Int]]) -> Bool {
>     a == b
> }
>
> fn find[T: Eq](xs: List[Option[T]], x: Option[T]) -> Bool {
>     xs.contains(x)
> }
>
> fn main() {
>     let a: Set[Int] = Set.from([1, 2, 3])
>     let b: Set[Int] = Set.from([3, 2, 1])
>     io.println("{same_tags(Some(a), Some(b))}")
>     let t1 = Tag { name: "x", ids: [1, 2] }
>     let t2 = Tag { name: "x", ids: [1, 2] }
>     io.println("{t1 == t2}")
> }
> ```
>
> Both lines print `true`.
>
> **What the hardware sees.** The compiler emits one C function per concrete type, such as `eq_List_Int(a, b)`, and memoizes it by tid. The steps:
>
> 1. If the two handles point to the same object, return true. This is safe because the Float total order makes `NaN == NaN`, so every Eq impl is reflexive.
> 2. If the lengths differ, return false. For all containers this check costs O(1).
> 3. For a List of a scalar with one bit pattern per value (Int, sized ints, Bool, Char), compare with a single `memcmp`. Float cannot take this path: NaN has many bit patterns, and -0.0 and 0.0 differ under the total order. This `memcmp` is a codegen choice, not a second language-level impl, so it does not break the "no specialization" rule.
> 4. Otherwise, run a straight loop that calls the element's eq function directly. The call is static and can be inlined, with no vtable.
> 5. For Set and Map, do one probe of `b` for each entry of `a`, which costs O(n) expected. The probe uses the seeded hash, but the result does not depend on the seed. That keeps H1 and the "iteration order is not identity" rule.
>
> There is no boxing and no dynamic dispatch. Programs that never compare containers get no code for it.
>
> **Tradeoffs.**
> - `==` on a container hides an O(n) cost. `Str == Str` and `Bytes == Bytes` already do the same thing, so this is not a new kind of hidden cost. It is also a cost you can predict from the type: no allocation, and linear in length.
> - Deep nesting such as `List[Map[Str, List[Int]]]` produces many small eq functions and more code. Memoizing by tid limits this to one function per type the program uses.
> - Container equality is by value, so no language-level path is left that exposes pointer identity. That is good: identity would leak allocator and GC layout into program meaning.
> - The spec becomes consistent. The Map sentence at 03_types.md ("two maps with equal entry sets are ==-equal") gets a real rule behind it. The `.contains` "not yet defined" paragraph can go away. The E1401 explain text must change.
>
> **Ord (out of scope, noted).** List, Option, Result and tuples could get lexicographic Ord later. Map and Set must never get Ord, because they have no order.
>
> **Cross-language.**
> - Rust: `impl PartialEq for Vec<T> where T: PartialEq`, with an internal `memcmp` fast path for bytewise-equal types. HashMap eq also works by lookup.
> - Swift: `Array: Equatable where Element: Equatable` (conditional conformance), the same shape as this proposal.
> - Go is the opposite case: slices and maps are not comparable with `==`, so users call `slices.Equal`, `maps.Equal` or the slow, reflection-based `reflect.DeepEqual`. That split is widely seen as friction.
>
> ###### Proposal S2 (fallback): make container `==` an error everywhere
>
> Fix only the leak. Typecheck rejects `==` on any type whose Option, Result, List, Map or Set layer has no Eq, with E0300 at typecheck. `Option[Int] == Option[Int]` stays valid, because Int is Eq and the recursive check passes. `Option[Set[Int]]` and a bare `Set[Int]` both fail. Users write the loop by hand, or call an explicit method.
>
> ```blink
> fn same(a: Option[List[Int]], b: Option[List[Int]]) -> Bool {
>     a == b
> }
> ```
>
> This gives `error[E0300]: Option[List[Int]] has no Eq: List[Int] has no Eq impl`.
>
> **Tradeoffs.** Nothing is hidden and there is zero new codegen. But `assert_eq` on a List still needs its own rule. The Map sentence in 03_types.md must be deleted. Every user will write the same loop, often wrongly, for example with an order-sensitive Set compare. This is Go's position, and it costs usability for no runtime gain, because the loop the user writes costs the same as the one the compiler would emit.
>
> ###### Recommendation
>
> **S1.** It costs nothing at run time beyond the loop a user would write anyway. It is monomorphized and statically dispatched. It removes the ICE by moving the check to typecheck, where it belongs, and it makes the Map entry-set sentence true. Choose S2 only if the panel will not accept an O(n) `==`, and in that case also reject `Str == Str` for the same reason, to stay consistent.
>
> **Out of scope, but it needs the same treatment.** Today `==` on the same data enum works with no `@derive(Eq)`. Under S1, an enum with a container payload should be Eq only when its payloads are Eq.

**Web/Scripting:**

> ###### Web/Scripting panelist — Phase A proposals
>
> My test for any answer: a Python/JS developer writes `if tags == other_tags` in their first hour. What happens next decides how many Stack Overflow questions we get.
>
> Python: `[1,2] == [1,2]` is `True`, `{1,2} == {2,1}` is `True`, `{"a":1} == {"a":1}` is `True`, `(1,2) == (1,2)` is `True`. Kotlin: `listOf(1,2) == listOf(1,2)` is `true`. Rust: `Vec`, `HashMap`, `HashSet`, `Option` all derive `PartialEq`. JavaScript is the odd one out — `[1,2] === [1,2]` is `false`, and it is one of the most-asked JS questions ever. We should not copy the one mainstream language whose container `==` is a known trap.
>
> ---
>
> ###### Proposal W1 (my pick): Structural Eq for every container, conditional on the element
>
> **Rule.** The compiler supplies conditional Eq impls, the same way it already supplies conditional Debug:
>
> | Type | Eq when | Meaning of `==` |
> |---|---|---|
> | `List[T]` | `T: Eq` | same length, elements equal in order |
> | `Set[T]` | `T: Eq` (Hash already required) | same size, every element of one is in the other; order does not matter |
> | `Map[K, V]` | `V: Eq` | same key set, equal value per key; order does not matter |
> | `Option[T]` | `T: Eq` | both None, or both Some with equal payloads |
> | `Result[T, E]` | `T: Eq, E: Eq` | same tag, equal payload |
> | tuples | all elements Eq | element-wise (already voted 5-0; typecheck must now implement it) |
> | `Bytes` | always | byte-wise (spec already says so) |
>
> **Consequences:**
> 1. `Option[Set[Int]] == Option[Set[Int]]` works and gives the value answer. The ICE goes away because the case becomes legal, not because we special-case it.
> 2. `Option[NoEqStruct] == ...` becomes a typecheck error that names the inner type. `cmp_operands_ok` must check the inner type for Eq.
> 3. In a generic fn, `Option[T] == Option[T]` needs `T: Eq` — same as the locked E0305 rule for bare `T`.
> 4. `@derive(Eq)` accepts container and tuple fields (per-field bounds inferred as today). Delete the E1401 explain text that says "`==` on them is pointer identity".
> 5. `List.contains` works for any `T: Eq`. Delete the "until value equality lands" caveat.
> 6. The Map sentence in 03_types.md ("equal entry sets are ==-equal") becomes true instead of dangling.
> 7. Nothing in Blink `==` is pointer identity. If someone later needs identity, add a named fn (`ref_eq`) that says what it does. YAGNI for now.
>
> ```blink
> @derive(Eq, Debug)
> type Tag {
>     name: Str
> }
>
> @derive(Eq)
> type Post {
>     title: Str
>     tags: Set[Str]
>     meta: Option[Map[Str, Str]]
> }
>
> fn same_items[T: Eq](a: List[T], b: List[T]) -> Bool {
>     a == b
> }
>
> fn main() {
>     let a = Set.from([1, 2, 3])
>     let b = Set.from([3, 2, 1])
>     io.println("{a == b}")                 // true: order is not identity
>
>     let x: Option[Set[Int]] = Some(a)
>     let y: Option[Set[Int]] = Some(b)
>     io.println("{x == y}")                 // true
>
>     let names = [Tag { name: "blink" }]
>     io.println("{names.contains(Tag { name: "blink" })}")   // true
>
>     io.println("{same_items([1, 2], [1, 2])}")              // true
>     io.println("{(1, "a") == (1, "a")}")                    // true
> }
> ```
>
> ```blink
> type Handle {
>     id: Int
> }
>
> fn main() {
>     let h: Option[Handle] = None
>     if h == None {  // error: Option[Handle] == needs Handle: Eq
>         io.println("empty")
>     }
> }
> ```
> The diagnostic must say *why* and give the fix: "Handle does not implement Eq; add @derive(Eq) to Handle, or use `h.is_none()`". The `== None` case is the one scripters will hit most — the hint must name `is_none()`.
>
> **Tradeoffs (DX view):**
> - **+** Zero surprise for Python/Kotlin/Rust/Swift users. One sentence in the docs: "`==` compares values; containers compare their contents."
> - **+** Removes four "not yet" caveats from the spec. Each caveat is a future forum question.
> - **+** Test code gets simpler: `assert_eq(xs, [1, 2, 3])` already works structurally; now plain `==` agrees with `assert_eq`. Today they disagree, which is worse than either rule alone.
> - **−** `==` on a large List/Map is O(n). Python users already expect this; nobody files bugs about it.
> - **−** Set/Map equality must use lookups, not lock-step walk (iteration order is randomized). Correct but slightly slower; hide it in the runtime.
> - **−** Element-conditional rules ("List[Handle] has no ==") need good diagnostics. The cost is in error text, not in the rule.
>
> **Scope limit.** W1 covers Eq only. Container Ord (lexicographic List/tuple, as in Python) is a separate question; tuples already have it by the 5-0 vote. Set and Map must never get Ord.
>
> ---
>
> ###### Proposal W2 (fallback, if the panel rejects W1): Consistent rejection
>
> If the panel does not want container Eq now, the minimum fix is consistency: **any container `==` is a typecheck error, including when wrapped in Option/Result.** `Option[T] ==` needs `T: Eq`; no container is Eq. The error text points to `.is_none()` / `.is_some()` / pattern match.
>
> ```blink
> fn main() {
>     let x: Option[List[Int]] = Some([1])
>     if x == None {   // error: List[Int] is not Eq; use x.is_none()
>         io.println("none")
>     }
> }
> ```
>
> **Tradeoffs:** safe, cheap, closes the silent-wrong hole. But it is a day-one papercut ("why can't I compare two lists?"), it keeps the Map-equality sentence false, and `assert_eq` still compares what `==` refuses. I would treat W2 only as a temporary state on the way to W1, not as the design.
>
> ---
>
> ###### What I reject
> - **Pointer identity for any `==`.** It is the JS trap, and it is silent-wrong. Nobody expects `Some(a) == Some(a_copy)` to be false.
> - **Different rules for bare vs wrapped.** Wrapping must never change what `==` means. That mismatch is the root bug in this ticket.

**PLT:**

> ##### PLT panelist: Phase A proposals
>
> ###### Diagnosis
>
> The gap is not "Option[Set] launders identity." The gap is that `==` has no typing rule for type constructors. The typecheck accepts `Option == Option` with no check on the inner type, so it has no sound way to decide `Option[S] : Eq`. The fix belongs in the trait system, not in codegen.
>
> Typing rule I want in the spec:
>
> ```
> Γ ⊢ e1 : τ    Γ ⊢ e2 : τ    Γ ⊢ τ : Eq
> -------------------------------------------
> Γ ⊢ e1 == e2 : Bool
> ```
>
> `τ : Eq` is derived from the instance environment, the same way we already do conditional `Debug`. Every other part of this proposal follows from that rule.
>
> ###### Proposal P1 (recommended): conditional built-in Eq instances for containers
>
> The compiler provides these instances. They are built-in and conditional, the same pattern as the conditional `Debug` instances (03_types.md, "Container Debug Rendering").
>
> | Instance | Condition | Meaning |
> |---|---|---|
> | `Option[T]: Eq` | `T: Eq` | tags equal, and payloads `==` |
> | `Result[T, E]: Eq` | `T: Eq, E: Eq` | tags equal, and payloads `==` |
> | `List[T]: Eq` | `T: Eq` | same length, and element-wise `==` in order |
> | `Set[T]: Eq` | none (`T: Hash` implies `T: Eq`) | same size, and every `x` in `a` is in `b` |
> | `Map[K, V]: Eq` | `V: Eq` (`K: Hash` implies `K: Eq`) | same key set, and `a[k] == b[k]` for each key |
> | tuples | already decided 5-0 | element-wise |
>
> ```blink
> fn same_tags(a: Option[Set[Str]], b: Option[Set[Str]]) -> Bool {
>     a == b    // Set[Str]: Eq, so Option[Set[Str]]: Eq. Value equality.
> }
>
> fn find[T: Eq](xs: List[Option[T]], x: Option[T]) -> Bool {
>     xs.contains(x)    // needs Option[T]: Eq, which needs T: Eq
> }
>
> fn bad[T](a: Option[T], b: Option[T]) -> Bool {
>     a == b    // error E0305: Option[T] is Eq only when T: Eq; add bound `T: Eq`
> }
>
> struct Handle { fd: Int }    // no Eq
> fn also_bad(a: Option[Handle], b: Option[Handle]) -> Bool {
>     a == b    // error E0300: Option[Handle] does not implement Eq because Handle does not
> }
>
> @derive(Eq)
> struct Doc { tags: Set[Str], lines: List[Str] }    // now legal, no E1401
>
> fn main() {
>     let a = Doc { tags: Set.from(["x"]), lines: ["hi"] }
>     let b = Doc { tags: Set.from(["x"]), lines: ["hi"] }
>     io.println("{a == b}")    // true
> }
> ```
>
> ###### Why each choice is sound
>
> 1. **Equivalence laws hold.** Reflexive, symmetric and transitive all carry up from the elements. The one risky leaf is Float, and the locked decision (NaN == NaN) makes Float a true equivalence. Without that decision, `List[Float]` would not be reflexive.
> 2. **Set and Map equality must be extensional, not representational.** Two sets with the same elements can have different bucket layouts, seeds and insertion histories. Comparing the storage shape would break the rule that iteration order is not part of a value's identity. Membership lookup is correct only if H1 (`a == b ⟹ hash(a) == hash(b)`) holds for `T`. H1 is already locked, so the instance is sound by construction. This also turns the orphaned Map sentence at 03_types.md:2140 into a theorem, not a stray claim.
> 3. **It composes.** Instance resolution is structural recursion on a finite type term, so `Option[List[Map[Str, Set[Int]]]]` resolves in finitely many steps. Mono emits one eq function per instantiation. A recursive user type stops at its own `eq` method, so resolution always ends.
> 4. **No overlap.** Each instance head is a distinct type constructor. Users cannot write `impl Eq for List[X]` (orphan rule), so coherence holds and no specialization is needed.
> 5. **The laundering hole closes as a consequence, not as a special case.** `cmp_operands_ok` stops treating Option as always comparable and asks the instance resolver instead. The codegen ICE `EqualityOperandNotDerived` becomes unreachable.
> 6. **@derive(Eq) extends for free.** Per-field bound inference already produces `where T: Eq`. A `List[T]` field adds the obligation `List[T]: Eq`, which reduces to `T: Eq`. E1401 remains only for fields whose type has no Eq instance (fn/closure types, opaque handles, StringBuilder).
>
> ###### Semantics note: shared cells
>
> Lists, Maps and Sets are shared cells (03_types.md:2342). `==` observes their contents at the time of the call. It does not compare cell identity. P1 adds no identity operator (YAGNI). If a need appears later, add a named function such as `List.same_cell(a, b)`, not a second meaning of `==`.
>
> ###### Spec edits P1 requires
>
> - Add rows for Option, Result, List, Set, Map and Bytes to the Built-in Type Trait Implementations table, with the conditions above.
> - 03_types.md:337 and :525: `List.contains` works for any `T: Eq`. Delete the "not yet defined" text.
> - E1401 explain text: delete the "pointer identity" claim. It is false today and would be false under P1.
> - `assert_eq`/`assert_ne` already declare `T: Eq`. Enforce that bound instead of comparing structurally in codegen.
>
> ###### Ord: out of scope, with one bound on it
>
> If Ord comes later, it must be lexicographic for List, with `None < Some` for Option. Set and Map must **never** be Ord: their elements need not be Ord, and there is no ordering that is canonical and consistent with extensional Eq.
>
> ###### Proposal P2 (fallback): Option/Result only
>
> `Option[T]: Eq` iff `T: Eq`, and `Result[T, E]: Eq` iff both parameters are Eq. List, Map and Set stay non-Eq, so `Option[Set[Int]] == ...` becomes a typecheck E0300.
>
> This is sound and small, but it does not compose. A struct with a `List` field cannot derive Eq. `List[List[Int]].contains` stays a hole. The Map sentence at :2140 must be deleted as false. I rank it below P1 because it fixes the symptom and leaves the type theory incomplete.
>
> ###### Flag for the panel: same issue, different ticket
>
> Same-enum `==` compiles with no `@derive(Eq)`, and so does equality on data enums whose payload is not Eq. That is the same hole P1 closes for containers. The typing rule above settles it: an enum is Eq only through a derive or an impl. I recommend a follow-up ticket, not scope creep here.
>
> ###### Other languages
>
> - **Haskell:** `instance Eq a => Eq [a]`, and `Data.Set` Eq is extensional. This is P1 exactly.
> - **Rust:** `impl<T: PartialEq> PartialEq for Vec<T>`, and `HashSet`/`HashMap` compare extensionally. Rust needs PartialEq only because float NaN breaks reflexivity. Blink already avoids that.
> - **Swift:** conditional conformance (`extension Array: Equatable where Element: Equatable`), added in Swift 4.1 after years of hand-written workarounds.
> - **OCaml:** a warning. Polymorphic `=` is structural on representation: it raises on functions and gives wrong answers for balanced-tree sets that hold the same elements in different shapes. That is the failure P1 avoids by requiring extensional Set and Map instances.
>
> **Vote intent:** P1.

**DevOps:**

> I propose **P1: conditional structural `Eq` for every built-in container**, with the error messages specified as part of the spec. **P2** is a fallback in case the panel rejects value equality for collections.
>
> ###### Why tooling cares
>
> What users get today is the worst possible result from a diagnostics view:
>
> - `[1] == [1]` gives `binary ==: incompatible types List[Int] and List[Int]`. The message is false, because the two types are the same. rust-analyzer or tsserver would never print it.
> - `Some(s) == Some(t)` passes `blink check` and then ICEs in codegen. The LSP shows no red squiggle, and the build crashes.
> - `assert_eq(list_a, list_b)` compiles, because `assert_eq` skips the `T: Eq` check. So the test harness and `==` disagree.
> - The explain text for E1401 says `==` on containers "is pointer identity". That is no longer true.
>
> A language server can only be as correct as the trait facts it reads. Today the code has no single answer to "does `Option[Set[Int]]` implement `Eq`?" Each proposal below gives one answer, stored in one place, which typecheck, `assert_eq`, `@derive` and the LSP all read.
>
> ###### P1: containers have Eq when their contents do (recommended)
>
> The compiler supplies conditional built-in instances. This is the same approach the spec already uses for container `Debug` (sections/03_types.md, "Container Debug Rendering"):
>
> | Type | `Eq` when | Meaning |
> |---|---|---|
> | `Option[T]` | `T: Eq` | tag, then payload |
> | `Result[T, E]` | `T: Eq`, `E: Eq` | tag, then payload |
> | `List[T]` | `T: Eq` | same length, element-wise in order |
> | `Set[T]` | always (`T: Hash` implies `Eq`) | same members; order ignored |
> | `Map[K, V]` | `V: Eq` | same key set, equal value per key; order ignored |
> | tuple | all elements `Eq` | already locked 5-0; typecheck must start to do it |
>
> `Ord` for containers is out of scope. Only tuples get `Ord`, as already decided.
>
> ```blink
> @derive(Eq)
> type Tag { name: Str }
>
> type Widget { id: Int }
>
> fn main() {
>     let a: Option[Set[Int]] = Some(Set.from([1, 2]))
>     let b: Option[Set[Int]] = Some(Set.from([2, 1]))
>     io.println("{a == b}")
>
>     let tags = [Tag { name: "x" }]
>     io.println("{tags.contains(Tag { name: "x" })}")
>
>     let w = [Widget { id: 1 }]
>     let same = w == w
> }
> ```
>
> The last line gives this error:
>
> ```
> error[E0300]: `==` needs `List[Widget]: Eq`
>   --> main.bl:14:16
>    |
> 14 |     let same = w == w
>    |                ^^^^^^
>    = note: `List[T]` is `Eq` only when `T: Eq`
>    = note: `Widget` does not implement `Eq`
>   help: add `@derive(Eq)` above `type Widget` (main.bl:4)
> ```
>
> The rule for this message: walk the type arguments down to the **first leaf that fails**, and report that leaf. Never report the outer type alone. The same walk gives the text for E0305 on generics, for `@derive(Eq)` on a struct whose field fails, and for the `assert_eq` bound. The `help:` line is a machine-applicable fix, so the LSP offers "Derive Eq for Widget" as a quick-fix.
>
> Other effects:
>
> - **Generics.** `Option[T] == Option[T]` in a generic fn now needs `T: Eq`, reported as E0305. This closes the `cmp_operands_ok` gap.
> - **`assert_eq`/`assert_ne`.** Their `T: Eq` bound gets checked like any other bound. The structural fallback in codegen goes away.
> - **`@derive(Eq)`.** It accepts container and tuple fields, with the inferred bound going through the field type. E1401 fires only when a leaf fails. We rewrite the E1401 explain text.
> - **Spec cleanup.**
>   - The Map sentence at the Map/Set iteration-order section becomes true.
>   - The `.contains` "not yet supported" paragraph becomes: `contains` needs `T: Eq`.
>   - The trait table gets rows for all container types, `Bytes` and tuples.
> - **LSP.** Hover on `==` shows the chosen impl, for example `impl Eq for List[T] where T: Eq`. Go-to-definition goes to the spec anchor, because no stdlib source exists for it. Completion does not change.
> - **`blink fmt`.** No new syntax, so no change.
>
> **Tradeoffs.**
>
> - For: one rule that users can predict. It uses the model the spec already has (Debug). It removes the ICE, the false message, the `assert_eq` hole and the stale explain text in one change.
> - For: AI tools that write Blink will write `list == other` because Python, Rust and Kotlin all allow it. P1 makes that code correct, not a trap.
> - Against: `==` on a large `List` or `Map` is O(n) and not visible at the call site. It is the same cost as Rust's `Vec == Vec` and Python's `list == list`. If this matters, a later opt-in lint can flag `==` on containers in hot loops. It should not be a default.
> - Against: Map/Set equality goes through the hash table, so the codegen needs one runtime helper per container kind. That is a fixed, bounded cost.
>
> **Other languages.**
>
> - Rust: `impl<T: PartialEq> PartialEq for Vec<T>`. P1 is the same idea.
> - Python: structural `==` on all containers.
> - Go: forbids `==` on slices and maps. Its error message is at least true ("slice can only be compared to nil").
> - TypeScript: reference identity. This is the silent-wrong result the ticket objects to.
>
> ###### P2 (fallback): Option and Result get Eq, collections get none
>
> - `Option[T]: Eq` when `T: Eq`, and the same for `Result[T, E]`. Tuples follow the locked 5-0 rule.
> - `List`, `Map` and `Set` have no `Eq`. `==` on them is a hard error with a true message:
>
> ```
> error[E0300]: `List[Int]` does not implement `Eq`
>    = note: collections have no `==`; compare with a loop or `.len()` + `.all(...)`
> ```
>
> Because `Option[List[Int]]` is then not `Eq`, the leaf walk rejects it. This closes the laundering path.
>
> Tradeoff: P2 is a smaller change, but users and LLMs will hit this error many times. Also, every `@derive(Eq)` struct with a `List` field stays blocked. P2 is only acceptable if we rewrite the message as above. If we keep "incompatible types X and X", P2 is worse than P1 on every count.
>
> ###### Rules for either proposal
>
> 1. Typecheck decides `Eq`, and one predicate answers it. Codegen never raises "not derived" for an input that typecheck accepted. A codegen ICE is always a compiler bug.
> 2. `assert_eq`, `.contains`, `@derive(Eq)`, `==` and the LSP all use that one predicate.
> 3. A failed `Eq` check names the leaf type that fails and offers a fix that can be applied.
> 4. Add tests for `==` on List, Map, Set, tuple and `Option[List/Map/Set]`, for both the accept and the reject cases. None of these exist today.

**AI/ML:**

> ##### AI/ML panelist: Phase A proposals
>
> ###### Proposal 1 (recommended): containers are Eq when their elements are Eq
>
> **Rule:** a built-in container gets `Eq` exactly when its parts are `Eq`. The comparison is structural. The same rule already applies to tuples (voted 5-0) and to Debug for containers.
>
> | Type | Eq when | Meaning of `==` |
> |---|---|---|
> | `List[T]` | `T: Eq` | same length, and each pair of elements in order is `==` |
> | `Set[T]` | always (`T: Hash`, and `Hash: Eq`) | same length, and each element of one set is in the other |
> | `Map[K, V]` | `V: Eq` | same key set, and each key's value is `==` |
> | `Option[T]` | `T: Eq` | both are `None`, or both are `Some` with `==` payloads |
> | `Result[T, E]` | `T: Eq, E: Eq` | same tag, and the payloads are `==` |
> | `(A, B, ...)` | each element is Eq | element by element (already decided; typecheck must implement it) |
>
> These rules follow from it:
> - `Option[T] == Option[T]` in a generic fn needs `T: Eq`. This closes the typecheck hole that lets unchecked comparisons reach codegen and hit the ICE.
> - If an element type is not Eq, you get a typecheck error that names the missing part. You never get an ICE, and `==` never falls back to comparing pointers.
> - `@derive(Eq)` accepts container and tuple fields and infers the per-field bound. Remove the E1401 container text and its "pointer identity" explain text.
> - `List.contains` works for every `T: Eq`. This removes the "not yet supported" paragraph.
> - `==` never means reference identity. If the language needs identity later, it gets its own named function. YAGNI for now.
> - Ord is out of scope, except for tuples, which are already decided. Containers do not get Ord.
>
> ```blink
> @derive(Eq)
> type Point {
>     x: Int
>     y: Int
> }
>
> @derive(Eq)
> type Route {
>     name: Str
>     stops: List[Point]
> }
>
> fn same_tags(a: Option[Set[Str]], b: Option[Set[Str]]) -> Bool {
>     a == b
> }
>
> fn find[T: Eq](items: List[T], want: T) -> Bool {
>     items.contains(want)
> }
>
> type Blob {
>     data: Bytes
> }
>
> fn main() {
>     let a = [Point { x: 1, y: 2 }]
>     let b = [Point { x: 1, y: 2 }]
>     io.println("{a == b}")
>
>     let r1 = Route { name: "north", stops: a }
>     let r2 = Route { name: "north", stops: b }
>     io.println("{r1 == r2}")
>
>     let m1 = {"k": [1, 2]}
>     let m2 = {"k": [1, 2]}
>     io.println("{m1 == m2}")
>
>     io.println("{same_tags(Some(Set.from([\"x\"])), None)}")
>
>     // Blob has no Eq, so this line is rejected with E0300:
>     // "List[Blob] == List[Blob]: Blob does not implement Eq; add @derive(Eq) to Blob"
>     // let bad = [Blob { data: Bytes.new() }] == [Blob { data: Bytes.new() }]
> }
> ```
>
> This prints `true`, `true`, `true`, then `false`.
>
> **Tradeoffs from the AI/ML view:**
> - **It matches the training data.** Python, Rust (`Vec<T>: PartialEq where T: PartialEq`), Swift (conditional `Equatable`), Kotlin data classes and Go's `==` on arrays all compare containers by value. Models already write `a == b` on lists and expect that. Today they hit E0300, then generate a loop.
> - **Fewer tokens.** The workaround costs about 25 to 40 tokens and is a common source of off-by-one mistakes. `a == b` costs 3 tokens. Comparing maps and sets by hand is worse still, because it needs a lookup in both directions.
> - **One rule to learn: "Eq when the parts are Eq".** It is the same rule as derive, tuples and container Debug. A model can learn it from one table in the spec, and the model needs no list of exceptions.
> - **The error message tells the model what to fix.** The diagnostic names the type that lacks Eq and gives the fix (`add @derive(Eq) to X`). Models fix a named cause in one step. An ICE or a wrong answer that the compiler does not report cannot be fixed that way.
> - **Cost:** `==` on a large container is O(n), and the source text does not show this. This is the same in Python and Rust, and nobody reports it as a problem. Set equality depends on Hash, which works because Hash is already required for Set elements.
> - **It makes the spec agree with itself.** The existing sentence "two maps with equal entry sets are ==-equal" becomes true.
>
> ###### Proposal 2 (fallback, not recommended): no Eq for any container
>
> Make `==` a hard error on every container, including Option and Result of anything. Provide `.equals()` methods, or no comparison at all.
>
> - This also closes the hole, but every Option comparison breaks, and `x == None` is a very common pattern. Models will write `==` on containers anyway, so the error rate rises and every fix costs a rewrite.
> - It creates a second way to compare (`==` for some types, `.equals()` for others). That is one more decision for the model to get wrong. Java's `==` versus `.equals()` split is the standard example of this bug class in LLM output.
>
> ###### Related gap to log as a separate ticket
>
> Same-enum `==` is accepted with no `@derive(Eq)`, and `assert_eq` skips its `T: Eq` bound in codegen. Both break the rule that "`==` needs Eq". Under Proposal 1, both should check Eq the same way. Enums would need `@derive(Eq)`, which is the Rust pattern and well represented in training data. Alternatively, the spec can state that enums are Eq when all their payloads are Eq. Whichever the panel picks, it should be written down as a rule. The spec should not leave it as an accident of the implementation.

**Minimalism:**

> ##### Minimalism panelist: Phase A proposals
>
> ###### What the problem is
>
> Blink has no single rule for which built-in types have `==`. Today:
> - `Option ==` needs no bound on the inner type, and the compiler crashes with an internal error when the inner type is a List or Set.
> - A bare `List ==` is a type error.
> - `@derive(Eq)` rejects container fields.
> - `List.contains` has its own "primitives only" rule.
> - `assert_eq` compares containers by structure but does not require Eq.
> - The spec says in one place that Map has `==`, and in another that nested equality "is not yet defined".
>
> That makes five exceptions and zero rules. My goal is the fewest rules that remove all five.
>
> The orphan rule matters here. Users cannot write `impl Eq for List[X]` or `impl Eq for Option[MyType]`. If the compiler leaves out a container Eq, users have no way to add it. So "leave it to user code" is not a real option, and "leave it to stdlib later" means "leave it to us".
>
> ###### Proposal M1 (recommended): one rule, "a built-in type has Eq when its parts do"
>
> **Rule.** Option, Result, List, Map, Set and tuples implement `Eq` exactly when their type arguments implement `Eq`:
> - `Option[T]: Eq where T: Eq`
> - `Result[T, E]: Eq where T: Eq, E: Eq`
> - `List[T]: Eq where T: Eq`
> - `Map[K, V]: Eq where V: Eq` (K is already Hash, and Hash implies Eq)
> - `Set[T]: Eq` (T is already Hash, so it has Eq)
> - Tuples follow the rule already decided.
>
> Equality always compares values, never pointers:
> - List: same length, and each pair of elements is equal, in order.
> - Map: same length, and each key in the left map is in the right map with an equal value.
> - Set: same length, and each element of the left set is in the right set.
>
> Order is not part of Map or Set identity, which matches the locked iteration-order decision.
>
> **Not added:**
> - No `Ord` for containers (tuples keep theirs).
> - No `Hash` for containers (locked).
> - No `Eq` for StringBuilder, fn types or opaque handles.
>
> **What this removes:**
> - The internal error. `Option[Set[Int]] ==` now type-checks under the real rule.
> - The unbounded `Option ==` in `cmp_operands_ok`. `Option[T] == Option[T]` in a generic fn now needs `T: Eq` like any other use of `T`.
> - The E1401 container carve-out in `@derive(Eq)`. Per-field bounds already cover it.
> - The "primitive elements only" limit on `List.contains`. It becomes `where T: Eq`.
> - `assert_eq`'s special structural path. It now uses the same `Eq` as `==`.
> - The conflict between the two spec sentences. The Map sentence becomes true, and the "not yet defined" note goes away.
>
> ```blink
> @derive(Eq)
> type Point {
>     x: Int
>     y: Int
> }
>
> fn same_tags(a: Option[Set[Str]], b: Option[Set[Str]]) -> Bool {
>     a == b
> }
>
> fn main() {
>     let a = Set.from(["x", "y"])
>     let b = Set.from(["y", "x"])
>     io.println("{same_tags(Some(a), Some(b))}")     // true: order is not identity
>     let ps = [Point { x: 1, y: 2 }]
>     io.println("{ps.contains(Point { x: 1, y: 2 })}") // true: List[T].contains where T: Eq
>     io.println("{[1, 2] == [1, 2]}")                // true
> }
>
> fn broken[T](a: Option[T], b: Option[T]) -> Bool {
>     a == b   // error E0305: T has no Eq bound
> }
> ```
>
> **Tradeoffs**
> - `==` on a large List or Map now costs O(n) in time and can take the program deep into nested data. Go refuses slice `==` for this reason. But Go then needed `reflect.DeepEqual`, and later `slices.Equal` and `maps.Equal`. That is three tools for one idea, which is the growth that minimalism wants to avoid.
> - The cost is easy to see in the type, and the codegen for the Option and Result case already does it (`cc_carrier_equal`).
> - The feature adds no new syntax, keyword or trait. It adds only table rows, and the conditional-impl pattern already exists for Debug.
> - It closes five special cases and opens none. That is a net cut in the spec, so I vote yes.
>
> **Cross-language:**
> - Rust: `PartialEq for Vec<T> where T: PartialEq`.
> - Python: `==` on list, dict and set compares values.
> - OCaml: structural `=`.
> - Go: no slice or map `==`, which led to the ad hoc helpers above.
>
> Every language that avoided value equality for containers later added it back as library functions.
>
> ###### Proposal M2 (fallback if the panel rejects List/Map/Set Eq): Option and Result only
>
> Add only `Option[T]: Eq where T: Eq` and `Result[T, E]: Eq where T: Eq, E: Eq`. List, Map, Set and Map-inside-Option stay non-Eq, and `Option[List[Int]] ==` becomes E0300 at typecheck instead of an internal error.
>
> This change must also:
> - Delete the "two maps with equal entry sets are ==-equal" sentence.
> - Keep the E1401 carve-out and the `List.contains` limit.
> - Make `assert_eq` require real `Eq`, or keep its bypass. Either way it stays a special case.
>
> **Tradeoff.** M2 adds less spec now, but it keeps four exceptions alive and leaves users with no escape hatch, because of the orphan rule. It fixes the ticket but not the gap. I rank it second.
>
> ###### Proposal M0 (the "do nothing" option)
>
> Rejected. Today's behavior is an internal compiler error, which cannot be a valid spec state. At minimum, typecheck must reject what codegen cannot compile.
>
> ###### Two things the panel must not skip
>
> 1. **Same-enum `==` without `@derive(Eq)`.** Today it is accepted, even for data enums. Under M1 or M2, `Option[MyEnum] ==` would need `MyEnum: Eq`. This is a small decision, but it is part of this gap. My view: require `@derive(Eq)` for data enums, keep payload-free enums implicit, and put it to a vote.
> 2. **Structs without Eq inside Option.** `Option[NoEqStruct] ==` must become E0300 at typecheck. Both M1 and M2 give this result.
>
> **Vote intent: M1 > M2 >> M0.**

#### Phase A.5 — Deduped option-space (moderator, mechanical)

- **A** — conditional structural `Eq` for built-in containers (first pick of all six). Variations: A-v1 `Set` condition wording; A-v2 a `Bytes` row; A-v3 normative diagnostic text; A-v4 codegen shape; A-v5 `Ord`; A-v6 a named identity function.
- **B** — no container is `Eq` (fallback: sys, web, aiml).
- **C** — `Option` and `Result` get conditional `Eq`; `List`, `Map`, `Set` do not (fallback: plt, devops, min).
- **D** — do nothing (listed and rejected by min).
- **SQ1** — `assert_eq`/`assert_ne` enforce their declared `T: Eq` bound (raised by all six).
- **SQ2** — same-enum `==` without `@derive(Eq)`.

#### Phase B — Debate (one round; all six replied `STABLE: ready to vote`)

Key shifts: all six accepted "always" for `Set`, the `Bytes` row, "`Set` and `Map` never implement `Ord`", and no named identity function; codegen shape stays out of the spec. sys and plt proposed the Eq-laws contract; sys proposed the cyclic-data sentence. All six agreed to decide SQ1 here. On SQ2, plt, devops, sys and aiml wanted a payload-conditional interim rule; min wanted "Eq exactly where same-enum `==` compiles today"; web wanted no interim rule. Full round-1 texts, verbatim:

**Systems:**

> ##### Systems: Phase B round 1
>
> ###### 1. Options and variations
>
> **Option A.** Rank: A > C > B. D is not valid.
>
> - **A-v1:** use the "always" text: `Set[T]: Eq` with no extra bound, because `T: Hash` already implies `T: Eq`. Web's "`T: Eq`" means the same thing. It only adds a condition that can never fail.
> - **A-v2:** yes, add the `Bytes` row: always Eq, compared byte by byte, no Ord. The spec already says this in prose, and the table must agree with it.
> - **A-v3:** make devops's "first failing leaf" rule normative, because it defines *which* type the error names. Keep the exact wording outside the spec. Also add web's `is_none()` hint as a `help:` line when one operand is the literal `None`.
> - **A-v4:** keep the codegen details out of the spec. Only two points belong in it: Set/Map `==` must not depend on seed or iteration order, and its cost is O(n) expected.
> - **A-v5:** put "Set and Map never get Ord" in the spec now. It is a lasting constraint, and PLT gives the reason. Treat plt's List/Option ordering as a note for a later ticket, not as a decision here.
> - **A-v6:** add no identity function now.
>
> **Proposed addition to A: the Eq laws, E1.** A user-written `impl Eq` must be reflexive, symmetric and transitive. The compiler may rely on this, the same way it relies on H1 for Hash. Without this rule, two things break:
>
> - My same-pointer shortcut (`a is b ⟹ true`) and the `memcmp` path would change observable results for a user impl that is not reflexive.
> - Set/Map membership would be ill-defined.
>
> Float already satisfies E1 through the locked NaN decision. This is one sentence next to H1, and it makes the codegen shortcuts legal by spec, not by luck.
>
> **Note on cycles.** Lists, Maps and Sets are shared cells. A struct can hold a List that then holds a copy of that struct, so `==` on such data may not end. Debug has the same problem today. The same-pointer shortcut ends the usual self-compare case. The spec should state "`==` on cyclic data may not terminate". It should not require a cycle guard, which would put a cost on every compare.
>
> ###### 2. SQ1 and SQ2
>
> **SQ1: decide it here.** `assert_eq` and `assert_ne` must enforce `T: Eq` and use the one Eq predicate, with the codegen path removed. This is the same rule, not a separate one.
>
> **SQ2: separate ticket, with one limit on it set here.** Under A, `Option[E] == Option[E]` asks whether `E: Eq`. So whatever rule the enum ticket chooses must give the same answer for a bare enum and for a wrapped enum (web: "Wrapping must never change what `==` means."). Until that ticket closes, the Eq predicate should treat a data enum as Eq only when its payloads are Eq. That stops a container payload inside an enum from becoming a new way around the check.
>
> ###### 3. Responses
>
> - devops: "the codegen needs one runtime helper per container kind." List and Option/Result eq should be monomorphized per type, with direct calls. A shared runtime helper that calls back through a function pointer per element costs one indirect call per element. For Set/Map, the lookup already goes through the kops table, so a helper there adds no new indirection. Either way, the spec does not change.
> - min: "the codegen for the Option and Result case already does it (`cc_carrier_equal`)." Agreed. A only adds the typecheck gate and the List/Set/Map leaves, so it is not a codegen rewrite.
> - devops and aiml: "a later opt-in lint can flag `==` on containers in hot loops." I agree with leaving it out by default. `Str ==` is already O(n) and carries no lint.
> - plt: "Rust needs PartialEq only because float NaN breaks reflexivity. Blink already avoids that." This is exactly why E1 above costs nothing: the built-in leaf types already satisfy it.
>
> STABLE: ready to vote

**Web/Scripting:**

> ##### Web/Scripting panelist: Phase B round 1
>
> ###### 1. Options and variations
>
> **Option A.** Six of six panelists put it first. B and C each leave a day-one papercut ("why can't I compare two lists?") and a spec that disagrees with `assert_eq`. D leaves an ICE. I rank them A > C > B > D.
>
> - **A-v1 (Set condition):** I withdraw my wording. Use "always (`T: Hash` implies `T: Eq`)". It means the same thing, and it tells the reader why no extra bound is needed.
> - **A-v2 (Bytes row):** Add it. 03_types.md already says "Bytes implements ... Eq", so the row only puts that fact in the table where readers look. It costs nothing and removes a lookup.
> - **A-v3 (diagnostics):** Put devops' first-failing-leaf rule in the spec as the normative rule: "A failed Eq check names the innermost type that is not Eq, and gives a fix." Keep the exact text non-normative. My `== None` → `is_none()` hint is one case of that rule, and it belongs in the implementation ticket, not the spec. It is still the case users hit most often, so the ticket must test it.
> - **A-v4 (codegen):** Not spec text. Keep it as implementation notes. The same-pointer shortcut is sound only because of the locked NaN == NaN rule. Put that dependency in a comment where it is used.
> - **A-v5 (Ord):** Spec text: "Set and Map never implement Ord." Leave everything else about container Ord out of the spec. plt's "lexicographic List, `None < Some`" is a sensible default, but it has not had a vote, and writing it down now pre-decides a later panel.
> - **A-v6 (identity):** No name in the spec. YAGNI. The spec says only "`==` on a built-in type never compares identity."
>
> ###### 2. Sub-questions
>
> **SQ1: enforce the `T: Eq` bound on `assert_eq`/`assert_ne`. Yes, and decide it here.** It is the same predicate as `==`. If we leave it out, the spec keeps a place where tests pass on types that `==` rejects, and users learn "equality" from their tests first. Migration cost: any test that calls `assert_eq` on a struct without Eq breaks. That is the correct outcome, and the fix is one `@derive(Eq)`. The implementation ticket must sweep tests/ for this.
>
> **SQ2: same-enum `==` without derive. Separate ticket, but log and link it before this one closes.** Option A's rule ("Option[T]: Eq when T: Eq") holds whatever way T gets Eq, so SQ2 does not block this vote. My DX input for that ticket: payload-free enums should stay Eq with no derive. Python `Enum`, TS enums and Kotlin enum classes all compare without ceremony, and `if color == Red` is the 90% use case. Data enums should follow `@derive(Eq)` like structs. That matches min's position.
>
> ###### 3. Responses
>
> - min: "Same-enum `==` ... This is a small decision, but it is part of this gap." I agree it is the same kind of gap, but a data-enum rule breaks existing user code and needs its own migration story. Folding it in slows the fix for the ICE. It should be a separate, linked ticket.
> - sys: "Choose S2 only if the panel will not accept an O(n) `==`, and in that case also reject `Str == Str`." Good point. It kills the "hidden cost" objection: we already accept O(n) `==` on Str and Bytes, and no user has complained.
> - aiml: "every Option comparison breaks, and `x == None` is a very common pattern." Agreed, and this applies under A too. `Option[Handle] == None` becomes an error when Handle has no Eq. I do **not** want a special rule for `== None`, because special rules are how we got this ticket. The `is_none()` hint in the error is the fix.
> - devops: "`binary ==: incompatible types List[Int] and List[Int]`. The message is false." That is the most damaging text in the current compiler for new users. The fix for this ticket must remove it, not only the ICE.
>
> STABLE: ready to vote

**PLT:**

> ##### PLT — Phase B round 1
>
> ###### 1. Options and variations
>
> **A.** All six panelists put A first, and it is the only option with a complete typing rule. B and C are sound but do not compose (a struct with a `List` field cannot derive Eq, and the orphan rule leaves users no escape). I reject D: the current state is an ICE.
>
> - **A-v1 (Set condition).** The two texts mean the same thing, because `Set[T]` already requires `T: Hash`, and `Hash: Eq`. Spec text I want: "`Set[T]: Eq` — no added condition; `T: Hash` already gives `T: Eq`." That states the reason, so a reader does not think a bound is missing.
> - **A-v2 (Bytes row).** Yes. The spec already says Bytes is Eq, and the table should agree with the prose.
> - **A-v3 (diagnostics).** Make one part normative: "a failed Eq check names the innermost type argument that has no Eq." Keep the exact wording and the `is_none()` hint informative. The spec should state a property that tools can test, not fix the message text.
> - **A-v4 (codegen).** Informative only, with one fix. The same-pointer shortcut and the Set/Map lookup are correct only if Eq is reflexive and Hash obeys H1. Eq and Hash are open traits, so a user impl can break both. The spec must therefore state the laws as a contract: "Eq impls must be an equivalence relation. Hash impls must obey H1. If an impl breaks a law, container `==` gives an unspecified Bool but stays memory-safe." Without that sentence, the shortcut changes observable behaviour (`xs == xs` is true even when `x == x` is false for an element), and the spec would have to forbid it. `memcmp` on built-in scalars needs no contract, because those impls are ours.
> - **A-v5 (Ord).** Put this in the spec: "Set and Map never implement Ord." That follows from the theory: no order is both canonical and consistent with extensional equality. Leave List, Option and Result Ord **open**, not denied. I disagree with aiml's "Containers do not get Ord", which closes a door we have no reason to close. My lexicographic note can stay in the decision record, not the spec.
> - **A-v6 (identity).** Spec sentence: "`==` never compares identity." Add no named identity function now. The name gets chosen when a user needs one.
>
> ###### 2. SQ1 and SQ2
>
> **SQ1: decide here.** It follows directly from the typing rule. `assert_eq[T: Eq + Display]` already declares the bound. Enforcing it removes a second equality path. Migration note: tests that `assert_eq` a struct with no Eq will stop compiling. That is correct: they relied on the bypass.
>
> **SQ2: I revise my Phase A position.** Option A cannot resolve `Option[MyEnum]: Eq` until the spec says when `MyEnum: Eq`. Today the typecheck treats every enum as Eq, which launders a non-Eq payload exactly as `Option` did. So decide the **soundness floor** here:
>
> > An enum with no Eq impl or derive is Eq only if every payload type is Eq. Payload-free enums are Eq.
>
> Whether data enums must *write* `@derive(Eq)` (min's view, and the Rust convention) is a surface-syntax choice that does not affect soundness. Send that to a separate ticket. This keeps the vote narrow and still closes every hole.
>
> ###### 3. Responses
>
> - sys: "If the two handles point to the same object, return true. This is safe because the Float total order makes `NaN == NaN`, so every Eq impl is reflexive." Float alone does not give "every Eq impl". User impls do not have to be reflexive. The shortcut is fine once the law contract in A-v4 is in the spec.
> - aiml: "Ord is out of scope ... Containers do not get Ord." Please drop the second sentence, or limit it to Set and Map.
> - min: "require `@derive(Eq)` for data enums, keep payload-free enums implicit." I agree with the direction, but only the soundness floor above belongs in this vote.
> - devops: "walk the type arguments down to the first leaf that fails." I support this as the normative property in A-v3. The machine-applicable `help:` should stay tooling guidance.
>
> STABLE: ready to vote

**DevOps:**

> ##### DevOps/Tooling — Phase B round 1
>
> ###### 1. Options
>
> **Option A.** B and C both keep "no `==` on a List" as a daily error that users and LLMs will hit. D leaves an ICE in place. I rank them A > C > B >> D.
>
> Variations:
>
> - **A-v1 (Set):** Put in the spec: "`Set[T]: Eq` always, because `T: Hash` already implies `T: Eq`." The spec needs that because-clause. Without it, the LSP hover shows an impl with no bound, and a reader asks why. Web's "`T: Eq`" means the same thing, but it suggests that a `Set` can fail Eq, which can never happen.
> - **A-v2 (Bytes):** Yes, add the row. The spec already says `Bytes` implements `Eq`. The trait table is what the LSP and `blink doc` read, so a type that is missing from it looks like it has no Eq.
> - **A-v3 (diagnostics):** Make the *content* normative and keep the *wording* non-normative. Text for the spec:
>   > When `τ: Eq` fails, the diagnostic names the innermost type argument that has no `Eq`, and the chain from `τ` to it. When that type is a user type, the diagnostic offers `@derive(Eq)` as a fix. When one operand of `==` is `None`, the diagnostic also offers `.is_none()`.
>
>   I accept web's `is_none()` hint as written. `x == None` is the error that will happen most often.
> - **A-v4 (codegen):** Keep it out of the spec. Same-pointer shortcut, `memcmp` and per-tid memoization are implementation notes. The one normative part is the Float exclusion, and it already follows from the total order.
> - **A-v5 (Ord):** Put plt's sentence "Set and Map never implement Ord" in the spec, because E0300's explain text can then say "never" and not "not yet". A "not yet" makes users file feature requests. Do not bind List/Option Ord now (YAGNI).
> - **A-v6 (identity):** No text in the spec. Do not name `ref_eq` or `same_cell`.
>
> ###### 2. Sub-questions
>
> **SQ1:** Yes, decide it here. `assert_eq` enforces `T: Eq` through the same predicate as `==`, and the codegen structural path goes away. If two paths remain, the test harness and the compiler will give different answers again.
>
> **SQ2:** Decide the final rule in a separate ticket. But **A cannot ship without an interim rule**, because A makes `Option[E] == Option[E]` ask whether `E: Eq`. Today the bare same-enum `==` says yes, with no predicate behind it. Suppose the predicate says no for `Option[E]` while bare `E == E` passes. Then wrapping changes what `==` means, which is the exact bug in this ticket, only the other way round. Web's line applies: "Wrapping must never change what `==` means."
>
> Interim text I support, taken from sys: **"An enum is Eq when all of its payload types are Eq. A payload-free enum is Eq."** This rule makes the predicate cover every type, so codegen cannot ICE on a payload that is not Eq. It rejects one case that compiles today: `==` on a data enum whose payload is a struct with no Eq. That code has no defined meaning today, so the new error is correct. It offers `@derive(Eq)` on the struct as the fix. The separate ticket can then decide whether data enums need `@derive(Eq)`.
>
> ###### 3. Responses
>
> - plt: "`Option[T] is Eq only when T: Eq; add bound T: Eq`". This is the leaf-walk message for the generic case. Adopt it as the E0305 example in the spec.
> - min M2: "Make `assert_eq` require real `Eq`, or keep its bypass." Under any option, keeping the bypass is not acceptable. SQ1 must hold for B and C too.
>
> STABLE: ready to vote

**AI/ML:**

> ##### AI/ML panelist: Phase B round 1
>
> ###### 1. Options and variations
>
> **Option A.** B, C and D rank below it: C > B > D. Option C leaves `@derive(Eq)` blocked on any struct that has a List field, and that shape is the most common one that models write. B turns `x == None` into an error for many types. D keeps an ICE.
>
> - **A-v1 (Set condition): put "always" in the spec, with the reason in brackets: "(`T: Hash`, and Hash implies Eq)".** Web's "`T: Eq`" gives the same result, but it reads as an extra bound, so a model will add `T: Eq` to generic fns over Set for no need. One row with no condition is one fewer decision.
> - **A-v2 (Bytes row): include it.** The spec already says Bytes is Eq. The table is where a model looks. A type that is Eq but has no row in the table is a trap.
> - **A-v3 (diagnostics): make devops's "first failing leaf" walk and its machine-applicable `help:` fix normative.** Add web's `is_none()` hint as a second `help:` line when one operand is the literal `None`. For LLMs, the error text is the most important part of this decision. A model fixes a named leaf with a stated fix in one step. The message "incompatible types List[Int] and List[Int]" makes a model loop.
> - **A-v4 (codegen): keep it out of the spec.** It is a valid implementation note for the ticket. The same-pointer shortcut and the `memcmp` path give the same results only because Float is a total order. The spec should state the laws (reflexive, symmetric, transitive) and let codegen follow them.
> - **A-v5 (Ord): put one sentence in the spec: "Set and Map have no Ord."** That removes a future question at no cost. Keep plt's "if Ord comes later, lexicographic" in the decision record only, not in the spec. It is a rule about a feature that does not exist.
> - **A-v6 (identity): pick no name now.** Put one sentence in the spec: "`==` never compares identity." That sentence is what a model needs, and a function name is YAGNI.
>
> ###### 2. Sub-questions
>
> **SQ1: decide it here, yes.** `assert_eq` is the path that tests use, and models write many tests. If `assert_eq(a, b)` passes where `a == b` is rejected, a model learns the wrong rule from its own passing tests. This must be one predicate, as devops's "Rules for either proposal" 1-2 says.
>
> **SQ2: separate ticket, with one interim rule decided here.** Under A, `Option[E] == Option[E]` reads `E: Eq`. Until the enum ticket closes, typecheck must reject `==` on an enum when a payload has no Eq, as sys says ("Eq only when its payloads are Eq"). Otherwise the ICE comes back through `Option[DataEnum]`. For the follow-up ticket, I lean away from min's split between payload-free and data enums. "Implicit when there is no payload, derive when there is" is a rule that a model will apply wrongly when it adds the first payload to an existing enum. Either "always derive" (Rust) or "structural when the payloads are Eq" is one rule. I will argue this in that ticket.
>
> ###### 3. Responses
>
> - To devops: "`[1] == [1]` gives `binary ==: incompatible types List[Int] and List[Int]`. The message is false." Agreed, and this matters more for AI than for people. A model trusts the message and tries to change the types. Tests that check the text of that message should be part of the decision.
> - To sys: "Choose S2 only if the panel will not accept an O(n) `==`, and in that case also reject `Str == Str`." Agreed. This argument disposes of the cost objection to A.
> - To min: "Every language that avoided value equality for containers later added it back as library functions." This matches what code models do. In Go they write `reflect.DeepEqual` in tests and hand-written loops elsewhere, which gives two styles for one idea.
> - To web, W1: `Set[T]` "`T: Eq` (Hash already required)". See A-v1. I prefer "always".
>
> STABLE: ready to vote

**Minimalism:**

> ##### Minimalism panelist: Phase B round 1
>
> ###### 1. Options and variations
>
> **Option A.** This is still my first pick. Six out of six panelists put it first, so B, C and D are now only fallbacks. My fallback order stays C > B >> D. B is worse than C: aiml's form breaks `x == None`, and sys's form turns into C once Option keeps its Eq.
>
> - **A-v1 (Set condition).** Use "always (`T: Hash`, and Hash implies Eq)". Web's "`T: Eq`" means the same, but it states a condition that can never fail. A spec row with a condition that is always true suggests a case that does not exist.
> - **A-v2 (Bytes row).** Yes. 03_types.md already says "Bytes implements: ... Eq". The row only copies that fact into the table, so it adds no new surface.
> - **A-v3 (diagnostic text).** This does not belong in the spec. The spec states the rule, and the compiler chooses the message. The requirement should be one sentence: "The E0300/E0305 diagnostic names the first type argument that is not Eq." Devops's full message layout and the `help:` fix, and web's `is_none()` hint, should go in an implementation ticket. They are good ideas, but a normative message format fixes wording in place, and every later change to it becomes a spec change.
> - **A-v4 (codegen).** This does not belong in the spec. The `memcmp` path, the same-pointer shortcut and the memoizing are implementation choices. Sys says so for `memcmp` itself ("a codegen choice, not a second language-level impl"). The spec needs only the equality laws.
> - **A-v5 (Ord).** I accept one sentence: "Set and Map have no Ord." The reason is permanent: they have no canonical order. I reject any promise of lexicographic List order or `None < Some`. That is an Ord design made before anyone asks for Ord. Decide it when Ord comes up.
> - **A-v6 (identity).** The spec should say "`==` never compares identity" and stop there. It should name no function (`ref_eq`, `same_cell`), not even as a future idea, because a named placeholder invites someone to build it.
>
> ###### 2. Sub-questions
>
> **SQ1: yes, decide it here.** Enforce the declared `T: Eq` bound on `assert_eq`/`assert_ne` and remove the structural path in codegen. Without this, Option A still has two meanings of equality. This is the subtraction that justifies A.
>
> **SQ2: decide it in a separate ticket, but state one sentence here.** Option A's rows say "when `T: Eq`". Whether a given enum is Eq is a question about the enum, not about containers. This ticket must not quietly decide it. The sentence I want in this ruling: "Until the enum-Eq ticket is decided, an enum counts as Eq exactly where same-enum `==` compiles today." That keeps `Option[MyEnum] == Option[MyEnum]` working and blocks nothing. It also means Option A creates no new enum behavior. My position for that ticket stays the same: payload-free enums are Eq by default, and data enums need `@derive(Eq)`. PLT's rule (Eq only through a derive or an impl) is a valid competing option there.
>
> ###### 3. Responses
>
> - PLT: "`Γ ⊢ τ : Eq` is derived from the instance environment". I endorse this as the normative text. It is the smallest statement of the whole ruling, and the table is its instance list. The spec should say one rule plus the table, not six prose paragraphs.
> - Sys: "Choose S2 only if the panel will not accept an O(n) `==`, and in that case also reject `Str == Str`". Agreed. This settles the "hidden O(n)" objection: Str and Bytes already have it, so rejecting A for cost would be inconsistent.
> - Devops: "a later opt-in lint can flag `==` on containers in hot loops". YAGNI. Leave it out of this ruling and do not open a ticket for it until someone reports the problem.
> - Devops rule 4 ("Add tests for `==` on List, Map, Set, tuple ... accept and reject"). Agreed. This belongs in the implementation ticket, not the spec.
> - aiml: "Go's `==` on arrays" compares containers by value. This is true of fixed-size arrays only. Go slices and maps, the equivalents of List and Map, have no `==`. Please do not cite Go as support for A in the recorded rationale.
>
> STABLE: ready to vote

#### Phase C — Final vote

The ballot, verbatim:

> ###### Q1 — Core rule
> - **A** — conditional structural Eq for built-in containers (Option[T] when T: Eq; Result[T, E] when T: Eq, E: Eq; List[T] when T: Eq; Set[T] always, because T: Hash gives T: Eq; Map[K, V] when V: Eq; tuples per the locked vote). Value equality; Set/Map by membership, order ignored. `Option[T] == Option[T]` in a generic fn needs `T: Eq`.
> - **B** — no List/Map/Set/container Eq; `==` on them is rejected, wrapped or bare.
> - **C** — Option and Result get conditional Eq; List, Map, Set do not.
> - **D** — do nothing.
>
> ###### Q2 — Bytes row in the trait table (Eq yes, Ord no)
> - **Yes** / **No**
>
> ###### Q3 — What the spec says about the failed-Eq diagnostic
> - **3a** — normative property only: "a failed Eq check names the innermost type argument that has no Eq". Wording and fix hints are non-normative (implementation ticket). (min, plt)
> - **3b** — normative property plus fixes: names the innermost failing type (and the chain from τ to it), offers `@derive(Eq)` when that type is a user type, and offers `.is_none()` when one operand is `None`. Exact wording non-normative. (devops text; aiml)
> - **3c** — no diagnostic text in the spec.
>
> ###### Q4 — Ord
> - **4a** — spec says "Set and Map never implement Ord." Nothing else about container Ord (List/Option/Result Ord left open; plt's lexicographic note stays in the decision record only).
> - **4b** — spec says nothing about container Ord.
>
> ###### Q5 — Identity
> - **5a** — spec sentence: "`==` never compares identity." No identity function named.
> - **5b** — no text in the spec (devops A-v6).
>
> ###### Q6 — Eq laws contract (sys "E1", plt A-v4)
> - **6a** — spec states: an `Eq` impl must be reflexive, symmetric and transitive; the compiler may rely on this (as it relies on H1 for Hash). If a user impl breaks a law, container `==` gives an unspecified Bool but stays memory-safe.
> - **6b** — no law contract in the spec.
>
> ###### Q7 — Cyclic data (sys)
> - **7a** — spec sentence: "`==` on cyclic data may not terminate." No cycle guard required.
> - **7b** — no sentence.
>
> ###### Q8 — assert_eq / assert_ne (SQ1)
> - **8a** — enforce the declared `T: Eq` bound through the same Eq predicate as `==`; remove the codegen structural path. Decided here.
> - **8b** — keep today's behaviour.
>
> ###### Q9 — Same-enum `==` without `@derive(Eq)` (SQ2)
> All six said the final rule (whether data enums must write `@derive(Eq)`) goes to a separate ticket. The question here is the interim rule this decision states:
> - **9a** — "An enum with no Eq impl or derive is Eq only if every payload type is Eq. Payload-free enums are Eq." (plt, devops, sys, aiml)
> - **9b** — "Until the enum-Eq ticket is decided, an enum counts as Eq exactly where same-enum `==` compiles today." (min)
> - **9c** — no interim rule in this decision; the separate ticket is logged and linked before this one closes. (web)

- **Q1: Core rule** (6-0 for A)
  - **Systems:**

    > ###### Q1: A
    > **Reasoning.** Each type used gets one monomorphized eq function with direct calls. The cost is a loop the user would otherwise write by hand, and a program that never compares containers gets no code for it. `cc_carrier_equal` already does the Option/Result part, so A adds only a typecheck gate and three kinds of leaf. B and C cost the same at run time but push the loop into user code, where it is often wrong, for example an order-sensitive Set compare.
    > **Concern.** An implementation may take the easy route of a generic runtime helper that makes an indirect call for each element. That would cost far more than a monomorphized loop for `List[Int]`.

  - **Web/Scripting:**

    > ###### Q1 — Core rule
    > **Vote:** A
    > **Reasoning:** Python, Kotlin, Rust and Swift users expect `[1, 2] == [1, 2]` to be true, and A gives them that with one rule: "Eq when the parts are Eq". B and C leave a day-one error on the most common comparison a scripter writes. D leaves an ICE.
    > **Concern:** The error for `Option[Handle] == None` when Handle has no Eq will surprise users. If the error text is poor, it becomes the new top forum question.

  - **PLT:**

    > ###### Q1 — A
    > **Reasoning:** A is the only option that gives `==` one typing rule, `τ : Eq`, resolved by structural recursion over conditional instances. That rule composes through derive, `contains` and generics without special cases. B and C are sound but leave the instance environment incomplete, and the orphan rule means users cannot fill the gap.
    > **Concern:** The typecheck could keep a second `cmp_operands_ok` fast path next to the instance resolver, and the two could drift. There must be one Eq predicate.

  - **DevOps:**

    > ###### Q1 — A
    > **Reasoning:** Under A, the answer to "does `τ` have Eq?" comes from one predicate. Typecheck, `assert_eq`, `@derive`, `.contains` and the LSP hover can all read that one predicate. B and C keep an error on `list == list` that users and LLMs will hit every day. C also leaves `@derive(Eq)` blocked on any struct with a List field.
    > **Concern:** The leaf walk may get built with less care than the rule. Then users get "Option[List[Widget]] is not Eq" and no pointer to `Widget`, which is only a little better than today's false "incompatible types" message.

  - **AI/ML:**

    > ###### Q1: Core rule
    > **Vote:** A
    > **Reasoning:** Models already write `a == b` on lists, maps and sets, because Python, Rust, Swift and Kotlin all compare them by value. Option A makes that code correct. It uses one rule, "Eq when the parts are Eq", which is the same rule as Debug, derive and tuples, so a model can learn it from one table. B and C add exceptions that a model must remember and will get wrong.
    > **Concern:** If the failed-Eq diagnostic is weak, the element-conditional rule gives errors that models cannot fix in one step.

  - **Minimalism:**

    > ###### Q1: core rule
    > **Vote:** A
    > **Reasoning:** A is one rule, "Eq when the parts are Eq", and one table. It adds no syntax, keyword or trait. It removes five special cases: the unbounded Option `==`, the E1401 container carve-out, the `List.contains` limit to primitive elements, the separate structural path in `assert_eq`, and the orphaned Map sentence. Because of the orphan rule, users cannot add these impls themselves, so leaving them out is not a smaller language. It only forces every user to write the same loop by hand.
    > **Concern:** The table may grow rows for every new built-in type by habit, when a row should come only from a real need.

- **Q2: Bytes row in the trait table (Eq yes, Ord no)** (6-0 for Yes)
  - **Systems:**

    > ###### Q2: Yes
    > **Reasoning.** The prose already says Bytes is Eq, and its codegen is a length check plus `memcmp`. The table must agree with the prose.
    > **Concern.** None.

  - **Web/Scripting:**

    > ###### Q2 — Bytes row
    > **Vote:** Yes
    > **Reasoning:** The spec already says Bytes is Eq. Readers look in the table first, so the fact must be there too.
    > **Concern:** A reader may take the missing Ord cell as an oversight and not as a ruling. The row should say "no" for Ord explicitly.

  - **PLT:**

    > ###### Q2 — Yes
    > **Reasoning:** The prose already says Bytes is Eq. The table must agree with it, or the spec contradicts itself. Byte-wise equality is a true equivalence relation.
    > **Concern:** Someone reads a missing Ord cell as "not yet" and adds a byte-wise Ord without a vote.

  - **DevOps:**

    > ###### Q2 — Yes
    > **Reasoning:** The spec already says Bytes is Eq. The table is what `blink doc` and the LSP present, so a row that is missing reads as "no Eq".
    > **Concern:** None.

  - **AI/ML:**

    > ###### Q2: Bytes row
    > **Vote:** Yes
    > **Reasoning:** The spec already says Bytes is Eq. The table is where a model looks for this fact, and a type that is Eq but has no row in the table misleads it.
    > **Concern:** None of note. The row must say "no Ord" clearly.

  - **Minimalism:**

    > ###### Q2: Bytes row
    > **Vote:** Yes
    > **Reasoning:** The spec already says Bytes implements Eq, so the row copies an existing fact into the table and adds no new surface. It adds no Ord.
    > **Concern:** None.

- **Q3: What the spec says about the failed-Eq diagnostic** (3-3 (3a: sys, plt, min; 3b: web, devops, aiml) → Phase D)
  - **Systems:**

    > ###### Q3: 3a
    > **Reasoning.** Which type the error names is a property that tools can test, so it belongs in the spec. Fix hints change as the tooling changes, so they belong in the implementation ticket, not in normative text.
    > **Concern.** If the hints stay non-normative, the `.is_none()` hint may never ship, so the implementation ticket must list it.

  - **Web/Scripting:**

    > ###### Q3 — Failed-Eq diagnostic
    > **Vote:** 3b
    > **Reasoning:** A new user learns what `==` accepts from the errors, not from the spec. If the spec requires the error to offer the fix (`@derive(Eq)`, `.is_none()`), no implementation can ship a bare "type mismatch" again, as today's "incompatible types List[Int] and List[Int]" did. Keeping the exact wording non-normative leaves the implementers room.
    > **Concern:** The `.is_none()` hint is specific to Option. If later carriers need their own hints, the rule can grow into a list of special cases.

  - **PLT:**

    > ###### Q3 — 3a
    > **Reasoning:** A spec should state properties that can be tested, not user-interface text. "Names the innermost failing type argument" is a property a test can check. Fix hints change with tooling and belong in the implementation ticket.
    > **Concern:** With only 3a in the spec, the useful `@derive(Eq)` and `is_none()` hints could never ship, so the implementation ticket must carry them.

  - **DevOps:**

    > ###### Q3 — 3b
    > **Reasoning:** The fix hint is the part of the message that users and LLMs act on. Most failures are a missing `@derive(Eq)` or `x == None`. If the hints are non-normative, they will be left out of the first version and stay missing. We keep the wording non-normative, so no implementation is bound to exact text.
    > **Concern:** If the `.is_none()` hint fires when `None` is only one operand of a deeper expression, it can point users at the wrong fix. The implementation ticket must limit it to a bare `None` literal operand.

  - **AI/ML:**

    > ###### Q3: Failed-Eq diagnostic
    > **Vote:** 3b
    > **Reasoning:** For code-generating models, the error text drives the fix. When the message names the failing leaf and gives the fix (`@derive(Eq)`, `.is_none()`), the model fixes the code in one step. A message that names only the outer type makes the model loop. The property and the fix kinds must be normative so that every tool gives them. The wording can stay free.
    > **Concern:** Implementers may treat the fix hints as optional if the tests do not check them, so the implementation ticket must include tests on the text.

  - **Minimalism:**

    > ###### Q3: failed-Eq diagnostic
    > **Vote:** 3a
    > **Reasoning:** The spec should fix the one property that makes the error useful, which is that it names the innermost type that fails. The spec should not fix the wording or the fixes it offers. Fix hints change as tooling improves. If they are normative, each improvement becomes a spec change.
    > **Concern:** Under 3b, the `.is_none()` and `@derive(Eq)` hints become promises that the language must keep. Under 3a, they may never ship unless the implementation ticket lists them.

- **Q4: Ord** (6-0 for 4a)
  - **Systems:**

    > ###### Q4: 4a
    > **Reasoning.** Set and Map have no canonical order, and any Ord for them would have to sort first, which is O(n log n) and needs `T: Ord`. Ruling it out now stops a costly impl from creeping in later.
    > **Concern.** None.

  - **Web/Scripting:**

    > ###### Q4 — Ord
    > **Vote:** 4a
    > **Reasoning:** Someone will ask "can I sort a list of sets?" One sentence answers it now and stops a later panel from adding an Ord that has no meaning. List, Option and Result Ord stay open, which is honest.
    > **Concern:** Users may read "Set and Map never" as implying that List does implement Ord today.

  - **PLT:**

    > ###### Q4 — 4a
    > **Reasoning:** "Set and Map never implement Ord" follows from the theory. Their equality is extensional, and no order over them is canonical, cheap and consistent with that equality. List, Option and Result Ord have a standard lexicographic answer, so the spec should leave them open, not deny them.
    > **Concern:** A reader may take the silence on List Ord as "List is Ord" and write code that expects it.

  - **DevOps:**

    > ###### Q4 — 4a
    > **Reasoning:** "Never" lets the E0300 explain text and the Ord docs close the question for good. A "not yet" makes users file feature requests. The other container Ord questions stay open, which is YAGNI.
    > **Concern:** Users will sort a `List[Set[T]]` and get an error, so the error text must suggest `sort_by` with a key.

  - **AI/ML:**

    > ###### Q4: Ord
    > **Vote:** 4a
    > **Reasoning:** One sentence removes a future question and stops models from writing `sorted(list_of_sets)` or `set_a < set_b`. It commits to nothing about List Ord.
    > **Concern:** A reader may take the silence on List Ord to mean that List is Ord.

  - **Minimalism:**

    > ###### Q4: Ord
    > **Vote:** 4a
    > **Reasoning:** "Set and Map never implement Ord" rests on a permanent fact: they have no canonical order. It costs one sentence and stops a future proposal early. Nothing about List, Option or Result Ord should go in the spec until someone asks for Ord.
    > **Concern:** A reader may take "Set and Map never" to mean that List, Option and Result will get Ord.

- **Q5: Identity** (6-0 for 5a)
  - **Systems:**

    > ###### Q5: 5a
    > **Reasoning.** One sentence stops anyone from reading `==` as a pointer compare. Identity would expose allocator and GC layout, which the program must not depend on.
    > **Concern.** A later need for a cheap identity check, for example in cache code, has no named home yet. That is acceptable under YAGNI.

  - **Web/Scripting:**

    > ###### Q5 — Identity
    > **Vote:** 5a
    > **Reasoning:** JavaScript's identity `==` on arrays is the trap this whole decision avoids. One sentence rules it out for good and gives docs and LLMs a clear line to quote.
    > **Concern:** Users who need identity (for example, cache keys on a shared cell) have no tool until a later ticket names one.

  - **PLT:**

    > ###### Q5 — 5a
    > **Reasoning:** One sentence removes the ambiguity that caused this ticket (pointer identity through wrapping), and it fixes the meaning of `==` as an observation on values. It commits us to nothing new.
    > **Concern:** A later identity need could push someone to overload `==` again, not add a named function.

  - **DevOps:**

    > ###### Q5 — 5a
    > **Reasoning:** In Phase B I said "no text". I change my vote. This ticket exists because `==` silently became identity, and one normative sentence makes any future codegen path that does that a spec violation. A spec violation is easier to test and to report than an accident of the implementation. The sentence names no function, so it is still YAGNI.
    > **Concern:** A later request for an identity function may try to weaken this sentence, when it should add a named function.

  - **AI/ML:**

    > ###### Q5: Identity
    > **Vote:** 5a
    > **Reasoning:** JavaScript and Java trained models to expect that `==` on objects can mean identity. One sentence in the spec overrides that prior.
    > **Concern:** A later identity function may appear without a name that clearly says it compares identity.

  - **Minimalism:**

    > ###### Q5: identity
    > **Vote:** 5a
    > **Reasoning:** The ticket exists because `==` quietly became pointer identity. One sentence rules that out for good and names nothing new.
    > **Concern:** None.

- **Q6: Eq laws contract (sys "E1", plt A-v4)** (6-0 for 6a)
  - **Systems:**

    > ###### Q6: 6a
    > **Reasoning.** The same-pointer shortcut, the `memcmp` path for scalar lists and Set/Map membership lookup are all correct only under reflexivity and the other laws. This sentence makes those shortcuts legal by spec, not by luck. It matches how H1 already works for Hash, and it costs nothing, because every built-in leaf already satisfies the laws.
    > **Concern.** "Unspecified Bool" must not grow into "undefined behaviour". The implementation must keep memory safety when a user impl is wrong.

  - **Web/Scripting:**

    > ###### Q6 — Eq laws
    > **Vote:** 6a
    > **Reasoning:** Almost every user gets Eq through `@derive`, so the laws hold without any thought. The few who write `eq` by hand need to know that a broken impl gives a wrong Bool, not a crash. That is the same contract as Python's `__eq__` and Java's `equals`.
    > **Concern:** "Unspecified Bool" can hide a user bug in Set/Map equality that is hard to find.

  - **PLT:**

    > ###### Q6 — 6a
    > **Reasoning:** The same-pointer shortcut and extensional Set/Map equality are valid only under the equivalence laws and H1. Eq and Hash are open traits, so the spec must state the laws as a contract, as it already does for H1. With the contract, broken user impls give an unspecified but memory-safe answer, not undefined behaviour.
    > **Concern:** Users may never read the law contract, so a lint or test helper for reflexivity would help later.

  - **DevOps:**

    > ###### Q6 — 6a
    > **Reasoning:** This contract allows the same-pointer shortcut and the membership compare. It also tells users what happens when their impl breaks a law: they get a wrong Bool, not a crash. It matches how H1 is already stated.
    > **Concern:** Users will not see a law break until a Set compare gives a strange result. A later lint on hand-written `eq` could help, but it should stay out of scope.

  - **AI/ML:**

    > ###### Q6: Eq laws
    > **Vote:** 6a
    > **Reasoning:** This matches the H1 contract that already exists for Hash, so a model learns one pattern for both. It also permits fast paths without making user code unsafe.
    > **Concern:** "Unspecified Bool" can hide a bug in a user's Eq impl. A lint on hand-written `eq` would help later.

  - **Minimalism:**

    > ###### Q6: Eq laws
    > **Vote:** 6a
    > **Reasoning:** Eq is an open trait, and the compiler already relies on reflexivity (for example a same-pointer shortcut, and the NaN == NaN decision). A written contract is cheaper than the bug reports that would come without one. It follows the model H1 already set for Hash.
    > **Concern:** "Unspecified Bool" may be read as permission for later optimizations that users find surprising. Keep the list of things the compiler relies on short and state each one.

- **Q7: Cyclic data (sys)** (6-0 for 7a)
  - **Systems:**

    > ###### Q7: 7a
    > **Reasoning.** A cycle guard would add a visited-set allocation to every container compare, a cost everyone pays for a rare case. Stating the limit honestly is the zero-cost choice, and the same-pointer shortcut already ends the usual self-compare case.
    > **Concern.** A cycle gives a stack overflow with a poor message, not a clean panic.

  - **Web/Scripting:**

    > ###### Q7 — Cyclic data
    > **Vote:** 7a
    > **Reasoning:** One honest sentence costs less than a user's afternoon lost to a hang with no known cause. A cycle guard would slow every comparison to help a rare case.
    > **Concern:** A hang is a worse experience than Python's RecursionError. If cycles turn out to be common, we will want a debug-mode guard.

  - **PLT:**

    > ###### Q7 — 7a
    > **Reasoning:** Lists, Maps and Sets are shared cells, so a value can contain itself through a struct field, and structural recursion on such a value does not terminate. The spec should state this honestly and not promise a cycle guard it does not require. Haskell and Rust take the same position.
    > **Concern:** A user who hits a hang will get no diagnostic, so docs should show the shape that causes it.

  - **DevOps:**

    > ###### Q7 — 7a
    > **Reasoning:** Lists and Maps are shared cells, so users can build cyclic data. A hang with no message is the worst result for tooling, but a spec that says so is honest, and it gives the docs a place to point. A cycle guard costs every compare for a rare case.
    > **Concern:** A user will hit a hang in a test, and `blink test` shows only a timeout. The test runner's timeout message may later need to mention this.

  - **AI/ML:**

    > ###### Q7: Cyclic data
    > **Vote:** 7a
    > **Reasoning:** Lists and maps are shared cells, so a cycle is possible. One honest sentence costs nothing and tells a model not to depend on termination. A cycle guard is YAGNI.
    > **Concern:** Users will not read the sentence and will see a hang with no diagnostic.

  - **Minimalism:**

    > ###### Q7: cyclic data
    > **Vote:** 7a
    > **Reasoning:** One sentence costs nothing. It also blocks a future request for a cycle guard, which would add a cost to every comparison for a rare case. Debug printing has the same property.
    > **Concern:** None worth noting.

- **Q8: assert_eq / assert_ne (SQ1)** (6-0 for 8a)
  - **Systems:**

    > ###### Q8: 8a
    > **Reasoning.** Two equality paths mean two codegens that can drift apart. Only one path should exist.
    > **Concern.** Test code that today compares structs without Eq will stop compiling. The migration needs a clear E0300 with a `@derive(Eq)` fix.

  - **Web/Scripting:**

    > ###### Q8 — assert_eq / assert_ne
    > **Vote:** 8a
    > **Reasoning:** Users learn equality from their tests first. If `assert_eq` accepts what `==` rejects, the tests teach them the wrong rule. The migration fix is one `@derive(Eq)` per type.
    > **Concern:** The migration touches many existing tests. It must land in the same change as the rule, or the corpus goes red and someone adds a bypass.

  - **PLT:**

    > ###### Q8 — 8a
    > **Reasoning:** `assert_eq[T: Eq + Display]` already declares the bound. A structural bypass in codegen is a second, unchecked equality relation, which is the same laundering this ticket is about. There must be one relation.
    > **Concern:** Existing tests that `assert_eq` a struct with no Eq will break, and the migration must be done, not waived.

  - **DevOps:**

    > ###### Q8 — 8a
    > **Reasoning:** If there are two equality paths, the test harness and the program can disagree about the same values. That is the worst kind of failure in a test tool. One predicate, one codegen path.
    > **Concern:** Existing tests that call `assert_eq` on non-Eq structs will start to fail to compile. The migration note must list the `@derive(Eq)` fix.

  - **AI/ML:**

    > ###### Q8: assert_eq / assert_ne
    > **Vote:** 8a
    > **Reasoning:** Models write many tests. If `assert_eq` accepts what `==` rejects, a model learns the wrong rule from tests that pass. `==` and `assert_eq` must use one predicate.
    > **Concern:** Enforcing the bound can break existing tests that call `assert_eq` on types with no Eq. Those tests need a sweep before the change lands.

  - **Minimalism:**

    > ###### Q8: assert_eq / assert_ne
    > **Vote:** 8a
    > **Reasoning:** Two equality paths are the root of this ticket. Removing the structural path in codegen is the subtraction that justifies A.
    > **Concern:** Test files that now compare types without Eq will break. The change needs a corpus sweep and a clear E0305/E0300 message.

- **Q9: Same-enum `==` without `@derive(Eq)` (SQ2)** (6-0 for 9a)
  - **Systems:**

    > ###### Q9: 9a
    > **Reasoning.** Without it, a container payload inside an enum becomes a new way around the Eq check. The rule is the same leaf recursion that A uses, so it adds no new mechanism.
    > **Concern.** Code that today compares data enums with non-Eq payloads will break before the enum ticket decides the final rule. That is a small amount of churn, but it may happen twice.

  - **Web/Scripting:**

    > ###### Q9 — Interim enum rule
    > **Vote:** 9a (I change my round-1 position from 9c)
    > **Reasoning:** With no interim rule, `Option[MyEnum] ==` has no defined answer until the other ticket lands, and that is exactly the gap this ticket closes. 9a is the same "Eq when the parts are Eq" rule as Q1, so users learn one idea. It also keeps `if color == Red` working with no ceremony. 9b would write today's implementation accident into the spec.
    > **Concern:** A data enum with a non-Eq payload that compiles today will break. The implementation must point the error at the payload type and offer the fix.

  - **PLT:**

    > ###### Q9 — 9a
    > **Reasoning:** A cannot resolve `Option[E]: Eq` without a rule for `E: Eq`. 9b keeps the exact hole A closes (a data enum with a non-Eq payload counts as Eq), and 9c leaves A's resolver undefined for enums until another ticket lands. 9a is the soundness floor, and it leaves the surface-syntax question (a required `@derive`) open.
    > **Concern:** If the enum ticket later requires `@derive(Eq)`, 9a's implicit structural Eq becomes a breaking change, so that ticket must include a migration.

  - **DevOps:**

    > ###### Q9 — 9a
    > **Reasoning:** 9a makes the predicate cover every type, so codegen cannot reach a payload that has no Eq, and wrapping never changes what `==` means. The only code it rejects today is a data enum whose payload has no Eq, and that code has no defined meaning. 9b ties the spec to "whatever compiles today", which is not a rule an LSP or a reader can check.
    > **Concern:** If the separate ticket later requires `@derive(Eq)` on data enums, users get two changes in a row. The enum ticket should be decided soon.

  - **AI/ML:**

    > ###### Q9: Interim enum rule
    > **Vote:** 9a
    > **Reasoning:** This rule is the same "Eq when the parts are Eq" rule as the container rule, so there is nothing new to learn. It closes the `Option[DataEnum]` path back to the ICE. 9b describes an accident of today's compiler, not a rule, and a model cannot learn it from the spec.
    > **Concern:** If the follow-up ticket then requires `@derive(Eq)`, enum code must change twice.

  - **Minimalism:**

    > ###### Q9: interim enum rule
    > **Vote:** 9a (I change from 9b, which I wrote)
    > **Reasoning:** 9a is the same rule as A: an enum is Eq when its parts are Eq. So the decision holds one rule instead of two. My 9b tied the spec to what the compiler happens to do today, which is the kind of accident this ticket is trying to remove. The separate ticket can still decide whether data enums must write `@derive(Eq)`.
    > **Concern:** If 9a stays long enough, users will depend on implicit enum Eq. The separate ticket must then either keep 9a or pay a migration cost, so it should be logged and linked before this ticket closes.

#### Phase D — Round 2 (Q3 only)

Q3 tied 3-3, so the panel ran one focused round on Q3. Each panelist read all six Q3 ballots, replied, and voted again. sys moved from 3a to 3b. **Result: 4-2 for 3b** (plt and min dissent). The 3b voters asked that the fixes be a floor ("at least") and that the `.is_none()` fix fire only for a bare `None` literal operand; the spec text follows both. min asked that the record cite §8.6, which already requires machine-applicable fixes on every error.

**Systems:**

> ##### Systems: Phase D, Q3
>
> ###### Reply
>
> min: "Fix hints change as tooling improves. If they are normative, each improvement becomes a spec change." That applies to wording, and 3b keeps the wording free. 3b fixes only two *kinds* of fix: `@derive(Eq)` and `.is_none()`. Both are features the spec already defines. They change only when the language changes, and then the spec changes anyway. A new hint added later needs no spec edit, because 3b sets a floor, not a closed list.
>
> devops: "If the hints are non-normative, they will be left out of the first version and stay missing." All three 3a ballots, mine included, named that same risk as their concern ("may never ship unless the implementation ticket lists them"). When every voter on one side names the same failure, and the other option removes it at almost no cost, the other option wins.
>
> web: "the rule can grow into a list of special cases." That risk is real but small. Each future hint must point to a spec'd feature to qualify, and that limits the growth.
>
> devops's own concern, that the `.is_none()` hint should fire only for a bare `None` literal operand, belongs in the spec text for 3b. It is a testable condition, and it stops the hint from pointing at the wrong fix.
>
> This question has no runtime cost either way, so my domain does not decide it. The deciding factor is which option leaves fewer broken promises.
>
> ###### Final vote
>
> **Vote.** 3b (changed from 3a), with the `.is_none()` hint limited to a bare `None` literal operand.
>
> **Reasoning.** The property plus the two fix kinds can all be tested, and both fixes point only to spec'd features. The wording stays free. 3b removes the one failure that every 3a voter named, and it costs one extra spec sentence.
>
> **Concern.** Implementers may read the fix kinds as a closed list and block better hints. The spec should say "at least".

**Web/Scripting:**

> ##### Web/Scripting panelist: Phase D, Q3
>
> ###### 1. Replies to the 3a side
>
> min: "If they are normative, each improvement becomes a spec change."
> Not so. 3b fixes the *kinds* of fix, not the wording. An implementation can improve the text or add new hints with no spec change. Only *removing* the `@derive(Eq)` or `.is_none()` hint would need a spec change, and that is exactly the change I want to be hard.
>
> sys: "If the hints stay non-normative, the `.is_none()` hint may never ship, so the implementation ticket must list it." plt says nearly the same.
> All three 3a votes name the same risk: the hints may never ship. A ticket is local, gets closed, and is not training data. The spec is what the next implementer, the LSP author and the LLM read. If all six of us agree the hints must ship, the one durable place to say so is the spec.
>
> plt: "A spec should state properties that can be tested, not user-interface text."
> The 3b hints can be tested. "The diagnostic offers `@derive(Eq)` on the failing user type" is a yes/no check on structured output, the same as "names the innermost type". Rust's reference and Elm's design both treat error quality as part of the language contract, and those two languages have the best reputations for errors.
>
> My own concern still stands: `.is_none()` is specific to Option. If the panel wants, I accept this amendment to 3b: "offers a fix when a standard one exists (for example `@derive(Eq)` on a user type, `.is_none()` for a bare `None` operand)". It keeps the promise and drops the closed list. devops' limit to a bare `None` literal should go in the text.
>
> ###### 2. Final vote
>
> **Vote:** 3b
> **Reasoning:** For a JS or Python developer, the error message is the documentation for `==`. Everyone on the panel agrees the two hints must ship. 3b puts that agreement in the one durable place, and it still leaves the wording free.
> **Concern:** If the hint list is closed, it can grow into a list of special cases per carrier. Wording the rule as "offers a standard fix, for example ..." avoids this.

**PLT *(dissent)*:**

> ##### PLT — Phase D (Q3)
>
> ###### Reply to the 3b side
>
> devops: "If the hints are non-normative, they will be left out of the first version and stay missing." That is a process risk, not a language property. The fix is a line in the implementation ticket with a test on it. All three 3a voters already asked for that line in our Phase C concerns. A spec clause does not make the hint ship any more than a ticket with a test does.
>
> aiml: "The property and the fix kinds must be normative so that every tool gives them." Part of this I accept. "Offer `@derive(Eq)` when the failing type is a user-defined type" is a testable property, and it follows from the typing rule: it names the one way to add the missing instance. The `.is_none()` hint is different. It is a heuristic keyed to one syntactic shape (a bare `None` literal) of one carrier. devops's own concern shows the edge: "it can point users at the wrong fix. The implementation ticket must limit it to a bare `None` literal operand." A rule that needs that kind of narrowing is a lint, not language semantics. web states the cost: "the rule can grow into a list of special cases."
>
> web: "no implementation can ship a bare 'type mismatch' again." 3a already rules that out. A message that names only "List[Int] and List[Int]" fails the property "names the innermost type argument that has no Eq".
>
> Both sides want the same fixes to ship, so this is a question of where the fixes live. Semantics go in the spec, and heuristics go in the tooling contract.
>
> ###### Final vote
>
> **Vote:** 3a
>
> **Reasoning:** The normative clause must be a property of the typing judgement: which instance fails to resolve. 3a states exactly that, and it already bans today's false message. 3b ties a carrier-specific syntactic heuristic (`.is_none()`) to the language definition, so every later improvement to hints becomes a spec change.
>
> **Concern:** If the implementation ticket does not list both hints with tests, they may never ship. The decision record should link that ticket as a required follow-up.

**DevOps:**

> ##### Phase D — Q3, DevOps/Tooling
>
> ###### 1. Replies
>
> min: "If they are normative, each improvement becomes a spec change."
> Under 3b the spec says which *kinds* of fix the error must offer, with free wording. It is a floor, not a ceiling. Better wording, a new hint, or a quick-fix in the LSP all fit inside 3b and need no spec change. Only removing one of the two hints needs a spec change, and removing either would make the tool worse.
>
> plt: "A spec should state properties that can be tested, not user-interface text."
> "When the failing type is a user type, the error offers `@derive(Eq)`" can be tested in exactly the same way as "names the innermost type". A test checks the diagnostic's fix list, not its text. Both are properties, so plt's rule does not tell 3a and 3b apart.
>
> sys, plt, min all state the same concern: the hints "may never ship unless the implementation ticket lists them."
> All three 3a voters predict the failure that 3b prevents. An implementation ticket is local-only and can be closed in part. The spec is what gets read later, by implementers of another toolchain and by models trained on this repo. Today's "incompatible types List[Int] and List[Int]" shipped because no normative text asked for more.
>
> web: "the rule can grow into a list of special cases."
> It is a real risk, and it is why 3b lists only two hints, both tied to this decision. Any new hint needs its own vote.
>
> ###### 2. Final vote
>
> **Vote:** 3b
>
> **Reasoning:** The fix hint is the part of an error that users, the LSP quick-fix and LLMs act on. Each 3a voter says the hints are wanted but may not ship. 3b makes the two hints this decision creates a testable floor, and leaves the wording free. It costs one sentence in the spec.
>
> **Concern:** If 3a wins, the decision record must still name both hints as required in the implementation ticket, with tests that check the fix list. If it does not, the concern that all six of us wrote comes true.

**AI/ML:**

> ##### AI/ML panelist: Phase D, Q3
>
> ###### Reply to the 3a side
>
> plt: "A spec should state properties that can be tested, not user-interface text." With 3b the fix is testable. The test is "the structured diagnostic has a `fix.edits` entry that inserts `@derive(Eq)` above type X". That is a property, not a string. The exact wording stays non-normative under 3b.
>
> sys and min: "Fix hints change as the tooling changes, so they belong in the implementation ticket." The spec already makes fixes normative. sections/06_tooling.md §8.6 says "Errors include machine-applicable fix suggestions that an AI agent can apply directly". It also says the AI fix loop "is mechanical, not inferential" (06_tooling.md:1846). The spec also names the exact fix for a diagnostic: W1401 carries "a machine-applicable fix that inserts the sort" (06_tooling.md:1348). 3b follows that pattern. 3a would be the exception.
>
> min: "If they are normative, each improvement becomes a spec change." Only if the text is written as a closed list. Write it as a floor: "offers at least these fixes". A new hint then needs no spec change. Only removing one of these two does, and that should need a spec change.
>
> sys, plt and min all give the same concern: under 3a the hints "may never ship unless the implementation ticket lists them". All three name the risk, and 3b removes it. A ticket can be closed without a hint. Spec text cannot be dropped that way.
>
> ###### Final vote
>
> **Vote:** 3b, with the fixes stated as a floor ("at least").
>
> **Reasoning:** The spec already promises a mechanical fix loop for AI agents (§8.6). For a failed Eq check, the fix is nearly always one of two edits: add `@derive(Eq)`, or write `.is_none()` in place of `== None`. If the spec names the failing type but not these two fixes, it breaks that promise for the most common error this decision creates.
>
> **Concern:** devops's point stands. The `.is_none()` fix must fire only when one operand is a bare `None` literal. Otherwise the fix is wrong, and a model applies wrong fixes without question.

**Minimalism *(dissent)*:**

> ##### Minimalism panelist: Phase D, Q3
>
> ###### Reply to the 3b side
>
> Devops: "If the hints are non-normative, they will be left out of the first version and stay missing."
> Web: "no implementation can ship a bare 'type mismatch' again."
>
> The spec already covers this. sections/06_tooling.md §8.6 says: "Errors include machine-applicable fix suggestions". So a failed-Eq error with no fix already breaks the spec under 3a. 3b adds a second, narrower copy of a rule the spec already has. Two rules that say nearly the same thing drift apart over time. That is the cost I object to.
>
> In fairness to 3b, the spec does name specific fixes in some places. W1401 in §9 names its sort-insert fix. So a normative fix has a precedent, and my Phase C claim that fixes "do not belong in the spec" was too broad. The better test is whether the fix is part of the rule. The sort for W1401 is part of that rule. `.is_none()` is not part of the Eq rule. It is advice about Option style.
>
> Web: "The `.is_none()` hint is specific to Option ... the rule can grow into a list of special cases."
> This is the reason I stay on 3a. Once one carrier-specific hint is normative, each new carrier asks for one too, and each hint becomes a spec edit.
>
> aiml: "Implementers may treat the fix hints as optional if the tests do not check them."
> Tests enforce this, not the spec. The implementation ticket should carry the fix kinds as acceptance tests. I ask that the decision record say so.
>
> ###### Final vote
>
> **Vote:** 3a
>
> **Reasoning:** The spec states the one property that tools can test: the error names the innermost type without Eq. §8.6 already requires a machine-applicable fix, so 3b's main worry is covered without new text. The concrete fixes (`@derive(Eq)` for a user type, `.is_none()` for a bare `None` operand) go into the implementation ticket as acceptance tests. The decision record should cite §8.6 so that no reader treats the fixes as optional.
>
> **Concern:** If the implementation ticket does not list the two fix kinds as tests, §8.6 alone is too general to make them ship.

### Final Spec

```blink
@derive(Eq)
type Point { x: Int, y: Int }

fn same[T: Eq](a: Option[T], b: Option[T]) -> Bool {
    a == b                       // needs T: Eq
}

fn main() {
    let same_list = [1, 2] == [1, 2]                        // true: List[Int] is Eq
    let p = Some([Point { x: 1, y: 2 }]) == Some([Point { x: 1, y: 2 }])  // true
    io.println("{same_list} {p}")
}
```

- `Option[T]`: `Eq` when `T: Eq`. `Result[T, E]`: when `T: Eq` and `E: Eq`. `List[T]`: when `T: Eq`. `Set[T]`: always. `Map[K, V]`: when `V: Eq`. `Bytes`: always, byte-wise, no `Ord`. Tuples: per the tuple vote.
- `==` compares values and never identity. `Set` and `Map` compare by membership; order is not part of the value.
- `==` on a container of a type parameter needs the bound: `Option[T] == Option[T]` needs `T: Eq`.
- A failed `Eq` check names the innermost type with no `Eq` and the chain to it, and offers at least `@derive(Eq)` (user type) and `.is_none()` (bare `None` operand). Wording is not normative.
- `Set` and `Map` never implement `Ord`. Other container `Ord` stays open.
- `Eq` impls must be reflexive, symmetric and transitive; the compiler may rely on this. A broken user impl gives an unspecified `Bool` and stays memory-safe.
- `==` on cyclic data may not terminate; no cycle guard.
- `assert_eq`/`assert_ne` enforce `T: Eq` with the same check as `==`.
- Interim: an enum with no `Eq` impl or derive is `Eq` only if every payload type is `Eq`; payload-free enums are `Eq`. Whether data enums must write `@derive(Eq)` is an open question for a separate decision.

Spec: §3.6 *Container Equality* and the *Built-in Type Trait Implementations* table (sections/03_types.md), §3.2 *The Contains Trait*, §3.6.1 *Generic Type Bound Inference*, §2.20 *Built-in Assertions* (sections/02_syntax.md).
