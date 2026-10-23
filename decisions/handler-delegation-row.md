[< All Decisions](../DECISIONS.md)

# Handler Delegation Row — Design Rationale

Spec ticket: a handler clause that forwards (`default.op(..)`, a call through the handled effect, or an omitted primitive operation) performs the handled effect E outside the handler, but the checker gives the clause body E for free. A function with an empty row can then print through the outer handler. A friction ticket asks which handler a forward reaches.

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in independent-proposal, debate and vote rounds. Panelist text below is verbatim, with "…" where the moderator cut. Seat names: sys = Systems, web = Web/Scripting, plt = PLT, devops = DevOps/Tooling, aiml = AI/ML, min = Minimalism.

#### Result

| Q | Question | Result | Vote |
|---|---|---|---|
| Q1+Q2 (paired) | Where the clause row is charged, and which handler a forward reaches | W: the handler type carries its clause row; the `with` is charged; a forward reaches the handler in force for E at the `with` that installed it | 6-0 |
| V1 | Spelling | `Handler[E ! R]` (row inside the brackets) | 6-0 |
| V2 | `Handler[E ! _]` in parameter types | ship | Phase C 4-2 (plt, min defer) → Phase D 6-0 ship |
| V3 | Several `with` items | follow `with a, b` = `with a { with b }` | 6-0 |
| V4 | Codegen conditions | in this file and the implementation ticket only; the spec prescribes no copy | 6-0 |

AI-first review: 5 of 5 criteria pass.

#### Phase A — Independent proposals

All six seats agreed on the base rule: the "+E" grant on clause bodies goes. `default.op`, a call through E in a clause, and an omitted primitive op perform E outside the handler. An omitted derived op adds nothing. They differed on where the row is charged.

##### Systems

> "So the delegation target for E is **bound at construction**, by one struct copy, with no search at call time. This is what [the forward-target ticket] reports."
>
> "The `Handler[E]` type carries no row (L180/L182, §4.7.1). Any rule that charges clause effects at the `with` site has nothing to read when the handler is a parameter, a field, or a returned value. So charging at the `with` site needs a type change. Charging at the literal does not."
>
> "## sys-1 (my proposal): a handler literal is a capability object. Charge its authority where it is built" — sys

##### Web/Scripting

> "**Rule (one sentence for the spec):** The clause bodies of a `handler E { ... }` expression are checked against the effect row in force at the handler expression, and that row does not get `E` from the handler itself."
>
> "A handler that forwards anything needs the forwarded effect where you write it. "If you pass it on, you must hold it." That is the ocap rule (§4.10: attenuate, never amplify) as a typing rule." — web (web-1)

##### PLT

> "`Handler[E]` is the one value type that runs effectful code and shows no row."
>
> "`Handler[E ! R]` — a handler for E whose operation bodies perform row R. `Handler[E]` with no `!` means R is empty (a pure handler)… The row sits inside the brackets, so it cannot be confused with the row of a fn that returns a handler."
>
> "Because Blink handlers are first-class (DECISIONS L180, L2072 "stored beyond the scope that created it"), the only sound way to carry that row from literal to `with` site is in the type." — plt (plt-1)

##### DevOps/Tooling

> "One coupling the panel must settle first: **the charge site must be the site that fixes the delegation target ([the forward-target ticket]).** If `default.op` reaches the handler in force where the literal was evaluated (what gen1 does today), the literal's fn is the one that uses the outer capability, and we must charge the literal."
>
> "## devops-1 (my pick): charge at the literal; the delegation target is fixed at the literal" — devops

##### AI/ML

> "**Rule.** A handler value is a closure over its operations. Its type carries its operation row with the same `!` grammar as a fn type (§4.15.1): `Handler[E]` (no `!`) means the operations perform nothing; `Handler[E] ! R` means they may perform `R`. A handler literal's row is inferred, like a closure literal's." — aiml (aiml-1)

##### Minimalism

> "The hole is one grant, not a missing feature."
>
> "So the smallest fix removes a rule. It adds no syntax, no type parameter and no diagnostic code." — min (min-1)

#### Phase B — Debate highlights

plt's escape probe (plt/escape.bl) decided the debate. A factory `make() ! Audit.Note` builds a handler inside a `with`. The value leaves that `with`. A function `sandbox(h)` with an empty row installs it. The program passes `check`, and the forward reaches a handler whose `with` has ended.

##### web withdraws web-1

> "plt's escape probe makes me drop web-1… The program passes `check`, and a fn with no `!` sends an `Audit.Note` call that reaches an outer handler. Put a `Scoped` handler in place of the outer one and the call runs after `exit()`. A Python dev would call that a closed file still being written. No message from the compiler explains it. Q1-L closes the ticket MVCE and nothing more."
>
> "plt-1 is the one-model answer: **a handler is a bundle of closures, so it gets a row in its type like a closure, and it pays the row where it runs.**" — web

##### devops withdraws devops-1

> "gen1's copy of the vtable at the literal (cg_print.bl:854) is a codegen detail that disagrees with voted text. The forward-target ticket is a friction ticket about that disagreement, not an open design point. If we pick construction, we reverse two votes and change a shipped diagnostic. Sys-1, web-1, min-1 and my own devops-1 did that without saying so. I missed it in Phase A." — devops

##### min withdraws min-1

> "I argued for min-1 because it removes one grant and adds no surface. Two cases in the Phase A texts show it is not sound alone. The extra rule it then needs costs more than plt-1."
>
> "**plt-1 reuses the closure rule.** The value's type carries the row, and the site that runs the code (the `with`) is charged. This reuses a rule, which is a minimalism win." — min

##### sys concedes the probe and withdraws sys-1b

> "My sys-1 argument was "the factory holds the authority, so the value may carry it". That is the ocap rule for the row check, and it holds… But the value carries more than authority. With construction binding it carries a pointer to a *specific handler*, and that handler belongs to a `with` extent. Once the value leaves the extent, the forward reaches a handler whose `with` has ended."
>
> "sys-1b makes this worse, not better: it captures the slots of *every* effect the clauses use, so every captured slot can outlive its `with`. I withdraw it." — sys

##### aiml: the spec already says install

> "The spec text already says which context a forwarded call uses. §4.7.1 *`default`*: "`default.op(args)` delegates to the handler that this operation's handler **was installed over**."… "Installed" means the `with`, not the literal. So gen1's construction-time copy (src/cg_print.bl:854) differs from the spec. It is not a design the spec chose." — aiml

##### plt asks for one paired vote

> "Each pairing has exactly one sound answer:
> - Q1-W + install: sound. Q1-W + construction: unsound (the with-site proof is about another handler; escape.bl).
> - Q1-L(+1b) + construction: sound for rows, with the revocation gap above. Q1-L + install: unsound (web's own note, A_web.md L106-113).
> I ask the moderator to vote Q1 and Q2 as one paired option, so no tally can land on an unsound pair." — plt

##### sys flags the order of several `with` items

> "04_effects.md:2005 says "`with a, b { body }` means `with a { with b { body } }`", so `a` is outside and `b` is innermost. 04_effects.md:1888 says "If two handlers cover the same effect, the leftmost wins (innermost-scope semantics)", so `a` is innermost. Both lines are in the spec today… Moderator: please put the L1888 / L2005 conflict to plt and check which one the compiler does." — sys

The moderator ran the probe (probe2/order.bl): two `IO.Print` handlers `a` and `b`, and `with a, b { io.println("x") }` prints `B got x`. The compiler follows the `with a { with b }` text. The "leftmost wins" sentence is wrong.

##### Withdrawn options

web-1, devops-1 and min-1 (by their authors) and sys-1b (by sys). The ballot offered three options: W (plt-1), L+ (sys-1 in full, with plt's conditions) and W2 (plt-2: row inferred, not writable, a handler with a non-empty row may only be installed in the fn that builds it).

#### Phase C — Final vote

##### Q1+Q2 (paired) — W, 6-0

- **sys:** W. "A `Handler[E]` value is code that runs later at another site, so its row must travel in its type, as a fn type's row does. A forward then reaches only a handler that is in force while the op runs. That closes the use-after-`exit` path that construction binding opens, and it needs no capture." Concern: "Codegen can let R leak into C types or mono keys, which gives one C instance per row and code bloat. The impl ticket must state that R is checked and then erased."
- **web:** W. "A handler is a bundle of closures, so it should follow the closure rule users already know: the row is in the type, you pay where it runs, and it uses the handlers in force there." Concern: "A factory author who returns `Handler[E]` from a clause that logs or forwards hits a type mismatch on day one. If the fix-it does not write the inferred `! R` into the return type, this becomes the most-asked handler question."
- **plt:** W. "W is the only pair under which every `with` site holds a proof about the handler that actually answers… §4.1 L11 and Principle 5 stay true as written, with no exception for handler values." Concern: "If [the forward-target ticket]'s codegen change (forward resolved at install, not copied at the literal) lands after the row rule, the checker will prove the `with`-site handler while the binary calls the literal-site one. The impl ticket must ship both in one change."
- **devops:** W. "Only W points the error at a place the user can fix and gives a machine-applicable fix: the `with` item, a `note:` at the `default.op` span or the handler head, and a fix-it that writes the inferred row into a `Handler[...]` return type." Concern: "The impl can ship the `with`-site check before [the handle-op capability ticket] maps the builtin handle ops. Then R silently omits every builtin effect (`io.log` in a clause adds nothing) and users get a check that looks complete but is not."
- **aiml:** W. "One rule covers both kinds of value that run code later. A closure or a handler carries its row in its type, and the row is charged where the code runs (a call or a `with`), with the handlers in force there." Concern: "Inference makes the row invisible in the common case. A model that has seen only `Handler[E]` may then write that type for a returned forwarding handler… so the fix-it must write the inferred `! R` into the type mechanically."
- **min:** W. "W reuses the rule closures already follow: the value's type carries its row, and the site that runs the code pays." Concern: "People may read the L180 amendment as permission to put more parameters on `Handler`. The decision file should state that the row slot is the only addition, and it is the same row that fn types carry."

##### V1 — `Handler[E ! R]`, 6-0

- **sys:** "With the row inside the brackets, a parser or a reader cannot confuse it with the row of the fn that returns the handler." Concern: "People can read `Handler[E ! R]` as an effect-kinded generic argument and then ask for effect variables there. The spec must say R is a concrete row (or `_`), not a type parameter."
- **web:** "With the row inside the brackets, it belongs to the handler and only the handler." Concern: "Users will still write `-> Handler[E] ! R` by habit from fn types, so the parser error for that shape must say "did you mean `Handler[E ! R]`"."
- **plt:** "The `!` still reads as "performs", and an absent row means pure, as it does in fn types." Concern: "Readers will see `fn() -> T ! R` and `Handler[E ! R]` as two places for `!`. The spec must give both in one sentence so that neither looks like a special case."
- **devops:** "Inside the brackets there is one reading, and the "add effect to fn row" and "add effect to handler row" fix-its edit different tokens." Concern: "The parser must give a targeted help ("a handler's row goes inside the brackets: `Handler[DB ! IO.Log]`"), not a generic row mismatch on the fn."
- **aiml:** "It can be read only one way, in return position too." Concern: "fn types keep the open return-position `!` ambiguity (04_effects.md L607/L787)… that gap needs its own ticket soon."
- **min:** "A reader can parse it only one way… No `!` means an empty row, the same default as fn types." Concern: "The formatter and the LSP hover must print the inferred R in this form every time, or users will see two spellings."

##### V2 — `Handler[E ! _]` in parameter types: ship 4, defer 2

- **sys (ship):** "Without `Handler[E ! _]`, a fn that installs a handler it receives (the spec's own `run_with`, the sandbox pattern) accepts only pure handlers, or hard-codes one R per helper." Concern: "If the `! _` pass for fn types does not carry over directly to a handler parameter, the impl can stall on V2 and hold back the soundness fix. Ship the core rule first, and land V2 in the same release but as a separate slice."
- **web (ship):** "`! _` is how Blink already passes a callback's row through (§4.15), so `Handler[E ! _]` costs no new idea." Concern: "If it is deferred, the `run_with` example must change in the same edit, or the spec will teach a signature that rejects the common logging handler."
- **plt (dissent, defer):** "The ticket needs concrete rows only. `! _` on a handler parameter is a new reading of wildcard forwarding: the callee takes on a row that comes from a value it installs, not from a value it calls. That deserves its own typing rule once a real combinator needs it, instead of a clause added to this ruling." Concern: "If ship wins, the spec must state how `_` from a handler parameter joins `_` from closure parameters in one row. That rule is not written yet."
- **devops (ship):** "`fn run_with(h: Handler[DB ! _]) ! _` reuses the `! _` reading users already know from fn params (§4.15)." Concern: "If `! _` on a handler param is resolved by a different path than `! _` on fn params, the two will give different messages for the same mistake; the impl must reuse one code path."
- **aiml (ship):** "§4.15.2 teaches `! _` wherever a row is written. A model will write `Handler[DB ! _]` in a parameter type and expect it to work." Concern: "`_` forwarding on a handler parameter needs its typing rule stated as clearly as for fn types. Otherwise models will read `Handler[E ! _]` as "any handler, rows ignored"."
- **min (dissent, defer):** "No probe, stdlib function or spec example needs a combinator over effectful handler values, and concrete rows can express every case shown. The spelling `Handler[E ! _]` stays free, so it is cheap to add later by the `fn() ! _` rule, when a real need appears." Concern: "If it ships now with no user, its interaction with projection (L181) and with `with` order goes untested in the corpus."

##### V3 — follow `with a { with b }`, 6-0

All six voted: for `with a, b`, b forwards to a; R_b is checked against the enclosing row plus a's effects; R_a against the enclosing row.

- **sys:** "The probe shows the compiler already makes the rightmost item innermost, and L2005 is the detailed, normative text (evaluation order, LIFO teardown, `?` unwind)." Concern: "The L1891 text fix must land with this ruling. If it does not, readers and LLMs who trust "leftmost wins" will put a forwarding handler on the wrong side and get an E0500 they cannot explain."
- **web:** "`with a, b` reads as `with a { with b }`, and the compiler does that today (probe2/order.bl prints `B got x`)." Concern: "L1891 ("leftmost wins") says the opposite. Until that chore lands, readers will get two answers from one section."
- **plt:** "My Phase A text took the direction from L1891, which is the line in error. I withdraw that direction and accept sys's correction." Concern: "Write the multi-item check as the nested desugar, not as "left" or "right", so that it cannot inherit the error."
- **devops:** "The E0500 note must name the items it checked, for example "`b` forwards to `IO.Print`; no item to its left in this `with` provides it, and `deleg` does not declare it", so users do not reorder items by trial and error." Concern: "L1891 ("the leftmost wins") stays in the spec until its text-fix chore lands… the chore should land with this ruling, not after."
- **aiml:** "A model can find the multi-item check by rewriting to nested `with`s, so it needs no separate rule." Concern: "Until the L1891 text fix lands, models trained on the spec will see two orders, and they will guess wrong on multi-item `with` for exactly the forwarding cases this ruling adds."
- **min:** "This is what the compiler does (probe2/order.bl), and `with a, b` then means exactly `with a { with b }`, with no extra rule for several items." Concern: "`tc_er_with_row` grows the row left to right today, so the impl must reverse the check direction. Without a two-item test with forwarding, that bug can come back."

##### V4 — codegen conditions in this file and the implementation ticket only, 6-0

- **sys:** "These conditions decide whether W is zero-cost… They are lowering facts, so they belong in the decision file and the impl ticket, not in sections/. The spec states only the semantics ("the handler in force for E at the `with`"), which leaves the optimisation legal." Concern: "The impl ticket can treat condition 2 as optional and keep the per-literal `blink_alloc` copy beside the new per-`with` fill. That doubles the work and keeps the stale construction-time pointer alive for a later bug to reach."
- **web:** "One C type for every R and no mono split keep compile times and binary size flat." Concern: "If the decision file is not linked from the impl ticket, the per-`with` copy can drift back to a per-literal copy, and [the forward-target ticket]'s behaviour comes back."
- **plt:** "R is a compile-time row and has no run-time meaning, so erasing it… is the correct semantics as well as the cheap one." Concern: "The "skip when E is not in R" fast path depends on R being exact for omitted primitive ops. If inference ever misses an omitted op, the binary calls an unfilled slot. The impl ticket needs a test that pins this case."
- **devops:** "R erased, with one C type for every R, also keeps `Handler[E ! R]` out of C symbol names, so linker and debugger output stays readable." Concern: "The "skip the fill when E is not in R" step must be tied to the typechecked R; if it reads a stale or approximate R (e.g. before [the handle-op capability ticket]), a forward reaches an unfilled slot and panics at run time."
- **aiml:** "The spec states only what can be seen in the program: a forward goes to the handler in force for E at the `with`." Concern: "If R is erased in codegen, a missing row check cannot be caught at run time. The typecheck tests must include the cross-fn escape probe and sys's `leak` case as error rows."
- **min:** "An erased R… keeps the row a type-checker fact with zero run-time cost, which is the cheapest result this ruling can have." Concern: ""Fill may be skipped when E is not in R" is an optimization. The impl ticket must say it is optional, so nobody treats it as a rule."

#### Phase D — Round 2 (V2 only)

The focused round covered V2 only. Each seat answered the strongest point on the other side and gave the typing rule it would write.

- **sys (ship):** "plt: "a new reading: the callee takes on a row from a value it installs, not from a value it calls." Under W (6-0), installing a handler is the point where its R is charged. For a handler value, `with h` plays the part that `f(x)` plays for a fn value. §4.15.2 says: "whatever effects the callback has, this function has too." Swap "handler" for "callback" and the sentence still holds with no other change." Concern: "The impl must resolve handler `_` and fn `_` through one union pass, or the corpus gets two rules that disagree."
- **web (ship):** "After the Phase C ruling, `Handler[DB]` means a pure handler, so `run_with(logging_db("x"))` is a type mismatch. That example is the only place where the spec teaches "a fn that takes a handler and installs it", and the most common handler a user passes it is a logging or forwarding one." Concern: "If the `_` from a handler argument goes through a different resolution path than the `_` from a callback, the two will give different E0500 text for the same mistake."
- **plt (switches to ship):** "I change my vote to ship. The strongest point on the other side is web's: under defer, the spec's own `run_with` (L2106) can take only pure handlers, or only one concrete row… I said in Phase C that `! _` on a handler parameter was "a new reading" that needs its own rule. I reread §4.15.2 and §4.15.3, and that claim does not hold." Concern: "Rule 5 (no subtraction) must be written in the spec, or an implementer will "improve" resolution by subtracting the callee's own discharges, and handler arguments and closure arguments will then disagree."
- **devops (ship):** "If we defer, the spec's two main examples do not compose, and the first user who tries them gets a type mismatch whose only fix is to copy one concrete row into `run_with`, which then rejects the pure mock." Concern: "If the impl resolves handler `_` in its own pass and not in the existing §4.15.3 call-site union, a fn that takes both a callback and a handler will report two partial rows, each one wrong. The impl must extend the one union and pin it with a corpus row that passes a closure and a handler to a single `! _` fn."
- **aiml (ship):** "In both cases the callee receives a value whose code it may cause to run, and `_` is an upper bound of what that code performs. §4.15.3 already says "`_` resolves at each call site to the concrete effects of the callback argument". The handler case replaces "the callback argument" with "the argument in a `! _` position" and changes nothing else." Concern: "Rules 2 and 5 must be one check with one message, and the corpus needs a row that passes a closure and a forwarding handler to the same `! _` callee."
- **min (switches to ship):** "I change to ship… aiml's point also decides it for me. Once `Handler[E ! R]` is grammar, `! _` is legal in every other place a row is written. Leaving it out of one place is an exception that users and models must learn. Minimalism counts exceptions as surface, so the smaller language is the one with no exception." Concern: "I adopt sys's slice order. The core W rule ships first, with `run_with` changed to form 1 in that slice. V2 lands as the next slice in the same release and restores `run_with` to the `! _` form."

V2 result: ship, 6-0. All six agreed on the shape of the typing rule. The spec text is in §4.15.2 *Handler parameters*.

### Final Spec

A handler type is `Handler[E]` or `Handler[E ! R]`. R is the clause row: the effects that the operation bodies perform outside the handler. `Handler[E]` means R is empty.

- R holds E when an operation body calls `default.op(..)`, calls through the handle of E, or leaves a primitive operation out (it forwards). A derived operation that is left out adds nothing. Calls through other effects also go in R, and they reach the handlers in force where the operation runs.
- A handler literal has an inferred R. A factory that returns a handler writes R in its declared type. The compiler offers a fix that writes the inferred `! R` into that type.
- `with h { .. }` with `h: Handler[E ! R]` needs R in the enclosing row. A missing effect is E0500 `UndeclaredEffect` at the `with` item. A note points at the `default.op` call, or at the handler head for an omitted primitive operation.
- A forward reaches the handler in force for E at the `with` that installed the handler. A handler value that leaves the block where it was built forwards to the handler in force where it is installed.
- `with a, b` means `with a { with b }`. The rightmost item is innermost. R_a is checked against the enclosing row. R_b is checked against the enclosing row plus the effects that a handles.
- `Handler[E ! _]` may appear only where `fn(..) ! _` may. Inside the callee `_` is opaque, and `with h` is charged `_`. At each call site `_` is the union of the rows of all `! _` arguments. Projection keeps R. There is no subtraction. A missing effect at the caller is E0500 at the argument.

```blink
// A forwarding factory: the row is part of the type
fn logging_db(label: Str) -> Handler[DB ! DB, IO.Log] {
    handler DB {
        fn read(query: Template[DB]) -> Result[List[Row], DBError] {
            io.log("{label}: read {query}")
            default.read(query)
        }
        // write is omitted: it forwards, so DB is in R
    }
}

// A pure handler: R is empty
fn mock_db(data: List[Row]) -> Handler[DB] {
    handler DB {
        fn read(query: Template[DB]) -> Result[List[Row], DBError] { Ok(data) }
        fn write(query: Template[DB]) -> Result[Int, DBError] { Ok(0) }
    }
}

// The error case: the handler forwards IO.Print, and deleg does not declare it
pub fn needs_print() ! IO.Print {
    io.println("x")
}

pub fn deleg() {
    let h = handler IO.Print {
        fn print(msg: Str) { default.print(msg) }
        fn print_no_nl(_msg: Str) { }
    }
    with h {            // error[UndeclaredEffect] E0500: the handler forwards IO.Print
        needs_print()
    }
}

// A handler parameter with a wildcard row
fn run_with(h: Handler[DB ! _]) ! _ {
    with h {
        do_work()
    }
}

fn test_path() {
    run_with(mock_db(rows))             // _ is empty: pure at this call site
}

fn prod_path() ! DB, IO.Log {
    run_with(logging_db("main"))        // _ = DB, IO.Log
}
```

Locked points:

- The "+E" grant on clause bodies is gone. §4.1 L11 ("a function with no `!` in its signature cannot perform side effects") is now true for handler values. No exception text exists.
- A forward goes to the handler in force for E at the `with` that installed the handler (install), not to the handler in force where the literal was evaluated.
- The row sits inside the brackets: `Handler[E ! R]`. `Handler[E] ! R` is not a handler row. R is a concrete row, or `_` in a parameter type. R is not a type parameter, and no effect variables exist.
- Pure handlers (`capture_*`, `mock_*`, `.as_handler()`) keep `Handler[E]`.
- The type system tracks the row, not the omitted operations.
- A value of type `Handler[E ! R1]` fits where `Handler[E ! R2]` is expected only if R1 is a subset of R2, as for function types. A pure handler fits any `Handler[E ! R]`.
- The spec states the forward target and does not prescribe how the compiler resolves it.

### Amendments

- Amends DECISIONS "Handler type identity" (L180): `Handler` is still one type constructor with one effect argument. The row is the only addition. It is the same row that fn types carry. It is not an effect-kinded generic parameter, so L182 (no effect-kinded generics) holds. Nobody may read this amendment as permission to add other parameters to `Handler`.
- Settles the forward-target question as install. This agrees with the text of DECISIONS L423 and L424 ("installed over") and with the E0544 help text.
- Corrects the sentence in §4.7 that said the leftmost handler wins. The text now agrees with the `with a { with b }` rule (a chore, done in this branch).
- Corrects §4.6: the check now sees a partial handler that forwards, because the `with` adds R to the row.

### Implementation notes

These notes are not spec. They carry sys's conditions (V4) for the implementation ticket. Sys's text, verbatim from B1_sys.md:

1. "**R is erased.** `Handler[E ! R1]` and `Handler[E ! R2]` have the same C type (pointer to E's root vtable) and the same layout. R never splits a mono instance, never appears in a C name (src/cname.bl), and never makes two otherwise-equal generic instances distinct. It is a check only, like the row on a fn type."
2. "**Install cost is bounded and local.** At `with h`, the compiler copies h's vtable into a frame that lives for the `with` body (stack, not `blink_alloc`), and fills each omitted primitive slot and the `default` slot from the current evidence for E. This replaces the copy that `print_handler_builder` (src/cg_print.bl:854) does today at the literal, so the literal itself gets cheaper: it no longer reads `ev_global`. A handler value used in two tasks at once is safe, because each `with` has its own copy."
3. "**A handler with no omitted primitive op and no `default` call** (R ∌ E) needs no fill at install. The compiler knows this per literal; for a value of type `Handler[E ! R]` with E ∉ R it may skip the fill. This is an optimisation, not a rule, but the spec must not forbid it."

Condition 3 is optional (min, C_min). Further conditions from the panel concerns:

- The row check and the forward-at-`with` change in `src/cg_print.bl:854` ship in one change (plt).
- The skip in condition 3 reads the typechecked R, and a test pins an omitted primitive op (plt, devops).
- `tc_er_with_row` grows the row left to right today. Reverse the check direction to follow `with a { with b }`, and add a two-item forwarding test (min).
- The E0500 note names the `with` items it checked (devops). The fix-it writes the inferred `! R` into the declared type (web, aiml). The parser gives a targeted help for `Handler[E] ! R` (web, devops).
- One code path resolves `_` for handlers and for closures. A corpus row passes a closure and a forwarding handler to one `! _` fn (devops, aiml).
- V2 may land as a separate slice in the same release (sys, min).
- Typecheck error rows: plt's escape probe (`sandbox(h)` with an empty row) and sys's `leak` case (aiml).
- The formatter and the LSP print the inferred row as `Handler[E ! R]` (min).
- The implementation ticket links to this file, so the per-`with` copy cannot drift back to a per-literal copy (web).

### Open cases and follow-ups

- Handle-op capability check: the built-in handle operations must be mapped first. Without the map, `io.log` in a clause adds nothing to R, and the check is only half enforced. The row check depends on it.
- `capture_*` helpers in `lib/std/testing.bl` write module-level state (`let mut`). Under this rule their R holds `State`, so they must move to captured cells before the check turns on.
- With-order text fix (L1891 "leftmost wins"): done in this branch. Older decision files (`mocking-helpers-beyond-io.md`, `arena-expression-form-semantics.md`) keep the old wording as history.
- Return-type `!` ambiguity for function types (04_effects.md L607 and L787): stays open. `Handler[E ! R]` avoids it.
- Raw output ops: with install-time forwarding and R in the type, an omitted `print_raw_bytes` puts `IO.Print` in R. This closes the hole in the `_raw` dispatch ruling (devops).
- Helper factories that the spec names but does not define (`scoped_fs`, `readonly_fs`, `frozen_time`, `sqlite_handler`) have no row in the spec text. Their bodies are not shown, so each takes the row of its clauses when someone writes it.
