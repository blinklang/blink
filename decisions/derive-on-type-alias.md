[< All Decisions](../DECISIONS.md)

# `@derive` and the Other Annotations on a Type Alias — Design Rationale

The §11.1 table lists the target of `@derive` as `type`, and §3.4 *Newtypes* says that a type alias is not a newtype: both names are the same type. Nothing said whether `type X = <type>` is a valid target. The compiler accepted `@derive(Hash, Eq)` on `type K = (Int, Str)` and ignored it. On `type A = Plain` it also ignored the derive, and the program then failed with E0306 on `Plain`. On `type L = List[Int]` it ignored the derive, and the program then failed with E1400 on `L`. The same gap held for the other rows with Target `type`: `@src`, `@where`, `@invariant`, `@ffi.struct`, `@ffi.opaque`, `@allow` and `@deprecated`.

This ruling settles both questions. Before 1.0 a new error is an error at once (§8.16.1), so the ballot did not cover rollout.

## Summary

| Q | Question | Result | Vote |
|---|---|---|---|
| Q1 | `@derive` on a type alias | E1110 `UnexpectedAnnotation` for every alias target (a struct or enum of this package, a tuple, a built-in type, a container, a type from another package, a generic alias). No new code. `type` in the §11.1 Target column means a declaration that creates a type. The help names the declaration that takes the derive, when the alias names a struct or enum of this package. `blink fix` deletes the attribute line, for every alias, and never moves the derive | 6-0 |
| Q2 | The other `Target: type` annotations on an alias | `@src`, `@deprecated` and `@allow` are legal on an alias. `@where`, `@invariant`, `@ffi.struct` and `@ffi.opaque` are E1110 | 6-0 |

The editor quick fix that moves the derive to the declaration of the aliased type (DevOps, V1c) adds no spec text. Four seats called it an editor feature, so it was not on the ballot.

`impl Shout for K`, where `K` aliases a tuple, is accepted and then fails at the call with E0505. All six seats flagged it as a separate question. It is not decided here.

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in independent-proposal, debate and vote rounds. Quotes are verbatim; a long reply is cut to the excerpt that carries the position.

#### Phase A — Independent proposals

All six seats proposed the same core rule: `@derive` on any type alias is E1110, with no new code. No seat proposed accept-and-ignore, or forwarding the derive to the aliased type.

- **Systems:**

  > SYS (Systems) Phase A proposal: `@derive` on a type alias is an error. I did not run the compiler; I worked from the brief's table.
  >
  > PROPOSAL A (my pick): reject, with the existing E1110 UnexpectedAnnotation.
  > In the §11.1 table, Target `type` means a declaration that creates a type: struct, enum, newtype. An alias creates no type. A `type X = <type>` declaration is not a `type` target for `@derive`, `@invariant`, `@where`, `@ffi.struct` or `@ffi.opaque`.
  >
  > ```blink
  > @derive(Hash, Eq)
  > type P = (Int, Str)
  > // error[E1110]: UnexpectedAnnotation: @derive does not apply to a type alias
  > //   help: `P` is another name for `(Int, Str)`. Remove @derive here.
  > //         Add @derive to the declaration of the aliased type, if you own it.
  > //   fix: remove the attribute (machine-applicable)
  >
  > type Plain { x: Int }
  > @derive(Debug)
  > type A = Plain
  > // same E1110. The help text points to `type Plain`.
  > ```
  >
  > This fixes the row 2 case in the measured table. Today the user adds the derive on `A`, gets E0306 on `Plain`, and the attribute silently does nothing. After the change the error appears at the attribute that has no effect.
  >
  > Behavior for related cases:
  > - Alias of a local struct or enum: E1110 with the help above. The derive belongs on the declaration. Mechanically it has to: derive emits impl code, and layout, hash and eq functions are keyed by the type's declaration identity (§3.4 point 8). An alias has no identity of its own, so there is nothing to emit.
  > - Alias of a tuple: E1110. Tuples already get Eq, Ord, Hash, Debug and Clone structurally (§3.8). A derive would be a no-op. This matches row 1 and row 4.
  > - Alias of List, Map, Set, Option, Result, Bytes or a fn type: E1110, with extra help that the aliased type "cannot gain" Hash (fact 7). Row 3 (`type L = List[Int]` used as a `Set[L]` element) stays E1400 on `L`, judged by the aliased type. The alias derive cannot change that.
  > - Alias of a type from another package: E1110. A derive would be a foreign impl, which the orphan rule forbids (fact 4). It would also break coherence (fact 5): `@derive(Eq)` on `type A = Plain` next to `@derive(Eq)` on `Plain` gives two impls for one (Trait, Type) pair.
  > - Generic alias `type Pair[T] = (T, T)`: E1110 under the same rule.
  >
  > Other `Target: type` annotations on an alias:
  > - `@deprecated` and `@allow`: legal, because they apply to the name. Deprecating a name is a real use.
  > - `@src`: legal, because it is metadata about the declaration site.
  > - `@where`, `@invariant`, `@ffi.struct`, `@ffi.opaque`: E1110. Each needs an owned type with its own layout, constructor or check point.
  > - The table should get an explicit `alias` target that lists `@deprecated`, `@allow` and `@src`.
  >
  > Systems tradeoffs:
  > - Runtime cost is zero either way. Rejecting means the compiler needs no alias-derive codegen path. The interim crash fix has a dead path today; rejection removes it, and the path in the brief's "separate codegen bug" cannot occur.
  > - Predictable codegen: a user never believes a Hash or Clone impl exists on a type they do not own. Hash and Eq on a Map key change the memory layout and cost of the key (hash function, compare function). An attribute that silently does not change them is the worst case.
  > - Monomorphization: an alias is erased at the typecheck or mono boundary. Rejecting it early keeps that erasure total. Accepting would force alias identity to survive into mono, which is a cost for nothing.
  >
  > PROPOSAL B (rejected): accept and ignore, with a warning.
  > - This keeps the "silent no-op" shape, only louder.
  > - A warning on a call is not a fix. The user reads a green build as proof.
  > - Pre-1.0 policy (fact 9) says to make it an error at once.
  >
  > PROPOSAL C (rejected): the derive on an alias forwards to the aliased local type.
  > - This acts at a distance.
  > - It conflicts with a derive on the target, which breaks coherence.
  > - It makes two spellings of one type behave differently depending on which name carries the attribute.
  >
  > Cross-language note:
  > - Rust: `#[derive]` on a `type` alias is an error ("`derive` may only be applied to `struct`s, `enum`s and `union`s").
  > - C and Zig: `typedef` and `const X = T` give no place to attach behavior.
  > - Go: `type A = B` aliases cannot have methods, while `type A B` can. That is the same split as Blink's alias vs newtype.
  >
  > Sub-question for the others to check: should the E1110 machine fix delete the attribute, or move it to the aliased type's declaration when that type is local? I lean toward delete only. A move changes another declaration and may collide with an existing derive.

- **Web/Scripting:**

  > WEB Phase A proposal: reject @derive on a type alias with the existing E1110. No new code.
  >
  > PROPOSAL 1 (my pick): `@derive` is legal only on a type declaration that defines a type (struct, enum, newtype). On an alias it is E1110 UnexpectedAnnotation. The compiler names the alias case and says where the derive goes.
  >
  > ```blink
  > @derive(Hash, Eq)
  > type K = (Int, Str)
  > ```
  > ```
  > error[E1110]: @derive is not allowed on a type alias
  >   --> k.bl:1:1
  >   help: an alias is the same type as `(Int, Str)`. A tuple already has Hash and Eq.
  > ```
  >
  > ```blink
  > type Plain { x: Int }
  >
  > @derive(Debug)
  > type A = Plain
  > ```
  > ```
  > error[E1110]: @derive is not allowed on a type alias
  >   help: `A` is `Plain`. Move `@derive(Debug)` to `type Plain`.
  > ```
  >
  > Machine fix: for an alias of a local struct or enum, move the derive line to that declaration. For any other alias (tuple, List, built-in, other package), the fix deletes the line, because the derive grants nothing or cannot be granted (see the orphan rule and the no-Hash containers). Other `Target: type` annotations on an alias:
  > - `@deprecated` and `@allow` stay legal. They help people who rename a type, and they describe the name, not the type.
  > - `@derive`, `@invariant`, `@where`, `@src`, `@ffi.struct`, `@ffi.opaque` are E1110. Each one adds behavior or layout to a type. An alias has neither.
  > A generic alias (`type Pair[T] = (T, T)`) follows the same rule. No special case.
  >
  > Why this is right:
  > 1. Spec rule 2 already gives E1110 for a target the row does not list. Fact 1 says an alias is not a new type. So "type" in the table means "type declaration". The ticket needs one clarifying row and one test, not a new rule.
  > 2. Accept-and-ignore is the worst result for a user. Row 2 of the measured table shows it: the user writes `@derive(Debug)` on `A`, it does nothing, and E0306 still fires later with a help that points at a different line. An attribute that silently does nothing is the thing Stack Overflow questions grow from ("why does my derive not work?"). Python and TS users expect a decorator or attribute to do something or to fail loudly.
  > 3. Fact 8 and the orphan rule agree. An alias makes no declaration identity. A derive needs an identity to attach an impl to. For `L = List[Int]` it would give Hash to a type that "cannot gain" it.
  > 4. A user who really wants a distinct type with its own derive writes a newtype. The help text can say so: `type K { key: (Int, Str) }`. This is the 90% fix for someone who reached for the alias because they wanted a distinct key type.
  >
  > Tradeoffs:
  > - Cost: one more error for a rare form. Pre-1.0 policy covers rollout.
  > - Risk: users who copy the derive from the aliased type get an error at once. The help text solves it in one step.
  > - The partial-accept option (allow the derive only on an alias of a local type, as forward to the target) was my second choice. I reject it. It makes the meaning depend on what the right side names, so the same line is legal for `type A = Plain` and illegal for `type K = (Int, Str)`. It also hides which declaration owns the impl, and a reader of `A` cannot see that Debug comes from there. Fact 8 says identity, not spelling. This option works against that.
  >
  > Related fact, not this ticket: `impl Shout for K` accepted but then E0505 on the call (table row 6) is the same silent-do-nothing class. I suggest a separate ticket: an impl through an alias of a non-local type should be an error too (orphan rule), and `impl ... for A` where `A = Plain` is fine (row 7).
  >
  > Cross-language: Rust `#[derive]` on `type A = Plain;` is an error ("derive may only be applied to structs, enums and unions"). TypeScript has no derive, but a decorator on a type alias is an error (decorators need a class). Kotlin `typealias` accepts no annotation that changes behavior. Rust, TS and Kotlin all say no. Blink matches them.

- **PLT:**

  > PLT proposal (Phase A): `@derive` on a type alias is an error. Reuse E1110 UnexpectedAnnotation. No new code.
  >
  > **Behavior**
  > The `Target: type` rows (`@derive`, `@where`, `@invariant`, `@ffi.struct`, `@ffi.opaque`) mean a nominal declaration: struct, enum, newtype. An alias is not a nominal declaration. It is a name for a type, so it has no identity to carry a derive.
  >
  > ```
  > @derive(Hash, Eq)
  > type K = (Int, Str)
  > // error[E1110]: `@derive` does not apply to a type alias
  > //   `K` is another name for `(Int, Str)`; an alias has no impls of its own
  > //   help: delete the attribute. `(Int, Str)` already has Hash and Eq (structural, 3.8)
  > //   help: for a distinct type with its own derive, declare a newtype:
  > //         @derive(Hash, Eq)
  > //         type K { key: (Int, Str) }
  > ```
  > The same error applies to every alias: aliases of local structs, enums, builtins and foreign-package types, and generic aliases like `type Pair[T] = (T, T)`.
  > - Machine fix: delete the attribute.
  > - Where the alias target is a local nominal type, the help says "put `@derive` on `type Plain`".
  >
  > **Why (soundness)**
  > 1. Typing rule. `@derive(T)` on declaration D generates `impl T for D` in D's module. The orphan argument in 3.6 ("trivially satisfies the orphan rule") holds only because D is the type's defining declaration. With an alias, the impl subject is the aliased type, which this declaration does not define.
  >    - Alias of a tuple, List or foreign type: this is an orphan impl, which 3.6 forbids.
  >    - Alias of a local struct, as in `type A = Plain`: the derive either duplicates Plain's impl (coherence violation, one impl per (Trait, Type)) or gives Plain an impl that Plain's own declaration does not show. Both break the rule that the declaration site determines the impls.
  > 2. Accept-and-ignore is a silent no-op. Your measured row 2 shows it: the user writes `@derive(Debug)` on `A`, the program then fails with E0306 on `Plain`, and the help points at `Plain`. The attribute reads as a promise and grants nothing. A static contract that does nothing is the worst case for AI-generated code, because the model reads the attribute as evidence that the trait holds.
  > 3. Identity, not spelling (fact 8). Alias-site metadata cannot change the behavior of the aliased type, or `type A = Plain` and `Plain` would behave differently while being the same type. That is the one semantic an alias must not break.
  >
  > **Sub-question: other `Target: type` annotations on an alias**
  > Split by what the annotation talks about.
  > - Type-level (about the type's structure or identity): `@derive`, `@where`, `@invariant`, `@ffi.struct`, `@ffi.opaque`. All E1110 on an alias. `@invariant` on an alias would constrain a type that other names also reach, so it cannot be sound.
  > - Name-level (about the spelling): `@deprecated`, `@allow`, `@src`. Legal on an alias, and the table should list `alias` as a target for these rows. `@deprecated type OldId = Int` is useful and sound, because deprecation follows the name at use sites and changes no typing.
  >
  > **Related fact 73 (not this ticket)**
  > `impl Shout for K` where `K = (Int, Str)` is accepted and then unreachable. By the same principle the impl subject is the aliased type. It should go through the orphan check (user trait on a tuple is legal for the trait's owner, but the call must then resolve), or be rejected consistently. Suggest the panel file this as a follow-up: an impl through an alias must behave exactly like the impl written on the aliased type, or be an error.
  >
  > **Tradeoffs**
  > - Cost: one more error for users who write the derive "just in case". A deletion fixes it, and the fix is mechanical.
  > - Gain: the table row stays simple ("type" means declaration), and no rule is needed for which aliases the derive might apply to.
  > - Rejected alternative (b), accept and ignore: unsound as documentation, and the case "alias of a local struct" silently suggests the derive worked.
  > - Rejected alternative (c), derive on an alias of a local nominal type forwards to the declaration: it makes a second place where the declaration's impls are set. This breaks locality, and it fails for every foreign or structural target, so the rule would need case splits.
  >
  > **Cross-language**
  > - Haskell: `deriving` is allowed only on `data` and `newtype`, never on `type` synonyms. A `type` synonym with `deriving` is a parse error.
  > - Rust: `#[derive]` on a `type` alias is an error ("`derive` may only be applied to structs, enums and unions").
  > - OCaml: `[@@deriving]` on a type abbreviation derives for the abbreviation's structure, but the result is a function, not an instance, so there is no coherence issue.
  > - Swift and Kotlin do not derive on typealiases.
  > - Blink should follow Haskell and Rust.

- **DevOps/Tooling:**

  > DEVOPS PROPOSAL (Phase A): reject `@derive` on a type alias with E1110 UnexpectedAnnotation. Use an alias-specific note and a machine fix.
  >
  > I did not run gen1 for this. I used your table of measured results.
  >
  > BEHAVIOR
  > - Target `type` in the annotation table means a type declaration: a struct, enum or newtype. A type alias declares no type, so `@derive` on an alias is E1110 for every alias target. That includes tuples, containers, built-ins, local types, foreign types and generic aliases.
  > - No new error code. Rule 2 under the table already covers it. The message text changes only when the target is an alias.
  > - Other `Target: type` annotations on an alias:
  >   - `@deprecated` and `@allow` stay legal. Renaming an alias is a normal migration path, and a lint allowance needs a place to sit.
  >   - `@src`, `@where`, `@invariant`, `@ffi.struct` and `@ffi.opaque` are E1110 on an alias. Each one constrains or describes a declaration, and an alias has none.
  >
  > EXAMPLE
  > ```
  > @derive(Hash, Eq)
  > type K = (Int, Str)
  > ```
  > ```
  > error[E1110]: @derive does not apply to a type alias
  >   --> k.bl:1:1
  >    |
  >  1 | @derive(Hash, Eq)
  >    | ^^^^^^^^^^^^^^^^^ `K` is another name for `(Int, Str)`. It is not a new type.
  >    |
  >    = note: `(Int, Str)` already has Hash and Eq. A tuple gets them from its elements.
  >    = help: remove the attribute
  >    = help: to make a distinct type, write a newtype: `type K { key: (Int, Str) }` and put @derive on it
  > ```
  > - If the alias target is a local struct or enum (`type A = Plain`), the help line becomes "put @derive on `type Plain`". That is the same advice the E0306 help text gives today.
  > - If the target is a container such as `List[Int]`, the note says it "cannot gain a Hash impl". This points the user to the real answer, E1400, before they hit it.
  >
  > MACHINE FIX
  > - `blink fix` and the LSP quick fix "Remove @derive" delete the attribute line.
  > - For an alias of a local type, the LSP offers a second quick fix: "Move @derive to `Plain`". It is offered only if `Plain` has no @derive for those traits yet. If `Plain` has one, the fix merges the missing traits into it.
  > - Neither fix changes program meaning. The derive on the alias grants nothing today, so removal is safe.
  >
  > WHY (DevOps view)
  > - Accept-and-ignore (option b) is the worst diagnostic outcome. Take `@derive(Hash, Eq) type L = List[Int]`. The author sees the attribute, then gets E1400 on `L` with no link back to the attribute. The error text cannot say "your derive did nothing" unless the compiler already knows, and if it knows, it should say so at the attribute.
  > - Accept-and-ignore also hurts the LSP. Hover and "go to impl" on `K` would show a derive that generates nothing. A linter would have to add a rule just to warn about a no-op that the compiler itself accepts.
  > - Rejection keeps the diagnostic at the source site, with a fix. Rust handles `#[derive]` on a `type` item the same way: "derive may only be applied to structs, enums and unions". Go has no derive, and `type X = T` there cannot have methods added, which is the same rule.
  > - Spec cost is small: one sentence saying `type` in the table means a declaration, not an alias.
  >
  > OUT OF SCOPE BUT RELATED
  > - Your row 6 (`impl Shout for K` accepted, then E0505 at the call) is the same family. An impl through an alias of a foreign or structural type should also be an error at the impl site. I would file it separately. It is not this question.
  >
  > REJECTED ALTERNATIVE (c): make `@derive` on an alias derive for the aliased type if the package owns it
  > - This is redundant for owned types, because the derive belongs on the declaration.
  > - It makes one type's impls depend on where the alias sits. That breaks the "identity, not spelling" rule (fact 8).
  > - It would give two places for one derive, and coherence could fail with a duplicate impl.

- **AI/ML:**

  > AI/ML seat, Phase A proposal: reject @derive on a type alias, using the existing E1110.
  >
  > Rule: @derive is legal only on a declaration that defines a type (struct, enum, newtype). A `type X = <type>` alias is not a "type" target for @derive. It is E1110 UnexpectedAnnotation. I tested nothing. This rests on the spec text and your measured table.
  >
  > Behavior:
  >
  > ```blink
  > @derive(Hash, Eq)
  > type P = (Int, Str)
  > ```
  > error[E1110]: @derive does not apply to a type alias. `P` is another name for `(Int, Str)`, so a derive grants nothing.
  > help: remove @derive. Tuples already have Eq, Ord, Hash, Clone and Debug when every element has them.
  > Machine fix: delete the attribute line.
  >
  > ```blink
  > type Plain { x: Int }
  > @derive(Debug)
  > type A = Plain
  > ```
  > error[E1110]: same message, with help "put @derive(Debug) on `type Plain`". The fix is not mechanical here, because the right edit is on another declaration. The help text gives the move.
  >
  > Aliases of List, Map, Set or a type from another package give the same E1110. The help adds nothing about the alias's target beyond "derive goes where the type is defined". That also matches the orphan rule: derive generates impls in the type's defining module (3.6).
  >
  > Other `Target: type` annotations on an alias:
  > - Rejected with E1110: @invariant, @where, @ffi.struct, @ffi.opaque. Each one constrains or lays out a definition, and an alias has none.
  > - Kept legal: @deprecated and @allow. They attach to the name, so they mean something on an alias (deprecate the old spelling, silence a lint at that line). @src is outside my domain, so I leave it to others.
  > - So the annotation table should list targets as "type declaration" vs "type alias" explicitly. Right now the single word "type" is the gap that made this question.
  >
  > Why this is best for AI code generation:
  > 1. One decision point. A model learns "derive goes on the definition with fields or variants". There is no second rule about when a derive on an alias works. Option (b), accept and ignore, teaches the wrong thing. A model sees a derive compile on an alias, copies the pattern, and then gets E0306 on `A` with no link back to the dead derive. Your table shows this: the derive on A is silently ignored, then E0306 points at Plain.
  > 2. Silent no-ops are the worst failure for LLM-written code. They pass the compiler and mislead the reader and the next model trained on that code. This repo is training data (CLAUDE.md says so), so a dead attribute in the corpus does real harm.
  > 3. Token cost: zero extra. The common path (derive on a struct or enum) is unchanged. No new code to learn, since E1110 and its rule 2 already exist. A new code would add one entry to the catalog for no gain.
  > 4. Debuggability: the error appears at the attribute line, the place the model wrote the mistake. It says what the alias is and where to move the derive.
  > 5. Alias identity matches 3.4: one name, one type. "Identity, not spelling" (fact 8) means a derive keyed to a spelling is incoherent. The same reasoning is why the E1400 check already follows the aliased type.
  >
  > Rejected alternative (c): treat @derive on an alias of a local struct as sugar that forwards to the struct. This adds a rule with exceptions (local struct yes, tuple no, foreign type no, generic alias unclear) and lets two spellings hold one derive, which breaks the coherence story. Four more decision points for no new power.
  >
  > Cross-language: Rust rejects `#[derive]` on a type alias (error: "derive may only be applied to structs, enums and unions"). Haskell has `deriving` only on data/newtype declarations, not on `type` synonyms (a synonym has no deriving clause). Swift and Kotlin have no derive-on-alias. All three agree with reject, and a model that knows Rust gets the right answer for free.
  >
  > Generic alias `type Pair[T] = (T, T)` with @derive(Debug): same E1110. The "separate not-yet-built .debug() error" on tuples is out of scope here.
  >
  > Side note, not this ticket: `impl Shout for K` (alias of a tuple) is accepted but the call fails with E0505. A rule that an impl through an alias must be on a type the package owns would fit the same principle. I leave it for another ticket.

- **Minimalism:**

  > MIN (Minimalism) Phase A proposal: reject @derive on a type alias with the existing E1110 UnexpectedAnnotation. No new code, no new rule.
  >
  > BEHAVIOR
  > "Target: type" in the annotation table means a type declaration that introduces a type: struct, enum, newtype. A `type X = <type>` alias introduces no type, so it is not a target. The existing rule 2 then gives the error. The table needs no new row. The writer only has to state what "type" covers.
  >
  > ```
  > @derive(Hash, Eq)
  > type P = (Int, Str)
  > ```
  > error[E1110]: `@derive` does not apply to a type alias. `P` is another name for `(Int, Str)`.
  >   help: delete the attribute. A tuple is already Hash and Eq. To derive on a type you own, put `@derive` on that type's declaration.
  >   machine fix: delete the attribute line.
  >
  > ```
  > type Plain { x: Int }
  > @derive(Debug)
  > type A = Plain
  > ```
  > Same E1110 on `A`. The help names the declaration to edit: "add `@derive(Debug)` to `type Plain`". The E0306 help already says this, so one hint serves both cases.
  >
  > Local struct, built-in, foreign package, generic alias (`type Pair[T] = (T, T)`) and List all get the same error. The rule does not depend on what the alias points to, so there is no case split. A case split would need "is it local? is it a tuple? is it generic?" and each answer is another thing to document and test.
  >
  > WHY NOT THE ALTERNATIVES
  > (b) Accept and ignore. This is the worst option. The author reads `@derive(Hash, Eq)` on `type L = List[Int]` as "L can be a Set element". It is E1400 anyway, and the attribute lied. Your table shows three of the four rows where the derive is silently dead or misleading. Accepted-and-ignored is a lint warning pretending to be a feature. It also trains AI-written code to put derives on aliases "to be safe".
  > (c1) Alias derive forwards to the target: for a local struct this is a second place to write the same derive, which gives two ways to do one thing. For a foreign or built-in target it breaks the orphan rule and coherence (§3.6, facts 4 and 5), and rule 8 (identity, not spelling). I would need a new orphan exception, and that is the exact cost I would not pay.
  > (c2) Alias derive creates a distinct type: this is a newtype. Syntax for that already exists (`type K { value: (Int, Str) }`). Do not give an alias two meanings.
  >
  > OTHER Target:type ANNOTATIONS ON AN ALIAS (kept small)
  > Apply the same test: does the annotation mean something about a name, or only about a type's identity?
  > - @deprecated: means something about a name. A deprecated alias is the standard rename path (`@deprecated type Old = New`). Accept.
  > - @allow: lint scope, not identity. Accept.
  > - @src: I do not know its semantics. Leave as is; the writer should check it by the same test.
  > - @where, @invariant, @ffi.struct, @ffi.opaque: all attach to a type's identity or layout. Alias is E1110. (@invariant on an alias would be a hidden refinement type; that is a different feature and needs its own proposal.)
  > This is an observation that falls out of the one test. I am not proposing to design it now. If the panel wants a smaller change, vote only on @derive.
  >
  > TRADEOFFS (my domain)
  > + Smallest spec: zero new codes, zero new rules, one clarifying sentence. Net surface goes down.
  > + Matches "an alias is the same type": no attribute can do something an alias name cannot.
  > + Errors point at the real fix site, so the fix is mechanical.
  > + Unlocks nothing that is lost: every working program with `@derive` on an alias runs the same with the line deleted (measured in your table: rows 1, 4 are no-ops; rows 2, 3 are already errors for another reason).
  > - Breaks any code that put @derive on an alias. Per settled policy (fact 9) this ships as an error at once with a CHANGELOG line. Not discussed further.
  > - Someone may want `@derive(...)` to "name the intent" on `type K = (Int, Str)`. A comment does that, and the bound is checked at the use site (E1400, E0306) either way.
  >
  > CROSS-LANGUAGE
  > Rust: `#[derive]` on a `type` alias is an error ("derive is not applicable to type aliases"); you derive on the struct. Haskell: `deriving` is only on `data`/`newtype`, not on `type` synonyms. Go: no derive; `type A = B` alias cannot have methods added. Swift/Kotlin: typealias cannot adopt conformances. No major language lets an alias carry a derive.
  >
  > VOTE: YES to reject via E1110; NO to accept-and-ignore; NO to forward/new-type semantics.

#### Phase B — Debate, round 1

The moderator deduped the six proposals into one core option (R: E1110 for every alias target) and two variations: V1, the machine fix (V1a delete for every alias; V1b move for an alias of a local struct or enum, delete otherwise; V1c delete, plus an editor quick fix that moves), and V2, the other annotations (V2a `@src` legal; V2b `@src` E1110). No seat objected to R. All six ended STABLE. Web moved from V1b to V1a and from V2b to V2a. DevOps moved from V2b to V2a.

- **Systems:**

  > SYS Phase B round 1.
  >
  > 1. V1: V1a. `blink fix` deletes the attribute line for every alias.
  > Reason: a fix that edits a second declaration may collide with an existing derive on it, and it may change what another module sees. Deleting is local, and a machine fix should not change a declaration the error did not point at. Moving or merging a derive onto a target declaration (V1b, V1c) changes that type's impls and its Hash and Eq layout cost. The help text names the target declaration, so the user can make that edit. I do not object to the LSP quick fix in V1c as an optional tool feature, but the language rule should say only that `blink fix` deletes.
  >
  > V2: V2a. `@src` stays legal on an alias.
  > Reason: §11.1 describes `@src` as provenance only (a link to a requirement, design doc or issue), and it adds no layout or codegen. An alias can come from a requirement. Rejecting `@src` there removes a traceability link that costs nothing at runtime and gains no safety. The "adds behavior or layout" argument (V2b) holds for `@derive`, `@invariant`, `@where` and `@ffi.*`, but not for `@src`. I would vote on all of V2, since it comes from the same rule: an annotation is legal on an alias if it describes the name, and E1110 if it needs an owned type.
  >
  > 2. Objection to R: none. E1110 for all alias targets is the right rule, and it removes the dead alias-derive codegen path.
  >
  > STABLE, ready to vote.

- **Web/Scripting:**

  > WEB, Phase B round 1.
  >
  > 1. V1: I change my vote from V1b to V1a. The machine fix deletes the line for every alias. A move edits a second declaration and can collide with an existing `@derive` there. A delete is the same edit for all alias targets, so a user (or a model) learns one rule. The help text still says "put `@derive(Debug)` on `type Plain`" for a local target, so the user has the move in plain words. I do not vote V1c: a second LSP quick fix adds merge logic for a rare case. The tooling seat can add it later without a spec change.
  >
  >    V2: I change my vote from V2b to V2a. `@src` is legal on an alias. My Phase A reason ("each one adds behavior or layout") was wrong for `@src`. The spec says `@src` links code to a requirement, RFC or issue. That link is about the declaration site, and an alias is a declaration. A team may want to trace "why does this name exist" (for example a rename kept for compatibility). `@src` adds no behavior, so it cannot do harm on an alias. The ones that stay E1110 are `@derive`, `@where`, `@invariant`, `@ffi.struct`, `@ffi.opaque`: each changes what a type is or does, and an alias is not a new type. `@deprecated`, `@allow` and `@src` stay legal: each is about the name or the site.
  >
  > 2. Objection to R: none.
  >
  > 3. STABLE, ready to vote.

- **PLT:**

  > PLT, Phase B round 1.
  >
  > 1. Positions
  > - V1a (delete the line for every alias). A machine fix must preserve behavior. Deleting the attribute does: today the derive has no effect, so removing it changes nothing. A move edits another declaration, so it adds an impl the program did not have before. That is a semantic change, and it can collide with a derive already on that declaration. Moving is a choice for the author. The help text names the target (`put @derive(Debug) on type Plain`). I accept V1c's extra LSP quick-fix, since an editor action that the user clicks is not a machine fix. I do not accept V1b.
  > - V2a (`@src` legal on an alias). The §11.1 row and §10.4 describe `@src` as a provenance link from code to a requirement, RFC or issue. That is metadata about a declaration site, and an alias declaration is a site. Requirement traceability (`blink trace`) may need to link an alias such as `type UserId = Int` to its requirement. `@src` adds no behavior and no layout, so web's argument ("each one adds behavior or layout") does not cover it. `@src` follows the same name-level test as `@deprecated` and `@allow`. If the panel would rather keep the change small, voting on `@derive` only is acceptable, but then the `@src` row must say explicitly which way it goes, so that a gap does not remain.
  >
  > 2. Objection to R: none. The typing argument is the same for every alias target, so one rule without cases is right.
  >
  > STABLE, ready to vote.

- **DevOps/Tooling:**

  > DEVOPS, Phase B round 1.
  >
  > 1. Positions
  > - V1: I vote V1c.
  >   - `blink fix` deletes the line. This is safe and local, and the derive on the alias does nothing today.
  >   - The "move to the local type" edit is an LSP quick fix only. It changes a second declaration, and that declaration may already have a `@derive`. A quick fix is the right place for it because the user sees the edit before it applies.
  >   - A batch tool such as `blink fix` should not touch a second declaration without that review. This is why I reject V1b.
  >   - If the panel wants less, V1a is acceptable. V1c adds no spec text, since a fix is tooling behavior, not language behavior.
  > - V2: I change my vote to V2a. `@src` is legal on an alias.
  >   - Reason: I called `@src` a thing that "constrains or describes a declaration". The spec says it is a provenance link for tool use (`blink trace`). It adds no behavior or layout. An alias is a declaration with a name. A requirement can map to that name, for example `@src(req: "ID-7") type UserId = Int`.
  >   - If `@src` were E1110 on an alias, `blink trace` would lose a real link and the user would get an error with no fix. The reason web gives (adds behavior or layout) does not apply to metadata.
  >   - That leaves `@where`, `@invariant`, `@ffi.struct` and `@ffi.opaque` as E1110 on an alias. These add behavior or layout.
  >   - If the panel wants a smaller change, I accept voting on `@derive` only. I prefer deciding all of V2 now, so the §11.1 table can list the alias target in one pass.
  >
  > 2. Objection to R: none. Every alias target gets the same rule. I support an explicit alias entry in the §11.1 table, as sys, plt and aiml asked. The table should list which annotations accept an alias. A reader should not need to guess what "type" covers.
  >
  > STABLE, ready to vote.

- **AI/ML:**

  > AI/ML, Phase B round 1.
  >
  > 1. Positions
  > - V1: V1a. `blink fix` deletes the attribute line for every alias.
  >   - I change my Phase A view that the local-struct case is "not mechanical". A move edits a second declaration and grants a trait the author never asked for. It may also collide with an existing derive. A fix that only deletes is predictable: one rule, one result, and a model or script can apply it blind.
  >   - The help text still names the target: "put `@derive(Debug)` on `type Plain`". The user then makes the move as an explicit choice.
  >   - V1c's LSP-only move is fine as a tool extra. It does not change the language rule, so I do not need it in the ballot.
  > - V2: V2a. `@src` stays legal on an alias.
  >   - It is provenance metadata checked by `blink trace`. §11.1 and §10.4 put no condition on the declaration having a body. A requirement link on a named alias (for example `@src(req: "AUTH-001")` on `type UserId = Int`) is plausible.
  >   - Rejecting it would add one more exception to learn, with no safety gain.
  >   - The rule is then short enough for a model to learn: "@deprecated, @allow, @src are name-level and stay legal on an alias. Annotations that add behavior, a check or layout (@derive, @where, @invariant, @ffi.*) are E1110."
  >   - I accept a vote on `@derive` only if the panel wants a smaller change. If the panel votes V2, I vote V2a.
  >
  > 2. Objection to R: none. It is the one rule that adds no decision point and uses an existing code. The E1110 text should say what the alias is: "`K` is another name for `(Int, Str)`". The help text should mention a newtype for a user who wants a distinct type.
  >
  > STABLE, ready to vote

- **Minimalism:**

  > MIN, Phase B round 1.
  >
  > 1. V1: choose V1a. `blink fix` deletes the line, for every alias.
  > - A move edits a second declaration. It can collide with an existing derive, and it can cross a module. That adds merge logic to the fixer and a second behavior to document and test.
  > - The help text already names the declaration to edit. The author makes that edit by hand, once.
  > - V1c (the LSP quick fix that moves the derive) is an editor feature. It does not change the language. I will not block it, but it should not be on the ballot or in the spec.
  > - V1b makes the fixer a two-case function. I vote no on it.
  >
  > V2: choose V2a. `@src` stays legal on an alias, with `@deprecated` and `@allow`.
  > - My test from Phase A is "does the annotation say something about a name, or about a type's identity?"
  > - `@src` is provenance for a declaration site. §11.1 says it is tool-checked by `blink trace`, and a requirement can be linked to an alias declaration like any other declaration. It does not touch identity or layout. So it passes the test.
  > - V2b would need a reason for the extra E1110, and I cannot find one. It would also remove a usable link for no gain.
  > - If the panel wants a smaller ballot, I will accept "vote on @derive only". Then the writer states the test and lists the cases it gives. I have no strong view on V2 beyond the test, and I will not argue for more rows in the table.
  >
  > 2. Objection to R: none. Six of six agree on it. Zero new codes, one rule, no case split on the alias target.
  >
  > Writer note: the explicit `alias` entry in the §11.1 table (sys, plt, aiml) is a clear way to say it, and costs one line. I support it over prose.
  >
  > STABLE, ready to vote.

#### Phase C — Silent vote

Q1 options: **A** E1110 for every alias, `blink fix` deletes the line. **B** E1110 for every alias, `blink fix` moves the line to the declaration for an alias of a local struct or enum, and deletes it otherwise.

Q2 options: **A** `@deprecated`, `@allow` and `@src` legal on an alias; `@where`, `@invariant`, `@ffi.struct` and `@ffi.opaque` E1110. **B** as A, but `@src` also E1110. **C** decide `@derive` only.

| Seat | Q1 | Q2 |
|---|---|---|
| Systems | A | A |
| Web/Scripting | A | A |
| PLT | A | A |
| DevOps/Tooling | A | A |
| AI/ML | A | A |
| Minimalism | A | A |

- **Systems:**

  > SYS Phase C vote.
  >
  > Q1
  > 1. Vote: A.
  > 2. Reasoning: `@derive` emits hash, eq and clone code keyed to a type's declaration identity, and an alias has none. A delete-only fix edits only the line that the error points at, so it cannot change the impls or layout of another declaration. The help text names `type Plain`, so the user makes that edit on purpose.
  > 3. Concern: for an alias of a local type, users may find delete-only less friendly than a move, but a move can collide with an existing derive on the target.
  >
  > Q2
  > 1. Vote: A.
  > 2. Reasoning: `@deprecated`, `@allow` and `@src` describe the name or the declaration site and add no layout, codegen or runtime check. `@src` is provenance only (§11.1, §10.4), so allowing it on an alias costs nothing at runtime and keeps traceability. `@where`, `@invariant` and `@ffi.*` need an owned type with its own layout or check point, so they get E1110.
  > 3. Concern: tools such as `blink trace` must treat an alias `@src` link as pointing at the name, and not as a claim about the aliased type.

- **Web/Scripting:**

  > WEB, Phase C vote.
  >
  > Q1: A
  > Reasoning: One rule for every alias target is easy to teach. The fix is the same edit each time (delete the line), so a user or a model does not need to learn a case split. A move edits a second declaration and can collide with an existing `@derive` there. The help text still gives the move in words.
  > Concern: A user who deletes the line on `type A = Plain` may forget to add the derive to `Plain`, and then gets E0306 at the use site. The E0306 help already says where the derive goes, so the loop closes in one more step.
  >
  > Q2: A
  > Reasoning: `@deprecated`, `@allow` and `@src` describe the name or the declaration site. They add no behavior, so they are safe on an alias, and they are useful (a rename kept for compatibility, a trace link to a requirement). `@where`, `@invariant`, `@ffi.struct` and `@ffi.opaque` change what a type is or does, and an alias is not a new type.
  > Concern: The line between "describes the name" and "changes the type" is a judgment call. The next annotation someone adds to the table needs an explicit alias decision, or it silently falls into E1110 by default.

- **PLT:**

  > PLT, Phase C.
  >
  > **Q1: A**
  > 1. Vote: A.
  > 2. Reasoning: A machine fix must keep program behavior. Deleting the line does, because the derive grants nothing today. The move in B adds an impl to another declaration. It changes the program, and it can collide with a derive already on that declaration. The author decides on a move, and the help text tells them how.
  > 3. Concern: users of A will see a fix that deletes the intent as well as the error, so they may delete the line and not read the help text that says to put the derive on `type Plain`.
  >
  > **Q2: A**
  > 1. Vote: A.
  > 2. Reasoning: `@src` is provenance metadata on a declaration site (§10.4, §11.1). It adds no behavior and no layout, so it passes the same name-level test as `@deprecated` and `@allow`. `@where`, `@invariant`, `@ffi.struct` and `@ffi.opaque` describe the type itself, which an alias does not own, so they are E1110. Option C leaves the `@src` row open, and the same gap would return as a later ticket.
  > 3. Concern: if `@src` is legal on an alias, `blink trace` must report a link to an alias as a link to that name, not to the aliased type, or traces will attach to the wrong declaration.

- **DevOps/Tooling:**

  > DEVOPS, Phase C vote.
  >
  > Q1: A
  > Reasoning: The compiler reports E1110 at the attribute site, and `blink fix` deletes the line. Deleting is safe because the derive on the alias does nothing today. `blink fix` should not edit a second declaration, which B would make it do. The help text still names `type Plain`, so the user gets the move advice without an unreviewed edit.
  > Concern: With A, a user with an alias of a local type applies the delete fix, then gets E0306 later if they skip the help text. The help line must name the move clearly.
  >
  > Q2: A
  > Reasoning: `@src` is provenance metadata for `blink trace`. It adds no behavior or layout, and an alias is a named declaration that a requirement can map to. `@where`, `@invariant`, `@ffi.struct` and `@ffi.opaque` add behavior or layout, so they stay E1110 on an alias.
  > Concern: A later metadata annotation may have unclear alias status. The §11.1 table needs an explicit alias entry for each row, so the answer is stated and not guessed.

- **AI/ML:**

  > AI/ML Phase C votes.
  >
  > Q1: A
  > Reasoning: The machine fix has one result, so a model or script can apply it without checking anything. A move edits a second declaration and grants a trait the author did not ask for. It could also collide with an existing derive. The help text still names the target declaration, so the model learns where the derive belongs.
  > Concern: A user who deletes the line on an alias of a local struct may never add the derive to the struct, and then hit E0306 later. The E1110 help text is the only guide, so it must name the struct.
  >
  > Q2: A
  > Reasoning: `@deprecated`, `@allow` and `@src` are name-level metadata, and §11.1 puts no condition on the declaration having a body. `@where`, `@invariant` and `@ffi.*` add checks or layout, which an alias lacks. The split is a short rule a model can learn: annotations that describe the name stay legal, annotations that add behavior are E1110.
  > Concern: `@src` on an alias may be rare in practice, so the exception could go untested. The corpus needs a test row for it.

- **Minimalism:**

  > MIN, Phase C vote.
  >
  > Q1
  > 1. Vote: A.
  > 2. Reasoning: E1110 for every alias, and the fixer deletes the line. This is one rule with one fix, so it has no case split on the alias target. A move edits a second declaration, may cross a module, and may collide with an existing derive. That adds merge logic to the fixer and a second behavior to document and test. The help text already names the declaration, so the author makes that edit by hand.
  > 3. Concern: an author who deletes the line for an alias of a local struct may never add the derive to the struct, and then hits E0306 at the next use. That error already says "add `@derive(Debug)` to `type Plain`", so the cost is one extra compile.
  >
  > Q2
  > 1. Vote: A.
  > 2. Reasoning: the test is whether an annotation says something about a name or about a type's identity. `@deprecated`, `@allow` and `@src` are about the declaration site, so they pass. `@where`, `@invariant`, `@ffi.struct` and `@ffi.opaque` need a type's identity or layout, so they fail. `@src` is provenance that `blink trace` checks, and a link to an alias declaration is as valid as a link to any other. One test gives the whole list, with no exceptions to remember.
  > 3. Concern: the §11.1 table gets an "alias" entry per row, and that list will drift if a later annotation is added without a row for aliases.

## Result

Q1 is A (6-0) and Q2 is A (6-0). The spec text is §11.1 *Annotations on a Type Alias*, with the Target column of the `@src`, `@allow` and `@deprecated` rows, the *Provenance on Types* note in §11.3, a cross-reference in §3.4 and §3.6, and the E1110 row of the error catalog.
