[< All Decisions](../DECISIONS.md)

# One Empty Form per Collection Type — Design Rationale

### Panel Deliberation

The ticket (verbatim):

> Spec: multiple constructors for the same type.
> Problem: more than one way to make an empty collection.
> Evidence: Map() / Map.new[K,V]() / Map[K,V](); Bytes() / Bytes.new().
> Principle: Principle 2 (one way to do it).
> Proposal (for panel): keep one constructor form per type; remove the others.

Moderator triage found that `Map`, `Set` and `Bytes` each had two or three working empty forms, and `List` had two (`[]` and `List.new()`). The spec named no rule for which form is the one. Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in four phases. Phase D was not triggered. Quoted text is each panelist's own words. Each quote is a whole paragraph or list item of the panel record, or a line range of one; "…" marks a cut.

Questions:

- Q1: the forms. `[]` is the empty `List`; `Map.new()`, `Set.new()`, `Bytes.new()`, `StringBuilder.new()` are the others. Removed: `Map()`, `Map[K, V]()`, `Set()`, `Set[T]()`, `Bytes()`, `List.new()`, `List.new[T]()`. Type arguments come from the annotation, the expected type, a later use, or a bracket list after the callee under §3.4 *Explicit Type Application*.
- Q2: W1122 `EmptyConstructorForm` for one minor release with machine fixes; then W1122 retires and each form is E0504 or E0505, with fix text read from §3.2 rows that exist from the first release.
- Q3: `List()`, `List[T]()`, `StringBuilder()`. **R:** §3.2 rows. **H:** no rows; one E0504 help rule for a callee that names a type.
- Q4: those three stay errors, with no warning release.
- Q5: a generic constructor declares the type's parameters, in the type's order, as its own binders. **S:** binds stdlib constructors. **G:** binds every constructor. **N:** no rule.
- Q6: §2.12.3: a type-scoped function on a generic type declares its own binders after the name (`fn Stack.empty[T]()`); the type head takes no list.
- Q7: `Map[K, V].new()` is E0314 `TypeArgsWithoutCall` with a machine fix to `Map.new[K, V]()`.
- Q8: the `List.new[T]()` fix is machine-applicable only as the whole initializer of an unannotated plain-name `let`; otherwise a suggestion; a disagreeing annotation gives no fix.

#### Phase A — Independent proposals

All six proposed `[]` for `List` and `Type.new()` for `Map`, `Set`, `Bytes` and `StringBuilder`, and the removal of `List.new()`. They differed on the diagnostic, on whether a constructor takes a type-argument list, and on whether `List()`, `List[T]()` and `StringBuilder()` get rows. Four seats also named a fallback that kept `List.new()` beside `[]`.

- **Systems:**

> `List.with_capacity(n)` and `StringBuilder.with_capacity(n)` stay. They are a different operation (they take an
> argument and change `capacity()`), not a second spelling of "empty".

- **Web/Scripting:**

> A list literal makes a list. Every other value of a built-in type comes from a static method on the type name:
> `Type.new()` when empty, `Type.with_capacity(n)` or another named method when not.

- **PLT:**

> The binder list of a generic one is the type's parameter list, in the same order. So `Map.new[A, B]()` has type
> `Map[A, B]`, and the brackets mean the same thing on the function as they do on the type. This is a requirement on
> every stdlib constructor of a generic type, including `List.with_capacity[T](n: Int) -> List[T]`.

- **DevOps/Tooling:**

> An empty `List` is `[]`. An empty `Map`, `Set`, `Bytes` or `StringBuilder` is `Type.new()`. A constructor takes no
> type-argument list: its type comes from the binding's annotation, the expected type, or a later use.

- **AI/ML:**

> The empty value of a type that has a literal is the empty literal (`[]` for `List`, `""` for `Str`). Every other type
> makes an empty value with `Type.new()`. A type argument that context does not fix goes in brackets after the callee
> (§3.4 *Explicit Type Application*), or in an annotation on the binding.

- **Minimalism:**

> | Type | The one empty form | Removed forms |
> |---|---|---|
> | `List[T]` | `[]` | `List.new()`, `List.new[T]()` |
> | `Map[K, V]` | `Map.new()` | `Map()`, `Map[K, V]()` |
> | `Set[T]` | `Set.new()` | `Set()`, `Set[T]()` |
> | `Bytes` | `Bytes.new()` | `Bytes()` |
> | `StringBuilder` | `StringBuilder.new()` | (none; `StringBuilder()` is already an error) |
>
> `List.with_capacity(n)` and `StringBuilder.with_capacity(n)` stay. They are a different operation (03_types.md:665), not
> a second spelling of "empty".

#### Phase B — Debate highlights

One round. All six seats ended it ready to vote.

- **Four seats withdrew the fallback that kept `List.new()`:**

> It reads sys-1 correctly. I withdraw sys-2 (keep `List.new()` beside `[]`). All six first proposals remove
> `List.new()`, and no seat argued for sys-2 as a first choice. I will not vote for it.

> - **web-2 withdrawn.** All six first proposals remove `List.new()`. I no longer see a reason to put "keep `List.new()`"
>   on the ballot as my option. If another seat keeps its fallback alive, I vote against it.
> - **web-1 takes in plt-1 rule 1 and rule 5, and aiml-1's extra rows.** Reasons are under V2, V5 and V3 below.

> Remove it (sys-1, web-1, devops-1, aiml-1, min-1, plt-1). I withdraw plt-1-L; I only listed it to oppose it, and no seat
> ranks a keep-both option first.

> **min-2 is withdrawn.** All six first proposals remove `List.new()`. No seat ranks keeping it first, and sys, web and plt
> each say they would vote against their own fallback. A fallback nobody wants is a ballot option that only costs time.

- **DevOps withdrew "no type-argument list on a constructor", and said why:**

> The table reads my proposal correctly. One change since: I **withdraw devops-1's "no type-argument list on a constructor"**
> and amend (below). So the V2 row for devops now reads "yes".

> With that declaration, the brackets on `Map.new` supply `new`'s **own** binders, and §3.4 covers them with no special case.
> §2.12.3 (02_syntax.md:1193) already says a type-scoped function is "an ordinary function that has no receiver", and
> 03c_protocols.md *No Inherent Methods* rules out the Rust `impl<K, V>` model, so the binders cannot belong to anything
> but the function. gen1's arity message (`` `Map` expects 2 type argument(s) ``) then becomes a message about `Map.new`, which
> is what it should say. min's point also holds: explicit type application is a general feature (`json.decode[T]`,
> `channel.new[Int]`), and taking it away from five functions is a special case, which is what I was trying to avoid.

- **PLT's argument that an annotated `let` is always a repair site for `[]`:**

> sys asked for a proof: "Every place an empty list can be under-determined has a place for the repair ... I believe this
> list is closed ... but I have not proved it." Here is the argument. `[]` is a pure value expression. For any
> expression context `E[[]]` inside a statement `s`, the rewrite to `let x: List[T] = []` placed directly before `s`, with
> `E[x]`, is well typed whenever some `T` makes `E[[]]` well typed, and it gives the same result. Two cases need care:
> - `[]` in a `while` condition, a `||`/`&&` right operand, or a match guard runs zero or many times per run of `s`. After
>   the rewrite it runs once. No program can tell: the value is fresh, pure, and not bound anywhere else, so no alias can
>   observe that two runs shared one list. The one exception would be a mutating call on the unbound value
>   (`[].push(1)`), and §3.2.2 already rejects that (E0610, no mutable root).
> - A module-level `let` initializer: the annotation goes on that `let`, which exists already.

- **The diagnostic: one warning code, then the existing error codes from §3.2 rows.** Minimalism merged the two positions; AI/ML joined it:

> These two fit together, and the merge is the smallest end state:
>
> 1. During the warning release: one code, W1122, for the whole family. A warning needs some code, and one code for one
>    rule is the W1120/W1121 model.
> 2. At the error release: W1122 retires. Each removed form becomes a §3.2 row under the code it would get anyway: E0504 for
>    `Map()`, `Set()`, `Bytes()`, `Map[K, V]()`, `Set[T]()`, `List()`, `List[T]()`, `StringBuilder()`; E0505 for
>    `List.new` (a missing static function on a type). The rows keep the fix.

> Amended position, merging with devops and plt: one warning code (`W1122 EmptyConstructorForm`, devops's name) for one minor
> release with the machine fixes, then the forms become errors that come from the §3.2 removed tables: E0504 for `Map()`,
> `Set()`, `Bytes()`, `Map[K, V]()`, `Set[T]()`, and E0505 for `List.new` (a method row, per DECISIONS.md:471 Q5). The
> tables hold the fix for good, as plt wants, and the warning phase protects code that followed llms-full.md:1317, as
> devops wants. So plt's end state and the majority's schedule do not conflict.

- **DevOps and AI/ML on rows for `List()`, `List[T]()` and `StringBuilder()`:**

> **Against aiml's §3.2 rows for `List()`, `List[T]()`, `StringBuilder()`:** these were never accepted, so a row breaks
> the table's rule ("only names that a released version ... accepted", 03_types.md:194). We do not need rows. gen1 already
> has a general help for a type name used as a callee:
>
> ```
> error[UndefinedFunction]: undefined function `Point`
>   help: `Point` has no constructor call; build a value with a struct literal, as in `Point { x: ... }`
> ```
>
> (probe dv/f1.bl). I propose that rule, which min also states ("a built-in type name is not a callee"), in place of rows:
> when a callee resolves to a type name and no function of that name is in scope, E0504's first `help:` names the type's one
> empty form: `[]` for `List`, `T.new()` when `T.new` exists, and the struct literal otherwise. This covers `List()`,
> `StringBuilder()` and every user type with one rule, and it is what aiml wants the model to see.

> The `List()`, `List[T]()` and `StringBuilder()` rows stay in my proposal. They are E0504 today with no fix, and they are
> exactly what a model writes by analogy from 1,700 `Map()` sites in its training data. web asks for the same help text.

#### Phase C — Silent vote

Before the vote the moderator re-ran DevOps's probe of an unread `let m = Map()` and an unread `let b = Bytes.new[Int]()`. Both give an error under the compiler, so the Phase A claim that they get no E0301 or E0303 did not reproduce. DevOps withdrew it in the ballot. No ticket was filed for it.

| Question | Result |
|---|---|
| Q1 forms | **yes 6-0** |
| Q2 W1122, then E0504/E0505 from §3.2 rows | **yes 6-0** |
| Q3 `List()`, `List[T]()`, `StringBuilder()` | **H 6-0** (sys and aiml moved from R to H) |
| Q4 those three stay errors | **yes 6-0** |
| Q5 binder order | **S 6-0** |
| Q6 binders after the name in §2.12.3 | **yes 6-0** |
| Q7 `Map[K, V].new()` is E0314 | **yes 6-0** |
| Q8 `List.new[T]()` fix class | **yes 6-0** |

Each seat's vote, reasoning and concern:

- **Systems:**

  - Q1 the forms — **yes**

    > **Reasoning:** Every removed form emits byte-identical C to the form that stays (`blink_map_new(&blink_kops_str)`,
    > `blink_bytes_new()`, `blink_list_new_atomic()`), so we remove surface at zero runtime cost. `Type.new()` reads as what
    > runs: a named function that allocates. `Type(x)` keeps its one meaning, wrapping a payload in a newtype or variant
    > (`Code(5)`, `Ok[Int, Str](3)`). The empty list stays the literal `[]`, which is the zero-element case of `[a, b]`.
    >
    > **Concern:** The migration touches about 2,200 sites. A `blink fix` pass that is not run through the 3-step bootstrap
    > order (warn, migrate src, then error) can leave gen0 unable to compile src.

  - Q2 schedule and codes — **yes**

    > **Reasoning:** A grace release is necessary because llms-full.md:1317 tells users to write `Map()`. After that release,
    > the removed forms are plain undefined names, so E0504/E0505 is the honest code and no permanent code is added. When the
    > §3.2 rows exist from the first release and W1122 reads its fix from them, the warning and the later error cannot
    > disagree.
    >
    > **Concern:** If W1122 and the rows are implemented as two separate tables, their fix text will drift. The implementation
    > must have one source.

  - Q3 `List()`, `List[T]()`, `StringBuilder()` — **H**

    > **Reasoning:** devops is right about the table rule. 03_types.md:194 says "The table holds only names that a released
    > version of Blink or its standard library accepted", and these three were never accepted. The help rule ("a type name in
    > callee position: name the type's one empty form, or its struct literal") covers these three, every user type and any
    > future built-in, all with one rule. One rule also needs less checker code than a list of rows. I withdraw my B1 support
    > for rows here.
    >
    > **Concern:** "`T.new()` when `T.new` exists" must name an existing zero-argument `new`. If a user's `new` takes
    > arguments, a help that names `T.new()` would be wrong.

  - Q4 no warning release for those three — **yes**

    > **Reasoning:** No released compiler accepted them, so no program depends on them. A warning release would make the
    > compiler accept new programs for one release only, then break them.
    >
    > **Concern:** None from my seat. The only cost is that the help text must be ready in the same release.

  - Q5 binder order of generic constructors — **S**

    > **Reasoning:** The systems reason for rule 1 is the stdlib key-ops table: `Map.new[K, V]` must use the same
    > monomorphization key as `Map[K, V]`, or the map picks the wrong hash and equality for its keys. That reason applies only
    > to stdlib constructors, and S binds them. G needs a definition of "constructor" for user code (does a function that
    > returns `Self[...]` count? does `with_capacity`?), plus a check that only a style guide needs. A user type with a
    > swapped binder order is a poor API, but it is still sound.
    >
    > **Concern:** Without G, the machine fix for `Registry[A, B].new()` (Q7's shape on a user type) cannot be exact when the
    > user's binder order differs. The fix must be suggestion-only for user types.

  - Q6 binders after the name in §2.12.3 — **yes**

    > **Reasoning:** Rule 1 needs a declaration form to point at, and binders after the name are the existing §3.4 callee
    > discipline. A type head without a list keeps one place for the brackets at each call and each declaration.
    >
    > **Concern:** gen1 does not parse `fn Stack.empty[T]()` today (plt's probe). The spec will be ahead of the compiler until
    > a feature chore lands.

  - Q7 `Map[K, V].new()` is E0314 — **yes**

    > **Reasoning:** A Rust developer will try this form first. One existing code with an exact fix (exact because of rule 1)
    > is better than today's `UnexpectedToken`. The parser change is local recovery and does not affect what codegen sees.
    >
    > **Concern:** For user types, the fix is exact only when the binder order matches the type's (see Q5), so it must be
    > suggestion-only there.

  - Q8 fix class for `List.new[T]()` — **yes**

    > **Reasoning:** The fix is machine-applicable only where the edit stays inside the `let` and cannot change a type. Every
    > other position needs a choice of where the type goes. That matches DECISIONS.md:471 Q1-R. When the annotation and `[T]`
    > disagree, there is already a type error, and a fix would hide it.
    >
    > **Concern:** About 20 such sites in the repo need a human edit, so the src migration step cannot be fully automatic.

- **Web/Scripting:**

  - Q1 the forms — **yes**

    > **Reasoning:** One rule a JS or Python dev learns in one read: a list literal makes a list, and every other built-in
    > value comes from `Type.name()`, as `StringBuilder.new()`, `Duration.ms(100)` and `with_capacity` already do. Type arguments
    > go on the call, as in TS `new Map<string, number>()` and Kotlin `mutableMapOf<String, Int>()`, so `show(Map.new[Str, Int]())`
    > works with no extra `let`.
    >
    > **Concern:** `Map()` has about 1,700 uses in the repo and llms-full.md teaches it, so if the docs, the help text and the
    > test corpus do not all move in the same slice, users will keep copying the old form.

  - Q2 schedule and codes — **yes**

    > **Reasoning:** User code that followed llms-full.md:1317 has `Map()` everywhere, so a warning release with a
    > machine fix lets them change with one `blink fix` instead of a broken build. After that, the §3.2 rows are the one
    > permanent place the fix lives, with no second "this name is gone" code.
    >
    > **Concern:** If the W1122 message gives only the edit and not the rule, a user learns five separate fixes in place of one
    > rule.

  - Q3 `List()`, `List[T]()`, `StringBuilder()` — **H**

    > **Reasoning:** The fix I care about is that a Python dev who types `list()`, `List()` or `StringBuilder()` gets the right
    > form in the first `help:` line. H gives that, and it also covers the same guess on a user type (`Registry()` → the struct
    > literal or `Registry.new()`), which rows never can. It also keeps the §3.2 table's rule (03_types.md:194: only names a
    > released Blink accepted) true.
    >
    > **Concern:** If the help rule is not written as normative §3.2 text with an example, the implementation could ship the
    > bare UndefinedFunction message and the Python guess still gets no answer.

  - Q4 no warning release for those three — **yes**

    > **Reasoning:** No released program uses them, so a warning release protects no one and would accept code that never
    > compiled for one release. Under Q3 the error already names the right form.
    >
    > **Concern:** None from my seat, as long as the Q3 help ships in the same release.

  - Q5 binder order of generic constructors — **S**

    > **Reasoning:** The stdlib must follow the rule so that `Map.new[Str, Int]()` and `Map[Str, Int]` mean the same thing and
    > the E0314 fix is exact. For user code, "which function is a constructor" has no clear test, and a user who writes
    > `fn Pair.new[B, A]()` for a reason of their own should not hit a hard error over a style point. A convention in the
    > docs (and later a lint if users hit it) is enough.
    >
    > **Concern:** If G wins, the spec must define "constructor" exactly, or users will hit an error whose scope they cannot
    > predict.

  - Q6 binders after the name in §2.12.3 — **yes**

    > **Reasoning:** `fn Stack.empty[T]()` puts the binders where every other Blink generic function puts them, so it is one
    > place to learn. A user who writes their own generic container needs this to be legal and stated.
    >
    > **Concern:** gen1 does not parse it yet, so the spec gets ahead of the compiler, and users who copy the example will get a
    > parse error until the implementation lands.

  - Q7 `Map[K, V].new()` is E0314 — **yes**

    > **Reasoning:** `Map[Str, Int].new()` is the first thing a Rust dev, or anyone who reads `Map[Str, Int]` as "the type",
    > will try. Today it is a bare `UnexpectedToken`. A named error with a one-step fix is the answer from my seat.
    >
    > **Concern:** The parser must recover well enough to report E0314 and not a cascade of `UnexpectedToken` errors.

  - Q8 fix class for `List.new[T]()` — **yes**

    > **Reasoning:** The `let` rewrite is local and exact, so `blink fix` can apply it. Every other position changes more than
    > the expression (a call's type arguments or a new binding), so a person must look at it, per DECISIONS.md:471 Q1-R.
    > There are about 20 such sites.
    >
    > **Concern:** The suggestion text must show the full rewritten line, not "add an annotation somewhere", or users will not
    > know what to type.

- **PLT:**

  - Q1 the forms — **yes**

    > **Reasoning:** Every empty value becomes an ordinary term. `[]` is a literal with principal type `List[?T]`, and each
    > `T.new` is a function with a declared type, so inference, E0301, E0303 and E0306 apply with no special case. The
    > removed forms are the ones that put a type name in a term position with no rule behind it. Brackets come from §3.4,
    > so no constructor-specific typing rule exists.
    >
    > **Concern:** Until rule 1 (Q5) and rule 3 (Q6) are in the spec text, `Map.new[Str, Int]()` stays justified only by
    > gen1's hidden rule, which counts the brackets against `Map`'s binders.

  - Q2 schedule and codes — **yes**

    > **Reasoning:** After the error release, the semantics are simple: `Map` in callee position is a type, not a function,
    > so E0504 is the true diagnostic, and the row only supplies the fix. W1122 is a transition device, not a permanent
    > rule. That matches the W1120/W1121 precedent. Rows that exist from the first release give one source for the fix text.
    >
    > **Concern:** If W1122 and the rows are written as two sources, the warning-phase fix and the error-phase fix can drift.

  - Q3 `List()`, `List[T]()`, `StringBuilder()` — **H**

    > **Reasoning:** 03_types.md:194 says the table holds only names that a released Blink accepted. Rows for names that
    > never compiled would break that invariant, and the table would then mean two things. The H rule is the general
    > statement I argued for in B1 ("no type name is a callee"). It covers user types too (`Point()` → the struct
    > literal), so one rule replaces three special rows. That composes better.
    >
    > **Concern:** The H rule must define "the type's one empty form" exactly, and say what happens for a generic user type
    > that has neither a `T.new` nor a struct body that can be written (an opaque type from another module): there the help
    > must name no form at all, not a struct literal the user cannot write.

  - Q4 no warning release for those three — **yes**

    > **Reasoning:** A warning release would make programs well typed for one release that no released Blink ever accepted.
    > That is a retroactive extension of the language just to retract it. A deprecation path exists only to protect code
    > that once compiled.
    >
    > **Concern:** An implementation that routes W1122 through one shared "type-name callee" check may downgrade these three
    > by accident, so the gate needs a test that they stay errors.

  - Q5 binder order of generic constructors — **S**

    > **Reasoning:** My reason for the rule was that the machine fix `Map[K, V]()` → `Map.new[K, V]()` is sound only if the
    > binder lists coincide. That concerns stdlib constructors only. For user code, "constructor" has no definition in the
    > language, and a checker for G would have to invent one ("returns `Self[..]`?"). That rule would be syntactic, not
    > semantic. S binds what a fix depends on and leaves user functions ordinary, which is what §2.12.3 says they are.
    >
    > **Concern:** A future stdlib constructor with a phantom or extra binder (for example an allocator parameter) will meet
    > S, and S must then say whether extra binders come after the type's binders.

  - Q6 binders after the name in §2.12.3 — **yes**

    > **Reasoning:** Q5 needs a declaration form to point at, and §2.12.3 today allows type-scoped functions but is silent on
    > generic types. Binders after the name keep a type-scoped function "an ordinary function" with one binder list. A list
    > on the type head as well would give two positions for one set of binders.
    >
    > **Concern:** gen1 does not parse `fn Stack.empty[T]()` yet, so the spec leads the compiler. A chore must track it, or
    > the rule stays text only.

  - Q7 `Map[K, V].new()` is E0314 — **yes**

    > **Reasoning:** 03_types.md:2405 already requires that a term-position list be followed by a call or a struct body.
    > `Map[K, V].new()` breaks that requirement, so E0314 follows from the spec. gen1's two different codes for one mistake
    > are the defect. The machine fix is exact only because of Q5.
    >
    > **Concern:** The parser must read `Map[Str, Int]` before `.` as a bracket head and not fail with `UnexpectedToken` on
    > the comma, or E0314 is never reached.

  - Q8 fix class for `List.new[T]()` — **yes**

    > **Reasoning:** A repair always exists: in B1 I showed that an annotated `let` placed just before the statement is
    > well typed and keeps the meaning. But it means choosing a statement, which changes more than the call, so outside
    > the unannotated-`let` case it must stay a suggestion (Q1-R). If the annotation disagrees with `[T]`, the program is
    > ill typed already, and no fix should hide which side was intended.
    >
    > **Concern:** The unannotated-`let` fix is wrong when the `let` destructures a pattern (`let (a, b) = (List.new[Int](), 1)`).
    > It must apply only when the initializer is exactly the call and the pattern is a plain name.

- **DevOps/Tooling:**

  - Q1 the forms — **yes**

    > **Reasoning:** One empty form per type gives one completion entry, one fix target and one line in `blink llms`. The bracket
    > list goes after the callee under the general §3.4 rule, so the LSP and E0303 treat `Map.new` the same as any generic function.
    > No checker special case remains for a type name used as a callee.
    >
    > **Concern:** The migration of about 2,200 sites in src, lib and tests could land part-way, and the repo would then teach both
    > forms for a release; the src/lib/tests migration must ship in the same slice as the warning.

  - Q2 schedule and codes — **yes**

    > **Reasoning:** A warning needs its own code so `blink fix` and CI can select the whole migration by one name. The end state is
    > "no such function", which already has a code, and the §3.2 rows keep the fix text after W1122 retires. Having W1122 read the
    > same rows means one source of fix text for both phases.
    >
    > **Concern:** A user who wrote `@allow(EmptyConstructorForm)`, or a CI filter on W1122, will meet E0504/E0505 at the error release
    > with no link back; the W1122 catalog entry should name the codes that replace it.

  - Q3 `List()`, `List[T]()`, `StringBuilder()` — **H**

    > **Reasoning:** 03_types.md:194 says the table "holds only names that a released version of Blink or its standard library
    > accepted"; `List()`, `List[T]()` and `StringBuilder()` never compiled, so a row breaks that rule. One help rule covers these
    > three, every future built-in and every user type (gen1 already gives `Point()` a struct-literal help), and does not need a
    > row each time a type is added.
    >
    > **Concern:** If R wins, the table's rule at :194 must change in the same edit, or the spec says two things.

  - Q4 no warning release for those three — **yes**

    > **Reasoning:** A warning release for a form that never compiled would make code accepted that was refused the day before.
    > They are errors now, and the only change is a better `help:` line.
    >
    > **Concern:** None from my seat.

  - Q5 binder order of generic constructors — **S**

    > **Reasoning:** A rule must be checkable. "Constructor" has no definition a checker can test for user code (`with_capacity`,
    > `from_list`, `parse`?), so G would be a normative rule with no diagnostic. For std it is checkable by the X12-style CI gate on
    > the std public surface, and the `Map[K, V]()` → `Map.new[K, V]()` fix needs it only for std.
    >
    > **Concern:** If G wins, the spec needs a diagnostic code and a definition of "constructor", or the rule is text no tool enforces.

  - Q6 binders after the name in §2.12.3 — **yes**

    > **Reasoning:** One place for binders on a type-scoped function makes go-to-definition and signature help show one shape.
    > gen1 does not parse `fn Stack.empty[T]()` yet, so this is a compiler chore that must follow the spec text.
    >
    > **Concern:** The parser error for `fn Stack[T].empty()` must carry a machine fix to `fn Stack.empty[T]()`, not a bare
    > UnexpectedToken.

  - Q7 `Map[K, V].new()` is E0314 — **yes**

    > **Reasoning:** It is the form a Rust user writes first, so it must get a fix, not a parse error. gen1 already gives E0314 for
    > `List[Int].new()`.
    >
    > **Concern:** gen1 fails `Map[Str, Int].new()` at the parser (`expected ], got ,`), so the parser must accept a comma list there
    > before E0314 and its fix can fire.

  - Q8 fix class for `List.new[T]()` — **yes**

    > **Reasoning:** A machine fix must change only the call, or it must leave the binding as it was written (DECISIONS.md:471 Q1-R).
    > Writing the annotation onto an unannotated `let` is the one place where the fix is exact. When the annotation and `[T]`
    > disagree, the program already has a type error, and a fix that picks one side would hide it.
    >
    > **Concern:** `blink fix` must apply the `let` rewrite as one edit (the annotation and the `[]` together), or two separate edits
    > will conflict under 06_tooling.md:307.

- **AI/ML:**

  - Q1 the forms — **yes**

    > **Reasoning:** "A literal if the type has one, else `Type.new()`" is the only rule that still compiles when a model extends it
    > to the next type: user types, `channel.new` and `with_capacity` included. Explicit type arguments go after the callee, as on
    > every other generic call, so there is no constructor-only bracket rule to memorize. Every removed form compiled before, and
    > nothing flagged it, so models learned it silently. This change ends that.
    >
    > **Concern:** For several releases, models trained on the old repo and docs will keep writing `Map()`. The change helps only
    > if llms-full.md and the test corpus are migrated in the same slice, not later.

  - Q2 schedule and codes — **yes**

    > **Reasoning:** One warning code for one rule teaches the rule once, and the machine fix makes each old site a one-step repair
    > for a model or `blink fix`. After the error release, the §3.2 rows keep the fix for good, so a model that writes `Map()` from
    > old training data still gets the exact replacement and does not guess again.
    >
    > **Concern:** W1122's fix text and the §3.2 rows can drift if they are written twice. Reading the fix from the rows (sys) must
    > be the implementation, not only the intent.

  - Q3 `List()`, `List[T]()`, `StringBuilder()` — **H**

    > **Reasoning:** I proposed rows, and I change my vote. 03_types.md:194 says the table "holds only names that a released version
    > of Blink or its standard library accepted", and these three names never compiled. The help rule in H gives the same fix for
    > these three names. It also covers every type a model might call by analogy, including a user's `Point()` (→ struct literal)
    > and any future type with a `new`. A rule that generalizes is better training signal than three hard-coded rows.
    >
    > **Concern:** The help rule must name the one form exactly (`[]`, not `List.new()`, for `List`). If it is ever wrong, it
    > teaches the removed form at the moment of the error.

  - Q4 no warning release for those three — **yes**

    > **Reasoning:** No released Blink accepted them, so no code needs a soft landing. A warning release would make a form that
    > never compiled compile for one release, and that code then goes into the training data.
    >
    > **Concern:** None from my seat. The E0504 help (Q3) carries the whole repair.

  - Q5 binder order of generic constructors — **S**

    > **Reasoning:** The stdlib is what models read and copy, so binding the rule there makes `Map.new[Str, Int]()` always mean
    > `Map[Str, Int]`. G needs a normative definition of "constructor" for user functions. That is a new, fuzzy decision point
    > (does `fn Registry.from_list[T](...)` count?). It costs more in spec text than it gains.
    >
    > **Concern:** On a user type whose function declares binders in another order, a machine fix that moves type arguments (Q7)
    > would be silently wrong. The fix must check binder order, or be suggestion-only there.

  - Q6 binders after the name in §2.12.3 — **yes**

    > **Reasoning:** The spec must state the one place where a type-scoped function's binders go, or models will guess
    > `fn Stack[T].empty()` from Rust's `impl<T> Stack<T>`. One position, after the name, is the same position as on every call
    > site, so declaration and call match.
    >
    > **Concern:** The rule lands in §2.12.3 while gen1 does not yet parse `fn Stack.empty[T]()` (plt's probe). Until the compiler
    > catches up, the spec teaches code that fails.

  - Q7 `Map[K, V].new()` is E0314 — **yes**

    > **Reasoning:** `HashMap::<K, V>::new()` is a strong Rust prior, so models will write `Map[K, V].new()`. Today it is an
    > `UnexpectedToken` parse error with no fix. E0314 with a machine fix turns that into a one-step repair.
    >
    > **Concern:** See Q5. The fix is exact for stdlib types, but on a user type it is exact only when the binder order matches.

  - Q8 fix class for `List.new[T]()` — **yes**

    > **Reasoning:** The rewrite to `let xs: List[T] = []` is local and exact. Anywhere else, the fix must add a binding or move the
    > type into another call, which changes more than the expression (DECISIONS.md:471 Q1-R). An annotation that disagrees keeps
    > the real type error, and no fix hides it.
    >
    > **Concern:** Suggestion-only sites stay as warnings until a person or model edits them. That is a small set (about 20 in the
    > repo), but it must be cleared before the error release.

- **Minimalism:**

  - Q1 the forms — **yes**

    > **Reasoning:** This only removes things: five forms go, and nothing is added. 03_types.md:148 and :623 already state the
    > rule. `[]` is the list literal with no elements, not a second construct, and `Str`'s `""` already follows the same
    > pattern. Type arguments use the general §3.4 rule, so constructors get no rule of their own.
    >
    > **Concern:** About 2,200 rewrites in the repo. If the migration stops halfway, the corpus teaches both forms longer than
    > it does today.

  - Q2 schedule and codes — **yes**

    > **Reasoning:** A warning needs a code for the one release, and one code for one rule is the W1120/W1121 model. After that
    > W1122 retires and the existing codes carry the rows. So the language ends with no permanent new code, which is the
    > smallest end state. One source (the rows) for the fix text keeps the warning and the error from disagreeing.
    >
    > **Concern:** W1122 could outlive its one release if no one owns the step that retires it.

  - Q3 `List()`, `List[T]()`, `StringBuilder()` — **H**

    > **Reasoning:** I change from my B1 text, where I listed these three under the rows. devops cites the table's own rule at
    > 03_types.md:194: the table "holds only names that a released version of Blink or its standard library accepted". Three
    > rows for names no release accepted bend that invariant. One E0504 help rule ("a type name is not a callee; here is its
    > empty form") covers these three, every user type, and any later built-in, with no per-name entries. That is one rule in
    > place of a growing list.
    >
    > **Concern:** The help rule needs "the type's one empty form" to be computable for each type. If that lookup gets special
    > cases, it adds back the list we removed.

  - Q4 no warning release for those three — **yes**

    > **Reasoning:** A warning release for a form that never compiled makes the language accept something for one release
    > that it never had. That adds surface in order to remove it. They are errors today; keep them errors.
    >
    > **Concern:** None from my seat. If Q3 R wins, its rows must not be read as a warning phase for these names.

  - Q5 binder order of generic constructors — **S**

    > **Reasoning:** The rule exists so that the stdlib's fixes (`Map[K, V]()` → `Map.new[K, V]()`) are exact. That needs it
    > only on stdlib constructors. G makes "is this function a constructor" a language category the checker must define and
    > enforce on user code. That is a new concept with no user-visible gain. A user's `fn Registry.new[T]()` is an ordinary
    > function.
    >
    > **Concern:** If G wins, the spec must define "constructor" for user code, and that definition is a new rule with edge
    > cases (`with_capacity`, `from_parts`, non-generic types).

  - Q6 binders after the name in §2.12.3 — **yes**

    > **Reasoning:** This adds no feature. It states what §2.12.3 already implies: a type-scoped function is an ordinary
    > function with its own binders. One sentence closes a gap that otherwise invites the `fn Stack[T].empty()` head, which
    > would need a second binder position.
    >
    > **Concern:** gen1 does not parse `fn Stack.empty[T]()` (plt's probe), so for a while the text leads the compiler. That
    > is acceptable, but it needs a ticket.

  - Q7 `Map[K, V].new()` is E0314 — **yes**

    > **Reasoning:** E0314 already exists, and gen1 already emits it for `List[Int].with_capacity(4)`. This gives a form that
    > does not parse today a better message under an existing code. It adds a sentence, not a feature.
    >
    > **Concern:** None significant. It is a diagnostic for a form no seat proposes.

  - Q8 fix class for `List.new[T]()` — **yes**

    > **Reasoning:** A fix that adds an annotation in place of a call goes beyond the call, and DECISIONS.md:471 Q1-R already
    > says such a fix is suggestion-only. The unannotated `let` is the one case where the edit is local and exact. No fix on a
    > disagreeing annotation is correct: the type error is the real problem there.
    >
    > **Concern:** None from my seat.

#### Phase D

Not triggered. Every question passed 6-0.

### Owner amendment

The owner approved the ruling except the warning release. Blink is pre-1.0, so the change breaks users at once: there is no W1122, and each old form is the error that its shape has, with the table row's fix. The panel's W1122 text above (Q2, the Phase A to C quotes, the vote table row, and the follow-ups on W1122 retirement) is superseded.

### Final Spec

```blink
// One empty form per type
let a: List[Int] = []
let b: Map[Str, Int] = Map.new()
let c: Set[Str] = Set.new()
let d = Bytes.new()
let e = StringBuilder.new()

// A bracket list after the callee supplies the callee's binders (§3.4)
let f = Map.new[Str, Int]()
let g = Set.new[Str]()

// Stdlib declarations: the type's parameters, in the type's order
pub fn Map.new[K, V]() -> Map[K, V]
pub fn Set.new[T]() -> Set[T]
pub fn Bytes.new() -> Bytes
pub fn StringBuilder.new() -> StringBuilder
pub fn List.with_capacity[T](n: Int) -> List[T]

// A type-scoped function on a generic type: binders follow the name
pub fn Stack.empty[T]() -> Stack[T]
let s: Stack[Int] = Stack.empty()
let t = Stack.empty[Str]()
```

Locked points:

- Each type has one empty form. A type with an empty literal uses it (`[]`, like `""` for `Str`). The others use `Type.new()`.
- Removed: `Map()`, `Map[K, V]()`, `Set()`, `Set[T]()`, `Bytes()`, `List.new()`, `List.new[T]()`.
- `List.with_capacity(n)` and `StringBuilder.with_capacity(n)` stay. They are a different operation, not a second empty form.
- Type arguments follow §3.4 *Explicit Type Application*. No rule is specific to constructors.
- The stdlib generic constructors declare the type's parameters, in order, as their own binders. `Map.new[Str]()` is E0303. A user's `fn Registry.new[T]()` is an ordinary function; the language does not check its binder order.
- §2.12.3: a type-scoped function on a generic type declares its own binders after the name. `fn Stack[T].empty()` is a parse error; the fix is `fn Stack.empty[T]()`.
- There is no warning release. `Map()`, `Set()`, `Bytes()`, `Map[K, V]()` and `Set[T]()` are E0504. `List.new()` and `List.new[T]()` are E0505. Each error carries the fix from its §3.2 row.
- `List()`, `List[T]()` and `StringBuilder()` get no row. A table row holds only a name that a released Blink accepted. One E0504 help rule covers a callee that names a type: the first `help:` names the type's one empty form. That is `[]` for `List`; `T.new()` when `T` has a type-scoped `new` with no parameters; a struct literal when the caller can write one; otherwise no form. The rule has no per-name case.
- `Map[K, V].new()` is E0314 `TypeArgsWithoutCall`. The fix to `Map.new[K, V]()` is machine-applicable for stdlib types and a suggestion for user types.
- The `List.new[T]()` fix to `[]` with an annotation is machine-applicable only when the call is the whole initializer of a `let` whose pattern is a plain name with no annotation. The annotation and the `[]` are one edit. Elsewhere it is a suggestion. If the `let` has an annotation that disagrees with `[T]`, there is no fix. A `let s: Set[Str] = Set.new[Str]()` is a kept form and gets no diagnostic.

### Amendments

None.

### Implementation notes

These are not spec text.

- All the forms give byte-identical C today (`blink_map_new(&blink_kops_str)`, `blink_bytes_new()`, `blink_list_new_atomic()`). The change removes surface at no runtime cost (sys).
- gen1 does not parse `fn Stack.empty[T]()` or `Map[Str, Int].new()`. Both need a parser change before the new text is true of the compiler. gen1 gives `UnexpectedToken` for the second.
- gen1 emits the retired name `CallSiteTypeArgs`, and its help recommends `Map[Str, Int]()`. The help must name only kept forms.
- gen1 counts the bracket list on `Map.new[..]` against `Map`'s binders. The Q5 declarations make this the general §3.4 rule.
- Migration is about 2,200 sites (moderator count on main, src+lib / tests): `Map()` and `Map[K, V]()` 455 / 1200; `Set()` and `Set[T]()` 24 / 476; `Bytes()` 2 / 32; `List.new()` and `List.new[T]()` 4 / 17. `Bytes.new()` (9 / 123) is a kept form. The migration must not land part-way. `llms-full.md` and the help text change in the same release.
- Follow the 3-step bootstrap order. Add the fixes to the compiler (the §3.2 rows and the `Type.new()` support) and run `task regen`. Migrate src/, lib/ and tests/ off the old forms with `blink fix`. These files must stop using the old forms before or with the compiler change that makes them errors. Then make the old forms errors.
- gen1 reports `List.blah()` as `UnknownMethod` (W0501), a warning, because it does not treat `List` as a known receiver type. The spec makes a removed `List.new` E0505 at the error release, so the type-scoped lookup on a type name must report E0505.
- DevOps's Phase A claim that an unread binding gets no E0301 did not reproduce, and DevOps withdrew it.

### Open cases and follow-ups

- The parser error for `fn Stack[T].empty()` should carry a machine fix to `fn Stack.empty[T]()` (devops).
- A CI check that `blink llms` output teaches no removed form (devops, aiml).
- A future stdlib constructor with an extra binder, such as an allocator parameter, needs a rule on where the extra binders go (plt).
