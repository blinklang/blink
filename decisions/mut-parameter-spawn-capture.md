[< All Decisions](../DECISIONS.md)

# Mutable Roots Under E0650 — Design Rationale

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated
in independent-proposal → debate → vote rounds. Ticket IDs in the quoted text are replaced with `[ticket]`.

#### Phase A — Independent proposals

- **Systems:** (excerpt, section `G1 ([ticket]) mut parameters and E0650`)

> Facts I measured. `fn f(mut b: List[Int]) -> Int ! Async` with `async.spawn(fn() { b.len() })`
> then `b.push(2)` before `h.await`: check exit 0, run ICE SharedMutableCaptureNotLowered. The
> ticket note shows the same for `mut b: Bytes`, and with the capture fix it is a real data race:
> spawner and task write one heap cell with no lock.
>
> What the hardware sees: a `mut` parameter is a mutable root, the same as a `let mut`. For
> `Bytes` (a value, not a shared cell, 03_types.md:1449) the freeze does not cover it, so nothing at
> run time stops the race. For `List` the freeze covers the cell, but a struct parameter can mix a
> `List` field with a `Bytes` or `Int` field, and a write to the value field races with no freeze. A static rule on the binding is the only sound guard, and it costs nothing at
> run time.
>
> **G1-P1 (preferred): E0650 covers every mutable root.** A closure passed to `async.spawn` may not
> capture a `let mut`, a `mut` pattern binder, a `mut` parameter, a `mut` binder in a parameter
> pattern, or a `mut self`. Any capture, a read too (a read races a spawner write). Error at the
> capture site in the closure, in `blink check`. Help (as today): bind a copy with `let`.
>
> ```blink
> fn ok(xs: List[Int]) -> Int ! Async {
>     async.scope {
>         let h = async.spawn(fn() { xs.len() })   // OK: immutable parameter
>         h.await
>     }
> }
>
> fn bad(mut b: Bytes) -> Int ! Async {
>     async.scope {
>         let h = async.spawn(fn() { b.len() })    // error[MutableCaptureInSpawn] (E0650) at `b`
>         b.push(2)
>         h.await
>     }
> }
>
> fn fixed(mut b: Bytes) -> Int ! Async {
>     let snap = b                                 // a copy: Bytes is a value
>     async.scope {
>         let h = async.spawn(fn() { snap.len() }) // OK
>         b.push(2)
>         h.await
>     }
> }
>
> // spec-ahead (parameter patterns do not parse yet): same rule
> fn pat((mut xs, n): (List[Int], Int)) -> Int ! Async {
>     async.scope { async.spawn(fn() { xs.len() + n }).await }   // E0650 at `xs`
> }
> ```
>
> Tradeoff: the user writes one `let` line. The rule is about the binder, not its type, so it is one
> check in escape.bl (`is_mut_binder` grows to include params) and gives one answer for plain and
> pattern parameters, which is the consistency the ticket asks for.
>
> **G1-P2: E0650 only for a `mut` binder whose type is not a shared cell (Bytes, StringBuilder,
> structs holding them).** List/Map/Set captures rely on the freeze. Rejected by me: type-dependent
> capture rules are hard to teach, and a struct param mixes both kinds.
>
> **G1-P3: do nothing for params; pattern binders in params stay under E0650.** Leaves the Bytes
> race. Not acceptable: a race on a value type is memory corruption with no panic.
>
> Cross-language: Rust rejects a `&mut` capture into `thread::spawn` without `move` + `Send`; Go
> allows it and has a race detector. Blink has no detector, so the compile rule must hold.
>
> ---

- **Web/Scripting:** (excerpt, section `G1 ([ticket]): E0650 and `mut` parameters`)

> ### G1-P1 (PREFERRED): E0650 covers every mutable root: `let mut`, `mut` pattern binder, `mut` parameter, `mut` binder in a parameter pattern, `mut self`
>
> One sentence: "a closure passed to `async.spawn` may not capture a name declared `mut`". The
> word `mut` is the signal; where the name came from does not matter. Fires in `blink check`, at
> the captured name inside the closure, same help as today (copy to a `let` before the spawn, or
> send it through a `Channel`).
>
> ```blink
> fn bad(mut b: Bytes) -> Int ! Async {
>     async.scope {
>         let h = async.spawn(fn() { b.push(1) })   // error[E0650]: `b` is a `mut` parameter
>         b.push(2)
>         h.await
>     }
>     b.len()
> }
>
> fn bad2((mut xs, n): (List[Int], Int)) ! Async {
>     async.scope {
>         let h = async.spawn(fn() { xs.push(n) })  // error[E0650]: same rule
>         h.await
>     }
> }
>
> fn ok(b: Bytes) -> Int ! Async {
>     async.scope {
>         let h = async.spawn(fn() { b.len() })     // OK: `b` is not mut
>         h.await
>     }
> }
>
> fn ok2(mut b: Bytes) -> Int ! Async {
>     let snap = b                                  // a `let` copy is not mut
>     async.scope {
>         let h = async.spawn(fn() { snap.len() })  // OK
>         b.push(2)
>         h.await
>     }
> }
> ```
>
> Tradeoffs (web seat): the user never has to know that a parameter cannot be reassigned but a
> `let mut` can. Both allow `b.push(...)`, and `push` is the race. The new evidence settles it: a
> `mut` parameter of `Bytes` gives an unlocked data race today (or an ICE on main). A data race
> that check accepts is the worst kind of Stack Overflow question ("works on my machine"). Cost:
> some code that compiles today breaks; pre-1.0, that is fine.
>
> Cross-language: Rust gets this from `Send`/borrow rules, which nobody can explain in five
> minutes. Kotlin coroutines let you capture a `var` and race. The `mut`-keyword rule is simpler
> than both.
>
> ### G1-P2: E0650 only for `let mut` and `let`-pattern binders; parameters rely on the spawn freeze
>
> Rejected by me: the freeze is not built, it does not cover `Bytes` (a value with `mut self`
> writers), and it gives a runtime panic where a compile error is possible. Also two near-identical
> spellings (`fn f(mut xs)` vs `fn f((mut xs, n))`) would behave differently if pattern binders
> alone got E0650; P1 removes that split.
>
> ---

- **PLT:** (excerpt, section `G1. Is a mut binder in a parameter pattern under E0650? Is a plain mut parameter?`)

> The reason for E0650 is a data race: the task and the spawner write one place with no lock. The
> property that makes the race is "the capture is a mutable root" (§3.2.2 defines the term: a
> `let mut` binding, a `mut` pattern binder, or a `mut` parameter). How the root was introduced
> does not change the race. The ticket's evidence proves it: `fn f(mut b: Bytes)` with a spawned
> `b.push(1)` is a race once it builds. So a rule that names only two of the three kinds of
> mutable root is unsound.
>
> ### G1-P1 (preferred): E0650 covers every mutable root
>
> A closure passed to `async.spawn` may not capture a mutable root: a `let mut` binding, a `mut`
> pattern binder, a `mut` parameter, a `mut` binder in a parameter pattern, and a `mut self`
> receiver. Error E0650 at the capture, in check. A `let` binding and a parameter with no `mut`
> stay legal captures (the freeze rule covers the shared cells they reach).
>
> ```blink
> fn ok(ys: List[Int]) -> Int ! Async {
>     async.scope {
>         let h = async.spawn(fn() { ys.len() })     // OK: ys is not a mutable root
>         h.await
>     }
> }
>
> fn bad1(mut b: Bytes) -> Int ! Async {
>     async.scope {
>         let h = async.spawn(fn() { b.push(1) })    // error[E0650]: `b` is a `mut` parameter
>         h.await
>     }
>     b.len()
> }
>
> fn bad2((mut xs, n): (List[Int], Int)) -> Int ! Async {
>     async.scope {
>         let h = async.spawn(fn() { xs.len() + n }) // error[E0650]: `xs` is a `mut` binder of a parameter pattern
>         h.await
>     }
> }
> ```
>
> The help is the one E0650 already gives: bind a copy with `let` before the spawn, then capture
> the copy. For a parameter, `let snapshot = b` is the copy.
>
> Tradeoffs: one rule, stated by the same term that E0610 uses, so the two rules can not drift.
> `is_mut_binder` in src/escape.bl becomes `is_mutable_root`. The cost: code that captures a plain
> `mut` parameter (it compiles today, and builds ICE or races) gets an error. Pre-1.0, a
> CHANGELOG line covers it.
>
> ### G1-P2: no parameter is under E0650
>
> Exclude `mut` parameters and parameter-pattern binders; rely on the freeze rule. Rejected by
> this seat: the freeze covers shared cells, and `Bytes` is a value with `mut self` writers, so
> `b.push(1)` writes the binding, not a frozen cell. This is the race in the ticket. It is
> unsound until some other rule closes it, and it makes `mut x` in a parameter differ from
> `mut x` in a pattern for no reason the user can see.
>
> Cross-language: Rust gets the same result from `Send` + borrow rules (a `&mut` capture can not
> cross `thread::spawn` without `move`); Swift 6 strict concurrency rejects a captured `var` in a
> `@Sendable` closure, parameter or local alike. Neither language separates the root kinds.
>
> ---

- **DevOps:** (excerpt, section `G1 ([ticket]) mut binder in a parameter pattern vs E0650`)

> **G1-P1 (preferred): every `mut` parameter binder is under E0650, plain or in a pattern.**
>
> ```blink
> fn bad(mut b: Bytes) -> Int ! Async {
>     async.scope {
>         let h = async.spawn(fn() { b.push(1) })   // error[E0650] at `b` in the closure
>         b.push(2)
>         h.await
>     }
>     b.len()
> }
> fn bad2((mut xs, n): (List[Int], Int)) -> Int ! Async { ... }   // same E0650, same text
>
> fn ok(b: Bytes) -> Int ! Async {                    // no `mut`: plain capture, legal
>     async.scope { async.spawn(fn() { b.len() }).await }
> }
> fn ok2(mut b: Bytes) -> Int ! Async {
>     let c = b                                        // copy out; capture `c`
>     async.scope { async.spawn(fn() { c.len() }).await }
> }
> ```
>
> Fires in `blink check`, at the capture site, with a `note:` at the `mut` on the parameter
> ("`b` is a `mut` parameter"). Help: bind a copy with `let` before the spawn, or drop `mut`.
> The note text is the only difference from the `let mut` form; the code, the JSON `code` field
> and the fix-it are one.
>
> Tradeoffs (tooling): one rule ("a `mut` binder, of any kind") is one sentence in the catalog row
> and one predicate in the checker; today's `is_mut_binder` already reads it that way. The
> alternative leaves a data race that check accepts. A user who reads E0650 for `let mut` and
> then sees the same race pass for `mut b:` has no way to learn the rule from the tool. Breaking:
> CHANGELOG line, nothing else.
>
> **G1-P2: plain `mut` parameters are exempt; pattern binders are too (E0612 says they are
> parameters).** Consistent, but it ships a race that the freeze spec ([ticket]) does not yet catch,
> and it needs a runtime answer before it is safe. I vote against.
>
> Cross-language: Rust gets this from `Send`/borrowck (a `mut` param is a local like any other);
> Go has no check and `go vet -race` finds it at run time. We should be at the Rust end.
>
> ---

- **AI/ML:** (excerpt, section `G1: mut parameter captured by async.spawn`)

> ### G1-P1 (PREFERRED): E0650 covers every mutable root
>
> E0650 fires when an `async.spawn` closure captures any mutable root: a `let mut` binding, a `mut`
> pattern binder, a `mut` parameter, a `mut` binder in a parameter pattern, and `mut self`. The set
> is the same set that §3.2.2 already lists as "mutable root" (03_types.md:661). Check-time error at
> the capture, same message and help as today.
>
> ```blink
> fn ok(ys: List[Int]) -> Int ! Async {
>     async.scope {
>         let h = async.spawn(fn() { ys.len() })     // OK: ys is not mut
>         h.await
>     }
> }
>
> fn bad(mut b: Bytes) -> Int ! Async {
>     async.scope {
>         let h = async.spawn(fn() { b.push(1) })     // error[E0650] at `b`
>         b.push(2)
>         h.await
>     }
> }
>
> fn bad2((mut xs, n): (List[Int], Int)) ! Async {
>     async.scope { async.spawn(fn() { xs.push(n) }).await }   // error[E0650] at `xs`
> }
> ```
>
> Tradeoffs (AI): one rule, zero carve-outs: "spawn may not capture a name you could mutate
> through". A model already knows which names are mutable roots from E0610; the same set governs
> E0650. The note's evidence shows the plain-param form is a silent data race on main once the
> ICE is fixed; a race is the worst failure for generated code because tests pass most runs. The
> "binder in a parameter pattern is a parameter" rule (E0612) stays true: both forms are in, so
> the two forms agree and the escape.bl `is_mut_binder` result is right as is.
>
> Cost: code that compiles today (and then ICEs) gets an error. Pre-1.0, fine.
>
> Cross-language: Rust rejects a non-`Send`/borrowed `&mut` capture in `thread::spawn` regardless
> of where the binding came from; Swift's `@Sendable` closures reject a captured `var` param too.
>
> ### G1-P2: exempt all parameters (plain and pattern)
>
> Neither form gets E0650; the spawn freeze ([ticket]) must then cover a `mut` parameter's value
> cells. Rejected by me: it depends on a runtime freeze that is not built, `Bytes` writers on a
> value still race, and a model must learn "mut local: error; mut param: runtime panic". Two
> behaviors for one keyword.
>
> ---

- **Minimalism:** (excerpt, section `G1 ([ticket]) mut binder in a parameter pattern, and a plain mut parameter, under E0650`)

> Probe: `fn f(mut b: List[Int]) -> Int ! Async { async.scope { let h = async.spawn(fn() { b.push(1) }); h.await }; b.len() }`
> is clean at check and ICEs at run. So today the Promise breaks; "do nothing" is not open.
>
> ### G1-P1 (PREFERRED): E0650 covers every mutable root
>
> One rule in place of a list: a closure given to `async.spawn` may not capture a name that is a
> mutable root (03_types.md:661 already defines the term: a `let mut`, a `mut` pattern binder, a
> `mut` parameter). That includes `mut self` and a `mut` binder in a parameter pattern. E0650 at
> the capture, in check. The help is the existing E0650 help.
>
> ```blink
> fn plain(mut b: List[Int]) -> Int ! Async {
>     async.scope {
>         let h = async.spawn(fn() { b.push(1) })   // error[MutableCaptureInSpawn] (E0650) at `b`
>         h.await
>     }
>     b.len()
> }
>
> fn pattern((mut xs, n): (List[Int], Int)) -> Int ! Async {
>     async.scope {
>         let h = async.spawn(fn() { xs.len() + n })   // E0650 at `xs`: capture alone is the error
>         h.await
>     }
> }
>
> fn ok(b: List[Int]) -> Int ! Async {
>     async.scope {
>         let h = async.spawn(fn() { b.len() })        // OK: `b` is not a mutable root
>         h.await
>     }
> }
> ```
>
> Tradeoffs: zero new concepts; the rule text gets shorter (it names one term in place of
> two cases), and `is_mut_binder` in src/escape.bl becomes "is a mutable root", which is what it
> almost is now. The `let mut` reason (a write through the binding races the spawner) applies in
> full to a `mut` parameter: E0612 stops reassignment, but the race in the ticket is a mutating
> call, which a `mut` parameter allows. The plain-param and the pattern-param cases get one
> answer, so [ticket] can land with no special case. Cost: code that passes a `mut` param into a
> spawn today breaks; the fix is `let ys = b.clone()` or a non-`mut` param. Pre-1.0, so fine.
>
> ### G1-P2 (rejected): exempt all parameters, rely on the spawn freeze
>
> The freeze ([ticket]) is not built, and it turns a check-time error into a run-time panic. It
> adds a clause ("except a parameter") for no gain.
>
> Cross-language: Rust gets this from `Send` + borrow rules; Go has no check at all (a data race).
> A one-line "mutable root" rule is the cheap middle.
>
> ---

#### Phase B — Debate highlights

- **Systems:** (excerpt)

> G1, G5, G6: no objection.

- **Web/Scripting:** (excerpt)

> G1, G5, G6: no objection. I accept devops' note at the param's `mut` for G1.

- **PLT:** (excerpt)

> G1, G5, G6: no objection.

- **DevOps:** (excerpt)

> G1, G5, G6: no objection. Writer note for G1: error at the capture, note at the `mut` of the param.

- **AI/ML:** (excerpt)

> G1, G5, G6: no objection.

- **Minimalism:** (excerpt)

> G1, G5, G6: no objection.

#### Phase C — Final vote

**G1-Q1: E0650 covers every mutable root** (6-0, option A; the other option was no change)

- **Systems:**

> ## G1-Q1: A
> Reasoning: A `mut` parameter of a value type (`Bytes`) is not covered by the spawn freeze, so without A a check-clean program has a data race on one heap cell with no lock. The rule is on the binder, not the type, so it costs nothing at run time and is one check in the escape pass.
> Concern: a struct parameter declared `mut` only to call one writer must now be copied to a `let` before a spawn; the help must show that line.

- **Web/Scripting:**

> ## G1-Q1: A
> Reasoning: "a spawned closure may not capture a name declared `mut`" is one sentence a JS/Python dev keeps in their head. The new evidence shows a check-clean data race through a `mut Bytes` param. A race that only shows up in production is the worst kind of bug report.
> Concern: the error message must point at the `mut` on the param and show the `let snap = b` copy fix, or users will think parameters are special.

- **PLT:**

> ## G1-Q1: A
> Reasoning: the race comes from capturing a mutable root. How the root was introduced does not matter. §3.2.2 already defines "mutable root" for E0610, so E0650 using the same term keeps the two rules from drifting apart. A rule that names only two of the three kinds of root is unsound: the `mut b: Bytes` evidence is a real race.
> Concern: `mut self` in a method that spawns may surprise users. The help must show the `let` copy fix.

- **DevOps:**

> ## G1-Q1: A
> Reasoning: one rule, "a `mut` binder of any kind", is one catalog sentence and one predicate, and `is_mut_binder` already reads it that way. Without it, check accepts a data race, and the build gives an ICE today or a lock-free race after the capture fix. The note at the param's `mut` tells the user why a param counts.
> Concern: `mut self` on a method that spawns may hit more code than we expect; the help must name the copy-out fix (`let c = self`) so the migration is mechanical.

- **AI/ML:**

> ## G1-Q1: A
> Reasoning: one set of "mutable roots" governs E0610, E0612 and now E0650, so a model learns one list, not one per rule. The ticket evidence shows a plain `mut` param capture is a silent race once the ICE is fixed, and a flaky race is the worst failure for generated code.
> Concern: the help must give a working repair (bind an immutable copy before the spawn, or join first), or models will thrash between E0610 and E0650.

- **Minimalism:**

> ## G1-Q1: A
> Reasoning: one term ("mutable root", already defined at 03_types.md:661) replaces a list of two cases, and the plain-param and pattern-param cases get one answer. A `mut` param allows the mutating call that makes the race; E0612 does not stop it.
> Concern: code that hands a `mut` param into a spawn breaks; the help must show the `let ys = xs.clone()` fix.

### Final Spec

```blink
fn plain(mut b: List[Int]) -> Int ! Async {
    async.scope {
        let h = async.spawn(fn() { b.push(1) })   // error[MutableCaptureInSpawn] (E0650) at `b`
        h.await
    }
    b.len()
}

fn ok(b: List[Int]) -> Int ! Async {
    async.scope {
        let h = async.spawn(fn() { b.len() })     // OK: `b` is not a mutable root
        h.await
    }
}
```

- E0650 fires for a spawned closure that captures any mutable root: a `let mut` binding, a `mut` pattern binder, a `mut` parameter, a `mut` binder in a parameter pattern, or `mut self`.
- The error is at the capture, in `blink check`.
- A note points at the `mut` of the parameter or pattern binder.
- The help shows the copy into a `let` before the spawn.
- Spec text: §2.8 *Closures and `async.spawn`*, §2.8 *Capture Rules Summary*, §3.5 *Mutable Binders*, E0650 in ERROR_CATALOG.md.
