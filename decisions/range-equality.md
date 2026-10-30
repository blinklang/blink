[< All Decisions](../DECISIONS.md)

# Range Equality: What `==` Compares on `Range[T]` — Design Rationale

**Gap:** §2.19 shows `let ok = r == 0..3` as valid code, so `Range[T]` has `==`. The spec did not say what `==` compares on two ranges, which bound `T` needs, or which other traits `Range[T]` has. Two readings were open: compare the start, the end and the kind (`..` or `..=`), or compare the values the range holds. A third reading gave `Range` no `==`.

**Result:** 6-0 on every question (Q1 and Q2a–Q2d). Phase A split 5 to 1 on Q1 (Web/Scripting proposed comparing the values). Web/Scripting moved to the structural rule in Phase B, and the Phase C vote was 6-0. No Phase D (all votes were unanimous). 

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in independent-proposal → debate → vote rounds. The excerpts below are verbatim.

#### Phase A — Independent proposals

Five seats put the structural rule first (option 1A). Web/Scripting put comparing by values first (option 1B). Every seat listed "no `==` on `Range`" (option 1C) as a fallback; none ranked it first.


- **Systems (1A):**
  > `==` compares the start, the end and the inclusive flag, each with `T`'s own `==`. Nothing else. No emptiness check, no element walk.

- **Systems (1A), on the cost:**
  > **What it compiles to.** Per monomorphized `T`, one inline function: `a.lo == b.lo && a.hi == b.hi && a.incl == b.incl`. For `Range[Int]` that is two 64-bit compares and one byte compare, branch-free after -O2, no loop, no call.

- **Web/Scripting (1B):**
  > Two ranges are `==` when they hold the same values. This is the rule the spec already uses for `Set` and `Map`: membership, not how the value was built.

- **Web/Scripting (1B), on the cost:**
  > The cost: two rules (discrete vs. not) in the compiler. Users never see the split for `Int`, and almost nobody writes `Range[Float]` today. If the panel will not accept a split, use the structural rule only for non-iterable `T` and accept that it is a corner.

- **PLT (1A):**
  > "Same elements" works only if T has a successor function. `Ord` gives no successor. For `Range[Float]` or `Range[Str]` (both well-formed, since Float and Str are `Ord`), the "elements" of `0.0..1.0` are not defined, so (b) can not decide `0.0..1.0 == 0.0..=0.5`. To make (b) sound you must add a hidden `Step` trait and split `Eq` into "Eq by elements when T: Step, else ...". That is two meanings for one operator, chosen by T. It does not compose.

- **PLT (1A), on the choice:**
  > (b) also breaks substitutivity (Leibniz: `a == b` implies `f(a) == f(b)` for every observer `f`). The day Range gets `.end()`, `.is_inclusive()`, or `Debug` that prints `0..3` vs `0..=2`, two `==` values give different results. With (a), `==` is a congruence for every observer we may add later. You can add (b) later as a method (`a.same_elements(b)`); you can not take (b) back out of `==`.

- **DevOps/Tooling (1A):**
  > 1. **Debug agrees with Eq (§3.6.1).** This rule decides the question for me. With element equality, `0..3 == 0..=2` is true, so the two `debug()` strings must be the same. Then `debug()` cannot print what the user wrote. It must print a normal form (`0..3` for `0..=2`), and every empty range must print the same text (`0..0`?). An `assert_eq` failure that prints `0..0` for the user's `5..3` hides the bug the test found. Structural equality lets `debug()` print what the user typed, and the law holds with no extra rule.

- **AI/ML (1A):**
  > `a == b` is true when the starts are `==`, the ends are `==`, and both are `..` or both are `..=`. Nothing else.

- **AI/ML (1A), on training data:**
  > - **Training data agrees.** Rust is the main source of `..`/`..=` code. There `0..3 == 0..=2` does not compile (two types) and `0..0 != 1..1`. Swift is the same. A model brings "structural" by default; an element rule would be a silent case where its prior is wrong. A type error would at least be loud; a wrong `true` is not.

- **Minimalism (1A):**
  > A range is the three things you wrote: start, end, and `..` or `..=`. `==` compares those three.

- **Minimalism (1A), on the promise:**
  > - It is a promise we cannot take back. Structural can grow a `.same_elements()` method later. Element equality cannot shrink back to structural without breaking code.


Phase A found three options and these shared points: every `Range[T]` is `Eq` with no bound beyond `Ord` ("always", as the `Set` row says); no `Hash`; no `Ord`. Four seats (Systems, Web/Scripting, DevOps/Tooling, AI/ML) named `Debug` with the source form. AI/ML named `Clone`. DevOps/Tooling and AI/ML said no `Display`. The moderator made these four parts of the vote (Q2a–Q2d).

- *Option 1A:* `==` compares the start, the end and the kind.
- *Option 1B:* `==` compares the values the range holds; for a `T` with no next value, both empty, or same start, end and kind.
- *Option 1C:* `Range` has no `==`.

#### Phase B — Debate highlights

Round 1. The moderator posted the option space and the facts. Web/Scripting moved from 1B to 1A, and dropped 1C. The reason it gave is below. The other five held 1A.


- **Web/Scripting (moves 1B → 1A):**
  > **Q1: I move from 1B to 1A (structural).** I drop 1C too: devops is right that a test must be able to `assert_eq` a returned range.
  >
  > What moved me is devops:
  > > "With element equality, `0..3 == 0..=2` is true, so the two `debug()` strings must be the same. Then `debug()` cannot print what the user wrote."
  >
  > The spec's *Debug agrees with Eq* rule forces this choice. Python can break that rule (`range(5, 3) == range(0)` is `True` and the two reprs differ), but Blink cannot. A test failure that prints `0..0` for the user's `5..3` costs more Stack Overflow questions than one surprising `false`. The second reason is the `Range[Float]` split. I proposed it myself, and it puts two rules behind one operator. I hold that the Python/Kotlin users who expect `true` are real. But 1A gives them a loud, readable failure (`left: 0..3, right: 0..=2`), not a silent wrong answer.

- **DevOps/Tooling, to Web:**
  > **To web (W1).** W1 says both "`r == 0..=2` // true" and "`Debug` prints the source form: `0..3`, `0..=2`". §3.6.1 forbids that pair. Equal values must give the same `debug()` text. W1 must choose one:
  > - normalized `debug()`. Then `assert_eq(f(), 5..3)` prints `left: 0..0, right: 0..0` and the user cannot see which range came from where; or
  > - source-form `debug()` and a broken law. Then the language breaks a law it defines, in the stdlib, on day one.
  >
  > 1A keeps the law and lets the failure message show the fix: `left: 0..3, right: 0..=2`.
  >
  > > "Blink ranges have no fields, so there is nothing structural for a user to see."
  >
  > `debug()` shows it, and so does each `assert_eq` failure. The user sees `..` against `..=` in the output, so the `false` is not silent.

- **PLT, on the split in 1B:**
  > My objection is the split itself. Whether `T` "has a next value" is not a trait in Blink. It would be a list of types that the compiler keeps closed. A user type that implements `Ord` and has a clear successor (`type Day`) falls on the structural side. Nothing in the user's code can move it to the other side. So in
  >
  > ```blink
  > fn same[T: Ord](a: Range[T], b: Range[T]) -> Bool { a == b }
  > ```
  >
  > the meaning of `==` depends on which `T` mono picks. No bound in the signature shows the choice. That is ad hoc overloading behind a uniform bound.

- **Systems, on generic code:**
  > Users see it in generic code. `fn same[T: Ord](a: Range[T], b: Range[T]) -> Bool { a == b }` has no single meaning under 1B. Mono must pick the rule per `T` with a "has a next value" test that no trait in the spec expresses. That is a hidden compiler-known `Step` trait, and it governs one operator only.

- **AI/ML, on the cost of a wrong guess:**
  > web also says Python and Kotlin "agree". They agree only for integer ranges with a step, and Kotlin has no `..`/`..=` pair at all (`until` builds a first/last pair). Blink copied Rust's `..`/`..=` syntax, and models write that syntax with Rust habits. Under 1B the Rust habit gives a silent wrong answer (`true` where the model expects `false`); under 1A the Python habit gives a `false` that `assert_eq` output explains in one line. A loud wrong guess beats a silent one.

- **Minimalism, on growth:**
  > **To web:** "a later fix to W1 changes what running code prints." This is an argument to decide now, not an argument for 1B. Of the two, only 1A can grow: a `.same_elements(other)` method can come later with no break. 1B cannot shrink back into 1A.


The moderator checked these facts before Phase B:

- Kotlin: `IntRange.equals` compares `first` and `last` and treats all empty ranges as equal. So `(0 until 3) == (0..2)` is `true`. PLT and Web/Scripting corrected their Phase A wording on this point in round 1.
- Python 3.3+: `range` `==` compares as sequences. `range(0, 3) == range(0, 3, 1)` and `range(5, 5) == range(2, 0)` are `True`.
- Rust: `Range` and `RangeInclusive` are different types. `PartialEq` on each is structural. `Hash` is implemented and `Ord` is not.

All six replies ended `STABLE: ready to vote`.

#### Phase C — Final vote


- **Q1: What `==` compares on two ranges.** (6-0 for 1A)
  - *Option 1A:* the start, the end and the kind (`..` or `..=`).
  - *Option 1B:* the values the range holds.
  - *Option 1C:* `Range` has no `==`.
  - **Systems:** 1A. — For each `T` after mono, structural `==` is one inline function with two `T` compares and one flag compare. It has no branch, no loop and no successor step, and its cost does not depend on the range length. It has one meaning for every `T` that `Range[T: Ord]` admits, `Float` included, so generic code needs no hidden "has a next value" trait to choose a rule. It also agrees with the stored bits, so a structural `Hash` stays a cheap option for later. *Concern:* Users who come from Python or Kotlin will expect `(0..3) == (0..=2)` to be `true`, and they will file it as a bug. The spec needs an example that shows `false`, plus a pointer to a later `same_elements` method or to comparing collected lists.
  - **Web/Scripting:** 1A. — The *Debug agrees with Eq* rule decides it. Under 1B, `debug()` must print a normal form, so an `assert_eq` failure would show text the user never wrote. That costs more confused questions than one surprising `false`. 1A also gives one rule for every `T`. A JS or Python dev learns it from one failure message (`left: 0..3, right: 0..=2`). *Concern:* Python and Kotlin users will expect `0..3 == 0..=2` to be `true`. The spec example and the `llms` Gotchas list must show it as `false` and say "collect both sides to compare elements", or the question comes back as a bug report.
  - **PLT:** 1A. — 1A gives one typing rule for every well-formed `Range[T]`: `impl[T: Ord] Eq for Range[T]`. It is a congruence for every observer the language has (`Debug`) or may add (`.start`, `.end`), so the *Debug agrees with Eq* law holds with no normal form. 1B needs a successor that `Ord` does not supply. Without a public `Step` trait, the meaning of `==` in a generic function changes with the type that mono picks, and no bound shows it. Element equality can come later as a method; it can not later leave `==`. *Concern:* a later `Step` trait or `.len()` may tempt someone to "fix" `==` to element equality. That is a silent change to what running code prints, so a later panel must treat it as a break, not a refinement.
  - **DevOps/Tooling:** 1A. — 1A is the only option that keeps §3.6.1 (*Debug agrees with Eq*) and lets `debug()` print what the user wrote. When `assert_eq` fails, the output then shows the fix: `left: 0..3, right: 0..=2`. The rule is the same for every `T`, so LSP hover, the docs and the error catalog each need one line and no new diagnostic. 1C adds errors that no single edit fixes (`assert_eq` on a returned range, `@derive(Eq)` on a struct that holds one). *Concern:* A user from Python or Kotlin expects `(0..3) == (0..=2)` to be true. Unless the spec shows that exact line, with a note that `..` and `..=` are compared, the user files a bug.
  - **AI/ML:** 1A. — Under 1A, a model needs no new rule: `==` acts as `@derive(Eq)` does on `{ start, end, inclusive }`, as `Option` and `Result` already do. 1B adds three facts (treat `..=` as `..`, all empty ranges are equal, a different rule when `T` has no next value) and breaks *Debug agrees with Eq*. Models write `..`/`..=` with Rust habits, and 1A matches them. Where a Python habit is wrong, `assert_eq` prints `0..3` vs `0..=2`, so the failure is loud and the fix is plain. *Concern:* Users from Python or Kotlin will expect `(0..3) == (0..=2)` to be true. The spec needs a worked example of that exact line printing `false`, so models learn the rule from the spec and not from Python training data.
  - **Minimalism:** 1A. — 1A has one rule for every `T`, takes O(1) time, and is exactly what `@derive(Eq)` gives a struct of start, end and kind, so users learn nothing new. 1B needs two rules, one for types with a next value and one for types without, and it forces `Debug` to print a normal form. 1C makes an exception to "values are comparable" and blocks `@derive(Eq)` on structs that hold a range. 1A is also the only option that can grow later with no break, because a `.same_elements()` method can come later. *Concern:* Python and Kotlin users will expect `(0..3) == (0..=2)` to be `true`. The spec needs an example that shows `false` and names the cause, or the same question comes back as a bug report.

- **Q2: The other traits of `Range[T]`.** (6-0 on each part: all six seats Agreed)
  - *Q2a:* every `Range[T]` is `Eq` (`Range[T: Ord]`, `Ord: Eq`); no extra bound on `T`.
  - *Q2b:* no `Hash`, no `Ord`, no `Display`.
  - *Q2c:* `Debug` when `T: Debug`, printing the source form.
  - *Q2d:* `Clone` when `T: Clone`.

#### Phase D

Not triggered. Every question passed 6-0.

### Facts From Other Languages

- Kotlin: `IntRange.equals` compares `first` and `last`, so all empty ranges are equal and `(0 until 3) == (0..2)` is `true`.
- Python: `range` compares as sequences, so `range(0, 3) == range(0, 3, 1)` and `range(5, 5) == range(2, 0)` are `True`. The two sides print differently.
- Rust: `Range` `PartialEq` is structural. `Hash` is implemented. There is no `Ord`.

Kotlin and Python ranges hold integers with a step, so each has a next value. `Range[T: Ord]` in Blink also holds `Float` and `Str`, which have none.

### Concerns Carried Into the Spec

Every seat gave the same Concern: a reader from Python or Kotlin expects `(0..3) == (0..=2)` to be `true`. The spec shows that exact line with the result `false`, says that `==` compares the kind, and shows how to compare the elements (collect both sides into lists). PLT's Concern: a later `Step` trait or `.len()` may tempt someone to change `==` to compare elements. That change would alter what running programs print, so a later panel treats it as a break. Element equality, if wanted, comes as a separate method.

### Final Spec

```blink
@derive(Eq, Clone, Debug)
type Window { span: Range[Int] }

fn same[T: Ord](a: Range[T], b: Range[T]) -> Bool {
    a == b                              // compiles: T: Ord gives T: Eq
}

fn main() {
    let a = (0..3) == (0..=2)           // false: different kind
    let b = (5..3) == (0..0)            // false: both empty, but the bounds differ
    let c = (0..3) == (0..3)            // true
    io.println((1..=4).debug())         // 1..=4
}
```

- `==` on two ranges compares the start, the end and the kind. It does not compare elements and it does not test for an empty range.
- `Range[T]` is `Eq` for every `T` it admits. The *Container Equality* table row says "always".
- `Range[T]` is `Debug` when `T: Debug` and `Clone` when `T: Clone`. It has no `Hash`, no `Ord` and no `Display`.
- `debug()` prints the source form. This keeps *Debug agrees with Eq* (§3.6.1).
- The §2.19 line `let ok = r == 0..3` stays valid.
- Spec: §2.10 *Ranges* (02_syntax.md), §3.6 *Container Equality*, *Hash Contract and Seeding* (03_types.md), §3.6.1 *Clone Semantics*, *Debug vs Display*, *Container Debug Rendering* (03_types.md).
