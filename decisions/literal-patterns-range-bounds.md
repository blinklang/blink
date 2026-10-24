[< All Decisions](../DECISIONS.md)

# Literal Patterns and Range Bounds — Design Rationale

The Pattern Grammar in §3.5 and the rules around it disagreed. The grammar listed `FLOAT_LIT` as a literal pattern, but
the range rule bars Float and the parser rejects a Float literal. The grammar had no row for a negative literal, but
§3.2 says every negative literal under an unsigned scrutinee is E0318. The grammar had no `CHAR_LIT` row, but the
compiler accepts `'a' =>`. §2.21 item 4 shows `1..=MAX_RETRIES`, but §3.5 said bounds are const expressions, and the C
build of a const-name bound fails. This decision settles each point.

## Summary

| Q | Question | Result | Vote |
|---|---|---|---|
| Q1 | A const name as a range bound | A: allowed as a bound only, bare or qualified; a `const` item of Int, sized-integer or Char type; §3.4 normal path, no local shadowing; value folds at type check; a cycle is an error; E0318 applies to the bound | 3-3 after Phase D; the user broke the tie for A |
| Q2 | The W0706 *Patterns* text | A: "No pattern form can write a Float, so `-0.0` cannot be a pattern. A change that adds Float patterns must bring them under W0706 or make them an error." | 5-1 (PLT dissent: B) |

All six seats agreed these points by the end of Phase B, so they were not voted:

- `-` INT_LIT is a literal pattern and a range bound. E0318 under an unsigned scrutinee is unchanged.
- `(-1)` and `-(1)` are not patterns. In a pattern `(` opens a tuple pattern. Systems and Web gave up their first
  position on this.
- The `FLOAT_LIT` row leaves the grammar. A Float literal is neither a pattern nor a bound. One new error,
  `FloatLiteralPattern`, names a guard (`x if x == 0.5`).
- A single `CHAR_LIT` row joins the grammar. The Char range rows stay.
- A const expression (`0..=K + 1`) is never a bound. One diagnostic, with a guard in the help.
- `K =>` stays E0308 and its help gains "use a guard: `x if x == K`".
- The spec states no lowering for a const bound.

Error codes: the panel named the errors but not their numbers. The writer chose E0322 for `FloatLiteralPattern` and
E0323 for `RangeBoundNotConst`. No catalog on `main` or on any `spec/*` branch uses E0322 to E0329.

### Compiler behavior before the decision

- `-1 =>` and `-128..=-1` are parse errors.
- `0.5 =>` is a parse error (UnexpectedToken at the FLOAT token).
- `'a' =>` works.
- `0..=K` with `const K: Int = 37` type-checks but the C build fails, because the printer writes the C name of the
  const in a `case` label.
- `0..=K + 1` is a parse error.

### Panel Deliberation

Six panelists: Systems (sys), Web/Scripting (web), PLT (plt), DevOps/Tooling (devops), AI/ML (aiml) and Minimalism
(min). The user, as BDFL, breaks ties.

#### Phase A — Independent proposals (excerpts)

All six seats took the same side on negative literals, Float literals, Char and const expressions. They split on
const names in bounds.

**Systems (sys-1)**: "a pattern may only hold what the compiler folds to an integer constant at compile time. Then a
match on an integer compiles to a C `switch` ... That has no runtime cost and no new machinery. Float patterns fail
this test." On const names: "Allow a bare or qualified const name as a bound, and only a const whose value folds to an
integer or Char literal." On the lone name: "an uppercase bare name followed by `..` or `..=` is a const bound. A
variant cannot start a range, so there is no clash. The lone `K =>` stays EnumPatternNeedsEnumScrutinee."

**Web (web-1)**: "Test: would a JS/Python/Rust dev guess it in 5 minutes? `-1 =>` and `1..=MAX =>` must work. `0.5 =>`
is the footgun." On const names: "Inside a range the name sits next to `..`/`..=`, so it is never a binding. The
\"Bare names\" rule is untouched." On `K =>`: "Add a hint: \"to match a const, use a guard: `x if x == K`\"."

**PLT (plt-1)**: "A pattern is closed under literal syntax. Name resolution never runs in a pattern (§3.4, *Bare
names*). Every bound and every literal is a value the exhaustiveness checker reads from the pattern text alone." On
const names: "`K =>` is already a variant (E0308). `K..=5` would be the same token in a position where one reading is
a variant. Two meanings for one token is not compositional." Tradeoff: "Const-bound ranges lose exhaustiveness. I accept
this as the cost of a pattern grammar with no name resolution."

**DevOps (devops-1)**: "I judge each form by the diagnostic the user sees, and by whether the LSP and `blink fmt`
can handle it without new rules." On const names: "This keeps 2.21 item 4 and the 5-0 \"compile-time constant
bounds\" vote." On Float: "Float `Eq` is the total order, so `0.0 =>` would match `-0.0` and `NaN =>` would match
NaN." Proposed the W0706 text: "No pattern form can write a Float, so `-0.0` cannot be a pattern. A change that adds
Float patterns must bring them under W0706 or make them an error."

**AI/ML (aiml-1)**: "Rule I want a model to learn from the spec alone: **a pattern literal is the same token a value
literal is, except Float. A range bound is a literal, never a name.** Two sentences, no exceptions to memorize." On the
vote text: "I read the vote as \"bounds fixed at compile time\", not \"names allowed\". The panel may rule otherwise."
Fallback aiml-2 allowed const names, ranked lower "because of the position-dependent rule".

**Minimalism (min-1)**: "The pattern grammar needs one new token (`-`). Every other form is either already accepted
and correct, or is removed." On const names: "A const bound is the first place a value name would change a pattern.
Allowing it needs resolution rules (bare, qualified, imported, shadowed), and exhaustiveness must evaluate consts."
Fallback min-2: "I accept only qualified or bare names of `const` items with an integer or char type, resolved by the §3.4
normal path."

#### Phase B — Debate, round 1 (digest)

The moderator listed six points of difference (V1 to V6):

| Point | Result of Phase B |
|---|---|
| V1 const name as a bound | Open. sys, web, devops for; plt, aiml, min against. Sent to the vote as Q1 |
| V2 `(-1)` | sys and web gave it up; the other four rejected it from the start |
| V3 W0706 text | Four seats took the devops text; plt took the min text. Sent to the vote as Q2 |
| V4 help on `K =>` | All support |
| V5 Float diagnostic | One new error, `FloatLiteralPattern`, after the parser reads the literal |
| V6 rejected-bound diagnostic | One code with a guard in the help, not one code per case |

Key replies, quoted:

- **sys** on V1: "`K..=5` has one parse: the token after the name is `..` or `..=`, and no variant pattern can be
  followed by either. This is one token of lookahead, not scope-dependent meaning."
- **web** on V1: "I concede that the text at 3181 needs one clause: \"except a const named as a range bound\"."
- **plt** on V1: "I concede sys and web are right on syntax ... My objection is not parsing. Line 3181 says no value
  binding, local or module-scope, changes what a pattern means. A const bound breaks that sentence at the first use."
- **aiml** on V1: "A later panel can add const names with one rule; adding is easy, removing is not."
- **devops** on V1: "The cost of rejecting is on the user. A `0..=MAX_RETRIES` arm becomes `0..=5`, a magic number, or a
  guard that loses the exhaustiveness check."
- **min** on V1: "Adding const bounds later breaks no code. Removing them later breaks code."
- **devops** on codegen: "sys is right that spec text must not say how a const bound lowers. I withdraw \"emit the
  mangled C name\" from my proposal."

All six ended Phase B with "STATUS: ready to vote".

#### Phase C — Final vote (silent ballot, verbatim)

Q1 result: A 3 (sys, web, devops), B 3 (plt, aiml, min). Q2 result: A 5, B 1 (plt).

##### Q1. A const name as a range bound

**sys — Vote: A.** Reasoning: "A const bound is a compile-time integer or Char value. Once typecheck folds it, the match
lowers like a literal arm, so the cost at run time is zero, and the lowering is the impl ticket's choice. One token of
lookahead settles the parse: no variant can stand next to `..` or `..=`, so `K` has one meaning there. Rejecting the
form forces `0..=5` magic numbers or a guard, and a guard does not count toward exhaustiveness. The spec text must
state the folding rule (const item of Int, sized-integer or Char type, resolved by the normal §3.4 path, value folds at
typecheck, a cycle is an error), as min and plt ask." Concern: "If B wins, a bound that names a limit loses its name or
its coverage check, and a later panel must reopen §2.21 item 4 to add the form back."

**web — Vote: A.** Reasoning: "A JS, Python or Rust dev who writes `0..=MAX_RETRIES` expects it to work. The spec already
shows that form in §2.21 item 4. Today the user gets a C compile error far from the cause, and under B the user must
replace a named limit with a magic number or give up exhaustiveness through a guard. The position rule is one sentence
(\"a range bound is a literal or a const name\"), and the `K =>` help line teaches the one asymmetry. I accept the
narrowing: only `const` items of Int, sized-integer or Char type, resolved by the normal §3.4 path, no local shadowing,
value must fold at typecheck, a cycle is an error, and the spec text states the folding rule. The text at 3181 gains the
clause \"except a const named as a range bound\"." Concern: "If B wins, `0..=MAX` becomes a hard error with no
named-constant form, so users will copy literals into arms and the constant and the arms will drift apart."

**devops — Vote: A.** Reasoning: "The compiler already accepts `0..=K`, and §2.21 item 4 already shows
`1..=MAX_RETRIES`. A user who writes it and gets a parse error will lose the named constant and must write a magic
number. The other way out is a guard, which loses the exhaustiveness check. Both give worse code than the const bound.
The parser reads `NAME ..` and `.. NAME` with one token of lookahead, so the token has one meaning there.
Go-to-definition and hover on a const bound reuse the existing const resolution, so the tooling needs no new rule. I want
the spec text to state the fold rule (a `const` of Int, sized-integer or Char type, resolved by §3.4, folding to an
integer or Char value at typecheck), and one clause at 3181 for \"except a const named as a range bound\"." Concern: "The
split between `K =>` (error) and `0..=K` (valid) is a position rule, so some users will try `K =>` first; the help line
\"use a guard: `x if x == K`\" must ship with the error or the rule has no teacher."

**plt — Vote: B.** Reasoning: "Line 3181 states that no value binding, local or module-scope, changes what a pattern
means. A const bound breaks that sentence at its first use, and it adds a resolution step (§3.4 path, shadowing,
folding, cycles) to a grammar that today needs none. The 5-0 \"compile-time constant bounds\" vote holds for literals,
so it does not require names. Soundness is the same either way, but the literal-only rule is closed under pattern
syntax: the checker reads every bound from the pattern text alone. Adding names later breaks no code; removing them
later does." Concern: "Users lose exhaustiveness checking on `0..=MAX_RETRIES` (a guard never counts as covering) or
must write magic numbers, and the tooling must teach this through the `RangeBoundNotLiteral` help text."

**aiml — Vote: B.** Reasoning: "A model that learns from the spec alone does best with one rule: a pattern holds
literals and nothing else, so it never chooses between a name, a qualified name and an expression. Option A makes `K =>`
an error and `0..=K` legal. The model must learn that a name changes meaning by position, and must also learn the fold
rule, the Int/sized/Char type filter, the shadowing exclusion and the cycle error. A model that writes `0..=MAX` under B
gets one error at the first compile, with a guard in the help text, so the repair costs one step. Adding const bounds
later breaks no code; removing them later does." Concern: "If B wins, users and models that write `1..=MAX_RETRIES` (a
form that §2.21 shows today) must switch to a magic number or a guard that loses the exhaustiveness check, and the help
text must teach that well."

**min — Vote: B.** Reasoning: "A const name after `..=` is the first place a value name changes what a pattern means,
while `K =>` stays an error. That makes a position-dependent rule, and it breaks the sentence at 03_types.md:3181 that
no value binding changes what a pattern means. The decided 5-0 vote needs a bound fixed at compile time, and a literal
is that. Adding const bounds later breaks no code; removing them later breaks code. A guard (`n if n >= 1 && n <= MAX`)
gives the same result at a few more tokens." Concern: "Users lose exhaustiveness checking on `0..=MAX_RETRIES` and
write magic numbers instead, and a later panel may need to add const bounds with a full resolution and folding rule."

##### Q2. The W0706 *Patterns* text

Options: A, the devops text (quoted in the Summary). B, the min text: "**Patterns.** No pattern form can write `-0.0`,
because a Float literal is not a pattern. A change that adds a Float literal pattern must bring it under W0706 or make
it an error."

**sys — Vote: A.** Reasoning: "devops's text names the cause (no pattern form can write a Float) and keeps the forward
sentence for the next change. It is also the text most seats already took. Both texts state the same fact, so I do not
stake the vote on wording." Concern: "Under B, \"Float literal pattern\" ties the sentence to one syntax; a future Float
pattern form that is not a literal would fall outside the forward rule."

**web — Vote: A.** Reasoning: "The text states the present fact and names the cause (no pattern form can write a
Float). It keeps the forward rule that the Q5 panel set. It is also what sys, aiml and I took in Phase B. B says the same
thing with slightly different wording, so I do not oppose it." Concern: "The forward sentence will go stale if a later
change adds Float patterns without anyone reading the W0706 section."

**plt — Vote: B.** Reasoning: "B states the cause (a Float literal is not a pattern), says what is true now (`-0.0`
cannot be written), and keeps the forward sentence that makes a later Float-pattern change face W0706. The sentence \"a
change that adds a Float literal pattern\" names the exact form that would break the invariant, which is a precise
typing-rule trigger. A and B differ only in wording; both are sound." Concern: "If a later change adds Float patterns
under another name (for example, a Float range bound), the text \"Float literal pattern\" could be read as not covering
it."

**devops — Vote: A.** Reasoning: "The text states the present fact and the cause: no pattern form can write a Float. It
keeps the forward sentence, so the next change that adds Float patterns must bring them under W0706 or make them an
error. It is the same length as B and says \"Float patterns\" in the forward sentence, which is the term a later change
will use." Concern: "If B wins, nothing breaks; \"Float literal pattern\" is a little narrower than \"Float patterns\", so a
future change that adds a non-literal Float pattern form could slip past the forward sentence."

**aiml — Vote: A.** Reasoning: "devops's text names the cause (no pattern form can write a Float) and states the
present fact, so a model reading it learns the rule and not only the symptom. It keeps the forward sentence for the next
change. B says the same in more words; I prefer the text four seats already took." Concern: "\"Float patterns\" in the
forward sentence is looser than \"Float literal pattern\", so a later change that adds a non-literal Float form (for
example a const Float name) may read as outside the rule."

**min — Vote: A.** Reasoning: "Text A states the present fact and keeps the forward sentence, and it is the shorter of
the two. It says why no pattern writes `-0.0`: no pattern form can write a Float. Text B says the same with more
words." Concern: "Neither text stops a later change from adding a Float pattern form without reading W0706, so the
sentence only works if a reviewer finds it."

#### Phase D — Focused round on Q1

Q2 was settled at 5-1 and not debated again. D1 was a debate of Q1; each seat answered the strongest argument against
its vote. No seat changed its vote. Quoted:

**sys (A)**: "A const in a bound never binds a name and never changes the shape of a pattern; it supplies a number. Line
3181 guards against a typo such as `Dott` or `MAX` turning into a binding that matches every value. A const bound cannot
do that." "plt says adding later breaks no code and removing later does. That holds, but the form is in §2.21 item 4
today, so B is a removal now."

**web (A)**: "'Add later, remove never' assumes the form does not exist. It does. §2.21 item 4 documents
`1..=MAX_RETRIES` and gen1 accepts `0..=K` today. Option B removes a documented form."

**devops (A)**: "The irreversibility argument cuts the other way here ... Option B is a removal of a documented form,
not a deferral." "A cycle is an error the const resolver already reports for any const. These are existing rules reused,
not new machinery."

**plt (B)**: "I grant this cost. It is the best case for A, and I did not weigh the drift risk enough in Phase C." "If B
is wrong, a later panel adds names under one complete rule, and no program breaks. If A is wrong, we cannot remove them
without breaking programs that use them."

**aiml (B)**: "The sys and web claim that a position rule is \"one sentence\" holds only for the parse. It does not hold
for the resolution rules that A adds behind it." If A wins, aiml asks that the spec state all five rules in the text.

**min (B)**: "Drift is a style risk. A name in a pattern changes what the pattern means, and that is a rule risk." If the
tie breaks to A: "The spec text, not the compiler, states which consts qualify".

D2 was a second silent ballot on Q1 only:

| Seat | D2 vote | Concern, quoted |
|---|---|---|
| sys | A | "If A wins, the position rule (`K =>` is an error, `0..=K` is valid) will catch users who try `K =>` first, and the rule has no teacher unless the help line \"use a guard: `x if x == K`\" ships with the error." |
| web | A | "The asymmetry between `K =>` (error) and `0..=K` (valid) will trip users who try `K =>` first, so the help line must ship with the error or the rule has no teacher." |
| devops | A | "The split between `K =>` (error) and `0..=K` (valid) depends on position, so users and models will try `K =>` first, and the rule has no teacher unless the help line ships in the same change." |
| plt | B | "Users lose the exhaustiveness check on `0..=MAX_RETRIES` or write magic numbers that drift from the constant, and the `RangeBoundNotLiteral` help text must teach the guard well." |
| aiml | B | "If B wins, `1..=MAX_RETRIES` (the form §2.21 shows today and that models write first) becomes an error, and users may copy literals into arms so the constant and the arms drift apart." |
| min | B | "Users lose the exhaustiveness check on `0..=MAX_RETRIES`, and the literals in arms drift from the constant." |

Reasoning quoted from D2: **sys (A)**: "A const bound folds to an integer or Char at typecheck, so the match lowers like a
literal arm and costs nothing at run time. The checker already folds consts for array sizes and the other §2.21
contexts, so range bounds reuse that fold and add no new machinery." **plt (B)**: "gen1 never compiled `0..=K` (the C
build fails with `K undeclared`), so no working program relies on it, and the §2.21 example is a spec line the ticket
asks us to settle." **min (B)**: "the spec is a blueprint, not a record of what gen1 accepts." **web (A)**: "the open
ticket is a bug about a wrong C name, not a request for a new feature."

Result: 3-3 -> user broke tie for A (sys, web, devops + BDFL). The owner gave no reasoning with the ruling.

### Final Spec

Pattern Grammar (§3.5):

```
|   INT_LIT
|   "-" INT_LIT
|   BOOL_LIT
|   STR_LIT
|   CHAR_LIT
|   range_bound ".." range_bound
|   range_bound "..=" range_bound
range_bound ::= INT_LIT | "-" INT_LIT | CHAR_LIT | IDENT | IDENT "." IDENT
```

Locked points:

- `-` INT_LIT is a literal pattern and a range bound. `(-1)` and `-(1)` are not patterns. Under an unsigned scrutinee
  a negative literal or bound is E0318, as before.
- A Float literal is neither a pattern nor a bound: `FloatLiteralPattern` (E0322). The help names a guard.
- A const expression is never a bound: `RangeBoundNotConst` (E0323). The help names a guard.
- A const name is a bound only, never a pattern by itself. `K =>` stays E0308, and its help names a guard.
- A const name is the name of a `const` item of Int, sized-integer or Char type, bare or qualified, resolved by the §3.4
  normal path. A local does not change the resolution. The value folds at type check. A cycle is an error. E0318 applies
  to the bound.
- §3.5 *Bare names* gains "except a `const` item named as a range bound". §2.21 item 4 stays, narrowed to a literal or
  a const name.
- The W0706 *Patterns* bullet reads as Q2 A.

### Reading Gaps and Open Points

The ruling left these points to the writer. Each reading is the least that fits the ruling.

- **Help on `K =>`.** The ruling asks that E0308 gain the help "use a guard: `x if x == K`". The spec text for E0308
  already shows the guard help when a value of that name is in scope, so the spec text did not change.
- **Cycle code.** The ruling says a cycle is an error and a non-const expression has "one diagnostic". The spec puts a
  cycle, a non-const name and an expression under the one code E0323.
- **Type of a const bound.** The ruling says "E0318 applies to the bound". The spec says the value must fit the
  scrutinee type. It does not say whether a `const K: Int` may bound an `I8` scrutinee when its value fits. This is open.
- **Error numbers and the name `RangeBoundNotConst`.** The writer chose them. The panel used working names.
- **Examples that gen1 rejects.** The spec leads the compiler. gen1 rejects `-1`, `-128..=-1` and `0.5 =>` with
  UnexpectedToken, and its C build of `0..=K` fails. The examples stay in the spec.
- **Codegen of a const bound.** The spec states none. This is for the implementation.

### Sibling Branches

Other spec branches touch nearby text. None contradicts this decision, but these need a check when they land:

- The numeric-literal grammar branch says patterns use the same two number tokens. That sentence no longer holds for
  Float.
- The module-init const branch edits the "four contexts" list beside §2.21 item 4.
- The qualified struct pattern branch and the brace pattern head branch edit the Pattern Grammar and *Bare names* text
  near these edits.

