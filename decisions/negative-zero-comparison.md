[< All Decisions](../DECISIONS.md)

# Negative Zero Comparison — Design Rationale

**Gap:** Under the total order, `-0.0 == 0.0` is `true` (§3.6 *Float Total Ordering*), and so is `(-0.0).ieee_eq(0.0)`. Code from C, Rust or JavaScript writes `x == -0.0` as a sign test, and it is silently true for `0.0`. The Float Bits panel (Q3b) gave the sign test `is_sign_negative()` and asked for a warning on a comparison with the literal `-0.0`, to ship before the next release.

```blink
fn classify(x: Float) -> Str {
    if x == -0.0 { return "negative zero" }   // true for 0.0 too
    "other"
}
```

## Result

| Question | Result | Vote |
|---|---|---|
| Settled in Phase B | `NegativeZeroComparison`, W0706, Float and F32. Operand predicate N (one unary `-` over a zero float literal, parentheses allowed; `-(-0.0)` does not match); no const or `let` following, no folding, no flow analysis. `==`, `!=`, `ieee_eq` covered; `0.0 * -1.0`, `-x`, `from_bits`, `min`/`max`, `contains` not covered. Fires in test blocks and `assert_panics` bodies. Help names `is_sign_negative()`; no machine-applicable fix for `==`/`!=`. `@allow`, `[lints]`, `[lints]` only at module scope. A friction ticket for the pattern grammar gap | all six, Phase B round 1 |
| Q1 Ordering | `<`, `<=`, `>`, `>=` and `cmp` are covered, with their own label | 6-0 |
| Q2 Asserts | `assert_eq` / `assert_ne` are covered when `T` is `Float` or `F32` | 6-0 |
| Q3 Both literal | Fires; no exemption | 6-0 in Phase D, after 4-2 in Phase C (DevOps, AI/ML for Exempt) |
| Q3b Example form | Marked: the *Float Total Ordering* example keeps its literal lines with a `// warning[NegativeZeroComparison]` comment, as the W0704 example does | 6-0 in Phase D |
| Q4 Const | Out: a `const` reference does not trigger it (W0704 parity) | 6-0 |
| Q5 Patterns | One forward sentence in the section text: a change that adds a pattern form that can write `-0.0` must bring it under W0706 or make it an error | 5-1 (Min dissent: no spec text) |
| Q6 Resolved relation | The check runs in typecheck on calls that resolve to the concrete `Float`/`F32` impl, so `.eq`, `.ne`, `.cmp` count; no diagnostics from mono | 6-0 |
| Q7 Ordering fix | None: `blink fix` applies nothing for any form; an editor may offer code actions | 5-1 (PLT dissent: ordering-only fix) |
| Q8 Diagnostic details | Span on the N operand; simple-path help, bind-first otherwise, never repeat a call; a `note:` that `0.0` means the same; `blink explain` with `to_bits()` and no literal above `Int` max | 6-0 |

AI-first review: 5/5 pass. The user signed off on the tally, including the reading of Q3b as the three marked lines in *Float Total Ordering*.

**Conditions for the implementation (from the Phase C and Phase D ballots).**
- Sweep `sections/`, the llms docs, `lib/std` and `tests/` for each written `-0.0` operand of a covered comparison, and mark or rewrite each one. The gate is zero *unmarked* W0706 hits (DevOps, Web, AI/ML, Min; Sys on the marker conflict).
- A doc-example check: each W0706 hit sits on a line with `// warning[NegativeZeroComparison]`, and each marker matches a hit (DevOps).
- Match on the resolved callee, not the method name (Sys, PLT, AI/ML).
- "Simple path" is a name, or a field access on a simple path; no call, no index; the help text gets a golden test (DevOps, PLT, AI/ML, Sys).
- The ordering label must be correct for `cmp`, which returns an `Ordering` (Sys).
- `blink explain W0706` says a `const` or `let` that holds -0.0 is not checked and does not fix a sign test, and names `xs.contains(-0.0)` as out (PLT, AI/ML, DevOps, Web).

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in independent-proposal → debate → vote rounds. The texts below are each panelist's own reply, verbatim; only heading levels are changed and local ticket IDs removed.

#### Phase A — Independent proposals

##### Systems

Systems seat, Phase A: one syntactic warning, W0706 NegativeZeroComparison, on every comparison against a written -0.0

###### Proposal S1 (primary): `NegativeZeroComparison` (W0706)

**Rule.** The compiler gives W0706 when one operand of a Float or F32 comparison is a *written negative zero*, and the other operand is not a float literal.

- **Written negative zero**: a float literal with the value 0 (`0.0`, `0.00`, `0e0`), with exactly one unary `-`, and optional parentheses at any level: `-0.0`, `(-0.0)`, `-(0.0)`, `-((0.0))`.
- **Comparisons covered**: `==`, `!=`, `<`, `<=`, `>`, `>=`, `x.ieee_eq(y)` (receiver or argument), and the arguments of the built-in `assert_eq` / `assert_ne` when `T` is Float or F32.
- **Not covered** (the W0704 rule: read only what is written): a `const` or `let` that holds -0.0; `0.0 * -1.0`; `-x`; `Float.from_bits(...)`; `-(-0.0)`. No flow analysis. It fires in a branch that never runs, and in test blocks.
- **Both operands literal** (`(-0.0).ieee_eq(0.0)`, `-0.0 == 0.0`): no warning. The result is a constant, and the code shows the rule; it does not test a value. This keeps spec line 3512 (`assert((-0.0).ieee_eq(0.0))`) clean.

```blink
fn classify(x: Float) -> Str {
    if x == -0.0 { return "neg zero" }   // warning[NegativeZeroComparison]
    if x <= -0.0 { return "non-pos" }    // warning[NegativeZeroComparison]
    "pos"
}

test "sign" {
    assert_eq(neg(0.0), -0.0)            // warning[NegativeZeroComparison]
}
```

```
warning[NegativeZeroComparison]: `-0.0` compares the same as `0.0`
  --> src/main.bl:2:13
   |
 2 |     if x == -0.0 { return "neg zero" }
   |             ^^^^ this comparison is true for 0.0 and -0.0
   = help: to test the sign, use `x.is_sign_negative()`
   = help: to test for negative zero, use `x == 0.0 && x.is_sign_negative()`
   = help: to test for zero, write `0.0`
   = help: to compare bits, use `x.to_bits() == y.to_bits()`
```

The label is per operator family: `==`/`ieee_eq`/`assert_eq` "is true for 0.0 and -0.0"; `!=`/`assert_ne` "is false for 0.0 and -0.0"; ordering "gives the same result as `0.0`". No machine-applicable fix: each rewrite changes behavior, and the compiler cannot know if the user meant "zero" or "negative zero".

**`blink explain W0706`**: shows the three tools side by side for x = 0.0 and x = -0.0: `x == -0.0` (true, true), `x.ieee_eq(-0.0)` (true, true), `x.is_sign_negative()` (false, true), `x.to_bits() == (-0.0).to_bits()` (false, true).

**Suppression.** `@allow(NegativeZeroComparison)` on the fn; `W0706 = "off"|"error"` under `[lints]`; at module scope `[lints]` only (W1011 precedent).

**Why ordering is in (against DevOps).** "Same meaning as 0.0" is the trap, not the excuse. A user who writes `-0.0` thinks the sign matters. `x <= -0.0` (meant: "negative, or negative zero") is true for +0.0. `x > -0.0` (meant: "positive, or positive zero") is false for +0.0. The false-positive rate is near zero: no one writes `-0.0` in a comparison unless they think the sign matters. One rule ("any comparison against a written -0.0") is also easier to spec, test and predict than a list of operators.

**Match arms: no rule now.** The grammar has no negative-literal pattern, and the compiler rejects float literal patterns. A `-0.0 =>` arm cannot be written. The ticket that adds negative literal patterns (if one comes) must carry this warning to them, and the spec says so in one sentence.

**Systems cost.** Zero run-time cost. At compile time it is an O(1) check per comparison node in typecheck, after operand types resolve (it needs Float/F32 to cover `assert_eq` and F32). No const evaluation, no data flow, so the result is stable under refactors that move a value into a `let`, which is the W0704 tradeoff the panel has accepted. The help target is also cheaper than the trap: `is_sign_negative` is one sign-bit test (a shift or AND on the bits; `signbit` in C), not a float compare.

**Tradeoffs.** A `const NEG_ZERO = -0.0` then `x == NEG_ZERO` stays silent. I accept that: the const has a name that a reader sees, and covering it needs const value tracking in the lint, which breaks the "read only what is written" rule that W0704 set. If the panel wants consts in, limit it to a direct reference to a `const` whose initializer is itself a written negative zero (one lookup, no evaluation), not `let`.

###### Proposal S2 (fallback, if ordering is voted out)

The same rule, but only `==`, `!=`, `ieee_eq`, `assert_eq`, `assert_ne`. I still ask that `assert_eq`/`assert_ne` stay in. Tests are where sign-of-zero checks are written most, and `assert_eq(x, -0.0)` passing for 0.0 is the worst form of the trap: a green test that tests nothing.

###### Cross-language

- ESLint `no-compare-neg-zero` covers `==`, `===`, `!=`, `!==`, `<`, `<=`, `>`, `>=` against `-0`: the same scope as S1, and in the recommended set.
- gcc/clang `-Wfloat-equal` warns on every float `==`. Too broad, which is why most people turn it off.
- clippy has no negative-zero lint; `float_cmp` is about epsilon. Go vet has nothing.
- C/Rust/Zig all have the same IEEE `-0.0 == 0.0`, so a model trained on them writes `x == -0.0` and expects a sign test. The warning is the only place the compiler can correct that belief.

##### Web/Scripting

###### Web/Scripting seat — Phase A: warn on the literal as written, fire everywhere, give two help lines

###### Proposal W1 (primary): `NegativeZeroComparison`, W0706

**What triggers it.** It fires when an operand of `==`, `!=` or `ieee_eq` is the literal `-0.0` as written. That means unary `-` on a float literal whose value is zero, with or without parentheses. These all count: `-0.0`, `(-0.0)`, `-(0.0)`, `-0e0`. It does not matter which side the literal is on. It applies to `Float` and `F32`. It also fires when both operands are literals. It fires in test blocks too, because `assert(x == -0.0)` is the bug in its purest form: a test that passes and checks nothing.

```blink
fn main() {
  let x = 0.0
  if x == -0.0 {
    io.println("negative zero?")
  }
}
```

```
warning[W0706]: this comparison is true for 0.0 and -0.0
 --> main.bl:3:6
  |
3 |   if x == -0.0 {
  |      ^^^^^^^^^ `==` does not tell -0.0 from 0.0
  |
  = help: to test the sign, write `x.is_sign_negative()`
  = help: to test for negative zero, write `x == 0.0 && x.is_sign_negative()`
  = note: if you mean zero, write `0.0`
```

For `!=`, the help lines read `!x.is_sign_negative()` and `!(x == 0.0 && x.is_sign_negative())`. For `ieee_eq`, the label reads "`ieee_eq` does not tell -0.0 from 0.0".

**No machine-applicable fix.** There are two likely intents, and they need different rewrites. A fix that writes `0.0` keeps the bug and only hides it. A JS or Python dev reads three short lines faster than they can work out what an auto-fix did.

**`blink explain W0706`** shows one table, with no prose wall:

| You want | Write |
|---|---|
| zero, either sign | `x == 0.0` |
| sign bit set | `x.is_sign_negative()` |
| exactly -0.0 | `x == 0.0 && x.is_sign_negative()` |
| exact bits | `x.to_bits() == y.to_bits()` |

Then one sentence: "`==` and `ieee_eq` both treat -0.0 and 0.0 as equal." Help lines name `to_bits()` exactly (Q6 condition).

**Rulings on the listed cases:**

- **`<`, `<=`, `>`, `>=`: out.** `x < -0.0` means the same as `x < 0.0`. Nobody writes `<` to test a sign, so nobody gets caught. Each warning that fires on code which is not wrong teaches users to turn the lint off.
- **`const`/`let` holding -0.0: out.** This follows the W0704 precedent exactly: the warning reads only the operand as written, with no value tracking. One rule for every literal lint is the 5-minute-learnable story. A user who writes `const NEG_ZERO = -0.0` has already thought about signs. The trap is the inline literal written by reflex.
- **Match arm `-0.0 =>`: write it into the rule now; it does nothing today.** The grammar has no negative-literal pattern, and the compiler rejects float patterns, so this case cannot occur yet. But a JS dev will write it the day float patterns parse. The rule text should say "an operand of `==`/`!=`/`ieee_eq`, **or a match pattern**, that is the literal -0.0". Then the future grammar change cannot forget it. It costs nothing to implement until then.
- **`0.0 * -1.0`, `Float.from_bits(...)`, `-x` where `x` is 0.0: out.** These are not the reflex spelling. Someone who writes `from_bits` knows about bits.
- **Suppression:** `@allow(NegativeZeroComparison)` on the fn, or `W0706 = "off"|"error"` under `[lints]`. That is the standard story, with nothing new to learn.
- **Code:** W0706, the next free code in the Linting band. W0702 is retired; do not reuse it.

**Tradeoffs.** The warning is purely syntactic, so it is cheap, predictable and has zero false positives on the reflex case. It misses value-based spellings, and that miss is deliberate, the same as W0704. The cost is one lint and one explain page. The win is that the most common sign-test mistake gets caught at compile time, not in a bug report three months later.

**Cross-language.** ESLint `no-compare-neg-zero` is the direct model. It is on in `eslint:recommended`, covers `==`, `===`, `!=`, `!==`, `<`, `<=`, `>`, `>=` against the literal `-0`, and points to `Object.is`. I would not copy its ordering-operator coverage. JS `-0 < 0` is false, the same as ours, so that part flags code that is merely odd, not wrong. Clippy has no exact equivalent: `float_cmp` is a broader, noisier lint, which is a warning sign for us. Python has no lint, and "why is `-0.0 == 0.0` True" is a long-running Stack Overflow question. That is the question count this warning cuts.

###### Proposal W2 (fallback, if the panel wants smaller)

Keep W1 but cover only `==` and `!=`, and drop `ieee_eq`. I rank it lower. `ieee_eq(-0.0)` is exactly what someone types after reading that `==` is a total order, so leaving it out is the second trap.

##### PLT

PLT seat, Phase A proposal (negative-zero comparison warning).

###### Principle
A lint needs a clear rule for when it fires. My rule: **warn when the `-` in `-0.0` cannot change the result.** Under the decided total order, `-0.0` and `0.0` are the same element of Float's equality and order. So in every Float comparison, putting `0.0` in place of a `-0.0` operand gives the same result. The minus sign is dead code that looks like a sign test. Each rule below follows from that one fact.

###### P1 (my pick): one syntactic predicate, applied to comparison relations
**Operand predicate N (negative-zero literal), on the AST as written:**
```
N ::= "-" Z | "(" N ")"
Z ::= FLOAT_LIT whose value is zero (0.0, 0.00, 0e0, ...) | "(" Z ")"
```
This covers `-0.0`, `(-0.0)`, `-(0.0)` and `((-0.0))`. It has exactly one minus, so `-(-0.0)` (which is +0.0) does not match. That is right, not a gap. `0.0 * -1.0`, `Float.from_bits(...)`, and a `const`/`let` that holds -0.0 do not match. This is the same "reads only the operand as written" rule as W0704. Two lints in one band should not use two different rules for what counts as a literal.

**Relation set R.** The warning fires when an argument of one of these is N, after typecheck has resolved the call to the Float or F32 impl:
- `Eq.eq` / `Eq.ne`, and so `==`, `!=`, `x.eq(y)`, because §3 makes `==` sugar for `Eq.eq` (spelling does not matter, only the resolved relation)
- `Ord` (`<`, `<=`, `>`, `>=`, `cmp`)
- `ieee_eq`
- `assert_eq` / `assert_ne`

Each of these returns a Bool or Ordering that does not change when N becomes 0.0. **`min`/`max` are out:** with two equal elements, which one comes back can carry the sign, so the `-` can matter there. That is the edge of the invariant, not an arbitrary cut.

Either side can be N. `-0.0 == 0.0` (both literal) also fires.

```blink
fn main() {
    let x = 0.0
    if x == -0.0 { io.println("negative zero?") }
    if x <= -0.0 { io.println("non-positive") }
}
```
```
warning[NegativeZeroComparison]: this comparison is true for 0.0 and -0.0
 --> main.bl:3:13
  |
3 |     if x == -0.0 { io.println("negative zero?") }
  |             ^^^^ `-0.0` and `0.0` are equal, so the `-` has no effect
  = help: use x.is_sign_negative() to test the sign
  = help: use x == 0.0 && x.is_sign_negative() to test for negative zero
warning[NegativeZeroComparison]: this comparison gives the same result for 0.0 and -0.0
 --> main.bl:4:13
  = help: write 0.0, or use x.is_sign_negative() to test the sign
```
Ordering gets a second message text but uses the same code. It can never be a false positive: removing the `-` never changes meaning.

**Generics and mono.** The warning comes from typecheck, before mono. It fires only where the resolved impl is concretely Float or F32. A generic body never warns based on its instantiation, so mono stays free of diagnostics. `xs.contains(-0.0)` is out: the call resolves to `List.contains`, not to a relation in R. I accept this boundary because it is decidable and local. Any wider rule needs effect-like tracking of "uses Eq internally", and that is unprincipled for a lint.

**Patterns.** The grammar has no negative-literal pattern, so `-0.0 =>` is a parse error and there is nothing to warn on. Rule for later: if a signed-literal pattern is ever added, a Float literal pattern matches by `Eq.eq`, so it is in R automatically and the pattern `-0.0` warns. The `0.0` pattern (which matches -0.0) does not warn: its spelling claims nothing false. Separate gap: the grammar also has no `-1` Int pattern. File that as friction, outside this ticket.

**Consts/lets.** Out (W0704 precedent). `const NEG_ZERO = -0.0` is a correct value for arithmetic (`1.0 / NEG_ZERO` is -inf), so warning at the declaration would be a false positive. Warning at the use needs const-value tracking, which W0704 rejected on purpose.

**Code and suppression.** `NegativeZeroComparison`, **W0706**. W0702 is retired; never reuse a retired code. `@allow(NegativeZeroComparison)` on the fn. `W0706` under `[lints]`. A module-scope `const C = x == -0.0` falls under `[lints]` (W1011 precedent). It fires in test blocks too (`assert(x == -0.0)` is the same bug) and inside `assert_panics` bodies. The W0704 exemption exists because a panic is wanted there; nothing like that applies here.

**`blink explain W0706`.** Show three columns for `x = 0.0`, `-0.0`, `NaN`, `-NaN`: `x == -0.0`, `x.ieee_eq(-0.0)`, `x.is_sign_negative()`, plus `x.to_bits()` (named exactly, per the Float Bits condition).

###### P2 (fallback): P1 limited to equality
Same N, but R = {Eq, `ieee_eq`, `assert_eq`/`assert_ne`}. This is simpler to explain ("an equality with -0.0"). Cost: it breaks the single invariant. `x <= -0.0` is just as dead a `-`, and leaving it out has no reason except "rare". I accept P2 only if the panel wants zero ordering noise.

###### Rejected
- Flow or const tracking: not a syntactic predicate, unlike W0704, and it gives false positives on consts used in arithmetic.
- Warning on every `-0.0` literal: false positives on `1.0 / -0.0`.

**Cross-language.** ESLint `no-compare-neg-zero` uses exactly P1's operator set: `==`, `===`, `!=`, `!==`, `<`, `<=`, `>`, `>=` against the literal `-0`, by syntax only, with no tracking of variable values. Clippy has no direct lint. gcc `-Wfloat-equal` is far broader (it warns on every float `==`) and noisy, which is why I bound the rule to the literal.

##### DevOps

DevOps/Tooling Phase A proposal (the -0.0 comparison warning).

###### P1 (main): `NegativeZeroComparison` (W0706), read as written

**Code.** W0706 (W0702 is retired; W0706 is the next free code in the band). The name says what the code does, like `DivisionByLiteralZero`. ESLint calls its rule `no-compare-neg-zero`.

**Trigger.** An operand of `==`, `!=` or `.ieee_eq(...)`, or an argument of `assert_eq`/`assert_ne`, is a negative-zero literal. Its type is `Float` or `F32`. A negative-zero literal is unary `-` on a float literal with value zero (`0.0`, `0.00`, `0e0`). Parentheses can be around the literal or around the whole operand: `-0.0`, `(-0.0)`, `-(0.0)`. The literal can be on either side. Both operands can be literals.

`assert_eq` is the case I most want added. `assert_eq(neg_round(-0.4), -0.0)` passes when the function returns `0.0`. A test that cannot fail is worse than the silent `if`, because it tells the user the code works.

**Out (same as W0704: the warning reads only the operand as written).**
- A `const` or `let` that holds `-0.0`. Following one would need constant propagation, and a lint that sometimes looks through names is hard to predict. Users learn one rule: "the literal, as written".
- `0.0 * -1.0`, `Float.from_bits(...)`, `-x`. Someone who writes these knows about the bits.
- `<`, `<=`, `>`, `>=`. `x < -0.0` means the same as `x < 0.0`. A warning here would be noise, and its help would point at a sign test that nobody asked for.

**Match arms.** No ruling is needed today. The grammar has no negative-literal pattern, and the compiler rejects float literal patterns. I propose a binding note: a future ticket that adds Float or negative-literal patterns must make a `-0.0` pattern fire W0706, or make it an error. That arm would also match `0.0`, which the user did not intend.

**Message.**

```blink
fn main() {
    let x = 0.0
    if x == -0.0 { io.println("negative zero?") }
}
```
```
warning[NegativeZeroComparison]: this comparison is true for both 0.0 and -0.0
 --> src/main.bl:3:13
  |
3 |     if x == -0.0 { io.println("negative zero?") }
  |             ^^^^ `-0.0` equals `0.0` under Float `==`
  |
  = help: to test for negative zero, use `x == 0.0 && x.is_sign_negative()`
  = help: to test the sign of any value, use `x.is_sign_negative()`
  = note: to test for zero, write `0.0`; it means the same and does not warn
```

The help lines name the other operand as the user wrote it, with the receiver in parentheses when it is not a simple name. For `!=`, the first help line is negated: `!(x == 0.0 && x.is_sign_negative())`.

**Fix.** No fix is machine-applicable. Of the two possible repairs, `0.0` keeps the meaning and hides the bug, and the sign test changes the meaning. The compiler cannot know which one the user meant. The language server offers both as code actions ("test for negative zero" / "compare with 0.0"), and `blink fix` applies neither. Precedent: `MixedOperatorPrecedence`.

**`blink explain W0706`.** It shows a side-by-side table for the values `0.0`, `-0.0` and `NaN` (sign set), with the columns `x == -0.0`, `x.ieee_eq(-0.0)`, `x.is_sign_negative()` and `x.to_bits() == (-0.0).to_bits()`. It tells why Float `==` is a total order (link to *Float Total Ordering*) and why `display()` writes `0.0` for both values, so print debugging does not catch the bug either. It also shows the suppression forms.

**Suppression.** `@allow(NegativeZeroComparison)` on the fn, or `W0706 = "off"|"error"` under `[lints]`. Unlike W0704, there is no exception in an `assert_panics` body. Nothing about panics makes the comparison correct.

**Tradeoffs.** No false positives: the check is syntactic, and each hit is either a bug or a no-op `-`. It misses `const NEG_ZERO = -0.0` and then `x == NEG_ZERO`. I accept that. The const site is often deliberate (bit tests), so to warn on the declaration would be noise.

###### P2 (alternative to the const part of P1): also follow a `const` with literal init

A `const` (module-level or local) whose initializer is a negative-zero literal also triggers W0706 at the comparison. The const is known at compile time and needs no flow analysis. The label says ``NEG_ZERO is `-0.0` (declared at L1)``. A `let` is still out. Cost: the rule breaks from W0704's "a const reference does not trigger it". Two lints in the same band would then have different rules. I lean P1 for consistency but would vote for P2 if AI/ML shows that models write a named `NEG_ZERO` const.

###### Cross-language
- ESLint `no-compare-neg-zero`: `==`/`===`/ordering against a literal `-0`; help names `Object.is`. Its ordering coverage is the noise I avoid.
- clippy: no direct lint. `float_cmp` is broader and noisy.
- gcc `-Wfloat-equal`: warns on all float `==`, so people turn it off. That is why this one stays narrow.
- Go vet: none. Go users find this bug at run time.

##### AI/ML

AI/ML seat, Phase A: one rule, "a -0.0 operand of a Float comparison", W0706 NegativeZeroComparison

###### P1 (primary): one syntactic rule over all comparisons

A model learns one rule faster than a list of operators. The rule: **the compiler warns when an operand of a Float comparison is `-0.0` as written.** In every such place, `-0.0` means the same as `0.0`, so the `-` does nothing or the code is wrong.

- Operators: `==`, `!=`, `<`, `<=`, `>`, `>=`, `x.ieee_eq(y)`, and the arguments of `assert_eq` / `assert_ne`.
- "As written": unary `-` applied to a float literal with value zero, with optional parentheses (`-0.0`, `(-0.0)`, `-(0.0)`, `-0e0`). This is the W0704 shape, so a model that learned W0704 already knows it.
- `Float` and `F32` alike.
- Not covered: `0.0 * -1.0`, `Float.from_bits(...)`, a `let` that holds `-0.0`. No flow analysis.

Why the ordering ops too (against DevOps): `x <= -0.0` reads as "negative or negative zero" and is true for `0.0`; `x > -0.0` is false for `0.0`. These are the same trap. Also, the fix for them is machine-applicable and keeps the meaning: replace `-0.0` with `0.0`. For `==` / `!=` the fix is not machine-applicable (intent unknown), so the help names the sign test.

Why `assert_eq`: a model writing a test for a function that must return `-0.0` writes `assert_eq(f(x), -0.0)`. That test passes for `0.0`. A test that cannot fail is worse than no test, because the model then trusts it.

```blink
fn sign_label(x: Float) -> Str {
    if x == -0.0 { return "negative zero" }
    if x <= -0.0 { return "negative" }
    "positive"
}
```

```
warning[NegativeZeroComparison]: this comparison is true for 0.0 and -0.0
 --> src/main.bl:2:13
  |
2 |     if x == -0.0 { return "negative zero" }
  |             ^^^^ Float `==` treats -0.0 and 0.0 as equal
  = help: to test for -0.0, write `x == 0.0 && x.is_sign_negative()`
  = help: to test the sign of any Float, use `x.is_sign_negative()`

warning[NegativeZeroComparison]: -0.0 here means the same as 0.0
 --> src/main.bl:3:13
  |
3 |     if x <= -0.0 { return "negative" }
  |             ^^^^ `x <= -0.0` is true for 0.0
  = help: write `0.0`, or use `x.is_sign_negative()` to test the sign
```

The help substitutes the user's operand text (`x`) when it is a simple path; else it writes `<expr>`. For `!=` the help reads `!(x == 0.0 && x.is_sign_negative())`. One step from diagnostic to correct code, which is what lets a model self-correct without reading the spec.

**Both operands literal** (`-0.0 == 0.0`): it fires. Code that states the order law on purpose (stdlib tests, docs) writes `@allow(NegativeZeroComparison)`. An exemption is one more decision point for a case only the language's own tests hit.

**Name/code:** `NegativeZeroComparison`, W0706 (next free in the Linting band).

**Suppression:** `@allow(NegativeZeroComparison)` on the fn; `W0706 = "off" | "error"` under `[lints]`; module-scope `const`/`let` initializer: `[lints]` only (W1011 precedent). No `assert_panics` exemption (nothing panics here).

**`blink explain W0706`:** a three-row table: `x == -0.0` (true for both zeros), `x.ieee_eq(-0.0)` (true for both zeros), `x == 0.0 && x.is_sign_negative()` (true only for -0.0), plus `x.to_bits() == 0x8000000000000000` named as the bits route with the note that this literal is above Int max today, so the `is_sign_negative` form is the one to copy.

###### P2: `const` that holds -0.0 (split from W0704)

A `const` reference whose value is `-0.0` (`const NEG_ZERO = -0.0` then `x == NEG_ZERO`) also fires. W0704 skips const refs because `if PER_PAGE == 0 { return 0 }` guards make a zero divisor legitimate. There is no legitimate `x == NEG_ZERO`: it always means `x == 0.0`. A const is known at compile time, so this is still no flow analysis. Cost: the rule text gains one clause ("or a `const` whose value is -0.0"). I accept dropping P2 if the panel wants strict W0704 parity; it is the lower-value half.

###### P3: match arms — no ruling in this ticket, one forward sentence

`-0.0 =>` does not parse today (no negative literal pattern; float patterns are rejected). A warning for a form that cannot be written adds spec text a model may copy as valid syntax. Add one sentence: "If a pattern grammar later admits `-0.0`, that pattern is a comparison under this warning." File the missing negative-literal pattern as a separate friction ticket. Note `0.0 =>` matches `-0.0` by value equality; no warning there.

###### Tradeoffs (my domain)

- One rule over all comparisons = zero operator list to memorize, and zero false positives: in every covered spot, deleting the `-` keeps the meaning.
- Covering `assert_eq` targets the place models fail most quietly: generated tests.
- Cost: `<`-family coverage warns on `x < -0.0`, which is correct code. The fix (`0.0`) is free and machine-applied, so the noise costs one keystroke.

###### Cross-language

ESLint `no-compare-neg-zero` covers `==`, `===`, `!=`, `!==`, `<`, `<=`, `>`, `>=` with a `-0` operand, i.e. P1's operator set; its help names `Object.is`. Clippy has no direct lint (`float_cmp` is wider and noisier). gcc `-Wfloat-equal` flags all float `==`: too broad, which is why ESLint's narrow form is the model to copy.

##### Minimalism

Minimalism seat, Phase A: one syntactic warning, the W0704 shape, nothing more.

###### Proposal M1 (primary): `NegativeZeroComparison` (W0706), literal-only

W0702 is retired and W0704 is the precedent, so take the next free code, W0706. A Linting warning.

**Rule.** It fires when an operand of `==`, `!=`, or `ieee_eq` (receiver or argument) is a Float literal with value 0 under a unary `-`, with optional parentheses. That covers `-0.0`, `(-0.0)`, `-(0.0)`, and `-0e0`. It reads only what you wrote: no const following, no let following, no constant folding, no flow analysis. It fires in a branch that never runs. The rule reads the literal, not the type, so F32 gets it for free.

```blink
fn sign_label(x: Float) -> Str {
    if x == -0.0 { return "negative zero" }
    "other"
}
```
```
warning[NegativeZeroComparison]: `-0.0` compares equal to `0.0`
 --> main.bl:2:13
  |
2 |     if x == -0.0 { return "negative zero" }
  |             ^^^^ this comparison is true for 0.0 and -0.0
  = help: to test the sign, use `x.is_sign_negative()`
  = help: to test for negative zero only, use `x == 0.0 && x.is_sign_negative()`
```

The help line puts the other operand's source text in place of `x`. The message names no operator, so `!=` uses the same text. There is no machine-applicable fix: the user might mean "the sign", "negative zero", or just "zero", and the tool cannot tell which.

**`blink explain W0706`** shows three lines side by side and nothing else:
```blink
x == -0.0              // true for 0.0 too: == is the total order
x.ieee_eq(-0.0)        // true for 0.0 too: IEEE says the zeros are equal
x.is_sign_negative()   // reads the sign bit; x.to_bits() gives all 64 bits
```

**Suppression.** Use `@allow(NegativeZeroComparison)` on the fn, or `W0706` under `[lints]`. At module scope, only `[lints]` applies (W1011 precedent). No new mechanism.

###### Rulings on the listed cases

- **`==`, `!=`, `ieee_eq`: in.** This is the trap. `ieee_eq` costs one fixed method name, and it is the second thing a model tries when it believes "IEEE tells the zeros apart".
- **Match arm `-0.0`: no rule.** The pattern grammar has no negative-literal pattern, and the compiler rejects even `0.5 =>`. You cannot write this case today. Do not specify a warning for syntax that does not exist. If negative literal patterns ever land, that change adds one line here. Separate issue: the grammar lists `FLOAT_LIT` but the compiler rejects it. That needs its own friction ticket, not this one.
- **const/let holding `-0.0`: out.** W0704 rejected this for `0`, so do the same here. Following consts brings name resolution and value tracking into a lint, and a let means flow analysis. Users who write `const NEG_ZERO = -0.0` have already met the concept. The cost is real and the gain is small.
- **`<`, `<=`, `>`, `>=`: out.** `x < -0.0` means the same as `x < 0.0`, and that is almost always what the user meant. A warning with no wrong answer to point at is noise. Note: ESLint `no-compare-neg-zero` covers the ordering ops. I think that copies JS shapes without the JS reason.
- **`0.0 * -1.0`, `Float.from_bits(...)`, `-x` where x is 0.0: out.** None of these is a literal. A user who builds negative zero on purpose knows about it.
- **Both operands literal (`-0.0 == 0.0`): does not fire.** That line tests the language, not a value, and the spec itself uses it (`assert(-0.0 == 0.0)` in *Float Total Ordering*). Without this clause, the spec's own example warns. This is the one clause I would drop first if the panel wants zero carve-outs. In that case, rewrite the spec examples with `@allow` instead.

###### Tradeoffs (subtraction lens)

- Each covered form adds a rule that a user, a model, and the compiler must all know. The narrow rule fits on one line of ERROR_CATALOG and matches W0704's shape. A reader who knows W0704 can guess W0706.
- Widening later is cheap in the spec but not free for users: anyone with `W0706 = "error"` breaks when we widen it. So start narrow on purpose and widen only on evidence.
- I reject a general float `==` lint (gcc `-Wfloat-equal`). Blink made `==` a total order on purpose, and warning on every Float `==` would reverse that decision.

###### Proposal M2 (fallback, narrower): `==` and `!=` only

Drop `ieee_eq`. A user who calls `ieee_eq` picked IEEE semantics on purpose and has read *Float Total Ordering*. This saves the method-call special case. I prefer M1 because the cost is one name, but M2 is acceptable.

###### Cross-language

- ESLint `no-compare-neg-zero`: covers the ordering ops too. Blink should not, for the reason above.
- clippy: no direct lint (`float_cmp` is a different problem).
- gcc `-Wfloat-equal`: too broad for a total-order `==`.
- Go vet: none.

#### Phase B — Debate (round 1)

The moderator's deduped option space (V1–V8) went to all six seats. Each seat replied once and signalled STABLE.

##### Systems

Systems seat, Phase B round 1

**V1 ordering: hold In.** Web and Min say `x < -0.0` "has no wrong answer to point at". There is a wrong answer, and it comes from the name of our own rule. IEEE 754 `totalOrder` and Rust `f64::total_cmp` both put `-0.0` *below* `+0.0`. Blink calls its order a "total order" too. So a reader from Rust or IEEE expects `x > -0.0` to be true for `0.0`. In Blink it is false. `x <= -0.0` is true for `0.0`. These are real wrong results, not odd code. Web's JS point (`-0 < 0` is false in JS too) misses this: JS has no `total_cmp` to learn from, and Blink does. Min's own widening argument helps me: adding ordering later breaks every project with `W0706 = "error"`, so decide the full scope now. The cost of a false positive is near zero, because no one writes `-0.0` in a comparison unless they think the sign matters. If ordering goes out, I vote for my S2 or PLT's P2.

On AI/ML's machine-applicable fix for ordering: I hold "no fix for any form". Writing `0.0` keeps the meaning but can hide the bug, which is DevOps's argument for `==`. It applies the same way to `<=`. One rule for the fix is also simpler. Low weight; I will not block on it.

**V2 assert_eq / assert_ne: in.** Four seats agree. A green test that tests nothing is the worst form of this trap.

**V3 both literal: concede, it fires.** Four seats want it, and Min gives it up first. Fewer exceptions means more predictable behavior. Fix the spec example at sections/03_types.md:3511–3512 without `@allow`: `let nz = -0.0` then `assert(nz == 0.0)` and `assert(nz.ieee_eq(0.0))`. A `let` does not trigger the warning, and the example then shows the law on a value, which reads better.

**V4 const: hold Out.** W0704 parity. PLT's `1.0 / NEG_ZERO` shows the const is often correct. If the panel votes it in, keep the narrow form: a direct reference to a `const` whose initializer is a written negative zero. One lookup, no evaluation, and no `let`.

**V5 match: one forward sentence, in the spec.** PLT's wording is the best: a Float literal pattern matches by `Eq.eq`, so a future `-0.0` pattern falls under W0706. I reject Web's "or a match pattern" in the rule text now. The rule would name syntax that does not parse, and a model copies spec text as valid code. Support a separate friction ticket for the grammar (`FLOAT_LIT` listed but rejected; no `-1` Int pattern either).

**V6 scope by resolved relation (PLT): support.** It is what "after typecheck" means in my S1, said better. It covers `x.eq(-0.0)`, `x.ne(-0.0)` and `cmp` with no extra spelling list. Diagnostics come from typecheck on concrete Float/F32 only, so mono stays free of diagnostics. That is a real win: no duplicate warning per instantiation, and no warning that comes and goes when a caller changes. `min`/`max` out: the sign of the result can carry, so the `-` can matter. `xs.contains(-0.0)` out.

**V7 placement: concede.** It fires in test blocks and in `assert_panics` bodies. The W0704 exemption exists because a panic is wanted there. Nothing like that applies here.

**V8 drop ieee_eq: reject.** `ieee_eq` is C's `==`. A C, Rust or Zig user who learns that Blink's `==` is a total order goes to `ieee_eq` next, and still gets `true` for `0.0`. It is the second trap, and it costs one method name.

Summary of my position: core + ordering (with `cmp`) + assert_eq/ne + resolved-relation scope (PLT V6), both-literal fires (spec example rewritten with a `let`), no const, one forward sentence for patterns, no machine-applicable fix.

STABLE

##### Web/Scripting

###### Web/Scripting seat — Phase B round 1

**V1 ordering: I concede, ordering goes in.** Sys moved me. `x <= -0.0` written as "negative, or negative zero" is true for +0.0, and `x > -0.0` written as "positive, or positive zero" is false for +0.0. Those are the same trap, not noise. My noise argument assumed someone writes `x < -0.0` and means `x < 0.0`. Nobody does: if you meant zero, you type `0.0`. So every hit is a bug or a dead `-`, and "write `0.0`" costs one keystroke. Min's own point decides it: widening later breaks every project with `W0706 = "error"`, so set the scope now. I take PLT's form: the same code, a second label for ordering ("gives the same result as `0.0`"), and `cmp` included as a resolved `Ord` relation.

On the fix: no machine-applicable fix for ordering either (against AI/ML). `0.0` keeps the meaning, but it also hides the bug, which is my objection for `==`. Use one rule for the whole code: `blink fix` applies nothing, and the LSP offers both code actions (DevOps). Users remember "W0706 is never auto-fixed" more easily than a per-operator rule.

**V2 `assert_eq`/`assert_ne`: in.** I missed this case. A green test that cannot fail is the worst form of the bug, and it is where people write sign checks.

**V3 both operands literal: I switch to "does not fire" (Sys, Min).** The spec's *Float Total Ordering* example is the first page a JS dev reads about this topic. Putting `@allow` in it to show a law teaches the wrong first lesson. Also, a beginner who types `io.println(-0.0 == 0.0)` is testing the rule, not falling into it. This preference is weak. If the panel keeps "fires", I want the spec examples rewritten with `@allow`, as Min said, not left to warn.

**V4 const: I hold, out.** W0704 parity is the 5-minute story: "the literal, as written". A user who names `NEG_ZERO` has already thought about the sign. PLT's `1.0 / NEG_ZERO` shows that the const itself is legitimate. If P2 wins, it must be Sys's narrow form: a direct reference to a const whose initializer is itself a written negative zero, never `let`.

**V5 match: one forward sentence (AI/ML wording).** It says a future `-0.0` pattern falls under W0706. I drop my "write it into the rule text now" version. Min and AI/ML are right that rule text for syntax that does not parse reads as "this is valid". Yes to a separate friction ticket on the FLOAT_LIT and negative-literal pattern gap.

**V6 resolved relation (PLT): agree.** `x.eq(-0.0)` is the same trap as `==`. Typecheck-only on concrete Float or F32 means a generic body never warns at a distance, which is what users expect. `min`/`max` and `contains` out is a clear line.

**V7: agree.** It fires in tests and inside `assert_panics` bodies. The W0704 exemption has no reason to apply here.

**V8: I withdraw W2.** `ieee_eq` stays in.

**A new point: the AI/ML explain text.** The row `x.to_bits() == 0x8000000000000000` uses a literal at Int max + 1. Q7 says spec examples avoid those, and a reader will copy it and get an error. Use DevOps's `x.to_bits() == (-0.0).to_bits()`, or leave `to_bits` without a comparison.

**Help text:** substitute the user's operand text, with `<expr>` or parentheses when the operand is not a simple name (AI/ML, DevOps). Agree.

STABLE

##### PLT

PLT seat, Phase B round 1

**V1 ordering: hold In.** Web, DevOps and Min say "`x < -0.0` means the same as `x < 0.0`, so it is noise." That sentence is the warning's own claim, not a reason to skip it. The lint states a fact that is always true in the covered places: the `-` has no effect. A `-` that does nothing, written by a user who thinks it does something, is the defect. `x <= -0.0` read as "negative or negative zero" is true for 0.0. Sys and AI/ML show the same trap for `>`. Two more points:
- Web: in JS, `-0 < 0` is false, as it is in Blink, and ESLint covers ordering anyway. The reason JS has is the reason we have.
- Min: "widening later breaks `W0706 = "error"` users" is a reason to decide the full scope now. It does not argue for starting narrow.

I concede AI/ML's point and add it to P1: for ordering, the fix "replace `-0.0` with `0.0`" is machine-applicable, because the result is provably unchanged. For `==`/`!=` there is still no fix, since the intent is unknown.

**V2 assert_eq/assert_ne: In.** Four seats agree. A green test that tests nothing is the worst form of the trap.

**V3 both literal: hold Fires, but I will not block.** The Sys/Min carve-out adds a second test, "the other operand is not a float literal". That test then needs its own rules: is `(0.0)` a literal? `-(1.0)`? A `const`? One rule with no case split composes better. The spec example at 3511–3512 is two lines. Mark them `// warning[NegativeZeroComparison]`, which also teaches the rule, or put them in a fn with `@allow`. If the carve-out wins, its predicate must be exact: "the other operand is also a float literal, with optional parentheses and one unary `-`".

**V4 const: hold Out.** AI/ML is right that `x == NEG_ZERO` is never correct at the use site. But following a const is a new kind of rule, name resolution inside a lint. It splits W0706 from W0704 inside one band. It also leaves new edges: `const A = NEG_ZERO` (a chain), and `const B = (-0.0)` versus `const C = 0.0 - 0.0`. If the majority wants consts in, I accept only Sys's bounded form: a direct reference to a `const` whose initializer itself matches the operand predicate. One lookup, no chain, no `let`.

**V5 match patterns: one normative sentence.** I prefer DevOps's binding form: "A change that adds a pattern able to match only negative zero, or a negative float literal pattern, must bring it under W0706 or make it an error." I am against Web putting "or a match pattern" in the trigger rule now. A rule written over syntax that does not exist cannot be checked or tested. Min's "no text" risks a later grammar ticket missing this case. File the `FLOAT_LIT`/negative-literal pattern grammar gap as separate friction.

**V6 scope by resolved relation: hold.** `==` desugars to `Eq.eq` (§3). A lint that catches `x == -0.0` but not `x.eq(-0.0)` is defined over spelling, not meaning. For the compiler it is the same check on the same resolved call. `cmp` follows from `Ord` once V1 is in. `min`/`max` stay out: with equal elements, which one comes back can carry the sign, so the `-` can matter.

Every seat already says "Float and F32". So does V2, because `assert_eq` is generic. Both need resolved types, so the check runs in typecheck on concrete Float/F32 only. Min's "reads the literal, not the type" works for `==` but not for `assert_eq[T]`. Stating "concrete Float/F32 after typecheck" also settles generics: a generic body never warns from its instantiation.

**V7: hold.** It fires in test blocks and in `assert_panics` bodies. W0704's exemption exists because a panic is the point there. That reason does not apply here.

**V8: reject.** `ieee_eq(-0.0)` is the second thing a user tries after learning that `==` is a total order (Web, Min M1). Dropping it leaves the trap that comes next.

STABLE

##### DevOps

DevOps/Tooling, Phase B round 1

**V1 ordering: I concede, so ordering is in.** Sys and AI/ML gave the case I missed. A user who writes `x > -0.0` to mean "zero or positive" gets `false` for `0.0`. That is a wrong result, not just odd code. Every hit is code where you can delete the `-` and the result stays the same, so there are no false positives. A single rule is also easier to explain on the `blink explain` page than a list of operators. I ask for two things:
- The ordering label has its own text, as Sys proposed for each operator family: "gives the same result as `0.0`". The `==` text ("true for 0.0 and -0.0") does not fit `<`.
- **No machine-applicable fix, for ordering too (against AI/ML).** Replacing `-0.0` with `0.0` keeps the meaning. That is exactly why `blink fix` must not apply it: an unattended run turns a possible bug into clean code with no warning, and nobody reviews it. The language server offers it as a code action that a person picks. The `==` case is the same.

**V2 `assert_eq` / `assert_ne`: hold, in.** Four seats agree. The help needs one tooling rule. `x == 0.0 && x.is_sign_negative()` uses the operand twice, and in a test the operand is usually a call (`assert_eq(neg(0.0), -0.0)`). Copying `neg(0.0)` into both places runs the call twice. So:
- If the operand is a simple path (`x`, `p.y`), the help puts it in directly.
- If not, the help says to bind it first: `let v = neg(0.0)` then `assert(v == 0.0 && v.is_sign_negative())`. It never repeats a call. AI/ML's `<expr>` placeholder is a weaker form of the same idea.

**V3 both operands literal: I change my vote to "does not fire" (Sys, Min).** The spec's own *Float Total Ordering* example has `assert(-0.0 == 0.0)`. That example would warn, and users copy doc examples. Putting `@allow` on a spec example teaches suppression as normal. Also, `@allow` goes on a `fn`, and that example may not sit inside one. With both operands literal, the result is a constant that states the rule; it does not test a value. Sys's wording is clean: "the other operand is not a float literal". The same applies to `-0.0 < 0.0` and to `(-0.0).ieee_eq(0.0)`.

**V4 const: hold, out. I withdraw my P2.** PLT's point decides it: `const NEG_ZERO = -0.0` is a correct value for arithmetic. Also, nobody asked for const-following on evidence. Min is right that widening later is safe, but narrowing later breaks users who set `W0706 = "error"`.

**V5 match: one sentence, in the section text, not in the ERROR_CATALOG row.** It says: "A future pattern form that can spell `-0.0` falls under this warning." I am fine with PLT's reason (a pattern matches by `Eq.eq`). A catalog row that names syntax which does not parse would get copied into the lint docs and into models' output as if it were valid. I support the separate friction ticket (grammar `FLOAT_LIT` vs the compiler; no `-1` Int pattern).

**V6 PLT's resolved relation: I support it.**
- `x.eq(-0.0)` / `x.ne(-0.0)` must count. If they do not, the method spelling slips past the warning.
- `cmp` counts if ordering is in.
- Most important for tooling: the warning is emitted in typecheck, only on concrete Float/F32, and never from mono. A warning emitted per instantiation means duplicate diagnostics and spans inside the generic body that the user cannot fix at the call site. Language-server users would see warnings they cannot act on.
- `contains` and `min`/`max` stay out. Agree.

**V7: hold.** It fires in test blocks and in `assert_panics` bodies, with no W0704-style exemption.

**V8 drop `ieee_eq`: reject.** Web is right: `ieee_eq(-0.0)` is the second thing a user tries.

**Span (small point).** The primary span is the `-0.0` operand, not the whole comparison (Web's example underlines `x == -0.0`). The code action edits that span, and a narrow span keeps two warnings in one long condition easy to tell apart.

STABLE

##### AI/ML

AI/ML seat, Phase B round 1

**V1 ordering: hold In, but I take back "machine-applicable".**
Web, DevOps and Min say `x < -0.0` means the same as `x < 0.0`, so the warning is noise. That is the point: in that place the `-` does nothing, and a model writes `-0.0` only when it thinks the sign matters. `x <= -0.0` ("negative or negative zero") is true for `0.0`, and `x > -0.0` is false for `0.0`. These are wrong answers, not just odd code. My main argument is learnability. "Any Float comparison with a written `-0.0`" is one rule. "`==`, `!=` and `ieee_eq`, but not `<`" is an operator list, and a model must remember which side of the line `cmp` is on. ESLint chose the full set, and models have seen a lot of ESLint output.
Concession to Sys and DevOps: writing `0.0` keeps the meaning but can hide the bug when the user wanted a sign test. So there is no machine-applicable fix for any operator. The LSP offers both rewrites as code actions, and `blink fix` applies neither. The ordering message is the PLT/Sys text: "gives the same result for 0.0 and -0.0".

**V2 assert_eq / assert_ne: hold In.** Four seats agree. Models write their tests themselves, so a test that cannot fail does the most damage there.

**V3 both operands literal: concede, does not fire (Sys, Min).** The spec's own *Float Total Ordering* example (`assert(-0.0 == 0.0)`) is training text. If it warns, a model learns that `@allow` is part of the normal idiom, which is worse than one carve-out. A literal-vs-literal comparison is a constant, so it is never a hidden sign test. Rule text: "and the other operand is not a float literal" (Sys wording). The same applies to `assert_eq(-0.0, 0.0)`.

**V4 const: concede, out.** Four seats are out, and I have no evidence that models write `x == NEG_ZERO`; the reflex form is the inline literal. Matching W0704 exactly means a model that learned one of these lints knows the other. I withdraw P2.

**V5 patterns: one forward sentence, no code example.** I agree with Sys and PLT. Web wants `-0.0 =>` in the rule text now. A spec line that shows `-0.0 =>` will be copied as valid syntax, so the parser error will then fire on code the spec seemed to approve. Wording: "If a future pattern form admits `-0.0`, that pattern falls under W0706." PLT's derivation (a Float literal pattern matches by `Eq.eq`) is the reason for it. I support the separate friction ticket (no negative-literal pattern; the grammar lists `FLOAT_LIT` but the compiler rejects it).

**V6 resolved relation: support PLT.** `x.eq(-0.0)` and `x.ne(-0.0)` are the same trap as `==`, and a model that is told "use the method" will write them. `cmp` is in only if V1 is in. Firing on concrete Float/F32 only, in typecheck, means a warning always points at code the user wrote, never at an instantiation. `contains` and `min`/`max` out: agreed.

**V7: agree.** It fires in test blocks and in `assert_panics` bodies. No exemption, because no panic is expected there.

**V8 drop ieee_eq: oppose.** After a model reads that `==` is a total order, `ieee_eq(-0.0)` is its next try. If that try is silent, the diagnostic has moved the bug instead of fixing it. The cost is one method name.

**Help text:** I endorse DevOps's third line, `note: to test for zero, write 0.0; it means the same and does not warn`. It gives the user a way to clear the warning when they meant zero, so the warning does not stay forever.

STABLE

##### Minimalism

Minimalism seat, Phase B round 1

I concede four points and hold two. Each concession removes a clause or a case-by-case decision, so it fits my lens.

**V1, ordering operators: I concede. Put them in.** PLT's invariant changed my mind: "warn when the `-` cannot change the result." That rule is one sentence. My list ("`==`, `!=`, `ieee_eq`, but not `<`") needed a reason for each cut. The cut I made was based on intent: "`x < -0.0` is what the user meant." Sys and AI/ML show that this is false for `<=` and `>`. `x <= -0.0` reads as "non-positive, sign included", and `x > -0.0` is false for `0.0`. No hit is a false positive, because deleting the `-` never changes behavior. ESLint ships the same set in its recommended config, so we have field evidence that this is not noise. I accept AI/ML's machine-applicable fix (`-0.0` to `0.0`) for the ordering operators only. It keeps the meaning, so it is safe.

**V2, `assert_eq` / `assert_ne`: I concede. Put them in.** A test that cannot fail is the worst form of the trap. The check already needs the resolved operand type for F32, so `T = Float` costs nothing more.

**V3, both operands literal: I concede. It fires.** I called this clause "the first I'd give up", so I give it up now. With no exemption there is one fewer decision point. The spec example at 03_types.md:3511–3512 then needs a rewrite, for example by putting the asserts in a `test` with `@allow(NegativeZeroComparison)`, or by stating the law in prose. That is a spec chore, not a rule clause. Sys, PLT and DevOps: note that the spec's own example warns under this ruling, and that is fine.

**V4, `const` following: I hold. Out.** AI/ML P2 is right that `x == NEG_ZERO` has no legitimate use. But it splits the "read what is written" rule from W0704 inside the same band. Two literal lints would then have two rules for what a literal is, and every later literal lint must pick a side. The person who writes `NEG_ZERO` has named the concept, and the trap we are fixing is the reflex inline literal. Widen it later only if we see the problem, and remember that widening breaks `W0706 = "error"` builds.

**V5, match patterns: I hold. No rule text.** I agree with AI/ML's own reason: spec text about a pattern that cannot be written is text a model will copy as valid syntax. I oppose Web's "or a match pattern" in the rule text. PLT already gives the answer: if a Float literal pattern ever matches by `Eq.eq`, then it is a comparison, and the invariant covers it with no new text. Put the forward note on the friction ticket for negative-literal patterns, where the person who adds the grammar will read it. If the majority wants one sentence, I can accept AI/ML's wording, but not a clause in the rule text.

**V6, scope by resolved relation: partly.** I agree that the check runs in typecheck on concrete Float and F32 only, that a generic body never warns from its instantiation, and that `min`/`max`/`contains` are out. I would not add `.eq`, `.ne` and `.cmp` method spellings. Nobody writes `x.eq(-0.0)`, and every covered spelling is one more test row. That said, if PLT's rule is "resolved relation", the method spellings come at no extra cost in the rule text. I will not block that.

**V7, `assert_panics` and test blocks: agree. It fires in both.** The W0704 exemption exists because a panic is wanted there, and nothing like that applies here. Copying the exemption would be cargo-cult.

**V8: I withdraw M2.** Web is right that `ieee_eq(-0.0)` is the second trap.

Resulting position: written negative zero (PLT's grammar, so `-(-0.0)` does not match), as an operand of `==`, `!=`, `<`, `<=`, `>`, `>=`, `ieee_eq`, `assert_eq` or `assert_ne` on concrete Float or F32. It fires everywhere, including when both operands are literals. No const following, no pattern text. There is a fix for the ordering operators only.

STABLE

#### Phase C — Final vote

| Q | Sys | Web | PLT | DevOps | AI/ML | Min |
|---|---|---|---|---|---|---|
| Q1 Ordering | In | In | In | In | In | In |
| Q2 Asserts | In | In | In | In | In | In |
| Q3 Both literal | Fires | Fires | Fires | Exempt | Exempt | Fires |
| Q4 Const | Out | Out | Out | Out | Out | Out |
| Q5 Patterns | Sentence | Sentence | Sentence | Sentence | Sentence | None *(dissent)* |
| Q6 Resolved relation | Yes | Yes | Yes | Yes | Yes | Yes |
| Q7 Ordering fix | None | None | Ordering-only *(dissent)* | None | None | None |
| Q8 Diagnostic details | Yes | Yes | Yes | Yes | Yes | Yes |

##### Systems

Systems seat, Phase C ballot

**Q1. Ordering operators**
1. **Vote:** In
2. **Reasoning:** IEEE 754 `totalOrder` and Rust `f64::total_cmp` put `-0.0` below `0.0`, and Blink also calls its order a "total order". So `x > -0.0` (false for `0.0`) and `x <= -0.0` (true for `0.0`) give wrong results to a reader from those languages. The check is the same O(1) node test as for `==`, so it adds no compile cost. Deleting the `-` never changes the result, so no hit is a false positive.
3. **Concern:** The second label text ("gives the same result as `0.0`") must be correct for `cmp` too, which returns an `Ordering`, not a Bool.

**Q2. `assert_eq` / `assert_ne`**
1. **Vote:** In
2. **Reasoning:** The check already needs the resolved type for F32, so `T = Float` on a built-in call costs nothing more. A test that passes for `0.0` tests nothing, and tests are where people write sign checks.
3. **Concern:** The help for `assert_eq(f(x), -0.0)` must not copy `f(x)` twice (Q8 b covers this).

**Q3. Both operands literal**
1. **Vote:** Fires
2. **Reasoning:** I proposed the exemption only to keep the spec example clean. The `let nz = -0.0` rewrite does that with no `@allow`, and it shows the law on a value. Without the exemption the predicate stays one test on one operand, with no second test on the other side (PLT's point: is `(0.0)` a literal? `-(1.0)`?). Fewer branches in the rule means fewer branches in the checker and in its tests.
3. **Concern:** If Exempt wins, its predicate must be PLT's exact form, or the checker and the spec will disagree on edge spellings.

**Q4. `const` holding -0.0**
1. **Vote:** Out
2. **Reasoning:** W0704 parity: a const reference never triggers a literal lint in this band. `const NEG_ZERO = -0.0` is a correct value for arithmetic (`1.0 / NEG_ZERO`). Following names brings name resolution into the lint, with edges such as chains and `0.0 - 0.0`.
3. **Concern:** `x == NEG_ZERO` stays silent. Accept it and widen only on evidence.

**Q5. Match patterns**
1. **Vote:** Sentence
2. **Reasoning:** One forward sentence in the section text tells the person who later adds the grammar that this case exists. Put no code example and no catalog row, so no one copies `-0.0 =>` as valid syntax. The friction ticket carries the grammar gap.
3. **Concern:** The sentence must not read as if `-0.0 =>` parses today.

**Q6. Scope by resolved relation**
1. **Vote:** Yes
2. **Reasoning:** `==` desugars to `Eq.eq`, so for the compiler `x == -0.0` and `x.eq(-0.0)` are the same resolved call and the same check. Typecheck-only on concrete Float/F32 means mono gives no diagnostics: no duplicate warning per instantiation, and no warning that changes when a caller changes. The result is predictable from the source alone.
3. **Concern:** The implementation must match on the resolved callee, not on method-name text, or a user method named `eq` on another type will warn.

**Q7. Fix for ordering forms**
1. **Vote:** None
2. **Reasoning:** One rule for the code: `blink fix` never touches W0706. Writing `0.0` keeps the meaning, but an unattended run then hides a possible sign bug with no review. The LSP code action keeps the rewrite one keystroke away for a person who chooses it.
3. **Concern:** If the ordering-only fix wins, `blink fix` will hide the `x > -0.0` bug that is the main reason I argued for Q1 In.

**Q8. Diagnostic details package**
1. **Vote:** Yes
2. **Reasoning:** (a) A narrow span keeps two hits in one condition apart. (b) Never repeating a call matters at the systems level: a repeated call runs its side effects and its cost twice, so bind-first is the only safe help for a non-path operand. (c) The `0.0` note gives a way to clear the warning when zero was meant. (d) `(-0.0).to_bits()` avoids a literal above Int max.
3. **Concern:** In (b), the "simple path" rule must leave out field reads through a getter or computed property if Blink ever adds those, because they are calls too.

##### Web/Scripting

###### Web/Scripting seat — Phase C ballot

**Q1. Ordering operators**
1. **Vote:** In
2. **Reasoning:** `x <= -0.0` and `x > -0.0` give wrong answers for 0.0 when they are read the way people write them. Nobody types `-0.0` when they mean zero. "Any Float comparison with a written `-0.0`" is one rule to learn, where an operator list makes people ask "why not `<`?". ESLint's recommended set shows this is not noise in practice.
3. **Concern:** The ordering label might drift from the `==` label in wording, and then users read two different lints. Keep the code, help and explain page shared.

**Q2. `assert_eq` / `assert_ne`**
1. **Vote:** In
2. **Reasoning:** Tests are where people write sign checks. A green `assert_eq(f(x), -0.0)` that passes for 0.0 is the most costly form of the bug, because it makes the user trust broken code.
3. **Concern:** In a test, the operand is usually a call. The help must not repeat the call (see Q8b), or the copied fix runs it twice.

**Q3. Both operands literal**
1. **Vote:** Fires
2. **Reasoning:** I change from my B1 lean. My only objection was `@allow` on the first spec page a newcomer reads. Sys's rewrite (`let nz = -0.0` then `assert(nz == 0.0)`) removes that objection and reads better, because it states the law on a value. A beginner who types `io.println(-0.0 == 0.0)` gets a warning that teaches them exactly the rule they are testing. Firing means one rule and no carve-out to explain.
3. **Concern:** Someone has to sweep every spec, llms doc and stdlib example that writes `-0.0 == 0.0`, not only lines 3511–3512. If one is missed, the docs warn.

**Q4. `const` holding -0.0**
1. **Vote:** Out
2. **Reasoning:** W0704 parity gives the 5-minute story: "the literal, as written". A user who names `NEG_ZERO` has already thought about the sign, and the const is correct for arithmetic.
3. **Concern:** A user can still write `const NEG_ZERO = -0.0` then `x == NEG_ZERO` and get no warning. The explain page should say this plainly so the silence does not read as approval.

**Q5. Match patterns**
1. **Vote:** Sentence
2. **Reasoning:** A note on a friction ticket gets lost. One sentence in the section text, with no code example, is what the person who adds the grammar will read. It does not show `-0.0 =>` as valid syntax.
3. **Concern:** Someone may still copy the sentence as proof that `-0.0 =>` parses today. Word it "a future pattern form", not as a pattern example.

**Q6. Scope by resolved relation**
1. **Vote:** Yes
2. **Reasoning:** "Use the method" is common advice, and `x.eq(-0.0)` is the same trap with a different spelling. Firing only on concrete Float or F32 in typecheck means the warning always points at a line the user wrote, never at an instantiation inside a library.
3. **Concern:** Users may expect `xs.contains(-0.0)` to warn too. The explain page should name it as out.

**Q7. Fix for ordering**
1. **Vote:** None
2. **Reasoning:** "W0706 is never auto-fixed" is one rule to remember. Writing `0.0` keeps the meaning but hides the bug, which is the reason we gave for `==`. A person picking an LSP code action is the right place for that choice.
3. **Concern:** A large codebase with many ordering hits gets no bulk fix. That is acceptable, because those hits should be rare and each one needs a human to look at it.

**Q8. Diagnostic details package**
1. **Vote:** Yes
2. **Reasoning:** Each part cuts a follow-up question. (a) The span shows which `-0.0` it means. (b) The help is copy-paste safe. (c) The note gives the "I meant zero" user a clean way out. (d) The explain page uses only literals that compile.
3. **Concern:** The bind-first help in (b) is longer. Keep it to one line, `let v = <call>` then the test, so it stays skimmable.

##### PLT

PLT seat, Phase C ballot

**Q1 Ordering operators**
1. **Vote:** In.
2. **Reasoning:** The warning rests on one fact: in a Float comparison, putting `0.0` in place of a written `-0.0` never changes the result. That fact holds for `Ord` exactly as it holds for `Eq`. A rule that covers equality but leaves out ordering draws its line by how often a form appears, not by what the code means. `x <= -0.0` and `x > -0.0` are real sign-test traps.
3. **Concern:** Users who write `x < -0.0` on purpose may see this as noise and switch the whole code off with `W0706 = "off"`.

**Q2 assert_eq / assert_ne**
1. **Vote:** In.
2. **Reasoning:** These are the `Eq` relation at a resolved Float/F32 type, so they fall under the same rule. A passing `assert_eq(f(x), -0.0)` proves nothing, which is the worst form of the trap.
3. **Concern:** None from my seat, as long as the rule fires only when `T` resolves to a concrete Float/F32.

**Q3 Both operands literal**
1. **Vote:** Fires.
2. **Reasoning:** One operand rule with no case split composes better than an exemption that needs its own operand rule. The rewrite with a `let` matches the rule as written: the spec example becomes a true statement about values, and it does not test whether the lint fires.
3. **Concern:** Someone may copy the `let nz = -0.0` rewrite as a general way to dodge the lint; the explain text should say it is for law statements only.

**Q4 const holding -0.0**
1. **Vote:** Out.
2. **Reasoning:** A lint that follows names is a different kind of rule from one that reads only what is written. It would split W0706 from W0704 inside one band, and it leaves loose edges: const chains, and `-0.0` versus `0.0 - 0.0` in an initializer. Keep one rule, "as written", for every literal lint.
3. **Concern:** `const NEG_ZERO = -0.0` then `x == NEG_ZERO` stays silent; a model that names its constants is exposed.

**Q5 Match patterns**
1. **Vote:** Sentence (the binding wording: "that change must bring it under W0706 or make it an error").
2. **Reasoning:** A trigger rule written over syntax that does not exist cannot be checked or tested. A binding sentence makes sure the grammar ticket, when it comes, cannot quietly drop the case. A note on the friction ticket alone is lost once that ticket closes.
3. **Concern:** The sentence may be read as a promise to add negative-literal patterns, which it is not.

**Q6 Scope by resolved relation**
1. **Vote:** Yes.
2. **Reasoning:** `==` desugars to `Eq.eq` and `<` desugars to `Ord.cmp`. A lint that catches the operator but not the method it desugars to is defined over spelling, not meaning. Type information is needed anyway for F32 and `assert_eq[T]`. Fixing the check to concrete Float/F32 in typecheck means mono never gives diagnostics.
3. **Concern:** The spec text must say "resolves to the Float/F32 impl", so that a user type whose `eq` takes a Float argument does not fire.

**Q7 Fix for ordering forms**
1. **Vote:** Ordering-only fix.
2. **Reasoning:** For `<`, `<=`, `>`, `>=` and `cmp`, replacing `-0.0` with `0.0` provably keeps the meaning, and that is the condition for a machine-applicable fix. For `==`/`!=` the user's intent is unknown, so there is no fix there, and the split follows from that difference.
3. **Concern:** `blink fix` then silently "fixes" `x <= -0.0` into `x <= 0.0` and hides a real sign-test bug; the label must still name `is_sign_negative()`.

**Q8 Diagnostic details package**
1. **Vote:** Yes.
2. **Reasoning:** (b) is the part that matters to my seat. Repeating a call in the help would change how many times its effects run. Binding the value first keeps the suggested code correct whatever effects the call has. (a), (c) and (d) are consistent with the rule.
3. **Concern:** "Simple path" needs an exact definition (a name, or field access on names, with no calls and no indexing), or tools will disagree on it.

##### DevOps

DevOps/Tooling — Phase C ballot

###### Q1: Ordering operators
**Vote:** In.
**Reasoning:** `x > -0.0` gives `false` for `0.0`, so ordering has the same trap, not only odd code. Each hit is code where you can delete the `-` and get the same result, so the warning has no false positives. One rule ("any comparison against a written `-0.0`") is easier to document, test and explain than a list of operators. The separate label for ordering keeps the message true.
**Concern:** Users who write `x < -0.0` on purpose (rare) may turn W0706 off for the whole project instead of deleting one `-`, and then lose the `==` check too.

###### Q2: `assert_eq` / `assert_ne`
**Vote:** In.
**Reasoning:** `assert_eq(f(), -0.0)` is a green test that tests nothing. That is the worst place for this bug, because the result looks like proof that the code works. The help must not repeat the call (see Q8b).
**Concern:** None, provided the help binds a call operand to a `let` before it uses it twice.

###### Q3: Both operands literal
**Vote:** Exempt.
**Reasoning:** With both operands literal, the result is a constant that states the language rule; it does not test a value. Without the exemption, the spec's own examples warn. Either we put `@allow` on them, which teaches suppression as normal, or we rewrite them into the less clear `let nz` form. PLT's exact operand form keeps the exemption to one check.
**Concern:** A future change to the predicate (for example, const-following) could widen the exemption by accident, so the exemption text must name the literal form exactly.

###### Q4: `const` holding a written negative zero
**Vote:** Out.
**Reasoning:** W0704 parity gives users and models one rule: "the literal, as written". `const NEG_ZERO = -0.0` is a correct value for arithmetic. A user who names it has met the concept. We can widen the rule later, but we cannot narrow it later without breaking users who set `W0706 = "error"`.
**Concern:** `x == NEG_ZERO` stays a silent bug; the explain page should name this miss in one line.

###### Q5: Match patterns
**Vote:** Sentence.
**Reasoning:** A note on the friction ticket is lost once that ticket closes. A sentence in the section binds the ticket that adds the grammar. Keeping it out of the catalog row and out of the code examples means no one copies `-0.0 =>` as valid syntax.
**Concern:** The sentence may be read as saying that the pattern parses today, so it must say "a future pattern form".

###### Q6: Scope by resolved relation
**Vote:** Yes.
**Reasoning:** If `x.eq(-0.0)` does not warn, the method spelling slips past the warning, and models do use method spellings. Typecheck-only on the concrete relation means no warning per instantiation and no span inside a generic body that the caller cannot fix. A language server that shows warnings the user cannot act on gets its warnings ignored.
**Concern:** The implementation must find the resolved relation through operator desugaring and method calls by the same path, or the two spellings will drift apart in what they report.

###### Q7: Fix for the ordering forms
**Vote:** None.
**Reasoning:** `blink fix` runs unattended. A fix that writes `0.0` turns a possible bug (`x > -0.0` meant "zero or positive") into clean code that no longer warns, and nobody reviews it. A rewrite that keeps the meaning is not the same as a rewrite that keeps the intent. The language server code action gives the same edit with a person in the loop.
**Concern:** People who use `blink fix` to clear warnings will have to clear these by hand, and some will turn the warning off instead.

###### Q8: Diagnostic details package
**Vote:** Yes.
**Reasoning:** (a) A narrow span gives the code action an exact edit range, and it keeps two hits in one condition apart. (b) Help that repeats a call runs the call twice, so the help itself would put a bug in the user's code. (c) The note covers the third intent, "I meant zero". (d) The explain page avoids a literal above Int max, as the Float Bits ruling asks.
**Concern:** The simple-path test for (b) needs an exact definition (names and field paths only, no index or call), or implementations will choose different cases.

##### AI/ML

AI/ML seat, Phase C ballot

###### Q1 Ordering operators
**Vote:** In.
**Reasoning:** "Any Float comparison with a written `-0.0`" is one rule that a model can learn from one spec sentence. A list of operators adds a decision point, plus a second one for `cmp`. `x <= -0.0` and `x > -0.0` give the wrong answer for `0.0` when the user meant a sign test. ESLint `no-compare-neg-zero` uses the same set, so models have seen this shape before.
**Concern:** If Out wins, `x <= -0.0` stays a silent sign-test bug, and the rule text has to explain why `<` is treated differently from `==`.

###### Q2 assert_eq / assert_ne
**Vote:** In.
**Reasoning:** Models write their own tests. `assert_eq(f(x), -0.0)` passes for `0.0`, so the model ends up trusting a test that cannot fail. Here the warning does the most good.
**Concern:** The check needs `T` resolved to Float or F32, so it must run after typecheck has inferred the assert's type argument, not on syntax.

###### Q3 Both operands literal
**Vote:** Exempt.
**Reasoning:** A literal-vs-literal comparison is a constant, never a hidden sign test. The spec's own law examples are training text. If they need a rewrite or `@allow`, models learn that the warning is normal noise. PLT's exact form keeps the carve-out to one clause.
**Concern:** If Fires wins, the rewritten spec example (`let nz = -0.0`) teaches models to hide the literal in a `let` to clear the warning.

###### Q4 const
**Vote:** Out.
**Reasoning:** Matching W0704 exactly means one literal-lint rule across the Linting band. I have no evidence that models write `x == NEG_ZERO`; the reflex form is the inline literal.
**Concern:** A codebase that names `NEG_ZERO` and compares with it stays silent. The explain page should name this case.

###### Q5 Match patterns
**Vote:** Sentence.
**Reasoning:** A forward sentence in the section text binds the future grammar change, and the spec is where that change's author will look. Without a code example, no model copies `-0.0 =>` as valid syntax today.
**Concern:** The sentence can still read as a hint that `-0.0 =>` parses. The wording should say plainly that no pattern form can write it today.

###### Q6 Resolved relation
**Vote:** Yes.
**Reasoning:** A model that is told to "use the method" writes `x.eq(-0.0)`. If the spelling decides whether the warning fires, that is a decision point the model cannot predict from the trap. Concrete Float/F32 only also means the warning always points at code the user wrote.
**Concern:** The implementation must not drop `.eq`/`.ne` in the cases where they resolve through the `Eq` trait instead of a built-in fast path.

###### Q7 Fix for ordering forms
**Vote:** None.
**Reasoning:** I conceded in round 1. Replacing `-0.0` with `0.0` keeps the meaning, and so it also keeps a sign-test bug, now hidden. An agent that runs `blink fix` would lose the warning and keep the bug. Code actions that a person picks are enough.
**Concern:** With no automatic fix, an agent loop may reach for `@allow` instead. The help order (sign test first, then the "write 0.0" note) needs to steer it.

###### Q8 Diagnostic details package
**Vote:** Yes.
**Reasoning:** All four parts serve self-correction in one step. (a) A span on the operand points at the token to change. (b) "Bind first, never repeat a call" stops the help from teaching a double evaluation that a model would copy word for word. (c) The note gives the zero-intent route that clears the warning. (d) Avoids a literal that does not compile today.
**Concern:** Part (b)'s "bind first" text must be valid Blink when copied as is, so the implementation needs a golden test.

##### Minimalism

Minimalism seat, Phase C ballot

**Q1. Ordering operators**
**Vote:** In.
**Reasoning:** One rule, "the `-` cannot change the result", is smaller than a list of operators where each cut needs its own reason. Every hit is a bug or a dead `-`, so it gives no false positives. Deciding the full scope now also avoids widening later, which would break `W0706 = "error"` builds.
**Concern:** The ordering label text drifts from the equality label text, and two message templates for one code become three.

**Q2. `assert_eq` / `assert_ne`**
**Vote:** In.
**Reasoning:** A test that cannot fail is the worst form of the trap. The check already resolves operand types for F32, so `T = Float` adds no new mechanism.
**Concern:** None worth a sentence, given Q8(b) keeps the help from repeating a call.

**Q3. Both operands literal**
**Vote:** Fires.
**Reasoning:** The exemption adds a second predicate ("the other operand is also a float literal") with its own edge cases. Sys's rewrite of the spec example (`let nz = -0.0` then `assert(nz == 0.0)`) removes the reason for the exemption without `@allow`. That answers the DevOps/AI/ML/Web objection that the spec would teach suppression. It also reads better as an example: it states the law on a value. A beginner who types `io.println(-0.0 == 0.0)` gets one warning that teaches the rule, and that is not a harm.
**Concern:** If "Exempt" wins, someone has to keep its predicate exactly in line with N, and it will drift.

**Q4. `const` initializer**
**Vote:** Out.
**Reasoning:** W0704 parity gives one meaning of "literal as written" across the band. Following a const brings name resolution into a lint and leaves chain and folding edges (`const A = NEG_ZERO`, `0.0 - 0.0`). No seat has evidence that the named form is written by reflex.
**Concern:** None. Out is the safe default, and widening stays possible if evidence appears.

**Q5. Match patterns**
**Vote:** None.
**Reasoning:** Spec text about a pattern form that does not exist cannot be tested, and it risks being read as approval. Under Q6, a future Float literal pattern that matches by `Eq.eq` is a resolved relation, so W0706 covers it with no extra text. The friction ticket for the grammar gap is where the person adding the grammar will look. Put the forward note there.
**Concern:** If "Sentence" wins, keep it in the section prose and out of the ERROR_CATALOG row, as the option says, with no `-0.0 =>` example.

**Q6. Scope by resolved relation**
**Vote:** Yes.
**Reasoning:** Defining the rule by resolved relation is shorter than listing spellings. `assert_eq` already requires "concrete Float/F32 after typecheck", so the method forms come at no cost. "No mono diagnostics" is a rule we want anyway.
**Concern:** The test matrix grows (`eq`, `ne`, `cmp` rows) for spellings almost no one writes. That is acceptable but not free.

**Q7. Fix for ordering forms**
**Vote:** None.
**Reasoning:** "W0706 is never auto-fixed" is one rule. A per-operator fix rule is a second one. DevOps is right that an unattended `blink fix` would turn a possible bug into silent clean code. AI/ML, who proposed the fix, withdrew it.
**Concern:** Users who meant zero must edit by hand. The Q8(c) note makes that edit obvious.

**Q8. Diagnostic details package**
**Vote:** Yes.
**Reasoning:** Each part is small and earns its place: (a) a narrow span keeps two hits in one condition apart; (b) never repeating a call is a correctness rule for the help text, not decoration; (c) the note gives a way to clear the warning when the user meant zero; (d) avoids a literal above Int max, which would not compile today.
**Concern:** (c) adds a third trailing line. If message length matters later, drop that line first.

#### Phase D — Round 2 (Q3)

Q3 was 4-2, so the panel re-debated it alone. In the debate, PLT proposed the marked example form, and the re-vote added Q3b on the example form.

##### Debate

##### Systems

Systems seat, Phase D, Q3: hold Fires, and change how the spec example is rewritten

AI/ML's concern is correct, and it applies to my own rewrite. If the spec shows `let nz = -0.0` and then `nz == 0.0`, a model learns "put the literal in a `let` to clear W0706". The next thing it writes is `let nz = -0.0` then `if x == nz`, which is the same trap with no warning. So I withdraw the `let` form as the fix.

That is a reason to change the example, not to add the exemption. Use PLT's other option: keep the literal and mark the line.

```blink
assert(-0.0 == 0.0)            // warning[NegativeZeroComparison]: true for 0.0 and -0.0
assert((-0.0).ieee_eq(0.0))    // warning[NegativeZeroComparison]
assert((-0.0).is_sign_negative())
```

This states the law and shows the warning in the same place. It teaches no dodge and no `@allow`. A warning does not stop a build, so the example still runs. To DevOps: this does not teach suppression as normal, because nothing is suppressed. To AI/ML: the training text pairs the trap with its diagnostic, which is the lesson we want a model to learn.

The checker argument still holds. With Exempt, the checker looks at the other operand as well, and that second check has its own edge cases (`(0.0)`, `-(1.0)`, and const-following later, as DevOps notes). With Fires, there is one predicate on one operand and fewer test rows.

Web's sweep concern stays: every spec, llms and stdlib example of `-0.0 == 0.0` gets the same comment, or moves to `is_sign_negative`.

Vote intent: Fires.

##### Web/Scripting

###### Web/Scripting seat — Phase D, Q3 only

**Hold: Fires.**

AI/ML's concern is the strongest point on the Exempt side, and I take it seriously. A bare `let nz = -0.0` then `assert(nz == 0.0)` does look like "hide the literal in a `let` to clear the warning". But the answer is to fix the example, not to add a carve-out. Write the spec example so the `let` has a visible job, and pair it with the sign test:

```blink
let nz = -0.0
assert(nz == 0.0)              // total order: the zeros are equal
assert(nz.ieee_eq(0.0))        // IEEE agrees
assert(nz.is_sign_negative())  // only the sign bit tells them apart
```

Read this way, the example teaches the correct tool on the page where people first meet the topic. It is better training text than `assert(-0.0 == 0.0)`, which states the law and stops just before the useful part.

To DevOps on "less clear": three lines that end in the answer are clearer to a JS or Python dev than one line that reads like a bug.

The Exempt side's predicate cost is still real. "Is the other side a literal?" brings in `(0.0)`, `-(1.0)` and, later, const-following. Sys and Min both expect it to drift.

I also back PLT's request: the explain text should say that a `let` does not fix the code, and `is_sign_negative()` does.

##### PLT

PLT seat, Phase D on Q3

**Hold: Fires.**

DevOps and AI/ML say a comparison of two literals is a constant and so never a hidden sign test. That is true, but it does not justify an exemption. The warning's claim, "the `-` has no effect", is exactly as true here. A user who types `-0.0 == 0.0` is checking what they believe the rule is, and the warning gives them the answer at compile time. An exemption is also a second predicate over the other operand, and that predicate drifts away from N: what about `(0.0)`, a const, or `-0.0 == -0.0`? DevOps's own concern says this.

I agree with AI/ML's concern about the `let nz` rewrite. It was also my Phase C concern: the rewrite teaches readers to hide the literal behind a `let`. There is a better answer that needs neither `@allow` nor a `let`. Keep the two spec lines as they are and mark them `// warning[NegativeZeroComparison]`. The spec already shows code that triggers a warning this way: W0704's own example is `let a = 10 / 0  // warning[DivisionByLiteralZero]`. The marker states the law, shows the lint, and teaches neither suppression nor a dodge. For training text, a marked warning is the most honest signal: "this compiles, and it warns, because the `-` does nothing".

So my position is: Fires, with the spec examples marked rather than rewritten. I take back my support for Sys's `let` rewrite as the spec form. Web's concern still stands: sweep the llms docs and the stdlib for `-0.0 ==`, and mark or rewrite each hit.

##### DevOps

DevOps/Tooling — Phase D, Q3

**I concede to Fires.** I voted Exempt only because of how the spec example reads. Sys's rewrite fixes that without `@allow`, so I have no reason left. Two tooling points go the same way:
- One operand predicate means the checker has one code path and one set of tests. An exemption needs its own predicate (`(0.0)`? `-(1.0)`?), and the spec and the checker would come to disagree on those spellings.
- A beginner who types `io.println(-0.0 == 0.0)` gets a warning that teaches the exact rule they are testing. That warning is correct, not noise.

AI/ML's concern is real: `let nz = -0.0` can be read as a way to hide the literal and clear the warning. Two conditions handle it, and I ask the moderator to record both with the result:
1. **Sweep.** Before W0706 ships, the implementation ticket sweeps sections/, llms docs, lib/std and tests/ for every comparison that has a written `-0.0` operand, not only lines 3511–3512 (Web's concern). The gate is that `task ci` gives zero W0706 hits in docs and stdlib examples. A docs page that warns is the worst first impression this lint can make.
2. **Explain text.** `blink explain W0706` says in one line that a `let` or `const` holding `-0.0` is not checked. It says the `let` form is for statements of the language rule only, and that it does not make a sign test correct (PLT's point). Saying this openly stops the `let` from reading as a fix.

Vote intent for the re-vote: Fires.

##### AI/ML

AI/ML seat, Phase D on Q3

**I concede to Fires, with two conditions.**

I voted Exempt to keep the spec's law examples from teaching `@allow` as normal. Sys's `let nz = -0.0` rewrite takes away that reason without any `@allow`. Web and Min make the point that counts most for my seat: a model that types `-0.0 == 0.0` to check its own belief gets a warning that states the rule. The diagnostic then does the teaching, and that is better than a silent constant. One operand predicate also means one fewer decision point, both for a model predicting the lint and for the checker's tests (Sys).

My concern from Phase C stays: models copy spec examples word for word, so `let nz = -0.0` can turn into a general way to dodge the lint. Conditions:

1. **Explain text (PLT's concern, made binding).** `blink explain W0706` says plainly that moving `-0.0` into a `let` hides the warning and keeps the bug, and that the sign test is `is_sign_negative()`. The rewritten spec example carries a one-line comment that it states the law and is not a sign test.
2. **Sweep (Web's concern).** The change that adds W0706 sweeps sections/, llms docs, lib/std and tests/ for every written `-0.0` operand of a covered comparison, not only lines 3511–3512. The ticket's done condition includes a corpus run with zero unplanned W0706 hits.

##### Minimalism

Minimalism seat, Phase D on Q3

**Hold: Fires.**

AI/ML's concern is the strongest point against my vote. The `let nz = -0.0` rewrite could teach a model to hide the literal in a `let` to clear the warning. I accept that risk is real. The answer is a different rewrite, not an exemption.

The spec already has a precedent. The W0704 example in sections/03_types.md writes `let a = 10 / 0          // warning[DivisionByLiteralZero]` and leaves the warning in the example on purpose. Do the same here:

```blink
assert(-0.0 == 0.0)             // warning[NegativeZeroComparison]: the zeros are equal
assert((-0.0).ieee_eq(0.0))     // warning[NegativeZeroComparison]
assert((-0.0).is_sign_negative()) // the sign of zero
```

This one example states the law, shows that the lint fires, and puts the right tool on the next line. It needs no `@allow` and no `let`, so it gives no way around the lint for a model to copy. This answers DevOps too: the example is no less clear, and it teaches more.

Beyond that, "the result is a constant" is true of literal-vs-literal code, but only language tests and docs write it. A carve-out for docs is a rule that every user and every checker must carry for a case almost none of them write. PLT and Sys are right that the exemption needs its own operand test, and DevOps's own concern shows that test can widen by accident.

I ask the moderator to note this rewrite as an option for the spec edit, whichever way Q3 goes on the re-vote. Web's sweep concern still applies: llms docs and stdlib examples need the same treatment.

##### Re-vote

Q3: Fires 6-0. Q3b: Marked 6-0.

##### Systems

Systems seat, Phase D re-vote

**Q3. Both operands literal**
- **Vote:** Fires
- **Reasoning:** The rule tests one operand with one predicate, so the checker has one code path and one set of test rows. An exemption needs a second predicate over the other operand (`(0.0)`, `-(1.0)`, later a const), and that one drifts away from N. All six seats now give the same reason: the warning's claim, "the `-` has no effect", is also true for two literals.
- **Concern:** A user's doc test or REPL check that states the law will warn, and someone will ask for the exemption again. The explain text should answer that up front.

**Q3b. Form of the spec example**
- **Vote:** Marked
- **Reasoning:** It follows the W0704 precedent at sections/03_types.md:3743, where the example keeps the code that warns and marks it in a comment. It teaches no dodge: Web's `let nz = -0.0` form, even with the sign test at the end, shows a model that a `let` clears W0706, and `let nz = -0.0` then `x == nz` is the same trap with no warning. The marked lines state the law, show the diagnostic, and put `is_sign_negative()` on the next line.
- **Concern:** DevOps's sweep gate, "zero W0706 hits in docs and stdlib examples", conflicts with Marked. The gate must count only hits on lines without a `// warning[NegativeZeroComparison]` marker, or the implementation ticket will strip the markers to pass.

##### Web/Scripting

###### Web/Scripting seat — Phase D re-vote

**Q3. Both operands literal**
- **Vote:** Fires
- **Reasoning:** With every seat now on Fires, there is one predicate on one operand and no carve-out to explain. A newcomer who types `-0.0 == 0.0` to check the rule gets a warning that states the rule. That is the fastest way to learn it.
- **Concern:** The sweep of sections/, llms docs, lib/std and tests/ must be part of the implementation ticket's done condition. Otherwise the first doc page a user opens warns.

**Q3b. Form of the spec example**
- **Vote:** Marked
- **Reasoning:** I drop my `let` form. Marked teaches the same law and puts the sign test on the next line, and it shows no way to hide the literal. W0704 already marks its example this way at 03_types.md:3743, so readers see one pattern across the lints. A JS or Python dev reads `// warning[NegativeZeroComparison]` next to the line and gets it in seconds.
- **Concern:** A reader may not know that a warning does not stop the build. Keep the first marker's short text ("the zeros are equal") so the comment explains itself.

##### PLT

PLT seat, Phase D re-vote

**Q3 Both operands literal**
- **Vote:** Fires.
- **Reasoning:** The warning's claim, "the `-` has no effect", is true here as in every other covered place, so an exemption would carve out a case where the claim still holds. Keeping one operand rule (N) and no second rule on the other operand means the checker and the spec cannot disagree on edge spellings.
- **Concern:** A literal-vs-literal line in docs or stdlib that nobody marked or rewrote will warn when someone first builds it.

**Q3b Form of the spec example**
- **Vote:** Marked.
- **Reasoning:** The spec already marks code that gives a warning this way (W0704 at 03_types.md:3743). A marked line states the law and also shows that the lint fires. The `let` form shows a way around the lint as if it were normal style. A reader or model learns from the marker that this code compiles and warns because the `-` does nothing, which is the exact fact the section must teach.
- **Concern:** A reader who copies a marked line into real code gets a warning, but the marker comment means they were told so in advance.

##### DevOps

DevOps/Tooling — Phase D re-vote

###### Q3: Both operands literal
**Vote:** Fires.
**Reasoning:** With one rule on one operand, the checker has one code path and one set of test rows. The exemption needs a second test on the other operand, and that test would drift. A warning on `-0.0 == 0.0` is true, and it teaches the rule at the point where the user tests it.
**Concern:** The examples in the docs and the stdlib must be swept before W0706 ships, or the docs will show warnings that nobody explains.

###### Q3b: Form of the spec example
**Vote:** Marked.
**Reasoning:** It copies the W0704 example at 03_types.md:3743, so readers see one convention for code that warns. It teaches no suppression and no way around the warning, which fixes AI/ML's concern and mine. The `let nz` form teaches the escape that leaves `if x == nz` silent. For tooling, a marker comment can be checked by a script: a doc-example test can require that each W0706 hit is on a line that carries `// warning[NegativeZeroComparison]`. I change my Phase D sweep condition from "zero hits" to "zero unmarked hits".
**Concern:** If no doc-example check compares the marker comments with what the compiler emits, a marker can stay after the code changes, or a hit can go unmarked.

##### AI/ML

AI/ML seat, Phase D re-vote

###### Q3 Both operands literal
**Vote:** Fires.
**Reasoning:** I conceded in my Phase D reply. A model that types `-0.0 == 0.0` to test what it believes gets the rule back from the compiler in one step. One operand predicate with no carve-out is one fewer thing for a model to predict.
**Concern:** The sweep of sections/, llms docs, lib/std and tests/ must happen in the same change, or the docs warn when someone copies them.

###### Q3b Form of the spec example
**Vote:** Marked.
**Reasoning:** Marked removes my main concern: a `let nz = -0.0` example in the core spec is a pattern a model copies word for word to clear the warning. Marking the warning inline follows the W0704 example at sections/03_types.md:3743, so a model sees one way of showing a warning across the spec. It also shows in the spec text where the warning fires, which is training data that teaches the lint itself.
**Concern:** A model may copy the marked lines into real code. The comment must read as the compiler's output (`warning[NegativeZeroComparison]`), not as a suggestion, and `blink explain W0706` must still name `is_sign_negative()` as the fix.

##### Minimalism

Minimalism seat, Phase D re-vote

**Q3. Both operands literal**
**Vote:** Fires.
**Reasoning:** With one predicate on one operand, there is nothing to drift. The exemption's second test (`(0.0)`, `-(1.0)`, a later const-following change) is spec text and checker code that serves only docs and language tests. DevOps and AI/ML have now dropped their reason for it, so the rule can stay as written.
**Concern:** The sweep of sections/, llms docs, lib/std and tests/ is the real cost of this vote, and the implementation ticket must make it a done condition.

**Q3b. Form of the spec example**
**Vote:** Marked.
**Reasoning:** The marked form follows the W0704 precedent at sections/03_types.md:3743. It states the law, shows the lint, and adds no `let` and no `@allow`. Web's version ends well with `is_sign_negative()`, but its `let nz = -0.0` is still the dodge that AI/ML named: the trap with the warning hidden. A model copies the first line as readily as the last. The marked form also puts `is_sign_negative()` on its third line, so it keeps Web's best part.
**Concern:** A reader may take a marked warning line in the spec as approved style, so the comment text should say why it warns (`the zeros are equal`), not only the code name.

### Final Spec

```blink
fn classify(x: Float) -> Str {
    if x == -0.0 { return "negative zero" }   // warning[NegativeZeroComparison]
    if x <= -0.0 { return "not positive" }    // warning[NegativeZeroComparison]
    "positive"
}

fn sign_label(x: Float) -> Str {
    if x == 0.0 && x.is_sign_negative() { return "negative zero" }  // no warning
    "other"
}
```

- W0706 `NegativeZeroComparison`, Linting, §3.6 *Negative Zero Comparison*.
- Operand: one unary `-` over a zero float literal, as written, parentheses allowed.
- Relations: the resolved `Float`/`F32` impl of `Eq`, `Ord`, `ieee_eq`, and `assert_eq`/`assert_ne`; either operand, both literal included.
- Not covered: `const`/`let` references, computed values, `min`/`max`, `contains`; generic bodies.
- Fires in dead branches, test blocks and `assert_panics` bodies.
- No machine-applicable fix; help names `is_sign_negative()`; suppression by `@allow` or `[lints]`.
