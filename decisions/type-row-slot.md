[< All Decisions](../DECISIONS.md)

# A Type That Stores a Callback Carries a Row Slot — Design Rationale

**Gap:** A closure has an effect row on its type (§4.15.1). A call of the closure charges the row at the call (§4.15.4). A type that stores a closure in a field had no way to keep that row: a `! _` field was not allowed, and a `fn` field with a concrete row had to name one fixed row. So `Cleanup` in `lib/std/testing.bl` stored `fn() -> Void` with no row, and a cleanup that deletes a file in a `! IO` fn could not be charged `FS.Delete` at its `with`.

```blink
pub type Cleanup {
    action: fn() -> Void
}

fn scratch(path: Str) ! IO {
    with cleanup(fn() { fs.delete(path) }) {   // the closure has the row `! FS.Delete`; `Cleanup` has no place for it
        io.println("work")
    }
}
```

## Summary

| Question | Decision | Vote |
|----------|----------|------|
| Q1: where does the row of a stored callback live? | **R**: a type that stores a callback carries one anonymous row slot. Construction infers it from the stored closure. An impl method `! _` on the type takes its source from the slot. A fn with a `! _` parameter may return the slotted type. | 6-0 |
| Q2: how does the declaration spell the slot? | **H1**: in brackets, `type Cleanup[! _] { action: fn() -> Void ! _ }` and `type Job[T ! _]`. The use site is `Cleanup[! FS.Delete]`, `Server[! _]`, `Job[Int ! IO]`. Bare `Cleanup` is the empty row. | 6-0 |

## Writer Notes

1. One anonymous `_` slot per type and per signature. Two slots, a named slot (`type Cleanup[! e]`) or implicit widening of a mutable container are not v1. The error for a named slot says named rows are v2 (E0571).
2. A mutable container never widens in place. A `List[Route[! R1]]` does not become `List[Route[! R2]]`. A builder returns a new value at the wider row, and an old `Server` value does not see a route added later (§4.15.5).
3. The E0500 at a `with` (or call) names the closure's row and points at the effect call inside the stored closure, not only at the `with`.
4. `Cleanup[Int]` gets its own error (E0572) that names the row slot.
5. `type Cleanup ! _ {` gets an error (E0573) with a fix to `type Cleanup[! _] {`.
6. `type Job[T ! _]` parses on the same grammar path as `Handler[E ! R]`. The declaration `! _` and the use `[! R]` are one slot.

The panel did not vote on the variance of the slot. The spec does not decide it.

### Position Changes

Quoted from the seats' own files.

- **sys, F to R, round 1** (`sys-B1.md`): "## Position: R. I drop F."
- **min, F to R, Phase C** (`min-C.md`): "I change from F. Round 1 showed my count of what F adds was too small."
- **min, W and X dropped as first choices, round 1** (`min-B1.md`): "**I take back W as my first choice.**" min listed W second and X third in the same file.
- **web, H2 to H1, Phase C** (`web-C.md`): "I wrote H2 in round 1, but the use site is now brackets, `Cleanup[! FS.Delete]`."
- **sys, H2 to H1, Phase C** (`sys-C.md`): "I wrote H2 in round 1, but H1 is the better fit once use sites take brackets."
- **aiml, H2 to H1, Phase C** (`aiml-C.md`): "Once the panel picks brackets for use sites, H1 gives the slot one spelling everywhere."
- **devops, H2 to H1, Phase C** (`devops-C.md`): "With H1 the declaration and every use have one spelling."
- **min, H2 to H1, Phase C** (`min-C.md`): "Use sites already write the row in brackets (`Cleanup[! FS.Delete]`), so H1 gives the row slot one spelling everywhere."

The options of Phase A.5 were R (plt, web, devops, aiml), F (sys), and W and X (min).

### Panel Deliberation

Each file below is the seat's own text. The only change is the ticket ID in the first heading, which is written `[ticket]`.


#### Phase A: proposals


##### Systems seat

> # [ticket] — Sys seat, Phase A
>
> Sys lens: a row has no runtime form. A closure is `{fn ptr, env}` with or without a row. So the question is only about the type system: where the row lives so that the `with` site is charged the right row. I want it in a type the monomorphizer resolves to a fixed row, as `Guard[T: Closeable]` already does.
>
> ## Measured (gen1, main 14e6f7ba)
>
> - M1: A user struct with a field of concrete row `action: fn() ! IO.Print`, used as a BlockHandler with `exit(...) ! IO.Print`, compiles and runs. Fact 3 holds today.
> - M2: `type Guard[T]`, `impl[T: Thunk] BlockHandler for Guard[T] { fn exit(self, ok: Bool) ! _ { self.inner.call() } }`, with a user `trait Thunk { fn call(self) ! _ }`. A `with Guard { ... }` in a pure fn gives `error[UndeclaredEffect]: with item of type Guard[Del] runs Guard[Del].exit, which needs effect IO.Print, which pure_fn does not declare`. In `main() ! IO.Print` it runs. **So the source-of-`_` rule, along a type parameter, already carries a stored callee's row to the `with` site.** The only gap: a closure cannot be that `T`.
>
> Read only, not measured: the step-3 rejection of an effectful closure in a rowless slot, fn-type subsumption (a pure closure fits `fn() ! IO`), and whether mono keys instances on the row.
>
> ## Q0
>
> Yes, Blink must act. With step 3 on, 59 test sites break, and a cleanup that cannot do effects has almost no use. "Do nothing" is not correct.
>
> ## Proposal S1 (recommended): fn-shape bound on a type parameter
>
> New v1 piece: a type parameter may have a fn type with row `_` as its bound: `[F: fn() ! _]`. Rules:
> 1. Any fn type of that shape (params, return) with any concrete row fits `F`. The row is part of `F`, inferred from the argument.
> 2. A call of a value of type `F` is charged the row of `F`.
> 3. `F` is a source of `_` (source-of-`_` rule extended by one case: "a type parameter whose bound is a fn type with `! _`").
> 4. Mono resolves `F`, so every body sees a concrete row. No row is ever named or unified apart from its type.
>
> std change:
>
> ```blink
> pub type Cleanup[F] {
>     action: F
> }
>
> impl[F: fn() ! _] BlockHandler for Cleanup[F] {
>     type Context = Void
>     fn enter(self) -> Void {
>         let _ = self
>     }
>     fn exit(self, ok: Bool) ! _ {
>         let _ = ok
>         (self.action)()
>     }
> }
>
> pub fn cleanup[F: fn() ! _](action: F) -> Cleanup[F] {
>     Cleanup { action: action }
> }
> ```
>
> Cases:
>
> ```blink
> test "a daemon stops at the end" {
>     let pid = start_daemon()
>     with cleanup(fn() { process.kill(pid) }) {   // F = fn() ! Process.Signal
>         assert(ping(pid))
>     }
> }
> ```
> Compiles. The test is charged `Process.Signal` at the `with`, as a direct `process.kill` call in the body would be. The 59 sites change no text.
>
> ```blink
> fn setup(dir: Str) ! IO {
>     with cleanup(fn() { fs.delete("{dir}/lock") }) {
>         io.println("working")
>     }
> }
> ```
> Error E0500 `UndeclaredEffect` at the `with` item (same form as M2): `Cleanup[...].exit` needs `FS.Delete`, which `setup` does not declare. I ask the writer to print the closure's row, not the full `Cleanup[fn() ! FS.Delete]` type. A pure cleanup in the same fn compiles and charges nothing. This is precise, unlike a fixed wide row.
>
> User struct outside std, two choices:
>
> ```blink
> type Retry[F] {
>     attempt: F
> }
>
> fn run_retry[F: fn() -> Bool ! _](r: Retry[F]) -> Bool ! _ {
>     (r.attempt)()                   // charged the row of F
> }
>
> type Hook {
>     on_save: fn(Str) ! FS.Write     // concrete row, legal today (M1)
> }
> ```
>
> Q2 general rule: a stored callback either has a concrete row on its field (the caller is charged that row; an effectful closure in a rowless field is `EffectMismatchInFnType`), or the struct takes a type parameter `F` with a fn-shape bound, and the row rides in `F`.
>
> http_server: routes are heterogeneous (one `List[Route]`, a different closure per route), so `F` does not fit there. Give `Route.callback`, `Hook.process`, `ErrorHandler.on_error` one concrete row chosen by std, for example `fn(Request) -> Response ! IO, DB, Net, FS, Time`. `server_listen` is charged it. The app root declares it. A DB route compiles; a pure route fits by subsumption (read). Cost: the root carries a wide row, which is honest, because the server can call any route.
>
> ```blink
> let srv = server_get(server_new(), "/users", fn(req: Request) -> Response {
>     let rows = db.query("SELECT name FROM users")   // DB.Read: fits the field row
>     json_response(rows)
> })
> ```
>
> Lazy `iter.map` with IO: unchanged, v1 error (P1 bug owns the code). S1 would allow a Rust-shape `Map[I, F]` adapter later, but `Iterator[T]` is a closure-built type and that redesign is v2.
>
> ```blink
> let xs = [1, 2].iter().map(fn(x: Int) -> Int { io.println("{x}") x })   // v1 error, unchanged
> ```
>
> ### Why S1 does not reopen the v2 vote
>
> v2 row variables are named rows that unify across a signature and a type (`Iterator[T ! e]`). S1 names no row: `F` is a type variable, and the row is resolved by mono like any other part of a type. It adds no row syntax beyond `! _`, which already means "the row of this argument". It is the same rule as `T: Closeable`, with a fn type as the bound. It does put `! _` in a new place (a bound); the adjacent ticket on `! _` positions should list it.
>
> ### Sys tradeoffs
>
> - Runtime cost: zero. `Cleanup[F]` has the same layout as today; `exit` calls through the same fn ptr. Since rows are erased, all `Cleanup[fn() ! R]` share a C layout and body; mono can key the C instance on layout to emit one copy. If mono keys on the row today, that is a handful of duplicate small bodies, not a cost to block on.
> - Compile cost of 59 sites: one inference of `F` each, no source edits.
> - Soundness: no hidden call; the row is in the type at every step.
>
> ## Rejected
>
> - S2, a fixed wide row on `Cleanup.action`: a pure cleanup in a `! IO` fn would fail. Imprecise.
> - S3, compiler special case for `with cleanup(...)`: magic; does not help a user struct.
>
> ## Cross-language
>
> Rust: `struct Guard<F: FnOnce()>` and `Map<I, F>` are this exact shape: the closure type is a parameter, mono makes it zero cost. Koka would use a row variable (our v2). Swift `@escaping` marks only that the closure is stored; it carries no effect. OCaml has no effect in the type, so it gives no check.

##### Web/Scripting seat

> # [ticket] — Web seat (gk-web), Phase A
>
> Measured on gen1 (main 14e6f7ba), probe dir `probe/web/`:
> - A field with a concrete row (`on_tick: fn() -> Void ! IO.Log`) compiles and the call charges `IO.Log`.
> - `fs.delete` in a cleanup closure inside a `! IO` fn: `UndeclaredEffect` (E0500) at `fs.delete`, "add effect `FS.Delete`". Today gen1 charges the closure body where it is written, not at the call.
> - A struct field `f: fn() -> Void ! _` passes `check` today. No check runs on it yet.
> Everything else here comes from reading the spec. The step-3 check is not on yet.
>
> ## Q0: yes, Blink must act
>
> Every Python/JS dev writes `with cleanup(fn() { kill(pid) })`. It is `finally` / `defer` / `addCleanup`. If 59 tests in our own repo break, users break the same way. The only way out today is a type per cleanup with `impl Closeable`. That is one Stack Overflow question per user, forever. "Do nothing" is out.
>
> ## Proposal W1 (recommend): stored rows work like Handler's clause row
>
> Handler already does this (§4.7.1). The type carries a concrete row, the compiler infers that row at construction, `Handler[E ! _]` can appear in a parameter, and `Handler[E]` means the empty row. W1 lets a user type do the same thing:
>
> 1. A type with a field of fn type `! _` has **one row slot**, written `T ! R`. Bare `T` = `T ! ()` (pure), matching rowless = empty.
> 2. Construction infers `R` = the union of the rows of the closures in those fields. `let c = cleanup(...)` has the inferred type. No one writes it.
> 3. A call through such a field charges `R` at the call (the §4.15.4 rule, unchanged).
> 4. An impl method `! _` on that type takes its source from `R` (a new item in the source-of-`_` list, next to type-parameter bounds). So `Cleanup.exit` has row `R`.
> 5. In a parameter or return type, `T ! _` follows today's `_` rule: one anonymous union of the `! _` inputs. A signature gets no named variable and can never relate two rows. That is why W1 does not reopen the v2 vote. It adds no expressiveness that Handler lacks today.
>
> std change: `type Cleanup { action: fn() ! _ }`, `pub fn cleanup(action: fn() ! _) -> Cleanup ! _`.
>
> ```blink
> test "a daemon stops at the end" {
>     let pid = start_daemon()
>     with cleanup(fn() { process.kill(pid) }) {   // Cleanup ! Process.Signal
>         assert(ping(pid))
>     }
> }   // OK. The with calls exit, so the test is charged Process.Signal
> ```
>
> ```blink
> fn scratch(path: Str) ! IO {
>     with cleanup(fn() { let _ = fs.delete(path) }) {
>         io.log("work")
>     }
> }
> // ERROR E0500 at the with (the call of exit): `scratch` declares IO, needs FS.Delete
> //   note: the cleanup closure on line 2 does `fs.delete` (FS.Delete)
> //   fix: add effect `FS.Delete`
> ```
>
> The 59 sites change by zero lines. The error matches the one users get today, but it now sits at the `with`, with a note that points at the closure (the DECISIONS line 616 format).
>
> **http_server.** `Route`, `Hook`, `ErrorHandler` and `Server` take `! _` fields, so `Server ! R`. The builders become `fn server_get(s: Server ! _, path: Str, cb: fn(Request) -> Response ! _) -> Server ! _`. The row grows down the chain, and `serve` charges it:
>
> ```blink
> fn main() ! Net, DB, IO.Log {
>     let s = server_new()
>         .get("/users", fn(req) { json(db.query(t"select * from users")) })
>     serve(s, 8080)   // charged Net + DB
> }
> ```
>
> This is Express/Flask with no new syntax.
>
> **Lazy `iter.map` with IO: unchanged, still a v1 error.** `Iterator[T]` is compiler-known and stays pure by the v2 deferral (§4.15.5). W1 makes `Iterator[T] ! R` easy to add in v2. In v1, std keeps `iter_map`'s `f` rowless. The P1 bug still owes a code for it.
>
> ```blink
> let lines = names.iter().map(fn(n) { io.log(n); n.len() })   // ERROR EffectMismatchInFnType (until v2)
> ```
>
> **A user struct (Q2):**
>
> ```blink
> type Retry {
>     attempts: Int
>     work: fn() -> Bool ! _
> }
> fn run(r: Retry ! _) -> Bool ! _ {      // source: r's row
>     for _ in 0..r.attempts { if (r.work)() { return true } }
>     false
> }
> fn sync() ! Net.Connect {
>     run(Retry { attempts: 3, work: fn() { net.ping("db") } })   // charged Net.Connect
> }
> ```
>
> The general rule for Q2 has three cases. A rowless field is pure, and an effectful closure there is `EffectMismatchInFnType`. A field with a concrete row is the fixed contract, legal today, and the call charges that row. A `! _` field makes the type carry an inferred row (W1).
>
> ### Tradeoffs (my domain)
> - Cost: 0 of the 59 test sites change. std changes about 10 signatures.
> - What users write: nothing in the common case. `T ! Row` shows up only in a signature that stores the value, which is rare. Users already know that form from Handler.
> - Error text stays the familiar E0500. The note names the closure line. People will not open "why does my cleanup break" threads.
> - Soundness: the row lives on the value's type, so each call is charged where it runs, under the handlers in force there. A value that escapes stays honest. A pure slot still rejects it.
> - v2: when named row variables land, `T ! _` becomes `T ! r` with no syntax break.
> - Risk: this answers part of the other ticket (`! _` in a struct field). It allows `! _` in a field, and only as the row slot of the type. Alias and `let` stay with that ticket.
>
> ## Proposal W2 (fallback, cleanup only): a concrete broad row
>
> `action: fn() ! FS, Process, Env, IO`. It is simple, but every test that uses cleanup gets charged all four, a `! IO` fn with a log-only cleanup gets E0500 for FS/Process/Env, and a closure that does Time or Net is `EffectMismatchInFnType`. That is the "why does my one-liner need 4 effects" question. I reject it, and I list it only to show the alternative.
>
> ## Cross-language
> - Swift `@escaping`: the stored callback is marked, and the compiler tracks it. W1's `! _` field does the same job.
> - Rust `struct S<F: FnMut()>`: generic over the closure type, so the type gets inferred at construction. That matches W1. Rust has no effect rows, so it says nothing about effects.
> - Koka: `struct s<e> { f: () -> e () }` is full row polymorphism. W1 is the anonymous, single-slot subset of it, and v2 can grow into Koka.
> - OCaml: effects are untyped, so it has nothing to copy. That is the case we avoid.

##### PLT seat

> # [ticket] Phase A — PLT seat (gk-plt)
>
> ## Q0: yes, Blink must act
> §4.15.2 names cleanup as *the* case for impl-chosen rows on `BlockHandler.exit`. lib/std's `Cleanup { action: fn() -> Void }` makes that row empty, so std contradicts the spec's own example. Leaving 59 tests to break is not "correct": it is a std type with the wrong signature. Do-nothing is rejected.
>
> ## Proposal P1 (primary): a type may carry the row of the callback it stores
>
> Rule. A type declaration may take one row index, written `! _`. Its fields of fn type may write `! _`; each value of the type carries one concrete row, as `Handler[DB ! IO.Log]` does (§4.7.1). The `_` is sourced only from a `! _` parameter of the fn that builds the value, and it may flow to that fn's return type. An impl method of such a type may write `! _`; its source is `Self`'s row (a new case of *Source of `_`*, beside the `T: Closeable` bound case). A call of that method is charged the concrete row of the receiver's type.
>
> ```blink
> pub type Cleanup ! _ {
>     action: fn() -> Void ! _
> }
> impl BlockHandler for Cleanup ! _ {
>     type Context = Void
>     fn enter(self) -> Void { let _ = self }
>     fn exit(self, ok: Bool) ! _ {
>         let _ = ok
>         (self.action)()
>     }
> }
> pub fn cleanup(action: fn() -> Void ! _) -> Cleanup ! _ {
>     Cleanup { action: action }
> }
> ```
>
> Cases:
> - Daemon example: `cleanup(fn() { process.kill(pid) })` has type `Cleanup ! Process.Signal`. `with` charges `exit`'s row (§4.15.4, impl-chosen call) to the test root. A built-in effect at a root never gives E0539. Compiles; the 59 sites stay as written.
> - FS in a fn with `! IO`:
>   ```blink
>   fn work() ! IO {
>       with cleanup(fn() { let _ = fs.delete("/tmp/x") }) {   // ERROR E0500 at the with: missing FS.Delete
>           io.println("hi")
>       }
>   }
>   ```
>   The error names the real effect (FS.Delete), not a std-wide set.
> - http_server: `type Server ! _`. `server_get(srv: Server ! _, pattern: Str, cb: fn(Request) -> Response ! _) -> Server ! _`. One `_` with two sources is their union (§4.15.2), so a chain of routes builds the union. `server_serve(srv: Server ! _) ! Net.Listen, IO, _` charges it. A DB route makes `serve` need DB at its call site, or a `with` that handles DB.
> - Lazy `iter.map(fn(x) { io.println(x) })`: unchanged, v1 error. `Iterator[T]` stays pure by std decision (§4.15.5); P1 gives the mechanism, it does not give Iterator a row index. That stays the v2 effectful-iteration vote.
> - User struct:
>   ```blink
>   type Retry ! _ {
>       times: Int
>       job: fn() -> Bool ! _
>   }
>   fn retry(times: Int, job: fn() -> Bool ! _) -> Retry ! _ { Retry { times: times, job: job } }
>   fn run(r: Retry ! _) -> Bool ! _ { (r.job)() }
>   ```
>   A user who wants a fixed row writes it on the field (`job: fn() -> Bool ! Net`), legal today (§4.15.4).
>
> Why this does not reopen the v2 vote. The power exists in v1: `Guard[T: Closeable]` already makes a type whose method row is the row of a stored value, sourced by a bound (§4.15.2). P1 lets a fn type be that stored value without a wrapper trait. It adds no named variable, no way to relate two distinct rows, no quantified field: there is still one anonymous, prenex row variable per signature, now allowed to appear in output position and as a type index. In v2, `Cleanup ! _` is sugar for `Cleanup[! e]` with a fresh `e`; no v1 program changes meaning. Rows are erased, so there is no mono or layout cost.
>
> Soundness. The row is in the type, so "no hidden call" (§4.15.4) holds: every call of `exit` is charged the stored row. Subsumption is covariant in the index, as for fn types: `Cleanup ! FS.Delete` fits a slot of `Cleanup ! FS`. A rowless `Cleanup` written in a type position means `Cleanup ! ` (empty), consistent with rowless fn types.
>
> Errors. Passing an effectful closure into a rowless field: `EffectMismatchInFnType` (§4.15.1) (unchanged). `! _` on a type with no fn field using it, or `_` in a return type with no `! _` parameter: E0551 `UnsourcedEffectWildcard`.
>
> Scope note. P1 settles `! _` only in (a) a type's own row index, (b) the return type of a fn that has a `! _` parameter. Alias and `let` stay with the adjacent ticket.
>
> ## Proposal P2 (fallback, no new form): fixed row on the field
> `action: fn() -> Void ! FS, Process, IO, Env`, `exit` declares the same row. Test sites compile (built-ins never E0539). Cost: a fn `! IO` that uses cleanup for a file delete gets E0500 for Process and Env it never uses; user effects cannot go in a cleanup at all; http_server needs one guessed fixed set (DB? Net?). Sound but imprecise, and the error text lies about cause. I vote against unless P1 fails.
>
> ## Measured vs read (gen1, main 14e6f7ba)
> - Measured: a field `fn() -> Void ! FS` plus `exit(self, ok: Bool) ! FS` compiles; `with c` in a `! IO` fn gives E0500 "with item of type `FsCleanup` runs `FsCleanup.exit`, which needs effect `FS`". So the charge path P1 relies on exists.
> - Measured, side finding: gen1 charges `fs.delete` inside a closure at the closure's creation (E0500 at the literal), against §4.15.4 "making a closure charges nothing". Worth a bug check by the moderator.
> - Read only: the rowless-field mismatch (step 3 off), all P1 syntax.
>
> ## Cross-language
> Koka: a stored callback's effect is a row variable in the record type (`cleanup<e>`); P1 is that with one anonymous variable. Rust: `struct Cleanup<F: FnOnce()>` — the closure type is a type parameter, same shape as Guard[T]. Swift `@escaping` marks storage but tracks no effects except `throws`/`async`, which lead to `rethrows`-style gaps for stored closures. OCaml has no effect typing on stored closures (OCaml 5 effects are untyped), the failure mode Blink exists to avoid.

##### DevOps/Tooling seat

> # [ticket] — DevOps seat, Phase A
>
> ## Q0: yes, Blink must act
>
> When step 3 is on, each of the 59 sites gets `EffectMismatchInFnType` on the closure. The error points at a std signature (`action: fn() -> Void`) that the user cannot change, and its only "fix" is to delete the cleanup. A diagnostic with no fix the user can apply is a defect. The spec also names cleanup as *the* use of impl-chosen rows (§4.15.2). Do nothing = reject.
>
> Measured today (gen1, step 3 off): a cleanup closure that calls `fs.delete` inside `fn tidy() ! IO` gives E0500 at the `fs.delete` span, "fix: add effect `FS.Delete`". That is the right error at the right span. My target: keep this error and this span after step 3 is on.
>
> ## Proposal A (recommended): one anonymous row slot on a type
>
> A type may declare one row slot, as `Handler[E ! R]` already has one:
>
> ```blink
> pub type Cleanup ! _ {
>     action: fn() -> Void ! _
> }
>
> impl BlockHandler for Cleanup ! _ {
>     type Context = Void
>     fn enter(self) -> Void {
>         let _ = self
>     }
>     fn exit(self, ok: Bool) ! _ {      // source of `_`: the slot of Self
>         let _ = ok
>         (self.action)()
>     }
> }
>
> pub fn cleanup(action: fn() -> Void ! _) -> (Cleanup ! _) {
>     Cleanup { action: action }         // pure: nothing calls action here
> }
> ```
>
> Behavior:
> - A use writes `Cleanup ! FS.Delete`. Bare `Cleanup` is `Cleanup ! ()`, the same rule as a rowless fn type.
> - A struct literal infers the slot as the union of the rows of its `! _` fields.
> - `-> (T ! _)` in a return takes the union of the `! _` parameter rows. The call charges nothing, because nothing is called (§4.15.4).
> - `s: T ! _` in a parameter is a source of `_`, as `h: Handler[DB ! _]` is.
> - `Cleanup ! FS.Delete` into a `Cleanup` slot: `EffectMismatchInFnType` with "in type" text, the same code.
> - `type X ! _` with no `! _` field: E0551 `UnsourcedEffectWildcard`.
>
> Cases:
>
> ```blink
> test "a daemon stops at the end" {
>     let pid = start_daemon()
>     with cleanup(fn() { process.kill(pid) }) {   // Cleanup ! Process.Signal
>         assert(ping(pid))
>     }
> }
> // OK: exit charges Process.Signal at the `with`, under the test root's handlers.
>
> fn tidy(path: Str) ! IO {
>     with cleanup(fn() { let _ = fs.delete(path) }) {
>         io.println("work")
>     }
> }
> // E0500 UndeclaredEffect at the `with` item: "`with` calls Cleanup.exit at block end;
> // its row is FS.Delete (from `Cleanup ! FS.Delete`)", secondary label on `fs.delete`,
> // fix: add effect `FS.Delete` to `tidy`.
> ```
>
> http_server: `Route`, `Hook`, `ErrorHandler` and `Server` get a slot. Each builder unions its rows:
>
> ```blink
> pub fn server_get(s: Server ! _, pattern: Str, cb: fn(Request) -> Response ! _) -> (Server ! _)
> pub fn serve(s: Server ! _, port: Int) ! Net.Listen, _
>
> fn main() ! Net.Listen, DB {
>     let s = server_get(new_server(), "/users", fn(r) { list_users(db.query(t"select ...")) })
>     serve(s, 8080)          // charged Net.Listen, DB.Read: compiles
> }
> ```
>
> Lazy iter (unchanged, v1 error, deferred by §4.15.5):
>
> ```blink
> fn main() ! IO {
>     let it = [1, 2].iter().map(fn(x) { io.println("{x}") x })
> }
> // EffectMismatchInFnType at the closure, plus a note: "a lazy Iterator adapter is pure in v1;
> // use a `for` loop or List.map". Iterator[T] gets no slot in v1. In v2 it can take this
> // same slot without new syntax.
> ```
>
> User struct:
>
> ```blink
> type Retry ! _ {
>     times: Int
>     op: fn() -> Bool ! _
> }
>
> fn run_retry(r: Retry ! _) -> Bool ! _ {
>     for _ in 0..r.times {
>         if (r.op)() { return true }
>     }
>     false
> }
>
> fn ping_db() -> Bool ! DB.Read {
>     run_retry(Retry { times: 3, op: fn() { db.query(t"select 1").len() > 0 } })
> }
> // OK. A concrete row also stays legal (measured: `type Job { action: fn() -> Void ! FS.Delete }` checks today).
> ```
>
> Why this does not reopen the v2 vote: there is one anonymous slot per type, no names, no two separate rows, no row bounds, and no new generic fn form beyond the `! _` forwarding v1 has. `Handler[E ! R]` puts a row in a v1 type today. In v2, `type Cleanup ! e` is a rename of the same thing.
>
> Tooling:
> - Hover and errors show the concrete row (`Cleanup ! Process.Signal`), never a variable. A user can read it.
> - The error span stays on the user's code (the `with` item and the effect call), not on std.
> - `blink fmt`: `type Name ! _ {` is one token run. Nothing new to lay out.
> - LSP completion after `!` already lists effects.
> - 59 test sites: zero edits. Std edits: testing.bl and http_server.bl only.
>
> ## Rejected alternatives (from the error-message angle)
>
> - **B. A fixed wide row on `Cleanup.action`** (`! FS, Process, Env, IO, Net, Time`): `tidy` above gets E0500 for Process, Env and Net, which the closure never does. False charges train users to ignore the error. Reject.
> - **C. Parameter-only shape** (`testing.ensure(body: fn() ! _, after: fn() ! _) ! _`): sound with no new rule, but it rewrites 59 sites, and `?`/`return` in a test body silently change meaning when the body moves into a closure. There is no diagnostic for that change. Reject.
> - **D. Do nothing**: every site gets an error with no fix the user can apply (see Q0).
>
> ## Q2 general rule (Proposal A)
>
> A stored callback either has a concrete row in its field type (legal now), or its type has a slot, and the row travels in the type to the call that runs it. That call is charged under the handlers in force there. Lazy Iterator stays pure in v1.
>
> ## Cross-language
>
> - Koka: data types carry effect rows (`list<() -> e ()>`). Proposal A is a one-variable, unnamed subset of that.
> - Rust: `struct Cleanup<F: FnOnce()>` puts the closure type in the struct type. Same idea, but the slot holds only the effect part.
> - Swift: `rethrows` does not reach an `@escaping` stored closure, so a stored closure must write `throws`. That is the concrete-row-only world, and its cost is the API split Swift has.
> - OCaml 5: effects are untyped, so the compiler checks nothing here.
>
> ## Measured vs read
>
> Measured on gen1 with step 3 off: the today errors for `tidy`, and the concrete-row field `Job`. Everything about step 3 and the slot syntax comes from reading the spec. The slot does not exist yet.

##### AI/ML seat

> # [ticket] — aiml seat, Phase A
>
> ## Q0: yes, Blink must act
>
> The doc comment of `Cleanup` names its use: "temp paths, env-var resets, mock restores". Every one of those is effectful. An AI that reads the doc writes `with cleanup(fn() { let _ = fs.delete(path) })`, and so do the 59 test sites. If the step-3 check makes that an `EffectMismatchInFnType` error, the documented use of the API is an error. "Do nothing" fails learnability on day one. Rejected.
>
> ## Proposal A (recommended): a stored `! _` gives the type one row slot
>
> Behavior:
>
> 1. A struct field may have a fn type with `! _`. Then the type has one anonymous row slot. All `! _` fields of that type share it (the slot is the union). Written, when needed, in the bracket form of the Handler precedent: `Cleanup[! R]`, `Job[T ! R]`. Users almost never write it: a construction infers the slot from the closure rows.
> 2. A fn may return `T[! _]` when a `! _` parameter is the source (existing source rule; `_` = union of the argument rows, as today).
> 3. An impl method on a slotted type may write `! _`; the self type's slot is its source (a new source kind next to "type parameter whose bound has a `_` method").
> 4. A call of such a method on a concrete value is charged the slot of that value. A `with` item counts as that call (§4.15.3 already says so).
> 5. No named variables, no constraints, one slot per type. v2 desugars `action: fn() ! _` to `type Cleanup[e] { action: fn() ! e }`, the same promise §4.15.5 makes for `_` now. So it does not reopen the v2 vote: it adds no surface that v2 must keep apart from what v2 adds.
>
> std change:
>
> ```blink
> pub type Cleanup {
>     action: fn() ! _
> }
>
> impl BlockHandler for Cleanup {
>     type Context = Void
>     fn enter(self) -> Void { let _ = self }
>     fn exit(self, ok: Bool) ! _ {
>         let _ = ok
>         (self.action)()
>     }
> }
>
> pub fn cleanup(action: fn() ! _) -> Cleanup[! _] {
>     Cleanup { action: action }
> }
> ```
>
> Cases:
>
> ```blink
> test "a daemon stops at the end" {
>     let pid = start_daemon()
>     with cleanup(fn() { process.kill(pid) }) {   // OK: the test is charged Process.Signal at the with
>         assert(ping(pid))
>     }
> }
>
> fn tidy(path: Str) ! IO {
>     with cleanup(fn() { let _ = fs.delete(path) }) {   // ERROR E0500 UndeclaredEffect: missing FS.Delete
>         io.println("work")
>     }
> }
> ```
>
> The E0500 points at the `with` line, with a note at `fs.delete`: "the cleanup closure runs when this with block ends". Fix: `! IO, FS.Delete`. The 59 sites need 0 edits.
>
> User struct:
>
> ```blink
> type Job {
>     run: fn() ! _
> }
>
> fn later(j: Job[! FS.Delete]) ! FS.Delete {
>     (j.run)()                        // charged FS.Delete
> }
>
> fn bad(j: Job[! FS.Delete]) ! IO {
>     (j.run)()                        // ERROR E0500: missing FS.Delete
> }
>
> type Fixed {
>     run: fn() ! FS.Delete            // already legal: a concrete row, charged FS.Delete at each call
> }
> ```
>
> http_server: `Route`, `Hook`, `ErrorHandler` and `Server` get a slot. `server_get(srv: Server[! _], pattern: Str, cb: fn(Request) -> Response ! _) -> Server[! _]` makes the server row the union of all routes. `serve` is charged `Net.Listen` plus that slot:
>
> ```blink
> fn main() ! Net, DB {
>     let srv = server_get(new_server(), "/users", fn(req) {
>         users_page(db.query(t"SELECT * FROM users"))
>     })
>     serve(srv, 8080)                 // charged Net.Listen + DB.Read
> }
> ```
>
> Flag for PLT and sys: the builder pushes a `Route[! R2]` into a `List[Route[! R1]]`. A mutable list is invariant, so the std body must build a new list at the wider row. Behavior for users stays as shown.
>
> Lazy iter:
>
> ```blink
> let lines = items.iter().map(fn(x) { io.println(x) })   // unchanged: v1 error
> ```
>
> Unchanged. `Iterator[T]` stays pure (§3c.1). But Proposal A is the mechanism v2 would use to surface the reserved row (`Iterator[T ! R]`), so v2 effectful iteration becomes "allow the slot on Iterator", not a new idea.
>
> ## Proposal B (fallback): a fixed wide row on the field
>
> `action: fn() ! (FS, Process, Env, IO, Time)`. Pure and narrow closures fit (pure is a subtype). Every `with cleanup` is charged the whole row. `tidy` above then fails for Process, Env and Time too, effects the user never wrote. For an AI this is the worst error: it names effects that do not appear in the code, and the fix (declare them) teaches a lie. I vote against B except as a stopgap.
>
> ## Q2 general rule (both proposals)
>
> A stored callback has the row its field type says. Concrete row: legal today, charged at each call. Rowless: pure, an effectful closure is `EffectMismatchInFnType`. `! _` field: only under A.
>
> ## Domain tradeoffs
>
> - Tokens: A costs 0 tokens at the 59 sites and at all user sites. The slot appears only in std signatures and in the rare user signature that names a slotted type.
> - Decision points: a test writer has none. A library author has one ("does my stored callback forward its row?"), the same choice they make for a parameter today, with the same spelling `! _`.
> - Learnability from the spec: one pattern, `! _` means "forward the argument's row", now also in a field. It mirrors `Handler[E ! R]`, which the spec already teaches.
> - Soundness: the slot is concrete at every use, so the charge is exact. No hidden call.
> - Error text: E0500 at the `with` must name the closure as the source, or the AI looks for an effect in the block body and does not find it.
>
> ## Measured vs read
>
> Measured (gen1, main 14e6f7ba): `tidy` above gives E0500 at `fs.delete` today, because the closure body is charged where it is written. A `Job` with `run: fn() ! FS.Delete` called from a `! IO` fn passes `blink check` today: the call through a field is not charged yet. The rest I read from the spec.
>
> ## Cross-language
>
> - Rust: `struct Cleanup<F: FnOnce()> { f: F }`. Mono carries the type; Proposal A is the effect form of that.
> - Koka: `struct cleanup<e> { action: () -> e () }`. Row variable on the type; A is its anonymous one-slot case.
> - Swift: `rethrows` does not survive `@escaping` storage; Swift 6 typed throws needs a generic `E: Error` on the stored type. Same gap, same fix.
> - OCaml 5: effects are untyped, so a stored callback can do anything. That is the unsound outcome Blink must avoid.

##### Minimalism seat

> # [ticket] — Min seat, Phase A
>
> Thesis: the language already answers Q2. §4.15.4 says a row travels through a field, and a field may hold a
> concrete row (`action: fn() ! Process.Spawn`). The gap is in two std signatures, not in the spec. Fix the
> library; add no syntax, no row parameter on user types, no `! _` in fields.
>
> ## Proposal M1 (preferred): concrete rows on stored callbacks; std picks them
>
> **Q0.** Yes, a rowless stored slot that rejects an effectful closure is correct. Blink changes `std.testing`,
> not the type rules.
>
> **Q2 (general rule).** A field of fn type has the row its type writes, and nothing else. A rowless field is
> pure. A call through the field charges that row at the call (E0500 in a fn, E0539 at a root for a user
> effect). An effectful closure into a slot whose row does not cover it is `EffectMismatchInFnType`. No `_` and
> no row variable in a field in v1 (§4.15.5 stays shut).
>
> **Q1.** `Cleanup.action` gets a fixed row: the built-in effects a test root holds
> (`FS, Net, DB, IO, Env, Time, Rand, Crypto, Process`). `Cleanup.exit` declares that row as its impl-chosen
> row (§4.15.2, already legal). The `with` charges the row of `Cleanup.exit` to the enclosing body (§4.15.4
> call of an impl-chosen method on a concrete type). In a test block the root holds all of it, so nothing
> errors and the 59 sites need zero edits.
>
> ```blink
> test "a daemon stops at the end" {
>     let pid = start_daemon()
>     with cleanup(fn() { process.kill(pid) }) {   // OK: root holds the built-in row
>         assert(ping(pid))
>     }
> }
>
> fn scratch(path: Str) ! IO {
>     with cleanup(fn() { fs.remove(path) }) {      // ERROR E0500: `scratch` does not declare FS, Net, DB, ...
>         io.println("work")
>     }
> }
> ```
>
> The E0500 in `scratch` is right in kind (FS is not under IO), but too broad: it names every built-in effect,
> not only FS. That is the cost of a fixed row, and I accept it, because `std.testing` is for tests and a test
> is a root. A user effect in a cleanup closure (`fn() { counter.inc(1) }`) is `EffectMismatchInFnType`; the
> help line points to a guard type (below).
>
> **User struct (outside std).** Write the row in the field. This compiles today:
>
> ```blink
> type Retry {
>     op: fn() -> Int ! Net.Connect
> }
>
> fn run_retry(r: Retry) -> Int ! Net.Connect {
>     (r.op)()                                   // charged Net.Connect
> }
>
> fn bad(r: Retry) -> Int {
>     (r.op)()                                   // ERROR E0500: missing Net.Connect
> }
> ```
>
> When the user wants the row to follow the callback precisely, the existing tool is a type with an
> impl-chosen row on a trait method, not a closure field:
>
> ```blink
> type StopDaemon {
>     pid: Int
> }
>
> impl BlockHandler for StopDaemon {
>     type Context = Void
>     fn enter(self) -> Void {
>         let _ = self
>     }
>     fn exit(self, ok: Bool) ! Process.Spawn {
>         let _ = ok
>         stop_daemon(self.pid)
>     }
> }
> ```
>
> **http_server.** Same rule as cleanup. `Route.callback`, `Hook.process` and `ErrorHandler.on_error` take the
> built-in row, and `server.run` declares it. Its caller is `main` in practice, which holds all of it.
>
> ```blink
> fn main() {
>     let s = server_get(new_server(), "/users", fn(req) { db.query(t"select 1") ... })  // OK
>     server.run(s, 8080)
> }
> ```
>
> **Lazy `iter.map`.** Unchanged: v1 error. `iter_map` takes a pure `f`, so
> `it.map(fn(x) { io.log(x) })` is `EffectMismatchInFnType` (the P1 bug gives it its code and help: "collect
> with `.to_list()`; `List.map` takes a `! _` callback"). Effectful iteration stays a v2 vote.
>
> **Tradeoffs.**
> - Language surface: zero added. Two std types change a field type.
> - 59 test sites: zero edits.
> - Precision: in a non-root fn, the charge over-reports. Rare for `std.testing`; for `http_server`, the
>   driver runs from `main`.
> - Soundness: full. Every call through a field is charged a row that covers the closure.
> - v2 fit: when row variables land, `Cleanup[r] { action: fn() ! r }` replaces the fixed row. Callers do not
>   change; some E0500s go away. Nothing in v1 needs to be taken back. A v1 `Cleanup[! R]` (row argument on a
>   user type, like `Handler[E ! R]`) is a narrow row variable in all but name. That is the v2 vote, so I
>   oppose it here.
>
> ## Proposal M2 (fallback, subtraction): remove `testing.cleanup`
>
> If the panel will not accept a fixed broad row in std, delete `cleanup` and use guard types (above). Rows are
> then exact. Cost: 45 of the 59 sites call `stop_daemon(pid)` (each file has its own copy), so one
> `StopDaemon` type per file covers them; about 14 multi-line closures need their own type or a shared one.
> This reverses part of the std-testing-user-api vote, so I rank it second.
>
> ## Measured vs read (gen1 at 14e6f7ba)
>
> - Measured: a user type with `exit ! Process.Spawn` in a pure fn gives E0500 at the `with` item with a good
>   help line; with the row declared it checks clean.
> - Measured: `type Later { action: fn() -> Void ! IO.Log }` checks, and so does a call `(l.action)()` from a
>   **pure** fn. Spec (§4.15.4) says that call is E0500. So gen1 does not yet charge a call through a field;
>   that is a compiler gap to file, not a spec question.
> - Measured: an IO closure into a rowless field checks today (step 3 off).
> - Read: http_server/iter signatures, `stop_daemon` count, root rule (§4.6), impl-chosen rows (§4.15.2).
>
> ## Cross-language
>
> Koka stores effectful fns with a polymorphic row `e`; that is the v2 shape. Rust `Box<dyn FnMut()>` and
> Swift `@escaping` mark escape or lifetime, not effects, so they have no answer to copy. OCaml 5 effects are
> untyped. Go has none. The minimal answer here matches "worse is better": a fixed row now, a variable later.

#### Phase B, round 1


##### Systems seat

> # [ticket] — Sys seat, Phase B round 1
>
> ## Position: R. I drop F.
>
> R does everything F does for cleanup and a user struct, and it also covers http_server, which F cannot (I said so in Phase A). On my own axis R is also cheaper:
> - F makes `Cleanup` generic over a type. Mono then makes one `exit` instance per distinct closure type, unless it dedupes by layout.
> - R adds no type parameter. Rows are erased, so `Cleanup ! FS.Delete` and `Cleanup ! Process.Signal` are the same C struct with one `exit` body. There is nothing to monomorphize.
>
> On min's "a row variable in all but name": F carries the row inside a type variable, so it has the same power. `Guard[T: Closeable]` measured on gen1 shows that v1 already has this power. R only removes the wrapper trait. I agree with plt that R does not reopen v2.
>
> W: reject. A pure cleanup in a fn with `! IO` fails, and a user effect cannot go in a cleanup at all. It is sound, but the error names effects that do not run. X: reject. It costs 14 or more hand-written guard types to get exactness that R gives for free.
>
> ## R-v1, mark on the header: I prefer the mark (`type Cleanup ! _ { ... }`)
>
> This changes what compiles, so it is not only wording. The header tells a reader, and the checker's first pass, that the type carries a row without scanning its fields. It also gives E0551 a fixed site when no field uses the slot. With no header mark, adding one `! _` field to an existing type silently changes the type's arity in every signature that names it. I would vote for either, but the mark is better.
>
> ## R-v2, spelling: brackets (`Cleanup[! FS.Delete]`). This is not only wording.
>
> `fn f() -> Cleanup ! IO` is ambiguous: `IO` can be the fn's own row or the type's index. devops already has to write `-> (Cleanup ! _)` to get around it. The bracket form has no such parse. It matches `Handler[DB ! IO.Log]` (§4.7.1) and the v2 form `Cleanup[! e]`. If the panel picks the bare form, the spec must state the parse: a `!` after a return type is the fn's row, and parentheses are needed for the type's index.
>
> ## aiml's invariance flag (aimed at plt and sys)
>
> aiml is right, and it is a soundness point, not a style point. `List` is a shared reference. If `server_get` pushed a `Route[! DB]` into the list that the old `srv: Server[! IO]` still points to, then `serve(old_srv)` would be charged IO but would run a DB route. So the builder must return a new `Server` with a new list at the wider row. The cost is O(n) per route, O(n²) to register n routes, and it runs only at startup: 100 routes is about 10k pointer copies, which does not matter. Codegen needs no change for the widening itself, because it changes only the type.
>
> ## Can I accept another option
>
> Yes: R in any of its variations. W only as a last resort. Not X.
>
> stable

##### Web/Scripting seat

> # [ticket] — web, Phase B round 1
>
> ## Position
>
> 1. **R** (first choice).
> 2. **F**: I accept it for cleanup alone, but it fails the web case. A server holds one `List[Route]` with a different closure per route, so F falls back to a wide row that std picks, which is W's flaw in the place users write the most callbacks. A user struct under F also needs `Retry[F]` plus a bound to store one closure. That is fine for TS devs, and noise for Python devs.
> 3. **W**: reject. aiml's point stands: the E0500 names effects the code never does, and the fix ("declare FS, Net, DB, ...") teaches users to over-declare. Every new user sees this, on day one, in a test.
> 4. **X**: reject. 14 bespoke types in our own tests means the same for every user. `defer`/`finally` is the 90% case, and a type per cleanup is the opposite of "just works".
>
> ## R-v1 (header mark): I switch to the header mark
>
> `type Cleanup ! _ { ... }`. Whether a type carries a row is a property of the whole type, and a reader of the signature or of `blink doc` must see it without scanning fields. One token is cheap. Errors in both directions:
> - a header mark with no `! _` field: E0551 (devops);
> - a `! _` field with no header mark: error with the fix "add `! _` to the type".
>
> This changes what compiles, so it is not a wording point.
>
> ## R-v2 (spelling): I switch to aiml's bracket form `Cleanup[! FS.Delete]`
>
> `-> Cleanup ! _` in a return type collides with the fn's own row: is `! _` on the fn or on `Cleanup`? devops already needs parens (`-> (Cleanup ! _)`) to dodge it, and that is a trap users will hit and file questions about. The bracket form has no clash. It matches `Handler[E ! R]`, and it reads like a type argument, which is what a JS/Python dev expects:
>
> ```blink
> pub fn cleanup(action: fn() -> Void ! _) -> Cleanup[! _] {
>     Cleanup { action: action }
> }
> fn keep(c: Cleanup[! FS.Delete]) ! FS.Delete { ... }
> ```
>
> ## Answer to min ("a narrow row variable in all but name; that is the v2 vote")
>
> `Handler[E ! _]` in a parameter has been v1 spec since §4.7.1. It is an anonymous row on a type, inferred at construction and taken as a source of `_`. R gives user types that same slot and nothing more:
> - still one anonymous `_` per signature;
> - no name;
> - no way to relate two rows;
> - no quantified field.
>
> If R reopens the v2 vote, Handler already did. The vote deferred *named* row variables, which R does not add.
>
> ## On aiml's list-invariance flag
>
> This is std-internal: the builder makes a new list at the wider row. Users never see it. It goes to the writer and implementation notes, and is not a point for the vote.
>
> ## Stable
>
> Ready to vote: R with the header mark and the bracket spelling; F as my second; reject W and X.

##### PLT seat

> # [ticket] Phase B1 — plt
>
> ## Position
> 1. R (first). 2. F (acceptable). W: reject as the answer; X: reject.
>
> ## R vs F
> For a type that stores one callback of fixed shape, F and R are the same thing. In `Cleanup[F: fn() ! _]` the params and return of `F` are fixed by the bound, so the row is the only part of `F` that varies. F is R with a full fn type where a row is all that changes. F costs more:
> - A bound is a trait today. `F: fn() ! _` adds a second kind of bound, a structural fn shape with a free row. That is a new form of judgement, not "the `T: Closeable` rule with a fn type".
> - Error text shows `Cleanup[fn() ! FS.Delete]` (sys asks the writer to hide it; R has nothing to hide).
> - Two callbacks need two type params; R gives one slot for the type.
> - F cannot do http_server, so it brings W in for std. R covers both with one rule.
> I accept F if the panel prefers it.
>
> ## R-v2: bracket form. I change my spelling
> `fn cleanup(action: fn() ! _) -> Cleanup ! _` is ambiguous: the trailing `! _` reads as the fn's own row. devops needed parens to avoid that. aiml's `Cleanup[! _]` has no such problem and follows `Handler[E ! R]`. So: `Cleanup[! FS.Delete]`, `Server[! _]`, `Job[T ! R]`. A bare `Cleanup` in a type position is the empty row, as a bare `Handler[DB]` has the empty clause row. This changes what parses, so it is not wording.
>
> ## R-v1: mark the header, in the same bracket form
> `type Cleanup[! _] { action: fn() -> Void ! _ }`. Declaration mirrors use, as `type List[T]` does. The slot changes the type's arity, so the declaration must show it. Without a mark, editing one field silently changes every type position that names the type. A `! _` field in a type with no `[! _]` header: E0551. A `[! _]` header that no field uses: E0551. I accept web/aiml's form if the panel prefers it; this changes what compiles, so it needs a vote.
>
> ## aiml's invariance flag
> Correct and needed. Covariance of the slot holds for a value that cannot be written through an alias. Widening a `List[Route[! R1]]` in place is unsound: an old alias typed at R1 could read a route that does R2 and call it charged only R1. So no implicit widening of a mutable container. The std builder makes a new list at the wider row (each element widens by subsumption). Setup cost is O(routes), once. Users see nothing.
>
> ## min: "a row variable in all but name"
> It is one anonymous row parameter on a type, yes. v1 already has both halves: a type indexed by a concrete row (`Handler[DB ! IO.Log]`) and a type whose method row follows a stored value (`Guard[T: Closeable]`, measured by sys, M2). What §4.15.5 defers is named rows that relate several distinct rows in one signature. R cannot write `fn f(a: X[! e1], b: Y[! e2]) -> X[! e1]`: one `_` per signature is a union. The v2 vote keeps its whole content. And F, which min does not object to in these words, has exactly the same power.
>
> Stable: ready to vote.

##### DevOps/Tooling seat

> # [ticket] — devops, Phase B round 1
>
> ## Position
>
> My ranking: R, then F, then X, then W. I hold R. I can accept F only if http_server also gets an exact row. I can accept X as a last resort. I will not accept W.
>
> **Why R.** One rule covers Cleanup, http_server and user structs. Each error names the effects that are really in the code, and each error lands on the user's `with` or call. Hover shows a concrete row and never a variable.
>
> **F (sys).** F is sound for Cleanup, and its errors are good there. But by sys's own account it does not fit http_server. A route then gets a fixed wide row, and that brings back W's false E0500 at `serve`. Two rules for one class of problem means two error texts and two doc pages. F's hover is also noisier: `Cleanup[fn() -> Void ! Process.Signal]` against `Cleanup[! Process.Signal]`. That is a minor cost.
>
> **W (min).** aiml is right that W "teaches a lie". An E0500 that lists FS, Net and DB for a closure that only prints trains users to paste in rows they do not need, and that wears down every later effect error. W also rejects a user effect in a cleanup closure. Reject.
>
> **X (min M2).** X is sound and every row is exact. Its cost is user friction: about 14 new types in tests/, and a guard type for every effectful cleanup a user writes. I accept it only over W.
>
> **On min's point** ("a narrow row variable in all but name"): from the tooling side, the user never sees or writes a variable name. `Handler[DB ! R]` already puts a row in a v1 type, and `! _` forwarding already exists. R adds no new kind of thing to type in, hover over or read in an error.
>
> ## R-v1: mark the slot on the type header (I keep my position, but can accept either)
>
> - `blink doc` and hover on the type show the slot without a reader scanning the fields.
> - A `! _` field in an unmarked type gets one clear error with a fix-it ("add `! _` to the header of `Route`"). A header mark with no `! _` field gets E0551.
> - Implicit slots mean that adding one field to a type silently changes how its type is spelled at every use. With an explicit header, that change is visible in review.
>
> Whichever form we pick, what compiles is the same. This choice is about tooling and review.
>
> ## R-v2: I switch to aiml's bracket form `Cleanup[! FS.Delete]`
>
> This changes what compiles, so it is not a wording point. With my form, `-> Cleanup ! _` without parentheses gives the row to the fn, not to the type. That is a silent wrong meaning, or an E0551 that confuses the user. The bracket form has no such trap: `-> Cleanup[! _]`, `List[Cleanup[! IO]]`, `Job[T ! R]`. It also matches `Handler[DB ! R]`, so the parser, `blink fmt` and LSP completion reuse a single path.
>
> ## aiml's invariance flag
>
> The std builder must build a new list at the wider row, because a mutable list does not widen. That is a std body detail, not a language rule. It goes to the implementation notes.
>
> stable

##### AI/ML seat

> # [ticket] — aiml, Phase B round 1
>
> ## Position
>
> 1. **R, first.** I can accept **F** as second. I reject **W** and **X**.
>
> ## Answer to min ("R is a narrow row variable in all but name")
>
> §4.15.5 already says `_` "can desugar to an anonymous effect variable". So every `! _` parameter is already an anonymous row variable in v1. R does not add a kind of thing. It lets that same anonymous variable reach a field and a return type. You still cannot name a row, cannot relate two rows, and cannot constrain one. Those three are what the v2 vote deferred. A user still writes only `_`, so an AI learns no new concept.
>
> ## F vs R (my domain)
>
> - F needs two rules for one class of API: F for `Cleanup`, and W for http_server, because routes are heterogeneous. That puts W's error back on every server app: the root must declare `IO, DB, Net, FS, Time` even when no route uses DB. An AI then adds effects it does not use, to quiet the compiler. R covers both with one rule.
> - F prints the closure type in the value type (`Cleanup[fn() -> Void ! Process.Signal]`). The error text is longer and names the closure's shape where only its row matters.
> - F does have one plus: it needs no new type-position syntax. If the panel rejects R, F is better than W for cleanup, and I vote for it.
>
> ## W and X
>
> - W: unchanged from Phase A. The error names effects that are not in the code.
> - X: about 14 sites need a separate 10-line type each. For a user, every cleanup becomes a type declaration. That costs tokens and adds a decision point at each use. web's point stands.
>
> ## R-v1 (mark on the header)
>
> I switch to the header mark: `type Cleanup ! _ { action: fn() ! _ }`. It mirrors `fn f() ! _ {`, and an AI that reads only the first line knows the type carries a row. `type X ! _` with no `! _` field gives E0551 (devops). A `! _` field in a type with no header mark should be an error too, with a fix that adds the mark. Then the program has one form, not two.
>
> ## R-v2 (spelling in a type position)
>
> This is syntax, not only wording, but it does not change which programs compile. I prefer the bracket form only a little. `Cleanup ! R` needs two rules: `! (A, B)` for two effects, and parentheses in return position (`-> (Cleanup ! _)`). Those are the rules for fn types today, so an AI that knows fn types knows them. With the header mark, `Cleanup ! R` is consistent with the declaration. **I accept `Cleanup ! R`** and do not hold out for brackets.
>
> ## My invariance flag
>
> This is about the std body, not about behavior. The builder returns a new `Server` at the union row and copies the routes into a new list. Users see no change. It goes to the implementation notes, not the spec.
>
> stable

##### Minimalism seat

> # [ticket] — Min seat, Phase B round 1
>
> ## Position: F first, W second, X third, R against
>
> **I take back W as my first choice.** sys has a correct point against it: `Cleanup.exit` has a fixed row, so *every*
> cleanup charges the full built-in row, even a pure cleanup. A pure cleanup in a `! IO` fn then gives E0500 for
> effects that no code does. aiml's point holds too ("the fix teaches a lie"). That is a defect in what the user
> sees, not only lost precision. I can accept W only as a fallback.
>
> **F clears my bar.** My test is "is there an existing feature it reuses, and what does it interact with?"
> - It reuses a mechanism that works today. sys measured `Guard[T: Thunk]` with `exit ! _`, and it charges the
>   stored callee's row at the `with`. The only gap is that a closure cannot fill `T`. F closes that one gap and
>   nothing more.
> - It adds one grammar case (a fn type with `! _` as a bound) and one case to the source-of-`_` rule. It adds
>   no new type position for a row, no row in a return type, and no variance rule.
> - It names no row, and mono resolves it. So the v2 vote stays shut. In v2, a row variable can replace the
>   bound with no change to call sites.
> - http_server under F is W (one concrete row picked by std). That puts the wide row only where routes are
>   mixed, which is the one place where it is honest. `serve` can call any route.
>
> **R is against.** The scope is larger than its proposers say:
> - a row index on every type that has one, and covariance of that index;
> - `! _` in a return position, a row union across a builder chain (`server_get` → `server_get`), and the
>   invariance problem that aiml flagged for `List[Route[! R]]`.
>
> That is row polymorphism in data. plt says it is "one anonymous prenex variable per signature". But a value
> that carries it can be stored, returned, put in a list and widened. Those are the v2 questions. The
> http_server union is the strongest case for R, and std can serve it with W at no language cost.
>
> ## R-v1 and R-v2, if R wins
>
> - **R-v1: mark the header** (`type Cleanup ! _`), as plt and devops do. If a field alone gives a type a row
>   index, an edit to one field changes the type's arity at every use site, with no sign of it in the
>   declaration. This is about what compiles, not wording.
> - **R-v2: use the bracket form** `Cleanup[! FS.Delete]` (aiml). `fn cleanup(...) -> Cleanup ! _ { ... }`
>   (plt-A) reads as the *fn's* row. devops needs parentheses (`-> (Cleanup ! _)`) to avoid that reading. The
>   bracket form has no such ambiguity and follows `Handler[E ! R]`. This is a parse and readability problem,
>   not wording.
>
> ## Answers aimed at my options
>
> - aiml on W ("names effects not in the code"): accepted, see above.
> - web on X ("one Stack Overflow question per user"): fair for users. X stays third: it subtracts from std, but
>   it costs every user a type per cleanup.
> - sys and others on "W is imprecise": accepted.
>
> ## For the writer (wording only)
>
> - The E0500 at the `with` should print the closure's row, not `Cleanup[fn() ! FS.Delete]` (sys asked the same).
>
> Stable: I am ready to vote. My order is F > W > X > R.

#### Phase C: votes


##### Systems seat

> # [ticket] — Sys seat, Phase C vote
>
> ## Q1
>
> **Vote:** R
>
> **Reasoning:** Rows have no runtime form, so under R every `Cleanup[! R]` is one C struct with one `exit` body. There is no type parameter and nothing for mono to multiply, and the closure call compiles exactly as it does today. F gives the same row precision for cleanup, but it makes mono key on a closure type, and for http_server it falls back to a wide fixed row that charges effects no code runs. One rule that costs nothing at runtime and gives exact rows in both places beats two rules.
>
> **Concern:** If the checker lets a mutable container widen in place, R is unsound: an old alias typed at a narrower row could call a route that does more. The builder copy, and an invariance rule for mutable containers, must ship with R and have a test.
>
> ## Q2
>
> **Vote:** H1
>
> **Reasoning:** I wrote H2 in round 1, but H1 is the better fit once use sites take brackets. The declaration and the use then have the same shape, so the parser, fmt and LSP share one path. A generic type stays in one bracket on both sides: `type Job[T ! _]` declares it and `Job[Int ! IO]` uses it. Under H2 that pair would be `type Job[T] ! _` against `Job[T ! R]`, two shapes for one slot.
>
> **Concern:** `type Cleanup[! _]` looks like it has a type parameter, so a reader may try `Cleanup[Int]`. That needs its own error that names the row slot.

##### Web/Scripting seat

> # [ticket] — web, Phase C vote
>
> ## Q1
>
> **Vote:** R
>
> **Reasoning:** The two cases users write most are `defer`-style cleanup and route handlers, and R covers both with one rule: the 59 sites need no edits, and every error names only effects the code performs. F covers cleanup but falls back to W on http_server. A Flask or Express dev then gets an E0500 at `serve` for DB or FS effects that no route does, which is the one error we should never teach. min's scope worry is real but already priced in: `Handler[E ! _]` ships the same anonymous slot in v1, and no user ever writes a name.
>
> **Concern:** Users may hit the builder widening (a `Server[! IO]` alias that does not see a later DB route) and file "why did my old server value not change" questions. std's builder must return a new value, and the docs must show that.
>
> ## Q2
>
> **Vote:** H1, `type Cleanup[! _] { ... }`
>
> **Reasoning:** I wrote H2 in round 1, but the use site is now brackets, `Cleanup[! FS.Delete]`. Declaration should mirror use, as with `type List[T]` / `List[Int]` and TS `type Box<T>` / `Box<number>`. A JS/Python dev then learns one shape, not two: `Job[T ! _]` at the declaration, `Job[Int ! IO]` at the use. With H2, a type is declared one way and named another, and that gap generates questions for no gain.
>
> **Concern:** `type Cleanup[! _]` looks like a generic parameter, so users may try to put a name there (`[! e]`). The error must say that named rows come in v2 and that `_` is the only form in v1.

##### PLT seat

> # [ticket] Phase C — plt
>
> ## Q1
> **Vote:** R
>
> **Reasoning:** For a type that stores one callback of fixed shape, F and R have the same power: the bound fixes everything but the row. F gets that power through a new kind of bound (a structural fn shape with a free row, where bounds are traits today), and it still needs W for http_server. R is one rule that covers std and user types, and it reuses a form v1 already has (`Handler[E ! R]`, a row on a type, sourced by `_`). It adds no named row and no way to relate two rows, so the content of the v2 vote stays open. min's list (stored, returned, in a list, widened) is true of `Handler[DB ! _]` today.
>
> **Concern:** The covariance of the slot must hold only for values, never for in-place widening of a shared mutable container (aiml's flag); if the spec or checker lets a `List[Route[! R1]]` widen in place, a call runs effects its charge does not show.
>
> ## Q2
> **Vote:** H1
>
> **Reasoning:** The use site writes the row as a type argument, `Cleanup[! FS.Delete]`, so the declaration should declare it as a type parameter in the same place, as `type List[T]` declares what `List[Int]` fills. With type parameters the gap shows: H1 gives `type Job[T ! _]` for a use `Job[Int ! IO]`; H2 gives `type Job[T] ! _` for that same use, two positions for one parameter. H1 also maps directly onto v2 named rows, `type Job[T ! e]`. H2's analogy with `fn f() ! _` is weaker, because a fn's row is an effect of running it, but a type's slot is an index.
>
> **Concern:** H2 is what most seats wrote by habit; if H1 loses, the spec must still say that the declaration's `! _` and the use site's `[! R]` are the same slot, or readers will expect `Cleanup ! R` at the use site.

##### DevOps/Tooling seat

> # [ticket] — devops, Phase C vote
>
> ## Q1
>
> **Vote:** R
>
> **Reasoning:** R gives one rule, and so one error text and one doc page, for Cleanup, http_server and user structs. Each E0500 names only the effects that the code really does, at the user's `with` or call, and hover shows a concrete row such as `Cleanup[! Process.Signal]`. F handles cleanup, but it puts W's false charges back at every `serve` and prints the full closure type in errors. The 59 test sites need no edits.
>
> **Concern:** When an E0500 at a `with` comes from a row inferred at a construction site much earlier, the user may not see where the row came from. The diagnostic must point at the effect call inside the stored closure as well as at the `with`.
>
> ## Q2
>
> **Vote:** H1 (`type Cleanup[! _] { ... }`)
>
> **Reasoning:** With H1 the declaration and every use have one spelling, and it is the same one `type List[T]` / `List[Int]` and `Handler[DB ! R]` use. `blink fmt`, LSP completion and a grep for `Cleanup[!` then find declarations and uses alike. H2 puts `!` after the name in the declaration and brackets at each use. Users will write each form in the other's place, and that is two more "did you mean" diagnostics to build and teach. H1 also composes with a type parameter as `type Job[T ! _]`, which mirrors the use `Job[T ! R]`. H2 needs `type Job[T] ! _`, a third shape.
>
> **Concern:** `type Cleanup[! _]` reads like a generic type parameter list, so a user may try to name the slot (`type Cleanup[! e]`). That must give a clear error that says named rows are v2 (§4.15.5), not a generic parse error.

##### AI/ML seat

> # [ticket] — aiml, Phase C vote
>
> ## Q1
>
> **Vote:** R
>
> **Reasoning:** R uses one rule for Cleanup, http_server and user structs, and every user site needs 0 extra tokens (the 59 tests need no edits). Each E0500 names only effects that are in the code. F needs a second rule (a wide row that std picks) for http_server. That puts back the error that teaches users to over-declare, in the place they write the most callbacks. R also reuses a form the spec already teaches (`Handler[E ! R]`), so an AI can learn it from the spec alone.
>
> **Concern:** Users may expect a type with a row to widen in place. The rule that a mutable container does not widen must be explicit, with an error that names it, or the first user builder that copies the http_server pattern will hit a confusing mismatch.
>
> ## Q2
>
> **Vote:** H1 (`type Cleanup[! _] { ... }`)
>
> **Reasoning:** Once the panel picks brackets for use sites, H1 gives the slot one spelling everywhere, so the declaration mirrors its use, as `type List[T]` mirrors `List[Int]`. An AI writes a declaration from the uses it has seen, and with H2 it must learn two spellings for one slot (`! _` after the name in the declaration, `[! R]` at a use). I backed H2 in round 1, when I accepted the bare `Cleanup ! R` at use sites. Now that brackets won there, H1 is the more consistent form.
>
> **Concern:** An AI that knows `fn f() ! _ {` may still write `type Cleanup ! _ {`. That form needs a targeted error with the fix "write `type Cleanup[! _]`".

##### Minimalism seat

> # [ticket] — Min seat, Phase C vote
>
> ## Q1
>
> **Vote:** R
>
> **Reasoning:** I change from F. Round 1 showed my count of what F adds was too small. plt is right that a fn-shape bound is a new kind of bound, a structural judgement and not a trait. F also needs W for http_server, so F is two rules (a new bound plus a fixed wide row) where R is one. On my axis, one rule that replaces two mechanisms beats two smaller ones. The v2 objection does not hold. `Handler[E ! _]` already puts an anonymous row on a v1 type (web), and §4.15.5 already calls `_` an anonymous variable (aiml). R still cannot name a row or relate two rows, and that is what the vote deferred.
>
> **Concern:** The slot must stay one anonymous `_` per type and per signature. A later "small" step such as two slots, a named slot, or implicit widening of a mutable container would be the v2 vote entered by the side door, so the spec must forbid those plainly.
>
> ## Q2
>
> **Vote:** H1 (`type Cleanup[! _] { ... }`)
>
> **Reasoning:** Use sites already write the row in brackets (`Cleanup[! FS.Delete]`), so H1 gives the row slot one spelling everywhere. H2 adds a second spelling for the same slot, and it looks like a fn's own row on a line that declares no fn. With H1, declaration mirrors use, as `type List[T]` and `Handler[E ! R]` do, and a reader learns one form, not two.
>
> **Concern:** `type Job[T ! _]` must parse the same way as `Handler[E ! R]`, with one grammar path. A second bracket rule only for declarations would cancel the gain.

### Final Spec

```blink
type Cleanup[! _] {
    action: fn() -> Void ! _
}

pub fn cleanup(action: fn() -> Void ! _) -> Cleanup[! _] {
    Cleanup { action: action }
}

impl Scoped for Cleanup[! _] {
    type Context = Void
    fn enter(self) -> Void { let _ = self }
    fn exit(self, ok: Bool) ! _ {
        let _ = ok
        (self.action)()
    }
}

fn scratch(path: Str) ! IO {
    with cleanup(fn() { fs.delete(path) }) {   // ERROR E0500: `FS.Delete` is not in `scratch`
        io.println("work")
    }
}
```

- A type that stores a callback carries one anonymous row slot, `[! _]` at the declaration and `[! R]` at a use site. Bare `Cleanup` is the empty row.
- A `! _` field in a type with no slot is E0551, with a fix that adds `[! _]`. A slot that no field uses is E0551.
- A named slot or a second slot is E0571. `Cleanup[Int]` and `Plain[! IO]` are E0572. `type Cleanup ! _ {` is E0573.
- A fn with a `! _` parameter may return the slotted type. The pass charges nothing. The call of the stored closure charges the slot.
- An impl method `! _` on a slotted type takes its source from the slot.
- A value never changes its row after it exists. A builder returns a new value at the union row.
- A field with a concrete row stays legal. A field with no row is pure. A lazy `iter.map` with an effectful callback stays a v1 error.
- One anonymous slot per type is v1. Named slots and two slots stay v2 (§4.15.6).
