[< All Decisions](../DECISIONS.md)

# Index Assignment Places — Design Rationale

**Gap:** the evaluation-order decision ([argument-evaluation-order.md](argument-evaluation-order.md)) wrote `xs[i] = v`, `m[k] = v`, `a[i()].f[j()] = v` and `xs[next()] += 10` into §2.22 *Assignment places* and §2.19 as legal, with the bounds check at the store. §3.4 *Postfix Brackets That Are Not a Type Application* says a postfix `[...]` is legal only as a type-argument list before `(` or `{`, and a value inside is `error[NoIndexOperator]` (E0313). No panel had voted on index assignment. A search of src/, lib/, tests/ and examples/ found zero index-assignment statements.

**Moderator disclosure.** The AI/ML seat's standing domain reminder says that training data from other languages primes `xs[i] = v`. That is a fact about its domain, not an option, but the other seats did not get it.

**Moderator facts surfaced during debate.** §3.4 already chooses the E0313 read help from the receiver's type. The runtime already panics on an out-of-bounds `set` (`bootstrap/runtime_core.h:717`, "list set index out of bounds"). The List table in §3 did not state this.

**Section note.** The ballots call the call-order rule "§2.18". That rule is §2.22 *What each form evaluates*; §2.18 is *Scoped Resources*. The MOVE result places the example there.

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated
in independent-proposal → debate → vote rounds.

#### Phase A — Independent proposals

All six proposed no index place as their primary option. Every index-place shape was a fallback or a recorded-and-rejected alternative. Full texts:

**Systems:**

> I propose **A**, with **B** as a fallback.
>
> ## Proposal A (preferred): no index place. Writes are method calls
>
> §2.22 is written so that a place is a root binding plus field names, and nothing else. `xs[i] = v`, `m[k] = v` and `xs[i] op= v` take E0313, the same code a bracket read takes. The help text names the method that already exists, so §3.1 is met:
>
> - List or Bytes: "use `xs.set(i, v)`"
> - Map: "use `m.insert(k, v)`"
>
> §2.22 and §2.19 swap their index examples for field examples. A call's evaluation order comes from ordinary argument order: receiver, then arguments left to right, then the call. So it needs no special place rule.
>
> ```blink
> fn main() {
>     let mut xs = [0, 0, 0]
>     let mut m = Map[Str, Int]()
>     xs.set(1, 10)                           // bounds check inside set; panics if out of range
>     m.insert("rare", 1)
>     let i = next()
>     xs.set(i, xs.get(i).unwrap() + 10)      // compound form, spelled out
>     xs[1] = 5                               // error[E0313]: help: use `xs.set(1, 5)`
> }
> ```
>
> **Tradeoffs (systems):**
> - **What you see is what runs.** `xs.set(i, v)` is one call to one runtime function with one bounds check that can panic. An index place hides that same call and panic behind `=`, which looks like a register store. With a place, `a[i()].f[j()] = v` compiles to a chain of calls with two bounds checks and two panic sites, and the source shows none of them. The *Structural fact* above says an index place is the only place form whose parts can have effects or fail. That is where hidden cost sits.
> - **Reads and writes match.** Reads are `.get()`, which returns `Option` and never panics. A write place gives an asymmetry, and compound assignment makes it worse: `xs[i] += 1` needs an implicit read that panics, and Blink has no such read anywhere else. We would add a panicking read only to support a sugar.
> - **Less compiler work.** I0004 now stops at this path, and no Blink source anywhere uses it. With A, the compiler lowers nothing new, E0601 (9w3twa) has no new store kind, and the "bounds check at the store, after rhs" rule is removed, because the call order already gives that behaviour.
> - **Real cost:** a nested write into a struct element takes get, change, then set. With value-semantic structs, that copies the element twice. An in-place place would write through one pointer. For `Int` elements the spelled-out compound form does two bounds checks; gcc -O2 usually merges them after the call inlines, but that is not certain. If profiles show this matters, add `List.update(self, Int, fn(T) -> T)` later. Monomorphized and inlined, it does one bounds check and one write. Wait for evidence first (YAGNI).
>
> **Cross-language:** Go and Rust both allow `xs[i] = v` with a panic on a bad index. Rust gets there through the `IndexMut` trait, and that hidden trait call is exactly the cost I object to. Rust also forbids `m[k] = v` on `HashMap`, because a missing key has no slot to write to. Zig spells every bounds check with its own safety mode. Java collections use `list.set(i, v)`, and the JIT inlines it to a bounds-checked store at no extra cost.
>
> ## Proposal B (fallback, if the panel wants sugar): a List-only write place
>
> If the majority wants `xs[i] = v`, restrict it as follows:
> 1. Only List and Bytes get the place. It is defined as exactly `xs.set(i, v)`: same runtime function, same check, same order.
> 2. Map gets no place. `m[k] = v` is E0313 with help "use `m.insert(k, v)`". An insert allocates and can rehash, so it is not a store and should not look like one.
> 3. There is no index compound form (`xs[i] += 1` takes E0313). Allowing it would add the panicking read that A avoids.
> 4. Nested places stop at the first index: `s.items[i] = v` is legal and `a[i].f = v` is not. This keeps "one place, one runtime call, one panic site."
>
> ```blink
> fn main() {
>     let mut xs = [1, 2, 3]
>     xs[0] = 9            // B: exactly xs.set(0, 9)
>     xs[0] += 1           // B: error[E0313]: help: use `xs.set(0, xs.get(0).unwrap() + 1)`
> }
> ```
>
> Tradeoff: B saves a few keystrokes but adds a place form that behaves differently from every other bracket use, and it still needs lowering, E0601 work and a spec rule. My vote goes to A: it costs nothing to build, it matches the `.get()` decision, and the source shows every panic site.

**Web/Scripting:**

> # Phase A: web/scripting seat, index assignment places (w0h7nh)
>
> ## Proposal A (my vote): no index place, and writes use methods
>
> In Blink, a place is a root binding followed by zero or more field names (`x`, `s.f`, `s.a.b`). An index is never a place. You write an element with the method that already exists:
>
> ```blink
> fn main() {
>     let mut xs = [0, 0, 0]
>     xs.set(1, 10)                        // List: replace at index
>     xs.set(2, xs.get(2).unwrap() + 5)    // no `+=` form for elements
>
>     let mut counts = Map.new()
>     for w in ["a", "b", "a"] {
>         counts.insert(w, counts.get_or_default(w, 0) + 1)
>     }
> }
> ```
>
> **Why this suits my domain:** the 5-0 §2.6 decision already told every JS or Python developer that `xs[i]` is not how Blink reads an element. If writes then allow `xs[0] = 1` but `io.println("{xs[0]}")` fails with E0313, users hit an inconsistency within 5 minutes of use. That is exactly the kind of rule that fills Stack Overflow ("why can I write `xs[0]` but not read it?"). One rule is easy to learn: brackets hold types, methods touch elements. Scripting users accept `.get` and `.set` if they apply everywhere. They do not accept a half-feature. Today's state is the worst of both: `blink check` accepts `xs[0] = 5` on a List, rejects `m["a"] = 1` on a Map, and codegen then stops with ICE I0004.
>
> **Replacement text for §2.22 and §2.19:** the 6-0 evaluation-order vote stays. Only its example places change.
> - §2.22: "A place is a root binding and a field path. `place = rhs` evaluates `rhs`, then stores." A field path has only names as sub-expressions, so it has no effects and no bounds checks to order.
> - The examples move to argument order in a method call. `xs.set(next(), fill())` runs `next()`, then `fill()`, then the bounds check inside `set`, so it keeps the "prints fill, then panics" example.
> - §2.19: `op=` applies to places as defined above, so `x += 1` and `s.n += 1` stay. `xs[next()] += 10` is removed. In `xs.set(i, xs.get(i).unwrap() + 10)` the user names `i` twice. If `i` has effects, the user binds it with a `let` first, and the spec says so in one sentence.
>
> **Diagnostics (§3.1: the repair must exist):**
> - `xs[i] = v` and `xs[i] op= v` stay E0313. E0313 fires at name resolution, before the receiver type is known, so the help names both verbs: "`xs.set(i, v)` for a List or Bytes, `m.insert(k, v)` for a Map". The help must not say `.insert` alone, because `List.insert` shifts the elements to the right (sections/03_types.md:379). That would be a wrong repair.
> - If typecheck later knows the receiver type, it may narrow the help to one verb. It gives no machine-applicable fix for `op=`, because the correct rewrite depends on `Option` handling.
>
> **Known cost (stated plainly):** `users[i].active = true` is common in JS and Python. Under A it becomes:
>
> ```blink
> let mut u = users.get(i).unwrap()
> u.active = true
> users.set(i, u)
> ```
>
> This is 3 lines. If structs copy on `let`, a missing `set` also silently loses the write. I did not find a clear statement of struct copy or alias semantics in the spec, and the panel must check this. Mitigation: a follow-up feature ticket for `List.update(self, Int, fn(T) -> T)`, so the fix is a library method, not new syntax. That ticket is not part of this vote.
>
> **Cross-language:** Kotlin `list[i] = v` desugars to `list.set(i, v)`, so Blink writes the desugared form. Python `d[k] = d.get(k, 0) + 1` maps one-to-one to `insert` + `get_or_default`. Rust `v[i]` panics, which Blink rejected for reads.
>
> ## Proposal B (I reject it): an index place that covers everything
>
> If the panel wants `xs[i] = v`, it must add all of these together:
> - List, Map, Bytes and nested places (`a[i].f[j] = v`, `m[k] += 1`).
> - A new exception in the §3.4 rule and the name-resolution bracket check for the left side of `=` and `op=`.
>
> Shipping List-only, as today, is worse than A or B. The honest cost: the §2.6 vote that reads must use `.get()` then conflicts with write syntax, so B probably means reopening §2.6 for reads as well. That is a much larger change than this ticket. I would only vote for B as part of a full "brackets for element access" reversal. Not by accident, one half at a time.
>
> **Vote: A.**

**PLT:**

> **PLT seat: Phase A submission (w0h7nh)**
>
> ### Framing: what a place has to be
> A place is an l-value. In any sound treatment (ML refs, lenses, Koka's local mutable variables) a place is a *get/put pair*: `put` must have a matching `get`, and the pair must obey the round-trip laws (`put(get(s)) = s`, `get(put(s,v)) = v`). `place op= rhs` needs both halves, because it is `put(p, get(p) op rhs)`.
>
> Blink has decided that an index *read* does not exist (§2.6 5-0, §3.4 6-0: `xs[1]` is E0313). Element access is `.get()`, which returns `Option[T]` because it is partial. An index *place* would therefore have a write half with no surface read half. `xs[i] += 1` would also need a hidden *total* read that panics on a miss. That is the only implicit panicking read in the language, and it contradicts the reason `get` returns `Option`. Nested places make it worse. `a[i()].f[j()] = v` under value semantics (§3.6, copy on bind) is lens composition `set_i ∘ modify_f ∘ set_j`. That composition is total only if every step is total, and `List.get` is not.
>
> So an index place is either unsound in its partiality story or a special case the type system cannot describe. §2.22 and §2.19 wrote the index examples to illustrate eval order. No vote ever created the construct.
>
> ---
>
> ### Proposal P1 (recommended): no index place; places are field paths
> **Grammar:** `place ::= ident | place "." field`. The root must be a `let mut` binding.
>
> A field place's sub-expressions have no effects and cannot fail, so place evaluation is trivial. §2.22 keeps its one real content: the root is read at the store, after `rhs`. Index writes are ordinary method calls under §2.13 order (receiver, then args, left to right).
>
> **New typing rule:** the receiver of a mutating method (`set`, `insert`, `push`, …) is a *place*, not a value. It is resolved at the call, after the arguments are evaluated. The §2.22 guarantee ("a write that `rhs` makes through a closure is not lost") then carries over to `.set` unchanged. There is one rule, not two.
>
> ```blink
> fn fill() -> Int {
>     io.println("fill")
>     7
> }
>
> fn main() {
>     let mut xs = [1, 2, 3]
>     xs.set(10, fill())            // prints "fill", then panics in set
>
>     let mut m = Map.new()
>     m.insert("rare", 1)
>
>     let mut i = 0
>     let next = fn() -> Int {
>         i = i + 1
>         i
>     }
>     let mut ys = [0, 0, 0]
>     let k = next()                // next() runs once, visibly
>     ys.set(k, ys.get(k).unwrap() + 10)
> }
> ```
>
> **§2.19:** compound assignment is defined on places (bare variables and field paths). Rewrite the `xs[next()] += 1` example with a field, such as `s.count += bump()`.
>
> **Diagnostics (§3.1: each repair exists):**
> - `xs[i] = v` on a List: E0313, help `xs.set(i, v)`
> - `m[k] = v` on a Map: E0313, help `m.insert(k, v)`
> - `xs[i] op= v`: E0313, help `xs.set(i, xs.get(i).unwrap() op v)`, which makes the partiality explicit
>
> This also replaces today's wrong behaviour. `blink check` accepts `xs[0] = 5`, and the Map TypeError says "`[i]` resolves only on a List".
>
> **Tradeoffs:** Every partial operation now shows in the types. Places stay total and effect-free, so the effect system never has to reason about effects inside an l-value. This closes the gap with no new construct and no migration, because src/lib/tests hold zero index-assignment statements. The cost is verbose nested updates: `a[i].f[j] = v` becomes get-row, `row.f.set(j, v)`, `a.set(i, row)`. If that pain turns out to be real, the principled fix is a total combinator such as `List.update(i, fn(T) -> T)`, a lens `modify` whose failure mode is documented. That would be a separate ticket, not syntax (YAGNI).
>
> **Cross-language:** Koka and Haskell have no index l-values and use functional update or lenses. OCaml's `a.(i) <- v` is sugar for `Array.set`, but OCaml *also* has the read `a.(i)`. Blink dropped that read on purpose.
>
> ---
>
> ### Proposal P2 (rejected, recorded for the panel): index place as sugar for a sealed `IndexSet` trait
> `e[k] = v ≡ e.set(k, v)` (or `insert` on Map), with compound index assignment forbidden.
>
> **I reject it.** It creates a place with no r-value form, which breaks the get/put pairing every sound l-value calculus assumes. It makes `[` depend on context again (value suffix legal only before `=`), which undoes the §2.6 and §3.4 parser simplification that won 5-0 and 6-0. And banning `+=` there makes places non-uniform. Rust's `IndexMut: Index` makes the same point: you cannot soundly have a write place without its read.
>
> ---
>
> **Vote intent:** P1.

**DevOps:**

> # DEVOPS/TOOLING: Phase A on w0h7nh (index assignment places)
>
> I judge this gap by what the user sees: the diagnostic, the LSP and `blink fmt`/`blink fix`. Facts I checked: §3.4 E0313 says "Blink has no index operator", and the code is chosen at name resolution from the bracket contents alone. `List.set` means "Replace at index", `Map.insert` inserts, and `List.get` returns `Option[T]`.
>
> ## Proposal 1 (recommended): no index place. E0313 also covers assignment position
>
> A bracket suffix holding a value is E0313 whether it is read or written. The LHS of `=` or `op=` is a syntactic position, so the code is still chosen at name resolution with no type information. Only the `help:` text looks at the receiver's type, as it does now.
>
> ```blink
> fn main() {
>     let mut xs = [1, 2, 3]
>     let mut ages: Map[Str, Int] = Map()
>     let i = 1
>
>     xs[0] = 5          // error[NoIndexOperator]: Blink has no index operator
>                        // help: `xs.set(0, 5)`            (machine-applicable)
>     ages["bob"] = 41   // error[NoIndexOperator]
>                        // help: `ages.insert("bob", 41)`  (machine-applicable)
>     xs[i] += 1         // error[NoIndexOperator]
>                        // help: `xs.set(i, xs.get(i).unwrap() + 1)`
>                        // note: panics if `i` is out of bounds, like the store it replaces
> }
> ```
>
> Rules for the help, from §3.1's rule that every prescribed repair must exist:
> - **Plain `=`:** List gives `.set(i, v)` and Map gives `.insert(k, v)`. The receiver, then the index, then `v` are evaluated left to right, as in the place rule. So the rewrite keeps the meaning, and it is machine-applicable.
> - **Compound `op=`:** machine-applicable only when the index is a local, a literal or a constant. The rewrite writes the index twice. If the index were `next()`, the rewrite would call it twice and change the meaning. In that case the help suggests `let k = next()` first and gives only a `note:`, with no auto-fix.
> - **Map compound (`m[k] += 1`):** a note only. A missing key has no single correct default (`?? 0`, `unwrap`, or `match`), and only the author can choose.
> - **Nested (`a[i].f[j] = v`):** a note only. The correct repair depends on whether `.get()` gives a copy. I will not let the tool guess at a write-back chain.
> - **Tuple (`pair[0] = v`):** `pair.0 = v`.
>
> **Spec edits.** §2.22 lists only these places: a binding and a field path (`s.f.g`). The index/key paragraph and the `xs[10] = fill()` example move to §2.18 call evaluation order, rewritten as `xs.set(10, fill())`. §2.19 uses `n += bump()` and a field example. The `xs[next()] += 10` example is removed. The "bounds check at the store" sentence becomes a sentence about `List.set`, which checks bounds when it runs, after its arguments. That is the same observable order.
>
> **Tooling wins:**
> - **One spelling.** Reads, writes, find-references on `set`/`insert`, hover docs and rename all work on real methods. An LSP cannot autocomplete an operator. `xs.` lists `set` and `insert` with signatures.
> - **No read/write asymmetry to explain.** "You can write `xs[i] = v` but not read `xs[i]`" is a confusing message whatever words we give it, and it would produce a steady stream of friction tickets.
> - **Map and List stay separate.** Rust saw that `m[k] = v` can mean "insert" or "replace, else panic" and did not implement `IndexMut` for `HashMap`. rustc E0594 says "use `.insert()`". Here each method name says which one it does.
> - **Cost today is zero.** The corpus has no index-assignment statements. `blink check` accepting `xs[0] = 5` and then stopping at ICE I0004 is a gate bug that this fixes. The same E0313 walk that migrates the ~272 reads covers writes.
> - **`blink fmt`** changes nothing: fmt does not change meaning. `blink fix` applies the machine-applicable helps above.
>
> ## Proposal 2 (fallback if the panel wants the sugar): the index place is only sugar for `set`/`insert`
>
> `xs[i] = v` lowers to `xs.set(i, v)` and `m[k] = v` to `m.insert(k, v)`. Compound and nested places are E0313 with the notes above. Reads stay E0313.
>
> Tooling cost:
> - The LSP must map `[]=` to a method for go-to-definition and references. rust-analyzer does this for `IndexMut`, and it is a known source of bugs there.
> - Every E0313 read message now needs a second sentence explaining why writes are legal.
> - Code that tools or AI generate will then write `xs[i]` in reads, because writes compile.
>
> Go and Kotlin have both reads and writes, so there is no asymmetry to explain. A write-only form is worse than either choice.
>
> ## Rejected: full index places (List, Map, nested, compound)
>
> This form carries effects and bounds failures inside place syntax, which is the only place form that can. It reopens §2.6 and §3.4 E0313 for writes with no panel vote. It also gives a second, hidden panic path that the LSP cannot show on hover.
>
> **Vote intent: Proposal 1.**

**AI/ML:**

> I propose **no index place anywhere**: brackets are never indexing, whether read or written.
>
> ## Proposal A: one rule for brackets
>
> A bracket suffix is never indexing, on the left of `=` or anywhere else. There are two place forms: a local binding and a field path (`s.a.b`). Element writes use the existing methods.
>
> ```blink
> fn main() {
>     let mut xs = [1, 2, 3]
>     xs.set(0, 99)
>     let mut counts = Map[Str, Int]()
>     counts.insert("rare", counts.get_or_default("rare", 0) + 1)
>     let j = next()
>     xs.set(j, xs.get(j).unwrap() + 10)
> }
> ```
>
> **§2.22** lists the two place forms. It keeps the "sub-expressions first, then `rhs`, then store" rule, shown on `s.inner.count = f()`. It says that element writes are method calls, so the argument order rule covers them: `xs.set(next(), fill())` runs `next()` before `fill()`. The out-of-bounds panic example moves to `.set()`.
>
> **§2.19** shows `s.count += bump()` in place of `xs[next()] += 10`. The "sub-expressions evaluated once" wording stays for field paths.
>
> **Diagnostics:** a value bracket as the target of `=` or `op=` is E0313. The fix it gives depends on where the bracket is and what the root's type is, so every case has a repair that exists (§3.1):
> - `xs[i] = v` on a List or Bytes: fix is `xs.set(i, v)`.
> - `m[k] = v` on a Map: fix is `m.insert(k, v)`.
> - `xs[i] += v`: fix is `xs.set(i, xs.get(i).unwrap() + v)`. When `i` is not a plain binding or literal, the fix first binds it with a `let`, so it keeps the single-evaluation rule.
> - The help text must not say "use `.get()`" at a store. It names `.set()` or `.insert()`. The current TypeError ("`[i]` resolves only on a List") goes away.
>
> **AI/ML tradeoffs:**
> - **One decision point.** "Brackets are types, never indexing" is one rule that a model can learn from the spec alone.
> - **Priming.** The training-data pull toward `xs[i] = v` is real. It is also the same pull as `xs[i]` reads, which Blink already rejects (§2.6, 5-0). A model that has learned "no index read" applies the same rule to writes. One fix-it diagnostic trains the repair in one round trip.
> - **Token cost.** `xs.set(i, v)` costs about 3 more tokens than `xs[i] = v`, which is low. Compound writes cost more: about 12 extra tokens for `xs[i] += 1`. Nested writes (`a[i].f[j] = v`) need get, copy-update and set, which is the highest cost. In LLM-written code these are rare, and the counter pattern on a Map already has `get_or_default`.
>
> **Cross-language:** Rust and Kotlin collections use `insert`/`set` methods where they do not want operator overloading. Rust's `v[i] = x` panics while `v.get(i)` returns an Option. That read/write split is a known source of confusion.
>
> ## Proposal B (I argue against it): index places for writes only
>
> `xs[i] = v`, `m[k] = v` and nested places would be legal, while reads stay `.get()`.
>
> - **Two rules instead of one.** The bracket is legal on the left of `=` and illegal on the right.
> - **Worse priming.** Each legal `xs[i] = v` in the corpus teaches the model that indexing exists. It will then write `let y = xs[i]` more often, and those reads are errors. Blink code is future training data (CLAUDE.md), so this cost grows over time.
> - **Mixed behavior.** A bracket write panics when out of bounds. A `.get()` read returns an Option. A model cannot tell from the syntax which failure mode applies.
> - **Two new forms.** Map writes would add a second surface (`m[k] = v` next to `.insert()`). That is a new "which form?" decision in every generated Map write.
> - It saves about 3 tokens per plain write.
>
> ## Proposal C (optional, only if the panel judges A's compound cost too high): `List.update`
>
> Add `fn update(self, index: Int, f: fn(T) -> T)` to ListOps. The compound fix-it then becomes:
>
> ```blink
> xs.update(next(), fn(x: Int) -> Int { x + 10 })
> ```
>
> - `next()` is evaluated once without a temporary.
> - It adds one method name and no new syntax. I would add it only after real code shows the compound pattern is common (YAGNI).
> - Rust `HashMap::entry`, Kotlin `compute` and Swift's `modify` accessors show that there is demand for this shape.
>
> ## Vote intent
>
> - **A: yes.**
> - **B: no.** It costs more in LLM accuracy than it saves in tokens.
> - **C:** defer and file a follow-up. I would not bundle it with this decision.

**Minimalism:**

> MINIMALISM seat, Phase A submission.
>
> ## Proposal M1 (primary): no index place. Fix §2.22 and §2.19 as editorial errors
>
> A place is a root binding plus field names, and nothing else. `xs[i] = v`, `m[k] = v`, `a[i()].f[j()] = v` and `xs[next()] += 10` are removed from the spec. Writes go through the methods that already exist: `List.set`, `Map.insert` and `Bytes.set`.
>
> ```blink
> fn main() {
>     let mut xs = [0, 0, 0]
>     xs.set(1, 10)
>
>     let mut tags = Map[Str, Int]()
>     tags.insert("rare", 1)
>
>     let mut i = 0
>     let next = fn() -> Int {
>         i = i + 1
>         i
>     }
>     let k = next()
>     xs.set(k, (xs.get(k) ?? 0) + 10)
>     io.println("{xs.len()}")
> }
> ```
>
> **Why this, and why it is not a new decision.** §2.6 (5-0) says "Blink uses `.get()` for element access". §3.4 (6-0) says a postfix `[...]` is legal only before `(` or `{`. That decision also rewrote `tags["rare"] = 1` as `.insert`. The eval-order vote in argument-evaluation-order.md (6-0) was about order only. It never voted an index place into the language. It only used index examples to show the order. Two votes rule out the syntax, and no vote puts it in. So this is a spec defect, not an open design question.
>
> **Subtraction ledger.** Removing the index place deletes all of these:
> - A read form that is illegal (`xs[i]`) next to a write form that is legal (`xs[i] = v`). An LLM or a human learns "brackets index" from the write and then gets E0313 on the read. That asymmetry is the worst option we have.
> - The only kind of place whose sub-expressions have effects or can fail. Places become pure paths again, so the whole "evaluate the path, defer the bounds check to the store" rule in §2.22 is gone.
> - A panicking write path in a language whose §3 says `.get()` returns Option so that there are "no index-out-of-bounds panics". The §2.22 example `xs[10] = fill()` panics. That contradicts §3.
> - The Map question (insert or update? missing key?), which the bracket form hides.
> - An I0004 codegen stage that nobody has built, and the extra rows it would add to the E0601 store list (9w3twa gets simpler).
>
> **What it costs.** Compound updates on elements get longer. A nested value update becomes get, change, `set`. Today no Blink code uses the index place: the search found zero index-assignment statements in src/, lib/, tests/ or examples/. We lose nothing that exists.
>
> **Cross-language note.** Go kept `m[k] = v` and then needed special rules for it: `m[k].f = v` is illegal, and comma-ok. Rust's `IndexMut` panics, and its Map has no `m[k] = v` at all, so you use `insert`. Lua and Scheme get by with one general mechanism (`vector-set!`). The C++ committee's `operator[]` on `std::map` silently inserts on read, which is the cautionary tale.
>
> **Edits.**
> - §2.22: rename it *Assignment targets*. A target is a local or a field path `s.f.g`. It has no sub-expressions with effects, so `rhs` evaluates first and then the store happens.
> - §2.19: `place op= rhs` applies to locals and field paths. Delete the `xs[next()]` sentence and the example.
> - Change the §2.22 examples to use `.set` and the closure example on `n`. Keep the `n += bump()` example, because it is still true.
>
> ## Proposal M2: diagnostics, which follow from M1
>
> `xs[i] = v` and `xs[i] op= v` take the §3.4 path: a value inside the brackets gives E0313 NoIndexOperator. The help text names a repair that exists (§3.1). On a List or Bytes the repair is `xs.set(i, v)`. On a Map it is `m.insert(k, v)`. For compound assignment it is the `get`/`set` pair. Do not add a new code. One code covers reads and writes, which is less surface. The current Map TypeError ("`[i]` resolves only on a List") is wrong under both §2.6 and §3.4, and it goes away.
>
> ## Proposal M3 (flag only, not a vote here): out-of-bounds `set`
>
> §3 does not say what `xs.set(99, v)` does. If we remove the index place, `set` becomes the only element-write path, so its failure mode needs one line in the List table (panic, or return a `Bool`/`Result`). Log it as a follow-up ticket and keep it out of this decision.
>
> ## Rejected alternative: legalize `xs[i] = v` only as a write
>
> This adds syntax that brings nothing new: `.set` does the same work. It breaks the read/write symmetry, reopens a 6-0 decision, and puts back the one place form that needs special eval-order rules. Someone who wants indexing sugar should bring a full `Index`/`IndexMut` trait proposal as its own spec ticket, with reads included. It should not come in through an eval-order example.
>
> **Vote intent: M1 + M2 yes. If a later panel wants indexing, it should decide reads and writes together.**

#### Phase B — Debate (one round)

After dedupe there was one primary option (NOPLACE) and six flagged variations (help verb, compound-assignment fix, §2.22 wording, plt's mutating-receiver rule, where the `fill()` example lives, out-of-bounds `set`). One round ran; five of six seats signalled stable. Key shifts: sys withdrew its fallback B; devops moved to "no automatic fix" for `xs[i] op= v` and to STAY on the example (both reversed in Phase C); aiml held DEFER on the `set` row note; plt held IN on its receiver rule. Full round-1 replies:

**Systems:**

> # SYSTEMS, Phase B round 1
>
> **Position: NOPLACE.** All six seats have it as their first choice. I withdraw my fallback B. devops' Proposal 2 and my B are the same shape, and aiml's priming argument settles it for me: a legal `xs[i] = v` makes the bracket look like an operator, and then `xs[i]` reads fail. That is the asymmetry both web and min describe.
>
> ## V1: help verb
> I agree with devops, aiml and plt, and with web's guard added. The code is E0313, chosen at name resolution. The help reads the receiver type, as §3.4 already does for reads (moderator fact), so this needs no new mechanism. Merged wording: *"The help names `.set(i, v)` for a List or Bytes receiver and `.insert(k, v)` for a Map receiver. When the receiver type is not known, it names both. It never names `List.insert`."* Web is right that `.insert` on a List is a wrong repair, because it shifts elements and so changes the length and the cost (O(n) memmove against an O(1) store).
>
> ## V2: machine-applicable compound fix
> I take devops' rule. The fix is machine-applicable only when the index is a local, a literal or a constant, and when the receiver is a List or Bytes. In every other case it is a note: an index with effects, a Map compound, or a nested write. The unwrap form (`xs.set(i, xs.get(i).unwrap() + v)`) is the only rewrite that keeps the failure mode: out of bounds panics, as the store did. I disagree with min's `?? 0`. A silent default in place of a panic hides a bug and changes the meaning, so it cannot be the repair. aiml's "bind with `let` first" is fine as note text, but the tool should not apply it. Web's "no auto-fix for `op=`" is too strict: with an index that has no effects, the rewrite is exact.
>
> ## V3: §2.22 wording
> Merged wording (aiml + web + min are the same for field paths): *"A place is a local binding or a field path `s.f.g`. A field path has no sub-expressions that have effects or can fail. `place = rhs` evaluates `rhs`, then reads the root binding, then stores."* This keeps the voted guarantee that a closure write in `rhs` is not lost, and it costs nothing to compile: we load the root after the call.
>
> I disagree with putting plt's mutating-receiver rule into this decision. It changes §2.13 receiver order for every method, user methods included, and that needs a definition of which methods mutate. It is a real question: `xs.set(i, f())`, where `f` reassigns `xs`, either writes the old handle or the new one. But this ticket did not raise it and nobody has measured it. Split it into its own spec ticket. The codegen for either answer is trivial, so deferring it blocks nothing.
>
> ## V4: panic-at-store example
> I take devops' placement. `xs.set(10, fill())` goes in §2.18 call evaluation order, because it is no longer about a place. §2.22 gets field examples only.
>
> ## V5: follow-ups
> - Defer `List.update`. When it comes, it must monomorphize and inline the closure so it compiles to one bounds check and one store. Otherwise it is not worth having.
> - min's M3: log it. `set` out of bounds panics today in the runtime (`blink_list_set`, bootstrap/runtime_core.h:715, "list set index out of bounds"), so the ticket should make the §3 table say "panics if out of range". Adding a `Bool` return would change the signature for no gain.
>
> STABLE: ready to vote

**Web/Scripting:**

> # Phase B round 1 — web/scripting seat
>
> **Position: NOPLACE.** No change. All six seats reach it independently. The PLACE fallbacks (sys B, devops 2) each create a write-only bracket. sys, devops, aiml, min and I all name that as the worst developer-experience outcome. Nobody argues for PLACE as their first choice, so I will not argue against it further.
>
> ## V1: which verb, and when
>
> **I concede.** The moderator's fact settles it: §3.4 already picks the E0313 *code* at name resolution and the *help* from the receiver type ("`.get()` where the type has it"). My worry about "nameres before types" does not apply. Merged wording:
>
> > The help names `.set(i, v)` for a List or Bytes receiver and `.insert(k, v)` for a Map receiver. When the receiver type is unknown (an error type), the help names both verbs, each with its receiver kind. The help never names `.insert` for a List (List.insert shifts right).
>
> ## V2: fix for compound `xs[i] op= v`
>
> **I adopt devops's rule** and withdraw my "no fix". `xs.get(i).unwrap() op v` panics out of bounds, as the removed store would have. So for a List it keeps the meaning the author meant. Merged:
>
> > - List/Bytes, index is a local, literal or constant: machine-applicable `xs.set(i, xs.get(i).unwrap() op v)`.
> > - List/Bytes, any other index: help shows `let k = <index>` then the same pair. Not machine-applicable: it inserts a statement.
> > - Map compound and nested writes: `note:` only.
>
> I **oppose min's `(xs.get(k) ?? 0)`** as the help. Out of bounds, it silently writes 0 + v, where the author expected a panic. That is a silent bug that leaves a user with nothing to search for. plt's `unwrap` spelling "makes the partiality explicit", which is the correct instinct.
>
> ## V3: what §2.22 says
>
> For field paths, plt, aiml, min and I say the same thing in different words. Merged:
>
> > A place is a `let mut` local or a field path `s.f.g`. `place = rhs` evaluates `rhs`, then reads the root binding and stores. A field path has no sub-expressions with effects, so nothing else is ordered.
>
> **plt's extra rule** (the receiver of a mutating method is a place, resolved after the arguments) is a real point. §2.x call order says "the receiver of a method call, then the arguments". Without plt's rule, `xs.set(i, f())` evaluates `xs` before `f()`. If `f` rebinds `xs` through a closure, the write goes to the old value. But that rule changes evaluation order for *every* mutating call (`push`, `insert`, `clear`), not only this gap. I support its intent. I do not want it in this vote without its own look at §2.x. I propose a separate spec ticket.
>
> ## V4: where `xs[10] = fill()` goes
>
> **devops.** The example is now a call, so it belongs in the call evaluation-order section as `xs.set(10, fill())`. §2.22 keeps a field example (aiml's `s.inner.count = f()`). One home per rule. A reader looking for "why did fill print before the panic" searches call order, not assignment.
>
> ## V5: follow-ups
>
> - `List.update`: defer. aiml, sys and plt agree. No objection.
> - **min's M3 (out-of-bounds `set`): file it now, as a priority.** `.set` becomes the only element-write path, and §3 does not say what `xs.set(99, v)` does. The V4 example claims it panics, and the table says nothing. The V4 example text depends on the answer, so the ticket must at least state "panics".
>
> NOT STABLE: V3 — is plt's "mutating-method receiver is a place resolved after the arguments" rule part of this decision, or a separate ticket (my position)? Also V5 — does the §3 List table state that out-of-bounds `set` panics before V4's example claims it?

**PLT:**

> **PLT, Phase B round 1**
>
> **Position: NOPLACE.** No change. All six seats agree, and every fallback (sys B, devops 2) is weaker than the rule it falls back from. I agree with min that this is a spec defect, not a new construct. No vote ever created an index place.
>
> **V1 (help verb): take web's rule, with a narrowing step.** The CODE comes from the bracket contents at name resolution. The HELP may use the receiver type, and §3.4 already does this for reads (moderator fact). Merged wording: "When the receiver type is known, the help names one verb: `.set(i, v)` for List or Bytes, `.insert(k, v)` for Map. When it is not known, the help names both. The help never names `.insert` for a List." I agree with web that List `.insert` shifts elements right, so naming it would be a wrong repair.
>
> **V2 (compound fix): take devops's rule.** I drop my plain `unwrap` help as the only form. The rewrite writes the index twice. That keeps the meaning only if the index is pure: a local, a literal or a constant. So the fix is machine-applicable only there, and in all other cases it is a `let` note (aiml's "bind first" is the same idea). For List I prefer `.unwrap()` to min's `?? 0`. The `?? 0` fix silently turns an out-of-bounds read into a default, where the original meant "this element exists". Map compound and nested writes get a note only (devops, web). The author must choose the missing-key default.
>
> **V3 (§2.22 evaluation): this is the one point where substance is at stake.** web and min say "`rhs` first, then store". aiml says "sub-expressions, then `rhs`, then store". For a field path these mean the same, because the path holds only names. The gap is in the replacement. §2.18 says "the receiver of a method call, then the arguments". Under copy-on-bind (03c:40), `xs.set(i, f())` where `f` writes `xs` through a closure is then under-determined. It could evaluate `xs` to a value first and lose `f`'s write, or it could write into a stale copy. §2.22 closed this gap for `xs[i] = f()`. Removing the place must not reopen it through `.set`. Merged wording for §2.18: "A mutating method's receiver is a place. Its path is evaluated in order with the other operands, and the root binding is read at the call, after the arguments." That is the same rule as §2.22, so the language has one store rule, not two. sys says "call order already gives that behaviour". It does not, unless this sentence is in the spec.
>
> **V4 (panic example):** I accept devops's move to §2.18 as `xs.set(10, fill())`, next to the V3 sentence, with a cross-reference from §2.22. min and sys's field examples take its place in §2.22.
>
> **V5:** I agree to defer `List.update`, since it is a total lens `modify` and belongs in its own ticket. On min M3, a coupling: the moved example says `xs.set(10, fill())` "panics". The §3 table does not say that `set` panics out of bounds, and §3 ~407 says there are "no index-out-of-bounds panics". A spec example must not assert behaviour the spec does not state. Either this edit adds one row note, "`set` panics when the index is out of bounds" (today's behaviour), or the example drops the panic. I prefer the row note. The other choice (a `Bool` or `Result` return) goes to M3's follow-up.
>
> STABLE: ready to vote

**DevOps:**

> # Phase B round 1: DEVOPS/TOOLING
>
> **Position: NOPLACE.** It has six votes of six, so I will not argue it again. aiml's point about priming and web's "why can I write `xs[0]` but not read it?" are the diagnostic case in short form. A write-only form means every E0313 read message needs an exception clause.
>
> ## V1: which verb the help names (merged wording, from web and the moderator fact)
> web is correct: the CODE is chosen at name resolution. But the moderator fact shows the §3.4 read help already looks at the receiver type, so a store can do the same. Proposed wording:
>
> > The first `help:` at a store depends on the receiver's type, as it does for a read: `.set(i, v)` for a List or Bytes, `.insert(k, v)` for a Map, a field assignment `pair.0 = v` for a tuple. When the receiver type is not known (it is an error type or unresolved), the help names both verbs. The help never names `.insert` for a List.
>
> The rule "never `.insert` for a List" is web's, and it is the most important line. `List.insert` compiles and shifts the elements, so a wrong help gives a program that is wrong at runtime with no error.
>
> ## V2: compound fix. I change my position to web's
> I proposed a machine-applicable fix when the index is trivial. I withdraw it. The precedent is §3.4 itself: `handlers[0](req)` gets no machine-applicable fix, because the Option handling (`?`, `unwrap`, `match`) is the author's choice. `xs[i] += 1` has the same choice. `.unwrap()` guesses "panic", which is correct for some programs and not for others, and `blink fix` must not apply it without the author reading it. Merged wording:
>
> > `xs[i] op= v` is E0313. The `help:` shows `xs.set(i, xs.get(i).unwrap() op v)` as text, with no machine-applicable fix. When the index is not a local, a literal or a constant, a `note:` tells the author to bind it with `let` first, so that it runs once. For a Map compound or a nested store, a `note:` only.
>
> This covers aiml's `let` point and plt's and min's help text. For plain `=`, the fix stays machine-applicable (the four proposals that give plain-`=` repairs agree).
>
> ## V3: §2.22 place evaluation
> I agree with min and web on the text: a field path has no sub-expressions that have effects, so the store follows `rhs`. Keep plt's sentence that the root binding is read at the store, after `rhs`. It is true for field paths and it is what the 6-0 vote was about.
>
> I object to adding plt's typing rule for mutating-method receivers in this decision. It changes method-call semantics for `push`, `insert`, every `self`-mutating method and user methods too. That needs its own ticket, its own tests, and a check of the current codegen. It is not a spec fix for an example. If it is left out, `xs.set(i, f())` where `f` writes `xs` through a closure has behavior that the spec does not state. Record that as a follow-up, not a vote here.
>
> ## V4: where the panic example goes. I concede
> Keep it in §2.22 as `xs.set(10, fill())` (web, aiml, plt), with a cross-reference to the call-order section. A reader looks for it where it was. My §2.18 move adds a jump for no gain.
>
> ## V5: follow-ups
> - `List.update`: defer. All four who named it agree.
> - Out-of-bounds `set` (min M3): support as a follow-up with priority. My V2 text says "panics if out of bounds", and §3.1 means the help must not state a behavior the spec does not define. Until the §3 table says so, the help says only what `set` is documented to do.
> - plt's receiver rule: new follow-up (see V3).
>
> STABLE: ready to vote

**AI/ML:**

> # AI/ML, Phase B round 1
>
> **Position: NOPLACE.** All six seats agree. I add one point for my seat: devops says that "tools or AI will write `xs[i]` in reads because writes compile". That is the main LLM risk, and it is why a write-only fallback (sys B, devops 2) is worse for LLM accuracy than either no place or full places (web's point). If the panel ever wants brackets, it decides reads and writes together (min, web).
>
> ## V1: which verb the help names
> Merged wording: "The code is E0313 at name resolution. The `help:` names one verb from the receiver's type when the type is known (`.set` for List/Bytes, `.insert` for Map). When the type is unknown, it names both. It never names `List.insert`."
> - §3.4 already makes the read help depend on the receiver type (moderator fact), so web's timing concern does not block type-specific help.
> - web's trap is real for LLMs. Python's `list.insert` and JS's `splice` prime the model toward `insert`, and `List.insert` shifts elements, so the result would be silently wrong. One exact verb is the best repair signal for a model in an edit loop.
>
> ## V2: machine-applicable fix for compound assignment
> I change my Phase A position and take **devops's rule**:
> - The fix is machine-applicable for List/Bytes only when the index is a local, literal or constant.
> - Otherwise the `let` binding goes in a note and there is no auto-fix. My own Phase A fix inserted a `let` automatically. A statement-inserting auto-fix is the riskiest kind of edit for an agent to apply without review.
> - Map compound and nested writes get a note only.
> - I disagree with min's `(xs.get(k) ?? 0)` as the help. It turns an out-of-bounds write into a silent write of `0 + v`. Agents copy the help verbatim, so the help must fail loudly (`.unwrap()`) or leave the choice to the author.
> - Against web: "no auto-fix at all" throws away the most common case (`xs[i] += 1` with a local `i`), where the rewrite is exact.
>
> ## V3: what §2.22 says
> Merged wording: "A place is a local binding or a field path `s.f.g`. Its parts have no effects and cannot fail. `place = rhs` evaluates `rhs`, then stores. The store reads the root binding at that point, so a write that `rhs` makes to the same binding through a closure is not lost."
> - This covers web's and min's "rhs, then store". It also keeps the guarantee that plt and I kept.
> - I oppose plt's new typing rule (the receiver of a mutating method is a place resolved after the arguments). It contradicts the 6-0 call order (callee, receiver, then arguments). It also adds a second evaluation rule for a model to learn. List and Map are handles (argument-evaluation-order.md ~536), so `.set` already sees the current contents. Only a closure that rebinds `xs` itself behaves differently. If plt thinks that edge case matters, it belongs on its own ticket.
>
> ## V4: where the `xs[10] = fill()` example goes
> I accept devops's location: §2.18 call order, written as a `.set` call. However, no spec text may say "then panics" yet. The §3 table does not say what `List.set` does out of bounds (min M3). Merged: "§2.18 shows `xs.set(next(), fill())` to demonstrate argument order. The out-of-bounds sentence waits for the M3 follow-up." A spec example that states unspecified behaviour trains models on a guess.
>
> ## V5: follow-ups
> - Defer `List.update` (I proposed it as C).
> - Defer M3, but file it now. It gates the V4 wording.
> - No objection to either.
>
> STABLE: ready to vote

**Minimalism:**

> # Phase B round 1: MINIMALISM (min)
>
> **Position: NOPLACE.** Unchanged. All six seats put NOPLACE first, and none of the PLACE fallbacks has an advocate. sys B and devops 2 are both "only if the panel wants sugar", and nobody does. I agree with plt that a write half with no read half breaks get/put pairing. I agree with aiml that a legal `xs[i] = v` in the corpus teaches `xs[i]` reads.
>
> **V1 (help verb): the code is chosen at name resolution, and typecheck narrows the help.** Merged wording: "E0313 is chosen from the bracket contents at name resolution (§3.4, unchanged). The `help:` names the method for the receiver's type: `.set(i, v)` for List or Bytes, `.insert(k, v)` for Map. If the type is unknown, the help names both. It never says `.insert` alone for a List, and it never says `.get()` at a store." This is not a new mechanism. §3.4 already makes read help depend on the receiver type. web is right about the `List.insert` trap, and devops, sys, plt and aiml are right that we can usually narrow the help. The merged wording keeps both points.
>
> **V2 (compound fix): take devops's rule.** It is machine-applicable only when the index is a local, a literal or a constant. Otherwise the help suggests a `let` in a note, with no auto-fix. Map compound and nested writes get a note only. aiml's "auto-insert a `let`" is a larger tool feature with no demand behind it. web's "never auto-fix" throws away the easy, safe case. plt's `.unwrap()` help is fine as the note text. I drop my own "get/set pair" wording in favour of devops's.
>
> **V3 (§2.22 on field places): I change my wording, and I oppose plt's new typing rule.** plt is right that "the store reads the root, after `rhs`" still matters for a field path. In `s.n = f()` where `f` writes `s.m` through a closure, a root read before `rhs` would lose that write. My Phase A text ("`rhs` evaluates first and then the store happens") and web's are too loose. Merged wording: "A place is a `let mut` binding or a field path from one. A field path has no sub-expressions to evaluate. `place = rhs` evaluates `rhs`, then stores: the store reads the root binding and writes along the path, so a write that `rhs` makes to the same binding is not lost." aiml's `s.inner.count = f()` is a good example for this.
>
> I vote against plt's rule that a mutating method's receiver is a place resolved after the arguments. §2.18 (02_syntax.md:2000) already says the receiver is evaluated before the arguments. plt's rule changes the call order for one set of methods, and "mutating" is not a property the spec defines on methods today. That is a new semantic rule, carried in by a ticket that is meant to remove one. The closure guarantee in §2.22 was only ever needed because of index places. Once they are gone, nothing depends on it for `.set`. If plt wants the rule, it needs its own spec ticket.
>
> **V4 (panic example): I take devops's placement.** Move `xs.set(10, fill())` to §2.18, because it now shows call order, not place order. §2.22 gets the field example from V3. The difference from web, aiml and plt is only where the text goes, so I will not fight for it. If the majority keeps the example in §2.22, I accept that.
>
> **V5 (follow-ups): defer both.** Log `List.update` as a feature ticket that waits for evidence. aiml, sys, plt and web all agree. The out-of-bounds `List.set` behaviour is a real gap in §3, and it is the only write path left, so it needs its own ticket, filed now. It is not voted here.
>
> STABLE: ready to vote

#### Phase C — Final vote

No question was closer than 6-0, so Phase D did not run.

- **Q1: Does an assignment place admit an index? NOPLACE | PLACE** (6-0 NOPLACE)
  - **Systems:** NOPLACE

    > Reasoning: under NOPLACE, an element write is one visible call (`blink_list_set`) with one bounds check and one panic site. PLACE hides that same call behind `=`, which looks like a store to a register. PLACE also adds a lowering stage (now I0004) and a new E0601 store kind, and no code in the tree needs either. I withdrew my own B in round 1.
    > Concern: nested value updates (`a[i].f = v`) cost two element copies under get/change/set, and nothing in this decision makes that cost visible or tracks it.

  - **Web/Scripting:** NOPLACE

    > 1. **Vote:** NOPLACE.
    > 2. **Reasoning:** One rule is easy to learn: brackets hold types, and methods touch elements. A JS or Python dev picks that up in minutes. A bracket that you can write but not read generates Stack Overflow questions forever. Both PLACE fallbacks have no advocate, their authors included.
    > 3. **Concern:** New users will still type `xs[i] = v` on day one. The whole case therefore rests on E0313 giving an exact, copy-paste repair every time.

  - **PLT:** NOPLACE

    > Reasoning: A place is a get/put pair. Blink has no index read (§2.6, §3.4), so an index place would be a put with no get, and `op=` would need a hidden total read that panics. That read contradicts `get -> Option`. PLACE as sugar keeps that asymmetry and makes `[` depend on context again.
    > Concern: Nested value updates (`a[i].f[j] = v`) become get/modify/set chains, and a missing `set` silently drops the write under copy-on-bind. Users will feel this before `List.update` exists.

  - **DevOps:** NOPLACE

    > Reasoning: A bracket that is legal before `=` but illegal as a read would make every E0313 read diagnostic explain an exception. LSP go-to-definition and find-references would also need a hidden map from `[]=` to a method. With NOPLACE there is one spelling, and hover, rename and completion on `set`/`insert` work with no extra code. Nothing in the corpus uses the place, so the migration cost is zero.
    > Concern: If the E0313 walk for stores ships at a different time from the walk for reads, `blink check` could keep accepting `xs[0] = 5` and codegen could keep stopping at I0004. The two must land and be tested together.

  - **AI/ML:** NOPLACE

    > Reasoning:
    > - With one rule ("brackets hold types, never indexing"), a model can learn Blink from the spec alone, with no exception for the left side of `=`.
    > - A legal `xs[i] = v` would add to the strong training-data prior toward `xs[i]`. Models would then write more E0313 reads, and each one costs a repair round trip.
    > - NOPLACE also takes away a "which form?" choice (`m[k] = v` or `.insert`) from every Map write a model generates.
    >
    > Concern: models will still write `xs[i] = v` often from other-language priming. NOPLACE works only if the E0313 help is exact enough to fix that in one round (Q2, Q3).

  - **Minimalism:** NOPLACE

    > Reasoning: Two votes (§2.6 5-0, §3.4 6-0) already rule out value brackets, and no vote ever put an index place into the language. Removing the index place deletes a construct: no index-place lowering, no new E0601 store kind, no "bounds check at the store" rule, and no read/write asymmetry. No code anywhere uses it, so nothing migrates.
    > Concern: Nested struct-element updates (get, change, set) will get friction reports. The panel must answer them with evidence-gated `List.update` and not by bringing back place syntax.


- **Q2: E0313 help at a store names one verb from the receiver type (`.set(i, v)` for List/Bytes, `.insert(k, v)` for Map), both when the type is unknown, never `.insert` for a List** (6-0 YES)
  - **Systems:** YES

    > Reasoning: §3.4 already selects the read help from the receiver type, so no new mechanism is needed. Naming `List.insert` would swap an O(1) store for an O(n) shift that also changes the length. That repair compiles and is wrong at runtime.
    > Concern: the "type not known" branch can fire more often than expected on error-recovery paths, so users see the two-verb help where one verb would do.

  - **Web/Scripting:** YES

    > 1. **Vote:** YES.
    > 2. **Reasoning:** The §3.4 read help already reads the receiver type, so a verb picked from the type needs no new mechanism. The "never `.insert` for a List" guard is the most important line. `List.insert` compiles, and it silently shifts elements.
    > 3. **Concern:** The help can fall back to naming both verbs when the receiver type is unknown. That fallback must stay rare, or users get a choice they cannot make.

  - **PLT:** YES

    > Reasoning: The code stays a function of the bracket contents alone, as §3.4 requires. The help is a type-directed repair, and §3.4 already does this for reads. "Never `.insert` for a List" is essential for soundness, because that repair type-checks and changes the program's meaning.
    > Concern: When the receiver type is unknown, the two-verb help could still be followed wrongly. The help must name each verb with its receiver kind.

  - **DevOps:** YES

    > Reasoning: One exact verb is the best fix an editor can apply. §3.4 already chooses the read help from the receiver type, so this needs no new mechanism. The line that never offers `.insert` for a List stops a repair that compiles but shifts the elements.
    > Concern: When the receiver is an error type, the help "names both" and gives two choices, so it must not be machine-applicable. The ICE-free path for that case needs a test.

  - **AI/ML:** YES

    > Reasoning:
    > - A model in an edit loop copies the help verbatim, so one exact verb is the best repair signal.
    > - The "never `.insert` for a List" guard matters most for LLMs. Python's `list.insert` primes the wrong verb, and it compiles, then runs wrong without an error.
    > - §3.4 already makes the read help depend on the receiver type, so this rule adds no new mechanism.
    >
    > Concern: when the receiver type is unknown, the help names two verbs, and a model may pick the wrong one. The test suite must cover that path.

  - **Minimalism:** YES

    > Reasoning: This is the same mechanism §3.4 already uses for reads, so it adds no new mechanism. It meets §3.1, because every verb it names is a real repair. The "never `.insert` for a List" guard stops a repair that compiles and is wrong.
    > Concern: The "type unknown, name both" branch will be the one that nobody tests, so it needs its own diagnostic test.


- **Q3: machine-applicable fix `xs.set(i, xs.get(i).unwrap() op v)` for `xs[i] op= v` only when the index is a local, literal or constant and the receiver is a List or Bytes; otherwise a note** (6-0 YES (devops moved back from "no automatic fix"))
  - **Systems:** YES

    > Reasoning: when the index has no effects, `xs.set(i, xs.get(i).unwrap() op v)` is an exact rewrite. It keeps the evaluation order and the out-of-bounds panic. An index with effects would run twice, so it must not be auto-applied. The rewrite does two bounds checks where the store did one, but gcc -O2 usually merges them once both calls inline, so the cost is acceptable.
    > Concern: devops withdrew this rule in round 1. If Q3 fails, `blink fix` drops the most common safe case, and every `xs[i] += 1` needs a manual edit.

  - **Web/Scripting:** YES

    > 1. **Vote:** YES.
    > 2. **Reasoning:** `xs[i] += 1` with a local `i` is the common case. For that case the rewrite is exact, and it fails the same way (out of bounds panics). An auto-fix saves the user a round trip. With an index that has effects, the fix must not run the index twice, so a note with no auto-fix is correct.
    > 3. **Concern:** devops's round 1 was right that `.unwrap()` chooses "panic" for the author. `blink fix` users apply fixes in bulk without reading them, so the help should say, in plain text, that it panics when out of bounds.

  - **PLT:** YES

    > Reasoning: Rewriting `xs[i] op= v` to `xs.set(i, xs.get(i).unwrap() op v)` duplicates `i`. That keeps the meaning exactly when `i` is pure (a local, a literal or a constant), so a machine-applicable fix is correct only there. `.unwrap()` keeps the failure mode the author wrote: the element must exist. `?? 0` would change the meaning. Map and nested cases have no single correct repair, so they get a note only.
    > Concern: "Constant" must mean a compile-time `const`. It must not mean an arbitrary immutable binding whose initializer we might re-evaluate. Implement it on the resolved binding kind, not on the syntax.

  - **DevOps:** YES

    > Reasoning: In round 1 I moved to "no auto-fix", but sys, web, plt and aiml convinced me to move back. Out of bounds, `.unwrap()` panics, as the author's store would have. So with a pure index the rewrite is exact. The `handlers[0](req)` precedent is not the same case: there the correct repair depends on the enclosing function's return type. An index with effects keeps a `let` note and no auto-fix, because `blink fix` must never insert a statement the author did not read.
    > Concern: "Constant" must mean a `let` constant or a literal as name resolution sees them, and not an expression that looks pure. A module `let mut` read or a getter call must not count.

  - **AI/ML:** YES

    > Reasoning:
    > - `xs[i] += 1` with a local index is the most common compound shape in generated code. Under the old §2.22 it panicked out of bounds, so the `.unwrap()` rewrite is the faithful translation, not a guess.
    > - If there is no auto-fix in that case (devops's round-1 change), agents must hand-write the repair each time. That costs more tokens and gives more room for errors like min's silent `?? 0`.
    > - An index with effects gets a note only. That is correct: an auto-fix that inserts a statement is the riskiest edit for an agent to apply without review.
    >
    > Concern: `blink fix` applies `.unwrap()` automatically in code where the author wanted a default. The help text must say that it keeps the panic.

  - **Minimalism:** YES

    > Reasoning: With a pure index the rewrite is exact, and `.unwrap()` keeps the panic the author expected. Refusing the fix for that case adds friction with no safety gain. The note-only cases (an index with effects, Map, nested) keep the tool out of places where it would have to guess.
    > Concern: "Constant" must mean a `const` binding, checked by the compiler, and not "any name that looks pure", or the fix will run an index with effects twice.


- **Q4a: §2.22 text — a place is a local binding or a field path `s.f.g`; `place = rhs` evaluates `rhs`, then reads the root binding, then stores** (6-0 YES)
  - **Systems:** YES

    > Reasoning: a field path has no sub-expressions, so "evaluate `rhs`, then read the root, then store" is the whole rule. Loading the root after the call costs nothing. The text keeps the 6-0 closure guarantee for field places.
    > Concern: the text says "local binding" and not "`let mut` binding", so the implementer must keep the existing mutability check. The wording must not seem to relax it.

  - **Web/Scripting:** YES

    > 1. **Vote:** YES.
    > 2. **Reasoning:** It is short, it matches what a Python or JS dev expects from `s.f = f()`, and it keeps the voted guarantee that a write the closure makes in `rhs` is not lost. My Phase A text left out the root read, and this text fixes that.
    > 3. **Concern:** The wording "reads the root binding, then stores" can read as internal detail to a newcomer. The §2.22 example (`s.inner.count = f()`) must show why it matters.

  - **PLT:** YES

    > Reasoning: For a field path the three orderings round 1 proposed are the same, because the path holds only names. This text keeps the one guarantee the 6-0 vote bought: the root is read at the store, after `rhs`.
    > Concern: None on substance. The text must say "a `let mut` binding" at the root, so that it does not read as permitting assignment through an immutable binding.

  - **DevOps:** YES

    > Reasoning: This is true for field paths and it keeps the 6-0 guarantee: the root is read after `rhs`. It adds no new diagnostic surface. min's point about `s.n = f()` shows why the root-read sentence must stay.
    > Concern: Codegen that loads the root before it calls `rhs` would break this without any diagnostic, so the spec example needs a corpus test that proves the closure write is kept.

  - **AI/ML:** YES

    > Reasoning:
    > - The wording is short and exact. It keeps the voted guarantee that a closure write in `rhs` is not lost (min's `s.n = f()` case).
    > - The order "`rhs`, then read the root, then store" is one sequence a model can apply the same way to every place.
    >
    > Concern: none from my seat beyond making sure the §2.19 compound text uses the same order words.

  - **Minimalism:** YES

    > Reasoning: It is the smallest true statement. A place is a path of names, and the root is read after `rhs`. It keeps the one guarantee that the 6-0 eval-order vote protected, and it drops all the index machinery.
    > Concern: "local binding" must say `let mut`, or the text reads as though an immutable binding is a place.


- **Q4b: plt's rule that a mutating method reads its receiver after its arguments. IN | SEPARATE** (6-0 SEPARATE (plt moved from IN))
  - **Systems:** SEPARATE

    > Reasoning: plt's rule changes the §2.18 receiver order (6-0) for every mutating method, user methods included. The spec does not yet define "mutating", and it has not settled whether List is a handle (aiml) or copied on bind (plt). The codegen for either answer is trivial, so a separate ticket blocks nothing. It lets the panel first decide what `xs` is at the machine level.
    > Concern: until that ticket lands, `xs.set(i, f())` where `f` rebinds `xs` through a closure has behaviour the spec does not state. The ticket must be filed now, not left as "later".

  - **Web/Scripting:** SEPARATE

    > 1. **Vote:** SEPARATE.
    > 2. **Reasoning:** The plt rule is a real question, but it changes the order of every mutating call (`push`, `insert`, user methods), and the spec does not define "mutating". A rule that users cannot predict from what they see must not come in through a ticket that removes a construct. It needs its own ticket, tests and examples.
    > 3. **Concern:** Until that ticket lands, the spec leaves `xs.set(i, f())` unstated in the case where `f` rebinds `xs` through a closure, so the follow-up must be filed now and not lost.

  - **PLT:** SEPARATE

    > Reasoning: I change my position. sys, web, devops and min are right about scope. The rule changes the §2.18 receiver order for a whole class of methods, user methods included, and it needs its own definition of "mutating" and its own tests. A rule that large must not come in on a ticket that removes a construct. The under-determination I raised is still real. If `f` rebinds `xs` through a closure, `xs.set(i, f())` could write either the old value or the new one. The spec does not decide this, and aiml's "List is a handle" contradicts 03c:40's copy-on-bind. So this decision must file that ticket and record the open question. It must not claim the question is closed.
    > Concern: If the follow-up ticket is not filed, removing the index place silently drops the §2.22 closure guarantee with no rule to replace it. That leaves exactly the under-determined, no-diagnostic behaviour that §3.4 E0301 rejects.

  - **DevOps:** SEPARATE

    > Reasoning: The rule changes call order for every mutating method, user methods included, and the spec has no definition of "mutating". A change that size needs its own ticket, its own tests and a codegen check. It must not come in as part of removing an example. I agree with plt that the gap is real, so the ticket must be filed now.
    > Concern: Until that ticket lands, `xs.set(i, f())` where `f` rebinds `xs` has behavior the spec does not state, and tooling cannot explain it.

  - **AI/ML:** SEPARATE

    > Reasoning:
    > - plt's sentence makes one set of methods run in a different order from the 6-0 call order in §2.18 (receiver before arguments). "Mutating method" is not a property the spec defines today.
    > - It is a second evaluation rule for a model to learn, carried in by a ticket that removes a construct.
    > - plt's gap (`xs.set(i, f())` where `f` rebinds `xs`) is real. It deserves its own ticket and tests.
    >
    > Concern: until that ticket lands, the spec leaves the edge case unstated. Models will assume plain call order, which may differ from what codegen does.

  - **Minimalism:** SEPARATE

    > Reasoning: plt's sentence changes the 6-0 §2.18 call order for a set of methods that the spec does not define. This ticket exists to remove a construct, so it must not add a new evaluation rule. The question is real. It gets its own ticket.
    > Concern: Until that ticket lands, the spec does not say what `xs.set(i, f())` does when `f` rebinds `xs` through a closure. The follow-up must be filed, not only mentioned.


- **Q5: move the `fill()` example to the call-order rule as `xs.set(10, fill())`. MOVE | STAY** (6-0 MOVE (devops moved from STAY))
  - **Systems:** MOVE

    > Reasoning: the example is now a call, so it shows call argument order (§2.18), not place order. One home per rule, with a cross-reference from §2.22.
    > Concern: readers who know the old §2.22 text may miss the move if the cross-reference is weak.

  - **Web/Scripting:** MOVE

    > 1. **Vote:** MOVE.
    > 2. **Reasoning:** The example is now a call, and a reader who asks "why did fill print before the panic" searches call order. The cross-reference from §2.22 covers the reader who looks where the example was. That gives one home per rule.
    > 3. **Concern:** A missing or vague cross-reference strands readers who go to §2.22 because they remember the old index example.

  - **PLT:** MOVE

    > Reasoning: With Q4b SEPARATE, `xs.set(10, fill())` printing "fill" and then panicking follows from §2.18 call order alone: receiver, then arguments, then the call. So the example belongs with the rule that explains it. §2.22 gets a field example and a cross-reference.
    > Concern: The moved example must not imply anything about the receiver-rebinding case, which stays open under Q4b.

  - **DevOps:** MOVE

    > Reasoning: In round 1 I gave way to STAY. But sys, web, plt and min then all took the move, and their reason is correct: the example now shows call order, not place order. A user who asks "why did fill print before the panic" looks in call order. §2.22 keeps a cross-reference, so a reader who starts there still finds it.
    > Concern: The cross-reference must point to the §2.18 heading by name, so it does not go stale when section numbers change.

  - **AI/ML:** MOVE

    > Reasoning:
    > - The example now shows argument order in a call, so it belongs in the call-order section, with one home per rule and a cross-reference from §2.22.
    > - A model that retrieves §2.22 then sees only place rules, with no call example to confuse with an assignment form.
    >
    > Concern: readers who remember the old §2.22 example look there first. The cross-reference must be explicit.

  - **Minimalism:** MOVE

    > Reasoning: Once the example is `xs.set(10, fill())`, it demonstrates call order, not place order. Each rule should have one home. A cross-reference from §2.22 covers readers who look for it where it was.
    > Concern: The moved example must keep its "prints fill first" point, and not turn into a bare panic demo.


- **Q6: the List table says `set` panics out of bounds. ROWNOTE | DEFER** (6-0 ROWNOTE (aiml moved from DEFER))
  - **Systems:** ROWNOTE

    > Reasoning: the runtime already panics (bootstrap/runtime_core.h:715-717, "list set index out of bounds"). The spec should state what the machine does, and the moved example then states a fact. A follow-up can still propose a `Bool` or `Result` return.
    > Concern: the edit must also narrow §3 ~407 ("no index-out-of-bounds panics") so that it covers `.get()` only. Otherwise the two lines contradict each other.

  - **Web/Scripting:** ROWNOTE

    > 1. **Vote:** ROWNOTE.
    > 2. **Reasoning:** The runtime already panics (runtime_core.h:717), and `.set` is now the only element-write path. Users need the table to say what happens, not a follow-up promise. Writing down today's behaviour costs nothing and keeps the moved example true. A `Bool`/`Result` return can still be proposed later.
    > 3. **Concern:** §3 ~407 says there are "no index-out-of-bounds panics". That sentence must be narrowed to `.get()` in the same edit, or the spec contradicts itself on the first page a newcomer reads.

  - **PLT:** ROWNOTE

    > Reasoning: The runtime already panics (runtime_core.h:717). A spec that states no behaviour for the only element-write path is under-determined, and a spec example must not assert behaviour the spec leaves unstated. The row note also forces §3 ~407 to say "no out-of-bounds panics on *reads*", which is the true scope of that claim. A later `Result` return stays open to a follow-up.
    > Concern: If the §3 ~407 sentence is not qualified in the same edit, the spec contradicts itself, saying both "no index-out-of-bounds panics" and "`set` panics".

  - **DevOps:** ROWNOTE

    > Reasoning: The runtime panics today (runtime_core.h:717). The §3 table must say so before any help, note or example claims a panic (§3.1: a diagnostic must not state behavior the spec does not define). One row note makes spec and runtime agree now. A follow-up can still propose a `Bool` or `Result` return.
    > Concern: The §3 ~407 sentence "no index-out-of-bounds panics" must be reworded in the same edit to say it applies to `.get()`. If it is not, the spec contradicts itself in two lines.

  - **AI/ML:** ROWNOTE

    > Reasoning:
    > - I change my round-1 position, based on the moderator fact that the runtime panics today (runtime_core.h:717).
    > - Stating behaviour that already exists is documentation, not new design. It makes the moved example true in the spec.
    > - A spec that states the failure mode beats one that is silent. A silent spec makes models guess, and the guesses become training data.
    >
    > Concern: §3 ~407 says there are "no index-out-of-bounds panics". The same edit must qualify that sentence to say reads, or the spec contradicts itself.

  - **Minimalism:** ROWNOTE

    > Reasoning: The runtime already panics (runtime_core.h:717). Stating that adds no surface. It documents behaviour that exists, and it lets the moved example stay true without hedging. A `Bool`/`Result` return is a real API change and stays a follow-up.
    > Concern: §3 ~407 says there are "no index-out-of-bounds panics". The same edit must limit that sentence to `.get()`, or the spec contradicts itself.


### Open question recorded by the panel

Q4b SEPARATE leaves one case open. Call order evaluates the receiver before the arguments (§2.22). For `xs.set(i, f())` where `f` rebinds `xs` through a closure, the spec does not say whether `set` writes into the old `xs` or the new one. The old index-place rule ("a write that `rhs` makes to the same binding is not lost") now covers field paths only. This is a separate spec question, filed with the decision, and not settled by it.

### Final Spec

```blink
type Stats {
    count: Int
    total: Int
}

fn main() {
    let mut xs = [10, 20, 30]
    let i = 1
    xs.set(0, 5)                            // an element write is a method call
    xs.set(i, xs.get(i).unwrap() + 1)       // the E0313 fix for `xs[i] += 1`

    let mut ages: Map[Str, Int] = Map()
    ages.insert("bob", 41)                  // not `ages["bob"] = 41`

    let mut s = Stats { count: 0, total: 0 }
    s.total = 5                             // a field path is a place
}
```

- A place is a `let mut` binding, or a field path whose root is one. An index is not a place (§2.22 *Assignment places*).
- `place = rhs` evaluates `rhs`, then reads the root binding, then stores.
- `xs[i] = v` and `xs[i] op= v` are `error[NoIndexOperator]` (E0313). The help names one write method chosen from the receiver's type, never `.insert` for a `List`, and both methods with no machine fix when the type is not known (§3.4).
- `xs[i] op= v` on a `List` or `Bytes` gets the machine fix `xs.set(i, xs.get(i).unwrap() op v)` only when `i` is a literal, a local binding or a `const` by name resolution. Otherwise a `note:` and no machine fix.
- The element-write example is `xs.set(10, fill())` under §2.22 *What each form evaluates*.
- `List.set` panics when the index is out of bounds (§3 List table). A read through `.get()` never panics.

### AI-First Review

| Criterion | Result | Why |
| --- | --- | --- |
| Learnability | pass | One rule for brackets: they hold types, never an index, whether read or written. |
| Consistency | pass | Stores take the same E0313 path as reads, and a place is a path of names, as before the eval-order vote. |
| Generability | pass | Every element write is a method a model already uses for other writes (`push`, `insert`). |
| Debuggability | pass | The E0313 help names one method chosen from the receiver's type, with a machine fix for the common compound case. |
| Token efficiency | fail | `xs[i] += 1` becomes `xs.set(i, xs.get(i).unwrap() + 1)`. The `List.update` follow-up addresses this. |

One criterion fails, so the decision is not flagged.
