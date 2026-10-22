[< All Decisions](../DECISIONS.md)

# Return With a Value in a Function That Returns () — Design Rationale

**Resolution:** `return e` checks `e` against the return type of the nearest enclosing function or closure, for every return type, `()` included. A mismatch is `TypeError` (E0300), the same fault as for any other return type. `return`, `return ()`, `return e` where `e` has type `()`, and `return e` where `e` has type `Never` stay legal in a function that returns `()`. The tail drop is unchanged: it applies to the result of the last statement, and the operand of `return` is never dropped. A closure with an expected function type takes its return type from that type. A closure with no expected type has the one type on which every `return e` and a tail that can complete agree, and `()` when there is none. The text "(equivalently `-> Void`)" leaves *Divergence and Body Completeness*.

**Vote:** Q1 6-0; Q2 6-0. Phase B and Phase D did not run.

## The Gap

§3.3 *Divergence and Body Completeness* names only the tail, and only for value-returning functions. The tail drop of §3.2.2 lets `fn f() { 5 }` pass. Nothing said what `return 5` means in a function that returns `()`. Measured on the compiler at the time (`blink check`, main):

| Program | `blink check` |
|---|---|
| `fn f() { return 5 }` | ok |
| `fn g() -> () { return "s" }` | ok |
| `h(fn(i: Int) { return i })`, `h` takes `fn(Int) -> ()` | ok |
| `let k = fn() { return 5 }`, then `let x: Int = k()` | ok; `k` is `fn() -> Int` |
| `let g: fn() -> () = fn() -> Int { 5 }` | rejected: "closure return type: declared type () but written Int" |
| `fn f(b: Bool) -> Int { if b { return } 5 }` | rejected: bare `return` has no value |

### Panel Deliberation

The ticket, verbatim:

> **May a fn that returns () use return with a value (fn f() { return 5 })?**
>
> Question: in a fn whose return type is () (written `-> ()` or left off), is `return e` with a value an error, or is the value dropped as a tail value is?
>
> Options: (a) error, "return value type Int does not match function `f` return type ()" (as for any other R); (b) drop the value, as for a tail; (c) error in named fns and under an expected () type, while (4) infers Int from the return.

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in independent-proposal → silent-vote rounds. Phase B did not run: the six first choices were the same rule.

#### Phase A — Independent proposals (excerpts)

All six seats put the same rule first: `return e` checks `e` against the return type for every return type, `()` included, and the tail drop stays. The moderator named it R1. Each seat also wrote down option (b), the drop of the value, as a second proposal, and opposed it.

- **Systems** (sys-1):

  > sys wants the source to say what the machine does.

  And: "No systems language I know drops an explicit `return` value silently." Of option (b): "sys opposes sys-2."

- **Web/Scripting** (web-1):

  > `return e` is never accidental. Nobody types `return` plus a value without meaning "hand this back". If the fn cannot hand it back, say so.

  Of option (b): "I oppose this as the rule. If the panel picks it anyway, it must ship with a warning (new W-code) on `return e` where `e` is not `()`, or the silent drop stays a trap."

- **PLT** (plt-1):

  > `return e` has one typing rule for every `R`, `()` included: the operand checks against the return type of the nearest enclosing fn or closure.

  Of option (b), under the heading "plt-2 (OPPOSED)": "The disjunct `R = ()` makes `()` a special type. That contradicts F4, which the panel decided."

- **DevOps** (devops-1):

  > A diagnostic that has no `if R == ()` exception is easier to explain, to document in one ERROR_CATALOG row, and to test.

  Of option (b): "I list it only as the fallback if the panel wants zero breakage; I oppose it."

- **AI/ML** (aiml-1):

  > One rule for `return e` over all `R`. A model does not need to know whether `R` is `()` to predict the checker.

  Of option (b), under the heading "aiml-2: drop the value (ticket option b) — I oppose": "But it keeps the silent-bug path above, it contradicts p7 for closures, and it needs a "except when R is ()" clause in the spec."

- **Minimalism** (min-1):

  > The minimal fix removes that special case. It does not add a rule.

  Of option (b): "Listed so the panel sees why I oppose it."

Two more proposals were opposed by their authors:

- **web-3** (a closure with no context returns `()`). Web: "That splits a rule devs rely on in every `map`/`filter` callback. No."
- **devops-3** (option (c) without the all-exits rule). DevOps: "With rule 3 added, (c) and devops-1 are the same rule."

DevOps and PLT each found that an unannotated closure with an early `return 5` and a tail that falls through passes `blink check` and reads an unset value at run time. This is a separate bug.

#### Phase B — Did not run

The dedupe gave two options (R1 and R2) and one flagged variation (the "(equivalently `-> Void`)" text). No seat asked for a debate.

#### Phase C — Final vote

Each panelist voted alone on a written ballot. The points that follow from R1 were on the ballot as carried points, with no vote: which `return` forms stay legal in a `()` function, that the tail drop stays, the closure rule, and the diagnostic.

##### Q1 — The rule — **R1** (6-0)

R1: `return e` checks `e` against `R` for every `R`, `()` included. R2: when `R` is `()`, the value of `return e` is dropped, as a tail is.

- **Systems:** "The source must say what the machine does. Under R2, `return build_big_list()` in a `()` fn allocates and then throws the value away, and the source says "hand this back"."
- **Web/Scripting:** "A dev who writes `return 5` in a fn with no `-> R` almost always forgot the annotation. R1 reports it on that line with a "declare `-> Int`" fix, and R2 moves the fault to the call site or hides it."
- **PLT:** "The rule `Γ ⊢ e ⇐ R ⟹ Γ ⊢ return e : Never` applies to every `R` and never tests whether `R = ()`. That keeps `()` an ordinary type, as decided (03_types.md:6097)."
- **DevOps:** "The error at the `return` names the cause (a missing `-> T`) at the place where it is, not later at a call site as "cannot assign () to Int"."
- **AI/ML:** "One rule for `return e` over every R means a model can predict the checker without a "unless R is `()`" special case, and special cases are what models miss when they learn from the spec alone."
- **Minimalism:** "R1 removes a special case and adds none." And: "R2 would write an exception for one type into the spec and hide a real bug class, a forgotten `-> T`."

##### Q2 — The text "(equivalently `-> Void`)" — **V1, delete it in this patch** (6-0)

V1: delete the text in this patch. V2: leave it for a separate wording chore. In Phase A, min and plt held V2. The dedupe also listed sys under V2; that was a mistake, because sys already asked in Phase A to delete the text in the same patch, and its Phase C ballot corrects the dedupe.

- **PLT** moved from V2 to V1: "I change my Phase A position." Its reason: "The deletion only removes a false statement and does not change what the language means, so it needs no separate deliberation. A separate chore only means the error stays in the spec for longer."
- **Minimalism** also moved: "I change my Phase A position. The patch already edits this paragraph, and the fix is to delete three words that contradict 03_types.md:6106."
- **Systems** (corrects the dedupe): "The dedupe puts sys under V2, but my A file says "Drop the parenthetical in the same spec edit"." And: "If we leave a known false sentence in a paragraph we are editing, a reader or an LLM can learn a wrong `-> Void` from it."
- **AI/ML:** "Left in, it tells a model reading the body-completeness rule to write `-> Void`, which the spec elsewhere makes E0828: a direct contradiction in the text that models learn from."
- **DevOps:** "Deleting four words in a paragraph you are already editing is cheaper than opening a separate chore that someone has to remember."
- **Web/Scripting:** "A learner who reads it in the section that defines the return rule will write `-> Void` and get an error."

#### AI-First Review

Learnability: one rule for every return type, and one sentence to teach the tail difference. Consistency: `()` gets the check every other type gets, and E0300 and E0311 keep their meaning. Generability: the common slip, a missing `-> T`, gets an error that names the fix. Debuggability: the error points to the place where `()` came from. Token efficiency: no new code, no new syntax, and correct programs need no extra tokens.

### Final Spec

```blink
fn lg() {
    io.println("hi")
}

fn tail() { 5 }                  // OK: the last statement drops its result
fn early() { return 5 }          // error[TypeError] (E0300): Int does not match return type ()
fn typed() -> () { return "s" }  // error[TypeError] (E0300): Str does not match return type ()

fn forward(b: Bool) {
    if b { return lg() }         // OK: lg() has type ()
    if b { return () }           // OK
    if b { return panic("x") }   // OK: the operand has type Never
    return                       // OK
}

fn h(cb: fn(Int) -> ()) { cb(1) }

h(fn(i: Int) { return i })                  // error[TypeError] (E0300): the expected type gives ()
h(fn(i: Int) { i })                         // OK: the tail is dropped

let k = fn() { return 5 }                   // fn() -> Int
let m = fn(b: Bool) { if b { return 5 } }   // error[MissingReturn] (E0311)
let q = fn() { return panic("x") }          // fn() -> ()
```

Locked points:

- `return e` checks `e` against the return type of the nearest enclosing function or closure, for every return type, `()` included. A mismatch is `TypeError` (E0300). No new code.
- In a function that returns `()`: `return`, `return ()`, `return e` where `e` has type `()`, and `return e` where `e` has type `Never` stay legal.
- The tail drop stays. It applies to the result of the last statement. The operand of `return` is not a statement result, so the drop never applies to it. The spec shows `fn f() { 5 }` and `fn f() { return 5 }` side by side.
- A closure with an expected function type takes its return type from that type.
- A closure with no expected type has the one type on which every `return e` and a tail that can complete agree, and `()` when there is none. A `return e` with a `Never` operand adds no constraint. A tail that can complete with `()` after a valued `return` is `MissingReturn` (E0311), as for a named function with `-> R`. Exits that disagree are `TypeError` (E0300).
- The help of the E0300 names two fixes, in this order: add `-> T` to the signature, or drop the value. Dropping the value keeps a call as its own statement: `return save(x)` becomes `save(x)` and then `return`. When `()` comes from an omitted `-> R` or from an expected parameter type, the error points to that place.
- *Divergence and Body Completeness* loses only the text "(equivalently `-> Void`)". The rest of the `()` bullet keeps its words.
- The divergence list names "A `return`, with or without a value", because `return e` also has type `Never`.

### Concerns for implementation

- **AI/ML:** "The tail-drops but `return`-errors asymmetry (`fn f() { 5 }` OK, `fn f() { return 5 }` error) will surprise readers unless the spec shows both lines side by side and the E0300 help names both fixes in the order "add `-> T`" then "drop the value"."
- **DevOps:** "If the secondary label does not point at the omitted `-> T` (or at the parameter that set a closure's type), users who never wrote `()` will not see where it came from. Also, a "drop the value" code action that deletes `e` will delete a call's side effects. Both must ship with the fix, not as follow-ups."
- **Minimalism:** "The closure inference text ("the one type that every `return e` and a completing tail agree on; `()` when there is none") could grow into its own sub-rules in the spec. The decision should state it in one sentence and show the cases only as examples."
- **PLT:** "The synthesis rule ("every `return e` and a tail that can complete agree; `()` when none") must say that a `Never` operand adds no constraint and that a tail that falls through after a valued `return` is E0311. If the spec text leaves either point out, the implementation can bring back the "first valued `return` wins" shortcut that caused the fall-through bug." On Q2: "The patch must delete only the parenthetical and must not reword the rest of the `()` bullet, so that the change stays a pure deletion and nobody can read it as a new rule."
- **Systems:** "The closure inference rule ("R is the one type that every `return e` and a tail that can complete agree on") must stay exact in the compiler. The fall-through bug that devops and plt found shows that today's closure path can emit C that reads an unset return slot, so the R1 fix must land with that bug, or at least with a corpus test for it."
- **Web/Scripting:** "The fix breaks code that compiles today, and a closure in a callback context (`h(fn(i: Int) { return i })`) may surprise script devs. The help text must name the parameter whose type sets `()`, or they will not see why their closure "returns ()"."

### Follow-ups

- Implement the rule in the type checker, for named functions and for closures. The checker has no `()` exception for `return e` after this change.
- The existing closure fall-through bug: an unannotated closure with an early `return 5` and a tail that falls through reads an unset value at run time. The panel asks that its fix land with, or before, the fix for this decision.
