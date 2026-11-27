[< All Decisions](../DECISIONS.md)

# The Exit Sweep of a DB Driver — Design Rationale

**Gap:** §4.4.10 (*Release*) says: "When the `with` of a driver's connection exits, the driver finalizes every `Stmt` that is still open ... by `?`, by `return`, by `break`, and by panic." The reference driver of §4.7.2 could not do this. `exit(self)` got only `Connection { handle }`, and the `stmts` map lived inside `sqlite_handler`, where only the clauses of the handler could reach it. A plain `sqlite3_close` also fails (SQLITE_BUSY) while a statement is open:

```blink
// before: exit has the handle only; the map is inside the handler
impl Scoped for Connection {
    fn exit(self, ok: Bool) ! FS.Read, FS.Write, FS.Delete {
        sqlite_close(self.handle)    // who finalizes the Stmt that `with` left open?
    }
}
```

**Questions:** Q0, does the spec need to say more? Q1, where does the sweep run, and what can it reach? Q2, does the sweep mark each entry it finalizes? The ticket also asked whether the sweep is a std rule or a driver convention. All six panelists agreed in Phase A: it is a driver convention.

**Already decided (not on the ballot):** the driver is the package `blinklang/sqlite`, and `connect` with `Connection: Scoped` is a convention for driver packages (see [Database Driver Package rationale](db-driver-package.md)); each `Stmt` method is a `DB` operation, with the three Errs, an idempotent `finalize` and the exit sweep (see [Stmt Operations rationale](stmt-db-effect-ops.md)); `Stmt.new()` is the one token constructor, and each handler keeps its tokens in a `Map[Stmt, ...]` (see [Statement Tokens rationale](stmt-token.md)); pre-1.0 changes ship at once.

### Panel Deliberation

Six panelists (systems, web/scripting, PLT, DevOps/tooling, AI/ML, minimalism) deliberated in independent-proposal, debate, vote rounds. Phase B ran one round, because all six were stable after it. Phase C was a silent vote. No Phase D ran.

#### Phase A — Independent proposals

All six said yes to Q0: the spec promises a sweep that its example cannot run. All six said the sweep is a driver convention, with no new language construct (no handler `finally` or `on_exit` clause, no `exit(self, ctx, ok)`). All six said the panic wording of §4.4.10 must cover only a panic that a catch frame catches, because an uncaught panic skips `exit()`. Three families of proposal came out of Phase A:

- **N:** `exit` walks the native library's own list of open statements through the handle, then closes. The map stays in the handler (Minimalism, Web).
- **F:** the map is a field of `Connection`, made in `connect`. `enter` passes it to the handler, and `exit` loops over it, then closes (Systems, PLT).
- **C:** `connect` builds the handler and a sweep closure over one `let mut` cell, and `Connection` stores both (DevOps, AI/ML).


- **Systems:**

> Systems Phase A: build the Stmt map in connect, keep it in Connection, and have exit sweep it. This is a driver convention, not a std rule.
>
> **Q0: yes, the spec has to change.** As written, the §4.7.2 example cannot do what §4.4.10 promises. `exit(self)` cannot reach `stmts`. The likely C call behind `sqlite_close` is `sqlite3_close`, which returns SQLITE_BUSY while any statement is open. So the example leaks the connection and every raw statement on the most common path: a `with` that prepared something and never called finalize. A spec example that leaks is the one people copy.
>
> **Proposal A (my pick): acquire the map before the block, the same way as the handle.**
> The fact-4 rule already settles this: enter cannot hand state to exit, so the state must exist from construction. `Map` is a shared cell (§3.6), so a copy of `Connection` names the same map. The handler captures it, exit reads it, and nothing new goes into the language:
>
> ```blink
> pub type Connection {
>     handle: Sqlite3
>     stmts: Map[Stmt, Entry]
> }
>
> pub fn connect(path: Str) -> Result[Connection, DBError] ! FS.Read, FS.Write, FS.Delete {
>     let handle = sqlite_open(path)?
>     Ok(Connection { handle: handle, stmts: Map.new() })
> }
>
> impl Scoped for Connection {
>     type Context = Handler[DB ! (FS.Read, FS.Write, FS.Delete, Time.Read, Time.Sleep, Rand, State)]
>
>     fn enter(self) -> Handler[DB ! (FS.Read, FS.Write, FS.Delete, Time.Read, Time.Sleep, Rand, State)] {
>         sqlite_handler(self.handle, self.stmts)
>     }
>
>     fn exit(self, ok: Bool) ! FS.Read, FS.Write, FS.Delete {
>         for entry in self.stmts.values() {
>             match entry {
>                 Open(raw) => sqlite_finalize(raw)
>                 Finalized => {}
>             }
>         }
>         sqlite_close(self.handle)
>     }
> }
>
> fn sqlite_handler(handle: Sqlite3, mut stmts: Map[Stmt, Entry])
>     -> Handler[DB ! (FS.Read, FS.Write, FS.Delete, Time.Read, Time.Sleep, Rand, State)] {
>     handler DB {
>         // clauses unchanged: prepare inserts Open(raw), finalize sets Finalized
>     }
> }
> ```
>
> Behavior: `with sqlite.connect(p)? { let s = db.prepare(q)? }` finalizes the raw statement of `s` and then closes the connection on `?`, `return`, `break`, and on a caught panic. Nothing new compiles or fails to compile.
>
> Tradeoffs from my seat:
> - What the hardware sees is plain: one hash map, one walk at exit, then close. There is no hidden runtime hook and no ordering magic.
> - Order matters: the sweep must run before close. The example shows it, and the spec should say it in one line.
> - Cost I want on record: Finalized tombstones never leave the map. A server that holds one connection for hours and prepares a statement per request grows the map, and the exit walk, without bound. That cost comes from the "statement is finalized" vs "another connection" distinction, not from this ticket. I will log a friction ticket rather than widen scope here.
> - The handler stays reachable only inside the `with` (E0601/E0602), so no one can see stale `Open` entries after the sweep. exit does not need to mutate the map.
>
> **Proposal B (rejected as the spec example): walk the native library's own list.**
> SQLite has `sqlite3_next_stmt(db, NULL)`, so `exit` could finalize every raw statement through `self.handle` alone. libpq's `PQfinish` drops server-side prepared statements as well. This works, but it holds only for C libraries that track their children, and it hides why the map exists. A driver may use it as an implementation choice. The spec should not teach it.
>
> **Panic wording.** §4.4.10 says "and by panic", but fact 2 says an uncaught panic bypasses `exit()`. It should say "a panic that a catch frame catches". After an uncaught panic the process ends, so the OS gets the memory back and SQLite's journal keeps the file consistent. The guarantee must not promise more than the runtime does.
>
> **Q2: driver convention.** The compiler cannot check that a driver walks its map. A std helper would be a framework for a 6-line loop (YAGNI). The convention text should name the duty: "exit finalizes each open Stmt before it closes the connection."
>
> Cross-language: Go's `database/sql` does this sweep itself: `DB.Close` closes every tracked `Stmt`. Rust `rusqlite` keeps a statement cache in the Connection and flushes it in `Drop` before `sqlite3_close`. That is Proposal A.

- **Web/Scripting:**

> Web/Scripting Phase A: keep the guarantee, make exit sweep the raw statements through the native handle, and fix the "by panic" wording.
>
> **Seat view.** Almost every user only writes `with sqlite.connect(path)? { ... }`. They should never think about the sweep. The ticket only asks how a driver author gets the work done, and the answer should be "with the tools you already have". It should not need a new hook.
>
> ## Proposal W1 (preferred): exit sweeps native handles, not tokens
>
> - **Q0:** Yes, the spec needs a small change.
>   (a) The example's `exit` must actually do the sweep. Today it promises a sweep that the code does not do.
>   (b) "and by panic" contradicts the unwind table. An uncaught panic skips `exit()` and ends the process, so the OS frees everything. The guarantee should cover `?`, `return`, `break`, and a panic that a catch frame catches. An uncaught panic gets no sweep, and none is needed.
> - **Q1:** The sweep runs in `exit(self, ok)`, after the handler is uninstalled. It does not reach the `stmts` map. Instead, `exit` frees the raw statements through the connection's own native handle. The token map dies with the handler. No live handler can see a stale `Open(raw)` entry, because the handler is gone and E0601/E0602 keep its value inside the `with`.
> - **Q2:** This is a driver convention, the same as the 6-0 `connect` convention. There is no std rule and no compiler check. What the spec promises users is behavior: "after the `with` exits, no statement that the connection made is still open."
>
> For SQLite this is cheap. `sqlite3_next_stmt(db, NULL)` walks every prepared statement on a connection, and the SQLite docs show this exact loop before `sqlite3_close`:
>
> ```blink
> impl Scoped for Connection {
>     type Context = Handler[DB ! (FS.Read, FS.Write, FS.Delete, Time.Read, Time.Sleep, Rand, State)]
>
>     fn enter(self) -> Handler[DB ! (FS.Read, FS.Write, FS.Delete, Time.Read, Time.Sleep, Rand, State)] {
>         sqlite_handler(self.handle)
>     }
>
>     fn exit(self, ok: Bool) ! FS.Read, FS.Write, FS.Delete {
>         loop {
>             match sqlite_next_stmt(self.handle) {
>                 Some(raw) => sqlite_finalize(raw)
>                 None => break
>             }
>         }
>         sqlite_close(self.handle)
>     }
> }
> ```
>
> Some other driver might have no way to list its statements, or might have to send server-side DEALLOCATE calls. That author can build the shared cell in `connect` and keep a sweep closure in the value (see W2). Postgres and MySQL free server-side prepared statements when the session closes, so in practice most drivers need only the W1 shape.
>
> Tradeoffs:
> - (+) There is no new language feature, and the 90% user sees nothing. The driver code is about five lines that any JS or Python developer can read.
> - (+) It matches what users of other languages expect: closing the connection frees its statements.
> - (-) The sweep runs on native state, not the token map. If a driver gets this wrong, it leaks. The compiler does not check it, but the convention vote already accepted that.
>
> ## Proposal W2 (fallback, for completeness): shared cell built in `connect`
>
> `connect` declares `let mut stmts`. It builds the handler (`Handler[E]` can be stored) and a `sweep: fn() -> Void` closure, and both capture the same cell. `Connection` holds both: `enter` returns `self.db`, and `exit` calls `(self.sweep)()` and then closes. This works with today's rules (shared `let mut` capture, and "acquire before the block"). But it reads like a trick, and a Python developer would not guess it in 5 minutes. I would show it only as a footnote for drivers that cannot list their statements natively, and not in the main example.
>
> I reject a new `on_exit`/`finally` clause inside `handler { }`. That is a language feature added for one package. YAGNI.
>
> **Cross-language:** JDBC `Connection.close()` releases its Statements. Python's `sqlite3` `close()` and Node's better-sqlite3 `db.close()` free open statements. Go's `database/sql` tracks statements per DB and closes them. In each one the driver does the sweep from its connection object, and users never write it. That is the W1 shape.

- **PLT:**

> PLT Phase A: the language already lets the driver do this. The fix is to the example, plus one wording fix. No new feature.
>
> **Q0: yes, the spec needs two changes.**
> (a) The §4.7.2 example is unsound as written. `exit(self)` cannot reach `stmts`, so the guarantee in §4.4.10 has no witness. Worse, plain `sqlite3_close` returns BUSY while any statement is open, so the shown `sqlite_close` can leak the whole connection.
> (b) §4.4.10 says "and by panic". The §4.7.2 table says an uncaught panic outside a catch frame bypasses `exit()`. Both cannot hold. The guarantee should cover each catchable unwind (`?`, `return`, `break`, an assertion failure, `skip()`, a panic that `assert_panics` or a `for_each` case catches). A process that dies of an uncaught panic finalizes nothing, and the OS reclaims the memory. "By panic" must not promise more than the unwind rules give.
>
> **Q1, Proposal A (I support this).** Make the map in `connect`. Keep it in `Connection` and give the same cell to the handler. `Map` is a shared cell (§3.6), so a struct copy and a by-value `self` still name the map the handler writes. `exit` then runs the sweep from `self`, with the outer handlers in place, as §4.7.2 *Order* requires.
>
> ```blink
> pub type Connection {
>     handle: Sqlite3
>     stmts: Map[Stmt, Entry]
> }
>
> pub fn connect(path: Str) -> Result[Connection, DBError] ! FS.Read, FS.Write, FS.Delete {
>     let handle = sqlite_open(path)?
>     Ok(Connection { handle: handle, stmts: Map.new() })
> }
>
> impl Scoped for Connection {
>     type Context = Handler[DB ! (FS.Read, FS.Write, FS.Delete, Time.Read, Time.Sleep, Rand, State)]
>
>     fn enter(self) -> Handler[DB ! (FS.Read, FS.Write, FS.Delete, Time.Read, Time.Sleep, Rand, State)] {
>         sqlite_handler(self.handle, self.stmts)
>     }
>
>     fn exit(self, ok: Bool) ! FS.Read, FS.Write, FS.Delete {
>         let mut stmts = self.stmts    // a second name for the same cell
>         for (s, e) in stmts.entries() {
>             match e {
>                 Open(raw) => {
>                     sqlite_finalize(raw)
>                     stmts.insert(s, Entry.Finalized)
>                 }
>                 Finalized => {}
>             }
>         }
>         sqlite_close(self.handle)
>     }
> }
>
> fn sqlite_handler(handle: Sqlite3, mut stmts: Map[Stmt, Entry])
>     -> Handler[DB ! (FS.Read, FS.Write, FS.Delete, Time.Read, Time.Sleep, Rand, State)] {
>     handler DB {
>         // prepare, step and finalize exactly as now, on the shared `stmts`
>     }
> }
> ```
>
> The sweep marks each entry `Finalized`. It does not leave the entry `Open`. This matters because `Connection` is a plain copyable value: `let c = sqlite.connect(p)?` followed by `with c {}` twice runs two `exit`s on the same map. Without the mark, the second sweep double-frees a raw statement. That is UB, and fact 9 ("a second exit should do nothing") forbids it. Iterating `entries()` copies the pairs, so the inserts do not disturb the loop.
>
> Soundness: the handler made by `enter` cannot escape the `with` (E0601/E0602), and `sqlite_handler` is private. After `exit`, nothing can reach a `RawStmt` in the map, so the state "Open entry whose raw was freed" never appears. A kept `Stmt` reaches some other handler and gets "belongs to another connection", as the `late` example prints today.
>
> **Rejected alternatives**
> - B. Let `enter` hand state to `exit` (`exit(self, ctx, ok)`). This changes the `Scoped` trait for everyone. `ctx` is an opaque `Handler`, so `exit` still could not read the map. You would need handler state projection, a new feature.
> - C. A `finally` clause on `handler E { }` (Koka has `initially`/`finally`, and Eff-style handlers have finalisers). It is clean in theory. But it is a new construct with its own effect row, and it overlaps `Scoped.exit`. YAGNI, because A works with today's rules.
> - D. Make `sqlite_close` walk `sqlite3_next_stmt`, or use `sqlite3_close_v2`. This is driver-specific, the map entries stay stale, and it gives no pattern that other drivers can copy. A driver may still use it as a second line of defense.
>
> **Q2: driver convention, not a std rule.** The compiler cannot check "every resource released". The `connect`/`Scoped` shape is already a convention (6-0), so the sweep is part of that convention. The spec example is its reference shape. std adds nothing.
>
> **Tradeoffs (PLT seat).** A needs no new typing rule and reuses §3.6 shared cells and §4.7.2 order. The cost is subtle: correctness rests on aliasing through a by-value `self`, which readers can miss. The example should show it with the one comment above. Cross-language: this is OCaml's pattern of sharing a `ref` between a resource record and a closure. Haskell's `bracket` does the same with an `IORef` built at acquire time.

- **DevOps:**

> DevOps Phase A: Q0 yes. The spec promises a sweep that its own example cannot run. Fix it in the driver example, keep it a driver convention, and make the panic wording agree with the unwind table.
>
> **What is wrong today.** `exit(self)` gets only `Connection { handle }`. `stmts` lives inside `sqlite_handler`, and `enter()` cannot pass state to `exit()` (self is by value). A driver author who copies §4.7.2 ships a driver that leaks statements. With `sqlite3_close` the close then fails with SQLITE_BUSY, and nothing reports it. Copied examples become user code and training data, so a broken example is a bug in our own docs.
>
> **Proposal A (my pick): make the cell at connect time, share it through two closures.** Captures are shared cells (§2.8), so a sweep closure made in the same scope as the handler sees every write the clauses make. This needs no new feature, and the pattern works for any driver (Postgres, MySQL, a pool).
>
> ```blink
> pub type Connection {
>     handle: Sqlite3
>     db: Handler[DB ! (FS.Read, FS.Write, FS.Delete, Time.Read, Time.Sleep, Rand, State)]
>     sweep: fn() -> Void
> }
>
> pub fn connect(path: Str) -> Result[Connection, DBError] ! FS.Read, FS.Write, FS.Delete {
>     let handle = sqlite_open(path)?
>     let mut stmts: Map[Stmt, Entry] = Map.new()
>     let h = handler DB {
>         fn prepare(sql: Template[DB]) -> Result[Stmt, DBError] {
>             let raw = sqlite_prepare(handle, sql)?
>             let s = Stmt.new()
>             stmts.insert(s, Entry.Open(raw))
>             Ok(s)
>         }
>         // step, finalize, ... as today
>     }
>     let sweep = fn() {
>         for e in stmts.values() {
>             match e {
>                 Open(raw) => sqlite_finalize(raw)
>                 Finalized => {}
>             }
>         }
>     }
>     Ok(Connection { handle: handle, db: h, sweep: sweep })
> }
>
> impl Scoped for Connection {
>     type Context = Handler[DB ! (FS.Read, FS.Write, FS.Delete, Time.Read, Time.Sleep, Rand, State)]
>     fn enter(self) -> Handler[DB ! (FS.Read, FS.Write, FS.Delete, Time.Read, Time.Sleep, Rand, State)] {
>         self.db
>     }
>     fn exit(self, ok: Bool) ! FS.Read, FS.Write, FS.Delete {
>         let sweep = self.sweep
>         sweep()
>         sqlite_close(self.handle)
>     }
> }
> ```
>
> The user's code does not change: `with sqlite.connect(path)? { let s = db.prepare(q)? }` finalizes `s` in `exit`, then closes. This also follows the existing rule "hold the resource from construction".
>
> **Proposal B (SQLite only, I note it but reject it for the spec example): sweep from the handle.** `sqlite3_next_stmt(db, NULL)` walks every unfinalized statement on a connection, so `exit` can finalize all of them using `self.handle` alone. After exit the map still says `Open`, but nothing can see that: the handler is gone and E0601 stops it from escaping. B is fine inside the package. It is a bad teaching example because Postgres and most other client libraries have no such walk, so authors would copy a pattern that does not carry over.
>
> **Q2: driver convention, not a std rule.** The compiler cannot check "every open Stmt is finalized". There is no diagnostic we could give that does not flag false positives. The parts that users can observe are already std rules (the three Errs, idempotent `finalize`). Sweep-at-exit is a duty of the driver author, in the same group as "connect returns Result[Connection, DBError]" (6-0). If we want to enforce it, the tool is a driver conformance test, not a compiler check. I do not ask for that test now (YAGNI).
>
> **Wording fix, same ticket.** §4.4.10 says the sweep runs "by panic". The unwind table says an uncaught panic outside a catch frame skips `exit()` completely. Readers (and LSP hover text taken from the spec) will trust the stronger claim. It should say a panic that a catch frame catches; for an uncaught panic the process ends and the OS reclaims the memory. Two sections that disagree is the worst kind of doc bug for tooling users.
>
> **Tradeoffs from my seat.** A: an extra field and closure, but plain code, and go-to-definition from `exit` leads straight to the sweep. No hidden runtime hook, so a stack trace from a failing finalize shows `exit -> sweep`, which is easy to debug. Its cost: `Connection` now holds a Handler value. That is legal (it is stored, not bound by `with ... as`), but the example should say so in one line, or readers will think E0601 applies.
>
> **Cross-language.** Go `database/sql`: `DB.Close` closes the statements it tracks, from a registry kept on the conn. That is the same pattern as A. rusqlite: `Connection` owns a statement cache, and its `Drop` clears the cache before `sqlite3_close`. Same pattern again: the state lives on the value that close can reach.

- **AI/ML:**

> AI/ML Phase A: Q0 yes; the sweep runs in exit(self) and reaches the map through a shared cell that connect makes. No new language feature. It is a driver convention.
>
> **Why Q0 is yes.** The §4.7.2 example is the pattern that every LLM-written driver will copy. As it stands, the pattern cannot keep the §4.4.10 promise. exit(self) holds only `handle`, and `stmts` lives inside sqlite_handler. A model that copies it will write a driver that leaks statements, and with plain sqlite3_close that close fails with SQLITE_BUSY. An example that cannot meet its own spec teaches the wrong thing.
>
> **Proposal A (recommended): connect owns the cell, and two closures share it.** This uses only existing rules. A captured `let mut` is one shared cell (§2.8). A Handler and an fn value can each go in a field. Because `self` is copied by value, the copied fields still point at the same cell.
>
> ```blink
> pub type Connection {
>     handle: Sqlite3
>     db: Handler[DB ! (FS.Read, FS.Write, FS.Delete, Time.Read, Time.Sleep, Rand, State)]
>     sweep: fn() -> Void ! FS.Write
> }
>
> pub fn connect(path: Str) -> Result[Connection, DBError] ! FS.Read, FS.Write, FS.Delete {
>     let handle = sqlite_open(path)?
>     let mut stmts: Map[Stmt, Entry] = Map.new()
>     let db = handler DB {
>         // prepare / step / finalize exactly as now, reading and writing stmts
>     }
>     let sweep = fn() {
>         for (s, e) in stmts.entries() {
>             match e {
>                 Open(raw) => {
>                     sqlite_finalize(raw)
>                     stmts.insert(s, Entry.Finalized)
>                 }
>                 Finalized => {}
>             }
>         }
>     }
>     Ok(Connection { handle: handle, db: db, sweep: sweep })
> }
>
> impl Scoped for Connection {
>     type Context = Handler[DB ! (FS.Read, FS.Write, FS.Delete, Time.Read, Time.Sleep, Rand, State)]
>     fn enter(self) -> Handler[DB ! (FS.Read, FS.Write, FS.Delete, Time.Read, Time.Sleep, Rand, State)] {
>         self.db
>     }
>     fn exit(self, ok: Bool) ! FS.Read, FS.Write, FS.Delete {
>         (self.sweep)()
>         sqlite_close(self.handle)
>     }
> }
> ```
>
> What runs: `with sqlite.connect(p)? { let s = db.prepare(q)? }`. On exit, the sweep finalizes the raw statement of `s` and marks it Finalized, then the close succeeds. A Stmt that `finalize` already freed is Finalized, so the sweep skips it and does not free it twice. Nothing new compiles or errors. This also fits fact 4 ("holds its resource from construction"), and it puts the handler in the value, not in enter.
>
> Tradeoffs from my seat: (+) there is one obvious shape. The sweep and the close sit next to each other in exit(), where a reader (or model) looks for cleanup. (+) No new decision points or syntax. (−) The full example is longer by about 15 lines. That cost is worth paying, because a short example that leaks is worse. (−) The shared-cell trick is subtle. The example needs one sentence: "the handler and `sweep` capture the same `stmts`".
>
> **Rejected B: SQLite-only sweep in exit via sqlite3_next_stmt.** exit could walk the statements with only the handle (the FFI binding already sits in §7). It works for SQLite, but the map still holds dangling `Open(raw)` entries. Also, the trick does not carry over to other drivers. Models generalize from the reference driver, so that driver must show the general pattern.
>
> **Rejected C: an exit clause on the handler expression** (`handler DB { ... } on exit { }`, in the spirit of Koka `finally`). Forgetting the sweep becomes impossible, but it adds a second place where cleanup can live (handler clause vs Scoped.exit). That is a new choice that models will get wrong half the time. Minimalism will also object.
>
> **Q2.** It is part of the driver convention, next to the `connect` convention (6-0 already), and the compiler does not check it. §4.4.10 should state the promise as what a conforming driver does. It should not read as a std rule that holds by magic.
>
> **One more point the ticket exposes.** §4.4.10 says the sweep runs "by panic", but fact 2 says an uncaught panic outside a catch frame skips exit() entirely. The "by panic" clause should cover only a panic that a catch frame catches (assert_panics, a for_each case). Models learn guarantees literally, and an overstated one leads them to write code that relies on it.
>
> Cross-language: Go database/sql tracks its statements per connection and closes them on Conn.Close. Python sqlite3 finalizes cached statements on close(). Both keep the statement registry with the connection object, which is what A does.

- **Minimalism:**

> Minimalism Phase A: no language or std change; the connection's own C resource does the sweep, and the spec fixes one contradiction on panic.
>
> Proposal M1 (preferred): `exit(self)` sweeps through the connection handle, not the handler map. Driver convention, no new rule.
>
> Q0: Yes, but only a little. The spec promises a sweep it never shows, and its "and by panic" goes further than §4.7.2 allows (fact 2: an uncaught panic bypasses exit()).
> Q1: The sweep runs in `exit(self, ok)`. It reaches only `self`. That is enough, because the native library already keeps a list of its open statements. SQLite has `sqlite3_next_stmt(db, prev)`, which walks every unfinalized statement on a connection. `exit` walks that list, finalizes each one, and then closes. The `stmts` map stays as it is: it holds token ownership and the three Errs, and nothing at exit reads it.
> Q2: Driver convention, the same status as `connect`/`Connection: Scoped` (6-0 already). It is not a std rule, and it should not be one. The reason: after the `with` exits, Blink code cannot observe the sweep. E0601 stops the handler from escaping, so a kept `Stmt` can only reach another handler, and that handler gives "belongs to another connection" whether or not the sweep ran. The sweep is a promise about leaks, not about semantics. The compiler cannot check that kind of promise, so it belongs in the driver contract.
>
> ```blink
> impl Scoped for Connection {
>     type Context = Handler[DB ! (FS.Read, FS.Write, FS.Delete, Time.Read, Time.Sleep, Rand, State)]
>
>     fn enter(self) -> Handler[DB ! (FS.Read, FS.Write, FS.Delete, Time.Read, Time.Sleep, Rand, State)] {
>         sqlite_handler(self.handle)
>     }
>
>     fn exit(self, ok: Bool) ! FS.Read, FS.Write, FS.Delete {
>         finalize_open(self.handle)
>         sqlite_close(self.handle)
>     }
> }
>
> // sqlite_next_stmt wraps sqlite3_next_stmt(handle, NULL): the first statement
> // that is still open on this connection, or None
> fn finalize_open(handle: Sqlite3) {
>     loop {
>         match sqlite_next_stmt(handle) {
>             Some(raw) => sqlite_finalize(raw)
>             None => break
>         }
>     }
> }
> ```
>
> What the user sees:
> ```blink
> with sqlite.connect(path)? {
>     let s = db.prepare(t"SELECT 1")?
>     let t = db.prepare(t"SELECT 2")?
>     t.finalize()?
> }   // exit: finalize_open frees s; t is not on SQLite's list, so it is not freed twice
> ```
> "Does not finalize again" comes for free, because a finalized raw statement has left the native list. No double-free logic is necessary.
>
> Panic: the exit path runs on `?`, `return`, `break`, and on a panic that `assert_panics`/`for_each` catches. On an uncaught panic, no Blink code runs. The process ends and the OS takes back the memory. Fact 1 must say that. Do not invent a panic path only for the DB.
>
> Tradeoffs (my seat):
> - Zero new surface: no `finally` clause on handlers, no hook that gives `exit` the handler, no shared-cell field in `Connection`.
> - The guarantee lives where the resource lives. The native connection owns its statements, so the native connection releases them. The map duplicates that list for the Blink side only.
> - Cost: a driver whose library has no "list my statements" call must track raw statements itself. It has two plain options. (a) `connect` makes a native-side registry that `Connection` holds by handle (the same trick as `Sqlite3`). (b) Closing the session frees them server-side (Postgres: a named prepared statement lives for the session; closing the socket drops it). Neither needs language help.
> - Risk: if a driver author forgets the sweep, the result is a leak, not wrong answers. The spec example should show the sweep so that authors copy it.
>
> Rejected, M2 (put `stmts` in `Connection` as a shared cell, so that `exit(self)` reads it): this needs a mutable shared field through a by-value `self`. That reopens "enter cannot hand state to exit" (fact 4) to solve something the C library already solves.
> Rejected, M3 (new language hook: a handler `on_exit`/finally clause, or `exit` gets the installed handler): new syntax for one driver pattern. YAGNI until a second, non-DB case asks for it.
>
> Cross-language: Python's sqlite3 `Connection.close()` and Go's `database/sql` both rely on the native or driver layer to release statements. Go's `DB.Close` closes the statements that the driver tracks; neither language adds a language feature for it. Rust rusqlite's `Connection` drop finalizes its statement cache through the handle in the same way.

#### Phase B — Round 1

The moderator put the option space to the panel (below, as sent), and asked for a position on two open points: N, F or C for the spec example, and whether the sweep marks each entry `Finalized`.


> Phase B, round 1: the deduped option space for "How does a DB driver's exit sweep reach the Stmt map that its handler captures?"
>
> All six Phase A proposals are below as options, with each proposer's own snippet. Reply to team-lead with your position on the open points. Say "stable, ready to vote" when you are.
>
> ## Points with no disagreement in Phase A (not on the ballot unless someone objects)
>
> - Q0: yes, the spec changes. All six.
> - Q2: the sweep is a driver convention, next to the `connect`/`Scoped` convention. Not a std rule, no compiler check. All six.
> - No new language construct (no handler `finally`/`on_exit` clause, no `exit(self, ctx, ok)`). All six rejected these.
> - Panic wording: all six say §4.4.10 "and by panic" must cover only a panic that a catch frame catches (`assert_panics`, a `for_each` case); an uncaught panic skips `exit()`. Every proposal gives the same behavior, so this goes to the writer notes.
>
> ## Q1: how does `exit` reach the open raw statements?
>
> ### Option N: walk the native library's list through the handle (Minimalism M1, Web W1)
>
> Minimalism:
> ```blink
> impl Scoped for Connection {
>     type Context = Handler[DB ! (FS.Read, FS.Write, FS.Delete, Time.Read, Time.Sleep, Rand, State)]
>
>     fn enter(self) -> Handler[DB ! (FS.Read, FS.Write, FS.Delete, Time.Read, Time.Sleep, Rand, State)] {
>         sqlite_handler(self.handle)
>     }
>
>     fn exit(self, ok: Bool) ! FS.Read, FS.Write, FS.Delete {
>         finalize_open(self.handle)
>         sqlite_close(self.handle)
>     }
> }
>
> // sqlite_next_stmt wraps sqlite3_next_stmt(handle, NULL): the first statement
> // that is still open on this connection, or None
> fn finalize_open(handle: Sqlite3) {
>     loop {
>         match sqlite_next_stmt(handle) {
>             Some(raw) => sqlite_finalize(raw)
>             None => break
>         }
>     }
> }
> ```
> Minimalism: "\"Does not finalize again\" comes for free, because a finalized raw statement has left the native list. No double-free logic is necessary."
> Minimalism: "Cost: a driver whose library has no \"list my statements\" call must track raw statements itself. It has two plain options. (a) `connect` makes a native-side registry that `Connection` holds by handle (the same trick as `Sqlite3`). (b) Closing the session frees them server-side (Postgres: a named prepared statement lives for the session; closing the socket drops it). Neither needs language help."
> Web: "Some other driver might have no way to list its statements, or might have to send server-side DEALLOCATE calls. That author can build the shared cell in `connect` and keep a sweep closure in the value (see W2). Postgres and MySQL free server-side prepared statements when the session closes, so in practice most drivers need only the W1 shape."
>
> ### Option F: the map is a field of `Connection`, made in `connect` (Systems A, PLT A)
>
> Systems:
> ```blink
> pub type Connection {
>     handle: Sqlite3
>     stmts: Map[Stmt, Entry]
> }
>
> pub fn connect(path: Str) -> Result[Connection, DBError] ! FS.Read, FS.Write, FS.Delete {
>     let handle = sqlite_open(path)?
>     Ok(Connection { handle: handle, stmts: Map.new() })
> }
>
> impl Scoped for Connection {
>     type Context = Handler[DB ! (FS.Read, FS.Write, FS.Delete, Time.Read, Time.Sleep, Rand, State)]
>
>     fn enter(self) -> Handler[DB ! (FS.Read, FS.Write, FS.Delete, Time.Read, Time.Sleep, Rand, State)] {
>         sqlite_handler(self.handle, self.stmts)
>     }
>
>     fn exit(self, ok: Bool) ! FS.Read, FS.Write, FS.Delete {
>         for entry in self.stmts.values() {
>             match entry {
>                 Open(raw) => sqlite_finalize(raw)
>                 Finalized => {}
>             }
>         }
>         sqlite_close(self.handle)
>     }
> }
>
> fn sqlite_handler(handle: Sqlite3, mut stmts: Map[Stmt, Entry])
>     -> Handler[DB ! (FS.Read, FS.Write, FS.Delete, Time.Read, Time.Sleep, Rand, State)] {
>     handler DB {
>         // clauses unchanged: prepare inserts Open(raw), finalize sets Finalized
>     }
> }
> ```
> PLT's `exit` (same shape, but it marks entries):
> ```blink
>     fn exit(self, ok: Bool) ! FS.Read, FS.Write, FS.Delete {
>         let mut stmts = self.stmts    // a second name for the same cell
>         for (s, e) in stmts.entries() {
>             match e {
>                 Open(raw) => {
>                     sqlite_finalize(raw)
>                     stmts.insert(s, Entry.Finalized)
>                 }
>                 Finalized => {}
>             }
>         }
>         sqlite_close(self.handle)
>     }
> ```
> Systems: "Cost I want on record: Finalized tombstones never leave the map. A server that holds one connection for hours and prepares a statement per request grows the map, and the exit walk, without bound."
>
> ### Option C: `connect` builds the handler and a sweep closure over one `let mut` cell; `Connection` stores both (DevOps A, AI/ML A, Web W2 as a fallback footnote)
>
> AI/ML:
> ```blink
> pub type Connection {
>     handle: Sqlite3
>     db: Handler[DB ! (FS.Read, FS.Write, FS.Delete, Time.Read, Time.Sleep, Rand, State)]
>     sweep: fn() -> Void ! FS.Write
> }
>
> pub fn connect(path: Str) -> Result[Connection, DBError] ! FS.Read, FS.Write, FS.Delete {
>     let handle = sqlite_open(path)?
>     let mut stmts: Map[Stmt, Entry] = Map.new()
>     let db = handler DB {
>         // prepare / step / finalize exactly as now, reading and writing stmts
>     }
>     let sweep = fn() {
>         for (s, e) in stmts.entries() {
>             match e {
>                 Open(raw) => {
>                     sqlite_finalize(raw)
>                     stmts.insert(s, Entry.Finalized)
>                 }
>                 Finalized => {}
>             }
>         }
>     }
>     Ok(Connection { handle: handle, db: db, sweep: sweep })
> }
>
> impl Scoped for Connection {
>     type Context = Handler[DB ! (FS.Read, FS.Write, FS.Delete, Time.Read, Time.Sleep, Rand, State)]
>     fn enter(self) -> Handler[DB ! (FS.Read, FS.Write, FS.Delete, Time.Read, Time.Sleep, Rand, State)] {
>         self.db
>     }
>     fn exit(self, ok: Bool) ! FS.Read, FS.Write, FS.Delete {
>         (self.sweep)()
>         sqlite_close(self.handle)
>     }
> }
> ```
> DevOps's sweep does not mark entries (`for e in stmts.values() { match e { Open(raw) => sqlite_finalize(raw)  Finalized => {} } }`) and its field is `sweep: fn() -> Void`.
> DevOps: "Its cost: `Connection` now holds a Handler value. That is legal (it is stored, not bound by `with ... as`), but the example should say so in one line, or readers will think E0601 applies."
> Web (on W2): "it reads like a trick, and a Python developer would not guess it in 5 minutes."
>
> ## Arguments each side made against the others (verbatim)
>
> Against N:
> - Systems: "it holds only for C libraries that track their children, and it hides why the map exists. A driver may use it as an implementation choice. The spec should not teach it."
> - DevOps: "It is a bad teaching example because Postgres and most other client libraries have no such walk, so authors would copy a pattern that does not carry over."
> - AI/ML: "the map still holds dangling `Open(raw)` entries. Also, the trick does not carry over to other drivers. Models generalize from the reference driver, so that driver must show the general pattern."
> - PLT: "This is driver-specific, the map entries stay stale, and it gives no pattern that other drivers can copy. A driver may still use it as a second line of defense."
>
> Against F:
> - Minimalism (M2): "this needs a mutable shared field through a by-value `self`. That reopens \"enter cannot hand state to exit\" (fact 4) to solve something the C library already solves."
>
> Against C:
> - Web (W2): quoted above.
>
> ## Variation to debate: does the sweep mark each entry Finalized?
>
> - Marks: PLT (F), AI/ML (C).
> - Does not mark: Systems (F), DevOps (C). Systems: "exit does not need to mutate the map."
> - PLT: "This matters because `Connection` is a plain copyable value: `let c = sqlite.connect(p)?` followed by `with c {}` twice runs two `exit`s on the same map. Without the mark, the second sweep double-frees a raw statement. That is UB, and fact 9 (\"a second exit should do nothing\") forbids it."
> - Minimalism (N): a finalized raw statement leaves the native list, so N needs no mark.
>
> ## Facts from the codebase (facts only)
>
> - `sections/07_trust_modules_metadata.md` ~line 1302 shows `@ffi("sqlite3", "sqlite3_next_stmt")` only as an example of a legal `@ffi` signature (`fn raw_next(db: Sqlite3) -> Option[Sqlite3] ! ()`). `lib/std/db_sqlite.bl` has no binding for `sqlite3_next_stmt` today.
>
> ## Open points for this round
>
> 1. N vs F vs C for the spec example. If you think F and C are one option, say so.
> 2. Mark Finalized or not.

All six moved to F with the mark in round 1. Minimalism withdrew its M2 objection (that F reopens "enter cannot hand state to exit"). DevOps and AI/ML left C. Web and Minimalism left N. Systems and DevOps took the mark. Web's reply reached the moderator after the debate closed, and it is quoted here with the others.


- **Systems:**

> Systems B1: I pick F for the example and now accept marking each swept entry Finalized. Stable, ready to vote.
>
> **Point 1: F, not C, not N.**
> - F and C use the same mechanism: `connect` builds one shared cell and both the handler and `exit` reach it. They differ only in how much they wrap around it. F keeps the map as plain data. C adds a stored `Handler` field and a closure field with its own effect row, plus a line of text to explain why E0601 does not apply. That cost buys nothing. If the panel treats F and C as one option, I vote for the F form of it.
> - To Minimalism's point against F: fact 4 says `enter` cannot hand *new* state to `exit`. The same paragraph tells the reader to hold the resource "from construction". The map is made in `connect`, so F is that rule applied, not a reopening of it. Mutation through a copy of a `Map` is §3.6 *Shared cells* behavior that already exists; nothing new is needed.
> - N stays legal for a driver whose C library can list its statements. It should not be the reference example, because most client libraries have no such call and models copy the reference driver. It also leaves stale `Open` entries for any later handler on the same map.
>
> **Point 2: mark them. I change my position.** PLT is right. `Connection` is a plain copyable value, so `with c {}` twice runs two sweeps over one map. Without the mark, the second sweep calls `sqlite_finalize` on a freed raw statement, and that is undefined behavior. The mark costs one map write per open statement, a cost the hardware never notices. Use PLT's `exit` (`let mut stmts = self.stmts` and then `insert(s, Entry.Finalized)`). Do not clear the map: the tombstone keeps "statement is finalized" correct if a second `with c` installs a handler over the same map.
>
> **Writer note, not on the ballot.** The same double-`with` case also calls `sqlite_close(self.handle)` twice. That is undefined behavior too, and marking does not fix it. The example should guard the close as well, or say that a second `with` on one `Connection` gives a defined error (fact 9). I would flag this to the writer rather than widen the ballot.
>
> The unbounded tombstone growth I raised in Phase A still stands. I will log it as friction, separate from this ticket.

- **Web/Scripting:**

> Web B1 position: I move from N to F for the spec example, and the sweep should mark entries Finalized. I am stable and ready to vote.
>
> **Point 1: N vs F vs C. I pick F, then C, then N.**
>
> I checked §3.6 *Shared cells* (sections/03_types.md ~line 1449, the "Shared cells" paragraph). `Map` is on the list. When you copy a struct, a field that holds a `Map` still refers to the same cell. So in F, `self.stmts` in `exit` and the `stmts` param inside the handler are one map, and F works with today's rules exactly as written. This also answers Minimalism's M2 objection. F does not need `enter` to hand state to `exit`: `connect` makes the map, which is "acquire before the block" (fact 4), and the shared-cell rule does the rest. It needs no new rule.
>
> Why F wins from my seat: "the connection object holds a dict of its open statements, and close walks it" is what a Python or JS developer would guess in 5 minutes, and it is how JDBC and Go's `database/sql` work. C uses the same shared-cell mechanism, but it hides it behind a stored `Handler` value and a closure field, and a reader then has to ask why E0601 does not apply. F and C are one mechanism, and F is the plain spelling. I drop my W2 (that is C) in favor of F.
>
> N: the arguments against it convinced me. It does not carry over to Postgres-style libraries, and the reference driver is what authors and models copy. N stays a legal choice for a driver, so the spec need not show it. I am not voting for it as the example.
>
> **Point 2: yes, mark Finalized.**
>
> PLT's case holds once you know `Map` is shared. `Connection` is a copyable value, so `with c {}` twice, or a copy `c2` of `c`, runs two `exit`s on the same map. Without the mark, the second sweep finalizes the same raw statement twice, and that is UB. The mark costs one line and makes the sweep do nothing the second time (fact 9).
>
> Writer note, not a ballot item: the same double-`exit` also runs `sqlite_close` twice on one handle. The mark does not fix that. The example's `exit` should guard the close too, for example with a `closed` flag kept in a shared cell made in `connect`. If the panel thinks that is out of scope, it should be its own ticket, and it applies to every option, N included.
>
> On Systems' growth cost (Finalized tombstones are never removed): it is real, but it is the same in every option and it is not this ticket's question. Suggest a separate friction ticket.
>
> Stable, ready to vote.

- **PLT:**

> PLT, Phase B round 1.
>
> **Point 1: I pick F. C has the same semantics. N should not be the spec example.**
>
> - F and C share one mechanism. A shared cell is built at construction, and `exit` reaches it through by-value `self`. They differ only in where the clauses sit. C makes the reader reason about two more things: a `Handler` value stored in a struct, and a closure field. It also tempts readers to think E0601 applies. F keeps `enter` as the place that builds the handler, as the current text does. If the panel prefers C, I count it as the same vote, but F is the cleaner example.
> - On Minimalism's objection to F: F does not reopen fact 4. Fact 4 says `enter` cannot hand new state to `exit`, so a scoped handler "holds its resource from construction". F does exactly that. The map is made in `connect`, before `enter`. `enter` only passes on a cell that already exists. F needs no new rule. It applies §3.6 (a `Map` field stays shared after a struct copy).
> - On N: a driver can do this inside its own code. As the spec's reference shape it is wrong. It works only for one C API, and it leaves `Open(raw)` entries that point at freed memory. N also does not make a second `exit` safe: `sqlite_next_stmt` on a closed handle is a use-after-free. See point 2.
> - On Systems' tombstone growth: it is real, but F does not cause it. The stmt panel voted for "a later op on a finalized Stmt gives `statement is finalized`, not `belongs to another connection`". That distinction needs the tombstone. Every option that keeps the map has the same growth. If the panel wants it bounded, that is a separate ticket on the stmt-db decision.
>
> **Point 2: mark Finalized. It is necessary, but it is not sufficient.**
>
> - Without the mark, `let c = sqlite.connect(p)?`, then `with c {}`, then `with c {}`, makes the second sweep call `sqlite_finalize` again on raw statements it already freed. That is UB in a safe-looking program.
> - A correction to my own Phase A claim: the mark alone does not make the second `exit` do nothing. Every option, N included, then calls `sqlite_close(self.handle)` a second time, and that is a double free. The second `with c` also installs a handler over a closed handle. That case is the "connection is closed" Err in fact 8. So the driver must already track that the connection is closed. The example should show it once, for example as a `closed` entry in the same shared state, or as a guard in `sqlite_close`, and both `exit` and the clauses should check it. Writer note: the reference example must not double-free under the two-`with` program. How it shows the closed state is a wording choice, not a ballot item.
>
> **Stable, ready to vote:** F (C counts as equivalent if the panel splits), mark Finalized, plus the closed-guard writer note.

- **DevOps:**

> DevOps B1: I move from C to F, and I vote to mark each entry Finalized. Stable, ready to vote.
>
> **Point 1: F for the spec example. F and C are not one option, and F beats my own C.**
>
> I missed one fact in Phase A. §3.6 *Shared cells* (03_types.md ~6368) lists `Map` as a shared cell: "A field whose value is a shared cell refers to the same cell after the copy." So the `Map` field in a by-value `self` refers to the same map that the handler's clauses write. The closure in C is only a detour to a shared cell that we already have. Without it:
> - no Handler value or fn value in a struct field, and no line telling readers that E0601 does not apply to a stored handler;
> - no `(self.sweep)()` call syntax that readers must think about;
> - one plain shape that a Go `database/sql` or rusqlite reader already knows (the registry lives on the conn, and close walks it);
> - go-to-definition from `exit` leads to the field, and a stack trace from a failing finalize reads `exit -> sqlite_finalize`.
>
> Answer to Minimalism's M2: F does not reopen fact 4. Fact 4 says `enter()` cannot hand NEW state to `exit()`, and that a scoped handler "therefore holds its resource from construction". F does just that: `connect` makes the map. The writer should cite §3.6 *Shared cells* next to the example so that nobody reads `self.stmts` in `exit` as a stale copy. That one cross-reference is the whole teaching cost.
>
> C stays legal for a driver that wants the map private to closures. N stays legal as an internal choice (or a second line of defense) for a C library that lists its children. Neither belongs in the reference example, for the reasons all four of us gave against N. One more fact against N as the example: `lib/std/db_sqlite.bl` has no `sqlite3_next_stmt` binding today.
>
> **Point 2: mark Finalized. Use PLT's exit.**
>
> PLT is right. `Connection` is a copyable value, so `with c {}` twice runs two exits over one shared map. Without the mark, the second sweep double-frees a raw statement. That is UB that no diagnostic or test reports, and it is the worst kind of bug to debug. The mark costs one `insert`.
>
> Two notes for the writer. They are not new ballot items:
> 1. The mark alone does not make a second exit safe. That exit also calls `sqlite_close` on a closed handle, and a second `enter` hands out a handler over a closed handle. Fact 9 asks a second exit to "do nothing or fail with a defined error". The example should either keep a closed flag (a one-entry shared cell, or a `closed` entry the driver checks), or state that a Connection is used for one `with`. I suggest a friction ticket for "what does `with c` twice do for a driver Connection", rather than widening this ticket.
> 2. Systems' point about tombstones that grow without bound is real. But the decided Err semantics need them: a finalized token must give "statement is finalized", not "belongs to another connection", so the entry cannot leave the map. The cost is one small entry per prepare for the life of the connection. The writer can say so in one line. I do not want to reopen the decided Errs to remove it.

- **AI/ML:**

> AI/ML round 1: I move from C to F, the sweep marks entries Finalized, and I am stable, ready to vote.
>
> 1. N vs F vs C: I rank F > C > N, and I now prefer F to my own C.
> - F and C are one mechanism: one Map cell that both the handler and exit reach. They differ only in how exit gets to that cell. In F the map sits in a field. In C it sits in a captured `let mut` behind a closure field. §3.6 says collections are shared cells (sections/03_types.md ~692), so `self.stmts` in exit is the same map that the handler writes. F therefore works with no closure trick.
> - From my seat, F wins on learnability. The owner of the map is visible in the `Connection` type. A reader or a model sees `stmts` in the struct, in enter and in exit, all three places. C needs a stored Handler (which invites a wrong E0601 guess, as DevOps said) and a capture subtlety (as Web said). F has fewer parts that a model must get right.
> - F needs one line in the example: "`Map` is a shared cell, so `exit` sees what the handler wrote." Without that line, models trained on value-semantics languages will think the field is a stale copy.
> - Minimalism's objection does not hold. F does not have enter hand state to exit. The cell exists from construction, which is the shape fact 4 itself prescribes.
> - N: it can be a driver's private second line of defense, but it is a bad reference example. The fact block confirms that std has no `sqlite3_next_stmt` binding, and the pattern does not carry over to other drivers.
>
> 2. Mark Finalized: yes, use PLT's exit (`let mut stmts = self.stmts`, then insert `Entry.Finalized`). `Connection` is a copyable value, so `with c {}` twice runs two exits on one map. Without the mark, the second exit double-frees, which is UB, and fact 9 asks that a second exit do nothing. The mark also keeps one rule true everywhere: an entry that is not Open is never freed again. A model can learn that one invariant, so it does not need to reason about exit order.
>
> Side note, not for this ballot: Systems' point about tombstones that never leave the map comes from explicit `finalize`, not from the sweep. If the panel agrees, log it as a separate ticket.

- **Minimalism:**

> Minimalism, round 1: I move from N to F, and I take back my M2 objection. F, with the sweep marking each entry Finalized. Stable, ready to vote.
>
> Why I take back M2: I said F "reopens fact 4" (enter cannot hand state to exit). That was wrong. §3.6 *Shared cells* (03_types.md ~6368) lists Map as a shared cell, so a struct copy shares it, and `self` by value still names the same map. In F, `connect` makes the map before `enter`, so `enter` hands nothing to `exit`. That is exactly the "hold the resource from construction" rule that fact 4 states. F uses only rules the spec already has. Nothing new.
>
> 1. N vs F vs C
> - F. It is the smallest option that is correct for every driver: one field, the clauses unchanged, a plain loop in `exit`.
> - N: I drop it as the spec example. The others are right that it teaches a SQLite-only trick, and the codebase fact makes it worse: there is no `sqlite3_next_stmt` binding today, so the example would need a new FFI binding just to show it. A driver may still use N as an implementation choice. The spec need not say so.
> - C is not the same as F, and it is strictly larger. It stores a `Handler` value and a closure in `Connection`, and it needs an extra line to explain why E0601 does not apply. Each of those costs F avoids. C buys nothing that F lacks, so I vote against C.
>
> 2. Mark Finalized: yes, mark.
> - PLT is right that `Connection` is copyable, so `with c {}` twice runs two exits over one shared map. Without the mark, the second sweep finalizes the same raw statement twice. The mark is one line and makes the second sweep do nothing.
> - A note for the writer, outside this ballot: the mark does not make a second exit fully safe, because `sqlite_close(self.handle)` still runs twice on a closed handle. Fact 9 only gives guidance there, but the reference driver should not show a double-close. I suggest a separate chore or friction ticket: either the example guards the close (the handle records that it is closed), or the spec says a driver `Connection` is single-use. Do not widen this ballot for it.
> - Systems' tombstone growth is real, but it follows from the decided "finalized stays in the map, gives 'statement is finalized'" rule, not from this ticket. If it matters, it needs its own ticket. It does not change my vote.

#### Phase C — Final vote

Five of six panelists sent "stable, ready to vote" in round 1, so the debate closed. The vote was silent. Each panelist read the round 1 replies and voted on Q1 (N, F or C) and Q2 (mark or no mark).

| Question | Result |
|----------|--------|
| Q1 | F, 6-0 |
| Q2 | Mark, 6-0 |


- **Systems:**

> **Q1: F**
> Reasoning: F puts the state the sweep needs in the `Connection` type, as one `Map` field made in `connect`. What the hardware does is visible: a hash map, one walk over it at exit, then the close. C reaches the same shared cell through a stored `Handler` and a closure field. That adds an indirect call and a line about E0601, and buys nothing. N fits only C libraries that list their statements, std has no `sqlite3_next_stmt` binding today, and N leaves `Open` entries that point at freed memory.
> Concern: a reader trained on value semantics may read `self.stmts` in `exit` as a stale copy and "fix" it with a `clone()`, so the sweep would see nothing. The §3.6 citation next to the example must stay.
> **Q2: Mark**
> Reasoning: `Connection` is copyable, so `with c {}` twice runs two sweeps over one map. Without the mark, the second sweep frees each raw statement again, and that is undefined behavior in a program that looks safe. The mark costs one map write per open statement at exit, which the hardware will never notice. It also keeps one simple rule true: an entry that is not `Open` is never freed again.
> Concern: the mark covers only the statements. The second `sqlite_close` on the same handle is still a double free, so the closed-guard writer note must be met, or the example ships UB anyway.

- **Web/Scripting:**

> **Q1: F**
> Reasoning: Under §3.6 *Shared cells*, `Map` is a shared cell, so a `stmts` field on `Connection` is the same map that the handler writes. `exit` can walk it with no closure and no stored handler. "The connection holds a dict of its open statements, and close walks it" is what a Python or JS developer would guess in 5 minutes, and it is how JDBC and Go's `database/sql` work. C uses the same mechanism behind more parts, and N teaches a SQLite-only trick that other drivers cannot copy.
> Concern: A reader who knows only value semantics will take `self.stmts` in `exit` for a stale empty copy. Without the §3.6 citation right next to the example, they will "fix" it by copying the map somewhere else.
> **Q2: Mark**
> Reasoning: `Connection` is copyable, so `with c {}` twice runs two sweeps over one map. Without the mark, the second sweep finalizes the same raw statement again, which is UB in a program that looks safe. The mark is one line and makes the second sweep do nothing (fact 9).
> Concern: The mark makes the sweep safe to run twice but not `sqlite_close`. If the writer leaves out the closed guard, the reference example still double-frees the handle under the two-`with` program.

- **PLT:**

> **Q1: F**
> Reasoning: F uses only rules the spec already has. §3.6 makes a `Map` field a shared cell across the by-value `self`. Fact 4 says to hold the resource from construction, and the map is made in `connect`. F needs no new typing rule and stores no `Handler` or fn value. C has the same semantics but adds parts the reader must reason through. N is sound only for one C API, and it leaves `Open(raw)` entries that point at freed memory.
> Concern: correctness rests on aliasing through a value copy. A reader or model who misses the §3.6 citation will "fix" the example by copying the map, and the sweep will then see nothing.
> **Q2: Mark**
> Reasoning: `Connection` is copyable, so two `with c {}` blocks run two sweeps over one cell. Without the mark, the second sweep is a double free in a program with no `@trusted` code at the use site. With the mark, one invariant holds in every path: an entry that is not `Open` is never freed again. That invariant is what makes the sweep idempotent.
> Concern: the mark covers the statements only. Until the writer adds the closed-handle guard, the second `sqlite_close` is still UB.

- **DevOps:**

> **Q1: F**
> Reasoning: `Map` is a shared cell (§3.6), so `self.stmts` in a by-value `exit` is the same map that the handler writes. Nothing new is needed. F is the shape Go's `database/sql` and rusqlite users already know: the registry lives on the conn, and close walks it. Go-to-definition and stack traces stay plain (`exit -> sqlite_finalize`). C adds a stored Handler and a closure field for no gain. N teaches a trick that only SQLite supports, and std has no binding for it.
> Concern: a reader who expects value semantics will read `self.stmts` in `exit` as a stale copy, unless the example cites §3.6 *Shared cells* next to it.
> **Q2: Mark**
> Reasoning: `Connection` is copyable, so `with c {}` twice runs two sweeps over one map. Without the mark, the second sweep frees the same raw statement twice. That is undefined behavior that no diagnostic or test reports, and the mark costs one `insert`.
> Concern: readers will take the mark as making a second `exit` safe, but the second `sqlite_close` is still a double free. The writer must guard the close in the example, or the reference driver ships undefined behavior.

- **AI/ML:**

> **Q1: F**
> Reasoning: F gives the one plain shape that models already know from Go database/sql and rusqlite: the statement registry is a field on the connection, and close walks it. Readers see the map in the type, in enter and in exit, with no stored Handler, no closure field, no `(self.sweep)()` call, and no false E0601 doubt. C (my own Phase A pick) is a detour to a shared cell that §3.6 already gives us. N teaches a SQLite-only trick that needs an FFI binding std does not have.
> Concern: models trained on value-semantics languages will read `self.stmts` in exit as a stale copy unless the §3.6 *Shared cells* note sits right next to the example.
> **Q2: Mark**
> Reasoning: `Connection` is copyable, so `with c {}` twice runs two sweeps over one map. Without the mark, the second sweep double-frees, which is silent UB. The mark keeps one invariant that a model can learn: an entry that is not Open is never freed again. That is cheaper to learn than reasoning about how many exits ran.
> Concern: the mark covers only half of the double-exit case. If the example does not also guard the second `sqlite_close` (writer note), models will copy a reference driver that still double-closes and believe it is safe.

- **Minimalism:**

> **Q1: F**
> Reasoning: F adds the least. It is one field and a plain loop, and it reuses two rules the spec already has: §3.6 says a Map field stays shared after a copy, and fact 4 says a scoped handler holds its resource from construction. C reaches the same cell but adds a stored Handler, a closure field and an E0601 explanation, and buys nothing for them. N is the smallest only for SQLite. It needs an FFI binding that does not exist, and other drivers cannot copy it.
> Concern: a reader from a value-semantics language reads `self.stmts` in `exit` as a stale copy, unless the §3.6 cite sits right next to the example.
> **Q2: Mark**
> Reasoning: `Connection` can be copied, so `with c {}` twice runs two sweeps over one map. Without the mark, the second sweep double-frees a raw statement, which is silent UB. The mark is one `insert` and makes the second sweep do nothing.
> Concern: the mark can give false comfort, because the second `sqlite_close` is still a double free; the writer note on the closed state must not get dropped.

### Final Spec

```blink
pub type Connection {
    handle: Sqlite3
    stmts: Map[Stmt, Entry]
    closed: List[Bool]
}

pub fn connect(path: Str) -> Result[Connection, DBError] ! FS.Read, FS.Write, FS.Delete {
    let handle = sqlite_open(path)?
    Ok(Connection { handle: handle, stmts: Map.new(), closed: List.new() })
}

impl Scoped for Connection {
    fn enter(self) -> Handler[DB ! (FS.Read, FS.Write, FS.Delete, Time.Read, Time.Sleep, Rand, State)] {
        sqlite_handler(self.handle, self.stmts, self.closed)
    }

    fn exit(self, ok: Bool) ! FS.Read, FS.Write, FS.Delete {
        let mut stmts = self.stmts    // a second name for the same cell
        for (s, e) in stmts.entries() {
            match e {
                Open(raw) => {
                    sqlite_finalize(raw)
                    stmts.insert(s, Entry.Finalized)
                }
                Finalized => {}
            }
        }
        if self.closed.is_empty() {
            sqlite_close(self.handle)
            let mut closed = self.closed
            closed.push(true)
        }
    }
}
```

- **Q0 (6-0):** yes, the spec changes. No new language construct.
- **Q1 (F, 6-0):** `Connection` has a field `stmts: Map[Stmt, Entry]`, made in `connect`. `enter` passes `self.stmts` to `sqlite_handler`, which no longer makes the map. `exit` sweeps the map, then closes. `Map` is a shared cell (§3.6 *Shared cells*), so `self.stmts` in `exit` is the map that the handler writes.
- **Q2 (Mark, 6-0):** the sweep finalizes each `Open(raw)` and writes `Entry.Finalized` for it. A second sweep over the same map finalizes nothing.
- **Sweep before close, and a closed state (writer note, from the panel concerns):** the sweep runs before the close. The mark covers the statements only. A second `exit()` on a copied `Connection` would close the handle again, so `connect` makes a `closed` cell, `exit` checks it before it closes, and `prepare` and `step` give `Err(ConnectionError("connection is closed"))` when it is set. The example uses only existing rules: a `List[Bool]` is a shared cell.
- **Panic wording:** the sweep runs when the `with` exits by `?`, `return`, `break`, or a panic that a catch frame catches (`assert_panics`, a `for_each` case). An uncaught panic skips `exit()`, the process ends, and the OS gets the memory back.
- **Driver convention:** the sweep is a convention for driver packages, next to `connect` and `Scoped`. It is not a std rule and the compiler does not check it.
- **Acquire before the block:** the map is made in `connect`, before `enter()`, so `enter()` hands nothing new to `exit()`.
- **Cost:** a finalized entry stays in the map for the life of the connection, because the "statement is finalized" Err needs it. The map grows by one entry per `prepare`.
- **Out of scope:** which Err wins for `finalize` of a swept `Stmt` after the connection closed ("closed" or "finalized"). That is a separate question.
