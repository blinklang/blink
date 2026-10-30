[< All Decisions](../DECISIONS.md)

# Range Operator Precedence — Design Rationale

The spec listed the infix range (`0..100`, `1..=100`) in §2.16 and had no row for `..` or `..=` in the §2.19 precedence table. So the spec did not say which expressions may start or end a range. The parser built a range only after an Int literal and read the end as a primary. As a result `rand.int(lo..hi)`, `for u in lo..hi`, `for i in xs.len()..4` and `let r = (a)..3` did not parse, `0..xs.len()` parsed as `(0..xs).len()`, `0..n + 1` parsed as `(0..n) + 1`, and `0..1..2` was accepted with no error. `blink fmt` dropped the parentheses of a binary range end, which changed the meaning.

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in independent-proposal → debate → vote rounds. One question (Q3, the formatter output) went to a fourth, focused round.

Constraints given to the panel (decided earlier, not reopened):

- `..` excludes the end, `..=` includes it, `Range[T: Ord]`, lazy (5-0).
- Comparisons do not chain (4-1). The integer operator groups are a partial order, and a mix of groups is `MixedOperatorPrecedence` (E1127) (see [shift-bitwise-precedence.md](shift-bitwise-precedence.md)).
- Range pattern bounds are literals or const items. Range patterns do not change.
- `rand.int(r: Range[Int])` takes a range (see [random-stdlib-module.md](random-stdlib-module.md)).
- `..` keeps its spread and rest meanings in §2.16.
- House rule: spec text in sections/ states language rules, not implementation.

Facts surfaced to the panel by the moderator:

- **F1:** `for u in lo..hi {` and `for i in xs.len()..4 {` were `UnexpectedToken` at `..`. `let r = (lo)..3` was `unexpected token ..`. `for i in 0..xs.len() {` was `NotIterable`. `for i in 0..n + 1 {` was a `TypeError`. `let r = 0..1..2` was accepted.
- **F2:** §2.19 had a test for when a mix of operators is a parse error: "A parse error removes each mix where two languages give different values. The comparison edge stays ordered because the other grouping never type-checks". The panel used the same test for the range row.
- **F3:** `blink fmt` rebuilds parentheses from precedence and keeps no record of the parentheses the author wrote. `let d = (b * 2) + 1` prints as `let d = b * 2 + 1`.

#### Phase A — Independent proposals

All six proposals gave `..` and `..=` one new row between comparison and the integer groups, with no associativity. All six let any expression at level 7 or higher start or end a range, so `for i in 0..n + 1` is `0..(n + 1)`. All six made `a..b..c` a parse error `ChainedRange` with no machine fix, and all six kept open-ended forms out. They differed on a bare range next to a comparison, on a missing bound, and on what `blink fmt` prints.

- **Systems:** proposal "Proposal S1 (primary): `..`/`..=` get their own row between comparison and arithmetic". "Operands are full expressions at level 7 and above."
- **Web/Scripting:** proposal "Proposal W1 (recommended): `..`/`..=` get their own level between comparison and arithmetic, with no associativity". "Each bound is any expression at level 7 or above: a name, a call, a field, a parenthesized expression, arithmetic, unary minus, a `?` expression."
- **PLT:** proposal "Proposal P1 (recommended): ranges get their own non-associative level, between comparison and the integer groups". "`int_expr` is any expression at level 7 or above: an integer-group expression, unary, postfix `?`, member access, call, primary."
- **DevOps/Tooling:** proposal "Proposal D1 (recommended): one new row, non-associative, ranges never bare operands of comparison". "New level between comparison (6) and the integer operator groups (7):"
- **AI/ML:** proposal "Proposal A1 (recommended): range row between comparison and integer operators; no chains; no bare range next to a comparison". "Any expression at level 7 or higher can start or end a range: a literal, a name, a call or member chain, a parenthesized expression, unary `-`/`!`/`~`, postfix `?`, and any level-7 expression (arithmetic, shift, bitwise)."
- **Minimalism:** proposal "Proposal M1: one non-associative row between comparison and level 7 (recommended)". "The minimal fix: give the existing operator one row in §2.19 and add no new forms."

#### Phase B — Debate highlights

The moderator merged the proposals into points: the comparison edge (1), a missing bound (2), the formatter output (3), and, from the debate, evaluation order, foreign spellings, the end of a type and empty ranges. Two rounds ran. Round 2 added the §2.19 test (F2). Seats moved on point 1:

- **Systems (r1):** "Point 1: I move from 1A to 1B (reuse `MixedOperatorPrecedence`, E1127)."
- **AI/ML (r1):** "Point 1: I move from 1B to 1A (`RangeInComparison`). I reject 1C."
- **PLT (r1):** "Point 1: I move from 1B to 1C."
- **Minimalism (r1):** "Point 1: I stay on 1C. My second choice is 1B. I vote against 1A."
- **Systems (r2):** "Point 1: I move from 1B to 1C, with plt's fmt mirror. 1B is my second choice."
- **AI/ML (r2):** "Point 1: I move from 1A to 1C, with plt's fmt mirror. 1A is my second choice."
- **DevOps/Tooling (r2):** "The :2003 fact changes my view."
- **PLT (r2):** "Only one grouping of `r == 0..3` type-checks, so no reader gets a different value without an error."
- **Minimalism (r2):** "That Rust grouping cannot compile in Blink, because Bool is not Ord."
- **Web/Scripting (r2):** "A parse error at `..` names the problem at the token they typed."
- **Web/Scripting (r2):** "If the panel picks 1C, the help line `x >= 0 && x < 3` must be required, not optional."

On point 3, round 2 moved web from keeping the author's parentheses to precedence-derived output, and min kept a variation: "Variation, by the same rule as :2001: fmt prints parentheses around a bitwise or shift operand, so `0..n | 1` prints as `0..(n | 1)`." (Minimalism, r2). plt: "Precedence-derived output: `0..(n + 1)` prints as `0..n + 1`, `(lo)..3` prints as `lo..3`, and parens that change the parse stay." (PLT, r2). aiml held its own option: "Under 3C, fmt turns a clear `0..(n + 1)` into the form that looks wrong. That is the one output I want fmt never to print." (AI/ML, r2).

Three more points came up in the debate and were not contested: sys on evaluation order and on `..=` at the largest value of a type, aiml on the help for `0..<n` and `0...n`, plt on empty ranges. They went to the ballot as Q4 to Q7.

#### Phase C — Vote

Each panelist voted alone. The ballot had seven questions. The vote and the reasoning below are the panelists' own words. A sentence that names a ticket id is left out and marked `[...]`.

- **Q1: a bare range as an operand of `==` `!=` `<` `>` `<=` `>=`.** Options: 1A new parse error `RangeInComparison`; 1B widen `MixedOperatorPrecedence`; 1C no parse error, the row groups it, the `TypeError` carries a help line, fmt prints parentheses.
  - **Systems:** 1C. "§2.19 already decides when a mix of operators needs a parse error: only when two groupings each type-check and give different values. Here `(x == 0)..3` never type-checks, so only one reading ever compiles. A parse rule for this case does not protect any program. fmt prints `r == (0..3)`, which shows the reader the grouping at no cost."
  - **Web/Scripting:** 1A. "A JS or Python dev who writes `x == 0..3` means membership. The error should name that shape at the `..` token they typed, not report a type mismatch about `Range[Int]`. A searchable, specific code with the help `x >= 0 && x < 3` answers the question where it comes up. 1A also stops `r == 0..3` from compiling silently, while under 1C only fmt shows the grouping."
  - **PLT:** 1C. "§2.19:2003 states the rule: a precedence edge is a parse error only where two languages give different values with no error. For a range in a comparison, the other grouping (Rust's `(x == 0)..3`) never type-checks, so the edge stays ordered, which is the case `flags & 0x0F == 0` is already in. Mirroring :2001 in fmt puts the grouping on screen, so 1C needs no new exception and no new code."
  - **DevOps/Tooling:** 1C. "§2.19 already keeps an edge ordered when the other grouping never type-checks, and `(x == 0)..3` needs `Bool: Ord`, which does not exist. One rule for every edge is one `blink explain` story. The help line on the TypeError and the fmt parens (`r == (0..3)`) were my two conditions, and the ballot carries both."
  - **AI/ML:** 1C. "The Rust grouping `(x == 0)..3` is `Bool..Int` and never type-checks, so no model gets a silent wrong value. This is the same argument that keeps the comparison edge ordered at :2003. One precedence rule over the whole table is easier for a model to learn than a special-case parse error. fmt printing `r == (0..3)` keeps the grouping explicit in the corpus."
  - **Minimalism:** 1C. "§2.19 gives a parse error only to a mix where two groupings both compile with different values. Here the other grouping, `(x == 0)..3`, never compiles, because Bool is not Ord. So `r == 0..3` with `r: Range[Int]` compiles to the meaning the reader wants, and fmt makes the grouping visible as `r == (0..3)`. A parse error adds a rule and a code but stops no wrong program."
  - Result: **Q1 1C 5-1** (web voted 1A).

- **Q2: a range with a missing bound.** Options: 2A existing `UnexpectedToken` with a range help line; 2B a new code `MissingRangeBound`.
  - **Systems:** 2A. "The fix is always "write the missing bound", so no tool needs a separate code to branch on. The message and help must name the range, not only the token."
  - **Web/Scripting:** 2A. "One existing code with a range-specific help line covers every missing-bound case. The slice hint inside `xs[...]` answers the most likely Python question. A new code adds nothing a user can act on."
  - **PLT:** 2A. "It is a parse error with one cause and no machine fix. A help line on `UnexpectedToken` carries all the information, and a new code would add catalog surface without new meaning."
  - **DevOps/Tooling:** 2A. "no machine fix exists for a missing bound, so a new code gives the LSP nothing to act on. A context-specific help line (including the no-slice hint in `xs[...]`) gives the user all the value."
  - **AI/ML:** 2A. "A model repairs from the help text, not the code number, so a new code adds nothing. The slice-syntax line inside `xs[...]` covers the most common open range in training data (`xs[1..]`)."
  - **Minimalism:** 2A. "A missing bound is a token the parser did not expect. A help line on `UnexpectedToken` gives the user all the information a new code would. A new code only adds a catalog row, an explain page and a test."
  - Result: **Q2 2A 6-0.**

- **Q3: what `blink fmt` prints around a range operand.** Options: 3B parentheses around every binary operand; 3C precedence-derived; 3C+ 3C plus parentheses around a bitwise or shift operand.
  - **Systems:** 3C. "fmt builds parens from precedence for each operator and keeps no record of user parens. A different rule for ranges only adds code paths to the formatter and makes fmt's output for ranges differ from all other operators. `0..n | 1` has no other grouping that type-checks, so the :2001 analogy does not apply."
  - **Web/Scripting:** 3C+. "fmt rebuilds parens from precedence for every operator, so ranges must follow the same rule. Otherwise users ask why fmt keeps parens in one place and strips them in another. The bitwise and shift parens reuse a rule fmt already applies at :2001, so readers learn nothing new, and `0..(n | 1)` is clearer to a Kotlin dev."
  - **PLT:** 3C+. "fmt has no grouping node and prints parens from precedence for every operator, so 3C is the only option that is not a range-local exception. The variation holds for the same reason as :2001: Kotlin groups `0..n or 1` as `(0..n) or 1`, and that grouping does not type-check. So the operand is legal bare, and fmt prints parens. This gives one fmt rule: a bitwise or shift operand of a comparison, equality or range operator gets parens. Arithmetic operands get none."
  - **DevOps/Tooling:** 3C. "fmt derives parens from precedence for every operator and keeps no record of user parens; one mechanism is the only one we can keep correct. [...] 3B rewrites the most common loop header in every file; 3C+ adds a rule where no language reads `0..n | 1` as `(0..n) | 1` (Rust and Swift bind `|` tighter)."
  - **AI/ML:** 3B. "With `..` unspaced and `+` spaced, `0..n + 1` looks like `(0..n) + 1`. [...] 3B gives one canonical form that no reader misreads. It is a rule on the tree of the same kind as :2001, so it needs no record of user parens. 3C+ is my second choice: under 3C, fmt rewrites a clear `0..(n + 1)` into the form that looks wrong."
  - **Minimalism:** 3C+. "Precedence-derived output is what fmt does for every operator today, so ranges need no special mechanism. The bitwise/shift parentheses are the existing :2001 rule applied to the new row, not a new rule. 3B is a rule that only ranges would have, and it rewrites the most common loop bound."
  - Result: **Q3 split: 3C+ 3 (web, plt, min), 3C 2 (sys, devops), 3B 1 (aiml).** It went to Phase D.

- **Q4 to Q7, all six voted Agree:** Q4 the bounds evaluate once, start first, when the range value is created; Q5 `0..<n` gets help and a machine fix, `0...n` gets help and no fix; Q6 `lo..=hi` with `hi` at the largest value of its type yields `hi` last and stops; Q7 `a..b` with `a >= b` and `a..=b` with `a > b` are empty.
  - Min on Q4: "This is the general rule for operands (once, left to right), applied to `..`. The spec should state it as that general rule, with the `xs.len()` example, not as a clause only for ranges."

#### Phase D — Re-debate and re-vote (Q3)

Q3 was closer than a plain majority could settle. The moderator gave it one focused debate round and then a silent re-vote. The other results stayed fixed.

Moves in the debate:

- **Systems:** "I move from 3C to 3C+."
- **DevOps/Tooling:** "I move from 3C to 3C+."
- **AI/ML:** "I move from 3B to 3C+."
- **Web/Scripting:** "Position: I move from 3C+ to 3B. 3C+ is my second choice."

Re-vote. Web went back from 3B to 3C+, so the vote was 3C+ 6-0:

  - **Systems:** 3C+. "The rule is one predicate in the existing `needs_parens`: "a bitwise or shift operand of a comparison, equality or range operator gets parens; an arithmetic operand gets none". Ranges join a set that already exists, so the formatter gets no new mechanism and no range-only branch. plt and min are right that :2001 never needed a second grouping that compiles, so my Phase C objection does not hold. 3B adds parens around arithmetic operands, which :2001 says fmt does not do, so fmt would contradict its own rule for one operator."
  - **Web/Scripting:** 3C+. "I go back from 3B to 3C+. sys and devops point out that :2001 says outright "The formatter does not add parentheses around an arithmetic operand", so 3B gives fmt a rule that goes against its own stated rule, but only for ranges. That is a "why does fmt do X here and not there" question, the kind I want to avoid. aiml's fact settles the misread worry for me: rustfmt and the Kotlin and Swift style tools print `0..n + 1` bare, so most devs who come to Blink already read it as `0..(n + 1)`. And `(0..n) + 1` never compiles, so a misread cannot become a wrong program. 3C+ gives one fmt sentence a dev can learn in one read: bitwise and shift operands of a comparison, equality or range operator get parens; arithmetic operands get none."
  - **PLT:** 3C+. "fmt derives parens from the tree, and 3C+ extends the existing :2001 predicate with one operator. The result is one sentence: "a bitwise or shift operand of a comparison, equality or range operator gets parens; an arithmetic operand gets none." 3B would contradict :2001's explicit "does not add parentheses around an arithmetic operand" for one operator only. 3C would make the range row a carve-out from the bitwise rule. `(0..n) + 1` never type-checks, so the bare `0..n + 1` cannot become a silent wrong program."
  - **DevOps/Tooling:** 3C+. "In the formatter this is one predicate in `needs_parens`: a bitwise or shift operand of a comparison, equality or range operator gets parens, an arithmetic operand gets none. It needs no record of user parens and no range-only path, and it keeps fmt consistent with the :2001 text that says fmt adds no parens around an arithmetic operand. web is right that 3B leaves `0..n` and `0..xs.len()` alone, but it still contradicts :2001 for one operator, and `(0..n) + 1` never compiles, so the bare form cannot hide a wrong program."
  - **AI/ML:** 3C+. "web has now taken up my old 3B argument, but the counter I gave in debate still holds. rustfmt and the Kotlin and Swift style tools print `0..n + 1` bare. That bare shape, meaning `0..(n + 1)`, is already common in training data, so models read it correctly. As min and plt note, `(0..n) + 1` never compiles, so a misread cannot turn into a wrong program. 3C+ gives one fmt rule that a model learns in one sentence: "a bitwise or shift operand of a comparison, equality or range operator gets parens; an arithmetic operand gets none". 3B would contradict :2001's "does not add parentheses around an arithmetic operand" for one operator only."
  - **Minimalism:** 3C+. "With 3C+, fmt has one sentence: "a bitwise or shift operand of a comparison, equality or range operator gets parens; an arithmetic operand gets none." The cost is one more operator in the existing `needs_parens` set. It adds no mechanism and no exception for the range row. 3B is the only rule on the ballot that exists for ranges alone, and it contradicts :2001 ("does not add parentheses around an arithmetic operand"). web says 3B "subsumes the bitwise case", but it does that by adding the range exception."

**Result: Q3 3C+ 6-0.** The rule has one sentence: a bitwise or shift operand of a comparison, equality or range operator gets parentheses; an arithmetic operand gets none. Together with Q1, a range that is an operand of a comparison or equality operator gets parentheses too.

#### Dissent

Web voted 1A for Q1: a new parse error for a bare range next to a comparison. Web's reasoning, from the vote: "A JS or Python dev who writes `x == 0..3` means membership. The error should name that shape at the `..` token they typed, not report a type mismatch about `Range[Int]`." The majority applied the §2.19 test (F2): the other grouping `(x == 0)..3` never type-checks, so a parse error protects no program. Web's condition, that the `TypeError` help line be required, is in the spec: the help is keyed on the syntax of the operand, not on the type mismatch.

#### User sign-off

Approved by the owner on 2026-10-30.

### AI-First Review

5/5 pass.

- **Learnability:** pass. One row: `..` binds looser than arithmetic and tighter than comparison. `0..n + 1` is `0..(n + 1)`.
- **Consistency:** pass. The range edges use the test that the integer groups use: a parse error only where two groupings both type-check with different values. The formatter has one rule for comparison, equality and range operators.
- **Generability:** pass. The common forms from other languages (`0..n + 1`, `lo..hi`, `0..xs.len()`) compile. `0..<n` and `0...n` get a help line, and `0..<n` a machine fix.
- **Debuggability:** pass. A missing bound, a chain, a bare range next to a comparison and the foreign spellings each give a specific message with help.
- **Token efficiency:** pass. No new tokens or parentheses are needed in the common forms.

### Final Spec

```blink
for i in 0..n + 1 { }            // 0..(n + 1)
for i in 0..xs.len() { }         // 0..(xs.len())
let a = -2..3                    // (-2)..3
let r = rand.int(lo..hi)         // a bound is any expression
let p = 0..1..2                  // error[ChainedRange]
let q = 0..                      // error[UnexpectedToken]: a range needs an end
let s = 0..<n                    // error[UnexpectedToken]; machine fix: 0..n
let t = 0...n                    // error[UnexpectedToken]; no machine fix
let u = r == 0..3                // r == (0..3); fmt prints the parentheses
let v = x == 0..3                // error[TypeError] with help: x >= 0 && x < 3
```

- A new §2.19 row for `..` and `..=` between comparison and the integer operator groups, with no associativity. Each operand is any expression at the integer-group level or higher.
- `a..b..c` and `a..=b..c` are the parse error `ChainedRange` (E1141), with no machine-applicable fix.
- No open-ended range (`a..`, `..b`, `..`). A prefix `..` stays spread and rest (§2.16). A missing bound is `UnexpectedToken` with a help line; inside `xs[...]` the help says that Blink has no slice syntax.
- `|>`, `??`, `||` and `&&` take a whole range as one operand. `0..n |> sum` is `(0..n) |> sum`, and `opt ?? 0..n` is `opt ?? (0..n)`.
- A bare range next to `==` `!=` `<` `>` `<=` `>=` is no parse error. `x == 0..3` with `x: Int` is a `TypeError` with a required help line. `r == 0..3` with `r: Range[Int]` is `r == (0..3)`.
- `blink fmt` prints parentheses around a bitwise or shift operand of a comparison, equality or range operator, and around a range that is an operand of a comparison or equality operator. It prints no parentheses around an arithmetic operand.
- Each bound evaluates once, start first, when the range value is created (§2.22). This holds for every range value, also one passed to `rand.int`.
- `0..<n` has a help line and a machine fix. `0...n` has a help line and no fix.
- `lo..=hi` with `hi` at the largest value of its type yields `hi` last and stops.
- `a..b` with `a >= b` and `a..=b` with `a > b` are empty. A `for` loop over one runs zero times. `rand.int` still panics on an empty range.
- Range patterns do not change.
- Spec: §2.10 *Ranges*, §2.16, §2.19 *Range Operands*, §2.22, §3.2, §4.4.7, §8.8. Catalog: E1141 added.

### Future Work

Not decided here, and not in the spec:

- A countdown form (for example `.rev()` on a range).
- A lint for a range whose constant bounds make it empty (`5..3`).
