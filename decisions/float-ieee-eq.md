[< All Decisions](../DECISIONS.md)

# Float `ieee_eq` and `-0.0` — Design Rationale

**Gap:** §3 *Float Total Ordering* said: "For IEEE 754-strict comparison where `NaN != NaN` and `-0.0 != 0.0`: use `float.ieee_eq(other)` from stdlib." IEEE 754 equality (compareQuietEqual, C `==`) gives `-0.0 == 0.0` as `true`, so the sentence contradicted the standard it names. It was also wrong about where `ieee_eq` lives: it is a method that the compiler supplies, not a stdlib function. The compiler, the runtime and `lib/std/float.bl` already treated `ieee_eq` as C `==`.

```blink
fn main() {
    let nz = -0.0
    assert(nz.ieee_eq(0.0))     // the old text said this is false
}
```

## Result

| Question | Result | Vote |
|---|---|---|
| Q1 Meaning | `ieee_eq` is IEEE 754 compareQuietEqual (C `==`); `(-0.0).ieee_eq(0.0)` is `true`. Ticket option (b), a sign-aware `ieee_eq`, rejected | 6-0 |
| Q2 Agreement law | The spec states "`x == y` is `true` exactly when `x.ieee_eq(y)` is `true` or both operands are `NaN`", in place of "differs only on NaN" | 6-0 |
| Q3 Sign of zero | Add "To test the sign of zero, use `1.0 / x < 0.0`." | 5-1 (Min dissent: no sentence) |
| Q4 Negative rule | Add "No `Float` equality tells `-0.0` from `0.0`." | 6-0 |
| Q5 Naming | "the method `x.ieee_eq(y)`", with no built-in or stdlib claim | 6-0 |
| Q6 Lint | No ticket for a lint `x.ieee_eq(x)` → `x.is_nan()` | 6-0 in Phase D (4-2 in Phase C; aiml and web changed to NO) |
| Q7 Chore | No chore to make `is_nan` the primitive and move `ieee_eq` into std.float | 6-0 |

AI-first review: 5/5 pass. The user signed off on the tally.

**No implementation work.** The compiler already behaves as the ruling says: `src/cg_call.bl` lowers `ieee_eq` to C `==`, and `blink_float_cmp(-0.0, 0.0)` returns 0, so `Eq` and `Ord` agree. Only text changed.

**Shared concern.** Five panelists named the same risk for Q3: if `to_bits()` or `is_sign_negative()` ships, the `1.0 / x < 0.0` line must change in the same commit.

**Follow-ups the panel raised outside the ballot.** In Phase D every panelist named a different lint as the real hazard: under total `==`, Float `x != x` is always `false` and `x == x` is always `true`, so a C-habit NaN check never fires. Sys raised `-ffast-math`, which folds the `x != x` NaN tests in the runtime and in `is_nan`. Both went to the friction log.

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in independent-proposal → debate → vote rounds. All panelist text below is verbatim. Headings inside a panelist's text are shown at one level.

#### Phase A — Independent proposals

**Systems:**

> ##### Sys proposal: `ieee_eq` is the hardware compare and nothing more
>
> ##### Proposal 1 (primary): fix the sentence. `ieee_eq` is C `==`.
>
> Under this proposal `ieee_eq` stays exactly as it is today. It lowers to C `==`, which on x86-64 is one `ucomisd` plus `sete`/`setnp`, and on AArch64 is one `fcmp` plus `cset eq`. IEEE 754 calls this compareQuietEqual. It already gives `-0.0 == 0.0` true. The only fix is the spec text, which is wrong twice:
>
> 1. It says ieee_eq gives `-0.0 != 0.0`. No IEEE predicate does that.
> 2. It says ieee_eq is "from stdlib". It is a compiler builtin method (src/typecheck.bl:18619, src/cg_call.bl:4637).
>
> ```blink
> fn main() {
>     let nan = 0.0 / 0.0
>     let neg_zero = 0.0 - 0.0 * 1.0 * -1.0
>     assert(nan == nan)                    // total Eq
>     assert(!nan.ieee_eq(nan))             // IEEE: NaN is unordered
>     assert(neg_zero == 0.0)               // total Eq
>     assert(neg_zero.ieee_eq(0.0))         // IEEE agrees: zeros are equal
>     assert(1.0.ieee_eq(1.0))
> }
> ```
>
> **Tradeoffs (Sys view).**
> - Cost: `ieee_eq` is the cheapest Float compare we have. Total `==` calls `blink_float_eq`, which adds two NaN branches. Code in a hot loop that knows its inputs are finite (SIMD-style kernels, physics) gets the bare instruction from `ieee_eq`. We should keep that.
> - Predictable codegen: one method maps to one instruction. A sign-aware `ieee_eq` would need a `signbit` test or a bit cast and a second compare. It would cost more, and it would not be IEEE, so the name would be false.
> - `lib/std/float.bl:13` (`is_nan` as `!x.ieee_eq(x)`) depends on this meaning, and so does the slice's test. Option (b) would break neither of them, but it would make the name a lie.
> - Hash: the rule that Float has no `Hash` stays sound. Under total Eq, `-0.0 == 0.0` while the bit patterns differ, and that argument does not involve `ieee_eq`.
> - `-ffast-math` caveat: under fast-math, `x != x` folds to false, so `is_nan` and `blink_float_eq` both break. The spec should not promise behaviour that only holds without fast-math unless we also forbid fast-math. The runtime comment already says this, but it is out of scope here.
>
> **Cross-language.** Rust's `f64::eq` is IEEE (`-0.0 == 0.0`, `NaN != NaN`) and `total_cmp` is the bitwise order. Zig, Go and C all use IEEE `==`. No mainstream language has an "IEEE equality" that separates the zeros. That supports (a).
>
> **Spec text:**
>
> > For IEEE 754 equality (compareQuietEqual, C `==`), use the built-in method `x.ieee_eq(other)`. Under it, `NaN` is unequal to every value, itself included. `-0.0` and `0.0` are equal under both `==` and `ieee_eq`. The two differ only on `NaN`.
>
> ##### Proposal 2 (deferred, not for this ruling): no sign-aware compare
>
> Do not add a sign-aware or bitwise equality method now (YAGNI). If a real need appears, for example a serializer that must round-trip `-0.0` or code that checks for canonical NaN payloads, the zero-cost primitive is a bit cast. A named compare is the wrong shape:
>
> ```blink
> fn same_bits(a: Float, b: Float) -> Bool {
>     a.to_bits() == b.to_bits()    // to_bits() -> U64; memcpy, which lowers to one movq
> }
> ```
>
> `to_bits()` costs one `movq` from xmm to a GPR. It handles every case: sign of zero, NaN payloads, and hashing a Float as bits, all in user code. A `sign_eq` method would solve only one of those. I am not proposing `to_bits()` in this ruling. I name it only so the panel does not invent `ieee_eq`'s "missing half" later. If someone wants it, file it as a separate type:spec ticket.
>
> ##### Vote position
> (a). Remove `-0.0 != 0.0` and "from stdlib" from the sentence. Add the `-0.0` `ieee_eq` row to tests/test_float_total_equality.bl as `assert(neg_zero.ieee_eq(0.0))`.

**Web/Scripting:**

> ##### Web/Scripting proposal: ticket 632psr (`ieee_eq` and `-0.0`)
>
> ##### Proposal W1 (recommended): `ieee_eq` means IEEE `==`; fix the sentence
>
> `ieee_eq` should mean what its name says: IEEE 754 `compareQuietEqual`, which is C's `==`. The only change from Blink's `==` is NaN. The `-0.0` clause in the spec is an error, so delete it. The "from stdlib" phrase is also wrong: `ieee_eq` is a built-in method on `Float`, so the text should say that.
>
> ```blink
> fn main() {
>     let nan = 0.0 / 0.0
>     let neg_zero = 0.0 - 0.0 * -1.0
>
>     print("{nan == nan}")                  // true  (total order)
>     print("{nan.ieee_eq(nan)}")            // false (IEEE)
>     print("{neg_zero == 0.0}")             // true
>     print("{neg_zero.ieee_eq(0.0)}")       // true  (IEEE: zeros are equal)
> }
> ```
>
> **Tradeoffs for a JS or Python developer:**
> - A JS or Python developer who reads "ieee_eq" and searches the web for "IEEE 754 equality" finds that `-0.0 == 0.0` is true. If Blink's `ieee_eq` returns false there, it breaks what that search teaches. That is a "why is Blink's IEEE compare not IEEE?" question that people will keep asking online. When a name promises a standard, the name must keep the promise.
> - With W1, the rule fits in one line: "`==` is IEEE, except NaN equals NaN." That is easy to learn in five minutes. Two differences, one of them invented, would not be.
> - The compiler and runtime already do this. Codegen lowers `ieee_eq` to C `==`, and `lib/std/float.bl`'s `is_nan` depends on NaN being the only value unequal to itself. W1 changes only the spec text and adds the missing `-0.0` test row. No compiler change.
> - Cost: no API tells `-0.0` from `0.0`. That is acceptable for the 90% case. Web and scripting code almost never needs it, and people who do (numeric and graphics code) can use W2.
>
> **Cross-language:**
> - JS: `===` is IEEE (`NaN !== NaN`, `-0 === 0`).
> - Python: `float.__eq__` is IEEE.
> - Kotlin: `==` on a statically typed `Double` is IEEE, but `.equals()` is total and separates `-0.0` from `0.0`.
>
> Every one of these keeps the name "IEEE" or `==` for the standard predicate. None uses the IEEE label for a sign-aware compare.
>
> **Spec text (replaces sections/03_types.md:2848):**
>
> > For IEEE 754 equality, use the built-in method `x.ieee_eq(other)`. It is the IEEE 754 equality predicate: it differs from `==` only on NaN. `NaN.ieee_eq(NaN)` is `false`, so NaN is the only value for which `x.ieee_eq(x)` is `false`. `(-0.0).ieee_eq(0.0)` is `true`, the same as `==`.
>
> ##### Proposal W2 (optional, a separate ticket): `is_sign_negative()` for the sign of zero
>
> I would not add a sign-aware equality function. Developers do not ask "are these zeros equal under sign?" They ask "is this zero negative?" A single predicate answers that and has no equality semantics to explain.
>
> ```blink
> fn fmt_temp(c: Float) -> Str {
>     if c == 0.0 && c.is_sign_negative() { "-0°C" } else { "{c}°C" }
> }
> ```
>
> - Prior art for the name: Rust has `f64::is_sign_negative`, JS has `Math.sign` and `Object.is`, and Python has `math.copysign`.
> - It is one method with an obvious meaning, and it involves no Eq or Hash coherence.
> - Under YAGNI, add it only when a user asks. W1 must not wait for it.
>
> **Spec text, if W2 is adopted** (add to the stdlib Float methods):
>
> > `x.is_sign_negative() -> Bool`: `true` if the sign bit of `x` is set, including `-0.0` and NaNs that have the sign bit set.
>
> ##### Rejected: option (b), keep the text and make `ieee_eq` check the sign bit
>
> This makes a method named "IEEE" disagree with IEEE, and it also changes `is_nan`'s documented basis. A sign-aware compare would need a new name such as `bit_eq`, but no one has shown a need for it. That fails the "how many questions online" test before it ships.
>
> ##### Vote
>
> W1 now. W2 only on request. Reject (b).

**PLT:**

> ##### PLT proposal: make `ieee_eq` exactly IEEE equality
>
> ##### Proposal 1 (recommended): `ieee_eq` is IEEE `compareQuietEqual`, and the spec states the law that links it to `==`
>
> The current sentence describes a relation that is not IEEE equality. IEEE `compareQuietEqual` gives `-0.0 == 0.0` as true. If `-0.0 != 0.0` holds, you are comparing bit patterns. So the name and the meaning disagree, and one of them must change. The compiler already uses the IEEE meaning: `src/cg_call.bl` lowers `ieee_eq` to C `==`, and `lib/std/float.bl:13` depends on it. Keep the meaning and fix the sentence.
>
> **Typing rule:** `Float.ieee_eq : (self: Float, other: Float) -> Bool`. It is a built-in method, not a stdlib function.
>
> **Laws.** These are the important part, because they make the two relations compose:
> 1. `ieee_eq` is a partial equivalence relation (PER). It is symmetric and transitive, and it is reflexive on every value except NaN.
> 2. **Agreement:** for all `x`, `y`, `x == y` if and only if `x.ieee_eq(y)` or both are NaN. So Blink's `==` is the reflexive closure of IEEE equality. The two relations differ only at NaN and agree at zero.
> 3. `x.ieee_eq(x)` is false if and only if `x` is NaN.
>
> Law 2 means a user moves between the two relations with one rule ("NaN only"), not two. It also keeps the Hash argument sound: `-0.0 == 0.0` under both relations, so no bitwise hash can match either one, and E1400 stands unchanged.
>
> ```blink
> fn ieee_demo() {
>     let nan = 0.0 / 0.0
>     assert(nan == nan)
>     assert(!nan.ieee_eq(nan))
>     assert(-0.0 == 0.0)
>     assert((-0.0).ieee_eq(0.0))
>     assert(1.0.ieee_eq(1.0))
> }
> ```
>
> **Tradeoffs**
> - For: the name is honest. The spec matches the code and `is_nan`. The test row for `-0.0` can be added with no compiler change.
> - Against: nothing in the language gives sign-aware equality. You can still observe the sign of zero with `1.0 / x`, and Proposal 2 covers that case.
> - Rejected option (b), "ieee_eq checks the sign bit": this relation is neither IEEE equality nor bit identity, because NaN payloads would still compare unequal. It has no clean law, and keeping the name would mislead readers.
>
> **Spec text** (replaces the last sentence of "Float Total Ordering"):
>
> > For IEEE 754 equality, use the built-in method `x.ieee_eq(y)`. It is IEEE 754 `compareQuietEqual` (C `==`): `NaN` is unequal to every value, itself included, and `-0.0` equals `0.0`. `ieee_eq` and `==` differ only at `NaN`: `x == y` is `true` exactly when `x.ieee_eq(y)` is `true` or both operands are `NaN`. No equality relation on `Float` tells `-0.0` from `0.0`. To see the sign of zero, read the sign bit.
>
> ##### Proposal 2 (deferred, do not ship now): sign-awareness through bit access, not a third equality
>
> If users need sign-aware or bit-exact comparison, give them `Float.to_bits() -> U64` and let them compare the integers. Bit identity is then `a.to_bits() == b.to_bits()`, a true equivalence on `U64` that you get from existing parts. This adds no third Float relation that could drift from `Eq`, and it also makes `-0.0` and NaN payloads distinguishable.
>
> ```blink
> fn same_bits(a: Float, b: Float) -> Bool {
>     a.to_bits() == b.to_bits()
> }
> ```
>
> I vote to defer this under YAGNI and file it as a feature only when a user needs it. The spec sentence above already says "read the sign bit" and does not promise an API.
>
> ##### Cross-language notes
> - **OCaml** is the closest match. Polymorphic `=` is IEEE equality, and `compare` / `Float.equal` treat `nan = nan` and `compare (-0.) 0. = 0`. That pair of relations is exactly Blink's `ieee_eq` / `==`.
> - **Haskell's** `Eq Double` is IEEE, so the Eq laws break at NaN. Blink avoids that by making `==` total.
> - **Rust's** `total_cmp` orders `-0.0 < +0.0`, which is a third relation. Blink should not copy it, because it would break agreement with `-0.0 == 0.0`.
>
> **Implications for Ord coherence (flag for Phase B)**
> `Ord.cmp(-0.0, 0.0)` must return `Equal`, or `Eq` and `Ord` disagree. Someone should confirm that `blink_float_cmp` (bootstrap/runtime_core.h) does this. If it does not, that is a separate soundness bug.
>
> **Vote:** Proposal 1 (option a). Defer Proposal 2.

**DevOps:**

> **DevOps/Tooling proposal on 632psr: `ieee_eq` and the sign of zero**
>
> **Proposal 1 (recommended): `ieee_eq` means IEEE `==`; fix the sentence; call it a built-in method**
>
> The compiler already does this. Typecheck takes `ieee_eq` as a built-in Float method (src/typecheck.bl:18619), and codegen lowers it to C `==` (src/cg_call.bl:4637). `lib/std/float.bl:13` builds `is_nan` on it, and its doc says NaN is the only value unequal to itself under `ieee_eq`. Only the spec sentence is wrong, and it is wrong twice:
> - `-0.0 != 0.0` is not IEEE behaviour.
> - "from stdlib" is false. Nothing in lib/std defines `ieee_eq`.
>
> ```blink
> fn main() {
>     let nan = 0.0 / 0.0
>     let nz = -0.0
>     assert(nan == nan)              // total Eq: reflexive
>     assert(!nan.ieee_eq(nan))       // IEEE: NaN unequal to itself
>     assert(nz == 0.0)               // total Eq
>     assert(nz.ieee_eq(0.0))         // IEEE: -0.0 equals 0.0
>     assert(1.0 / nz < 0.0)          // the sign of zero shows through division
> }
> ```
>
> Tradeoffs in my domain:
> - **Hover and docs.** The LSP hover and `blink doc` for `ieee_eq` read "IEEE 754 `compareQuietEqual`: C `==`". A user can check that in one line against any IEEE reference. If the name says "IEEE" but the method checks the sign bit, every hover misleads the user. That costs more than it seems, because people will learn from the docs and from this codebase as training data.
> - **Diagnostics.** No new code is needed. One optional lint, W-class: `x.ieee_eq(x)` → "use `x.is_nan()`" with a machine-applicable fix. This is the only common idiom with this method, and it already shows up in our own stdlib.
> - **Formatter and parser.** Nothing changes. It is a plain method call.
> - **Test gap closes.** tests/test_float_total_equality.bl gets its -0.0 row as `assert(nz.ieee_eq(0.0))`. That row exists today only as a blocked TODO.
>
> Cross-language: this matches Rust (`==` on f64 is IEEE, `total_cmp` is the total order), Java (`Double.equals` is total, `==` is IEEE), and Swift (`==` is IEEE, `isTotallyOrdered` is total). In all of them the IEEE predicate gives `-0.0 == 0.0`. None of them has an "IEEE equality" that separates the zeros.
>
> Spec text (replaces sections/03_types.md:2848):
>
> > For IEEE 754 comparison, use the built-in method `x.ieee_eq(y)`. It is IEEE 754 `compareQuietEqual` (C `==`): `NaN.ieee_eq(x)` is `false` for every `x`, including NaN itself, and `(-0.0).ieee_eq(0.0)` is `true`. No `Float` equality tells `-0.0` from `0.0`. To test the sign of zero, use `1.0 / x < 0.0`.
>
> **Proposal 2 (rejected by me, listed for the vote): keep the text and make `ieee_eq` sign-aware**
>
> ```blink
> assert(!(-0.0).ieee_eq(0.0))   // would no longer be IEEE
> ```
>
> This makes the hover lie. To be honest it would need a new name such as `bit_eq` or `same_bits`. It would also make NaN payloads observable, because two NaNs with different payloads would compare unequal. That is a new semantic surface that nobody asked for, it needs its own spec text, and the stdlib doc and `is_nan` reasoning would need rework.
>
> **Proposal 3 (defer, YAGNI): a sign-of-zero query**
>
> If users later need to read the sign without the `1.0 / x` trick, add `x.is_sign_negative() -> Bool`, which Rust also has, as a separate built-in. Don't overload equality with it. No caller in the repo needs it today, so file a friction ticket only when one does.
>
> **My vote**
>
> - Proposal 1 now.
> - Proposal 3 parked until a caller needs it.
> - Proposal 2 rejected: the name would contradict its own behaviour, and the docs and hover would carry that error.

**AI/ML:**

> ##### AI/ML panelist: make `ieee_eq` exactly IEEE `==`
>
> ##### Proposal 1 (recommended): `ieee_eq` means IEEE equality and nothing more
>
> Fix the false claim instead of inventing a new meaning. `ieee_eq` keeps its name and behaves the same as C `==` (IEEE 754 compareQuietEqual). The only difference from Blink's `==` is NaN. Remove the "from stdlib" phrase, because `ieee_eq` is a built-in method on `Float` (src/typecheck.bl, src/cg_call.bl).
>
> ```blink
> fn main() {
>     let nan = 0.0 / 0.0
>     assert(nan == nan)              // total order: reflexive
>     assert(!nan.ieee_eq(nan))       // IEEE: NaN is unequal to itself
>     assert(-0.0 == 0.0)             // total order
>     assert((-0.0).ieee_eq(0.0))     // IEEE: zeros compare equal too
>     assert(1.0.ieee_eq(1.0))
> }
> ```
>
> **Spec text (replaces sections/03_types.md:2848):**
>
> > For IEEE 754 equality, use the method `x.ieee_eq(y)`. It follows the IEEE 754 equality predicate: it is `false` if either operand is `NaN`, and otherwise it agrees with `==`. In particular, `(-0.0).ieee_eq(0.0)` is `true`. Under `ieee_eq`, `NaN` is the only value unequal to itself.
>
> **Tradeoffs (LLM accuracy and learnability):**
> - **The name matches the meaning.** A model reads `ieee_eq` and recalls what IEEE 754 equality does, which is also what Python, C, Rust and JS do with `==` on floats. Option (b) makes the name lie: any model that trusts the name gets `-0.0` wrong, and the spec text alone cannot fix a name that suggests the opposite.
> - **The rule has one exception.** "Blink `==` and IEEE `==` differ only on NaN" fits in one sentence. Two exceptions (NaN and the sign of zero) is one more thing to remember, and the second one has no other language to borrow from.
> - **It costs nothing.** No new tokens, no rename, no change to codegen. `lib/std/float.bl:is_nan` already depends on this exact meaning ("NaN is the only value unequal to itself"). Under (b) that comment would still hold, but the test suite and docs would describe two different functions.
> - **The current sentence gives wrong training data.** Code written from the current spec might use `ieee_eq` to detect `-0.0`. It would compile and quietly return the wrong answer, which is the worst way a spec bug can fail.
>
> **Cross-language:** C, C++, Java (primitive `==`), Rust (`f64 == f64`), Python, JS and Go all give `-0.0 == 0.0` as true. Rust's `total_cmp` and Java's `Double.equals` are the sign-aware cases. They have different names, and none of them is called "IEEE eq".
>
> ##### Proposal 2 (not now, YAGNI): a sign check with a clear name, if one is ever needed
>
> If users need to tell `-0.0` from `0.0`, add a separate method with a name that says what it does. Do not overload `ieee_eq`:
>
> ```blink
> fn describe(x: Float) -> Str {
>     if x == 0.0 && x.is_sign_negative() { "negative zero" } else { "other" }
> }
> ```
>
> `is_sign_negative` (as in Rust) or `to_bits()` (as in Rust and Zig) is a pattern models already know well. Nothing in sections/, lib/std or src asks for one today, so I would not add it in this ruling. If someone wants it, they should open a separate ticket.
>
> ##### Vote
>
> **Proposal 1.** Keep `ieee_eq` as IEEE `==` and fix the sentence. Also add the `-0.0` row to tests/test_float_total_equality.bl: `assert((-0.0).ieee_eq(0.0))`.

**Minimalism:**

> Proposal from the Min panelist (Minimalism) on ticket 632psr, the `ieee_eq` and `-0.0` question.
>
> **Summary:** fix the sentence. Do not add a feature. Rejecting the change and building a sign-aware compare are both wrong.
>
> ##### Proposal 1 (my vote): fix the text; `ieee_eq` means IEEE `==`
>
> The bug is one false clause in the spec. The code, the tests and the `lib/std/float.bl` doc already agree that `ieee_eq` is C's own `==`. Make the spec match the code, and remove "from stdlib", which is also false: `ieee_eq` is a compiler builtin method.
>
> ```blink
> fn main() {
>     let nan = 0.0 / 0.0
>     assert(nan == nan)            // total order: reflexive
>     assert(!nan.ieee_eq(nan))     // IEEE: NaN unequal to itself
>     assert(-0.0 == 0.0)           // total order
>     assert((-0.0).ieee_eq(0.0))   // IEEE agrees: zeros are equal
> }
> ```
>
> **Spec text (replaces the last line of "Float Total Ordering"):**
>
> > For IEEE 754 equality, use the method `a.ieee_eq(b)`. It is the IEEE 754 equality predicate (C's `==`). It differs from `==` only on NaN: `NaN.ieee_eq(x)` is `false` for every `x`, NaN included. Both `==` and `ieee_eq` give `-0.0` equal to `0.0`.
>
> **Tradeoffs:**
> - No new surface, no compiler change, no new name. The -0.0 test row goes back into `tests/test_float_total_equality.bl` and the ticket closes.
> - The name stays honest: "ieee" means what IEEE says. Option (b) would ship a function called `ieee_eq` that breaks IEEE, a trap that would live forever in the spec and in training data.
> - The Hash argument stays intact, because it rests on `-0.0 == 0.0`, which nobody wants to change.
>
> ##### Against a sign-aware or bitwise compare (YAGNI)
>
> Nobody has asked for one. No test, no stdlib code and no ticket needs to tell `-0.0` from `0.0` by equality. If a user needs it, `1.0 / x < 0.0` already shows the sign today. A real need later can add a single primitive such as `is_sign_negative()` or `to_bits()` behind its own ticket, not a third equality relation. Three equality relations on one type (`==`, `ieee_eq`, a sign-aware compare) is how a language gets Go-style footnotes without Go's smallness.
>
> **Cross-language note:**
> - Rust: `==` is IEEE. Sign and bits come from `is_sign_negative` and `to_bits`. It has no sign-aware `eq`.
> - Java: `Double.equals` is the odd one. It treats `-0.0` as unequal to `0.0`, and many people say this API is a mistake.
> - Neither one names a sign-aware compare "IEEE".
>
> ##### Proposal 2 (secondary, flag for a later chore, not this ruling): make `is_nan` the primitive
>
> The two predicates can be built from each other: `a.ieee_eq(b)` equals `a == b && !a.is_nan()`. Today `is_nan` is built on `ieee_eq`, so `ieee_eq` is the primitive. If `is_nan` were the builtin, `ieee_eq` could move to `std.float` as plain Blink, and the "from stdlib" phrase would become true:
>
> ```blink
> @pure
> pub fn ieee_eq(self: Float, other: Float) -> Bool {
>     self == other && !is_nan(self)
> }
> ```
>
> The language would keep one builtin predicate, and `is_nan` is the one people actually call. The gain is small, though, and it costs a 2-step bootstrap dance. I list it so the panel can see the surface could shrink, not to ask for a vote now. If the panel likes it, file a `type:chore`. It changes no user-visible meaning.
>
> ##### Vote
>
> Option (a), worded as Proposal 1: change the spec text only. Reject option (b) and any new sign-aware or bitwise equality.

#### Phase A.5 — Mechanical dedupe (moderator)

The moderator's Phase B broadcast. One moderator fact in it was wrong: `is_nan` is also a method, `x.is_nan()`, through `impl FloatPure for Float` after `import std.float`. Devops and aiml caught this in Phase B, and the Phase C ballot corrected it.

##### Option A — every panelist proposed it (sys, web, plt, devops, aiml, min)
`ieee_eq` is IEEE 754 compareQuietEqual (C `==`); it differs from `==` only at NaN; `(-0.0).ieee_eq(0.0)` is `true`. It is a built-in method on Float, not a stdlib fn. Delete "and `-0.0 != 0.0`" and "from stdlib" from the spec sentence. Add the `-0.0` ieee_eq row to tests/test_float_total_equality.bl.
Ticket option (b) (ieee_eq checks the sign bit) was proposed by no panelist; all six said they reject it.

##### Variation V1 — the replacement spec sentence. Proposed texts, verbatim:
- sys: "For IEEE 754 equality (compareQuietEqual, C `==`), use the built-in method `x.ieee_eq(other)`. Under it, `NaN` is unequal to every value, itself included. `-0.0` and `0.0` are equal under both `==` and `ieee_eq`. The two differ only on `NaN`."
- web: "For IEEE 754 equality, use the built-in method `x.ieee_eq(other)`. It is the IEEE 754 equality predicate: it differs from `==` only on NaN. `NaN.ieee_eq(NaN)` is `false`, so NaN is the only value for which `x.ieee_eq(x)` is `false`. `(-0.0).ieee_eq(0.0)` is `true`, the same as `==`."
- plt: "For IEEE 754 equality, use the built-in method `x.ieee_eq(y)`. It is IEEE 754 `compareQuietEqual` (C `==`): `NaN` is unequal to every value, itself included, and `-0.0` equals `0.0`. `ieee_eq` and `==` differ only at `NaN`: `x == y` is `true` exactly when `x.ieee_eq(y)` is `true` or both operands are `NaN`. No equality relation on `Float` tells `-0.0` from `0.0`. To see the sign of zero, read the sign bit."
- devops: "For IEEE 754 comparison, use the built-in method `x.ieee_eq(y)`. It is IEEE 754 `compareQuietEqual` (C `==`): `NaN.ieee_eq(x)` is `false` for every `x`, including NaN itself, and `(-0.0).ieee_eq(0.0)` is `true`. No `Float` equality tells `-0.0` from `0.0`. To test the sign of zero, use `1.0 / x < 0.0`."
- aiml: "For IEEE 754 equality, use the method `x.ieee_eq(y)`. It follows the IEEE 754 equality predicate: it is `false` if either operand is `NaN`, and otherwise it agrees with `==`. In particular, `(-0.0).ieee_eq(0.0)` is `true`. Under `ieee_eq`, `NaN` is the only value unequal to itself."
- min: "For IEEE 754 equality, use the method `a.ieee_eq(b)`. It is the IEEE 754 equality predicate (C's `==`). It differs from `==` only on NaN: `NaN.ieee_eq(x)` is `false` for every `x`, NaN included. Both `==` and `ieee_eq` give `-0.0` equal to `0.0`."
Points where these differ: (1) whether to state the formal agreement law (plt); (2) whether to add a sign-of-zero sentence, and which one: none (sys, web, aiml, min), "To see the sign of zero, read the sign bit." (plt), "To test the sign of zero, use `1.0 / x < 0.0`." (devops); (3) "No equality relation/`Float` equality tells `-0.0` from `0.0`" (plt, devops) or not.

##### Variation V2 — follow-up work raised (all proposers said: not in this ruling)
- `is_sign_negative()` method, file only on demand (web W2, devops P3, aiml P2).
- `to_bits() -> U64` as the primitive for bit identity, separate type:spec if wanted (sys P2, plt P2).
- W-class lint `x.ieee_eq(x)` → is_nan with a fix (devops).
- Make `is_nan` the builtin and move `ieee_eq` to std.float as plain Blink, as a type:chore (min P2).
- sys: fast-math caveat (`x != x` folds under -ffast-math) — out of scope.

##### Facts (checked by the moderator)
- `blink_float_cmp(-0.0, 0.0)` returns 0 (Equal): bootstrap/runtime_core.h:2724-2731 returns -1/1 only on `a < b` / `a > b`, both false for the zeros. The runtime comment says it answers 0 for exactly the pairs blink_float_eq answers 1 for. (plt's Ord question.)
- No `to_bits`, `is_sign_negative`, `signbit` or `copysign` exists in sections/, lib/std/ or src/typecheck.bl. Blink today has no API that reads the sign bit.
- `is_nan` is a free function in std.float (`pub fn is_nan(x: Float) -> Bool`, lib/std/float.bl:12), called `float.is_nan(x)`; it is not a method `x.is_nan()`.
- sections/03_types.md:2956: "`Float / Float` performs IEEE 754 division." Only integer `/` and `%` panic on 0. A gen1 probe today: with `let m = -0.0`, `1.0 / m < 0.0` is `true`, `m == 0.0` is `true`, `m.ieee_eq(0.0)` is `true`.

#### Phase B — Debate (one round; all six signalled stable)

**Systems:**

> Sys Phase B on 632psr: Option A holds. On V1 I take plt's law and devops's sign idiom. Stable, ready to vote.
>
> (1) Agreement law: YES, adopt plt's "x == y is true exactly when x.ieee_eq(y) is true or both operands are NaN". It is exact and testable, and it matches blink_float_eq line for line (NaN branches, then C ==). "Differ only at NaN" is looser prose for the same thing.
>
> (2) Sign-of-zero sentence: contest plt's "read the sign bit". Blink has no API that reads it (moderator fact), so that sentence sends users to nothing. devops's `1.0 / x < 0.0` works today (gen1 probe). It costs one divsd, about 10-20 cycles against one movq for a bit read, which is acceptable for a rare query. NaN gives false and -inf gives true, both correct. I take devops's sentence, or no sentence at all. Never one that names a missing API.
>
> (3) "No Float equality tells -0.0 from 0.0": YES. It is true and it closes the door on option (b).
>
> V2: all are fine as separate tickets. Two notes:
> - min P2 (ieee_eq as plain Blink in std.float): it costs codegen unless gcc folds the NaN guards back into one ucomisd. That must be measured, not assumed. Keep ieee_eq builtin until it is.
> - If a sign-bit API comes later, to_bits() is the primitive and is_sign_negative() can be built on it. Do not ship is_sign_negative() as a builtin of its own.
> - fast-math: still out of scope, but someone should file it as a friction ticket.

**Web/Scripting:**

> Web Phase B: Option A, stable, ready to vote. My positions on V1 and V2 follow.
>
> V1(1) Formal law: include plt's law ("`x == y` is true exactly when `x.ieee_eq(y)` is true or both are NaN"). It is one sentence, it is exact, and it ends questions like "where else do they differ?" Tools and LLMs can apply it directly.
>
> V1(2) Sign-of-zero sentence: reject plt's "read the sign bit". The moderator confirmed Blink has no API that reads the sign bit, so a reader who follows that advice finds nothing to call. That turns into a Stack Overflow question. Accept devops's "`1.0 / x < 0.0`", since a gen1 probe shows it works today. It is cryptic, but a working method is better than no method. I am also fine with no sentence. If the panel keeps one, it must be devops's.
>
> V1(3) "No `Float` equality tells `-0.0` from `0.0`": include it. That is exactly the question a reader asks after reading this paragraph, so answer it in the spec.
>
> One more point: write "method `x.ieee_eq(y)`" (aiml/min wording), not "built-in method". If min's P2 chore later moves `ieee_eq` into std.float, "built-in" would make the spec wrong again, which is the same kind of drift that caused this ticket. "Method" is true either way.
>
> V2: I agree all items stay out of this ruling. `is_sign_negative()` should be filed only when a user asks. If the sign-bit work happens, `to_bits()` is a reasonable primitive, but most users would ask for `is_sign_negative` first. The `x.ieee_eq(x)` lint is fine as a separate chore. Min's P2 chore is fine.
>
> Preferred text: min's base sentence plus plt's law plus "No `Float` equality tells `-0.0` from `0.0`." Optionally add devops's `1.0 / x < 0.0` tip.

**PLT:**

> PLT Phase B on 632psr: I am stable and ready to vote for Option A.
>
> V1(1), the agreement law: keep it. The phrase "differs only on NaN" is loose. `NaN == 1.0` and `NaN.ieee_eq(1.0)` are both false, so the two relations differ only on the single pair (NaN, NaN). The law makes that exact: `x == y` iff `x.ieee_eq(y)` or both operands are NaN. It is one sentence, and it is the normative definition the test rows check against. I would accept any text that keeps this iff.
>
> V1(2), sign of zero: I withdraw my "read the sign bit" sentence. The moderator's facts show Blink has no API that reads the sign bit, and the spec must not point at nothing. Adopt devops's `1.0 / x < 0.0`. It rests on specified behavior (03_types: `Float / Float` is IEEE division), and the gen1 probe confirms it. Dropping the sentence is my second choice.
>
> V1(3), "No Float equality tells -0.0 from 0.0": keep it. It is the premise of the E1400/no-Hash argument a few lines up. Stating it pins the coherence argument, so a later change cannot quietly turn ieee_eq into a sign-aware relation.
>
> Ord: closed. `blink_float_cmp` returns 0 for exactly the pairs `blink_float_eq` returns 1 for, so Eq and Ord agree.
>
> V2: no objection to filing these on demand. On min P2, `ieee_eq` written in Blink as `!is_nan(x) && !is_nan(y) && x == y` is correct under the law, so moving it is a sound chore. That is neutral from my side.

**DevOps:**

> DevOps Phase B on 632psr: Option A; V1 = keep the law, cut "read the sign bit"; stable, ready to vote.
>
> V1(1) Agreement law: include plt's sentence ("`x == y` is true exactly when `x.ieee_eq(y)` is true or both are NaN"). This text becomes the hover/`blink doc` text, and one exact rule beats three examples. A reader can check it in one step.
>
> V1(2) Sign of zero: I contest plt's "read the sign bit". Blink has no API that reads the sign bit (moderator fact), so the docs would point users at a method that does not exist. LSP autocomplete finds nothing, and the user files a bug. Use my `1.0 / x < 0.0`, which works today (gen1 probe confirmed). If the panel dislikes the trick, cut the sentence. Never ship text that names a missing API.
>
> V1(3) "No `Float` equality tells `-0.0` from `0.0`": keep it. It answers the exact question that made this ticket, and it closes off a later ticket asking for option (b).
>
> V2:
> - Correction for min/the moderator: `is_nan` IS callable as a method. lib/std/float.bl:36-40 has `impl FloatPure for Float { fn is_nan(self) ... }`, so `x.is_nan()` works once std.float is imported. That covers min P2's goal without making `is_nan` a builtin, so I'm neutral-to-against moving `ieee_eq` out as a chore.
> - My lint (`x.ieee_eq(x)` → `x.is_nan()`) stays a follow-up friction item, not part of this ruling.
> - `is_sign_negative`/`to_bits`: file on demand only, as separate type:spec.
>
> Stable, ready to vote.

**AI/ML:**

> AI/ML Phase B: stable, ready to vote for Option A, with a sign-of-zero sentence added.
>
> V1(1) agreement law: yes, keep it. A precise law lets a model work out each edge case without having to remember it. My phrase "false if either is NaN, otherwise agrees with ==" states the same law as plt's in fewer tokens. Either is fine.
>
> V1(2) sign-of-zero sentence: add one. This is the strongest AI point in the debate. A model asked to "detect -0.0" will write `x.ieee_eq(-0.0)` or `x == -0.0` unless the spec blocks it, and both compile and return the wrong answer. "Read the sign bit" (plt) names something Blink has no API for, so a model cannot act on it and will make up `x.sign_bit()`. Use devops's idiom, which works today: "To test the sign of zero, use `1.0 / x < 0.0`." If `is_sign_negative`/`to_bits` ships later, we change that one line.
>
> V1(3) "No Float equality tells -0.0 from 0.0": yes. It is a negative rule, and negative rules stop the wrong-pattern guess. It is also the lead-in to (2).
>
> V2: none of it goes in this ruling. I agree with the filing on demand for `is_sign_negative`/`to_bits`. I support devops's W-lint `x.ieee_eq(x)` → is_nan. Small correction to the moderator facts: lib/std/float.bl also has `impl FloatPure for Float { fn is_nan(self) }`, so `x.is_nan()` works as a method after the import too. That helps min P2 and the lint fix text.

**Minimalism:**

> Min Phase B on 632psr: Option A, stable, ready to vote.
>
> V1 (1) agreement law: drop it. "Differs from `==` only on NaN" already states it. A formal biconditional adds words without adding meaning.
>
> V1 (2) sign-of-zero sentence: none. If the panel wants one, only devops's text is true. plt's "read the sign bit" points at an API that does not exist (moderator fact: no to_bits/signbit/copysign), so the spec would send users to a dead end. Reject plt's wording outright.
>
> V1 (3) "No Float equality tells -0.0 from 0.0": accept. It is one short sentence, and it stops a reader from hunting for a third relation. It also states the outcome of this ruling.
>
> My merged text: "For IEEE 754 equality, use the built-in method `x.ieee_eq(y)`. It is the IEEE 754 equality predicate (C `==`) and differs from `==` only on NaN: `NaN.ieee_eq(x)` is `false` for every `x`, NaN included. No `Float` equality tells `-0.0` from `0.0`."
>
> V2: Everything stays out of this ruling. Reject the lint: it is new surface with no reported misuse. `is_sign_negative` and `to_bits`: file only when a real user asks. Do not open a ticket ahead of need. My P2 (make is_nan the builtin, move ieee_eq to std.float): I downgrade it to an optional chore note. It changes no user-visible meaning, so it must not block or shape the vote.

#### Phase C — Final vote

The ballot:

##### Ballot — answer every question
Q1. Meaning of `ieee_eq`.
  A: IEEE 754 compareQuietEqual (C `==`); `(-0.0).ieee_eq(0.0)` is `true`; differs from `==` only at NaN.
  B: ticket option (b): `ieee_eq` also checks the sign bit, so `(-0.0).ieee_eq(0.0)` is `false`.
Q2. State the agreement law in the spec ("`x == y` is `true` exactly when `x.ieee_eq(y)` is `true` or both operands are NaN")?  YES / NO
Q3. Sign-of-zero sentence.
  D: add "To test the sign of zero, use `1.0 / x < 0.0`." (devops)
  N: add no sign-of-zero sentence.
Q4. Include "No `Float` equality tells `-0.0` from `0.0`."?  YES / NO
Q5. How the spec names it.
  M: "the method `x.ieee_eq(y)`" (no built-in/stdlib claim)
  BI: "the built-in method `x.ieee_eq(y)`"
Q6. File a follow-up ticket for a lint `x.ieee_eq(x)` → `x.is_nan()` with a fix?  YES / NO
Q7. File a follow-up type:chore to make `is_nan` the primitive and move `ieee_eq` into std.float as plain Blink?  YES / NO

**Systems:**

> Sys votes on 632psr: Q1 A, Q2 YES, Q3 D, Q4 YES, Q5 M, Q6 NO, Q7 NO.
>
> Q1: A
> Reasoning: A is one ucomisd or fcmp, it is the real IEEE predicate, and is_nan plus the slice's tests already depend on it. B adds a sign-bit test, so it costs more and the name would be false.
> Concern: users may still assume ieee_eq separates the zeros. Q4 is what stops that.
>
> Q2: YES
> Reasoning: the law states exactly what blink_float_eq does: the NaN branches first, then C ==. It is exact and testable, while "differs only at NaN" is loose (the two differ only on the pair (NaN, NaN)).
> Concern: a reader may take the law as describing the codegen instead of the semantics. It does not describe the codegen.
>
> Q3: D
> Reasoning: the idiom works today with no new API. It costs one divsd, about 10-20 cycles, which is fine for a rare check. It gives false for NaN and true for -inf, both correct.
> Concern: it pins a trick in the spec. Replace it with to_bits() if that ever ships.
>
> Q4: YES
> Reasoning: it is true, it rules out option (b) for good, and it is the premise of the no-Hash/E1400 argument.
> Concern: none worth naming.
>
> Q5: M
> Reasoning: "method" is true whether the compiler or std.float provides it. Users see the same cost and call syntax either way.
> Concern: users may assume they must import std.float. Today they do not.
>
> Q6: NO
> Reasoning: `x.ieee_eq(x)` and `x.is_nan()` compile to the same instruction, so the lint would add new surface for a style choice no one has complained about. The lint would also fire inside float.bl itself.
> Concern: if NO loses, the lint must exempt std.float.
>
> Q7: NO
> Reasoning: ieee_eq written in plain Blink is `!a.is_nan() && !b.is_nan() && a == b`, which is three compares and branches unless gcc folds them back into one ucomisd. Nobody has measured that. The builtin is the zero-cost form, so file this only with a codegen diff in hand.
> Concern: if YES wins, the chore must show the -O2 assembly matches before merging.

**Web/Scripting:**

> Web Phase C votes on 632psr: Q1 A, Q2 YES, Q3 D, Q4 YES, Q5 M, Q6 YES, Q7 NO.
>
> Q1: A.
> Reasoning: A method named "ieee" must do what an IEEE web search says it does: JS `===`, Python `==` and C `==` all give -0.0 == 0.0. Option B would generate a steady stream of "Blink IEEE compare isn't IEEE" questions.
> Concern: Some readers will still expect `ieee_eq` to separate the zeros, so the spec sentence must state the -0.0 result outright.
>
> Q2: YES.
> Reasoning: plt is right that "differs only on NaN" is loose, since `NaN == 1.0` and `NaN.ieee_eq(1.0)` agree. One exact sentence ends the "where else do they differ?" follow-ups, and tools and LLMs can apply it directly.
> Concern: Some readers will skim past a formal biconditional, so keep the plain-words NaN example beside it.
>
> Q3: D.
> Reasoning: Once the spec says no equality tells the zeros apart, the next question is "then how do I check?" A working answer is better than silence. `1.0 / x < 0.0` works today, and we change that one line if `is_sign_negative` ships.
> Concern: The idiom is cryptic, and people may copy it for nonzero x without the `x == 0.0` guard.
>
> Q4: YES.
> Reasoning: It answers the exact question that started this ticket, and it stops people guessing `x == -0.0` or `x.ieee_eq(-0.0)`. Negative rules prevent wrong code better than examples do.
> Concern: If a sign-aware relation is ever added, this sentence goes stale, so it must be edited in the same change.
>
> Q5: M.
> Reasoning: "Built-in" and "from stdlib" are implementation claims, and the wrong one of those is what caused this ticket. "Method" is true wherever `ieee_eq` lives, and users call it the same way either way.
> Concern: None material; doc tools may still need to say where the method is defined.
>
> Q6: YES.
> Reasoning: `x.ieee_eq(x)` is a C-ism (`x != x`) that a JS or Python developer cannot read at a glance. `x.is_nan()` says what it means. A lint with an auto-fix is cheap teaching. File it as low-priority friction, not urgent.
> Concern: The lint might fire inside std.float's own `is_nan` body, so that body needs an exemption or the lint creates noise.
>
> Q7: NO.
> Reasoning: YAGNI: users see no difference, and sys has a real codegen-cost question that nobody has measured. Q5 M already makes the spec neutral about where `ieee_eq` lives, so the chore can wait until someone has a reason for it.
> Concern: `is_nan` stays defined through `ieee_eq`, which is a little odd to read in std.float, but it costs users nothing.

**PLT:**

> PLT Phase C votes on 632psr: A / YES / D / YES / M / NO / NO.
>
> Q1: A. Reasoning: compareQuietEqual is a partial equivalence relation, and its reflexive closure is exactly Blink's `==`, so the two relations compose cleanly. Option B is neither IEEE equality nor bit identity (NaN payloads would still differ), so it has no clean law. Concern: someone later asks for sign-aware equality and tries to reuse this name. Q4 blocks that.
>
> Q2: YES. Reasoning: "differs only on NaN" is loose, because the relations differ on one pair only, (NaN, NaN). The biconditional is the normative definition, it is testable, and it matches blink_float_eq line for line. Concern: readers skim past a formal sentence, so the prose examples must stay next to it.
>
> Q3: D. Reasoning: `1.0 / x < 0.0` rests on specified IEEE division and works today. Without the sentence, readers will write `x == -0.0`, which is well typed but semantically wrong. Concern: when `to_bits` or `is_sign_negative` ships, this line must change, or the spec teaches an indirect idiom.
>
> Q4: YES. Reasoning: this sentence is the premise of the no-Hash/E1400 coherence argument, and stating it pins that argument. Concern: none of substance.
>
> Q5: M. Reasoning: the spec should state the type and meaning, not where the method is implemented. "Built-in" is an implementation claim, and that kind of claim caused this ticket. Concern: readers may look for it in std.float and not find it there.
>
> Q6: NO. Reasoning: `x.ieee_eq(x)` is a correct NaN test with no semantic hazard. A lint adds surface with no soundness gain, and its fix needs an import. Concern: none if left out. File it only if someone reports misuse.
>
> Q7: NO. Reasoning: either direction is sound, since each can be defined from the other. `ieee_eq` is the more general relation, so it is the natural primitive, and sys's codegen cost is unmeasured. Concern: none if left out.

**DevOps:**

> DevOps votes on 632psr: Q1 A, Q2 YES, Q3 D, Q4 YES, Q5 M, Q6 NO, Q7 NO.
>
> Q1: A
> - Reasoning: The hover and `blink doc` text must match the name. An "IEEE" method that breaks IEEE would mislead every reader. A also matches the codegen (C `==`) and is_nan's doc, so no code changes. Only the spec text and one test row change.
> - Concern: Someone who wants to detect -0.0 may reach for `ieee_eq` anyway. Q3/Q4 must block that.
>
> Q2: YES
> - Reasoning: One exact rule makes better hover text than three examples. plt is right that "differs only on NaN" is loose. The two relations differ only on the pair (NaN, NaN). A test can check the law directly.
> - Concern: The sentence is formal, and a casual reader may skim past it, so keep the plain examples next to it.
>
> Q3: D
> - Reasoning: The idiom works today (gen1 probe), and it names no API that does not exist. Without it, users and models write `x == -0.0` to detect -0.0. That compiles and gives the wrong answer, and no diagnostic can catch it.
> - Concern: If `is_sign_negative`/`to_bits` ships, this line must change in the same commit, or the spec points at the clumsy way.
>
> Q4: YES
> - Reasoning: It answers the exact question this ticket came from. It is also the premise of E1400 (no Float Hash), so the spec should state it.
> - Concern: None worth a sentence beyond keeping it next to the E1400 text.
>
> Q5: M
> - Reasoning: web's point holds. "Built-in" or "stdlib" claims are what made this sentence wrong the first time. "Method" stays true wherever the code lives, and LSP autocomplete shows it the same way either way.
> - Concern: A reader who looks for its source in lib/std will not find it. That is minor.
>
> Q6: NO
> - Reasoning: I withdraw my own proposal. The only `x.ieee_eq(x)` site in the repo is the definition of `is_nan` itself, so the lint would need an allow there and would catch nothing else. File a ticket when a real misuse appears.
> - Concern: None.
>
> Q7: NO
> - Reasoning: It changes nothing a user sees. sys says it may cost codegen until someone measures it. With Q5=M, the move stays open later at zero spec cost.
> - Concern: None.

**AI/ML:**

> AI/ML Phase C votes for ticket 632psr.
>
> Q1: A
> Reasoning: The name says "IEEE", so a model will recall IEEE equality, which is also what C, Rust, Python and JS do with float `==`. Option B would make the name contradict what every model already knows. Its wrong results would compile and pass most tests without anyone seeing them.
> Concern: Old text or examples that say "-0.0 != 0.0" could stay somewhere else in the docs. Grep sections/ and `blink llms` output for that phrase.
>
> Q2: YES
> Reasoning: A model can apply one exact rule to any pair of values. "Differs only on NaN" leaves open whether `NaN.ieee_eq(1.0)` differs from `NaN == 1.0`, and plt showed it does not. The extra cost is one sentence.
> Concern: Two sentences that say almost the same thing can read as two different rules. Write the law so it clearly restates "differs only at NaN" and does not add a new rule.
>
> Q3: D
> Reasoning: Without a working idiom, a model asked to detect -0.0 writes `x == -0.0` or `x.ieee_eq(-0.0)`. Both compile and both are wrong. `1.0 / x < 0.0` works today and needs no new API.
> Concern: If `is_sign_negative`/`to_bits` ships later and nobody updates this line, the spec will teach a trick when a clear method exists.
>
> Q4: YES
> Reasoning: A rule that says what does not exist stops a model from making up a third equality. It also states the premise behind the E1400 no-Hash rule.
> Concern: None that matters. It holds as long as no sign-aware equality is added later.
>
> Q5: M
> Reasoning: "Method" is true whether the compiler or std.float provides it, so the spec cannot go stale the way "from stdlib" did. Users do not need to know where it is implemented.
> Concern: If it ever moves into std.float, it would need an import, and the spec would then have to say so.
>
> Q6: YES
> Reasoning: Models trained on C write `x != x` or `!x.ieee_eq(x)` to test for NaN. A lint with an automatic fix moves code to `x.is_nan()`, which is easier to read. A fix that compilers apply is the cheapest way to correct a habit models learned from training data.
> Concern: The fix must also add the `std.float` import, or the fixed code will not compile.
>
> Q7: NO
> Reasoning: With wording M, this changes nothing for the spec or for learnability. sys raised a real codegen cost that nobody has measured yet. File it only if a measurement shows no cost.
> Concern: Keeping two primitives (builtin `ieee_eq` and std `is_nan`) means two things to keep in sync. That is minor.

**Minimalism:**

> Min Phase C votes, ticket 632psr.
>
> Q1: A
> Reasoning: IEEE names the predicate, so `ieee_eq` must mean what IEEE says. Option B adds a third equality relation behind a false name. All shipped code and tests already implement A, so A costs only a text edit.
> Concern: Users may still expect `ieee_eq` to show the sign of zero, because the old spec text said so. Q4 covers this.
>
> Q2: YES
> Reasoning: plt is right that "differs only on NaN" is loose. The two relations disagree only on the pair (NaN, NaN). One exact rule beats a loose phrase plus examples, provided it REPLACES the loose phrase rather than sitting beside it. Fewer words with more meaning is the minimal choice.
> Concern: The editor may keep both the law and "differs only on NaN" and add words for nothing. Cut the loose phrase.
>
> Q3: N
> Reasoning: `1.0 / x < 0.0` is a trick, not an API. Putting it in the spec makes it a de facto idiom that we would have to change later. Q4 already blocks the wrong guess. Readers who need the sign of zero are rare and can file a ticket.
> Concern: If D wins, the idiom becomes permanent training data even after `is_sign_negative` ships, so change that line the same day the API lands.
>
> Q4: YES
> Reasoning: One short negative rule. It closes off option (b) for good and is the premise of the E1400/no-Hash argument.
> Concern: If a sign-aware API is added later, someone may read this line as forbidding it. It forbids only an equality relation, not a sign query.
>
> Q5: M
> Reasoning: "Method" is true whether `ieee_eq` lives in the compiler or in std.float. "Built-in" is the kind of claim about where code lives that drifted and caused this ticket. Fewer words, and nothing that can go stale.
> Concern: Readers looking for its home get no hint. `blink doc` and the method index cover that.
>
> Q6: NO
> Reasoning: Nobody has reported misusing `x.ieee_eq(x)`, and std.float itself uses that form on purpose. A lint is new tool surface with no proven need.
> Concern: If it wins, it must not fire inside std.float's own `is_nan`.
>
> Q7: NO
> Reasoning: I raised it, and I now vote against filing it. It changes no user-visible meaning. sys notes a possible codegen cost that nobody has measured. YAGNI applies to my own ideas too.
> Concern: If filed, it needs a perf measurement before merge. Otherwise it is churn for neatness.

#### Phase D — Round 2 on Q6

Q6 came out 4-2 (NO: sys, plt, devops, min; YES: aiml, web), which triggered one focused round. Each panelist replied to the other side and gave a final Q6 vote in one message. Final: 6-0 NO.

**Systems:**

> Sys final Q6 vote: NO, but aiml's data points at a different lint that does deserve a ticket.
>
> The habit aiml names is real, but it points at the wrong lint. In Blink, a C-trained model's `x != x` is the hazard: under total Eq it is always false, so it compiles and silently never detects NaN. `x.ieee_eq(x)` is correct, and it compiles to the same instruction as `x.is_nan()`. A lint on it catches nothing. A lint on `x != x` / `x == x` for Float (constant result, fix: `x.is_nan()`) would catch a real bug. I suggest filing that one instead, outside this Q6 vote.
>
> FINAL Q6: NO.
> Reasoning: `x.ieee_eq(x)` is a correct NaN test at the same cost as `x.is_nan()`, so the lint adds surface with no bug to catch.
> Concern: the real hazard, Float `x != x`, stays uncaught unless someone files it separately.

**Web/Scripting:**

> Web Phase D: I switch my final Q6 vote to NO.
>
> Response: devops's evidence settles it for me. The only `x.ieee_eq(x)` site in the repo is the body of `is_nan` itself, so the lint would catch nothing and would need an exemption on day one. The fix also has to add an import (plt and aiml), so it is not the cheap auto-fix I pictured. The readability argument still holds, but I applied YAGNI to every other follow-up in this ruling, and I should apply it here too. aiml's model-habit point is a good reason to watch for misuse, not yet a reason to build the lint.
>
> FINAL Q6: NO.
> Reasoning: No real misuse exists, so a lint adds tool surface that buys nothing today.
> Concern: If generated code starts using `!x.ieee_eq(x)` widely, someone must notice and file the ticket then.

**PLT:**

> PLT Phase D on Q6: final vote NO.
>
> To aiml and web: your argument puts two habits together. `!x.ieee_eq(x)` is correct and only reads less clearly, so a lint on it fixes style. The real hazard is the other habit, `x != x`. Under Blink's total `==` it is always false for Float, so a model trained on C gets a silent wrong NaN test. That deserves a lint ("Float self-comparison is constant; use `x.is_nan()`"), but it is not the lint in Q6, and I suggest filing it as separate friction.
>
> FINAL Q6: NO. Reasoning: the lint would rewrite code that is already correct, gains no soundness, and fires only on `is_nan`'s own definition. Concern: if nobody files the `x != x` lint, the actual C-habit hazard stays unchecked.

**DevOps:**

> DevOps final Q6 vote: NO.
>
> Response to aiml and web: they are right that models carry the C habit. But in Blink the C habit is `x != x`, not `x.ieee_eq(x)`. Under total Eq, `x != x` is always `false`, so a model's NaN check silently never fires. That is a real hazard a lint should catch: Float `x != x` / `x == x` is constant, so suggest `x.is_nan()`. `x.ieee_eq(x)` is correct code, and linting it is only about style.
>
> FINAL Q6: NO.
> - Reasoning: The lint as worded targets correct code. The C-habit risk sits in `x != x`, which is a separate, stronger lint idea I would file as friction outside this ruling.
> - Concern: If nobody files the `x != x` lint, the real NaN-check bug stays silent.

**AI/ML:**

> AI/ML Phase D, Q6: I change my vote to NO.
>
> The NO side is right. `x.ieee_eq(x)` gives the correct answer, and its only use in the repo is the body of `is_nan`. The habit I was worried about is a different one: a model trained on C writes `x != x`. In Blink, Float `==` is a total order, so that test is always `false` and quietly returns the wrong answer. That is the real hazard, and the Q6 lint does not catch it.
>
> FINAL Q6: NO
> Reasoning: `x.ieee_eq(x)` is correct code, so a lint against it adds surface with no correctness gain.
> Concern: The `x != x` / `x == x` on Float hazard stays uncaught. I suggest a separate friction ticket for a lint that flags self-comparison on Float as always false or always true, with `x.is_nan()` as the fix.

**Minimalism:**

> Min Phase D on Q6: final vote NO.
>
> To aiml and web: you name the wrong habit. `!x.ieee_eq(x)` is correct; it only reads poorly. The real hazard in your argument is the C habit `x != x`. Under Blink's total `==` it is always `false`, so it silently never detects NaN. That is a soundness bug worth a lint. A readability lint on a correct form, which fires only in its own definition, is not. If anyone files a lint ticket, file it for `x != x` / `x == x` on Float (always false / always true).
>
> FINAL Q6: NO.
> Reason: The lint would change a correct idiom for style, and the repo has zero real sites.
> Concern: Under NO, nobody may file the `x != x` lint, which is the one models will actually trip on, so the moderator should log it as friction.

### Final Spec

§3 *Float Total Ordering*, after the list of total-order rules:

> For IEEE 754 equality, use the method `x.ieee_eq(y)`. It is the IEEE 754 equality predicate (C's `==`): `NaN` is unequal to every value, itself included, and `(-0.0).ieee_eq(0.0)` is `true`. `x == y` is `true` exactly when `x.ieee_eq(y)` is `true` or both operands are `NaN`. No `Float` equality tells `-0.0` from `0.0`. To test the sign of zero, use `1.0 / x < 0.0`.

```blink
let nan = 0.0 / 0.0
assert(nan == nan)              // total order
assert(!nan.ieee_eq(nan))       // IEEE: NaN is unequal to itself
assert(-0.0 == 0.0)
assert((-0.0).ieee_eq(0.0))     // IEEE: the zeros are equal
assert(1.0 / -0.0 < 0.0)        // the sign of zero
```

- `ieee_eq` is IEEE 754 compareQuietEqual. It is not sign-aware and not bitwise.
- `==` is the reflexive closure of `ieee_eq`: the two differ only on the pair (`NaN`, `NaN`).
- No `Float` equality tells `-0.0` from `0.0`. This is the premise of the no-`Hash` rule (E1400).
- The spec does not say where `ieee_eq` is implemented.
- `1.0 / x < 0.0` is the sign-of-zero test until a sign-bit API exists. A later `to_bits()` or `is_sign_negative()` must replace this line.
