[< All Decisions](../DECISIONS.md)

# A Cyclic Type Alias (E0327) — Design Rationale

§3.4 says an alias gives a second name to a type, and that an alias creates no type. No text covered an alias whose
expansion returns to itself. On the compiler then, `blink check` passed, and the build then failed: a C compiler error
(`unknown type name`) or a core dump of the compiler, depending on the shape.

```blink
type A = A
fn f(x: A) -> Int { 0 }                 // check: ok. build: GeneratedCDidNotCompile

type A = B
type B = A
fn f(x: A) -> Int { 0 }                 // same

trait Sh { fn n(self) -> Int }
type A = A2
type A2 = A
impl Sh for A { fn n(self) -> Int { 1 } }   // same

type L = List[L]
fn f(x: L) -> Int { x.len() }           // check: ok. build: the compiler dumps core
```

The panel decided the error name, the code, the span, how many reports a cycle gets, the note, whether a cycle through
a type argument is the same error, and what a use of such an alias does.

## Summary

| Q | Question | Result | Vote |
|---|---|---|---|
| Q1 | Adopt one new error, E0327 `CyclicTypeAlias`, for every alias whose expansion reaches itself (through aliases, type arguments, tuples, fn types and generic aliases); one error for each cycle; the help is text only | A: adopt | 6-0 |
| Q2 | The primary span | B: the reference in the right-hand side that leads round the cycle | 6-0 |
| Q3 | Labels on the other aliases of the cycle | B: no labels; the chain note gives each link with `path:line` and a qualified name for an alias in another module | 6-0 after 4-2 in Phase C |
| Q4 | The help for a cycle with no type constructor | A: point one alias in the chain at a type that is not in the chain; the struct form only when a type constructor is in the cycle | 6-0 |
| Q5 | An alias whose right-hand side has another error (`type A = Nope`) | A: one poison rule, in this decision | 6-0 after 3-3 in Phase C |

Points all six seats stated, not balloted:

- E0327 is a new code. E0324 `InstantiationCycle` is about type arguments that grow in generic instances; it runs only
  when the front end finds no error. A cycle of aliases has no meaning at all, and `blink check`, the LSP and the daemon
  report it with the other front-end errors.
- A struct or enum name stops the walk. `type Kids = List[Node]` with `type Node { kids: Kids }` stays legal.
- Recursion through an alias is not legal. Equi-recursive aliases were offered and rejected by their own authors (PLT P2,
  AI/ML P2).
- The walk follows declarations, not the type arguments of a use. `type P[X] = List[X]` used as `P[P[Int]]` is legal.
- `type G[T] = G[List[T]]` and `type G[T] = List[G[T]]` are E0327, not E0324.
- An impl on an alias that has the poison type is dropped with no error, and its methods leave method lookup, so
  MVCE 3 gives exactly one error.
- The new error ships as an error at once, with a CHANGELOG Breaking Changes line (pre-1.0 rule). Rollout is not a
  panel question.

## Final spec

```blink
type A = A                       // error[CyclicTypeAlias] (E0327): `A` names `A`
type L = List[L]                 // error[CyclicTypeAlias] (E0327): `L` names `L`, inside `List[...]`
type F = fn(Int) -> F            // error[CyclicTypeAlias] (E0327)
type Pair[T] = (T, T)
type PP = Pair[PP]               // error[CyclicTypeAlias] (E0327)
type G[T] = G[List[T]]           // error[CyclicTypeAlias] (E0327), not E0324

type P[X] = List[X]
let grid: P[P[Int]] = [[1, 2], [3]]   // legal
type Node { kids: Kids }              // legal: the walk stops at the struct
type Kids = List[Node]

type A = geo.B                   // in a.bl, with `type B = A` in geo.bl
// error[CyclicTypeAlias] (E0327): type alias `A` expands to itself
//  --> a.bl:1:10
// 1 | type A = geo.B
//   |          ^ `A` names `geo.B`
//   = note: the chain is `A` (a.bl:1) -> `geo.B` (geo.bl:4) -> `A`

type A = Nope                    // error[UnknownType] (E0507), once, at `Nope`
fn f(x: A) -> Int { x.len() }    // no second error
```

- §3.4 *Newtypes*, new paragraphs after the E1110 sentence: the cycle rule with an example for each edge case; one
  error for each strongly connected component; the span and the label; the chain note with `path:line`; the two help
  shapes; the poison rule.
- ERROR_CATALOG: new row E0327 `CyclicTypeAlias`. A cross-reference in the E0324 and E0507 rows. The §3.4 *Limit on
  Generic Instances* text says that a cycle through aliases only is E0327.
- Every alias declaration is checked, used or not. `blink check` reports the error.
- One error for each strongly connected component. The first alias is the first by file path, then by position in the
  file.
- The primary span is the reference in that alias's right-hand side that leads round the cycle. The label is
  "`A` names `B`", and "`A` names `A`" for `type A = A`. No label on the other aliases.
- The chain note lists every link in a fixed order that starts at the alias with the primary span, with the
  `path:line` of each link and a qualified name for an alias in another module. The `--json` form holds the edge list,
  with a span for each edge.
- The help is text only, with no machine-applicable fix. If no edge of the cycle goes through a type constructor, it
  says to point one alias in the chain at a type that is not in the chain, and names no type. If any edge goes through
  one, it writes the struct form whole, with a field name, as `type L { items: List[L] }`.
- One poison rule: an alias whose right-hand side does not resolve to a type has the poison type (§6.3.5). This covers
  each alias in a cycle, each alias that leads into a cycle (which gets no error of its own) and an alias whose
  right-hand side has another error. The poison hides no unrelated error at a use. An impl on such an alias is dropped
  with no error, and its methods leave method lookup.
- A new code, E0327. E0324 keeps its meaning.

## Panel Deliberation

### Panel: Systems, Web/Scripting, PLT, DevOps, AI/ML, Minimalism

#### Phase A — Independent proposals

All six seats proposed one option (O1): a new error E0327 `CyclicTypeAlias`, one error for each cycle, every alias in
the cycle has the poison type, a text-only help. They differed on the span, labels on the other aliases, the help for a
cycle with no type constructor, and an alias whose right-hand side has another error.

- **Systems:** "Systems seat, Phase A proposal: a cyclic type alias is a new error, E0327 CyclicTypeAlias, raised when declarations are collected. It applies to every cycle, including one through List, Option or fn."
- **Web/Scripting:** "Rule a JS/Python dev learns in one line: "an alias is a second name. It must end at a real type. If following the names brings you back to the start, that is an error.""
- **PLT:** "Any cycle in this graph is an error. This is a syntactic check on declarations: it needs no unification and no type arguments, so it covers aliases that nothing uses, and runs before type checking."
- **DevOps:** "A new code, E0327 `CyclicTypeAlias` ... Not E0324: E0324 runs only when the front end has no error, and it is about copies of generics. An alias cycle is a name-resolution fault: the type has no meaning at all."
- **AI/ML:** "One rule for the model to learn: "an alias must reach a non-alias type in finite steps; to recurse, declare a struct or enum.""
- **Minimalism:** "Rule: to expand an alias, put its right side in its place. If the expansion reaches an alias that it is still expanding, and no struct or enum stands between them, that is `error[CyclicTypeAlias]` (new code E0327, the next free code after E0326)."

PLT measured a second fault: `type A = Nope` gives E0507, then a second error at a use of `A`. PLT proposed that such an
alias also has the poison type. Seven shapes passed `blink check` before: `type A = A`, `type A = B` with `type B = A`,
`type L = List[L]`, `type O = Option[O]`, `type F = fn(Int) -> F`, `type P[T] = Q[T]` with `type Q[T] = P[T]`, and
`type G[T] = List[G[T]]` (DevOps, Systems and AI/ML measured them).

#### Phase B — Debate highlights

A mechanical digest set four variations to settle: V1 the primary span, V2 labels on the other aliases, V3 the help for a
cycle with no type constructor, V4 an alias whose right-hand side has another error. All six seats ended Phase B stable.

- **AI/ML:** "V1 -> V1b (I switch from V1a). The reference in the right side is where the edit goes, so a model that patches at the caret patches the right token."
- **DevOps:** "V1: **V1b.** The squiggle goes where the fix goes. The user edits the right-hand side, not the name."
- **Systems:** "V3 = V3a. For `type A = A` or `A = B = A`, no recursion was meant. The user wanted some other type, often an imported `A` whose name the alias shadows. A help that writes a struct sends them the wrong way."
- **PLT:** "V3: I change to V3a. My V3b help is wrong for `type A = A` and `type A = B` / `type B = A`. With no type constructor in the cycle, no recursive type was intended. A struct help makes up a meaning the user did not write."
- **Web/Scripting:** "V2: V2a. For a 2- or 3-alias cycle, showing each line with a short label is what makes the chain click."
- **Minimalism:** "V2: V2b. The chain note already names each alias. Secondary labels add a second render path, plus a cross-file case and an LSP relatedInformation case, and they give no fact that the note does not give."

Two requests for the writer came out of Phase B:

- DevOps: "One wording request: the E0327 catalog row should say "one error per strongly connected component". "Per cycle" is ambiguous for two cycles that share an alias"
- Systems: "The walk follows each alias's declaration, never instance arguments. `type P[X] = List[X]` used as `P[P[Int]]` is legal, and the text must say so."

#### Phase C — Final vote

Q1 A 6-0, Q2 B 6-0, Q4 A 6-0. Q3 B 4-2 (Web/Scripting and DevOps for A). Q5 A 3-3 (Systems, Web/Scripting and PLT for A).

- **Q1: Adopt O1 (new error E0327, one error for each cycle, poison on the cycle, text-only help)** (A 6-0)
  - **Systems:** A — "An alias creates no type, so its expansion must end. A C typedef cannot refer to itself either."
  - **Web/Scripting:** A — "One rule, one code, and `blink check` catches what now ICEs or dumps core."
  - **PLT:** A — "An alias is a transparent abbreviation, so replacing it with its right-hand side must end."
  - **DevOps:** A — "Today `blink check` passes, and then the build crashes in the compiler."
  - **AI/ML:** A — "Checking every alias, used or not, removes "legal until used", which a model cannot learn from the spec."
  - **Minimalism:** A — "O1 adds one error code and no syntax."
- **Q2: Primary span (the reference in the right-hand side that leads round the cycle)** (B 6-0)
  - **Systems:** B — "The reference in the right-hand side is the edge you change to break the cycle, so the caret sits on the fix."
  - **Web/Scripting:** B — "The caret goes on the token the user must change."
  - **PLT:** B — "The edge is the fault, and the fix (change what the alias names) goes on that reference."
  - **DevOps:** B — "Put the caret where the user makes the edit."
  - **AI/ML:** B — "The caret sits on the token a fix changes, so a model that patches at the span patches the right place."
  - **Minimalism:** B — "The reference on the right-hand side is the edge that makes the cycle, and it is the place to edit."
- **Q3: Other aliases of the cycle (labels, or the chain note only)** (B 4-2 (Web/Scripting and DevOps for A))
  - **Systems:** B — "One span plus a chain note is E0324's shape, and the render is the same whether the cycle sits in one file or several."
  - **Web/Scripting:** A — "For a cycle of two or three aliases, a label on each line shows the loop at a glance."
  - **PLT:** B — "The chain note already names each alias, and the `--json` edge list gives tools a span for each edge."
  - **DevOps:** A — "A note with names only gives a terminal user no line for each link, and a cycle can cross files."
  - **AI/ML:** B — "The chain note gives everything a model needs, at lower token cost, and a long cycle does not grow into a wall of labels."
  - **Minimalism:** B — "Secondary labels add a cross-file render case and an LSP case and give no new fact."
- **Q4: Help for a cycle with no type constructor** (A 6-0)
  - **Systems:** A — "A cycle with no type constructor in it is almost always a typo or a shadowed import, not a wish for recursion."
  - **Web/Scripting:** A — "`type A = A` or `A = B`, `B = A` is a typo or a bad rename, not a try at recursion."
  - **PLT:** A — "When no type constructor is in the cycle, the user did not mean a recursive type, and a struct help makes up a meaning they never wrote."
  - **DevOps:** A — "A cycle of plain renames is a typo or a rename that was left half done."
  - **AI/ML:** A — "`type A = B` / `type B = A` is nearly always a typo or a half-done rename."
  - **Minimalism:** A — "The usual cause of `type A = B` / `type B = A` is a typo or a rename that is not finished, not a wish for recursion."
- **Q5: An alias whose right-hand side has another error (`type A = Nope`)** (A 3-3 (Systems, Web/Scripting and PLT for A; DevOps, AI/ML and Minimalism for B))
  - **Systems:** A — "It is the same mechanism: an alias that does not resolve has the poison type."
  - **Web/Scripting:** A — "It uses the same poison mechanism and keeps the same §6.3.5 promise."
  - **PLT:** A — "It is one rule: an alias whose right-hand side does not resolve to a type has the poison type, and a cycle is one case of that."
  - **DevOps:** B — "But it is a different diagnostic (E0507 and its cascade), with its own tests and catalog text, and it must not widen this P0 fix."
  - **AI/ML:** B — "`type A = Nope` already has its own code (E0507). Its follow-on error belongs in the general poison rule (§6.3.5), not in the cycle text, and mixing them widens a P0 ticket."
  - **Minimalism:** B — "An unknown type on the right-hand side is a different fault (E0507) with its own path."

Concerns the seats put on record, which the text answers:

- Systems, Q1: "the walk must follow alias declarations only, never instance arguments. Otherwise `type P[X] = List[X]` used as `P[P[Int]]` becomes a false positive."
- PLT, Q4: "A cycle through a generic alias (`type PP = Pair[PP]`) must count as having a type constructor, because Pair expands to a tuple"
- DevOps, Q4: "The code that picks between the two helps must test for "any type constructor on the cycle path", not "on the first edge"."
- Minimalism, Q4: "the text-only help must not suggest a type from outside the chain that it cannot know is right, such as `Int`, as if it were the fix."
- Minimalism, Q1: "if the impl that the error drops does not also leave method lookup, a call site still gets a second error, so the "one error" promise breaks."
- Systems, Q5: "the poison does not also hide errors at uses that are unrelated to the alias."

#### Phase D — Focused debate and re-vote (Q3, Q5)

**Q3: 4-2 to 6-0.** Web/Scripting and DevOps moved to B once the chain note had `path:line` for each link. All six seats
asked for that condition, so it is part of the ruling and not a wording note.

- **Web/Scripting:** "Q3: I CHANGE to B, on one condition. My only point for labels was that the reader should not have to hunt for each alias."
- **DevOps:** "Q3: **move to B**, on one condition: the chain note gives `path:line` for each alias that is outside the primary file."
- **Systems:** "B can grow into A later with no break: adding labels changes no code, no span and no JSON. Going from A back to B would remove output that tools may parse."
- **PLT:** "Then the note carries every location, the render is the same for one file or many, it matches E0324, and the label-cap rule that both A voters already say they need goes away."
- **AI/ML:** "Labels on short cycles look nice, but they cost tokens on every link and need a cap rule for long cycles ("8 then N more")."
- **Minimalism:** "That gives one form, a line for each link, no cap, and it works the same across files."

Re-vote, Q3: B 6-0. Concerns on record:

- Systems: "the note must keep its link order fixed: it starts at the alias that holds the primary span. A test must pin the order across modules."
- PLT: "The path:line and module-qualified name in the note must be pinned by a test with a cycle that crosses modules"
- Minimalism: "a long chain gives a long note on one line, so the writer may need to wrap it with one link per line."

**Q5: 3-3 to 6-0.** DevOps, AI/ML and Minimalism moved to A. The seats on B had objected to the size of a P0 fix, not to the
rule. PLT and Systems answered that the spec may lead the compiler, and that the implementation can land the cycle case
first and the E0507 case second.

- **PLT:** "So: the spec sentence for this ticket says "an alias whose right-hand side does not resolve to a type (a cycle, or an E0507 or other error in it) has the poison type; its uses get no second error"."
- **Systems:** "Once the spec states the rule, that case is a compiler bug against the spec, not a new spec question."
- **Web/Scripting:** "This ticket decides spec text, not the size of the commit."
- **DevOps:** "Web and Sys raised one limit, and I agree with it: the poison stays in the alias resolver. E0507 still fires once, at the right-hand side, and no unrelated error at a use is hidden."
- **AI/ML:** "Two narrower rules are harder to learn from the spec than one general rule"
- **Minimalism:** "PLT's argument is the stronger minimalism argument, and I weighed it too lightly."

Re-vote, Q5: A 6-0. Concerns on record:

- AI/ML: "The poison could hide real, unrelated errors at uses or spread into impl lookup. The E0507 case needs its own tests, which show E0507 fires once and that only errors caused by the alias go silent."
- Minimalism: "the implementer may treat the E0507 case as covered by the cycle tests, so it needs its own test that shows E0507 fires once and that a use of `A` gets no second error."

#### Dissents

None on the final votes. In Phase C, Web/Scripting and DevOps dissented on Q3, and DevOps, AI/ML and Minimalism dissented
on Q5. All five moved in Phase D.
