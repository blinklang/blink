[< All Decisions](../DECISIONS.md)

# String `+` Operator — Design Rationale

### Panel Deliberation

This is a re-audit of the DECISIONS.md row "String concatenation via `+`" ("Rejected. Use interpolation or `.concat()`", 5-0). The old five-seat panel left no decision file. The spec gave three reasons: `+` "encourages O(n²) loops, creates ambiguity with numeric `+`, and violates Principle 2 when interpolation already exists". The re-audit ticket asked: does the rejection prevent a bug class? If not, allow `+` on `Str`.

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in four phases. Quoted text is each panelist's own words. Each quote is a whole paragraph or list item of the panel record.

Options:

- Q1: **KEEP** the rejection; **ADD-impl** (`Str + Str` through a sealed `impl Add for Str`, `Str.concat()` removed); **BUILTIN-plus** (`Str + Str` as a built-in rule outside `Add`).
- Q1r: the reason the spec states if KEEP wins: **R-P2** (Principle 2), **R-Add** (`Add` means numeric addition), **R-law** (R-Add plus a written `Add` law in §3.6).
- Q2a: `s += t` on `Str` gives E0521; E0521 goes into ERROR_CATALOG.md and §2.19; the O(n²) and "ambiguity" reasons go. Q2b: one E0521 per `+` chain. Q2c: **F-allstr** (machine-applicable only when every operand is `Str`) or **F-adjacent** (machine-applicable when no two non-`Str` operands are adjacent).
- Q3: a warning for a `Str` that grows in a loop: **L-here** or **L-ticket**.

#### Phase A — Independent proposals

Sys, web and aiml proposed `+` through a sealed `Add` impl. PLT, devops and min proposed to keep the rejection. All six found that the O(n²) reason does not hold and that the "ambiguity" reason needs implicit conversion, which Blink does not have.

- **Systems:**

> 1. **O(n^2) loops.** Not prevented. `s = s.concat(x)` in a loop has the same cost as `s += x`, and lib/std/io_read.bl:23,36 and src/build_fs.bl:365 already do it. The rejection moves the O(n^2) shape to a different spelling; it does not remove it.
>
> So, by the ticket's own rule, the rejection does not earn its keep. My seat accepts `+` on Str if the cost stays the same as `concat` or better, and if generic numeric code cannot pick it up by accident.

- **Web/Scripting:**

> So: the ban prevents no bug class that strict typing does not already prevent. By the ticket's own principle, `+` on Str should go in.

- **PLT:**

>    Numeric `Add` on every built-in carrier is commutative (`a + b == b + a`; the spec's own prop test at 02_syntax.md:1838 checks it). Str concatenation is associative with an identity (a monoid) but **not commutative**. If `Str` implements `Add`, every generic body bounded by `T: Add` that relies on commutativity (reordering a reduction, `x + y == y + x` in a test, a parallel sum that combines partials out of order) silently takes strings and gives a wrong result. No diagnostic fires, because the bound is satisfied. **That is a real, if narrow, bug class: law violation through a generic bound.** Haskell keeps `(<>)` (Semigroup) apart from `(+)` (Num) for this reason. OCaml uses `^`. Rust lets `String: Add<&str>` and pays with an asymmetric, surprising surface (`String + &str` compiles, `&str + &str` does not).
>
> So: the ban stops one bug class (point 3). That bug class exists only if `+` on Str goes through `Add`. A non-trait `+` on Str (plt-2) would not cause it. So I give two proposals, and I vote for plt-1.
>
> I oppose any form that makes `Str: Add`.

- **DevOps/Tooling:**

> So by the ticket's own test, the rule prevents no bug class. But "match LLM priors" has a cheaper tooling answer than a new operator meaning: make the first wrong draft repair itself in one `blink fix` step, with zero prose reading. Both proposals below follow from that.
>
> The rule prevents no bug class the type system does not already prevent; its case rests on Principle 2. I prefer devops-1: keep the one way, and make the wrong first draft cost one `blink fix` step. devops-1(a), (b), (d) and (e) are worth doing whatever the vote on the operator. If the panel opens `+`, take devops-2 whole: `Str + Str` only, remove `.concat()` on Str, and a build-up lint that covers every spelling.

- **AI/ML:**

> Vote intent: aiml-1 (+ aiml-3 as a follow-up). The ban fails the ticket's own test: none of the three reasons is a bug class that `+` would bring in and the ban keeps out.

- **Minimalism:**

> So I will not defend the ban as bug prevention. I defend it as surface that we do not need. The ticket's principle ("match priors unless it prevents a bug") is not in the spec. Principle 2 is (01_philosophy.md:32). When they disagree, the written principle wins until a panel changes it.
>
> min-1. The ban stays, its stated reason gets fixed, and E0521 becomes a precise, machine-applicable fix that also covers `+=`. Oppose any option that adds `+` and keeps `.concat()`.

#### Phase B — Debate highlights

- **Web withdrew web-2** (`+` with `.concat()` kept):

> Principle 2 counts forms. ADD-impl with `.concat()` removed keeps the count at four: interpolation, `+`, `.join()`, StringBuilder. It swaps the form nobody guesses for the form everybody guesses. min-2 says this too. So Principle 2 does not decide between KEEP and web-1. It only rules out web-2 and sys-1's "keep `.concat()`" line. **I withdraw web-2.** I oppose any outcome that adds `+` and keeps `Str.concat`. I disagree with sys-1:42 that removal is "out of scope". If removal is a separate ticket, it gets deferred and we live with two spellings.

- **Systems withdrew sys-1** (the trait route):

> **I withdraw ADD-impl (sys-1's trait route). plt's objection holds, and it holds on systems grounds too.**
>
> From my seat the problem is cost, not only laws. Today, a body monomorphized under `T: Add` is one machine add per `+`, with no allocation. With `Str: Add`, the same body, unchanged, monomorphizes to an allocation plus two `memcpy` per `+`. The cost of generic code would then depend on which instance the caller picks, and the bound would no longer tell the reader. That is the "abstraction that hides cost" my seat exists to reject. plt's commutativity point is the same thing in law form. Concession to plt and min.

- **Every option that adds `+` removes `.concat()`:**

> **PLT:** Oppose web-2 and sys-1:43 (keep both). Two spellings for one binary operation breaks DECISIONS.md:471 in the same way `List.chain` did, and that row was 6-0 only weeks ago. If `+` comes in, `.concat()` on Str goes out by the 3-step dance (web-1, aiml-1, min-2, devops-2). The Bytes asymmetry (`Bytes.concat` stays) is a real cost of the "+" branch, and the decision file should record it.
>
> **DevOps:** **The `.concat()` variation.** If `+` opens, `.concat()` on Str must go in the same change. I oppose web-2 and sys-1's "keep `.concat()`". Two spellings for one operation break DECISIONS.md:471, which this panel held days ago. The migration cost (about 5,500 sites) is less than it looks: `a.concat(b)` → `a + b` is an exact rewrite, so a removed-method row (03_types.md:194) with a machine fix lets `blink fix` do the whole migration. The cost is the 3-step bootstrap dance, not hand edits.
>
> **Minimalism:** **Oppose any option that adds `+` and keeps `Str.concat()` (web-2, sys-1:43).** That takes us from four string-building forms to five, against DECISIONS.md:471, which this panel applied to List days ago. sys-1 calls the migration "out of scope". It is not out of scope: it is the cost of the change, and an option that leaves it out has not been costed. If the cost is too high, that counts against `+`, not for keeping two spellings.
>
> **AI/ML:** Remove it in the same change (3-step dance). I oppose web-2 and sys-1's "keep `.concat()`": two spellings for one two-string join is the exact duplicate DECISIONS.md:471 removed for List, and it gives an LLM a new decision point with no gain. sys-1's point that `Bytes` shares the name is not a reason to keep it on Str: `Bytes.concat` stays as the Bytes form, and Str and Bytes already differ (no interpolation for Bytes). `Bytes + Bytes` is out of scope here.

- **PLT's objection to `impl Add for Str`, as DevOps restated it, and PLT's own narrowing of it:**

> **plt's objection to ADD-impl holds, and it answers the ticket's own test.** In Phase A, all six seats said the ban prevents no bug class. plt found one: after `impl Add for Str`, a generic body bounded by `T: Add` that relies on `a + b == b + a` accepts Str and gives a wrong result, with no diagnostic. The spec writes that law as a test (02_syntax.md:1836-1840, `test "add is commutative"`). The E0306 explain text (src/diagnostics.bl:1374) teaches "a bounded `T` can only ever be a numeric type" by using `sum("a", "b")` as the rejected call. Under ADD-impl that example stops being true, and so does the explain text. From my seat, a diagnostic that teaches a rule the language no longer has is a defect, and an LLM that learns from `blink explain` learns the wrong rule. sys-1 and web-1 close the `Sum` route by giving Str no `Zero`. That fixes one generic, not the law, and it is a rule an LLM must remember ("Str is Add but not Zero").
>
> 1. **My commutativity argument is weaker than I wrote it.** The spec states laws for `Eq`, `Ord` and `Hash` (03_types.md §3.6, e.g. :81, :852), but it states **no law for `Add`**. My objection rests on a law that the spec only assumes (the prop test at 02_syntax.md:1838 tests a user `add` fn, not the trait). And the repo has little generic `Add` code: 5 files in lib/tests/examples have a `T: Add` bound, none in lib/std. So web-1:144 is right that the practical bug rate through `T: Add` is low. I no longer call `impl Add for Str` a soundness problem. It is type-safe. It changes what `Add` means. That is a design cost, not a bug.

- **DevOps's two-E0521 probe:**

> gen1 reports **two** E0521, one at each `+` (columns 23 and 27), each with the same prose help. A chain of k `+` gives k-1 copies of one mistake. The spec text must require **one** E0521 per maximal `+` chain, with the span over the full chain and one fix.

#### Phase C — Final vote

| Question | Result |
|---|---|
| Q1 | KEEP 4-2 (web, aiml: ADD-impl) → Phase D |
| Q1r | R-Add 6-0; R-P2 4-2 (web, aiml do not pick) → Phase D; R-law 3-3 (plt, devops, aiml yes; sys, web, min no) → Phase D |
| Q2a | yes 6-0 |
| Q2b | yes 6-0 |
| Q2c | F-allstr 5-1 (web: F-adjacent) |
| Q3 | L-ticket 5-1 (sys: L-here) |

Each seat's vote, reasoning and concern:

**Q1 — `+` on `Str`**

- **Systems:**

> **Vote:** KEEP
>
> **Reasoning:** `a + b`, `a.concat(b)` and `"{a}{b}"` all lower to one allocation of `la + lb` (bootstrap/runtime_core.h:3055), so opening `+` buys no runtime gain. ADD-impl makes a `T: Add` body allocate or not depending on the instance the caller picks, and the bound no longer shows the cost. BUILTIN-plus avoids that, but adds a permanent non-trait operator case to the IR, the checker and the LSP for zero hardware benefit. With a machine fix, the LLM's `+` chain becomes one interpolation, which is the cheapest form.
>
> **Concern:** If the fix stays weak (prose only, or one error per `+`), KEEP keeps costing round trips and the ticket comes back. Q2 has to land with it.

- **Web/Scripting:**

> **Vote:** ADD-impl
>
> **Reasoning:** Every JS, Python, Go, Kotlin, and Swift dev writes `a + b` on strings first, and all six seats agree the ban stops neither the slow loop nor the coercion bug. ADD-impl with `.concat()` removed keeps four ways to build a string. It swaps the form nobody guesses for the form everybody guesses, and keeps the one rule "every operator is a trait". I prefer it to BUILTIN-plus because "`+` works on Str but `T: Add` rejects Str" is a question users will ask, and its answer is a special case.
>
> **Concern:** If KEEP wins, every new user's first string join fails to compile on day one. A machine fix makes that one round trip, but a person in an editor still pays it and reads it as Blink being stubborn.

- **PLT:**

> **Vote:** KEEP
>
> **Reasoning:** `Add` today has one meaning, the arithmetic of the built-in numerics, and the spec and tools rely on it (E0306 explain at src/diagnostics.bl:1374; `trait Doubler: Add` at 03_types.md:3772-3787). ADD-impl makes that bound "a number, or Str", which is a list of types and not a category, and it makes Str the one exception to "no operator overloading beyond numeric traits" (01_philosophy.md:106). BUILTIN-plus keeps `Add` clean but breaks "every operator desugars to a trait call" (DECISIONS.md:107). The cost of KEEP is a compile error that always fires, never a wrong program, and Q2 makes the repair one tool step.
>
> **Concern:** If KEEP wins on a narrow vote, the next audit will reopen it unless the spec states the reason as a written rule (Q1r) and not as the old three claims.

- **DevOps/Tooling:**

> **Vote:** KEEP
>
> **Reasoning:** The rejection fails loud at compile time, every time, and Q2 makes the repair one `blink fix` run. ADD-impl makes the E0306 explain text and the `T: Add` rule false, and BUILTIN-plus gives `+` a second typing case that the checker, the under-determined error and LSP hover/go-to-definition must all special-case. Either `+` option puts its cost on the tools for every user, and the gain is one saved round trip that Q2 already makes cheap.
>
> **Concern:** The fix only pays off if Q2 ships with Q1. If the ban stays and the diagnostic work slips, we keep the worst state: an error every LLM hits on its first draft, with a prose help.

- **AI/ML:**

> **Vote:** ADD-impl
>
> **Reasoning:** `a + b` on two strings is the first form an LLM writes in every major training language, and no seat found a bug class that the ban stops in lib/std or src. The commutativity concern has no instance in the repo and no law in the spec. `Sum` stays closed because Str gets no `Zero`. ADD-impl keeps one rule an AI can learn from the spec alone ("every operator is a trait call"). BUILTIN-plus adds an exception: `+` compiles on Str, but `T: Add` rejects Str. With `.concat()` removed, the count of string-building forms stays at four.
>
> **Concern:** The overlap between `+` and interpolation for all-Str parts is a new style decision point. llms.md and §3.6 must give a one-line rule ("interpolation to embed non-Str values, `+` to join Str values"), or generated code will mix the two forms at random.

- **Minimalism:**

> **Vote:** KEEP
>
> **Reasoning:** Both `+` options add a form or an exception, and they replace `.concat()` only by migrating ~5,500 sites. KEEP adds nothing. The cost of the LLM prior is one compile error that the tool fixes. ADD-impl changes what every `T: Add` bound means, and BUILTIN-plus breaks the one-line rule that each operator desugars to a trait. KEEP holds the rules the spec has today: operators are numeric, and there is one way to build a string.
>
> **Concern:** If the Q2 fix ships late or with gaps, the ban costs every first draft a round trip and gets no payback, and this ticket opens again.

**Q1r — the reason, if KEEP wins**

- **Systems:**

> **Vote:** R-Add and R-P2
>
> **Reasoning:** R-Add is the reason that is true today and that the compiler already relies on (E0305/E0306 explain text, 03_types.md:3770-3790). It also keeps the cost of `+` predictable: one machine op for every type that admits it. R-P2 is the surface reason and is honest as stated. I do not pick R-law. Writing laws into §3.6 is a larger spec change, and "associative for Int" interacts with overflow traps, which needs its own careful wording.
>
> **Concern:** R-Add alone reads as circular ("Add is numeric because it is sealed to numerics") unless the text says why concatenation is a different operation.

- **Web/Scripting:**

> **Vote:** R-Add
>
> **Reasoning:** If the ban stays, the spec must give a reason that is true and that a user can check. "`Add` means numeric addition; `T: Add` admits only numeric types" is true today, and it explains the ban in one line. R-P2 is weak as a reason, because `+` could replace `.concat()` with no change in the count of forms. R-law adds formal text that most readers will skip; I do not object to it, but it is not needed to justify the ban.
>
> **Concern:** R-Add makes "`+` is numeric only" a rule. Later requests for `+` on other non-numeric types will cite it. That is fine, but the panel must apply it the same way each time.

- **PLT:**

> **Vote:** R-law and R-P2 (R-law includes R-Add)
>
> **Reasoning:** A reason should follow from a rule the spec writes down, so a reader can check it. Today the spec gives laws for `Eq`, `Ord` and `Hash` but none for `Add`, so "Str is not `Add`" rests on an unwritten assumption; R-law closes that gap. R-P2 is the surface reason and is true on its own; together they say what the operator means and why a fifth form is not wanted.
>
> **Concern:** The law text must hold for every built-in carrier as the spec defines it (wrapping Int, IEEE Float with NaN), or the law itself becomes a new latent defect.

- **DevOps/Tooling:**

> **Vote:** R-law (which includes R-Add), and R-P2
>
> **Reasoning:** A diagnostic's `note:` and `blink explain` text must cite a rule written in the spec, not a rationale. R-law gives E0521 and E0306 one written sentence to point to ("`Add` is numeric addition, with these laws"). R-P2 is true too, and it is the reason a reader asks about first ("why not just `+`?"), so the section should state it beside the typed reason.
>
> **Concern:** The law text for Float (IEEE 754) must be exact, or a later audit opens a ticket on the wording of the law instead of on strings.

- **AI/ML:**

> **Vote:** R-law (with R-Add in it)
>
> **Reasoning:** An AI learns a rule best when the spec states it and the error message cites it. "`T: Add` admits only numeric types, and `Add` is commutative" is a typed rule that a model can apply to new cases (Bytes, List, user types). R-P2 alone reads as taste, and the next audit will open it again. R-law also makes the E0306 and E0305 explain texts true by a written rule, not by accident.
>
> **Concern:** If the law text says "associative for Int" but stays silent for the sized ints, models will guess. The text must name each carrier or use one plain category ("every built-in integer type").

- **Minimalism:**

> **Vote:** R-P2 + R-Add
>
> **Reasoning:** These are the two reasons that hold, and both rest on rules already written (01_philosophy.md:32, 106; DECISIONS.md:56, 107-108). R-law adds new normative text (a law table, Float under IEEE 754) that the reason does not need. Stating laws for every carrier is its own spec change, and it should come with its own case. If a law statement is wanted, file it as its own ticket.
>
> **Concern:** Without R-law, a later panel may read "`T: Add` admits only numbers" as a list of types rather than a law, and admit a type with no laws.

**Q2a — the agreed block**

- **Systems:**

> **Vote:** yes
>
> **Reasoning:** `s += t` currently falls to a generic TypeError with no help. One mistake should give one diagnostic, and the false O(n^2) claim must go.
>
> **Concern:** none beyond test coverage for the `+=` path.

- **Web/Scripting:**

> **Vote:** yes
>
> **Reasoning:** `s += t` is the most common shape in a loop, and today it gets the worst message. One code, in the catalog and the spec, is what a user searches for. Removing reasons that are not true stops the next audit from opening this ticket again.
>
> **Concern:** None from my seat.

- **PLT:**

> **Vote:** yes
>
> **Reasoning:** One mistake should get one diagnostic code, and `s += t` is sugar for `s = s + t` (02_syntax.md:1808), so it must report the same E0521. The removed reasons are false as written. The code must be in the catalog and the spec so a reader can find it.
>
> **Concern:** The `+=` path lives in a different branch of the checker; a fix that covers only `+=` on a bare local and misses a field place (`s.f += t`) would leave the split in place.

- **DevOps/Tooling:**

> **Vote:** yes
>
> **Reasoning:** One mistake gets one diagnostic code, and that code is in the catalog and the spec. Today `s += t` gets a generic TypeError with no help, and E0521 is in no document a reader or an LLM retrieves.
>
> **Concern:** The tests that pin the TypeError text for `s += t` must move to E0521 in the same change, or the corpus pins the old path.

- **AI/ML:**

> **Vote:** yes
>
> **Reasoning:** One code for one mistake (`a + b` and `s += t`) and an entry in the catalog cut a retrieval step and a misread error for an LLM. Removing false reasons from the spec stops models from learning wrong lessons from it.
>
> **Concern:** The catalog entry must change its meaning if ADD-impl wins (E0521 then covers mixed operands only). The text must not keep "Str does not implement Add".

- **Minimalism:**

> **Vote:** yes
>
> **Reasoning:** One diagnostic for one mistake, a catalog entry for it, and no false reasons in the spec. This removes defects and adds no surface.
>
> **Concern:** The rewrite of 02_syntax.md:1825 must not bring a new unproven claim in place of the old ones.

**Q2b — one diagnostic per chain**

- **Systems:**

> **Vote:** yes
>
> **Reasoning:** One fix over the whole chain yields one interpolation, which is one buffer. Per-`+` fixes would rewrite to nested forms with intermediate strings, and the second error after applying the first fix is noise.
>
> **Concern:** The chain span must stop at parentheses and at non-`+` operators, or the fix may swallow a numeric sub-expression.

- **Web/Scripting:**

> **Vote:** yes
>
> **Reasoning:** Two errors for `"total: " + a + b` read as two mistakes when there is one. One error over the full chain, with one fix, is what a user expects.
>
> **Concern:** The chain span must stop at the edge of the `+` chain (for example, at a call argument or a parenthesis), or the fix rewrites more than the user wrote.

- **PLT:**

> **Vote:** yes
>
> **Reasoning:** The chain is one ill-typed expression with one repair (one interpolation), so one diagnostic over the full span matches the fix's span. Two errors for one mistake give two overlapping fixes that a tool cannot apply both of.
>
> **Concern:** "The chain" needs an exact definition (the maximal left-associated `+` tree that contains a Str operand, stopping at parentheses and at any non-`+` operator), or the span differs between checker and fixer.

- **DevOps/Tooling:**

> **Vote:** yes
>
> **Reasoning:** gen1 gives k-1 copies of one mistake for a chain of k operands. Copies are noise in `blink check`, and two fixes with overlapping spans are a conflict, so `blink fix` (06_tooling.md:307) would apply neither. One diagnostic with one span over the chain is what makes the machine fix work at all.
>
> **Concern:** The "maximal chain" must stop at parentheses and at operands that are not `+`, or the span takes in a numeric subexpression like `(a + b)` and the fix quotes it wrongly.

- **AI/ML:**

> **Vote:** yes
>
> **Reasoning:** Two E0521 errors for `"total: " + a + b` give an agent two overlapping fixes, and if it applies both it corrupts the line. One diagnostic over the full chain gives one exact replacement, which applies in one step.
>
> **Concern:** The chain span must stop at the precedence boundary (for example `n * 2 + s`) or the fix will swallow an operand that is not part of the chain.

- **Minimalism:**

> **Vote:** yes
>
> **Reasoning:** Two E0521 for `"total: " + a + b` report one mistake twice, and two fixes over one chain conflict. One span with one fix is less output, and the result is the same edit.
>
> **Concern:** The chain span must stop at the edge of the `+` tree (parentheses, a call argument), or the fix rewrites code the author did not write as part of the chain.

**Q2c — when the fix is machine-applicable**

- **Systems:**

> **Vote:** F-allstr
>
> **Reasoning:** For a non-Str operand, `"{n}"` inserts a `display()` call. For a user type that runs user `Display` code the author did not write at that site, and a tool should not add a call to user code on its own. The suggestion still carries exact text in `--json`, so an agent applies it in one step.
>
> **Concern:** Agents that apply only machine-applicable fixes will leave mixed chains unfixed. The suggestion text must be exact and must not need edits.

- **Web/Scripting:**

> **Vote:** F-adjacent
>
> **Reasoning:** For `"id: " + n`, the user clearly wants `n` in the text, and `"id: {n}"` is the only meaning that makes sense. Making the user approve that by hand is friction with no safety gain. The only real ambiguity is two non-Str operands next to each other (`"a" + 1 + 2`: "a12" or "a3"). F-adjacent makes exactly those cases a suggestion that shows both groupings.
>
> **Concern:** I expect F-allstr to win. Then the most common mixed case (`"count: " + n`) needs a manual step in `blink fix` and in agent loops, so an LLM's most common draft is not repaired automatically.

- **PLT:**

> **Vote:** F-allstr
>
> **Reasoning:** When every operand is Str, the rewrite to interpolation is exact: `Str` display is the identity and holes run left to right (decisions/argument-evaluation-order.md). When any operand is not Str, the rewrite inserts a `Display` call the author never wrote; for a user type that is user code with the `Fmt` effect, so the fix changes which code runs. The rule "a machine fix never adds a call" is one sentence and easy to check; F-adjacent's grouping rule is not.
>
> **Concern:** Literal text spliced into the interpolation must escape `{` and `}` (and handle raw `#"..."#` literals), or the "exact" fix changes the string.

- **DevOps/Tooling:**

> **Vote:** F-allstr
>
> **Reasoning:** A tool must not choose a Str conversion for the author. With all-Str operands, the rewrite is exact. With any non-Str operand, the tool picks the `Display` text, and the author may have meant something else (`"total: " + a + b` is the JS bug). F-adjacent removes the worst case, but it still has the fixer write conversions, and it adds a placement rule that users and LLMs must learn to predict when `blink fix` acts. One rule (Str-only operands) is easy to predict.
>
> **Concern:** Mixed chains are a common LLM draft, so a large share of E0521 still needs one step that a person or an agent takes. The `--json` diagnostic must carry the exact replacement text, so an agent can apply it without reasoning.

- **AI/ML:**

> **Vote:** F-allstr
>
> **Reasoning:** An agent loop applies the exact `help:` replacement text in the same step whether `blink fix` applies it or not, so the round-trip cost is the same for both options. F-allstr is one simple rule to learn. F-adjacent shows two groupings, so the model has a choice to make.
>
> **Concern:** If the suggestion carries prose and not the exact replacement string in the `--json` output, agents lose the step that F-allstr counts on.

- **Minimalism:**

> **Vote:** F-allstr
>
> **Reasoning:** One rule with no edge cases: all-Str chains keep their meaning under the rewrite, because Str's Display is the identity and holes keep left-to-right order. F-adjacent adds a grouping analysis and a two-grouping display, so the rule is more complex. It also still writes a Display call for the non-Str operands that the author did not ask for, and that call fails to compile for a type with no `Display`.
>
> **Concern:** LLM loops that apply only machine fixes will leave `"id: " + n` for a second step. The suggestion text must be exact, so a loop can apply it directly.

**Q3 — loop build-up warning**

- **Systems:**

> **Vote:** L-here
>
> **Reasoning:** With the O(n^2) reason removed from the spec, the lint is the only place the real cost gets named. It covers every spelling, including `.concat()`. The lib/std and src sites it finds (io_read.bl:23,36, build_fs.bl:365) are real quadratic loops and should be fixed with StringBuilder in the same change.
>
> **Concern:** A loose rule gives false positives on short loops and gets silenced across the board. Keep it to loop-carried Str locals assigned from themselves.

- **Web/Scripting:**

> **Vote:** L-ticket
>
> **Reasoning:** The warning does not depend on the Q1 result. On day one it fires on lib/std and src, and also on short loops where a StringBuilder adds code for no gain. Noisy default warnings teach users to ignore warnings. It needs its own design pass on when it fires and its default level.
>
> **Concern:** If it is filed as its own ticket, it can stay in the backlog, and the slow-loop reason, now removed from the spec, gets no tool to replace it.

- **PLT:**

> **Vote:** L-ticket
>
> **Reasoning:** The lint targets the real cost and is right to cover every spelling, but it needs its own typed definition (loop-carried local `x: Str`, assigned from an expression whose leftmost operand is `x`, read after the loop) and its own suppression rule. That is a feature with its own design questions, not a clause of a ruling about `+`.
>
> **Concern:** As a separate ticket it may sit unshipped, and the lib/std and src sites that grow a Str in a loop stay as they are.

- **DevOps/Tooling:**

> **Vote:** L-ticket
>
> **Reasoning:** A lint's value is its false-positive rate. Its precision rules (loop-carried local, read after the loop, the interpolation form, `@allow` for small loops) are not designed yet, and they need their own tests and corpus sweep. Adding it to this ruling would hold up the Q2 diagnostic work, which matters more. A feature ticket that covers every spelling keeps the point all six seats agreed on.
>
> **Concern:** As a separate ticket it can wait in the backlog for a long time, while the in-tree `x = x.concat(..)` loop sites stay.

- **AI/ML:**

> **Vote:** L-ticket
>
> **Reasoning:** The lint is the right tool for the O(n^2) bug class, but its precision rules (loop-carried locals, read after the loop, nested loops) need their own design and tests. It must not ride on this ruling. As a separate ticket, it also gets one exact help form (StringBuilder) and not a list of choices.
>
> **Concern:** A separate ticket can sit at low priority for a long time while lib/std keeps the quadratic sites at io_read.bl:23,36 and build_fs.bl:365. The moderator should file the ticket at once and link it to this ruling.

- **Minimalism:**

> **Vote:** L-ticket
>
> **Reasoning:** It is a new lint, not part of this gap. It needs its own design for false positives on short bounded loops and for how to silence it. Voting it in here without that design is how surface grows unexamined.
>
> **Concern:** A separate ticket can sit in the backlog for ever, which leaves the real O(n²) shape in lib/std/io_read.bl with no check.

#### Phase D — Round 2

Phase D covered D1 (KEEP or ADD-impl), D2 (state Principle 2 as a reason) and D3 (state the `Add` law). In step 1, four seats raised one fact: Int `+` is checked, so it is not associative.

> **Systems:** The spec does not define Int as wrapping. sections/03_types.md:1460-1462: "Arithmetic overflow is checked by default. An operation that exceeds the type's range panics at runtime." `wrapping_add` is a separate method. Under checked arithmetic, `+` on Int is **not associative**: `(MAX + 1) + -1` panics, `MAX + (1 + -1)` gives `MAX`. Which panic occurs is observable behavior (02_syntax.md:2894), so the compiler may not reassociate. So the R-law text on the ballot ("associative for Int") would be a false law, the exact latent defect plt warns about.
>
> **PLT:** My Q1r concern said the law must hold for "wrapping Int". That is wrong. Blink integer arithmetic is **checked**: overflow panics (03_types.md:1460-1466); wrapping is opt-in through `wrapping_add` (:1552). This matters for D3, below.
>
> **Web:** New evidence: the law as plt-1/B1 wrote it is not true for Blink today. 03_types.md:1462: "Arithmetic overflow is checked by default. An operation that exceeds the type's range panics at runtime." So Int addition is **not** associative as a total operation: `(Int.MAX + 1) + -1` panics, and `Int.MAX + (1 + -1)` gives `Int.MAX`. plt's own concern says "wrapping Int". Blink does not wrap; it panics. sys saw this in C ("'associative for Int' interacts with overflow traps"). aiml raises the sized-int case.
>
> **DevOps:** Int is not wrapping. 03_types.md:1462: "Arithmetic overflow is checked by default. An operation that exceeds the type's range panics at runtime". So associativity is **false** as a total law for every built-in integer: with `a = Int.MAX`, `b = 1`, `c = -1`, `(a + b) + c` panics and `a + (b + c)` returns `Int.MAX`. Float is not associative under IEEE 754 either. A law table that says "associative for Int" puts a false statement in the spec, and a prop test written from it fails.

AI/ML's D2 wording, which won:

> "Interpolation already joins any number of values, Str or not. A `+` on Str would be a second spelling for the same join (Principle 2)."

Web had asked for a different wording:

> If R-P2 is stated, I ask for this wording: "Str has one form to join two strings, `.concat()`; `+` would duplicate it (Principle 2)." That is true and does not claim more than it can prove.

| Item | Result |
|---|---|
| D1 | KEEP 5-1 (web: ADD-impl). All six: the ruling states that Q2a-c land in the same change as the spec text |
| D2 | yes 6-0, with the overlap wording |
| D3 | C-only 5-1 (web: no) |

AI/ML moved D1 from ADD-impl to KEEP. PLT and Systems moved D3 from no to C-only. Web held ADD-impl on D1 and no on D3. Each seat's step 2 vote:

**D1 — KEEP or ADD-impl**

- **Systems:**

> **Vote:** KEEP. The ruling must state the condition: Q2a, Q2b and Q2c land in the same change as the spec text, not in a later ticket.
>
> **Reasoning:** Every way of joining strings costs the same single allocation (bootstrap/runtime_core.h:3055), so `+` buys nothing at run time. ADD-impl puts an allocation behind every `T: Add` body for one instance. web and aiml say `T: Display` and `T: Hash` already vary in cost. That is true, but no one reads those bounds as "one machine op", while every reader reads `+` that way. The Q2 fix rewrites a `+` chain to one interpolation, which builds the result in one buffer, so KEEP steers code to the cheapest form.
>
> **Concern:** If the Q2 work slips, KEEP is the state all six seats called the worst. So the condition belongs in the ruling.

- **Web/Scripting:**

> **Vote:** ADD-impl
>
> **Reasoning:** No seat found a bug class that the ban stops, and the ticket's rule is "match priors unless the deviation prevents a bug class". KEEP stands on surface rules (numeric-only operators, one way to join), not on a bug. devops's point that the LSP shows E0521 as a squiggle with a one-key fix lowers the cost a lot, and I grant it. But it is still a rule that every new user from Python, JS, Go or Kotlin meets on day one, and the spec has to defend it each time. **Whichever option wins, the ruling must state as a condition that Q2a/Q2b/Q2c land in the same change as the spec text.** Five of six seats asked for this in step 1.
>
> **Concern:** KEEP wins and the Q2 work is filed as a later chore. Then we keep the state all six seats called the worst: an error on every first draft, with a prose help, and a second, worse error for `+=`.

- **PLT:**

> **Vote:** KEEP. Yes, the ruling must state the condition: the spec text and the Q2a/Q2b/Q2c diagnostic work land in the same change.
>
> **Reasoning:** KEEP holds two rules the spec already writes: operators are numeric only (01_philosophy.md:106, DECISIONS.md:56), and one way to join strings. ADD-impl keeps "every operator is a trait call", but it makes `T: Add` mean "a number, or Str". Every generic `Add` bound, and the E0305/E0306 explain texts, would then carry that exception. KEEP's cost is one compile error with an exact repair. Five seats name Q2 as what makes that cost small, so the ruling must tie Q2 to it, not leave it as a later chore.
>
> **Concern:** If the same-change condition is written but the Q2 fix only covers `+` on a bare local (not `s.f += t`, not chains in nested expressions), the ban keeps costing round trips and the ticket comes back.

- **DevOps/Tooling:**

> **Vote:** KEEP. And yes, the ruling must state the condition: the spec text for Q2a, Q2b and Q2c, and the E0521 changes (one diagnostic per chain, the machine fix, `+=` routed to E0521, the catalog entry), land in the same change as the KEEP text.
>
> **Reasoning:** With the Q2 package, the LLM prior costs one LSP code action or one `blink fix` step, and `T: Add`, the E0306 explain text and the "operators are numeric" rule stay true. ADD-impl needs a style lint to choose between `+` and interpolation for all-Str joins, so it brings a diagnostic on the first draft back as a warning. If KEEP lands without Q2, all six seats call the result the worst state on the table, so the condition belongs in the ruling, not in a follow-up.
>
> **Concern:** The mixed case (`"count: " + n`) stays a manual step under F-allstr. If the suggestion text in `--json` is not exact, agents will guess the conversion, and the web seat's day-one cost stays high for that case.

- **AI/ML:**

> **Vote:** KEEP (changed from ADD-impl). The ruling must state the condition: Q2a, Q2b and Q2c land in the same change as the spec text, not as a later chore.
>
> **Reasoning:** devops answered the concern I raised against my own vote. Under ADD-impl, `a + " " + b` and `"{a} {b}"` both compile, so the corpus mixes the two forms unless a lint picks one, and that lint fires a warning on every LLM's first draft. ADD-impl moves the round trip; it does not remove it. Under KEEP with Q2, the LLM's `+` chain gets one E0521 with an exact replacement, applied by the tool for all-Str chains. That is one mechanical step for an agent, and it leaves one form in the corpus for models to learn from. sys's point also holds: chain fusion is not in ADD-impl as balloted, so the form an LLM writes would be the slower one.
>
> **Concern:** The mixed case (`"count: " + n`) stays a suggestion under F-allstr. If the `--json` output does not carry the exact replacement string, agents fall back to reading prose and the ban costs a full round trip again.

- **Minimalism:**

> **Vote:** KEEP. The ruling must state the condition: Q2a, Q2b and Q2c land in the same change as the spec text, not as a later chore.
>
> **Reasoning:** KEEP adds no surface and holds both written rules: operators are numeric only (01_philosophy.md:106), and one way to build a string. ADD-impl changes the first rule and needs a ~5,500-site migration to keep the second. It also leaves `+` and interpolation as two forms that both compile for every all-Str chain (aiml's own concern; devops shows that enforcing one of them takes a new lint). Every seat named the same risk, KEEP without the fix. So the condition goes in the ruling, where the next audit can check it.
>
> **Concern:** The E0521 chain fix (span detection, literal splicing with `\{` escapes, raw strings) is real work. If it lands only in part, KEEP looks like a choice that was made and then left to sit.

**D2 — state Principle 2 as a reason**

- **Systems:**

> **Vote:** yes, with aiml's overlap wording ("Interpolation already joins any number of values, Str or not. A `+` on Str would be a second spelling for the same join (Principle 2).").
>
> **Reasoning:** The overlap wording is true under KEEP and under any swap, so no later audit can reopen it by counting forms. web's wording ("one binary-join form exists") is not exact: under KEEP, `.concat()` and `"{a}{b}"` both join two Str values today.
>
> **Concern:** The sentence must not say "fifth form" or count forms, or web's objection comes back.

- **Web/Scripting:**

> **Vote:** yes, with the overlap wording (aiml D): "Interpolation already joins any number of values, Str or not. A `+` on Str would be a second spelling for the same join (Principle 2)."
>
> **Reasoning:** This wording is true, and a reader can check it. It answers the first question a newcomer asks ("why not just `+`?"). It does not count "forms" or say "fifth", which is the claim I showed to be false once `.concat()` could go. My own wording ("one binary-join form exists") is also true, but aiml's names the real overlap, interpolation, so I take it.
>
> **Concern:** If the decision file or the spec keeps min-1's "fifth way to build a string" text, the next audit finds it false and opens this ticket again.

- **PLT:**

> **Vote:** yes, with the overlap wording (aiml D): "Interpolation already joins any number of values, Str or not. A `+` on Str would be a second spelling for the same join (Principle 2)."
>
> **Reasoning:** web is right that "a fifth way" is false once `.concat()` would go, and a reason that a later audit can show false brings the ticket back. The overlap wording is true under every option: `a + " " + b` and `"{a} {b}"` would both compile for the same all-Str join. It states the decision point an author would face, and that is what Principle 2 is about. I prefer it to web's "one binary-join form exists" wording, which rests on `.concat()` and so fails the same check.
>
> **Concern:** None from my seat beyond keeping it as the second reason, after R-Add, so the section does not read as taste alone.

- **DevOps/Tooling:**

> **Vote:** yes, with the overlap wording (aiml D): "Interpolation already joins any number of values, Str or not. A `+` on Str would be a second spelling for the same join (Principle 2)."
>
> **Reasoning:** The overlap is the true Principle 2 cost, and it holds even if `.concat()` goes. web's wording ("one binary-join form exists; `+` would duplicate it") rests on `.concat()`, and every `+` option removes `.concat()`, so the next audit can answer that wording with "then remove `.concat()`". The overlap wording also matches the E0521 fix, which rewrites a `+` chain to interpolation: the reason and the repair say the same thing.
>
> **Concern:** The sentence must not count forms ("fifth way"), or it gives the next auditor the same opening the old 02_syntax.md:1825 text did.

- **AI/ML:**

> **Vote:** yes, with the overlap wording: "Interpolation already joins any number of values, Str or not; `+` on Str would be a second spelling for the same join (Principle 2)."
>
> **Reasoning:** The overlap with interpolation is the true Principle 2 cost, and it is the cost that changed my D1 vote. web's wording ("one binary-join form exists; `+` would duplicate it") is true but weaker: it invites the answer "then swap `.concat()` for `+`", which is the case this ticket opened. The overlap wording answers that case as well.
>
> **Concern:** If the text counts forms ("a fifth way"), the next audit will show it is false once `.concat()` could go, and the ticket comes back.

- **Minimalism:**

> **Vote:** yes, with aiml's overlap wording: "Interpolation already joins any number of values, Str or not. A `+` on Str would be a second spelling for the same join (Principle 2)."
>
> **Reasoning:** web is right that "fifth way" is false once `.concat()` is removed, and I withdraw that wording. The true Principle 2 cost is the overlap with interpolation, which remains under every `+` option. I prefer aiml's text to web's ("one binary-join form exists, `.concat()`"), because interpolation also joins two strings. web's text would then claim one form where there are two today.
>
> **Concern:** Under KEEP, `.concat()` and interpolation already overlap for two Str values. A careful reader can turn the same argument on `.concat()`, and that is a fair ticket for another day.

**D3 — the `Add` law**

- **Systems:**

> **Vote:** C-only, on one condition: the NaN clause stays in the sentence (min D: "Every NaN counts as one value").
>
> **Reasoning:** I change from "no" in step 1. My objection was to a false associativity law, and C-only drops it. Commutativity holds as the spec defines arithmetic: checked Int `a + b` panics if and only if `b + a` does, and sized ints behave the same way. Float needs the clause. When both operands are NaN, x86 SSE returns the first operand's payload, so `a + b` and `b + a` can differ in bits. "Every NaN counts as one value" makes the sentence exact. With that, one sentence also fixes the circularity I raised in C. Systems side benefit: a written commutativity law licenses the optimizer to put the operands of `+` in a canonical order, because evaluation order of the operands is still fixed separately (02_syntax.md:2894).
>
> **Concern:** If the NaN clause is dropped in editing, the law is false at the bit level for Float, and a prop test over `to_bits` will find it.

- **Web/Scripting:**

> **Vote:** no
>
> **Reasoning:** The fact the reason needs is plain: `"ab"` is not `"ba"`, so joining strings is not the same kind of operation as addition. That sentence goes in the reason text, as plt D wrote it, and the user needs nothing more. A normative law in §3.6 is a different thing: a spec rule that prop tests and later panels will lean on. The step 1 replies show that its wording is not settled. devops needs "or both panic" and a NaN clause, min needs "every NaN counts as one value", and sys flags NaN payloads. Three seats wrote three versions of one sentence. Give it its own ticket, where it gets one careful pass, with the overflow case as its first test.
>
> **Concern:** C-only wins and the sentence lands with a gap (NaN, the panic case, or "same result" against `==`). Then a user's prop test `a + b == b + a` fails on Float NaN against a law the spec states, and we have a new latent defect in a ruling that was meant to remove false text.

- **PLT:**

> **Vote:** C-only
>
> **Reasoning:** I changed from "no" in step 1. My objection was to associativity, which is false under checked overflow (03_types.md:1462: `(Int.MAX + 1) + -1` panics, `Int.MAX + (1 + -1)` does not) and false for IEEE Float. C-only drops associativity. Commutativity alone holds for every built-in `Add` type: an integer `a + b` overflows if and only if `b + a` does, and IEEE 754 addition is commutative. One true normative sentence is better than prose in the reason text: it makes R-Add follow from a written law, not from the sealed list, and it gives the test for a new type (Bytes, List): concatenation breaks the law, so it is not `Add`.
>
> **Concern:** The sentence must cover the two edge cases exactly, or it becomes the false law I warned about: "give the same result, or both panic" for checked integers, and a NaN clause for Float (the results are both NaN, and the law is about the result, not about `==`, which is false on NaN).

- **DevOps/Tooling:**

> **Vote:** C-only
>
> **Reasoning:** A diagnostic note and `blink explain` should cite a rule the spec writes down. "Joining strings is not commutative" means something only if the spec says that `Add` is. One sentence holds for every carrier under checked overflow and IEEE 754, so it does not have the false-law risk of the associativity table. The text should cover the panic case and NaN, for example: "For every type that implements `Add`, `a + b` and `b + a` give the same result, or both panic; for Float, a NaN on one side means a NaN on the other." Associativity and any law table go to a follow-up ticket.
>
> **Concern:** If the sentence leaves out the panic or NaN clause, a prop test written from it with `assert_eq` fails on Float NaN or overflow. The text must say what "the same result" means for those two cases.

- **AI/ML:**

> **Vote:** C-only
>
> **Reasoning:** The checked-overflow fact (03_types.md:1460-1462) makes associativity false, but it does not touch commutativity: `a + b` panics if and only if `b + a` panics, and IEEE 754 addition is commutative. One sentence holds for every carrier with no list of types, and it is the property concatenation lacks, so the reason is a written rule and not a circle (sys's C concern). An AI can apply that rule to the next type (Bytes, List, Decimal); it cannot apply "sealed to numerics" without a list.
>
> **Concern:** The sentence must say "the same result, or both panic", and must treat every NaN as the same result. Otherwise a model that writes the law as a prop test with `==` will produce a test that fails on NaN.

- **Minimalism:**

> **Vote:** C-only
>
> **Reasoning:** One sentence that holds for every built-in carrier: "`a + b` and `b + a` give the same result, or both panic." That turns R-Add from a list of types into a rule, which answers sys's circularity point. From my seat the main gain is that it also blocks surface growth by rule: a later request for `+` on Bytes or List fails the written law, so it does not reopen a debate. plt's plain-words fact ("`"ab"` is not `"ba"`") explains this one case but binds no future one. The sentence has no associativity claim, so the checked-overflow defect that sys, web and plt found does not apply.
>
> **Concern:** "Same result" for Float must be read as "both NaN" when NaN is involved, not as the same NaN payload or as `==`. The sentence needs that clause, or a prop test written from it fails on NaN.

The panel record states that `==` is false on NaN. The spec says otherwise. Float `==` uses the total order, so `NaN == NaN` is true (sections/03_types.md, Float total order; DECISIONS.md "Float total order re-audit"). Every seat's DV condition was that a prop test `a + b == b + a` must hold on NaN. Under the total order it does, so the spec states the law with `==` and names the total order.

### Final Spec

```blink
let full = first + " " + last   // error[StrPlusUnsupported] (E0521): one error for the whole chain
s += "x"                        // error[StrPlusUnsupported] (E0521)
p.name += t                     // error[StrPlusUnsupported] (E0521)

let full = "{first} {last}"               // interpolation (preferred)
let full = first.concat(" ").concat(last) // .concat() for dynamic cases
s = "{s}{t}"                              // the fix for s += t
```

Locked points:

- `+` stays rejected on `Str`, 5-1 (web dissent). `.concat()` stays.
- Two reasons. (a) `Add` is commutative and joining strings is not, so `Str` is not `Add` (R-Add 6-0; the written law 5-1). (b) Principle 2, in the overlap wording: interpolation already joins any number of values, so `+` on `Str` would be a second spelling for the same join (6-0). The spec does not say "a fifth way".
- §3.6 states one law: `a + b == b + a`, or both panic; for Float, `==` is the total order, so every NaN is equal to every other NaN. The spec states no associativity law: Int `+` is checked and Float `+` rounds.
- `s += t` on a `Str` place is E0521, not `TypeError` (6-0). The O(n²) and "ambiguity" reasons are removed.
- One E0521 per `+` chain (6-0).
- The fix is one interpolated string. It is machine-applicable only when every operand is `Str`; otherwise it is a suggestion with the exact text (5-1, web: F-adjacent).
- The ruling requires the E0521 work of Q2a-c to land in the same change as this spec text (all six seats).
- No loop-growth warning in this ruling (5-1, sys: L-here).

### Amendments

- Replaces the reasons of the DECISIONS.md row "String concatenation via `+`". The result of that row, "Rejected. Use interpolation or `.concat()`", stays.
- Adds the commutativity law of `Add` to sections/03_types.md §3.6.
- Adds E0521 `StrPlusUnsupported` to ERROR_CATALOG.md and sections/02_syntax.md §2.19.

### Implementation notes

Not spec text.

- gen1 emits `StrPlusUnsupported` at src/typecheck.bl ~:23708 once per `+`, with a prose help and no machine-applicable fix. It must emit one diagnostic per chain.
- `s += t` takes the `TypeError` path today. It must reach `StrPlusUnsupported`, for a variable and for a field place.
- The fix must write `{` and `}` of copied `Str` literal text as `\{` and `\}`.
- The explain text at src/diagnostics.bl:1467 cites O(n²) and must change.
- Tests that pin the old behavior: tests/test_typecheck_a_closure_result_is_typed_before_its_expression_reads_it.bl (lines 62-119), tests/test_value_arms_in_literals_and_top_level_lets.bl (line 322), tests/test_arithmetic_on_non_numeric_operands_is_e0300.bl (line 60).

### Open cases and follow-ups

- A warning for a `Str` that grows in a loop (Q3). It needs its own design (0zrf2e).
- A full `Add` law table, and any associativity statement (web, D3).
- The `Sum` impl at sections/03_types.md:~4545 writes `Add[T, Output = T]`, which does not match `trait Add` (b2bs3n).
- The `CannotInferType` "empty construction" note on `fn(a, b) { a + b }` (DevOps's probe) is misleading (mnakqv).
