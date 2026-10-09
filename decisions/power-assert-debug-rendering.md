[< All Decisions](../DECISIONS.md)

# Power-Assert Sub-Expression Values: Debug Rendering — Design Rationale

**Gap:** §2.20 *Assertion Failure Output* shows sub-expression values for `assert(expr)` but names no trait. `assert` has the signature `fn assert(cond: Bool, msg: Str = "")` and no type parameter. The compiler prints values with printf specs: a `Str` prints without quotes, and a `Char` prints as an integer. Both break §3.6.1. The compiler also splits only a top-level comparison of scalar operands. The spec says "direct operands and field accesses", and that promises more than the compiler does. The open question: when an operand has no `Debug`, is leaving out its line a compile-time choice or a specialization (the panel rejected specialization in the `assert_eq` vote)? Follow-up of V4 in [assert-eq-debug-bound.md](assert-eq-debug-bound.md).

**Result:** Q1 6-0 R-debug (each line is `<source text> = <debug(value)>`). Q2 6-0 O-omit (no line, no placeholder, no compile error, decided at typecheck). Q3 5-1 V-note (Minimalism dissent: V-none). Q3a 3-3 in Phase C, then 6-0 for a three-way "Hint-local" rule in Phase D. Q3b 6-0 always present. Q4 5-1 S-table (Minimalism dissent: S-cmp+logic). Q4a 6-0 Yes (the `mut` rule). Q4b 6-0 No (no text dedupe). Q5 6-0 L-skip (closed literal list). Q6 6-0 always present, `[]`. Q7 6-0 Yes (the fixed-set sentence). Phase D ran on Q3a (6-0 R2 after 3-3) and on the hint wording (6-0 W-short after 3-3). AI-first review: 5/5 pass.

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in independent-proposal → debate → vote rounds. The text below is verbatim. The moderator cut sentences and paragraphs but did not change words inside a quote.

#### Phase A — Independent proposals

All six chose `debug()` as the renderer. Five chose to leave out the line of a non-Debug operand, decided from the static type. DevOps first chose the same, plus a compile-time warning, and kept a compile error (as in `assert_eq`) as its second choice. Excerpts follow.

- **Systems:**
  > Why "source-level" matters: if the compiler checked Debug after mono, `check_same[Int]` would print values and `check_same[Handle]` would not. One generic body would then make different code depending on whether the concrete type has a trait it never asked for. That is a trait-presence branch on an unbounded parameter: the same specialization we rejected as option Z, and the coherence rule (5-0) forbids it. If the check runs at typecheck, on the generic body, every instantiation emits the same code and the same lines. That is a plain compile-time choice, like an overload picked on a declared type.
  >
  > Why omission is not the banned silent fallback: `<?>` puts invented text where a value should be. An absent line invents nothing, because the condition text in the header is still exact. Also, `assert` takes `cond: Bool` and has no type parameter, so making Debug a requirement would refuse valid Bool expressions such as `assert(f == g)` or a compare on a non-derived struct. The value lines are extra diagnostic data, not part of assert's contract.

- **Web/Scripting:**
  > This is not specialization. The choice depends on the type as written, the same way the compiler already picks `==` from that type. A generic `T` with no `Debug` bound never prints a line, even when it is instantiated with `Int`. No hidden trait-presence branch exists, so the output does not change between instantiations. That answers the ticket's question: the choice happens at compile time, from the declared type, not from the instantiated one.
  >
  > Why: today Str prints unquoted and Char prints as a number. `name = alice` next to `name = 97` is exactly the kind of output that produces Stack Overflow questions. `debug()` fixes both, and it matches assert_eq, so the language has one rendering rule and the user learns it once.
  >
  > This is the biggest win in the whole proposal. `assert(list.contains(x))` and `assert(s.starts_with(p))` are the 90% case in test code. If they show no values, users drop `assert` and write `assert_eq(list.contains(x), true)`. That is worse code, and it is what JS and Python developers already do in frameworks without power-assert.

- **PLT:**
  > Why this is not specialization. Specialization picks behaviour from facts about an instantiation that the code cannot see. This rule reads only the type the user wrote and the bounds in scope, which is how ordinary instance resolution works at a known type.
  >
  > Why omission and not E0306. `assert(cond: Bool)` has no type parameter for operands, so there is nothing to put a bound on. Requiring Debug would reject `assert(a == b)` on legal `Eq` types and change which programs compile. That is a worse break.
  >
  > Omission is not the banned silent fallback. A fallback puts a stand-in where a value should be. Here, the assertion text, its Bool result and the span are all printed in full. The value lines are extra context, and the output never prints a false value.

- **DevOps:**
  > My test for this gap is whether a user who reads a failure log can tell why it looks the way it does. Under the ticket's leaning rule, a line that disappears with no notice fails that test. The user sees `minimum = 500` but no line for `acct`, and nothing tells them the cause. That is the banned silent fallback moved down one level. The output can stay free of placeholders, but the compiler must report the omission somewhere the user can act on it. That place is compile time.
  >
  > Blink has no universal Debug, so it cannot copy pytest. It must state what happens to a non-Debug operand, and tooling must make that state visible. Rust's `assert_eq!` E0277 note ("doesn't implement Debug, add #[derive(Debug)]") is the diagnostic quality that W07xx should match.

- **AI/ML:**
  > We should not make Debug a bound on operands (E0306). `assert(cond)` is the universal fallback for any Bool. If `assert(p == q)` failed to compile because `p` has no Debug, models would hit a surprise error on the most common test line, and `assert` would become a fifth bounded assert.
  >
  > **Amendment, offered separately (P2b).** When at least one line is dropped, print one trailer line:
  >
  > ```
  > assertion failed: assert(order.total == expected)
  >   expected = 1200
  >   note: order.total not shown: Order has no Debug (add @derive(Debug))
  >   --> tests/order_test.bl:9:5
  > ```
  >
  > This is not a stand-in value. It sits on its own `note:` line, never as `x = <?>`. It also tells you how to fix it. Without it, a silent omission looks the same as "this shape is not decomposed", and a model debugging the test cannot tell the two apart.

- **Minimalism:**
  > Every operator the compiler splits (`==` `!=` `<` `<=` `>` `>=`) needs both operands to have the same static type. sections/03_types.md says: "Operands must be the same type". I checked it: `I32 < Int` gives a `TypeError`. So either both operands have Debug or neither does, and "omit one line" never happens. The real choice is made once per assertion: show both value lines or none.
  >
  > **Why omit and not error.** `assert` takes a `Bool`, not a `T`. It is the way to assert on types that have `Eq` but no `Debug`. If `assert(a == b)` required Debug, it would reject the same code that `assert_eq` rejects, and those types would have no plain assertion left. Leaving out a line prints nothing false. It is not the banned `<?>` fallback, because the header still shows the source text.

Phase A.5 grouped the proposals into seven questions. Q1: how a line renders (R-debug). Q2: what happens to an operand with no `Debug` (O-omit or O-error). Q3: whether an omitted line is made visible (V-none, V-note or V-warn). Q4: which condition shapes get lines (S-cmp, S-cmp+logic, S-table or S-scalar). Q5: literal operands (L-skip or L-show). Q6: the JSON `introspection` field when no line renders. Min's claim that both operands of a comparison share one type was relayed to all panelists as a fact claim.

#### Phase B — Debate highlights

Round 1 had no dissent on Q1 and Q2 except DevOps's O-error, which DevOps dropped. The positions moved on Q3, Q4, Q5 and Q6.

**Q3 (visibility).** Systems, DevOps and Web moved from V-none or V-warn to V-note. AI/ML moved the other way. DevOps's fact that decided it: with no lines, "no Debug" and "shape never split" look the same.

- **Systems:**
  > Q3: I move from V-none to V-note, with a limit. The no-placeholder rule bans a stand-in VALUE. A `note:` line holds no value. It is a fixed sentence about a type, and the compiler builds it at compile time from the same static check that drops the line. It costs one static string in the cold branch and nothing on the pass path. It also answers the only real weak point of O-omit: the user does not see why lines are missing.
- **DevOps:**
  > Q3, the main open point. min's fact changes my case, and I accept it. A split comparison needs both operands to have the same type, so under S-cmp an assert shows all of its value lines or none. With V-none, a failure where Debug is missing then looks the same as a failure on a shape that is never split, such as a bare Bool or `is_valid(x)`. The user cannot tell "add @derive(Debug) and you get values" from "this shape never shows values". Two outputs that look the same but need different fixes are a diagnostic bug. So V-none fails my test.
- **Web/Scripting:**
  > Q3: I change my position, from V-none to V-note as first choice, text output only. My Phase A said a hint was fine if it is "a fixed sentence about the type, never a stand-in value". aiml's `note: order.total not shown: Order has no Debug (add @derive(Debug))` is exactly that. It does not pretend to be a value, so it cannot hide a gap the way `<?>` or `[object Object]` does. It does the opposite: it names the gap and the fix.
- **AI/ML (moved to V-none in round 1):**
  > **Q3: I withdraw V-note (my P2b) and support V-none.** Three reasons:
  > - Given min's point, under a comparison the whole assert prints no lines, and the spec can state that in one sentence. A model learns "no value lines means the type has no Debug, or the shape is not decomposed" from the spec. It does not need to see that at runtime.
- **Minimalism (held V-none):**
  > Q3, V-none: yes, against both V-note and V-warn.
  > - V-note: a runtime line that says "order.total not shown" is a stand-in for a value at the place where the value would go. It is not `<?>`, but it does the same job one level up, which §3.6.1 forbids. It also adds an `omitted` JSON key that tools must learn. I vote no.

**Q4 (shapes).** Systems added a correctness amendment for `mut` parameters. PLT accepted `!e` as a transparent wrapper. Minimalism moved from S-cmp to S-cmp+logic. The panel rejected AI/ML's descent into `&&`/`||` operands and its text dedupe, and AI/ML withdrew both.

- **Systems (the mut amendment):**
  > Value semantics plus `mut self` (§3.6, §3.2: push/pop/set, Bytes writers) break the bind-to-temp approach for calls. If the compiler binds the receiver of `xs.pop()` to a temp and calls on the temp, the root does not change, so the assert has changed the program. If it calls on the root and renders afterwards, the line shows the post-call value, not what the method saw. Both are wrong.
  > - Amendment: a receiver or argument bound to a `mut` parameter gets no line and is not rebound. The call runs on the original place exactly as written. The compiler decides this statically from the callee signature. The other operands of that call still get lines.
- **PLT:**
  > - `!e`: I change my position and accept web's form, rows(!e) = rows(e). Negation is a Bool-to-Bool wrapper that adds no value of its own, so treating it as transparent does not add a level. aiml's form, which re-applies all rules recursively, does add a level, and I reject it.
  > - aiml's dedup by text is unsound. In `assert(next() == next())` both operands have the same text and different values, so dedup would print one value and hide the other. That misrepresents the program. I reject it.
- **Minimalism:**
  > Q4: I move from S-cmp to S-cmp+logic (sys P2). I vote no on S-table.
  > - Logic row: each `&&`/`||` operand that ran gets one Bool line. Bool always has Debug, so no omission question comes up. It shows which side failed, and that is the one thing the header cannot show.
  > - S-table (calls, receivers, `!`, arithmetic) is where the real cost sits:
  >   1. It brings back per-line omission. Today both operands of a comparison share one type (my claim is checked: `I32 < Int` is a `TypeError`), so it is all lines or none. A call's receiver and arguments have different types, so half-rendered output becomes the normal case.
  >   2. `assert(user.is_active())` would dump the whole `User`. That is often large and seldom what the reader needs.

**Q5 (literals).** Minimalism moved from L-show to L-skip and set a closed definition. Systems answered Minimalism's earlier "fewer lines is always safe".

- **Systems:**
  > Q5: L-skip. Answer to min: "fewer lines is always safe" is not true for us. Users keep failure output in golden files and CI log greps, and the plt rule fixes output per site. Dropping lines later is an output change we would have to ship as a break. Decide it now.
- **Minimalism:**
  > Q5: I move to L-skip, on one condition: a closed definition of "literal". I propose this: an Int, Float, Char or Bool literal token, or a Str literal with no interpolation, with an optional unary `-` on a number. Constructor forms (`Ok(500)`, `Point { x: 0, y: 0 }`, `[]`) are NOT literals and keep their line.

**Q6 (JSON) and Q7.** DevOps withdrew "absent". Minimalism offered the sentence that became Q7.

- **DevOps:**
  > Q6: the shared shape is fine. On "absent vs `[]` when no line renders" I now prefer `[]`, with the field always present on a decomposed site. With `omitted` carrying the reason, absent vs empty no longer needs to signal anything, and plt's "fixed key set per site" is simpler for consumers. I withdraw "absent".
- **Minimalism:**
  > Amendment I offer: one sentence in §2.20, "Which lines appear is decided at compile time from the source shape and static types; no runtime value changes the set of lines, except that a `&&`/`||` operand that did not run has no line." That one sentence answers the specialization question, the JSON stability point and the short-circuit rule at once.

All six panelists then said STABLE.

#### Phase C — Final vote

Silent ballot. Q3a, Q3b, Q4a and Q4b were conditional on their parent option winning. They apply because V-note and S-table won.

- **Q1: Line form.** (6-0 for R-debug)
  - *Option* R-debug: each line is `<source text> = <debug(value)>`.
  - **Systems:** Yes.
    > one render path, the same `debug()` that assert_eq uses. The printf table and its fixed list of scalar kinds go away, along with the Str-unquoted and Char-as-integer bugs.
    >
    > Concern: the failure branch now calls into the Debug impls, so a Debug impl that panics would hide the assertion failure. A panic during the render must still report the original failure.
  - **Web/Scripting:** Yes.
    > One rendering rule across assert, assert_eq and Debug means users learn it once. Quoted strings and `'z'` rather than `97` end the "is that a string or a number?" confusion that the printf forms cause today.
    >
    > Concern: A large Debug value (a whole struct) can flood a CI log, and we have no length limit yet.
  - **PLT:** Yes.
    > one renderer for every assertion form means one semantics. The printf forms were an implementation detail that leaked into the output, and they break §3.6.1 (Char as a code point, Str unquoted).
    >
    > Concern: an expensive or huge Debug output on a large receiver makes failure output long. That is a cost, not a soundness fault.
  - **DevOps:** Yes.
    > Users should read a value the same way in `assert`, `assert_eq` and `debug()`. Today's `tag = 66` for a Char and unquoted Str lines go against §3.6.1, and nobody can tell they are wrong by reading the log.
    >
    > Concern: A large Debug value (a whole struct) can make a failure line long. Truncation is a separate ticket if users report it.
  - **AI/ML:** Yes.
    > One render rule for all four assertion built-ins, so there is one rule to learn from the spec. Quoted strings and Char literals let a model read the failure without guessing types.
    >
    > Concern: Large Debug values (a big List or struct) can flood a CI log or an agent's context. That is a later size-limit question, not a reason to vote against.
  - **Minimalism:** Yes.
    > It deletes a private type list and the printf specs, and it reuses the one trait the other three assertions already use. Nothing is added; a special case goes away.
    >
    > Concern: Large Debug forms (a big List or Map) make long value lines. That is a cost we already accepted for assert_eq.

- **Q2: Operand whose static type has no Debug.** (6-0 for O-omit)
  - *Option* O-omit: decided at typecheck from the static type and the bounds in scope, never per instantiation; no line, no placeholder, no compile error.
  - *Option* O-error: E0306, as for `assert_eq`.
  - **Systems:** O-omit.
    > the decision runs at typecheck on the generic body, so every instantiation emits identical code and output. That is a static choice, not specialization. `assert` takes a Bool and has no type parameter to carry a bound, so O-error would refuse correct programs over a diagnostic, and in generic code it would push `Debug` into public signatures.
    >
    > Concern: implementers may be tempted to check Debug after mono, where it is "free". That is exactly the per-instantiation branch we banned, so the spec text must say "static type as written, bounds in scope".
  - **Web/Scripting:** O-omit.
    > `assert` is the first tool a newcomer picks up, and it has no type parameter. A trait error on `assert(h == g)` blocks a correct test for the sake of a nicer diagnostic, which puts the cost on the wrong side. It also forces `Debug` into generic public signatures (plt's point about bounds spreading).
    >
    > Concern: Users will not know the rule unless Q3 tells them, so the output can look broken.
  - **PLT:** O-omit.
    > `assert(cond: Bool)` has no type variable that a bound could attach to, so O-error would be a rule on syntax pretending to be a typing rule. Inside generic code it also forces a test-only `Debug` bound onto public signatures and narrows which types can call them. The decision comes from entailment, Γ ⊩ Debug τ, at typecheck. Because of the orphan rule and the no-overlap rule, a negative result for a concrete type is stable, so this is elaboration and not specialization.
    >
    > Concern: if the implementation decides after mono instead of at typecheck, it silently becomes specialization. The spec text must say "never per instantiation", and a test must pin it: `fn f[T: Eq]` called with `T = Int` prints no line.
  - **DevOps:** O-omit.
    > I dropped O-error in round 1. An E0306 on `assert(h == g)` blocks a valid Bool check because of how its failure output looks, and in generic code it forces Debug into public signatures (plt's bound-creep point). Omission is acceptable only with Q3 making it visible.
    >
    > Concern: If V-none wins Q3, "no lines" will mean two different things, and users will file bugs about missing values that are working as designed.
  - **AI/ML:** O-omit.
    > `assert(any Bool)` must always compile. It is the fallback a model reaches for first. O-error would turn the most common generated test line into a trait error, and it would push generic code to add a Debug bound (plt's bound-creep point).
    >
    > Concern: Users may not know why lines are missing. Q3 is the answer to that.
  - **Minimalism:** O-omit.
    > `assert` takes a Bool and has no type parameter to carry a bound. O-error would remove the only plain assertion for Eq-but-not-Debug types, and in generic code it would push Debug into public signatures (plt's bound-creep point). Deciding from in-scope bounds keeps it out of specialization.
    >
    > Concern: Users may not know why a failure shows no values; Q3 decides whether we pay surface to tell them.

- **Q3: Visibility of an omitted line.** (5-1 for V-note; Minimalism dissent: V-none)
  - *Option* V-none: nothing reports it.
  - *Option* V-note: a runtime `note:` line per omitted operand, after the value lines and before `-->`. The text is fixed per site at compile time and names the static type as written (`T` stays `T`).
  - *Option* V-warn: compile-time warning W07xx `AssertOperandNotRendered`, configurable in `[lints]`.
  - **Systems:** V-note.
    > it is one static string per omitted operand, built at compile time, in the cold branch, with zero cost on the pass path. It states a true fact about a type and does not stand in for a value, so the §3.6.1 rule holds. It also separates "no Debug" from "shape not split", which V-none cannot do. V-warn fires on correct code that never fails.
    >
    > Concern: the note must name the type as written (`T`), or it becomes per-instantiation output by the back door.
  - **Web/Scripting:** V-note.
    > The note shows up at the moment of need: on failure, in the log the user is already reading, and never on code that passes. It is a fixed, true sentence about a static type and takes no value slot, so it is not the `<?>` or `[object Object]` stand-in that §3.6.1 bans. It also lets the user tell "no Debug, add a derive" apart from "this shape is never split", which V-none cannot. V-warn fires on correct code and gets turned off on day one.
    >
    > Concern: Min's reading (a note is a stand-in "one level up") may hold for some readers. The spec text must say clearly that the note is about the type, never the value.
  - **PLT:** V-note.
    > a note states a true fact about a static type. It is fixed per site at compile time and takes no value slot, so it is not a stand-in value. The no-placeholder rule bans false or empty values, not true statements. devops is right that with V-none, "no Debug" and "shape not split" print the same output while needing different fixes, and that is a diagnostic defect. V-warn fires on correct code and pushes users toward bound creep, so I rank it last.
    >
    > Concern: if the note text is ever computed from the instantiated type, the output differs per instantiation and we are back to specialization.
  - **DevOps:** V-note.
    > A note shows only when a test fails, which is when the user reads the output, and it adds no noise to correct code that passes. It takes no value slot and is a true, fixed sentence about a static type, so it is not the banned `<?>`. Under S-table, partial omission becomes the normal case (`orders.contains(id)`), so a silent gap would be read as a compiler bug. Ranking: V-note > V-warn > V-none.
    >
    > Concern: The note wording and the `omitted` key become stable output that golden files depend on, so we must fix the text now and not change it later.
  - **AI/ML:** V-note — "I return to my original P2b, which I withdrew in round 1 to cut options."
    > Three panelists now back it, and devops stated the core point well. With V-none, a missing Debug and a shape that is never split produce the same output, but they need different fixes. Two outputs that look the same but need different fixes are the hardest case for an agent that debugs from logs.
    >
    > Concern: The note can still be read as a weak placeholder. The rule must keep it a fixed sentence per site and never a value-shaped line.
  - **Minimalism: V-none. (dissent)**
    > devops's point is fair: with no lines, "no Debug" and "shape never split" look the same. But the header still shows the source, so nothing false is printed. A V-note is a new output form that needs its own text rules, a JSON key, the T-vs-concrete wording rule and tests, all to show at runtime what the spec states in one sentence. V-warn fires on correct code. An off-by-default lint or LSP hint can come later as tooling, with no change to the language output.
    >
    > Concern: If V-note wins, the note text becomes a stable output contract (goldens, CI greps), and its wording will be hard to change later.

- **Q3a: Fix hint in the note.** (3-3 in Phase C; sent to Phase D; Hint-local 6-0)
  - *Option* Hint-none: `note: <expr> not shown: <Type> has no Debug`.
  - *Option* Hint-yes: `(add @derive(Debug))` for a concrete type; `<T> has no Debug bound` for a type parameter.
  - **Systems:** Hint-yes.
    > with plt's split: `(add @derive(Debug))` for a concrete type, `T has no Debug bound` for a type parameter. Both are static text at no cost, and the split keeps the advice correct for generics.
  - **Web/Scripting:** Hint-yes.
    > The fix is the whole point for a newcomer, and a JS/Python developer will not guess `@derive(Debug)` on their own. plt's `T has no Debug bound` wording for a type parameter avoids wrong advice.
  - **AI/ML:** Hint-yes.
    > The hint is the one-token action a model or user takes next. It costs a few bytes on a cold path, and plt's variant keeps it correct for generic code.
  - **PLT:** Hint-none.
    > "(add @derive(Debug))" is wrong advice in two cases. For a type from another package, the orphan rule forbids the user from adding it. For a function type, Debug cannot exist at all. The fact is enough, but for a type parameter the true fact is "`T` has no Debug bound", not "`T` has no Debug", because the instantiation may well have Debug.
    >
    > Concern: users who do not know what to do with the note. LSP and `blink explain` can give context-aware advice there.
  - **DevOps:** Hint-none.
    > The note states the fact, and the LSP and `blink explain` give the fix. That also avoids the wrong `@derive` advice for a type parameter that plt raised. If the panel wants a hint, plt's split wording (derive for a concrete type, "no Debug bound" for `T`) is the only correct form.
  - **Minimalism:** Hint-none.
    > The fix hint belongs to `blink explain` and the LSP, not to every CI log, and leaving it out removes the concrete-vs-type-parameter wording fork.
    >
    > Concern: Users who only read CI logs get no fix pointer.

- **Q3b: JSON `omitted`.** (6-0 for always present, `[]` when nothing is left out)
  - *Option* always present (`[]`).
  - *Option* absent when nothing is left out.
  - **Systems:**
    > One schema per site, and consumers do not branch on whether the key exists.
  - **Web/Scripting:**
    > A key that is sometimes missing leads to KeyError and undefined bugs in every consumer, while a fixed schema needs one code path.
  - **PLT:**
    > a total field gives one schema and a key set fixed per site.
  - **DevOps:**
    > One fixed key set per record, the same as Q6. I withdraw my earlier "absent" here as well.
  - **AI/ML:**
    > One schema means no key-existence branch in generated consumer code.
  - **Minimalism:**
    > One schema per record, the same rule I vote for in Q6.
    >
    > Concern: Each record carries one more key for a rare case.

- **Q4: Decomposed shapes.** (5-1 for S-table; Minimalism dissent: S-cmp+logic)
  - *Option* S-table: comparison → both operands; method call `r.m(args)` → receiver and each arg; free call `f(args)` → each arg; `!e` → the rows of `e`; top-level `&&`/`||` → one Bool line per operand that ran, no descent. No arithmetic row.
  - *Option* S-cmp+logic: comparison operands, plus the `&&`/`||` row.
  - *Option* S-cmp: comparison operands only.
  - *Option* S-scalar: today's scalar-kind set, rendered through `debug()`.
  - **Systems:** S-table.
    > every row binds each operand once, left to right, into temps the condition uses anyway, so the pass path costs what it costs today. `xs.contains(x)` and `!xs.is_empty()` are the common asserts that show nothing today. The table is closed and each row is one level, so codegen stays a fixed switch on the node kind.
    >
    > Concern (min's point, which I accept as real): `assert(user.is_active())` debug-renders the whole receiver. A large value gives large output in CI logs, so a size cap on a value line may be needed later.
  - **Web/Scripting:** S-table.
    > `assert(xs.contains(x))`, `assert(s.starts_with(p))` and `assert(!xs.is_empty())` are the 90% case in real test code. Under S-cmp they print nothing, and users drift to `assert_eq(xs.contains(x), true)`, the Rust habit that power-assert was voted in to avoid. The table is a closed five-row list, each row one level deep, so it is easy to learn. Fallback: S-cmp+logic.
    >
    > Concern: Min's point about `assert(user.is_active())` printing the whole `User` is real. Long receivers can make the output noisy, and we may later need a size limit (a separate ticket).
  - **PLT:** S-table.
    > every row is one level and binds only values that ordinary evaluation produces, left to right, so §2.20 order holds. The rows are closed and mechanical, so the rule is a function of syntax plus static types. `!e` as a transparent Bool wrapper adds no level. min's objection is true: S-table brings in partial omission. But P1 already defines per-operand omission soundly, and with V-note that omission is visible. If S-table fails, I vote S-cmp+logic.
    >
    > Concern: a call row on a large receiver prints a whole struct, as in min's `user.is_active()`. That is noise, not wrong output.
  - **DevOps:** S-table.
    > `assert(xs.contains(x))`, `assert(s.starts_with(p))` and `assert(!xs.is_empty())` are the asserts where users most need a value and get none today. The table is a closed list of five rows that tooling and the spec can state exactly. Ranking: S-table > S-cmp+logic > S-cmp > S-scalar.
    >
    > Concern: min is right that `assert(user.is_active())` will print a whole `User`, so long receiver lines will be common output.
  - **AI/ML:** S-table.
    > `xs.contains(x)`, `s.starts_with(p)` and `!xs.is_empty()` make up a large share of the asserts models generate. Under S-cmp they print nothing, so the agent has to re-run the test with debug prints added, which costs extra tokens and an extra cycle. The table is a closed list of rows, each one level deep, and can be applied mechanically.
    >
    > Concern: Receivers like `user.is_active()` can dump a large struct. Later output trimming may be needed.
  - **Minimalism: S-cmp+logic. (dissent)**
    > Each row in it is either same-typed (comparison: all lines or none) or always Debug (Bool lines), so per-operand omission never comes up and both Q2 and Q3 stay cheap. S-table needed sys's mut-parameter amendment to be correct at all: the call row interacts with `mut self` value semantics, so a temp either changes the program or shows a post-call value. A row that needs a correctness patch found in round 1 is not ready. It can be added later by its own vote once there is evidence, and it builds on this one.
    >
    > Concern: `assert(xs.contains(x))` and `assert(!xs.is_empty())` stay bare. They are common shapes, and users will move them to assert_eq to get values.

- **Q4a: The `mut` rule (Systems' amendment).** (6-0 Yes)
  - *Option:* a receiver or argument bound to a `mut` parameter gets no line and is not rebound; the call runs on the original place; decided statically from the callee signature.
  - **Systems:** Yes.
    > Without it, the binding to a temp either changes the program, because the mutation lands on the temp and not the root, or the line shows the post-call value. Both are correctness bugs, and the callee signature settles the case statically.
  - **Web/Scripting:** Yes.
    > An assert must never change what the program does, and printing a value from before or after a `mut self` call would be a lie in either direction. Leaving that line out is the only honest choice.
  - **PLT:** Yes.
    > under value semantics, a place bound to a `mut` parameter has no single honest pre-call or post-call value to show, and rebinding it to a temp changes the program. Leaving it out, decided from the callee signature, keeps the assert semantics-preserving. sys found a real soundness hole here.
    >
    > Concern: the same issue at depth one must be handled for arguments too, not only receivers. The amendment covers both, so I am satisfied.
  - **DevOps:** Yes.
    > An assert must not change what the program does. Rebinding a `mut self` receiver to a temp, or showing its value after the call, either changes behaviour or shows a false value. Deciding it from the callee signature keeps it a compile-time choice.
  - **AI/ML:** Yes.
    > sys is right. Under value semantics, a `mut self` receiver can be neither bound to a temp nor shown faithfully. Deciding this from the callee signature keeps the rule static and keeps the assert from changing the program.
  - **Minimalism:** Yes.
    > Without it, S-table changes what the program does or shows a value the method never saw. It is required for correctness.
    >
    > Concern: A rule keyed on the callee's `mut` parameters is one more thing users must know to predict which lines appear.

- **Q4b: AI/ML's text dedupe.** (6-0 No; AI/ML had already withdrawn it)
  - *Option:* no line for a sub-expression whose text matches one already printed.
  - **Systems:** No.
    > plt's `next() == next()` case shows it hides a real value. Text equality is not value equality.
  - **Web/Scripting:** No.
    > `next() == next()` shows that the same text can have different values, so dedupe would hide a real value (and aiml has withdrawn it).
  - **PLT:** No.
    > two equal source texts are not equal values when evaluation has effects, as in `next() == next()`, so dedupe would hide a value and misreport the program. aiml has also withdrawn it.
  - **DevOps:** No.
    > `next() == next()` has two equal texts with different values, so a dedupe hides one of them and the output misreports the program.
  - **AI/ML:** No.
    > plt's and devops's `next() == next()` case shows the dedupe hides a real value, so I keep it withdrawn.
  - **Minimalism:** No.
    > plt's `next() == next()` case shows that matching text does not mean matching values, so the dedupe would hide a real value.
    >
    > Concern: None. The rule is withdrawn and it is unsound.

- **Q5: Literal operands.** (6-0 for L-skip)
  - *Option* L-skip: no line for a literal operand. "Literal" is a closed list: an Int, Float, Char or Bool literal token, or a Str literal with no interpolation, with an optional unary `-` on a number. Composite forms (`[1, 2]`, `Point { .. }`, `Ok(500)`) are not literals and keep their line.
  - *Option* L-show: no special rule.
  - **Systems:** L-skip, with min's closed definition of a literal.
    > it is a pure syntax check at compile time and costs nothing at run time. A line like `"alice" = "alice"` is noise in every golden log, and removing it later would break those goldens. The closed token list keeps it predictable.
    >
    > Concern: the edge cases of the definition (a Str with interpolation, a negative Float) need test rows, or the implementation drifts from the list.
  - **Web/Scripting:** L-skip.
    > `"bob" = "bob"` is noise that teaches people to skip the output. If we decide later, every golden file and snapshot breaks, so we should decide now. Min's closed token list makes the rule easy to predict, and composite forms keep their lines.
    >
    > Concern: A user may expect `-x` or a `const` name to count as a literal. The spec should show one example of a line that is kept.
  - **PLT:** L-skip, with min's closed literal list.
    > the rule is purely syntactic and decidable, and the closed list removes the "looks literal" judgment. Constructor forms keep their line because their source text and their debug form can differ.
    >
    > Concern: a Str literal with escapes, where the source text and the debug form match by design. That is fine.
  - **DevOps:** L-skip, with min's closed definition of a literal.
    > `"Bob" = "Bob"` is noise, and it would end up in every golden file, so removing it later breaks those files. A closed token list means the user never has to guess what counts as a literal.
    >
    > Concern: A Str literal with escapes, such as `"a\tb"`, now has a source form and a debug form that differ slightly. That is acceptable because its source text is still its exact value.
  - **AI/ML:** L-skip (min's closed literal list).
    > Lines like `500 = 500` cost tokens and carry zero information. Dropping them later would break goldens and learned output, so decide now. The closed token list is easy to apply from the spec.
    >
    > Concern: Users may expect `-x` or constant names to count as literals. The closed list must be in the spec text, word for word.
  - **Minimalism:** L-skip.
    > The definition is closed and purely syntactic: scalar literal tokens, a Str with no interpolation, and a unary minus on a number. sys and aiml are right that goldens make a later drop a break, so decide it now.
    >
    > Concern: Someone will ask for `Ok(500)` or `[]` to count as "literal enough". The closed list must hold against that.

- **Q6: JSON `introspection` when no line renders.** (6-0 for always present, `[]`)
  - *Option* always present, `[]`.
  - *Option* absent.
  - **Systems:**
    > A total field gives a fixed schema per site and no key-presence checks for consumers.
  - **Web/Scripting:**
    > One schema means consumers never have to check whether the key exists. That is the most common bug in JSON consumer code that people (and models) write.
  - **PLT:**
    > a total field with a fixed key set per site. Consumers never branch on whether the key exists.
  - **DevOps:**
    > A key that is sometimes absent is the classic KeyError/undefined bug in every consumer, and plt's rule fixes the key set per site at compile time.
  - **AI/ML:**
    > A field that is always present gives every consumer, human or generated, one shape to read.
  - **Minimalism:**
    > One shape means consumers write one code path. Absent vs `[]` carries no information, and a total field matches the per-site fixed key set.
    >
    > Concern: Under V-none, `[]` still cannot tell "no Debug" from "not split". Consumers must not read meaning into it.

- **Q7: Minimalism's sentence for §2.20.** (6-0 Yes)
  - *Sentence:* "Which lines appear is decided at compile time from the source shape and static types; no runtime value changes the set of lines, except that a `&&`/`||` operand that did not run has no line."
  - **Systems:** Yes.
    > One sentence fixes the line set at compile time. That settles the specialization question and the JSON stability point in one place. Under V-note, the notes come from the same compile-time decision, so the sentence covers them too.
  - **Web/Scripting:** Yes.
    > One sentence answers "why did this line appear?" for both users and tools. It also holds under V-note, because the notes are fixed per site too.
  - **PLT:** Yes.
    > this one sentence is the soundness statement for the whole feature. It says which lines appear depends only on syntax and static types, with short-circuit evaluation as the one runtime dependency that is honest and forced.
    >
    > Concern: with Q4a, a reader might ask whether a mut-bound operand is a runtime exception to the sentence. It is not, because the callee signature decides it statically, but the spec should say so next to Q4a.
  - **DevOps:** Yes.
    > One sentence answers the specialization question and the golden-file stability question, and the note lines in V-note follow the same compile-time rule.
  - **AI/ML:** Yes.
    > The sentence makes the output predictable from the source alone, which is the learnability property I care about most. It also states that this is not specialization.
  - **Minimalism:** Yes.
    > One sentence fixes the line set at compile time from the shape and static types, which answers specialization, JSON stability and short-circuit together, whichever Q4 row set wins.
    >
    > Concern: If S-table wins with Q4a, the sentence must also name the mut-parameter exclusion. That exclusion is static, so the sentence still holds, but the text must not read as if it covers every operand.

#### Phase D

Q3a tied 3-3 (Systems, AI/ML and Web for Hint-yes; DevOps, Minimalism and PLT for Hint-none). All other questions passed, so Phase D covered Q3a only. It ran in two rounds: first on the rule, then on the wording of the hint.

##### Round 1 — The rule for the hint

PLT's objection decided the debate. The flat hint gives advice that is false in some cases. All six panelists then proposed the same three-way rule, under different names.

- **PLT:**
  > My objection is to wrong advice, not to advice. The Hint-yes form tells the user to add the derive for every concrete type, and that is false in three cases:
  > 1. The type is declared in another package (stdlib or a dependency). The orphan rule forbids the user's impl, so the hint names an action the compiler will reject.
  > 2. The type is a function type or another built-in with no Debug. Debug can never exist for it.
  > 3. The type is a container such as `List[Handle]`. The fix belongs to the element type, not to `List`.
  >
  > A hint that points users to an error is worse than no hint. This is the same principle as our no-placeholder rule: output must never say something false.
- **Systems:**
  > Amendment, "Hint-local". The compiler picks one of three fixed texts at compile time from the static type as written:
  > 1. A struct or enum declared in the current package: `note: order not shown: Order has no Debug (add @derive(Debug) to Order)`
  > 2. A type parameter: `note: x not shown: T has no Debug bound`. This is plt's wording, true for every instantiation.
  > 3. Anything else (a foreign type, a function type, a container whose element is case 3): `note: h not shown: Handle has no Debug`, with no hint.
- **Web/Scripting:**
  > Answering devops and min ("the LSP and `blink explain` give the fix"): the note has no error code, so `blink explain` has nothing to look up, and nobody opens an LSP to read a failed CI run. The CI log is the one place the user is when they need the fix, and min agrees that "users who only read CI logs get no fix pointer."
- **DevOps:**
  > My test is that a diagnostic never gives advice the user cannot follow. rustc follows the same rule: it shows a `help:` suggestion only when the suggestion applies, and otherwise states the fact.
- **AI/ML:**
  > `(add @derive(Debug))` appears only when the static type is a struct or enum declared in the current package.
  > For a type parameter, plt's fact text: `T has no Debug bound`.
  > Every other case gets the fact only: `<Type> has no Debug`.
- **Minimalism:**
  > Hint-yes only under the three-way rule above, never the flat form. My ranking: Hint-none (with plt's `T` wording) > Hint-yes-local-only > flat Hint-yes.

Re-vote on Q3a: **Hint-local 6-0.** A sub-question on the wording split 3-3.

- **PLT:**
  > Vote: Hint-local. Wording: W-named.
  >
  > Reasoning: under Hint-local every note is true. The compiler chooses among the three texts at typecheck, using only the static type and the package that declares it. So the derive hint shows only where the orphan rule lets the user act on it, and the output does not change from one instantiation to another.
- **DevOps:**
  > Vote: Hint-local.
  > Reasoning: The note gives a hint only where the user can apply it, and otherwise states the fact. That is the rustc help-suggestion standard and our own E0306 behaviour. It answers both sides: CI-only readers get the fix, and nobody gets advice the orphan rule or a function type makes impossible.
  >
  > Concern: Case 1 vs case 3 depends on how "declared in the current package" is defined. Workspaces and multi-package builds need one exact definition, which the orphan rule's notion of "local" already supplies and the spec should reuse.
- **Systems:**
  > Vote: Hint-local, wording W-named.
  >
  > Reasoning: the hint appears only where the one step it names is possible. The compiler picks it at typecheck from the declaration site, as one of three fixed static strings, with no runtime cost and no per-instantiation branch, so the Q2 and Q7 rules hold.
- **Web/Scripting:**
  > Vote: Hint-local
  >
  > Reasoning: Users get the fix in the CI log at the moment of failure, and the hint appears only where it is true. That answers plt's objection (foreign types, function types) without leaving newcomers at a dead end in the common case, which is their own struct in a test.
  >
  > Wording: W-short.
- **AI/ML:**
  > **Vote:** Hint-local.
  >
  > **Reasoning:** Every hint the note prints is true, and it gives the next action to the readers who need it most, CI logs and agents that parse `--json`.
  >
  > **Wording:** W-short.
- **Minimalism:**
  > Vote: Hint-local.
  >
  > Reasoning: My objection was false advice: telling users to derive on foreign, function or FFI types. The three-way rule removes that, and all three texts are fixed at typecheck from the static type as written. That keeps the cost to three static strings, with no runtime logic. I still rank Hint-none as the smaller surface, but the rule the panel converged on is correct, and I will not dissent on a matter of taste.
  >
  > Wording: W-short.

The wording tied 3-3: W-named `(add @derive(Debug) to <Type>)` from PLT, Systems and DevOps; W-short `(add @derive(Debug))` from AI/ML, Web and Minimalism.

##### Round 2 — The wording of the hint

The wording had no debate step. The user, as BDFL, asked for one debate and one re-vote on the wording only. Systems, PLT and DevOps switched to W-short. Web and Minimalism held. AI/ML switched to W-named.

- **Systems:**
  > My re-vote reason was wrong. I said that in a container case the type to fix is not the expression's own type. But under the decided rule a container is case 3 and gets no hint at all. Only case 1 carries the hint, and in case 1 the type to fix is exactly the static type the note already names.
  >
  > W-named would help only if the hinted type could differ from the named type. The decided rule makes the two the same by construction: one static type, picked once at typecheck. So W-short is complete and correct.
- **PLT:**
  > The W-short side is right, and my reason was wrong. Under the rule we voted 6-0, the hint appears only in case 1. There, the type named in "<Type> has no Debug" is the operand's own static type, and that is the exact type that needs the derive. A field-path operand still names its type on the line: `order.total not shown: Money has no Debug (add @derive(Debug))`. The user does not need to work out the type from the expression text, so devops's lookup concern is already met.
- **DevOps:**
  > Condition: the spec text must state that the hint applies only when the named type is the operand's own static type, which the case 1 / case 3 split already ensures. If a later rule ever adds a hint for a type the note does not name, that rule must use the named form.
- **Web/Scripting (held W-short):**
  > The one real edge case: a generic local type such as `Box[Int]`. W-named would read `to Box[Int]`, while the derive goes on `Box`. That points slightly the wrong way, which is one more reason for W-short.
  >
  > I accept W-named if it wins. It is redundant, not wrong.
- **Minimalism (held W-short):**
  > The W-named reasons describe cases that rule 1 never reaches:
  > - sys's container case: a container whose element lacks Debug is rule 3, which has no hint at all. W-named has nothing to name there.
- **AI/ML (switched to W-named in the debate):**
  > The field-path argument from plt and devops does hold, from my side. The note is `order.total not shown: Money has no Debug (add @derive(Debug))`. A model reads "add" next to the expression `order.total` and may attach the derive to `Order`, the root it can see, rather than to `Money`. I have seen that error pattern in generated fixes: the edit goes to the nearest visible name, not to the noun named earlier in the sentence.

Re-vote on the wording: **W-short 6-0.** Web's `Box[Int]` point moved AI/ML.

- **AI/ML:**
  > **Vote:** W-short.
  >
  > **Reasoning:** web's `Box[Int]` case decides it for me. W-named would print `to Box[Int]`, but the derive goes on `Box`, so in the generic case the "unambiguous" form points the edit at text a model cannot write. My field-path concern is already met, because case 1 names the operand's own type (`Money`) right before the hint. A correct short form beats a longer form that is sometimes wrong.
  >
  > **Concern:** A model may still attach the derive to the expression's root (`Order`). The spec example for case 1 should therefore use a field-path operand, so the pattern is learned from the spec.
- **Systems:**
  > Vote: W-short.
  >
  > Reasoning: by construction of rule 1, the type to fix is the type the line already names, so `to <Type>` repeats it. web's `Box[Int]` case is a further point against W-named: the note names the applied type, while the derive goes on the declaration `Box`, so W-named would point slightly wrong unless it adds a separate rule for writing the type name.
- **PLT:**
  > Vote: W-short.
  >
  > Reasoning: in case 1 the type the hint refers to is, by construction, the operand's own static type, and the fact clause on the same line already names it, so W-named adds no information. web's edge case also makes W-named slightly wrong. For a generic local type, `to Box[Int]` names an instantiation, but the derive goes on the declaration `Box`. A hint must never name the wrong target.
- **DevOps:**
  > Vote: W-short.
  > Reasoning: Under rule 1 the hinted type is by construction the type the note already names, so `to <Type>` repeats it. web's `Box[Int]` case shows that W-named can also point the wrong way: it would say `to Box[Int]`, but the derive goes on `Box`. A fixed diagnostic must never name the wrong target, even slightly.
  > Concern: aiml's point that a model may attach the derive to the visible root (`Order`) and not to `Money` is real. The LSP quick fix and `blink explain` should carry the exact target, so that tools never rely on parsing the note text.
- **Web/Scripting:**
  > Vote: W-short
  >
  > Reasoning: Under the 6-0 rule, the hint appears only in case 1, where the type to fix is the type the note has just named. `to <Type>` repeats a word from the same line.
- **Minimalism:**
  > Vote: W-short.
  >
  > Concern: If a later rule adds a hint whose target type differs from the named type, W-short would become ambiguous; that rule must then use a named form (devops's condition, which I support).

##### Step 8 — User sign-off

The user signed off the full tally ("okay, send it").

##### AI-first review

5/5 pass: Learnability, Consistency, Generability, Debuggability, Token efficiency. The rule adds no new syntax. Closed lists make the output predictable from the source. The note names the fix. The literal skip and the notes only on failure keep the output short.

### Final Spec

```text
assertion failed: assert(users.contains(name))
  users = ["ana", "bo"]
  name = "cy"
  --> tests/test_users.bl:8:5
```

```text
assertion failed: assert(cart.is_open() && cart.total() > 0)
  cart.is_open() = true
  cart.total() > 0 = false
  --> tests/test_cart.bl:14:5
```

```text
assertion failed: assert(order.total.covers(limit))
  limit = 500
  note: order.total not shown: Money has no Debug (add @derive(Debug))
  --> src/shop.bl:21:5
```

Locked design points (spec: §2.20 *Sub-expression Values* in `sections/02_syntax.md`):

- **Shape table (closed, one level deep):** a comparison gives `a`, then `b`. A method call `r.m(x, y)` gives the receiver and each argument. A function call `f(x, y)` gives each argument. `!e` gives the lines that `e` gets. A top-level `a && b` or `a || b` gives one `Bool` line for each operand that ran, and the operands are not decomposed. Any other shape gives no lines. Arithmetic has no row. A field access is one operand.
- **Debug rendering:** each line is `<source text> = <value>`, and `debug()` (§3.6.1) renders the value. Lines come in source order. Each operand runs once, left to right. The lines do not change what the program does.
- **Omission decided at typecheck:** an operand whose type has no `Debug` gets no value line. The compiler decides from the static type as written at the `assert` site and the bounds in scope, never per instantiation. There is no placeholder and no compile error. In `fn check[T: Eq](a: T, b: T)`, `a` and `b` get no line, also when `T` is `Int`.
- **Note forms:** one `note:` line for each omitted operand, after the value lines and before `-->`. The text is fixed at compile time and has one of three forms. For a struct or enum that the package of the asserting module defines (the orphan-rule test): `note: <expr> not shown: <Type> has no Debug (add @derive(Debug))`. For a type parameter: `note: <expr> not shown: <T> has no Debug bound`. For any other type (a foreign type, a function type, an opaque or FFI type, or a container whose element has no `Debug`): `note: <expr> not shown: <Type> has no Debug`. `<Type>` and `<T>` are the static type as written, so a type parameter stays `T`. The derive hint appears only in the first form.
- **`mut` rule:** an operand bound to a `mut` parameter (the receiver of a mutating method, or an argument bound to a `mut` parameter) gets no line and is not bound to a temporary. The call runs on the original place. The callee signature decides this at compile time. The other operands of the call keep their lines.
- **Literal list (closed):** no line for an `Int`, `Float`, `Char` or `Bool` literal, a `Str` literal with no interpolation, or a number literal with a unary `-`. A composite form, such as `[1, 2]`, `Point { x: 0, y: 0 }` or `Ok(500)`, is not a literal and keeps its line.
- **Fixed-set sentence:** "Which lines appear is decided at compile time from the source shape and static types; no runtime value changes the set of lines, except that a `&&`/`||` operand that did not run has no line." The `mut` rule and the `Debug` rule are static rules of this kind.
- **JSON (`blink test --json`):** `introspection` is a list of `{"expr": <source text>, "value": <debug string>}`, one entry for each value line, in the same order. `omitted` is a list of `{"expr": <source text>, "type": <static type as written>}`, one entry for each `note:` line, in the same order. An operand with no line has no `introspection` entry, not `null` and not a placeholder. Both fields are always present, and each is `[]` when it has no entries.

### Follow-ups

- A size cap on a value line for large Debug output. All six panelists raised this.
- A `Debug` impl that panics while it renders must still report the original assertion failure (Systems).
- The LSP quick fix and `blink explain` carry the exact derive target, so that tools do not parse the note text (DevOps).
- If a later rule adds a hint for a type other than the one the note names, that rule must use the named form `(add @derive(Debug) to <Type>)` (DevOps, Minimalism).
