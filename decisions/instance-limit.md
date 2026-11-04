[< All Decisions](../DECISIONS.md)

# The Limit on Generic Instances — Design Rationale

**Gap:** A generic function or type that needs ever larger copies of itself made `blink check` hang or dump core, and the spec had no text on it. Explicit type arguments (`r[List[T]]`), a type that holds itself at a larger type argument (`P[(T, T)]`), two functions that call each other with a growing type, and a finite chain whose type doubles at each level all gave this fault. The limit had to stop memory growth as well as time. The panel also had to say what a call from a function to itself does with its own type parameters.

**Result:** 5-1 on Q1 and Q5, 6-0 on Q3, Q4 and Q6 (Q4 and Q6 stood 3-3 in Phase C and went 6-0 in Phase D), and Q2 settled in round 1. A check of the declarations rejects a generic cycle whose type argument grows: `InstantiationCycle` (E0324). A fixed budget in monomorphization covers what the check does not see: `InstanceLimit` (E0325). Each instance weighs 1 plus the nodes in its type arguments, and the total is 2^20 (1,048,576). A call from a function to itself follows the rule of any other call. E0324 and E0325 run only on a front end with no errors.

| Q | Result | Tally |
|---|---|---|
| Q1 | A check on declarations rejects a generic cycle whose type argument grows, with no number. Code E0324. A fixed limit in mono covers what it does not see. Code E0325. A declaration nothing uses also fails | 5-1, Minimalism dissents |
| Q2 | A method call whose impl the type fixes is an edge. A call on a bound (`x.m()` with `x: T`) is not an edge, so growth through a bound goes to the budget | settled in round 1 (PLT and Systems withdrew their options) |
| Q3 | One budget. Each instance weighs 1 + the nodes in its type arguments. The total is 2^20, and the message prints 1,048,576 | 6-0 |
| Q4 | A self-call follows the rule for any other call. No fallback. `r([], n - 1)` in `fn r[T]` is E0301, with help `r[T]([], n - 1)` | 6-0 after 3-3 in Phase C |
| Q5 | E0324 and E0325 run only on a front end with no errors. A file with a type error shows that error first | 5-1, DevOps dissents |
| Q6 | The E0325 span is where the type grows. The note always names the root call in user code. With no grown repeat, the span is the crossing call | 6-0 after 3-3 in Phase C |

**Settled by all six:**

- No flag, annotation or configuration key changes the budget. The verdict is the same on each host. A release can raise the number. There is no limit on time, memory or depth alone.
- The value of `n` plays no part. `if false { r[List[T]](...) }` does not change the verdict.
- The compiler adds the size of a type before it builds the type text or the C name. An over-budget program stops with E0325 and does not run out of memory.
- `blink check`, the LSP and the daemon report each of these errors, and none hang.
- A non-regular type behind a `List` is the same case: `type Q[T] { v: T, next: List[Q[List[T]]] }`. No boxed form makes it legal.
- A diagnostic never prints a type in full: depth 3, then `...`. Each cycle gets one diagnostic.
- The repairs are `help:` text, not machine-applicable: `type Nest[T] { One(v: T), Many(items: List[Nest[T]]) }`, and `type P[T] { Leaf(v: T), Node(l: P[T], r: P[T]) }` for the type that holds `P[(T, T)]`.
- Some finite programs must compile. A check of declarations may never reject them. They are the `Wrap` program (a call on a bound ends the chain at `Wrap`), the `W` program of AI/ML (it prints `7`), and the `List` delegate program of PLT. Each printed `7` on the pinned compiler.

**Measured fact for Q4.** A throwaway patch made a self-call follow the rule of any other call. The corpus passed 2841 of 2842 files, and the typecheck suite passed 178 of 178. No file in `src`, `lib/std` or `lib/pkg` uses the shape, so no bootstrap steps are needed to migrate. The one file that failed pinned the old E0300 on `grow([x], n-1) + grow((x, x), n-1)`, a program that was never legal; under the new text it is E0324. The new E0301 cases are all of the family of an empty value as an argument, and each has an explicit-argument repair: `r([], n-1)`, `[]` through a closure self-call, `let e = []` then a self-call, `Map()` and `None`. A tail `r([], n-1)` in a function that returns `List[T]` and an annotated `let` still compile by expected type. A method's own `U` follows the same rule, and an impl `T` that the receiver fixes does not break. The same patch fixed `swap[B, A](b, a, n - 1)`, which gave a `TypeError` before. Without the limit, the same patch makes `blink check` hang on a self-call that grows (`k4` below), so the self-call change and the limit have to ship together.

### The Programs

The panel used these programs. Each hung `blink check`, or stopped it with a crash, before this decision.

```blink
// k1: an explicit type argument that grows
fn r[T](x: T, n: Int) -> Int {
    if n == 0 { return 0 }
    r[List[T]]([x], n - 1)
}
fn main() { io.println("{r(1, 3)}") }
```

```blink
// k2: a type that holds itself at a larger type argument
type P[T] { Leaf(v: T), Node(p: P[(T, T)]) }
fn main() {
    let x: P[Int] = P.Leaf(1)
    match x {
        P.Leaf(v) => io.println("{v}")
        P.Node(_) => io.println("node")
    }
}
```

```blink
// k3: two calls at each level, so the count of instances doubles at each level
fn grow[T](x: T, n: Int) -> Int {
    if n == 0 { return 0 }
    other([x], n - 1) + other((x, x), n - 1)
}
fn other[U](y: U, n: Int) -> Int {
    if n == 0 { return 0 }
    grow([y], n - 1) + grow((y, y), n - 1)
}
fn main() { io.println("{grow(1, 3)}") }
```

```blink
// k4: a self-call at another type (E0300 `argument 1 of r expects T, got List[T]` before)
fn r[T](x: T, n: Int) -> Int {
    if n == 0 { return 0 }
    r([x], n - 1)
}
```

```blink
// k5: a generic fn named as a value in its own body
fn r[T](x: T, n: Int) -> Int { let f: fn(List[T], Int) -> Int = r
 if n == 0 { 0 } else { f([x], n - 1) } }
```

- **k6:** growth through trait dispatch. `fn h[T: Grow](x: T, n: Int) -> Int { x.g(n) }` and `impl[U: Grow] Grow for Box[U]` calls `h(Box { v: self }, n - 1)`. The impl is not known until the instance exists.
- **k7:** no cycle. A chain of fns, each `fn f1[T](x: T) -> Int { f2((x, x)) }`, so the type doubles at each level. It is finite, and `blink check` passes only after it uses 1.07 GB.

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in independent-proposal → debate → ballot → debate → re-vote rounds. The excerpts below are verbatim. Code names for probes, ticket numbers and scratch paths are cut. A program name such as `k4` is defined in *The Programs*.


#### Phase A — Independent proposals

- **Systems:**
  > # Sys seat: a cycle check and two fixed limits
  >
  > A front-end check rejects instance cycles that grow a type; it has no number and runs before mono. Mono also holds two fixed limits for what that check cannot see: type size 256 and instance count 65536. No flag changes them, so every host gives the same verdict.
  >
  > ## 1. Legality
  >
  > k1, k2, k3, k5 are illegal. Each needs infinite instances if reached, and the compiler does not read `n`. k4 stays E0300.
  >
  > **Rule:** build a graph over the type parameters of every generic fn and type. A call, a generic fn named as a value, or a field type adds an edge from each parameter in a type argument to the callee's binder. A bare `T` has weight 0; a `T` inside a constructor (`List[T]`, `(T, T)`) has weight 1. A cycle with weight above 0 is an error. Edges use the arguments typecheck recorded, so inferred calls count (k3). Go has this check (`types2/mono.go`).
  >
  > It never rejects a finite program: mono does not prune branches, and *No erasure* keeps phantom arguments. A cycle that does not grow stays legal. I ran this; it prints `0`:
  >
  > ```blink
  > fn a[T, U](x: T, y: U, n: Int) -> Int {
  >     if n == 0 { return 0 }
  >     b(y, x, n - 1)
  > }
  > fn b[V, W](x: V, y: W, n: Int) -> Int {
  >     if n == 0 { return 0 }
  >     a[W, V](y, x, n - 1)
  > }
  > fn main() { io.println("{a(1, "s", 3)}") }
  > ```
  >
  > Non-regular types are illegal, also behind a `List`: `type Q[T] { v: T, next: List[Q[List[T]]] }` dumps core today. Indirection changes layout, not instance count. Rust accepts `Box<P<(T, T)>>` until a method instantiates it, then fails after mono; I do not want that delay.
  >
  > ## 2. Limits
  >
  > The graph cannot follow growth through trait dispatch. This has no generic call edge and hangs today (exit 124 at 25 s):
  >
  > ```blink
  > trait Grow { fn g(self, n: Int) -> Int }
  > impl Grow for Int { fn g(self, n: Int) -> Int { n } }
  > impl[T: Grow] Grow for List[T] {
  >     fn g(self, n: Int) -> Int {
  >         if n == 0 { return 0 }
  >         [self].g(n - 1)
  >     }
  > }
  > fn main() { io.println("{[1].g(3)}") }
  > ```
  >
  > | Limit | Measures | Value |
  > |---|---|---|
  > | Type size | nodes in the type tree. A named type counts 1 plus its arguments, not its fields | 256 |
  > | Instance count | distinct fn and type instances in the program | 65536 |
  >
  > Evidence (gen1):
  > - The deepest written type in `src`, `lib`, `tests` has 4 bracket levels.
  > - Table instances: 8 for `blink check src/blinkc_main.bl`, at most 29 in a 1-in-6 corpus sample (473 files). The trace counts `mono_table` rows; if type instances live elsewhere, measure again before fixing the number.
  > - 14 levels of `[x]` + `Some(x)`: about 32000 instances, 0.43 s, 150 MB (4.6 KB each). So 65536 costs about 300 MB, by estimate.
  > - 14 levels of `[x]` + `(x, x)`: same count, 12.1 s, 386 MB. Type text is the cost, so limit size. A depth limit of 64 passes a type with 2^30 leaves, and depth is at most size.
  >
  > **Passing the limit.** A finite program under both limits is legal, whatever its shape. A slow grower only takes more steps to fail, because size stops every chain. A 7-level doubling tuple fits (255 nodes). Level 8 does not; that value is 256 fields by value. The verdict depends on the instance set, never on walk order, stack or RAM. Walk order can change which limit is named first, so both share one code.
  >
  > ## 3. Memory and time
  >
  > - **k3** never starts mono. The check is linear in edges, so no instance exists when the error appears.
  > - **k3 through traits:** the tuple arm passes size 256 at level 8, in about 2^8 instances. A `[x]` + `Some(x)` shape stops at count 65536. Each limit is checked before the instance enters the table, so the table has a hard top.
  > - **Size is O(1):** store it, saturating, on the interned type from its arguments' sizes. The pool grows per level, not per leaf.
  > - **Budget:** under 1 GB in the worst case, by estimate, not a measured worst case.
  > - **Printing:** a diagnostic prints a type to depth 3, then `...` and the size. Otherwise the error path is itself the 2^n bomb.
  >
  > ## 4. Diagnostics
  >
  > **E0324 `InstantiationCycle`** (k1, k2, k3, k5). The span is the first growing edge in source order: call, fn value, or field type. Notes name each hop.
  >
  > ```
  > error[InstantiationCycle]: `r` needs a new instance of itself with a larger type, without end
  >   --> k1.bl:3:5
  >   |
  > 3 |     r[List[T]]([x], n - 1)
  >   |     ^^^^^^^^^^ `T` of `r` becomes `List[T]` here
  >   = note: the instances are r[T], r[List[T]], r[List[List[T]]], ...
  >   = note: the compiler builds one instance per type argument list. The value of `n` does not end this
  >   = help: keep one type through the recursion. Hold the growth in a recursive type:
  >           `type Nest[T] { One(v: T), Many(items: List[Nest[T]]) }`, and make `r` take `Nest[T]`
  > ```
  >
  > The repair exists (rule 1). This prints `3`:
  >
  > ```blink
  > type Nest[T] { One(v: T), Many(items: List[Nest[T]]) }
  > fn r[T](x: Nest[T], n: Int) -> Int {
  >     if n == 0 { return 0 }
  >     1 + r(Nest.Many([x]), n - 1)
  > }
  > fn main() { io.println("{r(Nest.One(1), 3)}") }
  > ```
  >
  > For k2 the help is `type P[T] { Leaf(v: T), Node(left: P[T], right: P[T]) }`, which also runs. Neither is machine-applicable: the author picks the shape.
  >
  > **E0325 `InstanceLimit`** (dispatch growth, over-count). The span is the call in non-generic code that starts the chain. Notes give the limit, its value, and the first 4 and last 2 hops. The help is the same repair, or "write the concrete type at the hop shown".
  >
  > ## 5. When it fires
  >
  > - **E0324 fires at the declaration, with no instance.** k1's body and `P[T]` report `ok` today when nothing uses them; both become errors. A library author sees the fault in their own `blink check`, not a user two packages away. Dead code can now break a build, and that is fine: a dead bomb is one call from live.
  > - **E0325 fires only when an instance is reached.** `blink check` and the LSP run mono, so they report it (rule 2).
  >
  > The brief's k5 has no `main` and reports `ok` today (exit 0). With a `main` that calls `r`, it hangs (exit 124). E0324 rejects both.
  >
  > ## Tradeoffs
  >
  > - **Two mechanisms.** The limits alone stop every reached bomb, so they must ship. The cycle check adds the declaration-time error and a message with no magic number. My vote is both; if the panel wants one, keep the limits.
  > - **Trait growth gets the weaker error.** No simple graph covers dispatch: an impl can peel `List[U]` as well as add to it.
  > - **Fixed numbers can be wrong.** Rust's `recursion_limit` makes a verdict depend on an attribute. Raising a constant later is compatible; removing a knob is not. So no knob now.

- **Web/Scripting:**
  > #, web seat
  >
  > **Position: a plain rule with no number and no flag, then two fixed limits for the shapes the rule cannot see.**
  >
  > What a Python dev learns in 5 minutes: "Blink builds one copy of a generic per type. A generic that reaches itself with a bigger type needs endless copies, so it does not compile. The value of `n` does not matter."
  >
  > ## 1. What is legal
  >
  > k1, k2, k3 and k5 are illegal, and a rule decides that, not a limit. k4 already fails in 0.0 s; k1 is k4 with a way around that error.
  >
  > **Rule (`EndlessGeneric`, E0324).** Build a graph over type parameters. Each use of a generic adds an edge from each parameter in its type arguments to the parameter it fills. The edge is "growing" if the parameter sits inside a bigger type (`List[T]`, `(T, T)`). A cycle with a growing edge is an error. Uses that count: calls (written or inferred arguments), a generic fn named as a value (k5), field types (k2), and method calls whose impl the type fixes.
  >
  > These stay legal (gen1 runs this today):
  >
  > ```blink
  > fn flat[T](x: List[T], n: Int) -> Int {     // T stays T
  >     if n == 0 { return x.len() }
  >     flat([x.get(0).unwrap()], n - 1)
  > }
  > fn fixed[T](x: T, n: Int) -> Int {          // List[Int] holds no T: one more copy, then done
  >     if n == 0 { return 0 }
  >     fixed[List[Int]]([1], n - 1)
  > }
  > fn step2[T](x: T) -> Int { step3([x]) }     // grows once, no cycle
  > fn step3[U](y: U) -> Int { 1 }
  > fn main() { io.println("{flat([1], 2)} {fixed("s", 2)} {step2(1)}") }
  > // prints: 1 0 1
  > ```
  >
  > ## 2. The limits
  >
  > Two new probes show the rule is not enough alone:
  >
  > - **k6, growth through trait dispatch.** `fn h[T: Grow](x: T, n: Int) -> Int { x.g(n) }`, and `impl[U: Grow] Grow for Box[U]` calls `h(Box { v: self }, n - 1)`. The edge from `x.g` is not known until mono. `blink check`: exit 124 at 25 s.
  > - **k7, no cycle.** A chain of 24 fns, each `fn f1[T](x: T) -> Int { f2((x, x)) }`. `blink check` passes after **14.7 s and 1.07 GB**. It is finite, and it is still a trap.
  >
  > So mono enforces `GenericLimit` (E0325) with two fixed numbers:
  >
  > | Measure | Value | Why |
  > |---|---|---|
  > | Size of one type argument, written out (`(Int, Int)` is 3) | 1,024 nodes | Depth misses doubling: depth 10 of `(T, T)` has 2^10 leaves |
  > | Distinct instances in one build | 65,536 | Stops fan-out |
  >
  > Size covers depth (a type at depth n has size at least n), so a depth limit adds nothing. A type that grows one level per step passes until level 1,024. That is correct: each level costs little, and the limits still end it.
  >
  > For scale: `blink check src/cli.bl` logs 12 instances on `blink.mono`, longest argument text 128 characters. That trace may undercount; measure the corpus before fixing the numbers.
  >
  > **A user cannot change them.** No flag, annotation or config key. TS2589, Rust's `recursion_limit` and C++'s `-ftemplate-depth` teach people, and agents, to raise a number or cast to `any`. With no knob, the only repair is in the code, and a program compiles the same on each machine. Cost: a real program over a limit must change its types. If that ever occurs, we raise the number in a release.
  >
  > ## 3. Memory
  >
  > - **k3 and each other cycle the rule sees:** the rule runs in the type check, on a graph linear in the source. E0324 stops the pipeline **before mono**, so k3 makes no instances and nothing doubles.
  > - **Doubling the rule misses (k7, k3 through dispatch):** the compiler computes a type's size from its parts **before it builds the type or its text**, with saturating arithmetic. k7 stops at about level 10, not 24.
  > - **Bound:** 65,536 x 1,024 is about 67M nodes at worst, about 4 GB at 64 bytes each with no sharing. This leaves out instance bodies. If it is too high, cut the instance limit, not the size limit.
  > - **Printing:** a diagnostic prints three levels of a type, then `...` and the size. Never the full text.
  >
  > ## 4. Diagnostics
  >
  > | Shape | Code | Span | Names | Repair |
  > |---|---|---|---|---|
  > | k1, k5 | E0324 | the call or the fn value | fn, the type it reaches | a recursive type |
  > | k3 | E0324 | first growing edge | each fn on the cycle | same |
  > | k2 | E0324 | the field type | type, variant, field | `P[T]` in the field |
  > | k6, k7 | E0325 | the call over the limit, note at the root in user code | path, type elided, size | a recursive or non-generic type at that call |
  >
  > No machine-applicable fix: a tool cannot pick the new type. In full, for k1:
  >
  > ```
  > error[EndlessGeneric]: `r` calls itself with a type that grows without end
  >  --> k1.bl:3:5
  >   |
  > 3 |     r[List[T]]([x], n - 1)
  >   |     ^^^^^^^^^^ `r[T]` needs `r[List[T]]`
  >   = note: Blink builds one copy of `r` per type: `r[Int]`, `r[List[Int]]`, ...
  >   = note: `n` stops the calls at run time. The compiler does not read values.
  >   = help: keep one type at each level, with a recursive type:
  >             type Nest[T] { One(v: T), Many(items: List[Nest[T]]) }
  >             fn r[T](x: Nest[T], n: Int) -> Int
  > ```
  >
  > I ran that repair (rule 1). It prints `0`:
  >
  > ```blink
  > type Nest[T] { One(v: T), Many(items: List[Nest[T]]) }
  > fn r[T](x: Nest[T], n: Int) -> Int {
  >     if n == 0 { return 0 }
  >     r(Nest.Many([x]), n - 1)
  > }
  > fn main() { io.println("{r(Nest.One(1), 3)}") }
  > ```
  >
  > For k2 I also ran `type P[T] { Leaf(v: T), Node(l: P[T], r: P[T]) }`; it prints `1`. It loses the balance that `P[(T, T)]` promised, and the help must say so. I did not run a repair for k6 or k7; someone must, before the E0325 help text is fixed.
  >
  > k4 keeps E0300. Its help must never offer `r[List[T]](...)`, because that edit now gives E0324.
  >
  > ## 5. When it fires
  >
  > - **E0324 fires at the definition, used or not**, as k4 does and as in Go. `blink check` reports it on a library with no `main`, and the LSP shows it as you type. The author sees it, not a user three packages away.
  > - **One behavior changes:** k9 (k2's `P`, no uses) passes `blink check` today and would fail. I accept that, with no warning release; run the corpus to confirm nothing else has this shape.
  > - **E0325 fires in mono**, so `blink check`, the LSP and the daemon report it (rule 2) and none hang. It needs a root instance, so an unused generic cannot report it. The user then sees it with a path back into the library.
  >
  > ## Tradeoffs
  >
  > - **Two mechanisms, not one.** A limit alone is less text, but k1 would run to level 1,024 and then say "limit", not "your function grows". Error quality is why I want the rule. Most users will never see E0325.
  > - **Against rejecting:** Haskell and C# run k2 through uniform representation or runtime instantiation. Blink monomorphizes.
  > - **Precedent:** Go rejects this at the definition ("instantiation cycle"). ECMA-335 has an expanding-cycle rule. Rust uses limits only.
  >
  > ## Bug found while probing
  >
  > The rule calls a swap legal, but gen1 rejects it:
  >
  > ```blink
  > fn sw[A, B](a: A, b: B, n: Int) -> Int {
  >     if n == 0 { return 0 }
  >     sw[B, A](b, a, n - 1)
  > }
  > fn main() { io.println("{sw(1, "a", 3)}") }
  > // error[TypeError]: argument 2 of `sw` expects B, got A
  > ```
  >
  > It looks as if `A := B` and `B := A` apply in sequence, not at once. I did not read the code or file a ticket.

- **PLT:**
  > # plt seat:
  >
  > **Position.** Two rules. A graph check decides at the declaration if instances have no end, so no depth limit. A fixed budget covers finite programs that are too large. Measurement shows that one limit cannot do both jobs.
  >
  > ## 1. Legality: Rule A, no growing cycle
  >
  > Each type parameter (of a fn, type or impl) is a vertex. Each site that makes an instance adds edges: a call, explicit list, fn value, constructor, field type, annotation, or a method that a type instance pulls in.
  >
  > | Site | Edge | Weight |
  > |---|---|---|
  > | `g[T]` | T to g's param | 0 |
  > | `g[List[T]]`, `g[(T, T)]` | T to g's param | +1 (depth of T) |
  > | `x.foo()`, `x: T`, `impl[U] Foo for Box[U]` | T to U | -1 (depth of U) |
  > | `g[T.Out]` | T to g's param | infinite |
  >
  > A cycle with total weight above 0 is illegal. So k1, k2, k3 and k5 are E0324. `type Tree[T] { Node(v: T, kids: List[Tree[T]]) }` has weight 0 and is legal. `n` has no part in this.
  >
  > **Negative edges are essential.** Blink picks the impl per instance, so plain Go-style weights reject this program:
  >
  > ```blink
  > trait Size { fn size(self) -> Int }
  > impl Size for Int { fn size(self) -> Int { self } }
  > type Box[T] { v: T }
  > impl[T: Size] Size for Box[T] { fn size(self) -> Int { 1 + self.v.size() } }
  > fn total[T: Size](x: T) -> Int { x.size() }
  > fn main() { io.println("{total(Box { v: Box { v: 2 } })}") }   // prints 4 (measured); T to T is -1
  > ```
  >
  > The same edges catch a shape outside k1-k5, which hangs today (measured, exit 124 at 25 s):
  >
  > ```blink
  > trait Foo { fn foo(self, n: Int) -> Int }
  > type Box[T] { v: T }
  > fn f[T: Foo](x: T, n: Int) -> Int { x.foo(n) }
  > impl[U] Foo for Box[U] {
  >     fn foo(self, n: Int) -> Int { if n == 0 { 0 } else { f(Box { v: self }, n - 1) } }
  > }
  > ```
  >
  > T to U is -1, U to T is +2, total +1: E0324.
  >
  > **Soundness.** With no positive cycle, potentials exist that bound the depth of every argument. Constructors and arities are finite, so the instance set is finite and mono ends. The check builds no types.
  >
  > **Over-rejection, by design.** A projection on a cycle is rejected even if the type does not grow. No program reaches this today: `go(x.next(), n - 1)` through `T: Next` is an ICE (measured; a separate bug). A dispatch edge to an impl that no instance reaches also counts: generic bodies are judged at the declaration.
  >
  > **Self-calls (a fix I add).** Today `swap(b, a, n - 1)` inside `fn swap[A, B]` is TypeError, and so is `swap[B, A](...)`. The same recursion split into two fns compiles (measured). Moving a body into a helper must not change legality. All signatures are written, so a self-call at a fresh instance is decidable (Mycroft). `swap` becomes legal (weight 0, prints 0), and k4 becomes E0324 in place of TypeError.
  >
  > ## 2. Rule B, the budget
  >
  > These have no cycle (measured, `blink check`):
  >
  > | Program | Instances | Today |
  > |---|---|---|
  > | `c_i[T]` calls `c_i+1([x])`, `c_i+1((x, x))`; 12 levels | 8,192 | 1.2 s, 94 MB |
  > | same, 14 levels | 32,768 | 9.9 s, 388 MB |
  > | `t_i[T]` calls `t_i+1((x, x))`; 22 levels | 23 | 6.4 s, 461 MB |
  > | same, 26 levels | 27 | over 25 s |
  >
  > 27 instances exhaust the time. A depth limit or an instance count does not see this cost, because the cost is in the leaves.
  >
  > - **Measure:** instance weight = 16 + leaf count of its type arguments. The program total must not pass 2^20. A count gives the same result on each machine; memory or time does not.
  > - **Effect:** at most about 65,000 instances, or about 1M leaves. `c_i` passes at 12 levels and fails at 13. `t_i` passes at 18 and fails at 19. `blink check src/cli.bl` traces about a dozen instances, but the compiler uses few generics, so this value needs a check on generic-heavy code.
  > - **User control:** none. A setting makes legality local to one project, and a library does not carry it to its clients. If the value is wrong, change the spec.
  > - **A deep but small type:** legal. No depth limit exists, so a chain of 200 fns that each add one `List[...]` passes. Under a number like Rust's `recursion_limit`, acceptance depends on who calls it.
  >
  > Only Rule B can fail in a client for a library that passes alone. Each resource limit has this fault, so Rule A carries all infinite programs.
  >
  > ## 3. Memory
  >
  > k3 never reaches mono. Rule A runs after typecheck and builds no type, so I expect k3 to end in about the time of k4 (0.0 s; no build exists to measure). Mono adds the weight at registration, before it spells a C name or type text. Leaf counts are memoized on the interned tid and saturate, so `(T, T)` at level 40 costs one integer. Today `register_fn` spells the name first; that order must change. An edge that Rule A misses gives E0325, not a hang.
  >
  > ## 4. Diagnostics
  >
  > E0324 and E0325 are free. One code for k1, k2, k3, k4, k5 and dispatch, because it is one failure (the E0303 precedent).
  >
  > ```
  > error[UnboundedInstantiation]: `r[T]` needs `r[List[T]]`, so its instances have no end
  >   --> k1.bl:3:5
  >    |
  >  3 |     r[List[T]]([x], n - 1)
  >    |     ^^^^^^^^^^ `T` becomes `List[T]`
  >   note: Blink builds one copy of `r` per type argument. The value of `n` does not stop this
  >   help: keep `T` the same in this call, and hold the depth in a recursive type:
  >         type Nest[T] { One(v: T), Many(items: List[Nest[T]]) }
  >         fn r[T](x: Nest[T], n: Int) -> Int
  > ```
  >
  > - **Span:** the first growing edge of the cycle in source order, one error per cycle. A `note:` lists the other steps in declared spelling, never an expanded type. Over modules, the span is in the module that closes the cycle.
  > - **k2:** span on `P[(T, T)]`; names `P` and field `p`. Help: `Node(l: P[T], r: P[T])`.
  > - **Rule 1:** both repairs compile (measured). They are help only, because they change the shape of the data.
  > - **E0325 `InstanceBudgetExceeded`:** points at the heaviest declaration and names the top three. Help: "use one recursive type in place of the nested forms, so that fewer argument lists exist". A concrete type prints to a fixed size with `...`.
  >
  > ## 5. Timing
  >
  > - **E0324 fires at the declaration, with or without an instance.** `dead_type` and `dead_fn` (k2, k1 with no use) check as ok today and become errors. A library author sees the error first.
  > - **E0325 counts from roots** (`main`, tests), so a library with no roots gets none. It also rejects slow programs that finish today, such as 14 levels of `c_i`.
  > - **Both show in `blink check`, the LSP and the daemon**, because the pipeline runs mono (rule 2). E0324 needs a typecheck with no errors, so it adds no noise to a broken file.
  >
  > ## Other languages
  >
  > - **Haskell, OCaml** accept k2 (nested datatypes) through a uniform representation. Blink has no erasure, so that path is closed.
  > - **Go** `types2/mono.go` is Rule A without negative edges, because Go dispatches at run time. Kennedy and Pierce's expansive cycles are the same idea.
  > - **Rust** uses numbers and reports after expansion, with huge types in its messages.
  > - **Cost:** a new pass, and each new instance site must add an edge.

- **DevOps/Tooling:**
  > # devops seat: a cycle rule for the shape, a budget for the bill
  >
  > A check on declarations rejects each generic cycle that grows a type. A fixed budget, with no flag, stops finite programs that are too large. A limit alone gives the wrong message at the wrong site. A cycle check alone does not stop memory growth (table in 2).
  >
  > ## 1. What is legal
  >
  > k1, k2, k3, k5 are errors, whatever `n` holds. Make a graph of type parameters over fns, types, impls and methods. A use of a generic adds an edge from each parameter in an argument to the parameter it fills. The edge grows if the argument is more than the bare parameter. A cycle with a growing edge is an error.
  >
  > ```blink
  > fn c[T](_x: T, n: Int) -> Int {          // legal: 2 instances, measured
  >     if n == 0 { 0 } else { c[List[Int]]([1], n - 1) }   // no T in the argument: no edge
  > }
  > type Tree[A] { Leaf(v: A), Node(l: Tree[A], r: Tree[A]) }   // legal: edge does not grow
  > ```
  >
  > A shape the ticket does not name uses no brackets, and hangs today (exit 124 at 25 s). So the graph must include impls:
  >
  > ```blink
  > trait Grow { fn grow(self, n: Int) -> Int }
  > impl Grow for Int { fn grow(self, n: Int) -> Int { n } }
  > impl[T: Grow] Grow for List[T] {
  >     fn grow(self, n: Int) -> Int { if n == 0 { 0 } else { [self].grow(n - 1) } }
  > }
  > ```
  >
  > k4 keeps E0300. Its message must not offer brackets as a repair: that leads to E0324.
  >
  > ## 2. The limit
  >
  > These programs have no cycle and are finite (`blink check`, 3G cap):
  >
  > | Program | Shape | Instances | Result |
  > |---|---|---:|---|
  > | tup22 | 23 lines, `f{i+1}((x, x))` | 23 | 10.6 s, 703 MB |
  > | tup26 | same | stopped at f23 | exit 124, 1.58 GB |
  > | fan18 | `f{i+1}([x]) + f{i+1}(Some(x))` | 524,287 | 14.3 s, 2.3 GB |
  > | fan20 | same | stopped at f19 | killed at 3G cap |
  >
  > Instance count does not measure the cost: tup22 uses 703 MB for 23 instances. Depth does not either: fan18 has depth 18, and a chain of depth 100 needs 0.03 s.
  >
  > **Measure.** One budget per program. Each instance costs 1 plus the expanded node count of its type arguments. A named type with no arguments is one node.
  >
  > **Value.** 1,000,000 units. This stops fan near level 15 (about 300 MB, interpolated) and tup near level 18 (64 MB, 0.7 s). The check of `src/blinkc_main.bl` reports 8 instances, longest symbol 67 characters, so real code is far below it.
  >
  > **User control.** None. A flag makes legality differ between a laptop, CI and the LSP (the C++ `-ftemplate-depth` problem). The spec states the number, so each host gives the same verdict. If a real program reaches it, raise it in a release.
  >
  > **Small types.** A program under the budget compiles, however deep. A chain of 100 fns that each wrap once costs about 5,150 units and stays legal. A depth limit of 64 or 128 rejects that program, yet lets tup and fan run out of memory. k1 is an error even at `r(1, 0)`: the cycle rule does not read sizes.
  >
  > ## 3. Memory
  >
  > k3 never reaches mono: the cycle check runs after typecheck, so it makes 0 instances. The budget must add node counts on the interned types (saturating, memoized) BEFORE the compiler builds a C name or any text, because each C symbol holds the full expansion (the tup22 trace).
  >
  > Each instance costs at least 1, so a run has at most 1M instances. So an edge the graph misses gives a poor message, never a hang. `blink check`, the LSP and the daemon all get a bounded run.
  >
  > ## 4. Diagnostics
  >
  > **E0324 InstantiationCycle.** It prints types as the source spells them, in terms of the binders (`List[T]`, `(T, T)`). These are always short. It never prints a level-30 expansion.
  >
  > ```
  > error[InstantiationCycle]: `r` needs a new copy of itself for each bigger type, without end
  >   --> k1.bl:3:7
  >   |
  > 3 |     r[List[T]]([x], n - 1)
  >   |       ^^^^^^^ here `T` of `r` becomes `List[T]`
  >   note: the compiler makes one copy of `r` per type. It does not read `n`, so a stop at run
  >         time does not stop the copies
  >   help: give `r` one type that holds the nesting, and keep `T` the same in the call:
  >         `type Nest[T] { One(v: T), Many(kids: List[Nest[T]]) }`, then
  >         `fn r[T](x: Nest[T], n: Int)` calls `r(Nest.Many([x]), n - 1)`
  > ```
  >
  > The repair exists (rule 1): I ran it, and `r(Nest.One(1), 3)` with a `depth` fn prints `3`. It is `help:` only, not a machine-applicable fix, because it changes the program's types.
  >
  > | Shape | Span | Names | Repair |
  > |---|---|---|---|
  > | k1 | the type argument | fn, binder, argument | as above |
  > | k2 | the type in the field | "field `p` of `P.Node` uses `P[(T, T)]`" | `Node(l: P[T], r: P[T])` (ran: prints `node`); the perfect-tree rule moves to run time |
  > | k3 | first growing edge in source order | each fn in the cycle; a note per growing edge, 3 at most, then "and N more" | as k1 |
  > | k5 | the name `r` | the solved `T = List[T]` | as k1 |
  > | trait | the method call | impl, method, "`T` becomes `List[T]`" | as k1 |
  >
  > One diagnostic per cycle, so k3 gives 1 error, not 4. The JSON form holds the edge list (`decl`, `param`, `becomes`, `span`), and the LSP maps each edge to related information.
  >
  > **E0325 InstantiationBudget.** The span is the call in user code that made the instance that passed the budget. A type in the message prints to depth 3, then `...`.
  >
  > ```
  > error[InstantiationBudget]: this program needs more than 1,000,000 units of generic copies
  >   --> fan20.bl:15:5
  >   note: `f15` has 32768 copies; its type arguments reach depth 15
  >   help: name a type with no parameters in place of the nesting, or let the calls
  >         share one type argument, so that fewer copies are needed
  > ```
  >
  > A named non-generic type costs one node, so the repair exists.
  >
  > ## 5. When it fires
  >
  > | | Generic with no instance | `blink check` |
  > |---|---|---|
  > | E0324 | **fires**: k1 with no call, `P` with no use (both `ok` today) | yes, after typecheck, also with errors elsewhere; an edge with an error type is skipped |
  > | E0325 | cannot fire: no instance, no cost | yes, in mono, on a clean front end |
  >
  > Otherwise a library author ships `r`, and the first user gets the error in a module they do not own. Such a declaration has no legal instance, so nothing useful breaks. `if false { r[List[T]](...) }` is also rejected: mono does not read values.
  >
  > ## Tradeoffs
  >
  > - Two codes and one more pass, and the graph must cover each way to make an instance.
  > - E0325 depends on the whole program, so a leaf edit can trip it far away.
  > - The value is a judgment from this host's numbers.
  >
  > ## Cross-language
  >
  > From memory, not checked: Go reports "instantiation cycle" in its type checker (the model for E0324). Rust's limit fires after mono, and rustc writes long type names to a file; source-spelled text avoids that.
  >
  > ## Side finding
  >
  > `fn s[A, B](a: A, b: B, n: Int) -> Int { if n == 0 { 0 } else { s[B, A](b, a, n - 1) } }` gives `error[TypeError]: argument 2 of s expects B, got A`. The same swap on another fn (`t[B, A](b, a)`) compiles and runs. It looks like a capture bug in self-call substitution. Someone must file it.

- **AI/ML:**
  > # aiml seat: a limit on generic instances
  >
  > **Summary.** First, a rule with no number: reject a cycle of generic declarations whose type arguments grow. This catches k1, k2, k3 and k5 before the compiler makes one instance. Second, one fixed budget as a backstop, for what a declaration does not show. No knob.
  >
  > ## 1. Which programs are legal
  >
  > k1, k2, k3 and k5 are illegal, for any `n` and any call site. The **instantiation graph** decides:
  >
  > - A node is a binder of a generic fn, type or impl method.
  > - Each written or inferred type argument makes an edge: from a call, a fn named as a value, a field type, a constructor.
  > - The edge is *same* if the argument is exactly the binder, *growing* if the binder is inside a constructor (`List[T]`, `(T, T)`).
  > - A cycle with a growing edge is an error.
  >
  > Blink has no specialization, so such a cycle never stops at compile time. k4 stays E0300. An agent that "fixes" k4 with `r[List[T]]` gets E0324 next, and that repair ends the loop.
  >
  > **Bound dispatch makes no edge**, because `x.m()` on `x: T` has no known target at the declaration. This program is finite and must compile (I ran it):
  >
  > ```blink
  > trait M { fn m(self) -> Int }
  > impl M for Int { fn m(self) -> Int { self } }
  > type W[T] { v: T }
  > impl[U: M] M for List[U] { fn m(self) -> Int { g(W { v: self.get(0).unwrap() }) } }
  > impl[U: M] M for W[U] { fn m(self) -> Int { self.v.m() } }
  > fn g[T: M](x: T) -> Int { x.m() }
  > fn main() { io.println("{[[7]].m()}") }   // prints 7
  > ```
  >
  > A graph that followed dispatch would see `U` grow into `W[U]` in a cycle and reject it. So the static rule has no false positives, and it does not see everything. `[self].m(n - 1)` has a concrete receiver, resolved at the call (§3.6), so it is an edge. Growth through `g([self], n - 1)`, where `g` calls `x.m(n)`, is not (probe dg2). That needs the backstop.
  >
  > ## 2. The backstop
  >
  > **Measure:** the sum, over all instances in the program, of the type nodes in each instance's type arguments. `Int` is 1, `List[Int]` is 2, `(Int, Int)` is 3.
  >
  > **Value:** 2^20. Fixed in the spec, so the verdict is the same on every machine. No flag or annotation changes it.
  >
  > | Probe (gen1, `check`) | Shape | Today | Budget verdict |
  > |---|---|---|---|
  > | bin15 | no cycle, 2 calls per level, 15 levels | 65,535 instances, 1.2 s, 287 MB | 983k: compiles |
  > | chain20 | no cycle, `(x, x)`, 20 levels | 1.6 s, 125 MB | about 2^22: E0325 |
  > | chain24, chain40 | same | hang, 1.2 GB at 25 s | E0325 at about level 18 |
  > | dg2 | growth through a bound | hang, 4,269 instances in 20 s | E0325 at about 2,000 instances |
  > | src/cli.bl | real code | 12 instances reported (may leave out archived std) | far under |
  >
  > A program that passes only because its type is small: under the cycle rule this does not exist. `r(1, 3)` needs 3 levels at run time and is still rejected. Under the budget, a finite program compiles until it passes the budget. That cliff sits near 18 doubling levels, where only generated code goes.
  >
  > Rejected:
  > - **Depth limit alone:** k3 at depth 64 still has 2^64 instances.
  > - **Time or memory limit:** one program passes on one machine and fails on another. No agent can learn that from a spec.
  > - **A knob** (Rust `recursion_limit`, C++ `-ftemplate-depth`): the help becomes "raise the limit". Models try that first, and on a true cycle it never converges.
  >
  > ## 3. Memory
  >
  > k3 makes no instance: the cycle rule reads declarations, before mono, in time linear in the graph.
  >
  > The backstop stops memory only if a type's size never needs its full text. The compiler holds a saturating size on the interned type, so `(T, T)` at level 40 costs one add. The result to require: `check` memory does not depend on leaf count. bin15 costs about 4.2 KB per instance, so that shape stays in the hundreds of MB. I did not measure `build` per instance; the implementer must confirm it under the 3G cap.
  >
  > ## 4. Diagnostics
  >
  > Two codes, because the repairs differ and a fixer keys on the code. E0324 and E0325 are free; the writer sets the numbers. One error per cycle group, not per edge.
  >
  > ```
  > error[InstantiationCycle]: `r` instantiates itself with a larger type, so it has no finite set of instances
  >   --> k1.bl:3:5
  >   |
  > 3 |     r[List[T]]([x], n - 1)
  >   |     ^^^^^^^^^^ `T` grows to `List[T]` on each level
  >   note: the compiler builds one copy per type argument list, and it does not read run-time values such as `n`
  >   help: hold the nesting in a recursive type, so that `T` stays the same:
  >         type Nest[T] { Leaf(v: T), Wrap(items: List[Nest[T]]) }
  >         fn r[T](x: Nest[T], n: Int) -> Int { ... r(Nest.Wrap([x]), n - 1) ... }
  > ```
  >
  > That repair compiles and prints `0` (I ran it). It is a suggestion, not machine-applicable, because it changes the data shape.
  >
  > - **k2**, span on `P[(T, T)]`: names type `P` and field `Node.p`. Repair: `type P[T] { Leaf(v: T), Node(l: P[T], r: P[T]) }` (ran; prints `1`). The cost: the type no longer proves perfect balance. A repair exists, so rule 1 holds, but an invariant moves from type to code.
  > - **k3**, span on the first growing call, `other([x], n - 1)`: the note gives `grow[T] calls other[List[T]], other[U] calls grow[List[U]]` and lists the 3 other growing calls as line:col only.
  > - **k5**, span on the `r` value in `= r`: the note says that the expected type fixes `r`'s `T` to `List[T]`.
  > - **E0325 `InstanceBudgetExceeded`**, span on the call that passed the budget: names the budget, the declaration with most instances, and the last three chain links. Types print to depth 4 with `...` and the true depth. Repair: the same recursive type, or fewer nested layers. Never "raise the limit".
  >
  > **Token bound:** each message is at most about 20 lines of declared forms, never expanded types. Its cost follows cycle length, not type size. This matters most to an agent in a loop: C++ traces run to thousands of tokens, and Rust writes long types to a side file.
  >
  > ## 5. When it fires
  >
  > - **E0324 fires at the declaration, with or without an instance.** k1 with no call gives `ok` today and becomes an error. A generic verifies once, so the library author sees it, not a downstream user who cannot edit the source. No runnable code is lost.
  > - E0324 runs after typecheck on a front end with no errors, so it adds no noise to E0300. `blink check`, the LSP and the daemon report it (rule 2).
  > - E0325 fires only for what the program instantiates, in deterministic walk order: one error, then mono stops. `check` reports it, because `check` runs mono.
  >
  > ## Domain tradeoffs
  >
  > **Learnable from the spec:** one sentence ("a generic may not reach itself with a larger type argument") and one number nobody must memorize. Added decision points and token cost in ordinary code: zero.
  >
  > **Cost:** perfect trees and finger trees are out in v1. Models trained on Haskell will write them, and they get E0324 with a worked repair in one round trip.
  >
  > **Cross-language:** Go checks this at compile time and reports an "instantiation cycle". Rust and C++ use limits with knobs. Haskell and OCaml permit it because all `T` share one representation; Blink does not.

- **Minimalism:**
  > # Min seat
  >
  > **Proposal: one fixed number, one error code, no knob, no annotation, no static cycle check.**
  >
  > ## Why a limit and no cycle check
  >
  > "Just don't" fails here: k1, k2 and k3 stop `blink check` and the LSP. The rival to a limit is a Go-style check for growing cycles at the declaration. It cannot replace a limit:
  >
  > ```blink
  > // chain: 26 levels, no cycle, finite. Exit 124 at 25 s, 696 MB and growing
  > fn f0[T](x: T) -> Int { f1([x]) + f1((x, x)) }
  > // ... f1 to f25 have the same form ...
  > fn f26[T](_x: T) -> Int { 1 }
  > ```
  >
  > ```blink
  > // dbl: 40 levels, one instance per level, no cycle. Exit 124, 1.8 GB. dbl22 passes in 6.5 s at 532 MB
  > fn f0[T](x: T) -> Int { f1((x, x)) }
  > ```
  >
  > A limit also catches every cycle, so the limit replaces the cycle check and the reverse is false. A cycle check adds a second mechanism for one hazard, and it must model every way to name an instance: calls, k5's value reference, and impl dispatch. I found a shape not in the brief, and it hangs too (exit 124):
  >
  > ```blink
  > trait Foo { fn foo(self) -> Int }
  > impl Foo for Int { fn foo(self) -> Int { 1 } }
  > impl[U: Foo] Foo for List[U] { fn foo(self) -> Int { [self].foo() } }
  > fn main() { io.println("{[1].foo()}") }
  > ```
  >
  > Subtract the cycle check. Add it later only if the limit proves too late for library authors.
  >
  > ## 1. What is legal
  >
  > A program is legal if the instances it needs have a total weight at or under the limit. The value of `n` plays no part.
  >
  > | Program | Result |
  > |---|---|
  > | k1, k2, k3, k5 with a `main` that calls it, the trait shape above | E0324 |
  > | k1, k5 and a non-regular type with nothing that instantiates them | compile (no instance, no cost) |
  > | fixed-depth `g[T]` calls `h[List[T]]` calls `i[List[T]]` | compiles, prints 1 (runs today) |
  >
  > Correction to the brief: k5 as written has no `main`, and it gives `ok` in 0.03 s. It hangs only when something calls `r`. The same holds for k1 with no `main`.
  >
  > ## 2. The limit
  >
  > **Measure: total weight.** Each distinct instance of a generic fn, method or type weighs 1 + the size of its type arguments. Size is the node count of the type written out in full: `Int` is 1, `List[Int]` is 2, `(Int, Int)` is 3.
  >
  > **Value: 65,536.** Fixed in the spec, the same on each machine and for each tool. Measured use today:
  >
  > - The compiler has 12 instances.
  > - Of 2,879 corpus and stdlib files, the most instances in one file is 52.
  >
  > That leaves a margin of about 1000 to the limit, even with a large weight per instance.
  >
  > **No knob.** A flag or annotation makes legality depend on the build and invites copied settings (C++ `-ftemplate-depth`, Rust `#![recursion_limit]`). If a real program ever nears the limit, a release raises the constant. Raising it breaks no program.
  >
  > **Why one number and not two.** Depth alone fails on chain (depth 26, 2^26 instances). Count alone fails on dbl (40 instances, 2^40 leaves). Weight covers both. Levels reached before E0324:
  >
  > | Program | Levels | Size at stop |
  > |---|---|---|
  > | k1 | 360 | 361 |
  > | k2, dbl | 15 | 65,535 |
  > | k3 (breadth first) | 9, 511 instances | |
  >
  > **Small types.** A finite program under the limit is legal, with no warning, because it costs little. An unbounded program cannot pass because its type stays small: each new instance adds at least 1. The answer depends only on the set of instances. Walk order only picks the chain the message shows, and that order is deterministic.
  >
  > ## 3. How this stops memory
  >
  > - The compiler stores size on each interned type, computed from the children and saturated at the limit. This takes constant time.
  > - It adds the weight before it builds an instance, and the first crossing ends mono. So k2 never holds or walks 2^30 leaves. k3 stops at 511 instances.
  > - Worst case is a wide program at about weight 65,536. Measured: chain12 has 8,191 instances, 102 MB, 1.5 s. By linear scale, the limit costs about 800 MB and 12 s. I did not measure this at the limit, and a very large generic body costs more per instance. A growing cycle with one call stops at about 360 instances. A branching cycle stops at a few thousand at most.
  >
  > ## 4. The diagnostic
  >
  > One code for all shapes: **E0324 InstanceLimit** (next free in E03xx). It is one error, then stop.
  >
  > - **Span:** walk back from the crossing instance to the nearest site where a declaration repeats. For a type, this is the field type. For k5, the value name. With no repeat (chain), the crossing site.
  > - **Names:** the declaration, the first instances in the chain, and a count of the rest. Print types with nesting past depth 4 as `...`. Never print a type in full.
  > - **Repair (rule 1):** hold the growth in a recursive type. I checked that both repairs below compile and run. For a wide chain with no repeat, the repair is to call with fewer distinct types.
  >
  > ```
  > error[InstanceLimit]: generic instances exceed the limit of 65536
  >   --> k1.bl:3:5
  >   |
  > 3 |     r[List[T]]([x], n - 1)
  >   |     ^ each call needs `r` at a larger type
  >   chain: main -> r[Int] -> r[List[Int]] -> r[List[List[Int]]] -> ... (357 more)
  >   note: the compiler builds every instance before the program runs, so `n` does not end this
  >   help: keep the same type arguments in the recursive call, and put the growth in a recursive type
  > ```
  >
  > Repair for k1 (prints 0):
  >
  > ```blink
  > type Nest[T] { One(v: T), Many(kids: List[Nest[T]]) }
  > fn r[T](x: Nest[T], n: Int) -> Int {
  >     if n == 0 { return 0 }
  >     r(Nest.Many([x]), n - 1)
  > }
  > fn main() { io.println("{r(Nest.One(1), 3)}") }
  > ```
  >
  > k2 reports at 1:32 on `P[(T, T)]`, and names `P` and the field `Node.p`: "`P[Int]` needs `P[(Int, Int)]` through `Node.p`, without end". Its repair gives up the perfect-tree guarantee in the type:
  >
  > ```blink
  > type P[T] { Leaf(v: T), Node(l: P[T], r: P[T]) }
  > ```
  >
  > ## 5. When it fires
  >
  > It fires only on instances the program reaches. It fires in mono, so `blink check`, the LSP, the daemon and `blink build` all report the same error, which meets rule 2. A generic body or a non-regular type that nothing instantiates does not fire, and `check` gives `ok`, as today.
  >
  > ## Tradeoffs I accept
  >
  > - A library author can ship k1 and not learn until a test calls it. In practice a test does. An unused non-regular type does no harm.
  > - The limit adds across a whole program, so a new dependency could push it over. With this margin that is theory.
  >
  > I do not propose a boxed form to make k2 legal: a second code path for a shape I have not seen in real use.
  >
  > ## Cross-language
  >
  > - Go rejects growing cycles statically, with no number. That check would not catch chain or dbl, which have no cycle.
  > - Rust and C++ have a depth limit and a knob. I want the limit and not the knob.
  > - OCaml and Haskell permit k2 because they use a uniform representation, which Blink does not.


#### Phase B — Debate (round 1)

- **Systems:**
  > # sys, Phase B round 1
  >
  > **Q1: A.** The limit stops every reached bomb, but only the check tells a library author. Min's chain and dbl prove a limit is needed; they do not prove the check is useless.
  >
  > **Q2: B (changed from A).** web, aiml and devops are right. In `[self].g(n - 1)` the receiver type fixes the impl, and mono does not prune, so that edge cannot give a false error. I had put this concrete case in with bound dispatch.
  >
  > Against C, I object. This program is finite and prints `7` today (probe plt_fp):
  >
  > ```blink
  > trait Foo { fn foo(self) -> Int }
  > type Box[T] { v: T }
  > type Wrap[T] { v: T }
  > fn f[T: Foo](x: T) -> Int { x.foo() }
  > impl[U] Foo for Box[U] { fn foo(self) -> Int { f(Wrap { v: self }) } }
  > impl[U] Foo for Wrap[U] { fn foo(self) -> Int { 7 } }
  > fn main() { io.println("{f(Box { v: 1 })}") }
  > ```
  >
  > By plt's table, T to U is -1 and U to T is +2, total +1, so it is E0324. The graph does not know that `Wrap`'s impl ends the chain. A check on declarations must never reject a finite program. Bound dispatch goes to the limit.
  >
  > **Q3: E/D form (changed from A).** One budget: each instance weighs 1 + the nodes in its type arguments; the total is 2^20. My two limits allowed 65536 x 256 nodes. A sum bounds total type text directly, with one number. A real large program can have many instances, so I reject 2^16 (F): no knob and a whole-program sum need margin.
  >
  > Against C: leaves do not count `List` nesting. At weight 17 per level, a `List` chain reaches about 61,000 levels. Measured, a finite chain of 360 levels takes 0.08 s and 1448 levels takes 1.6 s, about n^2. So 61,000 levels would take most of an hour (extrapolated). With nodes, that chain stops near level 1448, and no crash occurs there.
  >
  > Worst case by this budget: 2^19 flat instances. Measured: 90,000 flat instances, 206 MB, 0.48 s, so about 1.2 GB (extrapolated). A large generic body costs more per instance, and no proposal counts that.
  >
  > **Q4: A.** k4 keeps E0300, and its help must not offer brackets. `sw[B, A](b, a, n - 1)` giving TypeError is a separate bug, to be fixed whatever Q4 decides.
  >
  > **Q5: A.** Typecheck recovery can leave wrong types, and a false E0324 on a broken file breaks rule 3. Mono also does not run on a broken file.
  >
  > **Q6: B (changed from A), web's form.** The crossing call, with a note at the root in user code. In a growing chain, the crossing call sits in the code that grows. The root alone shows no growth. Walk order must be fixed; the verdict does not depend on it.
  >
  > **P7:** no objection.
  >
  > Stable, ready to vote.

- **Web/Scripting:**
  >  B1, web seat.
  >
  > **Q1: A.** Min's limit-only form tells a library author nothing until a client trips it, and the message says "limit" for a fault that has a cause.
  >
  > **Q2: B.** "The compiler follows what you wrote, and a call on a bound goes to the limit" takes one sentence. plt's weights are sound and catch more, but only k6-shaped programs gain, and they still get an error from the limit.
  >
  > **Q3: A (sys), a change from my 1,024.** My Phase A worst case was the product of the limits: 67M nodes. At 256, it is 16.7M. Real code reaches 4 bracket levels, so 1,024 buys nothing. Against one budget (C to F): "this type has 511 parts, limit 256" and "65,536 copies" are things a dev can picture. "1,000,000 units" is not, and each limit has its own repair. Both limits share one code.
  >
  > **Q4: B (plt), a change from Phase A.** I grepped `sections/`: no text makes a self-call monomorphic. §3.4 says inference solves a binder from the call's arguments, with no self-call exception. sys's `a`/`b` pair and devops's `t[B, A]` compile, so k4's TypeError rests on no rule. B also removes a loop: k4 says "expects T, got List[T]", the user adds brackets, then gets E0324. Under B they get E0324 first. `swap(b, a, n - 1)` compiles.
  >
  > The `sw[B, A](b, a, n - 1)` TypeError is a separate bug fix whatever Q4 decides: §3.4 makes the list legal, and the arguments match it.
  >
  > **Q5: B (devops).** A skipped edge only removes edges, so a reported cycle is true whatever else is broken. Errors arrive in one pass, for a human in an LSP and for an agent in a loop. Under A, a user clears every error and then gets a new one.
  >
  > **Q6: B, with my note at the root.** The crossing call in k6 is the growth site, `h(Box { v: self }, n - 1)`. The root note gives the user a line in their own code when that site is in a library. Min's D may point better, but it adds a walk rule for a rare error.
  >
  > **P7:** no objection.
  >
  > **New evidence, E0325 repairs (closes my writer note).** Both ran:
  > - k7 with `type Tree[T] { Leaf(v: T), Pair(l: Tree[T], r: Tree[T]) }`, and `f1..f24` taking `Tree[T]`: prints 8388608 in 0.19 s, 44 MB, against 14.7 s and 1.07 GB. No named non-generic type can stand in a generic body, so the help is "a recursive type", not my Phase A wording.
  > - k6 with `type Nest[T] { One(v: T), Wrap(inner: Nest[T]) }`: prints 0.
  >
  > Stable, ready to vote.

- **PLT:**
  > plt seat B1. I withdraw two of my Phase A positions (Q2, Q3 measure), and one on Q6.
  >
  > **Q1: A.** A rule that rejects only true infinities, plus a budget for the rest. The limit alone cannot give a library author the error, and it blames a number for a fault of shape.
  >
  > **Q2: B (changed from C).** My negative edges reject a finite program. I ran this; it prints 7, with about 5 instances:
  > ```blink
  > trait M { fn m(self) -> Int }
  > impl M for Int { fn m(self) -> Int { self } }
  > type W[T] { v: T }
  > impl[U: M] M for List[U] {
  >     fn m(self) -> Int { if self.len() > 1 { g(W { v: [self.get(0).unwrap()] }) } else { self.get(0).unwrap().m() } }
  > }
  > impl[U: M] M for W[U] { fn m(self) -> Int { self.v.m() } }
  > fn g[T: M](x: T) -> Int { x.m() }
  > fn main() { io.println("{[7, 8].m()}") }
  > ```
  > Under C, U to T is +2 and T to the `List` impl's U is -1, total +1: E0324. That path does not exist, because here T is always `W[...]`. To tell the two apart, the check must follow the instances, and that is mono. aiml's program does not show this (total 0), but its conclusion holds.
  >
  > Rule: an edge only where the site always makes that instance. Weights are 0 or +1 only. So a growing cycle is infinite whenever it is reached, and E0324 has no false positive. Excluded: a call on a bound, a projection, and a method that a type instance gets only where a bound holds. All of these go to the budget, which guarantees that mono ends. My finiteness argument for C is gone, and I do not need it.
  >
  > **Q3: D (changed from C).** My leaf count is wrong. `List[List[...]]` has one leaf at any depth, so growth through a bound would reach about 65,000 levels, with text quadratic in depth. Node count charges this. One budget, not two: sys's 256 rejects a small 8-level tuple for no reason. Value about 2^20; 1,000,000 is fine.
  >
  > **Q4: B (held).** §3.4 says "a redundant list is never required". `r[List[T]](...)` type-checks, so deleting its list must too. Splitting a fn into two must not change legality (measured). k4 then gets E0324. `sw[B, A](b, a, n - 1)` is a separate bug fix, whatever Q4 decides: the substitution must apply at once.
  >
  > **Q5: A (held).** The edges read recorded type arguments. A clean front end is the same precondition as E0325.
  >
  > **Q6: D (changed from C).** The spec reports where the repair attaches (E0301). The nearest repeat is that place. My "heaviest declaration" is not.
  >
  > **P7:** no objection.
  >
  > Stable, ready to vote.

- **DevOps/Tooling:**
  > devops B1.
  >
  > Q1: A. E0324 at the declaration gives the library author the error, in source spelling, with no number.
  >
  > Q2: B. A call whose impl the receiver type fixes is an edge, with the exact substitution, so a reported cycle is a true one. A call on a bound goes to the limit. C reports on an impl that no instance reaches, so a new impl in another module can make an error appear in a fn the author did not edit. I cannot word a repair for "T to U is -1".
  >
  > Q3: D, and E is equal in practice. Count nodes and do not add a per-instance constant. New probe: `wide400x300`, 1,104 lines, 400 named types through 300 generic fns, 120,000 instances, size 1 each: 0.70 s, 249 MB today. D passes it (240,000 units). A, B, C and F reject it (C at 16+1 per instance, about 2M), though it costs less than bin15. Worst case under D is 500,000 such instances, about 1 GB by extrapolation (not measured), and it needs generated source. Reject C's leaf count: `List[List[...]]` has 1 leaf at any depth, so it does not see the symbol text.
  >
  > Q4: A, and the sw[B, A] TypeError is a separate bug fix whatever Q4 decides. New objection to B, measured:
  >
  > ```blink
  > fn r[T](xs: List[T], n: Int) -> Int {
  >     if n == 0 { return xs.len() }
  >     r([], n - 1)
  > }
  > fn main() { io.println("{r([1], 2)}") }   // compiles today, prints 0
  > ```
  >
  > The same call to a helper, `h([], n - 1)`, is E0301 today. `q(None, n - 1)` inside `q[T]` behaves as `r` does. So if a self-call gets fresh binders, these legal programs break unless B adds a rule to fall back to the fn's own binders. B must state that rule, or state the break.
  >
  > Q5: B, low stakes. An agent or LSP user gets E0324 one round earlier. Escape analysis already reports next to front-end errors. Condition: skip each edge from a call that has an error, so k4 stays one E0300 with no second error on the line. I accept A if the vote goes that way.
  >
  > Q6: B. The crossing call, with a note at the root in user code. On a cycle through a bound, the crossing call is already on the repeating path.
  >
  > P7: no objection. Depth 3.
  >
  > Change from Phase A: my "trait" row is now only a call with a fixed impl. I also ran the E0325 repair that web flagged as untested, for the tup shape: 26 levels with a named type per level (`type N1 { a: N0, b: N0 }`) gives `ok`, 27 instances, 0.03 s, 15 MB. tup26 with tuples times out at 25 s. Not run for fan or k6.
  >
  > Stable, ready to vote.

- **AI/ML:**
  > aiml B1. New probes are in probe/aiml/.
  >
  > **Q1: A.** Cycle check plus a limit. A limit alone reports k1 as "over 65536" where one sentence states the real fault.
  >
  > **Q2: B.** A call whose impl the type fixes is an edge. A call on a bound is not. Against C, this finite program prints 7 today (w2.bl):
  >
  > ```blink
  > trait M { fn m(self) -> Int }
  > impl M for Int { fn m(self) -> Int { self } }
  > type W[T] { v: T }
  > impl[U: M] M for List[U] { fn m(self) -> Int { g(W { v: W { v: self.get(0).unwrap() } }) } }
  > impl[U: M] M for W[U] { fn m(self) -> Int { self.v.m() } }
  > fn g[T: M](x: T) -> Int { x.m() }
  > fn main() { io.println("{[[7]].m()}") }
  > ```
  >
  > Under C: `U` of the List impl to `T` is +2, and `T` back to that `U` is -1, total +1, so E0324. That dispatch never happens, because `T` has head `W`. So C rejects a working program and tells the author to rewrite correct code. B gives the shape C catches a weaker message (limit code). I accept that.
  >
  > **Q3: changed from E.** One budget. Instance weight = 16 + type nodes of its arguments; total 2^20.
  > - **Floor (from plt):** my E had none. flat250k (500 fns, 500 types, each argument size 1) gives 250,500 instances, 1.6 s, 520 MB, so about 2.1 KB each with one-line bodies. That shape reaches 1M instances under E at about 2 GB. The floor caps instances near 61,000.
  > - **Nodes, not leaves:** `List[List[...]]` has one leaf at any depth, so under plt's measure dg2 runs about 61,000 instances. It took 20 s to reach 4,269 under trace. Nodes stop it near 2,000.
  > - **Effect:** bin14 passes (983k) and bin15 fails. A `(x, x)` chain stops near level 18.
  > - **Two limits (A, B):** a second number, and no gain.
  >
  > **Q4: changed to B.** Phase A I read k4's E0300 as a rule. It looks like a bug. p0.bl, `fn p[T](n: Int) -> Int { ... p(n - 1) }`, gives CannotInferType with help `p[T](...)`, so a self-call already has its own binders there. No text in `sections/` limits self-calls (rg). k3's inferred mutual calls typecheck. I infer that k4 and `sw[B, A]` are one capture bug; I did not read the code. Fix it, whatever the vote, and k4 then gets the cycle code. A special self-call rule is one more thing to learn, and it costs an agent an extra round trip through brackets.
  >
  > **Q5: A.** A false E0324 sends an agent to rewrite its data types. A late one costs one more `check`.
  >
  > **Q6: B, with web's note** at the root in user code. Add the declaration with most instances.
  >
  > **P7:** no objection. I accept depth 3.
  >
  > Stable, ready to vote.

- **Minimalism:**
  > # Min seat, B1
  >
  > **Q1: B. I hold.** Every seat now agrees the limit must ship: sys says "if the panel wants one, keep the limits". So the vote is whether to add a second mechanism on top. The check buys one thing the limit does not: an error on a generic nothing uses. A dead bomb harms nobody, and the first test that calls it reports it. The better message is not a gain, because a limit error that names the repeating call says nearly the same thing. The cost is permanent: a new pass, and each new instance site must add an edge. A missed edge just gives the limit error in place of the cycle error, so nothing flags it unless a test names that site. The library-author point is real. It is the one argument that could move me, and I do not find it enough.
  >
  > **Q2, if Q1 is A: B, not C.** A method call whose impl the type fixes is just a call. Bound calls make no edge. I oppose C: negative weights, infinite edges and a stated over-rejection are too much theory for a case the limit already ends.
  >
  > **Q3: E, and I change my value.** Sum of type nodes per instance, total 2^20, one number. E and D differ by a term nobody can see, so I take the shorter. I oppose two limits (A, B) and plt's extra constant 16.
  >
  > Why I drop 65,536: my "margin of about 1000" was wrong. I measured test files and a compiler that uses few generics. A large generic-heavy app could reach 20,000 instances at weight 5, which is 100,000. With no knob, a false rejection blocks that user until a release. At 2^20 the worst cases are bearable: fan near level 15 at about 300 MB, and bin15 at 287 MB, compiles. Tup stops at about level 18.
  >
  > **Q4: A.** k4 keeps E0300, and its help never offers brackets. `sw[B, A](b, a, n - 1)` giving TypeError is a separate bug: explicit arguments must substitute at once, whatever this ticket decides. plt's inference change for `swap(b, a, n - 1)` is a new feature with its own cost, and nobody needs it here.
  >
  > **Q5, if Q1 is A: A.** Clean front end only. Skipping error-typed edges is extra code for little gain.
  >
  > **Q6: D.** The chain's parent links are needed for the note anyway, so finding the repeat costs little. It points at the line to change. A is wrong for a bomb inside a library, since the user's call has no repair. C needs a table per declaration. If Q1 is A, D still serves dispatch growth.
  >
  > **P7: no objection.** Depth 3 or 4 does not matter to me.
  >
  > **Changes from Phase A:** the budget, 65,536 to 2^20. E0324 as the sole code stands if Q1 is B.
  >
  > Stable, ready to vote.


#### Phase C — Silent ballot

The ballot had Q1 (a check on declarations, or only a limit), Q3 (what the limit measures), Q4 (a self-call at other type arguments), Q5 (the order of E0324 and E0325 against other errors) and Q6 (where E0325 points). Q2 was settled in round 1. The votes were:

| Q | Sys | Web | PLT | DevOps | AI/ML | Min | Result |
|---|---|---|---|---|---|---|---|
| Q1 | A | A | A | A | A | B | A, 5-1 |
| Q3 | D | D | D | D | D | D | D, 6-0 |
| Q4 | A | B | B | A | B | A | 3-3 |
| Q5 | A | A | A | B | A | A | A, 5-1 |
| Q6 | B | B | D | D | B | D | 3-3 |

- **Systems:**
  > Q1: A
  > Q3: D
  > Q4: A
  > Q5: A
  > Q6: B
  >
  > Reasoning:
  > Q1: The limit is needed for finite bombs and for bound dispatch, so it ships either way. The check adds an error at the declaration in time linear in the edges, with no instance and no number. So k3 costs nothing, and a library author sees the fault in their own `blink check`.
  > Q3: D tracks what the compiler pays. An instance has a fixed cost (2.3 KB per flat instance, measured: 90,000 at 206 MB) and a cost per type node, and tup22 shows the node cost is real (23 instances, 461 to 703 MB). One number bounds both, so the worst case is 2^19 flat instances, about 1.2 GB by extrapolation. E has no fixed cost, so that worst case doubles to about 2 GB. G caps a program near 61,000 instances, which is too near a large real program for a whole-program sum with no knob. A rejects wide400x300, a 0.70 s, 249 MB program that costs little.
  > Q4: k4 is not needed to stop a bomb, because k1 already reaches E0324 through brackets. B changes inference at self-calls and must answer `r([], n - 1)`, which compiles today only because `T` stays fixed. That is a separate type-system change with no effect on instance cost, so it does not belong in this ticket.
  > Q5: Typecheck recovery can leave wrong types, so an edge in a broken file is not evidence of growth. Mono does not run on a broken file either, so both errors have one simple gate. The user waits one fix cycle and loses nothing, and a false E0324 would break rule 3.
  > Q6: The crossing call is already known when the budget trips, so it needs no more bookkeeping. In a growing chain, that call sits in the code that grows, so the walk back in D mostly finds the same site. The root note gives the user an edit point when the crossing call is inside a library.
  >
  > Concern:
  > Q1: Each new way to name an instance needs an edge, and a missed edge gives the weaker limit error, not a hang.
  > Q3: A very large generic body costs more per instance and D does not count it, so 1.2 GB is not a hard top.
  > Q4: The self-call and the helper call stay different (k4 fails, and the same call to a helper compiles), so users will still ask why.
  > Q5: An LSP user with one unrelated error sees no cycle error until that error clears.
  > Q6: The crossing call depends on walk order, so a small edit can move the span, and walk order must be fixed in the compiler.
  >
  > Objections: none. The number is 2^20.

- **Web/Scripting:**
  > Q1: A
  > Q3: D
  > Q4: B
  > Q5: A
  > Q6: B
  >
  > Reasoning:
  > - Q1: The error should state the cause ("`T` becomes `List[T]`"), not a number, and it should reach the library author who can repair it. A limit alone tells that author nothing until a client trips it.
  > - Q3: Changed from A. With no knob, a false rejection is the worst outcome for a user, and A rejects devops's wide400x300 (0.70 s, 249 MB), which costs less than bin15. An 8-level tuple also fails for no good reason. My case for A was that a dev can picture the message; the message need not say "units", so it can name the declaration with the most copies. D over E because the +1 caps instances and has a floor; G's 16 rejects wide400x300 again.
  > - Q4: Under A, once the `sw[B, A]` bug is fixed, `swap[B, A](b, a, n - 1)` compiles and `swap(b, a, n - 1)` does not. That makes a list required, and §3.4 says a redundant list never is (sections/03_types.md:3385 cites this). A also needs a new self-call rule; `sections/` has none today. I state the break for devops's case: no fallback rule. `r([], n - 1)` inside `r[T]` becomes E0301, as `h([], n - 1)` to a helper is today and as `p(n - 1)` inside `p[T]` already is (measured). The help is the existing one, and `r[T]([], n - 1)` compiles and prints 0 (measured). A scan of the 706 generic fn headers in src, lib, tests and examples for self-calls with `[]`, `None` or an empty collection found 9 text hits, all in tests. None looks like a real self-call, though the scan is a text search and does not prove it. A fallback rule is the kind of self-call special case that B removes.
  > - Q5: Changed from B. sys and aiml are right about cost: a false E0324 sends a person or an agent off to rewrite data types, and a late one costs one more `check`. My case was that skipping edges only removes edges, but that holds only for types marked as errors, not for a wrong type that recovery leaves behind. E0325 needs a clean front end too, so one precondition covers both.
  > - Q6: In a growing chain the crossing call sits in the code that grows, and the note at the root gives a line in the user's own code. D may point a little better, but it adds a walk rule for an error most users never see.
  >
  > Concern:
  > - Q1: Each new way to make an instance must add an edge, and a missed edge gives only the weaker limit error, so nothing flags the gap unless a test names that site.
  > - Q3: The 2^20 budget adds across the whole program, so a leaf edit can trip it far away, and the 1 GB or so worst case is extrapolated and leaves out large generic bodies.
  > - Q4: The change goes beyond what the ticket asks and turns some legal programs into errors, so it needs a corpus run and a rollout entry (§8.16.1), not only my text scan.
  > - Q5: A user clears every error and then meets a new one, and the cycle may be in a file they did not expect.
  > - Q6: Which call crosses depends on walk order, so the walk must be fixed in the spec or in a test, or the span will change between releases.
  >
  > Objections: none. The 2^20 budget number is fine. It is a judgment from measurements of test files and a compiler that uses few generics, so a release may need to raise it.

- **PLT:**
  > Q1: A
  > Q3: D
  > Q4: B
  > Q5: A
  > Q6: D
  > Reasoning:
  > Q1. An unused k1 or k2 has no legal instance, and this is a fact about the declaration, so the declaration must report it. With edges that always fire, E0324 has no false positive, and the budget keeps mono finite for what the graph does not see. Only the limit decides mono's end, but only the rule says what the fault is. A limit alone makes the verdict on a library depend on who calls it.
  > Q3. One budget gives one rule, and it is a function of the instance set alone. Node count charges both depth and doubling. The floor of 1 charges each instance when the type is small, which E does not do as well: E allows about 1M instances (about 2 GB by aiml's estimate), and D about half that. G fails wide400x300, a finite and cheap program (0.70 s, 249 MB), and A fails it too and also needs two numbers.
  > Q4. Every generic signature is written, so a self-call at a fresh instance is decidable (Mycroft), and it is the same judgment as a call to any other generic. §3.4 says "a redundant list is never required", yet `r[List[T]]` type-checks and `r([x], ...)` does not. Moving a body into a helper must not change legality. I state the break for devops's case, and I add no fallback: `r([], n - 1)` becomes E0301, as `h([], n - 1)` is today, and `q(None, n - 1)` too. A fallback to the fn's own binders keeps the helper difference that this vote removes. The repair exists and I ran it: `r[T]([], n - 1)` compiles and prints 0. Rust gives the same result for this shape, from memory, not checked.
  > Q5. The edges read the type arguments that typecheck recorded. On a broken front end those are partial, and a rule that must have no false positive should not run on them. It is the same precondition as E0325, so the two codes have one rule. The cost is one more round for a user, which is low.
  > Q6. The spec reports a diagnostic where its repair attaches (E0301, §3.4), and the nearest repeat is the site to edit. The crossing call depends on walk order, and in a chain it is one more step of the same growth with no special meaning. The walk needs only a parent index per instance, and the crossing site remains the fallback when nothing repeats.
  > Concern:
  > Q1. Each new way to make an instance must add an edge; a missed edge degrades to the budget's weaker message, not to a hang.
  > Q3. 2^20 is a judgment from this host's numbers, and at about 500,000 instances the memory may reach about 1 GB, more with large bodies.
  > Q4. The break may hit more legal programs than the two shapes known, so run the corpus before the writer fixes the text; also, the implementer must get the fresh-instance change in without a change to any legal call at the same `T`.
  > Q5. An agent in a loop sees E0324 one round later than it could.
  > Q6. A repeat is not always the fault: in a wide finite program the nearest repeat can be a harmless site, so the text must say which declaration repeated and how many times.
  > Objections: none

- **DevOps/Tooling:**
  > Q1: A
  > Q3: D
  > Q4: A
  > Q5: B
  > Q6: D
  >
  > Reasoning:
  > Q1: The cycle error names the fault in the source spelling, at the declaration, with no number and no list of instances. Under B, a library author who ships k1 gets `ok`, and a user in another package gets the error in a module they cannot edit. Rule 2 also favors A: `blink check` on a library with no `main` must see the fault.
  >
  > Q3: One number gives one message and one repair, and D tracks what the compiler spends: nodes for the text, and a per-instance unit for the table. wide400x300 is cheap (0.70 s, 249 MB), and rejecting it gives an error about a program with no problem, so A and G fall out for me. D caps instances near 524,000, about 1 GB at the 2 KB per instance that flat250k measures (extrapolated); E has no such margin (aiml: about 2 GB at 1M instances). Two limits (A) give two messages and two repairs for one cause.
  >
  > Q4: `r([], n - 1)` compiles today and prints 0, and B breaks it or needs a fallback rule that exists only for self-calls. A rule that a user must learn only to explain why a self-call differs from a helper is a poor diagnostic surface. E0300 on k4 is accurate, and a help with no brackets avoids the walk into E0324. The swap fix is settled apart from this.
  >
  > Q5: The check reads recorded type arguments, so it can give its answer in a file with an unrelated error, and an LSP user or agent then sees both errors in one round. Escape analysis already reports next to front-end errors. Skipping each edge from a call with an error keeps k4 at one E0300, and it only removes edges, so a reported cycle is still a true one. Low stakes for me.
  >
  > Q6: I change from B to D. The repair (a recursive type) goes at the site that repeats, and under B the crossing can land on a helper call that branches off the cycle, so the span points at code with no fault. The chain to the root is needed for the note in any case, so the walk back costs little. I ask that D keep the note at the root in user code (writer: the library user may not own the span).
  >
  > Concern:
  > Q1: A graph that misses a way to make an instance gives the weaker limit error on a true cycle, so each new instance site must add an edge.
  > Q3: An instance with a very large generic body costs more than the node count shows, so the 1 GB estimate is not a measured worst case and needs a test under the 3G cap at the limit.
  > Q4: k4's message stays "expects T, got List[T]", which does not say why a helper would pass, so a user can still add a helper and reach E0324 by that path.
  > Q5: A call with a wrong recorded type and no error of its own, after recovery from an error elsewhere, could make a false cycle, so the implementer must test this against broken files; if a false cycle occurs, A is the correct fallback.
  > Q6: A nearest repeat can be a declaration that repeats by chance with no growth (a shared helper used at two types), so the walk must pick a repeat where the type argument grew, and the writer must state that.
  >
  > Objections: none. 2^20 is fine; the message prints 1,048,576.

- **AI/ML:**
  > Q1: A
  > Q3: D
  > Q4: B
  > Q5: A
  > Q6: B
  >
  > Reasoning:
  > - Q1: The cycle error names the fault in one sentence, with no number, and a spec reader can predict it. A limit error at instance 65,000 or later teaches "a limit", and an agent then looks for a way to raise it. The library author sees the fault in the first `blink check`, not a client in a module the client cannot edit.
  > - Q3: I drop my G and vote D. devops's wide400x300 is 120,000 instances at 249 MB and 0.70 s, cheaper than bin15, and G rejects it. With no knob, a false rejection blocks a user until a release, and that costs more than memory. My reason for the floor was 1M flat instances at about 2 GB; D already halves that to about 1.1 GB (extrapolated), and only generated source gets there. One number with a short formula stays easy to learn, and +1 over E gives a real floor per instance.
  > - Q4: B, and I state the break. I add no fallback to the fn's own binders. devops's `r([], n - 1)` inside `r[T]` compiles today and becomes E0301, with help `r[T]([], n - 1)`. I ran that repair; it prints 0. A fallback would be a default, and §3.4 says a binder is "never defaulted"; the helper form `h([], n - 1)` and my p0 are already E0301 with that same help. An agent then learns one rule for each call, with no self-call exception, and k4 gets E0324 in one round trip, not two.
  > - Q5: A false E0324 sends an agent to rewrite its data types, which is the costliest wrong step on this ballot. A late E0324 costs one more `check`. Typecheck recovery can leave wrong types in calls that report no error, and skipping error edges does not cover those.
  > - Q6: The crossing call on a cycle through a bound is already the growth site (devops, web), so D gains little there, and a second walk rule adds spec text for a rare error. With web's note, the agent gets one line in its own code. The declaration with most instances tells it which generic to change in a finite fan.
  >
  > Concern:
  > - Q1: A new way to make an instance that adds no edge gives only the weaker limit error, and no test fails, so each instance site needs a test that names it.
  > - Q3: Worst-case memory scales with body size, which the budget does not count, so a generated program with large bodies can pass the budget and still cost several GB.
  > - Q4: The break needs a corpus sweep for `r([], ...)` and `q(None, ...)` self-calls, and if src or lib use them it needs the 3-step bootstrap dance.
  > - Q5: An agent with a file full of errors can clear them all and then meet a new E0324 that needs a larger rewrite.
  > - Q6: In a finite fan with no repeat, the crossing call depends on walk order and may be a line unrelated to the real growth, so the walk order must be fixed and the note must carry the weight.
  >
  > Objections: none. The budget number 2^20 stands.

- **Minimalism:**
  > Q1: B
  > Q3: D
  > Q4: A
  > Q5: A
  > Q6: D
  > Reasoning:
  > Q1: The limit must ship in every option, and it stops every reached bomb, so the check must earn its place on what it adds. It adds an error on a generic nothing uses, and a clearer first line. That does not justify a new pass and an edge rule for each present and future instance site. I accept that the library-author argument is real and that I am likely alone.
  > Q3: I move from E to D. In B1 I said the two differ by a term nobody can see, and flat250k shows that is wrong: E reaches 1M instances at about 2 GB, and the +1 halves that for one term of text. D also passes wide400x300, which A rejects, and it needs one number. G's 16 is a tuning constant with no meaning to a reader, and it rejects bin15, which costs only 287 MB.
  > Q4: A keeps the language as it is. B adds a new typing rule, and devops's `r([], n - 1)` shows it must also break a program or state another rule for that case, all to make a shape legal that this ticket did not ask for. With A, k4 stays a fast, clear error. If self-call rules deserve a change, that is its own ticket with its own case.
  > Q5: A is the smaller rule: the check reads only types that are known good, and needs no "skip this edge" logic. A cycle error next to a real type error is noise, because the fix to the type error can change the cycle.
  > Q6: D points at the line to change when growth repeats, and the parent links for the chain note give it at little cost. The crossing call in B is often an accident of walk order, and a root note does not say what to edit. With no repeat, D and B name the same site.
  > Concern:
  > Q1: A goes in, and a later instance site misses its edge, so that shape gets the weaker limit error and nothing flags it unless a test names that site.
  > Q3: 2^20 under D still allows about 1 GB in `check`, which is heavy for an LSP on a program near the limit.
  > Q4: A keeps the odd fact that moving a body into a helper can change legality, and this will show up in friction reports.
  > Q5: A user clears all type errors and only then sees a cycle error, which may force a second redesign of the same code.
  > Q6: In a wide program with no repeat, the crossing site is one call among thousands, so the message must lean on its note about the chain.
  > Objections: none, and none to the budget number 2^20.


**Minimalism dissents on Q1.** Minimalism voted B (one limit, one code, no check of declarations): "The limit must ship in every option, and it stops every reached bomb, so the check must earn its place on what it adds. It adds an error on a generic nothing uses, and a clearer first line. That does not justify a new pass and an edge rule for each present and future instance site. I accept that the library-author argument is real and that I am likely alone."

**DevOps dissents on Q5.** DevOps voted B (the check runs next to other errors): "The check reads recorded type arguments, so it can give its answer in a file with an unrelated error, and an LSP user or agent then sees both errors in one round. Escape analysis already reports next to front-end errors. Skipping each edge from a call with an error keeps k4 at one E0300, and it only removes edges, so a reported cycle is still a true one. Low stakes for me."

**Q4 and Q6 stood 3-3** (Q4: Sys, DevOps and Min for A, Web, PLT and AI/ML for B; Q6: Sys, Web and AI/ML for B, PLT, DevOps and Min for D). Both went to Phase D.


#### Phase D — Debate on Q4 and Q6

- **Systems:**
  > **Q4: B (changed).** My Phase C reason was the cost of answering `r([], n - 1)`. A sweep found no such site: 704 generic fns in src, lib and tests (regex, single-line binders), and the only real self-calls (5 sites) pass typed values. So the break costs almost nothing today, and `r[T]([], n - 1)` repairs it. `rg` finds no spec text that makes a self-call monomorphic, so k4's E0300 has no rule behind it; devops's swap finding suggests a substitution fault.
  >
  > web's point decides it. §3.4 says a redundant list is never required (sections/03_types.md:3385). Under A, that sentence is false for `swap`. B adds no instance cost: the cycle check sees k4 like k1. I accept the stated break with no fallback, and plt's corpus run first.
  >
  > **Q6: D (changed), with both devops points.** The walk picks the nearest repeat where the type argument grew, and the root note stays. I said B needs no more bookkeeping, but B's root note already needs the parent chain, so D adds only a loop of at most about 1448 steps.
  >
  > devops is right about the helper. In `fn f[T: Foo](x: T, n: Int) -> Int { h(x) + x.foo(n) }`, each level adds `f`, `h` and the impl method, so the crossing can land on `h(x)`, which has no fault. This is reasoning, not a measurement. D also answers my own Phase C concern: for one growth cycle, the span does not move with walk order.

- **Web/Scripting:**
  >  D, web seat.
  >
  > **Q4: B, held.** sys's strongest point: this is a separate type-system change, with no effect on instance cost. True for cost. But A also writes new spec text: `sections/` has no rule that keeps `T` fixed at a self-call, so A must add one, and that rule then conflicts with "a redundant list is never required" once `sw[B, A]` is fixed. Each side changes the spec here. A separate implementation slice is fine.
  >
  > devops's break is narrower than it reads. Measured:
  >
  > ```blink
  > fn h[T](xs: List[T], n: Int) -> List[T] { xs }
  > fn r[T](xs: List[T], n: Int) -> List[T] {
  >     if n == 0 { return xs }
  >     h([], n - 1)
  > }
  > fn main() { io.println("{r([1], 2).len()}") }   // prints 0
  > ```
  >
  > The return type fixes `T` for a helper today. So I expect a self-call in that position to stay legal under B. Only a call with no source for `T` breaks, and its help already exists.
  >
  > **Q6: changed from B to D, with devops's two conditions:** the repeat must have a grown type argument, and the root note stays. My "the crossing call is the growth site" was wrong. Measured: k6 plus `audit(self)` in the impl body. Its trace shows one `audit` instance in each four, in a fixed repeating order (1,524 instances in 5 s). So a crossing can land on `audit(self)`, a line with no fault. This also gives what E0324 gives: the span is the growth site. With no repeat (k7), the crossing call and its note remain, so walk order must still be fixed for that case.

- **PLT:**
  > plt seat D. No change: Q4 B, Q6 D.
  >
  > **Q4: B.** To "own ticket": k4 is in this ticket's brief, and A writes an E0300 help that B's later ticket must rewrite. The slice can still land apart.
  >
  > To "B breaks `r([], n - 1)`": yes, with a one-edit repair. A text scan of src, lib, tests and examples (3,316 files) finds 706 generic fns, 8 self-calls, and 0 with `[]`, `None` or an empty collection as an argument. The scan is lines only and does not see method self-calls, so the corpus run stays required. A keeps a false §3.4 sentence, to protect a shape that this tree does not use.
  >
  > **Q6: D.** I accept both of devops's points. The walk picks the nearest ancestor of the same declaration with larger type arguments, and the root note stays.
  >
  > To "the crossing call is the growth site" (sys, web, aiml): one site in four here.
  > ```blink
  > fn log_it[A](_a: A) -> Int { 1 }
  > fn f[T: Foo](x: T, n: Int) -> Int { log_it(x) + x.foo(n) }
  > impl[U] Foo for Box[U] {
  >     fn foo(self, n: Int) -> Int { if n == 0 { 0 } else { f(Box { v: self }, n - 1) } }
  > }
  > ```
  > A capped trace (2,520 instances) shows four instances per level, at about 690 units each near 2^20. By extrapolation, this exact program crosses on `f(Box { v: self }, ...)`. About 200 units of unrelated generics move B's span to `x.foo(n)`, and about 900 to `log_it(x)`, which has no fault. D stays on `f(Box { v: self }, ...)`.
  >
  > To "more spec text": one sentence. The parent links already exist for the chain note.

- **DevOps/Tooling:**
  > Q4: I change from A to B. My objection was a fallback rule that exists only for self-calls. B holders add no fallback, and `r[T]([], n - 1)` runs (measured, prints 0), so the objection is gone. A now holds the exception. Measured:
  >
  > ```blink
  > fn k[T](x: T, n: Int) -> Int {
  >     if n == 0 { return 0 }
  >     k[Int, Str](1, n - 1)
  > }
  > ```
  >
  > Today's help: "remove the brackets and let the arguments decide them". That edit gives `TypeError: argument 1 of k expects T, got Int`, while `k[Int](1, n - 1)` compiles. So the help names a repair that fails (rule 1), and §3.4 says "a redundant list is never required". `p(n - 1)` in `p[T]` is already E0301, so `T` is not fixed at all self-calls today. To sys and min (scope): A must write a self-call rule, or leave this help wrong. Condition: corpus run before the text is fixed.
  >
  > Q6: D. I accept both points: the repeat must be one where the type argument grew, and D keeps the root note. Measured: in a cycle through a bound with 3 helpers (`log1(x) + log2(x) + log3(x) + x.g(n)` in `h`), the trace registers 6 instances per level, 3 of them helpers. So under B the crossing lands on a helper call with no growth about half the time. That answers sys and aiml: the crossing is not always the growth site. D needs only the parent links the root note already needs. Walk order also moves B's span, and it moves D's less.

- **AI/ML:**
  > aiml Phase D: Q4 stays B; Q6 changes from B to D.
  >
  > **Q4: B, no change.** To sys ("a separate type-system change"): this ticket must set k4's code anyway. Under A, once the `sw[B, A]` fix lands, `swap[B, A](b, a, n - 1)` compiles and `swap(b, a, n - 1)` does not, so a list is required, against §3.4. To devops: `r([], n - 1)` breaks, I state that, and the repair is one bracket list that I ran. Under A an agent needs two rounds on k4, and it must learn a rule that `sections/` does not hold. Corpus run before the text is fixed: yes.
  >
  > **Q6: changed to D, with devops's two conditions** (the repeat must have a grown type argument; keep the root note). My Phase C reason was wrong. Measured, q6.bl, in probe/aiml:
  >
  > ```blink
  > fn note[V](_x: V) -> Int { 1 }
  > impl[U: M] M for List[U] { fn m(self, n: Int) -> Int {
  >   if n == 0 { return note(self) }
  >   g([self], n - 1) } }
  > fn g[T: M](x: T, n: Int) -> Int { x.m(n) }
  > ```
  >
  > The trace walk order per level is `m`, `note`, `g`, with near-equal weights. So the crossing call is `note(self)`, `g([self], ...)` or `x.m(n)` by chance. Only one of the three is the growth site. Under B the span lands on code with no fault in about two of three cases, and an agent edits at the span. So the sentence "the crossing call sits in the code that grows" fails here. The walk uses parent links that the chain note needs anyway. With no grown repeat, the crossing site stays, and the walk order must be fixed.

- **Minimalism:**
  >  D min: I change Q4 from A to B and hold Q6 at D, and I accept both of devops's points.
  >
  > **Q4: B (changed).** My ballot said B adds a typing rule. That was wrong: B removes one. `rg` finds no self-call rule in sections/. §3 Parametricity makes a body's own `T` rigid, and `src/typecheck.bl:3938` says a callee formal "is still open". At a self-call the formal and the rigid `T` appear to be one tid, so the formal goes rigid. That explains k4 and `sw[B, A]` alike. I read this; I did not build a fix. If so, fixing the settled `sw` bug makes k4 type-check, and A then needs new code to keep an unwritten exception.
  >
  > Strongest point for A: `r([], n - 1)` breaks. I accept that. It gets E0301, as the helper call does, and `r[T]([], n - 1)` repairs it. My regex sweep of tests, lib and src found 9 hits and none is a self-call. It covers only literal `[]` and `None`, so the corpus must still confirm.
  >
  > **Q6: D (held).** sys says the walk mostly finds the same site. With the cycle check, this error is mostly growth through a bound, where a body can branch to a helper and B can then blame that helper. D needs only the parent links that B's root note already needs. Accepted: the repeat must have a grown type argument, and the root note stays. Under D a shared helper at two types never matches. Walk order then matters only when no repeat exists.


#### Phase D — Re-vote on Q4 and Q6

Every seat voted Q4: B and Q6: D, so both went 6-0.

**Q4 moves:** Systems, DevOps and Minimalism moved from A to B. **Q6 moves:** Systems, Web/Scripting and AI/ML moved from B to D. The text of the re-vote is below.

- **Systems:**
  > Q4: B
  > Q4 reasoning: B costs nothing in instances, because a self-call at the same type reaches the same instance and a growing one meets the cycle check as k1 does. The sweeps (mine and plt's) find about 700 generic fns and no self-call with an empty value as an argument, so the break is small, and `r[T]([], n - 1)` repairs it. The spec has no rule that keeps `T` fixed at a self-call, and A would need one that contradicts §3.4. Min's reading is that one tid fault explains both k4 and `sw[B, A]`, which I did not verify; if it holds, A needs new code to keep an unwritten exception.
  > Q4 concern: The sweeps are text scans that do not see method self-calls, so the corpus run may find real breaks, and a use in src or lib would need the bootstrap steps.
  > Q6: D
  > Q6 reasoning: Under B the span can land on a site with no fault: web and plt trace one instance in four as a helper, devops about half, and aiml says about two in three sites are not the growth site. For a cycle, D gives a span that does not depend on walk order or on unrelated generics elsewhere in the program. It adds only a loop over the parent links that the root note already needs, and the chain is at most about 1448 long at this budget. Only a program with no grown repeat still depends on walk order, and the compiler fixes that order.
  > Q6 concern: A chain with two growth sites in one cycle reports only the nearest ancestor's site, so the user can fix one site and then meet the error again at the other.

- **Web/Scripting:**
  > Q4: B
  > Q4 reasoning: One rule for each call is what a dev expects: moving a body into a helper does not change whether it compiles, and a list is never required. Under A, `swap[B, A](b, a, n - 1)` compiles once that bug is fixed and `swap(b, a, n - 1)` does not, and k4 costs a second round trip before the real cause appears. The break is one bracket list, with a help that already exists, and the sweeps by several seats found no real site.
  > Q4 concern: The sweeps are line-level text searches, so the corpus run may find shapes they missed, such as method self-calls, and the self-call with an open `T` needs a clear E0301 help so that it does not read as a new bug.
  > Q6: D
  > Q6 reasoning: People and agents edit at the span, so the span must be where the repair goes, as with E0324. Measured by four seats, the crossing call often lands on a helper such as `audit(self)` with no fault, and small edits elsewhere move it. D needs only the parent links that the root note already uses.
  > Q6 concern: When no grown ancestor exists, as in a wide finite chain, the error falls back to one call among many, so the note must name the declaration and say what to change, or the user will not know where to start.

- **PLT:**
  > Q4: B
  > Q4 reasoning: A self-call is the same judgment as any call to a generic, and every signature is written, so a fresh instance is decidable (Mycroft). `sections/` holds no rule that fixes `T` at a self-call, and devops's `p(n - 1)` shows the compiler does not hold one everywhere; so A must write a new exception that makes §3.4's "a redundant list is never required" false. B's break is narrow: web measured that a return type still supplies `T`, so only a call with no source for `T` gets E0301, with a repair I ran.
  > Q4 concern: The corpus or the 3-step bootstrap may show a self-call site that the single-line sweeps missed, such as a method self-call, and the implementer may need to fix the formal's identity in typecheck with more care than the ticket shows.
  > Q6: D
  > Q6 reasoning: E0324 and E0325 then have one span rule for one fault: the site where the type grows, which is where the repair attaches. Four seats measured the same thing independently: the crossing lands on a helper or dispatch call with no fault, by chance, in most cases. For one growth cycle the span is independent of walk order, and only the no-repeat case needs a fixed order. Wording fix for the writer: the ballot says "with larger type arguments", which is my error from Phase D; an ancestor has smaller type arguments than the crossing instance, so the text must say the crossing instance's arguments are larger than the ancestor's.
  > Q6 concern: A cycle through two growth sites has one nearest ancestor, so the span shows only one of them, and the note must name the chain so that a user who repairs that one site is not surprised by the next E0325.

- **DevOps/Tooling:**
  > Q4: B
  > Q4 reasoning: Under A, the help on `k[Int, Str](1, n - 1)` says to remove the brackets, and that edit gives a TypeError, so the compiler names a repair that fails (rule 1). B removes the only cause: a self-call follows the same rule as a helper call, so the code, message and repair are the same for both. k4 gets E0324 in one round, with a repair that I ran. The break is one bracket list with a help that already exists.
  > Q4 concern: The fresh-instance change can reject more legal self-calls than the text scans found, because those scans do not see method self-calls, so the corpus must run before the text is fixed, and the E0301 help on a self-call must print `r[T]` as a real repair and not as a placeholder.
  > Q6: D
  > Q6 reasoning: The span is where a person, an LSP user and an agent edit first, so it must be the site of the fault. Four seats measured the same fact: under B the crossing can land on a helper call with no growth, about half of the time in my trace. D gives the same site as E0324 for a growth cycle, whatever the walk order, and it uses the parent links that the root note needs. The root note still gives a library user a line in their own code.
  > Q6 concern: A deep repeat at a span inside a library that the user cannot edit is correct but not useful on its own, so the root note must always print, and tests must fix the walk order for the case with no repeat.

- **AI/ML:**
  > Q4: B
  > Q4 reasoning: An agent learns one rule for each call, with no self-call exception, and k4 gets E0324 in one round trip. `sections/` holds no rule that fixes `T` at a self-call, and devops's `k[Int, Str](1, n - 1)` shows that today's help names a repair that fails (rule 1). The cost is one edit, `r[T]([], n - 1)`, which I ran, on a shape the sweeps do not find in this tree.
  > Q4 concern: The sweeps are text searches, so a corpus run could still find a self-call whose type argument has no source, and if src or lib hold one, it needs the bootstrap steps.
  > Q6: D
  > Q6 reasoning: An agent edits at the span, so the span must be the growth site. Four traces (mine, web's, plt's, devops's) show that an off-cycle helper takes a share of the crossings under B. With D, the span also does not move when the program adds unrelated generics. A span that follows the repair matches E0324 and E0301.
  > Q6 concern: The ballot's wording does not reach the case that decided this vote: a crossing on `note(self)` has no ancestor of `note` on its chain, because each `note` instance is a sibling of the cycle, so "the same declaration" as the crossing instance falls back to the crossing site, which is the helper; the writer must say "the nearest declaration on the chain that repeats with a grown type argument, and the span is the call in that stretch where the argument grew", and an ancestor's arguments are smaller, not larger.

- **Minimalism:**
  > Q4: B
  > Q4 reasoning: B removes an exception that sections/ never states, and A would have to write one down. Under A, "a redundant list is never required" (§3.4) is false for `swap`, and devops's `k[Int, Str]` shows today's help already names a repair that fails. The scans found no self-call that passes `[]` or `None`, so the break costs little, and one bracket list repairs it. Moving a body into a helper then no longer changes legality, which is one rule less to learn.
  > Q4 concern: Separating the callee's formal from the rigid `T` may prove larger than my reading of `src/typecheck.bl` suggests, and the line scans do not see method self-calls, so the corpus run could find a break nobody has counted.
  > Q6: D
  > Q6 reasoning: Three seats measured cycles through a bound where the crossing call lands on a helper with no fault, so B's span is often wrong. An agent or user edits at the span, so a wrong span costs a wasted round trip. D adds one sentence and one short loop over the parent links that the root note already needs. That is a small cost for a span that names the real fault and moves less with walk order.
  > Q6 concern: "Larger type arguments" needs one exact meaning (I would compare the stored size summed over all arguments), or two compilers can point at different sites on the same program.


### Points Left Open

- §8.16.1 gives no clear rule for three changes in this decision. E0324 on code that compiles today (an unused `fn r[T]` that calls `r[List[T]]`, or an unused `type P[T]` with a field of `P[(T, T)]`) has no repair that `blink fix` can apply, and the rule asks for a machine-applicable fix when a new error ships as a warning first. E0325 on a finite program that compiles today (for example a long chain of `(x, x)` calls) has the same gap. The Q4 break, `r([], n - 1)` in `fn r[T]`, is E0301 and not a new code, and its help `r[T]([], n - 1)` is a repair that a tool could apply. Whether the rule makes these warnings first was not decided. The spec text points to the rule and picks no answer.
- An implementation note, not a rule: `self.m([], n-1)` in `impl Tm for Int` (a builtin receiver) gave ICE I0001 and not E0301 in the corpus patch. A foreign call `1.m([], 2)` gives the same ICE without the patch.
- `sw[A: Display, B]` with `sw(b, a, n - 1)` compiled and ran in the patch. It is the same gap as a forwarded bound the caller lacks (E0306). No text here depends on it.
- A tie in the count of instances (no grown repeat) and the order of the walk are fixed by a test of the compiler, not by the spec text.
- The meaning of "user code" for the root note is the package that you build. The panel used the words "user code" and "the code of the user".

### Concerns For The Implementation

- Each new way to make an instance adds an edge to the check and a test that names it. A missed edge gives the weaker E0325, not a hang.
- Memory grows with the size of the generic bodies, which the budget does not count. Test at the limit under a 3 GB cap. The 1 GB figures are extrapolated.
- The break of Q4 needs a corpus run, and any use found in `src` or `lib` needs the bootstrap steps. The corpus run found none.
- A call that records a wrong type after a recovery from another error could give a false cycle. E0324 therefore runs only on a front end with no errors.

### Facts From Other Languages

- Go reports an "instantiation cycle" in its type checker, which is the model for E0324 (DevOps, from memory, not checked).
- Rust fires its limit after monomorphization and writes long type names to a file. Rust accepts `Box<P<(T, T)>>` until a method instantiates it, then fails after mono (DevOps and Systems, from memory, not checked).
- C++ `-ftemplate-depth` and Rust `#![recursion_limit]` are settings that change the verdict by build. The panel chose no such setting (Minimalism).
- A self-call at a fresh instance is decidable when every generic signature is written (PLT, citing Mycroft).
