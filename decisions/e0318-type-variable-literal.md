[< All Decisions](../DECISIONS.md)

# E0318 Form for a Literal That Solves a Type Variable — Design Rationale

§3.2 *Integer literal range* says that a literal gets "the expected type at that point, or `Int` when there is none", and that a type variable that nothing has solved becomes `Int`. It names three message forms for E0318: the range form (`does not fit in U8 (0 to 255)`), the default form (`does not fit in Int, the default type`, with a `U64` help) and `no integer type holds N`. It did not say which form a literal gets when its type comes from a type variable.

Measured with the compiler before the decision (gen1): `id(9223372036854775808)` gave the range form with no help; `[1, 9223372036854775808]`, `xs.push(9223372036854775808)` and `Some(9223372036854775808)` gave the default form with no help; `id(18446744073709551616)` gave `no integer type holds`; `let y: U64 = id(9223372036854775808)` gave the range form at the literal plus `TypeError: variable y: declared type U64 but got Int`; `let big = 9223372036854775808` gave the default form with the `U64` help.

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in independent-proposal → debate → vote rounds. Quoted text is each panelist's own, verbatim; only local ticket IDs are removed. Phase A and Phase B are excerpts with attribution. Phase C and Phase D votes are quoted in full.

#### Phase A — Independent proposals

All six proposed the same core rule: the four shapes share the default form, and the help names the repair that reaches the variable. They differed on the help for a generic call, on `Some(big)`, on wording for the check order, and on the shape of the §3.2 text. Excerpts:

- **Systems:**

> All four cases (`id(big)`, `Some(big)`, `[1, big]`, `xs.push(big)`) share one message. The literal got `Int` because no type reached it, so the message is the default form: `9223372036854775808 does not fit in Int, the default type`. The range form `(-9223372036854775808 to 9223372036854775807)` is only for a literal whose type came from a source the user wrote (annotation, parameter type, field type). The reason: the message must tell the user where `Int` came from. For `id(big)` the range form says "Int is the type here", which is false. The user never wrote Int.

> This is a separate defect, not a message question. The expected type `U64` reaches `T` through the return type, so under the spec ("the expected type at that point") the variable is already `U64` when the argument is checked, and the literal fits. gen1 checks the argument before it unifies the return type with the expected type. Result: a false E0318 and a second TypeError.

- **Web/Scripting:**

> `id(big)`, `Some(big)`, `[1, big]` and `xs.push(big)` all give the same message as `let big = ...`. [...] The range form (`does not fit in U8 (0 to 255)`) tells the reader "you or the context chose U8". In all four cases nobody chose `Int`. The compiler picked it because nothing else was known. That is the exact meaning of "the default type".

> The split rule is simple. The range form applies when the type came from outside the literal (annotation, parameter type, field type). The default form applies when the compiler bound an unsolved variable to `Int`. The rule is about where the type came from, not about the syntax around the literal.

- **PLT:**

> Every literal that binds an unsolved type variable to `Int` gets the default form, `does not fit in Int, the default type`. [...] In the second case `Int` is a choice the compiler made, not a fact the program stated. The message must say so, because the user's repair is different. "Use a smaller value" is wrong advice when the user meant `U64`.

> The explicit type argument works in every case, because no erasure applies (§3.4 *Explicit Type Application*), so it is the first help for a call. A constructor takes the annotation, as the `xs` row in §3.2 does. The help never offers a repair that does not compile.

- **DevOps:**

> The range form says "your type is Int". In `id(big)` the user wrote no type. The message must say the compiler chose `Int`; that is the only fact that explains the error. [...] Four cases with one rule is also one thing to learn, one fixture, and one test.

> After E0318, the compiler must not report the `declared type U64 but got Int` follow-up. One root cause gives one error.

- **AI/ML:**

> The range form for a compiler-chosen `Int` says "Int" as if the user wrote it. An AI then tries `Int64` or a cast, and that is wrong. The default form says the type was a default, which points to an annotation.

> I ask the panel to add one sentence to the spec so the order is not open: "The expected type of the call reaches the type variables of its result type before the arguments are checked."

- **Minimalism:**

> Every literal that binds an unsolved type variable to `Int` gets the default form. The range form belongs only to a literal whose type came from a declared or solved type. [...] A second rule ("generic arguments differ from list elements") adds a case to the spec and to the compiler for no gain. Subtraction: the four shapes collapse into the existing "No expected type" bullet. No new bullet.

> A missing help costs little. A wrong help costs trust.

#### Phase B — Debate highlights

One round. All six seats ended it with "STATUS: stable, ready to vote". Position shifts and key points:

- **AI/ML (V1, changed):**

> I now support `id[U64](big)` as the help for a generic fn call. It works in every case, so the model needs one rule for calls and does not have to check whether the variable is in the result type. That check was a decision point I added, and a model can get it wrong.

- **Web/Scripting (V1, changed):**

> I give up the annotation form, which feels more familiar, because it fails for `show`-like fns.

- **Minimalism (V1, changed; later dissent):**

> I drop my special wording. Use the rule §3.4 already has: the help is the repair that reaches the variable. [...] I do not accept a second rule that says "always `id[U64]`". That would be a new rule.

- **Minimalism (V2, changed):**

> I concede. `let o: Option[U64] = Some(...)` is an annotation, it compiles, and it follows the same §3.4 rule. Five seats agree and my "no help" gave less than the rule allows. I withdraw it.

- **Systems (V1, a correction):**

> My Phase A sentence "whose return type does not mention the variable" was a slip; the intended rule is: the type-argument list works for every generic call, the annotation works only when the result type mentions the variable. One rule that always compiles beats a rule with a condition.

- **DevOps (V3, changed):**

> In Phase A I called this an inference question. After sys's reading, the existing words "the expected type at that point" already say the order. The help text depends on the order: it decides whether `let y: U64 = id(big)` is a valid repair.

- **Web/Scripting (V3, changed; later returned to a sentence in Phase D):**

> I withdraw my request for new spec text. min and devops are right: the sentence "the expected type at that point" already covers the row, and the order of checks is an inference matter.

- **PLT (V3, kept):**

> "The expected type at that point" does not say whether the call's return type meets the expected type before or after the arguments. Without an order, the phrase "nothing has solved yet" has no fixed meaning, and two compilers could accept different programs. That is a language question, not an inference detail, so devops and min are wrong to leave it out.

- **Minimalism (V3, kept):**

> No new spec text on check order. "The expected type at that point" already says it. Three seats want a sentence. I do not oppose one short sentence if it only restates that sentence, but it must not add an inference algorithm to §3.2.

- **PLT (V5, changed):**

> I concede the shape. min's appended sentence in the existing bullet is enough; I withdraw the new bullet.

- **DevOps (V6):**

> Add a test for it: for each help, a fixture compiles the help text and expects success. This makes V6 a check, not a promise. plt's point about more binders is right: `fn pair[A, B](a: A, b: B)` needs `pair[U64, B]`, which names `B` the user did not write. In that case give no help, or write the full list from the solved types. I prefer no help for the first version.

- **Minimalism (V6):**

> A help prints only when applying it compiles. Where the callee has more binders than `T`, either the help names all of them or there is no help. Keep this in the E0318 catalog entry, not in §3.2.

- **PLT (point for the vote):**

> Add the `id` example, and a `show` example whose result does not mention `T`, to the §3.2 example block. The second example shows why the first help is the type-argument list.

**Agreed by all six by the end of Phase B (not balloted).** `id(big)`, `Some(big)`, `[1, big]` and `xs.push(big)` share the default form `does not fit in Int, the default type`; the range form is for a type that came from a source the user wrote; above the `U64` maximum the message is `no integer type holds N` with no help; the number of message forms stays at three. The help names the repair that reaches the variable (§3.4); a constructor, list literal or push gets the annotation on the binding. After E0318 the compiler reports no follow-up `TypeError` for the same literal. The text is appended to the existing *No expected type* bullet, with no new bullet. A help prints only when applying it compiles. The `id(...)` example joins the §3.2 block and the E0318 catalog entry is updated. `let y: U64 = id(big)` is a compiler defect against the check order, not a message case.

#### Phase C — Final vote

- **Q1: The help for a call to a generic function** (A 5-1, Minimalism dissent; soft consensus). A: the explicit type-argument list for every generic call, `let y = id[U64](9223372036854775808)`. B: the binding annotation when the variable is in the result type, else the type-argument list.
  - **Systems:** A — `id[U64](x)` is a one-time type application that always compiles, with no rule about where the variable sits in the result type. One help form means one code path in the compiler and one fixture. Annotation-or-type-argument is a branch the compiler must evaluate per callee, and it can pick wrong. Concern: for a call that already has an expected type, `let y: U64 = id(big)` would be the shorter, more familiar repair, and the type-argument help may look heavier than needed.
  - **Web/Scripting:** A — A JS or Python dev reads one rule: "a call to a generic fn gets `id[U64](...)`". The two-branch rule in B makes the dev check whether `T` is in the result type, and they will guess wrong. The type-argument list works for every callee, so one help text means one fixture and one quick-fix. Concern: Where the annotation would have worked, the user sees a longer help than the idiom they know, and may think `id[U64]` is the only way.
  - **PLT:** A — The explicit type-argument list is the one repair that reaches every type variable. No erasure applies (§3.4 *Explicit Type Application*), so it is total over callees. The annotation reaches `T` only when `T` occurs in the result type, so rule B makes the help depend on the shape of the signature, and the typing rule gives no reason for that split. Concern: If the check order is later fixed, `let y: U64 = id(big)` also compiles, and a reader may ask why the help does not use the shorter, familiar annotation.
  - **DevOps:** A — One help form for every generic call means one rule for the LSP quick-fix and one fixture. The type-argument list compiles in every case. The annotation form compiles only when the variable is in the result type, so it needs a check that a tool can get wrong. This is the same §3.4 repair ("whatever reaches the open type variable"); the list always reaches it. Concern: A user with `let y = id(big)` may read `id[U64](...)` as noise when `let y: U64 = ...` is shorter, and may copy the wrong form to a call site where the type argument is not needed.
  - **AI/ML:** A — One help form for every generic call means one rule. The model does not need to check whether the type variable appears in the result type, and that check is a decision point it can get wrong. `id[U64](...)` compiles in every case, including `show[T](x: T)`. min's objection (a second rule) is weaker than it looks: the §3.4 rule "the repair is whatever reaches the variable" still holds, and the type-argument list always reaches it. Concern: A model that sees `id[U64](big)` for a call may copy the type-argument list into code where an annotation is shorter, but that code still compiles, so the cost is a few tokens.
  - **Minimalism:** *(dissent)* B — §3.4 already says the repair is whatever reaches the open variable. B applies that rule; A adds a second rule ("always the type-argument list for a call"). A also prints a form the user did not need when the annotation would do. B needs no new spec text, and the "help only if it compiles" check covers the case where the annotation does not yet compile. Concern: B makes the compiler pick between two help forms, and a wrong pick prints a help that fails.

- **Q2: A sentence in §3.2 on the order of checks at a call** (Phase C: A 3, B 1, C 2; A 6-0 after Phase D). A: "The expected type of the call reaches the type variables of its result type before the arguments are checked." B: PLT's two sentences. C: no new text. Phase C votes:
  - **Systems:** A — The order of checks at a call decides what the compiler does. It is one unify of the return type with the expected type before the arguments, with no runtime cost. The spec must fix that order, or two compilers can accept different programs, and the help text depends on it. aiml's sentence is the shorter one. Concern: a one-line statement of order may later be read as a full inference algorithm and constrain future changes to checking.
  - **Web/Scripting:** C — "The expected type at that point" already covers `let y: U64 = id(big)`. The row is a compiler defect, so it needs a bug ticket, not an inference sentence in the spec. A dev does not read §3.2 for the order of unification. Concern: With no sentence, a second compiler could pick argument-first order and the spec would not call it wrong.
  - **PLT:** A — I accept aiml's shorter wording. It fixes the order of checks at a call, which "the expected type at that point" leaves open. Without an order, "nothing has solved yet" has no fixed meaning, and two compilers could accept different programs. Option C does not fix that. Concern: Option A does not say that a variable solved by the expected type is not unsolved at the literal, so a reader must infer that link.
  - **DevOps:** A — The help text depends on the check order. Without a sentence, `let y: U64 = id(big)` is a valid repair under one compiler and an invalid one under another, and the quick-fix cannot know which. aiml's sentence is the shorter one and fixes the order without a rule about variables. Concern: If the sentence is vague, the implementer can read it two ways and the `id(big) + 1` case can differ between compilers.
  - **AI/ML:** B — The spec is the only source a model reads. "The expected type at that point" does not say whether a call's return type meets the expected type before or after the arguments. The `let y: U64 = id(big)` row shows that a compiler and a reader can disagree. plt's second sentence ("A variable that the expected type solves is not unsolved at the literal") closes the gap that "nothing has solved yet" leaves open. Concern: Two sentences are more than min wants, and a reader may take them as a full inference algorithm; the text must stay limited to the return-type case.
  - **Minimalism:** C — "The expected type at that point" already fixes the order. The `let y: U64 = id(big)` row is a compiler defect against that sentence, so it needs a bug ticket, not new text. A new sentence in §3.2 begins to describe an inference algorithm in a section about literals. Concern: two compilers may read "at that point" differently, and the spec has no sentence to settle it.

- **Q3: Where "a help prints only when applying it compiles" is written** (B 5-1, AI/ML dissent; soft consensus). A: in the §3.2 sentence. B: in the ERROR_CATALOG E0318 entry only.
  - **Systems:** B — "A help prints only when applying it compiles" constrains diagnostics output, not the language. It belongs in the catalog entry next to the help text. §3.2 should state what the literal's type is and which message forms exist. Concern: with the rule only in the catalog, a later edit to the §3.2 example block can add a help that no fixture compiles.
  - **Web/Scripting:** B — "Print a help only if it compiles" is a rule for the compiler author, not for the language user. It belongs in the E0318 catalog entry, where the author looks. The §3.2 sentence stays short and the dev reads only what they act on. Concern: A reader of §3.2 alone cannot tell that a missing help is deliberate and not a gap.
  - **PLT:** B — "Print a help only when it compiles" is a rule about diagnostics, not about the typing of a literal. It belongs with the E0318 catalog entry. The typing rule in §3.2 stays about types. Concern: The catalog is not normative, so an implementer may skip the rule without breaking the spec.
  - **DevOps:** B — "A help prints only when applying it compiles" is a rule about the diagnostic, not about the language. The ERROR_CATALOG is where a tool author looks for what a diagnostic must do. §3.2 stays one sentence about types. Concern: A rule only in the catalog can drift from the compiler, so Q7 must back it with fixtures.
  - **AI/ML:** *(dissent)* A — A model that learns from the spec alone does not read the error catalog. The rule that a help prints only when it compiles tells a model it can trust and copy the help. One clause in §3.2 costs few tokens. Concern: If the clause is not tested (Q7), it becomes a promise the compiler does not keep, and the spec then states something false.
  - **Minimalism:** B — Whether a help compiles is a rule for the diagnostic, not for the language. Users do not need it to write programs. It belongs in the E0318 catalog entry, which keeps §3.2 to one added sentence. Concern: a reader who only reads §3.2 does not learn that a help can be absent.

- **Q4: A callee with more type parameters than the one the literal reaches (`fn pair[A, B](a: A, b: B)`)** (Phase C: A 2, B 4; B 6-0 after Phase D). A: the help names every type parameter, from the solved types; if it cannot, no help. B: no help in that case. Phase C votes:
  - **Systems:** A — For `pair[A, B]` the type-argument list must name every parameter or it does not compile. The compiler has the solved types, so it can write `pair[U64, Str](...)`. If any parameter is unsolved, it prints no help. This keeps the help correct and complete where the compiler can know it. Concern: the help builder must render solved types back to source text, and a type that has no short source form (an inferred closure type) will silently drop the help.
  - **Web/Scripting:** B — For `pair[A, B]`, a partial list does not compile, and a full list names a type the user never wrote. No help in the first version is the simple rule: a message with no help is not wrong. A dev who sees the plain message can still find the repair in §3.4. Concern: The `pair` case, a common shape, gets a bare message and the dev asks why `id` has a help and `pair` has none.
  - **PLT:** A — A partial list such as `pair[U64, B]` does not compile, so it fails the compile rule. The compiler knows the solved types at that point, and a full list such as `pair[U64, Int]` compiles. "Name all or give none" keeps the help sound and gives the user the repair where one exists. Concern: The solved types for the other parameters may be metavariables, so the compiler must fall back to no help often, and the behavior will look uneven.
  - **DevOps:** B — `pair[U64, B]` names a type the user did not write, and a wrong or partial list costs trust. The full list from solved types needs the compiler to keep each solution at the point of error, which is more work for a rare case. No help is the safe first version; we can add help later with no spec change. Concern: A user with `pair(big, "a")` gets the message and no help, and may ask why `id` has a help and `pair` does not.
  - **AI/ML:** B — A partial list such as `pair[U64, B]` names a type the user did not write, and a model may copy it as is. No help is safer than a wrong or partial one. A model then falls back to the default-form message, which says the type is a default and points to an annotation. Concern: A model that gets no help for `pair(big, "x")` has no copyable fix, but the message still names the cause.
  - **Minimalism:** B — A partial or reconstructed list (`pair[U64, B]`) names a type the user did not write, and it needs its own rule to build. No help in that case costs little, and the rule is one line. Add the all-parameters help later if a user needs it. Concern: users with multi-parameter callees get a bare message and must find the repair in §3.4.

- **Q5: A `Some(...)` line, with its help, in the §3.2 example block** (Phase C: A 3, B 3; A 4-2 after Phase D). A: yes. B: no. Phase C votes:
  - **Systems:** B — The `Some(...)` annotation form follows the same rule as the `xs.push` row already in the block. One more row adds no new fact. Spec text stays short. Concern: a reader may not see that constructors take the annotation while calls take the type-argument list.
  - **Web/Scripting:** A — `Some(big)` is the case a dev hits first, more often than `id(big)`. An example in the spec is what a dev or a model copies. It costs one row. Concern: The block grows to six rows, and a reader may take the `Some` row as the one special case.
  - **PLT:** B — The existing `xs.push` row already shows an annotation repair. One new row (`id`) and one for Q6 are enough to show both help forms. More rows add no new rule. Concern: Without a `Some(...)` row, a reader may think constructors get a type-argument help.
  - **DevOps:** A — Examples are the contract that the LSP quick-fix, the fixtures, and an AI copy. `Some(...)` is the constructor shape and shows the annotation help, which `id` does not show. One more row is cheap. Concern: The example block grows, and each row is one more line to keep in step with the compiler output.
  - **AI/ML:** A — Examples teach a model more than prose. The `Some(...)` line shows the constructor rule (annotation on the binding), which differs from the call rule (type-argument list). Without it, the model sees only calls and the push row. Concern: The block gets longer, which costs tokens on every read of §3.2, but by one line.
  - **Minimalism:** B — The `id(...)` row is the new case. The `Some(...)` case uses the same rule as the `xs.push` row already in the block, so a row would repeat what the block shows. Keep the spec text to one sentence plus one example row. Concern: models and users learn from examples, and the constructor shape has no example in the spec.

- **Q6: A `show[T](x: T)` line (result does not mention `T`) in the §3.2 example block** (Phase C: A 4, B 2; A 6-0 after Phase D). A: yes. B: no. Phase C votes:
  - **Systems:** A — The `show[T](x: T)` row is the case where the annotation cannot reach `T`. It shows why Q1 picks the type-argument list, and it is a real shape in systems code (a sink or a hash function that returns a fixed type). Concern: the block grows by one row, and readers may take `show` as a reason to prefer the type-argument list even where an annotation is shorter.
  - **Web/Scripting:** B — The `id` row already shows the type-argument help. The reader does not need a second row to know it is for every call. The `show` row serves the spec author, not the user, and a fifth call-shape row crowds the block. Concern: Without `show`, a dev may think `let y: U64 = id(...)` works for every generic call and be surprised by the one that does not.
  - **PLT:** A — `show[T](x: T)` is the only case where the annotation cannot reach `T`. This row shows why the call help is the type-argument list, and it shows the §3.4 rule at work. Concern: The extra row makes the §3.2 block longer for a case that is rare in real code.
  - **DevOps:** A — The `show[T](x: T)` row shows the reader why calls get the type-argument list: the annotation cannot reach `T` there. Without it, Q1 A looks like an arbitrary choice. It is the one row that tests the case where an annotation help would not compile. Concern: min's count of rows is fair; the block gets long, and a row that tests an edge may read as a rule for the edge.
  - **AI/ML:** A — The `show[T](x: T)` line is the only example where the annotation cannot reach the variable. It shows why the help for a call is a type-argument list, so the model does not infer a rule from `id` alone, where both forms work once the check order is fixed. Concern: One more row to keep in step with the compiler output; the fixture from Q7 covers it.
  - **Minimalism:** B — With Q1 = B, the `show` row would teach a branch of the rule that §3.4 already states in prose. A second row adds length to the §3.2 block for a point that belongs to §3.4. One row for `id` is enough. Concern: without the `show` row, the type-argument-list help has no example in §3.2.

- **Q7: A test rule: each printed help has a fixture that compiles it** (A 6-0). A: in the implementation ticket and the decision file, not in sections/. B: leave it to the implementer.
  - **Systems:** A — A help that does not compile is a wrong answer printed by the toolchain. A fixture that compiles each printed help makes the rule a check. It is a test rule, so it belongs in the ticket and the decision file, not in sections/. Concern: the fixtures bind to exact help text, so any wording change in a help breaks them and the fixtures need updating with each change.
  - **Web/Scripting:** A — A wrong help sends a dev to Stack Overflow with an error that the compiler itself caused. A fixture that compiles each printed help keeps the contract true as the compiler changes. It lives in the ticket and the decision file, so the spec stays clear of test rules. Concern: The rule rests on the implementer reading the ticket, and a later help added without a fixture will go unseen.
  - **PLT:** A — A rule that no test checks stops being true over time. One fixture per help form, which compiles the printed text, makes the compile rule a property of the suite. It belongs in the ticket and the decision file, not in sections/. Concern: A fixture proves each form once, not each callee shape, so a new shape can still print a wrong help.
  - **DevOps:** A — "Print only if it compiles" is a promise until a fixture checks it. A fixture per help, compiled in the corpus, makes it a test. It belongs in the ticket and the decision file, not in sections/, because it is a test rule, not a language rule. Concern: A rule in a ticket and a decision file can be lost; the implementer must carry it into a test file, and nothing enforces that.
  - **AI/ML:** A — The rule "a help prints only when it compiles" is checkable. A fixture per help turns it from a promise into a test. Since the corpus is training data for models, a printed help that fails to compile teaches wrong code. Concern: Each new help shape needs a fixture, so the compiler author may choose to print fewer helps; that is acceptable.
  - **Minimalism:** A — This is a test rule in the ticket and the decision file, not in sections/, so it adds nothing to the language surface. It makes the Q3 rule checkable at a small cost. A help that fails to compile costs trust. Concern: the fixture set grows with each new help shape, and someone must keep it current.

#### Phase D — Round 2 (Q2, Q4, Q5, Q6)

Phase C left Q2 at A 3, B 1, C 2, Q4 at A 2, B 4, Q5 at A 3, B 3 and Q6 at A 4, B 2. Q1, Q3 and Q7 were decided and not reopened. Each seat answered the strongest argument against its vote in a focused debate (D1), then voted again alone (D2).

**D1 debate highlights**

- **Q2, DevOps (kept A):**

> The strongest argument against is min's: a sentence in §3.2 starts to describe an inference algorithm. I answer that the sentence states one order, the expected type first, and no algorithm. web says the existing words already cover the row. They do not name an order, so a compiler that checks the argument first can claim to follow them.

- **Q2, PLT (kept A):**

> The sentence does not give an algorithm. It fixes which programs the language accepts. With argument-first order, `let y: U64 = id(big)` is an error. With result-first order, it is valid. Two compilers that read "at that point" differently accept different programs, and web and min both admit this in their Concerns. A rule that decides acceptance belongs in the spec.

- **Q2, Minimalism (changed C to A):**

> Strongest argument against C (devops, sys, plt): without an order, two compilers accept different programs, because `let y: U64 = id(big)` compiles in one and not in the other. That is a difference in which programs are valid, so it is the spec's job, not an inference detail. I also said I would not oppose one short sentence that only restates "the expected type at that point". aiml's wording does that and gives no algorithm.

- **Q2, AI/ML (changed B to A):**

> the first sentence alone fixes the order, which is the only thing the spec lacked.

- **Q2, Web/Scripting (changed C to A):**

> I agree that this is a thing a dev would try. They write `: U64` because it is the familiar fix. The spec should say it works.

- **Q4, Systems (changed A to B):**

> I checked my own claim, "the compiler has the solved types": at the literal, the other parameters (`B` in `pair[A, B]`) may not be solved yet, because later arguments are not checked. So A would often print no help anyway, or need a second pass. A rule that mostly gives no help is B with extra code.

- **Q4, PLT (changed A to B):**

> This holds. Both options keep the compile rule, because A also prints no help when any parameter is unsolved. The difference is only how often a help appears, and the spec does not need to fix that. B is the safe first version. The compiler may add the full list later with no spec change. I withdraw A.

- **Q5, PLT (changed B to A):**

> It adds a new shape. The `xs.push` row repairs a list binding. It does not show a constructor call, and my own Concern was that a reader would expect a type-argument help for a constructor. `Some(big)` is the first shape a user meets. One row makes the constructor rule visible, and the cost is one line. The vote is 3-3, so I give my vote to A.

- **Q5, Systems (kept B):**

> the `xs.push` row already shows the annotation repair on the binding, and the agreed text states the rule for constructors. One more row repeats that fact. If the panel wants a constructor row, I accept it; it costs only one line and no new rule.

- **Q5, Minimalism (kept B):**

> the `xs.push` row already shows the annotation repair for a shape the compiler cannot reach with a type-argument list. The `Some` row repeats that fact. The block has five rows before Q5; I would not make it six for a repeat.

- **Q6, Minimalism (changed B to A):**

> My Phase C reasoning assumed Q1 = B. Q1 is now A (5-1), so the call help is always the type-argument list. The strongest argument against my vote (devops): without the `show` row, that choice looks arbitrary, and a user may think `let y: U64 = id(...)` works for every call. The `show` row is the only row that shows why. It is a new fact, not a repeat, so it passes the test I apply to Q5.

- **Q6, Web/Scripting (changed B to A):**

> Without the `show` row, the `id` row alone makes the type-argument help look arbitrary, because after the check order is fixed both forms work for `id`. That is the surprise I named in my own concern. Four seats want it, and it costs one row.

**D2 re-vote**

- **Q2: the order sentence** (A 6-0; Phase C 3-1-2).
  - **Systems:** A — The order of checks at a call fixes what the compiler does: one unify of the return type with the expected type, before the arguments. Without a sentence, two compilers can accept different programs for `let y: U64 = id(big)`, and the help depends on the order. aiml's sentence is the shorter one and it states an order, not an inference algorithm. Concern: a reader may take the one-line order as the full inference algorithm and so limit later changes to checking.
  - **Web/Scripting:** A — A dev who writes `let y: U64 = id(big)` uses the fix they know. The spec must say that it works, or two compilers will answer differently and the dev cannot tell which is right. aiml's one sentence states the order and gives no inference algorithm. Concern: A reader may take one sentence about call order in the literals section as the whole inference rule.
  - **PLT:** A — The sentence fixes an order of checks at a call: the expected type meets the return type before the arguments. That order decides which programs the language accepts (`let y: U64 = id(big)` is valid with result-first order and an error with argument-first order), so it belongs in the spec. The link "a variable that the expected type solves is not unsolved at the literal" follows from the order sentence in one step. B adds no typing content that A lacks, and A is the text min and web now accept. Concern: A reader may take the sentence as a full inference algorithm, so later work on checking order must keep the text limited to the return-type case.
  - **DevOps:** A — The help for `let y: U64 = id(big)` depends on the order of checks at a call. Without a stated order, a quick-fix cannot know if the annotation repair compiles. aiml's sentence states the order in one line and names no inference algorithm. After D1, web, min and aiml also moved to A. Concern: If an implementer reads the sentence as covering only direct result-type variables, `id(big) + 1` can still differ between compilers.
  - **AI/ML:** A — The gap in the spec is the order of checks at a call, and the first sentence fixes it. A model that reads "The expected type of the call reaches the type variables of its result type before the arguments are checked" can draw the link to the literal in one step. It is the shorter text, and it states an order, not an inference algorithm. Concern: A reader may take one order sentence as the whole inference rule and assume it covers cases (for example, a result type that is itself a bare variable with no expected type) that it does not address.
  - **Minimalism:** A — The order of checks decides which programs the language accepts (`let y: U64 = id(big)` is valid or not), so it is a spec matter, not an inference detail. aiml's sentence states one order and no algorithm. It restates "the expected type at that point" and makes it exact. plt's second sentence follows from the first, so B adds length with no new fact. Concern: A reader may take the sentence as the start of an inference algorithm, and later changes to call checking will cite it.

- **Q4: a callee with more type parameters than the literal reaches** (B 6-0; Phase C 4-2).
  - **Systems:** B — At the literal, the other type parameters (`B` in `pair[A, B]`) may not be solved yet, because later arguments are not checked. Option A would often print no help, or need a second pass, and it risks a wrong list. No help in the first version costs nothing at run time, and help can be added later with no spec change. Concern: a developer asks why `id` has a help and `pair` has none.
  - **Web/Scripting:** B — A bare message is not wrong, and the full list for `pair[A, B]` needs every solution kept at the point of error. Other parameters are often not solved at the literal, so A would often print no help anyway. A later release can add the list with no spec change. Concern: A dev with `pair(big, "a")` gets no help and asks why `id` has one.
  - **PLT:** B — Both options keep the rule that a help prints only when it compiles, so they differ only in how often a help appears, which the spec need not fix. At the literal, the other type parameters (`B` in `pair[A, B]`) may not be solved, because later arguments are not checked yet. Then A prints no help in most cases and costs a renderer from solved types to source text. No help is sound, and the compiler may add the full list later with no spec change. Concern: A user with `pair(big, "a")` gets the message and no help, and may ask why `id` has a help and `pair` has none.
  - **DevOps:** B — A full type-argument list needs every parameter solved at the point of error, and later arguments are not checked yet, so help would often be absent anyway. It also needs a printer from solved types to source text, with a second fixture set. No help is never wrong, and a later release can add the full list with no spec change. Concern: A user with `pair(big, "a")` gets a bare message and may ask why `id` has a help and `pair` has none.
  - **AI/ML:** B — One rule, "no help in that case", is a rule a model learns in one read. A full list needs solved types that may not exist at the literal, so the help would appear by a condition the model cannot see from the spec. A partial or reconstructed list names a type the user did not write, and a model may copy it. Concern: A model that gets no help for `pair(big, "x")` has no copyable fix, though the default-form message still names the cause.
  - **Minimalism:** B — A partial list does not compile, and a full list needs every parameter solved at the literal, which is often false because later arguments are not checked yet. A would print no help in many cases and needs a renderer from solved types to source text. No help is never wrong, and a later release can add the full list with no spec change. Concern: A user with `pair(big, "a")` gets a bare message and asks why `id` has a help and `pair` has none.

- **Q5: a `Some(...)` example row** (A 4-2; Phase C 3-3; Systems and Minimalism dissent).
  - **Systems:** *(dissent)* B — The `xs.push` row already shows the annotation repair on the binding, and the agreed text states the rule for constructors. One more row repeats a fact the block already shows. I accept a `Some(...)` row if the panel keeps it, since it costs one line and adds no rule. Concern: a reader may think a constructor gets a type-argument help, because the block has no constructor row.
  - **Web/Scripting:** A — `Some(big)` is the first shape a JS or Python dev meets, and a statement-form `xs.push` row does not match it. The row shows the constructor repair is an annotation on the binding, not a type-argument list. It costs one line. Concern: The block grows to seven rows, and a reader may take the `Some` row as a special case.
  - **PLT:** A — The `xs.push` row shows an annotation on a `let mut` with an empty list. It does not show a constructor call with the literal inside, which is the first shape a user meets. My own concern was that a reader would expect a type-argument help for a constructor, and one row removes that guess. The vote is 3-3 without me, and the cost is one line. Concern: The block grows to seven rows, and a reader may take the `Some(...)` row as a special case and not as an instance of the annotation rule.
  - **DevOps:** A — Examples are the contract for the LSP quick-fix, the fixtures and an AI. `Some(big)` is an expression in a `let` and shows the annotation help on the binding, which no existing row shows. One row stops a reader from expecting a type-argument help for a constructor. Concern: The block grows to seven rows, and each row is one more line to keep in step with compiler output.
  - **AI/ML:** A — Models copy examples more than they follow prose. `Some(...)` is the constructor shape and shows an annotation on the binding inside an expression, which the `xs.push` row (a statement on a `let mut`) does not show. One row stops a model from guessing that a constructor gets a type-argument list. Concern: The block grows by one row, which costs a few tokens on every read of §3.2.
  - **Minimalism:** *(dissent)* B — The `xs.push` row already shows the annotation repair, and the agreed text states the constructor rule. A `Some(...)` row repeats a fact the block already has. The block is five rows with the `id` row and the `show` row. I would not make it six for a repeat. Concern: Models and users copy examples, and the constructor shape in an expression position has no example in §3.2.

- **Q6: a `show[T](x: T)` example row** (A 6-0; Phase C 4-2).
  - **Systems:** A — `show[T](x: T)` is the one row where the annotation cannot reach `T`. It shows why the help for a call is the type-argument list. With `id` alone, both repairs work once the check order is fixed, and Q1 A looks arbitrary. Concern: the block grows by one row, and readers may prefer the type-argument list even where an annotation is shorter.
  - **Web/Scripting:** A — With only `id`, both repairs compile once the order is fixed, so the type-argument help looks arbitrary. `show[T](x: T)` is the one row where the annotation cannot reach `T`. Without it, a dev may think the annotation works for every generic call. Concern: A rare edge case takes a row in the block, and a reader may take it for a rule of its own.
  - **PLT:** A — With only the `id` row, both the annotation and the type-argument list compile once the check order is fixed, so the example hides why a call gets the type-argument list. `show[T](x: T)` is the one case where the annotation cannot reach `T`, because `T` is not in the result type. The row shows the §3.4 rule ("the repair is whatever reaches the open type variable") at the place a user reads. Concern: A reader may take `show` as a reason to prefer the type-argument list even where an annotation is shorter, and the extra row must stay in step with compiler output through the Q7 fixture.
  - **DevOps:** A — `show[T](x: T)` is the only row where the annotation cannot reach `T`. It shows why a call gets the type-argument list, so Q1 A does not look arbitrary. It is also the one row that exercises the case where an annotation help would not compile. Concern: A row for an edge shape may read as a rule for that edge, and the block gets long.
  - **AI/ML:** A — `show[T](x: T)` is the only row where an annotation cannot reach `T`. Without it, `id` alone makes both repairs look valid and the type-argument help looks arbitrary. A model learns the rule from the row, not from a cross-reference to §3.4. Concern: The row may read as a rule for an edge case, and it must stay in step with the compiler output (the Q7 fixture covers it).
  - **Minimalism:** A — With Q1 = A, the call help is always the type-argument list. The `show[T](x: T)` row is the only row where an annotation cannot reach `T`, so it is the one row that shows why. It is a new fact, not a repeat, and it passes the test that I apply to Q5. Concern: A reader may take the edge case `show` as the usual case and prefer the type-argument list where an annotation is shorter.

#### Dissents and concerns

No owner tiebreak was used. The owner approved the tally.

- **Q1 (Minimalism dissent, soft consensus).** Minimalism's own words: "§3.4 already says the repair is whatever reaches the open variable. B applies that rule; A adds a second rule". Minimalism's Phase D note: "Q1 is now A (5-1), so the call help is always the type-argument list."
- **Q3 (AI/ML dissent, soft consensus).** AI/ML's own words: "A model that learns from the spec alone does not read the error catalog." Concern: "If the clause is not tested (Q7), it becomes a promise the compiler does not keep, and the spec then states something false." The Q7 fixture rule answers the concern.
- **Q5 (Systems and Minimalism dissent).** Both name the majority's point as their own concern: "a reader may think a constructor gets a type-argument help" (Systems) and "the constructor shape in an expression position has no example in §3.2" (Minimalism). Systems: "I accept a `Some(...)` row if the panel keeps it".
- **Shared concerns, not dissents.** Q2: Systems, Web/Scripting, PLT, Minimalism and AI/ML name the same risk: a reader may take the one sentence as the start of an inference algorithm. Q4: all six name the same risk: a user with `pair(big, "a")` asks why `id` has a help and `pair` has none; all say a later release can add the full list with no spec change. Q6: Systems, PLT and Minimalism name the risk that a reader prefers the type-argument list where an annotation is shorter.

#### Reading gaps

- **Check order beyond the result type.** DevOps: "If an implementer reads the sentence as covering only direct result-type variables, `id(big) + 1` can still differ between compilers." The sentence says that the expected type of the call reaches the type variables of the call's result type. In `id(big) + 1`, the expected type that reaches the call comes from the operator rules of §3.2 *Operator operands*; where none reaches it, the variable is unsolved and the literal gets the default form. AI/ML names a second gap: "a result type that is itself a bare variable with no expected type". The same reading applies. The spec does not add a rule for either.
- **Spec leads the compiler.** gen1 reports a range-form E0318 and a second `TypeError` for `let y: U64 = id(9223372036854775808)`. The §3.2 example block marks that row `OK`, as the sentence requires. The row is not one of the three rows in the ruling; the writer added it, because the order sentence is a new rule and each new rule needs an example. gen1 also gives the range form with no help for `id(big)`, and the default form with no help for `Some(big)`, `[1, big]` and `xs.push(big)`. Those rows state the ruled behavior; the compiler does not match them yet.
- **`Some[U64](big)`.** Systems asked in Phase B whether a type-argument form for a constructor is legal, and no seat used one. The spec gives a constructor the annotation help only.
- **Text from the tally that no seat balloted.** The *No expected type* sentence says that no other error follows E0318 for the same literal; this is the agreed point "No follow-up TypeError after E0318".
- **Which parameters the literal reaches.** The spec says "no `help:`" when the callee has more type parameters than the literal reaches. It does not say how many parameters count as reached. The panel said a later release can add the full list with no spec change.

#### Test rule (Q7)

Each printed help has a fixture that compiles the help text and expects success. For this decision the fixtures cover `id[U64](...)`, `show[U64](...)`, the `Option[U64]` annotation for a constructor, the `List[U64]` annotation for a list literal and for a push, plus a fixture for each message row above: one E0318 and no follow-up `TypeError` for `id(big)`, no help for a callee such as `pair`, and `no integer type holds N` with no help above the `U64` maximum. The rule belongs to the implementation ticket and to this file. It is not in `sections/`.

### Final Spec

```blink
fn id[T](x: T) -> T { x }
fn show[T](x: T) { }

fn main() {
    let w: U64 = id(9223372036854775808)    // OK: U64 reaches T before the argument is checked
    let y = id(9223372036854775808)         // error[IntLiteralOutOfRange]: 9223372036854775808 does not fit in Int, the default type
                                            //   help: let y = id[U64](9223372036854775808)
    let o = Some(9223372036854775808)       // error[IntLiteralOutOfRange]: 9223372036854775808 does not fit in Int, the default type
                                            //   help: let o: Option[U64] = Some(9223372036854775808)
    show(9223372036854775808)               // error[IntLiteralOutOfRange]: 9223372036854775808 does not fit in Int, the default type
                                            //   help: show[U64](9223372036854775808)
}
```

- A literal checked against a type variable that nothing solved has no expected type. In a generic call, a constructor, a list literal or a push, it gets the default form; the range form is only for a type the program wrote; above the `U64` maximum the message is `no integer type holds N`, with no help.
- The help names the repair that reaches the variable: an explicit type-argument list for every generic call; an annotation on the binding for a constructor, a list literal or a push; no help when the callee has more type parameters than the literal reaches.
- After E0318 the compiler gives no other error for the same literal.
- §3.2 gains one sentence: "The expected type of the call reaches the type variables of its result type before the arguments are checked."
- The §3.2 example block gains the `id(...)`, `Some(...)` and `show[T](x: T)` rows, and one `OK` row for `let w: U64 = id(...)`.
- "A help prints only when applying it compiles" is written in the ERROR_CATALOG E0318 entry only.
- Each printed help has a fixture that compiles it (implementation ticket and this file).
