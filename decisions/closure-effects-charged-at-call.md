[< All Decisions](../DECISIONS.md)

# A Closure Is Charged at Its Call — Design Rationale

**Gap:** §4.6 says the `UnhandledEffect` (E0539) check at a root "uses the effect rows of the program (§4.5, §4.15), closures and `! _` rows included". It did not say where a closure's row is charged. §4.7 says a closure that runs after an operation has returned performs its effects "with the handlers in force where it is called". The compiler charged the row where the closure is written. This program got E0539 at the closure, but at run time each call finds the handler and prints 15:

```blink
effect Counter {
    effect Inc { fn inc(n: Int) -> Int }
}
fn main() {
    let f = fn(x: Int) -> Int { counter.inc(x) }
    with handler Counter {
        fn inc(n: Int) -> Int { n + 10 }
    } {
        io.println("{f(5)}")
    }
}
```

## Summary

| Q | Question | Result | Vote |
|---|---|---|---|
| Q1 | Where E0539 charges a closure's row | `Call`: where the closure is called, or passed to a `! _` parameter; never where it is written, and not at both places | 6-0 |
| Q2 | A closure whose call the check cannot see | `Typed`: the row travels on the closure's type, so each call of the value is charged where it happens; no call is hidden | 6-0 |
| Q3 | E0500 in a fn that is not a root | `Same`: the same rule holds for E0500 in every fn. Writing a closure charges the enclosing fn nothing | 6-0 |

Phase B was skipped: all six Phase A proposals gave one behavior. Phase D was not triggered.

Writer notes from Phase A.5 and Phase C:

- The spec gets an example and the shortest statement. It does not restate §4.15.3 (Minimalism).
- The E0539 diagnostic names the closure binding and the line of the operation (Web/Scripting, DevOps, AI/ML).
- `EffectMismatchInFnType` (§4.15.1) governs a pure slot. This is a fact of the spec, not a vote.

## Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in independent-proposal and vote rounds. Each panelist's text below is a verbatim copy of the panelist's own reply. A ticket ID or a scratch file path in the copy is replaced by `[ticket]` or `[scratch path]`.

### Phase A — Independent proposals

- **Systems:**

> ## Sys seat — Phase A, [ticket]
>
> **Position: charge a closure's row where the closure runs (a call, or a forward through `_`), never where it is written.** Q2 needs no new mechanism: the row is part of the closure's type, so every path that can run it hits a charged site the checker already sees.
>
> ### What the hardware sees
>
> A closure literal is an env allocation plus a code pointer. No handler lookup happens there. The handler is found at the op call, dynamically, from the handlers in force at that moment (§4.7 l.4379; probes on `build/blink` 0.60.0-dev confirm: the ticket program prints 15). Charging at the write site checks a thing the machine never does. A static check that does not match the dynamic semantics is wrong in both directions:
>
> Probes (in [scratch path]):
> - `a.bl` (ticket program): E0539 at 5:33, runs and prints 15. **False positive.**
> - `e.bl`: closure made, never called — still E0539. A value that never runs cannot perform an effect.
> - `c.bl` — the reverse, and worse. **Compiler accepts it, and it prints `0` instead of panicking:**
>
> ```blink
> fn main() {
>     let mut h = fn(x: Int) -> Int { x }
>     with handler Counter {
>         fn inc(n: Int) -> Int { n + 10 }
>     } {
>         h = fn(x: Int) -> Int { counter.inc(x) }   // written under the handler
>         io.println("{h(1)}")                       // 11
>     }
>     io.println("{h(5)}")                           // check: ok. run: prints 0
> }
> ```
>
> So write-site charging is unsound, not just strict. (The `0` is also a separate runtime bug: decision "Unhandled effect operation" says panic. Should be filed as `type:bug` regardless of this vote.)
>
> ### Proposal S1 — charge at run sites only
>
> **Q0: yes.** One added point: making a closure charges nothing; running it, or passing it to a `! _` parameter, charges its row. Without this, "closures included" reads either way, and the compiler picked the wrong way.
>
> **Q1: where it is called.** Not "both": the write-site half is exactly the false positive.
>
> **Q2: nothing new.** The closure's type carries its row (§4.15.1), so each escape already has a charge:
>
> ```blink
> effect Counter {
>     effect Inc { fn inc(n: Int) -> Int }
> }
>
> // 1. Ticket program — compiles, prints 15
> fn main() {
>     let f = fn(x: Int) -> Int { counter.inc(x) }   // f: fn(Int) -> Int ! Counter.Inc, no charge
>     with handler Counter { fn inc(n: Int) -> Int { n + 10 } } {
>         io.println("{f(5)}")                       // charged here, discharged by the with
>     }
> }
>
> // 2. Passed to a function — `! _` charges the caller at the argument (rule 5)
> fn apply(f: fn(Int) -> Int ! _) -> Int ! _ {
>     f(1)
> }
> fn main() {
>     let f = fn(x: Int) -> Int { counter.inc(x) }
>     io.println("{apply(f)}")        // E0539 here: the argument row is the call's row
> }
> // Concrete-row param: fn apply2(f: fn(Int) -> Int ! Counter) -> Int ! Counter
> // is charged at the call of apply2. A pure param type rejects f: type mismatch, not a hole.
>
> // 3. Returned / stored, called outside any with
> fn make() -> (fn(Int) -> Int ! Counter) {
>     fn(x: Int) -> Int { counter.inc(x) }   // make's own row is pure
> }
> fn main() {
>     let g = make()                 // OK: just a value
>     let fs: List[fn(Int) -> Int ! Counter] = [g]
>     io.println("{g(1)}")           // E0539 here
>     io.println("{fs[0](1)}")       // E0539 here
> }
>
> // 4. Written inside with, called outside (c.bl):
> //    h = fn ... line: OK.   io.println("{h(5)}") outside the with: E0539.
> //    h(1) inside the with: discharged, prints 11.
> ```
>
> The row cannot get lost: the only way to put a `! Counter` closure into a place with a smaller row is a type error the checker already reports. `async.spawn` stays as decided (§4.13): it takes `! _`, so the caller is charged at the spawn site.
>
> This matches §4.16 for `State` exactly ("the enclosing function gets `State` only when it calls the closure, or passes it to a callee whose row forwards it with `_`"). S1 makes user effects follow the same rule. Two different charge rules for two effect kinds would be a trap.
>
> ### Tradeoffs
>
> - **Runtime cost:** zero either way; this is a static check. S1 keeps codegen free to use dynamic handler lookup with no evidence capture at closure creation.
> - **Compile-time cost:** small. The checker already carries rows on fn types for `_` and §4.15.3; S1 moves the charge from the literal node to the call node (a call of a fn-typed value already reads the callee type).
> - **Predictability:** the error points at the line that runs the op, the same line that panics at run time. Today's error points at a literal that may never run.
> - **Risk:** S1 is only correct if closure types in params/returns/fields carry rows the checker sees. See the facts below.
>
> ### Compiler facts for the moderator (not for vote)
>
> 1. `fn apply(f: fn(Int) -> Int ! Counter) -> Int ! Counter` does not parse on `build/blink` ("expected ), got !"); same with `! _`. The compiler cannot yet express the shape §4.15.2 specifies for user code, which likely explains why it charges at the write site.
> 2. `fn make() -> fn(Int) -> Int ! Counter` binds `! Counter` to `make`, so `let g = make()` gets E0539 (`d.bl`). The spec should state the grammar for a row on a returned fn type (parens as I wrote above?). Grammar question, not this ticket.
> 3. `c.bl`: clean check, and an unhandled op returns 0 at run time instead of panicking. P0-class bug.
>
> ### Cross-language
>
> Koka, Eff, OCaml 5: a closure's effects live in its function type and are handled where it is applied, dynamically; none charges at creation. Koka's `() -> <counter> int` puts the obligation on whoever applies the value. Rust's `async` blocks are the closest systems analogue: making the future costs nothing; `.await` is where the cost and context requirements show. S1 is that model.
>
> ### Vote intent
>
> S1. Against "both" and against "written" (unsound per `c.bl`). Against "do nothing" (Q0 needs the one point).

- **Web/Scripting:**

> I propose charging a closure's effects where it is called. I could not test my own examples because the compiler can't parse effect rows on function types yet (finding 1 below).
>
> # Web seat: Phase A proposal ([ticket])
>
> ## What I found on main (`build/blink` 0.60.0-dev)
>
> Probe files are in `[scratch path]`.
>
> 1. **The parser does not accept a row on a function type.** `fn apply(f: fn(Int) -> Int ! _, x: Int)` gives UnexpectedToken at the `!`. The §4.15.1 example has the same shape. Because of this, `apply_int(f: fn(Int) -> Int, ...)` in `tests/test_ev_closures_effects.bl` accepts an effectful closure today. The compiler can only charge a closure where it is written, because a closure's type has no row to carry the effect anywhere else.
> 2. **Charging where the closure is written gives wrong answers in both directions:**
>    - **Error on a program that works.** The ticket program gets E0539 at 5:33, but it runs and prints 15.
>    - **No error on a program that is wrong.** `b.bl` builds a closure inside a `with` and calls it outside. `blink check` says `ok`. At run time it prints **`0`** with exit code 0. It should panic, as the "Unhandled effect operation" decision requires. So the check misses the bad call, and the runtime gives a silent wrong answer.
> 3. In a function that is not a root (`fn noeff() { let f = fn(..) { counter.inc(x) } }`), writing the closure alone gives UndeclaredEffect. That is not consistent with §4.16, where a closure that touches State charges its enclosing function only when that function calls it.
>
> The write-site rule is a compiler shortcut, not a choice anyone made. A JS or Python developer gets a red squiggle on a line that runs fine, and no squiggle on a line that misbehaves. That would generate many Stack Overflow questions.
>
> ## Proposal W1: charge where the closure is called, and carry the row on the closure's type
>
> **Q0: yes.** The check must say where a closure is charged. Today each reader guesses differently, and the compiler guessed wrong.
>
> **Q1: where it is called. Never where it is written, and not both.** Making a closure only makes a value (§2.20). Its body runs at each call, with the handlers in force at that call (§4.7). The check should follow the run-time behavior. This is the same rule §4.16 already uses for State, so programmers learn one rule for every effect.
>
> **Q2: there is no call the check cannot see.** The row is part of the closure's type (§4.15.1), so it goes everywhere the value goes. Whoever calls the value, or passes it to a `! _` callee, is charged. The existing rules cover each case:
>
> - **Passed to a function.** The parameter type must hold the row, either as a concrete row or as `_`. With `! _`, rule 5 charges the caller of the higher-order function at that call. A concrete row such as `! Counter` makes the callee's own row need `Counter` (§4.15.3), so the effect reaches its caller. A pure parameter type `fn(Int) -> Int` rejects an effectful closure with a type mismatch, as §4.15.1 already says ("without `!` is pure").
> - **Stored or returned.** The field type or return type carries the row. Each call of the stored value is charged where it happens.
>
> ### Examples
>
> ```blink
> effect Counter {
>     effect Inc { fn inc(n: Int) -> Int }
> }
> ```
>
> **1. The ticket program compiles and prints 15.**
>
> ```blink
> fn main() {
>     let f = fn(x: Int) -> Int { counter.inc(x) }   // a value, so nothing is charged here
>     with handler Counter {
>         fn inc(n: Int) -> Int { n + 10 }
>     } {
>         io.println("{f(5)}")                       // charged here, inside the handler
>     }
> }
> ```
>
> **2. Passed to a function.**
>
> ```blink
> fn apply(f: fn(Int) -> Int ! _, x: Int) -> Int ! _ {
>     f(x)
> }
> fn apply_pure(f: fn(Int) -> Int, x: Int) -> Int {
>     f(x)
> }
> fn main() {
>     let f = fn(x: Int) -> Int { counter.inc(x) }
>     with handler Counter {
>         fn inc(n: Int) -> Int { n + 10 }
>     } {
>         io.println("{apply(f, 1)}")        // OK: _ = Counter.Inc, and the handler is in force. Prints 11
>     }
>     io.println("{apply(f, 1)}")            // E0539 at this line: `apply` requires `! Counter.Inc` through `_`
>     io.println("{apply_pure(f, 1)}")       // E0500 / type mismatch: an effectful closure where a pure fn is expected
> }
> ```
>
> **3. Returned, then called outside a `with`.**
>
> ```blink
> fn make() -> (fn(Int) -> Int ! Counter.Inc) {
>     fn(x: Int) -> Int { counter.inc(x) }   // OK: `make` only returns the closure, it does not call it
> }
> fn main() {
>     let g = make()                         // OK: no charge for making the value
>     io.println("{g(5)}")                   // E0539 at this line
> }
> ```
>
> **4. Written inside a `with`, called outside it.** This is the `b.bl` case, which prints 0 today.
>
> ```blink
> fn main() {
>     let f = with handler Counter {
>         fn inc(n: Int) -> Int { n + 10 }
>     } {
>         fn(x: Int) -> Int { counter.inc(x) }
>     }
>     io.println("{f(5)}")                   // E0539 at this line. Without the check, the call panics
> }
> ```
>
> **5. Stored in a struct.** Each call of `j.run` is charged where it happens, the same as example 3.
>
> ```blink
> type Job { run: fn(Int) -> Int ! Counter.Inc }
> ```
>
> ### What the diagnostic should show
>
> Point at the call, and add a note that names where the closure was written:
>
> ```
> error[UnhandledEffect]: unhandled effect `Counter.Inc` in `main`
>   --> app.bl:7:18
>    |
>  7 |     io.println("{f(5)}")
>    |                  ^^^^ calling `f` requires `! Counter.Inc`
>    = note: `f` is the closure at app.bl:5:13
> ```
>
> A developer then sees both the cause (the closure) and the place to put the fix (the call).
>
> ## Tradeoffs from the Web seat
>
> - **For:** the check matches the run-time behavior. A program that runs compiles, and a program that would panic gets an error. JS and Python developers already think of a callback as code that runs later: "creating a callback doesn't call it." Kotlin developers know this rule exactly: you can make a `suspend` lambda anywhere, but you can only call it from a suspend context.
> - **Cost:** programmers must write rows on callback parameter types (`fn(Int) -> Int ! _`), and `apply_int` in the existing test becomes an error. That is correct, and it is the 90% higher-order-function case that `! _` was designed for. The diagnostic for passing an effectful closure to a pure parameter must suggest `! _` as a fix.
> - **Rejected: both places.** It keeps the false positive on the ticket program and adds nothing over the call site.
> - **Rejected: where it is written.** Finding 2 shows it is wrong in both directions.
>
> ## Other languages
>
> - **Koka and Eff:** a lambda's effect is in its type, making a lambda is total, and the caller is charged. W1 is the same rule.
> - **Kotlin:** the `suspend` rule described above, the same rule again.
> - **OCaml 5:** no static check. An operation with no handler raises `Unhandled` at run time. That is our fallback, but only for code the check does not cover.
>
> ## For the moderator, not to vote on
>
> - The prerequisite is parsing and checking rows on function types (finding 1). Without them, W1 cannot be built.
> - Finding 2 (the escaped closure prints `0` instead of panicking) is a separate run-time bug. It needs a `type:bug` ticket whatever the panel decides.

- **PLT:**

> **PLT seat (plt): Phase A proposal for [ticket]**
>
> **Recommendation: P1, charge a closure where it is called. Q0 = yes, the check needs one more statement. Q1 = where it is called. Q2 = the effect row is part of the closure's type, so every call can be seen.**
>
> ### Typing rules (P1)
>
> E0539 uses the same row rules as E0500 and the `State` rule:
>
> - **Writing a closure charges nothing.** `fn(x) { e }` gets the type `fn(T) -> U ! ε`, where ε is the row of `e`. The enclosing scope pays nothing. §2.20 says "making it does not run its body". §4.15.1 `with_logging` is pure but returns an `IO.Log` closure. §4.16 charges `State` only on a call.
> - **A call is charged** the row of the callee's type, plus the rows of its arguments.
> - **A pass to a `! _` parameter** is charged at that call (§4.15.2 rules 3 and 5).
> - **A pass to a parameter with a fixed row** (`fn() -> () ! Counter`): the callee declares `! Counter` (§4.15.3), and the caller pays it at the call of the callee.
> - **No coercion from an effectful function type to a pure one.** If an effectful closure goes into a pure-typed place (parameter, `let mut` slot, field, list element), that is E0500 at that place. P1 is sound only with this rule.
>
> The root check then reads `main`'s (or a test's) row as computed above. E0539 fires when a user effect reaches it outside a `with` that discharges it.
>
> ### Examples
>
> ```blink
> // Ticket program: compiles, prints 15
> let f = fn(x: Int) -> Int { counter.inc(x) }   // no charge here
> with handler Counter { fn inc(n: Int) -> Int { n + 10 } } {
>     io.println("{f(5)}")                        // Counter charged here, discharged
> }
> ```
>
> ```blink
> // Passed to a function
> let f = fn(x: Int) -> Int { counter.inc(x) }
> with handler Counter { ... } {
>     let xs = [1, 2].map(f)    // map takes `! _`: Counter charged here, discharged. OK
> }
> let ys = [1, 2].map(f)        // E0539 at `[1, 2].map(f)`
>
> fn apply(g: fn(Int) -> Int, x: Int) -> Int { g(x) }
> apply(fn(x: Int) -> Int { counter.inc(x) }, 1)  // E0500 at the argument: effectful into a pure type
> ```
>
> ```blink
> // Stored or returned, called outside the `with`
> fn make() -> (fn(Int) -> Int ! Counter) {       // make is pure
>     fn(x: Int) -> Int { counter.inc(x) }
> }
> fn main() {
>     let f = make()                              // no charge
>     io.println("{f(1)}")                        // E0539 here
> }
> ```
>
> ```blink
> // Written inside a `with`, called outside it
> fn main() {
>     let mut g = fn(x: Int) -> Int ! Counter { x }
>     with handler Counter { fn inc(n: Int) -> Int { n + 10 } } {
>         g = fn(x: Int) -> Int { counter.inc(x) }
>         io.println("inside {g(1)}")             // OK, prints "inside 11"
>     }
>     io.println("outside {g(1)}")                // E0539 here
> }
> ```
>
> If `g` were declared pure (`fn(x: Int) -> Int { x }` with no row), the assignment inside the `with` would be E0500 instead.
>
> **Q2:** there is no call the check cannot see. The row goes wherever the value goes: in a field type, a list element type, a return type, or a `! _` union. A closure that nobody calls is never charged. That is sound, because its body never runs.
>
> ### Alternatives I reject
>
> - **P3, charge where written (what main does now): neither sound nor complete.**
>   - Not complete: it rejects the ticket program, which runs and prints 15.
>   - Not sound: a closure written inside a `with` and called outside it passes the check.
>   - I measured this with `build/gen1/bin/blink` on probe `i.bl` (the last example, with a pure `g`). `check` says **ok**, and the run prints `outside 0`. There is no panic and the value is wrong. This breaks the decided rule "an op with no handler panics". It is a run-time bug on its own, apart from this panel's question.
> - **P2, charge both where written and where called:** the charge where written adds no soundness, because the call already pays. It only rejects correct programs, such as a closure factory in `main` with the handler installed later. It is never more sound than P1.
>
> ### Tradeoffs from the PLT view
>
> - P1 is the standard type-and-effect rule (Talpin–Jouvelot; Koka). Making a lambda is pure, and the latent effect is paid when the function is applied. It composes: E0500, `State`, `! _` and E0539 all use one rule, with no special case for roots.
> - §4.7 puts handlers in force dynamically ("in force where it is called"). Only charging at the call matches that.
> - Cost: P1 depends on effect rows being sound in the types (no coercion from effectful to pure). The compiler breaks this today (findings 2 and 3 below). So P1 is the spec answer plus at least two compiler bugs to fix.
>
> ### Cross-language
>
> - **Koka:** a closure that escapes its handler keeps `<counter>` in its arrow type. Calling it outside the handler is a type error. This is P1.
> - **Frank and Eff:** effects are checked at application. The same idea.
> - **Effekt:** handlers are lexical capabilities, so a closure is checked where it is written. That needs capture tracking and lexical handler semantics, which contradict Blink's §4.7. Not a fit.
> - **OCaml 5:** effects are untyped, and an unhandled one raises `Effect.Unhandled` at run time. This is Blink's run-time panic, without the static check.
>
> ### Compiler findings for the moderator (not for the vote)
>
> 1. The compiler charges the closure where it is written in every function, not only at roots. In `fn make_unused() { let f = fn(x: Int) -> Int { counter.inc(x) } }`, it reports UndeclaredEffect on the closure body. This goes against the §4.15.1 `with_logging` example. The fix belongs in how the compiler builds rows in general, not only in E0539.
> 2. A pure parameter type accepts an effectful closure. In probe `h.bl`, `apply(fn(x: Int) -> Int { counter.inc(x) }, 1)` checks **ok**.
> 3. A closure that runs with no handler printed `0` instead of panicking (probe `i.bl`). This is a P0-class run-time bug.
> 4. The gen1 parser rejects the parenthesised fn return type `-> (fn(Int) -> Int ! Counter)` and `! _` on a user fn-type parameter. My probes used other forms because of this.
>
> All probes are in `[scratch path]`.

- **DevOps:**

> **Seat: DevOps/Tooling. Phase A proposal for ticket [ticket]**
>
> **What I found in the probes** (`build/blink` 0.60.0-dev; gen1 was missing, so I used the newer build/ binary. Probes are in `[scratch path]`):
>
> 1. **Ticket program (p1):** E0539 at 5:33, the `counter.inc` inside the closure body. At run time it prints 15.
> 2. **Closure that is never called (p6):** E0539 at the closure body. No operation ever runs.
> 3. **Closure written inside a `with` and called outside it (p5):** `ok`, with no error. When run, `f(5)` prints **`0`**. That is neither 15 nor the panic the decision requires: the program quietly returns a wrong value. The current write-site rule rejects the correct program and accepts the broken one.
> 4. **Same shape in a non-root fn (p2):** E0500 at the closure body. The E0539/E0500 explain text says "a closure holds the effects of the function around it", which is the write-site rule.
> 5. **Rows on fn types do not parse.** `fn(Int) -> Int ! _` in a parameter, `let f: fn(Int) -> Int ! Counter`, and `-> (fn(Int) -> Int ! Counter)` all give `UnexpectedToken: expected ), got !`. §4.15.1 is not in the parser. The unparenthesized form `fn make() -> fn(Int) -> Int ! Counter` parses with the row on `make`, so `let f = make()` gets E0539. The return type has no syntax today.
>
> ---
>
> **Proposal D1: a closure's row is part of its type, and each call charges it (Q0 yes, Q1 call site, Q2 the type carries the row)**
>
> Behavior:
> - Writing a closure charges nothing. Its inferred row goes into its type, as §2.20 says ("making it does not run its body").
> - A call `f(x)` charges `f`'s row at that call. E0539 checks the handlers in force at the call, which matches §4.7's run-time rule.
> - Passing a closure to a `! _` parameter charges its full row at the argument (§4.15.2 rules 5 and 6, unchanged).
> - Passing it to a concrete `fn(..) ! E` parameter, storing it in a field or list, or returning it needs the slot type to hold the row. A pure slot is a type mismatch at the store site, not E0539.
> - So Q2 has no "call the check cannot see". Every call is a call of a value whose type holds the row.
>
> Examples:
>
> ```blink
> fn main() {
>     let f = fn(x: Int) -> Int { counter.inc(x) }
>     with handler Counter { fn inc(n: Int) -> Int { n + 10 } } {
>         io.println("{f(5)}")      // OK, prints 15
>     }
> }
> ```
>
> ```blink
> fn apply(x: Int, g: fn(Int) -> Int ! _) -> Int ! _ { g(x) }
> fn main() {
>     let f = fn(x: Int) -> Int { counter.inc(x) }
>     io.println("{apply(5, f)}")   // E0539 at the argument `f`
> }
> ```
>
> ```
> error[UnhandledEffect]: unhandled effect `Counter.Inc` in `main`
>   --> app.bl:7:27
>   |
> 7 |     io.println("{apply(5, f)}")
>   |                           ^ `f` performs `Counter.inc` (5:33); `apply` forwards it with `_`
>   help: user-declared effects have no root handler; wrap the call in `with <handler> { ... }` (§4.12)
> ```
>
> ```blink
> fn make() -> (fn(Int) -> Int ! Counter) {   // needs the paren form to parse
>     fn(x: Int) -> Int { counter.inc(x) }     // make is pure
> }
> fn main() {
>     let f = make()                           // OK, no charge
>     io.println("{f(5)}")                     // E0539 here
> }
> ```
>
> ```blink
> fn main() {
>     let f = with handler Counter { fn inc(n: Int) -> Int { n + 10 } } {
>         fn(x: Int) -> Int { counter.inc(x) }
>     }
>     io.println("{f(5)}")          // E0539 at 7:18
> }
> ```
>
> ```
> error[UnhandledEffect]: unhandled effect `Counter.Inc` in `main`
>   --> app.bl:7:18
>   |
> 7 |     io.println("{f(5)}")
>   |                  ^^^^ call of `f` needs `! Counter.Inc`
>   |
> 4 |         fn(x: Int) -> Int { counter.inc(x) }
>   |                             ----------- `f` performs it here; the `with` at 2:13 ended before this call
>   help: a closure uses the handlers in force where it is called (§4.7), not where it is written
> ```
>
> In this last case the error replaces today's silent `0`.
>
> - **A closure that is never called (p6):** no E0539. W-UnusedVariable already fires.
> - **One rule for the non-root case (p2):** the E0500 case must follow the same rule. If it does not, moving code out of `main` into a helper changes the verdict. The E0539/E0500 explain texts must be rewritten too.
>
> Tooling tradeoffs:
> - **Error position:** the span lands where the handler is missing (the call), and a secondary label points at the operation. That is the line the user must change: they put the `with` around the call. Today's span points at the closure body, where no `with` can help.
> - **LSP:** hover on `f` must show the inferred `fn(Int) -> Int ! Counter.Inc`. The data comes from the same inference, so it costs nothing new. Without it, a call-site error at `f(5)` is opaque. The `main` row inlay hint (§4.6) stays the same.
> - **Cost:** returned or stored closures need §4.15.1 row syntax in the parser, and that is missing today (see probe 5). The `fn make() -> fn(..) -> T ! E` binding is ambiguous: today the row goes to `make`. The writer must settle the paren form, and the error must name it ("did you mean `-> (fn(Int) -> Int ! Counter)`?").
> - **`blink fmt`:** keeps `(fn(..) ! E)` parens in return position.
>
> ---
>
> **Proposal D2 (rejected): charge both where the closure is written and where it is called**
>
> This rejects the ticket program and the test `"closure called from different handler scopes"`, and it gains nothing over D1. The error points at code the user cannot fix with a `with`.
>
> **Proposal D3 (rejected): keep the write-site rule (do nothing)**
>
> The probes show it is wrong in both directions. It rejects p1, which works, and accepts p5, which returns garbage. It also contradicts §4.7 and §2.20.
>
> **Cross-language:** typed-effect languages charge the effect where the function is called:
> - Koka puts the effect in the function type (`(int) -> counter int`). Making the lambda is total; calling it needs the handler.
> - Unison does the same with `Nat ->{Counter} Nat`.
> - OCaml 5 has untyped effects and raises `Unhandled` at the perform. That is our run-time panic.
> - Effekt binds handlers lexically, which is the write-site model. Blink's §4.7 is dynamic, so Effekt's rule does not fit.
>
> **Side findings for the moderator** (outside this question, needs tickets): (a) p5 returns `0` instead of panicking. This is a P0-class bug against the "Unhandled effect operation" decision. (b) §4.15.1 rows on fn types do not parse.
>
> **Vote: D1**, with E0500 under the same rule and the explain text updated.

- **AI/ML:**

> **Seat: AI/ML (aiml). Phase A proposal for [ticket]**
>
> ## Proposal A (recommended): charge the row where the closure is called, using its type
>
> **Rule as behavior.** Making a closure value charges nothing. The closure's row stays on its type (`fn(Int) -> Int ! Counter.Inc`). Each call of a value whose type carries row R charges R at that call, under the handlers that enclose that call. If the value goes to a `! _` callee, the row is charged at that call (§4.15.2 rule 5). If it goes to a concrete-row parameter, the callee must declare the row, and its caller is charged at the call to that callee. The rule is the one §4.16 already gives for `State`. A learner, human or model, learns one rule for both.
>
> **Q0:** Yes. One clause: "a closure's row is charged where it is called, or where it is passed to a `! _` callee, never where it is written."
> **Q1:** At the call site only.
> **Q2:** No call is ever out of sight. The row travels on the type. A call the check cannot see is inside a function, and that function's signature must declare the row or `_`. That pushes the charge back up to a call the root can see.
>
> ```blink
> // 1. Ticket program: compiles, prints 15
> fn main() {
>     let f = fn(x: Int) -> Int { counter.inc(x) }    // no charge here
>     with handler Counter { fn inc(n: Int) -> Int { n + 10 } } {
>         io.println("{f(5)}")                          // charged here; handled
>     }
> }
> ```
>
> ```blink
> // 2. Passed to a function
> fn apply(v: Int, f: fn(Int) -> Int ! _) -> Int ! _ { f(v) }
> fn twice(f: fn(Int) -> Int ! Counter.Inc) -> Int ! Counter.Inc { f(f(1)) }
> fn main() {
>     let h = fn(x: Int) -> Int { counter.inc(x) }
>     io.println("{apply(1, h)}")          // line 5: E0539, the `_` call is charged Counter.Inc
>     with handler Counter { fn inc(n: Int) -> Int { n + 10 } } {
>         io.println("{apply(1, h)} {twice(h)}")   // ok: prints "11 21"
>     }
> }
> ```
>
> ```blink
> // 3. Returned and stored, called outside any `with`
> fn make() -> fn(Int) -> Int ! Counter.Inc {
>     fn(x: Int) -> Int { counter.inc(x) }   // make's own row is empty: it does not call it
> }
> fn main() {
>     let f = make()
>     let fs = [f]
>     io.println("{fs[0](5)}")              // line 7: E0539 at the call
> }
> ```
>
> ```blink
> // 4. Written inside a `with`, called outside it
> fn main() {
>     let f = with handler Counter { fn inc(n: Int) -> Int { n + 10 } } {
>         fn(x: Int) -> Int { counter.inc(x) }   // no charge, so no false "handled"
>     }
>     io.println("{f(5)}")                  // line 5: E0539
> }
> ```
>
> **Tradeoffs (my domain):**
> - **Write-site charging gives the wrong answer both ways.** In example 1 it rejects a program that runs correctly. In example 4 it accepts a program that fails at run time. I probed this on main. `build/blink` 0.60.0-dev accepts example 4 (`ok: c.bl`), and the inner-`with` reassignment version is accepted too (`a.bl`). A model that reads the spec (§4.7 "handlers in force where it is called", §2.20 "the body runs at each call") will predict call-site behavior. With write-site charging, the spec teaches one model and the compiler enforces another. That is the worst case for training data.
> - **Fewer decision points.** There is one rule for `State`, for user effects and for spawn (§4.13 already says the closure row is part of the caller's row). The model does not need a special case for "closures at roots".
> - **Token cost.** The common pattern (example 1) needs no annotation. Returned closures (example 3) need `! Counter.Inc` on the return type. The language already asks for that on every public signature, so there is no new cost.
> - **Debuggability.** The error points at the call that will fail at run time, not at the literal. The fix ("wrap this call in `with`") goes at the line the diagnostic names.
>
> **Cross-language.** In Koka, Eff and Frank, a lambda's effect is latent on its arrow type and is discharged where it is applied. Making a lambda is pure (`fun` is total). OCaml 5 has no static rows, but it handles at perform time with the dynamic handler stack, which is call-site semantics. Unison abilities work the same way: `'{Ability} a` is charged when forced. Write-site charging has no precedent I know of.
>
> ## Proposal B (rejected): charge where written, or at both places
>
> "Both" keeps the false positive of example 1 and adds nothing. A call-site check already covers every run-time failure that a write-site check would catch. "Write only" is unsound (example 4). I list B only so the panel can reject it on the record.
>
> ## Findings for the moderator, outside the vote
>
> 1. **Run-time bug, P0 candidate.** On main, `a.bl` and `c.bl` (example 4 shape) compile and run. The call outside the `with` prints `0` and does not panic. That breaks the decided rule "an operation that finds no handler panics". The op seems to return a zero value. Probe files are in [scratch path]
> 2. **The parser rejects user-written `! _` in a parameter's function type.** `fn apply(v: Int, f: fn(Int) -> Int ! _) -> Int ! _` gives "expected ), got !" (b.bl). Example 2 cannot be checked on main yet. Also, tests such as tests/test_fn_value_as_arg.bl:47 pass effectful closures to a parameter typed as pure `fn(Int) -> Int`. That suggests main does not check rows on function-typed parameters. Proposal A needs that check, so the panel should know the compiler is behind the spec here.

- **Minimalism:**

> **Minimalism seat (min): Phase A proposal for [ticket]**
>
> **Recommendation: P1. Change no rule. The existing rules already say "charged where called". The compiler on main is wrong, so this is a `type:bug`. Add the ticket program to §4.6 as an example.**
>
> ### Why no new rule is needed (Q0)
>
> Four existing rules already settle it:
>
> 1. §4.15.1: a closure value's type carries its row. `fn(x: Int) -> Int { counter.inc(x) }` has type `fn(Int) -> Int ! Counter.Inc`.
> 2. §2.20: making a closure literal does not run its body.
> 3. §4.15.3: the caller must hold a closure's row at the call. §4.15.2 rule 5: a call to a `! _` callee charges the row of each closure argument at that call.
> 4. §4.6: E0539 "uses the effect rows of the program, closures … included". These rows are the ones in rules 1 and 3.
>
> So the row is charged when the closure is called, or when it is passed to a `_` callee. Two other rules already work this way:
> - §4.16 *Closures*: the enclosing fn gets `State` only when it calls the closure or passes it to a `_` callee.
> - §4.7 ~4379: a closure uses the handlers in force where it is called.
>
> A separate "closure rule" for E0539 would be a third statement of one idea. Answer to Q0: no new rule. Add one example only.
>
> ### Q1: charged where called, not where written, not both
>
> Probes are under `[scratch path]`, checked with `build/blink` (`build/gen1/bin` is not present).
>
> **Ticket program (`a.bl`).**
> - Main today: E0539 at 5:33.
> - P1: compiles, prints `15`.
> - The call at line 9 is inside the `with`, so nothing is unhandled.
>
> **Closure written in a `with`, called outside it (`g.bl`).**
> ```blink
> fn main() {
>     let f = with handler Counter {
>         fn inc(n: Int) -> Int { n + 10 }
>     } {
>         fn(x: Int) -> Int { counter.inc(x) }
>     }
>     io.println("{f(5)}")
> }
> ```
> - Main today: `ok: g.bl`, and `blink run` prints `0`.
> - P1: E0539 at line 10 (`f(5)`): `f` requires `! Counter.Inc`.
> - So write-site charging fails both ways. It rejects the ticket program, which is correct, and it accepts this program, which has no handler at the call.
> - Also, printing `0` is a second bug. The decided behavior is a panic when an operation finds no handler, not a wrong value. That needs its own `type:bug` ticket.
>
> **A never-called closure (`d.bl`).**
> ```blink
> fn main() {
>     let f = fn(x: Int) -> Int { counter.inc(x) }
> }
> ```
> - P1: no E0539, because nothing runs. W-unused-variable still fires.
> - Main today: E0539, which is a false positive.
>
> **Why not "both".** "Both" keeps the ticket program's false positive and adds nothing: the call-site check already catches every unhandled run. It is two checks where one is enough.
>
> ### Q2: the call site is never hidden
>
> The row is part of the closure's type, and subtyping only lets a smaller row go into a larger one. Every way a closure leaves its scope keeps the row in a type that the next caller sees.
>
> **Passed to a function with a concrete row.**
> ```blink
> fn apply(g: fn(Int) -> Int ! Counter.Inc, v: Int) -> Int ! Counter.Inc {
>     g(v)
> }
> fn main() {
>     let f = fn(x: Int) -> Int { counter.inc(x) }
>     io.println("{apply(f, 5)}")   // E0539 here: apply requires ! Counter.Inc
> }
> ```
> - If `apply` leaves out `! Counter.Inc`, E0500 fires at `g(v)`.
> - If the call `apply(f, 5)` is in a `with handler Counter`, it compiles and prints `15`.
>
> **Passed to a `! _` callee.** The row is charged at the call of the callee (rule 5), and is never reduced.
>
> **Returned, then called outside.**
> ```blink
> fn make() -> (fn(Int) -> Int ! Counter.Inc) {
>     fn(x: Int) -> Int { counter.inc(x) }
> }
> fn main() {
>     let f = make()          // no charge: make's own row is empty
>     io.println("{f(5)}")    // E0539 here
> }
> ```
>
> **Stored.** A field or `List[fn(Int) -> Int ! Counter.Inc]` keeps the row in its element type. Each call of an element is charged.
>
> **`spawn`.** Already decided (§4.13): the row goes to the caller of `spawn`.
>
> The only remaining case is a closure that is never called. It does nothing, so there is nothing to report. Answer to Q2: the case the question names cannot happen. The spec needs no rule for it.
>
> ### Tradeoffs
> - **No new surface.** The rows and §4.15.3 do the work. E0539 stays "rows reaching a root". Users learn one model, and it is the same model as `State`.
> - **Precision.** Call-site charging rejects exactly the programs that can run an operation with no handler. Write-site charging rejects some correct programs and accepts some broken ones.
> - **Cost.** It is only a compiler fix: drop the charge where a closure is written, and charge the closure type's row at each call. The checker already reads that row for E0500. The test `tests/test_ev_closures_effects.bl` "closure called from different handler scopes" then stays green when test blocks become roots.
> - **Error location.** The error points at the call, not at the operation inside the closure. That is where the fix goes (wrap the call in `with`), so it helps the user.
>
> ### Cross-language note
> - **Koka:** a lambda's effect row is in its type and is required only where it is applied. Making it is total.
> - **Eff and OCaml 5:** deep handlers are dynamic. A closure created in a handler and called later outside it is unhandled. OCaml 5 raises `Effect.Unhandled` at that call, which is exactly the `g.bl` case.
> - **Unison:** abilities on a lambda's type are required where it is forced.
>
> All four charge at the call. None captures handlers at the write site.
>
> ### Side findings (not for this panel)
> 1. **`g.bl` prints `0` instead of panicking.** This is a runtime bug against the "Unhandled effect operation" decision, and a separate `type:bug`.
> 2. **Rows in function types do not parse on main.** `build/blink` rejects them in both places I tried: a parameter type (`g: fn(Int) -> Int ! Counter.Inc`) and a parenthesized return type (`-> (fn(Int) -> Int ! Counter)`). Both fail with `expected ), got !`. §4.15.1 and its ~5616/~5666 examples allow these forms. So no probe of the stored, returned or passed-with-row cases compiled; the expected results in Q2 come from the spec, not from runs. This parser gap may block the Q1 fix.

### Phase B — Debate highlights

Skipped. After the Phase A.5 dedupe there was one option per question.

### Phase C — Final vote

Option P (proposed by Systems S1, Web/Scripting W1, PLT P1, DevOps D1, AI/ML A, Minimalism P1), as put to the ballot:

> Making a closure charges nothing; its row stays on its type. A call of the value charges the row at that call, under the handlers in force there. A pass to a `! _` parameter charges the row at that call (§4.15.2 rule 5). A closure that is never called is never charged.

- **Q1: a closure is charged where it is called (6-0)**
  - **Systems:**

    > ## Q1 — ACCEPT
    >
    > **Reasoning:** Making a closure allocates an env and stores a code pointer; no handler lookup happens until an op runs, and the runtime resolves it against the handlers in force at that moment. Charging at the call makes the static check model what the machine does. The write-site rule gives a false positive (ticket program) and a false negative (closure written inside a `with`, called outside: check ok, run prints 0). "Both" keeps the false positive and adds nothing.
    >
    > **Concern:** A call through a value whose static type lost its row (today: pure param types accept effectful closures, and rows on fn types do not parse) becomes a silent hole, so those bugs must land with or before this change.

  - **Web/Scripting:**

    > ## Q1: ACCEPT
    >
    > **Reasoning:** JS, Python and Kotlin developers already know that making a callback does not run it. A `suspend` lambda in Kotlin follows the same rule: you can make one anywhere, but you can call it only from a suspend context. If the check charges at the call, it matches what the program does at run time. Then a program that prints 15 compiles, and a program that would panic gets an error. The write-site rule fails in both directions, so it would generate a large number of "the compiler is wrong" questions.
    >
    > **Concern:** The error points at the call, so a developer can fail to see which closure brings in the effect. The diagnostic must add a note that names the line where the closure was written.

  - **PLT:**

    > ## Q1 — ACCEPT
    >
    > **Reasoning:** This is the standard rule for types with effects (Talpin–Jouvelot, Koka). Making a closure is pure, and its row is paid when the closure is called. §4.7 puts handlers in force where the closure is called, so only a charge at the call matches what happens at run time. A charge where the closure is written rejects the ticket program, which is correct, and accepts the escape case, which is wrong. A charge at both places adds no soundness and only rejects correct programs.
    >
    > **Concern:** The rule is sound only if no value moves from an effectful function type to a pure one. Today main lets an effectful closure into a pure parameter, so until that ticket lands, E0539 still misses the closures that get through that hole.

  - **DevOps:**

    > ## Q1 — ACCEPT
    >
    > Reasoning: The E0539 span must land where the user can fix it with a `with`, and that is the call. Today's span points at the closure body, where no `with` helps. Today's rule also passes p5 silently (it prints `0`), so a diagnostic that cannot see the real fault is worse than none. A secondary label at the operation inside the closure keeps the cause visible.
    >
    > Concern: Without a secondary label at the operation and a hover that shows the inferred row, an error at `f(5)` is opaque. The user sees a call of a plain-looking local and no effect anywhere on that line.

  - **AI/ML:**

    > ## Q1 — ACCEPT
    >
    > **Reasoning.** The spec already says a closure body runs at each call (§2.20) and with the handlers in force where it is called (§4.7). A model that learns from the spec will predict call-site charging. Write-site charging rejects programs that run correctly (the ticket program) and accepts programs that fail at run time (example 2). Both kinds of error teach a wrong model through training data. One rule, the same as `State` in §4.16, means fewer decision points to learn.
    >
    > **Concern.** A user or model may expect an error at the literal inside the `with`. The E0539 message must point at the call and name the closure's binding, or the fix will go in the wrong place.

  - **Minimalism:**

    > ## Q1 — ACCEPT
    > **Reasoning:** The spec already has the rules that decide this: a closure's row is on its type (§4.15.1), making a closure runs nothing (§2.20), the caller holds the row at the call (§4.15.3), and `State` uses the same model (§4.16). Charging where the closure is written is wrong in both directions. It rejects the ticket program, which runs correctly, and it accepts the `with`-escape program, which runs an operation with no handler. "Both" would be a second check that catches nothing new and keeps the false positive.
    > **Concern:** The writer may add a closure clause to §4.6 that repeats §4.15.3 in other words, and the two texts can drift apart; one example plus the shortest statement is the most the spec should get.

- **Q2: the row travels on the closure type; no hidden call (6-0)**
  - **Systems:**

    > ## Q2 — ACCEPT
    >
    > **Reasoning:** The row is part of the fn type, so it travels with the value through params, fields, list elements, returns and `! _` unions at zero run-time cost. The checker reads the callee type at every call of a fn-typed value already, so each call is a visible, charged site. No escape analysis or whole-program pass is needed, and compile cost stays local.
    >
    > **Concern:** The soundness of Q2 depends entirely on `EffectMismatchInFnType` (§4.15.1) being enforced at every coercion site (param, field, element, return, assignment); one missed site lets an effectful closure travel as a pure one.

  - **Web/Scripting:**

    > ## Q2: ACCEPT
    >
    > **Reasoning:** The row travels on the closure's type, so the rule needs nothing new to learn. It is the same rule that already applies to a typed callback, a field or a return value. Every case (passed, stored, returned) uses one rule, and the error is at the line that would fail at run time.
    >
    > **Concern:** Developers must now write rows on callback types (`fn(Int) -> Int ! _`). Until the parser accepts that syntax, and EffectMismatchInFnType suggests `! _` as the fix, developers will hit a confusing wall in the 90% higher-order-function case.

  - **PLT:**

    > ## Q2 — ACCEPT
    >
    > **Reasoning:** The row is part of the closure's type, so wherever the value goes (field, list element, return type, `! _` union), every call of it is a call of a known type with a known row. The check never has to see the closure literal itself. A closure that is never called is never charged, which is sound, because its body never runs.
    >
    > **Concern:** A gap where the type loses the row would let a call go uncharged without any warning. Two such gaps exist on main: the parser rejects a row on a function type, and a pure type accepts an effectful closure. So Q2 holds only once both are fixed.

  - **DevOps:**

    > ## Q2 — ACCEPT
    >
    > Reasoning: When the row travels on the type, the LSP can show it on hover and in the signature help, and the check needs no escape analysis. Each diagnostic has one clear location: the call, the `! _` argument, or the `EffectMismatchInFnType` site where a value is stored in a slot whose type is too narrow.
    >
    > Concern: The parser rejects a row on a fn type today, and `fn make() -> fn(..) -> T ! E` binds the row to `make`. Until the paren form parses and that ambiguity has its own error with a "did you mean `-> (fn(..) -> T ! E)`" fix, a user cannot write the Q2 example.

  - **AI/ML:**

    > ## Q2 — ACCEPT
    >
    > **Reasoning.** The row is part of the function type, so it follows the value through parameters, fields, lists and return types without a special case. A model can find the cause from types alone: read the callee's type and see the row. The common local pattern needs no annotation. Only escaping closures need a row on the signature, and public signatures already must declare rows.
    >
    > **Concern.** Main cannot parse a row on a function type in a parameter today, so examples in the spec will not compile until that is fixed. Code generated from those examples will then fail, which is bad training signal.

  - **Minimalism:**

    > ## Q2 — ACCEPT
    > **Reasoning:** Subtyping only lets a smaller row flow into a larger one, so a row cannot leave a closure's type. A parameter, a field, a list element, a return type or a `_` union each carries the row to the next call. The only closure the check never sees is one that is never called, and that closure does nothing. No new rule is needed.
    > **Concern:** The guarantee holds only when the type checks are complete. On main, a parameter with a pure function type accepts an effectful closure, and the parser rejects a row on a function type. Until both are fixed, the claim is false in the compiler, so those tickets must block the Q1 fix.

- **Q3: the same rule for E0500 in every fn (6-0)**
  - **Systems:**

    > ## Q3 — ACCEPT
    >
    > **Reasoning:** E0539 at roots and E0500 in other fns are the same row check with a different consequence; two charge rules for one row would make the error depend on whether the code sits in `main` or a helper. This also matches the decided `State` rule in §4.16 (the enclosing fn gets `State` only when it calls or forwards the closure). One rule means one code path in the checker.
    >
    > **Concern:** Code that today declares an effect on a fn only because it writes (but does not call) an effectful closure will now get an unused-effect warning or a stricter public row check, which is churn, though pre-1.0 policy covers it.

  - **Web/Scripting:**

    > ## Q3: ACCEPT
    >
    > **Reasoning:** One rule for every fn is easier to learn than one rule for roots and a different rule for other fns. It also agrees with §4.16, where State is charged only on a call or on a pass to a `_` callee. Today's E0500 on a closure that is never called is the same false positive as the ticket program, in a different place.
    >
    > **Concern:** Existing code and tests that depend on the write-site E0500 will change behavior. The E0500/E0539 explain text must be updated together with this change, or it will teach the old rule.

  - **PLT:**

    > ## Q3 — ACCEPT
    >
    > **Reasoning:** One rule for E0500, `State` (§4.16) and E0539 means the system composes, and roots need no special case. §4.15.1 `with_logging` (a pure fn that returns an `IO.Log` closure) already needs this rule. If the rule differed between roots and other fns, a program could compile or fail depending on which fn holds the code.
    >
    > **Concern:** If the compiler fix changes only E0539 and leaves the charge where the closure is written for E0500, the two checks will disagree. The fix belongs in how the compiler builds rows, with tests for both codes.

  - **DevOps:**

    > ## Q3 — ACCEPT
    >
    > Reasoning: If the rule for roots and non-roots differs, moving code out of `main` into a helper changes the verdict. Users and the LSP would then report different errors for the same closure. With one rule, the E0539 and E0500 explain texts tell the same story.
    >
    > Concern: The E0500 explain text ("a closure holds the effects of the function around it") and any tests pinned to E0500 at the closure body must change in the same slice. If they do not, the docs contradict the compiler.

  - **AI/ML:**

    > ## Q3 — ACCEPT
    >
    > **Reasoning.** If E0500 used the write-site rule while E0539 used the call-site rule, the model would need to learn two charging rules for the same row, picked by whether the fn is a root. One rule everywhere is cheaper to learn and to explain in one diagnostic text. It also matches §4.16, where writing a closure that touches `State` charges the enclosing fn nothing.
    >
    > **Concern.** A closure that is written and never called now hides its effect with no message. A dead-code or unused-binding lint should cover that case so the effect does not silently disappear from view.

  - **Minimalism:**

    > ## Q3 — ACCEPT
    > **Reasoning:** Main and test blocks are only roots. The charge rule cannot change from one fn to the next, or E0500 and E0539 would give two models of one row. One rule for every fn means less surface and less to explain.
    > **Concern:** Before this, a fn that only wrote a closure was charged its row. Now it is charged nothing, so its declared row can lose an effect, and an over-declared `pub` row may then need a lint. That is a separate question; do not add a lint unless users ask for one.

### Final Spec

```blink
effect Counter {
    effect Inc { fn inc(n: Int) -> Int }
}

fn unused() {
    let _f = fn(x: Int) -> Int { counter.inc(x) }  // OK: no call, no charge
}

fn make() -> (fn(Int) -> Int ! Counter.Inc) {      // `make` is pure
    fn(x: Int) -> Int { counter.inc(x) }
}

fn main() {
    let f = fn(x: Int) -> Int { counter.inc(x) }   // OK: no charge here
    with handler Counter {
        fn inc(n: Int) -> Int { n + 10 }
    } {
        io.println("{f(5)}")                       // OK: prints 15
    }

    let g = make()                                 // OK: no charge here
    io.println("{g(1)}")                           // ERROR E0539 at the call
}
```

- A closure's row is charged where the closure is called, or where it is passed to a `! _` parameter (§4.15.2 rule 5). It is never charged where it is written.
- The row stays on the closure's type (§4.15.1). No call is hidden.
- The rule is the same for E0500 in every fn and for E0539 at a root.
- A pure slot takes no effectful closure: `EffectMismatchInFnType` (§4.15.1).
- The E0539 and E0500 diagnostics are at the call, and a `note:` names the closure binding and the line of the operation.
