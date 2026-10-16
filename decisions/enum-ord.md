[< All Decisions](../DECISIONS.md)

# Enum Ord — Design Rationale

**Gap:** "Ord for enums: fieldless ordered by tag, data enums only via derive or impl?" The enum-equality decision ([enum-equality.md](enum-equality.md)) decided `Eq` for enums and left `Ord` for same-enum `<`, `<=`, `>`, `>=` to a separate ticket. Open: is a written `impl Ord` on a fieldless enum an error (as `impl Eq` is), and must the order agree with the tag comparison with `Int`?

**Facts given to the panel (measured with build/blink, main @ f39b114f):**

- `type Color { Red  Green  Blue }` (fieldless, no derive): `Color.Red < Color.Green` compiles and prints `true`.
- `Color.Blue.cmp(Color.Red)`: `UnresolvedMethod`. `fn biggest[T: Ord]` called with `Color`: `TraitBoundNotSatisfied`. `(Color.Red, 1) < (Color.Green, 0)`: error. `@derive(Ord) type Q { c: Color  n: Int }`: `NonDerivableTrait`. So same-enum `<` compiled through a path that was not `Ord` by every other test.
- §3.4 *Tag Operations* listed three operations on the tag (comparison with `Int`, `to_int()`, `from_int()`); same-enum `<` was not one of them.
- `@derive(Ord)` on `Color` and on `type Shape { Circle(r: Int)  Sq(s: Int) }` worked, by the derive algorithm (variant index first, then fields).
- `Shape.Circle(1) < Shape.Circle(2)` with no `Ord` reached an internal compiler error (`OrderingMethodNotFound`).
- A written `impl Ord for Color` failed only on the missing supertrait `Eq`, which is the unimplemented part of the decided Eq rule; today's compiler said nothing about whether it should be legal.
- `Option`/`Result` conditional `Ord`, `List.sort`/`sort_by` and `Int.cmp` were out of scope (separate tickets).
- Migration size was not measured.

**Already decided (given to the panel as constraints):** the Enum Equality rule (6-0); tag operations on fieldless enums only; enums nominally distinct from `Int`; `trait Ord: Eq { fn cmp(self, other: Self) -> Ordering }`; the Ord laws; the derive algorithm (5-0); `Set` and `Map` never `Ord`; tuples auto-`Ord` (5-0); wrapping never changes what `==` means; the spec is the blueprint.

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated
in independent-proposal → debate → vote rounds.

#### Phase A — Independent proposals

Full texts, verbatim. In every panel text in this file, ticket IDs are shown as bracketed names. Markdown headings in the panelists' texts are shown as bold lines.

**Systems:**

**Systems: Ord for enums**

**Proposal S1: a fieldless enum is `Ord` with no derive, ordered by tag (declaration order)**

This works the same way as the decided Eq rule. A fieldless enum gets `Eq` and `Ord` with no annotation. `cmp` compares the tags, so the first variant declared is the smallest.

```blink
type Level { Debug  Info  Warn  Error }

fn max_of[T: Ord](a: T, b: T) -> T {
    if a < b { b } else { a }
}

fn main() {
    let lv = max_of(Level.Info, Level.Warn)     // Level.Warn
    let o = Level.Error.cmp(Level.Debug)        // Ordering.Greater
    let t = (Level.Warn, 1) < (Level.Warn, 2)   // true: tuple Ord, all elements Ord
    if lv >= 2 { print("warn or worse") }       // tag comparison with Int, same order
}
```

What the hardware sees: one integer compare on the tag. `a < b` becomes `a_tag < b_tag`. `cmp` becomes a three-way compare with no branches (`(a>b)-(a<b)`). When `max_of[Level]` is monomorphized, it does the same compare, with no call and no vtable. `Level` already exists as a bare integer, so this rule adds nothing at runtime.

It also fixes today's broken state. Now `<` works but `.cmp`, `T: Ord`, tuple Ord and `@derive(Ord)` on a struct with a `Level` field all fail. Under S1 there is one path, and that path is `Ord`.

**Proposal S2: a written `impl Ord` on a fieldless enum is a compile error**

This uses the same reasoning and diagnostic shape as `impl Eq`. A redundant `@derive(Ord)` on a fieldless enum stays legal with no warning, because the derived order and the tag order are the same.

```blink
type Color { Red  Green  Blue }

impl Ord for Color {   // error: fieldless enum `Color` already has Ord by tag order;
                       // to compare in a different way, write a named method
    fn cmp(self, other: Self) -> Ordering { other.to_int().cmp(self.to_int()) }
}

fn by_brightness(a: Color, b: Color) -> Ordering { ... }   // fine
```

On the second open question: the answer is an error, not a law. A law that says "your Ord must agree with the tag comparison with Int" is one the compiler cannot check, and a break gives "unspecified" results. The reversed impl in the brief obeys every Ord law, yet it makes `c < Color.Green` and `c < 1` disagree on the same value. A bug class you can only document is worse than one you remove.

Codegen benefit: the backend may then always lower fieldless-enum Ord to the tag compare. Later work can rely on it: integer sort, binary search on tags, range checks like `lv >= Level.Warn` turned into a single `cmp`. A user impl would force a real call and would block all of that. Custom orders go through `sort_by` or a named method, so the cost shows in the source.

**Proposal S3: a data enum is `Ord` only through `@derive(Ord)` or `impl Ord`, never structurally**

```blink
@derive(Ord)
type Shape { Circle(r: Int)  Sq(s: Int) }

type Token { Num(n: Int)  Word(w: Str) }

fn main() {
    let a = Shape.Circle(1) < Shape.Circle(2)   // true: tag first, then fields
    let b = Token.Num(1) < Token.Num(2)         // error[TraitBoundNotSatisfied]:
                                                // `Token` does not implement Ord;
                                                // add @derive(Ord) or impl Ord
}
```

This turns the [data-enum `<` ICE bug] ICE into a plain diagnostic. A structural Ord would hide a recursive compare whose cost depends on the payloads (a `Str`, a `List`, a nested enum), and that is exactly the kind of hidden cost I object to. A derive keeps the rule symmetric with Eq. It also puts the "variant index first" order the user agreed to at the declaration.

Adding a payload variant later: like Eq, `<` on that enum becomes an error until it gets `@derive(Ord)` or `impl Ord`. That is the right moment to make the order explicit, because "tag first, then fields" is now a real choice.

**Tradeoffs**

- **Reordering variants changes the order.** This is not a new hazard: `to_int()` and the tag comparison with `Int` already depend on declaration order. S1 makes the dependence the same in every place.
- **No custom order for fieldless enums through `Ord`.** If someone needs `Ord` with a different order (as a map key, say), they wrap the enum in a struct that has its own `impl Ord`. That costs nothing at runtime and keeps the bare enum predictable.
- **Rejected option: require `@derive(Ord)` even on fieldless enums.** Then `Color.Red < 1` would be legal while `Color.Red < Color.Green` would not. The order is already exposed through the tag operations, so hiding it from `Ord` only adds friction.
- **No dependence on [Option/Result Ord ticket] (Option/Result Ord).** S1 to S3 say only which enums are `Ord`.

**Cross-language notes**

- **C and Go:** enums are integers, so the order comes free and so does every misuse. Blink keeps the free order and still blocks Int assignability.
- **Rust:** fieldless enums need `#[derive(PartialOrd, Ord)]`, and a hand-written Ord can disagree with `as i32`. That is the disagreement S2 removes.
- **Zig:** no `<` on enums at all, so you write `@intFromEnum`. It is explicit but noisy, and it fails our tuple and generic cases.
- **Swift:** `Comparable` is synthesized only for enums without associated values, and only when you declare it. That is close to S1 and S3, but needs an opt-in.

**Web/Scripting:**

Web/Scripting Phase A proposal for [this gap] (enum Ord).

**Proposal W1: A fieldless enum is a real `Ord`, ordered by declaration, with no derive. Ord mirrors the decided Eq rule clause for clause.**

Rule text:
1. A fieldless enum is `Ord` with no derive and no impl. `cmp` compares the tags, and a variant's tag is its declaration position. It is the real `Ord`, not a separate operator path: `.cmp()` works, `T: Ord` bounds accept it, `@derive(Ord)` on a struct accepts a field of that type, and a tuple that holds it is `Ord`.
2. A written `impl Ord for E` on a fieldless enum is a compile error. Reason: a second order would make `a < b` disagree with `a.to_int() < b.to_int()` and with comparison with `Int`. To sort in a different way, write a named key method and use `sort_by`.
3. A redundant `@derive(Ord)` on a fieldless enum is legal, no warning. The derived order and the tag order are the same.
4. An enum with at least one payload is `Ord` only through `@derive(Ord)` or a written `impl Ord`, the same as a struct. Payload types alone never make it `Ord`. `<` on one without Ord is `error[TraitBoundNotSatisfied]` (or the same code Eq uses), never an ICE.
5. When a fieldless enum gets its first payload variant, `<` and `.cmp()` on it are errors until it gets `@derive(Ord)` or `impl Ord`. Same as Eq.
6. A Str-backed enum is fieldless, so rule 1 applies: the order is declaration order, NOT alphabetical order of the backing strings.

```blink
type Priority { Low  Medium  High }

fn biggest[T: Ord](a: T, b: T) -> T {
    if a > b { a } else { b }
}

@derive(Ord)
type Task { p: Priority  id: Int }      // OK: Priority is Ord

fn main() {
    let top = biggest(Priority.Low, Priority.High)    // Priority.High
    let o = Priority.Medium.cmp(Priority.Low)          // Greater
    let t = (Priority.Low, 9) < (Priority.High, 0)     // true
}

impl Ord for Priority { ... }   // error: Priority is fieldless; its order is its tag order
                                //   help: write a named method, e.g. fn urgency(self) -> Int

type Shape { Circle(r: Int)  Sq(s: Int) }
let bad = Shape.Circle(1) < Shape.Circle(2)
    // error[TraitBoundNotSatisfied]: Shape has payload variants and does not implement Ord
    //   help: add @derive(Ord) to Shape

type Status { Open = "open"  Done = "done"  Archived = "archived" }
let s = Status.Done < Status.Archived   // true: declaration order, not "done" < "archived"
```

Tradeoffs (DX lens):
- One sentence to learn: "fieldless enums are Eq and Ord for free; payload enums need @derive, like structs." The Eq rule already teaches the first half. A split answer ("fieldless is Eq for free but Ord needs derive") is the kind of special case that makes Stack Overflow questions.
- It closes the worst trap we have today. `Color.Red < Color.Green` works but `biggest(Color.Red, Color.Blue)` fails and `.cmp` does not exist. A Python or JS dev reads that as a compiler bug, and they are correct. Under W1, the operator and the trait always agree.
- No migration: every program that compiles today keeps compiling, and some that fail now start to compile.
- The order follows declaration position. That is the order a Kotlin or Java dev expects (`ordinal`, `compareTo`), and we already show it through `to_int()` and comparison with `Int`. The cost: if you move a variant, the order changes silently. This risk exists already through `to_int()`, so W1 adds no new hazard. A doc note ("declaration order is the order; move variants with care") is enough.
- Banning `impl Ord` costs little. In real code, "custom order on a plain enum" is almost always a sort key (`sort_by(fn(t) { t.urgency() })`), which is clearer than a hidden `cmp`. And it keeps `<`, `to_int()` and comparison with `Int` as one fact.
- Str-backed enums: some JS devs will expect string order. Rule 6 says so in one line, and anyone who wants string order writes `a.to_str() < b.to_str()`.

Answer to the second open question: yes, the order must agree with the tag comparison with `Int`. W1 makes that true by construction, so the spec needs no extra law, only the ban in rule 2.

Cross-language:
- Kotlin and Java: every enum is `Comparable` by ordinal, with no opt-in. W1 matches this for fieldless enums.
- Swift: an enum with no associated values gets `Comparable` when you declare it. Associated-value enums need it written. That is the same split as rules 1 and 4, but Swift needs one word of opt-in.
- Rust: needs `#[derive(PartialOrd, Ord)]` for all enums. That is correct but ceremonial; Blink already chose "free" for fieldless Eq.
- Python: plain `Enum` has no `<` (TypeError); `IntEnum` does. Python devs often hit this wall and switch to `IntEnum`. Blink's fieldless enum already acts like an `IntEnum` (comparison with Int, `to_int`), so giving it `<` is what such a dev expects.
- TypeScript: numeric enums compare as numbers, string enums compare as strings. Rule 6 is where we differ from TS, so we document it.

**Rejected alternative W2: fieldless enums Ord only through @derive(Ord)**

This is what Rust and Python do. I reject it for Blink. It breaks existing code (the migration size is not measured), and it leaves a confusing state: `Color.Red < 1` compiles but `Color.Red < Color.Green` does not. Users will read that as a bug. It also breaks symmetry with the decided Eq rule.

Bottom line: W1. Fieldless enums are Eq + Ord for free, with one fixed order (the tag order). You cannot override it. Payload enums opt in like structs. Fix [data-enum `<` ICE bug] to a normal diagnostic.

**PLT:**

Fieldless enums get one built-in `Ord` instance, ordered by declaration (tag) order. Data enums get `Ord` only through a derive or a written impl. A written `impl Ord` on a fieldless enum is an error, the same as `impl Eq`.

**Proposal P1: fieldless enums carry a built-in `Ord` instance (tag order), and it is the only one**

**Typing rule.** For an enum `E`, `Ord(E)` holds when one of these is true:
- `E` is fieldless. The instance is built in and `cmp` compares tags.
- `E` has `@derive(Ord)`.
- `E` has a written `impl Ord for E`.

At most one instance may exist for each type. For a fieldless enum the built-in instance is that one. We should spec it as an **implicit derive** that the declaration makes, for both `Eq` and `Ord`. Then a written `impl Ord for Color` is a normal duplicate-instance error, not a special case. A redundant `@derive(Ord)` gives the same instance, because the derive algorithm compares the variant index first. So the redundant derive is legal with no warning, the same as the decided Eq rule.

```blink
type Color { Red  Green  Blue }

fn biggest[T: Ord](a: T, b: T) -> T {
    if a < b { b } else { a }
}

fn main() {
    let a = Color.Red < Color.Green          // OK: Ord.cmp, built-in
    let b = Color.Blue.cmp(Color.Red)        // OK: Greater
    let c = biggest(Color.Red, Color.Blue)   // OK: Color satisfies Ord
    let t = (Color.Red, 1) < (Color.Green, 0) // OK: tuples are Ord element-wise
    io.println("{a} {b} {c} {t}")
}

impl Ord for Color {                          // error: Color is fieldless and already Ord by variant order
    fn cmp(self, other: Self) -> Ordering {   //   help: for another order, write a named method
        other.to_int().cmp(self.to_int())     //   or pass a comparator to sort_by
    }
}
```

**Why this is the sound choice:**

1. **One meaning of `<`.** §2 and §3.6 define `<` as `Ord.cmp`. Today `Color.Red < Color.Green` compiles but `Color` is not `Ord`. So `<` has a second meaning that skips the trait, and that breaks substitution: an expression that works at a concrete type fails under `[T: Ord]`. P1 closes this gap. All the facts in the brief (`.cmp`, the bound, tuples, `@derive(Ord)` on a struct with a `Color` field) then come from one instance.
2. **It adds no new leak of abstraction.** §3.4 already shows the tag order through `Color.Red < 1` and `to_int()`, so declaration order is already part of the meaning of the type. Moving variants around already breaks callers. A built-in `Ord` shows nothing new.
3. **Agreement becomes a theorem, not a law.** Because no second `Ord` can exist, this holds for every fieldless `E`: `a < b` exactly when `a.to_int() < b.to_int()`, and `a < n` agrees with `a.to_int() < n`. Mixed reasoning stays valid (`a < b` and `b < 2` give `a < 2`). The reversed impl in the brief obeys the Ord laws but breaks this, so a rule that relies on "the laws" alone does not hold. That answers the second open question: we need no extra law, because we forbid the impl itself.
4. **It matches the Eq decision.** A fieldless enum is `Eq` with no derive, and `Ord: Eq`. Having `Eq` built in but not `Ord` would leave no instance for `Ord` to sit on.

**Tradeoff.** For a type such as `Color`, declaration order may mean nothing, and an automatic `Ord` lets a user sort by an order that is an accident of the source. I accept this, because §3.4 already makes that order observable. A user who wants a different order has a named method or a `sort_by` comparator, which needs only a total preorder.

**Proposal P2: data enums get `Ord` only by name**

An enum with at least one payload is `Ord` only through `@derive(Ord)` or `impl Ord`. Payload types alone never make it `Ord`, the same as the Eq rule.
- `@derive(Ord)` also derives `Eq`, which §3.6.1 already says.
- A written `impl Ord` must obey only the three laws. Payload enums have no tag operations, so nothing else has to agree with it.
- With no instance, `Shape.Circle(1) < Shape.Circle(2)` is `error[TraitBoundNotSatisfied]`, not an ICE.
- **First payload:** when a fieldless enum gets its first payload variant, the built-in `Eq` and `Ord` go away together. Each `<` is an error until the declaration has `@derive(Ord)` or an impl.

```blink
@derive(Ord)
type Shape { Circle(r: Int)  Sq(s: Int) }      // Circle(_) < Sq(_), then by field

type Raw { A(n: Int)  B }
let x = Raw.A(1) < Raw.B                         // error: Raw does not implement Ord
                                                 //   help: add @derive(Ord) above `type Raw`
```

**Generic fieldless enums** such as `type Tag[T] { A  B }` are fieldless as written, so they are `Ord` with no bound on `T`. This follows from the fieldless definition and needs no new rule.

**Rejected alternative (P0): fieldless `Ord` only through a derive (Rust/Haskell style)**

P0 also hangs together. But then `Color.Red < 1` is legal while `Color.Red < Color.Green` is an error, so the type gets a tag order you can compare against an `Int` but cannot use against its own values. It also splits the `Eq` and `Ord` rules for one class of types. That is a design with two kinds of order inside one type, and I vote against it.

**Cross-language note**

- **Haskell, Rust:** neither has `Ord` without `deriving`. Neither has a tag comparison with an integer, so declaration order means nothing to the user there. Blink's §3.4 changes that premise.
- **OCaml:** polymorphic `compare` orders every value by its structure. That is the leak P2 avoids for data enums.
- **Coherence:** "one instance for each type" is Haskell's coherence condition. The built-in instance is an instance, so an `impl` beside it overlaps.

**Vote position:** P1 + P2. Fieldless `impl Ord` is an error, and that makes tag agreement a theorem.

**DevOps/Tooling:**

**DevOps/Tooling: Phase A proposals for [this gap] (enum Ord)**

My test for every proposal is the same: is there one rule a user can read off the declaration, one diagnostic for each wrong use, and no path where a feature "works" by accident? Today there is such a path. `Color.Red < Color.Green` compiles, but `.cmp`, `T: Ord`, tuples and `@derive(Ord)` on a struct all say `Color` is not `Ord`. An LSP hover on `Color` cannot say anything true about Ord today. Whatever we decide, `<` must be `Ord` and nothing else.

---

**D1 (preferred): mirror the Eq rule exactly**

**Rule.**
1. A fieldless enum is `Ord` with no derive and no impl. The order is declaration order, which is the tag order. It is a real `Ord`: `.cmp` resolves, `T: Ord` holds, tuples and `@derive(Ord)` structs that hold it work, and `Option[Color]` follows whatever [Option/Result Ord ticket] decides.
2. An enum with at least one payload is `Ord` only through `@derive(Ord)` or a written `impl Ord`. There is no structural Ord.
3. A written `impl Ord for E` on a fieldless enum is a compile error, for the same reason as Eq.
4. A redundant `@derive(Ord)` on a fieldless enum is legal, with no warning.
5. Law, stated in the spec: for a fieldless `E`, `a < b` exactly when `a.to_int() < b.to_int()`. The compiler guarantees this, because rule 3 leaves no way to write a second order.

```blink
type Color { Red  Green  Blue }
type Shape { Circle(r: Int)  Sq(s: Int) }

fn biggest[T: Ord](a: T, b: T) -> T {
    if a > b { a } else { b }
}

fn main() {
    let c = biggest(Color.Red, Color.Blue)      // OK: fieldless enums are Ord
    let k = Color.Blue.cmp(Color.Red)           // OK: Greater
    let s = Shape.Circle(1) < Shape.Circle(2)   // error, see below
}
```

**Diagnostics I want (each one replaces an ICE or a confusing message):**

```
error[TraitNotImplemented]: `Shape` does not implement `Ord`
 --> main.bl:12:13
   |
12 |     let s = Shape.Circle(1) < Shape.Circle(2)
   |             ^^^^^^^^^^^^^^^ `<` needs `Ord`
   = note: `Shape` has a payload variant, so it is not ordered by its tag
help: derive it at the declaration (this also derives `Eq`)
 --> main.bl:2:1
   |
 2 + @derive(Ord)
 2 | type Shape { Circle(r: Int)  Sq(s: Int) }
```

The fix must be machine-applicable, so the LSP shows it as a quick-fix and `blink fix` applies it. The same text covers "first payload added to a fieldless enum": the error points at the `<` and the help points at the `type` line.

```
error[ConflictingImpl]: a fieldless enum cannot implement `Ord`
 --> main.bl:4:1
  |
4 | impl Ord for Color {
  | ^^^^^^^^^^^^^^^^^^ `Color` is already ordered by declaration order
  = note: a second order would make `Color.Red < Color.Green` disagree with
          `Color.Red < 1` and `Color.Red.to_int() < Color.Green.to_int()`
help: to sort in a different order, write a named method or use `sort_by`
```

Use one error code for both the Eq and the Ord forms of "no impl on a fieldless enum", so the docs and `blink explain` have one page.

**Tooling surface.**
- Hover on a fieldless enum: `Eq, Ord (implicit: declaration order)`. `blink doc` prints the same line. One sentence, no inference for the user to do.
- Completion offers `.cmp` on a fieldless enum and does not offer it on a payload enum that has no Ord.
- `blink fmt` must never reorder variants. That is already true, but the spec should say it now, because variant order is meaning.
- A possible later lint (not part of this vote): reordering the variants of a `pub` fieldless enum changes its order, which is an API break. `blink` semver checks can flag it.

**Tradeoff.** With implicit Ord, moving a variant silently changes sort order. But the tag comparison with `Int` and `to_int()` already make declaration order visible, so implicit Ord adds no new hazard. It names the one that exists.

---

**D2 (fallback): fieldless enums need `@derive(Ord)` too**

Same as D1, except that rule 1 becomes "only through derive". Same-enum `<` with no derive becomes `TraitNotImplemented` with the same `@derive(Ord)` fix. This makes "is it ordered?" readable off the declaration, which is good for grep and for review. The costs: Eq and Ord would follow two different rules for the same enum, and enum-vs-Int `<` would work while enum-vs-enum `<` fails, which is an asymmetry I would hate to explain in an error message. If the panel picks D2, use the Eq migration: an immediate error with the machine-applicable fix, and `blink fix` named in the release notes. Measure the site count first. Nobody has measured it yet.

---

**Cross-language note.** In Java and Kotlin, every enum is `Comparable` by ordinal, and `compareTo` is `final`, so no one can override it. That is D1 almost exactly, and in 20 years it has not been a known source of bugs. Rust needs `#[derive(PartialOrd, Ord)]` and orders by discriminant (D2). Swift synthesizes `Comparable` only when the enum declares it (D2). The Java/Kotlin precedent is the closest match to our Eq decision.

**On the open questions:** a written `impl Ord` on a fieldless enum is an error (D1 rule 3). The "agrees with the tag comparison with Int" law is guaranteed by construction rather than left to the user. That keeps sort results and `<` with `Int` in step, so we never have to write a "your Ord disagrees with your tag" lint.

**AI/ML:**

I recommend making fieldless enums fully `Ord` by tag, forbidding a written `impl Ord` on them, and requiring `@derive(Ord)` or `impl Ord` on data enums. This matches the decided Eq rule.

**AI/ML panelist: Phase A proposal (gap [this gap])**

**Proposal 1 (preferred): Ord follows the Eq rule exactly**

**Rule.**
1. **A fieldless enum is `Ord` with no derive and no impl.** The order is the tag order, which is declaration order. It is a real `Ord`, not a separate operator:
   - `.cmp()` exists.
   - The enum satisfies `[T: Ord]`.
   - Tuples that contain it are `Ord`.
   - A struct that contains it can use `@derive(Ord)`.
2. **A written `impl Ord for E` on a fieldless enum is a compile error.** The reason is the same as for `impl Eq`. A second order would make `a < b` disagree with `a.to_int() < b.to_int()` and with `a < 1`. To sort in a different way, write a named method or pass a key function.
3. **A redundant `@derive(Ord)` on a fieldless enum is legal, with no warning.**
4. **A data enum is `Ord` only through `@derive(Ord)` or `impl Ord`.** Without one, `<` is a normal TraitBoundNotSatisfied error with a fix-it that adds `@derive(Ord)`. This replaces the ICE ([data-enum `<` ICE bug]). There is no structural Ord.

```blink
type Color { Red  Green  Blue }

@derive(Ord)
type Shape { Circle(r: Int)  Sq(s: Int) }

fn biggest[T: Ord](a: T, b: T) -> T {
    if a > b { a } else { b }
}

@derive(Ord)
type Pixel { c: Color  n: Int }     // OK: Color is Ord

impl Color {
    fn warmth(self) -> Int {
        match self {
            Red -> 2
            Green -> 0
            Blue -> 1
        }
    }
}

fn main() {
    let a = biggest(Color.Red, Color.Blue)       // Blue
    let o = Color.Blue.cmp(Color.Red)            // Greater
    let t = (Color.Red, 1) < (Color.Green, 0)    // true
    let s = Shape.Circle(1) < Shape.Circle(2)    // true, derived
}

// impl Ord for Color { ... }
//   error: fieldless enum Color is already ordered by tag;
//   a second order would disagree with comparison with Int.
//   To sort in a different way, write a named method (see warmth above).
```

**Second open question.** Rule 2 answers it: the user cannot write an order that differs from the tag order, so the case never comes up. It is better to make this impossible than to make it "unspecified results": an "unspecified" law is a trap that a model cannot see.

**Tradeoffs (AI/ML):**
- **One fact to learn, already in the spec.** "Fieldless enum: `==` and `<` come from the tag, and you cannot override them. Data enum: derive or impl." This adds zero new decision points over Eq. A model that learned the Eq rule gets Ord right without a separate section.
- **No silent change when the first payload is added.** That edit already removes `==`, `to_int`, `from_int` and comparison with Int. Each `<` site then fails with the `@derive(Ord)` fix-it. The derived order is variant index first, so the variants that were fieldless before keep their relative order. A machine fix-it keeps the old behavior, so the loop is mechanical and safe.
- **Fixes today's split.** At the moment, `<` works but `.cmp`, `[T: Ord]`, tuples and derive fields fail. Models generalize from `<` working, so today's split makes the most errors.
- **Token cost.** Zero tokens for the common case (state machines, levels, priorities). One line for data enums, which models already write by Rust habit.
- **Cost: declaration order now has meaning.** If someone reorders the variants, the sort order changes with no error. Comparison with Int already has this cost, so it is not new. I would accept a lint/doc note ("variant order is the sort order"), but not a language rule.

**Cross-language.** In Java and Kotlin, enums are `Comparable` by ordinal and `compareTo` is **final**, so you cannot override it. Rule 2 is that model, and it is the one most often seen in training data. Swift synthesizes `Comparable` for enums with no associated values but lets you write your own, so its `<` and `rawValue` comparison can disagree. Rust and Haskell need `derive(PartialOrd/Ord)` or `deriving Ord`, which gives the ceremony with no gain for fieldless enums.

**Proposal 2 (rejected, for the record): allow a written impl Ord on fieldless enums**

The argument for it: "Severity order differs from declaration order." But it adds a decision point ("does this enum's `<` mean the tag or the impl?"). It also gives two orders on the same values (`c < 1` versus `c < d`). A model cannot tell which one applies without reading the impl. The real need already has two answers: reorder the variants, or sort by a key. It would also break symmetry with the decided Eq rule, and models are bad at learning asymmetries.

**Notes for the moderator**

- The Eq decision already lists "same-enum `<`" under tag operations by implication. §3.4 should name it explicitly, or §3.6 should say "fieldless enums are Ord by tag", so that the text matches rule 1.
- Hash is unaffected (it still needs a derive, per fvceqe).
- This rule does not depend on [Option/Result Ord ticket] (`Option`/`Result` Ord).
- Migration size has not been measured. Under Proposal 1, no existing fieldless `<` site changes. Only code that uses `<` on a data enum with no Ord changes, and that code reaches the ICE today.

**Minimalism:**

**Minimalism panelist: Phase A proposal ([this gap], enum Ord)**

**Proposal M1 (recommended): Ord follows the Eq rule exactly. One rule, no new surface**

1. **Fieldless enum.** It is `Ord` with no derive and no impl. The order is declaration order, which is the tag order. This is a real `Ord` impl, so `.cmp`, `T: Ord` bounds, tuples and `@derive(Ord)` fields all work. The special path that lets `<` compile today without `Ord` goes away.
2. **Enum with a payload.** It is `Ord` only through `@derive(Ord)` or a written `impl Ord`, the same as a struct. There is no structural Ord, and payload types alone never make it `Ord`. `<` without `Ord` is `error[TraitBoundNotSatisfied]`, which also fixes the [data-enum `<` ICE bug] ICE.
3. **Written `impl Ord` on a fieldless enum is a compile error.** The reason is the same as for `impl Eq`. A second order would make `Color.Red < Color.Green` disagree with `Color.Red < 1` and with `.to_int()`. To sort in a different way, write a named method or use `sort_by`.
4. **Redundant `@derive(Ord)` on a fieldless enum** is legal, with no warning. It is the same as the Eq rule. The derive algorithm (variant index first) gives the identical order.
5. **First payload variant added:** `<` on that enum is an error until it gets `@derive(Ord)` or `impl Ord`. This mirrors Eq.

```blink
type Color { Red  Green  Blue }

fn biggest[T: Ord](a: T, b: T) -> T {
    if a > b { a } else { b }
}

fn main() {
    print(Color.Red < Color.Green)            // true, tag order
    print(Color.Blue.cmp(Color.Red))          // Greater
    print(biggest(Color.Red, Color.Blue))     // Blue
    print((Color.Red, 1) < (Color.Green, 0))  // true, tuple auto-derive
}

type Shape { Circle(r: Int)  Sq(s: Int) }
// Shape.Circle(1) < Shape.Circle(2)  -> error: Shape does not implement Ord

@derive(Ord)
type Shape2 { Circle(r: Int)  Sq(s: Int) }
// Shape2.Circle(1) < Shape2.Circle(2) -> true

// impl Ord for Color { ... }  -> error: fieldless enum Color already has
//   its tag order; a second Ord would disagree with comparison with Int.
//   Write a named method, or use sort_by.
```

**Tradeoffs (minimalism lens):**
- **It adds no new rule.** It copies a 6-0 decision onto the next trait, so a user who learned the Eq rule already knows this one. Two rules for two sibling traits would be the C++ path.
- **It removes a question.** The ticket asks whether a written Ord must agree with the tag comparison with Int. When we forbid the impl, that question cannot come up. There is no law for implementers to keep and no "unspecified results" area to document. The reversed-impl example in the brief cannot be written.
- **It removes a compiler special case.** Today `<` works on `Color` but `Color` is not `Ord`. After M1 it is `Ord` everywhere or nowhere.
- **It costs almost no flexibility.** A custom order on a fieldless enum is a sort key, not the type's identity. `sort_by(|c| priority(c))` or a named method handles it with no language surface. If a user wants a different order, they can reorder the declaration.
- **Migration should be near zero.** Every same-enum `<` on a fieldless enum that works today keeps working, because only things that are errors today change. Someone still needs to measure this, but M1 does not break the existing fieldless `<` uses, whatever their number.

**Cross-language:** Rust needs `#[derive(PartialOrd, Ord)]` even for C-like enums. That is more ceremony for the common case, but Rust has no implicit enum-Int comparison that the order must agree with. Swift's `Comparable` conformance for enums without associated values is synthesized, but you must still declare it. Java `Enum` is `Comparable` by ordinal and `compareTo` is `final`, which is exactly rule 3, and it has held up for 20 years. C/C++ enums order by value because they *are* integers. Blink's tag comparison with Int puts it in Java's camp, so Java's choice of a fixed final ordinal order fits.

**Proposal M2 (alternative, more subtraction): fieldless enums need `@derive(Ord)`**

Remove the implicit order. `Color.Red < Color.Green` is an error without `@derive(Ord)`. This is smaller in principle, because derive is the only way in.

**Why I rank it below M1:** it breaks working code. It also leaves `Color.Red < 1` legal (§3.4) while `Color.Red < Color.Green` is illegal, which is a worse inconsistency than the one we are fixing. And it splits Eq (implicit) from Ord (explicit) on the same type. To be consistent, M2 would also require removing the `<` forms of tag comparison with Int. That reopens a decided rule, so it is out of scope.

**Rejected options**

- **Do nothing.** There is an ICE, and `<` is not `Ord`. The gap is real.
- **Structural Ord on payload enums.** The Eq panel already rejected structural derivation (6-0). Doing it for Ord alone would bring back the asymmetry.
- **Allow `impl Ord` on a fieldless enum with an "agree with tag" law.** This adds a law that the compiler cannot check, plus a class of silent bugs, to support a use case that `sort_by` already covers.

**Vote intent:** M1. It is foundational, it replaces a special case, and it adds nothing a user must learn beyond the Eq rule.

#### Phase B — Debate

##### Moderator digest (mechanical dedupe of Phase A)

**Phase B — round 1 broadcast (moderator, mechanical dedupe of Phase A)**


**Distinct options**

**Option A — fieldless enums are a real `Ord` by tag (declaration) order with no derive; written `impl Ord` on a fieldless enum is a compile error; redundant `@derive(Ord)` on a fieldless enum is legal, no warning; an enum with a payload is `Ord` only through `@derive(Ord)` or a written `impl Ord`, never structurally; adding a first payload variant makes `<` an error until derive/impl.**
Proposed as first choice by: sys (S1+S2+S3), web (W1), plt (P1+P2), devops (D1), aiml (Proposal 1), min (M1).

**Option B — fieldless enums are `Ord` only through `@derive(Ord)` too (same-enum `<` with no derive is an error); data enums as in A.**
Proposed as fallback/second choice by: min (M2), devops (D2). Named and rejected by: web (W2), plt (P0), sys (rejected option), aiml (not proposed).

**Sub-points raised by only one or two panelists (not yet discussed by the others)**

1. **Str-backed enums** (web, W1 rule 6): a Str-backed enum is fieldless, so its order is declaration order, not the order of the backing strings; the spec says so in one line.
2. **Stated law** (devops, D1 rule 5): the spec states "for a fieldless `E`, `a < b` exactly when `a.to_int() < b.to_int()`", guaranteed because no second order can be written. (plt P1 point 3 calls the same fact a theorem.)
3. **One error code** (devops): one diagnostic code for both "no `impl Eq` on a fieldless enum" and "no `impl Ord` on a fieldless enum".
4. **Formatter** (devops): the spec says `blink fmt` never reorders variants, because variant order is meaning.
5. **Framing as implicit derive** (plt, P1): spec the built-in `Eq` and `Ord` of a fieldless enum as an implicit derive made by the declaration, so a written `impl Ord` is an ordinary duplicate-instance error rather than a special case.
6. **Generic fieldless enums** (plt, P2): `type Tag[T] { A  B }` is fieldless as written, so it is `Ord` with no bound on `T`.
7. **Custom order** (sys): a user who needs `Ord` with another order wraps the enum in a struct with its own `impl Ord`; (web, aiml, min, plt, devops): a named method or a `sort_by` comparator.
8. **§3.4 wording** (aiml): §3.4 *Tag Operations* or §3.6 should name same-enum ordering explicitly so the text matches the rule.
9. **Lint, out of scope** (devops, aiml): a possible later lint/semver check for reordering variants of a `pub` fieldless enum; both said it is not part of this vote.

**Your reply**

Reply to the moderator (team-lead) with:
- Your position on A vs B (one line is fine if unchanged).
- For each sub-point 1–8: accept / reject / no view, with a reason when you reject or want a change.
- Any new argument you want the other panelists to see.
- End with "stable, ready to vote" if you are ready.
Keep it under ~400 words. Plain SendMessage text to team-lead.

##### Round 1 replies

Full texts, verbatim. All six ended with "stable, ready to vote", so Phase B stopped after one round.

**Systems:**

**Systems — Phase B round 1**

**Position:** Option A, unchanged. B makes `Color.Red < 1` legal and `Color.Red < Color.Green` illegal on the same type. That adds friction and gives nothing back in cost or safety.

**Sub-points**

1. Str-backed enums: accept. The backing string is data; the tag is the order. One line in the spec stops users from expecting a string compare.
2. Stated law: accept. The compiler can rely on it, and the backend can always lower fieldless Ord to one integer compare.
3. One error code: accept. Same rule, same reason, one code.
4. Formatter never reorders variants: accept. Variant order is meaning (to_int, tag compare with Int, Ord).
5. Implicit-derive framing: accept, with one condition. The text must keep a redundant `@derive(Ord)` (and `@derive(Eq)`) legal with no warning, so the framing must say the explicit derive is the same instance, not a second one. Only a written `impl` is the duplicate.
6. Generic fieldless enums: accept. `T` is not in any payload, so the layout is the bare tag and the compare is the same integer compare for every `T`. No bound on `T` is correct.
7. Custom order: accept both, as two uses. A named method or a `sort_by` comparator is the ad-hoc path. A struct wrapper with its own `impl Ord` is the path when a generic `T: Ord` (a sorted container, a key) needs the other order. The wrapper has the same layout as the enum, so it costs nothing at runtime. The spec can name both in one sentence.
8. §3.4 wording: accept. §3.4 lists tag operations; same-enum ordering belongs in §3.6 next to the fieldless Eq rule, with a cross-reference from §3.4. That keeps §3.4 a list of tag-with-Int operations.

**New argument**

Under A, a fieldless enum is Eq, Ord and (later) Hash with no annotation, and all three are fixed functions of the tag. That gives one invariant the backend can use everywhere: for a fieldless enum, ==, cmp and hash never call user code. B would keep the same lowering, but only after the user writes a derive. So B adds an annotation and no new guarantee.

stable, ready to vote

**Web/Scripting:**

Web/Scripting, Phase B round 1.

Position: Option A, unchanged. Option B removes something that works today and leaves `Color.Red < 1` legal while `Color.Red < Color.Green` is not. That is the worst DX result on the table.

Sub-points:
1. Str-backed order: accept (my point). A TS dev expects string order, so the spec needs this one line.
2. Stated law: accept. Users read "a < b exactly when a.to_int() < b.to_int()" faster than they derive it from the ban.
3. One error code: accept. One rule ("a fieldless enum has a built-in Eq and Ord; you cannot write another") gives one code and one explain page. The message must still name the trait the user wrote.
4. Formatter never reorders variants: accept. It costs one sentence and removes a silent behavior change.
5. Implicit-derive framing: accept for the spec text. One condition: the diagnostic must not read like a generic "duplicate impl". It must say why and give the fix: "Color is fieldless, so its order is its declaration order; write a named method or use sort_by".
6. Generic fieldless enums: accept. No variant holds a T, so a bound on T would be a check with nothing to check. Users would hit it as a confusing error.
7. Custom order: accept both. In the help text, name the named method / sort_by first, because that is the 90% case (sorting by a key). Name the wrapper struct second, for when a user needs a `T: Ord` value with another order.
8. §3.4 wording: accept. §3.4 lists "three tag operations" today, and a reader will think same-enum `<` is not allowed. Add same-enum comparison there, or put a cross-reference to the §3.6 rule.

New argument: with A, one sentence covers the whole user-facing model: "Fieldless enums are Eq and Ord for free, in declaration order; enums with payloads opt in with @derive, the same as structs." Each sub-point above fits into that sentence or follows from it. If a proposed change cannot be explained inside that sentence, I will vote against it.

Second, the [data-enum `<` ICE bug] ICE must become a normal diagnostic with a fix-it ("add @derive(Ord) to Shape") in the same change. A crash is the first thing a new user sees when they try `<` on a payload enum.

stable, ready to vote

**PLT:**

PLT Phase B round 1: Option A, unchanged. Stable, ready to vote.

**Position:** Option A. Under B, `Color.Red < 1` is legal while `Color.Red < Color.Green` is an error. That gives one type a tag order that it cannot use against its own values. I reject B.

**Sub-points:**
1. **Str-backed enums: accept.** The order comes from the tag, which is the declaration order, so the backing strings must not change it. Give it one line.
2. **Stated law: accept.** Write it as a guarantee, not as a law that a user must keep. No user code can break it, so the compiler may rely on it.
3. **One error code: accept.** The rule for `impl Eq` and `impl Ord` is one rule (a second instance on a type that already has one built in), so one code fits.
4. **Formatter: accept.** Variant order is part of what the type means, through `to_int`, the comparison with `Int` and now `Ord`. A tool that moves variants changes behavior.
5. **Implicit derive: hold.** This framing gives three rules with no new text:
   - A written impl next to it is an ordinary duplicate-instance error.
   - A redundant `@derive(Ord)` gives the same instance, so it is legal.
   - The "first payload" rule follows: the implicit derive applies only while the enum is fieldless as written, so when the first payload comes, `Eq` and `Ord` go away together.

   I ask the moderator to write the spec text this way.
6. **Generic fieldless enums: hold.** `type Tag[T] { A  B }` has no payload, so a bound on `T` would be over-constrained, with nothing in the order that uses `T`.
7. **Custom order: accept both.** Use a named method or a `sort_by` comparator for a one-off order. Use a struct wrapper with its own `impl Ord` when generic code needs `T: Ord` with another order. The wrapper is the newtype pattern from Haskell, and it keeps coherence: one instance for each type.
8. **§3.4 wording: accept.** Add same-enum ordering in §3.6 next to the Eq rule, with a cross-reference from §3.4. The comparison with `Int` stays a tag operation and is not `Ord`, because `Ord.cmp` takes `Self` on both sides.

**New argument for the other panelists:** under A, `<`, `==`, `to_int` and the comparison with `Int` all come from one source, the tag. Every derived and built-in instance then agrees with them by construction. Under B, or with a written `impl Ord` allowed, they can disagree. Then generic code under `[T: Ord]` and code at a concrete type could give different answers for one expression. That is the substitution failure the brief measured today.

stable, ready to vote

**DevOps/Tooling:**

**DevOps/Tooling: Phase B round 1**

**Position:** A. My D2 is withdrawn. Six of us reached A on our own, and B's enum-vs-Int `<` working while enum-vs-enum `<` fails is a diagnostic I do not want to write.

**Sub-points:**

1. **Str-backed enums: accept.** Users will guess the order of the backing strings, so one spec line prevents a real bug report. Hover on a Str-backed enum shows `Ord (implicit: declaration order)`, the same as any other fieldless enum.
2. **Stated law: accept.** It reads the same as plt's theorem. State it once, in §3.6 next to the Ord laws.
3. **One error code: accept, merged with 5.** If 5 passes, the code is the duplicate-instance code, used for both Eq and Ord. My condition: the message must not be a bare "conflicting impl" with no location for the first impl. It must say where the first instance comes from:
   ```
   error[ConflictingImpl]: `Ord` is already implemented for `Color`
    --> main.bl:4:1
     |
   4 | impl Ord for Color {
     | ^^^^^^^^^^^^^^^^^^ second impl
     |
    ::: main.bl:1:1
     |
   1 | type Color { Red  Green  Blue }
     | ------------------------------- a fieldless enum is `Eq` and `Ord` by declaration order
   help: to sort in a different order, use `sort_by`, or wrap `Color` in a struct with its own `impl Ord`
   ```
   With no span for the first impl, a user will look for an impl they never wrote.
4. **Formatter: accept.** One sentence, in the fmt section.
5. **Implicit derive framing: accept,** with the diagnostic condition in 3. It also gives the LSP one model: "go to impl" on `Color: Ord` jumps to the `type` line.
6. **Generic fieldless enums: accept.** This matches the decided Eq wording, "fieldless as the declaration is written". Hover on `Tag[T]` must show `Ord` with no `T: Ord` bound, so that nobody adds a useless bound.
7. **Custom order: accept both, as two cases.** `sort_by` (or a named method) is for a one-time order. sys's wrapper struct is for when a `T: Ord` bound must hold, such as a sorted container or generic code. The help line in 3 names both.
8. **§3.4 wording: accept.** §3.4 *Tag Operations* should cross-reference the §3.6 rule. Same-enum `<` is not a tag operation: it is `Ord`, which happens to agree with the tag order. Do not list it as a fourth tag operation, or tag ops and Ord turn into two rules again.

**New argument for the others:** under A, bug [data-enum `<` ICE bug] (`Shape.Circle(1) < Shape.Circle(2)` gives an ICE) becomes a normal `TraitNotImplemented` with a machine-applicable `@derive(Ord)` fix at the `type` line. The impl ticket must include that fix and a test for it. The diagnostic is half of what this rule delivers, not polish to add later.

stable, ready to vote

**AI/ML:**

aiml, Phase B round 1: I keep Option A. I reject B.

**A vs B.** A is unchanged. B adds a derive to fieldless enums when only one order is possible (the tag order, which `c < 1` already fixes). Models will write `Color.Red < Color.Green` with no derive and fail. That is ceremony with no choice behind it.

**Sub-points:**
1. **Str-backed enums: accept.** Models will guess that the order comes from the backing strings. One line in the spec prevents that error.
2. **Stated law: accept.** Put it in the spec as a sentence: "for a fieldless `E`, `a < b` exactly when `a.to_int() < b.to_int()`". A model reads a stated rule more reliably than one it must derive.
3. **One error code: accept.** One code and one `blink explain` page cover Eq and Ord. The rule is learned once.
4. **Formatter never reorders variants: accept.** It costs one line and protects meaning.
5. **Implicit-derive framing: accept, with one change.** The spec must say that the implicit derive covers `Eq` and `Ord` only, not `Hash`, `Display` or `Debug`. "Implicit derive" alone invites a model to assume `Set[Color]` works. The diagnostic should also state the reason (agreement with comparison with Int), not only "duplicate instance", so that the fix-it points to a named method.
6. **Generic fieldless enums: accept.** This follows from the definition and needs no new rule.
7. **Custom order: accept both, but the spec shows one example first.** The canonical answer is a named key method used with `sort_by`. The struct wrapper is the answer only when a type must itself be `Ord` with another order (for example a map key). Showing two equal options adds a decision point.
8. **§3.4 wording: keep.** §3.4 or §3.6 names same-enum ordering in plain text.

**New argument.** Under A, the fix-it for the first payload (`@derive(Ord)`) keeps the old relative order of the existing variants, because the derived order compares the variant index first. A machine fix-it that keeps the old behavior is the safest kind of auto-repair for an AI agent loop. B gets no gain at this point, because its derive is already present.

stable, ready to vote

**Minimalism:**

**min, Phase B round 1**

**A vs B:** A. I withdraw M2. Everyone ranks A first, and B breaks working code while `Color.Red < 1` stays legal.

**Sub-points:**
1. **Str-backed enums, declaration order:** accept. One line removes a likely misreading, and it adds no rule.
2. **Stated law (`a < b` exactly when `a.to_int() < b.to_int()`):** accept, as a stated consequence, not a new requirement. It is the reason we forbid the impl, so say it once.
3. **One error code for impl Eq / impl Ord on a fieldless enum:** accept. It is one concept, so it gets one code. The message names the trait.
4. **Formatter never reorders variants:** accept, but as one sentence in the fmt/tooling section, not in §3.6. It is true of the formatter today and does not belong in the Ord rule.
5. **Implicit-derive framing:** accept with one change. If the declaration is an implicit derive, then a written `impl Ord` is a duplicate instance. A redundant `@derive(Ord)` would also be a duplicate under that framing. The Eq decision (6-0) makes redundant derive legal with no warning, so the spec text must say so explicitly: "an explicit `@derive(Eq)`/`@derive(Ord)` on a fieldless enum names the same instance and is not a duplicate". Also keep the decided Eq error message's reason text (tag comparison with Int). Do not reduce it to a generic "duplicate impl", because users need the why.
6. **Generic fieldless enum `Tag[T]` is Ord with no bound on T:** accept. It follows from "fieldless as written", and I want no extra rule. Confirm that the Eq rule reads the same way, so the two traits do not split.
7. **Custom order:** accept both a named method and a `sort_by` comparator in the diagnostic hint. The struct wrapper (sys) is valid but needs no spec text: it is ordinary code. The spec text needs only "write a named method, or wrap it in a type with its own `impl Ord`".
8. **§3.4 / §3.6 wording:** accept. Put same-enum ordering in §3.6 next to the enum Eq rule. §3.4 keeps its three tag operations and gets a cross-reference. Do not add a fourth "tag operation", because same-enum `<` is `Ord`, not a tag operation, and the old special path is what we are removing.

**New argument:** no new syntax and no new trait come from this decision. The full change is "copy the Eq paragraph, swap Eq for Ord, add the Int-agreement sentence". If the spec diff grows past that, someone has added scope. The out-of-scope lint (item 9) stays out.

stable, ready to vote

#### Phase C — Final vote

##### Ballot

**Phase C — silent vote (final positions)**

All six Phase B round 1 replies said "stable, ready to vote". Their full texts are in Phase B above. Vote alone; do not message other panelists.

Each question's wording is built from the panelists' own Phase A/B text; the conditions panelists attached are folded in and attributed.

**Q1. Core rule.**
- **A:** a fieldless enum is a real `Ord` by tag (declaration) order with no derive (`.cmp`, `T: Ord`, tuples, `@derive(Ord)` fields all work); a written `impl Ord` on a fieldless enum is a compile error; a redundant `@derive(Ord)` on it is legal, no warning; an enum with a payload is `Ord` only through `@derive(Ord)` or a written `impl Ord`, never structurally; when a fieldless enum gets its first payload variant, `<` is an error until derive/impl; `<` on a data enum with no Ord is a normal diagnostic, never an ICE.
- **B:** fieldless enums are `Ord` only through `@derive(Ord)`; data enums as in A.

**Q2. Str-backed enums (web).** A Str-backed enum is fieldless, so its order is declaration order, not the order of its backing strings. The spec says so in one line. — accept / reject

**Q3. Stated guarantee (devops; plt "theorem").** §3.6, next to the Ord laws, states: for a fieldless `E`, `a < b` exactly when `a.to_int() < b.to_int()`, and the same for `<=`, `>`, `>=` and `cmp`. It is written as a guarantee the compiler gives (no user code can break it), not as a law a user must keep (plt, min). — accept / reject

**Q4. Diagnostic for a written impl on a fieldless enum (devops, web, min, aiml, plt).** One diagnostic code covers a written `impl Eq` and a written `impl Ord` on a fieldless enum. The message names the trait the user wrote; it states the reason (the enum already has `Eq`/`Ord` by declaration order; a second one would disagree with comparison with `Int`), not only "duplicate impl"; it has a secondary span on the `type` line saying where the built-in instance comes from (devops); the help names the fix. — accept / reject

**Q5. Implicit-derive framing (plt), with conditions (min, aiml, sys).** The spec text says a fieldless enum's declaration gives it `Eq` and `Ord` as an implicit derive, while the enum is fieldless as written. It covers `Eq` and `Ord` only, not `Hash`, `Display`, `Debug`, `Clone`, `Serialize` (aiml). An explicit `@derive(Eq)` / `@derive(Ord)` names the same instance and is not a duplicate, legal with no warning (min, sys). Only a written `impl` is a duplicate. When the first payload variant is added, the implicit `Eq` and `Ord` go away together. — accept / reject

**Q6. Generic fieldless enums (plt).** `type Tag[T] { A  B }` is fieldless as written, so it is `Eq` and `Ord` with no bound on `T`. — accept / reject

**Q7. Custom order guidance.** Two versions were raised:
- **7a (min, aiml-leaning):** the spec and the help text name one canonical way: a named key method used with `sort_by` (or a `sort_by` comparator). The struct wrapper is ordinary code and gets no spec text.
- **7b (sys, plt, devops, web):** the spec and the help name both, in this order: a named method or `sort_by` comparator for a one-off order first; a struct wrapper with its own `impl Ord` second, for when a `T: Ord` bound must hold with another order.

**Q8. Placement (min, devops, sys, plt, web, aiml).** Same-enum ordering goes in §3.6 next to the fieldless-enum Eq rule. §3.4 *Tag Operations* keeps its three tag-with-`Int` operations and gets a cross-reference to §3.6. Same-enum `<` is `Ord`, not a fourth tag operation. — accept / reject

**Q9. Formatter (devops; min, web on placement).** One sentence in the tooling/fmt section: `blink fmt` never reorders variants, because variant order is meaning (`to_int`, comparison with `Int`, `Ord`). — accept / reject

**Format, per question**

1. **Vote** — option letter, or accept/reject.
2. **Reasoning** — 2–4 sentences in your domain.
3. **Concern** — one sentence on what could go wrong with the option you expect to win, from your POV.


##### Tally

- **Q1 core rule:** A, 6-0.
- **Q2 Str-backed enums:** accept, 6-0.
- **Q3 stated guarantee:** accept, 6-0.
- **Q4 one diagnostic:** accept, 6-0.
- **Q5 implicit-derive framing:** accept, 6-0.
- **Q6 generic fieldless enums:** accept, 6-0.
- **Q7 custom order guidance:** 7b, 5-1. **Minimalism:** *(dissent)* 7a. Phase D did not run (5-1).
- **Q8 placement:** accept, 6-0.
- **Q9 formatter:** accept, 6-0.

The Systems ballot was cut off by the tool partway through the Q7 reasoning. The vote line (7b) was written before the cut; Systems cast Q8 and Q9 after it and gave no new Q7 reason. The text below marks the cut.

##### Ballots

Full texts, verbatim.

**Systems:**

**Systems — Phase C ballot**

**Q1. Vote: A.**
Reasoning: Fieldless Ord is one integer compare on the tag, with no call and no vtable after monomorphization, so the built-in rule costs nothing. It also makes the one path that works today (`<`) agree with `.cmp`, `T: Ord`, tuples and derive fields. Data enums need a derive because their compare cost depends on the payloads, and that cost should show at the declaration.
Concern: Users who add a first payload variant to a widely used enum will see many `<` errors at once; the diagnostic must point straight at `@derive(Ord)`.

**Q2. Vote: accept.**
Reasoning: The backing string is data; the tag is the value the compare uses. A string compare would be a hidden O(n) cost and a different order from `to_int`.
Concern: Users may still expect alphabetical order, so the line must be easy to find.

**Q3. Vote: accept.**
Reasoning: A guarantee the compiler gives lets the backend always lower fieldless-enum ordering to the tag compare and lets later work (integer sort, range checks) depend on it. A law the user must keep gives none of that.
Concern: The guarantee must stay true if a later feature (for example explicit tag values) lets the tag order differ from declaration order; the text should tie it to `to_int`, as written.

**Q4. Vote: accept.**
Reasoning: One rule, one code. A message that gives the reason and points at the `type` line saves a round trip to the docs.
Concern: The code must not be reused for unrelated duplicate impls, or its meaning blurs.

**Q5. Vote: accept.**
Reasoning: The implicit-derive framing reuses the duplicate-instance machinery the compiler already has, so the checker needs no special case. Scoping it to `Eq` and `Ord`, and keeping explicit derives legal, matches what I asked for.
Concern: The spec must say clearly that "fieldless as written" is checked on the declaration, not after generic substitution.

**Q6. Vote: accept.**
Reasoning: `T` is in no payload, so the layout is the bare tag and the compare is the same for every `T`. A bound on `T` would be a constraint with no runtime meaning.
Concern: None from codegen; the only risk is a user who expects `T` to matter, which the spec example should prevent.

**Q7. Vote: 7b.**
Reasoning: A comparator covers one-off sorts, but a generic `T: Ord
[Q7 reasoning cut off; vote 7b stands.]

**Q8. Vote: accept.**
Reasoning: Same-enum `<` is a trait instance, so it belongs with the Eq rule and the Ord laws in §3.6. §3.4 then stays a short list of the operations that compare a tag with an `Int`. One place for the rule means one place the compiler and the reader check.
Concern: Readers who start at §3.4 may miss the rule if the cross-reference is not on the comparison line itself.

**Q9. Vote: accept.**
Reasoning: Variant order sets `to_int`, the comparison with `Int` and `Ord`, so a reorder changes program output. A tool that changes meaning while it claims to change only layout is a bug. One sentence costs nothing and blocks a future "sort variants" option.
Concern: None for codegen; the sentence must also cover any later auto-fix or refactor tool, not only `blink fmt`.

**Web/Scripting:**

Web/Scripting, Phase C ballot.

Q1. Vote: A.
Reasoning: Users learn one sentence: "Fieldless enums are Eq and Ord for free, in declaration order; enums with payloads opt in with @derive, like structs." It is what Kotlin and Java devs expect, and Python IntEnum users too. It breaks no code that compiles today. It also removes the trap where `<` works but `.cmp`, `T: Ord` and tuples do not.
Concern: a user who reorders variants changes the sort order with no warning. Docs must say "declaration order is the order".

Q2. Vote: accept.
Reasoning: A TypeScript dev expects a string enum to sort by its strings. One line stops that question before someone asks it. A user who wants string order writes `a.to_str() < b.to_str()`.
Concern: the line can get lost in §3.4. It must go next to the Str-backed enum text, or point to it.

Q3. Vote: accept.
Reasoning: A user can read a stated guarantee in one line. Without it, a user has to work out the fact from the impl ban. Wording it as a compiler guarantee and not a user law is correct, because no user code can break it.
Concern: none of note. Keep it to one sentence and do not add a proof.

Q4. Vote: accept.
Reasoning: One code and one explain page for one rule. The message names the trait the user wrote and gives the reason and the fix, so the user does not have to search for an answer. The secondary span on the `type` line answers "where does this Ord come from?" at the point where the user gets confused.
Concern: the message can get too long. Keep the primary line short and put the reason in a note.

Q5. Vote: accept.
Reasoning: The conditions handle my concern from round 1. A redundant `@derive` is not a duplicate, and the diagnostic (Q4) gives the real reason, not a generic "duplicate impl". Limiting it to Eq and Ord stops users from thinking Debug or Hash also come free.
Concern: users may read "implicit derive" and think `@derive(Debug)` is optional too. The spec must give the list of traits in words, near the start of the text.

Q6. Vote: accept.
Reasoning: No variant holds a T, so a bound on T would be an error with no cause the user can see. The rule "fieldless as written" is a test that users can apply by looking at the code.
Concern: rare case; little risk.

Q7. Vote: 7b.
Reasoning: Sorting by a key is the 90% case, so the help names the named method or `sort_by` first. Some users do need a `T: Ord` value with another order (an ordered map key, a generic max). Without the wrapper pattern in the help, they will ask on Stack Overflow how to get it.
Concern: the help text can get long. Show the wrapper only in the explain page, not in the inline help.

Q8. Vote: accept.
Reasoning: The cross-reference in §3.4 fixes the reading that "only three operations exist, so same-enum `<` is not allowed". Putting the rule next to the Eq rule lets users read Eq and Ord together, the same way they learn them.
Concern: none.

Q9. Vote: accept.
Reasoning: It costs one sentence. Users trust the formatter to never change behavior, and this keeps that promise.
Concern: none.

**PLT:**

**PLT ballot, Phase C**

**Q1. Core rule: A**
- **Reasoning:** `<` is defined as `Ord.cmp`, so a type that accepts `<` must be `Ord`, or substitution breaks: an expression that works at the concrete type fails under `[T: Ord]`. A puts every order on a fieldless enum on one source, the tag, so `==`, `<`, `to_int` and the comparison with `Int` agree by construction. B leaves a tag order that the type can use against an `Int` but not against its own values.
- **Concern:** when a fieldless enum gets its first payload, it loses `Eq` and `Ord` at the same time. That is a source break in a non-local place, and the diagnostic must point at the declaration, not only at each `<`.

**Q2. Str-backed enums: accept**
- **Reasoning:** a Str-backed enum is fieldless, so the tag rule applies and the backing strings are not part of `Ord`. One line stops a reader from assuming lexical order.
- **Concern:** users may still expect the strings to set the order, so the spec example should show an enum whose declaration order differs from the order of its strings.

**Q3. Stated guarantee: accept**
- **Reasoning:** because no second instance can exist, the property is a theorem about the language, not a law a user must keep. Stated that way, the compiler and generic code may rely on it.
- **Concern:** the text must not let a reader think it also holds for payload enums, which have no `to_int`.

**Q4. One diagnostic: accept**
- **Reasoning:** a written `impl Eq` and a written `impl Ord` break one rule: a second instance on a type that already has one. One code, with the trait named in the message and the secondary span on the `type` line, explains where the first instance comes from.
- **Concern:** the message must not say "duplicate impl" alone, or users will search for an impl they never wrote.

**Q5. Implicit-derive framing: accept**
- **Reasoning:** one framing gives the duplicate error, the legal redundant derive and the first-payload rule with no extra rules. Limiting it to `Eq` and `Ord` keeps the scope to what was decided.
- **Concern:** later panels may want to add `Hash` to the implicit set. That should go through a vote, not just appear.

**Q6. Generic fieldless enums: accept**
- **Reasoning:** no variant holds a `T`, so neither `Eq` nor `Ord` reads a `T` value. A bound on `T` would be over-constrained and would reject sound code.
- **Concern:** a phantom `T` may later carry meaning (for example, units). Then users who expect `Tag[A]` and `Tag[B]` to be incomparable get that from nominal typing, which already keeps them apart, so I see little risk.

**Q7. Custom order: 7b**
- **Reasoning:** a comparator handles a one-off order. Only the newtype wrapper gives a second order that satisfies `T: Ord` and still keeps coherence, one instance for each type. That is the standard answer in Haskell and Rust, and the help should name it.
- **Concern:** two forms in the help text make it longer, so keep the comparator first and the wrapper to one line.

**Q8. Placement: accept**
- **Reasoning:** same-enum `<` takes `Self` on both sides, so it is `Ord`, not a tag operation. The comparison with `Int` is heterogeneous and stays in §3.4. Putting it next to the Eq rule keeps the two instances together.
- **Concern:** without the cross-reference, readers of §3.4 will look for the same-enum case there and not find it.

**Q9. Formatter: accept**
- **Reasoning:** variant order now has meaning in three places (`to_int`, comparison with `Int`, `Ord`), so a tool that moves variants changes behavior. One sentence makes the tool keep the language's meaning.
- **Concern:** none in my domain. It is a tooling sentence and costs nothing.

**DevOps/Tooling:**

**DevOps/Tooling: Phase C ballot**

**Q1. Vote: A.**
Reasoning: under A, `<` has one meaning, so hover, completion of `.cmp` and bound checks all show the same fact. Under B, enum-vs-Int `<` works while enum-vs-enum `<` fails, and no error message can explain that well. A also turns the ICE in [data-enum `<` ICE bug] into a normal error with a machine-applicable `@derive(Ord)` fix.
Concern: the impl could ship the rule but leave the "first payload added" case without the fix at the `type` line, and then users get a bare "does not implement `Ord`".

**Q2. Vote: accept.**
Reasoning: users will guess that a Str-backed enum sorts by its backing strings, and one spec line stops that bug report. Hover then shows `Ord (implicit: declaration order)` for every fieldless enum.
Concern: someone may later want a lint for "declaration order differs from string order". That lint would be noise.

**Q3. Vote: accept.**
Reasoning: a guarantee the compiler gives needs no lint and no runtime check. Tooling can rely on it, for example to compute sort order from `to_int()`.
Concern: if a later ticket allows a custom order on fieldless enums, this guarantee breaks without anyone noticing, so the spec text must tie the guarantee to the no-impl rule.

**Q4. Vote: accept.**
Reasoning: this is the diagnostic I asked for. It needs the secondary span on the `type` line. Without it, a user looks for an impl they never wrote. One code for Eq and Ord gives `blink explain` one page.
Concern: the impl may reuse a generic duplicate-impl message and drop the secondary span, so the test must check the span and the reason text.

**Q5. Vote: accept.**
Reasoning: it gives the LSP one model, so "go to impl" on `Color: Ord` jumps to the `type` line. The conditions are right: Eq and Ord only, an explicit derive is the same instance, and both instances go away together when the first payload is added.
Concern: users may read "implicit derive" as "also Hash/Debug", so the spec sentence must name the two traits and only those.

**Q6. Vote: accept.**
Reasoning: this matches the decided Eq wording, "fieldless as the declaration is written". Hover must show no `T: Ord` bound, so that nobody adds a useless bound.
Concern: none in my domain.

**Q7. Vote: 7b.**
Reasoning: the help text must lead the user to code that compiles. If generic code needs `T: Ord` with another order, `sort_by` does not satisfy the bound, and help that names only `sort_by` leads the user to a dead end. Put `sort_by` first, because it is the common case.
Concern: help text with two fixes gets long, so keep each fix to one line.

**Q8. Vote: accept.**
Reasoning: same-enum `<` is `Ord`. If §3.4 lists it as a fourth tag operation, the docs show two rules for one operator. A cross-reference is enough.
Concern: none.

**Q9. Vote: accept.**
Reasoning: `blink fmt` must preserve meaning, and variant order is meaning. One sentence locks that in before anyone proposes "sort variants alphabetically".
Concern: none.

**AI/ML:**

aiml, Phase C ballot

**Q1. Vote: A.**
Reasoning: A makes Eq and Ord one fact: fieldless enums compare by tag with no derive, and data enums need a derive or impl. A model that knows the decided Eq rule gets Ord right with zero new decision points. B makes models fail on `Color.Red < Color.Green`, the most common enum comparison, and gives them nothing to choose.
Concern: Models trained on Rust will still write `@derive(Ord)` on fieldless enums. That is harmless, but the docs examples should show the bare form so the habit does not spread.

**Q2. Vote: accept.**
Reasoning: Models will guess that the order comes from the backing strings, as alphabetical sort. One sentence prevents a silent wrong-order bug.
Concern: The line could be missed if it is only in §3.6, so put an example next to the Str-backed enum text as well.

**Q3. Vote: accept.**
Reasoning: A stated guarantee is easier for a model to retrieve and apply than a fact it must derive. Calling it a compiler guarantee, not a user law, tells the reader that nothing can break it.
Concern: None from my domain.

**Q4. Vote: accept.**
Reasoning: One code and one explain page means the rule is learned once. A message that gives the reason and the fix lets an agent repair the code in one step, not by trial and error.
Concern: The help must name the fix (a named key method), not `.to_int()` comparisons, or agents will copy the workaround.

**Q5. Vote: accept.**
Reasoning: The framing is clear only with the stated exclusions. "Implicit derive" alone would make a model assume `Set[Color]` or `Debug` works. With `Eq` and `Ord` named as the whole list, the text is precise.
Concern: Readers may still generalize "implicit derive" to Hash. The text should have one negative example (`Set[Color]` needs `@derive(Hash)`).

**Q6. Vote: accept.**
Reasoning: This follows from "fieldless as written" and adds no rule.
Concern: None.

**Q7. Vote: 7b.**
Reasoning: The order matters most for models: the named method or `sort_by` first is the default, and the wrapper second only for a `T: Ord` bound. That matches my Phase B text. Fixed order with a stated condition is still one decision, not two equal options.
Concern: If the help text shows both with equal weight, agents will reach for the wrapper in one-off sorts and waste tokens.

**Q8. Vote: accept.**
Reasoning: Same-enum `<` is `Ord`, so it belongs with the Eq rule. A cross-reference from §3.4 keeps retrieval working from either entry point.
Concern: None.

**Q9. Vote: accept.**
Reasoning: One sentence protects meaning, and it tells AI-driven refactors that reordering variants is a semantic change.
Concern: None.

**Minimalism:**

**min, Phase C ballot**

**Q1. Core rule**
- **Vote:** A
- **Reasoning:** A copies the 6-0 Eq rule onto Ord, so users learn no new rule. It also removes the compiler's non-Ord `<` special path. Forbidding the written impl means the question of whether Ord must agree with Int cannot come up. B breaks working code and leaves `Color.Red < 1` legal while `Color.Red < Color.Green` is not.
- **Concern:** users may not see that reordering variants of a `pub` fieldless enum changes behaviour (that lint is deferred, correctly).

**Q2. Str-backed enums**
- **Vote:** accept
- **Reasoning:** one line stops a likely misreading, and it adds no rule. It is a stated consequence of "fieldless".
- **Concern:** someone may later ask for a backing-string order; the answer is a `sort_by`, not a variant of Ord.

**Q3. Stated guarantee**
- **Vote:** accept
- **Reasoning:** the guarantee is the reason the impl is forbidden, so the spec should say it once. Writing it as a compiler guarantee and not as a user law keeps the "unspecified results" area out.
- **Concern:** the text may grow into a long list of equivalences; one sentence is enough.

**Q4. Diagnostic**
- **Vote:** accept
- **Reasoning:** it is one concept, so it gets one code. The reason in the message teaches the rule at the point of error, which is cheaper than more spec prose.
- **Concern:** the secondary span and help must not drift into implementation detail in the spec. Keep the spec to what the message says, not how it is built.

**Q5. Implicit-derive framing**
- **Vote:** accept
- **Reasoning:** it turns a special case into the normal duplicate-instance rule. The explicit-derive carve-out keeps the decided Eq behaviour, and the Eq+Ord-only scope stops it from growing into other traits.
- **Concern:** later panels may read "implicit derive" as a precedent to add Hash/Debug the same way; that needs its own vote.

**Q6. Generic fieldless enums**
- **Vote:** accept
- **Reasoning:** it follows from "fieldless as written" with no extra rule. Eq and Ord read the same, so the traits do not split.
- **Concern:** none of substance.

**Q7. Custom order guidance**
- **Vote:** 7a
- **Reasoning:** one canonical way is less surface to teach and to keep in sync between spec and help. A struct wrapper is ordinary Blink, and the spec does not list every program a user can write. I do not object strongly to 7b, because it adds no language surface, only text.
- **Concern:** with 7b, help text grows a second paragraph that most users do not need.

**Q8. Placement**
- **Vote:** accept
- **Reasoning:** same-enum `<` is `Ord`, so it belongs beside the enum Eq rule. Adding a fourth "tag operation" would put back the special path we are removing.
- **Concern:** the §3.4 cross-reference may decay if §3.6 is renumbered.

**Q9. Formatter**
- **Vote:** accept
- **Reasoning:** one sentence, true today, in the tooling section. Variant order is meaning, and the formatter must not change meaning.
- **Concern:** none, provided it stays out of §3.6.

#### AI-first review

Learnability, consistency, generability, debuggability and token efficiency: 5/5 pass. The rule is one sentence that matches the Eq rule; it removes the special non-`Ord` `<` path; `<` on a fieldless enum works with no derive; the internal compiler error becomes a diagnostic with a `@derive(Ord)` fix.

The user signed off on the tally.

### Final Spec

```blink
type Priority { Low  Medium  High }

@derive(Ord)
type Task { p: Priority  id: Int }                     // OK: `Priority` is `Ord`

type Shape { Circle(r: Int)  Sq(s: Int) }

fn biggest[T: Ord](a: T, b: T) -> T {
    if a > b { a } else { b }
}

fn main() {
    let top = biggest(Priority.Low, Priority.High)     // Priority.High
    let o = Priority.Medium.cmp(Priority.Low)          // Greater
    let t = (Priority.Low, 9) < (Priority.High, 0)     // true
    let bad = Shape.Circle(1) < Shape.Circle(2)        // error: `Shape` does not implement `Ord`
}
```

- A fieldless enum is `Ord` by declaration order with no derive. It is the real instance: `.cmp()`, `T: Ord`, tuples and `@derive(Ord)` fields accept it.
- An enum with a payload is `Ord` only through `@derive(Ord)` or a written `impl Ord`. `<` on one with no `Ord` is a normal diagnostic, never an internal compiler error.
- The declaration of a fieldless enum gives `Eq` and `Ord` as an implicit derive, these two traits only. An explicit derive names the same instance and is legal. The first payload variant removes both.
- A written `impl Ord` (or `impl Eq`) on a fieldless enum is a compile error. One diagnostic code covers both; the message gives the reason and points at the `type` line. The inline help names a named key method with `sort_by`; the explain page adds a struct wrapper with its own `impl Ord` for a `T: Ord` bound.
- For a fieldless `E`, `a < b` exactly when `a.to_int() < b.to_int()` (also `<=`, `>`, `>=`, `cmp`). The compiler gives this guarantee.
- A Str-backed enum sorts by declaration order, not by its backing strings.
- `type Tag[T] { A  B }` is `Eq` and `Ord` with no bound on `T`.
- §3.4 *Tag Operations* keeps its three operations and points to §3.6 for same-enum comparison.
- `blink fmt` never reorders variants (§8.8).
- Out of scope: conditional `Ord` for `Option`/`Result`; a lint for reordering variants of a `pub` fieldless enum; adding `Hash` or any other trait to the implicit derive, which needs its own vote.
