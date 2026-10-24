[< All Decisions](../DECISIONS.md)

# Float Math Methods and Constants — Design Rationale

The spec has `round`, `floor` and `ceil` on `Float` (§3.2.5) and the four IEEE 754 methods `to_bits`, `from_bits`,
`is_sign_negative` and `is_nan` (*Built-in Float Methods*). It has no `sqrt`, no `pow`, no `abs`, `min` or `max` on a
float, no logarithm, no trigonometry and no float constant. `Float.INF` is used in §6 (`std.testing`) and defined
nowhere. `math.sqrt(2.0)` gives "undefined variable `math`". A user reaches the C math library only through `@ffi`.
The ticket asked for a module name, an MVP list, and a choice between free functions and methods.

## Summary

| Q | Question | Result | Vote |
|---|---|---|---|
| Q1 | `asin`, `acos`, `atan` | A: add them to the method set | 5-1 (Minimalism dissent) |
| Q2 | `hypot` | B: leave it out | 5-1 (Systems dissent) |
| Q3 | `is_infinite` | A: add it; the three class tests split the value set | 6-0 in Phase D (4-2 in Phase C) |
| Q4 | `Float.clamp` | A: add it | 3-3, owner broke tie for A. The owner gave no reason. |
| Q4b | `clamp` with a NaN receiver | B: NaN | 4-2 in Phase D (DevOps and AI/ML dissent) |
| Q4c | `clamp` with a NaN bound | A: panic, as for `lo > hi` | 5-1 (AI/ML dissent) |
| Q5 | `MIN_POSITIVE` | A: the smallest positive normal value | 5-1 (Minimalism dissent) |
| Q6 | `Int.MAX`, `Int.MIN`, sized-integer constants | B: a separate spec question | 6-0 in Phase D (4-1-1 in Phase C) |
| Q7 | Lint for `x == Float.NAN` | B: no lint | 5-1 (AI/ML dissent) |
| Q8 | Help content for `.log()` and `math.sqrt(x)` | A: the spec requires the content, not the wording | 4-2 in Phase D (PLT and Minimalism dissent) |

Five seats put first the same shape in Phase A: math is a set of built-in methods on `Float` and `F32`, with no
import, and constants are type-scoped `const T.NAME` items of the prelude. Minimalism put a small set of free
functions in `std.math` and kept a smaller set of methods, and moved to the shared shape in Phase B. By the end of
Phase B all six agreed on the points the Phase C ballot lists as agreed: every operation is a built-in method; no
free function; `std.math` keeps `BigInt` only and `std.num` gets nothing; one table covers both types and `F32`
does not compute through `Float`; the methods `abs`, `sqrt`, `min`, `max`, `pow`, `exp`, `ln`, `log2`, `log10`,
`sin`, `cos`, `tan`, `atan2`, `is_finite`; no method panics on a domain error; `min`/`max` use the total order;
there is no `log`; the constants `PI`, `E`, `INF`, `NAN`, `MAX`, `EPSILON`; no `MIN`; exact rows and C-math-library
rows; no `Int.sqrt`; `std.float.fabs` goes; the new section is §3.2.6 *Float Math*. The votes below cover the rest.

Earlier, `decisions/float-total-order-reaudit.md` rejected `is_infinite` and `is_finite` as YAGNI and left
`Float.NAN` and `Float.INFINITY` to a later ruling. This ruling reverses the first point (Q3) and settles the second.

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in
independent-proposal, debate, vote rounds. Phase A and Phase B are excerpted from each panelist's own text. Phases C
and D are quoted in full from each panelist's file, without its heading line and its "Files read" line.

#### Phase A — Independent proposals

- **Systems** (`A/sys.md`):

> ## sys-1: built-in methods on `Float` and `F32`, type-scoped constants, no `math` function module

> A second spelling for one operation costs the reader a choice and buys nothing: both lower to the same libm call.

> **Name `ln`, not `log`.** `log` means base 10 in C and base e in Rust, so it invites silent wrong results. Leave `log` unbound; a bare `x.log()` is an error that says "use `ln`, `log2` or `log10`".

> `min`/`max` use the decided total order: `NaN.max(x)` is NaN, `NaN.min(x)` is `x`. For `-0.0` against `0.0` the result is the first operand.

- **Web/Scripting** (`A/web.md`):

> ## web-1: built-in methods and type-scoped constants, no math module

> One rule ("numeric operations are methods") is easier to learn than a split rule.

> There is no `Float.MIN`: JS `Number.MIN_VALUE` is the smallest positive value, which surprises people. Write `-Float.MAX`. Negative infinity is `-Float.INF`.

> Con: JS/Python users first try `Math.sqrt(x)` or `math.sqrt(x)`. The error for `math.sqrt` should say "use `x.sqrt()`".

- **PLT** (`A/plt.md`):

> ## plt-1: built-in `Float`/`F32` methods and type-scoped constants. No `std.math` free functions.

> Rule for all: a `Float` method is pure, has no effect, and never panics. Domain errors give NaN or an infinity as IEEE 754 says.

> Soundness note: only `abs`, `min`, `max`, `sqrt`, `floor`, `ceil`, `round` are exact on every target. For `pow`, `exp`, `ln*`, trig the spec says "result is that of the target C math library; it can differ in the last bit between platforms".

- **DevOps/Tooling** (`A/devops.md`):

> ## devops-1: built-in methods and type-scoped constants, no free-function module

> Judge by the tool surface. `x.` in the LSP lists every method on the type. A free function in a module is only found if the user already knows the module name.

> `clamp` panics if `min > max` or either bound is NaN (as for `Int`); a NaN receiver returns NaN.

- **AI/ML** (`A/aiml.md`):

> ## aiml-1: built-in methods on `Float`/`F32`, type-scoped constants, no math module

> **Rule for the AI:** one place for each operation. If `x` is a number, the operation is `x.name(...)`.

> `lib/std/float.bl` loses `fabs` (it returns `-0.0` for `-0.0`, which breaks the `abs` rule)

- **Minimalism** (`A/min.md`):

> # min-1: Small built-in core, one small `std.math` module, nothing else

> Put an operation on `Float` as a built-in method only if IEEE 754 defines it with one exact result. Then it has the same answer on every platform, which fits the no-fast-math rule (sections/07 :556). Put every other operation in `std.math`.

> `Float.MAX`, `Float.MIN`, `Float.EPSILON` and `Int.MAX` wait until a real program needs them (YAGNI).

#### Phase B — Debate

The debate settled placement, `min`/`max`, `F32` and the `fabs` question. Excerpts, each from the seat named:

- **Minimalism** (`B1/min.md`) moved to methods:

> I change my Phase A position on V1. Five seats want methods, and plt and devops give reasons I cannot answer. One rule ("an operation on a number is a method") is a smaller language than two rules and two places to look.

- **PLT** (`B1/plt.md`) against Minimalism's split by exactness:

> Exactness is also a contract on the result, not a place in the namespace. A second rule ("exact means method, inexact means module") makes the user learn which operations are exact before they can find them. One rule survives: the spec states the accuracy class in the method's row.

- **Web/Scripting** (`B1/web.md`) gave up the JS rule for `min`/`max`:

> I concede. Five seats want agreement with `<`, and the spec already says NaN is equal to itself and above all numbers (03 :4367). One order for `<`, `sort`, `min` and `max` is a simpler rule than my JS match.

- **Systems** (`B1/sys.md`) on `F32`:

> `F32` gets every method, via the `f` variant. I oppose min: compute in `Float` and round back is a double rounding, and it costs a conversion pair per call on hot paths.

- **PLT** (`B1/plt.md`) on build flags:

> `-fno-math-errno`: a build-flag choice, not language text. It belongs in a codegen chore; the spec rule is only "a `Float` operation keeps its IEEE 754 result" (07 :556). Do not put flags in sections/.

- **PLT** (`B1/plt.md`) on the NaN lint:

> devops lint for `x == Float.NAN`: reject its rationale. Under Float total order, `NaN == NaN` is true, so that comparison is correct, not a bug. A lint would contradict the spec. Use `ieee_eq` for IEEE semantics.

- **DevOps/Tooling** (`B1/devops.md`) changed its `clamp` receiver rule:

> aiml is right on the NaN receiver: under the total order NaN is above every number, so `NaN.clamp(lo, hi)` is `hi`. This agrees with `x.max(lo).min(hi)`: NaN.max(lo) is NaN, then NaN.min(hi) is `hi`. I drop my "NaN receiver returns NaN".

- **AI/ML** (`B1/aiml.md`) asked for the help texts to be a requirement:

> The error-help texts for `.log()` and `math.sqrt` should be a spec or diagnostic requirement, not an implementation choice: they are what lets an AI recover from a wrong first guess.

Open after Phase B: the votes Q1 to Q8 below. The ballot also put `Int.MAX` and `Int.MIN` to a vote (Q6).

#### Phase C — Silent ballot

Each seat voted alone. The votes are quoted in full. A ticket ID in a seat's text is replaced by a plain phrase.

##### Q1. `asin`, `acos`, `atan`

Result: A, 5-1 (Minimalism dissent).

- **Systems** — Vote: A
  - Reasoning: Each is one libm call (`asin`, `acosf` and so on), monomorphic, with no hidden cost. plt shows that `atan2(x, 1.0)` is not equal to `atan(x)` for infinite or NaN input, so the rewrite is not a true substitute. A missing name sends a user to `@ffi`, which is worse for the hardware story than three table rows.
  - Concern: If B wins, every user and model that writes `x.atan()` meets `UnresolvedMethod` and must learn an `atan2` workaround that gives different results for edge input.
- **Web/Scripting** — Vote: A
  - Reasoning: Every language a JS or Python developer knows has `atan`. A method that is missing from a list that otherwise matches `<math.h>` shows up as `UnresolvedMethod`, and the user then loses time searching. `atan2(x, 1.0)` is a trap for the 90% case, and plt shows it is not equal to `atan(x)` for infinite or NaN input. Three rows cost little.
  - Concern: Each extra row is a name the compiler, the docs and the model must carry, and nobody may use `acos` for years.
- **PLT** — Vote: A
  - Reasoning: `atan(x)` and `atan2(x, 1.0)` differ for infinite and NaN input, so the rewrite min proposes is not a substitute. Each function is total on `Float` and follows the C result, so each row adds no new rule. The set is complete for the inverse trig family.
  - Concern: Each row adds an accuracy-class entry (C math library) that the spec must keep correct for both `Float` and `F32`.
- **DevOps/Tooling** — Vote: A
  - Reasoning: A missing name shows as `UnresolvedMethod` and the user must search or fall back to `@ffi`. A list that covers the C `<math.h>` core has fewer such errors than a list with holes. plt's point is correct: `atan2(x, 1.0)` is not equal to `atan(x)` for infinite or NaN input, so the rewrite is not a safe hint. The cost is three table rows and three intrinsics.
  - Concern: If B wins, each user who writes `x.atan()` gets a failed compile and the `atan2(x, 1.0)` help text would give a result that differs for infinite and NaN input.
- **AI/ML** — Vote: A
  - Reasoning: A model that knows `sin`, `cos` and `atan2` writes `x.atan()` next. A missing row costs a failed compile and a retry. plt shows that `atan2(x, 1.0)` differs from `atan(x)` for infinite and NaN input, so the workaround is not even equal. Three rows give a complete C `<math.h>` core.
  - Concern: Each added row is one more name to keep in the table forever, and min's argument for on-demand growth gets weaker each time.
- **Minimalism** — Vote: B
  - Reasoning: Each method is a row that the spec, the compiler, the docs and the model must carry for good. A program can write `atan(x)` as `atan2(x, 1.0)` today. plt shows the two differ for infinite and NaN input, but no program in the repo needs that difference. Add the rows when a program needs them.
  - Concern: A model writes `x.atan()` first, gets `UnresolvedMethod`, and wastes a retry in every trig program.

##### Q2. `hypot(self, Self)`

Result: B (leave it out), 5-1 (Systems dissent).

- **Systems** — Vote: A
  - Reasoning: `hypot` is one libm call, and it does not overflow or underflow in the middle of the computation where `(x*x+y*y).sqrt()` does. The user cannot write that safe form in one line. It costs one row and no codegen rule.
  - Concern: If B wins, programs that need overflow-safe lengths silently use the naive form and produce `INF` for large inputs.
- **Web/Scripting** — Vote: B
  - Reasoning: I said in Phase B that I accept its loss. Most web code writes `(x*x+y*y).sqrt()`, and the overflow case is rare in UI, scripting and server code. It is the weakest row and five seats leave it out.
  - Concern: A user with large coordinates gets `INF` from `(x*x+y*y).sqrt()` with no warning, and the spec offers no standard fix.
- **PLT** — Vote: B
  - Reasoning: `hypot` is a derived operation with a one-line definition. The overflow argument is a numerical-quality point, not a typing or soundness point. Leaving it out costs one table row to add later and breaks no program.
  - Concern: A user who writes `(x*x+y*y).sqrt()` gets silent overflow to `INF` where `hypot` would give a finite result.
- **DevOps/Tooling** — Vote: B
  - Reasoning: `hypot` is the weakest row. It adds a name to completion and hover for a case that `(x*x+y*y).sqrt()` covers in most programs. A later ticket can add it as one row if a program needs the overflow safety.
  - Concern: If A wins, the table has a row with a narrow use, and the overflow reason would also justify `cbrt`, `fma` and other rows.
- **AI/ML** — Vote: B
  - Reasoning: A model writes `(x*x + y*y).sqrt()` from training data and it works for common inputs. `hypot` adds a second spelling for the same job, and a model must pick between them. The overflow case is real but rare. Add it when a program needs it.
  - Concern: Users with large or small magnitudes get a silent overflow or underflow from the form models write most often.
- **Minimalism** — Vote: B
  - Reasoning: Four of six seats leave it out, and sys and web hold it only weakly. `(x*x+y*y).sqrt()` is one line. The overflow case is real but rare, and one table row can come later.
  - Concern: A user who writes `(x*x+y*y).sqrt()` gets a silent `INF` for large inputs.

##### Q3. `is_infinite`

Phase C result: A 4-2 (Web/Scripting and Minimalism B). After Phase D: A, 6-0.

- **Systems** — Vote: A
  - Reasoning: It is an exponent-bit test, like `is_nan`, with no libm call. It completes the classification group beside `is_nan` and `is_finite`. The row is nearly free and removes a name a model will guess.
  - Concern: If B wins, users write `!x.is_finite() && !x.is_nan()`, two tests where one suffices.
- **Web/Scripting** — Vote: B
  - Reasoning: I accept its loss. `x == Float.INF || x == -Float.INF` is short and clear, and it is rare in everyday code. `is_finite` covers the common guard.
  - Concern: A model that sees `is_finite` and `is_nan` will write `is_infinite` first and pay one failed compile, which aiml is right to count.
- **PLT** — Vote: A
  - Reasoning: `is_finite`, `is_nan` and `is_infinite` are the IEEE 754 classification predicates and form one group. With `is_infinite` absent, a user must write `!x.is_finite() && !x.is_nan()`, which is easy to get wrong. It needs no libm call and has no domain error.
  - Concern: Another predicate (`is_normal`, `is_subnormal`) will be requested by the same argument, so the group needs a stated boundary.
- **DevOps/Tooling** — Vote: A
  - Reasoning: It sits beside `is_finite` and `is_nan` in completion, so the three classification methods appear as one group. It needs no libm and costs one row. I do not insist.
  - Concern: If B wins, a user who sees `is_finite` and `is_nan` writes `is_infinite`, gets `UnresolvedMethod`, and writes `x == Float.INF || x == -Float.INF`.
- **AI/ML** — Vote: A
  - Reasoning: A model that sees `is_nan` and `is_finite` writes `is_infinite` next. It costs one row and needs no libm. Without it the model gets `UnresolvedMethod` and then guesses an unsafe workaround such as `x == Float.INF`.
  - Concern: It is the weakest-use row, so it may later look like clutter next to `is_finite`.
- **Minimalism** — Vote: B
  - Reasoning: `x == Float.INF || x == -Float.INF` says the same thing. No other seat needs it, and devops does not insist. `is_finite` plus `is_nan` already classify every value.
  - Concern: A model that has seen `is_finite` will write `is_infinite` and hit one avoidable error.

##### Q4. `Float.clamp(self, Self, Self)`

Result: A (add it), 3-3. The owner broke the tie for A. The owner gave no reason.

- **Systems** — Vote: B
  - Reasoning: `x.max(lo).min(hi)` compiles to two inline compares and does the same work. A `clamp` with NaN and bound rules adds a panic path and a check that the identity does not need. The only spec `clamp` example is on `I32`, so there is no float precedent to follow.
  - Concern: If A wins, a `Float.clamp` with a bound check adds a branch and a panic path to a hot-loop operation that users now write with no check.
- **Web/Scripting** — Vote: A
  - Reasoning: `Int` has `clamp`, so a user or model calls it on `Float` first. UI, colour and scroll code in web work clamps floats all the time. Without it `Float` has a hole that `Int` does not, and `x.max(lo).min(hi)` does not panic on `lo > hi`.
  - Concern: The NaN rules add special cases to a method that looks simple, and users will not read them.
- **PLT** — Vote: B
  - Reasoning: `clamp` needs three decisions (NaN receiver, NaN bound, `lo > hi`) that the total order only partly answers. `x.max(lo).min(hi)` already has defined behaviour under the total order. The only `clamp` example in the spec is on `I32`, so there is no precedent for `Float`.
  - Concern: `Int` has `clamp` and `Float` does not, so a user and a model will call it and get `UnresolvedMethod`.
- **DevOps/Tooling** — Vote: A
  - Reasoning: `Int` has `clamp`, so `x.` completion on a `Float` that lacks it looks like a hole, and a user will try it first. `x.max(lo).min(hi)` gives no panic on `lo > hi`, so it hides a caller bug that `Int.clamp` reports. One row, one rule, same panic as `Int`.
  - Concern: If B wins, `Float` and `Int` differ in a method that `Int` has, and the first `UnresolvedMethod` on `clamp` has no good help text.
- **AI/ML** — Vote: A
  - Reasoning: `Int` and the sized integers have `clamp`, so a model will call it on `Float`. The rule "`x.clamp(lo, hi)` equals `x.max(lo).min(hi)` when `lo <= hi`" is one sentence a model can learn from the spec alone. Without the row, `Float` has a hole that `Int` does not.
  - Concern: The NaN cases add spec text that sys and plt wanted to defer, and a wrong NaN rule would be hard to change later.
- **Minimalism** — Vote: B
  - Reasoning: `x.max(lo).min(hi)` already does the job, and it has defined NaN behavior under the total order. `clamp` adds three new special cases (NaN receiver, NaN bound, `lo > hi`) that each need spec text and a vote. The spec's only `clamp` example is on `I32`, so there is no precedent to follow.
  - Concern: `Int` has `clamp` and `Float` does not, so users and models will trip on the gap.

##### Q4b. `clamp` with a NaN receiver (every seat voted, also those who voted B on Q4)

Phase C result: B 4-2 (DevOps and AI/ML A). After Phase D: B, 4-2 (DevOps and AI/ML dissent).

- **Systems** — Vote: B
  - Reasoning: Returning NaN for a NaN receiver passes the problem value through unchanged, as IEEE operations do, and needs no special case in the emitted code. Returning `hi` hides a NaN by turning it into a valid-looking number. That hides a bug in the caller.
  - Concern: If A wins, a NaN input becomes `hi` silently, and a division by zero upstream shows up as a saturated value far from its cause.
- **Web/Scripting** — Vote: B
  - Reasoning: A NaN that goes into `clamp` and comes out as `hi` looks like a real value, so a bug upstream (for example `0.0 / 0.0` in a scroll position) becomes a plausible maximum with no sign of error. NaN in, NaN out is what Rust's `clamp` does and what a JS developer expects from `Math.min`/`Math.max`. The cost is that `clamp` differs from `x.max(lo).min(hi)` for NaN; the spec states it in one line.
  - Concern: If A wins, NaN input silently turns into `hi`, and the bug shows up far from its cause.
- **PLT** — Vote: B
  - Reasoning: A NaN receiver means the input is not a number, and `clamp` should not turn it into a valid value. Returning `hi` hides an error that `is_nan` can detect at the call site. The `max`/`min` identity is a derived property, not a typing rule for `clamp`.
  - Concern: If `clamp` returns NaN, it differs from `x.max(lo).min(hi)`, which returns `hi` for NaN; the two spellings give different results.
- **DevOps/Tooling** — Vote: A (returns `hi`)
  - Reasoning: Under the total order NaN is above every number, so `hi` is the result the order gives. It equals `x.max(lo).min(hi)` for every input, so a user can move between the two spellings with no change in result. I withdrew "returns NaN" in Phase B for this reason. A rule that makes `clamp` and `max`/`min` disagree is a second NaN rule.
  - Concern: If B wins, `x.clamp(lo, hi)` and `x.max(lo).min(hi)` give different results for NaN, and a user who refactors from one to the other changes behaviour with no diagnostic.
- **AI/ML** — Vote: A
  - Reasoning: The total order puts NaN above every number, so NaN `self` gives `hi`. The result agrees with `x.max(lo).min(hi)`, so a model needs only one identity and one NaN rule for `min`, `max` and `clamp`. "NaN gives NaN" would add a special case that breaks that identity.
  - Concern: A caller who expects NaN to propagate gets a normal-looking `hi` and may hide a bug upstream; the spec text must say so in the row.
- **Minimalism** — Vote: B
  - Reasoning: A NaN receiver returns NaN. This is the smaller rule: a NaN receiver passes through unchanged, as it does through `abs`, `sqrt` and `sin`. "NaN gives `hi`" is a new special case with no reason other than the `max`/`min` chain.
  - Concern: `x.clamp(lo, hi)` and `x.max(lo).min(hi)` then differ for NaN, which is the one identity users will expect.

##### Q4c. `clamp` with a NaN bound (every seat voted, also those who voted B on Q4)

Result: A (a NaN bound panics, as does `lo > hi`), 5-1 (AI/ML dissent).

- **Systems** — Vote: A
  - Reasoning: A NaN bound is a programmer error, and an explicit panic is the only predictable outcome. B covers a NaN `lo` through the `lo > hi` test, but a NaN `hi` compares above every number under the total order, so it does not panic and the clamp is silently open on one side. A panics on both bounds in one stated rule.
  - Concern: If B wins, `x.clamp(0.0, Float.NAN)` returns `x` unchanged and never panics, a silent open bound.
- **Web/Scripting** — Vote: A
  - Reasoning: A NaN bound is always a bug, and the panic matches `Int.clamp` for `lo > hi`. A separate rule "NaN bound panics" is easy to explain and to test. aiml's rule hides the case inside the `lo > hi` test, so a reader must work out the total order to see it.
  - Concern: A panic in a UI or server path from a NaN bound that came from user data can take down a request that a NaN result would have survived.
- **PLT** — Vote: A
  - Reasoning: Under the total order a NaN `hi` is above all numbers, so the interval `[lo, NaN]` is not a bounded range, and a NaN `lo` makes `lo <= hi` hold only by the order's convention. An explicit panic states the precondition. The `lo > hi` panic alone leaves NaN `hi` accepted silently.
  - Concern: A panic in a pure `Float` method differs from the no-panic rule for every other `Float` math method.
- **DevOps/Tooling** — Vote: A (panics, as does `lo > hi`)
  - Reasoning: A NaN bound is a caller bug, and a panic names it at the call site. Under the total order `lo > hi` already catches a NaN `lo` but not a NaN `hi` (NaN is above all, so `lo <= NaN`), and then the call returns a NaN-bounded result without a message. An explicit rule is easier to put in the diagnostic text.
  - Concern: If B wins, a NaN `hi` passes the `lo > hi` check silently, and the bug shows up far from the call.
- **AI/ML** — Vote: B
  - Reasoning: One rule is easier to learn: panic if `lo > hi` in the total order. A NaN `lo` is above every number, so that test already catches it unless `hi` is also NaN. A separate "NaN bound panics" clause adds a second decision point for no new case a model will meet.
  - Concern: A NaN `hi` does not panic, so `clamp` then acts as a one-sided `max(lo)` and may hide a bug; five seats prefer the explicit panic and it is the safer failure.
- **Minimalism** — Vote: A
  - Reasoning: A NaN bound is a bug in the caller, and the rule matches `lo > hi`, which already panics. One sentence covers both. Hiding a NaN bound behind the total order gives a silent, confusing result.
  - Concern: A panic in a numeric hot path can crash a program on bad data that IEEE code would pass through.

##### Q5. `MIN_POSITIVE`

Result: A, 5-1 (Minimalism dissent).

- **Systems** — Vote: A
  - Reasoning: The name has one meaning (smallest positive normal), it is one prelude `const`, and it is the value C programs get from `DBL_MIN` and `FLT_MIN`. It is the constant that tells a user where subnormals begin. It costs nothing at run time.
  - Concern: If B wins, a user who needs it writes a bit-pattern literal with `from_bits`, which is harder to read and easy to get wrong.
- **Web/Scripting** — Vote: A
  - Reasoning: The name has one meaning and costs one prelude `const`. It avoids the `MIN` trap, where JS `Number.MIN_VALUE` means smallest positive and Rust `MIN` means lowest.
  - Concern: Almost no web program uses it, so it is a row that few people read.
- **PLT** — Vote: A
  - Reasoning: The name has one meaning: the smallest positive normal value, as in C `DBL_MIN`. Without it, users have no way to name the underflow boundary, and `MIN` stays unbound for the stated reason. It is one `const` per type.
  - Concern: Users may read `MIN_POSITIVE` as the smallest positive subnormal; the spec row must say "normal".
- **DevOps/Tooling** — Vote: A
  - Reasoning: The name has one meaning, and without it users cannot name the smallest normal value except by `@ffi` or a bit pattern. It is one prelude `const` per type. It also gives the `Float.MIN` question a clear answer: `-Float.MAX` for lowest, `MIN_POSITIVE` for the small end.
  - Concern: If B wins, a user looks for `Float.MIN`, finds none, and the help text has no name to point to.
- **AI/ML** — Vote: A
  - Reasoning: The name has one meaning, and it removes the pull toward `Float.MIN`, which Rust, C and JS read three ways. Without it a model has no name for the smallest positive value. One `const` per type.
  - Concern: Rust users may expect `MIN_POSITIVE` to be a normal-only value; the spec must state "smallest positive normal".
- **Minimalism** — Vote: B
  - Reasoning: No program in the repo uses it. `MAX` and `EPSILON` have users (comparison and sentinel values); this one has none yet. It is one `const` to add when a program needs it.
  - Concern: Users who need the smallest normal value will write a magic number or look at `to_bits`.

##### Q6. `Int.MAX`, `Int.MIN` and the sized-integer constants

Phase C result: B 4-1-1 (A: AI/ML; C: Minimalism). After Phase D: B, 6-0.

- **Systems** — Vote: B
  - Reasoning: The constants need a rule for every sized type, so they interact with the sized-integer table and do not belong in a float ruling. `Int.abs` panics on the minimum value and users cannot name it, so the work is real and I want it filed now. It must not slip to C, where nobody files it.
  - Concern: If A wins, a rule for 10 or more integer types lands without the integer table's own review, and a mistake in one width stays in the spec.
- **Web/Scripting** — Vote: B
  - Reasoning: Users need `Int.MAX` often, so I want a ticket filed now. The sized-integer table (signed and unsigned, each width) needs its own rule, and this ruling is about floats. Keeping the ruling on floats keeps it small; a filed ticket keeps the gap from being forgotten.
  - Concern: If the ticket stays open for a long time, `Int.MAX` stays an `ICE` or an error, and every user hits it before `Float.MAX`.
- **PLT** — Vote: B
  - Reasoning: The sized-integer constants interact with the sized-integer table and with the `Int.abs` rule on the minimum value. That is a separate set of types and a separate ruling. This ruling covers `Float` and `F32`.
  - Concern: If the ticket is filed but not scheduled, `Int.abs` keeps a panic case that no user can name.
- **DevOps/Tooling** — Vote: B (separate ticket, filed now)
  - Reasoning: This ruling is about `Float`. The constants need a rule for every sized type, which touches the sized-integer table at 03 :1696, and they should have their own vote and diagnostics. The ticket must be filed now, so the gap does not stay open because the work is out of this ruling.
  - Concern: If A wins, the ruling grows across two type families, and a flaw in one half can block the other.
- **AI/ML** — Vote: A
  - Reasoning: Models try `Int.MAX` first. The form is the same `const T.NAME` as the float constants, and the names have no cross-language ambiguity. Putting them in this ruling avoids a second spec cycle for a one-table change. Sys notes users cannot name the minimum that `Int.abs` panics on.
  - Concern: The ruling grows to cover every sized integer, and the table must be right for each type; if it slips, the float work waits on it.
- **Minimalism** — Vote: C
  - Reasoning: Nothing in the repo asks for them now. A separate ticket creates a queue item for a feature with no program behind it. File one when a program needs a bound, with that program as its evidence.
  - Concern: sys is right that `Int.abs` panics on the minimum value and users cannot name that value, so this gap will be found by users soon.

##### Q7. Lint for `x == Float.NAN`

Result: B (no lint), 5-1 (AI/ML dissent).

- **Systems** — Vote: B
  - Reasoning: I change my Phase A position. I checked the fact in the ballot: under the total order `NaN == NaN` is `true`, so the comparison is correct code, and a spec lint would contradict the spec. A lint also adds work to the front end that has no codegen benefit.
  - Concern: If A wins, the spec requires a lint that warns on code that is right, and users learn to ignore the warning.
- **Web/Scripting** — Vote: B
  - Reasoning: I supported it in Phase B because it is the most common float bug in JS. plt's fact changes my view: under the total order `NaN == NaN` is true in Blink, so the comparison is correct, and a lint on correct code is noise that the spec should not require. A lint can come as a separate tooling ticket if users ask for it.
  - Concern: A JS or Python developer who ports code and expects `x == NAN` to be always false gets the opposite with no warning.
- **PLT** — Vote: B
  - Reasoning: Under the Float total order, `NaN == NaN` is `true`, so the comparison is correct and the lint would contradict the spec. A user who wants IEEE semantics writes `ieee_eq`. If the panel wants a style hint, it belongs in a separate ticket, not in this ruling.
  - Concern: A user who comes from C or JS expects `x == NAN` to be false and may write wrong code; only docs, not a lint, will teach the difference.
- **DevOps/Tooling** — Vote: B
  - Reasoning: I withdraw my Phase A lint. Under the total order `NaN == NaN` is true, so the comparison is correct, and plt is right that a spec lint would contradict the spec. A diagnostic that calls correct code a bug trains users to ignore lints. A style hint can exist in the linter later without spec text.
  - Concern: If A wins, the linter warns on code that is correct under the spec, and users who want IEEE semantics learn `ieee_eq` from a lint that gives the wrong reason.
- **AI/ML** — Vote: A
  - Reasoning: A model trained on JS, Python and C writes `x == NAN` and expects `false`. Here it is `true` for NaN, so the code is correct but misleading. A style hint that points to `is_nan` teaches the intended form. It does not call the code wrong.
  - Concern: plt is right that a lint on correct code can contradict the total-order rule; the lint must be a style hint, not a warning that calls the comparison a bug.
- **Minimalism** — Vote: B
  - Reasoning: Under the Float total order `NaN == NaN` is true, so the comparison is correct. A lint that says it is a bug contradicts the spec. Lint policy is a tooling matter and does not belong in this ruling.
  - Concern: Users who come from IEEE languages write `x == Float.NAN` and get no warning, while the code means something different from their habit.

##### Q8. Help content for `.log()` and `math.sqrt(x)`

Phase C result: A 4-2 (PLT and Minimalism B). After Phase D: A, 4-2 (PLT and Minimalism dissent).

- **Systems** — Vote: A
  - Reasoning: The help lines cost nothing at run time, and they move the user from a wrong guess to the right method in one step. Without them the error says only "undefined variable". As the spec is the source for models, a stated requirement keeps the wording from drifting.
  - Concern: If A wins, the spec text fixes diagnostic wording, which can go stale when the compiler's message format changes.
- **Web/Scripting** — Vote: A
  - Reasoning: JS and Python developers type `Math.sqrt(x)`, `math.sqrt(x)` and `log(x)` first, and the error is where they learn the Blink rule. A spec requirement means every compiler version gives the same recovery path, and the LSP and docs can rely on it. It costs two lines of spec.
  - Concern: A spec that fixes help text adds a requirement that is hard to test and may go stale if the method names change.
- **PLT** — Vote: B
  - Reasoning: The `.log()` rule is a language decision: `log` has no binding, and the error names `ln`, `log2`, `log10`. The `math.sqrt` help is wording for an unrelated error (`UndefinedVariable`), and the spec fixes language rules, not message text. Tools can add the hint without a spec change.
  - Concern: Without a spec requirement, the `math.sqrt` hint may never be built, and models that try `math.sqrt(x)` get a bare "undefined variable".
- **DevOps/Tooling** — Vote: A
  - Reasoning: These two lines are the recovery path for the two most likely wrong first guesses, from Python/JS/C habit. If the spec leaves the wording free, one release can drop the help and no test fails. The spec should state the requirement (name `ln`, `log2`, `log10`; say `sqrt` is a method) and leave the exact wording to the implementation.
  - Concern: If B wins, the `math.sqrt` help is optional, and the first user error stays `undefined variable math` with no hint.
- **AI/ML** — Vote: A
  - Reasoning: These two help lines are how a model recovers from a wrong first guess. If the spec leaves the wording free, an implementation can drop them with no test failing. A spec requirement makes them testable and stable training signal.
  - Concern: Fixed help text in the spec ties diagnostics to the spec and may need a spec change whenever a name is added.
- **Minimalism** — Vote: B
  - Reasoning: The `.log()` rule is a language rule: `log` is deliberately unbound and the error must name the three replacements. The `math.sqrt` help is wording of an `undefined variable` error and belongs to the implementation. I support the line in the compiler, not in sections/.
  - Concern: With no spec requirement, the `math.sqrt` help can be dropped or reworded in a later change, and the AI recovery path goes with it.

#### Phase D — Focused debate and re-vote

Phase C left Q3, Q4, Q4b, Q6 and Q8 open. Q1, Q2, Q4c, Q5 and Q7 were decided and not debated.

##### D1 — Debate on Q3, Q4, Q4b, Q6 and Q8

Each seat answered the strongest argument against its Phase C vote and said whether it changed the vote.

- **Systems** (`D1/sys.md`):

> **Q3 (`is_infinite`).** Strongest argument against (web, min): `x == Float.INF || x == -Float.INF` is short. Answer: it is two compares where the exponent-bit test is one operation, and the other spelling, `!x.is_finite() && !x.is_nan()`, is easy to get wrong. plt's boundary concern has an answer: predicates that need no libm and have no domain error. Vote stays A.

> **Q4 (`Float.clamp`).** Strongest argument against (devops, web, aiml): `Int` has `clamp`, so users and models try it on `Float`, and `x.max(lo).min(hi)` does not report `lo > hi`. I concede my cost point was weak: the `lo > hi` check is one compare, and `Int.clamp` pays it. I hold B because the NaN rules are still contested (Q4b is 4-2 for a result that differs from the `max`/`min` chain). A method with a contested rule surprises the first user. If A wins, I accept it. Vote stays B.

> **Q4b (NaN receiver).** Strongest argument against (devops, aiml): NaN out makes `clamp` differ from `x.max(lo).min(hi)`. Answer: they already differ, since `clamp` panics on `lo > hi` and the chain does not, and Q4c passed 5-1 for a panic on a NaN bound. NaN in, NaN out is the rule `abs`, `sqrt` and `sin` follow. `hi` turns a NaN into a valid-looking number. Vote stays B.

> **Q6 (integer constants).** Strongest argument against (aiml): models try `Int.MAX` first, and a second spec cycle costs more. Answer: the table needs a value for every width, signed and unsigned, and touches the `Int.abs` rule on the minimum. That review does not belong in a float ruling. Against min's C: the gap is known now, so the ticket has its evidence. Vote stays B, ticket filed in this ruling.

> **Q8 (help text).** Strongest argument against (plt, min): the spec fixes language rules, not message text. Answer: the requirement names content, not wording ("name `ln`, `log2`, `log10`"; "say `sqrt` is a method"). Only a spec line stops a release from dropping the hint with no failing test. Vote stays A.

> No vote changes.

- **Web/Scripting** (`D1/web.md`):

> **Q3 (`is_infinite`). I change to A.**
> Strongest argument against my B vote: plt says without `is_infinite` a user must write `!x.is_finite() && !x.is_nan()`, which is easy to get wrong. My replacement, `x == Float.INF || x == -Float.INF`, is correct, but it is longer and a user must know to write it. My own Phase C concern also named the failed compile. Four seats want the row, it needs no libm, and it is one line in the table. plt's point on a stated boundary is fair: the group is the IEEE classification predicates `is_nan`, `is_finite`, `is_infinite`. `is_normal` and `is_subnormal` are not in it.

> **Q4 (`Float.clamp`). I keep A.**
> Strongest argument against: plt, min and sys say `clamp` brings three special cases, and `x.max(lo).min(hi)` already has defined behaviour. Two of the three are decided or small: Q4c is decided (a NaN bound panics, as does `lo > hi`), and Q4b has a 4-2 majority for a single rule. What remains is one row with one rule each for the receiver and the bounds. The case against names a cost, but plt and min both put the same cost in their own concern: `Int` has `clamp`, `Float` does not, and users and models will hit `UnresolvedMethod`. That gap is the 90% case in UI, colour and scroll code. The spelling `x.max(lo).min(hi)` also gives no panic on `lo > hi`.

> **Q4b (NaN receiver). I keep B.**
> Strongest argument against: devops and aiml say `clamp` must equal `x.max(lo).min(hi)` for every input, or the spec has a second NaN rule. That identity is true and useful. But it makes a NaN input come out as `hi`, a valid-looking number, and sys says this hides a bug in the caller. The identity is a derived property, as plt says. NaN passes through `abs`, `sqrt` and `sin` unchanged, so "NaN in, NaN out" is the one NaN rule for single-input methods. The spec states the difference from `x.max(lo).min(hi)` in one sentence.

> **Q6 (`Int.MAX`/`Int.MIN`). I keep B.**
> Strongest argument against: aiml says models try `Int.MAX` first, and one ruling saves a second spec cycle. I agree on the demand; that is why I want the ticket filed now. But the constants need a rule for each sized type, and they touch the sized-integer table and `Int.abs` on the minimum value. A flaw in the integer half could block the float half. Filing now answers min's "it slips to C" risk.

> **Q8 (help text). I keep A, narrowed.**
> Strongest argument against: plt and min say the spec fixes language rules, not message text, and `math.sqrt` help belongs to the `UndefinedVariable` error. I agree the wording is free. I ask only for the requirement, as devops states it: the `.log()` error names `ln`, `log2`, `log10`, and the `math.sqrt` error says `sqrt` is a method. Without a requirement no test fails if a release drops the help, and plt's own concern is that the hint may never be built. JS and Python developers meet this error first.

- **PLT** (`D1/plt.md`):

> I read all six Phase C votes. No vote changes.

> **Q3 (A, `is_infinite`).** Strongest argument against: web and min say `x == Float.INF || x == -Float.INF` is short, and `is_finite` plus `is_nan` classify every value. Answer: the long form is correct under the total order, but it is two comparisons and a sign choice where one predicate names the class. My own concern (the group needs a boundary) is real; the answer is a stated boundary, not omission. The boundary I propose: the group is the three predicates that partition the value set (NaN, infinite, finite). `is_normal` and `is_subnormal` subdivide "finite" and stay out. Vote stays A.

> **Q4 (B, no `Float.clamp`).** Strongest argument against: devops says `x.max(lo).min(hi)` hides a caller bug that `Int.clamp` reports, because it does not panic on `lo > hi`. Answer: this is true and it is a real cost. But adding `clamp` adds three decisions to the spec (Q4b, Q4c, `lo > hi`), and Q4b is split 2-4 on what the NaN rule is. A feature whose rules the panel cannot agree on should wait for a program that needs it. The user who wants the check writes `assert(lo <= hi)`. Vote stays B.

> **Q4b (B, NaN receiver returns NaN).** Strongest argument against: devops and aiml say `clamp` then differs from `x.max(lo).min(hi)` for NaN, which is a second NaN rule. Answer: there is no second rule. The rule is "a NaN input to a `Float` method that has no domain restriction gives NaN", as for `abs`, `sqrt` and `sin`. `max`/`min` are the exception, because they follow the order. A user who wants the order-based result already writes `max`/`min`. Vote stays B.

> **Q6 (B, separate ticket).** Strongest argument against: aiml says one table row set avoids a second spec cycle, and models try `Int.MAX` first. Answer: the constants need a value for each sized type and a rule for the `Int.abs` minimum-value case, so they touch the sized-integer table, not the float section. min's C is the worse outcome (sys: nobody files it). I ask that the ticket be filed with this ruling. Vote stays B.

> **Q8 (B, only `.log()` in the spec).** Strongest argument against: devops says that if the spec leaves the wording free, one release can drop the help and no test fails. Answer: the `.log()` rule is a language rule (`log` is unbound, and the error names `ln`, `log2`, `log10`), so it belongs in the spec. The `math.sqrt` hint is about an `undefined variable` error for a name that is not a Blink module, and a spec rule for it would fix a diagnostic text for every unbound name that looks like a module. That is a tooling policy, not a language rule. I accept that the hint may be dropped later; a tooling ticket tracks it. Vote stays B.

- **DevOps/Tooling** (`D1/devops.md`):

> **Q3 (`is_infinite`). Hold A.**
> Against: web and min say `x == Float.INF || x == -Float.INF` is short, and `is_finite` plus `is_nan` classify every value. True; the row is not needed for power. I keep A for the tool surface: completion shows `is_nan`, `is_finite`, `is_infinite` as one group, and a missing member gives `UnresolvedMethod` on the name a user guesses first. plt's boundary point is fair: the spec says the group is the IEEE 754 predicates that need no libm, and `is_normal` needs its own ticket.

> **Q4 (`Float.clamp`). Hold A.**
> Against: sys, plt and min say `clamp` brings three special cases, and `x.max(lo).min(hi)` does the same work. Q4c is decided (NaN bound and `lo > hi` panic), so one open case remains, Q4b. In return the user gets the `lo > hi` panic that the chain hides, and `Float` matches `Int`. Both B voters name the same concern: `UnresolvedMethod` on `clamp`, with no good help to give.

> **Q4b (NaN receiver). Hold A (`hi`).**
> Against: sys says `hi` turns a NaN into a valid-looking number and hides a caller bug. This is the strongest B point. But `NaN.min(x)` is already `x` under the total order, so the chain hides the NaN the same way, and no seat objects to that. A `clamp` that differs from the chain gives two NaN answers for two spellings of one operation, with no diagnostic on refactor. If B wins, the `clamp` row must state the difference from the chain.

> **Q6 (`Int.MAX`/`MIN`). Hold B.**
> Against: aiml says a second spec cycle is waste; min says nothing needs the constants yet. sys's fact answers min: `Int.abs` panics on the minimum value and users cannot name it. Against aiml: the constants need a rule per sized type, with their own diagnostics (for example `U8.MAX + 1` at compile time). That is not a float ruling. The ticket must be filed before this ruling closes.

> **Q8 (help texts). Hold A.**
> Against: plt and min say the spec fixes language rules, not message wording, and the `math.sqrt` help belongs to `UndefinedVariable`. I agree wording stays free. The requirement is smaller: the `.log()` help names `ln`, `log2`, `log10`; `math.sqrt(x)` with no `math` in scope says `sqrt` is a method. Both B voters name the risk that the hint is never built or is dropped later. A spec requirement makes a test possible.

- **AI/ML** (`D1/aiml.md`):

> **Q3 `is_infinite`.** Strongest argument against: web and min say `x == Float.INF || x == -Float.INF` is short, and `is_finite` plus `is_nan` classify every value. Reply: that form is correct, but a model does not search for it. It sees `is_nan` and `is_finite` and writes `is_infinite`. One failed compile per program is a cost the table can avoid with one row and no libm call. plt's concern (a request for `is_normal` next) is real; the answer is that the group is the three predicates of `Float` that need a one-line bit test and that the spec says "no others in this ruling". I keep A.

> **Q4 `Float.clamp`.** Strongest argument against: sys, plt and min say `x.max(lo).min(hi)` does the same work and `clamp` adds three NaN and bound decisions. Reply: the `Int` row already exists, so the model calls `Float.clamp` first, and plt and min both name that gap as their own concern. Q4c is decided, so two of the three decisions are fixed; only Q4b stays open. A user who writes the `max`/`min` chain gets no `lo > hi` panic, which hides a caller bug that `Int.clamp` reports. I keep A.

> **Q4b NaN receiver.** Strongest argument against: sys and web say returning `hi` turns a NaN into a valid-looking number and hides an upstream bug. This is the best argument on the ballot. Reply: `max` and `min` already behave this way under the decided total order, and `NaN.min(hi)` is `hi`. A `clamp` that differs from its chain is a second NaN rule, and a model cannot learn that from the identity. The hiding risk exists today in `min`. If the panel picks B, the spec row must say "NaN stays NaN; this differs from `x.max(lo).min(hi)`" so a model does not assume the identity. I keep A, and I accept B with that sentence.

> **Q6 `Int.MAX`/`Int.MIN`.** Strongest argument against: sys, web, plt and devops say the constants need a rule for each sized type and touch the sized-integer table, so they do not belong in a float ruling. Reply: my reason (avoid a second cycle) is weaker than theirs, and the ruling is about `Float` and `F32`. I change to B on one condition: the ticket is filed now, and its text records that models try `Int.MAX` first and `Int.abs` panics on a value users cannot name.

> **Q8 help texts.** Strongest argument against: plt and min say the spec fixes language rules, not message text, and the `math.sqrt` help belongs to an unrelated `UndefinedVariable` error. Reply: A states the requirement, not the wording (devops makes the same point): the error names `ln`, `log2` and `log10`, and says `sqrt` is a method. The recovery path is a language feature for an AI user, and plt's own concern is that without a requirement the hint is never built. I keep A. The spec text can say "the compiler must name the method form" and leave the string free.

- **Minimalism** (`D1/min.md`):

> **Q3 (`is_infinite`). Change: B to A.**
> Strongest argument against me: plt's. `is_nan`, `is_finite` and `is_infinite` are one IEEE classification group. Without the third, a user writes `!x.is_finite() && !x.is_nan()`, which is easy to get wrong. My `x == Float.INF || x == -Float.INF` replacement is longer and needs two constants. Q1 is now decided to add `asin`, `acos` and `atan` for the same reason (complete group), so a hole here is the inconsistent choice. The row needs no libm call and costs one line. I accept plt's concern: the spec should name the group boundary (`is_nan`, `is_finite`, `is_infinite`; no `is_normal`) so that the next request meets a stated rule.

> **Q4 (`Float.clamp`). No change: B.**
> Strongest argument against me: web's and aiml's. `Int` has `clamp`, so a model calls it on `Float` first. `x.max(lo).min(hi)` also hides a `lo > hi` bug that `Int.clamp` reports. This is true, and the gap costs one failed compile per user. But the add is not one row. It carries three rules (NaN receiver, NaN bound, `lo > hi`), and the panel is split 3-3 on the first of them. A language should not fix a contested NaN rule to close a convenience gap. `Float` also has `min` and `max`, so the composition is available and defined. Add `clamp` later with `signum` when a program needs it.

> **Q4b (NaN receiver). No change: B.**
> Strongest argument against me: devops's and aiml's. With "returns NaN", `clamp` and `x.max(lo).min(hi)` give different results for NaN, so a user cannot move between the two spellings. Against that: the identity is a derived property of two other methods. It is not a rule of `clamp`. NaN in, NaN out matches `abs`, `sqrt` and `sin`, and it matches Rust's `clamp`. Turning NaN into `hi` hides the bug in the caller. If `clamp` is added, B stays correct, and a spec sentence can state that the two spellings differ for NaN.

> **Q6 (`Int.MAX`/`Int.MIN`). Change: C to B.**
> Strongest argument against me: sys's. `Int.abs` panics on the minimum value, and users cannot name that value. That is evidence from the spec itself, not a guess. C also sends the item to a place where nobody files it. A filed ticket costs one line and no spec text. It keeps this ruling to floats, which is what I want. I withdraw C.

> **Q8 (help texts as spec requirements). No change: B.**
> Strongest argument against me: devops's. If the spec leaves the wording free, a release can drop the help and no test fails. But the `.log()` rule is already in the spec (Q8 B states it), because it is a language rule: `log` is unbound on purpose. The `math.sqrt` hint is a note on `UndefinedVariable`, an error that the spec does not otherwise describe. Spec text for one hint would open a list of every hint that the compiler should give. The implementation ticket can carry the `math.sqrt` hint as an acceptance test. That makes it testable without adding to `sections/`.

##### D2 — Re-vote

Each seat voted alone on Q3, Q4, Q4b, Q6 and Q8 after it read all Phase C votes and all D1 replies.

- **Systems** (`D2/sys.md`):

> **Q3. `is_infinite`.**
> - **Vote:** A
> - **Reasoning:** It is an exponent-and-mantissa bit test like `is_nan`, with no libm call and no domain error. It completes the three-way partition of the value set (NaN, infinite, finite), and plt's boundary rule (predicates that partition the set; `is_normal` and `is_subnormal` stay out) answers the "next request" worry. The alternatives are two compares or a negated pair that is easy to get wrong.
> - **Concern:** `is_normal` and `is_subnormal` requests will follow, and the spec must state the boundary at once or the group grows by habit.
>
> **Q4. `Float.clamp(self, Self, Self)`.**
> - **Vote:** B
> - **Reasoning:** `x.max(lo).min(hi)` compiles to two inline compares and is fully defined by the `min`/`max` rules already agreed. I concede that the `lo > hi` check costs only one compare, so my objection is not performance. I hold B because the panel has no stable NaN rule for `clamp` (Q4b is 4-2 for a result that differs from the chain), and a method whose rule is contested will surprise the first user. The tie is 3-3; I accept A if the moderator or user breaks it that way.
> - **Concern:** `Int` has `clamp` and `Float` does not, so each user and model meets one `UnresolvedMethod` and loses the `lo > hi` check that `Int.clamp` gives.
>
> **Q4b. NaN receiver of `clamp` (if added).**
> - **Vote:** B
> - **Reasoning:** NaN in, NaN out is what `abs`, `sqrt` and `sin` do, and it needs no special case in the emitted code. Returning `hi` turns a NaN into a valid-looking number and hides a caller bug far from its cause. The identity with `x.max(lo).min(hi)` is a derived property, and `clamp` already differs from the chain because it panics on `lo > hi`.
> - **Concern:** If A wins, `clamp` and the single-input methods follow two different NaN rules, and an upstream divide-by-zero shows up as a saturated `hi`.
>
> **Q6. `Int.MAX`/`Int.MIN` and the sized-integer constants.**
> - **Vote:** B
> - **Reasoning:** The constants need a value for every signed and unsigned width and touch the `Int.abs` minimum-value rule, so they belong with the sized-integer table, not with a float ruling. `Int.abs` panics on a value users cannot name, so the gap is real now and the ticket has its evidence. A ticket filed now keeps the work from slipping to "when needed", where nobody files it.
> - **Concern:** If A wins, a rule for every integer width lands without the integer table's own review, and a mistake in one width stays in the spec.
>
> **Q8. Help text for `.log()` and `math.sqrt(x)`.**
> - **Vote:** A
> - **Reasoning:** The requirement names content, not wording: the `.log()` error names `ln`, `log2` and `log10`, and the `math.sqrt` error says `sqrt` is a method. The help costs nothing at run time and moves a user from a wrong guess to the right method in one step. Without a spec line, a release can drop the hint and no test fails.
> - **Concern:** If B wins, the `math.sqrt` hint has no owner and may never be built, so the most common first guess from a JS or Python user still ends in a bare "undefined variable".

- **Web/Scripting** (`D2/web.md`):

> **Q3. `is_infinite`.**
> - **Vote:** A
> - **Reasoning:** The row needs no libm call and completes the IEEE classification group (`is_nan`, `is_finite`, `is_infinite`). A JS or Python developer who sees the first two writes the third next. `!x.is_finite() && !x.is_nan()` is easy to get wrong. The group boundary is stated: the predicates that partition the value set; `is_normal` and `is_subnormal` stay out.
> - **Concern:** A request for `is_normal` and `is_subnormal` follows by the same argument, and the spec must hold the stated boundary.
>
> **Q4. `Float.clamp(self, Self, Self)`.**
> - **Vote:** A
> - **Reasoning:** `Int` has `clamp`, so a user or model calls it on `Float` first. Clamping floats is the 90% case in UI, colour and scroll code. `x.max(lo).min(hi)` gives no panic on `lo > hi`, so it hides a bug that `Int.clamp` reports. Q4c is decided, so one open rule remains (Q4b).
> - **Concern:** The NaN receiver rule is easy to miss, and a user who reads `clamp` as the same as the `max`/`min` chain gets a different result for NaN.
>
> **Q4b. NaN receiver of `clamp`.**
> - **Vote:** B
> - **Reasoning:** NaN in, NaN out matches `abs`, `sqrt` and `sin`, Rust's `clamp` and what a JS developer expects. Returning `hi` turns a NaN from an upstream bug (for example `0.0 / 0.0` in a scroll position) into a plausible maximum with no sign of error. The `max`/`min` identity is a derived property, not a rule of `clamp`. The `clamp` row must say that NaN stays NaN and that this differs from `x.max(lo).min(hi)`.
> - **Concern:** The two spellings of one clamp now differ for NaN, and a user who refactors between them changes behaviour with no diagnostic.
>
> **Q6. `Int.MAX`/`Int.MIN` and sized-integer constants.**
> - **Vote:** B
> - **Reasoning:** Users need `Int.MAX` often, so the ticket must be filed now. The constants need a value for every width, signed and unsigned, and touch the sized-integer table and the `Int.abs` minimum-value rule. A flaw in the integer half would block the float half if they ship together. The ticket text records that models and users try `Int.MAX` first.
> - **Concern:** If the ticket is filed but not scheduled, `Int.MAX` stays an ICE and every user hits it before `Float.MAX`.
>
> **Q8. Help text for `.log()` and `math.sqrt(x)`.**
> - **Vote:** A
> - **Reasoning:** JS and Python developers type `math.sqrt(x)`, `Math.sqrt(x)` and `log(x)` first, and the error is where they learn the Blink rule. The spec states content, not wording: the `.log()` error names `ln`, `log2` and `log10`; the `math.sqrt(x)` error with no `math` in scope says `sqrt` is a method. Without a requirement a release can drop the hint and no test fails.
> - **Concern:** The spec now ties one diagnostic to its text, and the same argument asks for the next hint (for example `Math.floor(x)`), which needs a stated limit.

- **PLT** (`D2/plt.md`):

> **Q3. `is_infinite`.**
> - **Vote:** A
> - **Reasoning:** NaN, infinite and finite partition the value set, so `is_nan`, `is_finite` and `is_infinite` form one complete classification group. Without the third, a user writes `!x.is_finite() && !x.is_nan()`, which is easy to get wrong. The row needs no libm call and has no domain error. The spec should state the group boundary: `is_normal` and `is_subnormal` subdivide "finite" and are out of this ruling.
> - **Concern:** Another predicate (`is_normal`) will be requested by the same argument, and the boundary sentence is the only defence.
>
> **Q4. `Float.clamp(self, Self, Self)`.**
> - **Vote:** B
> - **Reasoning:** `clamp` adds a NaN-receiver rule that the panel split on (4-2 for a result that differs from the `max`/`min` chain), and a contested rule should not enter the spec to close a convenience gap. `x.max(lo).min(hi)` is defined under the total order, and a caller who wants the `lo > hi` check writes `assert(lo <= hi)`. I grant devops that the chain does not report `lo > hi`; that is a real cost, not a soundness defect. Add `clamp` with its own vote when a program needs it.
> - **Concern:** `Int` has `clamp` and `Float` does not, so a user and a model call it first and get `UnresolvedMethod`.
>
> **Q4b. NaN receiver (if `clamp` is added).**
> - **Vote:** B
> - **Reasoning:** The rule for a `Float` method with no domain restriction is: NaN in, NaN out, as for `abs`, `sqrt` and `sin`. `max` and `min` are the exception because they follow the total order, and `clamp` is not defined as a composition of them. Returning `hi` turns a value that `is_nan` can detect into a valid-looking number. The spec row must state that `clamp` differs from `x.max(lo).min(hi)` for NaN.
> - **Concern:** The two spellings of a bounded value give different results for NaN, and a refactor between them changes behaviour with no diagnostic.
>
> **Q6. `Int.MAX`/`Int.MIN` and the sized-integer constants.**
> - **Vote:** B
> - **Reasoning:** The constants need a value for every signed and unsigned width and touch the sized-integer table and the `Int.abs` rule on the minimum value. That is a separate set of types and a separate ruling from `Float` and `F32`. A ticket filed now keeps the gap on record. aiml and min both moved to B in D1.
> - **Concern:** If the ticket is filed but not scheduled, `Int.abs` keeps a panic case that no user can name.
>
> **Q8. Help text for `.log()` and `math.sqrt(x)`.**
> - **Vote:** B
> - **Reasoning:** The `.log()` rule is a language rule: `log` is unbound on purpose, and the error names `ln`, `log2`, `log10`. The `math.sqrt` hint annotates `UndefinedVariable`, which the spec does not otherwise describe, and a spec rule for it would fix diagnostic text for every unbound name that looks like a module. That is tooling policy. The implementation ticket can carry the hint as an acceptance test.
> - **Concern:** With no spec line, the `math.sqrt` hint can be dropped or reworded in a later release and no spec test fails.

- **DevOps/Tooling** (`D2/devops.md`):

> **Q3. `is_infinite`.**
> - **Vote:** A
> - **Reasoning:** `is_nan`, `is_finite` and `is_infinite` show in completion as one group, and a user guesses the third name first. Without it the user gets `UnresolvedMethod` and writes a longer test by hand. It needs no libm call and costs one row. The spec should state the group boundary: the predicates that partition the value set (NaN, infinite, finite); `is_normal` and `is_subnormal` stay out.
> - **Concern:** A later request for `is_normal` or `is_subnormal` will cite this row, so the spec must state the boundary at once.
>
> **Q4. `Float.clamp(self, Self, Self)`.**
> - **Vote:** A
> - **Reasoning:** `Int` has `clamp`, so `x.` completion on a `Float` without it looks like a hole, and the first `UnresolvedMethod` has no good help text to give. `x.max(lo).min(hi)` does not report `lo > hi`, so it hides a caller bug that `Int.clamp` reports. Q4c is decided, so only the NaN receiver rule stays open. One row, one rule, the same panic as `Int`.
> - **Concern:** The panel stays split on the NaN receiver rule, and a row whose rule users call surprising will draw bug reports.
>
> **Q4b. `clamp` NaN receiver.**
> - **Vote:** A (returns `hi`)
> - **Reasoning:** `x.clamp(lo, hi)` then equals `x.max(lo).min(hi)` for every input when `lo <= hi`, so a user can change between the two spellings with no change in result and no diagnostic needed. `NaN.min(x)` is already `x` under the decided total order, so the chain hides a NaN the same way today. A `clamp` that differs adds a second NaN rule that a user must learn. sys and web are right that `hi` hides an upstream bug; if B wins, the row must state the difference from the chain.
> - **Concern:** If B wins, a refactor from `x.max(lo).min(hi)` to `x.clamp(lo, hi)` changes the result for NaN and no tool can flag it.
>
> **Q6. `Int.MAX`/`Int.MIN` and sized-integer constants.**
> - **Vote:** B
> - **Reasoning:** The constants need a value for each sized type, and they touch the sized-integer table and the `Int.abs` rule on the minimum value. That needs its own review and its own diagnostics, such as a compile-time error for `U8.MAX + 1`. This ruling covers `Float` and `F32`. The ticket must be filed before this ruling closes, so the gap does not drop out of view.
> - **Concern:** If the ticket is filed but not scheduled, `Int.MAX` stays an ICE or `UnresolvedMethod` and users hit it before `Float.MAX`.
>
> **Q8. Help text for `.log()` and `math.sqrt(x)`.**
> - **Vote:** A
> - **Reasoning:** If the spec leaves the content free, one release can drop the help and no test fails. The requirement names content, not wording: the `.log()` error names `ln`, `log2` and `log10`; `math.sqrt(x)` with no `math` in scope says `sqrt` is a method. A spec line lets the test suite check both. plt and min are right that the exact string stays free to the implementation.
> - **Concern:** If A wins, the spec starts to list diagnostic content, and each later hint will ask for the same treatment.

- **AI/ML** (`D2/aiml.md`):

> **Q3. `is_infinite`.**
> - **Vote:** A
> - **Reasoning:** A model that sees `is_nan` and `is_finite` writes `is_infinite` next. One row, no libm call, and it completes the three predicates that partition the value set (NaN, infinite, finite). The spec should state that boundary, so a request for `is_normal` meets a written rule.
> - **Concern:** The weakest-use row may later look like clutter, and other predicates will be requested by the same argument.
>
> **Q4. `Float.clamp`.**
> - **Vote:** A
> - **Reasoning:** `Int` has `clamp`, so a model calls it on `Float` first. Q4c is decided, so the rules for the bounds are fixed and only the NaN receiver stays open. `x.max(lo).min(hi)` also gives no `lo > hi` panic, so the chain hides a caller bug that `Int.clamp` reports.
> - **Concern:** A contested NaN rule gets fixed in the spec early, and a wrong choice is hard to change later.
>
> **Q4b. NaN receiver.**
> - **Vote:** A
> - **Reasoning:** With "returns `hi`", `x.clamp(lo, hi)` equals `x.max(lo).min(hi)` for every input. A model learns one identity and one NaN rule for `min`, `max` and `clamp`. "Returns NaN" adds a second NaN answer for two spellings of one operation. I accept that the hiding risk is real (sys, web); it already exists in `min`.
> - **Concern:** If B wins, the `clamp` row must say "NaN stays NaN; this differs from `x.max(lo).min(hi)`", or a model will assume the identity and refactor into a changed result with no diagnostic.
>
> **Q6. `Int.MAX`/`Int.MIN` and sized-integer constants.**
> - **Vote:** B
> - **Reasoning:** I change from A. The constants need a value and a rule for each sized type and touch the `Int.abs` minimum-value rule, so they are not a float ruling. The ticket must be filed now, and its text should record that models try `Int.MAX` first and that `Int.abs` panics on a value users cannot name.
> - **Concern:** If C wins, nobody files the ticket, and `Int.MAX` stays an ICE that every user and model meets before `Float.MAX`.
>
> **Q8. Help text for `.log()` and `math.sqrt(x)`.**
> - **Vote:** A
> - **Reasoning:** The spec states the content, not the wording: the `.log()` error names `ln`, `log2`, `log10`, and `math.sqrt(x)` with no `math` in scope says `sqrt` is a method. These two lines are how a model recovers from a wrong first guess. A spec line makes them testable, so no release drops them silently.
> - **Concern:** If B wins, the `math.sqrt` hint is optional, and the first error a Python or JS habit hits stays a bare "undefined variable".

- **Minimalism** (`D2/min.md`):

> **Q3. `is_infinite`.**
> - **Vote:** A
> - **Reasoning:** `is_nan`, `is_finite` and `is_infinite` partition the value set. Without the third, the replacements are `x == Float.INF || x == -Float.INF` (two constants) or `!x.is_finite() && !x.is_nan()` (easy to get wrong). It is one row, needs no libm call, and Q1 already took the complete-group argument. I change from B on this ground. The row must state the boundary: these three predicates only; `is_normal` and `is_subnormal` need their own case.
> - **Concern:** The next request for `is_normal` or `is_subnormal` will use the same "complete group" argument, and the stated boundary may not hold.
>
> **Q4. `Float.clamp`.**
> - **Vote:** B
> - **Reasoning:** `x.max(lo).min(hi)` is available and has defined NaN behavior under the total order. `clamp` adds a NaN receiver rule that the panel splits 2-4, and a panic path. A language should not fix a contested rule to close a convenience gap; add `clamp` when a program needs it, with its NaN evidence. The user who wants the `lo > hi` check writes `assert(lo <= hi)`.
> - **Concern:** `Int` has `clamp` and `Float` does not, so users and models will get `UnresolvedMethod` on the name they try first.
>
> **Q4b. NaN receiver, if `clamp` is added.**
> - **Vote:** B
> - **Reasoning:** A NaN receiver passes through unchanged, as it does through `abs`, `sqrt` and `sin`. That is the smaller rule: one NaN rule for every single-input method. Returning `hi` turns a NaN into a valid-looking number. If `clamp` is added, the row must say that it differs from `x.max(lo).min(hi)` for NaN.
> - **Concern:** `clamp` and `x.max(lo).min(hi)` then give different results for NaN, and users will expect them to be the same.
>
> **Q6. `Int.MAX`/`Int.MIN` and the sized-integer constants.**
> - **Vote:** B
> - **Reasoning:** I withdraw C. sys's fact holds: `Int.abs` panics on the minimum value, and users cannot name it, so the evidence exists in the spec now. The constants need a value for every sized type and touch the sized-integer table, so they do not belong in a float ruling. A filed ticket costs one line and adds no spec text.
> - **Concern:** A ticket filed with no program behind it can sit in the queue while models keep trying `Int.MAX` and fail.
>
> **Q8. Help text for `.log()` and `math.sqrt(x)`.**
> - **Vote:** B
> - **Reasoning:** The `.log()` rule is a language rule: `log` is unbound on purpose, and the error names `ln`, `log2`, `log10`. The `math.sqrt(x)` hint is a note on `UndefinedVariable`, an error the spec does not otherwise describe. A spec line for it opens a list of every hint the compiler should give. The implementation ticket carries it as an acceptance test, which makes it testable without text in `sections/`.
> - **Concern:** With no spec line, a later change can drop or reword the `math.sqrt` hint, and the AI recovery path goes with it.

##### D2 tally

| Q | A | B | Result |
|---|---|---|---|
| Q3 | all six | none | A, 6-0 |
| Q4 | Web/Scripting, DevOps/Tooling, AI/ML | Systems, PLT, Minimalism | 3-3 → owner broke tie for A. The owner gave no reason. |
| Q4b (A: `hi`, B: NaN) | DevOps/Tooling, AI/ML | Systems, Web/Scripting, PLT, Minimalism | B, 4-2 |
| Q6 | none | all six | B, 6-0 |
| Q8 | Systems, Web/Scripting, DevOps/Tooling, AI/ML | PLT, Minimalism | A, 4-2 |

### Dissents

The dissents are the seats' own D2 reasoning and concerns, quoted above. In short:

- **Q1, Q5 (Minimalism).** The Phase C blocks above hold the reasoning.
- **Q2 (Systems).** The Phase C block above holds the reasoning.
- **Q4 (Systems, PLT, Minimalism).** Systems: "I hold B because the panel has no stable NaN rule for `clamp` (Q4b is 4-2 for a result that differs from the chain), and a method whose rule is contested will surprise the first user." PLT: "a contested rule should not enter the spec to close a convenience gap." Minimalism: "A language should not fix a contested rule to close a convenience gap; add `clamp` when a program needs it, with its NaN evidence."
- **Q4b (DevOps/Tooling, AI/ML).** DevOps/Tooling: "If B wins, a refactor from `x.max(lo).min(hi)` to `x.clamp(lo, hi)` changes the result for NaN and no tool can flag it." AI/ML: "If B wins, the `clamp` row must say \"NaN stays NaN; this differs from `x.max(lo).min(hi)`\", or a model will assume the identity and refactor into a changed result with no diagnostic." Both accept B if the row states the difference. The spec row does.
- **Q4c (AI/ML), Q7 (AI/ML).** The Phase C blocks above hold the reasoning.
- **Q8 (PLT, Minimalism).** PLT: "With no spec line, the `math.sqrt` hint can be dropped or reworded in a later release and no spec test fails." Minimalism: "With no spec line, a later change can drop or reword the `math.sqrt` hint, and the AI recovery path goes with it."

### Final Spec

```blink
let r = 2.0.sqrt()
let h = 0.5.clamp(0.0, 1.0)
let d = 1.0.atan2(1.0)
let big = Float.MAX
```

- `Float` and `F32` have built-in methods `abs`, `sqrt`, `min`, `max`, `clamp`, `pow`, `exp`, `ln`, `log2`, `log10`, `sin`, `cos`, `tan`, `asin`, `acos`, `atan`, `atan2`, `is_finite` and `is_infinite`. No import is needed. There are no free functions.
- `std.math` keeps `BigInt` only. `std.float.fabs` goes: use `x.abs()`.
- No method panics on a domain error. `(-1.0).sqrt()` is NaN.
- `min` and `max` use the total order. `clamp` returns NaN for a NaN receiver, and panics for a NaN bound or for `lo > hi`. The `clamp` row states that this differs from `x.max(lo).min(hi)`.
- `log` does not exist. The E0505 help for `.log()` names `ln`, `log2` and `log10`. `math.sqrt(x)` with no `math` in scope gives E0506, and the help says `sqrt` is a method. The spec requires this content, not the wording.
- `is_nan`, `is_finite` and `is_infinite` partition the value set. `is_normal` and `is_subnormal` are not part of this ruling.
- Constants `PI`, `E`, `INF`, `NAN`, `MAX`, `EPSILON` and `MIN_POSITIVE` exist on `Float` and `F32`. `MIN_POSITIVE` is the smallest positive normal value. There is no `MIN` and no `NEG_INF`.
- There is no `hypot`, no `Int.sqrt`, and no lint for `x == Float.NAN`.
- `Int.MAX`, `Int.MIN` and the sized-integer constants go to a separate spec question.

### Reading Gaps

- The compiler does not yet resolve the new methods and constants. The spec leads the compiler. The examples cannot pass `blink check` until the compiler follows.
- The removal of `std.float.fabs` from `lib/` is a separate chore.
- The help content for `.log()` and for `math.sqrt(x)` needs a compiler change and a test.
- The F32 constants and the `is_finite`/`is_infinite` rows overlap with the work on `is_finite` in a sibling spec branch. That branch must follow this ruling on F32 constants.

