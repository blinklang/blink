[< All Decisions](../DECISIONS.md)

# Float Total Order Re-audit — Design Rationale

A batch of re-audits reopened earlier votes under one principle: "match LLM priors unless the deviation prevents a bug class." This one asked about Float equality and order. The earlier panel (5-0) gave `Float` a total order: `NaN == NaN` is true, NaN sorts greater than all other values, and `-0.0 == 0.0` is true. IEEE 754, and C, Rust, Python and JavaScript with it, make every comparison with NaN false except `!=`. The ticket asked the panel to keep the total order only if it prevents a bug class, and otherwise to use IEEE equality with a separate total-order compare.

This decision keeps the total order. It adds the warning `FloatSelfComparison` (W0707), a "Differences from IEEE 754" block in §3, and the built-in method `is_nan` on `Float` and `F32`.

Facts before the vote:

- `-0.0 == 0.0` is already the IEEE answer. The only differences from IEEE 754 are the NaN results of `==`, `!=`, `<`, `<=`, `>` and `>=`.
- Container equality uses a same-pointer shortcut that is valid only because Float `Eq` is reflexive ([Container Equality](container-equality.md)).
- `x.ieee_eq(y)` is IEEE equality ([Float ieee_eq](float-ieee-eq.md)). [Float Bits](float-bits.md) gives `to_bits`, `from_bits` and `is_sign_negative`. W0706 warns on a written `-0.0` operand ([Negative Zero Comparison](negative-zero-comparison.md)).
- Blink has no index operator: `xs[1]` is `NoIndexOperator` (E0313), and element access is the call `xs.get(i)`.

After the vote, the moderator found that the spec did not define `is_nan`, which the voted help text names. A second round with the same six seats closed that gap ("Follow-up: the NaN test", below).

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in independent-proposal → debate → vote rounds. Quoted text is each panelist's own, verbatim. Local ticket IDs are replaced with "[this ticket]".

All six seats proposed to keep the total order in Phase A. The dedupe listed the lint (operators, operands, fix mode, level, name, explain text), IEEE ordered predicates (plt), and the spec text for the differences as variations for Phase B.

#### Phase A — Independent proposals

- **Systems:**

> Sys (Systems) Phase A reply on [this ticket], Float total order. I prefer Proposal A: keep the rule and add one lint.
>
> **Facts I checked**
> - `bootstrap/runtime_core.h:3129` `blink_float_eq` and `:3138` `blink_float_cmp` are two NaN branches in front of C `==`/`<`. Code cost: x86 `ucomisd` already sets PF on unordered, so total `==` is `ZF&!PF | (PF & b!=b)`, about one extra branch that the CPU predicts well. GCC still vectorizes the loops (`cmpunordpd` plus a blend). The cost is real but small. It is not a reason to drop the rule.
> - -0.0 == 0.0 is already IEEE. The only deviations are about NaN.
> - No lint exists today for `x != x` / `x == x` on Float (I searched sections/ and found no hit).
>
> **Bug classes the current rule prevents (all real and well documented)**
> 1. **Sort UB / non-termination.** C++ `std::sort` with IEEE `<` on data that holds a NaN breaks strict weak order. Old libstdc++ read out of bounds. Blink's `sort` contract ("returns a permutation and does not panic") gets that for free for Float only because `cmp` is total. Under IEEE `Ord`, Float sort output turns unspecified for any NaN input.
> 2. **Container equality depends on aliasing.** Python: `x=[nan]; x==x` is True, but `[nan]==[nan]` is False. Blink codegen uses a same-pointer shortcut (decisions/container-equality.md), and that shortcut is valid only because Float `Eq` is reflexive. With IEEE `==` we must drop the shortcut (an O(n) walk on every aliased compare) or ship the Python bug.
> 3. **assert_eq / derived Eq / contains.** `assert_eq(f(x), expected)` where both are NaN, `@derive(Eq)` structs with a NaN field never equal to themselves, and `xs.contains(nan)` / `index_of` that never find an element that is in the list.
> 4. **Generic code lies.** `max[T: Ord]`, `dedup`, binary search, and `Set`-like code written over `T: Ord` all assume the laws. Under mono with no specialization, every generic instantiation at Float inherits the broken laws. We cannot special-case it.
>
> So the deviation prevents a bug class, and under the re-audit principle we keep it.
>
> **The hazard we create (do not hand-wave it)**
> - (a) Ported `if x != x { ... }` as a NaN test is now always false, so NaN gets through silently.
> - (b) Ordered compares: `NaN > hi` is **true** in Blink and false in IEEE. Ported clamp code changes behavior:
> ```
> fn clamp(x: Float, lo: Float, hi: Float) -> Float {
>     if x > hi { return hi }    // Blink: NaN -> hi. C/Rust/Python: NaN passes through
>     if x < lo { return lo }
>     x
> }
> ```
> (b) is the worse of the two because it hides bad data. But IEEE makes the mirror case true too: `if x <= hi { ok }` lets NaN pass. Each choice loses half the ported idioms. Neither prevents NaN bugs. Only `is_nan()` at the boundary does that.
>
> **Proposal A (preferred): keep total order, add W07xx `FloatSelfComparison`**
> - Warn when both operands of a Float/F32 `==`, `!=`, `<`, `<=`, `>`, `>=` are the same place expression as written (`x != x`, `a.b == a.b`). Help: "always `true`/`false` in Blink, because `NaN == NaN`; use `x.is_nan()`". This catches (a), the main port hazard, at zero runtime cost. It follows the W0704/W0706 "read the expression as written" shape.
> - Spec: add one *Porting from IEEE* paragraph to *Float Total Ordering* that shows the clamp example and names `ieee_eq` and `is_nan()`.
> - Runtime and codegen stay as they are. Cost is a few branches per compare, with no ABI change.
>
> **Proposal B (rejected): IEEE operators, separate `total_cmp`**
> ```
> let mut xs = [3.0, 0.0 / 0.0, 1.0]
> xs.sort_by(Float.total_cmp)   // xs.sort() no longer compiles
> ```
> Float would have to drop `Eq`/`Ord`, as in Rust (PartialEq/PartialOrd only). If Float kept `Eq` with IEEE semantics instead, it would break the stated Eq laws, the container pointer shortcut, and `sort`. Dropping `Eq`/`Ord` means a `PartialEq` trait split (a new trait tier and new desugar rules), and that breaks `List[Float] ==`, `assert_eq` on Floats, and `@derive(Eq)` on every struct with a Float field. LLMs know Rust's `f64` friction well: `sort()` on `Vec<f64>` is one of the most common Rust compile errors. So B matches C/Python priors on `==` but brings in Rust's worst Float friction. Cost: large churn, and no new safety.
>
> **Proposal C (rejected): split concrete and generic**
> Concrete `a < b` on Float emits IEEE, and `Ord.cmp` stays total for generics. Mono makes this cheap, but `fn lt[T: Ord](a: T, b: T) -> Bool { a < b }` would give a different answer at Float than inline `a < b`. That breaks "operators desugar to trait calls" and makes codegen depend on the call path. I refuse it: an inline call and a generic call must give the same result.
>
> **Cross-language**
> Rust: `f64::total_cmp` orders by bits (`-0.0 < 0.0`, negative NaN first). Ours is coarser and simpler. Java: `Double.equals` / `compareTo` are total (NaN == NaN, NaN greatest, as in Blink, but -0.0 < 0.0), and `==` is IEEE. Java's split is a known source of autoboxing bugs. Python: the aliasing bug described above. Zig/C: IEEE only, and sort is the caller's problem.
>
> **Vote preference:** A. Keep `NaN == NaN`, NaN greatest, and `-0.0 == 0.0`. Add `FloatSelfComparison` and a porting note. Second choice: none. I would vote against B and C.

- **Web/Scripting:**

> Web/Scripting seat, Phase A on [this ticket] (Float total order). My pick: keep the total order (Proposal 1) and add a self-compare diagnostic.
>
> ## Facts I checked
> - bootstrap/runtime_core.h:3129 `blink_float_eq` and :3138 `blink_float_cmp` match the brief: NaN == NaN, NaN is the greatest value, -0.0 == 0.0 (that last one is already IEEE).
> - Probe with gen1: `let x = 0.0 / 0.0; if x != x {..}` takes the else branch with NO diagnostic, and `1.0 < x` prints `true`. So the IEEE idiom `x != x` fails silently today. No lint covers it (I found nothing in sections/ or DECISIONS.md).
>
> ## What the 90% dev hits
> A JS/Python dev almost never writes `NaN == NaN` on purpose. They hit NaN by accident: a bad parse, 0/0, a missing value. Then three things happen:
> 1. **Sort breaks.** JS `[3, NaN, 1].sort((a,b) => a-b)` gives order that depends on the engine. Python `sorted([3, nan, 1])` gives `[3, nan, 1]` — unsorted, no error. C++ `std::sort` with NaN is UB. This is a top Stack Overflow topic in every one of those languages.
> 2. **Test asserts fail on equal data.** `assert_eq(result, expected)` where both hold NaN fails in IEEE. Python `[nan] == [nan]` is True only because of the identity shortcut; `[float("nan")] == [float("nan")]` is False. Nobody can explain that in 5 minutes.
> 3. **`contains`/`index_of`/dedup miss NaN.** JS had to add `Array.includes` with SameValueZero (NaN equals NaN, -0 equals +0 — exactly Blink's rule) because `indexOf(NaN)` returned -1. JS already went where Blink is.
>
> Those are real bug classes, and the current rule prevents all three. That passes the "keep only if it prevents a bug class" test.
>
> ## Proposal 1 (preferred): keep total order, add W07xx FloatSelfCompare
> Keep `==`/`<`/Ord.cmp as specified. Add a warning when both operands of a Float `==` or `!=` are the same expression (same local, same field path). Its message says the result is always constant and names `x.is_nan()`.
>
> ```blink
> fn clean(xs: List[Float]) -> List[Float] {
>     let mut out = []
>     for x in xs {
>         if x != x {          // warning[FloatSelfCompare]: `x != x` is always false for Float;
>             continue         //   NaN == NaN in Blink. Use `x.is_nan()`.
>         }
>         out.push(x)
>     }
>     out
> }
>
> fn clean_fixed(xs: List[Float]) -> List[Float] {
>     xs.filter(fn(x) { !x.is_nan() })
> }
> ```
>
> Tradeoffs: this fixes the one prior that really hurts — the `x != x` NaN test that every C/JS port and every LLM writes. It is silent today; a lint turns a silent wrong branch into a pointer to the fix. Cost: one lint, no runtime change, no migration.
>
> Open risk I flag but accept: `x > max` is true for NaN (rejects NaN — good), but `x >= min` is also true for NaN (accepts NaN — IEEE would reject). Range-check code ported from JS lets NaN through on the lower bound. I think that is rare next to the sort bug, and a range check of the form `x >= lo && x <= hi` still rejects NaN because `x <= hi` is false. Worth one example line in the spec's *Float Total Ordering* section.
>
> Cross-language: JS SameValueZero (`includes`, `Map`, `Set`) = Blink's `==`. Java `Double.equals`/`compareTo` = NaN equal and last (but splits -0.0/0.0). Kotlin same as Java for boxed Double. So "NaN equals NaN, sorts last" is a familiar prior for anyone who has used collections in those languages.
>
> ## Proposal 2 (reject): IEEE operators, Float loses Eq/Ord (Rust model)
> ```blink
> let xs = [3.0, 1.0]
> xs.sort()                      // error: Float does not implement Ord
> xs.sort_by(fn(a, b) { a.total_cmp(b) })
> ```
> This is Rust's most-asked float question ("why can't I sort a Vec<f64>"). It also breaks `@derive(Eq)` on any struct with a Float field, `assert_eq` on Floats, `List[Float].contains`, and container `==`. For the web dev this is a wall on day one. Blink has no PartialEq/PartialOrd, and adding them is a large spec change for a 10% case.
>
> ## Proposal 3 (reject): IEEE operators, total-order traits (Java model)
> Make `==`/`<` IEEE but keep `Eq`/`Ord` impls total. This breaks the decided rule that operators desugar to trait calls, so `a == b` and `[a] == [b]` give different answers. Java's `==` vs `.equals` split is itself a famous SO question. Worst of both worlds for learnability.
>
> ## Not proposed
> A full IEEE totalOrder (−0.0 < 0.0, NaN ordered by sign bit) would make `-0.0 == 0.0` false. That adds a deviation, not removes one, and every `x == 0.0` check after a multiply by a negative number breaks. No.
>
> ## Summary
> Preferred: Proposal 1. Keep the rule — it prevents the sort, assert and contains bug classes that JS, Python and C++ users hit daily. Add a FloatSelfCompare warning so the `x != x` NaN idiom fails loudly, and add one spec example for the `x >= lo` range-check case.

- **PLT:**

> PLT seat, Phase A: keep the total order for `==` and `Ord` (P1), add explicit IEEE ordered predicates (P2), and add a lint for the NaN self-test idiom (P3).
>
> **Facts I checked.** The deviation is narrow. `blink_float_eq` and `blink_float_cmp` (bootstrap/runtime_core.h:3129-3145) differ from C only on NaN operands. `-0.0 == 0.0` is IEEE already, so the title overstates it. Several spec rules depend on NaN == NaN:
> - the Eq laws (03_types.md:3931): "Float obeys them because NaN == NaN"
> - the Ord/sort laws (:3939)
> - the container-equality same-pointer shortcut (decisions/container-equality.md:75, :291)
> - the parse/display round-trip law (:4802)
> - JsonValue `==` (:5243)
>
> **The typing question.** Operators desugar to trait calls. `trait Ord: Eq` and `Ord.cmp` returns a total `Ordering`. With monomorphization, `a == b` at `Float` and `eq[T: Eq](a, b)` at `T = Float` must call the same impl, or generic code means something different from the same code written for one concrete type. That leaves exactly three sound designs:
>
> 1. Float's `Eq`/`Ord` is a true equivalence and total order (current).
> 2. Float is not `Eq`/`Ord`. Add `PartialEq`/`PartialOrd` and route the operators through them (Rust).
> 3. Float's operators skip the traits (IEEE), but its trait impls are total. This breaks the desugaring rule, so it is not sound in the sense we need.
>
> Haskell's `instance Eq Double` is IEEE and breaks the class laws. As a result `sort`, `nub` and `Data.Map` silently misbehave on NaN, which is a known wart. OCaml does design 3: `nan = nan` is false while `compare nan nan = 0`, so `List.mem` and `List.assoc` disagree with `Set.Make(Float)`. That is a known foot-gun. Rust does design 2 and pays for it everywhere: you cannot `.sort()` a `Vec<f64>`, and `f64` has no `Eq`, which users route around with `total_cmp`. Koka and Agda keep primitive float compares outside lawful classes.
>
> **The bug class it prevents (the re-audit test).** Law-dependent generic code silently gives wrong answers on NaN. Under IEEE:
> - `xs == xs` is false for a `List[Float]` that holds NaN, and the codegen shortcut makes the answer depend on aliasing.
> - `xs.contains(x)` is false when `x` comes from `xs` itself.
> - `xs.sort()` falls back to the spec's "unspecified permutation" clause, so you get garbage without a panic.
> - `max(a, b)` stops being commutative.
> - derived `Eq`/`Ord` on any struct with a Float field breaks its laws, and every container of that struct breaks with it.
>
> This is a real bug class, not a style choice. Python has it (`sorted([3, nan, 1])` returns unsorted data), and so do C++ (`std::sort` with NaN is UB) and Java (`Double.compare` and `==` disagree). The current rule removes it by construction.
>
> **P1: keep the rule.** This is my preferred option.
> ```
> fn main() {
>     let nan = 0.0 / 0.0
>     let xs = [3.0, nan, 1.0]
>     assert(xs == xs)                 // reflexive, so containers are lawful
>     assert(xs.contains(nan))
>     let mut ys = xs
>     ys.sort()                        // [1.0, 3.0, NaN], deterministic
>     assert(!nan.ieee_eq(nan))        // IEEE stays one name away
> }
> ```
> Tradeoff: ported code that relies on IEEE NaN behaviour changes meaning. The sharpest case is the C idiom `x != x`, which is now always `false`. That is exactly what P3 addresses.
>
> **P2: add IEEE ordered predicates.** Today only `ieee_eq` exists, so a port of IEEE code that uses `<` has no direct target. Add `ieee_lt`, `ieee_le`, `ieee_gt` and `ieee_ge`, each false when either operand is NaN, plus `partial_cmp() -> Option[Ordering]` (None if either is NaN). These are plain methods, not traits, so they leave the trait hierarchy alone.
> ```
> fn in_range(x: Float, lo: Float, hi: Float) -> Bool {
>     x.ieee_ge(lo) && x.ieee_le(hi)   // C semantics, written on purpose
> }
> ```
> Cross-language: Rust has `partial_cmp` and `total_cmp`, and IEEE 754-2008 names `compareQuietLess` and the rest. Under P1 these are the only extra surface the port story needs.
>
> **P3: lint the NaN self-test.** `x != x` and `x == x` with the same Float place on both sides always fold to `false`/`true` under P1. A ported NaN check therefore becomes dead code with no error. Add a warning, a sibling of W0706: "Float self-comparison is constant; use `x.is_nan()` or `x.ieee_eq(x)`". This catches the one porting hazard that P1 adds and that has a syntax signature. Low cost and sound.
>
> **Rejected: P4, the Rust split (design 2).** It needs new `PartialEq`/`PartialOrd` traits, re-plumbs operator desugaring, and makes `List[Float].sort()`, `contains`, derived `Eq` on Float structs, and `assert_eq` on Floats all type errors or all IEEE-unlawful. It also reopens the container-equality decision. Its cost is much larger than the porting friction it fixes, and LLMs write `v.sort()` on floats all the time, which Rust rejects. It does not match LLM priors better than P1.
>
> **Rejected: P5, IEEE operators with total trait impls (design 3).** It is unsound under our desugaring and monomorphization rules. The same expression would change meaning depending on whether `T` is concrete, which is OCaml's foot-gun built in on purpose.
>
> **One honest note on ordered compares.** NaN-as-greatest also changes guards. Under IEEE, `if x > limit { alarm() }` stays silent for NaN; under P1 it fires. `if x < floor { alarm() }` is silent under both. I count the first as fail-loud, a small plus, and the second as neutral. Neither is a reason to break the laws.
>
> **Vote: P1 + P2 + P3.** Keep the total order (it prevents the law-violation bug class in generic and container code), add the `ieee_*` ordered predicates and `partial_cmp`, and add the self-comparison lint. Also fix the ticket title: `-0.0 == 0.0` is not a deviation.

- **DevOps:**

> ## DevOps/Tooling seat: Phase A on [this ticket] (Float total order)
>
> **Facts I checked**
> - `build/blink run` on a scratch file gives: `x != x` is `false` for NaN, `nan > 1000000.0` is `true`, `[3.0, nan, 1.0].contains(nan)` is `true`, and `sort()` puts NaN last. This matches the spec.
> - No lint fires on `x != x`. I found no self-comparison check in `src/` or `sections/`. So when someone ports the classic NaN test, it becomes dead code and the compiler says nothing.
> - The E1400 text at `src/typecheck.bl:9977` gives "NaN-inequality" as the hazard. Under the current rule NaN *is* equal to NaN, so the message is stale. The real hazards are `-0.0`/`0.0` and NaN payload bits.
> - Side finding (outside this ticket, but it matters for diagnostics): interpolation `"{x}"` printed NaN as `-nan` and `1.0` as `1`. The Float Text Form says `NaN` and `1.0`. An `assert_eq` failure on Floats would show this wrong text.
>
> ### Proposal A (preferred): keep the total order, and make every deviation loud
>
> It prevents this bug class: **NaN breaks generic code without any error**. With IEEE `==`:
> - `xs.contains(nan)`, `index_of`, `dedup` and `assert_eq(nan, nan)` all return wrong answers.
> - `@derive(Eq)` on any struct with a Float field stops being reflexive. Then the container same-pointer shortcut gives `l == l` true while comparing the same elements one by one gives false. A user cannot debug that.
> - `sort()` gets a comparator that is not a total order.
>
> All of these are silent. None gives a diagnostic. The total order turns them into defined behaviour.
>
> The cost is ported code that relies on IEEE NaN behaviour. I want to close that gap with diagnostics, not with semantics:
>
> ```blink
> fn check(x: Float) -> Result[Float, Str] {
>     if x != x {                 // warning[FloatSelfComparison] W07xx
>         return Err("nan")
>     }
>     if !(x >= 0.0) {            // NaN passes here; IEEE code expected it to fail
>         return Err("negative")
>     }
>     Ok(x)
> }
> ```
>
> ```
> warning[FloatSelfComparison]: `x != x` is always false
>   --> check.bl:2:8
>    |
>  2 |     if x != x {
>    |        ^^^^^^ Float `==` treats NaN as equal to NaN
>   help: to test for NaN, use `x.is_nan()`
>   help: for IEEE equality, use `x.ieee_eq(x)`
> ```
>
> What it needs:
> 1. **New lint `FloatSelfComparison`**: a warning, error-level in `blink check --strict`. It fires when both operands of a Float or F32 `==` or `!=` are the same pure place expression. It has a machine-applicable fix: `x != x` becomes `x.is_nan()` and `x == x` becomes `!x.is_nan()`. The check reads the written syntax only, the same way W0706 does. Its explain text names `!(x >= 0.0)` as a NaN-reject idiom that does not port. It also names `x.ieee_eq(y)` and a raw IEEE `<`, if we add one.
> 2. **LSP hover on a Float comparison operator**: "total order: NaN == NaN, NaN sorts last; IEEE: `ieee_eq`". This puts the explanation where an LLM or a human reads code.
> 3. **Fix the E1400 text** so it names `-0.0`/`0.0` and NaN payloads, not "NaN-inequality".
> 4. **Fix NaN and Float rendering** in interpolation and assert output, so failure messages show `NaN`.
>
> I would also accept `ieee_lt`/`ieee_le` (or a single `ieee_cmp -> Option[Ordering]`) as a sibling of `ieee_eq`, so numeric code that ports IEEE ordering has a named target the lint can point to. That is optional. Add it only if the panel thinks ordered compares are the main porting risk. The `!(x >= 0.0)` case suggests they might be.
>
> Tradeoff: every LLM prior expects `x != x` to be the NaN test. The lint catches that one exact form, which is the most common one. It does not catch NaN that flows through `<`. Hover and explain text cover that case, and they are weaker.
>
> ### Proposal B: IEEE operators with a split trait (Rust model)
>
> `==` and `<` follow IEEE. Float implements a new `PartialEq`/`PartialOrd` but not `Eq` or `Ord`. `xs.sort()` on `List[Float]` becomes a compile error, and the help points to `sort_by(Float.total_cmp)`.
>
> ```blink
> let ys = xs.sort_by(Float.total_cmp)
> ```
>
> Diagnostic surface: Rust's "the trait `Ord` is not implemented for `f64`" is one of its most-searched errors. It works, but it is friction on every Float sort, max and contains, and on every derived struct. It also adds two traits to the prelude and breaks the 5-0 rule that operators desugar to `Eq`/`Ord`. The cost is large and the gain is "matches Rust", while it does not match Python, JS or Go, which all sort Floats directly. I reject it.
>
> ### Proposal C: IEEE operators, total order inside Eq/Ord (the Python/JS hybrid)
>
> I reject this outright. `a == b` and `[a] == [b]` give different answers, and a generic `fn same[T: Eq](a: T, b: T) -> Bool { a == b }` disagrees with the direct `==`. With monomorphization and no specialization, the same text compiles to two meanings, and no diagnostic can explain that at the call site. Python has this same bug (`nan in [nan]` is True, `nan == nan` is False), and people file it as a bug against Python.
>
> ### Cross-language note
> - Rust: IEEE operators, plus `total_cmp` with NaN placed by sign.
> - Go: IEEE, and NaN map keys leak entries.
> - Java: IEEE for primitives, but `Double.equals` and `compareTo` use a total order (NaN equals NaN, NaN sorts last, and unlike Blink -0.0 is less than 0.0). That is the closest precedent for Blink's choice.
> - Python and JS: IEEE operators with identity shortcuts in containers, which is Proposal C's bug.
>
> ### Vote
> **Proposal A**: keep the total order, plus the `FloatSelfComparison` lint with an autofix, LSP hover, and the E1400 and rendering fixes. Optionally add `ieee_cmp`. The deviation prevents a real bug class: silent wrong answers in containers, derived Eq and sort. The tooling turns the remaining porting risk into a warning at the exact line where it happens.

- **AI/ML:**

> AI/ML seat, Phase A on [this ticket] (Float total order): I recommend keeping the total order (Proposal A) and adding a lint for the one LLM habit it silently breaks.
>
> FACTS I CHECKED
> - gen1 today: `let x = 0.0 / 0.0; if x != x {..}` takes the else branch with NO diagnostic. `1.0 < x` prints `true`.
> - sections/06_tooling.md:879 (assert_close NaN policy) says "`NaN <= NaN` is `false`" and calls that "the IEEE-754 invariant". Under §3 *Float Total Ordering*, `NaN <= NaN` is `true`, so the two sections disagree. Whatever the vote, this line needs a fix (chore).
> - -0.0 == 0.0 already matches IEEE. Only NaN differs.
>
> HOW AN AI SEES IT
> LLM priors on NaN are mixed. They are not one shared rule:
> - Python/Rust/JS/Go code tests NaN with `math.isnan` / `.is_nan()` / `Number.isNaN`. That works the same in Blink.
> - C/C++/older JS code uses `x != x`. In Blink this is always false and fails without a sound. This is the one real prior break.
> - Few models write code that relies on `nan < y` being false. Most numeric code filters NaN first, or never thinks about it.
> The total order does protect a large prior: models write `xs.sort()`, `xs.contains(v)`, `assert_eq(a, b)`, `@derive(Eq)` on structs with Float fields, and generic `max[T: Ord]`. Under total order all of these compile and act sensibly. Under IEEE they either fail to compile or give quiet wrong answers.
>
> PROPOSAL A (preferred): keep the total order, add a self-compare lint, fix the docs
> ```
> fn mean_ok(xs: List[Float]) -> Bool {
>     let m = xs.sum() / xs.len().to_float()
>     if m != m {               // warning[FloatSelfCompare]: always false; NaN == NaN in Blink
>         return false          // help: use `m.is_nan()`
>     }
>     true
> }
> ```
> - New warning: a Float/F32 `==`, `!=`, `<`, `<=`, `>`, `>=` whose two operands are the same plain local or path. `x == x` and `x != x` both get the warning, with a machine fix to `x.is_nan()` / `!x.is_nan()`. This turns the only silent prior break into a compile-time message with a fix the model copies.
> - Spec: one short "Differences from IEEE 754" list (three items: `==`, `!=`, ordered compares with NaN), so a model reading only the spec learns them in one place.
> - Bug classes it prevents (the re-audit test): (1) sort with NaN. C++ std::sort with NaN is UB, and Python `sorted([3, nan, 1])` gives garbage order. Blink is deterministic. (2) `xs.contains(nan)` / `index_of` never finding a NaN. (3) Container `==` that disagrees with element `==`: Python `[nan] == [nan]` is True only through the identity shortcut. Blink's same-pointer shortcut relies on reflexivity (decisions/container-equality.md). (4) `assert_eq(result, expected)` failing on a NaN that both sides expect. (5) derived `Eq` on a struct being non-reflexive.
> - Cost: `x != x` (the lint covers it) and "NaN fails every ordered guard". `if x > limit` now catches NaN as too large, which is the safer error. `if x < 0.0` passes NaN in both models, so nothing changes there.
>
> PROPOSAL B (reject): IEEE operators, Float gets no Eq/Ord (Rust model)
> ```
> xs.sort_by(fn(a, b) { a.total_cmp(b) })   // every Float sort
> ```
> Rust's `partial_cmp(..).unwrap()` and "f64: Ord not satisfied" are among its most common LLM compile errors. This adds a decision point and about 10 to 15 tokens to every Float sort, max, dedup and derive. It also breaks the decided sort/contains/derive/container rules. Blink has no PartialEq/PartialOrd, and adding them doubles the trait surface a model must learn.
>
> PROPOSAL C (reject): IEEE operators, total-order Eq/Ord impls (Java `==` versus `Double.equals`)
> With monomorphization, `a == b` in `fn f[T: Eq]` and `a == b` on concrete Float give different answers for the same text. If a refactor moves code into a generic, the result changes. That is a new bug class, and it breaks the 5-0 rule that operators desugar to trait calls. `Ord.cmp` returns three cases and cannot say "unordered", so IEEE `<` needs its own desugar. For a model, the same token with two meanings that depend on context is the worst kind of rule to learn.
>
> CROSS-LANGUAGE
> Java `Double.compare`/`equals` and Rust `total_cmp` already ship a NaN-equal total order as the "sort/collection" answer. Blink makes that the only answer, and keeps IEEE behind the explicit `ieee_eq`. Unlike Java (and Rust `total_cmp`), Blink does not split -0.0 from 0.0. That matches IEEE and C, so it is the better prior.
>
> TOKEN / DECISION-POINT COUNT
> A: zero new decision points in common code (sort, contains, ==, assert_eq just work). One rare idiom changes, and a lint catches it.
> B: one decision point per Float compare site, plus higher token cost.
> C: one hidden decision point (generic or concrete context) with no syntax to show it.
>
> PREFERRED: A. Keep the total order. Add the FloatSelfCompare warning with the `is_nan()` fix. Add a three-item IEEE-difference list to §3. Fix 06_tooling.md:879.

- **Minimalism:**

> Min (Minimalism) Phase A on [this ticket]: keep the total order and add one lint. Reject the Rust-style trait split and any "IEEE operators, total cmp" hybrid.
>
> ## The question is smaller than the ticket title
> `-0.0 == 0.0` is already the IEEE answer (sections/03_types.md:3693, decisions/float-ieee-eq.md). Remove that half of the ticket. What is left is NaN: `NaN == NaN`, `NaN != NaN` is false, and NaN is the greatest value under `<`/`>`/`cmp`. So we are choosing which NaN rule holds, not reworking Float.
>
> ## Proposal 1 (preferred): keep the current rule and add W07xx FloatSelfComparison
> Keep. It prevents a real bug class: **NaN breaks generic code that assumes laws.** If one Float impl breaks a law, everything built on Eq/Ord breaks without a warning:
> - `sort()` on a list with a NaN: C++ calls this UB. Python returns garbage order. Blink returns a correct order with NaN last.
> - `xs.contains(nan)` and `index_of`: under IEEE these are always false or None.
> - Container `==`: `[nan] == [nan]`. Our codegen uses a same-pointer shortcut that is only valid because Float Eq is reflexive (decisions/container-equality.md). Under IEEE, the answer would depend on whether the two lists share storage. Python has this exact defect: `nan in [nan]` is True only because of an identity check.
> - `@derive(Eq, Ord)` on a struct with a Float field, generic `max[T: Ord]`, and tuple Eq/Ord all inherit the same break.
>
> The cost is the ported C idiom `if x != x { ... }`. Under the total order it is always false, so the NaN check never runs. Fix that with a lint, not by changing semantics. A diagnostic costs no language surface:
>
> ```blink
> fn safe_div(a: Float, b: Float) -> Option[Float] {
>     let q = a / b
>     if q != q {        // warning[FloatSelfComparison]: always false for Float; use `q.is_nan()`
>         return None
>     }
>     Some(q)
> }
> ```
> The lint fires when both operands of a Float/F32 `==`, `!=`, `<`, `<=`, `>`, `>=` are the same local or parameter, written the same way. Help: `x.is_nan()` / `!x.is_nan()`. The Phase D panel for ieee_eq already named this as "the real hazard" and sent it to friction. This re-audit is the right time to make it normative.
>
> Second known cost: `if !(x >= 0.0)` used as a NaN guard is true under IEEE and false here. The lint does not catch that. The opposite case cancels it: IEEE lets NaN slip through range guards like `if x < lo || x > hi { reject }`, and Blink rejects it (NaN > hi). Ported validation code fails open under IEEE and fails closed here. I count that as a net win.
>
> ## Proposal 2 (reject): IEEE operators, total `cmp`
> `==`/`<` follow IEEE, and `Ord.cmp` stays total. This breaks the 5-0 rule that operators desugar to trait calls. Either `a == b` and `a.eq(b)` give different answers, or `Eq.eq` itself is not reflexive. Also, under monomorphization, `x == y` in a generic fn would give a different answer from the same text on a concrete Float. That is two meanings of `==` for one type: the worst outcome for LLM priors and for users.
>
> ## Proposal 3 (reject): Rust split (PartialEq/PartialOrd + total_cmp)
> It matches IEEE and keeps the laws by adding two traits, a second bound on every generic, `sort_by(|a, b| a.total_cmp(b))` boilerplate for every Float sort, and the `f64: !Ord` papercut that every Rust user meets in week one (`ordered-float` crate). That is the C++ committee path: add surface to keep two answers. Our total order gives Rust's `total_cmp` behavior to everything for free, with no new trait.
>
> ## Proposal 4 (reject): remove Eq/Ord from Float
> Plain subtraction, but `if x == 0.0` would stop compiling. That breaks priors far more than NaN == NaN does.
>
> ## Cross-language note
> No mainstream language has a coherent answer. Python is IEEE for scalars and reflexive inside containers. Rust splits the traits. Java's `==` is IEEE, but `Double.equals`/`compareTo` are total, with NaN equal to NaN and largest. That is exactly our rule, used by Java collections for 25 years. Blink applies the Java collections rule to the operator as well, so one type has one meaning. The LLM-priors principle says "unless the deviation prevents a bug class". NaN in sort, contains, container ==, and derive is a bug class with CVE-grade examples (C++ sort UB).
>
> ## Ballot preference
> 1. Keep the total order for Eq/Ord/operators (NaN == NaN, NaN greatest, -0.0 == 0.0). YES
> 2. Add the FloatSelfComparison warning on `x op x` for Float/F32, with help to use `is_nan()`. YES (the only addition, and it is a diagnostic, not surface)
> 3. No new method (`total_cmp`, `ieee_lt`, etc.). `cmp` is already the total compare, and `ieee_eq` covers IEEE equality. If someone needs IEEE `<`, `!x.is_nan() && x < y` is one line. YAGNI.
> 4. Retitle the ticket. The -0.0 half is not a deviation.


#### Phase B — Debate (round 1)

All six seats signalled "STABLE, ready to vote" after one round. plt withdrew the IEEE ordered predicates; the other five seats asked for them on the ballot as a separate item. web, devops and plt moved on the fix mode, as their replies show.

- **Systems:**

> Sys Phase B r1 on [this ticket]: STABLE, ready to vote. Keep V2 on the ballot as its own item; I will vote no on it.
>
> **KEEP:** agree. All six seats reached it on their own, and each named the same bug class (sort, contains, container `==` with the same-pointer shortcut, derive, generic `max`).
>
> **V1a, which operators:** all six. `x < x` / `x > x` are always false and `x <= x` / `x >= x` are always true for every Float, so all six are constant compares. The check is the same syntactic match for each, so leaving four out costs as much as putting them in. Web and devops: do you object to the ordered four? `x <= x` is the NaN hazard in a different form (IEEE: `!is_nan`).
>
> **V1b, which operands match:** I concede to a tight rule: "the same local, parameter or field path (`a.b.c`), written the same way". This drops my looser "place expression", which let in `xs[i]` and calls. A call can return a different value each time. An index is pure but brings in "is `i` the same value?", which we do not need. Min's and web's texts plus field paths cover what people port.
>
> **V1c, the fix:** accept aiml/devops: machine-applicable where the IEEE meaning maps exactly. `x != x` becomes `x.is_nan()`. `x == x`, `x <= x` and `x >= x` become `!x.is_nan()`. `x < x` and `x > x` are false under both models, so they get help text only. The autofix is safe because the person writing ported code meant the IEEE answer. I drop plt's `x.ieee_eq(x)` as a help suggestion, because `is_nan()` says what the code means.
>
> **V1d, `--strict`:** no objection, but it is a CLI-mode question and not part of this ruling. Leave it out of the ballot text.
>
> **V1e, the name:** `FloatSelfComparison`, which is parallel to `NegativeZeroComparison` (W0706).
>
> **V1f:** agree. The explain text names `!(x >= 0.0)` as the NaN guard that does not port.
>
> **V2, IEEE ordered predicates: on the ballot, I vote NO.** Quoting min: "`!x.is_nan() && x < y` is one line." `ieee_eq` exists because it is the only way to get IEEE `==` and to show W0706's sign hazard. Ordered IEEE compares are already one `is_nan()` away, and that form tells the reader that NaN is the concern. Adding four methods plus `partial_cmp` brings back Rust's two-answer surface without Rust's type-level guard. Models will grab `partial_cmp(..).unwrap()` from Rust habit and get a panic where `cmp` would have worked. Plt, which ported code needs `ieee_lt` that `!x.is_nan() && x < y` cannot express? If you name one, I will reconsider.
>
> **V3, spec text:** merge them into one. Use aiml's three-item "Differences from IEEE 754" list under *Float Total Ordering*, and put my clamp example and web's range-check line under it as the two ordered-compare cases (`x > hi` rejects NaN, `x >= lo` admits it). It names `is_nan()` and `ieee_eq`. That is one block and not three.
>
> **V4:** these are separate chores and bugs. They are not part of the ruling.
> - 06_tooling.md:879: a chore to fix the text, which today wrongly says `NaN <= NaN` is false. Keep the `assert_close` NaN policy and give "NaN is not close to anything" as the reason.
> - E1400 text at typecheck.bl:9977: a chore (stale "NaN-inequality").
> - `"{x}"` printing `-nan` and `1` against the Float Text Form: a type:bug with an MVCE, not a chore. It breaks the round-trip law.
> - LSP hover: a tooling nicety that can be a feature ticket. It is not a normative spec item.
> - Retitle the ticket: agree with min/plt.
>
> **Systems note for the record:** no option on the ballot changes codegen or the runtime. `blink_float_eq` and `blink_float_cmp` stay as they are, the lint is front-end only, and the ABI does not change.
>
> STABLE, ready to vote.

- **Web/Scripting:**

> Web seat, Phase B round 1 on [this ticket]. KEEP: yes, and all six seats agree. My position on each variation is below.
>
> **V1a, which operators.** I accept all six as a concession. My Phase A covered `==`/`!=` only, but min/aiml/sys are right: `x <= x` and `x >= x` also flip for NaN (IEEE false, Blink true). One rule, "any Float compare of a value with itself", is easier to teach than "only the equality ones". `x < x`/`x > x` are false in both models, but they still warn as dead code, which costs nothing.
>
> **V1b, operand match.** I back sys's wording plus devops's "pure" condition: both operands are the same place expression as written, made only of a local, a parameter and field accesses (`x`, `a.b.c`). No calls, no indexing. `f() != f()` and `xs[i] != xs[i]` stay out, because two calls can return different values. A JS dev reads "same variable or same field" in five seconds. Anything wider brings false-positive questions.
>
> **V1c, fix.** I accept aiml/devops's machine-applicable fix for `==`/`!=` only: `x != x` → `x.is_nan()`, `x == x` → `!x.is_nan()`. That is the 90% case, and an autofix is what LLMs and editors pick up. For the ordered ops, give help text only: `x <= x` has no single correct rewrite the tool can be sure of. I object to plt's `x.ieee_eq(x)` as the help text. It is a second, obscure way to write `!x.is_nan()`. Name one idiom only.
>
> **V1d, level.** Warning. `--strict` promotes all warnings anyway if that mode exists, so it needs no line in this ruling.
>
> **V1e, name.** `FloatSelfComparison`. That is my concession to sys/min/devops: it matches `NegativeZeroComparison` (W0706).
>
> **V1f.** Agree. Put `!(x >= 0.0)` in the explain text. It is the one case the lint can't catch.
>
> **V2, IEEE ordered predicates.** Put it on the ballot as its own item, because plt proposed it as a first-tier part of their vote. I vote NO. Four `ieee_*` methods plus `partial_cmp -> Option[Ordering]` is Rust's API surface without Rust's reason for it. `partial_cmp(..).unwrap()` is exactly the papercut we rejected with the Rust split. A porter who needs C's `<` writes `!x.is_nan() && x < lo` (min's point), and that line is clearer to a Python/JS reader than `x.ieee_lt(lo)`. Add it later if real friction tickets show up. YAGNI.
>
> **V3, spec text.** Merge them into one subsection, "Differences from IEEE 754", under *Float Total Ordering*: aiml's three-item list, sys's clamp example, and my `x >= lo && x <= hi` line showing that a full range check still rejects NaN. One place to look, not three paragraphs.
>
> **V4, outside items.** I verified two of them with gen1:
> - sections/06_tooling.md:879 does say "`NaN <= NaN` is `false`… the IEEE-754 invariant". That contradicts §3. Fix it as a chore: the rule (assert_close rejects NaN) stays, and only the stated reason changes.
> - devops's rendering finding is real: `"{x} {y} {x.display()}"` with x = NaN, y = 1.0 prints `-nan 1 -nan`. The Float Text Form requires `NaN` and `1.0`. That is a bug ticket outside this vote, but it matters here: an `assert_eq` failure on Floats shows wrong text, so users can't see the NaN behavior we are keeping.
> - E1400 "NaN-inequality" text: fix it as a chore. Agree.
> - LSP hover: fine as tooling follow-up work. It does not belong in the ruling.
> - Retitle the ticket. Agree with min/plt: `-0.0 == 0.0` is not a deviation.
>
> Proposed ballot:
> 1. KEEP the total order.
> 2. FloatSelfComparison, a warning on all six ops; operands are the same pure place expression; autofix for `==`/`!=`, help text for the rest.
> 3. V2 `ieee_*`/`partial_cmp`: separate item, I vote NO.
> 4. One "Differences from IEEE 754" subsection.
> The V4 items go to chores and bugs.
>
> STABLE, ready to vote.

- **PLT:**

> PLT, Phase B round 1 on [this ticket]: KEEP unchanged. On V1, I want the lint to fire on four operators, only on pure place operands, with help text and no auto-applied fix. I withdraw V2. STABLE, ready to vote.
>
> **KEEP.** I agree with all six seats. None of the Phase A replies moves me.
>
> **V1a: operators.** I propose `==`, `!=`, `<=` and `>=` only.
> - These four are the operators whose answer on `x op x` changes from IEEE to Blink when x is NaN. Under IEEE `x <= x` is false for NaN; in Blink it is always true.
> - `x < x` and `x > x` are false in both models, so nothing changes in a port. Folding them in would make the lint's "because NaN == NaN" explanation false for those two. That fails the bar devops sets: a diagnostic must state the true reason.
> - min, sys and aiml want all six. I accept six as a concession only if the message is set per operator, and `<`/`>` say "always false" without any NaN reason.
>
> **V1b: operand match.** The lint is sound only if both operands must denote the same value, so the match rule needs that property. I back sys and devops on "the same pure place expression as written", defined as:
> - a local or a parameter
> - a field path on one of those (`a.b`)
> - an index whose index is itself such a place or a literal (`xs[i] != xs[i]`, the C array NaN test)
> - no calls
>
> Both operands sit in one expression with no side effects between them, so they read the same value. min's "local or parameter only" misses `a.b != a.b` and `xs[i] != xs[i]`, which are common in ported numeric code.
>
> **V1c: fix.** Help text only (min, sys, web), not machine-applicable (aiml, devops).
> - Rewriting `x != x` to `x.is_nan()` changes the runtime behavior from constant false to a real test. That is what the author meant, but a fix tool that runs without a prompt must not change semantics.
> - Ship it as a suggested fix the user accepts by hand.
> - I drop `x.ieee_eq(x)` from my help text. One answer, `x.is_nan()`, is better than two.
>
> **V1d.** Neutral on devops's `--strict` error level.
>
> **V1e: name.** `FloatSelfComparison`. That follows the W0706 `NegativeZeroComparison` pattern.
>
> **V1f.** I agree that the explain text should name `!(x >= 0.0)` as an idiom that does not port. min says it is offset by `x > hi` failing closed. That is true, but it belongs in the explanation, not in the lint rule.
>
> **V2: withdraw it.** I concede to min: "`!x.is_nan() && x < y` is one line. YAGNI." My proposal prevents no bug class, and it adds five methods. With one open slot on the ballot, it should not be on it. If devops still sponsors `ieee_cmp`, put it on as a separate optional item. I would vote no.
>
> **V3: spec text.** I support one normative list in *Float Total Ordering*: aiml's three items, plus sys's clamp example under it. The wording must be exact, because the laws depend on it:
> - `NaN == NaN` is true.
> - `NaN != NaN` is false.
> - When y is not NaN, `NaN > y` and `NaN >= y` are true, and `NaN < y` and `NaN <= y` are false.
> - `NaN <= NaN` and `NaN >= NaN` are true.
>
> I would not add web's separate range-check line. The clamp example already shows that idiom.
>
> **V4.** Agree on each item:
> - `sections/06_tooling.md:879` is factually false under §3. Restate the `assert_close` NaN policy as its own rule ("either argument NaN fails"), with no claim that IEEE requires it. This needs no vote; it is a spec fix.
> - The E1400 text at `src/typecheck.bl:9977` is stale and goes to a chore.
> - Bad NaN and Float text in interpolation goes to a bug ticket. It is not part of this ruling.
> - LSP hover is tooling and is fine.
> - Retitle the ticket: `-0.0 == 0.0` is not a deviation.
>
> STABLE, ready to vote.

- **DevOps:**

> DevOps Phase B r1 ([this ticket]): KEEP plus the V1 lint. I concede on V1a and V1d, and I narrow my own V1c.
>
> V1a, operators: I concede to sys/aiml/min and accept all six. `x < x` and `x > x` are always false, and `x <= x` and `x >= x` are always true, so each is the same kind of constant result. One rule is easier to explain than a list of exceptions.
>
> V1b, operand match: I agree with sys. The lint fires when both operands are the same local, parameter, or field path on one of those (`a.b == a.b`), written the same way. It does not fire on calls or on `.get()`, because those can give two different values. "Pure place expression" and "same local, field path" mean the same set, so use sys's words in the spec.
>
> V1c, fix: I narrow my own proposal. aiml and I asked for a machine-applicable fix, but `x != x` -> `x.is_nan()` changes what the program does: a dead branch becomes live. That is what the porter meant, but a fix that `blink fix` applies with no review must not change behaviour. So: show it as a suggested fix (an LSP quick-fix and a `help:` line with the replacement text), and keep it out of the automatic `blink fix` set. Suggested text: `x != x` -> `x.is_nan()`, `x == x` / `x <= x` / `x >= x` -> `!x.is_nan()`, and `x < x` / `x > x` -> help "always false" only, with no rewrite.
>
> V1d, level: I concede and drop the `--strict` part. `[lints] W07xx = "error"` (§4.16.8) already covers that need. Warning by default, the same as W0706.
>
> V1e, name: `FloatSelfComparison`, to match `NegativeZeroComparison` (W0706).
>
> V1f: put the `!(x >= 0.0)` case in the explain text, and in the V3 spec list. min is right that the lint cannot catch it, which is why it must be written down.
>
> V2, IEEE predicates: put it on the ballot as its own item, so plt's proposal gets a real vote. My vote is NO for now, with min: "`!x.is_nan() && x < y` is one line". The lint's help can point to `is_nan()`. Four methods plus `partial_cmp` add surface that no case in Phase A needs. If ports of numeric code later show that people need them, a friction ticket can bring them back.
>
> V3, spec text: merge aiml's three-item "Differences from IEEE 754" list with sys's clamp example and web's `x >= lo` line into ONE short subsection of *Float Total Ordering*. Three separate fragments would split the facts that a reader (or a model) must learn in one place. The list must name `ieee_eq`, `is_nan()` and the new lint.
>
> V4: none of these should be on the ballot. They are chores or bugs:
> - 06_tooling.md:879 (`NaN <= NaN` is false): a spec chore that is needed whatever the vote.
> - The E1400 message's "NaN-inequality" text: a chore.
> - Interpolation printing `-nan` and `1`, when §3 says `NaN` and `1.0`: a bug, with a ticket to file.
> - LSP hover: tooling, not spec. I withdraw it from the ruling.
> - I agree with min and plt: retitle the ticket and drop the `-0.0` half.
>
> STABLE, ready to vote.

- **AI/ML:**

> AI/ML seat, Phase B round 1 on [this ticket]: I keep KEEP + V1, V2 should go on the ballot and I will vote no on it, and my position is STABLE.
>
> V1a (operators): cover all six. They do not all carry the same hazard. `x <= x` and `x >= x` act like `x == x`: IEEE gives false for NaN, Blink always gives true. That is a real porting break, because C code uses `!(x <= x)` as a NaN test. `x < x` and `x > x` are constant false in BOTH models, so they are not a porting hazard, only dead code. Warn on them too, with a different message ("always false") and no is_nan fix. I object to web/devops "`==` and `!=` only": that misses the `<=`/`>=` forms, which break the same way.
>
> V1b (operand match): I accept sys's "same place expression as written (`x != x`, `a.b == a.b`)". I add one case: an index whose index is a local or a literal (`xs[i] != xs[i]`). C ports write `if (a[i] != a[i])` often. No calls, and no other expressions. One rule, read from syntax, like W0706.
>
> V1c (fix): machine-applicable. This is my strongest point. An LLM (or `blink fix`) applies a structured fix in one step at no token cost. Help text alone needs the model to read it, understand it and edit by hand, and that is where it makes mistakes. Fixes: `x != x` → `x.is_nan()`, `x == x` / `x <= x` / `x >= x` → `!x.is_nan()`. `x < x` / `x > x` get no fix.
>
> V1d (--strict error): I accept it if `--strict` already exists as a mode. I do not want it to grow out of this ticket.
>
> V1e (name): I concede `FloatSelfComparison`. It matches `NegativeZeroComparison`, and three seats use it.
>
> V1f: Agree. The explain text should name `!(x >= 0.0)`. It is the ordered-compare idiom the lint cannot see.
>
> V2 (IEEE ordered predicates): put it on the ballot as its own item. I vote NO, with min: "`!x.is_nan() && x < y` is one line." From the AI side, `ieee_lt` gives every Float `<` a second spelling. That is a new decision point at every compare site, and models will reach for it by mistake when they see "IEEE" in a port. `partial_cmp -> Option[Ordering]` brings in Rust's `.partial_cmp(..).unwrap()` habit, which is the thing we rejected. To plt: `ieee_eq` earns its place because `==` has no other way to say IEEE equality without `is_nan`. `ieee_lt` has no such gap, since `is_nan()` plus `<` says the same thing. To devops: the lint does not need an `ieee_*` target. Its fix target is `is_nan()`.
>
> V3 (spec text): merge the three into one *Porting from IEEE 754* block in *Float Total Ordering*:
> - my three-item difference list
> - sys's clamp example (`x > hi` catches NaN)
> - web's `x >= lo` line (NaN passes a lone lower-bound check)
> A spec-only reader then learns every difference in one place.
>
> V4 (items outside the ruling): I agree with all of them as chores, not ballot items:
> - Fix 06_tooling.md:879: under §3, `NaN <= NaN` is true.
> - Fix the stale E1400 "NaN-inequality" text.
> - Retitle the ticket, because `-0.0 == 0.0` is not a deviation.
> - devops's `-nan` / `1` interpolation output should become a type:bug with an MVCE. If it is real, it contradicts the Float Text Form.
> - LSP hover: fine as a tooling chore.
>
> STABLE, ready to vote.

- **Minimalism:**

> Min, Phase B round 1 on [this ticket].
>
> **KEEP.** All six seats chose it. Nothing to add.
>
> **V1a, operators. All six.** `x < x` and `x > x` are always false. `x <= x` and `x >= x` are always true. The check is identical for all six, so covering four fewer operators saves nothing. I agree with sys and aiml.
>
> **V1b, operand match.** I accept sys's "same place expression as written (`x != x`, `a.b == a.b`)" and narrow it to devops's "pure": a local, a parameter, or a field path over one of them. No calls and no index expressions. `f() != f()` is not constant, and `xs[i]` drags in bounds and aliasing questions we do not need to answer. The check reads syntax only, the same shape as W0706. I drop my wording "written the same way" in favor of this.
>
> **V1c, fix.** Concession: a machine-applicable fix for `==` and `!=` only (`x != x` becomes `x.is_nan()`, `x == x` becomes `!x.is_nan()`). The fix is tooling, not language surface. For the ordered forms, give help text only, because no single rewrite matches what the author meant. plt's help that names `x.ieee_eq(x)` as a NaN test is worse than `is_nan()`; I would leave it out.
>
> **V1d, level. Object to a lint-specific rule.** devops's "error-level in `blink check --strict`" is already true for every warning (sections/06_tooling.md:585, 04_effects.md:3704: "`--strict` and a `[lints]` entry can make it an error, as for any warning"). Do not write a special case.
>
> **V1e, name. `FloatSelfComparison`.** It pairs with `NegativeZeroComparison`.
>
> **V1f.** Agree. Put it in the explain text, which costs nothing.
>
> **V2, IEEE ordered predicates. Put it on the ballot as its own question. I vote NO.**
> plt proposes four `ieee_*` methods plus `partial_cmp -> Option[Ordering]`. That brings back "unordered" as a second ordering concept, the same thing that every seat rejected as the Rust split. Here it is just spelled as methods. A porter who knows to write `x.ieee_ge(lo)` already knows NaN is special, and can write `!x.is_nan() && x >= lo`, which is clearer. sys said it best: "Neither prevents NaN bugs. Only `is_nan()` at the boundary does that." Even devops calls it optional "only if... ordered compares are the main porting risk". No user or ticket has asked for it. YAGNI. If it fails now, a later ticket can add it with evidence. Once shipped, we can never remove it.
>
> **V3, spec text.** I want ONE block, not three. Merge aiml's three-item "Differences from IEEE 754" list with web's/sys's range-check example into one short subsection under *Float Total Ordering*. It names `is_nan()` and `ieee_eq`, and nothing more.
>
> **V4.**
> - 06_tooling.md:879 says "`NaN <= NaN` is `false`... the IEEE-754 invariant". That is false under §3 and must be a chore whatever the vote. The rule it states (assert_close rejects NaN) stays, but the reason changes. Good catch, aiml.
> - E1400 "NaN-inequality" text: a chore. Agree with devops.
> - Interpolation printing `-nan` / `1`: a bug ticket, outside this ruling. Do not ballot it.
> - LSP hover: not spec. Leave it off the ballot; tooling can do it without a vote.
> - Retitle the ticket: agree with plt.
>
> STABLE, ready to vote.


#### Phase C — Final vote

| Question | Result | Tally |
|---|---|---|
| Q1. Float `Eq`/`Ord` | KEEP the total order | 6-0 |
| Q2a. Lint operators | (i) all six: `==`, `!=`, `<`, `<=`, `>`, `>=` | 5-1, Minimalism dissent for (ii) |
| Q2b. Message for `x < x` / `x > x` | (i) a separate "always false" message, no NaN reason, no rewrite | 6-0 |
| Q2c. Lint operands | (i) 4, (ii) 2 (PLT, AI/ML) | to Phase D |
| Q2d. Fix mode | (C) 4, (A) 1 (Systems), (B) 1 (Web/Scripting) | to Phase D |
| Q3. `ieee_lt`/`ieee_le`/`ieee_gt`/`ieee_ge` and `partial_cmp` | NO | 6-0 |
| Q4a. Spec block contents | (i) the list, the clamp example and the `x >= lo` line | 6-0 |
| Q4b. Heading | (i) "Differences from IEEE 754" | 6-0 |

Each seat's ballot, verbatim:

- **Systems:**

> Sys (Systems) Phase C vote on [this ticket]
>
> Q1: KEEP
> Reasoning: The total order is what makes the Eq/Ord laws true for Float, and both the container same-pointer shortcut and the sort contract ("a permutation, no panic") depend on those laws. Under IEEE we would have to drop the shortcut, which means an O(n) walk on aliased compares, or ship Python's aliasing bug. Generic code under monomorphization would inherit broken laws, and with no specialization we could not patch it. The runtime cost is about one well-predicted branch per compare, with no ABI change.
> Concern: Ported ordered guards (`!(x >= 0.0)`, a lone `x >= lo`) let NaN through without notice, and no lint can see them.
>
> Q2a: (i) all six
> Reasoning: All six forms are constant for every Float, and the syntactic match is the same check, so covering only some costs as much as covering all. `x <= x` / `x >= x` are the NaN test in another form (IEEE: `!is_nan`), so they must be in. `x < x` / `x > x` are dead code, and flagging them is cheap.
> Concern: `x < x` is a rare form, so the extra coverage may never fire.
>
> Q2b: (i) separate "always false" message
> Reasoning: `x < x` and `x > x` are false under IEEE and under Blink alike, so a NaN reason would point the reader at a hazard that is not there. A diagnostic must state the true cause.
> Concern: Two message shapes for one lint name make the explain text a little longer.
>
> Q2c: (i) local, parameter or field path, no indexing
> Reasoning: "Same value on both sides" must be decidable with no analysis. An index brings in aliasing and evaluation questions (is `i` reassigned between the two reads, does a bounds panic matter?). Ported NaN tests almost always use a plain local. We can widen later with no breaking change, but narrowing later is a breaking change.
> Concern: `xs[i] != xs[i]` in a ported numeric loop still fails without a diagnostic.
>
> Q2d: (A) machine-applicable for !=, ==, <=, >=; help only for < / >
> Reasoning: Each rewrite gives exactly the IEEE meaning that the ported source meant, and the code it replaces is constant (dead), so no intended Blink behavior is lost. `blink fix` output still shows up in a diff for review.
> Concern: Applying it in bulk changes runtime behavior (a dead branch goes live), and someone who runs `blink fix` without reading the diff will not see that.
>
> Q3: NO
> Reasoning: `!x.is_nan() && x < y` already says the IEEE ordered compare in one line, and it says outright that NaN is the concern. Five methods plus `partial_cmp` bring back Rust's two-answer surface without Rust's type-level guard, and models will reach for `partial_cmp(..).unwrap()` from Rust habit and get panics. YAGNI: no seat named code that cannot be written without them.
> Concern: Numeric ports with many IEEE ordered compares get longer.
>
> Q4a: (i) list + clamp example + x >= lo line
> Reasoning: The two examples show both directions: NaN is caught by an upper bound and passes a lone lower bound. Showing only the clamp case would suggest that NaN is always rejected, which is false.
> Concern: More text in a section that is already long.
>
> Q4b: (i) "Differences from IEEE 754"
> Reasoning: The block states facts about the semantics, which is useful to every reader and not only to someone porting code. "Porting" frames it as migration advice, which goes stale.
> Concern: A reader searching for "porting" guidance may not find it under this heading.

- **Web/Scripting:**

> Web seat, Phase C vote on [this ticket].
>
> Q1: KEEP
> Reasoning: The total order prevents the NaN bugs that JS/Python/C++ developers hit all the time: sort gives garbage, `contains` misses NaN, and `assert_eq` fails on two equal NaN values. JS already uses this rule (SameValueZero) in `includes`, `Map` and `Set`, and Java uses it in collections. So it is a familiar prior, not an exotic one. `xs.sort()` and `@derive(Eq)` on Float structs work on day one.
> Concern: Developers who port C-style NaN checks keep hitting silent dead code that the lint cannot see (`!(x >= 0.0)`).
>
> Q2a: (i) all six
> Reasoning: "Any Float compare of a value with itself" is one rule a developer learns in five seconds. A list of exactly four operators raises the question "why not `<`?". All six are dead or constant code under Blink, so a warning on each one is honest.
> Concern: The `<`/`>` warnings could read as noise if their message suggests a NaN fix that does not apply.
>
> Q2b: (i) separate "always false" message
> Reasoning: `x < x` is false in IEEE too, so a NaN explanation on it would mislead and send people looking for a cause that does not exist. "Always false" with no rewrite is the plain truth.
> Concern: Two message shapes for one lint name add a little to the docs.
>
> Q2c: (i) local, parameter or field path; no calls, no indexing
> Reasoning: "Same variable or same field" is easy to predict, and a user can tell at a glance whether the lint fires. Index matching adds edge cases (aliasing, a mutable index, a bounds panic) that turn into "why did/didn't this warn" questions for a rare pattern.
> Concern: Ported numeric code that writes `xs[i] != xs[i]` slips through without a warning.
>
> Q2d: (B) machine fix for == and != only
> Reasoning: `x != x` as a NaN test has exactly one intent, so an automatic rewrite to `x.is_nan()` is safe, and it is the 90% case. `x <= x` and `x >= x` are rare, and their intent is less clear. A tool that silently changes their runtime behaviour starts a "blink fix changed my program" thread. Help text is enough for those.
> Concern: An automatic fix to `==`/`!=` still changes runtime behaviour, from constant to NaN-aware. A user who meant the constant (unlikely) would be surprised.
>
> Q3: NO
> Reasoning: Four `ieee_*` methods plus `partial_cmp -> Option[Ordering]` bring in Rust's surface and its `.unwrap()` papercut without Rust's reason for them. `!x.is_nan() && x < lo` is one line, and any JS/Python reader understands it at once. Add the methods later if real friction tickets ask for them.
> Concern: A numeric-heavy porter writes many `!x.is_nan() &&` guards and files friction tickets, which we would then need to triage honestly.
>
> Q4a: (i) list + clamp example + `x >= lo` line
> Reasoning: The lone lower-bound check is the case where NaN fails open, and the lint cannot catch it, so the reader must see it spelled out. The clamp example shows only the fail-closed half, so on its own it makes the rule look safer than it is.
> Concern: The subsection grows to three parts, so it must stay short or readers skip it.
>
> Q4b: (i) "Differences from IEEE 754"
> Reasoning: A developer searching the spec for "IEEE" finds this heading, and it describes the content plainly whether they are porting or writing new code. "Porting" suggests the section matters only to people who move old code.
> Concern: None of note. A cross-link from the ieee_eq paragraph would help it get found.

- **PLT:**

> PLT seat, Phase C vote on [this ticket]
>
> Q1. KEEP
> Reasoning: Operators desugar to Eq/Ord, and mono has no specialization. So Float's `==` must be the same relation that generic code, containers, derived impls and sort use. Only a total order makes that relation lawful (reflexive, transitive, total), and the Eq/Ord laws, the container same-pointer shortcut and the sort contract all rely on it. CHANGE needs either a PartialEq/PartialOrd split or two meanings for one operator, and both are worse.
> Concern: Ported code that uses NaN in ordered guards (`!(x >= 0.0)`) changes meaning in silence, and no lint can see it.
>
> Q2a. (i) all six
> Reasoning: In round 1 I asked for four operators only to keep the NaN reason true. With Q2b(i), `x < x` and `x > x` get an honest "always false" message. A constant compare of a place with itself is a bug signal for any operator, so I accept six on that condition.
> Concern: If Q2b(ii) wins, the `<`/`>` message will state a false NaN reason.
>
> Q2b. (i) separate "always false" message, no NaN reason, no rewrite
> Reasoning: A diagnostic must state the true reason. `x < x` is false under IEEE and under Blink alike, so it has no NaN cause and no `is_nan()` rewrite.
> Concern: Two messages for one lint name is a small cost in the docs.
>
> Q2c. (ii) include index by a local/parameter/field path or a literal
> Reasoning: The lint is sound when both operands must read the same value. `xs[i]` with a pure index in one expression with no side effects meets that test. `xs[i] != xs[i]` is the usual NaN test in ported array code, so (i) misses a common case.
> Concern: Indexing panics on an out-of-bounds index, but both operands panic the same way, so that does not affect soundness.
>
> Q2d. (C) suggested fix only, never auto-applied
> Reasoning: `x != x` -> `x.is_nan()` changes run-time behavior from constant false to a real test. A fix that `blink fix` applies with no prompt must keep semantics. This one guesses intent, so the user must accept it.
> Concern: Users who trust the autofix lose one keystroke of convenience, nothing more.
>
> Q3. NO
> Reasoning: I withdrew it. It prevents no bug class, it adds five methods, and `!x.is_nan() && x < y` already writes IEEE `<` in one line. `cmp` is already the total compare, and `ieee_eq` covers the one IEEE predicate the spec needs.
> Concern: Porters of IEEE ordered code get no named target, so the explain text must show the one-line form.
>
> Q4a. (i) list + clamp example + x >= lo line
> Reasoning: I change my round-1 view. The clamp example shows NaN caught (`x > hi`), and the lone `x >= lo` line shows NaN let through. Together they show both directions of the hazard, which the list alone states only in abstract terms. One line costs little.
> Concern: The examples must not read as advice to rely on NaN order for validation. The text should send readers to `is_nan()` at the boundary.
>
> Q4b. (i) "Differences from IEEE 754"
> Reasoning: The block states facts about the semantics, not a migration guide. A reader who never wrote IEEE code needs it too.
> Concern: None material.

- **DevOps:**

> DevOps Phase C vote, [this ticket]
>
> Q1: KEEP
> Reasoning: The total order turns silent wrong answers (in sort, contains, assert_eq, container == and derived Eq) into defined behaviour. No diagnostic could ever point at those failures, because they come from law-dependent generic code, not from one line. The one porting hazard with a syntax signature (x != x) gets a lint, so KEEP leaves the smallest gap that the compiler cannot catch.
> Concern: Ported ordered guards such as !(x >= 0.0) change meaning silently, and only the spec and explain text cover them.
>
> Q2a: (i) all six
> Reasoning: Every self-comparison of a Float place has a constant result, so one rule over six operators is simpler to state, to explain and to implement than a list of exceptions. A user who sees the warning on x <= x but not on x < x would read that as a lint bug.
> Concern: x < x is also constant under IEEE, so this lint now fires on code that was never a port hazard. Q2b must make that message honest.
>
> Q2b: (i) a separate "always false" message
> Reasoning: For x < x and x > x the NaN reason is false: the result is constant under IEEE too. A diagnostic that gives a wrong reason teaches the wrong rule, which is the worst diagnostic failure. The text must say what is true for each operator.
> Concern: Two message texts for one lint code make the explain page a little longer.
>
> Q2c: (i) locals, parameters, field paths; no calls, no indexing
> Reasoning: Blink has no index operator. `xs[i]` is error NoIndexOperator (I checked this with gen1 in Phase A), so option (ii) adds a match form that cannot occur in valid code. Element access is `xs.get(i)`, which is a call, and both options exclude calls. A rule that names syntax the language rejects would confuse readers and models.
> Concern: None from my view. If an index operator comes in later, that change must bring this lint under review, as W0706 does for patterns.
>
> Q2d: (C) suggested fix only
> Reasoning: Every rewrite changes behaviour. x != x -> x.is_nan() turns a dead branch into a live one, which is what the porter meant but is not what the program does today. A fix that `blink fix` applies with no review must keep behaviour the same, the same rule as rustc's MachineApplicable versus MaybeIncorrect. An LSP quick-fix plus a help: line with the replacement text gives one-keystroke repair and keeps a human, or a model, in the decision.
> Concern: Agents that apply only machine-applicable fixes will leave these warnings in place, unless their tooling also reads help: lines.
>
> Q3: NO
> Reasoning: No case in Phase A or round 1 needed IEEE ordered compares that `!x.is_nan() && x < y` cannot express in one line. Five methods add completion noise on every Float in the LSP, and each needs docs, an explain entry and tests. A friction ticket can bring them back if real ports show the need.
> Concern: A port of dense numeric C code will need more manual rewriting of guards.
>
> Q4a: (i) list + clamp example + x >= lo line
> Reasoning: The lone lower-bound check is the hazard the lint cannot see, so the spec is the only place that warns about it. The clamp example shows the safe direction and the x >= lo line shows the unsafe one. Both are needed to see that NaN-greatest is not just "safer".
> Concern: Two examples make the block longer than the four-line list it explains.
>
> Q4b: (i) "Differences from IEEE 754"
> Reasoning: It states a fact about the language, so a reader who has never ported code still finds it. The diagnostic explain text can link to it by that name, and "Porting" sounds like a migration guide that a reader can skip.
> Concern: None.

- **AI/ML:**

> AI/ML seat, Phase C vote on [this ticket]
>
> Q1: KEEP
> Reasoning: The things models write most for Floats (`xs.sort()`, `xs.contains(v)`, `assert_eq`, `@derive(Eq)`, generic `max[T: Ord]`) compile and give the expected answer only under the total order. IEEE equality would turn each of them into a compile error (Rust split) or a silent wrong answer, and it would break the container-equality laws. The one prior that breaks, `x != x`, has a syntax signature, so a lint can catch it.
> Concern: NaN that flows through ordered guards such as `!(x >= 0.0)` stays silent, and only the spec text and the explain text cover it.
>
> Q2a: (i) all six
> Reasoning: `x <= x` and `x >= x` break in the same way as `x == x`, and `x < x` / `x > x` are dead code that a reader should see. One rule over all compare operators is easier for a model to learn than a list with exceptions.
> Concern: The `<` / `>` warnings may read as noise if their message does not make clear that they are not a NaN issue.
>
> Q2b: (i) separate "always false" message, no NaN reason, no rewrite
> Reasoning: `x < x` is false in IEEE and in Blink, so a NaN reason would teach a model something false. A rewrite to `is_nan()` would be wrong there.
> Concern: Two message texts for one lint name add a small amount of spec surface.
>
> Q2c: (ii) also match an index with a local, parameter, field path or literal index
> Reasoning: Ported C and numeric code often writes `if (a[i] != a[i])`. LLM ports keep that form, so leaving it out lets the most common array NaN test through. The index forms stay syntactic and have no calls, so the rule is still one line to state.
> Concern: Indexing can panic on bounds, so the `is_nan()` rewrite must keep the same `xs[i]` read, not drop it.
>
> Q2d: (C) suggested fix only, never applied by the automatic `blink fix`
> Reasoning: I move from (A). A self-comparison can be a typo for `x != y` as well as a NaN test. An automatic rewrite to `is_nan()` changes behaviour, and in the typo case it hides the real bug. A `help:` line with the exact replacement text costs a model the same one edit, because models read diagnostics, so (C) loses nothing on token cost and keeps a person or the model in the loop.
> Concern: Agents that run only `blink fix` and skip warnings will leave the dead NaN check in place.
>
> Q3: NO
> Reasoning: `ieee_lt` and the others give every Float `<` a second spelling. That is a new decision point at each compare site, and models will reach for it by mistake in ports. `partial_cmp -> Option[Ordering]` brings back Rust's `.partial_cmp(..).unwrap()` pattern, which the panel rejected. `!x.is_nan() && x < y` already says it in one line.
> Concern: Someone who ports a large IEEE numeric kernel writes `is_nan` guards by hand and may miss one.
>
> Q4a: (i) list + clamp example + `x >= lo` line
> Reasoning: The two examples show the two directions NaN can go (a guard that catches NaN and a guard that lets it through). A spec-only reader, human or model, needs both to predict ported range checks. One extra line is cheap.
> Concern: Examples can drift from the list if one is edited without the other.
>
> Q4b: (i) "Differences from IEEE 754"
> Reasoning: I drop my own heading. A neutral, descriptive heading suits reference text, and the word "IEEE 754" is the search key either way.
> Concern: None of substance. A reader who is porting code may not look under a heading about differences, but the lint's explain text links there.

- **Minimalism:**

> Min (Minimalism), Phase C vote on [this ticket]
>
> Q1: KEEP
> Reasoning: The total order is the one rule that keeps sort, contains, container ==, derive and generic Ord code lawful, and it needs no extra traits. CHANGE needs either a trait split (two new traits) or two meanings of `==`, and both add surface to fix a narrow porting habit. A lint is cheaper than a semantic change.
> Concern: Ported code that leans on IEEE NaN behavior in ordered guards (`!(x >= 0.0)`) changes meaning silently, and no lint can see it.
>
> Q2a: (ii) ==, !=, <=, >= only
> Reasoning: I change my round-1 position. `x < x` and `x > x` are false under IEEE and under Blink, so they are not a porting hazard. They are a general "pointless compare" lint, which this ruling does not need. Covering only the four operators whose result differs from IEEE keeps the lint about one thing and removes the need for a second message (Q2b).
> Concern: Someone will later ask why `x < x` gets no warning; the answer is "not a NaN hazard", and the explain text must say so.
>
> Q2b: (i) a separate "always false" message with no NaN reason and no rewrite
> Reasoning: If (i) wins Q2a, a NaN reason on `x < x` would be false, because the result is the same under IEEE. A wrong reason is worse than a second message.
> Concern: Two messages for one lint name is more text to keep in sync.
>
> Q2c: (i) local, parameter, or field path; no calls, no indexing
> Reasoning: Indexing brings in the questions of whether `i` changed, aliasing, and bounds, for an idiom almost nobody writes. `xs[i] != xs[i]` is rare next to `x != x`. Start narrow; a later ticket can widen it with evidence.
> Concern: A porter who writes `v[i] != v[i]` gets no warning.
>
> Q2d: (C) suggested fix only, never auto-applied by `blink fix`
> Reasoning: I change my round-1 position after reading devops and plt. Every one of these rewrites changes what the program does at runtime: a branch that never ran starts to run. `blink fix` should apply only rewrites that keep behavior. A help line plus an LSP quick-fix still gives the exact replacement text at no risk.
> Concern: An LLM loop that only runs `blink fix` will not pick up the rewrite. It has to read the help line.
>
> Q3: NO
> Reasoning: Five methods and an `Option[Ordering]` bring back "unordered" as a second ordering concept, which the panel rejected as the Rust split. `!x.is_nan() && x >= lo` says the same thing, more clearly. No user has asked for it, and once shipped it cannot be removed.
> Concern: Numeric porters may write ad-hoc IEEE helpers in many slightly different ways; if that shows up, a later ticket can bring evidence.
>
> Q4a: (i) list + clamp example + the x >= lo line
> Reasoning: The lone lower-bound check is the one hazard the lint cannot see, so the spec is the only place that warns about it. One line costs less than the bug.
> Concern: The subsection grows past "short" if later edits keep adding examples.
>
> Q4b: (i) "Differences from IEEE 754"
> Reasoning: It states a fact about the language, so it stays true for readers who are not porting anything. "Porting" frames the section as migration help, which ages.
> Concern: None of substance.


#### Phase D — Round 2 (Q2c, Q2d)

The moderator gave the panel this fact: Blink has no index operator (`NoIndexOperator`, E0313), element access is the call `.get()`, and "An index is not a place." Option (ii) of Q2c named `xs[i]`, which cannot compile.

| Question | Result | Tally |
|---|---|---|
| Q2c. Lint operands | (i) the same local, parameter or field path, written the same way; no calls, no indexing | 6-0 R2 after 4-2 R1 |
| Q2d. Fix mode | (C) suggested fix only, never applied by `blink fix` | 6-0 R2 after 4-1-1 R1 |

Replies:

- **Systems:**

> Sys Phase D reply on [this ticket] (Q2c, Q2d)
>
> Q2c: I keep (i), and I correct my own reasoning. Devops is right: Blink has no index operator. `xs[i]` is E0313 NoIndexOperator, and "an index is not a place" (02_syntax.md:2942). My concern about "`xs[i] != xs[i]` slips through" was about code that cannot compile. Plt and aiml: a ported `a[i] != a[i]` first fails with E0313, and the porter rewrites it to `xs.get(i)`. That is a call, and both options exclude calls, so (ii) adds a match form with no valid input. In Blink the real array form is `let v = xs.get(i).unwrap()` followed by `v != v`, which (i) already catches. Leave index forms to whichever ticket adds an index operator, as devops says (the same rule as W0706 for patterns).
>
> Q2d: I move from (A) to (C). Two arguments change my view:
> - Aiml's typo case: `x != x` can be a slip for `x != y`. An automatic `is_nan()` rewrite would then hide the real bug behind code that looks correct. My (A) reasoning took for granted that every self-compare is a ported NaN test, and that is not certain.
> - Devops's rule: a fix that `blink fix` applies with no review must keep behavior the same (rustc MachineApplicable versus MaybeIncorrect). Every one of these rewrites turns a dead branch into a live one. I had already named that as my concern under (A), and it should decide the question, not stay a footnote.
>
> The help: line plus the LSP quick-fix gives the exact replacement text, so the cost to a human or a model is one accepted edit. Web, (B) has the same flaw as (A) for `==`/`!=`, which are the forms where the typo case is most likely.
>
> Nothing more on either question.

- **Web/Scripting:**

> Web seat, Phase D reply on [this ticket] (Q2c, Q2d).
>
> Q2c: Devops's fact settles this. Blink has no index operator (E0313 NoIndexOperator), and element access is `xs.get(i)`, a call. So (ii) names a form that valid Blink code cannot contain, and my own concern about `xs[i] != xs[i]` slipping through was moot. To plt and aiml: the ported `a[i] != a[i]` becomes `xs.get(i).unwrap() != xs.get(i).unwrap()` or a `let v = ...` binding. The first is a call, which both options exclude. The second is a plain local, which (i) already catches. Writing an index form into the lint rule would teach models and readers a syntax the language rejects. I stay on (i), and I ask plt and aiml to move. If an index operator ever arrives, that change reopens the lint.
>
> Q2d: I move from (B) to (C). Aiml's typo point changes my mind. `x != x` may be a typo for `x != y`. An automatic rewrite to `x.is_nan()` would then hide the real bug behind code that looks correct. That is the worse outcome for the 90% developer, and it is exactly the "blink fix changed my program" thread I wanted to avoid. Devops's rule is also the one JS/TS developers already know from ESLint: `--fix` applies only behaviour-preserving fixes, and the rest are editor "suggestions". (C) still gives a one-keystroke LSP quick-fix and an exact `help:` line. Convenience costs nothing, and safety goes up.
>
> Condition I ask to record with (C): the `help:` line must carry the exact replacement text (`x.is_nan()`, `!x.is_nan()`). That way a model that reads diagnostics, not `blink fix` output, can apply it in one edit. Devops, aiml and min all named this concern. Writing it into the ruling closes it.

- **PLT:**

> PLT seat, Phase D reply on [this ticket] (Q2c, Q2d)
>
> Q2c: I concede to (i). devops is right, and my Phase C vote rested on a false fact. Blink has no index operator (E0313 NoIndexOperator, sections/02_syntax.md:379), and "An index is not a place" (02_syntax.md:2942). Element access is `xs.get(i)`, which is a call, and both options already exclude calls. So option (ii) names a form that cannot occur in valid code. A lint rule must not name syntax the language rejects. I will vote (i) in the re-vote. aiml, the `a[i] != a[i]` port you name cannot compile in Blink, so a porter meets E0313 before this lint could fire.
>
> Q2d: I hold (C).
> - To sys: you say "no intended Blink behavior is lost" because the replaced code is dead. That assumes we know the intent. aiml's point decides it: `x != x` can also be a typo for `x != y`. In that case an auto-rewrite to `x.is_nan()` hides the real bug and makes it pass review. That is behavior the user never meant, applied with no prompt. A fix that `blink fix` applies must be a semantic identity. These rewrites are not.
> - To web: (B) has the same flaw on the exact case it auto-fixes. "One intent" is true for porters, but not for typos.
> - The cost of (C) is small. The help: line carries the exact replacement text, so a human or a model makes it in one edit, and the LSP quick-fix makes it in one keystroke. The rule "auto-fix keeps meaning" is easy to state and lasts. Making exceptions for "likely intent" gives up that rule for a few keystrokes.

- **DevOps:**

> DevOps Phase D reply, Q2c and Q2d
>
> Q2c, to plt and aiml: as worded, (ii) matches nothing. `xs[i]` is error E0313 (NoIndexOperator), and "An index is not a place" (02_syntax.md:2942). A ported `a[i] != a[i]` does not reach the type checker as a Float compare: it stops at E0313, and the help sends the porter to `.get(i)`. So the case you want to catch looks like `xs.get(i).unwrap() != xs.get(i).unwrap()`, or `xs.get(i) != xs.get(i)` on Option[Float]. Both are calls, and both options exclude calls. Option (ii) gives the spec a rule about syntax the language rejects, and a model that reads it will learn that `xs[i]` is valid Blink. That is a direct training-data harm.
>
> If you want array coverage, the correct widening is a separate rule: "a call to a sealed, side-effect-free builtin accessor (List.get, plus .unwrap) whose arguments match under (i)". That is a new proposal and needs its own evidence, so file it as friction after the lint ships. Widening later breaks nothing (sys's point). I ask plt and aiml to move to (i) on that basis.
>
> Q2d, to sys: "blink fix output still shows up in a diff" holds for a person at a desk. It does not hold for CI fix jobs, pre-commit hooks or agent loops, which apply the fixes in bulk and commit. A rewrite that turns a dead branch into a live one is a runtime change, and auto-apply tools must never make one. aiml's new point makes this stronger: `x != x` can be a typo for `x != y`, and in that case the rewrite to `is_nan()` hides the real bug behind code that looks correct.
>
> To web: (B) has the same flaw on the same operators. `==`/`!=` is where the typo case is most likely, so it is the worst place to auto-apply.
>
> On the shared concern (agents that only run `blink fix`): (C) still emits the exact replacement text in `help:` and in the JSON diagnostic, so any agent that reads diagnostics gets a one-edit repair. That costs nothing next to the risk of a silent behaviour change. I stay at (C).

- **AI/ML:**

> AI/ML seat, Phase D reply on Q2c and Q2d
>
> Q2c: I withdraw (ii). devops is right, and I checked it myself: sections/02_syntax.md:379 makes `xs[1]` error[NoIndexOperator] (E0313), and :2942 says "An index is not a place." My reasoning assumed C-style indexing that Blink does not have. A ported `a[i] != a[i]` therefore stops at E0313 before the lint can run, and the model's fix moves it to `xs.get(i)`, which is a call that both options exclude. A lint rule that names syntax the language rejects would also teach models that `xs[i]` is valid Blink. That does more harm to generability than the narrow rule does. I will vote (i). I agree with devops's concern: an index operator added later must bring this lint under review.
>
> Q2d: I stay on (C), which now has four seats. To sys: you say "the code it replaces is constant (dead), so no intended Blink behavior is lost", but that holds only when the porter meant a NaN test. In the typo case (`x != x` written for `x != y`), an automatic rewrite to `x.is_nan()` keeps the bug and removes the warning that points at it. To web: the same typo argument applies to `==`/`!=`, which (B) auto-applies, so (B) does not avoid the risk. On the agent concern that min, devops and I all named: agent tooling reads `help:` lines as part of the diagnostic text, so a help line with the exact replacement costs the model one edit. That makes (C) as cheap as (A) for models and safer for everyone else.

- **Minimalism:**

> Min, Phase D reply on [this ticket] (Q2c, Q2d)
>
> Q2c: I hold (i), but my Phase C reason was wrong, and devops has the right one. Blink has no index operator: `xs[i]` is E0313 NoIndexOperator, and "an index is not a place" (02_syntax.md:2942). So (ii) names a form that cannot reach the lint. aiml and plt: the ported `a[i] != a[i]` must become `xs.get(i)` in Blink, which is a call. That is excluded under both options, and it is `Option[Float]`, not Float, so it falls outside this Float/F32 lint anyway. If you want ported array NaN tests covered, the honest ask is a separate ticket for self-comparison on any `Eq` type, with evidence. Do not widen this rule with syntax the parser rejects. A rule text that names an impossible form also teaches models that `xs[i]` is valid Blink, which is the opposite of what we want in training data.
>
> Q2d: I hold (C). aiml's typo point settles it for me, and it answers both web and sys. web says "`x != x` as a NaN test has exactly one intent", but `x != x` is also the classic typo for `x != y`. An automatic rewrite to `x.is_nan()` turns that typo into a plausible-looking NaN test and buries the real bug for good. sys says "the diff still shows up for review", but bulk `blink fix` output is exactly the diff nobody reads line by line. One rule keeps this simple: `blink fix` applies only rewrites that keep behavior. Every rewrite on the table changes behavior. The help line costs a model or a person one edit.


Votes:

- **Systems:**

> Sys (Systems) Phase D re-vote on [this ticket]
>
> Q2c: (i) local, parameter or field path; no calls, no indexing
> Reasoning: Blink has no index operator (E0313 NoIndexOperator, 02_syntax.md:379), so (ii) names a form that valid code cannot contain. A ported array NaN test becomes `xs.get(i)`, a call that both options exclude, or a `let v = ...` binding that (i) already catches. The rule stays decidable from syntax alone, with no analysis.
> Concern: If an index operator is ever added, that change must reopen this lint, or array self-compares will slip through without a warning.
>
> Q2d: (C) suggested fix only, never applied by the automatic `blink fix`
> Reasoning: Every rewrite on the table turns a dead branch into a live one, so none of them keeps behavior the same, and auto-applied fixes must keep it. Aiml's typo case (`x != x` written for `x != y`) shows the rewrite can hide a real bug behind code that looks correct. Bulk fix runs in CI, hooks and agent loops get no line-by-line review. I support web's condition: the `help:` line (and the JSON diagnostic) must carry the exact replacement text.
> Concern: Agent loops that apply only `blink fix` output and ignore `help:` lines will leave the dead NaN checks in place.

- **Web/Scripting:**

> Web seat, Phase D re-vote on [this ticket].
>
> Q2c: (i)
> Reasoning: Blink has no index operator (E0313 NoIndexOperator), so (ii) names a form that valid code cannot contain. A rule that mentions `xs[i]` would teach readers and models a syntax the language rejects. The real array port is `let v = xs.get(i).unwrap()` followed by `v != v`, and (i) already catches that. Widening the rule later breaks nothing.
> Concern: A developer who writes `xs.get(i).unwrap() != xs.get(i).unwrap()` gets no warning. That needs friction evidence before anyone widens the rule.
>
> Q2d: (C)
> Reasoning: `x != x` can be a typo for `x != y`. An automatic rewrite to `x.is_nan()` would bury that bug in code that looks correct, so no auto-applied rewrite here is safe. This matches the ESLint rule JS/TS developers already know: `--fix` applies only behaviour-preserving fixes, and the rest are editor suggestions. The LSP quick-fix and the exact `help:` text keep the repair at one keystroke or one edit.
> Concern: Agents that run only `blink fix` and ignore `help:` lines leave the dead NaN check in place. So the help line (and the JSON diagnostic) must carry the exact replacement text, `x.is_nan()` / `!x.is_nan()`.

- **PLT:**

> PLT seat, Phase D re-vote on [this ticket]
>
> Q2c. (i)
> Reasoning: Blink has no index operator. `xs[i]` is E0313, and "an index is not a place" (02_syntax.md:2942). So (ii) adds a match form that no valid program can contain. The real ported form, `let v = xs.get(i).unwrap()` then `v != v`, is a plain local, and (i) already catches it. A rule over syntax the language rejects is not well-defined spec text.
> Concern: If an index operator arrives later, that change must reopen this lint's operand rule.
>
> Q2d. (C)
> Reasoning: Every rewrite on the table changes runtime meaning, and `x != x` can be a typo for `x != y`. In that case an automatic `is_nan()` rewrite hides the real bug. So `blink fix` must apply only rewrites that keep meaning, and these do not. I support web's condition: the help: line, and the JSON diagnostic, must carry the exact replacement text (`x.is_nan()`, `!x.is_nan()`).
> Concern: Agent loops that run only `blink fix` and do not read diagnostics leave the dead NaN check in place.

- **DevOps:**

> DevOps Phase D re-vote, [this ticket]
>
> Q2c: (i) the same local, parameter or field path, written the same way; no calls, no indexing
> Reasoning: Blink has no index operator (E0313, 02_syntax.md:379), and "An index is not a place" (02_syntax.md:2942), so (ii) names a form that no valid program contains. The ported array case becomes either `.get(i)`, which is a call and excluded under both options, or a `let v = ...` binding, which (i) already catches (sys and web). A lint rule must not teach readers or models syntax that the parser rejects.
> Concern: If an index operator comes in later, that change must bring this lint under review, as W0706 does for patterns.
>
> Q2d: (C) suggested fix only, never applied by the automatic `blink fix`; `<` / `>` get help "always false" with no rewrite
> Reasoning: Every rewrite on the table changes runtime behaviour, and aiml's typo case (`x != x` written for `x != y`) shows that an automatic rewrite can bury a real bug behind code that looks correct. `blink fix` must apply only rewrites that keep behaviour, the same rule as rustc MachineApplicable versus MaybeIncorrect and ESLint `--fix` versus suggestions. I second web's condition and ask that it be recorded in the ruling: the `help:` line, and the JSON diagnostic, must carry the exact replacement text (`x.is_nan()`, `!x.is_nan()`), so a person or a model can apply it in one edit.
> Concern: Agents that read only `blink fix` output, and never the diagnostics, will leave the dead NaN check in place.

- **AI/ML:**

> AI/ML seat, Phase D re-vote on [this ticket]
>
> Q2c: (i)
> Reasoning: Blink has no index operator (E0313, sections/02_syntax.md:379, :2942), so (ii) names a form that valid code cannot contain. A lint rule that names rejected syntax would teach models that `xs[i]` is valid Blink, which harms training data. A ported array NaN test becomes `let v = xs.get(i).unwrap()` then `v != v`, and (i) already catches that.
> Concern: `xs.get(i).unwrap() != xs.get(i).unwrap()` written inline slips through, because both options exclude calls.
>
> Q2d: (C)
> Reasoning: Every rewrite on the table changes runtime behaviour, and `x != x` can be a typo for `x != y`. In that case an automatic `is_nan()` rewrite hides the real bug behind code that looks correct. A fix that `blink fix` applies with no review must keep behaviour the same. I support web's condition: the `help:` line (and the JSON diagnostic) must carry the exact replacement text (`x.is_nan()`, `!x.is_nan()`), so a model that reads diagnostics repairs the code in one edit.
> Concern: Agent loops that apply only `blink fix` output and ignore warnings will leave the dead NaN check in place.

- **Minimalism:**

> Min, Phase D re-vote on [this ticket]
>
> Q2c: (i) local, parameter, or field path; no calls, no indexing
> Reasoning: Blink has no index operator (E0313 NoIndexOperator; "An index is not a place", 02_syntax.md:2942), so (ii) names a form valid code cannot contain. A rule must not describe syntax the language rejects, or it teaches models that `xs[i]` is Blink. The real ported form, `let v = xs.get(i).unwrap()` then `v != v`, is already caught by (i), as sys and web note.
> Concern: If an index operator ever arrives, that change must reopen this lint, or the rule goes quietly stale.
>
> Q2d: (C) suggested fix only, never applied by `blink fix`; help: line carries the exact replacement text
> Reasoning: Every rewrite on the table turns a dead branch into a live one, and aiml's typo case (`x != x` meant as `x != y`) means intent is not known. One simple rule lasts: `blink fix` applies only behavior-keeping rewrites. I support web's condition that the help: line holds the exact replacement (`x.is_nan()` / `!x.is_nan()`), so a model or a person repairs it in one edit.
> Concern: Agent loops that apply only `blink fix` and ignore warnings leave the dead NaN check in place.


Uncontested in round 1, recorded and not voted: the name `FloatSelfComparison` with the next free W07xx code (W0707); a warning by default, with the usual `--strict` and `[lints]` promotion; the explain text names `!(x >= 0.0)` as the NaN guard that the lint cannot see; the help names `is_nan()`, not `x.ieee_eq(x)`; no codegen or runtime change. Out of the ruling as chores or bugs: the false IEEE claim at sections/06_tooling.md (`assert_close` NaN policy), the stale E1400 "NaN-inequality" text, interpolation that prints NaN as `-nan` and `1.0` as `1`, LSP hover, and a new ticket title without the `-0.0` half.

The owner signed off on this tally.

### Follow-up: the NaN test

The vote assumed that `x.is_nan()` is part of the language. sections/ did not define it. The only NaN test the spec defined was `!x.ieee_eq(x)`. The implementation had a free function `std.float.is_nan` and a trait `FloatPure` with `is_nan`, for `Float` only: with no import, `x.is_nan()` was `UnresolvedMethod`, and on `F32` it did not resolve. The owner's stance: the spec is the blueprint and may lead the compiler. The same six seats answered one question: what the spec should say about a NaN test on `Float` and `F32`.

#### Phase A — Independent proposals

All six proposed the same core: `is_nan` as a built-in method on `Float` and `F32`, `fn(self) -> Bool`, no import, with the law `x.is_nan() == !x.ieee_eq(x)`, and the voted W0707 help unchanged.

- **Systems:**

> Systems seat: make is_nan a built-in method on Float and F32, with no import, in a "Float Classification" table next to Float Bits.
>
> Proposal
> - The spec defines `is_nan`, `is_infinite` and `is_finite` as built-in methods on both `Float` and `F32`, `fn(self) -> Bool`, with no import. They go in the same kind of table as *Float Bits* (to_bits / from_bits / is_sign_negative).
> - Laws: `x.is_nan()` == `!x.ieee_eq(x)`. `x.is_finite()` == `!x.is_nan() && !x.is_infinite()`. Exactly one of nan / infinite / finite is true.
> - Keep the voted help text unchanged: `x != x` -> `x.is_nan()`. Now it names a spec-defined method that works on both types the lint fires on, with no import.
> - std.float's free `is_nan` and the `FloatPure.is_nan` trait method become redundant. File a chore to remove them (or keep the free fn as a plain wrapper). A trait method with the same name as a built-in should not exist; it is two dispatch paths for one predicate.
> - No `is_normal` / `is_subnormal` / `classify` now (YAGNI). to_bits covers the rare user who needs them.
>
> ```blink
> fn mean(xs: List[F32]) -> Option[F32] {
>     let mut sum: F32 = 0.0
>     for x in xs {
>         if x.is_nan() { return None }
>         sum = sum + x
>     }
>     Some(sum / xs.len().to_f32())
> }
> ```
>
> Tradeoffs (what the hardware sees)
> - `is_nan` lowers to C `x != x` (or `isnan`), one `ucomisd` + parity branch. Zero cost; no call, no trait dispatch. As a built-in, the compiler emits it inline for both widths. A std trait impl per width is two impls to keep in sync, and the F32 one is missing today: proof that the library route drifts.
> - `is_infinite` / `is_finite` cost one compare against the bit mask (or C `isinf`/`isfinite`). Same cost class. I include them because the lint's sister cases (overflow checks, `x - x != 0` tricks) are how C users test finiteness, and a user who learns `is_nan` will reach for `is_finite` next. If the panel wants the minimum, `is_nan` alone fills the gap; I would still vote for the three.
> - A built-in "needs no import" rule is already the precedent for scalar bit methods; NaN tests are more common than to_bits.
>
> Cross-language
> - Rust: `f64::is_nan`, `is_infinite`, `is_finite` are inherent methods on both f32 and f64, no import.
> - Zig: `std.math.isNan` (library, generic over width). Go: `math.IsNaN` (library, f64 only, so f32 needs a cast).
> - C: `isnan` is a type-generic macro in <math.h>.
> Rust's shape (inherent, both widths) fits Blink best, because Blink already puts to_bits / is_sign_negative there.

- **Web/Scripting:**

> Web/Scripting: make `is_nan()` a built-in method on Float and F32, no import, defined in the spec next to `is_sign_negative`. Keep the voted help text as is.
>
> **Proposal**
> - Add a short *Float Predicates* table under *Float Bits* (or in it): `is_nan`, `is_infinite`, `is_finite`, each `fn(self) -> Bool`, on both `Float` and `F32`, no import. Same rule as `to_bits` and `is_sign_negative`.
> - Law: `x.is_nan() == !x.ieee_eq(x)`. `x.is_finite()` is true when x is not NaN and not infinite.
> - The "Differences from IEEE 754" block says: to test for NaN, use `x.is_nan()`. Do not compare a value to itself.
> - `std.float.is_nan` and `FloatPure.is_nan` are library and implementation matters. They must not be the path the lint help names. That cleanup is a chore, not spec text.
>
> ```blink
> fn safe_mean(xs: List[Float]) -> Option[Float] {
>     let m = xs.sum() / xs.len().to_float()
>     if m.is_nan() || !m.is_finite() {
>         return None
>     }
>     Some(m)
> }
>
> fn check(y: F32) -> Bool {
>     !y.is_nan()
> }
> ```
>
> **Tradeoffs**
> - Help text that names a method the user cannot call without an import is the worst outcome. The user copies the fix, gets UnresolvedMethod, then gets UnusedImport when they add the import. That is two Stack Overflow questions from one warning. A built-in method fixes both.
> - `!x.ieee_eq(x)` is correct but nobody writes it. A JS or Python dev reads it as a puzzle. `is_nan()` needs no explanation.
> - Why add `is_infinite` and `is_finite` now: they are the next two questions after "how do I test NaN". Every language that has one has all three. They cost three table rows. If the panel wants the smallest change, `is_nan` alone is enough to close the gap; I would still vote for all three.
> - F32 must get the same set. A lint that fires on F32 and names a method F32 does not have is a bug in the spec.
>
> **Cross-language**
> - JS: `Number.isNaN(x)`, `Number.isFinite(x)`; the global `isNaN` coerces and is a known trap.
> - Python: `math.isnan`, `math.isinf`, `math.isfinite`, all need `import math`, a common beginner snag.
> - Rust: `x.is_nan()`, `is_infinite()`, `is_finite()` as inherent methods on f32 and f64, no import.
> - Kotlin: `x.isNaN()`, `isInfinite()`, `isFinite()`, no import.
> Rust and Kotlin match Blink's method-call style and the "no import" rule of *Float Bits*. Copy them.

- **PLT:**

> PLT seat: make is_nan() a built-in method on Float and F32, defined by one law over ieee_eq; keep the voted help text.
>
> **Proposal.** Add one row to a built-in predicate table next to *Float Bits*. Like to_bits, the method needs no import:
>
> | Method | Float | F32 | Returns |
> |---|---|---|---|
> | is_nan | fn(self) -> Bool | fn(self) -> Bool | true exactly when the value is a NaN |
>
> The spec states it as a law, not as a new primitive:
> - **NaN test.** `x.is_nan() == !x.ieee_eq(x)` for all x. Under the total order, `x.is_nan()` is also `x == Float.NAN`, but the spec should define it through ieee_eq, because that is the IEEE predicate.
>
> The spec must also say that `ieee_eq` is defined on F32. *Float Total Ordering* names only Float today, but W0706 and W0707 fire on F32. Without that sentence, the law has no meaning for F32.
>
> ```blink
> fn mean(xs: List[Float]) -> Option[Float] {
>     let m = xs.fold(0.0, fn(a, b) { a + b }) / xs.len().to_float()
>     if m.is_nan() { None } else { Some(m) }
> }
> ```
>
> **Why built-in, not std.float.** The lint fires with no import in scope. Help text must name something that resolves in that scope, or the help is a lie. Under the total order, `==` cannot test for NaN. That makes is_nan a primitive observation that the language must give, the same as is_sign_negative, which `==` also cannot see.
>
> **Coherence.** If is_nan is built in, std.float's FloatPure.is_nan becomes a second method with the same name on the same receiver. That is an ambiguous method resolution. Remove is_nan from FloatPure (a chore). Keep the free fn std.float.is_nan, or make it call the built-in. Also file the UnusedImport probe as a bug.
>
> **Related predicates: no.** is_infinite and is_finite can be written with ==: `x == Float.INFINITY || x == -Float.INFINITY`. They are conveniences, not gaps, so leave them out (YAGNI). If a later ticket adds them, they go in the same table.
>
> **Help text:** keep it as voted: `x != x` -> `x.is_nan()`, and `x == x`, `<=`, `>=` -> `!x.is_nan()`.
>
> **Cross-language.** Rust (f32/f64::is_nan), Haskell (isNaN in RealFloat) and OCaml (Float.is_nan) all define it on every float width, with no import. Rust and OCaml define it as `x != x`, which is the ieee_eq law above.
>
> [Idle note from plt: "My message also said that under the total order `x.is_nan()` equals `x == Float.NAN`. I did not check that the spec defines a `Float.NAN` constant. If it does not, that one sentence should go; the rule above does not depend on it."]

- **DevOps:**

> DevOps/Tooling: make is_nan() a built-in method on Float AND F32, no import, in the Float Bits table. Keep the voted help text as is.
>
> **Proposal**
> Add one row to the *Float Bits* table (sections/03_types.md:3719), next to is_sign_negative:
>
> | `is_nan` | `fn(self) -> Bool` | `fn(self) -> Bool` | `true` exactly when the value is a NaN, any sign or payload |
>
> Law: `x.is_nan() == !x.ieee_eq(x)`. Then the "Differences from IEEE 754" block points to is_nan() as the NaN test, and to ieee_eq as the IEEE equality.
>
> ```blink
> fn mean(xs: List[Float]) -> Option[Float] {
>     let m = xs.sum() / xs.len().to_float()
>     if m.is_nan() { return None }
>     Some(m)
> }
>
> fn check(v: F32) -> Bool {
>     !v.is_nan()   // F32 too, no import
> }
> ```
>
> std.float: drop `is_nan` from the FloatPure trait. Keep or deprecate the free fn `is_nan(x)` for testing.bl, but there must be one method path, not two.
>
> **Tradeoffs from tooling**
> - A suggested fix that does not compile is the worst diagnostic we can ship. Today, `x != x` -> `x.is_nan()` turns a warning into error[UnresolvedMethod] (or, with `import std.float`, a bogus UnusedImport). On F32 it never resolves. W0707 fires on F32, so the target must exist on F32. Built-in and no import is the only form where the JSON replacement is correct with no extra edit. Help text that also adds an import is a multi-edit fix. That is more surface and more ways to fail.
> - LSP: `x.` then "nan" must give one completion. A built-in plus a trait method with the same name gives two entries and an ambiguity risk in method lookup. That is why the trait method goes.
> - Do not change the help to `!x.ieee_eq(x)`. Both spell correctly, but `x != x` -> `!x.ieee_eq(x)` swaps one puzzle for another. Users search for "is_nan". Every other toolchain teaches that name.
> - is_finite / is_infinite: not needed for this lint. YAGNI, leave them for a separate ticket.
> - Side gap: the spec text gives ieee_eq on Float only, but W0706 and W0707 cover F32. State that ieee_eq exists on F32 too, in the same edit.
>
> **Cross-language**
> Rust f32/f64::is_nan and Go math.IsNaN need no import beyond what the language gives. rust-analyzer's clippy `eq_op` / `float_cmp` help names `is_nan()` directly. TypeScript's `Number.isNaN` is global. No one makes users import a NaN test.

- **AI/ML:**

> AI/ML seat: make `is_nan()` a built-in method on Float and F32, with no import, listed in the spec next to `is_sign_negative`. Keep the voted help text as it is.
>
> **Proposal**
> - Add one row to the *Float Bits* table (or a small "Float predicates" table just below it): `is_nan` | `fn(self) -> Bool` on Float | `fn(self) -> Bool` on F32 | `true` exactly when the value is a NaN, whatever its sign or payload.
> - Law: `x.is_nan() == !x.ieee_eq(x)`.
> - The *Differences from IEEE 754* block names `is_nan()` as the NaN test and says why `x != x` does not work in Blink.
> - Do NOT add `is_finite` / `is_infinite` here. YAGNI: no lint needs them and no one has asked for them. File them as a separate question if wanted.
> - std.float's free fn `is_nan` and `FloatPure.is_nan` become redundant. That is an implementation chore, not spec text.
>
> ```blink
> fn mean_or_zero(xs: List[Float]) -> Float {
>     let m = xs.sum() / xs.len().to_float()
>     if m.is_nan() { 0.0 } else { m }
> }
>
> fn check(x: F32) {
>     assert(!x.is_nan())   // also works on F32, no import
> }
> ```
>
> **Tradeoffs (AI/ML)**
> - Training data: `x.is_nan()` is the form in Rust, and `isnan`/`isNaN` is the form in C, Python, JS, Go. A model will write `x.is_nan()` first with no prompting. If it needs `import std.float`, the model will leave out the import and get UnresolvedMethod; one more decision point for every NaN check.
> - Built-in with no import is the same rule as `is_sign_negative` and `ieee_eq`. One rule ("Float sign/NaN facts are built-in") is easier to learn from the spec than "some are built-in, one needs an import".
> - The lint help must name something that works where the lint fires. W0707 fires on F32 too, so `is_nan` must exist on F32. Today it does not, so a help line that names it on F32 would be wrong.
> - Token cost: `x.is_nan()` is 4-5 tokens; `!x.ieee_eq(x)` repeats the operand and reads as the same self-compare the lint flags. Bad as help text: a model can copy the pattern to `x.ieee_eq(x)` without the `!`.
>
> **Cross-language:** Rust `f64::is_nan` (inherent, no import), Go `math.IsNaN` (needs import, frequent miss in LLM output), Python `math.isnan` (same). The inherent-method form gives the fewest generation errors.
>
> Also: fix 06_tooling.md:879 in the same chore so `x.is_nan()` there points at the new definition.

- **Minimalism:**

> Minimalism seat: make `is_nan()` a built-in method on Float and F32, with no import. Add nothing else.
>
> **Proposal**
> - Add one row, `is_nan | fn(self) -> Bool | fn(self) -> Bool | true for every NaN, any sign or payload`, to the built-in method table. The *Float Bits* table already holds `is_sign_negative` with no import, so the new row fits there. Another option is to retitle that table "Built-in Float methods".
> - Add one law: `x.is_nan()` is `true` exactly when `!x.ieee_eq(x)`. This defines it in terms of a primitive the spec already has, so the spec gets no new semantics, only a name.
> - Keep the voted help text as it is (`x != x` -> `x.is_nan()`).
> - Do not add `is_infinite`, `is_finite`, `is_normal` or `classify` in this vote. Nobody has asked for them, and no lint help names them. If they are needed later, users can write them with `to_bits` or comparisons, or add them to std.float.
> - Chore (not spec): the `std.float.is_nan` free fn and `FloatPure.is_nan` become redundant. Remove them, or make them forward to the built-in. Then testing.bl calls `left.is_nan()`.
>
> ```blink
> fn mean(xs: List[Float]) -> Option[Float] {
>     let m = xs.sum() / xs.len().to_float()
>     if m.is_nan() { return None }
>     Some(m)
> }
> ```
>
> **Why a built-in, when I would usually say "solve it in a library"**
> - The total order takes away the usual NaN test. In C, Go and JS, `x != x` is the idiom. In Blink it is always `false`, and W0707 flags it. Blink took the test away, so Blink must give one back with the same reach: on every Float, with no import.
> - A lint whose help says "add `import std.float`" is a weak fix. And because of the UnusedImport bug, the advice it gives can itself raise a warning. A built-in has neither problem.
> - This is a foundational primitive, and those clear the bar. Every peer language has it: Rust `f64::is_nan`, Go `math.IsNaN`, Python `math.isnan`, Zig `std.math.isNan`.
> - Its cost is one table row and one law. It adds no syntax, no trait and no type.
>
> **Rejected options**
> - Naming `!x.ieee_eq(x)` in the help: that adds no surface, but the help becomes a puzzle. Users will write a helper for it in every codebase, which spreads the cost. The panel already chose `is_nan()`.
> - Keeping it in std.float only: a NaN test then needs an import, but `ieee_eq` does not. That is the wrong way round, because `is_nan` is the more common of the two.
>
> **Cross-language:** Go keeps `math.IsNaN` in a package, but Go's `x != x` still works, so Go never took the test away. Blink did, so Rust's built-in method is the model to follow.


#### Phase B — Debate (round 1)

Variations: V1, `is_infinite` and `is_finite` as well (sys, web); V2, a statement that `ieee_eq` is defined on `F32` (plt, devops); V3, where the row goes. sys and web withdrew V1. All six seats signalled "STABLE, ready to vote".

- **Systems:**

> Systems, Phase B round 1.
>
> V1 (related predicates): I drop is_infinite / is_finite. Four seats say YAGNI, and the gap this vote must close is the lint help, which names only is_nan. Cost was never my objection: they are zero-cost, so a later ticket can add them to the same table with no penalty. Final position: is_nan only.
>
> V2 (ieee_eq on F32): yes, in the same edit. The law `x.is_nan() == !x.ieee_eq(x)` has no meaning on F32 unless ieee_eq exists there. It lowers to a 32-bit `ucomiss` the same as the 64-bit form, so this is a spec gap, not a new cost. The spec should also say both methods compile to the IEEE compare of their own width, with no widening of F32 to Float. A widen would be correct for NaN but is a needless convert instruction.
>
> V3 (where the row goes): one row in the existing *Float Bits* table. A second table for one row is noise. is_sign_negative is already a fact about the value, not about bits, so the table already holds predicates. I support min's retitle to "Built-in Float methods" if the editor wants it; I do not need it.
>
> To plt: drop the `Float.NAN` / `Float.INFINITY` sentence. The spec defines no such constants, and the law over ieee_eq does not need them. Whether Blink should have NaN/INFINITY constants is a separate question, not for this vote.
>
> Chores: agree with plt and devops. Remove is_nan from FloatPure, because a built-in and a trait method with the same name on the same receiver is two dispatch paths. Make the free fn std.float.is_nan forward to the built-in, or remove it after testing.bl moves to `left.is_nan()`.
>
> STABLE, ready to vote

- **Web/Scripting:**

> Web/Scripting, Phase B round 1.
>
> **V1 (is_infinite / is_finite): I yield. Add `is_nan` only in this vote.** This question is about closing the lint's help-text gap, and `is_nan` alone does that. Four seats said YAGNI, and I will not hold up the vote over two rows. Two notes:
> - plt's reason does not hold. `x == Float.INFINITY` is not something users can write, because the spec has no `Float.INFINITY` (see the digest fact). Today a user must write `x == 1.0 / 0.0`, and no JS or Python dev will guess that. So these are real gaps, not conveniences.
> - Please file a follow-up for `is_infinite` / `is_finite` and the missing `Float.NAN` / `Float.INFINITY` constants. They belong together, so the follow-up should handle them as one group.
>
> **V2 (ieee_eq on F32): yes, in the same edit.** plt and devops are right. The law `x.is_nan() == !x.ieee_eq(x)` has no meaning for F32 unless `ieee_eq` exists there. W0706 and W0707 fire on F32, so their help must work on F32.
>
> **V3 (where): add a row to the existing *Float Bits* table and retitle it "Built-in Float methods" (min's option).** A user who looks for "what can I call on a Float with no import" should find one table, not two. The current title hides `is_sign_negative` and `is_nan`, because neither one is about bits. If the owner wants to keep the "Float Bits" title, then a row in that table is still better than a second table.
>
> No other disagreements. Plt's `Float.NAN` sentence should go, as plt said.
>
> STABLE, ready to vote

- **PLT:**

> PLT, round 1: is_nan only, the F32 ieee_eq sentence must be in the same edit, and one table retitled "Built-in Float methods".
>
> **Retraction.** My Phase A text used `Float.NAN` and `Float.INFINITY`. The spec defines neither, so drop both sentences. The law over ieee_eq does not need them.
>
> **V1: is_nan only (against sys and web).** The retraction makes this stronger. To define `is_infinite` you must refer to infinity, and the spec has no infinity constant. The law would have to use `1.0 / 0.0` or a bit mask through to_bits. Either way, this vote picks up a second question: should Float and F32 get NAN/INFINITY constants? That is a separate design question. is_nan has a clean definition from a primitive the spec already has: `!x.ieee_eq(x)`. Also, the total order removed the only NaN test that ==` can express, so the language owes users is_nan. It removed nothing for infinity, so the language owes no infinity test. File is_infinite, is_finite and the constants as one follow-up ticket, so they are designed together. sys and web both said is_nan alone closes the gap, so we agree on the floor.
>
> **V2: required, not optional.** The law `x.is_nan() == !x.ieee_eq(x)` has no meaning on F32 unless the spec defines `ieee_eq` on F32. W0706 and W0707 already fire on F32. Add the sentence to *Float Total Ordering* in this edit. I agree with devops.
>
> **V3: indifferent on the place; I take min's form.** Add the row to the existing table and retitle it "Built-in Float methods". Also change the lead sentence, which now says "three built-in methods that read and write the IEEE 754 bit pattern". is_nan reads no bit pattern; its definition goes through ieee_eq. One table keeps one "no import" rule for every built-in scalar method, which is simpler than two tables.
>
> **Chores:** I agree with all of them: remove or forward FloatPure.is_nan (two methods with one name on one receiver is ambiguous), move testing.bl to `left.is_nan()`, fix 06_tooling.md:879, and file the UnusedImport bug.
>
> STABLE, ready to vote

- **DevOps:**

> DevOps/Tooling, Phase B round 1: is_nan only; yes to ieee_eq on F32; one row in the existing Float Bits table.
>
> **V1: is_nan only.** I judge a feature by its diagnostic surface. The W0707 help names is_nan, and no diagnostic names is_infinite or is_finite. sys and web both said is_nan alone closes the gap. Adding the other two later is cheap and does not break anything. Today they would add two hover docs, two completions and two conformance rows that nothing points to. To sys and web: the "next question" argument is good for a later ticket, not for this one. Note that plt's example `x == Float.INFINITY` uses a constant the spec does not define. So if a later ticket adds is_finite, it should settle the infinity constants in the same ticket.
>
> **V2: yes.** Say in the same edit that ieee_eq is defined on F32. W0706's label already names ieee_eq, and W0706/W0707 fire on F32. Without that sentence, the law `x.is_nan() == !x.ieee_eq(x)` means nothing on F32, and `blink explain W0706` shows a method that F32 does not have.
>
> **V3: a row in the existing Float Bits table.** For tooling, one table means one anchor. Hover docs, `blink explain W0707` and the "Differences from IEEE 754" block link to the same place as is_sign_negative. A one-row table is noise. I have no objection to min's retitle to "Built-in Float methods", but it is not needed.
>
> **Other seats:** plt's `x.is_nan()` is also `x == Float.NAN` sentence must go, because the spec defines no Float.NAN. This is the same failure we are fixing: text that names something undefined.
>
> STABLE, ready to vote

- **AI/ML:**

> AI/ML, Phase B round 1.
>
> V1 (related predicates): `is_nan` only in this vote. To sys and web: from the model side, you have a point. A model trained on Rust or Kotlin will write `x.is_finite()` and get UnresolvedMethod. But that is a separate gap. It is not part of making the lint help name a defined method. Fold it in here and this vote turns into a float-API design vote. I would back a separate ticket for `is_finite` / `is_infinite` on both widths, and I would vote yes on it.
>
> V2 (`ieee_eq` on F32): yes, in the same edit. The law `x.is_nan() == !x.ieee_eq(x)` must hold on F32, and W0706/W0707 fire on F32. If the spec says `ieee_eq` exists on Float only, a model that learns from the spec alone will think the F32 law is undefined. Writing one sentence now costs less than that confusion later.
>
> V3 (where the row goes): one row in the existing table, and rename the table "Built-in Float methods" (min's option). For retrieval, one table that lists every Float/F32 method with no import beats two small tables. A model, or `blink llms --topic`, gets the full set in one place. If `ieee_eq` moves into that table too, all the no-import methods sit in one list. I would like that, but I do not insist.
>
> Also: plt's `Float.NAN` / `Float.INFINITY` sentence must not reach the spec. The spec does not define those names, and an example that uses an undefined name teaches models to call something that does not exist. plt has already agreed to drop it.
>
> STABLE, ready to vote

- **Minimalism:**

> Minimalism, Phase B round 1: V1 is_nan only; V2 yes; V3 a row in the existing table.
>
> **V1: is_nan only.** Both sys and web say `is_nan` alone closes the gap, and this gap is the whole reason we reopened. The total order took away `x != x`, so the language owes users a NaN test. It took nothing away from infinity tests: `x == 1.0 / 0.0 || x == -1.0 / 0.0` works today. plt's version uses `Float.INFINITY`, which the spec does not define, but the point still holds when written with `1.0 / 0.0`. So `is_infinite` and `is_finite` are conveniences, not gaps. They also do not belong in a follow-up to a lint vote. Anyone who wants them can file a separate type:spec ticket and run it through the panel on its own merits. Web says "every language that has one has all three", but Go's math package already shows that a NaN test can come first and alone.
>
> **V2: yes, state that ieee_eq exists on F32.** This adds no surface. It fixes a gap: W0706 and W0707 already fire on F32, and the is_nan law means nothing for F32 without it. It is one clause in the same edit.
>
> **V3: a row in the existing *Float Bits* table.** A new table holding one row is structure with nothing to carry. `is_sign_negative` already sits there and is a predicate too. If the title bothers anyone, rename it to "Float Bits and Predicates". If V1 passes with three predicates, a separate table is fine.
>
> **Answers to other seats:**
> - plt: drop the `Float.NAN` sentence. The spec has no such constant, and plt agrees it should go.
> - I agree with devops and plt that `is_nan` must leave the `FloatPure` trait in the chore, so a receiver has one method path, not two.
>
> STABLE, ready to vote


#### Phase C — Final vote

| Question | Result | Tally |
|---|---|---|
| QN1. The NaN test | YES: built-in `is_nan` on `Float` and `F32`, `fn(self) -> Bool`, no import, law `x.is_nan() == !x.ieee_eq(x)`; W0707 help unchanged; no `is_infinite`/`is_finite` here | 6-0 |
| QN2. `ieee_eq` on `F32` | YES, stated in the same edit | 6-0 |
| QN3. The table heading | (a) retitle it "Built-in Float methods" | 5-1, Minimalism dissent for (b) |

Each seat's ballot, verbatim:

- **Systems:**

> Systems, Phase C vote.
>
> QN1: YES
> Reasoning: the total order took away `x != x`, so the language must give back a NaN test that reaches as far: every Float and F32, with no import. A built-in compiles to one IEEE self-compare (ucomisd/ucomiss + parity) inline, with no call or trait dispatch. The law over ieee_eq defines it with no new semantics.
> Concern: the std.float trait method with the same name is still there until the chore lands, so method lookup could pick the wrong path or report ambiguity.
>
> QN2: YES
> Reasoning: the is_nan law means nothing on F32 unless ieee_eq exists there, and W0706/W0707 already fire on F32. It is a 32-bit IEEE compare, so it is a spec gap, not a new cost.
> Concern: an implementation could widen F32 to Float to share one code path. That is correct for NaN but adds a needless convert; the codegen chore should use each width's own compare.
>
> QN3: (a) "Built-in Float methods"
> Reasoning: I said a retitle was not needed, but once the lead sentence stops calling every method a bit-pattern method, the heading should match what the table holds. A correct heading costs nothing at runtime and helps the reader find is_nan. I do not object strongly to (b).
> Concern: other sections cite *Float Bits* by name (for example *Float Total Ordering* and §3.2.3), and a retitle that misses one leaves a dead cross-reference; the edit must rg for every "Float Bits" mention.

- **Web/Scripting:**

> Web/Scripting, Phase C votes.
>
> QN1: YES
> Reasoning: `x.is_nan()` is the name that every JS, Python, Rust and Kotlin dev searches for, and with no import it works the first time they copy the lint's help. It makes the help text true on both types that W0707 fires on. One table row clears up what would otherwise be a common "why does x != x not work" question.
> Concern: until the implementation catches up, `is_nan` resolves only on Float with an import, and F32 does not have it at all. So the spec promises something the compiler does not yet deliver, and users who copy the help get UnresolvedMethod. The chore should ship soon.
>
> QN2: YES
> Reasoning: the law that defines `is_nan` means nothing on F32 unless `ieee_eq` exists there. The lints fire on F32, so every method their help names must exist on F32 too. A user should never have to ask "does this work on F32?"
> Concern: the spec gains an F32 method that the compiler may not have yet, which is one more spec-to-compiler gap to track.
>
> QN3: (a) "Built-in Float methods"
> Reasoning: a dev who wants to know what they can call on a Float with no import looks for a heading that says exactly that. "Float Bits" hides `is_sign_negative` and `is_nan`, which are not about bits, and (c) still points readers at bits first. A general heading also leaves room for `is_infinite` / `is_finite` later without another rename.
> Concern: a general title may invite readers to think that this table lists every Float method (such as `to_string` and the arithmetic traits). The lead sentence should say it covers the IEEE 754 inspection methods.

- **PLT:**

> PLT votes: QN1 YES, QN2 YES, QN3 (a).
>
> QN1: YES
> Reasoning: The total order made `x != x` always false, so it removed the only NaN test that the comparison operators can express. The language must give one back, and it must work in the scope where the lint fires, which has no import. The law over ieee_eq defines is_nan through a primitive the spec already has, so it adds a name, not new semantics. Leaving out is_infinite and is_finite keeps this ruling free of the open question about infinity constants.
> Concern: If the chore is late, FloatPure.is_nan and the built-in are two methods with one name on one receiver, and method resolution is ambiguous until the chore removes it.
>
> QN2: YES
> Reasoning: Without it, the law `x.is_nan() == !x.ieee_eq(x)` has no meaning on F32. W0706 and W0707 already fire on F32 and name ieee_eq. The spec must define every operation that a rule uses, for every type the rule covers.
> Concern: An implementation could compute F32 ieee_eq by widening to Float. That gives the correct result for the NaN test, but it hides a missing per-width method, so tests must call ieee_eq on F32 directly (this is sys's note).
>
> QN3: (a) "Built-in Float methods"
> Reasoning: The heading should name what all the rows have in common: built-in, no import, on both widths. "Bits" no longer says that once is_nan is a row. With (c), the heading would grow each time a new kind of method joins the table.
> Concern: Other sections refer to "*Float Bits*" by name, for example *Float Total Ordering* and the help text for bitwise operators. The edit must update every one of those references, or they point to a heading that no longer exists.

- **DevOps:**

> DevOps/Tooling, Phase C vote.
>
> QN1: YES
> Reasoning: Only a built-in method with no import makes the W0707 replacement text compile as given, on both types the lint fires on. One method path gives one completion and one hover, with no ambiguity between the built-in and a trait method. Leaving out is_infinite and is_finite keeps the change to the surface that a diagnostic points to.
> Concern: Until the FloatPure chore lands, the built-in and `FloatPure.is_nan` share a name on Float. If the compiler implements the built-in first, a user with `import std.float` could hit an ambiguity or a wrong-path resolution. The chore must land in the same slice as the built-in.
>
> QN2: YES
> Reasoning: W0706's label already names ieee_eq, and both lints fire on F32. Without this sentence, the is_nan law and `blink explain W0706` name a method F32 does not have in the spec.
> Concern: Someone may write the F32 sentence as "the same as Float" and leave the width open. It must say that F32 compares at binary32, with no widening.
>
> QN3: (a) "Built-in Float methods"
> Reasoning: I said "not needed" in round 1, but the lead sentence is being rewritten anyway, and the heading is what docs search and `blink llms --topic` match on. A user who looks for a NaN test does not look under "Bits". This heading names what the table holds and still fits if the follow-up ticket adds is_finite or is_infinite.
> Concern: *Float Bits* is a cross-reference target today (Float Total Ordering, §3.2.3 bitwise help, W0706 text). Each reference must change in the same edit, or the spec will point to a heading that no longer exists.

- **AI/ML:**

> AI/ML seat, Phase C ballot.
>
> QN1: YES
> Reasoning: `x.is_nan()` is the form models already write first (Rust, Kotlin), so the help text and the code a model writes on its own become the same thing. No import means no extra decision point and no UnresolvedMethod on the first try. The law over `ieee_eq` lets a model work out what it means from the spec alone.
> Concern: models will also write `x.is_finite()` / `x.is_infinite()` and get UnresolvedMethod until the follow-up ticket lands, so that ticket must not stall.
>
> QN2: YES
> Reasoning: the lint fires on F32, and the `is_nan` law uses `ieee_eq`. A model that learns from the spec alone needs `ieee_eq` stated on F32, or the F32 law reads as undefined. It costs one sentence.
> Concern: if the sentence goes only in *Float Total Ordering* and not in the method table, the F32 signature is not stated in the place a model looks.
>
> QN3: (a) "Built-in Float methods"
> Reasoning: a heading that names what the table lists, the methods that need no import, helps retrieval. A model or `blink llms --topic` looking for "what methods does Float have" finds it at once. "Float Bits" hides `is_nan` under a heading about bit patterns. (c) will need a new name each time a non-bit, non-predicate method arrives.
> Concern: the heading says "Float", so state in the lead sentence that every row covers F32 too, or a reader may think the methods are Float-only.

- **Minimalism:**

> Minimalism, Phase C votes: QN1 YES, QN2 YES, QN3 (b).
>
> QN1: YES
> Reasoning: The total order took away the `x != x` NaN test, so the language must give one back, in the same scope where the lint fires. That makes this a foundational primitive, and those clear the bar. It costs one table row and one law, and it adds no new meaning, because the law defines it through `ieee_eq`.
> Concern: The follow-up ticket may use this to push `is_infinite`, `is_finite` and the constants through as "the obvious set", when each needs to make its own case.
>
> QN2: YES
> Reasoning: This fills a gap and adds no surface. W0706 and W0707 already fire on F32, and the `is_nan` law means nothing for F32 unless `ieee_eq` exists there.
> Concern: If the edit is written badly, a reader may think F32 `ieee_eq` widens to Float, so the text should say it uses the F32 compare (sys's note).
>
> QN3: (b) keep "Float Bits"
> Reasoning: I change my position from rounds A and B. Least churn wins here. "*Float Bits*" is a cross-reference target at sections/03_types.md:3702 and :4805, and at three src comments (typecheck.bl:17247, :17517, :24800; cg_call.bl:4847). Renaming the heading means editing all of these, for no change in what the spec means. plt's fix to the lead sentence already removes the false claim that every method there is a bit-pattern method. `is_sign_negative` already sits under this heading, so the heading has never been a strict promise.
> Concern: If the follow-up ticket adds more predicates, the heading will get too narrow, and the rename will cost the same then.


The owner signed off on this tally.

### AI-first review

Learnability, consistency, generability, debuggability and token efficiency: all five pass for both rounds. The total order stays, and W0707 catches the one prior that breaks without a sound (`x != x`). `is_nan` is the name every common language uses.

### Final Spec

```blink
fn check(x: Float) -> Result[Float, Str] {
    if x.is_nan() { return Err("nan") }    // built-in, no import; also on F32
    if x < 0.0 { return Err("negative") }
    Ok(x)
}

fn main() {
    let nan = 0.0 / 0.0
    assert(nan == nan)            // total order
    assert(!nan.ieee_eq(nan))     // IEEE equality
    assert(nan.is_nan())
    if nan != nan {               // warning[FloatSelfComparison]: always false
        io.println("never")
    }
}
```

- `Float` and `F32` keep the total order: `NaN == NaN`, NaN is the greatest value, `-0.0 == 0.0` (§3 *Float Total Ordering*).
- §3 *Differences from IEEE 754* lists the four NaN differences, the clamp example and the `x >= lo` line, and names `ieee_eq`, `is_nan()` and W0707.
- `ieee_eq` is defined on `F32` as well as `Float`; each type compares at its own width.
- `FloatSelfComparison` (W0707), a warning: any of the six operators on `Float`/`F32` whose operands are the same local, parameter or field path, written the same way. No calls, no indexing. A future index operator must decide whether an indexed operand matches.
- `<` and `>` get an "always false" message with no NaN reason and no rewrite. `!=` suggests `x.is_nan()`; `==`, `<=` and `>=` suggest `!x.is_nan()`. The fix is a suggestion only; `blink fix` never applies it.
- `blink explain W0707` names `!(x >= 0.0)` as a NaN guard that the check does not see.
- No `ieee_lt`, `ieee_le`, `ieee_gt`, `ieee_ge` or `partial_cmp`.
- `is_nan` is a built-in method on `Float` and `F32`, in the table retitled *Built-in Float Methods*, with the law `x.is_nan() == !x.ieee_eq(x)`.
- `is_infinite`, `is_finite` and NaN and infinity constants are a separate spec question.
