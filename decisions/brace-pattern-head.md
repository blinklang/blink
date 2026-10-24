[< All Decisions](../DECISIONS.md)

# Brace Pattern Head (`Name { .. }` in a Pattern) — Design Rationale

§3.5 *Bare names: variant or binding* said that an uppercase bare name names a variant "with or without a payload
(`Red`, `Red(x)`, `Red { .. }`)", and that it is E0308 when the type at the position is not an enum. Read literally,
the struct pattern `Point { x, .. }` on a `Point` was E0308. But *Struct patterns* ("Type name is required (nominal
matching)"), *Qualified names and the wrong type* (`Q { y }` on a `P` is E0300) and the irrefutable-pattern list
(`let User { name, .. } = ...`) treat `TYPE_NAME { .. }` as a struct pattern. The compiler accepts the struct form in
a `match`, also nested and in an OR-pattern. It gives E0308 "`Point` is a struct; it has no variants" for a typo,
`Pointt { .. }` on a `Point`.

## Summary

| Q | Question | Result | Vote |
|---|---|---|---|
| Option | S (a struct in scope wins, as at construction) or T (the type at the pattern position decides) | T: in `Name { .. }` the type at the pattern position decides. On an enum that has a variant `Name`, it is that variant, also when a struct `Name` is in scope. On a struct, `Name` must be that struct. A brace head never binds, so the first-character rule does not apply to it | 6-0 after Phase B (sys and min moved from S) |
| Q1 | A struct `Name` in scope, and `Name { .. }` names a variant of the enum at that position | A: a `note:` only | 6-0 in Phase D after 4-2 in Phase C |
| Q2 | `Name { .. }` on a type that is neither an enum nor a struct (`Int`, tuple, type parameter) | A: a type in scope is E0300; no type, but a variant of a visible enum, is E0308 (today's help); neither is E0507 | 6-0 in Phase D after 4-2 in Phase C |
| Q3 | Where the rule goes | A: a new *Brace patterns* paragraph after *Bare names: variant or binding* | 6-0 |
| Q4 | An amendment line in decisions/variant-spelling-and-pattern-case.md | A: add a line saying the brace form on a struct was never E0308 | 5-1 (Minimalism dissent: B) |
| Q5 | The sentence added to *Struct patterns* | A: "The name is a struct type, or a variant of the enum at that position." | 5-1 (PLT dissent: C) |

Agreed in Phase B by all six seats (not balloted): a brace pattern never binds, so the reason of the first-character
rule (a typo or a constant becomes a catch-all binding) does not apply to it. The bare name and the paren form keep
the old rule, so `Point(x)` on a struct stays E0308. One rule holds in every pattern position. A lowercase struct
name works. A typo on a struct is E0507, as *Qualified names and the wrong type* already uses E0507 for a name that is
no type. `Point { .. }` on an enum that has no variant `Point` is E0300.

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in
independent-proposal, debate, vote rounds. Phase A is excerpted from each panelist's own text. Phases B, C and D
are quoted in full from each panelist's file, without its heading line.

#### Phase A — Independent proposals

- **Systems:** "**Rule.** `Name { field_patterns }` is resolved at typecheck time, before layout, in this order. It is the same order as construction (03_types.md:2243), so one name means one thing in an expression and in a pattern.
  1. A struct type `Name` is in scope: the pattern is a struct pattern. The scrutinee type must be that struct, else E0300 (existing).
  2. Else the pattern is a variant brace pattern. The scrutinee must be an enum (else E0308, existing, "`T` is a struct; it has no variants" for a struct) and must have the variant `Name` (else E0547, existing)."
- **Web/Scripting:** "A JS/Python/Kotlin dev writes `Point { x, .. }` on a `Point` and expects it to work. It works today. The spec text says E0308. The fix is to change the text, not the compiler. ... Rule: in `Name { field_patterns }`, look at the scrutinee type T at that position."
- **PLT:** "**Typing rule.** Let `Γ ⊢ Name { fps } : τ` be checked against scrutinee type τ.
  1. τ is an enum: `Name` must be a variant of τ with named fields. Else E0547 `NoSuchVariant`, except when `Name` is a type in scope that is not a variant: E0300 (the pattern's type is not τ).
  2. τ is a struct `S`: `Name` must resolve to `S`. A different type in scope is E0300. A name that resolves to no type is E0507 `UnknownType` (a typo, `Pointt`).
  3. τ is a builtin, tuple, list, `Int`, or a type parameter: E0300."
- **DevOps:** "**Rule.** `Name { field_patterns }` has no binding hazard: a brace pattern never creates a new binding named `Name`. The reason at 3178 (typo or constant becomes a catch-all binding) does not apply to it. So the brace form is not decided by the case of its first letter. It is decided by the type at the pattern position, in this order:
  1. The type is an enum and it declares a variant `Name`: variant brace pattern.
  2. `Name` resolves to a type in scope: struct pattern. If that type is not the type at the position: E0300 (as `Q { y }` on a `P` today). On an enum, the help lists its variants.
  3. `Name` resolves to nothing. Type is an enum: E0547 (unchanged). Type is not an enum: E0507 UnknownType, with the nearest type name as a machine-applicable fix."
- **AI/ML:** "**Rule.** `Name { field_patterns }` is never a binding, so the typo/constant reason at 3178 does not apply to it. Resolve it by the type at that position, with no case test:
  1. Type at the position is an enum with a variant `Name`: variant brace pattern.
  2. Type at the position is a struct and `Name` resolves to that struct: struct pattern.
  3. Otherwise it is an error (table). Paren form `Name(p)` and bare `Name` keep the 3175 rule unchanged."
- **Minimalism:** "The gap is one sentence. 3175 says an uppercase bare name "names a variant". It was written for the bare name and the paren payload, where a typo becomes a catch-all binding. A brace pattern never binds a name, so that reason does not apply to it. The spec already has a rule for `Name { ... }` in expressions: *Resolution order* (2243) says a struct in scope names that struct. Use that rule in patterns."

#### Phase B — Debate highlights

Each seat's round-1 reply is quoted in full, without its heading line. Options: **S** (sys-1, min-1): a struct `Name` in scope wins, as at construction. **T** (web-1, plt-1, devops-1, aiml-1): the type at the pattern position decides.

- **Systems:** *(moved from S to T)*
  > **Option S vs T: I move to T.** Both cost the same: both resolve in typecheck, before mono and layout, and both lower a struct pattern to field loads and a variant pattern to a tag test. My Phase A reason for S was one lookup order for construction and patterns. plt's point beats it. A pattern has a scrutinee type. A construction site has none, so "scope wins" at 2243 exists only because nothing else can decide. The scrutinee is already an input to the lowercase rule (3176), so T adds no new input.
  >
  > **V1.** Concede to T: on an enum with a variant `Name`, the arm names the variant, even when a struct `Name` is in scope. Under S, a new import turns a working arm into E0300. That error is loud, not silent, but it is a distant-edit failure for no gain. min's "reader cannot see the type" objection holds for bare names because a bare name can bind. A brace pattern never binds, so it does not apply. I accept devops' `note:` that a struct `Name` is also in scope.
  >
  > **V2.** `Pointt { .. }` on a `Point`: no struct and no variant has that name. I accept E0507 `UnknownType` (F2: 3301 already uses it for an unresolved name). E0308 "`Point` is a struct; it has no variants" blames the scrutinee for a typo in the name. On an enum scrutinee the typo stays E0547.
  >
  > **V3.** A name that is no type, on a non-enum, non-struct scrutinee (`Zed { .. }` on `Int`): E0507, for the same reason as V2. If `Red` is a variant of some visible enum, E0308 with the existing help (devops). A struct `Name` on `Int` or `T`: E0300.
  >
  > **V4.** Agree, E0300 with the variant list.
  >
  > **V5.** One paragraph, *Brace patterns*, in the 3175 area. Do not edit 3175 inline, and amend :346 as aiml says. 3421: "The name is a struct in scope, or a variant of the enum at that position."
  >
  > STATUS: ready to vote
- **Web/Scripting:**
  > **S vs T: T.** In Option S, adding `import dep` can turn an arm from a variant into E0300. A JS/Python dev cannot find that. Under T, the `match` line shows the scrutinee type, and no import changes an arm. min says T makes the meaning depend on a type the reader cannot see. The reader sees it: 3178 is about bare names, where the arm can bind. A brace head never binds, so the 3178 reason is absent. Construction (2243) has no scrutinee; a pattern does. The two differ for that reason.
  >
  > **V1.** T. The arm names the variant. I support devops's `note:` that a struct `Point` is also in scope. I do not support the sys/min help line as the error: the arm is valid.
  >
  > **V2.** I concede to plt/devops: E0507 `UnknownType`, span `Pointt`, help "did you mean `Point`". 3301 already uses E0507 for "a name that is not a type", so it reuses an existing code and my E0300 was a new use of one that does not fit. On a struct there are no variants, so no E0547 is possible. On an enum, a typo stays E0547.
  >
  > **V3.** Not a strong view. `Red { .. }` on an `Int` where `Red` is a variant of a visible enum: E0308 with the existing help (devops). A name that is no type and no variant anywhere: E0507. This is one rule: "type in scope: E0300; variant of some visible enum: E0308; neither: E0507". I prefer it to plt's blanket E0300, which hides the real error.
  >
  > **V4.** Agreed, E0300.
  >
  > **V5.** A new *Brace patterns* paragraph, so the 3175 bullet stays short for a reader who scans. Take aiml's amendment line at :346. For 3421, take devops's text.
  >
  > STATUS: ready to vote
- **PLT:**
  > **Position: Option T.**
  >
  > **S vs T.** Option S makes the meaning of `Name { .. }` depend on scope: adding a struct `Name` to scope, or importing it, changes which arm a dependency-enum match means. T depends on the scrutinee type only, which the checker already has, and which an import cannot change. min's objection (3178) is about *binding*: a bare name that silently binds or silently matches. A brace pattern binds nothing, so the worst outcome of reading it wrongly is a type error, never a wrong match. 3178 does not carry over.
  >
  > **V1.** Variant. Under S the user's only fix is `Enum.Name { .. }`, a rule that exists for the import, not for the program. S also breaks the symmetry with E0518: that error forbids the overlap inside a package precisely because it is ambiguous. For a dependency enum no such ambiguity exists once the scrutinee decides. Devops' `note:` that a struct `Name` is also in scope is a good addition. I accept it.
  >
  > **V2.** Keep E0507. aiml and web say E0300, but E0300 needs a second type to report ("pattern of type Q used on P"). A typo has none, and 3301 already uses E0507 for step 1 of a qualified pattern. Same step, same code. I accept web's "did you mean `Point`" help and the span F3 shows.
  >
  > **V3.** I refine my text. A name that is no type is E0507 on every non-enum scrutinee, not E0300. A name that is a type is E0300. I concede devops' point: when the name is a variant of a visible enum and the scrutinee is a non-enum, E0308 with the existing help is the better message, since the author meant a variant. Only the diagnostic reads scope here; the meaning does not.
  >
  > **V4.** Agreed, E0300 with the variant list.
  >
  > **V5.** New paragraph *Brace patterns*. Add the aiml amendment line to :346. 3421 gets one sentence: "The name is the struct at that position, or a variant of the enum there."
  >
  > STATUS: ready to vote

- **DevOps:**
  > **S vs T: T.** Option S makes an arm break when someone adds an import. A user has a working `Point { x } => x` on a dependency enum. A later `import geo` brings a struct `Point` into scope, and the arm becomes E0300. The error points at code that did not change. Under T, an import never changes an arm, and the LSP and the compiler need no scope lookup to answer "what does this arm name".
  >
  > **Answer to min's objection.** A bare `Red` already needs the scrutinee type to find its variant, so the reader already reads the type. The arm sits under `match shape`. The 3178 reason is about binding, and a brace head never binds.
  >
  > **V1.** T: the variant, with a `note:` about the struct in scope. Concede to sys: the help should also show `Shape.Point { .. }`, the explicit spelling that is immune to scope.
  >
  > **V2.** E0507. The user wrote a type name that does not exist, so `UnknownType` fits (F2, 3301). I accept web and aiml's help text "did you mean `Point`". I oppose E0300: no type mismatch exists, and `Point` is the right type. I oppose E0308: its message says "no variants" to a user who wrote a struct pattern.
  >
  > **V3.** Not E0300 for a name that is no type (plt): E0300 says "wrong type", and no type was named. Rule: name resolves to a type: E0300. No type, but a visible enum declares a variant `Name`: E0308 (today's help is right). Neither: E0507. I concede this is the weakest part of my proposal; if the panel wants one fewer branch, E0507 for both no-type cases is acceptable.
  >
  > **V4.** Agree, E0300.
  >
  > **V5.** A new subsection *Brace patterns*, placed after *Bare names*. Inline text in 3175 would grow a bullet that already holds three rules. Add aiml's amendment line. For 3421 use: "The name is a struct type, or a variant of the enum at that position."
  >
  > STATUS: ready to vote
- **AI/ML:**
  > **Option S vs T: T.** S gives the writer a two-step test (is a struct in scope? then which enum?). T gives one: what is the type here? A model that writes `match shape { Point { x } => x }` on an enum with a variant `Point` is right under T and gets E0300 under S, though the code is correct. S also lets a new import change the meaning of an arm. T does not.
  >
  > **V1: variant (T).** I answer min's objection. 3178 protects bare names, because a bare name can bind, so its meaning decides which names an arm binds. A brace pattern binds nothing under `Name`, so the reader loses nothing. The scrutinee is in the same `match`. Construction (2243) has no scrutinee; a pattern has one. I accept devops' `note:` that a struct `Point` is also in scope.
  >
  > **V2: concede to E0507.** I withdraw E0300 for a typo. F2 shows 3301 already uses E0507 for a name that is no type. One code per cause is easier to learn: no type found is E0507, a wrong type is E0300, an enum with no such variant is E0547. Keep the "did you mean `Point`" help.
  >
  > **V3: E0507 when `Name` is no type and the position is not an enum** (`Zed { .. }` on an `Int` or `T`). E0300 when `Name` is a type in scope (the voted `T` case). For `Red { .. }` where `Red` is a variant of some enum that is visible but not at this position: E0300 is wrong, since `Red` is not a type. I accept devops' E0308 with the existing help only if it is the existing behaviour. I did not probe it.
  >
  > **V4:** agree, E0300.
  >
  > **V5: separate paragraph *Brace patterns*.** An inline edit in the 3175 bullet buries the rule. 3421 wording: take devops' ("a struct type, or a variant of the enum at that position"). I keep the amendment line at decisions/variant-spelling-and-pattern-case.md:346.
  >
  > STATUS: ready to vote
- **Minimalism:** *(moved from S to T)*
  > **Option S vs T: I move to T.** I withdraw my objection to T in V1.
  >
  > My argument against T was that the meaning of a name depends on a type the reader cannot see. plt shows S has the same flaw in a worse form. Under S, a new `import` or a new struct in scope changes what an existing arm means, and the arm text does not change. Under T the scrutinee decides, and the scrutinee is the thing the arm matches. T also removes a scope lookup from the pattern rule. Subtraction wins. E0518 already forbids the clash inside one package, so V1 only arises with a dependency enum, where T gives the variant and needs no qualifier.
  >
  > T needs one sentence: "In `Name { .. }`, if the type at that position is an enum with a variant `Name`, it is that variant. If it is a struct, `Name` must be that struct." No scope step.
  >
  > **V1.** Variant (T). A `note:` that a struct `Point` is also in scope is cheap; devops may keep it. F1 says it is unprobed, so the spec text needs a probe before sign-off.
  >
  > **V2.** Prefer to keep E0308 unchanged, but the message "`Point` is a struct; it has no variants" misleads on a typo. I accept E0507 when `Pointt` is no type in scope and the scrutinee is a struct, because 3301 has the same step. On an enum, `Zed` stays E0547. I do not want a third new code.
  >
  > **V3.** `Zed { .. }` or `Red { .. }` on an `Int` or a `T`: keep E0308 (no struct to match, so it reads as a variant on a non-enum). plt's E0300 is acceptable if the panel wants one code for non-enum, non-struct scrutinees. I do not hold this.
  >
  > **V4.** E0300 with the variants listed. Agreed.
  >
  > **V5.** Inline in the 3175 bullet. A new subsection adds surface for a one-sentence rule. Add the 3421 sentence from devops. Skip the amendment line from aiml unless the decision file text is false as written.
  >
  > STATUS: ready to vote

#### Phase C — Final vote

Options for Q1: **A** the `note:` only. **B** the `note:` and a help that shows `Shape.Point { .. }`. Options for Q2: **A** a type in scope is E0300, a variant of a visible enum is E0308 with the existing help, neither is E0507. **B** a type in scope is E0300, no type is E0507 (also when a visible enum has a variant `Name`). **C** a type in scope is E0300, no type is E0308.

- **Q1: V1 diagnostics, a struct `Name` in scope and `Name { .. }` names a variant of the enum at that position** (Phase C 4-2; 6-0 for A after Phase D)
  - **Systems:** B — **Reasoning:** The `Shape.Point { .. }` spelling is resolved by path, so no scope change can alter it. It costs one help line in the compiler, on the diagnostic path only, and no runtime cost. A user who sees the `note:` about a struct in scope needs the fix next to it. **Concern:** A help that shows the explicit spelling may lead users to write the qualified form where the bare form is already valid.
  - **Web/Scripting:** A — **Reasoning:** In V1 the arm is valid, so the message should say only what a reader needs: a struct `Name` is also in scope. A help line that shows `Shape.Point { .. }` reads as a fix for code that has no fault, and a JS or Python dev will try to apply it. The `note:` alone gives the fact and leaves the arm alone. **Concern:** If a user later does want the struct and not the variant, the note does not tell them the explicit spelling, so they may ask how to name the variant.
  - **PLT:** A — **Reasoning:** Under T the arm is valid and its meaning comes from the scrutinee type alone. The note tells the reader a struct `Name` is also in scope. A help that shows `Shape.Point { .. }` suggests a repair for code that is not wrong, and it implies that scope could change the arm, which T denies. **Concern:** With B the help text may read as if the arm needs the qualified spelling, and users will add it where it is not needed.
  - **DevOps:** B — **Reasoning:** The user sees the arm as correct code, so the diagnostic must tell them which reading the compiler took and how to remove doubt. The `note:` says a struct is also in scope; the help `Shape.Point { .. }` gives the one spelling that scope cannot change. It is one extra line in a diagnostic that already exists, and it needs no new lookup. **Concern:** The help line shows on every such arm, and a team that never imports a clashing struct may read it as noise.
  - **AI/ML:** A — **Reasoning:** The arm is valid under Option T, so the diagnostic is a `note:`, not an error. A help line that shows `Shape.Point { .. }` tells a model that the working spelling needs a rewrite. A model may then copy the qualified form into every arm, and that adds tokens and a new decision point. The `note:` alone gives the reader the fact and nothing to act on. **Concern:** Without the explicit spelling in the note, a writer who wants immunity from scope has to find `Enum.Name { .. }` in the spec.
  - **Minimalism:** A — **Reasoning:** The `note:` names the one fact the reader lacks (a struct `Name` is also in scope) and costs one line. A second help that shows `Shape.Point { .. }` is a repair for code that is not wrong: under T the arm is valid, so there is nothing to repair. Each extra help line is more text to keep right. **Concern:** A reader who wants a scope-immune spelling must find `Shape.Point { .. }` in the spec, because the diagnostic does not show it.
- **Q2: `Name { .. }` on a type that is neither an enum nor a struct (`Int`, tuple, type parameter)** (Phase C 4-2; 6-0 for A after Phase D)
  - **Systems:** A — **Reasoning:** One cause gets one code: a type in scope is E0300, a visible variant of the name is E0308 with the existing help, nothing is E0507. The scan of visible enums runs only after resolution has failed, so it adds no cost to a valid program or to layout. The branch keeps today's E0308 message for the author who meant a variant. **Concern:** The middle branch makes the diagnostic depend on which enums are visible, so a new import can change an error code, though never the meaning of a valid program.
  - **Web/Scripting:** A — **Reasoning:** The rule reads in one line: type in scope is E0300, variant of a visible enum is E0308 with the existing help, neither is E0507. Each code says what went wrong, and the E0308 branch keeps today's help for the writer who meant a variant. B hides that real error behind "unknown type". **Concern:** Three branches need a scope lookup for the diagnostic, and the E0308 branch can drift from the other two if the visible-enum search changes.
  - **PLT:** A — **Reasoning:** Each cause gets one code. A name that is a type in scope but the wrong type is E0300. A name that is no type but a variant of a visible enum is E0308, since the author wrote a variant on a non-enum. A name that is neither is E0507, as at 3301. Only the diagnostic reads scope here. The meaning of the pattern does not. **Concern:** Three branches make the checker consult scope for a message, and the E0308 branch may disagree with what a later change does to visible-enum lookup.
  - **DevOps:** A — **Reasoning:** Three causes give three codes: a wrong type is E0300, a name that is a visible variant but sits on a non-enum is E0308, a name that resolves to nothing is E0507. My probe shows E0308 on `Red { x }` on an `Int` already has a header that names the variant and a help that fits that author's intent. E0507 "unknown type `Red`" would hide that intent. The cost is one scope lookup, used only when the compiler builds the message; it never changes the meaning of the arm. **Concern:** If the E0308-vs-E0507 split costs a visible-variant search for the diagnostic, the compiler may drift from the spec text, and B would then be the safer wording.
  - **AI/ML:** B — **Reasoning:** One code per cause is easiest to learn from the spec alone: a type found but wrong is E0300, no type found is E0507, an enum with no such variant is E0547. Option A adds a third branch that reads scope for a visible enum with a variant `Name`, and a model must predict that scope lookup. The cost is a less specific message in a rare case, and the author can still read the E0507 help. **Concern:** E0507 on `Red { .. }` where `Red` is a visible variant hides the real fault (a variant used on a non-enum) from a repair loop.
  - **Minimalism:** B — **Reasoning:** One code per cause: a type in scope that does not fit is E0300, no type found is E0507, as 3301 already says. This drops the branch that reads scope for a variant of some unrelated visible enum, and a diagnostic that depends on what else is visible is surface I do not want. I held E0308 (C) in B1 but did not hold it hard; B is consistent with the typo case on a struct. **Concern:** `Red { .. }` on an `Int`, where `Red` is a real variant elsewhere, says "unknown type" and not "variant on a non-enum", which may mislead the author.

- **Q3: Where the rule goes** (6-0)
  - **Systems:** A — **Reasoning:** The 3175 bullet already holds three rules. A separate paragraph gives the brace rule one place that the checker and the spec both name. The rule resolves in typecheck, before mono and layout, and the spec should say so in one place. **Concern:** A paragraph placed apart from 3175 can drift from the bullet it exempts the brace form from.
  - **Web/Scripting:** A — **Reasoning:** A reader who scans for "what does `Point { .. }` mean" needs a heading to find. The 3175 bullet already holds three rules, and a fourth makes it hard to read. A short *Brace patterns* paragraph is easier to link from error messages and from the LSP. **Concern:** The first-character rule at 3175 now has a pointer to a second place, and a reader who stops at the bullet misses the brace exception.
  - **PLT:** A — **Reasoning:** The typing rule for the brace head is a separate rule from the first-character rule for bare names. It needs its own statement, with the case table. Inline in the 3175 bullet, it would mix a type-directed rule into a rule about binding. **Concern:** A new subsection adds one more place that must stay consistent with 3175, 3176, 3180 and 3304.
  - **DevOps:** A — **Reasoning:** The 3175 bullet holds three rules already. A separate *Brace patterns* subsection has one anchor that the LSP hover, `blink explain` and error help can link to. A reader who scans for "brace" finds it at once. **Concern:** Two places (3175 and the new subsection) now speak about `Name {`, and they can drift apart unless 3175 points to the subsection by name.
  - **AI/ML:** A — **Reasoning:** A model that looks up "brace pattern" finds one named paragraph with the whole rule. The 3175 bullet already holds three rules, and a fourth makes it hard to retrieve by search or by attention. **Concern:** Two places (the bullet and the new paragraph) now describe name resolution, and they can drift apart.
  - **Minimalism:** A — **Reasoning:** The rule now carries a choice by type, three error codes and the irrefutable case. That no longer fits in the 3175 bullet, which already holds three rules. A short paragraph adds no language surface; it only keeps the text readable. I withdraw B1's inline position. **Concern:** A new named paragraph invites later additions, and the brace rule may grow there.
- **Q4: Amendment line at decisions/variant-spelling-and-pattern-case.md** (5-1, Minimalism dissent)
  - **Systems:** A — **Reasoning:** The decision file says the bare payload pattern on a struct moved to E0308 and does not say the brace form was never E0308. One line stops a later reader from applying that amendment to `Point { .. }`. It costs one line and no code. **Concern:** An amendment line in a closed decision record can read as a new vote.
  - **Web/Scripting:** A — **Reasoning:** The decision file is read by users who search for "E0308 struct". One line that says the brace form on a struct was never E0308 stops a wrong reading of :346 and costs nothing. This is the question a new user asks first. **Concern:** An amendment line in an old decision file adds history that a reader must follow, and it can go stale if the rule changes again.
  - **PLT:** A — **Reasoning:** Line 346 says the bare payload pattern on a struct moved to E0308. A reader can take that to cover the brace form. One amendment line closes that reading and keeps the decision record consistent with the new rule. **Concern:** The amendment line records a negative ("never E0308"), and such lines drift when the E0308 row changes.
  - **DevOps:** A — **Reasoning:** The decision file said E0308 for the bare payload pattern on a struct, and a reader can take that to cover the brace form. One line removes the doubt for the next reader of the decision record. It costs nothing in the compiler or the tools. **Concern:** Amendment lines pile up in decision files, and a later reader must follow them in order to know the current rule.
  - **AI/ML:** A — **Reasoning:** The line says "the bare payload pattern on a struct ... is now E0308" and does not say the brace form is outside it. A model or reader who trains on the decision file can infer that the brace form on a struct is E0308. One sentence removes that false inference. **Concern:** An amendment to a past decision record adds edit history that readers must now reconcile with the original text.
  - **Minimalism:** B *(dissent)* — **Reasoning:** The line at :346 says "the bare payload pattern on a struct, tuple or type parameter". It does not mention the brace form, so it is not false as written. The new *Brace patterns* paragraph states the brace rule, and a second statement of it in a decision file is one more place to keep in step. **Concern:** Someone who reads :346 and the old 3175 together may still take the brace form on a struct for E0308, until the spec paragraph corrects them.
- **Q5: The sentence added to *Struct patterns*** (5-1, PLT dissent). Options: **A** "The name is a struct type, or a variant of the enum at that position." **B** "The name is a struct in scope, or a variant of the enum at that position." **C** "The name is the struct at that position, or a variant of the enum there."
  - **Systems:** A — **Reasoning:** Under T the name resolves by the type at that position, not by a scope lookup first, so "struct in scope" (my B1 text) states the S order. I withdraw B. "A struct type, or a variant of the enum at that position" is accurate and short. **Concern:** "A struct type" does not say that a different struct type in scope is E0300, so the sentence must sit next to the 3304 text.
  - **Web/Scripting:** A — **Reasoning:** "A struct type" is the plain phrase a JS or TS dev knows, and it does not bring in scope, which T rejects as an input. B ("in scope") puts scope back into a rule that the panel agreed the type decides. C uses "at that position" twice and is harder to read. **Concern:** "A struct type" does not say that the struct must be the one at that position, so a reader can think any struct type works.
  - **PLT:** C *(dissent)* — **Reasoning:** "The struct at that position" ties the name to the scrutinee type, which is the T rule. B ("a struct in scope") reintroduces scope into the sentence and reads like Option S. A says "a struct type", which does not say which one. **Concern:** If A or B wins, the sentence at 3421 can be read as the scope rule that the panel rejected.
  - **DevOps:** A — **Reasoning:** "A struct type" says what the name must be and does not say where the compiler looks it up, so it stays true if the lookup rules change. "A struct in scope" (B) brings scope back into the sentence and so brings back the S reading that the panel dropped. C ("the struct at that position") is correct but is harder to match to a diagnostic header. **Concern:** "A struct type" alone does not tell a reader that a struct of a different type still gives E0300, so 3304 must stay next to it.
  - **AI/ML:** A — **Reasoning:** "The name is a struct type, or a variant of the enum at that position" has no scope word, so it matches Option T. Option B ("struct in scope") brings the scope dependency back into the text. Option C uses "at that position" for a struct, which is vague for a model. **Concern:** "A struct type" does not say that the struct must be the scrutinee's own type, so a reader must also read the E0300 rule at 3304.
  - **Minimalism:** A — **Reasoning:** "A struct type" is the shortest wording and is true at the pattern position, with no reference to scope. B says "in scope", which brings the scope input back that T removed. C is the same idea in more words. **Concern:** "A struct type" does not say which struct, so a reader needs the *Brace patterns* paragraph for the nominal check.

#### Phase D — Round 2 (Q1 and Q2)

Q3 6-0, Q4 5-1 and Q5 5-1 were decided in Phase C. Phase D1 is the focused debate; each seat answers the strongest argument against its Phase C vote. Phase D2 is the silent re-vote.

**D1 debate**

- **Systems:**
  > **Q1. I change my vote from B to A.**
  > The strongest argument against B is plt's: under Option T, scope cannot change the arm, so a help that shows `Shape.Point { .. }` suggests a repair for code that is not wrong. It also implies a hazard that does not exist. aiml adds a cost I weigh as sys: a model may copy the qualified form into every arm, which adds tokens and a decision point for no gain in generated code. The qualified spelling is already legal and resolves by path, so the spec can state it once in *Brace patterns*. The compiler does not need to repeat it in a diagnostic. My B vote came from the S order, where scope could break an arm. T removed that case. The `note:` alone tells the user a struct `Point` is also in scope, and that is the fact they need.
  >
  > **Q2. I hold A.**
  > The strongest argument against A is min's and aiml's: the diagnostic then depends on what else is visible, and a model must predict a scope lookup. I accept that a new import can change the error code. It cannot change the meaning of a valid program, and the scan runs only on the error path, so it costs nothing in codegen or layout. devops' probe settles the message quality: E0308 on `Red { x }` on an `Int` already names the variant and gives help that fits the author's intent. E0507 "unknown type `Red`" would hide that intent from a repair loop. I keep today's behaviour and add no new branch to the checker beyond the existing one.
- **Web/Scripting:**
  > **Q1. I hold A (note only).**
  > Strongest argument against: sys and devops say the user who reads the `note:` needs the fix beside it. I answer that the arm is valid, so there is no fix to give. The note tells the user why a name may look odd: a struct `Point` is also in scope. A help line implies a fault, and plt is right that it implies scope could change the arm, which T denies. aiml adds a real cost: a model copies the qualified form into every arm. I admit my own Phase C concern stands: the note does not show the explicit spelling. That is a documentation gap, and the *Brace patterns* paragraph (Q3, A) can name `Enum.Name { .. }` in one sentence. The spelling is then in the spec, not in a diagnostic on correct code.
  >
  > **Q2. I hold A (three branches).**
  > Strongest argument against: aiml and min say the E0308 branch reads scope, so the error code depends on what else is visible, and a model must predict that lookup. I answer that the code changes only for code that is already wrong, and the lookup runs after resolution fails (sys). devops' probe shows E0308 on `Red { x }` on an `Int` already names the variant and gives a help that fits the author's intent. B replaces that with "unknown type `Red`", which is false: `Red` is a variant. A repair loop reads the false header and looks for a type to import. A user who meant a variant should hear that a variant is used on a non-enum. The cost is one more branch in the checker. I accept it for the better message.
- **PLT:**
  > **Q1. Hold A.**
  > Strongest argument against: sys and devops say a user who sees the note needs the fix beside it, and `Shape.Point { .. }` is the one spelling that scope cannot change.
  > Answer: the arm is valid. A note states a fact about scope. A help offers a fix, and nothing needs fixing. Under T, no import changes the arm, so the qualified spelling gives no immunity that the arm lacks. A help would teach the wrong model: that scope can alter the arm. aiml adds a second cost: a model copies the qualified form into every arm. The spec already states in *Brace patterns* that `Enum.Name { .. }` names the variant. A writer who wants it finds it there. If the panel wants a pointer, put it in the paragraph or in the E0518 text, not in a diagnostic on valid code.
  >
  > **Q2. Hold A.**
  > Strongest argument against: aiml and min say A makes the error code depend on what else is visible, and a model must predict a scope lookup.
  > Answer: the scan runs only after resolution fails, so it never changes a valid program (sys). The code depends on scope, the meaning does not. devops' probe shows E0308 already names the variant and gives a help that fits the author's intent. E0507 "unknown type `Red`" would hide that the author wrote a variant on a non-enum. aiml's own concern on B says the same. The branch costs one extra case in an error path.
- **DevOps:**
  > **Q1. I change my vote from B to A.**
  > Strongest argument against B: plt's. The arm is valid, so a help that shows `Shape.Point { .. }` offers a repair for code that is not wrong. It also hints that scope could change the arm, and under T it cannot. I checked where the `note:` shows: only on an error inside the arm, such as a wrong field label. The qualified spelling does not fix such an error, so the help sits next to a fault it does not cure. aiml adds a real cost: a model may copy the long form into every arm. The `note:` alone gives the reader the one fact they need, that a struct `Point` is also in scope. web's and aiml's concern (the explicit spelling is hard to find) is a spec and `blink explain` matter, and the *Brace patterns* paragraph from Q3 can name `Enum.Name { .. }` there.
  >
  > **Q2. I hold A.**
  > Strongest argument against A: min's and aiml's, that the E0308 branch reads scope for a visible enum with a variant `Name`, so a diagnostic depends on what else is visible. I accept that this is a third branch. Three facts weigh against it.
  > - The scan runs only after resolution fails (sys), so it never touches a valid program, meaning, or layout.
  > - The E0308 header today already names the variant; my probe shows it. B would replace that text with "unknown type `Red`", and aiml's own concern holds: a repair loop loses the real fault, a variant used on a non-enum.
  > - The new E0507 case only needs the scan to pick between two messages. If an implementer finds the scan costly, the fallback is E0308 for every no-type case on a non-enum, which is min's option C, not B.
- **AI/ML:**
  > **Q1. Hold A.**
  > The strongest argument for B is sys and web's: a writer who wants a scope-proof spelling needs the fix next to the `note:`. I accept the cost, but B has a larger one for a model. A help line that shows `Shape.Point { .. }` on a valid arm reads as a repair. A repair loop acts on help text, so it will rewrite a correct arm, and then copy the qualified form into other arms. The `note:` states the fact (a struct `Name` is also in scope). `Enum.Name { .. }` is already in the spec for anyone who wants it. The arm has no fault, so the diagnostic should not suggest a change.
  >
  > **Q2. Change to A.**
  > My B vote rested on one rule: one code per cause. devops' probe answers my concern better than B does. Today `Red { x }` on an `Int` gives E0308 with a header that names the variant and a help that fits the author's intent. B replaces that with "unknown type `Red`", which sends a repair loop to look for a type that the author never meant. That is the hiding I named in my own Concern. The extra branch costs a model nothing to predict: it reads the message, not the scope. The scan runs only after resolution fails (sys), so a valid program is not affected. min's objection (an error that depends on what is visible) is real, but the code changes only between two errors, never the meaning of a valid arm. The rule reads in one line: type in scope is E0300, visible variant is E0308, neither is E0507.
- **Minimalism:**
  > **Q1. Hold A.**
  > Strongest argument against: sys and devops say the writer needs the fix next to the `note:`. I do not agree. Under T the arm is valid, so there is no fix to give. The `note:` states a fact; a help line would suggest a repair for code that is not wrong. aiml's point adds weight: a model may copy `Shape.Point { .. }` into every arm. A writer who wants the qualified spelling finds it in the spec, and the `note:` shows where to look. I do not change.
  >
  > **Q2. Change to A.**
  > Strongest argument against my B vote: devops. His probe shows E0308 on `Red { x }` on an `Int` already has a header that names the variant and a help that fits the author's intent. B would replace working output with "unknown type `Red`", which hides the real fault from a repair loop (aiml's concern on B, which I cannot answer).
  >
  > My Phase C reason was that a diagnostic that reads scope is new surface. That is false here: the scan exists today and runs only after resolution fails (sys). Option A adds no code. It keeps the current result. B would remove a branch from the compiler and make the message worse. Subtraction that degrades the output is not worth the saving.
  >
  > I accept sys's concern that a new import can change an error code, because it never changes the meaning of a valid program.

**D2 re-vote.** Changes in D1: Q1 sys B to A, devops B to A. Q2 min B to A, aiml B to A.

- **Q1: V1 diagnostics** (6-0 for A)
  - **Systems:** A — **Reasoning:** Under Option T the arm is valid and its meaning comes from the scrutinee type alone, so no scope change can alter what the compiler emits for it. A help line that shows `Shape.Point { .. }` offers a repair for code that is not wrong, and it implies a scope hazard that T removed. The `note:` costs one diagnostic line and gives the reader the one fact they lack. The qualified spelling is already legal and resolves by path, so the *Brace patterns* paragraph states it once. **Concern:** A writer who wants a scope-proof spelling must find `Enum.Name { .. }` in the spec, because the diagnostic does not show it.
  - **Web/Scripting:** A — **Reasoning:** The arm is valid, so the message should state one fact: a struct `Name` is also in scope. A help line with `Shape.Point { .. }` reads as a fix for code with no fault, and a JS or Python dev will apply it everywhere. Sys and devops both moved to A in D1 for this reason. The qualified spelling belongs in one sentence of the *Brace patterns* paragraph. **Concern:** A user who wants the struct, or wants a scope-proof arm, does not see the explicit spelling in the diagnostic, so the spec sentence must be easy to find.
  - **PLT:** A — **Reasoning:** Under T the type at the pattern position decides the arm, so scope cannot change its meaning. A `note:` states the fact that a struct `Name` is also in scope. A help with `Shape.Point { .. }` offers a repair for a valid arm and implies that scope could change it. The qualified spelling stays legal and belongs in the *Brace patterns* paragraph. **Concern:** A writer who wants a spelling that scope cannot affect must find `Enum.Name { .. }` in the spec, because the diagnostic does not show it.
  - **DevOps:** A — **Reasoning:** The arm is valid under Option T, so the diagnostic states a fact (a struct `Name` is also in scope) and offers no repair. My D1 check showed the `note:` appears only on an error inside the arm, such as a wrong field label, and `Shape.Point { .. }` does not cure that error. The explicit spelling belongs in the *Brace patterns* paragraph and in `blink explain`, where a reader looks for it. **Concern:** A writer who wants a scope-proof spelling gets no pointer from the diagnostic, so the spec paragraph must name `Enum.Name { .. }`.
  - **AI/ML:** A — **Reasoning:** The arm is valid under Option T, so the diagnostic states a fact (a struct `Name` is also in scope) and offers no repair. A help line that shows `Shape.Point { .. }` reads as a fix, and a repair loop acts on help text. It would rewrite a correct arm and copy the long form into other arms, which adds tokens and a decision point. The *Brace patterns* paragraph can name `Enum.Name { .. }` once, so a writer who wants it finds it in the spec. **Concern:** A writer who wants a scope-proof spelling gets no pointer from the diagnostic and must find it in the spec.
  - **Minimalism:** A — **Reasoning:** The arm is valid under T, so the diagnostic states one fact (a struct `Name` is also in scope) and offers no repair. A second help line is more text to keep right, and it teaches that scope can change the arm, which T denies. The qualified spelling is already legal, and the *Brace patterns* paragraph can name it once. **Concern:** A writer who wants a scope-immune spelling gets no pointer from the diagnostic and must find it in the spec.
- **Q2: `Name { .. }` on a type that is neither an enum nor a struct** (6-0 for A)
  - **Systems:** A — **Reasoning:** The scan for a visible enum with a variant `Name` runs only after resolution has failed, so it adds no cost to a valid program, to mono or to layout. Today's E0308 on this case already names the variant, and E0507 "unknown type" would be false when `Name` is a visible variant. Three causes get three codes: a type in scope is E0300, a visible variant is E0308, nothing is E0507. **Concern:** A new import can change which error code the arm gets, so the checker's error path depends on which enums are visible, though never the meaning of a valid program.
  - **Web/Scripting:** A — **Reasoning:** devops' probe shows E0308 on `Red { x }` on an `Int` already names the variant. E0507 "unknown type `Red`" would be false when `Red` is a visible variant, and a user would hunt for a type to import. The scan runs only after resolution fails, so valid programs do not change. Min and aiml moved to A in D1 on the same evidence. **Concern:** The error code for a wrong arm can change when an unrelated import adds or removes a visible enum, which can confuse a user who searches for the code.
  - **PLT:** A — **Reasoning:** Each cause gets one code: a type in scope that does not fit is E0300, a variant of a visible enum used on a non-enum is E0308, and a name that resolves to nothing is E0507. The scan of visible enums runs only after resolution fails, so it changes an error code and never the meaning of a valid pattern. E0507 "unknown type" would be false when `Name` is a visible variant. **Concern:** The E0308 branch makes an error code depend on which enums are visible, and the spec text and the checker can drift if the visible-enum lookup changes.
  - **DevOps:** A — **Reasoning:** Three causes give three codes: a type in scope that does not fit is E0300, a name that is a visible variant on a non-enum is E0308 with today's help, a name that resolves to nothing is E0507. My probe shows E0308 already names the variant, and E0507 "unknown type `Red`" would be false for a real variant. The scan runs only on the error path, so it never changes the meaning of a valid program. **Concern:** A new import can change the error code on code that is already wrong, and the E0308 branch can drift from the other two if the visible-enum search changes.
  - **AI/ML:** A — **Reasoning:** I changed from B in D1 and hold A. The probe from devops shows that E0308 on `Red { x }` on an `Int` already names the variant and gives a fitting help. E0507 "unknown type `Red`" would be false, because `Red` is a variant, and a repair loop would look for a type to import. The spec rule stays one line: type in scope is E0300, visible variant is E0308, neither is E0507. A model reads the message and does not need to predict the scope scan. **Concern:** The E0308 branch makes the error code depend on which enums are visible, and the scan can drift from the spec text if visible-enum lookup changes.
  - **Minimalism:** A — **Reasoning:** I moved from B in D1. devops' probe shows E0308 on a variant used on a non-enum already exists, with a fitting header and help, so A adds no new surface. B would delete a working message and replace it with a false "unknown type". Subtraction that degrades the output is not worth the saving. **Concern:** The error code now depends on which enums are visible, so an import can change a code (never the meaning of a valid program), and the E0308 branch may drift if visible-enum lookup changes.

### Final Spec

A brace head never binds, so the first-character rule does not apply to it. The type at the pattern position decides:

```blink
type Point { x: Int, y: Int }
type Shape { At { x: Int, y: Int }, Dot }

fn px(p: Point) -> Int {
    match p {
        Point { x, .. } => x           // the struct at this position
    }
}

fn sx(s: Shape) -> Int {
    match s {
        At { x, .. } => x              // a variant of Shape
        Dot => 0
    }
}
```

- On an enum that has a variant `Name`, `Name { .. }` is that variant, also when a struct `Name` is in scope. On a struct, `Name` must be that struct. `Enum.Name { .. }` always names the variant.
- One rule at every pattern position: `match` at any depth, OR, `assert_matches`, `let`, `for`, parameters. A lowercase struct name works.
- A typo on a struct is E0507 with a did-you-mean help. A struct `Name` on an enum without that variant is E0300. On a type that is not an enum or a struct: a type in scope is E0300, a variant of a visible enum is E0308, neither is E0507. On an enum, an unknown name is E0547.
- A `note:` says that a struct `Name` is also in scope, when an error occurs inside an arm that names the variant. It has no help.
- The bare name and the paren form keep the first-character rule: `Point(x)` on a struct is E0308.

### Reading gaps and notes

- The cross-package case (a struct `Name` in scope and a variant `Name` of a dependency enum, matched on that enum) is not probed. No fixture in the repo has a path dependency.
- Today's compiler differs from the ruling in these places: a typo on a struct is E0308 (the ruling says E0507); `let` and `for` with a struct pattern do not parse; `assert_matches` does not exist.
- The ruling does not say what `Name { .. }` gives on an enum when `Name` is an enum type in scope (not a struct) and not a variant. The spec text says "a struct in scope" for that row and leaves the enum case open.
- The wording of the E0507 header ("unknown type `Name`") is the writer's choice. The ruling fixes the code and the did-you-mean help only.
- The ruling states no AI-First score, so the DECISIONS.md row has none.

