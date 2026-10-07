[< All Decisions](../DECISIONS.md)

# List Capacity — Design Rationale

`List` had only `List.new()`. A program that pushes one element at a time to a size it already knows pays for doubling slack and for realloc copies. The compiler's AST node pool profile measured column chunk growth at about 30% of all bytes allocated, with 41,760 reallocs. Presizing the columns would remove about 20% of all bytes allocated.

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in independent-proposal → debate → vote rounds.

Panelist text below is quoted verbatim. Cuts of whole sentences or paragraphs are marked with "…". Option labels used in the ballots: Q1 A = add `List.with_capacity(n)`. Q2 A = add `reserve(n)` now, B = defer. Q3 A = public `capacity()` with a weak contract, B = not exposed, and reword `clear` as non-normative. Q4 A = `n < 0` panics, B = `n <= 0` acts like `new()`. Q5 A = defer `Map`/`Set` capacity. Q6 A = one `n < 0` rule for every `with_capacity` constructor, stated once in a shared place.

#### Phase A — Independent proposals

- **Systems:** Proposal 1 (primary): `List.with_capacity(n)`, plus `capacity()` and `reserve(n)`

  ```blink
  let mut cols: List[Int] = List.with_capacity(node_count)
  assert(cols.len() == 0)          // capacity is not length
  assert(cols.capacity() >= node_count)

  let mut q = List[Int].new()      // existing path
  q.reserve(1000)                  // mut self: ensure capacity >= len() + 1000
  ```

  - `with_capacity(n)` returns an empty list with `len() == 0` and `capacity() >= n`. It allocates the backing store once.
  - There is no general zero value for `T`, so a "length n" constructor is not possible without a fill value. Reject `List.zeroed(n)` for `List[T]`. `BytesBuilder.zeroed` is fine because the element type is fixed.
  - `n < 0` panics, the same as `List.set` out of bounds. `n == 0` is the same as `new()`. Silent clamping hides bugs. `n` is a hint, so allocation failure follows the existing OOM path.
  - `reserve(n)` has "additional" semantics, like Rust: it guarantees `capacity() >= len() + n`. This is the right primitive for a list that already holds elements. It is also a no-op when capacity is enough, and it never shrinks.
  - `clear()` already retains capacity. That stays unchanged, and it makes a reused scratch list zero-alloc.
  - `capacity()` is public and read-only. It mirrors `StringBuilder.capacity()`, which is already decided, and it lets tests assert that presizing works. Without it, nobody can verify the guarantee. It does not weaken the "methods only" API rule.

  Proposal 2 (fallback, minimal): `with_capacity` only. Ship `List.with_capacity(n)` and `capacity()`. Defer `reserve`. This covers the blinkc case, where every column size is known at creation. It is the smallest ABI change.

  Scope for Map and Set: … YAGNI says to ship List now and file a follow-up for Map and Set once a profile shows the cost. The follow-up must not diverge in naming from `with_capacity`. I vote List-only for now, with the name fixed so Map and Set can follow.

  Rejected shapes:
  - **`List.filled(n, v)` or `List.repeat`:** it is a different feature. It sets `len`, and it needs `T` to be copyable or a closure.
  - **`list.set_capacity(n)` with shrink:** this lets users shrink, which is a trim operation. It is not needed yet.
  - **Compiler-inferred presizing:** this is hidden cost and unpredictable codegen. I reject it on principle.

  Cross-language note:
  - **Rust:** `Vec::with_capacity` and `reserve`. `reserve` is additional-based, and `capacity()` is public. This is the same shape as my proposal.
  - **Go:** `make([]T, 0, n)` and `slices.Grow`.
  - **Zig:** `ArrayList.initCapacity` and `ensureTotalCapacity`.
  - **C++:** `vector::reserve`.

  Every systems language ships both a constructor and a reserve method.

  Vote summary: I vote for Proposal 1, with `with_capacity`, `reserve` (additional semantics), and a public `capacity()`. Negative `n` panics. Scope is List only, with the Map and Set name reserved.

- **Web/Scripting:** Proposal A (recommended): `List.with_capacity(n)` only, with no `reserve` and no public `capacity()`

  ```blink
  let mut cols: List[Int] = List.with_capacity(node_count)
  for i in 0..node_count {
      cols.push(i)
  }
  cols.len()   // 0 right after with_capacity, 1 per push
  ```

  - `with_capacity(n: Int) -> List[T]` returns an empty list. `len()` is 0, and `n` is a hint for the first allocation.
  - `n <= 0` is not an error. It behaves like `List.new()`. A hint should never crash, and Python's `[]`, Kotlin's `ArrayList(0)` and Rust-style sizing code all treat it as a no-op. A panic on a performance hint would be a footgun.
  - A huge `n` is the one real risk. The runtime should clamp it, or abort with the existing OOM path.
  - `clear` already retains capacity. That matches the `StringBuilder` precedent, so the model stays consistent.

  Why no `reserve`: Every blinkc case in the ticket is "I know the final size up front." That is a constructor shape. `reserve` is a second way to do the same thing. JS and Python developers do not expect one, because neither language has it. Each extra method is another "which one do I use?" Stack Overflow question.

  Why no public `capacity()`: In JS and Python, nobody asks a list for its capacity. Exposing it invites `if list.capacity() > x` logic that depends on allocator details. It also makes the doubling policy observable, which becomes a de facto compatibility promise. … If the panel wants symmetry, accept `capacity()` as the fallback in Proposal C below.

  **Cross-language note:** Rust has `Vec::with_capacity`. Java has `new ArrayList<>(n)`. Go has `make([]T, 0, n)`. Kotlin has `ArrayList(n)`. Python and JS have none. Developers coming from the languages that have one will look for exactly `with_capacity`, so use that name.

  Proposal B: a filled constructor, named `List.filled(n, value)`, as a separate and later question.

  ```blink
  let mut counts = List.filled(256, 0)   // len() == 256
  ```

  - This is the Python `[0] * n` and JS `Array(n).fill(0)` case. It is a different feature: it changes `len()` and needs a value, and Blink has no default `T`.
  - Do not fold it into this ticket. If it is added later, it must copy by value for value types. A shared `value` for cell types (List, Map) would alias, which is the classic Python `[[]] * n` bug.

  Proposal C (fallback): A plus `capacity()` only.

  ```blink
  let l = List.with_capacity(100)
  l.capacity()   // >= 100
  ```

  - Contract: "at least n". It is not exact, and never less than `len()`.
  - Accept this only if the panel values symmetry with `StringBuilder` and testability. A test cannot otherwise prove the hint took effect.
  - The cost is the observability point above.

  Map and Set: Do not add `with_capacity` to Map or Set in this ticket. There is no evidence for them in the profile, and YAGNI applies. Reserve the name: if either is added later, it uses the same `with_capacity(n)` shape.

  Summary vote:
  1. Adopt `List.with_capacity(n)`.
  2. No `reserve`.
  3. No `capacity()` (C is acceptable if the panel insists).
  4. `n <= 0` is a no-op hint, not a panic.
  5. Map and Set are out of scope.
  6. `filled` is a separate future ticket.

- **PLT:** Position: Add `List.with_capacity(n)` and `capacity()`. Do not add `reserve`. Do not add Map/Set variants yet.

  ```blink
  let mut cols: List[Int] = List.with_capacity(node_count)
  assert(cols.len() == 0)
  assert(cols.capacity() >= node_count)
  for i in 0..node_count {
      cols.push(i)          // no realloc until len() > capacity()
  }
  cols.clear()              // len() == 0, capacity() unchanged (already specified)
  ```

  - The result has `len() == 0`. It is an ordinary empty list.
  - **Capacity is not part of the value's semantic content.** It is a performance hint, so `List.with_capacity(n) == List.new()` under structural equality, and the two lists are interchangeable at every type. Only `capacity()` can tell them apart.
  - `capacity()` has a weak contract: `capacity() >= len()`, and after `with_capacity(n)`, `capacity() >= n`. It is not `== n`. This lets the runtime round up without breaking the spec. StringBuilder's "sets the initial capacity to n" is stronger than needed.
  - `n < 0` is a precondition violation and panics, as `set` does for OOB. The alternative is to clamp to 0. Clamping hides a bug, and that is unsound as a contract, so I reject it. `n == 0` is legal and equals `new()`.
  - If `n` is huge and allocation fails, the existing allocation-failure path applies. No new error channel.

  Why not `reserve`: `reserve(mut self, n)` is a second way to do the same thing. … If a real case appears where the size is learned after construction (growing a table in phases), add `reserve` then. YAGNI. Record it as deferred, not rejected on principle.

  Proposal B (fallback if capacity() is contested): constructor only, no `capacity()`. … Tradeoff: I reject this. The spec already promises `clear()` "retains capacity" for List (lines 483, 578). A promise with no observer cannot be tested, so a conforming test cannot check the runtime. `capacity()` is what makes the contract falsifiable. It costs one read-only method, and StringBuilder has the precedent.

  Map and Set: Defer. The ticket's evidence is all List (the node pool). Map has a hash-table sizing question (load factor: does `n` mean entries or buckets?) that needs its own decision. Settle List's semantics first (`>= n` entries) and extend only when a profile shows the need.

  Cross-language:
  - Rust: `Vec::with_capacity`, `reserve`, and `capacity()`, with the contract "at least n". The same weak contract as proposed here.
  - Go: `make([]T, 0, n)`. Capacity is observable through `cap()`, and aliasing makes it a semantic hazard. Blink's cells avoid that.
  - OCaml `Array.make` and Haskell `Data.Vector.new` require an initial element or a fill. We deliberately do not, because Blink has no default `T`. This is why `with_capacity` yields an empty list and not a length-n list. Do not add a `List.filled(n, x)` here. It is a separate question.
  - Koka: no capacity API in the core. Not a precedent either way.

- **DevOps/Tooling:** Proposal A (recommended): `List.with_capacity(n)` only. No `reserve`, no `capacity()`.

  ```blink
  let mut cols: List[Int] = List.with_capacity(node_count)
  cols.len()        // 0, always
  cols.push(1)      // no realloc until n pushes
  ```

  - `len()` is 0 after construction. There is no fill value, because Blink has no default `T`.
  - `n <= 0` gives the same result as `List.new()`. It does not panic. A hint must not crash a program, and the n=0 case comes up naturally when the count is computed.
  - It matches `StringBuilder.with_capacity` and `BytesBuilder.with_capacity`, so the model has one rule: `Type.with_capacity(n)`.
  - **Diagnostics:** a negative literal argument is not an error. A lint is the right place for a bad hint, not an error code. The profile data says the common mistake is the missing hint, not a wrong one.

  Proposal B (add on top of A, only if the panel wants it): `reserve(n)` as a `mut self` method. … My view: do not ship B now. YAGNI. The 20% saving in the ticket comes from presizing at construction. Add `reserve` when a real case shows `with_capacity` cannot reach it.

  Proposal C: expose `capacity()` on List. I reject it. It exposes allocator behavior. Programs would branch on it, and then the growth policy becomes part of the spec. … The test for `with_capacity` can use the allocation counter from the runtime, not `capacity()`.

  Proposal D: Map and Set scope. Defer. No evidence in the ticket. The profile names only List columns. Add `Map.with_capacity` and `Set.with_capacity` when a profile shows them, using the same name and rules as A. State the rule now in the spec so the name is reserved: "`with_capacity(n)` on any collection is a size hint; `len()` is 0".

  Cargo-cult risk (the AI/ML worry): A GC does not remove the cost of realloc copies. The ticket's numbers prove it: 93 MB of slack. Put the guidance in `blink llms`: "Use `with_capacity` only when you know the final count. Do not use it for small lists."

  **Cross-language:** Rust has `Vec::with_capacity` and `reserve`. Go has `make([]T, 0, n)`. Java has `new ArrayList<>(n)` and `ensureCapacity`. C# has `new List<T>(n)` and `EnsureCapacity`. All of them keep `len` at 0 and treat capacity as a hint. A needs only the constructor, which is the common subset.

  **Vote:** A yes, B defer, C no, D defer with name reserved.

- **AI/ML:** Position: Add `List.with_capacity(n)` only. Do not add `reserve`. Do not add `capacity()` to List. Do not touch Map or Set. This reverses my StringBuilder dissent for one reason: StringBuilder is a convenience type where a hint is optional. Here the evidence is measured.

  ```blink
  fn build_columns(count: Int) -> List[Int] {
      let mut kinds = List.with_capacity(count)
      for i in 0..count {
          kinds.push(i * 2)
      }
      kinds
  }

  let mut empty: List[Str] = List.with_capacity(0)   // same as List.new()
  ```

  - Spec text: `with_capacity(n: Int) -> List[T]` returns an empty list. `len()` is 0 and the backing store has room for at least `n` elements. Indexing still obeys `len()`, so `get(0)` is `None` and `set(0, x)` panics.
  - `n < 0` panics. A silent clamp hides arithmetic bugs.
  - `n == 0` is the same as `new()`.
  - `n` is a hint. Pushing past `n` grows the list as usual and is never an error. The spec must say this explicitly, or models will treat `n` as a hard limit and add guards.

  There is no `capacity()` getter, so a model cannot write capacity-checking logic. This is the largest cargo-cult risk, and the ticket gives no use for it. StringBuilder has `capacity()`, so the asymmetry should be explained in one line of the spec.

  Proposal B (fallback if the panel wants a reserve-style method): `reserve` only on an existing list. … I would defer it under YAGNI until a blinkc case needs it. `reserve(n)` would mean "room for n more elements", as in Rust. The Java `ensureCapacity(total)` meaning is a different one, which is a real ambiguity risk for models.

  **Proposal C (reject):** Do nothing and keep `new()` only. This fails the correctness bar in CLAUDE.md. The compiler cannot show good practice when the language lacks the tool, and the spec gap is real.

  **Map and Set:** Out of scope. The ticket has no evidence for them, and their growth involves rehashing, so a hint has different semantics. Defer until a measured case appears.

  **Cross-language:** Rust `Vec::with_capacity` and `reserve`, Go `make([]T, 0, n)`, Java `new ArrayList<>(n)`, C# `new List<T>(n)`, Python has none. All four statically typed languages use a constructor form, so the constructor is the dominant signal.

- **Minimalism:** Add List.with_capacity(n) only. Reject reserve, capacity(), and Map/Set capacity.

  ```blink
  fn with_capacity[T](n: Int) -> List[T]   // static, on the type name; len() == 0

  let mut kinds: List[Int] = List.with_capacity(node_count)
  for i in 0..node_count {
      kinds.push(i)   // no realloc
  }
  kinds.len()         // grows from 0, never from n
  ```

  Do we need it? Yes, narrowly. The language cannot express "I know the size, allocate once". The blinkc data is the evidence: about 20% of all bytes allocated, with 41,760 reallocs. A convention cannot fix this. A stdlib library cannot fix it either, because List is a compiler-known cell and the allocation lives in the runtime.

  - n is a hint, not a contract. n <= 0 behaves like List.new(). I would not panic on a negative n. A panic adds a failure mode to a pure optimisation hint, and the hint should never change behaviour.

  PROPOSAL 2 (reject): reserve(n). … It also adds a mut method and a growth-arithmetic question: does n mean total capacity or additional room (Rust's reserve adds, Go's slices.Grow adds)? … We can add a method later; we cannot remove one.

  PROPOSAL 3 (reject): List.capacity(). This is the main point where I differ from the StringBuilder precedent. … For List, capacity() is observable runtime state with no semantic meaning. It invites code that branches on it and tests that assert on it. That locks the growth policy into the spec, which breaks the "spec is blueprint, no implementation details" rule. … Fallback if the panel insists: add capacity() with only the guarantee capacity() >= len(), and say nothing else about growth.

#### Phase B — Debate highlights

Three panelists changed position.

**Systems moved to defer `reserve` (Q2 B):**

> I move to 2b: defer `reserve`. My Phase A argument was that it costs almost no code, and that is true. But the ticket evidence is all constructor-shaped, and Web is right that every blinkc case knows the final size when it creates the list. Min's point also holds. We can add a method later, and we cannot remove one. The "total or additional" ambiguity is a real trap, and no profile row needs it today. Defer it, and record in the decision that `reserve` is open if a real case appears.

**DevOps moved to `capacity()` A (Q3):**

> I move to 3a. PLT's point changes my vote: the spec already says `clear()` "retains capacity". That sentence is a promise nobody can test. `StringBuilder.capacity()` also sets the pattern. My earlier fear was that the growth policy becomes spec. A weak contract removes that fear. The contract must say:
> - `capacity() >= len()`.
> - `capacity() >= n` after `with_capacity(n)`.
> - `capacity()` after `clear()` is not less than before `clear()`.
> - No promise on the growth factor, and none on the exact value.
>
> I accept 3a only with this weak contract. If the panel picks 3b, the spec must drop or reword "retains capacity" in `clear`. I do not want a promise with no observer.

**PLT moved from panic to no panic on `n < 0` (Q4 A to B):**

> I move to 4b (no panic). Min's argument changes my position. I called a negative `n` a precondition violation, treating `with_capacity` as a normal total function. But I also said capacity is not part of the value's semantics. If so, the hint must not change observable behavior. A hint that can panic contradicts that.
>
> I now propose this: `with_capacity(n)` for `n <= 0` is equivalent to `List.new()`. The spec states this as a rule, not as hidden clamping: "`n` is a hint only. Non-positive `n` means no preallocation." … It also gives one rule for all three: a hint cannot fail, an allocation failure on a huge `n` uses the existing OOM path, and nothing else can go wrong.
>
> AI/ML's worry that a silent path hides arithmetic bugs is valid. But a size computation that goes negative has a real bug upstream, and the bug will show up where the size is used, not where it is passed as a hint. A debug-mode assert is a possible compromise. I would not require it.

**Systems held Q3 A (PLT held it too):**

> I hold 3a. The spec already says `List.clear` "retains capacity" at lines 483 and 578. A promise nobody can observe cannot be tested. The 3b side suggests testing with the runtime allocation counter. That counter is a runtime internal. A spec-level guarantee needs a spec-level observer.

**Systems held Q4 A (panic) (dissent):**

> I hold 4a: panic. Min's argument is that a hint should never change behaviour. A negative `n` is not a bad hint. It is an arithmetic bug at the call site, such as `count - done`. Silent acceptance hides it, and the program then runs slower with no error.
>
> Two facts support the panic:
> - `List.set` out of bounds already panics, so there is a precedent.
> - `StringBuilder.with_capacity` leaves negative `n` unspecified. This decision should fix it for both types in the same wording, so I propose a spec line for each.
>
> If the panel prefers 4b, I can accept it. The condition is that the spec states it. Unspecified behaviour here would be the worst case.

**AI/ML held Q4 A (panic) (dissent):**

> 4a, panic, but I yield on this. My AI/ML reason is weak here. Models rarely compute a negative `n`. The real question is consistency. `set` out of bounds panics, so a negative `n` panicking is the same class of programmer error. Min's point about a hint not changing behaviour is fair, but a negative size is an arithmetic bug and not a hint. Keep 4a. I would not block on 4b.

**Minimalism held Q3 B (dissent):**

> 3b, not exposed. I accept PLT's point that "clear() retains capacity" is untestable without an observer. My answer is to make that prose less strong, not to add a getter. Concretely, reword List.clear and Map.clear to "Reset to empty" and drop the capacity promise, or keep it explicitly non-normative. A spec promise nobody can observe should not drive a new public method. … If the panel votes 3a, I will accept the weak contract (capacity() >= len(), and >= n after with_capacity(n)) and nothing more, and no growth-factor text.

**Minimalism on Q4 and a shared rule:**

> 4b, no panic. … A panic on a hint turns a perf optimisation into a crash path, and a computed n such as `count - skipped` could go negative in a case where the code was otherwise correct. If the panel picks 4a, I'd ask that it also apply the same rule to StringBuilder.with_capacity, which the spec leaves unspecified. Whichever way it goes, the two constructors must agree, and the spec should state the rule once in a shared place.

**Web held Q3 B (dissent), with a fallback:**

> 3b, with a change. … Testability does not need a public method. A runtime allocation counter, or a compiler-internal test hook, can check that the hint took effect. … If PLT insists it must be testable from Blink, I accept 3a as the fallback, with these limits.
>   - The contract is `capacity() >= len()`, and `>= n` after `with_capacity(n)`.
>   - The docs say it is for diagnostics and tests only.
>   - It is not a growth-policy promise. No doubling factor is documented.

**AI/ML held Q3 B (dissent), with a fallback:**

> 3b, not exposed. I accept 3a with the weak contract as a fallback. … The "clear retains capacity" promise has no observer, but the spec can drop the promise as a guarantee. Reword it to "may retain storage", which makes it an implementation note and not a contract. … If 3a wins, the spec should say "capacity() >= len(), no other guarantee, do not branch on it."

**Web held Q4 B:**

> 4b, `n <= 0` acts like `new()`. I hold this position, with one adjustment to weigh the Sys/PLT/AI-ML argument that a silent clamp hides arithmetic bugs. That argument is true for correctness values. A capacity hint is different: an off-by-one in `n` cannot change program output. It can only change speed. Panicking turns a harmless inaccuracy into a crash at runtime, and this is the one place where a JS/Python developer would be surprised by a crash.

**DevOps held Q4 B:**

> 4b, same as `List.new()` with no panic. … A static lint for a negative literal is cheap and can come later. One request: the spec must state the `n < 0` behavior for `StringBuilder.with_capacity` and `BytesBuilder.with_capacity` too. Today it is not specified. All three constructors must behave the same way. I suggest this be part of this decision.

#### Phase C — Final vote

- **Q1: add `List.with_capacity(n)` — empty list, `len()` is 0, `n` is a hint (6-0)**
  - **Systems:** A — One allocation of `n * sizeof(T)` replaces the doubling reallocs and their copies. The ticket cites about 20% of all bytes allocated, and per-column slack of 62% at 324K nodes. Every systems language has this constructor, and the header already has a `cap` field, so the ABI change is small. (Concern: Users may pass inflated hints, and the GC then scans that unused memory.)
  - **Web/Scripting:** A — It is the smallest change that removes about 20% of allocated bytes. `with_capacity` is the name that Rust, Java, Go and Kotlin developers will look for, and it matches `StringBuilder` and `BytesBuilder`. It also fits the static-constructor rule. (Concern: Models and new users will add it to every list by default, so the docs must say to use it only when the final size is known and large.)
  - **PLT:** A — The constructor adds no typing rule and no effect. It yields an ordinary empty list, because capacity is not part of a list's semantic content. The blinkc evidence is all "size known up front", which is exactly what a constructor covers. It also follows the §3.2 rule that constructors are static methods on the type name. (Concern: Models may copy `with_capacity` into code where the size is unknown or tiny. The cost is harmless over-allocation, but it is noise.)
  - **DevOps/Tooling:** A — One name, `Type.with_capacity(n)`, now works across `StringBuilder`, `BytesBuilder` and `List`. LSP completion and docs stay predictable. The ticket data shows about 20% of allocated bytes are removable. (Concern: Models may copy `with_capacity` onto small lists where it gains nothing, so the `blink llms` text must say to use it only when the final count is known.)
  - **AI/ML:** A — The measured slack is about 20% of bytes in the compiler that serves as training data. The constructor follows the static-method rule and matches Rust, Java, C# and Go, so a model can learn it from the spec alone. It adds one decision point, "is the size known?". (Concern: Models may copy `with_capacity(n)` into code where `n` is not known, which wastes memory. A one-line spec note ("use only when the size is known") limits this.)
  - **Minimalism:** A — The language cannot express "allocate once for a known size". The blinkc profile shows about 20% of allocated bytes and 41,760 reallocs, and neither a convention nor a library can fix this, because the allocation is in the runtime. It adds no new concept: it copies StringBuilder.with_capacity and BytesBuilder.with_capacity. (Concern: Models may cargo-cult it in code where the size is unknown; the docs should say "only when the final size is known".)

- **Q2: `reserve(n)` — B, defer (6-0)**
  - **Systems:** B — Every case in the ticket knows the final size at construction. I find no evidence for a populated-list reserve. "Additional" versus "total" is a real ambiguity trap, and adding a method later is cheap. Removing one is not. (Concern: A burst-growth workload will have to rebuild the list or push one element at a time until `reserve` is added.)
  - **Web/Scripting:** B — Every case in the ticket is a known final size, which a constructor covers. A second way to presize adds a "which one do I use?" question. It also invites `reserve(len() + 1)` inside loops. Adding a method later is cheap, and removing one is not. (Concern: A real case such as a bulk `append` onto an existing list may appear soon, and then users will work around the gap by copying into a new list.)
  - **PLT:** B — Every case in the ticket is covered by `with_capacity`. `reserve` would be a second way to do the same job, which the methods-only rule exists to prevent. It also forces an "additional versus total" contract choice with no use case to settle it. A method can be added later and cannot be removed. (Concern: A phased-growth use case may appear, and users will then have to work around the missing method (for example by allocating a new list and appending).)
  - **DevOps/Tooling:** B — Every case in the ticket is "the size is known at construction". The "additional" versus "total" meaning of `n` is a trap, and a method cannot be removed once added. Add it when a real case shows `with_capacity` cannot reach it. (Concern: A struct field list whose size is known only later may force a rebuild of the list, and that could push people to ask for `reserve` soon.)
  - **AI/ML:** B — Every case in the ticket is a constructor shape. A reserve method adds a second way to do the same job, and "additional" against "total" is ambiguous across languages. A method added later costs nothing, but a method removed later breaks code. (Concern: A real case may appear, such as a list held in a struct field, that forces a workaround until `reserve` ships.)
  - **Minimalism:** B — with_capacity covers every case in the ticket. reserve is a second spelling of one intent, and its meaning (total vs additional) is unsettled across languages. A method added later costs nothing, while a method removed later costs a breaking change. (Concern: A real "grow after the fact" case appears and people write workarounds until reserve is added.)

- **Q3: public `capacity()` with a weak contract (A) vs not exposed, reword `clear` as non-normative (B) (3-3 → Phase D)**
  - **Systems:** A — The spec already promises that `clear` "retains capacity" for List and Map. A promise with no observer cannot be tested. The weak contract fixes no growth factor, so the runtime keeps freedom to change its policy. `capacity()` reads a field that already exists, so it costs nothing on the hot path. (Concern: Some programs will branch on `capacity()` anyway, and the doc note will not stop them.)
  - **Web/Scripting:** B — JS and Python developers never ask a list for its capacity. A public `capacity()` tempts programs to branch on allocator details, and it makes the growth policy a de facto promise. Tests can use a runtime allocation counter. Rewording `clear` and `Map.clear` as a non-normative performance note is cheap and honest. (Concern: Without an observer, "retains capacity" can silently regress, since no Blink test can catch it. I would accept 3A, with the weak contract exactly as written, if the panel needs that guarantee.)
  - **PLT:** A — The spec already promises that `clear()` retains capacity (lines 483 and 578). A promise that no program can observe cannot be tested by a conformance test written in Blink. The weak contract (inequalities only) stops programs from relying on the growth policy, and StringBuilder already sets the precedent. Option B turns the promise into non-normative text, which gives up the one property we can actually check. (Concern: Even with the docs warning, some code will branch on `capacity()`. The inequalities then become de facto guarantees, and the runtime loses freedom to shrink or round.)
  - **DevOps/Tooling:** A — The spec already promises that `clear()` "retains capacity". A promise with no observer cannot be tested. `capacity()` makes it testable, and it matches `StringBuilder.capacity()`. The weak contract keeps the growth policy out of the spec. Docs and the hover text must say: "tests and diagnostics only". (Concern: Programs may branch on `capacity()` anyway, and then the exact growth factor becomes de facto behavior.)
  - **AI/ML:** B — A public `capacity()` invites programs and models to branch on it, and then the growth policy becomes part of the contract. The weak contract in 3A limits the damage but does not remove the invitation. Rewording `clear` to a non-normative note makes the spec testable without an observer. (Concern: Without `capacity()`, a test for `with_capacity` needs a runtime allocation counter, and that costs setup.)
  - **Minimalism:** B — capacity() is observable runtime state with no semantic meaning. Programs will branch on it despite the docs, and tests of the growth policy will lock it in. The unobservable "clear retains capacity" promise should be reworded as non-normative, and tests can use the runtime allocation counter. (Concern: with_capacity then has no direct in-language test, so a regression that ignores n would pass silently unless the allocation-counter test exists.)

- **Q4: `n < 0` — A, panic; B, same as `new()` with no panic (4-2, Sys and AI/ML dissent; soft consensus, accepted by the user)**
  - **Systems:** A *(dissent)* — A negative `n` almost always comes from an arithmetic bug, such as `count - done`. Silent acceptance hides the bug and gives a slower program with no error. `List.set` out of bounds already panics, so there is precedent. (Concern: A panic on a performance hint can crash a program in production where a clamp would have only run slower.)
  - **Web/Scripting:** B — A capacity hint cannot change program output, only speed. A panic turns a harmless arithmetic slip into a crash, and a JS or Python developer would be surprised by that. The spec sentence is short: "n is a hint only; non-positive n means no preallocation." (Concern: A silent clamp can hide a real arithmetic bug in the caller's size computation. That bug shows up only as a missed optimisation, which is hard to notice.)
  - **PLT:** B — I have to be consistent about what a hint is. If capacity is not semantic content, a hint must not change observable behavior, and a panic is observable behavior. Stating the rule once ("`n` is a hint only; non-positive `n` means no preallocation") keeps the constructor total and keeps `capacity() >= n` trivially true. Option A treats a performance hint as a partial function. (Concern: A size computation that goes negative is an upstream bug, and it is now silent at the call site. It shows up later, away from where the bug is.)
  - **DevOps/Tooling:** B — The hint must not change what the program does. A panic would add a failure path to a performance hint, and the panic would point at the call, not at the code that computed `n`. For diagnostics, a lint for a negative literal is cheap and can come later. (Concern: A real arithmetic bug in the computation of `n` is hidden, so a silent wrong hint gives a slow program with no message.)
  - **AI/ML:** A *(dissent)* — A negative size is an arithmetic bug, and it matches `set` out of bounds, which panics. A silent clamp hides the bug, and the model that wrote it never sees feedback. The panic message names `n`, so the model fixes it in one step. (Concern: A panic in an optimisation hint can crash a program over a hint miscalculated near zero, such as `count - 1` when `count` is 0.)
  - **Minimalism:** B — n is a hint that must not change behaviour. A panic turns a perf optimisation into a crash path, and a computed n like count - skipped can go negative in code that is otherwise correct. The spec states the rule in one sentence: "non-positive n means no preallocation". (Concern: A negative n from an arithmetic bug goes unnoticed and the presizing quietly stops working.)

- **Q5: `Map`/`Set` capacity — A, defer; same name and shape if added later (6-0)**
  - **Systems:** A — The evidence in the ticket is List only. A hash table rehash costs more than a list realloc, so Map and Set will likely need the same constructor. A profile should drive that, and the name is reserved now. (Concern: Map and Set stay unable to presize until someone files a profile.)
  - **Web/Scripting:** A — The profile has no evidence for Map or Set. YAGNI applies, and recording the name and shape now keeps any later addition predictable. (Concern: The same cost may exist in Map and Set code that nobody has profiled, so users may ask for it soon.)
  - **PLT:** A — The evidence is all List. For Map, `n` could mean entries or buckets, and load factor is involved. That question needs its own decision, and answering it now would be a guess. Reusing the same name and shape later keeps the surface uniform. (Concern: The `with_capacity` surface is inconsistent for a while (List and StringBuilder have it, Map and Set do not), and users may ask why.)
  - **DevOps/Tooling:** A — There is no profile evidence for `Map` or `Set`. Reserving the name and shape now costs nothing and avoids a second design round. (Concern: Map-heavy code in the compiler may show the same slack later, and the language will then lack the feature until another spec change.)
  - **AI/ML:** A — The ticket has no evidence for Map or Set. Rehash costs differ, so the semantics are not obviously the same as List. Same name and shape later keeps the learning cost low. (Concern: The compiler may add a hand-grown Map and hit the same slack, so the gap reopens.)
  - **Minimalism:** A — There is no evidence for it, because the profile only measures List columns. YAGNI applies. The same name and shape can be added when a measured case exists. (Concern: Map-heavy code pays doubling slack until someone files the next ticket.)

- **Q6: one `n < 0` rule for every `with_capacity` constructor, stated once in a shared place (6-0)**
  - **Systems:** A — Three `with_capacity` constructors with three negative-`n` behaviours would be a trap. StringBuilder's rule is unspecified today, so fixing it costs no compatibility. State the rule once in a shared place. (Concern: If StringBuilder callers already pass negative values, a panic would break them, so check the corpus before the change lands.)
  - **Web/Scripting:** A — Three builder-style types with three different negative-`n` behaviours would be a teachable inconsistency. `StringBuilder`'s behaviour is unspecified today, so stating one rule in one shared place fixes a gap at no cost. (Concern: If `BytesBuilder` or `StringBuilder` already panics in the runtime on negative `n`, changing it to a no-op is a behaviour change, and it needs a quick check of the runtime and a test.)
  - **PLT:** A — Three builder-like types with three different `n <= 0` behaviors would be an inconsistency with no justification. The rule should be stated once in a shared place and apply to all of them. StringBuilder's `n < 0` behavior is currently unspecified, so this closes that gap too. (Concern: This changes the current behavior of `StringBuilder.with_capacity` and `BytesBuilder.with_capacity` for negative `n`. The runtime must be checked for a path that panics or misbehaves today, so the change needs a test that pins the behavior.)
  - **DevOps/Tooling:** A — The `n < 0` rule is not specified today for `StringBuilder` or `BytesBuilder`. Three constructors with the same name must act the same way. State the rule once in a shared place in the spec, so docs and the LSP hover can link to it. (Concern: If `StringBuilder.with_capacity` currently panics or wraps on a negative `n` in the runtime, the change to the shared rule is a behavior change, and a test must pin it.)
  - **AI/ML:** A — One rule for all three builders means one thing to learn. A model should not have to remember that `List.with_capacity(-1)` panics and `StringBuilder.with_capacity(-1)` does not. The rule is stated once in a shared place. (Concern: The spec does not currently state the StringBuilder rule, so applying the winner there changes existing behaviour, and code that relies on a negative `n` would break. The implementer should check the corpus first.)
  - **Minimalism:** A — Three constructors with the same name must follow one rule, or we create a trap where one panics and the others do not. State the rule once in a shared place. (Concern: Changing StringBuilder.with_capacity's n < 0 behaviour could alter existing behaviour, so check the compiler and stdlib callers before the change lands.)

Q4 soft consensus: all four majority Concern fields name the dissent's point (the no-panic rule hides an arithmetic bug), so the user (BDFL) accepted the 4-2 result without a Phase D. The follow-up is a lint for a negative literal argument, or a debug-mode assert.

#### Phase D — Round 2 (Q3)

The 3-3 split on Q3 went to a second round. Each panelist saw all six Phase C Q3 ballots, and a fact check: no allocation counter is visible to Blink code today.

- **Systems:**

  > **Strongest point.** `with_capacity(n)` is a performance feature. Its whole contract is a statement about memory, and a statement about memory needs an observer. The last fact in the digest decides this: no allocation counter is exposed to Blink code today. B's testing answer therefore depends on a C-level hook that does not exist at the language level. Without an observer, a regression where `with_capacity` ignores `n` passes every test, the ticket's 20% saving silently disappears, and nobody notices. Min and Web's own concerns name this failure.
  >
  > **Answer to the other side.** They fear programs will branch on `capacity()`. That risk exists, but it is bounded. The weak contract gives only inequalities, so any such branch can only rely on `capacity() >= len()` and `capacity() >= n` after construction. Code relying on those two facts is correct under any allocator policy. The growth factor and exact value stay unspecified, so the runtime can still change them. `StringBuilder.capacity()` already carries the same risk, and the corpus shows no harm. Rewording `clear` as non-normative also makes the spec weaker: it deletes the one promise the spec makes about memory behaviour.
  >
  > **Offer.** If Web and Min need it, I accept a doc line that says "tests and diagnostics only; do not branch on it". I also support a lint warning for branching on `capacity()`, but only as a later follow-up and not as part of this decision.

- **Web/Scripting:**

  > **Strongest point.** Both sides name the same risk: programs will branch on `capacity()`, and the weak contract then becomes a de facto guarantee. Option A has no fix for that. The docs warning does not stop it. Option B's weakness is the lack of an in-language test. But the new fact changes that. No Blink-visible allocation counter exists today. So B's "tests can use a runtime allocation counter" is a C-level tool that only compiler developers can use. A Blink conformance test cannot use it.
  >
  > **Answer to Sys and PLT.** Their untestable-promise argument holds. I did not weigh it enough in Phase C. B is not free, because it leaves the `with_capacity` hint and `clear` retention with no in-language check. A regression that ignores `n` would pass silently.
  >
  > **Answer to Min and AI/ML.** `StringBuilder.capacity()` already exists with the same invitation, and the sky has not fallen. Users who branch on it are rare, because JS and Python developers do not think in capacities. Models rarely write such code unprompted. The cargo-cult risk is `with_capacity` everywhere, which Q1 already accepted.
  >
  > **Revised position: I move to A**, with the weak contract exactly as written. Inequalities only, no growth factor, and the docs say "tests and diagnostics, do not branch on it."

- **PLT:**

  > **Strongest point for A:** The B camp's own Concern fields make my case. Web says "retains capacity can silently regress, since no Blink test can catch it". Min says a regression that ignores `n` "would pass silently". AI/ML says tests would need setup. All three admit that B leaves a performance property that cannot be tested in the language. Under A, the same property is checkable by one inequality (`capacity() >= n`), and that is the only property the contract needs to promise.
  >
  > **Reply to the B camp:** Their strongest point is that programs will branch on `capacity()` anyway and so turn the growth policy into a de facto promise. The weak contract limits this. Only inequalities are guaranteed, and a program that relies on more breaks on a policy change. That is the program's defect, as with any unspecified behavior. B also does not remove the invitation to rely on the runtime's behavior. It removes only the ability to check it.
  >
  > The "tests can use an allocation counter" fact fails on its own terms. No such counter is exposed to Blink code today (the facts you gave). B would therefore have to add a new observer API, a larger surface than one read-only method that StringBuilder already has.
  >
  > Web accepted A with the exact weak contract, so I read A as the one option all six can live with.

- **DevOps/Tooling:**

  > **Strongest point for A:** The B side relies on an allocation counter for tests, and the last message says Blink code has none. So under B, a regression that ignores `n` or drops the retained buffer in `clear` has no in-language test. B also does not remove the risk it names. Programs can already branch on `StringBuilder.capacity()`, and that API has caused no known growth-policy lock-in. The weak contract is a set of inequalities. A program can rely only on the inequalities, so the runtime may change the growth factor, round up, or shrink on `clear` only if the clause "`clear` does not lower capacity" is dropped. That clause is the one promise we choose to keep.
  >
  > **Answer to the B side:** The cargo-cult and branching risk is real. But it is a documentation and lint problem, not a reason to make a promise untestable. We can add a lint for `capacity()` in a branch condition later. Also, B means the language has two different rules for two builders: `StringBuilder` exposes capacity and `List` hides it. For tooling that is a worse surface than one consistent rule.
  >
  > **Fallback:** If the panel picks B, rewording `clear` and `Map.clear` is required, and the `with_capacity` test must use a runtime counter. A would then need no further action.
  >
  > My vote stays A.

- **AI/ML:**

  > **Strongest point for B:** `with_capacity(n)` is specified as a hint, so its effect is a performance property and not a semantic one. A conformance test in Blink cannot check a hint, just as it cannot check that `sort` is O(n log n). Making `capacity()` public turns a performance property into API, and the cost is permanent. Some programs will branch on it, and the runtime then loses its freedom to shrink or round. A removal of a method would be a breaking change, while adding it later costs nothing.
  >
  > **Answer to the A side:** Sys and PLT are right that a promise with no observer is untestable. The fix is to reword `clear` and `Map.clear` to "may retain storage", which makes it a note and not a promise. A note needs no test. Regressions in a hint belong in a benchmark or a runtime C-level test, for example one that reads `GC_get_total_bytes()`. That is where the blinkc profile already caught this gap.
  >
  > **Where I concede:** The new fact weakens my earlier point that tests can use an allocation counter, because none is exposed to Blink code. If the panel wants a Blink-level test, a compiler-internal or test-only hook is a smaller commitment than a public method. If A wins on the weak contract exactly as written, I accept it.

- **Minimalism:**

  > Min Phase D, Q3: I am switching from B to A, with the weak contract exactly as written.
  >
  > My strongest point for B was that capacity() is observable state with no semantic meaning, and that programs will branch on it. That risk is real but it is bounded. The weak contract is inequalities only, so the runtime keeps freedom over the growth policy. Code that branches on capacity() >= len() learns nothing it should not know.
  >
  > The point I got wrong is the testing answer. My B vote depended on "tests can use the runtime allocation counter". Your fact check shows no such counter exists in Blink code today. So under B, with_capacity and "clear retains capacity" have no in-language test at all. The fix for that gap would be a new allocation-counter API. That is a larger surface than one getter, and it is a worse subtraction trade. A minimalist should not swap a getter for a bigger observer.
  >
  > Also, StringBuilder.capacity() already exists. With B, List and StringBuilder get different answers to the same question, and that costs a "why" in the docs. A keeps one answer.
  >
  > Direct answer to Sys, PLT and DevOps: agreed that an unobservable promise cannot be tested. Conditions for my A vote: (1) the contract is exactly the three inequalities, with no growth-factor text; (2) docs say "for tests and diagnostics, do not branch on it"; (3) it stays List-only, and Map/Set stay deferred under Q5.
  >
  > Web and AI/ML: the cargo-cult risk remains. The docs note is the mitigation, and I accept that it is imperfect.

**Q3 (A, 6-0 after 3-3 in Phase C)**

- **Systems:** Vote: A — Reasoning: `with_capacity(n)` is a performance feature, so its contract is a statement about memory. No Blink-visible allocation counter exists. Under B, a regression that ignores `n`, or one that drops retained storage in `clear`, would pass every in-language test. Five of the six Phase D replies now agree with A, and A needs only one read-only getter that reads a field the header already has. B would have to add a larger observer API, or drop the one memory promise the spec makes. `StringBuilder.capacity()` sets the precedent, and the weak contract of three inequalities leaves the growth policy unspecified. (Concern: Some programs will branch on `capacity()` anyway, and the docs note will not stop them. The runtime would then be less free to shrink or round. A later lint for branching on `capacity()` is the right follow-up. It is not part of this decision.)
- **Web/Scripting:** Vote: A — Reasoning: `with_capacity(n)` is a performance feature, and the file confirms Blink code has no allocation counter. Under B, a regression that ignores `n` would pass every in-language test. A adds one read-only getter to close that gap, and `StringBuilder.capacity()` already sets the precedent. The weak contract is only inequalities, so the growth policy stays unspecified. I moved from B in Phase D for this reason. (Concern: Some programs and models will branch on `capacity()` despite the "tests and diagnostics only" docs line, and those inequalities then become guarantees the runtime cannot break.)
- **PLT:** Vote: A — Reasoning: With `with_capacity`, capacity becomes a performance contract. A performance contract needs an observer that a Blink conformance test can use. No allocation counter is exposed to Blink code today, so B would leave both `with_capacity(n)` and "`clear` retains capacity" with no in-language test. The weak contract of three inequalities gives no growth-factor promise, so the runtime keeps freedom over its policy. `StringBuilder.capacity()` already sets the precedent, and Web and Min have both moved to A on that basis. (Concern: Some programs will branch on `capacity()` despite the docs. The inequalities, and in particular "`clear` does not lower capacity", then become promises the runtime cannot change.)
- **DevOps/Tooling:** Vote: A — Reasoning: `with_capacity` is a memory feature, and a memory feature needs an observer. No allocation counter exists in Blink code. Under B, a regression that ignores `n`, or one where `clear` drops the buffer, would pass every in-language test. B would also leave `List` and `StringBuilder` with two different answers for one question. For tooling, one rule is better. A adds one read-only getter, and B would need a larger observer API to get the same test. (Concern: Some programs will branch on `capacity()` despite the docs line. The inequalities then become de facto guarantees, and the runtime loses room to shrink or round. A lint for `capacity()` in a branch condition, as a later follow-up, is the mitigation.)
- **AI/ML:** Vote: A — Reasoning: My B position rested on the idea that a hint needs no test, and that a runtime allocation counter covers regressions. The fact check removed the second part, because no counter is visible to Blink code. A new observer API would be a larger surface than one getter that StringBuilder already has. The weak contract (inequalities only, no growth factor) limits the lock-in I feared. A model that sees `StringBuilder.capacity()` will guess `list.capacity()` anyway, so one consistent rule costs less to learn. (Concern: Models and programs will still branch on `capacity()`, and a later runtime change to shrink or round will break code that relied on more than the inequalities. A lint for `capacity()` in a branch condition is the follow-up that limits this.)
- **Minimalism:** Vote: A — Reasoning: No allocation counter is visible to Blink code, so under B the with_capacity hint and the "clear retains capacity" promise have no in-language test. Fixing that would need a new observer API, which is a larger surface than one getter that StringBuilder already has. The weak contract (three inequalities, no growth-factor text) keeps the runtime free to change its policy. A also gives List and StringBuilder one consistent answer. My conditions stand: the contract is exactly the three inequalities, the docs say "tests and diagnostics only, do not branch on it", and it stays List-only with Map/Set deferred. (Concern: Some programs will branch on capacity() anyway, and the inequalities will become de facto guarantees that limit the runtime's freedom to shrink or round.)

### Moderator correction

The Phase B digest told the panel that `decisions/bytes-value-semantics.md` gives a `BytesBuilder` a `with_capacity`. That was wrong: the bytes panel rejected `BytesBuilder` (Bytes stays one value type with `mut self` writers), and Bytes has no `with_capacity`. Q6 named StringBuilder and BytesBuilder; the spec applies its rule to every `with_capacity` constructor that exists, `List` and `StringBuilder`, and to any later one (Q5). The runtime already treats `StringBuilder.with_capacity(n)` with n < 16 as 16, so n <= 0 already behaves like `new()`.

### Final Spec

```blink
fn with_capacity(n: Int) -> List[T]   // static: List.with_capacity(n)
fn capacity(self) -> Int
```

- `List.with_capacity(n)` returns an empty list; `len()` is 0; push past n grows as usual. Use it only when the final size is known before the first push.
- `capacity()` has a weak contract with exactly three rules: `capacity() >= len()`; `capacity() >= n` right after `with_capacity(n)`; `clear()` does not lower `capacity()`. Growth factor and exact values are unspecified. Docs: tests and diagnostics only, do not branch on it.
- Every `with_capacity` constructor (List, StringBuilder): `n <= 0` is the same as `new()`, no panic; allocation failure uses the normal out-of-memory path.
- No `reserve`. No `Map`/`Set` capacity; if added later, same name and shape.
- `List.filled(n, v)` is a separate feature, not decided here.
- Follow-ups: a lint for `capacity()` in a branch condition; a lint or debug-mode assert for a negative literal `n`.
