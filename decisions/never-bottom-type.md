[< All Decisions](../DECISIONS.md)

# The `Never` Bottom Type — Design Rationale

§2.20 said `panic` returns `Never` "(bottom type), which inhabits every type". §3.7 said there is no
"bottom type that inhabits every type". The two sentences disagreed. §3.3 already treated `Never` as
a subtype of every type with no values, and the prelude table listed `Never` as a type name. The
compiler has an internal `Never` type, but writing `Never` in source fails with `UnknownType`. The
panel decided whether a nameable bottom type exists, where the spec defines it, and what rules come
with it.

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated
in independent-proposal → debate → vote rounds.

Facts surfaced to the panel by the moderator:

- **F1:** both contradictory sentences use the phrase "inhabits every type". §3.3 says `Never` has no
  values and is a subtype of every type.
- **F2:** §3.3 and the §7 prelude table both cross-reference `Never` to §2.20, but §2.20 has no
  definition of the type.
- **F3:** the type checker has an internal `TyKind.Never`. Writing `Never` in source is
  `error[UnknownType]` in every position tried. The spec leads the compiler here.
- **F4:** earlier rulings already settle that `panic` returns `Never`, that inference never chooses
  `Never` for an open slot, and that `Never`, `()` and `Void` are three distinct things.

#### Phase A — Independent proposals

All six proposed that `Never` be a real, nameable type with no values. Excerpts, each in the
panelist's own words:

- **Systems:** "`Never` inhabits *no* type, because it has zero values. It is a *subtype* of every
  type, which §3.3 already says correctly." And: "Fix the wording, make `Never` a real nameable
  type, and §3.7 stays true about what it was meant to forbid."
- **Web/Scripting:** "The bug is in the wording, not the design." And: "Name the type now,
  everywhere."
- **PLT:** "So one sound reading exists: `Never` is a real, nameable, empty type, and the only thing
  §3.7 forbids is a value that is a member of every type." And: "Required arms are sound, decidable
  and modular."
- **DevOps:** "An LSP hover on `Never` would show nothing." And: "The quick-fix an AI agent applies
  would quietly turn a diverging helper into a returning one."
- **AI/ML:** "A model that reads §2.20 and §3.7 learns two opposite facts." And: "If the spec says
  nothing, models will guess, and some will copy Rust's newer uninhabited-arm elision."
- **Minimalism:** "The fix should delete or narrow text and add nothing new." And: "`Never`
  implements no trait unless the prelude declares an impl."

#### Phase B — Debate highlights

One round. All six reported stable.

- **Systems** on the definition's home: "Every other type name is defined there, and it gives the
  LSP hover one target."
- **Web** **(dissent withdrawn)** moved to §3.2: "I drop my §3.3 placement."
- **PLT** **(dissent withdrawn)** moved to §3.2: "I drop §3.1 and back §3.2, where the other
  built-in types are listed."
- **Systems** **(dissent withdrawn)** withdrew the match-arm pruning rule S2: "I CHANGE POSITION. The
  arm is required (plt P3, aiml P2, devops P3). I withdraw S2." And: "If arm pruning depended on the
  mono instantiation (`T = Never`), exhaustiveness would depend on codegen-time types."
- **PLT** on why pruning does not compose: "A generic `fn f[E](r: Result[Int, E])` must keep the
  `Err` arm, and the same match written with a concrete `Never` drops it."
- **Web** on the match rule: "One rule is fewer Stack Overflow questions."
- **PLT** on lifting through type constructors: "For a mutable, aliased `List` that assumption is
  unsound."
- **AI/ML** on the same point: "So I support it on one condition: the mismatch diagnostic's help
  line must name the repair (`.map_err(fn(e) { e })`)."
- **Minimalism** **(dissent)** on the re-wrap idiom: "`map_err(fn(e) { e })` leaves `F` open with
  only a `Never` body to infer from, which is the exact substitution §3.4 bans."
- **Minimalism** **(dissent)** on "Elimination is subsumption": "OPPOSE as spec text. It follows
  from `Never <: R`, and a sentence that only restates another rule gives readers two places to keep
  in sync."
- **PLT** on the effects sentence: "If §4 already says that, I accept dropping the effects
  sentence."
- **Systems** on traits: "I still want *which* prelude impls `Never` gets (`Debug`? `Display`?) to
  go to its own ticket, when real friction appears."
- **DevOps** **(dissent withdrawn)** on the unreachable-code lint: "DEFER to its own ticket. I am
  changing my position."

#### Phase C — Final vote

- **Q1: Is `Never` a real prelude type with no values, writable in any type position?**
  (6-0, A: adopt)
  - **Systems:** A — "A nameable type with no values costs nothing at run time."
  - **Web/Scripting:** A — "One definition and no position limits is the familiar design that just
    works."
  - **PLT:** A — "The two spec lines do not disagree about types; they disagree about a word."
  - **DevOps:** A — "Hover, go-to-definition, the prelude table and `blink llms --topic types` each
    need one nameable target."
  - **AI/ML:** A — "Today a model that reads §2.20 and §3.7 learns two opposite facts about one
    type."
  - **Minimalism:** A — "The merged rulings already put `Never` into the language."

- **Q2: Where does the one definition live?** (6-0, A: §3.2 *Built-in Types*, as a full paragraph)
  - **Systems:** A — "§3.2 defines every other built-in type, so it gives the LSP hover and `blink
    llms` one place to find `Never`."
  - **Web/Scripting:** A — "A newcomer who sees `Never` in a signature looks in the built-in types
    list, not inside the divergence rules."
  - **PLT:** A — "I drop my §3.1 placement."
  - **DevOps:** A — "A full paragraph gives the hover a real sentence, not only a code-block
    comment."
  - **AI/ML:** A — "When a model meets a type name, it looks in the built-in types list."
  - **Minimalism:** A — "§3.2 already lists every built-in type, so this needs no new heading or
    subsection."

- **Q3: How does §3.7 word the narrowing?** (split in Phase C: B 3 — PLT, DevOps, AI/ML; A 1 —
  Systems; D 1 — Minimalism; E 1 — Web. Sent to Phase D)
  - **Systems:** A — "the call is `noreturn` and control does not come back"
  - **Web/Scripting:** E — "tells a JS developer in one step that `Never` is not `undefined`."
  - **PLT:** B — "It moves the forbidden thing from the type level to the value level, which is the
    correct invariant."
  - **DevOps:** B — "so a reader who searches for that term finds both §3.2 and §3.7 and sees they
    agree."
  - **AI/ML:** B — "with fewer words than my own draft C."
  - **Minimalism:** D — "§3.7 is about null, not about divergence, so the sentence should only point
    to §3.2 and stop."

- **Q4: Does the §3.2 definition say that no literal, constructor or conversion makes a `Never`?**
  (6-0, A: include)
  - **Systems:** A — "This is the guarantee the backend depends on: no instruction ever holds a
    `Never` value, so the type needs no runtime representation."
  - **Web/Scripting:** A — "One sentence that says no literal, constructor or conversion makes one
    stops that guess before the compiler has to."
  - **PLT:** A — "One sentence now blocks a whole class of future unsound additions."
  - **DevOps:** A — "and stops completion or an agent from offering `Never()` or
    `Never.from(...)`."
  - **AI/ML:** A — "Without this sentence, models invent `Never()`, `Never.new()` or a cast, because
    every other type has a way to make a value."
  - **Minimalism:** A — "This sentence takes something away: it closes the door on `Never.new()`, a
    cast, or an FFI path that makes a value."

- **Q5: Does the definition state "elimination is subsumption"?** (split in Phase C: B 3 — Web,
  DevOps, AI/ML; A 1 — Systems; C 1 — PLT; D 1 — Minimalism. Sent to Phase D)
  - **Systems:** A — "One sentence in the definition tells the reader that no eliminator function
    exists and none is needed, and that the step is a check-time fact with zero codegen."
  - **Web/Scripting:** B — "says the same thing and shows the one idiom users need."
  - **PLT:** C — "The place a reader needs it is the match idiom `Err(e) => e`, so a note there
    gives the effect without a second normative statement."
  - **DevOps:** B — "A hover must read in plain words"
  - **AI/ML:** B — "Models learn from examples more than from rules."
  - **Minimalism:** D — "A sentence that only restates another rule gives readers two texts to
    reconcile and implementers two places to edit."

- **Q6: Does the definition carry the handler-must-abort sentence?** (split in Phase C: B 4 —
  Systems, PLT, AI/ML, Minimalism; A 2 — Web, DevOps. Sent to Phase D)
  - **Systems:** B — "A handler rule in the type definition puts a §4 rule in two places."
  - **Web/Scripting:** A — "One sentence in the definition answers that where they will look, at the
    type."
  - **PLT:** B — "So the handler rule follows from the type and belongs in §4."
  - **DevOps:** A — "One sentence costs little and gives the diagnostic a section to cite."
  - **AI/ML:** B — "The rule about how a handler for a `-> Never` op ends belongs in §4, where a
    model looks when it writes a handler."
  - **Minimalism:** B — "The handler-must-abort rule is about handlers, not about the type, and it
    follows from the types: there is no value to resume with."

- **Q7: Must a `match` have an arm for a variant whose payload type is `Never`?** (6-0, A: arm
  required, no pruning)
  - **Systems:** A — "Arm pruning that depends on the mono instantiation makes exhaustiveness depend
    on codegen-time types, and a generic body must check once, before mono."
  - **Web/Scripting:** A — "One match rule for every type means fewer surprises and fewer
    questions."
  - **PLT:** A — "A required arm is sound, decidable and modular."
  - **DevOps:** A — "If pruning depended on the mono instantiation, the error would point at a call
    site, not at the `match`."
  - **AI/ML:** A — "One legal form is easier to learn than two."
  - **Minimalism:** A — "A required arm can become optional later without breaking code; the reverse
    change breaks code."

- **Q8: Does `Never <: R` lift through type constructors?** (6-0, A: no lifting)
  - **Systems:** A — "with no lifting, every `Never <: R` step stays a check-time fact with zero
    codegen."
  - **Web/Scripting:** A — "Blink has no variance anywhere else, so this adds no new concept."
  - **PLT:** A — "Covariant lifting is unsound for a mutable, aliased `List`: a write through a
    `List[Int]` alias can be read back through a `List[Never]` alias, which produces a `Never`
    value."
  - **DevOps:** A — "Blink has no variance anywhere, so this states what already holds, and the
    mismatch is the ordinary type-mismatch error with no new diagnostic."
  - **AI/ML:** A — "Sound beats convenient here because the repair is short and explicit."
  - **Minimalism:** A — "Blink has no variance rules today. No lifting keeps that count at zero."

- **Q9: Which re-wrap idiom does the spec show for widening `Result[T, Never]`?** (split in Phase C:
  B 4 — Systems, Web, PLT, Minimalism; A 2 — DevOps, AI/ML. Sent to Phase D)
  - **Systems:** B — "The `match` form needs no closure, so it compiles to a tag check and a rebuild
    with no lambda object and no reliance on the inliner to remove a call."
  - **Web/Scripting:** B — "The `match` form reuses the same `Err(e) => e` arm from Q7, so users
    learn one idiom, not two."
  - **PLT:** B — "The `match` idiom has no such dependency."
  - **DevOps:** A — "`.map_err(fn(e) { ... })` is already the one documented way to change an error
    type (§3c, §5), so the help line for Q8 can name the same method users already know."
  - **AI/ML:** A — "`.map_err(fn(e) { ... })` is already the spec's one idiom for changing an error
    type (§3c, §4, §5 all show it), so models already know it and it costs few tokens."
  - **Minimalism:** B — "The spec should show the idiom that works in every position, not the one
    whose meaning depends on context."

- **Q10: Does `Never` get automatic trait impls?** (6-0, A: no impl unless the prelude declares
  one; a separate ticket picks the impls)
  - **Systems:** A — "is the rule every other type already follows, and it rules out ex-falso
    blanket impls such as `Default`, which would have to make a value that cannot exist."
  - **Web/Scripting:** A — "writing it down stops the ex-falso proposals."
  - **PLT:** A — "Ex-falso blanket impls are only sound for traits whose methods all take a `Never`
    argument (`self` or a parameter)."
  - **DevOps:** A — "With this sentence, a failed bound on `Never` is the ordinary unsatisfied-bound
    error, with no special case in the solver or its messages."
  - **AI/ML:** A — "If the spec says nothing, models fill the gap with Rust's ex-falso intuition and
    expect `Never: Default` or `Never: Display` to hold."
  - **Minimalism:** A — "This states the default that holds for every other type and rules out
    ex-falso blanket impls."

- **Q11: What does the E0311 help say when the declared return type is `Never`?** (6-0, A: name the
  diverging repair, do not offer `Option[R]`)
  - **Systems:** A — "The `Option[R]` help points a diverging helper toward returning a value, which
    is wrong and which an agent will apply automatically."
  - **Web/Scripting:** A — "A help line that tells you to return `Option[Never]` is a wrong fix, and
    both humans and agents apply help lines as written."
  - **PLT:** A — "The only well-typed completions of a `-> Never` body are divergent constructs, and
    the help must list only those."
  - **DevOps:** A — "The current help offers `Option[R]`, a repair that does not fix a `-> Never`
    function, and agents apply help lines as written."
  - **AI/ML:** A — "For generate-compile-fix loops this is the most important item on the ballot."
  - **Minimalism:** A — "This corrects a diagnostic and adds no language feature."

- **Q12: Adopt an unreachable-code lint after a `Never` construct now?** (6-0, A: defer to its own
  ticket, together with the two meanings of W0700)
  - **Systems:** A — "The backend already drops dead code after a `noreturn` call, so nothing at run
    time depends on this lint."
  - **Web/Scripting:** A — "But W0700 has two meanings today, and binding a third to it makes the
    mess worse."
  - **PLT:** A — "Fix the code collision first, then extend the lint, in one ticket."
  - **DevOps:** A — "Adding a third behaviour to a code with two meanings makes the diagnostic
    surface worse."
  - **AI/ML:** A — "A model that reads a diagnostic code and looks it up must find one meaning."
  - **Minimalism:** A — "Adding a third behaviour to a code whose meaning is in dispute adds to the
    mess."

#### Phase D — Round 2

Q3, Q5, Q6 and Q9 split in Phase C. The panel ran one focused debate on them, then re-voted.

**Q3 — §3.7 wording**

- **Web** **(changed E to D)**: "I withdraw E." And: "It is also the shortest text that fixes the
  bug, and §3.2 holds the full definition, as min says."
- **PLT** on E: "Bottom is not the opposite of null: null is a value that belongs to every type, and
  bottom is a type that is a subtype of every type."
- **Systems** **(changed A to B)**: "PLT's concern applies to my own draft too." And: "I keep the
  codegen fact (`noreturn`) for the §3.2 definition, where it belongs."
- **DevOps**: "Min: you named B as your second choice, so B already has the most support."
- **Minimalism** **(changed D to B)**: "I give up the shorter text so the vote can close."

Re-vote (5-1, B; Web dissent, voted D):

- **Systems:** B — "The codegen fact (`noreturn`) belongs in the §3.2 definition, not in the null
  section."
- **PLT:** B — "null is a value in every type, bottom is a type below every type."
- **DevOps:** B — "Five of six panelists now name B as their vote or second choice."
- **AI/ML:** B — "All six panelists now name B as their first or second choice"
- **Minimalism:** B — "I said in Phase D that I would give up the shorter text so the vote can
  close, and I keep that promise."
- **Web/Scripting:** *(dissent)* D — "B is my second choice; its next clause explains the term, so I
  can live with it." Concern: "may still guess that `Never` is a kind of null"

**Q5 — "Elimination is subsumption"**

Minimalism added option E: C placement (the Q7 match note) with B's wording.

- **Systems** **(changed A to B)**: "I move from A to B, on one condition: Q8's no-lifting sentence
  (ballot Q8-A text) comes right after B's sentence in §3.2."
- **PLT** **(changed C to B)**: "B's sentence is not a new rule if it says it is a consequence"
- **Web**: "Put the Q8 no-lifting sentence directly after it."
- **DevOps**: "I accept your condition"
- **Minimalism** **(dissent)**: "a combined option, C placement with B's wording." And: "With one
  example in one place there is nothing to keep in step."

Re-vote (5-1, B; Minimalism dissent, voted E):

- **Systems:** B — "The rule is about the type, so it belongs in the type's definition, where a
  hover or a reader finds it first;"
- **Web/Scripting:** B — "If it sits only in the match note (E), users who meet `let x: Int = e` or
  a `Never` call argument never see it and ask for an `absurd` function."
- **PLT:** B — "E puts it only beside `match`, where readers will still miss the other positions."
- **DevOps:** B — "An LSP hover on `Never` shows the §3.2 definition, not the Q7 match note, so the
  plain sentence must sit in the definition to reach the user at the point of use."
- **AI/ML:** B — "Models learn from a plain rule next to one example."
- **Minimalism:** *(dissent)* E — "The §3.2 definition already says `Never <: R`. A second sentence
  there only restates it." Concern: "If B wins, the conditions must hold as text, not as intent."

Conditions the B voters attached:

- PLT's wording: "Because `Never` is a subtype of every type (§3.3), a value of type `Never` fits
  wherever any type is expected."
- The Q8 no-lifting sentence follows right after it. Systems: "the Q8 no-lifting sentence comes right
  after B's sentence in §3.2, and that the `Err(e) => e` example has one copy, with the Q7 note
  pointing to it."

**Q6 — Effects sentence**

- **Web** **(changed A to B)**: "Sys, plt and min convinced me." And: "Condition: the ruling must
  require §4 to state the general rule in prose, once, for any op declared `-> Never`."
- **DevOps** **(changed A to B)**: "If the type definition and §4 both carry handler text, the two
  will drift apart, which is the reason this ticket exists."
- **Systems**: "Compromise: move option A's handler sentence into §4.4.3 as a general prose rule for
  any op declared `-> Never`."
- **PLT**: "§4 must state the general rule in prose, not only in the `exit` example."
- **Minimalism**: "I accept the condition sys, plt and aiml set: the §4 owner states the general
  rule once in prose"

Re-vote (6-0, B):

- **Systems:** B — "The handler rule follows from the type: `resume` needs a `Never` argument and
  none exists, so the ordinary type error fires with no special case in the checker."
- **Web/Scripting:** B — "A `resume(...)` in a handler for an op declared `-> Never` is already an
  ordinary type error, because no `Never` value exists to pass."
- **PLT:** B — "The handler rule follows from the type: `resume` needs an argument of type `Never`,
  none exists, so a resuming handler is an ordinary type error."
- **DevOps:** B — "My vote for A only asked for one section a diagnostic can cite, and §4 serves
  that purpose if it states the general rule in prose."
- **AI/ML:** B — "A model that writes a handler looks in §4, and §4.6 already shows the `exit`
  handler ending in `abort`."
- **Minimalism:** B — "The handler rule is about handlers, and it follows from the types: `resume`
  needs a `Never` argument, and none exists."

Condition all six attached. PLT: "§4 states once, in prose, the general rule for any effect op
declared `-> Never`"

**Q9 — Re-wrap idiom**

- **DevOps** **(changed A to B)**: "PLT's point decides it for me. Whether `map_err(fn(e) { e })`
  widens depends on inference order, and the spec does not fix that order."
- **AI/ML** **(changed A to B)**: "I CHANGE from A to B." And: "an idiom whose meaning changes with
  context is the worst kind"
- **PLT**: "An idiom whose meaning depends on an unspecified inference order is the wrong one for the
  spec to teach."
- **Web**: "A failure the user cannot see costs more than a loud one."
- **Systems**: "The spec does not fix that order, so the result can depend on how the compiler is
  built."
- **Minimalism**: "The spec should teach the form that fails loudly."

Re-vote (6-0, B):

- **Systems:** B — "The `match` arm is a check point that §3.3 already defines, so `Never <: R`
  applies the same way in every checker."
- **Web/Scripting:** B — "A silent failure costs users far more time than a loud one."
- **PLT:** B — "The `match` form uses only subsumption at an arm check point (`e: Never <: Result[Int,
  Str]`), which §3.3 already defines, so it means the same in every conforming checker."
- **DevOps:** B — "the mismatch appears later at an unrelated call site, which is the worst case
  for diagnostics."
- **AI/ML:** B — "I keep my Phase D change from A to B."
- **Minimalism:** B — "The `match` form uses only `Never <: R` at an arm check point, which §3.3
  already defines, so it adds no new mechanism to explain."

Conditions the voters attached:

- The example sits in a checked position. Systems: "shown in a checked position (declared return
  type or annotated `let`)".
- The diagnostic names the `match` rewrite first. DevOps: "The Q8 mismatch help line should name the
  `match` rewrite first; it may also offer `map_err` as a second quick-fix when a target type
  exists."

#### User sign-off

The user approved the tally, including the 5-1 results on Q3 and Q5.

#### AI-first review

- **Learnability:** pass. One definition of `Never` in §3.2. §2.20, §3.3, §3.7 and the §7 table
  point at it.
- **Consistency:** pass. §3.7 and §2.20 no longer use "inhabits". `Never` follows the same
  no-variance and no-pruning rules as every other type.
- **Generability:** pass. The spec shows one widening idiom and one `Err(e) => e` arm. A model needs
  no `absurd` function, no `resume` and no constructor.
- **Debuggability:** pass. E0311 help names a diverging tail for `-> Never`. The E0300 help names the
  `match` rewrite. A `match` without an expected type fails at the `match` and does not widen
  silently.
- **Token efficiency:** pass. The `match` re-wrap is longer than `map_err`. The panel accepted that
  cost in exchange for an error at the `match` instead of a silent wrong type.

5/5 pass.

#### Moderator notes on spec wording

Two facts changed the wording of the §4.4.3 rule.

- **No `resume` keyword.** Blink handlers have no `resume` keyword. A handler gives an op its result
  by returning from the op's `fn`. The rule therefore says the handler `fn` for a `-> Never` op
  "cannot return" and its body "must diverge", where the panel text said "cannot `resume`".
- **`abort` is not defined.** The §4.4.3 mock handler ends with `abort`, but no section defines
  `abort`. The rule does not make `abort` normative. A follow-up ticket covers it.

### Final Spec

```blink
fn fail(msg: Str) -> Never {
    panic("config: {msg}")
}

fn load() -> Result[Int, Str] {
    let r: Result[Int, Never] = Ok(3)
    match r {
        Ok(v) => Ok(v),
        Err(e) => e,
    }
}
```

- `Never` is a nameable prelude built-in type with no values.
- It is legal in any type position: return type, parameter, field, `let` annotation, type argument.
- `Never` is a subtype of every type. Inference never chooses it for an open slot.
- No literal, constructor or conversion makes a `Never`. Only a construct that diverges (§3.3) has
  this type.
- Subsumption does not lift through type constructors. `List[Never]` is not a `List[Int]`,
  `Result[Int, Never]` is not a `Result[Int, Str]`, `fn() -> Never` is not a `fn() -> Int`.
- A variant with a `Never` payload still needs an arm. The checker does not prune it. The arm body
  may be the payload itself.
- `Never` implements no trait unless the prelude declares an impl. A separate ticket decides which
  impls the prelude declares.
- `-> Never` keeps the effect row. `fn exit(code: Int) -> Never` still needs `! Env.Exit` at each
  call.
- A handler `fn` for an op declared `-> Never` cannot return. Its body must diverge (§4.4.3).
- The E0311 help for `-> Never` names only a diverging tail and does not offer `Option[R]`.
- The unreachable-code lint after a `Never` construct is deferred (W0700).

Spec locations: §3.2 (definition and widening example), §3.3 (divergence), §3.5 *Exhaustiveness*,
§3.7 (No Null), §2.11 (loop tail cross-reference), §2.20 (`panic`), §4.4.3 (handler rule), §7
(prelude table), ERROR_CATALOG E0311.

### Follow-ups

- Implement the nameable `Never` type in the compiler. Writing `Never` in source is `UnknownType`
  today.
- Remove the `-> ()` (equivalently `-> Void`) parenthetical in §3.3. It conflicts with the ruling
  that `Void` is FFI-only.
- Fix the two meanings of W0700, then add the unreachable-code lint after a `Never` construct.
- Decide which prelude trait impls `Never` gets (for example `Display`, so `.unwrap()` works on
  `Result[T, Never]`).
- State in the FFI section whether the compiler trusts a foreign function declared `-> Never`.
- Define `abort`, or replace it in the §4.4.3 handler example. Handler bodies have no defined
  `abort`.
