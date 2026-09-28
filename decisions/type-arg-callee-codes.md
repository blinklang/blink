[< All Decisions](../DECISIONS.md)

# Type-Argument Count at a Call, and Brackets That Are Not a Call — Design Rationale

§3.4 *Explicit Type Application* made `f[T](x)` legal. The spec did not say which diagnostic a
wrong count at a callee gets (`decode[A, B](s)` for a one-binder `decode`), nor which diagnostic a
bracket suffix gets when it is not a type application (`let f = identity[Int]`, `xs[1]`). The
compiler had one code for these shapes, E0307 `CallSiteTypeArgs`, and it refused explicit type
application outright, so its meaning was the opposite of the ratified rule. The panel answered
three questions: the code for a wrong count at a call (Q1), how brackets that are not a valid call
are judged (Q2), and what happens to E0307 (Q3).

Before the vote, the spec's own index examples (`xs[N]`, `mc.elapsed()[1]`, `m[k] = v`) in
06_tooling.md, 04_effects.md, 03b_contracts.md and 03_types.md were rewritten to `.get(N).unwrap()`
and `.insert(...)`, so the spec no longer breaks its own §2.6 rule.

**A note on quotation.** Panelist text below is verbatim. The single exception is `br` ticket
identifiers: `br` is local-only, so per the repo rule that keeps local IDs out of spec, decisions,
and source, each is replaced by a bracketed description of the ticket. No other substitution was
made, and no panelist text was reworded or shortened without an ellipsis.

---

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in
independent-proposal → debate → vote rounds. Phase A produced six independent proposal sets;
Phase A.5 deduped them into one Q1 option with five variations, three Q2 options with four
variations, and one Q3 option. Phase B ran one round, after which all six panelists marked READY
TO VOTE. Phase C was a silent vote. Every line came back 6-0, so Phase D did not trigger.

#### Phase A — Independent proposals

- **Systems:** "My test is the one I apply everywhere: what does the rule compile to, and in which
  phase is it decided? Every question here is decidable **at name resolution**." Its Proposal S1
  found an existing contradiction: "§3.4 already contradicts itself. 03_types.md:1356 lists the
  struct-literal head as a type position where a bare constructor ("including **none**") is E0303.
  But 03_types.md:1467 says `let w = W { n: 1 }` is legal when inference or the annotation fixes
  `T`, and E0301 reports it when nothing does… The struct-literal head behaves like a callee, and
  the fix for both is the same." Its summary: "(1) Wrong arity at a callee: E0303 widened to cover
  application sites… (2) Brackets with no call: New codes E0313 `NoIndexOperator` and E0314
  `TypeArgsWithoutCall`, both decided at name resolution. (3) E0307: Retire it with a tombstone row
  and reuse neither the number nor the name."
- **Web/Scripting:** "My test for each choice: a Python, JS or TS developer reads the error once and
  knows what to type next." Its W2 rule text: "What the brackets contain decides what they mean.
  When the brackets after an expression contain something other than type expressions, the program
  is attempting indexing. Blink has no index operator, and that is `error[NoIndexOperator]` (E0313),
  whether or not a call follows." Its summary: "Each name says what the user did wrong, and each
  first `help:` is an edit that compiles. A developer arriving from another language can decode each
  message in about five seconds."
- **PLT:** "Every bracket suffix is either a type-argument list or it is not. If it is one, we must
  know how many binders it fills. The spec today mixes up two kinds of position… **Type position**
  (parameter, return, field, binding annotation, nested type argument): the constructor *must* be
  applied. A missing list means *k* = 0. That is correct kinding. **Term position** (a callee, a
  struct-literal head): a missing list means **inference supplies the binders**. Only a list that is
  actually written gets its arity checked." On Q2: "'Brackets with no call' is the wrong way to cut
  this. E0307's own text names `fns[0]()`, where brackets *are* followed by a call. What decides the
  case is **what the brackets contain**, and name resolution decides that."
- **DevOps:** "I judge each option by four questions. What does the error line say? Can the LSP
  apply the fix? What does `blink explain <Name>` print? Does `@allow(Name)` mean one thing?" Its Q1
  rule text: "Every type-argument list must supply exactly the number of type parameters its head
  declares… A wrong count, including none where brackets are mandatory, is `error[TypeArgArity]`
  (E0303)." Its Q2: "Two codes, chosen by what the brackets follow… Brackets after a function name
  supply type arguments to a call… Brackets after a value are `error[NoIndexOperator]`."
- **AI/ML:** "Lens: can an agent fix the error from the first `help:` in one step, with no extra
  decision? The three sub-questions below all rest on one split, **what the bracketed head resolves
  to**." Its P2a: "Postfix brackets on an expression that resolves to a value are
  `error[NoIndexOperator]` (E0313)… The front end must recognise `e[...]` whatever the brackets
  contain, so an integer, string or arithmetic argument must not surface as a generic parse error."
  Its fallback: "fold P2b into E0301, whose annotation help is the same, but keep P2a separate at
  any cost."
- **Minimalism:** "**Summary: no new code. Widen E0303 to cover callees, send bracket misuse to the
  existing parser code, and retire E0307 without reusing it.** … One discipline should give one
  code. We have been adding codes for positions when we should be adding them for failures." Its
  M2: "After an expression, `[` opens a type-argument list, and only that. The closing `]` must be
  followed directly by `(` (a call) or by `{` (a struct-literal head). Any other token after `]` is
  `error[UnexpectedToken]` (E1100)."

#### Phase B — Debate highlights

Round 1 settled every flagged variation. Three panelists changed position.

**Minimalism withdrew the parse-error option (2-PARSE):** "My own sharp edge decides it. Under
2-PARSE, `fns[i]()` becomes "unknown type `i`", which misleads the user. A parse rule cannot tell a
local from a type. Name resolution can." It moved to HEAD in round 1: "2-CONTENTS has the same
defect from the other side: `xs[Int]` would be "TypeArgsWithoutCall" on a list value."

**DevOps withdrew its "none where brackets are mandatory" clause and moved from HEAD to CONTENTS:**
"The 1356-vs-1467 contradiction is real. I withdraw "including none where brackets are mandatory".
With no list at a callee or a literal head, inference supplies the binders, and E0301 fires if it
cannot." And: "Under HEAD, `identity[0]` gets TypeArgsWithoutCall and an annotation help, which is
the wrong repair." It proposed the three-step order that the vote adopted, and a guard on plt's help
split: "'Remove the brackets' comes first only when an expected type exists **and fixes the same
arguments that were written**."

**Systems conceded its stage wording:** "I concede my S1 wording. "At name resolution" is false for
a method callee." Four panelists had objected to it; plt: "This is false for `x.decode[A, B]()`,
where the receiver's type picks the method."

**Systems made the case against HEAD:** "The head decides nothing that the contents do not already
decide, and the head is the harder input. For `self.cache[0]` or `obj.items[i]`, the head resolves
only after the receiver is typed. The contents (a literal, a local, or a type name) are sorted at
name resolution in every case. 2-HEAD therefore makes the most common error depend on inference."

**Web and AI/ML proposed a UNION of HEAD and CONTENTS.** Web: "Brackets are an indexing attempt
(NoIndexOperator) when the head resolves to a value that is not a function, **or** any bracketed item
resolves to a value." Both moved to CONTENTS in the vote (see Phase C).

**PLT withdrew its guessed help for over-application:** "My "remove the extra argument" was a
guess, and I withdraw it." **AI/ML withdrew its fold-into-E0301 fallback:** "I withdraw my fallback.
Two codes."

**Four panelists objected to plt's `fns.get(0)?()` help.** DevOps: "`?` compiles only inside a
function that returns `Option`, so a fixer would apply this help in places where it breaks rule 1.
Give a note, or `match` wording, and no machine fix." PLT withdrew it in the vote.

**Three panelists objected to web's "counts as supplied".** DevOps: "This wording invites an
implementation to build a mono key from a rejected list. Say it "supplies nothing, and E0301/E0306
are suppressed"." Web accepted this in the vote.

#### Phase C — Final vote

##### Q1: widen E0303 `TypeArgArity` to every written list, with the term/type cut (**6-0, option A**)

Option A carried five variations: V1a (a callee and a struct-literal head are term positions), V1b
("delete the list" first when inference then fixes every binder, else the exact-count list), V1c
(no E0301 and no E0306 for a rejected list's binders), V1d (`site` as non-normative structured data)
and V1e (decided when the head resolves).

- **Systems:** A — "Arity comes from the declaration's binder count and the length of the written
  list. The check needs nothing more than the head's resolution, so E0303 is the right code, and
  E0301's "cannot infer" would be a false statement here. V1c matters to what the hardware sees. The
  explicit list is the mono key, so a rejected list must supply nothing and never reach mono."
  *Concern:* "A method callee is decided only once its receiver is typed. An implementation could
  let a wrong-count list feed inference before that point, so the rule text must say the list
  supplies nothing even when it is judged late."
- **Web/Scripting:** A — "One discipline gets one name, and `TypeArgArity` reads correctly to a
  newcomer at a callee as well as in a type position. The V1a cut keeps
  `Pair { first: "hi", second: 1 }` legal, and that is the form everyone writes." *Concern:* "For a
  method callee, E0303 is decided only once the receiver's type is known. An implementation that
  still checks at name resolution will report nothing on `x.parse[Int, Str]()`, or report it only at
  a later stage."
- **PLT:** A — "Every written list is judged the same way: a declaration with *n* binders applied to
  *k* ≠ *n* arguments. So there is one code… Suppressing E0301 and E0306 for a rejected list is
  required, not a courtesy. An ill-arity list has no binder-to-argument map, so neither "unbound"
  nor "bound not met" has a meaning there." *Concern:* "An implementation could still let a rejected
  list reach mono as a partial key. The rule text must say the list "supplies nothing", not "counts
  as supplied"."
- **DevOps:** A — "One discipline gets one name, so `@allow(TypeArgArity)` and
  `blink explain TypeArgArity` each mean one thing in every position. Rust's E0107 and TypeScript's
  TS2558 set the precedent. Under V1b the first help is the only edit an LSP can apply by machine
  without guessing." *Concern:* ""Delete the list" can compile and still change the instance,
  because inference may pick `Int` where the written list said `Float`. The fixer must mark this help
  as maybe-incorrect, not machine-applicable, whenever an inferred binder differs from the written
  argument at the same position."
- **AI/ML:** A — "One concept, one learned token. An agent that meets `TypeArgArity` at a callee
  already knows the repair from the type-position case. "Delete the list" first is the one edit a
  fixer can apply without guessing intent, and it always compiles." *Concern:* "agents trained on
  the old catalog line ("type positions only") may not look for E0303 at a call, so the catalog text
  and the explain text must both show a callee example."
- **Minimalism:** A — "One discipline gets one code, and the existing name already fits. The
  term/type cut is not new surface. It removes the conflict between 03:1356 and 03:1467. "Delete the
  list" as the first help is the subtraction repair: it removes text, and it never guesses."
  *Concern:* "The E0303 row gets longer (a position cut, a stage clause and a suppression clause).
  Later edits may drift the catalog one-line text away from §3.4."

##### Q2: the bracket contents decide, in a three-step order (**6-0, CONTENTS**)

Round 1 stood 3 CONTENTS (systems, DevOps, PLT), 1 HEAD (minimalism), 2 UNION (web, AI/ML). All
six voted CONTENTS.

- **Systems:** CONTENTS — "Classifying by contents needs only name resolution of the items, and it
  gives a repair that exists in the rare cases where the options differ. Take `xs[Int]`: CONTENTS
  gives E0303 or E0314 with "remove the list". UNION gives NoIndexOperator with a `.get(Int)` help,
  and that repair does not exist, which breaks §3.1 rule 1." *Concern:* "A name that resolves as
  both a type and a value needs a stated tie-break. I suggest the value namespace first, which gives
  NoIndexOperator. That is the more likely intent, and it is the safer help."
- **Web/Scripting:** CONTENTS — "I move from UNION… UNION and CONTENTS differ only on `xs[Int]`, a
  shape nobody writes by habit. Sys is right that the head is the harder input: for `self.cache[0]`
  it waits on the receiver's type… CONTENTS also gives the user one sentence to learn: "a value
  inside the brackets means indexing, and Blink has no indexing."" *Concern:* "`xs[Int]` on a List
  reports "`xs` takes 0 type arguments, 1 was given". It is correct but mildly confusing. When the
  head is a non-function value, E0303 should add a `note:` that element access is `.get()`."
- **PLT:** CONTENTS — "The contents are the only input decided at name resolution in every case…
  Min's counterexample `xs[Int]` does not reach TypeArgsWithoutCall under CONTENTS, because arity is
  checked first. A value head binds 0, so the error is E0303, "`xs` takes 0 type arguments", with
  help "remove the list". That statement is true and the repair exists." *Concern:* ""Is a type"
  must be defined exactly: the item parses as a type expression and resolves in the type namespace.
  Otherwise a name that is bound as both a type and a value splits across implementations."
- **DevOps:** CONTENTS — "The contents are sorted at name resolution in every case, with no receiver
  typing. So the most common error, `xs[i]` and `self.items[i]`, never waits on inference, and
  `blink check` reports it even in a file where inference fails elsewhere." *Concern:* "A user who
  writes `xs[Int]` gets an arity message where an index lesson would teach more. The E0303 explain
  text should cross-reference NoIndexOperator for a value head."
- **AI/ML:** CONTENTS — "I move from UNION. sys's point decides it. For `self.cache[0]`, the head
  resolves only after the receiver is typed. The contents sort it at name resolution, so the
  commonest habit error gets its code early and the same way every time." *Concern:* "a value whose
  name looks like a type (an uppercase constant such as `xs[MAX]`) must resolve as a value, or the
  commonest error gets the wrong code. The spec example set should include one."
- **Minimalism:** CONTENTS — "In round 1 I backed HEAD because of `xs[Int]`. Under CONTENTS
  precedence, `xs[Int]` goes to E0303 against a head that binds 0, with the help "remove the list".
  That message is true and the repair works, so my objection is gone… The rule with the fewest
  clauses that is still right wins." *Concern:* "A new future construct that is neither a clear value
  nor a clear type inside `[...]` (for example, a const generic) would have no place in the
  three-step order and would need an amendment."

**Q2 sub-items (all 6-0):**

- **Numbers:** E0313 `NoIndexOperator`, E0314 `TypeArgsWithoutCall`. Every panelist voted yes.
- **First help for `TypeArgsWithoutCall`: P+G** (plt's split, with devops's guard).
  - **AI/ML:** "When the expected type fixes different arguments than the ones written
    (`apply(identity[Str], 3)`), "remove the brackets" silently drops the author's stated type. A
    mechanical fixer must not apply that."
  - **DevOps:** "Without the guard, `apply(identity[Str], 3)` gets "remove the brackets". That edit
    compiles, and it silently changes the instance the user wrote. That is the "compiles while
    deleting the construct the user needed" case §3.1 rule 1 forbids."
  - **PLT:** "If the expected type fixes different arguments from the written ones, removing the
    brackets silently changes the instantiation. That is a change of meaning, not a repair."
  - **Systems:** "The guard keeps the machine fix meaning-preserving. When the guard fails, the real
    error is a type mismatch at the argument, and that error should lead."
  - **Web/Scripting:** "The guard is what makes "remove the brackets" a repair that works."
  - **Minimalism:** "It also keeps faith with §3.1 rule 1 in spirit: the repair must be the program
    the user meant."
- **Help for a callable element (`fns[0](x)`): a note or `match` wording, no machine fix.**
  - **PLT:** "`fns.get(0)?()` type-checks only inside a function that returns Option, so as a machine
    fix it breaks rule 1. I withdraw it."
  - **Web/Scripting:** "Everywhere else it is a quick-fix that introduces a new error, and that loses
    a new user's trust in help lines faster than no fix at all. The note must still say that
    `.get(0)` returns `Option`, because that is the lesson."
  - **DevOps:** "`.unwrap()` is a panic the language deliberately designed out of indexing, so the
    tool must not insert it for the user."
  - **Systems, AI/ML, Minimalism:** yes, on the same ground (`?` depends on the enclosing function's
    return type).

##### Q3: retire E0307 `CallSiteTypeArgs`; never reuse the number or the name (**6-0, RETIRE**)

- **Systems:** RETIRE — "Suppression and tooling key on the name, so reusing the number or the name
  would silently change what an old `@allow(CallSiteTypeArgs)`, log line or trained model means."
  *Concern:* "The gen0 binaries still print the old E0307 explain text until the next re-pin, so a
  user can meet the stale meaning in the meantime."
- **Web/Scripting:** RETIRE — "People search error codes. "E0307" already finds explain text and
  decision records that say the opposite of the ratified rule." *Concern:* "The retired
  `blink explain CallSiteTypeArgs` text must point to E0303/E0313/E0314. If it just says "retired",
  the user who found it in an old log has nowhere to go."
- **PLT:** RETIRE — "E0307's published meaning is the negation of the ratified rule… A row in the
  Retired table is the only thing the catalog's never-reuse rule can protect." *Concern:* "Old
  binaries still print E0307's explain text, so the retired row should point to E0303, E0313 and
  E0314."
- **DevOps:** RETIRE — "The name and number have printed the opposite meaning, "brackets at a call
  are banned", in compiler output and in decision records." *Concern:* "The spec does not say what
  `@allow(CallSiteTypeArgs)` or `blink explain E0307` does after retirement. Both should report
  "retired" and name the current codes, and should not fail silently. The E0503 retirement, now only
  a comment in src, should get a row in the same table."
- **AI/ML:** RETIRE — "This repository is training data, and "E0307 CallSiteTypeArgs" is bound in it
  to "remove the brackets". That is the opposite of the ratified repair." *Concern:* "if the row is
  added without updating the `blink explain E0307` text, the old "open question" explanation keeps
  shipping and keeps training the wrong fix."
- **Minimalism:** RETIRE — "One tombstone row costs less than one flipped meaning in logs, gen0
  binaries and training data." *Concern:* "The Retired table must be kept up to date, or the next
  retirement will again live only as a source comment."

#### Phase D

Not triggered. Every line came back 6-0.

---

### Final Spec

```blink
fn decode[T](s: Str) -> T { ... }
fn plain(n: Int) -> Int { n }
fn identity[T](x: T) -> T { x }
fn apply(f: fn(Int) -> Int, n: Int) -> Int { f(n) }

fn main() {
    // Q1 -- a wrong count at a callee or a struct-literal head is E0303
    let a = decode[Forecast, Str](body)       // error[TypeArgArity]: `decode` takes 1 type argument, 2 were given
    let b = plain[Int](3)                     // error[TypeArgArity]: `plain` takes 0 type arguments, 1 was given
                                              // help: delete the list: `plain(3)`
    let p = Pair { first: "hi", second: 1 }   // OK -- term position, inference supplies the binders

    // Q2 -- the bracket contents decide
    let xs = [10, 20, 30]
    let x = xs[1]                             // error[NoIndexOperator]: help: `xs.get(1)` returns `Option[Int]`
    let y = xs[Int]                           // error[TypeArgArity]: `xs` takes 0 type arguments, 1 was given
    let r = apply(identity[Int], 3)           // error[TypeArgsWithoutCall]: help: `apply(identity, 3)`
    let f = identity[Int]                     // error[TypeArgsWithoutCall]
                                              // help: `let f: fn(Int) -> Int = identity`
}
```

- **Q1.** E0303 `TypeArgArity` covers every written type-argument list. A callee and a
  struct-literal head are term positions: an absent list there is left to inference (E0301 if it
  cannot). A callee counts its own binders only; impl binders come from the receiver (§3.6). A
  non-generic declaration or a local value binds zero.
- **Q1.** The first help is "delete the list" when inference then fixes every binder, and the
  exact-count list otherwise.
- **Q1.** A rejected list supplies nothing: no E0301 or E0306 fires for that call's binders.
- **Q1.** E0303 is decided when the head resolves: at name resolution for a path, and once the
  receiver's type is known for a method.
- **Q2.** In order: any bracket item is a value → E0313 `NoIndexOperator`, with or without a call;
  every item is a type → E0303 against the head; a well-formed list with no `(` or `{` after it →
  E0314 `TypeArgsWithoutCall`. An item is a type when it parses as a type expression and every name
  in it resolves to a type or a type parameter.
- **Q2.** E0314's first help removes the brackets only when an expected type fixes the same
  arguments as written; a binding with no expected type gets the combined annotation edit; a
  conflict gets no machine fix.
- **Q2.** A callable element (`handlers[0](req)`) gets a `note:` and no machine fix.
- **Q3.** E0307 `CallSiteTypeArgs` is retired. ERROR_CATALOG.md gains a *Retired Codes* table, and
  neither the number nor the name is reused.

Spec text: 03_types.md §3.4 (*Explicit Type Application*, *Kind-Correctness*, *Postfix Brackets
That Are Not a Type Application*), 02_syntax.md §2.6, and ERROR_CATALOG.md.
