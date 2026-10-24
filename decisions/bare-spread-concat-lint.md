[< All Decisions](../DECISIONS.md)

# Bare Two-Source Spread Check (W0709) — Design Rationale

Spec ticket: a lint for a bare two-source spread. §3.2.2 *Concatenation* says that two lists join with `a.append(b)`,
and that spread is for a literal with extra elements or for three or more sources. The duplicate-APIs decision
([decisions/duplicate-apis.md](duplicate-apis.md), Q1, 5-1) kept that rule. PLT, DevOps and Minimalism then asked for a
check that flags `[..a, ..b]` and points to `a.append(b)`; without it, both forms would appear for the same job. The
panel had to decide the class, the default level, and whether `blink fix` applies the edit.

## Summary

| Q | Question | Result | Vote |
|---|---|---|---|
| Q1 | Name | A: `BareSpreadConcat` | 5-1 (PLT dissent: B `SpreadConcatenation`) |
| Q2 | Is the fix applied by `blink fix`? | A: machine-applicable, with the fallbacks that Q3 and Q4 decide | 5-1 (Minimalism dissent: B, suggested only) |
| Q3 | Expected-type fallback | A: none; only a comment inside the literal makes the fix a suggestion | 6-0 |
| Q4 | A first source that is not a primary or postfix expression | A: the fix puts it in parentheses | 5-1 (Minimalism dissent: B, suggestion with the parenthesized text in `help:`) |
| Q5 | A source that is itself a list literal (`[..a, ..[2, 3]]`, `[..[], ..a]`) | B: does not match; the text says "neither source is a list literal" | 3-3 after Phase D (A: Systems, Web, AI/ML; B: PLT, DevOps, Minimalism); BDFL tiebreak for B |
| Q6 | The §2.16 last rule | A: keep the rule, append the warning name and code | 6-0 in Phase D (Phase C 4-2; Web and PLT moved) |
| Q7 | The §3.2.2 sentence | No majority (A: Web, DevOps, AI/ML; B: PLT, Minimalism; C: Systems); the wording goes to the writer | 3-2-1 in Phase C and again in Phase D |

Points all six seats stated, not balloted:

- A Warning in the Linting range of ERROR_CATALOG.md *Warning Names*, default level warn. No Info row, no new
  "style lint" class, no off-by-default level.
- Suppression is §4.16.8 as it is today (`@allow(Name)`, `[lints]`). The check fires in `test` blocks.
- It matches a list literal with exactly two elements, both spreads, and no other element. Layout, a trailing comma and
  a comment do not change the match. It does not match one spread, three or more elements, or any plain element.
  The same source twice (`[..a, ..a]`) matches.
- The span is the whole literal. The help text gives the replacement with the real operand text.
- The code is W0709: the next free code in the Linting range W070x.
- A `const` initializer does not get the warning; E0533 already applies there.
- A bare statement `[..a, ..b]` gets the warning, with no special case. After the fix, W0606 fires on `a.append(b)`.
- A comment inside the literal makes the fix a suggestion.
- `blink fmt` leaves both forms alone.
- The 02_syntax.md operator-table example `[..list1, ..list2]` becomes `[..list1, x, ..list2]`.
- The §2.16 last rule names the warning.
- The 8 repo sites that write a bare two-source spread migrate to `a.append(b)`.
- Minimalism withdrew its fallback min-2 (remove the rule line) in Phase B.

### Compiler behavior before the decision

The moderator ran probes with the gen1 compiler (built from main at edad70d8) and gave the results to the panel:

- p01: `[..a, ..b]` gives no diagnostic and prints `1,2,3`.
- p02: `[..xs.filter(p), ..ys]` and `xs.filter(p).append(ys)` give no diagnostic and the same output.
- p03: `let ys: List[Int] = [..none(), ..base]` and `let zs: List[Int] = none().append(base)` (a generic
  `none[T]()`) both compile and give the same output.
- p04: `[..if c { a } else { b }, ..d]` gives the ICE `UnmaterialisedValueExpr`. This is an open bug, not part of
  this decision.
- p05: `[..f(), ..g()]` and `f().append(g())` print `f` then `g`.
- p06: a bare statement `[..a, ..b]` gets no diagnostic. A bare statement `a.append(b)` gets W0606.
- p07: `const C: List[Int] = [..A, ..B]` gives `NonConstExpr` (E0533).
- p08: `[..a, ..[2, 3]]` and `[..[], ..a]` compile with no diagnostic.
- p09: a two-spread literal over several lines with a trailing comma gives no diagnostic.
- p10: `[..a]` (one spread) gives no diagnostic.
- p11: `[..a, ..a]` on `List[Str]` gives no diagnostic.
- p12: `[].append(a)` compiles.
- p13: `[..a, ..b]` as a function tail gives no diagnostic.
- Phase B probe (Web): `let a: List[Int] = [..none(), ..none()]` and `let b: List[Int] = none().append(none())`, with
  `fn none[T]() -> List[T]`, both compile and print `0 0`.

The repo has 8 bare two-source spread literals in src, lib and tests, for example `tests/test_spread_list.bl:22`
`let z = [..x, ..y]`.

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in
independent-proposal, debate, vote rounds. Phase A is excerpted from each panelist's own text ("…" marks a cut).
Phases B, C and D are quoted in full from each panelist's file, without the "Files read" line; those lines appear in
*Reading gaps* below where they matter.

#### Phase A — Independent proposals

- **Systems:** "## sys-1: Warning `BareSpreadConcat` (W0709), on by default, fix is a suggestion only. Both forms
  compile to one copy loop of `a.len() + b.len()` elements. The check has no runtime cost and no codegen effect. […]
  I want one spelling and one lowering. A warning with a hard default makes that true. An Info row that is silent by
  default (as `EscapeHeavyString` is) would not enforce the rule line that prior votes asked to enforce." […]
  "A fix that sometimes needs parentheses and may change inference is not safe in `blink fix`. The help text carries
  the edit." Fallback sys-2: "Do nothing. Valid only if the panel accepts that Q1 stays advisory. I oppose it."
- **Web/Scripting:** "## web-1 (my pick): Warning `BareTwoSpread`, default warn, `blink fix` machine-applicable, narrow
  match. A JS/Python dev who writes `[..a, ..b]` wrote it because `[...a, ...b]` is the idiom they know. The compiler
  must teach `a.append(b)` at the first keystroke. A warning does that. An Info row is silent in the terminal […] so
  the dev never sees it and the rule stays advisory […]." On a generic first source: "if the first source is a generic
  call, the fix is suggested only (like W0707), never applied." Fallback web-2: "Reject; docs only. Valid fallback. I
  oppose it: the vote already conceded that advisory rules drift."
- **PLT:** "## plt-1: warning W0709 `SpreadConcatenation`, default warn, fix machine-applicable only when the edit is
  exact. […] §3.2.2 states the rule in normative text ("Each concatenation has one form"). Info is silent by default,
  so a rule behind an Info row is advisory in terminal output." On a literal source: "Either source is itself a list
  literal (`[..a, ..[2, 3]]`, `[..[], ..a]`, p08). That is a literal with extra elements, which §3.2.2 allows.
  `[].append(a)` would read worse and has no value." Typing: "For `a: List[T]` and `b: List[T]`, `[..a, ..b]` and
  `a.append(b)` have the same type, the same value and the same cost, O(`a.len() + b.len()`). The rewrite preserves
  meaning." Fallback plt-2: "Info V11xx, no fix. Weaker: silent in terminal, so it does not enforce. I oppose it."
- **DevOps:** "## devops-1: a Warning, default `warn`, machine-applicable fix (recommended). `BareListSpread`, next free
  Linting code (W07xx). It is a Warning, not Info. Info is silent in the terminal […], and the whole point is that the
  author, and a model that reads the output, sees it." On the fix: "If a comment sits between the elements, report the
  warning but give the fix as help text only. `blink fix` must never delete a comment." Fallback devops-2: "Info only,
  no fix (fallback). `V11xx`, silent by default. Weak: nobody reads silent output, so the rule stays advisory."
- **AI/ML:** "## aiml-1: Warning `BareSpreadConcat`, default warn, fix machine-applicable. My concern in the
  duplicate-API vote was that models mix both forms at random. A model learns what the compiler corrects. A rule line
  in the spec is read once. A warning with a fix is read on every build, in every agent loop, and `blink fix` closes
  the loop with no model decision." On a bare statement: "Suppress the new warning when the literal is an expression
  statement, and let a separate decision handle dropped literals." Fallback aiml-2: "do nothing. Valid only if the
  panel accepts that both forms will spread. I oppose this; […]"
- **Minimalism:** "## min-1: one ordinary warning, no new class, no `blink fix` edit (recommended). Add one row to
  ERROR_CATALOG.md *Warning Names*, W070x (Linting range): `SpreadConcat`. […]" On a literal source: "A literal source
  is a "list literal with extra elements", which §3.2.2 already allows. This keeps the check purely syntactic: no
  types, no inference, no `none()` case (p03)." On the fix: "suggested fix only, never applied (same wording as W0705
  to W0707). […] The lint's job is to name the one form; the author types five tokens." Fallback min-2: "reject the
  lint and remove the rule line […] so I prefer min-1."

#### Phase B — Debate highlights

Each seat read the six Phase A files and replied on nine variations (name, code, fix class, fallbacks, parentheses,
literal source, bare statement, `const`, spec text). Excerpts from each seat's own text:

- **Systems** changed on the fix class **(position shift)**: "**V3 fix class. I change my position.** I now back a
  machine-applicable fix, with narrow exact conditions (V4, V5). Five seats want one, and the lint's job is to end
  drift. My safety concern is real but solvable with exact fallbacks […]". On the bare statement: "I change: the lint
  fires and W0606 follows after the fix. Aiml's suppression adds a special case for no gain." On literal sources: "I
  hold "match all". One syntactic rule, no carve-out, and the rule line says "two lists and nothing else". […] I
  accept the no-match option (plt, devops, min) if it wins, but the exact text must say "neither source is a list
  literal"."
- **Web/Scripting** moved to the name `BareSpreadConcat` and dropped its generic-call exception **(position shift)**:
  "I move from `BareTwoSpread` to `BareSpreadConcat` (sys, aiml): it names the job (concatenation), which is what a dev
  searches for." "Expected type: I drop my generic-call exception. I probed `let b: List[Int] = none().append(none())`
  against `[..none(), ..none()]`: both compile and give the same result. devops and plt are right; a type exception
  adds a rule with no case behind it. Concession." On parentheses: "Rule I want in spec text: "parenthesise the receiver
  unless it is a postfix or primary expression"."
- **PLT** dropped its claim that no type information is needed, then dropped the both-generic exception in Phase C:
  "I drop my claim that no type information is needed. web-1 and aiml-1 have a real point when no operand fixes `T`.
  […] I have not probed the both-generic case; the ballot should say so." On the name: "`SpreadConcatenation` is the
  only name that states the rule instead of a flaw ("Bare" says nothing a reader can act on), but I will not fight for
  it."
- **DevOps** dropped `BareListSpread` and withdrew "replace the rule" for §2.16 **(position shift)**: "I drop
  `BareListSpread`." "Ballot only the §2.16 edit. I hold: keep the last rule and append the warning name and code (min,
  sys, plt agree in substance). […] I withdraw "replace the rule" in my Phase A." On the fix: "W0545, W0552, W0901 and
  W0902 set the precedent for fixes with conditions."
- **AI/ML** withdrew its bare-statement suppression **(position shift)**: "I concede. I withdraw my suppression. Fire
  the warning; W0606 follows after the fix. Four seats agree, and my rule added an exception for a rare case." On the
  fix: "I oppose "suggested only" (sys-1, min-1). A suggestion needs one more model step, and that step is the decision
  point I want gone." On literal sources: "I hold "match", but weakly."
- **Minimalism** held "suggested only" **(dissent)** and withdrew min-2: "I hold "suggested only". The V4 and V5 rules
  show the cost: four seats list four different fall-back conditions (comment, generic call, expected type,
  parentheses). Each is a rule to specify, build and test […]. I do not oppose a fix if the panel takes it, but then V4
  needs one agreed condition list, not four." "I withdraw min-2 as a ballot option; five seats reject it."

All six agreed that a comment inside the literal makes the fix a suggestion, that the check does not fire in a `const`
initializer, and that the §2.16 last rule names the warning. Seats still split on the fix class, the fallback
conditions, the parentheses rule, literal sources, the §2.16 text and the §3.2.2 sentence; those went to the ballot.

#### Phase C — Votes

Each seat voted on seven ballot questions. Votes, reasoning and concerns are complete and verbatim.

##### Q1. Name

- **Systems — A.** Reasoning: `BareSpreadConcat` says what the compiler sees (a bare spread that does a concatenation) and carries the two words a reader searches for. web and devops moved to it, so it has the widest support. The name does not change codegen. Concern: "Bare" says little about the fix, so a reader may not see that `a.append(b)` is the answer until they read the help line.
- **Web/Scripting — A.** Reasoning: A dev who hits this warning searches for "spread" and "concat". The name has both words and says what the code does. It also has the most support (sys, aiml, and web and devops after B1). Concern: "Bare" tells the reader little by itself, as plt says, but the help text names the replacement, so this costs little.
- **PLT — B (`SpreadConcatenation`).** Reasoning: The name should state the rule, not the flaw. "Bare" tells a reader nothing they can act on, and the §3.2.2 heading is "Concatenation". The name does not change soundness, so I hold my own text. Concern: If A wins, `BareSpreadConcat` reads as a judgment on the literal, but it still carries "spread" and "concat", so I accept it.
- **DevOps — A.** Reasoning: The name states what the check flags and shows in the `warning[W0709]: BareSpreadConcat` header and in `@allow(...)`. An author or model who sees it can search for "spread" and "concat". Five seats now accept it. Concern: "Bare" tells the reader little until the help line, so the header text must carry the rule ("two lists join with `append`").
- **AI/ML — A.** Reasoning: It holds "spread" and "concat", the two words a model or an agent searches for when it reads the diagnostic. It also says what the check flags. The other names add no learning value. Concern: "Bare" has no meaning outside this rule, so a new reader must look up what it excludes.
- **Minimalism — A.** Reasoning: I dropped `SpreadConcat`, so the choice is between A and B. A names the flaw and the job, and has the most seats behind it (sys, aiml, web, devops). A model or a user who greps for "spread" and "concat" finds it. Concern: "Bare" has no precise meaning in the spec, so a reader may ask what a non-bare spread concat is.

**Result: A (`BareSpreadConcat`) 5-1** (dissent: plt, B).

##### Q2. Is the fix applied by `blink fix`?

- **Systems — A.** Reasoning: Both forms lower to one copy loop with the same cost and the same evaluation order, so the edit changes no runtime behavior. Five seats want enforcement, and a suggestion-only fix leaves every hit to a manual edit. My safety concerns were about precedence, comments and inference. Q3 and Q4 answer them with exact rules. Concern: Every fallback condition is one more case the fixer must build and test, and a bug in the edit would change user code silently.
- **Web/Scripting — A (machine-applicable, with the fallbacks that Q3 and Q4 decide).** Reasoning: A suggestion-only fix means each warning needs a manual edit. Most hits will be in AI-written files, and that friction pushes people to `@allow` the rule. W0545, W0552, W0901 and W0902 already set the precedent for a fix with conditions. Five seats now hold this. Concern: A wrong edit from `blink fix` costs more trust than a missing one, so the fallback conditions must be exact and tested.
- **PLT — A (machine-applicable).** Reasoning: `append` is `List[T] -> List[T] -> List[T]` and the two-spread literal has the same type, value and cost, so the rewrite keeps meaning. Order of evaluation is the same (p05). A suggestion-only fix leaves every model-written site to a human and weakens the enforcement the Phase C concerns asked for. Concern: A fixed rewrite that the checker later finds type-unsafe in a case no probe covers would break a build on `blink fix`.
- **DevOps — A (machine-applicable, with the Q3 and Q4 fallbacks).** Reasoning: The edit is two operand texts and an optional pair of parentheses. W0545, W0552, W0901 and W0902 already set the precedent for fixes with conditions. A suggestion-only fix leaves every hit as a manual edit, and the Q1 concern was that the rule must be enforceable. Concern: Each fallback condition is code to build and test, and a wrong edit from `blink fix` costs more trust than a missing one.
- **AI/ML — A (machine-applicable).** Reasoning: A suggestion needs one more model step per hit, and that step is the decision point this ticket must remove. An agent loop that runs `blink fix` ends the drift with no model choice. The fallbacks of Q3 and Q4 keep the edit exact. Concern: If the fix has a rare wrong edit, users stop trusting `blink fix` for every other rule.
- **Minimalism — B (suggested only).** Reasoning: The check needs no types and no edit logic if it gives help text only. Every applied-fix option adds rules (comment, parentheses, inference) to specify, build and test, for a five-token edit. W0705 to W0707 already set the wording. Concern: If A wins, `blink fix` gains an expression-rewriting path with parentheses logic that the first bug in it will exercise, and p04 shows the receiver forms are not yet sound.

**Result: A (machine-applicable) 5-1** (dissent: min, B).

##### Q3. The expected-type fallback

- **Systems — A.** Reasoning: web's probe, re-run on gen1, shows `[..none(), ..none()]` and `none().append(none())` both compile and print the same. I asked for a type-based rule only to protect inference, and the facts show no case where inference changes. A fallback with no case behind it is dead code that needs a test and a spec sentence. Comments stay the only fallback, because that edit would drop text. Concern: The probe covers one shape on one compiler build; a generic receiver in a future inference rule could type differently under `append`, and `blink fix` would then change a result type.
- **Web/Scripting — A (none; only a comment makes the fix a suggestion).** Reasoning: My probe on gen1 compiled both `[..none(), ..none()]` and `none().append(none())` and printed `0 0` for each. The probe found no case where the fix changes the result, so another exception would be a rule with no case behind it. B, C and D add a rule that needs a syntactic or type check, and the rule would look inconsistent to a user. Concern: One probe is not a proof. If a case turns up where `T` stays unresolved after the rewrite, the fix produces a compile error. That is a bug to fix with a new exception then, not one to guard against now.
- **PLT — A (none; only a comment makes the fix a suggestion).** Reasoning: I withdraw option D. My B1 text rested on an unprobed case. The new fact shows `[..none(), ..none()]` and `none().append(none())` both compile and print `0 0`, so the both-generic case has no counterexample. A fallback with no case behind it is an extra rule in the spec and an extra type query in the checker. Concern: A generic receiver whose binder only the expected type fills may fail to infer in some form the probes did not reach, and the fix would then not compile.
- **DevOps — A (none; only a comment makes the fix a suggestion).** Reasoning: The fact says `none().append(none())` and `[..none(), ..none()]` both compile and print the same, so no case supports an exception. Options B, C and D make the lint read type or inference state, and D names the one case that the probe just cleared. A syntactic lint with one fallback is easy to explain in the diagnostic and to test. Concern: A generic shape that the probes did not cover may fail to infer after the fix, and the author then sees a type error in code that `blink fix` wrote.
- **AI/ML — A (none; only a comment makes the fix a suggestion).** Reasoning: The fact shows `[..none(), ..none()]` and `none().append(none())` both compile and print `0 0`. No case supports an exception, and each extra exception is a rule a model must learn and the compiler must test. I withdraw my B1 vote for the generic-call rule: the probe is the evidence I lacked. Concern: A case no probe covers may type differently, and then the applied fix breaks the build instead of being suggested.
- **Minimalism — A (none; only a comment makes the fix a suggestion).** Reasoning: web's probe on gen1 shows both-generic `none()` compiles in both spellings, so no case backs an inference exception. Options B, C and D each need type information or a new syntactic rule for no observed failure. Concern: A later generic case that does not infer will turn a machine-applied fix into a compile error in a user's tree.

**Result: A (only a comment makes the fix a suggestion) 6-0.**

##### Q4. A first source that is not a primary or postfix expression

- **Systems — A.** Reasoning: The set of expressions that need parentheses is a fixed syntactic list. Wrapping the receiver cannot change evaluation order or type, so the edit is exact. Option B would make `blink fix` skip these hits and leave a manual step for the rare cases. I said in B1 that I accept the list if the panel wants auto-parens. Concern: If a new expression form joins the grammar and the list is not updated, the fix writes `a + b.append(c)` with the wrong meaning; the spec rule should say "parenthesize unless primary or postfix" so new forms are safe by default.
- **Web/Scripting — A (the fix wraps it in parentheses; the list is `if`, `match`, lambda, `??`, `as`, unary, binary, range).** Reasoning: The list is fixed and small, and the edit is mechanical. A user who sees "suggestion only" for `(a ?? b).append(c)` has to do the one step the fix should do. The spec text can say "parenthesise unless the receiver is a postfix or primary expression", which covers future expression forms. Concern: A new expression form added later, left off the list, would yield a wrong edit. Stating the rule as "not postfix or primary" avoids that.
- **PLT — A (the fix wraps it in parentheses).** Reasoning: The list is finite and syntactic: `if`, `match`, lambda, `??`, `as`, unary, binary, range. Parenthesizing a whole source never changes its meaning, and the spec text can say "unless a postfix or primary expression". Suggestion-only for every such case gives up the fix on the exact inputs where an author is most likely to make a precedence error. Concern: If the list misses one expression kind, the fix emits a receiver that parses differently, so the rule needs a test per kind.
- **DevOps — A (the fix wraps it in parentheses).** Reasoning: The list is fixed and the edit is mechanical, so `blink fix` can apply it and the help text shows the same string. Option B makes the same hit machine-applicable in some cases and not in others for a reason the author cannot see. A listed set also covers the `if` and `match` cases that most need the fix. Concern: A source kind missing from the list yields code that parses differently, so the spec text should say "any expression that is not a primary or postfix expression" rather than only list kinds.
- **AI/ML — A (the fix wraps it in parentheses).** Reasoning: The list is fixed and finite, and the rule "parenthesize unless primary or postfix" is easy to state and learn. A suggestion-only path would leave all these hits as manual work. Concern: The first-source list drifts from the parser's precedence table when a new expression form is added.
- **Minimalism — B (suggestion, with the parenthesized text in `help:`).** Reasoning: A fixed paren list is a rule that grows as the grammar grows, and `blink fix` should not write text it must reason about. A suggestion keeps the machine edit to the one exact case. Concern: If A wins, a new expression form added to the grammar later will be missing from the list and produce a wrong edit.

**Result: A (the fix wraps it in parentheses) 5-1** (dissent: min, B).

##### Q5. A source that is itself a list literal

- **Systems — A.** Reasoning: The check stays one syntactic rule: two elements, both spreads. A literal-source carve-out makes the check read the source's spelling and needs a spec clause. `[].append(a)` compiles (p12) and is the same single copy loop, so there is no cost reason to exempt it. Concern: `[..[], ..a]` becomes `[].append(a)`, which reads worse than the input, and authors may add `@allow` for it.
- **Web/Scripting — A (matches).** Reasoning: One rule with no carve-out is quicker to learn and to state in the spec. In `[..a, ..[2, 3]]`, `[2, 3]` is a source, not an extra element, so "two lists and nothing else" covers it. A carve-out leaves a spread form that a model will copy. Concern: `[..[], ..a]` becomes `[].append(a)`, which reads oddly, but it is rare and still correct.
- **PLT — B (does not match).** Reasoning: §3.2.2 allows "a list literal with extra elements"; `[..a, ..[2, 3]]` is that, read as a literal built from a list and a literal. Matching it makes `[..[], ..a]` become `[].append(a)`, which is worse code than the input and no one would write it. The spec text must say "neither source is a list literal". Concern: If A wins, the fix emits `a.append([2, 3])` or `[].append(a)`, and a model learns that these are the required spellings.
- **DevOps — B (does not match; the text says "neither source is a list literal").** Reasoning: The help text for `[..[], ..a]` would read `[].append(a)`, and `[..a, ..[2, 3]]` would read `a.append([2, 3])`. No author would write either, so the diagnostic suggests a form worse than the input. The exemption follows the §3.2.2 wording for a literal with extra elements, and it is one syntactic clause. Concern: Authors and models may copy the literal-source spread as the sanctioned form, which is a small remaining path for drift.
- **AI/ML — A (matches).** Reasoning: One rule with no carve-out is fewer decision points for a model. A "neither source is a list literal" clause is an exception to learn, and it leaves a spread form that a model copies. The cost either way is small, because literal sources are rare. Concern: `[].append(a)` reads worse than the input, so the fix gives an odd result for the empty-literal case.
- **Minimalism — B (does not match; the text says "neither source is a list literal").** Reasoning: A literal source is a list literal with extra elements, which §3.2.2 already allows. `[].append(a)` is worse code than the input, and the carve-out is one clause taken from the spec's own wording. Concern: If A wins, the check flags `[..[], ..a]` and suggests `[].append(a)`, a rewrite no author would write.

**Result in Phase C: 3-3** (A: sys, web, aiml; B: plt, devops, min). Phase D follows.

##### Q6. The §2.16 last rule

- **Systems — A.** Reasoning: Keep the existing normative sentence and append the name and code. That is the smallest edit, and it makes §2.16 and §3.2.2 agree without a second copy of the rule's wording. B and C reword a rule that five seats already voted on. Concern: The name and code appear in three places (§2.16, §3.2.2, the catalog), so a later rename or recode must update all three.
- **Web/Scripting — B (plt-1 text: "...join with `a.append(b)`, not `[..a, ..b]`; the compiler warns W0709 (§3.2.2 *Concatenation*).").** Reasoning: A dev reads §2.16 first. The rule there must say that the compiler checks it and give the code to look up. B does both in one clause and points to the catalog section. Concern: The text names the code but not the warning name. A reader who wants to `@allow` it must follow the link. The catalog row gives the name.
- **PLT — B.** Reasoning: The rule must name the check and point to §3.2.2, so §2.16 and §3.2.2 agree. B gives the code and the cross reference in one clause and keeps the "not `[..a, ..b]`" part that tells a reader what to avoid. C drops the code, so a reader cannot look up the warning. Concern: If A wins, the rule line stays long and the warning name sits at its end, where a reader may skip it.
- **DevOps — A (keep the rule and append the warning name and code).** Reasoning: The rule stays as the prior vote wrote it, and the appended name and code give a reader one string to search for in the catalog. It makes the smallest edit, so the diff against the 5-1 decision text is easy to review. Both sections then name the same warning. Concern: If a later change renames or recodes the warning, the §2.16 text is a second place that must change.
- **AI/ML — A (keep the rule, append the warning name and code).** Reasoning: A model reads the existing rule line and then the name and code, which it can search for in ERROR_CATALOG.md. This changes the least text and cannot make the two sections disagree. Concern: The rule line gets longer, and a model may skip a trailing parenthesis.
- **Minimalism — A (keep the rule, append the warning name and code).** Reasoning: The smallest edit that makes §2.16 and §3.2.2 agree. It leaves the existing rule text intact and adds the pointer. Concern: If B or C wins, the rule text is reworded, and the two sections can drift in wording.

**Result in Phase C: A 4-2** (B: web, plt). Phase D follows.

##### Q7. The §3.2.2 sentence

- **Systems — C.** Reasoning: The sentence states the match and the code. The fix class, the comment fallback and the parentheses rule belong in the catalog row, where the other fix rows (W0705 to W0707) keep theirs. Repeating them in §3.2.2 gives two places to keep in step. The Q1 name appears in §2.16 and the catalog row. Concern: A reader of §3.2.2 alone does not learn that `blink fix` rewrites the literal, and must follow the code to the catalog.
- **Web/Scripting — A (devops-1: "A literal of exactly two spreads and no other element is warning `<Name>` (W0709); `blink fix` rewrites it to `a.append(b)`.").** Reasoning: It gives the name, the code and the fix in one sentence, so a reader needs no other page to know what happens. "No other element" is exact and matches the rule line. B and C leave out the fix, and D leaves out the code. Concern: The sentence says `blink fix` rewrites it, but the comment fallback means it sometimes only suggests. The catalog row must state that condition.
- **PLT — B.** Reasoning: One short sentence that names the code and the name, and the catalog row carries the Q2 to Q5 detail. Putting the fix behavior in §3.2.2 as well (A) repeats the catalog row and can drift from it. The sentence must still match the Q5 result, so the writer adds "neither source a list literal" to the row. Concern: If D wins, the sentence omits the code, and §3.2.2 does not tell a reader which warning to suppress.
- **DevOps — A.** Reasoning: It states the match ("exactly two spreads and no other element"), the name and code, and the fix in one sentence. A reader of §3.2.2 sees both the check and what `blink fix` does without opening the catalog. The Q5 result goes in the catalog row and the sentence stays short. Concern: The sentence must also state the Q5 result ("neither source a list literal") or it disagrees with the match rule.
- **AI/ML — A (devops-1 as web B1 holds it).** Reasoning: It states the match, the name, the code and the fix in one sentence, so a model learns the whole rule from the spec alone. The other options omit either the fix or the name. Concern: The sentence must change if the Q2 to Q5 results change, and a stale sentence misleads models.
- **Minimalism — B (plt-1: "A literal of exactly two spreads is W0709 (`<Name>`).").** Reasoning: It is the shortest sentence that gives both name and code, and it does not state the fix class, so it stays true if the fix choice changes. A states the fix class in prose, which duplicates the catalog row. Concern: The sentence says "exactly two spreads" and not "nothing else", and the Q5 result (no literal source) lives only in the catalog row.

**Result in Phase C: no majority** (A: web, devops, aiml; B: plt, min; C: sys). Phase D follows.

#### Phase D — Debate and silent re-vote (Q5, Q6, Q7)

Phase C left Q5 at 3-3, Q6 at 4-2 and Q7 with no majority. Each seat read the Phase C votes, named the strongest
point from the other side, answered it and held or moved. Excerpts, attributed:

**Q5 (literal source).**

- **Systems (holds A):** "The strongest point from the B side: `[..[], ..a]` becomes `[].append(a)`, a form no author
  writes, and the help line then suggests worse code than the input. I grant that for the empty literal. It does not
  change my vote. A literal source is rare, the warning is a nudge to review the line, and the author may keep the
  spread with `@allow`. […] I accept B if it wins, on the condition that the text says "neither source is a list
  literal", as I wrote in B1."
- **Web/Scripting (holds A):** "Answer: `[2, 3]` is a source here, not an extra element, and the rule line says "two
  lists and nothing else". The carve-out is a second clause to learn, and the literal-source spread stays legal and
  unflagged, so models keep copying it."
- **PLT (holds B):** "the rule exists to stop two forms for one job. For a literal source the sanctioned rewrite,
  `a.append([2, 3])` or `[].append(a)`, is worse code than the input, so the warning would push authors to a form no one
  writes. A warning whose fix makes code worse teaches `@allow`."
- **DevOps (holds B):** "The cost of A is on my surface: the help line for `[..[], ..a]` reads `[].append(a)`. sys,
  web and aiml all name this as their own Concern, and an author who gets a suggestion worse than the input will add
  `@allow`."
- **AI/ML (holds A):** "The carve-out costs more than it saves: it is a clause a model must learn, and it leaves
  `[..a, ..[2, 3]]` as a spread form that is not flagged and so looks approved."
- **Minimalism (holds B):** "A check that suggests worse code than its input teaches the wrong lesson."

**Q6 (§2.16 last rule).** Web and plt moved from B to A. Web: "My B said the reader must see the code in §2.16. A
does that: the name and code go at the end of the rule, and the reader can search the catalog for them. A is the smaller
edit and cannot reword a rule that five seats already voted on. I withdraw B." Plt: "My reason for B was that A hides
the name at the end of a long line, and that is a layout concern, not a soundness one."

**Q7 (§3.2.2 sentence).** The split held. Web, devops and aiml wanted the fix named in the sentence. Plt, min and sys
said the fix has conditions, so a flat "`blink fix` rewrites it" is "not always true" (sys, plt) and one clause is
"either wrong or long" (min), and the catalog row keeps them.
Every seat said it accepts another option if it wins, with the Q5 result and a qualifier on the fix stated somewhere.

##### Phase D round 2 — silent votes

Each seat voted alone. Text is complete and verbatim.

###### Q5. A source that is itself a list literal

- **Systems — A (matches).** Reasoning: The check stays one syntactic rule: two elements, both spreads. A carve-out makes the check read the spelling of a source. `[].append(a)` compiles (p12) and lowers to the same single copy loop, so there is no cost reason to exempt it. The odd help text for `[..[], ..a]` is rare and still correct. Concern: `[..[], ..a]` becomes `[].append(a)`, which reads worse than the input, and authors may add `@allow` for it.
- **Web/Scripting — A (matches).** Reasoning: In `[..a, ..[2, 3]]` the literal `[2, 3]` is a source, not an extra element, so "two lists and nothing else" already covers it. One rule with no carve-out is quicker for a JS or Python dev to learn, and a literal-source spread that stays unflagged looks approved, so models keep copying it. The odd help text for `[..[], ..a]` is rare, still correct, and the author may keep the spread with `@allow`. Concern: If B wins, `[..a, ..[2, 3]]` stays unflagged and a model reads it as the sanctioned spread form, so the two forms keep drifting.
- **PLT — B (does not match; the text says "neither source is a list literal").** Reasoning: The rule exists so that one job has one form. For a literal source, the rewrite (`[].append(a)`, `a.append([2, 3])`) is worse than the input, and sys, web and aiml all name this in their own concerns. §3.2.2 already allows a list literal with extra elements, so the carve-out is one clause that follows the spec's own wording and adds no new rule. Concern: If A wins, a warning whose fix makes the code worse teaches authors to add `@allow`, and models may learn `[].append(a)` as a required spelling.
- **DevOps — B.** Reasoning: The help line for `[..[], ..a]` reads `[].append(a)`, and for `[..a, ..[2, 3]]` it reads `a.append([2, 3])`. A diagnostic that suggests code worse than its input makes authors add `@allow`, which is the wrong lesson from a lint. The exemption follows the §3.2.2 wording "a list literal with extra elements" and is one syntactic clause. Both the spec sentence and the catalog row must state "neither source is a list literal". Concern: If A wins, the help text prints `[].append(a)`, and authors suppress the warning instead of fixing the line.
- **AI/ML — A (matches).** Reasoning: One syntactic rule has the fewest decision points for a model: two elements, both spreads, warn. A carve-out is a clause to learn, and it leaves `[..a, ..[2, 3]]` unflagged, so it looks approved and models copy it. The odd `[].append(a)` result is rare and still correct, and the cost is one copy loop either way. Concern: The fix prints `[].append(a)` for `[..[], ..a]`, which reads worse than the input, so authors may add `@allow` and models may learn that the odd form is required.
- **Minimalism — B (does not match; the text says "neither source is a list literal").** Reasoning: A literal source is the shape §3.2.2 already allows as "a list literal with extra elements". A check whose fix turns `[..[], ..a]` into `[].append(a)` suggests code worse than its input, and that teaches authors to add `@allow`. The carve-out is one syntactic clause that reuses the spec's own wording, so it adds little surface. Concern: If A wins, the warning fires on literal sources and the help text prints a rewrite that no author writes.

**Tally: 3-3** (A: sys, web, aiml; B: plt, devops, min). No majority.

**Tiebreak (BDFL): B.** The owner broke the tie for B: "a warning whose fix is worse than the input is noise". A
list literal as either source does not match.

###### Q6. The §2.16 last rule

- **Systems — A (keep the rule, append the warning name and code).** Reasoning: It is the smallest edit and it does not reword a rule that 5-1 already settled. All six seats hold A. The appended name gives `@allow` its string, and the code gives the catalog lookup. Concern: The name and code then appear in three places (§2.16, §3.2.2, the catalog), so a later rename or recode must change all three.
- **Web/Scripting — A (keep the rule, append the warning name and code).** Reasoning: A dev reads §2.16 first, and A tells them the compiler checks the rule. It gives both the code to look up and the name to put in `@allow`, and it leaves the 5-1 text intact. Concern: The name and code now appear in three places (§2.16, §3.2.2, the catalog), so a later rename must change all three.
- **PLT — A (keep the rule, append the warning name and code).** Reasoning: It is the smallest edit and it does not reword a rule that 5-1 already settled. It gives the name and the code, so §2.16 and §3.2.2 cannot disagree and a reader can find the catalog row and `@allow` the warning. My reason for B was layout, not soundness. Concern: The name and code now sit in three places (§2.16, §3.2.2, the catalog), so a later rename must change all three.
- **DevOps — A.** Reasoning: Keep the voted rule text and append the warning name and code. This is the smallest edit, so the diff against the 5-1 decision is easy to review. The reader gets the name for `@allow` and the code for the catalog search. Concern: The name and code now appear in §2.16, §3.2.2 and the catalog, so a later rename must change all three.
- **AI/ML — A (keep the rule, append the warning name and code).** Reasoning: A model reads the rule it already has, then the name and code, and can search for both in ERROR_CATALOG.md. The name is what `@allow` needs. It changes the least text, so §2.16 and §3.2.2 cannot disagree. Concern: The rule line gets longer, and a model may skip a trailing parenthesis.
- **Minimalism — A (keep the rule, append the warning name and code).** Reasoning: It is the smallest edit. It leaves the rule that the 5-1 vote settled intact and gives the reader the one string to search for in the catalog. Nothing is reworded, so §2.16 and §3.2.2 cannot drift in wording. Concern: The name and code now sit in three places (§2.16, §3.2.2, the catalog), so a later rename must change all three.

**Result: A 6-0.**

###### Q7. The §3.2.2 sentence

- **Systems — C (sys-1: "A literal of exactly two spreads and nothing else gets W0709.").** Reasoning: The sentence states the match and the code. The fix class, the comment fallback and the parentheses rule have conditions, so one clause in §3.2.2 is either wrong or long, and the catalog row is the one place to keep them. A flat "`blink fix` rewrites it" is not always true. I rank B above A and accept either. Concern: A reader of §3.2.2 alone does not learn that `blink fix` rewrites the literal, and must follow the code to the catalog.
- **Web/Scripting — A (devops-1: "A literal of exactly two spreads and no other element is warning `<Name>` (W0709); `blink fix` rewrites it to `a.append(b)`.").** Reasoning: A reader of §3.2.2 learns the match, the name, the code and the fix in one sentence, with no second page. The comment fallback, the parentheses rule and the Q5 result go in the catalog row. I would also take A with "neither source a list literal" added if Q5 goes to B. Concern: The sentence says `blink fix` rewrites it, but the comment fallback means it sometimes only suggests, so a stale or unqualified sentence misleads.
- **PLT — B (plt-1: "A literal of exactly two spreads is W0709 (`<Name>`).").** Reasoning: The fix has conditions: a comment makes it a suggestion, and a first source that is not primary or postfix gets parentheses. A one-sentence statement of the fix is either wrong or long. The catalog row holds those conditions, as it does for W0705 to W0707, so §3.2.2 states only the match, the code and the name. Concern: If A wins, §3.2.2 says `blink fix` rewrites the literal without the comment condition, and the sentence and the row can drift apart. The sentence must also match the Q5 result.
- **DevOps — A.** Reasoning: One sentence gives the match, the name, the code and the fix, so a reader of §3.2.2 needs no other page. The catalog row holds the comment fallback, the parentheses rule and the Q5 result. The writer should keep the fix clause exact (for example "where the edit is exact"), so the sentence does not claim more than the comment fallback allows. Concern: If B or C wins, a reader of §3.2.2 does not learn that `blink fix` rewrites the literal, and must follow the code to the catalog.
- **AI/ML — A (devops-1: "A literal of exactly two spreads and no other element is warning `<Name>` (W0709); `blink fix` rewrites it to `a.append(b)`.").** Reasoning: A model that learns from the spec alone gets the match, the name, the code and the fix in one sentence. §3.2.2 is the page that shows what happens after the warning. The comment fallback and the Q5 result go in the catalog row, and the writer should add "neither source a list literal" only if Q5 = B. Concern: The sentence says `blink fix` always rewrites it, but a comment makes the fix a suggestion, so a flat sentence misleads models.
- **Minimalism — B (plt-1: "A literal of exactly two spreads is W0709 (`<Name>`).").** Reasoning: It is the shortest sentence that gives both name and code. It says nothing on the fix class, so it stays true if the fix has conditions (a comment makes it a suggestion). The catalog row is the one place for the fix, the comment fallback, the parentheses rule and the Q5 result, so there is one text to keep in step. Concern: If A wins, the sentence states an unqualified "`blink fix` rewrites it" that the comment fallback makes untrue, and it needs the Q5 result added or it disagrees with the match rule.

**Tally: 3-2-1, no majority** (A: web, devops, aiml; B: plt, min; C: sys). Phase D did not change Phase C. Sys ranks B
above A, and every seat accepts another option with conditions. Those conditions agree on three points: the sentence
must not claim more than the fix does, the Q5 result must show, and the catalog row holds the fix conditions. The writer
drafts the wording under these points. The draft in the Final Spec names the match, the Q5 exclusion, the name, the
code, the fix and the comment condition. That adds the fix to B and adds the comment condition to A; the writer's
wording is not a panel vote (see Open points).

#### Dissents

- **PLT, Q1 (B, `SpreadConcatenation`).** "The name should state the rule, not the flaw. "Bare" tells a reader nothing
  they can act on, and the §3.2.2 heading is "Concatenation"." PLT accepted A.
- **Minimalism, Q2 (B, suggested only).** "Every applied-fix option adds rules (comment, parentheses, inference) to
  specify, build and test, for a five-token edit." Concern: "`blink fix` gains an expression-rewriting path with
  parentheses logic that the first bug in it will exercise, and p04 shows the receiver forms are not yet sound."
- **Minimalism, Q4 (B, suggestion with the parenthesized text in `help:`).** "A fixed paren list is a rule that grows
  as the grammar grows, and `blink fix` should not write text it must reason about." The spec states the rule as
  "unless primary or postfix", so a new expression form is safe by default (Systems, Web, DevOps and AI/ML each raised
  this in their Concern).
- **Systems, Web and AI/ML, Q5 (A, match).** They held that a carve-out makes the check read the spelling of a
  source and leaves a spread form that a model copies as approved. Web's Concern: "If B wins, `[..a, ..[2, 3]]` stays
  unflagged and a model reads it as the sanctioned spread form, so the two forms keep drifting." The owner broke the
  tie for B.
- **Q7.** No majority, so no dissent. Web, DevOps and AI/ML wanted the fix in the sentence; PLT, Minimalism and
  Systems wanted it only in the catalog row.

#### Reading gaps

- In Phase D round 1, AI/ML read only its own Phase C file and the Phase D digest. PLT read the digest, its own Phase
  C file and the round 1 files; it did not re-read the five other Phase C files in round 1 or in round 2. Minimalism
  read only the digest in round 1. These seats worked from the Phase C votes as the digest quotes them verbatim.
- The Systems round 1 file lists the six Phase C files and the ballot, with no read of the digest's own text beyond
  `D1.md`; its round 2 file lists every input.
- The Phase D round 2 votes were silent: no seat read another seat's round 2 file.

### AI-First Review

| Criterion | Result |
|---|---|
| Learnability | Pass: a model that wrote `[..a, ..b]` gets a warning with the exact replacement in `help:`; "two spreads and nothing else" is the whole match rule |
| Consistency | Pass: the lint enforces the existing §3.2.2 rule and the duplicate-APIs decision; the fix class follows W0545, W0552, W0901 and W0902 |
| Generability | Pass: `a.append(b)` is one form for one job; the three-source and framed spreads stay legal and unflagged. A literal source is not flagged, so `[..a, ..[2, 3]]` stays legal (the owner's tiebreak) |
| Debuggability | Pass: one warning on the whole literal, the replacement written with the real operands, and `blink fix` applies it; a comment makes it a suggestion so no text is lost |
| Token Efficiency | Pass: `a.append(b)` is not longer than `[..a, ..b]`, and the check adds no syntax |

Result: 5 of 5 pass.

### Final Spec

```blink
let bad = [..a, ..b]                      // W0709: write a.append(b)
let kept = [..a, ..[2, 3]]                // OK: a source is a list literal
let also_kept = [..[], ..a]               // OK: a source is a list literal
let framed = [..a, 0, ..b]                // OK: a plain element
let from_option = [..x ?? y, ..z]         // W0709: the edit is (x ?? y).append(z)
```

```
warning[W0709]: two lists join with `append`, not a spread
 --> m.bl:3:13
  |
3 |     let z = [..x, ..y]
  |             ^^^^^^^^^^ two spreads and no other element
  |
  = help: write `x.append(y)`
```

- **Name and code (Q1).** `BareSpreadConcat`, W0709, a Warning in the Linting range, default warn. Suppress it with
  `@allow(BareSpreadConcat)` or `W0709` under `[lints]` (§4.16.8).
- **Match.** A list literal with exactly two elements, both spreads, in any layout. `[..a, ..a]` matches. One spread,
  three or more elements and any plain element do not match.
- **Literal source (Q5).** A literal where either source is a list literal does not match (BDFL tiebreak).
- **Not in a `const` initializer.** E0533 applies there. A bare statement gets the warning, and W0606 follows after
  the fix. The check fires in `test` blocks.
- **Fix (Q2, Q3, Q4).** `blink fix` rewrites the literal to `a.append(b)`. It puts the first source in parentheses
  unless it is a primary or postfix expression. A comment inside the literal makes the fix a suggestion only. No other
  case does, and the expected type plays no part.
- **`blink fmt`.** It leaves both forms alone.
- **§2.16 (Q6).** The last rule keeps its text and names the warning and the code. The 02_syntax.md operator-table
  example becomes `[..list1, x, ..list2]`.
- **§3.2.2 (Q7).** The sentence is the writer's wording, not a panel vote. It names the match, the literal-source
  exclusion, the name, the code, the fix and the comment condition. ERROR_CATALOG.md carries the full rule.

### Open points

- Q7 had no majority; the §3.2.2 sentence is the writer's draft.
- `sections/03_types.md` (the paragraph on what brackets mean in an expression) still uses `[..a, ..b]` as an example.
  The ruling did not name it; a follow-up chore can change it.
- The 8 repo sites that write the bare form migrate in the implementation, under the bootstrap protocol.
- `[..if c {a} else {b}, ..d]` crashes the compiler today (probe p04), so the `(if ...).append(...)` edit cannot be
  tested until that bug is fixed. The spec leads the compiler here.
- The golden header text, "two lists join with `append`, not a spread", is the writer's choice. DevOps asked that the
  header carry the rule.

